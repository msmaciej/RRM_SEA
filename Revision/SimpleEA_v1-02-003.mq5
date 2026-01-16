//+------------------------------------------------------------------+
//|                                           SimpleEA_v1-02-003.mq5 |
//|                                  Institutional Trading Solutions |
//|                                     Elastic Modular Architecture |
//+------------------------------------------------------------------+
#property copyright "SimpleEA Redesign v3"
#property version   "1.023"
#property strict

#include <Trade\Trade.mqh>

//--- ENUMS FOR ELASTIC CONFIGURATION ---
enum EBiasMode { BIAS_MANUAL, BIAS_AUTO };
enum EManualSide { SIDE_BOTH, SIDE_LONG, SIDE_SHORT };
enum EAutoStrategy { STRAT_SINGLE_SLOPE, STRAT_PAIR_CROSS }; 
enum EEmaRole { ROLE_EMA1, ROLE_EMA2, ROLE_EMA3, ROLE_EMA4 };

// Indicator Specific Modes
enum ERsiMode { RSI_FILTER_EXTREME, RSI_TREND_ABOVE_50 };
enum EMacdMode { MACD_SIGNAL_ALIGN, MACD_ZERO_LEVEL };

// Trailing Stop Logic
enum ETrailingMode { TRAIL_NONE, TRAIL_ATR, TRAIL_PSAR, TRAIL_FRACTAL };

//--- GLOBAL OBJECTS ---
CTrade trade;
// Handles
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

input group "=== 4. INDICATOR SETTINGS ==="
// EMA
input int    InpEma1Period = 13;
input int    InpEma2Period = 21;
input int    InpEma3Period = 34;
input int    InpEma4Period = 55;

// EMA Filter (Vote 1)
input bool   InpUseEmaFilter  = true;     // Vote: Price vs EMA1 (Recovery)

// ADX (Vote 2)
input bool   InpUseAdx        = true;     // Vote: ADX Trend Strength
input int    InpAdxPeriod     = 14;
input int    InpAdxThreshold  = 20;       // ADX Level > X

// MACD (Vote 3)
input bool   InpUseMacd       = true;     // Vote: MACD
input EMacdMode InpMacdMode   = MACD_SIGNAL_ALIGN;
input int    InpMacdFast      = 12;
input int    InpMacdSlow      = 26;
input int    InpMacdSig       = 9;

// RSI (Vote 4)
input bool   InpUseRsi        = true;     // Vote: RSI
input ERsiMode InpRsiMode     = RSI_FILTER_EXTREME; 
input int    InpRsiPeriod     = 14;
input double InpRsiOverbought = 70.0;
input double InpRsiOversold   = 30.0;

// Stochastic (Vote 5)
input bool   InpUseSto        = false;    // Vote: Stochastic
input int    InpStoK          = 5;
input int    InpStoD          = 3;
input int    InpStoSlow       = 3;

// Bollinger (Vote 6)
input bool   InpUseBB         = false;    // Vote: Bollinger Trend
input int    InpBbPeriod      = 20;
input double InpBbDev         = 2.0;

// PSAR (Vote 7)
input bool   InpUsePsar       = false;    // Vote: PSAR Direction
input double InpPsarStep      = 0.02;
input double InpPsarMax       = 0.2;

// Ross Hook / Fractals (Vote 8)
input bool   InpUseRossHook   = false;    // Vote: Fractal Breakout
// No separate inputs for Fractal period (standard is 5 bars)

