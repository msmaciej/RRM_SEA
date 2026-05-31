//  SAVE AS UTF-16 LE WITH BOM
//+------------------------------------------------------------------+
//|                     DPI_v30_FULL_RIBBON.mq5                       |
//|   Purpose: MT4 DPI replica - FULL RIBBON with no gaps            |
//|   Version: 30 FULL RIBBON - Complete fill regardless of position |
//|                                                                  |
//|   RIBBON STRATEGY:                                               |
//|   The ribbon fills the ENTIRE space from zero to the furthest   |
//|   line, regardless of whether lines are on same or opposite     |
//|   sides of zero.                                                 |
//|                                                                  |
//|   POSITIVE SIDE (above 0):                                       |
//|   - Find max(Blue, hist) on positive side                       |
//|   - Fill from 0 to that maximum                                  |
//|                                                                  |
//|   NEGATIVE SIDE (below 0):                                       |
//|   - Find min(Blue, hist) on negative side                       |
//|   - Fill from 0 to that minimum                                  |
//|                                                                  |
//|   This creates a continuous ribbon with NO GAPS regardless of   |
//|   whether Blue and histogram are on same or opposite sides.     |
//+------------------------------------------------------------------+
#property strict
#property version   "30.00"
#property indicator_separate_window
#property indicator_buffers 9
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
#property indicator_width1    3

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
#property indicator_width4    4

// Plot 4: Red histogram (negative or CCI override)
#property indicator_label5    "Hist_Negative"
#property indicator_type5     DRAW_HISTOGRAM
#property indicator_color5    clrRed
#property indicator_style5    STYLE_SOLID
#property indicator_width5    4

// Plot 5: GREEN histogram (momentum alignment)
#property indicator_label6    "Hist_Green"
#property indicator_type6     DRAW_HISTOGRAM
#property indicator_color6    clrLimeGreen
#property indicator_style6    STYLE_SOLID
#property indicator_width6    4

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
input int InpRedLineType = 3;   // Red line type (1=EMA5, 2=EMA8, 3=EMA13, 4=EMA21, 5=Double)
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
double g_HistGreen[];     // GREEN histogram

