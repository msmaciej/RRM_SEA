# PRESET_TOPINVESTOR — Implementation Manual

## SimpleEA Integration of Dr Świerk's TopInvestor / OXO Methodology

**Version:** 1.0  
**Date:** May 2026  
**Source:** RRM-topinvestor/ folder (3 PDFs, 243 pages total)  
**Target:** SimpleEA v1.04+ (`SEA_Config.mqh`, `SEA_Presets.mqh`, `SEA_SignalEngine.mqh`, `SEA_TradeExecutor.mqh`)

---

## 1. Executive Summary

The TopInvestor "MasterPack" by Dr Dariusz Świerk (ForexInstitute.PL) describes a discretionary trading methodology centered on the OXO indicator — a proprietary, compiled MT4 reversal-point detector (.ex4). The system emphasizes trading strong trends, entering at correction endpoints near key moving averages and confluence zones.

This manual translates that methodology into a fully automated `PRESET_TOPINVESTOR` for SimpleEA. Since OXO is closed-source and cannot be replicated, we replace it with SimpleEA's multi-indicator voting pipeline — which actually exceeds OXO in sophistication by checking 8–11 independent conditions simultaneously.

**One unified preset covers all three named systems.** No separate presets are needed.

---

## 2. Source Material Analysis

### 2.1 Files in RRM-topinvestor/

| File | Type | Content |
|------|------|---------|
| `MasterPack-PODRECZNIK SKANER WSKAZNIK OXO I SYSTEMY 01.pdf` | PDF, 72 pages | Part I–V: OXO indicator, 3 named systems, scanner, exits |
| `MasterPack-PODRECZNIK SKANER WSKAZNIK OXO I SYSTEMY 02.pdf` | PDF, 81 pages | Part VI: Zones, breakers, confluence K-score, advanced examples |
| `MasterPack-PODRECZNIK - DODATKOWE PRZYKLADY.pdf` | PDF, 90 pages | Part VII: Additional examples, "best-looking" setups |
| `OXO-Indicator.ex4` | Compiled MT4 indicator | Reversal-point detector (proprietary, no source) |
| `OXO-Scanner.ex4` | Compiled MT4 indicator | Multi-pair/TF scanner dashboard |
| `OXO.tpl` | MT4 template | Chart with EMA 50 (dashed) + EMA 200 (solid) + OXO |
| `ScanOXO.tpl` | MT4 template | Scanner layout |

### 2.2 OXO Indicator Properties (from PDFs)

The OXO indicator is a black box. From the documentation we know:

- **Does not repaint** — once a signal appears on a closed candle, it stays permanently.
- **Does not show direction** — it marks probable reversal points (both tops and bottoms).
- **Best in strong trends** during high-liquidity sessions.
- **Entry rule:** Enter on the open of the next candle after the signal arrow appears.
- **Signal candle quality:** The signal candle should close above 75% of its range (shows strength).
- **Disqualification:** Signal candle too long (overextension) → use half-candle pending entry instead.

### 2.3 The Three Named Systems

**System 1 — EMA Bounce with OXO:** Price pulls back to EMA 50 or EMA 200 in a strong trend. OXO signal appears at or near the moving average. Enter on next candle open. SL below the MA or below second swing high/low. Works best after Golden Cross (EMA 50 × EMA 200). The author emphasizes retest-and-bounce — price pierces then returns to the MA and gets rejected.

**System 2 — Signal at Key Level:** OXO signal appears at a well-respected horizontal support/resistance level (double/triple top or bottom, prior swing highs/lows). Must be in a strong trend. The level should have been respected multiple times from both sides.

**System 3 — "Samobój" (Standalone OXO):** The author explicitly discourages this but documents strict conditions: strong impulse followed by clearly weakening correction, signal candle must close above 75% of its body, ideally with divergence on an oscillator, and near an MA or level. Requires extreme selectivity.

**All three share the same foundation:** Strong trend (IKI/MDR) + pullback exhaustion + confirmation. The only difference is the confirmation source. This is why one preset suffices.

### 2.4 PDF 02 Advanced Concepts

**Extreme Zones:** Drawn on the last candle before a strong move. Types include extreme candle body, candle with long wick, and opposite-color candle before impulse. Strongest when combined with EMA 200/50.

**Breakers (Type 1 + 2):** Type 1 is the zone at the last correction end that broke prior highs (stronger). Type 2 is the zone that started a correction (weaker). Frequently marks correction endpoints in strong trends.

**Confluence K-Score:** Each tool/level present at the signal earns 1 point (EMA 200 earns 2). K-3 is minimum playable, K-4 is good, K-5+ is excellent.

