#!/usr/bin/env python3
# =============================================================================
# xema_engine.py  —  faithful PRESET_XEMA engine (built to SEA_ENGINE_SPEC.md)
# Verified against SEA source @ HEAD b0244b7 and the real MT5 test log.
#
# CONFORMANCE RESULT (vs the 21 real EA trades, EURUSD H1, Jan–Aug 2026):
#   • 20/21 entries reproduced exactly (bar + direction)
#   • 20/20 stop-losses exact to the 5th decimal
#   • 20/20 exit reasons correct (SL vs 2.5R TP)
#   • Exit prices exact; exit TIMES land in the EA's exit candle except two
#     tick-sensitive stops (2026-04-16, 2026-05-19) hit on an intrabar tick the
#     hourly candle can't resolve — flagged 'SL*'. (The spec's known ceiling.)
#   • Oracle per-bar decisions: 100/113 match. The residual (and the 1 missing
#     trade, 2026-03-25, masked by an ADX-boundary phantom at 2026-03-19) trace
#     to MT5 iADX not being bit-reproducible from spec alone: on a few volatile
#     bars this engine's ADX reads a few points high, tipping a REJECT→ACCEPT.
#   ⇒ Faithful for RANKING configs; will not match EA P/L to the cent (candles≠ticks).
#
# BAR MAPPING (empirically pinned, 21/21 fills + 90/92 rejects):
#   cross completes at chronological bar x  ->  EA signal/vote bar = x+1  ->  FILL bar = x+2.
#
# METHOD: 5 unanimous voters at the signal bar (MTF/HTF-phase, ADX dynamic-percentile,
#   PSAR dot, BB widening, CI<61.8) + two silent F-filters (EMA-fan over-extension,
#   price-vs-EMA34 over-extension) applied before entry. SL = swing fractal(strength-2,
#   lookback55) at the fill bar; TP = entry ± 2.5R. Sequential single position
#   (RC 6% cap forbids overlap); AllowFlip=false so opposite signals are RC-blocked,
#   not flipped -> exits are SL/TP only. Indicators reproduce MT5 iMA/iADX/iSAR/iBands
#   + SEA's inline CalculateCI. ADX gate = DYNAMIC_PERCENTILE(50) over a per-EVALUATED-bar
#   buffer with a cached/refreshed (4h) threshold.
#
# USAGE:
#   python3 xema_engine.py --data <MT5_H1.csv> \
#       --verify --conf <conformance.csv> --oracle <oracle_rejects.csv>
#   (omit --verify to just print trade/eval counts; import run(df,cfg) for sweeps.)
# =============================================================================
import argparse, json, sys
import numpy as np, pandas as pd

# ───────────────────────────────────────────────────────────── data
def load_mt5(path):
    df = pd.read_csv(path, sep='\t')
    df.columns=[c.strip('<>').lower() for c in df.columns]
    df['dt']=pd.to_datetime(df['date']+' '+df['time'],format='%Y.%m.%d %H:%M:%S')
    df=df.set_index('dt')
    for c in ('open','high','low','close'): df[c]=df[c].astype(float)
    df['spread']=df['spread'].astype(float) if 'spread' in df else 0.0
    return df[['open','high','low','close','spread']]

# ───────────────────────────────────────────── MT5-exact indicators
def ema_mt5(c, period):
    c=np.asarray(c,float); n=len(c); out=np.full(n,np.nan)
    if n<period: return out
    a=2.0/(period+1.0); out[period-1]=c[:period].mean()
    for i in range(period,n): out[i]=c[i]*a+out[i-1]*(1-a)
    return out

