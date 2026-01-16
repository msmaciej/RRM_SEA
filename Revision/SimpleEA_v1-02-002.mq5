//+------------------------------------------------------------------+
//|                                           SimpleEA_v1-02-002.mq5 |
//|                                  Institutional Trading Solutions |
//|                                     Elastic Modular Architecture |
//+------------------------------------------------------------------+
#property copyright "SimpleEA Redesign"
#property version   "1.02"
#property strict

#include <Trade\Trade.mqh>

//--- ENUMS FOR ELASTIC CONFIGURATION ---
enum EBiasMode { BIAS_MANUAL, BIAS_AUTO };
enum EManualSide { SIDE_BOTH, SIDE_LONG, SIDE_SHORT };
enum EAutoStrategy { STRAT_SINGLE_SLOPE, STRAT_PAIR_CROSS }; // Simplified for clarity
enum EEmaRole { ROLE_EMA1, ROLE_EMA2, ROLE_EMA3, ROLE_EMA4 };

// New: Elastic Modes for Indicators
enum ERsiMode { RSI_FILTER_EXTREME, RSI_TREND_ABOVE_50 };
enum EMacdMode { MACD_SIGNAL_ALIGN, MACD_ZERO_LEVEL };

//--- GLOBAL OBJECTS ---
CTrade trade;
int    g_h_ema1, g_h_ema2, g_h_ema3, g_h_ema4;
int    g_h_macd, g_h_rsi, g_h_cci, g_h_sto, g_h_atr, g_h_bb, g_h_psar, g_h_fractals, g_h_adx;
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
input EBiasMode     InpBiasMode      = BIAS_AUTO;   // Bias Mode
input EManualSide   InpManualSide    = SIDE_BOTH;   // Manual: Allowed Sides
input EAutoStrategy InpAutoStrat     = STRAT_PAIR_CROSS; // Auto Strategy
input EEmaRole      InpBiasFast      = ROLE_EMA3;   // Auto: Fast MA
input EEmaRole      InpBiasSlow      = ROLE_EMA4;   // Auto: Slow MA

input group "=== 3. CONFLUENCE VOTING ==="
input int    InpVotingThreshold  = 3;     // MINIMUM Indicators needed to Trade
// Note: Bias is mandatory. These votes are for the confirmation indicators below.

input group "=== 4. INDICATOR SETTINGS (ON/OFF) ==="
// EMA Filter
input bool   InpUseEmaFilter  = true;     // Vote 1: Price vs EMA1 (Recovery)
// ADX (Trend Strength)
input bool   InpUseAdx        = true;     // Vote 2: ADX Trend Strength
input int    InpAdxThreshold  = 20;       // ADX Level > 20
// MACD
input bool   InpUseMacd       = true;     // Vote 3: MACD
input EMacdMode InpMacdMode   = MACD_SIGNAL_ALIGN;
// RSI
input bool   InpUseRsi        = true;     // Vote 4: RSI
input ERsiMode InpRsiMode     = RSI_FILTER_EXTREME; 
input int    InpRsiPeriod     = 14;
// Stochastic
input bool   InpUseSto        = false;    // Vote 5: Stochastic
// Bollinger
input bool   InpUseBB         = false;    // Vote 6: Bollinger Trend
// PSAR
input bool   InpUsePsar       = false;    // Vote 7: PSAR
// Ross Hook
input bool   InpUseRossHook   = false;    // Vote 8: Fractal Breakout

