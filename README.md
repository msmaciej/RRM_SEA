# SimpleEA (RRM_SEA)

SimpleEA is a professional-grade Expert Advisor for MetaTrader 5 implementing a comprehensive 9-step signal validation pipeline combining market bias analysis, multi-indicator voting, and risk-aware position management. 

**Environment Constraints:** macOS + Wine + MT5 + **MQL5 ONLY** (no C++, no templates, no lambdas).

---

## 📊 TS Equation — Signal Evaluation Formula

```
TS = B × P × L × I × F
```

Every factor is multiplicative. Any factor = 0 → TS = 0 → NO TRADE.

| Factor | Name | Purpose |
|--------|------|---------|
| **B** | Bias | Market direction: LONG (+1), SHORT (-1), or NONE (0) |
| **P** | Phase / Market Type | Structural quality of the trend — permits or blocks trading |
| **L** | Layer / Sub-market | Entry timing via pullback-recovery detection |
| **I** | Indicators | Technical confirmations (all enabled must agree) |
| **F** | Filters | Execution conditions: spread, session time, news |

---

### B — Bias

Direction is always determined by the **slowest available EMA pair's position** (or slope if only 1 EMA):

| EMA count | Method | Rule |
|-----------|--------|------|
| 1 EMA | Slope of that EMA | Rising → LONG, Falling → SHORT |
| 2 EMAs | Position: fast vs slow | fast > slow → LONG, fast < slow → SHORT |
| 3 EMAs | Position: slowest pair (EMA3 vs EMA2) | same positional rule |
| 4 EMAs | Position: slowest pair (EMA4 vs EMA3) | same positional rule |

The slowest pair is always the most structurally stable signal. Slopes are only used when a single EMA is configured.

---

### P — Phase (Market Type)

Evaluated using **EMA2, EMA3, EMA4 position only**. EMA1 is ignored. No slopes.

| Phase | Bullish condition | Bearish condition | Trade allowed? |
|-------|-------------------|-------------------|----------------|
| **TM** (Trending) | EMA2 > EMA3 > EMA4 | EMA4 > EMA3 > EMA2 | ✅ Always |
| **EM** (Emerging) | EMA2 > **EMA4** > EMA3 | EMA3 > **EMA4** > EMA2 | ✅ If configured |
| **UNO** (Unordered) | any other arrangement | any other arrangement | ❌ Never |

Key: EM is identified by EMA4 (slowest) being sandwiched between EMA2 and EMA3. UNO is identified by EMA2 (fast) being sandwiched — or any arrangement not matching TM or EM.

---

### L — Layer (Sub-market)

Three sub-markets exist within each bias direction. Each is evaluated independently using its own EMA pair.

| Layer | EMA Pair | Nickname | Priority |
|-------|----------|----------|----------|
| **L3** Strong / Shark | EMA3 – EMA4 | Deep pullback | **Highest** (used first) |
| **L2** Medium / Ghost | EMA2 – EMA3 | Medium pullback | Medium |
| **L1** Weak / Ribbon | EMA1 – EMA2 | Shallow pullback | Lowest |

**Priority rule**: If multiple layers are valid, take L3 first, then L2, then L1.

**Why L3 is highest probability**: The slowest EMA pair reflects the strongest structural support/resistance. A pullback to EMA3-EMA4 and recovery is the most reliable setup.

**Layer Sub-Equation** (per layer):

```
L_x = pos_x × slope_x × BC_x × BD_x
```

Where:
- **pos_x** — EMA_fast correctly positioned relative to EMA_slow (above for LONG, below for SHORT)
- **slope_x** — Pullback detected (fast EMA slope flattened/moved toward slow), then recovery (fast EMA slope resumed bias direction)
- **BC_x** (Bar Close) — Close price is beyond the fast EMA of this layer in bias direction. LONG: close > fast EMA. SHORT: close < fast EMA. Checks the closing price level regardless of wick or body size.
- **BD_x** (Bar Direction) — Bar closed in bias direction. LONG: close > open (bullish bar). SHORT: close < open (bearish bar). A doji or opposite bar = 0 even if close is beyond the EMA.

