//+------------------------------------------------------------------+
//| SEA_MetaGate.mqh — optional ML "second opinion" for the RRM EA    |
//|                                                                    |
//| SELF-CONTAINED. Computes its OWN indicator values, so it works    |
//| unchanged for ANY preset (RRM_ORG, MA, FPM, TOPINVESTOR, ...).    |
//| No ONNX, no external libraries. Model = numbers in a CSV; scoring  |
//| is one dot-product + sigmoid. Handles + model are lazy-loaded, so  |
//| there is NOTHING to wire in OnInit.                                |
//|                                                                    |
//| Place at:  MQL5\Include\RRMS\SEA_MetaGate.mqh                      |
//| Files go to the terminal COMMON\Files folder.                     |
//+------------------------------------------------------------------+
#ifndef SEA_METAGATE_MQH
#define SEA_METAGATE_MQH
#property strict

//==================== INPUTS =======================================
input bool   Inp_META_Enabled     = false;     // false = EA behaves exactly as today
input bool   Inp_META_LogFeatures = false;     // true ONLY during the collection run
input double Inp_META_Threshold   = 0.50;      // fallback if model file lacks one
input bool   Inp_META_SizeByScore = false;     // scale lots by confidence
input string Inp_META_PresetName  = "RRM_ORG"; // drives the CSV file names
input double Inp_META_LabelRR     = 1.5;        // label TP = RR * SL distance (labels only)
input int    Inp_META_LabelBars   = 24;         // label time-barrier in bars

//==================== FILE NAMES (derived from preset) =============
string MetaEventsFile() { return "TS_events_"  + Inp_META_PresetName + ".csv"; }
string MetaModelFile()  { return "MetaModel_"  + Inp_META_PresetName + ".csv"; }

//==================== INDICATOR HANDLES (lazy) =====================
int  h_atr=INVALID_HANDLE, h_adx=INVALID_HANDLE, h_rsi=INVALID_HANDLE,
     h_cci=INVALID_HANDLE, h_macd=INVALID_HANDLE, h_psar=INVALID_HANDLE,
     h_sto=INVALID_HANDLE, h_bb=INVALID_HANDLE,  h_mfi=INVALID_HANDLE,
     h_e1=INVALID_HANDLE,  h_e2=INVALID_HANDLE,  h_e3=INVALID_HANDLE, h_e4=INVALID_HANDLE;
bool g_meta_init = false;

