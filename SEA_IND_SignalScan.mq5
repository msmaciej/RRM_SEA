//  SAVE AS UTF-16 LE WITH BOM
//+------------------------------------------------------------------+
//| SEA_IND_SignalScan.mq5  v4.0                                     |
//|                                                                  |
//| Universal signal scanner — tests any combination of TS equation |
//| components on any pair, any TF, any periods.                     |
//|                                                                  |
//| HOW TO USE — step by step:                                       |
//|                                                                  |
//| STEP 1 — Open a chart for the pair + TF you want to test.      |
//|   Example: open XAUUSD M15, or GBPUSD H1, or USDJPY M5         |
//|   The scanner uses whichever chart you drop it on.              |
//|                                                                  |
//| STEP 2 — Drag SEA_IND_SignalScan from Navigator onto the chart. |
//|   The input dialog opens.                                        |
//|                                                                  |
//| STEP 3 — In the dialog, set what you want to test:             |
//|   a) EMA periods      — leave at 5/13/34/89 for RRM_ORG         |
//|   b) MarketBias       — 4EMA TM = same as RRM_ORG EA            |
//|   c) TS Components    — set true/false for each indicator:       |
//|        TS_Pullback_Recovery = true   (L factor)                 |
//|        TS_DPI               = false  (I factor)                 |
//|        TS_PSAR_Flip         = false  (I factor)                 |
//|        TS_MTF               = false  (I factor)                 |
//|        TS_ADX / TS_RSI / TS_CCI / TS_MACD / ...                |
//|      → ALL components set true must pass for a line to appear   |
//|   d) Time window      — set DateFrom and DateTo:                |
//|        DateFrom = 2026.05.21 10:00  (leave 0 = no limit)        |
//|        DateTo   = 2026.05.21 21:00  (leave 0 = up to now)       |
//|   e) Parameters       — only edit the group for each true item  |
//|                                                                  |
//| STEP 4 — Click OK.                                              |
//|   BLUE vertical lines = LONG signals on those bars              |
//|   RED  vertical lines = SHORT signals on those bars             |
//|   Panel top-left shows: pair/TF, active components, counts      |
//|                                                                  |
//| STEP 5 — To change settings:                                    |
//|   Right-click chart → Indicators list → SEA_IND_SignalScan      |
//|   → Edit → change any value → OK → lines update immediately     |
//|                                                                  |
//| WORKFLOW — how to compare indicators:                           |
//|   1. Set TS_Pullback_Recovery=true, everything else false        |
//|      → see every pullback-recovery bar (raw timing)             |
//|   2. Also set TS_DPI=true                                        |
//|      → lines narrow: only bars where pullback AND DPI agree     |
//|   3. Also set TS_PSAR_Flip=true                                  |
//|      → further narrowed: all three must agree                   |
//|   4. Try TS_RSI=true instead of TS_DPI to compare              |
//|                                                                  |
//+------------------------------------------------------------------+
#property strict
#property version        "5.00"
#property description    "SEA Signal Scanner: mark TS=1 bars for any indicator combination on any pair/TF"
#property indicator_chart_window
#property indicator_buffers 6
#property indicator_plots   6

#define SEA_BUILD_TOKEN_105001 1
#include <RRMS\SEA_SignalEngine.mqh>

//+------------------------------------------------------------------+
//| Bias mode enum                                                   |
//+------------------------------------------------------------------+
enum EScanBias
{
   SBIAS_4EMA_TM    = 0,  // 4 EMA: TRENDING markets only — TM (recommended, same as RRM_ORG)
   SBIAS_4EMA_TM_EM = 1,  // 4 EMA: TRENDING + EMERGING markets
   SBIAS_2EMA       = 2,  // 2 EMA: fast EMA position vs slow EMA
   SBIAS_1EMA       = 3,  // 1 EMA: slope of single EMA
   SBIAS_LONG       = 4,  // Manual: LONG only on every bar
   SBIAS_SHORT      = 5,  // Manual: SHORT only on every bar
   SBIAS_BOTH       = 6,  // Manual: test LONG and SHORT on every bar
};


//+------------------------------------------------------------------+
//| STEP 0 — Panel & Signals Display
//+------------------------------------------------------------------+
input group " ";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "--- STEP0: Panel ---";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input ENUM_BASE_CORNER   Scn_PanelCorner = CORNER_LEFT_UPPER;  // Panel corner
input int         Scn_PanelX           = 30;                   // Panel X px from corner
input int         Scn_PanelY           = 30;                   // Panel Y px (30=top; set ~300 if EA cockpit is also on chart)
input group "╔════════════════════════════════════════════════════════╗";
input group "--- Panel Fonts ---";
input group "╚════════════════════════════════════════════════════════╝";
input string      Scn_Font             = "Arial";              // Panel font
input int         Scn_FontSize         = 10;                   // Panel font size
input int         Scn_LineSpacing      = 28;                   // Panel line spacing px
input group "╔════════════════════════════════════════════════════════╗";
input group "--- TS Signals ---";
input group "╚════════════════════════════════════════════════════════╝";
input ENUM_LINE_STYLE LineStyle        = STYLE_DOT;            // Line style
input int         LineWidth            = 1;                    // Line width
input group "--- LONG colors (S=darkest  M=mid  W=lightest) ---"
input color       Color_Long_S         = C'0,80,180';          // LONG Layer S (strong/deep)
input color       Color_Long_M         = C'30,144,255';        // LONG Layer M (medium)
input color       Color_Long_W         = C'135,206,250';       // LONG Layer W (weak/shallow)
input group "--- SHORT colors (S=darkest  M=mid  W=lightest) ---"
input color       Color_Short_S        = C'180,0,0';           // SHORT Layer S (strong/deep)
input color       Color_Short_M        = C'255,50,50';         // SHORT Layer M (medium)
input color       Color_Short_W        = C'255,160,160';       // SHORT Layer W (weak/shallow)
input group "╔════════════════════════════════════════════════════════╗";
input group "--- Chart Overlays ---";
input group "╚════════════════════════════════════════════════════════╝";
input bool        Show_EMAs            = true;                 // Draw EMA1/2/3/4 on chart
input color       Color_EMA1           = C'255,255,100';       // EMA1 color (fastest)
input color       Color_EMA2           = C'255,200,50';        // EMA2 color
input color       Color_EMA3           = C'220,140,0';         // EMA3 color
input color       Color_EMA4           = C'160,80,0';          // EMA4 color (slowest/darkest)
input bool        Show_PSAR            = false;                // Draw PSAR dots on chart
input bool        Show_AllActiveIndicators = false;          // Add every enabled TS_* indicator to chart (add-only; oscillators -> sub-windows)

input group "--- Bar Inspector (drag the SCN_INSPECT line) ---";
input bool        Scn_Inspect_Enabled  = false;                // Inspector: TS factor breakdown for the marked bar
input color       Scn_Inspect_Color    = clrGold;              // Inspector: marked-line color
input datetime    Scn_Inspect_Time     = 0;                    // Inspector: start the line at this time (0 = latest bar); then drag to fine-tune

#define SCN_PANEL_FONT      Scn_Font
#define SCN_PANEL_FONTSIZE  Scn_FontSize
#define SCN_PANEL_SPACING   Scn_LineSpacing
#define SCN_PANEL_X         Scn_PanelX
#define SCN_PANEL_Y         Scn_PanelY
#define SCN_PANEL_CORNER    Scn_PanelCorner


//+------------------------------------------------------------------+
//| STEP 1 — Pair and Timeframe                                      |
//| Set these by opening the chart you want to test on.              |
//| The scanner automatically uses that chart's symbol and TF.       |
//+------------------------------------------------------------------+
input group " ";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "--- STEP1: Pair And TimeFrame ";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group " No inputs needed - comes from the chart";

//+------------------------------------------------------------------+
//| STEP 2 — EMA Ribbon Periods                                      |
//+------------------------------------------------------------------+
input group " ";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "--- STEP2: EMA Ribbon  [RRM_ORG default: 5 / 13 / 34 / 89] ---";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input int         EMA1           = 5;         // EMA1 fastest (LayerW fast EMA)
input int         EMA2           = 13;        // EMA2 (LayerM fast EMA)
input int         EMA3           = 34;        // EMA3 (LayerS fast EMA)
input int         EMA4           = 89;        // EMA4 slowest

//+------------------------------------------------------------------+
//| STEP 3 — Bias / Direction                                        |
//+------------------------------------------------------------------+
input group " ";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "--- STEP3: Market BIAS ---";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input EScanBias MarketBias       = SBIAS_4EMA_TM;     // Bias mode

