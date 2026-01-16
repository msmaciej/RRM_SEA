//+------------------------------------------------------------------+
//|                                          SimpleEA_v1-02-012c.mq5 |
//|                                  Institutional Trading Solutions |
//|             GOLDEN MASTER: Aggressive Trend | Re-Entry Fix       |
//+------------------------------------------------------------------+
#property copyright "SimpleEA Production v1.03"
#property version   "1.03"
#property strict

#include <Trade\Trade.mqh>

//--- ENUMS FOR CONFIGURATION ---
// 1. BIAS & STRATEGY
enum EBiasMode { 
   BIAS_MANUAL,   // User Manually sets Direction
   BIAS_AUTO      // EA determines Direction (EMA Slope/Cross)
};

enum EManualSide { 
   SIDE_BOTH,     // Trade Both Long and Short
   SIDE_LONG,     // Long Only (Filter Short signals)
   SIDE_SHORT     // Short Only (Filter Long signals)
};

enum EAutoStrategy { 
   STRAT_SINGLE_SLOPE, // Slope of BiasFast MA
   STRAT_PAIR_CROSS    // Cross of BiasFast > BiasSlow
}; 

enum EEmaRole { 
   ROLE_EMA1, ROLE_EMA2, ROLE_EMA3, ROLE_EMA4 
};

// 2. INDICATOR MODES
enum EMacdMode { 
   MACD_SIGNAL_ALIGN, // Buy if Main > Signal
   MACD_ZERO_CROSS    // Buy if Main > 0
};

enum ERsiMode { 
   RSI_FILTER_EXTREME, // Pass if NOT Overbought (>70)
   RSI_TREND_ABOVE_50, // Pass if RSI > 50
   RSI_CROSS_LEVEL     // Signal on Level Breakout
};

enum ECciMode { 
   CCI_TREND_ZERO,     // Buy if CCI > 0
   CCI_IMPULSE_100     // Buy if CCI > 100
};

enum EStochMode { 
   STO_CROSS_SIGNAL,   // K line crosses D line
   STO_ZONE_FILTER     // K is not in extreme zones
};

enum EBbMode { 
   BB_TREND_FOLLOW,    // Price > Middle Band
   BB_MEAN_REVERSION   // Price touches Lower Band
};

// 3. EXIT & TRAILING LOGIC
enum ETrailingMode { 
   TRAIL_NONE,       // Fixed SL only
   TRAIL_ATR,        // Volatility based (Smooth)
   TRAIL_PSAR,       // Parabolic SAR (Trend Lock)
   TRAIL_FRACTAL     // Market Structure (Swing High/Low)
};

//--- NEWS EVENT STRUCTURE ---
struct SNewsEvent {
   datetime time;
   string   currency;
   string   impact;
};

//--- GLOBAL OBJECTS ---
CTrade trade;
// Indicator Handles
int    g_h_ema1, g_h_ema2, g_h_ema3, g_h_ema4;
int    g_h_macd, g_h_rsi, g_h_cci, g_h_sto, g_h_atr, g_h_bb, g_h_psar, g_h_fractals, g_h_adx, g_h_mfi;
int    g_h_htf_ema; // Handle for HTF filter

//--- STATE VARIABLES ---
datetime g_last_bar_time = 0;
datetime g_start_time = 0; // For Report Filename
datetime g_last_trade_bar = 0; // CRITICAL: Prevents multiple trades on same candle
SNewsEvent g_news_events[]; // News Cache

//--- FUNCTION PROTOTYPES ---
bool CheckSignal_EMA1(int bias);
bool CheckSignal_ADX();
bool CheckSignal_MACD(int bias);
bool CheckSignal_RSI(int bias);
bool CheckSignal_CCI(int bias);
bool CheckSignal_MFI(int bias);
bool CheckSignal_Sto(int bias);
bool CheckSignal_BB(int bias);
bool CheckSignal_PSAR(int bias);
bool CheckSignal_Pattern123(int bias);
bool CheckSignal_RossHook(int bias);
bool CheckHTF(int bias);
bool CheckTimeFilter();
bool CheckNewsFilter();
void LoadNewsCSV();
void GenerateReport(); 
int  GetSlope(int handle);
double GetIndValue(int handle, int shift);
bool GetIndBuffer(int handle, int buf_idx, int shift, double &arr[]);
double GetFractal(int shift, int mode);
void ManageExit();
void ManageBreakeven(double atr);
void OpenTrade(ENUM_ORDER_TYPE type);
bool IsNewBar();
bool CheckBasicFilters();
int  GetBias();
int  GetHandleByRole(EEmaRole role);

//+------------------------------------------------------------------+
//| INPUT PARAMETERS (Defaults Tuned for Aggressive Trend)           |
//+------------------------------------------------------------------+
input group "=== 1. RISK & MONEY MANAGEMENT ==="
input double InpRiskPercent      = 2.0;      // Risk per trade (%)
input double InpMaxSpreadPips    = 5.0;      // Max Spread (Widened for aggressive)
input double InpMinATRPips       = 0.0;      // Min Volatility (0.0 = Disabled)

