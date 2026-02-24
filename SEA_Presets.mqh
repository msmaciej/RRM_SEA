//+------------------------------------------------------------------+
//|                                                  SEA_Presets.mqh |
//|                                   Copyright 2026, SimpleEA System|
//| DESCRIPTION: Model A presets: overwrite strategy-critical fields  |
//|              on top of already hydrated Settings.                 |
//|                                                                  |
//| IMPORTANT:                                                       |
//| - NO input->struct mapping in this file.                          |
//| - NO printing/diagnostic spam in this file.                       |
//| - NO ValidateEffectiveSettings() in this file.                    |
//| - Do NOT touch global-allowed-under-presets fields:               |
//|   PrintEffectiveConfig, DebugFlow, UI toggles, reporting toggles. |
//+------------------------------------------------------------------+
#property strict

#include <RRMS\SEA_Config.mqh>

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

void ApplyPreset(const EStrategyPreset preset, ST_Settings &cfg)
{
   if(preset == PRESET_CUSTOM)
      return;

   // Do NOT modify cfg.PrintEffectiveConfig / cfg.DebugFlow
   // Do NOT modify UI toggles or reporting toggles (ExportCSV, ExportUseCommonFiles)

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
      cfg.Use_EmaSig        = false;
      cfg.Use_Adx           = false;
      cfg.Use_Macd          = false;
      cfg.Use_Rsi           = false;
      cfg.Use_Cci           = false;
      cfg.Use_Mfi           = false;
      cfg.Use_Sto           = false;
      cfg.Use_Bb            = false;
      cfg.Use_Psar          = false;
      cfg.Use_P123          = false;
      cfg.Use_Ross          = false;

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

      cfg.Use_EmaSig        = true;
      cfg.Use_Adx           = false;
      cfg.Use_Macd          = false;
      cfg.Use_Rsi           = false;
      cfg.Use_Cci           = false;
      cfg.Use_Mfi           = false;
      cfg.Use_Sto           = false;
      cfg.Use_Bb            = false;
      cfg.Use_Psar          = false;
      cfg.Use_P123          = false;
      cfg.Use_Ross          = false;

      cfg.SL_PlacementMode  = SL_ATR;
      cfg.SL_Mult           = 0.0;
      cfg.TP_Mult           = 0.0;
      cfg.Use_BE            = false;
      cfg.TrailMode         = TRAIL_NONE;

      cfg.MaType            = METHOD_SMA;
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

      cfg.Use_EmaSig     = true;
      cfg.Use_Adx        = true;
      cfg.Use_Macd       = true;
      cfg.Use_Rsi        = false;
      cfg.Use_Cci        = false;
      cfg.Use_Mfi        = false;
      cfg.Use_Sto        = false;
      cfg.Use_Bb         = false;
      cfg.Use_Psar       = false;
      cfg.Use_P123       = false;
      cfg.Use_Ross       = false;

      cfg.SL_PlacementMode = SL_ATR;
      cfg.SL_Mult        = 1.5;
      cfg.TP_Mult        = 3.0;
      cfg.Use_BE         = true;
      cfg.BE_Trig        = 1.0;
      cfg.BE_Buff        = 0.1;
      cfg.TrailMode      = TRAIL_ATR;
      cfg.Trail_Mult     = 1.5;

      cfg.MaType         = METHOD_EMA;
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

      cfg.Use_EmaSig     = true;
      cfg.Use_Adx        = true;
      cfg.Use_Macd       = true;
      cfg.Use_Rsi        = false;
      cfg.Use_Cci        = false;
      cfg.Use_Mfi        = false;
      cfg.Use_Sto        = false;
      cfg.Use_Bb         = false;
      cfg.Use_Psar       = false;
      cfg.Use_P123       = false;
      cfg.Use_Ross       = false;

      cfg.SL_PlacementMode = SL_ATR;
      cfg.SL_Mult        = 2.0;
      cfg.TP_Mult        = 4.0;
      cfg.Use_BE         = true;
      cfg.BE_Trig        = 1.0;
      cfg.BE_Buff        = 0.1;
      cfg.TrailMode      = TRAIL_ATR;
      cfg.Trail_Mult     = 2.0;

      cfg.MaType         = METHOD_EMA;
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

      cfg.Use_EmaSig     = false;
      cfg.Use_Adx        = false;
      cfg.Use_Macd       = false;
      cfg.Use_Rsi        = true;
      cfg.Use_Cci        = false;
      cfg.Use_Mfi        = false;
      cfg.Use_Sto        = true;
      cfg.Use_Bb         = true;
      cfg.Use_Psar       = false;
      cfg.Use_P123       = false;
      cfg.Use_Ross       = false;

      cfg.SL_PlacementMode = SL_ATR;
      cfg.SL_Mult        = 2.0;
      cfg.TP_Mult        = 2.0;
      cfg.Use_BE         = false;
      cfg.TrailMode      = TRAIL_NONE;
      return;
   }

   if(preset == PRESET_RRM)
   {
      // Preset is authoritative; do not use strategy inputs Inp_RRM_* for cfg fields.
      ERRMMode mode = Inp_RRM_Mode;
      if(mode == RRM_AUTO_BY_TF)
      {
         if(_Period == PERIOD_M1 || _Period == PERIOD_M5 || _Period == PERIOD_M15) mode = RRM_SCALP;
         else mode = RRM_SWING;
      }

      cfg.CloseOnReverse = true;
      cfg.BiasEnabled    = true;
      cfg.BiasMode       = BIAS_AUTO;
      cfg.MaType         = METHOD_EMA;

      if(mode == RRM_SCALP)
      {
         cfg.AutoStrat  = STRAT_PAIR_CROSS;
         cfg.BiasFastID = (int)ROLE_EMA1;
         cfg.BiasSlowID = (int)ROLE_EMA2;

         cfg.P_Ema1 = 34; cfg.P_Ema2 = 89; cfg.P_Ema3 = 34; cfg.P_Ema4 = 89;

         cfg.MaxSpread = 2.5;
         cfg.MinATR    = 12.5;
         cfg.MaxATR    = 0.0;
      }
      else
      {
         cfg.AutoStrat  = STRAT_PAIR_CROSS;
         cfg.BiasFastID = (int)ROLE_EMA3;
         cfg.BiasSlowID = (int)ROLE_EMA4;

         cfg.P_Ema1 = 5; cfg.P_Ema2 = 13; cfg.P_Ema3 = 34; cfg.P_Ema4 = 89;

         cfg.MaxSpread = 5.0;
         cfg.MinATR    = 8.0;
         cfg.MaxATR    = 0.0;
      }

      cfg.VoteThreshold = 4;
      cfg.Use_EmaSig    = true;
      cfg.Use_Adx       = false;
      cfg.Use_Macd      = true;
      cfg.Use_Rsi       = false;
      cfg.Use_Cci       = true;
      cfg.Use_Mfi       = false;
      cfg.Use_Sto       = false;
      cfg.Use_Bb        = false;
      cfg.Use_Psar      = true;
      cfg.Use_P123      = false;
      cfg.Use_Ross      = false;

      cfg.P_MacdFast = 8;
      cfg.P_MacdSlow = 13;
      cfg.P_MacdSig  = 8;

      cfg.RRM_RequirePullbackReclaim = false;
      cfg.RRM_RequireEmaDiv          = false;
      cfg.RRM_Lookback               = 5;
      cfg.RRM_MinDivPips             = 0.5;

      // Authoritative exits (stable defaults)
      cfg.TP_Mult = 3.0;

      cfg.Use_BE  = true;
      cfg.BE_Trig = 1.0;
      cfg.BE_Buff = 0.1;

      cfg.SL_PlacementMode    = SL_SWING_HIGHLOW;
      cfg.SL_Mult             = 0.0;
      cfg.SL_PsarPipsCushion  = 5.0;
      cfg.SL_SwingPipsCushion = 10.0;
      cfg.SL_FixedPips        = 20.0;

      cfg.TrailMode             = TRAIL_PSAR;
      cfg.PSAR_TrailCushionMode = PSAR_CUSHION_PIPS;
      cfg.PSAR_TrailPipsCushion = 5.0;
      cfg.P_PsarTrailCushionATR = 0.2;
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

         cfg.SL_PlacementMode = SL_PSAR_ATR;
         cfg.SL_Mult          = 1.25;
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

         cfg.SL_PlacementMode = SL_PSAR_ATR;
         cfg.SL_Mult          = 1.25;
         cfg.TP_Mult          = 4.0;
      }

      cfg.Use_EmaSig    = true;
      cfg.Use_Adx       = false;
      cfg.Use_Macd      = true;
      cfg.Use_Rsi       = false;
      cfg.Use_Cci       = false;
      cfg.Use_Mfi       = true;
      cfg.Use_Sto       = true;
      cfg.Use_Bb        = true;
      cfg.Use_Psar      = true;
      cfg.Use_P123      = false;
      cfg.Use_Ross      = false;

      cfg.VoteThreshold = 4;

      cfg.P_MacdFast = 8;
      cfg.P_MacdSlow = 13;
      cfg.P_MacdSig  = 8;

      cfg.StoMode    = STO_CROSS_SIGNAL;

      cfg.RRM_RequirePullbackReclaim = false;
      cfg.RRM_RequireEmaDiv          = false;
      cfg.RRM_Lookback               = 5;
      cfg.RRM_MinDivPips             = 0.5;

      cfg.Use_BE  = true;
      cfg.BE_Trig = 1.5;
      cfg.BE_Buff = 0.3;

      cfg.TrailMode             = TRAIL_PSAR;
      cfg.P_PsarTrailCushionATR = 0.5;
      return;
   }
}

// Temporary back-compat for any remaining callers.
// Core .mq5 should use InitializeConfig + ApplyPreset directly.
void ApplySettings()
{
   InitializeConfig();
   ApplyPreset(InpPreset, Settings);

}