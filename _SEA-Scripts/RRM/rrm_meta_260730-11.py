#!/usr/bin/env python3
# =============================================================================
# rrm_meta.py — RRM EA meta-model trainer (fully automatic)
# =============================================================================
# Just run:   python3 rrm_meta.py
# No config, no paths to remember. It AUTO-FINDS the TS_events CSV the tester
# wrote (even inside a Tester/Agent sandbox), auto-finds the matching price
# CSV, trains, prints the result, and writes MetaModel_<PRESET>.csv next to
# the events file. Optional overrides: --preset RRM_ORG --mt5 /path/to/drive_c
# =============================================================================
import os, sys, glob, math, argparse
import numpy as np
import pandas as pd
from sklearn.linear_model import LogisticRegression
from sklearn.preprocessing import StandardScaler

# ---- where MT5 lives (auto-detected; override with --mt5) ----
DEFAULT_MT5 = os.path.expanduser(
    "~/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c")

PRICE_TIME, PRICE_OPEN, PRICE_HIGH, PRICE_LOW = "time", "open", "high", "low"
TIME_FORMAT   = None
COST_PRICE    = 0.0
TEST_FRACTION = 0.30
PURGE_BARS    = 50
NON_FEATURES  = {"event_time","symbol","preset","direction",
                 "sl_dist","tp_dist","time_barrier_bars"}


def newest(paths):
    return max(paths, key=os.path.getmtime) if paths else None


def find_events(mt5_root, preset):
    """Search the whole MT5 tree for TS_events_<preset>.csv, newest wins."""
    hits = glob.glob(os.path.join(mt5_root, "**", f"TS_events_{preset}.csv"),
                     recursive=True)
    return newest(hits)


def find_price(mt5_root, events_dir):
    """Prefer a price CSV next to the events file; else newest matching one anywhere."""
    local = glob.glob(os.path.join(events_dir, "*_M*_*_*.csv"))
    local = [p for p in local if "TS_events" not in os.path.basename(p)
             and "MetaModel" not in os.path.basename(p)]
    if local:
        return newest(local)
    anywhere = glob.glob(os.path.join(mt5_root, "**", "*_M*_*_*.csv"), recursive=True)
    anywhere = [p for p in anywhere if os.path.basename(p)[0].isalpha()
                and "TS_events" not in p and "MetaModel" not in p]
    return newest(anywhere)


def label_triple_barrier(ev, px):
    t = px[PRICE_TIME].values; hi = px[PRICE_HIGH].values
    lo = px[PRICE_LOW].values; op = px[PRICE_OPEN].values
    out = []
    for _, e in ev.iterrows():
        idx = np.searchsorted(t, np.datetime64(e["event_time"]), side="right")
        if idx >= len(px) - 1: out.append(np.nan); continue
        entry = op[idx]; d = float(e["direction"])
        tp = entry + d * (float(e["tp_dist"]) + COST_PRICE)
        sl = entry - d * (float(e["sl_dist"]))
        tmax = int(e["time_barrier_bars"]); lab = 0
        for k in range(idx, min(idx + tmax, len(px))):
            hit_tp = (hi[k] >= tp) if d > 0 else (lo[k] <= tp)
            hit_sl = (lo[k] <= sl) if d > 0 else (hi[k] >= sl)
            if hit_tp and hit_sl: lab = 0; break
            if hit_tp: lab = 1; break
            if hit_sl: lab = 0; break
        out.append(lab)
    ev = ev.copy(); ev["label"] = out
    ev = ev.dropna(subset=["label"]).reset_index(drop=True)
    ev["label"] = ev["label"].astype(int)
    return ev


def normal_cdf(x): return 0.5 * (1.0 + math.erf(x / math.sqrt(2.0)))

def psr(r, bench=0.0):
    r = np.asarray(r, float); n = len(r)
    if n < 3 or r.std(ddof=1) == 0: return float("nan"), float("nan")
    sr = r.mean() / r.std(ddof=1)
    sk = pd.Series(r).skew(); ku = pd.Series(r).kurt() + 3.0
    denom = math.sqrt(max(1e-12, 1 - sk*sr + (ku-1)/4.0*sr*sr))
    return sr, normal_cdf((sr - bench) * math.sqrt(n-1) / denom)

def r_returns(sub):
    r = np.where(sub["label"] == 1,
                 sub["tp_dist"] / sub["sl_dist"].replace(0, np.nan), -1.0)
    return np.nan_to_num(r, nan=0.0)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--preset", default="RRM_ORG")
    ap.add_argument("--mt5", default=DEFAULT_MT5)
    a = ap.parse_args()

    print(f"Searching for TS_events_{a.preset}.csv under MT5 ...")
    events_path = find_events(a.mt5, a.preset)
    if not events_path:
        sys.exit(f"ERROR: no TS_events_{a.preset}.csv found. "
                 f"Run the COLLECT backtest first (Inp_META_LogFeatures=true).")
    events_dir = os.path.dirname(events_path)
    print(f"  events : {events_path}")

    price_path = find_price(a.mt5, events_dir)
    if not price_path:
        sys.exit("ERROR: no price CSV (PAIR_TF_FROM_TO.csv) found.")
    print(f"  price  : {price_path}")

    model_path = os.path.join(events_dir, f"MetaModel_{a.preset}.csv")
    print(f"  model  : {model_path}\n")

    ev = pd.read_csv(events_path)
    ev["event_time"] = pd.to_datetime(ev["event_time"], format=TIME_FORMAT)
    ev = ev.sort_values("event_time").reset_index(drop=True)
    px = pd.read_csv(price_path)
    px[PRICE_TIME] = pd.to_datetime(px[PRICE_TIME], format=TIME_FORMAT)
    px = px.sort_values(PRICE_TIME).reset_index(drop=True)
    print(f"Loaded {len(ev)} events, {len(px)} price bars")

    ev = label_triple_barrier(ev, px)
    print(f"Labeled {len(ev)} events — win rate {ev['label'].mean():.1%}")

    feats = [c for c in ev.columns if c not in NON_FEATURES | {"label"}]
    n = len(ev); cut = int(n * (1 - TEST_FRACTION))
    train = ev.iloc[:max(0, cut - PURGE_BARS)].reset_index(drop=True)
    test  = ev.iloc[cut:].reset_index(drop=True)

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
    print("===============================================\n")

    with open(model_path, "w") as f:
        f.write(f"INTERCEPT,{clf.intercept_[0]:.10f}\n")
        f.write(f"THRESHOLD,{best_thr:.4f}\n")
        for name, m, s, w in zip(feats, sc.mean_, sc.scale_, clf.coef_[0]):
            f.write(f"FEATURE,{name},{m:.10f},{s:.10f},{w:.10f}\n")
    print(f"Wrote {model_path}")
    print("Ship it only if gated R-Sharpe beat ungated above.")


if __name__ == "__main__":
    main()
