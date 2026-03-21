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

// ================================================================
// HELPER FUNCTIONS
// ================================================================

// Count active voting indicators
int GetActiveIndicatorCount(const ST_Settings &cfg)
{
   int count = 0;
   if(cfg.Ind_EmaSig_Enabled) count++;
   if(cfg.Ind_Adx_Enabled)    count++;
   if(cfg.Ind_Macd_Enabled)   count++;
   if(cfg.Ind_Rsi_Enabled)    count++;
   if(cfg.Ind_Cci_Enabled)    count++;
   if(cfg.Ind_Mfi_Enabled)    count++;
   if(cfg.Ind_Sto_Enabled)    count++;
   if(cfg.Ind_Bb_Enabled)     count++;
   if(cfg.Ind_Psar_Enabled)   count++;
   if(cfg.Ind_ATR_Enabled)    count++;
   if(cfg.Ind_P123_Enabled)   count++;
   if(cfg.Ind_Ross_Enabled)   count++;
   return count;
}

// Symbol type detection
enum ESymbolType
{
   SYMBOL_TYPE_FOREX,
   SYMBOL_TYPE_GOLD,
   SYMBOL_TYPE_CRYPTO,
   SYMBOL_TYPE_INDEX,
   SYMBOL_TYPE_UNKNOWN
};

ESymbolType DetectSymbolType()
{
   string symbol = StringToUpper(_Symbol);

   if(StringFind(symbol, "XAU") >= 0 || StringFind(symbol, "GOLD") >= 0)
      return SYMBOL_TYPE_GOLD;

   if(StringFind(symbol, "BTC") >= 0 || StringFind(symbol, "ETH") >= 0 ||
      StringFind(symbol, "CRYPTO") >= 0 || StringFind(symbol, "XRP") >= 0)
      return SYMBOL_TYPE_CRYPTO;

   if(StringFind(symbol, "US30") >= 0 || StringFind(symbol, "SPX") >= 0 ||
      StringFind(symbol, "NAS") >= 0 || StringFind(symbol, "DAX") >= 0)
      return SYMBOL_TYPE_INDEX;

   return SYMBOL_TYPE_FOREX;
}

string SymbolTypeToString(ESymbolType type)
{
   switch(type)
   {
      case SYMBOL_TYPE_FOREX:   return "FOREX";
      case SYMBOL_TYPE_GOLD:    return "GOLD";
      case SYMBOL_TYPE_CRYPTO:  return "CRYPTO";
      case SYMBOL_TYPE_INDEX:   return "INDEX";
      default:                  return "UNKNOWN";
   }
}

// Print active indicator list
void PrintActiveIndicators(const ST_Settings &cfg)
{
   Print("Active Indicators (", GetActiveIndicatorCount(cfg), " votes):");
   if(cfg.Ind_EmaSig_Enabled) Print("  ✓ EmaSig");
   if(cfg.Ind_Adx_Enabled)    Print("  ✓ ADX (P:", cfg.P_Adx, ", T:", cfg.T_Adx, ")");
   if(cfg.Ind_Macd_Enabled)   Print("  ✓ MACD (", cfg.P_MacdFast, "/", cfg.P_MacdSlow, "/", cfg.P_MacdSig, ") Mode:", EnumToString(cfg.MacdVoteMode));
   if(cfg.Ind_Rsi_Enabled)    Print("  ✓ RSI (P:", cfg.P_Rsi, ", OB:", cfg.T_RsiOB, ", OS:", cfg.T_RsiOS, ") Mode:", EnumToString(cfg.RsiMode));
   if(cfg.Ind_Cci_Enabled)    Print("  ✓ CCI (P:", cfg.P_Cci, ") Mode:", EnumToString(cfg.CciMode));
   if(cfg.Ind_Mfi_Enabled)    Print("  ✓ MFI (P:", cfg.P_Mfi, ", OB:", cfg.T_MfiOB, ", OS:", cfg.T_MfiOS, ")");
   if(cfg.Ind_Sto_Enabled)    Print("  ✓ Stochastic (K:", cfg.P_StoK, ", D:", cfg.P_StoD, ", Slow:", cfg.P_StoSlow, ") Mode:", EnumToString(cfg.StoMode));
   if(cfg.Ind_Bb_Enabled)     Print("  ✓ Bollinger Bands (P:", cfg.P_Bb, ", Dev:", cfg.P_BbDev, ") Mode:", EnumToString(cfg.BbMode));
   if(cfg.Ind_Psar_Enabled)   Print("  ✓ PSAR (Step:", cfg.P_PsarStep, ", Max:", cfg.P_PsarMax, ")");
   if(cfg.Ind_ATR_Enabled)    Print("  ✓ ATR (P:", cfg.P_Atr, ", Min:", cfg.MinATR, ", Max:", cfg.MaxATR, ")");
   if(cfg.Ind_P123_Enabled)   Print("  ✓ Pattern 1-2-3");
   if(cfg.Ind_Ross_Enabled)   Print("  ✓ Ross Hook");
}

