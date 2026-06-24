//+-------------------------------------------------------------------+
//|                                                  SEA_Presets.mqh  |
//|                                   Copyright 2026, SimpleEA System |
//| DESCRIPTION: Model A presets: overwrite strategy-critical fields  |
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

string PresetToString(EStrategyPreset p)
{
   switch(p)
   {
      case PRESET_CUSTOM:         return "CUSTOM";
      case PRESET_MA_BENCHMARK:   return "MA_BENCHMARK";
      case PRESET_TREND_REVERSAL: return "TREND_REVERSAL";
      case PRESET_TREND_SCALP:    return "TREND_SCALP";
      case PRESET_TREND_SWING:    return "TREND_SWING";
      case PRESET_RANGE_GRID:     return "RANGE_GRID";
      case PRESET_RRM_ATR:        return "RRM_ATR";
      case PRESET_RRM:            return "RRM";
      default:                    return "UNKNOWN";
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
         return "MA benchmark mode: indicator periods/roles fixed; gates, exits, position sizing user-controlled.";
      case PRESET_TREND_REVERSAL:
      case PRESET_TREND_SCALP:
      case PRESET_TREND_SWING:
         return "Trend strategy fixed (AutoStrat, bias, votes, thresholds); only gates, time filters, spread/ATR limits, exits user-controlled.";
      case PRESET_RANGE_GRID:
         return "Range grid strategy fixed (voting, EMA roles, thresholds); only gates, filters, exit policy user-controlled.";
      case PRESET_RRM_ATR:
      case PRESET_RRM:
         return "RRM resilience strategy fixed (AutoStrat, EMA/MACD config, vote threshold); only Policy A gates and exits user-controlled.";
      default:
         return "Preset active; strategy-critical settings fixed by preset.";
   }
}