input group "=== 2. MARKET BIAS (The Narrative) ==="
input bool          InpBiasEnabled   = true;        // Master Bias Switch
input EBiasMode     InpBiasMode      = BIAS_AUTO;   // Mode: MANUAL or AUTO
input EManualSide   InpManualSide    = SIDE_BOTH;   // Manual Side
input EAutoStrategy InpAutoStrat     = STRAT_PAIR_CROSS; // Auto Strategy
input EEmaRole      InpBiasFast      = ROLE_EMA3;   // Auto Fast MA
input EEmaRole      InpBiasSlow      = ROLE_EMA4;   // Auto Slow MA

input group "=== 3. FILTERS: TIME & NEWS ==="
input bool   InpUseTimeFilter    = false;    // OFF: Trade 24/5
input int    InpStartHour        = 8;        // Start Trading Hour (0-23)
input int    InpEndHour          = 20;       // End Trading Hour (0-23)
// News Filter (Requires calendar_statement.csv in MQL5/Files)
input bool   InpUseNewsFilter    = false;    // OFF: Ignore News
input string InpNewsFileName     = "calendar_statement.csv"; // File Name
input int    InpNewsPreMin       = 60;       // Pause Mins BEFORE News
input int    InpNewsPostMin      = 60;       // Pause Mins AFTER News

input group "=== 4. REPORTING & HTF ==="
input bool   InpExportCSV        = true;     // Export Detailed Report to CSV?
input bool   InpUseHTF_Filter    = false;    // OFF: Don't wait for H4
input ENUM_TIMEFRAMES InpHTF_Period = PERIOD_H4; // HTF Period
input int    InpHTF_EmaPeriod    = 55;       // HTF EMA Period

input group "=== 5. CONFLUENCE VOTING ==="
input int    InpVotingThreshold  = 1;        // AGGRESSIVE: 1 Vote Only

input group "=== 6. INDICATOR SETTINGS ==="
// --- EMA Definitions ---
input int    InpEma1Period = 12; // Faster Signal MA
input int    InpEma2Period = 26;
input int    InpEma3Period = 34; // Bias Fast
input int    InpEma4Period = 55; // Bias Slow

// --- ACTIVE VOTES (The "Sniper" Team) ---
input bool   InpUseEmaSignal  = true;     // Vote 1: EMA Recovery (Price > EMA)
input bool   InpUseAdx        = true;     // Vote 2: ADX Strength
input int    InpAdxPeriod     = 14;
input int    InpAdxThreshold  = 20;       // ADX Level > X
input bool   InpUseMacd       = true;     // Vote 3: MACD
input EMacdMode InpMacdMode   = MACD_SIGNAL_ALIGN; 
input int    InpMacdFast      = 12;
input int    InpMacdSlow      = 26;
input int    InpMacdSig       = 9;
input bool   InpUsePsar       = true;     // Vote 4: PSAR Direction
input double InpPsarStep      = 0.02;
input double InpPsarMax       = 0.2;
input bool   InpUseRossHook   = true;     // Vote 5: Ross Hook (Fractal Break)

// --- DISABLED VOTES (Noise Reduction) ---
input bool   InpUseRsi        = false;    // OFF
input ERsiMode InpRsiMode     = RSI_FILTER_EXTREME; 
input int    InpRsiPeriod     = 14;
input double InpRsiOverbought = 70.0;
input double InpRsiOversold   = 30.0;

input bool   InpUseCci        = false;    // OFF
input ECciMode InpCciMode     = CCI_TREND_ZERO; 
input int    InpCciPeriod     = 14;

input bool   InpUseSto        = false;    // OFF
input EStochMode InpStoMode   = STO_CROSS_SIGNAL; 
input int    InpStoK          = 5;
input int    InpStoD          = 3;
input int    InpStoSlow       = 3;

input bool   InpUseMfi        = false;    // OFF
input int    InpMfiPeriod     = 14;
input double InpMfiLevel      = 50.0;     // Trend Threshold

input bool   InpUseBB         = false;    // OFF
input EBbMode InpBbMode       = BB_TREND_FOLLOW; 
input int    InpBbPeriod      = 20;
input double InpBbDev         = 2.0;

input bool   InpUsePattern123 = false;    // OFF

