//  SAVE AS UTF-16 LE WITH BOM
//+------------------------------------------------------------------+
//| DPI_mc_main.mq5                                                   |
//| Renamed from: DPI_v31_CLEAN_22_OK_FINAL_WORKING.mq5  (logic unchanged*)|
//|                                                                   |
//| Naming convention:                                                |
//|   mc = MACD + CCI core   (Blue=EMA(Fast)-EMA(Slow), Red=EMA(Blue))|
//|   tm = TSI + MACD core   (William Blau Ergodic / TSI oscillator)  |
//|   simple = no GREEN momentum overlay                              |
//|   main   = with GREEN momentum overlay (toggleable)               |
//|                                                                   |
//| Vote rule (used by EA): RIBBON color drives DPI vote.             |
//|   Red ribbon  -> DPI=1 for Bias=Short                             |
//|   Yellow ribbon -> DPI=1 for Bias=Long                            |
//|   GREEN is visualization only (momentum strength), not a vote.    |
//|                                                                   |
//| (*) Colors: 5 input color parameters (Inputs tab) drive all plot       |
//|     colors — works reliably on macOS/Wine and Windows. The Colors tab  |
//|     still shows plot rows but runtime overrides reflect Inputs values  |
//|     on every load. To change a color: edit the corresponding input.    |
//|                                                                        |
//|     When InpEnableGreen=false, GREEN plot is painted with the chart    |
//|     background color so bars are invisible BUT still mask yellow/red   |
//|     below them, preserving the ribbon-only look (matches MT4 ref).     |
//|     OnChartEvent re-applies the background color if the user changes   |
//|     the chart theme while GREEN is disabled.                           |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//|                      DPI_v31_FINAL_WORKING.mq5                    |
//|   Purpose: Complete MT4 DPI replica - ALL WORKING                |
//|   Version: 31.25 - Plot numbering fixed                          |
//|                                                                  |
//|   FIX: Corrected plot count - needs 8 plots (0-7) for 8 buffers |
//+------------------------------------------------------------------+
#property strict
#property version   "31.25"
#property indicator_separate_window
#property indicator_buffers 11
#property indicator_plots   8

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

// Plot 2: Red contour line
#property indicator_label3    "Red_Contour"
#property indicator_type3     DRAW_LINE
#property indicator_color3    clrRed
#property indicator_style3    STYLE_SOLID
#property indicator_width3    2

// Plot 3: Red histogram POSITIVE side
#property indicator_label4    "Hist_Red_Pos"
#property indicator_type4     DRAW_HISTOGRAM
#property indicator_color4    clrRed
#property indicator_style4    STYLE_SOLID
#property indicator_width4    4

// Plot 4: Red histogram NEGATIVE side
#property indicator_label5    "Hist_Red_Neg"
#property indicator_type5     DRAW_HISTOGRAM
#property indicator_color5    clrRed
#property indicator_style5    STYLE_SOLID
#property indicator_width5    4

// Plot 5: Yellow histogram POSITIVE side
#property indicator_label6    "Hist_Yellow_Pos"
#property indicator_type6     DRAW_HISTOGRAM
#property indicator_color6    clrYellow
#property indicator_style6    STYLE_SOLID
#property indicator_width6    4

// Plot 6: Yellow histogram NEGATIVE side
#property indicator_label7    "Hist_Yellow_Neg"
#property indicator_type7     DRAW_HISTOGRAM
#property indicator_color7    clrYellow
#property indicator_style7    STYLE_SOLID
#property indicator_width7    4

// Plot 7: GREEN histogram (drawn LAST to overlay)
#property indicator_label8    "Hist_Green"
#property indicator_type8     DRAW_HISTOGRAM
#property indicator_color8    clrLime
#property indicator_style8    STYLE_SOLID
#property indicator_width8    4

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

input int InpFastEMA  = 8;      // Fast EMA period
input int InpSlowEMA  = 13;     // Slow EMA period

input int InpRedLineType = 3;   // Red line type (1=EMA5, 2=EMA8, 3=EMA13, 4=EMA21, 5=Double)
input int InpRedEMA_A    = 5;   // Red EMA period A
input int InpRedEMA_B    = 8;   // Red EMA period B
input int InpRedEMA_C    = 13;  // Red EMA period C
input int InpRedEMA_D    = 21;  // Red EMA period D
input int InpDoubleEMA1  = 5;   // Double smooth: First EMA
input int InpDoubleEMA2  = 3;   // Double smooth: Second EMA

