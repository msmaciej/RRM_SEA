//+------------------------------------------------------------------+
//|                                                     SEA_UI.mqh   |
//|                                   Copyright 2026, SimpleEA System|
//| SimpleEA UI Panels (Settings Status + Cockpit)                   |
//+------------------------------------------------------------------+
// SAVE AS UTF-16 LE WITH BOM
#property strict

#define SEA_MOD_UI_103001 1

// -----------------------------------
// Internal state (no static locals)
// -----------------------------------
string g_sea_ui_base_name    = "";
ulong  g_sea_ui_magic        = 0;

string g_sea_ui_settings_name = "";
string g_sea_ui_cockpit_name  = "";

string g_sea_ui_last_settings_txt = "";
string g_sea_ui_last_cockpit_txt  = "";

// -----------------------------------
// Helpers
// -----------------------------------
string SEA_UI_OnOff(const bool v) { return (v ? "ON" : "OFF"); }

// Returns " [adm]" when admin override is active for a preset (marks overridden fields)
string SEA_UI_AdmMark()
{
   return ((Settings.AdminOverridePreset && InpPreset != PRESET_CUSTOM) ? " [adm]" : "");
}

int SEA_UI_PipFactor()
{
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   if(digits == 3 || digits == 5) return 10;
   return 1;
}

color SEA_UI_ForeColor()
{
   long c = 0;
   if(ChartGetInteger(0, CHART_COLOR_FOREGROUND, 0, c))
      return (color)c;
   return clrWhite;
}

color SEA_UI_PanelBgColor()
{
   color fg  = SEA_UI_ForeColor();
   int   r   = (int)fg & 0xFF;
   int   g   = ((int)fg >> 8) & 0xFF;
   int   b   = ((int)fg >> 16) & 0xFF;
   int   avg = (r + g + b) / 3;
   color base = (avg > 128 ? clrBlack : clrWhite);
   return (color)ColorToARGB(base, 110);
}

int SEA_UI_SplitLines(const string text, string &out[])
{
   string s = text;
   StringReplace(s, "\r\n", "\n");
   StringReplace(s, "\r",   "\n");
   int n = StringSplit(s, '\n', out);

   while(n > 0)
   {
      if(StringLen(out[n-1]) != 0) break;
      ArrayResize(out, n-1);
      n--;
   }
   return n;
}

int SEA_UI_GetLineSpacingPx(const int configured, const int font_size)
{
   int sp = configured;
   if(sp <= 0)
      sp = (font_size > 0 ? (font_size + 4) : 14);
   if(sp < 8)  sp = 8;
   if(sp > 60) sp = 60;
   return sp;
}

void SEA_UI_DestroyPanel(const string panel_name)
{
   if(panel_name == "") return;

   string bg = panel_name + "_BG";
   ObjectDelete(0, bg);

   for(int i=0; i<50; i++)
   {
      string ln = panel_name + StringFormat("_L%02d", i);
      ObjectDelete(0, ln);
   }
}

