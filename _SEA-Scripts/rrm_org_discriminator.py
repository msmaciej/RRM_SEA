#!/usr/bin/env python3
# =============================================================================
# rrm_org_discriminator.py
# -----------------------------------------------------------------------------
# Purpose: read an MT5 price CSV, reconstruct BASE PRESET_RRM_ORG TS=1 candidate
# bars (approximation, NOT the EA's authoritative EvaluateTS_Breakdown), and for
# each candidate compute the CONTEXT / OVER-EXTENSION discriminators that the
# already-coded-but-OFF RRM_ORG gates use, then report which added gate would
# veto each candidate.
#
# What is EXACT (computed straight from OHLC, faithful to the engine's math):
#   EMA 5/13/34/89, phase/bias, DPI(MACD 8/13 + EMA13 signal + CCI13),
#   PSAR(0.02/0.2), ATR14, ADX14, Choppiness Index(14), EMA-fan width (pips),
#   ATR-extension, ClimaxGuard bar/move ATR ratios, DPI exhaustion-divergence.
#
# What is APPROXIMATE (labelled hypothesis, framework Gate 5):
#   the BASE TS=1 candidate detection (esp. the layer pullback->recovery state
#   machine). It is only used to FIND signal bars for the demonstration; the
#   discriminator FEATURES it reports for each bar are exact. For an authoritative
#   TS verdict, the EA / SignalScan remain the source of truth.
#
# Usage:
#   python3 rrm_org_discriminator.py FILE.csv [--resample H1] [--rr 1.5]
#          [--at "2025.12.30 22:00,2025.12.31 03:00"]   # evaluate only these bars
# =============================================================================
import sys, argparse
import numpy as np
import pandas as pd

PIP = 0.0001  # EURUSD

# ----------------------------------------------------------------------------- IO
def load_csv(path, resample=None):
    # MT5 native export: Date,Time,O,H,L,C,tickvol,realvol,spread  (comma OR tab,
    # with or without a <DATE><TIME>... header row)
    raw = pd.read_csv(path, header=None, sep=None, engine="python",
                      skip_blank_lines=True)
    # drop a header row if present (first cell not a date)
    if not str(raw.iloc[0,0]).strip().startswith(("19","20")):
        raw = raw.iloc[1:].reset_index(drop=True)
    raw = raw.iloc[:, :8]
    raw.columns = ["date","time","open","high","low","close","tvol","rvol"][:raw.shape[1]]
    dt = pd.to_datetime(raw["date"].astype(str).str.strip()+" "+raw["time"].astype(str).str.strip(),
                        format="mixed")
    df = raw[["open","high","low","close"]].astype(float)
    df.index = dt
    if resample:
        rule = {"H1":"1h","H4":"4h","M15":"15min","M30":"30min","M5":"5min"}[resample]
        df = df.resample(rule).agg({"open":"first","high":"max","low":"min","close":"last"}).dropna()
    return df

# ----------------------------------------------------------------------------- indicators (exact)
def ema(s, n):              # MT5 semantics: seed on first value, recurse forward
    return s.ewm(alpha=2/(n+1), adjust=False).mean()

def atr(df, n=14):
    h,l,c = df["high"], df["low"], df["close"]
    pc = c.shift(1)
    tr = pd.concat([(h-l),(h-pc).abs(),(l-pc).abs()], axis=1).max(axis=1)
    return tr.ewm(alpha=1/n, adjust=False).mean()   # Wilder

def cci(df, n=13):
    tp = (df["high"]+df["low"]+df["close"])/3.0
    sma = tp.rolling(n).mean()
    mad = (tp - sma).abs().rolling(n).mean()
    return (tp - sma)/(0.015*mad.replace(0,np.nan))

def dpi(df):                # Blue=EMA8-EMA13, Red=EMA13(Blue), hist=Blue-Red
    blue = ema(df["close"],8) - ema(df["close"],13)
    red  = ema(blue,13)
    return blue-red

def choppiness(df, n=14):
    a = atr(df,1)                                   # 1-bar TR series (ATR n=1 = TR)
    num = a.rolling(n).sum()
    rng = df["high"].rolling(n).max() - df["low"].rolling(n).min()
    return 100*np.log10(num/rng.replace(0,np.nan))/np.log10(n)

def adx(df, n=14):
    h,l,c = df["high"],df["low"],df["close"]
    up = h.diff(); dn = -l.diff()
    plus  = np.where((up>dn)&(up>0), up, 0.0)
    minus = np.where((dn>up)&(dn>0), dn, 0.0)
    tr = pd.concat([(h-l),(h-c.shift()).abs(),(l-c.shift()).abs()],axis=1).max(axis=1)
    atr_ = tr.ewm(alpha=1/n,adjust=False).mean()
    pdi = 100*pd.Series(plus,index=df.index).ewm(alpha=1/n,adjust=False).mean()/atr_
    mdi = 100*pd.Series(minus,index=df.index).ewm(alpha=1/n,adjust=False).mean()/atr_
    dx = 100*(pdi-mdi).abs()/(pdi+mdi).replace(0,np.nan)
    return dx.ewm(alpha=1/n,adjust=False).mean()

