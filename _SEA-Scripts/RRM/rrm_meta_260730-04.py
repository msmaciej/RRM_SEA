#!/usr/bin/env python3
# =============================================================================
# rrm_meta.py  —  RRM EA meta-model trainer (Option 1: logistic regression)
# =============================================================================
# Lives wherever YOU want (e.g. your repo's scripts/ folder). It does NOT need
# to sit under the MT5/Wine tree — it only needs to be TOLD the path to the
# terminal's Common\Files folder, which it reads from rrm_meta.config (next to
# this file) so you never paste the long Wine path again.
#
# ONE script for the whole EA and ALL presets (feature columns auto-detected).
# Train a separate model per preset just by changing the preset name.
#
# FILE-NAME CONVENTION (all in Common\Files):
#   INPUT  price  : PAIR_TF_FROM_TO.csv      e.g. USDJPY_M15_240101_241231.csv
#   INPUT  events : TS_events_<PRESET>.csv    (EA writes it, COLLECT mode)
#   OUTPUT model  : MetaModel_<PRESET>.csv    (EA reads it)
#
# RUN:            python3 scripts/rrm_meta.py
#                 (edit rrm_meta.config once; then just run and press Enter)
# INSTALL ONCE:   pip install pandas numpy scikit-learn
# =============================================================================

import os, math, argparse, configparser
import numpy as np
import pandas as pd
from sklearn.linear_model import LogisticRegression
from sklearn.preprocessing import StandardScaler

HERE = os.path.dirname(os.path.abspath(__file__))
CONFIG_PATH = os.path.join(HERE, "rrm_meta.config")

# static knobs (rarely change)
PRICE_TIME, PRICE_OPEN, PRICE_HIGH, PRICE_LOW = "time", "open", "high", "low"
TIME_FORMAT   = None
COST_PRICE    = 0.0
TEST_FRACTION = 0.30
PURGE_BARS    = 50
NON_FEATURES  = {"event_time", "symbol", "preset", "direction",
                 "sl_dist", "tp_dist", "time_barrier_bars"}


def load_config():
    d = {}
    if os.path.exists(CONFIG_PATH):
        cp = configparser.ConfigParser()
        cp.read(CONFIG_PATH)
        if cp.has_section("meta"):
            d = dict(cp.items("meta"))
    return d


def resolve(cfg):
    """CLI flag > config file > interactive prompt."""
    ap = argparse.ArgumentParser()
    ap.add_argument("--pair"); ap.add_argument("--tf")
    ap.add_argument("--from", dest="frm"); ap.add_argument("--to")
    ap.add_argument("--preset"); ap.add_argument("--files-dir")
    a = ap.parse_args()

    def pick(flag, key, prompt, default):
        val = flag or cfg.get(key) or default
        typed = input(f"{prompt} [{val}]: ").strip()
        return typed or val

    files_dir = pick(a.files_dir, "files_dir", "MT5 Common/Files folder",
                     "/CHANGE/ME/MetaQuotes/Terminal/Common/Files")
    pair   = pick(a.pair,   "pair",   "Pair",       "USDJPY")
    tf     = pick(a.tf,     "tf",     "Timeframe",  "M15")
    frm    = pick(a.frm,    "from",   "From YYMMDD","240101")
    to     = pick(a.to,     "to",     "To   YYMMDD","241231")
    preset = pick(a.preset, "preset", "Preset",     "RRM_ORG")
    return files_dir, pair, tf, frm, to, preset


def label_triple_barrier(events, px):
    t = px[PRICE_TIME].values; hi = px[PRICE_HIGH].values
    lo = px[PRICE_LOW].values; op = px[PRICE_OPEN].values
    out = []
    for _, e in events.iterrows():
        idx = np.searchsorted(t, np.datetime64(e["event_time"]), side="right")
        if idx >= len(px) - 1:
            out.append(np.nan); continue
        entry = op[idx]; d = float(e["direction"])
        tp = entry + d * (float(e["tp_dist"]) + COST_PRICE)
        sl = entry - d * (float(e["sl_dist"]))
        tmax = int(e["time_barrier_bars"]); lab = 0
        for k in range(idx, min(idx + tmax, len(px))):
            hit_tp = (hi[k] >= tp) if d > 0 else (lo[k] <= tp)
            hit_sl = (lo[k] <= sl) if d > 0 else (hi[k] >= sl)
            if hit_tp and hit_sl: lab = 0; break
            if hit_tp:            lab = 1; break
            if hit_sl:            lab = 0; break
        out.append(lab)
    events = events.copy(); events["label"] = out
    events = events.dropna(subset=["label"]).reset_index(drop=True)
    events["label"] = events["label"].astype(int)
    return events


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


def main():
    files_dir, pair, tf, frm, to, preset = resolve(load_config())
    price_csv  = f"{pair}_{tf}_{frm}_{to}.csv"
    events_csv = f"TS_events_{preset}.csv"
    model_out  = f"MetaModel_{preset}.csv"
    P = lambda f: os.path.join(files_dir, f)
    print(f"\nprice : {price_csv}\nevents: {events_csv}\nmodel : {model_out}\n")

    ev = pd.read_csv(P(events_csv))
    ev["event_time"] = pd.to_datetime(ev["event_time"], format=TIME_FORMAT)
    ev = ev.sort_values("event_time").reset_index(drop=True)
    print(f"Loaded {len(ev)} signal events")

    px = pd.read_csv(P(price_csv))
    px[PRICE_TIME] = pd.to_datetime(px[PRICE_TIME], format=TIME_FORMAT)
    px = px.sort_values(PRICE_TIME).reset_index(drop=True)
    print(f"Loaded {len(px)} price bars")

    ev = label_triple_barrier(ev, px)
    print(f"Labeled {len(ev)} events — win rate {ev['label'].mean():.1%}")

    feats = [c for c in ev.columns if c not in NON_FEATURES | {"label"}]
    print(f"{len(feats)} features: {feats}")

    n = len(ev); cut = int(n * (1 - TEST_FRACTION))
    train = ev.iloc[:max(0, cut - PURGE_BARS)].reset_index(drop=True)
    test  = ev.iloc[cut:].reset_index(drop=True)
    print(f"train {len(train)} | purge {PURGE_BARS} | test {len(test)}")

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

    with open(P(model_out), "w") as f:
        f.write(f"INTERCEPT,{clf.intercept_[0]:.10f}\n")
        f.write(f"THRESHOLD,{best_thr:.4f}\n")
        for name, m, s, w in zip(feats, sc.mean_, sc.scale_, clf.coef_[0]):
            f.write(f"FEATURE,{name},{m:.10f},{s:.10f},{w:.10f}\n")
    print(f"Wrote {model_out}. Ship it only if gated R-Sharpe beat ungated above.")


if __name__ == "__main__":
    main()
