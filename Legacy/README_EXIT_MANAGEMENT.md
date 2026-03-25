# Exit Management

## Overview

SimpleEA supports multiple exit modes for SL, TP, Breakeven, and Trailing Stop.
All cushion values auto-adjust by timeframe — no manual input required.

---

## Stop Loss Modes (`ESLMode`)

| Mode | Description |
|------|-------------|
| `SL_MODE_FIXED_PIPS` | User-defined pip distance (`Inp_SL_FixedPips`) |
| `SL_MODE_PSAR_DOT` | PSAR level + TF-based cushion (auto) |
| `SL_MODE_SWING` | Swing high/low + TF-based cushion (auto) |
| `SL_MODE_FRACTAL` | Fractal level + TF-based cushion (auto) |
| `SL_MODE_PERCENT` | % of entry price (`Inp_SLPercent`) |

---

## Take Profit Modes (`ETPMode`)

| Mode | Description |
|------|-------------|
| `TP_MODE_FIXED_PIPS` | User-defined pip distance (`Inp_FixedTPPips`) |
| `TP_MODE_RR` | Risk:Reward ratio (`Inp_RRRatio`, e.g., 2.0 = 1:2 RR) |
| `TP_MODE_FRACTAL` | Next fractal level (market-defined) |
| `TP_MODE_PSAR_FLIP` | Exit on PSAR flip (no fixed TP) |
| `TP_MODE_NONE` | No TP (rely on trailing stop) |

---

## Breakeven Modes (`EBeMode`)

| Mode | Description |
|------|-------------|
| `BE_MODE_OFF` | Disabled |
| `BE_MODE_TP_PROGRESS_PCT` | Trigger at % progress toward TP |
| `BE_MODE_R_MULTIPLE` | Trigger at R-multiple threshold |

**Buffer:** Auto-set by TF via `GetTFBasedCushion()`. No user input required.

---

## Trailing Stop Modes (`ETrailingMode`)

| Mode | Description |
|------|-------------|
| `TRAIL_NONE` | No trailing |
| `TRAIL_PSAR` | PSAR dot trailing with TF-based cushion |
| `TRAIL_FRACTAL` | Fractal-based trailing |
| `TRAIL_PSAR_FLIP_EXIT` | Close position on PSAR flip |
| `TRAIL_FIXED_PIPS` | Fixed pip distance trailing |
| `TRAIL_BREAKEVEN` | Move to breakeven then trail |
| `TRAIL_PROFIT_PERCENT` | Trail after profit % threshold |

---

## TF-Based Cushions

### Overview
Cushions automatically scale with timeframe to provide appropriate noise protection.

### SL Cushion (`GetRecommendedInitialSlCushionPips`)

| Timeframe | Standard | JPY pairs |
|-----------|----------|-----------|
| M1        | 2 pips   | 3 pips    |
| M5        | 3 pips   | 5 pips    |
| M15       | 5 pips   | 8 pips    |
| M30       | 7 pips   | 12 pips   |
| H1        | 10 pips  | 15 pips   |
| H4        | 15 pips  | 25 pips   |
| D1        | 25 pips  | 40 pips   |

### Trail Cushion (`GetRecommendedTrailPsarCushionPips`)

| Timeframe | Standard | JPY pairs |
|-----------|----------|-----------|
| M1        | 1 pip    | 2 pips    |
| M5        | 2 pips   | 3 pips    |
| M15       | 3 pips   | 5 pips    |
| M30       | 5 pips   | 7 pips    |
| H1        | 7 pips   | 10 pips   |
| H4        | 10 pips  | 15 pips   |
| D1        | 15 pips  | 25 pips   |

### BE Buffer (`GetTFBasedCushion`)

| Timeframe | Cushion |
|-----------|---------|
| M1        | 3 pips  |
| M5        | 3 pips  |
| M15       | 5 pips  |
| M30       | 8 pips  |
| H1        | 10 pips |
| H4        | 15 pips |
| D1        | 25 pips |

### Functions
```cpp
double GetTFBasedCushion(ENUM_TIMEFRAMES tf);         // Generic cushion (BE buffer)
double GetRecommendedInitialSlCushionPips();          // SL cushion (current TF + JPY-aware)
double GetRecommendedTrailPsarCushionPips();          // Trail cushion (current TF + JPY-aware)
```

### Usage
Cushions are auto-set in `InitializeConfig()` before preset application:
```cpp
Settings.SL_PsarPipsCushion    = GetRecommendedInitialSlCushionPips();
Settings.SL_SwingPipsCushion   = GetRecommendedInitialSlCushionPips();
Settings.PSAR_TrailPipsCushion = GetRecommendedTrailPsarCushionPips();
Settings.RRM_BE_BufferPips     = GetTFBasedCushion(Period());
```

**No user input required.** Presets may override for strategy-specific optimization.

### Applied To
- PSAR SL cushion (`SL_MODE_PSAR_DOT`)
- Swing SL cushion (`SL_MODE_SWING`)
- PSAR trailing cushion (`TRAIL_PSAR`)
- Breakeven buffer (RRM BE modes)

### NOT Applied To
- Fixed SL distance (`Inp_SL_FixedPips` — user defines strategy parameter)
- Fixed TP distance (`Inp_FixedTPPips` — user defines strategy parameter)
- RR ratio (`Inp_RRRatio` — fixed relationship, e.g., 2:1)

---

## Legacy Settings REMOVED (v1.03)

- ❌ `Inp_SL_PsarPipsCushion` — Replaced by `GetRecommendedInitialSlCushionPips()`
- ❌ `Inp_SL_SwingPipsCushion` — Replaced by `GetRecommendedInitialSlCushionPips()`
- ❌ `Inp_PSAR_TrailPipsCushion` — Replaced by `GetRecommendedTrailPsarCushionPips()`
- ❌ `Inp_RRM_BE_BufferPips` — Replaced by `GetTFBasedCushion(Period())`
- ❌ `Use_BE`, `BE_Trig`, `BE_Buff` — Replaced by `BE_Mode` enum system
- ❌ `SL_Mult`, `TP_Mult`, `Trail_Mult` — ATR multipliers not used in RRM
- ❌ `ATR_HardGate` — ATR gate is always hard when `UseATRGate=true`
