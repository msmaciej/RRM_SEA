#!/usr/bin/env python3
# jpy_map.py — USDJPY (PIP=0.01) XEMA analysis: transfer test of the EURUSD-optimal config
# plus sweeps of the highest-leverage knobs, per TF, net R after cost. Sequential one-position.
import importlib.util, argparse
import numpy as np, pandas as pd
spec=importlib.util.spec_from_file_location("xt","xema_test.py")
xt=importlib.util.module_from_spec(spec); spec.loader.exec_module(xt)
disc=xt.disc; PIP=0.01; SL_CUSHION=2*PIP; SL_MIN=5*PIP; BB_PERIOD=20; SPREAD=0.8
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

def run(d,sigs,swing_lb=55,exit_mode="REVCROSS",session=None):
    hi=d["high"].values;lo=d["low"].values;close=d["close"].values
    ef=d["ef"].values;es=d["es"].values;O=d["open"].values;idx=d.index
    net=0.0;free=0;n=0
    for (i,lng) in sigs:
        if i<free: continue
        if session is not None and idx[i].hour not in session: continue
        entry=O[i+1]
        sw=lo[i-swing_lb:i+1].min() if lng else hi[i-swing_lb:i+1].max()
        R=max(abs(entry-sw)+SL_CUSHION,SL_MIN); sl0=entry-R if lng else entry+R
        rR,xi=xt.walk(hi,lo,close,ef,es,i+1,entry,sl0,R,exit_mode,lng)
        net+=rR-2.0*(SPREAD*PIP)/R; free=xi+1; n+=1
    return net,n

def main():
    ap=argparse.ArgumentParser();ap.add_argument("csv");ap.add_argument("--htf",default=None);ap.add_argument("--m5",action="store_true"); ap.add_argument("--noadx",action="store_true"); ap.add_argument("--peryear",action="store_true")
    a=ap.parse_args()
    df=xt.load(a.csv); d=df.copy()
    d["adx"]=disc.adx(d,14); d["adxmed"]=d["adx"].rolling(100).median()
    d["psar"]=disc.psar(d,0.08,0.5); d["chop"]=disc.choppiness(d,14)
    std=d["close"].rolling(BB_PERIOD).std().values
    d["_widen"]=np.concatenate([[False],(std[1:]>std[:-1])])
    if a.htf: hs=[htf_sign(d.index,xt.load(a.htf),13,34)]
    else:     hs=[htf_sign(d.index,resample(df,"4h"),13,34)]   # H1 chart -> H4 HTF
    tag=a.csv.split('/')[-1]
    print(f"\n#### USDJPY {tag}  HTF={'file' if a.htf else 'H4(resampled)'}  (netR after {SPREAD}p / n) ####")
    base=sigs_of(d,hs,13,34,useADX=0 if a.noadx else 1)
    if a.m5:
        for lbl,win in [("ALL hours",None),("LDN+NY 8-20",W_LDNNY),("NY 12-21",W_NY)]:
            net,n=run(d,base,session=win); print(f"   {lbl:14s} {net:+.0f}R (n{n})  [ADX {'OFF' if a.noadx else 'on'}]")
        return
    if a.peryear:
        hi=d["high"].values;lo=d["low"].values;close=d["close"].values;ef=d["ef"].values;es=d["es"].values;O=d["open"].values;idx=d.index
        by={};free=0
        for (i,lng) in base:
            if i<free: continue
            entry=O[i+1]; sw=lo[i-55:i+1].min() if lng else hi[i-55:i+1].max()
            R=max(abs(entry-sw)+SL_CUSHION,SL_MIN); sl0=entry-R if lng else entry+R
            rR,xi=xt.walk(hi,lo,close,ef,es,i+1,entry,sl0,R,"REVCROSS",lng)
            Y=idx[i].year; by[Y]=by.get(Y,0)+(rR-2.0*(SPREAD*PIP)/R); free=xi+1
        print(f"   ADX {'OFF' if a.noadx else 'on'} per-year: "+"  ".join(f"{y}:{by[y]:+.0f}" for y in sorted(by)))
        return
    def line(lbl,net,n): print(f"   {lbl:26s} {net:+.0f}R (n{n})")
    line("standard 13/34 (live)",*run(d,base))
    print("  EMA periods:")
    for (f,s) in [(8,21),(13,34),(21,55)]: line(f"  {f}/{s}",*run(d,sigs_of(d,hs,f,s)))
    print("  HTF:")
    line("  no HTF",*run(d,sigs_of(d,[],13,34)))
    line("  single HTF",*run(d,base))
    print("  exit:")
    for ex in ["REVCROSS","FIX2.0","TRAIL1.0"]: line(f"  {ex}",*run(d,base,exit_mode=ex))
    print("  filters:")
    line("  no ADX",*run(d,sigs_of(d,hs,13,34,useADX=0)))
    line("  no BB",*run(d,sigs_of(d,hs,13,34,useBB=0)))
    line("  +CI(61.8)",*run(d,sigs_of(d,hs,13,34,ci_thr=61.8)))
    print("  swing lookback:")
    for slb in [34,55,89]: line(f"  {slb}",*run(d,base,swing_lb=slb))

if __name__=="__main__": main()
