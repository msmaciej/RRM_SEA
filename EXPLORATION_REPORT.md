input int            Inp_P_MacdFast       = 8;
input int            Inp_P_MacdSlow       = 13;
input int            Inp_P_MacdSig        = 8;
input int            Inp_MacdFreshBars    = 3;
input double         Inp_MacdSlopeMin     = 0.00001;
input group "═══ 📊 Indicator: RSI ═══"
input bool     Inp_Ind_Rsi_Enabled  = false;
input int      Inp_Ind_Rsi_Weight   = 1;
input ERsiMode Inp_Ind_Rsi_Mode     = RSI_FILTER_EXTREME;
input int      Inp_Ind_Rsi_Period   = 14;
input double   Inp_Ind_Rsi_OB       = 70.0;
input double   Inp_Ind_Rsi_OS       = 30.0;
input group "═══ 📊 Indicator: CCI ═══"
input bool    Inp_Ind_Cci_Enabled = true;
input int     Inp_Ind_Cci_Weight  = 1;
input ECciMode Inp_Ind_Cci_Mode   = CCI_TREND_ZERO;
input int     Inp_Ind_Cci_Period  = 14;
// ... Additional indicators (MFI, Stochastic, Bollinger, PSAR, Pattern123, Ross)
```
**STEP 9: Risk & Execution**
```mql5
input group "--- ℹ️ Step 9: Risk & Execution ---"
input double Inp_RiskPercent = 2.0;    // Risk per trade (%)
input group "--- ℹ️ Step 9 · Initial SL Placement ---"
input ESlPlacementMode Inp_SL_PlacementMode  = SL_SWING_HIGHLOW;
input double           Inp_SL_Mult           = 1.5;
input double           Inp_SL_PsarPipsCushion = 5.0;
input double           Inp_SL_SwingPipsCushion = 10.0;
input double           Inp_SL_FixedPips      = 20.0;
input group "--- ℹ️ Step 9 · TP & Breakeven ---"
input double Inp_TP_Mult  = 3.0;
input bool   Inp_Use_BE   = false;
input double Inp_BE_Trig  = 1.0;
input double Inp_BE_Buff  = 0.1;
input group "--- ℹ️ Step 9 · Trailing Stop ---"
input ETrailingMode Inp_TrailMode                = TRAIL_PSAR;
input double        Inp_Trail_Mult               = 3.0;
input EPsarTrailCushionMode Inp_PSAR_TrailCushionMode = PSAR_CUSHION_PIPS;
input double        Inp_PSAR_TrailPipsCushion    = 5.0;
input double        Inp_PSAR_TrailCushionATR     = 0.2;
```
### ZONE 3C: ADAPTIVE SETTINGS (Auto-scale by Pair & Timeframe)
```mql5
input group "══════════ 🔧 ZONE 3C: ADAPTIVE SETTINGS ══════════"
input group "═══ 🔧 Adaptive: Pair Type Detection ═══"
input EPairType Inp_Adaptive_PairType = PAIR_TYPE_AUTO;
input group "═══ 🔧 Adaptive: Spread Limits (by pair type) ═══"
input double Inp_Adaptive_Spread_Major  = 2.0;
input double Inp_Adaptive_Spread_Minor  = 4.0;
input double Inp_Adaptive_Spread_Exotic = 10.0;
input double Inp_Adaptive_Spread_Gold   = 5.0;
input double Inp_Adaptive_Spread_Crypto = 50.0;
input group "═══ 🔧 Adaptive: ATR Limits (by timeframe) ═══"
input ETFScaling Inp_Adaptive_ATR_Mode  = TF_SCALE_AUTO;
input double     Inp_Adaptive_ATR_Min_Base = 5.0;
input double     Inp_Adaptive_ATR_Max_Base = 20.0;
input group "═══ 🔧 Adaptive: SL/TP Distance (by timeframe) ═══"
input double Inp_Adaptive_SL_Base = 20.0;
input double Inp_Adaptive_TP_Base = 40.0;
input bool   Inp_Adaptive_UseSL   = false;
input bool   Inp_Adaptive_UseTP   = false;
input group "═══ 🔧 Adaptive: Trail Stop Cushion (by timeframe) ═══"
input double Inp_Adaptive_TrailCushion_Base = 5.0;
input bool   Inp_Adaptive_UseTrailCushion   = false;
input group "═══ 🔧 Adaptive: PSAR Trail Cushion (by volatility) ═══"
input double Inp_Adaptive_PsarCushion_Pips = 3.0;
input bool   Inp_Adaptive_PsarUseATR        = false;
input double Inp_Adaptive_PsarATR_Multiplier = 0.5;
```
### ZONE 3B: ADMIN OVERRIDE (For Testing)
```mql5
input group "══════════ 🔓 ZONE 3B: ADMIN OVERRIDE ══════════"
input bool Inp_AdminOverridePreset = false;  // Unlock preset parameters
// ... Override inputs for AutoStrat, EMA periods, vote threshold, etc.
```
---
## 8. SUMMARY: Key Architecture Points
### Default Configuration (PRESET_RRM)
- **Preset**: `PRESET_RRM` (Enhanced Protection)
- **Bias**: `BIAS_AUTO` or `BIAS_AUTO_PHASE`
- **AutoStrat**: `STRAT_PAIR_CROSS` (EMA crossover)
- **Bias EMAs**: EMA3(34) fast / EMA4(89) slow
- **Entry Strategy**: Pair crossover (not single slope or price cross)
- **ATR**: Fully disabled (MinATR=0, MaxATR=0, no ATR voting)
- **Voting**: ALL mode (all enabled indicators must agree)
- **Indicators**: EMA, MACD, CCI, PSAR (4 votes required)
- **Phase Detection**: Enabled (UNORDERED, EMERGING, TRENDING)
- **Layer Detection**: Enabled (LAYER_1_WEAK, LAYER_2_MEDIUM, LAYER_3_STRONG)
- **Exit**: Swing-based SL with PSAR trailing
### Key Protection Features (PRESET_RRM)
1. **4-bar phase confirmation** (was 3)
2. **Recovery momentum requirement** (bullish/bearish candle)
3. **20-bar pullback lookback** (M1/M5)
4. **1.5 pips min EMA divergence** (was 0.5)
5. **Stricter EMERGING layer filtering** (L3 blocked)
6. **Multi-layer pullback detection** enabled
7. **Swing-based SL** (not ATR)
8. **PSAR-based trailing** with adaptive cushions
9. **Max 3 concurrent trades** with 4% portfolio risk limit
### Layer Detection Mechanism
- **Layer 3 (STRONG)**: Price within tolerance of EMA3 or EMA4 → deep pullback
- **Layer 2 (MEDIUM)**: Price within tolerance of EMA2 or EMA3 → medium pullback
- **Layer 1 (WEAK)**: Price within tolerance of EMA1 or EMA2 → shallow pullback
- Tolerance: `LayerTouchTolerancePips` (default controlled by preset)
- Passive detection: logs to diagnostics, doesn't filter entries (yet)
### AutoStrat Signal Generation (STRAT_PAIR_CROSS)
1. Check for fresh EMA crossover (bullish or bearish)
2. If fresh cross found, return crossover direction
3. If no fresh cross but RRM mode and bias valid, return market_bias (continuation)
4. Else return 0 (no signal)
EOF
cat /tmp/RRM_SEA_EXPLORATION.md
                EC=$?
                echo "___BEGIN___COMMAND_DONE_MARKER___$EC"
            }
___BEGIN___COMMAND_OUTPUT_MARKER___
# RRM_SEA Repository Structure & Analysis

## 1. DIRECTORY STRUCTURE

```
/home/runner/work/RRM_SEA/RRM_SEA/
├── SimpleEA_v1-03.mq5                 # Main EA (current version)
├── SEA_Config.mqh                     # Core configuration & enums (1353 lines)
├── SEA_SignalEngine.mqh                # Signal processing engine (2520 lines)
├── SEA_TradeExecutor.mqh               # Trade execution module
├── SEA_Presets.mqh                     # Preset definitions & applications
├── SEA_UI.mqh                          # UI/Panel management
├── SEA_Reporting.mqh                   # CSV reporting
├── SimpleEA_Settings.json              # JSON settings
├── Calendar/                           # News calendar data
├── Sets/                               # MT5 .set parameter files
├── Legacy/                             # Legacy code
├── Revision/                           # Historical versions
└── README.md
```

---

## 2. KEY ENUMS IN SEA_Config.mqh

### EStrategyPreset (Line 12)
```mql5
enum EStrategyPreset
{
   PRESET_CUSTOM,             // User controlled (no preset overrides)
   PRESET_MA_BENCHMARK,       // MT5 MA compatibility
   PRESET_TREND_REVERSAL,     // Trend Reversal (Baseline)
   PRESET_TREND_SCALP,        // Trend Scalp (Intraday)
   PRESET_TREND_SWING,        // Trend Swing (Institutional)
   PRESET_RANGE_GRID,         // Range Grid (Conservative mean reversion)
   PRESET_RRM_ATR,            // RRM with ATR (OPTIMIZED)
   PRESET_RRM                 // RRM Strict No-ATR Trend Pullback
};
```

### EMarketPhase (Line 59)
```mql5
enum EMarketPhase {
   PHASE_UNORDERED,   // EMAs crossed/mixed - choppy market (NO TRADE)
   PHASE_EMERGING,    // EMAs forming trend - EMA4(89) between EMA2(13) and EMA3(34)
   PHASE_TRENDING     // EMAs fully stacked - strong established trend
};
```

### EEntryLayer (Line 65)
```mql5
enum EEntryLayer {
   LAYER_NONE,        // No layer detected or detection disabled
   LAYER_1_WEAK,      // Layer 1: price touched EMA1/EMA2 zone (shallow pullback)
   LAYER_2_MEDIUM,    // Layer 2: price touched EMA2/EMA3 zone (medium pullback)
   LAYER_3_STRONG     // Layer 3: price touched EMA3/EMA4 zone (deep pullback)
};
```

### EAutoStrategy (Line ~85)
```mql5
enum EAutoStrategy
{
   STRAT_SINGLE_SLOPE,     // Single EMA direction
   STRAT_PAIR_CROSS,       // EMA crossover (RRM uses this)
   STRAT_PRICE_CROSS       // Price vs EMA
};
```

---

## 3. ST_Settings STRUCT (Core Configuration)

Location: SEA_Config.mqh
Contains 100+ configuration fields organized by function:

### Key Fields:
```mql5
struct ST_Settings
{
   // Logic
   bool CloseOnReverse;

