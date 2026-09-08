//+------------------------------------------------------------------+
//| SEA_ServerTime_Check.mq5                                         |
//| One-shot diagnostic script: server time, UTC offset, CME session |
//| alignment, and VPRR external symbol probe.                       |
//|                                                                  |
//| USAGE:                                                           |
//|   1. Drag onto any chart (XAUUSD recommended)                    |
//|   2. Set Inp_VPRR_ProxySymbol to your broker's MGC symbol name   |
//|   3. Results appear in Journal AND as on-chart panel             |
//|   4. Panel auto-removes after Inp_DisplaySeconds (default 60s)   |
//|   5. Set Inp_DisplaySeconds=0 to keep panel until script removed |
//+------------------------------------------------------------------+
#property script_show_inputs
#property strict

input string   Inp_VPRR_ProxySymbol  = "MGC";   // Proxy symbol for COMEX volume (e.g. MGC, MGCM26, GC)
input int      Inp_DisplaySeconds    = 60;       // Seconds to show panel (0 = keep until removed)
input ENUM_BASE_CORNER Inp_Corner    = CORNER_LEFT_UPPER; // Panel corner
input int      Inp_X                 = 20;       // Panel X offset (px)
input int      Inp_Y                 = 50;       // Panel Y offset (px)
input int      Inp_FontSize          = 11;       // Font size
input string   Inp_Font              = "Courier New"; // Font

#define PANEL_NAME  "SEA_STC_PANEL"
#define MAX_LINES   40
#define LINE_H      16

