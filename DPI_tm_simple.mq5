// SAVE AS UTF-16 LE WITH BOM
//+------------------------------------------------------------------+
//| DPI_tm_simple.mq5                                                 |
//| Copied from: Legacy/DPI_Indicator.mq5  (logic unchanged)         |
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
//| Source uses TSI(R,S,U,FastR,FastS) + MACD signal - different math.|
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//|                                             DPI_Indicator.mq5    |
//|              DPI (Dynamic Price Index) - MT5 Implementation      |
//|              Based on William Blau Ergodic / TSI Oscillator      |
//|                                                                  |
//| Reverse-engineered from Russ Horn's dpi.ex4 (MT4 binary).       |
//| Architecture: dual-layer True Strength Index (TSI) oscillator   |
//| with coloured histogram overlay and nested pullback histogram.   |
//+------------------------------------------------------------------+
#property copyright "MJS Institutional Trading Solutions"
#property version   "1.00"
#property strict

#property indicator_separate_window
#property indicator_buffers 6
#property indicator_plots   6

// Reference levels -------------------------------------------------------
#property indicator_level1     0.0       // Zero line
#property indicator_level2     0.00005   // Threshold (overridden in OnInit)
#property indicator_levelcolor clrSilver
#property indicator_levelstyle STYLE_DOT
#property indicator_levelwidth 1

// Plot 0 — Main Line (Red standard TSI line — R=25, S=13 smoothing) -----
#property indicator_label1  "MainLine"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrRed
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

// Plot 1 — Signal Line (Blue MACD Signal = EMA(MACD_Signal, macdLine)) ---
#property indicator_label2  "SignalLine"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrDodgerBlue
#property indicator_style2  STYLE_SOLID
#property indicator_width2  2

// Plot 2 — Bullish Histogram (Yellow — buy zone) -------------------------
#property indicator_label3  "BullHist"
#property indicator_type3   DRAW_HISTOGRAM
#property indicator_color3  clrYellow
#property indicator_style3  STYLE_SOLID
#property indicator_width3  3

// Plot 3 — Bearish Histogram (Red — sell zone) ---------------------------
#property indicator_label4  "BearHist"
#property indicator_type4   DRAW_HISTOGRAM
#property indicator_color4  clrRed
#property indicator_style4  STYLE_SOLID
#property indicator_width4  3

// Plot 4 — Nested Histogram (Lime — pullback / Shark Trade entry signal) -
#property indicator_label5  "NestedHist"
#property indicator_type5   DRAW_HISTOGRAM
#property indicator_color5  clrLime
#property indicator_style5  STYLE_SOLID
#property indicator_width5  1

// Plot 5 — Green Histogram (Green — broad TSI crossover zone; always at mainHist height)
#property indicator_label6  "GreenHist"
#property indicator_type6   DRAW_HISTOGRAM
#property indicator_color6  clrGreen
#property indicator_style6  STYLE_SOLID
#property indicator_width6  3

//--- Input parameters
input int    TSI_R          = 25;       // First EMA period  (slow smoothing)
input int    TSI_S          = 13;       // Second EMA period (medium smoothing)
input int    TSI_U          = 7;        // Signal line EMA period
input int    TSI_FastR      = 8;        // Lead period (original DPI default)
input int    TSI_FastS      = 13;       // Follow period (original DPI default)
input double ThresholdLevel = 0.00005;  // Reference line offset from zero
input int    MACD_Fast      = 8;        // MACD fast EMA period
input int    MACD_Slow      = 13;       // MACD slow EMA period
input int    MACD_Signal    = 5;        // MACD signal EMA period

//--- Indicator output buffers (registered with SetIndexBuffer)
double g_MainLine[];    // Buffer 0: Red   TSI MainLine (R=25, S=13)
double g_SignalLine[];  // Buffer 1: Blue  MACD Signal = EMA(MACD_Signal, macdLine)
double g_HistBull[];    // Buffer 2: Yellow bullish histogram (mainHist>0 AND macdHist>0)
double g_HistBear[];    // Buffer 3: Red   bearish histogram  (mainHist<0 AND macdHist<0)
double g_HistNested[];  // Buffer 4: Lime  nested histogram
double g_HistGreen[];   // Buffer 5: Green broad TSI crossover zone (mainHist sign)

//--- EMA intermediate arrays (global scope — no static locals)
double g_Momentum[];
double g_AbsMomentum[];
double g_EMA1_Mom[];
double g_EMA2_Mom[];
double g_EMA1_Abs[];
double g_EMA2_Abs[];

//--- Fast TSI EMA arrays (for nested histogram — global scope)
double g_FastEMA1_Mom[];
double g_FastEMA2_Mom[];
double g_FastEMA1_Abs[];
double g_FastEMA2_Abs[];

