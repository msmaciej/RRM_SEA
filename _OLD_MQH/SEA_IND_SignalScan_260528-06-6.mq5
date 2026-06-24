//  SAVE AS UTF-16 LE WITH BOM
//+------------------------------------------------------------------+
//| SEA_IND_SignalScan.mq5  v4.0                                     |
//|                                                                  |
//| Universal signal scanner — tests any combination of TS equation |
//| components on any pair, any TF, any periods.                     |
//|                                                                  |
//| HOW TO USE:                                                      |
//|  1. Open any chart (sets the pair and TF to test)               |
//|  2. Drag this indicator onto it                                  |
//|  3. In the dialog:                                               |
//|     a. Set EMA periods (default = RRM_ORG: 5/13/34/89)          |
//|     b. Set Bias mode (default = 4EMA TM, same as RRM_ORG)       |
//|     c. Turn ON the components you want to test                   |
//|     d. Adjust component parameters if needed                     |
//|  4. Click OK → vertical lines appear on every TS=1 bar          |
//|  5. Right-click chart → Indicators list → Edit → change & rescan|
//|                                                                  |
//| LINES:  BLUE = LONG signal    RED = SHORT signal                 |
//|                                                                  |
//| TESTING WORKFLOW:                                                |
//|  Start with ONE component ON to see how it fires alone.          |
//|  Add a second component — lines narrow to where both agree.      |
//|  Keep adding to find the best combination for the pair/TF.       |
//|                                                                  |
//| EXAMPLES:                                                        |
//|  Pullback timing only:   TS_Pullback_Recovery=ON, rest OFF               |
//|  DPI alone:              TS_DPI=ON, rest OFF                    |
//|  Pullback + DPI:         TS_Pullback_Recovery=ON, TS_DPI=ON             |
//|  Full RRM_ORG signal:    TS_Pullback_Recovery, TS_DPI, TS_PSAR_Flip,   |
//|                          TS_MTF all ON                          |
//|  Test RSI instead of DPI:TS_Pullback_Recovery=ON, TS_RSI=ON             |
//|  ADX filter only:        TS_ADX=ON, rest OFF                    |
//+------------------------------------------------------------------+
#property strict
#property version        "4.00"
#property description    "SEA Signal Scanner: mark TS=1 bars for any indicator combination on any pair/TF"
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0

#define SEA_BUILD_TOKEN_104001 1
#include <RRMS\SEA_Config.mqh>
#include <RRMS\SEA_Presets.mqh>
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
//| STEP 1 — Pair and Timeframe                                      |
//| Set these by opening the chart you want to test on.             |
//| The scanner automatically uses that chart's symbol and TF.      |
//+------------------------------------------------------------------+
// (no inputs needed — comes from the chart itself)

//+------------------------------------------------------------------+
//| STEP 2 — EMA Ribbon Periods                                      |
//+------------------------------------------------------------------+
input group "=== STEP 2: EMA Ribbon Periods  [default RRM_ORG: 5 / 13 / 34 / 89] ==="
input int  EMA1 = 5;   // EMA1 fastest — used by all bias modes and Layer W
input int  EMA2 = 13;  // EMA2 — used by 2EMA/4EMA bias and Layer M
input int  EMA3 = 34;  // EMA3 — used by 4EMA bias and Layer S
input int  EMA4 = 89;  // EMA4 slowest — used by 4EMA bias and Layer S

//+------------------------------------------------------------------+
//| STEP 3 — Bias / Direction                                        |
//+------------------------------------------------------------------+
input group "=== STEP 3: Market BIAS — how direction is determined ==="
input EScanBias MarketBias = SBIAS_4EMA_TM;  // MARKET BIAS: which direction is the market? (4EMA TM = same as RRM_ORG EA)

//+------------------------------------------------------------------+
//| STEP 4 — Components ON/OFF                                       |
//| Turn ON each component to include it in the signal.             |
//| A line appears ONLY when ALL enabled components pass together.   |
//+------------------------------------------------------------------+
input group "=== STEP 4: TS Equation Components  [true = ON, false = OFF, all ON must pass] ==="
input bool TS_Pullback_Recovery = true;   // [L] Layer: EMA pullback then recovery — price must show cycle
input bool TS_DPI                = false;  // [I] DPI: momentum histogram in bias direction
input bool TS_PSAR               = false;  // [I] PSAR: dot on correct side of price
input bool TS_PSAR_Flip          = false;  // [I] PSAR Flip: dot flipped recently + on correct side
input bool TS_MTF                = false;  // [I] MTF: higher timeframe EMA agrees with bias
input bool TS_CandleBody         = false;  // [I] CandleBody: bar closes in bias direction, not a spike
input bool TS_ADX                = false;  // [I] ADX: trend strength above minimum level
input bool TS_RSI                = false;  // [I] RSI: not overbought/oversold
input bool TS_CCI                = false;  // [I] CCI: confirms bias direction
input bool TS_MACD               = false;  // [I] MACD: histogram or zero-line confirms bias
input bool TS_Stochastic         = false;  // [I] Stochastic: %K/%D level confirms bias
input bool TS_BollingerBands     = false;  // [I] Bollinger Bands: price position confirms bias
input bool TS_MFI                = false;  // [I] MFI: money flow confirms bias
input bool TS_ATR                = false;  // [I] ATR: volatility within defined range
input bool TS_VPRR               = false;  // [I] VPRR: recovery volume > pullback volume (reliable with real exchange volume: metals/stocks/indices; unreliable on FX = tick volume only)
input bool TS_CI                 = false;  // [I] Choppiness Index: market trending, not ranging

