//+------------------------------------------------------------------+
//|                      DPI_v22_TEST-04b_RevisedColors.mq5          |
//| CAREFUL RE-ANALYSIS of MT4 DPI screenshot:                       |
//| - Red/Yellow histogram shows the SELECTED smoothed component     |
//| - Green does NOT appear as separate bars in most places          |
//| - Blue line = Fast EMA                                           |
//| Hypothesis: Maybe histogram is STACKED not separate?             |
//+------------------------------------------------------------------+
#property strict
#property version   "4.01"
#property indicator_separate_window
#property indicator_buffers 5
#property indicator_plots   5

#property indicator_level1 0.0
#property indicator_levelcolor clrSilver
#property indicator_levelstyle STYLE_DOT

// Plot 0: Blue line = Fast EMA
#property indicator_label1 "Blue"
#property indicator_type1 DRAW_LINE
#property indicator_color1 clrDodgerBlue
#property indicator_style1 STYLE_SOLID
#property indicator_width1 2

// Plot 1: Histogram from zero to selected smoothed value
#property indicator_label2 "Base_Hist"
#property indicator_type2 DRAW_HISTOGRAM
#property indicator_color2 clrNONE
#property indicator_style2 STYLE_SOLID
#property indicator_width2 3

// Plot 2: Red section (when negative)
#property indicator_label3 "Red"
#property indicator_type3 DRAW_HISTOGRAM
#property indicator_color3 clrRed
#property indicator_style3 STYLE_SOLID
#property indicator_width3 3

// Plot 3: Yellow section (when positive)
#property indicator_label4 "Yellow"
#property indicator_type4 DRAW_HISTOGRAM
#property indicator_color4 clrYellow
#property indicator_style4 STYLE_SOLID
#property indicator_width4 3

// Plot 4: Green section (gap or extension)
#property indicator_label5 "Green"
#property indicator_type5 DRAW_HISTOGRAM
#property indicator_color5 clrLime
#property indicator_style5 STYLE_SOLID
#property indicator_width5 3

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
double g_Base[];
double g_Red[];
double g_Yellow[];
double g_Green[];

//--- Working
double g_Fast[];
double g_Slow[];
double g_Core[];
double g_Selected[];

double _alpha(int p) { return (p <= 1) ? 1.0 : 2.0 / (p + 1.0); }

int OnInit()
{
    SetIndexBuffer(0, g_Blue, INDICATOR_DATA);
    SetIndexBuffer(1, g_Base, INDICATOR_DATA);
    SetIndexBuffer(2, g_Red, INDICATOR_DATA);
    SetIndexBuffer(3, g_Yellow, INDICATOR_DATA);
    SetIndexBuffer(4, g_Green, INDICATOR_DATA);

    ArraySetAsSeries(g_Blue, true);
    ArraySetAsSeries(g_Base, true);
    ArraySetAsSeries(g_Red, true);
    ArraySetAsSeries(g_Yellow, true);
    ArraySetAsSeries(g_Green, true);
    ArraySetAsSeries(g_Fast, true);
    ArraySetAsSeries(g_Slow, true);
    ArraySetAsSeries(g_Core, true);
    ArraySetAsSeries(g_Selected, true);

    PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, 0.0);
    PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, EMPTY_VALUE);
    PlotIndexSetDouble(3, PLOT_EMPTY_VALUE, EMPTY_VALUE);
    PlotIndexSetDouble(4, PLOT_EMPTY_VALUE, EMPTY_VALUE);

    IndicatorSetString(INDICATOR_SHORTNAME, "DPI v22 TEST-04b");
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
    ArrayResize(g_Selected, rates_total);

    double aFast = _alpha(InpFastEMA);
    double aSlow = _alpha(InpSlowEMA);

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
    g_Selected[oldest] = 0;

    double tempStage1[]; 
    ArrayResize(tempStage1, rates_total);
    ArraySetAsSeries(tempStage1, true);
    tempStage1[oldest] = 0;

    for(int i = rates_total - 2; i >= 0; i--)
    {
        g_Fast[i] = aFast * close[i] + (1 - aFast) * g_Fast[i+1];
        g_Slow[i] = aSlow * close[i] + (1 - aSlow) * g_Slow[i+1];
        g_Core[i] = g_Fast[i] - g_Slow[i];

        double selected = aSel * g_Core[i] + (1 - aSel) * g_Selected[i+1];
        
        if(InpSelectedRedForHistogram == 5)
        {
            tempStage1[i] = aD1 * g_Core[i] + (1 - aD1) * tempStage1[i+1];
            selected = aD2 * tempStage1[i] + (1 - aD2) * g_Selected[i+1];
        }
        
        g_Selected[i] = selected;
        g_Blue[i] = g_Fast[i];

        // Initialize
        g_Base[i] = 0;
        g_Red[i] = EMPTY_VALUE;
        g_Yellow[i] = EMPTY_VALUE;
        g_Green[i] = EMPTY_VALUE;

        // NEW HYPOTHESIS based on MT4 DPI careful observation:
        // The histogram appears as solid red OR yellow bars
        // Green appears VERY rarely
        // 
        // Maybe: Histogram = selected smoothed value
        //        Color = based on value sign
        //        Green = only in special divergence cases
        
        double hist = selected;

        // Draw main histogram with appropriate color
        if(hist > 0.00001)
        {
            g_Yellow[i] = hist;
        }
        else if(hist < -0.00001)
        {
            g_Red[i] = hist;
        }

        // Green appears ONLY in specific rare cases
        // Looking at MT4 DPI: green seems to appear when:
        // - There's a divergence between indicator phases
        // - Or at transition points
        
        // Let's try: Green when blue and histogram have opposite trends
        // Or when absolute difference exceeds certain threshold
        
        // For now: NO GREEN (let's first confirm red/yellow match MT4)
        // We'll add green logic once we confirm the base histogram is correct
    }

    return rates_total;
}
