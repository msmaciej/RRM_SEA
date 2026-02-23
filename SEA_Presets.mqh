//+------------------------------------------------------------------+
//|                                                  SEA_Presets.mqh |
//|                                   Copyright 2026, SimpleEA System|
//| DESCRIPTION: Maps raw inputs to the global struct & applies      |
//|              hardcoded preset strategy overrides.                |
//+------------------------------------------------------------------+
#property strict

// Include the configuration state so we can read inputs and write to GlobalSettings
#include <RRMS\SEA_Config.mqh>

//+------------------------------------------------------------------+
//| SETTINGS APPLICATION & PRESET ORCHESTRATION                      |
//+------------------------------------------------------------------+

// --- [PASTE YOUR ENTIRE ApplySettings() FUNCTION HERE] ---
void ApplySettings() {
   // Defensive: wipe any previous values (prevents uninitialized fields and stale state)
   ZeroMemory(Settings);
   
   // OPTIMISED: Default behavior: keep execution filters HARD by default
   Settings.ATR_HardGate         = false;
   Settings.Use_ATRVote          = false;
   
   // --- A. Determine effective controls
   EEmaStrategy effEmaStrategy   = Inp_EmaStrategy;
   EMaMethod    effMaType        = Inp_MaType;
   EBiasMode    effBiasMode      = Inp_BiasMode;
   string note = "";
   bool easy_strategy = (effEmaStrategy != EMA_STRAT_CUSTOM);

   // NOTE: MT5 Inputs UI is static (cannot disable irrelevant fields).
   // We therefore keep a strict precedence model and emit explicit notes about ignored inputs.
   // Precedence: Preset overrides -> BiasEnabled -> BiasMode -> (if AUTO) EmaStrategy mapping.
   
   // --- B. Load base settings from inputs
   Settings.CloseOnReverse       = Inp_CloseOnReverse;
   Settings.RiskPercent          = Inp_RiskPercent;
   Settings.MaxSpread            = Inp_MaxSpreadPips;
   Settings.MinATR               = Inp_MinATRPips;
   Settings.MaxATR               = Inp_MaxATRPips; // NEW: upper volatility bound

   // Moving Average benchmark compatibility
   Settings.UseMACompatSizer     = false;
   Settings.MA_MaximumRiskPct    = Inp_MA_MaximumRiskPct;
   Settings.MA_DecreaseFactor    = Inp_MA_DecreaseFactor;
   Settings.RequirePriceCross    = false;
   Settings.MABenchmarkStrict    = false;

   // RRM trigger gates (OPTIMIZED: enabled by default)
   bool rrm_enable = (InpPreset == PRESET_RRM) || Inp_RRM_EnableInCustom;
   Settings.RRM_RequirePullbackReclaim = (rrm_enable ? Inp_RRM_RequirePullbackReclaim : false);
   Settings.RRM_RequireEmaDiv          = (rrm_enable ? Inp_RRM_RequireEmaDiv : false);
   Settings.RRM_Lookback         = Inp_RRM_Lookback;
   Settings.RRM_MinDivPips       = Inp_RRM_MinDivPips;
   
   Settings.BiasEnabled          = Inp_BiasEnabled;
   Settings.BiasMode             = effBiasMode;
   Settings.ManSide              = Inp_ManualSide;
   
   // --- C. Strategy mapping
   // BiasFastID/BiasSlowID are role indices (0..3) mapped in SEA_SignalEngine: 0=EMA1, 1=EMA2, 2=EMA3, 3=EMA4
   if(effEmaStrategy == EMA_STRAT_1_PRICE_CROSS)
   {
      Settings.AutoStrat         = STRAT_PRICE_CROSS;
      Settings.BiasFastID        = (int)ROLE_EMA1;
      Settings.BiasSlowID        = (int)ROLE_EMA1;
   }
   else if(effEmaStrategy == EMA_STRAT_2_CROSS_1_2)
   {
      Settings.AutoStrat         = STRAT_PAIR_CROSS;
      Settings.BiasFastID        = (int)ROLE_EMA1;
      Settings.BiasSlowID        = (int)ROLE_EMA2;
   }
   else if(effEmaStrategy == EMA_STRAT_2_CROSS_3_4)
   {
      Settings.AutoStrat         = STRAT_PAIR_CROSS;
      Settings.BiasFastID        = (int)ROLE_EMA3;
      Settings.BiasSlowID        = (int)ROLE_EMA4;
   }
   else
   {
      // CUSTOM: infer AutoStrat purely from the selected MA roles
      Settings.BiasFastID        = (int)Inp_BiasFast_Adv;
      Settings.BiasSlowID        = (int)Inp_BiasSlow_Adv;
      Settings.AutoStrat         = (Settings.BiasFastID == Settings.BiasSlowID) ? STRAT_PRICE_CROSS : STRAT_PAIR_CROSS;
   }

   // --- D. Execution / indicator method
   Settings.MaType               = effMaType;
   Settings.ma_h_shift           = Inp_MaHorShift;
   Settings.ma_v_shift           = Inp_MaVerShift;
   
   // --- E. Filters
   Settings.UseTime              = Inp_UseTime;
   Settings.StartHr              = Inp_StartHour;
   Settings.EndHr                = Inp_EndHour;
   Settings.UseNews              = Inp_UseNews;
   Settings.NewsPre              = Inp_NewsPre;
   Settings.NewsPost             = Inp_NewsPost;
   Settings.UseHTF               = Inp_UseHTF;
   Settings.HtfPeriod            = Inp_HtfPeriod;
   Settings.P_HtfEma             = Inp_HtfEmaPeriod;
   
   // --- F. Voting (OPTIMIZED: threshold now 3)
   Settings.VoteThreshold        = Inp_VoteThreshold;
   if(Settings.VoteThreshold <= 1)
   {
      if(note != "") note += " | ";
      note += "NOTE: VoteThreshold<=1 -> voting bypass (direction uses bias only).";
   }

   // --- G. Indicator periods / thresholds
   Settings.P_Ema1               = InpEma1Period;
   Settings.P_Ema2               = InpEma2Period;
   Settings.P_Ema3               = InpEma3Period;
   Settings.P_Ema4               = InpEma4Period;
   Settings.P_Adx                = InpAdxPeriod;
   Settings.T_Adx                = InpAdxThreshold;
   Settings.P_MacdFast           = InpMacdFast;
   Settings.P_MacdSlow           = InpMacdSlow;
   Settings.P_MacdSig            = InpMacdSig;
   Settings.P_Rsi                = InpRsiPeriod;
   Settings.T_RsiOB              = InpRsiOverbought;
   Settings.T_RsiOS              = InpRsiOversold;
   Settings.P_Cci                = InpCciPeriod;
   Settings.P_Mfi                = InpMfiPeriod;
   Settings.T_Mfi                = InpMfiLevel;
   Settings.P_StoK               = InpStoK;
   Settings.P_StoD               = InpStoD;
   Settings.P_StoSlow            = InpStoSlow;
   Settings.P_Bb                 = InpBbPeriod;
   Settings.P_BbDev              = InpBbDev;
   Settings.P_PsarStep           = InpPsarStep;
   Settings.P_PsarMax            = InpPsarMax;
   Settings.P_PsarTrailCushionATR = Inp_PSAR_TrailCushionATR;
   
   Settings.MacdMode             = InpMacdMode;
   Settings.RsiMode              = InpRsiMode;
   Settings.CciMode              = InpCciMode;
   Settings.StoMode              = InpStoMode;
   Settings.BbMode               = InpBbMode;
   
   // --- H. Active votes (OPTIMIZED: only 4 active, threshold 3)
   Settings.Use_EmaSig           = Inp_Use_EmaSig;   // Vote 1: EMA (KEEP)
   Settings.Use_Adx              = Inp_Use_Adx;      // Vote 2: ADX (NOW ENABLED)
   Settings.Use_Macd             = Inp_Use_Macd;     // Vote 3: MACD (KEEP)
   Settings.Use_Rsi              = Inp_Use_Rsi;      // DISABLED
   Settings.Use_Cci              = Inp_Use_Cci;      // DISABLED
   Settings.Use_Mfi              = Inp_Use_Mfi;      // DISABLED
   Settings.Use_Sto              = Inp_Use_Sto;      // Vote 4: Stochastic (KEEP, zone filter)
   Settings.Use_Bb               = Inp_Use_Bb;       // DISABLED (redundant)
   Settings.Use_Psar             = Inp_Use_Psar;     // DISABLED as vote (trailing only)
   Settings.Use_P123             = Inp_Use_P123;     // DISABLED
   Settings.Use_Ross             = Inp_Use_Ross;     // DISABLED
   
   // --- I. Exit / BE / trailing
   // SL - Stop-Loss: Initial SL Placement
   Settings.SL_PlacementMode     = Inp_SL_PlacementMode;
   Settings.SL_Mult              = Inp_SL_Mult;
   Settings.SL_PsarPipsCushion   = Inp_SL_PsarPipsCushion;
   Settings.SL_SwingPipsCushion  = Inp_SL_SwingPipsCushion;
   Settings.SL_FixedPips         = Inp_SL_FixedPips;
   
   // TR - TRailing-Stop: TP, BE
   Settings.TP_Mult              = Inp_TP_Mult;
   Settings.Use_BE               = Inp_Use_BE;
   Settings.BE_Trig              = Inp_BE_Trig;
   Settings.BE_Buff              = Inp_BE_Buff;
   Settings.TrailMode            = Inp_TrailMode;
   Settings.Trail_Mult           = Inp_Trail_Mult;
   
   // TR - TRailing-Stop: PSAR Trailing Cushion Mode
   Settings.PSAR_TrailCushionMode   = Inp_PSAR_TrailCushionMode;
   Settings.PSAR_TrailPipsCushion   = Inp_PSAR_TrailPipsCushion;
   
   // --- J. Reporting
   Settings.ExportCSV            = Inp_ExportCSV;
   
   // --- K. Apply presets (OPTIMIZED PRESET_RRM)
   
   //+------------------------------------------------------------------+
   //| PRESET_MA_BENCHMARK (UNCHANGED)                                  |
   //+------------------------------------------------------------------+

   if(InpPreset == PRESET_MA_BENCHMARK)
   {
      // Goal: match MetaTrader 5 built-in "Moving Average" Expert
      // - True price/MA cross confirmation (no "state" flip each bar)
      // - Always stop-and-reverse
      // - MA-style lot sizing: MaximumRisk + DecreaseFactor
      // - No additional filters, votes, or broker-side SL/TP

      Settings.CloseOnReverse    = true;
      Settings.BiasEnabled       = true;
      Settings.BiasMode          = BIAS_AUTO;
      Settings.AutoStrat         = STRAT_PRICE_CROSS;
      Settings.BiasFastID        = (int)ROLE_EMA1;
      Settings.BiasSlowID        = (int)ROLE_EMA1;
      Settings.RequirePriceCross = true;
      Settings.MABenchmarkStrict = true;

      Settings.UseMACompatSizer  = true;
      Settings.MA_MaximumRiskPct = Inp_MA_MaximumRiskPct;
      Settings.MA_DecreaseFactor = Inp_MA_DecreaseFactor;
      Settings.RiskPercent       = 0.0;

      Settings.VoteThreshold     = 1;
      Settings.MaxSpread         = 9999.0;
      Settings.MinATR            = 0.0;
      Settings.UseTime           = false;
      Settings.UseNews           = false;
      Settings.UseHTF            = false;
      
      Settings.Use_EmaSig        = false;
      Settings.Use_Adx           = false;
      Settings.Use_Macd          = false;
      Settings.Use_Rsi           = false;
      Settings.Use_Cci           = false;
      Settings.Use_Mfi           = false;
      Settings.Use_Sto           = false;
      Settings.Use_Bb            = false;
      Settings.Use_Psar          = false;
      Settings.Use_P123          = false;
      Settings.Use_Ross          = false;

      Settings.SL_PlacementMode  = SL_ATR; // Benchmark uses ATR-based SL
      Settings.SL_Mult           = 0.0;    // MA Benchmark: no broker SL
      Settings.TP_Mult           = 0.0;
      Settings.Use_BE            = false;
      Settings.TrailMode         = TRAIL_NONE;
      
      Settings.MaType            = METHOD_SMA;
      Settings.ma_h_shift        = Inp_MA_Shift;
      Settings.ma_v_shift        = 1; // confirmed (closed bar)
      Settings.P_Ema1            = Inp_MA_Period;
      
      effEmaStrategy             = EMA_STRAT_1_PRICE_CROSS;
      effMaType                  = Settings.MaType;
      effBiasMode                = Settings.BiasMode;
      
      if(note != "") note += " | ";
      note += "PRESET: MA_BENCHMARK (MT5 Moving Average compat) applied.";
   }

   //+------------------------------------------------------------------+
   //| PRESET_TREND_REVERSAL (UNCHANGED)                                |
   //+------------------------------------------------------------------+

   else if(InpPreset == PRESET_TREND_REVERSAL)
   {
      Settings.CloseOnReverse    = true;
      Settings.BiasEnabled       = true;
      Settings.BiasMode          = BIAS_AUTO;
      Settings.AutoStrat         = STRAT_PRICE_CROSS;
      Settings.BiasFastID        = (int)ROLE_EMA1;
      Settings.BiasSlowID        = (int)ROLE_EMA1;
      // Benchmark intent: require true cross confirmation (reduces overtrading vs price>MA state)
      Settings.RequirePriceCross = true;
      // Benchmark intent: evaluate confirmed bar like the MT5 sample (shift=1 and shift=2)
      Settings.ma_v_shift        = 1;
      
      Settings.VoteThreshold     = 1;
      Settings.MaxSpread         = 5.0;
      Settings.MinATR            = 0.0;
      Settings.UseTime           = false;
      Settings.UseNews           = false;
      Settings.UseHTF            = false;
      
      Settings.Use_EmaSig        = true;
      Settings.Use_Adx           = false;
      Settings.Use_Macd          = false;
      Settings.Use_Rsi           = false;
      Settings.Use_Cci           = false;
      Settings.Use_Mfi           = false;
      Settings.Use_Sto           = false;
      Settings.Use_Bb            = false;
      Settings.Use_Psar          = false;
      Settings.Use_P123          = false;
      Settings.Use_Ross          = false;

      Settings.SL_PlacementMode  = SL_ATR;
      Settings.SL_Mult           = 0.0;
      Settings.TP_Mult           = 0.0;
      Settings.Use_BE            = false;
      Settings.TrailMode         = TRAIL_NONE;
      
      // Preset intent: mimic Moving Average benchmark behaviour
      Settings.MaType            = METHOD_SMA;
      
      effEmaStrategy             = EMA_STRAT_1_PRICE_CROSS;
      effMaType                  = Settings.MaType;
      effBiasMode                = Settings.BiasMode;
      
      if(note != "") note += " | ";
      note += "PRESET: TREND_REVERSAL applied.";
   }
   
   //+------------------------------------------------------------------+
   //| PRESET_TREND_SCALP = Individual: Intraday confluence + HTF/News  |
   //+------------------------------------------------------------------+

   else if(InpPreset == PRESET_TREND_SCALP)
   {
      Settings.CloseOnReverse = true;
      Settings.BiasEnabled    = true;
      Settings.BiasMode       = BIAS_AUTO;
      Settings.AutoStrat      = STRAT_PAIR_CROSS;
      Settings.BiasFastID     = (int)ROLE_EMA1;
      Settings.BiasSlowID     = (int)ROLE_EMA2;

      // Expert intent: intraday continuation with hard gates + HTF veto + confluence votes
      Settings.VoteThreshold  = 3;
      Settings.MaxSpread      = 3.0;
      Settings.MinATR         = 5.0;
      Settings.UseTime        = false;
      Settings.UseNews        = true;
      Settings.UseHTF         = true;
      
      // Confluence votes ("Sniper" bundle)
      Settings.Use_EmaSig     = true;
      Settings.Use_Adx        = true;
      Settings.Use_Macd       = true;
      Settings.Use_Rsi        = false;
      Settings.Use_Cci        = false;
      Settings.Use_Mfi        = false;
      Settings.Use_Sto        = false;
      Settings.Use_Bb         = false;
      Settings.Use_Psar       = false;
      Settings.Use_P123       = false;
      Settings.Use_Ross       = false;
      
      // Exits: ATR envelope + BE + ATR trail (kept modest for intraday)
      Settings.SL_PlacementMode = SL_ATR;
      Settings.SL_Mult        = 1.5;
      Settings.TP_Mult        = 3.0;
      Settings.Use_BE         = true;
      Settings.BE_Trig        = 1.0;
      Settings.BE_Buff        = 0.1;
      Settings.TrailMode      = TRAIL_ATR;
      Settings.Trail_Mult     = 1.5;
      
      // Method: EMA is the default for faster reaction
      Settings.MaType         = METHOD_EMA;
      
      effEmaStrategy          = EMA_STRAT_2_CROSS_1_2;
      effMaType               = Settings.MaType;
      effBiasMode             = Settings.BiasMode;
      
      if(note != "") note += " | ";
      note += "PRESET: TREND_SCALP applied.";
   }
   
   //+------------------------------------------------------------------+
   //| PRESET_TREND_SWING = Institutional: HTF + News + ATR gates       |
   //+------------------------------------------------------------------+

   else if(InpPreset == PRESET_TREND_SWING)
   {
      // Institutional-style trend following: fewer trades, stronger gating, HTF veto
      Settings.CloseOnReverse = true;
      Settings.BiasEnabled    = true;
      Settings.BiasMode       = BIAS_AUTO;
      Settings.AutoStrat      = STRAT_PAIR_CROSS;
      Settings.BiasFastID     = (int)ROLE_EMA3;
      Settings.BiasSlowID     = (int)ROLE_EMA4;

      Settings.VoteThreshold  = 1;
      Settings.MaxSpread      = 5.0;
      Settings.MinATR         = 5.0;
      Settings.UseTime        = true;
      Settings.UseNews        = true;
      Settings.UseHTF         = true;

      Settings.Use_EmaSig     = true;
      Settings.Use_Adx        = true;
      Settings.Use_Macd       = true;
      Settings.Use_Rsi        = false;
      Settings.Use_Cci        = false;
      Settings.Use_Mfi        = false;
      Settings.Use_Sto        = false;
      Settings.Use_Bb         = false;
      Settings.Use_Psar       = false;
      Settings.Use_P123       = false;
      Settings.Use_Ross       = false;
      
      Settings.SL_PlacementMode = SL_ATR;
      Settings.SL_Mult        = 2.0;
      Settings.TP_Mult        = 4.0;
      Settings.Use_BE         = true;
      Settings.BE_Trig        = 1.0;
      Settings.BE_Buff        = 0.1;
      Settings.TrailMode      = TRAIL_ATR;
      Settings.Trail_Mult     = 2.0;
      
      Settings.MaType         = METHOD_EMA;
      
      effEmaStrategy          = EMA_STRAT_2_CROSS_3_4;
      effMaType               = Settings.MaType;
      effBiasMode             = Settings.BiasMode;
      
      if(note != "") note += " | ";
      note += "PRESET: TREND_SWING applied.";
   }
   
   //+------------------------------------------------------------------+
   //| PRESET_RANGE_GRID (UNCHANGED)                                    |
   //+------------------------------------------------------------------+

   else if(InpPreset == PRESET_RANGE_GRID)
   {
      // Consultant-style conservative mean reversion: only trade when gates pass
      Settings.CloseOnReverse = false;
      Settings.BiasEnabled    = true;
      Settings.BiasMode       = BIAS_AUTO;
      Settings.AutoStrat      = STRAT_PAIR_CROSS;
      Settings.BiasFastID     = (int)ROLE_EMA2;
      Settings.BiasSlowID     = (int)ROLE_EMA4;

      Settings.VoteThreshold  = 4;
      Settings.MaxSpread      = 4.0;
      Settings.MinATR         = 2.0;
      Settings.UseTime        = true;
      Settings.UseNews        = true;
      Settings.UseHTF         = true;
      
      // Mean reversion votes
      Settings.RsiMode        = RSI_FILTER_EXTREME;
      Settings.StoMode        = STO_ZONE_FILTER;
      Settings.BbMode         = BB_MEAN_REVERSION;

      Settings.Use_EmaSig     = false;
      Settings.Use_Adx        = false;
      Settings.Use_Macd       = false;
      Settings.Use_Rsi        = true;
      Settings.Use_Cci        = false;
      Settings.Use_Mfi        = false;
      Settings.Use_Sto        = true;
      Settings.Use_Bb         = true;
      Settings.Use_Psar       = false;
      Settings.Use_P123       = false;
      Settings.Use_Ross       = false;
      
      Settings.SL_PlacementMode = SL_ATR;
      Settings.SL_Mult        = 2.0;
      Settings.TP_Mult        = 2.0;
      Settings.Use_BE         = false;
      Settings.TrailMode      = TRAIL_NONE;
      
      effEmaStrategy          = EMA_STRAT_2_CROSS_3_4;
      effMaType               = Settings.MaType;
      effBiasMode             = Settings.BiasMode;
      
      if(note != "") note += " | ";
      note += "PRESET: RANGE_GRID applied.";
   }

   //+------------------------------------------------------------------+
   //| PRESET_RRM - WITH FULL DIAGNOSTICS
   //+------------------------------------------------------------------+
   else if(InpPreset == PRESET_RRM)
   {
      // RRM Trend Pullback: Trend bias (EMA) + HTF confirmation + pullback/reclaim trigger
      // Confirmations: MACD alignment + PSAR not blocking + EMA convergence->divergence
   
      // Determine RRM mode: SCALP or SWING
      ERRMMode mode = Inp_RRM_Mode;
      if(mode == RRM_AUTO_BY_TF)
      {
         // Auto mapping: fast intraday => scalp; higher TF => swing
         if(_Period == PERIOD_M1 || _Period == PERIOD_M5 || _Period == PERIOD_M15)
            mode = RRM_SCALP;
         else
            mode = RRM_SWING;
      }
   
      // ============ USE INPUT PARAMETERS FOR STRATEGY ============
      Settings.AutoStrat      = Inp_RRM_AutoStrat; // User selects: PAIR_CROSS / PRICE_CROSS / SINGLE_SLOPE
      
      // ★★★ DIAGNOSTIC: Show input before casting ★★★
      PrintFormat("PRESET_RRM: Inp_RRM_BiasEMA input value = %d (ROLE_EMA1=0, ROLE_EMA2=1, ROLE_EMA3=2, ROLE_EMA4=3)",
                  (int)Inp_RRM_BiasEMA);
                  
      // Set bias EMAs based on user input and selected strategy
      if(Inp_RRM_AutoStrat == STRAT_PRICE_CROSS || Inp_RRM_AutoStrat == STRAT_SINGLE_SLOPE)
      {
         // Single EMA strategies - both use same EMA
         Settings.BiasFastID  = (int)Inp_RRM_BiasEMA;
         Settings.BiasSlowID  = (int)Inp_RRM_BiasEMA;
         
         // ★★★ DIAGNOSTIC: Confirm assignment ★★★
         PrintFormat("PRESET_RRM: SINGLE/PRICE strategy → BiasFastID=%d BiasSlowID=%d (both same EMA)",
                     Settings.BiasFastID, Settings.BiasSlowID);
      }
      else // STRAT_PAIR_CROSS
      {
         // Pair strategy - use selected EMA and next one
         Settings.BiasFastID  = (int)Inp_RRM_BiasEMA;
         Settings.BiasSlowID  = (int)Inp_RRM_BiasEMA + 1;  // Next EMA (e.g., EMA1->EMA2 or EMA3->EMA4)
         
         // ★★★ DIAGNOSTIC: Confirm assignment ★★★
         PrintFormat("PRESET_RRM: PAIR_CROSS strategy → BiasFastID=%d BiasSlowID=%d",
                     Settings.BiasFastID, Settings.BiasSlowID);
      }
   
      Settings.CloseOnReverse = true;
      Settings.BiasEnabled    = true;
      Settings.BiasMode       = BIAS_AUTO;
      Settings.MaType         = METHOD_EMA; // RRM uses EMA ribbon
      Settings.UseHTF         = Inp_UseHTF;
      Settings.UseNews        = Inp_UseNews;
      Settings.UseTime        = Inp_UseTime;
      
      // Mode-specific settings (SCALP vs SWING)
      if(mode == RRM_SCALP)
      {
         // Legacy RRM ribbon (matches historical RRM controller visualization)
         Settings.P_Ema1      = 34; // 21 .. 5 .. BEST: 34
         Settings.P_Ema2      = 89; // 89 .. 13 .. BEST: 89
         Settings.P_Ema3      = 34;
         Settings.P_Ema4      = 89;
   
         Settings.MaxSpread   = 2.5; // ORG: 2.5 .. BEST: 3.5
         Settings.MinATR      = 12.5; // ORG: 3.0 .. BEST: 12.5
         Settings.SL_Mult     = 0.0; // Disabled: Use swing-based SL instead
         Settings.TP_Mult     = Inp_TP_Mult; // Use input R:R ratio (not ATR multiplier)
         
         PrintFormat("PRESET_RRM: Mode=SCALP → EMA periods: 34,89,34,89");
      }
      else // RRM_SWING
      {
         // Legacy RRM ribbon
         Settings.P_Ema1      = 5;  // 5
         Settings.P_Ema2      = 13; // 13
         Settings.P_Ema3      = 34; // 34
         Settings.P_Ema4      = 89; // 89
         
         Settings.MaxSpread   = 5.0; // ORG: 5.0
         Settings.MinATR      = 8.0; // ORG: 5.0 .. BEST: 3.0, 5.0, 8.0, 10.0
         Settings.SL_Mult     = 0.0; // Disabled: Use swing-based SL instead
         Settings.TP_Mult     = Inp_TP_Mult; // Use input R:R ratio (not ATR multiplier)
         
         PrintFormat("PRESET_RRM: Mode=SWING → EMA periods: 5,13,34,89");
      }
      
      // ★★★ DIAGNOSTIC: Show final period mapping ★★★
      int actual_fast_period = (Settings.BiasFastID==0) ? Settings.P_Ema1 : 
                               (Settings.BiasFastID==1) ? Settings.P_Ema2 : 
                               (Settings.BiasFastID==2) ? Settings.P_Ema3 : Settings.P_Ema4;
      
      int actual_slow_period = (Settings.BiasSlowID==0) ? Settings.P_Ema1 : 
                               (Settings.BiasSlowID==1) ? Settings.P_Ema2 : 
                               (Settings.BiasSlowID==2) ? Settings.P_Ema3 : Settings.P_Ema4;
      
      PrintFormat("PRESET_RRM: Final mapping → BiasFastID=%d uses EMA%d(period=%d), BiasSlowID=%d uses EMA%d(period=%d)",
                  Settings.BiasFastID, Settings.BiasFastID+1, actual_fast_period,
                  Settings.BiasSlowID, Settings.BiasSlowID+1, actual_slow_period);
                  
      // Confirmations as votes
      Settings.VoteThreshold  = 4;
      Settings.Use_EmaSig     = true; // EMA signal vote
      Settings.Use_Adx        = false;
      Settings.Use_Macd       = true;
      Settings.Use_Rsi        = false;
      Settings.Use_Cci        = true;
      Settings.Use_Mfi        = false;
      Settings.Use_Sto        = false;
      Settings.Use_Bb         = false;
      Settings.Use_Psar       = true;
      Settings.Use_P123       = false;
      Settings.Use_Ross       = false;
      
      // Legacy MACD parameters (RRM controller): 8/13/8
      Settings.P_MacdFast     = 8;
      Settings.P_MacdSlow     = 13;
      Settings.P_MacdSig      = 8;
      
      // RRM optional gates
      Settings.RRM_RequirePullbackReclaim = Inp_RRM_RequirePullbackReclaim;
      Settings.RRM_RequireEmaDiv          = Inp_RRM_RequireEmaDiv;
      Settings.RRM_Lookback               = Inp_RRM_Lookback;
      Settings.RRM_MinDivPips             = Inp_RRM_MinDivPips;
      
      // Exits / management - Use input values for user control
      Settings.Use_BE                     = Inp_Use_BE;
      Settings.BE_Trig                    = Inp_BE_Trig; // Use input R:R ratio (not ATR multiplier)
      Settings.BE_Buff                    = Inp_BE_Buff;
      
      // =====================================================================
      // ★★★ CONFIGURE INITIAL SL: USE INPUT PARAMETERS ★★★
      // =====================================================================
      Settings.SL_PlacementMode           = Inp_SL_PlacementMode; // User can choose: SWING_HIGHLOW, PSAR_PIPS, etc.
      Settings.SL_PsarPipsCushion         = Inp_SL_PsarPipsCushion;
      Settings.SL_SwingPipsCushion        = Inp_SL_SwingPipsCushion;
      Settings.SL_FixedPips               = Inp_SL_FixedPips;
      
      // =====================================================================
      // ★★★ CONFIGURE TRAILING STOP: USE INPUT PARAMETERS ★★★
      // =====================================================================
      Settings.TrailMode                  = Inp_TrailMode; // User can choose: PSAR, ATR, FRACTAL, NONE
      Settings.PSAR_TrailCushionMode      = Inp_PSAR_TrailCushionMode; // User can choose: PIPS or ATR
      Settings.PSAR_TrailPipsCushion      = Inp_PSAR_TrailPipsCushion;
      Settings.P_PsarTrailCushionATR      = Inp_PSAR_TrailCushionATR;
   
      Settings.MaType                     = METHOD_EMA;
      
      effEmaStrategy                      = (mode == RRM_SCALP ? EMA_STRAT_2_CROSS_1_2 : EMA_STRAT_2_CROSS_3_4);
      effMaType                           = Settings.MaType;
      effBiasMode                         = Settings.BiasMode;
      
      if(note != "") note += " | ";
      note += "PRESET_RRM: TREND_PULLBACK applied (using input SL/TP/BE/Trail settings for user control).";
   }
   
   //+------------------------------------------------------------------+
   //| PRESET_RRM_ATR (LEGACY-ALIGNED, COMMENTS RESTORED)
   //+------------------------------------------------------------------+

   else if(InpPreset == PRESET_RRM_ATR)
   {
      // RRM Trend Pullback (LEGACY-ALIGNED + EXECUTION-SAFE ATR)
      //
      // Architecture fit (Filters → Bias → Votes → ATR Exits/Management):
      //   1) Filters (Spread/News/Session/HTF) gate out truly untradeable conditions.
      //   2) Bias is defined by EMA pair trend direction (AUTO bias).
      //   3) Votes provide confluence confirmations (do NOT require all votes to fire).
      //   4) ATR is primarily used for stop/target sizing and PSAR trailing cushion.
      //
      // Key intent vs earlier "OPTIMIZED" variants:
      //   - PullbackReclaim and EMA-Div are *setup confirmations* (stateful / lookback-based).
      //   - MaxATR is NOT used as a hard veto in RRM (news/spread/session already protect execution).
      //   - MinATR is scaled by timeframe so M5/M15 are not starved while M1 still avoids dead zones.
      
      // Determine RRM mode
      ERRMMode mode = Inp_RRM_Mode;
      if(mode == RRM_AUTO_BY_TF)
      {
         // Auto mapping: fast intraday => scalp; higher TF => swing
         if(_Period == PERIOD_M1 || _Period == PERIOD_M5 || _Period == PERIOD_M15)
            mode = RRM_SCALP;
         else
            mode = RRM_SWING;
      }

      Settings.CloseOnReverse = true;
      Settings.BiasEnabled    = true;
      Settings.BiasMode       = BIAS_AUTO;
      Settings.AutoStrat      = STRAT_PAIR_CROSS;
      
      Settings.MaType         = METHOD_EMA; // RRM uses EMA ribbon
      Settings.UseHTF         = Inp_UseHTF;
      Settings.UseNews        = Inp_UseNews;
      
      // ATR handling (expert guidance):
      // - HARD ATR gating tends to starve signals on low TFs and during quiet regimes.
      // - For RRM we treat ATR as a *soft* confluence vote (regime preference), not a blocker.
      Settings.ATR_HardGate = false; // do not block entries if ATR is outside band
      Settings.Use_ATRVote  = true;  // add one vote when ATR is within [MinATR, MaxATR]

      // Scalp vs Swing bias pair (pullback trigger uses BiasFast EMA)
      if(mode == RRM_SCALP)
      {
         Settings.BiasFastID  = (int)ROLE_EMA1;
         Settings.BiasSlowID  = (int)ROLE_EMA2;
         Settings.UseTime     = Inp_UseTime;
         
         // Legacy RRM ribbon (visual + behaviour baseline)
         Settings.P_Ema1 = 34;
         Settings.P_Ema2 = 89;
         Settings.P_Ema3 = 34;
         Settings.P_Ema4 = 89;

         Settings.MaxSpread   = 2.5;
         
         // ATR floor by TF (pips): M1 needs a higher floor; M5/M15 should not be starved
         Settings.MinATR      = (_Period == PERIOD_M1 ? 12.5 : 5.0);
         Settings.MaxATR      = 0.0;  // IMPORTANT: disable hard max-ATR veto in RRM

         Settings.SL_PlacementMode = SL_PSAR_ATR; // Use PSAR with ATR cushion for RRM
         Settings.SL_Mult     = 1.25;
         Settings.TP_Mult     = 4.0;
      }
      else // RRM_SWING
      {
         Settings.BiasFastID  = (int)ROLE_EMA3;
         Settings.BiasSlowID  = (int)ROLE_EMA4;
         Settings.UseTime     = Inp_UseTime;
         
         // Legacy RRM ribbon
         Settings.P_Ema1 = 5;
         Settings.P_Ema2 = 13;
         Settings.P_Ema3 = 34;
         Settings.P_Ema4 = 89;

         Settings.MaxSpread   = 5.0;
         Settings.MinATR      = 5.0;  // moderate: swing still prefers adequate range
         Settings.MaxATR      = 0.0;  // IMPORTANT: disable hard max-ATR veto in RRM
         
         Settings.SL_PlacementMode = SL_PSAR_ATR; // Use PSAR with ATR cushion for RRM
         Settings.SL_Mult     = 1.25;
         Settings.TP_Mult     = 4.0;
      }

      // --- Votes (confluence confirmations; do not hard-starve entries) ---
      // We keep the "legacy" confirmation bundle but require only a subset.
      Settings.Use_EmaSig     = true;   // Trend/trigger vote
      Settings.Use_Adx        = false;  // ADX is useful in some markets, but not default for RRM
      Settings.Use_Macd       = true;
      Settings.Use_Rsi        = false;
      Settings.Use_Cci        = false;
      Settings.Use_Mfi        = true;
      Settings.Use_Sto        = true;
      Settings.Use_Bb         = true;
      Settings.Use_Psar       = true;
      Settings.Use_P123       = false;
      Settings.Use_Ross       = false;
      
      // Threshold: default 4-of-enabled (user can still override via global Inp_VoteThreshold)
      int enabled_votes = 0;
      if(Settings.Use_EmaSig) enabled_votes++;
      if(Settings.Use_Macd)   enabled_votes++;
      if(Settings.Use_Mfi)    enabled_votes++;
      if(Settings.Use_Sto)    enabled_votes++;
      if(Settings.Use_Bb)     enabled_votes++;
      if(Settings.Use_Psar)   enabled_votes++;
      if(Settings.Use_ATRVote) enabled_votes++; // ATR regime vote (soft)

      int thr = 4;
      if(Inp_VoteThreshold > 0) thr = Inp_VoteThreshold;
      if(thr > enabled_votes) thr = enabled_votes;
      if(thr < 1) thr = 1;
      Settings.VoteThreshold = thr;
      
      // Legacy MACD parameters (RRM controller): 8/13/8
      Settings.P_MacdFast     = 8;
      Settings.P_MacdSlow     = 13;
      Settings.P_MacdSig      = 8;
      
      // Stochastic mode: keep classic cross behaviour for responsiveness
      Settings.StoMode        = STO_CROSS_SIGNAL;
      
      // RRM setup confirmations (stateful, lookback-based; not single-bar hard gates)
      Settings.RRM_RequirePullbackReclaim = Inp_RRM_RequirePullbackReclaim;
      Settings.RRM_RequireEmaDiv          = Inp_RRM_RequireEmaDiv;
      Settings.RRM_Lookback              = Inp_RRM_Lookback;
      Settings.RRM_MinDivPips            = Inp_RRM_MinDivPips;
      
      // Exits / management
      Settings.Use_BE         = true;
      Settings.BE_Trig        = 1.5;
      Settings.BE_Buff        = 0.3;
      Settings.TrailMode      = TRAIL_PSAR;
      Settings.P_PsarTrailCushionATR = 0.5;
      
      effEmaStrategy          = (mode == RRM_SCALP ? EMA_STRAT_2_CROSS_1_2 : EMA_STRAT_2_CROSS_3_4);
      effMaType               = Settings.MaType;
      effBiasMode             = Settings.BiasMode;
      
      if(note != "") note += " | ";
      note += "PRESET_RRM_ATR: TREND_PULLBACK (LEGACY-ALIGNED, ATR-SAFE) applied.";
   }

   // --- L. Final effective provenance + UI clarity + UI clarity
   string dir_source = "AUTO";
   if(!Settings.BiasEnabled)
      dir_source = "DISABLED";
   else if(Settings.BiasMode == BIAS_MANUAL)
   {
      if(Settings.ManSide == SIDE_LONG)
         dir_source = "MANUAL_LONG";
      else if(Settings.ManSide == SIDE_SHORT)
         dir_source = "MANUAL_SHORT";
      else
         dir_source = "AUTO_FALLBACK";
   }
   g_effectiveDirSource = dir_source;
   
   // UI clarity flags
   bool uses_auto_logic  = (Settings.BiasEnabled && (Settings.BiasMode == BIAS_AUTO || (Settings.BiasMode == BIAS_MANUAL && Settings.ManSide == SIDE_BOTH)));
   bool uses_manual_fix  = (Settings.BiasEnabled && Settings.BiasMode == BIAS_MANUAL && (Settings.ManSide == SIDE_LONG || Settings.ManSide == SIDE_SHORT));
   bool uses_adv_mapping = (uses_auto_logic && effEmaStrategy == EMA_STRAT_CUSTOM);

   string used = "";
   string ignored = "";
   if(!Settings.BiasEnabled)
   {
      used = "BiasEnabled=OFF";
      ignored = "BiasMode, ManualSide, EmaStrategy, AdvMapping";
   }
   else if(uses_manual_fix)
   {
      used = StringFormat("ManualSide=%s", EnumToString(Settings.ManSide));
      ignored = "EmaStrategy, AdvMapping";
   }
   else
   {
      used = "AUTO";
      if(Settings.BiasMode == BIAS_AUTO)
         ignored = "";
      else
         used = "AUTO_FALLBACK";

      used += StringFormat(" | EmaStrategy=%s", EnumToString(effEmaStrategy));
      if(uses_adv_mapping)
      {
         used += StringFormat(" | AdvMapping(Fast=%d Slow=%d)", Settings.BiasFastID, Settings.BiasSlowID);
      }
      else
      {
         if(ignored != "") ignored += ", ";
         ignored += "AdvMapping";
      }

      if(Settings.BiasMode == BIAS_AUTO)
      {
         if(ignored != "") ignored += ", ";
         ignored += "ManualSide";
      }
   }

   g_ui_used_flags = used;
   g_ui_ignored_flags = ignored;
   
   // MA inputs provenance
   g_ui_ma_source = (InpPreset == PRESET_MA_BENCHMARK ? "BENCHMARK (0c)" : "CUSTOM (5)");
   
   // Explicit ignored MA inputs
   if(InpPreset == PRESET_MA_BENCHMARK)
   {
      if(g_ui_ignored_flags != "") g_ui_ignored_flags += ", ";
      g_ui_ignored_flags += "CustomMaType, CustomMaHorShift, CustomMaVerShift, CustomEma1Period, RiskPercent";

      // Warn once (benchmark preset ignores CUSTOM indicator inputs).
      if(!g_warned_bench_ignored)
      {
         bool mismatch = false;
         if(Inp_MaType != METHOD_SMA) mismatch = true;
         if(Inp_MaHorShift != Inp_MA_Shift) mismatch = true;
         if(InpEma1Period != Inp_MA_Period) mismatch = true;
         if(Inp_MaVerShift != 1) mismatch = true;

         Print("WARNING: PRESET_MA_BENCHMARK uses ONLY benchmark inputs (group 0c) and ignores CUSTOM MA inputs (group 5) and RiskPercent.");
         Print("Effective MA (USED): Method=", EnumToString(Settings.MaType), " Period=", Settings.P_Ema1, " Shift=", Settings.ma_h_shift, " BarShift=", Settings.ma_v_shift, ".");
         if(mismatch)
            Print("NOTE: Your CUSTOM MA settings differ from benchmark values; they are ignored in PRESET_MA_BENCHMARK.");
         g_warned_bench_ignored = true;
      }
   }
   else
   {
      if(g_ui_ignored_flags != "") g_ui_ignored_flags += ", ";
      g_ui_ignored_flags += "BenchmarkMA(MaxRisk/Dec/Period/Shift)";

      // Warn once if user changed benchmark inputs but is not running the benchmark preset.
      bool bench_changed = false;
      if(Inp_MA_MaximumRiskPct != 0.02) bench_changed = true;
      if(Inp_MA_DecreaseFactor != 3.0) bench_changed = true;
      if(Inp_MA_Period != 12) bench_changed = true;
      if(Inp_MA_Shift != 6) bench_changed = true;
      if(bench_changed && !g_warned_custom_bench)
      {
         Print("INFO: Benchmark inputs (group 0c) are ignored unless Preset=PRESET_MA_BENCHMARK.");
         g_warned_custom_bench = true;
      }
   }

   // Preset override disclosure
   string overrides = "";
   if(InpPreset != PRESET_CUSTOM)
   {
      if(Settings.MaType != Inp_MaType)                  AddListItem(overrides, "MaType");
      if(InpPreset == PRESET_MA_BENCHMARK)
      {
         if(Settings.P_Ema1 != Inp_MA_Period)            AddListItem(overrides, "MA_Period(Bench)");
         if(Settings.ma_h_shift != Inp_MA_Shift)         AddListItem(overrides, "MA_Shift(Bench)");
      }
      else
      {
         if(Settings.ma_h_shift != Inp_MaHorShift)       AddListItem(overrides, "MaHorShift");
         if(Settings.ma_v_shift != Inp_MaVerShift)       AddListItem(overrides, "MaVerShift");
         if(Settings.P_Ema1 != InpEma1Period)            AddListItem(overrides, "Ema1Period");
      }
      if(Settings.BiasMode != Inp_BiasMode)              AddListItem(overrides, "BiasMode");
      if(effEmaStrategy != Inp_EmaStrategy)              AddListItem(overrides, "EmaStrategy");
      if(Settings.CloseOnReverse != Inp_CloseOnReverse)  AddListItem(overrides, "CloseOnReverse");
      if(Settings.VoteThreshold != Inp_VoteThreshold)    AddListItem(overrides, "VoteThreshold");
      if(Settings.MaxSpread != Inp_MaxSpreadPips)        AddListItem(overrides, "MaxSpreadPips");
      if(Settings.MinATR != Inp_MinATRPips)              AddListItem(overrides, "MinATRPips");
      if(Settings.MaxATR != Inp_MaxATRPips)              AddListItem(overrides, "MaxATRPips");
      if(Settings.UseTime != Inp_UseTime)                AddListItem(overrides, "UseTime");
      if(Settings.UseNews != Inp_UseNews)                AddListItem(overrides, "UseNews");
      if(Settings.UseHTF != Inp_UseHTF)                  AddListItem(overrides, "UseHTF");
      if(Settings.HtfPeriod != Inp_HtfPeriod)            AddListItem(overrides, "HtfPeriod");
      if(Settings.P_HtfEma != Inp_HtfEmaPeriod)          AddListItem(overrides, "HtfEmaPeriod");
      
      // Vote toggles and modes (frequently overridden by presets)
      if(Settings.Use_EmaSig != Inp_Use_EmaSig)          AddListItem(overrides, "Use_EmaSig");
      if(Settings.Use_Adx != Inp_Use_Adx)                AddListItem(overrides, "Use_Adx");
      if(Settings.Use_Macd != Inp_Use_Macd)              AddListItem(overrides, "Use_Macd");
      if(Settings.Use_Rsi != Inp_Use_Rsi)                AddListItem(overrides, "Use_Rsi");
      if(Settings.Use_Cci != Inp_Use_Cci)                AddListItem(overrides, "Use_Cci");
      if(Settings.Use_Mfi != Inp_Use_Mfi)                AddListItem(overrides, "Use_Mfi");
      if(Settings.Use_Sto != Inp_Use_Sto)                AddListItem(overrides, "Use_Sto");
      if(Settings.Use_Bb != Inp_Use_Bb)                  AddListItem(overrides, "Use_Bb");
      if(Settings.Use_Psar != Inp_Use_Psar)              AddListItem(overrides, "Use_Psar");
      if(Settings.Use_P123 != Inp_Use_P123)              AddListItem(overrides, "Use_P123");
      if(Settings.Use_Ross != Inp_Use_Ross)              AddListItem(overrides, "Use_Ross");
      if(Settings.MacdMode != InpMacdMode)               AddListItem(overrides, "MacdMode");
      if(Settings.RsiMode != InpRsiMode)                 AddListItem(overrides, "RsiMode");
      if(Settings.CciMode != InpCciMode)                 AddListItem(overrides, "CciMode");
      if(Settings.StoMode != InpStoMode)                 AddListItem(overrides, "StoMode");
      if(Settings.BbMode != InpBbMode)                   AddListItem(overrides, "BbMode");
      if(Settings.SL_Mult != Inp_SL_Mult)                AddListItem(overrides, "SL_Mult");
      if(Settings.TP_Mult != Inp_TP_Mult)                AddListItem(overrides, "TP_Mult");
      if(Settings.Use_BE != Inp_Use_BE)                  AddListItem(overrides, "Use_BE");
      if(Settings.BE_Trig != Inp_BE_Trig)                AddListItem(overrides, "BE_Trig");
      if(Settings.BE_Buff != Inp_BE_Buff)                AddListItem(overrides, "BE_Buff");
      if(Settings.TrailMode != Inp_TrailMode)            AddListItem(overrides, "TrailMode");
      if(Settings.Trail_Mult != Inp_Trail_Mult)          AddListItem(overrides, "Trail_Mult");
      if(Settings.RRM_RequirePullbackReclaim != Inp_RRM_RequirePullbackReclaim) AddListItem(overrides, "RRM_Pullback");
      if(Settings.RRM_RequireEmaDiv != Inp_RRM_RequireEmaDiv) AddListItem(overrides, "RRM_EmaDiv");
   }
   g_ui_overrides = overrides;
   
   // Rebuild effective note
   string note2 = note;
   if(!Settings.BiasEnabled)
   {
      if(note2 != "") note2 += " | ";
      note2 += "NOTE: BiasEnabled=false -> direction neutral (no new entries).";
   }
   else if(uses_manual_fix)
   {
      if(note2 != "") note2 += " | ";
      note2 += "NOTE: BiasMode=MANUAL (fixed direction) -> EmaStrategy and AdvMapping ignored.";
   }
   else if(Settings.BiasMode == BIAS_MANUAL && Settings.ManSide == SIDE_BOTH)
   {
      if(note2 != "") note2 += " | ";
      note2 += "NOTE: BiasMode=MANUAL and ManualSide=BOTH -> no restriction; AUTO bias logic used.";
   }
   else if(Settings.BiasMode == BIAS_AUTO && effEmaStrategy != EMA_STRAT_CUSTOM)
   {
      if(note2 != "") note2 += " | ";
      note2 += "NOTE: BiasMode=AUTO and EmaStrategy!=CUSTOM -> AdvMapping ignored.";
   }

   if(g_ui_overrides != "")
   {
      if(note2 != "") note2 += " | ";
      note2 += "OVERRIDES: " + g_ui_overrides + ".";
   }

   note = note2;
   
   // Publish for diagnostics
   g_effectiveEmaStrategy = effEmaStrategy;
   g_effectiveMaType      = effMaType;
   g_effectiveBiasMode    = effBiasMode;
   g_effectiveSigNote     = note;
}

// --- [PASTE ValidateEffectiveSettings() FUNCTION HERE AS WELL] ---
bool ValidateEffectiveSettings()
{
   if(!Inp_BiasEnabled)
   {
      FlowLog("Bias disabled by input (Inp_BiasEnabled=false). Trading signals will be neutral.");
   }

   if((int)g_effectiveMaType < (int)METHOD_EMA || (int)g_effectiveMaType > (int)METHOD_SMA)
   {
      Print("ERROR: Effective MA method is out of range: ", (int)g_effectiveMaType);
      return false;
   }

   if((int)g_effectiveEmaStrategy < (int)EMA_STRAT_1_PRICE_CROSS || (int)g_effectiveEmaStrategy > (int)EMA_STRAT_CUSTOM)
   {
      Print("ERROR: Effective EMA strategy is out of range: ", (int)g_effectiveEmaStrategy);
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| END OF FILE                                                      |
//+------------------------------------------------------------------+