//+------------------------------------------------------------------+
//| STEP 4 — Components ON/OFF                                       |
//| Turn ON each component to include it in the signal.              |
//| A line appears ONLY when ALL enabled components pass together.   |
//+------------------------------------------------------------------+
input group " ";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "--- STEP4: TS Components  [true=ON  false=OFF  all ON must pass] ---";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input bool TS_ADX                = false;  // [I] ADX trend strength
input bool TS_ATR                = false;  // [I] ATR volatility range
input bool TS_BollingerBands     = false;  // [I] Bollinger Bands
input bool TS_CandleBody         = false;  // [I] CandleBody direction
input bool TS_CCI                = false;  // [I] CCI direction
input bool TS_CI                 = false;  // [I] Choppiness Index
input bool   TS_ClimaxGuard      = true;   // [Guard] Block late entries into over-extended impulses
input int    CG_Lookback         = 5;      // [Guard] Window (bars) scanned for an impulse
input int    CG_ATRPeriod        = 14;     // [Guard] ATR baseline period (pre-impulse)
input double CG_BarATRMult       = 2.0;    // [Guard] Single-bar range threshold (x ATR)
input double CG_MoveATRMult      = 3.0;    // [Guard] Cumulative move threshold (x ATR)
input bool   CG_ResetPullback    = true;   // [Guard] On detection reset ALL layer PB states
input bool TS_DPI                = false;  // [I] DPI momentum
input bool TS_MACD               = false;  // [I] MACD histogram
input bool TS_MFI                = false;  // [I] MFI money flow
input bool TS_MTF                = false;  // [I] MTF higher TF alignment
input bool TS_PSAR               = false;  // [I] PSAR dot position
input bool TS_PSAR_Flip          = false;  // [I] PSAR + flip window
input bool TS_LayerS             = true;   // [L] Pullback-Recovery Layer S: EMA3->EMA4 (strongest)
input bool TS_LayerM             = true;   // [L] Pullback-Recovery Layer M: EMA2->EMA3 (medium)
input bool TS_LayerW             = true;   // [L] Pullback-Recovery Layer W: EMA1->EMA2 (weakest)
input bool TS_RSI                = false;  // [I] RSI level
input bool TS_Stochastic         = false;  // [I] Stochastic level
input bool TS_VPRR               = false;  // [I] VPRR volume (metals/stocks; FX=unreliable)
input bool TS_P123               = false;  // [I] Mark Crisp 1-2-3 fractal breakout
input bool TS_Ross               = false;  // [I] Ross Hook (trend-momentum; builds on 1-2-3)


//+------------------------------------------------------------------+
//| STEP 5 — Indicators - Component Parameters                       |
//| Only edit a section if the matching component is ON above.       |
//+------------------------------------------------------------------+
input group " ";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "--- STEP5: Indicators - TS Equation";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "--- ADX  ---"
input int      ADX_Period           = 14;          // ADX period
input double   ADX_MinLevel         = 20.0;        // Min ADX level
input group "--- ATR ---"
input int      ATR_Period           = 14;          // ATR period
input double   ATR_MinPips          = 5.0;         // Min volatility pips
input double   ATR_MaxPips          = 50.0;        // Max volatility pips
input group "--- Bollinger Bands ---"
input int      BB_Period            = 20;          // BB period
input double   BB_Dev               = 2.0;         // Standard deviations
input group "--- CandleBody ---"
input int      CB_AvgPeriod         = 5;           // Avg body period
input int      CB_CheckBars         = 3;           // Spike check bars
input double   CB_MaxMult           = 4.0;         // Max body multiplier
input group "--- CCI ---"
input int      CCI_Period           = 20;          // CCI period
input double   CCI_Level            = 0.0;         // CCI threshold
input group "--- Choppiness Index ---"
input int      CI_Period            = 14;          // CI period
input group "--- DPI ---"
input int                DPI_Fast            = SEA_DEF_DPI_MACD_FAST;       // MACD fast EMA
input int                DPI_Slow            = SEA_DEF_DPI_MACD_SLOW;       // MACD slow EMA
input int                DPI_RedSignalType   = SEA_DEF_DPI_RED_SIGNAL_TYPE; // Red line: 1=EMA_A 2=B 3=C 4=D 5=Double
input int                DPI_RedEMA_A        = SEA_DEF_DPI_RED_EMA_A;       // Red EMA period A
input int                DPI_RedEMA_B        = SEA_DEF_DPI_RED_EMA_B;       // Red EMA period B
input int                DPI_RedEMA_C        = SEA_DEF_DPI_RED_EMA_C;       // Red EMA period C (type 3 default)
input int                DPI_RedEMA_D        = SEA_DEF_DPI_RED_EMA_D;       // Red EMA period D
input int                DPI_DblSmooth1      = SEA_DEF_DPI_DBLSMOOTH_1;     // Double-smooth EMA 1 (type 5)
input int                DPI_DblSmooth2      = SEA_DEF_DPI_DBLSMOOTH_2;     // Double-smooth EMA 2 (type 5)
input int                DPI_CCI_Per         = SEA_DEF_DPI_CCI_PERIOD;      // CCI period
input ENUM_APPLIED_PRICE DPI_CCI_Price       = SEA_DEF_DPI_CCI_PRICE;       // CCI applied price
input bool               DPI_UseCCIReset     = SEA_DEF_DPI_USE_CCI_RESET;   // Require CCI reset/agreement
input bool               DPI_IgnoreCCI       = SEA_DEF_DPI_IGNORE_CCI_VOTE; // Vote on raw hist direction only
input bool               DPI_UseGreenHist    = SEA_DEF_DPI_USE_GREEN_HIST;  // Require Blue/hist green-presence
input bool               DPI_GrowthBoost     = SEA_DEF_DPI_GROWTH_BOOST;    // Histogram-growth confirmation
input group "--- MACD ---"
input int      MACD_Fast            = 8;           // MACD fast EMA
input int      MACD_Slow            = 13;          // MACD slow EMA
input int      MACD_Signal          = 5;           // MACD signal line
input group "--- MFI ---"
input int      MFI_Period           = 14;          // MFI period
input double   MFI_Level            = 50.0;        // MFI threshold
input group "--- MTF ---"
input ENUM_TIMEFRAMES MTF_TF        = PERIOD_M15;  // Higher timeframe [EA: Inp_MTF_TF2]
input int             MTF_EMA_Fast  = 20;          // Fast EMA period  [EA: Inp_MTF_EMA_Fast]
input int             MTF_EMA_Slow  = 50;          // Slow EMA period  [EA: Inp_MTF_EMA_Slow]
input group "--- PSAR ---"
input double   PSAR_Step            = 0.05;        // Acceleration step
input double   PSAR_Max             = 0.5;         // Maximum acceleration
input int      PSAR_FlipBars        = 5;           // Bars after flip still valid (-1=always)
input group "--- Pullback-Recovery ---"
input int      PB_Lookback          = 21;          // Lookback bars for baseline
input int      PB_Lookback_W        = SEA_DEF_LAYER_LB_W;            // LayerW baseline lookback (mirror EA)
input int      PB_Lookback_M        = SEA_DEF_LAYER_LB_M;            // LayerM baseline lookback
input int      PB_Lookback_S        = SEA_DEF_LAYER_LB_S;            // LayerS baseline lookback
input double   PB_PullbackRatio     = SEA_DEF_LAYER_PULLBACK_RATIO;  // Pullback threshold (|ratio|<this = weakened)
input double   PB_FlatRatio         = SEA_DEF_LAYER_FLAT_RATIO;      // Flat threshold
input double   PB_RecoveryRatio     = SEA_DEF_LAYER_RECOVERY_RATIO;  // Global recovery threshold (fallback)
input double   PB_RecoveryRatio_W   = SEA_DEF_LAYER_RECOVERY_W;      // LayerW recovery override (-1=use global)
input double   PB_RecoveryRatio_M   = SEA_DEF_LAYER_RECOVERY_M;      // LayerM recovery override
input double   PB_RecoveryRatio_S   = SEA_DEF_LAYER_RECOVERY_S;      // LayerS recovery override
input bool     PB_AllowReversal     = SEA_DEF_LAYER_ALLOW_REVERSAL;  // Count slope reversal as pullback
input int      PB_MinBars           = 1;           // Min consecutive DETECTED bars before recovery valid
input group "--- RSI---"
input int      RSI_Period           = 14;          // RSI period
input double   RSI_OB               = 70.0;        // Overbought level
input double   RSI_OS               = 30.0;        // Oversold level
input group "--- Stochastic ---"
input int      Sto_K                = 5;           // %K period
input int      Sto_D                = 3;           // %D period
input int      Sto_Slow             = 3;           // Slowing period
input double   Sto_OB               = 80.0;        // Overbought level
input double   Sto_OS               = 20.0;        // Oversold level
input group "--- VPRR --- real volume = metals/stocks/indices; FX = tick only, unreliable ---"
input double   VPRR_MinRatio        = 1.0;         // Min recovery/pullback ratio
input int      VPRR_RecovBars       = 3;           // Recovery bars to measure


