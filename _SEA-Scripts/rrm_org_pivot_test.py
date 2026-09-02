#!/usr/bin/env python3
# =============================================================================
# rrm_org_pivot_test.py
# -----------------------------------------------------------------------------
# Condition B, pivot version: enter only when the signal bar CLOSES BEYOND the
# most recent CONFIRMED swing pivot in the trade direction (real support/
# resistance), not a Donchian extreme.
#   short: close < most-recent confirmed pivot-LOW (broke support)
#   long : close > most-recent confirmed pivot-HIGH (broke resistance)
# Pivot = fractal: low[j] is a pivot low if it is the strict min of [j-L, j+L];
# confirmed L bars later (no look-ahead: only pivots with confirm_idx <= i used).
#
# Also A = deep-trend EMA3/EMA4 pos+slope (+ optional HTF bias confirm).
# Full exit grid per combo: FIX 1:1/1.5:1/2:1 and TRAIL 0.5/1.0/1.5/2.0R.
# SL = last swing(12)+2p; R=|entry-SL|; entry next-bar open; results in R.
# =============================================================================
import importlib.util, argparse
import numpy as np, pandas as pd

spec=importlib.util.spec_from_file_location("disc","rrm_org_discriminator.py")
disc=importlib.util.module_from_spec(spec); spec.loader.exec_module(disc)
PIP=0.0001; SWING_LB=12; SL_CUSHION=2*PIP; SL_MIN=5*PIP
PIVOT_L=3; PIVOT_LOOKBACK=60
EXITS=["FIX1.0","FIX1.5","FIX2.0","TRAIL0.5","TRAIL1.0","TRAIL1.5","TRAIL2.0"]

def last_swing(d,i,lng):
    w=d.iloc[i-SWING_LB:i+1]; return w["low"].min() if lng else w["high"].max()

def deep_trend(r,lng):
    if lng: return (r.e3>r.e4) and (r.e3_sl>0) and (r.e4_sl>0)
    return (r.e3<r.e4) and (r.e3_sl<0) and (r.e4_sl<0)

def build_pivots(d, L=PIVOT_L):
    lo=d["low"].values; hi=d["high"].values; n=len(d)
    pl_idx=[]; pl_lvl=[]; ph_idx=[]; ph_lvl=[]
    for j in range(L, n-L):
        seg_lo=lo[j-L:j+L+1]; seg_hi=hi[j-L:j+L+1]
        if lo[j]==seg_lo.min() and (seg_lo< lo[j]).sum()==0 and list(seg_lo).count(lo[j])==1:
            pl_idx.append(j+L); pl_lvl.append(lo[j])           # confirmed at j+L
        if hi[j]==seg_hi.max() and (seg_hi> hi[j]).sum()==0 and list(seg_hi).count(hi[j])==1:
            ph_idx.append(j+L); ph_lvl.append(hi[j])
    return (np.array(pl_idx),np.array(pl_lvl),np.array(ph_idx),np.array(ph_lvl))

def pivot_break(d,i,lng,piv):
    pl_idx,pl_lvl,ph_idx,ph_lvl=piv
    if lng:
        m=np.searchsorted(ph_idx,i,side="right")-1        # most recent confirmed pivot high <= i
        if m<0 or (i-ph_idx[m])>PIVOT_LOOKBACK: return False
        return d["close"].iloc[i] > ph_lvl[m]
    else:
        m=np.searchsorted(pl_idx,i,side="right")-1
        if m<0 or (i-pl_idx[m])>PIVOT_LOOKBACK: return False
        return d["close"].iloc[i] < pl_lvl[m]

def htf_ok(hb,ts,lng):
    if hb is None: return True
    b=hb.asof(ts)
    if pd.isna(b): return True
    return (b>0) if lng else (b<0)

def build_htf_bias(hdf):
    h=disc.build(hdf)
    return h.apply(lambda r:(disc.phase_bias(r.e2,r.e3,r.e4)[1]), axis=1)

def walk(d,ei,entry,sl0,R,ex,lng):
    if ex.startswith("FIX"):
        rr=float(ex[3:]); tp=entry+rr*R if lng else entry-rr*R; sl=sl0
        for j in range(ei,len(d)):
            hi,lo=d["high"].iloc[j],d["low"].iloc[j]
            if lng:
                if lo<=sl: return -1.0,j
                if hi>=tp: return rr,j
            else:
                if hi>=sl: return -1.0,j
                if lo<=tp: return rr,j
        return ((d["close"].iloc[-1]-entry)/R if lng else (entry-d["close"].iloc[-1])/R),len(d)-1
    k=float(ex[5:]); sl=sl0; peak=entry
    for j in range(ei,len(d)):
        hi,lo=d["high"].iloc[j],d["low"].iloc[j]
        if lng:
            if lo<=sl: return (sl-entry)/R,j
            if hi>peak: peak=hi; sl=max(sl,peak-k*R)
        else:
            if hi>=sl: return (sl-entry)/-R,j
            if lo<peak: peak=lo; sl=min(sl,peak+k*R)
    return ((d["close"].iloc[-1]-entry)/R if lng else (entry-d["close"].iloc[-1])/R),len(d)-1

def run(d,useA,useB,piv,hb,ex):
    i,n=91,len(d); Rs=[]
    while i<n-1:
        e=disc.evaluate_bar(d,i,1.0)
        if e.get("ts1"):
            r=d.iloc[i]; lng=e["bias"]>0; ok=True
            if useA and not (deep_trend(r,lng) and htf_ok(hb,d.index[i],lng)): ok=False
            if ok and useB and not pivot_break(d,i,lng,piv): ok=False
            if ok:
                ei=i+1; entry=d["open"].iloc[ei]
                sw=last_swing(d,i,lng); R=max(abs(entry-sw)+SL_CUSHION,SL_MIN)
                sl0=entry-R if lng else entry+R
                rR,xi=walk(d,ei,entry,sl0,R,ex,lng); Rs.append(rR); i=xi+1; continue
        i+=1
    R=np.array(Rs); n=len(R)
    return n,(100*np.mean(R>0) if n else 0),(np.mean(R) if n else 0),(np.sum(R) if n else 0)

def main():
    ap=argparse.ArgumentParser(); ap.add_argument("csv"); ap.add_argument("--htf",default=None)
    a=ap.parse_args()
    d=disc.build(disc.load_csv(a.csv)); piv=build_pivots(d)
    hb=build_htf_bias(disc.load_csv(a.htf)) if a.htf else None
    tf="H1" if "_H1_" in a.csv else "M15" if "_M15_" in a.csv else "?"
    print(f"\n############ {tf}  {a.csv.split('/')[-1]}  HTF={'none' if not a.htf else a.htf.split('/')[-1]} ############")
    print(f"# pivots: L={PIVOT_L} (fractal), lookback {PIVOT_LOOKBACK} | pivot-lows {len(piv[0])} pivot-highs {len(piv[2])}")
    print(f"# cells = meanR (win% / n).  SL=swing(12); results in R.\n")
    combos=[("BASE",0,0),("+A",1,0),("+B_pivot",0,1),("+A+B",1,1)]
    hdr="combo".ljust(10)+"".join(e.rjust(15) for e in EXITS)
    print(hdr)
    for label,uA,uB in combos:
        row=label.ljust(10)
        for ex in EXITS:
            n,win,mn,tot=run(d,uA,uB,piv,hb,ex)
            row+= f"{mn:+.2f}({win:.0f}/{n})".rjust(15)
        print(row)

if __name__=="__main__":
    main()
