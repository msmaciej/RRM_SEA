//  SAVE AS UTF-16 LE WITH BOM
//+------------------------------------------------------------------+
//|                         DPI_v30_FINAL.mq5                        |
//|   Purpose: MT4 DPI complete replica with GREEN histogram         |
//|   Version: 30 FINAL - Correct ribbon + green implementation     |
//|                                                                  |
//|   VISUAL ELEMENTS:                                               |
//|   1. Blue Line (LEAD)    = MACD Core = EMA(8) - EMA(13)         |
//|   2. Red Line (FOLLOW)   = EMA of Blue Line (signal)            |
//|   3. RED/YELLOW Ribbon   = Filled area BETWEEN Blue and Red     |
//|   4. GREEN Histogram     = From 0-line to nearest line          |
//|                                                                  |
//|   RED/YELLOW RIBBON:                                             |
//|   - Fills the space between Blue (LEAD) and Red (FOLLOW)        |
//|   - YELLOW when hist >= 0 (normal) or CCI bullish reset         |
//|   - RED when hist < 0 (normal) or CCI bearish reset             |
//|   - Always visible, shows divergence between lines              |
//|                                                                  |
//|   GREEN HISTOGRAM:                                               |
//|   - Appears when both Blue and Red on SAME side of zero         |
//|   - Value: whichever line is CLOSER to zero                     |
//|   - Fills from 0-line up/down to nearest line                   |
//|   - Shows trend alignment strength                              |
//|                                                                  |
//+------------------------------------------------------------------+
#property strict
#property version   "30.00"
#property indicator_separate_window
#property indicator_buffers 12
#property indicator_plots   7

#property indicator_level1          0.0
#property indicator_levelcolor  clrSilver
#property indicator_levelstyle  STYLE_DOT
#property indicator_levelwidth  1

// Plot 0: Blue MACD core (LEAD line)
#property indicator_label1    "Blue_LEAD"
#property indicator_type1     DRAW_LINE
#property indicator_color1    clrDodgerBlue
#property indicator_style1    STYLE_SOLID
#property indicator_width1    2

// Plot 1: Red signal line (FOLLOW line)
#property indicator_label2    "Red_FOLLOW"
#property indicator_type2     DRAW_LINE
#property indicator_color2    clrRed
#property indicator_style2    STYLE_SOLID
#property indicator_width2    2

// Plot 2: YELLOW ribbon fill (between Blue and Red)
#property indicator_label3    "Ribbon_Yellow"
#property indicator_type3     DRAW_FILLING
#property indicator_color3    clrYellow
#property indicator_style3    STYLE_SOLID

// Plot 3: RED ribbon fill (between Blue and Red)
#property indicator_label4    "Ribbon_Red"
#property indicator_type4     DRAW_FILLING
#property indicator_color4    clrRed
#property indicator_style4    STYLE_SOLID

// Plot 4: GREEN histogram (from 0-line to nearest line)
#property indicator_label5    "Green_Momentum"
#property indicator_type5     DRAW_HISTOGRAM
#property indicator_color5    clrLimeGreen
#property indicator_style5    STYLE_SOLID
#property indicator_width5    3

// Plot 5: Zero line for ribbon fill base (Yellow)
#property indicator_label6    "Zero_Yellow"
#property indicator_type6     DRAW_LINE
#property indicator_color6    clrNONE
#property indicator_style6    STYLE_SOLID
#property indicator_width6    1

// Plot 6: Zero line for ribbon fill base (Red)
#property indicator_label7    "Zero_Red"
#property indicator_type7     DRAW_LINE
#property indicator_color7    clrNONE
#property indicator_style7    STYLE_SOLID
#property indicator_width7    1

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
double g_BlueCore[];          // Blue MACD core line
double g_RedSignal[];         // Red signal line
double g_RibbonYellow1[];     // Yellow ribbon - Blue side
double g_RibbonYellow2[];     // Yellow ribbon - Red side
double g_RibbonRed1[];        // Red ribbon - Blue side
double g_RibbonRed2[];        // Red ribbon - Red side
double g_HistGreen[];         // GREEN histogram

