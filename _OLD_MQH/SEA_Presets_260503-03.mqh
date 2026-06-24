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

// TF-based swing lookback for FPM preset — prevents anchor landing on wrong side
// FIX: replaces hardcoded Inp_FPM_SwingLookback=5 which was too short (5 bars on H1 = 5 hours)
int GetFPMSwingLookback()
{
   switch(_Period) {
      case PERIOD_M1:  return 10;
      case PERIOD_M5:  return 12;
      case PERIOD_M15: return 15;
      case PERIOD_M30: return 18;
      case PERIOD_H1:  return 20;
      case PERIOD_H4:  return 30;
      case PERIOD_D1:  return 10;
      default:         return 20;
   }
}

// TF-based TP pips for FPM preset (midpoints of cheat sheet ranges)
double GetFPMFixedTpPips()
{
   ENUM_TIMEFRAMES tf = _Period;
   if      (tf <= PERIOD_M5)  return 11.0;   // M5:  7-15 pips → midpoint 11
   else if (tf <= PERIOD_M15) return 15.0;   // M15: 10-20 pips → midpoint 15
   else if (tf <= PERIOD_M30) return 40.0;   // M30: 30-50 pips → midpoint 40
   else                       return 50.0;   // H1+: cheat sheet specifies 50 pips for higher timeframes
}

