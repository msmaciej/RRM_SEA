//  SAVE AS UTF-16 LE WITH BOM
//+------------------------------------------------------------------+
//|                         DPI_v29_with_CCI_reset_logic.mq5         |
//|   Purpose: Replicate MT4 DPI indicator with CCI reset logic      |
//|   Version: 29 - Implements CCI(13) histogram color override      |
//|                                                                  |
//|   EVOLUTION:                                                     |
//|   v13 - Base MACD indicator with multiple red line candidates    |
//|   v28 - Added red contour line from v18                          |
//|   v29 - Added CCI(13) reset logic for histogram colors           |
//|                                                                  |
//|   CORE COMPONENTS:                                               |
//|   1. Blue Line (LEAD)    = MACD Core = EMA(8) - EMA(13)         |
//|   2. Red Line (FOLLOW)   = EMA of Blue Line (signal)            |
//|   3. Red Contour         = Histogram outline                     |
//|   4. Histogram           = Blue - Red (difference)               |
//|   5. CCI Filter          = CCI(13, HLC/3) for color resets      |
//|                                                                  |
//|   HISTOGRAM COLOR LOGIC:                                         |
//|   WITHOUT CCI (v28 logic):                                       |
//|     - hist >= 0 → YELLOW                                        |
//|     - hist <  0 → RED                                            |
//|                                                                  |
//|   WITH CCI RESET (v29 logic):                                    |
//|     - hist >= 0 AND CCI >= 0 → YELLOW                           |
//|     - hist >= 0 AND CCI <  0 → RED (reset!)                     |
//|     - hist <  0 AND CCI >= 0 → YELLOW (reset!)                  |
//|     - hist <  0 AND CCI <  0 → RED                              |
//|                                                                  |
//|   The CCI acts as a TREND FILTER that can override the          |
//|   simple above/below zero logic, creating "resets" where        |
//|   histogram color contradicts its position relative to zero.    |
//+------------------------------------------------------------------+
#property strict
#property version   "29.00"
#property indicator_separate_window
#property indicator_buffers 10
#property indicator_plots   10

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

// Plot 1-5: Red line candidates for testing
#property indicator_label2    "Red_EMA_5"
#property indicator_type2     DRAW_LINE
#property indicator_color2    clrRed
#property indicator_style2    STYLE_SOLID
#property indicator_width2    2

#property indicator_label3    "Red_EMA_8"
#property indicator_type3     DRAW_LINE
#property indicator_color3    clrTomato
#property indicator_style3    STYLE_DOT
#property indicator_width3    1

#property indicator_label4    "Red_EMA_13"
#property indicator_type4     DRAW_LINE
#property indicator_color4    clrOrangeRed
#property indicator_style4    STYLE_DASH
#property indicator_width4    1

#property indicator_label5    "Red_EMA_21"
#property indicator_type5     DRAW_LINE
#property indicator_color5    clrMagenta
#property indicator_style5    STYLE_DASHDOT
#property indicator_width5    1

#property indicator_label6    "Red_Double_5_3"
#property indicator_type6     DRAW_LINE
#property indicator_color6    clrWhite
#property indicator_style6    STYLE_DOT
#property indicator_width6    1

// Plot 6: Grey histogram (backup/debug - always shows full histogram)
#property indicator_label7    "Hist_CoreMinusSelected"
#property indicator_type7     DRAW_HISTOGRAM
#property indicator_color7    clrSilver
#property indicator_style7    STYLE_SOLID
#property indicator_width7    2

// Plot 7: Yellow histogram (positive or CCI-filtered)
#property indicator_label8    "Hist_Pos"
#property indicator_type8     DRAW_HISTOGRAM
#property indicator_color8    clrYellow
#property indicator_style8    STYLE_SOLID
#property indicator_width8    3

// Plot 8: Red histogram (negative or CCI-filtered)
#property indicator_label9    "Hist_Neg"
#property indicator_type9     DRAW_HISTOGRAM
#property indicator_color9    clrRed
#property indicator_style9    STYLE_SOLID
#property indicator_width9    3

// Plot 9: Red contour line (follows histogram value)
#property indicator_label10   "Red_Hist_Contour"
#property indicator_type10    DRAW_LINE
#property indicator_color10   clrRed
#property indicator_style10   STYLE_SOLID
#property indicator_width10   2

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                  |
//+------------------------------------------------------------------+