input group "=== 5. EXIT & TRAILING RULES ==="
input double InpSLMultiplier    = 2.0;    // SL (ATR Multiplier)
input double InpTPMultiplier    = 4.0;    // TP (ATR Multiplier)
input ETrailingMode InpTrailMode = TRAIL_ATR; // Trailing Logic
input double InpTrailATRMult    = 1.5;    // ATR Trail Distance
// Note: PSAR Trail uses PSAR settings above. 

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("=== SimpleEA v1.02.003 Initializing ===");
   
   // 1. Initialize Indicators
   g_h_ema1 = iMA(_Symbol, PERIOD_CURRENT, InpEma1Period, 0, MODE_EMA, PRICE_CLOSE);
   g_h_ema2 = iMA(_Symbol, PERIOD_CURRENT, InpEma2Period, 0, MODE_EMA, PRICE_CLOSE);
   g_h_ema3 = iMA(_Symbol, PERIOD_CURRENT, InpEma3Period, 0, MODE_EMA, PRICE_CLOSE);
   g_h_ema4 = iMA(_Symbol, PERIOD_CURRENT, InpEma4Period, 0, MODE_EMA, PRICE_CLOSE);
   g_h_atr  = iATR(_Symbol, PERIOD_CURRENT, 14); // ATR used for volatility calc
   
   // Always init handles to prevent runtime errors, even if unchecked
   g_h_macd = iMACD(_Symbol, PERIOD_CURRENT, InpMacdFast, InpMacdSlow, InpMacdSig, PRICE_CLOSE);
   g_h_rsi  = iRSI(_Symbol, PERIOD_CURRENT, InpRsiPeriod, PRICE_CLOSE);
   g_h_adx  = iADX(_Symbol, PERIOD_CURRENT, InpAdxPeriod);
   g_h_sto  = iStochastic(_Symbol, PERIOD_CURRENT, InpStoK, InpStoD, InpStoSlow, MODE_SMA, STO_LOWHIGH);
   g_h_bb   = iBands(_Symbol, PERIOD_CURRENT, InpBbPeriod, 0, InpBbDev, PRICE_CLOSE);
   g_h_psar = iSAR(_Symbol, PERIOD_CURRENT, InpPsarStep, InpPsarMax);
   g_h_fractals = iFractals(_Symbol, PERIOD_CURRENT);

   // Validation
   if(g_h_ema1 == INVALID_HANDLE || g_h_atr == INVALID_HANDLE) {
      Print("CRITICAL ERROR: Failed to create indicator handles.");
      return INIT_FAILED;
   }
   
   // 2. Print Active Configuration
   Print("--- Active Strategy Configuration ---");
   Print("Bias Mode: ", EnumToString(InpBiasMode));
   Print("Voting Threshold: ", InpVotingThreshold, " votes required.");
   
   if(InpUseEmaFilter) Print("Filter [ON]: EMA1 Recovery (", InpEma1Period, ")");
   if(InpUseAdx)       Print("Filter [ON]: ADX Strength (>", InpAdxThreshold, ")");
   if(InpUseMacd)      Print("Filter [ON]: MACD (",InpMacdFast,"/",InpMacdSlow,"/",InpMacdSig,") Mode: ", EnumToString(InpMacdMode));
   if(InpUseRsi)       Print("Filter [ON]: RSI (",InpRsiPeriod,") Mode: ", EnumToString(InpRsiMode));
   if(InpUseSto)       Print("Filter [ON]: Stochastic (",InpStoK,"/",InpStoD,"/",InpStoSlow,")");
   if(InpUseBB)        Print("Filter [ON]: Bollinger Bands (",InpBbPeriod,", ",InpBbDev,")");
   if(InpUsePsar)      Print("Filter [ON]: PSAR (",InpPsarStep,", ",InpPsarMax,")");
   if(InpUseRossHook)  Print("Filter [ON]: Ross Hook (Fractals)");
   
   Print("Trailing Mode: ", EnumToString(InpTrailMode));
   Print("=======================================");
   
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) {
   Print("=== SimpleEA v1.02.003 Shutting Down ===");
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
      return; 
   }

   // 2. Entry Logic (Closed Bar based)
   if(!IsNewBar()) return;
   
   // 3. Basic Filters
   if(!CheckBasicFilters()) return;

   // 4. BIAS DETERMINATION
   int bias = GetBias();
   if(bias == 0) return;

   // 5. VOTING SYSTEM
   int votes = 0;
   
   if(InpUseEmaFilter && CheckSignal_EMA1(bias))    votes++;
   if(InpUseAdx       && CheckSignal_ADX())         votes++; 
   if(InpUseMacd      && CheckSignal_MACD(bias))    votes++;
   if(InpUseRsi       && CheckSignal_RSI(bias))     votes++;
   if(InpUseSto       && CheckSignal_Sto(bias))     votes++;
   if(InpUseBB        && CheckSignal_BB(bias))      votes++;
   if(InpUsePsar      && CheckSignal_PSAR(bias))    votes++;
   if(InpUseRossHook  && CheckSignal_RossHook(bias)) votes++;

   // 6. EXECUTE
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
   if(!InpBiasEnabled) return 0;

   // Manual
   if(InpBiasMode == BIAS_MANUAL) {
      if(InpManualSide == SIDE_LONG)  return 1;
      if(InpManualSide == SIDE_SHORT) return -1;
      return GetSlope(g_h_ema4); // Both = Slope
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
   double price = iClose(_Symbol, PERIOD_CURRENT, 1);
   double ema   = GetIndValue(g_h_ema1, 1);
   return (bias == 1) ? (price > ema) : (price < ema);
}