Eligible elements for K-score: EMA 50 (1pt), EMA 200 (2pts), Fibonacci 0.38/0.5 retracement, S/R level, extreme zone, breaker zone, flag/pennant structure, ABC correction, OXO signal, divergence on oscillator, round number level (e.g. 200.00), doji/spinning top, Wyckoff structure, volume signals, harmonic patterns, envelopes.

---

## 3. Key Abbreviations

| Abbreviation | Meaning | Source |
|---|---|---|
| **IKI** | Impulse – Correction – Impulse | TopInvestor PDFs |
| **MDR** | Multi-Day Runner (extended multi-day/week trend) | TopInvestor PDFs |
| **TM** | Trending Market — EMAs in perfect order | SimpleEA Phase detection |
| **EM** | Emerging Market — EMA4 sandwiched between EMA2/EMA3 | SimpleEA Phase detection |
| **UNO** | Unordered — no clear EMA arrangement, no trades | SimpleEA Phase detection |
| **RC** | Risk Control — hardcoded safeguards in SimpleEA | SimpleEA architecture |
| **CM** | Capital Management / position sizing | SimpleEA architecture |
| **TS** | Trade Setup — signal evaluated on closed candle (shift=1) | SimpleEA signal pipeline |
| **TE** | Trade Entry — execution check on next candle open (shift=0) | SimpleEA execution pipeline |
| **BC** | Bar Close — candle close beyond the relevant EMA in bias direction | SimpleEA Layer system |
| **BD** | Bar Direction — candle closed in bias direction | SimpleEA Layer system |
| **L1/L2/L3** | Layer Weak/Medium/Strong (pullback zones between EMA pairs) | SimpleEA Layer system |
| **K-score** | Confluence count — number of tools agreeing at one price zone | TopInvestor PDFs |

---

## 4. Why One Preset, Not Three

The author's own "modern system" from PDF 02 (the confluence K-score) already unifies everything. He counts tools present at a signal — EMA, Fibonacci, breaker, level, divergence — and the more that agree, the better.

This is exactly what SimpleEA's `VOTE_MODE_ALL` does. The Layer system naturally routes:

- **System 1 fires** when a Layer pullback lands on an EMA and the voters agree.
- **System 2 fires** when it lands near a swing level (with Fibonacci voter checking pullback depth).
- **System 3 fires** when DPI momentum + MACD divergence detect exhaustion even without a level.

Same pipeline, different conditions triggering naturally. The indicator toggles serve as the "aggressiveness dial" — Conservative (5 voters) through Full (11 voters) — matching K-3 through K-6 confluence.

---

## 5. Indicator-by-Indicator Mapping

### 5.1 Already Built-In (just enable)

| TopInvestor Element | SimpleEA Equivalent | Preset Setting |
|---|---|---|
| Strong trend (EMA stack) | `BIAS_4EMA` + Phase TM/EM | `BiasMode=BIAS_4EMA`, `PhaseAllowEM=false` |
| Pullback to EMA + recovery | Layer L1/L2/L3 + pullback detection | `LayerPullbackEnabled=true` |
| Higher TF trend ("secret is 2 TF higher") | `Ind_MTF_Enabled` | `MTF_TF1=H4`, `MTF_RequirePhase=true` |
| Bar close beyond EMA | `BC` (BarClose per layer) | Automatic in `STRAT_4EMA_LAYER` |
| Bar direction in bias | `BD` (BarDirection per layer) | Automatic in `STRAT_4EMA_LAYER` |
| Session/liquidity window | `StartHour` / `EndHour` | `StartHour=7, EndHour=17` |
| News avoidance | News Filter (Zone 2) | Enable in Zone 2 |
| PSAR direction confirmation | `Ind_Psar_Enabled` | `Ind_Psar_Enabled=true` |
| MACD divergence | `MacdRequireDivergence` | `Ind_Macd_Enabled=true` |
| CCI momentum | `Ind_Cci_Enabled` | `CciMode=CCI_TREND_ZERO` |
| ADX trend strength | `ADX_MODE_DYNAMIC_PERCENTILE` | `Ind_Adx_Enabled=true` |
| Spike candle rejection | `Ind_CandleBody_Enabled` | `CandleBody_MaxMult=2.5` |
| Choppiness filter | `Ind_CI_Enabled` | `CI_RangingThreshold=61.8` |
| DPI momentum exhaustion | `Ind_Dpi_Enabled` | `DPI_BlockOnDeceleration=true` |
| BB volatility expansion | `Ind_Bb_Enabled` + `BB_WIDENING` | `BbMode=BB_WIDENING` |
| SMA convergence (pullback) | `Ind_SmaConverge_Enabled` | Enable |

