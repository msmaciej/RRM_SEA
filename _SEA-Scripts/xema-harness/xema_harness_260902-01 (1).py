#!/usr/bin/env python3
# =============================================================================
# xema_harness_260902-01.py
# -----------------------------------------------------------------------------
# ONE consolidated, conformance-checked reconstruction of PRESET_XEMA for offline
# sweeps. Replaces the ad-hoc per-pair scripts (gbp_map / jpy_map / gold_map /
# param_sweep / htf_sweep / ema_swing_sweep / xema_test / sweep_psar / m5_*).
#
# Verified against repo HEAD:  b0244b7956fe4c2851e71cb956462bd7f3591409  (2026-09-02)
# Authoritative EA sources read for this reconstruction:
#   SEA_Presets.mqh      — PRESET_XEMA block (cfg mapping) + ValidateXEMA_ExitConfig
#                          + GetTFBasedCushion + GetRecommendedInitialSlCushionPips
#                          + GetInstrumentFanMultiplier
#   SEA_Inputs.mqh       — Inp_XEMA_* defaults (the NEUTRAL standard config)
#   SEA_SignalEngine.mqh — STRAT_2EMA_CROSS_EMA entry, CheckMTFFilter (dual-HTF +
#                          MTF_RequirePhase), Check_ADX (DYNAMIC_PERCENTILE),
#                          Check_BB (BB_WIDENING)
#   SEA_TradeExecutor.mqh— GetSwingLevel (fractal swing), RRM_GetStrictSL / CalcEntrySL
#                          chain, EnforceSLMinFloor, EvaluateTM SIMPLE exit path,
#                          CloseOnReverse, TryMoveToBreakEven (BE@R), TryTrailRLadder (LPR)
#
# ─────────────────────────────────────────────────────────────────────────────
# AUTHORITY / TRUST MODEL  (read this before trusting any number this prints)
# ─────────────────────────────────────────────────────────────────────────────
# This harness RECONSTRUCTS the EA in Python. It is AUTHORITATIVE ONLY where
# `--verify` PASSES against a fixture logged from the EA at the current HEAD.
#   * PASS  = the reconstruction reproduces the EA's entries AND exits (time,
#             direction, SL, exit reason) within tolerance for the fixture window
#             → results at THIS commit are trustworthy.
#   * FAIL  = the EA changed, or the harness drifted → STOP. Do not trust sweep
#             output. Print diff, reconcile, re-verify.
#   * PARTIAL (fixture built from SignalScan/DebugFlow, not a full EA trade log)
#             = entries checked, exits only partially → treat as provisional.
#
# The prior ad-hoc scripts silently diverged from the EA in at least these ways
# (all corrected here; the verify gate exists so a saved reconstruction can never
# again freeze such a bug):
#   1. baked findings into defaults (EMA 13/34, swing 55) — EA default is 20/50, swing 20
#   2. single H4-resampled HTF w/ EMA 13/34 — EA uses DUAL M15+H1, EMA 20/50, phase-required
#   3. swing SL = rolling low.min() — EA uses a FRACTAL strength-2 swing detector
#   4. reverse-cross = raw EMA-position flip — EA closes on the next QUALIFIED opposite signal
#   5. per-tick TRAIL k*R — EA uses once-per-bar BE@2R + LPR ladder (3R->2R, 4R->3R)
#   6. fixed 2p cushion / 5p min — EA uses instrument/TF-scaled cushion + SL_MinPips floor
#
# NOTE ON EXACTNESS: a few EA quantities (SL_SwingPipsCushion, RRM_BE_BufferPips)
# resolve at runtime from _Period/_Symbol and, for XEMA, are inherited rather than
# set in the preset block. The harness ships the EA's own FORMULAS for them
# (GetRecommendedInitialSlCushionPips / GetTFBasedCushion) as defaults, but the
# `--verify` gate is what certifies the exact values for a given symbol×TF. Treat
# unverified exact-price SLs as best-effort until a full-log fixture passes.
# =============================================================================

import argparse
import json
import sys
from dataclasses import dataclass, field, asdict, replace
from typing import Optional

import numpy as np
import pandas as pd

REPO_HEAD_VERIFIED = "b0244b7956fe4c2851e71cb956462bd7f3591409"
HARNESS_VERSION = "260902-01"

# ───────────────────────────────────────────────────────── pip / instrument map
# Auto-detected from the symbol string; overridable via --symbol / config.
#   FX      : 0.0001
#   JPY     : 0.01
#   Gold/XAU: 0.1
# GetInstrumentFanMultiplier() (SEA_Presets.mqh) — used by the EA's cushion/min
# formulas. Reproduced here so swing cushion & BE buffer match the EA per symbol.
def instrument_fan_multiplier(symbol: str) -> float:
    s = symbol.upper()
    if "XAU" in s or "GOLD" in s:            return 100.0
    if "XAG" in s or "SILVER" in s:          return 50.0
    if "BTC" in s or "ETH" in s or "CRYPTO" in s: return 25.0
    return 1.0  # Forex baseline


def detect_pip(symbol: str, price_sample: Optional[float] = None) -> float:
    """Pip size. Prefer explicit symbol map; fall back to a price-magnitude heuristic."""
    s = symbol.upper() if symbol else ""
    if "JPY" in s:                           return 0.01
    if "XAU" in s or "GOLD" in s:            return 0.1
    if "XAG" in s or "SILVER" in s:          return 0.01
    if s and ("USD" in s or "EUR" in s or "GBP" in s or "CHF" in s
              or "AUD" in s or "NZD" in s or "CAD" in s):
        return 0.0001
    # heuristic fallback from price magnitude
    if price_sample is not None:
        if price_sample > 500:               return 0.1      # gold-like
        if price_sample > 20:                return 0.01     # jpy-like
    return 0.0001


def symbol_from_filename(path: str) -> str:
    """MT5 export files are named e.g. EURUSD_H1_2025...csv — take the leading token."""
    base = path.replace("\\", "/").split("/")[-1]
    return base.split("_")[0] if "_" in base else ""


def tf_from_filename(path: str) -> Optional[str]:
    base = path.replace("\\", "/").split("/")[-1].upper()
    for tf in ("M1", "M5", "M15", "M30", "H1", "H4", "D1"):
        if f"_{tf}_" in base:
            return tf
    return None


# GetRecommendedInitialSlCushionPips() and GetTFBasedCushion() from SEA_Presets.mqh.
# base pips are per-TF and JPY-aware, then scaled by the instrument fan multiplier.
_TF_ORDER = ["M1", "M5", "M15", "M30", "H1", "H4", "D1"]

def recommended_sl_cushion_pips(symbol: str, tf: str) -> float:
    isJPY = "JPY" in symbol.upper()
    t = tf.upper()
    if   t in ("M1",):            base = 1.5 if isJPY else 1.0
    elif t in ("M5",):            base = 3.0 if isJPY else 2.0
    elif t in ("M15", "M30"):     base = 5.0 if isJPY else 3.0
    elif t in ("H1",):            base = 8.0 if isJPY else 5.0
    elif t in ("H4",):            base = 15.0 if isJPY else 10.0
    else:                         base = 25.0 if isJPY else 15.0
    return base * instrument_fan_multiplier(symbol)

def tf_based_cushion_pips(symbol: str, tf: str) -> float:
    isJPY = "JPY" in symbol.upper()
    t = tf.upper()
    if   t in ("M1",):            base = 2.0 if isJPY else 1.5
    elif t in ("M5",):            base = 5.0 if isJPY else 3.0
    elif t in ("M15", "M30"):     base = 8.0 if isJPY else 5.0
    elif t in ("H1",):            base = 12.0 if isJPY else 8.0
    elif t in ("H4",):            base = 15.0 if isJPY else 10.0
    else:                         base = 25.0 if isJPY else 15.0
    return base * instrument_fan_multiplier(symbol)


