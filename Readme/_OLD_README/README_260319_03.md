# RRM_SEA (SimpleEA)

RRM_Simple EA — macOS + Wine + MT5 + **MQL5 ONLY**  
(**no C++**, **no templates**, **no lambdas**, **no static locals**)

## Canonical documentation (current)
All current docs live in `Readme/`:

- `Readme/README_SYSTEM.md` — system architecture & full documentation
- `Readme/README_INDICATORS.md` — indicator and voting pipeline reference
- `Readme/README_EXTENDING.md` — developer guide: how to add custom indicators
- `Readme/README_SEA_RULES.md` — agent ownership, constraints, preset policy
- `Readme/README_SEA_BOOTSTRAP.md` — how to start a new chat and run tasks with SEA agents
- `Readme/README_SEA_AI-AGENTS.md` — SEA Agents v.03 prompts (roles/guardrails/output)

## Legacy / archive
Historical/obsolete documentation is stored in `Legacy/`.  
Do not use it unless explicitly required:

- `Legacy/README_LEGACY.md`

## Quick start (for a new task)
1. Read `Readme/README_SEA_BOOTSTRAP.md`
2. Follow `Readme/README_SEA_RULES.md`
3. Define the task and proceed via the SEA Architect → Specialized Agent workflow

## Python EA vs SimpleEA MQL5 Comparison

### Phase 2 Implementation Status (PR #12)

**COMPLETED** ✅:
- ✅ 3 Bias Modes (Manual, 2-EMA, 4-EMA Phase)
- ✅ Market Phase Detection (TRENDING/EMERGING/UNORDERED)
- ✅ Entry Layer Detection (L1/L2/L3)
- ✅ Phase-Layer Filtering (progressive risk management)
- ✅ Configurable phase confirmation bars

