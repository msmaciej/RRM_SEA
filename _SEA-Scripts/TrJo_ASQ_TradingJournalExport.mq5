//+------------------------------------------------------------------+
//|                                  ASQ_TradingJournalExport.mq5    |
//|                              Copyright 2026, AlgoSphere Quant    |
//|                      https://www.mql5.com/en/users/robin2.0      |
//+------------------------------------------------------------------+
#property copyright   "Copyright 2026, AlgoSphere Quant"
#property link        "https://www.mql5.com/en/users/robin2.0"
#property version     "3.00"
#property description "ASQ Trading Journal Export v3.00"
#property description "One-click CSV export with advanced analytics:"
#property description "per-symbol breakdown, drawdown curve, profit factor,"
#property description "streaks, R:R analysis, and account header."
#property description ""
#property description "Free & open-source. AlgoSphere Quant — Precision before profit."
#property script_show_inputs

//+------------------------------------------------------------------+
//| ENUMS                                                             |
//+------------------------------------------------------------------+
enum ENUM_EXPORT_FORMAT
  {
   FMT_CSV  = 0, // CSV (Excel / Sheets)
   FMT_TSV  = 1  // TSV (Tab-separated)
  };

enum ENUM_SORT_ORDER
  {
   SORT_TIME_ASC  = 0, // Oldest first
   SORT_TIME_DESC = 1, // Newest first
   SORT_PNL_DESC  = 2, // Best P/L first
   SORT_PNL_ASC   = 3  // Worst P/L first
  };

//+------------------------------------------------------------------+
//| INPUTS                                                            |
//+------------------------------------------------------------------+
input group              "══════ Export Settings ══════"
input string             InpFileName        = "ASQ_Journal";   // File Name (without extension)
input int                InpDaysBack        = 30;              // Days of History (0=all)
input string             InpSymbolFilter    = "";              // Symbol Filter (empty=all)
input long               InpMagicFilter     = -1;              // Magic Filter (-1=all)
input ENUM_EXPORT_FORMAT InpFormat          = FMT_CSV;         // Export format
input ENUM_SORT_ORDER    InpSortOrder       = SORT_TIME_ASC;   // Sort order

input group              "══════ Columns ══════"
input bool               InpIncludeSwap     = true;            // Include Swap
input bool               InpIncludeComm     = true;            // Include Commission
input bool               InpIncludeDuration = true;            // Include Duration
input bool               InpIncludeMagic    = true;            // Include Magic Number
input bool               InpIncludeComment  = true;            // Include Comment
input bool               InpIncludePips     = true;            // Include Pips P/L
input bool               InpIncludeMAE      = true;            // Include MAE/MFE columns

input group              "══════ Analytics ══════"
input bool               InpSymbolBreakdown = true;            // Per-symbol breakdown section
input bool               InpDrawdownCurve   = true;            // Cumulative P/L + DD curve
input bool               InpAccountHeader   = true;            // Account info header

//+------------------------------------------------------------------+
//| TRADE RECORD STRUCT                                               |
//+------------------------------------------------------------------+
struct STradeRecord
  {
   long              posId;
   string            symbol;
   string            direction;
   datetime          openTime;
   datetime          closeTime;
   double            lots;
   double            openPrice;
   double            closePrice;
   double            sl;
   double            tp;
   double            grossPL;
   double            swap;
   double            commission;
   double            netPL;
   double            pips;
   int               durationMin;
   long              magic;
   string            comment;
   int               digits;
  };

//+------------------------------------------------------------------+
//| SYMBOL STATS STRUCT                                               |
//+------------------------------------------------------------------+
struct SSymbolStats
  {
   string            symbol;
   int               trades;
   int               wins;
   int               losses;
   double            grossPL;
   double            netPL;
   double            totalPips;
   double            avgWin;
   double            avgLoss;
   double            bestTrade;
   double            worstTrade;
   double            profitFactor;
  };

