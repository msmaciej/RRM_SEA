//  SAVE AS UTF-16 LE WITH BOM
//+------------------------------------------------------------------+
//|                         DPI_v30_CLEAN.mq5                         |
//|   Purpose: MT4 DPI replica with GREEN histogram logic            |
//|   Version: 30 CLEAN - Test version with green momentum bars     |
//|                                                                  |
//|   COMPONENTS:                                                    |
//|   1. Blue Line (LEAD)    = MACD Core = EMA(8) - EMA(13)         |
//|   2. Red Line (FOLLOW)   = EMA of Blue Line (signal)            |
//|   3. Red Contour         = Histogram outline                     |
//|   4. YELLOW Histogram    = Positive OR CCI bullish override     |
//|   5. RED Histogram       = Negative OR CCI bearish override     |
//|   6. GREEN Histogram     = STRONG MOMENTUM CONFIRMATION          |
//|                                                                  |
//|   GREEN HISTOGRAM LOGIC:                                         |
//|   In MT4 DPI, there are TWO histogram zones:                     |
//|                                                                  |
//|   ZONE 1: RED/YELLOW histogram                                   |
//|   - Fills gap between Blue (LEAD) and Red (FOLLOW) lines         |
//|   - Value: Blue - Red                                            |
//|   - Color: YELLOW (positive) or RED (negative), CCI can override |
//|                                                                  |
//|   ZONE 2: GREEN histogram                                        |
//|   - Fills gap between 0-line and nearest line to zero            |
//|   - Value: The line closest to zero (Blue or Red)                |
//|   - Appears ONLY when both lines on same side of zero            |
//|                                                                  |
//|   BEARISH GREEN (below zero):                                    |
//|   - Both Blue and Red are below zero                             |
//|   - Green fills space from 0-line down to nearest line           |
//|   - Shows strong bearish trend alignment                         |
//|                                                                  |
//|   BULLISH GREEN (above zero):                                    |
//|   - Both Blue and Red are above zero                             |
//|   - Green fills space from 0-line up to nearest line             |
//|   - Shows strong bullish trend alignment                         |
//|                                                                  |
//|   GREEN DISAPPEARS when:                                         |
//|   - One line crosses zero (lines now opposite sides)             |
//|   - Trend alignment broken, only RED/YELLOW remains              |
//|                                                                  |
//|   HISTOGRAM COLOR PRIORITY (when GREEN enabled):                 |
//|   1. GREEN = Strong momentum (both lines same side of zero)      |
//|   2. YELLOW = Positive hist OR CCI bullish override              |
//|   3. RED = Negative hist OR CCI bearish override                 |
//|                                                                  |
//+------------------------------------------------------------------+
#property strict
#property version   "30.00"
#property indicator_separate_window
#property indicator_buffers 10
#property indicator_plots   6

#property indicator_level1          0.0
#property indicator_levelcolor  clrSilver
#property indicator_levelstyle  STYLE_DOT
#property indicator_levelwidth  1

// Plot 0: Blue MACD core (LEAD line)
#property indicator_label1    "Blue_MACD_Core"
#property indicator_type1     DRAW_LINE
#property indicator_color1    clrDodgerBlue
#property indicator_style1    STYLE_SOLID
#property indicator_width1    2

// Plot 1: Red signal line (FOLLOW line)
#property indicator_label2    "Red_Signal"
#property indicator_type2     DRAW_LINE
#property indicator_color2    clrRed
#property indicator_style2    STYLE_SOLID
#property indicator_width2    2

// Plot 2: Red contour line (follows histogram)
#property indicator_label3    "Red_Contour"
#property indicator_type3     DRAW_LINE
#property indicator_color3    clrRed
#property indicator_style3    STYLE_SOLID
#property indicator_width3    2

// Plot 3: Yellow histogram (positive or CCI override)
#property indicator_label4    "Hist_Positive"
#property indicator_type4     DRAW_HISTOGRAM
#property indicator_color4    clrYellow
#property indicator_style4    STYLE_SOLID
#property indicator_width4    3

// Plot 4: Red histogram (negative or CCI override)
#property indicator_label5    "Hist_Negative"
#property indicator_type5     DRAW_HISTOGRAM
#property indicator_color5    clrRed
#property indicator_style5    STYLE_SOLID
#property indicator_width5    3

