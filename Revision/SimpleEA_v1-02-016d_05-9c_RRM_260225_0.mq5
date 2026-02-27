//+------------------------------------------------------------------+
//|                                 SimpleEA_v1-02-016d_05-9_RRM.mq5 |
//|                              MJS Institutional Trading Solutions |
//+------------------------------------------------------------------+
// SAVE AS UTF-16 LE WITH BOM
//+------------------------------------------------------------------+
#property copyright "SimpleEA v1.02.016d-05-9_RRM"
#property version   "102.016"
#property strict

// --- Anti-stale build lock
#define SEA_BUILD_TOKEN_102016D 1

#define SEA_BUILD_NUM 1020168
#define SEA_BUILD_STR "1.02.016d-05-9_RRM"

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

#ifndef SEA_MOD_SIGNALENGINE_102016D
enum { __SEA_STALE_SEA_MOD_SIGNALENGINE_102016D__ = SEA_MOD_SIGNALENGINE_102016D };
#endif
#ifndef SEA_MOD_TRADEEXEC_102016D
enum { __SEA_STALE_SEA_MOD_TRADEEXEC_102016D__ = SEA_MOD_TRADEEXEC_102016D };
#endif
#ifndef SEA_MOD_UI_102016D
enum { __SEA_STALE_SEA_MOD_UI_102016D__ = SEA_MOD_UI_102016D };
#endif
#ifndef SEA_MOD_REPORTING_102016D
enum { __SEA_STALE_SEA_MOD_REPORTING_102016D__ = SEA_MOD_REPORTING_102016D };
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

//+------------------------------------------------------------------+
//| HELPERS                                                          |
//+------------------------------------------------------------------+

void FlowLog(const string msg)
{
   if(Inp_DebugFlow) Print("FLOW: ", msg);
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
      Print("Preset ", PresetToString(InpPreset), " is active; strategy inputs ignored");

   Print("Diagnostics: PrintEffectiveConfig=", (Settings.PrintEffectiveConfig ? "true" : "false"),
         " DebugFlow=", (Settings.DebugFlow ? "true" : "false"));

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

   if(Settings.VoteThreshold < 1)
   {
      Print("ERROR: VoteThreshold must be >= 1 (got ", Settings.VoteThreshold, ")");
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| INIT                                                             |
//+------------------------------------------------------------------+

int OrchestrateInit()
{
   FlowLog("EA start -> OnInit()");
   g_start_time = TimeCurrent();

   FlowLog("Step A: InitializeConfig() (inputs -> Settings)");
   InitializeConfig();

   FlowLog("Step B: ApplyPreset() (preset overrides -> Settings)");
   ApplyPreset(InpPreset, Settings);

   // Build UI/Reporting compatibility strings AFTER preset application
   BuildUiReportingState();

   FlowLog("Step C: Validate effective Settings");
   if(!ValidateEffectiveSettings())
      return INIT_FAILED;

   if(Settings.PrintEffectiveConfig)
      PrintEffectiveConfig();

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
   SEA_UI_UpdateCockpitPanel(Signal.GetATR(), 0, Signal.LastBias(), Signal.LastVotes(), Signal.LastReason());

   FlowLog("OnInit complete -> INIT_SUCCEEDED");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| TICK                                                             |
//+------------------------------------------------------------------+

void OrchestrateTick()
{
   datetime t = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(t == g_last_bar_time)
      return;

   g_last_bar_time = t;
   FlowLog("OnTick -> NewBar detected -> begin bar pipeline");

   double atr = Signal.GetATR();

   FlowLog("Step A: Manage open positions (Trailing/BE)");
   Executor.ManageTrade(atr);

   FlowLog("Step B: Compute direction signal");
   int direction = Signal.GetDirection();

   if(Settings.DebugFlow)
   {
      if(direction == 0)
      {
         Print("DEBUG: No signal. Reason: ", Signal.LastReason(), " | Bias: ", Signal.LastBias(),
               " | Votes: ", Signal.LastVotes(), "/", Settings.VoteThreshold);
      }
      else
      {
         Print("DEBUG: SIGNAL GENERATED! Direction: ", direction, " | Bias: ", Signal.LastBias(),
               " | Votes: ", Signal.LastVotes(), "/", Settings.VoteThreshold,
               " | Reason: ", Signal.LastReason());
      }
   }

   if(Settings.DrawEntryLines && direction != 0)
      SEA_DrawEntrySignalLine(iTime(_Symbol, PERIOD_CURRENT, 1), direction, Signal.LastReason());

   FlowLog(StringFormat("Step C: ProcessSignal (direction=%d)", direction));
   if(direction != 0)
      Executor.ProcessSignal(direction, atr);

   SEA_UI_UpdateCockpitPanel(atr, direction, Signal.LastBias(), Signal.LastVotes(), Signal.LastReason());
   FlowLog("Bar pipeline complete");
}

//+------------------------------------------------------------------+
//| DEINIT                                                           |
//+------------------------------------------------------------------+

void OrchestrateDeinit(const int reason)
{
   if(Settings.ExportCSV)
      SEA_Report_Generate();

   SEA_UI_DestroyAll();
   FlowLog(StringFormat("EA stop -> OnDeinit(reason=%d)", reason));

   Signal.Release();
   g_last_bar_time = 0;

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
   // 2. TS evaluation on shift=1: VoteCount >= VoteThreshold
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
   Print("  → Vote Threshold: ", Settings.VoteThreshold);
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
   need_ema[0] = (Settings.BiasFastID == 0 || Settings.BiasSlowID == 0 || Settings.Use_EmaSig);
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
            if(i == 0 && Settings.Use_EmaSig)
            {
               role = "bias + TS component";
               ts_components_visible++;
            }

            Print("  ✓ EMA", (i+1), " (", Settings.P_Ema1 + i*8, ") [", role, "]");
         }
      }
   }

   // --- PSAR (TS component + optional trailing)
   if(Settings.Use_Psar ||
      Settings.TrailMode == TRAIL_PSAR)
   {
      int h = Signal.GetPsarHandle();
      if(h != INVALID_HANDLE)
      {
         ChartIndicatorAdd(0, 0, h);
         overlays_added++;

         string role = "";
         if(Settings.Use_Psar)
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
   if(Settings.Use_Bb)
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
   if(Settings.Use_P123)
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
   if(Settings.Use_Ross)
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
   if(Settings.Use_Macd)
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
   if(Settings.Use_Rsi)
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
   if(Settings.Use_Cci)
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
   if(Settings.Use_Mfi)
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
   if(Settings.Use_Sto)
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
   if(Settings.Use_Adx)
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
   Print("  → Vote Threshold: ", Settings.VoteThreshold, " (need ", Settings.VoteThreshold, "/", ts_components_visible, " to trigger TS=1)");
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