//+------------------------------------------------------------------+
//| SEA_MetaGate.mqh — optional ML "second opinion" for the RRM EA    |
//|                                                                    |
//| SELF-CONTAINED, PARAMETER-AWARE. Signal-side indicators (EMAs,     |
//| MACD/CCI = DPI core, PSAR) are computed from the LIVE preset       |
//| inputs, so changing a VALUE in SEA_Inputs.mqh needs NO edit here — |
//| just re-collect + re-train. Context/ranging gauges (ADX, BB, ATR,  |
//| volatility, Stoch, RSI, MFI) are ALWAYS measured, even when the    |
//| preset has them disabled for voting — that is what lets the model  |
//| learn "ranging market = skip" without changing your TS rules.      |
//|                                                                    |
//| Adding a NEW feature (e.g. a ranging indicator you trust) is the   |
//| only reason to edit this file — add one line in MetaBuildFeatures. |
//|                                                                    |
//| Place at:  MQL5\Include\RRMS\SEA_MetaGate.mqh                      |
//| EVENTS CSV durability (2026-07-31): the collect log is written to  |
//| the SHARED Common\Files via FILE_COMMON, which is OUTSIDE the per- |
//| run tester agent sandbox and therefore SURVIVES sequential runs —  |
//| so many pair+TF collects accumulate instead of leaving only the    |
//| last. (0bbe5ad had switched to NON-common Agent-*\MQL5\Files, which |
//| the tester re-creates every run; that wiped all but the final       |
//| collect — confirmed on disk.) The earlier FILE_COMMON INVALID_HANDLE|
//| under Wine was the shared folder not existing yet in the prefix:    |
//| LogTSEvent now FolderCreate+retries, and if FILE_COMMON is still    |
//| unavailable it FALLS BACK to the sandbox (run not lost) and prints  |
//| a loud non-durable warning. A run-scoped dup-guard skips already-   |
//| logged bars so re-collecting an overlapping range adds no repeats.  |
//| MODEL read stays NON-common on purpose: rrm_meta.py writes the model|
//| into the terminal MQL5\Files, which the tester SEEDS into the agent |
//| sandbox at run start, so the EA reads it there. rrm_meta.py's       |
//| discovery already searches Common\Files + every MQL5\Files.         |
//+------------------------------------------------------------------+
#ifndef SEA_METAGATE_MQH
#define SEA_METAGATE_MQH
#property strict

//==================== META INPUTS ==================================
input bool   Inp_META_Enabled     = false;     // Inp_META_Enabled: false = behaves as today; true = gate active
input bool   Inp_META_LogFeatures = false;     // Inp_META_LogFeatures: TRUE only for the COLLECT run
input double Inp_META_Threshold   = 0.50;      // Inp_META_Threshold: fallback if model file lacks one
input bool   Inp_META_SizeByScore = false;     // Inp_META_SizeByScore: scale lots by confidence
input string Inp_META_PresetName  = "RRM_ORG"; // Inp_META_PresetName: drives the CSV file names
input double Inp_META_LabelRR     = 1.5;        // Inp_META_LabelRR: LEGACY fallback only (fixed RR x SL label when no TS_outcomes file); B labels on realized BE-or-profit
input int    Inp_META_LabelBars   = 24;         // Inp_META_LabelBars: LEGACY fallback only (fixed time-barrier when no TS_outcomes file)

//==================== FILE NAMES (derived from preset) =============
// Key files by preset + chart symbol + chart timeframe, e.g. RRM_ORG_EURUSD_M1.
// EnumToString(PERIOD_M1)="PERIOD_M1" -> substr(7) -> "M1"; works for every TF.
string MetaTFStr()      { return StringSubstr(EnumToString((ENUM_TIMEFRAMES)_Period), 7); }
string MetaKey()        { return Inp_META_PresetName + "_" + _Symbol + "_" + MetaTFStr(); }
string MetaEventsFile() { return "TS_events_"  + MetaKey() + ".csv"; }
string MetaOutcomesFile(){ return "TS_outcomes_"+ MetaKey() + ".csv"; } // B: realized exit per TS event
string MetaModelFile()  { return "MetaModel_"  + MetaKey() + ".csv"; }

