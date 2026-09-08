# PRESET_FPM — The Five-Point Method

**Status: IMPLEMENTED.** Coded inline in `SEA_Presets.mqh` (`ApplyPreset` → `if(preset == PRESET_FPM)`)
and evaluated through the shared `EvaluateTS_Breakdown` core. No external indicator file is required.
Companion iconographic: `_SEA_FPM/FX-FPM-Trading_System_v01.png`.

FPM is a **flat, unanimous multi-confirmation** system — no EMA ribbon, no phase, no layer.
It fires only when **every enabled point agrees at bar close**, on a simple dual-SMA(10/20) bias.

---

## 1. The idea — five independent confirmations or nothing

The "Five-Point Method" asks five unrelated questions about the same bar and trades only when all
answers line up. Because the points are *independent* (a trend indicator, a momentum event, a
volatility state, a price-location gate, and a structural bias), agreement between them is
meaningfully stronger than any one alone. The vote is **unanimous** — this is a multiplicative AND,
identical in spirit to the RRM `I` factor, but with the ribbon machinery stripped out.

---

## 2. How it maps onto the TS/TE pipeline

SEA evaluates `TS = B × P × F × L × I → CG`, then executes through the TE gate chain.
FPM is a clean instantiation with phase/layer switched off:

| Factor | FPM behaviour |
|--------|---------------|
| **B** (direction) | Dual-SMA position — price above **both** SMA10 & SMA20 = +1, below both = −1 (`BIAS_2EMA`, `STRAT_2EMA_POSITION`). |
| **P** (phase) | Inert (`PhaseDetectionEnabled = false`). |
| **L** (layer) | Inert (`EnableLayerDetection = false`). The **BC** bar-close gate carries the price-location role. |
| **I** (indicators) | **The five points** — PSAR, MACD fresh cross, BB widening, plus the bar-close gate; all unanimous. |
| **F / CG** | Off by default (Policy-A gates still apply). |

**Exit** is the SIMPLE profile: swing-based SL + fixed/RR TP + optional fixed-pip trail.

---

## 3. The five points (entry)

All enabled points are evaluated at bar close (`shift = 1`) and must pass unanimously
(`VOTE_MODE_ALL`). Any single 0 → TS = 0 → no trade.

| # | Point | Passes when (LONG) | Config |
|---|-------|--------------------|--------|
| 1 | **PSAR** | dot **below** price | `Ind_Psar_Enabled`, `Vote_AllowPsarFlip=true`, `Vote_PsarFlipDelay=-1` (every bar) |
| 2 | **MACD** | **fresh** cross above the signal line, ≤ 5 bars old | `MacdVoteMode = MACD_CROSSOVER_N`, `MacdFreshBars = 5` |
| 3 | **Bollinger** | bandwidth(now) > bandwidth(prev) — bands **widening** | `BbMode = BB_WIDENING`, `P_Bb=20`, `P_BbDev=2.0` |
| 4 | **Bar-close** | candle closes **beyond fast SMA10** in bias direction | `BarClose_Mode = BC_BIAS_FAST`, `BarClose_DefaultEMA = ROLE_EMA1` |
| 5 | **Dual-SMA bias** | price above **both** SMA10 & SMA20 | `BiasMode = BIAS_2EMA`, `MaType = METHOD_SMA`, `P_Ema1=10`, `P_Ema2=20` |

SHORT is the mirror (PSAR above, MACD cross down, close below SMA10, price below both SMAs);
BB widening is symmetric and direction-agnostic.

> **Removed 6th condition (SMA convergence).** The original cheat sheet's "gap narrowing" test is
> mutually exclusive with a trending 2-SMA position bias — when the position bias fires the SMAs are
> *diverging*, so convergence always fails. `BC_BIAS_FAST` already covers "price is positioned
> relative to the SMAs", so `Ind_SmaConverge_Enabled = false`.

### Optional add-on voters (default OFF, user-toggleable)
`Inp_FPM_Use_Adx`, `Inp_FPM_Use_CandleBody`, `Inp_FPM_Use_CI`, `Inp_FPM_Ind_Mfi_Enabled`
(MFI>50 long / <50 short volume gate), `Inp_FPM_Use_Dpi`, `Inp_FPM_Use_P123`, `Inp_FPM_Use_Ross`,
`Inp_FPM_Use_Mtf`. Each adds another unanimous confirmation.

---

## 4. Exits & stops (SIMPLE profile — Zone 3C)

- **SL** = `SL_MODE_SWING`. Swing lookback is **TF-aware** (`GetFPMSwingLookback()`:
  M1 10 · M5 12 · M15 15 · M30 18 · H1 20 · H4 30). Cushion + `SL_MinPips` floor with
  `SL_WidenToMinimum = true` (widen rather than block a too-tight stop).
- **TP** = user-selected. `TP_MODE_FIXED_PIPS` uses the TF cheat-sheet midpoints
  (`GetFPMFixedTpPips()`: ≤M5 11 · M15 15 · M30 40 · H1+ 50 pips); `TP_MODE_RR` uses `Inp_FPM_RRRatio`.
- **Trail** = optional `TRAIL_FIXED_PIPS` (`Inp_FPM_TrailDistancePips`, cheat-sheet 15 pips;
  broker-min clamped), `TrailLockProfit = true`, `TrailStepPips = 5`. `TrailTrigger = TRIGGER_BREAKEVEN`.
- BE-path fields are RRM-only and explicitly zeroed under SIMPLE.

---

## 5. Locked vs flexible

**Locked:** SMA 10/20, `BIAS_2EMA` position, `VOTE_MODE_ALL`, `MACD_CROSSOVER_N`, `BB_WIDENING`,
`BC_BIAS_FAST`, phase/layer OFF, `ExitProfile = SIMPLE`, `SL_MODE_SWING`.
**Flexible:** PSAR step/max, MACD periods, TP mode & R:R, trail toggle/distance, optional add-on voters,
and all Policy-A gates (spread, session, news, risk).

---

## 6. Quick reference

```
Entry  : PSAR·side  AND  MACD·freshCross(≤5)  AND  BB·widening  AND  close>SMA10  AND  price>SMA10&SMA20
Bias   : 2-SMA position (10/20)         Phase/Layer: OFF
Vote   : unanimous (all enabled)        Eval: bar close, shift=1
SL     : swing (TF-aware) + floor       TP: TF cheat-sheet pips OR R:R
Trail  : optional 15-pip lock           Enum: PRESET_FPM
```