//--- MACD and TSI Signal arrays (global scope — no static locals)
double g_EMA_Fast[];     // EMA(MACD_Fast) of close price
double g_EMA_Slow[];     // EMA(MACD_Slow) of close price
double g_MACDLine[];     // EMA_Fast - EMA_Slow
double g_MACDSig[];      // EMA(MACD_Signal) of MACDLine = MT4 blue line
double g_TSISignal[];    // EMA(TSI_U) of MainLine — internal only, not a buffer

//+------------------------------------------------------------------+
//| Indicator initialization                                          |
//+------------------------------------------------------------------+
int OnInit()
{
   // Validate input periods
   if(TSI_R < 1 || TSI_S < 1 || TSI_U < 1 || TSI_FastR < 1 || TSI_FastS < 1)
   {
      Print("DPI Error: all period inputs must be >= 1");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(MACD_Fast < 1 || MACD_Slow <= MACD_Fast || MACD_Signal < 1)
   {
      Print("DPI Error: MACD_Fast>=1, MACD_Slow>MACD_Fast, MACD_Signal>=1 required");
      return(INIT_PARAMETERS_INCORRECT);
   }

   // Bind indicator buffers to plots
   SetIndexBuffer(0, g_MainLine,   INDICATOR_DATA);
   SetIndexBuffer(1, g_SignalLine, INDICATOR_DATA);
   SetIndexBuffer(2, g_HistBull,   INDICATOR_DATA);
   SetIndexBuffer(3, g_HistBear,   INDICATOR_DATA);
   SetIndexBuffer(4, g_HistNested, INDICATOR_DATA);
   SetIndexBuffer(5, g_HistGreen,  INDICATOR_DATA);

   // Histograms: treat 0.0 as "no bar" (zero-height bar is invisible)
   PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, 0.0);
   PlotIndexSetDouble(3, PLOT_EMPTY_VALUE, 0.0);
   PlotIndexSetDouble(4, PLOT_EMPTY_VALUE, 0.0);
   PlotIndexSetDouble(5, PLOT_EMPTY_VALUE, 0.0);

   // Set indicator buffers as series: index 0 = newest bar
   ArraySetAsSeries(g_MainLine,   true);
   ArraySetAsSeries(g_SignalLine, true);
   ArraySetAsSeries(g_HistBull,   true);
   ArraySetAsSeries(g_HistBear,   true);
   ArraySetAsSeries(g_HistNested, true);
   ArraySetAsSeries(g_HistGreen,  true);

   // Set calculation arrays as series
   ArraySetAsSeries(g_Momentum,     true);
   ArraySetAsSeries(g_AbsMomentum,  true);
   ArraySetAsSeries(g_EMA1_Mom,     true);
   ArraySetAsSeries(g_EMA2_Mom,     true);
   ArraySetAsSeries(g_EMA1_Abs,     true);
   ArraySetAsSeries(g_EMA2_Abs,     true);
   ArraySetAsSeries(g_FastEMA1_Mom, true);
   ArraySetAsSeries(g_FastEMA2_Mom, true);
   ArraySetAsSeries(g_FastEMA1_Abs, true);
   ArraySetAsSeries(g_FastEMA2_Abs, true);
   ArraySetAsSeries(g_EMA_Fast,     true);
   ArraySetAsSeries(g_EMA_Slow,     true);
   ArraySetAsSeries(g_MACDLine,     true);
   ArraySetAsSeries(g_MACDSig,      true);
   ArraySetAsSeries(g_TSISignal,    true);

   // Display name (header reads "DPI [values…]")
   IndicatorSetString(INDICATOR_SHORTNAME, "DPI");
   IndicatorSetInteger(INDICATOR_DIGITS, 6);

   // Level 0 — zero line: silver dotted
   IndicatorSetDouble(INDICATOR_LEVELVALUE,  0, 0.0);
   IndicatorSetInteger(INDICATOR_LEVELCOLOR, 0, clrSilver);
   IndicatorSetInteger(INDICATOR_LEVELSTYLE, 0, STYLE_DOT);
   IndicatorSetInteger(INDICATOR_LEVELWIDTH, 0, 1);

   // Level 1 — threshold: lime green dotted (user-configurable offset)
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
   // Need at least (R + S + U + MACD_Slow + MACD_Signal + 2) bars for all EMA chains
   // to produce meaningful values, plus 1 seed bar and 1 safety margin.
   if(rates_total < TSI_R + TSI_S + TSI_U + MACD_Slow + MACD_Signal + 2)
      return(0);

   // Align close[] to series ordering: index 0 = newest bar
   ArraySetAsSeries(close, true);

   // Resize calculation arrays to match history length.
   // ArraySetAsSeries flag is preserved across resize calls.
   ArrayResize(g_Momentum,     rates_total);
   ArrayResize(g_AbsMomentum,  rates_total);
   ArrayResize(g_EMA1_Mom,     rates_total);
   ArrayResize(g_EMA2_Mom,     rates_total);
   ArrayResize(g_EMA1_Abs,     rates_total);
   ArrayResize(g_EMA2_Abs,     rates_total);
   ArrayResize(g_FastEMA1_Mom, rates_total);
   ArrayResize(g_FastEMA2_Mom, rates_total);
   ArrayResize(g_FastEMA1_Abs, rates_total);
   ArrayResize(g_FastEMA2_Abs, rates_total);
   ArrayResize(g_EMA_Fast,     rates_total);
   ArrayResize(g_EMA_Slow,     rates_total);
   ArrayResize(g_MACDLine,     rates_total);
   ArrayResize(g_MACDSig,      rates_total);
   ArrayResize(g_TSISignal,    rates_total);

   // Pre-compute EMA smoothing multipliers
   double alphaR       = 2.0 / (double)(TSI_R     + 1);
   double alphaS       = 2.0 / (double)(TSI_S     + 1);
   double alphaU       = 2.0 / (double)(TSI_U     + 1);
   double alphaFastR   = 2.0 / (double)(TSI_FastR + 1);
   double alphaFastS   = 2.0 / (double)(TSI_FastS + 1);
   double alphaFast    = 2.0 / (double)(MACD_Fast   + 1);
   double alphaSlow    = 2.0 / (double)(MACD_Slow   + 1);
   double alphaMACDSig = 2.0 / (double)(MACD_Signal + 1);

   // With series=true: index (rates_total-1) = oldest bar, index 0 = newest bar.
   // Seed all arrays at the oldest bar (no prior close available for momentum).
   int oldest = rates_total - 1;
   g_Momentum[oldest]     = 0.0;
   g_AbsMomentum[oldest]  = 0.0;
   g_EMA1_Mom[oldest]     = 0.0;
   g_EMA2_Mom[oldest]     = 0.0;
   g_EMA1_Abs[oldest]     = 0.0;
   g_EMA2_Abs[oldest]     = 0.0;
   g_MainLine[oldest]     = 0.0;
   g_SignalLine[oldest]   = 0.0;
   g_HistBull[oldest]     = 0.0;
   g_HistBear[oldest]     = 0.0;
   g_HistNested[oldest]   = 0.0;
   g_HistGreen[oldest]    = 0.0;
   g_FastEMA1_Mom[oldest] = 0.0;
   g_FastEMA2_Mom[oldest] = 0.0;
   g_FastEMA1_Abs[oldest] = 0.0;
   g_FastEMA2_Abs[oldest] = 0.0;
   g_EMA_Fast[oldest]     = 0.0;
   g_EMA_Slow[oldest]     = 0.0;
   g_MACDLine[oldest]     = 0.0;
   g_MACDSig[oldest]      = 0.0;
   g_TSISignal[oldest]    = 0.0;

   // Full recalculation: loop from second-oldest bar (rates_total-2) down
   // to bar 0 (newest).  This goes "oldest → newest" in time-series terms.
   // EMA formula:  EMA[i] = alpha * src[i]  +  (1-alpha) * EMA[i+1]
   // where i+1 is always the older bar (higher index with series=true).
   for(int i = rates_total - 2; i >= 0; i--)
   {
      // ------------------------------------------------------------------
      // Step 1: Momentum = close-to-close change
      // ------------------------------------------------------------------
      g_Momentum[i]    = close[i] - close[i + 1];
      g_AbsMomentum[i] = MathAbs(g_Momentum[i]);

      // ------------------------------------------------------------------
      // Step 2: Main TSI — double EMA smoothing (R-period then S-period)
      // ------------------------------------------------------------------
      g_EMA1_Mom[i] = alphaR * g_Momentum[i]    + (1.0 - alphaR) * g_EMA1_Mom[i + 1];
      g_EMA1_Abs[i] = alphaR * g_AbsMomentum[i] + (1.0 - alphaR) * g_EMA1_Abs[i + 1];

      g_EMA2_Mom[i] = alphaS * g_EMA1_Mom[i]    + (1.0 - alphaS) * g_EMA2_Mom[i + 1];
      g_EMA2_Abs[i] = alphaS * g_EMA1_Abs[i]    + (1.0 - alphaS) * g_EMA2_Abs[i + 1];

      // Main Line = TSI ratio  (guard against division by zero)
      double mainLine = 0.0;
      if(g_EMA2_Abs[i] != 0.0)
         mainLine = g_EMA2_Mom[i] / g_EMA2_Abs[i];
      g_MainLine[i] = mainLine;

      // ------------------------------------------------------------------
      // Step 3: TSI Signal Line — internal only for mainHist computation.
      //         NOT stored in g_SignalLine[] buffer (that now holds MACD Signal).
      // ------------------------------------------------------------------
      g_TSISignal[i] = alphaU * mainLine + (1.0 - alphaU) * g_TSISignal[i + 1];

      // ------------------------------------------------------------------
      // Step 4: Fast TSI — double EMA smoothing (FastR then FastS)
      // ------------------------------------------------------------------
      g_FastEMA1_Mom[i] = alphaFastR * g_Momentum[i]       + (1.0 - alphaFastR) * g_FastEMA1_Mom[i + 1];
      g_FastEMA1_Abs[i] = alphaFastR * g_AbsMomentum[i]    + (1.0 - alphaFastR) * g_FastEMA1_Abs[i + 1];
      g_FastEMA2_Mom[i] = alphaFastS * g_FastEMA1_Mom[i]   + (1.0 - alphaFastS) * g_FastEMA2_Mom[i + 1];
      g_FastEMA2_Abs[i] = alphaFastS * g_FastEMA1_Abs[i]   + (1.0 - alphaFastS) * g_FastEMA2_Abs[i + 1];
      double fastLine = 0.0;
      if(g_FastEMA2_Abs[i] != 0.0)
         fastLine = g_FastEMA2_Mom[i] / g_FastEMA2_Abs[i];

      // ------------------------------------------------------------------
      // Step 5: MACD computation (price EMA differential)
      //   macdLine = EMA(MACD_Fast, close) - EMA(MACD_Slow, close)
      //   macdSig  = EMA(MACD_Signal, macdLine)  <- MT4 DPI blue line
      //   macdHist = macdLine - macdSig
      // Blue line buffer = MACD Signal (replaces EMA-of-TSI display)
      // ------------------------------------------------------------------
      g_EMA_Fast[i]  = alphaFast    * close[i]       + (1.0 - alphaFast)    * g_EMA_Fast[i + 1];
      g_EMA_Slow[i]  = alphaSlow    * close[i]       + (1.0 - alphaSlow)    * g_EMA_Slow[i + 1];
      g_MACDLine[i]  = g_EMA_Fast[i] - g_EMA_Slow[i];
      g_MACDSig[i]   = alphaMACDSig * g_MACDLine[i] + (1.0 - alphaMACDSig) * g_MACDSig[i + 1];
      double macdHist = g_MACDLine[i] - g_MACDSig[i];

      // Store MACD Signal as the displayed blue line
      g_SignalLine[i] = g_MACDSig[i];

      // ------------------------------------------------------------------
      // Step 6: TSI crossover differential (mainHist) — gate for all histograms
      // ------------------------------------------------------------------
      double mainHist = mainLine - g_TSISignal[i];

      // ------------------------------------------------------------------
      // Step 7: Green histogram = broad TSI crossover zone (always at mainHist
      //         height regardless of MACD — this is the MT4 DPI green equivalent)
      // ------------------------------------------------------------------
      // GREEN = "broad TSI zone" — only where yellow/red are NOT drawn.
      // Yellow/red are drawn when (mainHist & macdHist) agree in sign;
      // elsewhere (TSI/MACD disagree) green fills the gap at mainHist height.
      bool tsi_macd_agree = (mainHist >= 0.0 && macdHist >= 0.0) ||
                            (mainHist <  0.0 && macdHist <  0.0);

      if(mainHist != 0.0 && !tsi_macd_agree)
         g_HistGreen[i] = mainHist;
      else
         g_HistGreen[i] = 0.0;

      // ------------------------------------------------------------------
      // Step 8: Yellow/Red = TSI crossover AND MACD histogram agree (intersection)
      //   Yellow when mainHist >= 0 AND macdHist >= 0 → draw at mainHist height
      //   Red    when mainHist <  0 AND macdHist <  0 → draw at mainHist height
      //   TSI/MACD disagree → no yellow or red bar (transition/divergence zone)
      // ------------------------------------------------------------------
      if(mainHist >= 0.0 && macdHist >= 0.0)
      {
         g_HistBull[i] = mainHist;
         g_HistBear[i] = 0.0;
      }
      else if(mainHist < 0.0 && macdHist < 0.0)
      {
         g_HistBull[i] = 0.0;
         g_HistBear[i] = mainHist;
      }
      else
      {
         // TSI and MACD disagree — no yellow or red bar
         g_HistBull[i] = 0.0;
         g_HistBear[i] = 0.0;
      }

      // ------------------------------------------------------------------
      // Step 9: Lime nested = v2 gate (mainHist, not mainLine)
      //   Pullback entry trigger: shown when |fastLine - mainLine| < |mainHist|
      // ------------------------------------------------------------------
      double nestedHist = fastLine - mainLine;
      if(mainHist != 0.0 && MathAbs(nestedHist) < MathAbs(mainHist))
         g_HistNested[i] = nestedHist;
      else
         g_HistNested[i] = 0.0;
   }

   return(rates_total);
}