**BC and BD are independent**: A bar can close above EMA1 (BC=1) but be bearish (BD=0) → L=0. This correctly rejects uncertainty and market indecision even when price is at the right level.

**Layer independence**: Each layer is evaluated on its own. If EMA1 crosses below EMA2 (L1 invalid), L2 may still be valid if EMA2 slope is pulling toward EMA3 and price closes above EMA2. The BC check is the key discriminator — it determines which layer boundary price actually respected.

---

### I — Indicators

All enabled technical indicators evaluated at bar close (shift=1). All must pass (VOTE_MODE_ALL):

```
I = MACD × PSAR × RSI × CCI × ADX × MFI × Stoch × BB × CandleBody × ...
```

**CandleBody** belongs here — it checks whether the bar is a spike (body > N × average body → reject). This is different from BD (which checks direction) and BC (which checks close level).

Disabled indicators contribute 1 (neutral — they do not block).

---

### F — Filters

Execution-moment conditions checked at bar open (shift=0) during TE evaluation:
- Spread ≤ MaxSpread
- Session time within configured window
- No high-impact news imminent

---

### Full TS Flow

```
Bar N closes (shift=1):
  B → direction determined
  P → market type confirmed (UNO = stop)
  L = pos × slope × BC × BD  (L3 checked first, then L2, then L1)
  I → all indicators must agree
  → TS=1: signal armed

Bar N+1 opens (shift=0):
  F → spread / session / news check
  → TE=1: trade executed
```

---

## 📐 Bias Modes & Strategy Mapping

SimpleEA supports 4 bias modes, each with specific strategy requirements:

| BiasMode | Description | Valid Strategies | EMAs Used | Layers |
|----------|-------------|------------------|-----------|--------|
| `BIAS_MANUAL` | User sets fixed direction | None | 0 | ❌ |
| `BIAS_1EMA` | Single EMA slope | `STRAT_1EMA_SLOPE` | EMA1 only | ❌ |
| `BIAS_2EMA` | Two EMA crossover/position | `STRAT_2EMA_CROSS`<br>`STRAT_PRICE_CROSS`<br>`STRAT_2EMA_POSITION` | EMA1, EMA2 | ❌ |
| `BIAS_4EMA` | Four EMA phase detection | `STRAT_4EMA_LAYER` | EMA1-4 | ✅ LayerW/M/S |

### Strategy Details

- **`STRAT_1EMA_SLOPE`**: Signal based on single EMA slope direction (up/down/flat)
- **`STRAT_2EMA_CROSS`**: Signal generated at EMA crossover point (one-bar signal)
- **`STRAT_PRICE_CROSS`**: Signal generated when price crosses EMA (one-bar signal)
- **`STRAT_2EMA_POSITION`**: Signal generated when position + slopes agree (continuous)
- **`STRAT_4EMA_LAYER`**: Signal generated on pullback-recovery patterns in EMA zones

---

## 🗺️ Canonical Documentation Map
The system architecture has been refactored into focused, authoritative files. Start here:

* **[Step 1: Signal & Indicator Engine](Readme/README_SEA_SIGNAL_REFERENCE.md)**
    * The 9-step TS (Trade Setup) multiplicative pipeline (`TS = Bias × Phase × Layer × Indicators`).
    * Indicator logic (ADX Dynamic, VRC Percentiles, MACD, PSAR, etc.).
    * Developer Guide: Centralized Indicator Registry & Plugin pattern.
* **[Step 2: Execution & Trade Logic](Readme/README_SEA_TRADE_LOGIC.md)**
    * The TE (Trade Entry) execution architecture at shift=0.
    * Exit Management (SL, TP, Breakeven, and Trailing).
    * Auto-scaling TF-based cushions and Adaptive Spread Limits.
* **[SEA Agents Bootstrapping](Readme/README_SEA_BOOTSTRAP.md)**
    * AI Agent Manifest and instructions for starting new chat tasks.
* **[Preset Reference](Readme/README_SEA_PRESETS.md)**
    * Full logic diagrams and user guides for all presets: CUSTOM, MA, RRM, TEST, FPM.
    * Five-Point Method (PRESET_FPM) cheat sheet mapping and Zone 3C input reference.