# ───────────────────────────────────────────────────────────────────────── IO
def load_csv(path: str, resample: Optional[str] = None) -> pd.DataFrame:
    """MT5 native export loader (comma OR tab, with/without a <DATE><TIME>.. header)."""
    raw = pd.read_csv(path, header=None, sep=None, engine="python", skip_blank_lines=True)
    first = str(raw.iloc[0, 0]).strip()
    if not first.startswith(("19", "20")):
        raw = raw.iloc[1:].reset_index(drop=True)
    ncols = raw.shape[1]
    names = ["date", "time", "open", "high", "low", "close", "tvol", "rvol", "spread"][:ncols]
    raw = raw.iloc[:, :ncols]
    raw.columns = names
    dt = pd.to_datetime(raw["date"].astype(str).str.strip() + " "
                        + raw["time"].astype(str).str.strip(), format="mixed")
    cols = ["open", "high", "low", "close"]
    df = raw[cols].astype(float)
    # carry the MT5 <SPREAD> column (in points) if present — lets --spread auto use real spread
    if "spread" in raw.columns:
        df["spread_pts"] = pd.to_numeric(raw["spread"], errors="coerce")
    df.index = dt
    if resample:
        rule = {"H1": "1h", "H4": "4h", "D1": "1D", "M15": "15min",
                "M30": "30min", "M5": "5min", "M1": "1min"}[resample]
        agg = {"open": "first", "high": "max", "low": "min", "close": "last"}
        df = df.resample(rule).agg(agg).dropna()
    return df


# ─────────────────────────────────────────────────────────── indicators (exact)
# EMA with MT5 semantics: seed on first value, recurse forward (adjust=False).
def ema(s: pd.Series, n: int) -> pd.Series:
    return s.ewm(alpha=2.0 / (n + 1.0), adjust=False).mean()

def atr_wilder(df: pd.DataFrame, n: int = 14) -> pd.Series:
    h, l, c = df["high"], df["low"], df["close"]
    pc = c.shift(1)
    tr = pd.concat([(h - l), (h - pc).abs(), (l - pc).abs()], axis=1).max(axis=1)
    return tr.ewm(alpha=1.0 / n, adjust=False).mean()

def adx(df: pd.DataFrame, n: int = 14) -> pd.Series:
    h, l, c = df["high"], df["low"], df["close"]
    up = h.diff(); dn = -l.diff()
    plus  = np.where((up > dn) & (up > 0), up, 0.0)
    minus = np.where((dn > up) & (dn > 0), dn, 0.0)
    tr = pd.concat([(h - l), (h - c.shift()).abs(), (l - c.shift()).abs()], axis=1).max(axis=1)
    atr_ = tr.ewm(alpha=1.0 / n, adjust=False).mean()
    pdi = 100 * pd.Series(plus,  index=df.index).ewm(alpha=1.0 / n, adjust=False).mean() / atr_
    mdi = 100 * pd.Series(minus, index=df.index).ewm(alpha=1.0 / n, adjust=False).mean() / atr_
    dx = 100 * (pdi - mdi).abs() / (pdi + mdi).replace(0, np.nan)
    return dx.ewm(alpha=1.0 / n, adjust=False).mean()

def choppiness(df: pd.DataFrame, n: int = 14) -> pd.Series:
    tr = atr_wilder(df, 1)  # ATR n=1 == TR
    num = tr.rolling(n).sum()
    rng = df["high"].rolling(n).max() - df["low"].rolling(n).min()
    return 100 * np.log10(num / rng.replace(0, np.nan)) / np.log10(n)

def psar(df: pd.DataFrame, step: float = 0.02, mx: float = 0.2) -> pd.Series:
    h = df["high"].values; l = df["low"].values
    n = len(df); ps = np.zeros(n)
    bull = True; af = step; ep = l[0]; sar = l[0]
    for i in range(1, n):
        sar = sar + af * (ep - sar)
        if bull:
            if l[i] < sar: bull = False; sar = ep; ep = l[i]; af = step
            else:
                if h[i] > ep: ep = h[i]; af = min(af + step, mx)
        else:
            if h[i] > sar: bull = True; sar = ep; ep = h[i]; af = step
            else:
                if l[i] < ep: ep = l[i]; af = min(af + step, mx)
        ps[i] = sar
    return pd.Series(ps, index=df.index)

def bb_widening(df: pd.DataFrame, period: int = 20, dev: float = 2.0) -> np.ndarray:
    """EA Check_BB / BB_WIDENING: bandwidth_now > bandwidth_prev.
    bandwidth = upper-lower = 2*dev*stdev(period) => reduces to stdev_now > stdev_prev."""
    std = df["close"].rolling(period).std(ddof=0).values
    bw = 2.0 * dev * std
    out = np.zeros(len(df), dtype=bool)
    out[1:] = bw[1:] > bw[:-1]
    return out

def dpi_hist(df: pd.DataFrame) -> pd.Series:
    """DPI histogram: Blue=EMA8-EMA13, Red=EMA13(Blue), hist=Blue-Red (voter, off by default)."""
    blue = ema(df["close"], 8) - ema(df["close"], 13)
    red = ema(blue, 13)
    return blue - red

def cci(df: pd.DataFrame, n: int = 13) -> pd.Series:
    tp = (df["high"] + df["low"] + df["close"]) / 3.0
    sma = tp.rolling(n).mean()
    mad = (tp - sma).abs().rolling(n).mean()
    return (tp - sma) / (0.015 * mad.replace(0, np.nan))


