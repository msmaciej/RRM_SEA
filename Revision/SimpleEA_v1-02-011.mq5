//+------------------------------------------------------------------+
//|                                           SimpleEA_v1-02-011.mq5 |
//|                                  Institutional Trading Solutions |
//|               Full Production: Audit Trail, Universal Lots, News |
//+------------------------------------------------------------------+
#property copyright "SimpleEA Redesign v1.02.011"
#property version   "102.011"
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
// State Variables
datetime g_last_bar_time = 0;
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
//| INPUT PARAMETERS                                                 |
//+------------------------------------------------------------------+
input group "=== 1. RISK & MONEY MANAGEMENT ==="
input double InpRiskPercent      = 2.0;      // Risk per trade (%)
input double InpMaxSpreadPips    = 3.0;      // Max Spread (Pips)
input double InpMinATRPips       = 5.0;      // Min Volatility (ATR Pips)

input group "=== 2. MARKET BIAS (The Narrative) ==="
input bool          InpBiasEnabled   = true;        // Master Bias Switch
input EBiasMode     InpBiasMode      = BIAS_AUTO;   // Mode: MANUAL or AUTO
input EManualSide   InpManualSide    = SIDE_BOTH;   // Manual Side
input EAutoStrategy InpAutoStrat     = STRAT_PAIR_CROSS; // Auto Strategy
input EEmaRole      InpBiasFast      = ROLE_EMA3;   // Auto Fast MA
input EEmaRole      InpBiasSlow      = ROLE_EMA4;   // Auto Slow MA

input group "=== 3. FILTERS: TIME & NEWS ==="
input bool   InpUseTimeFilter    = true;     // Use Time Scheduler?
input int    InpStartHour        = 8;        // Start Trading Hour (0-23)
input int    InpEndHour          = 20;       // End Trading Hour (0-23)
input bool   InpUseNewsFilter    = true;     // Use CSV News Filter?
input string InpNewsFileName     = "calendar_statement.csv"; // File Name (MQL5/Files)
input int    InpNewsPreMin       = 60;       // Pause Mins BEFORE News
input int    InpNewsPostMin      = 60;       // Pause Mins AFTER News

input group "=== 4. HTF CONTEXT (Master Filter) ==="
input bool           InpUseHTF_Filter = false;       // Master Filter: Check Higher Timeframe?
input ENUM_TIMEFRAMES InpHTF_Period   = PERIOD_H4;   // HTF Period (e.g. H4, D1)
input int            InpHTF_EmaPeriod = 55;          // HTF EMA Period for Trend

input group "=== 5. CONFLUENCE VOTING ==="
input int    InpVotingThreshold  = 4;     // MINIMUM Votes required to Trade

input group "=== 6. INDICATOR SETTINGS ==="
// EMA Definition
input int    InpEma1Period = 13;
input int    InpEma2Period = 21;
input int    InpEma3Period = 34;
input int    InpEma4Period = 55;

// Vote 1: EMA Signal
input bool   InpUseEmaSignal  = true;     // Vote 1: Price vs EMA1 (Recovery)

// Vote 2: ADX
input bool   InpUseAdx        = true;     // Vote 2: ADX Trend Strength
input int    InpAdxPeriod     = 14;
input int    InpAdxThreshold  = 20;       // ADX Level > X

// Vote 3: MACD
input bool   InpUseMacd       = true;     // Vote 3: MACD
input EMacdMode InpMacdMode   = MACD_SIGNAL_ALIGN; // Options: SIGNAL_ALIGN, ZERO_CROSS
input int    InpMacdFast      = 12;
input int    InpMacdSlow      = 26;
input int    InpMacdSig       = 9;

// Vote 4: RSI
input bool   InpUseRsi        = true;     // Vote 4: RSI
input ERsiMode InpRsiMode     = RSI_FILTER_EXTREME; // Options: FILTER_EXTREME, TREND_ABOVE_50
input int    InpRsiPeriod     = 14;
input double InpRsiOverbought = 70.0;
input double InpRsiOversold   = 30.0;

// Vote 5: CCI
input bool   InpUseCci        = true;     // Vote 5: CCI Momentum
input ECciMode InpCciMode     = CCI_TREND_ZERO; // Options: TREND_ZERO (>0), IMPULSE_100 (>100)
input int    InpCciPeriod     = 14;

