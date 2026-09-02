#!/usr/bin/env python3
# xema_test.py — reconstruct PRESET_XEMA and run it through the same SL/RR/exit grid.
#
# XEMA (from SEA_Inputs.mqh defaults):
#   entry : EMA fast(20) crosses EMA slow(50) on chart TF
#   HTF   : require EMA20>EMA50 on higher TF(s)  (M15 chart -> H1;  H1 chart -> H4 & D1)
#   ADX   : ADX(14) >= its own rolling-100 median (percentile-50 gate)  [ON by default]
#   (BB/CI/PSAR/DPI/CandleBody voters OFF by default)
#   SL    : swing;  native exit = reverse-cross + let-profit-run (no fixed TP)
#
# Tested here with the SAME framework as the RRM_ORG grids for comparability:
#   entry next-bar open; SL=swing(12)+2p; R=|entry-SL|; results in R multiples.
#   exits: FIX 1:1/1.5:1/2:1, TRAIL 0.5..2.0R, and REVCROSS (XEMA native, SL-protected).
#   rows : RAW cross / +HTF / +HTF+ADX(=XEMA default) to show each filter's contribution.
import importlib.util, argparse
import numpy as np, pandas as pd
spec=importlib.util.spec_from_file_location("disc","rrm_org_discriminator.py")
disc=importlib.util.module_from_spec(spec); spec.loader.exec_module(disc)
PIP=0.0001; SWING_LB=12; SL_CUSHION=2*PIP; SL_MIN=5*PIP
FAST,SLOW=20,50
EXITS=["FIX1.0","FIX1.5","FIX2.0","TRAIL0.5","TRAIL1.0","TRAIL1.5","TRAIL2.0","REVCROSS"]

def ema(s,n): return s.ewm(alpha=2/(n+1),adjust=False).mean()

def load(path,resample=None): return disc.load_csv(path,resample)

def htf_trend(chart_index, hdf):
    """sign of EMA20-EMA50 on a higher-TF df, asof-mapped to chart bars."""
    ef=ema(hdf["close"],FAST); es=ema(hdf["close"],SLOW)
    sign=np.sign(ef-es); sign.index=hdf.index
    return sign.reindex(sign.index.union(chart_index)).ffill().reindex(chart_index)

def build(df, htf_dfs):
    d=df.copy()
    d["ef"]=ema(d["close"],FAST); d["es"]=ema(d["close"],SLOW)
    d["adx"]=disc.adx(d,14); d["adxmed"]=d["adx"].rolling(100).median()
    d["htf"]=1.0
    ok=pd.Series(True,index=d.index)
    for h in htf_dfs:
        t=htf_trend(d.index,h)
        d[f"_h"]=t
        # store per-HTF sign in a list column via successive AND handled at signal time
    d["_htfs"]=None
    return d

def htf_signs(d, htf_dfs):
    return [htf_trend(d.index,h).values for h in htf_dfs]

def walk(hi,lo,close,ef,es,ei,entry,sl0,R,ex,lng):
    n=len(hi)
    if ex=="REVCROSS":
        sl=sl0
        for j in range(ei,n):
            if lng:
                if lo[j]<=sl: return (sl-entry)/R,j
                if ef[j]<es[j]: return (close[j]-entry)/R,j     # reverse cross down
            else:
                if hi[j]>=sl: return (sl-entry)/-R,j
                if ef[j]>es[j]: return (entry-close[j])/R,j
        return ((close[-1]-entry)/R if lng else (entry-close[-1])/R),n-1
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

def signals(d, hsigns, useHTF, useADX):
    ef=d["ef"].values; es=d["es"].values; adx=d["adx"].values; adm=d["adxmed"].values
    out=[]
    for i in range(SLOW+2,len(d)-1):
        up = ef[i]>es[i] and ef[i-1]<=es[i-1]
        dn = ef[i]<es[i] and ef[i-1]>=es[i-1]
        if not (up or dn): continue
        lng=up
        if useHTF:
            good=True
            for hs in hsigns:
                s=hs[i]
                if np.isnan(s) or (s>0)!=lng: good=False; break
            if not good: continue
        if useADX and not (adx[i]>=adm[i]): continue
        out.append((i,lng))
    return out

def run(d,hi,lo,close,ef,es,sigs,ex):
    Rs=[]; free=0; O=d["open"].values
    hh=d["high"].values; ll=d["low"].values
    for (i,lng) in sigs:
        if i<free: continue
        entry=O[i+1]
        sw=ll[i-SWING_LB:i+1].min() if lng else hh[i-SWING_LB:i+1].max()
        R=max(abs(entry-sw)+SL_CUSHION,SL_MIN)
        sl0=entry-R if lng else entry+R
        rR,xi=walk(hi,lo,close,ef,es,i+1,entry,sl0,R,ex,lng); Rs.append(rR); free=xi+1
    R=np.array(Rs); n=len(R)
    return n,(100*np.mean(R>0) if n else 0),(np.mean(R) if n else 0),(np.sum(R) if n else 0)

def main():
    ap=argparse.ArgumentParser(); ap.add_argument("csv")
    ap.add_argument("--htf",nargs="*",default=[]); a=ap.parse_args()
    df=load(a.csv)
    tf="H1" if "_H1_" in a.csv else "M15" if "_M15_" in a.csv else "?"
    if a.htf:
        htf_dfs=[load(h) for h in a.htf]; htflabel=",".join("H1" for _ in a.htf)
    elif tf=="H1":
        htf_dfs=[load(a.csv,"H4"),load(a.csv,"D1")]; htflabel="H4,D1(resampled)"
    else:
        htf_dfs=[]; htflabel="none"
    d=build(df,htf_dfs); hsigns=htf_signs(d,htf_dfs)
    hi=d["high"].values; lo=d["low"].values; close=d["close"].values
    ef=d["ef"].values; es=d["es"].values
    print(f"\n############ XEMA  {tf}  {a.csv.split('/')[-1]}  HTF={htflabel} ############")
    print(f"# EMA {FAST}/{SLOW} cross | ADX>=rolling-median(100) | SL=swing({SWING_LB}) | cells=meanR (win%/n)\n")
    print("config".ljust(12)+"".join(e.rjust(14) for e in EXITS))
    for label,uH,uA in [("RAW cross",0,0),("+HTF",1,0),("+HTF+ADX",1,1)]:
        sigs=signals(d,hsigns,uH,uA); row=label.ljust(12)
        for ex in EXITS:
            n,win,mn,tot=run(d,hi,lo,close,ef,es,sigs,ex)
            row+=f"{mn:+.2f}({win:.0f}/{n})".rjust(14)
        print(row)

if __name__=="__main__": main()