// Plot 5: GREEN histogram (strong momentum confirmation)
#property indicator_label6    "Hist_Green_Momentum"
#property indicator_type6     DRAW_HISTOGRAM
#property indicator_color6    clrLimeGreen
#property indicator_style6    STYLE_SOLID
#property indicator_width6    3

//+------------------------------------------------------------------+
//| ENUMERATIONS                                                      |
//+------------------------------------------------------------------+

enum ENUM_CCI_PRICE
{
   CCI_PRICE_TYPICAL = 0,    // Typical Price (HLC/3)
   CCI_PRICE_CLOSE = 1,      // Close
   CCI_PRICE_OPEN = 2,       // Open
   CCI_PRICE_HIGH = 3,       // High
   CCI_PRICE_LOW = 4,        // Low
   CCI_PRICE_MEDIAN = 5,     // Median (HL/2)
   CCI_PRICE_WEIGHTED = 6    // Weighted (HLCC/4)
};

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                  |
//+------------------------------------------------------------------+

// MACD parameters
input int InpFastEMA  = 8;      // Fast EMA period
input int InpSlowEMA  = 13;     // Slow EMA period

// Red signal line selection
input int InpRedLineType = 1;   // Red line type (1=EMA5, 2=EMA8, 3=EMA13, 4=EMA21, 5=Double)
input int InpRedEMA_A    = 5;   // Red EMA period A
input int InpRedEMA_B    = 8;   // Red EMA period B
input int InpRedEMA_C    = 13;  // Red EMA period C
input int InpRedEMA_D    = 21;  // Red EMA period D
input int InpDoubleEMA1  = 5;   // Double smooth: First EMA
input int InpDoubleEMA2  = 3;   // Double smooth: Second EMA

// CCI reset logic parameters
input bool InpEnableCCI     = true;                     // Enable CCI reset logic
input int  InpCCIPeriod     = 13;                       // CCI period
input ENUM_CCI_PRICE InpCCIPrice = CCI_PRICE_TYPICAL;   // CCI price calculation

// GREEN histogram control
input bool InpEnableGreen   = true;                     // Enable GREEN momentum histogram

//+------------------------------------------------------------------+
//| INDICATOR BUFFERS                                                 |
//+------------------------------------------------------------------+

// Visible plot buffers
double g_BlueCore[];      // Blue MACD core line
double g_RedSignal[];     // Red signal line (selected)
double g_RedContour[];    // Red contour line
double g_HistPos[];       // Yellow histogram
double g_HistNeg[];       // Red histogram
double g_HistGreen[];     // GREEN momentum histogram

// Internal calculation buffers
double g_Fast[];          // Fast EMA
double g_Slow[];          // Slow EMA
double g_CCI[];           // CCI values
double g_Histogram[];     // Histogram value (Blue - Red)

//+------------------------------------------------------------------+
//| HELPER FUNCTIONS                                                  |
//+------------------------------------------------------------------+

double _alpha(const int period)
{
   if(period <= 1)
      return 1.0;
   return 2.0 / ((double)period + 1.0);
}

//+------------------------------------------------------------------+
//| Get price for CCI calculation                                     |
//+------------------------------------------------------------------+
double GetCCIPrice(const int bar, const double &high[], const double &low[], 
                   const double &close[], const double &open[])
{
   switch(InpCCIPrice)
   {
      case CCI_PRICE_TYPICAL:  return (high[bar] + low[bar] + close[bar]) / 3.0;
      case CCI_PRICE_CLOSE:    return close[bar];
      case CCI_PRICE_OPEN:     return open[bar];
      case CCI_PRICE_HIGH:     return high[bar];
      case CCI_PRICE_LOW:      return low[bar];
      case CCI_PRICE_MEDIAN:   return (high[bar] + low[bar]) / 2.0;
      case CCI_PRICE_WEIGHTED: return (high[bar] + low[bar] + close[bar] + close[bar]) / 4.0;
      default:                 return (high[bar] + low[bar] + close[bar]) / 3.0;
   }
}

