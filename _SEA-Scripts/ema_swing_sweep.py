#!/usr/bin/env python3
# ema_swing_sweep.py — sweep EMA entry periods and swing lookback on the live XEMA
# config across one CSV's years, after cost. Indicators independent of EMA period are
# computed once; only EMAs + HTF signs are recomputed per pair.
import importlib.util, argparse
import numpy as np, pandas as pd
spec=importlib.util.spec_from_file_location("xt","xema_test.py")
xt=importlib.util.module_from_spec(spec); spec.loader.exec_module(xt)
disc=xt.disc; PIP=0.0001; SL_CUSHION=2*PIP; SL_MIN=5*PIP; BB_PERIOD=20; SPREAD=0.8

def ema(s,n): return s.ewm(alpha=2/(n+1),adjust=False).mean()

def htf_sign(chart_index,hdf,f,s):
    t=np.sign(ema(hdf["close"],f)-ema(hdf["close"],s)); t.index=hdf.index
    return t.reindex(t.index.union(chart_index)).ffill().reindex(chart_index).values

def signals(d,hsign,adx,adxmed,psar,close,widen):
    ef=d["ef"].values; es=d["es"].values; out=[]
    for i in range(60,len(d)-1):
        up=ef[i]>es[i] and ef[i-1]<=es[i-1]; dn=ef[i]<es[i] and ef[i-1]>=es[i-1]
        if not(up or dn): continue
        lng=up; hs=hsign[i]
        if np.isnan(hs) or (hs>0)!=lng: continue          # HTF
        if adx[i]<adxmed[i]: continue                     # ADX
        if not((psar[i]<close[i]) if lng else (psar[i]>close[i])): continue   # PSAR
        if not widen[i]: continue                          # BB
        out.append((i,lng))
    return out

def run_all_years(d,sigs,swing_lb):
    hi=d["high"].values;lo=d["low"].values;close=d["close"].values
    ef=d["ef"].values;es=d["es"].values;O=d["open"].values;idx=d.index
    by={}; free=0
    for (i,lng) in sigs:
        if i<free: continue
        entry=O[i+1]
        sw=lo[i-swing_lb:i+1].min() if lng else hi[i-swing_lb:i+1].max()
        R=max(abs(entry-sw)+SL_CUSHION,SL_MIN); sl0=entry-R if lng else entry+R
        rR,xi=xt.walk(hi,lo,close,ef,es,i+1,entry,sl0,R,"REVCROSS",lng)
        by[idx[i].year]=by.get(idx[i].year,0.0)+(rR-2.0*(SPREAD*PIP)/R); free=xi+1
    return sum(by.values())

def main():
    ap=argparse.ArgumentParser();ap.add_argument("csv");ap.add_argument("htf");a=ap.parse_args()
    df=xt.load(a.csv); hdf=xt.load(a.htf)
    d=df.copy()
    d["adx"]=disc.adx(d,14); d["adxmed"]=d["adx"].rolling(100).median()
    d["psar"]=disc.psar(d,0.08,0.5)
    std=d["close"].rolling(BB_PERIOD).std().values
    widen=np.concatenate([[False],(std[1:]>std[:-1])])
    adx=d["adx"].values; adxmed=d["adxmed"].values; psar=d["psar"].values; close=d["close"].values
    tag=a.csv.split('/')[-1]
    print(f"\n#### EMA-period sweep (swing 55) — {tag} ####")
    for (f,s) in [(8,21),(13,34),(21,55),(8,34),(13,55)]:
        d["ef"]=ema(d["close"],f); d["es"]=ema(d["close"],s)
        hs=htf_sign(d.index,hdf,f,s)
        tot=run_all_years(d,signals(d,hs,adx,adxmed,psar,close,widen),55)
        print(f"   EMA {f}/{s:<3}  netR {tot:+.1f}")
    print(f"\n#### Swing-lookback sweep (EMA 13/34) — {tag} ####")
    d["ef"]=ema(d["close"],13); d["es"]=ema(d["close"],34)
    hs=htf_sign(d.index,hdf,13,34); sig=signals(d,hs,adx,adxmed,psar,close,widen)
    for slb in [20,34,55,89]:
        tot=run_all_years(d,sig,slb)
        print(f"   swing {slb:<3}  netR {tot:+.1f}")

if __name__=="__main__": main()