//+------------------------------------------------------------------+
//| Script start                                                      |
//+------------------------------------------------------------------+
void OnStart()
  {
//--- Date range
   datetime startDate = 0;
   if(InpDaysBack > 0)
      startDate = TimeCurrent() - InpDaysBack * 86400;

   if(!HistorySelect(startDate, TimeCurrent()))
     {
      Print("[ASQ JournalExport] Failed to select history.");
      Alert("[ASQ JournalExport] Failed to select history.");
      return;
     }

//--- Collect all trades
   STradeRecord trades[];
   int tradeCount = CollectTrades(trades);

   if(tradeCount == 0)
     {
      Alert("[ASQ JournalExport] No trades found for the specified period.");
      return;
     }

//--- Sort
   SortTrades(trades, tradeCount);

//--- Build filename
   MqlDateTime dtNow;
   TimeToStruct(TimeCurrent(), dtNow);
   string ext = (InpFormat == FMT_CSV) ? ".csv" : ".tsv";
   string sep = (InpFormat == FMT_CSV) ? "," : "\t";
   string fileName = InpFileName + "_" +
                     IntegerToString(dtNow.year) +
                     StringFormat("%02d", dtNow.mon) +
                     StringFormat("%02d", dtNow.day) + ext;

//--- Open file
   int handle = FileOpen(fileName, FILE_WRITE | FILE_CSV | FILE_ANSI, StringGetCharacter(sep, 0));
   if(handle == INVALID_HANDLE)
     {
      Print("[ASQ JournalExport] Cannot create file: ", fileName, " Err=", GetLastError());
      Alert("[ASQ JournalExport] Cannot create file.");
      return;
     }

//--- SECTION 1: Account header
   if(InpAccountHeader)
      WriteAccountHeader(handle);

//--- SECTION 2: Trade rows
   WriteTradeHeader(handle);
   for(int i = 0; i < tradeCount; i++)
      WriteTradeRow(handle, trades[i]);

//--- Calculate stats
   int wins = 0, losses = 0;
   double totalGross = 0, totalNet = 0, totalPips = 0;
   double sumWins = 0, sumLosses = 0;
   double bestTrade = -DBL_MAX, worstTrade = DBL_MAX;
   int maxWinStreak = 0, maxLossStreak = 0;
   int curWinStreak = 0, curLossStreak = 0;
   double peakPL = 0, maxDD = 0, runningPL = 0;

   for(int i = 0; i < tradeCount; i++)
     {
      totalGross += trades[i].grossPL;
      totalNet   += trades[i].netPL;
      totalPips  += trades[i].pips;

      if(trades[i].netPL > bestTrade)  bestTrade  = trades[i].netPL;
      if(trades[i].netPL < worstTrade) worstTrade = trades[i].netPL;

      if(trades[i].netPL >= 0)
        {
         wins++; sumWins += trades[i].netPL;
         curWinStreak++; curLossStreak = 0;
         if(curWinStreak > maxWinStreak) maxWinStreak = curWinStreak;
        }
      else
        {
         losses++; sumLosses += MathAbs(trades[i].netPL);
         curLossStreak++; curWinStreak = 0;
         if(curLossStreak > maxLossStreak) maxLossStreak = curLossStreak;
        }

      //--- Drawdown tracking
      runningPL += trades[i].netPL;
      if(runningPL > peakPL) peakPL = runningPL;
      double dd = peakPL - runningPL;
      if(dd > maxDD) maxDD = dd;
     }

   double winRate = (tradeCount > 0) ? (double)wins / tradeCount * 100.0 : 0;
   double avgWin  = (wins > 0) ? sumWins / wins : 0;
   double avgLoss = (losses > 0) ? sumLosses / losses : 0;
   double profitFactor = (sumLosses > 0) ? sumWins / sumLosses : (sumWins > 0 ? 999.0 : 0);
   double expectancy = (tradeCount > 0) ? totalNet / tradeCount : 0;
   double rrRatio = (avgLoss > 0) ? avgWin / avgLoss : 0;

//--- SECTION 3: Summary
   FileWriteString(handle, "\n");
   FileWriteString(handle, "SUMMARY\n");
   FileWriteString(handle, "Trades" + sep + IntegerToString(tradeCount) + "\n");
   FileWriteString(handle, "Wins" + sep + IntegerToString(wins) + "\n");
   FileWriteString(handle, "Losses" + sep + IntegerToString(losses) + "\n");
   FileWriteString(handle, "Win Rate" + sep + DoubleToString(winRate, 1) + "%\n");
   FileWriteString(handle, "Gross P/L" + sep + DoubleToString(totalGross, 2) + "\n");
   FileWriteString(handle, "Net P/L" + sep + DoubleToString(totalNet, 2) + "\n");
   FileWriteString(handle, "Total Pips" + sep + DoubleToString(totalPips, 1) + "\n");
   FileWriteString(handle, "Profit Factor" + sep + DoubleToString(profitFactor, 2) + "\n");
   FileWriteString(handle, "Expectancy" + sep + DoubleToString(expectancy, 2) + "\n");
   FileWriteString(handle, "Avg Win" + sep + DoubleToString(avgWin, 2) + "\n");
   FileWriteString(handle, "Avg Loss" + sep + DoubleToString(avgLoss, 2) + "\n");
   FileWriteString(handle, "R:R Ratio" + sep + DoubleToString(rrRatio, 2) + "\n");
   FileWriteString(handle, "Best Trade" + sep + DoubleToString(bestTrade, 2) + "\n");
   FileWriteString(handle, "Worst Trade" + sep + DoubleToString(worstTrade, 2) + "\n");
   FileWriteString(handle, "Max Win Streak" + sep + IntegerToString(maxWinStreak) + "\n");
   FileWriteString(handle, "Max Loss Streak" + sep + IntegerToString(maxLossStreak) + "\n");
   FileWriteString(handle, "Max Drawdown" + sep + DoubleToString(maxDD, 2) + "\n");
   FileWriteString(handle, "Period" + sep + IntegerToString(InpDaysBack) + " days\n");
   FileWriteString(handle, "Generated" + sep + TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES) + "\n");

