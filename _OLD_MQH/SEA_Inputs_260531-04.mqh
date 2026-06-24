//  SAVE AS UTF-16 LE WITH BOM
//+------------------------------------------------------------------+
//| SEA_Inputs.mqh — EA input parameter declarations                |
//| Included by: SimpleEA, SEA_Presets, SEA_TradeExecutor, SEA_UI   |
//| NOT included by: SEA_IND_SignalScan (keeps scanner dialog clean) |
//+------------------------------------------------------------------+
#include <RRMS\SEA_Config.mqh>


//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                 |
//+------------------------------------------------------------------+

input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "    🎯 PRESET";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input ulong     Inp_Global_MagicNum                = 12345;       // Magic number (trade identifier)
input EStrategyPreset Inp_Global_Preset            = PRESET_RRM_ORG;    // Strategy preset

input group " ";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "    🎯 TRADE MANAGEMENT";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "╔════════════════════════════════════════════════════════╗";
input group "║   💰 (RM) RISK MANAGEMENT (GLOBAL)";
input group "╚════════════════════════════════════════════════════════╝";
input int         Inp_RM_MaxOpenTrades             = 3;              // RM: Max concurrent trades (0 = unlimited)
input double      Inp_RM_RiskPercentDefault        = 2.0;            // RM: Default risk % per trade
input double      Inp_RM_MaxTotalRisk              = 6.0;            // RM: Max total active risk (%; 0 = unlimited)
input double      Inp_RM_RiskCapMultiple           = 1.5;            // RM: Hard per-trade risk cap (× target; clamps oversized lots, circuit breaker)
input double      Inp_RM_MarginUsageLimit          = 80.0;           // RM: Max % of free margin per trade (0 = use 100%)
input double      Inp_RM_MinMarginLevel            = 100.0;          // RM: Min margin level (%) required to allow new entries (0 = disabled)
input double      Inp_RM_EmergencyMarginLevel      = 80.0;           // RM: Emergency margin level (%) to force-close worst position (0 = disabled)
// input string   Inp_Step9_Ref1                   = "Risk per trade applies to all presets unless overridden by Admin Override";
// input string   Inp_Step9_Ref2                   = "To adjust exits under a strict preset: use PRESET_CUSTOM mode";
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 (RM) ADAPTIVE RISK & MARGIN (GLOBAL)";
input group "╚════════════════════════════════════════════════════════╝";
// ── TF-Based Adaptive Risk Scaling ────────────────────────────────
input bool        Inp_RM_UseAdaptiveRisk           = true;           // RM Adaptive: Enable TF-based risk scaling
input bool        Inp_RM_UseMarginAdjustment       = true;           // RM Adaptive: Enable instrument-aware margin adjustment
input double      Inp_RM_AdaptiveRisk_M1           = 1.0;            // RM Adaptive: risk % on M1
input double      Inp_RM_AdaptiveRisk_M5           = 1.5;            // RM Adaptive: risk % on M5
input double      Inp_RM_AdaptiveRisk_M15Plus      = 2.0;            // RM Adaptive: risk % on M15+

// ── Optional Cushion Overrides (0 = use auto TF/JPY calculation) ──
input double      Inp_RM_Override_SL_Cushion       = 0.0;            // RM Override: SL cushion pips (0=auto)
input double      Inp_RM_Override_Trail_Cushion    = 0.0;            // RM Override: Trail cushion pips (0=auto)
input double      Inp_RM_Override_BE_Cushion       = 0.0;            // RM Override: BE cushion pips (0=auto)

// ── Margin Level Instrument Adjustment ────────────────────────────
input double      Inp_RM_MarginAdj_Gold            = 0.8;            // RM Margin: Gold/Metals multiplier (0.8 = 80%)
input double      Inp_RM_MarginAdj_Crypto          = 0.7;            // RM Margin: Crypto multiplier (0.7 = 70%)
input double      Inp_RM_MarginAdj_Exotic          = 0.85;           // RM Margin: Exotic pairs multiplier (0.85 = 85%)
input double      Inp_RM_MarginAdj_JPY             = 0.9;            // RM Margin: JPY pairs multiplier (0.9 = 90%)

input group " ";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "║   🛡️ SAFETY GUARDS (GLOBAL) OFF by default";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
// These guards are preset-independent: they are NOT cleared by preset overrides,
// so they remain active under PRESET_RRM/FPM/etc. All default to 0 = disabled,
// so enabling none reproduces existing backtest behavior exactly.
input bool        Inp_Safety_CountBEInAggregateRisk = false;         // SAFETY: Count BE positions toward MaxTotalRisk (closes pyramiding gap)
input int         Inp_Safety_MaxPositionsPerDir    = 2;              // SAFETY: Max concurrent positions per direction (0=off)
input bool        Inp_Safety_DelayTrailUntilR      = false;          // SAFETY: Delay trailing until open profit reaches R-multiple
input double      Inp_Safety_TrailActivateR        = 0.0;            // SAFETY: R-multiple of profit before trailing engages (0=off)
input bool        Inp_Safety_RequirePriorAtBEToAdd = false;          // SAFETY: New trade only if all ar BE+ open same-symbol positions are at BE+ (staged risk)
input double      Inp_Safety_MaxEquityDrawdownPct  = 0.0;            // SAFETY: Pause new entries if peak→trough equity DD ≥ % (0=off)
input double      Inp_Safety_MinEquityFloor        = 0.0;            // SAFETY: Pause new entries if equity ≤ absolute value (0=off)
input double      Inp_Safety_MinRewardRiskRatio    = 0.0;            // SAFETY: Reject entries with TP:SL ratio below this (0=off)

input group " ";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "    🚫✅ VETO CONTROLS (GLOBAL)";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "╔════════════════════════════════════════════════════════╗";
input group "║   🚫 VETO: F FILTERS (SPREAD/TIME/NEWS)";
input group "╚════════════════════════════════════════════════════════╝";
input bool        Inp_VETO_UseSpread               = false;          // Veto Spread: enable
input int         Inp_VETO_MaxSpreadRetryBars      = 3;              // Veto Spread: retry bars (0=unlimited)
input double      Inp_VETO_MaxSpread               = 3.0;            // Veto Spread: max pips
input group "╔════════════════════════════════════════════════════════╗";
input group "║   🚫 VETO: TIME";
input group "╚════════════════════════════════════════════════════════╝";
input bool        Inp_VETO_UseTime                 = false;           // Veto Session: enable
input int         Inp_VETO_StartHr                 = 8;              // Veto Session: start hour (broker time)
input int         Inp_VETO_EndHr                   = 18;             // Veto Session: end hour (broker time)
input group "╔════════════════════════════════════════════════════════╗";
input group "║   🚫 VETO: NEWS";
input group "╚════════════════════════════════════════════════════════╝";
input bool        Inp_VETO_UseNews                 = false;          // Veto News: enable
input string      Inp_VETO_NewsFile                = "calendar_statement.csv"; // Veto News: CSV filename
input int         Inp_VETO_NewsPreMinutes          = 60;             // Veto News: block minutes before
input int         Inp_VETO_NewsPostMinutes         = 60;             // Veto News: block minutes after
input group "╔════════════════════════════════════════════════════════╗";
input group "║   🚫 VETO: TE QUALITY GATES (ADVANCED)";
input group "╚════════════════════════════════════════════════════════╝";
input bool        Inp_VETO_TE_RecheckBarClose      = false;          // Veto TE: re-check price drift vs Close[1]
input double      Inp_VETO_TE_BC_TolerancePips     = 3.0;            // Veto TE: drift tolerance pips
input int         Inp_VETO_TE_OpenDelaySeconds     = 0;              // Veto TE: open delay seconds (0=off)
input int         Inp_VETO_TE_SpreadMedianTicks    = 0;              // Veto TE: spread median filter ticks (0=off)
input group "╔════════════════════════════════════════════════════════╗";
input group "║   🚫 VETO: MTF (Multi-Timeframe Confirmation)";
input group "╚════════════════════════════════════════════════════════╝";
input bool        Inp_Ind_MTF_Enabled              = true;           // Veto MTF: enable
input ENUM_TIMEFRAMES Inp_MTF_TF1                  = PERIOD_M5;      // Veto MTF: TF1 (primary)
input ENUM_TIMEFRAMES Inp_MTF_TF2                  = PERIOD_M15;     // Veto MTF: TF2 (PERIOD_CURRENT = single TF)
input int         Inp_MTF_EMA_Fast                 = 20;             // Veto MTF: fast EMA period
input int         Inp_MTF_EMA_Slow                 = 50;             // Veto MTF: slow EMA period
input bool        Inp_MTF_RequirePhase             = true;           // Veto MTF: require trending phase
input bool        Inp_MTF_StrictAlignment          = true;           // Veto MTF: strict gate — all HTFs must agree
input group "╔════════════════════════════════════════════════════════╗";
input group "║   🚫 VETO: Climax";
input group "╚════════════════════════════════════════════════════════╝";
// ── CLIMAX / EXHAUSTION GUARD (global; blocks late entries into over-extended impulses) ──
input int         Inp_ClimaxGuard_Lookback         = 5;              // Climax: window (bars) scanned for an impulse
input int         Inp_ClimaxGuard_ATRPeriod        = 14;             // Climax: ATR baseline period (measured pre-impulse)
input double      Inp_ClimaxGuard_BarATRMult       = 2.0;            // Climax: single-bar range threshold (x ATR)
input double      Inp_ClimaxGuard_MoveATRMult      = 3.0;            // Climax: cumulative move threshold (x ATR)
input bool        Inp_ClimaxGuard_ResetPullback    = true;           // Climax: on detection reset ALL layer PB states

input group " ";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "    ✅✅ UI (GLOBAL)";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "╔════════════════════════════════════════════════════════╗";
input group "║   🎨 UI: ALL PANELS — SHARED SETTINGS";
input group "╚════════════════════════════════════════════════════════╝";
input int         Inp_UI_PanelFontSize             = 10;             // UI: Font size (all panels)
input int         Inp_UI_PanelLineSpacingPx        = 28;             // UI: Line spacing px (all panels)
input string      Inp_UI_PanelFont                 = "Arial";        // UI: Font name (all panels)
input group "╔════════════════════════════════════════════════════════╗";
input group "║   🎨 UI: COCKPIT PANEL";
input group "╚════════════════════════════════════════════════════════╝";
input bool        Inp_UI_ShowCockpitPanel          = true;           // UI CP: COCKPIT PANEL
input ENUM_BASE_CORNER  Inp_UI_CockpitCorner       = CORNER_LEFT_UPPER; // UI CP: corner
input int         Inp_UI_CockpitX                  = 30;             // UI CP: Cockpit panel X (px)
input int         Inp_UI_CockpitY                  = 30;             // UI CP: Cockpit panel Y (px)
input group "╔════════════════════════════════════════════════════════╗";
input group "║   🎨 UI: COCKPIT PANEL COLORS";
input group "╚════════════════════════════════════════════════════════╝";
input color       Inp_UI_clr_Header                = clrGold;        // UI CP: Header Text Color
input color       Inp_UI_clr_Value                 = clrWhite;       // UI CP: Market Data Color
input color       Inp_UI_clr_Pass                  = clrLimeGreen;   // UI CP: Logic PASS Color
input color       Inp_UI_clr_Fail                  = clrOrangeRed;   // UI CP: Logic FAIL Color
input color       Inp_UI_clr_Disabled              = clrGray;        // UI CP: Logic DISABLED Color
input group "╔════════════════════════════════════════════════════════╗";
input group "║   🎨 UI: STATUS PANEL";
input group "╚════════════════════════════════════════════════════════╝";
input bool        Inp_UI_ShowStatusPanel           = false;          // UI SP: STATUS PANEL
input ENUM_BASE_CORNER Inp_UI_PanelCorner          = CORNER_RIGHT_UPPER; // UI SP: Status panel corner
input bool        Inp_UI_ManageChartIndicators     = false;          // UI SP: Auto-add/remove chart indicators
input int         Inp_UI_PanelX                    = 30;             // UI SP: Status panel X (px)
input int         Inp_UI_PanelY                    = 30;             // UI SP: Status panel Y (px)
input group "╔════════════════════════════════════════════════════════╗";
input group "║   🎨 UI: VPRR PANEL";
input group "╚════════════════════════════════════════════════════════╝";
input bool        Inp_UI_ShowVPRRPanel             = false;          // UI VP: VPRR panel
input ENUM_BASE_CORNER Inp_UI_VPRRCorner           = CORNER_RIGHT_LOWER; // UI VP: VPRR panel corner
input int         Inp_UI_VPRR_X                    = 30;             // UI VP: VPRR panel X (px)
input int         Inp_UI_VPRR_Y                    = 30;             // UI VP: VPRR panel Y (px)
input bool        Inp_UI_ShowVPRRInitPanel         = true;           // UI VI: VPRR Init Check panel (startup validation; set false after verified)
input ENUM_BASE_CORNER Inp_UI_VPRRInitCorner       = CORNER_RIGHT_LOWER; // UI VI: VPRR Init Check panel corner
input int         Inp_UI_VPRRInit_X                = 30;             // UI VI: VPRR Init Check panel X (px)
input int         Inp_UI_VPRRInit_Y                = 30;             // UI VI: VPRR Init Check panel Y (px)
input group "╔════════════════════════════════════════════════════════╗";
input group "║   🎨 UI: SIGNAL MARKERS & COLORS";
input group "╚════════════════════════════════════════════════════════╝";
input EUIFrameMode Inp_UI_FrameMode                = UI_FRAME_NONE;  // UI SM: Panel frame mode
input bool        Inp_UI_DrawEntryLines            = true;           // UI SM: Draw entry marker lines
input bool        Inp_UI_DrawTradeLines            = true;           // UI SM: Draw trade management lines
input bool        Inp_UI_UseCustomColors           = true;           // UI SM: Use custom panel colors
input color       Inp_UI_FontColor                 = clrYellow;      // UI SM: font color
input int         Inp_UI_FramePadPx                = 6;              // UI SM: Panel padding (px)
input group "╔════════════════════════════════════════════════════════╗";
input group "║   🎨 (UI) VISUALISATION (Swing & Fractals)";
input group "╚════════════════════════════════════════════════════════╝";
input bool        Inp_CUSTOM_ShowSwingMarkers      = false;          // Custom: Show Swing
input bool        Inp_CUSTOM_ShowFractalMarkers    = true;           // Custom: Show Fractal
input bool        Inp_CUSTOM_ShowMarkerLabels      = false;          // Custom: Show Labels
input int         Inp_CUSTOM_MarkerLookback        = 55;             // Custom: Bars (0 = all history)
input color       Inp_CUSTOM_SwingHighColor        = clrCrimson;     // Custom: Swing High color
input color       Inp_CUSTOM_SwingLowColor         = clrDodgerBlue;  // Custom: Swing Low color
input int         Inp_CUSTOM_SwingMarkerSize       = 1;              // Custom: Swing Marker (1-5)
input color       Inp_CUSTOM_FractalHighColor      = clrOrange;      // Custom: Fractal High color
input color       Inp_CUSTOM_FractalLowColor       = clrGray;        // Custom: Fractal Low color
input int         Inp_CUSTOM_FractalMarkerSize     = 1;              // Custom: Fractal marker (1-5)

input group " ";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "    ✅✅ DEBUG (GLOBAL)";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "╔════════════════════════════════════════════════════════╗";
input group "║   🔍 DEBUG: DIAGNOSTICS";
input group "╚════════════════════════════════════════════════════════╝";
input EDebugLevel Inp_Debug_Level                  = DEBUG_SILENT;   // Debug: Level
input bool        Inp_Debug_Flow                   = true;           // Debug: Print OnInit/OnTick/OnDeinit flow ... have to be true with DEBUG_SIGNALS_ONLY
input bool        Inp_Debug_PrintEffectiveConfig   = true;           // Debug: Print effective config on init
input group "╔════════════════════════════════════════════════════════╗";
input group "║   🔍 DEBUG: DIAGNOSTICS: STATISTICS";
input group "╚════════════════════════════════════════════════════════╝";
input bool        Inp_Debug_Stats_TrackRejections  = true;           // Stats: Track rejection counts
input bool        Inp_Debug_Stats_TrackPasses      = true;           // Stats: Track pass counts
input bool        Inp_Debug_Stats_FullEvaluation   = true;           // Stats: Evaluate ALL indicators per bar
//input string    Inp_Stats_Info1                  = "FullEvaluation=false: waterfall (stop at first fail)";
//input string    Inp_Stats_Info2                  = "FullEvaluation=true: evaluate all, identify true bottlenecks";
input group "╔════════════════════════════════════════════════════════╗";
input group "║   🔬 DEBUG: TARGETED BAR EVALUATION";
input group "╚════════════════════════════════════════════════════════╝";
input EDebugLevel Inp_Debug_EvalMode               = DEBUG_SUMMARY;  // Debug Eval: level to apply
input datetime    Inp_Debug_EvalFrom               = 0;              // Debug Eval: from datetime (0=off)
input datetime    Inp_Debug_EvalTo                 = 0;              // Debug Eval: to datetime (0=off)
input datetime    Inp_Debug_EvalAt                 = 0;              // Debug Eval: pinpoint bar time (0=off)
input group "╔════════════════════════════════════════════════════════╗";
input group "║   🔍 DEBUG: REPORTING";
input group "╚════════════════════════════════════════════════════════╝";
input bool        Inp_Debug_ExportCSV              = false;          // Report: Export CSV reporting
input bool        Inp_Debug_ExportUseCommonFiles   = false;          // Report: Use terminal Common Files folder

#ifdef SEA_PRESET_MA
input group " ";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "    📐 PRESET: MA";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "╔════════════════════════════════════════════════════════╗";
input group "║   🛑 MT5 Moving Average Benchmark (PRESET_MA)";
input group "╚════════════════════════════════════════════════════════╝";
input int         Inp_MA_Period                    = 12;             // MA period
input int         Inp_MA_Shift                     = 6;              // MA shift
input double      Inp_MA_MaximumRiskPct            = 0.02;           // MA Max risk (%)
input double      Inp_MA_DecreaseFactor            = 3.0;            // MA Lot decrease factor
#endif // SEA_PRESET_MA

