#!/usr/bin/env python3
# m5_decade_session.py — M5 EURUSD with PRE-DEFINED session windows (structural, not fitted)
# across config variants. Independent/de-clustered scoring, net R after 0.8p cost.
# Windows (data clock): ALL | LDN_NY = hours 8-20 | NY = hours 12-21  (Asian/rollover dropped).
import importlib.util, argparse
import numpy as np, pandas as pd
spec=importlib.util.spec_from_file_location("xt","xema_test.py")
xt=importlib.util.module_from_spec(spec); spec.loader.exec_module(xt)
disc=xt.disc; PIP=0.0001; SL_CUSHION=2*PIP; SL_MIN=5*PIP; BB_PERIOD=20; SPREAD=0.8
W_LDNNY=set(range(8,21)); W_NY=set(range(12,22))
def ema(s,n): return s.ewm(alpha=2/(n+1),adjust=False).mean()
def htf_sign(ci,hdf,f,s):
    t=np.sign(ema(hdf["close"],f)-ema(hdf["close"],s)); t.index=hdf.index
    return t.reindex(t.index.union(ci)).ffill().reindex(ci).values

def score(d,hs,fast,slow,swing_lb,exit_mode):
    ef=ema(d["close"],fast).values; es=ema(d["close"],slow).values
    adx=d["adx"].values;adxmed=d["adxmed"].values;psar=d["psar"].values
    close=d["close"].values;widen=d["_widen"].values
    hi=d["high"].values;lo=d["low"].values;O=d["open"].values;idx=d.index
    rows=[]; last=-10
    start=max(120,swing_lb+2)
    for i in range(start,len(d)-1):
        up=ef[i]>es[i] and ef[i-1]<=es[i-1]; dn=ef[i]<es[i] and ef[i-1]>=es[i-1]
        if not(up or dn): continue
        lng=up; h=hs[i]
        if np.isnan(h) or (h>0)!=lng: continue
        if adx[i]<adxmed[i]: continue
        if not((psar[i]<close[i]) if lng else (psar[i]>close[i])): continue
        if not widen[i]: continue
        if i-last<3: continue
        last=i; entry=O[i+1]
        sw=lo[i-swing_lb:i+1].min() if lng else hi[i-swing_lb:i+1].max()
        R=max(abs(entry-sw)+SL_CUSHION,SL_MIN); sl0=entry-R if lng else entry+R
        rR,_=xt.walk(hi,lo,close,ef,es,i+1,entry,sl0,R,exit_mode,lng)
        rows.append((idx[i].hour, rR-2.0*(SPREAD*PIP)/R))
    return rows

def agg(rows,win):
    sel=[r[1] for r in rows if (win is None or r[0] in win)]
    a=np.array(sel); n=len(a)
    return n,(a.sum() if n else 0.0)

def main():
    ap=argparse.ArgumentParser();ap.add_argument("m5");ap.add_argument("htf_m15");ap.add_argument("htf_h1")
    a=ap.parse_args()
    df=xt.load(a.m5); d=df.copy()
    d["adx"]=disc.adx(d,14); d["adxmed"]=d["adx"].rolling(100).median()
    d["psar"]=disc.psar(d,0.08,0.5)
    std=d["close"].rolling(BB_PERIOD).std().values
    d["_widen"]=np.concatenate([[False],(std[1:]>std[:-1])])
    hsM15=htf_sign(d.index,xt.load(a.htf_m15),13,34)
    hsH1 =htf_sign(d.index,xt.load(a.htf_h1),13,34)
    tag=a.m5.split('/')[-1]
    print(f"\n#### M5 decade-session — {tag} (netR after {SPREAD}p; n) ####")
    print(f"{'config':26s}{'ALL hours':>16}{'LDN+NY 8-20':>16}{'NY 12-21':>16}")
    configs=[
        ("standard 13/34 HTF=M15", hsM15,13,34,55,"REVCROSS"),
        ("EMA 21/55  HTF=M15",     hsM15,21,55,55,"REVCROSS"),
        ("HTF=H1     13/34",       hsH1, 13,34,55,"REVCROSS"),
        ("swing 89   13/34",       hsM15,13,34,89,"REVCROSS"),
        ("exit FIX2  13/34",       hsM15,13,34,55,"FIX2.0"),
        ("EMA21/55 + FIX2 HTF=M15",hsM15,21,55,55,"FIX2.0"),
    ]
    for label,hs,f,s,slb,ex in configs:
        rows=score(d,hs,f,s,slb,ex)
        cells=[]
        for w in (None,W_LDNNY,W_NY):
            n,net=agg(rows,w); cells.append(f"{net:+.0f}R(n{n})")
        print(f"{label:26s}{cells[0]:>16}{cells[1]:>16}{cells[2]:>16}")

if __name__=="__main__": main()