//+------------------------------------------------------------------+
//| STEP 6 — Time Window                                             |
//| Limit signal lines to a specific date/time range.               |
//| Leave DateFrom = 0 to scan from BarsBack bars ago.              |
//| Leave DateTo   = 0 to scan up to the current bar.               |
//| Example: DateFrom = 2026.05.21 10:00  DateTo = 2026.05.21 21:00 |
//+------------------------------------------------------------------+
input group " ";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "--- STEP6: Time Window  [0 = no limit] ---"
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input datetime DateFrom = 0;   // From date/time (0=use BarsBack)
input datetime DateTo   = 0;   // To date/time (0=current bar)
input int      BarsBack = 500; // Bars back (if DateFrom=0)


//+------------------------------------------------------------------+
//| Globals                                                          |
//+------------------------------------------------------------------+
CSignalEngine  g_eng_long;
CSignalEngine  g_eng_short;

//+------------------------------------------------------------------+
//| Scn_AddInd — add one indicator handle to the chart (add-only).   |
//| INVALID_HANDLE is silently skipped; failures are logged.         |
//+------------------------------------------------------------------+
void Scn_AddInd(const int win, const int handle, const string label)
{
   if(handle == INVALID_HANDLE) return;
   if(ChartIndicatorAdd(0, win, handle))
      PrintFormat("[Scanner] + %s (window %d)", label, win);
   else
      PrintFormat("[Scanner] ! add %s failed (err %d)", label, GetLastError());
}

//+------------------------------------------------------------------+
//| Scn_AddActiveIndicators — draw every enabled TS_* voter that has |
//| an engine handle, sharing the verdict's exact parameters.        |
//| Add-only: existing chart indicators are preserved.               |
//|   price overlays -> window 0 (EMA/PSAR already drawn natively)    |
//|   oscillators     -> each appended in its own new sub-window      |
//| DPI/VPRR/P123/Ross are handle-less (inline) -> verdict/inspector only. |
//+------------------------------------------------------------------+
void Scn_AddActiveIndicators(CSignalEngine *eng)
{
   if(eng == NULL) return;

   // price-window overlays
   if(TS_BollingerBands) Scn_AddInd(0, eng.GetBbHandle(), "Bollinger Bands");
   if(TS_MTF)
   {
      Scn_AddInd(0, eng.GetMtfTf1FastHandle(), "MTF TF1 fast");
      Scn_AddInd(0, eng.GetMtfTf1SlowHandle(), "MTF TF1 slow");
      Scn_AddInd(0, eng.GetMtfTf2FastHandle(), "MTF TF2 fast");
      Scn_AddInd(0, eng.GetMtfTf2SlowHandle(), "MTF TF2 slow");
   }

   // oscillators: each into the next free sub-window
   if(TS_MACD)       Scn_AddInd((int)ChartGetInteger(0, CHART_WINDOWS_TOTAL), eng.GetMacdHandle(), "MACD");
   if(TS_RSI)        Scn_AddInd((int)ChartGetInteger(0, CHART_WINDOWS_TOTAL), eng.GetRsiHandle(),  "RSI");
   if(TS_CCI)        Scn_AddInd((int)ChartGetInteger(0, CHART_WINDOWS_TOTAL), eng.GetCciHandle(),  "CCI");
   if(TS_MFI)        Scn_AddInd((int)ChartGetInteger(0, CHART_WINDOWS_TOTAL), eng.GetMfiHandle(),  "MFI");
   if(TS_Stochastic) Scn_AddInd((int)ChartGetInteger(0, CHART_WINDOWS_TOTAL), eng.GetStoHandle(),  "Stochastic");
   if(TS_ADX)        Scn_AddInd((int)ChartGetInteger(0, CHART_WINDOWS_TOTAL), eng.GetAdxHandle(),  "ADX");
   if(TS_ATR)        Scn_AddInd((int)ChartGetInteger(0, CHART_WINDOWS_TOTAL), eng.GetAtrHandle(),  "ATR");
   if(TS_CI)         Scn_AddInd((int)ChartGetInteger(0, CHART_WINDOWS_TOTAL), eng.GetCiHandle(),   "CI");
}

string         g_pfx;
// -- Bar inspector (marked bar via SCN_INSPECT vline) --
string         g_insp_line  = "";
int            g_insp_shift = -1;
datetime       g_insp_time  = 0;
bool           g_insp_valid = false;
bool           g_insp_dirty = false;
int            g_insp_bias  = 0;
int            g_insp_P = -1, g_insp_L = -1, g_insp_I = -1, g_insp_F = -1, g_insp_CG = -1;
string         g_insp_P_reason="", g_insp_L_reason="", g_insp_I_reason="", g_insp_F_reason="";
int            g_insp_L_layer = 0;
string         g_insp_layer_w = "";
string         g_insp_layer_m = "";
string         g_insp_layer_s = "";
int            g_insp_ts    = 0;
bool           g_ok = false;
int            g_sig_long  = 0;
int            g_sig_short = 0;
int            g_sig_long_s  = 0;
int            g_sig_long_m  = 0;
int            g_sig_long_w  = 0;
int            g_sig_short_s = 0;
int            g_sig_short_m = 0;
int            g_sig_short_w = 0;

// ── Per-layer min-bars tracking (consecutive DETECTED bars) ───────
int g_det_s_long=0, g_det_m_long=0, g_det_w_long=0;
int g_det_s_short=0, g_det_m_short=0, g_det_w_short=0;
// Peak DETECTED bar count just before each layer transitioned to RECOVERED
int g_peak_s_long=0, g_peak_m_long=0, g_peak_w_long=0;
int g_peak_s_short=0, g_peak_m_short=0, g_peak_w_short=0;

double g_buf_ema1[];
double g_buf_ema2[];
double g_buf_ema3[];
double g_buf_ema4[];
double g_buf_psar_up[];    // PSAR dots below price (bull)
double g_buf_psar_dn[];    // PSAR dots above price (bear)