input group "=== 5. EXIT RULES ==="
input double InpSLMultiplier    = 2.0;    // SL (ATR Multiplier)
input double InpTPMultiplier    = 4.0;    // TP (ATR Multiplier)
input bool   InpTrailStop       = true;   // Trailing Stop
input double InpTrailMultiplier = 1.5;    // Trailing Step (ATR)

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Basic Indicators
   g_h_ema1 = iMA(_Symbol, PERIOD_CURRENT, 13, 0, MODE_EMA, PRICE_CLOSE);
   g_h_ema2 = iMA(_Symbol, PERIOD_CURRENT, 21, 0, MODE_EMA, PRICE_CLOSE);
   g_h_ema3 = iMA(_Symbol, PERIOD_CURRENT, 34, 0, MODE_EMA, PRICE_CLOSE);
   g_h_ema4 = iMA(_Symbol, PERIOD_CURRENT, 55, 0, MODE_EMA, PRICE_CLOSE);
   g_h_atr  = iATR(_Symbol, PERIOD_CURRENT, 14);
   
   // Optional Indicators (Always init handles to avoid lag, but logic checks bools)
   g_h_macd = iMACD(_Symbol, PERIOD_CURRENT, 12, 26, 9, PRICE_CLOSE);
   g_h_rsi  = iRSI(_Symbol, PERIOD_CURRENT, InpRsiPeriod, PRICE_CLOSE);
   g_h_adx  = iADX(_Symbol, PERIOD_CURRENT, 14);
   g_h_sto  = iStochastic(_Symbol, PERIOD_CURRENT, 5, 3, 3, MODE_SMA, STO_LOWHIGH);
   g_h_bb   = iBands(_Symbol, PERIOD_CURRENT, 20, 0, 2.0, PRICE_CLOSE);
   g_h_psar = iSAR(_Symbol, PERIOD_CURRENT, 0.02, 0.2);
   g_h_fractals = iFractals(_Symbol, PERIOD_CURRENT);

   if(g_h_ema1 == INVALID_HANDLE || g_h_atr == INVALID_HANDLE) return INIT_FAILED;
   
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) {
   IndicatorRelease(g_h_ema1); IndicatorRelease(g_h_ema2);
   IndicatorRelease(g_h_ema3); IndicatorRelease(g_h_ema4);
   IndicatorRelease(g_h_atr); IndicatorRelease(g_h_macd);
   IndicatorRelease(g_h_rsi); IndicatorRelease(g_h_adx);
   IndicatorRelease(g_h_sto); IndicatorRelease(g_h_bb);
   IndicatorRelease(g_h_psar); IndicatorRelease(g_h_fractals);
}

//+------------------------------------------------------------------+
//| Main OnTick                                                      |
//+------------------------------------------------------------------+
void OnTick()
{
   // 1. Manage Open Positions (Tick based)
   if(PositionSelect(_Symbol)) {
      ManageExit();
      return; // SimpleEA philosophy: One trade at a time per symbol
   }

   // 2. Entry Logic (Closed Bar based)
   if(!IsNewBar()) return;
   
   // 3. Basic Filters
   if(!CheckBasicFilters()) return;

   // 4. BIAS DETERMINATION (Mandatory)
   // Returns: 1 (Long), -1 (Short), 0 (Neutral)
   int bias = GetBias();
   if(bias == 0) return;

   // 5. VOTING SYSTEM (Elasticity)
   int votes = 0;
   
   // Check enabled indicators. 
   // Note: We only count votes for enabled indicators.
   // If an indicator is enabled but fails, it contributes 0.
   
   if(InpUseEmaFilter && CheckSignal_EMA1(bias))    votes++;
   if(InpUseAdx       && CheckSignal_ADX())         votes++; // ADX is directionless, just "Trend exists"
   if(InpUseMacd      && CheckSignal_MACD(bias))    votes++;
   if(InpUseRsi       && CheckSignal_RSI(bias))     votes++;
   if(InpUseSto       && CheckSignal_Sto(bias))     votes++;
   if(InpUseBB        && CheckSignal_BB(bias))      votes++;
   if(InpUsePsar      && CheckSignal_PSAR(bias))    votes++;
   if(InpUseRossHook  && CheckSignal_RossHook(bias)) votes++;

   // 6. EXECUTE IF THRESHOLD MET
   if(votes >= InpVotingThreshold) {
      if(bias == 1)      OpenTrade(ORDER_TYPE_BUY);
      else if(bias == -1) OpenTrade(ORDER_TYPE_SELL);
   }
}

