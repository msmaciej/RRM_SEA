//+------------------------------------------------------------------+
//|                    DPI_Indicator_v14b_ThresholdBased.mq5         |
//|                          Alternative: Threshold color assignment |
//|                   Use if v14a green still appears too thick      |
//+------------------------------------------------------------------+
#property copyright "MT5 Reverse Engineering - v14b"
#property link      ""
#property version   "14.01"
#property indicator_separate_window
#property indicator_buffers 4
#property indicator_plots   4

// Blue line (MACD core)
#property indicator_label1  "DPI Blue"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrDodgerBlue
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

// Red histogram
#property indicator_label2  "DPI Red"
#property indicator_type2   DRAW_HISTOGRAM
#property indicator_color2  clrRed
#property indicator_style2  STYLE_SOLID
#property indicator_width2  3

// Yellow histogram
#property indicator_label3  "DPI Yellow"
#property indicator_type3   DRAW_HISTOGRAM
#property indicator_color3  clrYellow
#property indicator_style3  STYLE_SOLID
#property indicator_width3  3

// Green histogram
#property indicator_label4  "DPI Green"
#property indicator_type4   DRAW_HISTOGRAM
#property indicator_color4  clrLime
#property indicator_style4  STYLE_SOLID
#property indicator_width4  3

//--- TEST-02 preserved parameters
input int InpFastEMA = 8;                    // Lead EMA
input int InpSlowEMA = 13;                   // Follow EMA (13 or 21)
input int InpRedA_EMA = 5;                   // Red candidate A
input int InpRedB_EMA = 8;                   // Red candidate B
input int InpRedC_EMA = 13;                  // Red candidate C
input int InpRedD_EMA = 21;                  // Red candidate D
input int InpDoubleFirst = 5;                // Double smooth 1st
input int InpDoubleSecond = 3;               // Double smooth 2nd
input int InpSelectedRedForHistogram = 3;    // Fib selector (3 for slow13, 4 for slow21)

//--- v14b specific: threshold parameters for tuning
input double InpRedThreshold = 0.5;          // Red dominance threshold ratio
input double InpGreenThreshold = 0.2;        // Green visibility threshold ratio

//--- Indicator buffers
double BlueBuffer[];
double RedBuffer[];
double YellowBuffer[];
double GreenBuffer[];

//--- Working buffers
double FastEMA[];
double SlowEMA[];
double SelectedRedEMA[];
double DoubleSmoothedRed[];

