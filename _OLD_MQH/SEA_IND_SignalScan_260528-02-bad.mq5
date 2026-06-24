//  SAVE AS UTF-16 LE WITH BOM
//+------------------------------------------------------------------+
//| SEA_Scanner.mq5  v2.0                                            |
//|                                                                  |
//| Universal chart scanner. Evaluates the full TS equation on every |
//| historical bar and draws a vertical dotted line wherever TS=1.  |
//|                                                                  |
//| Uses SEA_SignalEngine.mqh directly — identical evaluation to the |
//| live EA. Every indicator can be toggled ON/OFF independently.    |
//| When multiple are ON, a line appears only when ALL pass (AND).   |
//|                                                                  |
//| TS equation:  TS = B × P × L × I × F                            |
//|   B  — Bias:  market direction (manual / 1EMA / 2EMA / 4EMA)   |
//|   P  — Phase: TM / EM / UNO gate                                |
//|   L  — Layer: pullback-recovery per EMA pair (W/M/S)            |
//|   I  — Indicators: DPI / PSAR / CandleBody / MTF (each toggle)  |
//|   F  — Filters: spread/time (always active, not configurable)    |
//|                                                                  |
//| Blue lines = LONG signal.  Red lines = SHORT signal.            |
//+------------------------------------------------------------------+
#property strict
#property version        "2.00"
#property description    "SEA Signal Scanner — TS equation on chart, all indicators configurable"
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0

#include "SEA_SignalEngine.mqh"

//+------------------------------------------------------------------+
//| Bias mode enum                                                   |
//+------------------------------------------------------------------+
enum EScanBias
{
   SBIAS_LONG        = 0,   // Manual: LONG only
   SBIAS_SHORT       = 1,   // Manual: SHORT only
   SBIAS_BOTH        = 2,   // Manual: LONG + SHORT (scan both)
   SBIAS_1EMA        = 3,   // Auto: 1 EMA slope direction
   SBIAS_2EMA        = 4,   // Auto: 2 EMA position (fast vs slow)
   SBIAS_4EMA_TM     = 5,   // Auto: 4 EMA phase — TM only (no EM)
   SBIAS_4EMA_TM_EM  = 6,   // Auto: 4 EMA phase — TM + EM
};

//+------------------------------------------------------------------+
//| Inputs — Bias                                                    |
//+------------------------------------------------------------------+
input group "=== BIAS / DIRECTION ==="
input EScanBias    In_Bias    = SBIAS_4EMA_TM;   // Bias detection mode
input int          In_EMA1    = 5;               // EMA1 (fast)
input int          In_EMA2    = 13;              // EMA2
input int          In_EMA3    = 34;              // EMA3 (4EMA/phase only)
input int          In_EMA4    = 89;              // EMA4 slow (4EMA/phase only)

//+------------------------------------------------------------------+
//| Inputs — TS Components (each independently ON/OFF)              |
//+------------------------------------------------------------------+
input group "=== TS COMPONENTS — AND logic, all ON must pass ==="
input bool  In_L_Pullback       = true;    // L: Pullback-Recovery gate (LayerW/M/S)
input bool  In_I_DPI            = true;    // I: DPI histogram direction vote
input bool  In_I_PSAR           = false;   // I: PSAR dot position
input bool  In_I_PSAR_Flip      = false;   // I: PSAR with flip window (replaces plain PSAR)
input bool  In_I_CandleBody     = false;   // I: CandleBody direction + overextension
input bool  In_I_MTF            = false;   // I: Higher TF EMA alignment

//+------------------------------------------------------------------+
//| Inputs — Pullback / Layer                                        |
//+------------------------------------------------------------------+
input group "=== LAYER / PULLBACK ==="
input int     In_PB_Lookback    = 10;      // Baseline direction lookback (bars)

