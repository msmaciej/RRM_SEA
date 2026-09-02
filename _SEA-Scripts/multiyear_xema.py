#!/usr/bin/env python3
# multiyear_xema.py — run the XEMA variant year-by-year with a regime metric,
# to see whether the edge is structural or a 2025-trend artifact.
import importlib.util, argparse
import numpy as np, pandas as pd
spec=importlib.util.spec_from_file_location("xt","xema_test.py")
xt=importlib.util.module_from_spec(spec); spec.loader.exec_module(xt)
disc=xt.disc; PIP=0.0001; SWING_LB=12; SL_CUSHION=2*PIP; SL_MIN=5*PIP

def regime(dy):
    o=dy["open"].iloc[0]; c=dy["close"].iloc[-1]; net=(c-o)*1e4
    daily=dy["close"].resample("1D").last().dropna()
    path=daily.diff().abs().sum()
    er=abs(daily.iloc[-1]-daily.iloc[0])/path if path>0 else 0
    return net, er

def seq(d, sigs, ex):
    hi=d["high"].values; lo=d["low"].values; close=d["close"].values
    ef=d["ef"].values; es=d["es"].values; O=d["open"].values
    Rs=[]; free=0
    for (i,lng) in sigs:
        if i<free: continue
        entry=O[i+1]
        sw=lo[i-SWING_LB:i+1].min() if lng else hi[i-SWING_LB:i+1].max()
        R=max(abs(entry-sw)+SL_CUSHION,SL_MIN); sl0=entry-R if lng else entry+R
        rR,xi=xt.walk(hi,lo,close,ef,es,i+1,entry,sl0,R,ex,lng); Rs.append(rR); free=xi+1
    R=np.array(Rs); n=len(R)
    return n,(100*np.mean(R>0) if n else 0),(np.mean(R) if n else 0),(np.sum(R) if n else 0)

def main():
    ap=argparse.ArgumentParser(); ap.add_argument("csv"); ap.add_argument("htf")
    ap.add_argument("--fast",type=int,default=13); ap.add_argument("--slow",type=int,default=34)
    a=ap.parse_args()
    xt.FAST,xt.SLOW,xt.START=a.fast,a.slow,None
    df=xt.load(a.csv); hdf=xt.load(a.htf)
    d=xt.build(df,[hdf]); hsigns=xt.htf_signs(d,[hdf])
    allsig=xt.signals(d,hsigns,useHTF=1,useADX=1,useP=1)   # the winning variant
    tf="M15" if "_M15_" in a.csv else "H1" if "_H1_" in a.csv else "?"
    print(f"\n#### XEMA {a.fast}/{a.slow} +HTF+ADX+PSAR  {tf}  {a.csv.split('/')[-1]} ####")
    print(f"{'year':6}{'netPip':>8}{'effR':>6}{'| FIX2:1  meanR(win/n)':>26}{'| REVCROSS meanR(win/n)':>26}")
    years=sorted({t.year for (i,t) in [(i,d.index[i]) for (i,lng) in allsig]})
    for Y in sorted({d.index[i].year for (i,lng) in allsig}):
        dy=d[d.index.year==Y]
        if len(dy)<500: continue
        net,er=regime(dy)
        ys=[(i,lng) for (i,lng) in allsig if d.index[i].year==Y]
        n2,w2,m2,t2=seq(d,ys,"FIX2.0")
        nr,wr,mr,tr=seq(d,ys,"REVCROSS")
        print(f"{Y:<6}{net:>+8.0f}{er:>6.2f}   {m2:>+6.2f}({w2:>3.0f}/{n2:<3})        {mr:>+6.2f}({wr:>3.0f}/{nr:<3})")

if __name__=="__main__": main()