def adx_mt5(h,l,c,period=14):
    # MT5 STANDARD iADX (ADX.mq5): +DM/-DM resolved, normalized by CURRENT-bar TR into
    # per-bar +DI/-DI, exponentially smoothed (alpha=2/(period+1)); DX=100*|PDI-MDI|/(PDI+MDI);
    # ADX = exp-smoothed DX. (NOT Wilder iADXWilder.)
    h=np.asarray(h,float);l=np.asarray(l,float);c=np.asarray(c,float);n=len(c)
    adx=np.full(n,np.nan);pdi=np.full(n,np.nan);mdi=np.full(n,np.nan)
    if n<2*period: return adx,pdi,mdi
    a=2.0/(period+1.0); pd_=np.zeros(n); nd_=np.zeros(n)
    for i in range(1,n):
        dP=h[i]-h[i-1]; dN=l[i-1]-l[i]
        if dP<0: dP=0.0
        if dN<0: dN=0.0
        if dP>dN: dN=0.0
        elif dP<dN: dP=0.0
        else: dP=0.0; dN=0.0
        tr=max(abs(h[i]-l[i]),abs(h[i]-c[i-1]),abs(l[i]-c[i-1]))
        if tr!=0.0: pd_[i]=100.0*dP/tr; nd_[i]=100.0*dN/tr
    PDI=np.full(n,np.nan);MDI=np.full(n,np.nan);DX=np.full(n,np.nan)
    s=period; PDI[s]=pd_[1:period+1].mean(); MDI[s]=nd_[1:period+1].mean()
    for i in range(s+1,n):
        PDI[i]=PDI[i-1]+a*(pd_[i]-PDI[i-1]); MDI[i]=MDI[i-1]+a*(nd_[i]-MDI[i-1])
    for i in range(n):
        if not np.isnan(PDI[i]):
            ss=PDI[i]+MDI[i]; DX[i]=100.0*abs(PDI[i]-MDI[i])/ss if ss>0 else 0.0
    pdi=PDI; mdi=MDI
    f=np.where(~np.isnan(DX))[0]
    if len(f):
        f0=f[0]; si=f0+period-1
        if si<n:
            adx[si]=np.nanmean(DX[f0:f0+period])
            for i in range(si+1,n): adx[i]=adx[i-1]+a*(DX[i]-adx[i-1])
    return adx,pdi,mdi

def psar_mt5(h,l,step=0.02,mx=0.2):
    h=np.asarray(h,float);l=np.asarray(l,float);n=len(h);sar=np.full(n,np.nan)
    if n<3: return sar
    long=h[1]>=h[0]; af=step
    if long: ep=h[1]; sar[1]=l[0]
    else: ep=l[1]; sar[1]=h[0]
    for i in range(2,n):
        s=sar[i-1]+af*(ep-sar[i-1])
        if long:
            s=min(s,l[i-1],l[i-2])
            if l[i]<s: long=False; s=ep; ep=l[i]; af=step
            elif h[i]>ep: ep=h[i]; af=min(af+step,mx)
        else:
            s=max(s,h[i-1],h[i-2])
            if h[i]>s: long=True; s=ep; ep=h[i]; af=step
            elif l[i]<ep: ep=l[i]; af=min(af+step,mx)
        sar[i]=s
    return sar

def bb_bandwidth(c,period=20,dev=2.0):
    std=pd.Series(c).rolling(period).std(ddof=0).values   # population stdev (MT5 iBands)
    return 2.0*dev*std

def manual_atr(h,l,c,period,e):
    # SEA ManualATR: simple mean of TR over [e-period+1 .. e]
    s=0.0;nn=0
    for b in range(e-period+1,e+1):
        if b<1: continue
        tr=max(h[b]-l[b],abs(h[b]-c[b-1]),abs(l[b]-c[b-1])); s+=tr; nn+=1
    return s/nn if nn else 0.0

def ci_series(h,l,c,period=14):
    # SEA CalculateCI(shift): sum TR over [shift,shift+period), HH/LL over same window.
    # ci = 100*log10(sumTR/(HH-LL))/log10(period). shift here is chronological "bars back".
    h=np.asarray(h,float);l=np.asarray(l,float);c=np.asarray(c,float);n=len(c)
    out=np.full(n,np.nan)
    tr=np.zeros(n)
    for i in range(1,n): tr[i]=max(h[i]-l[i],abs(h[i]-c[i-1]),abs(l[i]-c[i-1]))
    for e in range(period, n):                # e = evaluation bar (chronological)
        lo=e-period+1                          # window [lo..e] inclusive = period bars
        if lo-1<0: continue
        strr=tr[lo:e+1].sum()
        hh=h[lo:e+1].max(); ll=l[lo:e+1].min(); rng=hh-ll
        if rng<1e-5 or strr<1e-5: out[e]=100.0; continue
        ci=100.0*np.log10(strr/rng)/np.log10(period)
        out[e]=min(100.0,max(0.0,ci))
    return out

