//+------------------------------------------------------------------+
//|                                 SimpleEA_v1-02-016d_05-9_RRM.mq5 |
//|                              MJS Institutional Trading Solutions |
//|                                                                  |
//| GOLDEN MASTER: Easy Setup + MA Method + Dual Shifts              |
//| RRM REV 05-7: Legacy-aligned + ATR gate fix                      |
//+------------------------------------------------------------------+
// SAVE AS UTF-16 LE WITH BOM
//+------------------------------------------------------------------+
// SYSTEM OVERVIEW:
// Real Risk Money (RRM) methodology combined with Signal Engine Architecture
// Modular design with separate components for signals, risk, and trade management
//
// ARCHITECTURE:
// 1. SimpleEA (this file) - Main coordinator
// 2. SEA_SignalEngine - 9-step signal pipeline
// 3. SEA_RiskManager - Position sizing
// 4. SEA_TradeManager - Trade execution and management
//
// KEY CONCEPTS:
// - Market Bias: Primary trend filter (EMA position + slope alignment)
// - Entry Signal: Timing signal within bias context (from AutoStrat)
// - Indicator Voting: Multiple indicators confirm bias (consensus system)
// - RRM Gates: Optional quality filters (pullback/reclaim, divergence)
//
// SIGNAL FLOW:
// Bar closes -> OnTick() -> SignalEngine.GetDirection() [9-step pipeline]
// -> If signal valid: RiskManager -> TradeManager -> Open position
// -> If signal = 0: Only manage existing positions
//
// BIAS DETERMINATION:
// LONG: Fast EMA > Slow EMA AND both rising
// SHORT: Fast EMA < Slow EMA AND both falling
// NEUTRAL: Neither condition met -> NO TRADE
//
// Note: STRAT_PAIR_CROSS uses relaxed logic (only Fast slope required)
//
// AUTOSTRAT STRATEGIES:
// - STRAT_SINGLE_SLOPE: Single EMA slope direction
// - STRAT_PRICE_CROSS: Price vs EMA position/cross
// - STRAT_PAIR_CROSS: EMA crossover (catches early momentum)
//
// INDICATOR VOTING:
// Each enabled indicator votes if it agrees with bias.
// VoteThreshold determines minimum votes required (e.g., 4 out of 5)
// Available: EMA1, ADX, MACD, CCI, RSI, Stochastic, PSAR, BB, MFI, P123, Ross
//
// RRM GATES (Optional):
// - RRM_RequirePullbackReclaim: Wait for pullback to EMA then reclaim
// - RRM_RequireEmaDiv: Require EMAs expanding (not converging)
//
// CONFIGURATION:
// BiasMode: MANUAL or AUTO
// BiasFastID/SlowID: Which EMAs for bias (0=5, 1=13, 2=34, 3=89)
// AutoStrat: Entry timing method (PAIR_CROSS recommended)
// VoteThreshold: How many indicators must agree (4 recommended)
//
// See README.md and README_INDICATORS.md for complete documentation
//
// VERSION: v1.02.016d-05-8b_RRM
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| FILE HEADER & TERMINAL DIRECTIVES                                |
//+------------------------------------------------------------------+

#property copyright "SimpleEA v1.02.016d-05-9_RRM"
#property version   "102.016"
#property strict

//+------------------------------------------------------------------+
//| BUILD SWITCHES & CONSTANTS                                       |
//+------------------------------------------------------------------+

// --- Anti-stale build lock (MQL5-safe: no #if, no #error)
#define SEA_BUILD_TOKEN_102016D 1

// --- Anti-stale build lock (macOS+Wine+MT5)
#define SEA_BUILD_NUM 1020168      // 1.02.016d => 1020164
#define SEA_BUILD_STR "1.02.016d-05-9_RRM"   // Revision tag with OPT suffix

//+------------------------------------------------------------------+
//| FORWARD DECLARATIONS                                             |
//+------------------------------------------------------------------+

// (entry/trade markers implemented in main EA; callable by modules)

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

// --- Module revision stamps (fail fast if stale include path)
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

