//+------------------------------------------------------------------+
//|                                           SimpleEA_v1-02-004.mq5 |
//|                                  Institutional Trading Solutions |
//|                            Enhanced Inputs & Volume Architecture |
//+------------------------------------------------------------------+
#property copyright "SimpleEA Redesign v4"
#property version   "1.024"
#property strict

#include <Trade\Trade.mqh>

//--- ENUMS FOR ELASTIC CONFIGURATION ---
// 1. BIAS & STRATEGY
enum EBiasMode { 
   BIAS_MANUAL,   // User defines direction
   BIAS_AUTO      // EA determines direction
};
enum EManualSide { 
   SIDE_BOTH,     // Trade both Long and Short
   SIDE_LONG,     // Long Only
   SIDE_SHORT     // Short Only
};
enum EAutoStrategy { 
   STRAT_SINGLE_SLOPE, // Slope of one MA
   STRAT_PAIR_CROSS    // Crossover of two MAs
}; 
enum EEmaRole { 
   ROLE_EMA1, ROLE_EMA2, ROLE_EMA3, ROLE_EMA4 
};

// 2. INDICATOR MODES
enum EMacdMode { 
   MACD_SIGNAL_ALIGN, // Main > Signal
   MACD_ZERO_CROSS    // Main > 0
};
enum ERsiMode { 
   RSI_FILTER_EXTREME, // Pass if NOT Overbought/Oversold
   RSI_TREND_ABOVE_50, // Pass if > 50 (Bullish)
   RSI_CROSS_LEVEL     // Signal on breakout of 30/70
};
enum EStochMode {
   STO_CROSS_SIGNAL,   // K line crosses D line
   STO_ZONE_FILTER     // K is not in extreme zones
};
enum EBbMode {
   BB_TREND_FOLLOW,    // Price > Middle Band
   BB_MEAN_REVERSION   // Price touches Lower Band (Buy)
};

// 3. TRAILING LOGIC
enum ETrailingMode { 
   TRAIL_NONE,       // Hard SL only
   TRAIL_ATR,        // Volatility based (Smooth)
   TRAIL_PSAR,       // Parabolic SAR (Trend Lock)
   TRAIL_FRACTAL     // Market Structure (Swings)
};

//--- GLOBAL OBJECTS ---
CTrade trade;
// Handles
int    g_h_ema1, g_h_ema2, g_h_ema3, g_h_ema4;
int    g_h_macd, g_h_rsi, g_h_cci, g_h_sto, g_h_atr, g_h_bb, g_h_psar, g_h_fractals, g_h_adx, g_h_mfi;
datetime g_last_bar_time = 0;

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
input EManualSide   InpManualSide    = SIDE_BOTH;   // Manual: BOTH, LONG, SHORT
input EAutoStrategy InpAutoStrat     = STRAT_PAIR_CROSS; // Auto: SINGLE_SLOPE, PAIR_CROSS
input EEmaRole      InpBiasFast      = ROLE_EMA3;   // Auto Fast MA
input EEmaRole      InpBiasSlow      = ROLE_EMA4;   // Auto Slow MA

input group "=== 3. CONFLUENCE VOTING ==="
input int    InpVotingThreshold  = 4;     // MINIMUM Votes (Indicators) to Trade

input group "=== 4. INDICATOR SETTINGS ==="
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
input ERsiMode InpRsiMode     = RSI_FILTER_EXTREME; // Options: FILTER_EXTREME, TREND_ABOVE_50, CROSS_LEVEL
input int    InpRsiPeriod     = 14;
input double InpRsiOverbought = 70.0;
input double InpRsiOversold   = 30.0;

// Vote 5: MFI (Volume)
input bool   InpUseMfi        = true;     // Vote 5: Money Flow Index (Volume)
input int    InpMfiPeriod     = 14;
input double InpMfiLevel      = 50.0;     // Trend Threshold (e.g. > 50 is Bullish)

// Vote 6: Stochastic
input bool   InpUseSto        = false;    // Vote 6: Stochastic
input EStochMode InpStoMode   = STO_CROSS_SIGNAL; // Options: CROSS_SIGNAL, ZONE_FILTER
input int    InpStoK          = 5;
input int    InpStoD          = 3;
input int    InpStoSlow       = 3;

// Vote 7: Bollinger
input bool   InpUseBB         = false;    // Vote 7: Bollinger Bands
input EBbMode InpBbMode       = BB_TREND_FOLLOW; // Options: TREND_FOLLOW, MEAN_REVERSION
input int    InpBbPeriod      = 20;
input double InpBbDev         = 2.0;

// Vote 8: PSAR
input bool   InpUsePsar       = false;    // Vote 8: PSAR Direction
input double InpPsarStep      = 0.02;
input double InpPsarMax       = 0.2;

// Vote 9: Ross Hook
input bool   InpUseRossHook   = false;    // Vote 9: Fractal Breakout (Ross Hook)

