#!/usr/bin/env python3
# =============================================================================
# rrm_org_confirm_test.py
# -----------------------------------------------------------------------------
# Test the operator's two proposed confirmations added to BASE RRM_ORG:
#   A = deep-trend align: EMA3/EMA4 position AND slope in bias dir  (same-TF)
#       + optional HIGHER-TF trend confirm (bias of a supplied HTF file)
#   B = structure break: signal closes through the prior N-bar Donchian extreme
#       (short: close < lowest-low[N] before the bar; long: close > highest-high[N])
#
# Verdict method = the clean one: of BASE candidates, does the confirmation cut
# LOSERS? (removed win% < kept win% => it helps).  Also full sequential P&L in R
# for BASE / +A / +B / +A+B under the trailing exit we found best.
#
#   entry next-bar open; SL=swing(12)+2p; R=|entry-SL|; results in R multiples.
#   exit  = TRAIL 1.0R (let-profits-run, operator's proposal)  [+ FIX 1:1 ref]
# =============================================================================
import importlib.util, argparse
import numpy as np, pandas as pd

spec = importlib.util.spec_from_file_location("disc", "rrm_org_discriminator.py")
disc = importlib.util.module_from_spec(spec); spec.loader.exec_module(disc)
PIP=0.0001; SWING_LB=12; SL_CUSHION=2*PIP; SL_MIN=5*PIP; DONCH_N=20

def last_swing(d,i,lng):
    w=d.iloc[i-SWING_LB:i+1]; return w["low"].min() if lng else w["high"].max()

def deep_trend(r, lng):                       # A: EMA3/EMA4 pos + slope in dir
    if lng: return (r.e3>r.e4) and (r.e3_sl>0) and (r.e4_sl>0)
    return (r.e3<r.e4) and (r.e3_sl<0) and (r.e4_sl<0)

def donch_break(d, i, lng, N=DONCH_N):        # B: close breaks prior N-bar extreme
    prior = d.iloc[i-N:i]
    if lng: return d["close"].iloc[i] > prior["high"].max()
    return d["close"].iloc[i] < prior["low"].min()

def htf_ok(htf_bias, ts, lng):                # A2: higher-TF bias agrees
    if htf_bias is None: return True
    b = htf_bias.asof(ts)
    if pd.isna(b): return True
    return (b>0) if lng else (b<0)

def build_htf_bias(htf_df):
    h=disc.build(htf_df)
    def bmap(row): 
        _,b=disc.phase_bias(row.e2,row.e3,row.e4); return b
    return h.apply(bmap, axis=1)

def exit_trail(d, ei, entry, sl0, R, k, lng):
    sl=sl0; peak=entry
    for j in range(ei,len(d)):
        hi,lo=d["high"].iloc[j],d["low"].iloc[j]
        if lng:
            if lo<=sl: return (sl-entry)/R, j
            if hi>peak: peak=hi; sl=max(sl,peak-k*R)
        else:
            if hi>=sl: return (sl-entry)/-R, j
            if lo<peak: peak=lo; sl=min(sl,peak+k*R)
    return ((d["close"].iloc[-1]-entry)/R if lng else (entry-d["close"].iloc[-1])/R), len(d)-1

def exit_fix(d, ei, entry, sl0, R, rr, lng):
    tp=entry+rr*R if lng else entry-rr*R; sl=sl0
    for j in range(ei,len(d)):
        hi,lo=d["high"].iloc[j],d["low"].iloc[j]
        if lng:
            if lo<=sl: return -1.0, j
            if hi>=tp: return rr, j
        else:
            if hi>=sl: return -1.0, j
            if lo<=tp: return rr, j
    return ((d["close"].iloc[-1]-entry)/R if lng else (entry-d["close"].iloc[-1])/R), len(d)-1

def qualifies(d,i,r,lng,useA,useB,htf_bias):
    if useA and not deep_trend(r,lng): return False
    if useA and not htf_ok(htf_bias, d.index[i], lng): return False
    if useB and not donch_break(d,i,lng): return False
    return True