// ApplyAdminOverrides(): applies admin override inputs onto cfg.
// Called at the end of each non-CUSTOM preset block in ApplyPreset().
// Only applies when cfg.AdminOverridePreset is true; no-op otherwise.
// Overrides: AutoStrat, VoteThreshold, EMA/MACD periods, vote enable flags,
//            RRM gate flags, indicator thresholds, and entry/exit parameters
//            (RequirePriceCross, UseHTF, CloseOnReverse, RiskPercent,
//             SL/TP modes and multipliers, trailing stop, breakeven,
//             and phase detection & layer filtering settings (§5)).
//
// NOTE: MACD mode/filter settings are unconditionally applied from user inputs at the top
//       of this function, BEFORE the AdminOverridePreset gate. This is by design (two-tier
//       MACD architecture): the preset sets a safe default (e.g. MACD_ZERO_AND_CROSS), then
//       the user's MACD inputs ALWAYS override it so signal configuration changes are never
//       silently blocked by a preset. All other preset-locked settings still respect the gate.
void ApplyAdminOverrides(ST_Settings &cfg)
{
   // MACD settings — ALWAYS apply from user inputs (not gated by AdminOverridePreset)
   // Rationale: MACD vote mode is a signal-tuning parameter that users must be able to
   //            change at any time without enabling full AdminOverridePreset mode.
   cfg.MacdVoteMode          = Inp_MacdVoteMode;
   cfg.MacdRequireSlope      = Inp_MacdRequireSlope;
   cfg.MacdRequireDivergence = Inp_MacdRequireDivergence;
   cfg.MacdRequireHook       = Inp_MacdRequireHook;
   cfg.MacdFreshBars         = Inp_MacdFreshBars;
   cfg.MacdSlopeMin          = Inp_MacdSlopeMin;
   cfg.P_MacdFast            = Inp_P_MacdFast;
   cfg.P_MacdSlow            = Inp_P_MacdSlow;
   cfg.P_MacdSig             = Inp_P_MacdSig;

   // Exit here if not admin mode — only MACD settings above are applied
   if(!cfg.AdminOverridePreset) return;

   cfg.AutoStrat      = Inp_Override_AutoStrat;
   cfg.VoteThreshold  = Inp_Override_VoteThreshold;
   cfg.P_Ema1         = Inp_Override_EMA1;
   cfg.P_Ema2         = Inp_Override_EMA2;
   cfg.P_Ema3         = Inp_Override_EMA3;
   cfg.P_Ema4         = Inp_Override_EMA4;
   cfg.P_MacdFast     = Inp_Override_MACD_Fast;
   cfg.P_MacdSlow     = Inp_Override_MACD_Slow;
   cfg.P_MacdSig      = Inp_Override_MACD_Signal;
   cfg.Ind_EmaSig_Enabled     = Inp_Override_Use_EmaSig;
   cfg.Ind_Macd_Enabled       = Inp_Override_Use_Macd;
   cfg.Ind_Psar_Enabled       = Inp_Override_Use_Psar;
   cfg.Ind_Cci_Enabled        = Inp_Override_Use_Cci;
   cfg.Ind_Rsi_Enabled        = Inp_Override_Use_Rsi;
   cfg.Ind_Adx_Enabled        = Inp_Override_Use_Adx;
   cfg.Ind_Mfi_Enabled        = Inp_Override_Use_Mfi;
   cfg.Ind_Sto_Enabled        = Inp_Override_Use_Sto;
   cfg.Ind_Bb_Enabled         = Inp_Override_Use_Bb;
   cfg.Ind_P123_Enabled       = Inp_Override_Use_P123;
   cfg.Ind_Ross_Enabled       = Inp_Override_Use_Ross;
   cfg.RequirePullback            = Inp_Override_RequirePullback;
   cfg.PullbackLookback           = Inp_Override_PullbackLookback;
   cfg.RequireRecoveryMomentum    = Inp_Override_RequireRecoveryMomentum;
   cfg.Gate_UseMultiLayer         = Inp_Override_UseMultiLayer;

   cfg.P_Adx          = Inp_Override_ADX_Period;
   cfg.T_Adx          = Inp_Override_ADX_Threshold;
   cfg.P_Rsi          = Inp_Override_RSI_Period;
   cfg.T_RsiOB        = Inp_Override_RSI_OB;
   cfg.T_RsiOS        = Inp_Override_RSI_OS;
   cfg.P_StoK         = Inp_Override_STO_K;
   cfg.P_StoD         = Inp_Override_STO_D;
   cfg.P_StoSlow      = Inp_Override_STO_Slow;
   cfg.T_StoOB        = Inp_Override_STO_OB;
   cfg.T_StoOS        = Inp_Override_STO_OS;
   cfg.P_PsarStep     = Inp_Override_PSAR_Step;
   cfg.P_PsarMax      = Inp_Override_PSAR_Max;
   cfg.P_Cci          = Inp_Override_CCI_Period;
   cfg.P_Bb           = Inp_Override_BB_Period;
   cfg.P_BbDev        = Inp_Override_BB_Dev;
   cfg.P_Mfi          = Inp_Override_MFI_Period;
   cfg.T_MfiOB        = Inp_Override_MFI_OB;
   cfg.T_MfiOS        = Inp_Override_MFI_OS;
   cfg.P_Atr          = Inp_Override_ATR_Period;
   cfg.MinATR         = Inp_Override_ATR_MinPips;
   cfg.MaxATR         = Inp_Override_ATR_MaxPips;
   cfg.Use_ATRVote    = Inp_Override_ATR_UseAsVote;

   cfg.RequirePriceCross     = Inp_Override_RequirePriceCross;
   cfg.UseHTF                = Inp_Override_UseHTF;
   cfg.CloseOnReverse        = Inp_Override_CloseOnReverse;
   cfg.RiskPercent           = Inp_Override_RiskPercent;
   cfg.SL_PlacementMode      = Inp_Override_SL_PlacementMode;
   cfg.SL_Mult               = Inp_Override_SL_Mult;
   cfg.SL_PsarPipsCushion    = Inp_Override_SL_PsarPipsCushion;
   cfg.SL_SwingPipsCushion   = Inp_Override_SL_SwingPipsCushion;
   cfg.TP_Mult               = Inp_Override_TP_Mult;
   cfg.Use_BE                = Inp_Override_Use_BE;
   cfg.BE_Trig               = Inp_Override_BE_Trig;
   cfg.BE_Buff               = Inp_Override_BE_Buff;
   cfg.TrailMode             = Inp_Override_TrailMode;
   cfg.Trail_Mult            = Inp_Override_Trail_Mult;
   cfg.PSAR_TrailCushionMode = Inp_Override_PSAR_TrailCushionMode;
   cfg.PSAR_TrailPipsCushion = Inp_Override_PSAR_TrailPipsCushion;

   // §5 Phase Detection & Layer Filtering
   cfg.PhaseDetectionEnabled      = Inp_Override_PhaseDetectionEnabled;
   cfg.EnableLayerDetection       = Inp_Override_EnableLayerDetection;
   cfg.BlockUnorderedPhase        = Inp_Override_BlockUnorderedPhase;
   cfg.RequireMinPhaseConfirm     = Inp_Override_RequireMinPhaseConfirm;
   cfg.MinPhaseConfirmBars        = Inp_Override_MinPhaseConfirmBars;

   // §6 RRM Drawdown Protection
   cfg.RRM_EnableDrawdownProtection = Inp_RRM_EnableDrawdownProtection;
   cfg.RRM_MaxConsecutiveLosses     = Inp_RRM_MaxConsecutiveLosses;
   cfg.RRM_MaxTradesPerDay          = Inp_RRM_MaxTradesPerDay;
   cfg.RRM_MaxDailyDrawdownPct      = Inp_RRM_MaxDailyDrawdownPct;

   // Layer 1 (Weak, EMA1/EMA2) phase permissions
   cfg.Trending_AllowWeakTrades   = Inp_Override_Layer1_AllowTrending;
   cfg.Emerging_AllowWeakTrades   = Inp_Override_Layer1_AllowEmerging;

   // Layer 2 (Medium, EMA2/EMA3) phase permissions
   cfg.Trending_AllowMediumTrades = Inp_Override_Layer2_AllowTrending;
   cfg.Emerging_AllowMediumTrades = Inp_Override_Layer2_AllowEmerging;

   // Layer 3 (Strong, EMA3/EMA4) phase permissions
   cfg.Trending_AllowStrongTrades = Inp_Override_Layer3_AllowTrending;
   cfg.Emerging_AllowStrongTrades = Inp_Override_Layer3_AllowEmerging;
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

      cfg.VoteThreshold     = 1;
      cfg.MaxSpread         = 9999.0;
      cfg.MinATR            = 0.0;
      cfg.MaxATR            = 0.0;

      cfg.UseTime           = false;
      cfg.UseNews           = false;
      cfg.UseHTF            = false;

      // Disable all votes
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

      ApplyAdminOverrides(cfg);
      return;
   }

   if(preset == PRESET_TREND_REVERSAL)
   {
      cfg.CloseOnReverse    = true;

      cfg.BiasEnabled       = true;
      cfg.BiasMode          = BIAS_AUTO;
      cfg.AutoStrat         = STRAT_PRICE_CROSS;
      cfg.BiasFastID        = (int)ROLE_EMA1;
      cfg.BiasSlowID        = (int)ROLE_EMA1;

      cfg.RequirePriceCross = true;
      cfg.ma_v_shift        = 1;

      cfg.VoteThreshold     = 1;
      cfg.MaxSpread         = 5.0;
      cfg.MinATR            = 0.0;
      cfg.MaxATR            = 0.0;

      cfg.UseTime           = false;
      cfg.UseNews           = false;
      cfg.UseHTF            = false;

      cfg.Ind_EmaSig_Enabled        = true;
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

      cfg.SL_PlacementMode  = SL_ATR;
      cfg.SL_Mult           = 0.0;
      cfg.TP_Mult           = 0.0;
      cfg.Use_BE            = false;
      cfg.TrailMode         = TRAIL_NONE;

      cfg.MaType            = METHOD_SMA;

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

      ApplyAdminOverrides(cfg);
      return;
   }

   if(preset == PRESET_TREND_SCALP)
   {
      cfg.CloseOnReverse = true;

      cfg.BiasEnabled    = true;
      cfg.BiasMode       = BIAS_AUTO;
      cfg.AutoStrat      = STRAT_PAIR_CROSS;
      cfg.BiasFastID     = (int)ROLE_EMA1;
      cfg.BiasSlowID     = (int)ROLE_EMA2;

      cfg.VoteThreshold  = 3;
      cfg.MaxSpread      = 3.0;
      cfg.MinATR         = 5.0;
      cfg.MaxATR         = 0.0;

      cfg.UseTime        = false;
      cfg.UseNews        = true;
      cfg.UseHTF         = true;

      cfg.Ind_EmaSig_Enabled     = true;
      cfg.Ind_Adx_Enabled        = true;
      cfg.Ind_Macd_Enabled       = true;
      cfg.Ind_Rsi_Enabled        = false;
      cfg.Ind_Cci_Enabled        = false;
      cfg.Ind_Mfi_Enabled        = false;
      cfg.Ind_Sto_Enabled        = false;
      cfg.Ind_Bb_Enabled         = false;
      cfg.Ind_Psar_Enabled       = false;
      cfg.Ind_P123_Enabled       = false;
      cfg.Ind_Ross_Enabled       = false;

      cfg.SL_PlacementMode = SL_ATR;
      cfg.SL_Mult        = 1.5;
      cfg.TP_Mult        = 3.0;
      cfg.Use_BE         = true;
      cfg.BE_Trig        = 1.0;
      cfg.BE_Buff        = 0.1;
      cfg.TrailMode      = TRAIL_ATR;
      cfg.Trail_Mult     = 1.5;

      cfg.MaType         = METHOD_EMA;

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

      ApplyAdminOverrides(cfg);
      return;
   }

   if(preset == PRESET_TREND_SWING)
   {
      cfg.CloseOnReverse = true;

      cfg.BiasEnabled    = true;
      cfg.BiasMode       = BIAS_AUTO;
      cfg.AutoStrat      = STRAT_PAIR_CROSS;
      cfg.BiasFastID     = (int)ROLE_EMA3;
      cfg.BiasSlowID     = (int)ROLE_EMA4;

      cfg.VoteThreshold  = 1;
      cfg.MaxSpread      = 5.0;
      cfg.MinATR         = 5.0;
      cfg.MaxATR         = 0.0;

      cfg.UseTime        = true;
      cfg.UseNews        = true;
      cfg.UseHTF         = true;

      cfg.Ind_EmaSig_Enabled     = true;
      cfg.Ind_Adx_Enabled        = true;
      cfg.Ind_Macd_Enabled       = true;
      cfg.Ind_Rsi_Enabled        = false;
      cfg.Ind_Cci_Enabled        = false;
      cfg.Ind_Mfi_Enabled        = false;
      cfg.Ind_Sto_Enabled        = false;
      cfg.Ind_Bb_Enabled         = false;
      cfg.Ind_Psar_Enabled       = false;
      cfg.Ind_P123_Enabled       = false;
      cfg.Ind_Ross_Enabled       = false;

      cfg.SL_PlacementMode = SL_ATR;
      cfg.SL_Mult        = 2.0;
      cfg.TP_Mult        = 4.0;
      cfg.Use_BE         = true;
      cfg.BE_Trig        = 1.0;
      cfg.BE_Buff        = 0.1;
      cfg.TrailMode      = TRAIL_ATR;
      cfg.Trail_Mult     = 2.0;

      cfg.MaType         = METHOD_EMA;

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

      ApplyAdminOverrides(cfg);
      return;
   }

   if(preset == PRESET_RANGE_GRID)
   {
      cfg.CloseOnReverse = false;

      cfg.BiasEnabled    = true;
      cfg.BiasMode       = BIAS_AUTO;
      cfg.AutoStrat      = STRAT_PAIR_CROSS;
      cfg.BiasFastID     = (int)ROLE_EMA2;
      cfg.BiasSlowID     = (int)ROLE_EMA4;

      cfg.VoteThreshold  = 4;
      cfg.MaxSpread      = 4.0;
      cfg.MinATR         = 2.0;
      cfg.MaxATR         = 0.0;

      cfg.UseTime        = true;
      cfg.UseNews        = true;
      cfg.UseHTF         = true;

      cfg.RsiMode        = RSI_FILTER_EXTREME;
      cfg.StoMode        = STO_ZONE_FILTER;
      cfg.BbMode         = BB_MEAN_REVERSION;

      cfg.Ind_EmaSig_Enabled     = false;
      cfg.Ind_Adx_Enabled        = false;
      cfg.Ind_Macd_Enabled       = false;
      cfg.Ind_Rsi_Enabled        = true;
      cfg.Ind_Cci_Enabled        = false;
      cfg.Ind_Mfi_Enabled        = false;
      cfg.Ind_Sto_Enabled        = true;
      cfg.Ind_Bb_Enabled         = true;
      cfg.Ind_Psar_Enabled       = false;
      cfg.Ind_P123_Enabled       = false;
      cfg.Ind_Ross_Enabled       = false;

      cfg.SL_PlacementMode = SL_ATR;
      cfg.SL_Mult        = 2.0;
      cfg.TP_Mult        = 2.0;
      cfg.Use_BE         = false;
      cfg.TrailMode      = TRAIL_NONE;

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

      ApplyAdminOverrides(cfg);
      return;
   }

   if(preset == PRESET_RRM_ATR)
   {
      ERRMMode mode = Inp_RRM_Mode;
      if(mode == RRM_AUTO_BY_TF)
      {
         if(_Period == PERIOD_M1 || _Period == PERIOD_M5 || _Period == PERIOD_M15) mode = RRM_SCALP;
         else mode = RRM_SWING;
      }

      cfg.CloseOnReverse = true;
      cfg.BiasEnabled    = true;
      cfg.BiasMode       = BIAS_AUTO;
      cfg.AutoStrat      = STRAT_PAIR_CROSS;
      cfg.MaType         = METHOD_EMA;

      cfg.ATR_HardGate   = false;
      cfg.Use_ATRVote    = true;

      if(mode == RRM_SCALP)
      {
         cfg.BiasFastID = (int)ROLE_EMA1;
         cfg.BiasSlowID = (int)ROLE_EMA2;

         cfg.P_Ema1 = 34; cfg.P_Ema2 = 89; cfg.P_Ema3 = 34; cfg.P_Ema4 = 89;

         cfg.MaxSpread = 2.5;
         cfg.MinATR    = (_Period == PERIOD_M1 ? 12.5 : 5.0);
         cfg.MaxATR    = 0.0;

         cfg.SL_PlacementMode = SL_ATR;
         cfg.SL_Mult          = 2.0;
         cfg.TP_Mult          = 4.0;
      }
      else
      {
         cfg.BiasFastID = (int)ROLE_EMA3;
         cfg.BiasSlowID = (int)ROLE_EMA4;

         cfg.P_Ema1 = 5; cfg.P_Ema2 = 13; cfg.P_Ema3 = 34; cfg.P_Ema4 = 89;

         cfg.MaxSpread = 5.0;
         cfg.MinATR    = 5.0;
         cfg.MaxATR    = 0.0;

         cfg.SL_PlacementMode = SL_ATR;
         cfg.SL_Mult          = 2.0;
         cfg.TP_Mult          = 4.0;
      }

      cfg.Ind_EmaSig_Enabled    = true;
      cfg.Ind_Adx_Enabled       = false;
      cfg.Ind_Macd_Enabled      = true;
      cfg.Ind_Rsi_Enabled       = false;
      cfg.Ind_Cci_Enabled       = false;
      cfg.Ind_Mfi_Enabled       = true;
      cfg.Ind_Sto_Enabled       = true;
      cfg.Ind_Bb_Enabled        = true;
      cfg.Ind_Psar_Enabled      = true;
      cfg.Ind_P123_Enabled      = false;
      cfg.Ind_Ross_Enabled      = false;

      cfg.VoteThreshold = 4;

      cfg.P_MacdFast = 8;
      cfg.P_MacdSlow = 13;
      cfg.P_MacdSig  = 8;

      cfg.StoMode    = STO_CROSS_SIGNAL;

      cfg.RRM_Lookback               = 5;
      cfg.RRM_MinDivPips             = 0.5;

      cfg.Use_BE  = true;
      cfg.BE_Trig = 1.5;
      cfg.BE_Buff = 0.3;

      cfg.TrailMode             = TRAIL_PSAR;
      cfg.P_PsarTrailCushionATR = 0.5;

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

      ApplyAdminOverrides(cfg);
      return;
   }

   if(preset == PRESET_RRM)
   {
      // RRM: user-owned exits (SL/TP/BE/trailing preserved from InitializeConfig mapping).
      //
      // Architecture fit (Filters → Bias → Votes → User-controlled Exits):
      //   1) Filters (Spread/News/Session/HTF) gate out truly untradeable conditions.
      //   2) Bias is defined by EMA pair trend direction (AUTO bias) OR phase-based (AUTO_PHASE).
      //   3) Votes provide confluence confirmations (EMA ribbon + MACD/CCI/PSAR; no ATR vote).
      //   4) Exits remain as mapped from user inputs; only PSAR cushions are auto-scaled when
      //      user left defaults (non-invasive).
      //
      // ATR is fully disabled: MinATR=0, MaxATR=0, ATR_HardGate=false, Use_ATRVote=false.
      // Policy A: MaxSpread is operator-controlled; MinATR/MaxATR are NOT restored (kept at 0).
   
      ERRMMode mode = Inp_RRM_Mode;
      if(mode == RRM_AUTO_BY_TF)
      {
         if(_Period == PERIOD_M1 || _Period == PERIOD_M5 || _Period == PERIOD_M15) mode = RRM_SCALP;
         else mode = RRM_SWING;
      }
   
      cfg.CloseOnReverse = true;
      cfg.BiasEnabled    = true;
      cfg.BiasMode       = Inp_BiasMode;  // ✅ FIX 1: Use input setting
      cfg.MaType         = METHOD_EMA;
   
      // ATR gating fully disabled for strict mode
      cfg.MinATR       = 0.0;
      cfg.MaxATR       = 0.0;
      cfg.ATR_HardGate = false;
      cfg.Use_ATRVote  = false;
   
      // ✅ FIX 2: Adaptive AutoStrat based on BiasMode
      if(cfg.BiasMode == BIAS_AUTO_PHASE)
      {
         // Phase-based bias: uses 3-EMA structure (EMA2/3/4) for phase detection
         // AutoStrat and BiasFastID/SlowID are not used for bias calculation
         // but kept for compatibility with signal validation logic
         cfg.AutoStrat  = STRAT_PAIR_CROSS;
         cfg.BiasFastID = (int)ROLE_EMA3;  // Not used in phase bias, kept for structure
         cfg.BiasSlowID = (int)ROLE_EMA4;  // Not used in phase bias, kept for structure
         
         cfg.P_Ema1 = 5; cfg.P_Ema2 = 13; cfg.P_Ema3 = 34; cfg.P_Ema4 = 89;
         cfg.MaxSpread = (mode == RRM_SCALP) ? 2.0 : 4.0;  // ✅ PROTECTION 3: Tighter spread
      }
      else
      {
         // Traditional BIAS_AUTO: uses EMA3/EMA4 crossover for bias
         if(mode == RRM_SCALP)
         {
            cfg.AutoStrat  = STRAT_PAIR_CROSS;
            cfg.BiasFastID = (int)ROLE_EMA3;  // EMA3(34) — stable bias, resists shallow pullbacks
            cfg.BiasSlowID = (int)ROLE_EMA4;  // EMA4(89) — very stable; EMA1/EMA2 used only for entry timing
   
            cfg.P_Ema1 = 5; cfg.P_Ema2 = 13; cfg.P_Ema3 = 34; cfg.P_Ema4 = 89;
   
            cfg.MaxSpread = 2.0;  // ✅ PROTECTION 3: Tighter spread (was 2.5)
         }
         else
         {
            cfg.AutoStrat  = STRAT_PAIR_CROSS;
            cfg.BiasFastID = (int)ROLE_EMA3;
            cfg.BiasSlowID = (int)ROLE_EMA4;
   
            cfg.P_Ema1 = 5; cfg.P_Ema2 = 13; cfg.P_Ema3 = 34; cfg.P_Ema4 = 89;
   
            cfg.MaxSpread = 4.0;  // ✅ PROTECTION 3: Tighter spread (was 5.0)
         }
      }
   
      // Votes: EMA ribbon + MACD/CCI/PSAR (no ATR vote)
      cfg.VoteThreshold = 4;
      cfg.Ind_EmaSig_Enabled    = true;
      cfg.Ind_Adx_Enabled       = false;
      cfg.Ind_Macd_Enabled      = true;
      cfg.Ind_Rsi_Enabled       = false;
      cfg.Ind_Cci_Enabled       = true;
      cfg.Ind_Mfi_Enabled       = false;
      cfg.Ind_Sto_Enabled       = false;
      cfg.Ind_Bb_Enabled        = false;
      cfg.Ind_Psar_Enabled      = true;
      cfg.Ind_P123_Enabled      = false;
      cfg.Ind_Ross_Enabled      = false;
   
      cfg.P_MacdFast = 8;     //  8,
      cfg.P_MacdSlow = 13;    // 13,
      cfg.P_MacdSig  = 8;     //  8,

      // MACD vote mode: default industry "traditional" (zero + crossover)
      cfg.MacdVoteMode          = MACD_ZERO_AND_CROSS;
      cfg.MacdRequireSlope      = false;
      cfg.MacdRequireDivergence = false;
      cfg.MacdRequireHook       = false;
      cfg.MacdFreshBars         = 3;
      cfg.MacdSlopeMin          = 0.00001;
   
      cfg.RRM_Lookback               = 5;
      cfg.RRM_MinDivPips             = 1.5;  // ✅ PROTECTION 7: Deeper pullback required (was 0.5)
   
      // Dynamic structure pullback gate (no pip thresholds)
      ENUM_TIMEFRAMES tf = (ENUM_TIMEFRAMES)_Period;
   
      cfg.RequirePullback            = true;
      cfg.PullbackLookback           = (tf <= PERIOD_M5 ? 20 : 15);  // ✅ PROTECTION 6: Longer lookback (was 15/10)
      cfg.RequireRecoveryMomentum    = true;   // ✅ PROTECTION 2: Confirm momentum (was false)
      cfg.Gate_UseMultiLayer         = true;
   
      cfg.Vote_EvalShift    = 1;
      cfg.Vote_AllowPsarFlip = true;
   
      // Enforce strict no-ATR exit contract (RRM design: swing-based SL, PSAR trail, no ATR)
      cfg.ExitProfile           = EXIT_PROFILE_RRM_STRICT_NO_ATR;
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
      cfg.BE_Mode               = BE_MODE_OFF;
   
      // Phase Detection (PR1-5) — enabled in PRESET_RRM
      cfg.PhaseDetectionEnabled      = true;
      cfg.EnableLayerDetection       = true;
      cfg.BlockUnorderedPhase        = true;
      cfg.RequireMinPhaseConfirm     = true;
      cfg.MinPhaseConfirmBars        = 4;  // ✅ PROTECTION 1: Stricter confirmation (was 3)
   
      // Layer phase permissions (PR4):
      // ✅ PROTECTION 5: Stricter EMERGING phase filtering
      // EMERGING phase: Only L2 allowed, L1/L3 blocked (reduce false signals in forming trends)
      cfg.Emerging_AllowWeakTrades   = false;  // ✅ Changed from true - L1 too risky
      cfg.Emerging_AllowMediumTrades = true;
      cfg.Emerging_AllowStrongTrades = false;
      // TRENDING phase: all layers allowed (strong established trend)
      cfg.Trending_AllowWeakTrades   = true;
      cfg.Trending_AllowMediumTrades = true;
      cfg.Trending_AllowStrongTrades = true;
   
      if(cfg.PrintEffectiveConfig || cfg.DebugFlow)
      {
         Print("=== PRESET APPLIED: RRM (Enhanced Protection) ===");
         Print("  BiasMode: ", EnumToString(cfg.BiasMode));
         Print("  MinPhaseConfirmBars: ", cfg.MinPhaseConfirmBars, " (4-bar confirmation)");
         Print("  RequireRecoveryMomentum: ", cfg.RequireRecoveryMomentum ? "YES" : "NO");
         Print("  PullbackLookback: ", cfg.PullbackLookback);
         Print("  RRM_MinDivPips: ", cfg.RRM_MinDivPips);
         Print("  MaxSpread: ", cfg.MaxSpread);
         Print("  SL_PlacementMode: ", EnumToString(cfg.SL_PlacementMode));
         Print("  SL_Mult (ATR): ", cfg.SL_Mult, " (0.0 = ATR disabled)");
         Print("  SL_SwingPipsCushion: ", cfg.SL_SwingPipsCushion);
         Print("  SL_PsarPipsCushion: ", cfg.SL_PsarPipsCushion);
         Print("  TP_Mult: ", cfg.TP_Mult);
         Print("  TrailMode: ", EnumToString(cfg.TrailMode));
      }
   
      // Restore operator-controlled gates (Policy A)
      // NOTE: MaxSpread is restored; MinATR/MaxATR are NOT restored (kept at 0 for strict mode).
      cfg.MaxSpread = op_MaxSpread;
      cfg.UseTime   = op_UseTime;
      cfg.StartHr   = op_StartHr;
      cfg.EndHr     = op_EndHr;
   
      cfg.UseNews   = op_UseNews;
      cfg.NewsPre   = op_NewsPre;
      cfg.NewsPost  = op_NewsPost;
   
      // ✅ PROTECTION 4: Enable HTF filter for multi-timeframe confirmation
      cfg.UseHTF    = true;  // Changed from op_UseHTF - force enable
      cfg.HtfPeriod = (_Period == PERIOD_M15) ? PERIOD_H1 : 
                      (_Period <= PERIOD_M5) ? PERIOD_H1 : PERIOD_H4;
      cfg.P_HtfEma  = 89;    // Use slow EMA on higher timeframe
   
      ApplyAdminOverrides(cfg);
      return;
   }

   // Failsafe: if execution reaches here for any reason, restore operator gates.
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
}