// Vote 6: MFI (Volume)
input bool   InpUseMfi        = true;     // Vote 6: Money Flow Index (Volume)
input int    InpMfiPeriod     = 14;
input double InpMfiLevel      = 50.0;     // Trend Threshold

// Vote 7: Stochastic
input bool   InpUseSto        = false;    // Vote 7: Stochastic
input EStochMode InpStoMode   = STO_CROSS_SIGNAL; // Options: CROSS_SIGNAL, ZONE_FILTER
input int    InpStoK          = 5;
input int    InpStoD          = 3;
input int    InpStoSlow       = 3;

// Vote 8: Bollinger
input bool   InpUseBB         = false;    // Vote 8: Bollinger Bands
input EBbMode InpBbMode       = BB_TREND_FOLLOW; // Options: TREND_FOLLOW, MEAN_REVERSION
input int    InpBbPeriod      = 20;
input double InpBbDev         = 2.0;

// Vote 9: PSAR
input bool   InpUsePsar       = false;    // Vote 9: PSAR Direction
input double InpPsarStep      = 0.02;
input double InpPsarMax       = 0.2;

// Vote 10: 1-2-3 Pattern
input bool   InpUsePattern123 = false;    // Vote 10: Mark Crisp 1-2-3 Pattern

// Vote 11: Ross Hook
input bool   InpUseRossHook   = false;    // Vote 11: Ross Hook (Simple Breakout)

input group "=== 7. EXIT & BREAKEVEN ==="
input double InpSLMultiplier    = 2.0;    // SL (ATR Multiplier)
input double InpTPMultiplier    = 4.0;    // TP (ATR Multiplier)
input bool   InpUseBreakeven    = true;   // Move SL to Entry?
input double InpBE_TriggerATR   = 1.0;    // Breakeven Trigger (ATR distance)
input double InpBE_BufferATR    = 0.1;    // Breakeven Buffer (Profit lock)
input ETrailingMode InpTrailMode = TRAIL_ATR; // Options: NONE, ATR, PSAR, FRACTAL
input double InpTrailATRMult    = 1.5;    // ATR Trail Distance

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("=== SimpleEA v1.02.011 Initializing ===");
   
   // 1. Initialize Indicators
   g_h_ema1 = iMA(_Symbol, PERIOD_CURRENT, InpEma1Period, 0, MODE_EMA, PRICE_CLOSE);
   g_h_ema2 = iMA(_Symbol, PERIOD_CURRENT, InpEma2Period, 0, MODE_EMA, PRICE_CLOSE);
   g_h_ema3 = iMA(_Symbol, PERIOD_CURRENT, InpEma3Period, 0, MODE_EMA, PRICE_CLOSE);
   g_h_ema4 = iMA(_Symbol, PERIOD_CURRENT, InpEma4Period, 0, MODE_EMA, PRICE_CLOSE);
   g_h_atr  = iATR(_Symbol, PERIOD_CURRENT, 14); 
   
   // Optional Indicators
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
   Print("=== SimpleEA v1.02.011 Shutdown ===");
}

//+------------------------------------------------------------------+
//| Main OnTick                                                      |
//+------------------------------------------------------------------+
void OnTick()
{
   // 1. Manage Open Positions
   if(PositionSelect(_Symbol)) {
      ManageExit();
      return; 
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
//| SIGNAL CHECKS                                                    |
//+------------------------------------------------------------------+
bool CheckSignal_EMA1(int bias) {
   double price = iClose(_Symbol, PERIOD_CURRENT, 1);
   double ema   = GetIndValue(g_h_ema1, 1);
   return (bias == 1) ? (price > ema) : (price < ema);
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
   if(!GetIndBuffer(g_h_macd, 0, 1, main) || !GetIndBuffer(g_h_macd, 1, 1, sig)) return false;
   if(InpMacdMode == MACD_SIGNAL_ALIGN) return (bias == 1) ? (main[0] > sig[0]) : (main[0] < sig[0]);
   if(InpMacdMode == MACD_ZERO_CROSS)   return (bias == 1) ? (main[0] > 0) : (main[0] < 0);
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
      return (bias == 1) ? (cci > 0) : (cci < 0);
   }
   if(InpCciMode == CCI_IMPULSE_100) {
      return (bias == 1) ? (cci > 100) : (cci < -100);
   }
   return false;
}

bool CheckSignal_Sto(int bias) {
   double k[1], d[1];
   CopyBuffer(g_h_sto, 0, 1, 1, k);
   CopyBuffer(g_h_sto, 1, 1, 1, d);
   if(InpStoMode == STO_CROSS_SIGNAL) return (bias == 1) ? (k[0] > d[0]) : (k[0] < d[0]);
   if(InpStoMode == STO_ZONE_FILTER)  return (bias == 1) ? (k[0] < 80) : (k[0] > 20); 
   return false;
}

bool CheckSignal_BB(int bias) {
   double mid = GetIndValue(g_h_bb, 0); 
   double lower = GetIndValue(g_h_bb, 2); 
   double close = iClose(_Symbol, PERIOD_CURRENT, 1);
   
   if(InpBbMode == BB_TREND_FOLLOW) return (bias == 1) ? (close > mid) : (close < mid);
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
   return (bias == 1) ? (close > psar) : (close < psar);
}

bool CheckSignal_Pattern123(int bias) {
   double f1_val=0, f2_val=0, f3_val=0; 
   int f1_idx=0, f2_idx=0, f3_idx=0;
   
   if(bias == 1) { // BUY 1-2-3 (Bottom)
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
             double close = iClose(_Symbol, PERIOD_CURRENT, 1);
             if(close > f2_val) return true;
         }
      }
   }
   if(bias == -1) { // SELL 1-2-3 (Top)
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
             double close = iClose(_Symbol, PERIOD_CURRENT, 1);
             if(close < f2_val) return true;
         }
      }
   }
   return false;
}