#ifdef SEA_PRESET_FPM
input group " ";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "    📐 PRESET: FPM";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 FPM: (TP) Take Profit Settings";
input group "╚════════════════════════════════════════════════════════╝";
input ETPMode     Inp_FPM_TPMode                   = TP_MODE_RR;     // FPM TP: TP mode — RR=derive from SL distance (recommended); FIXED_PIPS=TF cheat sheet pips
input double      Inp_FPM_RRRatio                  = 1.5;            // FPM TP: R:R ratio (used with TP_MODE_RR, e.g. 1.5, 2.0, 3.0)
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 FPM: (SL) Stop Loss Settings";
input group "╚════════════════════════════════════════════════════════╝";
input ESLMode     Inp_FPM_SLMode                   = SL_MODE_SWING;  // FPM SL: mode — SWING (recent high/low) or FIXED_PIPS
input int         Inp_FPM_SwingLookback            = 34;             // FPM SL: swing lookback bars (advisory; auto-scaled internally)
input double      Inp_FPM_SLFixedPips              = 15.0;           // FPM SL: fixed distance in pips (SL_MODE_FIXED_PIPS only)
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 FPM: (TS) Trailing Stop";
input group "╚════════════════════════════════════════════════════════╝";
input bool        Inp_FPM_UseTrailing              = true;           // FPM TS: Enable optional trailing stop
input double      Inp_FPM_TrailDistancePips        = 15.0;           // FPM TS: Trailing distance in pips (15 = cheat sheet default)
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 FPM: MACD Settings";
input group "╚════════════════════════════════════════════════════════╝";
input int         Inp_FPM_MacdFast                 = 12;             // FPM MACD: fast EMA period
input int         Inp_FPM_MacdSlow                 = 26;             // FPM MACD: slow EMA period
input int         Inp_FPM_MacdSig                  = 9;              // FPM MACD: signal period
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 FPM: PSAR Settings";
input group "╚════════════════════════════════════════════════════════╝";
input double      Inp_FPM_PsarStep                 = 0.02;           // FPM PSAR: step
input double      Inp_FPM_PsarMax                  = 0.2;            // FPM PSAR: max
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📊 FPM: SMA Convergence";
input group "╚════════════════════════════════════════════════════════╝";
input bool        Inp_FPM_Ind_SmaConverge_Enabled  = false;          // FPM SMA: Enable SMA convergence vote (FPM Condition 4)
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📊 FPM: MFI Volume Confirmation";
input group "╚════════════════════════════════════════════════════════╝";
input bool        Inp_FPM_Ind_Mfi_Enabled          = true;           // FPM MFI: Enable MFI volume gate (MFI>50 for longs, <50 for shorts)
input int         Inp_FPM_Mfi_Period               = 14;             // FPM MFI: period (default 14)
#endif // SEA_PRESET_FPM

#ifdef SEA_PRESET_RRM_FAMILY
input group " ";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "    📊 VPRR: Instruments + Shared Settings";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "╔════════════════════════════════════════════════════════╗";
input group "    📊 VPRR (used by RRM/RRM_ORG/TOPINVESTOR presets)";
input group "╚════════════════════════════════════════════════════════╝";
// Effective MinRatio = base x TF multiplier (auto-applied at EA start).
// Restart EA after instrument or TF change to auto-update settings.
input bool        Inp_VPRR_TF_ReduceRecBars        = true;           // VPRR TF: Reduce RecBars by 1 on H4+ and M5
input string      Inp_VPRR_ExternalSymbol          = "";             // VPRR EXTERNAL: proxy symbol for real volume ("GC" gold futures, "MGC" micro gold). Only used when VolumeType=VPRR_VOL_EXTERNAL. Symbol must be in Market Watch.

input double      Inp_VPRR_MinRatio_Gold           = 1.0;            // VPRR GOLD (XAU): MinRatio base (M15:1.0; TF mult auto-scales)
input int         Inp_VPRR_RecBars_Gold            = 3;              // VPRR Gold: RecoveryBars base

input double      Inp_VPRR_MinRatio_Silver         = 0.9;            // VPRR SILVER (XAG): MinRatio base (thinner market, 0.85-1.0)
input int         Inp_VPRR_RecBars_Silver          = 2;              // VPRR Silver: RecoveryBars base

input double      Inp_VPRR_MinRatio_IndicesUS      = 1.1;            // VPRR US INDices (NAS/US30/SPX): MinRatio base (1.1-1.3; NY session 14:30-21:00 UTC)
input int         Inp_VPRR_RecBars_IndicesUS       = 3;              // VPRR US Indices: RecoveryBars base

input double      Inp_VPRR_MinRatio_IndicesEU      = 1.0;            // VPRR EU INDices (DAX/FTSE): MinRatio base (1.0-1.2; Frankfurt/London 07:00-15:30 UTC)
input int         Inp_VPRR_RecBars_IndicesEU       = 3;              // VPRR EU Indices: RecoveryBars base

input double      Inp_VPRR_MinRatio_Oil            = 0.9;            // VPRR Oil (WTI/Brent): MinRatio base (0.9-1.0)
input int         Inp_VPRR_RecBars_Oil             = 3;              // VPRR Oil: RecoveryBars base

input double      Inp_VPRR_MinRatio_Crypto         = 0.7;            // VPRR CRYPTO (BTC/ETH): MinRatio base (0.7-0.8; retail-dominated)
input int         Inp_VPRR_RecBars_Crypto          = 2;              // VPRR Crypto: RecoveryBars base

input double      Inp_VPRR_MinRatio_Equities       = 1.0;            // VPRR EQUITIES (NVDA/AAPL etc.): MinRatio base (0.9-1.1)
input int         Inp_VPRR_RecBars_Equities        = 2;              // VPRR Equities: RecoveryBars base (fast institutional execution)

input double      Inp_VPRR_MinRatio_FX             = 0.7;            // VPRR FX: MinRatio base (0.6-0.7; tick vol approximation)
input int         Inp_VPRR_RecBars_FX              = 3;              // VPRR FX: RecoveryBars base
input double      Inp_VPRR_MinRatio_NonFXTick      = 0.8;            // VPRR non-FX tick fallback: MinRatio
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📊 VPRR TF Auto-Multiplier";
input group "╚════════════════════════════════════════════════════════╝";
// TF auto-multiplier: M5x0.85  M15x1.00  H1x0.95  H4+x0.90 (see chart comment for effective value)
input double      Inp_VPRR_TF_Mult_M5              = 0.85;           // VPRR TF: M5 multiplier (noisier, loosen 15%%)
input double      Inp_VPRR_TF_Mult_M15             = 1.00;           // VPRR TF: M15 multiplier (baseline)
input double      Inp_VPRR_TF_Mult_H1              = 0.95;           // VPRR TF: H1 multiplier (fewer bars, loosen slightly)
input double      Inp_VPRR_TF_Mult_H4Plus          = 0.90;           // VPRR TF: H4+ multiplier (very few cycles, loosen)
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📊 VPRR RRM - Volume Confirmation";
input group "╚════════════════════════════════════════════════════════╝";
input EVPRRVolumeType Inp_RRM_VPRR_VolumeType      = VPRR_VOL_AUTO;  // RRM VPRR: Volume source (Auto=real then tick fallback)
input bool        Inp_RRM_VPRR_AutoEnable          = true;           // RRM VPRR: Auto-enable VPRR based on instrument type (ON=auto; OFF=use manual toggle below)
input bool        Inp_RRM_VPRR_Enabled             = false;          // RRM VPRR: Manual enable (only used when AutoEnable=OFF)
input int         Inp_RRM_VPRR_RecoveryBars        = 5;              // RRM VPRR: Default recovery bars (1-10); per-instrument overrides in shared block below
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📊 VPRR RRM_ORG - Volume Confirmation";
input group "╚════════════════════════════════════════════════════════╝";
input EVPRRVolumeType Inp_RRM_ORG_VPRR_VolumeType  = VPRR_VOL_AUTO;  // RRM ORG VPRR: AUTO, EXTERNAL, REAL, TICK (Auto=real then tick fallback)
input bool        Inp_RRM_ORG_VPRR_AutoEnable      = true;           // RRM ORG VPRR: Auto-enable VPRR based on instrument type (ON=auto; OFF=use manual Enabled toggle below)
input bool        Inp_RRM_ORG_VPRR_Enabled         = false;          // RRM ORG VPRR: Manual enable (only used when AutoEnable=OFF)
input int         Inp_RRM_ORG_VPRR_RecoveryBars    = 5;              // RRM ORG VPRR: Default recovery bars (1-10); per-instrument overrides in shared block below

input group " ";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "    📐 PRESET: RRM";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 RRM: (TP) Take Profit - Risk Reward Ratio";
input group "╚════════════════════════════════════════════════════════╝";
input ETPMode     Inp_RRM_TPMode                   = TP_MODE_RR;     // RRM TP: mode
input double      Inp_RRM_RRRatio                  = 1.5;            // RRM TP: RRM R:R ratio (used with TP_MODE_RR)
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 RRM: (SL) Stop Loss";
input group "╚════════════════════════════════════════════════════════╝";
input ESLMode     Inp_RRM_SLMode                   = SL_MODE_SWING;  // RRM SL: SL_MODE_=*: *ATR, *FIXED_PIPS, *FRACTAL, *PERCENT, *PSAR_DOT, *SWING
input int         Inp_RRM_SwingLookback            = 34;             // RRM SL: RRM Swing lookback bars (used with SL_MODE_SWING)
input int         Inp_RRM_SL_AtrPeriod             = 14;             // RRM SL: ATR period (SL_MODE_ATR only)
input double      Inp_RRM_SL_AtrMult               = 1.0;            // RRM SL: ATR multiplier — SL = swing_anchor − ATR×N (SL_MODE_ATR only; 0.5–1.5 typical)
input int         Inp_RRM_MinBarsAfterClose        = 3;              // RRM SL: post-trade cooldown bars (0=off)
input int         Inp_RRM_ReEntryLotScalePct       = 50;             // RRM Re-entry: lot size % for re-entry after BE (0=full size; 50=half; since original is at BE total risk stays controlled)
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 RRM: (TS) Trailing Stop";
input group "╚════════════════════════════════════════════════════════╝";
input ETrailingMode Inp_RRM_TrailMode              = TRAIL_PSAR;     // RRM TS: MODE
input ETrailTrigger Inp_RRM_TrailTrigger           = TRIGGER_BREAKEVEN; // RRM TS: TRIGGER
input bool        Inp_RRM_TrailStartsAfterBE       = false;          // RRM TS: START after BE
input bool        Inp_RRM_TrailLockProfit          = true;           // RRM TS: NEVER move SL backwards
input bool        Inp_RRM_FreezeTrailOnFlip        = true;           // RRM TS: FREEZE on PSAR flip
input int         Inp_RRM_TrailPsarDotShift        = 1;              // RRM TS: PSAR DOT shift (1..3) (TRAIL_PSAR only)
input double      Inp_RRM_TrailStepPips            = 5.0;            // RRM TS: PIPS fixed-step
input int         Inp_RRM_MaxSpreadRetryBars       = 3;              // RRM: SPREAD bars retry (if TE block)
input bool        Inp_RRM_AllowReEntryAfterBE      = true;           // RRM: ALLOW re-entry after BE
// input string   Inp_PSAR_TrailCushion_Note       = "PSAR trail cushion auto-set by timeframe (M15=3, H1=7, H4=10 pips)"
// input string   Inp_RRM_Trail_Info               = "RRM trailing: PSAR-based with bar shift delay for flip stability";
input group "╔════════════════════════════════════════════════════════╗";
input group "║   🛑 RRM: (BE) Breakeven (% Progress)";
input group "╚════════════════════════════════════════════════════════╝";
input double      Inp_RRM_BE_ProgressPct           = 50.0;           // RRM BE: BE at % to TP
input double      Inp_RRM_BE_RMultiple             = 1.0;            // RRM BE: BE at R-multiple
// input string   Inp_RRM_BE_Buffer_Note           = "BE buffer auto-set by timeframe (M15=5, H1=10, H4=20 pips)";
// input string   Inp_RRM_BE_Example               = "Example: SL=10, TP=30 (3:1), BE@33% → triggers at +10 pips; SL locks at entry + TF-cushion";
input group "╔════════════════════════════════════════════════════════╗";
input group "║   🔧 RRM: (DP) Drawdown Protection";
input group "╚════════════════════════════════════════════════════════╝";
input bool        Inp_RRM_EnableDrawdownProtection = false;          // RRM DP: Enable drawdown protection
input int         Inp_RRM_MaxConsecutiveLosses     = 10;             // RRM DP: Max consecutive losses before pause
input int         Inp_RRM_MaxTradesPerDay          = 50;             // RRM DP: Max trades per day
input double      Inp_RRM_MaxDailyDrawdownPct      = 3.0;            // RRM DP: Max daily drawdown %
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 RRM: LAYER WMS Filter (sub-markets)";
input group "╚════════════════════════════════════════════════════════╝";
input bool        Inp_RRM_AllowWeak                = true;           // RRM Layer: Allow WEAK   trades (L1 EMA1/EMA2)
input bool        Inp_RRM_AllowMedium              = true;           // RRM Layer: Allow MEDIUM trades (L2 EMA2/EMA3)
input bool        Inp_RRM_AllowStrong              = true;           // RRM Layer: Allow STRONG trades (L3 EMA3/EMA4, TRENDING only)
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 RRM: LAYER WMS Pullback-Recovery Detection";
input group "╚════════════════════════════════════════════════════════╝";
// This Layer system is independent from legacy RRM gate fields below.
input bool        Inp_RRM_LayerPullbackEnabled     = true;           // RRM Layer PB: Layer PB: Enable pullback-recovery detection
input int         Inp_RRM_LayerBaselineLookback    = 10;             // RRM Layer PB: Layer PB: Baseline slope lookback (bars, recommended 3+)

input group " ";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "    📐 PRESET: RRM INDICATORS";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 RRM: Indicators — Enable/Disable";
input group "╚════════════════════════════════════════════════════════╝";
input bool        Inp_RRM_Use_Adx                  = false;          // RRM Ind: ADX vote enabled
input bool        Inp_RRM_Use_Bb                   = false;          // RRM Ind: BB vote enabled
input bool        Inp_RRM_Use_CandleBody           = true;           // RRM Ind: CBody vote enabled
input bool        Inp_RRM_Use_Cci                  = true;           // RRM Ind: CCI vote enabled
input bool        Inp_RRM_Use_CI                   = false;          // RRM Ind: CI vote enabled
input bool        Inp_RRM_Use_Macd                 = true;           // RRM Ind: MACD vote enabled
input bool        Inp_RRM_Use_Mfi                  = false;          // RRM Ind: MFI vote enabled
input bool        Inp_RRM_Use_Psar                 = true;           // RRM Ind: PSAR vote enabled
input bool        Inp_RRM_Use_Rsi                  = false;          // RRM Ind: RSI vote enabled
input bool        Inp_RRM_Use_Stoch                = false;          // RRM Ind: STO vote enabled
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 RRM: ADX Settings";
input group "╚════════════════════════════════════════════════════════╝";
input EADXMode    Inp_RRM_Adx_Mode                 = ADX_MODE_PHASE_AWARE; // RRM ADX: Mode
input int         Inp_RRM_AdxPeriod                = 14;             // RRM ADX: Period
input int         Inp_RRM_Adx_Lookback             = 100;            // RRM ADX: Lookback
input double      Inp_RRM_AdxThreshold             = 20.0;           // RRM ADX: Threshold
input double      Inp_RRM_Adx_Percentile           = 50.0;           // RRM ADX: Percentile
input double      Inp_RRM_Adx_Thr_Accum            = 12.0;           // RRM ADX: Thr Accumulation
input double      Inp_RRM_Adx_Thr_Trending         = 25.0;           // RRM ADX: Thr Trending
input double      Inp_RRM_Adx_Thr_Distrib          = 18.0;           // RRM ADX: Thr Distribution
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 RRM: ATR Settings";
input group "╚════════════════════════════════════════════════════════╝";
input int         Inp_RRM_P_Atr                    = 14;             // RRM ATR: ATR period
input double      Inp_RRM_ATR_VoteMinPips          = 5.0;            // RRM ATR: min pips to allow trade
input double      Inp_RRM_ATR_VoteMaxPips          = 50.0;           // RRM ATR: max pips to allow trade
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 RRM: BB Settings";
input group "╚════════════════════════════════════════════════════════╝";
input EBbMode     Inp_RRM_Bb_Mode                  = BB_TREND_FOLLOW; // RRM BB: Mode
input int         Inp_RRM_Bb_Period                = 20;             // RRM BB: Period
input double      Inp_RRM_Bb_Deviation             = 2.0;            // RRM BB: Deviation
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 RRM: CCI Settings";
input group "╚════════════════════════════════════════════════════════╝";
input ECciMode    Inp_RRM_CciMode                  = CCI_TREND_ZERO; // RRM CCI: Mode
input int         Inp_RRM_CciPeriod                = 14;             // RRM CCI: Period
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 RRM: Candle Body Settings";
input group "╚════════════════════════════════════════════════════════╝";
input bool        Inp_RRM_CandleBody_RequireDir    = true;           // RRM CBody: Require direction
input int         Inp_RRM_CandleBody_AvgPeriod     = 5;              // RRM CBody: Average period
input int         Inp_RRM_CandleBody_CheckBars     = 3;              // RRM CBody: Bars to check
input double      Inp_RRM_CandleBody_MaxMult       = 4;              // RRM CBody: Max multiplier
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 RRM: CI Settings";
input group "╚════════════════════════════════════════════════════════╝";
input int         Inp_RRM_CiPeriod                 = 14;             // RRM CI: Period
input double      Inp_RRM_CiRangingThreshold       = 61.8;           // RRM CI: Threshold
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 RRM: EMA Periods";
input group "╚════════════════════════════════════════════════════════╝";
input int         Inp_RRM_Ema1Period               = 5;              // RRM EMA: RRM EMA1 Period ( 5)
input int         Inp_RRM_Ema2Period               = 13;             // RRM EMA: RRM EMA2 Period (13)
input int         Inp_RRM_Ema3Period               = 34;             // RRM EMA: RRM EMA3 Period (34)
input int         Inp_RRM_Ema4Period               = 89;             // RRM EMA: RRM EMA4 Period (89)
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 RRM: EMA Fan Filter";
input group "╚════════════════════════════════════════════════════════╝";
input bool        Inp_RRM_EmaFanFilterEnabled      = false;          // RRM Fan: EMA FAN Filter
input double      Inp_RRM_EmaFanMaxTotalPips       = 0.0;            // RRM Fan: EMA1–EMA4 max gap pips (0=disabled; M1/M5 start: 25.0)
input double      Inp_RRM_EmaFanMaxPct             = 0.0;            // RRM Fan: EMA1–EMA4 max gap % of price (0=use pips; 0.36≈40pip EURUSD)
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 RRM: MACD Settings";
input group "╚════════════════════════════════════════════════════════╝";
input EMacdVoteMode Inp_RRM_MacdMode               = MACD_ZERO_AND_HIST; // RRM MACD: mode
input bool        Inp_RRM_MacdSlope                = false;          // RRM MACD: slope
input bool        Inp_RRM_MacdDiv                  = false;          // RRM MACD: div
input bool        Inp_RRM_MacdHistDecel            = true;           // RRM MACD: block when histogram shrinking bar-over-bar (decel pre-filter, analogous to DPI_BlockOnDeceleration)
input int         Inp_RRM_MacdFast                 = 12;             // RRM MACD: Fast (12)
input int         Inp_RRM_MacdSlow                 = 26;             // RRM MACD: Slow (26)
input int         Inp_RRM_MacdSig                  = 9;              // RRM MACD: Signal (9)
input int         Inp_RRM_MacdFreshBars            = 3;              // RRM MACD: max bars since zero-cross to be fresh
input double      Inp_RRM_MacdSlopeMin             = 0.00001;        // RRM MACD: minimum histogram slope
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 RRM: MFI Settings";
input group "╚════════════════════════════════════════════════════════╝";
input EMfiMode    Inp_RRM_Mfi_Mode                 = MFI_ZONE_FILTER; // RRM MFI: Mode
input int         Inp_RRM_Mfi_Period               = 14;             // RRM MFI: Period
input double      Inp_RRM_Mfi_OB                   = 80.0;           // RRM MFI: Overbought
input double      Inp_RRM_Mfi_OS                   = 20.0;           // RRM MFI: Oversold
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 RRM: PSAR Settings";
input group "╚════════════════════════════════════════════════════════╝";
input double      Inp_RRM_PsarStep                 = 0.05;           // RRM PSAR: Step
input double      Inp_RRM_PsarMax                  = 0.5;            // RRM PSAR: Max
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 RRM: RSI Settings";
input group "╚════════════════════════════════════════════════════════╝";
input ERsiMode    Inp_RRM_RsiMode                  = RSI_TREND_ABOVE_50; // RRM RSI: Mode
input int         Inp_RRM_RsiPeriod                = 14;             // RRM RSI: Period
input double      Inp_RRM_Rsi_OB                   = 70.0;           // RRM RSI: Overbought
input double      Inp_RRM_Rsi_OS                   = 30.0;           // RRM RSI: Oversold
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 RRM: Stochastic Settings";
input group "╚════════════════════════════════════════════════════════╝";
input EStochMode  Inp_RRM_Sto_Mode                 = STO_CROSS_SIGNAL; // RRM STO: Mode
input int         Inp_RRM_Sto_K                    = 5;              // RRM STO: K period
input int         Inp_RRM_Sto_D                    = 3;              // RRM STO: D period
input int         Inp_RRM_Sto_Slow                 = 3;              // RRM STO: Slowing period
input double      Inp_RRM_Sto_OB                   = 80.0;           // RRM STO: Overbought
input double      Inp_RRM_Sto_OS                   = 20.0;           // RRM STO: Oversold
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 RRM: VRC Settings";
input group "╚════════════════════════════════════════════════════════╝";
input int         Inp_RRM_VRC_ATR_Period           = 14;             // RRM VRC: ATR period for regime classification
input int         Inp_RRM_VRC_Lookback             = 100;            // RRM VRC: lookback bars
input double      Inp_RRM_VRC_LowThreshold         = 33.0;           // RRM VRC: low-volatility threshold
#endif // SEA_PRESET_RRM_FAMILY

