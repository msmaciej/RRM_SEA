//+------------------------------------------------------------------+
//|                                                SEA_Reporting.mqh |
//|                              MJS Institutional Trading Solutions |
//|                                                                  |
//|                         SimpleEA CSV Reporting (Strategy Tester) |
//+------------------------------------------------------------------+
// SAVE AS UTF-16 LE WITH BOM
#property strict

// --- Anti-stale build lock (MQL5-safe: no #if, no #error)
#ifndef SEA_BUILD_TOKEN_105001
enum { __SEA_BUILD_TOKEN_MISSING_REPORTING_105001 = SEA_BUILD_TOKEN_105001 };
#endif

#define SEA_MOD_REPORTING_105001 1


// --- Anti-stale build lock (macOS+Wine+MT5)
void SEA_Report_Generate()
{
   if(!MQLInfoInteger(MQL_TESTER))
      return;

   if(!Settings.ExportCSV && !Inp_Debug_ExportCSV)
      return;

   string start_str = TimeToString(g_start_time, TIME_DATE);
   string end_str   = TimeToString(TimeCurrent(), TIME_DATE);
   StringReplace(start_str, ".", "-");
   StringReplace(end_str, ".", "-");
   string tf_str = EnumToString((ENUM_TIMEFRAMES)_Period);
   string filename = StringFormat("Report_SimpleEA_%s_%s_%s_%s.csv", _Symbol, tf_str, start_str, end_str);

   uint flags = FILE_CSV | FILE_WRITE | FILE_UNICODE;
   if(Inp_Debug_ExportUseCommonFiles)
      flags |= FILE_COMMON;

   int handle = FileOpen(filename, flags, ",");
   if(handle == INVALID_HANDLE)
   {
      Print("Report: Failed to write ", filename, " (flags=", (int)flags, ")");
      return;
   }

   FileWrite(handle, "=== TEST CONFIGURATION (" + SEA_BUILD_STR + ") ===");
   FileWrite(handle, "Preset Mode", EnumToString(Inp_Global_Preset));
   FileWrite(handle, "ExportCSV (Input)", (Inp_Debug_ExportCSV ? "true" : "false"));
   FileWrite(handle, "ExportCSV (Effective)", (Settings.ExportCSV ? "true" : "false"));
   FileWrite(handle, "BiasMode (Effective)", EnumToString(g_effectiveBiasMode));
   FileWrite(handle, "Direction Source (Effective)", g_effectiveDirSource);
   FileWrite(handle, "Used Flags (Effective)", g_ui_used_flags);
   FileWrite(handle, "Ignored Flags (Effective)", g_ui_ignored_flags);
   FileWrite(handle, "Overrides (Effective)", g_ui_overrides);
   FileWrite(handle, "BiasEnabled (Effective)", (Settings.BiasEnabled ? "true" : "false"));
   FileWrite(handle, "AutoStrat (Effective)", EnumToString(Settings.AutoStrat));
   FileWrite(handle, "BiasFastID/BiasSlowID (Effective)", StringFormat("%d/%d", Settings.BiasFastID, Settings.BiasSlowID));
   FileWrite(handle, "MA Method (Effective)", EnumToString(g_effectiveMaType));
   FileWrite(handle, "Notes", g_effectiveSigNote);
   FileWrite(handle, "EMA Strategy (Effective)", EnumToString(g_effectiveEmaStrategy));
   FileWrite(handle, "");

   FileWrite(handle, "=== BENCHMARK INPUTS (0c) ===");
   // F-AUDIT 2026-07 CORRECTION: Inp_MA_Period/Inp_MA_Shift are themselves declared inside
   // #ifdef SEA_PRESET_MA in SEA_Inputs.mqh (this repo builds one active preset at a time,
   // selected in SEA_Config.mqh — currently SEA_PRESET_RRM_ORG). Restored the guard here to
   // match; my first pass wrongly removed it, causing "undeclared identifier" when SEA_PRESET_MA
   // isn't the active build. The old Inp_MA_MaximumRiskPct/Inp_MA_DecreaseFactor lines that used
   // to live in this block are gone for good (proven dead sinks; see
   // Readme/README_SEA_PARAMETER_MAPPING.md "Input Surface Audit") — the effective values are
   // still reported unconditionally below via Settings.MA_MaximumRiskPct/MA_DecreaseFactor.
#ifdef SEA_PRESET_MA
   FileWrite(handle, "MA Period (Input)", IntegerToString(Inp_MA_Period));
   FileWrite(handle, "MA Shift (Input)", IntegerToString(Inp_MA_Shift));
#endif // SEA_PRESET_MA
   FileWrite(handle, "MACompatSizer (Effective)", (Settings.UseMACompatSizer ? "true" : "false"));
   FileWrite(handle, "MA MaximumRiskPct (Effective)", DoubleToString(Settings.MA_MaximumRiskPct, 4));
   FileWrite(handle, "MA DecreaseFactor (Effective)", DoubleToString(Settings.MA_DecreaseFactor, 2));
   FileWrite(handle, "MABenchmarkStrict (Effective)", (Settings.MABenchmarkStrict ? "true" : "false"));
   FileWrite(handle, "RequirePriceCross (Effective)", (Settings.RequirePriceCross ? "true" : "false"));
   FileWrite(handle, "MA Method (Effective)", EnumToString(g_effectiveMaType));
   FileWrite(handle, "MA HorShift (Effective)", IntegerToString(Settings.ma_h_shift));
   FileWrite(handle, "MA VerShift (Effective)", IntegerToString(Settings.ma_v_shift));
   FileWrite(handle, "");

   FileWrite(handle, "=== CORE PERFORMANCE ===");
   FileWrite(handle, "Net Profit", DoubleToString(TesterStatistics(STAT_PROFIT), 2));
   FileWrite(handle, "Gross Profit", DoubleToString(TesterStatistics(STAT_GROSS_PROFIT), 2));
   FileWrite(handle, "Gross Loss", DoubleToString(TesterStatistics(STAT_GROSS_LOSS), 2));
   FileWrite(handle, "Profit Factor", DoubleToString(TesterStatistics(STAT_PROFIT_FACTOR), 2));
   FileWrite(handle, "Expected Payoff", DoubleToString(TesterStatistics(STAT_EXPECTED_PAYOFF), 2));
   FileWrite(handle, "Sharpe Ratio", DoubleToString(TesterStatistics(STAT_SHARPE_RATIO), 2));
   FileWrite(handle, "Recovery Factor", DoubleToString(TesterStatistics(STAT_RECOVERY_FACTOR), 2));
   FileWrite(handle, "");

   FileWrite(handle, "=== RISK & DRAWDOWN ===");
   FileWrite(handle, "Balance DD Relative %", DoubleToString(TesterStatistics(STAT_BALANCE_DDREL_PERCENT), 2) + "%");
   FileWrite(handle, "Equity DD Relative %", DoubleToString(TesterStatistics(STAT_EQUITY_DDREL_PERCENT), 2) + "%");
   FileWrite(handle, "Absolute Drawdown", DoubleToString(TesterStatistics(STAT_EQUITY_DD), 2));
   FileWrite(handle, "");

   FileWrite(handle, "=== TRADE STATISTICS ===");
   double trades = TesterStatistics(STAT_TRADES);
   double wins   = TesterStatistics(STAT_PROFIT_TRADES);
   double winRate = (wins / (trades > 0 ? trades : 1)) * 100.0;
   FileWrite(handle, "Total Trades", DoubleToString(trades, 0));
   FileWrite(handle, "Win Rate %", DoubleToString(winRate, 2) + "%");
   FileWrite(handle, "Winning Trades", DoubleToString(wins, 0));
   FileWrite(handle, "Losing Trades", DoubleToString(TesterStatistics(STAT_LOSS_TRADES), 0));
   FileWrite(handle, "");

   FileWrite(handle, "=== DEAL HISTORY ===");
   FileWrite(handle, "Time", "Symbol", "Type", "Volume", "Price", "Profit", "Balance");

   HistorySelect(0, TimeCurrent());
   int deals = HistoryDealsTotal();
   double balance = TesterStatistics(STAT_INITIAL_DEPOSIT);
   for(int i=0; i<deals; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      long type = HistoryDealGetInteger(ticket, DEAL_TYPE);
      if(type == DEAL_TYPE_BUY || type == DEAL_TYPE_SELL)
      {
         datetime time = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
         double vol    = HistoryDealGetDouble(ticket, DEAL_VOLUME);
         double price  = HistoryDealGetDouble(ticket, DEAL_PRICE);
         double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT) + HistoryDealGetDouble(ticket, DEAL_SWAP) + HistoryDealGetDouble(ticket, DEAL_COMMISSION);
         balance += profit;
         string s_type = (type==DEAL_TYPE_BUY) ? "Buy" : "Sell";
         string s_time = TimeToString(time, TIME_DATE|TIME_MINUTES);
         FileWrite(handle, s_time, _Symbol, s_type, DoubleToString(vol, 2), DoubleToString(price, 5), DoubleToString(profit, 2), DoubleToString(balance, 2));
      }
   }

   FileClose(handle);

   if(Inp_Debug_ExportUseCommonFiles)
      Print("Report: Saved ", filename, " (COMMON Files) | DataFolder -> Common -> Files");
   else
      Print("Report: Saved ", filename, " (Terminal Files) | DataFolder -> MQL5 -> Files");
}