// Internal calculation buffers
double g_Fast[];              // Fast EMA
double g_Slow[];              // Slow EMA
double g_CCI[];               // CCI values
double g_Histogram[];         // Histogram value (Blue - Red)
double g_ZeroLineYellow[];    // Zero reference for yellow fill
double g_ZeroLineRed[];       // Zero reference for red fill

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
   
   double prices[];
   ArrayResize(prices, period);
   
   double sum = 0.0;
   for(int i = 0; i < period; i++)
   {
      int idx = bar_index + i;
      prices[i] = GetCCIPrice(idx, high, low, close, open);
      sum += prices[i];
   }
   
   double sma = sum / (double)period;
   
   double mean_deviation = 0.0;
   for(int i = 0; i < period; i++)
   {
      mean_deviation += MathAbs(prices[i] - sma);
   }
   mean_deviation /= (double)period;
   
   if(mean_deviation == 0.0)
      return 0.0;
   
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
      case 1:
         ema_a[bar] = alpha_a * core_value + (1.0 - alpha_a) * ema_a[bar + 1];
         return ema_a[bar];
         
      case 2:
         ema_b[bar] = alpha_b * core_value + (1.0 - alpha_b) * ema_b[bar + 1];
         return ema_b[bar];
         
      case 3:
         ema_c[bar] = alpha_c * core_value + (1.0 - alpha_c) * ema_c[bar + 1];
         return ema_c[bar];
         
      case 4:
         ema_d[bar] = alpha_d * core_value + (1.0 - alpha_d) * ema_d[bar + 1];
         return ema_d[bar];
         
      case 5:
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
   SetIndexBuffer(0, g_BlueCore,        INDICATOR_DATA);
   SetIndexBuffer(1, g_RedSignal,       INDICATOR_DATA);
   SetIndexBuffer(2, g_RibbonYellow1,   INDICATOR_DATA);
   SetIndexBuffer(3, g_RibbonYellow2,   INDICATOR_DATA);
   SetIndexBuffer(4, g_RibbonRed1,      INDICATOR_DATA);
   SetIndexBuffer(5, g_RibbonRed2,      INDICATOR_DATA);
   SetIndexBuffer(6, g_HistGreen,       INDICATOR_DATA);
   
   SetIndexBuffer(7,  g_Fast,           INDICATOR_CALCULATIONS);
   SetIndexBuffer(8,  g_Slow,           INDICATOR_CALCULATIONS);
   SetIndexBuffer(9,  g_CCI,            INDICATOR_CALCULATIONS);
   SetIndexBuffer(10, g_Histogram,      INDICATOR_CALCULATIONS);
   SetIndexBuffer(11, g_ZeroLineYellow, INDICATOR_CALCULATIONS);
   SetIndexBuffer(12, g_ZeroLineRed,    INDICATOR_CALCULATIONS);

   // Set arrays as series
   ArraySetAsSeries(g_BlueCore,        true);
   ArraySetAsSeries(g_RedSignal,       true);
   ArraySetAsSeries(g_RibbonYellow1,   true);
   ArraySetAsSeries(g_RibbonYellow2,   true);
   ArraySetAsSeries(g_RibbonRed1,      true);
   ArraySetAsSeries(g_RibbonRed2,      true);
   ArraySetAsSeries(g_HistGreen,       true);
   ArraySetAsSeries(g_Fast,            true);
   ArraySetAsSeries(g_Slow,            true);
   ArraySetAsSeries(g_CCI,             true);
   ArraySetAsSeries(g_Histogram,       true);
   ArraySetAsSeries(g_ZeroLineYellow,  true);
   ArraySetAsSeries(g_ZeroLineRed,     true);

   // Set empty values
   PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(3, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(4, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(5, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(6, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   // Set indicator name
   string red_name[] = {"EMA5", "EMA8", "EMA13", "EMA21", "Double"};
   string red_label = red_name[InpRedLineType - 1];
   string cci_label = InpEnableCCI ? " + CCI(" + IntegerToString(InpCCIPeriod) + ")" : "";
   string green_label = InpEnableGreen ? " + GREEN" : "";
   
   IndicatorSetString(INDICATOR_SHORTNAME, 
                      "DPI v30 FINAL (" + IntegerToString(InpFastEMA) + "," + 
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
   int min_bars = InpSlowEMA + MathMax(InpRedEMA_D, InpDoubleEMA1 + InpDoubleEMA2) + InpCCIPeriod + 10;
   if(rates_total < min_bars)
      return 0;

   ArraySetAsSeries(close, true);
   ArraySetAsSeries(high,  true);
   ArraySetAsSeries(low,   true);
   ArraySetAsSeries(open,  true);

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

   const double aFast = _alpha(InpFastEMA);
   const double aSlow = _alpha(InpSlowEMA);

   int oldest = rates_total - 1;
   g_Fast[oldest] = close[oldest];
   g_Slow[oldest] = close[oldest];
   g_BlueCore[oldest] = 0.0;
   g_RedSignal[oldest] = 0.0;
   g_RibbonYellow1[oldest] = EMPTY_VALUE;
   g_RibbonYellow2[oldest] = EMPTY_VALUE;
   g_RibbonRed1[oldest] = EMPTY_VALUE;
   g_RibbonRed2[oldest] = EMPTY_VALUE;
   g_HistGreen[oldest] = EMPTY_VALUE;
   g_CCI[oldest] = 0.0;
   g_Histogram[oldest] = 0.0;
   
   ema_a[oldest] = 0.0;
   ema_b[oldest] = 0.0;
   ema_c[oldest] = 0.0;
   ema_d[oldest] = 0.0;
   double_stage1[oldest] = 0.0;
   double_final[oldest] = 0.0;

   for(int i = rates_total - 2; i >= 0; --i)
   {
      g_Fast[i] = aFast * close[i] + (1.0 - aFast) * g_Fast[i + 1];
      g_Slow[i] = aSlow * close[i] + (1.0 - aSlow) * g_Slow[i + 1];
      
      g_BlueCore[i] = g_Fast[i] - g_Slow[i];
      
      g_RedSignal[i] = CalculateRedSignal(InpRedLineType, g_BlueCore[i], i,
                                          ema_a, ema_b, ema_c, ema_d, 
                                          double_stage1, double_final);
      
      double hist = g_BlueCore[i] - g_RedSignal[i];
      g_Histogram[i] = hist;
      
      if(InpEnableCCI)
      {
         g_CCI[i] = CalculateCCI(InpCCIPeriod, i, high, low, close, open);
      }
      else
      {
         g_CCI[i] = 0.0;
      }
      
      // ===================================================================
      // HISTOGRAM LOGIC - TWO ZONES EXTENDING FROM 0-LINE TO BLUE LINE
      // ===================================================================
      
      bool both_above_zero = (g_BlueCore[i] > 0.0 && g_RedSignal[i] > 0.0);
      bool both_below_zero = (g_BlueCore[i] < 0.0 && g_RedSignal[i] < 0.0);
      bool green_condition = InpEnableGreen && (both_above_zero || both_below_zero);
      
      if(green_condition)
      {
         // BOTH LINES ON SAME SIDE OF ZERO
         // Histogram extends from 0-line all the way to Blue line in TWO zones:
         // Zone 1 (GREEN): From 0-line to nearest line
         // Zone 2 (RED/YELLOW): From nearest line to Blue line
         
         double nearest_to_zero, furthest_from_zero;
         
         if(both_above_zero)
         {
            // Both positive
            nearest_to_zero = MathMin(g_BlueCore[i], g_RedSignal[i]);
            furthest_from_zero = MathMax(g_BlueCore[i], g_RedSignal[i]);
         }
         else // both_below_zero
         {
            // Both negative
            nearest_to_zero = MathMax(g_BlueCore[i], g_RedSignal[i]);  // Less negative
            furthest_from_zero = MathMin(g_BlueCore[i], g_RedSignal[i]);  // More negative
         }
         
         // GREEN histogram: From 0-line to nearest line
         g_HistGreen[i] = nearest_to_zero;
         
         // RED/YELLOW histogram: From nearest line to Blue line (furthest)
         // This is the gap between nearest and furthest
         double ribbon_height = furthest_from_zero - nearest_to_zero;
         
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
         
         if(use_yellow)
         {
            // YELLOW ribbon on top of GREEN
            g_RibbonYellow1[i] = furthest_from_zero;
            g_RibbonYellow2[i] = nearest_to_zero;
            g_RibbonRed1[i] = EMPTY_VALUE;
            g_RibbonRed2[i] = EMPTY_VALUE;
         }
         else
         {
            // RED ribbon on top of GREEN
            g_RibbonRed1[i] = furthest_from_zero;
            g_RibbonRed2[i] = nearest_to_zero;
            g_RibbonYellow1[i] = EMPTY_VALUE;
            g_RibbonYellow2[i] = EMPTY_VALUE;
         }
      }
      else
      {
         // LINES ON OPPOSITE SIDES OF ZERO
         // No GREEN, only RED/YELLOW histogram from 0-line
         g_HistGreen[i] = EMPTY_VALUE;
         
         // Determine color
         bool use_yellow;
         if(hist >= 0.0)
         {
            use_yellow = !(InpEnableCCI && g_CCI[i] < 0.0);
         }
         else
         {
            use_yellow = (InpEnableCCI && g_CCI[i] >= 0.0);
         }
         
         if(use_yellow)
         {
            // YELLOW ribbon from 0-line to Blue
            g_RibbonYellow1[i] = g_BlueCore[i];
            g_RibbonYellow2[i] = 0.0;
            g_RibbonRed1[i] = EMPTY_VALUE;
            g_RibbonRed2[i] = EMPTY_VALUE;
         }
         else
         {
            // RED ribbon from 0-line to Blue
            g_RibbonRed1[i] = g_BlueCore[i];
            g_RibbonRed2[i] = 0.0;
            g_RibbonYellow1[i] = EMPTY_VALUE;
            g_RibbonYellow2[i] = EMPTY_VALUE;
         }
      }
   }

   return rates_total;
}
//+------------------------------------------------------------------+