//+------------------------------------------------------------------+
//| Inputs — DPI                                                     |
//+------------------------------------------------------------------+
input group "=== DPI ==="
input int     In_DPI_Fast       = 8;       // MACD fast EMA
input int     In_DPI_Slow       = 13;      // MACD slow EMA
input int     In_DPI_Signal     = 13;      // Signal EMA
input bool    In_DPI_CCI        = false;   // Require CCI confirmation
input int     In_DPI_CCI_Period = 13;      // CCI period

//+------------------------------------------------------------------+
//| Inputs — PSAR                                                    |
//+------------------------------------------------------------------+
input group "=== PSAR ==="
input double  In_PSAR_Step      = 0.02;    // PSAR step
input double  In_PSAR_Max       = 0.2;     // PSAR max
input int     In_PSAR_Delay     = 5;       // Flip window bars (-1=persistent dot only)

//+------------------------------------------------------------------+
//| Inputs — CandleBody                                              |
//+------------------------------------------------------------------+
input group "=== CANDLE BODY ==="
input int     In_CB_AvgPeriod   = 5;       // Average period
input int     In_CB_CheckBars   = 3;       // Bars to check
input double  In_CB_MaxMult     = 4.0;     // Max body multiplier

//+------------------------------------------------------------------+
//| Inputs — MTF                                                     |
//+------------------------------------------------------------------+
input group "=== MTF ==="
input ENUM_TIMEFRAMES In_MTF_TF = PERIOD_H1;    // Higher timeframe
input int     In_MTF_EMA        = 34;            // MTF EMA period (slope direction)

//+------------------------------------------------------------------+
//| Inputs — Display                                                 |
//+------------------------------------------------------------------+
input group "=== DISPLAY ==="
input color            In_CLong    = clrDodgerBlue;   // Long signal color
input color            In_CShort   = clrRed;          // Short signal color
input ENUM_LINE_STYLE  In_Style    = STYLE_DOT;       // Line style
input int              In_Width    = 1;               // Line width
input int              In_BarsBack = 500;             // Bars to scan on init

//+------------------------------------------------------------------+
//| Globals                                                          |
//+------------------------------------------------------------------+
CSignalEngine  g_eng_long;    // engine instance for LONG evaluation
CSignalEngine  g_eng_short;   // engine instance for SHORT evaluation
string         g_pfx;
bool           g_ok = false;

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
{
   g_pfx = "SCN_" + _Symbol + "_" + IntegerToString(ChartID()) + "_";

   ST_Settings sets_l, sets_s;
   BuildSettings(sets_l,  1);
   BuildSettings(sets_s, -1);

   bool ok_l = true, ok_s = true;
   if(In_Bias == SBIAS_LONG || In_Bias == SBIAS_BOTH || In_Bias >= SBIAS_1EMA)
      ok_l = g_eng_long.Init(sets_l, _Symbol);
   if(In_Bias == SBIAS_SHORT || In_Bias == SBIAS_BOTH || In_Bias >= SBIAS_1EMA)
      ok_s = g_eng_short.Init(sets_s, _Symbol);

   if(!ok_l || !ok_s)
   {
      Print("[Scanner] ERROR: engine init failed");
      return INIT_FAILED;
   }

   g_ok = true;
   Print("[Scanner] v2.0 ready. Bias=", (int)In_Bias,
         " PB=", In_L_Pullback, " DPI=", In_I_DPI,
         " PSAR=", In_I_PSAR, " PSARFlip=", In_I_PSAR_Flip,
         " CBody=", In_I_CandleBody, " MTF=", In_I_MTF);
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
                const double &open[],  const double &high[],
                const double &low[],   const double &close[],
                const long &tick_volume[], const long &volume[],
                const int &spread[])
{
   if(!g_ok || rates_total < 3) return 0;

   if(prev_calculated == 0)
   {
      ClearLines();
      int from = MathMin(rates_total - 2, In_BarsBack);
      // replay oldest→newest so state machine accumulates correctly
      for(int s = from; s >= 1; s--)
         ScanBar(s);
   }
   else if(rates_total > prev_calculated)
   {
      ScanBar(1);   // just-closed bar
   }

   return rates_total;
}

