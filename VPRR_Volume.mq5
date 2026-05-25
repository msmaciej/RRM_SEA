//  SAVE AS UTF-16 LE WITH BOM
//+------------------------------------------------------------------+
//| VPRR_Volume.mq5                                                   |
//| Volume Pullback-Recovery Ratio — standalone sub-window indicator  |
//|                                                                    |
//| Visualises the same volume logic used by the SEA VPRR voter.      |
//| Recalculates at bar close only (shift=1) — no per-tick CPU cost.  |
//|                                                                    |
//| Settings must match EA inputs manually:                           |
//|   Inp_MinRatio      = Inp_RRM_ORG_VPRR_MinRatio                  |
//|   Inp_RecoveryBars  = Inp_RRM_ORG_VPRR_RecoveryBars              |
//|   Inp_PullbackRatio = Inp_RRM_ORG_LayerPullbackRatio (global)    |
//|   Inp_RecoveryRatio = Inp_RRM_ORG_LayerRecoveryRatio (global)    |
//|                                                                    |
//| Colour key:                                                        |
//|   Grey       = IDLE  (normal volume, no active cycle)            |
//|   Orange     = PULLBACK  (volume drying up below baseline)       |
//|   Bright Green = RECOVERY + ratio >= MinRatio  (PASS)           |
//|   Dark Red   = RECOVERY + ratio <  MinRatio  (FAIL)             |
//|   White line = Rolling SMA baseline (Inp_BaselinePeriod bars)    |
//|   Gold dash  = Baseline × MinRatio  (threshold)                  |
//+------------------------------------------------------------------+
#property strict
#property version   "1.01"
#property indicator_separate_window
#property indicator_buffers 7
#property indicator_plots   5

// Plot 0: Idle volume (grey)
#property indicator_label1  "Vol_Idle"
#property indicator_type1   DRAW_HISTOGRAM
#property indicator_color1  clrDimGray
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

// Plot 1: Pullback volume (orange)
#property indicator_label2  "Vol_Pullback"
#property indicator_type2   DRAW_HISTOGRAM
#property indicator_color2  clrDarkOrange
#property indicator_style2  STYLE_SOLID
#property indicator_width2  2

// Plot 2: Recovery pass (bright green)
#property indicator_label3  "Vol_RecovPass"
#property indicator_type3   DRAW_HISTOGRAM
#property indicator_color3  clrLimeGreen
#property indicator_style3  STYLE_SOLID
#property indicator_width3  2

// Plot 3: Recovery fail (dark red)
#property indicator_label4  "Vol_RecovFail"
#property indicator_type4   DRAW_HISTOGRAM
#property indicator_color4  clrFireBrick
#property indicator_style4  STYLE_SOLID
#property indicator_width4  2

// Plot 4: Rolling average baseline (white line)
#property indicator_label5  "Vol_Baseline"
#property indicator_type5   DRAW_LINE
#property indicator_color5  clrWhite
#property indicator_style5  STYLE_SOLID
#property indicator_width5  1

#property indicator_level1      0.0
#property indicator_levelcolor  clrDimGray
#property indicator_levelstyle  STYLE_DOT
#property indicator_levelwidth  1

//--- Inputs
input int    Inp_BaselinePeriod  = 20;    // Baseline: SMA period for rolling volume average
input double Inp_MinRatio        = 1.0;   // VPRR: MinRatio — match Inp_RRM_ORG_VPRR_MinRatio
input int    Inp_RecoveryBars    = 3;     // VPRR: recovery bars — match Inp_RRM_ORG_VPRR_RecoveryBars
input double Inp_PullbackRatio   = 0.5;   // Layer: pullback vol threshold (fraction of baseline)
input double Inp_RecoveryRatio   = 0.3;   // Layer: recovery vol threshold (fraction of baseline)
input bool   Inp_ForceRealVol    = false; // Volume: force real volume (false = auto-probe like EA)
input bool   Inp_ShowThreshLine  = true;  // Display: show MinRatio threshold line
input bool   Inp_ShowLabels      = true;  // Display: show ratio + state labels