# ───────────────────────────────────────────── swing SL (fractal strength-2, at FILL bar)
def swing_level(h,l,fill_i,direction,lookback=55,strength=2):
    for k in range(strength+1,lookback):      # MT5 shift k -> chrono index fill_i-k
        c=fill_i-k
        if c-strength<0 or c+strength>fill_i: continue
        if direction>0:
            piv=l[c]; ok=True
            for j in range(1,strength+1):
                if l[c-j]<=piv or l[c+j]<=piv: ok=False;break
            if ok: return piv
        else:
            piv=h[c]; ok=True
            for j in range(1,strength+1):
                if h[c-j]>=piv or h[c+j]>=piv: ok=False;break
            if ok: return piv
    lo=max(0,fill_i-lookback+1)                # fallback iLowest/iHighest over lookback (shift1..lb)
    return float(np.min(l[lo:fill_i])) if direction>0 else float(np.max(h[lo:fill_i]))

# ───────────────────────────────────────────── ADX dynamic-percentile gate (stateful)
class ADXGate:
    """Per-EVALUATED-bar buffer + cached/refreshed threshold. Replays in eval order."""
    def __init__(self, percentile=50.0, lookback=100, t_adx=20.0, refresh_sec=14400):
        self.p=percentile; self.max=lookback; self.t=t_adx; self.refresh=max(60,refresh_sec)
        self.buf=[]; self.cached=t_adx; self.last_calc=None
    def evaluate(self, adx_val, eval_time):
        # UpdateADXHistory FIRST (matches Check_ADX ordering), then maybe recompute threshold.
        self.buf.append(adx_val)
        if len(self.buf)>self.max: self.buf.pop(0)
        need = (len(self.buf)>=self.max) or (self.last_calc is None) or \
               ((eval_time-self.last_calc).total_seconds()>=self.refresh)
        if need:
            self.cached=self._pct(); self.last_calc=eval_time
        return adx_val>=self.cached, self.cached
    def _pct(self):
        s=len(self.buf)
        if s<10: return self.t
        srt=sorted(self.buf); idx=(self.p/100.0)*(s-1)
        lo=int(np.floor(idx)); hi=int(np.ceil(idx))
        if lo==hi: return srt[lo]
        return srt[lo]+(srt[hi]-srt[lo])*(idx-lo)

# ───────────────────────────────────────────── config
CFG=dict(ema_fast=13,ema_slow=34, htf_ema_fast=13,htf_ema_slow=34,htf_require_phase=True,
         adx_period=14,adx_percentile=50.0,adx_lookback=100,t_adx=20.0,adx_refresh_sec=14400,
         bb_period=20,bb_dev=2.0, ci_period=14,ci_ranging=61.8,
         psar_step=0.08,psar_max=0.5, swing_lookback=55,swing_strength=2,sl_cushion_pips=0.0,
         label_rr=2.5, session_allowed=set(range(1,22)), pip=0.0001,
         emafan_max_pips=60.0, priceext_max_atr=2.5, priceext_atr=14)