//+------------------------------------------------------------------+
//| STEP 5 — Component Parameters                                    |
//| Only edit a section if the matching component is ON above.       |
//+------------------------------------------------------------------+

input group "--- Pullback-Recovery parameters (TS_Pullback_Recovery = true) ---"
input int  PB_Lookback = 10;  // Baseline direction lookback bars

input group "--- DPI parameters (TS_DPI = true) ---"
input int  DPI_Fast    = 8;    // MACD fast EMA period
input int  DPI_Slow    = 13;   // MACD slow EMA period
input int  DPI_Signal  = 13;   // Signal/red EMA period
input bool DPI_CCI     = false; // Also require CCI agreement (stricter)
input int  DPI_CCI_Per = 13;   // CCI period (only if DPI_CCI=ON)

input group "--- PSAR parameters (TS_PSAR or TS_PSAR_Flip = true) ---"
input double PSAR_Step     = 0.02;  // Acceleration step
input double PSAR_Max      = 0.2;   // Maximum acceleration
input int    PSAR_FlipBars = 5;     // Flip window: bars after flip still valid (-1=persistent)

input group "--- MTF parameters (TS_MTF = true) ---"
input ENUM_TIMEFRAMES MTF_TF  = PERIOD_H1;  // Higher timeframe to check
input int             MTF_EMA = 34;          // EMA period on that timeframe

input group "--- CandleBody parameters (TS_CandleBody = true) ---"
input int    CB_AvgPeriod = 5;    // Body average period
input int    CB_CheckBars = 3;    // Recent bars to check for spikes
input double CB_MaxMult   = 4.0;  // Spike = body > avg × this value

input group "--- ADX parameters (TS_ADX = true) ---"
input int    ADX_Period  = 14;    // ADX period
input double ADX_MinLevel= 25.0;  // Minimum ADX value to pass (trend strong enough)

input group "--- RSI parameters (TS_RSI = true) ---"
input int    RSI_Period  = 14;    // RSI period
input double RSI_OB      = 70.0;  // Overbought level (SHORT blocked above, LONG blocked if below OS)
input double RSI_OS      = 30.0;  // Oversold level

input group "--- CCI parameters (TS_CCI = true) ---"
input int    CCI_Period  = 20;    // CCI period
input double CCI_Level   = 0.0;   // CCI must be above this for LONG, below for SHORT

input group "--- MACD parameters (TS_MACD = true) ---"
input int    MACD_Fast   = 12;    // MACD fast EMA
input int    MACD_Slow   = 26;    // MACD slow EMA
input int    MACD_Signal = 9;     // MACD signal line

input group "--- Stochastic parameters (TS_Stochastic = true) ---"
input int    Sto_K       = 5;     // %K period
input int    Sto_D       = 3;     // %D period
input int    Sto_Slow    = 3;     // Slowing period
input double Sto_OB      = 80.0;  // Overbought level
input double Sto_OS      = 20.0;  // Oversold level

input group "--- Bollinger Bands parameters (TS_BollingerBands = true) ---"
input int    BB_Period   = 20;    // BB period
input double BB_Dev      = 2.0;   // Standard deviations

input group "--- MFI parameters (TS_MFI = true) ---"
input int    MFI_Period  = 14;    // MFI period
input double MFI_Level   = 50.0;  // MFI must be above for LONG, below for SHORT

input group "--- ATR parameters (TS_ATR = true) ---"
input int    ATR_Period  = 14;    // ATR period
input double ATR_MinPips = 5.0;   // Minimum volatility (pips) to allow trade
input double ATR_MaxPips = 100.0; // Maximum volatility (pips) to allow trade

input group "--- VPRR parameters (TS_VPRR = true) --- real volume = metals/stocks/indices; FX = tick only, unreliable ---"
input double VPRR_MinRatio    = 1.0;  // Recovery volume must be this × pullback volume
input int    VPRR_RecovBars   = 3;    // Recovery bars to measure

