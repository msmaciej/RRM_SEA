#!/usr/bin/env python3
"""
xema_report2.py — the report format you already know, on the VERIFIED engine.

Produces the two-halves sweep you've seen before:
  - every knob swept, each row a full backtest
  - EARLY half and RECENT half side by side (out-of-sample check)
  - DECADE total + a robustness verdict (consistent vs lopsided)
  - powered by xema_engine_260903-01.py, which matches the real EA 20/21

USAGE (give the two history halves for one pair/TF):
  python3 xema_report2.py \
     --early  EURUSD_H1_2015-2019.csv \
     --recent EURUSD_H1_2020-2025.csv \
     --pip 0.0001 --spread 0.4 --out report_EURUSD_H1.md
"""
import argparse, copy, sys, importlib.util, datetime
import numpy as np, pandas as pd

_spec = importlib.util.spec_from_file_location("eng", "xema_engine_260903-01.py")
eng = importlib.util.module_from_spec(_spec); sys.modules["eng"] = eng; _spec.loader.exec_module(eng)


def netR(df, base, ov, spread, pip):
    cfg = copy.deepcopy(base); cfg["pip"] = pip; cfg.update(ov)
    trades = eng.run(df, cfg)["trades"]
    if not trades:
        return 0.0, 0
    tot = 0.0
    for t in trades:
        R = t["R"]; cost = (spread*pip)/R if R > 0 else 0.0
        tot += t["r"] - cost
    return round(tot, 1), len(trades)


def verdict(e, r):
    """consistent if both halves same sign & similar; lopsided if one half carries it."""
    if e > 0 and r > 0:
        return "consistent ✓"
    if e <= 0 and r <= 0:
        return "negative"
    # opposite signs -> lopsided
    return "lopsided"


VARIANTS = [
    ("— entry EMA —", None, None),
    ("EMA 8/21",        dict(ema_fast=8,  ema_slow=21)),
    ("EMA 13/34 (base)",dict(ema_fast=13, ema_slow=34)),
    ("EMA 20/50",       dict(ema_fast=20, ema_slow=50)),
    ("EMA 21/55",       dict(ema_fast=21, ema_slow=55)),
    ("— ADX gate —", None, None),
    ("ADX OFF",         dict(use_adx=False)),
    ("ADX pct 40",      dict(adx_percentile=40.0)),
    ("ADX pct 50 (base)",dict(adx_percentile=50.0)),
    ("ADX pct 60",      dict(adx_percentile=60.0)),
    ("ADX pct 70",      dict(adx_percentile=70.0)),
    ("— PSAR —", None, None),
    ("PSAR OFF",        dict(use_psar=False)),
    ("PSAR 0.02/0.2",   dict(psar_step=0.02, psar_max=0.2)),
    ("PSAR 0.08/0.5 (base)",dict(psar_step=0.08, psar_max=0.5)),
    ("— voters —", None, None),
    ("BB OFF",          dict(use_bb=False)),
    ("BB period 30",    dict(bb_period=30)),
    ("CI OFF",          dict(use_ci=False)),
    ("CI thr 55",       dict(ci_ranging=55.0)),
    ("HTF OFF",         dict(use_htf=False)),
    ("HTF ON (base)",   dict(use_htf=True)),
    ("— stop / target —", None, None),
    ("swing 34",        dict(swing_lookback=34)),
    ("swing 55 (base)", dict(swing_lookback=55)),
    ("swing 89",        dict(swing_lookback=89)),
    ("RR 1.5",          dict(label_rr=1.5)),
    ("RR 2.0",          dict(label_rr=2.0)),
    ("RR 2.5 (base)",   dict(label_rr=2.5)),
    ("RR 3.0",          dict(label_rr=3.0)),
    ("— session —", None, None),
    ("all hours",       dict(session_allowed=set(range(0, 24)))),
    ("1-21 (base)",     dict(session_allowed=set(range(1, 22)))),
    ("NY 13-22",        dict(session_allowed=set(range(13, 23)))),
]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--early", required=True, help="early-half CSV (e.g. 2015-2019)")
    ap.add_argument("--recent", required=True, help="recent-half CSV (e.g. 2020-2025)")
    ap.add_argument("--pip", type=float, default=0.0001)
    ap.add_argument("--spread", type=float, default=0.4)
    ap.add_argument("--label", default=None, help="pair/TF label for the title")
    ap.add_argument("--out", default=None)
    a = ap.parse_args()

    de = eng.load_mt5(a.early); dr = eng.load_mt5(a.recent)
    e_span = f"{de.index[0].date()}→{de.index[-1].date()}"
    r_span = f"{dr.index[0].date()}→{dr.index[-1].date()}"
    label = a.label or a.recent.split("/")[-1]
    base = copy.deepcopy(eng.CFG)

    L = []
    L.append(f"# PRESET_XEMA sweep — {label}")
    L.append(f"early half {e_span} · recent half {r_span} · spread {a.spread}p · pip {a.pip} "
             f"· engine 260903-01 (verified 20/21 vs EA) · {datetime.date.today()}\n")
    L.append("Every row is a full backtest. **EARLY** is the out-of-sample check (settings were "
             "never tuned to it). **consistent ✓** = positive in both halves (robust); "
             "**lopsided** = one half carries it (regime fit, don't trust). net-R after spread; "
             "ranks configs, not EA P/L to the cent.\n")
    L.append("| setting | EARLY | RECENT | DECADE | n(rec) | verdict |")
    L.append("|---|---:|---:|---:|---:|---|")

    for row in VARIANTS:
        if row[1] is None:  # section header
            L.append(f"| **{row[0]}** | | | | | |")
            continue
        label_v, ov = row[0], row[1]
        e, _ = netR(de, base, ov, a.spread, a.pip)
        r, nr = netR(dr, base, ov, a.spread, a.pip)
        L.append(f"| {label_v} | {e:+.0f} | {r:+.0f} | {e+r:+.0f} | {nr} | {verdict(e, r)} |")

    # summary: robust improvements only (consistent AND better than base decade)
    baseE, _ = netR(de, base, {}, a.spread, a.pip)
    baseR, _ = netR(dr, base, {}, a.spread, a.pip)
    base_dec = baseE + baseR
    robust = []
    for row in VARIANTS:
        if row[1] is None: continue
        e, _ = netR(de, base, row[1], a.spread, a.pip)
        r, _ = netR(dr, base, row[1], a.spread, a.pip)
        if e > 0 and r > 0 and (e+r) > base_dec + 1 and "base" not in row[0]:
            robust.append((row[0], e, r, e+r))
    L.append(f"\n## Robust improvements (positive in BOTH halves AND better than base {base_dec:+.0f})")
    if robust:
        for name, e, r, d in sorted(robust, key=lambda x: -x[3]):
            L.append(f"- **{name}**: {e:+.0f}/{r:+.0f} → {d:+.0f} decade")
    else:
        L.append("- none — the base config sits on the robust plateau; every 'higher total' "
                 "alternative is lopsided (a regime fit). Keep the base.")
    L.append("\n_Reminder: confirm any change in the real MT5 tester before trusting it live._")

    out = a.out or f"report2_{label.replace('.csv','')}.md"
    text = "\n".join(L); open(out, "w").write(text)
    print(text); print(f"\n[written to {out}]")


if __name__ == "__main__":
    main()
