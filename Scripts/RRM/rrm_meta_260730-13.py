#!/usr/bin/env python3
# =============================================================================
# rrm_meta.py  —  RRM EA meta-model trainer (Option 1: logistic regression)
# =============================================================================
# WHAT CHANGED vs the previous version (I/O layer only; the stats core — triple
# barrier, PSR/deflated-Sharpe sweep, purged split, export — is unchanged):
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
                  "sl_dist", "tp_dist", "time_barrier_bars"}

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


def find_events(files_dir, preset):
    target = f"TS_events_{preset}.csv"
    hits = []
    for d in _candidate_dirs(files_dir):
        # recursive: agent folders nest under Tester/Agent-*/MQL5/Files
        hits += glob.glob(os.path.join(d, "**", target), recursive=True)
    hits = sorted(set(hits))
    return _newest(hits), hits


def find_price(files_dir, pair, tf):
    pat = f"{pair}_{tf}_*.csv"
    hits = []
    for d in _candidate_dirs(files_dir):
        hits += glob.glob(os.path.join(d, "**", pat), recursive=True)
    # also the repo's bundled price folders, if the script sits in the repo
    hits += glob.glob(os.path.join(HERE, "..", "_FX-PAIRS_CSV_*", pat))
    hits = sorted(set(os.path.normpath(h) for h in hits))
    return hits


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


def pick_price_for_events(price_paths, ev):
    """Choose the price file that actually covers the events' date span (parse each
    header cheaply); fall back to the largest file."""
    if not price_paths:
        return None
    need_lo, need_hi = ev["event_time"].min(), ev["event_time"].max()
    best, best_cov = None, -1.0
    for p in price_paths:
        try:
            px = read_price(p)
        except Exception:
            continue
        if len(px) == 0:
            continue
        lo, hi = px["time"].min(), px["time"].max()
        cov = (min(hi, need_hi) - max(lo, need_lo)).total_seconds()
        cov = max(cov, 0.0) + len(px) * 1e-6   # tie-break toward more bars
        if cov > best_cov:
            best, best_cov = p, cov
    return best or max(price_paths, key=os.path.getsize)


# ----------------------------------------------------------------------------- labelling (unchanged logic)
def label_triple_barrier(events, px):
    t = px["time"].values; hi = px["high"].values
    lo = px["low"].values; op = px["open"].values
    out = []
    for _, e in events.iterrows():
        idx = int(np.searchsorted(t, np.datetime64(e["event_time"]), side="right"))
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
    r = np.where(sub["label"] == 1,
                 sub["tp_dist"] / sub["sl_dist"].replace(0, np.nan), -1.0)
    return np.nan_to_num(r, nan=0.0)


# ----------------------------------------------------------------------------- main
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--pair"); ap.add_argument("--tf")
    ap.add_argument("--preset"); ap.add_argument("--files-dir", dest="files_dir")
    ap.add_argument("--interactive", action="store_true",
                    help="prompt for values (old behaviour); off by default")
    args = ap.parse_args()

    files_dir, pair, tf, preset = resolve(load_config(), args)

    # ---- locate events ----
    ev_path, ev_hits = find_events(files_dir, preset)
    if not ev_path:
        searched = "\n  ".join(_candidate_dirs(files_dir)) or "(no MT5 dirs found)"
        print(f"ERROR: no TS_events_{preset}.csv found.\nSearched under:\n  {searched}")
        print("Run the COLLECT backtest first (Inp_META_LogFeatures=true), then re-run.")
        sys.exit(1)
    if len(ev_hits) > 1:
        print(f"note: {len(ev_hits)} events files found; using newest:\n  {ev_path}")

    ev = read_events(ev_path)
    print(f"events: {ev_path}\n        {len(ev)} signal events")

    # ---- locate price ----
    price_hits = find_price(files_dir, pair, tf)
    px_path = pick_price_for_events(price_hits, ev)
    if not px_path:
        print(f"ERROR: no {pair}_{tf}_*.csv price file found near the events file.")
        sys.exit(1)
    px = read_price(px_path)
    print(f"price : {px_path}\n        {len(px)} bars "
          f"({px['time'].min()} .. {px['time'].max()})")

    model_out = os.path.join(os.path.dirname(ev_path), f"MetaModel_{preset}.csv")

    # ---- label ----
    ev = label_triple_barrier(ev, px)
    if len(ev) == 0:
        print("ERROR: 0 events fell inside the price series — check pair/TF/date range.")
        sys.exit(1)
    print(f"labeled {len(ev)} events — win rate {ev['label'].mean():.1%}")

    feats = [c for c in ev.columns if c not in NON_FEATURES | {"label"}]
    print(f"{len(feats)} features: {feats}")

    n = len(ev); cut = int(n * (1 - TEST_FRACTION))
    train = ev.iloc[:max(0, cut - PURGE_BARS)].reset_index(drop=True)
    test  = ev.iloc[cut:].reset_index(drop=True)
    print(f"train {len(train)} | purge {PURGE_BARS} | test {len(test)}")
    if len(train) == 0 or len(test) == 0:
        print(f"ERROR: only {n} labeled events — the {int(TEST_FRACTION*100)}% holdout minus a "
              f"{PURGE_BARS}-bar purge leaves no training data.\n"
              f"Collect more history (a full-year M15 COLLECT run yields hundreds of events), "
              f"or lower TEST_FRACTION/PURGE_BARS at the top of this script for a quick check.")
        sys.exit(2)
    if len(train) < 20 or len(test) < 5:
        print("WARNING: very few events — result is indicative only; collect more history.")

    sc = StandardScaler().fit(train[feats].values)
    clf = LogisticRegression(class_weight="balanced", max_iter=1000)
    clf.fit(sc.transform(train[feats].values), train["label"].values)

    ptr = clf.predict_proba(sc.transform(train[feats].values))[:, 1]
    best_thr, best_sr = 0.5, -1e9
    for thr in np.linspace(0.30, 0.80, 51):
        taken = train[ptr >= thr]
        if len(taken) < 20: continue
        sr, _ = psr(r_returns(taken))
        if not math.isnan(sr) and sr > best_sr: best_sr, best_thr = sr, thr

    pte = clf.predict_proba(sc.transform(test[feats].values))[:, 1]
    sr_all, _  = psr(r_returns(test))
    sr_gate, _ = psr(r_returns(test[pte >= best_thr]))
    print("\n================ OUT-OF-SAMPLE ================")
    print(f"threshold             : {best_thr:.3f}")
    print(f"trades  all -> gated  : {len(test)} -> {int((pte>=best_thr).sum())}")
    print(f"R-Sharpe all -> gated : {sr_all:.3f} -> {sr_gate:.3f}")
    print("Reminder: every threshold/feature set you try is a trial — more trials")
    print("make a good number more likely to be luck (deflated Sharpe).")
    print("===============================================\n")

    with open(model_out, "w") as f:
        f.write(f"INTERCEPT,{clf.intercept_[0]:.10f}\n")
        f.write(f"THRESHOLD,{best_thr:.4f}\n")
        for name, m, s, w in zip(feats, sc.mean_, sc.scale_, clf.coef_[0]):
            f.write(f"FEATURE,{name},{m:.10f},{s:.10f},{w:.10f}\n")
    print(f"wrote {model_out}\nShip it only if gated R-Sharpe beat ungated above.")


if __name__ == "__main__":
    main()