//+------------------------------------------------------------------+
void OnStart()
{
   string lines[];
   color  clrs[];
   int    n = 0;

   ArrayResize(lines, MAX_LINES);
   ArrayResize(clrs,  MAX_LINES);

   // ── helpers ──────────────────────────────────────────────────────
   #define ADD(txt, clr) { lines[n] = txt; clrs[n] = clr; n++; }

   color cHead  = clrDodgerBlue;
   color cOk    = clrLimeGreen;
   color cWarn  = clrOrange;
   color cFail  = clrTomato;
   color cInfo  = clrSilver;
   color cLabel = clrGold;

   // ── SECTION 1: Server time ────────────────────────────────────────
   datetime srv_now   = TimeCurrent();
   datetime gmt_now   = TimeGMT();
   int      tz_offset = (int)((long)srv_now - (long)gmt_now) / 3600;
   string   srv_str   = TimeToString(srv_now, TIME_DATE|TIME_SECONDS);
   string   gmt_str   = TimeToString(gmt_now, TIME_DATE|TIME_SECONDS);

   ADD("══ SERVER TIME CHECK ══════════════════",   cHead)
   ADD(StringFormat("  Server time : %s",  srv_str), cInfo)
   ADD(StringFormat("  GMT/UTC     : %s",  gmt_str), cInfo)
   ADD(StringFormat("  TZ offset   : UTC%+d h",  tz_offset), tz_offset == 0 ? cOk : cWarn)
   ADD(" ", cInfo)

   // ── SECTION 2: CME / COMEX session alignment ─────────────────────
   // CME Gold (GC/MGC) electronic session: Sun 18:00 – Fri 17:00 ET
   // Core pit hours: 08:20 – 13:30 ET
   // ET = UTC-5 (EST) or UTC-4 (EDT). We use UTC-5 as conservative baseline.
   int et_offset    = -5;   // EST conservative
   int srv_to_et    = tz_offset + et_offset;  // hours to add to server time to get ET

   MqlDateTime sdt;
   TimeToStruct(srv_now, sdt);
   int srv_hour = sdt.hour;
   int srv_min  = sdt.min;

   // Convert server hour to ET
   int et_hour  = ((srv_hour + srv_to_et) % 24 + 24) % 24;

   // Core session: 08:20 – 13:30 ET  (best liquidity + volume)
   bool in_core = (et_hour > 8 || (et_hour == 8 && srv_min >= 20)) &&
                  (et_hour < 13 || (et_hour == 13 && srv_min <= 30));

   // Electronic session: 18:00 previous day – 17:00 ET (Sun–Fri)
   bool in_electronic = !(et_hour == 17 && srv_min > 0) && (et_hour < 17 || et_hour >= 18);

   // Session filter recommendation for EA inputs
   // StartHr/EndHr in SERVER TIME that covers core+overlap
   // Core 08:20–13:30 ET → server time
   int core_start_srv = ((8  + (-et_offset)) % 24 + 24) % 24;
   int core_end_srv   = ((13 + (-et_offset)) % 24 + 24) % 24;
   // NY open to late NY: 08:00–21:00 server recommendation (covers London overlap too)
   int rec_start_srv  = ((8  + (-et_offset)) % 24 + 24) % 24;
   int rec_end_srv    = ((21 + (-et_offset)) % 24 + 24) % 24;

   ADD("══ CME / COMEX SESSION ════════════════",  cHead)
   ADD(StringFormat("  Server→ET   : add %+d h to server time", srv_to_et), cInfo)
   ADD(StringFormat("  Current ET  : %02d:%02d",  et_hour, srv_min), cInfo)
   ADD(StringFormat("  Core session: %s",  in_core       ? "✅ ACTIVE (08:20-13:30 ET)"
                                                          : "⛔ outside core hours"),
                                           in_core ? cOk : cWarn)
   ADD(StringFormat("  Electronic  : %s",  in_electronic ? "✅ OPEN"
                                                          : "⛔ CLOSED (17:00-18:00 ET gap)"),
                                           in_electronic ? cOk : cFail)
   ADD(" ", cInfo)
   ADD("══ EA SESSION FILTER RECOMMENDATION ══",   cHead)
   ADD(StringFormat("  Inp_StartHr = %d  (= 08:00 ET in server time)", rec_start_srv), cLabel)
   ADD(StringFormat("  Inp_EndHr   = %d  (= 21:00 ET in server time)", rec_end_srv),   cLabel)
   ADD("  (covers London+NY overlap, full CME core)", cInfo)
   ADD(" ", cInfo)

   // ── SECTION 3: VPRR proxy symbol probe ───────────────────────────
   ADD("══ VPRR PROXY SYMBOL PROBE ════════════",  cHead)
   ADD(StringFormat("  Traded sym  : %s", _Symbol),                    cInfo)
   ADD(StringFormat("  Proxy sym   : %s", Inp_VPRR_ProxySymbol),       cInfo)
   ADD(" ", cInfo)

   string ext = Inp_VPRR_ProxySymbol;
   bool   sym_ok  = false;
   bool   bar_ok  = false;
   bool   vol_ok  = false;
   bool   aln_ok  = false;
   long   vol_val = 0;
   int    ext_bars = 0;

   if(StringLen(ext) == 0)
   {
      ADD("  ❌ Proxy symbol is empty — set Inp_VPRR_ProxySymbol", cFail)
   }
   else
   {
      // 1. Symbol select
      sym_ok = SymbolSelect(ext, true);
      ADD(StringFormat("  Symbol found: %s  %s",
                       sym_ok ? "✅" : "❌",
                       sym_ok ? "in Market Watch" : "NOT found on this broker"),
          sym_ok ? cOk : cFail)

      if(sym_ok)
      {
         // 2. Bars available
         ext_bars = Bars(ext, PERIOD_CURRENT);
         bar_ok   = (ext_bars >= 5);
         ADD(StringFormat("  Bars (curr TF): %s  %d bars on %s",
                          bar_ok ? "✅" : "⚠️",
                          ext_bars,
                          EnumToString((ENUM_TIMEFRAMES)_Period)),
             bar_ok ? cOk : cWarn)

         // 3. Real volume probe on last closed bar
         datetime bar_time = iTime(_Symbol, PERIOD_CURRENT, 1);
         int ext_shift = iBarShift(ext, PERIOD_CURRENT, bar_time, true);

         if(ext_shift >= 0)
         {
            long probe[];
            if(CopyRealVolume(ext, PERIOD_CURRENT, ext_shift, 1, probe) == 1 && probe[0] > 0)
            {
               vol_ok  = true;
               vol_val = probe[0];
            }
            ADD(StringFormat("  Real volume : %s  %s",
                             vol_ok ? "✅" : "❌",
                             vol_ok ? StringFormat("%I64d contracts (bar shift %d)", vol_val, ext_shift)
                                    : "CopyRealVolume returned 0 — CFD broker, no COMEX data"),
                vol_ok ? cOk : cFail)

            // 4. Bar alignment check
            if(vol_ok)
            {
               datetime ext_bar_open = iTime(ext, PERIOD_CURRENT, ext_shift);
               int      gap_sec      = (int)MathAbs((long)(bar_time - ext_bar_open));
               int      bar_secs     = PeriodSeconds(PERIOD_CURRENT);
               aln_ok = (gap_sec <= bar_secs);
               ADD(StringFormat("  Bar align   : %s  gap=%ds (%s)",
                                aln_ok ? "✅" : "⚠️",
                                gap_sec,
                                aln_ok ? "within 1 bar — OK"
                                       : "exceeds 1 bar — check TF / sessions"),
                   aln_ok ? cOk : cWarn)
            }
         }
         else
         {
            ADD("  Bar align   : ❌  iBarShift failed — sessions may not overlap", cFail)
         }

         // 5. Rollover hint — detect if symbol looks like a dated contract
         if(StringLen(ext) > 2)
         {
            string suffix = StringSubstr(ext, StringLen(ext)-3, 3);
            bool looks_dated = (StringFind("FGHJKMNQUVXZ", StringSubstr(suffix,0,1)) >= 0);
            if(looks_dated)
               ADD(StringFormat("  ⚠️  '%s' looks like a dated contract — update Inp_VPRR_ExternalSymbol on rollover", ext), cWarn)
            else
               ADD(StringFormat("  ℹ️  '%s' — if broker uses dated names (e.g. MGCM26), update on quarterly rollover", ext), cInfo)
         }
      }
   }

   ADD(" ", cInfo)

   // ── SECTION 4: Verdict ────────────────────────────────────────────
   ADD("══ VERDICT ════════════════════════════",  cHead)

   bool all_ok = sym_ok && bar_ok && vol_ok && aln_ok;
   if(all_ok)
   {
      ADD("  ✅ READY: VPRR EXTERNAL will be ACTIVE",   cOk)
      ADD("  Set in EA inputs:",                        cInfo)
      ADD("    Inp_RRM_ORG_VPRR_AutoEnable  = false",   cLabel)
      ADD("    Inp_RRM_ORG_VPRR_VolumeType  = EXTERNAL",cLabel)
      ADD(StringFormat("    Inp_VPRR_ExternalSymbol     = \"%s\"", ext), cLabel)
   }
   else if(sym_ok && bar_ok && !vol_ok)
   {
      ADD("  ❌ BROKER INCOMPATIBLE for VPRR EXTERNAL", cFail)
      ADD("  This broker provides no real COMEX volume", cFail)
      ADD("  → Use AMP Futures or Optimus Futures",     cWarn)
      ADD("  → CFD brokers (Pepperstone/IC Markets)     ", cWarn)
      ADD("    cannot provide CopyRealVolume on metals", cWarn)
   }
   else if(!sym_ok)
   {
      ADD("  ❌ Symbol not found on this broker",        cFail)
      ADD("  Check exact symbol name in Market Watch",  cWarn)
      ADD("  Common names: MGC, MGCM26, GC, GCUSD",    cInfo)
   }
   else
   {
      ADD("  ⚠️  Partial — review items above",          cWarn)
   }

   ADD(" ", cInfo)
   ADD(StringFormat("  Checked: %s", TimeToString(srv_now, TIME_DATE|TIME_SECONDS)), cInfo)
   if(Inp_DisplaySeconds > 0)
      ADD(StringFormat("  Panel auto-removes in %ds", Inp_DisplaySeconds), clrGray)

   // ── Render panel ──────────────────────────────────────────────────
   _RenderPanel(lines, clrs, n);

   // ── Print to journal ──────────────────────────────────────────────
   Print("════════════════════════════════════════════════════");
   Print("  SEA SERVER TIME & VPRR CHECK");
   Print("════════════════════════════════════════════════════");
   for(int i = 0; i < n; i++)
      if(lines[i] != " " && lines[i] != "")
         Print("  ", lines[i]);
   Print("════════════════════════════════════════════════════");

   // ── Auto-remove ───────────────────────────────────────────────────
   if(Inp_DisplaySeconds > 0)
   {
      Sleep(Inp_DisplaySeconds * 1000);
      _DestroyPanel();
   }
}