   // Risk Management
   double RiskPercent;
   double MaxTotalRisk;          // Max % portfolio risk simultaneously (e.g., 4.0)
   int    MaxOpenTrades;         // Max concurrent trades (0 = no limit)
   bool   CountBEasZeroRisk;     // Breakeven trades don't count toward risk
   double MaxSpread;
   double MinATR;
   double MaxATR;
   bool   ATR_HardGate;
   bool   Use_ATRVote;

   // RRM (Trend Pullback)
   int    RRM_Lookback;
   double RRM_MinDivPips;

   // Bias
   bool          BiasEnabled;
   EBiasMode     BiasMode;       // AUTO, AUTO_PHASE, or MANUAL
   EManualSide   ManSide;
   EAutoStrategy AutoStrat;      // Which entry strategy to use
   int           BiasFastID;     // 0=EMA1(5), 1=EMA2(13), 2=EMA3(34), 3=EMA4(89)
   int           BiasSlowID;

   // EMAs (4-ribbon structure)
   int P_Ema1;                   // Default: 5
   int P_Ema2;                   // Default: 13
   int P_Ema3;                   // Default: 34 (RRM uses as fast bias)
   int P_Ema4;                   // Default: 89 (RRM uses as slow bias)

   // Indicators with enabled flags and weights
   int Ind_EmaSig_Weight;
   int Ind_Adx_Weight;
   int Ind_Macd_Weight;
   // ... 8 more indicator weights

