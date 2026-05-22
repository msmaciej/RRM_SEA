//+------------------------------------------------------------------+
//|                                           SimpleEA_v1-04.mq5     |
//|                       Copyright © 2025 Maciej Jerzy Szczech (MJS)|
//|                      RRM Simple EA - macOS + Wine + MT5 + MQL5   |
//+------------------------------------------------------------------+
// SAVE AS UTF-16 LE WITH BOM
//+------------------------------------------------------------------+
#property copyright "Copyright © 2025 Maciej Jerzy Szczech (MJS)"
#property link      "https://github.com/msmaciej/RRM_SEA"
#property version   "104.001"
#property strict
#property description "Simple Expert Advisor - Original research and development"
#property description "Incorporates concepts from multiple trading methodologies"
#property description "macOS + Wine + MT5 compatible | MQL5 ONLY"

// ══════════════════════════════════════════════════════════════════
// 🔒 ACTIVE BUILD TOKEN - DO NOT MODIFY
// This is the CURRENT production version. All legacy tokens (103003,
// 102016D, etc.) in Legacy/ and Revision/ folders are ARCHIVED.
// ══════════════════════════════════════════════════════════════════
#define SEA_BUILD_TOKEN_104001 1

#define SEA_BUILD_NUM 104001
#define SEA_BUILD_STR "1.04.001"
// ══════════════════════════════════════════════════════════════════

//+------------------------------------------------------------------+
//| FORWARD DECLARATIONS                                             |
//+------------------------------------------------------------------+
void SEA_DrawEntrySignalLine(datetime bar_time, int direction, const string label);
void SEA_DrawTradeExecLine(datetime event_time, int direction, double price, const string label);

//+------------------------------------------------------------------+
//| MODULE INCLUDES                                                  |
//+------------------------------------------------------------------+
#include <RRMS\SEA_Config.mqh>
#include <RRMS\SEA_Presets.mqh>
#include <RRMS\SEA_SignalEngine.mqh>
#include <RRMS\SEA_TradeExecutor.mqh>
#include <RRMS\SEA_UI.mqh>
#include <RRMS\SEA_Reporting.mqh>

#ifndef SEA_MOD_SIGNALENGINE_104001
enum { __SEA_STALE_SEA_MOD_SIGNALENGINE_104001__ = SEA_MOD_SIGNALENGINE_104001 };
#endif
#ifndef SEA_MOD_TRADEEXEC_104001
enum { __SEA_STALE_SEA_MOD_TRADEEXEC_104001__ = SEA_MOD_TRADEEXEC_104001 };
#endif
#ifndef SEA_MOD_UI_104001
enum { __SEA_STALE_SEA_MOD_UI_104001__ = SEA_MOD_UI_104001 };
#endif
#ifndef SEA_MOD_REPORTING_104001
enum { __SEA_STALE_SEA_MOD_REPORTING_104001__ = SEA_MOD_REPORTING_104001 };
#endif

//+------------------------------------------------------------------+
//| GLOBAL STATE & MODULE OBJECTS                                    |
//+------------------------------------------------------------------+

CSignalEngine  Signal;
CTradeExecutor Executor;

// --- UI/Reporting compatibility globals (previously built in old presets logic)
EEmaStrategy g_effectiveEmaStrategy = EMA_STRAT_1_PRICE_CROSS;
EMaMethod    g_effectiveMaType      = METHOD_EMA;
EBiasMode    g_effectiveBiasMode    = BIAS_2EMA;
string       g_effectiveSigNote     = "";
string       g_effectiveDirSource   = "";

string       g_ui_used_flags        = "";
string       g_ui_ignored_flags     = "";
string       g_ui_overrides         = "";
string       g_ui_ma_source         = "";

datetime g_last_bar_time            = 0;
datetime g_start_time               = 0;
bool     g_chart_indicators_managed = false;

// --- TS snapshot (last confirmed trade signal evaluated at shift=1)
datetime g_ts_time   = 0;
int      g_ts_dir    = 0;
int      g_ts_bias   = 0;
int      g_ts_votes  = 0;
string   g_ts_reason = "";

// TS snapshot — SL/Lots/Risk captured after TE runs (for diagnostics)
double g_ts_sl   = 0.0;
double g_ts_lots = 0.0;
double g_ts_risk = 0.0;

// Last TE execution result — persists until TE runs again (not reset each bar)
string g_last_te_result = "";   // "ENTERED", "BLOCKED", or "" (no TE this session)
string g_last_te_veto   = "";   // "SL_ZERO", "VETO_RISK_CONTROL", "OK", or ""

// TE retry tracking — allows VETO_OPEN_DELAY (and other temporary vetoes) to
// keep the signal alive across ticks rather than consuming it on the first attempt.
int      g_te_retry_count = 0;          // Current retry attempt counter
datetime g_te_retry_bar   = 0;          // Bar time when TE retries started
const int MAX_TE_RETRIES  = 200;        // Retry limit per bar (safety cap)

// Global tracking for RRM drawdown protection
int      g_consecutive_losses     = 0;
int      g_trades_today           = 0;
datetime g_last_trade_date        = 0;
double   g_daily_starting_balance = 0.0;

// System analysis tracking (for end-of-test report)
double g_starting_balance = 0.0;   // Account balance captured at EA start
double g_peak_equity      = 0.0;   // Highest equity seen during the test
double g_max_drawdown_abs = 0.0;   // Maximum absolute equity drawdown (peak - trough)

// Trade return tracking for Sharpe Ratio calculation
double g_trade_returns[];          // Array of % returns per trade (relative to starting balance)
int    g_trade_return_count = 0;   // Number of trades tracked


//+------------------------------------------------------------------+
//| EXPERT LIFECYCLE                                                 |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| ONINIT
//+------------------------------------------------------------------+
int OnInit() { return OrchestrateInit(); }

//+------------------------------------------------------------------+
//| ONTICK
//+------------------------------------------------------------------+
void OnTick()
{
   if(Inp_UI_ManageChartIndicators && !g_chart_indicators_managed)
   {
      SEA_UI_ManageChartIndicators(Signal);
      g_chart_indicators_managed = true;
   }
   OrchestrateTick();
}

//+------------------------------------------------------------------+
//| ONDEINIT
//+------------------------------------------------------------------+
void OnDeinit(const int reason) { OrchestrateDeinit(reason); }

// ✅ ADD THIS NEW HANDLER HERE (after OnDeinit, before helpers section)
void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& request,
                        const MqlTradeResult& result)
{
   // Only process deal transactions (position close events)
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   
   // Only track our EA's positions
   if(trans.symbol != _Symbol) return;
   
   // Get deal information
   ulong deal_ticket = trans.deal;
   if(deal_ticket == 0) return;
   
   if(HistoryDealSelect(deal_ticket))
   {
      long deal_magic = HistoryDealGetInteger(deal_ticket, DEAL_MAGIC);
      if(deal_magic != Inp_Global_MagicNum) return;  // Not our trade
      
      long deal_entry = HistoryDealGetInteger(deal_ticket, DEAL_ENTRY);
      if(deal_entry != DEAL_ENTRY_OUT) return;  // Not a position close
      
      // Get profit/loss
      double profit = HistoryDealGetDouble(deal_ticket, DEAL_PROFIT);
      double swap = HistoryDealGetDouble(deal_ticket, DEAL_SWAP);
      double commission = HistoryDealGetDouble(deal_ticket, DEAL_COMMISSION);
      double total_pl = profit + swap + commission;
      
      bool was_profitable = (total_pl > 0);

      // Store return as % of starting balance for Sharpe Ratio calculation
      if(g_starting_balance > 0.0)
      {
         double return_pct = (total_pl / g_starting_balance) * 100.0;
         ArrayResize(g_trade_returns, g_trade_return_count + 1);
         g_trade_returns[g_trade_return_count] = return_pct;
         g_trade_return_count++;
      }

      // Update tracking
      UpdateRRMDrawdownTracking(was_profitable);
      
      if(Settings.DebugFlow)
      {
         PrintFormat("[RRM_DD_TRACK] Position closed: P/L=%.2f %s | Consecutive losses=%d | Trades today=%d",
                     total_pl, 
                     was_profitable ? "WIN" : "LOSS",
                     g_consecutive_losses,
                     g_trades_today);
      }
   }
}

