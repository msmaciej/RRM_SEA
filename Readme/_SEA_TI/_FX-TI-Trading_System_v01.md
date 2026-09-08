# PRESET_TOPINVESTOR — Dr Świerk's TopInvestor / OXO Methodology

**Status: IMPLEMENTED.** Coded in `SEA_Presets.mqh` (`if(preset == PRESET_TOPINVESTOR)`), evaluated
through the shared `EvaluateTS_Breakdown` core. This file accompanies the iconographic
`_SEA_TOPINVESTOR/FX-TOPINVESTOR-Trading_System_v01.png`; the full source-material analysis lives in
`Readme/README_SEA_PRESET_TOPINVESTOR_MANUAL.md`.

The OXO indicator is a closed-source MT4 reversal-point detector and cannot be replicated, so SEA
replaces it with its **multi-indicator confluence voting** — one preset covering all three named systems.

---

## 1. The idea — buy the correction inside a strong trend

TopInvestor trades **strong trends only**, entering where a **correction exhausts** near a key moving
average or level, confirmed by confluence. The EMA ribbon is the institutional set
`9 / 50 / 89 / 200`, and the "secret" is a higher-timeframe filter **two TFs above** the chart.

---

## 2. How it maps onto the TS/TE pipeline

```
TS = Phase(4EMA) × Layer × BC × BD × Indicators(profile) × Filters   → CG
```

| Factor | TI behaviour |
|--------|--------------|
| **B/P** | 4-EMA phase (`BIAS_4EMA`, `BiasFast=EMA3(89)`, `BiasSlow=EMA4(200)`). UNORDERED blocked; EMERGING via `Inp_TI_PhaseAllowEM`. |
| **L** | Layer pullback→recovery (System 1) — the EMA-bounce engine. `BarClose_Mode = BC_LAYER_AWARE`. |
| **I** | Profile-scaled unanimous voter set (5 / 8 / 11) + HTF (MTF) voter. |
| **F/CG** | EMA-fan overextension filter (instrument-scaled); climax veto available. |

Evaluated on the closed bar (`Vote_EvalShift = 1`). **Exit** = RRM engine (see §5).

---

## 3. The three named systems (one preset)

They share one foundation — strong trend + pullback exhaustion + confirmation — differing only in the
confirmation source, which is why a single preset suffices:

1. **EMA Bounce** — price pulls back to EMA50/200 in a strong trend and is rejected/bounces. This is
   the layer pullback→recovery machine anchored on the 50/200 ribbon.
2. **Key Level** — signal at a well-respected horizontal S/R level (double/triple top-bottom), with a
   Fibonacci retracement depth check (Full profile).
3. **Exhaustion ("Samobój")** — impulse then a clearly weakening correction; DPI momentum + MACD
   divergence; the signal candle must close in the top/bottom **75%** of its range. Extreme selectivity.

---

## 4. The three profiles (confluence depth)

Set via `Inp_TI_Profile`. Voting is unanimous (`VOTE_MODE_ALL`) — more voters = stricter, fewer trades,
higher quality. Profiles map onto the OXO K-score confluence idea (K-3 minimum playable, K-4 good, K-5+ excellent):

| Profile | Voters | Base + additions | ~K |
|---------|:------:|------------------|:--:|
| **Conservative** | 5 | PSAR + ADX(dynamic-percentile) + CandleBody + MTF + Bar-close | K-3 |
| **Moderate** | 8 | + MACD(histogram, slope-required) + CCI(zero-line) + BB-widening | K-4/5 |
| **Full** | 11 | + DPI + SMA-convergence + Fibonacci retracement; CandleBody body ≥ 75% | K-6 |

**Confluence K-score** (documentation model): each tool present at the signal earns 1 point,
**EMA200 earns 2** — EMA50, Fib 0.38/0.5, S/R level, extreme zone, breaker, OXO/divergence, round
number, etc.

---

## 5. Key locked geometry

- **Ribbon:** EMA `9 / 50 / 89 / 200` (`Inp_TI_Ema1..4`). EMA9 = trailing-exit reference; EMA50 =
  primary bounce; EMA200 = major trend anchor.
- **HTF confirmation ("2 TFs higher"):** one MTF voter auto-computed two steps above the chart TF
  (`GetAutoHTF_TF2()`: M15→H4, H1→D1), EMA **50/200**, `MTF_RequirePhase = true`. An unordered HTF blocks.
- **Signal-candle quality:** Full profile requires body ≥ 75% of range (`CandleBody_MinCloseRatio`);
  over-long/over-extended bars are rejected by the CandleBody voter.
- **Bar-close:** layer-aware (L1→EMA1, L2→EMA2, L3→EMA3).

---

## 6. Exits — RRM engine (`EXIT_PROFILE_RRM`)

- **SL:** swing (instrument-scaled lookback via `GetInstrumentFanMultiplier()`) or ATR
  (`SL_MODE_ATR`); cushion + `SL_MinPips` floor, auto-widen.
- **TP:** R:R (`TP_MODE_RR`, primary) with instrument-scaled fixed-pip fallback.
- **BE:** break-even at N×R (`Inp_TI_BE_RMultiple`), TF-adaptive buffer.
- **Trail:** EMA(EMA1=9) exit, PSAR fallback; `TrailLockProfit = true`; optional start-after-BE.
- **Drawdown protection:** optional max-consecutive-losses / max-trades-per-day / daily-DD caps.

---

## 7. Locked vs flexible

**Locked:** 4-EMA phase/layer architecture, `BC_LAYER_AWARE`, HTF "2-TFs-higher" geometry, voter-mode
choices per profile, `EXIT_PROFILE_RRM`, `shift = 1`.
**Flexible:** profile (Conservative/Moderate/Full), EMA periods, indicator periods, EM-phase toggles,
SL/TP/BE/trail modes, drawdown protection, and Policy-A gates.

---

## 8. Quick reference

```
Ribbon : EMA 9/50/89/200           HTF : EMA 50/200, auto 2 TFs higher
Systems: 1 bounce · 2 key level · 3 exhaustion (one preset)
Profile: Conservative 5 / Moderate 8 / Full 11  (unanimous, K-3..K-6)
Confirm: layer-aware BC + BD + body≥75% (Full)  Eval: shift=1
Exits  : RRM engine (swing/ATR SL, RR TP, BE N×R, EMA9/PSAR trail)
Enum   : PRESET_TOPINVESTOR
```