input group "=== 7. EXIT & BREAKEVEN ==="
input double InpSLMultiplier    = 3.0;    // WIDER SL (3.0 ATR)
input double InpTPMultiplier    = 6.0;    // BIGGER TP (6.0 ATR)
input bool   InpUseBreakeven    = true;   // ON: Free Ride
input double InpBE_TriggerATR   = 1.5;    // Lock after 1.5 ATR
input double InpBE_BufferATR    = 0.2;    // Lock at Entry + 0.2
input ETrailingMode InpTrailMode = TRAIL_ATR; // Options: NONE, ATR, PSAR, FRACTAL
input double InpTrailATRMult    = 2.0;    // WIDER Trail

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("=== SimpleEA v1.03 Production Initializing ===");
   g_start_time = TimeCurrent(); // Capture start time for filename
   
   // 1. Initialize Indicators
   g_h_ema1 = iMA(_Symbol, PERIOD_CURRENT, InpEma1Period, 0, MODE_EMA, PRICE_CLOSE);
   g_h_ema2 = iMA(_Symbol, PERIOD_CURRENT, InpEma2Period, 0, MODE_EMA, PRICE_CLOSE);
   g_h_ema3 = iMA(_Symbol, PERIOD_CURRENT, InpEma3Period, 0, MODE_EMA, PRICE_CLOSE);
   g_h_ema4 = iMA(_Symbol, PERIOD_CURRENT, InpEma4Period, 0, MODE_EMA, PRICE_CLOSE);
   g_h_atr  = iATR(_Symbol, PERIOD_CURRENT, 14); 
   g_h_macd = iMACD(_Symbol, PERIOD_CURRENT, InpMacdFast, InpMacdSlow, InpMacdSig, PRICE_CLOSE);
   g_h_rsi  = iRSI(_Symbol, PERIOD_CURRENT, InpRsiPeriod, PRICE_CLOSE);
   g_h_cci  = iCCI(_Symbol, PERIOD_CURRENT, InpCciPeriod, PRICE_CLOSE);
   g_h_adx  = iADX(_Symbol, PERIOD_CURRENT, InpAdxPeriod);
   g_h_mfi  = iMFI(_Symbol, PERIOD_CURRENT, InpMfiPeriod, VOLUME_TICK); 
   g_h_sto  = iStochastic(_Symbol, PERIOD_CURRENT, InpStoK, InpStoD, InpStoSlow, MODE_SMA, STO_LOWHIGH);
   g_h_bb   = iBands(_Symbol, PERIOD_CURRENT, InpBbPeriod, 0, InpBbDev, PRICE_CLOSE);
   g_h_psar = iSAR(_Symbol, PERIOD_CURRENT, InpPsarStep, InpPsarMax); 
   g_h_fractals = iFractals(_Symbol, PERIOD_CURRENT);
   
   // HTF Indicator
   if(InpUseHTF_Filter) {
      g_h_htf_ema = iMA(_Symbol, InpHTF_Period, InpHTF_EmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
      if(g_h_htf_ema == INVALID_HANDLE) Print("Warning: Failed to create HTF Handle");
   }

   if(g_h_ema1 == INVALID_HANDLE || g_h_atr == INVALID_HANDLE) return INIT_FAILED;
   
   // 2. Load News if Enabled
   if(InpUseNewsFilter) LoadNewsCSV();
   
   // 3. Print Active Configuration (Audit Trail)
   Print("------------------------------------------");
   Print("--- Active Strategy Configuration ---");
   Print("Symbol: ", _Symbol);
   Print("Bias Mode: ", EnumToString(InpBiasMode));
   Print("HTF Filter: ", InpUseHTF_Filter ? "ON ("+EnumToString(InpHTF_Period)+")" : "OFF");
   Print("Voting Threshold: ", InpVotingThreshold, " votes required.");
   
   Print("--- Filters ---");
   Print("Time Filter: ", InpUseTimeFilter ? "ON ("+(string)InpStartHour+":00 - "+(string)InpEndHour+":00)" : "OFF");
   Print("News Filter: ", InpUseNewsFilter ? "ON ("+(string)ArraySize(g_news_events)+" events loaded)" : "OFF");
   Print("Breakeven: ", InpUseBreakeven ? "ON" : "OFF");
   Print("Reporting: ", InpExportCSV ? "ON" : "OFF");
   
   Print("--- Enabled Indicators ---");
   if(InpUseEmaSignal) Print("+ Vote: EMA Recovery");
   if(InpUseAdx)       Print("+ Vote: ADX Strength");
   if(InpUseMacd)      Print("+ Vote: MACD (", EnumToString(InpMacdMode), ")");
   if(InpUseRsi)       Print("+ Vote: RSI (", EnumToString(InpRsiMode), ")");
   if(InpUseCci)       Print("+ Vote: CCI");
   if(InpUseMfi)       Print("+ Vote: MFI (Volume)");
   if(InpUseSto)       Print("+ Vote: Stochastic");
   if(InpUseBB)        Print("+ Vote: Bollinger");
   if(InpUsePsar)      Print("+ Vote: PSAR");
   if(InpUsePattern123) Print("+ Vote: Mark Crisp 1-2-3");
   if(InpUseRossHook)  Print("+ Vote: Ross Hook");
   Print("------------------------------------------");
   
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) {
   IndicatorRelease(g_h_ema1); IndicatorRelease(g_h_ema2);
   IndicatorRelease(g_h_ema3); IndicatorRelease(g_h_ema4);
   IndicatorRelease(g_h_atr); IndicatorRelease(g_h_macd);
   IndicatorRelease(g_h_rsi); IndicatorRelease(g_h_cci);
   IndicatorRelease(g_h_adx); IndicatorRelease(g_h_mfi);
   IndicatorRelease(g_h_sto); IndicatorRelease(g_h_bb);
   IndicatorRelease(g_h_psar); IndicatorRelease(g_h_fractals);
   if(InpUseHTF_Filter) IndicatorRelease(g_h_htf_ema);
   
   // --- GENERATE REPORT IF ENABLED ---
   if(InpExportCSV) GenerateReport();
   
   Print("=== SimpleEA v1.03 Production Shutdown ===");
}

