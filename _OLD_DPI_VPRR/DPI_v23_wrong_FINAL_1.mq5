//+------------------------------------------------------------------+
//|                           DPI_v23_FINAL.mq5                      |
//| Based on confirmed TEST-02 logic that was "Partly-OK"            |
//| Key insight: Blue = MACD Core (Fast-Slow), NOT Fast EMA          |
//| Histogram = Core - Selected smoothed red                         |
//| Red/Yellow based on histogram sign                               |
//| Green = ??? (needs observation from MT4 DPI)                     |
//+------------------------------------------------------------------+
#property strict
#property version   "23.00"
#property indicator_separate_window
#property indicator_buffers 4
#property indicator_plots   4

#property indicator_level1 0.0
#property indicator_levelcolor clrSilver
#property indicator_levelstyle STYLE_DOT
#property indicator_levelwidth 1

// Plot 0: Blue line = MACD Core (Fast - Slow)
#property indicator_label1 "Blue_MACD_Core"
#property indicator_type1 DRAW_LINE
#property indicator_color1 clrDodgerBlue
#property indicator_style1 STYLE_SOLID
#property indicator_width1 2

// Plot 1: Red histogram (negative)
#property indicator_label2 "Hist_Red"
#property indicator_type2 DRAW_HISTOGRAM
#property indicator_color2 clrRed
#property indicator_style2 STYLE_SOLID
#property indicator_width2 3

// Plot 2: Yellow histogram (positive)
#property indicator_label3 "Hist_Yellow"
#property indicator_type3 DRAW_HISTOGRAM
#property indicator_color3 clrYellow
#property indicator_style3 STYLE_SOLID
#property indicator_width3 3

// Plot 3: Green histogram (special cases)
#property indicator_label4 "Hist_Green"
#property indicator_type4 DRAW_HISTOGRAM
#property indicator_color4 clrLime
#property indicator_style4 STYLE_SOLID
#property indicator_width4 3

//--- Inputs (exactly from TEST-02)
input int InpFastEMA = 8;
input int InpSlowEMA = 13;
input int InpRedA_EMA = 5;
input int InpRedB_EMA = 8;
input int InpRedC_EMA = 13;
input int InpRedD_EMA = 21;
input int InpDoubleFirst = 5;
input int InpDoubleSecond = 3;
input int InpSelectedRedForHistogram = 3;  // 3 for slow=13, 4 for slow=21

//--- Buffers
double g_Blue[];
double g_HistRed[];
double g_HistYellow[];
double g_HistGreen[];

//--- Working
double g_Fast[];
double g_Slow[];
double g_Core[];
double g_RedA[];
double g_RedB[];
double g_RedC[];
double g_RedD[];
double g_DoubleStage1[];
double g_Double[];

