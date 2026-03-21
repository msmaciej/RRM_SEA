//+------------------------------------------------------------------+
//|                                           SimpleEA_v1-03-001.mq5 |
//| Institutional Trading Solutions RRMS Simple Rapid Results Method |
//+------------------------------------------------------------------+
// SAVE AS UTF-16 LE WITH BOM
//+------------------------------------------------------------------+
#property copyright "SimpleEA_v1.03"
#property version   "103.001"
#property strict

// --- Anti-stale build lock
#define SEA_BUILD_TOKEN_103001 1

#define SEA_BUILD_NUM 103001
#define SEA_BUILD_STR "1.03.001"

//+------------------------------------------------------------------+
//| FORWARD DECLARATIONS                                             |
//+------------------------------------------------------------------+

void SEA_DrawEntrySignalLine(datetime bar_time, int direction, const string label);
void SEA_DrawTradeExecLine(datetime event_time, int direction, double price, const string label);
void SEA_UI_ManageChartIndicators();

//+------------------------------------------------------------------+
//| MODULE INCLUDES                                                  |
//+------------------------------------------------------------------+

#include <RRMS\SEA_Config.mqh>
#include <RRMS\SEA_Presets.mqh>
#include <RRMS\SEA_SignalEngine.mqh>
#include <RRMS\SEA_TradeExecutor.mqh>
#include <RRMS\SEA_UI.mqh>
#include <RRMS\SEA_Reporting.mqh>

#ifndef SEA_MOD_SIGNALENGINE_103001
enum { __SEA_STALE_SEA_MOD_SIGNALENGINE_103001__ = SEA_MOD_SIGNALENGINE_103001 };
#endif
#ifndef SEA_MOD_TRADEEXEC_103001
enum { __SEA_STALE_SEA_MOD_TRADEEXEC_103001__ = SEA_MOD_TRADEEXEC_103001 };
#endif
#ifndef SEA_MOD_UI_103001
enum { __SEA_STALE_SEA_MOD_UI_103001__ = SEA_MOD_UI_103001 };
#endif
#ifndef SEA_MOD_REPORTING_103001
enum { __SEA_STALE_SEA_MOD_REPORTING_103001__ = SEA_MOD_REPORTING_103001 };
#endif

//+------------------------------------------------------------------+
//| GLOBAL STATE & MODULE OBJECTS                                    |
//+------------------------------------------------------------------+

CSignalEngine  Signal;
CTradeExecutor Executor;

// --- UI/Reporting compatibility globals (previously built in old presets logic)
EEmaStrategy g_effectiveEmaStrategy = EMA_STRAT_1_PRICE_CROSS;
EMaMethod    g_effectiveMaType      = METHOD_EMA;
EBiasMode    g_effectiveBiasMode    = BIAS_AUTO;
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

int OnInit() { return OrchestrateInit(); }

void OnTick()
{
   if(Inp_UI_ManageChartIndicators && !g_chart_indicators_managed)
   {
      SEA_UI_ManageChartIndicators();
      g_chart_indicators_managed = true;
   }
   OrchestrateTick();
}

void OnDeinit(const int reason) { OrchestrateDeinit(reason); }

// ✅ ADD THIS NEW HANDLER HERE (after OnDeinit, before helpers section)
void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& request,
                        const MqlTradeResult& result)
{
   Print("OnTradeTransaction fired: type=", EnumToString(trans.type)); // ✅ Test

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
      if(deal_magic != Inp_MagicNum) return;  // Not our trade
      
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
   if(Inp_DebugFlow && Inp_DebugLevel >= DEBUG_FULL) Print("FLOW: ", msg);
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
      if(Settings.AutoStrat == STRAT_PRICE_CROSS && Settings.BiasFastID == 0 && Settings.BiasSlowID == 0)
         g_effectiveEmaStrategy = EMA_STRAT_1_PRICE_CROSS;
      else if(Settings.AutoStrat == STRAT_PAIR_CROSS && Settings.BiasFastID == 0 && Settings.BiasSlowID == 1)
         g_effectiveEmaStrategy = EMA_STRAT_2_CROSS_1_2;
      else if(Settings.AutoStrat == STRAT_PAIR_CROSS && Settings.BiasFastID == 2 && Settings.BiasSlowID == 3)
         g_effectiveEmaStrategy = EMA_STRAT_2_CROSS_3_4;
      else
         g_effectiveEmaStrategy = EMA_STRAT_CUSTOM;
   }

   g_ui_ma_source = (InpPreset == PRESET_MA_BENCHMARK ? "BENCHMARK" : "CUSTOM");

   if(InpPreset == PRESET_CUSTOM)
   {
      g_ui_used_flags    = "CUSTOM";
      g_ui_ignored_flags = "";
      g_ui_overrides     = "";
   }
   else
   {
      g_ui_used_flags    = "PRESET=" + PresetToString(InpPreset);
      g_ui_ignored_flags = "Strategy inputs ignored (preset authoritative)";
      g_ui_overrides     = "Preset overwrote strategy-critical fields";
      g_effectiveSigNote = "Preset is active; strategy inputs ignored.";
   }
}