bool MetaEnsureInit()
{
   if(g_meta_init) return true;
   h_atr = iATR(_Symbol, PERIOD_CURRENT, 14);
   h_adx = iADX(_Symbol, PERIOD_CURRENT, 14);
   h_rsi = iRSI(_Symbol, PERIOD_CURRENT, 14, PRICE_CLOSE);
   h_cci = iCCI(_Symbol, PERIOD_CURRENT, 13, PRICE_TYPICAL);
   h_macd= iMACD(_Symbol, PERIOD_CURRENT, 8, 13, 1, PRICE_CLOSE);   // DPI core = MACD 8/13
   h_psar= iSAR(_Symbol, PERIOD_CURRENT, 0.02, 0.2);
   h_sto = iStochastic(_Symbol, PERIOD_CURRENT, 5, 3, 3, MODE_SMA, STO_LOWHIGH);
   h_bb  = iBands(_Symbol, PERIOD_CURRENT, 20, 0, 2.0, PRICE_CLOSE);
   h_mfi = iMFI(_Symbol, PERIOD_CURRENT, 14, VOLUME_TICK);
   h_e1  = iMA(_Symbol, PERIOD_CURRENT, 5,  0, MODE_EMA, PRICE_CLOSE);
   h_e2  = iMA(_Symbol, PERIOD_CURRENT, 13, 0, MODE_EMA, PRICE_CLOSE);
   h_e3  = iMA(_Symbol, PERIOD_CURRENT, 34, 0, MODE_EMA, PRICE_CLOSE);
   h_e4  = iMA(_Symbol, PERIOD_CURRENT, 89, 0, MODE_EMA, PRICE_CLOSE);
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
// The feature vector — computed identically for logging AND scoring.
// Universal across presets. Add/remove lines freely; the Python side
// auto-detects whatever columns appear.
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

   // --- structure (EMA fan / bias / phase-ish) ---
   names[n]="bias_dir";            vals[n]=(e3>e4)?1.0:((e3<e4)?-1.0:0.0);      n++;
   names[n]="ema_fan_atr";         vals[n]=(e1-e4)/atr;                          n++;
   names[n]="dist_close_ema1_atr"; vals[n]=(c1-e1)/atr;                          n++;
   names[n]="ema1_slope_atr";      vals[n]=(e1-MBuf(h_e1,0,2))/atr;              n++;
   names[n]="ema3_slope_atr";      vals[n]=(e3-MBuf(h_e3,0,2))/atr;              n++;

   // --- momentum (DPI core = MACD 8/13, + CCI) ---
   names[n]="macd_hist";           vals[n]=MBuf(h_macd,0,1)-MBuf(h_macd,1,1);   n++;
   names[n]="cci";                 vals[n]=MBuf(h_cci,0,1);                      n++;

   // --- PSAR ---
   double sar = MBuf(h_psar,0,1);
   names[n]="psar_side";           vals[n]=(c1>sar)?1.0:-1.0;                    n++;
   names[n]="psar_dist_atr";       vals[n]=MathAbs(c1-sar)/atr;                  n++;

   // --- candle body ---
   names[n]="body_ratio";          vals[n]=MathAbs(c1-o1)/rng;                   n++;

   // --- context (universal) ---
   names[n]="adx";                 vals[n]=MBuf(h_adx,0,1);                      n++;
   names[n]="rsi";                 vals[n]=MBuf(h_rsi,0,1);                      n++;
   names[n]="stoch";               vals[n]=MBuf(h_sto,0,1);                      n++;
   names[n]="bb_width_atr";        vals[n]=(MBuf(h_bb,1,1)-MBuf(h_bb,2,1))/atr;  n++;
   names[n]="mfi";                 vals[n]=MBuf(h_mfi,0,1);                      n++;
   names[n]="atr";                 vals[n]=atr;                                  n++;
   names[n]="bar_range_atr";       vals[n]=rng/atr;                             n++;
   names[n]="spread_pts";          vals[n]=(double)SymbolInfoInteger(_Symbol,SYMBOL_SPREAD); n++;
   names[n]="ret_vol_20";          vals[n]=MetaRetVol(20);                       n++;

   MqlDateTime dt; TimeToStruct(iTime(_Symbol,PERIOD_CURRENT,1), dt);
   names[n]="hour";                vals[n]=(double)dt.hour;                      n++;
   names[n]="dow";                 vals[n]=(double)dt.day_of_week;               n++;

   ArrayResize(names, n);
   ArrayResize(vals,  n);
   return n;
}

//==================== LOGGING (COLLECT mode) ========================
void LogTSEvent(int direction, double ref_price, double sl_price)
{
   string names[]; double vals[];
   int n = MetaBuildFeatures(names, vals);

   double sl_dist = MathAbs(ref_price - sl_price);
   double tp_dist = sl_dist * Inp_META_LabelRR;
   int    tbar    = Inp_META_LabelBars;

   string fname   = MetaEventsFile();
   bool   existed = FileIsExist(fname, FILE_COMMON);
   int h = FileOpen(fname, FILE_COMMON|FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI, ',');
   if(h==INVALID_HANDLE) { Print("META: cannot open ", fname); return; }
   FileSeek(h, 0, SEEK_END);

   if(!existed)
   {
      string hdr = "event_time,symbol,preset,direction,sl_dist,tp_dist,time_barrier_bars";
      for(int i=0;i<n;i++) hdr += "," + names[i];
      FileWrite(h, hdr);
   }
   string row = TimeToString(iTime(_Symbol,PERIOD_CURRENT,1), TIME_DATE|TIME_MINUTES) + "," +
                _Symbol + "," + Inp_META_PresetName + "," + IntegerToString(direction) + "," +
                DoubleToString(sl_dist,_Digits) + "," + DoubleToString(tp_dist,_Digits) + "," +
                IntegerToString(tbar);
   for(int i=0;i<n;i++) row += "," + DoubleToString(vals[i], 8);
   FileWrite(h, row);
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
   int h = FileOpen(fname, FILE_COMMON|FILE_READ|FILE_CSV|FILE_ANSI, ',');
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
