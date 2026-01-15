//+------------------------------------------------------------------+
//|                                                  SimpleEA_v1.mq5 |
//|                                         Simplified Trading System |
//|                                                                    |
//| PHILOSOPHY:  Simple, robust, fast.  One file, clear logic.          |
//| INDICATORS: EMA, MACD, RSI, ATR, Pullback, Candle                |
//| CONFIG: JSON-driven (SimpleEA_Settings.json)                     |
//+------------------------------------------------------------------+
#property copyright "Simple EA"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
#include <JAson. mqh>

//--- Global objects
CTrade trade;
CJAVal root;

//--- Settings loaded from JSON
struct EASettings {
    // Risk Management
    double risk_percent;
    double max_spread_pips;
    double min_atr_pips;
    
    // EMA Periods
    int ema_fast;
    int ema_mid1;
    int ema_mid2;
    int ema_slow;
    
    // MACD
    int macd_fast;
    int macd_slow;
    int macd_signal;
    
    // RSI
    int rsi_period;
    double rsi_oversold;
    double rsi_overbought;
    
    // ATR
    int atr_period;
    
    // Entry Rules
    double min_body_pips;
    int pullback_lookback;
    bool require_macd_align;
    bool require_rsi_filter;
    
    // Trade Management
    double sl_atr_multiplier;
    double tp_atr_multiplier;
    bool trail_stop;
    double trail_atr_multiplier;
};

EASettings g_settings;
datetime g_last_bar_time = 0;

//+------------------------------------------------------------------+
//| Expert initialization                                             |
//+------------------------------------------------------------------+
int OnInit()
{
    Print("=== SimpleEA v1.0 Initializing ===");
    
    // Load JSON settings
    if(!LoadSettings()) {
        Print("ERROR: Failed to load settings from JSON");
        return INIT_FAILED;
    }
    
    Print("Settings loaded successfully");
    Print("EMA periods: ", g_settings.ema_fast, "/", g_settings.ema_mid1, 
          "/", g_settings. ema_mid2, "/", g_settings.ema_slow);
    
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    Print("=== SimpleEA v1.0 Stopped ===");
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
    // Only trade on new bar (closed bar semantics)
    if(!IsNewBar()) return;
    
    // Check if we already have a position
    if(PositionSelect(_Symbol)) {
        ManageOpenPosition();
        return;
    }
    
    // Evaluate entry signals
    int signal = EvaluateEntry();
    
    if(signal == 1) {
        OpenTrade(ORDER_TYPE_BUY);
    }
    else if(signal == -1) {
        OpenTrade(ORDER_TYPE_SELL);
    }
}

//+------------------------------------------------------------------+
//| Load settings from JSON file                                      |
//+------------------------------------------------------------------+
bool LoadSettings()
{
    string filename = "SimpleEA_Settings. json";
    
    // Load JSON
    int handle = FileOpen(filename, FILE_READ|FILE_TXT);
    if(handle == INVALID_HANDLE) {
        Print("ERROR: Cannot open ", filename);
        return false;
    }
    
    string json_text = "";
    while(! FileIsEnding(handle)) {
        json_text += FileReadString(handle);
    }
    FileClose(handle);
    
    // Parse JSON
    root. Deserialize(json_text);
    
    // Load settings
    g_settings.risk_percent = root["risk"]["percent"]. ToDouble();
    g_settings.max_spread_pips = root["risk"]["max_spread_pips"].ToDouble();
    g_settings.min_atr_pips = root["risk"]["min_atr_pips"].ToDouble();
    
    g_settings.ema_fast = (int)root["indicators"]["ema"]["fast"].ToInt();
    g_settings.ema_mid1 = (int)root["indicators"]["ema"]["mid1"].ToInt();
    g_settings.ema_mid2 = (int)root["indicators"]["ema"]["mid2"]. ToInt();
    g_settings.ema_slow = (int)root["indicators"]["ema"]["slow"].ToInt();
    
    g_settings.macd_fast = (int)root["indicators"]["macd"]["fast"].ToInt();
    g_settings.macd_slow = (int)root["indicators"]["macd"]["slow"]. ToInt();
    g_settings.macd_signal = (int)root["indicators"]["macd"]["signal"].ToInt();
    
    g_settings.rsi_period = (int)root["indicators"]["rsi"]["period"].ToInt();
    g_settings.rsi_oversold = root["indicators"]["rsi"]["oversold"].ToDouble();
    g_settings.rsi_overbought = root["indicators"]["rsi"]["overbought"].ToDouble();
    
    g_settings.atr_period = (int)root["indicators"]["atr"]["period"].ToInt();
    
    g_settings.min_body_pips = root["entry"]["min_body_pips"]. ToDouble();
    g_settings.pullback_lookback = (int)root["entry"]["pullback_lookback"].ToInt();
    g_settings.require_macd_align = root["entry"]["require_macd_align"].ToBool();
    g_settings.require_rsi_filter = root["entry"]["require_rsi_filter"].ToBool();
    
    g_settings.sl_atr_multiplier = root["exit"]["sl_atr_multiplier"].ToDouble();
    g_settings.tp_atr_multiplier = root["exit"]["tp_atr_multiplier"].ToDouble();
    g_settings.trail_stop = root["exit"]["trail_stop"].ToBool();
    g_settings.trail_atr_multiplier = root["exit"]["trail_atr_multiplier"].ToDouble();
    
    return true;
}