def psar(df, step=0.02, mx=0.2):
    h,l = df["high"].values, df["low"].values
    n=len(df); ps=np.zeros(n); bull=True; af=step; ep=l[0]; sar=l[0]
    for i in range(1,n):
        sar = sar + af*(ep-sar)
        if bull:
            if l[i]<sar: bull=False; sar=ep; ep=l[i]; af=step
            else:
                if h[i]>ep: ep=h[i]; af=min(af+step,mx)
        else:
            if h[i]>sar: bull=True; sar=ep; ep=h[i]; af=step
            else:
                if l[i]<ep: ep=l[i]; af=min(af+step,mx)
        ps[i]=sar
    return pd.Series(ps,index=df.index)

# ----------------------------------------------------------------------------- phase/bias (exact, 4-EMA)
def phase_bias(e2,e3,e4):
    if e2>e3>e4: return "TM_UP", +1
    if e4>e3>e2: return "TM_DN", -1
    if e2>e4>e3: return "EM_UP", +1
    if e3>e4>e2: return "EM_DN", -1
    return "UNO", 0

# ----------------------------------------------------------------------------- build frame
def build(df):
    d = df.copy()
    d["e1"],d["e2"],d["e3"],d["e4"] = ema(d.close,5),ema(d.close,13),ema(d.close,34),ema(d.close,89)
    d["dpi"]  = dpi(d)
    d["cci"]  = cci(d,13)
    d["atr"]  = atr(d,14)
    d["adx"]  = adx(d,14)
    d["chop"] = choppiness(d,14)
    d["psar"] = psar(d)
    for k in ["e1","e2","e3","e4"]:
        d[k+"_sl"] = d[k].diff()                     # 1-bar slope
    return d

# ----------------------------------------------------------------------------- base TS=1 candidate (APPROX) + discriminators (exact)
def evaluate_bar(d, i, rr):
    r = d.iloc[i]; p = d.iloc[i-1]
    ph, bias = phase_bias(r.e2, r.e3, r.e4)
    out = dict(time=d.index[i], phase=ph, bias=bias, close=r.close)
    if bias == 0:
        out["ts1"]=False; out["block"]="B(no bias)"; return out
    lng = bias>0

    # --- base voters (exact) ---
    dpi_ok  = (r.dpi>0)==lng and (np.sign(r.dpi)==np.sign(r.cci))       # DPI + CCI reset
    psar_ok = (r.psar < r.close) if lng else (r.psar > r.close)
    body    = abs(r.close-r.open)
    cbody_ok= ((r.close>r.open)==lng) and \
              ((r.close-r.low)/max(r.high-r.low,1e-9) >= 0.75 if lng
               else (r.high-r.close)/max(r.high-r.low,1e-9) >= 0.75)   # MinCloseRatio 0.75

    # --- layer: positional align + close-beyond-fast + simplified pullback-recovery (APPROX) ---
    def layer_ok(fast,slow,fslcol,fsl,ssl,fastval):
        pos  = (fast>slow) if lng else (fast<slow)
        bc   = (r.close>fastval) if lng else (r.close<fastval)
        # pullback->recovery proxy: fast slope dipped (flat/against) in last 3 bars, now with bias
        win  = d[fslcol].iloc[i-3:i+1]
        dipped = (win.abs().min() < 0.1*abs(win).mean()) or ((win<0).any() if lng else (win>0).any())
        recov  = (fsl>0 and ssl>0) if lng else (fsl<0 and ssl<0)
        return pos and bc and dipped and recov
    L_W = layer_ok(r.e1,r.e2,"e1_sl",r.e1_sl,r.e2_sl,r.e1)
    L_M = layer_ok(r.e2,r.e3,"e2_sl",r.e2_sl,r.e3_sl,r.e2)
    L_S = layer_ok(r.e3,r.e4,"e3_sl",r.e3_sl,r.e4_sl,r.e3) and ph.startswith("TM")  # LayerS TM-only
    layer_ok_any = L_W or L_M or L_S
    active = "S" if L_S else "M" if L_M else "W" if L_W else "-"

    base_ok = dpi_ok and psar_ok and cbody_ok and layer_ok_any and ph!="UNO"
    out["ts1"]=base_ok; out["layer"]=active
    out["voters"]=f"DPI:{int(dpi_ok)} PSAR:{int(psar_ok)} CBODY:{int(cbody_ok)} L:{int(layer_ok_any)}"
    if not base_ok:
        miss=[]
        if not layer_ok_any: miss.append("L")
        if not dpi_ok: miss.append("DPI")
        if not psar_ok: miss.append("PSAR")
        if not cbody_ok: miss.append("CBODY")
        out["block"]="+".join(miss) or ph
        return out

    # ===================== ADDED-GATE DISCRIMINATORS (EXACT) =====================
    # 1. Choppiness Index (anti-range) — high = "not so nice to trade"
    out["CHOP"] = round(float(r.chop),1)
    # 2. ADX (trend strength)
    out["ADX"]  = round(float(r.adx),1)
    # 3. EMA-fan width in pips (over-extension when too wide)
    fan = (max(r.e1,r.e2,r.e3,r.e4)-min(r.e1,r.e2,r.e3,r.e4))/PIP
    out["FANpips"]=round(fan,1)
    # 4. ClimaxGuard: signal-bar range / ATR ; cumulative move(13) / ATR (in trade dir)
    out["BARxATR"] = round(float((r.high-r.low)/max(r.atr,1e-9)),2)
    mv = (r.close - d.close.iloc[i-13]) if lng else (d.close.iloc[i-13]-r.close)
    out["MOVExATR"]= round(float(mv/max(r.atr,1e-9)),2)
    # 5. ATR-extension: distance close->EMA34 in ATR units (price-vs-EMA over-extension)
    out["EXTxATR"] = round(float(abs(r.close-r.e3)/max(r.atr,1e-9)),2)
    # 6. DPI exhaustion-divergence: price new 55-extreme but DPI hist not confirming
    lb=55
    if i>=lb:
        pxext = (r.close>=d.close.iloc[i-lb:i+1].max()) if lng else (r.close<=d.close.iloc[i-lb:i+1].min())
        dpext = (r.dpi >=d.dpi.iloc[i-lb:i+1].max())   if lng else (r.dpi  <=d.dpi.iloc[i-lb:i+1].min())
        out["DPIdiv"] = bool(pxext and not dpext)
    else:
        out["DPIdiv"] = False

    # ---- which proposed gate would VETO (with suggested thresholds) ----
    vetoes=[]
    if out["CHOP"]   > 61.8: vetoes.append("CI>61.8")
    if out["ADX"]    < 23.0: vetoes.append("ADX<23")
    if out["FANpips"]> 40.0: vetoes.append("FAN>40p")          # RRM_ORG M15 fan band 25-40
    if out["BARxATR"]> 2.0 or out["MOVExATR"]>3.0: vetoes.append("CLIMAX")
    if out["EXTxATR"]> 2.5: vetoes.append("EXT>2.5")
    if out["DPIdiv"]:        vetoes.append("DPIdiv")
    out["VETO"]=",".join(vetoes) if vetoes else ""
    out["kept_after_gates"] = (out["VETO"]=="")
    return out

