#!/usr/bin/env python3
# m5_test.py — does M5 EURUSD want a different config, and can any config beat costs?
# Live config baseline: EMA13/34, HTF, ADX@50pct, PSAR0.08, BB-widen(20), swing55, REVCROSS.
import importlib.util, argparse
import numpy as np, pandas as pd
spec=importlib.util.spec_from_file_location("xt","xema_test.py")
xt=importlib.util.module_from_spec(spec); spec.loader.exec_module(xt)
disc=xt.disc; PIP=0.0001; SWING_LB=55; SL_CUSHION=2*PIP; SL_MIN=5*PIP; BB_PERIOD=20; SPREAD=0.8
def ema(s,n): return s.ewm(alpha=2/(n+1),adjust=False).mean()

def htf_sign(ci,hdf,f,s):
    t=np.sign(ema(hdf["close"],f)-ema(hdf["close"],s)); t.index=hdf.index
    return t.reindex(t.index.union(ci)).ffill().reindex(ci).values

def make_signals(d,hs,fast,slow):
    ef=ema(d["close"],fast).values; es=ema(d["close"],slow).values
    d["ef"]=ef; d["es"]=es
    adx=d["adx"].values;adxmed=d["adxmed"].values;psar=d["psar"].values
    close=d["close"].values;widen=d["_widen"].values;out=[]
    for i in range(60,len(d)-1):
        up=ef[i]>es[i] and ef[i-1]<=es[i-1]; dn=ef[i]<es[i] and ef[i-1]>=es[i-1]
        if not(up or dn): continue
        lng=up; h=hs[i]
        if np.isnan(h) or (h>0)!=lng: continue
        if adx[i]<adxmed[i]: continue
        if not((psar[i]<close[i]) if lng else (psar[i]>close[i])): continue
        if not widen[i]: continue
        out.append((i,lng))
    return out

def run(d,sigs,exit_mode="REVCROSS"):
    hi=d["high"].values;lo=d["low"].values;close=d["close"].values
    ef=d["ef"].values;es=d["es"].values;O=d["open"].values;idx=d.index
    g={};nyr={};cnt={};free=0
    for (i,lng) in sigs:
        if i<free: continue
        entry=O[i+1]
        sw=lo[i-SWING_LB:i+1].min() if lng else hi[i-SWING_LB:i+1].max()
        R=max(abs(entry-sw)+SL_CUSHION,SL_MIN); sl0=entry-R if lng else entry+R
        rR,xi=xt.walk(hi,lo,close,ef,es,i+1,entry,sl0,R,exit_mode,lng)
        Y=idx[i].year; g[Y]=g.get(Y,0)+rR; nyr[Y]=nyr.get(Y,0)+rR-2.0*(SPREAD*PIP)/R
        cnt[Y]=cnt.get(Y,0)+1; free=xi+1
    return g,nyr,cnt

def main():
    ap=argparse.ArgumentParser();ap.add_argument("m5");ap.add_argument("htf")
    a=ap.parse_args()
    df=xt.load(a.m5); hdf=xt.load(a.htf); d=df.copy()
    d["adx"]=disc.adx(d,14); d["adxmed"]=d["adx"].rolling(100).median()
    d["psar"]=disc.psar(d,0.08,0.5)
    std=d["close"].rolling(BB_PERIOD).std().values
    d["_widen"]=np.concatenate([[False],(std[1:]>std[:-1])])
    hsM15=htf_sign(d.index,hdf,13,34)
    print(f"\n#### M5 map — {a.m5.split('/')[-1]} (HTF={a.htf.split('/')[-1]}) ####")
    print(f"# baseline live cfg 13/34, HTF, ADX, BB, PSAR0.08, swing55, REVCROSS; spread {SPREAD}p\n")
    def summarize(label,sigs,exit_mode="REVCROSS"):
        g,nyr,cnt=run(d,sigs,exit_mode)
        yrs=sorted(nyr)
        tg=sum(g.values()); tn=sum(nyr.values()); tc=sum(cnt.values())
        peryr="  ".join(f"{y}:{nyr[y]:+.0f}" for y in yrs)
        print(f"  {label}")
        print(f"     gross {tg:+.0f}R | NET {tn:+.0f}R | trades {tc} | per-yr net: {peryr}")
    summarize("baseline (HTF 13/34)", make_signals(d,hsM15,13,34))
    print("  slower EMAs (cut M5 noise?):")
    summarize("  EMA 21/55", make_signals(d,hsM15,21,55))
    summarize("  EMA 34/89", make_signals(d,hsM15,34,89))
    print("  exit variants (13/34):")
    sig=make_signals(d,hsM15,13,34)
    summarize("  FIX 2:1", sig, "FIX2.0")
    summarize("  TRAIL 1.0R", sig, "TRAIL1.0")

if __name__=="__main__": main()
