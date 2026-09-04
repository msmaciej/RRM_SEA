#!/usr/bin/env python3
"""
xema_sweep.py — the ANALYSIS layer on top of xema_engine.py

Answers the two questions you actually want:
  1. Is PRESET_XEMA profitable on a given PAIR / TF / PERIOD / SPREAD?
  2. How does changing each SETTING move the result? (find the optimum)

The engine (xema_engine.py) is the faithful part — verified 20/21 vs the
real EA. This wrapper just runs it and summarises. It reports net-R (profit in
risk-multiples), win%, and a per-year breakdown, then sweeps each knob.

USAGE
  # one config, one file:
  python3 xema_sweep.py --data <MT5_H1.csv> --from 2020 --to 2025 --spread 0.4

  # full knob sweep (shows how each setting changes net-R):
  python3 xema_sweep.py --data <MT5_H1.csv> --sweep

  # change a knob:
  python3 xema_sweep.py --data <MT5_H1.csv> --set adx_percentile=55 --set swing_lookback=34
"""
import argparse, copy, sys
import numpy as np, pandas as pd

# import the verified engine
import importlib.util
_spec = importlib.util.spec_from_file_location("eng", "xema_engine.py")
eng = importlib.util.module_from_spec(_spec); sys.modules["eng"] = eng; _spec.loader.exec_module(eng)


def summarise(trades, spread_pips, pip):
    """net-R after spread cost, win%, count, per-year."""
    if not trades:
        return dict(n=0, netR=0.0, win=0.0, peryear={})
    rows = []
    for t in trades:
        # cost = spread on entry side only (SL/TP already in price terms); approx 1 spread per trade
        # expressed in R: spread_pips*pip / R
        R = t["R"]
        cost_R = (spread_pips * pip) / R if R > 0 else 0.0
        net = t["r"] - cost_R
        rows.append((t["entry_time"].year, net, t["r"]))
    net = np.array([r[1] for r in rows])
    peryear = {}
    for y, nr, _ in rows:
        peryear[y] = peryear.get(y, 0.0) + nr
    return dict(n=len(rows), netR=float(net.sum()),
                win=float(100 * np.mean([r[2] > 0 for r in rows])),
                peryear={y: round(v, 1) for y, v in sorted(peryear.items())})


def analyze(df, cfg, spread_pips):
    res = eng.run(df, cfg)
    return summarise(res["trades"], spread_pips, cfg["pip"])


def fmt_year(py):
    if not py:
        return "(no trades)"
    return "  ".join(f"{y}:{v:+.0f}" for y, v in py.items()) + f"   | tot {sum(py.values()):+.0f}"


def one(df, cfg, spread_pips, label="config"):
    s = analyze(df, cfg, spread_pips)
    print(f"\n{label}")
    print(f"  net-R {s['netR']:+.1f}   trades {s['n']}   win {s['win']:.0f}%   (spread {spread_pips}p)")
    print(f"  per-year: {fmt_year(s['peryear'])}")
    return s


# ── the knob sweep: each row is a variant, showing how it moves net-R ─────────
def sweep(df, base_cfg, spread_pips):
    variants = [
        ("as-run base (EMA13/34)",   {}),
        ("EMA 8/21",                 dict(ema_fast=8,  ema_slow=21)),
        ("EMA 20/50",                dict(ema_fast=20, ema_slow=50)),
        ("EMA 21/55",                dict(ema_fast=21, ema_slow=55)),
        ("ADX pct 40",               dict(adx_percentile=40.0)),
        ("ADX pct 55",               dict(adx_percentile=55.0)),
        ("ADX pct 60",               dict(adx_percentile=60.0)),
        ("PSAR 0.02/0.2",            dict(psar_step=0.02, psar_max=0.2)),
        ("PSAR 0.05/0.5",            dict(psar_step=0.05, psar_max=0.5)),
        ("swing 34",                 dict(swing_lookback=34)),
        ("swing 20",                 dict(swing_lookback=20)),
        ("RR 1.0",                   dict(label_rr=1.0)),
        ("RR 1.5",                   dict(label_rr=1.5)),
        ("RR 2.0",                   dict(label_rr=2.0)),
        ("RR 3.0",                   dict(label_rr=3.0)),
        ("session all hours",        dict(session_allowed=set(range(0, 24)))),
    ]
    print(f"\n{'variant':26s}{'net-R':>8}{'trades':>8}{'win%':>7}   per-year")
    print("-" * 92)
    for label, ov in variants:
        cfg = copy.deepcopy(base_cfg)
        cfg.update(ov)
        s = analyze(df, cfg, spread_pips)
        print(f"{label:26s}{s['netR']:>+8.1f}{s['n']:>8d}{s['win']:>7.0f}   {fmt_year(s['peryear'])}")
    print("\nnote: net-R is a RANKING measure (risk-multiples after spread), not EA P/L to the cent.")


def parse_set(pairs):
    """--set key=value overrides, typed sensibly."""
    out = {}
    for p in pairs or []:
        k, v = p.split("=", 1)
        if k == "session_allowed":
            out[k] = set(int(x) for x in v.split(","))
        elif "." in v or k in ("adx_percentile", "psar_step", "psar_max", "bb_dev",
                                "ci_ranging", "label_rr", "t_adx", "sl_cushion_pips"):
            out[k] = float(v)
        else:
            try: out[k] = int(v)
            except ValueError: out[k] = v
    return out


def main():
    ap = argparse.ArgumentParser(description="XEMA analysis/sweep on top of the verified engine")
    ap.add_argument("--data", required=True, help="MT5 H1 CSV (tab-delimited export)")
    ap.add_argument("--from", dest="frm", default=None, help="start year or YYYY-MM-DD")
    ap.add_argument("--to", dest="to", default=None, help="end year or YYYY-MM-DD")
    ap.add_argument("--spread", type=float, default=0.4, help="spread in pips for cost (default 0.4)")
    ap.add_argument("--pip", type=float, default=None, help="override pip size (JPY=0.01, gold=0.1)")
    ap.add_argument("--sweep", action="store_true", help="run the per-knob table")
    ap.add_argument("--set", action="append", help="override a knob, e.g. --set adx_percentile=55")
    a = ap.parse_args()

    df = eng.load_mt5(a.data)
    # period filter
    def bound(x):
        if x is None: return None
        return pd.Timestamp(x if "-" in str(x) else f"{x}-01-01")
    lo, hi = bound(a.frm), bound(a.to)
    if hi is not None and "-" not in str(a.to):  # a bare year means through end of that year
        hi = pd.Timestamp(f"{int(a.to)}-12-31 23:59")
    if lo is not None: df = df[df.index >= lo]
    if hi is not None: df = df[df.index <= hi]

    cfg = copy.deepcopy(eng.CFG)
    if a.pip: cfg["pip"] = a.pip
    cfg.update(parse_set(a.set))

    span = f"{df.index[0].date()} → {df.index[-1].date()}  ({len(df)} bars)"
    print(f"=== XEMA on {a.data.split('/')[-1]} ===\n{span}")

    if a.sweep:
        sweep(df, cfg, a.spread)
    else:
        one(df, cfg, a.spread, "as-run config")


if __name__ == "__main__":
    main()
