//+------------------------------------------------------------------+
//|                              DPI_v24.mq5                         |
//| DPI_v13 + Red Line that traces histogram peaks                  |
//| ONLY change: Added Plot 10 for selected red component line      |
//+------------------------------------------------------------------+
#property strict
#property version   "24.00"
#property indicator_separate_window
#property indicator_buffers 10
#property indicator_plots   10

#property indicator_level1     0.0
#property indicator_levelcolor clrSilver
#property indicator_levelstyle STYLE_DOT
#property indicator_levelwidth 1

// Plot 0: blue MACD core candidate
#property indicator_label1  "Blue_MACD_Core"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrDodgerBlue
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

// Plot 1: red candidate A
#property indicator_label2  "Red_EMA_5"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrRed
#property indicator_style2  STYLE_SOLID
#property indicator_width2  2

// Plot 2: candidate B
#property indicator_label3  "Red_EMA_8"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrTomato
#property indicator_style3  STYLE_DOT
#property indicator_width3  1

// Plot 3: candidate C
#property indicator_label4  "Red_EMA_13"
#property indicator_type4   DRAW_LINE
#property indicator_color4  clrOrangeRed
#property indicator_style4  STYLE_DASH
#property indicator_width4  1

// Plot 4: candidate D
#property indicator_label5  "Red_EMA_21"
#property indicator_type5   DRAW_LINE
#property indicator_color5  clrMagenta
#property indicator_style5  STYLE_DASHDOT
#property indicator_width5  1

// Plot 5: double smooth candidate
#property indicator_label6  "Red_Double_5_3"
#property indicator_type6   DRAW_LINE
#property indicator_color6  clrWhite
#property indicator_style6  STYLE_DOT
#property indicator_width6  1

// Plot 6: grey MACD-style histogram core minus selected red
#property indicator_label7  "Hist_CoreMinusSelected"
#property indicator_type7   DRAW_HISTOGRAM
#property indicator_color7  clrSilver
#property indicator_style7  STYLE_SOLID
#property indicator_width7  2

// Plot 7: yellow positive histogram
#property indicator_label8  "Hist_Pos"
#property indicator_type8   DRAW_HISTOGRAM
#property indicator_color8  clrYellow
#property indicator_style8  STYLE_SOLID
#property indicator_width8  3

// Plot 8: red negative histogram
#property indicator_label9  "Hist_Neg"
#property indicator_type9   DRAW_HISTOGRAM
#property indicator_color9  clrRed
#property indicator_style9  STYLE_SOLID
#property indicator_width9  3

// Plot 9: NEW - Red line tracing histogram peaks (selected component)
#property indicator_label10 "Red_HistogramPeaks"
#property indicator_type10  DRAW_LINE
#property indicator_color10 clrRed
#property indicator_style10 STYLE_SOLID
#property indicator_width10 2

input int InpFastEMA = 8;
input int InpSlowEMA = 13;

input int InpRedA_EMA = 5;
input int InpRedB_EMA = 8;
input int InpRedC_EMA = 13;
input int InpRedD_EMA = 21;

input int InpDoubleFirst  = 5;
input int InpDoubleSecond = 3;

// 1=A EMA5, 2=B EMA8, 3=C EMA13, 4=D EMA21, 5=Double 5/3
input int InpSelectedRedForHistogram = 1;

double g_Core[];
double g_RedA[];
double g_RedB[];
double g_RedC[];
double g_RedD[];
double g_Double[];
double g_HistGrey[];
double g_HistPos[];
double g_HistNeg[];
double g_RedLine[];  // NEW - Histogram peak line

double g_Fast[];
double g_Slow[];
double g_DoubleStage1[];

double _alpha(const int period)
{
   if(period <= 1)
      return 1.0;
   return 2.0 / ((double)period + 1.0);
}