// Print inactive indicator list
void PrintInactiveIndicators(const ST_Settings &cfg)
{
   int inactiveCount = 12 - GetActiveIndicatorCount(cfg);
   if(inactiveCount == 0)
   {
      Print("Inactive Indicators: None (all enabled)");
      return;
   }

   Print("Inactive Indicators (", inactiveCount, " available):");
   if(!cfg.Ind_EmaSig_Enabled) Print("  ○ EmaSig");
   if(!cfg.Ind_Adx_Enabled)    Print("  ○ ADX (P:", cfg.P_Adx, ", T:", cfg.T_Adx, ")");
   if(!cfg.Ind_Macd_Enabled)   Print("  ○ MACD (", cfg.P_MacdFast, "/", cfg.P_MacdSlow, "/", cfg.P_MacdSig, ")");
   if(!cfg.Ind_Rsi_Enabled)    Print("  ○ RSI (P:", cfg.P_Rsi, ")");
   if(!cfg.Ind_Cci_Enabled)    Print("  ○ CCI (P:", cfg.P_Cci, ")");
   if(!cfg.Ind_Mfi_Enabled)    Print("  ○ MFI (P:", cfg.P_Mfi, ")");
   if(!cfg.Ind_Sto_Enabled)    Print("  ○ Stochastic (K:", cfg.P_StoK, ", D:", cfg.P_StoD, ")");
   if(!cfg.Ind_Bb_Enabled)     Print("  ○ Bollinger Bands (P:", cfg.P_Bb, ", Dev:", cfg.P_BbDev, ")");
   if(!cfg.Ind_Psar_Enabled)   Print("  ○ PSAR (Step:", cfg.P_PsarStep, ", Max:", cfg.P_PsarMax, ")");
   if(!cfg.Ind_ATR_Enabled)    Print("  ○ ATR (P:", cfg.P_Atr, ")");
   if(!cfg.Ind_P123_Enabled)   Print("  ○ Pattern 1-2-3");
   if(!cfg.Ind_Ross_Enabled)   Print("  ○ Ross Hook");
}

