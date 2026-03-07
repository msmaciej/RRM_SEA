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
int      g_ts_thr    = 0;
string   g_ts_reason = "";

// --- TS→TE Two-Phase Entry State
// Phase 1 (TS): evaluated at bar-close (shift=1) when a new bar opens.
//               Sets g_ts_active=true and records the bar time + direction.
// Phase 2 (TE): evaluated on the very first tick of the NEXT bar (shift=0).
//               Calls Executor.EvaluateTE() which handles the complete entry
//               process (filters → RC → CM → execute); resets g_ts_active.
bool     g_ts_active    = false;  // True while a TS signal is pending TE execution
datetime g_ts_bar_time  = 0;      // Bar N open-time when the TS was generated
int      g_ts_direction = 0;      // TS direction: 1=BUY, -1=SELL
datetime g_last_te_bar_time = 0;  // Bar time when TE executed (to skip next TS)

// Global tracking for RRM drawdown protection
int      g_consecutive_losses     = 0;
int      g_trades_today           = 0;
datetime g_last_trade_date        = 0;
double   g_daily_starting_balance = 0.0;

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
   {
      Print("Preset ", PresetToString(InpPreset), " is active; strategy inputs ignored");
      if(Settings.AdminOverridePreset)
         Print("AdminOverride: ACTIVE [Admin Mode] - override inputs are applied on top of preset");
      else
         Print("AdminOverride: OFF [Normal User Mode] - preset is fully enforced");
   }

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

   if(Settings.VoteThreshold < 1)
   {
      Print("ERROR: VoteThreshold must be >= 1 (got ", Settings.VoteThreshold, ")");
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
   // TS→TE Phase 2: Trade Entry evaluation on bar N+1 open (shift=0)
   //
   // Fires on the first tick of the bar AFTER the TS signal was generated.
   // EvaluateTE() handles the complete entry process: filters → RC → CM → Execute.
   // g_ts_active is reset unconditionally so TE fires at most once per TS.
   // ═══════════════════════════════════════════════════════════════
   if(g_ts_active && current_bar != g_ts_bar_time)
   {
      if(Settings.DebugFlow)
         PrintFormat("[TE CHECK] Evaluating TE at shift=0 for %s | TS bar: %s",
                     (g_ts_direction > 0 ? "BUY" : "SELL"),
                     TimeToString(g_ts_bar_time, TIME_DATE|TIME_MINUTES));

      // TE: handles filters, RC, CM and order execution internally
      int te_result = Executor.EvaluateTE(g_ts_direction);

      if(te_result != 0)
      {
         g_last_te_bar_time = current_bar;  // Mark this bar as TE execution bar
      }
      else
      {
         if(Settings.DebugFlow)
            PrintFormat("[TE SKIPPED/BLOCKED] EvaluateTE returned 0 for TS from %s",
                        TimeToString(g_ts_bar_time, TIME_DATE|TIME_MINUTES));
      }

      // TS→TE state reset: TE fires at most once per TS signal
      g_ts_active    = false;
      g_ts_direction = 0;
      g_ts_bar_time  = 0;
   }

   // ═══════════════════════════════════════════════════════════════
   // New-bar pipeline: runs only once per bar
   // ═══════════════════════════════════════════════════════════════
   if(!is_new_bar)
      return;

   g_last_bar_time = current_bar;
   FlowLog("OnTick -> NewBar detected -> begin bar pipeline");

   FlowLog("Step A: Manage open positions (Trailing/BE)");
   Executor.EvaluateTM();

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
   // TS→TE Phase 1: Trade Setup evaluation on bar close (shift=1)
   //
   // Runs once per bar when no TS is pending and drawdown is not blocked.
   // EvaluateTS() evaluates ALL pipeline steps (bias, filters, voting)
   // on the CLOSED bar (shift=1 via Vote_EvalShift=1) and returns a
   // direction if a valid TS is found.  The TS is stored; execution is
   // deferred to Phase 2 on the next tick.
   // ═══════════════════════════════════════════════════════════════
   if(!drawdown_blocked && !g_ts_active)
   {
      // Skip TS evaluation if previous bar was a TE execution bar
      // (gives indicators time to develop a new setup)
      // prev_bar = shift=1 (the bar that just closed); if TE executed on it, skip TS
      datetime prev_bar = iTime(_Symbol, PERIOD_CURRENT, 1);
      if(prev_bar == g_last_te_bar_time)
      {
         if(Settings.DebugFlow)
            PrintFormat("[TS SKIP] Not evaluating TS - previous bar %s was TE execution bar",
                        TimeToString(prev_bar, TIME_DATE|TIME_MINUTES));
      }
      else
      {
      FlowLog("Step B: Compute direction signal (TS evaluation at shift=1)");
      int ts = Signal.EvaluateTS();

      // Capture TS display snapshot
      if(ts != 0)
      {
         g_ts_time   = iTime(_Symbol, PERIOD_CURRENT, 1);
         g_ts_dir    = ts;
         g_ts_bias   = Signal.LastBias();
         g_ts_votes  = Signal.LastVotes();
         g_ts_thr    = Settings.VoteThreshold;
         g_ts_reason = Signal.LastReason();

         // Arm TS→TE state for Phase 2 evaluation on the next bar's first tick.
         // Store current bar's open-time; Phase 2 fires when current_bar != g_ts_bar_time.
         g_ts_active    = true;
         g_ts_direction = ts;
         g_ts_bar_time  = current_bar;  // Open-time of bar N where TS was detected

         if(Settings.DebugFlow)
            PrintFormat("[TS=1] Setup confirmed at bar close %s | %s | Waiting for TE on next bar open",
                        TimeToString(g_ts_time, TIME_DATE|TIME_MINUTES),
                        (ts > 0 ? "BUY" : "SELL"));

         if(Settings.DrawEntryLines)
            SEA_DrawEntrySignalLine(g_ts_time, ts, Signal.LastReason());
      }
      else
      {
         if(Settings.DebugFlow)
            Print("[TS=0] No setup. Reason: ", Signal.LastReason(),
                  " | Bias: ", Signal.LastBias(),
                  " | Votes: ", Signal.LastVotes(), "/", Settings.VoteThreshold);
      }

      FlowLog(StringFormat("Step B done: TS=%d (pending=%s)",
                           ts, (g_ts_active ? "YES" : "NO")));
      } // end else (not TE execution bar)
   }
   else if(g_ts_active)
   {
      // A TS is already pending TE on the next bar — skip fresh TS evaluation
      // to avoid overwriting the pending setup before TE has fired.
      if(Settings.DebugFlow)
         PrintFormat("[TS SKIP] TS already pending for %s direction=%d; skipping new TS evaluation",
                     TimeToString(g_ts_bar_time, TIME_DATE|TIME_MINUTES), g_ts_direction);
   }

   // Build TS/TE snapshot strings for cockpit display
   string ts_snap = "";
   if(g_ts_time > 0)
   {
      string dir_str = (g_ts_dir > 0 ? "BUY" : "SELL");
      ts_snap = StringFormat("TS@%s dir=%s votes=%d/%d reason=%s",
         TimeToString(g_ts_time, TIME_DATE|TIME_MINUTES), dir_str, g_ts_votes, g_ts_thr, g_ts_reason);
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

   SEA_UI_UpdateCockpitPanel(atr, (g_ts_active ? g_ts_direction : 0),
                             snap_bias, snap_votes, snap_reason,
                             ts_snap, te_snap, vote_snaps, vote_snap_count, diag_snap);
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
   g_last_bar_time     = 0;
   g_ts_active         = false;
   g_ts_direction      = 0;
   g_ts_bar_time       = 0;
   g_last_te_bar_time  = 0;

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