//+------------------------------------------------------------------+
//| LOGIC: BIAS                                                      |
//+------------------------------------------------------------------+
int GetBias()
{
   if(!InpBiasEnabled) return 0; // If disabled, no trade logic allows entry

   // Manual
   if(InpBiasMode == BIAS_MANUAL) {
      if(InpManualSide == SIDE_LONG)  return 1;
      if(InpManualSide == SIDE_SHORT) return -1;
      // If SIDE_BOTH in manual, we default to EMA4 Slope
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

//+------------------------------------------------------------------+
//| LOGIC: INDICATORS                                                |
//+------------------------------------------------------------------+
bool CheckSignal_EMA1(int bias) {
   // Price Recovery: Close > EMA1 (Buy)
   double price = iClose(_Symbol, PERIOD_CURRENT, 1);
   double ema   = GetIndValue(g_h_ema1, 1);
   return (bias == 1) ? (price > ema) : (price < ema);
}

bool CheckSignal_ADX() {
   // Directionless filter: Is trend strong enough?
   double adx = GetIndValue(g_h_adx, 1);
   return (adx > InpAdxThreshold);
}

bool CheckSignal_MACD(int bias) {
   double main[], sig[];
   if(!GetIndBuffer(g_h_macd, 0, 1, main) || !GetIndBuffer(g_h_macd, 1, 1, sig)) return false;
   
   if(InpMacdMode == MACD_SIGNAL_ALIGN) {
      return (bias == 1) ? (main[0] > sig[0]) : (main[0] < sig[0]);
   }
   if(InpMacdMode == MACD_ZERO_LEVEL) {
      return (bias == 1) ? (main[0] > 0) : (main[0] < 0);
   }
   return false;
}

bool CheckSignal_RSI(int bias) {
   double rsi = GetIndValue(g_h_rsi, 1);
   
   if(InpRsiMode == RSI_FILTER_EXTREME) {
      // Logic: PASS if NOT Overbought (Buy) or NOT Oversold (Sell)
      // Actually, if it's a "Vote", it should be affirmative. 
      // Let's say: Vote YES if RSI is "Safe" (e.g. 40-70 for Buy)
      if(bias == 1) return (rsi < 70); 
      if(bias == -1) return (rsi > 30);
   }
   if(InpRsiMode == RSI_TREND_ABOVE_50) {
      if(bias == 1) return (rsi > 50);
      if(bias == -1) return (rsi < 50);
   }
   return false;
}

bool CheckSignal_Sto(int bias) {
   double k[1], d[1];
   CopyBuffer(g_h_sto, 0, 1, 1, k);
   CopyBuffer(g_h_sto, 1, 1, 1, d);
   // Standard signal cross
   return (bias == 1) ? (k[0] > d[0] && k[0] < 80) : (k[0] < d[0] && k[0] > 20);
}

bool CheckSignal_BB(int bias) {
   double mid = GetIndValue(g_h_bb, 0); // Base line
   double close = iClose(_Symbol, PERIOD_CURRENT, 1);
   return (bias == 1) ? (close > mid) : (close < mid);
}

bool CheckSignal_PSAR(int bias) {
   double psar = GetIndValue(g_h_psar, 1);
   double close = iClose(_Symbol, PERIOD_CURRENT, 1);
   return (bias == 1) ? (close > psar) : (close < psar);
}

bool CheckSignal_RossHook(int bias) {
   // Improved: Breakout of most recent opposing fractal
   // Buy: Close > Recent Up Fractal
   int lookback = 10;
   double fractal_level = 0;
   
   for(int i=2; i<=lookback; i++) {
      double val = 0;
      double up[1], down[1];
      CopyBuffer(g_h_fractals, 0, i, 1, up);
      CopyBuffer(g_h_fractals, 1, i, 1, down);
      
      if(bias == 1 && up[0] != DBL_MAX && up[0] > 0) {
         fractal_level = up[0];
         break; // Found most recent high
      }
      if(bias == -1 && down[0] != DBL_MAX && down[0] > 0) {
         fractal_level = down[0];
         break; // Found most recent low
      }
   }
   
   if(fractal_level == 0) return false;
   
   double close = iClose(_Symbol, PERIOD_CURRENT, 1);
   return (bias == 1) ? (close > fractal_level) : (close < fractal_level);
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
   
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk = balance * (InpRiskPercent / 100.0);
   double tick_val = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tick_val == 0) tick_val = 1.0; 
   double lot = (risk / sl_dist) / tick_val;
   
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   lot = MathFloor(lot / step) * step;
   double min = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if(lot < min) lot = min;
   
   trade.PositionOpen(_Symbol, type, lot, price, sl, tp, "SimpleEA v1.02 Elastic");
}

void ManageExit() {
   if(!InpTrailStop) return;
   double atr = GetIndValue(g_h_atr, 1);
   double dist = atr * InpTrailMultiplier;
   
   if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) {
      double new_sl = SymbolInfoDouble(_Symbol, SYMBOL_BID) - dist;
      if(new_sl > PositionGetDouble(POSITION_SL) && new_sl < PositionGetDouble(POSITION_PRICE_CURRENT))
         trade.PositionModify(_Symbol, new_sl, PositionGetDouble(POSITION_TP));
   }
   else {
      double new_sl = SymbolInfoDouble(_Symbol, SYMBOL_ASK) + dist;
      if(new_sl < PositionGetDouble(POSITION_SL) && new_sl > PositionGetDouble(POSITION_PRICE_CURRENT))
         trade.PositionModify(_Symbol, new_sl, PositionGetDouble(POSITION_TP));
   }
}