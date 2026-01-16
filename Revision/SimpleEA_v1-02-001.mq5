//+------------------------------------------------------------------+
//|                                           SimpleEA_v1-02-001.mq5 |
//|                                  Institutional Trading Solutions |
//|                                       Elastic & Modular Redesign |
//+------------------------------------------------------------------+
#property copyright "SimpleEA Redesign"
#property version   "1.02"
#property strict

#include <Trade\Trade.mqh>

//--- ENUMS FOR ELASTIC CONFIGURATION ---
enum EBiasMode {
   BIAS_MANUAL,   // Manual Direction
   BIAS_AUTO      // Auto Indicator
};

enum EManualSide {
   SIDE_BOTH,     // Long and Short
   SIDE_LONG,     // Long Only
   SIDE_SHORT     // Short Only
};

enum EAutoStrategy {
   STRAT_SINGLE,  // Single Indicator (Slope/Price Cross)
   STRAT_PAIR     // Two Indicators (Crossover)
};

enum ELogicSingle {
   LOGIC_PRICE_CROSS, // Price above/below indicator
   LOGIC_SLOPE        // Indicator sloping up/down
};

enum ELogicPair {
   LOGIC_CROSS,   // Fast > Slow
   LOGIC_STRICT   // Fast > Slow AND Slope align
};

enum EEmaRole {
   ROLE_EMA1, ROLE_EMA2, ROLE_EMA3, ROLE_EMA4
};

//--- GLOBAL OBJECTS ---
CTrade trade;
int    g_handle_ema1, g_handle_ema2, g_handle_ema3, g_handle_ema4;
int    g_handle_macd, g_handle_rsi, g_handle_cci, g_handle_sto, g_handle_atr, g_handle_bb, g_handle_psar, g_handle_fractals;
datetime g_last_bar_time = 0;

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                 |
//+------------------------------------------------------------------+
input group "=== 1. RISK MANAGEMENT ==="
input double InpRiskPercent      = 2.0;      // Risk per trade (%)
input double InpMaxSpreadPips    = 3.0;      // Max Spread (Pips)
input double InpMinATRPips       = 5.0;      // Min Volatility (ATR Pips)

input group "=== 2. MARKET BIAS (Trend) ==="
input bool          InpBiasEnabled   = true;        // Master Bias Switch
input EBiasMode     InpBiasMode      = BIAS_AUTO;   // Bias Mode
input EManualSide   InpManualSide    = SIDE_BOTH;   // Manual: Allowed Sides
input EAutoStrategy InpAutoStrat     = STRAT_PAIR;  // Auto: Strategy
input EEmaRole      InpSingleRef     = ROLE_EMA4;   // Auto-Single: Reference Indicator
input ELogicSingle  InpSingleLogic   = LOGIC_SLOPE; // Auto-Single: Logic
input EEmaRole      InpPairFast      = ROLE_EMA3;   // Auto-Pair: Fast Ind
input EEmaRole      InpPairSlow      = ROLE_EMA4;   // Auto-Pair: Slow Ind

input group "=== 3. EMA SETTINGS ==="
input int InpEMA1_Period = 13;   // EMA 1 Period
input int InpEMA2_Period = 21;   // EMA 2 Period
input int InpEMA3_Period = 34;   // EMA 3 Period
input int InpEMA4_Period = 55;   // EMA 4 Period

input group "=== 4. INDICATOR FILTERS (ON/OFF) ==="
// EMA Filter (Price vs EMA1 - Recovery)
input bool InpUseEmaFilter   = true;  // Filter: Price vs EMA1 (Recovery)
// MACD
input bool InpUseMacd        = true;  // Filter: MACD Alignment
input int  InpMacdFast       = 12;
input int  InpMacdSlow       = 26;
input int  InpMacdSig        = 9;
// RSI
input bool InpUseRsi         = false; // Filter: RSI Extremes
input int  InpRsiPeriod      = 14;
input double InpRsiUpper     = 70;
input double InpRsiLower     = 30;
// Bollinger Bands
input bool InpUseBB          = false; // Filter: Price inside BB
input int  InpBbPeriod       = 20;
input double InpBbDev        = 2.0;
// CCI
input bool InpUseCCI         = false; // Filter: CCI Direction
input int  InpCciPeriod      = 14;
input double InpCciLevel     = 100;   // +/- Level
// Stochastic
input bool InpUseSto         = false; // Filter: Stochastic Direction
input int  InpStoK           = 5;
input int  InpStoD           = 3;
input int  InpStoSlow        = 3;
// PSAR
input bool InpUsePsar        = false; // Filter: PSAR Direction
input double InpPsarStep     = 0.02;
input double InpPsarMax      = 0.2;
// Ross Hook (Fractal Breakout)
input bool InpUseRossHook    = false; // Filter: Ross Hook (Fractal Break)