//====================================================================
// >>> PARAMETER SOURCE <<<
// Signal-side indicators read the LIVE preset inputs from SEA_Inputs.mqh.
// If your preset uses different input NAMES than these, change only the
// right-hand sides below (once). Everything else follows automatically.
//====================================================================
int    MetaEma1Period() { return Inp_RRM_ORG_Ema1Period;   }   // e.g. 5
int    MetaEma2Period() { return Inp_RRM_ORG_Ema2Period;   }   // e.g. 13
int    MetaEma3Period() { return Inp_RRM_ORG_Ema3Period;   }   // e.g. 34
int    MetaEma4Period() { return Inp_RRM_ORG_Ema4Period;   }   // e.g. 89
int    MetaMacdFast()   { return Inp_RRM_ORG_DPI_MacdFast;  }   // DPI core fast (e.g. 8)
int    MetaMacdSlow()   { return Inp_RRM_ORG_DPI_MacdSlow;  }   // DPI core slow (e.g. 13)
int    MetaCciPeriod()  { return Inp_RRM_ORG_DPI_CCI_Period;}   // DPI CCI reset (e.g. 13)
// DPI Red/signal EMA period — the counterpart the histogram subtracts. Was hard-coded 1
// in the iMACD handle, which made SIGNAL==MAIN (EMA period 1 is identity) so macd_hist was
// identically 0 on every bar (dead feature). Mirror the live DPI Red line instead.
int    MetaRedPeriod()
{
   switch(Inp_RRM_ORG_DPI_RedSignalType)
   {
      case 1:  return Inp_RRM_ORG_DPI_RedEMA_A;
      case 2:  return Inp_RRM_ORG_DPI_RedEMA_B;
      case 4:  return Inp_RRM_ORG_DPI_RedEMA_D;
      case 5:  return Inp_RRM_ORG_DPI_RedEMA_C; // Double: use C as the histogram proxy
      default: return Inp_RRM_ORG_DPI_RedEMA_C; // type 3 (RRM_ORG default) = EMA(13) of Blue
   }
}
double MetaPsarStep()   { return Inp_RRM_ORG_PsarStep;      }   // e.g. 0.05
double MetaPsarMax()    { return Inp_RRM_ORG_PsarMax;       }   // e.g. 0.5

//==================== INDICATOR HANDLES (lazy) =====================
int  h_atr=INVALID_HANDLE, h_adx=INVALID_HANDLE, h_rsi=INVALID_HANDLE,
     h_cci=INVALID_HANDLE, h_macd=INVALID_HANDLE, h_psar=INVALID_HANDLE,
     h_sto=INVALID_HANDLE, h_bb=INVALID_HANDLE,  h_mfi=INVALID_HANDLE,
     h_e1=INVALID_HANDLE,  h_e2=INVALID_HANDLE,  h_e3=INVALID_HANDLE, h_e4=INVALID_HANDLE;
bool g_meta_init = false;