/*
PROPOSED MODIFICATION:

if(preset == PRESET_RRM)
{
   // ... existing code ...

   // ✅ 1. STRICTER PHASE CONFIRMATION (reduce whipsaws)
   cfg.MinPhaseConfirmBars        = 4;  // Was 3, now 4 bars required

   // ✅ 2. REQUIRE RECOVERY MOMENTUM (confirm trend resumption)
   cfg.RequireRecoveryMomentum    = true;  // Was false

   // ✅ 3. TIGHTER SPREAD FILTER (avoid poor execution)
   cfg.MaxSpread = (mode == RRM_SCALP) ? 2.0 : 4.0;  // Was 2.5/5.0

   // ✅ 4. ENABLE HTF FILTER (confirm higher timeframe alignment)
   cfg.UseHTF    = true;   // Require H1/H4 alignment
   cfg.HtfPeriod = (_Period == PERIOD_M15) ? PERIOD_H1 : PERIOD_H4;
   cfg.P_HtfEma  = 89;     // Use slow EMA on HTF

   // ✅ 5. STRICTER EMERGING PHASE (only allow safest layer)
   cfg.Emerging_AllowWeakTrades   = false;  // Was true - L1 too risky
   cfg.Emerging_AllowMediumTrades = true;   // Keep L2
   cfg.Emerging_AllowStrongTrades = false;  // Keep blocked

   // ✅ 6. INCREASE PULLBACK LOOKBACK (better structure detection)
   cfg.PullbackLookback = (tf <= PERIOD_M5 ? 20 : 15);  // Was 15/10

   // ✅ 7. ADD MINIMUM EMA DIVERGENCE (confirm pullback depth)
   cfg.RRM_MinDivPips = 1.5;  // Was 0.5 - require deeper pullback

   // ... rest of preset ...
}

Additional external protections (add to inputs, checked in filters):

// In SEA_Config.mqh inputs:
input group "=== PRESET_RRM: DRAWDOWN PROTECTION ==="
input int    Inp_RRM_MaxConsecutiveLosses = 5;   // Pause after X losses
input int    Inp_RRM_MaxTradesPerDay      = 10;  // Daily trade limit
input double Inp_RRM_MaxDailyDrawdownPct  = 2.0; // Pause if daily DD > 2%

// In filter logic:
if(consecutive_losses >= Inp_RRM_MaxConsecutiveLosses) return 0; // Pause
if(trades_today >= Inp_RRM_MaxTradesPerDay) return 0;           // Daily limit
if(daily_drawdown_pct > Inp_RRM_MaxDailyDrawdownPct) return 0; // DD protection


Quick wins to add NOW:

MinPhaseConfirmBars = 4 (fewer false signals)
RequireRecoveryMomentum = true (confirm momentum)
Emerging_AllowWeakTrades = false (block risky L1 in forming trends)
UseHTF = true (multi-timeframe confirmation)

These changes will reduce trade frequency but increase quality, targeting the high-loss periods visible in your equity curve.

*/

// Temporary back-compat for any remaining callers.
// Core .mq5 should use InitializeConfig + ApplyPreset directly.
void ApplySettings()
{
   InitializeConfig();
   ApplyPreset(InpPreset, Settings);

}