input group "=== 5. EXIT RULES ==="
input double InpSLMultiplier    = 2.0;   // SL (ATR Multiplier)
input double InpTPMultiplier    = 4.0;   // TP (ATR Multiplier)
input bool   InpTrailStop       = true;  // Trailing Stop
input double InpTrailMultiplier = 1.5;   // Trailing Step (ATR)

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Initialize Indicators
   g_handle_ema1 = iMA(_Symbol, PERIOD_CURRENT, InpEMA1_Period, 0, MODE_EMA, PRICE_CLOSE);
   g_handle_ema2 = iMA(_Symbol, PERIOD_CURRENT, InpEMA2_Period, 0, MODE_EMA, PRICE_CLOSE);
   g_handle_ema3 = iMA(_Symbol, PERIOD_CURRENT, InpEMA3_Period, 0, MODE_EMA, PRICE_CLOSE);
   g_handle_ema4 = iMA(_Symbol, PERIOD_CURRENT, InpEMA4_Period, 0, MODE_EMA, PRICE_CLOSE);
   
   g_handle_atr  = iATR(_Symbol, PERIOD_CURRENT, 14);
   
   if(InpUseMacd) g_handle_macd = iMACD(_Symbol, PERIOD_CURRENT, InpMacdFast, InpMacdSlow, InpMacdSig, PRICE_CLOSE);
   if(InpUseRsi)  g_handle_rsi  = iRSI(_Symbol, PERIOD_CURRENT, InpRsiPeriod, PRICE_CLOSE);
   if(InpUseBB)   g_handle_bb   = iBands(_Symbol, PERIOD_CURRENT, InpBbPeriod, 0, InpBbDev, PRICE_CLOSE);
   if(InpUseCCI)  g_handle_cci  = iCCI(_Symbol, PERIOD_CURRENT, InpCciPeriod, PRICE_CLOSE);
   if(InpUseSto)  g_handle_sto  = iStochastic(_Symbol, PERIOD_CURRENT, InpStoK, InpStoD, InpStoSlow, MODE_SMA, STO_LOWHIGH);
   if(InpUsePsar) g_handle_psar = iSAR(_Symbol, PERIOD_CURRENT, InpPsarStep, InpPsarMax);
   if(InpUseRossHook) g_handle_fractals = iFractals(_Symbol, PERIOD_CURRENT);

   if(g_handle_ema1 == INVALID_HANDLE || g_handle_atr == INVALID_HANDLE) return INIT_FAILED;
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Deinitialization                                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(g_handle_ema1); IndicatorRelease(g_handle_ema2);
   IndicatorRelease(g_handle_ema3); IndicatorRelease(g_handle_ema4);
   IndicatorRelease(g_handle_atr);
   if(InpUseMacd) IndicatorRelease(g_handle_macd);
   if(InpUseRsi)  IndicatorRelease(g_handle_rsi);
   if(InpUseBB)   IndicatorRelease(g_handle_bb);
   if(InpUseCCI)  IndicatorRelease(g_handle_cci);
   if(InpUseSto)  IndicatorRelease(g_handle_sto);
   if(InpUsePsar) IndicatorRelease(g_handle_psar);
   if(InpUseRossHook) IndicatorRelease(g_handle_fractals);
}

//+------------------------------------------------------------------+
//| Main OnTick                                                      |
//+------------------------------------------------------------------+
void OnTick()
{
   // 1. New Bar Check
   if(!IsNewBar()) return;
   
   // 2. Manage Open Positions
   if(PositionSelect(_Symbol)) {
      ManageExit();
      return; 
   }

   // 3. Basic Filters (Spread/ATR)
   if(!CheckBasicFilters()) return;

   // 4. DETERMINE BIAS (1=Long, -1=Short, 0=Neutral)
   int bias = GetBias();
   if(bias == 0) return;

   // 5. EVALUATE INDICATORS (Multiplication Rule)
   // Start with the assumption that the trade is valid based on Bias
   bool signal_valid = true;

   // Rule: Signal = Bias * Ind1 * Ind2... 
   // If any enabled indicator returns false, the whole signal becomes 0
   
   if(InpUseEmaFilter && !CheckSignal_EMA1(bias))    signal_valid = false;
   if(InpUseMacd      && !CheckSignal_MACD(bias))    signal_valid = false;
   if(InpUseRsi       && !CheckSignal_RSI(bias))     signal_valid = false;
   if(InpUseBB        && !CheckSignal_BB(bias))      signal_valid = false;
   if(InpUseCCI       && !CheckSignal_CCI(bias))     signal_valid = false;
   if(InpUseSto       && !CheckSignal_Sto(bias))     signal_valid = false;
   if(InpUsePsar      && !CheckSignal_PSAR(bias))    signal_valid = false;
   if(InpUseRossHook  && !CheckSignal_RossHook(bias)) signal_valid = false;

   // 6. EXECUTE
   if(signal_valid) {
      if(bias == 1)      OpenTrade(ORDER_TYPE_BUY);
      else if(bias == -1) OpenTrade(ORDER_TYPE_SELL);
   }
}