### 5.2 New Additions Required

| TopInvestor Element | New Code Needed | Effort |
|---|---|---|
| Fibonacci retracement 0.38–0.618 | New `Check_Fib()` voter (~50 lines) | Small |
| Candle body close ratio ≥ 75% | Extend `CheckCandleBodyIndicator()` (~15 lines) | Trivial |
| EMA 9 trailing exit | New `TRAIL_EMA` mode (~40 lines) | Small |

### 5.3 Deliberately Excluded

| Element | Reason |
|---|---|
| OXO reversal signal | Proprietary .ex4, closed source. Replaced by full voting pipeline. |
| Breaker zones | Complex structure detection. Layers + Fibonacci cover most of this implicitly. Phase 2. |
| Visual S/R levels | Phase 2. Swing detection exists for SL; extend to vote as S/R proximity later. |
| Half-candle pending orders | Requires pending-order logic rewrite. Low priority. |

---

## 6. Coverage Estimates

| Configuration | Indicators Enabled | Coverage | Notes |
|---|---|---|---|
| Original proposal | PSAR + CandleBody only | ~70% | Too sparse |
| With all existing indicators ON | + MACD, CCI, ADX, CI, DPI, BB, MTF, SmaConverge | ~85% | No new code needed |
| With 3 new additions | + Fibonacci + Body ratio + EMA trail | ~92% | Small coding effort |
| Theoretical maximum | + Breakers + S/R levels + pending orders | ~98% | Major effort, diminishing returns |

The remaining 8% gap consists of breaker zones, visual S/R level detection, and pending mid-candle orders — all significantly more complex to implement.

---

## 7. Signal Evaluation Profiles

The key insight from the K-score system is that more confluence elements increase quality but decrease frequency. The three profiles below map to K-3, K-4/K-5, and K-6 confluence levels.

**Important:** With `VOTE_MODE_ALL`, every enabled indicator is a veto. Enabling all 11 at once will produce very few signals. The author himself says K-3 is minimum — he does not require all tools simultaneously.

### 7.1 Conservative Profile (start here)

**5 voters.** Matches K-3 confluence. Proven, low false-positive rate. Recommended for initial deployment and backtesting.

Enabled indicators:
1. **PSAR** — direction confirmation (always-on)
2. **ADX Dynamic** — trend strength filter ("silny trend")
3. **CandleBody** — spike rejection + direction gate
4. **Choppiness Index** — ranging market blocker
5. **MTF** — higher timeframe alignment

All others disabled. This configuration ensures we are in a strong, non-choppy trend on both the current and higher TF, PSAR confirms direction, and the signal candle is not a spike.

### 7.2 Moderate Profile (recommended)

**8 voters.** Matches K-4/K-5 confluence. Adds oscillator confirmation and volatility expansion check.

All Conservative indicators plus:
6. **MACD histogram slope** — momentum aligns with bias
7. **CCI zero-line** — momentum direction agrees (above zero = bull, below = bear)
8. **BB Widening** — Bollinger Bands must be actively expanding (volatility breakout)

This profile catches the "something extra" the author demands — not just trend, but expanding momentum in the right direction.

### 7.3 Full Profile (K-6 equivalent)

**11 voters.** Very selective. Few signals per week. For experienced operators who prefer quality over quantity.

All Moderate indicators plus:
9. **DPI momentum** — blocks entries when momentum is decelerating
10. **SMA Convergence** — confirms pullback (EMAs narrowing = correction underway)
11. **Fibonacci retracement** — pullback depth must be 0.38–0.618 of last swing (NEW)

Plus the enhanced CandleBody with MinCloseRatio = 0.75 (NEW).

---

## 8. Full Preset Code — PRESET_TOPINVESTOR

### 8.1 ApplyPreset() Addition for SEA_Presets.mqh

Add the following block inside `ApplyPreset()`, after the existing `PRESET_RRM` block:

```mql5
   if(preset == PRESET_TOPINVESTOR)
   {
      // ================================================================
      // PRESET_TOPINVESTOR — Dr Świerk's TopInvestor / OXO Methodology
      // ================================================================
      //
      // Unified preset covering all 3 TopInvestor systems:
      //   System 1: EMA bounce (Layer pullback to EMA 50/200)
      //   System 2: Key level (Fibonacci retracement depth check)
      //   System 3: Exhaustion (DPI momentum + MACD divergence)
      //
      // OXO replaced by multi-indicator voting pipeline.
      // Three profiles via indicator toggles:
      //   Conservative (5 voters) = K-3
      //   Moderate     (8 voters) = K-4/K-5
      //   Full         (11 voters) = K-6
      //
      // SIGNAL FORMULA:
      //   TS = Phase(4EMA) × Layer × BC × BD × Indicators × Filters
      // ================================================================

      // ── ARCHITECTURE (locked) ──────────────────────────────────────
      cfg.BiasMode               = BIAS_4EMA;
      cfg.AutoStrat              = STRAT_4EMA_LAYER;
      cfg.VoteMode               = VOTE_MODE_ALL;
      cfg.BiasEnabled            = true;
      cfg.BiasFastID             = (int)ROLE_EMA3;    // EMA89 phase direction fast
      cfg.BiasSlowID             = (int)ROLE_EMA4;    // EMA200 phase direction slow
      cfg.MaType                 = METHOD_EMA;
      cfg.CloseOnReverse         = false;
      cfg.RequirePriceCross      = false;
      cfg.MABenchmarkStrict      = false;
      cfg.UseMACompatSizer       = false;

      // ── EMA PERIODS (TopInvestor standard) ─────────────────────────
      cfg.P_Ema1                 = 9;       // EMA9 — trailing exit reference
      cfg.P_Ema2                 = 50;      // EMA50 — primary bounce level
      cfg.P_Ema3                 = 89;      // EMA89 — intermediate structure
      cfg.P_Ema4                 = 200;     // EMA200 — major trend anchor

      // ── PHASE: strict trending only ────────────────────────────────
      cfg.PhaseAllowEM           = false;   // TM only ("silny trend")

      // ── LAYER: pullback-recovery detection ─────────────────────────
      cfg.LayerPullbackEnabled   = true;
      cfg.LayerBaselineLookback  = 10;
      cfg.LayerPullbackRatio     = 0.5;     // pullback = slope weakened 50%
      cfg.LayerRecoveryRatio     = 0.3;     // recovery = 30% strength returned
      cfg.LayerAllowReversalPullback = true;

      // ── HIGHER TF CONFIRMATION ("secret is 2 TF higher") ──────────
      cfg.Ind_MTF_Enabled        = true;
      cfg.Ind_MTF_Weight         = 1;
      cfg.MTF_TF1                = PERIOD_H4;
      cfg.MTF_TF2                = PERIOD_CURRENT;  // single-TF mode
      cfg.MTF_EMA_Fast           = 50;
      cfg.MTF_EMA_Slow           = 200;
      cfg.MTF_RequirePhase       = true;    // HTF must also be in TM phase
      cfg.MTF_StrictAlignment    = false;

      // ── SPREAD: pair-adaptive from Zone 3C ─────────────────────────
      cfg.MaxSpread              = op_MaxSpread;

      // ══════════════════════════════════════════════════════════════
      // VOTING INDICATORS — replacing OXO
      // Profile selection: enable/disable via Inp_TI_* user inputs
      // ══════════════════════════════════════════════════════════════

      // ── CONSERVATIVE PROFILE (always on) ───────────────────────────

      // PSAR — direction confirmation
      cfg.Ind_Psar_Enabled       = true;
      cfg.P_PsarStep             = 0.02;
      cfg.P_PsarMax              = 0.2;
      cfg.Vote_AllowPsarFlip     = true;
      cfg.Vote_PsarFlipDelay     = -1;

      // ADX — trend strength filter
      cfg.Ind_Adx_Enabled        = true;
      cfg.ADX_Mode               = ADX_MODE_DYNAMIC_PERCENTILE;
      cfg.P_Adx                  = 14;
      cfg.ADX_Percentile         = 50.0;    // above median = trending

      // CandleBody — spike rejection + direction gate
      cfg.Ind_CandleBody_Enabled = true;
      cfg.CandleBody_MaxMult     = 2.5;
      cfg.CandleBody_RequireDirection = true;
      // NEW: cfg.CandleBody_MinCloseRatio = 0.75; (see Section 9.2)

      // Choppiness Index — ranging market blocker
      cfg.Ind_CI_Enabled         = true;
      cfg.CI_Period              = 14;
      cfg.CI_RangingThreshold    = 61.8;    // > 61.8 = choppy, block

      // ── MODERATE PROFILE (user-toggled via Inp_TI_*) ───────────────

      // MACD — momentum direction + optional divergence
      cfg.Ind_Macd_Enabled       = Inp_TI_Use_Macd;      // default: true
      cfg.P_MacdFast             = 12;
      cfg.P_MacdSlow             = 26;
      cfg.P_MacdSig              = 9;
      cfg.MacdVoteMode           = MACD_HISTOGRAM;
      cfg.MacdRequireSlope       = true;
      cfg.MacdRequireDivergence  = false;   // optional, user toggle
      cfg.MacdRequireHook        = false;

      // CCI — momentum zero-line confirmation
      cfg.Ind_Cci_Enabled        = Inp_TI_Use_Cci;       // default: true
      cfg.P_Cci                  = 14;
      cfg.CciMode                = CCI_TREND_ZERO;

      // BB Widening — volatility expansion confirmation
      cfg.Ind_Bb_Enabled         = Inp_TI_Use_Bb;        // default: true
      cfg.BbMode                 = BB_WIDENING;
      cfg.P_Bb                   = 20;
      cfg.P_BbDev                = 2.0;

      // ── FULL PROFILE (user-toggled via Inp_TI_*) ───────────────────

      // DPI — momentum exhaustion detection (System 3 "samobój")
      cfg.Ind_Dpi_Enabled        = Inp_TI_Use_Dpi;       // default: false
      cfg.Ind_Dpi_Weight         = 1;
      cfg.DPI_BlockOnDeceleration = true;
      cfg.DPI_HistTrackingEnabled = true;
      cfg.DPI_HistDecelLookback  = 3;

      // SMA Convergence — pullback detection
      cfg.Ind_SmaConverge_Enabled = Inp_TI_Use_SmaConv;  // default: false
      cfg.Ind_SmaConverge_Weight  = 1;

      // Fibonacci retracement — pullback depth check (NEW, see Section 9.1)
      // cfg.Ind_Fib_Enabled      = Inp_TI_Use_Fib;      // default: false
      // cfg.Fib_MinRetracement   = 0.38;
      // cfg.Fib_MaxRetracement   = 0.618;
      // cfg.Fib_SwingLookback    = 50;

      // ── DISABLED (not part of TopInvestor methodology) ─────────────
      cfg.Ind_Rsi_Enabled        = false;
      cfg.Ind_Mfi_Enabled        = false;
      cfg.Ind_Sto_Enabled        = false;
      cfg.Ind_Atr_Enabled        = false;
      cfg.Ind_VRC_Enabled        = false;
      cfg.Ind_P123_Enabled       = false;
      cfg.Ind_Ross_Enabled       = false;

      // ── EXIT MANAGEMENT ────────────────────────────────────────────
      cfg.SLMode                 = SL_MODE_SWING;
      cfg.SwingLookback          = 20;    // "behind 2nd swing" per PDF
      cfg.TrailMode              = TRAIL_PSAR;  // proxy until TRAIL_EMA coded
      // NEW: cfg.TrailMode      = TRAIL_EMA;   // (see Section 9.3)
      // NEW: cfg.TrailEMA_Period = 9;
      cfg.TrailStartsAfterBE    = true;
      cfg.TrailLockProfit        = true;
      cfg.BE_Mode                = BE_MODE_R_MULTIPLE;
      cfg.BE_RMultiple           = 1.0;
      cfg.TPMode                 = TP_MODE_RR;
      cfg.RRRatio                = 2.0;

      // ── INITIAL SL CUSHION (auto-scaled) ───────────────────────────
      cfg.Override_SL_Cushion    = 0.0;   // use TF-adaptive defaults
      cfg.Override_Trail_Cushion = 0.0;
      cfg.Override_BE_Cushion    = 0.0;
   }
```