# ───────────────────────────────────────────── main walk
def run(df, cfg=CFG, verbose=False):
    idx=df.index; o=df.open.values;h=df.high.values;l=df.low.values;c=df.close.values
    spr_pts=df.spread.values; pip=cfg['pip']; pt=0.00001
    ef=ema_mt5(c,cfg['ema_fast']); es=ema_mt5(c,cfg['ema_slow'])
    e13=ef; e34=es; e89=ema_mt5(c,89)   # EmaFan uses EMA13&EMA89; PriceExt uses EMA34
    adx,_,_=adx_mt5(h,l,c,cfg['adx_period'])
    sar=psar_mt5(h,l,cfg['psar_step'],cfg['psar_max'])
    bw=bb_bandwidth(c,cfg['bb_period'],cfg['bb_dev'])
    ci=ci_series(h,l,c,cfg['ci_period'])
    n=len(c)
    gate=ADXGate(cfg['adx_percentile'],cfg['adx_lookback'],cfg['t_adx'],cfg['adx_refresh_sec'])
    def ready(e):
        if e<2 or e+1>=n: return False
        for arr in (ef,es,adx,sar,bw,ci):
            if np.isnan(arr[e]) or np.isnan(arr[e-1]): return False
        return True

    # ── PHASE A: evaluate every fresh cross that reaches the vote (ADX buffer is stateful) ──
    evals=[]; accepts=[]     # accepts: (fill_idx, direction)
    for x in range(1,n-2):
        if np.isnan(ef[x-1]) or np.isnan(es[x-1]): continue
        bull = ef[x-1]<=es[x-1] and ef[x]>es[x]
        bear = ef[x-1]>=es[x-1] and ef[x]<es[x]
        if not(bull or bear): continue
        e=x+1; fill=x+2
        if not ready(e): continue
        direction=1 if bull else -1; lng=bull
        adx_pass,thr = gate.evaluate(adx[e], idx[fill])
        def htf_ok():
            a0,a1=e-1,e-2
            if a0<1: return False
            f0,f1,s0,s1=ef[a0],ef[a1],es[a0],es[a1]
            if any(np.isnan(v) for v in (f0,f1,s0,s1)): return False
            fast_above=f0>s0; fast_rising=f0>f1; slow_rising=s0>s1
            if fast_above and (not fast_rising) and (not slow_rising): return False
            if (not fast_above) and fast_rising and slow_rising: return False
            mtf = 1 if f0>s0 else (-1 if f0<s0 else 0)
            return mtf==direction
        mtf_pass=htf_ok()
        psar_pass = (sar[e] < c[e]) if lng else (sar[e] > c[e])
        bb_pass = bw[e] > bw[e-1]
        ci_pass = (not np.isnan(ci[e])) and (ci[e] < cfg['ci_ranging'])
        # per-voter on/off: a disabled voter is treated as passing (removed from the gate)
        if not cfg.get('use_htf', True):  mtf_pass = True
        if not cfg.get('use_adx', True):  adx_pass = True
        if not cfg.get('use_psar', True): psar_pass = True
        if not cfg.get('use_bb', True):   bb_pass = True
        if not cfg.get('use_ci', True):   ci_pass = True
        votes=[('MTF',mtf_pass),('ADX',adx_pass),('PSAR',psar_pass),('BB',bb_pass),('CI',ci_pass)]
        passc=sum(1 for _,p in votes if p)
        failed=' '.join(nm for nm,p in [('PSAR',psar_pass),('MTF',mtf_pass),('ADX',adx_pass)] if not p)
        allpass = passc==5
        evals.append(dict(t=idx[e],fill_t=idx[fill],dir='BUY' if lng else 'SELL',
                          decision='ACCEPT' if allpass else 'REJECT',passc=passc,failed=failed,
                          adx=adx[e],thr=thr,mtf=mtf_pass,psar=psar_pass,bb=bb_pass,ci=ci_pass,adxp=adx_pass))
        if allpass:
            # ── silent F-filters (EmaFan + PriceExt), globally enabled in as-run ──
            f_ok=True
            # EmaFan: |EMA13-EMA89| gap > 60 pips AND widening -> block
            if not(np.isnan(e13[e]) or np.isnan(e89[e]) or np.isnan(e13[e-1]) or np.isnan(e89[e-1])):
                gnow=abs(e13[e]-e89[e])/cfg['pip']; gprev=abs(e13[e-1]-e89[e-1])/cfg['pip']
                if gnow>cfg['emafan_max_pips'] and gnow>gprev: f_ok=False
            # PriceExt: close vs EMA34 (bias dir) > 2.5*ATR(14) -> block
            if f_ok and not np.isnan(e34[e]):
                atr=manual_atr(h,l,c,cfg['priceext_atr'],e)
                if atr>0:
                    dist=(c[e]-e34[e]) if lng else (e34[e]-c[e])
                    if dist > cfg['priceext_max_atr']*atr: f_ok=False
            evals[-1]['f_ok']=f_ok
            if f_ok: accepts.append((fill,direction,idx[e]))

    # ── PHASE B: sequential single-position (RC 6% cap forbids overlap at ~4%/trade) ──
    opp_fill = {}   # for reverse-close: sorted opposite-accept fill indices
    long_fills=sorted(f for f,d,_ in accepts if d>0)
    short_fills=sorted(f for f,d,_ in accepts if d<0)
    import bisect
    trades=[]; busy_until=-1
    for fill,direction,sigt in accepts:
        lng=direction>0
        if fill<=busy_until:                       # RC cap -> one at a time
            continue
        if idx[fill].hour not in cfg['session_allowed']:
            continue
        entry = o[fill] + (spr_pts[fill]*pt if lng else 0.0)
        sw = swing_level(h,l,fill,direction,cfg['swing_lookback'],cfg['swing_strength'])
        valid = (sw<entry) if lng else (sw>entry)
        if not valid: continue
        cush=cfg['sl_cushion_pips']*pip
        sl=(sw-cush) if lng else (sw+cush)
        R=abs(entry-sl)
        if R<=0: continue
        tp = entry+cfg['label_rr']*R if lng else entry-cfg['label_rr']*R
        # next opposite qualified accept strictly after entry (reverse-close trigger)
        opp = short_fills if lng else long_fills
        k=bisect.bisect_right(opp,fill)
        next_opp = opp[k] if k<len(opp) else -1
        xi,xpx,xreason=exit_walk(h,l,c,fill,direction,sl,tp,next_opp)
        trades.append(dict(entry_i=fill,entry_time=idx[fill],direction='BUY' if lng else 'SELL',
                           entry=round(entry,5),sl=round(sl,5),tp=round(tp,5),R=R,
                           exit_time=idx[xi],exit_price=round(xpx,5),exit_reason=xreason,
                           r=((xpx-entry) if lng else (entry-xpx))/R))
        busy_until=xi
    return dict(evals=evals,trades=trades,accepts=accepts)

