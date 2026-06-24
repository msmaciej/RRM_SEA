//+------------------------------------------------------------------+
//|                                                       SEA_UI.mqh |
//|                                  Copyright 2026, SimpleEA System |
//|                   SimpleEA UI Panels (Settings Status + Cockpit) |
//+------------------------------------------------------------------+
// SAVE AS UTF-16 LE WITH BOM
#property strict

#define SEA_UI_MAX_PANEL_LINES 75

#define SEA_MOD_UI_105001 1

// -----------------------------------
// Internal state (no static locals)
// -----------------------------------
string g_sea_ui_base_name    = "";
ulong  g_sea_ui_magic        = 0;

string g_sea_ui_settings_name  = "";
string g_sea_ui_cockpit_name   = "";
string g_sea_ui_vprr_name      = "";
string g_sea_ui_vprr_init_name = "";   // VPRR Init Check panel (startup validation results)

string g_sea_ui_last_settings_txt = "";
string g_sea_ui_last_cockpit_txt  = "";

// Deferred VPRR panel content (stored during preset, rendered after SEA_UI_Init)
string g_sea_ui_vprr_lines[];
color  g_sea_ui_vprr_clrs[];

// Deferred VPRR Init Check panel (stored by ValidateVPRRExternalSymbol, rendered after SEA_UI_Init)
string g_sea_ui_vprr_init_lines[];
color  g_sea_ui_vprr_init_clrs[];

// -----------------------------------
// Helpers
// -----------------------------------
string SEA_UI_OnOff(const bool v) { return (v ? "ON" : "OFF"); }

string SEA_UI_BiasLabel(const int bias)
{
   if(bias ==  1) return "LONG";
   if(bias == -1) return "SHORT";
   return "NEUTRAL";
}

string SEA_UI_SignalLabel(const int signal_dir)
{
   if(signal_dir ==  1) return "BUY";
   if(signal_dir == -1) return "SELL";
   return "FLAT";
}

string SEA_UI_EntryLayerLabel(EEntryLayer layer)
{
   int bits = (int)layer;
   if(bits == 0) return "(none)";

   string result = "";
   if((bits & (int)LAYER_1_WEAK)   != 0) result += (result == "" ? "" : "+") + "L1";
   if((bits & (int)LAYER_2_MEDIUM) != 0) result += (result == "" ? "" : "+") + "L2";
   if((bits & (int)LAYER_3_STRONG) != 0) result += (result == "" ? "" : "+") + "L3";

   return result;
}

bool SEA_UI_IsLayerActive(EEntryLayer bitfield, EEntryLayer layer)
{
   return ((int)bitfield & (int)layer) != 0;
}

string SEA_UI_FormatPhase(EMarketPhase phase, color &out_color)
{
   switch(phase)
   {
      case PHASE_TRENDING_UP:
         out_color = clrLimeGreen;
         return "TRENDING UP";
      case PHASE_TRENDING_DN:
         out_color = clrLimeGreen;
         return "TRENDING DN";
      case PHASE_TRENDING:
         out_color = clrLimeGreen;
         return "TRENDING";
      case PHASE_EMERGING_UP:
         out_color = clrGold;
         return "EMERGING UP";
      case PHASE_EMERGING_DN:
         out_color = clrGold;
         return "EMERGING DN";
      case PHASE_EMERGING:
         out_color = clrGold;
         return "EMERGING";
      case PHASE_UNORDERED:
         out_color = clrOrangeRed;
         return "UNORDERED";
      default:
         out_color = clrGray;
         return "UNKNOWN";
   }
}

string SEA_UI_FormatAllowedLayers(EMarketPhase phase, bool filter_active)
{
   if(!filter_active)
      return "ALL (filter disabled)";

   bool is_emerging = (phase == PHASE_EMERGING || phase == PHASE_EMERGING_UP || phase == PHASE_EMERGING_DN);
   bool is_trending = (phase == PHASE_TRENDING || phase == PHASE_TRENDING_UP || phase == PHASE_TRENDING_DN);

   if(is_trending)  return "L1, L2, L3";
   if(is_emerging)  return "L1, L2";
   if(phase == PHASE_UNORDERED) return "NONE";
   return "UNKNOWN";
}

string SEA_UI_FormatFilterStatus(bool is_allowed, bool filter_active, color &out_color)
{
   if(!filter_active)
   {
      out_color = clrGray;
      return "- DISABLED";
   }
   if(is_allowed)
   {
      out_color = clrLimeGreen;
      return ShortToString(0x2713) + " ALLOWED";
   }
   else
   {
      out_color = clrRed;
      return ShortToString(0x2717) + " BLOCKED";
   }
}

string SEA_UI_AdmMark() { return ""; }

string SEA_UI_NormalizeStatusText(const string status)
{
   if(StringLen(status) == 0 || StringCompare(status, "null") == 0)
      return SEA_STATUS_EVALUATING;
   return status;
}

int SEA_UI_PipFactor()
{
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   if(digits == 3 || digits == 5) return 10;
   return 1;
}