#ifdef SEA_PRESET_RRM_ORG
input group " ";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "    📐 PRESET: RRM_ORG: DPI";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 RRM_ORG: DPI v31 — Core Math (shared by all)";
input group "╚════════════════════════════════════════════════════════╝";
input ENUM_APPLIED_PRICE Inp_RRM_ORG_DPI_CCI_Price       = PRICE_TYPICAL;  // RRM ORG DPI: CCI applied price
input int         Inp_RRM_ORG_DPI_MacdFast               = 8;        // RRM ORG DPI: MACD fast EMA period
input int         Inp_RRM_ORG_DPI_MacdSlow               = 13;       // RRM ORG DPI: MACD slow EMA period
input int         Inp_RRM_ORG_DPI_RedSignalType          = 3;        // RRM ORG DPI: Red line type (1=EMA_A 2=EMA_B 3=EMA_C 4=EMA_D 5=Double)
input int         Inp_RRM_ORG_DPI_RedEMA_A               = 5;        // RRM ORG DPI: Red EMA period A (type 1)
input int         Inp_RRM_ORG_DPI_RedEMA_B               = 8;        // RRM ORG DPI: Red EMA period B (type 2)
input int         Inp_RRM_ORG_DPI_RedEMA_C               = 13;       // RRM ORG DPI: Red EMA period C (type 3, default)
input int         Inp_RRM_ORG_DPI_RedEMA_D               = 21;       // RRM ORG DPI: Red EMA period D (type 4)
input int         Inp_RRM_ORG_DPI_DoubleSmoothFirst      = 5;        // RRM ORG DPI: Double-smooth first EMA
input int         Inp_RRM_ORG_DPI_DoubleSmoothSecond     = 8;        // RRM ORG DPI: Double-smooth second EMA
input int         Inp_RRM_ORG_DPI_CCI_Period             = 13;       // RRM ORG DPI: CCI period

input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 RRM_ORG: DPI Vote (I factor — ribbon direction)";
input group "╚════════════════════════════════════════════════════════╝";
input bool        Inp_RRM_ORG_DPI_Enabled                = true;     // RRM ORG DPI: Enable DPI vote in TS equation
input bool        Inp_RRM_ORG_DPI_UseCCIReset            = true;     // RRM ORG DPI: CCI can reset ribbon color (trend filter)
input bool        Inp_RRM_ORG_DPI_IgnoreCCIForVote       = false;    // RRM ORG DPI: Skip CCI check — vote on raw histogram direction only
input bool        Inp_RRM_ORG_DPI_AllowTransition        = true;     // RRM ORG DPI: Pass when hist rising toward zero (pullback exhaustion = bull signal)
input bool        Inp_RRM_ORG_DPI_UseGreenHist           = true;     // RRM ORG DPI: Also require GREEN overlay for vote pass
// Yellow ribbon = BUY vote, Red ribbon = SELL vote.
// CCI can reset ribbon color: hist>0 but CCI<0 → Red override (weakening).
//
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 RRM_ORG: DPI Pre-filter — GREEN Deceleration";
input group "╚════════════════════════════════════════════════════════╝";
input bool        Inp_RRM_ORG_DPI_Decel_Filter           = false;    // RRM ORG DPI: Block entry when GREEN shrinking or disappeared
input bool        Inp_RRM_ORG_DPI_BlockOnDeceleration    = false;    // RRM ORG DPI: Block entries when CCI momentum decelerating (needs tracking ON)
input int         Inp_RRM_ORG_DPI_HistDecelLookback      = 3;        // RRM ORG DPI: CCI deceleration lookback bars (needs tracking ON)
//
// Inp_RRM_ORG_DPI_Decel_Filter - Blocks entry when GREEN momentum is fading or has just disappeared.
// GREEN = Blue & hist both same side of zero (momentum confirmation).
// GREEN shrinking = trend exhaustion / OB-OS conditions.
// No GREEN on either bar = pass (ribbon-only setup, no momentum to decelerate).
//
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 RRM_ORG: DPI System B — CCI Histogram Tracking";
input group "╚════════════════════════════════════════════════════════╝";
input bool        Inp_RRM_ORG_DPI_HistTrackingEnabled    = false;    // RRM ORG DPI: Enable CCI histogram tracking (master switch)
input bool        Inp_RRM_ORG_DPI_Histogram_Growth_Boost = false;    // RRM ORG DPI: Use histogram growth as layer momentum boost (needs tracking ON)
input double      Inp_RRM_ORG_DPI_HistMomentumThreshold  = 0.0001;   // RRM ORG DPI: Ignore CCI-delta below this (needs tracking ON)
input bool        Inp_RRM_ORG_DPI_ExitOnHistDisappear    = false;    // RRM ORG DPI: Close trades when CCI trend flips (needs tracking ON)
input double      Inp_RRM_ORG_DPI_ExitThreshold          = 0.0;      // RRM ORG DPI: Exit when |CCI| below threshold, 0=disable (needs tracking ON)
//
// Inp_RRM_ORG_DPI_HistTrackingEnabled - 
// Separate deceleration system using CCI values (not ribbon/GREEN).
// Master switch: HistTrackingEnabled. When OFF, all settings below are inactive.
//
// Inp_RRM_ORG_DPI_Histogram_Growth_Boost - LAYER BOOST (needs tracking ON)
// When layer momentum check fails, GREEN/CCI growth can override.
// Requires HistTrackingEnabled = true to function.
//
// Inp_RRM_ORG_DPI_ExitOnHistDisappear - ENTRY EXIT GATES
// All require HistTrackingEnabled = true above.
//
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 RRM_ORG: DPI System C — CCI Reset-Recovery Gate";
input group "╚════════════════════════════════════════════════════════╝";
input bool        Inp_RRM_ORG_DPI_RequireResetRecovery   = true;     // RRM ORG DPI: Require CCI reset→recovery cycle before entry
input int         Inp_RRM_ORG_DPI_ResetRecoveryBars      = 0;        // RRM ORG DPI: Recovery bars after CCI flip-back (0=immediate)
input bool        Inp_RRM_ORG_DPI_ResetRequireGreen      = false;    // RRM ORG DPI: Also require GREEN reappearance during recovery
//
// Inp_RRM_ORG_DPI_RequireResetRecovery — CCI RESET-RECOVERY ENTRY GATE
// Requires HistTrackingEnabled = true and DPI_UseCCIReset = true.
//
// When enabled, the entry pipeline tracks the CCI reset lifecycle:
//   1. IDLE: Ribbon color correct for bias (CCI agrees with hist). Waiting for reset.
//   2. RESET_DETECTED: CCI flipped against hist → ribbon color changed (pullback).
//   3. RECOVERY_COUNTING: CCI flipped back → ribbon color recovered. Counting bars.
//   4. ENTRY_ALLOWED: Recovery held for N bars. Entry gate opens.
//
// This ensures entries only happen AFTER a proven pullback (CCI reset confirmed it)
// where the trend survived (CCI recovered). Higher reliability than entering
// during continuous GREEN — waits for the OB/OS reset cycle to complete.
//
// Inp_RRM_ORG_DPI_ResetRecoveryBars:
//   0 = entry allowed immediately when CCI recovers (flip-back bar)
//   1 = one bar of recovery required (confirms it's not a single-bar fake)
//   2+ = multiple bars (stricter, fewer trades, higher confidence)
//
// Inp_RRM_ORG_DPI_ResetRequireGreen:
//   When true, recovery also requires GREEN to reappear (Blue+hist aligned again).
//   Stricter: not just CCI agreeing, but full momentum alignment restored.
//

input group " ";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "    📐 PRESET: RRM_ORG";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 RRM_ORG: (TP) TAKE PROFIT TARGET";
input group "╚════════════════════════════════════════════════════════╝";
input ETPMode     Inp_RRM_ORG_TPMode               = TP_MODE_RR;     // RRM ORG TP: TP_MODE=*: *FIXED_PIPS, *FRACTAL, *NONE, *PSAR_FLIP, *RR
input double      Inp_RRM_ORG_RRRatio              = 2.5;            // RRM ORG TP: RR ratio
//
// Inp_RRM_ORG_TPMode - Take profit mode:
// TP_MODE_FIXED_PIPS: TP at fixed pip distance
// TP_MODE_RR:         TP derived from SL distance × RR ratio (recommended)
// TP_MODE_FRACTAL:    TP at next fractal level
// TP_MODE_PSAR_FLIP:  No fixed TP, exit on PSAR flip
// TP_MODE_NONE:       No TP target, rely on trailing stop only (LPR mode)
//
// Inp_RRM_ORG_RRRatio - Risk:Reward ratio: TP distance = SL distance × RR
// Example: RR=2.0 and SL=20 pips → TP=40 pips
// Only used when TPMode = TP_MODE_RR
//
// ⚠️ TP vs trailing interaction:
// TPMode != TP_MODE_NONE → TP stays fixed, trailing runs underneath.
// TPMode == TP_MODE_NONE → no TP cap, trailing manages full exit.
//
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 RRM_ORG: (SL) INITIAL STOP LOSS PLACEMENT";
input group "╚════════════════════════════════════════════════════════╝";
input ESLMode     Inp_RRM_ORG_SLMode               = SL_MODE_PSAR_DOT;  // RRM ORG SL: SL_MODE_=*: *ATR, *FIXED_PIPS, *FRACTAL, *PERCENT, *PSAR_DOT, *SWING
input int         Inp_RRM_ORG_SwingLookback        = 34;             // RRM ORG SL: SWING lookback bars
input int         Inp_RRM_ORG_SL_AtrPeriod         = 14;             // RRM ORG SL: ATR period (SL_MODE_ATR only)
input double      Inp_RRM_ORG_SL_AtrMult           = 1.0;            // RRM ORG SL: ATR multiplier — SL = swing_anchor − ATR×N (SL_MODE_ATR; 0.5–1.5 typical; Gold M15 use 1.0–1.5)
input int         Inp_RRM_ORG_MinBarsAfterClose    = 1;              // RRM ORG SL: post-trade cooldown bars (0=off)
input int         Inp_RRM_ORG_ReEntryLotScalePct   = 50;             // RRM ORG Re-entry: lot size % for re-entry after BE (0=full size; 50=half)
//
// Inp_RRM_ORG_SLMode - Initial SL placement method:
// SL_MODE_SWING:      SL at recent swing high/low (lookback bars)
// SL_MODE_ATR:        SL at swing anchor − ATR(period)×mult (industry standard; prevents under-sized SL on Gold/indices)
// SL_MODE_PSAR_DOT:   SL at current PSAR dot + cushion (keep for FX pairs)
// SL_MODE_FRACTAL:    SL at last fractal level
// SL_MODE_FIXED_PIPS: SL at fixed pip distance from entry
// SL_MODE_PERCENT:    SL at % distance from entry
//
// Inp_RRM_ORG_SwingLookback - Swing lookback: number of bars to scan for swing high/low.
// Larger value = wider SL (major swings), smaller value = tighter SL (minor swings).
// Typical guide: M5 21-34, M15 34-55, H1 55-89, H4 89-144.
// Only used when SLMode = SL_MODE_SWING.
//
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 RRM_ORG: (TSL) HOW TO TRAIL STOP LOSS";
input group "╚════════════════════════════════════════════════════════╝";
input ETrailingMode Inp_RRM_ORG_TrailMode             = TRAIL_EMA;   // RRM ORG TS: *BREAKEVEN, *EMA, *FIXED_PIPS, *FRACTAL, *NONE, *PROFIT_PERCENT, *PSAR, *PSAR_FLIP_EXIT
input EPsarTrailCushionMode Inp_RRM_ORG_PSAR_TrailCushionMode = PSAR_CUSHION_ATR; // RRM ORG TS: PSAR cushion mode (PIPS / ATR / PERCENT)
input int         Inp_RRM_ORG_TrailCushionAtrPeriod   = 14;          // RRM ORG TS: ATR period (ATR mode)
input double      Inp_RRM_ORG_TrailCushionAtrMult     = 1.0;         // RRM ORG TS: cushion ATR multiplier (cushion = ATR × this)
input double      Inp_RRM_ORG_TrailCushionPct         = 25.0;        // RRM ORG TS: cushion % of price (PERCENT mode + safety floor)
input double      Inp_RRM_ORG_TrailProfitPercentLPR   = 25.0;        // RRM ORG TS: LPR trailing percent behind peak
//
// Inp_RRM_ORG_TrailMode - Trailing method:
// TRAIL_NONE:            No trailing
// TRAIL_PSAR:            Follow PSAR dots with cushion (RRM default)
// TRAIL_FIXED_PIPS:      Fixed pip distance from current price
// TRAIL_PROFIT_PERCENT:  Let Profit Run (% behind peak profit)
// TRAIL_FRACTAL:         Trail with fractal levels
// TRAIL_PSAR_FLIP_EXIT:  Close position on PSAR flip
//
// Inp_RRM_ORG_PSAR_TrailCushionMode - PSAR trailing cushion mode:
// PSAR_CUSHION_PIPS    = fixed pips safety buffer
// PSAR_CUSHION_AUTO_TF = auto TF-aware cushion from preset helper
//
// Let Profit Run mode: SL trails X% behind the PEAK profit reached.
// Example: peak=80 pips, value=25 → SL target at +60 pips.
// Only used when TrailMode = TRAIL_PROFIT_PERCENT.
//
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 RRM_ORG: (TSL) ROLE_EMA* & TRIGGER";
input group "╚════════════════════════════════════════════════════════╝";
input EEmaRole    Inp_RRM_ORG_TrailEMA_RibbonRole     = ROLE_EMA3;   // RRM ORG TS: which ribbon EMA to trail (EMA1=5,EMA2=13,EMA3=34,EMA4=89) when Period=0
input int         Inp_RRM_ORG_TrailEMA_Period         = 0;           // RRM ORG TS: EMA period (0=use ribbon role selector below)
input int         Inp_RRM_ORG_TrailEMA_Shift          = 1;           // RRM ORG TS: bar shift for EMA read (1=last closed bar, 2=two bars back, 3=three bars back)
input double      Inp_RRM_ORG_TrailEMA_CushionPips    = 0.0;         // RRM ORG TS: EMA trail cushion pips (0=use ATR mode)
input double      Inp_RRM_ORG_TrailEMA_CushionAtrMult = 0.1;         // RRM ORG TS: EMA cushion = ATR×this (0=disabled; 0.1=recommended)
input int         Inp_RRM_ORG_TrailEMA_CushionAtrPeriod = 14;        // RRM ORG TS: ATR period for EMA cushion
input ETrailTrigger Inp_RRM_ORG_TrailTrigger          = TRIGGER_IMMEDIATE; // RRM ORG TS: *BREAKEVEN, *IMMEDIATE, *PROFIT_PERCENT, *PROFIT_PIPS, *PSAR_ALIGN
input bool        Inp_RRM_ORG_TrailStartsAfterBE      = true;       // RRM ORG TS: Safety override: trail after BE
input bool        Inp_RRM_ORG_TrailLockProfit         = true;        // RRM ORG TS: never move SL backwards (lock profit)
input double      Inp_RRM_ORG_TrailStepPips           = 5.0;         // RRM ORG TS: step size for fixed-step trail modes
input int         Inp_RRM_ORG_MaxSpreadRetryBars      = 3;           // RRM ORG: SPREAD bars retry (if TE block)
input bool        Inp_RRM_ORG_AllowReEntryAfterBE     = true;        // RRM ORG: ALLOW re-entry after BE
//
// Inp_RRM_ORG_TrailStartsAfterBE- Trailing activation logic in PRESET_RRM_ORG:
// TrailTrigger is preset-managed (TRIGGER_BREAKEVEN by default).
// Trail starts after BE lock unless safety override below is disabled.
//
// If custom profiles use TRIGGER_IMMEDIATE, keep BE protection in mind.
// Force trailing to wait for BE lock before any trailing movement.
// Recommended true for protection against trailing in loss zone.
// In PRESET_RRM_ORG, TrailTrigger is internally set to TRIGGER_BREAKEVEN.
//
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 RRM_ORG: (BE) BREAKEVEN";
input group "╚════════════════════════════════════════════════════════╝";
input EBeMode     Inp_RRM_ORG_BE_Mode                 = BE_MODE_TP_PROGRESS_PCT;  // RRM ORG BE: Breakeven trigger mode
input double      Inp_RRM_ORG_BE_RMultiple            = 1.0;         // RRM ORG BE: BE trigger as R multiple
input double      Inp_RRM_ORG_BE_ProgressPct          = 25.0;        // RRM ORG BE: BE trigger as TP progress %
//
// Inp_RRM_ORG_BE_Mode - Breakeven trigger mode:
// BE_MODE_OFF:             Breakeven disabled
// BE_MODE_TP_PROGRESS_PCT: Move SL to BE when profit reaches X% toward TP
// BE_MODE_R_MULTIPLE:      Move SL to BE when profit reaches X× risk (R-multiple)
//
// Inp_RRM_ORG_BE_RMultiple - BE trigger in R-multiples.
// Example: 1.0 = BE at 1R (profit equals initial risk distance).
// Only used when BE_Mode = BE_MODE_R_MULTIPLE.
//
// BE trigger as percent progress toward TP.
// Example: 33 = move to BE at one-third of the path to TP.
// Only used when BE_Mode = BE_MODE_TP_PROGRESS_PCT.
//
// Inp_RRM_ORG_BE_ProgressPct - 
// ⚠️ BE lock is one-time: once triggered, SL moves to entry+buffer and does not recalculate.
// Buffer pips are TF-adaptive in PRESET_RRM_ORG via GetTFBasedCushion().
//
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 RRM_ORG: (DD) Drawdown Protection";
input group "╚════════════════════════════════════════════════════════╝";
input bool        Inp_RRM_ORG_ForceDDProtection    = false;          // RRM ORG DD: Force DrawDown protection
input int         Inp_RRM_ORG_DDMaxConsecLosses    = 3;              // RRM ORG DD: Override max consecutive losses (0=use Inp_RRM_*)
input int         Inp_RRM_ORG_DDMaxTradesPerDay    = 15;             // RRM ORG DD: Override max trades per day (0=use Inp_RRM_*)
input double      Inp_RRM_ORG_DDMaxDailyPct        = 8.0;            // RRM ORG DD: Override max daily DD % (0=use Inp_RRM_*)