//+------------------------------------------------------------------+
//| Main OnTick                                                      |
//+------------------------------------------------------------------+
void OnTick()
{
   // 1. Manage Open Positions (Tick based)
   if(PositionSelect(_Symbol)) {
      ManageExit();
      return; 
   }

   // ---------------------------------------------------------
   // CRITICAL LOGIC FIX: PREVENT MULTIPLE TRADES ON SAME CANDLE
   // ---------------------------------------------------------
   datetime current_bar_time = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(g_last_trade_bar == current_bar_time) {
      return; // We already traded on this candle. Wait for next one.
   }

   // 2. Filters & New Bar
   if(!IsNewBar()) return;
   if(!CheckBasicFilters()) return;
   
   // Expert Filters
   if(InpUseTimeFilter && !CheckTimeFilter()) return;
   if(InpUseNewsFilter && !CheckNewsFilter()) return;

   // 3. BIAS (Chart Timeframe)
   int bias = GetBias();
   if(bias == 0) return;
   
   // 4. MASTER FILTER: HTF
   if(InpUseHTF_Filter) {
      if(!CheckHTF(bias)) return; // Veto if HTF disagrees
   }

   // 5. VOTING
   int votes = 0;
   
   if(InpUseEmaSignal && CheckSignal_EMA1(bias))    votes++;
   if(InpUseAdx       && CheckSignal_ADX())         votes++; 
   if(InpUseMacd      && CheckSignal_MACD(bias))    votes++;
   if(InpUseRsi       && CheckSignal_RSI(bias))     votes++;
   if(InpUseCci       && CheckSignal_CCI(bias))     votes++;
   if(InpUseMfi       && CheckSignal_MFI(bias))     votes++;
   if(InpUseSto       && CheckSignal_Sto(bias))     votes++;
   if(InpUseBB        && CheckSignal_BB(bias))      votes++;
   if(InpUsePsar      && CheckSignal_PSAR(bias))    votes++;
   if(InpUsePattern123 && CheckSignal_Pattern123(bias)) votes++;
   if(InpUseRossHook   && CheckSignal_RossHook(bias))   votes++;

   // 6. EXECUTE
   if(votes >= InpVotingThreshold) {
      if(bias == 1)      OpenTrade(ORDER_TYPE_BUY);
      else if(bias == -1) OpenTrade(ORDER_TYPE_SELL);
   }
}