// MACD parameters
input int InpFastEMA  = 8;      // Fast EMA period for MACD core
input int InpSlowEMA  = 13;     // Slow EMA period for MACD core

// Red signal line candidates
input int InpRedA_EMA = 5;      // Red candidate A: EMA period
input int InpRedB_EMA = 8;      // Red candidate B: EMA period
input int InpRedC_EMA = 13;     // Red candidate C: EMA period
input int InpRedD_EMA = 21;     // Red candidate D: EMA period

// Double-smoothed red line
input int InpDoubleFirst  = 5;  // First EMA for double-smooth
input int InpDoubleSecond = 3;  // Second EMA for double-smooth

// Select which red line to use for histogram calculation
// 1=EMA5, 2=EMA8, 3=EMA13, 4=EMA21, 5=Double EMA(5,3)
input int InpSelectedRedForHistogram = 1;  // Selected red line candidate

// CCI RESET LOGIC (v29 feature)
input bool InpEnableCCIReset = true;       // Enable CCI color reset logic
input int  InpCCIPeriod      = 13;         // CCI period for reset logic

//+------------------------------------------------------------------+
//| INDICATOR BUFFERS                                                 |
//+------------------------------------------------------------------+

// Visible plot buffers
double g_Core[];          // Blue MACD core line
double g_RedA[];          // Red candidate A
double g_RedB[];          // Red candidate B
double g_RedC[];          // Red candidate C
double g_RedD[];          // Red candidate D
double g_Double[];        // Double-smoothed candidate
double g_HistGrey[];      // Grey backup histogram
double g_HistPos[];       // Yellow histogram
double g_HistNeg[];       // Red histogram
double g_RedContour[];    // Red contour line

// Internal calculation buffers
double g_Fast[];          // Fast EMA for MACD
double g_Slow[];          // Slow EMA for MACD
double g_DoubleStage1[];  // First stage of double-smooth
double g_CCI[];           // CCI values for reset logic

//+------------------------------------------------------------------+
//| HELPER FUNCTIONS                                                  |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Calculate EMA alpha (smoothing factor)                            |
//| Alpha = 2 / (period + 1)                                         |
//+------------------------------------------------------------------+
double _alpha(const int period)
{
   if(period <= 1)
      return 1.0;
   return 2.0 / ((double)period + 1.0);
}

//+------------------------------------------------------------------+
//| Calculate CCI (Commodity Channel Index)                           |
//| CCI = (TypicalPrice - SMA) / (0.015 * MeanDeviation)            |
//| TypicalPrice = (High + Low + Close) / 3                          |
//+------------------------------------------------------------------+
double CalculateCCI(const int period, const int bar_index,
                    const double &high[], const double &low[], const double &close[])
{
   if(bar_index + period >= ArraySize(high))
      return 0.0;
   
   // Calculate typical prices
   double typical_prices[];
   ArrayResize(typical_prices, period);
   
   double sum = 0.0;
   for(int i = 0; i < period; i++)
   {
      int idx = bar_index + i;
      typical_prices[i] = (high[idx] + low[idx] + close[idx]) / 3.0;
      sum += typical_prices[i];
   }
   
   // Calculate SMA of typical price
   double sma = sum / (double)period;
   
   // Calculate mean deviation
   double mean_deviation = 0.0;
   for(int i = 0; i < period; i++)
   {
      mean_deviation += MathAbs(typical_prices[i] - sma);
   }
   mean_deviation /= (double)period;
   
   // Avoid division by zero
   if(mean_deviation == 0.0)
      return 0.0;
   
   // Calculate CCI
   // Current typical price
   double current_tp = (high[bar_index] + low[bar_index] + close[bar_index]) / 3.0;
   double cci = (current_tp - sma) / (0.015 * mean_deviation);
   
   return cci;
}