//+------------------------------------------------------------------+
//| Calculate CCI                                                     |
//+------------------------------------------------------------------+
double CalculateCCI(const int period, const int bar_index,
                    const double &high[], const double &low[], 
                    const double &close[], const double &open[])
{
   if(bar_index + period >= ArraySize(high))
      return 0.0;
   
   // Calculate prices for the period
   double prices[];
   ArrayResize(prices, period);
   
   double sum = 0.0;
   for(int i = 0; i < period; i++)
   {
      int idx = bar_index + i;
      prices[i] = GetCCIPrice(idx, high, low, close, open);
      sum += prices[i];
   }
   
   // Calculate SMA
   double sma = sum / (double)period;
   
   // Calculate mean deviation
   double mean_deviation = 0.0;
   for(int i = 0; i < period; i++)
   {
      mean_deviation += MathAbs(prices[i] - sma);
   }
   mean_deviation /= (double)period;
   
   // Avoid division by zero
   if(mean_deviation == 0.0)
      return 0.0;
   
   // Calculate CCI
   double current_price = GetCCIPrice(bar_index, high, low, close, open);
   double cci = (current_price - sma) / (0.015 * mean_deviation);
   
   return cci;
}

//+------------------------------------------------------------------+
//| Calculate selected red signal line                               |
//+------------------------------------------------------------------+
double CalculateRedSignal(const int type, const double core_value, const int bar,
                          double &ema_a[], double &ema_b[], double &ema_c[], 
                          double &ema_d[], double &double_stage1[], double &double_final[])
{
   static double alpha_a = 0, alpha_b = 0, alpha_c = 0, alpha_d = 0;
   static double alpha_d1 = 0, alpha_d2 = 0;
   static bool initialized = false;
   
   if(!initialized)
   {
      alpha_a = _alpha(InpRedEMA_A);
      alpha_b = _alpha(InpRedEMA_B);
      alpha_c = _alpha(InpRedEMA_C);
      alpha_d = _alpha(InpRedEMA_D);
      alpha_d1 = _alpha(InpDoubleEMA1);
      alpha_d2 = _alpha(InpDoubleEMA2);
      initialized = true;
   }
   
   switch(type)
   {
      case 1:  // EMA(5) of blue core
         ema_a[bar] = alpha_a * core_value + (1.0 - alpha_a) * ema_a[bar + 1];
         return ema_a[bar];
         
      case 2:  // EMA(8) of blue core
         ema_b[bar] = alpha_b * core_value + (1.0 - alpha_b) * ema_b[bar + 1];
         return ema_b[bar];
         
      case 3:  // EMA(13) of blue core
         ema_c[bar] = alpha_c * core_value + (1.0 - alpha_c) * ema_c[bar + 1];
         return ema_c[bar];
         
      case 4:  // EMA(21) of blue core
         ema_d[bar] = alpha_d * core_value + (1.0 - alpha_d) * ema_d[bar + 1];
         return ema_d[bar];
         
      case 5:  // Double smoothing
         double_stage1[bar] = alpha_d1 * core_value + (1.0 - alpha_d1) * double_stage1[bar + 1];
         double_final[bar]  = alpha_d2 * double_stage1[bar] + (1.0 - alpha_d2) * double_final[bar + 1];
         return double_final[bar];
         
      default:
         return 0.0;
   }
}

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
   // Set indicator buffers
   SetIndexBuffer(0, g_BlueCore,    INDICATOR_DATA);
   SetIndexBuffer(1, g_RedSignal,   INDICATOR_DATA);
   SetIndexBuffer(2, g_RedContour,  INDICATOR_DATA);
   SetIndexBuffer(3, g_HistPos,     INDICATOR_DATA);
   SetIndexBuffer(4, g_HistNeg,     INDICATOR_DATA);
   SetIndexBuffer(5, g_HistGreen,   INDICATOR_DATA);
   
   SetIndexBuffer(6, g_Fast,        INDICATOR_CALCULATIONS);
   SetIndexBuffer(7, g_Slow,        INDICATOR_CALCULATIONS);
   SetIndexBuffer(8, g_CCI,         INDICATOR_CALCULATIONS);
   SetIndexBuffer(9, g_Histogram,   INDICATOR_CALCULATIONS);

   // Set arrays as series
   ArraySetAsSeries(g_BlueCore,    true);
   ArraySetAsSeries(g_RedSignal,   true);
   ArraySetAsSeries(g_RedContour,  true);
   ArraySetAsSeries(g_HistPos,     true);
   ArraySetAsSeries(g_HistNeg,     true);
   ArraySetAsSeries(g_HistGreen,   true);
   ArraySetAsSeries(g_Fast,        true);
   ArraySetAsSeries(g_Slow,        true);
   ArraySetAsSeries(g_CCI,         true);
   ArraySetAsSeries(g_Histogram,   true);

   // Set empty values
   PlotIndexSetDouble(3, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(4, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(5, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   // Set indicator name
   string red_name[] = {"EMA5", "EMA8", "EMA13", "EMA21", "Double"};
   string red_label = red_name[InpRedLineType - 1];
   string cci_label = InpEnableCCI ? " + CCI(" + IntegerToString(InpCCIPeriod) + ")" : "";
   string green_label = InpEnableGreen ? " + GREEN" : "";
   
   IndicatorSetString(INDICATOR_SHORTNAME, 
                      "DPI v30 (" + IntegerToString(InpFastEMA) + "," + 
                      IntegerToString(InpSlowEMA) + ", " + red_label + ")" + cci_label + green_label);
   IndicatorSetInteger(INDICATOR_DIGITS, _Digits + 1);

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Main calculation function                                         |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   // Minimum bars check
   int min_bars = InpSlowEMA + MathMax(InpRedEMA_D, InpDoubleEMA1 + InpDoubleEMA2) + InpCCIPeriod + 10;
   if(rates_total < min_bars)
      return 0;

   ArraySetAsSeries(close, true);
   ArraySetAsSeries(high,  true);
   ArraySetAsSeries(low,   true);
   ArraySetAsSeries(open,  true);

   // Internal buffers for red signal calculation
   static double ema_a[], ema_b[], ema_c[], ema_d[], double_stage1[], double_final[];
   static bool buffers_initialized = false;
   
   if(!buffers_initialized)
   {
      ArrayResize(ema_a, rates_total);
      ArrayResize(ema_b, rates_total);
      ArrayResize(ema_c, rates_total);
      ArrayResize(ema_d, rates_total);
      ArrayResize(double_stage1, rates_total);
      ArrayResize(double_final, rates_total);
      
      ArraySetAsSeries(ema_a, true);
      ArraySetAsSeries(ema_b, true);
      ArraySetAsSeries(ema_c, true);
      ArraySetAsSeries(ema_d, true);
      ArraySetAsSeries(double_stage1, true);
      ArraySetAsSeries(double_final, true);
      
      buffers_initialized = true;
   }

   // EMA smoothing factors
   const double aFast = _alpha(InpFastEMA);
   const double aSlow = _alpha(InpSlowEMA);

   // Initialize oldest bar
   int oldest = rates_total - 1;
   g_Fast[oldest] = close[oldest];
   g_Slow[oldest] = close[oldest];
   g_BlueCore[oldest] = 0.0;
   g_RedSignal[oldest] = 0.0;
   g_RedContour[oldest] = EMPTY_VALUE;
   g_HistPos[oldest] = EMPTY_VALUE;
   g_HistNeg[oldest] = EMPTY_VALUE;
   g_HistGreen[oldest] = EMPTY_VALUE;
   g_CCI[oldest] = 0.0;
   g_Histogram[oldest] = 0.0;
   
   ema_a[oldest] = 0.0;
   ema_b[oldest] = 0.0;
   ema_c[oldest] = 0.0;
   ema_d[oldest] = 0.0;
   double_stage1[oldest] = 0.0;
   double_final[oldest] = 0.0;

   // Main calculation loop
   for(int i = rates_total - 2; i >= 0; --i)
   {
      // Calculate Fast and Slow EMAs
      g_Fast[i] = aFast * close[i] + (1.0 - aFast) * g_Fast[i + 1];
      g_Slow[i] = aSlow * close[i] + (1.0 - aSlow) * g_Slow[i + 1];
      
      // Blue MACD core (LEAD)
      g_BlueCore[i] = g_Fast[i] - g_Slow[i];
      
      // Calculate selected red signal line (FOLLOW)
      g_RedSignal[i] = CalculateRedSignal(InpRedLineType, g_BlueCore[i], i,
                                          ema_a, ema_b, ema_c, ema_d, 
                                          double_stage1, double_final);
      
      // ===================================================================
      // HISTOGRAM COLOR LOGIC WITH GREEN MOMENTUM
      // ===================================================================
      
      // Standard histogram = gap between Blue (LEAD) and Red (FOLLOW)
      double hist = g_BlueCore[i] - g_RedSignal[i];
      
      // Red contour follows the standard histogram
      g_RedContour[i] = hist;
      
      // Calculate CCI if enabled
      if(InpEnableCCI)
      {
         g_CCI[i] = CalculateCCI(InpCCIPeriod, i, high, low, close, open);
      }
      else
      {
         g_CCI[i] = 0.0;
      }
      
      // Check if GREEN condition is met (both lines on same side of zero)
      bool both_above_zero = (g_BlueCore[i] > 0.0 && g_RedSignal[i] > 0.0);
      bool both_below_zero = (g_BlueCore[i] < 0.0 && g_RedSignal[i] < 0.0);
      bool green_condition = InpEnableGreen && (both_above_zero || both_below_zero);
      
      if(green_condition)
      {
         // GREEN: Fill gap between 0-line and nearest line to zero
         // Find which line is closer to zero
         double nearest_line;
         if(both_above_zero)
         {
            // Both positive, pick the smaller value (closer to zero)
            nearest_line = MathMin(g_BlueCore[i], g_RedSignal[i]);
         }
         else // both_below_zero
         {
            // Both negative, pick the one with smaller absolute value (closer to zero)
            nearest_line = MathMax(g_BlueCore[i], g_RedSignal[i]);
         }
         
         // GREEN histogram shows the gap from 0-line to nearest line
         g_HistGreen[i] = nearest_line;
         
         // RED/YELLOW histogram still shows gap between Blue and Red
         if(hist >= 0.0)
         {
            if(InpEnableCCI && g_CCI[i] < 0.0)
            {
               g_HistPos[i] = EMPTY_VALUE;
               g_HistNeg[i] = hist;
            }
            else
            {
               g_HistPos[i] = hist;
               g_HistNeg[i] = EMPTY_VALUE;
            }
         }
         else
         {
            if(InpEnableCCI && g_CCI[i] >= 0.0)
            {
               g_HistPos[i] = hist;
               g_HistNeg[i] = EMPTY_VALUE;
            }
            else
            {
               g_HistPos[i] = EMPTY_VALUE;
               g_HistNeg[i] = hist;
            }
         }
      }
      else
      {
         // No GREEN: only RED/YELLOW histogram (gap between Blue and Red)
         g_HistGreen[i] = EMPTY_VALUE;
         
         if(hist >= 0.0)
         {
            // Above zero: default YELLOW, CCI can force RED
            if(InpEnableCCI && g_CCI[i] < 0.0)
            {
               // CCI RESET: Force RED despite being above zero
               g_HistPos[i] = EMPTY_VALUE;
               g_HistNeg[i] = hist;
            }
            else
            {
               // Normal: YELLOW
               g_HistPos[i] = hist;
               g_HistNeg[i] = EMPTY_VALUE;
            }
         }
         else
         {
            // Below zero: default RED, CCI can force YELLOW
            if(InpEnableCCI && g_CCI[i] >= 0.0)
            {
               // CCI RESET: Force YELLOW despite being below zero
               g_HistPos[i] = hist;
               g_HistNeg[i] = EMPTY_VALUE;
            }
            else
            {
               // Normal: RED
               g_HistPos[i] = EMPTY_VALUE;
               g_HistNeg[i] = hist;
            }
         }
      }
   }

   return rates_total;
}
//+------------------------------------------------------------------+
//| END OF INDICATOR                                                  |
//+------------------------------------------------------------------+
//
// USAGE NOTES - DPI v30 with GREEN MOMENTUM HISTOGRAM:
//
// 1. TWO HISTOGRAM ZONES (FINAL CORRECT VERSION):
//    MT4 DPI displays TWO separate histogram zones simultaneously:
//    
//    ZONE 1 - RED/YELLOW HISTOGRAM:
//    - Location: Between Blue (LEAD) and Red (FOLLOW) lines
//    - Value: Blue - Red (the gap between the two lines)
//    - Color logic: 
//      * hist >= 0 + CCI >= 0 → YELLOW
//      * hist >= 0 + CCI < 0 → RED (CCI reset)
//      * hist < 0 + CCI >= 0 → YELLOW (CCI reset)
//      * hist < 0 + CCI < 0 → RED
//    - Always visible
//    
//    ZONE 2 - GREEN HISTOGRAM:
//    - Location: Between 0-line and nearest line to zero
//    - Value: Whichever line (Blue or Red) is closer to zero
//    - Condition: ONLY appears when both lines on same side of zero
//    - Color: Always GREEN (LimeGreen)
//    - Disappears when lines are on opposite sides of zero
//
// 2. VISUAL UNDERSTANDING:
//    
//    BULLISH (both lines above zero):
//    ┌─────────────────────────
//    │   Blue (LEAD) = +0.0050
//    │   ║RED/YELLOW║ = 0.0020  ← Zone 1: Between Blue & Red
//    │   Red (FOLLOW) = +0.0030
//    │   ▓▓▓ GREEN ▓▓▓ = 0.0030  ← Zone 2: From 0-line to Red
//    ├─────────────────────────  ← Zero-line (0.0)
//    
//    BEARISH (both lines below zero):
//    ├─────────────────────────  ← Zero-line (0.0)
//    │   ▓▓▓ GREEN ▓▓▓ = -0.0030  ← Zone 2: From 0-line to Red
//    │   Red (FOLLOW) = -0.0030
//    │   ║RED/YELLOW║ = -0.0020  ← Zone 1: Between Red & Blue
//    │   Blue (LEAD) = -0.0050
//    └─────────────────────────
//    
//    TRANSITION (lines opposite sides):
//    │   Blue (LEAD) = +0.0020
//    │   ║RED/YELLOW║ = 0.0050  ← Only Zone 1 visible
//    ├─────────────────────────  ← Zero-line (crosses histogram)
//    │   Red (FOLLOW) = -0.0030
//    │   (NO GREEN - lines not aligned)
//
// 3. GREEN APPEARANCE/DISAPPEARANCE:
//    
//    GREEN APPEARS when:
//    - Both Blue and Red move to same side of zero
//    - Signals: Strong trend alignment, directional momentum confirmed
//    
//    GREEN DISAPPEARS when:
//    - One line crosses zero (lines now opposite sides)
//    - Signals: Trend alignment broken, potential reversal/consolidation
//    - Only RED/YELLOW histogram remains visible
//
// 4. TRADING SIGNALS WITH GREEN:
//    
//    MAXIMUM CONFIDENCE (Green present):
//    - SELL: Green below zero = both indicators bearish aligned
//    - BUY: Green above zero = both indicators bullish aligned
//    - This is the STRONGEST trend confirmation signal
//    
//    TREND TRANSITION (Green disappears):
//    - One line crossed zero = trend changing
//    - Consider: Exit positions, tighten stops, wait for re-alignment
//    - Wait for green to reappear before new entries
//    
//    WEAK SIGNALS (No green):
//    - Lines on opposite sides = conflicting signals
//    - Avoid new entries until green appears
//
// 5. HISTOGRAM COLOR MEANINGS:
//    
//    When GREEN is present (both lines same side):
//    - GREEN zone: Shows distance from 0-line to trend
//    - RED/YELLOW zone: Shows divergence between Lead and Follow
//    - Strong trend = Both zones visible and expanding
//    
//    When GREEN is absent (lines opposite sides):
//    - Only RED/YELLOW zone visible
//    - Trend in transition or reversal phase
//    - Wait for clarity before trading
//
// 6. TOGGLING GREEN:
//    Set InpEnableGreen = false to disable green histogram
//    This reverts to v29 behavior (only RED/YELLOW with CCI resets)
//    Useful for A/B testing strategies with/without green filter
//
// 7. EA INTEGRATION WITH GREEN:
//    
//    Simple and powerful filtering strategy:
//    - Entry condition: GREEN must be present
//      * BUY: Green above zero
//      * SELL: Green below zero
//    - Exit condition: GREEN disappears
//      * Close all positions when green vanishes
//      * Or tighten stops significantly
//    - Re-entry: Wait for green to reappear
//    
//    Advanced filtering:
//    - Check both GREEN and RED/YELLOW zones
//    - Best entries: Green expanding + Yellow histogram
//    - Warning signs: Green present but Red histogram (CCI reset)
//
// 8. COMBINED WITH CCI:
//    
//    Even when GREEN is present, CCI affects RED/YELLOW zone:
//    - GREEN shows trend alignment (0-line to nearest line)
//    - RED/YELLOW shows momentum quality (Blue vs Red)
//    - CCI resets apply to RED/YELLOW zone only
//    - Best setup: GREEN + YELLOW = Maximum strength
//    - Warning: GREEN + RED = Strong trend but CCI divergence
//
// 9. COMPARISON WITH MT4 DPI:
//    v30 should now exactly replicate MT4 DPI behavior:
//    - Two histogram zones displayed simultaneously
//    - GREEN appears/disappears based on line alignment
//    - Same visual appearance and trading signals
//    - Both zones provide complementary information
//
//+------------------------------------------------------------------+
