# PRESET_RRM — Complete Configuration Reference

## Overview

`PRESET_RRM` is the production preset for the RRM (Rhythm-Responsive Market) methodology. It implements a strict **multiplicative signal filter** where every enabled indicator must agree before a trade is taken.

**Core formula:**
```
Trade Signal (TS) = Bias × Phase × Layer × Ind₁ × Ind₂ × ... × Indₙ
→ ANY factor = 0 → TS = 0 (no trade)
```

---

## Default PRESET_RRM Settings

### Bias & Phase

| Setting                | Value        | Description                                    |
|------------------------|--------------|------------------------------------------------|
| `BiasMode`             | AUTO_PHASE   | EMA-slope + phase detection for trend direction |
| `PhaseDetectionEnabled`| false        | Phase detection off by default                  |
| `MinPhaseConfirmBars`  | 0            | Instant EMA check (0 = no delay)               |
| `BlockUnorderedPhase`  | true         | Block all trades in choppy UNORDERED phase     |

### Entry Layer

| Setting                    | Value | Description                                         |
|----------------------------|-------|-----------------------------------------------------|
| `EnableLayerDetection`     | false | Layer detection off by default                      |
| `LayerTouchTolerance`      | 1%    | Price must be within 1% of EMA to count as touch    |
| `RequireRecoveryMomentum`  | false | Recovery momentum confirmation not required         |

### Indicator Voting (Multiplicative — ALL must pass)

Default enabled indicators:

| Indicator | Enabled | Notes                          |
|-----------|---------|--------------------------------|
| EmaSig    | ✅      | Price vs EMA1                  |
| MACD      | ✅      | Zero-line + crossover (TRIPLE) |
| PSAR      | ✅      | Parabolic SAR direction        |
| CCI       | ✅      | Commodity Channel Index        |
| RSI       | ❌      | Disabled by default            |
| ADX       | ❌      | Disabled by default            |
| MFI       | ❌      | Disabled by default            |
| Stoch     | ❌      | Disabled by default            |
| BB        | ❌      | Disabled by default            |
| P123      | ❌      | Disabled by default            |
| Ross Hook | ❌      | Disabled by default            |

> **Important:** In VOTE_MODE_ALL (default), ALL enabled indicators must pass. Adding more indicators makes the system MORE restrictive, not more confirmatory.

---

## Understanding Rejection Statistics

After each backtest or live session, rejection statistics print automatically in `OnDeinit()`. This shows you WHY trades were blocked:

```
════════════════════════════════════════════════
  REJECTION STATISTICS
════════════════════════════════════════════════
Bars evaluated: 1440
Signals confirmed: 12 (0.83%)

TOP REJECTION REASONS:
   1. Bias=0               :   820 bars (56.9%)
   2. MACD                 :   310 bars (21.5%)
   3. PSAR                 :   180 bars (12.5%)
   4. CCI                  :    85 bars (5.9%)
   5. EmaSig               :    28 bars (1.9%)
════════════════════════════════════════════════
```

### Interpreting Results

| Rejection Reason  | Meaning                                                                 |
|-------------------|-------------------------------------------------------------------------|
| `Bias=0`          | No clear EMA trend direction — most common in ranging/choppy markets    |
| `Phase=UNORDERED` | Phase detection active & market is choppy (only if PhaseDetectionEnabled=true) |
| `Layer=NONE`      | STRAT_LAYER_DETECTION mode: no pullback-recovery pattern found          |
| `Layer blocked`   | Phase-layer rule blocked entry (e.g., L3 in EMERGING phase)             |
| `MACD`            | MACD vote failed — price action doesn't confirm trend via MACD          |
| `PSAR`            | Parabolic SAR is on wrong side of price                                 |
| `CCI`             | CCI is not in the expected zone                                         |
| `EmaSig`          | Price is on wrong side of EMA1                                          |
| `Spread`          | Current spread exceeds `MaxSpread` limit                                |
| `ATR Min`         | Volatility too low (market too quiet for safe entries)                  |
| `ATR Max`         | Volatility too high (market too volatile for safe entries)              |
| `Time filter`     | Outside allowed trading hours                                           |
| `News filter`     | Within pre/post news event blackout window                              |

---

## Configuration Validation

On startup, the EA prints a configuration validation report:

```
════════════════════════════════════════════════
  CONFIGURATION VALIDATION
════════════════════════════════════════════════
WARNING: 7 indicators enabled (ALL must pass)
   Very restrictive, consider disabling some
════════════════════════════════════════════════
```

### Common Warnings and Fixes

#### "PhaseDetection=true but BiasMode != AUTO_PHASE"
- **Cause:** `PhaseDetectionEnabled=true` but `BiasMode` is set to MANUAL or AUTO
- **Fix:** Set `BiasMode = BIAS_AUTO_PHASE` or disable phase detection

#### "LayerDetection=true but PhaseDetection=false"
- **Cause:** `EnableLayerDetection=true` but `PhaseDetectionEnabled=false`
- **Fix:** Enable phase detection or disable layer detection