//+------------------------------------------------------------------+
//| HELPERS                                                          |
//+------------------------------------------------------------------+
void FlowLog(const string msg)
{
   if(Inp_Debug_Flow && Inp_Debug_Level >= DEBUG_FULL) Print("FLOW: ", msg);
}

void BuildUiReportingState()
{
   // In Model A, "effective" is simply the post-preset Settings.
   g_effectiveBiasMode    = Settings.BiasMode;
   g_effectiveMaType      = Settings.MaType;
   g_effectiveSigNote     = "";
   g_effectiveDirSource   = (Settings.BiasEnabled ? "AUTO" : "DISABLED");

   // Best-effort effective strategy label for UI/Reporting (derived from resulting behavior)
   if(!Settings.BiasEnabled)
      g_effectiveEmaStrategy = EMA_STRAT_CUSTOM;
   else
   {
      if(Settings.AutoStrat == STRAT_2EMA_CROSS_PRICE && Settings.BiasFastID == 0 && Settings.BiasSlowID == 0)
         g_effectiveEmaStrategy = EMA_STRAT_1_PRICE_CROSS;
      else if(Settings.AutoStrat == STRAT_2EMA_CROSS_EMA && Settings.BiasFastID == 0 && Settings.BiasSlowID == 1)
         g_effectiveEmaStrategy = EMA_STRAT_2_CROSS_1_2;
      else if(Settings.AutoStrat == STRAT_2EMA_CROSS_EMA && Settings.BiasFastID == 2 && Settings.BiasSlowID == 3)
         g_effectiveEmaStrategy = EMA_STRAT_2_CROSS_3_4;
      else
         g_effectiveEmaStrategy = EMA_STRAT_CUSTOM;
   }

   g_ui_ma_source = (Inp_Global_Preset == PRESET_MA ? "BENCHMARK" : "CUSTOM");

   if(Inp_Global_Preset == PRESET_CUSTOM)
   {
      g_ui_used_flags    = "CUSTOM";
      g_ui_ignored_flags = "";
      g_ui_overrides     = "";
   }
   else
   {
      g_ui_used_flags    = "PRESET=" + PresetToString(Inp_Global_Preset);
      g_ui_ignored_flags = "Strategy inputs ignored (preset authoritative)";
      g_ui_overrides     = "Preset overwrote strategy-critical fields";
      g_effectiveSigNote = "Preset is active; strategy inputs ignored.";
   }
}

void PrintEffectiveConfig()
{
   Print("------------------------------------------");
   Print("--- SimpleEA v", SEA_BUILD_STR, " Configuration ---");
   Print("Program: ", MQLInfoString(MQL_PROGRAM_NAME), " | Path: ", MQLInfoString(MQL_PROGRAM_PATH));
   Print("Symbol: ", _Symbol, " | Magic: ", Inp_Global_MagicNum);
   Print("Preset: ", EnumToString(Inp_Global_Preset), " (", (int)Inp_Global_Preset, ")");

   if(Inp_Global_Preset != PRESET_CUSTOM)
   {
      Print("Preset ", PresetToString(Inp_Global_Preset), " is active; strategy inputs ignored");
   }

   Print("Diagnostics: PrintEffectiveConfig=", (Settings.PrintEffectiveConfig ? "true" : "false"),
         " DebugFlow=", (Settings.DebugFlow ? "true" : "false"),
         " DebugLevel=", EnumToString(Settings.DebugLevel));

   if(Settings.DebugEvalFrom > 0 || Settings.DebugEvalAt > 0)
   {
      Print("DebugEval: Window=[", TimeToString(Settings.DebugEvalFrom, TIME_DATE|TIME_MINUTES),
            " → ", TimeToString(Settings.DebugEvalTo, TIME_DATE|TIME_MINUTES),
            "] At=", (Settings.DebugEvalAt > 0 ? TimeToString(Settings.DebugEvalAt, TIME_DATE|TIME_MINUTES) : "off"),
            " Mode=", EnumToString(Settings.DebugEvalMode));
   }

   Print("UI: StatusPanel=", (Settings.UI_ShowStatusPanel ? "true" : "false"),
         " CockpitPanel=", (Settings.UI_ShowCockpitPanel ? "true" : "false"),
         " ManageChartIndicators=", (Settings.UI_ManageChartIndicators ? "true" : "false"),
         " DrawEntryLines=", (Settings.DrawEntryLines ? "true" : "false"),
         " DrawTradeLines=", (Settings.DrawTradeLines ? "true" : "false"));

   Print("Reporting: ExportCSV=", (Settings.ExportCSV ? "true" : "false"),
         " ExportUseCommonFiles=", (Settings.ExportUseCommonFiles ? "true" : "false"));

   Print("Effective: CloseOnReverse=", (Settings.CloseOnReverse ? "true" : "false"),
         " Risk%=", DoubleToString(Settings.RiskPercent, 2),
         " MaxSpreadPips=", DoubleToString(Settings.MaxSpread, 2));

   Print("Effective: BiasEnabled=", (Settings.BiasEnabled ? "true" : "false"),
         " BiasMode=", EnumToString(Settings.BiasMode),
         " ManSide=", EnumToString(Settings.ManSide));

   Print("Effective: AutoStrat=", EnumToString(Settings.AutoStrat),
         " BiasFastID=", Settings.BiasFastID,
         " BiasSlowID=", Settings.BiasSlowID);

   Print("Effective: MA Method=", EnumToString(Settings.MaType),
         " h_shift=", Settings.ma_h_shift,
         " v_shift=", Settings.ma_v_shift);

   if(Settings.MABenchmarkStrict)
      Print("MA Benchmark Inputs: MaxRisk=", Inp_MA_MaximumRiskPct, "% Dec=", Inp_MA_DecreaseFactor,
            " Period=", Inp_MA_Period, " Shift=", Inp_MA_Shift);

   Print("Effective EMA periods: ", Settings.P_Ema1, ",", Settings.P_Ema2, ",", Settings.P_Ema3, ",", Settings.P_Ema4);
   Print("Effective MACD periods: ", Settings.P_MacdFast, ",", Settings.P_MacdSlow, ",", Settings.P_MacdSig);
   Print("MACD Mode: ", GetMACDModeDescription(Settings.MacdVoteMode, Settings.MacdRequireSlope,
                                               Settings.MacdRequireDivergence, Settings.MacdRequireHook));

   if(Settings.ExitProfile == EXIT_PROFILE_RRM || Inp_Global_Preset == PRESET_RRM)
   {
      Print("Effective: ExitProfile=", EnumToString(Settings.ExitProfile),
            " TP_Enabled=", (Settings.TP_Enabled ? "true" : "false"),
            " RRRatio=", DoubleToString(Settings.RRRatio, 2),
            " BE_Mode=", EnumToString(Settings.BE_Mode));
      Print("Effective: RRM_BE_ProgressPct=", DoubleToString(Settings.RRM_BE_ProgressPct, 1),
            " RRM_BE_BufferPips=", DoubleToString(Settings.RRM_BE_BufferPips, 1),
            " TrailPsarShiftDelay=", Settings.RRM_TrailPsarShiftDelay,
            " FreezeTrailOnFlip=", (Settings.RRM_FreezeTrailOnFlip ? "true" : "false"),
            " TrailStartsAfterBE=", (Settings.RRM_TrailStartsAfterBE ? "true" : "false"));
   }
   Print("------------------------------------------");
}

bool ValidateEffectiveSettings()
{
   if((int)Settings.MaType < (int)METHOD_EMA || (int)Settings.MaType > (int)METHOD_SMA)
   {
      Print("ERROR: Settings.MaType is out of range: ", (int)Settings.MaType);
      return false;
   }
   if(Settings.BiasFastID < 0 || Settings.BiasFastID > 3 || Settings.BiasSlowID < 0 || Settings.BiasSlowID > 3)
   {
      Print("ERROR: Bias EMA role IDs out of range. FastID=", Settings.BiasFastID, " SlowID=", Settings.BiasSlowID);
      return false;
   }
   return true;
}