# =============================================================================
# CONFIG — every indicator + on/off + internals parameterised.
# DEFAULTS ARE THE NEUTRAL EA STANDARD CONFIG (Inp_XEMA_* @ HEAD b0244b7).
# No per-pair "findings" are baked in — that is the sweep chats' job.
# =============================================================================
@dataclass
class XemaConfig:
    # -- entry EMA cross (Inp_XEMA_EmaFast/Slow) --
    ema_fast: int = 20
    ema_slow: int = 50

    # -- HTF / MTF (Inp_XEMA_MTF_*) --
    htf_enabled: bool = True
    htf_use_second: bool = True          # true => require BOTH TF1 and TF2
    htf_tf1: str = "M15"
    htf_tf2: str = "H1"
    htf_ema_fast: int = 20
    htf_ema_slow: int = 50
    htf_require_phase: bool = True        # MTF_RequirePhase (XEMA forces true)
    # Optional real HTF native CSVs, keyed by TF label ("M15","H1",...). When a TF's
    # file is supplied it is loaded directly (matching what the live EA reads via
    # iBarShift on that TF); otherwise the chart file is resampled UP to that TF.
    # Required whenever an HTF is not strictly above the chart TF (e.g. XEMA's default
    # M15 HTF on an H1 chart: MT5 has real M15 data, a lone H1 CSV does not).
    htf_source_files: dict = field(default_factory=dict)

    # -- ADX gate (Inp_XEMA_Use_Adx / ADX_*) — ADX_MODE_DYNAMIC_PERCENTILE --
    use_adx: bool = True
    adx_period: int = 14
    adx_percentile: float = 50.0
    adx_lookback: int = 100

    # -- BB widening voter (Inp_XEMA_Use_Bb / BB_*) — off by default --
    use_bb: bool = False
    bb_period: int = 20
    bb_dev: float = 2.0

    # -- CI choppiness voter (Inp_XEMA_Use_CI / CI_*) — off by default --
    use_ci: bool = False
    ci_period: int = 14
    ci_ranging_thresh: float = 61.8      # block when CI >= thresh (ranging)

    # -- PSAR voter (Inp_XEMA_Use_Psar / Psar_*) — off by default --
    use_psar: bool = False
    psar_step: float = 0.02
    psar_max: float = 0.2

    # -- CandleBody voter (Inp_XEMA_Use_CandleBody / CandleBody_*) — off by default --
    use_candlebody: bool = False
    cb_require_dir: bool = True
    cb_avg_period: int = 14
    cb_max_mult: float = 3.0
    cb_min_close_ratio: float = 0.75

    # -- DPI voter (Inp_XEMA_Use_Dpi) — off by default --
    use_dpi: bool = False

    # -- SL (Inp_XEMA_SLMode / SwingLookback / SL_Atr*) --
    sl_mode: str = "SWING"               # SWING | ATR
    swing_lookback: int = 20
    swing_strength: int = 2              # GetSwingLevel fractal strength (fixed in EA)
    sl_atr_period: int = 14
    sl_atr_mult: float = 1.0
    sl_cushion_pips: Optional[float] = None   # None => GetRecommendedInitialSlCushionPips(sym,tf)
    sl_min_pips: Optional[float] = None       # None => Inp_Global_SL_MinPips (3.0), broker floor n/a offline
    sl_widen_to_minimum: bool = True
    sl_fixed_pips: float = 20.0

    # -- exit (ValidateXEMA_ExitConfig forces reverse-cross; TP NONE) --
    exit_mode: str = "XEMA_NATIVE"       # XEMA_NATIVE = revcross + BE + LPR (the shipped default)
                                         # also: REVCROSS_ONLY | FIX<r> | TRAIL<k>  (for sweeps only)
    close_on_reverse: bool = True
    be_mode: str = "R_MULTIPLE"          # R_MULTIPLE | OFF
    be_r_multiple: float = 2.0
    be_buffer_pips: Optional[float] = None    # None => GetTFBasedCushion(sym,tf)
    trail_mode: str = "NONE"             # NONE (XEMA default) | (sweep overrides handled via exit_mode)
    lpr_enabled: bool = True             # XEMA forces cfg.LPR_LadderEnabled = true
    lpr_ladder: tuple = ((3.0, 2.0), (4.0, 3.0))   # (triggerR, lockR) from Inp_Global_LPR_*

    # -- cost / accounting --
    spread_pips: Optional[float] = None  # None => use MT5 <SPREAD> column per bar if available, else 0
    # -- walk / de-cluster --
    independent: bool = False            # False = sequential one-position (EA-like); True = independent walks
    min_bars_between: int = 0            # de-cluster gap for independent mode

    def resolved_sl_cushion(self, symbol: str, tf: str) -> float:
        return self.sl_cushion_pips if self.sl_cushion_pips is not None \
            else recommended_sl_cushion_pips(symbol, tf)

    def resolved_sl_min(self) -> float:
        return self.sl_min_pips if self.sl_min_pips is not None else 3.0  # Inp_Global_SL_MinPips

    def resolved_be_buffer(self, symbol: str, tf: str) -> float:
        return self.be_buffer_pips if self.be_buffer_pips is not None \
            else tf_based_cushion_pips(symbol, tf)

    @staticmethod
    def from_dict(d: dict) -> "XemaConfig":
        base = XemaConfig()
        for k, v in (d or {}).items():
            if not hasattr(base, k):
                raise KeyError(f"Unknown config key: {k}")
            if k == "lpr_ladder" and v is not None:
                v = tuple(tuple(x) for x in v)
            setattr(base, k, v)
        return base

    def to_dict(self) -> dict:
        return asdict(self)


# =============================================================================
# PRECOMPUTE — period-INDEPENDENT indicators computed once (M5 files 350-450k rows).
# EMAs (entry + HTF) depend on period and are recomputed per config in build_frame.
# =============================================================================
@dataclass
class Precomputed:
    df: pd.DataFrame
    symbol: str
    tf: str
    pip: float
    # period-independent series/arrays
    adx: np.ndarray
    chop: np.ndarray
    psar_cache: dict            # (step,max) -> np.ndarray  (psar depends on step/max, not EMA period)
    dpi: np.ndarray
    cci: np.ndarray
    # raw OHLC arrays for the walk
    o: np.ndarray; h: np.ndarray; l: np.ndarray; c: np.ndarray
    idx: pd.DatetimeIndex
    spread_pts: Optional[np.ndarray]


