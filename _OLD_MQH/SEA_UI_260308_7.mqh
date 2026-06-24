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

// 260308_PR: Format EEntryLayer bitfield as short label.
// Handles multi-layer combinations (e.g. L1+L2, L2+L3, L1+L2+L3).
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

// 260308_PR: Check if a specific layer flag is active in an EEntryLayer bitfield.
bool SEA_UI_IsLayerActive(EEntryLayer bitfield, EEntryLayer layer)
{
   return ((int)bitfield & (int)layer) != 0;
}

// 260304_PR7: Format market phase as text with color coding
// TRENDING=LimeGreen, EMERGING=Gold, UNORDERED=OrangeRed, unknown=Gray
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

// 260304_PR7: Format allowed layers string based on current phase and filter state.
// Phase-layer filtering rules:
//   UNORDERED  → NONE            — Block ALL layers (L1, L2, L3)
//   EMERGING   → L1, L2          — Allow L1/L2 only; Block L3 (STRONG)
//   TRENDING   → L1, L2, L3      — Allow ALL layers (deep pullbacks valid in strong trend)
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

// 260304_PR7: Format phase-layer filter status with icon and color coding
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

   for(int i=0; i<70; i++)
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

   if(n > 70) n = 70;

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

   for(int i=n; i<70; i++)
   {
      string ln = panel_name + StringFormat("_L%02d", i);
      ObjectDelete(0, ln);
   }
}

// -----------------------------------
// Vote & Config Display Helpers
// -----------------------------------

// Returns a short label for the bias EMA pair used (e.g. "EMA3(34)/EMA4(89)")
string SEA_UI_BiasEmaLabel(const ST_Settings &cfg)
{
   int fast_period = (cfg.BiasFastID==0) ? cfg.P_Ema1 :
                     (cfg.BiasFastID==1) ? cfg.P_Ema2 :
                     (cfg.BiasFastID==2) ? cfg.P_Ema3 : cfg.P_Ema4;
   int slow_period = (cfg.BiasSlowID==0) ? cfg.P_Ema1 :
                     (cfg.BiasSlowID==1) ? cfg.P_Ema2 :
                     (cfg.BiasSlowID==2) ? cfg.P_Ema3 : cfg.P_Ema4;
   if(cfg.BiasFastID == cfg.BiasSlowID)
      return StringFormat("EMA%d(%d) slope", cfg.BiasFastID+1, fast_period);
   return StringFormat("EMA%d(%d)/EMA%d(%d)", cfg.BiasFastID+1, fast_period,
                                               cfg.BiasSlowID+1, slow_period);
}

string SEA_UI_BuildActiveVotesList(const ST_Settings &cfg)
{
   string output = "";
   int count = 0;
   if(cfg.Ind_EmaSig_Enabled) { output += StringFormat("  + EmaSig  (EMA1 price pos)  w=%d\n", cfg.Ind_EmaSig_Weight); count++; }
   if(cfg.Ind_Adx_Enabled)    { output += StringFormat("  + ADX     (trend strength)  w=%d\n", cfg.Ind_Adx_Weight);    count++; }
   if(cfg.Ind_Macd_Enabled)   { output += StringFormat("  + MACD    (momentum)        w=%d\n", cfg.Ind_Macd_Weight);   count++; }
   if(cfg.Ind_Rsi_Enabled)    { output += StringFormat("  + RSI     (momentum zones)  w=%d\n", cfg.Ind_Rsi_Weight);    count++; }
   if(cfg.Ind_Cci_Enabled)    { output += StringFormat("  + CCI     (cyclical)        w=%d\n", cfg.Ind_Cci_Weight);    count++; }
   if(cfg.Ind_Mfi_Enabled)    { output += StringFormat("  + MFI     (money flow)      w=%d\n", cfg.Ind_Mfi_Weight);    count++; }
   if(cfg.Ind_Sto_Enabled)    { output += StringFormat("  + Stoch   (oscillator)      w=%d\n", cfg.Ind_Sto_Weight);    count++; }
   if(cfg.Ind_Bb_Enabled)     { output += StringFormat("  + BB      (volatility)      w=%d\n", cfg.Ind_Bb_Weight);     count++; }
   if(cfg.Ind_Psar_Enabled)   { output += StringFormat("  + PSAR    (trend dir)       w=%d\n", cfg.Ind_Psar_Weight);   count++; }
   if(cfg.Ind_P123_Enabled)   { output += StringFormat("  + P123    (123 pattern)     w=%d\n", cfg.Ind_P123_Weight);   count++; }
   if(cfg.Ind_Ross_Enabled)   { output += StringFormat("  + Ross    (Ross hook)       w=%d\n", cfg.Ind_Ross_Weight);   count++; }
   string mode_str = (cfg.VoteMode == VOTE_MODE_ALL ? "ALL" : "THRESHOLD");
   return StringFormat("Step 6 · Votes (%d enabled, mode=%s):\n%s", count, mode_str, output);
}

