//+------------------------------------------------------------------+
//| SEA_MetaGate.mqh — optional ML "second opinion" for the RRM EA    |
//|                                                                    |
//| Pure MQL5. No ONNX, no libraries. The model is just numbers read   |
//| from a CSV; scoring is one dot-product + sigmoid.                  |
//|                                                                    |
//| INTEGRATION (3 places, all marked >>> ADAPT <<<):                  |
//|   1) In OnInit():   if(Inp_META_Enabled) LoadMetaModel();          |
//|   2) In EvaluateTE(), AFTER TS==1 and F-filters pass, BEFORE trade:|
//|        if(Inp_META_LogFeatures) LogTSEvent(etime,dir,sl,tp,tbar);  |
//|        double mult=1.0;                                            |
//|        if(!EvaluateMetaGate(mult)) return;   // gate vetoes trade  |
//|        // then multiply your computed lot size by 'mult'           |
//|   3) Fill in MetaBuildFeatures() with YOUR indicator globals.      |
//+------------------------------------------------------------------+
#property strict

//==================== INPUTS (add to Zone 2 in SEA_Config) ==========
input bool   Inp_META_Enabled     = false;              // false = EA unchanged
input bool   Inp_META_LogFeatures = false;              // true ONLY when collecting
input double Inp_META_Threshold   = 0.50;               // fallback if model has none
input bool   Inp_META_SizeByScore = false;              // scale lots by confidence
input string Inp_META_ModelFile   = "MetaModel_RRM.csv";
input string Inp_META_EventsFile  = "TS_events_RRM.csv";
input string Inp_META_PresetName  = "RRM";

//==================== MODEL STORAGE (globals) =======================
#define META_MAX 64
string g_meta_name[META_MAX];
double g_meta_mean[META_MAX];
double g_meta_std [META_MAX];
double g_meta_w   [META_MAX];
int    g_meta_n   = 0;
double g_meta_b0  = 0.0;
double g_meta_thr = 0.5;
bool   g_meta_ready = false;

//====================================================================
// >>> ADAPT <<<  The ONE function you edit.
// List each feature: a NAME (string) and its CURRENT value at the
// closed bar (shift=1). Used for BOTH logging and scoring, so parity
// is automatic. Replace g_atr / g_rsi_val / ... with YOUR variables.
// Comment out features a given preset doesn't use.
//====================================================================
int MetaBuildFeatures(string &names[], double &vals[])
{
   ArrayResize(names, META_MAX);
   ArrayResize(vals,  META_MAX);
   int n = 0;

   // --- Group B: context (always available) ---
   names[n]="atr";                    vals[n]= g_atr;                          n++;
   names[n]="spread_pts";             vals[n]=(double)SymbolInfoInteger(_Symbol,SYMBOL_SPREAD); n++;
   names[n]="hour";                   vals[n]=(double)TimeHour(iTime(_Symbol,PERIOD_CURRENT,1)); n++;
   names[n]="adx";                    vals[n]= g_adx_val;                      n++;
   names[n]="dist_close_emaFast_atr"; vals[n]=(g_atr==0.0)?0.0:(iClose(_Symbol,PERIOD_CURRENT,1)-g_emaFast)/g_atr; n++;

   // --- Group A: whichever indicators THIS preset enables (raw values) ---
   names[n]="rsi";                    vals[n]= g_rsi_val;                      n++;
   names[n]="cci";                    vals[n]= g_cci_val;                      n++;
   names[n]="dpi_hist";               vals[n]= g_dpi_hist;                     n++;
   // ... add / remove lines to match what you actually log ...

   ArrayResize(names, n);
   ArrayResize(vals,  n);
   return n;
}

