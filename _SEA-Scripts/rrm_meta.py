#!/usr/bin/env python3
# =============================================================================
# rrm_meta.py  —  RRM EA meta-model trainer (Option 1: logistic regression)
# =============================================================================
# WHAT THIS IS: Ladder 2 (the MODEL). It labels, fits a logistic regression, tunes
# the decision threshold, and exports MetaModel_*.csv for the EA. It runs a SINGLE
# purged HOLDOUT + PSR as a quick sanity read — it does NOT do purged K-fold / CPCV
# / Deflated Sharpe / PBO. That honest validation is Ladder 1 (rrm_validate.py); run
# it FIRST and only train the pairs it marks SHIP. (Earlier headers called this a
# "deflated-Sharpe sweep" — it was never that; corrected 2026-08-03.)
#
# 2026-08-03 CORRECTIONS (this file):
#   * DEAD-FEATURE GUARD. Before fitting, every feature is checked for zero variance
#     (constant / all-zero / all-NaN). Dead columns are DROPPED from the model and
#     loudly reported. This is the exact failure that can make a gate underperform:
#     a feature logged as 0.0 every bar (the old macd_hist proxy, or a telemetry
#     value collected before the engine wired it) teaches the model nothing and
#     dilutes the rest. If you see DEAD columns here, DELETE the pair's TS_events_*
#     and TS_outcomes_* and RE-COLLECT with the current EA before trusting anything.
#   * HONEST OUTPUT. The run prints "purged HOLDOUT + PSR", the number of thresholds
#     swept (a trial count), and a SHIP / DO-NOT-SHIP line — and points to Ladder 1.
#
# WHAT CHANGED earlier (I/O layer only; the stats core — triple barrier, PSR
# threshold sweep, single purged holdout, export — is unchanged):
#   * AUTO-LOCATES both CSVs anywhere under the MT5/Wine tree. The EA writes the
#     events file with FILE_COMMON => it lands in  <terminal>\Common\Files , NOT
#     the Tester agent sandbox. We search Common\Files, every Tester Agent-*\
#     MQL5\Files, MQL5\Files, and any configured files_dir, and take the newest.
#   * PARSES MT5-NATIVE EXPORTS. Price CSVs exported by MT5 are TAB-separated
#     with columns  <DATE> <TIME> <OPEN> <HIGH> <LOW> <CLOSE> ...  (date & time
#     in TWO columns, CRLF). The old reader assumed comma + a single lowercase
#     "time" column and failed on every real file. We now sniff the delimiter
#     and map both layouts.
#   * GLOBS the price file (PAIR_TF_*.csv) instead of constructing an exact name
#     that never matched (native names carry YYYYMMDDHHMM stamps).
#   * NON-INTERACTIVE by default so it can't hang on prompts. Prompts only when a
#     value is genuinely missing AND stdin is a TTY (or pass --interactive).
#
# FILE-NAME CONVENTION:
#   INPUT  price  : PAIR_TF_*.csv            e.g. GBPUSD_M15_202401020000_202412310000.csv
#   INPUT  events : TS_events_<PRESET>.csv   (EA writes it, COLLECT mode)
#   OUTPUT model  : MetaModel_<PRESET>.csv   (EA reads it) — written next to the events file
#
# RUN:          python3 rrm_meta.py            (reads rrm_meta.config, auto-locates, trains)
#               python3 rrm_meta.py --interactive        (old prompt behaviour)
# INSTALL ONCE: pip install pandas numpy scikit-learn
# =============================================================================

import os, sys, glob, math, argparse, configparser
import numpy as np
import pandas as pd
from sklearn.linear_model import LogisticRegression
from sklearn.preprocessing import StandardScaler

HERE = os.path.dirname(os.path.abspath(__file__))
CONFIG_PATH = os.path.join(HERE, "rrm_meta.config")

# static knobs (rarely change)
EVENT_TIME_FMT = "%Y.%m.%d %H:%M"      # how the EA's TimeToString writes event_time
COST_PRICE     = 0.0
TEST_FRACTION  = 0.30
PURGE_BARS     = 50
NON_FEATURES   = {"event_time", "symbol", "preset", "direction",
                  "sl_dist", "tp_dist", "time_barrier_bars",
                  "be_or_better", "realized_r"}

