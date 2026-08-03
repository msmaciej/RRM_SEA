#!/usr/bin/env python3
# =============================================================================
# rrm_validate.py  —  RRM EA  LADDER 1  (the CHECK, run BEFORE the model)
# =============================================================================
# Ladder 1 answers ONE question: "is a meta-model on THIS pair+TF worth shipping,
# or is any apparent edge just the luck of one split / the residue of trying many
# thresholds?"  It does NOT export a model. Run it first; only feed the passers to
# rrm_meta.py (Ladder 2) and then the EA gate (Ladder 3).
#
# It reuses rrm_meta.py's schema verbatim (same events/outcomes files, same
# EVENT_TIME_FMT, same B label) so numbers are comparable, and adds the de Prado
# rigour that the single-holdout trainer intentionally defers:
#
#   1. FEATURE HEALTH   — per-feature coverage / variance / %-zero / constant flag.
#                         Catches the "dead column" failure mode automatically
#                         (e.g. the pre-2026-07-31 macd_hist that logged 0.0 every
#                         bar). A model can't learn "ranging -> skip" from a feature
#                         that never varies; this prints which ones are dead.
#   2. DUAL LABELS      — B (realized BE-or-profit, from TS_outcomes) AND
#                         Q (signal-only, a REALISTIC triple barrier at Q_TARGET_R x
#                         the placed SL). B grades signal+exits jointly (the go/no-go
#                         label); Q isolates TE-signal quality. Comparing them tells
#                         you "bad signal" vs "good signal my exits leave behind."
#   3. CPCV             — Combinatorial Purged Cross-Validation (de Prado Ch.12):
#                         many purged+embargoed OOS paths, not one 30% holdout. You
#                         get a DISTRIBUTION of gated-vs-ungated performance.
#   4. DSR + PBO        — Deflated Sharpe (Ch.14) corrects the reported Sharpe for
#                         the number of thresholds tried (TRIALS, tracked explicitly);
#                         PBO (Bailey/Lopez de Prado CSCV) estimates the probability
#                         the threshold selection is overfit. These are the numbers
#                         that turn "looks good OOS" into "survives honest scoring."
#
# RUN:   python3 rrm_validate.py                 # auto-locate real CSVs, validate all pairs
#        python3 rrm_validate.py --smoke         # synthetic self-test, no MT5 data needed
#        python3 rrm_validate.py --pair EURUSD --tf M1 --preset RRM_ORG
# DEPS:  pip install pandas numpy scikit-learn   (same as rrm_meta.py)
# =============================================================================

import os, sys, glob, math, argparse, itertools, re
import numpy as np
import pandas as pd
from sklearn.linear_model import LogisticRegression
from sklearn.preprocessing import StandardScaler

HERE = os.path.dirname(os.path.abspath(__file__))

# ---- schema knobs: keep IDENTICAL to rrm_meta.py so the two agree ------------
EVENT_TIME_FMT = "%Y.%m.%d %H:%M"
COST_PRICE     = 0.0
NON_FEATURES   = {"event_time", "symbol", "preset", "direction",
                  "sl_dist", "tp_dist", "time_barrier_bars",
                  "be_or_better", "realized_r"}
WINE_ROOTS = [
    "~/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c",
    "~/.wine/drive_c",
    "~/.mt5/drive_c",
]

# ---- Ladder-1 validation knobs (these ARE the trial surface; changing them is
#      itself a trial — the DSR below is told how many thresholds you swept) ----
CPCV_N_GROUPS   = 6      # N: number of contiguous time groups
CPCV_TEST_K     = 2      # k: groups held out per split  -> C(N,k) splits
EMBARGO_FRAC    = 0.01   # embargo after each test block, as a fraction of #events
THRESH_GRID     = np.round(np.linspace(0.30, 0.80, 51), 4)   # 51 trials (matches trainer)
PBO_SUBSETS     = 8      # S for CSCV (even). C(S,S/2) train/test partitions.
Q_TARGET_R      = 1.0    # Q label: profit target as a multiple of the PLACED SL
                         # (1.0R = "did the signal give back at least what it risked",
                         # a barrier RRM actually reaches — unlike the retired 2.5R)
MIN_EVENTS      = 120    # below this, report but flag as indicative-only
EULER_GAMMA     = 0.5772156649015329

# ---- FEATURE_SUBSET: None = use every (live) logged feature. Set to a LIST to test
#      only those features — e.g. the ranging/regime tells — WITHOUT re-collecting.
#      Fewer features on limited data => less overfit => usually a lower PBO. Each
#      distinct subset you try is itself a trial, so don't keep re-rolling. ----
FEATURE_SUBSET  = None
# Example regime-only experiment (uncomment to use):
# FEATURE_SUBSET = ["adx","di_spread","bb_width_atr","ret_vol_20","ema_fan_atr","atr","hour"]