// When a trade closes, update consecutive loss counter and daily trade count
void UpdateRRMDrawdownTracking(bool was_profitable)
{
   // FIX Bug5: always update g_consecutive_losses for accurate [RRM_DD_TRACK] logging,
   // regardless of whether DrawdownProtection is enabled.
   // g_trades_today is tracked at trade ENTRY in OrchestrateTick().
   if(was_profitable)
      g_consecutive_losses = 0;  // Reset on win
   else
      g_consecutive_losses++;    // Increment on loss

   // Bail out early if protection is disabled — counters above are still updated for display.
   if(!Settings.RRM_EnableDrawdownProtection) return;
}


//+------------------------------------------------------------------+
//| VALIDATE CONFIGURATION
//+------------------------------------------------------------------+
void ValidateConfiguration()
{
   Print("════════════════════════════════════════════════");
   Print("  CONFIGURATION VALIDATION");
   Print("════════════════════════════════════════════════");

   bool has_warnings = false;

   // (Admin override section removed)

   // Warn if phase detection enabled but BiasMode is not BIAS_4EMA
   if(Settings.PhaseDetectionEnabled && Settings.BiasMode != BIAS_4EMA) {
      Print("WARNING: PhaseDetection=true but BiasMode != BIAS_4EMA");
      Print("   Phase detection only works with BIAS_4EMA");
      has_warnings = true;
   }

   // Warn if layer detection enabled but phase detection is off
   if(Settings.EnableLayerDetection && !Settings.PhaseDetectionEnabled) {
      Print("WARNING: LayerDetection=true but PhaseDetection=false");
      Print("   Layer filtering has no effect without phase detection");
      has_warnings = true;
   }

   // Count enabled indicators using central helper (all 13 indicators)
   int enabled = GetEnabledIndicatorCount(Settings);

   if(enabled == 0) {
      Print("WARNING: NO indicators enabled!");
      Print("   No trades possible (at least 1 indicator required for signal generation)");
      has_warnings = true;
   }

   if(enabled > 6) {
      Print("WARNING: ", enabled, " indicators enabled (ALL must pass)");
      Print("   Very restrictive, consider disabling some");
      has_warnings = true;
   }

   if(!has_warnings) {
      Print("OK: No configuration warnings");
   }

   Print("════════════════════════════════════════════════");
}

