//+------------------------------------------------------------------+
//|                           DPI_v22_TEST-04_FixedGreenLogic.mq5    |
//| FIX: Green was drawing everywhere - should be SPARSE             |
//| Green only when specific gap/substitution conditions met         |
//+------------------------------------------------------------------+
#property strict
#property version   "4.00"
#property indicator_separate_window
#property indicator_buffers 4
#property indicator_plots   4

#property indicator_level1 0.0
#property indicator_levelcolor clrSilver
#property indicator_levelstyle STYLE_DOT

// Plot 0: Blue line = Fast EMA
#property indicator_label1 "Blue_FastEMA"
#property indicator_type1 DRAW_LINE
#property indicator_color1 clrDodgerBlue
#property indicator_style1 STYLE_SOLID
#property indicator_width1 2

// Plot 1: Red histogram
#property indicator_label2 "Hist_Red"
#property indicator_type2 DRAW_HISTOGRAM
#property indicator_color2 clrRed
#property indicator_style2 STYLE_SOLID
#property indicator_width2 3

// Plot 2: Yellow histogram
#property indicator_label3 "Hist_Yellow"
#property indicator_type3 DRAW_HISTOGRAM
#property indicator_color3 clrYellow
#property indicator_style3 STYLE_SOLID
#property indicator_width3 3

// Plot 4: Green histogram - SPARSE, not continuous
#property indicator_label4 "Hist_Green"
#property indicator_type4 DRAW_HISTOGRAM
#property indicator_color4 clrLime
#property indicator_style4 STYLE_SOLID
#property indicator_width4 2

//--- Inputs
input int InpFastEMA = 8;
input int InpSlowEMA = 13;
input int InpRedA_EMA = 5;
input int InpRedB_EMA = 8;
input int InpRedC_EMA = 13;
input int InpRedD_EMA = 21;
input int InpDoubleFirst = 5;
input int InpDoubleSecond = 3;
input int InpSelectedRedForHistogram = 3;

//--- Buffers
double g_Blue[];
double g_HistRed[];
double g_HistYellow[];
double g_HistGreen[];

//--- Working
double g_Fast[];
double g_Slow[];
double g_Core[];
double g_SelectedSmooth[];

double _alpha(int p) { return (p <= 1) ? 1.0 : 2.0 / (p + 1.0); }

int OnInit()
{
    SetIndexBuffer(0, g_Blue, INDICATOR_DATA);
    SetIndexBuffer(1, g_HistRed, INDICATOR_DATA);
    SetIndexBuffer(2, g_HistYellow, INDICATOR_DATA);
    SetIndexBuffer(3, g_HistGreen, INDICATOR_DATA);

    ArraySetAsSeries(g_Blue, true);
    ArraySetAsSeries(g_HistRed, true);
    ArraySetAsSeries(g_HistYellow, true);
    ArraySetAsSeries(g_HistGreen, true);
    ArraySetAsSeries(g_Fast, true);
    ArraySetAsSeries(g_Slow, true);
    ArraySetAsSeries(g_Core, true);
    ArraySetAsSeries(g_SelectedSmooth, true);

    PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);
    PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, EMPTY_VALUE);
    PlotIndexSetDouble(3, PLOT_EMPTY_VALUE, EMPTY_VALUE);

    IndicatorSetString(INDICATOR_SHORTNAME, 
        StringFormat("DPI v22 TEST-04 (%d,%d,sel=%d)", InpFastEMA, InpSlowEMA, InpSelectedRedForHistogram));
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
    if(rates_total < 50) return 0;

    ArraySetAsSeries(close, true);
    ArrayResize(g_Fast, rates_total);
    ArrayResize(g_Slow, rates_total);
    ArrayResize(g_Core, rates_total);
    ArrayResize(g_SelectedSmooth, rates_total);

    double aFast = _alpha(InpFastEMA);
    double aSlow = _alpha(InpSlowEMA);

    // Get selected period
    int selPeriod = InpRedC_EMA;
    switch(InpSelectedRedForHistogram)
    {
        case 1: selPeriod = InpRedA_EMA; break;
        case 2: selPeriod = InpRedB_EMA; break;
        case 3: selPeriod = InpRedC_EMA; break;
        case 4: selPeriod = InpRedD_EMA; break;
    }
    double aSel = _alpha(selPeriod);
    double aD1 = _alpha(InpDoubleFirst);
    double aD2 = _alpha(InpDoubleSecond);

    int oldest = rates_total - 1;
    g_Fast[oldest] = close[oldest];
    g_Slow[oldest] = close[oldest];
    g_Core[oldest] = 0;
    g_SelectedSmooth[oldest] = 0;

    double tempStage1[]; 
    ArrayResize(tempStage1, rates_total);
    ArraySetAsSeries(tempStage1, true);
    tempStage1[oldest] = 0;

    for(int i = rates_total - 2; i >= 0; i--)
    {
        // Calculate Fast and Slow EMAs
        g_Fast[i] = aFast * close[i] + (1 - aFast) * g_Fast[i+1];
        g_Slow[i] = aSlow * close[i] + (1 - aSlow) * g_Slow[i+1];
        
        // Core = MACD-like difference
        g_Core[i] = g_Fast[i] - g_Slow[i];

        // Calculate selected smoothed histogram
        double redCandidate = aSel * g_Core[i] + (1 - aSel) * g_SelectedSmooth[i+1];
        
        if(InpSelectedRedForHistogram == 5)
        {
            // Double smooth
            tempStage1[i] = aD1 * g_Core[i] + (1 - aD1) * tempStage1[i+1];
            redCandidate = aD2 * tempStage1[i] + (1 - aD2) * g_SelectedSmooth[i+1];
        }
        
        g_SelectedSmooth[i] = redCandidate;

        // Blue = Fast EMA only (confirmed)
        g_Blue[i] = g_Fast[i];

        // Initialize ALL histograms to EMPTY
        g_HistRed[i] = EMPTY_VALUE;
        g_HistYellow[i] = EMPTY_VALUE;
        g_HistGreen[i] = EMPTY_VALUE;

        double blue = g_Blue[i];
        double hist = redCandidate;

        // CRITICAL FIX: Green should be SPARSE, not everywhere
        // Looking at MT4 DPI: green appears occasionally, not continuously
        
        // Primary histogram color based on sign
        if(hist >= 0)
        {
            // Positive: Yellow histogram
            g_HistYellow[i] = hist;
        }
        else
        {
            // Negative: Red histogram
            g_HistRed[i] = hist;
        }

        // Green logic - MUST be sparse
        // Hypothesis: Green appears only when there's a SIGNIFICANT gap or divergence
        // Not just any difference between blue and histogram
        
        double gap = blue - hist;
        double threshold = MathAbs(hist) * 0.3;  // Gap must be >30% of histogram magnitude
        
        // Only draw green if gap is significant AND meets certain conditions
        if(MathAbs(gap) > threshold && MathAbs(gap) > 0.0001)
        {
            // Additional condition: Check if this represents a real divergence
            // Green in MT4 DPI seems to appear when blue diverges from histogram trend
            
            // Simple approach: green only when gap is substantial
            g_HistGreen[i] = gap;
            
            // When green is drawn, DON'T draw the primary histogram
            // This matches MT4 behavior where green sometimes replaces red/yellow
            if(hist >= 0)
                g_HistYellow[i] = EMPTY_VALUE;
            else
                g_HistRed[i] = EMPTY_VALUE;
        }
    }

    return rates_total;
}
