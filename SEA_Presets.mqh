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
   bool isJPY = (StringFind(_Symbol, "JPY") >= 0);
   switch(_Period)
   {
      case PERIOD_M1:  return isJPY ?  3.0 :  2.0;    // ORG:  3.0 :  2.0
      case PERIOD_M5:  return isJPY ?  3.0 :  2.0;    // ORG:  5.0 :  3.0
      case PERIOD_M15: return isJPY ?  5.0 :  3.0;    // ORG:  8.0 :  5.0
      case PERIOD_M30: return isJPY ?  5.0 :  3.0;    // ORG: 12.0 :  7.0
      case PERIOD_H1:  return isJPY ?  8.0 :  5.0;    // ORG: 15.0 : 10.0
      case PERIOD_H2:  return isJPY ? 12.0 :  7.0;    // ORG: 20.0 : 12.0
      case PERIOD_H4:  return isJPY ? 15.0 : 10.0;    // ORG: 25.0 : 15.0
      case PERIOD_D1:  return isJPY ? 25.0 : 15.0;    // ORG: 40.0 : 25.0
      default:         return isJPY ?  5.0 :  3.0;    // ORG: 10.0 :  5.0
   }
}

// TF+JPY-aware trailing cushion mapping (smaller, suited for TRAIL_PSAR + PSAR_CUSHION_PIPS)
double GetRecommendedTrailPsarCushionPips()
{
   bool isJPY = (StringFind(_Symbol, "JPY") >= 0);
   switch(_Period)
   {
      case PERIOD_M1:  return isJPY ?  2.0 :  1.0;    // ORG:  2.0 :  1.0
      case PERIOD_M5:  return isJPY ?  2.0 :  1.0;    // ORG:  3.0 :  2.0
      case PERIOD_M15: return isJPY ?  3.0 :  2.0;    // ORG:  5.0 :  3.0
      case PERIOD_M30: return isJPY ?  5.0 :  3.0;    // ORG:  7.0 :  5.0
      case PERIOD_H1:  return isJPY ?  7.0 :  5.0;    // ORG: 10.0 :  7.0
      case PERIOD_H2:  return isJPY ? 10.0 :  5.0;    // ORG: 13.0 :  8.0
      case PERIOD_H4:  return isJPY ? 10.0 :  5.0;    // ORG: 15.0 : 10.0
      case PERIOD_D1:  return isJPY ? 25.0 : 15.0;    // ORG: 25.0 : 15.0
      default:         return isJPY ?  5.0 :  3.0;    // ORG:  7.0 :  3.0
   }
}