input group "=== 5. EXIT & TRAILING RULES ==="
input double InpSLMultiplier    = 2.0;    // SL (ATR Multiplier)
input double InpTPMultiplier    = 4.0;    // TP (ATR Multiplier)
input ETrailingMode InpTrailMode = TRAIL_ATR; // Options: NONE, ATR, PSAR, FRACTAL
input double InpTrailATRMult    = 1.5;    // ATR Trail Distance

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("=== SimpleEA v1.02.004 Initializing ===");
   
   // 1. Initialize Indicators
   g_h_ema1 = iMA(_Symbol, PERIOD_CURRENT, InpEma1Period, 0, MODE_EMA, PRICE_CLOSE);
   g_h_ema2 = iMA(_Symbol, PERIOD_CURRENT, InpEma2Period, 0, MODE_EMA, PRICE_CLOSE);
   g_h_ema3 = iMA(_Symbol, PERIOD_CURRENT, InpEma3Period, 0, MODE_EMA, PRICE_CLOSE);
   g_h_ema4 = iMA(_Symbol, PERIOD_CURRENT, InpEma4Period, 0, MODE_EMA, PRICE_CLOSE);
   g_h_atr  = iATR(_Symbol, PERIOD_CURRENT, 14); 
   
   // Optional Indicators
   g_h_macd = iMACD(_Symbol, PERIOD_CURRENT, InpMacdFast, InpMacdSlow, InpMacdSig, PRICE_CLOSE);
   g_h_rsi  = iRSI(_Symbol, PERIOD_CURRENT, InpRsiPeriod, PRICE_CLOSE);
   g_h_adx  = iADX(_Symbol, PERIOD_CURRENT, InpAdxPeriod);
   g_h_mfi  = iMFI(_Symbol, PERIOD_CURRENT, InpMfiPeriod, VOLUME_TICK); // Using Tick Volume for Forex
   g_h_sto  = iStochastic(_Symbol, PERIOD_CURRENT, InpStoK, InpStoD, InpStoSlow, MODE_SMA, STO_LOWHIGH);
   g_h_bb   = iBands(_Symbol, PERIOD_CURRENT, InpBbPeriod, 0, InpBbDev, PRICE_CLOSE);
   g_h_psar = iSAR(_Symbol, PERIOD_CURRENT, InpPsarStep, InpPsarMax);
   g_h_fractals = iFractals(_Symbol, PERIOD_CURRENT);

   if(g_h_ema1 == INVALID_HANDLE || g_h_atr == INVALID_HANDLE) {
      Print("CRITICAL ERROR: Failed to create essential handles.");
      return INIT_FAILED;
   }
   
   // 2. Print Summary
   Print("--- Voting System Config ---");
   Print("Required Votes: ", InpVotingThreshold);
   if(InpUseEmaSignal) Print("+ Vote: EMA Recovery");
   if(InpUseAdx)       Print("+ Vote: ADX Strength");
   if(InpUseMacd)      Print("+ Vote: MACD (", EnumToString(InpMacdMode), ")");
   if(InpUseRsi)       Print("+ Vote: RSI (", EnumToString(InpRsiMode), ")");
   if(InpUseMfi)       Print("+ Vote: MFI (Volume)");
   if(InpUseRossHook)  Print("+ Vote: Ross Hook (Fractals)");
   Print("Trailing Mode: ", EnumToString(InpTrailMode));
   
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) {
   IndicatorRelease(g_h_ema1); IndicatorRelease(g_h_ema2);
   IndicatorRelease(g_h_ema3); IndicatorRelease(g_h_ema4);
   IndicatorRelease(g_h_atr); IndicatorRelease(g_h_macd);
   IndicatorRelease(g_h_rsi); IndicatorRelease(g_h_adx);
   IndicatorRelease(g_h_mfi);
   IndicatorRelease(g_h_sto); IndicatorRelease(g_h_bb);
   IndicatorRelease(g_h_psar); IndicatorRelease(g_h_fractals);
   Print("=== SimpleEA Shutdown ===");
}

//+------------------------------------------------------------------+
//| Main OnTick                                                      |
//+------------------------------------------------------------------+
void OnTick()
{
   if(PositionSelect(_Symbol)) {
      ManageExit();
      return; 
   }

   if(!IsNewBar()) return;
   if(!CheckBasicFilters()) return;

   // 1. BIAS
   int bias = GetBias();
   if(bias == 0) return;

   // 2. VOTING
   int votes = 0;
   
   if(InpUseEmaSignal && CheckSignal_EMA1(bias))    votes++;
   if(InpUseAdx       && CheckSignal_ADX())         votes++; 
   if(InpUseMacd      && CheckSignal_MACD(bias))    votes++;
   if(InpUseRsi       && CheckSignal_RSI(bias))     votes++;
   if(InpUseMfi       && CheckSignal_MFI(bias))     votes++;
   if(InpUseSto       && CheckSignal_Sto(bias))     votes++;
   if(InpUseBB        && CheckSignal_BB(bias))      votes++;
   if(InpUsePsar      && CheckSignal_PSAR(bias))    votes++;
   if(InpUseRossHook  && CheckSignal_RossHook(bias)) votes++;

   // 3. EXECUTE
   if(votes >= InpVotingThreshold) {
      if(bias == 1)      OpenTrade(ORDER_TYPE_BUY);
      else if(bias == -1) OpenTrade(ORDER_TYPE_SELL);
   }
}