//+------------------------------------------------------------------+
//| Check if new bar formed                                           |
//+------------------------------------------------------------------+
bool IsNewBar()
{
    datetime current_bar_time = iTime(_Symbol, PERIOD_CURRENT, 0);
    if(current_bar_time != g_last_bar_time) {
        g_last_bar_time = current_bar_time;
        return true;
    }
    return false;
}

//+------------------------------------------------------------------+
//| Main entry evaluation logic                                       |
//| Returns: 1=BUY, -1=SELL, 0=NO SIGNAL                            |
//+------------------------------------------------------------------+
int EvaluateEntry()
{
    // 1. Get current bar data (closed bar = shift 1)
    double close = iClose(_Symbol, PERIOD_CURRENT, 1);
    double open = iOpen(_Symbol, PERIOD_CURRENT, 1);
    double high = iHigh(_Symbol, PERIOD_CURRENT, 1);
    double low = iLow(_Symbol, PERIOD_CURRENT, 1);
    
    // 2. Calculate indicators
    double ema_fast = CalculateEMA(g_settings.ema_fast, 1);
    double ema_mid1 = CalculateEMA(g_settings.ema_mid1, 1);
    double ema_mid2 = CalculateEMA(g_settings.ema_mid2, 1);
    double ema_slow = CalculateEMA(g_settings.ema_slow, 1);
    
    // 3. Check basic filters
    if(! CheckSpread()) return 0;
    if(! CheckATRVolatility()) return 0;
    if(!CheckCandleBody(open, close)) return 0;
    
    // 4. Determine trend direction
    int trend = GetTrendDirection(ema_fast, ema_mid1, ema_mid2, ema_slow);
    if(trend == 0) return 0; // No clear trend
    
    // 5. Check pullback
    if(! CheckPullback(trend, ema_mid1)) return 0;
    
    // 6. Optional:  MACD alignment
    if(g_settings.require_macd_align) {
        if(!CheckMACDAlign(trend)) return 0;
    }
    
    // 7. Optional: RSI filter
    if(g_settings.require_rsi_filter) {
        if(!CheckRSIFilter(trend)) return 0;
    }
    
    // 8. Final confirmation:  price recovered from pullback
    if(trend == 1 && close > ema_fast) return 1;  // BUY
    if(trend == -1 && close < ema_fast) return -1; // SELL
    
    return 0;
}

//+------------------------------------------------------------------+
//| Calculate EMA (simple implementation)                             |
//+------------------------------------------------------------------+
double CalculateEMA(int period, int shift)
{
    int handle = iMA(_Symbol, PERIOD_CURRENT, period, 0, MODE_EMA, PRICE_CLOSE);
    if(handle == INVALID_HANDLE) return 0;
    
    double buffer[1];
    if(CopyBuffer(handle, 0, shift, 1, buffer) <= 0) {
        IndicatorRelease(handle);
        return 0;
    }
    
    IndicatorRelease(handle);
    return buffer[0];
}

//+------------------------------------------------------------------+
//| Check spread filter                                               |
//+------------------------------------------------------------------+
bool CheckSpread()
{
    double spread = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - 
                     SymbolInfoDouble(_Symbol, SYMBOL_BID)) / _Point;
    
    return (spread <= g_settings.max_spread_pips * 10); // *10 for pips to points
}