bool CheckSignal_RossHook(int bias) {
   int lookback = 20;
   double level = 0;
   for(int i=2; i<=lookback; i++) {
      double up = GetFractal(i, 0);
      double down = GetFractal(i, 1);
      if(bias == 1 && up > 0) { level = up; break; } 
      if(bias == -1 && down > 0) { level = down; break; } 
   }
   if(level == 0) return false;
   double close = iClose(_Symbol, PERIOD_CURRENT, 1);
   return (bias == 1) ? (close > level) : (close < level);
}

//+------------------------------------------------------------------+
//| TIME & NEWS FILTER LOGIC                                         |
//+------------------------------------------------------------------+
bool CheckTimeFilter() {
   MqlDateTime dt;
   TimeCurrent(dt);
   // Simple hour check (e.g. 08:00 to 20:00)
   if(InpStartHour < InpEndHour) {
      return (dt.hour >= InpStartHour && dt.hour < InpEndHour);
   } else {
      // Overnight (e.g. Start 22, End 08)
      return (dt.hour >= InpStartHour || dt.hour < InpEndHour);
   }
}

bool CheckNewsFilter() {
   if(ArraySize(g_news_events) == 0) return true; // No news loaded
   
   datetime now = TimeCurrent();
   string base = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_BASE);
   string profit = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_PROFIT);
   
   for(int i=0; i<ArraySize(g_news_events); i++) {
      // 1. Currency Check
      if(g_news_events[i].currency != base && 
         g_news_events[i].currency != profit && 
         g_news_events[i].currency != "USD") continue;
      
      // 2. Time Window Check
      long diff = (long)now - (long)g_news_events[i].time;
      
      // Before News (diff is negative) -> e.g. -1800 sec = 30 min before
      if(diff < 0 && MathAbs(diff) <= InpNewsPreMin * 60) return false;
      
      // After News (diff is positive)
      if(diff >= 0 && diff <= InpNewsPostMin * 60) return false;
   }
   return true;
}