def run_seq(d, useA, useB, htf_bias, exit_kind="trail", k=1.0, rr=1.0):
    i,n=91,len(d); Rs=[]
    while i<n-1:
        e=disc.evaluate_bar(d,i,1.0)
        if e.get("ts1"):
            r=d.iloc[i]; lng=e["bias"]>0
            if qualifies(d,i,r,lng,useA,useB,htf_bias):
                ei=i+1; entry=d["open"].iloc[ei]
                sw=last_swing(d,i,lng); R=max(abs(entry-sw)+SL_CUSHION,SL_MIN)
                sl0=entry-R if lng else entry+R
                if exit_kind=="trail": rR,xi=exit_trail(d,ei,entry,sl0,R,k,lng)
                else:                  rR,xi=exit_fix(d,ei,entry,sl0,R,rr,lng)
                Rs.append(rR); i=xi+1; continue
        i+=1
    return np.array(Rs)

def indep(d, htf_bias):
    """every base candidate (de-clustered), with A/B flags + trailing-1R outcome."""
    rows=[]; last=-10**9
    for i in range(91,len(d)-1):
        e=disc.evaluate_bar(d,i,1.0)
        if not e.get("ts1"): continue
        if i-last<6: continue
        last=i; r=d.iloc[i]; lng=e["bias"]>0
        ei=i+1; entry=d["open"].iloc[ei]
        sw=last_swing(d,i,lng); R=max(abs(entry-sw)+SL_CUSHION,SL_MIN)
        sl0=entry-R if lng else entry+R
        rR,_=exit_trail(d,ei,entry,sl0,R,1.0,lng)
        rows.append(dict(A=deep_trend(r,lng) and htf_ok(htf_bias,d.index[i],lng),
                         B=donch_break(d,i,lng), win=rR>0, R=rR))
    return rows

def wr(rows): 
    n=len(rows); return n,(100*np.mean([x["win"] for x in rows]) if n else 0),(np.mean([x["R"] for x in rows]) if n else 0)

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("csv"); ap.add_argument("--htf",default=None)
    a=ap.parse_args()
    d=disc.build(disc.load_csv(a.csv))
    htf_bias=build_htf_bias(disc.load_csv(a.htf)) if a.htf else None
    tf="H1" if "_H1_" in a.csv else "M15" if "_M15_" in a.csv else "?"
    print(f"\n############ {tf}  {a.csv.split('/')[-1]}  HTF={'none' if not a.htf else a.htf.split('/')[-1]} ############")
    print(f"# {len(d)} bars {d.index[0]}->{d.index[-1]} | Donchian N={DONCH_N} | exit TRAIL 1R\n")

    # B) per-confirmation: does it cut losers? (independent, de-clustered)
    rows=indep(d,htf_bias); bn,bw,bm=wr(rows)
    print(f"base candidates: n={bn}  win%={bw:.1f}  meanR={bm:+.2f}")
    for label,key in [("A (deep-trend+HTF)","A"),("B (structure break)","B")]:
        kept=[r for r in rows if r[key]]; rem=[r for r in rows if not r[key]]
        kn,kw,km=wr(kept); rn,rw,rm=wr(rem)
        verdict="HELPS" if (rn>0 and rw<kw) else ("—" if rn==0 else "hurts")
        print(f"  {label:22s} KEPT n={kn:3d} win%={kw:5.1f} R={km:+.2f} | REMOVED n={rn:3d} win%={rw:5.1f} R={rm:+.2f}  -> {verdict}")

    # A) sequential P&L for the four combos, trailing 1R + fixed 1:1 ref
    print(f"\n{'combo':16s}{'exit':9s}{'trades':>7}{'win%':>7}{'meanR':>8}{'totR':>8}")
    for label,useA,useB in [("BASE",0,0),("+A",1,0),("+B",0,1),("+A+B",1,1)]:
        for ek,kk,rr,tag in [("trail",1.0,None,"TRAIL1R"),("fix",None,1.0,"FIX1:1")]:
            R=run_seq(d,useA,useB,htf_bias,ek,kk if kk else 1.0,rr if rr else 1.0)
            n=len(R); win=100*np.mean(R>0) if n else 0; mn=np.mean(R) if n else 0
            print(f"{label:16s}{tag:9s}{n:>7}{win:>7.1f}{mn:>+8.2f}{np.sum(R):>+8.1f}")

if __name__=="__main__":
    main()