   // Phase Detection (PR1)
   bool PhaseDetectionEnabled;
   bool BlockUnorderedPhase;
   bool RequireMinPhaseConfirm;
   int  MinPhaseConfirmBars;

   // Layer Detection (PR3)
   bool   EnableLayerDetection;
   double LayerTouchTolerancePips;
   bool   AllowLayer1_Entries;
   bool   AllowLayer2_Entries;
   bool   AllowLayer3_Entries;

   // Phase-specific permissions
   bool Emerging_AllowWeakTrades;
   bool Emerging_AllowMediumTrades;
   bool Emerging_AllowStrongTrades;
   bool Trending_AllowWeakTrades;
   bool Trending_AllowMediumTrades;
   bool Trending_AllowStrongTrades;
};
```

---

## 4. SEA_SignalEngine.mqh - Signal Processing

### Main GetDirection() Function (Line 1528)
**9-Step Signal Validation Pipeline:**

```
1. PRE-FILTERS      → Spread, ATR, time checks
2. MARKET BIAS      → EMA position & slopes (SINGLE_SLOPE / PAIR / NEUTRAL)
3. AUTOSTRAT        → Generate entry signal (SINGLE_SLOPE / PRICE_CROSS / PAIR_CROSS)
4. SIGNAL VALIDATION→ Entry signal matches bias
5. HTF FILTER       → Higher timeframe agreement
6. RRM GATES        → Pullback/divergence if enabled
7. VOTING BYPASS    → Skip voting if threshold <= 1
8. INDICATOR VOTING → Count indicator confirmations
9. FINAL DECISION   → Accept if votes >= threshold
```

### Entry Layer Detection (Line 2457)
**DetectEntryLayer(const int v_shift = 1)**
- Compares price to EMA tolerance band
- Returns LAYER_3_STRONG (EMA3/EMA4 touch) → highest priority
- Returns LAYER_2_MEDIUM (EMA2/EMA3 touch)
- Returns LAYER_1_WEAK (EMA1/EMA2 touch)
- Returns LAYER_NONE if disabled or no match
- Passive detection: doesn't affect entry, only logs

### AutoStrat Signal Generation (Line 1797)
```mql5
if(m_settings.AutoStrat == STRAT_SINGLE_SLOPE) {
   // Entry signal from EMA slope
   entry_signal = fast_slope;
}
else if(m_settings.AutoStrat == STRAT_PRICE_CROSS) {
   // Price vs EMA
   entry_signal = PriceCrossDirection(hf, v_shift);
}
else {  // STRAT_PAIR_CROSS (RRM default)
   // Check for EMA crossover
   bool bullish_cross = (f_prev <= s_prev && f_curr > s_curr);
   bool bearish_cross = (f_prev >= s_prev && f_curr < s_curr);
   
   if(bullish_cross)
      entry_signal = 1;
   else if(bearish_cross)
      entry_signal = -1;
   else if(RRM mode && bias valid)
      entry_signal = market_bias;  // Continuation mode
}
```

### Market Phase Diagnostics
Located in CSignalEngine class:
- `EMarketPhase m_diag_last_phase` - Last detected market phase
- `EEntryLayer m_diag_last_layer` - Last detected entry layer
- `EEntryLayer m_diag_last_entry_layer` - Last detected entry layer (260304_PR4)
- Methods: `GetLastDetectedPhase()`, `IsLayerAllowed(EEntryLayer layer, EMarketPhase phase)`

---

## 5. PRESET_RRM DEFINITION & APPLICATION

Location: SEA_Presets.mqh (Lines 574-850)

### PRESET_RRM_ATR (with ATR voting)
```mql5
if(preset == PRESET_RRM_ATR)
{
   // Auto-detect RRM mode by timeframe
   ERRMMode mode = Inp_RRM_Mode;
   if(mode == RRM_AUTO_BY_TF)
   {
      if(_Period == PERIOD_M1 || _Period == PERIOD_M5 || _Period == PERIOD_M15)
         mode = RRM_SCALP;
      else
         mode = RRM_SWING;
   }

   cfg.CloseOnReverse = true;
   cfg.BiasEnabled    = true;
   cfg.BiasMode       = BIAS_AUTO;
   cfg.AutoStrat      = STRAT_PAIR_CROSS;  // EMA crossover
   cfg.MaType         = METHOD_EMA;
   cfg.ATR_HardGate   = false;
   cfg.Use_ATRVote    = true;

   // SCALP MODE (M1/M5/M15)
   if(mode == RRM_SCALP)
   {
      cfg.BiasFastID = 0;  // EMA1(5)
      cfg.BiasSlowID = 1;  // EMA2(13)
      cfg.P_Ema1 = 34; cfg.P_Ema2 = 89; cfg.P_Ema3 = 34; cfg.P_Ema4 = 89;
      cfg.MaxSpread = 2.5;
      cfg.MinATR = (_Period == PERIOD_M1 ? 12.5 : 5.0);
      cfg.MaxATR = 0.0;
   }
   // SWING MODE (H1+)
   else
   {
      cfg.BiasFastID = 2;  // EMA3(34)
      cfg.BiasSlowID = 3;  // EMA4(89)
      cfg.P_Ema1 = 5; cfg.P_Ema2 = 13; cfg.P_Ema3 = 34; cfg.P_Ema4 = 89;
      cfg.MaxSpread = 5.0;
      cfg.MinATR = 5.0;
      cfg.MaxATR = 0.0;
   }

   // Indicators (EMA + MACD/MFI/STO/BB/PSAR)
   cfg.Ind_EmaSig_Enabled = true;
   cfg.Ind_Macd_Enabled   = true;
   cfg.Ind_Mfi_Enabled    = true;
   cfg.Ind_Sto_Enabled    = true;
   cfg.Ind_Bb_Enabled     = true;
   cfg.Ind_Psar_Enabled   = true;
   
   cfg.VoteThreshold = 4;
   cfg.VoteMode = VOTE_MODE_ALL;  // All enabled indicators must agree
   
   cfg.P_MacdFast = 8;
   cfg.P_MacdSlow = 13;
   cfg.P_MacdSig  = 8;
   
   cfg.RRM_Lookback   = 5;
   cfg.RRM_MinDivPips = 0.5;
   
   cfg.Use_BE  = true;
   cfg.BE_Trig = 1.5;
   cfg.BE_Buff = 0.3;
}
```

### PRESET_RRM (Strict No-ATR, Enhanced Protection)
```mql5
if(preset == PRESET_RRM)
{
   ERRMMode mode = Inp_RRM_Mode;
   if(mode == RRM_AUTO_BY_TF) { /* auto-detect */ }

   cfg.CloseOnReverse = true;
   cfg.BiasEnabled    = true;
   cfg.BiasMode       = Inp_BiasMode;  // Can be AUTO or AUTO_PHASE
   cfg.MaType         = METHOD_EMA;
   
   // ATR FULLY DISABLED
   cfg.MinATR       = 0.0;
   cfg.MaxATR       = 0.0;
   cfg.ATR_HardGate = false;
   cfg.Use_ATRVote  = false;

   // BIAS CONFIGURATION (based on BiasMode)
   if(cfg.BiasMode == BIAS_AUTO_PHASE)
   {
      // Phase-based: 3-EMA structure
      cfg.AutoStrat  = STRAT_PAIR_CROSS;
      cfg.BiasFastID = 2;  // EMA3(34) - not used in phase calc
      cfg.BiasSlowID = 3;  // EMA4(89) - not used in phase calc
      cfg.P_Ema1 = 5; cfg.P_Ema2 = 13; cfg.P_Ema3 = 34; cfg.P_Ema4 = 89;
      cfg.MaxSpread = (mode == RRM_SCALP) ? 2.0 : 4.0;
   }
   else  // BIAS_AUTO
   {
      cfg.AutoStrat  = STRAT_PAIR_CROSS;
      cfg.BiasFastID = 2;  // EMA3(34)
      cfg.BiasSlowID = 3;  // EMA4(89)
      cfg.P_Ema1 = 5; cfg.P_Ema2 = 13; cfg.P_Ema3 = 34; cfg.P_Ema4 = 89;
      cfg.MaxSpread = (mode == RRM_SCALP) ? 2.0 : 4.0;
   }

   // VOTING (EMA + MACD/CCI/PSAR, NO ATR)
   cfg.VoteThreshold = 4;
   cfg.VoteMode = VOTE_MODE_ALL;
   cfg.Ind_EmaSig_Enabled = true;
   cfg.Ind_Macd_Enabled   = true;
   cfg.Ind_Cci_Enabled    = true;
   cfg.Ind_Psar_Enabled   = true;
   cfg.Ind_Adx_Enabled    = false;
   cfg.Ind_Rsi_Enabled    = false;
   cfg.Ind_Mfi_Enabled    = false;
   cfg.Ind_Sto_Enabled    = false;
   cfg.Ind_Bb_Enabled     = false;

   cfg.P_MacdFast = 8;
   cfg.P_MacdSlow = 13;
   cfg.P_MacdSig  = 8;
   cfg.MacdVoteMode = MACD_HISTOGRAM;

   // PROTECTION FEATURES
   cfg.RequirePullback           = true;
   cfg.PullbackLookback          = (tf <= PERIOD_M5 ? 20 : 15);
   cfg.RequireRecoveryMomentum   = true;  // Confirm bullish/bearish momentum
   cfg.Gate_UseMultiLayer        = true;  // Multi-layer pullback detection
   
   cfg.RRM_Lookback   = 5;
   cfg.RRM_MinDivPips = 1.5;  // Deeper pullback required
   
   // PHASE DETECTION (enabled in PRESET_RRM)
   cfg.PhaseDetectionEnabled      = true;
   cfg.EnableLayerDetection       = true;
   cfg.BlockUnorderedPhase        = true;
   cfg.RequireMinPhaseConfirm     = true;
   cfg.MinPhaseConfirmBars        = 4;    // Stricter confirmation
   
   // LAYER PERMISSIONS (phase-specific)
   // EMERGING: L1, L2 allowed; L3 blocked
   cfg.Emerging_AllowWeakTrades   = true;
   cfg.Emerging_AllowMediumTrades = true;
   cfg.Emerging_AllowStrongTrades = false;
   // TRENDING: all layers allowed
   cfg.Trending_AllowWeakTrades   = true;
   cfg.Trending_AllowMediumTrades = true;
   cfg.Trending_AllowStrongTrades = true;

   // EXIT CONFIGURATION (Swing-based, PSAR trailing, no ATR)
   cfg.ExitProfile           = EXIT_PROFILE_RRM_STRICT_NO_ATR;
   cfg.SL_PlacementMode      = SL_SWING_HIGHLOW;
   cfg.SL_Mult               = 0.0;  // ATR disabled
   cfg.SL_SwingPipsCushion   = GetRecommendedInitialSlCushionPips();
   cfg.TP_Mult               = 3.0;
   cfg.TP_Enabled            = true;
   cfg.TrailMode             = TRAIL_PSAR;
   cfg.PSAR_TrailCushionMode = PSAR_CUSHION_PIPS;
   cfg.PSAR_TrailPipsCushion = GetRecommendedTrailPsarCushionPips();
   cfg.Use_BE                = true;
   cfg.BE_Mode               = BE_MODE_R_MULTIPLE;

   // RISK LIMITS
   cfg.MaxTotalRisk      = 4.0;   // Max 4% portfolio risk
   cfg.MaxOpenTrades     = 3;     // Max 3 concurrent trades
   cfg.CountBEasZeroRisk = true;

   // POLICY A (always restored)
   cfg.MaxSpread = op_MaxSpread;
   cfg.UseTime   = op_UseTime;
   // MinATR/MaxATR NOT restored (kept at 0 for strict mode)
}
```

---

## 6. MAIN EA FILE: SimpleEA_v1-03.mq5

### Header (Lines 1-70)
```mql5
//+------------------------------------------------------------------+
//|                                           SimpleEA_v1-03.mq5 |
//| Institutional Trading Solutions RRMS Simple Rapid Results Method |
//+------------------------------------------------------------------+
// SAVE AS UTF-16 LE WITH BOM
#property copyright "SimpleEA_v1.03"
#property version   "103.001"
#property strict