//--- Indicator buffers
double buf_idle[];
double buf_pullback[];
double buf_recov_pass[];
double buf_recov_fail[];
double buf_baseline[];
double buf_vol_raw[];    // INDICATOR_CALCULATIONS — not plotted
double buf_state[];      // INDICATOR_CALCULATIONS — not plotted

//--- State machine (persisted between OnCalculate calls)
enum EVPRRState { STATE_IDLE=0, STATE_PULLBACK=1, STATE_RECOVERY=2 };

EVPRRState g_state        = STATE_IDLE;
double     g_pb_vol_sum   = 0.0;
int        g_pb_vol_cnt   = 0;
double     g_rec_vol_sum  = 0.0;
int        g_rec_vol_cnt  = 0;
double     g_vprr_ratio   = 0.0;

bool       g_use_real_vol = false;
int        g_win_num      = -1;   // Subwindow index — resolved on first OnCalculate
string     g_vol_source   = "TICK";
string     g_obj_prefix   = "VPRR_";
datetime   g_last_bar     = 0;   // Bar-close gate: skip recalc on same-bar ticks

//+------------------------------------------------------------------+
int OnInit()
{
   // ── Probe volume source (mirrors GetVPRRRecommendedMode in EA) ──
   if(Inp_ForceRealVol)
   {
      g_use_real_vol = true;
      g_vol_source   = "REAL";
   }
   else
   {
      long probe[];
      g_use_real_vol = (CopyRealVolume(_Symbol, PERIOD_CURRENT, 1, 3, probe) == 3 && probe[0] > 0);
      g_vol_source   = g_use_real_vol ? "REAL" : "TICK";
   }

   PrintFormat("[VPRR_Volume] %s | Source: %s | Baseline: %d | MinRatio: %.2f",
               _Symbol, g_vol_source, Inp_BaselinePeriod, Inp_MinRatio);

   // ── Buffer registration ─────────────────────────────────────────
   SetIndexBuffer(0, buf_idle,       INDICATOR_DATA);
   SetIndexBuffer(1, buf_pullback,   INDICATOR_DATA);
   SetIndexBuffer(2, buf_recov_pass, INDICATOR_DATA);
   SetIndexBuffer(3, buf_recov_fail, INDICATOR_DATA);
   SetIndexBuffer(4, buf_baseline,   INDICATOR_DATA);
   SetIndexBuffer(5, buf_vol_raw,    INDICATOR_CALCULATIONS);
   SetIndexBuffer(6, buf_state,      INDICATOR_CALCULATIONS);

   // Ensure buffers are indexed oldest→newest (not series) — required for
   // histogram indicators in MQL5 separate-window mode.
   ArraySetAsSeries(buf_idle,       false);
   ArraySetAsSeries(buf_pullback,   false);
   ArraySetAsSeries(buf_recov_pass, false);
   ArraySetAsSeries(buf_recov_fail, false);
   ArraySetAsSeries(buf_baseline,   false);
   ArraySetAsSeries(buf_vol_raw,    false);
   ArraySetAsSeries(buf_state,      false);

   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, 0.0);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, 0.0);
   PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, 0.0);
   PlotIndexSetDouble(3, PLOT_EMPTY_VALUE, 0.0);
   PlotIndexSetDouble(4, PLOT_EMPTY_VALUE, 0.0);

   IndicatorSetString(INDICATOR_SHORTNAME,
      StringFormat("VPRR Vol  [%s | Base:%d | Ratio:%.1f]",
                   g_vol_source, Inp_BaselinePeriod, Inp_MinRatio));

   g_last_bar = 0;  // Force full recalc on first call
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   RemoveObjects();
}