input bool InpEnableCCI     = true;                     // Enable CCI reset logic
input int  InpCCIPeriod     = 13;                       // CCI period
input ENUM_CCI_PRICE InpCCIPrice = CCI_PRICE_TYPICAL;   // CCI price calculation

input bool InpEnableGreen   = true;                     // Enable GREEN momentum histogram

// User-editable colors (Inputs tab — reliable on macOS/Wine)
input color InpColorBlueLine = clrDodgerBlue;  // Blue MACD core line
input color InpColorRedLine  = clrRed;         // Red signal & contour lines
input color InpColorBullish  = clrYellow;      // Bullish (yellow) histogram color
input color InpColorBearish  = clrRed;         // Bearish (red) histogram color
input color InpColorGreen    = clrLime;        // GREEN momentum overlay color

//+------------------------------------------------------------------+
//| INDICATOR BUFFERS                                                 |
//+------------------------------------------------------------------+

// Visible plot buffers
double g_BlueCore[];        // Blue MACD core line
double g_RedSignal[];       // Red signal line
double g_RedContour[];      // Red contour line
double g_HistRedPos[];      // Red histogram - positive side
double g_HistRedNeg[];      // Red histogram - negative side
double g_HistYellowPos[];   // Yellow histogram - positive side
double g_HistYellowNeg[];   // Yellow histogram - negative side
double g_HistGreen[];       // GREEN histogram overlay

// Internal calculation buffers
double g_Fast[];            // Fast EMA
double g_Slow[];            // Slow EMA
double g_CCI[];             // CCI values

// Cached chart background color (used for GREEN masking when InpEnableGreen=false)
color g_LastBgColor = CLR_NONE;

//+------------------------------------------------------------------+
//| HELPER FUNCTIONS                                                  |
//+------------------------------------------------------------------+