// ── Overlay indicator handles ──────────────────────────────────────
int g_h_ema1 = INVALID_HANDLE;
int g_h_ema2 = INVALID_HANDLE;
int g_h_ema3 = INVALID_HANDLE;
int g_h_ema4 = INVALID_HANDLE;
int g_h_psar = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
{
   g_pfx = "SCN_" + _Symbol + "_" + IntegerToString(ChartID()) + "_";
   g_insp_line = "SCN_INSPECT_" + IntegerToString(ChartID());  // NOT under g_pfx, so ClearLines() never deletes the dragged line

   // ── Overlay buffers — always register all 6 (MT5 requires buffer count
   //    to match #property indicator_buffers regardless of Show_* state) ──
   SetIndexBuffer(0, g_buf_ema1,    INDICATOR_DATA);
   SetIndexBuffer(1, g_buf_ema2,    INDICATOR_DATA);
   SetIndexBuffer(2, g_buf_ema3,    INDICATOR_DATA);
   SetIndexBuffer(3, g_buf_ema4,    INDICATOR_DATA);
   SetIndexBuffer(4, g_buf_psar_up, INDICATOR_DATA);
   SetIndexBuffer(5, g_buf_psar_dn, INDICATOR_DATA);

   // ── EMA plot styles ────────────────────────────────────────────────
   for(int i = 0; i < 4; i++)
   {
      color clr = (i==0)?Color_EMA1:(i==1)?Color_EMA2:(i==2)?Color_EMA3:Color_EMA4;
      if(Show_EMAs)
      {
         PlotIndexSetInteger(i, PLOT_DRAW_TYPE,  DRAW_LINE);
         PlotIndexSetInteger(i, PLOT_LINE_COLOR, clr);
         PlotIndexSetInteger(i, PLOT_LINE_WIDTH, 1);
         PlotIndexSetInteger(i, PLOT_LINE_STYLE, STYLE_SOLID);
      }
      else
         PlotIndexSetInteger(i, PLOT_DRAW_TYPE, DRAW_NONE);

      PlotIndexSetDouble(i, PLOT_EMPTY_VALUE, 0.0);
      string lbl = "EMA" + (string)(i+1) + "(" + (string)(i==0?EMA1:i==1?EMA2:i==2?EMA3:EMA4) + ")";
      PlotIndexSetString(i, PLOT_LABEL, lbl);
   }

   // ── PSAR plot styles — dots above/below price ──────────────────────
   if(Show_PSAR)
   {
      PlotIndexSetInteger(4, PLOT_DRAW_TYPE,  DRAW_ARROW);
      PlotIndexSetInteger(4, PLOT_ARROW,      159);        // dot symbol
      PlotIndexSetInteger(4, PLOT_LINE_COLOR, clrLimeGreen);
      PlotIndexSetInteger(4, PLOT_LINE_WIDTH, 2);
      PlotIndexSetInteger(5, PLOT_DRAW_TYPE,  DRAW_ARROW);
      PlotIndexSetInteger(5, PLOT_ARROW,      159);
      PlotIndexSetInteger(5, PLOT_LINE_COLOR, clrOrangeRed);
      PlotIndexSetInteger(5, PLOT_LINE_WIDTH, 2);
   }
   else
   {
      PlotIndexSetInteger(4, PLOT_DRAW_TYPE, DRAW_NONE);
      PlotIndexSetInteger(5, PLOT_DRAW_TYPE, DRAW_NONE);
   }
   PlotIndexSetDouble(4, PLOT_EMPTY_VALUE, 0.0);
   PlotIndexSetDouble(5, PLOT_EMPTY_VALUE, 0.0);
   PlotIndexSetString(4, PLOT_LABEL, "PSAR Bull");
   PlotIndexSetString(5, PLOT_LABEL, "PSAR Bear");

   // ── Create overlay handles ─────────────────────────────────────────
   if(Show_EMAs)
   {
      g_h_ema1 = iMA(_Symbol, PERIOD_CURRENT, EMA1, 0, MODE_EMA, PRICE_CLOSE);
      g_h_ema2 = iMA(_Symbol, PERIOD_CURRENT, EMA2, 0, MODE_EMA, PRICE_CLOSE);
      g_h_ema3 = iMA(_Symbol, PERIOD_CURRENT, EMA3, 0, MODE_EMA, PRICE_CLOSE);
      g_h_ema4 = iMA(_Symbol, PERIOD_CURRENT, EMA4, 0, MODE_EMA, PRICE_CLOSE);
   }
   if(Show_PSAR)
      g_h_psar = iSAR(_Symbol, PERIOD_CURRENT, PSAR_Step, PSAR_Max);

   ST_Settings s;
   BuildSettings(s);

   bool ok_l = true, ok_s = true;
   if(MarketBias != SBIAS_SHORT) ok_l = g_eng_long.Init(s, _Symbol);
   if(MarketBias != SBIAS_LONG)  ok_s = g_eng_short.Init(s, _Symbol);

   if(!ok_l || !ok_s)
   {
      Print("[Scanner] ERROR: engine init failed");
      return INIT_FAILED;
   }

   g_ok = true;

   // Mirror every enabled TS_* voter onto the chart (Tier 1: engine-handle indicators)
   if(Show_AllActiveIndicators)
      Scn_AddActiveIndicators(MarketBias != SBIAS_SHORT ? GetPointer(g_eng_long) : GetPointer(g_eng_short));

   // Print active components to journal so user can confirm what's running
   string active = "";
   if(TS_LayerS)     active += "LayerS ";
   if(TS_LayerM)     active += "LayerM ";
   if(TS_LayerW)     active += "LayerW ";
   if(TS_DPI)        active += "DPI ";
   if(TS_PSAR_Flip)  active += "PSAR_Flip ";
   else if(TS_PSAR)  active += "PSAR ";
   if(TS_MTF)        active += "MTF ";
   if(TS_CandleBody) active += "CandleBody ";
   if(TS_ADX)        active += "ADX ";
   if(TS_RSI)        active += "RSI ";
   if(TS_CCI)        active += "CCI ";
   if(TS_MACD)       active += "MACD ";
   if(TS_Stochastic)      active += "Stoch ";
   if(TS_BollingerBands)  active += "BB ";
   if(TS_MFI)        active += "MFI ";
   if(TS_ATR)        active += "ATR ";
   if(TS_VPRR)       active += "VPRR ";
   if(TS_CI)         active += "CI ";
   if(TS_P123)       active += "P123 ";
   if(TS_Ross)       active += "Ross ";
   if(active == "")   active  = "(none — line on every bias bar)";

   Print("[Scanner v4.0] ", _Symbol, " ", EnumToString(PERIOD_CURRENT),
         " | Bias: ", EnumToString((ENUM_TIMEFRAMES)MarketBias),
         " | Active: ", active);
   if(Scn_Inspect_Enabled) CreateInspectorLine();

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(ObjectFind(0, g_insp_line) >= 0) ObjectDelete(0, g_insp_line);
   ClearLines();
   g_eng_long.Release();
   g_eng_short.Release();
   if(g_h_ema1 != INVALID_HANDLE) { IndicatorRelease(g_h_ema1); g_h_ema1 = INVALID_HANDLE; }
   if(g_h_ema2 != INVALID_HANDLE) { IndicatorRelease(g_h_ema2); g_h_ema2 = INVALID_HANDLE; }
   if(g_h_ema3 != INVALID_HANDLE) { IndicatorRelease(g_h_ema3); g_h_ema3 = INVALID_HANDLE; }
   if(g_h_ema4 != INVALID_HANDLE) { IndicatorRelease(g_h_ema4); g_h_ema4 = INVALID_HANDLE; }
   if(g_h_psar != INVALID_HANDLE) { IndicatorRelease(g_h_psar); g_h_psar = INVALID_HANDLE; }
   g_ok = false;
}

//+------------------------------------------------------------------+
//| OnCalculate                                                      |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Bar Inspector helpers + marked-line resolver                     |
//+------------------------------------------------------------------+
string InspMark(int v){ return (v==1) ? "ok" : (v==0 ? "NO" : "--"); }
// Map an engine reason string to a compact inspector code.
string InspCode(string raw)
{
   if(raw=="") return "";
   if(StringFind(raw,"LAYER_NONE_ALIGNED")>=0) return "ALIGN";
   if(StringFind(raw,"BC_NOT_CONFIRMED")>=0)   return "BC";
   if(StringFind(raw,"CandleDir")>=0)          return "BD";
   if(StringFind(raw,"MOMENTUM")>=0)           return "MOM";
   if(StringFind(raw,"PHASE_UNORDERED")>=0)    return "UNORD";
   if(StringFind(raw,"PHASE_EMERGING")>=0)     return "EMERG";
   if(StringFind(raw,"EMA_OVEREXT")>=0)        return "EMAFAN";
   if(StringFind(raw,"DPI_DECEL")>=0)          return "DECEL";
   if(StringFind(raw,"DPI_RESET")>=0)          return "RESET";
   if(StringFind(raw,"PHASE_AGE")>=0)          return "AGE";
   return raw;   // I-voter names (already compact, e.g. "DPI,PSAR") shown as-is
}
// Like InspMark but appends the engine reason code when a factor is NO.
string InspMark2(int v, string raw)
{
   if(v==1) return "ok";
   if(v!=0) return "--";
   string c = InspCode(raw);
   return (c=="") ? "NO" : "NO("+c+")";
}
// L factor: show the winning layer (W/M/S) on pass, the reason code on NO.
string InspMarkL(int v, string raw, int layer)
{
   if(v==1)
   {
      string lc = (layer==1) ? "W" : (layer==2) ? "M" : (layer==3) ? "S" : "";
      return (lc=="") ? "ok" : "ok("+lc+")";
   }
   if(v!=0) return "--";
   string c = InspCode(raw);
   return (c=="") ? "NO" : "NO("+c+")";
}
string InspFirstFail()
{
   if(g_insp_P==0)  return "P (Phase)";
   if(g_insp_L==0)  return "L (Layer)";
   if(g_insp_I==0)  return "I (Indicators)";
   if(g_insp_F==0)  return "F (Filters)";
   if(g_insp_CG==0) return "CG (Climax)";
   return "?";
}

// Resolve the marked inspector bar from the SCN_INSPECT vline. Creates a
// draggable line when enabled, deletes it when disabled, and sets g_insp_dirty
// when the marked bar moves (forces a full re-scan so it is re-evaluated with
// correct per-bar state).
void ResolveInspector()
{
   if(!Scn_Inspect_Enabled)
   {
      if(ObjectFind(0, g_insp_line) >= 0) ObjectDelete(0, g_insp_line);
      if(g_insp_shift != -1) g_insp_dirty = true;
      g_insp_shift = -1; g_insp_valid = false;
      return;
   }
   if(ObjectFind(0, g_insp_line) < 0)   // user deleted the marker — respect it (toggle the input to restore)
   {
      if(g_insp_shift != -1) g_insp_dirty = true;
      g_insp_shift = -1; g_insp_valid = false;
      return;
   }
   datetime lt = (datetime)ObjectGetInteger(0, g_insp_line, OBJPROP_TIME);
   int sh = iBarShift(_Symbol, PERIOD_CURRENT, lt, false);
   if(sh < 1) sh = 1;
   if(sh != g_insp_shift) { g_insp_shift = sh; g_insp_time = lt; g_insp_dirty = true; }
}

//+------------------------------------------------------------------+
//| Inspector line creation + full-scan runner + chart events        |
//+------------------------------------------------------------------+
void CreateInspectorLine()
{
   if(ObjectFind(0, g_insp_line) >= 0) return;
   datetime t0;
   if(Scn_Inspect_Time > 0)
   {
      int sh = iBarShift(_Symbol, PERIOD_CURRENT, Scn_Inspect_Time, false);
      if(sh < 1) sh = 1;
      t0 = iTime(_Symbol, PERIOD_CURRENT, sh);   // snap to the nearest bar
   }
   else t0 = iTime(_Symbol, PERIOD_CURRENT, 1);  // default: latest bar
   ObjectCreate(0, g_insp_line, OBJ_VLINE, 0, t0, 0);
   ObjectSetInteger(0, g_insp_line, OBJPROP_COLOR,      Scn_Inspect_Color);
   ObjectSetInteger(0, g_insp_line, OBJPROP_STYLE,      STYLE_SOLID);
   ObjectSetInteger(0, g_insp_line, OBJPROP_WIDTH,      2);
   ObjectSetInteger(0, g_insp_line, OBJPROP_BACK,       false);
   ObjectSetInteger(0, g_insp_line, OBJPROP_SELECTABLE, true);
   ObjectSetInteger(0, g_insp_line, OBJPROP_SELECTED,   false);
   ObjectSetString (0, g_insp_line, OBJPROP_TOOLTIP,    "Drag to inspect this bar TS breakdown");
}

