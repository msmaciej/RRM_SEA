# RRM_SEA Quick Reference Guide

## File Locations

| File | Lines | Purpose |
|------|-------|---------|
| `SEA_Config.mqh` | 1,353 | Configuration, enums (EStrategyPreset, EMarketPhase, EEntryLayer, EAutoStrategy), ST_Settings struct, input parameters |
| `SEA_SignalEngine.mqh` | 2,520 | Signal processing (GetDirection 9-step pipeline), phase/layer detection, entry signal generation |
| `SEA_Presets.mqh` | 36,200 | Preset definitions (PRESET_RRM_ATR and PRESET_RRM) |
| `SimpleEA_v1-03.mq5` | 39,100 | Main EA file with includes and global state |

---

## Key Enums

### EStrategyPreset (8 options)
- **PRESET_RRM** (DEFAULT) - Strict no-ATR trend pullback with enhanced protection
- **PRESET_RRM_ATR** - RRM with ATR voting (optimized)
- PRESET_CUSTOM, PRESET_MA_BENCHMARK, PRESET_TREND_REVERSAL, PRESET_TREND_SCALP, PRESET_TREND_SWING, PRESET_RANGE_GRID

### EAutoStrategy (3 options)
- **STRAT_PAIR_CROSS** - EMA crossover (RRM default)
- STRAT_SINGLE_SLOPE - Single EMA direction
- STRAT_PRICE_CROSS - Price vs EMA

### EMarketPhase (3 options)
- PHASE_UNORDERED - No trade (EMAs crossed/mixed)
- PHASE_EMERGING - EMA4 between EMA2 and EMA3
- PHASE_TRENDING - Fully stacked trend

### EEntryLayer (4 options)
- LAYER_NONE - No pullback detected
- LAYER_1_WEAK - EMA1/EMA2 touch (shallow)
- LAYER_2_MEDIUM - EMA2/EMA3 touch (medium)
- LAYER_3_STRONG - EMA3/EMA4 touch (deep)

---

## PRESET_RRM Configuration Summary

### Entry Strategy
- **Bias**: EMA3(34) fast / EMA4(89) slow (uses EMA3/EMA4 crossover)
- **AutoStrat**: STRAT_PAIR_CROSS (EMA crossover)
- **Indicators Voted**: EMA, MACD, CCI, PSAR (4 votes, ALL mode = all must agree)

### Protection Features
1. **4-bar phase confirmation** (PHASE_UNORDERED blocked, PHASE_EMERGING/TRENDING allowed)
2. **Recovery momentum requirement** (bullish/bearish candle confirmation)
3. **20-bar pullback lookback** (M1/M5) to verify volatility
4. **1.5 pips min EMA divergence** (deep pullback required)
5. **Stricter EMERGING phase**: L1, L2 allowed; L3 blocked
6. **Multi-layer pullback detection** (passive observation)
7. **Swing-based SL** (not ATR)
8. **PSAR-based trailing** (adaptive cushions by TF/JPY)
9. **Max 3 concurrent trades** with 4% portfolio risk limit
10. **ATR fully disabled** (MinATR=0, MaxATR=0)

### Exit Strategy
- **SL Mode**: SL_SWING_HIGHLOW (swing high/low detection)
- **TP Multiplier**: 3.0 R-multiple
- **Trailing**: TRAIL_PSAR with automatic cushion adjustment
- **Breakeven**: Enabled at 1.0 R-multiple (BE_MODE_R_MULTIPLE)

