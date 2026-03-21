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

#include <RRMS\SEA_Config.mqh>

// TF+JPY-aware initial SL cushion mapping (larger, suited for SL_PSAR_PIPS / SL_SWING_HIGHLOW)
double GetRecommendedInitialSlCushionPips()
{
   bool isJPY = (StringFind(_Symbol, "JPY") >= 0);
   switch(_Period)
   {
      case PERIOD_M1:  return isJPY ?  3.0 :  2.0;
      case PERIOD_M5:  return isJPY ?  5.0 :  3.0;
      case PERIOD_M15: return isJPY ?  8.0 :  5.0;
      case PERIOD_M30: return isJPY ? 12.0 :  7.0;
      case PERIOD_H1:  return isJPY ? 15.0 : 10.0;
      case PERIOD_H2:  return isJPY ? 20.0 : 12.0;
      case PERIOD_H4:  return isJPY ? 25.0 : 15.0;
      case PERIOD_D1:  return isJPY ? 40.0 : 25.0;
      default:         return isJPY ? 10.0 :  5.0;
   }
}

// TF+JPY-aware trailing cushion mapping (smaller, suited for TRAIL_PSAR + PSAR_CUSHION_PIPS)
double GetRecommendedTrailPsarCushionPips()
{
   bool isJPY = (StringFind(_Symbol, "JPY") >= 0);
   switch(_Period)
   {
      case PERIOD_M1:  return isJPY ?  2.0 :  1.0;
      case PERIOD_M5:  return isJPY ?  3.0 :  2.0;
      case PERIOD_M15: return isJPY ?  5.0 :  3.0;
      case PERIOD_M30: return isJPY ?  7.0 :  5.0;
      case PERIOD_H1:  return isJPY ? 10.0 :  7.0;
      case PERIOD_H2:  return isJPY ? 13.0 :  8.0;
      case PERIOD_H4:  return isJPY ? 15.0 : 10.0;
      case PERIOD_D1:  return isJPY ? 25.0 : 15.0;
      default:         return isJPY ?  7.0 :  3.0;
   }
}

// TF-based breakeven/trail cushion values
double GetTFBasedCushion(ENUM_TIMEFRAMES tf)
{
   switch(tf)
   {
      case PERIOD_M1:  return 3.0;   // M1 needs slightly more room
      case PERIOD_M5:  return 3.0;
      case PERIOD_M15: return 5.0;
      case PERIOD_M30: return 8.0;
      case PERIOD_H1:  return 10.0;
      case PERIOD_H4:  return 15.0;
      case PERIOD_D1:  return 25.0;
      default:         return 5.0;
   }
}

string PresetToString(EStrategyPreset p)
{
   switch(p)
   {
      case PRESET_CUSTOM:       return "CUSTOM";
      case PRESET_MA_BENCHMARK: return "MA_BENCHMARK";
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
      case PRESET_MA_BENCHMARK:
         return "MA benchmark mode: replicates MT5 Moving Average EA; all voting disabled.";
      case PRESET_RRM:
         return "RRM phase-based system fixed (AutoStrat, EMA/MACD config, vote threshold); only Policy A gates and exits user-controlled.";
      case PRESET_TEST:
         return "Minimal testing mode: bypass voting (threshold=1), fixed SL/TP, no trailing.";
      default:
         return "Preset active; strategy-critical settings fixed by preset.";
   }
}