// Full chronological scan — callable from OnCalculate and OnChartEvent (drag),
// so the marked bar is re-judged with correct per-bar state without waiting for a tick.
void RunFullScan()
{
   int rates_total = Bars(_Symbol, PERIOD_CURRENT);
   if(rates_total < 3) return;

   g_insp_valid = false;   // re-prove on this scan; stays false if the marked bar is outside the window
   ClearLines();
   g_sig_long = 0; g_sig_short = 0;
   g_sig_long_s = 0; g_sig_long_m = 0; g_sig_long_w = 0;
   g_sig_short_s = 0; g_sig_short_m = 0; g_sig_short_w = 0;
   g_det_s_long=0; g_det_m_long=0; g_det_w_long=0;
   g_det_s_short=0; g_det_m_short=0; g_det_w_short=0;
   g_peak_s_long=0; g_peak_m_long=0; g_peak_w_long=0;
   g_peak_s_short=0; g_peak_m_short=0; g_peak_w_short=0;

   int shift_from = 1;
   int shift_to   = MathMin(rates_total - 2, BarsBack);
   if(DateTo > 0)   { int s = iBarShift(_Symbol, PERIOD_CURRENT, DateTo, false);   shift_from = MathMax(1, s); }
   if(DateFrom > 0) { int s = iBarShift(_Symbol, PERIOD_CURRENT, DateFrom, false); shift_to   = MathMin(rates_total - 2, s); }

   for(int s = shift_to; s >= shift_from; s--)
      ScanBar(s);
   DrawInfoPanel();
}

// Instant response to dragging / deleting the SCN_INSPECT marker (no tick needed).
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(!g_ok || !Scn_Inspect_Enabled) return;
   if(sparam != g_insp_line)         return;
   if(id == CHARTEVENT_OBJECT_DRAG)
   {
      ResolveInspector();
      if(g_insp_dirty) { g_insp_dirty = false; RunFullScan(); }
   }
   else if(id == CHARTEVENT_OBJECT_DELETE)
   {
      g_insp_shift = -1; g_insp_valid = false;   // marker removed by user; stays gone until input is re-enabled
      DrawInfoPanel();
   }
}

int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[], const double &high[],
                const double &low[],  const double &close[],
                const long &tick_volume[], const long &volume[],
                const int &spread[])
{
   if(!g_ok || rates_total < 3) return 0;

   // ── Copy overlay data every call ──────────────────────────────────
   if(Show_EMAs)
   {
      if(g_h_ema1 != INVALID_HANDLE) CopyBuffer(g_h_ema1, 0, 0, rates_total, g_buf_ema1);
      if(g_h_ema2 != INVALID_HANDLE) CopyBuffer(g_h_ema2, 0, 0, rates_total, g_buf_ema2);
      if(g_h_ema3 != INVALID_HANDLE) CopyBuffer(g_h_ema3, 0, 0, rates_total, g_buf_ema3);
      if(g_h_ema4 != INVALID_HANDLE) CopyBuffer(g_h_ema4, 0, 0, rates_total, g_buf_ema4);
   }
   if(Show_PSAR && g_h_psar != INVALID_HANDLE)
   {
      // PSAR buffer 0 = values; split into up/down by comparing to close
      double tmp[];
      if(CopyBuffer(g_h_psar, 0, 0, rates_total, tmp) == rates_total)
      {
         ArraySetAsSeries(tmp, false);
         for(int i = 0; i < rates_total; i++)
         {
            double cl = close[i];
            if(tmp[i] < cl)  { g_buf_psar_up[i] = tmp[i]; g_buf_psar_dn[i] = 0.0; }
            else             { g_buf_psar_up[i] = 0.0;    g_buf_psar_dn[i] = tmp[i]; }
         }
      }
   }

   ResolveInspector();

   if(prev_calculated == 0 || g_insp_dirty)
   {
      g_insp_dirty = false;
      RunFullScan();
   }
   else if(rates_total > prev_calculated)
   {
      // On new bar: only evaluate if within the defined window
      datetime t1 = iTime(_Symbol, PERIOD_CURRENT, 1);
      bool in_window = (DateFrom == 0 || t1 >= DateFrom) &&
                       (DateTo   == 0 || t1 <= DateTo);
      if(in_window) ScanBar(1);
      DrawInfoPanel();
   }

   return rates_total;
}

//+------------------------------------------------------------------+
//| ScanBar — determine bias then evaluate each direction            |
//+------------------------------------------------------------------+
void ScanBar(int shift)
{
   bool doL = false, doS = false;

   switch(MarketBias)
   {
      case SBIAS_LONG:      doL = true; break;
      case SBIAS_SHORT:     doS = true; break;
      case SBIAS_BOTH:      doL = doS = true; break;
      case SBIAS_1EMA:
      {
         double n=EMAv(EMA1,shift), p=EMAv(EMA1,shift+1);
         if(n>p) doL=true; else if(n<p) doS=true;
         break;
      }
      case SBIAS_2EMA:
      {
         double f=EMAv(EMA1,shift), sl=EMAv(EMA2,shift);
         if(f>sl) doL=true; else if(f<sl) doS=true;
         break;
      }
      case SBIAS_4EMA_TM:
      case SBIAS_4EMA_TM_EM:
      {
         double e2=EMAv(EMA2,shift), e3=EMAv(EMA3,shift), e4=EMAv(EMA4,shift);
         if(e2>e3&&e3>e4)       doL=true;
         else if(e4>e3&&e3>e2)  doS=true;
         else if(MarketBias==SBIAS_4EMA_TM_EM)
         {
            if(e2>e4&&e4>e3)      doL=true;
            else if(e3>e4&&e4>e2) doS=true;
         }
         break;
      }
   }

   // PSAR flip tracking must run on every bar (both engines) so the
   // flip history accumulates correctly when scanning oldest→newest.
   if(TS_PSAR || TS_PSAR_Flip)
   {
      g_eng_long.Scanner_UpdatePSARFlip(shift);
      g_eng_short.Scanner_UpdatePSARFlip(shift);
   }

   // Layer pullback state: update only the engine matching current or last-known bias.
   // During bias-absent bars (transitional), update neither engine to prevent
   // cross-contamination of state between LONG and SHORT engines.
   if(TS_LayerS || TS_LayerM || TS_LayerW)
   {
      if(doL) g_eng_long.Scanner_UpdateLayerPullback(shift);
      if(doS) g_eng_short.Scanner_UpdateLayerPullback(shift);
      // When bias is absent: reset ALL layer states (DETECTED and RECOVERED) for the idle engine.
      // This prevents DETECTED state accumulated under the wrong bias from transitioning
      // to RECOVERED and firing the moment bias returns.
      if(!doL) { g_eng_long.Scanner_ResetLayerAfterFire(1); g_eng_long.Scanner_ResetLayerAfterFire(2); g_eng_long.Scanner_ResetLayerAfterFire(3);
                 g_det_w_long=0; g_det_m_long=0; g_det_s_long=0; g_peak_w_long=0; g_peak_m_long=0; g_peak_s_long=0; }
      if(!doS) { g_eng_short.Scanner_ResetLayerAfterFire(1); g_eng_short.Scanner_ResetLayerAfterFire(2); g_eng_short.Scanner_ResetLayerAfterFire(3);
                 g_det_w_short=0; g_det_m_short=0; g_det_s_short=0; g_peak_w_short=0; g_peak_m_short=0; g_peak_s_short=0; }

      // Track consecutive DETECTED bars per layer per engine for PB_MinBars enforcement
      int prev_det_s_long  = g_det_s_long;
      int prev_det_m_long  = g_det_m_long;
      int prev_det_w_long  = g_det_w_long;
      int prev_det_s_short = g_det_s_short;
      int prev_det_m_short = g_det_m_short;
      int prev_det_w_short = g_det_w_short;

      g_det_s_long  = (g_eng_long.GetLayerSPullbackState() ==LAYER_PB_DETECTED) ? g_det_s_long+1  : 0;
      g_det_m_long  = (g_eng_long.GetLayerMPullbackState() ==LAYER_PB_DETECTED) ? g_det_m_long+1  : 0;
      g_det_w_long  = (g_eng_long.GetLayerWPullbackState() ==LAYER_PB_DETECTED) ? g_det_w_long+1  : 0;
      g_det_s_short = (g_eng_short.GetLayerSPullbackState()==LAYER_PB_DETECTED) ? g_det_s_short+1 : 0;
      g_det_m_short = (g_eng_short.GetLayerMPullbackState()==LAYER_PB_DETECTED) ? g_det_m_short+1 : 0;
      g_det_w_short = (g_eng_short.GetLayerWPullbackState()==LAYER_PB_DETECTED) ? g_det_w_short+1 : 0;

      if(g_eng_long.GetLayerSPullbackState() ==LAYER_PB_RECOVERED && prev_det_s_long  > 0) g_peak_s_long  = prev_det_s_long;
      if(g_eng_long.GetLayerMPullbackState() ==LAYER_PB_RECOVERED && prev_det_m_long  > 0) g_peak_m_long  = prev_det_m_long;
      if(g_eng_long.GetLayerWPullbackState() ==LAYER_PB_RECOVERED && prev_det_w_long  > 0) g_peak_w_long  = prev_det_w_long;
      if(g_eng_short.GetLayerSPullbackState()==LAYER_PB_RECOVERED && prev_det_s_short > 0) g_peak_s_short = prev_det_s_short;
      if(g_eng_short.GetLayerMPullbackState()==LAYER_PB_RECOVERED && prev_det_m_short > 0) g_peak_m_short = prev_det_m_short;
      if(g_eng_short.GetLayerWPullbackState()==LAYER_PB_RECOVERED && prev_det_w_short > 0) g_peak_w_short = prev_det_w_short;

      if(g_eng_long.GetLayerSPullbackState() ==LAYER_PB_NONE) g_peak_s_long  = 0;
      if(g_eng_long.GetLayerMPullbackState() ==LAYER_PB_NONE) g_peak_m_long  = 0;
      if(g_eng_long.GetLayerWPullbackState() ==LAYER_PB_NONE) g_peak_w_long  = 0;
      if(g_eng_short.GetLayerSPullbackState()==LAYER_PB_NONE) g_peak_s_short = 0;
      if(g_eng_short.GetLayerMPullbackState()==LAYER_PB_NONE) g_peak_m_short = 0;
      if(g_eng_short.GetLayerWPullbackState()==LAYER_PB_NONE) g_peak_w_short = 0;
   }

   // Inspector capture BEFORE Eval: a fire inside Eval calls ResetLayerAfterFire,
   // which would wipe the layer state and make this bar read TS=0 after firing.
   if(Scn_Inspect_Enabled && shift == g_insp_shift)
   {
      if(doL)      g_insp_ts = g_eng_long.Scanner_InspectBar(shift, g_insp_bias, g_insp_P, g_insp_L, g_insp_I, g_insp_F, g_insp_CG, g_insp_P_reason, g_insp_L_reason, g_insp_I_reason, g_insp_F_reason, g_insp_L_layer);
      else if(doS) g_insp_ts = g_eng_short.Scanner_InspectBar(shift, g_insp_bias, g_insp_P, g_insp_L, g_insp_I, g_insp_F, g_insp_CG, g_insp_P_reason, g_insp_L_reason, g_insp_I_reason, g_insp_F_reason, g_insp_L_layer);
      else         g_insp_ts = g_eng_long.Scanner_InspectBar(shift, g_insp_bias, g_insp_P, g_insp_L, g_insp_I, g_insp_F, g_insp_CG, g_insp_P_reason, g_insp_L_reason, g_insp_I_reason, g_insp_F_reason, g_insp_L_layer);
      if(doL)      g_eng_long.Scanner_InspectLayers(shift, g_insp_bias, g_insp_layer_w, g_insp_layer_m, g_insp_layer_s);
      else if(doS) g_eng_short.Scanner_InspectLayers(shift, g_insp_bias, g_insp_layer_w, g_insp_layer_m, g_insp_layer_s);
      else         g_eng_long.Scanner_InspectLayers(shift, g_insp_bias, g_insp_layer_w, g_insp_layer_m, g_insp_layer_s);
      g_insp_valid = true;
   }

   if(doL) Eval(shift, g_eng_long,   1);
   if(doS) Eval(shift, g_eng_short, -1);
}