string SEA_UI_BuildDisabledVotesList(const ST_Settings &cfg)
{
   string list = "";
   if(!cfg.Ind_EmaSig_Enabled) list += "EmaSig, ";
   if(!cfg.Ind_Adx_Enabled)    list += "ADX, ";
   if(!cfg.Ind_Macd_Enabled)   list += "MACD, ";
   if(!cfg.Ind_Rsi_Enabled)    list += "RSI, ";
   if(!cfg.Ind_Cci_Enabled)    list += "CCI, ";
   if(!cfg.Ind_Mfi_Enabled)    list += "MFI, ";
   if(!cfg.Ind_Sto_Enabled)    list += "Stoch, ";
   if(!cfg.Ind_Bb_Enabled)     list += "BB, ";
   if(!cfg.Ind_Psar_Enabled)   list += "PSAR, ";
   if(!cfg.Ind_P123_Enabled)   list += "P123, ";
   if(!cfg.Ind_Ross_Enabled)   list += "Ross, ";
   if(StringLen(list) > 2)
      list = StringSubstr(list, 0, StringLen(list) - 2);
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
      string psar_mode = cfg.Vote_AllowPsarFlip
         ? StringFormat("[FLIP mode: delay=%d bars]", cfg.Vote_PsarFlipDelay)
         : "[DOT mode]";
      output += StringFormat("  PSAR: Step=%.2f, Max=%.2f %s\n",
                             cfg.P_PsarStep, cfg.P_PsarMax, psar_mode);
   }
   if(cfg.Ind_Rsi_Enabled)
      output += StringFormat("  RSI: Period=%d, OB=%.0f, OS=%.0f\n",
                             cfg.P_Rsi, cfg.T_RsiOB, cfg.T_RsiOS);
   if(cfg.Ind_Cci_Enabled)
      output += StringFormat("  CCI: Period=%d\n", cfg.P_Cci);
   if(cfg.Ind_Adx_Enabled)
      output += StringFormat("  ADX: Period=%d, Threshold=%d\n",
                             cfg.P_Adx, cfg.T_Adx);
   if(cfg.Ind_Sto_Enabled)
      output += StringFormat("  Stoch: K=%d, D=%d, Slow=%d\n",
                             cfg.P_StoK, cfg.P_StoD, cfg.P_StoSlow);
   if(cfg.Ind_Mfi_Enabled)
      output += StringFormat("  MFI: Period=%d\n", cfg.P_Mfi);
   if(cfg.Ind_Bb_Enabled)
      output += StringFormat("  BB: Period=%d, Dev=%.1f\n",
                             cfg.P_Bb, cfg.P_BbDev);
   return output;
}