### 8.2 Enum Addition for SEA_Config.mqh

Add to the `EStrategyPreset` enum:

```mql5
enum EStrategyPreset
{
   PRESET_CUSTOM,
   PRESET_FPM,
   PRESET_MA,
   PRESET_RRM,
   PRESET_RRM_ORG,
   PRESET_TEST,
   PRESET_TOPINVESTOR    // NEW: TopInvestor / OXO methodology
};
```

### 8.3 User Input Declarations for SEA_Config.mqh

Add to Zone 3 inputs section:

```mql5
// ── PRESET_TOPINVESTOR: User Toggles ─────────────────────────────
input string   Inp_TI_Header         = "═══ TopInvestor Profile ═══";   // --- TopInvestor Settings ---
input bool     Inp_TI_Use_Macd       = true;    // TI: Enable MACD (Moderate+)
input bool     Inp_TI_Use_Cci        = true;    // TI: Enable CCI (Moderate+)
input bool     Inp_TI_Use_Bb         = true;    // TI: Enable BB Widening (Moderate+)
input bool     Inp_TI_Use_Dpi        = false;   // TI: Enable DPI momentum (Full)
input bool     Inp_TI_Use_SmaConv    = false;   // TI: Enable SMA Convergence (Full)
input bool     Inp_TI_Use_Fib        = false;   // TI: Enable Fibonacci (Full, requires new code)
input bool     Inp_TI_Use_MacdDiv    = false;   // TI: Require MACD Divergence (stricter)
```

---

