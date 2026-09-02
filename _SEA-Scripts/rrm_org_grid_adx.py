#!/usr/bin/env python3
# rrm_org_grid_adx.py — BASE / +A / +B(pivot) / +ADX combos across full exit grid.
# Precomputes base TS=1 candidates + A/B/ADX flags ONCE, then walks each exit fast.
import importlib.util, argparse
import numpy as np, pandas as pd
spec=importlib.util.spec_from_file_location("disc","rrm_org_discriminator.py")
disc=importlib.util.module_from_spec(spec); spec.loader.exec_module(disc)
PIP=0.0001; SWING_LB=12; SL_CUSHION=2*PIP; SL_MIN=5*PIP
PIVOT_L=3; PIVOT_LOOKBACK=60; ADX_MIN=20.0
EXITS=["FIX1.0","FIX1.5","FIX2.0","TRAIL0.5","TRAIL1.0","TRAIL1.5","TRAIL2.0"]

def build_pivots(d,L=PIVOT_L):
    lo=d["low"].values; hi=d["high"].values; n=len(d)
    pli=[];pll=[];phi=[];phl=[]
    for j in range(L,n-L):
        sl=lo[j-L:j+L+1]; sh=hi[j-L:j+L+1]
        if lo[j]==sl.min() and list(sl).count(lo[j])==1: pli.append(j+L);pll.append(lo[j])
        if hi[j]==sh.max() and list(sh).count(hi[j])==1: phi.append(j+L);phl.append(hi[j])
    return np.array(pli),np.array(pll),np.array(phi),np.array(phl)

def pivot_break(close,i,lng,piv):
    pli,pll,phi,phl=piv
    if lng:
        m=np.searchsorted(phi,i,side="right")-1
        return (m>=0 and (i-phi[m])<=PIVOT_LOOKBACK and close[i]>phl[m])
    m=np.searchsorted(pli,i,side="right")-1
    return (m>=0 and (i-pli[m])<=PIVOT_LOOKBACK and close[i]<pll[m])

def build_htf_bias(hdf):
    h=disc.build(hdf); return h.apply(lambda r:disc.phase_bias(r.e2,r.e3,r.e4)[1],axis=1)

def precompute(d,hb,piv):
    """one pass: for every bar, base ts1? dir? A? B? ADX? + entry/R/sl0."""
    close=d["close"].values; opn=d["open"].values; hi=d["high"].values; lo=d["low"].values
    e3=d["e3"].values; e4=d["e4"].values; e3s=d["e3_sl"].values; e4s=d["e4_sl"].values
    adxv=d["adx"].values; idx=d.index; n=len(d)
    cand=[]
    for i in range(91,n-1):
        e=disc.evaluate_bar(d,i,1.0)
        if not e.get("ts1"): continue
        lng=e["bias"]>0
        A=( (e3[i]>e4[i] and e3s[i]>0 and e4s[i]>0) if lng else (e3[i]<e4[i] and e3s[i]<0 and e4s[i]<0) )
        if A and hb is not None:
            b=hb.asof(idx[i]); 
            if not pd.isna(b): A = (b>0) if lng else (b<0)
        B=pivot_break(close,i,lng,piv)
        ADX = adxv[i]>=ADX_MIN
        entry=opn[i+1]
        w_lo=lo[i-SWING_LB:i+1].min(); w_hi=hi[i-SWING_LB:i+1].max()
        sw=w_lo if lng else w_hi
        R=max(abs(entry-sw)+SL_CUSHION,SL_MIN)
        sl0=entry-R if lng else entry+R
        cand.append((i,lng,A,B,ADX,entry,R,sl0))
    return cand,hi,lo,close

def walk(hi,lo,close,ei,entry,sl0,R,ex,lng):
    n=len(hi)
    if ex.startswith("FIX"):
        rr=float(ex[3:]); tp=entry+rr*R if lng else entry-rr*R; sl=sl0
        for j in range(ei,n):
            if lng:
                if lo[j]<=sl: return -1.0,j
                if hi[j]>=tp: return rr,j
            else:
                if hi[j]>=sl: return -1.0,j
                if lo[j]<=tp: return rr,j
        return ((close[-1]-entry)/R if lng else (entry-close[-1])/R),n-1
    k=float(ex[5:]); sl=sl0; peak=entry
    for j in range(ei,n):
        if lng:
            if lo[j]<=sl: return (sl-entry)/R,j
            if hi[j]>peak: peak=hi[j]; sl=max(sl,peak-k*R)
        else:
            if hi[j]>=sl: return (sl-entry)/-R,j
            if lo[j]<peak: peak=lo[j]; sl=min(sl,peak+k*R)
    return ((close[-1]-entry)/R if lng else (entry-close[-1])/R),n-1

def run(cand,hi,lo,close,uA,uB,uADX,ex):
    Rs=[]; free=0
    for (i,lng,A,B,ADX,entry,R,sl0) in cand:
        if i<free: continue
        if uA and not A: continue
        if uB and not B: continue
        if uADX and not ADX: continue
        rR,xi=walk(hi,lo,close,i+1,entry,sl0,R,ex,lng); Rs.append(rR); free=xi+1
    R=np.array(Rs); n=len(R)
    return n,(100*np.mean(R>0) if n else 0),(np.mean(R) if n else 0),(np.sum(R) if n else 0)

def main():
    ap=argparse.ArgumentParser(); ap.add_argument("csv"); ap.add_argument("--htf",default=None)
    a=ap.parse_args()
    d=disc.build(disc.load_csv(a.csv)); piv=build_pivots(d)
    hb=build_htf_bias(disc.load_csv(a.htf)) if a.htf else None
    cand,hi,lo,close=precompute(d,hb,piv)
    tf="H1" if "_H1_" in a.csv else "M15" if "_M15_" in a.csv else "?"
    print(f"\n############ {tf}  {a.csv.split('/')[-1]}  HTF={'none' if not a.htf else 'H1'} ############")
    print(f"# {len(d)} bars | base candidates {len(cand)} | ADX>={ADX_MIN:.0f} | pivot L={PIVOT_L}")
    print(f"# cells = meanR (win% / trades)\n")
    combos=[("BASE",0,0,0),("+A",1,0,0),("+B",0,1,0),("+A+B",1,1,0),
            ("+ADX",0,0,1),("+A+ADX",1,0,1),("+B+ADX",0,1,1),("+A+B+ADX",1,1,1)]
    print("combo".ljust(10)+"".join(e.rjust(15) for e in EXITS))
    for label,uA,uB,uADX in combos:
        row=label.ljust(10)
        for ex in EXITS:
            n,win,mn,tot=run(cand,hi,lo,close,uA,uB,uADX,ex)
            row+=f"{mn:+.2f}({win:.0f}/{n})".rjust(15)
        print(row)

if __name__=="__main__": main()