void ApplyPreset(const EStrategyPreset preset, ST_Settings &cfg)
{
   if(preset == PRESET_CUSTOM)
      return;

   // Do NOT modify cfg.PrintEffectiveConfig / cfg.DebugFlow
   // Do NOT modify UI toggles or reporting toggles (ExportCSV, ExportUseCommonFiles)

   // ================================================================
   // Policy A: Operator gates remain user-controlled even under presets
   // Preserve them across preset application.
   // ================================================================
   const double          op_MaxSpread  = cfg.MaxSpread;
   const double          op_MinATR     = cfg.MinATR;
   const double          op_MaxATR     = cfg.MaxATR;

   const bool            op_UseTime    = cfg.UseTime;
   const int             op_StartHr    = cfg.StartHr;
   const int             op_EndHr      = cfg.EndHr;

   const bool            op_UseNews    = cfg.UseNews;
   const int             op_NewsPre    = cfg.NewsPre;
   const int             op_NewsPost   = cfg.NewsPost;

   const bool            op_UseHTF     = cfg.UseHTF;
   const ENUM_TIMEFRAMES op_HtfPeriod  = cfg.HtfPeriod;
   const int             op_P_HtfEma   = cfg.P_HtfEma;

   if(preset == PRESET_MA_BENCHMARK)
   {
      // Goal: Replicate MT5 Moving Average EA
      cfg.CloseOnReverse    = true;

      cfg.BiasEnabled       = true;
      cfg.BiasMode          = BIAS_AUTO;
      cfg.AutoStrat         = STRAT_PRICE_CROSS;
      cfg.BiasFastID        = (int)ROLE_EMA1;
      cfg.BiasSlowID        = (int)ROLE_EMA1;

      cfg.RequirePriceCross = true;
      cfg.MABenchmarkStrict = true;

      cfg.UseMACompatSizer  = true;
      cfg.RiskPercent       = 0.0;

      cfg.VoteMode          = VOTE_MODE_ALL;
      cfg.MaxSpread         = 9999.0;
      cfg.MinATR            = 0.0;
      cfg.MaxATR            = 0.0;

      cfg.UseTime           = false;
      cfg.UseNews           = false;
      cfg.UseHTF            = false;

      // Disable all voting indicators
      cfg.Ind_EmaSig_Enabled        = false;
      cfg.Ind_Adx_Enabled           = false;
      cfg.Ind_Macd_Enabled          = false;
      cfg.Ind_Rsi_Enabled           = false;
      cfg.Ind_Cci_Enabled           = false;
      cfg.Ind_Mfi_Enabled           = false;
      cfg.Ind_Sto_Enabled           = false;
      cfg.Ind_Bb_Enabled            = false;
      cfg.Ind_Psar_Enabled          = false;
      cfg.Ind_P123_Enabled          = false;
      cfg.Ind_Ross_Enabled          = false;
      cfg.Ind_ATR_Enabled           = false;

      cfg.SL_PlacementMode  = SL_ATR;
      cfg.SL_Mult           = 0.0;
      cfg.TP_Mult           = 0.0;
      cfg.Use_BE            = false;
      cfg.BE_Trig           = 0.0;
      cfg.BE_Buff           = 0.0;
      cfg.TrailMode         = TRAIL_NONE;
      cfg.Trail_Mult        = 0.0;

      cfg.MaType            = METHOD_SMA;
      cfg.ma_h_shift        = Inp_MA_Shift;
      cfg.ma_v_shift        = 1;
      cfg.P_Ema1            = Inp_MA_Period;

      // Restore operator-controlled gates (Policy A)
      cfg.MaxSpread = op_MaxSpread;
      cfg.MinATR    = op_MinATR;
      cfg.MaxATR    = op_MaxATR;

      cfg.UseTime   = op_UseTime;
      cfg.StartHr   = op_StartHr;
      cfg.EndHr     = op_EndHr;

      cfg.UseNews   = op_UseNews;
      cfg.NewsPre   = op_NewsPre;
      cfg.NewsPost  = op_NewsPost;

      cfg.UseHTF    = op_UseHTF;
      cfg.HtfPeriod = op_HtfPeriod;
      cfg.P_HtfEma  = op_P_HtfEma;

      return;
   }

   if(preset == PRESET_RRM)
   {
      // RRM Phase-Based Layer Detection System
      cfg.CloseOnReverse = true;
      cfg.BiasEnabled    = true;
      cfg.BiasMode       = BIAS_AUTO_PHASE;
      cfg.AutoStrat      = STRAT_LAYER_DETECTION;
      cfg.MaType         = METHOD_EMA;

      // EMA Periods for 4-layer system
      cfg.P_Ema1 = 5;    // L1 fast
      cfg.P_Ema2 = 13;   // L1 slow, L2 fast
      cfg.P_Ema3 = 34;   // L2 slow, L3 fast, Bias fast
      cfg.P_Ema4 = 89;   // L3 slow, Bias slow

      // Bias EMA roles
      cfg.BiasFastID = (int)ROLE_EMA3;
      cfg.BiasSlowID = (int)ROLE_EMA4;

      // ATR gating disabled (ATR participates as voting indicator instead)
      cfg.MinATR       = 0.0;
      cfg.MaxATR       = 0.0;
      cfg.ATR_HardGate = false;

      // Voting indicators
      cfg.VoteMode               = VOTE_MODE_ALL;
      cfg.Ind_EmaSig_Enabled     = true;
      cfg.Ind_Adx_Enabled        = false;
      cfg.Ind_Macd_Enabled       = true;
      cfg.Ind_Rsi_Enabled        = false;
      cfg.Ind_Cci_Enabled        = true;
      cfg.Ind_Mfi_Enabled        = false;
      cfg.Ind_Sto_Enabled        = false;
      cfg.Ind_Bb_Enabled         = false;
      cfg.Ind_Psar_Enabled       = true;
      cfg.Ind_P123_Enabled       = false;
      cfg.Ind_Ross_Enabled       = false;
      cfg.Ind_ATR_Enabled        = true;   // ATR as voting indicator

      cfg.P_MacdFast             = 8;
      cfg.P_MacdSlow             = 13;
      cfg.P_MacdSig              = 8;

      // MACD vote mode: histogram-based
      cfg.MacdVoteMode           = MACD_HISTOGRAM;
      cfg.MacdRequireSlope       = false;
      cfg.MacdRequireDivergence  = false;
      cfg.MacdRequireHook        = false;
      cfg.MacdFreshBars          = 3;
      cfg.MacdSlopeMin           = 0.00001;

      cfg.RRM_Lookback           = 5;
      cfg.RRM_MinDivPips         = 1.5;

      // Dynamic structure pullback gate
      ENUM_TIMEFRAMES tf = (ENUM_TIMEFRAMES)_Period;
      cfg.RequirePullback           = true;
      cfg.PullbackLookback          = (tf <= PERIOD_M5 ? 20 : 15);
      cfg.RequireRecoveryMomentum   = true;
      cfg.Gate_UseMultiLayer        = true;
      cfg.LayerTouchTolerance       = 0.01;

      cfg.Vote_EvalShift            = 1;

      // Timeframe-adaptive PSAR flip configuration
      if(tf >= PERIOD_H4)
      {
         cfg.Vote_AllowPsarFlip     = false;
         cfg.Vote_PsarFlipDelay     = 0;
      }
      else if(tf == PERIOD_H1)
      {
         cfg.Vote_AllowPsarFlip     = true;
         cfg.Vote_PsarFlipDelay     = 4;
      }
      else if(tf == PERIOD_M30)
      {
         cfg.Vote_AllowPsarFlip     = true;
         cfg.Vote_PsarFlipDelay     = 3;
      }
      else if(tf == PERIOD_M15)
      {
         cfg.Vote_AllowPsarFlip     = true;
         cfg.Vote_PsarFlipDelay     = 3;
      }
      else if(tf == PERIOD_M5)
      {
         cfg.Vote_AllowPsarFlip     = true;
         cfg.Vote_PsarFlipDelay     = 2;
      }
      else
      {
         cfg.Vote_AllowPsarFlip     = true;
         cfg.Vote_PsarFlipDelay     = 1;
      }

      // Risk management (portfolio-level)
      cfg.MaxTotalRisk              = 4.0;
      cfg.MaxOpenTrades             = 3;
      cfg.CountBEasZeroRisk         = true;

      // Exit profile
      cfg.ExitProfile           = EXIT_PROFILE_RRM;
      cfg.SL_PlacementMode      = SL_SWING_HIGHLOW;
      cfg.SL_Mult               = 0.0;
      cfg.SL_SwingPipsCushion   = GetRecommendedInitialSlCushionPips();
      cfg.SL_PsarPipsCushion    = GetRecommendedInitialSlCushionPips();
      cfg.TP_Mult               = 3.0;
      cfg.TP_Enabled            = true;
      cfg.TrailMode             = TRAIL_PSAR;
      cfg.PSAR_TrailCushionMode = PSAR_CUSHION_PIPS;
      cfg.PSAR_TrailPipsCushion = GetRecommendedTrailPsarCushionPips();
      cfg.Use_BE                = false;
      cfg.BE_Mode               = BE_MODE_R_MULTIPLE;  // Preserved for future activation without recompilation

      // SL/TP strategy (RRM: swing-based SL, R:R ratio TP, ATR disabled for exit)
      cfg.SLMode        = SL_MODE_SWING;
      cfg.TPMode        = TP_MODE_RR;
      cfg.FixedTPPips   = 40.0;
      cfg.UseATRforSL   = false;
      cfg.UseATRforTP   = false;
      cfg.SLPercent     = 0.5;
      cfg.RRRatio       = 3.0;
      cfg.SwingLookback = 20;

      // Fractal/PSAR SL/TP defaults
      cfg.FractalPeriod      = 5;
      cfg.TPFractalOffset    = 1;
      cfg.PSARStep           = 0.02;
      cfg.PSARMax            = 0.2;

      // Advanced trailing trigger defaults
      cfg.TrailTrigger       = TRIGGER_BREAKEVEN;
      cfg.TrailDistancePips  = GetTFBasedCushion(tf);
      cfg.TrailATRMultiplier = 0.0;   // ATR multiplier disabled; using fixed-pip trailing (TrailDistancePips)
      cfg.BEThresholdPips    = GetTFBasedCushion(tf);
      cfg.TrailProfitPercent = 1.0;
      cfg.TrailStepPips      = 5.0;
      cfg.TrailLockProfit    = true;

      // Phase Detection — enabled in PRESET_RRM
      cfg.PhaseDetectionEnabled      = true;
      cfg.EnableLayerDetection       = true;
      cfg.BlockUnorderedPhase        = true;
      cfg.RequireMinPhaseConfirm     = false;
      cfg.MinPhaseConfirmBars        = 0;

      // Layer phase permissions
      cfg.Emerging_AllowWeakTrades   = true;
      cfg.Emerging_AllowMediumTrades = true;
      cfg.Emerging_AllowStrongTrades = false;
      cfg.Trending_AllowWeakTrades   = true;
      cfg.Trending_AllowMediumTrades = true;
      cfg.Trending_AllowStrongTrades = true;

      // Spread limit based on timeframe
      cfg.MaxSpread = (tf <= PERIOD_M5) ? 2.0 : 4.0;

      // Restore operator-controlled gates (Policy A)
      // NOTE: MaxSpread is restored; MinATR/MaxATR kept at 0 (ATR votes, not hard gates)
      cfg.MaxSpread = op_MaxSpread;
      cfg.UseTime   = op_UseTime;
      cfg.StartHr   = op_StartHr;
      cfg.EndHr     = op_EndHr;

      cfg.UseNews   = op_UseNews;
      cfg.NewsPre   = op_NewsPre;
      cfg.NewsPost  = op_NewsPost;

      cfg.UseHTF    = false;
      cfg.HtfPeriod = (_Period == PERIOD_M1) ? PERIOD_M5 :
                      (_Period == PERIOD_M5) ? PERIOD_M15 :
                      (_Period <= PERIOD_M15) ? PERIOD_H1 : PERIOD_H4;
      cfg.P_HtfEma  = 89;

      return;
   }

   if(preset == PRESET_TEST)
   {
      // Minimal configuration for development/testing
      cfg.BiasEnabled    = true;
      cfg.BiasMode       = BIAS_AUTO;
      cfg.AutoStrat      = STRAT_PAIR_CROSS;
      cfg.BiasFastID     = (int)ROLE_EMA3;
      cfg.BiasSlowID     = (int)ROLE_EMA4;
      cfg.PhaseDetectionEnabled  = false;
      cfg.MinPhaseConfirmBars    = 0;
      cfg.BlockUnorderedPhase    = false;

      // Disable all gates (bypass for testing)
      cfg.MaxSpread    = 100.0;
      cfg.MinATR       = 0.0;
      cfg.MaxATR       = 0.0;
      cfg.ATR_HardGate = false;
      cfg.UseTime      = false;
      cfg.UseNews      = false;
      cfg.UseHTF       = false;

      // Disable entry layers
      cfg.EnableLayerDetection     = false;
      cfg.LayerTouchTolerance      = 0.0;
      cfg.RequireRecoveryMomentum  = false;
      cfg.RequirePullback          = false;

      // Disable all indicators (user enables one at a time for testing)
      cfg.Ind_EmaSig_Enabled = false;
      cfg.Ind_Adx_Enabled    = false;
      cfg.Ind_Macd_Enabled   = false;
      cfg.Ind_Rsi_Enabled    = false;
      cfg.Ind_Cci_Enabled    = false;
      cfg.Ind_Mfi_Enabled    = false;
      cfg.Ind_Sto_Enabled    = false;
      cfg.Ind_Bb_Enabled     = false;
      cfg.Ind_Psar_Enabled   = false;
      cfg.Ind_P123_Enabled   = false;
      cfg.Ind_Ross_Enabled   = false;
      cfg.Ind_ATR_Enabled    = false;

      // Single indicator test: enable PSAR
      cfg.Ind_Psar_Enabled     = true;
      cfg.Vote_AllowPsarFlip   = true;
      cfg.Vote_PsarFlipDelay   = 10;
      cfg.P_PsarStep           = 0.02;
      cfg.P_PsarMax            = 0.2;

      // Voting: ALL mode with single indicator active
      cfg.VoteMode = VOTE_MODE_ALL;

      // Simple fixed SL/TP for testing
      cfg.SLMode        = SL_MODE_FIXED_PIPS;
      cfg.TPMode        = TP_MODE_FIXED_PIPS;
      cfg.TrailMode     = TRAIL_NONE;
      cfg.Use_BE        = false;

      return;
   }
}

//+------------------------------------------------------------------+
//| END OF FILE                                                      |
//+------------------------------------------------------------------+
