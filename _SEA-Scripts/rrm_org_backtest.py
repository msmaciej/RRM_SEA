#!/usr/bin/env python3
# =============================================================================
# rrm_org_backtest.py
# -----------------------------------------------------------------------------
# A/B test: does adding the proposed over-extension / chop / divergence gates to
# BASE PRESET_RRM_ORG improve trade outcomes on EURUSD H1 2026?
#
# Method (matches the operator's spec):
#   * signal   : BASE RRM_ORG TS=1 candidate (approximation via rrm_org_discriminator;
#                the layer pullback machine is approximate, the gate features are exact)
#   * entry    : next-bar OPEN after the signal bar (TE at shift=0)
#   * SL       : last swing (lowest low / highest high over SWING_LB bars) + cushion
#   * TP       : entry +/- RR * |entry-SL|   for RR in {1.0, 1.5, 2.0}
#   * outcome  : walk forward bar-by-bar; TP-first = WIN, SL-first = LOSS.
#                If a bar touches BOTH, count SL first (conservative). No trailing.
#   * position : one at a time (flat -> take next qualifying signal). This also
#                de-clusters adjacent same-move signals.
#   * expectancy: E[R] = win% * RR - (1-win%) * 1     (loss = -1R by construction)
#
# Compares gate stacks so we see which gate earns its removal, not just that it cuts.
# =============================================================================
import importlib.util, argparse
import numpy as np, pandas as pd

spec = importlib.util.spec_from_file_location("disc", "rrm_org_discriminator.py")
disc = importlib.util.module_from_spec(spec); spec.loader.exec_module(disc)
PIP = 0.0001

SWING_LB   = 12      # bars scanned back for the last swing
SL_CUSHION = 2*PIP   # buffer beyond the swing
SL_MIN     = 5*PIP   # floor on SL distance (avoid degenerate tiny stops)

# ---- gate stacks to compare (H1-appropriate thresholds) ----
GATES = {
 "BASE (no added gates)"          : dict(),
 "+FAN>60p"                        : dict(fan=60),
 "+FAN +CLIMAX"                    : dict(fan=60, climax=True),
 "+FAN +CLIMAX +ADX>=23"          : dict(fan=60, climax=True, adx=23),
 "+FAN +CLIMAX +ADX +CI +EXT +DIV": dict(fan=60, climax=True, adx=23, ci=61.8, ext=2.5, div=True),
}

def passes(e, g):
    if "fan"    in g and e["FANpips"]  > g["fan"]:  return False
    if "adx"    in g and e["ADX"]      < g["adx"]:  return False
    if "ci"     in g and e["CHOP"]     > g["ci"]:   return False
    if "ext"    in g and e["EXTxATR"]  > g["ext"]:  return False
    if g.get("climax") and (e["BARxATR"] > 2.0 or e["MOVExATR"] > 3.0): return False
    if g.get("div")   and e["DPIdiv"]:  return False
    return True

def last_swing(d, i, lng):
    w = d.iloc[i-SWING_LB:i+1]
    return (w["low"].min() if lng else w["high"].max())

def outcome(d, entry_i, entry, sl, tp, lng):
    for j in range(entry_i, len(d)):
        hi, lo = d["high"].iloc[j], d["low"].iloc[j]
        if lng:
            if lo <= sl: return "L", j
            if hi >= tp: return "W", j
        else:
            if hi >= sl: return "L", j
            if lo <= tp: return "W", j
    return "OPEN", len(d)-1

def run(d, gate, rr):
    i, n = 91, len(d)
    trades = []
    while i < n-1:
        e = disc.evaluate_bar(d, i, rr)
        if not e.get("ts1") or not passes(e, gate):
            i += 1; continue
        lng = e["bias"] > 0
        entry_i = i+1
        entry = d["open"].iloc[entry_i]
        sw = last_swing(d, i, lng)
        sldist = max(abs(entry - sw) + SL_CUSHION, SL_MIN)
        sl = entry - sldist if lng else entry + sldist
        tp = entry + rr*sldist if lng else entry - rr*sldist
        res, exit_i = outcome(d, entry_i, entry, sl, tp, lng)
        if res != "OPEN":
            trades.append((d.index[i], "L" if lng else "S", res, sldist/PIP))
            i = exit_i + 1          # flat again after exit
        else:
            i += 1
    return trades

