//+------------------------------------------------------------------+
//|                                         TradeJournalExporter.mq5 |
//|                        Trade Journal Exporter - closed positions |
//|                                                        Dror Munk |
//+------------------------------------------------------------------+
#property copyright   "Dror Munk"
#property version     "1.00"
#property description "Exports your closed positions to a CSV file for journal analysis"
#property description "in Excel / Google Sheets: entry & exit time and price (volume-"
#property description "weighted over partial fills), volume, commission, swap, net"
#property description "profit, result in points and trade duration."
#property description ""
#property description "The file is written to MQL5\\Files (or the common folder if enabled)."
#property script_show_inputs

//--- inputs
input int    InpDaysBack       = 30;      // Period to export, days back from now
input string InpFileName       = "";      // File name ("" = auto TradeJournal_YYYY-MM-DD.csv)
input string InpSeparator      = ";";     // CSV separator (";" opens directly in Excel EU)
input bool   InpCommonFolder   = false;   // Write to common Files folder of all terminals
input bool   InpOnlyThisSymbol = false;   // Export only the current chart symbol

//+------------------------------------------------------------------+
//| One aggregated position record                                    |
//+------------------------------------------------------------------+
struct PositionRecord
  {
   long              position_id;
   string            symbol;
   string            type;          // buy / sell
   double            in_volume;     // total entered volume
   double            out_volume;    // total exited volume
   datetime          open_time;     // first entry deal time
   double            open_price;    // volume-weighted entry price
   datetime          close_time;    // last exit deal time
   double            close_price;   // volume-weighted exit price
   double            commission;
   double            swap;
   double            profit;        // net result of all deals of the position
   string            comment;
  };

//+------------------------------------------------------------------+
//| Script program start function                                     |
//+------------------------------------------------------------------+
void OnStart()
  {
   datetime to   = TimeCurrent() + 60;
   datetime from = to - (datetime)InpDaysBack * 86400;

   if(!HistorySelect(from, to))
     {
      Print("TradeJournalExporter: HistorySelect() failed, error ", GetLastError());
      return;
     }

   PositionRecord recs[];
   int total = HistoryDealsTotal();

   for(int i = 0; i < total; i++)
     {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0)
         continue;

      long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
      long dtype = HistoryDealGetInteger(ticket, DEAL_TYPE);
      if(dtype != DEAL_TYPE_BUY && dtype != DEAL_TYPE_SELL)
         continue;                                    // skip balance/credit operations

      string symbol = HistoryDealGetString(ticket, DEAL_SYMBOL);
      if(InpOnlyThisSymbol && symbol != _Symbol)
         continue;

      long     pos_id = HistoryDealGetInteger(ticket, DEAL_POSITION_ID);
      double   vol    = HistoryDealGetDouble(ticket, DEAL_VOLUME);
      double   price  = HistoryDealGetDouble(ticket, DEAL_PRICE);
      datetime dtime  = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);

      int idx = FindOrCreate(recs, pos_id, symbol);

      recs[idx].commission += HistoryDealGetDouble(ticket, DEAL_COMMISSION);
      recs[idx].swap       += HistoryDealGetDouble(ticket, DEAL_SWAP);
      recs[idx].profit     += HistoryDealGetDouble(ticket, DEAL_PROFIT);

      bool is_in  = (entry == DEAL_ENTRY_IN  || entry == DEAL_ENTRY_INOUT);
      bool is_out = (entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_INOUT ||
                     entry == DEAL_ENTRY_OUT_BY);

      if(is_in)
        {
         double prev = recs[idx].in_volume;
         recs[idx].open_price = (prev + vol > 0) ?
                                (prev * recs[idx].open_price + vol * price) / (prev + vol) : price;
         recs[idx].in_volume  = prev + vol;
         if(recs[idx].type == "")
            recs[idx].type = (dtype == DEAL_TYPE_BUY ? "buy" : "sell");
         if(recs[idx].open_time == 0 || dtime < recs[idx].open_time)
            recs[idx].open_time = dtime;
         if(recs[idx].comment == "")
            recs[idx].comment = HistoryDealGetString(ticket, DEAL_COMMENT);
        }

      if(is_out)
        {
         double prev = recs[idx].out_volume;
         recs[idx].close_price = (prev + vol > 0) ?
                                 (prev * recs[idx].close_price + vol * price) / (prev + vol) : price;
         recs[idx].out_volume  = prev + vol;
         if(dtime > recs[idx].close_time)
            recs[idx].close_time = dtime;
        }
     }