input group "--- Choppiness Index parameters (TS_CI = true) ---"
input int    CI_Period   = 14;    // CI period (lower = trending, higher = ranging)

//+------------------------------------------------------------------+
//| STEP 6 — Display                                                 |
//+------------------------------------------------------------------+
input group "=== STEP 5: Display ==="
input color           Color_Long  = clrDodgerBlue;  // LONG signal line color
input color           Color_Short = clrRed;          // SHORT signal line color
input ENUM_LINE_STYLE LineStyle   = STYLE_DOT;       // Line style
input int             LineWidth   = 1;               // Line width
input int             BarsBack    = 500;             // Bars to scan back on startup

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
      int from = MathMin(rates_total - 2, BarsBack);
      for(int s = from; s >= 1; s--)
         ScanBar(s);
      DrawInfoPanel();
   }
   else if(rates_total > prev_calculated)
   {
      ScanBar(1);
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
//| DrawInfoPanel — show scan status directly on chart               |
//+------------------------------------------------------------------+
void DrawInfoPanel()
{
   string pfx2 = g_pfx + "INFO_";

   // Build component list
   string comps = "";
   if(TS_Pullback_Recovery)   comps += "Pullback ";
   if(TS_DPI)        comps += "DPI ";
   if(TS_PSAR_Flip)  comps += "PSAR_Flip ";
   else if(TS_PSAR)  comps += "PSAR ";
   if(TS_MTF)        comps += "MTF ";
   if(TS_CandleBody) comps += "CandleBody ";
   if(TS_ADX)        comps += "ADX ";
   if(TS_RSI)        comps += "RSI ";
   if(TS_CCI)        comps += "CCI ";
   if(TS_MACD)       comps += "MACD ";
   if(TS_Stochastic)      comps += "Stoch ";
   if(TS_BollingerBands)         comps += "BB ";
   if(TS_MFI)        comps += "MFI ";
   if(TS_ATR)        comps += "ATR ";
   if(TS_VPRR)       comps += "VPRR ";
   if(TS_CI)         comps += "CI ";
   if(comps == "")    comps  = "(none — marking every bias bar)";

   string bias_str;
   switch(MarketBias)
   {
      case SBIAS_4EMA_TM:    bias_str = "4EMA TM only";        break;
      case SBIAS_4EMA_TM_EM: bias_str = "4EMA TM+EM";          break;
      case SBIAS_2EMA:       bias_str = "2EMA position";        break;
      case SBIAS_1EMA:       bias_str = "1EMA slope";           break;
      case SBIAS_LONG:       bias_str = "Manual LONG";          break;
      case SBIAS_SHORT:      bias_str = "Manual SHORT";         break;
      default:               bias_str = "LONG + SHORT";         break;
   }

   string lines[];
   ArrayResize(lines, 6);
   lines[0] = "[ SEA Signal Scanner ]";
   lines[1] = "Pair: " + _Symbol + "  TF: " + EnumToString(PERIOD_CURRENT);
   lines[2] = "Bias: " + bias_str + "  EMA: " + (string)EMA1+"/"+(string)EMA2+"/"+(string)EMA3+"/"+(string)EMA4;
   lines[3] = "ON: " + comps;
   lines[4] = "Signals found in last " + (string)BarsBack + " bars:";
   lines[5] = "  LONG: " + (string)g_sig_long + " (blue)    SHORT: " + (string)g_sig_short + " (red)";

   for(int i = 0; i < 6; i++)
   {
      string nm = pfx2 + (string)i;
      if(ObjectFind(0, nm) < 0)
      {
         ObjectCreate(0, nm, OBJ_LABEL, 0, 0, 0);
         ObjectSetInteger(0, nm, OBJPROP_CORNER,    CORNER_LEFT_UPPER);
         ObjectSetInteger(0, nm, OBJPROP_XDISTANCE, 10);
         ObjectSetInteger(0, nm, OBJPROP_YDISTANCE, 20 + i * 16);
         ObjectSetInteger(0, nm, OBJPROP_FONTSIZE,  9);
         ObjectSetInteger(0, nm, OBJPROP_BACK,      false);
         ObjectSetInteger(0, nm, OBJPROP_SELECTABLE,false);
         color c = (i==0) ? clrWhite : (i==5) ? clrYellow : clrSilver;
         ObjectSetInteger(0, nm, OBJPROP_COLOR, c);
      }
      ObjectSetString(0, nm, OBJPROP_TEXT, lines[i]);
   }
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
   int n=ObjectsTotal(0);
   for(int i=n-1;i>=0;i--)
   {
      string nm=ObjectName(0,i);
      if(StringFind(nm,g_pfx)==0) ObjectDelete(0,nm);
   }
}