double _alpha(int period)
{
    if(period <= 1) return 1.0;
    return 2.0 / ((double)period + 1.0);
}

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
    ArraySetAsSeries(g_RedA, true);
    ArraySetAsSeries(g_RedB, true);
    ArraySetAsSeries(g_RedC, true);
    ArraySetAsSeries(g_RedD, true);
    ArraySetAsSeries(g_DoubleStage1, true);
    ArraySetAsSeries(g_Double, true);

    PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);
    PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, EMPTY_VALUE);
    PlotIndexSetDouble(3, PLOT_EMPTY_VALUE, EMPTY_VALUE);

    IndicatorSetString(INDICATOR_SHORTNAME, 
        StringFormat("DPI v23 FINAL (%d,%d,sel=%d)", InpFastEMA, InpSlowEMA, InpSelectedRedForHistogram));
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
    int min_bars = InpSlowEMA + MathMax(MathMax(InpRedC_EMA, InpRedD_EMA), 
                                        InpDoubleFirst + InpDoubleSecond) + 5;
    if(rates_total < min_bars) return 0;

    ArraySetAsSeries(close, true);

    ArrayResize(g_Fast, rates_total);
    ArrayResize(g_Slow, rates_total);
    ArrayResize(g_Core, rates_total);
    ArrayResize(g_RedA, rates_total);
    ArrayResize(g_RedB, rates_total);
    ArrayResize(g_RedC, rates_total);
    ArrayResize(g_RedD, rates_total);
    ArrayResize(g_DoubleStage1, rates_total);
    ArrayResize(g_Double, rates_total);

    double aFast = _alpha(InpFastEMA);
    double aSlow = _alpha(InpSlowEMA);
    double aA = _alpha(InpRedA_EMA);
    double aB = _alpha(InpRedB_EMA);
    double aC = _alpha(InpRedC_EMA);
    double aD = _alpha(InpRedD_EMA);
    double aD1 = _alpha(InpDoubleFirst);
    double aD2 = _alpha(InpDoubleSecond);

    int oldest = rates_total - 1;

    g_Fast[oldest] = close[oldest];
    g_Slow[oldest] = close[oldest];
    g_Core[oldest] = 0;
    g_RedA[oldest] = 0;
    g_RedB[oldest] = 0;
    g_RedC[oldest] = 0;
    g_RedD[oldest] = 0;
    g_DoubleStage1[oldest] = 0;
    g_Double[oldest] = 0;
    g_Blue[oldest] = 0;
    g_HistRed[oldest] = EMPTY_VALUE;
    g_HistYellow[oldest] = EMPTY_VALUE;
    g_HistGreen[oldest] = EMPTY_VALUE;

    for(int i = rates_total - 2; i >= 0; i--)
    {
        // Calculate Fast and Slow EMAs (exactly from TEST-02)
        g_Fast[i] = aFast * close[i] + (1.0 - aFast) * g_Fast[i+1];
        g_Slow[i] = aSlow * close[i] + (1.0 - aSlow) * g_Slow[i+1];

        // Blue line = MACD Core (Fast - Slow)
        g_Core[i] = g_Fast[i] - g_Slow[i];
        g_Blue[i] = g_Core[i];

        // Calculate red candidates (smoothed versions of core)
        g_RedA[i] = aA * g_Core[i] + (1.0 - aA) * g_RedA[i+1];
        g_RedB[i] = aB * g_Core[i] + (1.0 - aB) * g_RedB[i+1];
        g_RedC[i] = aC * g_Core[i] + (1.0 - aC) * g_RedC[i+1];
        g_RedD[i] = aD * g_Core[i] + (1.0 - aD) * g_RedD[i+1];

        // Double smooth
        g_DoubleStage1[i] = aD1 * g_Core[i] + (1.0 - aD1) * g_DoubleStage1[i+1];
        g_Double[i] = aD2 * g_DoubleStage1[i] + (1.0 - aD2) * g_Double[i+1];

        // Select red component based on input
        double selected = g_RedA[i];
        if(InpSelectedRedForHistogram == 2)
            selected = g_RedB[i];
        else if(InpSelectedRedForHistogram == 3)
            selected = g_RedC[i];
        else if(InpSelectedRedForHistogram == 4)
            selected = g_RedD[i];
        else if(InpSelectedRedForHistogram == 5)
            selected = g_Double[i];

        // Histogram = Core - Selected (exactly from TEST-02)
        double hist = g_Core[i] - selected;

        // Initialize all histogram buffers
        g_HistRed[i] = EMPTY_VALUE;
        g_HistYellow[i] = EMPTY_VALUE;
        g_HistGreen[i] = EMPTY_VALUE;

        // HYPOTHESIS for green based on MT4 DPI observation:
        // Looking at your screenshot, green appears occasionally
        // Possibly when histogram and core have specific relationship
        
        // For now: Simple red/yellow split (same as TEST-02)
        // We'll refine green logic after you confirm this base works
        
        if(hist >= 0)
        {
            g_HistYellow[i] = hist;
        }
        else
        {
            g_HistRed[i] = hist;
        }

        // Green placeholder - needs your observation
        // Where exactly does green appear in MT4 DPI?
        // Uncomment and adjust based on your findings:
        /*
        // Option 1: Green when histogram is very small
        if(MathAbs(hist) < 0.0001)
            g_HistGreen[i] = hist;
        
        // Option 2: Green at zero crossings
        if(i < rates_total-1 && hist * (g_Core[i+1] - selected_prev) < 0)
            g_HistGreen[i] = hist;
        
        // Option 3: Green when core and selected diverge significantly
        double divergence = g_Core[i] / (selected + 0.00001);
        if(MathAbs(divergence) > 2.0)
            g_HistGreen[i] = hist;
        */
    }

    return rates_total;
}