//--- build the file name
   string fname = InpFileName;
   if(fname == "")
     {
      MqlDateTime t;
      TimeToStruct(TimeCurrent(), t);
      fname = StringFormat("TradeJournal_%04d-%02d-%02d.csv", t.year, t.mon, t.day);
     }
   else
      if(StringFind(fname, ".csv") < 0)
         fname += ".csv";

   int flags = FILE_WRITE | FILE_TXT | FILE_ANSI;
   if(InpCommonFolder)
      flags |= FILE_COMMON;

   int fh = FileOpen(fname, flags);
   if(fh == INVALID_HANDLE)
     {
      Print("TradeJournalExporter: cannot open file '", fname, "', error ", GetLastError());
      return;
     }

   string s = InpSeparator;
   FileWriteString(fh, "PositionID" + s + "Symbol" + s + "Type" + s + "Volume" + s +
                   "OpenTime" + s + "OpenPrice" + s + "CloseTime" + s + "ClosePrice" + s +
                   "Points" + s + "Commission" + s + "Swap" + s + "NetProfit" + s +
                   "DurationMin" + s + "Comment\r\n");

   int written = 0;
   for(int r = 0; r < ArraySize(recs); r++)
     {
      if(recs[r].close_time == 0 || recs[r].open_time == 0)
         continue;                                   // still open or entry outside the period

      double pt     = SymbolInfoDouble(recs[r].symbol, SYMBOL_POINT);
      int    digits = (int)SymbolInfoInteger(recs[r].symbol, SYMBOL_DIGITS);
      double dir    = (recs[r].type == "sell" ? -1.0 : 1.0);
      double points = (pt > 0) ? dir * (recs[r].close_price - recs[r].open_price) / pt : 0;
      double durmin = (double)(recs[r].close_time - recs[r].open_time) / 60.0;

      FileWriteString(fh, StringFormat("%I64d%s", recs[r].position_id, s) +
                      recs[r].symbol + s +
                      recs[r].type + s +
                      DoubleToString(recs[r].in_volume, 2) + s +
                      TimeToString(recs[r].open_time, TIME_DATE | TIME_MINUTES) + s +
                      DoubleToString(recs[r].open_price, digits) + s +
                      TimeToString(recs[r].close_time, TIME_DATE | TIME_MINUTES) + s +
                      DoubleToString(recs[r].close_price, digits) + s +
                      DoubleToString(points, 1) + s +
                      DoubleToString(recs[r].commission, 2) + s +
                      DoubleToString(recs[r].swap, 2) + s +
                      DoubleToString(recs[r].profit, 2) + s +
                      DoubleToString(durmin, 1) + s +
                      recs[r].comment + "\r\n");
      written++;
     }

   FileClose(fh);

   string where = InpCommonFolder ? "common Files folder" : "MQL5\\Files";
   PrintFormat("TradeJournalExporter: %d closed position(s) exported to '%s' (%s), period %s -> %s",
               written, fname, where,
               TimeToString(from, TIME_DATE), TimeToString(to, TIME_DATE));
   Comment(StringFormat("Trade Journal exported: %d position(s)\nFile: %s (%s)",
                        written, fname, where));
  }

//+------------------------------------------------------------------+
//| Find record index by position id or create a new one             |
//+------------------------------------------------------------------+
int FindOrCreate(PositionRecord &arr[], const long pos_id, const string symbol)
  {
   for(int i = 0; i < ArraySize(arr); i++)
      if(arr[i].position_id == pos_id)
         return i;

   int n = ArraySize(arr);
   ArrayResize(arr, n + 1);
   arr[n].position_id = pos_id;
   arr[n].symbol      = symbol;
   arr[n].type        = "";
   arr[n].comment     = "";
   arr[n].in_volume   = 0;
   arr[n].out_volume  = 0;
   arr[n].open_time   = 0;
   arr[n].open_price  = 0;
   arr[n].close_time  = 0;
   arr[n].close_price = 0;
   arr[n].commission  = 0;
   arr[n].swap        = 0;
   arr[n].profit      = 0;
   return n;
  }
//+------------------------------------------------------------------+