string PresetToString(EStrategyPreset p)
{
   switch(p)
   {
      case PRESET_CUSTOM:       return "CUSTOM";
      case PRESET_FPM:          return "FPM";
      case PRESET_MA:           return "MA";
      case PRESET_RRM:          return "RRM";
      case PRESET_RRM_ORG:      return "RRM_ORG";
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
         return "PRESET_CUSTOM"; //: All inputs respected; you control strategy, indicators, and operator gates.";
      case PRESET_FPM:
         return "PRESET_FPM"; //: Five-Point Method locked (PSAR+MACD+BB_WIDENING+SMA10/20+BarClose); SL mode/TP mode/Trail user-controlled via Zone 3C.";
      case PRESET_MA:
         return "PRESET_MA"; //: benchmark mode: replicates MT5 Moving Average EA; all voting disabled.";
      case PRESET_RRM:
         return "PRESET_RRM"; //: phase-based system fixed (AutoStrat, EMA/MACD config, vote threshold); only Policy A gates and exits user-controlled.";
      case PRESET_RRM_ORG:
         return "PRESET_RRM_ORG"; //: Original Russ Horn RRM with DPI momentum voter locked (TSI R/S/U inline); phase/layer/recovery/PSAR/CandleBody fixed; exits user-controlled.";
      case PRESET_TEST:
         return "PRESET_TEST"; //: Minimal testing mode: bypass voting (threshold=1), fixed SL/TP, no trailing.";
      default:
         return "PRESET_ACTIVE"; //: Preset active; strategy-critical settings fixed by preset.";
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
   Print("    SmaConv: ", (cfg.Ind_SmaConverge_Enabled ? "✓" : "✗"));
   Print("    DPI:     ", (cfg.Ind_Dpi_Enabled ? "✓" : "✗"),
         (cfg.Ind_Dpi_Enabled ? StringFormat(" (TSI R=%d S=%d U=%d FastR=%d FastS=%d MACD=%d/%d/%d)",
          cfg.DPI_TSI_R, cfg.DPI_TSI_S, cfg.DPI_TSI_U, cfg.DPI_TSI_FastR, cfg.DPI_TSI_FastS,
          cfg.DPI_MACD_Fast, cfg.DPI_MACD_Slow, cfg.DPI_MACD_Signal) : ""));
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
   //   - Risk:       Personal risk tolerance (RiskPercent, MaxOpenTrades, MaxTotalRisk, margin thresholds)
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
   
   const double op_RiskPercent   = cfg.RiskPercent;      // Policy A: user risk tolerance
   const int    op_MaxOpenTrades = cfg.MaxOpenTrades;    // Policy A: user position limit   
   const double op_MaxTotalRisk  = cfg.MaxTotalRisk;     // Policy A: user portfolio risk cap   
   const double op_MinMarginLevel = cfg.MinMarginLevel;  // Policy A: user margin safety thresholds
   
   const double op_EmergencyMarginLevel = cfg.EmergencyMarginLevel;  // Saved for PRESET_TEST exit-profile logic
   const EExitProfile op_ExitProfile = cfg.ExitProfile;

   
   if(preset == PRESET_FPM)
   {
      // ================================================================
      // PRESET_FPM: Five-Point Method (FPM)
      // ================================================================
      //
      // ENTRY FORMULA (3 indicator votes + bar-close gate must all align):
      //   1. PSAR crossed below/above price (dot position + optional flip)
      //   2. MACD crossed above/below signal line (MACD_CROSSOVER_N: fresh cross, ≤5 bars)
      //   3. Bollinger Bands widening (BB_WIDENING mode: bandwidth expanding bar-to-bar)
      //   + Bar-close gate: candle closed above/below 10+20 SMA (BarClose_Mode=BC_BIAS_FAST)
      //      (SmaConverge removed: contradicts trending Bias; BC_BIAS_FAST covers this role)
      //
      // LOCKED (never user-changeable in FPM):
      //   MaType    = SMA               (10 + 20 period SMAs)
      //   P_Ema1    = 10, P_Ema2 = 20   (10 SMA, 20 SMA)
      //   BiasMode  = BIAS_2EMA          (two-SMA structure)
      //   AutoStrat = STRAT_2EMA_POSITION (price position vs both SMAs)
      //   Ind_Psar  ON, Ind_Macd ON, Ind_Bb ON  (3 voting indicators; unanimous via VOTE_MODE_ALL)
      //   BarClose  = BC_BIAS_FAST       (close vs fast SMA=10)
      //   VoteMode  = VOTE_MODE_ALL      (all 3 voting indicators must agree unanimously)
      //   Phase/Layer detection OFF      (simple 2-SMA system)
      //
      // NOTE - Condition 4 (SmaConverge removed):
      //   SmaConverge (gap narrowing) was mutually exclusive with the trending Bias:
      //   when STRAT_2EMA_POSITION Bias fires (both SMAs moving apart), SmaConverge
      //   fails, and vice versa.  The BC_BIAS_FAST bar-close gate already satisfies
      //   "price is positioned relative to the SMAs." Ind_SmaConverge_Enabled = false.
      //
      // NOTE - Condition 3 (BB widening):
      //   BB_WIDENING compares bandwidth (upper - lower) at shift vs shift+1.
      //   Pass when bandwidth_now > bandwidth_prev (bands actively expanding).
      //   Bias-direction is not relevant — widening is symmetric.
      //
      // NOTE - SL/TP user control (Zone 3C):
      //   SL mode: SWING (swing high/low) or FIXED_PIPS — via Inp_FPM_SLMode
      //   TP mode: FIXED_PIPS (TF-based cheat sheet pips) or RR (user ratio) — via Inp_FPM_TPMode
      //
      // FLEXIBLE (via Inp_FPM_* inputs):
      //   SL mode, swing lookback, fixed SL pips, TP mode, R:R ratio,
      //   PSAR step/max, MACD periods, trailing toggle, trail distance
      //
      // ================================================================

      // ── SIGNAL ARCHITECTURE: locked ──────────────────────────────────
      cfg.BiasMode               = BIAS_2EMA;
      cfg.AutoStrat              = STRAT_2EMA_POSITION;    // Price must be above/below both SMA10 and SMA20
      cfg.BiasFastID             = (int)ROLE_EMA1;         // SMA10: fast
      cfg.BiasSlowID             = (int)ROLE_EMA2;         // SMA20: slow
      cfg.MaType                 = METHOD_SMA;             // SMA (not EMA)
      cfg.CloseOnReverse         = false;
      cfg.BiasEnabled            = true;
      cfg.RequirePriceCross      = false;
      cfg.MABenchmarkStrict      = false;
      cfg.UseMACompatSizer       = false;
      cfg.VoteMode               = VOTE_MODE_ALL;

      // ── SMA PERIODS: locked (10 + 20 per cheat sheet) ────────────────
      cfg.P_Ema1                 = 10;    // SMA10
      cfg.P_Ema2                 = 20;    // SMA20
      cfg.P_Ema3                 = 34;    // Unused but must be ascending
      cfg.P_Ema4                 = 89;    // Unused but must be ascending

      // ── INDICATOR TOGGLES: locked ─────────────────────────────────────
      cfg.Ind_Psar_Enabled       = true;   // Condition 1: PSAR position
      cfg.Ind_Macd_Enabled       = true;   // Condition 2: MACD vs signal
      cfg.Ind_Bb_Enabled         = true;   // Condition 3: BB widening
      // All other indicators OFF (not part of FPM methodology):
      cfg.Ind_Adx_Enabled        = false;
      cfg.Ind_Atr_Enabled        = false;
      cfg.Ind_CandleBody_Enabled = false;
      cfg.Ind_CI_Enabled         = false;
      cfg.Ind_VRC_Enabled        = false;
      cfg.Ind_Cci_Enabled        = false;
      cfg.Ind_Mfi_Enabled        = false;
      cfg.Ind_P123_Enabled       = false;
      cfg.Ind_Ross_Enabled       = false;
      cfg.Ind_Rsi_Enabled        = false;
      cfg.Ind_Sto_Enabled        = false;
      cfg.Ind_SmaConverge_Enabled = false;  // Removed: contradicts trending Bias; BC_BIAS_FAST covers Condition 4
      cfg.Ind_SmaConverge_Weight  = 1;
      cfg.Ind_Dpi_Enabled        = false;   // DPI not used in FPM methodology
      cfg.Ind_Dpi_Weight         = 1;

      // ── PSAR SETTINGS ─────────────────────────────────────────────────
      // Condition 1: PSAR crossed below price (for buy) = PSAR dot below price
      cfg.P_PsarStep             = Inp_FPM_PsarStep;
      cfg.P_PsarMax              = Inp_FPM_PsarMax;
      cfg.Vote_AllowPsarFlip     = true;   // Allow flip detection
      cfg.Vote_PsarFlipDelay     = -1;     // -1 = no time expiry: PSAR dot position evaluated on every bar

      // ── MACD SETTINGS ─────────────────────────────────────────────────
      // Condition 2: MACD crossed above signal line = fresh crossover (within N bars)
      cfg.P_MacdFast             = Inp_FPM_MacdFast;
      cfg.P_MacdSlow             = Inp_FPM_MacdSlow;
      cfg.P_MacdSig              = Inp_FPM_MacdSig;
      cfg.MacdVoteMode           = MACD_CROSSOVER_N;  // Fresh cross only (within N bars)
      cfg.MacdRequireSlope       = false;
      cfg.MacdRequireDivergence  = false;
      cfg.MacdRequireHook        = false;
      cfg.MacdFreshBars          = 5;                  // Valid for 5 bars after cross (25 min on M5; allows Bias to confirm)
      cfg.MacdSlopeMin           = 0.00001;

      // ── BOLLINGER BANDS SETTINGS ──────────────────────────────────────
      // Condition 3: Bollinger Bands widening (BB_WIDENING)
      //   Compares bandwidth (upper - lower) at shift vs shift+1.
      //   Passes when bandwidth_now > bandwidth_prev (bands actively expanding).
      cfg.P_Bb                   = 20;
      cfg.P_BbDev                = 2.0;
      cfg.BbMode                 = BB_WIDENING;  // Cheat sheet: "Bollinger Bands are widening"

      // ── BAR CLOSE (bcX): Condition 5 ──────────────────────────────────
      // Candle closed above 10 SMA (fast SMA) → above both SMAs in bullish bias
      cfg.BarClose_Enabled       = true;
      cfg.BarClose_Mode          = BC_BIAS_FAST;   // Close vs SMA10 (fast)
      cfg.BarClose_DefaultEMA    = ROLE_EMA1;

      // ── PHASE DETECTION & LAYER FILTERING: disabled ───────────────────
      cfg.PhaseDetectionEnabled     = false;
      cfg.EnableLayerDetection      = false;
      cfg.BlockUnorderedPhase       = false;
      cfg.BlockEmergingPhase        = false;
      cfg.RequireMinPhaseConfirm    = false;
      cfg.MinPhaseConfirmBars       = 0;

      // Layer permissions (all irrelevant when detection is off, set safe defaults)
      cfg.Trending_AllowWeakTrades   = true;
      cfg.Emerging_AllowWeakTrades   = true;
      cfg.Trending_AllowMediumTrades = true;
      cfg.Emerging_AllowMediumTrades = true;
      cfg.Trending_AllowStrongTrades = true;
      cfg.Emerging_AllowStrongTrades = true;

      // ── PULLBACK DETECTION GATES: disabled ────────────────────────────
      cfg.RequireRecoveryMomentum   = false;
      cfg.Gate_Recovery.mode        = GATE_SCALE_FIXED;
      cfg.Gate_Recovery.value       = 0.0;
      cfg.RRM_Lookback              = 0;
      cfg.Gate_EmaDiv.mode          = GATE_SCALE_FIXED;
      cfg.Gate_EmaDiv.value         = 0.0;
      cfg.RRM_MinDivPips            = 0.0;
      cfg.Gate_CandleDirection.mode  = GATE_SCALE_FIXED;
      cfg.Gate_CandleDirection.value = 0.0;

      // ── VOTE EVALUATION ───────────────────────────────────────────────
      cfg.Vote_EvalShift            = 1;

      // ── OTHER INDICATOR PERIODS (unused but set safe defaults) ─────────
      cfg.P_Adx                     = 14;
      cfg.T_Adx                     = 20.0;
      cfg.ADX_Mode                  = ADX_MODE_STATIC;
      cfg.ADX_Percentile            = 50.0;
      cfg.ADX_Lookback              = 100;
      cfg.ADX_Threshold_Accumulation = 12.0;
      cfg.ADX_Threshold_Trending     = 25.0;
      cfg.ADX_Threshold_Distribution = 18.0;
      cfg.P_Atr                     = 14;
      cfg.ATR_VoteMinPips           = 5.0;
      cfg.ATR_VoteMaxPips           = 50.0;
      cfg.CandleBody_AvgPeriod      = 10;
      cfg.CandleBody_MaxMult        = 3.0;
      cfg.CandleBody_CheckBars      = 1;
      cfg.CandleBody_RequireDirection = true;
      cfg.Ind_CandleBody_Weight     = 1;
      cfg.CI_Period                 = 14;
      cfg.CI_RangingThreshold       = 61.8;
      cfg.Ind_CI_Weight             = 1;
      cfg.VRC_ATR_Period            = 14;
      cfg.VRC_Lookback              = 100;
      cfg.VRC_LowThreshold          = 33.0;
      cfg.Ind_VRC_Weight            = 1;
      cfg.P_Cci                     = 14;
      cfg.CciMode                   = CCI_TREND_ZERO;
      cfg.P_Mfi                     = 14;
      cfg.T_MfiOB                   = 80.0;
      cfg.T_MfiOS                   = 20.0;
      cfg.MfiMode                   = MFI_ZONE_FILTER;
      cfg.P_Rsi                     = 14;
      cfg.T_RsiOB                   = 70.0;
      cfg.T_RsiOS                   = 30.0;
      cfg.RsiMode                   = RSI_TREND_ABOVE_50;
      cfg.P_StoK                    = 5;
      cfg.P_StoD                    = 3;
      cfg.P_StoSlow                 = 3;
      cfg.T_StoOB                   = 80.0;
      cfg.T_StoOS                   = 20.0;
      cfg.StoMode                   = STO_CROSS_SIGNAL;
      cfg.FractalPeriod             = 5;
      cfg.TPFractalOffset           = 1;

      // ── RISK MANAGEMENT ───────────────────────────────────────────────
      cfg.CountBEasZeroRisk         = true;
      cfg.FixedLotSize              = 0.0;

      // ── EXIT STRATEGY ─────────────────────────────────────────────────
      cfg.ExitProfile               = EXIT_PROFILE_SIMPLE;

      // SL: Hardcode SL_MODE_SWING — swing is the FPM methodology; Inp_FPM_SLMode is kept for PRESET_CUSTOM only
      // FIX: was cfg.SLMode = Inp_FPM_SLMode — user could accidentally switch to non-swing mode
      cfg.SLMode                    = SL_MODE_SWING;
      // FIX: was Inp_FPM_SwingLookback (default 5) — too short; use TF-aware helper instead
      cfg.SwingLookback             = GetFPMSwingLookback();
      cfg.SL_SwingPipsCushion       = GetRecommendedInitialSlCushionPips();
      cfg.SL_PsarPipsCushion        = GetRecommendedInitialSlCushionPips();
      cfg.SL_FixedPips              = Inp_FPM_SLFixedPips;

      // TP: User-selected mode
      //   TP_MODE_FIXED_PIPS → TF-based cheat sheet midpoints via GetFPMFixedTpPips()
      //   TP_MODE_RR         → user R:R ratio (Inp_FPM_RRRatio, any double e.g. 1.5, 2.0, 3.0)
      cfg.TPMode                    = Inp_FPM_TPMode;
      cfg.TP_Enabled                = true;
      cfg.FixedTPPips               = (Inp_FPM_TPMode == TP_MODE_FIXED_PIPS) ? GetFPMFixedTpPips() : 0.0;
      // FIX: was 0.0 when TP_MODE_FIXED_PIPS — ExecuteTrade TP chain skipped all branches → tp=0
      // Always set a non-zero RRRatio so the RRRatio>0 branch in ExecuteTrade fires as fallback
      cfg.RRRatio                   = (Inp_FPM_TPMode == TP_MODE_RR)         ? Inp_FPM_RRRatio      : 2.0;
      cfg.SLPercent                 = 0.0;

      // BE: Move to breakeven after 10 pips profit
      cfg.BE_Mode                   = BE_MODE_R_MULTIPLE;
      cfg.RRM_BE_RMultiple          = 1.0;                         // BE at 1R profit (triggers when profit ≥ 1× initial SL distance)
      cfg.RRM_BE_BufferPips         = GetTFBasedCushion(_Period);  // TF-adaptive buffer (e.g., M5=3p, M15=5p, H1=8p)
      cfg.BEThresholdPips           = 0.0;                         // Not used in R_MULTIPLE mode
      cfg.TrailTrigger              = TRIGGER_BREAKEVEN;

      // Trail: Optional 15-pip trailing stop (cheat sheet: "15 points or minimum broker-allowed distance")
      // If 15 pips is below the broker's minimum trail distance, the platform will
      // clamp it to the minimum. Set Inp_FPM_UseTrailing=false to disable entirely.
      cfg.TrailMode                 = Inp_FPM_UseTrailing ? TRAIL_FIXED_PIPS : TRAIL_NONE;
      cfg.TrailDistancePips         = Inp_FPM_TrailDistancePips;
      cfg.TrailLockProfit           = true;
      cfg.TrailStepPips             = 5.0;
      cfg.TrailProfitPercent        = 0.0;

      cfg.PSAR_TrailCushionMode     = PSAR_CUSHION_PIPS;
      cfg.PSAR_TrailPipsCushion     = 0.0;

      // ── SLOPE CALCULATION ─────────────────────────────────────────────
      cfg.SlopeLookbackBars         = 3;  // Smoother slope on M5; SMA20 needs multiple bars to show direction

      // ── MA BENCHMARK SPECIFIC: off ────────────────────────────────────
      cfg.ma_h_shift                = 1;
      cfg.ma_v_shift                = 1;

      // ── DRAWDOWN PROTECTION: off (not part of FPM methodology) ────────
      cfg.RRM_EnableDrawdownProtection = false;
      cfg.RRM_MaxConsecutiveLosses  = 0;
      cfg.RRM_MaxTradesPerDay       = 0;
      cfg.RRM_MaxDailyDrawdownPct   = 0.0;

      // ── POLICY A: RESTORE OPERATOR-CONTROLLED GATES ───────────────────
      cfg.UseSpread                 = op_UseSpread;
      cfg.MaxSpread                 = op_MaxSpread;
      cfg.UseTime                   = op_UseTime;
      cfg.StartHr                   = op_StartHr;
      cfg.EndHr                     = op_EndHr;
      cfg.UseNews                   = op_UseNews;
      cfg.NewsPre                   = op_NewsPre;
      cfg.NewsPost                  = op_NewsPost;
      cfg.RiskPercent               = op_RiskPercent;
      cfg.MaxOpenTrades             = op_MaxOpenTrades;
      cfg.MaxTotalRisk              = op_MaxTotalRisk;
      cfg.MinMarginLevel            = op_MinMarginLevel;
      cfg.EmergencyMarginLevel      = op_EmergencyMarginLevel;

      return;
   }
   
   
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
      cfg.Ind_SmaConverge_Enabled = false;
      cfg.Ind_SmaConverge_Weight  = 1;
      cfg.Ind_Dpi_Enabled        = false;
      cfg.Ind_Dpi_Weight         = 1;
   
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
      cfg.CandleBody_RequireDirection = true;
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
      cfg.BlockEmergingPhase        = false;
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
      cfg.MinMarginLevel = op_MinMarginLevel; // Policy A: restore entry margin guard
      cfg.EmergencyMarginLevel = op_EmergencyMarginLevel; // Policy A: restore emergency margin guard

      return;
   }

   if(preset == PRESET_RRM)
   {
      // ================================================================
      // PRESET_RRM: RRM Methodology — Phase-Based Trend Pullback
      // ================================================================
      //
      // SIGNAL FORMULA (locked, no branches):
      //   TS = Phase(4EMA) × Layer(EMA-pair) × BarClose × Indicators × Gates
      //
      // LOCKED (never user-changeable):
      //   BiasMode    = BIAS_4EMA          (4-EMA phase: TRENDING/EMERGING/UNORDERED)
      //   AutoStrat   = STRAT_4EMA_LAYER   (layer-based pullback entry)
      //   VoteMode    = VOTE_MODE_ALL       (all enabled indicators must agree)
      //   Phase/Layer detection ON, UNORDERED blocked
      //
      // FLEXIBLE (via dedicated Inp_RRM_* inputs):
      //   EMA periods, indicator toggles, indicator parameters, SL/TP/Trail modes
      //
      // ================================================================

      // ── SIGNAL ARCHITECTURE: locked ──────────────────────────────────
      cfg.BiasMode               = BIAS_4EMA;
      cfg.AutoStrat              = STRAT_4EMA_LAYER;
      cfg.BiasFastID             = (int)ROLE_EMA3;    // EMA34: phase direction fast
      cfg.BiasSlowID             = (int)ROLE_EMA4;    // EMA89: phase direction slow
      cfg.MaType                 = METHOD_EMA;
      cfg.CloseOnReverse         = false;
      cfg.BiasEnabled            = true;              // true
      cfg.RequirePriceCross      = false;
      cfg.MABenchmarkStrict      = false;
      cfg.UseMACompatSizer       = false;
      cfg.VoteMode               = VOTE_MODE_ALL;

      // ── EMA PERIODS: flexible via Inp_RRM_* ──────────────────────────
      cfg.P_Ema1                 = Inp_RRM_Ema1Period;   // default 5
      cfg.P_Ema2                 = Inp_RRM_Ema2Period;   // default 13
      cfg.P_Ema3                 = Inp_RRM_Ema3Period;   // default 34
      cfg.P_Ema4                 = Inp_RRM_Ema4Period;   // default 89

      // ── SPREAD: derived from pair type (Zone 3C), no mode branching ──
      cfg.MaxSpread = op_MaxSpread;  // Policy A: user spread gate

      // ── INDICATOR TOGGLES: flexible via Inp_RRM_* ────────────────────
      cfg.Ind_Macd_Enabled       = Inp_RRM_Use_Macd;
      cfg.Ind_Psar_Enabled       = Inp_RRM_Use_Psar;
      cfg.Ind_CandleBody_Enabled = Inp_RRM_Use_CandleBody;
      cfg.Ind_Cci_Enabled        = Inp_RRM_Use_Cci;
      cfg.Ind_Rsi_Enabled        = Inp_RRM_Use_Rsi;
      cfg.Ind_Adx_Enabled        = Inp_RRM_Use_Adx;
      cfg.Ind_Sto_Enabled        = Inp_RRM_Use_Stoch;
      cfg.Ind_Bb_Enabled         = Inp_RRM_Use_Bb;
      cfg.Ind_Mfi_Enabled        = Inp_RRM_Use_Mfi;
      // Always off in RRM (not part of RRM methodology):
      cfg.Ind_Atr_Enabled        = false;
      cfg.Ind_CI_Enabled         = false;
      cfg.Ind_VRC_Enabled        = false;
      cfg.Ind_P123_Enabled       = false;
      cfg.Ind_Ross_Enabled       = false;
      cfg.Ind_SmaConverge_Enabled = false;
      cfg.Ind_SmaConverge_Weight  = 1;
      cfg.Ind_Dpi_Enabled        = false;
      cfg.Ind_Dpi_Weight         = 1;

      // ── MACD SETTINGS: flexible via Inp_RRM_* ────────────────────────
      cfg.P_MacdFast             = Inp_RRM_MacdFast;
      cfg.P_MacdSlow             = Inp_RRM_MacdSlow;
      cfg.P_MacdSig              = Inp_RRM_MacdSig;
      cfg.MacdVoteMode           = Inp_RRM_MacdMode;
      cfg.MacdRequireSlope       = Inp_RRM_MacdSlope;
      cfg.MacdRequireDivergence  = Inp_RRM_MacdDiv;
      cfg.MacdRequireHook        = false;
      cfg.MacdFreshBars          = 3;
      cfg.MacdSlopeMin           = 0.00001;

      // ── PSAR SETTINGS: flexible via Inp_RRM_* ────────────────────────
      cfg.P_PsarStep             = Inp_RRM_PsarStep;
      cfg.P_PsarMax              = Inp_RRM_PsarMax;
      cfg.Vote_AllowPsarFlip     = true;              // true
      cfg.Vote_PsarFlipDelay     = -1;

      // ── CCI SETTINGS: flexible via Inp_RRM_* ─────────────────────────
      cfg.P_Cci                  = Inp_RRM_CciPeriod;
      cfg.CciMode                = Inp_RRM_CciMode;

      // ── RSI SETTINGS: flexible via Inp_RRM_* ─────────────────────────
      cfg.P_Rsi                  = Inp_RRM_RsiPeriod;
      cfg.RsiMode                = Inp_RRM_RsiMode;
      cfg.T_RsiOB                = 70.0;
      cfg.T_RsiOS                = 30.0;

      // ── ADX SETTINGS: flexible via Inp_RRM_* ─────────────────────────
      cfg.ADX_Mode               = ADX_MODE_PHASE_AWARE;
      cfg.P_Adx                  = Inp_RRM_AdxPeriod;
      cfg.T_Adx                  = Inp_RRM_AdxThreshold;
      cfg.ADX_Percentile         = 50.0;
      cfg.ADX_Lookback           = 100;
      cfg.ADX_Threshold_Accumulation  = 12.0;
      cfg.ADX_Threshold_Trending      = 25.0;
      cfg.ADX_Threshold_Distribution  = 18.0;

      // ── STOCH SETTINGS: fixed reasonable defaults ─────────────────────
      cfg.StoMode                = STO_CROSS_SIGNAL;
      cfg.P_StoK                 = 5;
      cfg.P_StoD                 = 3;
      cfg.P_StoSlow              = 3;
      cfg.T_StoOB                = 80.0;
      cfg.T_StoOS                = 20.0;

      // ── BB SETTINGS: fixed reasonable defaults ────────────────────────
      cfg.BbMode                 = BB_TREND_FOLLOW;
      cfg.P_Bb                   = 20;
      cfg.P_BbDev                = 2.0;

      // ── MFI SETTINGS: fixed reasonable defaults ───────────────────────
      cfg.MfiMode                = MFI_ZONE_FILTER;
      cfg.P_Mfi                  = 14;
      cfg.T_MfiOB                = 80.0;
      cfg.T_MfiOS                = 20.0;

      // ── CANDLE BODY SETTINGS ──────────────────────────────────────────
      cfg.CandleBody_AvgPeriod   = 15;
      cfg.CandleBody_MaxMult     = 3.5;
      cfg.CandleBody_CheckBars   = (_Period <= PERIOD_M5) ? 1 : 2;
      cfg.CandleBody_RequireDirection = true;
      cfg.Ind_CandleBody_Weight  = 1;

      // ── BAR CLOSE (bcX) CONFIGURATION ────────────────────────────────
      cfg.BarClose_Mode          = BC_LAYER_AWARE;
      cfg.BarClose_DefaultEMA    = ROLE_EMA1;
      cfg.BarClose_Enabled       = true;              // true

      // ── PHASE DETECTION & LAYER FILTERING: locked ────────────────────
      cfg.PhaseDetectionEnabled     = true;           // true
      cfg.EnableLayerDetection      = true;           // true
      cfg.BlockUnorderedPhase       = true;           // true
      cfg.BlockEmergingPhase        = true;           // true: EM phase = no trades; TM phase = trades allowed
      cfg.RequireRecoveryMomentum = (_Period <= PERIOD_M5) ? true : false; 
      cfg.MinPhaseConfirmBars     = (_Period <= PERIOD_M5) ? 0 : 1;        // M1: No delay needed on M1

      // Layer permissions per phase (per RRM methodology PNGs):
      //   TRENDING:  Weak + Medium + Strong trades allowed (user-controllable via Inp_RRM_Allow*)
      //   EMERGING:  Weak + Medium allowed; Strong always blocked per RRM methodology
      //   UNORDERED: all blocked (BlockUnorderedPhase = true)
      cfg.Trending_AllowWeakTrades   = Inp_RRM_AllowWeak;
      cfg.Emerging_AllowWeakTrades   = Inp_RRM_AllowWeak;
      cfg.Trending_AllowMediumTrades = Inp_RRM_AllowMedium;
      cfg.Emerging_AllowMediumTrades = Inp_RRM_AllowMedium;
      cfg.Trending_AllowStrongTrades = Inp_RRM_AllowStrong;
      cfg.Emerging_AllowStrongTrades = false;  // STRONG always blocked in EMERGING per RRM methodology

      // ── PULLBACK DETECTION GATES ──────────────────────────────────────
      cfg.RequireRecoveryMomentum   = false;   // Wick-touch recovery valid on M1/M5

      cfg.Gate_Recovery.mode        = GATE_SCALE_AUTO_TF;
      cfg.Gate_Recovery.value       = 1.0;
      cfg.RRM_Lookback              = (_Period <= PERIOD_M1) ? 15 : (_Period <= PERIOD_M5) ? 10 : 12;

      cfg.Gate_EmaDiv.mode          = GATE_SCALE_AUTO_TF;
      cfg.Gate_EmaDiv.value         = 1.0;
      cfg.RRM_MinDivPips            = 1.5;

      cfg.Gate_CandleDirection.mode  = GATE_SCALE_FIXED;
      cfg.Gate_CandleDirection.value = 1.0;

      // ── VOTE EVALUATION ───────────────────────────────────────────────
      cfg.Vote_EvalShift            = 1;

      // ── RISK MANAGEMENT ───────────────────────────────────────────────
      cfg.CountBEasZeroRisk         = true;              // true
      cfg.FixedLotSize              = 0.0;

      // ── EXIT STRATEGY: flexible via Inp_RRM_* ────────────────────────
      cfg.ExitProfile               = EXIT_PROFILE_RRM;
      cfg.SLMode                    = Inp_RRM_SLMode;
      cfg.TPMode                    = Inp_RRM_TPMode;
      cfg.TP_Enabled                = (Inp_RRM_TPMode != TP_MODE_NONE);
      cfg.RRRatio                   = Inp_RRM_RRRatio;
      cfg.SwingLookback             = Inp_RRM_SwingLookback;
      cfg.SL_SwingPipsCushion       = GetRecommendedInitialSlCushionPips();
      cfg.SL_PsarPipsCushion        = GetRecommendedInitialSlCushionPips();
      cfg.FixedTPPips               = 40.0;
      cfg.SLPercent                 = 0.5;

      cfg.TrailMode                 = Inp_RRM_TrailMode;
      cfg.PSAR_TrailCushionMode     = PSAR_CUSHION_PIPS;
      cfg.PSAR_TrailPipsCushion     = GetRecommendedTrailPsarCushionPips();
      cfg.BE_Mode                   = BE_MODE_R_MULTIPLE;

      // ── ADVANCED TRAILING TRIGGER ─────────────────────────────────────
      ENUM_TIMEFRAMES tf            = (ENUM_TIMEFRAMES)_Period;
      cfg.TrailTrigger              = TRIGGER_BREAKEVEN;
      cfg.TrailDistancePips         = GetTFBasedCushion(tf);
      cfg.BEThresholdPips           = GetTFBasedCushion(tf);
      cfg.TrailLockProfit           = true;              // true
      cfg.TrailProfitPercent        = 2.0;
      cfg.TrailStepPips             = 5.0;

      // ── FRACTAL SL/TP DEFAULTS ────────────────────────────────────────
      cfg.FractalPeriod             = 5;
      cfg.TPFractalOffset           = 1;

      // ── RRM DRAWDOWN PROTECTION ───────────────────────────────────────
      cfg.RRM_EnableDrawdownProtection = Inp_RRM_EnableDrawdownProtection;
      cfg.RRM_MaxConsecutiveLosses  = Inp_RRM_MaxConsecutiveLosses;
      cfg.RRM_MaxTradesPerDay       = Inp_RRM_MaxTradesPerDay;
      cfg.RRM_MaxDailyDrawdownPct   = Inp_RRM_MaxDailyDrawdownPct;

      // ── SLOPE CALCULATION ─────────────────────────────────────────────
      cfg.SlopeLookbackBars         = 1;

      // ── POLICY A: RESTORE OPERATOR-CONTROLLED GATES ───────────────────
      cfg.UseSpread                 = op_UseSpread;
      cfg.UseTime                   = op_UseTime;
      cfg.StartHr                   = op_StartHr;
      cfg.EndHr                     = op_EndHr;
      cfg.UseNews                   = op_UseNews;
      cfg.NewsPre                   = op_NewsPre;
      cfg.NewsPost                  = op_NewsPost;
      cfg.RiskPercent               = op_RiskPercent;
      cfg.MaxOpenTrades             = op_MaxOpenTrades;
      cfg.MaxTotalRisk              = op_MaxTotalRisk;
      cfg.MinMarginLevel            = op_MinMarginLevel;
      cfg.EmergencyMarginLevel      = op_EmergencyMarginLevel;

      // ── RE-ENTRY AFTER BREAKEVEN ──────────────────────────────────────
      cfg.AllowReEntryAfterBE       = true;

      // ── POST-TRADE COOLDOWN ───────────────────────────────────────────
      cfg.MinBarsAfterClose         = 3;

      // ── SPREAD RETRY CAP ─────────────────────────────────────────────
      cfg.MaxSpreadRetryBars        = 3;

      // ── EMA FAN OVEREXTENSION FILTER ──────────────────────────────────
      // EmaFanMaxTotalPips=25.0 is an empirically chosen starting point for
      // M1/M5 charts with the standard EMA5/13/34/89 fan. It represents the
      // approximate fan width at which trend exhaustion typically begins on
      // major FX pairs (e.g. EURUSD, GBPUSD). Adjust per instrument and TF:
      //   M15/H1: consider 40–60 pips; H4+: 80–120 pips.
      // JPY pairs: GlobalPipSize() returns the correct pip unit automatically.
      cfg.EmaFanFilterEnabled       = true;
      cfg.EmaFanMaxTotalPips        = 25.0;

      // ── DPI DECELERATION FILTER ────────────────────────────────────────
      // DPI voter not enabled in PRESET_RRM base; filter stays inactive.
      cfg.DpiDecelFilterEnabled     = false;

      return;
   }


   if(preset == PRESET_RRM_ORG)
   {
      // ================================================================
      // PRESET_RRM_ORG: Original Russ Horn RRM with Inline DPI Voter
      // ================================================================
      //
      // SIGNAL FORMULA (all steps must pass):
      //   STEP 1: DPI (inline TSI) — momentum direction voter
      //   STEP 2: Phase (4-EMA) — UNORDERED blocked, EMERGING/TRENDING allowed
      //   STEP 3: Layer (EMA pair spacing) — WEAK/MEDIUM/STRONG
      //   STEP 4: Recovery gates — Gate_Recovery + Gate_EmaDiv
      //   STEP 5: Bar close (BC_LAYER_AWARE) — close vs role-based EMA
      //   STEP 6: PSAR + CandleBody confirmation
      //   → ENTRY SIGNAL
      //
      // LOCKED: DPI (inline TSI), PSAR, CandleBody, phase structure,
      //         recovery gates, bar close mode.
      // FLEXIBLE: TSI periods (via Zone 3D inputs), SL/TP/Trail modes.
      // ================================================================

      // ── SIGNAL ARCHITECTURE: locked ──────────────────────────────────
      cfg.BiasMode               = BIAS_4EMA;
      cfg.AutoStrat              = STRAT_4EMA_LAYER;
      cfg.BiasFastID             = (int)ROLE_EMA3;    // EMA34: phase direction fast
      cfg.BiasSlowID             = (int)ROLE_EMA4;    // EMA89: phase direction slow
      cfg.MaType                 = METHOD_EMA;
      cfg.CloseOnReverse         = false;
      cfg.BiasEnabled            = true;
      cfg.RequirePriceCross      = false;
      cfg.MABenchmarkStrict      = false;
      cfg.UseMACompatSizer       = false;
      cfg.VoteMode               = VOTE_MODE_ALL;

      // ── EMA PERIODS: locked to RRM standard ──────────────────────────
      cfg.P_Ema1                 = 5;
      cfg.P_Ema2                 = 13;
      cfg.P_Ema3                 = 34;
      cfg.P_Ema4                 = 89;

      // ── DPI (inline TSI): LOCKED ON — only momentum voter ────────────
      cfg.Ind_Dpi_Enabled        = true;
      cfg.Ind_Dpi_Weight         = 1;
      cfg.DPI_TSI_R              = Inp_RRM_ORG_TSI_R;       // default 25
      cfg.DPI_TSI_S              = Inp_RRM_ORG_TSI_S;       // default 13
      cfg.DPI_TSI_U              = Inp_RRM_ORG_TSI_U;       // default 7
      cfg.DPI_TSI_FastR          = Inp_RRM_ORG_TSI_FastR;   // default 8 (Lead, original DPI)
      cfg.DPI_TSI_FastS          = Inp_RRM_ORG_TSI_FastS;   // default 13 (Follow, original DPI)
      cfg.DPI_MACD_Fast          = 8;
      cfg.DPI_MACD_Slow          = 13;
      cfg.DPI_MACD_Signal        = 5;

      // ── PSAR: LOCKED ON (timing/direction confirmation) ───────────────
      cfg.Ind_Psar_Enabled       = true;
      cfg.P_PsarStep             = 0.02;
      cfg.P_PsarMax              = 0.2;
      cfg.Vote_AllowPsarFlip     = true;
      cfg.Vote_PsarFlipDelay     = -1;   // Persistent: evaluate dot position on every bar

      // ── CANDLE BODY: LOCKED OFF (PSAR-flip entry bar may be doji/mixed) ─
      cfg.Ind_CandleBody_Enabled = false;
      cfg.Ind_CandleBody_Weight  = 1;
      cfg.CandleBody_AvgPeriod   = 15;
      cfg.CandleBody_MaxMult     = 3.5;
      cfg.CandleBody_CheckBars   = (_Period <= PERIOD_M5) ? 1 : 2;
      cfg.CandleBody_RequireDirection = false;

      // ── ALL OTHER INDICATORS: LOCKED OFF ─────────────────────────────
      cfg.Ind_Adx_Enabled        = false;
      cfg.Ind_Atr_Enabled        = false;
      cfg.Ind_Bb_Enabled         = false;
      cfg.Ind_CI_Enabled         = false;
      cfg.Ind_VRC_Enabled        = false;
      cfg.Ind_Cci_Enabled        = false;
      cfg.Ind_Macd_Enabled       = false;
      cfg.Ind_Mfi_Enabled        = false;
      cfg.Ind_P123_Enabled       = false;
      cfg.Ind_Ross_Enabled       = false;
      cfg.Ind_Rsi_Enabled        = false;
      cfg.Ind_Sto_Enabled        = false;
      cfg.Ind_SmaConverge_Enabled = false;
      cfg.Ind_SmaConverge_Weight  = 1;

      // ── ADX SETTINGS: safe defaults (disabled) ────────────────────────
      cfg.P_Adx                  = 14;
      cfg.T_Adx                  = 20.0;
      cfg.ADX_Mode               = ADX_MODE_STATIC;
      cfg.ADX_Percentile         = 50.0;
      cfg.ADX_Lookback           = 100;
      cfg.ADX_Threshold_Accumulation  = 12.0;
      cfg.ADX_Threshold_Trending      = 25.0;
      cfg.ADX_Threshold_Distribution  = 18.0;

      // ── ATR SETTINGS: safe defaults (disabled) ────────────────────────
      cfg.P_Atr                  = 14;
      cfg.ATR_VoteMinPips        = 5.0;
      cfg.ATR_VoteMaxPips        = 50.0;

      // ── MACD SETTINGS: safe defaults (disabled) ───────────────────────
      cfg.P_MacdFast             = 12;
      cfg.P_MacdSlow             = 26;
      cfg.P_MacdSig              = 9;
      cfg.MacdVoteMode           = MACD_HISTOGRAM;
      cfg.MacdRequireSlope       = false;
      cfg.MacdRequireDivergence  = false;
      cfg.MacdRequireHook        = false;
      cfg.MacdFreshBars          = 3;
      cfg.MacdSlopeMin           = 0.00001;

      // ── CCI/RSI/STOCH/BB/MFI: safe defaults (all disabled) ───────────
      cfg.P_Cci                  = 14;
      cfg.CciMode                = CCI_TREND_ZERO;
      cfg.P_Rsi                  = 14;
      cfg.T_RsiOB                = 70.0;
      cfg.T_RsiOS                = 30.0;
      cfg.RsiMode                = RSI_TREND_ABOVE_50;
      cfg.P_StoK                 = 5;
      cfg.P_StoD                 = 3;
      cfg.P_StoSlow              = 3;
      cfg.T_StoOB                = 80.0;
      cfg.T_StoOS                = 20.0;
      cfg.StoMode                = STO_CROSS_SIGNAL;
      cfg.P_Bb                   = 20;
      cfg.P_BbDev                = 2.0;
      cfg.BbMode                 = BB_TREND_FOLLOW;
      cfg.P_Mfi                  = 14;
      cfg.T_MfiOB                = 80.0;
      cfg.T_MfiOS                = 20.0;
      cfg.MfiMode                = MFI_ZONE_FILTER;

      // ── CI/VRC: safe defaults (disabled) ─────────────────────────────
      cfg.CI_Period              = 14;
      cfg.CI_RangingThreshold    = 61.8;
      cfg.Ind_CI_Weight          = 1;
      cfg.VRC_ATR_Period         = 14;
      cfg.VRC_Lookback           = 100;
      cfg.VRC_LowThreshold       = 33.0;
      cfg.Ind_VRC_Weight         = 1;

      // ── BAR CLOSE (bcX): LOCKED to layer-aware ───────────────────────
      cfg.BarClose_Enabled       = true;
      cfg.BarClose_Mode          = BC_LAYER_AWARE;   // bcW=EMA1, bcM=EMA2, bcS=EMA3
      cfg.BarClose_DefaultEMA    = ROLE_EMA1;

      // ── PHASE DETECTION & LAYER FILTERING: LOCKED ON ─────────────────
      cfg.PhaseDetectionEnabled     = true;
      cfg.EnableLayerDetection      = true;
      cfg.BlockUnorderedPhase       = true;           // UNORDERED → block all trades
      cfg.BlockEmergingPhase        = true;           // true: EM phase = no trades; TM phase = trades allowed
      cfg.RequireRecoveryMomentum = (_Period <= PERIOD_M5) ? true : false; 
      cfg.MinPhaseConfirmBars     = (_Period <= PERIOD_M5) ? 0 : 1;        // M1: No delay needed on M1

      // EMERGING phase: WEAK + MEDIUM only; STRONG always blocked per RRM methodology
      cfg.Emerging_AllowWeakTrades   = Inp_RRM_AllowWeak;
      cfg.Emerging_AllowMediumTrades = Inp_RRM_AllowMedium;
      cfg.Emerging_AllowStrongTrades = false;         // STRONG always blocked in EMERGING per RRM methodology

      // TRENDING phase: controlled by layer filter inputs (Inp_RRM_Allow*)
      cfg.Trending_AllowWeakTrades   = Inp_RRM_AllowWeak;
      cfg.Trending_AllowMediumTrades = Inp_RRM_AllowMedium;
      cfg.Trending_AllowStrongTrades = Inp_RRM_AllowStrong;

      // ── PULLBACK DETECTION GATES: LOCKED ON ──────────────────────────
      cfg.RequireRecoveryMomentum   = false;   // Wick-touch recovery valid on M1/M5
      cfg.Gate_Recovery.mode        = GATE_SCALE_AUTO_TF;
      cfg.Gate_Recovery.value       = 1.0;
      cfg.RRM_Lookback              = (_Period <= PERIOD_M1) ? 15 : (_Period <= PERIOD_M5) ? 10 : 12;

      cfg.Gate_EmaDiv.mode          = GATE_SCALE_AUTO_TF;
      cfg.Gate_EmaDiv.value         = 1.0;
      cfg.RRM_MinDivPips            = 1.5;

      cfg.Gate_CandleDirection.mode  = GATE_SCALE_FIXED;
      cfg.Gate_CandleDirection.value = 1.0;

      // ── VOTE EVALUATION ───────────────────────────────────────────────
      cfg.Vote_EvalShift            = 1;

      // ── RISK MANAGEMENT ───────────────────────────────────────────────
      cfg.CountBEasZeroRisk         = true;
      cfg.FixedLotSize              = 0.0;

      // ── EXIT STRATEGY: flexible (uses RRM profile, SL/TP from inputs) ─
      cfg.ExitProfile               = EXIT_PROFILE_RRM;
      cfg.SLMode                    = Inp_RRM_SLMode;
      cfg.TPMode                    = Inp_RRM_TPMode;
      cfg.TP_Enabled                = (Inp_RRM_TPMode != TP_MODE_NONE);
      cfg.RRRatio                   = Inp_RRM_RRRatio;
      cfg.SwingLookback             = Inp_RRM_SwingLookback;
      cfg.SL_SwingPipsCushion       = GetRecommendedInitialSlCushionPips();
      cfg.SL_PsarPipsCushion        = GetRecommendedInitialSlCushionPips();
      cfg.FixedTPPips               = 40.0;
      cfg.SLPercent                 = 0.5;

      cfg.TrailMode                 = Inp_RRM_TrailMode;
      cfg.PSAR_TrailCushionMode     = PSAR_CUSHION_PIPS;
      cfg.PSAR_TrailPipsCushion     = GetRecommendedTrailPsarCushionPips();
      cfg.BE_Mode                   = BE_MODE_R_MULTIPLE;

      ENUM_TIMEFRAMES tfOrg         = (ENUM_TIMEFRAMES)_Period;
      cfg.TrailTrigger              = TRIGGER_BREAKEVEN;
      cfg.TrailDistancePips         = GetTFBasedCushion(tfOrg);
      cfg.BEThresholdPips           = GetTFBasedCushion(tfOrg);
      cfg.TrailLockProfit           = true;
      cfg.TrailProfitPercent        = 2.0;
      cfg.TrailStepPips             = 5.0;

      cfg.FractalPeriod             = 5;
      cfg.TPFractalOffset           = 1;

      // ── DRAWDOWN PROTECTION ───────────────────────────────────────────
      cfg.RRM_EnableDrawdownProtection = Inp_RRM_EnableDrawdownProtection;
      cfg.RRM_MaxConsecutiveLosses  = Inp_RRM_MaxConsecutiveLosses;
      cfg.RRM_MaxTradesPerDay       = Inp_RRM_MaxTradesPerDay;
      cfg.RRM_MaxDailyDrawdownPct   = Inp_RRM_MaxDailyDrawdownPct;

      // ── SLOPE CALCULATION ─────────────────────────────────────────────
      cfg.SlopeLookbackBars         = 1;
      cfg.ma_h_shift                = 0;
      cfg.ma_v_shift                = 1;

      // ── POLICY A: RESTORE OPERATOR-CONTROLLED GATES ───────────────────
      cfg.MaxSpread                 = op_MaxSpread;
      cfg.UseSpread                 = op_UseSpread;
      cfg.UseTime                   = op_UseTime;
      cfg.StartHr                   = op_StartHr;
      cfg.EndHr                     = op_EndHr;
      cfg.UseNews                   = op_UseNews;
      cfg.NewsPre                   = op_NewsPre;
      cfg.NewsPost                  = op_NewsPost;
      cfg.RiskPercent               = op_RiskPercent;
      cfg.MaxOpenTrades             = op_MaxOpenTrades;
      cfg.MaxTotalRisk              = op_MaxTotalRisk;
      cfg.MinMarginLevel            = op_MinMarginLevel;
      cfg.EmergencyMarginLevel      = op_EmergencyMarginLevel;

      // ── RE-ENTRY AFTER BREAKEVEN ──────────────────────────────────────
      cfg.AllowReEntryAfterBE       = true;

      // ── POST-TRADE COOLDOWN ───────────────────────────────────────────
      cfg.MinBarsAfterClose         = 3;

      // ── SPREAD RETRY CAP ─────────────────────────────────────────────
      cfg.MaxSpreadRetryBars        = 3;

      // ── EMA FAN OVEREXTENSION FILTER ──────────────────────────────────
      // EmaFanMaxTotalPips=25.0 is an empirically chosen starting point for
      // M1/M5 charts with the standard EMA5/13/34/89 fan. It represents the
      // approximate fan width at which trend exhaustion typically begins on
      // major FX pairs (e.g. EURUSD, GBPUSD). Adjust per instrument and TF:
      //   M15/H1: consider 40–60 pips; H4+: 80–120 pips.
      // JPY pairs: GlobalPipSize() returns the correct pip unit automatically.
      cfg.EmaFanFilterEnabled       = false;
      cfg.EmaFanMaxTotalPips        = 25.0;   // value retained for reference, filter is off

      // ── DPI DECELERATION FILTER ────────────────────────────────────────
      // DPI voter is enabled in PRESET_RRM_ORG — decel filter is active.
      cfg.DpiDecelFilterEnabled     = true;

      return;
   }
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
      cfg.BiasEnabled               = true;           // true
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
      cfg.Ind_CandleBody_Enabled    = true;           // true
      cfg.Ind_CI_Enabled            = false;
      cfg.Ind_VRC_Enabled           = false;
      cfg.Ind_Cci_Enabled           = true;           // true
      cfg.Ind_Macd_Enabled          = true;           // true
      cfg.Ind_Mfi_Enabled           = false;
      cfg.Ind_P123_Enabled          = false;
      cfg.Ind_Psar_Enabled          = true;           // true
      cfg.Ind_Ross_Enabled          = false;
      cfg.Ind_Rsi_Enabled           = false;
      cfg.Ind_Sto_Enabled           = false;
      cfg.Ind_SmaConverge_Enabled   = false;
      cfg.Ind_SmaConverge_Weight    = 1;
      cfg.Ind_Dpi_Enabled           = false;
      cfg.Ind_Dpi_Weight            = 1;
   
      // BAR CLOSE (bcX) CONFIGURATION
      cfg.BarClose_Enabled          = true;           // true
      cfg.BarClose_Mode             = BC_BIAS_FAST;   // Fast
      cfg.BarClose_DefaultEMA       = ROLE_EMA1;      // Close vs EMA1
   
      cfg.VoteMode = VOTE_MODE_ALL;
      
      // ================================================================
      // INDICATOR PERIODS & THRESHOLDS (Alphabetical)
      // ================================================================
      
      // ADX (Average Directional Index)
      cfg.ADX_Mode                  = ADX_MODE_STATIC;
      cfg.P_Adx                     = 14;
      cfg.T_Adx                     = 20.0;
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
      cfg.BbMode                    = BB_TREND_FOLLOW;
      cfg.P_Bb                      = 20;
      cfg.P_BbDev                   = 2.0;
      
      // Candle Body
      cfg.CandleBody_AvgPeriod      = 5;      // ORG: 10     5
      cfg.CandleBody_MaxMult        = 3.0;    // ORG:  3.0   3.0
      cfg.CandleBody_CheckBars      = 3;      // ORG:  1     3
      cfg.CandleBody_RequireDirection = true;
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
      cfg.CciMode                   = CCI_TREND_ZERO;
      cfg.P_Cci                     = 13;          // ORG: 14
      
      // EMA (Periods)
      cfg.P_Ema1                    = 5;           // ORG:  5
      cfg.P_Ema2                    = 13;          // ORG: 13
      cfg.P_Ema3                    = 34;          // ORG: 34
      cfg.P_Ema4                    = 89;          // ORG: 89
   
      // MACD (Moving Average Convergence Divergence)
      cfg.MacdVoteMode              = MACD_ZERO_AND_HIST;
      cfg.P_MacdFast                = 8;           // ORG: 12  8   5  5
      cfg.P_MacdSlow                = 13;          // ORG: 26  13  8  8
      cfg.P_MacdSig                 = 5;           // ORG: 9   8   5  3
      cfg.MacdRequireSlope          = true;        // ORG: false
      cfg.MacdRequireDivergence     = false;       // ORG: false
      cfg.MacdRequireHook           = false;       // ORG: false
      cfg.MacdFreshBars             = 10;          // ORG: 3
      cfg.MacdSlopeMin              = 0.000001;    // ORG: 0.00001
   
      // MFI (Money Flow Index)
      cfg.MfiMode                   = MFI_ZONE_FILTER;
      cfg.P_Mfi                     = 14;
      cfg.T_MfiOB                   = 80.0;
      cfg.T_MfiOS                   = 20.0;
      
      // PSAR (Parabolic SAR)
      cfg.Vote_AllowPsarFlip        = true;        // true
      cfg.P_PsarStep                = 0.05;
      cfg.P_PsarMax                 = 0.5;
      cfg.Vote_PsarFlipDelay        = -1;          // -1=Flip+Dot, 0=Flip only, 1,2,..=Flip+N only
   
      // RSI (Relative Strength Index)
      cfg.RsiMode                   = RSI_TREND_ABOVE_50;
      cfg.P_Rsi                     = 14;
      cfg.T_RsiOB                   = 70.0;
      cfg.T_RsiOS                   = 30.0;
      
      // Stochastic Oscillator
      cfg.StoMode                   = STO_CROSS_SIGNAL;
      cfg.P_StoK                    = 5;
      cfg.P_StoD                    = 3;
      cfg.P_StoSlow                 = 3;
      cfg.T_StoOB                   = 80.0;
      cfg.T_StoOS                   = 20.0;
      
      // ================================================================
      // PHASE DETECTION & LAYER FILTERING (All disabled for testing)
      // ================================================================
      cfg.PhaseDetectionEnabled        = false;
      cfg.EnableLayerDetection         = false;
      cfg.BlockUnorderedPhase          = false;
      cfg.BlockEmergingPhase           = false;
      cfg.RequireMinPhaseConfirm       = false;
      cfg.MinPhaseConfirmBars          = 0;
      
      // Layer permissions per phase
      cfg.Trending_AllowWeakTrades     = false;
      cfg.Emerging_AllowWeakTrades     = false;
      cfg.Trending_AllowMediumTrades   = false;
      cfg.Emerging_AllowMediumTrades   = false;
      cfg.Trending_AllowStrongTrades   = false;
      cfg.Emerging_AllowStrongTrades   = false;
      
      // ================================================================
      // PULLBACK DETECTION GATES (All disabled)
      // ================================================================
      cfg.RequireRecoveryMomentum      = false;   // ORG: false
   
      // Gate 2: Recovery momentum
      cfg.Gate_Recovery.mode           = GATE_SCALE_FIXED;
      cfg.Gate_Recovery.value          = 0.0;
      cfg.RRM_Lookback                 = 0;
      
      // Gate 3: EMA divergence
      cfg.Gate_EmaDiv.mode             = GATE_SCALE_FIXED;
      cfg.Gate_EmaDiv.value            = 0.0;
      cfg.RRM_MinDivPips               = 0.0;
      
      // Gate 4: Candle direction
      cfg.Gate_CandleDirection.mode    = GATE_SCALE_FIXED;
      cfg.Gate_CandleDirection.value   = 0.0;
      
      // ================================================================
      // VOTE EVALUATION SETTINGS
      // ================================================================
      cfg.Vote_EvalShift               = 1;
      
      // ================================================================
      // RISK MANAGEMENT (Portfolio-level)
      // ================================================================
      cfg.CountBEasZeroRisk            = true;     // ORG: false
      cfg.RiskPercent                  = 2.0;      // ORG: 2.0
      cfg.FixedLotSize                 = 0.0;
      cfg.MaxTotalRisk                 = 6.0;
      cfg.MaxOpenTrades                = 3;
      
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
         cfg.SwingLookback          = swing_lookback;  // TF-adaptive (M1=10 bars, D1=30 bars)
         cfg.RRRatio                = 2.0;             // Risk:Reward = 2:1 (risk 50p to win 100p)

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
         cfg.RRM_BE_BufferPips      = be_cushion * 1; // ORG: * 0.5: TF-adaptive, tighter (H4=7.5p vs old 15p)
         cfg.RRM_BE_ProgressPct     = 5.0;            // Trigger at 10% progress toward TP
         cfg.BEThresholdPips        = 0.0;            // Not used (ProgressPct mode)

         // ────────────────────────────────────────────────────────────
         // TRAILING STOP
         // ────────────────────────────────────────────────────────────
         cfg.TrailMode              = TRAIL_PSAR;
         cfg.TrailTrigger           = TRIGGER_IMMEDIATE; // Start checking immediately
         cfg.RRM_TrailStartsAfterBE = false;          // ✅ Only trail after BE hit (safer!)
         cfg.TrailLockProfit        = true;           // Never trail SL below entry
         cfg.TrailDistancePips      = 5.0;            // Not used (PSAR mode = dynamic)
         cfg.TrailProfitPercent     = 5.0;            // Not used (PSAR mode)
         cfg.TrailStepPips          = 0.0;            // Not used (PSAR mode)

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

      // ════════════════════════════════════════════════════════════════
      // BAR CLOSE (bcX) CONFIGURATION
      // Formula: TS = Bias × LayerX × bcX × IndicatorX × FilterX
      // CONFIGURATION: Fixed EMA1 check (not layer-aware for simpler testing)
      // ════════════════════════════════════════════════════════════════
      cfg.BarClose_Mode             = BC_BIAS_FAST;   // Always check vs fixed EMA
      cfg.BarClose_DefaultEMA       = ROLE_EMA1;      // Close vs EMA1
      cfg.BarClose_Enabled          = true;           // ✅ Enable bcX
      
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
      cfg.MinMarginLevel            = op_MinMarginLevel; // Policy A: restore entry margin guard
      cfg.EmergencyMarginLevel      = op_EmergencyMarginLevel; // Policy A: restore emergency margin guard

      return;
   }

}

//+------------------------------------------------------------------+
//| END OF FILE                                                      |
//+------------------------------------------------------------------+
