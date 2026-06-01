# DPI mc_main — Complete Documentation

> **File:** `DPI_mc_main.mq5`
> **Renamed from:** `DPI_v31_CLEAN_22_OK_FINAL_WORKING.mq5` (logic unchanged, plus GREEN-off visual fix)
> **Naming:** `mc` = MACD + CCI core; `main` = with GREEN momentum overlay (toggleable)

## Overview

DPI (Dynamic Price Index) is a momentum indicator built on a MACD-core architecture with a CCI trend filter and a GREEN momentum overlay. It measures both the direction and the strength of price momentum, with distinct visual components that map to different aspects of the market cycle.

The indicator has three functional layers:
1. **Directional core** — Blue (lead) and Red (signal) lines determine momentum direction
2. **Ribbon histogram** — the area between Blue and Red lines, colored yellow or red (with CCI override), shows whether momentum supports the current direction
3. **GREEN overlay** — appears when Blue and histogram align on the same side of zero, confirming momentum is actively pushing in that direction; its lifecycle (appearing → growing → declining → vanishing) tracks the momentum cycle from impulse to exhaustion

## Components

### Lines

1. **Blue Line (LEAD)** — Fast MACD core = `EMA(Fast, close) − EMA(Slow, close)`. This is the primary momentum measure. When Blue is above zero, short-term momentum is bullish; below zero, bearish.

2. **Red Signal Line (FOLLOW)** — Smoothed version of the Blue line: `EMA(RedType, Blue)` or double-smooth. It lags Blue, creating the histogram divergence that drives the ribbon.

3. **Red Contour Line** — Tracks the histogram value `Blue − Red`. Visually it defines one edge of the ribbon histogram.

### Histogram Colors

The **ribbon histogram** fills the area between the Blue line and the Red contour. Its color indicates momentum quality:

**Without CCI reset:**
- `hist > 0` → **Yellow** (bullish momentum — Blue above Red)
- `hist < 0` → **Red** (bearish momentum — Blue below Red)

**With CCI reset enabled (trend filter):**

CCI acts as a higher-level trend filter. When CCI disagrees with the histogram direction, it "resets" the color as a warning that momentum may be weakening:

| Histogram | CCI | Ribbon Color | Meaning |
|-----------|-----|-------------|---------|
| hist > 0 | CCI > 0 | **Yellow** | Strong bullish — momentum and trend agree |
| hist > 0 | CCI < 0 | **Red** (CCI reset) | Bullish weakening — CCI warns trend shifting |
| hist < 0 | CCI > 0 | **Yellow** (CCI reset) | Bearish weakening — CCI warns trend shifting |
| hist < 0 | CCI < 0 | **Red** | Strong bearish — momentum and trend agree |

### GREEN Histogram Overlay

GREEN is the most important visual component for trade management. It appears when the **Blue line and histogram are on the same side of zero** — meaning the lead momentum and its divergence from the signal are aligned.

**GREEN above the zero line** = Bullish momentum confirmation. Blue is positive (bullish lead) and hist is positive (Blue accelerating away from Red upward). The market is actively pushing higher.

**GREEN below the zero line** = Bearish momentum confirmation. Blue is negative (bearish lead) and hist is negative (Blue accelerating away from Red downward). The market is actively pushing lower.

**GREEN magnitude** = `min(|Blue|, |hist|)` — the smaller of the two aligned components. This is the area from zero to the closer line, visually the "confirmed" portion of the move.

#### GREEN Momentum Lifecycle

GREEN tracks the full momentum cycle within a trending move:

1. **GREEN appears** — Momentum impulse begins. Blue and hist have aligned on the same side. A new wave of directional pressure is starting. This is confirmation that the move is real, not a fake-out.

2. **GREEN grows** — Momentum is accelerating. Both Blue and hist are expanding in the same direction. This is the strongest phase — entries taken during GREEN growth have the best follow-through.

3. **GREEN declines** — Momentum is decelerating. The move is still directional but losing steam. The smaller of Blue/hist is contracting even as the larger may still be expanding. Early warning of exhaustion.

4. **GREEN vanishes** — **Overbought/Oversold condition reached.** Blue and hist are no longer aligned — either hist has crossed zero (Blue/Red convergence), or Blue has crossed zero (momentum reversal). A pullback or reversal is likely. Open profits are at risk of being eroded.

This lifecycle applies identically above and below the zero line. GREEN disappearing in a bullish context signals overbought; in a bearish context, oversold. In both cases, the immediate implication is the same: expect a retracement.

