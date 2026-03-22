# Config Zones Reference

## Overview

SimpleEA inputs are organized into zones:

- **ZONE 2** — Operator gates (spread, ATR, time, news)
- **ZONE 3A** — Pipeline config (bias, indicators, exit management)
- **ZONE 3C** — Pair-specific spread limits

---

## ZONE 3A.9: Exit Management

### Stop Loss Configuration

**User Inputs (Strategy Parameters):**
- `Inp_SLMode` — How to calculate SL distance
  - `SL_MODE_FIXED_PIPS` — User-defined pip distance (`Inp_SL_FixedPips`)
  - `SL_MODE_PSAR_DOT` — PSAR level + TF-based cushion (auto)
  - `SL_MODE_SWING` — Swing high/low + TF-based cushion (auto)
  - `SL_MODE_FRACTAL` — Fractal level + TF-based cushion (auto)
  - `SL_MODE_PERCENT` — % of entry price (`Inp_SLPercent`)

**No Cushion Inputs Required:**
Cushions auto-adjust by timeframe (M15=5 pips, H1=10 pips, H4=15 pips).

### Take Profit Configuration

**User Inputs (Strategy Parameters):**
- `Inp_TPMode` — How to calculate TP distance
  - `TP_MODE_FIXED_PIPS` — User-defined pip distance (`Inp_FixedTPPips`)
  - `TP_MODE_RR` — Risk:Reward ratio (`Inp_RRRatio`, e.g., 2.0 = 1:2 RR)
  - `TP_MODE_FRACTAL` — Next fractal level (market-defined)
  - `TP_MODE_PSAR_FLIP` — Exit on PSAR flip (no fixed TP)
  - `TP_MODE_NONE` — No TP (rely on trailing stop)

### Breakeven Configuration (RRM)

**RRM BE Mode (`Inp_BE_Mode`):**
- `BE_MODE_OFF` — Disabled
- `BE_MODE_TP_PROGRESS_PCT` — Trigger at % progress toward TP
- `BE_MODE_R_MULTIPLE` — Trigger at R-multiple

**Buffer:** Auto-set by TF (no input required).

### Trailing Stop Configuration

**Cushion:** Auto-set by TF for PSAR trailing (no input required).

### Legacy Settings REMOVED (v1.03)
- ❌ `Inp_SL_PsarPipsCushion` — Replaced by `GetRecommendedInitialSlCushionPips()`
- ❌ `Inp_SL_SwingPipsCushion` — Replaced by `GetRecommendedInitialSlCushionPips()`
- ❌ `Inp_PSAR_TrailPipsCushion` — Replaced by `GetRecommendedTrailPsarCushionPips()`
- ❌ `Inp_RRM_BE_BufferPips` — Replaced by `GetTFBasedCushion(Period())`
- ❌ `Use_BE`, `BE_Trig`, `BE_Buff` — Replaced by `BE_Mode` enum system
- ❌ `SL_Mult`, `TP_Mult`, `Trail_Mult` — ATR multipliers not used in RRM
- ❌ Adaptive ATR/SL/TP/Cushion system — Replaced by TF functions + pair spread detection

---

## ZONE 3C: Pair-Specific Spread Limits

### Purpose
Auto-detect maximum spread based on symbol type. Different instruments have inherently different spreads.

### Configuration
- `Inp_Adaptive_PairType` — AUTO (auto-detect) or manual override
- `Inp_Adaptive_Spread_Major` — Max spread for majors (default: 2.0 pips)
- `Inp_Adaptive_Spread_Minor` — Max spread for minors (default: 4.0 pips)
- `Inp_Adaptive_Spread_Exotic` — Max spread for exotics (default: 10.0 pips)
- `Inp_Adaptive_Spread_Gold` — Max spread for gold (default: 5.0 pips)
- `Inp_Adaptive_Spread_Crypto` — Max spread for crypto (default: 50.0 pips)

### Example
```
Symbol = "EURUSD" → Detected as MAJOR → MaxSpread = 2.0 pips
Symbol = "XAUUSD" → Detected as GOLD  → MaxSpread = 5.0 pips
Symbol = "BTCUSD" → Detected as CRYPTO → MaxSpread = 50.0 pips
```

### What's NOT Adaptive
- **ATR gates** — User sets appropriate values in ZONE 2A
- **SL/TP distances** — Market-defined (PSAR/Swing/Fractal) or user-defined (Fixed/RR)
- **Cushions** — TF-based auto-calculation (see [TF-Based Cushions](README_EXIT_MANAGEMENT.md#tf-based-cushions))

---

## Preset Policy

| Preset | ZONE 3A.9 | ZONE 3C |
|--------|-----------|---------|
| `PRESET_CUSTOM` | User controls | User controls |
| `PRESET_MA` | Preset overrides | User controls |
| `PRESET_RRM` | Preset overrides exits | User controls |
| `PRESET_TEST` | Preset sets safe defaults | User controls |

See [README_SYSTEM.md](README_SYSTEM.md) for full preset documentation.
