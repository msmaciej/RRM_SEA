#!/usr/bin/env python3
# m5_session.py — (1) measure the ACTUAL M5 swing-SL distance in pips, (2) break net R
# and SL-size down by hour-of-day to test the "flat during dead sessions" idea,
# (3) re-run M5 restricted to the active hours.
import importlib.util, argparse
import numpy as np, pandas as pd
spec=importlib.util.spec_from_file_location("xt","xema_test.py")
xt=importlib.util.module_from_spec(spec); spec.loader.exec_module(xt)
disc=xt.disc; PIP=0.0001; SWING_LB=55; SL_CUSHION=2*PIP; SL_MIN=5*PIP; BB_PERIOD=20; SPREAD=0.8
def ema(s,n): return s.ewm(alpha=2/(n+1),adjust=False).mean()
def htf_sign(ci,hdf,f,s):
    t=np.sign(ema(hdf["close"],f)-ema(hdf["close"],s)); t.index=hdf.index
    return t.reindex(t.index.union(ci)).ffill().reindex(ci).values

def main():
    ap=argparse.ArgumentParser();ap.add_argument("m5");ap.add_argument("htf")
    a=ap.parse_args()
    df=xt.load(a.m5); hdf=xt.load(a.htf); d=df.copy()
    d["ef"]=ema(d["close"],13); d["es"]=ema(d["close"],34)
    d["adx"]=disc.adx(d,14); d["adxmed"]=d["adx"].rolling(100).median()
    d["psar"]=disc.psar(d,0.08,0.5)
    std=d["close"].rolling(BB_PERIOD).std().values
    d["_widen"]=np.concatenate([[False],(std[1:]>std[:-1])])
    hs=htf_sign(d.index,hdf,13,34)
    ef=d["ef"].values;es=d["es"].values;adx=d["adx"].values;adxmed=d["adxmed"].values
    psar=d["psar"].values;close=d["close"].values;widen=d["_widen"].values
    hi=d["high"].values;lo=d["low"].values;O=d["open"].values;idx=d.index
    # collect signals with hour, R_pips, net R (independent, de-clustered by 3 bars)
    rows=[]; last=-10
    for i in range(60,len(d)-1):
        up=ef[i]>es[i] and ef[i-1]<=es[i-1]; dn=ef[i]<es[i] and ef[i-1]>=es[i-1]
        if not(up or dn): continue
        lng=up; h=hs[i]
        if np.isnan(h) or (h>0)!=lng: continue
        if adx[i]<adxmed[i]: continue
        if not((psar[i]<close[i]) if lng else (psar[i]>close[i])): continue
        if not widen[i]: continue
        if i-last<3: continue
        last=i; entry=O[i+1]
        sw=lo[i-SWING_LB:i+1].min() if lng else hi[i-SWING_LB:i+1].max()
        R=max(abs(entry-sw)+SL_CUSHION,SL_MIN); sl0=entry-R if lng else entry+R
        rR,_=xt.walk(hi,lo,close,ef,es,i+1,entry,sl0,R,"REVCROSS",lng)
        rows.append((idx[i].hour, R/PIP, rR-2.0*(SPREAD*PIP)/R))
    R_pips=np.array([r[1] for r in rows]); netR=np.array([r[2] for r in rows]); hr=np.array([r[0] for r in rows])
    print(f"\n#### M5 SL distance & session analysis — {a.m5.split('/')[-1]} ####")
    print(f"# de-clustered signals: {len(rows)}")
    print(f"# SL distance (pips): median {np.median(R_pips):.1f}  mean {np.mean(R_pips):.1f}  "
          f"p25 {np.percentile(R_pips,25):.1f}  p75 {np.percentile(R_pips,75):.1f}  min {R_pips.min():.1f}  max {R_pips.max():.1f}")
    print(f"# avg cost/trade at {SPREAD}p spread = 2*{SPREAD}/median_R = {2*SPREAD/np.median(R_pips):.3f} R")
    print(f"# gross meanR/trade {np.mean(netR+2*SPREAD*PIP/(R_pips*PIP)):.4f}  |  net meanR/trade {np.mean(netR):.4f}")
    print("\n# by hour-of-day (data clock):  hour  n   medSLpips   netR_sum")
    for H in range(24):
        m=hr==H
        if m.sum()==0: continue
        print(f"    {H:02d}   {m.sum():4d}    {np.median(R_pips[m]):5.1f}     {netR[m].sum():+7.1f}")
    # active-hours restriction: keep hours with positive net and reasonable SL
    good=[H for H in range(24) if (hr==H).sum()>0 and netR[hr==H].sum()>0]
    m=np.isin(hr,good)
    print(f"\n# restricted to net-positive hours {good}: n {m.sum()}  netR {netR[m].sum():+.1f}  "
          f"(vs all-hours {netR.sum():+.1f})")

if __name__=="__main__": main()