//+------------------------------------------------------------------+
//| NEW: REPORT GENERATION (Excel Ready)                             |
//+------------------------------------------------------------------+
void GenerateReport() {
   if(!MQLInfoInteger(MQL_TESTER)) return; // Only in Tester
   
   string start_str = TimeToString(g_start_time, TIME_DATE);
   string end_str   = TimeToString(TimeCurrent(), TIME_DATE);
   StringReplace(start_str, ".", "-"); 
   StringReplace(end_str, ".", "-");
   
   // Format: Report_SimpleEA_EURUSD_H1_2024-01-01_2025-01-01.csv
   string filename = StringFormat("Report_SimpleEA_%s_%s_%s_%s.csv", 
                                  _Symbol, 
                                  EnumToString(_Period), 
                                  start_str, 
                                  end_str);
                                  
   // FIX: Removed FILE_COMMON. Now saves to MQL5/Files (Standard Data Folder)
   int handle = FileOpen(filename, FILE_CSV|FILE_WRITE|FILE_ANSI, ",");
   if(handle == INVALID_HANDLE) {
      Print("Report: Failed to write ", filename);
      return;
   }
   
   // 1. METRICS HEADER
   FileWrite(handle, "--- TEST STATISTICS ---");
   FileWrite(handle, "Metric", "Value");
   FileWrite(handle, "Net Profit", DoubleToString(TesterStatistics(STAT_PROFIT), 2));
   FileWrite(handle, "Total Trades", DoubleToString(TesterStatistics(STAT_TRADES), 0));
   FileWrite(handle, "Profit Factor", DoubleToString(TesterStatistics(STAT_PROFIT_FACTOR), 2));
   FileWrite(handle, "Sharpe Ratio", DoubleToString(TesterStatistics(STAT_SHARPE_RATIO), 2));
   FileWrite(handle, "Drawdown Equity %", DoubleToString(TesterStatistics(STAT_EQUITY_DDREL_PERCENT), 2) + "%");
   FileWrite(handle, "Win Rate %", DoubleToString((TesterStatistics(STAT_PROFIT_TRADES)/TesterStatistics(STAT_TRADES))*100, 1) + "%");
   FileWrite(handle, ""); // Spacer
   
   // 2. TRADES LIST (For Excel Graphs)
   FileWrite(handle, "--- DEAL HISTORY (Graph Data) ---");
   FileWrite(handle, "Time", "Symbol", "Type", "Volume", "Price", "Profit", "Balance");
   
   HistorySelect(0, TimeCurrent());
   int deals = HistoryDealsTotal();
   double balance = TesterStatistics(STAT_INITIAL_DEPOSIT); // Start balance
   
   for(int i=0; i<deals; i++) {
      ulong ticket = HistoryDealGetTicket(i);
      long type = HistoryDealGetInteger(ticket, DEAL_TYPE);
      
      // We only care about Entry/Exit deals (Buy/Sell), not Balance ops usually
      if(type == DEAL_TYPE_BUY || type == DEAL_TYPE_SELL) {
         datetime time = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
         double vol    = HistoryDealGetDouble(ticket, DEAL_VOLUME);
         double price  = HistoryDealGetDouble(ticket, DEAL_PRICE);
         double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT) + 
                         HistoryDealGetDouble(ticket, DEAL_SWAP) + 
                         HistoryDealGetDouble(ticket, DEAL_COMMISSION);
         
         balance += profit; // Running balance calc
         
         string s_type = (type==DEAL_TYPE_BUY) ? "Buy" : "Sell";
         string s_time = TimeToString(time, TIME_DATE|TIME_MINUTES);
         
         FileWrite(handle, s_time, _Symbol, s_type, DoubleToString(vol, 2), DoubleToString(price, 5), DoubleToString(profit, 2), DoubleToString(balance, 2));
      }
   }
   
   FileClose(handle);
   Print(">> REPORT SAVED: ", filename, " (Check MQL5/Files) <<");
}

//+------------------------------------------------------------------+
//| SIGNAL CHECKS                                                    |
//+------------------------------------------------------------------+
bool CheckSignal_EMA1(int bias) {
   double price = iClose(_Symbol, PERIOD_CURRENT, 1);
   double ema   = GetIndValue(g_h_ema1, 1);
   
   if(bias == 1) return (price > ema);
   if(bias == -1) return (price < ema);
   return false;
}

bool CheckSignal_ADX() {
   return (GetIndValue(g_h_adx, 1) > InpAdxThreshold);
}

bool CheckSignal_MFI(int bias) {
   double mfi = GetIndValue(g_h_mfi, 1);
   
   if(bias == 1) return (mfi > InpMfiLevel);
   if(bias == -1) return (mfi < (100 - InpMfiLevel)); 
   return false;
}

bool CheckSignal_MACD(int bias) {
   double main[], sig[];
   if(!GetIndBuffer(g_h_macd, 0, 1, main)) return false;
   if(!GetIndBuffer(g_h_macd, 1, 1, sig)) return false;
   
   if(InpMacdMode == MACD_SIGNAL_ALIGN) {
      if(bias == 1) return (main[0] > sig[0]);
      if(bias == -1) return (main[0] < sig[0]);
   }
   if(InpMacdMode == MACD_ZERO_CROSS) {
      if(bias == 1) return (main[0] > 0);
      if(bias == -1) return (main[0] < 0);
   }
   return false;
}

bool CheckSignal_RSI(int bias) {
   double rsi = GetIndValue(g_h_rsi, 1);
   
   if(InpRsiMode == RSI_FILTER_EXTREME) {
      if(bias == 1) return (rsi < InpRsiOverbought);
      if(bias == -1) return (rsi > InpRsiOversold);
   }
   if(InpRsiMode == RSI_TREND_ABOVE_50) {
      if(bias == 1) return (rsi > 50);
      if(bias == -1) return (rsi < 50);
   }
   if(InpRsiMode == RSI_CROSS_LEVEL) {
       if(bias == 1) return (rsi > InpRsiOversold); 
       if(bias == -1) return (rsi < InpRsiOverbought);
   }
   return false;
}

bool CheckSignal_CCI(int bias) {
   double cci = GetIndValue(g_h_cci, 1);
   
   if(InpCciMode == CCI_TREND_ZERO) {
      if(bias == 1) return (cci > 0);
      if(bias == -1) return (cci < 0);
   }
   if(InpCciMode == CCI_IMPULSE_100) {
      if(bias == 1) return (cci > 100);
      if(bias == -1) return (cci < -100);
   }
   return false;
}

