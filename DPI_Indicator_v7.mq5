// SAVE AS UTF-16 LE WITH BOM
//+------------------------------------------------------------------+
//|                                          DPI_Indicator_v7.mq5   |
//|              DPI (Dynamic Price Index) - MT5 Implementation      |
//|              Full MACD Architecture — correct reverse-eng        |
//|                                                                  |
//| Red  line  = MACD line   = EMA(Fast,close) − EMA(Slow,close)   |
//| Blue line  = MACD signal = EMA(Signal, red_line)                |
//| Histogram  = red − blue  (MACD histogram, split by sign)        |
//| Green hist = mainHist always (broad crossover zone)             |
//| Lime  hist = nested fast MACD differential (pullback trigger)   |
//+------------------------------------------------------------------+
#property copyright "MJS Institutional Trading Solutions"
#property version   "1.00"
#property strict

#property indicator_separate_window
#property indicator_buffers 6
#property indicator_plots   6

// Reference levels -------------------------------------------------------
#property indicator_level1     0.0
#property indicator_level2     0.00005
#property indicator_levelcolor clrSilver
#property indicator_levelstyle STYLE_DOT
#property indicator_levelwidth 1

// Plot 0 — Main Line (Red — MACD line = EMA(Fast,close) − EMA(Slow,close))
#property indicator_label1  "MainLine"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrRed
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

// Plot 1 — Signal Line (Blue — MACD signal = EMA(Signal, MainLine))
#property indicator_label2  "SignalLine"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrDodgerBlue
#property indicator_style2  STYLE_SOLID
#property indicator_width2  2

// Plot 2 — Bullish Histogram (Yellow — mainHist >= 0)
#property indicator_label3  "BullHist"
#property indicator_type3   DRAW_HISTOGRAM
#property indicator_color3  clrYellow
#property indicator_style3  STYLE_SOLID
#property indicator_width3  3

// Plot 3 — Bearish Histogram (Red — mainHist < 0)
#property indicator_label4  "BearHist"
#property indicator_type4   DRAW_HISTOGRAM
#property indicator_color4  clrRed
#property indicator_style4  STYLE_SOLID
#property indicator_width4  3

// Plot 4 — Nested Histogram (Lime — pullback trigger)
#property indicator_label5  "NestedHist"
#property indicator_type5   DRAW_HISTOGRAM
#property indicator_color5  clrLime
#property indicator_style5  STYLE_SOLID
#property indicator_width5  1

// Plot 5 — Green Histogram (Green — mainHist always, broad crossover zone)
#property indicator_label6  "GreenHist"
#property indicator_type6   DRAW_HISTOGRAM
#property indicator_color6  clrGreen
#property indicator_style6  STYLE_SOLID
#property indicator_width6  3

//--- Input parameters
input int    MACD_Fast      = 8;        // MACD fast EMA period (red line fast component)
input int    MACD_Slow      = 13;       // MACD slow EMA period (red line slow component)
input int    MACD_Signal    = 5;        // MACD signal EMA period (blue line smoothing)
input int    Nested_Fast    = 3;        // Nested fast EMA period (lime histogram fast)
input int    Nested_Slow    = 5;        // Nested slow EMA period (lime histogram slow)
input double ThresholdLevel = 0.00005;  // Reference line offset from zero

//--- Indicator output buffers (registered with SetIndexBuffer)
double g_MainLine[];    // Buffer 0: Red   MACD line   = EMA(Fast,close) - EMA(Slow,close)
double g_SignalLine[];  // Buffer 1: Blue  MACD signal = EMA(Signal, MainLine)
double g_HistBull[];    // Buffer 2: Yellow bullish histogram (mainHist >= 0)
double g_HistBear[];    // Buffer 3: Red   bearish histogram  (mainHist <  0)
double g_HistNested[];  // Buffer 4: Lime  nested fast MACD differential (pullback trigger)
double g_HistGreen[];   // Buffer 5: Green broad crossover zone (mainHist always)

//--- EMA intermediate calculation arrays (global scope — no static locals)
double g_EMA_Fast[];      // EMA(MACD_Fast) of close
double g_EMA_Slow[];      // EMA(MACD_Slow) of close
double g_MACDSig[];       // EMA(MACD_Signal) of MainLine
double g_Nest_EMA_Fast[]; // EMA(Nested_Fast) of close
double g_Nest_EMA_Slow[]; // EMA(Nested_Slow) of close