//+------------------------------------------------------------------+
//| PrintEffectiveConfig(): single init snapshot                      |
//+------------------------------------------------------------------+
void PrintEffectiveConfig()
{
   Print("------------------------------------------");
   Print("--- SimpleEA v", SEA_BUILD_STR, " Configuration ---");
   Print("Program: ", MQLInfoString(MQL_PROGRAM_NAME), " | Path: ", MQLInfoString(MQL_PROGRAM_PATH));
   Print("Symbol: ", _Symbol, " | Magic: ", Inp_MagicNum);
   Print("Preset: ", EnumToString(InpPreset), " (", (int)InpPreset, ")");

   if(InpPreset != PRESET_CUSTOM)
   {
      Print("Preset ", PresetToString(InpPreset), " is active; strategy inputs ignored");
      if(Settings.AdminOverridePreset)
         Print("AdminOverride: ACTIVE [Admin Mode] - override inputs are applied on top of preset");
      else
         Print("AdminOverride: OFF [Normal User Mode] - preset is fully enforced");
   }

   Print("Diagnostics: PrintEffectiveConfig=", (Settings.PrintEffectiveConfig ? "true" : "false"),
         " DebugFlow=", (Settings.DebugFlow ? "true" : "false"),
         " DebugLevel=", EnumToString(Settings.DebugLevel));

   Print("UI: StatusPanel=", (Settings.UI_ShowStatusPanel ? "true" : "false"),
         " CockpitPanel=", (Settings.UI_ShowCockpitPanel ? "true" : "false"),
         " ManageChartIndicators=", (Settings.UI_ManageChartIndicators ? "true" : "false"),
         " DrawEntryLines=", (Settings.DrawEntryLines ? "true" : "false"),
         " DrawTradeLines=", (Settings.DrawTradeLines ? "true" : "false"));

   Print("Reporting: ExportCSV=", (Settings.ExportCSV ? "true" : "false"),
         " ExportUseCommonFiles=", (Settings.ExportUseCommonFiles ? "true" : "false"));

   Print("Effective: CloseOnReverse=", (Settings.CloseOnReverse ? "true" : "false"),
         " Risk%=", DoubleToString(Settings.RiskPercent, 2),
         " MaxSpreadPips=", DoubleToString(Settings.MaxSpread, 2),
         " ATR[min,max]=[", DoubleToString(Settings.MinATR, 2), ",", DoubleToString(Settings.MaxATR, 2), "]");

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


   if(Settings.ExitProfile != EXIT_PROFILE_LEGACY || InpPreset == PRESET_RRM)
   {
      Print("Effective: ExitProfile=", EnumToString(Settings.ExitProfile),
            " TP_Enabled=", (Settings.TP_Enabled ? "true" : "false"),
            " TP_Mult=", DoubleToString(Settings.TP_Mult, 2),
            " BE_Mode=", EnumToString(Settings.BE_Mode));
      Print("Effective: RRM_BE_ProgressPct=", DoubleToString(Settings.RRM_BE_ProgressPct, 1),
            " RRM_BE_BufferPips=", DoubleToString(Settings.RRM_BE_BufferPips, 1),
            " TrailPsarShiftDelay=", Settings.RRM_TrailPsarShiftDelay,
            " FreezeTrailOnFlip=", (Settings.RRM_FreezeTrailOnFlip ? "true" : "false"),
            " TrailStartsAfterBE=", (Settings.RRM_TrailStartsAfterBE ? "true" : "false"));
   }

   Print("------------------------------------------");
}

//+------------------------------------------------------------------+
//| ValidateEffectiveSettings(): minimal safety checks (post-preset)  |
//+------------------------------------------------------------------+
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
   if(!Settings.RRM_EnableDrawdownProtection) return;
   
   g_trades_today++;  // Increment daily trade counter
   
   if(was_profitable)
      g_consecutive_losses = 0;  // Reset on win
   else
      g_consecutive_losses++;    // Increment on loss
}

// Call this from your OnTrade() handler when a position closes:
// UpdateRRMDrawdownTracking(profit > 0);

//+------------------------------------------------------------------+
//| INIT                                                             |
//+------------------------------------------------------------------+