bool CheckSignal_ADX() {
   double adx = GetIndValue(g_h_adx, 1);
   return (adx > InpAdxThreshold);
}

bool CheckSignal_MACD(int bias) {
   double main[], sig[];
   if(!GetIndBuffer(g_h_macd, 0, 1, main) || !GetIndBuffer(g_h_macd, 1, 1, sig)) return false;
   if(InpMacdMode == MACD_SIGNAL_ALIGN) return (bias == 1) ? (main[0] > sig[0]) : (main[0] < sig[0]);
   if(InpMacdMode == MACD_ZERO_LEVEL)   return (bias == 1) ? (main[0] > 0) : (main[0] < 0);
   return false;
}

bool CheckSignal_RSI(int bias) {
   double rsi = GetIndValue(g_h_rsi, 1);
   if(InpRsiMode == RSI_FILTER_EXTREME) {
      if(bias == 1) return (rsi < InpRsiOverbought); // Safe to buy
      if(bias == -1) return (rsi > InpRsiOversold);   // Safe to sell
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
   // Buy: K > D (Momentum up) and not overbought yet (optional, simplified here)
   return (bias == 1) ? (k[0] > d[0]) : (k[0] < d[0]);
}

bool CheckSignal_BB(int bias) {
   double mid = GetIndValue(g_h_bb, 0); 
   double close = iClose(_Symbol, PERIOD_CURRENT, 1);
   return (bias == 1) ? (close > mid) : (close < mid);
}

bool CheckSignal_PSAR(int bias) {
   double psar = GetIndValue(g_h_psar, 1);
   double close = iClose(_Symbol, PERIOD_CURRENT, 1);
   return (bias == 1) ? (close > psar) : (close < psar);
}

bool CheckSignal_RossHook(int bias) {
   // Look for recent fractal breakout
   int lookback = 10;
   double fractal_level = 0;
   
   for(int i=2; i<=lookback; i++) {
      double up[1], down[1];
      CopyBuffer(g_h_fractals, 0, i, 1, up);
      CopyBuffer(g_h_fractals, 1, i, 1, down);
      
      if(bias == 1 && up[0] != DBL_MAX && up[0] > 0) {
         fractal_level = up[0]; break;
      }
      if(bias == -1 && down[0] != DBL_MAX && down[0] > 0) {
         fractal_level = down[0]; break;
      }
   }
   
   if(fractal_level == 0) return false;
   double close = iClose(_Symbol, PERIOD_CURRENT, 1);
   return (bias == 1) ? (close > fractal_level) : (close < fractal_level);
}

//+------------------------------------------------------------------+
//| UTILITIES                                                        |
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

//+------------------------------------------------------------------+
//| EXECUTION & EXIT                                                 |
//+------------------------------------------------------------------+
void OpenTrade(ENUM_ORDER_TYPE type) {
   double atr = GetIndValue(g_h_atr, 1);
   double sl_dist = atr * InpSLMultiplier;
   double tp_dist = atr * InpTPMultiplier;
   
   double price = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl = (type == ORDER_TYPE_BUY) ? price - sl_dist : price + sl_dist;
   double tp = (type == ORDER_TYPE_BUY) ? price + tp_dist : price - tp_dist;
   
   // Normalize
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   sl = NormalizeDouble(sl, digits);
   tp = NormalizeDouble(tp, digits);
   
   // Lot Calc
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk = balance * (InpRiskPercent / 100.0);
   double tick_val = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tick_val == 0) tick_val = 1.0; 
   double lot = (risk / sl_dist) / tick_val;
   
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   lot = MathFloor(lot / step) * step;
   double min = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if(lot < min) lot = min;
   
   // EXECUTE
   if(trade.PositionOpen(_Symbol, type, lot, price, sl, tp, "SimpleEA v1.02.3")) {
      Print("=== TRADE OPENED ===");
      Print("Type: ", EnumToString(type));
      Print("Size: ", lot, " lots");
      Print("Price: ", price);
      Print("SL: ", sl, " (", DoubleToString(sl_dist/_Point,0), " pts)");
      Print("TP: ", tp);
      Print("====================");
   } else {
      Print("ERROR: Trade Open Failed. Code: ", GetLastError());
   }
}