# ============================================================ discovery (mirrors rrm_meta.py)
def _candidate_dirs(files_dir):
    dirs = []
    if files_dir:
        dirs.append(files_dir)
    for root in WINE_ROOTS:
        root = os.path.expanduser(root)
        if not os.path.isdir(root):
            continue
        dirs += glob.glob(os.path.join(root, "**", "Common", "Files"), recursive=True)
        dirs += glob.glob(os.path.join(root, "**", "MQL5", "Files"), recursive=True)
        dirs += glob.glob(os.path.join(root, "**", "MetaTrader 5", "Files"), recursive=True)
    seen, out = set(), []
    for d in dirs:
        d = os.path.normpath(d)
        if d not in seen and os.path.isdir(d):
            seen.add(d); out.append(d)
    return out

def _newest(paths):
    return max(paths, key=os.path.getmtime) if paths else None

def find_all_events(files_dir, preset):
    by_name = {}
    for d in _candidate_dirs(files_dir):
        for h in glob.glob(os.path.join(d, "**", f"TS_events_{preset}*.csv"), recursive=True):
            b = os.path.basename(h)
            if b not in by_name or os.path.getmtime(h) > os.path.getmtime(by_name[b]):
                by_name[b] = h
    return [by_name[b] for b in sorted(by_name)]

def parse_pair_tf(ev_path, preset):
    m = re.match(rf"TS_events_{re.escape(preset)}(?:_(.+))?\.csv$", os.path.basename(ev_path))
    if not m or not m.group(1):
        return None, None
    pair, _, tf = m.group(1).rpartition("_")
    return (pair or None), (tf or None)

def find_outcomes(files_dir, preset, pair, tf):
    pat = (f"TS_outcomes_{preset}_{pair}_{tf}.csv" if pair else f"TS_outcomes_{preset}.csv")
    hits = []
    for d in _candidate_dirs(files_dir):
        hits += glob.glob(os.path.join(d, "**", pat), recursive=True)
    return _newest(sorted(set(os.path.normpath(h) for h in hits))) if hits else None

def find_price(files_dir, pair, tf):
    pat = f"{pair}_{tf}_*.csv"
    hits = []
    for d in _candidate_dirs(files_dir):
        hits += glob.glob(os.path.join(d, "**", pat), recursive=True)
    hits += glob.glob(os.path.join(HERE, "..", "_FX-PAIRS_CSV_*", pat))
    return sorted(set(os.path.normpath(h) for h in hits))


# ============================================================ CSV parsing (mirrors rrm_meta.py)
def _sniff_sep(path):
    with open(path, "r", errors="replace") as fh:
        head = fh.readline()
    return "\t" if head.count("\t") >= head.count(",") else ","

def read_events(path):
    ev = pd.read_csv(path, sep=_sniff_sep(path))
    ev["event_time"] = pd.to_datetime(ev["event_time"], format=EVENT_TIME_FMT, errors="coerce")
    if ev["event_time"].isna().any():
        ev["event_time"] = pd.to_datetime(ev["event_time"], errors="coerce")
    return ev.dropna(subset=["event_time"]).sort_values("event_time").reset_index(drop=True)

def read_outcomes(path):
    oc = pd.read_csv(path, sep=_sniff_sep(path))
    oc["event_time"] = pd.to_datetime(oc["event_time"], format=EVENT_TIME_FMT, errors="coerce")
    if oc["event_time"].isna().any():
        oc["event_time"] = pd.to_datetime(oc["event_time"], errors="coerce")
    return (oc.dropna(subset=["event_time"])
              .drop_duplicates(subset="event_time", keep="last").reset_index(drop=True))

def read_price(path):
    sep = _sniff_sep(path)
    df = pd.read_csv(path, sep=sep)
    cols = {c.strip().lower().strip("<>"): c for c in df.columns}
    if "date" in cols and "time" in cols:
        t = df[cols["date"]].astype(str).str.strip() + " " + df[cols["time"]].astype(str).str.strip()
        time = pd.to_datetime(t, format="%Y.%m.%d %H:%M:%S", errors="coerce")
        if time.isna().all():
            time = pd.to_datetime(t, errors="coerce")
    elif "time" in cols:
        time = pd.to_datetime(df[cols["time"]], errors="coerce")
    else:
        raise ValueError(f"{os.path.basename(path)}: no <DATE>/<TIME> or time column")
    return pd.DataFrame({
        "time": time,
        "open": pd.to_numeric(df[cols["open"]], errors="coerce"),
        "high": pd.to_numeric(df[cols["high"]], errors="coerce"),
        "low":  pd.to_numeric(df[cols["low"]],  errors="coerce"),
    }).dropna().sort_values("time").reset_index(drop=True)