# Roots we scan when auto-locating CSVs (macOS + Wine layouts). ~ is expanded.
WINE_ROOTS = [
    "~/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c",
    "~/.wine/drive_c",
    "~/.mt5/drive_c",
]


# ----------------------------------------------------------------------------- config / resolve
def load_config():
    d = {}
    if os.path.exists(CONFIG_PATH):
        cp = configparser.ConfigParser()
        cp.read(CONFIG_PATH)
        if cp.has_section("meta"):
            d = dict(cp.items("meta"))
    return d


def resolve(cfg, args):
    """CLI flag > config file > (optional) prompt > default. Never prompts unless
    --interactive AND stdin is a TTY, so an unattended run can't hang."""
    interactive = args.interactive and sys.stdin.isatty()

    def pick(flag, key, prompt, default):
        val = flag or cfg.get(key) or default
        if interactive:
            typed = input(f"{prompt} [{val}]: ").strip()
            return typed or val
        return val

    files_dir = pick(args.files_dir, "files_dir", "MT5 files folder (optional)", "")
    pair   = pick(args.pair,   "pair",   "Pair",       "GBPUSD")
    tf     = pick(args.tf,     "tf",     "Timeframe",  "M15")
    preset = pick(args.preset, "preset", "Preset",     "RRM_ORG")
    return (os.path.expanduser(files_dir) if files_dir else ""), pair, tf, preset


# ----------------------------------------------------------------------------- file discovery
def _candidate_dirs(files_dir):
    """Ordered, de-duplicated list of directories to search."""
    dirs = []
    if files_dir:
        dirs.append(files_dir)
    for root in WINE_ROOTS:
        root = os.path.expanduser(root)
        if not os.path.isdir(root):
            continue
        # Common\Files (where FILE_COMMON writes land) — highest priority for events
        dirs += glob.glob(os.path.join(root, "**", "Common", "Files"), recursive=True)
        # Tester agent sandboxes + live MQL5\Files
        dirs += glob.glob(os.path.join(root, "**", "MQL5", "Files"), recursive=True)
        # a bare Files/ some users create under the install dir
        dirs += glob.glob(os.path.join(root, "**", "MetaTrader 5", "Files"), recursive=True)
    # de-dup, keep order, keep only existing dirs
    seen, out = set(), []
    for d in dirs:
        d = os.path.normpath(d)
        if d not in seen and os.path.isdir(d):
            seen.add(d); out.append(d)
    return out


def _newest(paths):
    return max(paths, key=os.path.getmtime) if paths else None


def find_all_events(files_dir, preset):
    """Every  TS_events_<preset>*.csv  under the MT5 tree — one per pair+TF the EA
    collected (e.g. TS_events_RRM_ORG_EURUSD_M1.csv), plus any legacy unkeyed file.
    If the same name exists in several folders, keep the newest."""
    by_name = {}
    for d in _candidate_dirs(files_dir):
        for h in glob.glob(os.path.join(d, "**", f"TS_events_{preset}*.csv"), recursive=True):
            b = os.path.basename(h)
            if b not in by_name or os.path.getmtime(h) > os.path.getmtime(by_name[b]):
                by_name[b] = h
    return [by_name[b] for b in sorted(by_name)]


def parse_pair_tf(ev_path, preset):
    """Pull PAIR and TF out of  TS_events_<preset>_<PAIR>_<TF>.csv .  Preset itself
    may contain underscores (RRM_ORG), so strip the known prefix, then split the
    remainder on the LAST underscore. Returns (None, None) for a legacy unkeyed file."""
    import re
    m = re.match(rf"TS_events_{re.escape(preset)}(?:_(.+))?\.csv$", os.path.basename(ev_path))
    if not m or not m.group(1):
        return None, None
    pair, _, tf = m.group(1).rpartition("_")
    return (pair or None), (tf or None)


def find_price(files_dir, pair, tf):
    pat = f"{pair}_{tf}_*.csv"
    hits = []
    for d in _candidate_dirs(files_dir):
        hits += glob.glob(os.path.join(d, "**", pat), recursive=True)
    # also the repo's bundled price folders, if the script sits in the repo
    hits += glob.glob(os.path.join(HERE, "..", "_FX-PAIRS_CSV_*", pat))
    hits = sorted(set(os.path.normpath(h) for h in hits))
    return hits