#define SEA_BUILD_TOKEN_103001 1
#define SEA_BUILD_NUM 103001
#define SEA_BUILD_STR "1.03.001"

// MODULE INCLUDES
#include <RRMS\SEA_Config.mqh>
#include <RRMS\SEA_Presets.mqh>
#include <RRMS\SEA_SignalEngine.mqh>
#include <RRMS\SEA_TradeExecutor.mqh>
#include <RRMS\SEA_UI.mqh>
#include <RRMS\SEA_Reporting.mqh>

// Build version verification guards
```

### Global State Variables
```mql5
CSignalEngine  Signal;
CTradeExecutor Executor;

// Global config
EEmaStrategy g_effectiveEmaStrategy;
EMaMethod    g_effectiveMaType;
EBiasMode    g_effectiveBiasMode;
string       g_effectiveSigNote;
string       g_effectiveDirSource;

// UI/Tracking
datetime g_last_bar_time = 0;
datetime g_start_time = 0;
bool     g_chart_indicators_managed = false;

// Trade Signal State (TS = Trade Signal)
datetime g_ts_time;
int      g_ts_dir;      // 1=BUY, -1=SELL
int      g_ts_bias;
int      g_ts_votes;
int      g_ts_thr;
string   g_ts_reason;

// Two-Phase Entry (TS→TE)
// Phase 1 (TS): bar-close (shift=1)
// Phase 2 (TE): first tick of NEXT bar (shift=0)
bool     g_ts_active     = false;
datetime g_ts_bar_time   = 0;
int      g_ts_direction  = 0;
datetime g_last_te_bar_time = 0;