//+------------------------------------------------------------------+
void _RenderPanel(const string &lines[], const color &clrs[], int n)
{
   _DestroyPanel();
   int pad = 6;
   int lh  = LINE_H;

   // Background
   string bg = PANEL_NAME + "_BG";
   ObjectCreate(0, bg, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, bg, OBJPROP_CORNER,     Inp_Corner);
   ObjectSetInteger(0, bg, OBJPROP_XDISTANCE,  Inp_X);
   ObjectSetInteger(0, bg, OBJPROP_YDISTANCE,  Inp_Y);
   ObjectSetInteger(0, bg, OBJPROP_XSIZE,      360);
   ObjectSetInteger(0, bg, OBJPROP_YSIZE,      n * lh + pad * 2);
   ObjectSetInteger(0, bg, OBJPROP_BGCOLOR,    C'20,20,30');
   ObjectSetInteger(0, bg, OBJPROP_BORDER_TYPE,BORDER_FLAT);
   ObjectSetInteger(0, bg, OBJPROP_COLOR,      clrDimGray);
   ObjectSetInteger(0, bg, OBJPROP_BACK,       true);

   for(int i = 0; i < n && i < MAX_LINES; i++)
   {
      string ln = PANEL_NAME + StringFormat("_L%02d", i);
      ObjectCreate(0, ln, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, ln, OBJPROP_CORNER,    Inp_Corner);
      ObjectSetInteger(0, ln, OBJPROP_ANCHOR,    ANCHOR_LEFT_UPPER);
      ObjectSetInteger(0, ln, OBJPROP_XDISTANCE, Inp_X + pad);
      ObjectSetInteger(0, ln, OBJPROP_YDISTANCE, Inp_Y + pad + i * lh);
      ObjectSetInteger(0, ln, OBJPROP_COLOR,     clrs[i]);
      ObjectSetInteger(0, ln, OBJPROP_SELECTABLE,false);
      ObjectSetString(0,  ln, OBJPROP_FONT,      Inp_Font);
      ObjectSetInteger(0, ln, OBJPROP_FONTSIZE,  Inp_FontSize);
      ObjectSetString(0,  ln, OBJPROP_TEXT,      (lines[i] == "") ? " " : lines[i]);
   }
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
void _DestroyPanel()
{
   ObjectDelete(0, PANEL_NAME + "_BG");
   for(int i = 0; i < MAX_LINES; i++)
      ObjectDelete(0, PANEL_NAME + StringFormat("_L%02d", i));
   ChartRedraw(0);
}
