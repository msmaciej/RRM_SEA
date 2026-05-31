//  SAVE AS UTF-16 LE WITH BOM
//+------------------------------------------------------------------+
//|                    DPI_v30_FINAL_COLOR.mq5                        |
//|   Purpose: Use COLOR_HISTOGRAM for perfect ribbon                |
//|   Version: 30 FINAL COLOR - Complete solution                    |
//|                                                                  |
//|   REVOLUTIONARY APPROACH:                                        |
//|   Uses DRAW_COLOR_HISTOGRAM which allows:                        |
//|   - Single histogram buffer (one value per bar)                  |
//|   - Color buffer (color index per bar)                           |
//|   - Result: Complete fill + CCI color resets!                    |
//|                                                                  |
//|   Color indices:                                                 |
//|   0 = Red                                                         |
//|   1 = Yellow                                                      |
//+------------------------------------------------------------------+
#property strict
#property version   "30.00"
#property indicator_separate_window
#property indicator_buffers 8
#property indicator_plots   5

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

// Plot 3: Color histogram with CCI resets
#property indicator_label4    "Histogram"
#property indicator_type4     DRAW_COLOR_HISTOGRAM
#property indicator_color4    clrRed,clrYellow
#property indicator_style4    STYLE_SOLID
#property indicator_width4    4

// Plot 4: GREEN histogram (momentum alignment)
#property indicator_label5    "Hist_Green"
#property indicator_type5     DRAW_HISTOGRAM
#property indicator_color5    clrLimeGreen
#property indicator_style5    STYLE_SOLID
#property indicator_width5    4

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

input int InpFastEMA  = 8;
input int InpSlowEMA  = 13;
input int InpRedLineType = 3;
input int InpRedEMA_A    = 5;
input int InpRedEMA_B    = 8;
input int InpRedEMA_C    = 13;
input int InpRedEMA_D    = 21;
input int InpDoubleEMA1  = 5;
input int InpDoubleEMA2  = 3;
input bool InpEnableCCI     = true;
input int  InpCCIPeriod     = 13;
input ENUM_CCI_PRICE InpCCIPrice = CCI_PRICE_TYPICAL;
input bool InpEnableGreen   = true;

//+------------------------------------------------------------------+
//| INDICATOR BUFFERS                                                 |
//+------------------------------------------------------------------+

double g_BlueCore[];
double g_RedSignal[];
double g_RedContour[];
double g_Hist[];          // Color histogram values
double g_HistColor[];     // Color histogram colors
double g_HistGreen[];
double g_Fast[];
double g_Slow[];
double g_CCI[];