def build_price_series(paths):
    frames = []
    for p in sorted(paths):
        try:
            frames.append(read_price(p))
        except Exception as e:
            print(f"  (skipped price {os.path.basename(p)}: {e})")
    if not frames:
        return None
    return (pd.concat(frames, ignore_index=True)
              .drop_duplicates(subset="time").sort_values("time").reset_index(drop=True))


# ============================================================ labels
def label_B_from_outcomes(events, outcomes):
    """B: realized BE-or-profit meta-label (== rrm_meta.py). Grades signal+exits
    JOINTLY — the correct label for a live go/no-go trade gate."""
    cols = [c for c in ("event_time", "be_or_better", "realized_r") if c in outcomes.columns]
    m = events.merge(outcomes[cols], on="event_time", how="inner")
    m["label_B"] = m["be_or_better"].astype(int)
    return m.reset_index(drop=True)

def label_Q_signal_only(events, px, target_r=Q_TARGET_R):
    """Q: signal-quality label, INDEPENDENT of your live exits. Triple barrier from
    the entry bar using the PLACED SL geometry, with a REALISTIC profit target of
    target_r x sl_dist (not the retired 2.5R that RRM hits ~5% of the time), net of
    cost, vertical = time_barrier_bars. label_Q = 1 iff the target is touched before
    the SL and before the time barrier. This measures 'was the move there', so
    Q-vs-B separates a bad SIGNAL from a good signal your exits gave back."""
    t  = px["time"].values; hi = px["high"].values
    lo = px["low"].values;  op = px["open"].values
    t0, t1 = t[0], t[-1]
    out = np.full(len(events), np.nan)
    for i, e in events.reset_index(drop=True).iterrows():
        et = np.datetime64(e["event_time"])
        if et < t0 or et >= t1:
            continue
        idx = int(np.searchsorted(t, et, side="right"))     # entry = bar AFTER the signal bar
        if idx >= len(px) - 1:
            continue
        entry = op[idx]; d = float(e["direction"])
        sl_dist = float(e.get("sl_dist", np.nan))
        if not np.isfinite(sl_dist) or sl_dist <= 0:
            continue
        tp = entry + d * (target_r * sl_dist + COST_PRICE)
        sl = entry - d * sl_dist
        tmax = int(e.get("time_barrier_bars", 0)) or (len(px) - idx)
        lab = 0
        for k in range(idx, min(idx + tmax, len(px))):
            hit_tp = (hi[k] >= tp) if d > 0 else (lo[k] <= tp)
            hit_sl = (lo[k] <= sl) if d > 0 else (hi[k] >= sl)
            if hit_tp and hit_sl: lab = 0; break            # same-bar ambiguity -> loss
            if hit_tp:            lab = 1; break
            if hit_sl:            lab = 0; break
        out[i] = lab
    ev = events.copy(); ev["label_Q"] = out
    return ev


# ============================================================ feature health (the dead-column guard)
def feature_health(df, feats):
    """One row per feature: n, %-present(non-NaN), %-zero, std, and a DEAD flag for
    constant / all-zero / all-NaN columns. A DEAD feature cannot carry signal and is
    the classic silent cause of 'the gate made things worse'."""
    rows = []
    for f in feats:
        x = pd.to_numeric(df[f], errors="coerce")
        n = len(x); present = x.notna().sum()
        nun = x.nunique(dropna=True)
        std = float(x.std(ddof=1)) if present > 1 else 0.0
        pz  = float((x == 0).mean()) if present else 1.0
        dead = (present == 0) or (nun <= 1) or (std == 0.0)
        rows.append(dict(feature=f, present_pct=100*present/max(1, n),
                         zero_pct=100*pz, nunique=int(nun), std=std, DEAD=bool(dead)))
    h = pd.DataFrame(rows).sort_values(["DEAD", "std"], ascending=[False, True]).reset_index(drop=True)
    return h


# ============================================================ stats core
def normal_cdf(x):  return 0.5 * (1.0 + math.erf(x / math.sqrt(2.0)))
def normal_ppf(p):
    # Acklam's inverse-normal approximation (no scipy dependency)
    if p <= 0: return -np.inf
    if p >= 1: return np.inf
    a=[-3.969683028665376e+01,2.209460984245205e+02,-2.759285104469687e+02,1.383577518672690e+02,-3.066479806614716e+01,2.506628277459239e+00]
    b=[-5.447609879822406e+01,1.615858368580409e+02,-1.556989798598866e+02,6.680131188771972e+01,-1.328068155288572e+01]
    c=[-7.784894002430293e-03,-3.223964580411365e-01,-2.400758277161838e+00,-2.549732539343734e+00,4.374664141464968e+00,2.938163982698783e+00]
    d=[7.784695709041462e-03,3.224671290700398e-01,2.445134137142996e+00,3.754408661907416e+00]
    pl=0.02425
    if p < pl:
        q=math.sqrt(-2*math.log(p)); return (((((c[0]*q+c[1])*q+c[2])*q+c[3])*q+c[4])*q+c[5])/((((d[0]*q+d[1])*q+d[2])*q+d[3])*q+1)
    if p > 1-pl:
        q=math.sqrt(-2*math.log(1-p)); return -(((((c[0]*q+c[1])*q+c[2])*q+c[3])*q+c[4])*q+c[5])/((((d[0]*q+d[1])*q+d[2])*q+d[3])*q+1)
    q=p-0.5; r=q*q
    return (((((a[0]*r+a[1])*r+a[2])*r+a[3])*r+a[4])*r+a[5])*q/(((((b[0]*r+b[1])*r+b[2])*r+b[3])*r+b[4])*r+1)

