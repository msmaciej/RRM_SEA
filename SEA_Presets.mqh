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

// TF+JPY-aware initial SL cushion mapping (suited for SL_PSAR_DOT / SL_MODE_SWING)
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
   //
   // Strategic filters (ATR, HTF) are preset-controlled.
   // Users who want full control: Use PRESET_CUSTOM
   // ================================================================
   const double op_MaxSpread = cfg.MaxSpread;

   const bool   op_UseTime   = cfg.UseTime;
   const int    op_StartHr   = cfg.StartHr;
   const int    op_EndHr     = cfg.EndHr;

   const bool   op_UseNews   = cfg.UseNews;
   const int    op_NewsPre   = cfg.NewsPre;
   const int    op_NewsPost  = cfg.NewsPost;
   
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
      // EMA PERIODS
      // ================================================================
      cfg.P_Ema1 = Inp_MA_Period;  // Primary MA (user-controlled via input)
      cfg.P_Ema2 = 13;
      cfg.P_Ema3 = 34;
      cfg.P_Ema4 = 89;
   
      // ================================================================
      // INDICATOR VOTING CONFIGURATION (Alphabetical)
      // ================================================================
      cfg.Ind_Adx_Enabled    = false;
      cfg.Ind_Atr_Enabled    = false;
      cfg.Ind_Bb_Enabled     = false;
      cfg.Ind_Cci_Enabled    = false;
      cfg.Ind_EmaSig_Enabled = false;
      cfg.Ind_Macd_Enabled   = false;
      cfg.Ind_Mfi_Enabled    = false;
      cfg.Ind_P123_Enabled   = false;
      cfg.Ind_Psar_Enabled   = false;
      cfg.Ind_Ross_Enabled   = false;
      cfg.Ind_Rsi_Enabled    = false;
      cfg.Ind_Sto_Enabled    = false;
   
      cfg.VoteMode = VOTE_MODE_ALL;
   
      // ================================================================
      // INDICATOR PERIODS & THRESHOLDS (Alphabetical)
      // ================================================================
      
      // ADX (Average Directional Index)
      cfg.P_Adx = 14;
      cfg.T_Adx = 20.0;
   
      // ATR (Average True Range)
      cfg.P_Atr       = 14;
      cfg.Use_ATRVote = false;
      cfg.MinATR      = 0.0;
      cfg.MaxATR      = 0.0;
   
      // Bollinger Bands
      cfg.P_Bb    = 20;
      cfg.P_BbDev = 2.0;
      cfg.BbMode  = BB_TREND_FOLLOW;
   
      // CCI (Commodity Channel Index)
      cfg.P_Cci   = 14;
      cfg.CciMode = CCI_TREND_ZERO;
   
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
      cfg.SL_Mult               = 0.0;
      cfg.SL_SwingPipsCushion   = 0.0;
      cfg.SL_PsarPipsCushion    = 0.0;
      cfg.TP_Mult               = 0.0;
      cfg.TP_Enabled            = false;
      cfg.TrailMode             = TRAIL_NONE;
      cfg.PSAR_TrailCushionMode = PSAR_CUSHION_PIPS;
      cfg.PSAR_TrailPipsCushion = 0.0;
      cfg.Use_BE                = false;
      cfg.BE_Mode               = BE_MODE_OFF;
      cfg.BE_Trig               = 0.0;
      cfg.BE_Buff               = 0.0;
   
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
      cfg.PSARStep        = 0.02;
      cfg.PSARMax         = 0.2;
   
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
      // POLICY A: RESTORE OPERATOR-CONTROLLED GATES
      // ================================================================
      cfg.MaxSpread = op_MaxSpread;
      cfg.UseTime   = op_UseTime;
      cfg.StartHr   = op_StartHr;
      cfg.EndHr     = op_EndHr;
      cfg.UseNews   = op_UseNews;
      cfg.NewsPre   = op_NewsPre;
      cfg.NewsPost  = op_NewsPost;
   
      // ================================================================
      // APPLY ADMIN OVERRIDES
      // ================================================================
      ApplyAdminOverrides(cfg);
      return;
   }

   if(preset == PRESET_RRM)
   {
      // ================================================================
      // PRESET_RRM: Strict No-ATR Trend Pullback Strategy
      // - Bias: User-selectable (BIAS_AUTO or BIAS_AUTO_PHASE via Inp_BiasMode)
      // - Entry: Layer detection (pullback-recovery on EMA zones)
      // - Votes: EMA ribbon + MACD + CCI + PSAR (4 votes, ALL must agree)
      // - ATR: Not used for voting or pre-filtering
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
      cfg.Ind_Adx_Enabled    = false;
      cfg.Ind_Atr_Enabled    = false;
      cfg.Ind_Bb_Enabled     = false;
      cfg.Ind_Cci_Enabled    = true;
      cfg.Ind_EmaSig_Enabled = true;
      cfg.Ind_Macd_Enabled   = true;
      cfg.Ind_Mfi_Enabled    = false;
      cfg.Ind_P123_Enabled   = false;
      cfg.Ind_Psar_Enabled   = true;
      cfg.Ind_Ross_Enabled   = false;
      cfg.Ind_Rsi_Enabled    = false;
      cfg.Ind_Sto_Enabled    = false;
   
      cfg.VoteMode = VOTE_MODE_ALL;
   
      // ================================================================
      // INDICATOR PERIODS & THRESHOLDS (Alphabetical)
      // ================================================================
      
      // ADX (Average Directional Index)
      cfg.P_Adx = 14;
      cfg.T_Adx = 20.0;
   
      // ATR (Average True Range)
      cfg.P_Atr       = 14;
      cfg.Use_ATRVote = false;
      cfg.MinATR      = 0.0;
      cfg.MaxATR      = 0.0;
   
      // Bollinger Bands
      cfg.P_Bb    = 20;
      cfg.P_BbDev = 2.0;
      cfg.BbMode  = BB_TREND_FOLLOW;
   
      // CCI (Commodity Channel Index)
      cfg.P_Cci   = 14;
      cfg.CciMode = CCI_TREND_ZERO;
   
      // MACD (Moving Average Convergence Divergence)
      cfg.P_MacdFast            = 8;
      cfg.P_MacdSlow            = 13;
      cfg.P_MacdSig             = 8;
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
      cfg.P_PsarStep         = 0.05;
      cfg.P_PsarMax          = 0.5;
      cfg.Vote_AllowPsarFlip = true;
      cfg.Vote_PsarFlipDelay = 2;
   
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
      cfg.SL_Mult               = 0.0;
      cfg.SL_SwingPipsCushion   = GetRecommendedInitialSlCushionPips();
      cfg.SL_PsarPipsCushion    = GetRecommendedInitialSlCushionPips();
      cfg.TP_Mult               = 3.0;
      cfg.TP_Enabled            = true;
      cfg.TrailMode             = TRAIL_PSAR;
      cfg.PSAR_TrailCushionMode = PSAR_CUSHION_PIPS;
      cfg.PSAR_TrailPipsCushion = GetRecommendedTrailPsarCushionPips();
      cfg.Use_BE                = false;
      cfg.BE_Mode               = BE_MODE_R_MULTIPLE;
      cfg.BE_Trig               = 1.5;
      cfg.BE_Buff               = 0.3;
   
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
      cfg.PSARStep        = 0.02;
      cfg.PSARMax         = 0.2;
   
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
      // POLICY A: RESTORE OPERATOR-CONTROLLED GATES
      // ================================================================
      cfg.MaxSpread = op_MaxSpread;
      cfg.UseTime   = op_UseTime;
      cfg.StartHr   = op_StartHr;
      cfg.EndHr     = op_EndHr;
      cfg.UseNews   = op_UseNews;
      cfg.NewsPre   = op_NewsPre;
      cfg.NewsPost  = op_NewsPost;
   
      // ================================================================
      // APPLY ADMIN OVERRIDES
      // ================================================================
      ApplyAdminOverrides(cfg);
      return;
   }

   if(preset == PRESET_TEST)
   {
      // ================================================================
      // PRESET_TEST: Isolated Indicator Testing Mode
      // Minimal configuration for testing ONE indicator at a time
      // - All gates disabled (no filtering noise)
      // - All indicators disabled by default (admin enables ONE to test)
      // - Simple bias: Position + Slope (BIAS_AUTO + STRAT_POSITION_SLOPE)
      // - Phase/layer detection OFF
      // - All RRM gates OFF
      // - Basic exits enabled for testing
      // - High spread/ATR tolerance for testing
      // ================================================================
   
      Print("═══════════════════════════════════════════════════════════");
      Print("  PRESET: TEST (Isolated Indicator Testing Mode)");
      Print("═══════════════════════════════════════════════════════════");
   
      // ================================================================
      // CORE STRATEGY SETTINGS
      // ================================================================
      cfg.CloseOnReverse    = false;
      cfg.BiasEnabled       = true;
      cfg.BiasMode          = BIAS_AUTO;
      cfg.AutoStrat         = STRAT_POSITION_SLOPE;
      cfg.BiasFastID        = (int)ROLE_EMA3;
      cfg.BiasSlowID        = (int)ROLE_EMA4;
      cfg.MaType            = METHOD_EMA;
      cfg.RequirePriceCross = false;
      cfg.MABenchmarkStrict = false;
      cfg.UseMACompatSizer  = false;
   
      // ================================================================
      // EMA PERIODS
      // ================================================================
      cfg.P_Ema1 = 5;
      cfg.P_Ema2 = 13;
      cfg.P_Ema3 = 34;
      cfg.P_Ema4 = 89;
   
      // ================================================================
      // INDICATOR VOTING CONFIGURATION (Alphabetical)
      // ================================================================
      cfg.Ind_Adx_Enabled    = false;
      cfg.Ind_Atr_Enabled    = false;
      cfg.Ind_Bb_Enabled     = false;
      cfg.Ind_Cci_Enabled    = false;
      cfg.Ind_EmaSig_Enabled = false;
      cfg.Ind_Macd_Enabled   = false;
      cfg.Ind_Mfi_Enabled    = false;
      cfg.Ind_P123_Enabled   = false;
      cfg.Ind_Psar_Enabled   = false;
      cfg.Ind_Ross_Enabled   = false;
      cfg.Ind_Rsi_Enabled    = false;
      cfg.Ind_Sto_Enabled    = false;
   
      cfg.VoteMode = VOTE_MODE_ALL;
   
      // ================================================================
      // INDICATOR PERIODS & THRESHOLDS (Alphabetical)
      // ================================================================
      
      // ADX (Average Directional Index)
      cfg.P_Adx = 14;
      cfg.T_Adx = 20.0;
   
      // ATR (Average True Range)
      cfg.P_Atr       = 14;
      cfg.Use_ATRVote = false;
      cfg.MinATR      = 0.0;
      cfg.MaxATR      = 0.0;
   
      // Bollinger Bands
      cfg.P_Bb    = 20;
      cfg.P_BbDev = 2.0;
      cfg.BbMode  = BB_TREND_FOLLOW;
   
      // CCI (Commodity Channel Index)
      cfg.P_Cci   = 14;
      cfg.CciMode = CCI_TREND_ZERO;
   
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
      cfg.RiskPercent       = 1.0;
      cfg.FixedLotSize      = 0.0;
      cfg.MaxTotalRisk      = 10.0;
      cfg.MaxOpenTrades     = 5;
      cfg.CountBEasZeroRisk = false;
   
      // ================================================================
      // EXIT STRATEGY CONFIGURATION
      // ================================================================
      cfg.ExitProfile           = EXIT_PROFILE_SIMPLE;
      cfg.SL_Mult               = 0.0;
      cfg.SL_SwingPipsCushion   = 10.0;
      cfg.SL_PsarPipsCushion    = 5.0;
      cfg.TP_Mult               = 3.0;
      cfg.TP_Enabled            = true;
      cfg.TrailMode             = TRAIL_NONE;
      cfg.PSAR_TrailCushionMode = PSAR_CUSHION_PIPS;
      cfg.PSAR_TrailPipsCushion = 0.0;
      cfg.Use_BE                = false;
      cfg.BE_Mode               = BE_MODE_OFF;
      cfg.BE_Trig               = 0.0;
      cfg.BE_Buff               = 0.0;
   
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
      cfg.PSARStep        = 0.02;
      cfg.PSARMax         = 0.2;
   
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
      cfg.ma_h_shift = 0;
      cfg.ma_v_shift = 1;
   
      // ================================================================
      // RRM DRAWDOWN PROTECTION
      // ================================================================
      cfg.RRM_EnableDrawdownProtection = false;
      cfg.RRM_MaxConsecutiveLosses     = 0;
      cfg.RRM_MaxTradesPerDay          = 0;
      cfg.RRM_MaxDailyDrawdownPct      = 0.0;
   
      // ================================================================
      // POLICY A: RESTORE OPERATOR-CONTROLLED GATES
      // ================================================================
      cfg.MaxSpread = op_MaxSpread;
      cfg.UseTime   = op_UseTime;
      cfg.StartHr   = op_StartHr;
      cfg.EndHr     = op_EndHr;
      cfg.UseNews   = op_UseNews;
      cfg.NewsPre   = op_NewsPre;
      cfg.NewsPost  = op_NewsPost;
   
      // ================================================================
      // APPLY ADMIN OVERRIDES
      // ================================================================
      ApplyAdminOverrides(cfg);
      return;
   }
}

//+------------------------------------------------------------------+
//| END OF FILE                                                      |
//+------------------------------------------------------------------+