## 9. New Code: Three Additions

### 9.1 Fibonacci Retracement Voter

Add to `SEA_Config.mqh` struct `ST_Settings`:

```mql5
   // Fibonacci Retracement voter
   bool   Ind_Fib_Enabled;
   int    Ind_Fib_Weight;
   double Fib_MinRetracement;    // minimum pullback depth (default 0.38)
   double Fib_MaxRetracement;    // maximum pullback depth (default 0.618)
   int    Fib_SwingLookback;     // bars to search for swing high/low (default 50)
```

Add to `SEA_SignalEngine.mqh` (after `Check_SmaConverge`):

```mql5
   //+------------------------------------------------------------------+
   //| Check_Fib: Fibonacci Retracement Depth Voter                     |
   //|                                                                    |
   //| Purpose: Confirm that the current pullback depth falls within     |
   //| the 0.38–0.618 Fibonacci retracement zone of the last swing.     |
   //| This is a key K-score element from the TopInvestor methodology.   |
   //|                                                                    |
   //| Logic:                                                             |
   //|   1. Find the highest high and lowest low in the lookback window. |
   //|   2. Calculate the retracement ratio:                             |
   //|      LONG:  ratio = (swing_high - current_low) / swing_range     |
   //|      SHORT: ratio = (current_high - swing_low) / swing_range     |
   //|   3. PASS if Fib_MinRetracement <= ratio <= Fib_MaxRetracement.  |
   //|                                                                    |
   //| Matches TopInvestor rule: "correction to 0.38 is minimum,        |
   //| may slightly exceed 0.5, should not go beyond 0.618"             |
   //+------------------------------------------------------------------+
   bool Check_Fib(int bias, int shift)
   {
      if(!m_settings.Ind_Fib_Enabled) return true;  // disabled = neutral

      int lookback = m_settings.Fib_SwingLookback;
      if(lookback < 10) lookback = 50;

      // Find swing high and swing low in the lookback window
      // Start from shift+1 to avoid including the signal bar itself
      int start = shift + 1;
      int total = iBars(m_symbol, PERIOD_CURRENT);
      if(start + lookback >= total) return true;  // not enough data

      int hi_idx = iHighest(m_symbol, PERIOD_CURRENT, MODE_HIGH, lookback, start);
      int lo_idx = iLowest(m_symbol, PERIOD_CURRENT, MODE_LOW, lookback, start);

      if(hi_idx < 0 || lo_idx < 0) return true;  // safety

      double swing_high = iHigh(m_symbol, PERIOD_CURRENT, hi_idx);
      double swing_low  = iLow(m_symbol, PERIOD_CURRENT, lo_idx);
      double swing_range = swing_high - swing_low;

      if(swing_range <= 0.0) return false;  // flat market = no valid swing

      double current_close = iClose(m_symbol, PERIOD_CURRENT, shift);
      double ratio = 0.0;

      if(bias == 1)  // LONG: pullback retraces downward from swing_high
      {
         // The swing high should be more recent than the swing low (uptrend)
         if(hi_idx >= lo_idx) return true;  // wrong structure, pass neutrally
         ratio = (swing_high - current_close) / swing_range;
      }
      else if(bias == -1)  // SHORT: pullback retraces upward from swing_low
      {
         // The swing low should be more recent than the swing high (downtrend)
         if(lo_idx >= hi_idx) return true;  // wrong structure, pass neutrally
         ratio = (current_close - swing_low) / swing_range;
      }
      else return true;  // no bias

      bool result = (ratio >= m_settings.Fib_MinRetracement &&
                     ratio <= m_settings.Fib_MaxRetracement);

      if(m_settings.DebugFlow)
      {
         if(m_settings.Ind_Fib_Enabled)
            DebugLog(StringFormat("[IND_FIB] ENABLED | SwingH=%.5f SwingL=%.5f | "
                                  "Ratio=%.3f (%.1f%%) | Range=[%.2f–%.2f] | Result: %s",
                                  swing_high, swing_low, ratio, ratio * 100.0,
                                  m_settings.Fib_MinRetracement,
                                  m_settings.Fib_MaxRetracement,
                                  result ? "PASS" : "FAIL"));
      }

      return result;
   }
```

Wire it into the voting loop (in `CastAllVotes` or equivalent):

```mql5
   CAST_VOTE_STAT(m_settings.Ind_Fib_Enabled, m_settings.Ind_Fib_Weight,
                  Check_Fib(bias, v_shift),
                  m_stats.rejected_fib, m_stats.passed_fib)
```

Add stats counters to the stats struct:

```mql5
   int passed_fib, rejected_fib;
```

### 9.2 CandleBody Close-Ratio Extension