bool CheckSignal_Sto(int bias) {
   double k[1], d[1];
   CopyBuffer(g_h_sto, 0, 1, 1, k); 
   CopyBuffer(g_h_sto, 1, 1, 1, d);
   
   if(InpStoMode == STO_CROSS_SIGNAL) {
      if(bias == 1) return (k[0] > d[0]);
      if(bias == -1) return (k[0] < d[0]);
   }
   if(InpStoMode == STO_ZONE_FILTER) {
      if(bias == 1) return (k[0] < 80);
      if(bias == -1) return (k[0] > 20); 
   }
   return false;
}

bool CheckSignal_BB(int bias) {
   double mid = GetIndValue(g_h_bb, 0); 
   double lower = GetIndValue(g_h_bb, 2); 
   double close = iClose(_Symbol, PERIOD_CURRENT, 1);
   
   if(InpBbMode == BB_TREND_FOLLOW) {
      if(bias == 1) return (close > mid);
      if(bias == -1) return (close < mid);
   }
   if(InpBbMode == BB_MEAN_REVERSION) {
       if(bias == 1) return (iLow(_Symbol, PERIOD_CURRENT, 1) < lower);
       
       double upper = GetIndValue(g_h_bb, 1);
       if(bias == -1) return (iHigh(_Symbol, PERIOD_CURRENT, 1) > upper);
   }
   return false;
}

bool CheckSignal_PSAR(int bias) {
   if(!InpUsePsar) return false;
   
   double psar = GetIndValue(g_h_psar, 1); 
   double close = iClose(_Symbol, PERIOD_CURRENT, 1);
   
   if(bias == 1) return (close > psar);
   if(bias == -1) return (close < psar);
   return false;
}

bool CheckSignal_Pattern123(int bias) {
   double f1_val=0, f2_val=0, f3_val=0; 
   int f1_idx=0, f2_idx=0, f3_idx=0;
   
   if(bias == 1) { // BUY
      int found_down = 0; 
      int found_up = 0;
      for(int i=2; i<40; i++) {
         double up = GetFractal(i, 0); 
         double down = GetFractal(i, 1); 
         
         if(down > 0) {
            if(found_down == 0) { f3_val = down; f3_idx = i; found_down++; } 
            else if(found_down == 1 && found_up == 1) { f1_val = down; f1_idx = i; found_down++; break; } 
         }
         if(up > 0) { 
            if(found_down == 1 && found_up == 0) { f2_val = up; f2_idx = i; found_up++; } 
         }
      }
      if(f1_val > 0 && f2_val > 0 && f3_val > 0) { 
         if(f3_val > f1_val) { 
            if(iClose(_Symbol, PERIOD_CURRENT, 1) > f2_val) return true; 
         } 
      }
   }
   
   if(bias == -1) { // SELL
      int found_up = 0; 
      int found_down = 0;
      for(int i=2; i<40; i++) {
         double up = GetFractal(i, 0); 
         double down = GetFractal(i, 1); 
         
         if(up > 0) {
            if(found_up == 0) { f3_val = up; f3_idx = i; found_up++; } 
            else if(found_up == 1 && found_down == 1) { f1_val = up; f1_idx = i; found_up++; break; } 
         }
         if(down > 0) { 
            if(found_up == 1 && found_down == 0) { f2_val = down; f2_idx = i; found_down++; } 
         }
      }
      if(f1_val > 0 && f2_val > 0 && f3_val > 0) { 
         if(f3_val < f1_val) { 
            if(iClose(_Symbol, PERIOD_CURRENT, 1) < f2_val) return true; 
         } 
      }
   }
   return false;
}

bool CheckSignal_RossHook(int bias) {
   for(int i=2; i<=20; i++) {
      double up = GetFractal(i, 0); 
      double down = GetFractal(i, 1);
      
      if(bias == 1 && up > 0) 
         return (iClose(_Symbol, PERIOD_CURRENT, 1) > up); 
         
      if(bias == -1 && down > 0) 
         return (iClose(_Symbol, PERIOD_CURRENT, 1) < down); 
   }
   return false;
}

//+------------------------------------------------------------------+
//| UTILITIES & FILTERS                                              |
//+------------------------------------------------------------------+
bool IsNewBar() { 
   datetime c = iTime(_Symbol, PERIOD_CURRENT, 0); 
   if(c != g_last_bar_time) { 
      g_last_bar_time = c; 
      return true; 
   } 
   return false; 
}

int GetHandleByRole(EEmaRole role) { 
   if(role==ROLE_EMA1) return g_h_ema1; 
   if(role==ROLE_EMA2) return g_h_ema2; 
   if(role==ROLE_EMA3) return g_h_ema3; 
   return g_h_ema4; 
}

double GetIndValue(int handle, int shift) { 
   double b[1]; 
   if(CopyBuffer(handle,0,shift,1,b)>0) return b[0]; 
   return 0.0; 
}

bool GetIndBuffer(int handle, int buf, int shift, double &a[]) { 
   return (CopyBuffer(handle,buf,shift,1,a)>0); 
}