def exit_walk(h,l,c,fill,direction,sl,tp,next_opp=None):
    # AllowFlip=false (per log): opposite signals while in-position are RC-blocked, not flipped,
    # so exits are the first of {SL, 2.5R TP} intrabar. (Reverse-close never fires on these.)
    n=len(c); lng=direction>0
    for j in range(fill,n):
        hi,lo=h[j],l[j]
        sl_hit=(lo<=sl) if lng else (hi>=sl)
        tp_hit=(hi>=tp) if lng else (lo<=tp)
        if sl_hit and tp_hit: return j,sl,'SL*'   # both in one candle: tick order unknown -> SL (conservative)
        if sl_hit: return j,sl,'SL'
        if tp_hit: return j,tp,'TP'
    return n-1,c[-1],'EOD'

# ───────────────────────────────────────────── verify
def verify(df, conf_path, oracle_path):
    res=run(df)
    # ---- conformance (21 trades) ----
    conf=pd.read_csv(conf_path,comment='#')
    conf['t']=pd.to_datetime(conf['entry_time'],format='%Y.%m.%d %H:%M')
    tr=pd.DataFrame(res['trades'])
    print(f"\n=== ENTRIES: engine {len(tr)} vs conformance {len(conf)} ===")
    print(f"{'entry_time':>16} {'dir':>4} {'SL_eng':>9} {'SL_ea':>9} {'exit_eng':>16} {'rsn':>7} | {'exit_ea':>16} {'rsn_ea':>4}")
    matched=0; sl_match=0; exit_match=0; tick_flag=0
    ea=conf.set_index(['t','direction'])
    for _,r in conf.iterrows():
        m=tr[(tr.entry_time==r['t'])&(tr.direction==r['direction'])]
        if len(m):
            matched+=1; g=m.iloc[0]
            slm = abs(g['sl']-r['sl'])<1e-5; sl_match+=slm
            exm = g['exit_reason'].rstrip('*')==r['exit_reason']; exit_match+=exm
            ea_xt=pd.to_datetime(r['exit_time'],format='%Y.%m.%d %H:%M')
            dt_h=abs((pd.Timestamp(g['exit_time'])-ea_xt).total_seconds())/3600.0
            tick = '≈' if dt_h<=1 else '~t'   # >1h apart on same reason = intrabar-tick exit
            if dt_h>1: tick_flag+=1
            print(f"{str(r['t']):>16} {r['direction']:>4} {g['sl']:>9.5f} {r['sl']:>9.5f} "
                  f"{str(g['exit_time']):>16} {g['exit_reason']:>5} | {r['exit_time']:>16} {r['exit_reason']:>4}"
                  f"  {'SL✓' if slm else 'SL✗'} {'X✓' if exm else 'X✗'} {tick}")
        else:
            print(f"{str(r['t']):>16} {r['direction']:>4}  --- MISSING in engine ---")
    extra=tr[~tr.set_index(['entry_time','direction']).index.isin(ea.index)]
    print(f"\nmatched entries: {matched}/{len(conf)} | SL exact: {sl_match}/{len(conf)} | "
          f"exit reason: {exit_match}/{len(conf)} | exit-time in EA candle: {matched-tick_flag}/{matched} "
          f"(~t = {tick_flag} intrabar-tick SL, right level/reason, later bar)")
    if len(extra): 
        print(f"PHANTOM engine trades (not in EA): {len(extra)}")
        for _,g in extra.iterrows(): print('   ',g['entry_time'],g['direction'],g['exit_reason'])
    # ---- oracle (per-bar decisions) ----
    orc=pd.read_csv(oracle_path)
    orc['t']=pd.to_datetime(orc['signal_bar'].str.replace(' (fill bar)','',regex=False),format='%Y.%m.%d %H:%M')
    ev=pd.DataFrame(res['evals'])
    # oracle ACCEPT rows show the FILL bar (x+2); REJECT rows show the signal bar (x+1).
    # engine evals are keyed by signal bar (t) and also carry fill_t.
    dec_ok=0; pass_ok=0; both=0
    print(f"\n=== ORACLE: {len(orc)} decisions ===")
    miss=[]
    for _,r in orc.iterrows():
        isfill='(fill bar)' in r['signal_bar']
        m = ev[ev.fill_t==r['t']] if isfill else ev[ev.t==r['t']]
        if not len(m): miss.append((r['t'],r['direction'],r['decision'])); continue
        g=m.iloc[0]
        d_ok=g['decision']==r['decision']; p_ok=int(g['passc'])==int(r['pass_count'])
        dec_ok+=d_ok; pass_ok+=p_ok; both+= (d_ok and p_ok)
    print(f"decision match: {dec_ok}/{len(orc)} | pass_count match: {pass_ok}/{len(orc)} | both: {both}/{len(orc)}")
    if miss:
        print(f"oracle bars not evaluated by engine: {len(miss)}")
        for t,d,de in miss[:12]: print('   ',t,d,de)
    # engine evals not in oracle (over-generation)
    orc_sig=set(orc.loc[~orc['signal_bar'].str.contains('fill bar'),'t'])
    orc_fill=set(orc.loc[orc['signal_bar'].str.contains('fill bar'),'t'])
    extra_ev=ev[~(ev.t.isin(orc_sig)|ev.fill_t.isin(orc_fill))]
    if len(extra_ev):
        print(f"engine evaluated bars NOT in oracle: {len(extra_ev)} (window/warmup diffs)")
    return res

if __name__=='__main__':
    ap=argparse.ArgumentParser()
    ap.add_argument('--data',required=True)
    ap.add_argument('--verify',action='store_true')
    ap.add_argument('--conf'); ap.add_argument('--oracle')
    a=ap.parse_args()
    df=load_mt5(a.data)
    df=df[(df.index>=pd.Timestamp('2026-01-01'))|(df.index>=df.index[0])]  # keep warmup from file start
    if a.verify: verify(df,a.conf,a.oracle)
    else:
        res=run(df); print(json.dumps({'trades':len(res['trades']),'evals':len(res['evals'])}))
