# RRM_SEA Documentation Index

This repository exploration has generated comprehensive documentation files to help you understand the codebase structure and functionality.

---

## 📄 Documentation Files (NEW)

### 1. **QUICK_REFERENCE.md** (242 lines)
**Best for:** Quick lookups and cheat sheet
- File locations and line counts
- Key enum definitions (EStrategyPreset, EAutoStrategy, EMarketPhase, EEntryLayer)
- PRESET_RRM configuration summary (protection features, exit strategy, risk limits)
- Signal processing pipeline (9-step overview)
- Layer detection mechanism
- Main input parameters (Zone 2 - always editable)
- RRM mode detection by timeframe
- EMA configuration
- Policy A gates (always respected)
- Hidden/disabled features
- File structure summary
- Default parameters table

**Use this when you need:** Quick answers, configuration comparisons, input parameter defaults

---

### 2. **EXPLORATION_REPORT.md** (854 lines)
**Best for:** In-depth understanding with code snippets
- Complete directory structure
- Full enum definitions (EStrategyPreset, EMarketPhase, EEntryLayer, EAutoStrategy)
- ST_Settings struct with 100+ fields
- SEA_SignalEngine.mqh detailed analysis
  - Main GetDirection() 9-step pipeline
  - Entry Layer Detection function (line 2457)
  - AutoStrat Signal Generation (line 1797)
  - Market Phase Diagnostics
- PRESET_RRM_ATR complete definition
- PRESET_RRM complete definition (Strict No-ATR Enhanced Protection)
- SimpleEA_v1-03.mq5 structure
  - Header and includes
  - Global state variables
  - Two-Phase Entry system
  - RRM Drawdown Protection
- Complete input parameters (Zone 1-3C with descriptions)
- Architecture points summary

**Use this when you need:** Complete understanding, detailed code context, configuration documentation

---

### 3. **CODE_EXCERPTS.md** (541 lines)
**Best for:** Copy-paste reference for key code sections
- EAutoStrategy enum (3 options)
- EMarketPhase enum (3 options)
- EEntryLayer enum (4 options)
- EStrategyPreset enum (8 presets)
- ST_Settings struct (key fields only)
- DetectEntryLayer() full function (line 2457)
- AutoStrat Signal Generation (line 1797)
- PRESET_RRM full definition (174 lines)
- Main EA global variables
- Key input parameters (organized by Zone)
- Summary table of all key items

**Use this when you need:** To copy code, reference function signatures, understand specific implementations

---

## 🎯 Quick Navigation

### If You Need To Know...

**"What is PRESET_RRM?"**
→ See QUICK_REFERENCE.md → "PRESET_RRM Configuration Summary"
→ Or EXPLORATION_REPORT.md → "5. PRESET_RRM DEFINITION"
→ Or CODE_EXCERPTS.md → "8. PRESET_RRM Definition"

**"How does layer detection work?"**
→ See QUICK_REFERENCE.md → "Layer Detection"
→ Or EXPLORATION_REPORT.md → "4. SEA_SignalEngine.mqh"
→ Or CODE_EXCERPTS.md → "6. DetectEntryLayer() Function"

**"What are the input parameters?"**
→ See QUICK_REFERENCE.md → "Main Input Parameters"
→ Or EXPLORATION_REPORT.md → "7. INPUT PARAMETERS"
→ Or CODE_EXCERPTS.md → "10. Key Input Parameters"

**"How is the entry signal generated?"**
→ See QUICK_REFERENCE.md → "Signal Processing Pipeline"
→ Or EXPLORATION_REPORT.md → "4. SEA_SignalEngine.mqh"
→ Or CODE_EXCERPTS.md → "7. AutoStrat Signal Generation"

**"What's the default configuration?"**
→ See QUICK_REFERENCE.md → "Default Parameters Summary"
→ Or EXPLORATION_REPORT.md → "8. Summary: Key Architecture Points"

---

## �� File Summary

| File | Lines | Focus | Best Used For |
|------|-------|-------|---------------|
| QUICK_REFERENCE.md | 242 | Overview | Quick answers, cheat sheet |
| EXPLORATION_REPORT.md | 854 | Complete | In-depth understanding |
| CODE_EXCERPTS.md | 541 | Code snippets | Implementation reference |
| DOCUMENTATION_INDEX.md | This file | Navigation | Finding what you need |

---

## 🔍 Repository Structure

### Main Source Files

**SEA_Config.mqh** (1,353 lines)
- EStrategyPreset enum (line 12)
- EMarketPhase enum (line 59)
- EEntryLayer enum (line 65)
- EAutoStrategy enum (~line 85)
- ST_Settings struct
- All input parameters (lines 554+)

