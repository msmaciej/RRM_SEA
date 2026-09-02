#!/usr/bin/env python3
# xema_divergence_test.py — prototype the price-vs-DPI divergence idea before any MQL5.
# Uses TRUE fractal pivots (Bill-Williams style, L=2 => 5-bar) like iFractals.
# Gates added to the operator's live XEMA config (13/34 HTF ADX BB PSAR0.08 swing55):
#   reg2/reg3 = BLOCK regular (exhaustion) divergence over last 2/3 pivots
#   hid2/hid3 = REQUIRE hidden (continuation) divergence over last 2/3 pivots
#   LONG  regular-bearish: highs rising + DPI falling      -> block
#         hidden-bullish : lows  rising + DPI falling      -> confirm
#   SHORT mirror on the opposite pivots.
import importlib.util, argparse
import numpy as np
spec=importlib.util.spec_from_file_location("xt","xema_test.py")
xt=importlib.util.module_from_spec(spec); spec.loader.exec_module(xt)
disc=xt.disc; PIP=0.0001; SWING_LB=55; SL_CUSHION=2*PIP; SL_MIN=5*PIP; BB_PERIOD=20
SPREAD=0.8; PIV_L=2

def build(csv,htf):
    xt.FAST,xt.SLOW,xt.START,xt.SLMODE,xt.ATR_MULT,xt.PSTEP,xt.PMAX=13,34,None,"swing",1.0,0.08,0.5
    df=xt.load(csv)
    d=xt.build(df,[xt.load(htf)]); hs=xt.htf_signs(d,[xt.load(htf)])
    d["dpi"]=disc.dpi(d)
    std=d["close"].rolling(BB_PERIOD).std().values
    d["_widen"]=np.concatenate([[False],(std[1:]>std[:-1])])
    return d,hs

def fractal_pivots(d,L=PIV_L):
    h=d["high"].values; l=d["low"].values; dp=d["dpi"].values; n=len(d)
    hi_idx=[];hi_px=[];hi_dp=[]; lo_idx=[];lo_px=[];lo_dp=[]
    for j in range(L,n-L):
        seg_h=h[j-L:j+L+1]; seg_l=l[j-L:j+L+1]
        if h[j]==seg_h.max() and list(seg_h).count(h[j])==1:
            hi_idx.append(j+L); hi_px.append(h[j]); hi_dp.append(dp[j])   # confirmed at j+L
        if l[j]==seg_l.min() and list(seg_l).count(l[j])==1:
            lo_idx.append(j+L); lo_px.append(l[j]); lo_dp.append(dp[j])
    return (np.array(hi_idx),np.array(hi_px),np.array(hi_dp),
            np.array(lo_idx),np.array(lo_px),np.array(lo_dp))

def last_n(idx,px,dp,i,N):
    m=np.searchsorted(idx,i,side="right")   # pivots confirmed strictly before/at i
    if m<N: return None
    return px[m-N:m], dp[m-N:m]              # chronological oldest->recent

def rising(a):  return all(a[k]<a[k+1] for k in range(len(a)-1))
def falling(a): return all(a[k]>a[k+1] for k in range(len(a)-1))

def gate_ok(i,lng,gate,piv,N):
    hi_idx,hi_px,hi_dp,lo_idx,lo_px,lo_dp=piv
    if gate=="reg":                          # block exhaustion divergence
        if lng:
            r=last_n(hi_idx,hi_px,hi_dp,i,N)
            if r is None: return True
            px,dp=r; return not(rising(px) and falling(dp))     # reg bearish present -> block
        else:
            r=last_n(lo_idx,lo_px,lo_dp,i,N)
            if r is None: return True
            px,dp=r; return not(falling(px) and rising(dp))     # reg bullish present -> block
    else:                                    # require continuation divergence
        if lng:
            r=last_n(lo_idx,lo_px,lo_dp,i,N)
            if r is None: return False
            px,dp=r; return rising(px) and falling(dp)          # hidden bullish
        else:
            r=last_n(hi_idx,hi_px,hi_dp,i,N)
            if r is None: return False
            px,dp=r; return falling(px) and rising(dp)          # hidden bearish

def run_year(d,sigs,spread):
    hi=d["high"].values;lo=d["low"].values;close=d["close"].values
    ef=d["ef"].values;es=d["es"].values;O=d["open"].values
    net=[];free=0
    for (i,lng) in sigs:
        if i<free: continue
        entry=O[i+1]
        sw=lo[i-SWING_LB:i+1].min() if lng else hi[i-SWING_LB:i+1].max()
        R=max(abs(entry-sw)+SL_CUSHION,SL_MIN); sl0=entry-R if lng else entry+R
        rR,xi=xt.walk(hi,lo,close,ef,es,i+1,entry,sl0,R,"REVCROSS",lng)
        net.append(rR-2.0*(spread*PIP)/R); free=xi+1
    a=np.array(net); return len(a),np.sum(a)

def main():
    ap=argparse.ArgumentParser();ap.add_argument("csv");ap.add_argument("htf");a=ap.parse_args()
    d,hs=build(a.csv,a.htf); piv=fractal_pivots(d)
    base=[(i,l) for (i,l) in xt.signals(d,hs,useHTF=1,useADX=1,useP=1) if d["_widen"].values[i]]
    variants={"baseline":(None,0),"+reg2":("reg",2),"+reg3":("reg",3),"+hid2":("hid",2),"+hid3":("hid",3)}
    print(f"\n#### divergence prototype — live cfg — {a.csv.split('/')[-1]} (pivots L={PIV_L}, spread {SPREAD}p) ####")
    hdr="year".ljust(6)
    for k in variants: hdr+=f"{k:>16}"
    print(hdr)
    tot={k:0.0 for k in variants}
    for Y in sorted({d.index[i].year for (i,l) in base}):
        if len(d[d.index.year==Y])<500: continue
        row=f"{Y:<6}"
        for name,(g,N) in variants.items():
            ys=[(i,l) for (i,l) in base if d.index[i].year==Y and (g is None or gate_ok(i,l,g,piv,N))]
            n,s=run_year(d,ys,SPREAD); tot[name]+=s
            row+=f"{s:>+7.1f}R(n{n:<3})".rjust(16)
        print(row)
    print("\nDECADE netR:  "+"  ".join(f"{k} {tot[k]:+.0f}" for k in variants))

if __name__=="__main__": main()
