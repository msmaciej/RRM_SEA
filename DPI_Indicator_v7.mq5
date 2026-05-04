// SAVE AS UTF-16 LE WITH BOM
//+------------------------------------------------------------------+
//|                                          DPI_Indicator_v7.mq5    |
//|              DPI (Dynamic Price Index) - MT5 Implementation      |
//|              Based on William Blau Ergodic / TSI Oscillator      |
//|                                                                  |
//| Reverse-engineered from Russ Horn's dpi.ex4 (MT4 binary).       |
//| Architecture: dual-layer True Strength Index (TSI) oscillator   |
//| with coloured histogram overlay and nested pullback histogram.   |
//|                                                                  |
//| v7 vs v6: SignalLine restored to EMA(TSI_U, MainLine) — pure    |
//| TSI signal — removing the v6 MACD-based blue line entirely.     |
//| Yellow/Red histograms are pure TSI crossover (no MACD gating).  |
//| GreenHist (Plot 5) retained: mainHist height, always drawn.     |
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

// Plot 0 — Main Line (Red — slow double-EMA chain of momentum R=25, S=13)
#property indicator_label1  "MainLine"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrRed
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

// Plot 1 — Signal Line (DodgerBlue — EMA(U=7) of MainLine — pure TSI signal)
#property indicator_label2  "SignalLine"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrDodgerBlue
#property indicator_style2  STYLE_SOLID
#property indicator_width2  2

// Plot 2 — Bullish Histogram (Yellow — buy zone: MainHist >= 0)
#property indicator_label3  "BullHist"
#property indicator_type3   DRAW_HISTOGRAM
#property indicator_color3  clrYellow
#property indicator_style3  STYLE_SOLID
#property indicator_width3  3

// Plot 3 — Bearish Histogram (Red — sell zone: MainHist < 0)
#property indicator_label4  "BearHist"
#property indicator_type4   DRAW_HISTOGRAM
#property indicator_color4  clrRed
#property indicator_style4  STYLE_SOLID
#property indicator_width4  3

// Plot 4 — Nested Histogram (Lime — pullback / Shark Trade entry signal)
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
input int    TSI_U          = 7;        // Signal line EMA period (EMA of MainLine)
input int    TSI_FastR      = 8;        // Nested fast first  EMA period (Lead, original DPI default)
input int    TSI_FastS      = 13;       // Nested fast second EMA period (Follow, original DPI default)
input double ThresholdLevel = 0.00005;  // Reference line offset from zero

//--- Indicator output buffers (registered with SetIndexBuffer)
double g_MainLine[];    // Buffer 0: Red   TSI MainLine (R=25, S=13 double EMA of momentum)
double g_SignalLine[];  // Buffer 1: Blue  Signal line = EMA(TSI_U, MainLine) — pure TSI signal
double g_HistBull[];    // Buffer 2: Yellow bullish histogram (mainHist >= 0)
double g_HistBear[];    // Buffer 3: Red   bearish histogram  (mainHist <  0)
double g_HistNested[];  // Buffer 4: Lime  nested pullback histogram
double g_HistGreen[];   // Buffer 5: Green broad TSI crossover zone (mainHist height, always drawn)

//--- EMA intermediate arrays (global scope — no static locals)
double g_Momentum[];
double g_AbsMomentum[];
double g_EMA1_Mom[];      // EMA(R) of momentum
double g_EMA2_Mom[];      // EMA(S, EMA1_Mom)
double g_EMA1_Abs[];      // EMA(R) of |momentum|
double g_EMA2_Abs[];      // EMA(S, EMA1_Abs)

//--- Fast TSI EMA arrays (for nested histogram)
double g_FastEMA1_Mom[];  // EMA(FastR) of momentum
double g_FastEMA2_Mom[];  // EMA(FastS, FastEMA1_Mom)
double g_FastEMA1_Abs[];  // EMA(FastR) of |momentum|
double g_FastEMA2_Abs[];  // EMA(FastS, FastEMA1_Abs)

//+------------------------------------------------------------------+
//| Indicator initialization                                          |
//+------------------------------------------------------------------+
int OnInit()
{
   if(TSI_R < 1 || TSI_S < 1 || TSI_U < 1 || TSI_FastR < 1 || TSI_FastS < 1)
   {
      Print("DPI Error: all period inputs must be >= 1");
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
   // Need at least (R + S + U + 2) bars for full EMA warm-up
   if(rates_total < TSI_R + TSI_S + TSI_U + 2)
      return(0);

   // Align close[] to series ordering: index 0 = newest bar
   ArraySetAsSeries(close, true);

   // Resize calculation arrays to match history length
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

   // Pre-compute EMA smoothing multipliers
   double alphaR     = 2.0 / (double)(TSI_R     + 1);
   double alphaS     = 2.0 / (double)(TSI_S     + 1);
   double alphaU     = 2.0 / (double)(TSI_U     + 1);
   double alphaFastR = 2.0 / (double)(TSI_FastR + 1);
   double alphaFastS = 2.0 / (double)(TSI_FastS + 1);

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
      //   MainLine = EMA(S, EMA(R, momentum)) / EMA(S, EMA(R, |momentum|))
      //   Normalized ratio in range [-1, +1]
      // ------------------------------------------------------------------
      g_EMA1_Mom[i] = alphaR * g_Momentum[i]    + (1.0 - alphaR) * g_EMA1_Mom[i + 1];
      g_EMA1_Abs[i] = alphaR * g_AbsMomentum[i] + (1.0 - alphaR) * g_EMA1_Abs[i + 1];

      g_EMA2_Mom[i] = alphaS * g_EMA1_Mom[i]    + (1.0 - alphaS) * g_EMA2_Mom[i + 1];
      g_EMA2_Abs[i] = alphaS * g_EMA1_Abs[i]    + (1.0 - alphaS) * g_EMA2_Abs[i + 1];

      double mainLine = 0.0;
      if(g_EMA2_Abs[i] != 0.0)
         mainLine = g_EMA2_Mom[i] / g_EMA2_Abs[i];
      g_MainLine[i] = mainLine;

      // ------------------------------------------------------------------
      // Step 3: Signal Line = EMA(TSI_U) of MainLine — pure TSI signal
      //   This is the correct v2 architecture (NOT MACD-based like v6)
      // ------------------------------------------------------------------
      g_SignalLine[i] = alphaU * mainLine + (1.0 - alphaU) * g_SignalLine[i + 1];

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
      // Step 5: Main Histogram = MainLine - SignalLine
      //   Yellow (BullHist) when >= 0 → buy confirmation
      //   Red    (BearHist) when  < 0 → sell confirmation
      //   Pure TSI crossover — no MACD gating (unlike v6)
      // ------------------------------------------------------------------
      double mainHist = mainLine - g_SignalLine[i];
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
      // Step 6: Nested Histogram = FastLine - MainLine
      //   Shown only when |nested| < |main| → visually nested inside main bars.
      //   This is the Shark Trade / pullback entry trigger.
      // ------------------------------------------------------------------
      double nestedHist = fastLine - mainLine;
      if(mainHist != 0.0 && MathAbs(nestedHist) < MathAbs(mainHist))
         g_HistNested[i] = nestedHist;
      else
         g_HistNested[i] = 0.0;

      // ------------------------------------------------------------------
      // Step 7: Green Histogram = broad TSI crossover zone
      //   Always drawn at mainHist height when mainHist != 0.
      //   No secondary condition (no MACD agreement required).
      // ------------------------------------------------------------------
      g_HistGreen[i] = (mainHist != 0.0) ? mainHist : 0.0;
   }

   return(rates_total);
}
