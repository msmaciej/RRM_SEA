//+------------------------------------------------------------------+
//|                           DPI_TEST-03_CorrectBlueGreenLogic.mq5  |
//| Based on confirmed observations:                                 |
//| - Blue line = Fast EMA (NOT Fast-Slow)                           |
//| - Red/Yellow histogram envelope = double-smoothed selected red   |
//| - Green = gap between blue line and red histogram                |
//+------------------------------------------------------------------+
#property strict
#property version   "3.00"
#property indicator_separate_window
#property indicator_buffers 4
#property indicator_plots   4

#property indicator_level1          0.0
#property indicator_levelcolor  clrSilver
#property indicator_levelstyle  STYLE_DOT
#property indicator_levelwidth  1

// Plot 0: Blue line = Fast EMA
#property indicator_label1    "Blue_FastEMA"
#property indicator_type1     DRAW_LINE
#property indicator_color1    clrDodgerBlue
#property indicator_style1    STYLE_SOLID
#property indicator_width1    2

// Plot 1: Red histogram (negative values)
#property indicator_label2    "Hist_Red"
#property indicator_type2     DRAW_HISTOGRAM
#property indicator_color2    clrRed
#property indicator_style2    STYLE_SOLID
#property indicator_width2    3

// Plot 2: Yellow histogram (positive values)
#property indicator_label3    "Hist_Yellow"
#property indicator_type3     DRAW_HISTOGRAM
#property indicator_color3    clrYellow
#property indicator_style3    STYLE_SOLID
#property indicator_width3    3

// Plot 3: Green histogram (gap filler)
#property indicator_label4    "Hist_Green"
#property indicator_type4     DRAW_HISTOGRAM
#property indicator_color4    clrLime
#property indicator_style4    STYLE_SOLID
#property indicator_width4    3

//--- Inputs (preserved from TEST-02)
input int InpFastEMA = 8;                       // Fast EMA (Blue line)
input int InpSlowEMA = 13;                      // Slow EMA (for red calculation)
input int InpRedA_EMA = 5;                      // Red candidate A
input int InpRedB_EMA = 8;                      // Red candidate B  
input int InpRedC_EMA = 13;                     // Red candidate C
input int InpRedD_EMA = 21;                     // Red candidate D
input int InpDoubleFirst = 5;                   // Double smooth 1st
input int InpDoubleSecond = 3;                  // Double smooth 2nd
input int InpSelectedRedForHistogram = 3;       // Selector: 1=A,2=B,3=C,4=D,5=Double

//--- Buffers
double g_Blue[];          // Blue line = Fast EMA
double g_HistRed[];       // Red histogram (below zero)
double g_HistYellow[];    // Yellow histogram (above zero)
double g_HistGreen[];     // Green gap filler

//--- Working buffers
double g_Fast[];          // Fast EMA
double g_Slow[];          // Slow EMA
double g_Core[];          // Fast - Slow (MACD core) for red calculation
double g_RedA[];
double g_RedB[];
double g_RedC[];
double g_RedD[];
double g_DoubleStage1[];
double g_Double[];

//+------------------------------------------------------------------+
double _alpha(const int period)
{
    if(period <= 1)
        return 1.0;
    return 2.0 / ((double)period + 1.0);
}