//+------------------------------------------------------------------+
//| MASTER COLOR RESOLVER - Hierarchy: Custom > Theme > Chart        |
//+------------------------------------------------------------------+
color SEA_UI_ForeColor()
{
   // 1. Check if the User enabled "Use custom panel colors" 
   if(Inp_UI_UseCustomColors) 
      return Inp_UI_FontColor; // Yellow 

   // 2. Fallback to Dashboard Theme "Market Data Color" 
   if(Settings.clr_Value != 0) 
      return Settings.clr_Value; // White 

   // 3. Final safety fallback to MT5 Chart Foreground [cite: 31]
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

void SEA_UI_ClearMTFSegments()
{
   for(int i = 0; i < 10; i++)
      ObjectDelete(0, "CP_MTF_Seg" + IntegerToString(i));
}

void SEA_UI_DrawMTFSegments(CSignalEngine &signal, const int line_index)
{
   SEA_UI_ClearMTFSegments();
   if(line_index < 0) return;

   SMTFSegment segments[];
   signal.GetMTFCockpitData(segments);
   int seg_count = ArraySize(segments);
   if(seg_count <= 0) return;

   int line_h = SEA_UI_GetLineSpacingPx(Inp_UI_PanelLineSpacingPx, Inp_UI_PanelFontSize);
   int pad = Inp_UI_FramePadPx;
   int x_cursor = Inp_UI_CockpitX + pad;
   int y = Inp_UI_CockpitY + pad + (line_index * line_h);

   // Set font for accurate TextGetSize measurement
   string font_name = Inp_UI_PanelFont;
   int font_size_px = -(int)(Inp_UI_PanelFontSize * 10);  // negative = points * 10
   TextSetFont(font_name, font_size_px);

   for(int i = 0; i < seg_count && i < 10; i++)
   {
      string label_name = "CP_MTF_Seg" + IntegerToString(i);
      if(ObjectFind(0, label_name) < 0)
         ObjectCreate(0, label_name, OBJ_LABEL, 0, 0, 0);

      ObjectSetInteger(0, label_name, OBJPROP_CORNER, (int)Inp_UI_CockpitCorner);
      ObjectSetInteger(0, label_name, OBJPROP_XDISTANCE, x_cursor);
      ObjectSetInteger(0, label_name, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(0, label_name, OBJPROP_COLOR, segments[i].clr);
      ObjectSetInteger(0, label_name, OBJPROP_FONTSIZE, Inp_UI_PanelFontSize);
      ObjectSetInteger(0, label_name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, label_name, OBJPROP_HIDDEN, true);
      ObjectSetString(0, label_name, OBJPROP_FONT, font_name);
      ObjectSetString(0, label_name, OBJPROP_TEXT, segments[i].text);

      // Accurate pixel width via TextGetSize; fallback to generous estimate
      uint tw = 0, th = 0;
      if(TextGetSize(segments[i].text, tw, th) && tw > 0)
         x_cursor += (int)tw + 2;   // +2px gap between segments
      else
         x_cursor += (int)(StringLen(segments[i].text) * Inp_UI_PanelFontSize * 0.85) + 4;
   }
}

void SEA_UI_DestroyPanel(const string panel_name)
{
   if(panel_name == "") return;

   string bg = panel_name + "_BG";
   ObjectDelete(0, bg);
   for(int i=0; i<SEA_UI_MAX_PANEL_LINES; i++)
   {
      string ln = panel_name + StringFormat("_L%02d", i);
      ObjectDelete(0, ln);
   }
}

//+------------------------------------------------------------------+
//| STANDALONE RENDER ENGINE - Fixes scope and array errors          |
//+------------------------------------------------------------------+
void SEA_UI_RenderPanel(
   const string panel_name, const string txt, const ENUM_BASE_CORNER corner,
   const int x, const int y, const int font_size, const int line_spacing_px,
   const string font, const color &line_colors[] 
) {
   if(panel_name == "") return;
   
   string lines[];
   int n = StringSplit(txt, '\n', lines);
   if(n <= 0) return;

   // Calculate spacing and padding
   int line_h = (line_spacing_px <= 0) ? (font_size + 4) : line_spacing_px;
   int pad = Inp_UI_FramePadPx;

   // Anchor each label to the side matching the chosen corner. For right-side
   // corners we anchor text to its right edge so lines grow leftward and never
   // run off the right of the chart, regardless of line length.
   bool is_right = (corner == CORNER_RIGHT_UPPER || corner == CORNER_RIGHT_LOWER);
   bool is_lower = (corner == CORNER_LEFT_LOWER  || corner == CORNER_RIGHT_LOWER);
   ENUM_ANCHOR_POINT anchor =
        is_right ? (is_lower ? ANCHOR_RIGHT_LOWER : ANCHOR_RIGHT_UPPER)
                 : (is_lower ? ANCHOR_LEFT_LOWER  : ANCHOR_LEFT_UPPER);

   // Handle Background
   if(Inp_UI_FrameMode == UI_FRAME_BG) {
      string bg = panel_name + "_BG";
      if(ObjectFind(0, bg) < 0) ObjectCreate(0, bg, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, bg, OBJPROP_CORNER, (int)corner);
      ObjectSetInteger(0, bg, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, bg, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(0, bg, OBJPROP_BGCOLOR, SEA_UI_PanelBgColor());
   }

   // Dynamic Line Rendering
   for(int i=0; i<SEA_UI_MAX_PANEL_LINES; i++) {
      string ln = panel_name + StringFormat("_L%02d", i);
      
      if(i < n) {
         // Create if missing, then update with real data
         if(ObjectFind(0, ln) < 0) ObjectCreate(0, ln, OBJ_LABEL, 0, 0, 0);
         
         color clr = (i < ArraySize(line_colors)) ? line_colors[i] : SEA_UI_ForeColor();
         
         ObjectSetInteger(0, ln, OBJPROP_CORNER, (int)corner);
         ObjectSetInteger(0, ln, OBJPROP_ANCHOR, (int)anchor);
         ObjectSetInteger(0, ln, OBJPROP_XDISTANCE, x + pad);
         ObjectSetInteger(0, ln, OBJPROP_YDISTANCE, y + pad + (i * line_h));
         ObjectSetInteger(0, ln, OBJPROP_COLOR, clr);
         ObjectSetInteger(0, ln, OBJPROP_SELECTABLE, false);
         
         // CRITICAL: If line is empty, use a space to overwrite "Label"
         string final_txt = (lines[i] == "" || lines[i] == " ") ? " " : lines[i];
         ObjectSetString(0, ln, OBJPROP_TEXT, final_txt);
      }
      else {
         // Wipe out any leftover labels from previous larger renders
         ObjectDelete(0, ln);
      }
   }
   
   // Cleanup unused lines
   for(int i=n; i<SEA_UI_MAX_PANEL_LINES; i++) ObjectDelete(0, panel_name + StringFormat("_L%02d", i));
}

//+------------------------------------------------------------------+
//| Dashboard Helper: Calculate real-time trade metrics              |
//+------------------------------------------------------------------+
void SEA_UI_GetTradeMetrics(string &out_risk_p, string &out_rew_p, string &out_ratio, string &out_be) {
   out_risk_p = "0.0"; out_rew_p = "0.0"; out_ratio = "0.0"; out_be = "N/A";
   
   if(!PositionSelect(_Symbol)) return;
   
   double entry = PositionGetDouble(POSITION_PRICE_OPEN);
   double sl    = PositionGetDouble(POSITION_SL);
   double tp    = PositionGetDouble(POSITION_TP);
   long   type  = PositionGetInteger(POSITION_TYPE);
   int    p_fac = SEA_UI_PipFactor();

   if(sl > 0) {
      double r_pips = MathAbs(entry - sl) / (_Point * p_fac);
      out_risk_p = StringFormat("%.1f", r_pips);
      
      if(tp > 0) {
         double rew_pips = MathAbs(tp - entry) / (_Point * p_fac);
         out_rew_p = StringFormat("%.1f", rew_pips);
         out_ratio = StringFormat("1:%.2f", (r_pips > 0 ? rew_pips / r_pips : 0));
      }
   }
   
   double cur = (type == POSITION_TYPE_BUY ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK));
   double be_trigger_points = Settings.BEThresholdPips * _Point * p_fac;
   double be_level = entry + (type == POSITION_TYPE_BUY ? be_trigger_points : -be_trigger_points);
   double dist_to_be = (type == POSITION_TYPE_BUY ? (be_level - cur) : (cur - be_level)) / (_Point * p_fac);
   out_be = (dist_to_be <= 0 ? "ACTIVE" : StringFormat("%.1f pip", dist_to_be));
}

// -----------------------------------
// Vote & Config Display Helpers
// -----------------------------------
string SEA_UI_BiasEmaLabel(const ST_Settings &cfg)
{
   int fast_period = (cfg.BiasFastID==0) ? cfg.P_Ema1 : (cfg.BiasFastID==1) ? cfg.P_Ema2 : (cfg.BiasFastID==2) ? cfg.P_Ema3 : cfg.P_Ema4;
   int slow_period = (cfg.BiasSlowID==0) ? cfg.P_Ema1 : (cfg.BiasSlowID==1) ? cfg.P_Ema2 : (cfg.BiasSlowID==2) ? cfg.P_Ema3 : cfg.P_Ema4;
   if(cfg.BiasFastID == cfg.BiasSlowID)
      return StringFormat("EMA%d(%d) slope", cfg.BiasFastID+1, fast_period);
   return StringFormat("EMA%d(%d)/EMA%d(%d)", cfg.BiasFastID+1, fast_period, cfg.BiasSlowID+1, slow_period);
}

string SEA_UI_GetActiveIndicatorsCompact(const ST_Settings &cfg)
{
   string list = "";
   if(cfg.Ind_Adx_Enabled)        list += StringFormat("ADX(%d), ", cfg.P_Adx);
   if(cfg.Ind_Atr_Enabled)        list += StringFormat("ATR(%d), ", cfg.P_Atr);
   if(cfg.Ind_Bb_Enabled)         list += StringFormat("BB(%d,%.1f), ", cfg.P_Bb, cfg.P_BbDev);
   if(cfg.Ind_CandleBody_Enabled) list += StringFormat("CBody(%d), ", cfg.CandleBody_AvgPeriod);
   if(cfg.Ind_CI_Enabled)         list += StringFormat("CI(%d), ", cfg.CI_Period);
   if(cfg.Ind_Cci_Enabled)        list += StringFormat("CCI(%d), ", cfg.P_Cci);
   if(cfg.Ind_Macd_Enabled)       list += StringFormat("MACD(%d,%d,%d), ", cfg.P_MacdFast, cfg.P_MacdSlow, cfg.P_MacdSig);
   if(cfg.Ind_Mfi_Enabled)        list += StringFormat("MFI(%d), ", cfg.P_Mfi);
   if(cfg.Ind_P123_Enabled)       list += "P123, ";
   if(cfg.Ind_Psar_Enabled)       list += StringFormat("PSAR(%.2f,%.2f), ", cfg.P_PsarStep, cfg.P_PsarMax);
   if(cfg.Ind_Ross_Enabled)       list += "Ross, ";
   if(cfg.Ind_Rsi_Enabled)        list += StringFormat("RSI(%d), ", cfg.P_Rsi);
   if(cfg.Ind_Sto_Enabled)        list += StringFormat("Stoch(%d,%d,%d), ", cfg.P_StoK, cfg.P_StoD, cfg.P_StoSlow);
   
   if(list == "") return "None";
   return StringSubstr(list, 0, StringLen(list) - 2);
}

string SEA_UI_BuildActiveVotesList(const ST_Settings &cfg)
{
   string output = "";
   int count = 0;
   if(cfg.Ind_Adx_Enabled)        { output += "  + ADX      (trend strength)\n"; count++; }
   if(cfg.Ind_Macd_Enabled)       { output += "  + MACD     (momentum)\n"; count++; }
   if(cfg.Ind_Rsi_Enabled)        { output += "  + RSI      (momentum zones)\n"; count++; }
   if(cfg.Ind_Cci_Enabled)        { output += "  + CCI      (cyclical)\n"; count++; }
   if(cfg.Ind_Mfi_Enabled)        { output += "  + MFI      (money flow)\n"; count++; }
   if(cfg.Ind_Sto_Enabled)        { output += "  + Stoch    (oscillator)\n"; count++; }
   if(cfg.Ind_Bb_Enabled)         { output += "  + BB       (volatility)\n"; count++; }
   if(cfg.Ind_Psar_Enabled)       { output += "  + PSAR     (trend dir)\n"; count++; }
   if(cfg.Ind_P123_Enabled)       { output += "  + P123     (123 pattern)\n"; count++; }
   if(cfg.Ind_Ross_Enabled)       { output += "  + Ross     (Ross hook)\n"; count++; }
   if(cfg.Ind_Atr_Enabled)        { output += "  + ATR      (volatility rng)\n"; count++; }
   if(cfg.Ind_CandleBody_Enabled) { output += "  + CBody    (body filter)\n"; count++; }
   if(cfg.Ind_CI_Enabled)         { output += "  + CI       (ranging filter)\n"; count++; }
   return output;
}

string SEA_UI_BuildDisabledVotesList(const ST_Settings &cfg)
{
   string list = "";
   if(!cfg.Ind_Adx_Enabled)        list += "ADX, ";
   if(!cfg.Ind_Macd_Enabled)       list += "MACD, ";
   if(!cfg.Ind_Rsi_Enabled)        list += "RSI, ";
   if(!cfg.Ind_Cci_Enabled)        list += "CCI, ";
   if(!cfg.Ind_Mfi_Enabled)        list += "MFI, ";
   if(!cfg.Ind_Sto_Enabled)        list += "Stoch, ";
   if(!cfg.Ind_Bb_Enabled)         list += "BB, ";
   if(!cfg.Ind_Psar_Enabled)       list += "PSAR, ";
   if(!cfg.Ind_P123_Enabled)       list += "P123, ";
   if(!cfg.Ind_Ross_Enabled)       list += "Ross, ";
   if(!cfg.Ind_Atr_Enabled)        list += "ATR, ";
   if(!cfg.Ind_CandleBody_Enabled) list += "CBody, ";
   if(!cfg.Ind_CI_Enabled)         list += "CI, ";
   if(StringLen(list) > 2) list = StringSubstr(list, 0, StringLen(list) - 2);
   if(list == "") return "Disabled Votes: (none)\n";
   return "Disabled Votes:\n  - " + list + "\n";
}

string SEA_UI_BuildIndicatorConfigs(const ST_Settings &cfg)
{
   string output = "Indicator Configs:\n";
   if(cfg.Ind_Macd_Enabled)
      output += StringFormat("  MACD: %d/%d/%d (Fast/Slow/Sig) [%s]\n",
                             cfg.P_MacdFast, cfg.P_MacdSlow, cfg.P_MacdSig,
                             GetMACDModeDescription(cfg.MacdVoteMode, cfg.MacdRequireSlope,
                                                   cfg.MacdRequireDivergence, cfg.MacdRequireHook));
   if(cfg.Ind_Psar_Enabled) {
      string psar_mode = cfg.Vote_AllowPsarFlip ? StringFormat("[FLIP mode: delay=%d bars]", cfg.Vote_PsarFlipDelay) : "[DOT mode]";
      output += StringFormat("  PSAR: Step=%.2f, Max=%.2f %s\n", cfg.P_PsarStep, cfg.P_PsarMax, psar_mode);
   }
   if(cfg.Ind_Rsi_Enabled) output += StringFormat("  RSI: Period=%d, OB=%.0f, OS=%.0f\n", cfg.P_Rsi, cfg.T_RsiOB, cfg.T_RsiOS);
   if(cfg.Ind_Cci_Enabled) output += StringFormat("  CCI: Period=%d\n", cfg.P_Cci);
   if(cfg.Ind_Adx_Enabled) output += StringFormat("  ADX: Period=%d, Threshold=%d\n", cfg.P_Adx, cfg.T_Adx);
   if(cfg.Ind_Sto_Enabled) output += StringFormat("  Stoch: K=%d, D=%d, Slo\n", cfg.P_StoK, cfg.P_StoD, cfg.P_StoSlow);
   if(cfg.Ind_Mfi_Enabled) output += StringFormat("  MFI: Period=%d\n", cfg.P_Mfi);
   if(cfg.Ind_Bb_Enabled)  output += StringFormat("  BB: Period=%d, Dev=%.1f\n", cfg.P_Bb, cfg.P_BbDev);
   return output;
}

//+------------------------------------------------------------------+
//| REFACTORED: Theme-Aware Vote Breakdown (Strategy Zone)           |
//+------------------------------------------------------------------+
// -----------------------------------
// Public API
// -----------------------------------
void SEA_UI_Init(const ulong magic)
{
   // Purge ALL stale SEA_UI_* objects from any previous instance before creating new panels.
   // All SEA UI chart objects use the "SEA_UI_" prefix (enforced by g_sea_ui_base_name).
   for(int i = ObjectsTotal(0) - 1; i >= 0; i--)
   {
      string obj_name = ObjectName(0, i);
      if(StringFind(obj_name, "SEA_UI_") == 0)
         ObjectDelete(0, obj_name);
   }

   g_sea_ui_magic     = magic;
   g_sea_ui_base_name = StringFormat("SEA_UI_%I64d_%I64u", (long)ChartID(), g_sea_ui_magic);
   g_sea_ui_settings_name  = g_sea_ui_base_name + "_SET";
   g_sea_ui_cockpit_name   = g_sea_ui_base_name + "_COCK";
   g_sea_ui_vprr_name      = g_sea_ui_base_name + "_VPRR";
   g_sea_ui_vprr_init_name = g_sea_ui_base_name + "_VPRR_INIT";
}

void SEA_UI_DestroyAll()
{
   SEA_UI_DestroyPanel(g_sea_ui_settings_name);
   SEA_UI_DestroyPanel(g_sea_ui_cockpit_name);
   SEA_UI_DestroyPanel(g_sea_ui_vprr_name);
   SEA_UI_DestroyPanel(g_sea_ui_vprr_init_name);
   SEA_UI_ClearMTFSegments();
   
   // Clean up dedicated Master Telemetry Objects
   ObjectDelete(0, "SEA_UI_TS_MASTER");
   ObjectDelete(0, "SEA_UI_TE_MASTER");

   // Prefix scan: delete any remaining SEA_UI_* objects from any instance (ghost panel cleanup).
   // All SEA UI chart objects use the "SEA_UI_" prefix (enforced by g_sea_ui_base_name).
   for(int i = ObjectsTotal(0) - 1; i >= 0; i--)
   {
      string obj_name = ObjectName(0, i);
      if(StringFind(obj_name, "SEA_UI_") == 0)
         ObjectDelete(0, obj_name);
   }
   
   g_sea_ui_last_settings_txt = "";
   g_sea_ui_last_cockpit_txt  = "";
}

//+------------------------------------------------------------------+
//| SETTINGS PANEL (Refactored for Institutional Vertical Grid)      |
//+------------------------------------------------------------------+
void SEA_UI_UpdateSettingsPanel(EMarketPhase current_phase = PHASE_UNORDERED)
{
   if(!Inp_UI_ShowStatusPanel)
   {
      SEA_UI_DestroyPanel(g_sea_ui_settings_name);
      return;
   }

   string lines[]; color line_clrs[];
   ArrayResize(lines, 0); ArrayResize(line_clrs, 0);

   // Use the resolved master color for standard values and Gold for headers
   color v_clr = SEA_UI_ForeColor();
   color h_clr = Settings.clr_Header;  

   // --- ZONE 1: SYSTEM ARCHITECTURE ---
   AddLine("--- SYSTEM ARCHITECTURE ---", h_clr, lines, line_clrs);
   AddLine(StringFormat("VER:      %s", SEA_BUILD_STR), v_clr, lines, line_clrs);
   AddLine(StringFormat("SYMBOL:   %s %s", _Symbol, EnumToString(_Period)), v_clr, lines, line_clrs);
   AddLine(StringFormat("PRESET:   %s", EnumToString(Inp_Global_Preset)), v_clr, lines, line_clrs);
   AddLine(StringFormat("MODE:     %s", (Inp_Global_Preset == PRESET_CUSTOM ? "CUSTOM" : "LOCKED")), v_clr, lines, line_clrs);
   AddLine("", (color)0, lines, line_clrs); // Spacer

   // --- ZONE 2: BIAS & STRUCTURE ---
   AddLine("--- BIAS & STRUCTURE ---", h_clr, lines, line_clrs);
   AddLine(StringFormat("STRATEGY: %s", EnumToString(Settings.AutoStrat)), v_clr, lines, line_clrs);
   AddLine(StringFormat("BIAS:     %s", EnumToString(Settings.BiasMode)), v_clr, lines, line_clrs);
   AddLine(StringFormat("EMAS:     %s", SEA_UI_BiasEmaLabel(Settings)), v_clr, lines, line_clrs);
   AddLine(StringFormat("RIBBON:   %d/%d/%d/%d", Settings.P_Ema1, Settings.P_Ema2, Settings.P_Ema3, Settings.P_Ema4), v_clr, lines, line_clrs);
   AddLine("", (color)0, lines, line_clrs); // Spacer
   
   // --- ZONE 3: ENVIRONMENT AUDIT ---
   AddLine("--- ENVIRONMENT AUDIT ---", h_clr, lines, line_clrs);
   color phase_color;
   string phase_label = SEA_UI_FormatPhase(current_phase, phase_color);
   AddLine(StringFormat("PHASE:    %s", phase_label), phase_color, lines, line_clrs);
   AddLine(StringFormat("ALLOWED:  %s", SEA_UI_FormatAllowedLayers(current_phase, Settings.PhaseDetectionEnabled)), phase_color, lines, line_clrs);
   AddLine(StringFormat("F-PHASE:  %s", (Settings.PhaseDetectionEnabled ? "ON" : "OFF")), v_clr, lines, line_clrs);
   AddLine(StringFormat("F-LAYER:  %s", (Settings.EnableLayerDetection ? "ON" : "OFF")), v_clr, lines, line_clrs);
   AddLine("", (color)0, lines, line_clrs); // Spacer

   // --- ZONE 4: VOTE CONFIGURATION ---
   AddLine("--- VOTE CONFIGURATION ---", h_clr, lines, line_clrs);
   string vote_list = SEA_UI_BuildActiveVotesList(Settings); 
   string vote_lines[];
   int v_total = StringSplit(vote_list, '\n', vote_lines);
   for(int i=0; i<v_total; i++) {
      if(vote_lines[i] != "" && StringLen(vote_lines[i]) > 1) 
         AddLine(vote_lines[i], v_clr, lines, line_clrs);
   }
   AddLine("", (color)0, lines, line_clrs); // Spacer
   
   // --- ZONE 5: RISK & PROTECTION ---
   AddLine("--- RISK & PROTECTION ---", h_clr, lines, line_clrs);
   AddLine(StringFormat("SIZER:    %s", (Settings.UseMACompatSizer ? "MA_COMPAT" : "RISK_PCT")), v_clr, lines, line_clrs);
   AddLine(StringFormat("SL MODE:  %s", EnumToString(Settings.SLMode)), v_clr, lines, line_clrs);
   AddLine(StringFormat("RISK:     %.2f%%", Settings.RiskPercent), v_clr, lines, line_clrs);
   string rr_source = "Inp_CUSTOM_RRRatio";
   // STEP3 2026-06: removed `if(Inp_Global_Preset == PRESET_RRM) rr_source = "Inp_RRM_RRRatio";` — PRESET_RRM gone
   if(Inp_Global_Preset == PRESET_RRM_ORG)
      rr_source = "Inp_RRM_ORG_RRRatio";
   else if(Inp_Global_Preset == PRESET_FPM)
      rr_source = "Inp_FPM_RRRatio";
   AddLine(StringFormat("RR:       %.2f  (src: %s)", Settings.RRRatio, rr_source), v_clr, lines, line_clrs);
   AddLine(StringFormat("BE:       %s", (Settings.BE_Mode != BE_MODE_OFF ? "ENABLED" : "OFF")), v_clr, lines, line_clrs);

   // Construct full text to check for changes
   string full_txt = "";
   for(int i=0; i<ArraySize(lines); i++) 
   {
      if(lines[i] == "") lines[i] = " ";
      full_txt += lines[i] + "\n";
   }

   if(full_txt == g_sea_ui_last_settings_txt) return;
   g_sea_ui_last_settings_txt = full_txt;

   // Call the render engine with all 9 parameters
   SEA_UI_RenderPanel(
      g_sea_ui_settings_name, 
      full_txt, 
      Inp_UI_PanelCorner, 
      Inp_UI_PanelX, 
      Inp_UI_PanelY, 
      Inp_UI_PanelFontSize, 
      Inp_UI_PanelLineSpacingPx, 
      Inp_UI_PanelFont,
      line_clrs 
   );
}

//+------------------------------------------------------------------+
//| COCKPIT PANEL - Full Institutional Grid & Logic Audit Restoration|
//+------------------------------------------------------------------+
void SEA_UI_UpdateCockpit(
   CSignalEngine &signal,
   const ST_SignalTelemetry &ts_telemetry,
   double active_lots,
   double initial_risk_money,
   double active_reward_money, 
   double initial_sl_pips,
   double current_sl_pips,
   double active_tp_pips, 
   double current_rr, 
   double config_risk_pct, 
   double current_risk_pct,
   double current_risk_money,
   string config_trail_method,
   string last_te_result  = "",
   string last_te_veto    = "",
   int    cooldown_bars_remaining = 0
) {
   if(!Inp_UI_ShowCockpitPanel) {
      SEA_UI_DestroyPanel(g_sea_ui_cockpit_name);
      SEA_UI_ClearMTFSegments();
      return;
   }

   string lines[]; 
   color line_clrs[];
   ArrayResize(lines, 0); 
   ArrayResize(line_clrs, 0);

   // --- COLOR RESOLUTION (Respecting Dashboard Theme) ---
   color h_clr = Settings.clr_Header;
   color v_clr = (Settings.clr_Value != 0) ? Settings.clr_Value : clrWhite;
   int mtf_line_index = -1;

   // --- MARKET CONTEXT (Extended Information) ---
   AddLine("--- MARKET CONTEXT ---", h_clr, lines, line_clrs);
   
   double ask_val = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid_val = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double spread_val = (ask_val - bid_val) / _Point;
   long stop_lvl = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   
   AddLine(StringFormat("SPREAD:    %.1f Pips", spread_val), v_clr, lines, line_clrs);
   AddLine(StringFormat("STOPLEVEL: %d Pips", (int)stop_lvl), v_clr, lines, line_clrs);
   
   string status_text = SEA_UI_NormalizeStatusText(ts_telemetry.rejection_reason);
   bool is_valid = (status_text == "Valid Signal" || status_text == "OK");
   string sig_str = is_valid ? ((ts_telemetry.bias == 1) ? "BUY" : "SELL") : "FLAT";
   AddLine(StringFormat("STATUS:    %s", status_text), (is_valid ? Settings.clr_Pass : Settings.clr_Fail), lines, line_clrs);
   AddLine(StringFormat("SIGNAL:    %s", sig_str), v_clr, lines, line_clrs);
   mtf_line_index = ArraySize(lines);
   AddLine(" ", Settings.clr_Disabled, lines, line_clrs);

   AddLine("", (color)0, lines, line_clrs); 
   
   // --- STRATEGY LOGIC (The Institutional Grid) ---
   AddLine("--- STRATEGY LOGIC ---", h_clr, lines, line_clrs);

   AddLine(StringFormat("PRESET:    %s", GetPresetContractWording(Inp_Global_Preset)), h_clr, lines, line_clrs);

   // Effective display values: always use live telemetry (no carry-forward freeze state)
   int          disp_bias  = ts_telemetry.bias;
   int          disp_votes = ts_telemetry.votes_for;
   EMarketPhase disp_phase = (EMarketPhase)ts_telemetry.phase;

   // 1. Standardized Equation: TS = B * P * L * I * F
   int    disp_phase_val = (int)disp_phase;
   string b_eq = (disp_bias  > 0) ? "+" : ((disp_bias  < 0) ? "-" : ".");
   string p_eq = (disp_phase_val > 0) ? "+" : ((disp_phase_val < 0) ? "-" : ".");
   string l_eq = (ts_telemetry.layer > 0) ? "+" : ((ts_telemetry.layer < 0) ? "-" : ".");
   string i_eq = (disp_votes > 0) ? "+" : ".";
   bool filter_rejected = (StringFind(status_text, "HTF")    >= 0 ||
                           StringFind(status_text, "MTF")    >= 0 ||
                           StringFind(status_text, "Filter") >= 0 ||
                           StringFind(status_text, "TIME")   >= 0 ||
                           StringFind(status_text, "SPREAD") >= 0 ||
                           StringFind(status_text, "NEWS")   >= 0);
   bool signal_valid    = (status_text == "Valid Signal" ||
                           status_text == "OK");
   string f_eq = filter_rejected ? "-" : (signal_valid ? "+" : ".");

   AddLine(StringFormat("TS EQ: TS = B[%s] * P[%s] * L[%s] * I[%s] * F[%s]", b_eq, p_eq, l_eq, i_eq, f_eq), v_clr, lines, line_clrs);
   AddLine(StringFormat("VOTE:  %d / %d", disp_votes, ts_telemetry.votes_total), v_clr, lines, line_clrs);

   // 2. Component Detail Audit
   string bias_sym = (disp_bias > 0) ? "[+]" : (disp_bias < 0 ? "[-]" : "[.]");
   color  bias_clr = (disp_bias > 0) ? Settings.clr_Pass : (disp_bias < 0 ? Settings.clr_Pass : Settings.clr_Disabled);
   AddLine(StringFormat("  BIAS:  %s %s", SEA_UI_BiasLabel(disp_bias), bias_sym), bias_clr, lines, line_clrs);
   
   if(ts_telemetry.phase_detection_enabled)
   {
      color phase_clr;
      string phase_label = SEA_UI_FormatPhase(disp_phase, phase_clr);
      bool phase_trending  = (disp_phase == PHASE_TRENDING || disp_phase == PHASE_TRENDING_UP || disp_phase == PHASE_TRENDING_DN);
      bool phase_unordered = (disp_phase == PHASE_UNORDERED);
      string phase_sym = phase_trending ? "[+]" : (phase_unordered ? "[-]" : "[.]");
      AddLine(StringFormat("  PHASE: %s %s", phase_label, phase_sym), phase_clr, lines, line_clrs);

      // ── Ribbon snapshot lines (single source of truth) ────────────────────
      // Reads from ts_telemetry.ribbon — populated once per evaluation pass by
      // RefreshRibbonSnapshot in the engine. Periods are sourced from Settings
      // at display time so labels stay in sync if the user reconfigures.
      //
      // Each slot is annotated with its provenance ("iMA" normal / "MAN" used
      // manual fallback / "ERR" both paths failed). If any slot needed for
      // phase classification is invalid, the implied phase is suppressed.
      int      ema_dig = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
      int      P[4];
      P[0] = Settings.P_Ema1;
      P[1] = Settings.P_Ema2;
      P[2] = Settings.P_Ema3;
      P[3] = Settings.P_Ema4;

      // Format each slot: "13=1.15173" when normal, "34=1.15224(MAN)" when
      // the manual fallback fired, "89=INVALID(ERR)" when both tiers failed.
      // The (iMA) annotation is suppressed to keep the line compact —
      // absence of a source tag means "normal iMA read".
      string fmt_slot[4];
      for(int k = 0; k < 4; k++)
      {
         double vk  = ts_telemetry.ribbon.ema[k];
         bool   okk = ts_telemetry.ribbon.valid[k];
         string sk  = ts_telemetry.ribbon.src[k];
         if(!okk)            fmt_slot[k] = StringFormat("%d=INVALID(%s)", P[k], sk);
         else if(sk == "iMA") fmt_slot[k] = StringFormat("%d=%.*f", P[k], ema_dig, vk);
         else                fmt_slot[k] = StringFormat("%d=%.*f(%s)", P[k], ema_dig, vk, sk);
      }
      AddLine(StringFormat("  EMAS:  %s  %s  %s  %s",
                           fmt_slot[0], fmt_slot[1], fmt_slot[2], fmt_slot[3]),
              v_clr, lines, line_clrs);

      // Implied-phase decoder: only meaningful when slots 2/3/4 are all valid
      // (slot 1 not used in phase classification). Compares slots positionally
      // per RRM book card; period numbers shown alongside slot ordering for
      // human cross-reference against the chart.
      bool ok2 = ts_telemetry.ribbon.valid[1];
      bool ok3 = ts_telemetry.ribbon.valid[2];
      bool ok4 = ts_telemetry.ribbon.valid[3];
      if(ok2 && ok3 && ok4)
      {
         double v2 = ts_telemetry.ribbon.ema[1];
         double v3 = ts_telemetry.ribbon.ema[2];
         double v4 = ts_telemetry.ribbon.ema[3];
         string o23 = (v2 > v3) ? ">" : (v2 < v3 ? "<" : "=");
         string o34 = (v3 > v4) ? ">" : (v3 < v4 ? "<" : "=");
         string o24 = (v2 > v4) ? ">" : (v2 < v4 ? "<" : "=");
         string implied = "UNORDERED";
         if(o23 == ">" && o34 == ">")                        implied = "TRENDING_UP";
         else if(o23 == "<" && o34 == "<")                   implied = "TRENDING_DN";
         else if(o23 == ">" && o34 == "<" && o24 == ">")     implied = "EMERGING_UP";
         else if(o23 == "<" && o34 == ">" && o24 == "<")     implied = "EMERGING_DN";
         AddLine(StringFormat("  ORDER: %d%s%d  %d%s%d  %d%s%d  -> %s",
                              P[1], o23, P[2],
                              P[2], o34, P[3],
                              P[1], o24, P[3],
                              implied),
                 v_clr, lines, line_clrs);
      }
      else
      {
         AddLine("  ORDER: (suppressed — one or more slots invalid)",
                 Settings.clr_Fail, lines, line_clrs);
      }
   }
   else
   {
      AddLine("  PHASE: N/A (BIAS_2EMA mode)", Settings.clr_Disabled, lines, line_clrs);
   }

   // Per-sub-market layer signals
   if(ts_telemetry.layer_detection_enabled)
   {
      string lw_sym = (ts_telemetry.diag_layer_w ==  1 ? "[+]" : ts_telemetry.diag_layer_w == -1 ? "[-]" : "[.]");
      string lm_sym = (ts_telemetry.diag_layer_m ==  1 ? "[+]" : ts_telemetry.diag_layer_m == -1 ? "[-]" : "[.]");
      string ls_sym = (ts_telemetry.diag_layer_s ==  1 ? "[+]" : ts_telemetry.diag_layer_s == -1 ? "[-]" : "[.]");
      color lw_clr = (ts_telemetry.diag_layer_w == 1 ? Settings.clr_Pass : ts_telemetry.diag_layer_w == -1 ? Settings.clr_Fail : Settings.clr_Disabled);
      color lm_clr = (ts_telemetry.diag_layer_m == 1 ? Settings.clr_Pass : ts_telemetry.diag_layer_m == -1 ? Settings.clr_Fail : Settings.clr_Disabled);
      color ls_clr = (ts_telemetry.diag_layer_s == 1 ? Settings.clr_Pass : ts_telemetry.diag_layer_s == -1 ? Settings.clr_Fail : Settings.clr_Disabled);
      // Show active layer bitfield label
      string active_lbl = SEA_UI_EntryLayerLabel((EEntryLayer)ts_telemetry.layer);
      if(active_lbl == "") active_lbl = "(none)";
      AddLine(StringFormat("  WEAK:  EMA1/EMA2 %s", lw_sym), lw_clr, lines, line_clrs);
      AddLine(StringFormat("  MED:   EMA2/EMA3 %s", lm_sym), lm_clr, lines, line_clrs);
      AddLine(StringFormat("  STR:   EMA3/EMA4 %s", ls_sym), ls_clr, lines, line_clrs);
      AddLine(StringFormat("  ACTIVE LAYER: %s", active_lbl), v_clr, lines, line_clrs);
   }
   else
   {
      AddLine("  LAYER: N/A (phase detection off)", Settings.clr_Disabled, lines, line_clrs);
   }

   // VPRR: Volume Pullback-Recovery Ratio (only shown when the voter is on)
   if(ts_telemetry.vprr_enabled)
   {
      string vprr_sym = ts_telemetry.vprr_pass ? "[+]" : "[.]";
      color  vprr_clr = ts_telemetry.vprr_pass ? Settings.clr_Pass : Settings.clr_Disabled;
      AddLine(StringFormat("  VPRR:  %.2f (min %.2f) %s  Vol:%s",
                           ts_telemetry.vprr_ratio,
                           ts_telemetry.vprr_min_ratio,
                           vprr_sym,
                           ts_telemetry.vprr_vol_source),
              vprr_clr, lines, line_clrs);
   }

   // 3. INDICATOR AUDIT (Detailed MACD, CCI, PSAR restoration)
   string ind_parts[];
   int ind_count = StringSplit(ts_telemetry.active_indicators, '\n', ind_parts);
   
   for(int i = 0; i < ind_count; i++) {
      string item = ind_parts[i];
      StringTrimLeft(item); 
      StringTrimRight(item);
      if(item == "") continue;

      string clean_name = item;
      string eval_sym   = "(.)";
      color  line_clr   = Settings.clr_Disabled;

      // Reformat brackets [+] to institutional parenthesis (+) for the grid
      if(StringFind(item, "[+]") >= 0) { 
         StringReplace(clean_name, "[+]", ""); 
         eval_sym = "(+)"; 
         line_clr = Settings.clr_Pass;
      }
      else if(StringFind(item, "[-]") >= 0) { 
         StringReplace(clean_name, "[-]", ""); 
         eval_sym = "(-)"; 
         line_clr = Settings.clr_Fail;
      }
      else if(StringFind(item, "[.]") >= 0) { 
         StringReplace(clean_name, "[.]", ""); 
         eval_sym = "(.)"; 
         line_clr = Settings.clr_Disabled; 
      }

      StringTrimLeft(clean_name);
      AddLine(StringFormat("  %s %s", clean_name, eval_sym), line_clr, lines, line_clrs);
   }

   AddLine("", (color)0, lines, line_clrs); 
   
   // --- EXECUTION GATE ---
   AddLine("--- EXECUTION GATE ---", h_clr, lines, line_clrs);

   if(active_lots > 0)
   {
      AddLine("STATE:  ACTIVE", Settings.clr_Pass, lines, line_clrs);
   }
   else if(last_te_result == "ENTERED")
   {
      AddLine("STATE:  ENTERED", Settings.clr_Pass, lines, line_clrs);
   }
   else if(last_te_result == "BLOCKED" || last_te_result == "VETO")
   {
      string veto_label = (last_te_veto != "" && last_te_veto != "OK") ? last_te_veto : "BLOCKED";
      AddLine(StringFormat("STATE:  TE_BLOCKED [%s]", veto_label), clrRed, lines, line_clrs);
   }
   else
   {
      AddLine("STATE:  MONITORING", v_clr, lines, line_clrs);
   }

   if(cooldown_bars_remaining > 0)
      AddLine(StringFormat("COOLDOWN: %d bars", cooldown_bars_remaining), clrGold, lines, line_clrs);
   else if(Settings.MinBarsAfterClose > 0)
      AddLine("COOLDOWN: ready", v_clr, lines, line_clrs);

   AddLine("", (color)0, lines, line_clrs);

   // --- RISK & PROTECTION (Orig | Bar) ---
   AddLine("--- RISK & PROTECTION (Orig | Bar) ---", h_clr, lines, line_clrs);
   if(active_lots == 0) {
      AddLine(StringFormat("RISK:  %.2f%%  TRAIL: %s", config_risk_pct, config_trail_method), v_clr, lines, line_clrs);
   } 
   else {
      // Color current risk green when trail has cut exposure significantly (< 50% of original)
      bool risk_reduced = (current_risk_pct > 0.0 && current_risk_pct < config_risk_pct * 0.5);
      color risk_clr = risk_reduced ? Settings.clr_Pass : v_clr;

      // Setup RR from original SL (fixed at entry)
      double setup_rr = (initial_sl_pips > 0.0 && active_tp_pips > 0.0) ? (active_tp_pips / initial_sl_pips) : 0.0;

      AddLine(StringFormat("RISK:  %.2f%%($%.0f) | %.2f%%($%.0f)",
              config_risk_pct, initial_risk_money,
              current_risk_pct, current_risk_money),
              risk_clr, lines, line_clrs);
      AddLine(StringFormat("SL:    %.1f pips | %.1f pips",
              initial_sl_pips, current_sl_pips),
              v_clr, lines, line_clrs);
      AddLine(StringFormat("TP:    %.1f pips ($%.0f)",
              active_tp_pips, active_reward_money),
              v_clr, lines, line_clrs);
      AddLine(StringFormat("RR:    %.2f setup | %.2f cur",
              setup_rr, current_rr),
              v_clr, lines, line_clrs);
   }

   // --- FINAL RENDER ---
   string cockpit_txt = "";
   for(int k = 0; k < ArraySize(lines); k++) cockpit_txt += lines[k] + "\n";

   if(cockpit_txt != g_sea_ui_last_cockpit_txt) {
      g_sea_ui_last_cockpit_txt = cockpit_txt;
      SEA_UI_RenderPanel(
         g_sea_ui_cockpit_name, cockpit_txt, Inp_UI_CockpitCorner, 
         Inp_UI_CockpitX, Inp_UI_CockpitY, Inp_UI_PanelFontSize, 
         Inp_UI_PanelLineSpacingPx, Inp_UI_PanelFont, line_clrs
      );
   }

   SEA_UI_DrawMTFSegments(signal, mtf_line_index);
}

//+------------------------------------------------------------------+
//| Helper to append lines to the render arrays                      |
//+------------------------------------------------------------------+
void AddLine(string text, color clr, string &lines_arr[], color &clrs_arr[]) 
{
   int sz = ArraySize(lines_arr);
   if(ArrayResize(lines_arr, sz + 1) != sz + 1) return;
   if(ArrayResize(clrs_arr, sz + 1) != sz + 1) return;
   lines_arr[sz] = text;
   clrs_arr[sz] = clr;
}

//+------------------------------------------------------------------+
//| INTERNAL HELPER: Safe Indicator Attachment & Audit Logging      |
//+------------------------------------------------------------------+
// This replaces the "Performance Patch" standalone function.
void _SEA_UI_AddIndicator(int subwindow, int handle, string label, int &added_counter)
{
   bool allow_log = (Settings.DebugLevel > 0);
   
   if(handle == INVALID_HANDLE)
   {
      if(allow_log) PrintFormat("UI: Cannot add indicator [%s] - Invalid handle.", label);
      return;
   }

   if(ChartIndicatorAdd(0, subwindow, handle))
   {
      added_counter++;
      if(allow_log) PrintFormat("  ✓ %s added to window %d", label, subwindow);
   }
   else
   {
      if(allow_log) PrintFormat("  ⚠ Failed to add [%s]. Error: %d", label, GetLastError());
   }
}

//+------------------------------------------------------------------+
//| PUBLIC API: Flexible Chart Indicator Management                 |
//+------------------------------------------------------------------+
// This is the master function that rebuilds the chart from settings.
void SEA_UI_ManageChartIndicators(CSignalEngine &engine)
{
   // 1. Wipe the Chart Slate to prevent duplicate overlays
   int win_total = (int)ChartGetInteger(0, CHART_WINDOWS_TOTAL);
   for(int w = win_total - 1; w >= 0; w--)
   {
      int total = ChartIndicatorsTotal(0, w);
      while(total > 0)
      {
         string nm = ChartIndicatorName(0, w, 0);
         if(nm == "") break;
         ChartIndicatorDelete(0, w, nm);
         total = ChartIndicatorsTotal(0, w);
      }
   }

   Print("═══════════════════════════════════════════════════════════");
   Print("UI: Institutional Indicator Sync - Rebuilding from Settings");
   Print("═══════════════════════════════════════════════════════════");

   int overlays = 0;
   int sub_added = 0;
   int ts_active = 0;

   // --- ZONE 1: MAIN CHART OVERLAYS (Subwindow 0) ---
   
   if(Settings.MABenchmarkStrict) 
      _SEA_UI_AddIndicator(0, engine.GetPrimaryMAHandle(), "Benchmark MA", overlays);

   // EMA Ribbon Logic
   bool need_ema[4];
   need_ema[0] = (Settings.BiasFastID == 0 || Settings.BiasSlowID == 0);
   need_ema[1] = (Settings.BiasFastID == 1 || Settings.BiasSlowID == 1);
   need_ema[2] = (Settings.BiasFastID == 2 || Settings.BiasSlowID == 2);
   need_ema[3] = (Settings.BiasFastID == 3 || Settings.BiasSlowID == 3);

   for(int i = 0; i < 4; i++) {
      if(need_ema[i]) {
         string label = StringFormat("EMA%d (%d)", i+1, Settings.P_Ema1 + (i*8));
         _SEA_UI_AddIndicator(0, engine.GetEmaHandle(i), label, overlays);
      }
   }

   if(Settings.Ind_Psar_Enabled || Settings.TrailMode == TRAIL_PSAR) {
      _SEA_UI_AddIndicator(0, engine.GetPsarHandle(), "PSAR", overlays);
      if(Settings.Ind_Psar_Enabled) ts_active++;
   }

   if(Settings.Ind_Bb_Enabled) {
      _SEA_UI_AddIndicator(0, engine.GetBbHandle(), "Bollinger Bands", overlays);
      ts_active++;
   }

   if(Settings.Ind_MTF_Enabled)  // MTF indicator overlay
   {
      if(engine.GetMtfTf1FastHandle() != INVALID_HANDLE)
         _SEA_UI_AddIndicator(0, engine.GetMtfTf1FastHandle(), 
            StringFormat("MTF %s Fast EMA", EnumToString(Settings.MTF_TF1)), overlays);  // ← CHANGED
      if(engine.GetMtfTf1SlowHandle() != INVALID_HANDLE)
         _SEA_UI_AddIndicator(0, engine.GetMtfTf1SlowHandle(), 
            StringFormat("MTF %s Slow EMA", EnumToString(Settings.MTF_TF1)), overlays);  // ← CHANGED
      if(engine.GetMtfTf2FastHandle() != INVALID_HANDLE)
         _SEA_UI_AddIndicator(0, engine.GetMtfTf2FastHandle(), 
            StringFormat("MTF %s Fast EMA", EnumToString(Settings.MTF_TF2)), overlays);  // ← CHANGED
      if(engine.GetMtfTf2SlowHandle() != INVALID_HANDLE)
         _SEA_UI_AddIndicator(0, engine.GetMtfTf2SlowHandle(), 
            StringFormat("MTF %s Slow EMA", EnumToString(Settings.MTF_TF2)), overlays);  // ← CHANGED
   }

   if(Settings.TrailMode == TRAIL_FRACTAL) 
      _SEA_UI_AddIndicator(0, engine.GetFractalHandle(), "Fractals (Trail)", overlays);

   if(Settings.Ind_P123_Enabled) { _SEA_UI_AddIndicator(0, engine.GetP123Handle(), "123 Pattern", overlays); ts_active++; }
   if(Settings.Ind_Ross_Enabled) { _SEA_UI_AddIndicator(0, engine.GetRossHandle(), "Ross Hook", overlays); ts_active++; }

   // --- ZONE 2: SUBWINDOW OSCILLATORS (Dynamic Window Incrementing) ---
   
   int sw = 1; // Current subwindow counter
   int sw_count = 0;

   if(Settings.Ind_Macd_Enabled) { 
      int prev = sw_count;
      _SEA_UI_AddIndicator(sw, engine.GetMacdHandle(), "MACD", sw_count); 
      if(sw_count > prev) { sw++; ts_active++; } 
   }
   if(Settings.Ind_Rsi_Enabled) { 
      int prev = sw_count;
      _SEA_UI_AddIndicator(sw, engine.GetRsiHandle(), "RSI", sw_count); 
      if(sw_count > prev) { sw++; ts_active++; } 
   }
   if(Settings.Ind_Cci_Enabled) { 
      int prev = sw_count;
      _SEA_UI_AddIndicator(sw, engine.GetCciHandle(), "CCI", sw_count); 
      if(sw_count > prev) { sw++; ts_active++; } 
   }
   if(Settings.Ind_Mfi_Enabled) { 
      int prev = sw_count;
      _SEA_UI_AddIndicator(sw, engine.GetMfiHandle(), "MFI", sw_count); 
      if(sw_count > prev) { sw++; ts_active++; } 
   }
   if(Settings.Ind_Sto_Enabled) { 
      int prev = sw_count;
      _SEA_UI_AddIndicator(sw, engine.GetStoHandle(), "Stoch", sw_count); 
      if(sw_count > prev) { sw++; ts_active++; } 
   }
   if(Settings.Ind_Adx_Enabled) { 
      int prev = sw_count;
      _SEA_UI_AddIndicator(sw, engine.GetAdxHandle(), "ADX", sw_count); 
      if(sw_count > prev) { sw++; ts_active++; } 
   }
   if(Settings.Ind_Atr_Enabled) { 
      int prev = sw_count;
      _SEA_UI_AddIndicator(sw, engine.GetAtrHandle(), "ATR", sw_count); 
      if(sw_count > prev) { sw++; ts_active++; } 
   }
   if(Settings.Ind_CI_Enabled) { 
      int prev = sw_count;
      _SEA_UI_AddIndicator(sw, engine.GetCiHandle(), "CI", sw_count); 
      if(sw_count > prev) { sw++; ts_active++; } 
   }

   // Internal-only components
   if(Settings.Ind_VRC_Enabled) ts_active++;
   if(Settings.Ind_CandleBody_Enabled) ts_active++;

   Print("───────────────────────────────────────────────────────────");
   Print("UI: Chart indicator synchronization complete");
   Print(StringFormat("  → %d Overlays | %d Subwindows | %d TS Components Active", overlays, sw-1, ts_active));
   Print("═══════════════════════════════════════════════════════════");
}

//+------------------------------------------------------------------+
//| SEA_UI_StoreVPRRContent: called from PrintVPRRSummary() during   |
//| preset application (before SEA_UI_Init). Stores content so       |
//| SEA_UI_RenderDeferredVPRR() can draw it after panel names init.  |
//+------------------------------------------------------------------+
void SEA_UI_StoreVPRRContent(const string &lines[], const color &clrs[])
{
   int n = ArraySize(lines);
   ArrayResize(g_sea_ui_vprr_lines, n);
   ArrayResize(g_sea_ui_vprr_clrs, n);
   for(int i = 0; i < n; i++)
   {
      g_sea_ui_vprr_lines[i] = lines[i];
      g_sea_ui_vprr_clrs[i]  = clrs[i];
   }
}

//+------------------------------------------------------------------+
//| SEA_UI_RenderDeferredVPRR: called from OnInit AFTER SEA_UI_Init  |
//| so panel names are valid. Uses shared font/spacing inputs.        |
//+------------------------------------------------------------------+
void SEA_UI_RenderDeferredVPRR()
{
   if(!Inp_UI_ShowVPRRPanel || g_sea_ui_vprr_name == "")
   {
      SEA_UI_DestroyPanel(g_sea_ui_vprr_name);
      return;
   }
   int n = ArraySize(g_sea_ui_vprr_lines);
   if(n == 0)
   {
      SEA_UI_DestroyPanel(g_sea_ui_vprr_name);
      return;
   }

   string txt = "";
   for(int i = 0; i < n; i++)
   {
      if(i > 0) txt += "\n";
      txt += g_sea_ui_vprr_lines[i];
   }

   SEA_UI_RenderPanel(
      g_sea_ui_vprr_name, txt,
      Inp_UI_VPRRCorner,
      Inp_UI_VPRR_X, Inp_UI_VPRR_Y,
      Inp_UI_PanelFontSize,
      Inp_UI_PanelLineSpacingPx,
      Inp_UI_PanelFont,
      g_sea_ui_vprr_clrs);
}

//+------------------------------------------------------------------+
//| SEA_UI_StoreVPRRInitContent: called from ValidateVPRRExternal    |
//| Symbol() to store validation results for deferred rendering.     |
//+------------------------------------------------------------------+
void SEA_UI_StoreVPRRInitContent(const string &lines[], const color &clrs[])
{
   int n = ArraySize(lines);
   ArrayResize(g_sea_ui_vprr_init_lines, n);
   ArrayResize(g_sea_ui_vprr_init_clrs,  n);
   for(int i = 0; i < n; i++)
   {
      g_sea_ui_vprr_init_lines[i] = lines[i];
      g_sea_ui_vprr_init_clrs[i]  = clrs[i];
   }
}

//+------------------------------------------------------------------+
//| SEA_UI_RenderVPRRInitPanel: renders the VPRR Init Check panel.   |
//| Called from OnInit() after SEA_UI_Init() so panel name is valid. |
//| Controlled by Inp_UI_ShowVPRRInitPanel (default ON).             |
//| Set Inp_UI_ShowVPRRInitPanel=false after setup verified to hide. |
//+------------------------------------------------------------------+
void SEA_UI_RenderVPRRInitPanel()
{
   if(!Inp_UI_ShowVPRRInitPanel || g_sea_ui_vprr_init_name == "")
   {
      SEA_UI_DestroyPanel(g_sea_ui_vprr_init_name);
      return;
   }
   int n = ArraySize(g_sea_ui_vprr_init_lines);
   if(n == 0)
   {
      SEA_UI_DestroyPanel(g_sea_ui_vprr_init_name);
      return;
   }

   string txt = "";
   for(int i = 0; i < n; i++)
   {
      if(i > 0) txt += "\n";
      txt += g_sea_ui_vprr_init_lines[i];
   }

   SEA_UI_RenderPanel(
      g_sea_ui_vprr_init_name, txt,
      Inp_UI_VPRRInitCorner,
      Inp_UI_VPRRInit_X, Inp_UI_VPRRInit_Y,
      Inp_UI_PanelFontSize,
      Inp_UI_PanelLineSpacingPx,
      Inp_UI_PanelFont,
      g_sea_ui_vprr_init_clrs);
}