---

## 🏛️ System Architecture: The Modular Shift
SimpleEA utilizes a highly modular architecture. To eliminate parameter bloat and prevent over-optimization, all configuration and preset definitions have been permanently migrated into dedicated header files:

1. **`SEA_Config.mqh`**: The ultimate source of truth for all global variables, enums, and the master `ST_Settings` struct. This file manages the visual inputs in the MT5 dialog and maps them via `InitializeConfig()` into the global struct used by all other modules.
2. **`SEA_Presets.mqh`**: Contains hardcoded strategy arrays and struct assignments. When a specific preset is selected, this file overrides the MT5 UI inputs to enforce strict, institutional-grade parameters.

## ⚙️ Configuration Zones (The Architect Manual)

Inputs in `SEA_Config.mqh` are visually grouped in the MT5 dialog to distinguish operator controls from preset-controlled strategy variables.

### ZONE 1: Preset Selection
Selects the core strategy mapped within `SEA_Presets.mqh`. See **[📐 Preset Reference →](Readme/README_SEA_PRESETS.md)** for full logic diagrams and user guides.

| Preset | Summary | Strategy locked? | Exits locked? |
|---|---|---|---|
| `PRESET_CUSTOM` | All inputs respected; full user control | ✗ | ✗ |
| `PRESET_MA` | MT5 Moving Average EA benchmark | ✓ (voting off) | ✓ fixed pips |
| `PRESET_RRM` | Phase-based trend pullback (4EMA, PSAR+MACD+CCI) | ✓ | Partially (trail locked, SL/TP user) |
| `PRESET_TEST` | Development / debug bypass | ✗ (threshold=1) | ✓ fixed pips |
| `PRESET_FPM` | **Five-Point Method** — PSAR + MACD crossover + BB widening + SMA10/20 convergence + bar close | ✓ | ✗ (SL/TP/Trail user-controlled via Zone 3C) |

1.  **Anti-Confusion Mapping:** When `PRESET_RRM` is active, it fully defines all strategy-critical settings via `SEA_Presets.mqh`. Strategy-related inputs in MT5 are ignored. The EA prints a clear initialization note, and the UI/Logs display the *effective* settings.
2.  **Two-Phase Signal Timing:**
    * **TS (Trade Setup):** Evaluated strictly on the closed candle (`shift=1`) via `GetDirection()`.
    * **TE (Trade Entry):** Evaluated strictly on the open tick (`shift=0`) via `EvaluateTE()`, checking real-time spread, time, and news limits. 
    * No signal evaluation occurs on forming bars. No trade execution occurs without a prior TS validation.
3.  **Strict Multiplicative Voting:** In RRM setups, `VOTE_MODE_ALL` is enforced. Adding indicators makes the system MORE restrictive, not less. ANY indicator returning 0 kills the signal.

### ZONE 2: User Controls (Policy A Gates)
**Always editable by the user, regardless of preset.**
* Operator Gates: Spread Limits (`MaxSpreadPips`).
* Time/Session Filter (`StartHour`, `EndHour`).
* News Filter & HTF Trend Filter.
* UI, Diagnostics, and Reporting output levels.

### ZONE 3A: Preset Info
Contains the strategy-critical variables (EMA periods, Indicator toggles, Exit modes). 
* If `PRESET_CUSTOM` is active, these inputs drive the EA. 
* If any other preset is active, these inputs are **ignored and overridden** by the hardcoded preset to guarantee systemic integrity.

### ZONE 3B & 3C: Overrides & Adaptives
* **Zone 3B (Admin Override):** Setting `Inp_AdminOverridePreset = true` allows advanced users to test variations of strict presets without modifying source code.
* **Zone 3C (Pair Limits):** Auto-detects pair types to apply dynamic spread limits.

---

## ⚖️ The Preset Policy (Model A) & Architecture Rules

To avoid misleading behavior and user confusion, presets are defined as **fully authoritative**.