bool MetaEnsureInit()
{
   if(g_meta_init) return true;
   // signal-side: driven by LIVE preset inputs
   h_e1  = iMA(_Symbol, PERIOD_CURRENT, MetaEma1Period(), 0, MODE_EMA, PRICE_CLOSE);
   h_e2  = iMA(_Symbol, PERIOD_CURRENT, MetaEma2Period(), 0, MODE_EMA, PRICE_CLOSE);
   h_e3  = iMA(_Symbol, PERIOD_CURRENT, MetaEma3Period(), 0, MODE_EMA, PRICE_CLOSE);
   h_e4  = iMA(_Symbol, PERIOD_CURRENT, MetaEma4Period(), 0, MODE_EMA, PRICE_CLOSE);
   h_macd= iMACD(_Symbol, PERIOD_CURRENT, MetaMacdFast(), MetaMacdSlow(), MetaRedPeriod(), PRICE_CLOSE);
   h_cci = iCCI(_Symbol, PERIOD_CURRENT, MetaCciPeriod(), PRICE_TYPICAL);
   h_psar= iSAR(_Symbol, PERIOD_CURRENT, MetaPsarStep(), MetaPsarMax());
   // context / ranging gauges: ALWAYS measured (independent of preset toggles)
   h_atr = iATR(_Symbol, PERIOD_CURRENT, 14);
   h_adx = iADX(_Symbol, PERIOD_CURRENT, 14);
   h_rsi = iRSI(_Symbol, PERIOD_CURRENT, 14, PRICE_CLOSE);
   h_sto = iStochastic(_Symbol, PERIOD_CURRENT, 5, 3, 3, MODE_SMA, STO_LOWHIGH);
   h_bb  = iBands(_Symbol, PERIOD_CURRENT, 20, 0, 2.0, PRICE_CLOSE);
   h_mfi = iMFI(_Symbol, PERIOD_CURRENT, 14, VOLUME_TICK);
   g_meta_init = (h_atr!=INVALID_HANDLE && h_macd!=INVALID_HANDLE && h_e4!=INVALID_HANDLE);
   return g_meta_init;
}

double MBuf(int handle, int buf, int shift)
{
   double a[];
   if(handle==INVALID_HANDLE) return 0.0;
   if(CopyBuffer(handle, buf, shift, 1, a) < 1) return 0.0;
   return a[0];
}

double MetaRetVol(int nbars)
{
   double s=0.0, s2=0.0; int cnt=0;
   for(int i=1; i<=nbars; i++)
   {
      double a=iClose(_Symbol,PERIOD_CURRENT,i);
      double b=iClose(_Symbol,PERIOD_CURRENT,i+1);
      if(b>0.0) { double r=(a-b)/b; s+=r; s2+=r*r; cnt++; }
   }
   if(cnt<2) return 0.0;
   double m=s/cnt, v=s2/cnt - m*m;
   return (v>0.0) ? MathSqrt(v) : 0.0;
}