// Print comprehensive preset configuration summary
void PrintPresetConfigSummary(const EStrategyPreset preset, const ST_Settings &cfg, bool showInactive = true)
{
   if(!cfg.PrintEffectiveConfig) return;

   Print("═══════════════════════════════════════════════════════════");
   Print("  ", PresetToString(preset), " Configuration Applied");
   if(StringLen(cfg.PresetVersion) > 0)
      Print("  Version: ", cfg.PresetVersion);
   Print("═══════════════════════════════════════════════════════════");

   // Symbol info
   ESymbolType symbolType = DetectSymbolType();
   Print("Symbol: ", _Symbol, " (", SymbolTypeToString(symbolType), ")");
   Print("Timeframe: ", EnumToString((ENUM_TIMEFRAMES)_Period));
   Print("");

   // Strategy settings
   Print("Strategy:");
   Print("  CloseOnReverse: ", cfg.CloseOnReverse ? "YES" : "NO");
   Print("  BiasMode: ", EnumToString(cfg.BiasMode));
   Print("  AutoStrat: ", EnumToString(cfg.AutoStrat));
   Print("  BiasFastID: ", cfg.BiasFastID, " (", EnumToString((EEmaRole)cfg.BiasFastID), ")");
   Print("  BiasSlowID: ", cfg.BiasSlowID, " (", EnumToString((EEmaRole)cfg.BiasSlowID), ")");
   Print("  EMAs: ", cfg.P_Ema1, "/", cfg.P_Ema2, "/", cfg.P_Ema3, "/", cfg.P_Ema4);
   Print("  MA Type: ", EnumToString(cfg.MaType));
   Print("");

   // Voting
   Print("Voting:");
   Print("  VoteMode: ", EnumToString(cfg.VoteMode));
   Print("  Vote_EvalShift: ", cfg.Vote_EvalShift);
   PrintActiveIndicators(cfg);
   if(showInactive)
   {
      Print("");
      PrintInactiveIndicators(cfg);
   }
   Print("");

   // Phase & Layer Detection
   Print("Phase & Layer Detection:");
   Print("  Phase Detection: ", cfg.PhaseDetectionEnabled ? "ON" : "OFF");
   Print("  Layer Detection: ", cfg.EnableLayerDetection ? "ON" : "OFF");
   Print("  Block UNORDERED: ", cfg.BlockUnorderedPhase ? "YES" : "NO");
   if(cfg.RequireMinPhaseConfirm)
      Print("  Min Confirm Bars: ", cfg.MinPhaseConfirmBars);
   if(cfg.EnableLayerDetection)
   {
      Print("  Layer Permissions:");
      Print("    TRENDING: L1=", cfg.Trending_AllowWeakTrades ? "Y" : "N",
            " L2=", cfg.Trending_AllowMediumTrades ? "Y" : "N",
            " L3=", cfg.Trending_AllowStrongTrades ? "Y" : "N");
      Print("    EMERGING: L1=", cfg.Emerging_AllowWeakTrades ? "Y" : "N",
            " L2=", cfg.Emerging_AllowMediumTrades ? "Y" : "N",
            " L3=", cfg.Emerging_AllowStrongTrades ? "Y" : "N");
   }
   Print("");

   // Gates
   Print("Entry Gates:");
   Print("  RequirePullback: ", cfg.RequirePullback ? "YES" : "NO");
   if(cfg.RequirePullback)
      Print("    Lookback: ", cfg.PullbackLookback, " bars");
   Print("  RequireRecoveryMomentum: ", cfg.RequireRecoveryMomentum ? "YES" : "NO");
   Print("  Gate_UseMultiLayer: ", cfg.Gate_UseMultiLayer ? "YES" : "NO");
   Print("");

   // Risk Management
   Print("Risk Management:");
   Print("  RiskPercent: ", cfg.RiskPercent, "%");
   Print("  MaxOpenTrades: ", cfg.MaxOpenTrades);
   Print("  MaxTotalRisk: ", cfg.MaxTotalRisk, "%");
   Print("  CountBEasZeroRisk: ", cfg.CountBEasZeroRisk ? "YES" : "NO");
   if(cfg.StopAfterConsecutiveLosses)
   {
      Print("  Consecutive Loss Protection: ON");
      Print("    Max Losses: ", cfg.MaxConsecutiveLosses);
      Print("    Cooldown: ", cfg.ConsecutiveLossCooldownHrs, " hrs");
   }
   Print("");

   // Exits
   Print("Exit Strategy:");
   Print("  ExitProfile: ", EnumToString(cfg.ExitProfile));
   Print("  SL Mode: ", EnumToString(cfg.SLMode));
   Print("  TP Mode: ", EnumToString(cfg.TPMode));
   if(cfg.TPMode == TP_MODE_RR)
      Print("  R:R Ratio: 1:", cfg.RRRatio);
   Print("  TP Enabled: ", cfg.TP_Enabled ? "YES" : "NO");
   Print("  TrailMode: ", EnumToString(cfg.TrailMode));
   if(cfg.Use_BE)
   {
      Print("  Breakeven: ON (Mode:", EnumToString(cfg.BE_Mode), ", Trig:", cfg.BE_Trig, ")");
   }
   Print("");

   // User Controls (Policy A)
   Print("User Controls (Policy A):");
   Print("  MaxSpread: ", cfg.MaxSpread, " pips");
   Print("  UseTime: ", cfg.UseTime ? "ON" : "OFF");
   if(cfg.UseTime)
      Print("    Hours: ", cfg.StartHr, ":00 - ", cfg.EndHr, ":00");
   Print("  UseNews: ", cfg.UseNews ? "ON" : "OFF");
   if(cfg.UseNews)
      Print("    Window: -", cfg.NewsPre, " min / +", cfg.NewsPost, " min");
   Print("");

   // Preset-Controlled (Not User-Controlled)
   Print("Preset-Controlled Settings:");
   Print("  MinATR: ", cfg.MinATR, " (", cfg.MinATR == 0.0 ? "no filter" : "filter active", ")");
   Print("  MaxATR: ", cfg.MaxATR, " (", cfg.MaxATR == 0.0 ? "no filter" : "filter active", ")");
   Print("  UseHTF: ", cfg.UseHTF ? "ON" : "OFF");
   if(cfg.UseHTF)
      Print("    HTF Period: ", EnumToString(cfg.HtfPeriod), ", EMA:", cfg.P_HtfEma);

   Print("═══════════════════════════════════════════════════════════");
}