input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 RRM_ORG: QUALITY Gates";
input group "╚════════════════════════════════════════════════════════╝";
input bool        Inp_RRM_ORG_RequireRecoveryIntraday = true;        // RRM ORG QA: Require recovery <M15
input bool        Inp_RRM_ORG_HtfFilter            = true;           // RRM ORG QA: HTF Trend Filter
input bool        Inp_RRM_ORG_ClimaxGuard_Enabled  = true;           // RRM ORG: enable climax/exhaustion guard
input int         Inp_RRM_ORG_Ema1Period           = 5;              // RRM ORG QA: EMA1 period
input int         Inp_RRM_ORG_Ema2Period           = 13;             // RRM ORG QA: EMA2 period
input int         Inp_RRM_ORG_Ema3Period           = 34;             // RRM ORG QA: EMA3 period
input int         Inp_RRM_ORG_Ema4Period           = 89;             // RRM ORG QA: EMA4 period
input int         Inp_RRM_ORG_PhaseConfirmM5       = 0;              // RRM ORG QA: PhaseConfirmBars <M5
input int         Inp_RRM_ORG_PhaseConfirmM30      = 0;              // RRM ORG QA: PhaseConfirmBars <M30
input int         Inp_RRM_ORG_PhaseConfirmH1plus   = 0;              // RRM ORG QA: PhaseConfirmBars H1+
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 RRM_ORG: LAYER WMS Pullback & Recovery";
input group "╚════════════════════════════════════════════════════════╝";
input bool        Inp_RRM_ORG_LayerPBEnabled       = true;           // RRM ORG PB: Enable pullback-recovery state machine (P2?)
input int         Inp_RRM_ORG_LayerPBLookback      = 21;              // RRM ORG PB: Global baseline lookback (fallback; per-layer below)
input int         Inp_RRM_ORG_LayerPBLookback_W    = SEA_DEF_LAYER_LB_W;            // RRM ORG PB: LayerW baseline lookback (fast/responsive)
input int         Inp_RRM_ORG_LayerPBLookback_M    = SEA_DEF_LAYER_LB_M;            // RRM ORG PB: LayerM baseline lookback (medium)
input int         Inp_RRM_ORG_LayerPBLookback_S    = SEA_DEF_LAYER_LB_S;            // RRM ORG PB: LayerS baseline lookback (slow/stable)
input double      Inp_RRM_ORG_LayerPBPullbackRatio = SEA_DEF_LAYER_PULLBACK_RATIO;  // RRM ORG PB: Pullback threshold (|ratio|<this = weakened)
input double      Inp_RRM_ORG_LayerPBRecoveryRatio = SEA_DEF_LAYER_RECOVERY_RATIO;  // RRM ORG PB: Global recovery threshold (fallback)
input double      Inp_RRM_ORG_LayerPBFlatRatio     = SEA_DEF_LAYER_FLAT_RATIO;      // RRM ORG PB: Flat threshold (|ratio|<this = flat)
input bool        Inp_RRM_ORG_LayerPBAllowReversal = SEA_DEF_LAYER_ALLOW_REVERSAL;  // RRM ORG PB: Count slope reversal as pullback
input double      Inp_RRM_ORG_RecoveryRatio_W      = SEA_DEF_LAYER_RECOVERY_W;      // RRM ORG PB: LayerW recovery override (-1=use global)
input double      Inp_RRM_ORG_RecoveryRatio_M      = SEA_DEF_LAYER_RECOVERY_M;      // RRM ORG PB: LayerM recovery override (-1=use global)
input double      Inp_RRM_ORG_RecoveryRatio_S      = SEA_DEF_LAYER_RECOVERY_S;      // RRM ORG PB: LayerS recovery override (-1=use global)
input bool        Inp_RRM_ORG_AllowLayerS          = true;                          // RRM ORG PB: allow Layer S (EMA3/4) entries
input bool        Inp_RRM_ORG_AllowLayerM          = true;                          // RRM ORG PB: allow Layer M (EMA2/3) entries
input bool        Inp_RRM_ORG_AllowLayerW          = true;                          // RRM ORG PB: allow Layer W (EMA1/2) entries
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 RRM_ORG: EMA Fan Filter (pips)";
input group "╚════════════════════════════════════════════════════════╝";
input bool        Inp_RRM_ORG_EmaFanFilter         = false;           // RRM ORG Fan: EMA Fan Filter
input double      Inp_RRM_ORG_EmaFan_M5Pips        = 25.0;           // RRM ORG Fan: pips <M5
input double      Inp_RRM_ORG_EmaFan_M30Pips       = 40.0;           // RRM ORG Fan: pips <M30
input double      Inp_RRM_ORG_EmaFan_H1Pips        = 60.0;           // RRM ORG Fan: pips H1
input double      Inp_RRM_ORG_EmaFan_H4Pips        = 100.0;          // RRM ORG Fan: pips H4
input double      Inp_RRM_ORG_EmaFan_DailyPips     = 180.0;          // RRM ORG Fan: pips D1+
input double      Inp_RRM_ORG_EmaFan_MaxPct        = 0.0;            // RRM ORG Fan: max gap % of price (>0 overrides pips; universal for all instruments)
input double      Inp_RRM_ORG_JpyGateMultiplier    = 1.3;            // RRM ORG Fan: JPY Gate Multiplier (1.0=disabled)

input group " ";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "    📐 PRESET: RRM_ORG: INDICATORS";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 RRM_ORG: Indicators — Use";
input group "╚════════════════════════════════════════════════════════╝";
input bool        Inp_RRM_ORG_Use_Adx              = false;          // RRM ORG Ind: ADX vote
input bool        Inp_RRM_ORG_Use_Atr              = false;          // RRM ORG Ind: ATR vote
input bool        Inp_RRM_ORG_Use_Bb               = false;          // RRM ORG Ind: BB vote
input bool        Inp_RRM_ORG_Use_CandleBody       = true;           // RRM ORG Ind: CBody vote true
input bool        Inp_RRM_ORG_Use_Cci              = false;          // RRM ORG Ind: CCI vote
input bool        Inp_RRM_ORG_Use_CI               = false;          // RRM ORG Ind: CI vote
input bool        Inp_RRM_ORG_Use_Macd             = false;          // RRM ORG Ind: MACD vote
input bool        Inp_RRM_ORG_Use_Mfi              = false;          // RRM ORG Ind: MFI vote
input bool        Inp_RRM_ORG_Use_P123             = false;          // RRM ORG Ind: P123
input bool        Inp_RRM_ORG_Use_Psar             = true;           // RRM ORG Ind: PSAR vote true
input bool        Inp_RRM_ORG_Use_Ross             = false;          // RRM ORG Ind: Ross vote
input bool        Inp_RRM_ORG_Use_Rsi              = false;          // RRM ORG Ind: RSI vote
input bool        Inp_RRM_ORG_Use_Stoch            = false;          // RRM ORG Ind: STO vote
input bool        Inp_RRM_ORG_Use_VRC              = false;          // RRM ORG Ind: VRC vote
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 RRM_ORG: ADX Settings";
input group "╚════════════════════════════════════════════════════════╝";
input EADXMode    Inp_RRM_ORG_Adx_Mode             = ADX_MODE_STATIC;  // RRM ORG ADX: ADX Mode
input int         Inp_RRM_ORG_AdxPeriod            = 14;             // RRM ORG ADX: ADX Period
input int         Inp_RRM_ORG_Adx_Lookback         = 100;            // RRM ORG ADX: ADX Lookback bars
input double      Inp_RRM_ORG_AdxThreshold         = 20.0;           // RRM ORG ADX: ADX Threshold
input double      Inp_RRM_ORG_Adx_Percentile       = 50.0;           // RRM ORG ADX: ADX Percentile
input double      Inp_RRM_ORG_Adx_Thr_Accum        = 12.0;           // RRM ORG ADX: ADX Thr Accumulation
input double      Inp_RRM_ORG_Adx_Thr_Trending     = 25.0;           // RRM ORG ADX: ADX Thr Trending
input double      Inp_RRM_ORG_Adx_Thr_Distrib      = 18.0;           // RRM ORG ADX: ADX Tht Distribution
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 RRM_ORG: ATR Settings";
input group "╚════════════════════════════════════════════════════════╝";
input int         Inp_RRM_ORG_P_Atr                = 14;             // RRM ORG ATR: ATR period (used when ATR voter enabled)
input double      Inp_RRM_ORG_ATR_VoteMinPips      = 5.0;            // RRM ORG ATR: min ATR pips to allow trade
input double      Inp_RRM_ORG_ATR_VoteMaxPips      = 50.0;           // RRM ORG ATR: max ATR pips to allow trade
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 RRM_ORG: BB Settings";
input group "╚════════════════════════════════════════════════════════╝";
input EBbMode     Inp_RRM_ORG_Bb_Mode              = BB_TREND_FOLLOW;   // RRM ORG BB: BB Mode
input int         Inp_RRM_ORG_Bb_Period            = 20;             // RRM ORG BB: BB Period
input double      Inp_RRM_ORG_Bb_Deviation         = 2.0;            // RRM ORG BB: BB Deviation
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 RRM_ORG: CB Candle Body Settings";
input group "╚════════════════════════════════════════════════════════╝";
input bool        Inp_RRM_ORG_CandleBody_RequireDir   = true;        // RRM ORG CBody: CBody Require direction
input int         Inp_RRM_ORG_CandleBody_AvgPeriod    = 5;           // RRM ORG CBody: CBody Average period
input int         Inp_RRM_ORG_CandleBody_CheckBars    = 3;           // RRM ORG CBody: CBody Bars to check
input double      Inp_RRM_ORG_CandleBody_MaxMult      = 4.0;         // RRM ORG CBody: CBody Max multiplier
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 RRM_ORG: CC Candle Close Settings";
input group "╚════════════════════════════════════════════════════════╝";
input bool        Inp_RRM_ORG_BarClose_Require_Progressive_Momentum = false; // RRM ORG CC: Momentum
input int         Inp_RRM_ORG_BarClose_LookbackBars   = 3;           // RRM ORG CC: Lookback (1-4 bars)
input double      Inp_RRM_ORG_BarClose_PipTolerance   = 0.0;         // RRM ORG CC: Allow N pips of target EMA (0=strict close>EMA)
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 RRM_ORG: CCI Settings";
input group "╚════════════════════════════════════════════════════════╝";
input ECciMode    Inp_RRM_ORG_CciMode              = CCI_TREND_ZERO; // RRM ORG CCI: CCI Mode
input int         Inp_RRM_ORG_CciPeriod            = 14;             // RRM ORG CCI: CCI Period
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 RRM_ORG: CI Settings";
input group "╚════════════════════════════════════════════════════════╝";
input int         Inp_RRM_ORG_CiPeriod             = 14;             // RRM ORG CI: CI Period
input double      Inp_RRM_ORG_CiRangingThreshold   = 61.8;           // RRM ORG CI: CI Threshold
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 RRM_ORG: MACD Settings";
input group "╚════════════════════════════════════════════════════════╝";
input EMacdVoteMode Inp_RRM_ORG_MacdMode           = MACD_HISTOGRAM; // RRM ORG MACD: MACD Mode
input bool        Inp_RRM_ORG_MacdSlope            = false;          // RRM ORG MACD: MACD require SLO
input bool        Inp_RRM_ORG_MacdDiv              = false;          // RRM ORG MACD: MACD require DIV
input int         Inp_RRM_ORG_MacdFast             = 8;              // RRM ORG MACD: MACD Fast
input int         Inp_RRM_ORG_MacdSlow             = 13;             // RRM ORG MACD: MACD Slow
input int         Inp_RRM_ORG_MacdSig              = 5;              // RRM ORG MACD: MACD Signal
input int         Inp_RRM_ORG_MacdFreshBars        = 3;              // RRM ORG MACD: max bars since last zero-cross to be "fresh"
input double      Inp_RRM_ORG_MacdSlopeMin         = 0.00001;        // RRM ORG MACD: minimum histogram slope magnitude
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 RRM_ORG: MFI Settings";
input group "╚════════════════════════════════════════════════════════╝";
input EMfiMode    Inp_RRM_ORG_Mfi_Mode             = MFI_ZONE_FILTER; // RRM ORG MFI: MFI Mode
input int         Inp_RRM_ORG_Mfi_Period           = 14;             // RRM ORG MFI: MFI Period
input double      Inp_RRM_ORG_Mfi_OB               = 80.0;           // RRM ORG MFI: MFI Overbought
input double      Inp_RRM_ORG_Mfi_OS               = 20.0;           // RRM ORG MFI: MFI Oversold
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 RRM_ORG: PSAR Settings";
input group "╚════════════════════════════════════════════════════════╝";
input bool        Inp_RRM_ORG_Vote_AllowPsarFlip   = true;           // RRM ORG PSAR: PSAR Enable Flip
input int         Inp_RRM_ORG_Vote_PsarFlipDelay   = 5;              // RRM ORG PSAR: PSAR Flip delay (-1=persistent, 0-10=bars after flip)
input int         Inp_RRM_ORG_TrailPsarDotShift    = 1;              // RRM ORG QA: PSAR trail shift (1–3 bars back)
input int         Inp_RRM_ORG_PsarFlipDelay_W      = -99;            // RRM ORG PSAR: PSAR Flip delay LayerW override (-99=use global, 0=flip bar, 1-10=window)
input int         Inp_RRM_ORG_PsarFlipDelay_M      = -99;            // RRM ORG PSAR: PSAR Flip delay LayerM override (-99=use global, 0=flip bar, 1-10=window)
input int         Inp_RRM_ORG_PsarFlipDelay_S      = -99;            // RRM ORG PSAR: PSAR Flip delay LayerS override (-99=use global, 0=flip bar, 1-10=window)
input int         Inp_RRM_ORG_PSAR_FlipGraceBars   = 0;              // RRM ORG PSAR: PSAR Ignore vote for N bars after an adverse flip (0=disabled)
input double      Inp_RRM_ORG_PsarStep             = 0.05;           // RRM ORG PSAR: PSAR Step
input double      Inp_RRM_ORG_PsarMax              = 0.5;            // RRM ORG PSAR: PSAR Max
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 RRM_ORG: RSI Settings";
input group "╚════════════════════════════════════════════════════════╝";
input ERsiMode    Inp_RRM_ORG_RsiMode              = RSI_TREND_ABOVE_50; // RRM ORG RSI: RSI Mode
input int         Inp_RRM_ORG_RsiPeriod            = 14;             // RRM ORG RSI: RSI Period
input double      Inp_RRM_ORG_Rsi_OB               = 70.0;           // RRM ORG RSI: RSI Overbought
input double      Inp_RRM_ORG_Rsi_OS               = 30.0;           // RRM ORG RSI: RSI Oversold
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 RRM_ORG: Stochastic Settings";
input group "╚════════════════════════════════════════════════════════╝";
input EStochMode  Inp_RRM_ORG_Sto_Mode             = STO_CROSS_SIGNAL; // RRM ORG STO: Sto Mode
input int         Inp_RRM_ORG_Sto_K                = 5;              // RRM ORG STO: Sto K period
input int         Inp_RRM_ORG_Sto_D                = 3;              // RRM ORG STO: Sto D period
input int         Inp_RRM_ORG_Sto_Slow             = 3;              // RRM ORG STO: Sto Slowing period
input double      Inp_RRM_ORG_Sto_OB               = 80.0;           // RRM ORG STO: Sto Overbought
input double      Inp_RRM_ORG_Sto_OS               = 20.0;           // RRM ORG STO: Sto Oversold
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 RRM_ORG: VRC Settings";
input group "╚════════════════════════════════════════════════════════╝";
input int         Inp_RRM_ORG_VRC_Lookback         = 100;            // RRM ORG VRC: lookback bars for regime classification
input double      Inp_RRM_ORG_VRC_LowThreshold     = 33.0;           // RRM ORG VRC: low-volatility percentile threshold
input int         Inp_RRM_ORG_VRC_ATR_Period       = 14;             // RRM ORG VRC: ATR period for VRC calculation
#endif // SEA_PRESET_RRM_ORG