# ----------------------------------------------------------------------------- main
def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("csv")
    ap.add_argument("--resample",default=None)
    ap.add_argument("--rr",type=float,default=1.5)
    ap.add_argument("--at",default=None,help="comma-sep 'YYYY.MM.DD HH:MM' bars to evaluate")
    a=ap.parse_args()
    df=load_csv(a.csv,a.resample)
    d=build(df)
    print(f"# loaded {len(d)} bars  {d.index[0]} -> {d.index[-1]}  "
          f"TF={'native' if not a.resample else a.resample}")

    if a.at:
        want=[pd.to_datetime(x.strip(),format="%Y.%m.%d %H:%M") for x in a.at.split(",")]
        rows=[evaluate_bar(d,d.index.get_indexer([w],method='nearest')[0],a.rr) for w in want]
        print(pd.DataFrame(rows).to_string(index=False)); return

    # scan whole file for base candidates
    cand=[]
    for i in range(90,len(d)):
        e=evaluate_bar(d,i,a.rr)
        if e.get("ts1"): cand.append(e)
    C=pd.DataFrame(cand)
    if C.empty: print("no base candidates"); return
    print(f"\n# BASE RRM_ORG TS=1 candidates (approx): {len(C)}")
    kept=C["kept_after_gates"].sum()
    print(f"# after proposed added gates: KEPT {kept}  /  VETOED {len(C)-kept} "
          f"({100*(len(C)-kept)/len(C):.0f}% removed)\n")
    # per-gate contribution
    print("# per-gate veto counts (how many base candidates each gate removes):")
    for g in ["CI>61.8","ADX<23","FAN>40p","CLIMAX","EXT>2.5","DPIdiv"]:
        print(f"    {g:10s} {C['VETO'].str.contains(g,regex=False).sum()}")
    # feature separation: kept vs vetoed
    print("\n# discriminator means  (KEPT = clean-trend  vs  VETOED = choppy/overextended):")
    for col in ["CHOP","ADX","FANpips","BARxATR","MOVExATR","EXTxATR"]:
        k=C.loc[C.kept_after_gates,col].mean(); v=C.loc[~C.kept_after_gates,col].mean()
        print(f"    {col:9s} KEPT {k:7.2f}   VETOED {v:7.2f}")
    # show a clean example and an over-extended/choppy example
    print("\n# EXAMPLE — a KEPT (clean) candidate:")
    print(C[C.kept_after_gates].iloc[len(C[C.kept_after_gates])//2].to_dict())
    print("\n# EXAMPLE — a VETOED (choppy/overextended) candidate:")
    print(C[~C.kept_after_gates].iloc[len(C[~C.kept_after_gates])//2].to_dict())

if __name__=="__main__":
    main()