//+------------------------------------------------------------------+
//| ORCHESTRATE INIT
//+------------------------------------------------------------------+
int OrchestrateInit()
{
   FlowLog("EA start -> OnInit()");
   g_start_time = TimeCurrent();

   FlowLog("Step A: InitializeConfig() (inputs -> Settings)");
   InitializeConfig();

   // Pip size sanity check (helps diagnose unusual broker digit configurations)
   double pip_sz = GlobalPipSize(_Symbol);
   int    sym_digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double tick_sz    = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tick_val   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tick_val_loss = 0.0;
   SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE_LOSS, tick_val_loss);
   double contract_sz = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
   string acc_ccy     = AccountInfoString(ACCOUNT_CURRENCY);
   string profit_ccy  = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_PROFIT);
   bool   is_jpy     = (StringFind(_Symbol, "JPY") >= 0);
   PrintFormat("📐 [SYMBOL] %s | digits=%d | _Point=%.6f | pip=%.6f | tick_sz=%.6f | tick_val=%.6f | tick_val_loss=%.6f | contract=%.0f | acc=%s | profit_ccy=%s",
               _Symbol, sym_digits, _Point, pip_sz, tick_sz, tick_val, tick_val_loss, contract_sz, acc_ccy, profit_ccy);
   if(is_jpy && pip_sz < 0.005) {
      PrintFormat("⚠️ [SYMBOL] JPY pair detected but pip size (%.6f) looks too small — check broker digit config (expected ~0.01)", pip_sz);
   }
   if(!is_jpy && pip_sz > 0.01) {
      PrintFormat("⚠️ [SYMBOL] Non-JPY pair but pip size (%.6f) looks too large — check broker digit config", pip_sz);
   }

   FlowLog("Step B: ApplyPreset() (preset overrides -> Settings)");
   ApplyPreset(Inp_Global_Preset, Settings);

   // Safety synchronization: BIAS_4EMA requires phase detection.
   // Prevents silent BIAS=0 behavior if a preset/input regression disables phase.
   if(Settings.BiasMode == BIAS_4EMA && !Settings.PhaseDetectionEnabled)
   {
      Print("WARNING: BIAS_4EMA with PhaseDetectionEnabled=false detected after ApplyPreset.");
      Print("WARNING: Auto-correcting PhaseDetectionEnabled=true to keep Bias/Phase synchronized.");
      Settings.PhaseDetectionEnabled = true;
   }

   FlowLog("Step B1: InitializeIndicatorRegistry() (populate central indicator registry)");
   InitializeIndicatorRegistry(Settings);

   // ═══════════════════════════════════════════════════════════════
   // 🔍 DIAGNOSTIC: Verify exit settings after preset application
   // ═══════════════════════════════════════════════════════════════
   if(Settings.DebugLevel >= DEBUG_SUMMARY || Settings.PrintEffectiveConfig)
   {
      Print("════════════════════════════════════════════════════════════");
      Print("🔍 DIAGNOSTIC: FINAL Exit Management Values");
      Print("   (After InitializeConfig + ApplyPreset)");
      Print("════════════════════════════════════════════════════════════");
      Print("");
      Print("📊 VERIFICATION - Input vs Settings:");
      Print("");

      Print("Exit Profile:");
      PrintFormat("  Input:    %s", EnumToString(Inp_CUSTOM_ExitProfile));
      PrintFormat("  Settings: %s", EnumToString(Settings.ExitProfile));
      PrintFormat("  ✓ Match:  %s", (Settings.ExitProfile == Inp_CUSTOM_ExitProfile) ? "YES ✅" : "NO ❌ BUG DETECTED!");
      Print("");

      Print("Stop Loss Mode:");
      PrintFormat("  Input:    %s", EnumToString(Inp_CUSTOM_SLMode));
      PrintFormat("  Settings: %s", EnumToString(Settings.SLMode));
      PrintFormat("  ✓ Match:  %s", (Settings.SLMode == Inp_CUSTOM_SLMode) ? "YES ✅" : "NO ❌ BUG DETECTED!");
      if(Inp_CUSTOM_SLMode == SL_MODE_PSAR_DOT || Settings.SLMode == SL_MODE_PSAR_DOT)
      {
         PrintFormat("  PSAR Cushion (TF-based): %.1f pips", Settings.SL_PsarPipsCushion);
      }
      Print("");

      Print("Take Profit Mode:");
      PrintFormat("  Input:    %s (RRRatio: %.1f)", EnumToString(Inp_CUSTOM_TPMode), Inp_CUSTOM_RRRatio);
      PrintFormat("  Settings: %s (RRRatio: %.1f)", EnumToString(Settings.TPMode), Settings.RRRatio);
      PrintFormat("  ✓ Match:  %s", (Settings.TPMode == Inp_CUSTOM_TPMode && Settings.RRRatio == Inp_CUSTOM_RRRatio) ? "YES ✅" : "NO ❌ BUG DETECTED!");
      Print("");

      Print("Breakeven Mode:");
      PrintFormat("  RRM Input:    %s", EnumToString(Inp_CUSTOM_BE_Mode));
      PrintFormat("  RRM Settings: %s", EnumToString(Settings.BE_Mode));
      PrintFormat("  ✓ Match:      %s", (Settings.BE_Mode == Inp_CUSTOM_BE_Mode) ? "YES ✅" : "NO ❌ BUG DETECTED!");
      if(Inp_CUSTOM_BE_Mode == BE_MODE_TP_PROGRESS_PCT || Settings.BE_Mode == BE_MODE_TP_PROGRESS_PCT)
      {
         PrintFormat("  Progress%% Input:    %.1f%%", Inp_RRM_BE_ProgressPct);
         PrintFormat("  Progress%% Settings: %.1f%%", Settings.RRM_BE_ProgressPct);
         PrintFormat("  Buffer (TF-based):   %.1f pips", Settings.RRM_BE_BufferPips);
      }
      Print("");

      Print("Trailing Stop Mode:");
      PrintFormat("  Input:    %s", EnumToString(Inp_CUSTOM_TrailMode));
      PrintFormat("  Settings: %s", EnumToString(Settings.TrailMode));
      PrintFormat("  ✓ Match:  %s", (Settings.TrailMode == Inp_CUSTOM_TrailMode) ? "YES ✅" : "NO ❌ BUG DETECTED!");
      if(Inp_CUSTOM_TrailMode == TRAIL_PSAR || Settings.TrailMode == TRAIL_PSAR)
      {
         PrintFormat("  PSAR Cushion (TF-based): %.1f pips", Settings.PSAR_TrailPipsCushion);
         PrintFormat("  PSAR Trail Shift (live):   %d bars", Settings.RRM_TrailPsarShiftDelay);
         PrintFormat("  PSAR Delay (deprecated):   %d bars (mirrors trail shift)", Settings.PSAR_TrailDelay);
         PrintFormat("  RRM StartAfterBE Input:    %s", Inp_RRM_TrailStartsAfterBE ? "true" : "false");
         PrintFormat("  RRM StartAfterBE Settings: %s", Settings.RRM_TrailStartsAfterBE ? "true" : "false");
      }
      Print("");

      Print("════════════════════════════════════════════════════════════");
      Print("🎯 DIAGNOSIS COMPLETE - Check for ❌ above to find bugs");
      Print("════════════════════════════════════════════════════════════");
      Print("");
   }

   // Build UI/Reporting compatibility strings AFTER preset application
   BuildUiReportingState();

   FlowLog("Step C: Validate effective Settings");
   if(!ValidateEffectiveSettings())
      return INIT_FAILED;

   if(Settings.PrintEffectiveConfig)
      PrintEffectiveConfig();

   // Print adaptive configuration summary
   {
      EPairType det = Settings.Adaptive.PairType;
      ENUM_TIMEFRAMES tf = Period();
      Print("═══ ADAPTIVE CONFIGURATION ═══");
      Print("Pair type: ", EnumToString(det),
            " | Max spread: ", DoubleToString(GetAdaptiveSpreadLimit(det, Settings.Adaptive), 1), " pips");
      Print("Timeframe: ", EnumToString(tf));
      Print("SL cushion (TF-based): ", DoubleToString(Settings.SL_PsarPipsCushion, 1), " pips");
      Print("Trail cushion (TF-based): ", DoubleToString(Settings.PSAR_TrailPipsCushion, 1), " pips");
      Print("BE buffer (TF-based): ", DoubleToString(Settings.RRM_BE_BufferPips, 1), " pips");
      Print("═════════════════════════════");
   }

   // Active configuration summary
   {
      Print("════════════════════════════════════════════");
      Print("  SimpleEA v", SEA_BUILD_STR, " - ACTIVE CONFIGURATION");
      Print("  Symbol: ", _Symbol, " | TF: ", EnumToString(_Period));
      Print("  Preset: ", EnumToString(Inp_Global_Preset));
      Print("════════════════════════════════════════════");

      Print("BIAS & PHASE:");
      Print("  BiasMode: ", EnumToString(Settings.BiasMode));
      Print("  PhaseDetectionEnabled: ", (Settings.PhaseDetectionEnabled ? "true" : "false"));
      Print("  MinPhaseConfirmBars: ", Settings.MinPhaseConfirmBars, " (0=instant EMA check)");
      Print("  BlockUnorderedPhase: ", (Settings.BlockUnorderedPhase ? "true" : "false"));
      Print("  BlockEmergingPhase:  ", (Settings.BlockEmergingPhase  ? "true" : "false"));

      Print("ENTRY LAYER:");
      Print("  EnableLayerDetection: ", (Settings.EnableLayerDetection ? "true" : "false"));
      Print("  RequireRecoveryMomentum: ", (Settings.RequireRecoveryMomentum ? "true" : "false"));

      Print("VOTING MODE: ", (Settings.VoteMode == VOTE_MODE_ALL ? "ALL (pure multiplicative)" : "THRESHOLD"));
      int enabled_count = 0;
      if(Settings.Ind_Macd_Enabled)   { Print("  + MACD");   enabled_count++; }
      if(Settings.Ind_Psar_Enabled)   { Print("  + PSAR");   enabled_count++; }
      if(Settings.Ind_Cci_Enabled)    { Print("  + CCI");    enabled_count++; }
      if(Settings.Ind_Rsi_Enabled)    { Print("  + RSI");    enabled_count++; }
      if(Settings.Ind_Adx_Enabled)    { Print("  + ADX");    enabled_count++; }
      if(Settings.Ind_Mfi_Enabled)    { Print("  + MFI");    enabled_count++; }
      if(Settings.Ind_Sto_Enabled)    { Print("  + Stoch");  enabled_count++; }
      if(Settings.Ind_Bb_Enabled)     { Print("  + BB");     enabled_count++; }
      if(Settings.Ind_P123_Enabled)   { Print("  + P123");   enabled_count++; }
      if(Settings.Ind_Ross_Enabled)   { Print("  + Ross");   enabled_count++; }
      Print("  Total: ", enabled_count, " indicators (ALL must pass)");
      Print("════════════════════════════════════════════");
   }

   FlowLog("Step D: Init Signal Engine");
   if(!Signal.Init(Settings, _Symbol))
   {
      Print("ERROR: Signal.Init() failed.");
      return INIT_FAILED;
   }

   if(Inp_UI_ManageChartIndicators)
      SEA_UI_ManageChartIndicators(Signal);
   else
   {
      if(Settings.MABenchmarkStrict)
      {
         int h = Signal.GetPrimaryMAHandle();
         if(h != INVALID_HANDLE)
            ChartIndicatorAdd(0, 0, h);
      }
   }

   FlowLog("Step E: Validate MA setup (method/period/shift)");
   if(!Signal.ValidateAndReportMA(Settings.PrintEffectiveConfig))
   {
      Print("ERROR: MA setup validation failed.");
      return INIT_FAILED;
   }

   FlowLog("Step F: Init Trade Executor");
   Executor.Init(Inp_Global_MagicNum, Settings);

   // BUG FIX: Restore g_consecutive_losses from history on (re-)init so DrawdownProtection
   // is not bypassed after an EA restart (crash, parameter change, broker disconnect, etc.)
   if(Settings.RRM_EnableDrawdownProtection)
   {
      g_consecutive_losses = Executor.GetConsecutiveLossesToday();
      if(Settings.DebugFlow)
         PrintFormat("[RRM_DD_INIT] Restored consecutive losses from history: %d", g_consecutive_losses);
   }

   FlowLog("Step G: Load News calendar (optional)");
    if(Settings.UseNews)
       Signal.LoadNews(Inp_VETO_NewsFile);

   SEA_UI_Init(Inp_Global_MagicNum);
   SEA_UI_UpdateSettingsPanel();
   {
      // Fetch the initial empty state from the Signal Engine
      ST_SignalTelemetry telemetry = Signal.GetTelemetry();
      
      // Push the initial state to the Cockpit (Zero active trade metrics on startup)
      SEA_UI_UpdateCockpit(
         Signal,
         telemetry,
         0.0, // active_lots
         0.0, // initial_risk_money
         0.0, // active_reward_money
         0.0, // initial_sl_pips
         0.0, // current_sl_pips
         0.0, // active_tp_pips
         0.0, // current_rr
         Settings.RiskPercent,
         0.0, // current_risk_pct
         0.0, // current_risk_money
         EnumToString(Settings.TrailMode),
         "",   // last_te_result
         "",   // last_te_veto
         Executor.CooldownBarsRemaining()
      );
   }

   FlowLog("OnInit complete -> INIT_SUCCEEDED");
   ValidateConfiguration();

   // Capture starting balance for end-of-test system analysis report
   g_starting_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   g_peak_equity      = g_starting_balance;

   // BUG FIX: Reset flag so OnTick() re-manages chart indicators after every (re-)init
   g_chart_indicators_managed = false;

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| ORCHESTRATE TICK
//+------------------------------------------------------------------+
void OrchestrateTick()
{
   // 1. Time & Bar Detection
   datetime current_bar = iTime(_Symbol, PERIOD_CURRENT, 0);
   bool     is_new_bar  = (current_bar != g_last_bar_time);

   // 2. Track peak equity and maximum drawdown (every tick)
   double current_equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(current_equity > g_peak_equity) g_peak_equity = current_equity;
   double current_dd = g_peak_equity - current_equity;
   if(current_dd > g_max_drawdown_abs) g_max_drawdown_abs = current_dd;

   // 3. Excursion tracking runs every tick (MAE/MFE price tracking)
   Executor.UpdateExcursionOnly();

   // 4. TE consumption — fires on every tick as soon as a pending TS signal exists,
   //    so TE executes intra-bar rather than waiting for the next new-bar event.
   //    Same-bar re-entry is still prevented by the guards inside ExecuteTrade()
   //    (m_last_trade_bar and m_last_close_bar checks).
   if(g_ts_dir != 0)
   {
      g_last_te_result = "";
      g_last_te_veto   = "";

      bool te_news_blocked = Signal.IsNewsBlocked();
      int te = Executor.EvaluateTE(g_ts_dir, te_news_blocked);

      // Always count trades at ENTRY for accurate daily tracking (used by DrawdownProtection when enabled)
      // FIX Bug5: removed RRM_EnableDrawdownProtection gate so g_trades_today is always accurate for logging
      if(te > 0)
      {
         g_trades_today++;
         // Reset CCI reset-recovery state after trade execution — cycle must start fresh
         Signal.ResetDPIResetState();
      }

      g_ts_sl   = Executor.LastCachedSL();
      g_ts_lots = Executor.LastCachedLots();
      g_ts_risk = Executor.LastCachedRisk();

      g_last_te_result = Executor.LastTEResult();
      g_last_te_veto   = Executor.LastVetoReason();

      PrintFormat("📋 [TE RESULT] dir=%s | te=%d | SL=%.5f | lots=%.2f | risk=%.2f%% | veto=%s",
                  (g_ts_dir > 0 ? "BUY" : "SELL"), te, g_ts_sl, g_ts_lots, g_ts_risk,
                  (g_last_te_veto != "" ? g_last_te_veto : "OK"));

      // ── TE retry logic ──────────────────────────────────────────────────────
      // Track per-bar retry count so we can reset it cleanly on new bars.
      datetime current_bar_time = iTime(_Symbol, PERIOD_CURRENT, 0);
      if(g_te_retry_bar != current_bar_time)
      {
         g_te_retry_bar   = current_bar_time;
         g_te_retry_count = 0;
      }
      g_te_retry_count++;

      // Classify veto: VETO_OPEN_DELAY is temporary (bar will age past the threshold).
      // All other vetoes are permanent for the current bar.
      bool is_temporary_veto = Executor.IsTemporaryVeto(g_last_te_veto);
      bool is_retry_allowed  = (g_te_retry_count < MAX_TE_RETRIES);
      bool should_retry      = (te == 0 && is_temporary_veto && is_retry_allowed);

      if(te > 0)
      {
         // ✅ Trade executed successfully — consume signal and reset retry counter
         int prior_attempts = g_te_retry_count - 1; // attempts before this successful one
         g_ts_dir         = 0;
         g_te_retry_count = 0;
         FlowLog(StringFormat("[TE] Trade executed successfully (retries: %d)", prior_attempts));
      }
      else if(should_retry)
      {
         // ⏳ Temporary veto — keep signal alive so next tick re-attempts TE
         FlowLog(StringFormat("[TE] Retry %d/%d: %s (signal preserved)",
                 g_te_retry_count, MAX_TE_RETRIES, g_last_te_veto));
         // DO NOT consume signal (g_ts_dir remains non-zero)
      }
      else
      {
         // ❌ Permanent veto OR retry limit reached — consume signal
         int failed_attempts = g_te_retry_count - 1; // attempts before this final rejection
         g_ts_dir         = 0;
         g_te_retry_count = 0;

         if(!is_retry_allowed && is_temporary_veto)
            PrintFormat("[TE WARNING] Retry limit exceeded (%d attempts) — signal consumed. Veto: %s",
                        MAX_TE_RETRIES, g_last_te_veto);
         else
            FlowLog(StringFormat("[TE] Signal consumed (permanent veto: %s, retries: %d)",
                    g_last_te_veto, failed_attempts));
      }
      // ───────────────────────────────────────────────────────────────────────
   }

   // 5. New-bar pipeline: runs only once per bar
   if(!is_new_bar) return;

   g_last_bar_time = current_bar;

   // Reset TE retry tracking on new bar so the retry counter is fresh
   // for any signal that fires on this bar.
   g_te_retry_count = 0;
   g_te_retry_bar   = current_bar;

   // 6. TM: Trail/BE modifications — bar-close only
   Executor.SetDPIHistogramState(Signal.GetDPIHistCurrent(), Signal.GetDPIHistTrend(), Signal.GetDPIHistDecelerating(), Signal.GetDPIHistGreenPresent());
   Executor.EvaluateTM();
   Executor.UpdateChartMarkers();

   FlowLog("OnTick -> NewBar detected -> begin bar pipeline");

   // 7. RRM Drawdown Protection Filter
   bool drawdown_blocked = false;
   if(Settings.RRM_EnableDrawdownProtection)
   {
      datetime today = TimeCurrent();
      datetime today_date = today - (today % 86400); 
      
      if(today_date != g_last_trade_date)
      {
         // FIX: Reset ALL daily protection counters — including consecutive losses.
         // Without this, hitting MaxConsecutiveLosses creates a permanent deadlock:
         // no trades → no wins → counter never resets → EA frozen forever.
         if(Settings.DebugFlow && g_consecutive_losses > 0)
            PrintFormat("[RRM_DD_RESET] New day: resetting consecutive_losses from %d → 0", g_consecutive_losses);
         g_trades_today = 0;
         g_consecutive_losses = 0;
         g_last_trade_date = today_date;
         g_daily_starting_balance = AccountInfoDouble(ACCOUNT_BALANCE);
      }
      
      if(Settings.RRM_MaxConsecutiveLosses > 0 && g_consecutive_losses >= Settings.RRM_MaxConsecutiveLosses)
      {
         if(Settings.DebugFlow) PrintFormat("[RRM_DD_PROTECT] Trading PAUSED: %d consecutive losses", g_consecutive_losses);
         drawdown_blocked = true;
      }
      
      if(!drawdown_blocked && Settings.RRM_MaxTradesPerDay > 0 && g_trades_today >= Settings.RRM_MaxTradesPerDay)
      {
         if(Settings.DebugFlow) PrintFormat("[RRM_DD_PROTECT] Trading PAUSED: Daily limit reached (%d/%d)", g_trades_today, Settings.RRM_MaxTradesPerDay);
         drawdown_blocked = true;
      }
      
      if(!drawdown_blocked && Settings.RRM_MaxDailyDrawdownPct > 0.0)
      {
         double current_balance = AccountInfoDouble(ACCOUNT_BALANCE);
         double daily_dd_pct = ((g_daily_starting_balance - current_balance) / g_daily_starting_balance) * 100.0;
         if(daily_dd_pct > Settings.RRM_MaxDailyDrawdownPct)
         {
             if(Settings.DebugFlow) PrintFormat("[RRM_DD_PROTECT] Trading PAUSED: Daily DD %.2f%% exceeds limit", daily_dd_pct);
             drawdown_blocked = true;
         }
      }
   }

   // --- LOCAL DATA HOLDERS ---
   int          snap_bias   = 0;
   int          snap_votes  = 0;
   string       snap_reason = "";
   EMarketPhase snap_phase  = PHASE_UNORDERED;
   SVoteSnapshot vote_snaps[];
   int vote_snap_count = 0;

   // --- STEP 2: TS — evaluate current bar close, store for NEXT bar ---
   if(!drawdown_blocked)
   {
      int ts = Signal.EvaluateTS();

      snap_bias   = Signal.LastBias();
      snap_votes  = Signal.LastVotes();
      snap_reason = Signal.LastReason();
      snap_phase  = Signal.GetLastDetectedPhase();
      Signal.CaptureVoteSnapshots(vote_snaps, vote_snap_count, snap_bias);

      if(ts != 0)
      {
         g_ts_time   = iTime(_Symbol, PERIOD_CURRENT, 1);
         g_ts_dir    = snap_bias;   // Direction from bias (+1 LONG, -1 SHORT), NOT from ts (which is 1/0)
         g_ts_bias   = snap_bias;
         g_ts_votes  = snap_votes;
         g_ts_reason = snap_reason;

         if(Settings.DrawEntryLines)
            SEA_DrawEntrySignalLine(g_ts_time, snap_bias, snap_reason);
      }
      else
      {
         g_ts_dir    = 0;
         g_ts_reason = snap_reason;
         g_ts_votes  = snap_votes;
         g_ts_bias   = snap_bias;
      }

      // Pre-compute SL/lots/risk for cockpit display using the newly stored signal direction
      if(g_ts_dir != 0)
      {
         Executor.EvaluateCM(g_ts_dir);
         g_ts_sl   = Executor.LastCachedSL();
         g_ts_lots = Executor.LastCachedLots();
         g_ts_risk = Executor.LastCachedRisk();
      }
   }
   else
   {
      g_ts_dir = 0;
   }

   // 9. Build Display Snapshots 
   string ts_snap = (g_ts_time > 0) ? StringFormat("TS@%s dir=%s votes=%d reason=%s", 
                     TimeToString(g_ts_time, TIME_DATE|TIME_MINUTES), (g_ts_dir > 0 ? "BUY" : "SELL"), g_ts_votes, g_ts_reason) : "";
   
   string te_snap = (Executor.LastTETime() > 0) ? StringFormat("TE@%s %s%s", 
                     TimeToString(Executor.LastTETime(), TIME_DATE|TIME_MINUTES), Executor.LastTEResult(), 
                     (Executor.LastTEReason() != "" ? ": " + Executor.LastTEReason() : "")) : "";

   // 10. Update Cockpit Panel with Synchronized Data
   ST_SignalTelemetry telemetry = Signal.GetTelemetry();

   double active_lots = 0.0;
   double active_risk_money = 0.0;
   double active_reward_money = 0.0;
   double sl_pips = 0.0;
   double cur_sl_pips = 0.0;
   double tp_pips = 0.0;
   double current_rr = 0.0;
   double current_risk_pct = 0.0;
   double current_risk_money = 0.0;

   if(PositionSelect(_Symbol))
   {
      active_lots         = Executor.GetActiveLots(Inp_Global_MagicNum);
      active_risk_money   = Executor.GetInitialRiskMoney(Inp_Global_MagicNum);
      active_reward_money = Executor.GetActiveRewardMoney(Inp_Global_MagicNum);
      sl_pips             = Executor.GetInitialSLPips(Inp_Global_MagicNum);
      cur_sl_pips         = Executor.GetActiveSLPips(Inp_Global_MagicNum);
      tp_pips             = Executor.GetActiveTPPips(Inp_Global_MagicNum);
      current_rr          = Executor.GetCurrentRR(Inp_Global_MagicNum);
      current_risk_pct    = Executor.GetCurrentRiskPct(Inp_Global_MagicNum);
      current_risk_money  = Executor.GetCurrentRiskMoney(Inp_Global_MagicNum);
   }
   
   SEA_UI_UpdateCockpit(
      Signal,
      telemetry,
      active_lots,
      active_risk_money, 
      active_reward_money, 
      sl_pips, 
      cur_sl_pips,
      tp_pips, 
      current_rr, 
      Settings.RiskPercent,
      current_risk_pct,
      current_risk_money,
      EnumToString(Settings.TrailMode),
      g_last_te_result,
      g_last_te_veto,
      Executor.CooldownBarsRemaining()
   );
   
   FlowLog("Bar pipeline complete");
}