def model_target_dirs(ev_path):
    """Folders to write the model into. The EA reads the model at test STARTUP, so
    the per-run agent sandbox (where the events file lives) is not enough — the
    tester seeds the agent from the terminal's MQL5\\Files. Write to BOTH so the
    GATE run finds the model regardless of the tester's per-run reset behaviour."""
    dirs = [os.path.dirname(ev_path)]                       # agent sandbox (harmless)
    # derive the terminal MQL5/Files from  …/Tester/Agent-*/MQL5/Files
    import re
    m = re.search(r"(.*?)[/\\]Tester[/\\]Agent-[^/\\]+[/\\]MQL5[/\\]Files", ev_path)
    if m:
        term = os.path.join(m.group(1), "MQL5", "Files")
        if os.path.isdir(term):
            dirs.append(term)
    # de-dup, keep existing
    seen, out = set(), []
    for d in dirs:
        d = os.path.normpath(d)
        if d not in seen and os.path.isdir(d):
            seen.add(d); out.append(d)
    return out


# ----------------------------------------------------------------------------- CSV parsing
def _sniff_sep(path):
    with open(path, "r", errors="replace") as fh:
        head = fh.readline()
    return "\t" if head.count("\t") >= head.count(",") else ","


def read_price(path):
    """Return a DataFrame with columns time(datetime64), open, high, low — from
    either an MT5-native TAB export (<DATE> <TIME> <OPEN>...) or an already-clean
    comma file with lowercase headers."""
    sep = _sniff_sep(path)
    df = pd.read_csv(path, sep=sep)
    cols = {c.strip().lower().strip("<>"): c for c in df.columns}

    if "date" in cols and "time" in cols:                 # MT5 native: DATE + TIME split
        t = df[cols["date"]].astype(str).str.strip() + " " + df[cols["time"]].astype(str).str.strip()
        time = pd.to_datetime(t, format="%Y.%m.%d %H:%M:%S", errors="coerce")
        if time.isna().all():
            time = pd.to_datetime(t, errors="coerce")     # tolerate a different stamp
    elif "time" in cols:                                  # single datetime column
        time = pd.to_datetime(df[cols["time"]], errors="coerce")
    else:
        raise ValueError(f"price file {os.path.basename(path)} has no <DATE>/<TIME> "
                         f"or time column; got {list(df.columns)}")

    out = pd.DataFrame({
        "time": time,
        "open": pd.to_numeric(df[cols["open"]], errors="coerce"),
        "high": pd.to_numeric(df[cols["high"]], errors="coerce"),
        "low":  pd.to_numeric(df[cols["low"]],  errors="coerce"),
    }).dropna().sort_values("time").reset_index(drop=True)
    return out


def read_events(path):
    ev = pd.read_csv(path, sep=_sniff_sep(path))
    ev["event_time"] = pd.to_datetime(ev["event_time"], format=EVENT_TIME_FMT, errors="coerce")
    if ev["event_time"].isna().any():
        ev["event_time"] = pd.to_datetime(ev["event_time"], errors="coerce")
    ev = ev.dropna(subset=["event_time"]).sort_values("event_time").reset_index(drop=True)
    return ev


def build_price_series(price_paths):
    """Concatenate ALL matching <PAIR>_<TF>_*.csv files (yearly or monthly splits)
    into ONE continuous, de-duplicated, time-sorted series. This is what lets a
    2020-2025 train work from six separate yearly files, or M1 from monthly files."""
    frames = []
    for p in sorted(price_paths):
        try:
            frames.append(read_price(p))
        except Exception as e:
            print(f"  (skipped price {os.path.basename(p)}: {e})")
    if not frames:
        return None
    px = pd.concat(frames, ignore_index=True)
    px = px.drop_duplicates(subset="time").sort_values("time").reset_index(drop=True)
    return px


