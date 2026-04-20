//+-------------------------------------------------------------------+
//|                                                  SEA_Presets.mqh  |
//|                                   Copyright 2026, SimpleEA System |
//| DESCRIPTION: Preset definitions: overwrite strategy-critical fields|
//|              on top of already hydrated Settings.                 |
//|                                                                   |
//| IMPORTANT:                                                        |
//| - NO input->struct mapping in this file.                          |
//| - NO printing/diagnostic spam in this file.                       |
//| - NO ValidateEffectiveSettings() in this file.                    |
//| - Do NOT touch global-allowed-under-presets fields:               |
//|   PrintEffectiveConfig, DebugFlow, UI toggles, reporting toggles. |
//+-------------------------------------------------------------------+
#property strict

// Preset system version
#define PRESET_SYSTEM_VERSION "2.1.0"  // Major.Minor.Patch

#include <RRMS\SEA_Config.mqh>

// TF+JPY-aware initial SL cushion mapping (suited for SL_PSAR_DOT / SL_MODE_SWING)
double GetRecommendedInitialSlCushionPips()
{
   ENUM_TIMEFRAMES tf = _Period;
   bool isJPY = (StringFind(_Symbol, "JPY") >= 0);

   if      (tf <= PERIOD_M5)  return isJPY ?  3.0 :  2.0;    // Covers M1 through M5
   else if (tf <= PERIOD_M30) return isJPY ?  5.0 :  3.0;    // Covers M6 through M30
   else if (tf <= PERIOD_H1)  return isJPY ?  8.0 :  5.0;    // Covers H1
   else if (tf <= PERIOD_H4)  return isJPY ? 15.0 : 10.0;    // Covers H2 through H4
   else                       return isJPY ? 25.0 : 15.0;    // Covers H6, D1, W1, MN1
}

// TF+JPY-aware trailing cushion mapping (smaller, suited for TRAIL_PSAR + PSAR_CUSHION_PIPS)
double GetRecommendedTrailPsarCushionPips()
{
   ENUM_TIMEFRAMES tf = _Period;
   bool isJPY = (StringFind(_Symbol, "JPY") >= 0);

   if      (tf <= PERIOD_M5)  return isJPY ?  2.0 :  1.0;    // Covers M1 through M5
   else if (tf <= PERIOD_M30) return isJPY ?  3.0 :  2.0;    // Covers M16 through M30
   else if (tf <= PERIOD_H1)  return isJPY ?  7.0 :  5.0;    // Covers H1
   else if (tf <= PERIOD_H4)  return isJPY ? 10.0 :  5.0;    // Covers H2 through H4
   else                       return isJPY ? 25.0 : 15.0;    // Covers H6, D1, W1, MN1
}

// TF+JPY-aware breakeven/trail cushion values
double GetTFBasedCushion(ENUM_TIMEFRAMES tf)
{
   if(tf == PERIOD_CURRENT) tf = _Period; // Safe fallback just in case
   bool isJPY = (StringFind(_Symbol, "JPY") >= 0);

   if      (tf <= PERIOD_M5)  return isJPY ?  5.0 :  3.0;    // Covers M1 through M5
   else if (tf <= PERIOD_M30) return isJPY ?  8.0 :  5.0;    // Covers M6 through M30
   else if (tf <= PERIOD_H1)  return isJPY ? 12.0 :  8.0;    // Covers H1
   else if (tf <= PERIOD_H4)  return isJPY ? 15.0 : 10.0;    // Covers H2 through H4
   else                       return isJPY ? 25.0 : 15.0;    // Covers H6, D1, W1, MN1
}

string PresetToString(EStrategyPreset p)
{
   switch(p)
   {
      case PRESET_CUSTOM:       return "CUSTOM";
      case PRESET_MA:           return "MA";
      case PRESET_RRM:          return "RRM";
      case PRESET_TEST:         return "TEST";
      default:                  return "UNKNOWN";
   }
}

// GetPresetContractWording(): returns a one-line description of what the preset controls
// vs. what the user controls. Used in Cockpit Panel and Status Panel displays.
string GetPresetContractWording(EStrategyPreset preset)
{
   switch(preset)
   {
      case PRESET_CUSTOM:
         return "PRESET CUSTOM: All inputs respected; you control strategy, indicators, and operator gates.";
      case PRESET_MA:
         return "PRESET MA: benchmark mode: replicates MT5 Moving Average EA; all voting disabled.";
      case PRESET_RRM:
         return "PRESET RRM: phase-based system fixed (AutoStrat, EMA/MACD config, vote threshold); only Policy A gates and exits user-controlled.";
      case PRESET_TEST:
         return "PRESET TEST: Minimal testing mode: bypass voting (threshold=1), fixed SL/TP, no trailing.";
      default:
         return "PRESET: Preset active; strategy-critical settings fixed by preset.";
   }
}

//+------------------------------------------------------------------+
//| GetActiveIndicatorCount(): Wrapper → use GetEnabledIndicatorCount|
//| Kept for backward compatibility; delegates to central function.  |
//+------------------------------------------------------------------+
int GetActiveIndicatorCount(const ST_Settings &cfg)
{
   return GetEnabledIndicatorCount(cfg);
}

//+------------------------------------------------------------------+
//| DetectSymbolType(): Detect symbol category for spread defaults   |
//+------------------------------------------------------------------+
string DetectSymbolType(const string symbol)
{
   string sym = symbol;
   StringToUpper(sym);
   
   // Majors
   if(StringFind(sym, "EURUSD") >= 0) return "MAJOR";
   if(StringFind(sym, "GBPUSD") >= 0) return "MAJOR";
   if(StringFind(sym, "USDJPY") >= 0) return "MAJOR";
   if(StringFind(sym, "USDCHF") >= 0) return "MAJOR";
   if(StringFind(sym, "AUDUSD") >= 0) return "MAJOR";
   if(StringFind(sym, "USDCAD") >= 0) return "MAJOR";
   if(StringFind(sym, "NZDUSD") >= 0) return "MAJOR";
   
   // Gold
   if(StringFind(sym, "XAUUSD") >= 0) return "GOLD";
   if(StringFind(sym, "GOLD")   >= 0) return "GOLD";
   
   // Crypto
   if(StringFind(sym, "BTC") >= 0) return "CRYPTO";
   if(StringFind(sym, "ETH") >= 0) return "CRYPTO";
   
   // Exotics
   if(StringFind(sym, "TRY") >= 0) return "EXOTIC";
   if(StringFind(sym, "ZAR") >= 0) return "EXOTIC";
   if(StringFind(sym, "MXN") >= 0) return "EXOTIC";

   // Default: minor
   return "MINOR";
}