//+------------------------------------------------------------------+
//| SYSTEM ANALYSIS REPORT                                           |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| PRINT TRADE PERFORMANCE
//+------------------------------------------------------------------+
void PrintTradePerformance()
{
   Print("================================================================");
   Print("  TRADE PERFORMANCE");
   Print("================================================================");

   if(!HistorySelect(g_start_time, TimeCurrent()))
   {
      Print("  No trade history available");
      Print("================================================================");
      return;
   }

   int    total_trades = 0, long_trades = 0, short_trades = 0;
   int    wins = 0, losses = 0, long_wins = 0;
   double gross_profit = 0.0, gross_loss = 0.0;
   double largest_win  = 0.0, largest_loss = 0.0;
   int    cur_win_streak = 0, cur_loss_streak = 0;
   int    max_win_streak = 0, max_loss_streak = 0;

   int total_deals = HistoryDealsTotal();
   for(int i = 0; i < total_deals; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;

      // Only count closing deals where P&L is realized
      long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_INOUT) continue;

      long deal_type = HistoryDealGetInteger(ticket, DEAL_TYPE);
      if(deal_type != DEAL_TYPE_BUY && deal_type != DEAL_TYPE_SELL) continue;

      double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT)
                    + HistoryDealGetDouble(ticket, DEAL_SWAP)
                    + HistoryDealGetDouble(ticket, DEAL_COMMISSION);

      total_trades++;

      // A SELL closing deal closes a LONG position; a BUY closing deal closes a SHORT position
      bool is_long = (deal_type == DEAL_TYPE_SELL);
      if(is_long) long_trades++;
      else        short_trades++;

      if(profit > 0.0)
      {
         wins++;
         gross_profit += profit;
         if(is_long) long_wins++;
         if(profit > largest_win) largest_win = profit;
         cur_win_streak++;
         cur_loss_streak = 0;
         if(cur_win_streak > max_win_streak) max_win_streak = cur_win_streak;
      }
      else if(profit < 0.0)
      {
         losses++;
         gross_loss += profit;
         if(profit < largest_loss) largest_loss = profit;
         cur_loss_streak++;
         cur_win_streak = 0;
         if(cur_loss_streak > max_loss_streak) max_loss_streak = cur_loss_streak;
      }
      else
      {
         // Breakeven: reset both streaks
         cur_win_streak  = 0;
         cur_loss_streak = 0;
      }
   }

   if(total_trades == 0)
   {
      Print("  No trades executed during this test");
      Print("================================================================");
      return;
   }

   double win_rate       = wins * 100.0 / total_trades;
   double long_win_rate  = long_trades > 0 ? long_wins * 100.0 / long_trades : 0.0;
   int    short_wins     = wins - long_wins;
   double short_win_rate = short_trades > 0 ? short_wins * 100.0 / short_trades : 0.0;
   double net_profit     = gross_profit + gross_loss;
   // Profit factor: N/A when no losing trades (all winners); shown as "N/A" separately
   bool   has_losses     = (gross_loss != 0.0);
   double profit_factor  = has_losses ? gross_profit / MathAbs(gross_loss) : 0.0;
   double avg_trade      = net_profit / total_trades;
   double avg_win        = wins   > 0 ? gross_profit / wins   : 0.0;
   double avg_loss       = losses > 0 ? gross_loss   / losses : 0.0;

   PrintFormat("Total Trades         : %d", total_trades);
   PrintFormat("  ├─ Long            : %d (%.1f%%)", long_trades,
               long_trades * 100.0 / total_trades);
   PrintFormat("  └─ Short           : %d (%.1f%%)", short_trades,
               short_trades * 100.0 / total_trades);
   Print("");
   PrintFormat("Win Rate             : %.1f%% (%dW / %dL)", win_rate, wins, losses);
   PrintFormat("  ├─ Long win rate   : %.1f%% (%d/%d)", long_win_rate, long_wins, long_trades);
   PrintFormat("  └─ Short win rate  : %.1f%% (%d/%d)", short_win_rate, short_wins, short_trades);
   Print("");
   if(has_losses) PrintFormat("Profit Factor        : %.2f",  profit_factor);
   else            Print("Profit Factor        : N/A (no losing trades)");
   PrintFormat("  ├─ Gross profit    : $%.2f", gross_profit);
   PrintFormat("  └─ Gross loss      : $%.2f", gross_loss);
   Print("");
   PrintFormat("Average Trade        : $%.2f", avg_trade);
   PrintFormat("  ├─ Average win     : $%.2f", avg_win);
   PrintFormat("  └─ Average loss    : $%.2f", avg_loss);
   Print("");
   PrintFormat("Best Trade           : $%.2f", largest_win);
   PrintFormat("Worst Trade          : $%.2f", largest_loss);
   Print("");
   PrintFormat("Consecutive Wins     : %d (max)", max_win_streak);
   PrintFormat("Consecutive Losses   : %d (max)", max_loss_streak);
   Print("================================================================");
}