//====================================================================
// Feature vector — identical for logging AND scoring, universal across
// presets. RANGING-MARKET gauges (adx, bb_width_atr, atr, ret_vol_20,
// ema_fan_atr) are here on purpose so the model can learn "ranging =
// skip" even though PRESET_RRM_ORG leaves ADX/BB disabled for voting.
// To add your own ranging indicator: add one line, then re-train.
//====================================================================
int MetaBuildFeatures(string &names[], double &vals[])
{
   MetaEnsureInit();
   ArrayResize(names, 48);
   ArrayResize(vals,  48);
   int n = 0;

   double atr = MBuf(h_atr,0,1); if(atr<=0.0) atr=_Point;
   double c1  = iClose(_Symbol,PERIOD_CURRENT,1);
   double o1  = iOpen (_Symbol,PERIOD_CURRENT,1);
   double h1  = iHigh (_Symbol,PERIOD_CURRENT,1);
   double l1  = iLow  (_Symbol,PERIOD_CURRENT,1);
   double rng = (h1-l1); if(rng<=0.0) rng=_Point;
   double e1=MBuf(h_e1,0,1), e2=MBuf(h_e2,0,1), e3=MBuf(h_e3,0,1), e4=MBuf(h_e4,0,1);

   // --- structure (EMA fan / bias) ---
   names[n]="bias_dir";            vals[n]=(e3>e4)?1.0:((e3<e4)?-1.0:0.0);      n++;
   names[n]="ema_fan_atr";         vals[n]=(e1-e4)/atr;                          n++; // ranging tell: fan collapses
   names[n]="dist_close_ema1_atr"; vals[n]=(c1-e1)/atr;                          n++;
   names[n]="ema1_slope_atr";      vals[n]=(e1-MBuf(h_e1,0,2))/atr;              n++;
   names[n]="ema3_slope_atr";      vals[n]=(e3-MBuf(h_e3,0,2))/atr;              n++;

   // --- momentum (DPI core = MACD + CCI, from live inputs) ---
   names[n]="macd_hist";           vals[n]=MBuf(h_macd,0,1)-MBuf(h_macd,1,1);   n++;
   names[n]="cci";                 vals[n]=MBuf(h_cci,0,1);                      n++;

   // --- PSAR (from live inputs) ---
   double sar = MBuf(h_psar,0,1);
   names[n]="psar_side";           vals[n]=(c1>sar)?1.0:-1.0;                    n++;
   names[n]="psar_dist_atr";       vals[n]=MathAbs(c1-sar)/atr;                  n++;

   // --- candle body ---
   names[n]="body_ratio";          vals[n]=MathAbs(c1-o1)/rng;                   n++;

   // --- ranging / context gauges (ALWAYS measured) ---
   names[n]="adx";                 vals[n]=MBuf(h_adx,0,1);                      n++; // <25 ~ ranging
   names[n]="di_spread";           vals[n]=MBuf(h_adx,1,1)-MBuf(h_adx,2,1);      n++; // +DI minus -DI
   names[n]="bb_width_atr";        vals[n]=(MBuf(h_bb,1,1)-MBuf(h_bb,2,1))/atr;  n++; // tight = ranging
   names[n]="rsi";                 vals[n]=MBuf(h_rsi,0,1);                      n++;
   names[n]="stoch";               vals[n]=MBuf(h_sto,0,1);                      n++;
   names[n]="mfi";                 vals[n]=MBuf(h_mfi,0,1);                      n++;
   names[n]="atr";                 vals[n]=atr;                                  n++;
   names[n]="bar_range_atr";       vals[n]=rng/atr;                             n++;
   names[n]="ret_vol_20";          vals[n]=MetaRetVol(20);                       n++; // low = quiet/ranging
   names[n]="spread_pts";          vals[n]=(double)SymbolInfoInteger(_Symbol,SYMBOL_SPREAD); n++;

   MqlDateTime dt; TimeToStruct(iTime(_Symbol,PERIOD_CURRENT,1), dt);
   names[n]="hour";                vals[n]=(double)dt.hour;                      n++;
   names[n]="dow";                 vals[n]=(double)dt.day_of_week;               n++;

   ArrayResize(names, n);
   ArrayResize(vals,  n);
   return n;
}

//==================== LOGGING (COLLECT mode) ========================
// Dedup state at FILE SCOPE (Spec §7b: globals, no static locals). Minimal:
// a single monotonic "newest event_time already in the file" — no arrays, no
// ArraySort, no binary search (keeps the compile surface tiny). Reset per run.
datetime _dd_last  = 0;
string   _dd_file  = "";
bool     _dd_ready = false;