string SEA_UI_BuildVoteBreakdown(const SVoteSnapshot &votes[], const int voteCount, const int threshold = 0)
{
   if(voteCount <= 0) return "";
   int passingVotes = 0;
   string lines = "";
   for(int i = 0; i < voteCount; i++)
   {
      string icon = (votes[i].vote_result == 1) ? "+" : "-";
      lines += StringFormat("  %s %-7s %-5s %s\n",
                            icon,
                            votes[i].name + ":",
                            votes[i].state,
                            votes[i].reason);
      if(votes[i].vote_result == 1) passingVotes++;
   }
   return StringFormat("Vote Status: %d/%d\n", passingVotes, voteCount) + lines;
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
void SEA_UI_UpdateSettingsPanel(EMarketPhase current_phase = PHASE_UNORDERED)
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
   txt += "--- Step 1: Bias Calculation ---\n";
   txt += StringFormat("AutoStrat: %s%s  BiasMode: %s\n", EnumToString(Settings.AutoStrat), SEA_UI_AdmMark(), EnumToString(Settings.BiasMode));
   txt += StringFormat("BiasEnabled: %s  BiasEMAs: %s%s\n",
                       SEA_UI_OnOff(Settings.BiasEnabled),
                       SEA_UI_BiasEmaLabel(Settings), SEA_UI_AdmMark());
   txt += StringFormat("EMA ribbon: %d/%d/%d/%d%s\n",
                       Settings.P_Ema1, Settings.P_Ema2, Settings.P_Ema3, Settings.P_Ema4,
                       SEA_UI_AdmMark());

   // --- Step 5: Structure Gate
   txt += "--- Step 5: Structure Gate ---\n";
   txt += StringFormat("MultiLayer: %s  RequirePullback: %s\n",
                       SEA_UI_OnOff(Settings.Gate_UseMultiLayer),
                       SEA_UI_OnOff(Settings.RequirePullback));

   // --- Phase & Layer Status (260304_PR7)
   txt += "--- Phase & Layer Status ---\n";
   color phase_color;
   string phase_text = SEA_UI_FormatPhase(current_phase, phase_color);
   txt += StringFormat("Market Phase: %s\n", phase_text);
   txt += StringFormat("Bias Mode: %s\n", EnumToString(Settings.BiasMode));

   bool phase_filter_on = Settings.PhaseDetectionEnabled;
   bool layer_filter_on = Settings.EnableLayerDetection;
   txt += StringFormat("Phase Filter: %s\n", (phase_filter_on ? "ACTIVE" : "DISABLED"));
   txt += StringFormat("Layer Filter: %s\n", (layer_filter_on ? "ACTIVE" : "DISABLED"));

   bool both_filters = phase_filter_on && layer_filter_on;
   string allowed_layers = SEA_UI_FormatAllowedLayers(current_phase, both_filters);
   txt += StringFormat("Allowed Layers: %s\n", allowed_layers);

   // --- Active & Disabled Votes (Step 6)
   txt += SEA_UI_BuildActiveVotesList(Settings);
   txt += SEA_UI_BuildDisabledVotesList(Settings);
   txt += SEA_UI_BuildIndicatorConfigs(Settings);

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
   {
      trail_str += StringFormat("  %s", EnumToString(Settings.PSAR_TrailCushionMode));
      if(Settings.PSAR_TrailCushionMode == PSAR_CUSHION_ATR)
         trail_str += StringFormat("  CushionATR=%.2f", Settings.P_PsarTrailCushionATR);
      else
         trail_str += StringFormat("  CushionPips=%.1f  Delay=%d", Settings.PSAR_TrailPipsCushion, Settings.PSAR_TrailDelay);
   }
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
                                const string te_snap,
                                const SVoteSnapshot &vote_snaps[],
                                const int    vote_snap_count,
                                const string diag_snap = "",
                                EMarketPhase current_phase = PHASE_UNORDERED,
                                EEntryLayer  entry_layer   = LAYER_NONE,
                                bool         filter_active = false,
                                bool         layer_allowed = false)
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

   string sig_line = StringFormat("Signal=%s  Bias=%s", SEA_UI_SignalLabel(last_signal_dir), SEA_UI_BiasLabel(last_bias));
   if(Settings.VoteMode == VOTE_MODE_ALL)
      sig_line += StringFormat("  Votes=ALL(%d enabled)", last_votes);
   else
      sig_line += StringFormat("  Votes=%d", last_votes);

   if(last_signal_dir == 0 && last_reason != "")
      sig_line += StringFormat("  (%s)", last_reason);

   // Pipeline config line: bias EMAs and multi-layer
   string pipeline_line = StringFormat("BiasEMAs=%s  MultiLayer=%s",
                                       SEA_UI_BiasEmaLabel(Settings),
                                       SEA_UI_OnOff(Settings.Gate_UseMultiLayer));

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
   txt += gates_line    + "\n";
   txt += risk_line     + "\n";
   txt += pipeline_line + "\n";
   txt += sig_line      + "\n";

   // 260308_PR: Phase & Layer section (only shown when phase+layer filtering is active)
   if(filter_active)
   {
      txt += "--- Phase & Layer ---\n";
      color phase_color_dummy;
      txt += StringFormat("Phase: %s\n", SEA_UI_FormatPhase(current_phase, phase_color_dummy));
      string layer_str = SEA_UI_EntryLayerLabel(entry_layer);
      txt += StringFormat("Entry Layers: %s\n", layer_str);

      // Show individual layer status for multi-layer visibility
      if(entry_layer != LAYER_NONE)
      {
         if(SEA_UI_IsLayerActive(entry_layer, LAYER_1_WEAK))   txt += "  " + ShortToString(0x2713) + " L1 (EMA1" + ShortToString(0x2194) + "EMA2) Ribbon\n";
         if(SEA_UI_IsLayerActive(entry_layer, LAYER_2_MEDIUM)) txt += "  " + ShortToString(0x2713) + " L2 (EMA2" + ShortToString(0x2194) + "EMA3) Ghost\n";
         if(SEA_UI_IsLayerActive(entry_layer, LAYER_3_STRONG)) txt += "  " + ShortToString(0x2713) + " L3 (EMA3" + ShortToString(0x2194) + "EMA4) Shark\n";
      }

      color status_color_dummy;
      txt += StringFormat("Filter Status: %s\n", SEA_UI_FormatFilterStatus(layer_allowed, filter_active, status_color_dummy));
   }

   // Per-vote runtime breakdown
   if(vote_snap_count > 0)
      txt += SEA_UI_BuildVoteBreakdown(vote_snaps, vote_snap_count);

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

   // Pipeline diagnostics: EMA values, structure gate, statistics
   if(diag_snap != "")
   {
      txt += "--- Diagnostics ---\n";
      txt += diag_snap + "\n";
   }

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