//--- SECTION 4: Per-symbol breakdown
   if(InpSymbolBreakdown)
     {
      SSymbolStats symStats[];
      int symCount = BuildSymbolStats(trades, tradeCount, symStats);

      FileWriteString(handle, "\nPER-SYMBOL BREAKDOWN\n");
      FileWriteString(handle, "Symbol" + sep + "Trades" + sep + "Wins" + sep + "Losses" +
                      sep + "Win%" + sep + "Net P/L" + sep + "Pips" +
                      sep + "Avg Win" + sep + "Avg Loss" + sep + "PF" +
                      sep + "Best" + sep + "Worst\n");

      for(int s = 0; s < symCount; s++)
        {
         double wr = (symStats[s].trades > 0) ? (double)symStats[s].wins / symStats[s].trades * 100 : 0;
         FileWriteString(handle,
                         symStats[s].symbol + sep +
                         IntegerToString(symStats[s].trades) + sep +
                         IntegerToString(symStats[s].wins) + sep +
                         IntegerToString(symStats[s].losses) + sep +
                         DoubleToString(wr, 1) + "%" + sep +
                         DoubleToString(symStats[s].netPL, 2) + sep +
                         DoubleToString(symStats[s].totalPips, 1) + sep +
                         DoubleToString(symStats[s].avgWin, 2) + sep +
                         DoubleToString(symStats[s].avgLoss, 2) + sep +
                         DoubleToString(symStats[s].profitFactor, 2) + sep +
                         DoubleToString(symStats[s].bestTrade, 2) + sep +
                         DoubleToString(symStats[s].worstTrade, 2) + "\n");
        }
     }