void LogTSEvent(int direction, double ref_price, double sl_price)
{
   string names[]; double vals[];
   int n = MetaBuildFeatures(names, vals);

   double sl_dist = MathAbs(ref_price - sl_price);
   double tp_dist = sl_dist * Inp_META_LabelRR;
   int    tbar    = Inp_META_LabelBars;

   string   fname    = MetaEventsFile();
   datetime bar_time = iTime(_Symbol, PERIOD_CURRENT, 1);

   // DURABILITY: write to the shared Common\Files via FILE_COMMON (outside the
   // per-run tester sandbox, so it survives across runs). If the shared folder
   // isn't there yet under Wine, FolderCreate + retry; if FILE_COMMON is still
   // unavailable, fall back to the sandbox so the run is not lost, and warn.
   int  common_flags = FILE_COMMON|FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI;
   int  local_flags  =             FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI;
   bool use_common   = true;
   bool existed      = FileIsExist(fname, FILE_COMMON);
   int  h            = FileOpen(fname, common_flags, ',');
   if(h == INVALID_HANDLE)
   {
      FolderCreate("_ensure", FILE_COMMON);
      existed = FileIsExist(fname, FILE_COMMON);
      h       = FileOpen(fname, common_flags, ',');
   }
   if(h == INVALID_HANDLE)
   {
      use_common = false;
      PrintFormat("[META] FILE_COMMON unavailable (err=%d) - FALLING BACK to sandbox; will NOT survive next run.",
                  GetLastError());
      existed = FileIsExist(fname);
      h       = FileOpen(fname, local_flags, ',');
      if(h == INVALID_HANDLE)
      {
         PrintFormat("[META] CANNOT OPEN %s at all (err=%d)", fname, GetLastError());
         return;
      }
   }

   // one-time dedup seed: remember the newest event_time already in the file
   if(!_dd_ready || _dd_file != fname)
   {
      _dd_ready = true; _dd_file = fname; _dd_last = 0;
      if(existed)
      {
         FileSeek(h, 0, SEEK_SET);
         bool first = true;
         while(!FileIsEnding(h))
         {
            string c0 = FileReadString(h);
            while(!FileIsLineEnding(h) && !FileIsEnding(h)) FileReadString(h);
            if(first) { first = false; continue; }   // skip header row
            datetime t = StringToTime(c0);
            if(t > _dd_last) _dd_last = t;
         }
      }
   }

   // skip a bar already logged (re-collect of an overlapping range appends nothing)
   if(existed && bar_time <= _dd_last)
   {
      FileClose(h);
      return;
   }

   // append
   FileSeek(h, 0, SEEK_END);
   if(!existed)
   {
      string hdr = "event_time,symbol,preset,direction,sl_dist,tp_dist,time_barrier_bars";
      for(int i=0;i<n;i++) hdr += "," + names[i];
      FileWrite(h, hdr);
   }
   string row = TimeToString(bar_time, TIME_DATE|TIME_MINUTES) + "," +
                _Symbol + "," + Inp_META_PresetName + "," + IntegerToString(direction) + "," +
                DoubleToString(sl_dist,_Digits) + "," + DoubleToString(tp_dist,_Digits) + "," +
                IntegerToString(tbar);
   for(int i=0;i<n;i++) row += "," + DoubleToString(vals[i], 8);
   FileWrite(h, row);
   FileClose(h);
   if(bar_time > _dd_last) _dd_last = bar_time;

   static int _meta_rows = 0;
   if(++_meta_rows == 1)
      PrintFormat("[META] logging events -> %s\\%s (durable=%s)",
                  use_common ? TerminalInfoString(TERMINAL_COMMONDATA_PATH)
                             : TerminalInfoString(TERMINAL_DATA_PATH) + "\\MQL5\\Files",
                  fname, use_common ? "YES" : "NO");
}

//==================== OUTCOME LOGGING (COLLECT mode, B) =============
// One row per CLOSED trade, keyed by the SAME event_time LogTSEvent wrote, so the
// trainer joins events<->outcomes and labels on the REAL exit (BE-or-profit) instead
// of a synthetic RR x SL barrier the strategy never trades to. realized_r is price-
// based and lot-independent: dir*(exit-entry)/|entry-initial_sl|. be_or_better is the
// NET result (profit+swap+commission >= 0), which is the operator's definition of a
// good RRM trade. Called from CTradeExecutor at DEAL_ENTRY_OUT.
void LogTSOutcome(datetime ev_time, double entry, double init_sl, double exit_px,
                  int direction, double net_pl, string reason)
{
   double risk       = MathAbs(entry - init_sl);
   double realized_r = (risk > 0.0) ? (direction * (exit_px - entry) / risk) : 0.0;
   int    be         = (net_pl >= 0.0) ? 1 : 0;

   string fname   = MetaOutcomesFile();
   int  common_flags = FILE_COMMON|FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI;
   int  local_flags  =             FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI;
   bool use_common   = true;
   bool existed      = FileIsExist(fname, FILE_COMMON);
   int  h            = FileOpen(fname, common_flags, ',');
   if(h == INVALID_HANDLE)
   {
      FolderCreate("_ensure", FILE_COMMON);
      existed = FileIsExist(fname, FILE_COMMON);
      h       = FileOpen(fname, common_flags, ',');
   }
   if(h == INVALID_HANDLE)
   {
      use_common = false;
      existed    = FileIsExist(fname);
      h          = FileOpen(fname, local_flags, ',');
      if(h == INVALID_HANDLE)
      {
         PrintFormat("[META] CANNOT OPEN outcomes %s (err=%d)", fname, GetLastError());
         return;
      }
   }
   FileSeek(h, 0, SEEK_END);
   if(!existed)
      FileWrite(h, "event_time,entry_price,initial_sl,exit_price,direction,realized_r,net_pl,be_or_better,exit_reason");
   FileWrite(h,
      TimeToString(ev_time, TIME_DATE|TIME_MINUTES) + "," +
      DoubleToString(entry,   _Digits) + "," +
      DoubleToString(init_sl, _Digits) + "," +
      DoubleToString(exit_px, _Digits) + "," +
      IntegerToString(direction)       + "," +
      DoubleToString(realized_r, 6)     + "," +
      DoubleToString(net_pl, 2)         + "," +
      IntegerToString(be)               + "," +
      reason);
   FileClose(h);
}