int DetGet(int layer, int bias)
{
   if(layer==3) return (bias==1) ? g_det_s_long : g_det_s_short;
   if(layer==2) return (bias==1) ? g_det_m_long : g_det_m_short;
                return (bias==1) ? g_det_w_long : g_det_w_short;
}
int PeakGet(int layer, int bias)
{
   if(layer==3) return (bias==1) ? g_peak_s_long : g_peak_s_short;
   if(layer==2) return (bias==1) ? g_peak_m_long : g_peak_m_short;
                return (bias==1) ? g_peak_w_long : g_peak_w_short;
}

//+------------------------------------------------------------------+
//| Eval — check all enabled components for one bias direction       |
//+------------------------------------------------------------------+
void Eval(int shift, CSignalEngine &eng, int bias)
{
   // ── Shared engine: single B*P*L*I (+climax) decision path ─────────
   // SignalScan delegates the entire signal decision to the same core the EA
   // uses (EvaluateTS_AtShift), so the scanner and the EA apply identical
   // Phase / Layer(pullback-recovery) / Indicator / Climax logic at the
   // scanned bar. Bias is supplied per-direction by ScanBar; the layer
   // pullback and PSAR-flip state were already updated there.
   //
   // NOTE: the F pre-filters (DPI reset-recovery, phase-age, EMA-fan,
   // DPI-decel) are not yet in the shared core, so the scanner is slightly
   // more permissive than the EA on those gates until F is unified. Phase (P)
   // is a no-op here until the scanner config sets PhaseDetectionEnabled (2.4).
   if(eng.EvaluateTS_AtShift(shift, bias) != 1)
      return;

   int fired_layer = eng.GetLastLayer();   // 0 when layer detection is off / N/A
   PutLine(iTime(_Symbol, PERIOD_CURRENT, shift), bias, fired_layer);
   if(fired_layer > 0)
      eng.Scanner_ResetLayerAfterFire(fired_layer);
}

//+------------------------------------------------------------------+
//| EMAv — EMA value at shift                                        |
//+------------------------------------------------------------------+
double EMAv(int period, int shift)
{
   int h = iMA(_Symbol, PERIOD_CURRENT, period, 0, MODE_EMA, PRICE_CLOSE);
   if(h==INVALID_HANDLE) return 0.0;
   double buf[1];
   if(CopyBuffer(h, 0, shift, 1, buf)!=1) return 0.0;
   return buf[0];
}