//+------------------------------------------------------------------+
//| Check ATR volatility filter                                       |
//+------------------------------------------------------------------+
bool CheckATRVolatility()
{
    int handle = iATR(_Symbol, PERIOD_CURRENT, g_settings.atr_period);
    if(handle == INVALID_HANDLE) return false;
    
    double atr[1];
    if(CopyBuffer(handle, 0, 1, 1, atr) <= 0) {
        IndicatorRelease(handle);
        return false;
    }
    
    IndicatorRelease(handle);
    
    double atr_pips = atr[0] / (_Point * 10);
    return (atr_pips >= g_settings.min_atr_pips);
}

//+------------------------------------------------------------------+
//| Check candle body size                                            |
//+------------------------------------------------------------------+
bool CheckCandleBody(double open, double close)
{
    double body_pips = MathAbs(close - open) / (_Point * 10);
    return (body_pips >= g_settings.min_body_pips);
}

//+------------------------------------------------------------------+
//| Get trend direction from EMA stack                                |
//| Returns: 1=BULLISH, -1=BEARISH, 0=NO TREND                       |
//+------------------------------------------------------------------+
int GetTrendDirection(double ema_fast, double ema_mid1, double ema_mid2, double ema_slow)
{
    // Bullish: EMAs stacked from fast (top) to slow (bottom)
    if(ema_fast > ema_mid1 && ema_mid1 > ema_mid2 && ema_mid2 > ema_slow)
        return 1;
    
    // Bearish: EMAs stacked from fast (bottom) to slow (top)
    if(ema_fast < ema_mid1 && ema_mid1 < ema_mid2 && ema_mid2 < ema_slow)
        return -1;
    
    return 0; // Choppy/no trend
}

