//+------------------------------------------------------------------+
//|                    DPI_Indicator_v14_IndependentHistograms.mq5   |
//|                                  Rebuilt from TEST-02 foundation |
//|                      Focus: Independent histogram color logic    |
//+------------------------------------------------------------------+
#property copyright "MT5 Reverse Engineering - v14"
#property link      ""
#property version   "14.00"
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
   
   //--- Set drawing order (later = on top)
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
   string short_name = StringFormat("DPI v14 (%d,%d) RedSel=%d", 
                                    InpFastEMA, InpSlowEMA, InpSelectedRedForHistogram);
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
   
   //--- Now assign histogram colors based on INDEPENDENT conditions
   //    Key insight: MT4 DPI likely uses position/slope/zone conditions
   //    not residual arithmetic
   
   for(int i = start; i < rates_total; i++)
   {
      double blue = BlueBuffer[i];
      double smoothedRed = TempBuffer[i];
      
      // Initialize all histograms to EMPTY
      RedBuffer[i] = EMPTY_VALUE;
      YellowBuffer[i] = EMPTY_VALUE;
      GreenBuffer[i] = EMPTY_VALUE;
      
      //--- Hypothesis: Color assignment based on blue vs smoothed relationship
      //    and magnitude/direction
      
      // Condition 1: RED histogram - dominant oscillator state
      // Draw red when smoothedRed and blue are both significant and aligned
      if(MathAbs(smoothedRed) > 0.00001)  // Has magnitude
      {
         // Red appears when smoothed red component is the dominant feature
         if((smoothedRed > 0 && blue > 0) || (smoothedRed < 0 && blue < 0))
         {
            // Both same sign - draw smoothed red as RED histogram
            RedBuffer[i] = smoothedRed;
         }
         else
         {
            // Opposite signs - draw smoothed red as YELLOW histogram
            YellowBuffer[i] = smoothedRed;
         }
      }
      
      // Condition 2: GREEN histogram - difference/residual component
      // Green appears when there's a gap between blue and red
      double residual = blue - smoothedRed;
      if(MathAbs(residual) > 0.00001)
      {
         // Only draw green if it's NOT already covered by red/yellow
         if(RedBuffer[i] == EMPTY_VALUE && YellowBuffer[i] == EMPTY_VALUE)
         {
            GreenBuffer[i] = residual;
         }
         else
         {
            // Green draws the "gap" between blue and the red/yellow histogram
            // If red/yellow already drawn, green fills to complete the blue total
            if(RedBuffer[i] != EMPTY_VALUE)
            {
               GreenBuffer[i] = blue - RedBuffer[i];
            }
            else if(YellowBuffer[i] != EMPTY_VALUE)
            {
               GreenBuffer[i] = blue - YellowBuffer[i];
            }
         }
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