//+------------------------------------------------------------------+
//| BuildSettings — map scanner inputs → ST_Settings                 |
//+------------------------------------------------------------------+
void BuildSettings(ST_Settings &s)
{
   ZeroMemory(s);

   // EMA ribbon
   s.P_Ema1 = EMA1; s.P_Ema2 = EMA2; s.P_Ema3 = EMA3; s.P_Ema4 = EMA4;
   s.MaType = METHOD_EMA; s.ma_h_shift = 0; s.ma_v_shift = 0;
   s.BiasMode = BIAS_4EMA; s.BiasEnabled = true;
   // Phase (P) mirrors RRM_ORG / CUSTOM so EvaluateP matches the EA:
   //   detect phase, block UNORDERED, allow EMERGING.
   s.PhaseDetectionEnabled = true;
   s.BlockUnorderedPhase   = true;
   s.BlockEmergingPhase    = false;

   // Pullback
   s.LayerPullbackEnabled  = (TS_LayerS || TS_LayerM || TS_LayerW);
   s.EnableLayerDetection  = (TS_LayerS || TS_LayerM || TS_LayerW);  // engage EvaluateL in shared core
   s.LayerBaselineLookback = PB_Lookback;
   s.LayerBaselineLookback_W = PB_Lookback_W;
   s.LayerBaselineLookback_M = PB_Lookback_M;
   s.LayerBaselineLookback_S = PB_Lookback_S;
   s.LayerPullbackRatio      = PB_PullbackRatio;
   s.LayerFlatRatio          = PB_FlatRatio;
   s.LayerRecoveryRatio      = PB_RecoveryRatio;
   s.LayerRecoveryRatio_W    = PB_RecoveryRatio_W;
   s.LayerRecoveryRatio_M    = PB_RecoveryRatio_M;
   s.LayerRecoveryRatio_S    = PB_RecoveryRatio_S;
   s.LayerAllowReversalPullback = PB_AllowReversal;
   s.AllowLayer1_Entries   = TS_LayerW;   // per-layer entry toggle (W) -> walk gate
   s.AllowLayer2_Entries   = TS_LayerM;   // (M)
   s.AllowLayer3_Entries   = TS_LayerS;   // (S)

   // DPI — full config; defaults mirror RRM_ORG via SEA_DEF_DPI_* (SEA_Config.mqh)
   s.Ind_Dpi_Enabled            = TS_DPI;
   s.DPI_MACD_Fast              = DPI_Fast;
   s.DPI_MACD_Slow              = DPI_Slow;
   s.DPI_RedSignalType          = DPI_RedSignalType;
   s.DPI_RedEMA_A               = DPI_RedEMA_A;
   s.DPI_RedEMA_B               = DPI_RedEMA_B;
   s.DPI_RedEMA_C               = DPI_RedEMA_C;
   s.DPI_RedEMA_D               = DPI_RedEMA_D;
   s.DPI_DoubleSmoothFirst      = DPI_DblSmooth1;
   s.DPI_DoubleSmoothSecond     = DPI_DblSmooth2;
   s.DPI_CCI_Period             = DPI_CCI_Per;
   s.DPI_CCI_AppliedPrice       = (int)DPI_CCI_Price;
   s.DPI_UseCCIReset            = DPI_UseCCIReset;
   s.DPI_IgnoreCCIForVote       = DPI_IgnoreCCI;
   s.DPI_UseGreenHist           = DPI_UseGreenHist;
   s.DPI_Histogram_Growth_Boost = DPI_GrowthBoost;

   // PSAR
   s.Ind_Psar_Enabled   = (TS_PSAR || TS_PSAR_Flip);
   s.P_PsarStep         = PSAR_Step;
   s.P_PsarMax          = PSAR_Max;
   s.Vote_AllowPsarFlip = TS_PSAR_Flip;
   s.Vote_PsarFlipDelay = PSAR_FlipBars;

   // MTF
   s.Ind_MTF_Enabled     = TS_MTF;
   s.MTF_TF1             = MTF_TF;
   s.MTF_TF2             = PERIOD_CURRENT;
   s.MTF_EMA_Fast        = MTF_EMA_Fast;
   s.MTF_EMA_Slow        = MTF_EMA_Slow;

   // Climax / exhaustion guard
   s.ClimaxGuard_Enabled       = TS_ClimaxGuard;
   s.ClimaxGuard_Lookback      = CG_Lookback;
   s.ClimaxGuard_ATRPeriod     = CG_ATRPeriod;
   s.ClimaxGuard_BarATRMult    = CG_BarATRMult;
   s.ClimaxGuard_MoveATRMult   = CG_MoveATRMult;
   s.ClimaxGuard_ResetPullback = CG_ResetPullback;
   s.MTF_RequirePhase    = false;
   s.MTF_StrictAlignment = false;

   // CandleBody
   s.Ind_CandleBody_Enabled      = TS_CandleBody;
   s.CandleBody_AvgPeriod        = CB_AvgPeriod;
   s.CandleBody_CheckBars        = CB_CheckBars;
   s.CandleBody_MaxMult          = CB_MaxMult;
   s.CandleBody_RequireDirection = true;
   s.CandleBody_MinCloseRatio    = 0.0;

   // ADX
   s.Ind_Adx_Enabled            = TS_ADX;
   s.P_Adx                      = ADX_Period;
   s.T_Adx                      = ADX_MinLevel;
   s.ADX_Mode                   = ADX_MODE_STATIC;
   s.ADX_Threshold_Trending     = ADX_MinLevel;
   s.ADX_Threshold_Accumulation = ADX_MinLevel * 0.7;
   s.ADX_Threshold_Distribution = ADX_MinLevel * 0.85;

   // RSI
   s.Ind_Rsi_Enabled = TS_RSI;
   s.P_Rsi           = RSI_Period;
   s.T_RsiOB         = RSI_OB;
   s.T_RsiOS         = RSI_OS;
   s.RsiMode         = RSI_TREND_ABOVE_50;

   // CCI
   s.Ind_Cci_Enabled = TS_CCI;
   s.P_Cci           = CCI_Period;
   s.CciMode         = CCI_TREND_ZERO;

   // MACD
   s.Ind_Macd_Enabled  = TS_MACD;
   s.P_MacdFast        = MACD_Fast;
   s.P_MacdSlow        = MACD_Slow;
   s.P_MacdSig         = MACD_Signal;
   s.MacdVoteMode      = MACD_ZERO_AND_HIST;

   // Stochastic
   s.Ind_Sto_Enabled = TS_Stochastic;
   s.P_StoK          = Sto_K;
   s.P_StoD          = Sto_D;
   s.P_StoSlow       = Sto_Slow;
   s.T_StoOB         = Sto_OB;
   s.T_StoOS         = Sto_OS;
   s.StoMode         = STO_ZONE_FILTER;

   // Bollinger Bands
   s.Ind_Bb_Enabled = TS_BollingerBands;
   s.P_Bb           = BB_Period;
   s.P_BbDev        = BB_Dev;
   s.BbMode         = BB_TREND_FOLLOW;

   // MFI
   s.Ind_Mfi_Enabled = TS_MFI;
   s.P_Mfi           = MFI_Period;
   s.T_Mfi           = MFI_Level;
   s.T_MfiOB         = MFI_Level;
   s.T_MfiOS         = 100.0 - MFI_Level;

   // ATR
   s.Ind_Atr_Enabled  = TS_ATR;
   s.P_Atr            = ATR_Period;
   s.ATR_VoteMinPips  = ATR_MinPips;
   s.ATR_VoteMaxPips  = ATR_MaxPips;

   // VPRR
   s.VPRR_Enabled         = TS_VPRR;
   s.VPRR_VolumeType      = (int)VPRR_VOL_AUTO;
   s.VPRR_MinRatio        = VPRR_MinRatio;
   s.VPRR_RecoveryBars    = VPRR_RecovBars;
   s.VPRR_MinRecoveryBars = 1;

   // Choppiness Index
   s.Ind_CI_Enabled = TS_CI;
   s.CI_Period      = CI_Period;

   // P123/Ross exposed via TS_* (EA parity); VRC + SmaConverge unused (OFF)
   s.Ind_P123_Enabled       = TS_P123;
   s.Ind_Ross_Enabled       = TS_Ross;
   s.Ind_VRC_Enabled        = false;
   s.Ind_SmaConverge_Enabled= false;
   s.Ind_Fib_Enabled        = false;

   s.Vote_EvalShift = 1;
   s.DebugLevel     = DEBUG_SILENT;
   s.DebugFlow      = false;
}


//+------------------------------------------------------------------+
//| SCN_RenderPanel — self-contained panel renderer for the IND     |
//| Mirrors SEA_UI_RenderPanel but uses Scn_* inputs only.          |
//| No dependency on Inp_UI_* or SEA_Inputs.mqh.                    |
//+------------------------------------------------------------------+
#define SCN_PANEL_NAME  "SCN_IND_PANEL"
#define SCN_MAX_LINES   50

void SCN_RenderPanel(const string txt, const color &clrs[])
{
   string lines[];
   int n = StringSplit(txt, '\n', lines);
   if(n <= 0) return;

   int  line_h   = (SCN_PANEL_SPACING > 0) ? SCN_PANEL_SPACING
                                            : MathMax(SCN_PANEL_FONTSIZE + 4, 14);
   int  pad       = 4;   // px padding — matches Inp_UI_FramePadPx default
   int  x_base    = SCN_PANEL_X + pad;
   int  y_base    = SCN_PANEL_Y + pad;
   string font    = SCN_PANEL_FONT;
   int   fs       = SCN_PANEL_FONTSIZE;

   bool is_right = (SCN_PANEL_CORNER == CORNER_RIGHT_UPPER || SCN_PANEL_CORNER == CORNER_RIGHT_LOWER);
   bool is_lower = (SCN_PANEL_CORNER == CORNER_LEFT_LOWER  || SCN_PANEL_CORNER == CORNER_RIGHT_LOWER);
   ENUM_ANCHOR_POINT anchor =
        is_right ? (is_lower ? ANCHOR_RIGHT_LOWER : ANCHOR_RIGHT_UPPER)
                 : (is_lower ? ANCHOR_LEFT_LOWER  : ANCHOR_LEFT_UPPER);

   for(int i = 0; i < SCN_MAX_LINES; i++)
   {
      string ln = SCN_PANEL_NAME + StringFormat("_L%02d", i);
      if(i < n)
      {
         if(ObjectFind(0, ln) < 0) ObjectCreate(0, ln, OBJ_LABEL, 0, 0, 0);
         color clr = (i < ArraySize(clrs)) ? clrs[i] : clrSilver;
         ObjectSetInteger(0, ln, OBJPROP_CORNER,      (int)SCN_PANEL_CORNER);
         ObjectSetInteger(0, ln, OBJPROP_ANCHOR,      (int)anchor);
         ObjectSetInteger(0, ln, OBJPROP_XDISTANCE,   x_base);
         ObjectSetInteger(0, ln, OBJPROP_YDISTANCE,   y_base + i * line_h);
         ObjectSetInteger(0, ln, OBJPROP_COLOR,       clr);
         ObjectSetInteger(0, ln, OBJPROP_FONTSIZE,    fs);
         ObjectSetInteger(0, ln, OBJPROP_SELECTABLE,  false);
         ObjectSetInteger(0, ln, OBJPROP_BACK,        false);
         ObjectSetString (0, ln, OBJPROP_FONT,        font);
         string final_txt = (lines[i] == "" || lines[i] == " ") ? " " : lines[i];
         ObjectSetString (0, ln, OBJPROP_TEXT,        final_txt);
      }
      else
         ObjectDelete(0, ln);
   }
}