1.  **Anti-Confusion Mapping:** When `PRESET_RRM` is active, it fully defines all strategy-critical settings. Strategy-related inputs in MT5 are ignored. The EA prints a clear initialization note, and the UI/Logs display the *effective* settings.
2.  **Two-Phase Signal Timing:**
    * **TS (Trade Setup):** Evaluated strictly on the closed candle (`shift=1`) via `GetDirection()`.
    * **TE (Trade Entry):** Evaluated strictly on the open tick (`shift=0`) via `EvaluateTE()`, checking real-time spread, time, and news limits. 
    * No signal evaluation occurs on forming bars. No trade execution occurs without a prior TS validation.
3.  **Strict Multiplicative Voting:** In RRM setups, `VOTE_MODE_ALL` is enforced. Adding indicators makes the system MORE restrictive, not less. ANY indicator returning 0 kills the signal.

---

## 📊 System Analysis & Reporting

SimpleEA automatically outputs comprehensive performance metrics directly to the `OnDeinit` log, segmented into three critical diagnostic areas:\

1.  **Signal Efficiency:** Tracks total bars evaluated, TS conversion rate, and individual component pass/fail rates (e.g., "Bias=0: 56.9% rejection").
2.  **Trade Performance:** Win rate (Long vs Short), Profit Factor, Average Win/Loss, and Consecutive streaks.
3.  **Risk Analysis:** Maximum Absolute/Relative Drawdown, Recovery Factor, and Risk-Reward ratio profiling.

*Use the `Inp_DebugLevel` (Zone 2) to control per-tick log verbosity (DEBUG_SILENT, SUMMARY, INDICATORS, FULL).*
---

## 📐 DPI — Dynamic Price Indicator (v31)

### Overview

The EA's internal DPI is now **v31-equivalent**, matching `DPI_v31_CLEAN_22_OK_FINAL_WORKING.mq5` bar-for-bar (same histogram sign, same green/yellow/red zone logic).

### Architecture

```
Blue(i) = EMA(DPI_MACD_Fast, close)(i) − EMA(DPI_MACD_Slow, close)(i)
Red(i)  = EMA(RedSignalType, Blue)(i)                 [or double-smooth]
hist(i) = Blue(i) − Red(i)
```

**Red signal line types** (`DPI_RedSignalType`):
| Type | Method | Default period |
|------|--------|---------------|
| 1 | EMA_A | 5 |
| 2 | EMA_B | 8 |
| **3** | **EMA_C** (default) | **13** |
| 4 | EMA_D | 21 |
| 5 | Double-smooth (First → Second EMA) | 5 → 8 |

### DPI as a Voting Indicator

DPI now participates in the TS equation `I` factor as a first-class voting indicator (on par with MACD, CCI, RSI, etc.). Enable with `Inp_Ind_Dpi_Enabled = true`.

**Vote logic:**
1. **Direction**: `hist > 0` → LONG pass; `hist < 0` → SHORT pass
2. **CCI filter** (when `DPI_UseCCIReset = true`): requires `sign(hist) == sign(CCI)` — no CCI reset warning
3. **GREEN momentum** (when `DPI_UseGreenHist = true`): requires Blue and hist on the same side of zero (strength confirmation)

All three checks must pass. Any failure → DPI vote fails → TS = 0 (in `VOTE_MODE_ALL`).

### v29-Equivalent Behavior

Set `Inp_RRM_ORG_DPI_UseGreenHist = false` to disable the GREEN overlay (reproduces DPI v29 behavior). CCI reset remains independently toggleable.

### Standalone Indicators (Chart Visualization)

The following files remain at repo root for direct chart use and A/B comparison:
- `DPI_v29_OK_CLEAN.mq5` — v29 reference (MACD core + CCI reset, no GREEN)
- `DPI_v31_CLEAN_22_OK_FINAL_WORKING.mq5` — v31 reference (MACD core + CCI reset + GREEN)
- `DPI_v31_CLEAN_22_DOCUMENTATION.md` — full parameter reference

### Legacy

`DPI_Indicator.mq5` (TSI-based) and `DPI_Indicator_v7.mq5` have been moved to `Legacy/` and are no longer maintained. The EA's internal DPI logic is now v31-equivalent and supersedes both.