//+------------------------------------------------------------------+
//| PrintPresetConfiguration(): Print active preset config           |
//+------------------------------------------------------------------+
void PrintPresetConfiguration(const ST_Settings &cfg, const string preset_name)
{
   Print("═══════════════════════════════════════════════════════════");
   Print("🎯 PRESET ACTIVE: ", preset_name);
   Print("═══════════════════════════════════════════════════════════");
   Print("");
   Print("📊 BIAS & STRATEGY:");
   Print("  BiasMode:       ", EnumToString(cfg.BiasMode));
   Print("  AutoStrat:      ", EnumToString(cfg.AutoStrat));
   Print("  EMA Periods:    ", cfg.P_Ema1, "/", cfg.P_Ema2, "/", cfg.P_Ema3, "/", cfg.P_Ema4);
   Print("");

   Print("🗳️  VOTING:");
   Print("  Mode:           ", EnumToString(cfg.VoteMode));
   Print("  Active Votes:   ", GetActiveIndicatorCount(cfg), " indicators enabled");
   Print("    ADX:     ", (cfg.Ind_Adx_Enabled ? "✓" : "✗"));
   Print("    ATR:     ", (cfg.Ind_Atr_Enabled ? "✓" : "✗"));
   Print("    BB:      ", (cfg.Ind_Bb_Enabled ? "✓" : "✗"));
   Print("    CandleBody: ", (cfg.Ind_CandleBody_Enabled ? "✓" : "✗"));
   Print("    CI:      ", (cfg.Ind_CI_Enabled ? "✓" : "✗"));
   Print("    VRC:     ", (cfg.Ind_VRC_Enabled ? "✓" : "✗"));
   Print("    CCI:     ", (cfg.Ind_Cci_Enabled ? "✓" : "✗"));
   Print("    MACD:    ", (cfg.Ind_Macd_Enabled ? "✓" : "✗"), (cfg.Ind_Macd_Enabled ? " (" + EnumToString(cfg.MacdVoteMode) + ")" : ""));
   Print("    MFI:     ", (cfg.Ind_Mfi_Enabled ? "✓" : "✗"));
   Print("    P123:    ", (cfg.Ind_P123_Enabled ? "✓" : "✗"));
   Print("    PSAR:    ", (cfg.Ind_Psar_Enabled ? "✓" : "✗"));
   Print("    Ross:    ", (cfg.Ind_Ross_Enabled ? "✓" : "✗"));
   Print("    RSI:     ", (cfg.Ind_Rsi_Enabled ? "✓" : "✗"));
   Print("    Stoch:   ", (cfg.Ind_Sto_Enabled ? "✓" : "✗"));
   Print("");

   Print("💰 RISK MANAGEMENT:");
   Print("  RiskPercent:    ", cfg.RiskPercent, "%");
   Print("  MaxOpenTrades:  ", (cfg.MaxOpenTrades > 0 ? IntegerToString(cfg.MaxOpenTrades) : "unlimited"));
   Print("  MaxTotalRisk:   ", (cfg.MaxTotalRisk > 0.0 ? DoubleToString(cfg.MaxTotalRisk, 1) + "%" : "unlimited"));
   Print("");
   Print("🛡️  GATES (Policy A - User Controlled):");
   Print("  MaxSpread:      ", cfg.MaxSpread, " pips");
   Print("  Time Filter:    ", (cfg.UseTime ? ("✓ " + IntegerToString(cfg.StartHr) + "h-" + IntegerToString(cfg.EndHr) + "h") : "✗"));
   Print("  News Filter:    ", (cfg.UseNews ? ("✓ ±" + IntegerToString(cfg.NewsPre) + "/" + IntegerToString(cfg.NewsPost) + "min") : "✗"));
   Print("");

   Print("🎯 EXIT PROFILE:");
   Print("  Profile:        ", EnumToString(cfg.ExitProfile));
   Print("  SL Mode:        ", EnumToString(cfg.SLMode), " (", cfg.SL_FixedPips, " pips)");
   Print("  TP Mode:        ", EnumToString(cfg.TPMode), (cfg.TP_Enabled ? " ✓ ENABLED" : " ✗ DISABLED"));
   Print("  Trail Mode:     ", EnumToString(cfg.TrailMode));
   Print("  BE Mode:        ", EnumToString(cfg.BE_Mode));
   Print("");

   Print("🔧 SYMBOL CONTEXT:");
   Print("  Symbol:         ", _Symbol);
   Print("  Type:           ", DetectSymbolType(_Symbol));
   Print("  Timeframe:      ", EnumToString(Period()));
   Print("");

   Print("📐 SLOPE CALCULATION:");
   Print("  Lookback:      ", cfg.SlopeLookbackBars, " bar(s)");
   Print("  Threshold:     ", cfg.UseSlopeThreshold ? "ENABLED" : "DISABLED");
   if(cfg.UseSlopeThreshold) {
      if(cfg.SlopeThresholdAdaptive) {
         Print("  Mode:          ADAPTIVE (TF + Pair)");
      } else {
         Print("  Mode:          FIXED (", cfg.SlopeThresholdPips, " pips)");
      }
      Print("  Measure:       ", EnumToString(cfg.SlopeMeasureMode));
   }
   Print("");

   Print("📊 BAR CLOSE (bcX):");
   Print("  Enabled:       ", cfg.BarClose_Enabled ? "✓ YES" : "✗ NO");
   if(cfg.BarClose_Enabled && cfg.BarClose_Mode != BC_DISABLED) {
      Print("  Mode:          ", EnumToString(cfg.BarClose_Mode));
      if(cfg.BarClose_Mode == BC_FIXED_EMA || cfg.BarClose_Mode == BC_LAYER_AWARE)
         Print("  DefaultEMA:    ", EnumToString(cfg.BarClose_DefaultEMA));
   }
   Print("");

   Print("═══════════════════════════════════════════════════════════");
}

//+------------------------------------------------------------------+
//| ValidatePresetConfiguration(): Validate preset sanity            |
//| Returns: true if valid, false if critical errors detected        |
//+------------------------------------------------------------------+
bool ValidatePresetConfiguration(const ST_Settings &cfg, const string preset_name)
{
   bool valid = true;
   string errors = "";

   // Check: At least one indicator enabled (EXCEPT for MA Benchmark Mode)
   if(GetActiveIndicatorCount(cfg) == 0 && !cfg.MABenchmarkStrict)
   {
      errors += "  ❌ ERROR: No voting indicators enabled!\n";
      valid = false;
   }

   // Check: EMA periods ascending
   if(cfg.P_Ema1 >= cfg.P_Ema2 || cfg.P_Ema2 >= cfg.P_Ema3 || cfg.P_Ema3 >= cfg.P_Ema4)
   {
      errors += "  ❌ ERROR: EMA periods must be ascending (EMA1 < EMA2 < EMA3 < EMA4)!\n";
      valid = false;
   }

   // Check: Risk percent valid
   // Note: MA Benchmark might use 0.0 to rely on fixed lots, so we allow 0.0 if strict mode is active
   if(cfg.RiskPercent < 0.0 || (cfg.RiskPercent == 0.0 && !cfg.MABenchmarkStrict && cfg.FixedLotSize <= 0.0) || cfg.RiskPercent > 100.0)
   {
      errors += "  ❌ ERROR: RiskPercent must be > 0 and <= 100 (unless using FixedLotSize)!\n";
      valid = false;
   }

   // Check: VOTE_MODE_ALL recommended (Skip warning for MA mode since voting is off)
   if(cfg.VoteMode != VOTE_MODE_ALL && !cfg.MABenchmarkStrict)
   {
      errors += "  ⚠️  WARNING: VoteMode is not VOTE_MODE_ALL (recommended default)\n";
   }

   // Print results
   if(!valid)
   {
      Print("═══════════════════════════════════════════════════════════");
      Print("❌ PRESET VALIDATION FAILED: ", preset_name);
      Print("═══════════════════════════════════════════════════════════");
      Print(errors);
      Print("---");
   }
   else if(errors != "")
   {
      Print("═══════════════════════════════════════════════════════════");
      Print("⚠️  PRESET VALIDATION WARNINGS: ", preset_name);
      Print("═══════════════════════════════════════════════════════════");
      Print(errors);
      Print("---");
   }

   return valid;
}