# ----------------------------------------------------------------------------- labelling (unchanged logic)
def label_triple_barrier(events, px):
    t = px["time"].values; hi = px["high"].values
    lo = px["low"].values; op = px["open"].values
    t0, t1 = t[0], t[-1]
    out = []
    for _, e in events.iterrows():
        et = np.datetime64(e["event_time"])
        if et < t0 or et >= t1:                 # GUARD: event outside price coverage -> unlabelable
            out.append(np.nan); continue
        idx = int(np.searchsorted(t, et, side="right"))
        if idx >= len(px) - 1:
            out.append(np.nan); continue
        entry = op[idx]; d = float(e["direction"])
        tp = entry + d * (float(e["tp_dist"]) + COST_PRICE)
        sl = entry - d * (float(e["sl_dist"]))
        tmax = int(e["time_barrier_bars"]); lab = 0
        for k in range(idx, min(idx + tmax, len(px))):
            hit_tp = (hi[k] >= tp) if d > 0 else (lo[k] <= tp)
            hit_sl = (lo[k] <= sl) if d > 0 else (hi[k] >= sl)
            if hit_tp and hit_sl: lab = 0; break   # same-bar ambiguity => loss
            if hit_tp:            lab = 1; break
            if hit_sl:            lab = 0; break
        out.append(lab)
    events = events.copy(); events["label"] = out
    events = events.dropna(subset=["label"]).reset_index(drop=True)
    events["label"] = events["label"].astype(int)
    return events


# ----------------------------------------------------------------------------- B: realized-outcome label
def find_outcomes(files_dir, preset, pair, tf):
    pat = (f"TS_outcomes_{preset}_{pair}_{tf}.csv" if pair else f"TS_outcomes_{preset}.csv")
    hits = []
    for d in _candidate_dirs(files_dir):
        hits += glob.glob(os.path.join(d, "**", pat), recursive=True)
    return _newest(sorted(set(os.path.normpath(h) for h in hits))) if hits else None


def read_outcomes(path):
    oc = pd.read_csv(path, sep=_sniff_sep(path))
    oc["event_time"] = pd.to_datetime(oc["event_time"], format=EVENT_TIME_FMT, errors="coerce")
    if oc["event_time"].isna().any():
        oc["event_time"] = pd.to_datetime(oc["event_time"], errors="coerce")
    oc = (oc.dropna(subset=["event_time"])
            .drop_duplicates(subset="event_time", keep="last")
            .reset_index(drop=True))
    return oc


def label_from_outcomes(events, outcomes):
    """B-binary meta-label: inner-join events->outcomes on event_time; label = be_or_better.
    Only events that became a CLOSED trade are labelled; the rest (blocked at TE, or still
    open at test end) are dropped, exactly as de Prado meta-labelling intends."""
    cols = [c for c in ("event_time", "be_or_better", "realized_r") if c in outcomes.columns]
    m = events.merge(outcomes[cols], on="event_time", how="inner")
    m["label"] = m["be_or_better"].astype(int)
    return m.reset_index(drop=True)



# ----------------------------------------------------------------------------- stats core (unchanged)
def normal_cdf(x): return 0.5 * (1.0 + math.erf(x / math.sqrt(2.0)))

def psr(returns, bench=0.0):
    r = np.asarray(returns, float); n = len(r)
    if n < 3 or r.std(ddof=1) == 0: return float("nan"), float("nan")
    sr = r.mean() / r.std(ddof=1)
    sk = pd.Series(r).skew(); ku = pd.Series(r).kurt() + 3.0
    denom = math.sqrt(max(1e-12, 1 - sk*sr + (ku-1)/4.0*sr*sr))
    return sr, normal_cdf((sr - bench) * math.sqrt(n-1) / denom)

def r_returns(sub):
    # B (realized): use the EA's logged realized R per trade, not a synthetic +RR/-1 step.
    if "realized_r" in sub.columns:
        return np.nan_to_num(sub["realized_r"].astype(float).values, nan=0.0)
    # legacy fallback (fixed-barrier data with no outcomes file)
    r = np.where(sub["label"] == 1,
                 sub["tp_dist"] / sub["sl_dist"].replace(0, np.nan), -1.0)
    return np.nan_to_num(r, nan=0.0)