#### "N indicators enabled (ALL must pass)"
- **Cause:** More than 6 indicators enabled simultaneously
- **Fix:** Disable indicators that are redundant or causing too many rejections
- **Tip:** Check rejection statistics to see which indicator blocks the most trades

#### "NO indicators enabled!"
- **Cause:** All indicator votes are disabled
- **Fix:** Enable at least one indicator (EmaSig is a good starting point)

---

## Troubleshooting: Why Am I Getting Few Trades?

### Step 1: Run a backtest and read rejection statistics

In `OnDeinit()` you will see the top rejection reasons sorted by frequency.

### Step 2: Identify the primary blocker

- **Bias=0 is dominant (>50%):** Market lacks a clear trend on this timeframe. Try a longer timeframe (H4 → D1) or add more trend-friendly instruments.
- **Indicator is dominant (>30%):** That specific indicator is very restrictive. Consider disabling it or adjusting its parameters.
- **Phase=UNORDERED is dominant:** Market is choppy. This is correct behavior — PRESET_RRM avoids low-quality setups.

### Step 3: Test adjustments using Admin Override

Use ZONE 3B (Admin Override) to temporarily modify preset values without changing the preset:

1. Set `Inp_AdminOverridePreset = true`
2. Adjust the relevant `Inp_Override_*` inputs
3. Re-run backtest and compare rejection statistics

---

## Admin Override Mode

### When to Use Admin Override

Admin Override is for **experienced users** who want to test adjustments to PRESET_RRM values without switching to PRESET_CUSTOM.

### How It Works

```
Inp_AdminOverridePreset = false (default)
→ All Inp_Override_* inputs are IGNORED
→ PRESET_RRM values are fully enforced

Inp_AdminOverridePreset = true
→ Inp_Override_* inputs REPLACE the corresponding preset values
→ Useful for testing individual parameter changes
```

### Overridable Settings

- **Strategy & EMAs:** AutoStrat, EMA periods, indicator on/off toggles
- **Indicator parameters:** MACD, RSI, CCI, ADX, Stoch, PSAR, BB, MFI periods and thresholds
- **Risk & entry:** SL/TP multipliers, risk percent, price cross requirements
- **Phase & layer:** Phase detection on/off, layer detection, phase-layer rules per layer

### NOT Overridable via Admin Mode

- **Adaptive settings:** Pair type detection, spread limits (use Zone 2 inputs)
- **RRM drawdown protection:** Uses dedicated §6 inputs regardless of admin mode

---

## Phase Detection (Advanced)

Phase detection classifies the market into three states:

| Phase     | Description                        | Behavior with PRESET_RRM               |
|-----------|------------------------------------|----------------------------------------|
| TRENDING  | Strong, established trend          | All layers allowed (L1/L2/L3)          |
| EMERGING  | Trend forming, not yet confirmed   | L1/L2 allowed; L3 (Shark) blocked      |
| UNORDERED | Choppy, no clear direction         | ALL trades blocked                     |

### Enabling Phase Detection

Phase detection is **disabled by default** in PRESET_RRM. To enable:

**Via Admin Override:**
1. Set `Inp_AdminOverridePreset = true`
2. Set `Inp_Override_PhaseDetectionEnabled = true`
3. Ensure `Inp_Override_EnableLayerDetection = true`

**Via PRESET_CUSTOM:**
```
InpPreset = PRESET_CUSTOM
Inp_BiasMode = BIAS_AUTO_PHASE
```
Then set your phase/layer settings in Zone 3A.

---

## Layer Detection (Advanced)

Layer detection identifies which EMA layer a pullback is touching:

| Layer   | EMAs          | Nickname | Depth    |
|---------|---------------|----------|----------|
| Layer 1 | EMA1 / EMA2   | Ribbon   | Shallow  |
| Layer 2 | EMA2 / EMA3   | Ghost    | Medium   |
| Layer 3 | EMA3 / EMA4   | Shark    | Deep     |

Layer detection is most useful with `STRAT_LAYER_DETECTION` and `BIAS_AUTO_PHASE`.

---

## H4 Timeframe Tuning Notes

H4 is a longer timeframe with fewer bars. Expect:
- Fewer total bars evaluated per session
- Lower trade frequency (quality over quantity)
- `Bias=0` will dominate (H4 spends more time consolidating)

**Typical H4 signal rate:** 0.5–2% of bars (very normal for a strict multiplicative system)

If you need more trades on H4:
1. Reduce the number of enabled indicators (check rejection stats for worst offenders)
2. Consider disabling PSAR (tends to be slow on H4)
3. Try `MACD_HISTOGRAM` mode instead of `MACD_TRIPLE`

---

## Quick Reference

```
PRESET_RRM defaults:
  BiasMode:           BIAS_AUTO_PHASE
  Phase detection:    OFF (enable via admin override)
  Layer detection:    OFF (enable via admin override)
  Voting mode:        ALL (multiplicative)
  Indicators:         EmaSig + MACD + PSAR + CCI

To diagnose low trade count:
  1. Read rejection stats in OnDeinit()
  2. Find top rejection reason
  3. Use Admin Override to test adjustments
  4. Compare backtest results
```