### Risk Limits
- **MaxTotalRisk**: 4.0% (portfolio level)
- **MaxOpenTrades**: 3
- **CountBEasZeroRisk**: true (BE trades don't count toward risk)

---

## Signal Processing Pipeline (GetDirection)

```
1. PRE-FILTERS       → Spread, ATR, time, news gates
2. BIAS CALC         → EMA3/EMA4 direction (or phase-based)
3. AUTOSTRAT SIGNAL  → Crossover detection or continuation
4. SIGNAL-BIAS MATCH → Entry signal must align with bias
5. HTF FILTER        → Higher timeframe confirmation (optional)
6. RRM GATES         → Pullback/momentum/recovery checks
7. VOTE BYPASS       → Skip voting if threshold <= 1
8. INDICATOR VOTING  → EMA, MACD, CCI, PSAR consensus
9. FINAL DECISION    → Accept if votes >= 4 (ALL mode)
```

---

## Layer Detection (DetectEntryLayer, Line 2457)

```mql5
EEntryLayer DetectEntryLayer(const int v_shift = 1)
{
   if(!m_settings.EnableLayerDetection) return LAYER_NONE;
   
   // Layer 3: price within tolerance of EMA3 or EMA4 → STRONG
   // Layer 2: price within tolerance of EMA2 or EMA3 → MEDIUM
   // Layer 1: price within tolerance of EMA1 or EMA2 → WEAK
   // Else: LAYER_NONE
}
```

**Current Status**: Passive detection only (logs to diagnostics, no filtering yet)

---

## Main Input Parameters (Zone 2 - Always Editable)

| Parameter | Default | Purpose |
|-----------|---------|---------|
| `Inp_MaxSpreadPips` | 3.0 | Operator gate: max spread |
| `Inp_MinATRPips` | 0.0 | Operator gate: min ATR (0=off) |
| `Inp_MaxATRPips` | 20.0 | Operator gate: max ATR (0=off) |
| `Inp_UseTime` | false | Enable session/time filter |
| `Inp_StartHour` / `Inp_EndHour` | 8/20 | Session hours (broker time) |
| `Inp_UseNews` | false | Enable news filter |
| `Inp_UseHTF` | false | Enable HTF trend filter |
| `Inp_UI_ShowCockpitPanel` | true | Show cockpit panel |
| `Inp_PrintEffectiveConfig` | true | Print settings on init |
| `Inp_DebugFlow` | true | Enable diagnostic logging |

---

## RRM Mode Detection (Timeframe-Based)

When `Inp_RRM_Mode = RRM_AUTO_BY_TF`:
- **SCALP MODE**: M1, M5, M15 → tighter parameters
  - BiasFastID=2 (EMA3), BiasSlowID=3 (EMA4)
  - MaxSpread: 2.0 pips
- **SWING MODE**: H1+ → standard parameters
  - BiasFastID=2 (EMA3), BiasSlowID=3 (EMA4)
  - MaxSpread: 4.0 pips

---

## EMA Configuration (PRESET_RRM Default)

```
EMA1(5)  - Entry timing (price cross)
EMA2(13) - Mid-term support/resistance
EMA3(34) - Bias Fast (crossover detection)
EMA4(89) - Bias Slow (trend confirmation)
```

---

## Policy A Gates (Always Respected)

These user-controlled gates apply EVEN when presets are active:

1. **Spread Filter**: `Inp_MaxSpreadPips`
2. **Time Filter**: `Inp_UseTime`, `Inp_StartHour`, `Inp_EndHour`
3. **News Filter**: `Inp_UseNews`, `Inp_NewsPre`, `Inp_NewsPost`
4. **HTF Filter**: `Inp_UseHTF`, `Inp_HtfPeriod`, `Inp_HtfEmaPeriod`
5. **UI Settings**: Status panel, cockpit, diagnostics

**Note**: MinATR/MaxATR are NOT restored in PRESET_RRM (kept at 0 for strict mode)

---

## Hidden Features (Disabled by Default)

1. **Phase Detection** (`PhaseDetectionEnabled=true` in PRESET_RRM)
   - Detects UNORDERED/EMERGING/TRENDING phases
   - Blocks trades in UNORDERED phase
   - Requires 4-bar confirmation

2. **Layer Detection** (`EnableLayerDetection=true` in PRESET_RRM)
   - Identifies pullback depth (L1/L2/L3)
   - Phase-specific permissions:
     - EMERGING: L1, L2 allowed; L3 blocked
     - TRENDING: all allowed

3. **Multi-Layer Pullback** (`Gate_UseMultiLayer=true` in PRESET_RRM)
   - Cascading EMA pullback detection
   - Recovery momentum requirement

4. **Adaptive Settings** (`Inp_Adaptive_*`)
   - Auto-scales spread, ATR, SL, TP, trail by pair type and timeframe
   - Supports JPY pairs, exotic pairs, crypto, gold

---

## To Enable Advanced Features

**In PRESET_CUSTOM**:
- Set `Inp_RRM_EnableInCustom = true` to use RRM logic
- All other inputs are fully respected

**Phase Detection**:
- Set `Inp_Gate_UseMultiLayer = true` (enables layer detection)
- Already enabled in PRESET_RRM

**Admin Override Mode**:
- Set `Inp_AdminOverridePreset = true`
- Can then override EMA periods, vote threshold, etc.

---

## File Structure Summary

### Module Architecture
```
SimpleEA_v1-03.mq5 (main EA)
  ├── SEA_Config.mqh (enums, struct, inputs)
  ├── SEA_Presets.mqh (preset logic)
  ├── SEA_SignalEngine.mqh (signal processing)
  ├── SEA_TradeExecutor.mqh (trade execution)
  ├── SEA_UI.mqh (UI/panels)
  └── SEA_Reporting.mqh (CSV reporting)
```

### Two-Phase Entry System
- **Phase 1 (TS)**: Trade Signal evaluated at bar close (shift=1)
- **Phase 2 (TE)**: Trade Execution evaluated on next bar first tick (shift=0)
- Decouples signal generation from execution to avoid race conditions

---

## Default Parameters Summary

| Setting | Value | Notes |
|---------|-------|-------|
| Preset | PRESET_RRM | Enhanced RRM protection |
| Entry Strategy | STRAT_PAIR_CROSS | EMA crossover |
| Bias | EMA3(34) / EMA4(89) | Deep, stable bias |
| Voting | ALL mode | All 4 indicators must agree |
| Vote Threshold | 4 | EMA, MACD, CCI, PSAR |
| Max Spread | 3.0 pips (user gate) / 2-4 (preset) | Policy A: user controls |
| ATR | Disabled (MinATR=0, MaxATR=0) | Strict mode only |
| Max Trades | 3 concurrent | Portfolio protection |
| Max Risk | 4.0% total | Portfolio-level limit |
| SL Mode | SL_SWING_HIGHLOW | Swing-based, not ATR |
| TP Multiple | 3.0 R | Risk-based TP |
| Trail Mode | TRAIL_PSAR | Parabolic SAR trailing |

---

## Documentation Files

- **EXPLORATION_REPORT.md** (854 lines) - Full detailed analysis with code examples
- **QUICK_REFERENCE.md** (this file) - Quick lookup guide
- **README.md** - Repository overview

