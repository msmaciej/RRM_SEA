//+------------------------------------------------------------------+
//| Test_SwingDetector.mq5                                            |
//| Test script for Swing Detector module                            |
//+------------------------------------------------------------------+
#property copyright "RRM EA"
#property version   "1.00"
#property script_show_inputs

#include <RRM\RRM_EAv1.0_TS_SwingDetector.mqh>

input int InpLookback     = 50;    // Bars to scan
input int InpSwingBars    = 3;     // Bars on each side
input int InpMaxSwings    = 10;    // Max swings to find

//+------------------------------------------------------------------+
void OnStart()
{
    string symbol = _Symbol;
    ENUM_TIMEFRAMES tf = _Period;
    
    Print("=== Swing Detector Test ===");
    Print("Symbol: ", symbol, " Timeframe: ", EnumToString(tf));
    
    // Test 1: Find swing highs
    SwingPoint highs[];
    int num_highs = FindSwingHighs(symbol, tf, 1, InpLookback, InpSwingBars, highs, InpMaxSwings);
    
    Print("\n--- Swing Highs Found:  ", num_highs, " ---");
    for(int i = 0; i < num_highs; i++) {
        Print("High #", i+1, ": Bar=", highs[i].bar_index, 
              " Price=", DoubleToString(highs[i].price, _Digits),
              " Time=", TimeToString(highs[i].time));
    }
    
    // Test 2: Find swing lows
    SwingPoint lows[];
    int num_lows = FindSwingLows(symbol, tf, 1, InpLookback, InpSwingBars, lows, InpMaxSwings);
    
    Print("\n--- Swing Lows Found: ", num_lows, " ---");
    for(int i = 0; i < num_lows; i++) {
        Print("Low #", i+1, ": Bar=", lows[i].bar_index,
              " Price=", DoubleToString(lows[i].price, _Digits),
              " Time=", TimeToString(lows[i].time));
    }
    
    // Test 3: Check specific bar
    int test_bar = 10;
    bool is_high = IsSwingHigh(symbol, tf, test_bar, InpSwingBars, InpSwingBars);
    bool is_low  = IsSwingLow(symbol, tf, test_bar, InpSwingBars, InpSwingBars);
    
    Print("\n--- Bar ", test_bar, " Analysis ---");
    Print("Is Swing High: ", is_high ?  "YES" : "NO");
    Print("Is Swing Low: ", is_low ? "YES" : "NO");
    
    Print("\n=== Test Complete ===");
}