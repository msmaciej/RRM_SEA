//  SAVE AS UTF-16 LE WITH BOM
//+------------------------------------------------------------------+
//|                         DPI_v28_CLEAN.mq5                         |
//|   Purpose: Clean DPI indicator without CCI reset logic           |
//|   Version: 28 CLEAN - Production ready, decluttered              |
//|                                                                  |
//|   COMPONENTS:                                                    |
//|   1. Blue Line (LEAD)    = MACD Core = EMA(8) - EMA(13)         |
//|   2. Red Line (FOLLOW)   = EMA of Blue Line (signal)            |
//|   3. Red Contour         = Histogram outline                     |
//|   4. Yellow Histogram    = Positive values (hist >= 0)          |
//|   5. Red Histogram       = Negative values (hist < 0)           |
//|                                                                  |
//|   HISTOGRAM COLOR LOGIC:                                         |
//|   Simple, clean logic:                                           |
//|     - hist >= 0 → YELLOW                                        |
//|     - hist <  0 → RED                                            |
//|                                                                  |
//|   USAGE:                                                         |
//|   Pure MACD histogram visualization without CCI filtering.      |
//|   Provides clear, unambiguous signals for trend following.      |
//+------------------------------------------------------------------+
#property strict
#property version   "28.00"
#property indicator_separate_window
#property indicator_buffers 7
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

// Plot 3: Yellow histogram (positive values)
#property indicator_label4    "Hist_Positive"
#property indicator_type4     DRAW_HISTOGRAM
#property indicator_color4    clrYellow
#property indicator_style4    STYLE_SOLID
#property indicator_width4    3

// Plot 4: Red histogram (negative values)
#property indicator_label5    "Hist_Negative"
#property indicator_type5     DRAW_HISTOGRAM
#property indicator_color5    clrRed
#property indicator_style5    STYLE_SOLID
#property indicator_width5    3

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

//+------------------------------------------------------------------+
//| INDICATOR BUFFERS                                                 |
//+------------------------------------------------------------------+

// Visible plot buffers
double g_BlueCore[];      // Blue MACD core line
double g_RedSignal[];     // Red signal line (selected)
double g_RedContour[];    // Red contour line
double g_HistPos[];       // Yellow histogram
double g_HistNeg[];       // Red histogram

// Internal calculation buffers
double g_Fast[];          // Fast EMA
double g_Slow[];          // Slow EMA

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
//| Calculate selected red signal line                               |
//+------------------------------------------------------------------+
double CalculateRedSignal(const int type, const double core_value, const int bar,
                          double &ema_a[], double &ema_b[], double &ema_c[], 
                          double &ema_d[], double &double_stage1[], double &double_final[])
{
   static double alpha_a = 0, alpha_b = 0, alpha_c = 0, alpha_d = 0;
   static double alpha_d1 = 0, alpha_d2 = 0;
   static bool initialized = false;
   
   // Initialize alphas once
   if(!initialized)
   {
      alpha_a  = _alpha(InpRedEMA_A);
      alpha_b  = _alpha(InpRedEMA_B);
      alpha_c  = _alpha(InpRedEMA_C);
      alpha_d  = _alpha(InpRedEMA_D);
      alpha_d1 = _alpha(InpDoubleEMA1);
      alpha_d2 = _alpha(InpDoubleEMA2);
      initialized = true;
   }
   
   // Calculate all candidates
   ema_a[bar] = alpha_a * core_value + (1.0 - alpha_a) * ema_a[bar + 1];
   ema_b[bar] = alpha_b * core_value + (1.0 - alpha_b) * ema_b[bar + 1];
   ema_c[bar] = alpha_c * core_value + (1.0 - alpha_c) * ema_c[bar + 1];
   ema_d[bar] = alpha_d * core_value + (1.0 - alpha_d) * ema_d[bar + 1];
   
   double_stage1[bar] = alpha_d1 * core_value + (1.0 - alpha_d1) * double_stage1[bar + 1];
   double_final[bar]  = alpha_d2 * double_stage1[bar] + (1.0 - alpha_d2) * double_final[bar + 1];
   
   // Return selected type
   switch(type)
   {
      case 1:  return ema_a[bar];
      case 2:  return ema_b[bar];
      case 3:  return ema_c[bar];
      case 4:  return ema_d[bar];
      case 5:  return double_final[bar];
      default: return ema_a[bar];
   }
}