#ifdef SEA_PRESET_TOPINVESTOR
input group " ";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "    📐 PRESET: TOPINVESTOR";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
// ════════════════════════════════════════════════════════════════
// TOPINVESTOR: STANDARD — methodology defaults.
// Change only when testing or adapting to different instruments.
// ════════════════════════════════════════════════════════════════
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 TOPINVESTOR: STANDARD — EMA Ribbon";
input group "╚════════════════════════════════════════════════════════╝";
input int         Inp_TI_Ema1                      = 9;              // TI EMA: EMA1 period (trailing exit ref)
input int         Inp_TI_Ema2                      = 50;             // TI EMA: EMA2 period (primary bounce)
input int         Inp_TI_Ema3                      = 89;             // TI EMA: EMA3 period (intermediate structure)
input int         Inp_TI_Ema4                      = 200;            // TI EMA: EMA4 period (major trend anchor)
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 TOPINVESTOR: STANDARD — Signal Architecture";
input group "╚════════════════════════════════════════════════════════╝";
input bool        Inp_TI_BlockUnorderedPhase       = true;           // TI Arch: block unordered phase
input bool        Inp_TI_RequireMinPhaseConfirm    = true;           // TI Arch: require phase confirm bars
input bool        Inp_TI_Emerging_AllowStrong      = false;          // TI Arch: allow strong trades in EM phase
input bool        Inp_TI_CloseOnReverse            = false;          // TI Arch: close on bias reversal
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 TOPINVESTOR: STANDARD — LAYER (Pullback Detection)";
input group "╚════════════════════════════════════════════════════════╝";
input int         Inp_TI_LayerBaselineLookback     = 34;             // TI Layer: baseline lookback
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 TOPINVESTOR: STANDARD — HTF Confirmation";
input group "╚════════════════════════════════════════════════════════╝";
input int         Inp_TI_MTF_EMA_Fast              = 50;             // TI HTF: fast EMA period
input int         Inp_TI_MTF_EMA_Slow              = 200;            // TI HTF: slow EMA period
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 TOPINVESTOR: STANDARD — EXIT Strategy";
input group "╚════════════════════════════════════════════════════════╝";
input ETrailingMode   Inp_TI_TrailMode             = TRAIL_EMA;      // TI Exit: trail mode
input int         Inp_TI_TrailEMA_Shift            = 1;              // TI Exit: trail EMA shift (1=tight, 2=cushion)
input ETrailTrigger   Inp_TI_TrailTrigger          = TRIGGER_BREAKEVEN; // TI Exit: trail trigger
input double      Inp_TI_TrailStepPips             = 5.0;            // TI Exit: trail step (pips)
input double      Inp_TI_TrailProfitPercent        = 2.0;            // TI Exit: trail lock profit %
input ESLMode     Inp_TI_SLMode                    = SL_MODE_SWING;  // TI Exit: SL mode
input int         Inp_TI_SL_AtrPeriod              = 14;             // TI Exit: ATR period (SL_MODE_ATR only)
input double      Inp_TI_SL_AtrMult                = 1.0;            // TI Exit: ATR multiplier — SL = swing_anchor − ATR×N (SL_MODE_ATR; 0.5–1.5 typical)
input ETPMode     Inp_TI_TPMode                    = TP_MODE_RR;     // TI Exit: TP mode
input double      Inp_TI_RRRatio                   = 2.0;            // TI Exit: R:R ratio
input EBeMode     Inp_TI_BE_Mode                   = BE_MODE_R_MULTIPLE; // TI Exit: BE mode
input double      Inp_TI_BE_RMultiple              = 1.0;            // TI Exit: BE trigger (N×R)
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 TOPINVESTOR: STANDARD — EMA Fan Filter";
input group "╚════════════════════════════════════════════════════════╝";
input bool        Inp_TI_EmaFanFilterEnabled       = true;           // TI Fan: enable EMA fan filter
input double      Inp_TI_EmaFanBase_M1M5           = 50.0;           // TI Fan: max pips M1–M5
input double      Inp_TI_EmaFanBase_M6M30          = 80.0;           // TI Fan: max pips M6–M30
input double      Inp_TI_EmaFanBase_H1             = 120.0;          // TI Fan: max pips H1
input double      Inp_TI_EmaFanBase_H2H4           = 200.0;          // TI Fan: max pips H2–H4
input double      Inp_TI_EmaFanBase_H4Plus         = 350.0;          // TI Fan: max pips H4+
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 TOPINVESTOR: STANDARD — Drawdown Protection       ║";
input group "╚════════════════════════════════════════════════════════╝";
input bool        Inp_TI_EnableDDProtection        = true;           // TI DD: enable
input int         Inp_TI_MaxConsecutiveLosses      = 4;              // TI DD: max consecutive losses
input int         Inp_TI_MaxTradesPerDay           = 0;              // TI DD: max trades/day (0=unlimited)
input double      Inp_TI_MaxDailyDrawdownPct       = 2.0;            // TI DD: max daily DD %
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📊 TOPINVESTOR: VPRR Volume Confirmation";
input group "╚════════════════════════════════════════════════════════╝";
input EVPRRVolumeType Inp_TI_VPRR_VolumeType       = VPRR_VOL_AUTO;  // TI VPRR: Volume source (Auto=real then tick fallback)
input bool        Inp_TI_VPRR_AutoEnable           = true;           // TI VPRR: Auto-enable VPRR based on instrument type (ON=auto; OFF=use manual toggle below)
input bool        Inp_TI_VPRR_Enabled              = false;          // TI VPRR: Manual enable (only used when AutoEnable=OFF)
input int         Inp_TI_VPRR_RecoveryBars         = 5;              // TI VPRR: Default recovery bars (1-10); per-instrument overrides in shared block below
input bool        Inp_TI_PhaseAllowEM              = true;           // TI: allow Emerging phase

// ════════════════════════════════════════════════════════════════
// TOPINVESTOR: Quick Profile + core toggles
// ════════════════════════════════════════════════════════════════
input group " ";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "    📐 PRESET: TOPINVESTOR: PROFILES";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input ETIProfile  Inp_TI_Profile                   = TI_MODERATE;    // TI: profile select
input int         Inp_TI_MinBarsAfterClose         = 3;              // TI: cooldown bars after close (0=off)
input int         Inp_TI_ReEntryLotScalePct        = 50;             // TI Re-entry: lot size % for re-entry after BE (0=full size; 50=half)
// ════════════════════════════════════════════════════════════════
// TOPINVESTOR: Conservative voters — always active
// ════════════════════════════════════════════════════════════════
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 TOPINVESTOR: CONSERVATIVE (always active)";
input group "╚════════════════════════════════════════════════════════╝";
input double      Inp_TI_Psar_Step                 = 0.02;           // TI Con: PSAR step
input double      Inp_TI_Psar_Max                  = 0.2;            // TI Con: PSAR max
input int         Inp_TI_ADX_Period                = 14;             // TI Con: ADX period
input double      Inp_TI_ADX_Percentile            = 50.0;           // TI Con: ADX percentile threshold
input int         Inp_TI_ADX_Lookback              = 100;            // TI Con: ADX percentile lookback
input double      Inp_TI_ADX_Threshold_Accum       = 12.0;           // TI Con: ADX threshold Accumulation
input double      Inp_TI_ADX_Threshold_Trend       = 25.0;           // TI Con: ADX threshold Trending
input double      Inp_TI_ADX_Threshold_Dist        = 18.0;           // TI Con: ADX threshold Distribution
input int         Inp_TI_CandleBody_AvgPeriod      = 10;             // TI Con: CBody avg period
input double      Inp_TI_CandleBody_MaxMult        = 2.5;            // TI Con: CBody max spike mult
// ════════════════════════════════════════════════════════════════
// TOPINVESTOR: Moderate additions — active when Profile >= Moderate
// ════════════════════════════════════════════════════════════════
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 TOPINVESTOR: MODERATE +=Conservative";
input group "╚════════════════════════════════════════════════════════╝";
input int         Inp_TI_MACD_Fast                 = 12;             // TI Mod: MACD fast
input int         Inp_TI_MACD_Slow                 = 26;             // TI Mod: MACD slow
input int         Inp_TI_MACD_Signal               = 9;              // TI Mod: MACD signal
input int         Inp_TI_MACD_FreshBars            = 5;              // TI Mod: MACD fresh bars
input double      Inp_TI_MACD_SlopeMin             = 0.00001;        // TI Mod: MACD slope min
input int         Inp_TI_CCI_Period                = 14;             // TI Mod: CCI period
input int         Inp_TI_BB_Period                 = 20;             // TI Mod: BB period
input double      Inp_TI_BB_Deviation              = 2.0;            // TI Mod: BB deviation
// ════════════════════════════════════════════════════════════════
// TOPINVESTOR: Full additions — active when Profile >= Full
// ════════════════════════════════════════════════════════════════
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 TOPINVESTOR: FULL +=Moderate";
input group "╚════════════════════════════════════════════════════════╝";
input double      Inp_TI_Fib_MinRetracement        = 0.38;           // TI Full: Fib min retracement
input double      Inp_TI_Fib_MaxRetracement        = 0.618;          // TI Full: Fib max retracement
input int         Inp_TI_Fib_SwingLookback         = 50;             // TI Full: Fib swing lookback
input double      Inp_TI_CandleBody_FullRatio      = 0.75;           // TI Full: min close ratio for body quality gate
#endif // SEA_PRESET_TOPINVESTOR


input group " ";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "    ⚠️  CUSTOM PRESETS OVERRIDES! (Step1-5)";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "╔════════════════════════════════════════════════════════╗";
input group "║   🔧 STEP 1: BIAS (Major Trend Direction)";
input group "╚════════════════════════════════════════════════════════╝";
input EBiasMode   Inp_CUSTOM_BiasMode              = BIAS_4EMA;      // Override: Bias Mode: Manual, 2-EMA, 4-EMA
input EManualSide Inp_CUSTOM_ManualSide            = SIDE_BOTH;      // Override: Bias Side
input bool        Inp_CUSTOM_BiasEnabled           = true;           // Override: Bias Enabled
input int         Inp_CUSTOM_BiasFastID            = 2;              // Override: Bias Fast ID
input int         Inp_CUSTOM_BiasSlowID            = 3;              // Override: Bias Slow ID
input group "╔════════════════════════════════════════════════════════╗";
input group "║   🔧 STEP 2: MA | EMA";
input group "╚════════════════════════════════════════════════════════╝";
input EMaMethod   Inp_CUSTOM_MaType                = METHOD_EMA;     // Override: MA: SMA, EMA
input int         Inp_CUSTOM_MaHorShift            = 1;              // Override: MA: Hor Shift
input int         Inp_CUSTOM_MaVerShift            = 1;              // Override: MA: Ver Shift
input int         Inp_CUSTOM_Ema1Period            = 5;              // Override: EMA1 Period
input int         Inp_CUSTOM_Ema2Period            = 13;             // Override: EMA2 Period
input int         Inp_CUSTOM_Ema3Period            = 34;             // Override: EMA3 Period
input int         Inp_CUSTOM_Ema4Period            = 89;             // Override: Ema4 Period
input group "╔════════════════════════════════════════════════════════╗";
input group "║   🔧 STEP 3: ENTRY Signal (Timing Strategy)";
input group "╚════════════════════════════════════════════════════════╝";
input EAutoStrategy  Inp_CUSTOM_AutoStrat          = STRAT_4EMA_LAYER;  // Override: STRATegy
input bool        Inp_CUSTOM_CloseOnReverse        = false;          // Override: Close On Reverse
input group "╔════════════════════════════════════════════════════════╗";
input group "║   🔧 STEP 3b: PHASE / LAYER / VPRR (4-EMA Architecture)";
input group "╚════════════════════════════════════════════════════════╝";
input bool        Inp_CUSTOM_PhaseDetectionEnabled = true;          // Override: [PH] Enable market-phase detection (TRENDING/EMERGING/UNORDERED)
input bool        Inp_CUSTOM_BlockUnorderedPhase   = true;           // Override: [PH] Block trades while phase is UNORDERED
input bool        Inp_CUSTOM_BlockEmergingPhase    = false;          // Override: [PH] Block trades while phase is EMERGING
input bool        Inp_CUSTOM_EnableLayerDetection  = true;          // Override: [LY] Enable EMA-layer detection (L1/L2/L3)
input bool        Inp_CUSTOM_LayerPullbackEnabled  = false;          // Override: [LY] Enable layer pullback-recovery state machine
input bool        Inp_CUSTOM_ClimaxGuard_Enabled   = true;           // Override: [CG] Enable climax/exhaustion guard
input bool        Inp_CUSTOM_VPRR_Enabled          = false;          // Override: [VP] Enable Volume Pullback-Recovery Ratio voter
input group "╔════════════════════════════════════════════════════════╗";
input group "║   🔧 STEP 4: Candle Close & Candle Body";
input group "╚════════════════════════════════════════════════════════╝";
input EBarCloseMode  Inp_CUSTOM_BarClose_Mode      = BC_LAYER_AWARE; // Override: [CC] CClose Mode: DISABLED/FIXED_EMA/LAYER_AWARE/BIAS_FAST
input EEmaRole    Inp_CUSTOM_BarClose_DefaultEMA   = ROLE_EMA1;      // Override: [CC] CClose in FIXED mode: EMA1, EMA2, EMA3, EMA4
input bool        Inp_CUSTOM_BarClose_Enabled      = true;           // Override: [CC] CClose Enable
input double      Inp_CUSTOM_CandleBody_MinCloseRatio = 0.0;         // Override: [CB] CBody Min close ratio (0=off, 0.75=TopInvestor)
input group "╔═══════════════════════════════════════════════════════╗";
input group "║   📊 STEP 5: Fibonacci Retracement Voter";
input group "╚═══════════════════════════════════════════════════════╝";
input bool        Inp_CUSTOM_Ind_Fib_Enabled       = false;          // Override: [Fib] Enable
input double      Inp_CUSTOM_Fib_MinRetracement    = 0.38;           // Override: [Fib] Min pullback depth
input double      Inp_CUSTOM_Fib_MaxRetracement    = 0.618;          // Override: [Fib] Max pullback depth
input int         Inp_CUSTOM_Fib_SwingLookback     = 50;             // Override: [Fib] Swing search bars
input group "╔════════════════════════════════════════════════════════╗";
input group "║   🔧 STEP 6: Pullback Gate";
input group "╚════════════════════════════════════════════════════════╝";
// Pullback gate uses pure distance comparison: the current EMA gap must exceed the prior EMA gap (no pip threshold).
input bool        Inp_CUSTOM_RequireRecoveryMomentum = false;        // Override: PULL recovery
input int         Inp_CUSTOM_Lookback              = 5;              // Override: PULL lookback
input group "╔════════════════════════════════════════════════════════╗";
input group "║   🔧 STEP X: Trail EMA (Global)";
input group "╚════════════════════════════════════════════════════════╝";
input int         Inp_CUSTOM_TrailEMA_Period       = 9;              // Override: [Trail] EMA period for TRAIL_EMA mode
input int         Inp_CUSTOM_TrailEMA_Shift        = 1;              // Override: [Trail] EMA shift (1=current bar, 2=one bar cushion)