void ManageExit() {
   if(InpTrailMode == TRAIL_NONE) return;
   
   if(!PositionSelect(_Symbol)) return;
   
   double new_sl = 0.0;
   ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   double current_sl = PositionGetDouble(POSITION_SL);
   double current_price = PositionGetDouble(POSITION_PRICE_CURRENT);
   
   // --- CALCULATE TRAILING LEVEL ---
   if(InpTrailMode == TRAIL_ATR) {
      double atr = GetIndValue(g_h_atr, 1);
      double dist = atr * InpTrailATRMult;
      new_sl = (type == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) - dist 
                                           : SymbolInfoDouble(_Symbol, SYMBOL_ASK) + dist;
   }
   
   else if(InpTrailMode == TRAIL_PSAR) {
      double psar = GetIndValue(g_h_psar, 1); // Value at close of bar 1
      new_sl = psar;
      // Safety: ensure PSAR is on correct side
      if(type == POSITION_TYPE_BUY && new_sl > current_price) return;
      if(type == POSITION_TYPE_SELL && new_sl < current_price) return;
   }
   
   else if(InpTrailMode == TRAIL_FRACTAL) {
      // Find most recent Valid Fractal
      for(int i=2; i<20; i++) {
         double up[1], down[1];
         CopyBuffer(g_h_fractals, 0, i, 1, up);
         CopyBuffer(g_h_fractals, 1, i, 1, down);
         
         if(type == POSITION_TYPE_BUY && down[0] != DBL_MAX && down[0] > 0) {
            new_sl = down[0]; break;
         }
         if(type == POSITION_TYPE_SELL && up[0] != DBL_MAX && up[0] > 0) {
            new_sl = up[0]; break;
         }
      }
      if(new_sl == 0.0) return; // No fractal found
   }

   // --- MODIFY POSITION ---
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   new_sl = NormalizeDouble(new_sl, digits);
   
   bool modify = false;
   if(type == POSITION_TYPE_BUY) {
      if(new_sl > current_sl && new_sl < current_price) modify = true;
   } else {
      if((new_sl < current_sl || current_sl == 0) && new_sl > current_price) modify = true;
   }
   
   if(modify) {
      if(trade.PositionModify(_Symbol, new_sl, PositionGetDouble(POSITION_TP))) {
         // Optional: Print("Trailing Stop Updated: ", new_sl);
      }
   }
}