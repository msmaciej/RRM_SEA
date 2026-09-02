#!/usr/bin/env python3
# htf_sweep.py — sweep HTF confirmation for the live XEMA config on EURUSD, after cost.
# Tests: no HTF, single HTF (which TF), dual HTF (both must agree), and HTF EMA periods.
# Chart = M15. HTF candidates built by resampling the M15 file (H1, H4, D1) so any combo works.
import importlib.util, argparse
import numpy as np, pandas as pd
spec=importlib.util.spec_from_file_location("xt","xema_test.py")
xt=importlib.util.module_from_spec(spec); spec.loader.exec_module(xt)
disc=xt.disc; PIP=0.0001; SWING_LB=55; SL_CUSHION=2*PIP; SL_MIN=5*PIP; BB_PERIOD=20; SPREAD=0.8
def ema(s,n): return s.ewm(alpha=2/(n+1),adjust=False).mean()

def resample(df,rule):
    return df.resample(rule).agg({"open":"first","high":"max","low":"min","close":"last"}).dropna()

def htf_sign(ci,hdf,f,s):
    t=np.sign(ema(hdf["close"],f)-ema(hdf["close"],s)); t.index=hdf.index
    return t.reindex(t.index.union(ci)).ffill().reindex(ci).values

def make_signals(d,hsigns):
    ef=d["ef"].values;es=d["es"].values;adx=d["adx"].values;adxmed=d["adxmed"].values
    psar=d["psar"].values;close=d["close"].values;widen=d["_widen"].values
    out=[]
    for i in range(60,len(d)-1):
        up=ef[i]>es[i] and ef[i-1]<=es[i-1]; dn=ef[i]<es[i] and ef[i-1]>=es[i-1]
        if not(up or dn): continue
        lng=up; ok=True
        for hs in hsigns:
            h=hs[i]
            if np.isnan(h) or (h>0)!=lng: ok=False; break
        if not ok: continue
        if adx[i]<adxmed[i]: continue
        if not((psar[i]<close[i]) if lng else (psar[i]>close[i])): continue
        if not widen[i]: continue
        out.append((i,lng))
    return out

def total(d,sigs):
    hi=d["high"].values;lo=d["low"].values;close=d["close"].values
    ef=d["ef"].values;es=d["es"].values;O=d["open"].values
    net=0.0;free=0;n=0
    for (i,lng) in sigs:
        if i<free: continue
        entry=O[i+1]
        sw=lo[i-SWING_LB:i+1].min() if lng else hi[i-SWING_LB:i+1].max()
        R=max(abs(entry-sw)+SL_CUSHION,SL_MIN); sl0=entry-R if lng else entry+R
        rR,xi=xt.walk(hi,lo,close,ef,es,i+1,entry,sl0,R,"REVCROSS",lng)
        net+=rR-2.0*(SPREAD*PIP)/R; free=xi+1; n+=1
    return net,n

def main():
    ap=argparse.ArgumentParser();ap.add_argument("csv");a=ap.parse_args()
    df=xt.load(a.csv); d=df.copy()
    d["ef"]=ema(d["close"],13); d["es"]=ema(d["close"],34)
    d["adx"]=disc.adx(d,14); d["adxmed"]=d["adx"].rolling(100).median()
    d["psar"]=disc.psar(d,0.08,0.5)
    std=d["close"].rolling(BB_PERIOD).std().values
    d["_widen"]=np.concatenate([[False],(std[1:]>std[:-1])])
    H1=resample(df,"1h"); H4=resample(df,"4h"); D1=resample(df,"1D")
    tag=a.csv.split('/')[-1]
    print(f"\n#### HTF sweep — {tag} (netR after cost / n) ####")
    def show(label,hsigns):
        net,n=total(d,make_signals(d,hsigns)); print(f"   {label:26s} {net:>+7.1f}R  (n{n})")
    print("  presence / which TF (HTF EMA 13/34):")
    show("no HTF", [])
    show("single H1", [htf_sign(d.index,H1,13,34)])
    show("single H4", [htf_sign(d.index,H4,13,34)])
    show("single D1", [htf_sign(d.index,D1,13,34)])
    show("dual H1+H4", [htf_sign(d.index,H1,13,34),htf_sign(d.index,H4,13,34)])
    show("dual H1+D1", [htf_sign(d.index,H1,13,34),htf_sign(d.index,D1,13,34)])
    print("  HTF EMA periods (single H1):")
    for (f,s) in [(8,21),(13,34),(20,50),(21,55),(34,89)]:
        show(f"H1 {f}/{s}", [htf_sign(d.index,H1,f,s)])

if __name__=="__main__": main()