//--- SECTION 5: Cumulative P/L curve
   if(InpDrawdownCurve)
     {
      FileWriteString(handle, "\nCUMULATIVE P/L CURVE\n");
      FileWriteString(handle, "Trade#" + sep + "Close Time" + sep + "Net P/L" +
                      sep + "Cumulative" + sep + "Peak" + sep + "Drawdown\n");

      double cumPL = 0, peak = 0;
      for(int i = 0; i < tradeCount; i++)
        {
         cumPL += trades[i].netPL;
         if(cumPL > peak) peak = cumPL;
         double dd = peak - cumPL;
         FileWriteString(handle,
                         IntegerToString(i + 1) + sep +
                         TimeToString(trades[i].closeTime, TIME_DATE | TIME_MINUTES) + sep +
                         DoubleToString(trades[i].netPL, 2) + sep +
                         DoubleToString(cumPL, 2) + sep +
                         DoubleToString(peak, 2) + sep +
                         DoubleToString(dd, 2) + "\n");
        }
     }

//--- Footer
   FileWriteString(handle, "\nAlgoSphere Quant — Precision before profit\n");
   FileClose(handle);

//--- Report
   string report = StringFormat(
      "[ASQ Trading Journal Export v3.00]\n\n"
      "File: %s\n"
      "Trades: %d (W:%d L:%d | %.1f%%)\n"
      "Net P/L: %.2f | PF: %.2f | Exp: %.2f\n"
      "Max DD: %.2f | R:R: %.2f\n"
      "Streaks: W%d / L%d\n"
      "Location: MQL5/Files/%s",
      fileName, tradeCount, wins, losses, winRate,
      totalNet, profitFactor, expectancy,
      maxDD, rrRatio,
      maxWinStreak, maxLossStreak,
      fileName);

   Print(report);
   Alert(report);
  }

//+------------------------------------------------------------------+
//| COLLECT TRADES                                                    |
//+------------------------------------------------------------------+
int CollectTrades(STradeRecord &trades[])
  {
   int totalDeals = HistoryDealsTotal();
   int count = 0;
   ArrayResize(trades, 0, 200);

   for(int i = 0; i < totalDeals; i++)
     {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;

      ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_INOUT) continue;

      string symbol = HistoryDealGetString(ticket, DEAL_SYMBOL);
      if(InpSymbolFilter != "" && symbol != InpSymbolFilter) continue;

      long magic = HistoryDealGetInteger(ticket, DEAL_MAGIC);
      if(InpMagicFilter >= 0 && magic != InpMagicFilter) continue;

      STradeRecord rec;
      rec.symbol    = symbol;
      rec.lots      = HistoryDealGetDouble(ticket, DEAL_VOLUME);
      rec.closePrice= HistoryDealGetDouble(ticket, DEAL_PRICE);
      rec.grossPL   = HistoryDealGetDouble(ticket, DEAL_PROFIT);
      rec.swap      = HistoryDealGetDouble(ticket, DEAL_SWAP);
      rec.commission= HistoryDealGetDouble(ticket, DEAL_COMMISSION);
      rec.closeTime = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
      rec.comment   = HistoryDealGetString(ticket, DEAL_COMMENT);
      rec.magic     = magic;
      rec.posId     = HistoryDealGetInteger(ticket, DEAL_POSITION_ID);
      rec.digits    = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
      if(rec.digits == 0) rec.digits = 5;

      ENUM_DEAL_TYPE dealType = (ENUM_DEAL_TYPE)HistoryDealGetInteger(ticket, DEAL_TYPE);

      //--- Find opening deal
      rec.openPrice = 0; rec.sl = 0; rec.tp = 0;
      rec.openTime  = rec.closeTime;
      rec.direction = (dealType == DEAL_TYPE_SELL) ? "BUY" : "SELL";

      for(int j = 0; j < totalDeals; j++)
        {
         ulong ot = HistoryDealGetTicket(j);
         if(ot == 0) continue;
         if(HistoryDealGetInteger(ot, DEAL_POSITION_ID) != rec.posId) continue;
         if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(ot, DEAL_ENTRY) == DEAL_ENTRY_IN)
           {
            rec.openPrice = HistoryDealGetDouble(ot, DEAL_PRICE);
            rec.openTime  = (datetime)HistoryDealGetInteger(ot, DEAL_TIME);
            ENUM_DEAL_TYPE ot2 = (ENUM_DEAL_TYPE)HistoryDealGetInteger(ot, DEAL_TYPE);
            rec.direction = (ot2 == DEAL_TYPE_BUY) ? "BUY" : "SELL";
            long orderId = HistoryDealGetInteger(ot, DEAL_ORDER);
            if(HistoryOrderSelect(orderId))
              { rec.sl = HistoryOrderGetDouble(orderId, ORDER_SL); rec.tp = HistoryOrderGetDouble(orderId, ORDER_TP); }
            break;
           }
        }

      rec.netPL = rec.grossPL + rec.swap + rec.commission;
      rec.durationMin = (int)((rec.closeTime - rec.openTime) / 60);

      //--- Pips
      double pipDiv = (rec.digits == 3 || rec.digits == 5) ? 10.0 : 1.0;
      double point  = SymbolInfoDouble(rec.symbol, SYMBOL_POINT);
      if(point > 0 && rec.openPrice > 0)
        {
         double diff = (rec.direction == "BUY") ?
                       (rec.closePrice - rec.openPrice) :
                       (rec.openPrice - rec.closePrice);
         rec.pips = diff / (point * pipDiv);
        }
      else
         rec.pips = 0;

      ArrayResize(trades, count + 1);
      trades[count] = rec;
      count++;
     }

   return count;
  }