//==================== LOGGING (COLLECT mode) ========================
void LogTSEvent(datetime etime, double dir, double sl_dist, double tp_dist, int tbar)
{
   string names[]; double vals[];
   int n = MetaBuildFeatures(names, vals);

   bool existed = FileIsExist(Inp_META_EventsFile, FILE_COMMON);
   int h = FileOpen(Inp_META_EventsFile,
                    FILE_COMMON|FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI, ',');
   if(h == INVALID_HANDLE) { Print("META: cannot open events file"); return; }
   FileSeek(h, 0, SEEK_END);

   if(!existed)
   {
      string hdr = "event_time,symbol,preset,direction,sl_dist,tp_dist,time_barrier_bars";
      for(int i=0;i<n;i++) hdr += "," + names[i];
      FileWrite(h, hdr);
   }
   string row = TimeToString(etime, TIME_DATE|TIME_MINUTES) + "," + _Symbol + "," +
                Inp_META_PresetName + "," + DoubleToString(dir,0) + "," +
                DoubleToString(sl_dist,_Digits) + "," + DoubleToString(tp_dist,_Digits) + "," +
                IntegerToString(tbar);
   for(int i=0;i<n;i++) row += "," + DoubleToString(vals[i], 8);
   FileWrite(h, row);
   FileClose(h);
}

//==================== LOAD MODEL (OnInit) ===========================
bool LoadMetaModel()
{
   g_meta_ready = false; g_meta_n = 0;
   int h = FileOpen(Inp_META_ModelFile,
                    FILE_COMMON|FILE_READ|FILE_CSV|FILE_ANSI, ',');
   if(h == INVALID_HANDLE) { Print("META: no model file — gate stays inert"); return false; }
   while(!FileIsEnding(h))
   {
      string tag = FileReadString(h);
      if(tag == "")            continue;
      if(tag == "INTERCEPT")   g_meta_b0  = StringToDouble(FileReadString(h));
      else if(tag=="THRESHOLD")g_meta_thr = StringToDouble(FileReadString(h));
      else if(tag=="FEATURE" && g_meta_n < META_MAX)
      {
         g_meta_name[g_meta_n] = FileReadString(h);
         g_meta_mean[g_meta_n] = StringToDouble(FileReadString(h));
         g_meta_std [g_meta_n] = StringToDouble(FileReadString(h));
         g_meta_w   [g_meta_n] = StringToDouble(FileReadString(h));
         g_meta_n++;
      }
   }
   FileClose(h);
   g_meta_ready = (g_meta_n > 0);
   PrintFormat("META: loaded %d features, thr=%.3f", g_meta_n, g_meta_thr);
   return g_meta_ready;
}

//==================== SCORE =========================================
double MetaScore()
{
   string names[]; double vals[];
   int n = MetaBuildFeatures(names, vals);
   double z = g_meta_b0;
   for(int i=0;i<g_meta_n;i++)
   {
      double raw = 0.0; bool found = false;
      for(int j=0;j<n;j++)
         if(names[j] == g_meta_name[i]) { raw = vals[j]; found = true; break; }
      if(!found) { Print("META: live value missing for ", g_meta_name[i]); continue; }
      double zi = (g_meta_std[i]==0.0) ? 0.0 : (raw - g_meta_mean[i]) / g_meta_std[i];
      z += g_meta_w[i] * zi;
   }
   return 1.0 / (1.0 + MathExp(-z));   // sigmoid -> 0..1
}

//==================== THE GATE ======================================
// returns true = allow trade. size_mult scales the lot when enabled.
bool EvaluateMetaGate(double &size_mult)
{
   size_mult = 1.0;
   if(!Inp_META_Enabled || !g_meta_ready) return true;   // inert = today's behaviour
   double s   = MetaScore();
   double thr = (g_meta_thr > 0.0 ? g_meta_thr : Inp_META_Threshold);
   if(s < thr) return false;                              // veto a TS the gate distrusts
   if(Inp_META_SizeByScore) size_mult = 0.5 + s;          // e.g. 0.5x .. 1.5x
   return true;
}
//+------------------------------------------------------------------+