double _alpha(const int period)
{
   if(period <= 1)
      return 1.0;
   return 2.0 / ((double)period + 1.0);
}

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
         
      case 5: // Double EMA
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
   SetIndexBuffer(0, g_BlueCore,      INDICATOR_DATA);
   SetIndexBuffer(1, g_RedSignal,     INDICATOR_DATA);
   SetIndexBuffer(2, g_RedContour,    INDICATOR_DATA);
   SetIndexBuffer(3, g_HistRedPos,    INDICATOR_DATA);
   SetIndexBuffer(4, g_HistRedNeg,    INDICATOR_DATA);
   SetIndexBuffer(5, g_HistYellowPos, INDICATOR_DATA);
   SetIndexBuffer(6, g_HistYellowNeg, INDICATOR_DATA);
   SetIndexBuffer(7, g_HistGreen,     INDICATOR_DATA);
   
   SetIndexBuffer(8,  g_Fast,         INDICATOR_CALCULATIONS);
   SetIndexBuffer(9,  g_Slow,         INDICATOR_CALCULATIONS);
   SetIndexBuffer(10, g_CCI,          INDICATOR_CALCULATIONS);
   
   ArraySetAsSeries(g_BlueCore,      true);
   ArraySetAsSeries(g_RedSignal,     true);
   ArraySetAsSeries(g_RedContour,    true);
   ArraySetAsSeries(g_HistRedPos,    true);
   ArraySetAsSeries(g_HistRedNeg,    true);
   ArraySetAsSeries(g_HistYellowPos, true);
   ArraySetAsSeries(g_HistYellowNeg, true);
   ArraySetAsSeries(g_HistGreen,     true);
   ArraySetAsSeries(g_Fast,          true);
   ArraySetAsSeries(g_Slow,          true);
   ArraySetAsSeries(g_CCI,           true);
   
   PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(3, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(4, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(5, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(6, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(7, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   
   // Apply user-editable colors (Inputs tab) to all plots.
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, InpColorBlueLine);
   PlotIndexSetInteger(1, PLOT_LINE_COLOR, InpColorRedLine);
   PlotIndexSetInteger(2, PLOT_LINE_COLOR, InpColorRedLine);
   PlotIndexSetInteger(3, PLOT_LINE_COLOR, InpColorBearish);
   PlotIndexSetInteger(4, PLOT_LINE_COLOR, InpColorBearish);
   PlotIndexSetInteger(5, PLOT_LINE_COLOR, InpColorBullish);
   PlotIndexSetInteger(6, PLOT_LINE_COLOR, InpColorBullish);

   // GREEN visibility:
   //   InpEnableGreen=true  → paint plot 7 with user-selected InpColorGreen.
   //   InpEnableGreen=false → paint plot 7 in chart background color so bars are
   //                          invisible BUT still mask yellow/red below them,
   //                          preserving the ribbon-only look (matches MT4 reference).
   if(InpEnableGreen)
   {
      PlotIndexSetInteger(7, PLOT_LINE_COLOR, InpColorGreen);
      g_LastBgColor = CLR_NONE;
   }
   else
   {
      g_LastBgColor = (color)ChartGetInteger(0, CHART_COLOR_BACKGROUND);
      PlotIndexSetInteger(7, PLOT_LINE_COLOR, g_LastBgColor);
   }
   
   string red_name[] = {"EMA5", "EMA8", "EMA13", "EMA21", "Double"};
   string red_label = red_name[InpRedLineType - 1];
   string cci_label = InpEnableCCI ? " + CCI(" + IntegerToString(InpCCIPeriod) + ")" : "";
   string green_label = InpEnableGreen ? " + GREEN" : "";
   
   IndicatorSetString(INDICATOR_SHORTNAME, 
                      "DPI v31 (" + IntegerToString(InpFastEMA) + "," + 
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

   // Grow internal EMA buffers on demand. ArrayResize is a no-op when the
   // requested size equals the current size, so this is cheap to call every tick.
   // FIX: previously these arrays were sized once on first OnCalculate via a
   // `buffers_initialized` flag, which caused writes past array bounds as
   // new bars arrived → Red_Signal collapsed → ribbon flattened over time.
   if(ArraySize(ema_a) < rates_total)
   {
      ArrayResize(ema_a,         rates_total);
      ArrayResize(ema_b,         rates_total);
      ArrayResize(ema_c,         rates_total);
      ArrayResize(ema_d,         rates_total);
      ArrayResize(double_stage1, rates_total);
      ArrayResize(double_final,  rates_total);

      ArraySetAsSeries(ema_a,         true);
      ArraySetAsSeries(ema_b,         true);
      ArraySetAsSeries(ema_c,         true);
      ArraySetAsSeries(ema_d,         true);
      ArraySetAsSeries(double_stage1, true);
      ArraySetAsSeries(double_final,  true);
   }

   const double aFast = _alpha(InpFastEMA);
   const double aSlow = _alpha(InpSlowEMA);

   int oldest = rates_total - 1;
   g_Fast[oldest] = close[oldest];
   g_Slow[oldest] = close[oldest];
   g_BlueCore[oldest] = 0.0;
   g_RedSignal[oldest] = 0.0;
   g_RedContour[oldest] = EMPTY_VALUE;
   g_HistRedPos[oldest] = EMPTY_VALUE;
   g_HistRedNeg[oldest] = EMPTY_VALUE;
   g_HistYellowPos[oldest] = EMPTY_VALUE;
   g_HistYellowNeg[oldest] = EMPTY_VALUE;
   g_HistGreen[oldest] = EMPTY_VALUE;
   g_CCI[oldest] = 0.0;
   
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
      g_RedContour[i] = hist;
      
      if(InpEnableCCI)
      {
         g_CCI[i] = CalculateCCI(InpCCIPeriod, i, high, low, close, open);
      }
      else
      {
         g_CCI[i] = 0.0;
      }
      
      // Determine GREEN condition
      bool both_above_zero = (g_BlueCore[i] > 0.0 && hist > 0.0);
      bool both_below_zero = (g_BlueCore[i] < 0.0 && hist < 0.0);
      
      // CCI color logic
      bool hist_wants_yellow;
      if(hist >= 0.0)
      {
         hist_wants_yellow = !(InpEnableCCI && g_CCI[i] < 0.0);
      }
      else
      {
         hist_wants_yellow = (InpEnableCCI && g_CCI[i] >= 0.0);
      }
      
      // ── Composite rendering ─────────────────────────────────────────
      // Determine sides
      bool blue_positive = (g_BlueCore[i] > 0.0);
      bool hist_positive = (hist > 0.0);
      bool opposite_sides = (blue_positive != hist_positive);
      
      // Calculate extents
      double positive_extent = 0.0;
      double negative_extent = 0.0;
      
      if(opposite_sides)
      {
         if(blue_positive)
         {
            positive_extent = g_BlueCore[i];
            negative_extent = hist;
         }
         else
         {
            positive_extent = hist;
            negative_extent = g_BlueCore[i];
         }
      }
      else
      {
         if(blue_positive && hist_positive)
         {
            positive_extent = MathMax(g_BlueCore[i], hist);
            negative_extent = 0.0;
         }
         else if(!blue_positive && !hist_positive)
         {
            positive_extent = 0.0;
            negative_extent = MathMin(g_BlueCore[i], hist);
         }
      }
      
      // GREEN buffer always populated when Blue and hist aligned same side.
      // Visual visibility controlled by plot color (chart background color when InpEnableGreen=false).
      if(both_above_zero)
         g_HistGreen[i] = MathMin(g_BlueCore[i], hist);
      else if(both_below_zero)
         g_HistGreen[i] = MathMax(g_BlueCore[i], hist);
      else
         g_HistGreen[i] = EMPTY_VALUE;
      
      // Draw base layer
      if(opposite_sides)
      {
         // Positive side
         if(positive_extent > 0.0)
         {
            if(hist_wants_yellow)
            {
               g_HistYellowPos[i] = positive_extent;
               g_HistRedPos[i] = EMPTY_VALUE;
            }
            else
            {
               g_HistYellowPos[i] = EMPTY_VALUE;
               g_HistRedPos[i] = positive_extent;
            }
         }
         else
         {
            g_HistYellowPos[i] = EMPTY_VALUE;
            g_HistRedPos[i] = EMPTY_VALUE;
         }
         
         // Negative side
         if(negative_extent < 0.0)
         {
            if(hist_wants_yellow)
            {
               g_HistYellowNeg[i] = negative_extent;
               g_HistRedNeg[i] = EMPTY_VALUE;
            }
            else
            {
               g_HistYellowNeg[i] = EMPTY_VALUE;
               g_HistRedNeg[i] = negative_extent;
            }
         }
         else
         {
            g_HistYellowNeg[i] = EMPTY_VALUE;
            g_HistRedNeg[i] = EMPTY_VALUE;
         }
      }
      else
      {
         // SAME SIDE
         if(positive_extent > 0.0)
         {
            if(hist_wants_yellow)
            {
               g_HistYellowPos[i] = positive_extent;
               g_HistRedPos[i] = EMPTY_VALUE;
            }
            else
            {
               g_HistYellowPos[i] = EMPTY_VALUE;
               g_HistRedPos[i] = positive_extent;
            }
            
            g_HistYellowNeg[i] = EMPTY_VALUE;
            g_HistRedNeg[i] = EMPTY_VALUE;
         }
         else if(negative_extent < 0.0)
         {
            if(hist_wants_yellow)
            {
               g_HistYellowNeg[i] = negative_extent;
               g_HistRedNeg[i] = EMPTY_VALUE;
            }
            else
            {
               g_HistYellowNeg[i] = EMPTY_VALUE;
               g_HistRedNeg[i] = negative_extent;
            }
            
            g_HistYellowPos[i] = EMPTY_VALUE;
            g_HistRedPos[i] = EMPTY_VALUE;
         }
         else
         {
            g_HistYellowPos[i] = EMPTY_VALUE;
            g_HistRedPos[i] = EMPTY_VALUE;
            g_HistYellowNeg[i] = EMPTY_VALUE;
            g_HistRedNeg[i] = EMPTY_VALUE;
         }
      }
   }

   return rates_total;
}
//+------------------------------------------------------------------+
//| Chart event handler — re-apply background masking when chart      |
//| theme/colors change, but only when GREEN is disabled.             |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id == CHARTEVENT_CHART_CHANGE && !InpEnableGreen)
   {
      color bg = (color)ChartGetInteger(0, CHART_COLOR_BACKGROUND);
      if(bg != g_LastBgColor)
      {
         g_LastBgColor = bg;
         PlotIndexSetInteger(7, PLOT_LINE_COLOR, g_LastBgColor);
      }
   }
}
//+------------------------------------------------------------------+