//+------------------------------------------------------------------+
//| LOGIC: BIAS DETERMINATION                                        |
//+------------------------------------------------------------------+
int GetBias()
{
   if(!InpBiasEnabled) return 0;

   // --- MANUAL MODE ---
   if(InpBiasMode == BIAS_MANUAL) {
      if(InpManualSide == SIDE_LONG)  return 1;
      if(InpManualSide == SIDE_SHORT) return -1;
      // If SIDE_BOTH, we need a technical trigger. 
      // For this EA, SIDE_BOTH in Manual implies we default to Auto logic 
      // or we need a base technical trigger. Let's assume Auto logic for direction if Both.
      // Or, strictly speaking, Manual Both means "Always in market"? No, dangerous.
      // We will default to EMA4 Slope for direction if Manual Both is selected.
      if(InpManualSide == SIDE_BOTH) return GetSlope(g_handle_ema4); 
   }

   // --- AUTO MODE ---
   double val1 = 0, val2 = 0;
   
   // Get handles based on role selection
   int h1 = GetHandleByRole(InpSingleRef); // Used for Single or Fast Pair
   int h2 = GetHandleByRole(InpPairSlow);  // Used for Slow Pair
   if(InpAutoStrat == STRAT_PAIR) h1 = GetHandleByRole(InpPairFast);

   if(InpAutoStrat == STRAT_SINGLE) {
      if(InpSingleLogic == LOGIC_SLOPE) return GetSlope(h1);
      if(InpSingleLogic == LOGIC_PRICE_CROSS) {
         double price = iClose(_Symbol, PERIOD_CURRENT, 1);
         double ind   = GetIndValue(h1, 1);
         if(price > ind) return 1;
         if(price < ind) return -1;
      }
   }
   
   if(InpAutoStrat == STRAT_PAIR) {
      double fast = GetIndValue(h1, 1);
      double slow = GetIndValue(h2, 1);
      if(fast > slow) return 1;
      if(fast < slow) return -1;
   }
   
   return 0;
}

//+------------------------------------------------------------------+
//| LOGIC: INDIVIDUAL INDICATOR CHECKS                               |
//| Returns TRUE if indicator confirms Bias or is Neutral            |
//+------------------------------------------------------------------+

bool CheckSignal_EMA1(int bias) {
   // Recovery check: Price must be on correct side of EMA1 (Fastest)
   double price = iClose(_Symbol, PERIOD_CURRENT, 1);
   double ema1  = GetIndValue(g_handle_ema1, 1);
   if(bias == 1  && price > ema1) return true;
   if(bias == -1 && price < ema1) return true;
   return false;
}

bool CheckSignal_MACD(int bias) {
   double main[], sig[];
   if(GetIndBuffer(g_handle_macd, 0, 1, main) && GetIndBuffer(g_handle_macd, 1, 1, sig)) {
      if(bias == 1  && main[0] > sig[0]) return true;
      if(bias == -1 && main[0] < sig[0]) return true;
   }
   return false;
}

bool CheckSignal_RSI(int bias) {
   double rsi = GetIndValue(g_handle_rsi, 1);
   // Filter: Don't buy if overbought, Don't sell if oversold
   if(bias == 1  && rsi < InpRsiUpper) return true;
   if(bias == -1 && rsi > InpRsiLower) return true;
   return false;
}

bool CheckSignal_BB(int bias) {
   // Simple Logic: Trend Mode -> Buy if price > Middle Band
   double mid = GetIndValue(g_handle_bb, 1); // Base line is buffer 0 usually
   double close = iClose(_Symbol, PERIOD_CURRENT, 1);
   if(bias == 1  && close > mid) return true;
   if(bias == -1 && close < mid) return true;
   return false;
}

bool CheckSignal_CCI(int bias) {
   double cci = GetIndValue(g_handle_cci, 1);
   if(bias == 1  && cci > 0) return true;
   if(bias == -1 && cci < 0) return true;
   return false;
}