#### GREEN in the EA

GREEN affects two stages of the EA pipeline:

**Entry (Signal Engine):**
- When `DPI_UseGreenHist = true`, GREEN presence is **required** for the DPI vote to pass. A setup without GREEN at entry time fails the DPI voter.
- When `DpiDecelFilterEnabled = true`, the pre-filter blocks entries when GREEN is shrinking (`GREEN[shift] < GREEN[shift+1]`), preventing late entries after the momentum peak.

**Exit (Trade Executor):**
- When `DPI_ExitOnHistDisappear = true` (with `DPI_HistTrackingEnabled = true`), open positions are closed when GREEN vanishes. This locks in profits before the OB/OS pullback erodes them.
- This exit is **direction-neutral** — it works for both BUY and SELL because GREEN exists on both sides of zero.

## EA Vote Logic

The DPI voter in `Check_DPI()` evaluates three independent conditions, all of which must pass:

```
DPI_PASS = dir_ok AND cci_ok AND green_ok
```

1. **dir_ok** — Histogram direction matches bias:
   - LONG bias requires `hist > 0` (Blue above Red)
   - SHORT bias requires `hist < 0` (Blue below Red)

2. **cci_ok** — CCI agrees with histogram (when `UseCCIReset = true`):
   - `hist > 0 AND CCI > 0` → OK (no CCI reset)
   - `hist < 0 AND CCI < 0` → OK (no CCI reset)
   - Disagreement → FAIL (CCI reset warning)
   - Bypassed when `DPI_IgnoreCCIForVote = true`

3. **green_ok** — GREEN is present (when `UseGreenHist = true`):
   - Blue and hist on same side of zero → OK
   - Not aligned → FAIL
   - Bypassed when `UseGreenHist = false`

**Note:** The documentation previously described the vote as "ribbon color drives the vote" — this is an oversimplification. The vote is not a single ribbon-color check but three separate AND conditions: histogram direction, CCI confirmation, and GREEN alignment.

### Vote Example (LONG setup)

```
Bias = LONG (+1)
Blue = 0.0005 (positive → momentum bullish)
hist = 0.0003 (positive → Blue accelerating above Red)
CCI  = +50    (positive → trend agrees)

dir_ok  = (hist > 0 matches LONG)    → PASS
cci_ok  = (hist > 0 AND CCI > 0)     → PASS (no CCI reset)
green_ok = (Blue > 0 AND hist > 0)   → PASS (GREEN present above zero)

→ DPI vote = PASS
→ GREEN visible above zero line (momentum confirmation)
```

### Vote Example (SHORT setup)

```
Bias = SHORT (−1)
Blue = −0.0004 (negative → momentum bearish)
hist = −0.0002 (negative → Blue accelerating below Red)
CCI  = −80     (negative → trend agrees)

dir_ok  = (hist < 0 matches SHORT)   → PASS
cci_ok  = (hist < 0 AND CCI < 0)     → PASS (no CCI reset)
green_ok = (Blue < 0 AND hist < 0)   → PASS (GREEN present below zero)

→ DPI vote = PASS
→ GREEN visible below zero line (bearish momentum confirmation)
```

## Input Parameters

### MACD Settings
- **Fast EMA period** (default: 8) — Fast moving average for Blue line
- **Slow EMA period** (default: 13) — Slow moving average for Blue line

### Red Signal Line Settings
- **Red line type** (default: 3 = EMA13)
  - 1 = EMA5 of Blue
  - 2 = EMA8 of Blue
  - 3 = EMA13 of Blue
  - 4 = EMA21 of Blue
  - 5 = Double smoothed (two-stage EMA)
- **Red EMA periods A/B/C/D** — Individual EMA periods for each type
- **Double smooth: First/Second EMA** — For double smoothing option

### CCI Reset Logic
- **Enable CCI reset logic** (default: true) — Enables trend filter that overrides ribbon color
- **CCI period** (default: 13) — CCI calculation period
- **CCI price calculation** (default: Typical Price HLC/3)

### GREEN Histogram
- **Enable GREEN momentum histogram** (default: true) — Shows momentum alignment overlay; when enabled in EA, also required for DPI vote to pass

### Color Customization (standalone indicator only)
- **Bullish histogram color** (default: Yellow)
- **Bearish histogram color** (default: Red)
- **GREEN overlay color** (default: Lime)