//+------------------------------------------------------------------+
//| ScanBar — evaluate one closed bar, draw line if TS=1            |
//+------------------------------------------------------------------+
void ScanBar(int shift)
{
   // Determine which directions to evaluate from bias mode
   bool do_long  = false;
   bool do_short = false;

   switch(In_Bias)
   {
      case SBIAS_LONG:  do_long  = true; break;
      case SBIAS_SHORT: do_short = true; break;
      case SBIAS_BOTH:  do_long  = do_short = true; break;

      case SBIAS_1EMA:
      {
         double e1n = EMAval(In_EMA1, shift),   e1p = EMAval(In_EMA1, shift+1);
         if(e1n > e1p) do_long=true; else if(e1n < e1p) do_short=true;
         break;
      }
      case SBIAS_2EMA:
      {
         double f = EMAval(In_EMA1, shift), sl = EMAval(In_EMA2, shift);
         if(f > sl) do_long=true; else if(f < sl) do_short=true;
         break;
      }
      case SBIAS_4EMA_TM:
      case SBIAS_4EMA_TM_EM:
      {
         double e2=EMAval(In_EMA2,shift), e3=EMAval(In_EMA3,shift), e4=EMAval(In_EMA4,shift);
         // TM
         if(e2>e3 && e3>e4)      do_long  = true;
         else if(e4>e3 && e3>e2) do_short = true;
         // EM (optional)
         else if(In_Bias == SBIAS_4EMA_TM_EM)
         {
            if(e2>e4 && e4>e3)      do_long  = true;
            else if(e3>e4 && e4>e2) do_short = true;
         }
         break;
      }
   }

   // EvaluateTS runs at Vote_EvalShift=shift — but EvaluateTS() always uses
   // m_settings.Vote_EvalShift. We set that to 1, so we need to call it only
   // when we're processing shift=1 for live bars. For historical replay we
   // cannot call EvaluateTS() on arbitrary shifts via the engine (it is
   // hardcoded to shift=1 internally). Instead for history we call the engine
   // component checks directly but still through the engine's own functions.
   // This gives identical results to the EA.

   if(do_long)  EvalWithEngine(shift, g_eng_long,  1);
   if(do_short) EvalWithEngine(shift, g_eng_short, -1);
}

