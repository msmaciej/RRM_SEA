//+------------------------------------------------------------------+
//|                    DPI_v22_TEST-04c_TEST02Logic.mq5              |
//| Exactly TEST-02 histogram logic, but Blue = Fast EMA not Core    |
//| This should match since you said TEST-02 looked close            |
//+------------------------------------------------------------------+
#property strict
#property version   "4.02"
#property indicator_separate_window
#property indicator_buffers 3
#property indicator_plots   3

#property indicator_level1 0.0
#property indicator_levelcolor clrSilver
#property indicator_levelstyle STYLE_DOT

// Plot 0: Blue line = Fast EMA (CHANGED from TEST-02)
#property indicator_label1 "Blue_FastEMA"
#property indicator_type1 DRAW_LINE
#property indicator_color1 clrDodgerBlue
#property indicator_style1 STYLE_SOLID
#property indicator_width1 2

// Plot 1: Yellow histogram (positive, SAME as TEST-02)
#property indicator_label2 "Hist_Pos"
#property indicator_type2 DRAW_HISTOGRAM
#property indicator_color2 clrYellow
#property indicator_style2 STYLE_SOLID
#property indicator_width2 3

// Plot 2: Red histogram (negative, SAME as TEST-02)
#property indicator_label3 "Hist_Neg"
#property indicator_type3 DRAW_HISTOGRAM
#property indicator_color3 clrRed
#property indicator_style3 STYLE_SOLID
#property indicator_width3 3

//--- Inputs (SAME as TEST-02)
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
double g_HistPos[];
double g_HistNeg[];

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

double _alpha(int p) { return (p <= 1) ? 1.0 : 2.0 / (p + 1.0); }

int OnInit()
{
    SetIndexBuffer(0, g_Blue, INDICATOR_DATA);
    SetIndexBuffer(1, g_HistPos, INDICATOR_DATA);
    SetIndexBuffer(2, g_HistNeg, INDICATOR_DATA);

    ArraySetAsSeries(g_Blue, true);
    ArraySetAsSeries(g_HistPos, true);
    ArraySetAsSeries(g_HistNeg, true);
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

    IndicatorSetString(INDICATOR_SHORTNAME, "DPI v22 TEST-04c (TEST-02 logic)");
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
    g_HistPos[oldest] = EMPTY_VALUE;
    g_HistNeg[oldest] = EMPTY_VALUE;

    for(int i = rates_total - 2; i >= 0; i--)
    {
        g_Fast[i] = aFast * close[i] + (1 - aFast) * g_Fast[i+1];
        g_Slow[i] = aSlow * close[i] + (1 - aSlow) * g_Slow[i+1];

        // ONLY CHANGE FROM TEST-02: Blue = Fast EMA (not Core)
        g_Blue[i] = g_Fast[i];

        // Everything else SAME as TEST-02
        g_Core[i] = g_Fast[i] - g_Slow[i];

        g_RedA[i] = aA * g_Core[i] + (1 - aA) * g_RedA[i+1];
        g_RedB[i] = aB * g_Core[i] + (1 - aB) * g_RedB[i+1];
        g_RedC[i] = aC * g_Core[i] + (1 - aC) * g_RedC[i+1];
        g_RedD[i] = aD * g_Core[i] + (1 - aD) * g_RedD[i+1];

        g_DoubleStage1[i] = aD1 * g_Core[i] + (1 - aD1) * g_DoubleStage1[i+1];
        g_Double[i] = aD2 * g_DoubleStage1[i] + (1 - aD2) * g_Double[i+1];

        // Select red component (SAME as TEST-02)
        double selected = g_RedA[i];
        if(InpSelectedRedForHistogram == 2)
            selected = g_RedB[i];
        else if(InpSelectedRedForHistogram == 3)
            selected = g_RedC[i];
        else if(InpSelectedRedForHistogram == 4)
            selected = g_RedD[i];
        else if(InpSelectedRedForHistogram == 5)
            selected = g_Double[i];

        // Histogram (SAME as TEST-02)
        double hist = g_Core[i] - selected;

        if(hist >= 0)
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