input group " ";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "    ⚠️  CUSTOM INDICATORS";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📊 ADX (Average Directional Index - Strength of Market Trend)";
input group "╚════════════════════════════════════════════════════════╝";
input EADXMode    Inp_CUSTOM_Ind_Adx_Mode          = ADX_MODE_STATIC; // Ind [ADX]: Mode
input bool        Inp_CUSTOM_Ind_Adx_Enabled       = false;          // Ind: [ADX] Enable
input int         Inp_CUSTOM_Ind_Adx_Period        = 14;             // Ind [ADX]: Period
input int         Inp_CUSTOM_Ind_Adx_Threshold     = 20;             // Ind [ADX]: Threshold
input int         Inp_CUSTOM_Ind_Adx_Lookback      = 100;            // Ind [ADX]: Lookback
input double      Inp_CUSTOM_Ind_Adx_Percentile    = 50.0;           // Ind [ADX]: Percentile
input double      Inp_CUSTOM_Ind_Adx_Thr_Accum     = 12.0;           // Ind [ADX]: Accumulation
input double      Inp_CUSTOM_Ind_Adx_Thr_Trending  = 25.0;           // Ind [ADX]: Trending
input double      Inp_CUSTOM_Ind_Adx_Thr_Distrib   = 18.0;           // Ind [ADX]: Distribution
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📊 ATR (Average True Range - Market Volatility - Non-directional)";
input group "╚════════════════════════════════════════════════════════╝";
input bool        Inp_CUSTOM_Ind_Atr_Enabled       = false;          // Ind [ATR]: Enable ATR
input int         Inp_CUSTOM_Ind_Atr_Period        = 14;             // Ind [ATR]: Period
input double      Inp_CUSTOM_Ind_Atr_VoteMinPips   = 5.0;            // Ind [ATR]: Voting min pips
input double      Inp_CUSTOM_Ind_Atr_VoteMaxPips   = 50.0;           // Ind [ATR]: Voting max pips
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📊 BB (Bollinger Bands - Market Volatility and Over bought/sold Levels)";
input group "╚════════════════════════════════════════════════════════╝";
input EBbMode     Inp_CUSTOM_Ind_Bb_Mode           = BB_TREND_FOLLOW; // Ind [BB]: Mode
input bool        Inp_CUSTOM_Ind_Bb_Enabled        = false;          // Ind [BB]: Enable BB
input int         Inp_CUSTOM_Ind_Bb_Period         = 20;             // Ind [BB]: Period
input double      Inp_CUSTOM_Ind_Bb_Dev            = 2.0;            // Ind [BB]: Deviation
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📊 CBody (Candle Body - Votes Against Overextended Candles (news/spikes))";
input group "╚════════════════════════════════════════════════════════╝";
input bool        Inp_CUSTOM_Ind_CandleBody_Enabled    = true;       // Ind [CBody]: Enable CB
input bool        Inp_CUSTOM_Ind_CandleBody_RequireDirection = true; // Ind [CBody]: Require DIR
input int         Inp_CUSTOM_Ind_CandleBody_AvgPeriod  = 5;          // Ind [CBody]: Average body period
input int         Inp_CUSTOM_Ind_CandleBody_CheckBars  = 3;          // Ind [CBody]: Bars to check
input double      Inp_CUSTOM_Ind_CandleBody_MaxMult    = 4.0;        // Ind [CBody]: Max body multiplier
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📊 CCI (Commodity Channel Index - Momentum Oscilator)";
input group "╚════════════════════════════════════════════════════════╝";
input ECciMode    Inp_CUSTOM_Ind_Cci_Mode          = CCI_TREND_ZERO; // Ind [CCI]: Mode
input bool        Inp_CUSTOM_Ind_Cci_Enabled       = false;          // Ind [CCI]: Enable CCI
input int         Inp_CUSTOM_Ind_Cci_Period        = 14;             // Ind [CCI]: Period
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📊 CI (Choppiness Index - Block Trades in Ranging Market)";
input group "╚════════════════════════════════════════════════════════╝";
input bool        Inp_CUSTOM_Ind_CI_Enabled        = false;          // Ind [CI]: Enable ranging market filter
input int         Inp_CUSTOM_Ind_CI_Period         = 14;             // Ind [CI]: Period
input double      Inp_CUSTOM_Ind_CI_RangingThreshold  = 61.8;        // Ind [CI]: Threshold (>= this value = reject)
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📊 MACD (Moving Average Convergence Divergence - Trend-Following Momentum)";
input group "╚════════════════════════════════════════════════════════╝";
input EMacdVoteMode  Inp_CUSTOM_Ind_Macd_Mode      = MACD_ZERO_AND_HIST; // Ind: TI Full: [MACD] Mode
input bool        Inp_CUSTOM_Ind_Macd_Enabled      = false;          // Ind: TI Full: [MACD] Enable MACD
input bool        Inp_CUSTOM_Ind_Macd_RequireSlope       = false;    // Ind: TI Full: [MACD] Require Slope
input bool        Inp_CUSTOM_Ind_Macd_RequireDivergence  = false;    // Ind: TI Full: [MACD] Require Divergence
input bool        Inp_CUSTOM_Ind_Macd_RequireHook        = false;    // Ind: TI Full: [MACD] Require Histogram Flip
input int         Inp_CUSTOM_Ind_Macd_Fast         = 8;              // Ind: TI Full: [MACD] Fast EMA period
input int         Inp_CUSTOM_Ind_Macd_Slow         = 13;             // Ind: TI Full: [MACD] Slow EMA period
input int         Inp_CUSTOM_Ind_Macd_Sig          = 5;              // Ind: TI Full: [MACD] Signal SMA period
input int         Inp_CUSTOM_Ind_Macd_FreshBars    = 3;              // Ind: TI Full: [MACD] Fresh Bars validity
input double      Inp_CUSTOM_Ind_Macd_SlopeMin     = 0.00001;       // Ind: TI Full: [MACD] Min slope change per bar
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📊 MFI (Money Flow Index - Oscillator Buying Selling Pressure)";
input group "╚════════════════════════════════════════════════════════╝";
input EMfiMode    Inp_CUSTOM_Ind_Mfi_Mode          = MFI_ZONE_FILTER; // Ind: TI Full: [MFI] Mode
input bool        Inp_CUSTOM_Ind_Mfi_Enabled       = false;          // Ind: TI Full: [MFI] Enable MFI
input int         Inp_CUSTOM_Ind_Mfi_Period        = 14;             // Ind: TI Full: [MFI] Period
input double      Inp_CUSTOM_Ind_Mfi_Level         = 50.0;           // Ind: TI Full: [MFI] Threshold/level
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📊 P123 (Mark Crisp 1-2-3 fractal breakout pattern (see Ross Hook))";
input group "╚════════════════════════════════════════════════════════╝";
input bool        Inp_CUSTOM_Ind_P123_Enabled      = false;          // Ind: TI Full: [P123] Enable 1-2-3
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📊 PSAR (Parabolic Stop and Reverse - Trend-Following Indicator)";
input group "╚════════════════════════════════════════════════════════╝";
input bool        Inp_CUSTOM_Ind_Psar_Enabled      = true;           // Ind: TI Full: [PSAR] Enable PSAR
input int         Inp_CUSTOM_Ind_PsarFlipDelay     = 10;             // Ind: TI Full: [PSAR] Flip timer: -1=persistent, 0=flip bar, 1-10=countdown
input double      Inp_CUSTOM_Ind_Psar_Step         = 0.05;           // Ind: TI Full: [PSAR] Step
input double      Inp_CUSTOM_Ind_Psar_Max          = 0.5;            // Ind: TI Full: [PSAR] Maximum
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📊 Ross Hook (Trend Momentum (see to P123))";
input group "╚════════════════════════════════════════════════════════╝";
input bool        Inp_CUSTOM_Ind_Ross_Enabled      = false;          // Ind: TI Full: [Ross] Enable Ross Hook
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📊 RSI (Relative Strength Index - Monentum Oscilator)";
input group "╚════════════════════════════════════════════════════════╝";
input ERsiMode    Inp_CUSTOM_Ind_Rsi_Mode          = RSI_TREND_ABOVE_50; // Ind: TI Full: [RSI] Mode
input bool        Inp_CUSTOM_Ind_Rsi_Enabled       = false;          // Ind: TI Full: [RSI] Enable RSI
input int         Inp_CUSTOM_Ind_Rsi_Period        = 14;             // Ind: TI Full: [RSI] Period
input double      Inp_CUSTOM_Ind_Rsi_OB            = 70.0;           // Ind: TI Full: [RSI] Overbought
input double      Inp_CUSTOM_Ind_Rsi_OS            = 30.0;           // Ind: TI Full: [RSI] Oversold
input group "╔════════════════════════════=═══════════════════════════╗";
input group "║   📊 STO (Stochastic Oscillator - Momentum Potential Market Reversals)";
input group "╚════════════════════════════════════════════════════════╝";
input EStochMode  Inp_CUSTOM_Ind_Sto_Mode          = STO_CROSS_SIGNAL;  // Ind: TI Full: [Sto] Mode
input bool        Inp_CUSTOM_Ind_Sto_Enabled       = false;          // Ind: TI Full: [Sto] Enable STO
input int         Inp_CUSTOM_Ind_Sto_K             = 5;              // Ind: TI Full: [Sto] %K period
input int         Inp_CUSTOM_Ind_Sto_D             = 3;              // Ind: TI Full: [Sto] %D period
input int         Inp_CUSTOM_Ind_Sto_Slow          = 3;              // Ind: TI Full: [Sto] Slowing
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📊 VRC (Volatility Regime Classifier - Reject Trades in Low Volatility (quiet/choppy markets))";
input group "╚════════════════════════════════════════════════════════╝";
input bool        Inp_CUSTOM_Ind_VRC_Enabled       = false;          // Ind: TI Full: [VRC] Enable volatility regime
input int         Inp_CUSTOM_Ind_VRC_ATR_Period    = 14;             // Ind: TI Full: [VRC] VRC-ATR period
input int         Inp_CUSTOM_Ind_VRC_Lookback      = 100;            // Ind: TI Full: [VRC] Lookback bars for percentile
input double      Inp_CUSTOM_Ind_VRC_LowThreshold  = 33.0;           // Ind: TI Full: [VRC] Low volatility threshold (percentile)

input group " ";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "    🔧 PAIR SETTINGS (Type | Spread)";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "╔════════════════════════════════════════════════════════╗";
input group "║   🔧 Pair Type Detection";
input group "╚════════════════════════════════════════════════════════╝";
input EPairType   Inp_Adaptive_PairType            = PAIR_TYPE_AUTO; // Pair: Pair type (PAIR_TAPY_AUTO)
// input string   Inp_Adaptive_PairInfo            = "AUTO: EURUSD/GBPUSD/USDJPY=MAJOR; XAUUSD/GOLD=GOLD; BTC/ETH=CRYPTO; TRY/ZAR/MXN=EXOTIC; others=MINOR";
input group "╔════════════════════════════════════════════════════════╗";
input group "║   🔧 Max Spread by Pair Type (pips)";
input group "╚════════════════════════════════════════════════════════╝";
input double      Inp_Adaptive_Spread_Major        = 3.0;            // Pair: Max spread major (pips)
input double      Inp_Adaptive_Spread_Minor        = 5.0;            // Pair: Max spread minor (pips)
input double      Inp_Adaptive_Spread_Exotic       = 11.0;           // Pair: Max spread exotic (pips)
input double      Inp_Adaptive_Spread_Gold         = 6.0;            // Pair: Max spread gold/XAU (pips)
input double      Inp_Adaptive_Spread_Crypto       = 50.0;           // Pair: Max spread crypto (pips)
// input string   Inp_Adaptive_Note1               = "📝 Note: SL/TP cushions auto-adjust by timeframe (no input needed)";
// input string   Inp_Adaptive_Note2               = "📝 M15=5 pips, H1=10 pips, H4=20 pips (see GetTFBasedCushion)";

input group " ";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "    🎯 STRATEGY SETTINGS (PRESET_CUSTOM Only)";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "╔════════════════════════════════════════════════════════╗";
input group "║   🎯 (TP) TAKE PROFIT (CUSTOM only)";
input group "╚════════════════════════════════════════════════════════╝";
input ETPMode     Inp_CUSTOM_TPMode                = TP_MODE_RR;     // Custom: TP mode
input bool        Inp_CUSTOM_TP_Enabled            = true;           // Custom: Enable TP
input double      Inp_CUSTOM_RRRatio               = 2.5;            // Custom: R:R ratio
input double      Inp_CUSTOM_FixedTPPips           = 40.0;           // Custom: Fixed TP
input group "╔════════════════════════════════════════════════════════╗";
input group "║   🎯 EXIT PROFILES";
input group "╚════════════════════════════════════════════════════════╝";
input EExitProfile   Inp_CUSTOM_ExitProfile        = EXIT_PROFILE_RRM; // Custom: Exit profile
// input string   Inp_Exit_Zone_Info1              = "Active for: PRESET_TEST & PRESET_CUSTOM (direct input control)";
// input string   Inp_Exit_Zone_Info2              = "Other presets override exits with strategy-optimized values";
// input string   Inp_CUSTOM_ExitProfile_Info      = "RRM: Swing-based SL, PSAR trail, no ATR multipliers";
input group "╔════════════════════════════════════════════════════════╗";
input group "║   🛑 (SL) STOP LOSS (CUSTOM only)";
input group "╚════════════════════════════════════════════════════════╝";
input ESLMode     Inp_CUSTOM_SLMode                = SL_MODE_PSAR_DOT;  // Custom: SL mode
input bool        Inp_CUSTOM_SL_WidenToMinimum     = false;          // Custom: If true: widen to min.; if false: block TE
// input string   Inp_SL_Help1                     = "FIXED_PIPS: Simple pip distance";
// input string   Inp_SL_Help2                     = "MODE_SWING: Recent structure high/low";
// input string   Inp_SL_Help3                     = "PSAR_DOT: PSAR level  |  PERCENT: % of price  |  FRACTAL: Bill Williams";
// input string   Inp_SL_TFCushion_Note            = "PSAR/Swing cushions auto-set by timeframe (M15=5, H1=10, H4=20 pips)";
input int         Inp_CUSTOM_SwingLookback         = 34;             // Custom: Swing lookback (bars SL_MODE_SWING)
input double      Inp_CUSTOM_SL_FixedPips          = 20.0;           // Custom: SL distance (pips SL_MODE_FIXED_PIPS)
input double      Inp_CUSTOM_SL_MinPips            = 3.0;            // Custom: Min. SL pips (0 = no user floor, broker minimum still applies)
input double      Inp_CUSTOM_SLPercent             = 0.5;            // Custom: SL as % of entry
input int         Inp_CUSTOM_SL_AtrPeriod          = 14;             // Custom: ATR period (SL_MODE_ATR only)
input double      Inp_CUSTOM_SL_AtrMult            = 1.0;            // Custom: ATR multiplier — SL = swing_anchor − ATR×N (SL_MODE_ATR; 0.5–1.5 typical)
// input group "--- SL Configuration Examples ---";
// input string   Inp_Ex1_Header                   = "Example 1 - Simple Fixed SL: Inp_CUSTOM_SLMode=SL_MODE_FIXED_PIPS, Inp_CUSTOM_SL_FixedPips=20";
// input string   Inp_Ex2_Header                   = "Example 2 - Swing Structure: Inp_CUSTOM_SLMode=SL_MODE_SWING, Inp_CUSTOM_SwingLookback=20";
// input string   Inp_Ex3_Header                   = "Example 3 - Fractal SL:      Inp_CUSTOM_SLMode=SL_MODE_FRACTAL, Inp_CUSTOM_FractalPeriod=5, Inp_CUSTOM_TPFractalOffset=1";

input group "╔════════════════════════════════════════════════════════╗";
input group "║   🛑 (SL) STOP LOSS FRACTAL: used with SL_FRACTAL & SL_PSAR_DOT";
input group "╚════════════════════════════════════════════════════════╝";
input int         Inp_CUSTOM_FractalPeriod         = 5;              // Custom: Fractal period
input int         Inp_CUSTOM_TPFractalOffset       = 1;              // Custom: Fractal offset
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📈 (TS) TRAILING STOP (CUSTOM only)";
input group "╚════════════════════════════════════════════════════════╝";
// PSAR trail cushion (used by CUSTOM preset when TrailMode=TRAIL_PSAR):
input EPsarTrailCushionMode Inp_CUSTOM_PSAR_TrailCushionMode = PSAR_CUSHION_ATR; // Custom: PSAR cushion mode (PIPS / ATR / PERCENT)
input int         Inp_CUSTOM_TrailCushionAtrPeriod = 14;            // Custom: PSAR cushion ATR period
input double      Inp_CUSTOM_TrailCushionAtrMult   = 0.5;           // Custom: PSAR cushion ATR multiplier (cushion = ATR × this)
input double      Inp_CUSTOM_TrailCushionPct       = 0.04;          // Custom: PSAR cushion % of price (PERCENT mode)
input ETrailingMode  Inp_CUSTOM_TrailMode          = TRAIL_EMA;     // Custom: Trailing Mode
input ETrailTrigger  Inp_CUSTOM_TrailTrigger       = TRIGGER_IMMEDIATE; // Custom: When Trail
input bool        Inp_CUSTOM_TrailLockProfit       = true;           // Custom: Trail Lock Profit
input double      Inp_CUSTOM_TrailDistancePips     = 5.0;            // Custom: Trail Pips
input double      Inp_CUSTOM_BEThresholdPips       = 5.0;            // Custom: BE Pips
// Trail trigger: % of RISK (R-multiple based)
// Examples: 50 = 0.5R, 100 = 1.0R, 150 = 1.5R
input double      Inp_CUSTOM_TrailProfitPercent    = 25.0;           // Custom: Trail trigger as % of risk for TRIGGER_PROFIT_PERCENT
input double      Inp_CUSTOM_TrailStepPips         = 5.0;            // Custom: Trail Step Pips
input group "╔════════════════════════════════════════════════════════╗";
input group "║   ⚖️ (BE) BREAK-EVEN (CUSTOM only)";
input group "╚════════════════════════════════════════════════════════╝";
input EBeMode     Inp_CUSTOM_BE_Mode               = BE_MODE_TP_PROGRESS_PCT; // Custom: BE mode
// input string   Inp_RRM_Info1                    = "RRM uses % of TP distance for BE — not absolute pips";
// input string   Inp_RRM_Info2                    = "Only active when ExitProfile = EXIT_PROFILE_RRM";
// input string   Inp_RRM_Info3                    = "Example: SL=10 pips, TP=30 pips (3:1 RR), BE@33% → triggers at +10 pips profit";
input group "╔════════════════════════════════════════════════════════╗";
input group "║   🛡 (TE) COOLDOWN BARS Post-Trade Protection";
input group "╚════════════════════════════════════════════════════════╝";
input int         Inp_CUSTOM_MinBarsAfterClose      = 2;             // Custom: TE: Min bars cooldown (0=off)
input int         Inp_CUSTOM_MinBarsAfterWeekendGap = 2;             // Custom: TS: Bars skip weekend gap (0=off, recommended 1-2)

//+------------------------------------------------------------------+
//| ADAPTIVE UTILITY FUNCTIONS                                       |
//+------------------------------------------------------------------+