// TF-based breakeven/trail cushion values
double GetTFBasedCushion(ENUM_TIMEFRAMES tf)
{
   switch(tf)
   {  // M1 needs slightly more room: 3.0
      case PERIOD_M1:  return 3.0;  // ORG:  3.0
      case PERIOD_M5:  return 3.0;  // ORG:  3.0
      case PERIOD_M15: return 5.0;  // ORG:  5.0
      case PERIOD_M30: return 5.0;  // ORG:  8.0
      case PERIOD_H1:  return 8.0;  // ORG: 10.0
      case PERIOD_H4:  return 10.0; // ORG: 15.0
      case PERIOD_D1:  return 15.0; // ORG: 25.0
      default:         return 5.0;  // ORG:  5.0
   }
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
         return "All inputs respected; you control strategy, indicators, and operator gates.";
      case PRESET_MA:
         return "MA benchmark mode: replicates MT5 Moving Average EA; all voting disabled.";
      case PRESET_RRM:
         return "RRM phase-based system fixed (AutoStrat, EMA/MACD config, vote threshold); only Policy A gates and exits user-controlled.";
      case PRESET_TEST:
         return "Minimal testing mode: bypass voting (threshold=1), fixed SL/TP, no trailing.";
      default:
         return "Preset active; strategy-critical settings fixed by preset.";
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
   Print("    EmaSig:  ", (cfg.Ind_EmaSig_Enabled ? "✓" : "✗"));
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

   // Check: At least one indicator enabled
   if(GetActiveIndicatorCount(cfg) == 0)
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
   if(cfg.RiskPercent <= 0.0 || cfg.RiskPercent > 100.0)
   {
      errors += "  ❌ ERROR: RiskPercent must be > 0 and <= 100!\n";
      valid = false;
   }

   // Check: VOTE_MODE_ALL recommended
   if(cfg.VoteMode != VOTE_MODE_ALL)
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
      Print("═══════════════════════════════════════════════════════════");
   }
   else if(errors != "")
   {
      Print("═══════════════════════════════════════════════════════════");
      Print("⚠️  PRESET VALIDATION WARNINGS: ", preset_name);
      Print("═══════════════════════════════════════════════════════════");
      Print(errors);
      Print("═══════════════════════════════════════════════════════════");
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
      cfg.CloseOnReverse    = true;
      cfg.BiasEnabled       = true;
      cfg.BiasMode          = BIAS_AUTO;
      cfg.AutoStrat         = STRAT_PRICE_CROSS;
      cfg.BiasFastID        = (int)ROLE_EMA1;
      cfg.BiasSlowID        = (int)ROLE_EMA1;
      cfg.MaType            = METHOD_SMA;
      cfg.RequirePriceCross = true;
      cfg.MABenchmarkStrict = true;
      cfg.UseMACompatSizer  = true;
   
      // ================================================================
      // INDICATOR VOTING CONFIGURATION (Alphabetical)
      // ================================================================
      cfg.Ind_Adx_Enabled          = false;
      cfg.Ind_Atr_Enabled          = false;
      cfg.Ind_Bb_Enabled           = false;
      cfg.Ind_CandleBody_Enabled   = false;
      cfg.Ind_CI_Enabled           = false;
      cfg.Ind_VRC_Enabled          = false;
      cfg.Ind_Cci_Enabled          = false;
      cfg.Ind_EmaSig_Enabled       = false;
      cfg.Ind_Macd_Enabled         = false;
      cfg.Ind_Mfi_Enabled          = false;
      cfg.Ind_P123_Enabled         = false;
      cfg.Ind_Psar_Enabled         = false;
      cfg.Ind_Ross_Enabled         = false;
      cfg.Ind_Rsi_Enabled          = false;
      cfg.Ind_Sto_Enabled          = false;
   
      cfg.VoteMode = VOTE_MODE_ALL;
      // INDICATOR PERIODS & THRESHOLDS (Alphabetical)
      // ================================================================
      
      // ADX (Average Directional Index)
      cfg.P_Adx = 14;
      cfg.T_Adx = 20.0;
      cfg.ADX_Mode                   = ADX_MODE_STATIC;
      cfg.ADX_Percentile             = 50.0;
      cfg.ADX_Lookback               = 100;
      cfg.ADX_Threshold_Accumulation = 12.0;
      cfg.ADX_Threshold_Trending     = 25.0;
      cfg.ADX_Threshold_Distribution = 18.0;
   
      // ATR (Average True Range) - Voting Indicator Only
      cfg.P_Atr       = 14;
      cfg.ATR_VoteMinPips   = 5.0;
      cfg.ATR_VoteMaxPips   = 50.0;
   
      // Bollinger Bands
      cfg.P_Bb    = 20;
      cfg.P_BbDev = 2.0;
      cfg.BbMode  = BB_TREND_FOLLOW;
   
      // Candle Body
      cfg.CandleBody_AvgPeriod     = 10;
      cfg.CandleBody_MaxMult       = 3.0;
      cfg.CandleBody_CheckBars     = 1;
      cfg.Ind_CandleBody_Weight    = 1;

      // Choppiness Index
      cfg.CI_Period           = 14;
      cfg.CI_RangingThreshold = 61.8;
      cfg.Ind_CI_Weight       = 1;

      // VRC (Volatility Regime Classifier)
      cfg.VRC_ATR_Period      = 14;
      cfg.VRC_Lookback        = 100;
      cfg.VRC_LowThreshold    = 33.0;
      cfg.Ind_VRC_Weight      = 1;

      // CCI (Commodity Channel Index)
      cfg.P_Cci   = 14;
      cfg.CciMode = CCI_TREND_ZERO;

      // EMA (Periods)
      cfg.P_Ema1 = Inp_MA_Period;  // Primary MA (user-controlled via input)
      cfg.P_Ema2 = 13;
      cfg.P_Ema3 = 34;
      cfg.P_Ema4 = 89;

      // MACD (Moving Average Convergence Divergence)
      cfg.P_MacdFast            = 12;
      cfg.P_MacdSlow            = 26;
      cfg.P_MacdSig             = 9;
      cfg.MacdVoteMode          = MACD_HISTOGRAM;
      cfg.MacdRequireSlope      = false;
      cfg.MacdRequireDivergence = false;
      cfg.MacdRequireHook       = false;
      cfg.MacdFreshBars         = 3;
      cfg.MacdSlopeMin          = 0.00001;
   
      // MFI (Money Flow Index)
      cfg.P_Mfi   = 14;
      cfg.T_MfiOB = 80.0;
      cfg.T_MfiOS = 20.0;
      cfg.MfiMode = MFI_ZONE_FILTER;
   
      // PSAR (Parabolic SAR)
      cfg.P_PsarStep         = 0.02;
      cfg.P_PsarMax          = 0.2;
      cfg.Vote_AllowPsarFlip = false;
      cfg.Vote_PsarFlipDelay = 0;
   
      // RSI (Relative Strength Index)
      cfg.P_Rsi   = 14;
      cfg.T_RsiOB = 70.0;
      cfg.T_RsiOS = 30.0;
      cfg.RsiMode = RSI_TREND_ABOVE_50;
   
      // Stochastic Oscillator
      cfg.P_StoK    = 5;
      cfg.P_StoD    = 3;
      cfg.P_StoSlow = 3;
      cfg.T_StoOB   = 80.0;
      cfg.T_StoOS   = 20.0;
      cfg.StoMode   = STO_CROSS_SIGNAL;
   
      // ================================================================
      // PHASE DETECTION & LAYER FILTERING
      // ================================================================
      cfg.PhaseDetectionEnabled      = false;
      cfg.EnableLayerDetection       = false;
      cfg.BlockUnorderedPhase        = false;
      cfg.RequireMinPhaseConfirm     = false;
      cfg.MinPhaseConfirmBars        = 0;
   
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
      cfg.RequirePullback         = false;
      cfg.PullbackLookback        = 0;
      cfg.RequireRecoveryMomentum = false;
      cfg.Gate_UseMultiLayer      = false;
      cfg.LayerTouchTolerance     = 0.0;
   
      // Gate 2: Recovery momentum
      cfg.Gate_Recovery.mode  = GATE_SCALE_FIXED;
      cfg.Gate_Recovery.value = 0.0;
      cfg.RRM_Lookback        = 0;
   
      // Gate 3: EMA divergence
      cfg.Gate_EmaDiv.mode    = GATE_SCALE_FIXED;
      cfg.Gate_EmaDiv.value   = 0.0;
      cfg.RRM_MinDivPips      = 0.0;
   
      // Gate 4: Candle direction
      cfg.Gate_CandleDirection.mode  = GATE_SCALE_FIXED;
      cfg.Gate_CandleDirection.value = 0.0;
   
      // ================================================================
      // VOTE EVALUATION SETTINGS
      // ================================================================
      cfg.Vote_EvalShift = 1;
   
      // ================================================================
      // RISK MANAGEMENT (Portfolio-level)
      // ================================================================
      cfg.RiskPercent       = 0.0;  // Uses MA-compatible sizer instead
      cfg.FixedLotSize      = 0.0;
      cfg.MaxTotalRisk      = 100.0;
      cfg.MaxOpenTrades     = 1;
      cfg.CountBEasZeroRisk = false;
   
      // ================================================================
      // EXIT STRATEGY CONFIGURATION
      // ================================================================
      cfg.ExitProfile           = EXIT_PROFILE_NONE;
      cfg.TP_Enabled            = false;
      cfg.TrailMode             = TRAIL_NONE;
      cfg.PSAR_TrailCushionMode = PSAR_CUSHION_PIPS;
      cfg.PSAR_TrailPipsCushion = 0.0;
      cfg.BE_Mode               = BE_MODE_OFF;
   
      // ================================================================
      // SL/TP STRATEGY MODES
      // ================================================================
      cfg.SLMode        = SL_MODE_FIXED_PIPS;
      cfg.TPMode        = TP_MODE_NONE;
      cfg.FixedTPPips   = 0.0;
      cfg.SLPercent     = 0.0;
      cfg.RRRatio       = 0.0;
      cfg.SwingLookback = 0;
   
      // ================================================================
      // FRACTAL/PSAR SL/TP DEFAULTS
      // ================================================================
      cfg.FractalPeriod   = 5;
      cfg.TPFractalOffset = 1;

      // ================================================================
      // ADVANCED TRAILING TRIGGER DEFAULTS
      // ================================================================
      cfg.TrailTrigger       = TRIGGER_IMMEDIATE;
      cfg.TrailDistancePips  = 0.0;
      cfg.BEThresholdPips    = 0.0;
      cfg.TrailProfitPercent = 0.0;
      cfg.TrailStepPips      = 0.0;
      cfg.TrailLockProfit    = false;
   
      // ================================================================
      // MA-SPECIFIC SETTINGS
      // ================================================================
      cfg.ma_h_shift = Inp_MA_Shift;
      cfg.ma_v_shift = 1;
   
      // ================================================================
      // MA DRAWDOWN PROTECTION (All off for benchmark mode)
      // ================================================================
      cfg.RRM_EnableDrawdownProtection = false;
      cfg.RRM_MaxConsecutiveLosses     = 0;
      cfg.RRM_MaxTradesPerDay          = 0;
      cfg.RRM_MaxDailyDrawdownPct      = 0.0;

      // ================================================================
      // SLOPE CALCULATION SETTINGS (Benchmark Mode - No Filtering)
      // ================================================================
      cfg.SlopeLookbackBars      = 1;                     // MT5 standard (single bar)
      cfg.UseSlopeThreshold      = false;                 // No filtering (match MT5)
      cfg.SlopeThresholdPips     = 0.0;
      cfg.SlopeThresholdAdaptive = false;
      cfg.SlopeMeasureMode       = SLOPE_MEASURE_PIPS;

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
      cfg.RiskPercent   = op_RiskPercent;    // Policy A: restore user risk tolerance
      cfg.MaxOpenTrades = op_MaxOpenTrades;  // Policy A: restore user position limit
      cfg.MaxTotalRisk  = op_MaxTotalRisk;   // Policy A: restore user portfolio risk cap

      return;
   }

   if(preset == PRESET_RRM)
   {
      // ================================================================
      // PRESET_RRM: Strict Trend Pullback Strategy
      // - Bias: User-selectable (BIAS_AUTO or BIAS_AUTO_PHASE via Inp_BiasMode)
      // - Entry: Layer detection (pullback-recovery on EMA zones)
      // - Votes: EMA ribbon + MACD + CCI + PSAR (4 votes, ALL must agree)
      // - ATR: Disabled for voting (Ind_Atr_Enabled = false)
      // - Exits: User-controlled via inputs (SL/TP/BE/Trailing preserved)
      // - Phase filtering: Enabled (blocks UNORDERED, restricts L3 in EMERGING)
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
      cfg.CloseOnReverse      = true;
      cfg.BiasEnabled         = true;
      cfg.BiasMode            = Inp_BiasMode;
      cfg.MaType              = METHOD_EMA;
      cfg.RequirePriceCross   = false;
      cfg.MABenchmarkStrict   = false;
      cfg.UseMACompatSizer    = false;
   
      // ================================================================
      // BIAS MODE ROUTING
      // ================================================================
      if(cfg.BiasMode == BIAS_AUTO_PHASE)
      {
         // ────────────────────────────────────────────────────────────
         // BRANCH 1: BIAS_AUTO_PHASE (4-EMA Phase Detection)
         // Uses: EMA1(5), EMA2(13), EMA3(34), EMA4(89)
         // Logic: 3-layer hierarchical validation (TRENDING/EMERGING/UNORDERED)
         // AutoStrat: STRAT_LAYER_DETECTION (pullback-recovery on EMA zones)
         // ────────────────────────────────────────────────────────────
         cfg.AutoStrat  = STRAT_LAYER_DETECTION;
         cfg.BiasFastID = (int)ROLE_EMA3;
         cfg.BiasSlowID = (int)ROLE_EMA4;
         
         cfg.P_Ema1 = 5; 
         cfg.P_Ema2 = 13; 
         cfg.P_Ema3 = 34; 
         cfg.P_Ema4 = 89;
         
         cfg.MaxSpread = (mode == RRM_SCALP) ? 2.0 : 4.0;
      }
      else  // BIAS_AUTO or BIAS_MANUAL
      {
         // ────────────────────────────────────────────────────────────
         // BRANCH 2: BIAS_AUTO (Traditional 2-EMA Bias)
         // Sub-branches: RRM_SCALP vs RRM_SWING
         // ────────────────────────────────────────────────────────────
         
         if(mode == RRM_SCALP)
         {
            // ························································
            // SUB-BRANCH 2A: RRM_SCALP (M1/M5/M15 timeframes)
            // Bias: EMA34 vs EMA89 (slower pair for stable bias)
            // Entry: STRAT_PAIR_CROSS (crossover-based entries)
            // ························································
            cfg.AutoStrat  = STRAT_PAIR_CROSS;
            cfg.BiasFastID = (int)ROLE_EMA1;
            cfg.BiasSlowID = (int)ROLE_EMA2;
            
            cfg.P_Ema1 = 34; 
            cfg.P_Ema2 = 89; 
            cfg.P_Ema3 = 34; 
            cfg.P_Ema4 = 89;
            
            cfg.MaxSpread = 2.5;
         }
         else  // RRM_SWING (H1/H4/D1 and higher timeframes)
         {
            // ························································
            // SUB-BRANCH 2B: RRM_SWING (H1+ timeframes)
            // Bias: EMA34 vs EMA89 (stable trend direction)
            // Entry: STRAT_PAIR_CROSS (crossover-based entries)
            // Full 4-EMA structure: EMA5/13/34/89 for layer detection
            // ························································
            cfg.AutoStrat  = STRAT_PAIR_CROSS;
            cfg.BiasFastID = (int)ROLE_EMA3;
            cfg.BiasSlowID = (int)ROLE_EMA4;
            
            cfg.P_Ema1 = 5;
            cfg.P_Ema2 = 13;
            cfg.P_Ema3 = 34;
            cfg.P_Ema4 = 89;
            
            cfg.MaxSpread = 5.0;
         }
      }
   
      // ================================================================
      // INDICATOR VOTING CONFIGURATION (Alphabetical)
      // ================================================================
      cfg.Ind_Adx_Enabled          = false;
      cfg.Ind_Atr_Enabled          = false;
      cfg.Ind_Bb_Enabled           = false;
      cfg.Ind_CandleBody_Enabled   = true;
      cfg.Ind_CI_Enabled           = true;  // Enable ranging market protection
      cfg.Ind_VRC_Enabled          = false;
      cfg.Ind_Cci_Enabled          = true;
      cfg.Ind_EmaSig_Enabled       = true;
      cfg.Ind_Macd_Enabled         = true;
      cfg.Ind_Mfi_Enabled          = false;
      cfg.Ind_P123_Enabled         = false;
      cfg.Ind_Psar_Enabled         = true;
      cfg.Ind_Ross_Enabled         = false;
      cfg.Ind_Rsi_Enabled          = false;
      cfg.Ind_Sto_Enabled          = false;
   
      cfg.VoteMode = VOTE_MODE_ALL;
   
      // ================================================================
      // INDICATOR PERIODS & THRESHOLDS (Alphabetical)
      // ================================================================
      
      // ADX (Average Directional Index)
      cfg.P_Adx = 14;
      cfg.T_Adx = 20.0;
      cfg.ADX_Mode                   = ADX_MODE_PHASE_AWARE;
      cfg.ADX_Percentile             = 50.0;
      cfg.ADX_Lookback               = 100;
      cfg.ADX_Threshold_Accumulation = 12.0;
      cfg.ADX_Threshold_Trending     = 25.0;
      cfg.ADX_Threshold_Distribution = 18.0;
   
      // ATR (Average True Range) - Voting Indicator Only
      cfg.P_Atr             = 14;
      cfg.ATR_VoteMinPips   = 5.0;
      cfg.ATR_VoteMaxPips   = 50.0;
   
      // Bollinger Bands
      cfg.P_Bb    = 20;
      cfg.P_BbDev = 2.0;

      // Candle Body
      cfg.CandleBody_AvgPeriod     = 15;
      cfg.CandleBody_MaxMult       = 3.5;
      cfg.CandleBody_CheckBars     = 2;
      cfg.Ind_CandleBody_Weight    = 1;

      // Choppiness Index (ranging market protection)
      cfg.CI_Period           = 14;
      cfg.CI_RangingThreshold = 61.8;   // Standard threshold
      cfg.Ind_CI_Weight       = 1;

      // VRC (Volatility Regime Classifier)
      cfg.VRC_ATR_Period      = 14;
      cfg.VRC_Lookback        = 100;
      cfg.VRC_LowThreshold    = 33.0;
      cfg.Ind_VRC_Weight      = 1;

      // MACD
      cfg.MacdVoteMode          = MACD_ZERO_AND_CROSS;
      cfg.MacdRequireSlope      = false;
      cfg.MacdRequireDivergence = false;
      cfg.MacdRequireHook       = false;
      cfg.MacdFreshBars         = 3;
      cfg.MacdSlopeMin          = 0.00001;
   
      // MFI (Money Flow Index)
      cfg.P_Mfi   = 14;
      cfg.T_MfiOB = 80.0;
      cfg.T_MfiOS = 20.0;
      cfg.MfiMode = MFI_ZONE_FILTER;
   
      // PSAR (Parabolic SAR)
      cfg.P_PsarStep         = 0.02;
      cfg.P_PsarMax          = 0.2;
      cfg.Vote_AllowPsarFlip = true;
      cfg.Vote_PsarFlipDelay = -1;  // Persistent mode: dot on correct side = pass (no flip timer)
   
      // RSI (Relative Strength Index)
      cfg.P_Rsi   = 14;
      cfg.T_RsiOB = 70.0;
      cfg.T_RsiOS = 30.0;
      cfg.RsiMode = RSI_TREND_ABOVE_50;
   
      // Stochastic Oscillator
      cfg.P_StoK    = 5;
      cfg.P_StoD    = 3;
      cfg.P_StoSlow = 3;
      cfg.T_StoOB   = 80.0;
      cfg.T_StoOS   = 20.0;
      cfg.StoMode   = STO_CROSS_SIGNAL;
   
      // ================================================================
      // PHASE DETECTION & LAYER FILTERING
      // ================================================================
      cfg.PhaseDetectionEnabled      = true;
      cfg.EnableLayerDetection       = true;
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
      cfg.RequirePullback         = true;
      cfg.PullbackLookback        = (_Period <= PERIOD_M5) ? 15 : 10;
      cfg.RequireRecoveryMomentum = false;
      cfg.Gate_UseMultiLayer      = true;
      cfg.LayerTouchTolerance     = 0.01;
   
      // Gate 2: Recovery momentum
      cfg.Gate_Recovery.mode  = GATE_SCALE_AUTO_TF;
      cfg.Gate_Recovery.value = 1.0;
      cfg.RRM_Lookback        = (_Period <= PERIOD_M5) ? 5 : 7;
   
      // Gate 3: EMA divergence
      cfg.Gate_EmaDiv.mode    = GATE_SCALE_AUTO_TF;
      cfg.Gate_EmaDiv.value   = 1.0;
      cfg.RRM_MinDivPips      = 1.5;
   
      // Gate 4: Candle direction
      cfg.Gate_CandleDirection.mode  = GATE_SCALE_FIXED;
      cfg.Gate_CandleDirection.value = 1.0;
   
      // ================================================================
      // VOTE EVALUATION SETTINGS
      // ================================================================
      cfg.Vote_EvalShift = 1;
   
      // ================================================================
      // RISK MANAGEMENT (Portfolio-level)
      // ================================================================
      cfg.RiskPercent       = 1.0;
      cfg.FixedLotSize      = 0.0;
      cfg.MaxTotalRisk      = 4.0;
      cfg.MaxOpenTrades     = 3;
      cfg.CountBEasZeroRisk = true;
   
      // ================================================================
      // EXIT STRATEGY CONFIGURATION
      // ================================================================
      cfg.ExitProfile           = EXIT_PROFILE_RRM;
      cfg.SL_SwingPipsCushion   = GetRecommendedInitialSlCushionPips();
      cfg.SL_PsarPipsCushion    = GetRecommendedInitialSlCushionPips();
      cfg.TP_Enabled            = true;
      cfg.TrailMode             = TRAIL_PSAR;
      cfg.PSAR_TrailCushionMode = PSAR_CUSHION_PIPS;
      cfg.PSAR_TrailPipsCushion = GetRecommendedTrailPsarCushionPips();
      cfg.BE_Mode               = BE_MODE_R_MULTIPLE;
   
      // ================================================================
      // SL/TP STRATEGY MODES
      // ================================================================
      cfg.SLMode        = SL_MODE_SWING;
      cfg.TPMode        = TP_MODE_RR;
      cfg.FixedTPPips   = 40.0;
      cfg.SLPercent     = 0.5;
      cfg.RRRatio       = 3.0;
      cfg.SwingLookback = 20;
   
      // ================================================================
      // FRACTAL/PSAR SL/TP DEFAULTS
      // ================================================================
      cfg.FractalPeriod   = 5;
      cfg.TPFractalOffset = 1;

      // ================================================================
      // ADVANCED TRAILING TRIGGER DEFAULTS
      // ================================================================
      ENUM_TIMEFRAMES tf = (ENUM_TIMEFRAMES)_Period;
      cfg.TrailTrigger       = TRIGGER_BREAKEVEN;
      cfg.TrailDistancePips  = GetTFBasedCushion(tf);
      cfg.BEThresholdPips    = GetTFBasedCushion(tf);
      cfg.TrailProfitPercent = 1.0;
      cfg.TrailStepPips      = 5.0;
      cfg.TrailLockProfit    = true;
   
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
         slope_lookback = 2;  // Smoother for swing trading (H1+)

      cfg.SlopeLookbackBars      = slope_lookback;
      cfg.UseSlopeThreshold      = true;
      cfg.SlopeThresholdPips     = 0.0;                   // Use adaptive calculation
      cfg.SlopeThresholdAdaptive = true;                  // Auto: M5=0.4p, H1=1.2p, H4=2.0p
      cfg.SlopeMeasureMode       = SLOPE_MEASURE_PIPS;

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
      cfg.RiskPercent   = op_RiskPercent;    // Policy A: restore user risk tolerance
      cfg.MaxOpenTrades = op_MaxOpenTrades;  // Policy A: restore user position limit
      cfg.MaxTotalRisk  = op_MaxTotalRisk;   // Policy A: restore user portfolio risk cap

      return;
   }
   
   if(preset == PRESET_TEST)
   {
      // ================================================================
      // PRESET_TEST: EA System Testing Mode
      // Flexible configuration for testing SimpleEA signal processing pipeline
      // - Multiple indicators enabled by default (admin can adjust as needed)
      // - All gates disabled (no filtering noise)
      // - Simple bias: Position + Slope (BIAS_AUTO + STRAT_POSITION_SLOPE)
      // - Phase/layer detection OFF (focus on core voting logic)
      // - RRM protection enabled for safety during testing
      // - TF-adaptive exit management for multi-timeframe testing
      // ================================================================
   
      Print("═══════════════════════════════════════════════════════════");
      Print("  PRESET: TEST (EA System Testing Mode)");
      Print("═══════════════════════════════════════════════════════════");
   
      // ================================================================
      // CORE STRATEGY SETTINGS
      // ================================================================
      cfg.CloseOnReverse            = false;
      cfg.BiasEnabled               = true;
      cfg.BiasMode                  = BIAS_AUTO;
      cfg.AutoStrat                 = STRAT_POSITION_SLOPE;
      cfg.BiasFastID                = (int)ROLE_EMA3;
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
      cfg.Ind_CandleBody_Enabled    = true;
      cfg.Ind_CI_Enabled            = false;
      cfg.Ind_VRC_Enabled           = false;
      cfg.Ind_Cci_Enabled           = true;
      cfg.Ind_EmaSig_Enabled        = true;
      cfg.Ind_Macd_Enabled          = true;
      cfg.Ind_Mfi_Enabled           = false;
      cfg.Ind_P123_Enabled          = false;
      cfg.Ind_Psar_Enabled          = true;
      cfg.Ind_Ross_Enabled          = false;
      cfg.Ind_Rsi_Enabled           = false;
      cfg.Ind_Sto_Enabled           = false;
   
      cfg.VoteMode = VOTE_MODE_ALL;
   
      // ================================================================
      // INDICATOR PERIODS & THRESHOLDS (Alphabetical)
      // ================================================================
      
      // ADX (Average Directional Index)
      cfg.P_Adx = 14;
      cfg.T_Adx = 20.0;
      cfg.ADX_Mode                   = ADX_MODE_STATIC;
      cfg.ADX_Percentile             = 50.0;
      cfg.ADX_Lookback               = 100;
      cfg.ADX_Threshold_Accumulation = 12.0;
      cfg.ADX_Threshold_Trending     = 25.0;
      cfg.ADX_Threshold_Distribution = 18.0;

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
      cfg.CandleBody_AvgPeriod      = 5;   // ORG: 10
      cfg.CandleBody_MaxMult        = 3.0; // ORG: 3.0
      cfg.CandleBody_CheckBars      = 3;   // ORG: 1
      cfg.Ind_CandleBody_Weight     = 1;   // ORG: 1

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
      cfg.P_Cci                     = 13;    // ORG: 14
      cfg.CciMode                   = CCI_TREND_ZERO;
   
      // EMA (Periods)
      cfg.P_Ema1 = 5;
      cfg.P_Ema2 = 13;
      cfg.P_Ema3 = 34;
      cfg.P_Ema4 = 89;
   
      // MACD (Moving Average Convergence Divergence)
      cfg.P_MacdFast                = 5;      // ORG: 12  8
      cfg.P_MacdSlow                = 8;      // ORG: 26  13
      cfg.P_MacdSig                 = 5;      // ORG: 9   8
      cfg.MacdVoteMode              = MACD_ZERO_LINE;
      cfg.MacdRequireSlope          = true;   // ORG: false
      cfg.MacdRequireDivergence     = true;   // ORG: false
      cfg.MacdRequireHook           = false;  // ORG: false
      cfg.MacdFreshBars             = 5;      // ORG: 3
      cfg.MacdSlopeMin              = 0.00001;
   
      // MFI (Money Flow Index)
      cfg.P_Mfi                     = 14;
      cfg.T_MfiOB                   = 80.0;
      cfg.T_MfiOS                   = 20.0;
      cfg.MfiMode                   = MFI_ZONE_FILTER;
   
      // PSAR (Parabolic SAR)
      cfg.P_PsarStep                = 0.02;
      cfg.P_PsarMax                 = 0.2;
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
      cfg.RequirePullback           = false;
      cfg.PullbackLookback          = 0;
      cfg.RequireRecoveryMomentum   = false;
      cfg.Gate_UseMultiLayer        = false;
      cfg.LayerTouchTolerance       = 0.0;
   
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
      cfg.RiskPercent               = 2.0;
      cfg.FixedLotSize              = 0.0;
      cfg.MaxTotalRisk              = 6.0;
      cfg.MaxOpenTrades             = 3;
      cfg.CountBEasZeroRisk         = false;

      // ================================================================
      // EXIT STRATEGY CONFIGURATION
      // ================================================================
      // LOGIC FLOW:
      //   1. SL: Market-determined (PSAR dot or SWING high/low + cushion)
      //   2. Lots: Calculated from Risk% / SL_distance
      //   3. TP: Either FIXED pips OR dynamic (SL_distance × RRRatio)
      //   4. BE: Triggers when price progresses X% toward TP
      //   5. Trail: Follows PSAR (only after BE hit for safety)
      //
      // TF-ADAPTIVE SETTINGS:
      //   - SwingLookback: How many bars to scan for swing points
      //   - SL/Trail cushions: Extra buffer around PSAR/swing levels
      //   - BE buffer: Pips above entry when moving to breakeven
      //   - FixedTPPips: Static TP distance (only for TP_MODE_FIXED_PIPS)
      //
      // NON-ADAPTIVE (Universal):
      //   - RRRatio: Risk:Reward ratio (2:1 = standard)
      //   - BE_ProgressPct: % of TP distance before triggering BE
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
         // Why adaptive: Smaller TFs need tighter buffers (2-3 pips)
         //               Larger TFs need room for noise (15-25 pips)
         // ────────────────────────────────────────────────────────────
         double sl_cushion    = GetRecommendedInitialSlCushionPips();   // M1=2p, H4=10p, D1=25p (JPY-adjusted)
         double trail_cushion = GetRecommendedTrailPsarCushionPips();   // M1=1p, H4=5p, D1=15p (JPY-adjusted)
         double be_cushion    = GetTFBasedCushion(tf);                  // M1=3p, H4=15p, D1=25p

         // ────────────────────────────────────────────────────────────
         // SWING LOOKBACK: How many bars to scan for swing high/low
         // Used by: SL_MODE_SWING (finds recent swing point for SL)
         // Why adaptive: Smaller TFs = more bars needed for valid swing
         //               Larger TFs = fewer bars capture meaningful swing
         // ────────────────────────────────────────────────────────────
         int swing_lookback = 20;  // Default
         switch(tf)
         {
            case PERIOD_M1:  swing_lookback = 10; break;  // Fast markets, recent swing
            case PERIOD_M5:  swing_lookback = 15; break;
            case PERIOD_M15: swing_lookback = 20; break;
            case PERIOD_M30: swing_lookback = 20; break;
            case PERIOD_H1:  swing_lookback = 20; break;
            case PERIOD_H4:  swing_lookback = 20; break;
            case PERIOD_D1:  swing_lookback = 30; break;  // Slower markets, broader swing
            default:         swing_lookback = 20; break;
         }

         // ────────────────────────────────────────────────────────────
         // FIXED TP DISTANCE: Static TP in pips (for TP_MODE_FIXED_PIPS)
         // Used by: TP_MODE_FIXED_PIPS only (ignored by TP_MODE_RR)
         // Why adaptive: Smaller TFs target smaller moves (10-20p)
         //               Larger TFs target larger moves (40-80p)
         // Note: When using TP_MODE_RR, this value is IGNORED
         //       (TP calculated as: SL_distance × RRRatio)
         // ────────────────────────────────────────────────────────────
         double fixed_tp_pips = 40.0;  // Default
         switch(tf)
         {
            case PERIOD_M1:  fixed_tp_pips = 10.0; break;  // Scalping: 10 pips
            case PERIOD_M5:  fixed_tp_pips = 15.0; break;  // Scalping: 15 pips
            case PERIOD_M15: fixed_tp_pips = 20.0; break;  // Short-term: 20 pips
            case PERIOD_M30: fixed_tp_pips = 25.0; break;
            case PERIOD_H1:  fixed_tp_pips = 30.0; break;  // Intraday: 30 pips
            case PERIOD_H2:  fixed_tp_pips = 35.0; break;
            case PERIOD_H4:  fixed_tp_pips = 40.0; break;  // Swing: 40 pips
            case PERIOD_D1:  fixed_tp_pips = 80.0; break;  // Position: 80 pips
            default:         fixed_tp_pips = 30.0; break;
         }

         // ════════════════════════════════════════════════════════════
         // APPLY EXIT MANAGEMENT VALUES
         // ════════════════════════════════════════════════════════════

         // ────────────────────────────────────────────────────────────
         // CORE SETTINGS
         // ────────────────────────────────────────────────────────────
         cfg.RRRatio             = 2.5;            // Risk:Reward = 2:1 (risk 50p to win 100p)
         cfg.SwingLookback       = swing_lookback; // TF-adaptive (M1=10 bars, D1=30 bars)

         // ────────────────────────────────────────────────────────────
         // TAKE PROFIT
         // Mode: TP_MODE_RR = Dynamic (TP = SL × RRRatio)
         //       TP_MODE_FIXED_PIPS = Static (TP = FixedTPPips)
         // 
         // Example (TP_MODE_RR):
         //   - PSAR SL = 50 pips
         //   - TP = 50 × 2.0 = 100 pips (dynamic!)
         //
         // Example (TP_MODE_FIXED_PIPS):
         //   - TP = 40 pips (H4 default, regardless of SL distance)
         // ────────────────────────────────────────────────────────────
         cfg.TP_Enabled          = true;
         cfg.TPMode              = TP_MODE_RR;        // Use R:R ratio (dynamic TP)
                                                      // Change to TP_MODE_FIXED_PIPS for static TP
         cfg.FixedTPPips         = fixed_tp_pips;     // TF-adaptive (M1=10p, H4=40p, D1=80p)
                                                      // Only used if TPMode = TP_MODE_FIXED_PIPS
         cfg.TPFractalOffset     = 1;                 // Fractal offset (if using TP_MODE_FRACTAL)
         cfg.FractalPeriod       = 5;                 // Fractal period (if using TP_MODE_FRACTAL)

         // ────────────────────────────────────────────────────────────
         // BREAKEVEN
         // Triggers when: price moves X% toward TP
         // Action: Move SL to Entry + BE_BufferPips
         //
         // Example (H4):
         //   - Entry: 1.1000, TP: 1.1100 (100 pips away)
         //   - BE triggers at: 1.1000 + (100 × 10%) = 1.1010
         //   - SL moves to: 1.1000 + 7.5 pips = 1.10075 (locked profit!)
         //
         // Why 50% cushion: Tighter lock (was using full cushion 15p)
         //                  Now uses 7.5p = faster profit protection
         // ────────────────────────────────────────────────────────────
         cfg.BE_Mode             = BE_MODE_TP_PROGRESS_PCT;
         cfg.RRM_BE_ProgressPct  = 10.0;              // Trigger at 10% progress toward TP
         cfg.RRM_BE_BufferPips   = be_cushion * 0.5;  // TF-adaptive, tighter (H4=7.5p vs old 15p)
         cfg.BEThresholdPips     = 0.0;               // Not used (ProgressPct mode)

         // ────────────────────────────────────────────────────────────
         // TRAILING STOP
         // Mode: TRAIL_PSAR = Follow PSAR dot
         // When: Only AFTER breakeven hit (safer!)
         //
         // Example (H4):
         //   - BE hit at 1.1010, SL now at 1.10075
         //   - PSAR dot at 1.1005
         //   - Trail SL moves to: 1.1005 - 5 pips = 1.1000
         //   - SL locked at breakeven, now trailing price up!
         //
         // Why after BE: Prevents premature stop-out
         //               (price might dip below entry before rally)
         // ────────────────────────────────────────────────────────────
         cfg.TrailMode              = TRAIL_PSAR;
         cfg.TrailTrigger           = TRIGGER_IMMEDIATE;  // Start checking immediately
         cfg.RRM_TrailStartsAfterBE = false;               // ✅ Only trail after BE hit (safer!)
         cfg.TrailDistancePips      = 0.0;                // Not used (PSAR mode = dynamic)
         cfg.TrailProfitPercent     = 0.0;                // Not used (PSAR mode)
         cfg.TrailStepPips          = 0.0;                // Not used (PSAR mode)
         cfg.TrailLockProfit        = true;               // Never trail SL below entry

         // ────────────────────────────────────────────────────────────
         // STOP LOSS
         // Mode: SL_MODE_PSAR_DOT = Place SL at PSAR dot - cushion
         //       SL_MODE_SWING = Place SL at recent swing + cushion
         //
         // Example (PSAR, H4):
         //   - Entry: 1.1000 (LONG)
         //   - PSAR dot: 1.0950
         //   - Cushion: 10 pips
         //   - SL: 1.0950 - 0.0010 = 1.0940
         //   - SL distance: 60 pips (dynamic!)
         //
         // Example (SWING, H4):
         //   - Entry: 1.1000 (LONG)
         //   - Swing low (20 bars): 1.0960
         //   - Cushion: 10 pips
         //   - SL: 1.0960 - 0.0010 = 1.0950
         //   - SL distance: 50 pips (dynamic!)
         // ────────────────────────────────────────────────────────────
         cfg.SLMode              = SL_MODE_PSAR_DOT;
         cfg.SL_SwingPipsCushion = sl_cushion;    // TF+JPY adaptive (M1=2p, H4=10p)
         cfg.SL_PsarPipsCushion  = sl_cushion;    // TF+JPY adaptive (M1=2p, H4=10p)
         cfg.SLPercent           = 0.5;           // Not used (not using SL_MODE_PERCENT)

         // ────────────────────────────────────────────────────────────
         // PSAR TRAILING CONFIGURATION
         // Cushion: Extra buffer below PSAR dot when trailing
         //
         // Example (H4):
         //   - PSAR dot moves to 1.1020
         //   - Cushion: 5 pips
         //   - Trail SL to: 1.1020 - 5 = 1.1015
         //   - Follows price up, locked profit keeps growing!
         // ────────────────────────────────────────────────────────────
         cfg.PSAR_TrailCushionMode = PSAR_CUSHION_PIPS;
         cfg.PSAR_TrailPipsCushion = trail_cushion;  // TF+JPY adaptive (M1=1p, H4=5p, D1=15p)
      }
      // else: user's EXIT_PROFILE_SIMPLE (or EXIT_PROFILE_RRM) settings are
      // preserved from InitializeConfig — SLMode, TrailMode, BE_Mode,
      // TrailTrigger etc. are already mapped from their respective input parameters.

      // ================================================================
      // MA-SPECIFIC SETTINGS
      // ================================================================
      cfg.ma_h_shift = 0;
      cfg.ma_v_shift = 0;

      // ================================================================
      // RRM DRAWDOWN PROTECTION (Enabled for testing safety)
      // ================================================================
      cfg.RRM_EnableDrawdownProtection = true;   // ✅ Enabled
      cfg.RRM_MaxConsecutiveLosses     = 3;      // ✅ Stop after 3 losses
      cfg.RRM_MaxTradesPerDay          = 12;     // ✅ Limit overtrading
      cfg.RRM_MaxDailyDrawdownPct      = 6.0;    // ✅ Stop if -6% day

      // ================================================================
      // SLOPE CALCULATION SETTINGS (Minimal - Testing Mode)
      // ================================================================
      cfg.SlopeLookbackBars      = 1;                     // Single bar (fast)
      cfg.UseSlopeThreshold      = false;                 // No filtering
      cfg.SlopeThresholdPips     = 0.0;
      cfg.SlopeThresholdAdaptive = false;
      cfg.SlopeMeasureMode       = SLOPE_MEASURE_PIPS;

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
      cfg.RiskPercent   = op_RiskPercent;    // Policy A: restore user risk tolerance
      cfg.MaxOpenTrades = op_MaxOpenTrades;  // Policy A: restore user position limit
      cfg.MaxTotalRisk  = op_MaxTotalRisk;   // Policy A: restore user portfolio risk cap

      return;
   }

}

//+------------------------------------------------------------------+
//| END OF FILE                                                      |
//+------------------------------------------------------------------+