int GetSlope(int handle) { 
   double c=GetIndValue(handle,1); 
   double p=GetIndValue(handle,2); 
   return (c>p)?1:(c<p)?-1:0; 
}

double GetFractal(int shift, int mode) { 
   double r[1]; 
   if(CopyBuffer(g_h_fractals,mode,shift,1,r)>0 && r[0]!=DBL_MAX) return r[0]; 
   return 0.0; 
}

bool CheckBasicFilters() { 
   double s = (SymbolInfoDouble(_Symbol, SYMBOL_ASK)-SymbolInfoDouble(_Symbol, SYMBOL_BID))/_Point; 
   if(s > InpMaxSpreadPips * 10) return false;
   
   return (GetIndValue(g_h_atr,1)/(_Point*10) >= InpMinATRPips);
}

int GetBias() {
   if(!InpBiasEnabled) return 0;
   
   if(InpBiasMode == BIAS_MANUAL) {
      if(InpManualSide == SIDE_LONG) return 1;
      if(InpManualSide == SIDE_SHORT) return -1;
      return GetSlope(g_h_ema4);
   }
   
   int hf = GetHandleByRole(InpBiasFast); 
   int hs = GetHandleByRole(InpBiasSlow);
   
   if(InpAutoStrat == STRAT_SINGLE_SLOPE) return GetSlope(hf);
   
   double f = GetIndValue(hf,1); 
   double s = GetIndValue(hs,1);
   return (f>s)?1:(f<s)?-1:0;
}

bool CheckHTF(int bias) {
   double b[2]; 
   if(CopyBuffer(g_h_htf_ema,0,1,2,b)<2) return true;
   return (bias == ((b[1]>b[0])?1:-1));
}

bool CheckTimeFilter() {
   MqlDateTime dt; 
   TimeCurrent(dt);
   
   if(InpStartHour < InpEndHour) 
      return (dt.hour >= InpStartHour && dt.hour < InpEndHour);
   else 
      return (dt.hour >= InpStartHour || dt.hour < InpEndHour);
}

bool CheckNewsFilter() {
   if(ArraySize(g_news_events) == 0) return true; 
   
   datetime now = TimeCurrent();
   string base = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_BASE);
   string profit = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_PROFIT);
   
   for(int i=0; i<ArraySize(g_news_events); i++) {
      if(g_news_events[i].currency != base && g_news_events[i].currency != profit && g_news_events[i].currency != "USD") continue;
      
      long diff = (long)now - (long)g_news_events[i].time;
      
      if(diff < 0 && MathAbs(diff) <= InpNewsPreMin * 60) return false;
      if(diff >= 0 && diff <= InpNewsPostMin * 60) return false;
   }
   return true;
}

void LoadNewsCSV() {
   int handle = FileOpen(InpNewsFileName, FILE_READ|FILE_CSV|FILE_ANSI, ",");
   if(handle == INVALID_HANDLE) { 
      Print("News: File Not Found"); 
      return; 
   }
   
   if(!FileIsEnding(handle)) { 
      string d = FileReadString(handle); 
      if(StringFind(d, "Date") >= 0) { 
         FileReadString(handle); FileReadString(handle); FileReadString(handle); 
      } else {
         FileSeek(handle, 0, SEEK_SET); 
      }
   }
   
   while(!FileIsEnding(handle)) {
      string d1 = FileReadString(handle); 
      string d2 = FileReadString(handle); 
      string d3 = FileReadString(handle);
      string full = d1 + "," + d2 + "," + d3; 
      StringReplace(full, "\"", "");
      
      string event = FileReadString(handle); 
      string impact = FileReadString(handle); 
      string curr = FileReadString(handle);
      
      if(impact == "High" || impact == "Medium") {
         string p[]; StringSplit(full, ',', p);
         if(ArraySize(p) >= 3) {
            string db = p[1]; StringTrimLeft(db); 
            string md[]; StringSplit(db, ' ', md);
            int m = 1; 
            if(md[0]=="February")m=2; else if(md[0]=="March")m=3; else if(md[0]=="April")m=4; 
            else if(md[0]=="May")m=5; else if(md[0]=="June")m=6; else if(md[0]=="July")m=7; 
            else if(md[0]=="August")m=8; else if(md[0]=="September")m=9; else if(md[0]=="October")m=10; 
            else if(md[0]=="November")m=11; else if(md[0]=="December")m=12;
            
            datetime t = StringToTime(p[0] + "." + (string)m + "." + md[1] + " " + p[2]);
            int s = ArraySize(g_news_events); ArrayResize(g_news_events, s+1);
            g_news_events[s].time = t; 
            g_news_events[s].currency = curr; 
            g_news_events[s].impact = impact;
         }
      }
   }
   FileClose(handle);
}

