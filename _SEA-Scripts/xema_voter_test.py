#!/usr/bin/env python3
# xema_voter_test.py — matches the operator's live XEMA config and tests whether
# turning ON each currently-OFF voter (CandleBody / CI / DPI) improves the DECADE
# result after costs. Baseline = live config (ADX+BB+PSAR on).
import importlib.util, argparse
import numpy as np, pandas as pd
spec=importlib.util.spec_from_file_location("xt","xema_test.py")
xt=importlib.util.module_from_spec(spec); spec.loader.exec_module(xt)
disc=xt.disc; PIP=0.0001
SWING_LB=55; SL_CUSHION=2*PIP; SL_MIN=5*PIP; BB_PERIOD=20   # live: swing 55
SPREAD=0.8; CB_MINRATIO=0.75; CB_MAXMULT=3.0; CI_THRESH=61.8

def build(csv,htf):
    xt.FAST,xt.SLOW,xt.START,xt.SLMODE,xt.ATR_MULT,xt.PSTEP,xt.PMAX=13,34,None,"swing",1.0,0.08,0.5
    df=xt.load(csv); tf="M15" if "_M15_" in csv else "H1"
    htf_dfs=[xt.load(htf)] if htf else ([xt.load(csv,"H4")] if tf=="H1" else [])
    d=xt.build(df,htf_dfs); hs=xt.htf_signs(d,htf_dfs)
    d["dpi"]=disc.dpi(d); d["chop"]=disc.choppiness(d,14)
    std=d["close"].rolling(BB_PERIOD).std().values
    d["_widen"]=np.concatenate([[False],(std[1:]>std[:-1])])
    return d,hs

def voter_ok(d,i,lng,which):
    if which=="CB":
        o,h,l,c=d["open"].values[i],d["high"].values[i],d["low"].values[i],d["close"].values[i]
        rng=max(h-l,1e-9); atr=d["atr"].values[i]
        dir_ok=(c>o) if lng else (c<o)
        ratio=((c-l)/rng) if lng else ((h-c)/rng)
        spike_ok=(h-l)<=CB_MAXMULT*atr
        return dir_ok and ratio>=CB_MINRATIO and spike_ok
    if which=="CI":
        return d["chop"].values[i] < CI_THRESH
    if which=="DPI":
        dp=d["dpi"].values[i]
        return (dp>0) if lng else (dp<0)
    return True

def run_year(d,sigs,spread):
    hi=d["high"].values;lo=d["low"].values;close=d["close"].values
    ef=d["ef"].values;es=d["es"].values;O=d["open"].values
    net=[];free=0
    for (i,lng) in sigs:
        if i<free: continue
        entry=O[i+1]
        sw=lo[i-SWING_LB:i+1].min() if lng else hi[i-SWING_LB:i+1].max()
        R=max(abs(entry-sw)+SL_CUSHION,SL_MIN); sl0=entry-R if lng else entry+R
        rR,xi=xt.walk(hi,lo,close,ef,es,i+1,entry,sl0,R,"REVCROSS",lng)
        net.append(rR-2.0*(spread*PIP)/R); free=xi+1
    a=np.array(net); return len(a),(100*np.mean(a>0) if len(a) else 0),np.sum(a)

def main():
    ap=argparse.ArgumentParser();ap.add_argument("csv");ap.add_argument("htf")
    a=ap.parse_args()
    d,hs=build(a.csv,a.htf)
    base=[(i,l) for (i,l) in xt.signals(d,hs,useHTF=1,useADX=1,useP=1) if d["_widen"].values[i]]
    variants={"baseline (live)":None,"+CandleBody":"CB","+CI":"CI","+DPI":"DPI"}
    print(f"\n#### XEMA voter test (live cfg: 13/34 HTF ADX BB PSAR0.08 swing55) — {a.csv.split('/')[-1]} ####")
    print(f"# exit REVCROSS, spread {SPREAD}p, net R after cost\n")
    hdr="year".ljust(6)
    for name in variants: hdr+=f"{name:>18}"
    print(hdr)
    yrs=sorted({d.index[i].year for (i,l) in base})
    tot={k:0.0 for k in variants}
    for Y in yrs:
        dyN=len(d[d.index.year==Y])
        if dyN<500: continue
        row=f"{Y:<6}"
        for name,vk in variants.items():
            ys=[(i,l) for (i,l) in base if d.index[i].year==Y and (vk is None or voter_ok(d,i,l,vk))]
            n,w,s=run_year(d,ys,SPREAD); tot[name]+=s
            row+=f"{s:>+8.1f}R(n{n:<3})"[:18].rjust(18)
        print(row)
    print("\nDECADE TOTAL netR:")
    for name in variants: print(f"   {name:20s} {tot[name]:+.0f}R")

if __name__=="__main__": main()