# ----------------------------------------------------------------------------- feature health (dead-column guard)
def feature_health(df, feats):
    """One row per feature: %-present, %-zero, unique count, std, and a DEAD flag for
    constant / all-zero / all-NaN columns. A DEAD feature carries no signal and is the
    classic silent cause of 'the gate made things worse'. Same check as rrm_validate.py."""
    rows = []
    for f in feats:
        x = pd.to_numeric(df[f], errors="coerce")
        present = int(x.notna().sum()); nun = int(x.nunique(dropna=True))
        std = float(x.std(ddof=1)) if present > 1 else 0.0
        pz  = float((x == 0).mean()) if present else 1.0
        dead = (present == 0) or (nun <= 1) or (std == 0.0)
        rows.append(dict(feature=f, present_pct=100*present/max(1, len(x)),
                         zero_pct=100*pz, nunique=nun, std=std, DEAD=bool(dead)))
    return pd.DataFrame(rows).sort_values(["DEAD", "std"], ascending=[False, True]).reset_index(drop=True)


# ----------------------------------------------------------------------------- train one pair+TF
def train_one(ev_path, pair, tf, preset, files_dir):
    """Label + train + export for a single events file. Returns a one-line summary."""
    tag = f"{pair}_{tf}" if pair else "(legacy)"
    print(f"\n========================= {tag} =========================")
    ev = read_events(ev_path)
    span = f"{ev['event_time'].min().date()} .. {ev['event_time'].max().date()}" if len(ev) else "empty"
    print(f"events: {ev_path}\n        {len(ev)} signal events   period {span}")

    price_hits = find_price(files_dir, pair, tf)
    px = build_price_series(price_hits)
    if px is None or len(px) == 0:
        print(f"  SKIP {tag}: no {pair}_{tf}_*.csv price file found."); return (tag, "no price file")
    print(f"price : {len(price_hits)} file(s) -> {len(px)} bars "
          f"({px['time'].min()} .. {px['time'].max()})")
    lo, hi = px["time"].min(), px["time"].max()
    pad = pd.Timedelta(days=1)
    n_out = int(((ev["event_time"] < lo - pad) | (ev["event_time"] > hi + pad)).sum())
    if n_out:
        print(f"  WARNING: {n_out} event(s) fall outside the price coverage "
              f"{lo.date()}..{hi.date()} and will be dropped — add the missing "
              f"{pair}_{tf} price file(s) for full coverage.")

    oc_path = find_outcomes(files_dir, preset, pair, tf)
    if oc_path:
        oc = read_outcomes(oc_path)
        n_before = len(ev)
        ev = label_from_outcomes(ev, oc)
        print(f"labeled {len(ev)}/{n_before} events from REALIZED outcomes "
              f"({os.path.basename(oc_path)}) — win rate {ev['label'].mean():.1%}  [B: BE-or-profit]")
    else:
        print("  (no TS_outcomes_* file — legacy fixed-barrier label; re-collect with the patched EA "
              "for realized BE-or-profit labels)")
        ev = label_triple_barrier(ev, px)
    if len(ev) == 0:
        print(f"  SKIP {tag}: 0 events labelled (no price/outcome coverage)."); return (tag, "0 labelled")
    print(f"labeled {len(ev)} events — win rate {ev['label'].mean():.1%}")

    feats = [c for c in ev.columns if c not in NON_FEATURES | {"label"}]

    # --- DEAD-FEATURE GUARD (2026-08-03): never fit on a constant / all-zero column ---
    health = feature_health(ev, feats)
    dead = health[health["DEAD"]]["feature"].tolist()
    if dead:
        print(f"  ** DEAD features (constant/all-zero) DROPPED — they carry no signal and are a "
              f"sign of stale/pre-fix data. Delete + re-COLLECT if unexpected: {dead}")
    feats = [f for f in feats if f not in dead]
    if not feats:
        print(f"  SKIP {tag}: every feature is dead — delete TS_events_*/TS_outcomes_* and re-COLLECT.")
        return (tag, "all features dead")

    n = len(ev); cut = int(n * (1 - TEST_FRACTION))
    train = ev.iloc[:max(0, cut - PURGE_BARS)].reset_index(drop=True)
    test  = ev.iloc[cut:].reset_index(drop=True)
    print(f"train {len(train)} | purge {PURGE_BARS} | test {len(test)}")
    if len(train) == 0 or len(test) == 0:
        print(f"  SKIP {tag}: only {n} labeled events — not enough for a {int(TEST_FRACTION*100)}% "
              f"holdout minus a {PURGE_BARS}-bar purge. Collect more history.")
        return (tag, f"too few ({n})")
    if len(train) < 20 or len(test) < 5:
        print("WARNING: very few events — result is indicative only.")

    sc  = StandardScaler().fit(train[feats].values)
    clf = LogisticRegression(class_weight="balanced", max_iter=1000)
    clf.fit(sc.transform(train[feats].values), train["label"].values)

    ptr = clf.predict_proba(sc.transform(train[feats].values))[:, 1]
    thr_grid = np.linspace(0.30, 0.80, 51)         # each threshold is a TRIAL (Ladder 1 deflates for these)
    best_thr, best_sr = 0.5, -1e9
    for thr in thr_grid:
        taken = train[ptr >= thr]
        if len(taken) < 20: continue
        sr, _ = psr(r_returns(taken))
        if not math.isnan(sr) and sr > best_sr: best_sr, best_thr = sr, thr

    pte = clf.predict_proba(sc.transform(test[feats].values))[:, 1]
    sr_all, _  = psr(r_returns(test))
    sr_gate, _ = psr(r_returns(test[pte >= best_thr]))
    def _pf(rr):
        rr = np.asarray(rr, float); g = rr[rr > 0].sum(); l = -rr[rr < 0].sum()
        return (g / l) if l > 0 else float("inf")
    r_te = r_returns(test); r_gt = r_returns(test[pte >= best_thr])
    ship = (not math.isnan(sr_gate)) and (not math.isnan(sr_all)) and (sr_gate > sr_all)
    print(f"PURGED HOLDOUT + PSR  (NOT deflated — run rrm_validate.py for CPCV / DSR / PBO)")
    print(f"OUT-OF-SAMPLE  thr={best_thr:.3f}  ({len(thr_grid)} thresholds tried)  "
          f"trades {len(test)}->{int((pte>=best_thr).sum())}  R-Sharpe {sr_all:.3f}->{sr_gate:.3f}")
    print(f"PROFITABILITY (realized R)  ungated: {r_te.sum():+.1f}R total, PF {_pf(r_te):.2f}"
          f"   gated: {r_gt.sum():+.1f}R total, PF {_pf(r_gt):.2f}   <- 'are we making money?'")
    print(f"  {'SHIP-candidate' if ship else 'DO NOT SHIP'}: gated {'>' if ship else '<='} ungated on this "
          f"one holdout. Confirm with Ladder 1 (DSR>0.95 & PBO<0.5) before trusting it.")

    key = f"{preset}_{pair}_{tf}" if pair else preset
    model_name = f"MetaModel_{key}.csv"
    body = f"INTERCEPT,{clf.intercept_[0]:.10f}\nTHRESHOLD,{best_thr:.4f}\n" + "".join(
        f"FEATURE,{nm},{m:.10f},{s:.10f},{w:.10f}\n"
        for nm, m, s, w in zip(feats, sc.mean_, sc.scale_, clf.coef_[0]))
    for d in model_target_dirs(ev_path):
        with open(os.path.join(d, model_name), "w") as f:
            f.write(body)
        loc = "terminal MQL5\\Files" if os.sep + "Tester" + os.sep not in d else "agent sandbox"
        print(f"wrote {os.path.join(d, model_name)}  ({loc})")
    return (tag, f"OOS R {sr_all:.2f}->{sr_gate:.2f}, thr {best_thr:.2f}")