**Target Metrics**:
- Win Rate: 50-55% (approaching Python EA's 55-60%)
- Trade Quality: Reduced false signals in choppy markets
- Configurability: `MinPhaseConfirmBars` tunable per symbol/timeframe

### Layer Detection Equivalence
SimpleEA's STRAT_LAYER_DETECTION replicates Python EA's TrSet pattern logic:

| Feature | Python EA (`rrm_f1_34_its_engine.py`) | SimpleEA MQL5 |
|---------|----------------------------------------|---------------|
| Shallow Pullback | "Ribbon" (EMA1/2) | LAYER_1_WEAK |
| Medium Pullback | "Ghost" (EMA2/3) | LAYER_2_MEDIUM |
| Deep Pullback | "Shark" (EMA3/4) | LAYER_3_STRONG |
| Tolerance | `_is_near()` 1% | `LayerTouchTolerance` 1% |
| Lookback | Multi-bar scan (`TSV_DPB_LOOKBACK`) | Single-bar check (shift=1) |

### Performance Differences
- **Python EA**: 55–60% win rate, 5–8 trades/day (M1 timeframe)
- **SimpleEA**: 35–40% win rate, 2–3 trades/day (same conditions)

**Root Causes:**
1. **Lookback difference**: Python EA scans last N bars for patterns (`TSV_DPB_LOOKBACK`); SimpleEA checks only current bar (shift=1)
2. **Additional filters**: SimpleEA PRESET_RRM includes 7 extra protection gates:
   - Phase confirmation delay (4 bars)
   - Recovery momentum requirement
   - Divergence validation (1.5 pips minimum)
   - HTF alignment (optional)
   - Pullback lookback (20 bars)
3. **Trade-off**: SimpleEA prioritizes quality over quantity (fewer trades, stricter entry rules)

**Tuning for Python EA Parity:**
To increase trade frequency closer to Python EA levels:
- Set `MinPhaseConfirmBars = 2` (faster phase detection)
- Set `Emerging_AllowWeakTrades = true` (allow L1 in EMERGING phase)
- Set `RequireRecoveryMomentum = false` (accept more pullback patterns)
- Consider implementing multi-bar lookback (future enhancement)

See `Readme/README_SYSTEM.md` STRAT_LAYER_DETECTION section for full details.

## System Analysis Report

After each backtest, SimpleEA automatically outputs comprehensive performance metrics
immediately following the rejection statistics.

### Trade Performance
```
================================================================
  TRADE PERFORMANCE
================================================================
Total Trades         : 45
  ├─ Long            : 22 (48.9%)
  └─ Short           : 23 (51.1%)

Win Rate             : 62.2% (28W / 17L)
  ├─ Long win rate   : 59.1% (13/22)
  └─ Short win rate  : 65.2% (15/23)

Profit Factor        : 2.34
  ├─ Gross profit    : $4,680.00
  └─ Gross loss      : -$2,000.00

Average Trade        : $59.56
  ├─ Average win     : $167.14
  └─ Average loss    : -$117.65

Best Trade           : $420.50
Worst Trade          : -$245.80

Consecutive Wins     : 7 (max)
Consecutive Losses   : 4 (max)
================================================================
```

### Risk Analysis
```
================================================================
  RISK ANALYSIS
================================================================
Starting Balance     : $10,000.00
Ending Balance       : $11,195.00
Net Profit           : $1,195.00 (+11.95%)

Maximum Drawdown     : 8.5% ($850.00)
  ├─ Absolute        : $850.00
  └─ Relative        : 8.5%

Recovery Factor      : 1.41 (Net Profit / Max DD)
Risk-Reward Ratio    : 1.42 (Avg Win / Avg Loss)
================================================================
```

### Signal Efficiency
```
================================================================
  SIGNAL EFFICIENCY ANALYSIS
================================================================
Signal Generation
  ├─ Total bars evaluated    : 1,606
  ├─ Signals confirmed       : 370 (23.04%)
  ├─ Signals rejected        : 1,236 (76.96%)
  └─ Avg bars between signals: 4.3 bars

Signal-to-Trade Conversion
  ├─ Signals confirmed       : 370
  ├─ Trades executed         : 45 (12.2% conversion)
  └─ Signals filtered out    : 325 (87.8%)

Component Efficiency (Pass Rate Among Bias-Confirmed Bars)
  ├─ Bias detection          : 63.6% (1,022 / 1,606 bars)
  └─ When bias ≠ 0:
      ├─ PSAR         : 36.2% (370 / 1,022)   ← if enabled
      └─ MACD         : 55.3% (565 / 1,022)   ← if enabled

Combined Efficiency          : 23.0% (signals / total bars)
================================================================
```

The **Component Efficiency** section is **dynamic** — it lists only enabled indicators
(controlled by `Inp_Ind_XXX_Enabled` input flags). Disabled indicators are not shown.

**Implementation notes:**
- Trade data queried from MT5 history via `HistorySelect()` at `OnDeinit`
- Maximum drawdown tracked every tick via peak-equity calculation
- In Strategy Tester, uses `TesterStatistics()` for balance/drawdown; falls back to manual tracking in live
- All three sections are graceful when no trades were executed



SimpleEA supports 4 debug verbosity levels controlled by `Inp_DebugLevel`:

| Level | Name | Per-bar output | Log size (year) | Use case |
|-------|------|----------------|-----------------|----------|
| 0 | `DEBUG_SILENT` | None | ~100 lines | Optimization runs |
| 1 | `DEBUG_SUMMARY` | 1-2 lines (result only) | ~3,000 lines | Long-term tests |
| 2 | `DEBUG_INDICATORS` | 20-30 lines (pass/fail summary) | ~15,000 lines | Multi-indicator analysis |
| 3 | `DEBUG_FULL` | 50+ lines (all diagnostics) | ~75,000 lines | Development/debugging |

**Configuration:**
```mql5
input bool        Inp_DebugFlow  = true;           // Master on/off switch
input EDebugLevel Inp_DebugLevel = DEBUG_SUMMARY;  // Verbosity level
```

**Backward compatibility:**
- `Inp_DebugFlow = false` → Forces `DEBUG_SILENT` regardless of `Inp_DebugLevel`
- `Inp_DebugFlow = true` → Uses `Inp_DebugLevel` setting
- `Inp_DebugLevel = DEBUG_FULL` → Identical to old `Inp_DebugFlow = true` behaviour

**Recommendations:**
- Short tests (<100 bars): `DEBUG_INDICATORS` or `DEBUG_FULL`
- Long tests (year+): `DEBUG_SUMMARY`
- Optimization runs: `DEBUG_SILENT`