// RRM Drawdown Protection
int      g_consecutive_losses = 0;
int      g_trades_today = 0;
datetime g_last_trade_date = 0;
double   g_daily_starting_balance = 0.0;
```

---

## 7. INPUT PARAMETERS (SEA_Config.mqh, Lines 554+)

### ZONE 1: PRESET SELECTION
```mql5
input group "══════════ 🎯 ZONE 1: PRESET SELECTION ══════════"
input ulong           Inp_MagicNum     = 12345;        // Magic number
input EStrategyPreset InpPreset         = PRESET_RRM;   // Strategy preset (default is RRM)
```

### ZONE 2: USER CONTROLS (Policy A - Always Editable)

**Operator Gates: Spread & ATR**
```mql5
input group "--- ✅ Operator Gates: Spread & ATR Limits ---"
input double Inp_MaxSpreadPips  = 3.0;    // Max spread (pips)
input double Inp_MinATRPips     = 0.0;    // Min ATR gate (pips; 0=off)
input double Inp_MaxATRPips     = 20.0;   // Max ATR gate (pips; 0=off)
```

**Operator Gates: Session Time**
```mql5
input group "--- ✅ Operator Gates: Session Time Filter ---"
input bool    Inp_UseTime       = false;  // Enable session filter
input int     Inp_StartHour     = 8;      // Session start (broker time)
input int     Inp_EndHour       = 20;     // Session end (broker time)
```

**Operator Gates: News Filter**
```mql5
input group "--- ✅ Operator Gates: News Filter ---"
input bool    Inp_UseNews       = false;  // Enable news filter
input string  Inp_NewsFile      = "calendar_statement.csv";
input int     Inp_NewsPre       = 60;     // Minutes before news block
input int     Inp_NewsPost      = 60;     // Minutes after news block
```

**Operator Gates: HTF Trend Filter**
```mql5
input group "--- ✅ Operator Gates: HTF Trend Filter ---"
input bool            Inp_UseHTF        = false;       // Enable HTF filter
input ENUM_TIMEFRAMES Inp_HtfPeriod     = PERIOD_H4;   // HTF timeframe
input int             Inp_HtfEmaPeriod  = 89;          // HTF EMA period
```

**UI Configuration**
```mql5
input group "--- ✅ UI: Status Panel ---"
input bool             Inp_UI_ShowStatusPanel     = false;
input bool             Inp_UI_ManageChartIndicators = false;
input ENUM_BASE_CORNER Inp_UI_PanelCorner        = CORNER_LEFT_UPPER;
input int              Inp_UI_PanelX             = 30;
input int              Inp_UI_PanelY             = 30;
input int              Inp_UI_PanelFontSize      = 10;
input int              Inp_UI_LineSpacingPx      = 28;
input string           Inp_UI_PanelFont          = "Arial";