## DPI Exit Logic (CCI Histogram Tracking System)

The CCI Histogram Tracking system provides two exit-side features that work with GREEN:

### Feature 1: Close on GREEN Disappearance (`DPI_ExitOnHistDisappear`)

When enabled, open positions are force-closed on the bar where GREEN vanishes. The rationale:

- GREEN disappearing signals that the momentum impulse is exhausted (OB/OS)
- A pullback or consolidation typically follows
- Closing before the pullback preserves accumulated profits
- This is direction-neutral: works for BUY (GREEN was above zero) and SELL (GREEN was below zero)

**Configuration:**
- `DPI_HistTrackingEnabled = true` (master switch)
- `DPI_ExitOnHistDisappear = true` (enable close-on-GREEN-vanish)
- `DPI_ExitThreshold = 0.0` (optional: close when |CCI| drops below threshold, 0 = disabled)

### Feature 2: Block Entry on GREEN Shrinking (`DpiDecelFilterEnabled`)

When enabled, new entries are blocked when GREEN is declining bar-over-bar. This prevents entering after the momentum peak when the move is already decelerating toward exhaustion.

**Configuration:**
- `DpiDecelFilterEnabled = true`
- `Ind_Dpi_Enabled = true` (DPI voter must be active)

### Feature 3: CCI Deceleration Filter (`DPI_BlockOnDeceleration`)

When enabled, blocks new entries when the CCI histogram values show a pattern of decreasing momentum over a lookback window. This is a more granular deceleration check than GREEN shrinking.

**Configuration:**
- `DPI_HistTrackingEnabled = true` (master switch)
- `DPI_BlockOnDeceleration = true`
- `DPI_HistDecelLookback = 3` (bars to check for deceleration pattern)

## Technical Implementation (MT5 Specific)

### Four Histogram Buffers

The standalone indicator uses FOUR separate histogram buffers instead of two:
- `g_HistYellowPos[]` — Yellow bars on positive side
- `g_HistYellowNeg[]` — Yellow bars on negative side
- `g_HistRedPos[]` — Red bars on positive side
- `g_HistRedNeg[]` — Red bars on negative side

This solves MT5's limitation where you need independent color control on each side when Blue and histogram are on opposite sides of zero.

### EA Internal Calculation

The SimpleEA computes DPI values internally in `SEA_SignalEngine.mqh::ComputeDPIMainHist()` using the same math as the standalone indicator. No indicator handle is needed.

Computed values:
- `out_hist_cur` / `out_hist_prev` — histogram (Blue − Red) at current and previous bar
- `out_green` — boolean: Blue and hist on same side of zero
- `out_green_mag_cur` / `out_green_mag_prev` — `min(|Blue|, |hist|)` when aligned, else 0
- `out_macd_agree` — CCI trend filter agreement flag

### GREEN State Tracking

GREEN presence is tracked per-bar in `UpdateDPIHistogramState()` and passed to the Trade Executor via `SetDPIHistogramState()`. The executor uses `m_dpi_hist_green_present` for the exit check, not the CCI-based `m_dpi_hist_trend`.

## Configuration Mapping

EA settings map to standalone indicator parameters:

| EA Setting | Indicator Parameter | Default | Purpose |
|------------|---------------------|---------|---------|
| `DPI_MACD_Fast` | `InpFastEMA` | 8 | Blue line fast EMA |
| `DPI_MACD_Slow` | `InpSlowEMA` | 13 | Blue line slow EMA |
| `DPI_RedSignalType` | `InpRedLineType` | 3 (EMA13) | Red signal calculation |
| `DPI_UseCCIReset` | `InpEnableCCI` | true | CCI trend filter for ribbon color |
| `DPI_CCI_Period` | `InpCCIPeriod` | 13 | CCI calculation period |
| `DPI_UseGreenHist` | `InpEnableGreen` | true | GREEN alignment check in vote |
| `DPI_IgnoreCCIForVote` | — | false | Bypass CCI in vote (hist direction only) |

## Trading Interpretation

### Signal Strength Hierarchy

1. **Strongest** — Yellow ribbon + GREEN growing + no CCI resets. Full momentum alignment, impulse phase.
2. **Strong** — Yellow/Red ribbon matching direction + GREEN present but flat. Momentum confirmed but not accelerating.
3. **Weakening** — GREEN shrinking. Still directional but momentum fading. Avoid new entries.
4. **Exhausted** — GREEN vanished. OB/OS reached. Close open positions; expect pullback.
5. **Conflicted** — CCI reset active (ribbon color contradicts hist direction). Momentum direction uncertain.

