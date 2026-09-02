#!/usr/bin/env python3
# xema_decade_cost.py — XEMA 13/34 +HTF +PSAR(0.08/0.5) swing SL, reverse-cross exit.
# Compares ALL-OFF (no ADX/BB) vs FILTERED (ADX+BB on) year-by-year, WITH spread cost.
# Cost model: subtract spread twice (entry+exit) as a fraction of R -> cost_R = 2*spread/R.
import importlib.util, argparse
import numpy as np, pandas as pd
spec=importlib.util.spec_from_file_location("xt","xema_test.py")
xt=importlib.util.module_from_spec(spec); spec.loader.exec_module(xt)
disc=xt.disc; PIP=0.0001; SWING_LB=12; SL_CUSHION=2*PIP; SL_MIN=5*PIP; BB_PERIOD=20
SPREAD_PIPS=0.8   # realistic EURUSD retail spread (round-trip applied as entry+exit)

def regime(dy):
    o=dy.open.iloc[0];c=dy.close.iloc[-1];net=(c-o)*1e4
    daily=dy.close.resample("1D").last().dropna();path=daily.diff().abs().sum()
    return net,(abs(daily.iloc[-1]-daily.iloc[0])/path if path>0 else 0)

def run_year(d,sigs,ex,spread):
    hi=d["high"].values;lo=d["low"].values;close=d["close"].values
    ef=d["ef"].values;es=d["es"].values;O=d["open"].values
    grossRs=[];netRs=[];free=0
    for (i,lng) in sigs:
        if i<free: continue
        entry=O[i+1]
        sw=lo[i-SWING_LB:i+1].min() if lng else hi[i-SWING_LB:i+1].max()
        R=max(abs(entry-sw)+SL_CUSHION,SL_MIN); sl0=entry-R if lng else entry+R
        rR,xi=xt.walk(hi,lo,close,ef,es,i+1,entry,sl0,R,ex,lng)
        costR=2.0*(spread*PIP)/R                       # spread on entry + exit, in R units
        grossRs.append(rR); netRs.append(rR-costR); free=xi+1
    g=np.array(grossRs); n=np.array(netRs); N=len(n)
    if N==0: return 0,0,0,0,0
    return N,100*np.mean(n>0),np.mean(g),np.mean(n),np.sum(n)

def build_all(csv,htf):
    xt.FAST,xt.SLOW,xt.START,xt.SLMODE,xt.ATR_MULT,xt.PSTEP,xt.PMAX=13,34,None,"swing",1.0,0.08,0.5
    df=xt.load(csv)
    tf="M15" if "_M15_" in csv else "H1" if "_H1_" in csv else "?"
    htf_dfs=[xt.load(htf)] if htf else ([xt.load(csv,"H4")] if tf=="H1" else [])
    d=xt.build(df,htf_dfs); hs=xt.htf_signs(d,htf_dfs)
    std=d["close"].rolling(BB_PERIOD).std().values
    widen=np.concatenate([[False],(std[1:]>std[:-1])])
    return d,hs,widen

def main():
    ap=argparse.ArgumentParser();ap.add_argument("csv");ap.add_argument("htf")
    ap.add_argument("--exit",default="REVCROSS");ap.add_argument("--spread",type=float,default=SPREAD_PIPS)
    a=ap.parse_args()
    d,hs,widen=build_all(a.csv,a.htf)
    allsig=xt.signals(d,hs,useHTF=1,useADX=0,useP=1)     # ALL-OFF (no ADX/BB)
    filsig0=xt.signals(d,hs,useHTF=1,useADX=1,useP=1)    # ADX on
    filsig=[(i,l) for (i,l) in filsig0 if widen[i]]      # ADX+BB on
    print(f"\n#### XEMA all-off vs filtered — exit {a.exit}, spread {a.spread}p — {a.csv.split('/')[-1]} ####")
    print(f"# ALL-OFF = no ADX/BB ; FILTERED = ADX+BB on. netR is AFTER cost.\n")
    print(f"{'year':6}{'effR':>6}   {'ALL-OFF  n  win% grossR netR  sumR':<40}{'FILTERED  n  win% netR sumR':<32}")
    yrs=sorted({d.index[i].year for (i,l) in allsig})
    tot_all=0; tot_fil=0
    for Y in yrs:
        dy=d[d.index.year==Y]
        if len(dy)<500: continue
        net,er=regime(dy)
        A=run_year(d,[(i,l) for (i,l) in allsig if d.index[i].year==Y],a.exit,a.spread)
        F=run_year(d,[(i,l) for (i,l) in filsig if d.index[i].year==Y],a.exit,a.spread)
        tot_all+=A[4]; tot_fil+=F[4]
        print(f"{Y:<6}{er:>6.2f}   n={A[0]:<4} {A[1]:>3.0f}% g{A[2]:+.2f} net{A[3]:+.2f} sum{A[4]:>+6.1f}R   "
              f"| n={F[0]:<3} {F[1]:>3.0f}% net{F[3]:+.2f} sum{F[4]:>+6.1f}R")
    print(f"\nDECADE TOTAL netR:  ALL-OFF {tot_all:+.0f}R   FILTERED {tot_fil:+.0f}R")

if __name__=="__main__": main()
