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
#property version        "4.00"
#property description    "SEA Signal Scanner: mark TS=1 bars for any indicator combination on any pair/TF"
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0

#define SEA_BUILD_TOKEN_104001 1
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
input color       Color_Long           = clrDodgerBlue;        // LONG line color
input color       Color_Short          = clrRed;               // SHORT line color

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
input group "--- STEP4: TS Equation Components  [true=ON  false=OFF  all ON must pass] ---";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input bool     TS_ADX                = false;      // [I] ADX trend strength
input bool     TS_ATR                = false;      // [I] ATR volatility range
input bool     TS_BollingerBands     = false;      // [I] Bollinger Bands
input bool     TS_CandleBody         = false;      // [I] CandleBody direction
input bool     TS_CCI                = false;      // [I] CCI direction
input bool     TS_CI                 = false;      // [I] Choppiness Index
input bool     TS_DPI                = false;      // [I] DPI momentum
input bool     TS_MACD               = false;      // [I] MACD histogram
input bool     TS_MFI                = false;      // [I] MFI money flow
input bool     TS_MTF                = false;      // [I] MTF higher TF alignment
input bool     TS_PSAR               = false;      // [I] PSAR dot position
input bool     TS_PSAR_Flip          = false;      // [I] PSAR + flip window
input bool     TS_Pullback_Recovery  = true;       // [L] Pullback-Recovery layer
input bool     TS_RSI                = false;      // [I] RSI level
input bool     TS_Stochastic         = false;      // [I] Stochastic level
input bool     TS_VPRR               = false;      // [I] VPRR volume (metals/stocks; FX=unreliable)

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
input int      DPI_Fast             = 8;           // MACD fast EMA period
input int      DPI_Slow             = 13;          // MACD slow EMA period
input int      DPI_Signal           = 13;          // Signal/red EMA period
input bool     DPI_CCI              = true;        // Also require CCI
input int      DPI_CCI_Per          = 13;          // CCI period
input group "--- MACD ---"
input int      MACD_Fast            = 8;           // MACD fast EMA
input int      MACD_Slow            = 13;          // MACD slow EMA
input int      MACD_Signal          = 5;           // MACD signal line
input group "--- MFI ---"
input int      MFI_Period           = 14;          // MFI period
input double   MFI_Level            = 50.0;        // MFI threshold
input group "--- MTF ---"
input ENUM_TIMEFRAMES MTF_TF  = PERIOD_H1;         // Higher timeframe
input int      MTF_EMA              = 34;          // EMA period
input group "--- PSAR ---"
input double   PSAR_Step            = 0.05;        // Acceleration step
input double   PSAR_Max             = 0.5;         // Maximum acceleration
input int      PSAR_FlipBars        = 5;           // Bars after flip still valid (-1=always)
input group "--- Pullback-Recovery ---"
input int      PB_Lookback          = 21;          // Lookback bars for baseline
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
//| Limit signal lines to a specific date/time range.                |
//| Leave DateFrom = 0 to scan from BarsBack bars ago.               |
//| Leave DateTo   = 0 to scan up to the current bar.                |
//| Example: DateFrom = 2026.05.21 10:00  DateTo = 2026.05.21 21:00  |
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
string         g_pfx;
bool           g_ok = false;
int            g_sig_long  = 0;
int            g_sig_short = 0;

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
{
   g_pfx = "SCN_" + _Symbol + "_" + IntegerToString(ChartID()) + "_";

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

   // Print active components to journal so user can confirm what's running
   string active = "";
   if(TS_Pullback_Recovery)   active += "Pullback ";
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
   if(TS_BollingerBands)         active += "BB ";
   if(TS_MFI)        active += "MFI ";
   if(TS_ATR)        active += "ATR ";
   if(TS_VPRR)       active += "VPRR ";
   if(TS_CI)         active += "CI ";
   if(active == "")   active  = "(none — line on every bias bar)";

   Print("[Scanner v4.0] ", _Symbol, " ", EnumToString(PERIOD_CURRENT),
         " | Bias: ", EnumToString((ENUM_TIMEFRAMES)MarketBias),
         " | Active: ", active);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ClearLines();
   g_eng_long.Release();
   g_eng_short.Release();
   g_ok = false;
}

