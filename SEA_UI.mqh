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

void SEA_UI_DestroyPanel(const string panel_name)
{
   if(panel_name == "") return;

   string bg = panel_name + "_BG";
   ObjectDelete(0, bg);
   for(int i=0; i<70; i++)
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
   for(int i=0; i<75; i++) {
      string ln = panel_name + StringFormat("_L%02d", i);
      
      if(i < n) {
         // Create if missing, then update with real data
         if(ObjectFind(0, ln) < 0) ObjectCreate(0, ln, OBJ_LABEL, 0, 0, 0);
         
         color clr = (i < ArraySize(line_colors)) ? line_colors[i] : SEA_UI_ForeColor();
         
         ObjectSetInteger(0, ln, OBJPROP_CORNER, (int)corner);
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
   for(int i=n; i<75; i++) ObjectDelete(0, panel_name + StringFormat("_L%02d", i));
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
   out_be = (dist_to_be <= 0 ? "ACTIVE" : StringFormat("%.1f P", dist_to_be));
}

// -----------------------------------
// Performance Patch: ManageChartIndicators
// -----------------------------------
void SEA_UI_ManageChartIndicators(const ST_Settings &cfg, int handle, string label)
{
   bool allow_log = (cfg.DebugLevel > 0);
   if(handle == INVALID_HANDLE)
   {
      if(allow_log) PrintFormat("UI: Cannot add indicator [%s] - Invalid handle.", label);
      return;
   }

   if(ChartIndicatorAdd(0, 0, handle))
   {
      if(allow_log) PrintFormat("UI: Indicator [%s] added to chart successfully.", label);
   }
   else
   {
      if(allow_log) PrintFormat("UI: Failed to add indicator [%s]. Error: %d", label, GetLastError());
   }
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
   if(cfg.Ind_EmaSig_Enabled)     list += StringFormat("EmaSig(%d), ", cfg.P_Ema1);
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
   if(cfg.Ind_EmaSig_Enabled)     { output += StringFormat("  + EmaSig   (EMA1 price pos)  w=%d\n", cfg.Ind_EmaSig_Weight); count++; }
   if(cfg.Ind_Adx_Enabled)        { output += StringFormat("  + ADX      (trend strength)  w=%d\n", cfg.Ind_Adx_Weight); count++; }
   if(cfg.Ind_Macd_Enabled)       { output += StringFormat("  + MACD     (momentum)        w=%d\n", cfg.Ind_Macd_Weight); count++; }
   if(cfg.Ind_Rsi_Enabled)        { output += StringFormat("  + RSI      (momentum zones)  w=%d\n", cfg.Ind_Rsi_Weight); count++; }
   if(cfg.Ind_Cci_Enabled)        { output += StringFormat("  + CCI      (cyclical)        w=%d\n", cfg.Ind_Cci_Weight); count++; }
   if(cfg.Ind_Mfi_Enabled)        { output += StringFormat("  + MFI      (money flow)      w=%d\n", cfg.Ind_Mfi_Weight); count++; }
   if(cfg.Ind_Sto_Enabled)        { output += StringFormat("  + Stoch    (oscillator)      w=%d\n", cfg.Ind_Sto_Weight); count++; }
   if(cfg.Ind_Bb_Enabled)         { output += StringFormat("  + BB       (volatility)      w=%d\n", cfg.Ind_Bb_Weight); count++; }
   if(cfg.Ind_Psar_Enabled)       { output += StringFormat("  + PSAR     (trend dir)       w=%d\n", cfg.Ind_Psar_Weight); count++; }
   if(cfg.Ind_P123_Enabled)       { output += StringFormat("  + P123     (123 pattern)     w=%d\n", cfg.Ind_P123_Weight); count++; }
   if(cfg.Ind_Ross_Enabled)       { output += StringFormat("  + Ross     (Ross hook)       w=%d\n", cfg.Ind_Ross_Weight); count++; }
   if(cfg.Ind_Atr_Enabled)        { output += StringFormat("  + ATR      (volatility rng)  w=%d\n", cfg.Ind_Atr_Weight); count++; }
   if(cfg.Ind_CandleBody_Enabled) { output += StringFormat("  + CBody    (body filter)     w=%d\n", cfg.Ind_CandleBody_Weight); count++; }
   if(cfg.Ind_CI_Enabled)         { output += StringFormat("  + CI       (ranging filter)  w=%d\n", cfg.Ind_CI_Weight); count++; }
   
   string mode_str = (cfg.VoteMode == VOTE_MODE_ALL ? "ALL" : "THRESHOLD");
   return StringFormat("Step 6 · Votes (%d enabled, mode=%s):\n%s", count, mode_str, output);
}

string SEA_UI_BuildDisabledVotesList(const ST_Settings &cfg)
{
   string list = "";
   if(!cfg.Ind_EmaSig_Enabled)     list += "EmaSig, ";
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
   if(cfg.Ind_Sto_Enabled) output += StringFormat("  Stoch: K=%d, D=%d, Slow=%d\n", cfg.P_StoK, cfg.P_StoD, cfg.P_StoSlow);
   if(cfg.Ind_Mfi_Enabled) output += StringFormat("  MFI: Period=%d\n", cfg.P_Mfi);
   if(cfg.Ind_Bb_Enabled)  output += StringFormat("  BB: Period=%d, Dev=%.1f\n", cfg.P_Bb, cfg.P_BbDev);
   return output;
}

//+------------------------------------------------------------------+
//| REFACTORED: Theme-Aware Vote Breakdown (Strategy Zone)           |
//+------------------------------------------------------------------+
string SEA_UI_BuildVoteBreakdown(const ST_Settings &cfg, const SVoteSnapshot &votes[], int count, color &out_line_clrs[]) 
{
   string grid = "";
   int cols = 3;
   int current_row = 0;

   for(int i = 0; i < count; i += cols) 
   {
      string line = "  ";
      color row_color = cfg.clr_Value; // Default to neutral value color
      bool any_pass = false;
      bool any_fail = false;

      for(int j = 0; j < cols; j++) 
      {
         if(i + j < count) 
         {
            // Determine Icon based on vote result
            string icon = "[.]"; 
            if(votes[i+j].vote_result == 1)  icon = "[+]";
            else if(votes[i+j].vote_result == -1) icon = "[-]";

            // Format the cell with standardized width
            line += StringFormat("%s %-12s ", icon, votes[i+j].name);
            if(j < cols - 1) line += "| ";

            // Logic for per-line color selection based on Vote Results
            if(votes[i+j].vote_result == 1) any_pass = true;
            if(votes[i+j].vote_result == -1) any_fail = true;
         }
      }

      // Final Color Assignment for the row
      if(any_fail)      row_color = cfg.clr_Fail;
      else if(any_pass) row_color = cfg.clr_Pass;
      else              row_color = cfg.clr_Disabled;

      // Add to output and track colors for the RenderPanel
      grid += line + "\n";
      
      // Expand color array to match lines
      int old_size = ArraySize(out_line_clrs);
      ArrayResize(out_line_clrs, old_size + 1);
      out_line_clrs[old_size] = row_color;
   }
   return grid;
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

//+------------------------------------------------------------------+
//| SETTINGS PANEL
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
   AddLine(StringFormat("Ver: %s | Symbol: %s %s", SEA_BUILD_STR, _Symbol, EnumToString(_Period)), v_clr, lines, line_clrs);
   AddLine(StringFormat("Preset: %-15s Mode: %s", EnumToString(InpPreset), (InpPreset == PRESET_CUSTOM ? "CUSTOM" : "LOCKED")), v_clr, lines, line_clrs);
   
   // --- ZONE 2: BIAS & STRUCTURE ---
   AddLine(" ", v_clr, lines, line_clrs); 
   AddLine("--- BIAS & STRUCTURE ---", h_clr, lines, line_clrs);
   AddLine(StringFormat("Strategy: %-15s Bias: %s", EnumToString(Settings.AutoStrat), EnumToString(Settings.BiasMode)), v_clr, lines, line_clrs);
   AddLine(StringFormat("EMAs: %-19s Ribbon: %d/%d/%d/%d", SEA_UI_BiasEmaLabel(Settings), Settings.P_Ema1, Settings.P_Ema2, Settings.P_Ema3, Settings.P_Ema4), v_clr, lines, line_clrs);
   AddLine(StringFormat("Gates: PB=%s | MultiLayer=%s", SEA_UI_OnOff(Settings.RequirePullback), SEA_UI_OnOff(Settings.Gate_UseMultiLayer)), v_clr, lines, line_clrs);
   
   // --- ZONE 3: ENVIRONMENT AUDIT ---
   AddLine(" ", v_clr, lines, line_clrs); 
   AddLine("--- ENVIRONMENT AUDIT ---", h_clr, lines, line_clrs);
   color phase_color;
   string phase_label = SEA_UI_FormatPhase(current_phase, phase_color); 
   AddLine(StringFormat("Phase: %-18s Allowed: %s", phase_label, SEA_UI_FormatAllowedLayers(current_phase, Settings.PhaseDetectionEnabled)), phase_color, lines, line_clrs);
   AddLine(StringFormat("Filter: Phase=%s | Layer=%s", (Settings.PhaseDetectionEnabled ? "ON" : "OFF"), (Settings.EnableLayerDetection ? "ON" : "OFF")), v_clr, lines, line_clrs);
   
   // --- ZONE 4: VOTE CONFIGURATION ---
   AddLine(" ", v_clr, lines, line_clrs);
   AddLine("--- VOTE CONFIGURATION ---", h_clr, lines, line_clrs);
   
   string vote_list = SEA_UI_BuildActiveVotesList(Settings); 
   string vote_lines[];
   int v_total = StringSplit(vote_list, '\n', vote_lines);
   for(int i=0; i<v_total; i++) {
      if(vote_lines[i] != "" && StringLen(vote_lines[i]) > 1) 
         AddLine(vote_lines[i], v_clr, lines, line_clrs);
   }
   
   // --- ZONE 5: RISK & PROTECTION ---
   AddLine(" ", v_clr, lines, line_clrs);
   AddLine("--- RISK & PROTECTION ---", h_clr, lines, line_clrs);
   AddLine(StringFormat("Sizer: %-18s SL Mode: %s", (Settings.UseMACompatSizer ? "MA_COMPAT" : "RISK_PCT"), EnumToString(Settings.SLMode)), v_clr, lines, line_clrs);
   AddLine(StringFormat("Risk: %.2f%% | RR: %.2f | BE: %s", Settings.RiskPercent, Settings.RRRatio, (Settings.BE_Mode != BE_MODE_OFF ? "ENABLED" : "OFF")), v_clr, lines, line_clrs);

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
      Inp_UI_LineSpacingPx, 
      Inp_UI_PanelFont,
      line_clrs 
   );
}

//+------------------------------------------------------------------+
//| COCKPIT PANEL
//+------------------------------------------------------------------+
void SEA_UI_UpdateCockpitPanel(
   const double atr, const int last_signal_dir, const int last_bias,
   const int last_votes, const int total_enabled, const string last_reason, const string ts_snap,
   const string te_snap, const SVoteSnapshot &vote_snaps[], const int vote_snap_count,
   const string diag_snap = "", EMarketPhase current_phase = PHASE_UNORDERED,
   EEntryLayer entry_layer = LAYER_NONE, bool filter_active = false,
   bool layer_allowed = false, const string pos_snap = ""
) {
   if(!Inp_UI_ShowCockpitPanel) { 
      SEA_UI_DestroyPanel(g_sea_ui_cockpit_name);
      return; 
   }

   string lines[]; color line_clrs[];
   ArrayResize(lines, 0); ArrayResize(line_clrs, 0);
   color v_clr = SEA_UI_ForeColor();   

   // --- ZONE 1: MARKET CONTEXT ---
   AddLine("--- MARKET CONTEXT ---", Settings.clr_Header, lines, line_clrs);
   AddLine(StringFormat("%-12s: %s (%s)", "Instrument", _Symbol, EnumToString(_Period)), Settings.clr_Value, lines, line_clrs);
   
   double spread = (SymbolInfoDouble(_Symbol, SYMBOL_ASK)-SymbolInfoDouble(_Symbol, SYMBOL_BID))/(_Point*SEA_UI_PipFactor());
   AddLine(StringFormat("%-12s: %.1f Pips", "Spread", spread), Settings.clr_Value, lines, line_clrs);

   // --- ZONE 2: STRATEGY LOGIC ---
   AddLine(" ", v_clr, lines, line_clrs); 
   AddLine("--- STRATEGY LOGIC ---", Settings.clr_Header, lines, line_clrs);

   // 1. Calculate how many indicators are currently GREEN [+] 
   // Using your specific parameter names: vote_snaps and vote_snap_count
   int active_votes = 0;
   for(int i = 0; i < vote_snap_count; i++)
   {
      // Check if the result is 1 (Pass/Green)
      if(vote_snaps[i].vote_result == 1) 
         active_votes++;
   }

   // 2. Format the string using your total_enabled parameter
   // This shows "1/5" based on the logic above
   string vote_str = StringFormat("%d/%d", active_votes, total_enabled);

   // 3. Print the Strategy Logic line
   AddLine(StringFormat("Signal: %-6s Bias: %-6s Votes: %s", 
           SEA_UI_SignalLabel(last_signal_dir), 
           SEA_UI_BiasLabel(last_bias), 
           vote_str), 
           Settings.clr_Value, lines, line_clrs);
        
   // Fixed Vote Grid Loop
   for(int i=0; i<vote_snap_count; i+=3) {
      string row = "  ";
      bool has_pass = false; bool has_fail = false;
      for(int j=0; j<3; j++) {
         if(i+j < vote_snap_count) {
            string icon = (vote_snaps[i+j].vote_result == 1 ? "[+]" : (vote_snaps[i+j].vote_result == -1 ? "[-]" : "[.]"));
            row += StringFormat("%s %-10s ", icon, vote_snaps[i+j].name);
            if(vote_snaps[i+j].vote_result == 1) has_pass = true;
            else if(vote_snaps[i+j].vote_result == -1) has_fail = true;
         }
      }
      color row_clr = has_fail ? Settings.clr_Fail : (has_pass ? Settings.clr_Pass : Settings.clr_Disabled);
      AddLine(row, row_clr, lines, line_clrs);
   }

   // --- ZONE 3: DIAGNOSTICS & SNAPSHOTS ---
   if(ts_snap != "") AddLine("TS: " + ts_snap, Settings.clr_Value, lines, line_clrs);
   if(te_snap != "") AddLine("TE: " + te_snap, Settings.clr_Value, lines, line_clrs);

   // --- ZONE 4: TRADE METRICS ---
   AddLine(" ", v_clr, lines, line_clrs); 
   AddLine("--- TRADE METRICS ---", Settings.clr_Header, lines, line_clrs);
   string r_p, rew_p, ratio, be; 
   SEA_UI_GetTradeMetrics(r_p, rew_p, ratio, be);
   AddLine(StringFormat("%-12s: %-8s Ratio: %s", "Risk(Pips)", r_p, ratio), Settings.clr_Value, lines, line_clrs);
   AddLine(StringFormat("%-12s: %-8s", "BE Trigger", be), Settings.clr_Value, lines, line_clrs);
   if(pos_snap != "") AddLine("POS: " + pos_snap, Settings.clr_Value, lines, line_clrs);

   // CRITICAL CLEANUP: Ensure we don't leave "Label" text
   string full_txt = "";
   for(int i=0; i<ArraySize(lines); i++) {
      if(lines[i] == "") lines[i] = " "; // Space prevents default "Label" text
      full_txt += lines[i] + "\n";
   }

   if(full_txt != g_sea_ui_last_cockpit_txt) {
      g_sea_ui_last_cockpit_txt = full_txt;
      SEA_UI_RenderPanel(g_sea_ui_cockpit_name, full_txt, Inp_UI_CockpitCorner, Inp_UI_CockpitX, Inp_UI_CockpitY, 
                         Inp_UI_CockpitFontSize, Inp_UI_CockpitLineSpacingPx, Inp_UI_CockpitFont, line_clrs);
   }
}

//+------------------------------------------------------------------+
//| THEME HELPER - Adds a line and its color to the tracking arrays  |
//+------------------------------------------------------------------+
void AddLine(string text, color clr, string &lines[], color &clrs[]) {
   int n = ArraySize(lines);
   ArrayResize(lines, n + 1);
   ArrayResize(clrs, n + 1);
   lines[n] = text;
   clrs[n] = clr;
}

//+------------------------------------------------------------------+
//| CHART INDICATOR MANAGEMENT                                       |
//+------------------------------------------------------------------+
void SEA_UI_ManageChartIndicators(CSignalEngine &engine)
{
   int win_total = (int)ChartGetInteger(0, CHART_WINDOWS_TOTAL);
   for(int w=win_total-1; w>=0; w--)
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
   Print("UI: Chart Indicator Manager - Rebuilding from Settings...");
   Print("  → Vote Mode: ", (Settings.VoteMode == VOTE_MODE_ALL ? "ALL (all enabled must pass)" : "THRESHOLD"));
   Print("═══════════════════════════════════════════════════════════");

   int overlays_added = 0;
   int ts_components_visible = 0;

   if(Settings.MABenchmarkStrict) {
      int h = Signal.GetPrimaryMAHandle();
      if(h != INVALID_HANDLE) {
         ChartIndicatorAdd(0, 0, h);
         overlays_added++;
         Print("  ✓ Benchmark MA (bias determination)");
      }
   }

   bool need_ema[4];
   need_ema[0] = (Settings.BiasFastID == 0 || Settings.BiasSlowID == 0 || Settings.Ind_EmaSig_Enabled);
   need_ema[1] = (Settings.BiasFastID == 1 || Settings.BiasSlowID == 1);
   need_ema[2] = (Settings.BiasFastID == 2 || Settings.BiasSlowID == 2);
   need_ema[3] = (Settings.BiasFastID == 3 || Settings.BiasSlowID == 3);
   for(int i=0; i<4; i++) {
      if(need_ema[i]) {
         int h = Signal.GetEmaHandle(i);
         if(h != INVALID_HANDLE) {
            ChartIndicatorAdd(0, 0, h);
            overlays_added++;
            string role = "bias";
            if(i == 0 && Settings.Ind_EmaSig_Enabled) {
               role = "bias + TS component";
               ts_components_visible++;
            }
            Print("  ✓ EMA", (i+1), " (", Settings.P_Ema1 + i*8, ") [", role, "]");
         }
      }
   }

   if(Settings.Ind_Psar_Enabled || Settings.TrailMode == TRAIL_PSAR) {
      int h = Signal.GetPsarHandle();
      if(h != INVALID_HANDLE) {
         ChartIndicatorAdd(0, 0, h);
         overlays_added++;
         string role = "";
         if(Settings.Ind_Psar_Enabled) { role = "TS component"; ts_components_visible++; }
         if(Settings.TrailMode == TRAIL_PSAR) { if(role != "") role += " + ";
         role += "trailing"; }
         Print("  ✓ PSAR [", role, "]");
      } else {
         Print("  ⚠ PSAR enabled but handle not available");
      }
   }

   if(Settings.Ind_Bb_Enabled) {
      int h = Signal.GetBbHandle();
      if(h != INVALID_HANDLE) {
         ChartIndicatorAdd(0, 0, h);
         overlays_added++;
         ts_components_visible++;
         Print("  ✓ Bollinger Bands (", Settings.P_Bb, ", ", Settings.P_BbDev, ") [TS component]");
      } else {
         Print("  ⚠ BB enabled but handle not available");
      }
   }

   if(Settings.UseHTF) {
      int h = Signal.GetHtfEmaHandle();
      if(h != INVALID_HANDLE) {
         ChartIndicatorAdd(0, 0, h);
         overlays_added++;
         Print("  ✓ HTF EMA (", EnumToString(Settings.HtfPeriod), "/", Settings.P_HtfEma, ") [filter gate]");
      } else {
         Print("  ⚠ HTF filter enabled but handle not available");
      }
   }

   if(Settings.TrailMode == TRAIL_FRACTAL) {
      int h = Signal.GetFractalHandle();
      if(h != INVALID_HANDLE) {
         ChartIndicatorAdd(0, 0, h);
         overlays_added++;
         Print("  ✓ Fractals [trailing]");
      } else {
         Print("  ⚠ Fractals needed but handle not available");
      }
   }

   if(Settings.Ind_P123_Enabled) {
      int h = Signal.GetP123Handle();
      if(h != INVALID_HANDLE) {
         ChartIndicatorAdd(0, 0, h);
         overlays_added++;
         ts_components_visible++;
         Print("  ✓ Pattern 123 [TS component]");
      } else {
         Print("  ⚠ Pattern 123 enabled but handle not available");
      }
   }

   if(Settings.Ind_Ross_Enabled) {
      int h = Signal.GetRossHandle();
      if(h != INVALID_HANDLE) {
         ChartIndicatorAdd(0, 0, h);
         overlays_added++;
         ts_components_visible++;
         Print("  ✓ Ross Hook [TS component]");
      } else {
         Print("  ⚠ Ross Hook enabled but handle not available");
      }
   }

   int subwindow = 1;
   int subwindows_added = 0;

   if(Settings.Ind_Macd_Enabled) {
      int h = Signal.GetMacdHandle();
      if(h != INVALID_HANDLE) {
         if(ChartIndicatorAdd(0, subwindow, h)) {
            Print("  ✓ MACD (", Settings.P_MacdFast, "/", Settings.P_MacdSlow, "/", Settings.P_MacdSig, ") [TS component, subwindow ", subwindow, "]");
            subwindow++; subwindows_added++; ts_components_visible++;
         }
      }
   }

   if(Settings.Ind_Rsi_Enabled) {
      int h = Signal.GetRsiHandle();
      if(h != INVALID_HANDLE) {
         if(ChartIndicatorAdd(0, subwindow, h)) {
            Print("  ✓ RSI (", Settings.P_Rsi, ") [TS component, subwindow ", subwindow, "]");
            subwindow++; subwindows_added++; ts_components_visible++;
         }
      }
   }

   if(Settings.Ind_Cci_Enabled) {
      int h = Signal.GetCciHandle();
      if(h != INVALID_HANDLE) {
         if(ChartIndicatorAdd(0, subwindow, h)) {
            Print("  ✓ CCI (", Settings.P_Cci, ") [TS component, subwindow ", subwindow, "]");
            subwindow++; subwindows_added++; ts_components_visible++;
         }
      }
   }

   if(Settings.Ind_Mfi_Enabled) {
      int h = Signal.GetMfiHandle();
      if(h != INVALID_HANDLE) {
         if(ChartIndicatorAdd(0, subwindow, h)) {
            Print("  ✓ MFI (", Settings.P_Mfi, ") [TS component, subwindow ", subwindow, "]");
            subwindow++; subwindows_added++; ts_components_visible++;
         }
      }
   }

   if(Settings.Ind_Sto_Enabled) {
      int h = Signal.GetStoHandle();
      if(h != INVALID_HANDLE) {
         if(ChartIndicatorAdd(0, subwindow, h)) {
            Print("  ✓ Stochastic (K:", Settings.P_StoK, " D:", Settings.P_StoD, " Slow:", Settings.P_StoSlow, ") [TS component, subwindow ", subwindow, "]");
            subwindow++; subwindows_added++; ts_components_visible++;
         }
      }
   }

   if(Settings.Ind_Adx_Enabled) {
      int h = Signal.GetAdxHandle();
      if(h != INVALID_HANDLE) {
         if(ChartIndicatorAdd(0, subwindow, h)) {
            Print("  ✓ ADX (", Settings.P_Adx, ") [TS component, subwindow ", subwindow, "]");
            subwindow++; subwindows_added++; ts_components_visible++;
         }
      }
   }

   if(Settings.Ind_Atr_Enabled) {
      int h = Signal.GetAtrHandle();
      if(h != INVALID_HANDLE) {
         if(ChartIndicatorAdd(0, subwindow, h)) {
            Print("  ✓ ATR (", Settings.P_Atr, ") [TS component, subwindow ", subwindow, "]");
            subwindow++; subwindows_added++; ts_components_visible++;
         }
      } else {
         Print("  ⚠ ATR enabled but handle not available");
      }
   }

   if(Settings.Ind_CI_Enabled) {
      int h = Signal.GetCiHandle();
      if(h != INVALID_HANDLE) {
         if(ChartIndicatorAdd(0, subwindow, h)) {
            Print("  ✓ CI (", Settings.CI_Period, ") [TS component, subwindow ", subwindow, "]");
            subwindow++; subwindows_added++; ts_components_visible++;
         }
      } else {
         Print("  ⚠ CI enabled but handle not available");
      }
   }

   if(Settings.Ind_VRC_Enabled) {
       Print("  ✓ VRC (Volatility Regime Classifier) [TS component, internal buffer only]");
       ts_components_visible++;
   }
   if(Settings.Ind_CandleBody_Enabled) {
       Print("  ✓ CandleBody (", Settings.CandleBody_AvgPeriod, ") [TS component, price-action only]");
       ts_components_visible++;
   }

   Print("───────────────────────────────────────────────────────────");
   Print("UI: Chart indicator management complete");
   Print("  → ", overlays_added, " overlays on main chart");
   Print("  → ", subwindows_added, " indicators in subwindows");
   Print("  → ", ts_components_visible, " TS components active");
   Print("  → Vote Mode: ", (Settings.VoteMode == VOTE_MODE_ALL ? "ALL" : "THRESHOLD"), " (", ts_components_visible, " indicators active)");
   Print("═══════════════════════════════════════════════════════════");
}