def summarize(trades, rr):
    res = [t[2] for t in trades]
    w, l = res.count("W"), res.count("L")
    tot = w + l
    if tot == 0: return dict(n=0, win=0.0, exp=0.0, netR=0.0)
    win = w/tot
    exp = win*rr - (1-win)*1.0
    return dict(n=tot, win=100*win, exp=exp, netR=exp*tot)

# ---- independent per-signal eval (overlap allowed, de-clustered by cooldown) ----
COOLDOWN = 6
def collect_independent(d, rr):
    """Every base candidate, de-clustered, each scored independently."""
    out = []; last = -10**9
    for i in range(91, len(d)-1):
        e = disc.evaluate_bar(d, i, rr)
        if not e.get("ts1"): continue
        if i - last < COOLDOWN: continue
        last = i
        lng = e["bias"] > 0
        entry = d["open"].iloc[i+1]
        sw = last_swing(d, i, lng)
        sldist = max(abs(entry-sw)+SL_CUSHION, SL_MIN)
        sl = entry-sldist if lng else entry+sldist
        tp = entry+rr*sldist if lng else entry-rr*sldist
        res,_ = outcome(d, i+1, entry, sl, tp, lng)
        if res == "OPEN": continue
        e["win"] = (res=="W"); out.append(e)
    return out

SINGLE = {"FAN>60p":dict(fan=60), "CLIMAX":dict(climax=True), "ADX>=23":dict(adx=23),
          "CI<=61.8":dict(ci=61.8), "EXT<=2.5":dict(ext=2.5), "DPIdiv-block":dict(div=True)}

def wr(rows):
    n=len(rows); w=sum(r["win"] for r in rows)
    return n, (100*w/n if n else 0.0)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("csv")
    ap.add_argument("--resample", default=None)
    a = ap.parse_args()
    df = disc.load_csv(a.csv, a.resample)
    d  = disc.build(df)
    print(f"# {len(d)} bars  {d.index[0]} -> {d.index[-1]}  (TF={'native' if not a.resample else a.resample})")
    print(f"# SL=last swing over {SWING_LB} bars +{SL_CUSHION/PIP:.0f}p cushion, floor {SL_MIN/PIP:.0f}p; no trailing.")
    print("# NOTE: base TS=1 is an APPROXIMATION of the EA, not its authoritative signal set.\n")

    print("############ A) SEQUENTIAL (one position at a time) ############")
    for rr in (1.0, 1.5, 2.0):
        print(f"================  RR = {rr:g}:1  ================")
        print(f"{'gate stack':34s}{'trades':>7}{'win%':>8}{'E[R]':>8}{'netR':>9}{'vs base':>9}")
        base_n = None
        for name, g in GATES.items():
            s = summarize(run(d, g, rr), rr)
            if base_n is None: base_n = s["n"]
            dd = s["n"]-base_n
            tag = "" if dd==0 else (f"+{dd}" if dd>0 else f"{dd}")
            print(f"{name:34s}{s['n']:>7}{s['win']:>8.1f}{s['exp']:>+8.2f}{s['netR']:>+9.1f}{tag:>9}")
        print()

    print("############ B) PER-GATE: does it cut LOSERS? (independent, de-clustered) ############")
    print("#  a gate earns its place only if REMOVED win% < KEPT win%\n")
    for rr in (1.0, 1.5, 2.0):
        cand = collect_independent(d, rr)
        bn, bw = wr(cand)
        print(f"---- RR {rr:g}:1 | base candidates n={bn}, win%={bw:.1f}, E[R]={bw/100*rr-(1-bw/100):+.2f} ----")
        print(f"{'gate':16s}{'KEPT n':>8}{'KEPT win%':>11}{'REMOVED n':>11}{'REM win%':>10}{'verdict':>10}")
        for name, g in SINGLE.items():
            kept   = [r for r in cand if passes(r,g)]
            remov  = [r for r in cand if not passes(r,g)]
            kn,kw = wr(kept); rn,rw = wr(remov)
            verdict = "helps" if (rn>0 and rw < kw) else ("—" if rn==0 else "hurts")
            print(f"{name:16s}{kn:>8}{kw:>11.1f}{rn:>11}{rw:>10.1f}{verdict:>10}")
        print()

if __name__ == "__main__":
    main()