// Detect pair type from symbol name for adaptive spread/parameter selection.
EPairType DetectPairType(const string symbol)
{
   string sym = symbol;
   StringToUpper(sym);
   // Majors (tight spreads)
   if(StringFind(sym, "EURUSD") >= 0) return PAIR_TYPE_MAJOR;
   if(StringFind(sym, "GBPUSD") >= 0) return PAIR_TYPE_MAJOR;
   if(StringFind(sym, "USDJPY") >= 0) return PAIR_TYPE_MAJOR;
   if(StringFind(sym, "USDCHF") >= 0) return PAIR_TYPE_MAJOR;
   if(StringFind(sym, "AUDUSD") >= 0) return PAIR_TYPE_MAJOR;
   if(StringFind(sym, "USDCAD") >= 0) return PAIR_TYPE_MAJOR;
   if(StringFind(sym, "NZDUSD") >= 0) return PAIR_TYPE_MAJOR;
   // Gold
   if(StringFind(sym, "XAUUSD") >= 0) return PAIR_TYPE_GOLD;
   if(StringFind(sym, "GOLD")   >= 0) return PAIR_TYPE_GOLD;
   // Crypto
   if(StringFind(sym, "BTC") >= 0) return PAIR_TYPE_CRYPTO;
   if(StringFind(sym, "ETH") >= 0) return PAIR_TYPE_CRYPTO;
   // Exotics
   if(StringFind(sym, "TRY") >= 0) return PAIR_TYPE_EXOTIC;
   if(StringFind(sym, "ZAR") >= 0) return PAIR_TYPE_EXOTIC;
   if(StringFind(sym, "MXN") >= 0) return PAIR_TYPE_EXOTIC;

   // Default: minor pair
   return PAIR_TYPE_MINOR;
}

// Return the appropriate max spread limit (pips) for the detected pair type.
double GetAdaptiveSpreadLimit(EPairType pair_type, const ST_AdaptiveSettings &adaptive)
{
   switch(pair_type)
   {
      case PAIR_TYPE_MAJOR:  return adaptive.Spread_Major;
      case PAIR_TYPE_MINOR:  return adaptive.Spread_Minor;
      case PAIR_TYPE_EXOTIC: return adaptive.Spread_Exotic;
      case PAIR_TYPE_GOLD:   return adaptive.Spread_Gold;
      case PAIR_TYPE_CRYPTO: return adaptive.Spread_Crypto;
      default:               return adaptive.Spread_Minor;
   }
}