bool CheckSignal_Sto(int bias) {
   double main[], sig[];
   // Buffer 0 is Main, 1 is Signal
   // Note: iStochastic buffers vary. Usually 0=Main, 1=Signal
   // Logic: Buy if Main > Signal (Upside momentum)
   // But we need to use CopyBuffer specifically for Sto
   double k[1], d[1];
   CopyBuffer(g_handle_sto, 0, 1, 1, k);
   CopyBuffer(g_handle_sto, 1, 1, 1, d);
   if(bias == 1  && k[0] > d[0]) return true;
   if(bias == -1 && k[0] < d[0]) return true;
   return false;
}

bool CheckSignal_PSAR(int bias) {
   double psar = GetIndValue(g_handle_psar, 1);
   double close = iClose(_Symbol, PERIOD_CURRENT, 1);
   if(bias == 1  && close > psar) return true;
   if(bias == -1 && close < psar) return true;
   return false;
}

bool CheckSignal_RossHook(int bias) {
   // Simplified Ross Hook / Fractal Breakout
   // Look back 5 bars. Find a fractal.
   // If Bias Long, we need a Down Fractal (Swing Low) formed recently, and price moving up?
   // Or specific RH: Breakout of the last High Fractal in an uptrend.
   
   // Logic: If Bias is Long, we confirm if Close > Last Upper Fractal
   // If Bias is Short, we confirm if Close < Last Lower Fractal
   
   for(int i=2; i<10; i++) {
      double up=0, down=0;
      double buff_up[1], buff_down[1];
      CopyBuffer(g_handle_fractals, 0, i, 1, buff_up);   // Upper
      CopyBuffer(g_handle_fractals, 1, i, 1, buff_down); // Lower
      
      if(bias == 1 && buff_up[0] != DBL_MAX && buff_up[0] > 0) {
         // Found recent high fractal. Are we breaking it?
         double close = iClose(_Symbol, PERIOD_CURRENT, 1);
         if(close > buff_up[0]) return true; 
      }
      if(bias == -1 && buff_down[0] != DBL_MAX && buff_down[0] > 0) {
         // Found recent low fractal
         double close = iClose(_Symbol, PERIOD_CURRENT, 1);
         if(close < buff_down[0]) return true;
      }
   }
   return false; // No breakout found
}

//+------------------------------------------------------------------+
//| HELPER FUNCTIONS                                                 |
//+------------------------------------------------------------------+
bool IsNewBar() {
   datetime curr = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(curr != g_last_bar_time) { g_last_bar_time = curr; return true; }
   return false;
}

int GetHandleByRole(EEmaRole role) {
   switch(role) {
      case ROLE_EMA1: return g_handle_ema1;
      case ROLE_EMA2: return g_handle_ema2;
      case ROLE_EMA3: return g_handle_ema3;
      case ROLE_EMA4: return g_handle_ema4;
   }
   return g_handle_ema4;
}

double GetIndValue(int handle, int shift) {
   double buf[1];
   if(CopyBuffer(handle, 0, shift, 1, buf) > 0) return buf[0];
   return 0.0;
}

bool GetIndBuffer(int handle, int buffer_num, int shift, double &result[]) {
   return (CopyBuffer(handle, buffer_num, shift, 1, result) > 0);
}

int GetSlope(int handle) {
   double curr = GetIndValue(handle, 1);
   double prev = GetIndValue(handle, 2);
   if(curr > prev) return 1;
   if(curr < prev) return -1;
   return 0;
}

bool CheckBasicFilters() {
   // Spread
   double spread = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / _Point;
   if(spread > InpMaxSpreadPips * 10) return false;
   
   // ATR
   double atr = GetIndValue(g_handle_atr, 1);
   if((atr / (_Point * 10)) < InpMinATRPips) return false;
   
   return true;
}

//+------------------------------------------------------------------+
//| EXECUTION MANAGEMENT                                             |
//+------------------------------------------------------------------+
void OpenTrade(ENUM_ORDER_TYPE type) {
   double atr = GetIndValue(g_handle_atr, 1);
   double sl_dist = atr * InpSLMultiplier;
   double tp_dist = atr * InpTPMultiplier;
   
   double price = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl = (type == ORDER_TYPE_BUY) ? price - sl_dist : price + sl_dist;
   double tp = (type == ORDER_TYPE_BUY) ? price + tp_dist : price - tp_dist;
   
   // Lot Calc
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk = balance * (InpRiskPercent / 100.0);
   double tick_val = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double lot = (risk / sl_dist) / tick_val;
   
   // Normalize Lot
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   lot = MathFloor(lot / step) * step;
   double min = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if(lot < min) lot = min;

   trade.PositionOpen(_Symbol, type, lot, price, sl, tp, "SimpleEA v1.02");
}

void ManageExit() {
   if(!InpTrailStop) return;
   double atr = GetIndValue(g_handle_atr, 1);
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
//+------------------------------------------------------------------+