//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double   &open[],
                const double   &high[],
                const double   &low[],
                const double   &close[],
                const long     &tick_volume[],
                const long     &volume[],
                const int      &spread[])
{
   if(rates_total < Inp_BaselinePeriod + 2) return 0;

   // ── Resolve subwindow number on first call ───────────────────────
   if(g_win_num < 0)
      g_win_num = ChartWindowFind();

   // ── Bar-close gate: skip all work on intra-bar ticks ────────────
   // rates_total - 1 is the forming (current) bar.
   // rates_total - 2 is the last closed bar.
   // We only recalculate when a new closed bar appears.
   datetime current_bar = time[rates_total - 2];
   bool is_new_bar      = (current_bar != g_last_bar);
   bool is_full_recalc  = (prev_calculated <= 1);

   if(!is_new_bar && !is_full_recalc)
      return prev_calculated;  // Same bar — nothing to do

   g_last_bar = current_bar;

   // ── Determine start bar ─────────────────────────────────────────
   // Full recalc: start from beginning.
   // Incremental: roll back enough bars to rebuild state context,
   // then re-run the state machine forward from there.
   // We always exclude the forming bar (rates_total-1) — shift=1 only.
   int last_closed = rates_total - 2;  // Last bar we process
   int start;

   if(is_full_recalc)
   {
      start = Inp_BaselinePeriod;
      // Reset persisted state
      g_state = STATE_IDLE; g_pb_vol_sum = 0; g_pb_vol_cnt = 0;
      g_rec_vol_sum = 0; g_rec_vol_cnt = 0; g_vprr_ratio = 0.0;
   }
   else
   {
      // Roll back enough to reconstruct state context reliably.
      // Context window = baseline period + a few recovery cycles.
      int context = Inp_BaselinePeriod + Inp_RecoveryBars * 4;
      start = MathMax(Inp_BaselinePeriod, last_closed - context);
      // Reset state — will rebuild from 'start' forward
      g_state = STATE_IDLE; g_pb_vol_sum = 0; g_pb_vol_cnt = 0;
      g_rec_vol_sum = 0; g_rec_vol_cnt = 0; g_vprr_ratio = 0.0;
   }

   // ── Pass 1: raw volume ──────────────────────────────────────────
   for(int i = start; i <= last_closed; i++)
      buf_vol_raw[i] = g_use_real_vol ? (double)volume[i] : (double)tick_volume[i];

   // ── Pass 2: SMA baseline ────────────────────────────────────────
   for(int i = start; i <= last_closed; i++)
   {
      if(i < Inp_BaselinePeriod - 1) { buf_baseline[i] = 0.0; continue; }
      double sum = 0.0;
      for(int k = 0; k < Inp_BaselinePeriod; k++) sum += buf_vol_raw[i - k];
      buf_baseline[i] = sum / Inp_BaselinePeriod;
   }

   // ── Pass 3: state machine + histogram assignment ────────────────
   for(int i = start; i <= last_closed; i++)
   {
      buf_idle[i] = buf_pullback[i] = buf_recov_pass[i] = buf_recov_fail[i] = 0.0;

      double vol  = buf_vol_raw[i];
      double base = buf_baseline[i];

      if(base <= 0.0) { buf_idle[i] = vol; continue; }

      double low_thresh = base * (1.0 - Inp_PullbackRatio);  // Volume dries up below this
      double rec_thresh = base * Inp_RecoveryRatio;            // Volume recovers above this

      // ── State transitions ────────────────────────────────────────
      if(g_state == STATE_IDLE)
      {
         if(vol < low_thresh)
         {
            g_state = STATE_PULLBACK;
            g_pb_vol_sum = vol; g_pb_vol_cnt = 1;
            g_rec_vol_sum = 0.0; g_rec_vol_cnt = 0;
            g_vprr_ratio = 0.0;
         }
      }
      else if(g_state == STATE_PULLBACK)
      {
         if(vol >= rec_thresh)
         {
            g_state = STATE_RECOVERY;
            g_rec_vol_sum = vol; g_rec_vol_cnt = 1;
            if(g_pb_vol_cnt > 0)
               g_vprr_ratio = (g_rec_vol_sum / g_rec_vol_cnt) / (g_pb_vol_sum / g_pb_vol_cnt);
         }
         else
         {
            g_pb_vol_sum += vol; g_pb_vol_cnt++;
         }
      }
      else // STATE_RECOVERY
      {
         if(vol < low_thresh)
         {
            // Relapse into pullback
            g_state = STATE_PULLBACK;
            g_pb_vol_sum = vol; g_pb_vol_cnt = 1;
            g_rec_vol_sum = 0.0; g_rec_vol_cnt = 0;
            g_vprr_ratio = 0.0;
         }
         else
         {
            if(g_rec_vol_cnt < Inp_RecoveryBars)
            {
               g_rec_vol_sum += vol; g_rec_vol_cnt++;
               if(g_pb_vol_cnt > 0)
                  g_vprr_ratio = (g_rec_vol_sum / g_rec_vol_cnt) / (g_pb_vol_sum / g_pb_vol_cnt);
            }
            // Recovery complete once enough bars measured and volume normalised
            if(g_rec_vol_cnt >= Inp_RecoveryBars && vol >= base * 0.8)
               g_state = STATE_IDLE;
         }
      }

      buf_state[i] = (double)g_state;

      // ── Histogram assignment ─────────────────────────────────────
      switch(g_state)
      {
         case STATE_IDLE:     buf_idle[i]       = vol; break;
         case STATE_PULLBACK: buf_pullback[i]   = vol; break;
         case STATE_RECOVERY:
            if(g_vprr_ratio >= Inp_MinRatio) buf_recov_pass[i] = vol;
            else                             buf_recov_fail[i] = vol;
            break;
      }
   }

   // ── Labels + threshold line (update once per new bar) ───────────
   if(Inp_ShowLabels)
      UpdateLabels();

   if(Inp_ShowThreshLine)
      UpdateThresholdLine(buf_baseline[last_closed]);

   return rates_total;
}