//+------------------------------------------------------------------+
//| Indicator initialization function                                 |
//+------------------------------------------------------------------+
int OnInit()
{
   if(InpFastEMA < 1 || InpSlowEMA <= InpFastEMA)
   {
      Print("DPI v29 error: Slow EMA must be > Fast EMA.");
      return INIT_PARAMETERS_INCORRECT;
   }

   // Set index buffers
   SetIndexBuffer(0, g_Core,          INDICATOR_DATA);
   SetIndexBuffer(1, g_RedA,          INDICATOR_DATA);
   SetIndexBuffer(2, g_RedB,          INDICATOR_DATA);
   SetIndexBuffer(3, g_RedC,          INDICATOR_DATA);
   SetIndexBuffer(4, g_RedD,          INDICATOR_DATA);
   SetIndexBuffer(5, g_Double,        INDICATOR_DATA);
   SetIndexBuffer(6, g_HistGrey,      INDICATOR_DATA);
   SetIndexBuffer(7, g_HistPos,       INDICATOR_DATA);
   SetIndexBuffer(8, g_HistNeg,       INDICATOR_DATA);
   SetIndexBuffer(9, g_RedContour,    INDICATOR_DATA);

   // Set arrays as series (newest data at index 0)
   ArraySetAsSeries(g_Core,          true);
   ArraySetAsSeries(g_RedA,          true);
   ArraySetAsSeries(g_RedB,          true);
   ArraySetAsSeries(g_RedC,          true);
   ArraySetAsSeries(g_RedD,          true);
   ArraySetAsSeries(g_Double,        true);
   ArraySetAsSeries(g_HistGrey,      true);
   ArraySetAsSeries(g_HistPos,       true);
   ArraySetAsSeries(g_HistNeg,       true);
   ArraySetAsSeries(g_RedContour,    true);

   ArraySetAsSeries(g_Fast,          true);
   ArraySetAsSeries(g_Slow,          true);
   ArraySetAsSeries(g_DoubleStage1,  true);
   ArraySetAsSeries(g_CCI,           true);

   // Set empty values for histogram plots
   PlotIndexSetDouble(7, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(8, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   // Set indicator name
   string cci_status = InpEnableCCIReset ? " + CCI Reset" : "";
   IndicatorSetString(INDICATOR_SHORTNAME, 
                      "DPI v29 (" + IntegerToString(InpFastEMA) + "," + 
                      IntegerToString(InpSlowEMA) + ")" + cci_status);
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
   // Calculate minimum bars needed
   int min_bars = InpSlowEMA + 
                  MathMax(MathMax(InpRedC_EMA, InpRedD_EMA), 
                          InpDoubleFirst + InpDoubleSecond) + 
                  InpCCIPeriod + 10;
   
   if(rates_total < min_bars)
      return 0;

   // Set price arrays as series
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(high,  true);
   ArraySetAsSeries(low,   true);

   // Resize internal buffers
   ArrayResize(g_Fast,          rates_total);
   ArrayResize(g_Slow,          rates_total);
   ArrayResize(g_DoubleStage1,  rates_total);
   ArrayResize(g_CCI,           rates_total);

   // Calculate EMA smoothing factors
   const double aFast = _alpha(InpFastEMA);
   const double aSlow = _alpha(InpSlowEMA);
   const double aA    = _alpha(InpRedA_EMA);
   const double aB    = _alpha(InpRedB_EMA);
   const double aC    = _alpha(InpRedC_EMA);
   const double aD    = _alpha(InpRedD_EMA);
   const double aD1   = _alpha(InpDoubleFirst);
   const double aD2   = _alpha(InpDoubleSecond);

   // Initialize oldest bar
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
   g_RedContour[oldest] = EMPTY_VALUE;
   g_CCI[oldest] = 0.0;

   //+------------------------------------------------------------------+
   //| MAIN CALCULATION LOOP                                            |
   //+------------------------------------------------------------------+
   for(int i = rates_total - 2; i >= 0; --i)
   {
      //=================================================================
      // STEP 1: Calculate MACD components
      //=================================================================
      
      // Fast and Slow EMAs
      g_Fast[i] = aFast * close[i] + (1.0 - aFast) * g_Fast[i + 1];
      g_Slow[i] = aSlow * close[i] + (1.0 - aSlow) * g_Slow[i + 1];
      
      // Blue MACD core (LEAD line)
      g_Core[i] = g_Fast[i] - g_Slow[i];

      //=================================================================
      // STEP 2: Calculate red signal line candidates
      //=================================================================
      
      // All candidates are EMAs of the blue core
      g_RedA[i] = aA * g_Core[i] + (1.0 - aA) * g_RedA[i + 1];
      g_RedB[i] = aB * g_Core[i] + (1.0 - aB) * g_RedB[i + 1];
      g_RedC[i] = aC * g_Core[i] + (1.0 - aC) * g_RedC[i + 1];
      g_RedD[i] = aD * g_Core[i] + (1.0 - aD) * g_RedD[i + 1];
      
      // Double-smoothed: EMA of EMA
      g_DoubleStage1[i] = aD1 * g_Core[i] + (1.0 - aD1) * g_DoubleStage1[i + 1];
      g_Double[i]       = aD2 * g_DoubleStage1[i] + (1.0 - aD2) * g_Double[i + 1];

      //=================================================================
      // STEP 3: Select which red line to use for histogram
      //=================================================================
      
      double selected = g_RedA[i];  // Default: candidate A
      
      if(InpSelectedRedForHistogram == 2)
         selected = g_RedB[i];
      else if(InpSelectedRedForHistogram == 3)
         selected = g_RedC[i];
      else if(InpSelectedRedForHistogram == 4)
         selected = g_RedD[i];
      else if(InpSelectedRedForHistogram == 5)
         selected = g_Double[i];

      //=================================================================
      // STEP 4: Calculate histogram (Blue - Red)
      //=================================================================
      
      double hist = g_Core[i] - selected;
      
      // Grey histogram always shows the full value (backup)
      g_HistGrey[i] = hist;
      
      // Red contour line follows histogram value
      g_RedContour[i] = hist;

      //=================================================================
      // STEP 5: Calculate CCI for reset logic (v29 feature)
      //=================================================================
      
      if(InpEnableCCIReset)
      {
         g_CCI[i] = CalculateCCI(InpCCIPeriod, i, high, low, close);
      }
      else
      {
         g_CCI[i] = 0.0;  // CCI not used
      }

      //=================================================================
      // STEP 6: Determine histogram color with CCI reset logic
      //=================================================================
      
      // WITHOUT CCI RESET (v28 logic):
      //   hist >= 0 → YELLOW
      //   hist <  0 → RED
      //
      // WITH CCI RESET (v29 logic):
      //   hist >= 0 AND CCI >= 0 → YELLOW
      //   hist >= 0 AND CCI <  0 → RED (reset!)
      //   hist <  0 AND CCI >= 0 → YELLOW (reset!)
      //   hist <  0 AND CCI <  0 → RED
      //
      // The CCI acts as a TREND FILTER that overrides the simple
      // above/below zero logic, creating histogram color "resets"
      // that match the MT4 DPI behavior.
      
      if(hist >= 0.0)
      {
         // Histogram is above zero line
         if(InpEnableCCIReset && g_CCI[i] < 0.0)
         {
            // CCI RESET: Force RED despite being above zero
            g_HistPos[i] = EMPTY_VALUE;
            g_HistNeg[i] = hist;
         }
         else
         {
            // Normal: YELLOW above zero
            g_HistPos[i] = hist;
            g_HistNeg[i] = EMPTY_VALUE;
         }
      }
      else
      {
         // Histogram is below zero line
         if(InpEnableCCIReset && g_CCI[i] >= 0.0)
         {
            // CCI RESET: Force YELLOW despite being below zero
            g_HistPos[i] = hist;
            g_HistNeg[i] = EMPTY_VALUE;
         }
         else
         {
            // Normal: RED below zero
            g_HistPos[i] = EMPTY_VALUE;
            g_HistNeg[i] = hist;
         }
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
// 1. VISUAL ANALYSIS:
//    - Blue line = Trend direction (LEAD)
//    - Red contour = Momentum strength
//    - Yellow histogram = Bullish momentum or CCI bullish override
//    - Red histogram = Bearish momentum or CCI bearish override
//
// 2. TRADING SIGNALS:
//    - Histogram crossing zero = Potential trend change
//    - CCI resets = Counter-trend warnings
//    - Blue-Red convergence = Momentum weakening
//    - Blue-Red divergence = Momentum strengthening
//
// 3. EA INTEGRATION:
//    Use histogram color as trend confirmation:
//    - Market Bias SELL + DPI RED → Signal = 1 (confirm)
//    - Market Bias SELL + DPI YELLOW → Signal = 0 (contradict)
//    - Market Bias BUY + DPI YELLOW → Signal = 1 (confirm)
//    - Market Bias BUY + DPI RED → Signal = 0 (contradict)
//
// 4. PARAMETER TUNING:
//    - InpSelectedRedForHistogram: Test 1-5 to match MT4 DPI
//    - InpEnableCCIReset: Toggle to compare v28 vs v29 logic
//    - InpCCIPeriod: Adjust CCI sensitivity (default 13)
//
// 5. COMPARISON:
//    - v28: Pure histogram (no CCI resets) - cleaner visual
//    - v29: MT4 DPI replica (with CCI resets) - matches original
//
//+------------------------------------------------------------------+