# ----------------------------------------------------------------------------- main
def _count_rows(path):
    """Data rows in a CSV (lines minus header). 0 on any error."""
    try:
        with open(path, "r", errors="ignore") as f:
            return max(0, sum(1 for _ in f) - 1)
    except Exception:
        return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--pair"); ap.add_argument("--tf")
    ap.add_argument("--preset"); ap.add_argument("--files-dir", dest="files_dir")
    ap.add_argument("--interactive", action="store_true",
                    help="prompt for values (old behaviour); off by default")
    ap.add_argument("--force", action="store_true",
                    help="retrain everything, even pairs whose model is already up to date")
    ap.add_argument("--check", action="store_true",
                    help="dry-run: report which pairs have events+outcomes and what would happen; writes nothing")
    args = ap.parse_args()

    print("=== rrm_meta.py — Ladder 2 (TRAIN): purged holdout + PSR sanity, then export ===")
    print("    Ladder 1 (rrm_validate.py) is the honest check — run it FIRST.\n")
    files_dir, cfg_pair, cfg_tf, preset = resolve(load_config(), args)

    ev_paths = find_all_events(files_dir, preset)
    if not ev_paths:
        searched = "\n  ".join(_candidate_dirs(files_dir)) or "(no MT5 dirs found)"
        print(f"ERROR: no TS_events_{preset}*.csv found.\nSearched under:\n  {searched}")
        print("Run a COLLECT backtest first (Inp_META_LogFeatures=true), then re-run.")
        sys.exit(1)

    # optional CLI filter: train only the named pair/TF
    if args.pair or args.tf:
        want = f"{args.pair or cfg_pair}_{args.tf or cfg_tf}"
        ev_paths = [p for p in ev_paths if want in os.path.basename(p)]

    print(f"found {len(ev_paths)} events file(s) for preset {preset}:")
    for p in ev_paths:
        print(f"  {os.path.basename(p)}")

    if args.check:
        base = os.path.dirname(ev_paths[0])
        print(f"\n===== CHECK (dry-run) — preset {preset} — nothing will be written =====")
        print(f"folder: {base}\n")
        n_ready = 0
        for ev_path in ev_paths:
            pair, tf = parse_pair_tf(ev_path, preset)
            if pair is None:
                pair, tf = cfg_pair, cfg_tf
            tag  = f"{pair}_{tf}"
            n_ev = _count_rows(ev_path)
            oc   = find_outcomes(files_dir, preset, pair, tf)
            model = os.path.join(os.path.dirname(ev_path),
                                 f"MetaModel_{preset}_{pair}_{tf}.csv" if pair else f"MetaModel_{preset}.csv")
            up_to_date = (os.path.exists(model)
                          and os.path.getmtime(model) >= os.path.getmtime(ev_path)
                          and not (oc and os.path.getmtime(oc) > os.path.getmtime(model)))
            if up_to_date:
                plan = "model up to date -> SKIP (use --force to retrain)"
            elif oc:
                plan = "READY -> trains with REAL outcome label (B)"; n_ready += 1
            else:
                plan = "NO outcomes file -> would FALL BACK to old label; delete events + re-COLLECT with the patched EA"
            oc_str = str(_count_rows(oc)) if oc else "MISSING"
            print(f"  {tag:<14} events={n_ev:<6} outcomes={oc_str:<8} {plan}")
        print(f"\n{len(ev_paths)} pair(s) found, {n_ready} ready to train with B.")
        print("Run `python3 rrm_meta.py` (no --check) to train the READY ones.")
        return

    results = []
    for ev_path in ev_paths:
        pair, tf = parse_pair_tf(ev_path, preset)
        if pair is None:                 # legacy unkeyed file -> fall back to config
            pair, tf = cfg_pair, cfg_tf
        # skip pairs already trained: model newer than its events file (unless --force)
        if not args.force:
            model = os.path.join(os.path.dirname(ev_path),
                                 f"MetaModel_{preset}_{pair}_{tf}.csv" if pair else f"MetaModel_{preset}.csv")
            if os.path.exists(model) and os.path.getmtime(model) >= os.path.getmtime(ev_path):
                # B: the label also depends on the outcomes file — retrain if it is newer than the model.
                oc = find_outcomes(files_dir, preset, pair, tf)
                oc_newer = bool(oc) and os.path.getmtime(oc) > os.path.getmtime(model)
                if not oc_newer:
                    results.append((f"{pair}_{tf}", "up to date — skipped (use --force to retrain)"))
                    continue
        try:
            results.append(train_one(ev_path, pair, tf, preset, files_dir))
        except Exception as e:
            results.append((f"{pair}_{tf}", f"ERROR: {e}"))

    print("\n===================== SUMMARY =====================")
    for tag, msg in results:
        print(f"  {tag:<18} {msg}")
    print("\nThis is a purged-HOLDOUT + PSR sanity read, NOT honest validation.")
    print("Before shipping ANY model: run  python3 rrm_validate.py  (Ladder 1) and")
    print("ship a pair only if it passes there (Deflated Sharpe > 0.95 and PBO < 0.5).")


if __name__ == "__main__":
    main()