//==================== MODEL (lazy load) =============================
#define META_MAX 64
string g_mn[META_MAX]; double g_mmean[META_MAX], g_mstd[META_MAX], g_mw[META_MAX];
int    g_mcount=0; double g_mb0=0.0, g_mthr=0.5;
bool   g_mloaded=false, g_mtried=false;

bool MetaLoadModel()
{
   g_mtried = true; g_mcount = 0; g_mloaded = false;
   string fname = MetaModelFile();
   // NON-common — the trainer writes MetaModel next to the events file (MQL5\Files).
   int h = FileOpen(fname, FILE_READ|FILE_CSV|FILE_ANSI, ',');
   if(h==INVALID_HANDLE) { Print("META: no model ", fname, " — gate inert"); return false; }
   while(!FileIsEnding(h))
   {
      string tag = FileReadString(h);
      if(tag=="")               continue;
      if(tag=="INTERCEPT")       g_mb0  = StringToDouble(FileReadString(h));
      else if(tag=="THRESHOLD")  g_mthr = StringToDouble(FileReadString(h));
      else if(tag=="FEATURE" && g_mcount<META_MAX)
      {
         g_mn[g_mcount]    = FileReadString(h);
         g_mmean[g_mcount] = StringToDouble(FileReadString(h));
         g_mstd[g_mcount]  = StringToDouble(FileReadString(h));
         g_mw[g_mcount]    = StringToDouble(FileReadString(h));
         g_mcount++;
      }
   }
   FileClose(h);
   g_mloaded = (g_mcount>0);
   if(g_mloaded) PrintFormat("META: loaded %d features from %s (thr=%.3f)", g_mcount, fname, g_mthr);
   return g_mloaded;
}

double MetaScore()
{
   string names[]; double vals[];
   int n = MetaBuildFeatures(names, vals);
   double z = g_mb0;
   for(int i=0;i<g_mcount;i++)
   {
      double raw=0.0; bool found=false;
      for(int j=0;j<n;j++) if(names[j]==g_mn[i]) { raw=vals[j]; found=true; break; }
      if(!found) continue;
      double zi = (g_mstd[i]==0.0) ? 0.0 : (raw - g_mmean[i]) / g_mstd[i];
      z += g_mw[i] * zi;
   }
   return 1.0 / (1.0 + MathExp(-z));
}

//==================== THE GATE ======================================
// returns true = allow trade; size_mult scales the lot when enabled.
bool EvaluateMetaGate(double &size_mult)
{
   size_mult = 1.0;
   if(!Inp_META_Enabled) return true;               // OFF = today's behaviour
   if(!g_mtried) MetaLoadModel();
   if(!g_mloaded) return true;                       // no model => inert (never blocks)
   double s   = MetaScore();
   double thr = (g_mthr>0.0 ? g_mthr : Inp_META_Threshold);
   if(s < thr) return false;                         // veto a TS the gate distrusts
   if(Inp_META_SizeByScore) size_mult = 0.5 + s;     // 0.5x .. 1.5x
   return true;
}

#endif // SEA_METAGATE_MQH
//+------------------------------------------------------------------+