input group "--- ✅ UI: Cockpit Panel ---"
input bool             Inp_UI_ShowCockpitPanel   = true;
input ENUM_BASE_CORNER Inp_UI_CockpitCorner     = CORNER_LEFT_UPPER;
input int              Inp_UI_CockpitX          = 30;
input int              Inp_UI_CockpitY          = 30;
input int              Inp_UI_CockpitFontSize   = 10;
input int              Inp_UI_CockpitLineSpacingPx = 28;
input string           Inp_UI_CockpitFont       = "Arial";

input group "--- ✅ UI: Signal Markers ---"
input bool           Inp_DrawEntryLines         = true;
input bool           Inp_DrawTradeLines         = true;

input group "--- ✅ UI: Colors & Framing ---"
input bool        Inp_UI_UseCustomColors  = true;
input color       Inp_UI_FontColor        = clrYellow;
input int         Inp_UI_PanelBgAlpha     = 110;
input EUIFrameMode Inp_UI_FrameMode       = UI_FRAME_NONE;
input int         Inp_UI_FramePadPx       = 6;

input group "--- ✅ Diagnostics ---"
input bool Inp_PrintEffectiveConfig = true;
input bool Inp_DebugFlow            = true;

input group "--- ✅ Reporting ---"
input bool Inp_ExportCSV             = false;
input bool Inp_ExportUseCommonFiles   = false;
```

### ZONE 3A: PIPELINE CONFIG (Overridden by Presets)

**STEP 1: Bias Calculation**
```mql5
input group "═══ 🔧 STEP 1: Bias Calculation ═══"
input string         Inp_Step1_Info     = "Configure major trend detection";
input bool           Inp_BiasEnabled    = true;
input EBiasMode      Inp_BiasMode       = BIAS_AUTO_PHASE;
input int            Inp_BiasFastID     = 2;    // 0=EMA1, 1=EMA2, 2=EMA3, 3=EMA4
input int            Inp_BiasSlowID     = 3;
input EManualSide    Inp_ManualSide     = SIDE_BOTH;
input EMaMethod      Inp_MaType         = METHOD_EMA;
input int            Inp_MaHorShift     = 0;    // Horizontal shift (bars)
input int            Inp_MaVerShift     = 1;    // Vertical shift (pips)
input int            InpEma1Period      = 5;
input int            InpEma2Period      = 13;
input int            InpEma3Period      = 34;
input int            InpEma4Period      = 89;
```

**STEP 2: Entry Signal & AutoStrat**
```mql5
input group "═══ 🔧 STEP 2: Entry Signal ═══"
input string        Inp_Step2_Info    = "Configure entry timing strategy";
input EAutoStrategy Inp_AutoStrat     = STRAT_PAIR_CROSS;  // SINGLE_SLOPE / PRICE_CROSS / PAIR_CROSS
input ERRMMode      Inp_RRM_Mode      = RRM_AUTO_BY_TF;
input bool          Inp_RRM_EnableInCustom = false;
input bool          Inp_CloseOnReverse = false;
input EExitProfile  Inp_ExitProfile   = EXIT_PROFILE_LEGACY;
```

**STEP 5: Structure Gate (Pullback)**
```mql5
input group "═══ 🔧 STEP 5: Structure Gate (Pullback) ═══"
input string Inp_Step5_Info            = "Configure pullback-recovery detection";
input bool   Inp_Gate_UseMultiLayer    = false;
input bool   Inp_Gate_RequirePullback  = false;
input int    Inp_Gate_PullbackLookback = 15;
input bool   Inp_Gate_RequireRecoveryMomentum = false;
input int    Inp_RRM_Lookback          = 5;
input double Inp_RRM_MinDivPips        = 0.5;
```

**STEP 6: Voting Configuration**
```mql5
input group "═══ 🔧 STEP 6: Voting Configuration ═══"
input string Inp_Step6_Info      = "Configure multi-indicator consensus";
input bool   Inp_VoteMode_All    = true;      // TRUE: all must agree; FALSE: threshold
input int    Inp_VoteThreshold   = 4;