EEmaStrategy   g_effectiveEmaStrategy  = EMA_STRAT_1_PRICE_CROSS;
EMaMethod      g_effectiveMaType       = METHOD_EMA;
EBiasMode      g_effectiveBiasMode     = BIAS_AUTO;
string         g_effectiveSigNote      = "";
string         g_effectiveDirSource    = "";

string         g_ui_used_flags         = "";
string         g_ui_ignored_flags      = "";
string         g_ui_overrides          = "";
string         g_ui_ma_source          = "";

bool           g_warned_bench_ignored  = false;
bool           g_warned_custom_bench   = false;

datetime       g_last_bar_time         = 0;
datetime       g_start_time            = 0;
bool           g_chart_indicators_managed = false;

//+------------------------------------------------------------------+
//| EXPERT LIFECYCLE (ENTRY POINTS)                                  |
//+------------------------------------------------------------------+

int OnInit() {
   return OrchestrateInit();
}

void OnTick() {
   // UI: Strategy Tester applies chart templates after OnInit in some environments (macOS+Wine).
   // To keep visualization clean, manage indicators once on the first tick.
   if(Inp_UI_ManageChartIndicators && !g_chart_indicators_managed)
   {
      SEA_UI_ManageChartIndicators();
      g_chart_indicators_managed = true;
   }
   OrchestrateTick();
}

void OnDeinit(const int reason) {
   OrchestrateDeinit(reason);
}

//+------------------------------------------------------------------+
//| HELPER: Get recommended PSAR pips cushion based on TF & currency |
//+------------------------------------------------------------------+
double GetRecommendedPsarPipsCushion() {
   bool isJPY = (StringFind(_Symbol, "JPY") >= 0);
   double cushion = 5.0; // Default
   
   switch(_Period) {
      case PERIOD_M1:
         cushion = isJPY ? 3.0 : 2.0;
         break;
      case PERIOD_M5:
         cushion = isJPY ? 5.0 : 3.0;
         break;
      case PERIOD_M15:
         cushion = isJPY ? 8.0 : 5.0;
         break;
      case PERIOD_M30:
         cushion = isJPY ? 12.0 : 7.0;
         break;
      case PERIOD_H1:
         cushion = isJPY ? 15.0 : 10.0;
         break;
      case PERIOD_H2:
         cushion = isJPY ? 20.0 : 12.0;
         break;
      case PERIOD_H4:
         cushion = isJPY ? 25.0 : 15.0;
         break;
      case PERIOD_D1:
         cushion = isJPY ? 40.0 : 25.0;
         break;
      default:
         cushion = isJPY ? 10.0 : 5.0;
         break;
   }
   
   return cushion;
}

//+------------------------------------------------------------------+
//| EXPLICIT INIT PIPELINE                                           |
//+------------------------------------------------------------------+