This extends the existing `CheckCandleBodyIndicator()` in `SEA_SignalEngine.mqh`. Add to `ST_Settings`:

```mql5
   double CandleBody_MinCloseRatio;  // Minimum close-to-range ratio (0.0–1.0, default 0.0 = disabled)
```

Modify `CheckCandleBodyIndicator()` — add the following block **before** the existing `return true` at the end:

```mql5
   // ── NEW: Close-ratio quality filter (TopInvestor 75% rule) ──────
   // The signal candle must close in the "strong" portion of its range.
   // LONG:  (close - low)  / (high - low) >= MinCloseRatio
   // SHORT: (high - close) / (high - low) >= MinCloseRatio
   // This ensures the candle shows directional conviction, not indecision.
   if(m_settings.CandleBody_MinCloseRatio > 0.0)
   {
      double h = iHigh(m_symbol, PERIOD_CURRENT, 1);   // signal bar (shift=1)
      double l = iLow(m_symbol, PERIOD_CURRENT, 1);
      double c = iClose(m_symbol, PERIOD_CURRENT, 1);
      double range = h - l;

      if(range > 0.0)
      {
         double close_ratio = 0.0;
         if(bias == 1)       // LONG: close should be near the high
            close_ratio = (c - l) / range;
         else if(bias == -1) // SHORT: close should be near the low
            close_ratio = (h - c) / range;

         if(close_ratio < m_settings.CandleBody_MinCloseRatio)
         {
            if(m_settings.DebugFlow)
               DebugLog(StringFormat("[IND_CB_RATIO] CloseRatio=%.2f < Min=%.2f | FAIL",
                                     close_ratio, m_settings.CandleBody_MinCloseRatio));
            return false;
         }
      }
   }
   // ── END close-ratio extension ───────────────────────────────────
```

### 9.3 TRAIL_EMA Trailing Stop Mode

Add to the `ETrailingMode` enum in `SEA_Config.mqh`:

```mql5
   TRAIL_EMA               // TRAIL_EMA: exit when close crosses EMA against bias
```

Add to `ST_Settings`:

```mql5
   int TrailEMA_Period;    // EMA period for trailing exit (default 9)
```

Add to `SEA_TradeExecutor.mqh` — in the trailing management section, add the case:

```mql5
   //+------------------------------------------------------------------+
   //| TRAIL_EMA: Exit when bar closes across EMA against bias          |
   //|                                                                    |
   //| TopInvestor exit rule: "exit when candle closes below EMA9 for   |
   //| longs, above EMA9 for shorts". This is not a traditional SL      |
   //| trail — it's a bar-close exit signal evaluated at shift=1.        |
   //|                                                                    |
   //| Implementation: Each tick, check if the last closed bar crossed  |
   //| the trailing EMA. If so, close the position at market.            |
   //+------------------------------------------------------------------+
   case TRAIL_EMA:
   {
      m_excursion.trail_active = true;
      m_excursion.trail_type = "EMA";

      // Only check on new bar (shift=1 just closed)
      static datetime last_ema_check = 0;
      datetime bar_time = iTime(m_symbol, PERIOD_CURRENT, 0);
      if(bar_time == last_ema_check) break;  // already checked this bar
      last_ema_check = bar_time;

      // Create or reuse EMA handle
      int ema_period = m_settings.TrailEMA_Period;
      if(ema_period <= 0) ema_period = 9;

      // Calculate EMA value at shift=1 (last closed bar)
      int h_trail_ema = iMA(m_symbol, PERIOD_CURRENT, ema_period,
                            0, MODE_EMA, PRICE_CLOSE);
      if(h_trail_ema == INVALID_HANDLE) break;

      double ema_val[];
      if(CopyBuffer(h_trail_ema, 0, 1, 1, ema_val) != 1)
      {
         IndicatorRelease(h_trail_ema);
         break;
      }
      IndicatorRelease(h_trail_ema);

      double bar_close = iClose(m_symbol, PERIOD_CURRENT, 1);
      bool should_exit = false;

      if(isBuy && bar_close < ema_val[0])
         should_exit = true;     // LONG: close below EMA = exit
      else if(!isBuy && bar_close > ema_val[0])
         should_exit = true;     // SHORT: close above EMA = exit

      if(should_exit)
      {
         if(m_settings.DebugFlow)
            PrintFormat("[TRAIL_EMA] #%I64u: Close=%.5f %s EMA(%d)=%.5f -> EXIT",
                        ticket, bar_close,
                        isBuy ? "<" : ">",
                        ema_period, ema_val[0]);

         // Close position at market
         MqlTradeRequest  req = {};
         MqlTradeResult   res = {};
         req.action    = TRADE_ACTION_DEAL;
         req.position  = ticket;
         req.symbol    = m_symbol;
         req.volume    = PositionGetDouble(POSITION_VOLUME);
         req.type      = isBuy ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
         req.price     = isBuy ? SymbolInfoDouble(m_symbol, SYMBOL_BID)
                                : SymbolInfoDouble(m_symbol, SYMBOL_ASK);
         req.deviation = 10;
         req.comment   = StringFormat("TRAIL_EMA%d_EXIT", ema_period);
         OrderSend(req, res);
      }
      break;
   }
```