//+------------------------------------------------------------------+
void UpdateLabels()
{
   string ratio_text = StringFormat("VPRR: %.2f  (min %.2f)  %s  [%s]",
                                    g_vprr_ratio, Inp_MinRatio,
                                    g_vprr_ratio >= Inp_MinRatio ? "PASS" : "FAIL",
                                    g_vol_source);
   color ratio_clr = (g_state == STATE_RECOVERY)
                     ? (g_vprr_ratio >= Inp_MinRatio ? clrLimeGreen : clrOrangeRed)
                     : clrSilver;

   string state_txt; color state_clr;
   switch(g_state)
   {
      case STATE_PULLBACK: state_txt = "PULLBACK"; state_clr = clrDarkOrange; break;
      case STATE_RECOVERY: state_txt = "RECOVERY"; state_clr = clrLimeGreen;  break;
      default:             state_txt = "IDLE";     state_clr = clrDimGray;    break;
   }

   SetLabel(g_obj_prefix + "ratio", ratio_text, ratio_clr, 8, 20);
   SetLabel(g_obj_prefix + "state", state_txt,  state_clr, 8, 38);
}

//+------------------------------------------------------------------+
void SetLabel(const string name, const string text, color clr, int x, int y)
{
   if(g_win_num < 0) return;  // Window not yet resolved
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_LABEL, g_win_num, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER,    CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString (0, name, OBJPROP_TEXT,      text);
   ObjectSetInteger(0, name, OBJPROP_COLOR,     clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,  9);
   ObjectSetString (0, name, OBJPROP_FONT,      "Courier New");
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE,false);
}

//+------------------------------------------------------------------+
void UpdateThresholdLine(double baseline_val)
{
   if(baseline_val <= 0.0) return;
   double thresh = baseline_val * Inp_MinRatio;
   string name   = g_obj_prefix + "thresh";
   if(g_win_num < 0) return;  // Window not yet resolved

   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_HLINE, g_win_num, 0, thresh);
      ObjectSetInteger(0, name, OBJPROP_COLOR,     clrGold);
      ObjectSetInteger(0, name, OBJPROP_STYLE,     STYLE_DASH);
      ObjectSetInteger(0, name, OBJPROP_WIDTH,     1);
      ObjectSetString (0, name, OBJPROP_TOOLTIP,
         StringFormat("VPRR threshold  baseline × %.2f", Inp_MinRatio));
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   }
   else
      ObjectSetDouble(0, name, OBJPROP_PRICE, thresh);
}

//+------------------------------------------------------------------+
void RemoveObjects()
{
   ObjectDelete(0, g_obj_prefix + "ratio");
   ObjectDelete(0, g_obj_prefix + "state");
   ObjectDelete(0, g_obj_prefix + "thresh");
}
//+------------------------------------------------------------------+