//+------------------------------------------------------------------+
//| CALCULATE SHARPE RATIO
//+------------------------------------------------------------------+
// Uses sample standard deviation and a risk-free rate of 0% (standard for backtesting).
// Returns 0.0 when fewer than 2 trades or zero standard deviation.
double CalculateSharpeRatio(const double& returns[], int count, double risk_free_rate = 0.0)
{
   // Clamp count to actual array size to prevent out-of-bounds access
   int array_size = ArraySize(returns);
   if(count > array_size) count = array_size;
   if(count < 2) return 0.0;

   // Mean return
   double sum = 0.0;
   for(int i = 0; i < count; i++)
      sum += returns[i];
   double mean_return = sum / count;

   // Sample standard deviation (divides by count-1 for unbiased estimate)
   double variance_sum = 0.0;
   for(int i = 0; i < count; i++)
   {
      double deviation = returns[i] - mean_return;
      variance_sum += deviation * deviation;
   }
   double std_dev = MathSqrt(variance_sum / (count - 1));

   if(std_dev == 0.0) return 0.0;

   return (mean_return - risk_free_rate) / std_dev;
}

//+------------------------------------------------------------------+
//| PRINT RISK ANALYSIS
//+------------------------------------------------------------------+
void PrintRiskAnalysis()
{
   Print("================================================================");
   Print("  RISK ANALYSIS");
   Print("================================================================");

   bool   in_tester  = (bool)MQLInfoInteger(MQL_TESTER);
   double start_bal  = in_tester ? TesterStatistics(STAT_INITIAL_DEPOSIT) : g_starting_balance;
   double end_bal    = AccountInfoDouble(ACCOUNT_BALANCE);
   double net_profit = end_bal - start_bal;
   double net_pct    = (start_bal > 0.0) ? net_profit * 100.0 / start_bal : 0.0;

   // Use tester-computed drawdown when available; fall back to our tick tracker
   double dd_abs = 0.0, dd_pct = 0.0;
   if(in_tester)
   {
      dd_abs = TesterStatistics(STAT_BALANCE_DD);
      dd_pct = TesterStatistics(STAT_BALANCE_DDREL_PERCENT);
   }
   else
   {
      dd_abs = g_max_drawdown_abs;
      // Use peak equity (not starting balance) as the denominator for accuracy
      dd_pct = (g_peak_equity > 0.0) ? dd_abs * 100.0 / g_peak_equity : 0.0;
   }

   // Recovery factor: net profit / max drawdown
   double recovery_factor = (dd_abs > 0.0) ? net_profit / dd_abs : 0.0;

   // Risk-reward: avg win / |avg loss| — query closing deals from history
   double avg_win = 0.0, avg_loss = 0.0;
   if(HistorySelect(g_start_time, TimeCurrent()))
   {
      double gross_profit = 0.0, gross_loss = 0.0;
      int    wins = 0, losses = 0;
      int    total_deals = HistoryDealsTotal();
      for(int i = 0; i < total_deals; i++)
      {
         ulong ticket = HistoryDealGetTicket(i);
         if(ticket == 0) continue;
         long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
         if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_INOUT) continue;
         long dt = HistoryDealGetInteger(ticket, DEAL_TYPE);
         if(dt != DEAL_TYPE_BUY && dt != DEAL_TYPE_SELL) continue;
         double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT)
                       + HistoryDealGetDouble(ticket, DEAL_SWAP)
                       + HistoryDealGetDouble(ticket, DEAL_COMMISSION);
         if(profit > 0.0) { gross_profit += profit; wins++; }
         else if(profit < 0.0) { gross_loss += profit; losses++; }
      }
      avg_win  = (wins   > 0) ? gross_profit / wins   : 0.0;
      avg_loss = (losses > 0) ? gross_loss   / losses : 0.0;
   }
   double rr_ratio = (avg_loss != 0.0) ? avg_win / MathAbs(avg_loss) : 0.0;

   PrintFormat("Starting Balance     : $%.2f", start_bal);
   PrintFormat("Ending Balance       : $%.2f", end_bal);
   PrintFormat("Net Profit           : $%.2f (%+.2f%%)", net_profit, net_pct);
   Print("");
   PrintFormat("Maximum Drawdown     : %.1f%% ($%.2f)", dd_pct, dd_abs);
   PrintFormat("  ├─ Absolute        : $%.2f", dd_abs);
   PrintFormat("  └─ Relative        : %.1f%%", dd_pct);
   Print("");
   PrintFormat("Recovery Factor      : %.2f (Net Profit / Max DD)", recovery_factor);
   PrintFormat("Risk-Reward Ratio    : %.2f (Avg Win / Avg Loss)", rr_ratio);

   // Sharpe Ratio: (mean trade return - risk-free rate) / std dev of trade returns
   if(g_trade_return_count < 2)
   {
      PrintFormat("Sharpe Ratio         : N/A (need >= 2 trades, have %d)", g_trade_return_count);
   }
   else
   {
      double sharpe = CalculateSharpeRatio(g_trade_returns, g_trade_return_count);
      PrintFormat("Sharpe Ratio         : %.2f", sharpe);
      string sharpe_rating = "";
      if(sharpe > 2.0)       sharpe_rating = "Excellent";
      else if(sharpe > 1.0)  sharpe_rating = "Good";
      else if(sharpe > 0.5)  sharpe_rating = "Fair";
      else if(sharpe > 0.0)  sharpe_rating = "Poor";
      else                   sharpe_rating = "Losing";
      PrintFormat("  └─ Rating          : %s", sharpe_rating);
   }

   Print("================================================================");
}

