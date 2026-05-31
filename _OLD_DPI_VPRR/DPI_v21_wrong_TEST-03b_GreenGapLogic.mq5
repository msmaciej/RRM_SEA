//+------------------------------------------------------------------+
//|                        DPI_TEST-03b_GreenGapLogic.mq5            |
//| CONFIRMED OBSERVATIONS:                                          |
//| 1. Blue line = Fast EMA (8) - NOT (Fast-Slow)                    |
//| 2. Red line in MT4 = Slow EMA (13 or 21)                         |
//| 3. Red/Yellow histogram = envelope of double-smoothed selected   |
//| 4. Green histogram YOUR OBSERVATION:                             |
//|    "when red histogram below zero AND blue line below zero       |
//|     AND blue < red, then red becomes GREEN"                      |
//+------------------------------------------------------------------+
#property strict
#property version   "3.01"
#property indicator_separate_window
#property indicator_buffers 5
#property indicator_plots   5

#property indicator_level1 0.0
#property indicator_levelcolor clrSilver
#property indicator_levelstyle STYLE_DOT

// Plot 0: Blue line = Fast EMA
#property indicator_label1 "Blue_FastEMA"
#property indicator_type1 DRAW_LINE
#property indicator_color1 clrDodgerBlue
#property indicator_style1 STYLE_SOLID
#property indicator_width1 2

// Plot 1: Slow EMA for reference (MT4 DPI red line)
#property indicator_label2 "SlowEMA_Ref"
#property indicator_type2 DRAW_LINE
#property indicator_color2 clrWhite
#property indicator_style2 STYLE_DOT
#property indicator_width2 1

// Plot 2: Red histogram
#property indicator_label3 "Hist_Red"
#property indicator_type3 DRAW_HISTOGRAM
#property indicator_color3 clrRed
#property indicator_style3 STYLE_SOLID
#property indicator_width3 3

// Plot 3: Yellow histogram
#property indicator_label4 "Hist_Yellow"
#property indicator_type4 DRAW_HISTOGRAM
#property indicator_color4 clrYellow
#property indicator_style4 STYLE_SOLID
#property indicator_width4 3

// Plot 4: Green histogram
#property indicator_label5 "Hist_Green"
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
double g_SlowRef[];
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
    SetIndexBuffer(1, g_SlowRef, INDICATOR_DATA);
    SetIndexBuffer(2, g_HistRed, INDICATOR_DATA);
    SetIndexBuffer(3, g_HistYellow, INDICATOR_DATA);
    SetIndexBuffer(4, g_HistGreen, INDICATOR_DATA);

    ArraySetAsSeries(g_Blue, true);
    ArraySetAsSeries(g_SlowRef, true);
    ArraySetAsSeries(g_HistRed, true);
    ArraySetAsSeries(g_HistYellow, true);
    ArraySetAsSeries(g_HistGreen, true);
    ArraySetAsSeries(g_Fast, true);
    ArraySetAsSeries(g_Slow, true);
    ArraySetAsSeries(g_Core, true);
    ArraySetAsSeries(g_SelectedSmooth, true);

    PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, EMPTY_VALUE);
    PlotIndexSetDouble(3, PLOT_EMPTY_VALUE, EMPTY_VALUE);
    PlotIndexSetDouble(4, PLOT_EMPTY_VALUE, EMPTY_VALUE);

    IndicatorSetString(INDICATOR_SHORTNAME, "DPI TEST-03b");
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
    int selPeriod = InpRedC_EMA;  // Default
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
        g_Fast[i] = aFast * close[i] + (1 - aFast) * g_Fast[i+1];
        g_Slow[i] = aSlow * close[i] + (1 - aSlow) * g_Slow[i+1];
        g_Core[i] = g_Fast[i] - g_Slow[i];

        // Calculate selected smoothed red
        double redCandidate = aSel * g_Core[i] + (1 - aSel) * g_SelectedSmooth[i+1];
        
        if(InpSelectedRedForHistogram == 5)
        {
            // Double smooth
            tempStage1[i] = aD1 * g_Core[i] + (1 - aD1) * tempStage1[i+1];
            redCandidate = aD2 * tempStage1[i] + (1 - aD2) * g_SelectedSmooth[i+1];
        }
        
        g_SelectedSmooth[i] = redCandidate;

        // CONFIRMED: Blue = Fast EMA only
        g_Blue[i] = g_Fast[i];
        
        // Reference: Slow EMA (MT4 DPI red line)
        g_SlowRef[i] = g_Slow[i];

        // Initialize histograms
        g_HistRed[i] = EMPTY_VALUE;
        g_HistYellow[i] = EMPTY_VALUE;
        g_HistGreen[i] = EMPTY_VALUE;

        double blue = g_Blue[i];
        double hist = redCandidate;  // The smoothed histogram value

        // YOUR OBSERVATION IMPLEMENTED:
        // "when red histogram below zero AND blue line below zero 
        //  AND blue < red (blue more negative), 
        //  then what would be red histogram becomes GREEN"
        
        if(hist >= 0)
        {
            // Positive zone - Yellow histogram
            g_HistYellow[i] = hist;
            
            // Green fills gap if blue > hist
            if(blue > hist && (blue - hist) > 0.00001)
            {
                g_HistGreen[i] = blue - hist;
            }
        }
        else  // hist < 0
        {
            // Negative zone
            if(blue < 0 && blue < hist)
            {
                // YOUR KEY OBSERVATION:
                // Blue is below zero AND more negative than histogram
                // Draw GREEN histogram instead of red
                g_HistGreen[i] = hist;
            }
            else
            {
                // Normal case: draw RED histogram
                g_HistRed[i] = hist;
                
                // If blue is in negative zone but less negative (blue > hist)
                // green fills the gap
                if(blue < 0 && blue > hist && (blue - hist) > 0.00001)
                {
                    g_HistGreen[i] = blue - hist;
                }
            }
        }
    }

    return rates_total;
}