//+------------------------------------------------------------------+
int OnInit()
{
    if(InpFastEMA < 1 || InpSlowEMA <= InpFastEMA)
    {
        Print("DPI TEST-03 error: Slow EMA must be > Fast EMA.");
        return INIT_PARAMETERS_INCORRECT;
    }

    // Indicator buffers (displayed)
    SetIndexBuffer(0, g_Blue,       INDICATOR_DATA);
    SetIndexBuffer(1, g_HistRed,    INDICATOR_DATA);
    SetIndexBuffer(2, g_HistYellow, INDICATOR_DATA);
    SetIndexBuffer(3, g_HistGreen,  INDICATOR_DATA);

    ArraySetAsSeries(g_Blue,       true);
    ArraySetAsSeries(g_HistRed,    true);
    ArraySetAsSeries(g_HistYellow, true);
    ArraySetAsSeries(g_HistGreen,  true);

    // Working buffers (not displayed)
    ArraySetAsSeries(g_Fast,           true);
    ArraySetAsSeries(g_Slow,           true);
    ArraySetAsSeries(g_Core,           true);
    ArraySetAsSeries(g_RedA,           true);
    ArraySetAsSeries(g_RedB,           true);
    ArraySetAsSeries(g_RedC,           true);
    ArraySetAsSeries(g_RedD,           true);
    ArraySetAsSeries(g_DoubleStage1,   true);
    ArraySetAsSeries(g_Double,         true);

    PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);
    PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, EMPTY_VALUE);
    PlotIndexSetDouble(3, PLOT_EMPTY_VALUE, EMPTY_VALUE);

    IndicatorSetString(INDICATOR_SHORTNAME, 
        StringFormat("DPI TEST-03 (Fast=%d,Slow=%d,Sel=%d)", 
                     InpFastEMA, InpSlowEMA, InpSelectedRedForHistogram));
    IndicatorSetInteger(INDICATOR_DIGITS, _Digits + 1);

    return INIT_SUCCEEDED;
}

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
    int min_bars = InpSlowEMA + MathMax(MathMax(InpRedC_EMA, InpRedD_EMA), 
                                        InpDoubleFirst + InpDoubleSecond) + 5;
    if(rates_total < min_bars)
        return 0;

    ArraySetAsSeries(close, true);

    ArrayResize(g_Fast,           rates_total);
    ArrayResize(g_Slow,           rates_total);
    ArrayResize(g_Core,           rates_total);
    ArrayResize(g_RedA,           rates_total);
    ArrayResize(g_RedB,           rates_total);
    ArrayResize(g_RedC,           rates_total);
    ArrayResize(g_RedD,           rates_total);
    ArrayResize(g_DoubleStage1,   rates_total);
    ArrayResize(g_Double,         rates_total);

    const double aFast = _alpha(InpFastEMA);
    const double aSlow = _alpha(InpSlowEMA);
    const double aA    = _alpha(InpRedA_EMA);
    const double aB    = _alpha(InpRedB_EMA);
    const double aC    = _alpha(InpRedC_EMA);
    const double aD    = _alpha(InpRedD_EMA);
    const double aD1   = _alpha(InpDoubleFirst);
    const double aD2   = _alpha(InpDoubleSecond);

    int oldest = rates_total - 1;

    // Initialize
    g_Fast[oldest] = close[oldest];
    g_Slow[oldest] = close[oldest];
    g_Core[oldest] = 0.0;
    g_RedA[oldest] = 0.0;
    g_RedB[oldest] = 0.0;
    g_RedC[oldest] = 0.0;
    g_RedD[oldest] = 0.0;
    g_DoubleStage1[oldest] = 0.0;
    g_Double[oldest] = 0.0;

    g_Blue[oldest] = 0.0;
    g_HistRed[oldest] = EMPTY_VALUE;
    g_HistYellow[oldest] = EMPTY_VALUE;
    g_HistGreen[oldest] = EMPTY_VALUE;

    // Calculate EMAs and histograms
    for(int i = rates_total - 2; i >= 0; --i)
    {
        // Calculate Fast and Slow EMAs
        g_Fast[i] = aFast * close[i] + (1.0 - aFast) * g_Fast[i + 1];
        g_Slow[i] = aSlow * close[i] + (1.0 - aSlow) * g_Slow[i + 1];

        // CRITICAL CORRECTION:
        // Blue line = Fast EMA only (NOT Fast - Slow)
        g_Blue[i] = g_Fast[i];

        // Core for red calculation = Fast - Slow (MACD core)
        g_Core[i] = g_Fast[i] - g_Slow[i];

        // Calculate red candidates (smoothed versions of core)
        g_RedA[i] = aA * g_Core[i] + (1.0 - aA) * g_RedA[i + 1];
        g_RedB[i] = aB * g_Core[i] + (1.0 - aB) * g_RedB[i + 1];
        g_RedC[i] = aC * g_Core[i] + (1.0 - aC) * g_RedC[i + 1];
        g_RedD[i] = aD * g_Core[i] + (1.0 - aD) * g_RedD[i + 1];

        // Double smooth
        g_DoubleStage1[i] = aD1 * g_Core[i] + (1.0 - aD1) * g_DoubleStage1[i + 1];
        g_Double[i]       = aD2 * g_DoubleStage1[i] + (1.0 - aD2) * g_Double[i + 1];

        // Select red histogram component
        double selected = g_RedA[i];
        if(InpSelectedRedForHistogram == 2)
            selected = g_RedB[i];
        else if(InpSelectedRedForHistogram == 3)
            selected = g_RedC[i];
        else if(InpSelectedRedForHistogram == 4)
            selected = g_RedD[i];
        else if(InpSelectedRedForHistogram == 5)
            selected = g_Double[i];

        // Initialize histogram buffers
        g_HistRed[i] = EMPTY_VALUE;
        g_HistYellow[i] = EMPTY_VALUE;
        g_HistGreen[i] = EMPTY_VALUE;

        // CRITICAL LOGIC FROM YOUR OBSERVATION:
        // Red/Yellow histogram shows the selected smoothed component
        // Green shows the GAP between blue line and the histogram
        
        double blue_val = g_Blue[i];
        double red_val = selected;

        // Red/Yellow histogram assignment based on sign
        if(red_val >= 0.0)
        {
            // Positive: Yellow histogram
            g_HistYellow[i] = red_val;
        }
        else
        {
            // Negative: Red histogram
            g_HistRed[i] = red_val;
        }

        // Green histogram = gap between blue line and red/yellow histogram
        // YOUR KEY OBSERVATION:
        // "when red histogram is below zero line, and blue line is below zero line 
        //  and below red histogram, then what is red marked histogram becomes 
        //  visible as green histogram"
        //
        // This means green REPLACES red display when blue < red in negative zone
        // or when specific gap conditions are met
        
        // Let's think about this differently:
        // MT4 DPI shows: red histogram reaching certain height
        //                blue line at different position
        //                green filling the visual gap
        
        // If blue and red are on same side of zero:
        if((blue_val >= 0 && red_val >= 0) || (blue_val < 0 && red_val < 0))
        {
            // Check if there's a gap to fill
            if(blue_val > red_val)  // Blue is further from zero (above red in pos, or less negative)
            {
                // Green fills FROM red TO blue
                // But we're using DRAW_HISTOGRAM which draws from zero
                // So we need to draw green as the DIFFERENCE
                // Actually, we need DRAW_HISTOGRAM2 or draw green FROM red level
                
                // Simple approach: green = the gap amount FROM the red bar top
                double gap = blue_val - red_val;
                if(MathAbs(gap) > 0.00001)
                {
                    g_HistGreen[i] = gap;
                }
            }
            else if(blue_val < red_val)  // Red is further from zero
            {
                // In this case, red histogram extends beyond blue
                // Green might fill differently or not appear
                // Based on MT4 DPI observation, green appears when blue is MORE extreme
                // So no green here - just let red show
            }
        }
        else
        {
            // Blue and red on opposite sides of zero
            // This is a divergence case
            // Green might show the full blue in this case
            double gap = blue_val - red_val;
            if(MathAbs(gap) > 0.00001)
            {
                g_HistGreen[i] = gap;
            }
        }
    }

    return rates_total;
}
//+------------------------------------------------------------------+