//+------------------------------------------------------------------+
//| EXECUTION & MANAGEMENT                                           |
//+------------------------------------------------------------------+
void OpenTrade(ENUM_ORDER_TYPE type) {
   // Universal Lot Calculation
   double atr = GetIndValue(g_h_atr, 1);
   double sl_dist = atr * InpSLMultiplier;
   double tp_dist = atr * InpTPMultiplier;
   
   double price = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl = (type == ORDER_TYPE_BUY) ? price - sl_dist : price + sl_dist;
   double tp = (type == ORDER_TYPE_BUY) ? price + tp_dist : price - tp_dist;
   
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   sl = NormalizeDouble(sl, digits); 
   tp = NormalizeDouble(tp, digits);
   
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk = balance * (InpRiskPercent / 100.0);
   double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tick_val  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   
   double lot = 0.01;
   if(tick_size > 0 && tick_val > 0) {
      double loss_per_lot = (sl_dist / tick_size) * tick_val;
      if(loss_per_lot > 0) lot = risk / loss_per_lot;
   }
   
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   lot = MathFloor(lot / step) * step;
   double min = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if(lot < min) lot = min;
   
   if(trade.PositionOpen(_Symbol, type, lot, price, sl, tp, "SimpleEA v1.03 Production")) {
      Print("=== TRADE OPENED ===");
      Print("Type: ", EnumToString(type));
      Print("Price: ", price);
      Print("Lots: ", lot);
      Print("SL: ", sl, " (", DoubleToString(sl_dist/_Point, 0), " pts)");
      Print("Risk: ", DoubleToString(risk, 2));
      Print("====================");
      
      // RECORD TRADE TIME TO PREVENT RE-ENTRY
      g_last_trade_bar = iTime(_Symbol, PERIOD_CURRENT, 0);
      
   } else {
      Print("Trade Error: ", GetLastError());
   }
}

void ManageExit() {
   if(!PositionSelect(_Symbol)) return;
   
   double atr = GetIndValue(g_h_atr, 1);
   if(InpUseBreakeven) ManageBreakeven(atr);
   if(InpTrailMode == TRAIL_NONE) return;
   
   ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   double current_sl = PositionGetDouble(POSITION_SL);
   double current_price = PositionGetDouble(POSITION_PRICE_CURRENT);
   double new_sl = 0.0;
   
   if(InpTrailMode == TRAIL_ATR) {
      double dist = atr * InpTrailATRMult;
      new_sl = (type == POSITION_TYPE_BUY) ?
         SymbolInfoDouble(_Symbol, SYMBOL_BID) - dist : SymbolInfoDouble(_Symbol, SYMBOL_ASK) + dist;
   }
   else if(InpTrailMode == TRAIL_PSAR) {
      new_sl = GetIndValue(g_h_psar, 1);
      if((type == POSITION_TYPE_BUY && new_sl > current_price) || 
         (type == POSITION_TYPE_SELL && new_sl < current_price)) return;
   }
   else if(InpTrailMode == TRAIL_FRACTAL) {
      for(int i=2; i<20; i++) {
         double up = GetFractal(i, 0); 
         double down = GetFractal(i, 1);
         if(type == POSITION_TYPE_BUY && down > 0) { new_sl = down; break; }
         if(type == POSITION_TYPE_SELL && up > 0) { new_sl = up; break; }
      }
   }

   if(new_sl != 0.0) {
      int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
      new_sl = NormalizeDouble(new_sl, digits);
      bool modify = false;
      
      if(type == POSITION_TYPE_BUY) { 
         if(new_sl > current_sl && new_sl < current_price) modify = true; 
      } 
      else { 
         if((new_sl < current_sl || current_sl == 0) && new_sl > current_price) modify = true; 
      }
      
      if(modify) trade.PositionModify(_Symbol, new_sl, PositionGetDouble(POSITION_TP));
   }
}

void ManageBreakeven(double atr) {
   if(PositionGetInteger(POSITION_MAGIC) == 0 && StringFind(PositionGetString(POSITION_COMMENT), "SimpleEA") < 0) return; 
   
   ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   double open = PositionGetDouble(POSITION_PRICE_OPEN);
   double curr = PositionGetDouble(POSITION_PRICE_CURRENT);
   double sl = PositionGetDouble(POSITION_SL);
   double trig = atr * InpBE_TriggerATR;
   double buff = atr * InpBE_BufferATR;
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   
   if(type == POSITION_TYPE_BUY && curr >= open + trig) {
      double t_sl = NormalizeDouble(open + buff, digits);
      if(sl < t_sl) trade.PositionModify(_Symbol, t_sl, PositionGetDouble(POSITION_TP));
   }
   else if(type == POSITION_TYPE_SELL && curr <= open - trig) {
      double t_sl = NormalizeDouble(open - buff, digits);
      if(sl > t_sl || sl == 0) trade.PositionModify(_Symbol, t_sl, PositionGetDouble(POSITION_TP));
   }
}
//+------------------------------------------------------------------+