def precompute(df: pd.DataFrame, symbol: str, tf: str, cfg: XemaConfig) -> Precomputed:
    pip = detect_pip(symbol, float(df["close"].iloc[len(df) // 2]))
    a = adx(df, cfg.adx_period).values
    ch = choppiness(df, cfg.ci_period).values
    psar_cache = {(cfg.psar_step, cfg.psar_max): psar(df, cfg.psar_step, cfg.psar_max).values}
    dpi_v = dpi_hist(df).values
    cci_v = cci(df, 13).values
    spr = df["spread_pts"].values if "spread_pts" in df.columns else None
    return Precomputed(
        df=df, symbol=symbol, tf=tf, pip=pip,
        adx=a, chop=ch, psar_cache=psar_cache, dpi=dpi_v, cci=cci_v,
        o=df["open"].values, h=df["high"].values, l=df["low"].values, c=df["close"].values,
        idx=df.index, spread_pts=spr,
    )


# =============================================================================
# HTF sign with MTF_RequirePhase  (SEA_SignalEngine.mqh GetMTFBias)
# Returns +1 / -1 / 0 per chart bar, as-of mapped from the HTF frame.
#   phase rule: if position bull (fast>slow) but BOTH htf EMAs falling -> 0 (unclear)
#               if position bear (fast<slow) but BOTH htf EMAs rising  -> 0 (unclear)
# =============================================================================
def htf_bias_series(chart_index: pd.DatetimeIndex, hdf: pd.DataFrame,
                    fast: int, slow: int, require_phase: bool) -> np.ndarray:
    ef = ema(hdf["close"], fast)
    es = ema(hdf["close"], slow)
    ef_prev = ef.shift(1); es_prev = es.shift(1)
    fast_above = (ef > es)
    fast_rising = (ef > ef_prev)
    slow_rising = (es > es_prev)
    bias = pd.Series(0, index=hdf.index, dtype=float)
    bias[fast_above] = 1.0
    bias[~fast_above] = -1.0
    if require_phase:
        # position bull but both falling -> unclear
        unclear_bull = fast_above & (~fast_rising) & (~slow_rising)
        # position bear but both rising -> unclear
        unclear_bear = (~fast_above) & fast_rising & slow_rising
        bias[unclear_bull | unclear_bear] = 0.0
    # invalidate warmup (NaN EMAs) -> 0 (fail-closed)
    bias[ef.isna() | es.isna() | ef_prev.isna() | es_prev.isna()] = np.nan
    # as-of map onto chart bars (last closed HTF bar)
    mapped = bias.reindex(bias.index.union(chart_index)).ffill().reindex(chart_index)
    return mapped.values


def adx_dynamic_threshold(adx_arr: np.ndarray, percentile: float, lookback: int) -> np.ndarray:
    """Rolling interpolated percentile of ADX over the last `lookback` VALID bars
    (EA CalculateADXPercentile: linear interpolation, needs >=10 valid values).
    Threshold at bar i is computed from bars strictly BEFORE i (closed-bar reading),
    matching the EA which reads the cached threshold from prior history.
    Vectorized: drop NaNs, rolling-quantile over valid values, then map back."""
    n = len(adx_arr)
    thr = np.full(n, np.nan)
    s = pd.Series(adx_arr)
    valid_mask = s.notna().values
    valid_idx = np.nonzero(valid_mask)[0]
    if len(valid_idx) < 10:
        return thr
    vals = s.values[valid_idx]
    q = percentile / 100.0
    # rolling quantile over the last `lookback` valid values, using values strictly
    # before the current position -> shift by 1. min_periods=10 mirrors the EA gate.
    vser = pd.Series(vals)
    roll = vser.shift(1).rolling(window=lookback, min_periods=10).quantile(q,
                                                                           interpolation="linear")
    # place each valid position's threshold at its original bar index
    thr[valid_idx] = roll.values
    # forward-fill threshold across NaN-ADX bars so gate has a value if ADX momentarily NaN
    thr = pd.Series(thr).ffill().values
    return thr


# =============================================================================
# Swing SL — FRACTAL detector faithful to TradeExecutor.GetSwingLevel().
#   scan i in [strength+1, lookback): a swing low is low[i] strictly below
#   low[i±1..±strength]; nearest-first wins. Fallback: iLowest/iHighest over lookback.
#   All indices are "bars back" from the signal-evaluation bar (shift semantics).
# Returns the raw swing PRICE (before cushion/floor).
# =============================================================================
def swing_level(h: np.ndarray, l: np.ndarray, eval_i: int, direction: int,
                lookback: int, strength: int) -> float:
    # bars back: shift k -> array index (eval_i - k). eval bar is the last CLOSED bar.
    for k in range(strength + 1, lookback):
        c = eval_i - k
        if c - strength < 0 or c + strength > eval_i:
            continue
        if direction > 0:
            piv = l[c]
            if piv <= 0:
                continue
            ok = True
            for j in range(1, strength + 1):
                if l[c - j] <= piv or l[c + j] <= piv:
                    ok = False; break
            if ok:
                return piv
        else:
            piv = h[c]
            if piv <= 0:
                continue
            ok = True
            for j in range(1, strength + 1):
                if h[c - j] >= piv or h[c + j] >= piv:
                    ok = False; break
            if ok:
                return piv
    # fallback: extremum over the lookback window ending at eval bar
    lo_i = max(0, eval_i - lookback + 1)
    if direction > 0:
        return float(np.min(l[lo_i:eval_i + 1]))
    return float(np.max(h[lo_i:eval_i + 1]))


def build_initial_sl(pc: Precomputed, cfg: XemaConfig, eval_i: int, entry: float,
                     direction: int) -> Optional[float]:
    """Full EA SL chain: swing -> validity -> cushion -> min-floor(widen/block)."""
    pip = pc.pip
    if cfg.sl_mode.upper() == "ATR":
        atr_here = atr_wilder(pc.df, cfg.sl_atr_period).values[eval_i]
        dist = cfg.sl_atr_mult * atr_here
        sl = entry - dist if direction > 0 else entry + dist
    else:
        sw = swing_level(pc.h, pc.l, eval_i, direction, cfg.swing_lookback, cfg.swing_strength)
        valid = (sw < entry) if direction > 0 else (sw > entry)
        if not valid:
            # EA tries PSAR then fixed-pips. Offline default: fixed-pips fallback.
            dist = cfg.sl_fixed_pips * pip
            sl = entry - dist if direction > 0 else entry + dist
        else:
            cushion = cfg.resolved_sl_cushion(pc.symbol, pc.tf) * pip
            sl = (sw - cushion) if direction > 0 else (sw + cushion)
    # EnforceSLMinFloor (offline: broker stops-level unknown -> use user min only)
    min_dist = cfg.resolved_sl_min() * pip
    actual = abs(entry - sl)
    if actual < min_dist:
        if cfg.sl_widen_to_minimum:
            sl = entry - min_dist if direction > 0 else entry + min_dist
        else:
            return None  # trade blocked
    return sl


# =============================================================================
# build_frame — recompute period-dependent series (entry EMAs + HTF signs) for a config.
# Returns everything the signal generator + walk need.
# =============================================================================
def build_frame(pc: Precomputed, cfg: XemaConfig):
    df = pc.df
    ef = ema(df["close"], cfg.ema_fast).values
    es = ema(df["close"], cfg.ema_slow).values

    htf_signs = []
    if cfg.htf_enabled:
        for use, tflabel in ((True, cfg.htf_tf1), (cfg.htf_use_second, cfg.htf_tf2)):
            if not use:
                continue
            src = (cfg.htf_source_files or {}).get(tflabel) or (cfg.htf_source_files or {}).get(tflabel.upper())
            if src:
                hdf = load_csv(src)   # real HTF native file (what the live EA reads on that TF)
            elif _tf_rank(tflabel) > _tf_rank(pc.tf):
                hdf = _resample_for_htf(df, tflabel)   # resample chart UP to a genuine HTF
            elif _tf_rank(tflabel) == _tf_rank(pc.tf):
                hdf = df   # HTF == chart TF: the EA reads same-TF bars => use the chart frame
            else:
                # HTF strictly BELOW chart TF and no native file supplied. NOTE: XEMA does
                # NOT auto-promote HTF (unlike RRM_ORG's GetSafeMTF_*); the live EA reads
                # real sub-chart data via iBarShift, which a lone higher-TF CSV lacks.
                raise ValueError(
                    f"HTF {tflabel} is below chart TF {pc.tf} and no htf_source_files"
                    f"['{tflabel}'] was provided. Supply the real {tflabel} native CSV "
                    f"(the EA reads actual {tflabel} bars here), or run the native "
                    f"{tflabel}-or-lower file so {tflabel} is a genuine HTF.")
            htf_signs.append(htf_bias_series(df.index, hdf, cfg.htf_ema_fast, cfg.htf_ema_slow,
                                             cfg.htf_require_phase))

    # psar for the configured step/max (cache period-independent series)
    key = (cfg.psar_step, cfg.psar_max)
    if key not in pc.psar_cache:
        pc.psar_cache[key] = psar(df, cfg.psar_step, cfg.psar_max).values
    psar_arr = pc.psar_cache[key]

    # bb widening for configured period/dev
    bb = bb_widening(df, cfg.bb_period, cfg.bb_dev) if cfg.use_bb else None

    # adx dynamic threshold for configured percentile/lookback
    adx_thr = adx_dynamic_threshold(pc.adx, cfg.adx_percentile, cfg.adx_lookback) if cfg.use_adx else None

    return dict(ef=ef, es=es, htf_signs=htf_signs, psar=psar_arr, bb=bb, adx_thr=adx_thr)


_TF_RANK = {"M1": 1, "M5": 5, "M15": 15, "M30": 30, "H1": 60, "H4": 240, "D1": 1440}

def _tf_rank(tf: str) -> int:
    return _TF_RANK.get(str(tf).upper(), 0)


def _resample_for_htf(df: pd.DataFrame, tf: str) -> pd.DataFrame:
    rule = {"M5": "5min", "M15": "15min", "M30": "30min",
            "H1": "1h", "H4": "4h", "D1": "1D"}[tf.upper()]
    return df.resample(rule).agg({"open": "first", "high": "max",
                                  "low": "min", "close": "last"}).dropna()


# =============================================================================
# SIGNALS — reproduces STEP2 entry (STRAT_2EMA_CROSS_EMA) + gates in EA order:
#   cross -> HTF(all-agree) -> ADX -> [PSAR] -> [BB] -> [CI] -> [CandleBody] -> [DPI]
# Evaluation bar i is a CLOSED bar; prev bar is i-1 (EA v_shift / v_shift+1).
# Returns list of (i, direction) where direction in {+1,-1}.
# =============================================================================
def generate_signals(pc: Precomputed, cfg: XemaConfig, fr: dict) -> list:
    ef = fr["ef"]; es = fr["es"]; htf = fr["htf_signs"]
    adx_arr = pc.adx; adx_thr = fr["adx_thr"]
    psar_arr = fr["psar"]; bb = fr["bb"]; chop = pc.chop
    close = pc.c; open_ = pc.o; high = pc.h; low = pc.l
    dpi = pc.dpi; cci_v = pc.cci
    warm = max(cfg.ema_slow + 2, cfg.swing_lookback + 2, 120)
    out = []
    for i in range(warm, len(ef) - 1):
        if np.isnan(ef[i]) or np.isnan(es[i]) or np.isnan(ef[i-1]) or np.isnan(es[i-1]):
            continue
        bull = ef[i-1] <= es[i-1] and ef[i] > es[i]
        bear = ef[i-1] >= es[i-1] and ef[i] < es[i]
        if not (bull or bear):
            continue
        direction = 1 if bull else -1
        lng = direction > 0

        # HTF: ALL configured HTFs must agree with direction (dual = AND)
        ok = True
        for hs in htf:
            v = hs[i]
            if np.isnan(v) or v == 0.0 or (v > 0) != lng:
                ok = False; break
        if not ok:
            continue

        # ADX: adx[i] >= dynamic percentile threshold
        if cfg.use_adx:
            t = adx_thr[i]
            if np.isnan(adx_arr[i]):
                continue
            if not np.isnan(t) and adx_arr[i] < t:
                continue

        # PSAR voter
        if cfg.use_psar:
            p = psar_arr[i]
            if (p < close[i]) != lng:
                continue

        # BB widening voter
        if cfg.use_bb and not bool(bb[i]):
            continue

        # CI (choppiness) voter: block when ranging (CI >= thresh)
        if cfg.use_ci:
            if np.isnan(chop[i]) or chop[i] >= cfg.ci_ranging_thresh:
                continue

        # CandleBody voter
        if cfg.use_candlebody:
            rng = max(high[i] - low[i], 1e-12)
            body = abs(close[i] - open_[i])
            dir_ok = ((close[i] > open_[i]) == lng) if cfg.cb_require_dir else True
            close_ratio = ((close[i] - low[i]) / rng) if lng else ((high[i] - close[i]) / rng)
            if not (dir_ok and close_ratio >= cfg.cb_min_close_ratio):
                continue

        # DPI voter: histogram sign agrees with direction
        if cfg.use_dpi:
            if np.isnan(dpi[i]) or (dpi[i] > 0) != lng:
                continue

        out.append((i, direction))
    return out


# =============================================================================
# TRADE — a single reconstructed trade record (for output + conformance).
# =============================================================================
@dataclass
class Trade:
    entry_i: int
    entry_time: pd.Timestamp
    direction: int            # +1 / -1
    entry: float
    sl0: float                # initial SL price
    R: float                  # risk distance (price)
    exit_i: int
    exit_time: pd.Timestamp
    exit_price: float
    exit_reason: str          # SL | REVCROSS | BE | LPR | FIX | TRAIL | EOD
    r_multiple: float         # gross R (before spread)
    net_r: float              # after 2*spread/R cost


# =============================================================================
# WALK — EA-faithful XEMA_NATIVE management for one open position, OR a sweep exit.
# opp_signal_bars: set of bar indices where a QUALIFIED opposite signal fires
#   (used for the reverse-cross close — the EA's real CloseOnReverse trigger).
# Once-per-bar: BE@R then LPR ladder (SL only tightens). Intrabar: SL hit checked
# against bar low/high; conservatively SL-before-target within a bar.
# =============================================================================
def walk_native(pc: Precomputed, cfg: XemaConfig, entry_i: int, direction: int,
                entry: float, sl0: float, R: float, next_opp_bar: int) -> tuple:
    h = pc.h; l = pc.l; c = pc.c
    n = len(c)
    lng = direction > 0
    sl = sl0
    pip = pc.pip
    be_buffer = cfg.resolved_be_buffer(pc.symbol, pc.tf) * pip
    be_done = False
    j = entry_i + 1
    while j < n:
        # 1) intrabar hard SL check first (conservative)
        if lng and l[j] <= sl:
            return j, (sl - entry) / R, "SL" if sl <= sl0 + 1e-12 else _lock_reason(sl, entry, sl0, R, lng)
        if (not lng) and h[j] >= sl:
            return j, (entry - sl) / R, "SL" if sl >= sl0 - 1e-12 else _lock_reason(sl, entry, sl0, R, lng)

        # 2) reverse-cross close: the next qualified opposite signal fires on this bar
        if cfg.close_on_reverse and next_opp_bar >= 0 and j >= next_opp_bar:
            px = c[j]
            r = (px - entry) / R if lng else (entry - px) / R
            return j, r, "REVCROSS"

        # 3) once-per-bar SL management on bar close (BE then LPR)
        px = c[j]
        cur_r = (px - entry) / R if lng else (entry - px) / R
        # BE @ R
        if (not be_done) and cfg.be_mode.upper() == "R_MULTIPLE" and cur_r >= cfg.be_r_multiple:
            be_sl = entry + be_buffer if lng else entry - be_buffer
            if (lng and be_sl > sl) or ((not lng) and be_sl < sl):
                sl = be_sl
            be_done = True
        # LPR ladder (highest triggered lock)
        if cfg.lpr_enabled and cfg.lpr_ladder:
            lock_r = 0.0
            for trig, lock in cfg.lpr_ladder:
                if cur_r >= trig:
                    lock_r = lock
            if lock_r > 0.0:
                new_sl = entry + lock_r * R if lng else entry - lock_r * R
                if (lng and new_sl > sl) or ((not lng) and new_sl < sl):
                    sl = new_sl
        j += 1

    # ran off the end — mark-to-close at last bar
    px = c[-1]
    r = (px - entry) / R if lng else (entry - px) / R
    return n - 1, r, "EOD"


def _lock_reason(sl, entry, sl0, R, lng) -> str:
    """Classify a SL-hit that occurred at a moved stop (BE/LPR) vs the initial stop."""
    locked_r = (sl - entry) / R if lng else (entry - sl) / R
    if abs(locked_r) < 1e-9:
        return "BE"
    return "LPR" if locked_r > 0 else "SL"


def walk_sweep(pc: Precomputed, cfg: XemaConfig, ef: np.ndarray, es: np.ndarray,
               entry_i: int, direction: int, entry: float, sl0: float, R: float,
               mode: str) -> tuple:
    """Sweep-only exits for A/B comparison (NOT the shipped default):
       FIX<r>  : fixed r:1 TP with initial SL.
       TRAIL<k>: peak-anchored k*R trail.
       REVCROSS_ONLY: close on raw EMA-position flip (the old ad-hoc approximation)."""
    h = pc.h; l = pc.l; c = pc.c
    n = len(c); lng = direction > 0
    if mode.startswith("FIX"):
        rr = float(mode[3:]); tp = entry + rr * R if lng else entry - rr * R; sl = sl0
        for j in range(entry_i + 1, n):
            if lng:
                if l[j] <= sl: return j, -1.0, "SL"
                if h[j] >= tp: return j, rr, "FIX"
            else:
                if h[j] >= sl: return j, -1.0, "SL"
                if l[j] <= tp: return j, rr, "FIX"
        px = c[-1]; return n - 1, ((px - entry) / R if lng else (entry - px) / R), "EOD"
    if mode.startswith("TRAIL"):
        k = float(mode[5:]); sl = sl0; peak = entry
        for j in range(entry_i + 1, n):
            if lng:
                if l[j] <= sl: return j, (sl - entry) / R, ("SL" if sl <= sl0 + 1e-12 else "TRAIL")
                if h[j] > peak: peak = h[j]; sl = max(sl, peak - k * R)
            else:
                if h[j] >= sl: return j, (entry - sl) / R, ("SL" if sl >= sl0 - 1e-12 else "TRAIL")
                if l[j] < peak: peak = l[j]; sl = min(sl, peak + k * R)
        px = c[-1]; return n - 1, ((px - entry) / R if lng else (entry - px) / R), "EOD"
    # REVCROSS_ONLY (raw EMA-position flip — legacy approximation)
    sl = sl0
    for j in range(entry_i + 1, n):
        if lng:
            if l[j] <= sl: return j, (sl - entry) / R, "SL"
            if ef[j] < es[j]: return j, (c[j] - entry) / R, "REVCROSS"
        else:
            if h[j] >= sl: return j, (entry - sl) / R, "SL"
            if ef[j] > es[j]: return j, (entry - c[j]) / R, "REVCROSS"
    px = c[-1]; return n - 1, ((px - entry) / R if lng else (entry - px) / R), "EOD"


# =============================================================================
# RUN — turn signals into trades (sequential one-position OR independent walks).
# Sequential: after an exit, the next entry must be at/after the exit bar (+gap),
#             and reverse-cross uses the next opposite qualified signal.
# =============================================================================
def run_trades(pc: Precomputed, cfg: XemaConfig, fr: dict, signals: list) -> list:
    ef = fr["ef"]; es = fr["es"]
    o = pc.o; idx = pc.idx
    pip = pc.pip
    # Precompute, once, the sorted bar indices of LONG and SHORT signals so the
    # reverse-cross lookup for each trade is a slice, not an O(signals) rebuild.
    long_bars = np.array([j for (j, d) in signals if d > 0], dtype="int64")
    short_bars = np.array([j for (j, d) in signals if d < 0], dtype="int64")
    trades: list = []
    free = 0
    last_entry = -10 ** 9
    for (i, direction) in signals:
        if not cfg.independent and i < free:
            continue
        if cfg.independent and (i - last_entry) < cfg.min_bars_between:
            continue
        entry = o[i + 1]
        sl0 = build_initial_sl(pc, cfg, i, entry, direction)
        if sl0 is None:
            continue
        R = abs(entry - sl0)
        if R <= 0:
            continue
        # next qualified opposite signal strictly after entry (for reverse-cross close)
        opp_src = short_bars if direction > 0 else long_bars
        cut = int(np.searchsorted(opp_src, i, side="right"))
        next_opp_bar = int(opp_src[cut]) if cut < len(opp_src) else -1

        em = cfg.exit_mode.upper()
        if em in ("XEMA_NATIVE",):
            xi, rR, reason = walk_native(pc, cfg, i, direction, entry, sl0, R, next_opp_bar)
        elif em.startswith("FIX") or em.startswith("TRAIL") or em == "REVCROSS_ONLY":
            xi, rR, reason = walk_sweep(pc, cfg, ef, es, i, direction, entry, sl0, R, em)
        else:
            raise ValueError(f"Unknown exit_mode: {cfg.exit_mode}")

        # cost: 2*spread/R (round trip). spread from config, else per-bar MT5 <SPREAD>, else 0.
        spr_pips = _spread_pips_for(pc, cfg, i)
        net = rR - 2.0 * (spr_pips * pip) / R
        trades.append(Trade(
            entry_i=i, entry_time=idx[i], direction=direction, entry=entry,
            sl0=sl0, R=R, exit_i=xi, exit_time=idx[xi], exit_price=pc.c[xi],
            exit_reason=reason, r_multiple=rR, net_r=net,
        ))
        free = xi + 1
        last_entry = i
    return trades


def _spread_pips_for(pc: Precomputed, cfg: XemaConfig, i: int) -> float:
    if cfg.spread_pips is not None:
        return cfg.spread_pips
    if pc.spread_pts is not None and not np.isnan(pc.spread_pts[i]):
        # MT5 <SPREAD> is in points; pip = 10 points for 5-digit FX, 1 point for gold/jpy 3-digit.
        # points->pips: points * _Point / pip. _Point ~= pip/10 for FX 5-digit, = pip for others.
        # Use a robust conversion: assume points are in _Point units where 10 points = 1 pip on
        # 5-digit FX and 1 point = 1 pip elsewhere. Detect via pip size.
        pts = float(pc.spread_pts[i])
        if pc.pip == 0.0001:      # 5-digit FX
            return pts / 10.0
        if pc.pip == 0.01:        # 3-digit JPY
            return pts / 10.0
        return pts                 # gold/other: treat as pip units
    return 0.0


# =============================================================================
# REPORTING — per-year, split-half, session windows (for M5), per-knob tables.
# =============================================================================
def summarize(trades: list) -> dict:
    if not trades:
        return dict(n=0, net=0.0, gross=0.0, win=0.0, meanR=0.0)
    net = np.array([t.net_r for t in trades])
    gross = np.array([t.r_multiple for t in trades])
    return dict(n=len(trades), net=float(net.sum()), gross=float(gross.sum()),
                win=float(100 * np.mean(gross > 0)), meanR=float(np.mean(gross)))


def per_year(trades: list) -> dict:
    by: dict = {}
    for t in trades:
        y = t.entry_time.year
        by.setdefault(y, []).append(t.net_r)
    return {y: float(np.sum(v)) for y, v in sorted(by.items())}


def split_half(trades: list) -> tuple:
    if not trades:
        return (0.0, 0.0)
    mid = trades[len(trades) // 2].entry_time
    a = [t.net_r for t in trades if t.entry_time < mid]
    b = [t.net_r for t in trades if t.entry_time >= mid]
    return (float(np.sum(a)), float(np.sum(b)))


def by_session(trades: list, windows: dict) -> dict:
    out = {}
    for name, hours in windows.items():
        sel = [t.net_r for t in trades if (hours is None or t.entry_time.hour in hours)]
        out[name] = (len(sel), float(np.sum(sel)) if sel else 0.0)
    return out


SESSION_WINDOWS = {
    "ALL": None,
    "LDN+NY(8-20)": set(range(8, 21)),
    "NY(12-21)": set(range(12, 22)),
}


def fmt_year(by: dict) -> str:
    return "  ".join(f"{y}:{by[y]:+.0f}" for y in sorted(by)) + f"  | tot {sum(by.values()):+.0f}"


# =============================================================================
# CONFORMANCE (--verify) — the safety gate.
# Fixture CSV columns (EA-logged; a header row is required):
#   entry_time,direction,sl,exit_time,exit_reason
#     entry_time : 'YYYY.MM.DD HH:MM' (data clock, bar time of the signal/entry bar)
#     direction  : BUY/SELL or +1/-1
#     sl         : initial SL price (optional; checked if present)
#     exit_time  : 'YYYY.MM.DD HH:MM' (optional; checked if present)
#     exit_reason: SL/REVCROSS/BE/LPR/... (optional; checked if present)
# A fixture may be a full trade log (entries+exits => full conformance) or a
# SignalScan/DebugFlow inspector dump of a few bars (entries only => PARTIAL).
# =============================================================================
@dataclass
class Tolerance:
    time_bars: int = 1          # entry/exit bar-time tolerance (in bars)
    sl_pips: float = 1.0        # SL price tolerance in pips
    require_exit: bool = True   # if fixture has no exit cols -> PARTIAL


def _parse_dir(v) -> int:
    s = str(v).strip().upper()
    if s in ("BUY", "LONG", "+1", "1"):   return 1
    if s in ("SELL", "SHORT", "-1"):      return -1
    try:
        return 1 if float(s) > 0 else -1
    except ValueError:
        raise ValueError(f"bad direction: {v}")


def fixture_provenance(path: str) -> str:
    """Read a leading '# kind: <EA_LOG|SIGNALSCAN|REGRESSION>' comment if present.
    EA_LOG    = signals exported from the MT5 tester (authoritative -> can reach PASS).
    SIGNALSCAN= SignalScan/DebugFlow inspector dump (entries mostly -> PARTIAL at best).
    REGRESSION= harness-derived self-consistency (guards DRIFT only -> never certifies
                harness-vs-EA fidelity; reported as REGRESSION-OK, not PASS)."""
    try:
        with open(path) as fh:
            for line in fh:
                s = line.strip()
                if not s:
                    continue
                if s.startswith("#") and "kind:" in s.lower():
                    return s.lower().split("kind:", 1)[1].strip().upper()
                break  # first non-blank line isn't a kind header
    except OSError:
        pass
    return "EA_LOG"  # default assumption; operator should label explicitly


def load_fixture(path: str) -> pd.DataFrame:
    fx = pd.read_csv(path, comment="#")
    fx.columns = [c.strip().lower() for c in fx.columns]
    if "entry_time" not in fx.columns or "direction" not in fx.columns:
        raise ValueError("fixture needs at least entry_time,direction columns")
    fx["entry_time"] = pd.to_datetime(fx["entry_time"].astype(str).str.strip(), format="mixed")
    fx["dir"] = fx["direction"].apply(_parse_dir)
    if "exit_time" in fx.columns:
        fx["exit_time"] = pd.to_datetime(fx["exit_time"].astype(str).str.strip(),
                                         format="mixed", errors="coerce")
    return fx


def verify(pc: Precomputed, cfg: XemaConfig, trades: list, fixture: pd.DataFrame,
           tol: Tolerance, kind: str = "EA_LOG") -> tuple:
    """Return (status, report_lines).
       status: PASS / PARTIAL / FAIL for EA_LOG or SIGNALSCAN fixtures;
               REGRESSION-OK / REGRESSION-FAIL for REGRESSION fixtures (harness-derived:
               these guard against DRIFT across harness edits, they do NOT certify
               harness-vs-EA fidelity — only an EA_LOG fixture can do that)."""
    idx = pc.idx
    # bar spacing in nanoseconds (robust to pandas datetime unit: us vs ns).
    # Use Timedelta so the unit is explicit and matches Timestamp.value (ns).
    def _ns(ts) -> int:
        return int(pd.Timestamp(ts).value)  # always nanoseconds
    if len(idx) > 2:
        deltas_ns = np.diff(np.array([_ns(t) for t in idx[:min(len(idx), 5000)]], dtype="int64"))
        bar_ns = int(np.median(deltas_ns)) if len(deltas_ns) else 3600 * 10**9
    else:
        bar_ns = 3600 * 10**9
    tol_ns = tol.time_bars * bar_ns

    has_exit = "exit_time" in fixture.columns and fixture["exit_time"].notna().any()
    has_reason = "exit_reason" in fixture.columns
    has_sl = "sl" in fixture.columns and pd.to_numeric(fixture["sl"], errors="coerce").notna().any()

    lines = []
    mism = 0
    matched = 0
    # index trades by entry time for nearest-match
    tr_times = np.array([_ns(t.entry_time) for t in trades], dtype="int64")

    for _, row in fixture.iterrows():
        et = row["entry_time"]
        want_dir = int(row["dir"])
        # nearest reconstructed trade by entry time
        if len(trades) == 0:
            lines.append(f"  MISS entry {et}  dir {want_dir:+d}: no reconstructed trades at all")
            mism += 1; continue
        k = int(np.argmin(np.abs(tr_times - _ns(et))))
        tr = trades[k]
        dt_ns = abs(_ns(tr.entry_time) - _ns(et))
        ok = True; why = []
        if dt_ns > tol_ns:
            ok = False; why.append(f"entry Δt={dt_ns/bar_ns:.1f}bars>{tol.time_bars}")
        if tr.direction != want_dir:
            ok = False; why.append(f"dir {tr.direction:+d}!={want_dir:+d}")
        if has_sl and pd.notna(row.get("sl")):
            try:
                want_sl = float(row["sl"])
                dpips = abs(tr.sl0 - want_sl) / pc.pip
                if dpips > tol.sl_pips:
                    ok = False; why.append(f"SL Δ={dpips:.1f}p>{tol.sl_pips}")
            except (ValueError, TypeError):
                pass
        if has_exit and pd.notna(row.get("exit_time")):
            dexit = abs(_ns(tr.exit_time) - _ns(row["exit_time"]))
            if dexit > tol_ns:
                ok = False; why.append(f"exit Δt={dexit/bar_ns:.1f}bars>{tol.time_bars}")
        if has_reason and isinstance(row.get("exit_reason"), str) and row["exit_reason"].strip():
            wr = row["exit_reason"].strip().upper()
            if wr != tr.exit_reason.upper():
                # SL-at-BE and BE are commonly logged interchangeably; treat as soft
                soft = {("SL", "BE"), ("BE", "SL"), ("LPR", "TRAIL"), ("TRAIL", "LPR")}
                if (wr, tr.exit_reason.upper()) not in soft:
                    ok = False; why.append(f"reason {tr.exit_reason}!={wr}")
        if ok:
            matched += 1
        else:
            mism += 1
            lines.append(f"  MISM entry {et} dir {want_dir:+d}: " + "; ".join(why)
                         + f"  [recon: {tr.entry_time} {tr.direction:+d} SL={tr.sl0:.5f} "
                           f"exit={tr.exit_time}/{tr.exit_reason}]")

    ok_all = (mism == 0)
    if kind == "REGRESSION":
        status = "REGRESSION-OK" if ok_all else "REGRESSION-FAIL"
    else:
        status = "PASS" if ok_all else "FAIL"
        # SIGNALSCAN fixtures, or any fixture lacking full exit+reason columns, cap at PARTIAL
        if status == "PASS" and (kind == "SIGNALSCAN" or not has_exit or not has_reason) and tol.require_exit:
            status = "PARTIAL"
    header = [
        f"# CONFORMANCE {status}  (matched {matched}/{len(fixture)}, mismatched {mism})",
        f"#   fixture kind          : {kind}",
        f"#   HEAD verified-against : {REPO_HEAD_VERIFIED}",
        f"#   fixture rows          : {len(fixture)}   exits_present={has_exit} reasons_present={has_reason} sl_present={has_sl}",
        f"#   tolerance             : {tol.time_bars} bar(s) time, {tol.sl_pips} pip SL",
    ]
    if status == "PARTIAL":
        header.append("#   PARTIAL: SignalScan/entry-only fixture — entries verified, exits "
                      "provisional. Add a full EA trade-log (kind: EA_LOG) fixture to reach PASS.")
    if kind == "REGRESSION":
        header.append("#   REGRESSION: harness-derived fixture. Guards against harness DRIFT across "
                      "edits only. Does NOT certify harness-vs-EA fidelity — that needs an EA_LOG fixture.")
    return status, header + lines


# =============================================================================
# HIGH-LEVEL ENTRYPOINTS
# =============================================================================
def prepare(csv: str, cfg: XemaConfig, symbol: Optional[str] = None,
            tf: Optional[str] = None, resample: Optional[str] = None) -> Precomputed:
    df = load_csv(csv, resample=resample)
    sym = symbol or symbol_from_filename(csv) or "EURUSD"
    t = tf or (resample or tf_from_filename(csv) or "H1")
    return precompute(df, sym, t, cfg)


def analyze(csv: str, cfg: XemaConfig, symbol=None, tf=None, resample=None) -> dict:
    pc = prepare(csv, cfg, symbol, tf, resample)
    fr = build_frame(pc, cfg)
    sigs = generate_signals(pc, cfg, fr)
    trades = run_trades(pc, cfg, fr, sigs)
    return dict(pc=pc, cfg=cfg, fr=fr, signals=sigs, trades=trades,
                summary=summarize(trades), per_year=per_year(trades),
                split_half=split_half(trades), by_session=by_session(trades, SESSION_WINDOWS))


def settings_card(cfg: XemaConfig, pc: Precomputed) -> str:
    c = cfg
    htf = f"{c.htf_tf1}+{c.htf_tf2}" if c.htf_use_second else c.htf_tf1
    voters = [n for n, on in [("BB", c.use_bb), ("CI", c.use_ci), ("PSAR", c.use_psar),
                              ("CandleBody", c.use_candlebody), ("DPI", c.use_dpi)] if on]
    lines = [
        "┌─ XEMA settings card ─────────────────────────────────────",
        f"│ symbol/TF   : {pc.symbol} {pc.tf}   pip={pc.pip}",
        f"│ EMA cross   : {c.ema_fast}/{c.ema_slow}",
        f"│ HTF         : {'ON '+htf+' EMA'+str(c.htf_ema_fast)+'/'+str(c.htf_ema_slow)+(' phase' if c.htf_require_phase else '') if c.htf_enabled else 'OFF'}",
        f"│ ADX         : {'ON p'+str(c.adx_percentile)+' lb'+str(c.adx_lookback) if c.use_adx else 'OFF'}",
        f"│ voters ON   : {', '.join(voters) if voters else '(none — neutral)'}",
        f"│ SL          : {c.sl_mode} lookback={c.swing_lookback} cushion={c.resolved_sl_cushion(pc.symbol,pc.tf):.1f}p min={c.resolved_sl_min():.1f}p",
        f"│ exit        : {c.exit_mode}  BE={c.be_mode}@{c.be_r_multiple}R buf={c.resolved_be_buffer(pc.symbol,pc.tf):.1f}p  LPR={'on '+str(c.lpr_ladder) if c.lpr_enabled else 'off'}  trail={c.trail_mode}",
        f"│ cost        : spread={'per-bar MT5' if c.spread_pips is None else str(c.spread_pips)+'p'}  walk={'independent' if c.independent else 'sequential'}",
        "└──────────────────────────────────────────────────────────",
    ]
    return "\n".join(lines)


# ---- per-knob sweep table (the single-cell sweep) -----------------------------
def knob_table(csv: str, base: XemaConfig, symbol=None, tf=None, resample=None):
    """Emit the standard per-knob table for one pair×TF×span at the neutral base config."""
    variants = [
        ("standard (neutral)",      {}),
        ("EMA 8/21",                dict(ema_fast=8, ema_slow=21)),
        ("EMA 13/34",               dict(ema_fast=13, ema_slow=34)),
        ("EMA 21/55",               dict(ema_fast=21, ema_slow=55)),
        ("no ADX",                  dict(use_adx=False)),
        ("single HTF (TF1 only)",   dict(htf_use_second=False)),
        ("no HTF",                  dict(htf_enabled=False)),
        ("+PSAR",                   dict(use_psar=True)),
        ("+BB",                     dict(use_bb=True)),
        ("+CI(61.8)",               dict(use_ci=True)),
        ("swing 12",                dict(swing_lookback=12)),
        ("swing 55",                dict(swing_lookback=55)),
        ("exit REVCROSS_ONLY",      dict(exit_mode="REVCROSS_ONLY")),
        ("exit FIX2.0",             dict(exit_mode="FIX2.0")),
        ("exit TRAIL0.5",           dict(exit_mode="TRAIL0.5")),
        ("exit TRAIL1.0",           dict(exit_mode="TRAIL1.0")),
    ]
    pc = prepare(csv, base, symbol, tf, resample)  # precompute once
    print(settings_card(base, pc))
    print(f"\n#### per-knob sweep — {pc.symbol} {pc.tf}  {csv.split('/')[-1]} ####")
    print(f"{'variant':22s}{'netR':>8}{'n':>6}{'win%':>7}   per-year")
    for label, ov in variants:
        cfg = replace(base, **ov)
        fr = build_frame(pc, cfg)
        sigs = generate_signals(pc, cfg, fr)
        trades = run_trades(pc, cfg, fr, sigs)
        s = summarize(trades)
        print(f"{label:22s}{s['net']:>+8.0f}{s['n']:>6d}{s['win']:>7.0f}   {fmt_year(per_year(trades))}")


# =============================================================================
# CLI
# =============================================================================
def main(argv=None):
    ap = argparse.ArgumentParser(
        description="Consolidated conformance-checked XEMA harness. "
                    "Verified against HEAD " + REPO_HEAD_VERIFIED)
    ap.add_argument("csv", nargs="?", help="MT5 price CSV")
    ap.add_argument("--symbol", default=None, help="override symbol (else inferred from filename)")
    ap.add_argument("--tf", default=None, help="override chart TF label (else from filename)")
    ap.add_argument("--resample", default=None, help="resample native file to this TF (M5/M15/H1/H4/D1)")
    ap.add_argument("--config", default=None, help="JSON config file OR inline JSON dict of overrides")
    ap.add_argument("--htf", action="append", default=None, metavar="TF=PATH",
                    help="supply a real HTF native CSV, e.g. --htf M15=Files/EURUSD_M15_...csv "
                         "(repeatable). Needed when an HTF is not above the chart TF.")
    ap.add_argument("--spread", type=float, default=None, help="fixed spread in pips (else per-bar MT5 spread)")
    ap.add_argument("--independent", action="store_true", help="independent walks instead of sequential")
    ap.add_argument("--sweep", action="store_true", help="emit the standard per-knob table + settings card")
    ap.add_argument("--sessions", action="store_true", help="also print session-window breakdown (M5)")
    ap.add_argument("--verify", default=None, metavar="FIXTURE",
                    help="CONFORMANCE MODE: check reconstruction against an EA-logged fixture CSV. "
                         "Exit 0=PASS, 2=PARTIAL, 1=FAIL.")
    ap.add_argument("--tol-bars", type=int, default=1, help="verify time tolerance in bars (default 1)")
    ap.add_argument("--tol-sl", type=float, default=1.0, help="verify SL tolerance in pips (default 1.0)")
    ap.add_argument("--json", action="store_true", help="emit machine-readable JSON summary")
    a = ap.parse_args(argv)

    if not a.csv:
        ap.error("a price CSV path is required")

    # build config
    cfg = XemaConfig()
    if a.config:
        try:
            d = json.loads(a.config)
        except json.JSONDecodeError:
            with open(a.config) as fh:
                d = json.load(fh)
        cfg = XemaConfig.from_dict(d)
    if a.spread is not None:
        cfg.spread_pips = a.spread
    if a.independent:
        cfg.independent = True
    if a.htf:
        for item in a.htf:
            if "=" not in item:
                ap.error(f"--htf expects TF=PATH, got: {item}")
            tf_label, path = item.split("=", 1)
            cfg.htf_source_files[tf_label.strip().upper()] = path.strip()

    # ---- CONFORMANCE MODE ----
    if a.verify:
        pc = prepare(a.csv, cfg, a.symbol, a.tf, a.resample)
        fr = build_frame(pc, cfg)
        sigs = generate_signals(pc, cfg, fr)
        trades = run_trades(pc, cfg, fr, sigs)
        fx = load_fixture(a.verify)
        kind = fixture_provenance(a.verify)
        tol = Tolerance(time_bars=a.tol_bars, sl_pips=a.tol_sl)
        status, report = verify(pc, cfg, trades, fx, tol, kind=kind)
        print(settings_card(cfg, pc))
        print("\n".join(report))
        code = {"PASS": 0, "PARTIAL": 2, "FAIL": 1,
                "REGRESSION-OK": 0, "REGRESSION-FAIL": 1}[status]
        sys.exit(code)

    # ---- SWEEP TABLE ----
    if a.sweep:
        knob_table(a.csv, cfg, a.symbol, a.tf, a.resample)
        return

    # ---- single-config analysis ----
    res = analyze(a.csv, cfg, a.symbol, a.tf, a.resample)
    pc = res["pc"]
    if a.json:
        out = dict(head=REPO_HEAD_VERIFIED, version=HARNESS_VERSION,
                   symbol=pc.symbol, tf=pc.tf, config=cfg.to_dict(),
                   summary=res["summary"], per_year=res["per_year"],
                   split_half=res["split_half"])
        print(json.dumps(out, indent=2, default=str))
        return
    print(settings_card(cfg, pc))
    s = res["summary"]
    print(f"\n#### {pc.symbol} {pc.tf}  {a.csv.split('/')[-1]} ####")
    print(f"  netR {s['net']:+.0f}  n {s['n']}  win {s['win']:.0f}%  meanR {s['meanR']:+.3f}")
    print(f"  per-year : {fmt_year(res['per_year'])}")
    sh = res["split_half"]
    print(f"  split-half : first {sh[0]:+.0f}  second {sh[1]:+.0f}")
    if a.sessions:
        print("  sessions :")
        for name, (n, net) in res["by_session"].items():
            print(f"    {name:14s} n{n:<5d} netR {net:+.0f}")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, FileNotFoundError) as e:
        print(f"error: {e}", file=sys.stderr)
        sys.exit(3)