double _alpha(const int period)
{
   if(period <= 1) return 1.0;
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
      case 1:
         if(bar == ArraySize(ema_a) - 1)
            ema_a[bar] = core_value;
         else
         {
            double alpha_a = _alpha(InpRedEMA_A);
            ema_a[bar] = alpha_a * core_value + (1.0 - alpha_a) * ema_a[bar + 1];
         }
         result = ema_a[bar];
         break;
         
      case 2:
         if(bar == ArraySize(ema_b) - 1)
            ema_b[bar] = core_value;
         else
         {
            double alpha_b = _alpha(InpRedEMA_B);
            ema_b[bar] = alpha_b * core_value + (1.0 - alpha_b) * ema_b[bar + 1];
         }
         result = ema_b[bar];
         break;
         
      case 3:
         if(bar == ArraySize(ema_c) - 1)
            ema_c[bar] = core_value;
         else
         {
            double alpha_c = _alpha(InpRedEMA_C);
            ema_c[bar] = alpha_c * core_value + (1.0 - alpha_c) * ema_c[bar + 1];
         }
         result = ema_c[bar];
         break;
         
      case 4:
         if(bar == ArraySize(ema_d) - 1)
            ema_d[bar] = core_value;
         else
         {
            double alpha_d = _alpha(InpRedEMA_D);
            ema_d[bar] = alpha_d * core_value + (1.0 - alpha_d) * ema_d[bar + 1];
         }
         result = ema_d[bar];
         break;
         
      case 5:
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

int OnInit()
{
   SetIndexBuffer(0, g_BlueCore, INDICATOR_DATA);
   SetIndexBuffer(1, g_RedSignal, INDICATOR_DATA);
   SetIndexBuffer(2, g_RedContour, INDICATOR_DATA);
   SetIndexBuffer(3, g_Hist, INDICATOR_DATA);
   SetIndexBuffer(4, g_HistColor, INDICATOR_COLOR_INDEX);
   SetIndexBuffer(5, g_HistGreen, INDICATOR_DATA);
   SetIndexBuffer(6, g_Fast, INDICATOR_CALCULATIONS);
   SetIndexBuffer(7, g_Slow, INDICATOR_CALCULATIONS);
   SetIndexBuffer(8, g_CCI, INDICATOR_CALCULATIONS);
   
   ArraySetAsSeries(g_BlueCore, true);
   ArraySetAsSeries(g_RedSignal, true);
   ArraySetAsSeries(g_RedContour, true);
   ArraySetAsSeries(g_Hist, true);
   ArraySetAsSeries(g_HistColor, true);
   ArraySetAsSeries(g_HistGreen, true);
   ArraySetAsSeries(g_Fast, true);
   ArraySetAsSeries(g_Slow, true);
   ArraySetAsSeries(g_CCI, true);
   
   PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(3, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(5, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   
   string red_name[] = {"EMA5", "EMA8", "EMA13", "EMA21", "Double"};
   string red_label = red_name[InpRedLineType - 1];
   string cci_label = InpEnableCCI ? " + CCI(" + IntegerToString(InpCCIPeriod) + ")" : "";
   string green_label = InpEnableGreen ? " + GREEN" : "";
   
   IndicatorSetString(INDICATOR_SHORTNAME, 
                      "DPI v30 COLOR (" + IntegerToString(InpFastEMA) + "," + 
                      IntegerToString(InpSlowEMA) + ", " + red_label + ")" + cci_label + green_label);
   IndicatorSetInteger(INDICATOR_DIGITS, _Digits + 1);

   return INIT_SUCCEEDED;
}

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
   g_RedContour[oldest] = EMPTY_VALUE;
   g_Hist[oldest] = EMPTY_VALUE;
   g_HistColor[oldest] = 0;
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
      
      bool both_above_zero = (g_BlueCore[i] > 0.0 && hist > 0.0);
      bool both_below_zero = (g_BlueCore[i] < 0.0 && hist < 0.0);
      bool green_condition = InpEnableGreen && (both_above_zero || both_below_zero);
      
      // CCI color logic
      bool use_yellow;
      if(hist >= 0.0)
      {
         use_yellow = !(InpEnableCCI && g_CCI[i] < 0.0);
      }
      else
      {
         use_yellow = (InpEnableCCI && g_CCI[i] >= 0.0);
      }
      
      // COLOR HISTOGRAM APPROACH:
      // Single histogram value, color index determines color
      // This allows complete fill with CCI resets!
      
      // Fill to furthest extent
      double hist_extent;
      if(g_BlueCore[i] >= 0.0 && hist >= 0.0)
      {
         hist_extent = MathMax(g_BlueCore[i], hist);
      }
      else if(g_BlueCore[i] <= 0.0 && hist <= 0.0)
      {
         hist_extent = MathMin(g_BlueCore[i], hist);
      }
      else
      {
         // Opposite sides: use Blue
         hist_extent = g_BlueCore[i];
      }
      
      g_Hist[i] = hist_extent;
      g_HistColor[i] = use_yellow ? 1 : 0;  // 0=Red, 1=Yellow
      
      // GREEN overlay
      if(green_condition)
      {
         if(both_above_zero)
         {
            g_HistGreen[i] = MathMin(g_BlueCore[i], hist);
         }
         else
         {
            g_HistGreen[i] = MathMax(g_BlueCore[i], hist);
         }
      }
      else
      {
         g_HistGreen[i] = EMPTY_VALUE;
      }
   }

   return rates_total;
}
//+------------------------------------------------------------------+
