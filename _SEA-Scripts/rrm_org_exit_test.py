#!/usr/bin/env python3
# =============================================================================
# rrm_org_exit_test.py
# -----------------------------------------------------------------------------
# Compare EXIT strategies for BASE PRESET_RRM_ORG signals on EURUSD 2025, H1 & M15.
#
#   signal : BASE RRM_ORG TS=1 (approximation via rrm_org_discriminator; layer
#            machine approximate, indicator features exact)
#   entry  : next-bar OPEN after signal bar
#   SL0    : last swing (lowest low / highest high over SWING_LB bars) + cushion
#   R      : |entry - SL0|   (initial risk; ALL results reported in R multiples)
#   exits tested:
#       FIX 1:1 / 1.5:1 / 2:1  — fixed TP at RR*R, SL0 fixed, TP-first/SL-first
#       TRAIL kR (k=0.5,1,1.5,2) — LET PROFITS RUN: stop trails at distance k*R
#            behind the running favourable extreme; no take-profit; exit on stop.
#            (k=1 is the operator's proposal: trail distance = initial SL distance.)
#   intrabar: stop tested BEFORE the same bar's extreme updates the trail
#             (no look-ahead); both-touched on a fixed trade = SL first (worst case)
#   position: one at a time (flat -> next signal); realised R = (exit-entry)/R signed
#   metric  : mean R = expectancy per trade; also win%, median, best, total R
# =============================================================================
import importlib.util, argparse
import numpy as np, pandas as pd

spec = importlib.util.spec_from_file_location("disc", "rrm_org_discriminator.py")
disc = importlib.util.module_from_spec(spec); spec.loader.exec_module(disc)
PIP = 0.0001
SWING_LB, SL_CUSHION, SL_MIN = 12, 2*PIP, 5*PIP

def last_swing(d, i, lng):
    w = d.iloc[i-SWING_LB:i+1]
    return (w["low"].min() if lng else w["high"].max())

def exit_fixed(d, ei, entry, sl, tp, lng):
    for j in range(ei, len(d)):
        hi, lo = d["high"].iloc[j], d["low"].iloc[j]
        if lng:
            if lo <= sl: return (sl-entry)          # loss first (conservative tie)
            if hi >= tp: return (tp-entry)
        else:
            if hi >= sl: return sl-entry            # short stop = loss (sign handled by caller)
            if lo <= tp: return (tp-entry)
    return d["close"].iloc[-1]-entry

def exit_trail(d, ei, entry, sl0, R, k, lng):
    sl = sl0; peak = entry
    for j in range(ei, len(d)):
        hi, lo = d["high"].iloc[j], d["low"].iloc[j]
        if lng:
            if lo <= sl: return sl-entry            # stop tested first (no look-ahead)
            if hi > peak: peak = hi; sl = max(sl, peak - k*R)
        else:
            if hi >= sl: return sl-entry
            if lo < peak: peak = lo; sl = min(sl, peak + k*R)
    return d["close"].iloc[-1]-entry

EXITS = ["FIX1.0","FIX1.5","FIX2.0","TRAIL0.5","TRAIL1.0","TRAIL1.5","TRAIL2.0"]

def run(d, exit_name):
    i, n = 91, len(d); Rs = []
    while i < n-1:
        e = disc.evaluate_bar(d, i, 1.0)
        if not e.get("ts1"): i += 1; continue
        lng = e["bias"] > 0
        ei = i+1; entry = d["open"].iloc[ei]
        sw = last_swing(d, i, lng)
        R = max(abs(entry-sw)+SL_CUSHION, SL_MIN)
        sl0 = entry-R if lng else entry+R
        if exit_name.startswith("FIX"):
            rr = float(exit_name[3:]); tp = entry+rr*R if lng else entry-rr*R
            pl = exit_fixed(d, ei, entry, sl0, tp, lng)
        else:
            k = float(exit_name[5:]); pl = exit_trail(d, ei, entry, sl0, R, k, lng)
        realR = (pl/R) if lng else (-pl/R)
        # find exit bar to resume flat (re-walk cheaply: advance to first stop/tp)
        Rs.append(realR)
        # resume: step forward until this trade would have closed
        i = _exit_index(d, i, entry, sl0, R, exit_name, lng)+1
    return np.array(Rs)

def _exit_index(d, i, entry, sl0, R, exit_name, lng):
    ei = i+1
    if exit_name.startswith("FIX"):
        rr=float(exit_name[3:]); tp=entry+rr*R if lng else entry-rr*R; sl=sl0
        for j in range(ei,len(d)):
            hi,lo=d["high"].iloc[j],d["low"].iloc[j]
            if lng and (lo<=sl or hi>=tp): return j
            if (not lng) and (hi>=sl or lo<=tp): return j
        return len(d)-1
    k=float(exit_name[5:]); sl=sl0; peak=entry
    for j in range(ei,len(d)):
        hi,lo=d["high"].iloc[j],d["low"].iloc[j]
        if lng:
            if lo<=sl: return j
            if hi>peak: peak=hi; sl=max(sl,peak-k*R)
        else:
            if hi>=sl: return j
            if lo<peak: peak=lo; sl=min(sl,peak+k*R)
    return len(d)-1

def stats(R):
    n=len(R)
    if n==0: return None
    return dict(n=n, win=100*np.mean(R>0), mean=np.mean(R), med=np.median(R),
                best=np.max(R), tot=np.sum(R))

def main():
    ap=argparse.ArgumentParser(); ap.add_argument("files",nargs="+")
    a=ap.parse_args()
    for path in a.files:
        df=disc.load_csv(path); d=disc.build(df)
        tf = "H1" if "_H1_" in path else "M15" if "_M15_" in path else "M1" if "_M1_" in path else "?"
        print(f"\n############ {tf}   {path.split('/')[-1]} ############")
        print(f"# {len(d)} bars {d.index[0]} -> {d.index[-1]} | SL=swing({SWING_LB})+{SL_CUSHION/PIP:.0f}p, floor {SL_MIN/PIP:.0f}p")
        print(f"{'exit':10s}{'trades':>7}{'win%':>7}{'meanR':>8}{'medR':>7}{'bestR':>7}{'totR':>8}")
        for ex in EXITS:
            s=stats(run(d,ex))
            if s: print(f"{ex:10s}{s['n']:>7}{s['win']:>7.1f}{s['mean']:>+8.2f}{s['med']:>+7.2f}{s['best']:>+7.1f}{s['tot']:>+8.1f}")

if __name__=="__main__":
    main()