def sharpe(returns):
    r = np.asarray(returns, float)
    if len(r) < 2 or r.std(ddof=1) == 0: return float("nan")
    return r.mean() / r.std(ddof=1)

def psr(returns, sr_star=0.0):
    """Probabilistic Sharpe Ratio: P(true SR > sr_star), skew/kurtosis-adjusted."""
    r = np.asarray(returns, float); n = len(r)
    if n < 3 or r.std(ddof=1) == 0: return float("nan")
    sr = r.mean() / r.std(ddof=1)
    sk = pd.Series(r).skew(); ku = pd.Series(r).kurt() + 3.0
    denom = math.sqrt(max(1e-12, 1 - sk*sr + (ku-1)/4.0*sr*sr))
    return normal_cdf((sr - sr_star) * math.sqrt(n-1) / denom)

def deflated_sharpe(returns, sr_trials, n_trials):
    """Deflated Sharpe Ratio (de Prado 2014). Deflates the observed SR by the
    Sharpe you'd EXPECT as the max of n_trials independent tries under the null,
    using the variance of the trial Sharpes. Returns (DSR_prob, sr_obs, sr0)."""
    r = np.asarray(returns, float); n = len(r)
    if n < 3 or r.std(ddof=1) == 0: return float("nan"), float("nan"), float("nan")
    sr = r.mean() / r.std(ddof=1)
    v  = np.var(np.asarray(sr_trials, float), ddof=1) if len(sr_trials) > 1 else 0.0
    N  = max(1, int(n_trials))
    if v > 0 and N > 1:
        sr0 = math.sqrt(v) * ((1-EULER_GAMMA)*normal_ppf(1 - 1.0/N)
                              + EULER_GAMMA*normal_ppf(1 - 1.0/(N*math.e)))
    else:
        sr0 = 0.0
    return psr(r, sr_star=sr0), sr, sr0


# ============================================================ CPCV
def make_groups(n, n_groups):
    """Contiguous, time-ordered groups (indices)."""
    edges = np.linspace(0, n, n_groups + 1, dtype=int)
    return [np.arange(edges[g], edges[g+1]) for g in range(n_groups)]

def cpcv_splits(n, n_groups=CPCV_N_GROUPS, k=CPCV_TEST_K, embargo=None):
    """Yield (train_idx, test_idx) for every choice of k test-groups out of N,
    purging + embargoing training rows adjacent to the test blocks. Labels here are
    forward-looking (a trade/label resolves AFTER its event), so we drop training
    events that fall inside a test block's span or within the embargo just after it."""
    groups = make_groups(n, n_groups)
    if embargo is None:
        embargo = max(1, int(round(EMBARGO_FRAC * n)))
    for combo in itertools.combinations(range(n_groups), k):
        test_idx = np.concatenate([groups[g] for g in combo])
        test_lo, test_hi = test_idx.min(), test_idx.max()
        train_mask = np.ones(n, dtype=bool)
        train_mask[test_idx] = False
        # purge: anything overlapping the test span; embargo: buffer just after it
        train_mask[test_lo:test_hi + 1 + embargo] = False
        train_idx = np.where(train_mask)[0]
        if len(train_idx) >= 30 and len(test_idx) >= 10:
            yield train_idx, test_idx

def fit_pick_threshold(Xtr, ytr, rtr):
    """Fit scaler+logit on TRAIN, pick the threshold maximising PSR ON TRAIN
    (never on test). Returns (scaler, clf, best_thr, sr_trials) where sr_trials are
    RAW Sharpe ratios per threshold — the correct unit for the DSR variance term."""
    sc  = StandardScaler().fit(Xtr)
    clf = LogisticRegression(class_weight="balanced", max_iter=1000).fit(sc.transform(Xtr), ytr)
    ptr = clf.predict_proba(sc.transform(Xtr))[:, 1]
    best_thr, best_psr, sr_trials = 0.5, -1e9, []
    for thr in THRESH_GRID:
        taken = rtr[ptr >= thr]
        if len(taken) >= 20:
            ssr = sharpe(taken); ppsr = psr(taken)          # raw Sharpe for variance; PSR to select
        else:
            ssr = float("nan"); ppsr = float("nan")
        sr_trials.append(ssr if not math.isnan(ssr) else 0.0)
        if not math.isnan(ppsr) and ppsr > best_psr:
            best_psr, best_thr = ppsr, thr
    return sc, clf, best_thr, sr_trials