void LoadNewsCSV() {
   // Expected Format: "2026, January 12, 09:00","Event Name",Impact,Currency
   int handle = FileOpen(InpNewsFileName, FILE_READ|FILE_CSV|FILE_ANSI, ",");
   if(handle == INVALID_HANDLE) {
      Print("News Filter Error: Could not open ", InpNewsFileName, " in MQL5/Files/");
      return;
   }
   
   // Skip Header
   if(!FileIsEnding(handle)) {
      string dummy = FileReadString(handle);
      if(StringFind(dummy, "Date") >= 0) { // Header row logic
         FileReadString(handle); FileReadString(handle); FileReadString(handle); 
      } else {
         FileSeek(handle, 0, SEEK_SET); // Reset if no header
      }
   }
   
   while(!FileIsEnding(handle)) {
      // Read Date fields (CSV might split "2026, January 12, 09:00" into 3 parts)
      string date_part1 = FileReadString(handle); // "2026"
      string date_part2 = FileReadString(handle); // " January 12"
      string date_part3 = FileReadString(handle); // " 09:00"
      
      // Reconstruct Date
      string full_date = date_part1 + "," + date_part2 + "," + date_part3;
      StringReplace(full_date, "\"", ""); // Clean quotes
      
      string event    = FileReadString(handle);
      string impact   = FileReadString(handle);
      string currency = FileReadString(handle);
      
      if(impact == "High" || impact == "Medium") {
         // Parse Date Manually
         string parts[];
         StringSplit(full_date, ',', parts); // [0]=2026 [1]= Jan 12 [2]= 09:00
         
         if(ArraySize(parts) >= 3) {
            string date_body = parts[1]; // " January 12"
            StringTrimLeft(date_body);
            string month_day[];
            StringSplit(date_body, ' ', month_day);
            
            int mon = 1;
            if(month_day[0] == "February") mon=2;
            else if(month_day[0] == "March") mon=3;
            else if(month_day[0] == "April") mon=4;
            else if(month_day[0] == "May") mon=5;
            else if(month_day[0] == "June") mon=6;
            else if(month_day[0] == "July") mon=7;
            else if(month_day[0] == "August") mon=8;
            else if(month_day[0] == "September") mon=9;
            else if(month_day[0] == "October") mon=10;
            else if(month_day[0] == "November") mon=11;
            else if(month_day[0] == "December") mon=12;
            
            string final_time_str = parts[0] + "." + (string)mon + "." + month_day[1] + " " + parts[2];
            datetime t = StringToTime(final_time_str);
            
            int s = ArraySize(g_news_events);
            ArrayResize(g_news_events, s+1);
            g_news_events[s].time = t;
            g_news_events[s].currency = currency;
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
   double atr = GetIndValue(g_h_atr, 1);
   double sl_dist = atr * InpSLMultiplier;
   double tp_dist = atr * InpTPMultiplier;
   
   double price = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl = (type == ORDER_TYPE_BUY) ? price - sl_dist : price + sl_dist;
   double tp = (type == ORDER_TYPE_BUY) ? price + tp_dist : price - tp_dist;
   
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   sl = NormalizeDouble(sl, digits);
   tp = NormalizeDouble(tp, digits);
   
   // --- UNIVERSAL LOT CALCULATION (Fix for JPY/GOLD/Indices) ---
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk = balance * (InpRiskPercent / 100.0);
   double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tick_val  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   
   double lot = 0.01; // Default min
   if(tick_size > 0 && tick_val > 0) {
      double loss_per_lot = (sl_dist / tick_size) * tick_val;
      if(loss_per_lot > 0) lot = risk / loss_per_lot;
   }
   
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   lot = MathFloor(lot / step) * step;
   double min = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if(lot < min) lot = min;
   
   if(trade.PositionOpen(_Symbol, type, lot, price, sl, tp, "SimpleEA v1.02.011")) {
      Print("=== TRADE OPENED ===");
      Print("Type: ", EnumToString(type));
      Print("Price: ", price);
      Print("Lots: ", lot);
      Print("SL: ", sl, " (", DoubleToString(sl_dist/_Point, 0), " pts)");
      Print("TP: ", tp);
      Print("Risk: ", DoubleToString(risk, 2), " (approx)");
      Print("====================");
   } else {
      Print("Trade Error: ", GetLastError());
   }
}

void ManageExit() {
   if(!PositionSelect(_Symbol)) return;
   
   double atr = GetIndValue(g_h_atr, 1);
   
   // 1. Breakeven Check
   if(InpUseBreakeven) ManageBreakeven(atr);
   
   // 2. Trailing Stop
   if(InpTrailMode == TRAIL_NONE) return;
   
   ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   double current_sl = PositionGetDouble(POSITION_SL);
   double current_price = PositionGetDouble(POSITION_PRICE_CURRENT);
   double new_sl = 0.0;
   
   if(InpTrailMode == TRAIL_ATR) {
      double dist = atr * InpTrailATRMult;
      new_sl = (type == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) - dist 
                                           : SymbolInfoDouble(_Symbol, SYMBOL_ASK) + dist;
   }
   else if(InpTrailMode == TRAIL_PSAR) {
      double psar = GetIndValue(g_h_psar, 1); 
      new_sl = psar;
      if(type == POSITION_TYPE_BUY && new_sl > current_price) return;
      if(type == POSITION_TYPE_SELL && new_sl < current_price) return;
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
      } else {
         if((new_sl < current_sl || current_sl == 0) && new_sl > current_price) modify = true;
      }
      if(modify) trade.PositionModify(_Symbol, new_sl, PositionGetDouble(POSITION_TP));
   }
}

void ManageBreakeven(double atr) {
   if(PositionGetInteger(POSITION_MAGIC) == 0 && StringFind(PositionGetString(POSITION_COMMENT), "SimpleEA") < 0) return; 
   
   ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
   double current_price = PositionGetDouble(POSITION_PRICE_CURRENT);
   double sl = PositionGetDouble(POSITION_SL);
   
   double trigger_dist = atr * InpBE_TriggerATR;
   double buffer_dist  = atr * InpBE_BufferATR;
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   
   if(type == POSITION_TYPE_BUY) {
      // If profit > trigger AND SL is below (Entry + Buffer)
      if(current_price >= open_price + trigger_dist) {
         double target_sl = NormalizeDouble(open_price + buffer_dist, digits);
         if(sl < target_sl) trade.PositionModify(_Symbol, target_sl, PositionGetDouble(POSITION_TP));
      }
   }
   else if(type == POSITION_TYPE_SELL) {
      if(current_price <= open_price - trigger_dist) {
         double target_sl = NormalizeDouble(open_price - buffer_dist, digits);
         if(sl > target_sl || sl == 0) trade.PositionModify(_Symbol, target_sl, PositionGetDouble(POSITION_TP));
      }
   }
}

//+------------------------------------------------------------------+
//| BIAS & UTILITIES                                                 |
//+------------------------------------------------------------------+
bool IsNewBar() {
   datetime curr = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(curr != g_last_bar_time) { g_last_bar_time = curr; return true; }
   return false;
}

int GetHandleByRole(EEmaRole role) {
   switch(role) {
      case ROLE_EMA1: return g_h_ema1;
      case ROLE_EMA2: return g_h_ema2;
      case ROLE_EMA3: return g_h_ema3;
      case ROLE_EMA4: return g_h_ema4;
   }
   return g_h_ema4;
}

double GetIndValue(int handle, int shift) {
   double buf[1];
   if(CopyBuffer(handle, 0, shift, 1, buf) > 0) return buf[0];
   return 0.0;
}

bool GetIndBuffer(int handle, int buf_idx, int shift, double &arr[]) {
   return (CopyBuffer(handle, buf_idx, shift, 1, arr) > 0);
}

int GetSlope(int handle) {
   double c = GetIndValue(handle, 1);
   double p = GetIndValue(handle, 2);
   return (c > p) ? 1 : (c < p) ? -1 : 0;
}

double GetFractal(int shift, int mode) {
   // Mode 0 = Upper, 1 = Lower
   double res[1];
   if(CopyBuffer(g_h_fractals, mode, shift, 1, res) > 0) {
      if(res[0] != DBL_MAX) return res[0];
   }
   return 0.0;
}

bool CheckBasicFilters() {
   double spread = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / _Point;
   if(spread > InpMaxSpreadPips * 10) return false;
   double atr = GetIndValue(g_h_atr, 1);
   if((atr / (_Point * 10)) < InpMinATRPips) return false;
   return true;
}

int GetBias() {
   if(!InpBiasEnabled) return 0;
   if(InpBiasMode == BIAS_MANUAL) {
      if(InpManualSide == SIDE_LONG)  return 1;
      if(InpManualSide == SIDE_SHORT) return -1;
      return GetSlope(g_h_ema4); 
   }
   // Auto
   int h_fast = GetHandleByRole(InpBiasFast);
   int h_slow = GetHandleByRole(InpBiasSlow);
   
   if(InpAutoStrat == STRAT_SINGLE_SLOPE) return GetSlope(h_fast);
   if(InpAutoStrat == STRAT_PAIR_CROSS) {
      double f = GetIndValue(h_fast, 1);
      double s = GetIndValue(h_slow, 1);
      if(f > s) return 1;
      if(f < s) return -1;
   }
   return 0;
}

bool CheckHTF(int bias) {
   double curr = 0.0, prev = 0.0;
   double buf[2];
   if(CopyBuffer(g_h_htf_ema, 0, 1, 2, buf) < 2) return true; 
   curr = buf[1];
   prev = buf[0];
   int htf_trend = (curr > prev) ? 1 : -1;
   return (bias == htf_trend);
}
//+------------------------------------------------------------------+