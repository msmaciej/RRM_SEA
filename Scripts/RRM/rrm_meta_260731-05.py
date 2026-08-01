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

    ev = label_triple_barrier(ev, px)
    if len(ev) == 0:
        print(f"  SKIP {tag}: 0 events fell inside the price series (check dates)."); return (tag, "0 in-range")
    print(f"labeled {len(ev)} events — win rate {ev['label'].mean():.1%}")

    feats = [c for c in ev.columns if c not in NON_FEATURES | {"label"}]
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
    best_thr, best_sr = 0.5, -1e9
    for thr in np.linspace(0.30, 0.80, 51):
        taken = train[ptr >= thr]
        if len(taken) < 20: continue
        sr, _ = psr(r_returns(taken))
        if not math.isnan(sr) and sr > best_sr: best_sr, best_thr = sr, thr

    pte = clf.predict_proba(sc.transform(test[feats].values))[:, 1]
    sr_all, _  = psr(r_returns(test))
    sr_gate, _ = psr(r_returns(test[pte >= best_thr]))
    print(f"OUT-OF-SAMPLE  thr={best_thr:.3f}  trades {len(test)}->{int((pte>=best_thr).sum())}  "
          f"R-Sharpe {sr_all:.3f}->{sr_gate:.3f}")

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
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--pair"); ap.add_argument("--tf")
    ap.add_argument("--preset"); ap.add_argument("--files-dir", dest="files_dir")
    ap.add_argument("--interactive", action="store_true",
                    help="prompt for values (old behaviour); off by default")
    ap.add_argument("--force", action="store_true",
                    help="retrain everything, even pairs whose model is already up to date")
    args = ap.parse_args()

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
                results.append((f"{pair}_{tf}", "up to date — skipped (use --force to retrain)"))
                continue
        try:
            results.append(train_one(ev_path, pair, tf, preset, files_dir))
        except Exception as e:
            results.append((f"{pair}_{tf}", f"ERROR: {e}"))

    print("\n===================== SUMMARY =====================")
    for tag, msg in results:
        print(f"  {tag:<18} {msg}")
    print("Ship a model only if its gated R-Sharpe beat ungated (out-of-sample).")


if __name__ == "__main__":
    main()