void SEA_UI_RenderPanel(
   const string panel_name,
   const string txt,
   const ENUM_BASE_CORNER corner,
   const int x,
   const int y,
   const int font_size,
   const int line_spacing_px,
   const string font
)
{
   if(panel_name == "") return;

   string lines[];
   int n = SEA_UI_SplitLines(txt, lines);
   if(n <= 0)
   {
      ArrayResize(lines, 1);
      lines[0] = txt;
      n = 1;
   }

   if(n > 50) n = 50;

   int max_chars = 0;
   for(int i=0; i<n; i++)
   {
      int l = StringLen(lines[i]);
      if(l > max_chars) max_chars = l;
   }

   int line_h  = SEA_UI_GetLineSpacingPx(line_spacing_px, font_size);
   int char_px = (int)MathMax(6.0, MathRound(font_size * 0.6 + 4.0));
   int pad     = Inp_UI_FramePadPx;
   int w       = pad*2 + max_chars * char_px;
   int h       = pad*2 + n * line_h;

   if(Inp_UI_FrameMode == UI_FRAME_BG)
   {
      string bg = panel_name + "_BG";
      if(ObjectFind(0, bg) < 0)
         ObjectCreate(0, bg, OBJ_RECTANGLE_LABEL, 0, 0, 0);

      ObjectSetInteger(0, bg, OBJPROP_CORNER,     (int)corner);
      ObjectSetInteger(0, bg, OBJPROP_XDISTANCE,  x);
      ObjectSetInteger(0, bg, OBJPROP_YDISTANCE,  y);
      ObjectSetInteger(0, bg, OBJPROP_XSIZE,       w);
      ObjectSetInteger(0, bg, OBJPROP_YSIZE,       h);
      ObjectSetInteger(0, bg, OBJPROP_SELECTABLE,  false);
      ObjectSetInteger(0, bg, OBJPROP_HIDDEN,      false);
      ObjectSetInteger(0, bg, OBJPROP_BACK,        true);
      ObjectSetInteger(0, bg, OBJPROP_COLOR,       SEA_UI_ForeColor());
      ObjectSetInteger(0, bg, OBJPROP_BGCOLOR,     SEA_UI_PanelBgColor());
      ObjectSetInteger(0, bg, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   }

   for(int i=0; i<n; i++)
   {
      string ln = panel_name + StringFormat("_L%02d", i);
      if(ObjectFind(0, ln) < 0)
      {
         if(!ObjectCreate(0, ln, OBJ_LABEL, 0, 0, 0))
         {
            Print("UI: failed to create panel line object: ", ln);
            continue;
         }
      }

      color fc = (Inp_UI_UseCustomColors ? Inp_UI_FontColor : SEA_UI_ForeColor());
      ObjectSetInteger(0, ln, OBJPROP_CORNER,    (int)corner);
      ObjectSetInteger(0, ln, OBJPROP_XDISTANCE, x + pad);
      ObjectSetInteger(0, ln, OBJPROP_YDISTANCE, y + pad + i*line_h);
      ObjectSetInteger(0, ln, OBJPROP_FONTSIZE,  font_size);
      ObjectSetString(0,  ln, OBJPROP_FONT,      font);
      ObjectSetInteger(0, ln, OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0, ln, OBJPROP_HIDDEN,    false);
      ObjectSetInteger(0, ln, OBJPROP_BACK,      false);
      ObjectSetInteger(0, ln, OBJPROP_COLOR,     fc);
      ObjectSetString(0,  ln, OBJPROP_TEXT,      lines[i]);
   }

   for(int i=n; i<50; i++)
   {
      string ln = panel_name + StringFormat("_L%02d", i);
      ObjectDelete(0, ln);
   }
}

// -----------------------------------
// Public API
// -----------------------------------
void SEA_UI_Init(const ulong magic)
{
   g_sea_ui_magic     = magic;
   g_sea_ui_base_name = StringFormat("SEA_UI_%I64d_%I64u", (long)ChartID(), g_sea_ui_magic);
   g_sea_ui_settings_name = g_sea_ui_base_name + "_SET";
   g_sea_ui_cockpit_name  = g_sea_ui_base_name + "_COCK";
}

void SEA_UI_DestroyAll()
{
   SEA_UI_DestroyPanel(g_sea_ui_settings_name);
   SEA_UI_DestroyPanel(g_sea_ui_cockpit_name);
   g_sea_ui_last_settings_txt = "";
   g_sea_ui_last_cockpit_txt  = "";
}

// Status panel: preset, strategy, and entry/exit effective config
void SEA_UI_UpdateSettingsPanel()
{
   if(!Inp_UI_ShowStatusPanel)
   {
      SEA_UI_DestroyPanel(g_sea_ui_settings_name);
      return;
   }

   string txt = "";
   txt += StringFormat("SimpleEA v%s  [%s %s]\n", SEA_BUILD_STR, _Symbol, EnumToString(_Period));
   txt += StringFormat("Preset: %s\n", EnumToString(InpPreset));

   // AdminOverride status
   if(InpPreset != PRESET_CUSTOM)
   {
      if(Settings.AdminOverridePreset)
         txt += "AdminOverride: ACTIVE [Admin Mode - Testing]\n";
      else
         txt += "AdminOverride: OFF [Normal User Mode]\n";
   }

   txt += StringFormat("Mode: %s\n", (InpPreset == PRESET_CUSTOM
                                       ? "CUSTOM (inputs respected)"
                                       : "PRESET (overrides active)"));

   // --- Strategy
   txt += "--- Strategy ---\n";
   txt += StringFormat("AutoStrat: %s%s\n", EnumToString(Settings.AutoStrat), SEA_UI_AdmMark());
   txt += StringFormat("BiasEnabled: %s  BiasMode: %s\n",
                       SEA_UI_OnOff(Settings.BiasEnabled), EnumToString(Settings.BiasMode));
   txt += StringFormat("EMA: %d/%d/%d/%d%s  VoteThreshold: %d%s\n",
                       Settings.P_Ema1, Settings.P_Ema2, Settings.P_Ema3, Settings.P_Ema4,
                       SEA_UI_AdmMark(), Settings.VoteThreshold, SEA_UI_AdmMark());
   txt += StringFormat("MACD: %d/%d/%d%s\n", Settings.P_MacdFast, Settings.P_MacdSlow, Settings.P_MacdSig,
                       SEA_UI_AdmMark());

   // --- Entry / Filters
   txt += "--- Entry / Filters ---\n";
   txt += StringFormat("RequirePriceCross: %s%s  UseHTF: %s\n",
                       SEA_UI_OnOff(Settings.RequirePriceCross), SEA_UI_AdmMark(),
                       SEA_UI_OnOff(Settings.UseHTF));
   txt += StringFormat("CloseOnReverse: %s%s\n", SEA_UI_OnOff(Settings.CloseOnReverse), SEA_UI_AdmMark());

   // --- Position Sizing
   txt += "--- Position Sizing ---\n";
   if(Settings.UseMACompatSizer)
      txt += StringFormat("Sizer: MACompat (MaxRisk=%.4f%%  Dec=%.2f)\n",
                          Settings.MA_MaximumRiskPct, Settings.MA_DecreaseFactor);
   else
      txt += StringFormat("Sizer: Risk%%  RiskPercent=%.2f%%%s\n", Settings.RiskPercent, SEA_UI_AdmMark());

   // --- Exits: SL / TP
   txt += "--- Exits: SL / TP ---\n";
   txt += StringFormat("SL: %s%s  Mult=%.2f%s\n", EnumToString(Settings.SL_PlacementMode),
                       SEA_UI_AdmMark(), Settings.SL_Mult, SEA_UI_AdmMark());
   txt += StringFormat("TP_Mult=%.2f%s\n", Settings.TP_Mult, SEA_UI_AdmMark());

   // --- Exits: Breakeven
   txt += "--- Exits: Breakeven ---\n";
   if(Settings.Use_BE)
      txt += StringFormat("BE: ON%s  Trig=%.2fR  Buff=%.1f pips\n", SEA_UI_AdmMark(),
                          Settings.BE_Trig, Settings.BE_Buff);
   else
      txt += StringFormat("BE: OFF%s\n", SEA_UI_AdmMark());

   // --- Exits: Trailing
   txt += "--- Exits: Trailing ---\n";
   string trail_str = EnumToString(Settings.TrailMode) + SEA_UI_AdmMark();
   if(Settings.TrailMode == TRAIL_ATR)
      trail_str += StringFormat("  Mult=%.2f", Settings.Trail_Mult);
   else if(Settings.TrailMode == TRAIL_PSAR)
      trail_str += StringFormat("  %s", EnumToString(Settings.PSAR_TrailCushionMode));
   txt += trail_str + "\n";

   // Admin override notice
   if(Settings.AdminOverridePreset && InpPreset != PRESET_CUSTOM)
      txt += "** ADMIN OVERRIDES APPLIED [adm] **\n";

   if(txt == g_sea_ui_last_settings_txt)
      return;
   g_sea_ui_last_settings_txt = txt;

   SEA_UI_RenderPanel(
      g_sea_ui_settings_name,
      txt,
      Inp_UI_PanelCorner,
      Inp_UI_PanelX,
      Inp_UI_PanelY,
      Inp_UI_PanelFontSize,
      Inp_UI_LineSpacingPx,
      Inp_UI_PanelFont
   );
}

// Cockpit panel: essential runtime and position info (call only once per new bar)
void SEA_UI_UpdateCockpitPanel(const double atr,
                                const int    last_signal_dir,
                                const int    last_bias,
                                const int    last_votes,
                                const string last_reason,
                                const string ts_snap,
                                const string te_snap)
{
   if(!Inp_UI_ShowCockpitPanel)
   {
      SEA_UI_DestroyPanel(g_sea_ui_cockpit_name);
      return;
   }

   // Market snapshot
   double bid=0.0, ask=0.0;
   SymbolInfoDouble(_Symbol, SYMBOL_BID, bid);
   SymbolInfoDouble(_Symbol, SYMBOL_ASK, ask);
   double spread_points = (ask - bid) / _Point;
   int    pip_fac       = SEA_UI_PipFactor();
   double spread_pips   = (pip_fac > 0 ? spread_points / pip_fac : spread_points);

   double atr_pips = 0.0;
   if(atr > 0.0)
      atr_pips = (atr / _Point) / (pip_fac > 0 ? pip_fac : 1);

   // Position snapshot (single position per symbol+magic expected; scan robustly)
   bool   has_pos   = false;
   long   pos_type  = -1;
   double pos_vol=0.0, pos_open=0.0, pos_sl=0.0, pos_tp=0.0, pos_profit=0.0;

   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != g_sea_ui_magic) continue;
      has_pos    = true;
      pos_type   = PositionGetInteger(POSITION_TYPE);
      pos_vol    = PositionGetDouble(POSITION_VOLUME);
      pos_open   = PositionGetDouble(POSITION_PRICE_OPEN);
      pos_sl     = PositionGetDouble(POSITION_SL);
      pos_tp     = PositionGetDouble(POSITION_TP);
      pos_profit = PositionGetDouble(POSITION_PROFIT);
      break;
   }

   string sig_line = StringFormat("Signal=%d  Bias=%d", last_signal_dir, last_bias);
   if(Settings.VoteThreshold <= 1)
      sig_line += "  Votes=BYPASS";
   else
      sig_line += StringFormat("  Votes=%d/%d", last_votes, Settings.VoteThreshold);

   if(last_signal_dir == 0 && last_reason != "")
      sig_line += StringFormat("  (%s)", last_reason);

   string risk_line = "";
   if(Settings.UseMACompatSizer)
      risk_line = StringFormat("Sizer=MACompat (MaxRisk=%.4f%%  Dec=%.2f)",
                               Settings.MA_MaximumRiskPct, Settings.MA_DecreaseFactor);
   else
      risk_line = StringFormat("Sizer=Risk%%  (%.2f%%)", Settings.RiskPercent);

   string gates_line = StringFormat("Spread=%.1f pips  ATR=%.1f pips", spread_pips, atr_pips);

   datetime bt = iTime(_Symbol, PERIOD_CURRENT, 0);
   string time_line = (bt > 0 ? TimeToString(bt, TIME_DATE|TIME_MINUTES)
                               : TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES));

   string txt = "";
   txt += StringFormat("Cockpit v%s  [%s %s]\n", SEA_BUILD_STR, _Symbol, EnumToString(_Period));
   txt += StringFormat("Bar: %s\n", time_line);
   txt += gates_line + "\n";
   txt += risk_line  + "\n";
   txt += sig_line   + "\n";

   if(has_pos)
   {
      string side = (pos_type == POSITION_TYPE_BUY ? "BUY" : "SELL");
      txt += StringFormat("%s %.2f @ %.5f  PnL=%.2f\n", side, pos_vol, pos_open, pos_profit);
      txt += StringFormat("SL=%.5f  TP=%.5f\n", pos_sl, pos_tp);
   }
   else
   {
      txt += "Position: Flat\n";
   }

   // Preset contract wording
   if(InpPreset != PRESET_CUSTOM)
   {
      txt += "--- Preset Contract ---\n";
      txt += GetPresetContractWording(InpPreset) + "\n";
      if(Settings.AdminOverridePreset)
         txt += "** ADMIN OVERRIDES APPLIED **\n";
   }

   // TS/TE snapshots
   if(ts_snap != "")
      txt += ts_snap + "\n";
   if(te_snap != "")
      txt += te_snap + "\n";

   if(txt == g_sea_ui_last_cockpit_txt)
      return;
   g_sea_ui_last_cockpit_txt = txt;

   SEA_UI_RenderPanel(
      g_sea_ui_cockpit_name,
      txt,
      Inp_UI_CockpitCorner,
      Inp_UI_CockpitX,
      Inp_UI_CockpitY,
      Inp_UI_CockpitFontSize,
      Inp_UI_CockpitLineSpacingPx,
      Inp_UI_CockpitFont
   );
}