//+------------------------------------------------------------------+
//| SIGNAL LOGIC                                                     |
//+------------------------------------------------------------------+
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
   // MFI Logic: Confirming trend momentum
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
       // Check if it Just crossed? Or is positioned?
       // For "Simple" EA, position is safer.
       if(bias == 1) return (rsi > InpRsiOversold); // Recovered from low
       if(bias == -1) return (rsi < InpRsiOverbought);
   }
   return false;
}

bool CheckSignal_Sto(int bias) {
   double k[1], d[1];
   CopyBuffer(g_h_sto, 0, 1, 1, k);
   CopyBuffer(g_h_sto, 1, 1, 1, d);
   if(InpStoMode == STO_CROSS_SIGNAL) return (bias == 1) ? (k[0] > d[0]) : (k[0] < d[0]);
   if(InpStoMode == STO_ZONE_FILTER)  return (bias == 1) ? (k[0] < 80) : (k[0] > 20); // Not exhausted
   return false;
}

bool CheckSignal_BB(int bias) {
   double mid = GetIndValue(g_h_bb, 0); 
   double lower = GetIndValue(g_h_bb, 2); // Buffer 2 is Lower
   double close = iClose(_Symbol, PERIOD_CURRENT, 1);
   
   if(InpBbMode == BB_TREND_FOLLOW) return (bias == 1) ? (close > mid) : (close < mid);
   if(InpBbMode == BB_MEAN_REVERSION) {
       // Buy if price touched lower band recently
       if(bias == 1) return (iLow(_Symbol, PERIOD_CURRENT, 1) < lower);
       // For Sell, we need Upper (Buffer 1)
       double upper = GetIndValue(g_h_bb, 1);
       if(bias == -1) return (iHigh(_Symbol, PERIOD_CURRENT, 1) > upper);
   }
   return false;
}

bool CheckSignal_PSAR(int bias) {
   double psar = GetIndValue(g_h_psar, 1);
   double close = iClose(_Symbol, PERIOD_CURRENT, 1);
   return (bias == 1) ? (close > psar) : (close < psar);
}

bool CheckSignal_RossHook(int bias) {
   // Logic: Breakout of most recent opposing fractal in trend direction
   int lookback = 10;
   double level = 0;
   for(int i=2; i<=lookback; i++) {
      double up[1], down[1];
      CopyBuffer(g_h_fractals, 0, i, 1, up);
      CopyBuffer(g_h_fractals, 1, i, 1, down);
      if(bias == 1 && up[0] != DBL_MAX && up[0] > 0) { level = up[0]; break; }
      if(bias == -1 && down[0] != DBL_MAX && down[0] > 0) { level = down[0]; break; }
   }
   if(level == 0) return false;
   double close = iClose(_Symbol, PERIOD_CURRENT, 1);
   return (bias == 1) ? (close > level) : (close < level);
}

//+------------------------------------------------------------------+
//| UTILITIES & EXECUTION                                            |
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

bool CheckBasicFilters() {
   double spread = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / _Point;
   if(spread > InpMaxSpreadPips * 10) return false;
   double atr = GetIndValue(g_h_atr, 1);
   if((atr / (_Point * 10)) < InpMinATRPips) return false;
   return true;
}

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
   
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk = balance * (InpRiskPercent / 100.0);
   double tick_val = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tick_val == 0) tick_val = 1.0; 
   double lot = (risk / sl_dist) / tick_val;
   
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   lot = MathFloor(lot / step) * step;
   double min = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if(lot < min) lot = min;
   
   if(trade.PositionOpen(_Symbol, type, lot, price, sl, tp, "SimpleEA v1.02.4")) {
      Print("Trade Opened: ", EnumToString(type), " Lots: ", lot);
   } else {
      Print("Trade Error: ", GetLastError());
   }
}

void ManageExit() {
   if(InpTrailMode == TRAIL_NONE) return;
   
   ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   double current_sl = PositionGetDouble(POSITION_SL);
   double current_price = PositionGetDouble(POSITION_PRICE_CURRENT);
   double new_sl = 0.0;
   
   if(InpTrailMode == TRAIL_ATR) {
      double atr = GetIndValue(g_h_atr, 1);
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
         double up[1], down[1];
         CopyBuffer(g_h_fractals, 0, i, 1, up);
         CopyBuffer(g_h_fractals, 1, i, 1, down);
         if(type == POSITION_TYPE_BUY && down[0] != DBL_MAX && down[0] > 0) { new_sl = down[0]; break; }
         if(type == POSITION_TYPE_SELL && up[0] != DBL_MAX && up[0] > 0) { new_sl = up[0]; break; }
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