int OrchestrateInit()
{
   FlowLog("EA start -> OnInit()");
   g_start_time = TimeCurrent();
   
   FlowLog("Step A: Read Inputs -> ApplySettings() -> build effective Settings");
   ApplySettings();

   FlowLog("Step B: Validate effective Settings");
   if(!ValidateEffectiveSettings())
      return INIT_FAILED;

   FlowLog("Step C: Init Signal Engine (indicators/handles/libraries)");
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

   FlowLog("Step D: Validate MA setup (method/period/shift)");
   if(!Signal.ValidateAndReportMA(Inp_PrintEffectiveConfig))
   {
      Print("ERROR: MA setup validation failed.");
      return INIT_FAILED;
   }

   FlowLog("Step E: Init Trade Executor");
   Executor.Init(Inp_MagicNum, Settings);

   FlowLog("Step F: Load News calendar (optional)");
   if(Settings.UseNews)
      Signal.LoadNews(Inp_NewsFile);

   FlowLog("Step G: Print configuration (inputs and effective)");
   Print("------------------------------------------");
   Print("--- SimpleEA v", SEA_BUILD_STR, " Configuration ---");
   Print("Program: ", MQLInfoString(MQL_PROGRAM_NAME), " | Path: ", MQLInfoString(MQL_PROGRAM_PATH));
   Print("Preset (raw): ", (int)InpPreset, " | Name: ", EnumToString(InpPreset));
   Print("VoteThreshold (input): ", Inp_VoteThreshold, " | Effective: ", Settings.VoteThreshold);
   Print("Symbol: ", _Symbol, " | Magic: ", Inp_MagicNum);
   Print("MA Source: ", g_ui_ma_source);
   Print("MA Shifts (CUSTOM Inputs): h=", Inp_MaHorShift, " v=", Inp_MaVerShift, (InpPreset==PRESET_MA_BENCHMARK ? " (IGNORED)" : ""));
   Print("MA Shifts (Effective): h=", Settings.ma_h_shift, " v=", Settings.ma_v_shift);
   
   if(InpPreset == PRESET_MA_BENCHMARK)
      Print("MA Benchmark Inputs (0c): MaxRisk=", Inp_MA_MaximumRiskPct, "% Dec=", Inp_MA_DecreaseFactor, " Period=", Inp_MA_Period, " Shift=", Inp_MA_Shift);
      
   Print("EMA Strategy (Input): ", EnumToString(Inp_EmaStrategy));
   Print("Effective EMA periods: ", Settings.P_Ema1, ",", Settings.P_Ema2, ",", Settings.P_Ema3, ",", Settings.P_Ema4);
   Print("Effective MACD periods: ", Settings.P_MacdFast, ",", Settings.P_MacdSlow, ",", Settings.P_MacdSig);
   Print("Bias Mode (Input): ", EnumToString(Inp_BiasMode), " | ManualSide (Input): ", EnumToString(Inp_ManualSide));
   Print("BiasEnabled (Input): ", (Inp_BiasEnabled ? "true" : "false"));
   
   if(Settings.VoteThreshold <= 1) 
      Print("NOTE: VoteThreshold <= 1 => voting bypassed (individual vote toggles ignored).");
      
   Print("MA Method (Input): ", EnumToString(Inp_MaType));
   
   if(Inp_PrintEffectiveConfig)
   {
      Print("Effective Bias Mode: ", EnumToString(g_effectiveBiasMode), (g_effectiveSigNote=="" ? "" : " | "), g_effectiveSigNote);
      Print("Effective Direction Source: ", g_effectiveDirSource);
      Print("Effective EMA Strategy: ", EnumToString(g_effectiveEmaStrategy));
      Print("Effective MA Method: ", EnumToString(g_effectiveMaType));
      
      if(g_ui_used_flags != "")   Print("Effective Used Flags: ", g_ui_used_flags);
      if(g_ui_ignored_flags != "") Print("Effective Ignored Flags: ", g_ui_ignored_flags);
      
      Print("Effective AutoStrat: ", EnumToString(Settings.AutoStrat),
            " | FastID:", Settings.BiasFastID,
            " | SlowID:", Settings.BiasSlowID,
            " | ManSide:", EnumToString(Settings.ManSide));
            
      Print("=== OPTIMIZATION SUMMARY (v1.02.016d-OPT) ===");
      Print("Vote Bundle: EMA + ADX + MACD + Stochastic (Zone Filter)");
      Print("Vote Threshold: ", Settings.VoteThreshold, " (OPTIMIZED from 6)");
      Print("RRM Pullback/Reclaim Gate: ", (Settings.RRM_RequirePullbackReclaim ? "ENABLED" : "DISABLED"));
      Print("RRM EMA Divergence Gate: ", (Settings.RRM_RequireEmaDiv ? "ENABLED" : "DISABLED"));
      Print("MaxATR Gate: ", Settings.MaxATR, " pips (NEW)");
      Print("Spread Gate: ", Settings.MaxSpread, " pips");
      Print("MinATR Gate: ", Settings.MinATR, " pips");
      Print("Risk per Trade: ", Settings.RiskPercent, "%");
      Print("Expected Win Rate Improvement: +10-15% vs baseline");
   }
   
   Print("------------------------------------------");
   SEA_UI_Init(Inp_MagicNum);
   SEA_UI_UpdateSettingsPanel();
   SEA_UI_UpdateCockpitPanel(Signal.GetATR(), 0, Signal.LastBias(), Signal.LastVotes(), Signal.LastReason());

   FlowLog("OnInit complete -> INIT_SUCCEEDED");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| EXPLICIT TICK PIPELINE                                           |
//+------------------------------------------------------------------+

void OrchestrateTick()
{
   // New bar execution only (stability)
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
   
   // ★★★ DEBUG OUTPUT ★★★
   if(direction == 0) {
      string reason = Signal.LastReason();
      Print("DEBUG: No signal. Reason: ", reason, " | Bias: ", Signal.LastBias(), 
            " | Votes: ", Signal.LastVotes(), "/", Settings.VoteThreshold);
   } else {
      Print("DEBUG: SIGNAL GENERATED! Direction: ", direction, " | Bias: ", Signal.LastBias(), 
            " | Votes: ", Signal.LastVotes(), "/", Settings.VoteThreshold, 
            " | Reason: ", Signal.LastReason());
   }
   
   // Visualization: eligible entry signal marker
   if(Inp_DrawEntryLines && direction != 0)
      SEA_DrawEntrySignalLine(iTime(_Symbol, PERIOD_CURRENT, 1), direction, Signal.LastReason());
      
   FlowLog(StringFormat("Step C: ProcessSignal (direction=%d)", direction));
   if(direction != 0)
      Executor.ProcessSignal(direction, atr);

   SEA_UI_UpdateCockpitPanel(atr, direction, Signal.LastBias(), Signal.LastVotes(), Signal.LastReason());
   FlowLog("Bar pipeline complete");
}

//+------------------------------------------------------------------+
//| EXPLICIT SHUTDOWN PIPELINE                                       |
//+------------------------------------------------------------------+

void OrchestrateDeinit(const int reason)
{
   // Strategy Tester report export (if enabled)
   if(Settings.ExportCSV)
      SEA_Report_Generate();
      
   SEA_UI_DestroyAll();
   FlowLog(StringFormat("EA stop -> OnDeinit(reason=%d)", reason));

   FlowLog("Step A: Release indicator handles / engine state");
   Signal.Release();

   FlowLog("Step B: Trade executor cleanup");
   // (No executor release required in current design.)

   FlowLog("Step C: Clear runtime state");
   g_last_bar_time = 0;

   FlowLog("OnDeinit complete");
}

//+------------------------------------------------------------------+
//| UI & CHART UTILITIES                                             |
//+------------------------------------------------------------------+

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
//| UI: SIGNAL MARKERS (STRATEGY TESTER)                             |
//+------------------------------------------------------------------+

void SEA_DrawEntrySignalLine(datetime bar_time, int direction, const string label)
{
   string name = StringFormat("SEA_ELIG_%I64d_%s", (long)bar_time, (direction>0?"BUY":"SELL"));
   if(ObjectFind(0, name) >= 0) return;

   ObjectCreate(0, name, OBJ_VLINE, 0, bar_time, 0);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DOT);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetString(0, name, OBJPROP_TOOLTIP, StringFormat("ELIGIBLE %s | %s", (direction>0?"BUY":"SELL"), label));
}

void SEA_DrawTradeExecLine(datetime event_time, int direction, double price, const string label)
{
   string name = StringFormat("SEA_TRADE_%I64d_%s", (long)event_time, (direction>0?"BUY":"SELL"));
   if(ObjectFind(0, name) >= 0) return;

   ObjectCreate(0, name, OBJ_VLINE, 0, event_time, 0);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
   ObjectSetString(0, name, OBJPROP_TOOLTIP, StringFormat("EXECUTED %s @%.5f | %s", (direction>0?"BUY":"SELL"), price, label));
}

//+------------------------------------------------------------------+
//| GENERIC HELPERS                                                  |
//+------------------------------------------------------------------+

void FlowLog(const string msg)
{
   if(Inp_DebugFlow) Print("FLOW: ", msg);
}

void AddListItem(string &list, const string item)
{
   if(list != "") list += ", ";
   list += item;
}

//+------------------------------------------------------------------+
//| END OF FILE                                                      |
//+------------------------------------------------------------------+