void ApplyPreset(const EStrategyPreset preset, ST_Settings &cfg)
{
   if(preset == PRESET_CUSTOM)
      return;
      
   // Do NOT modify cfg.PrintEffectiveConfig / cfg.DebugFlow
   // Do NOT modify UI toggles or reporting toggles (ExportCSV, ExportUseCommonFiles)

   // ================================================================
   // Policy A: Universal Operational Filters (User Always Controls)
   // 
   // These filters apply ON TOP of preset strategy logic:
   //   - MaxSpread:  Cost control / broker protection (slippage, spreads)
   //   - Time:       User availability / preferred trading sessions
   //   - News:       Risk aversion / avoid high-impact news volatility
   //   - Risk:       Personal risk tolerance (RiskPercent, MaxOpenTrades, MaxTotalRisk)
   //
   // Strategic filters (ATR voting, HTF) are preset-controlled.
   // Users who want full control: Use PRESET_CUSTOM
   // ================================================================
   const double op_MaxSpread     = cfg.MaxSpread;
   const bool   op_UseSpread     = cfg.UseSpread;
   const bool   op_UseTime       = cfg.UseTime;
   const int    op_StartHr       = cfg.StartHr;
   const int    op_EndHr         = cfg.EndHr;
   const bool   op_UseNews       = cfg.UseNews;
   const int    op_NewsPre       = cfg.NewsPre;
   const int    op_NewsPost      = cfg.NewsPost;
   // Policy A: user risk tolerance
   const double op_RiskPercent   = cfg.RiskPercent;
   // Policy A: user position limit
   const int    op_MaxOpenTrades = cfg.MaxOpenTrades;
   // Policy A: user portfolio risk cap
   const double op_MaxTotalRisk  = cfg.MaxTotalRisk;
   // Saved for PRESET_TEST exit-profile logic
   const EExitProfile op_ExitProfile = cfg.ExitProfile;

   if(preset == PRESET_MA)
   {
      // ================================================================
      // PRESET_MA: MT5 Moving Average Benchmark
      // Replicates MT5 built-in "Moving Average" Expert Advisor behavior
      // - Simple price/MA crossover (no bias, no phase detection)
      // - All indicator voting disabled
      // - Stop-and-reverse on every cross
      // - MA-compatible lot sizing (MaximumRisk + DecreaseFactor)
      // - No broker-side SL/TP (EA manages exits internally)
      // ================================================================
   
      // ================================================================
      // CORE STRATEGY SETTINGS
      // ================================================================
      cfg.CloseOnReverse         = true;
      cfg.BiasEnabled            = true;
      cfg.BiasMode               = BIAS_2EMA;
      cfg.AutoStrat              = STRAT_2EMA_CROSS_PRICE;
      cfg.BiasFastID             = (int)ROLE_EMA1;
      cfg.BiasSlowID             = (int)ROLE_EMA1;
      cfg.MaType                 = METHOD_SMA;
      cfg.RequirePriceCross      = true;
      cfg.MABenchmarkStrict      = true;
      cfg.UseMACompatSizer       = true;
   
      // ================================================================
      // INDICATOR VOTING CONFIGURATION (Alphabetical)
      // ================================================================
      cfg.Ind_Adx_Enabled        = false;
      cfg.Ind_Atr_Enabled        = false;
      cfg.Ind_Bb_Enabled         = false;
      cfg.Ind_CandleBody_Enabled = false;
      cfg.Ind_CI_Enabled         = false;
      cfg.Ind_VRC_Enabled        = false;
      cfg.Ind_Cci_Enabled        = false;
      cfg.Ind_Macd_Enabled       = false;
      cfg.Ind_Mfi_Enabled        = false;
      cfg.Ind_P123_Enabled       = false;
      cfg.Ind_Psar_Enabled       = false;
      cfg.Ind_Ross_Enabled       = false;
      cfg.Ind_Rsi_Enabled        = false;
      cfg.Ind_Sto_Enabled        = false;
   
      cfg.VoteMode               = VOTE_MODE_ALL;
      
      // ================================================================
      // INDICATOR PERIODS & THRESHOLDS (Alphabetical)
      // ================================================================
      
      // ADX (Average Directional Index)
      cfg.P_Adx                  = 14;
      cfg.T_Adx                  = 20.0;
      cfg.ADX_Mode               = ADX_MODE_STATIC;
      cfg.ADX_Percentile         = 50.0;
      cfg.ADX_Lookback           = 100;
      cfg.ADX_Threshold_Accumulation = 12.0;
      cfg.ADX_Threshold_Trending     = 25.0;
      cfg.ADX_Threshold_Distribution = 18.0;
      
      // ATR (Average True Range) - Voting Indicator Only
      cfg.P_Atr                  = 14;
      cfg.ATR_VoteMinPips        = 5.0;
      cfg.ATR_VoteMaxPips        = 50.0;
      
      // Bollinger Bands
      cfg.P_Bb                   = 20;
      cfg.P_BbDev                = 2.0;
      cfg.BbMode                 = BB_TREND_FOLLOW;
   
      // Candle Body
      cfg.CandleBody_AvgPeriod   = 10;
      cfg.CandleBody_MaxMult     = 3.0;
      cfg.CandleBody_CheckBars   = 1;
      cfg.Ind_CandleBody_Weight  = 1;

      // Choppiness Index
      cfg.CI_Period              = 14;
      cfg.CI_RangingThreshold    = 61.8;
      cfg.Ind_CI_Weight          = 1;
      
      // VRC (Volatility Regime Classifier)
      cfg.VRC_ATR_Period         = 14;
      cfg.VRC_Lookback           = 100;
      cfg.VRC_LowThreshold       = 33.0;
      cfg.Ind_VRC_Weight         = 1;

      // CCI (Commodity Channel Index)
      cfg.P_Cci                  = 14;
      cfg.CciMode                = CCI_TREND_ZERO;

      // EMA (Periods)
      cfg.P_Ema1                 = Inp_MA_Period; // Primary MA (user-controlled via input)
      cfg.P_Ema2                 = 13;
      cfg.P_Ema3                 = 34;
      cfg.P_Ema4                 = 89;
      
      // MACD (Moving Average Convergence Divergence)
      cfg.P_MacdFast             = 12;
      cfg.P_MacdSlow             = 26;
      cfg.P_MacdSig              = 9;
      cfg.MacdVoteMode           = MACD_HISTOGRAM;
      cfg.MacdRequireSlope       = false;
      cfg.MacdRequireDivergence  = false;
      cfg.MacdRequireHook        = false;
      cfg.MacdFreshBars          = 3;
      cfg.MacdSlopeMin           = 0.00001;
      
      // MFI (Money Flow Index)
      cfg.P_Mfi                  = 14;
      cfg.T_MfiOB                = 80.0;
      cfg.T_MfiOS                = 20.0;
      cfg.MfiMode                = MFI_ZONE_FILTER;
   
      // PSAR (Parabolic SAR)
      cfg.P_PsarStep             = 0.02;
      cfg.P_PsarMax              = 0.2;
      cfg.Vote_AllowPsarFlip     = false;
      cfg.Vote_PsarFlipDelay     = 0;
      
      // RSI (Relative Strength Index)
      cfg.P_Rsi                  = 14;
      cfg.T_RsiOB                = 70.0;
      cfg.T_RsiOS                = 30.0;
      cfg.RsiMode                = RSI_TREND_ABOVE_50;
   
      // Stochastic Oscillator
      cfg.P_StoK                 = 5;
      cfg.P_StoD                 = 3;
      cfg.P_StoSlow              = 3;
      cfg.T_StoOB                = 80.0;
      cfg.T_StoOS                = 20.0;
      cfg.StoMode                = STO_CROSS_SIGNAL;
   
      // ================================================================
      // PHASE DETECTION & LAYER FILTERING
      // ================================================================
      cfg.PhaseDetectionEnabled     = false;
      cfg.EnableLayerDetection      = false;
      cfg.BlockUnorderedPhase       = false;
      cfg.RequireMinPhaseConfirm    = false;
      cfg.MinPhaseConfirmBars       = 0;
      
      // Layer permissions per phase
      cfg.Trending_AllowWeakTrades   = false;
      cfg.Emerging_AllowWeakTrades   = false;
      cfg.Trending_AllowMediumTrades = false;
      cfg.Emerging_AllowMediumTrades = false;
      cfg.Trending_AllowStrongTrades = false;
      cfg.Emerging_AllowStrongTrades = false;
      
      // ================================================================
      // PULLBACK DETECTION GATES
      // ================================================================
      cfg.RequireRecoveryMomentum   = false;
      
      // Gate 2: Recovery momentum
      cfg.Gate_Recovery.mode        = GATE_SCALE_FIXED;
      cfg.Gate_Recovery.value       = 0.0;
      cfg.RRM_Lookback              = 0;
      
      // Gate 3: EMA divergence
      cfg.Gate_EmaDiv.mode          = GATE_SCALE_FIXED;
      cfg.Gate_EmaDiv.value         = 0.0;
      cfg.RRM_MinDivPips            = 0.0;
      
      // Gate 4: Candle direction
      cfg.Gate_CandleDirection.mode  = GATE_SCALE_FIXED;
      cfg.Gate_CandleDirection.value = 0.0;
      
      // ================================================================
      // VOTE EVALUATION SETTINGS
      // ================================================================
      cfg.Vote_EvalShift            = 1;
      
      // ================================================================
      // RISK MANAGEMENT (Portfolio-level)
      // ================================================================
      cfg.RiskPercent               = 0.0; // Uses MA-compatible sizer instead
      cfg.FixedLotSize              = 0.0;
      cfg.MaxTotalRisk              = 100.0;
      cfg.MaxOpenTrades             = 1;
      cfg.CountBEasZeroRisk         = false;
      
      // ================================================================
      // EXIT STRATEGY CONFIGURATION
      // ================================================================
      cfg.ExitProfile               = EXIT_PROFILE_NONE;
      cfg.TP_Enabled                = false;
      cfg.TrailMode                 = TRAIL_NONE;
      cfg.PSAR_TrailCushionMode     = PSAR_CUSHION_PIPS;
      cfg.PSAR_TrailPipsCushion     = 0.0;
      cfg.BE_Mode                   = BE_MODE_OFF;
      
      // ================================================================
      // SL/TP STRATEGY MODES
      // ================================================================
      cfg.SLMode                    = SL_MODE_FIXED_PIPS;
      cfg.TPMode                    = TP_MODE_NONE;
      cfg.FixedTPPips               = 0.0;
      cfg.SLPercent                 = 0.0;
      cfg.RRRatio                   = 0.0;
      cfg.SwingLookback             = 0;
      
      // ================================================================
      // FRACTAL/PSAR SL/TP DEFAULTS
      // ================================================================
      cfg.FractalPeriod             = 5;
      cfg.TPFractalOffset           = 1;

      // ================================================================
      // ADVANCED TRAILING TRIGGER DEFAULTS
      // ================================================================
      cfg.TrailTrigger              = TRIGGER_IMMEDIATE;
      cfg.TrailDistancePips         = 0.0;
      cfg.BEThresholdPips           = 0.0;
      cfg.TrailProfitPercent        = 0.0;
      cfg.TrailStepPips             = 0.0;
      cfg.TrailLockProfit           = false;
      
      // ================================================================
      // MA-SPECIFIC SETTINGS
      // ================================================================
      cfg.ma_h_shift                = Inp_MA_Shift;
      cfg.ma_v_shift                = 1;
   
      // ================================================================
      // MA DRAWDOWN PROTECTION (All off for benchmark mode)
      // ================================================================
      cfg.RRM_EnableDrawdownProtection = false;
      cfg.RRM_MaxConsecutiveLosses  = 0;
      cfg.RRM_MaxTradesPerDay       = 0;
      cfg.RRM_MaxDailyDrawdownPct   = 0.0;

      // ================================================================
      // SLOPE CALCULATION SETTINGS (Benchmark Mode - No Filtering)
      // ================================================================
      cfg.SlopeLookbackBars         = 1; // MT5 standard (single bar)
      cfg.UseSlopeThreshold         = false; // No filtering (match MT5)
      cfg.SlopeThresholdPips        = 0.0;
      cfg.SlopeThresholdAdaptive    = false;
      cfg.SlopeMeasureMode          = SLOPE_MEASURE_PIPS;

      // ════════════════════════════════════════════════════════════════
      // BAR CLOSE (bcX) CONFIGURATION - Disabled for MA benchmark mode
      // ════════════════════════════════════════════════════════════════
      cfg.BarClose_Enabled          = false;        // Disabled: bcX not used in MA benchmark
      cfg.BarClose_Mode             = BC_DISABLED;
      cfg.BarClose_DefaultEMA       = ROLE_EMA1;

      // ════════════════════════════════════════════════════════════════
      // BAR CLOSE (bcX) CONFIGURATION - Disabled for MA benchmark mode
      // ════════════════════════════════════════════════════════════════
      cfg.BarClose_Enabled    = false;        // Disabled: bcX not used in MA benchmark
      cfg.BarClose_Mode       = BC_DISABLED;
      cfg.BarClose_DefaultEMA = ROLE_EMA1;

      // ================================================================
      // POLICY A: RESTORE OPERATOR-CONTROLLED GATES
      // ================================================================
      cfg.MaxSpread     = op_MaxSpread;
      cfg.UseSpread     = op_UseSpread;
      cfg.UseTime       = op_UseTime;
      cfg.StartHr       = op_StartHr;
      cfg.EndHr         = op_EndHr;
      cfg.UseNews       = op_UseNews;
      cfg.NewsPre       = op_NewsPre;
      cfg.NewsPost      = op_NewsPost;
      cfg.RiskPercent   = op_RiskPercent; // Policy A: restore user risk tolerance
      cfg.MaxOpenTrades = op_MaxOpenTrades; // Policy A: restore user position limit
      cfg.MaxTotalRisk  = op_MaxTotalRisk; // Policy A: restore user portfolio risk cap

      return;
   }

   if(preset == PRESET_RRM)
   {
      // ================================================================
      // PRESET_RRM: KISS Minimal Layer-Based Strategy
      // ================================================================
      //
      // FORMULA:
      //   TS = Bias × LayerX × bcX × IndicatorX × FilterX
      //
      // COMPONENTS:
      //   Bias = BIAS_4EMA (Phase: UNO/EM/TM)
      //   LayerX = EMA pair structure (position + slope)
      //   bcX = Bar close confirmation (layer-aware)
      //     • bcW: Close beyond EMA1 (for LayerW)
      //     • bcM: Close beyond EMA2 (for LayerM)
      //     • bcS: Close beyond EMA3 (for LayerS)
      //   IndicatorX = PSAR only
      //   FilterX = User-controlled gates
      //
      // ================================================================
   
      ERRMMode mode = Inp_RRM_Mode;
      if(mode == RRM_AUTO_BY_TF)
      {
         // Auto-select sub-mode based on chart timeframe
         if(_Period == PERIOD_M1 || _Period == PERIOD_M5 || _Period == PERIOD_M15) 
            mode = RRM_SCALP;
         else 
            mode = RRM_SWING;
      }
   
      // ================================================================
      // CORE STRATEGY SETTINGS
      // ================================================================
      cfg.CloseOnReverse         = true;
      cfg.BiasEnabled            = true;
      cfg.BiasMode               = Inp_BiasMode;
      cfg.MaType                 = METHOD_EMA;
      cfg.RequirePriceCross      = false;
      cfg.MABenchmarkStrict      = false;
      cfg.UseMACompatSizer       = false;
      
      // ================================================================
      // BIAS MODE ROUTING
      // ================================================================
      if(cfg.BiasMode == BIAS_4EMA)
      {
         // ────────────────────────────────────────────────────────────
         // BRANCH 1: BIAS_4EMA (4-EMA Phase Detection)
         // Uses: EMA1(5), EMA2(13), EMA3(34), EMA4(89)
         // Logic: 3-layer hierarchical validation (TRENDING/EMERGING/UNORDERED)
         // AutoStrat: STRAT_4EMA_LAYER (pullback-recovery on EMA zones)
         // ────────────────────────────────────────────────────────────
         cfg.AutoStrat           = STRAT_4EMA_LAYER;
         cfg.BiasFastID          = (int)ROLE_EMA3;
         cfg.BiasSlowID          = (int)ROLE_EMA4;
         
         cfg.P_Ema1              = 5; 
         cfg.P_Ema2              = 13; 
         cfg.P_Ema3              = 34; 
         cfg.P_Ema4              = 89;
         cfg.MaxSpread = (mode == RRM_SCALP) ? 2.0 : 4.0;
      }
      else  // BIAS_2EMA or BIAS_MANUAL
      {
         // ────────────────────────────────────────────────────────────
         // BRANCH 2: BIAS_2EMA (Traditional 2-EMA Bias)
         // Sub-branches: RRM_SCALP vs RRM_SWING
         // ────────────────────────────────────────────────────────────
         
         if(mode == RRM_SCALP)
         {
            // ························································
            // SUB-BRANCH 2A: RRM_SCALP (M1/M5/M15 timeframes)
            // Bias: EMA34 vs EMA89 (slower pair for stable bias)
            // Entry: STRAT_2EMA_CROSS_EMA (crossover-based entries)
            // ························································
            cfg.AutoStrat        = STRAT_2EMA_POSITION;
            cfg.BiasFastID       = (int)ROLE_EMA1;
            cfg.BiasSlowID       = (int)ROLE_EMA2;
            
            cfg.P_Ema1           = 5; 
            cfg.P_Ema2           = 13; 
            cfg.P_Ema3           = 34; 
            cfg.P_Ema4           = 89;
            cfg.MaxSpread        = 2.5;
         }
         else  // RRM_SWING (H1/H4/D1 and higher timeframes)
         {
            // ························································
            // SUB-BRANCH 2B: RRM_SWING (H1+ timeframes)
            // Bias: EMA34 vs EMA89 (stable trend direction)
            // Entry: STRAT_2EMA_CROSS_EMA (crossover-based entries)
            // Full 4-EMA structure: EMA5/13/34/89 for layer detection
            // ························································
            cfg.AutoStrat        = STRAT_2EMA_POSITION;
            cfg.BiasFastID       = (int)ROLE_EMA3;
            cfg.BiasSlowID       = (int)ROLE_EMA4;
            
            cfg.P_Ema1           = 5;
            cfg.P_Ema2           = 13;
            cfg.P_Ema3           = 34;
            cfg.P_Ema4           = 89;
            cfg.MaxSpread        = 5.0;
         }
      }
   
      // ================================================================
      // INDICATOR VOTING CONFIGURATION (Alphabetical)
      // ================================================================
      cfg.Ind_Adx_Enabled           = false;
      cfg.Ind_Atr_Enabled           = false;
      cfg.Ind_Bb_Enabled            = false;
      cfg.Ind_CandleBody_Enabled    = true;
      cfg.Ind_CI_Enabled            = false;
      cfg.Ind_VRC_Enabled           = false; // Enable ranging market protection
      cfg.Ind_Cci_Enabled           = false;
      cfg.Ind_Macd_Enabled          = true;
      cfg.Ind_Mfi_Enabled           = false;
      cfg.Ind_P123_Enabled          = false;
      cfg.Ind_Psar_Enabled          = true;
      cfg.Ind_Ross_Enabled          = false;
      cfg.Ind_Rsi_Enabled           = false;
      cfg.Ind_Sto_Enabled           = false;

      // BAR CLOSE (bcX) CONFIGURATION
      cfg.BarClose_Enabled          = true;              // ✅ Enable bcX
      cfg.BarClose_Mode             = BC_LAYER_AWARE;    // bcW/bcM/bcS adaptive
      cfg.BarClose_DefaultEMA       = ROLE_EMA1;         // Fallback
   
      cfg.VoteMode                  = VOTE_MODE_ALL;
      
      
      // ================================================================
      // INDICATOR PERIODS & THRESHOLDS (Alphabetical)
      // ================================================================
      
      // ADX (Average Directional Index)
      cfg.P_Adx                  = 14;
      cfg.T_Adx                  = 20.0;
      cfg.ADX_Mode               = ADX_MODE_PHASE_AWARE;
      cfg.ADX_Percentile         = 50.0;
      cfg.ADX_Lookback           = 100;
      cfg.ADX_Threshold_Accumulation = 12.0;
      cfg.ADX_Threshold_Trending     = 25.0;
      cfg.ADX_Threshold_Distribution = 18.0;
      
      // ATR (Average True Range) - Voting Indicator Only
      cfg.P_Atr                  = 14;
      cfg.ATR_VoteMinPips        = 5.0;
      cfg.ATR_VoteMaxPips        = 50.0;
      
      // Bollinger Bands
      cfg.P_Bb                   = 20;
      cfg.P_BbDev                = 2.0;
      
      // Candle Body
      cfg.CandleBody_AvgPeriod   = 15;
      cfg.CandleBody_MaxMult     = 3.5;
      cfg.CandleBody_CheckBars   = 2;
      cfg.Ind_CandleBody_Weight  = 1;

      // Choppiness Index (ranging market protection)
      cfg.CI_Period              = 14;
      cfg.CI_RangingThreshold    = 61.8;   // Standard threshold
      cfg.Ind_CI_Weight          = 1;
      
      // VRC (Volatility Regime Classifier)
      cfg.VRC_ATR_Period         = 14;
      cfg.VRC_Lookback           = 100;
      cfg.VRC_LowThreshold       = 33.0;
      cfg.Ind_VRC_Weight         = 1;
      
      // MACD
      cfg.MacdVoteMode           = MACD_ZERO_AND_CROSS;
      cfg.MacdRequireSlope       = true;
      cfg.MacdRequireDivergence  = true;
      cfg.MacdRequireHook        = false;
      cfg.MacdFreshBars          = 3;
      cfg.MacdSlopeMin           = 0.00001;
      
      // MFI (Money Flow Index)
      cfg.P_Mfi                  = 14;
      cfg.T_MfiOB                = 80.0;
      cfg.T_MfiOS                = 20.0;
      cfg.MfiMode                = MFI_ZONE_FILTER;
      
      // PSAR (Parabolic SAR)
      cfg.P_PsarStep             = 0.05;
      cfg.P_PsarMax              = 0.5;
      cfg.Vote_AllowPsarFlip     = true;
      cfg.Vote_PsarFlipDelay     = -1; // Persistent mode: dot on correct side = pass (no flip timer)
   
      // RSI (Relative Strength Index)
      cfg.P_Rsi                  = 14;
      cfg.T_RsiOB                = 70.0;
      cfg.T_RsiOS                = 30.0;
      cfg.RsiMode                = RSI_TREND_ABOVE_50;
      
      // Stochastic Oscillator
      cfg.P_StoK                 = 5;
      cfg.P_StoD                 = 3;
      cfg.P_StoSlow              = 3;
      cfg.T_StoOB                = 80.0;
      cfg.T_StoOS                = 20.0;
      cfg.StoMode                = STO_CROSS_SIGNAL;
      
      // ================================================================
      // PHASE DETECTION & LAYER FILTERING
      // ================================================================
      cfg.PhaseDetectionEnabled      = true;
      
      // ✅ FIX: Only enable strict layer touch evaluation if the strategy requires it
      cfg.EnableLayerDetection       = (cfg.AutoStrat == STRAT_4EMA_LAYER);
      
      cfg.BlockUnorderedPhase        = true;
      cfg.RequireMinPhaseConfirm     = true;
      cfg.MinPhaseConfirmBars        = 4;
      
      // Layer permissions per phase
      cfg.Trending_AllowWeakTrades   = true;
      cfg.Emerging_AllowWeakTrades   = true;
      cfg.Trending_AllowMediumTrades = true;
      cfg.Emerging_AllowMediumTrades = true;
      cfg.Trending_AllowStrongTrades = true;
      cfg.Emerging_AllowStrongTrades = false;
      
      // ================================================================
      // PULLBACK DETECTION GATES
      // ================================================================
      cfg.RequireRecoveryMomentum   = true;
   
      // Gate 2: Recovery momentum
      cfg.Gate_Recovery.mode        = GATE_SCALE_AUTO_TF;
      cfg.Gate_Recovery.value       = 1.0;
      cfg.RRM_Lookback              = (_Period <= PERIOD_M5) ? 5 : 7;
   
      // Gate 3: EMA divergence
      cfg.Gate_EmaDiv.mode          = GATE_SCALE_AUTO_TF;
      cfg.Gate_EmaDiv.value         = 1.0;
      cfg.RRM_MinDivPips            = 1.5;
      
      // Gate 4: Candle direction
      cfg.Gate_CandleDirection.mode  = GATE_SCALE_FIXED;
      cfg.Gate_CandleDirection.value = 1.0;
      
      // ================================================================
      // VOTE EVALUATION SETTINGS
      // ================================================================
      cfg.Vote_EvalShift            = 1;
      
      // ================================================================
      // RISK MANAGEMENT (Portfolio-level)
      // ================================================================
      cfg.RiskPercent               = 2.0;
      cfg.FixedLotSize              = 0.0;
      cfg.MaxTotalRisk              = 4.0;
      cfg.MaxOpenTrades             = 3;
      cfg.CountBEasZeroRisk         = true;
      
      // ================================================================
      // EXIT STRATEGY CONFIGURATION
      // ================================================================
      cfg.ExitProfile               = EXIT_PROFILE_RRM;
      cfg.SL_SwingPipsCushion       = GetRecommendedInitialSlCushionPips();
      cfg.SL_PsarPipsCushion        = GetRecommendedInitialSlCushionPips();
      cfg.TP_Enabled                = true;
      cfg.TrailMode                 = TRAIL_PSAR;
      cfg.PSAR_TrailCushionMode     = PSAR_CUSHION_PIPS;
      cfg.PSAR_TrailPipsCushion     = GetRecommendedTrailPsarCushionPips();
      cfg.BE_Mode                   = BE_MODE_R_MULTIPLE;
      
      // ================================================================
      // SL/TP STRATEGY MODES
      // ================================================================
      cfg.SLMode                    = SL_MODE_SWING;
      cfg.TPMode                    = TP_MODE_RR;
      cfg.FixedTPPips               = 40.0;
      cfg.SLPercent                 = 0.5;
      cfg.RRRatio                   = 3.0;
      cfg.SwingLookback             = 20;
   
      // ================================================================
      // FRACTAL/PSAR SL/TP DEFAULTS
      // ================================================================
      cfg.FractalPeriod             = 5;
      cfg.TPFractalOffset           = 1;

      // ================================================================
      // ADVANCED TRAILING TRIGGER DEFAULTS
      // ================================================================
      ENUM_TIMEFRAMES tf = (ENUM_TIMEFRAMES)_Period;
      cfg.TrailTrigger              = TRIGGER_BREAKEVEN;
      cfg.TrailDistancePips         = GetTFBasedCushion(tf);
      cfg.BEThresholdPips           = GetTFBasedCushion(tf);
      cfg.TrailProfitPercent        = 2.0; // ORG: 1.0
      cfg.TrailStepPips             = 5.0;
      cfg.TrailLockProfit           = true;
   
      // ================================================================
      // RRM DRAWDOWN PROTECTION
      // ================================================================
      cfg.RRM_EnableDrawdownProtection = Inp_RRM_EnableDrawdownProtection;
      cfg.RRM_MaxConsecutiveLosses     = Inp_RRM_MaxConsecutiveLosses;
      cfg.RRM_MaxTradesPerDay          = Inp_RRM_MaxTradesPerDay;
      cfg.RRM_MaxDailyDrawdownPct      = Inp_RRM_MaxDailyDrawdownPct;

      // ================================================================
      // SLOPE CALCULATION SETTINGS (Adaptive by Timeframe)
      // ================================================================

      // Determine lookback based on timeframe branch
      int slope_lookback = 1;
      if(tf >= PERIOD_H1)
         slope_lookback = 2; // Smoother for swing trading (H1+)

      cfg.SlopeLookbackBars      = slope_lookback;
      cfg.UseSlopeThreshold      = true;
      cfg.SlopeThresholdPips     = 0.0; // Use adaptive calculation
      cfg.SlopeThresholdAdaptive = true; // Auto: M5=0.4p, H1=1.2p, H4=2.0p
      cfg.SlopeMeasureMode       = SLOPE_MEASURE_PIPS;
      cfg.SlopeLookbackBars      = slope_lookback;
      cfg.UseSlopeThreshold      = true;
      cfg.SlopeThresholdPips     = 0.1; // Use adaptive calculation
      cfg.SlopeThresholdAdaptive = true; // Auto: M5=0.4p, H1=1.2p, H4=2.0p
      cfg.SlopeMeasureMode       = SLOPE_MEASURE_PIPS;

      // ════════════════════════════════════════════════════════════════
      // BAR CLOSE (bcX) CONFIGURATION
      // Formula: TS = Bias × LayerX × bcX × IndicatorX × FilterX
      // bcW: Close beyond EMA1 (LayerW) | bcM: EMA2 (LayerM) | bcS: EMA3 (LayerS)
      // ════════════════════════════════════════════════════════════════
      cfg.BarClose_Enabled       = true;              // ✅ Enable bcX
      cfg.BarClose_Mode          = BC_LAYER_AWARE;    // bcW/bcM/bcS adaptive (layer-aware)
      cfg.BarClose_DefaultEMA    = ROLE_EMA1;         // Fallback EMA for non-layer-aware modes
      cfg.BarClose_Enabled       = true;              // ✅ Enable bcX
      cfg.BarClose_Mode          = BC_LAYER_AWARE;    // bcW/bcM/bcS adaptive (layer-aware)
      cfg.BarClose_DefaultEMA    = ROLE_EMA1;         // Fallback EMA for non-layer-aware modes
      
      // ================================================================
      // POLICY A: RESTORE OPERATOR-CONTROLLED GATES
      // ================================================================
      cfg.MaxSpread              = op_MaxSpread;
      cfg.UseSpread              = op_UseSpread;
      cfg.UseTime                = op_UseTime;
      cfg.StartHr                = op_StartHr;
      cfg.EndHr                  = op_EndHr;
      cfg.UseNews                = op_UseNews;
      cfg.NewsPre                = op_NewsPre;
      cfg.NewsPost               = op_NewsPost;
      cfg.RiskPercent            = op_RiskPercent; // Policy A: restore user risk tolerance
      cfg.MaxOpenTrades          = op_MaxOpenTrades; // Policy A: restore user position limit
      cfg.MaxTotalRisk           = op_MaxTotalRisk; // Policy A: restore user portfolio risk cap

      return;
   }
   
   //+------------------------------------------------------------------+
   //| PRESET_TEST: Indicator & Component Testing Harness               |
   //+------------------------------------------------------------------+
   // PURPOSE:
   //   Sandbox environment for testing individual indicators, voting
   //   combinations, and strategy components in isolation.
   //
   // WHAT'S CONFIGURED:
   //   - Basic 2EMA bias structure (EMA34 vs EMA89)
   //   - Simple fixed-pip SL/TP
   //   - All indicators DISABLED by default
   //   - No phase detection, no layer detection
   //
   // WHAT YOU MUST CONFIGURE (via inputs):
   //   - Enable specific indicators to test (Inp_Ind_Macd_Enabled, etc.)
   //   - AutoStrat mode (STRAT_2EMA_POSITION vs STRAT_2EMA_CROSS_PRICE)
   //   - BarClose_Mode and target EMA
   //   - SL/TP distances
   //   - Voting thresholds
   //
   // NOT FOR:
   //   - Production trading (use PRESET_RRM)
   //   - Benchmarking (use PRESET_MA)
   //   - Strategy optimization (incomplete configuration)
   //
   // EXPECTED WORKFLOW:
   //   1. Select PRESET_TEST
   //   2. Enable 1-2 indicators via inputs
   //   3. Run backtest to see their impact
   //   4. Iterate: add more indicators, adjust settings
   //+------------------------------------------------------------------+
   
   if(preset == PRESET_TEST)
   {
      // ================================================================
      // PRESET_TEST: EA System Testing Mode
      // ================================================================
      //
      // FORMULA:
      //   TS = Bias × LayerX × bcX × IndicatorX × FilterX
      //
      // CONFIGURATION:
      //   Bias = BIAS_2EMA (simple position + slope)
      //   LayerX = DISABLED (returns 1)
      //   bcX = Fixed EMA1 check
      //   IndicatorX = MACD, CCI, PSAR, CandleBody
      //   FilterX = User-controlled
      //
      // ================================================================
   
      Print("═══════════════════════════════════════════════════════════");
      Print("  PRESET: TEST (EA System Testing Mode)");
      Print("═══════════════════════════════════════════════════════════");
   
      // ================================================================
      // CORE STRATEGY SETTINGS
      // ================================================================
      cfg.CloseOnReverse            = false;
      cfg.BiasEnabled               = true;     // true
      cfg.BiasMode                  = BIAS_2EMA;
      cfg.AutoStrat                 = STRAT_2EMA_POSITION;  // ✅ Compatible with BIAS_2EMA
      cfg.BiasFastID                = (int)ROLE_EMA2;
      cfg.BiasSlowID                = (int)ROLE_EMA4;
      cfg.MaType                    = METHOD_EMA;
      cfg.RequirePriceCross         = false;
      cfg.MABenchmarkStrict         = false;
      cfg.UseMACompatSizer          = false;
      
      // ================================================================
      // INDICATOR VOTING CONFIGURATION (Alphabetical)
      // Multiple indicators enabled for comprehensive EA testing
      // Admin can disable/enable as needed via individual inputs
      // ================================================================
      cfg.Ind_Adx_Enabled           = false;
      cfg.Ind_Atr_Enabled           = false;
      cfg.Ind_Bb_Enabled            = false;
      cfg.Ind_CandleBody_Enabled    = true;     // true
      cfg.Ind_CI_Enabled            = false;
      cfg.Ind_VRC_Enabled           = false;
      cfg.Ind_Cci_Enabled           = true;     // true
      cfg.Ind_Macd_Enabled          = true;     // true
      cfg.Ind_Mfi_Enabled           = false;
      cfg.Ind_P123_Enabled          = false;
      cfg.Ind_Psar_Enabled          = true;     // true
      cfg.Ind_Ross_Enabled          = false;
      cfg.Ind_Rsi_Enabled           = false;
      cfg.Ind_Sto_Enabled           = false;
   
      // BAR CLOSE (bcX) CONFIGURATION
      cfg.BarClose_Enabled          = true;           // ✅ Enable bc
      cfg.BarClose_Mode             = BC_BIAS_FAST;   // Fast
      cfg.BarClose_DefaultEMA       = ROLE_EMA3;      // Close vs EMA3
   
      cfg.VoteMode = VOTE_MODE_ALL;
      
      // ================================================================
      // INDICATOR PERIODS & THRESHOLDS (Alphabetical)
      // ================================================================
      
      // ADX (Average Directional Index)
      cfg.P_Adx                     = 14;
      cfg.T_Adx                     = 20.0;
      cfg.ADX_Mode                  = ADX_MODE_STATIC;
      cfg.ADX_Percentile            = 50.0;
      cfg.ADX_Lookback              = 100;
      cfg.ADX_Threshold_Accumulation   = 12.0;
      cfg.ADX_Threshold_Trending       = 25.0;
      cfg.ADX_Threshold_Distribution   = 18.0;
      
      // ATR (Average True Range) - Voting Indicator Only
      cfg.P_Atr                     = 14;
      cfg.ATR_VoteMinPips           = 5.0;
      cfg.ATR_VoteMaxPips           = 50.0;
      
      // Bollinger Bands
      // - BbMode options:
      //  - BB_TREND_FOLLOW (trade with breakouts)
      //  - BB_MEAN_REVERT (trade bounces)
      //  - BB_SQUEEZE_BREAKOUT (detect low volatility consolidation)
      cfg.P_Bb                      = 20;
      cfg.P_BbDev                   = 2.0;
      cfg.BbMode                    = BB_TREND_FOLLOW;
      
      // Candle Body
      cfg.CandleBody_AvgPeriod      = 5;      // ORG: 10     5
      cfg.CandleBody_MaxMult        = 3.0;    // ORG:  3.0   3.0
      cfg.CandleBody_CheckBars      = 3;      // ORG:  1     3
      cfg.Ind_CandleBody_Weight     = 1;      // ORG:  1

      // Choppiness Index
      cfg.CI_Period                 = 14;
      cfg.CI_RangingThreshold       = 61.8;
      cfg.Ind_CI_Weight             = 1;
      
      // VRC (Volatility Regime Classifier)
      cfg.VRC_ATR_Period            = 14;
      cfg.VRC_Lookback              = 100;
      cfg.VRC_LowThreshold          = 33.0;
      cfg.Ind_VRC_Weight            = 1;
      
      // CCI (Commodity Channel Index)
      cfg.P_Cci                     = 13;     // ORG: 14
      cfg.CciMode                   = CCI_TREND_ZERO;
      
      // EMA (Periods)
      cfg.P_Ema1                    = 5;      // ORG:  5
      cfg.P_Ema2                    = 13;     // ORG: 13
      cfg.P_Ema3                    = 34;     // ORG: 34
      cfg.P_Ema4                    = 89;     // ORG: 89
   
      // MACD (Moving Average Convergence Divergence)
      cfg.P_MacdFast                = 8;      // ORG: 12  8   5  5
      cfg.P_MacdSlow                = 13;     // ORG: 26  13  8  8
      cfg.P_MacdSig                 = 5;      // ORG: 9   8   5  3
      cfg.MacdVoteMode              = MACD_ZERO_AND_HIST;
      cfg.MacdRequireSlope          = true;   // ORG: false
      cfg.MacdRequireDivergence     = true;   // ORG: false
      cfg.MacdRequireHook           = false;  // ORG: false
      cfg.MacdFreshBars             = 10;     // ORG: 3
      cfg.MacdSlopeMin              = 0.000001; // ORG: 0.00001
   
      // MFI (Money Flow Index)
      cfg.P_Mfi                     = 14;
      cfg.T_MfiOB                   = 80.0;
      cfg.T_MfiOS                   = 20.0;
      cfg.MfiMode                   = MFI_ZONE_FILTER;
      
      // PSAR (Parabolic SAR)
      cfg.P_PsarStep                = 0.05;
      cfg.P_PsarMax                 = 0.5;
      cfg.Vote_AllowPsarFlip        = true;
      cfg.Vote_PsarFlipDelay        = -1;     // -1=Flip+Dot, 0=Flip only, 1,2,..=Flip+N only
   
      // RSI (Relative Strength Index)
      cfg.P_Rsi                     = 14;
      cfg.T_RsiOB                   = 70.0;
      cfg.T_RsiOS                   = 30.0;
      cfg.RsiMode                   = RSI_TREND_ABOVE_50;
      
      // Stochastic Oscillator
      cfg.P_StoK                    = 5;
      cfg.P_StoD                    = 3;
      cfg.P_StoSlow                 = 3;
      cfg.T_StoOB                   = 80.0;
      cfg.T_StoOS                   = 20.0;
      cfg.StoMode                   = STO_CROSS_SIGNAL;
      
      // ================================================================
      // PHASE DETECTION & LAYER FILTERING (All disabled for testing)
      // ================================================================
      cfg.PhaseDetectionEnabled     = false;
      cfg.EnableLayerDetection      = false;
      cfg.BlockUnorderedPhase       = false;
      cfg.RequireMinPhaseConfirm    = false;
      cfg.MinPhaseConfirmBars       = 0;
      
      // Layer permissions per phase
      cfg.Trending_AllowWeakTrades   = false;
      cfg.Emerging_AllowWeakTrades   = false;
      cfg.Trending_AllowMediumTrades = false;
      cfg.Emerging_AllowMediumTrades = false;
      cfg.Trending_AllowStrongTrades = false;
      cfg.Emerging_AllowStrongTrades = false;
      
      // ================================================================
      // PULLBACK DETECTION GATES (All disabled)
      // ================================================================
      cfg.RequireRecoveryMomentum   = false;   // ORG: false
   
      // Gate 2: Recovery momentum
      cfg.Gate_Recovery.mode        = GATE_SCALE_FIXED;
      cfg.Gate_Recovery.value       = 0.0;
      cfg.RRM_Lookback              = 0;
      
      // Gate 3: EMA divergence
      cfg.Gate_EmaDiv.mode          = GATE_SCALE_FIXED;
      cfg.Gate_EmaDiv.value         = 0.0;
      cfg.RRM_MinDivPips            = 0.0;
      
      // Gate 4: Candle direction
      cfg.Gate_CandleDirection.mode  = GATE_SCALE_FIXED;
      cfg.Gate_CandleDirection.value = 0.0;
      
      // ================================================================
      // VOTE EVALUATION SETTINGS
      // ================================================================
      cfg.Vote_EvalShift            = 1;
      
      // ================================================================
      // RISK MANAGEMENT (Portfolio-level)
      // ================================================================
      cfg.RiskPercent               = 2.0;    // ORG: 2.0
      cfg.FixedLotSize              = 0.0;
      cfg.MaxTotalRisk              = 6.0;
      cfg.MaxOpenTrades             = 3;
      cfg.CountBEasZeroRisk         = false;
      
      // ================================================================
      // EXIT STRATEGY CONFIGURATION
      // ================================================================
      if(op_ExitProfile == EXIT_PROFILE_NONE)
      {
         cfg.ExitProfile = EXIT_PROFILE_SIMPLE;
         // ════════════════════════════════════════════════════════════
         // TF-ADAPTIVE VALUE CALCULATION
         // ════════════════════════════════════════════════════════════
         ENUM_TIMEFRAMES tf = (ENUM_TIMEFRAMES)_Period;
         
         // ────────────────────────────────────────────────────────────
         // CUSHIONS: Extra buffer around market-determined levels
         // Used by: SL_MODE_PSAR_DOT, SL_MODE_SWING, TRAIL_PSAR
         // ────────────────────────────────────────────────────────────
         double sl_cushion    = GetRecommendedInitialSlCushionPips();   // M1=2p, H4=10p, D1=25p (JPY-adjusted)
         double trail_cushion = GetRecommendedTrailPsarCushionPips();   // M1=1p, H4=5p, D1=15p (JPY-adjusted)
         double be_cushion    = GetTFBasedCushion(tf);                  // M1=3p, H4=15p, D1=25p


         // ────────────────────────────────────────────────────────────
         // SWING LOOKBACK: Continuous bounding for ALL MT5 Timeframes
         // ────────────────────────────────────────────────────────────
         int swing_lookback = 20; // Default
         
         if      (tf <= PERIOD_M1)  swing_lookback = 10;
         else if (tf <= PERIOD_M5)  swing_lookback = 15;
         else if (tf <= PERIOD_M30) swing_lookback = 15;
         else if (tf <= PERIOD_H1)  swing_lookback = 20;
         else if (tf <= PERIOD_H4)  swing_lookback = 20;
         else                       swing_lookback = 30; // D1, W1, MN1

         // ────────────────────────────────────────────────────────────
         // FIXED TP DISTANCE: JPY-Aware and MT5 TF-Aware
         // ────────────────────────────────────────────────────────────
         double fixed_tp_pips = 40.0; // Default
         bool isJPY = (StringFind(_Symbol, "JPY") >= 0);
         
         if      (tf <= PERIOD_M1)  fixed_tp_pips = isJPY ? 15.0 : 10.0;
         else if (tf <= PERIOD_M5)  fixed_tp_pips = isJPY ? 20.0 : 15.0;
         else if (tf <= PERIOD_M30) fixed_tp_pips = isJPY ? 30.0 : 20.0;
         else if (tf <= PERIOD_H1)  fixed_tp_pips = isJPY ? 45.0 : 30.0;
         else if (tf <= PERIOD_H4)  fixed_tp_pips = isJPY ? 60.0 : 40.0;
         else                       fixed_tp_pips = isJPY ? 120.0: 80.0; // D1+


         // ════════════════════════════════════════════════════════════
         // APPLY EXIT MANAGEMENT VALUES
         // ════════════════════════════════════════════════════════════

         // ────────────────────────────────────────────────────────────
         // CORE SETTINGS
         // ────────────────────────────────────────────────────────────
         cfg.RRRatio                = 3.5;             // Risk:Reward = 2:1 (risk 50p to win 100p)
         cfg.SwingLookback          = swing_lookback;  // TF-adaptive (M1=10 bars, D1=30 bars)

         // ────────────────────────────────────────────────────────────
         // TAKE PROFIT
         // ────────────────────────────────────────────────────────────
         cfg.TP_Enabled             = true;
         cfg.TPMode                 = TP_MODE_RR;      // Use R:R ratio (dynamic TP)
         cfg.FixedTPPips            = fixed_tp_pips;   // TF-adaptive (M1=10p, H4=40p, D1=80p)
         cfg.TPFractalOffset        = 1;               // Fractal offset (if using TP_MODE_FRACTAL)
         cfg.FractalPeriod          = 5;               // Fractal period (if using TP_MODE_FRACTAL)

         // ────────────────────────────────────────────────────────────
         // BREAKEVEN
         // ────────────────────────────────────────────────────────────
         cfg.BE_Mode                = BE_MODE_R_MULTIPLE;
         cfg.RRM_BE_ProgressPct     = 5.0;            // Trigger at 10% progress toward TP
         cfg.RRM_BE_BufferPips      = be_cushion * 1; // ORG: * 0.5: TF-adaptive, tighter (H4=7.5p vs old 15p)
         cfg.BEThresholdPips        = 0.0;            // Not used (ProgressPct mode)

         // ────────────────────────────────────────────────────────────
         // TRAILING STOP
         // ────────────────────────────────────────────────────────────
         cfg.TrailMode              = TRAIL_PSAR;
         cfg.TrailTrigger           = TRIGGER_IMMEDIATE; // Start checking immediately
         cfg.RRM_TrailStartsAfterBE = false;          // ✅ Only trail after BE hit (safer!)
         cfg.TrailDistancePips      = 5.0;            // Not used (PSAR mode = dynamic)
         cfg.TrailProfitPercent     = 5.0;            // Not used (PSAR mode)
         cfg.TrailStepPips          = 0.0;            // Not used (PSAR mode)
         cfg.TrailLockProfit        = true;           // Never trail SL below entry

         // ────────────────────────────────────────────────────────────
         // STOP LOSS
         // ────────────────────────────────────────────────────────────
         cfg.SLMode                 = SL_MODE_PSAR_DOT;
         cfg.SL_SwingPipsCushion    = sl_cushion;     // TF+JPY adaptive (M1=2p, H4=10p)
         cfg.SL_PsarPipsCushion     = sl_cushion;     // TF+JPY adaptive (M1=2p, H4=10p)
         cfg.SLPercent              = 0.5;            // Not used (not using SL_MODE_PERCENT)

         // ────────────────────────────────────────────────────────────
         // PSAR TRAILING CONFIGURATION
         // ────────────────────────────────────────────────────────────
         cfg.PSAR_TrailCushionMode  = PSAR_CUSHION_PIPS;
         cfg.PSAR_TrailPipsCushion  = trail_cushion;   // TF+JPY adaptive (M1=1p, H4=5p, D1=15p)
      }
      
      // ================================================================
      // MA-SPECIFIC SETTINGS
      // ================================================================
      cfg.ma_h_shift                = 0;
      cfg.ma_v_shift                = 0;
      
      // ================================================================
      // RRM DRAWDOWN PROTECTION (Enabled for testing safety)
      // ================================================================
      cfg.RRM_EnableDrawdownProtection = false; // ✅ Enabled
      cfg.RRM_MaxConsecutiveLosses  = 5;        // ✅ 3: Stop after 3 losses
      cfg.RRM_MaxTradesPerDay       = 12;       // ✅ 12: Limit overtrading
      cfg.RRM_MaxDailyDrawdownPct   = 6.0;      // ✅ 6: Stop if -6% day

      // ================================================================
      // SLOPE CALCULATION SETTINGS (Minimal - Testing Mode)
      // ================================================================
      cfg.SlopeLookbackBars         = 1;        // Single bar (fast)
      cfg.UseSlopeThreshold         = false;    // No filtering
      cfg.SlopeThresholdPips        = 0.1;
      cfg.SlopeThresholdAdaptive    = false;
      cfg.SlopeMeasureMode          = SLOPE_MEASURE_PIPS;
      cfg.SlopeLookbackBars         = 1;        // Single bar (fast)
      cfg.UseSlopeThreshold         = false;    // No filtering
      cfg.SlopeThresholdPips        = 0.0;
      cfg.SlopeThresholdAdaptive    = false;
      cfg.SlopeMeasureMode          = SLOPE_MEASURE_PIPS;

      // ════════════════════════════════════════════════════════════════
      // BAR CLOSE (bcX) CONFIGURATION
      // Formula: TS = Bias × LayerX × bcX × IndicatorX × FilterX
      // CONFIGURATION: Fixed EMA1 check (not layer-aware for simpler testing)
      // ════════════════════════════════════════════════════════════════
      cfg.BarClose_Enabled          = true;           // ✅ Enable bcX
      cfg.BarClose_Mode             = BC_FIXED_EMA;   // Always check vs fixed EMA
      cfg.BarClose_DefaultEMA       = ROLE_EMA2;      // Close vs EMA1
      
      // ================================================================
      // POLICY A: RESTORE OPERATOR-CONTROLLED GATES
      // ================================================================
      cfg.MaxSpread                 = op_MaxSpread;
      cfg.UseSpread                 = op_UseSpread;
      cfg.UseTime                   = op_UseTime;
      cfg.StartHr                   = op_StartHr;
      cfg.EndHr                     = op_EndHr;
      cfg.UseNews                   = op_UseNews;
      cfg.NewsPre                   = op_NewsPre;
      cfg.NewsPost                  = op_NewsPost;
      cfg.RiskPercent               = op_RiskPercent;    // Policy A: restore user risk tolerance
      cfg.MaxOpenTrades             = op_MaxOpenTrades;  // Policy A: restore user position limit
      cfg.MaxTotalRisk              = op_MaxTotalRisk;   // Policy A: restore user portfolio risk cap

      return;
   }

}

//+------------------------------------------------------------------+
//| END OF FILE                                                      |
//+------------------------------------------------------------------+