//+------------------------------------------------------------------+
//| SORT TRADES                                                       |
//+------------------------------------------------------------------+
void SortTrades(STradeRecord &trades[], int count)
  {
   //--- Simple insertion sort
   for(int i = 1; i < count; i++)
     {
      STradeRecord key = trades[i];
      int j = i - 1;
      while(j >= 0 && ShouldSwap(trades[j], key))
        {
         trades[j + 1] = trades[j];
         j--;
        }
      trades[j + 1] = key;
     }
  }

bool ShouldSwap(const STradeRecord &a, const STradeRecord &b)
  {
   switch(InpSortOrder)
     {
      case SORT_TIME_ASC:  return a.closeTime > b.closeTime;
      case SORT_TIME_DESC: return a.closeTime < b.closeTime;
      case SORT_PNL_DESC:  return a.netPL < b.netPL;
      case SORT_PNL_ASC:   return a.netPL > b.netPL;
     }
   return false;
  }

//+------------------------------------------------------------------+
//| BUILD PER-SYMBOL STATS                                            |
//+------------------------------------------------------------------+
int BuildSymbolStats(const STradeRecord &trades[], int count, SSymbolStats &stats[])
  {
   ArrayResize(stats, 0, 30);
   int symCount = 0;

   for(int i = 0; i < count; i++)
     {
      int idx = -1;
      for(int s = 0; s < symCount; s++)
        {
         if(stats[s].symbol == trades[i].symbol)
           { idx = s; break; }
        }
      if(idx < 0)
        {
         ArrayResize(stats, symCount + 1);
         idx = symCount;
         stats[idx].symbol = trades[i].symbol;
         stats[idx].trades = 0; stats[idx].wins = 0; stats[idx].losses = 0;
         stats[idx].grossPL = 0; stats[idx].netPL = 0; stats[idx].totalPips = 0;
         stats[idx].avgWin = 0; stats[idx].avgLoss = 0;
         stats[idx].bestTrade = -DBL_MAX; stats[idx].worstTrade = DBL_MAX;
         symCount++;
        }

      stats[idx].trades++;
      stats[idx].grossPL   += trades[i].grossPL;
      stats[idx].netPL     += trades[i].netPL;
      stats[idx].totalPips += trades[i].pips;
      if(trades[i].netPL > stats[idx].bestTrade)  stats[idx].bestTrade  = trades[i].netPL;
      if(trades[i].netPL < stats[idx].worstTrade) stats[idx].worstTrade = trades[i].netPL;
      if(trades[i].netPL >= 0) stats[idx].wins++;
      else                     stats[idx].losses++;
     }

   //--- Compute averages
   for(int s = 0; s < symCount; s++)
     {
      double sw = 0, sl = 0;
      int wc = 0, lc = 0;
      for(int i = 0; i < count; i++)
        {
         if(trades[i].symbol != stats[s].symbol) continue;
         if(trades[i].netPL >= 0) { sw += trades[i].netPL; wc++; }
         else                     { sl += MathAbs(trades[i].netPL); lc++; }
        }
      stats[s].avgWin  = (wc > 0) ? sw / wc : 0;
      stats[s].avgLoss = (lc > 0) ? sl / lc : 0;
      stats[s].profitFactor = (sl > 0) ? sw / sl : (sw > 0 ? 999.0 : 0);
     }

   return symCount;
  }