//+------------------------------------------------------------------+
//| Check pullback to EMA                                             |
//+------------------------------------------------------------------+
bool CheckPullback(int trend, double ema_pullback)
{
    // Look back N bars to see if price touched the pullback EMA
    for(int i = 1; i <= g_settings.pullback_lookback; i++) {
        double high = iHigh(_Symbol, PERIOD_CURRENT, i);
        double low = iLow(_Symbol, PERIOD_CURRENT, i);
        
        if(trend == 1) {
            // Bullish:  check if price touched EMA from above
            if(low <= ema_pullback * 1.0005) return true; // 0.05% tolerance
        }
        else if(trend == -1) {
            // Bearish: check if price touched EMA from below
            if(high >= ema_pullback * 0.9995) return true;
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Check MACD alignment with trend                                   |
//+------------------------------------------------------------------+
bool CheckMACDAlign(int trend)
{
    int handle = iMACD(_Symbol, PERIOD_CURRENT, 
                       g_settings.macd_fast, g_settings.macd_slow, 
                       g_settings.macd_signal, PRICE_CLOSE);
    if(handle == INVALID_HANDLE) return true; // Don't block trade if MACD fails
    
    double main[1], signal[1];
    if(CopyBuffer(handle, 0, 1, 1, main) <= 0 || CopyBuffer(handle, 1, 1, 1, signal) <= 0) {
        IndicatorRelease(handle);
        return true;
    }
    
    IndicatorRelease(handle);
    
    if(trend == 1) return (main[0] > signal[0]); // Bullish MACD
    if(trend == -1) return (main[0] < signal[0]); // Bearish MACD
    
    return false;
}

//+------------------------------------------------------------------+
//| Check RSI filter (avoid extremes)                                 |
//+------------------------------------------------------------------+
bool CheckRSIFilter(int trend)
{
    int handle = iRSI(_Symbol, PERIOD_CURRENT, g_settings.rsi_period, PRICE_CLOSE);
    if(handle == INVALID_HANDLE) return true; // Don't block if RSI fails
    
    double rsi[1];
    if(CopyBuffer(handle, 0, 1, 1, rsi) <= 0) {
        IndicatorRelease(handle);
        return true;
    }
    
    IndicatorRelease(handle);
    
    if(trend == 1) return (rsi[0] < g_settings.rsi_overbought); // Not overbought for BUY
    if(trend == -1) return (rsi[0] > g_settings.rsi_oversold);  // Not oversold for SELL
    
    return false;
}

//+------------------------------------------------------------------+
//| Open trade with calculated SL/TP                                  |
//+------------------------------------------------------------------+
void OpenTrade(ENUM_ORDER_TYPE order_type)
{
    // Calculate ATR for SL/TP
    int atr_handle = iATR(_Symbol, PERIOD_CURRENT, g_settings.atr_period);
    if(atr_handle == INVALID_HANDLE) return;
    
    double atr[1];
    if(CopyBuffer(atr_handle, 0, 1, 1, atr) <= 0) {
        IndicatorRelease(atr_handle);
        return;
    }
    IndicatorRelease(atr_handle);
    
    double atr_value = atr[0];
    
    // Calculate position size based on risk
    double account_balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double risk_amount = account_balance * (g_settings.risk_percent / 100.0);
    double sl_distance = atr_value * g_settings. sl_atr_multiplier;
    double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double lot_size = (risk_amount / sl_distance) / tick_value;
    
    // Normalize lot size
    double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double max_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double lot_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    lot_size = MathFloor(lot_size / lot_step) * lot_step;
    lot_size = MathMax(min_lot, MathMin(max_lot, lot_size));
    
    // Calculate SL/TP levels
    double price = (order_type == ORDER_TYPE_BUY) ? 
                   SymbolInfoDouble(_Symbol, SYMBOL_ASK) : 
                   SymbolInfoDouble(_Symbol, SYMBOL_BID);
    
    double sl_price, tp_price;
    if(order_type == ORDER_TYPE_BUY) {
        sl_price = price - sl_distance;
        tp_price = price + (atr_value * g_settings. tp_atr_multiplier);
    }
    else {
        sl_price = price + sl_distance;
        tp_price = price - (atr_value * g_settings.tp_atr_multiplier);
    }
    
    // Normalize prices
    int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
    sl_price = NormalizeDouble(sl_price, digits);
    tp_price = NormalizeDouble(tp_price, digits);
    
    // Open trade
    string comment = StringFormat("SimpleEA_%s", 
                                  order_type == ORDER_TYPE_BUY ? "BUY" : "SELL");
    
    if(trade. PositionOpen(_Symbol, order_type, lot_size, price, sl_price, tp_price, comment)) {
        Print("=== TRADE OPENED ===");
        Print("Type: ", order_type == ORDER_TYPE_BUY ?  "BUY" : "SELL");
        Print("Lots: ", lot_size);
        Print("Price: ", price);
        Print("SL: ", sl_price, " (-", sl_distance/_Point, " points)");
        Print("TP: ", tp_price);
    }
    else {
        Print("ERROR: Failed to open trade.  Error:  ", GetLastError());
    }
}

//+------------------------------------------------------------------+
//| Manage open position (trailing stop, etc.)                        |
//+------------------------------------------------------------------+
void ManageOpenPosition()
{
    if(! g_settings.trail_stop) return;
    
    // Get position info
    double position_price = PositionGetDouble(POSITION_PRICE_OPEN);
    double current_sl = PositionGetDouble(POSITION_SL);
    ENUM_POSITION_TYPE position_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
    
    // Calculate ATR for trailing
    int atr_handle = iATR(_Symbol, PERIOD_CURRENT, g_settings.atr_period);
    if(atr_handle == INVALID_HANDLE) return;
    
    double atr[1];
    if(CopyBuffer(atr_handle, 0, 1, 1, atr) <= 0) {
        IndicatorRelease(atr_handle);
        return;
    }
    IndicatorRelease(atr_handle);
    
    double trail_distance = atr[0] * g_settings.trail_atr_multiplier;
    double current_price = (position_type == POSITION_TYPE_BUY) ? 
                           SymbolInfoDouble(_Symbol, SYMBOL_BID) : 
                           SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    
    double new_sl;
    bool should_modify = false;
    
    if(position_type == POSITION_TYPE_BUY) {
        new_sl = current_price - trail_distance;
        if(new_sl > current_sl && new_sl < current_price) {
            should_modify = true;
        }
    }
    else {
        new_sl = current_price + trail_distance;
        if(new_sl < current_sl && new_sl > current_price) {
            should_modify = true;
        }
    }
    
    if(should_modify) {
        int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
        new_sl = NormalizeDouble(new_sl, digits);
        
        if(trade.PositionModify(_Symbol, new_sl, PositionGetDouble(POSITION_TP))) {
            Print("Trailing stop updated:  ", new_sl);
        }
    }
}