int OnInit()
{
   if(InpFastEMA < 1 || InpSlowEMA <= InpFastEMA)
   {
      Print("DPI v24 error: Slow EMA must be > Fast EMA.");
      return INIT_PARAMETERS_INCORRECT;
   }

   SetIndexBuffer(0, g_Core,     INDICATOR_DATA);
   SetIndexBuffer(1, g_RedA,     INDICATOR_DATA);
   SetIndexBuffer(2, g_RedB,     INDICATOR_DATA);
   SetIndexBuffer(3, g_RedC,     INDICATOR_DATA);
   SetIndexBuffer(4, g_RedD,     INDICATOR_DATA);
   SetIndexBuffer(5, g_Double,   INDICATOR_DATA);
   SetIndexBuffer(6, g_HistGrey, INDICATOR_DATA);
   SetIndexBuffer(7, g_HistPos,  INDICATOR_DATA);
   SetIndexBuffer(8, g_HistNeg,  INDICATOR_DATA);
   SetIndexBuffer(9, g_RedLine,  INDICATOR_DATA);  // NEW

   ArraySetAsSeries(g_Core,     true);
   ArraySetAsSeries(g_RedA,     true);
   ArraySetAsSeries(g_RedB,     true);
   ArraySetAsSeries(g_RedC,     true);
   ArraySetAsSeries(g_RedD,     true);
   ArraySetAsSeries(g_Double,   true);
   ArraySetAsSeries(g_HistGrey, true);
   ArraySetAsSeries(g_HistPos,  true);
   ArraySetAsSeries(g_HistNeg,  true);
   ArraySetAsSeries(g_RedLine,  true);  // NEW

   ArraySetAsSeries(g_Fast,         true);
   ArraySetAsSeries(g_Slow,         true);
   ArraySetAsSeries(g_DoubleStage1, true);

   PlotIndexSetDouble(7, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(8, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   IndicatorSetString(INDICATOR_SHORTNAME, "DPI v24 (with Red Peak Line)");
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
   int min_bars = InpSlowEMA + MathMax(MathMax(InpRedC_EMA, InpRedD_EMA), InpDoubleFirst + InpDoubleSecond) + 5;
   if(rates_total < min_bars)
      return 0;

   ArraySetAsSeries(close, true);

   ArrayResize(g_Fast, rates_total);
   ArrayResize(g_Slow, rates_total);
   ArrayResize(g_DoubleStage1, rates_total);

   const double aFast = _alpha(InpFastEMA);
   const double aSlow = _alpha(InpSlowEMA);
   const double aA    = _alpha(InpRedA_EMA);
   const double aB    = _alpha(InpRedB_EMA);
   const double aC    = _alpha(InpRedC_EMA);
   const double aD    = _alpha(InpRedD_EMA);
   const double aD1   = _alpha(InpDoubleFirst);
   const double aD2   = _alpha(InpDoubleSecond);

   int oldest = rates_total - 1;

   g_Fast[oldest] = close[oldest];
   g_Slow[oldest] = close[oldest];

   g_Core[oldest] = 0.0;
   g_RedA[oldest] = 0.0;
   g_RedB[oldest] = 0.0;
   g_RedC[oldest] = 0.0;
   g_RedD[oldest] = 0.0;
   g_DoubleStage1[oldest] = 0.0;
   g_Double[oldest] = 0.0;
   g_HistGrey[oldest] = 0.0;
   g_HistPos[oldest] = EMPTY_VALUE;
   g_HistNeg[oldest] = EMPTY_VALUE;
   g_RedLine[oldest] = 0.0;  // NEW

   for(int i = rates_total - 2; i >= 0; --i)
   {
      g_Fast[i] = aFast * close[i] + (1.0 - aFast) * g_Fast[i + 1];
      g_Slow[i] = aSlow * close[i] + (1.0 - aSlow) * g_Slow[i + 1];

      g_Core[i] = g_Fast[i] - g_Slow[i];   // MACD(8,13) core

      g_RedA[i] = aA * g_Core[i] + (1.0 - aA) * g_RedA[i + 1];
      g_RedB[i] = aB * g_Core[i] + (1.0 - aB) * g_RedB[i + 1];
      g_RedC[i] = aC * g_Core[i] + (1.0 - aC) * g_RedC[i + 1];
      g_RedD[i] = aD * g_Core[i] + (1.0 - aD) * g_RedD[i + 1];

      g_DoubleStage1[i] = aD1 * g_Core[i] + (1.0 - aD1) * g_DoubleStage1[i + 1];
      g_Double[i]       = aD2 * g_DoubleStage1[i] + (1.0 - aD2) * g_Double[i + 1];

      double selected = g_RedA[i];
      if(InpSelectedRedForHistogram == 2)
         selected = g_RedB[i];
      else if(InpSelectedRedForHistogram == 3)
         selected = g_RedC[i];
      else if(InpSelectedRedForHistogram == 4)
         selected = g_RedD[i];
      else if(InpSelectedRedForHistogram == 5)
         selected = g_Double[i];

      double hist = g_Core[i] - selected;
      g_HistGrey[i] = hist;

      // NEW - Red line traces histogram peaks = selected component
      g_RedLine[i] = selected;

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