input group "═══ 📊 Indicator: EmaSig ═══"
input bool   Inp_Ind_EmaSig_Enabled = true;
input int    Inp_Ind_EmaSig_Weight  = 1;
input string Inp_Ind_EmaSig_Info    = "Price position vs EMA1";

input group "═══ 📊 Indicator: ADX ═══"
input bool   Inp_Ind_Adx_Enabled    = false;
input int    Inp_Ind_Adx_Weight     = 1;
input int    Inp_Ind_Adx_Period     = 14;
input int    Inp_Ind_Adx_Threshold  = 20;

input group "═══ 📊 Indicator: MACD ═══"
input bool           Inp_Ind_Macd_Enabled = true;
input int            Inp_Ind_Macd_Weight  = 1;
input EMacdVoteMode  Inp_MacdVoteMode     = MACD_ZERO_AND_CROSS;
input bool           Inp_MacdRequireSlope = false;
input bool           Inp_MacdRequireDivergence = false;
input bool           Inp_MacdRequireHook  = false;
input int            Inp_P_MacdFast       = 8;
input int            Inp_P_MacdSlow       = 13;
input int            Inp_P_MacdSig        = 8;
input int            Inp_MacdFreshBars    = 3;
input double         Inp_MacdSlopeMin     = 0.00001;

input group "═══ 📊 Indicator: RSI ═══"
input bool     Inp_Ind_Rsi_Enabled  = false;
input int      Inp_Ind_Rsi_Weight   = 1;
input ERsiMode Inp_Ind_Rsi_Mode     = RSI_FILTER_EXTREME;
input int      Inp_Ind_Rsi_Period   = 14;
input double   Inp_Ind_Rsi_OB       = 70.0;
input double   Inp_Ind_Rsi_OS       = 30.0;

input group "═══ 📊 Indicator: CCI ═══"
input bool    Inp_Ind_Cci_Enabled = true;
input int     Inp_Ind_Cci_Weight  = 1;
input ECciMode Inp_Ind_Cci_Mode   = CCI_TREND_ZERO;
input int     Inp_Ind_Cci_Period  = 14;

// ... Additional indicators (MFI, Stochastic, Bollinger, PSAR, Pattern123, Ross)
```

**STEP 9: Risk & Execution**
```mql5
input group "--- ℹ️ Step 9: Risk & Execution ---"
input double Inp_RiskPercent = 2.0;    // Risk per trade (%)

input group "--- ℹ️ Step 9 · Initial SL Placement ---"
input ESlPlacementMode Inp_SL_PlacementMode  = SL_SWING_HIGHLOW;
input double           Inp_SL_Mult           = 1.5;
input double           Inp_SL_PsarPipsCushion = 5.0;
input double           Inp_SL_SwingPipsCushion = 10.0;
input double           Inp_SL_FixedPips      = 20.0;

input group "--- ℹ️ Step 9 · TP & Breakeven ---"
input double Inp_TP_Mult  = 3.0;
input bool   Inp_Use_BE   = false;
input double Inp_BE_Trig  = 1.0;
input double Inp_BE_Buff  = 0.1;