**Note:** The handle creation/destruction pattern above is simplified. In production, cache the handle in `m_h_trail_ema` (add to class members) and create it once in `Init()`, release in `ReleaseHandles()`.

---

## 10. Over-Filtering Risk and Tuning

With `VOTE_MODE_ALL`, every enabled indicator is a veto. The relationship between enabled voters and signal frequency is exponential, not linear:

| Voters enabled | Approximate signals/week (M15, major pairs) | K-score equivalent |
|---|---|---|
| 3 (Phase + PSAR + ADX) | 15–25 | K-2 (too loose) |
| 5 (Conservative) | 5–12 | K-3 |
| 8 (Moderate) | 2–5 | K-4/K-5 |
| 11 (Full) | 0–2 | K-6 |

**Recommendation:** Start with Conservative, backtest, then add Moderate indicators one at a time. Monitor the rejection statistics (`Inp_DebugLevel = SUMMARY`) to identify which indicator is the primary bottleneck. If one indicator rejects 80%+ of signals, consider whether it's misconfigured or genuinely filtering bad trades.

**The author's own advice:** "In a truly strong trend, practically every signal works — the result depends not on the signals but on market behavior." This argues for the Conservative profile during strong-trend periods and Moderate during ambiguous conditions.

---

## 11. Exit Strategy Reference

The TopInvestor PDFs describe several exit methods. Here is how each maps:

| TopInvestor Exit | SimpleEA Implementation | Status |
|---|---|---|
| EMA 9 trailing close | `TRAIL_EMA` (Section 9.3) | NEW CODE |
| "Exit when price moves strongly in your direction near TP" | `TRAIL_PROFIT_PERCENT` at 25% | Built-in |
| "SL behind 2nd swing high/low" | `SL_MODE_SWING`, `SwingLookback=20` | Built-in |
| "SL below the moving average" | `SL_MODE_PSAR_DOT` with cushion | Built-in |
| Reversal signal (negation = opposite signal) | `CloseOnReverse = true` | Built-in |

---

## 12. Quick-Start Checklist

1. Add `PRESET_TOPINVESTOR` to the `EStrategyPreset` enum in `SEA_Config.mqh`.
2. Add the `Inp_TI_*` user inputs to Zone 3 in `SEA_Config.mqh`.
3. Add the `ApplyPreset()` block from Section 8.1 to `SEA_Presets.mqh`.
4. Implement `Check_Fib()` from Section 9.1 in `SEA_SignalEngine.mqh` and wire it into voting.
5. Extend `CheckCandleBodyIndicator()` with MinCloseRatio from Section 9.2.
6. Implement `TRAIL_EMA` from Section 9.3 in `SEA_TradeExecutor.mqh`.
7. Add the preset name strings to `GetPresetName()` and `GetPresetDescription()`.
8. Compile and backtest with Conservative profile first (all `Inp_TI_*` at defaults).
9. Monitor rejection statistics with `DebugLevel = SUMMARY`.
10. Gradually enable Moderate indicators, retest each addition.

---

## 13. Appendix: TopInvestor Best Practices (from PDFs)

These discretionary rules cannot be automated but should inform how the operator uses the EA:

- **"The secret to success is 2 timeframes higher."** Always identify the trend on D1/W1 before running the EA on M5/M15. The MTF voter partially automates this.
- **"Play in strong trends during maximum liquidity sessions."** Use StartHour/EndHour to enforce London/NY overlap.
- **"The best entries are at correction endpoints."** This is exactly what the Layer pullback-recovery detection does.
- **"If the market doesn't behave as expected after a signal — change the pair."** Manual operator judgment. If the EA produces many TE rejections on a pair, consider removing it from the watchlist.
- **"Never chase a departing market."** The TE open-delay check handles this — no chasing.
- **"Candle quality matters: close above 75%, no long wicks on the wrong side."** The CandleBody_MinCloseRatio filter automates this.
- **"Confluence (K-score) is the modern approach: the more tools agree, the stronger the signal."** The voting pipeline with VOTE_MODE_ALL implements this directly.

---

*End of Manual*
