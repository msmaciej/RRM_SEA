#!/usr/bin/env python3
# multiyear_rrm.py — BASE RRM_ORG (approx) year-by-year on M15, vectorized detector.
import importlib.util, argparse
import numpy as np, pandas as pd
spec=importlib.util.spec_from_file_location("disc","rrm_org_discriminator.py")
disc=importlib.util.module_from_spec(spec); spec.loader.exec_module(disc)
PIP=0.0001; SWING_LB=12; SL_CUSHION=2*PIP; SL_MIN=5*PIP

def base_candidates(d):
    e1,e2,e3,e4=d.e1.values,d.e2.values,d.e3.values,d.e4.values
    e1s,e2s,e3s,e4s=d.e1_sl.values,d.e2_sl.values,d.e3_sl.values,d.e4_sl.values
    o,h,l,c=d.open.values,d.high.values,d.low.values,d.close.values
    dpi,cci,psar=d.dpi.values,d.cci.values,d.psar.values
    TMUP=(e2>e3)&(e3>e4); TMDN=(e4>e3)&(e3>e2)
    EMUP=(e2>e4)&(e4>e3); EMDN=(e3>e4)&(e4>e2)
    bias=np.where(TMUP|EMUP,1,np.where(TMDN|EMDN,-1,0)); isTM=TMUP|TMDN
    lng=bias>0; sht=bias<0
    dpi_ok=(((dpi>0)&lng)|((dpi<0)&sht))&(np.sign(dpi)==np.sign(cci))
    psar_ok=((psar<c)&lng)|((psar>c)&sht)
    rng=np.maximum(h-l,1e-9)
    clr_l=(c-l)/rng; clr_s=(h-c)/rng
    cbody=(((c>o)&lng)&(clr_l>=0.75))|(((c<o)&sht)&(clr_s>=0.75))
    def sser(a): return pd.Series(a)
    def layer(fast,slow,fsl,ssl):
        pos=((fast>slow)&lng)|((fast<slow)&sht)
        bc=((c>fast)&lng)|((c<fast)&sht)
        fa=sser(np.abs(fsl))
        dip_abs=(fa.rolling(4).min()<0.1*fa.rolling(4).mean()).values
        anyneg=(sser((fsl<0).astype(int)).rolling(4).sum()>0).values
        anypos=(sser((fsl>0).astype(int)).rolling(4).sum()>0).values
        dipped=dip_abs|(anyneg&lng)|(anypos&sht)
        recov=((fsl>0)&(ssl>0)&lng)|((fsl<0)&(ssl<0)&sht)
        return pos&bc&dipped&recov
    LW=layer(e1,e2,e1s,e2s); LM=layer(e2,e3,e2s,e3s); LS=layer(e3,e4,e3s,e4s)&isTM
    base=(bias!=0)&dpi_ok&psar_ok&cbody&(LW|LM|LS)
    idx=np.where(base)[0]
    # de-cluster: min 6 bars apart
    out=[]; last=-10
    for i in idx:
        if i<91 or i>=len(d)-1: continue
        if i-last<6: continue
        last=i; out.append((i,bool(lng[i])))
    return out

def walk(hi,lo,close,ei,entry,sl0,R,ex,lng):
    n=len(hi)
    if ex.startswith("FIX"):
        rr=float(ex[3:]); tp=entry+rr*R if lng else entry-rr*R; sl=sl0
        for j in range(ei,n):
            if lng:
                if lo[j]<=sl: return -1.0,j
                if hi[j]>=tp: return rr,j
            else:
                if hi[j]>=sl: return -1.0,j
                if lo[j]<=tp: return rr,j
        return ((close[-1]-entry)/R if lng else (entry-close[-1])/R),n-1
    k=float(ex[5:]); sl=sl0; peak=entry
    for j in range(ei,n):
        if lng:
            if lo[j]<=sl: return (sl-entry)/R,j
            if hi[j]>peak: peak=hi[j]; sl=max(sl,peak-k*R)
        else:
            if hi[j]>=sl: return (sl-entry)/-R,j
            if lo[j]<peak: peak=lo[j]; sl=min(sl,peak+k*R)
    return ((close[-1]-entry)/R if lng else (entry-close[-1])/R),n-1

def seq(d,sigs,ex):
    hi=d.high.values;lo=d.low.values;close=d.close.values;O=d.open.values
    Rs=[];free=0
    for (i,lng) in sigs:
        if i<free: continue
        entry=O[i+1]; sw=lo[i-SWING_LB:i+1].min() if lng else hi[i-SWING_LB:i+1].max()
        R=max(abs(entry-sw)+SL_CUSHION,SL_MIN); sl0=entry-R if lng else entry+R
        rR,xi=walk(hi,lo,close,i+1,entry,sl0,R,ex,lng); Rs.append(rR); free=xi+1
    R=np.array(Rs);n=len(R)
    return n,(100*np.mean(R>0) if n else 0),(np.mean(R) if n else 0)

def regime(dy):
    o=dy.open.iloc[0];c=dy.close.iloc[-1];net=(c-o)*1e4
    daily=dy.close.resample("1D").last().dropna();path=daily.diff().abs().sum()
    er=abs(daily.iloc[-1]-daily.iloc[0])/path if path>0 else 0
    return net,er

def main():
    ap=argparse.ArgumentParser(); ap.add_argument("csv"); ap.add_argument("--sanity",action="store_true")
    a=ap.parse_args()
    d=disc.build(disc.load_csv(a.csv))
    sigs=base_candidates(d)
    if a.sanity:
        n,w,m=seq(d,sigs,"TRAIL1.0"); nf,wf,mf=seq(d,sigs,"FIX1.0")
        print(f"SANITY {a.csv.split('/')[-1]}: candidates {len(sigs)} | TRAIL1R {m:+.2f}({w:.0f}/{n}) FIX1:1 {mf:+.2f}({wf:.0f}/{nf})")
        return
    print(f"\n#### RRM_ORG base  M15  {a.csv.split('/')[-1]} ####")
    print(f"{'year':6}{'netPip':>8}{'effR':>6}{'| TRAIL1R meanR(win/n)':>26}{'| FIX1:1 meanR(win/n)':>24}")
    for Y in sorted({d.index[i].year for (i,lng) in sigs}):
        dy=d[d.index.year==Y]
        if len(dy)<500: continue
        net,er=regime(dy); ys=[(i,lng) for (i,lng) in sigs if d.index[i].year==Y]
        n,w,m=seq(d,ys,"TRAIL1.0"); nf,wf,mf=seq(d,ys,"FIX1.0")
        print(f"{Y:<6}{net:>+8.0f}{er:>6.2f}   {m:>+6.2f}({w:>3.0f}/{n:<4})       {mf:>+6.2f}({wf:>3.0f}/{nf:<4})")

if __name__=="__main__": main()
