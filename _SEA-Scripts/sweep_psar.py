#!/usr/bin/env python3
# sweep_psar.py — vary PSAR step/max on XEMA 13/34 +HTF+ADX+PSAR (swing SL).
import importlib.util, argparse
import numpy as np, pandas as pd
spec=importlib.util.spec_from_file_location("xt","xema_test.py")
xt=importlib.util.module_from_spec(spec); spec.loader.exec_module(xt)
disc=xt.disc; PIP=0.0001; SWING_LB=12; SL_CUSHION=2*PIP; SL_MIN=5*PIP

SETTINGS=[(0.02,0.2),(0.03,0.3),(0.05,0.5),(0.08,0.5),(0.10,0.5),(0.02,0.5)]
EXITS=["FIX1.0","FIX2.0","REVCROSS"]

def seq(d,sigs,ex):
    hi=d["high"].values;lo=d["low"].values;close=d["close"].values
    ef=d["ef"].values;es=d["es"].values;O=d["open"].values
    Rs=[];free=0
    for (i,lng) in sigs:
        if i<free: continue
        entry=O[i+1]
        sw=lo[i-SWING_LB:i+1].min() if lng else hi[i-SWING_LB:i+1].max()
        R=max(abs(entry-sw)+SL_CUSHION,SL_MIN); sl0=entry-R if lng else entry+R
        rR,xi=xt.walk(hi,lo,close,ef,es,i+1,entry,sl0,R,ex,lng);Rs.append(rR);free=xi+1
    R=np.array(Rs);n=len(R)
    return n,(100*np.mean(R>0) if n else 0),(np.mean(R) if n else 0)

def main():
    ap=argparse.ArgumentParser();ap.add_argument("csv");ap.add_argument("--htf",nargs="*",default=[])
    ap.add_argument("--fast",type=int,default=13);ap.add_argument("--slow",type=int,default=34)
    a=ap.parse_args()
    xt.FAST,xt.SLOW,xt.START,xt.SLMODE,xt.ATR_MULT=a.fast,a.slow,None,"swing",1.0
    df=xt.load(a.csv)
    tf="M15" if "_M15_" in a.csv else "H1" if "_H1_" in a.csv else "?"
    if a.htf: htf_dfs=[xt.load(h) for h in a.htf]
    elif tf=="H1": htf_dfs=[xt.load(a.csv,"H4")]
    else: htf_dfs=[]
    d=xt.build(df,htf_dfs); hsigns=xt.htf_signs(d,htf_dfs)
    print(f"\n#### PSAR sweep — XEMA {a.fast}/{a.slow} +HTF+ADX+PSAR (swing SL)  {tf} ####")
    print(f"{'step/max':10}{'| FIX1:1':>16}{'| FIX2:1':>16}{'| REVCROSS':>16}")
    for (st,mx) in SETTINGS:
        d["psar"]=disc.psar(d,st,mx)
        sigs=xt.signals(d,hsigns,useHTF=1,useADX=1,useP=1)
        cells=[]
        for ex in EXITS:
            n,w,m=seq(d,sigs,ex); cells.append(f"{m:+.2f}({w:.0f}/{n})")
        print(f"{st:.2f}/{mx:<5}{cells[0]:>16}{cells[1]:>16}{cells[2]:>16}")

if __name__=="__main__": main()
