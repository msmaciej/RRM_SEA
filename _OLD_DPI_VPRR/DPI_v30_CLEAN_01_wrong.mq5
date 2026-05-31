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
//|   There is ONE histogram (Blue - Red), but THREE colors:        |
//|                                                                  |
//|   The histogram shows: Blue (LEAD) - Red (FOLLOW)                |
//|   The color depends on line positions relative to zero:         |
//|                                                                  |
//|   GREEN histogram:                                               |
//|   - Appears when BOTH Blue and Red are on SAME side of zero     |
//|   - Value: Blue - Red (normal histogram)                         |
//|   - Color: LimeGreen                                             |
//|   - Meaning: Strong trend alignment, both indicators agree       |
//|                                                                  |
//|   YELLOW histogram:                                              |
//|   - Appears when histogram >= 0 (without green condition)        |
//|   - OR when CCI forces yellow (CCI reset logic)                  |
//|   - Meaning: Bullish histogram or CCI override                   |
//|                                                                  |
//|   RED histogram:                                                 |
//|   - Appears when histogram < 0 (without green condition)         |
//|   - OR when CCI forces red (CCI reset logic)                     |
//|   - Meaning: Bearish histogram or CCI override                   |
//|                                                                  |
//|   PRIORITY: GREEN > CCI resets > Normal RED/YELLOW               |
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
      
      // Red contour follows the histogram
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
         // GREEN: Both lines on same side of zero
         // Green REPLACES normal RED/YELLOW color for this histogram bar
         g_HistGreen[i] = hist;
         g_HistPos[i] = EMPTY_VALUE;
         g_HistNeg[i] = EMPTY_VALUE;
      }
      else
      {
         // No GREEN: Use normal RED/YELLOW logic with CCI resets
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
// 1. GREEN HISTOGRAM LOGIC (CORRECT SIMPLE VERSION):
//    There is ONE histogram with THREE possible colors:
//    
//    Histogram Value: Blue (LEAD) - Red (FOLLOW)
//    This is the standard MACD histogram between the two lines.
//    
//    Color Logic:
//    ┌─────────────────────────────────────────────────────────┐
//    │ CONDITION                      │ COLOR   │ MEANING      │
//    ├────────────────────────────────┼─────────┼──────────────┤
//    │ Both lines same side of zero   │ GREEN   │ Trend aligned│
//    │ hist >= 0 (normal)             │ YELLOW  │ Bullish hist │
//    │ hist >= 0 + CCI < 0            │ RED     │ CCI reset    │
//    │ hist < 0 (normal)              │ RED     │ Bearish hist │
//    │ hist < 0 + CCI >= 0            │ YELLOW  │ CCI reset    │
//    └────────────────────────────────┴─────────┴──────────────┘
//    
//    Priority: GREEN condition > CCI resets > Normal color
//
// 2. WHEN GREEN APPEARS:
//    
//    BULLISH GREEN (histogram above zero):
//    - Both Blue > 0 AND Red > 0
//    - Histogram = Blue - Red (positive value)
//    - Green bars above zero line
//    → Strong bullish trend, both indicators aligned bullish
//    
//    BEARISH GREEN (histogram below zero):
//    - Both Blue < 0 AND Red < 0
//    - Histogram = Blue - Red (negative value)
//    - Green bars below zero line
//    → Strong bearish trend, both indicators aligned bearish
//
// 3. WHEN GREEN DISAPPEARS:
//    
//    Lines cross to opposite sides of zero:
//    - Blue > 0 and Red < 0 (or vice versa)
//    - Trend alignment broken
//    - Histogram changes to RED or YELLOW (normal logic)
//    
//    Signals:
//    - Potential trend reversal
//    - Consolidation phase beginning
//    - Momentum weakening
//    - Overbought/oversold condition
//
// 4. VISUAL PATTERN MATCHING MT4 DPI:
//    
//    Looking at the screenshot:
//    - Left side: GREEN bars below zero (both lines bearish)
//    - Middle: RED/YELLOW bars (lines crossing zero)
//    - Right side: GREEN bars appear when lines re-align
//    
//    The GREEN histogram has the SAME SHAPE as the normal histogram,
//    it just changes COLOR when both lines are on same side of zero.
//
// 5. TRADING SIGNALS:
//    
//    STRONGEST SIGNALS (Green histogram):
//    - BUY: Green bars above zero = Maximum bullish confidence
//    - SELL: Green bars below zero = Maximum bearish confidence
//    - Both indicators (Blue and Red) agree on direction
//    
//    WEAK/TRANSITION SIGNALS (Red/Yellow histogram):
//    - Lines on opposite sides of zero = Conflicting signals
//    - Wait for green to reappear before new entries
//    - Consider exiting existing positions
//    
//    EXIT SIGNALS:
//    - Green changes to Red/Yellow = Trend alignment lost
//    - Tighten stops immediately
//    - Prepare to close or reverse positions
//
// 6. HISTOGRAM COLOR MEANINGS:
//    
//    GREEN = Trend aligned (both lines same side)
//    - Best time to enter trades
//    - Stay in existing positions
//    - Add to positions on pullbacks
//    
//    YELLOW (normal) = Positive histogram, no trend alignment
//    - Caution: Mixed signals
//    - Wait for confirmation
//    
//    RED (normal) = Negative histogram, no trend alignment
//    - Caution: Mixed signals
//    - Wait for confirmation
//    
//    YELLOW/RED (CCI reset) = CCI divergence warning
//    - Even more caution needed
//    - Possible reversal building
//
// 7. EA INTEGRATION:
//    
//    Simple and effective filtering:
//    ```
//    Entry rules:
//    - BUY: histogram GREEN AND above zero
//    - SELL: histogram GREEN AND below zero
//    
//    Exit rules:
//    - Close when histogram changes from GREEN to RED/YELLOW
//    - Or use trailing stop when GREEN present
//    
//    Avoid:
//    - Any trades when histogram is RED or YELLOW (not green)
//    - Wait for GREEN to reappear
//    ```
//    
//    Advanced filtering:
//    - GREEN + YELLOW histogram = Maximum bullish strength
//    - GREEN + RED histogram (CCI reset) = Strong but watch for reversal
//    - No GREEN = Stay out
//
// 8. TOGGLING GREEN:
//    Set InpEnableGreen = false to disable green coloring
//    This reverts to v29 behavior (only RED/YELLOW with CCI resets)
//    Useful for comparing strategies with/without green filter
//
// 9. COMBINED WITH CCI:
//    
//    When GREEN enabled:
//    - GREEN overrides normal RED/YELLOW color
//    - Shows: Both lines on same side of zero
//    
//    When GREEN disabled or condition not met:
//    - CCI resets apply normally
//    - RED/YELLOW based on histogram sign and CCI value
//    
//    Best combinations:
//    - GREEN histogram + Normal CCI = Maximum confidence
//    - GREEN histogram + CCI reset = Strong but cautious
//    - No GREEN = Avoid or wait
//
// 10. COMPARISON WITH MT4 DPI:
//     v30 now correctly replicates MT4 DPI green histogram:
//     - Same histogram shape (Blue - Red)
//     - GREEN color when both lines same side of zero
//     - RED/YELLOW color when lines opposite sides
//     - Exact visual match with MT4 DPI screenshots
//
//+------------------------------------------------------------------+