//+------------------------------------------------------------------+
//| Custom indicator initialization                                  |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Indicator buffers mapping
   SetIndexBuffer(0, BlueBuffer, INDICATOR_DATA);
   SetIndexBuffer(1, RedBuffer, INDICATOR_DATA);
   SetIndexBuffer(2, YellowBuffer, INDICATOR_DATA);
   SetIndexBuffer(3, GreenBuffer, INDICATOR_DATA);
   
   //--- Working buffers (not plotted)
   SetIndexBuffer(4, FastEMA, INDICATOR_CALCULATIONS);
   SetIndexBuffer(5, SlowEMA, INDICATOR_CALCULATIONS);
   SetIndexBuffer(6, SelectedRedEMA, INDICATOR_CALCULATIONS);
   SetIndexBuffer(7, DoubleSmoothedRed, INDICATOR_CALCULATIONS);
   
   //--- Set drawing order
   PlotIndexSetInteger(0, PLOT_DRAW_BEGIN, MathMax(InpFastEMA, InpSlowEMA));
   PlotIndexSetInteger(1, PLOT_DRAW_BEGIN, MathMax(InpFastEMA, InpSlowEMA));
   PlotIndexSetInteger(2, PLOT_DRAW_BEGIN, MathMax(InpFastEMA, InpSlowEMA));
   PlotIndexSetInteger(3, PLOT_DRAW_BEGIN, MathMax(InpFastEMA, InpSlowEMA));
   
   //--- Set empty value
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, 0.0);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, 0.0);
   PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, 0.0);
   PlotIndexSetDouble(3, PLOT_EMPTY_VALUE, 0.0);
   
   //--- Indicator name
   string short_name = StringFormat("DPI v14b (%d,%d) RedSel=%d Thresh=%.1f/%.1f", 
                                    InpFastEMA, InpSlowEMA, InpSelectedRedForHistogram,
                                    InpRedThreshold, InpGreenThreshold);
   IndicatorSetString(INDICATOR_SHORTNAME, short_name);
   
   //--- Digits
   IndicatorSetInteger(INDICATOR_DIGITS, _Digits + 1);
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Custom indicator iteration                                        |
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
   if(rates_total < MathMax(InpFastEMA, InpSlowEMA))
      return(0);
      
   int start = prev_calculated - 1;
   if(start < 0) start = 0;
   
   //--- Calculate base EMAs
   CalculateEMA(close, rates_total, InpFastEMA, FastEMA, start);
   CalculateEMA(close, rates_total, InpSlowEMA, SlowEMA, start);
   
   //--- Calculate blue line (MACD core)
   for(int i = start; i < rates_total; i++)
   {
      BlueBuffer[i] = FastEMA[i] - SlowEMA[i];
   }
   
   //--- Calculate selected red histogram candidate
   int selectedPeriod = GetSelectedRedPeriod(InpSelectedRedForHistogram);
   CalculateEMA(close, rates_total, selectedPeriod, SelectedRedEMA, start);
   
   //--- Double smooth the selected red
   CalculateEMA(SelectedRedEMA, rates_total, InpDoubleFirst, DoubleSmoothedRed, start);
   double TempBuffer[];
   ArrayResize(TempBuffer, rates_total);
   ArraySetAsSeries(TempBuffer, false);
   CalculateEMA(DoubleSmoothedRed, rates_total, InpDoubleSecond, TempBuffer, start);
   
   //--- v14b: Threshold-based color assignment
   //    Hypothesis: Red drawn when it's "dominant" (close to blue magnitude)
   //                Yellow drawn during weak/divergent phases
   //                Green drawn only for small residual gaps
   
   for(int i = start; i < rates_total; i++)
   {
      double blue = BlueBuffer[i];
      double smoothedRed = TempBuffer[i];
      double residual = blue - smoothedRed;
      
      // Initialize all histograms to EMPTY
      RedBuffer[i] = EMPTY_VALUE;
      YellowBuffer[i] = EMPTY_VALUE;
      GreenBuffer[i] = EMPTY_VALUE;
      
      double blueAbs = MathAbs(blue);
      double redAbs = MathAbs(smoothedRed);
      double residualAbs = MathAbs(residual);
      
      //--- Threshold-based decision tree
      
      // Condition 1: RED - smoothed red is dominant (close to blue magnitude)
      if(blueAbs > 0.00001 && redAbs > 0.00001)
      {
         double redRatio = redAbs / blueAbs;
         
         if(redRatio >= InpRedThreshold)  // Red is significant portion of blue
         {
            // RED histogram: Draw the smoothed red component
            RedBuffer[i] = smoothedRed;
            
            // GREEN gap: Only if residual is visible but small
            double residualRatio = residualAbs / blueAbs;
            if(residualRatio >= InpGreenThreshold && residualRatio < (1.0 - InpRedThreshold))
            {
               GreenBuffer[i] = residual;
            }
         }
         else
         {
            // YELLOW histogram: Red is weak, blue is from other components
            YellowBuffer[i] = smoothedRed;
            
            // GREEN shows the larger gap
            if(residualAbs > redAbs * 0.3)  // Gap is significant
            {
               GreenBuffer[i] = residual;
            }
         }
      }
      else if(blueAbs > 0.00001)
      {
         // Only blue exists, no red - draw as GREEN
         GreenBuffer[i] = blue;
      }
      else if(redAbs > 0.00001)
      {
         // Only red exists - draw as YELLOW (unusual case)
         YellowBuffer[i] = smoothedRed;
      }
   }
   
   return(rates_total);
}

//+------------------------------------------------------------------+
//| Calculate EMA on any buffer                                       |
//+------------------------------------------------------------------+
void CalculateEMA(const double &src[], int rates_total, int period, 
                  double &dest[], int start)
{
   if(period <= 0) return;
   
   double alpha = 2.0 / (period + 1.0);
   
   // Initialize first value
   if(start == 0 && rates_total > 0)
   {
      dest[0] = src[0];
      start = 1;
   }
   
   // Calculate EMA
   for(int i = start; i < rates_total; i++)
   {
      dest[i] = alpha * src[i] + (1.0 - alpha) * dest[i-1];
   }
}

//+------------------------------------------------------------------+
//| Get selected red period from Fibonacci selector                  |
//+------------------------------------------------------------------+
int GetSelectedRedPeriod(int selector)
{
   switch(selector)
   {
      case 1: return InpRedA_EMA;  // 5
      case 2: return InpRedB_EMA;  // 8
      case 3: return InpRedC_EMA;  // 13
      case 4: return InpRedD_EMA;  // 21
      default: return InpRedC_EMA; // Default to 13
   }
}
//+------------------------------------------------------------------+