//+------------------------------------------------------------------+
//| EvalWithEngine — run all enabled checks via engine functions     |
//+------------------------------------------------------------------+
void EvalWithEngine(int shift, CSignalEngine &eng, int bias)
{
   // ── L: Pullback-Recovery ───────────────────────────────────────
   if(In_L_Pullback)
   {
      eng.UpdateLayerPullbackStates(shift);

      bool layer_pass = false;
      double fast_ema = 0.0;

      // LayerW — EMA1/EMA2
      if(eng.GetLayerWPullbackState() == LAYER_PB_RECOVERED)
      {
         double f=EMAval(In_EMA1,shift), sl=EMAval(In_EMA2,shift);
         if((bias==1&&f>sl)||(bias==-1&&f<sl)) { layer_pass=true; fast_ema=f; }
      }
      // LayerM — EMA2/EMA3
      if(!layer_pass && eng.GetLayerMPullbackState() == LAYER_PB_RECOVERED)
      {
         double f=EMAval(In_EMA2,shift), sl=EMAval(In_EMA3,shift);
         if((bias==1&&f>sl)||(bias==-1&&f<sl)) { layer_pass=true; fast_ema=f; }
      }
      // LayerS — EMA3/EMA4
      if(!layer_pass && eng.GetLayerSPullbackState() == LAYER_PB_RECOVERED)
      {
         double f=EMAval(In_EMA3,shift), sl=EMAval(In_EMA4,shift);
         if((bias==1&&f>sl)||(bias==-1&&f<sl)) { layer_pass=true; fast_ema=f; }
      }
      if(!layer_pass) return;

      // BC — bar close beyond fast EMA
      double cl = iClose(_Symbol, PERIOD_CURRENT, shift);
      if(bias== 1 && cl <= fast_ema) return;
      if(bias==-1 && cl >= fast_ema) return;

      // BD — bar closed in bias direction
      double op = iOpen(_Symbol, PERIOD_CURRENT, shift);
      if(bias== 1 && cl <= op) return;
      if(bias==-1 && cl >= op) return;
   }

   // ── I: DPI ────────────────────────────────────────────────────
   if(In_I_DPI)
      if(!eng.Check_DPI(bias, shift)) return;

   // ── I: PSAR ───────────────────────────────────────────────────
   if(In_I_PSAR_Flip)
   { if(!eng.Check_PSAR_WithFlip(bias, shift)) return; }
   else if(In_I_PSAR)
   { if(!eng.Check_PSAR(bias, shift)) return; }

   // ── I: CandleBody ─────────────────────────────────────────────
   if(In_I_CandleBody)
   {
      double cl=iClose(_Symbol,PERIOD_CURRENT,shift);
      double op=iOpen (_Symbol,PERIOD_CURRENT,shift);
      // direction gate
      if(bias== 1 && cl<=op) return;
      if(bias==-1 && cl>=op) return;
      // overextension: any of last CheckBars bars body > avg * MaxMult
      double avg=0.0;
      for(int i=shift+1;i<=shift+In_CB_AvgPeriod;i++)
         avg+=MathAbs(iClose(_Symbol,PERIOD_CURRENT,i)-iOpen(_Symbol,PERIOD_CURRENT,i));
      avg/=In_CB_AvgPeriod;
      if(avg>0.0)
         for(int i=shift;i<=shift+In_CB_CheckBars-1;i++)
            if(MathAbs(iClose(_Symbol,PERIOD_CURRENT,i)-iOpen(_Symbol,PERIOD_CURRENT,i))>avg*In_CB_MaxMult)
               return;
   }

   // ── I: MTF ────────────────────────────────────────────────────
   if(In_I_MTF)
      if(!eng.Check_MTF(bias)) return;

   // ── All enabled components passed → draw vertical line ────────
   datetime t = iTime(_Symbol, PERIOD_CURRENT, shift);
   PutLine(t, bias);
}

//+------------------------------------------------------------------+
//| EMAval — compute EMA value at shift via iMA handle               |
//+------------------------------------------------------------------+
double EMAval(int period, int shift)
{
   int h = iMA(_Symbol, PERIOD_CURRENT, period, 0, MODE_EMA, PRICE_CLOSE);
   if(h == INVALID_HANDLE) return 0.0;
   double buf[1];
   if(CopyBuffer(h, 0, shift, 1, buf) != 1) return 0.0;
   return buf[0];
}