//+------------------------------------------------------------------+
//| Indicator initialization                                          |
//+------------------------------------------------------------------+
int OnInit()
{
   if(InpFastEMA < 1 || InpSlowEMA <= InpFastEMA)
   {
      Print("DPI v28 CLEAN error: Slow EMA must be > Fast EMA.");
      return INIT_PARAMETERS_INCORRECT;
   }
   
   if(InpRedLineType < 1 || InpRedLineType > 5)
   {
      Print("DPI v28 CLEAN error: Red line type must be 1-5.");
      return INIT_PARAMETERS_INCORRECT;
   }

   // Set index buffers (5 visible plots + 2 internal)
   SetIndexBuffer(0, g_BlueCore,    INDICATOR_DATA);
   SetIndexBuffer(1, g_RedSignal,   INDICATOR_DATA);
   SetIndexBuffer(2, g_RedContour,  INDICATOR_DATA);
   SetIndexBuffer(3, g_HistPos,     INDICATOR_DATA);
   SetIndexBuffer(4, g_HistNeg,     INDICATOR_DATA);
   SetIndexBuffer(5, g_Fast,        INDICATOR_CALCULATIONS);
   SetIndexBuffer(6, g_Slow,        INDICATOR_CALCULATIONS);

   // Set arrays as series
   ArraySetAsSeries(g_BlueCore,    true);
   ArraySetAsSeries(g_RedSignal,   true);
   ArraySetAsSeries(g_RedContour,  true);
   ArraySetAsSeries(g_HistPos,     true);
   ArraySetAsSeries(g_HistNeg,     true);
   ArraySetAsSeries(g_Fast,        true);
   ArraySetAsSeries(g_Slow,        true);

   // Set empty values
   PlotIndexSetDouble(3, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(4, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   // Set indicator name
   string red_name[] = {"EMA5", "EMA8", "EMA13", "EMA21", "Double"};
   string red_label = red_name[InpRedLineType - 1];
   IndicatorSetString(INDICATOR_SHORTNAME, 
                      "DPI v28 (" + IntegerToString(InpFastEMA) + "," + 
                      IntegerToString(InpSlowEMA) + ", " + red_label + ")");
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
   int min_bars = InpSlowEMA + MathMax(InpRedEMA_D, InpDoubleEMA1 + InpDoubleEMA2) + 5;
   if(rates_total < min_bars)
      return 0;

   ArraySetAsSeries(close, true);

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
      
      // Histogram color: simple above/below zero logic
      if(hist >= 0.0)
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

   return rates_total;
}
//+------------------------------------------------------------------+
//| END OF INDICATOR                                                  |
//+------------------------------------------------------------------+
//
// USAGE NOTES:
//
// 1. VISUAL INTERPRETATION:
//    - Blue line above red = Bullish momentum
//    - Blue line below red = Bearish momentum
//    - Histogram crossing zero = Momentum shift
//    - Histogram expanding = Momentum strengthening
//    - Histogram contracting = Momentum weakening
//
// 2. TRADING SIGNALS:
//    - Yellow histogram (above 0) = Bullish zone
//    - Red histogram (below 0) = Bearish zone
//    - Transition from red to yellow = Buy signal
//    - Transition from yellow to red = Sell signal
//
// 3. EA INTEGRATION:
//    Simple trend confirmation:
//    - Market trend SELL + Histogram RED → Confirm trade
//    - Market trend SELL + Histogram YELLOW → Avoid trade
//    - Market trend BUY + Histogram YELLOW → Confirm trade
//    - Market trend BUY + Histogram RED → Avoid trade
//
// 4. PARAMETER OPTIMIZATION:
//    - InpRedLineType: Test which signal line matches your strategy
//    - Type 1 (EMA5): Fast, responsive
//    - Type 3 (EMA13): Balanced
//    - Type 5 (Double): Smoothest
//
// 5. ADVANTAGES OF v28:
//    - Clean, unambiguous signals
//    - No contradictory color resets
//    - Pure MACD histogram logic
//    - Easier to backtest and optimize
//
//+------------------------------------------------------------------+