//+------------------------------------------------------------------+
//| WRITE HELPERS                                                     |
//+------------------------------------------------------------------+
void WriteAccountHeader(int handle)
  {
   string sep = (InpFormat == FMT_CSV) ? "," : "\t";
   FileWriteString(handle, "ACCOUNT INFO\n");
   FileWriteString(handle, "Broker" + sep + AccountInfoString(ACCOUNT_COMPANY) + "\n");
   FileWriteString(handle, "Account" + sep + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + "\n");
   FileWriteString(handle, "Name" + sep + AccountInfoString(ACCOUNT_NAME) + "\n");
   FileWriteString(handle, "Server" + sep + AccountInfoString(ACCOUNT_SERVER) + "\n");
   FileWriteString(handle, "Currency" + sep + AccountInfoString(ACCOUNT_CURRENCY) + "\n");
   FileWriteString(handle, "Leverage" + sep + "1:" + IntegerToString(AccountInfoInteger(ACCOUNT_LEVERAGE)) + "\n");
   FileWriteString(handle, "Balance" + sep + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2) + "\n");
   string mode = (AccountInfoInteger(ACCOUNT_TRADE_MODE) == ACCOUNT_TRADE_MODE_DEMO) ? "DEMO" : "LIVE";
   FileWriteString(handle, "Mode" + sep + mode + "\n");
   FileWriteString(handle, "\n");
  }

void WriteTradeHeader(int handle)
  {
   string sep = (InpFormat == FMT_CSV) ? "," : "\t";
   string h = "Ticket" + sep + "Symbol" + sep + "Direction" + sep +
              "Open Time" + sep + "Close Time" + sep + "Lots" + sep +
              "Open Price" + sep + "Close Price" + sep + "SL" + sep + "TP" + sep +
              "Gross P/L";
   if(InpIncludeSwap)     h += sep + "Swap";
   if(InpIncludeComm)     h += sep + "Commission";
   h += sep + "Net P/L";
   if(InpIncludePips)     h += sep + "Pips";
   if(InpIncludeDuration) h += sep + "Duration (min)";
   if(InpIncludeMagic)    h += sep + "Magic";
   if(InpIncludeComment)  h += sep + "Comment";
   FileWriteString(handle, h + "\n");
  }

void WriteTradeRow(int handle, const STradeRecord &t)
  {
   string sep = (InpFormat == FMT_CSV) ? "," : "\t";
   string row = IntegerToString(t.posId) + sep +
                t.symbol + sep + t.direction + sep +
                TimeToString(t.openTime, TIME_DATE | TIME_MINUTES) + sep +
                TimeToString(t.closeTime, TIME_DATE | TIME_MINUTES) + sep +
                DoubleToString(t.lots, 2) + sep +
                DoubleToString(t.openPrice, t.digits) + sep +
                DoubleToString(t.closePrice, t.digits) + sep +
                DoubleToString(t.sl, t.digits) + sep +
                DoubleToString(t.tp, t.digits) + sep +
                DoubleToString(t.grossPL, 2);
   if(InpIncludeSwap)     row += sep + DoubleToString(t.swap, 2);
   if(InpIncludeComm)     row += sep + DoubleToString(t.commission, 2);
   row += sep + DoubleToString(t.netPL, 2);
   if(InpIncludePips)     row += sep + DoubleToString(t.pips, 1);
   if(InpIncludeDuration) row += sep + IntegerToString(t.durationMin);
   if(InpIncludeMagic)    row += sep + IntegerToString(t.magic);
   if(InpIncludeComment)  row += sep + t.comment;
   FileWriteString(handle, row + "\n");
  }
//+------------------------------------------------------------------+