### GREEN as Trade Management Tool

GREEN provides actionable trade management signals:
- **GREEN appears** → Momentum confirmed; entries are safe, trailing can be loose
- **GREEN peak** → Maximum momentum; tighten trailing or take partial profits
- **GREEN declining** → Momentum fading; block new entries, tighten stops
- **GREEN vanishes** → Exhaustion; close position before pullback erodes gains

## GREEN-OFF Visual Fix

When `InpEnableGreen = false` (GREEN overlay disabled), the histogram renders as a clean single-color `0→Blue` ribbon on Blue's side only — matching MT4 reference behavior.

**Note:** Disabling GREEN in the standalone indicator does not affect the EA's GREEN vote condition. The EA computes GREEN internally regardless of the indicator's visual toggle. To disable GREEN in the EA vote, set `DPI_UseGreenHist = false` in the EA inputs.

## Files Structure

```
DPI_mc_main.mq5
├── Plot 0: Blue_MACD_Core (Blue line — lead momentum)
├── Plot 1: Red_Signal (Red signal line — smoothed Blue)
├── Plot 2: Red_Contour (Histogram value = Blue − Red)
├── Plot 3: Hist_Red_Pos (Red ribbon on positive side)
├── Plot 4: Hist_Red_Neg (Red ribbon on negative side)
├── Plot 5: Hist_Yellow_Pos (Yellow ribbon on positive side)
├── Plot 6: Hist_Yellow_Neg (Yellow ribbon on negative side)
└── Plot 7: Hist_Green (GREEN momentum alignment overlay)
```

**Related files:**
- `DPI_mc_simple.mq5` — Simplified variant (no GREEN, renamed from `DPI_v29_OK_CLEAN.mq5`)
- `DPI_tm_simple.mq5` — TSI+MACD math family (William Blau Ergodic)
- `Legacy/DPI_v31_CLEAN_22_OK_FINAL_WORKING.mq5` — Original pre-rename (historical reference)

## Troubleshooting

### GREEN Not Visible
**Symptoms:** GREEN is declared but doesn't show in Colors tab
**Cause:** `#property indicator_plots` count is wrong
**Fix:** Must be set to 8 (for plots 0-7)

### Gaps in Histogram
**Symptoms:** Ribbon doesn't fill continuously between lines
**Cause:** Using only 2 histogram buffers instead of 4
**Fix:** Already implemented — 4 buffers allow independent color per side

### CCI Resets Not Working
**Symptoms:** Histogram always matches its sign (no color overrides)
**Cause:** Color logic applies to wrong sides when opposite
**Fix:** Already implemented — same color (based on hist) applies to both sides

### DPI Exit Kills All SHORT Trades (fixed 2026-05-21)
**Symptoms:** 0% SHORT win rate; all SHORTs closed on bar 1 after entry
**Cause:** `CheckDPIHistogramExit()` was checking `m_dpi_hist_trend != 1` which used CCI sign (positive=1). For SHORTs, CCI is correctly negative (trend=-1), so `-1 != 1` was always true → immediate exit.
**Fix:** Now tracks actual GREEN presence via `ComputeDPIMainHist()` instead of CCI sign. Direction-neutral — GREEN on either side of zero confirms the trade is alive.

## Version History

- **mc_simple / v29** — CCI resets working, gaps present, no GREEN
- **v30_14** — Continuous ribbon, GREEN correct, no CCI resets
- **v30_16** — Attempted fix, still had issues
- **v31_18** — Four buffers, CCI logic bug
- **v31_20** — CCI logic fixed, GREEN not plotting (plots=7 bug)
- **v31_25** — All features operational (base for `DPI_mc_main.mq5`)
- **mc_main** — GREEN-off visual fix applied (clean `0→Blue` ribbon when `InpEnableGreen=false`)
- **EA v1-04 (2026-05-21)** — Fixed `CheckDPIHistogramExit` to use GREEN presence instead of CCI sign; added `m_dpi_hist_green_present` tracking through Signal Engine → Executor pipeline

## See Also

- [Signal reference — DPI voter section](README_SEA_SIGNAL_REFERENCE.md)
- [Preset reference — PRESET_RRM_ORG workflow](README_SEA_PRESETS.md)
- [Trade logic — Exit management modes](README_SEA_TRADE_LOGIC.md)