// Validate preset configuration for logical consistency
void ValidatePresetConfig(const EStrategyPreset preset, const ST_Settings &cfg)
{
   Print("═══════════════════════════════════════════════════════════");
   Print("  Validating ", PresetToString(preset), " Configuration");
   Print("═══════════════════════════════════════════════════════════");

   bool hasErrors = false;
   bool hasWarnings = false;

   // Check 1: Indicator count (except PRESET_MA which has 0 by design)
   int activeIndicators = GetActiveIndicatorCount(cfg);
   if(preset != PRESET_MA && activeIndicators == 0)
   {
      Print("⚠️ WARNING: No indicators enabled! Strategy will only use bias.");
      hasWarnings = true;
   }
   else if(preset != PRESET_MA)
   {
      Print("✓ Indicators: ", activeIndicators, " active");
   }

   // Check 2: Phase detection + layer detection consistency
   if(cfg.EnableLayerDetection && !cfg.PhaseDetectionEnabled)
   {
      Print("❌ ERROR: Layer detection enabled but phase detection OFF!");
      Print("   Layer filtering requires phase detection to work properly.");
      hasErrors = true;
   }
   else if(cfg.EnableLayerDetection)
   {
      Print("✓ Phase & Layer Detection: Properly configured");
   }

   // Check 3: BiasMode + AutoStrat consistency
   if(cfg.BiasMode == BIAS_AUTO_PHASE && cfg.AutoStrat != STRAT_LAYER_DETECTION)
   {
      Print("⚠️ WARNING: BiasMode=BIAS_AUTO_PHASE but AutoStrat != STRAT_LAYER_DETECTION");
      Print("   Phase-based bias works best with layer detection strategy.");
      hasWarnings = true;
   }
   else if(cfg.BiasMode == BIAS_AUTO_PHASE)
   {
      Print("✓ BiasMode & AutoStrat: Aligned (Phase + Layer)");
   }

   // Check 4: Position sizing
   if(cfg.RiskPercent < 0.001 && !cfg.UseMACompatSizer)
   {
      Print("❌ ERROR: No position sizing configured!");
      Print("   Either RiskPercent > 0 OR UseMACompatSizer = true required.");
      hasErrors = true;
   }
   else
   {
      Print("✓ Position Sizing: Configured");
   }

   // Check 5: Risk limits sanity
   if(cfg.RiskPercent > 5.0)
   {
      Print("⚠️ WARNING: RiskPercent (", cfg.RiskPercent, "%) is very high! Recommended: <= 2%");
      hasWarnings = true;
   }
   if(cfg.MaxTotalRisk > 10.0)
   {
      Print("⚠️ WARNING: MaxTotalRisk (", cfg.MaxTotalRisk, "%) is very high! Recommended: <= 6%");
      hasWarnings = true;
   }

   // Check 6: Vote mode with no indicators
   if(cfg.VoteMode == VOTE_MODE_ALL && activeIndicators == 0 && preset != PRESET_MA)
   {
      Print("✓ VoteMode=ALL with 0 indicators (will trade on bias only)");
   }

   // Check 7: ATR voting vs ATR gate conflict
   if(cfg.Ind_ATR_Enabled && (cfg.MinATR > 0.0 || cfg.MaxATR > 0.0))
   {
      Print("⚠️ WARNING: ATR enabled as voting indicator AND as hard gate!");
      Print("   This creates double-filtering. Recommended: Use ATR for voting OR gating, not both.");
      hasWarnings = true;
   }

   // Check 8: Consecutive loss protection
   if(cfg.StopAfterConsecutiveLosses && cfg.MaxConsecutiveLosses == 0)
   {
      Print("❌ ERROR: Consecutive loss protection enabled but MaxConsecutiveLosses = 0!");
      hasErrors = true;
   }
   if(cfg.StopAfterConsecutiveLosses && cfg.ConsecutiveLossCooldownHrs <= 0)
   {
      Print("❌ ERROR: Consecutive loss protection enabled but ConsecutiveLossCooldownHrs <= 0!");
      hasErrors = true;
   }

   // Check 9: EMA periods ordering (for phase detection)
   if(cfg.BiasMode == BIAS_AUTO_PHASE)
   {
      if(!(cfg.P_Ema1 < cfg.P_Ema2 && cfg.P_Ema2 < cfg.P_Ema3 && cfg.P_Ema3 < cfg.P_Ema4))
      {
         Print("❌ ERROR: EMA periods not in ascending order for phase detection!");
         Print("   Current: ", cfg.P_Ema1, "/", cfg.P_Ema2, "/", cfg.P_Ema3, "/", cfg.P_Ema4);
         Print("   Required: P_Ema1 < P_Ema2 < P_Ema3 < P_Ema4");
         hasErrors = true;
      }
      else
      {
         Print("✓ EMA Periods: Properly ordered for phase detection");
      }
   }

   Print("═══════════════════════════════════════════════════════════");
   if(hasErrors)
   {
      Print("❌ Configuration validation FAILED. Critical errors found above.");
   }
   else if(hasWarnings)
   {
      Print("⚠️ Configuration validation passed with warnings. Review above.");
   }
   else
   {
      Print("✓ Configuration validation PASSED. No issues found.");
   }
   Print("═══════════════════════════════════════════════════════════");
}

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
         return "MA benchmark mode: replicates MT5 Moving Average EA; all voting disabled. User controls: Spread/Time/News/Risk.";
      case PRESET_RRM:
         return "RRM phase-based system (strategy fixed). User controls: Spread/Time/News/Risk/MaxTrades. Admin controls: ATR/HTF/Indicators.";
      case PRESET_TEST:
         return "Isolated testing mode (minimal config). User controls: Spread/Time/News/Risk. Admin enables ONE indicator to test.";
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
   // POLICY A: BACKUP UNIVERSAL OPERATIONAL FILTERS & RISK CONTROLS
   // User-controlled settings preserved across preset application.
   // NOTE: MinATR, MaxATR, UseHTF are preset-controlled (not backed up).
   // ================================================================
   const double op_MaxSpread       = cfg.MaxSpread;
   const double op_RiskPercent     = cfg.RiskPercent;
   const int    op_MaxOpenTrades   = cfg.MaxOpenTrades;
   const double op_MaxTotalRisk    = cfg.MaxTotalRisk;

   const bool   op_UseTime         = cfg.UseTime;
   const int    op_StartHr         = cfg.StartHr;
   const int    op_EndHr           = cfg.EndHr;

   const bool   op_UseNews         = cfg.UseNews;
   const int    op_NewsPre         = cfg.NewsPre;
   const int    op_NewsPost        = cfg.NewsPost;

   const bool   op_StopAfterConsecutiveLosses  = cfg.StopAfterConsecutiveLosses;
   const int    op_MaxConsecutiveLosses        = cfg.MaxConsecutiveLosses;
   const int    op_ConsecutiveLossCooldownHrs  = cfg.ConsecutiveLossCooldownHrs;

   if(preset == PRESET_MA)
   {
      // ═══════════════════════════════════════════════════════════
      // PRESET_MA (Moving Average Benchmark)
      // Simple MA cross system — all votes disabled, minimal config
      // ═══════════════════════════════════════════════════════════

      cfg.CloseOnReverse    = true;

      // Bias & AutoStrat
      cfg.BiasEnabled       = true;
      cfg.BiasMode          = BIAS_AUTO;
      cfg.AutoStrat         = STRAT_PRICE_CROSS;
      cfg.BiasFastID        = (int)ROLE_EMA1;
      cfg.BiasSlowID        = (int)ROLE_EMA1;

      cfg.RequirePriceCross = true;
      cfg.MABenchmarkStrict = true;
      cfg.UseMACompatSizer  = true;
      cfg.RiskPercent       = 0.0;

      // Voting
      cfg.VoteMode          = VOTE_MODE_ALL;

      // ALL votes disabled
      cfg.Ind_EmaSig_Enabled     = false;
      cfg.Ind_Adx_Enabled        = false;
      cfg.Ind_Macd_Enabled       = false;
      cfg.Ind_Rsi_Enabled        = false;
      cfg.Ind_Cci_Enabled        = false;
      cfg.Ind_Mfi_Enabled        = false;
      cfg.Ind_Sto_Enabled        = false;
      cfg.Ind_Bb_Enabled         = false;
      cfg.Ind_Psar_Enabled       = false;
      cfg.Ind_P123_Enabled       = false;
      cfg.Ind_Ross_Enabled       = false;
      cfg.Ind_ATR_Enabled        = false;

      // EMA periods (only EMA1 used)
      cfg.P_Ema1            = Inp_MA_Period;
      cfg.P_Ema2            = 13;
      cfg.P_Ema3            = 34;
      cfg.P_Ema4            = 89;

      // MACD periods (disabled but defined)
      cfg.P_MacdFast        = 12;
      cfg.P_MacdSlow        = 26;
      cfg.P_MacdSig         = 9;
      cfg.MacdVoteMode      = MACD_HISTOGRAM;
      cfg.MacdRequireSlope  = false;
      cfg.MacdRequireDivergence = false;
      cfg.MacdRequireHook   = false;
      cfg.MacdFreshBars     = 3;
      cfg.MacdSlopeMin      = 0.00001;

      // Other indicator periods (disabled but defined)
      cfg.P_Cci             = 14;
      cfg.P_PsarStep        = 0.02;
      cfg.P_PsarMax         = 0.2;
      cfg.P_Atr             = 14;
      // Commented untested indicators
      // cfg.P_Rsi          = 14;
      // cfg.T_RsiOB        = 70.0;
      // cfg.T_RsiOS        = 30.0;
      // cfg.P_Adx          = 14;
      // cfg.T_Adx          = 20;
      // cfg.P_Mfi          = 14;
      // cfg.T_MfiOB        = 80.0;
      // cfg.T_MfiOS        = 20.0;
      // cfg.P_StoK         = 5;
      // cfg.P_StoD         = 3;
      // cfg.P_StoSlow      = 3;
      // cfg.T_StoOB        = 80.0;
      // cfg.T_StoOS        = 20.0;
      // cfg.P_Bb           = 20;
      // cfg.P_BbDev        = 2.0;

      // Gates (all disabled)
      cfg.MaxSpread         = 9999.0;
      cfg.MinATR            = 0.0;
      cfg.MaxATR            = 0.0;
      cfg.ATR_HardGate      = false;
      cfg.Ind_ATR_Enabled   = false;
      cfg.UseTime           = false;
      cfg.UseNews           = false;
      cfg.UseHTF            = false;

      // Phase detection (disabled)
      cfg.PhaseDetectionEnabled      = false;
      cfg.EnableLayerDetection       = false;
      cfg.BlockUnorderedPhase        = false;
      cfg.RequireMinPhaseConfirm     = false;
      cfg.MinPhaseConfirmBars        = 0;

      // RRM gates (disabled)
      cfg.RequirePullback            = false;
      cfg.PullbackLookback           = 0;
      cfg.RequireRecoveryMomentum    = false;
      cfg.Gate_UseMultiLayer         = false;
      cfg.RRM_Lookback               = 0;
      cfg.RRM_MinDivPips             = 0.0;

      // Exits (all disabled)
      cfg.SL_Mult           = 0.0;
      cfg.SL_SwingPipsCushion   = 0.0;
      cfg.SL_PsarPipsCushion    = 0.0;
      cfg.TP_Mult           = 0.0;
      cfg.TP_Enabled        = false;
      cfg.Use_BE            = false;
      cfg.BE_Trig           = 0.0;
      cfg.BE_Buff           = 0.0;
      cfg.TrailMode         = TRAIL_NONE;
      cfg.Trail_Mult        = 0.0;
      cfg.PSAR_TrailCushionMode = PSAR_CUSHION_PIPS;
      cfg.PSAR_TrailPipsCushion = 0.0;

      // SL/TP strategy modes
      cfg.SLMode            = SL_MODE_FIXED_PIPS;
      cfg.TPMode            = TP_MODE_NONE;
      cfg.FixedTPPips       = 0.0;
      cfg.SLPercent         = 0.0;
      cfg.RRRatio           = 0.0;
      cfg.SwingLookback     = 0;

      // MA-specific settings
      cfg.MaType            = METHOD_SMA;
      cfg.ma_h_shift        = Inp_MA_Shift;
      cfg.ma_v_shift        = 1;

      // ================================================================
      // POLICY A: RESTORE UNIVERSAL OPERATIONAL FILTERS & RISK CONTROLS
      // ================================================================
      cfg.MaxSpread     = op_MaxSpread;
      cfg.RiskPercent   = op_RiskPercent;
      cfg.MaxOpenTrades = op_MaxOpenTrades;
      cfg.MaxTotalRisk  = op_MaxTotalRisk;
      cfg.UseTime       = op_UseTime;
      cfg.StartHr       = op_StartHr;
      cfg.EndHr         = op_EndHr;
      cfg.UseNews       = op_UseNews;
      cfg.NewsPre       = op_NewsPre;
      cfg.NewsPost      = op_NewsPost;
      cfg.StopAfterConsecutiveLosses = op_StopAfterConsecutiveLosses;
      cfg.MaxConsecutiveLosses       = op_MaxConsecutiveLosses;
      cfg.ConsecutiveLossCooldownHrs = op_ConsecutiveLossCooldownHrs;
      // NOTE: MinATR, MaxATR, UseHTF are preset-controlled (not restored)
   }

   if(preset == PRESET_RRM)
   {
      // RRM Phase-Based Layer Detection System
      cfg.PresetVersion  = "RRM_v1.1_2026-03-21";
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

      // Indicator periods (tested indicators — uncommented)
      cfg.P_Cci                  = 14;
      cfg.P_PsarStep             = 0.02;
      cfg.P_PsarMax              = 0.2;
      cfg.P_Atr                  = 14;  // Used for ATR vote when enabled

      // Untested indicators (commented out — periods defined)
      // cfg.P_Rsi          = 14;
      // cfg.T_RsiOB        = 70.0;
      // cfg.T_RsiOS        = 30.0;
      // cfg.P_Adx          = 14;
      // cfg.T_Adx          = 20;
      // cfg.P_Mfi          = 14;
      // cfg.T_MfiOB        = 80.0;
      // cfg.T_MfiOS        = 20.0;
      // cfg.P_StoK         = 5;
      // cfg.P_StoD         = 3;
      // cfg.P_StoSlow      = 3;
      // cfg.T_StoOB        = 80.0;
      // cfg.T_StoOS        = 20.0;
      // cfg.P_Bb           = 20;
      // cfg.P_BbDev        = 2.0;

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
      cfg.SL_Mult               = 0.0;
      cfg.SL_SwingPipsCushion   = GetRecommendedInitialSlCushionPips();
      cfg.SL_PsarPipsCushion    = GetRecommendedInitialSlCushionPips();
      cfg.TP_Mult               = 3.0;
      cfg.TP_Enabled            = true;
      cfg.TrailMode             = TRAIL_PSAR;
      cfg.PSAR_TrailCushionMode = PSAR_CUSHION_PIPS;
      cfg.PSAR_TrailPipsCushion = GetRecommendedTrailPsarCushionPips();
      cfg.Use_BE                = false;
      cfg.BE_Mode               = BE_MODE_R_MULTIPLE;  // Preferred BE mode when enabled; preserved for easy activation

      // SL/TP strategy (RRM: swing-based SL, R:R ratio TP)
      cfg.SLMode        = SL_MODE_SWING;
      cfg.TPMode        = TP_MODE_RR;
      cfg.FixedTPPips   = 40.0;
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

      // Symbol-type-aware MaxSpread (preset default; overridden by Policy A)
      ESymbolType symbolType = DetectSymbolType();
      switch(symbolType)
      {
         case SYMBOL_TYPE_FOREX:
            cfg.MaxSpread = (tf <= PERIOD_M5) ? 2.0 : 4.0;  // Tight forex spreads
            break;
         case SYMBOL_TYPE_GOLD:
            cfg.MaxSpread = 30.0;   // Gold has wider spreads
            break;
         case SYMBOL_TYPE_CRYPTO:
            cfg.MaxSpread = 50.0;   // Crypto has very wide spreads
            break;
         case SYMBOL_TYPE_INDEX:
            cfg.MaxSpread = 10.0;   // Indices have moderate spreads
            break;
         default:
            cfg.MaxSpread = 5.0;
            break;
      }

      // ================================================================
      // POLICY A: RESTORE UNIVERSAL OPERATIONAL FILTERS & RISK CONTROLS
      // NOTE: MinATR/MaxATR kept at 0 (ATR votes, not hard gates); UseHTF preset-controlled
      // ================================================================
      cfg.MaxSpread     = op_MaxSpread;
      cfg.RiskPercent   = op_RiskPercent;
      cfg.MaxOpenTrades = op_MaxOpenTrades;
      cfg.MaxTotalRisk  = op_MaxTotalRisk;
      cfg.UseTime       = op_UseTime;
      cfg.StartHr       = op_StartHr;
      cfg.EndHr         = op_EndHr;
      cfg.UseNews       = op_UseNews;
      cfg.NewsPre       = op_NewsPre;
      cfg.NewsPost      = op_NewsPost;
      cfg.StopAfterConsecutiveLosses = op_StopAfterConsecutiveLosses;
      cfg.MaxConsecutiveLosses       = op_MaxConsecutiveLosses;
      cfg.ConsecutiveLossCooldownHrs = op_ConsecutiveLossCooldownHrs;
      // NOTE: MinATR, MaxATR, UseHTF are preset-controlled (not restored)
      cfg.UseHTF    = false;
      cfg.HtfPeriod = (_Period == PERIOD_M1) ? PERIOD_M5 :
                      (_Period == PERIOD_M5) ? PERIOD_M15 :
                      (_Period <= PERIOD_M15) ? PERIOD_H1 : PERIOD_H4;
      cfg.P_HtfEma  = 89;
   }

   if(preset == PRESET_TEST)
   {
      // ═══════════════════════════════════════════════════════════
      // INDICATOR TESTING MODE
      // Minimal configuration for testing ONE indicator at a time.
      // All gates, layers, and indicators are disabled so that only
      // the bias and the single enabled indicator can reject a signal.
      // ═══════════════════════════════════════════════════════════

      Print("═══════════════════════════════════════════════════════════");
      Print("  PRESET: TEST (Isolated Testing Mode)");
      Print("═══════════════════════════════════════════════════════════");

      // Bias: Position + Slope (persistent bias for multi-indicator systems)
      cfg.BiasEnabled            = true;
      cfg.BiasMode               = BIAS_AUTO;
      cfg.AutoStrat              = STRAT_POSITION_SLOPE;
      cfg.BiasFastID             = (int)ROLE_EMA3;
      cfg.BiasSlowID             = (int)ROLE_EMA4;
      cfg.PhaseDetectionEnabled  = false;
      cfg.MinPhaseConfirmBars    = 0;
      cfg.BlockUnorderedPhase    = false;

      // EMA periods
      cfg.P_Ema1                 = 5;
      cfg.P_Ema2                 = 13;
      cfg.P_Ema3                 = 34;
      cfg.P_Ema4                 = 89;

      // ALL VOTES DISABLED (user enables ONE to test)
      cfg.Ind_EmaSig_Enabled     = false;
      cfg.Ind_Adx_Enabled        = false;
      cfg.Ind_Macd_Enabled       = false;
      cfg.Ind_Rsi_Enabled        = false;
      cfg.Ind_Cci_Enabled        = false;
      cfg.Ind_Mfi_Enabled        = false;
      cfg.Ind_Sto_Enabled        = false;
      cfg.Ind_Bb_Enabled         = false;
      cfg.Ind_Psar_Enabled       = false;
      cfg.Ind_P123_Enabled       = false;
      cfg.Ind_Ross_Enabled       = false;
      cfg.Ind_ATR_Enabled        = false;

      // Voting: ALL mode (with all indicators disabled, no vote filter applies)
      cfg.VoteMode               = VOTE_MODE_ALL;

      // Indicator periods (all defined — user can override via inputs)
      cfg.P_MacdFast             = 12;
      cfg.P_MacdSlow             = 26;
      cfg.P_MacdSig              = 9;
      cfg.MacdVoteMode           = MACD_HISTOGRAM;
      cfg.MacdRequireSlope       = false;
      cfg.MacdRequireDivergence  = false;
      cfg.MacdRequireHook        = false;
      cfg.MacdFreshBars          = 3;
      cfg.MacdSlopeMin           = 0.00001;

      cfg.P_Cci                  = 14;
      cfg.P_PsarStep             = 0.02;
      cfg.P_PsarMax              = 0.2;
      cfg.P_Atr                  = 14;
      cfg.P_Rsi                  = 14;
      cfg.T_RsiOB                = 70.0;
      cfg.T_RsiOS                = 30.0;
      cfg.P_Adx                  = 14;
      cfg.T_Adx                  = 20;
      cfg.P_Mfi                  = 14;
      cfg.T_MfiOB                = 80.0;
      cfg.T_MfiOS                = 20.0;
      cfg.P_StoK                 = 5;
      cfg.P_StoD                 = 3;
      cfg.P_StoSlow              = 3;
      cfg.T_StoOB                = 80.0;
      cfg.T_StoOS                = 20.0;
      cfg.P_Bb                   = 20;
      cfg.P_BbDev                = 2.0;

      // ALL GATES DISABLED (remove filtering noise)
      cfg.MaxSpread              = 100.0;
      cfg.MinATR                 = 0.0;
      cfg.MaxATR                 = 0.0;
      cfg.ATR_HardGate           = false;
      cfg.UseTime                = false;
      cfg.UseNews                = false;
      cfg.UseHTF                 = false;

      // Phase detection disabled
      cfg.PhaseDetectionEnabled      = false;
      cfg.EnableLayerDetection       = false;
      cfg.BlockUnorderedPhase        = false;
      cfg.RequireMinPhaseConfirm     = false;
      cfg.MinPhaseConfirmBars        = 0;

      // RRM gates disabled
      cfg.RequirePullback            = false;
      cfg.PullbackLookback           = 0;
      cfg.RequireRecoveryMomentum    = false;
      cfg.Gate_UseMultiLayer         = false;
      cfg.RRM_Lookback               = 0;
      cfg.RRM_MinDivPips             = 0.0;

      // Exits
      cfg.SL_Mult                = 0.0;
      cfg.SL_SwingPipsCushion    = 10.0;
      cfg.SL_PsarPipsCushion     = 5.0;
      cfg.TP_Mult                = 3.0;
      cfg.TP_Enabled             = true;
      cfg.Use_BE                 = false;
      cfg.BE_Mode                = BE_MODE_OFF;
      cfg.BE_Trig                = 0.0;
      cfg.BE_Buff                = 0.0;
      cfg.TrailMode              = TRAIL_NONE;
      cfg.Trail_Mult             = 0.0;
      cfg.PSAR_TrailCushionMode  = PSAR_CUSHION_PIPS;
      cfg.PSAR_TrailPipsCushion  = 0.0;

      // SL/TP strategy modes
      cfg.SLMode            = SL_MODE_SWING;
      cfg.TPMode            = TP_MODE_RR;
      cfg.FixedTPPips       = 40.0;
      cfg.SLPercent         = 0.5;
      cfg.RRRatio           = 3.0;
      cfg.SwingLookback     = 20;

      // ================================================================
      // POLICY A: RESTORE UNIVERSAL OPERATIONAL FILTERS & RISK CONTROLS
      // ================================================================
      cfg.MaxSpread     = op_MaxSpread;
      cfg.RiskPercent   = op_RiskPercent;
      cfg.MaxOpenTrades = op_MaxOpenTrades;
      cfg.MaxTotalRisk  = op_MaxTotalRisk;
      cfg.UseTime       = op_UseTime;
      cfg.StartHr       = op_StartHr;
      cfg.EndHr         = op_EndHr;
      cfg.UseNews       = op_UseNews;
      cfg.NewsPre       = op_NewsPre;
      cfg.NewsPost      = op_NewsPost;
      cfg.StopAfterConsecutiveLosses = op_StopAfterConsecutiveLosses;
      cfg.MaxConsecutiveLosses       = op_MaxConsecutiveLosses;
      cfg.ConsecutiveLossCooldownHrs = op_ConsecutiveLossCooldownHrs;
      // NOTE: MinATR, MaxATR, UseHTF are preset-controlled (not restored)
   }

   // ================================================================
   // POST-PRESET APPLICATION: DIAGNOSTICS & VALIDATION
   // ================================================================
   PrintPresetConfigSummary(preset, cfg, true);
   ValidatePresetConfig(preset, cfg);
}

//+------------------------------------------------------------------+
//| END OF FILE                                                      |
//+------------------------------------------------------------------+
