# The Sea Trading System — candidate preset design

**Status: NOT YET IMPLEMENTED.** There is no Sea-Trading preset in the current enum
(`FPM, MA, RRM_ORG, TOPINVESTOR, XEMA, TURTLE, TREND, RH_REBELLION`). This document is a
**design-stage** artifact — the same staging `_RH_REBELLION` had (design doc + iconographic +
implementation notes) before it became `PRESET_RH_REBELLION`. Source material lives in
`_SEA_TRADING/`: `sea_trading.pdf` (Russ Horn manual), `The_Sea_Trading_System.jpg` (annotated chart),
`sea_trading_a.tpl` / `sea_trading_b.tpl` (MT4 chart templates). Iconographic:
`_SEA_TRADING/FX-SEA-Trading_System_v01.png`.

> **Name clash, worth stating up front.** "SEA" in this repo means *SimpleEA*. "The **Sea** Trading
> System" is an unrelated Russ Horn method that happens to share the syllable. If it is implemented,
> a non-colliding enum such as `PRESET_SEA_STS` (Sea Trading System) is recommended to avoid confusion
> with the `SEA_*` engine files.

---

## A. Canonical system (from the manual)

A flat, all-timeframe momentum-confirmation method: a signal fires when the momentum tools cross their
**middle level together** — MACD through **0**, RSI through **50**, and price/EMA through the **middle
Bollinger band**. Those aligned midline crossings are the "sea level" it is named for.

### Components (exact parameters — confirmed from the .tpl templates)
| Indicator | Settings | Reference level |
|-----------|----------|-----------------|
| Bollinger Bands | period **20**, deviation **3**, apply Close | middle band = 20-SMA |
| Moving Average | period **3**, **EMA**, apply Close | vs middle band |
| MACD | fast **6** / slow **17** / MACD-SMA **1**, apply Close | 0 line |
| RSI | period **14**, apply Close | 50 line |

- Timeframe: **all**. Pairs: **majors** (EUR/USD, GBP/USD).
- The **"Middle Bollinger Band" is a 20-period SMA** (the BB basis). Template `sea_trading_b.tpl` makes
  this explicit — it drops the full Bollinger object and draws a plain **MA(20)** in its place, alongside
  the MA(3). So the core trigger reduces to **EMA(3) crossing SMA(20)**, with the bands used only for
  SL/TP placement.

### Long entry rules (verbatim)
1. The 3-period EMA must cross **above** the Middle Bollinger Band.
2. The MACD must cross **above** the 0 level.
3. The 14-period RSI must cross **above** the 50 level.
4. When all conditions are met, place a **buy** order.
5. Stop Loss a few pips **below** the nearest swing low **or** the Lower Bollinger Band — whichever is closer.
6. Take Profit at the **Upper** Bollinger Band, or a fixed TF target.

### Short entry rules (mirror)
1. 3-EMA crosses **below** the Middle Bollinger Band.
2. MACD falls **below** the 0 level.
3. RSI moves **below** the 50 level.
4. All met → place a **sell** order.
5. Stop Loss a few pips **above** the nearest swing high **or** the Upper Bollinger Band — whichever closer.
6. Take Profit at the **Lower** Bollinger Band, or a fixed TF target.

### Fixed take-profit ladder (per manual)
| TF | Pips | TF | Pips |
|----|------|----|------|
| M1 | 3–5 | H1 | 40–60 |
| M5 | 5–10 | H4 | 80–100 |
| M15 | 15–20 | D1 | 150–200 |
| M30 | 25–30 | | |

### Worked examples (manual)
- **Long — GBP/JPY H4:** RSI > 50 first, then MACD > 0, then EMA(3) crosses above the middle band.
  Entry after the setup-candle close @ **126.283**; SL @ **125.483** (−80 pips, below swing low);
  TP @ **127.283** (+100 pips), hit on the next candle.
- **Short — EUR/USD H1:** RSI < 50 and EMA(3) below middle band ~simultaneously, then MACD < 0.
  Entry **1.30512**; SL **1.30662** (+15 pips, above swing high); TP **1.30112** (−40 pips), hit 4h later.

---

## B. How it would map onto the SEA TS/TE pipeline

`TS = B × P × F × L × I → CG`, then TE. The Sea Trading System is a **flat** system (no ribbon
phase/layer), so it instantiates like FPM:

| Factor | Sea Trading wiring |
|--------|--------------------|
| **B** (direction) | EMA(3) vs 20-SMA (middle band): `BIAS_2EMA`, fast = EMA3, slow = SMA20, position/cross. **Mixed EMA/SMA pair** — see §C. |
| **P / L** | OFF (`PhaseDetectionEnabled=false`, `EnableLayerDetection=false`). |
| **I** (voters, unanimous) | **MACD(6,17,1) zero-line** + **RSI(14) 50-line** — both must agree in the bias direction. |
| **F / CG** | Off by default; Policy-A gates (spread/session/news/risk) stay operator-controlled. |
| **Exit** | SL = nearest of {swing, Bollinger band}; TP = opposite band **or** TF-fixed pips from the ladder. |

Reuses existing engine knobs: `MacdVoteMode = MACD_ZERO_LINE`, `RsiMode = RSI_TREND_ABOVE_50`
(already used by other presets), Bollinger via `BbMode`/`P_Bb=20`/`P_BbDev=3`, and the SIMPLE exit
profile. **No new indicator file is required.**

---

## C. Open items before it can be coded (honest gaps)

1. **Mixed EMA/SMA bias pair.** `BIAS_2EMA` currently assumes one `MaType` for both slots. Sea Trading
   wants **EMA(3)** vs **SMA(20)**. Either add a per-slot MA-method, or approximate (both EMA, or both
   SMA) and validate the drift — the FPM lesson (period-sensitive EMA/SMA divergence) applies.
2. **"Take profit at the opposite band."** There is no `TP_MODE_OPPOSITE_BAND` today; the TF-fixed
   ladder maps cleanly to a `GetSTSFixedTpPips()` helper, but the band-target TP needs new code.
3. **"Nearest of swing / band" SL.** Needs a min() between the swing-based SL and the band level —
   a small addition to the SL chain.
4. **MACD(6,17,1) semantics.** SMA-signal = 1 means the signal line ≈ the MACD main line, so
   "MACD crosses 0" is a pure zero-line test — `MACD_ZERO_LINE` is the correct vote mode (not
   `MACD_CROSSOVER_N`).

### Manual-vs-template discrepancy to resolve
The manual specifies a **3-period EMA** (setup step selects "Exponential"), but `sea_trading_a.tpl`
saved the Moving Average with `method=0` (**SMA**). The manual is authoritative; flag this so the
preset uses **EMA(3)** and the template is corrected, or the discrepancy is a deliberate choice to
record.

---

## D. Quick reference

```
Entry (long) : EMA3 > 20-SMA(mid band)  AND  MACD(6,17,1) > 0  AND  RSI(14) > 50  → BUY
Entry (short): mirror                                                              → SELL
Bias : EMA3 vs SMA20 (2-MA)      Phase/Layer: OFF      Vote: unanimous (MACD-zero + RSI-50)
SL   : nearest of swing / Bollinger band     TP: opposite band OR TF-fixed pips (M1 3-5 … D1 150-200)
Status: candidate — proposed enum PRESET_SEA_STS (not yet implemented)
```