//+------------------------------------------------------------------+
//| OnCalculate                                                      |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[], const double &high[],
                const double &low[],  const double &close[],
                const long &tick_volume[], const long &volume[],
                const int &spread[])
{
   if(!g_ok || rates_total < 3) return 0;

   if(prev_calculated == 0)
   {
      ClearLines();
      g_sig_long = 0; g_sig_short = 0;

      // Determine scan range from DateFrom/DateTo or BarsBack
      int shift_from = 1;
      int shift_to   = MathMin(rates_total - 2, BarsBack);

      if(DateTo > 0)
      {
         int s = iBarShift(_Symbol, PERIOD_CURRENT, DateTo, false);
         shift_from = MathMax(1, s);
      }
      if(DateFrom > 0)
      {
         int s = iBarShift(_Symbol, PERIOD_CURRENT, DateFrom, false);
         shift_to = MathMin(rates_total - 2, s);
      }

      // Scan oldest→newest so pullback state machine accumulates correctly
      for(int s = shift_to; s >= shift_from; s--)
         ScanBar(s);
      DrawInfoPanel();
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

   if(doL) Eval(shift, g_eng_long,   1);
   if(doS) Eval(shift, g_eng_short, -1);
}

//+------------------------------------------------------------------+
//| Eval — check all enabled components for one bias direction       |
//+------------------------------------------------------------------+
void Eval(int shift, CSignalEngine &eng, int bias)
{
   // ── Pullback-Recovery ──────────────────────────────────────────
   if(TS_Pullback_Recovery)
   {
      eng.Scanner_UpdateLayerPullback(shift);
      bool   ok  = false;
      double fema = 0.0;

      if(eng.GetLayerWPullbackState()==LAYER_PB_RECOVERED)
      {
         double f=EMAv(EMA1,shift), sl=EMAv(EMA2,shift);
         if((bias==1&&f>sl)||(bias==-1&&f<sl)){ok=true;fema=f;}
      }
      if(!ok && eng.GetLayerMPullbackState()==LAYER_PB_RECOVERED)
      {
         double f=EMAv(EMA2,shift), sl=EMAv(EMA3,shift);
         if((bias==1&&f>sl)||(bias==-1&&f<sl)){ok=true;fema=f;}
      }
      if(!ok && eng.GetLayerSPullbackState()==LAYER_PB_RECOVERED)
      {
         double f=EMAv(EMA3,shift), sl=EMAv(EMA4,shift);
         if((bias==1&&f>sl)||(bias==-1&&f<sl)){ok=true;fema=f;}
      }
      if(!ok) return;

      double cl=iClose(_Symbol,PERIOD_CURRENT,shift);
      double op=iOpen (_Symbol,PERIOD_CURRENT,shift);
      if(bias== 1&&cl<=fema) return;
      if(bias==-1&&cl>=fema) return;
      if(bias== 1&&cl<=op)   return;
      if(bias==-1&&cl>=op)   return;
   }

   // ── DPI ────────────────────────────────────────────────────────
   if(TS_DPI)
      if(!eng.Scanner_Check_DPI(bias, shift)) return;

   // ── PSAR ───────────────────────────────────────────────────────
   if(TS_PSAR_Flip)
   { if(!eng.Scanner_Check_PSAR_Flip(bias, shift)) return; }
   else if(TS_PSAR)
   { if(!eng.Scanner_Check_PSAR(bias, shift)) return; }

   // ── MTF ────────────────────────────────────────────────────────
   if(TS_MTF)
      if(!eng.Scanner_Check_MTF(bias)) return;

   // ── CandleBody ─────────────────────────────────────────────────
   if(TS_CandleBody)
      if(!eng.Scanner_Check_CandleBody(bias, shift)) return;

   // ── ADX ────────────────────────────────────────────────────────
   if(TS_ADX)
      if(!eng.Scanner_Check_ADX(shift)) return;

   // ── RSI ────────────────────────────────────────────────────────
   if(TS_RSI)
      if(!eng.Scanner_Check_RSI(bias, shift)) return;

   // ── CCI ────────────────────────────────────────────────────────
   if(TS_CCI)
      if(!eng.Scanner_Check_CCI(bias, shift)) return;

   // ── MACD ───────────────────────────────────────────────────────
   if(TS_MACD)
      if(!eng.Scanner_Check_MACD(bias, shift)) return;

   // ── Stochastic ─────────────────────────────────────────────────
   if(TS_Stochastic)
      if(!eng.Scanner_Check_Sto(bias, shift)) return;

   // ── Bollinger Bands ────────────────────────────────────────────
   if(TS_BollingerBands)
      if(!eng.Scanner_Check_BB(bias, shift)) return;

   // ── MFI ────────────────────────────────────────────────────────
   if(TS_MFI)
      if(!eng.Scanner_Check_MFI(bias, shift)) return;

   // ── ATR ────────────────────────────────────────────────────────
   if(TS_ATR)
      if(!eng.Scanner_Check_ATR(bias, shift)) return;

   // ── VPRR ───────────────────────────────────────────────────────
   if(TS_VPRR)
      if(!eng.Scanner_Check_VPRR(shift)) return;

   // ── Choppiness Index ───────────────────────────────────────────
   if(TS_CI)
      if(!eng.Scanner_Check_CI(bias, shift)) return;

   // ── All enabled components passed → draw line ──────────────────
   PutLine(iTime(_Symbol, PERIOD_CURRENT, shift), bias);
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
   s.BlockEmergingPhase = false;

   // Pullback
   s.LayerPullbackEnabled  = TS_Pullback_Recovery;
   s.LayerBaselineLookback = PB_Lookback;

   // DPI
   s.Ind_Dpi_Enabled      = TS_DPI;
   s.DPI_MACD_Fast        = DPI_Fast;
   s.DPI_MACD_Slow        = DPI_Slow;
   s.DPI_RedEMA_A         = DPI_Signal;
   s.DPI_UseCCIReset      = DPI_CCI;
   s.DPI_IgnoreCCIForVote = !DPI_CCI;
   s.DPI_CCI_Period       = DPI_CCI_Per;

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
   s.MTF_EMA_Fast        = MTF_EMA;
   s.MTF_EMA_Slow        = MTF_EMA;
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

   // Unused voters OFF
   s.Ind_P123_Enabled       = false;
   s.Ind_Ross_Enabled       = false;
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
   string cnames[]  = {"Pullback-Recovery","DPI","PSAR","PSAR Flip","MTF",
                        "CandleBody","ADX","RSI","CCI","MACD",
                        "Stochastic","Bollinger Bands","MFI","ATR","VPRR","CI"};
   bool   cstates[] = {TS_Pullback_Recovery,TS_DPI,TS_PSAR,TS_PSAR_Flip,TS_MTF,
                        TS_CandleBody,TS_ADX,TS_RSI,TS_CCI,TS_MACD,
                        TS_Stochastic,TS_BollingerBands,TS_MFI,TS_ATR,TS_VPRR,TS_CI};

   bool any_on = false;
   for(int i = 0; i < 16; i++)
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
   ADD("  LONG:  " + (string)g_sig_long,                     Color_Long)
   ADD("  SHORT: " + (string)g_sig_short,                    Color_Short)

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
void PutLine(datetime t, int bias)
{
   string name = g_pfx + IntegerToString((long)t) + (bias>0?"L":"S");
   if(ObjectFind(0,name)>=0) return;
   ObjectCreate(0,name,OBJ_VLINE,0,t,0);
   ObjectSetInteger(0,name,OBJPROP_COLOR,      bias>0?Color_Long:Color_Short);
   ObjectSetInteger(0,name,OBJPROP_STYLE,      LineStyle);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,      LineWidth);
   ObjectSetInteger(0,name,OBJPROP_BACK,       true);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,     true);
   if(bias>0) g_sig_long++; else g_sig_short++;
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