void SCN_DestroyPanel()
{
   for(int i = 0; i < SCN_MAX_LINES; i++)
      ObjectDelete(0, SCN_PANEL_NAME + StringFormat("_L%02d", i));
}

//+------------------------------------------------------------------+
//| DrawInfoPanel — build content strings and call SCN_RenderPanel   |
//+------------------------------------------------------------------+
void DrawInfoPanel()
{
   string bias_str;
   switch(MarketBias)
   {
      case SBIAS_4EMA_TM:    bias_str = "4EMA TM only";   break;
      case SBIAS_4EMA_TM_EM: bias_str = "4EMA TM + EM";   break;
      case SBIAS_2EMA:       bias_str = "2EMA position";   break;
      case SBIAS_1EMA:       bias_str = "1EMA slope";      break;
      case SBIAS_LONG:       bias_str = "Manual LONG";     break;
      case SBIAS_SHORT:      bias_str = "Manual SHORT";    break;
      default:               bias_str = "LONG + SHORT";    break;
   }
   string sPer = EnumToString(PERIOD_CURRENT);
   StringReplace(sPer, "PERIOD_", "");

   // ── Build lines[] and clrs[] arrays ────────────────────────────
   string lines[];
   color  clrs[];

   // Helper lambda equivalent via macro
   #define ADD(txt, clr) { \
      int _sz = ArraySize(lines); \
      ArrayResize(lines, _sz + 1); ArrayResize(clrs, _sz + 1); \
      lines[_sz] = (txt); clrs[_sz] = (clr); }

   // ── Title ───────────────────────────────────────────────────────
   ADD("SEA Signal Scanner",                                 clrWhite)

   // ── Instrument + Bias ───────────────────────────────────────────
   ADD(_Symbol + "  " + sPer,                                clrCyan)
   ADD("Bias:  " + bias_str,                                 clrCyan)
   ADD("EMA:   " + (string)EMA1 + " / " + (string)EMA2
      + " / " + (string)EMA3 + " / " + (string)EMA4,        clrCyan)

   // ── Gap ─────────────────────────────────────────────────────────
   ADD(" ",                                                  clrDimGray)

   // ── Components header ───────────────────────────────────────────
   ADD("TS Components:",                                     clrSilver)

   // Only ON components shown — keeps panel compact
   string cnames[]  = {"PB: Layer S (EMA3->EMA4)","PB: Layer M (EMA2->EMA3)","PB: Layer W (EMA1->EMA2)",
                        "DPI","PSAR","PSAR Flip","MTF",
                        "CandleBody","ADX","RSI","CCI","MACD",
                        "Stochastic","Bollinger Bands","MFI","ATR","VPRR","CI"};
   bool   cstates[] = {TS_LayerS,TS_LayerM,TS_LayerW,
                        TS_DPI,TS_PSAR,TS_PSAR_Flip,TS_MTF,
                        TS_CandleBody,TS_ADX,TS_RSI,TS_CCI,TS_MACD,
                        TS_Stochastic,TS_BollingerBands,TS_MFI,TS_ATR,TS_VPRR,TS_CI};

   bool any_on = false;
   for(int i = 0; i < 18; i++)
   {
      if(!cstates[i]) continue;
      ADD("  + " + cnames[i],                                clrYellow)
      any_on = true;
   }
   if(!any_on)
      ADD("  (none — all bias bars marked)",                  clrDimGray)

   // ── Gap ─────────────────────────────────────────────────────────
   ADD(" ",                                                  clrDimGray)

   // ── Time window ─────────────────────────────────────────────────
   string tw;
   if(DateFrom > 0 || DateTo > 0)
   {
      string tf = (DateFrom > 0) ? TimeToString(DateFrom, TIME_DATE|TIME_MINUTES) : "start";
      string tt = (DateTo   > 0) ? TimeToString(DateTo,   TIME_DATE|TIME_MINUTES) : "now";
      tw = tf + " -> " + tt;
   }
   else
      tw = "last " + (string)BarsBack + " bars";
   ADD("Window: " + tw,                                      clrSilver)

   // ── Signal counts ───────────────────────────────────────────────
   bool any_layer = (TS_LayerS || TS_LayerM || TS_LayerW);
   if(any_layer)
   {
      ADD("  LONG:  " + (string)g_sig_long
         + "  (S:" + (string)g_sig_long_s
         + " M:" + (string)g_sig_long_m
         + " W:" + (string)g_sig_long_w + ")",               Color_Long_M)
      ADD("  SHORT: " + (string)g_sig_short
         + "  (S:" + (string)g_sig_short_s
         + " M:" + (string)g_sig_short_m
         + " W:" + (string)g_sig_short_w + ")",              Color_Short_M)
   }
   else
   {
      ADD("  LONG:  " + (string)g_sig_long,                  Color_Long_M)
      ADD("  SHORT: " + (string)g_sig_short,                 Color_Short_M)
   }

   // -- Inspector (marked bar) --
   if(Scn_Inspect_Enabled)
   {
      ADD(" ", clrDimGray)
      ADD("Inspector (drag SCN_INSPECT):", clrGold)
      if(!g_insp_valid)
         ADD("  mark a bar inside the scan window", clrDimGray)
      else
      {
         ADD("  Bar:  " + TimeToString(g_insp_time, TIME_DATE|TIME_MINUTES), clrSilver)
         string _bs = (g_insp_bias>0?"LONG":(g_insp_bias<0?"SHORT":"none"));
         color  _bc = (g_insp_bias>0?Color_Long_M:(g_insp_bias<0?Color_Short_M:clrDimGray));
         ADD("  Bias: " + _bs, _bc)
         if(g_insp_bias==0)
            ADD("  TS=0  blocked by B (no bias)", clrOrangeRed)
         else
         {
            ADD("  B:ok P:"+InspMark2(g_insp_P,g_insp_P_reason)+" L:"+InspMarkL(g_insp_L,g_insp_L_reason,g_insp_L_layer)+" I:"+InspMark2(g_insp_I,g_insp_I_reason)+" F:"+InspMark2(g_insp_F,g_insp_F_reason)+" CG:"+InspMark(g_insp_CG), clrWhite)
            ADD("    S: " + g_insp_layer_s, (g_insp_bias>0?Color_Long_S:Color_Short_S))
            ADD("    M: " + g_insp_layer_m, (g_insp_bias>0?Color_Long_M:Color_Short_M))
            ADD("    W: " + g_insp_layer_w, (g_insp_bias>0?Color_Long_W:Color_Short_W))
            if(g_insp_ts==1) ADD("  TS=1  SIGNAL", clrLime)
            else             ADD("  TS=0  blocked by " + InspFirstFail(), clrOrangeRed)
         }
      }
   }

   #undef ADD

   // ── Render via unified renderer ──────────────────────────────────
   // Concatenate to newline-separated string for SCN_RenderPanel
   string txt = "";
   for(int i = 0; i < ArraySize(lines); i++)
      txt += lines[i] + (i < ArraySize(lines)-1 ? "\n" : "");

   SCN_RenderPanel(txt, clrs);
   ChartRedraw(0);
}


//+------------------------------------------------------------------+
//| PutLine / ClearLines                                             |
//+------------------------------------------------------------------+
void PutLine(datetime t, int bias, int layer)
{
   string lbl = (layer==3?"S":(layer==2?"M":(layer==1?"W":"X")));
   string name = g_pfx + IntegerToString((long)t) + (bias>0?"L":"S") + lbl;
   if(ObjectFind(0,name)>=0) return;

   color clr;
   if(bias > 0)
      clr = (layer==3) ? Color_Long_S : (layer==2) ? Color_Long_M : Color_Long_W;
   else
      clr = (layer==3) ? Color_Short_S : (layer==2) ? Color_Short_M : Color_Short_W;

   ObjectCreate(0,name,OBJ_VLINE,0,t,0);
   ObjectSetInteger(0,name,OBJPROP_COLOR,      clr);
   ObjectSetInteger(0,name,OBJPROP_STYLE,      LineStyle);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,      LineWidth);
   ObjectSetInteger(0,name,OBJPROP_BACK,       true);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,     true);

   if(bias > 0)
   {
      g_sig_long++;
      if(layer==3) g_sig_long_s++;
      else if(layer==2) g_sig_long_m++;
      else g_sig_long_w++;
   }
   else
   {
      g_sig_short++;
      if(layer==3) g_sig_short_s++;
      else if(layer==2) g_sig_short_m++;
      else g_sig_short_w++;
   }
}

void ClearLines()
{
   SCN_DestroyPanel();
   int n=ObjectsTotal(0);
   for(int i=n-1;i>=0;i--)
   {
      string nm=ObjectName(0,i);
      if(StringFind(nm,g_pfx)==0) ObjectDelete(0,nm);
   }
}