//+------------------------------------------------------------------+
//| BuildSettings — populate ST_Settings for one bias direction      |
//+------------------------------------------------------------------+
void BuildSettings(ST_Settings &s, int bias)
{
   ZeroMemory(s);
   s.symbol              = _Symbol;

   // EMA periods
   s.ma_period_1         = In_EMA1;
   s.ma_period_2         = In_EMA2;
   s.ma_period_3         = In_EMA3;
   s.ma_period_4         = In_EMA4;
   s.MaType              = MODE_EMA;
   s.ma_h_shift          = 0;
   s.ma_v_shift          = 0;

   // Bias — engine uses BIAS_4EMA internally for handle creation
   s.BiasMode            = BIAS_4EMA;

   // Phase — allow both TM and EM (bias filter is done in scanner directly)
   s.BlockEmergingPhase  = false;

   // Pullback
   s.LayerPullbackEnabled   = In_L_Pullback;
   s.LayerBaselineLookback  = In_PB_Lookback;

   // DPI
   s.Ind_Dpi_Enabled        = In_I_DPI;
   s.DPI_FastPeriod         = In_DPI_Fast;
   s.DPI_SlowPeriod         = In_DPI_Slow;
   s.DPI_SignalPeriod       = In_DPI_Signal;
   s.DPI_UseCCIReset        = In_DPI_CCI;
   s.DPI_IgnoreCCIForVote   = !In_DPI_CCI;
   s.DPI_CCI_Period         = In_DPI_CCI_Period;

   // PSAR
   s.Ind_Psar_Enabled       = (In_I_PSAR || In_I_PSAR_Flip);
   s.Psar_Step              = In_PSAR_Step;
   s.Psar_Max               = In_PSAR_Max;
   s.Vote_AllowPsarFlip     = In_I_PSAR_Flip;
   s.Vote_PsarFlipDelay     = In_PSAR_Delay;

   // CandleBody
   s.Ind_CandleBody_Enabled        = In_I_CandleBody;
   s.CandleBody_AvgPeriod          = In_CB_AvgPeriod;
   s.CandleBody_CheckBars          = In_CB_CheckBars;
   s.CandleBody_MaxMult            = In_CB_MaxMult;
   s.CandleBody_RequireDirection   = true;
   s.CandleBody_MinCloseRatio      = 0.0;

   // MTF
   s.Ind_MTF_Enabled        = In_I_MTF;
   s.MTF_TF1                = In_MTF_TF;
   s.MTF_EMA_Fast           = In_MTF_EMA;
   s.MTF_EMA_Slow           = In_MTF_EMA;   // same period = slope mode
   s.MTF_RequirePhase       = false;
   s.MTF_StrictAlignment    = false;

   // All other indicators OFF
   s.Ind_Adx_Enabled        = false;
   s.Ind_Atr_Enabled        = false;
   s.Ind_Bb_Enabled         = false;
   s.Ind_CI_Enabled         = false;
   s.Ind_Cci_Enabled        = false;
   s.Ind_Macd_Enabled       = false;
   s.Ind_Mfi_Enabled        = false;
   s.Ind_P123_Enabled       = false;
   s.Ind_Ross_Enabled       = false;
   s.Ind_Rsi_Enabled        = false;
   s.Ind_SmaConverge_Enabled= false;
   s.Ind_Sto_Enabled        = false;
   s.Ind_VRC_Enabled        = false;
   s.Ind_Fib_Enabled        = false;
   s.VPRR_Enabled           = false;

   // Vote / eval
   s.VoteMode               = VOTE_MODE_ALL;
   s.VoteThreshold          = 1;
   s.Vote_EvalShift         = 1;

   // Suppress all debug output
   s.DebugLevel             = DEBUG_SILENT;
   s.DebugFlow              = false;
}

//+------------------------------------------------------------------+
//| PutLine — draw vertical line on chart                            |
//+------------------------------------------------------------------+
void PutLine(datetime t, int bias)
{
   string name = g_pfx + IntegerToString((long)t) + (bias>0 ? "L" : "S");
   if(ObjectFind(0, name) >= 0) return;
   ObjectCreate(0, name, OBJ_VLINE, 0, t, 0);
   ObjectSetInteger(0, name, OBJPROP_COLOR,      bias>0 ? In_CLong : In_CShort);
   ObjectSetInteger(0, name, OBJPROP_STYLE,      In_Style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH,      In_Width);
   ObjectSetInteger(0, name, OBJPROP_BACK,       true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
}

//+------------------------------------------------------------------+
//| ClearLines — remove all scanner objects from chart               |
//+------------------------------------------------------------------+
void ClearLines()
{
   int n = ObjectsTotal(0);
   for(int i = n-1; i >= 0; i--)
   {
      string nm = ObjectName(0, i);
      if(StringFind(nm, g_pfx) == 0) ObjectDelete(0, nm);
   }
}