**SEA_SignalEngine.mqh** (2,520 lines)
- GetDirection() main 9-step pipeline (line 1528)
- AutoStrat signal generation (line 1797)
- DetectEntryLayer() function (line 2457)
- Phase detection logic
- Market phase diagnostics

**SEA_Presets.mqh** (36,200 bytes)
- PRESET_RRM_ATR definition (lines 574-650)
- PRESET_RRM definition (lines 674-850)
- Preset application logic

**SimpleEA_v1-03.mq5** (39,100 bytes)
- Main EA file
- Global state and module objects
- Two-phase entry system (TS/TE)
- RRM drawdown protection

---

## 🎓 Key Concepts Explained

### PRESET_RRM (The Default)
- **Strict No-ATR Trend Pullback with Enhanced Protection**
- Uses EMA3(34) / EMA4(89) for bias
- Entry via STRAT_PAIR_CROSS (EMA crossover)
- Voting: ALL mode (EMA, MACD, CCI, PSAR - all 4 must agree)
- ATR completely disabled (MinATR=0, MaxATR=0)
- Phase/Layer detection enabled for additional filtering
- 4-bar phase confirmation, recovery momentum required
- Swing-based SL, PSAR-based trailing
- Max 3 concurrent trades, 4% portfolio risk limit

### Two-Phase Entry System
**Phase 1 (TS)**: Trade Signal generated at bar close (shift=1)
- Evaluated when bar completes
- Saves signal state (direction, votes, bias)

**Phase 2 (TE)**: Trade Execution on next bar first tick (shift=0)
- Validates live conditions
- If still valid, executes trade
- Prevents race conditions between signal and execution

### Layer Detection (Passive)
- **LAYER_3_STRONG**: Price touches EMA3 or EMA4 zone (deep pullback)
- **LAYER_2_MEDIUM**: Price touches EMA2 or EMA3 zone (medium pullback)
- **LAYER_1_WEAK**: Price touches EMA1 or EMA2 zone (shallow pullback)
- Tolerance: Configurable pixels
- Currently: Diagnostic only (logs data, no filtering yet)

### Market Phases (Active in PRESET_RRM)
- **PHASE_UNORDERED**: EMAs crossed/mixed (blocked - no trades)
- **PHASE_EMERGING**: EMA4 between EMA2 and EMA3 (forming trend, L3 blocked)
- **PHASE_TRENDING**: Fully stacked trend (all layers allowed)

### Policy A Gates (Always Respected)
- Spread filter (Inp_MaxSpreadPips)
- Time filter (session hours)
- News filter (calendar events)
- HTF filter (higher timeframe confirmation)
- UI settings (diagnostics, reporting)

These are user-controlled even when presets are active.

---

## 🚀 Quick Start

### To Understand the System:
1. Start with **QUICK_REFERENCE.md** - get the overview
2. Read **EXPLORATION_REPORT.md** sections 1-3 - understand structure
3. Read **EXPLORATION_REPORT.md** section 8 - key architecture points

### To Implement Changes:
1. Refer to **CODE_EXCERPTS.md** for exact code
2. Check **QUICK_REFERENCE.md** for configuration values
3. Verify input parameters in **EXPLORATION_REPORT.md** section 7

### To Debug Issues:
1. Check **QUICK_REFERENCE.md** "Signal Processing Pipeline"
2. Trace through **CODE_EXCERPTS.md** "7. AutoStrat Signal Generation"
3. Review preset settings in **EXPLORATION_REPORT.md** section 5

---

## 📝 Notes

- All enums and structs are in **SEA_Config.mqh**
- All signal processing in **SEA_SignalEngine.mqh**
- All preset definitions in **SEA_Presets.mqh**
- Main EA file is **SimpleEA_v1-03.mq5**
- Default preset is **PRESET_RRM** (strict no-ATR)
- Default entry strategy is **STRAT_PAIR_CROSS** (EMA crossover)
- Default voting is **ALL mode** (all indicators must agree)
- Layer/Phase detection is **enabled in PRESET_RRM** but **passive** (diagnostic only)

---

## 📞 Documentation Generated

Created: 2024-03-06
Source: RRM_SEA repository at /home/runner/work/RRM_SEA/RRM_SEA
Files analyzed:
- SEA_Config.mqh (1,353 lines)
- SEA_SignalEngine.mqh (2,520 lines)
- SEA_Presets.mqh (36.2 KB)
- SimpleEA_v1-03.mq5 (39.1 KB)
- Plus modules: SEA_TradeExecutor.mqh, SEA_UI.mqh, SEA_Reporting.mqh