//+------------------------------------------------------------------+
//| Indicator initialization                                          |
//+------------------------------------------------------------------+
int OnInit()
{
   if(MACD_Fast < 1)
   {
      Print("DPI v7 Error: MACD_Fast must be >= 1");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(MACD_Slow <= MACD_Fast)
   {
      Print("DPI v7 Error: MACD_Slow must be > MACD_Fast");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(MACD_Signal < 1)
   {
      Print("DPI v7 Error: MACD_Signal must be >= 1");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(Nested_Fast < 1)
   {
      Print("DPI v7 Error: Nested_Fast must be >= 1");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(Nested_Slow <= Nested_Fast)
   {
      Print("DPI v7 Error: Nested_Slow must be > Nested_Fast");
      return(INIT_PARAMETERS_INCORRECT);
   }

   // Bind indicator buffers to plots
   SetIndexBuffer(0, g_MainLine,   INDICATOR_DATA);
   SetIndexBuffer(1, g_SignalLine, INDICATOR_DATA);
   SetIndexBuffer(2, g_HistBull,   INDICATOR_DATA);
   SetIndexBuffer(3, g_HistBear,   INDICATOR_DATA);
   SetIndexBuffer(4, g_HistNested, INDICATOR_DATA);
   SetIndexBuffer(5, g_HistGreen,  INDICATOR_DATA);

   // Histograms: treat 0.0 as "no bar"
   PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, 0.0);
   PlotIndexSetDouble(3, PLOT_EMPTY_VALUE, 0.0);
   PlotIndexSetDouble(4, PLOT_EMPTY_VALUE, 0.0);
   PlotIndexSetDouble(5, PLOT_EMPTY_VALUE, 0.0);

   // All output buffers as series (index 0 = newest bar)
   ArraySetAsSeries(g_MainLine,   true);
   ArraySetAsSeries(g_SignalLine, true);
   ArraySetAsSeries(g_HistBull,   true);
   ArraySetAsSeries(g_HistBear,   true);
   ArraySetAsSeries(g_HistNested, true);
   ArraySetAsSeries(g_HistGreen,  true);

   // All calculation arrays as series
   ArraySetAsSeries(g_EMA_Fast,      true);
   ArraySetAsSeries(g_EMA_Slow,      true);
   ArraySetAsSeries(g_MACDSig,       true);
   ArraySetAsSeries(g_Nest_EMA_Fast, true);
   ArraySetAsSeries(g_Nest_EMA_Slow, true);

   IndicatorSetString(INDICATOR_SHORTNAME, "DPI");
   IndicatorSetInteger(INDICATOR_DIGITS, 6);

   // Level 0 — zero line: silver dotted
   IndicatorSetDouble(INDICATOR_LEVELVALUE,  0, 0.0);
   IndicatorSetInteger(INDICATOR_LEVELCOLOR, 0, clrSilver);
   IndicatorSetInteger(INDICATOR_LEVELSTYLE, 0, STYLE_DOT);
   IndicatorSetInteger(INDICATOR_LEVELWIDTH, 0, 1);

   // Level 1 — threshold: lime dotted
   IndicatorSetDouble(INDICATOR_LEVELVALUE,  1, ThresholdLevel);
   IndicatorSetInteger(INDICATOR_LEVELCOLOR, 1, clrLime);
   IndicatorSetInteger(INDICATOR_LEVELSTYLE, 1, STYLE_DOT);
   IndicatorSetInteger(INDICATOR_LEVELWIDTH, 1, 1);

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Indicator calculation                                             |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double   &open[],
                const double   &high[],
                const double   &low[],
                const double   &close[],
                const long     &tick_volume[],
                const long     &volume[],
                const int      &spread[])
{
   // Need at least MACD_Slow + MACD_Signal + 2 bars for meaningful output
   if(rates_total < MACD_Slow + MACD_Signal + 2)
      return(0);

   // Align close[] to series ordering: index 0 = newest bar
   ArraySetAsSeries(close, true);

   // Resize all calculation arrays to match history length
   ArrayResize(g_EMA_Fast,      rates_total);
   ArrayResize(g_EMA_Slow,      rates_total);
   ArrayResize(g_MACDSig,       rates_total);
   ArrayResize(g_Nest_EMA_Fast, rates_total);
   ArrayResize(g_Nest_EMA_Slow, rates_total);

   // Pre-compute EMA smoothing multipliers
   double alphaFast  = 2.0 / (double)(MACD_Fast   + 1);
   double alphaSlow  = 2.0 / (double)(MACD_Slow   + 1);
   double alphaSig   = 2.0 / (double)(MACD_Signal + 1);
   double alphaNFast = 2.0 / (double)(Nested_Fast  + 1);
   double alphaNSlow = 2.0 / (double)(Nested_Slow  + 1);

   // Seed all arrays at the oldest bar (index = rates_total-1 with series=true)
   int oldest = rates_total - 1;
   g_EMA_Fast[oldest]      = close[oldest];
   g_EMA_Slow[oldest]      = close[oldest];
   g_MACDSig[oldest]       = 0.0;
   g_Nest_EMA_Fast[oldest] = close[oldest];
   g_Nest_EMA_Slow[oldest] = close[oldest];
   g_MainLine[oldest]      = 0.0;
   g_SignalLine[oldest]    = 0.0;
   g_HistBull[oldest]      = 0.0;
   g_HistBear[oldest]      = 0.0;
   g_HistNested[oldest]    = 0.0;
   g_HistGreen[oldest]     = 0.0;

   // Loop oldest→newest (high index → low index with series=true)
   // EMA formula: EMA[i] = alpha*src[i] + (1-alpha)*EMA[i+1]
   for(int i = rates_total - 2; i >= 0; i--)
   {
      // ------------------------------------------------------------------
      // Step 1: MACD lines
      //   EMA(Fast) and EMA(Slow) of close price
      //   MainLine = EMA(Fast) - EMA(Slow)  ← MACD line, price-domain scale
      // ------------------------------------------------------------------
      g_EMA_Fast[i] = alphaFast * close[i] + (1.0 - alphaFast) * g_EMA_Fast[i + 1];
      g_EMA_Slow[i] = alphaSlow * close[i] + (1.0 - alphaSlow) * g_EMA_Slow[i + 1];
      double mainLine = g_EMA_Fast[i] - g_EMA_Slow[i];
      g_MainLine[i] = mainLine;

      // ------------------------------------------------------------------
      // Step 2: MACD Signal line (blue)
      //   SignalLine = EMA(Signal) of MainLine
      // ------------------------------------------------------------------
      g_MACDSig[i]    = alphaSig * mainLine + (1.0 - alphaSig) * g_MACDSig[i + 1];
      g_SignalLine[i] = g_MACDSig[i];

      // ------------------------------------------------------------------
      // Step 3: Main histogram = MainLine - SignalLine
      // ------------------------------------------------------------------
      double mainHist = mainLine - g_MACDSig[i];

      // ------------------------------------------------------------------
      // Step 4: Green histogram (broad crossover zone — mainHist always)
      // ------------------------------------------------------------------
      g_HistGreen[i] = (mainHist != 0.0) ? mainHist : 0.0;

      // ------------------------------------------------------------------
      // Step 5: Yellow/Red histograms (split by sign)
      //   Yellow (BullHist) when mainHist >= 0 → buy confirmation
      //   Red    (BearHist) when mainHist  < 0 → sell confirmation
      // ------------------------------------------------------------------
      if(mainHist >= 0.0)
      {
         g_HistBull[i] = mainHist;
         g_HistBear[i] = 0.0;
      }
      else
      {
         g_HistBull[i] = 0.0;
         g_HistBear[i] = mainHist;
      }

      // ------------------------------------------------------------------
      // Step 6: Nested fast histogram (lime — pullback trigger)
      //   Nested EMAs of close (not momentum), differential vs MainLine
      //   Shown only when |nestedHist| < |mainHist| (visually nested inside main bars)
      // ------------------------------------------------------------------
      g_Nest_EMA_Fast[i] = alphaNFast * close[i] + (1.0 - alphaNFast) * g_Nest_EMA_Fast[i + 1];
      g_Nest_EMA_Slow[i] = alphaNSlow * close[i] + (1.0 - alphaNSlow) * g_Nest_EMA_Slow[i + 1];
      double fastLine   = g_Nest_EMA_Fast[i] - g_Nest_EMA_Slow[i];
      double nestedHist = fastLine - mainLine;
      if(mainHist != 0.0 && MathAbs(nestedHist) < MathAbs(mainHist))
         g_HistNested[i] = nestedHist;
      else
         g_HistNested[i] = 0.0;
   }

   return(rates_total);
}