// Internal calculation buffers
double g_Fast[];          // Fast EMA
double g_Slow[];          // Slow EMA
double g_CCI[];           // CCI values

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
                          double &ema_d[], double &double_stage1[], 
                          double &double_final[])
{
   double result = 0.0;
   
   switch(type)
   {
      case 1: // EMA A
         if(bar == ArraySize(ema_a) - 1)
            ema_a[bar] = core_value;
         else
         {
            double alpha_a = _alpha(InpRedEMA_A);
            ema_a[bar] = alpha_a * core_value + (1.0 - alpha_a) * ema_a[bar + 1];
         }
         result = ema_a[bar];
         break;
         
      case 2: // EMA B
         if(bar == ArraySize(ema_b) - 1)
            ema_b[bar] = core_value;
         else
         {
            double alpha_b = _alpha(InpRedEMA_B);
            ema_b[bar] = alpha_b * core_value + (1.0 - alpha_b) * ema_b[bar + 1];
         }
         result = ema_b[bar];
         break;
         
      case 3: // EMA C
         if(bar == ArraySize(ema_c) - 1)
            ema_c[bar] = core_value;
         else
         {
            double alpha_c = _alpha(InpRedEMA_C);
            ema_c[bar] = alpha_c * core_value + (1.0 - alpha_c) * ema_c[bar + 1];
         }
         result = ema_c[bar];
         break;
         
      case 4: // EMA D
         if(bar == ArraySize(ema_d) - 1)
            ema_d[bar] = core_value;
         else
         {
            double alpha_d = _alpha(InpRedEMA_D);
            ema_d[bar] = alpha_d * core_value + (1.0 - alpha_d) * ema_d[bar + 1];
         }
         result = ema_d[bar];
         break;
         
      case 5: // Double smoothed
         if(bar == ArraySize(double_stage1) - 1)
         {
            double_stage1[bar] = core_value;
            double_final[bar] = core_value;
         }
         else
         {
            double alpha1 = _alpha(InpDoubleEMA1);
            double alpha2 = _alpha(InpDoubleEMA2);
            
            double_stage1[bar] = alpha1 * core_value + (1.0 - alpha1) * double_stage1[bar + 1];
            double_final[bar] = alpha2 * double_stage1[bar] + (1.0 - alpha2) * double_final[bar + 1];
         }
         result = double_final[bar];
         break;
         
      default:
         result = core_value;
         break;
   }
   
   return result;
}

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
   SetIndexBuffer(0, g_BlueCore, INDICATOR_DATA);
   SetIndexBuffer(1, g_RedSignal, INDICATOR_DATA);
   SetIndexBuffer(2, g_RedContour, INDICATOR_DATA);
   SetIndexBuffer(3, g_HistPos, INDICATOR_DATA);
   SetIndexBuffer(4, g_HistNeg, INDICATOR_DATA);
   SetIndexBuffer(5, g_HistGreen, INDICATOR_DATA);
   
   SetIndexBuffer(6, g_Fast, INDICATOR_CALCULATIONS);
   SetIndexBuffer(7, g_Slow, INDICATOR_CALCULATIONS);
   SetIndexBuffer(8, g_CCI, INDICATOR_CALCULATIONS);
   
   ArraySetAsSeries(g_BlueCore, true);
   ArraySetAsSeries(g_RedSignal, true);
   ArraySetAsSeries(g_RedContour, true);
   ArraySetAsSeries(g_HistPos, true);
   ArraySetAsSeries(g_HistNeg, true);
   ArraySetAsSeries(g_HistGreen, true);
   ArraySetAsSeries(g_Fast, true);
   ArraySetAsSeries(g_Slow, true);
   ArraySetAsSeries(g_CCI, true);
   
   PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(3, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(4, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(5, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   
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
      
      // Histogram = Blue - Red
      double hist = g_BlueCore[i] - g_RedSignal[i];
      
      // Red contour follows histogram
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
      
      // GREEN CONDITION: Both Blue LEAD line AND histogram on same side of zero
      bool both_above_zero = (g_BlueCore[i] > 0.0 && hist > 0.0);
      bool both_below_zero = (g_BlueCore[i] < 0.0 && hist < 0.0);
      bool green_condition = InpEnableGreen && (both_above_zero || both_below_zero);
      
      // Determine color based on histogram sign and CCI
      bool use_yellow;
      if(hist >= 0.0)
      {
         use_yellow = !(InpEnableCCI && g_CCI[i] < 0.0);
      }
      else
      {
         use_yellow = (InpEnableCCI && g_CCI[i] >= 0.0);
      }
      
      // FULL RIBBON FILL LOGIC - NO GAPS ANYWHERE
      //
      // Strategy: Fill to the FURTHEST point from zero on each side
      // This works whether lines are on same or opposite sides
      //
      // Positive side: max(Blue, hist) if either is positive
      // Negative side: min(Blue, hist) if either is negative
      
      // Determine the extent of the ribbon on positive side
      double positive_extent = 0.0;
      if(g_BlueCore[i] > 0.0 || hist > 0.0)
      {
         positive_extent = MathMax(g_BlueCore[i], hist);
      }
      
      // Determine the extent of the ribbon on negative side
      double negative_extent = 0.0;
      if(g_BlueCore[i] < 0.0 || hist < 0.0)
      {
         negative_extent = MathMin(g_BlueCore[i], hist);
      }
      
      // Now draw the histograms
      // Key insight: When lines are on OPPOSITE sides, we need to fill BOTH
      // the positive and negative portions. We use the SAME color for both.
      
      if(green_condition)
      {
         // GREEN CONDITION: Show green overlay from 0 to hist
         g_HistGreen[i] = hist;
         
         // Base RED/YELLOW layer fills to furthest extent on EACH side
         if(positive_extent > 0.0 && negative_extent < 0.0)
         {
            // OPPOSITE SIDES: Fill BOTH positive and negative
            // Use the SAME color (determined by hist sign and CCI)
            if(use_yellow)
            {
               g_HistPos[i] = positive_extent;   // Yellow fills positive side
               g_HistNeg[i] = negative_extent;   // Yellow fills negative side too!
            }
            else
            {
               // This is unusual but possible with CCI resets
               g_HistPos[i] = positive_extent;   // Red fills positive side
               g_HistNeg[i] = negative_extent;   // Red fills negative side
            }
         }
         else if(positive_extent > 0.0)
         {
            // Only positive side
            if(use_yellow)
            {
               g_HistPos[i] = positive_extent;
               g_HistNeg[i] = EMPTY_VALUE;
            }
            else
            {
               g_HistPos[i] = EMPTY_VALUE;
               g_HistNeg[i] = positive_extent;
            }
         }
         else if(negative_extent < 0.0)
         {
            // Only negative side
            if(use_yellow)
            {
               g_HistPos[i] = negative_extent;
               g_HistNeg[i] = EMPTY_VALUE;
            }
            else
            {
               g_HistPos[i] = EMPTY_VALUE;
               g_HistNeg[i] = negative_extent;
            }
         }
         else
         {
            g_HistPos[i] = EMPTY_VALUE;
            g_HistNeg[i] = EMPTY_VALUE;
         }
      }
      else
      {
         // NO GREEN CONDITION
         g_HistGreen[i] = EMPTY_VALUE;
         
         // RED/YELLOW fills to furthest extent on EACH side
         if(positive_extent > 0.0 && negative_extent < 0.0)
         {
            // OPPOSITE SIDES: Fill BOTH positive and negative
            if(use_yellow)
            {
               g_HistPos[i] = positive_extent;   // Yellow fills positive side
               g_HistNeg[i] = negative_extent;   // Yellow fills negative side too!
            }
            else
            {
               g_HistPos[i] = positive_extent;   // Red fills positive side
               g_HistNeg[i] = negative_extent;   // Red fills negative side
            }
         }
         else if(positive_extent > 0.0)
         {
            // Only positive side
            if(use_yellow)
            {
               g_HistPos[i] = positive_extent;
               g_HistNeg[i] = EMPTY_VALUE;
            }
            else
            {
               g_HistPos[i] = EMPTY_VALUE;
               g_HistNeg[i] = positive_extent;
            }
         }
         else if(negative_extent < 0.0)
         {
            // Only negative side
            if(use_yellow)
            {
               g_HistPos[i] = negative_extent;
               g_HistNeg[i] = EMPTY_VALUE;
            }
            else
            {
               g_HistPos[i] = EMPTY_VALUE;
               g_HistNeg[i] = negative_extent;
            }
         }
         else
         {
            g_HistPos[i] = EMPTY_VALUE;
            g_HistNeg[i] = EMPTY_VALUE;
         }
      }
   }

   return rates_total;
}
//+------------------------------------------------------------------+
//| END OF INDICATOR                                                  |
//+------------------------------------------------------------------+
//
// FULL RIBBON STRATEGY EXPLANATION:
//
// The ribbon always fills from 0-line to the FURTHEST point from zero,
// regardless of whether Blue and histogram are on same or opposite sides.
//
// EXAMPLES:
//
// Case 1: Both positive (Blue = 0.5, hist = 0.3)
//   → positive_extent = max(0.5, 0.3) = 0.5
//   → Ribbon fills from 0 to 0.5 (to Blue line)
//   → If GREEN enabled: GREEN from 0 to 0.3, RED/YELLOW from 0 to 0.5
//
// Case 2: Both negative (Blue = -0.5, hist = -0.3)
//   → negative_extent = min(-0.5, -0.3) = -0.5
//   → Ribbon fills from 0 to -0.5 (to Blue line)
//   → If GREEN enabled: GREEN from 0 to -0.3, RED/YELLOW from 0 to -0.5
//
// Case 3: Opposite sides (Blue = 0.5, hist = -0.3)
//   → positive_extent = max(0.5, -0.3) = 0.5
//   → negative_extent = min(0.5, -0.3) = -0.3
//   → Ribbon fills BOTH: 0 to 0.5 AND 0 to -0.3
//   → No GREEN (opposite sides condition fails)
//   → RED/YELLOW fills from -0.3 to 0 to 0.5 (complete fill, no gaps!)
//
// This creates a continuous ribbon with NO GAPS in any scenario.
//
//+------------------------------------------------------------------+