input group "--- ℹ️ Step 9 · Trailing Stop ---"
input ETrailingMode Inp_TrailMode                = TRAIL_PSAR;
input double        Inp_Trail_Mult               = 3.0;
input EPsarTrailCushionMode Inp_PSAR_TrailCushionMode = PSAR_CUSHION_PIPS;
input double        Inp_PSAR_TrailPipsCushion    = 5.0;
input double        Inp_PSAR_TrailCushionATR     = 0.2;
```

### ZONE 3C: ADAPTIVE SETTINGS (Auto-scale by Pair & Timeframe)
```mql5
input group "══════════ 🔧 ZONE 3C: ADAPTIVE SETTINGS ══════════"

input group "═══ 🔧 Adaptive: Pair Type Detection ═══"
input EPairType Inp_Adaptive_PairType = PAIR_TYPE_AUTO;

input group "═══ 🔧 Adaptive: Spread Limits (by pair type) ═══"
input double Inp_Adaptive_Spread_Major  = 2.0;
input double Inp_Adaptive_Spread_Minor  = 4.0;
input double Inp_Adaptive_Spread_Exotic = 10.0;
input double Inp_Adaptive_Spread_Gold   = 5.0;
input double Inp_Adaptive_Spread_Crypto = 50.0;

input group "═══ 🔧 Adaptive: ATR Limits (by timeframe) ═══"
input ETFScaling Inp_Adaptive_ATR_Mode  = TF_SCALE_AUTO;
input double     Inp_Adaptive_ATR_Min_Base = 5.0;
input double     Inp_Adaptive_ATR_Max_Base = 20.0;

input group "═══ 🔧 Adaptive: SL/TP Distance (by timeframe) ═══"
input double Inp_Adaptive_SL_Base = 20.0;
input double Inp_Adaptive_TP_Base = 40.0;
input bool   Inp_Adaptive_UseSL   = false;
input bool   Inp_Adaptive_UseTP   = false;

input group "═══ 🔧 Adaptive: Trail Stop Cushion (by timeframe) ═══"
input double Inp_Adaptive_TrailCushion_Base = 5.0;
input bool   Inp_Adaptive_UseTrailCushion   = false;

input group "═══ 🔧 Adaptive: PSAR Trail Cushion (by volatility) ═══"
input double Inp_Adaptive_PsarCushion_Pips = 3.0;
input bool   Inp_Adaptive_PsarUseATR        = false;
input double Inp_Adaptive_PsarATR_Multiplier = 0.5;
```

### ZONE 3B: ADMIN OVERRIDE (For Testing)
```mql5
input group "══════════ 🔓 ZONE 3B: ADMIN OVERRIDE ══════════"
input bool Inp_AdminOverridePreset = false;  // Unlock preset parameters

// ... Override inputs for AutoStrat, EMA periods, vote threshold, etc.
```

---

## 8. SUMMARY: Key Architecture Points

### Default Configuration (PRESET_RRM)
- **Preset**: `PRESET_RRM` (Enhanced Protection)
- **Bias**: `BIAS_AUTO` or `BIAS_AUTO_PHASE`
- **AutoStrat**: `STRAT_PAIR_CROSS` (EMA crossover)
- **Bias EMAs**: EMA3(34) fast / EMA4(89) slow
- **Entry Strategy**: Pair crossover (not single slope or price cross)
- **ATR**: Fully disabled (MinATR=0, MaxATR=0, no ATR voting)
- **Voting**: ALL mode (all enabled indicators must agree)
- **Indicators**: EMA, MACD, CCI, PSAR (4 votes required)
- **Phase Detection**: Enabled (UNORDERED, EMERGING, TRENDING)
- **Layer Detection**: Enabled (LAYER_1_WEAK, LAYER_2_MEDIUM, LAYER_3_STRONG)
- **Exit**: Swing-based SL with PSAR trailing

### Key Protection Features (PRESET_RRM)
1. **4-bar phase confirmation** (was 3)
2. **Recovery momentum requirement** (bullish/bearish candle)
3. **20-bar pullback lookback** (M1/M5)
4. **1.5 pips min EMA divergence** (was 0.5)
5. **Stricter EMERGING layer filtering** (L3 blocked)
6. **Multi-layer pullback detection** enabled
7. **Swing-based SL** (not ATR)
8. **PSAR-based trailing** with adaptive cushions
9. **Max 3 concurrent trades** with 4% portfolio risk limit

### Layer Detection Mechanism
- **Layer 3 (STRONG)**: Price within tolerance of EMA3 or EMA4 → deep pullback
- **Layer 2 (MEDIUM)**: Price within tolerance of EMA2 or EMA3 → medium pullback
- **Layer 1 (WEAK)**: Price within tolerance of EMA1 or EMA2 → shallow pullback
- Tolerance: `LayerTouchTolerancePips` (default controlled by preset)
- Passive detection: logs to diagnostics, doesn't filter entries (yet)

### AutoStrat Signal Generation (STRAT_PAIR_CROSS)
1. Check for fresh EMA crossover (bullish or bearish)
2. If fresh cross found, return crossover direction
3. If no fresh cross but RRM mode and bias valid, return market_bias (continuation)
4. Else return 0 (no signal)

___BEGIN___COMMAND_DONE_MARKER___0