//+------------------------------------------------------------------+
//| InitializeConfig(): maps inputs into Settings (NO preset logic)   |
//+------------------------------------------------------------------+
void InitializeConfig()
{
   ZeroMemory(Settings);
   
   // === Global inputs allowed under presets (still mapped normally) ===
   Settings.PrintEffectiveConfig     = Inp_Debug_PrintEffectiveConfig;

   // Map debug level first; DebugFlow=false forces SILENT mode
   Settings.DebugLevel               = Inp_Debug_Flow ? Inp_Debug_Level : DEBUG_SILENT;
   Settings.DebugFlow                = (Settings.DebugLevel >= DEBUG_FULL);
   Settings.DebugEvalFrom            = Inp_Debug_EvalFrom;
   Settings.DebugEvalTo              = Inp_Debug_EvalTo;
   Settings.DebugEvalAt              = Inp_Debug_EvalAt;
   Settings.DebugEvalMode            = Inp_Debug_EvalMode;
   Settings.Stats_TrackRejections    = Inp_Debug_Stats_TrackRejections;
   Settings.Stats_TrackPasses        = Inp_Debug_Stats_TrackPasses;
   Settings.Stats_FullEvaluation     = Inp_Debug_Stats_FullEvaluation;

   Settings.UI_ShowStatusPanel       = Inp_UI_ShowStatusPanel;
   Settings.UI_ShowCockpitPanel      = Inp_UI_ShowCockpitPanel;
   Settings.UI_ManageChartIndicators = Inp_UI_ManageChartIndicators;
   Settings.DrawEntryLines           = Inp_UI_DrawEntryLines;
   Settings.DrawTradeLines           = Inp_UI_DrawTradeLines;
   Settings.ExportCSV                = Inp_Debug_ExportCSV;
   Settings.ExportUseCommonFiles     = Inp_Debug_ExportUseCommonFiles;
   
   // === Tactical UI Theme Mapping ===
   Settings.clr_Header              = Inp_UI_clr_Header;   // Gold 
   Settings.clr_Value               = Inp_UI_clr_Value;    // White 
   Settings.clr_Pass                = Inp_UI_clr_Pass;     // LimeGreen 
   Settings.clr_Fail                = Inp_UI_clr_Fail;     // OrangeRed 
   Settings.clr_Disabled            = Inp_UI_clr_Disabled; // Gray
   
   // Master Toggle and Global Font Color
   Settings.UseCustomColors         = Inp_UI_UseCustomColors; // 
   Settings.UI_FontColor            = Inp_UI_FontColor;       // Yellow

   // === Strategy inputs ===
   Settings.CloseOnReverse          = Inp_CUSTOM_CloseOnReverse;
   Settings.RiskPercent             = Inp_RM_RiskPercentDefault;
   Settings.RiskCapMultiple         = (Inp_RM_RiskCapMultiple > 0.0) ? Inp_RM_RiskCapMultiple : 1.5;
   Settings.FixedLotSize            = 0.0; // 0 = risk-based sizing (default)
   Settings.MaxSpread               = Inp_VETO_MaxSpread;
   Settings.UseSpread               = Inp_VETO_UseSpread;
   Settings.ATR_VoteMinPips         = Inp_CUSTOM_Ind_Atr_VoteMinPips;
   Settings.ATR_VoteMaxPips         = Inp_CUSTOM_Ind_Atr_VoteMaxPips;

   Settings.CandleBody_AvgPeriod    = MathMax(1, Inp_CUSTOM_Ind_CandleBody_AvgPeriod);
   Settings.CandleBody_MaxMult      = Inp_CUSTOM_Ind_CandleBody_MaxMult;
   Settings.CandleBody_CheckBars    = MathMax(1, Inp_CUSTOM_Ind_CandleBody_CheckBars);
   Settings.CandleBody_RequireDirection = Inp_CUSTOM_Ind_CandleBody_RequireDirection;

   Settings.UseMACompatSizer        = false;
   Settings.MA_MaximumRiskPct       = 0.02;   // default (MA preset only; overwritten by ApplyPreset)
   Settings.MA_DecreaseFactor       = 3.0;    // default (MA preset only; overwritten by ApplyPreset)
   Settings.RequirePriceCross       = false;
   Settings.MABenchmarkStrict       = false;

   Settings.RRM_Lookback               = Inp_CUSTOM_Lookback;
   Settings.RequireRecoveryMomentum    = Inp_CUSTOM_RequireRecoveryMomentum;
   
   Settings.Gate_Recovery.mode         = GATE_SCALE_OFF;
   Settings.Gate_Recovery.value        = 0.0;
   Settings.Gate_EmaDiv.mode           = GATE_SCALE_OFF;
   Settings.Gate_EmaDiv.value          = 0.0;
   Settings.Gate_CandleDirection.mode  = GATE_SCALE_OFF;
   Settings.Gate_CandleDirection.value = 0.0;

   // Bias
   Settings.BiasEnabled          = Inp_CUSTOM_BiasEnabled;
   Settings.BiasMode             = Inp_CUSTOM_BiasMode;
   Settings.ManSide              = Inp_CUSTOM_ManualSide;
   Settings.BiasFastID           = MathMax(0, MathMin(3, Inp_CUSTOM_BiasFastID));
   Settings.BiasSlowID           = MathMax(0, MathMin(3, Inp_CUSTOM_BiasSlowID));
   Settings.AutoStrat            = Inp_CUSTOM_AutoStrat;
   Settings.MaType               = Inp_CUSTOM_MaType;
   Settings.ma_h_shift           = Inp_CUSTOM_MaHorShift;
   Settings.ma_v_shift           = Inp_CUSTOM_MaVerShift;
   
   // Filters
   Settings.UseTime              = Inp_VETO_UseTime;
   Settings.StartHr              = Inp_VETO_StartHr;
   Settings.EndHr                = Inp_VETO_EndHr;
   Settings.UseNews              = Inp_VETO_UseNews;
   Settings.NewsPre              = Inp_VETO_NewsPreMinutes;
   Settings.NewsPost             = Inp_VETO_NewsPostMinutes;
   Settings.Ind_MTF_Enabled      = Inp_Ind_MTF_Enabled;
   Settings.MTF_TF1              = Inp_MTF_TF1;
   Settings.MTF_TF2              = Inp_MTF_TF2;
   Settings.MTF_EMA_Fast         = MathMax(1, Inp_MTF_EMA_Fast);
   Settings.MTF_EMA_Slow         = MathMax(1, Inp_MTF_EMA_Slow);
   Settings.MTF_RequirePhase     = Inp_MTF_RequirePhase;
   Settings.MTF_StrictAlignment  = Inp_MTF_StrictAlignment;

   // Fibonacci voter (globally available)
   Settings.Ind_Fib_Enabled      = Inp_CUSTOM_Ind_Fib_Enabled;
   Settings.Fib_MinRetracement   = MathMax(0.0, MathMin(1.0, Inp_CUSTOM_Fib_MinRetracement));
   Settings.Fib_MaxRetracement   = MathMax(Settings.Fib_MinRetracement, MathMin(1.0, Inp_CUSTOM_Fib_MaxRetracement));
   Settings.Fib_SwingLookback    = MathMax(10, Inp_CUSTOM_Fib_SwingLookback);

   // CandleBody close-ratio extension
   Settings.CandleBody_MinCloseRatio = MathMax(0.0, MathMin(1.0, Inp_CUSTOM_CandleBody_MinCloseRatio));

   // TRAIL_EMA period
   Settings.TrailEMA_Period           = MathMax(0, Inp_CUSTOM_TrailEMA_Period);
   Settings.TrailEMA_RibbonRole       = 0;  // CUSTOM: EMA1 as fallback
   Settings.TrailEMA_Shift            = MathMax(1, MathMin(5, Inp_CUSTOM_TrailEMA_Shift));
   Settings.TrailEMA_CushionPips      = 0.0;   // CUSTOM: set via preset or direct cfg override
   Settings.TrailEMA_CushionAtrMult   = 0.0;   // CUSTOM: 0 = disabled (falls back to pip or PSAR)
   Settings.TrailEMA_CushionAtrPeriod = 14;

   // Voting

   // Indicator periods / thresholds
   Settings.P_Ema1               = Inp_CUSTOM_Ema1Period;
   Settings.P_Ema2               = Inp_CUSTOM_Ema2Period;
   Settings.P_Ema3               = Inp_CUSTOM_Ema3Period;
   Settings.P_Ema4               = Inp_CUSTOM_Ema4Period;
   Settings.P_Adx                = Inp_CUSTOM_Ind_Adx_Period;
   Settings.T_Adx                = Inp_CUSTOM_Ind_Adx_Threshold;
   Settings.ADX_Mode                  = Inp_CUSTOM_Ind_Adx_Mode;
   Settings.ADX_Percentile            = Inp_CUSTOM_Ind_Adx_Percentile;
   Settings.ADX_Lookback              = Inp_CUSTOM_Ind_Adx_Lookback;
   Settings.ADX_Threshold_Accumulation= Inp_CUSTOM_Ind_Adx_Thr_Accum;
   Settings.ADX_Threshold_Trending    = Inp_CUSTOM_Ind_Adx_Thr_Trending;
   Settings.ADX_Threshold_Distribution= Inp_CUSTOM_Ind_Adx_Thr_Distrib;
   Settings.P_MacdFast           = Inp_CUSTOM_Ind_Macd_Fast;
   Settings.P_MacdSlow           = Inp_CUSTOM_Ind_Macd_Slow;
   Settings.P_MacdSig            = Inp_CUSTOM_Ind_Macd_Sig;
   Settings.P_Rsi                = Inp_CUSTOM_Ind_Rsi_Period;
   Settings.T_RsiOB              = Inp_CUSTOM_Ind_Rsi_OB;
   Settings.T_RsiOS              = Inp_CUSTOM_Ind_Rsi_OS;
   Settings.P_Cci                = Inp_CUSTOM_Ind_Cci_Period;
   Settings.P_Mfi                = Inp_CUSTOM_Ind_Mfi_Period;
   Settings.T_Mfi                = Inp_CUSTOM_Ind_Mfi_Level;
   Settings.T_MfiOB              = Inp_CUSTOM_Ind_Mfi_Level;
   Settings.T_MfiOS              = Inp_CUSTOM_Ind_Mfi_Level;
   Settings.P_StoK               = Inp_CUSTOM_Ind_Sto_K;
   Settings.P_StoD               = Inp_CUSTOM_Ind_Sto_D;
   Settings.P_StoSlow            = Inp_CUSTOM_Ind_Sto_Slow;
   Settings.T_StoOB              = 80.0;
   Settings.T_StoOS              = 20.0;
   Settings.P_Bb                 = Inp_CUSTOM_Ind_Bb_Period;
   Settings.P_BbDev              = Inp_CUSTOM_Ind_Bb_Dev;
   Settings.P_PsarStep           = Inp_CUSTOM_Ind_Psar_Step;
   Settings.P_PsarMax            = Inp_CUSTOM_Ind_Psar_Max;
   Settings.P_Atr                = Inp_CUSTOM_Ind_Atr_Period;

   // Modes
   Settings.MacdRequireSlope     = Inp_CUSTOM_Ind_Macd_RequireSlope;
   Settings.MacdRequireDivergence= Inp_CUSTOM_Ind_Macd_RequireDivergence;
   Settings.MacdRequireHook      = Inp_CUSTOM_Ind_Macd_RequireHook;
   Settings.MacdFreshBars        = Inp_CUSTOM_Ind_Macd_FreshBars;
   Settings.MacdHistDecelEnabled = false;  // RRM-only pre-filter; set true by PRESET_RRM via Inp_RRM_MacdHistDecel
   Settings.MacdSlopeMin         = Inp_CUSTOM_Ind_Macd_SlopeMin;
   Settings.RsiMode              = Inp_CUSTOM_Ind_Rsi_Mode;
   Settings.CciMode              = Inp_CUSTOM_Ind_Cci_Mode;
   Settings.StoMode              = Inp_CUSTOM_Ind_Sto_Mode;
   Settings.BbMode               = Inp_CUSTOM_Ind_Bb_Mode;
   Settings.MfiMode              = Inp_CUSTOM_Ind_Mfi_Mode;

   // Active votes
   Settings.Ind_Adx_Enabled      = Inp_CUSTOM_Ind_Adx_Enabled;
   Settings.Ind_Macd_Enabled     = Inp_CUSTOM_Ind_Macd_Enabled;
   Settings.Ind_Rsi_Enabled      = Inp_CUSTOM_Ind_Rsi_Enabled;
   Settings.Ind_Cci_Enabled      = Inp_CUSTOM_Ind_Cci_Enabled;
   Settings.Ind_Mfi_Enabled      = Inp_CUSTOM_Ind_Mfi_Enabled;
   Settings.Ind_Sto_Enabled      = Inp_CUSTOM_Ind_Sto_Enabled;
   Settings.Ind_Bb_Enabled       = Inp_CUSTOM_Ind_Bb_Enabled;
   Settings.Ind_Psar_Enabled     = Inp_CUSTOM_Ind_Psar_Enabled;
   Settings.Ind_P123_Enabled     = Inp_CUSTOM_Ind_P123_Enabled;
   Settings.Ind_Ross_Enabled     = Inp_CUSTOM_Ind_Ross_Enabled;
   Settings.Ind_Atr_Enabled      = Inp_CUSTOM_Ind_Atr_Enabled;
   Settings.Ind_CandleBody_Enabled = Inp_CUSTOM_Ind_CandleBody_Enabled;
   Settings.Ind_CI_Enabled        = Inp_CUSTOM_Ind_CI_Enabled;
   Settings.Ind_VRC_Enabled       = Inp_CUSTOM_Ind_VRC_Enabled;
   Settings.Ind_SmaConverge_Enabled = false;  // default (FPM preset only; overwritten by ApplyPreset)

   // Weights


   // DPI v31 (disabled by default; enabled and parameterised by PRESET_RRM_ORG)
   Settings.Ind_Dpi_Enabled             = Inp_RRM_ORG_DPI_Enabled;
   Settings.DPI_MACD_Fast               = MathMax(1, Inp_RRM_ORG_DPI_MacdFast);
   Settings.DPI_MACD_Slow               = MathMax(1, Inp_RRM_ORG_DPI_MacdSlow);
   Settings.DPI_RedSignalType           = MathMax(1, MathMin(5, Inp_RRM_ORG_DPI_RedSignalType));
   Settings.DPI_RedEMA_A                = MathMax(1, Inp_RRM_ORG_DPI_RedEMA_A);
   Settings.DPI_RedEMA_B                = MathMax(1, Inp_RRM_ORG_DPI_RedEMA_B);
   Settings.DPI_RedEMA_C                = MathMax(1, Inp_RRM_ORG_DPI_RedEMA_C);
   Settings.DPI_RedEMA_D                = MathMax(1, Inp_RRM_ORG_DPI_RedEMA_D);
   Settings.DPI_DoubleSmoothFirst       = MathMax(1, Inp_RRM_ORG_DPI_DoubleSmoothFirst);
   Settings.DPI_DoubleSmoothSecond      = MathMax(1, Inp_RRM_ORG_DPI_DoubleSmoothSecond);
   Settings.DPI_UseCCIReset             = Inp_RRM_ORG_DPI_UseCCIReset;
   Settings.DPI_CCI_Period              = MathMax(1, Inp_RRM_ORG_DPI_CCI_Period);
   Settings.DPI_CCI_AppliedPrice        = (int)Inp_RRM_ORG_DPI_CCI_Price;
   Settings.DPI_UseGreenHist            = Inp_RRM_ORG_DPI_UseGreenHist;
    Settings.DPI_HistMomentumThreshold   = Inp_RRM_ORG_DPI_HistMomentumThreshold;
    Settings.DPI_HistDecelLookback       = MathMax(1, MathMin(9, Inp_RRM_ORG_DPI_HistDecelLookback));
    Settings.DPI_HistTrackingEnabled     = Inp_RRM_ORG_DPI_HistTrackingEnabled;
    Settings.DPI_BlockOnDeceleration     = Inp_RRM_ORG_DPI_BlockOnDeceleration;
    Settings.DPI_ExitOnHistDisappear     = Inp_RRM_ORG_DPI_ExitOnHistDisappear;
    Settings.DPI_ExitThreshold           = MathMax(0.0, Inp_RRM_ORG_DPI_ExitThreshold);
    // DPI CCI Reset-Recovery
    Settings.DPI_RequireResetRecovery    = Inp_RRM_ORG_DPI_RequireResetRecovery;
    Settings.DPI_ResetRecoveryBars       = MathMax(0, Inp_RRM_ORG_DPI_ResetRecoveryBars);
    Settings.DPI_ResetRequireGreen       = Inp_RRM_ORG_DPI_ResetRequireGreen;
    // Choppiness Index
    Settings.CI_Period             = MathMax(5, Inp_CUSTOM_Ind_CI_Period);
    Settings.CI_RangingThreshold   = MathMax(0.0, Inp_CUSTOM_Ind_CI_RangingThreshold);

   // VRC
   Settings.VRC_ATR_Period        = MathMax(1, Inp_CUSTOM_Ind_VRC_ATR_Period);
   Settings.VRC_Lookback          = MathMax(10, Inp_CUSTOM_Ind_VRC_Lookback);
   Settings.VRC_LowThreshold      = MathMax(0.0, MathMin(100.0, Inp_CUSTOM_Ind_VRC_LowThreshold));

   // Exits
   Settings.SL_FixedPips         = Inp_CUSTOM_SL_FixedPips;
   Settings.SL_MinPips           = MathMax(0.0, Inp_CUSTOM_SL_MinPips);
   Settings.SL_WidenToMinimum    = Inp_CUSTOM_SL_WidenToMinimum;
   Settings.SLMode               = Inp_CUSTOM_SLMode;
   Settings.TPMode               = Inp_CUSTOM_TPMode;
   Settings.FixedTPPips          = Inp_CUSTOM_FixedTPPips;
   Settings.SLPercent            = Inp_CUSTOM_SLPercent;
   Settings.SL_AtrPeriod         = Inp_CUSTOM_SL_AtrPeriod;   // CUSTOM: user-controlled; overridden by TI/RRM/RRM_ORG preset blocks
   Settings.SL_AtrMult           = Inp_CUSTOM_SL_AtrMult;     // CUSTOM: user-controlled; overridden by TI/RRM/RRM_ORG preset blocks
   Settings.RRRatio              = Inp_CUSTOM_RRRatio;
   Settings.SwingLookback        = Inp_CUSTOM_SwingLookback;
   Settings.FractalPeriod        = Inp_CUSTOM_FractalPeriod;
   Settings.TPFractalOffset      = Inp_CUSTOM_TPFractalOffset;
   Settings.ShowSwingMarkers     = Inp_CUSTOM_ShowSwingMarkers;
   Settings.ShowFractalMarkers   = Inp_CUSTOM_ShowFractalMarkers;
   Settings.MarkerLookback       = MathMax(0, Inp_CUSTOM_MarkerLookback);
   Settings.ShowMarkerLabels     = Inp_CUSTOM_ShowMarkerLabels;
   Settings.SwingHighColor       = Inp_CUSTOM_SwingHighColor;
   Settings.SwingLowColor        = Inp_CUSTOM_SwingLowColor;
   Settings.SwingMarkerSize      = MathMax(1, MathMin(5, Inp_CUSTOM_SwingMarkerSize));
   Settings.FractalHighColor     = Inp_CUSTOM_FractalHighColor;
   Settings.FractalLowColor      = Inp_CUSTOM_FractalLowColor;
   Settings.FractalMarkerSize    = MathMax(1, MathMin(5, Inp_CUSTOM_FractalMarkerSize));

   Settings.TrailTrigger         = Inp_CUSTOM_TrailTrigger;
   Settings.TrailDistancePips    = Inp_CUSTOM_TrailDistancePips;
   Settings.BEThresholdPips      = Inp_CUSTOM_BEThresholdPips;
   Settings.TrailProfitPercent   = Inp_CUSTOM_TrailProfitPercent;
   Settings.TrailProfitPercentLPR= 25.0;
   Settings.TrailStepPips        = Inp_CUSTOM_TrailStepPips;
   Settings.TrailLockProfit      = Inp_CUSTOM_TrailLockProfit;
   Settings.TP_Enabled           = Inp_CUSTOM_TP_Enabled;
   Settings.TrailMode            = Inp_CUSTOM_TrailMode;
   Settings.PSAR_TrailCushionMode   = PSAR_CUSHION_ATR; // default; overwritten by ApplyPreset
   Settings.PSAR_TrailCushionAtrPeriod = 14;  // default; overwritten by ApplyPreset
   Settings.PSAR_TrailCushionAtrMult   = 0.5; // default; overwritten by ApplyPreset
   Settings.PSAR_TrailCushionPct       = 0.0; // default; overwritten by ApplyPreset
   Settings.PSAR_TrailDelay         = 2;      // default; overwritten by ApplyPreset

   Settings.ExitProfile             = Inp_CUSTOM_ExitProfile;
   Settings.BE_Mode                 = Inp_CUSTOM_BE_Mode;
   Settings.RRM_BE_ProgressPct      = 50.0;   // default; overwritten by ApplyPreset
   Settings.RRM_BE_RMultiple        = 1.0;    // default; overwritten by ApplyPreset
   Settings.RRM_TrailPsarDotShift = 2;      // default; overwritten by ApplyPreset
   Settings.RRM_FreezeTrailOnFlip   = true;   // default; overwritten by ApplyPreset
   Settings.RRM_TrailStartsAfterBE  = false;  // default; overwritten by ApplyPreset

   Settings.Vote_EvalShift       = 1;
   Settings.Vote_AllowPsarFlip   = false;
   Settings.Vote_PsarFlipDelay   = (Inp_CUSTOM_Ind_PsarFlipDelay < -1) ? -1 : (Inp_CUSTOM_Ind_PsarFlipDelay > 10) ? 10 : Inp_CUSTOM_Ind_PsarFlipDelay;
   Settings.Vote_PsarFlipDelay_W = -99;  // P1: default = use global
   Settings.Vote_PsarFlipDelay_M = -99;  // P1: default = use global
   Settings.Vote_PsarFlipDelay_S = -99;  // P1: default = use global

   Settings.MaxTotalRisk            = MathMax(0.0, Inp_RM_MaxTotalRisk);
   Settings.MaxOpenTrades           = MathMax(0, Inp_RM_MaxOpenTrades);
   Settings.CountBEasZeroRisk       = true;
   Settings.MarginUsageLimit        = MathMax(0.0, Inp_RM_MarginUsageLimit);
   Settings.MinMarginLevel          = MathMax(0.0, Inp_RM_MinMarginLevel);
   Settings.UseAdaptiveRisk         = Inp_RM_UseAdaptiveRisk;
   Settings.AdaptiveRisk_M1         = MathMax(0.0, Inp_RM_AdaptiveRisk_M1);
   Settings.AdaptiveRisk_M5         = MathMax(0.0, Inp_RM_AdaptiveRisk_M5);
   Settings.AdaptiveRisk_M15Plus    = MathMax(0.0, Inp_RM_AdaptiveRisk_M15Plus);
   Settings.Override_SL_Cushion     = MathMax(0.0, Inp_RM_Override_SL_Cushion);
   Settings.Override_Trail_Cushion  = MathMax(0.0, Inp_RM_Override_Trail_Cushion);
   Settings.Override_BE_Cushion     = MathMax(0.0, Inp_RM_Override_BE_Cushion);
   Settings.UseMarginAdjustment     = Inp_RM_UseMarginAdjustment;
   Settings.MarginAdj_Gold          = MathMax(0.0, Inp_RM_MarginAdj_Gold);
   Settings.MarginAdj_Crypto        = MathMax(0.0, Inp_RM_MarginAdj_Crypto);
   Settings.MarginAdj_Exotic        = MathMax(0.0, Inp_RM_MarginAdj_Exotic);
   Settings.MarginAdj_JPY           = MathMax(0.0, Inp_RM_MarginAdj_JPY);
   Settings.EmergencyMarginLevel    = MathMax(0.0, Inp_RM_EmergencyMarginLevel);

   Settings.Adaptive.PairType          = Inp_Adaptive_PairType;
   Settings.Adaptive.Spread_Major      = Inp_Adaptive_Spread_Major;
   Settings.Adaptive.Spread_Minor      = Inp_Adaptive_Spread_Minor;
   Settings.Adaptive.Spread_Exotic     = Inp_Adaptive_Spread_Exotic;
   Settings.Adaptive.Spread_Gold       = Inp_Adaptive_Spread_Gold;
   Settings.Adaptive.Spread_Crypto     = Inp_Adaptive_Spread_Crypto;

   if(Settings.Adaptive.PairType == PAIR_TYPE_AUTO)
      Settings.Adaptive.PairType = DetectPairType(_Symbol);

   Settings.MaxSpread = GetAdaptiveSpreadLimit(Settings.Adaptive.PairType, Settings.Adaptive);

   Settings.PhaseDetectionEnabled        = Inp_CUSTOM_PhaseDetectionEnabled;
   Settings.BlockUnorderedPhase          = Inp_CUSTOM_BlockUnorderedPhase;
   Settings.BlockEmergingPhase           = Inp_CUSTOM_BlockEmergingPhase;
   Settings.RequireMinPhaseConfirm       = false;
   Settings.MinPhaseConfirmBars          = 0;
   
   Settings.Emerging_AllowWeakTrades     = true;
   Settings.Emerging_AllowMediumTrades   = true;
   Settings.Emerging_AllowStrongTrades   = true;
   Settings.Trending_AllowWeakTrades     = true;
   Settings.Trending_AllowMediumTrades   = true;
   Settings.Trending_AllowStrongTrades   = true;

    Settings.EnableLayerDetection         = Inp_CUSTOM_EnableLayerDetection;
    Settings.AllowLayer1_Entries          = true;
    Settings.AllowLayer2_Entries          = true;
    Settings.AllowLayer3_Entries          = true;
   Settings.RRM_EnableDrawdownProtection = false; // default; overwritten by ApplyPreset
   Settings.RRM_MaxConsecutiveLosses     = 4;     // default; overwritten by ApplyPreset
   Settings.RRM_MaxTradesPerDay          = 5;     // default; overwritten by ApplyPreset
   Settings.RRM_MaxDailyDrawdownPct      = 2.0;   // default; overwritten by ApplyPreset

   // Account-level safety guards (preset-independent; mapped here so they are
   // never cleared by preset overrides applied later in ApplyPreset()).
   Settings.Safety_MaxEquityDrawdownPct  = Inp_Safety_MaxEquityDrawdownPct;
   Settings.Safety_MinEquityFloor        = Inp_Safety_MinEquityFloor;
   Settings.Safety_MinRewardRiskRatio    = Inp_Safety_MinRewardRiskRatio;
   Settings.Safety_CountBEInAggregateRisk = Inp_Safety_CountBEInAggregateRisk;
   Settings.Safety_MaxPositionsPerDir    = MathMax(0, Inp_Safety_MaxPositionsPerDir);
   Settings.Safety_DelayTrailUntilR      = Inp_Safety_DelayTrailUntilR;
   Settings.Safety_TrailActivateR        = Inp_Safety_TrailActivateR;
   Settings.Safety_RequirePriorAtBEToAdd = Inp_Safety_RequirePriorAtBEToAdd;

    Settings.SlopeLookbackBars      = 1;
   Settings.LayerPullbackEnabled        = Inp_CUSTOM_LayerPullbackEnabled;
   Settings.LayerBaselineLookback       = 10;     // default; overwritten by ApplyPreset
   // Per-layer pullback-recovery defaults (seed for ALL presets so the shared
   // magnitude logic is safe; RRM_ORG/CUSTOM override these via ApplyPreset).
   Settings.LayerBaselineLookback_W     = 0;     // 0 = fall back to global lookback
   Settings.LayerBaselineLookback_M     = 0;
   Settings.LayerBaselineLookback_S     = 0;
   Settings.LayerPullbackRatio          = SEA_DEF_LAYER_PULLBACK_RATIO;
   Settings.LayerFlatRatio              = SEA_DEF_LAYER_FLAT_RATIO;
   Settings.LayerRecoveryRatio          = SEA_DEF_LAYER_RECOVERY_RATIO;
   Settings.LayerRecoveryRatio_W        = -1.0;  // -1 = use global
   Settings.LayerRecoveryRatio_M        = -1.0;
   Settings.LayerRecoveryRatio_S        = -1.0;
   Settings.LayerAllowReversalPullback  = SEA_DEF_LAYER_ALLOW_REVERSAL;

   // Climax guard: params are global; enable is OFF in the base so non-opted
   // presets are unaffected. RRM_ORG and CUSTOM opt in via ApplyPreset.
   Settings.ClimaxGuard_Enabled         = false;
   Settings.ClimaxGuard_Lookback        = MathMax(1, Inp_ClimaxGuard_Lookback);
   Settings.ClimaxGuard_ATRPeriod       = MathMax(1, Inp_ClimaxGuard_ATRPeriod);
   Settings.ClimaxGuard_BarATRMult      = MathMax(0.0, Inp_ClimaxGuard_BarATRMult);
   Settings.ClimaxGuard_MoveATRMult     = MathMax(0.0, Inp_ClimaxGuard_MoveATRMult);
   Settings.ClimaxGuard_ResetPullback   = Inp_ClimaxGuard_ResetPullback;

    // VPRR defaults (disabled — only RRM_ORG preset wires it on)
    Settings.VPRR_Enabled         = Inp_CUSTOM_VPRR_Enabled;
    Settings.VPRR_VolumeType      = (int)VPRR_VOL_AUTO;
    Settings.VPRR_RecoveryBars    = 3;
    Settings.VPRR_MinRecoveryBars = 2;
    Settings.VPRR_MinRatio        = 1.0;
    Settings.VPRR_ExternalSymbol  = "";

    // BarClose (bcX) settings
    Settings.BarClose_Enabled    = Inp_CUSTOM_BarClose_Enabled;
   Settings.BarClose_Mode       = Inp_CUSTOM_BarClose_Mode;
   Settings.BarClose_DefaultEMA = Inp_CUSTOM_BarClose_DefaultEMA;

   // Re-entry after breakeven: disabled by default; enabled by RRM presets
   Settings.AllowReEntryAfterBE = false;
   Settings.ReEntryLotScalePct  = 0;    // 0 = full size (default for CUSTOM; overridden by RRM/RRM_ORG/TI presets)

   // Post-trade cooldown: disabled by default; presets may override
   Settings.MinBarsAfterClose      = Inp_CUSTOM_MinBarsAfterClose;
   Settings.MinBarsAfterWeekendGap = MathMax(0, Inp_CUSTOM_MinBarsAfterWeekendGap);

   // Spread retry cap: kill carry after N consecutive spread-blocked bars (0=unlimited)
   Settings.MaxSpreadRetryBars    = Inp_VETO_MaxSpreadRetryBars;

   // EMA fan overextension filter: disabled by default (presets override)
   Settings.EmaFanFilterEnabled   = false;   // default; overwritten by ApplyPreset
   Settings.EmaFanMaxTotalPips    = 60.0;    // default; overwritten by ApplyPreset
   Settings.EmaFanMaxPct          = 0.0;     // default; overwritten by ApplyPreset

   // DPI momentum deceleration filter: disabled by default (presets override)
   Settings.DpiDecelFilterEnabled = Inp_RRM_ORG_DPI_Decel_Filter;

   // ── PHASE B: TE-side gates (user-configurable veto controls) ──
   Settings.TE_RecheckBarClose    = Inp_VETO_TE_RecheckBarClose;
   Settings.TE_BC_TolerancePips   = MathMax(0.0, Inp_VETO_TE_BC_TolerancePips);
   Settings.TE_OpenDelaySeconds   = Inp_VETO_TE_OpenDelaySeconds;
   Settings.TE_SpreadMedianTicks  = Inp_VETO_TE_SpreadMedianTicks;

   // ── PHASE B: Recovery-sensitivity tuning defaults (all off; PRESET_RRM_ORG may override) ──
   Settings.DPI_IgnoreCCIForVote  = false;
   Settings.DPI_AllowTransition    = true;
   Settings.Layer_SlopeTolerance  = 0.0;
   Settings.BarClose_PipTolerance = 0.0;
   Settings.BarClose_LookbackBars        = 3;    // Default; overridden by PRESET_RRM_ORG via Inp_RRM_ORG_BarClose_LookbackBars
   Settings.Require_Progressive_Momentum = true; // Default; overridden by PRESET_RRM_ORG via Inp_RRM_ORG_BarClose_Require_Progressive_Momentum
   Settings.DPI_Histogram_Growth_Boost   = true; // Default; overridden by PRESET_RRM_ORG via Inp_RRM_ORG_DPI_Histogram_Growth_Boost
   Settings.PSAR_FlipGraceBars    = 0;

   // === FINAL VALIDATION: BiasMode vs AutoStrat compatibility ===
   if(Settings.BiasEnabled && !ValidateBiasStratCombo(Settings.BiasMode, Settings.AutoStrat))
   {
      string msg = StringFormat(
         "[FATAL] Invalid BiasMode/AutoStrat combination!\n"
         "BiasMode=%s requires different AutoStrat than %s\n"
         "Valid combinations:\n"
         "  BIAS_1EMA    → STRAT_1EMA_SLOPE\n"
         "  BIAS_2EMA    → STRAT_2EMA_CROSS_EMA, STRAT_2EMA_CROSS_PRICE, or STRAT_2EMA_POSITION\n"
         "  BIAS_4EMA    → STRAT_4EMA_LAYER\n"
         "EA will use BIAS_MANUAL to prevent undefined behavior.",
         EnumToString(Settings.BiasMode),
         EnumToString(Settings.AutoStrat)
      );
      Print(msg);
      Alert(msg);

      // Force safe default
      Settings.BiasMode = BIAS_MANUAL;
      Settings.ManSide  = SIDE_BOTH;
   }
}

//+------------------------------------------------------------------+
//| INDICATOR REGISTRY SYSTEM                                        |
//+------------------------------------------------------------------+

