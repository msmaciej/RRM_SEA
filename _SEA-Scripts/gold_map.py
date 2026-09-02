#!/usr/bin/env python3
# gold_map.py — XAUUSD (PIP=0.1, spread $0.30) XEMA analysis with PER-YEAR detail per config.
import importlib.util, argparse
import numpy as np, pandas as pd
spec=importlib.util.spec_from_file_location("xt","xema_test.py")
xt=importlib.util.module_from_spec(spec); spec.loader.exec_module(xt)
disc=xt.disc; PIP=0.1; SL_CUSHION=2*PIP; SL_MIN=5*PIP; BB_PERIOD=20; SPREAD=3.0  # 3*0.1=$0.30
W_LDNNY=set(range(8,21)); W_NY=set(range(12,22))
def ema(s,n): return s.ewm(alpha=2/(n+1),adjust=False).mean()
def resample(df,rule): return df.resample(rule).agg({"open":"first","high":"max","low":"min","close":"last"}).dropna()
def htf_sign(ci,hdf,f,s):
    t=np.sign(ema(hdf["close"],f)-ema(hdf["close"],s)); t.index=hdf.index
    return t.reindex(t.index.union(ci)).ffill().reindex(ci).values

def sigs_of(d,hsigns,fast,slow,useADX=1,useBB=1,usePSAR=1,ci_thr=None):
    ef=ema(d["close"],fast).values; es=ema(d["close"],slow).values; d["ef"]=ef; d["es"]=es
    adx=d["adx"].values;adxmed=d["adxmed"].values;psar=d["psar"].values;close=d["close"].values
    widen=d["_widen"].values; chop=d["chop"].values; out=[]
    for i in range(120,len(d)-1):
        up=ef[i]>es[i] and ef[i-1]<=es[i-1]; dn=ef[i]<es[i] and ef[i-1]>=es[i-1]
        if not(up or dn): continue
        lng=up; ok=True
        for hs in hsigns:
            h=hs[i]
            if np.isnan(h) or (h>0)!=lng: ok=False;break
        if not ok: continue
        if useADX and adx[i]<adxmed[i]: continue
        if usePSAR and not((psar[i]<close[i]) if lng else (psar[i]>close[i])): continue
        if useBB and not widen[i]: continue
        if ci_thr is not None and chop[i]>=ci_thr: continue
        out.append((i,lng))
    return out

def peryear(d,sigs,swing_lb=55,exit_mode="REVCROSS",session=None):
    hi=d["high"].values;lo=d["low"].values;close=d["close"].values
    ef=d["ef"].values;es=d["es"].values;O=d["open"].values;idx=d.index
    by={};free=0
    for (i,lng) in sigs:
        if i<free: continue
        if session is not None and idx[i].hour not in session: continue
        entry=O[i+1]
        sw=lo[i-swing_lb:i+1].min() if lng else hi[i-swing_lb:i+1].max()
        R=max(abs(entry-sw)+SL_CUSHION,SL_MIN); sl0=entry-R if lng else entry+R
        rR,xi=xt.walk(hi,lo,close,ef,es,i+1,entry,sl0,R,exit_mode,lng)
        Y=idx[i].year; by[Y]=by.get(Y,0)+(rR-2.0*(SPREAD*PIP)/R); free=xi+1
    return by

def fmt(by): 
    return "  ".join(f"{y}:{by[y]:+.0f}" for y in sorted(by))+f"  | tot {sum(by.values()):+.0f}"

def main():
    ap=argparse.ArgumentParser();ap.add_argument("csv");ap.add_argument("--htf",default=None);ap.add_argument("--m5",action="store_true")
    a=ap.parse_args()
    df=xt.load(a.csv); d=df.copy()
    d["adx"]=disc.adx(d,14); d["adxmed"]=d["adx"].rolling(100).median()
    d["psar"]=disc.psar(d,0.08,0.5); d["chop"]=disc.choppiness(d,14)
    std=d["close"].rolling(BB_PERIOD).std().values
    d["_widen"]=np.concatenate([[False],(std[1:]>std[:-1])])
    hs=[htf_sign(d.index,xt.load(a.htf),13,34)] if a.htf else [htf_sign(d.index,resample(df,"4h"),13,34)]
    tag=a.csv.split('/')[-1]
    print(f"\n#### XAUUSD {tag}  (netR after \$0.30 spread) ####")
    if a.m5:
        for lbl,adx in [("standard",1),("no-ADX",0)]:
            s=sigs_of(d,hs,13,34,useADX=adx)
            for wl,win in [("ALL",None),("LDN+NY",W_LDNNY),("NY",W_NY)]:
                print(f"  {lbl:9s} {wl:7s}: {fmt(peryear(d,s,session=win))}")
        return
    base=sigs_of(d,hs,13,34)
    print(f"  standard 13/34   : {fmt(peryear(d,base))}")
    print(f"  no-ADX           : {fmt(peryear(d,sigs_of(d,hs,13,34,useADX=0)))}")
    print(f"  no-BB            : {fmt(peryear(d,sigs_of(d,hs,13,34,useBB=0)))}")
    print(f"  +CI(61.8)        : {fmt(peryear(d,sigs_of(d,hs,13,34,ci_thr=61.8)))}")
    print(f"  EMA 8/21         : {fmt(peryear(d,sigs_of(d,hs,8,21)))}")
    print(f"  EMA 21/55        : {fmt(peryear(d,sigs_of(d,hs,21,55)))}")
    print(f"  no-HTF           : {fmt(peryear(d,sigs_of(d,[],13,34)))}")
    print(f"  exit FIX2:1      : {fmt(peryear(d,base,exit_mode='FIX2.0'))}")
    print(f"  exit TRAIL1.0    : {fmt(peryear(d,base,exit_mode='TRAIL1.0'))}")
    print(f"  swing 89         : {fmt(peryear(d,base,swing_lb=89))}")

if __name__=="__main__": main()