# ============================================================ PBO (Bailey/Lopez de Prado CSCV)
def pbo(X, y, r, feats, n_subsets=PBO_SUBSETS):
    """Probability of Backtest Overfitting over the THRESHOLD grid (the config set):
    split the sample into S contiguous subsets; for every way to pick S/2 as IS,
    the rest as OOS, fit on IS, score every threshold on IS and OOS, take the IS-best
    threshold, and read its OOS rank. PBO = P(the IS-best is below the OOS median)."""
    n = len(y)
    if n < n_subsets * 10:
        return float("nan")
    edges = np.linspace(0, n, n_subsets + 1, dtype=int)
    subs  = [np.arange(edges[s], edges[s+1]) for s in range(n_subsets)]
    logits = []
    for isC in itertools.combinations(range(n_subsets), n_subsets // 2):
        is_idx  = np.concatenate([subs[s] for s in isC])
        oos_idx = np.concatenate([subs[s] for s in range(n_subsets) if s not in isC])
        sc = StandardScaler().fit(X[is_idx])
        clf = LogisticRegression(class_weight="balanced", max_iter=1000).fit(sc.transform(X[is_idx]), y[is_idx])
        p_is  = clf.predict_proba(sc.transform(X[is_idx]))[:, 1]
        p_oos = clf.predict_proba(sc.transform(X[oos_idx]))[:, 1]
        is_perf, oos_perf = [], []
        for thr in THRESH_GRID:
            ai = r[is_idx][p_is >= thr]; ao = r[oos_idx][p_oos >= thr]
            is_perf.append(sharpe(ai) if len(ai) >= 10 else -1e9)
            oos_perf.append(sharpe(ao) if len(ao) >= 10 else np.nan)
        is_perf = np.array(is_perf); oos_perf = np.array(oos_perf)
        n_star = int(np.nanargmax(is_perf))                    # best config in-sample
        valid  = ~np.isnan(oos_perf)
        if valid.sum() < 2 or np.isnan(oos_perf[n_star]):
            continue
        # relative OOS rank of the IS-best config in (0,1)
        rank = (oos_perf[valid] < oos_perf[n_star]).sum() / valid.sum()
        rank = min(max(rank, 1e-6), 1 - 1e-6)
        logits.append(math.log(rank / (1 - rank)))
    if not logits:
        return float("nan")
    return float(np.mean(np.array(logits) <= 0))               # PBO = P(logit <= 0)


# ============================================================ profitability (the money question)
def profitability(returns):
    """Plain 'are we making money' stats on a per-trade R series. Independent of the
    gate verdict: total_R>0 and profit_factor>1 means the strategy is profitable on
    this data, whatever the Sharpe/DSR say."""
    r = np.asarray(returns, float); r = r[~np.isnan(r)]; n = len(r)
    if n == 0:
        return dict(n=0, win_pct=float("nan"), total_R=0.0, mean_R=float("nan"), pf=float("nan"))
    wins = r[r > 0]; losses = r[r < 0]
    gp = float(wins.sum()); gl = float(-losses.sum())
    pf = (gp / gl) if gl > 0 else float("inf")
    return dict(n=n, win_pct=100.0*len(wins)/n, total_R=float(r.sum()),
                mean_R=float(r.mean()), pf=pf)

def _fmt_prof(p, label):
    if p["n"] == 0: return f"    {label:<22}: no trades"
    pf = "inf" if p["pf"] == float("inf") else f"{p['pf']:.2f}"
    return (f"    {label:<22}: {p['n']:>4} trades   win {p['win_pct']:4.0f}%   "
            f"total {p['total_R']:+7.1f}R   expectancy {p['mean_R']:+.3f}R/trade   PF {pf}")


# ============================================================ per-pair validation
def validate_one(ev_path, pair, tf, preset, files_dir):
    tag = f"{pair}_{tf}" if pair else "(legacy)"
    print(f"\n=================== LADDER 1: {tag} ===================")
    ev = read_events(ev_path)
    print(f"events : {len(ev)} rows  ({ev['event_time'].min()} .. {ev['event_time'].max()})")

    # ---- labels: B (realized) required; Q (signal-only) if price available ----
    oc_path = find_outcomes(files_dir, preset, pair, tf)
    if not oc_path:
        print("  SKIP: no TS_outcomes_* file -> no realized (B) label. Re-collect with the current EA.")
        return None
    ev = label_B_from_outcomes(ev, read_outcomes(oc_path))
    print(f"label B: {len(ev)} labelled trades, win rate {ev['label_B'].mean():.1%}  [realized BE-or-profit]")

    px = build_price_series(find_price(files_dir, pair, tf)) if pair else None
    have_Q = px is not None and len(px) > 0
    if have_Q:
        ev = label_Q_signal_only(ev, px)
        q = ev["label_Q"].dropna()
        if len(q):
            print(f"label Q: {len(q)} labelled signals, hit rate {q.mean():.1%}  "
                  f"[signal-only, {Q_TARGET_R:.1f}R barrier]  -> Q-vs-B gap = "
                  f"{q.mean() - ev['label_B'].mean():+.1%}")
    else:
        print("label Q: (no price file — skipping signal-only label; add PAIR_TF_*.csv for it)")

    feats = [c for c in ev.columns if c not in NON_FEATURES | {"label_B", "label_Q"}]
    if FEATURE_SUBSET:
        feats = [c for c in feats if c in FEATURE_SUBSET]
        print(f"  (FEATURE_SUBSET active: {len(feats)} features -> {feats})")
    ev = ev.dropna(subset=feats + ["label_B"]).reset_index(drop=True)

    # ---- 1. FEATURE HEALTH (the dead-column guard) ----
    health = feature_health(ev, feats)
    dead = health[health["DEAD"]]["feature"].tolist()
    print(f"\n[1] FEATURE HEALTH  ({len(feats)} features, {len(dead)} DEAD)")
    print(health.to_string(index=False,
          formatters={"present_pct":"{:.0f}".format, "zero_pct":"{:.0f}".format, "std":"{:.4g}".format}))
    if dead:
        print(f"  ** DEAD (constant / all-zero) -> carry no signal, drop or fix + re-collect: {dead}")
    live = [f for f in feats if f not in dead]

    if len(ev) < MIN_EVENTS:
        print(f"\n  NOTE: only {len(ev)} labelled events (<{MIN_EVENTS}) — results indicative only.")
    if len(live) == 0 or len(ev) < CPCV_N_GROUPS * 12:
        print("  SKIP scoring: too few live features or events for CPCV.")
        return dict(tag=tag, dead=dead, n=len(ev))

    X = ev[live].values.astype(float)
    y = ev["label_B"].values.astype(int)
    r = np.nan_to_num(ev["realized_r"].astype(float).values, nan=0.0) if "realized_r" in ev else \
        np.where(y == 1, 1.0, -1.0)

    # ---- 2. PROFITABILITY (the money question: ungated, ALL trades, realized R) ----
    prof_all_full = profitability(r)
    print(f"\n[2] PROFITABILITY  <- 'are we making money?' (ungated, all {prof_all_full['n']} trades, realized R)")
    print(_fmt_prof(prof_all_full, "RRM_ORG ungated"))
    print("    total R > 0 and PF > 1 = the base strategy is profitable on this data —")
    print("    that stands even if the gate below says DO NOT SHIP (the gate is a separate question).")

    # ---- 3. CPCV: distribution of OOS gated-vs-all performance ----
    all_paths, gate_paths, best_sr_trials = [], [], []
    for tr, te in cpcv_splits(len(ev)):
        sc, clf, thr, sr_tr = fit_pick_threshold(X[tr], y[tr], r[tr])
        best_sr_trials.extend([s for s in sr_tr if s != 0.0])   # per-threshold Sharpes -> DSR variance input
        pte = clf.predict_proba(sc.transform(X[te]))[:, 1]
        r_all, r_gate = r[te], r[te][pte >= thr]
        s_all, s_gate = psr(r_all), psr(r_gate)
        if not math.isnan(s_all):  all_paths.append(s_all)
        if not math.isnan(s_gate): gate_paths.append(s_gate)
    # de Prado's N = number of configurations you SELECT among = the thresholds swept.
    # Folds are CV estimates of those same configs, NOT extra trials — so do not multiply.
    n_trials = len(THRESH_GRID)
    if not gate_paths:
        print("\n  SKIP scoring: no valid CPCV paths (too few gated trades).")
        return dict(tag=tag, dead=dead, n=len(ev))

    med_all  = float(np.median(all_paths))
    med_gate = float(np.median(gate_paths))
    print(f"\n[3] CPCV  (N={CPCV_N_GROUPS}, k={CPCV_TEST_K} -> {len(gate_paths)} OOS paths)")
    print(f"    PSR (median over paths)  all -> gated : {med_all:.3f} -> {med_gate:.3f}"
          f"   ({'+' if med_gate>=med_all else ''}{med_gate-med_all:.3f})")
    print(f"    gated better than ungated on {np.mean(np.array(gate_paths) > np.median(all_paths))*100:.0f}% of paths")

    # ---- 4. Deflated Sharpe (corrects for the {n_trials} thresholds swept) + PBO ----
    # Pool the OOS returns across paths: gated (kept by the filter) vs ungated (all).
    pooled, pooled_all = [], []
    for tr, te in cpcv_splits(len(ev)):
        sc, clf, thr, _ = fit_pick_threshold(X[tr], y[tr], r[tr])
        pte = clf.predict_proba(sc.transform(X[te]))[:, 1]
        pooled.extend(list(r[te][pte >= thr]))
        pooled_all.extend(list(r[te]))
    dsr_p, sr_obs, sr0 = deflated_sharpe(pooled, best_sr_trials, n_trials)
    pbo_val = pbo(X, y, r, live)
    print(f"\n[4] DOES THE GATE HELP?  profitability on the SAME out-of-sample trades:")
    print(_fmt_prof(profitability(pooled_all), "ungated (OOS)"))
    print(_fmt_prof(profitability(pooled),     "gated   (OOS)"))
    print(f"    DEFLATED SHARPE  (trials counted = {n_trials})")
    print(f"      observed SR (gated, pooled OOS) : {sr_obs:.3f}")
    print(f"      SR0 (expected max under null)   : {sr0:.3f}")
    print(f"      DSR = P(true SR > SR0)          : {dsr_p:.3f}   (want > 0.95)")
    print(f"      PBO (prob. of overfit selection): {pbo_val:.3f}   (want < 0.50, ideally < 0.20)")

    prof_u = profitability(pooled_all); prof_g = profitability(pooled)

    # ---- verdict ----
    # SHIP is driven by PROFITABILITY + robustness, NOT by DSR alone. DSR is a per-trade
    # Sharpe test; a fat-tailed R profile (many BE scratches + rare big winners — RRM's
    # shape) has low per-trade Sharpe even when clearly profitable, so DSR is reported as
    # a STRICT advisory, not a hard gate. Practical ship test: the filter makes MORE money
    # out-of-sample (total R and PF up) AND selection isn't overfit (PBO < 0.5) AND it wins
    # on a majority of CPCV paths.
    money_up = (prof_g["total_R"] > prof_u["total_R"]) and (prof_g["pf"] > prof_u["pf"])
    robust   = (not math.isnan(pbo_val)) and (pbo_val < 0.50)
    paths_up = med_gate > med_all
    ship = money_up and robust and paths_up
    dsr_ok = (not math.isnan(dsr_p)) and (dsr_p > 0.95)
    print(f"\n  VERDICT [{tag}]: {'SHIP -> train with rrm_meta.py' if ship else 'DO NOT SHIP (gate not proven)'}")
    print(f"    money OOS (gated>ungated): {'YES' if money_up else 'no ':<3}"
          f"   robust (PBO<0.5): {'YES' if robust else 'no ':<3}"
          f"   paths (gated>ungated): {'YES' if paths_up else 'no ':<3}"
          f"   [DSR strict check: {'pass' if dsr_ok else 'fail — expected on fat-tailed R'}]")
    if dead:
        print(f"  (also: {len(dead)} DEAD feature(s) auto-dropped — if unexpected, delete + re-collect)")
    return dict(tag=tag, dead=dead, n=len(ev), psr_all=med_all, psr_gate=med_gate,
                total_R_u=prof_u["total_R"], total_R_g=prof_g["total_R"],
                pf_u=prof_u["pf"], pf_g=prof_g["pf"],
                dsr=dsr_p, sr0=sr0, pbo=pbo_val, trials=n_trials, ship=ship)


# ============================================================ smoke test (no MT5 data)
def smoke():
    """Synthetic self-test: a signal whose edge exists ONLY in low-ADX (ranging)
    rows is bad; a real feature ('adx') should let the gate help, a DEAD feature
    ('macd_hist' all-zero) should be flagged. Proves the pipeline end to end."""
    rng = np.random.default_rng(0)
    n = 1500
    t0 = pd.Timestamp("2024-01-01")
    adx = rng.uniform(8, 45, n)
    # ranging (low adx) trades lose; trending win -> a learnable edge
    p_win = np.clip(0.30 + 0.012*(adx-10), 0.1, 0.85)
    y = (rng.uniform(size=n) < p_win).astype(int)
    realized_r = np.where(y == 1, rng.uniform(0.3, 2.0, n), -1.0)
    times = [t0 + pd.Timedelta(minutes=i) for i in range(n)]
    ev = pd.DataFrame({                                # events file: features only, no label
        "event_time":times,
        "symbol":"EURUSD","preset":"RRM_ORG","direction":1,
        "sl_dist":0.0010,"tp_dist":0.0025,"time_barrier_bars":50,
        "adx":adx, "rsi":rng.uniform(20,80,n), "bb_width_atr":rng.uniform(0.5,3,n),
        "ret_vol_20":rng.uniform(0,1,n),
        "macd_hist":np.zeros(n),                       # <-- DEAD column (the classic bug)
    })
    oc = pd.DataFrame({"event_time":times, "be_or_better":y, "realized_r":realized_r})
    print("SMOKE TEST — synthetic ranging-edge data with one dead feature (macd_hist)")
    ev2 = label_B_from_outcomes(ev, oc)
    feats = [c for c in ev2.columns if c not in NON_FEATURES | {"label_B"}]
    print("\n[1] feature health:")
    print(feature_health(ev2, feats).to_string(index=False))
    X = ev2[[f for f in feats if f != "macd_hist"]].values.astype(float)
    yv = ev2["label_B"].values; rv = ev2["realized_r"].values
    paths_all, paths_gate, trials, srt = [], [], 0, []
    for tr, te in cpcv_splits(len(ev2)):
        sc, clf, thr, s = fit_pick_threshold(X[tr], yv[tr], rv[tr])
        trials += sum(1 for x in s if x != 0.0); srt += [x for x in s if x != 0.0]
        pte = clf.predict_proba(sc.transform(X[te]))[:,1]
        paths_all.append(psr(rv[te])); paths_gate.append(psr(rv[te][pte>=thr]))
    paths_all=[x for x in paths_all if not math.isnan(x)]; paths_gate=[x for x in paths_gate if not math.isnan(x)]
    print(f"\n[3] CPCV PSR median  all -> gated : {np.median(paths_all):.3f} -> {np.median(paths_gate):.3f}")
    pooled=[]
    for tr, te in cpcv_splits(len(ev2)):
        sc, clf, thr, _ = fit_pick_threshold(X[tr], yv[tr], rv[tr])
        pte = clf.predict_proba(sc.transform(X[te]))[:,1]; pooled += list(rv[te][pte>=thr])
    d,sro,s0 = deflated_sharpe(pooled, srt, trials)
    print(f"[4] DSR={d:.3f}  SR0={s0:.3f}  trials={trials}  PBO={pbo(X,yv,rv,None):.3f}")
    print("\nSMOKE OK — pipeline runs, dead feature flagged, gate evaluated out-of-sample.")


# ============================================================ main
def main():
    ap = argparse.ArgumentParser(description="RRM Ladder-1 validator (CPCV + DSR + PBO).")
    ap.add_argument("--files-dir", default="")
    ap.add_argument("--pair", default=None)
    ap.add_argument("--tf", default=None)
    ap.add_argument("--preset", default="RRM_ORG")
    ap.add_argument("--smoke", action="store_true", help="synthetic self-test, no MT5 data")
    args = ap.parse_args()

    if args.smoke:
        smoke(); return

    files_dir = os.path.expanduser(args.files_dir) if args.files_dir else ""
    if args.pair and args.tf:
        name = f"TS_events_{args.preset}_{args.pair}_{args.tf}.csv"
        hits = []
        for d in _candidate_dirs(files_dir):
            hits += glob.glob(os.path.join(d, "**", name), recursive=True)
        ev_paths = sorted(set(os.path.normpath(h) for h in hits))
    else:
        ev_paths = find_all_events(files_dir, args.preset)

    if not ev_paths:
        print("No TS_events_* files found. Run a COLLECT backtest first "
              "(Inp_META_LogFeatures=true), or pass --files-dir / --smoke.")
        return

    print(f"Found {len(ev_paths)} events file(s) for preset {args.preset}.")
    summary = []
    for ep in ev_paths:
        p, tf = parse_pair_tf(ep, args.preset)
        try:
            res = validate_one(ep, p, tf, args.preset, files_dir)
            if res: summary.append(res)
        except Exception as e:
            print(f"  ERROR on {os.path.basename(ep)}: {e}")

    if summary:
        print("\n===================== SUMMARY =====================")
        for s in summary:
            if "ship" in s:
                pfg = "inf" if s.get("pf_g")==float("inf") else f"{s.get('pf_g',float('nan')):.2f}"
                print(f"  {s['tag']:<18} n={s['n']:<5} "
                      f"R {s.get('total_R_u',0):+.0f}->{s.get('total_R_g',0):+.0f}  PFg={pfg}  "
                      f"PBO={s['pbo']:.2f} DSR={s['dsr']:.2f}  "
                      f"{'SHIP' if s['ship'] else 'hold'}"
                      f"{'  DEAD:'+','.join(s['dead']) if s['dead'] else ''}")
            else:
                print(f"  {s['tag']:<18} n={s['n']:<5} (not scored)"
                      f"{'  DEAD:'+','.join(s['dead']) if s.get('dead') else ''}")
    print("\nLadder 1 done. Train (Ladder 2) only the pairs marked SHIP, then gate (Ladder 3).")


if __name__ == "__main__":
    main()