//+------------------------------------------------------------------+
//| PRINT SIGNAL EFFICIENCY - dynamic
//+------------------------------------------------------------------+
void PrintSignalEfficiency()
{
   Print("================================================================");
   Print("  SIGNAL EFFICIENCY ANALYSIS");
   Print("================================================================");

   // const SRejectionStats& st = Signal.GetStats();  // ❌ WRONG   
   SRejectionStats st = Signal.GetStats();  // ✅ CORRECT
   
   if(st.total_bars == 0)
   {
      Print("  No bars evaluated");
      Print("================================================================");
      return;
   }

   int    total_bars       = st.total_bars;
   int    sigs_confirmed   = st.signals_confirmed;
   int    sigs_rejected    = total_bars - sigs_confirmed;
   double signal_rate      = sigs_confirmed * 100.0 / total_bars;
   double avg_bars_between = (sigs_confirmed > 0) ? total_bars * 1.0 / sigs_confirmed : 0.0;

   // Count closed trades from history for conversion rate
   int total_trades = 0;
   if(HistorySelect(g_start_time, TimeCurrent()))
   {
      int total_deals = HistoryDealsTotal();
      for(int i = 0; i < total_deals; i++)
      {
         ulong ticket = HistoryDealGetTicket(i);
         if(ticket == 0) continue;
         long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
         if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_INOUT) continue;
         long dt = HistoryDealGetInteger(ticket, DEAL_TYPE);
         if(dt == DEAL_TYPE_BUY || dt == DEAL_TYPE_SELL) total_trades++;
      }
   }

   double conversion_rate = (sigs_confirmed > 0) ? total_trades * 100.0 / sigs_confirmed : 0.0;
   int    filtered_out    = sigs_confirmed - total_trades;

   Print("Signal Generation");
   PrintFormat("  ├─ Total bars evaluated    : %d",         total_bars);
   PrintFormat("  ├─ Signals confirmed       : %d (%.2f%%)", sigs_confirmed, signal_rate);
   PrintFormat("  ├─ Signals rejected        : %d (%.2f%%)", sigs_rejected, 100.0 - signal_rate);
   PrintFormat("  └─ Avg bars between signals: %.1f bars",  avg_bars_between);
   Print("");
   Print("Signal-to-Trade Conversion");
   PrintFormat("  ├─ Signals confirmed       : %d",         sigs_confirmed);
   PrintFormat("  ├─ Trades executed         : %d (%.1f%% conversion)", total_trades, conversion_rate);
   PrintFormat("  └─ Signals filtered out    : %d (%.1f%%)", filtered_out,
               sigs_confirmed > 0 ? filtered_out * 100.0 / sigs_confirmed : 0.0);
   Print("");

   // ── Component Efficiency ──
   // Shows each enabled indicator's pass rate relative to bias-confirmed bars.
   // DYNAMIC: only enabled indicators appear (controlled by Settings flags).
   Print("Component Efficiency (Pass Rate Among Bias-Confirmed Bars)");
   int    bias_passed = st.passed_bias;
   double bias_rate   = bias_passed * 100.0 / total_bars;
   PrintFormat("  ├─ Bias detection          : %.1f%% (%d / %d bars)",
               bias_rate, bias_passed, total_bars);
   Print("  └─ When bias ≠ 0:");

   // Build a list of enabled indicators with their pass counts
   // Array size = total supported indicator slots (14: MACD, PSAR, CCI, RSI, ADX, MFI, Sto, BB, P123, Ross, CandleBody, CI, VRC, ATR)
   struct SIndEntry { string name; int passed; };
   SIndEntry inds[14];
   int ind_count = 0;

   if(Settings.Ind_Macd_Enabled)
      { inds[ind_count].name = "MACD";       inds[ind_count++].passed = st.passed_macd; }
   if(Settings.Ind_Psar_Enabled)
      { inds[ind_count].name = "PSAR";       inds[ind_count++].passed = st.passed_psar; }
   if(Settings.Ind_Cci_Enabled)
      { inds[ind_count].name = "CCI";        inds[ind_count++].passed = st.passed_cci; }
   if(Settings.Ind_Rsi_Enabled)
      { inds[ind_count].name = "RSI";        inds[ind_count++].passed = st.passed_rsi; }
   if(Settings.Ind_Adx_Enabled)
      { inds[ind_count].name = "ADX";        inds[ind_count++].passed = st.passed_adx; }
   if(Settings.Ind_Mfi_Enabled)
      { inds[ind_count].name = "MFI";        inds[ind_count++].passed = st.passed_mfi; }
   if(Settings.Ind_Sto_Enabled)
      { inds[ind_count].name = "Stochastic"; inds[ind_count++].passed = st.passed_sto; }
   if(Settings.Ind_Bb_Enabled)
      { inds[ind_count].name = "BB";         inds[ind_count++].passed = st.passed_bb; }
   if(Settings.Ind_P123_Enabled)
      { inds[ind_count].name = "P123";       inds[ind_count++].passed = st.passed_p123; }
   if(Settings.Ind_Ross_Enabled)
      { inds[ind_count].name = "Ross Hook";  inds[ind_count++].passed = st.passed_ross; }
   if(Settings.Ind_CandleBody_Enabled)
      { inds[ind_count].name = "CandleBody"; inds[ind_count++].passed = st.passed_candle_body; }
   if(Settings.Ind_CI_Enabled)
      { inds[ind_count].name = "CI";         inds[ind_count++].passed = st.passed_ci; }
   if(Settings.Ind_VRC_Enabled)
      { inds[ind_count].name = "VRC";        inds[ind_count++].passed = st.passed_vrc; }
   if(Settings.Ind_Atr_Enabled)
      { inds[ind_count].name = "ATR";        inds[ind_count++].passed = st.passed_atr; }

   if(ind_count == 0)
      Print("      └─ (no indicators enabled)");
   else
   {
      for(int i = 0; i < ind_count; i++)
      {
         double rate   = (bias_passed > 0) ? inds[i].passed * 100.0 / bias_passed : 0.0;
         string branch = (i < ind_count - 1) ? "      ├─ " : "      └─ ";
         PrintFormat("%s%-12s : %.1f%% (%d / %d)", branch,
                     inds[i].name, rate, inds[i].passed, bias_passed);
      }
   }
   Print("");
   PrintFormat("Combined Efficiency          : %.1f%% (signals / total bars)", signal_rate);
   Print("================================================================");
}