void ValidateConfiguration()
{
   Print("════════════════════════════════════════════════");
   Print("  CONFIGURATION VALIDATION");
   Print("════════════════════════════════════════════════");

   bool has_warnings = false;

   // Warn if preset + admin override both active
   if(InpPreset != PRESET_CUSTOM && Settings.AdminOverridePreset) {
      Print("WARNING: Preset=", EnumToString(InpPreset), " but AdminOverride=true");
      Print("   Admin settings will OVERRIDE preset values");
      has_warnings = true;
   }

   // Warn if phase detection enabled but BiasMode is not AUTO_PHASE
   if(Settings.PhaseDetectionEnabled && Settings.BiasMode != BIAS_AUTO_PHASE) {
      Print("WARNING: PhaseDetection=true but BiasMode != AUTO_PHASE");
      Print("   Phase detection only works with BIAS_AUTO_PHASE");
      has_warnings = true;
   }

   // Warn if layer detection enabled but phase detection is off
   if(Settings.EnableLayerDetection && !Settings.PhaseDetectionEnabled) {
      Print("WARNING: LayerDetection=true but PhaseDetection=false");
      Print("   Layer filtering has no effect without phase detection");
      has_warnings = true;
   }

   // Count enabled indicators
   int enabled = 0;
   if(Settings.Ind_EmaSig_Enabled) enabled++;
   if(Settings.Ind_Macd_Enabled)   enabled++;
   if(Settings.Ind_Psar_Enabled)   enabled++;
   if(Settings.Ind_Cci_Enabled)    enabled++;
   if(Settings.Ind_Rsi_Enabled)    enabled++;
   if(Settings.Ind_Adx_Enabled)    enabled++;
   if(Settings.Ind_Mfi_Enabled)    enabled++;
   if(Settings.Ind_Sto_Enabled)    enabled++;
   if(Settings.Ind_Bb_Enabled)     enabled++;
   if(Settings.Ind_P123_Enabled)   enabled++;
   if(Settings.Ind_Ross_Enabled)   enabled++;

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

int OrchestrateInit()
{
   FlowLog("EA start -> OnInit()");
   g_start_time = TimeCurrent();

   FlowLog("Step A: InitializeConfig() (inputs -> Settings)");
   InitializeConfig();

   FlowLog("Step B: ApplyPreset() (preset overrides -> Settings)");
   ApplyPreset(InpPreset, Settings);

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
      PrintFormat("  Input:    %s", EnumToString(Inp_ExitProfile));
      PrintFormat("  Settings: %s", EnumToString(Settings.ExitProfile));
      PrintFormat("  ✓ Match:  %s", (Settings.ExitProfile == Inp_ExitProfile) ? "YES ✅" : "NO ❌ BUG DETECTED!");
      Print("");

      Print("Stop Loss Mode:");
      PrintFormat("  Input:    %s", EnumToString(Inp_SLMode));
      PrintFormat("  Settings: %s", EnumToString(Settings.SLMode));
      PrintFormat("  ✓ Match:  %s", (Settings.SLMode == Inp_SLMode) ? "YES ✅" : "NO ❌ BUG DETECTED!");
      if(Inp_SLMode == SL_PSAR_DOT || Settings.SLMode == SL_PSAR_DOT)
      {
         PrintFormat("  PSAR Cushion Input:    %.1f pips", Inp_SL_PsarPipsCushion);
         PrintFormat("  PSAR Cushion Settings: %.1f pips", Settings.SL_PsarPipsCushion);
      }
      Print("");

      Print("Take Profit Mode:");
      PrintFormat("  Input:    %s (Mult: %.1f)", EnumToString(Inp_TPMode), Inp_TP_Mult);
      PrintFormat("  Settings: %s (Mult: %.1f)", EnumToString(Settings.TPMode), Settings.TP_Mult);
      PrintFormat("  ✓ Match:  %s", (Settings.TPMode == Inp_TPMode && Settings.TP_Mult == Inp_TP_Mult) ? "YES ✅" : "NO ❌ BUG DETECTED!");
      Print("");

      Print("Breakeven Mode:");
      PrintFormat("  RRM Input:    %s", EnumToString(Inp_BE_Mode));
      PrintFormat("  RRM Settings: %s", EnumToString(Settings.BE_Mode));
      PrintFormat("  ✓ Match:      %s", (Settings.BE_Mode == Inp_BE_Mode) ? "YES ✅" : "NO ❌ BUG DETECTED!");
      if(Inp_BE_Mode == BE_MODE_TP_PROGRESS_PCT || Settings.BE_Mode == BE_MODE_TP_PROGRESS_PCT)
      {
         PrintFormat("  Progress%% Input:    %.1f%%", Inp_RRM_BE_ProgressPct);
         PrintFormat("  Progress%% Settings: %.1f%%", Settings.RRM_BE_ProgressPct);
         PrintFormat("  Buffer Input:        %.1f pips", Inp_RRM_BE_BufferPips);
         PrintFormat("  Buffer Settings:     %.1f pips", Settings.RRM_BE_BufferPips);
      }
      PrintFormat("  LEGACY Input:    Use_BE=%s, Trig=%.1f, Buff=%.1f", Inp_Use_BE ? "true" : "false", Inp_BE_Trig, Inp_BE_Buff);
      PrintFormat("  LEGACY Settings: Use_BE=%s, Trig=%.1f, Buff=%.1f", Settings.Use_BE ? "true" : "false", Settings.BE_Trig, Settings.BE_Buff);
      Print("");

      Print("Trailing Stop Mode:");
      PrintFormat("  Input:    %s", EnumToString(Inp_TrailMode));
      PrintFormat("  Settings: %s", EnumToString(Settings.TrailMode));
      PrintFormat("  ✓ Match:  %s", (Settings.TrailMode == Inp_TrailMode) ? "YES ✅" : "NO ❌ BUG DETECTED!");
      if(Inp_TrailMode == TRAIL_PSAR || Settings.TrailMode == TRAIL_PSAR)
      {
         PrintFormat("  PSAR Cushion Input:    %.1f pips", Inp_PSAR_TrailPipsCushion);
         PrintFormat("  PSAR Cushion Settings: %.1f pips", Settings.PSAR_TrailPipsCushion);
         PrintFormat("  PSAR Delay Input:      %d bars", Inp_PSAR_TrailDelay);
         PrintFormat("  PSAR Delay Settings:   %d bars", Settings.PSAR_TrailDelay);
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
      Print("Timeframe: ", EnumToString(tf),
            " | TF multiplier: ", DoubleToString(GetTimeframeMultiplier(tf), 2), "x");
      Print("ATR gate: min=", DoubleToString(Settings.MinATR, 1),
            " max=", DoubleToString(Settings.MaxATR, 1), " pips");
      if(Settings.Adaptive.UseSL)
         Print("Adaptive SL: ", DoubleToString(GetAdaptiveSL(tf, Settings.Adaptive), 1), " pips");
      if(Settings.Adaptive.UseTP)
         Print("Adaptive TP: ", DoubleToString(GetAdaptiveTP(tf, Settings.Adaptive), 1), " pips");
      if(Settings.Adaptive.UseTrailCushion)
         Print("Adaptive trail cushion: ", DoubleToString(GetAdaptiveTrailCushion(tf, Settings.Adaptive), 1), " pips");
      Print("═════════════════════════════");
   }

   // Active configuration summary
   {
      Print("════════════════════════════════════════════");
      Print("  SimpleEA v", SEA_BUILD_STR, " - ACTIVE CONFIGURATION");
      Print("  Symbol: ", _Symbol, " | TF: ", EnumToString(_Period));
      Print("  Preset: ", EnumToString(InpPreset));
      if(Settings.AdminOverridePreset)
         Print("  ADMIN OVERRIDE ACTIVE");
      Print("════════════════════════════════════════════");

      Print("BIAS & PHASE:");
      Print("  BiasMode: ", EnumToString(Settings.BiasMode));
      Print("  PhaseDetectionEnabled: ", (Settings.PhaseDetectionEnabled ? "true" : "false"));
      Print("  MinPhaseConfirmBars: ", Settings.MinPhaseConfirmBars, " (0=instant EMA check)");
      Print("  BlockUnorderedPhase: ", (Settings.BlockUnorderedPhase ? "true" : "false"));

      Print("ENTRY LAYER:");
      Print("  EnableLayerDetection: ", (Settings.EnableLayerDetection ? "true" : "false"));
      Print("  LayerTouchTolerance: ", DoubleToString(Settings.LayerTouchTolerance * 100.0, 1), "%");
      Print("  RequireRecoveryMomentum: ", (Settings.RequireRecoveryMomentum ? "true" : "false"));

      Print("VOTING MODE: ", (Settings.VoteMode == VOTE_MODE_ALL ? "ALL (pure multiplicative)" : "THRESHOLD"));
      int enabled_count = 0;
      if(Settings.Ind_EmaSig_Enabled) { Print("  + EmaSig"); enabled_count++; }
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
      SEA_UI_ManageChartIndicators();
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
   Executor.Init(Inp_MagicNum, Settings);

   FlowLog("Step G: Load News calendar (optional)");
   if(Settings.UseNews)
      Signal.LoadNews(Inp_NewsFile);

   SEA_UI_Init(Inp_MagicNum);
   SEA_UI_UpdateSettingsPanel();
   {
      SVoteSnapshot init_snaps[];
      int init_snap_count = 0;
      SEA_UI_UpdateCockpitPanel(Signal.GetATR(), 0, Signal.LastBias(), Signal.LastVotes(), Signal.LastReason(), "", "", init_snaps, init_snap_count);
   }

   FlowLog("OnInit complete -> INIT_SUCCEEDED");
   ValidateConfiguration();

   // Capture starting balance for end-of-test system analysis report
   g_starting_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   g_peak_equity      = g_starting_balance;

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| TICK                                                             |
//+------------------------------------------------------------------+

void OrchestrateTick()
{
   datetime current_bar = iTime(_Symbol, PERIOD_CURRENT, 0);
   bool     is_new_bar  = (current_bar != g_last_bar_time);

   // ═══════════════════════════════════════════════════════════════
   // Track peak equity and maximum drawdown (every tick, for report)
   // ═══════════════════════════════════════════════════════════════
   double current_equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(current_equity > g_peak_equity) g_peak_equity = current_equity;
   double current_dd = g_peak_equity - current_equity;
   if(current_dd > g_max_drawdown_abs) g_max_drawdown_abs = current_dd;

   // ═══════════════════════════════════════════════════════════════
   // TM: Trade Management (every tick)
   // ═══════════════════════════════════════════════════════════════
   Executor.EvaluateTM();

   // ═══════════════════════════════════════════════════════════════
   // New-bar pipeline: runs only once per bar
   // ═══════════════════════════════════════════════════════════════
   if(!is_new_bar)
      return;

   g_last_bar_time = current_bar;
   FlowLog("OnTick -> NewBar detected -> begin bar pipeline");

   // ═══════════════════════════════════════════════════════════════
   // RRM Drawdown Protection Filter (§6)
   // ═══════════════════════════════════════════════════════════════
   bool drawdown_blocked = false;
   if(Settings.RRM_EnableDrawdownProtection)
   {
      // Reset daily counters on new trading day
      datetime today = TimeCurrent();
      datetime today_date = today - (today % 86400);  // Strip time component
      
      if(today_date != g_last_trade_date)
      {
         g_trades_today = 0;
         g_last_trade_date = today_date;
         g_daily_starting_balance = AccountInfoDouble(ACCOUNT_BALANCE);
      }
      
      // Check 1: Max consecutive losses
      if(Settings.RRM_MaxConsecutiveLosses > 0 && 
         g_consecutive_losses >= Settings.RRM_MaxConsecutiveLosses)
      {
         if(Settings.DebugFlow)
            PrintFormat("[RRM_DD_PROTECT] Trading PAUSED: %d consecutive losses (max=%d)",
                        g_consecutive_losses, Settings.RRM_MaxConsecutiveLosses);
         drawdown_blocked = true;
      }
      
      // Check 2: Max trades per day
      if(!drawdown_blocked && Settings.RRM_MaxTradesPerDay > 0 && 
         g_trades_today >= Settings.RRM_MaxTradesPerDay)
      {
         if(Settings.DebugFlow)
            PrintFormat("[RRM_DD_PROTECT] Trading PAUSED: Daily trade limit reached (%d/%d)",
                        g_trades_today, Settings.RRM_MaxTradesPerDay);
         drawdown_blocked = true;
      }
      
      // Check 3: Daily drawdown protection
      if(!drawdown_blocked && Settings.RRM_MaxDailyDrawdownPct > 0.0)
      {
         double current_balance = AccountInfoDouble(ACCOUNT_BALANCE);
         double daily_dd_pct = ((g_daily_starting_balance - current_balance) / g_daily_starting_balance) * 100.0;
         
         if(daily_dd_pct > Settings.RRM_MaxDailyDrawdownPct)
         {
            if(Settings.DebugFlow)
               PrintFormat("[RRM_DD_PROTECT] Trading PAUSED: Daily DD %.2f%% exceeds limit %.2f%%",
                           daily_dd_pct, Settings.RRM_MaxDailyDrawdownPct);
            drawdown_blocked = true;
         }
      }
   }

   // ═══════════════════════════════════════════════════════════════
   // TS: Trade Setup evaluation on bar close (shift=1)
   // TE: Trade Entry evaluation immediately on the same new bar
   //
   // EvaluateTS() evaluates ALL pipeline steps (bias, filters, voting)
   // on the CLOSED bar (shift=1 via Vote_EvalShift=1) and returns a
   // direction if a valid TS is found.  EvaluateTE() then checks live
   // conditions (spread, time, risk) and executes if all pass.
   // ═══════════════════════════════════════════════════════════════
   if(!drawdown_blocked)
   {
      FlowLog("Step B: Compute direction signal (TS evaluation at shift=1)");
      if(Settings.DebugFlow)
         Print("[DEBUG_TEST] About to call Signal.EvaluateTS()");
      int ts = Signal.EvaluateTS();
      if(Settings.DebugFlow)
         PrintFormat("[DEBUG_TEST] Signal.EvaluateTS() returned: %d", ts);

      // Capture TS display snapshot
      if(ts != 0)
      {
         g_ts_time   = iTime(_Symbol, PERIOD_CURRENT, 1);
         g_ts_dir    = ts;
         g_ts_bias   = Signal.LastBias();
         g_ts_votes  = Signal.LastVotes();
         g_ts_reason = Signal.LastReason();

         if(Settings.DebugFlow)
            PrintFormat("[PIPELINE] TS=%d confirmed at %s | %s | Evaluating entry...",
                        ts, TimeToString(g_ts_time, TIME_DATE|TIME_MINUTES),
                        (ts > 0 ? "BUY" : "SELL"));

         if(Settings.DrawEntryLines)
            SEA_DrawEntrySignalLine(g_ts_time, ts, Signal.LastReason());

         // TE: Evaluate Trade Entry
         int te = Executor.EvaluateTE(ts);

         if(Settings.DebugFlow)
         {
            if(te == 1) Print("[PIPELINE] ✅ Trade entered");
            else        Print("[PIPELINE] ❌ Entry rejected");
         }
      }
      else
      {
         if(Settings.DebugFlow)
            Print("[PIPELINE] TS=0, no setup. Reason: ", Signal.LastReason(),
                  " | Bias: ", Signal.LastBias(),
                  " | Votes: ", Signal.LastVotes());
      }

      FlowLog(StringFormat("Step B done: TS=%d", ts));
   }

   // Build TS/TE snapshot strings for cockpit display
   string ts_snap = "";
   if(g_ts_time > 0)
   {
      string dir_str = (g_ts_dir > 0 ? "BUY" : "SELL");
      ts_snap = StringFormat("TS@%s dir=%s votes=%d reason=%s",
         TimeToString(g_ts_time, TIME_DATE|TIME_MINUTES), dir_str, g_ts_votes, g_ts_reason);
   }
   string te_snap = "";
   if(Executor.LastTETime() > 0)
   {
      string te_reason = Executor.LastTEReason();
      te_snap = StringFormat("TE@%s %s%s",
         TimeToString(Executor.LastTETime(), TIME_DATE|TIME_MINUTES),
         Executor.LastTEResult(),
         (te_reason != "" ? ": " + te_reason : ""));
      if(Settings.DebugFlow)
         Print("TE: ", te_snap);
   }

   // Capture current vote states for cockpit display
   int   snap_bias   = Signal.LastBias();
   int   snap_votes  = Signal.LastVotes();
   string snap_reason = Signal.LastReason();
   SVoteSnapshot vote_snaps[];
   int vote_snap_count = 0;
   Signal.CaptureVoteSnapshots(vote_snaps, vote_snap_count, snap_bias);

   // Build pipeline diagnostics string (EMA values, structure gate, statistics)
   string diag_snap = Signal.GetDiagnosticsString();

   SEA_UI_UpdateCockpitPanel(Signal.GetATR(), (drawdown_blocked ? 0 : g_ts_dir),
                             snap_bias, snap_votes, snap_reason,
                             ts_snap, te_snap, vote_snaps, vote_snap_count, diag_snap);
   FlowLog("Bar pipeline complete");
}

//+------------------------------------------------------------------+
//| SYSTEM ANALYSIS REPORT                                           |
//+------------------------------------------------------------------+

// Prints Trade Performance section: totals, win rate, profit factor,
// average trade, best/worst, consecutive streaks.
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

// Calculates the Sharpe Ratio from an array of per-trade % returns.
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

// Prints Risk Analysis section: starting/ending balance, net profit,
// max drawdown, recovery factor, and risk-reward ratio.
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

// Prints Signal Efficiency section: signal generation rate,
// signal-to-trade conversion, and per-indicator component efficiency.
// Component Efficiency is DYNAMIC — only enabled indicators are listed.
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
   // Array size = total supported indicator slots (11: EmaSig,MACD,PSAR,CCI,RSI,ADX,MFI,Sto,BB,P123,Ross)
   struct SIndEntry { string name; int passed; };
   SIndEntry inds[11];
   int ind_count = 0;

   if(Settings.Ind_EmaSig_Enabled)
      { inds[ind_count].name = "EmaSig";     inds[ind_count++].passed = st.passed_emasig; }
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

// Wrapper: prints the full System Analysis Report (Trade Performance +
// Risk Analysis + Signal Efficiency) at end of test.
void PrintSystemAnalysisReport()
{
   PrintTradePerformance();
   Print("");
   PrintRiskAnalysis();
   Print("");
   PrintSignalEfficiency();
}

//+------------------------------------------------------------------+
//| DEINIT                                                           |
//+------------------------------------------------------------------+

void OrchestrateDeinit(const int reason)
{
   Signal.PrintRejectionStatistics();
   Signal.PrintEnhancedStatistics();
   PrintSystemAnalysisReport();

   if(Settings.ExportCSV)
      SEA_Report_Generate();

   SEA_UI_DestroyAll();
   FlowLog(StringFormat("EA stop -> OnDeinit(reason=%d)", reason));

   Signal.Release();
   g_last_bar_time     = 0;

   FlowLog("OnDeinit complete");
}

void SEA_UI_ManageChartIndicators()
{
   // =====================================================================
   // UNIVERSAL CHART INDICATOR MANAGER
   // Shows ALL indicators involved in Trade Signal (TS) evaluation
   //
   // ARCHITECTURE:
   // 1. Bias determination (EMAs)
   // 2. TS evaluation on shift=1: ALL enabled indicators must pass
   // 3. TE execution on shift=0: if TS=1 confirmed
   // =====================================================================

   // 1) Clear all existing indicators from all windows
   int win_total = (int)ChartGetInteger(0, CHART_WINDOWS_TOTAL);
   for(int w=win_total-1; w>=0; w--)
   {
      int total = ChartIndicatorsTotal(0, w);
      while(total > 0)
      {
         string nm = ChartIndicatorName(0, w, 0);
         if(nm == "") break;
         ChartIndicatorDelete(0, w, nm);
         total = ChartIndicatorsTotal(0, w);
      }
   }

   Print("═══════════════════════════════════════════════════════════");
   Print("UI: Chart Indicator Manager - Rebuilding from Settings...");
   Print("  → Vote Mode: ", (Settings.VoteMode == VOTE_MODE_ALL ? "ALL (all enabled must pass)" : "THRESHOLD"));
   Print("═══════════════════════════════════════════════════════════");

   // ========================
   // 2) MAIN CHART OVERLAYS
   // ========================

   int overlays_added = 0;
   int ts_components_visible = 0; // TS voting components on chart

   // --- Benchmark MA (PRESET_MA_BENCHMARK mode)
   if(Settings.MABenchmarkStrict)
   {
      int h = Signal.GetPrimaryMAHandle();
      if(h != INVALID_HANDLE)
      {
         ChartIndicatorAdd(0, 0, h);
         overlays_added++;
         Print("  ✓ Benchmark MA (bias determination)");
      }
   }

   // --- EMAs (bias determination + optional TS component)
   bool need_ema[4];
   need_ema[0] = (Settings.BiasFastID == 0 || Settings.BiasSlowID == 0 || Settings.Ind_EmaSig_Enabled);
   need_ema[1] = (Settings.BiasFastID == 1 || Settings.BiasSlowID == 1);
   need_ema[2] = (Settings.BiasFastID == 2 || Settings.BiasSlowID == 2);
   need_ema[3] = (Settings.BiasFastID == 3 || Settings.BiasSlowID == 3);

   for(int i=0; i<4; i++)
   {
      if(need_ema[i])
      {
         int h = Signal.GetEmaHandle(i);
         if(h != INVALID_HANDLE)
         {
            ChartIndicatorAdd(0, 0, h);
            overlays_added++;

            string role = "bias";
            if(i == 0 && Settings.Ind_EmaSig_Enabled)
            {
               role = "bias + TS component";
               ts_components_visible++;
            }

            Print("  ✓ EMA", (i+1), " (", Settings.P_Ema1 + i*8, ") [", role, "]");
         }
      }
   }

   // --- PSAR (TS component + optional trailing)
   if(Settings.Ind_Psar_Enabled ||
      Settings.TrailMode == TRAIL_PSAR)
   {
      int h = Signal.GetPsarHandle();
      if(h != INVALID_HANDLE)
      {
         ChartIndicatorAdd(0, 0, h);
         overlays_added++;

         string role = "";
         if(Settings.Ind_Psar_Enabled)
         {
            role = "TS component";
            ts_components_visible++;
         }
         if(Settings.TrailMode == TRAIL_PSAR)
         {
            if(role != "") role += " + ";
            role += "trailing";
         }

         Print("  ✓ PSAR [", role, "]");
      }
      else
      {
         Print("  ⚠ PSAR enabled but handle not available");
      }
   }

   // --- Bollinger Bands (TS component)
   if(Settings.Ind_Bb_Enabled)
   {
      int h = Signal.GetBbHandle();
      if(h != INVALID_HANDLE)
      {
         ChartIndicatorAdd(0, 0, h);
         overlays_added++;
         ts_components_visible++;
         Print("  ✓ Bollinger Bands [TS component]");
      }
      else
      {
         Print("  ⚠ Bollinger Bands enabled but GetBbHandle() not available");
      }
   }

   // --- HTF EMA (filter/gate - NOT a TS component)
   if(Settings.UseHTF)
   {
      int h = Signal.GetHtfEmaHandle();
      if(h != INVALID_HANDLE)
      {
         ChartIndicatorAdd(0, 0, h);
         overlays_added++;
         Print("  ✓ HTF EMA (", EnumToString(Settings.HtfPeriod), "/", Settings.P_HtfEma, ") [filter gate]");
      }
      else
      {
         Print("  ⚠ HTF filter enabled but GetHtfEmaHandle() not available");
      }
   }

   // --- Fractals (structure + optional trailing)
   if(Settings.TrailMode == TRAIL_FRACTAL)
   {
      int h = Signal.GetFractalHandle();
      if(h != INVALID_HANDLE)
      {
         ChartIndicatorAdd(0, 0, h);
         overlays_added++;
         Print("  ✓ Fractals [trailing]");
      }
      else
      {
         Print("  ⚠ Fractals needed but GetFractalHandle() not available");
      }
   }

   // --- Pattern 123 (TS component)
   if(Settings.Ind_P123_Enabled)
   {
      int h = Signal.GetP123Handle();
      if(h != INVALID_HANDLE)
      {
         ChartIndicatorAdd(0, 0, h);
         overlays_added++;
         ts_components_visible++;
         Print("  ✓ Pattern 123 [TS component]");
      }
      else
      {
         Print("  ⚠ Pattern 123 enabled but GetP123Handle() not available");
      }
   }

   // --- Ross Hook (TS component)
   if(Settings.Ind_Ross_Enabled)
   {
      int h = Signal.GetRossHandle();
      if(h != INVALID_HANDLE)
      {
         ChartIndicatorAdd(0, 0, h);
         overlays_added++;
         ts_components_visible++;
         Print("  ✓ Ross Hook [TS component]");
      }
      else
      {
         Print("  ⚠ Ross Hook enabled but GetRossHandle() not available");
      }
   }

   // ========================
   // 3) SUBWINDOW INDICATORS
   // (ALL are TS components)
   // ========================

   int subwindow = 1;
   int subwindows_added = 0;

   // --- MACD (TS component)
   if(Settings.Ind_Macd_Enabled)
   {
      int h = Signal.GetMacdHandle();
      if(h != INVALID_HANDLE)
      {
         if(ChartIndicatorAdd(0, subwindow, h))
         {
            Print("  ✓ MACD (", Settings.P_MacdFast, "/", Settings.P_MacdSlow, "/", Settings.P_MacdSig, ") [TS component, subwindow ", subwindow, "]");
            subwindow++;
            subwindows_added++;
            ts_components_visible++;
         }
      }
      else
      {
         Print("  ⚠ MACD enabled but handle not available");
      }
   }

   // --- RSI (TS component)
   if(Settings.Ind_Rsi_Enabled)
   {
      int h = Signal.GetRsiHandle();
      if(h != INVALID_HANDLE)
      {
         if(ChartIndicatorAdd(0, subwindow, h))
         {
            Print("  ✓ RSI (", Settings.P_Rsi, ") [TS component, subwindow ", subwindow, "]");
            subwindow++;
            subwindows_added++;
            ts_components_visible++;
         }
      }
      else
      {
         Print("  ⚠ RSI enabled but GetRsiHandle() not available");
      }
   }

   // --- CCI (TS component)
   if(Settings.Ind_Cci_Enabled)
   {
      int h = Signal.GetCciHandle();
      if(h != INVALID_HANDLE)
      {
         if(ChartIndicatorAdd(0, subwindow, h))
         {
            Print("  ✓ CCI (", Settings.P_Cci, ") [TS component, subwindow ", subwindow, "]");
            subwindow++;
            subwindows_added++;
            ts_components_visible++;
         }
      }
      else
      {
         Print("  ⚠ CCI enabled but GetCciHandle() not available");
      }
   }

   // --- MFI (TS component)
   if(Settings.Ind_Mfi_Enabled)
   {
      int h = Signal.GetMfiHandle();
      if(h != INVALID_HANDLE)
      {
         if(ChartIndicatorAdd(0, subwindow, h))
         {
            Print("  ✓ MFI (", Settings.P_Mfi, ") [TS component, subwindow ", subwindow, "]");
            subwindow++;
            subwindows_added++;
            ts_components_visible++;
         }
      }
      else
      {
         Print("  ⚠ MFI enabled but GetMfiHandle() not available");
      }
   }

   // --- Stochastic (TS component)
   if(Settings.Ind_Sto_Enabled)
   {
      int h = Signal.GetStoHandle();
      if(h != INVALID_HANDLE)
      {
         if(ChartIndicatorAdd(0, subwindow, h))
         {
            Print("  ✓ Stochastic (K:", Settings.P_StoK, " D:", Settings.P_StoD, " Slow:", Settings.P_StoSlow, ") [TS component, subwindow ", subwindow, "]");
            subwindow++;
            subwindows_added++;
            ts_components_visible++;
         }
      }
      else
      {
         Print("  ⚠ Stochastic enabled but GetStoHandle() not available");
      }
   }

   // --- ADX (TS component)
   if(Settings.Ind_Adx_Enabled)
   {
      int h = Signal.GetAdxHandle();
      if(h != INVALID_HANDLE)
      {
         if(ChartIndicatorAdd(0, subwindow, h))
         {
            Print("  ✓ ADX (", Settings.P_Adx, ") [TS component, subwindow ", subwindow, "]");
            subwindow++;
            subwindows_added++;
            ts_components_visible++;
         }
      }
      else
      {
         Print("  ⚠ ADX enabled but GetAdxHandle() not available");
      }
   }

   // ========================
   // 4) SUMMARY
   // ========================

   Print("───────────────────────────────────────────────────────────");
   Print("UI: Chart indicator management complete");
   Print("  → ", overlays_added, " overlays on main chart");
   Print("  → ", subwindows_added, " indicators in subwindows");
   Print("  → ", ts_components_visible, " TS components visible");
   Print("  → Vote Mode: ", (Settings.VoteMode == VOTE_MODE_ALL ? "ALL" : "THRESHOLD"), " (", ts_components_visible, " indicators visible)");
   Print("═══════════════════════════════════════════════════════════");
}

//+------------------------------------------------------------------+
//| UI: SIGNAL MARKERS                                               |
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