//+------------------------------------------------------------------+
//| PRINT SYSTEM ANALYSIS - wrapper
//+------------------------------------------------------------------+
void PrintSystemAnalysisReport()
{
   PrintTradePerformance();
   Print("");
   PrintRiskAnalysis();
   Print("");
   PrintSignalEfficiency();
}

//+------------------------------------------------------------------+
//| ORCHESTRATE DEINIT
//+------------------------------------------------------------------+
void OrchestrateDeinit(const int reason)
{
   // ── PHASE A.1: Bridge TE-side counters from Executor into Signal.m_stats
   //              before reporting, so the new "1b. PRE-FILTER QUALITY GATES"
   //              section shows correct TE Open Delay / BC Recheck / Spread
   //              Median rejection counts. Must run BEFORE any Print* calls.
   Signal.AddTeStats(
      Executor.RejOpenDelay(),  Executor.RejBCRecheck(),  Executor.RejSpreadMedian(),
      Executor.PassOpenDelay(), Executor.PassBCRecheck(), Executor.PassSpreadMedian()
   );
   Signal.AddDPIExitStats(Executor.ExitsDpiHist());

   Signal.PrintRejectionStatistics();
   Signal.PrintEnhancedStatistics();
   PrintSystemAnalysisReport();

   if(Settings.ExportCSV)
      SEA_Report_Generate();

   Executor.RemoveAllMarkers();
   SEA_UI_DestroyAll();
   FlowLog(StringFormat("EA stop -> OnDeinit(reason=%d)", reason));

   Signal.Release();
   g_last_bar_time     = 0;

   FlowLog("OnDeinit complete");
}

//+------------------------------------------------------------------+
//| UI: SIGNAL MARKERS
//+------------------------------------------------------------------+
void SEA_DrawEntrySignalLine(datetime bar_time, int direction, const string label)
{
   string name = StringFormat("SEA_ELIG_%I64d_%s", (long)bar_time, (direction > 0 ? "BUY" : "SELL"));
   if(ObjectFind(0, name) >= 0) return;

   ObjectCreate(0, name, OBJ_VLINE, 0, bar_time, 0);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DOT);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetString(0, name, OBJPROP_TOOLTIP, StringFormat("ELIGIBLE %s | %s", (direction > 0 ? "BUY" : "SELL"), label));
}
void SEA_DrawTradeExecLine(datetime event_time, int direction, double price, const string label)
{
   string name = StringFormat("SEA_TRADE_%I64d_%s", (long)event_time, (direction > 0 ? "BUY" : "SELL"));
   if(ObjectFind(0, name) >= 0) return;

   ObjectCreate(0, name, OBJ_VLINE, 0, event_time, 0);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
   ObjectSetString(0, name, OBJPROP_TOOLTIP, StringFormat("EXECUTED %s @%.5f | %s", (direction > 0 ? "BUY" : "SELL"), price, label));
}

//+------------------------------------------------------------------+
//| END OF FILE                                                      |
//+------------------------------------------------------------------+
