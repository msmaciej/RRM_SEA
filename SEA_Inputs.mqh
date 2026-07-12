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
input group "    🎯 PRESET SELECTOR (GLOBAL)";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input ulong     Inp_Global_MagicNum                = 12345;       // Magic number (trade identifier)
input EStrategyPreset Inp_Global_Preset            = PRESET_RRM_ORG;    // Strategy preset

input group " ";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "    💰 TRADE MANAGEMENT / RISK (GLOBAL)";
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
// input string   Inp_Step9_Ref2                   = "To adjust exits under a preset: edit individual Inp_<preset>_* inputs"; // STEP9 2026-06: was "use PRESET_CUSTOM mode"; CUSTOM preset retired
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
input group "    🌐 PAIR / SPREAD (GLOBAL)";
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
input double      Inp_Adaptive_Spread_Gold         = 20.0;           // Pair: Max spread gold/XAU (pips) // BUGFIX D1 2026-07: changed 6.0→20.0. XAUUSD spread on MetaQuotes demo (and IC Markets raw) is 12-18 pips at London+NY overlap. The 6.0-pip cap was activating the TE SPREAD VETO on every bar, blocking all XAUUSD TE execution regardless of TS signal quality. 20.0 allows entry up to typical peak-session spread; tighten to 15.0 on IC Markets raw once live spread data is available.
input double      Inp_Adaptive_Spread_Silver       = 150.0;          // Pair: Max spread silver/XAG (native XAG pips, pip=0.001) // ADD 2026-07: XAG/USD has digits=3, pip=$0.001; IC Markets spread ~$0.03-0.08 = 30-80 native pips. 150 is a permissive ceiling; tighten to 80 once average session spread is observed.
input double      Inp_Adaptive_Spread_Indices      = 20.0;           // Pair: Max spread indices (native index-points) // ADD 2026-07: DAX ~1-3 pts, NAS100 ~2-5 pts, US30 ~1-3 pts, SPX500 ~0.5-1 pt. 20 is a generous ceiling covering all major indices at peak spread; tighten per-instrument via the Inp_Adaptive_PairType override on each chart.
input double      Inp_Adaptive_Spread_Crypto       = 50.0;           // Pair: Max spread crypto (pips)
// input string   Inp_Adaptive_Note1               = "📝 Note: SL/TP cushions auto-adjust by timeframe (no input needed)";
// input string   Inp_Adaptive_Note2               = "📝 M15=5 pips, H1=10 pips, H4=20 pips (see GetTFBasedCushion)";

input group " ";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "    🛡️ SAFETY GUARDS (GLOBAL) — off by default";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
// These guards are preset-independent: they are NOT cleared by preset overrides,
// so they remain active under all presets (FPM/MA/RRM_ORG/TI/CUSTOM). All default to 0 = disabled,
// so enabling none reproduces existing backtest behavior exactly. STEP3 2026-06: was "PRESET_RRM/FPM/etc"; RRM removed.
input bool        Inp_Global_Safety_CountBEInAggregateRisk = false;         // SAFETY: Count BE positions toward MaxTotalRisk (closes pyramiding gap)
input int         Inp_Global_Safety_MaxPositionsPerDir    = 2;              // SAFETY: Max concurrent positions per direction (0=off)
input bool        Inp_Global_Safety_DelayTrailUntilR      = false;          // SAFETY: Delay trailing until open profit reaches R-multiple
input double      Inp_Global_Safety_TrailActivateR        = 0.0;            // SAFETY: R-multiple of profit before trailing engages (0=off)
input bool        Inp_Global_Safety_RequirePriorAtBEToAdd = false;          // SAFETY: New trade only if all ar BE+ open same-symbol positions are at BE+ (staged risk)
input double      Inp_Global_Safety_MaxEquityDrawdownPct  = 0.0;            // SAFETY: Pause new entries if peak→trough equity DD ≥ % (0=off)
input double      Inp_Global_Safety_MinEquityFloor        = 0.0;            // SAFETY: Pause new entries if equity ≤ absolute value (0=off)
input double      Inp_Global_Safety_MinRewardRiskRatio    = 0.0;            // SAFETY: Reject entries with TP:SL ratio below this (0=off)

input group " ";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "    🚫✅ VETO CONTROLS (GLOBAL)";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "╔════════════════════════════════════════════════════════╗";
input group "║   🚫 VETO: F FILTERS (SPREAD/TIME/NEWS)";
input group "╚════════════════════════════════════════════════════════╝";
input bool        Inp_Global_VETO_UseSpread               = false;          // Veto Spread: enable
input int         Inp_Global_VETO_MaxSpreadRetryBars      = 3;              // Veto Spread: retry bars (0=unlimited)
input double      Inp_Global_VETO_MaxSpread               = 3.0;            // Veto Spread: max pips
input group "╔════════════════════════════════════════════════════════╗";
input group "║   🚫 VETO: TIME";
input group "╚════════════════════════════════════════════════════════╝";
// ═══════════════════════════════════════════════════════════════════════
// TRADING HOURS FILTER
// EA only enters trades when the current broker-time hour falls inside at
// least one enabled session or custom window (OR logic across all active).
// Broker time is typically EET (UTC+2 winter / UTC+3 summer). Check your
// broker's server clock. All hours below are in that broker time.
//
// Named session defaults (EET):  London 09-17 · NY 14-22 · Asia 01-09
// Margin extends a session symmetrically: London + 2h margin → 07-19.
// Custom windows let you define any two arbitrary ranges, e.g. 08-12 + 16-21.
// ═══════════════════════════════════════════════════════════════════════
input bool   Inp_Session_Enabled          = true;   // Trading hours filter: true=only trade in enabled sessions | false=trade 24h
// London session
input bool   Inp_Session_London           = true;   // London session active (09:00–17:00 EET by default)
input int    Inp_Session_London_Margin    = 0;      // Extend London ±N hours: 0=exact 09-17 · 1→08-18 · 2→07-19
// New York session
input bool   Inp_Session_NY               = true;   // New York session active (14:00–22:00 EET by default)
input int    Inp_Session_NY_Margin        = 0;      // Extend NY ±N hours: 0=exact 14-22 · 1→13-23 · 2→12-24
// Asian session
input bool   Inp_Session_Asia             = false;  // Asian/Tokyo session active (01:00–09:00 EET by default)
input int    Inp_Session_Asia_Margin      = 0;      // Extend Asia ±N hours: 0=exact 01-09 · 1→00-10
// Custom windows — for non-standard hours, additive with named sessions above (OR logic)
input bool   Inp_Session_Win1             = false;  // Custom window 1 active (e.g. morning only: 08-12)
input int    Inp_Session_Win1_Start       = 8;      // Window 1 start hour (broker time, 0-23)
input int    Inp_Session_Win1_End         = 12;     // Window 1 end hour
input bool   Inp_Session_Win2             = false;  // Custom window 2 active (e.g. afternoon: 16-21)
input int    Inp_Session_Win2_Start       = 16;     // Window 2 start hour (broker time, 0-23)
input int    Inp_Session_Win2_End         = 21;     // Window 2 end hour
input group "╔════════════════════════════════════════════════════════╗";
input group "║   🚫 VETO: NEWS";
input group "╚════════════════════════════════════════════════════════╝";
input bool        Inp_Global_VETO_UseNews                 = false;          // Veto News: enable
input ENewsImpactLevel Inp_Global_VETO_NewsImpactFilter    = NEWS_IMPACT_MED_PLUS; // F-AUDIT 2026-06: which impact levels block (default MED+ = legacy hardcode)
input string      Inp_Global_VETO_NewsFile                = "calendar_statement.csv"; // Veto News: CSV filename
input int         Inp_Global_VETO_NewsPreMinutes          = 60;             // Veto News: block minutes before
input int         Inp_Global_VETO_NewsPostMinutes         = 60;             // Veto News: block minutes after
input group "╔════════════════════════════════════════════════════════╗";
input group "║   🚫 VETO: TE QUALITY GATES (ADVANCED)";
input group "╚════════════════════════════════════════════════════════╝";
input bool        Inp_Global_VETO_TE_RecheckBarClose      = false;          // Veto TE: re-check price drift vs Close[1]
input double      Inp_Global_VETO_TE_BC_TolerancePips     = 3.0;            // Veto TE: drift tolerance pips
input int         Inp_Global_VETO_TE_OpenDelaySeconds     = 0;              // Veto TE: open delay seconds (0=off)
input int         Inp_Global_VETO_TE_SpreadMedianTicks    = 0;              // Veto TE: spread median filter ticks (0=off)
input group "╔════════════════════════════════════════════════════════╗";
input group "║   🚫 VETO: MTF (Multi-Timeframe Confirmation)";
input group "╚════════════════════════════════════════════════════════╝";
input bool        Inp_Ind_MTF_Enabled              = false;           // Veto MTF: enable
input ENUM_TIMEFRAMES Inp_Global_MTF_TF1                  = PERIOD_M5;      // Veto MTF: TF1 (primary)
input ENUM_TIMEFRAMES Inp_Global_MTF_TF2                  = PERIOD_M15;     // Veto MTF: TF2 (PERIOD_CURRENT = single TF)
input int         Inp_Global_MTF_EMA_Fast                 = 20;             // Veto MTF: fast EMA period
input int         Inp_Global_MTF_EMA_Slow                 = 50;             // Veto MTF: slow EMA period
input bool        Inp_Global_MTF_RequirePhase             = true;           // Veto MTF: require trending phase
// F-AUDIT 2026-07: Inp_Global_MTF_StrictAlignment REMOVED. Dev comment at SEA_SignalEngine.mqh
// (near GetMTFBias) confirms: "MTF_StrictAlignment is retained for compatibility but the gate is
// strict-by-construction; the flag no longer relaxes it." See
// Readme/README_SEA_PARAMETER_MAPPING.md "Input Surface Audit".
input group "╔════════════════════════════════════════════════════════╗";
input group "║   🚫 VETO: Climax";
input group "╚════════════════════════════════════════════════════════╝";
// ── CLIMAX / EXHAUSTION GUARD (global; blocks late entries into over-extended impulses) ──
input int         Inp_Global_ClimaxGuard_Lookback         = 13;              // Climax: window (bars) scanned for an impulse
input int         Inp_Global_ClimaxGuard_ATRPeriod        = 14;             // Climax: ATR baseline period (measured pre-impulse)
input double      Inp_Global_ClimaxGuard_BarATRMult       = 2.0;            // Climax: single-bar range threshold (x ATR)
input double      Inp_Global_ClimaxGuard_MoveATRMult      = 3.0;            // Climax: cumulative move threshold (x ATR)
input bool        Inp_Global_ClimaxGuard_ResetPullback    = false;           // Climax: on detection reset ALL layer PB states

input group "╔════════════════════════════════════════════════════════╗";
input group "║   🚫 F-FILTERS (GLOBAL MASTERS — preset-agnostic)";
input group "╚════════════════════════════════════════════════════════╝";
// F-AUDIT 2026-06: master enable switches for the F-factor sub-filters. Globalized so any
// preset can opt in/out independently of strategy choice. Tuning sub-params (EmaFan*Pips,
// PriceExt*, ClimaxGuard_*) remain where they are (preset-tuned or already global).
input bool        Inp_Global_F_EmaFanFilterEnabled        = false;          // F-Filter: EMA-fan over-extension master toggle
input bool        Inp_Global_F_PriceExtFilterEnabled      = false;          // F-Filter: price-vs-EMA over-extension master toggle
input bool        Inp_Global_F_DpiDecelFilterEnabled      = false;          // F-Filter: DPI GREEN deceleration master toggle (stateless)
input bool        Inp_Global_F_DPI_HistTrackingEnabled    = false;          // F-Filter: DPI histogram tracking master (prereq for hist-decel block)
input bool        Inp_Global_F_DPI_BlockOnDeceleration    = false;          // F-Filter: Block on DPI histogram decel (requires hist-tracking on)
input bool        Inp_Global_F_ClimaxGuard_Enabled        = false;          // F-Filter: Climax / exhaustion-guard master toggle

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
input bool        Inp_UI_ShowSwingMarkers      = false;          // UI Viz: Show Swing
input bool        Inp_UI_ShowFractalMarkers    = true;           // UI Viz: Show Fractal
input bool        Inp_UI_ShowMarkerLabels      = false;          // UI Viz: Show Labels
input int         Inp_UI_MarkerLookback        = 55;             // UI Viz: Bars (0 = all history)
input color       Inp_UI_SwingHighColor        = clrCrimson;     // UI Viz: Swing High color
input color       Inp_UI_SwingLowColor         = clrDodgerBlue;  // UI Viz: Swing Low color
input int         Inp_UI_SwingMarkerSize       = 1;              // UI Viz: Swing Marker (1-5)
input color       Inp_UI_FractalHighColor      = clrOrange;      // UI Viz: Fractal High color
input color       Inp_UI_FractalLowColor       = clrGray;        // UI Viz: Fractal Low color
input int         Inp_UI_FractalMarkerSize     = 1;              // UI Viz: Fractal marker (1-5)

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
// F-AUDIT 2026-07: Inp_Debug_Stats_TrackRejections / Inp_Debug_Stats_TrackPasses REMOVED — both
// fed proven-dead Settings fields; only Inp_Debug_Stats_FullEvaluation actually gates stats
// tracking. See Readme/README_SEA_PARAMETER_MAPPING.md "Input Surface Audit".
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
input group "    📐 PRESET_MA  (MT5 MA benchmark)";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "╔════════════════════════════════════════════════════════╗";
input group "║   🛑 MT5 Moving Average Benchmark (PRESET_MA)";
input group "╚════════════════════════════════════════════════════════╝";
input int         Inp_MA_Period                    = 12;             // MA period
input int         Inp_MA_Shift                     = 6;              // MA shift
// F-AUDIT 2026-07: Inp_MA_MaximumRiskPct / Inp_MA_DecreaseFactor REMOVED — Settings.MA_MaximumRiskPct
// and Settings.MA_DecreaseFactor (the fields SEA_TradeExecutor.mqh actually uses for MA-benchmark lot
// sizing) are hardcoded in InitializeConfig() and never touched by ApplyPreset() for any preset; these
// inputs were never read. Their defaults (0.02 / 3.0) coincidentally matched the hardcoded values,
// masking the disconnect. See Readme/README_SEA_PARAMETER_MAPPING.md "Input Surface Audit" section.
#endif // SEA_PRESET_MA

#ifdef SEA_PRESET_FPM
input group " ";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "    📐 PRESET_FPM";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 FPM: (TP) Take Profit Settings";
input group "╚════════════════════════════════════════════════════════╝";
input ETPMode     Inp_FPM_TPMode                   = TP_MODE_RR;     // FPM TP: TP mode — RR=derive from SL distance (recommended); FIXED_PIPS=TF cheat sheet pips
input double      Inp_FPM_RRRatio                  = 1.5;            // FPM TP: R:R ratio (used with TP_MODE_RR, e.g. 1.5, 2.0, 3.0)
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 FPM: (SL) Stop Loss Settings";
input group "╚════════════════════════════════════════════════════════╝";
// F-AUDIT 2026-07: Inp_FPM_SLMode REMOVED — never read since the STEP4 2026-06 fix
// (cfg.SLMode is hardcoded SL_MODE_SWING for FPM; see SEA_Presets.mqh, "SL: Hardcode
// SL_MODE_SWING — swing is the FPM methodology"). Re-wiring it would undo that fix.
// F-AUDIT 2026-07: Inp_FPM_SwingLookback REMOVED — never read since the same fix;
// GetFPMSwingLookback() (TF-aware helper) supplies SwingLookback instead.
// See Readme/README_SEA_PARAMETER_MAPPING.md "Input Surface Audit" section.
input double      Inp_FPM_SLFixedPips              = 15.0;           // FPM SL: fixed distance in pips (SL_MODE_FIXED_PIPS only — unreachable under FPM's current SWING lock; retained for TradeExecutor's general SL_MODE_FIXED_PIPS path)
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
// F-AUDIT 2026-07: Inp_FPM_Ind_SmaConverge_Enabled REMOVED — never read anywhere.
// Ind_SmaConverge_Enabled is hardcoded false in every preset block (SEA_Presets.mqh,
// see the FPM Condition 4 removal note there). A dead sweep target for FPM optimizers.
// See Readme/README_SEA_PARAMETER_MAPPING.md "Input Surface Audit" section.
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📊 FPM: MFI Volume Confirmation";
input group "╚════════════════════════════════════════════════════════╝";
input bool        Inp_FPM_Ind_Mfi_Enabled          = true;           // FPM MFI: Enable MFI volume gate (MFI>50 for longs, <50 for shorts)
input int         Inp_FPM_Mfi_Period               = 14;             // FPM MFI: period (default 14)
#endif // SEA_PRESET_FPM

// STEP3 2026-06: #ifdef SEA_PRESET_RRM_FAMILY guard removed.
// The "family" concept existed solely to share Inp_RRM_* between PRESET_RRM
// and PRESET_RRM_ORG. With PRESET_RRM gone, the family is just RRM_ORG.
//
// VPRR shared inputs (Inp_VPRR_*) and Inp_RRM_ORG_VPRR_* — used by CUSTOM,
// RRM_ORG, and TOPINVESTOR — are now UNCONDITIONAL (no #ifdef wrapping).
// This was a STRUCTURAL fix: prior code wrongly nested these inside the RRM
// family guard, meaning TI/CUSTOM users were silently disabled if neither
// RRM nor RRM_ORG was active.
//
// Inp_RRM_VPRR_* (4 RRM-only inputs) and the rest of PRESET_RRM inputs
// (~25 inputs across TP/SL/TS/BE/DP/Layer/Indicators sections) — all removed.
input group " ";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "    📊 VPRR — SHARED (all remaining presets: FPM / MA / RRM_ORG / TI)"; // STEP3 2026-06: removed PRESET_RRM mention | STEP9 2026-06: CUSTOM preset retired; relabeled to "all presets"
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "╔════════════════════════════════════════════════════════╗";
input group "    📊 VPRR (used by FPM / MA / RRM_ORG / TI presets)"; // STEP3 2026-06 | STEP9 2026-06: was "CUSTOM / RRM_ORG / TOPINVESTOR"; CUSTOM preset retired
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
// STEP3 2026-06: Inp_RRM_VPRR_* (4 inputs) removed — RRM-only, no longer needed.
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📊 VPRR RRM_ORG - Volume Confirmation";
input group "╚════════════════════════════════════════════════════════╝";
input EVPRRVolumeType Inp_RRM_ORG_VPRR_VolumeType  = VPRR_VOL_AUTO;  // RRM ORG VPRR: AUTO, EXTERNAL, REAL, TICK (Auto=real then tick fallback)
input bool        Inp_RRM_ORG_VPRR_AutoEnable      = false;           // RRM ORG VPRR: Auto-enable VPRR based on instrument type (ON=auto; OFF=use manual Enabled toggle below)
input bool        Inp_RRM_ORG_VPRR_Enabled         = false;          // RRM ORG VPRR: Manual enable (only used when AutoEnable=OFF)
input int         Inp_RRM_ORG_VPRR_RecoveryBars    = 5;              // RRM ORG VPRR: Default recovery bars (1-10); per-instrument overrides in shared block below

// STEP3 2026-06 FIX: 3 Inp_RRM_ORG_Allow* inputs were originally placed inside the
// "PRESET_RRM — LAYER WMS Filter" sub-group of the RRM_FAMILY block (HEAD lines 427-429)
// — visually grouped with RRM inputs but functionally RRM_ORG-specific. The Step 3 bulk
// deletion of the family block accidentally removed them too. Restored here.
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 RRM_ORG: LAYER WMS Filter";
input group "╚════════════════════════════════════════════════════════╝";
// F-AUDIT 2026-07: Inp_RRM_ORG_AllowWeak / AllowMedium / AllowStrong REMOVED — each fed only
// proven-dead Settings fields (Emerging_/Trending_Allow*Trades — see SEA_Presets.mqh). The real,
// live layer on/off controls are Inp_RRM_ORG_AllowLayerW/M/S just below (-> AllowLayer1/2/3_Entries,
// actually read by SEA_SignalEngine.mqh). These three looked like duplicates of that real control
// and were a live optimizer-sweep trap. See Readme/README_SEA_PARAMETER_MAPPING.md "Input Surface Audit".

// STEP3 2026-06: PRESET_RRM block (~25 inputs across TP/SL/TS/BE/DP/Layer/Indicators) removed.
// All inputs were RRM-only with no cross-preset reads (prior PRESET ISOLATION 2026-06 work
// already cleaned cross-preset leaks; this is the final physical removal).


#ifdef SEA_PRESET_RRM_ORG
input group " ";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "    📐 PRESET_RRM_ORG — DPI";
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
input bool        Inp_RRM_ORG_DPI_UseCCIReset            = false;     // RRM ORG DPI: CCI can reset ribbon color (trend filter)
input bool        Inp_RRM_ORG_DPI_IgnoreCCIForVote       = false;    // RRM ORG DPI: Skip CCI check — vote on raw histogram direction only
input bool        Inp_RRM_ORG_DPI_UseGreenHist           = false;     // RRM ORG DPI: Also require GREEN overlay for vote pass
// Theme5a 2026-06: DPI divergence sub-filter (mirrors Inp_RRM_ORG_MacdDiv pattern, off by default)
input bool        Inp_RRM_ORG_DpiDiv                     = false;     // RRM ORG DPI: Require price-vs-DPI-histogram divergence (off by default)
input int         Inp_RRM_ORG_DpiDivLookback             = 10;        // RRM ORG DPI: Divergence detection window in bars (two non-overlapping windows)
// Yellow ribbon = BUY vote, Red ribbon = SELL vote.
// CCI can reset ribbon color: hist>0 but CCI<0 → Red override (weakening).
//
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 RRM_ORG: DPI Pre-filter — GREEN Deceleration";
input group "╚════════════════════════════════════════════════════════╝";
// F-AUDIT 2026-06: 3 inputs removed (Inp_RRM_ORG_DPI_Decel_Filter, _DPI_BlockOnDeceleration,
// _DPI_HistTrackingEnabled). Toggles globalized to Inp_Global_F_DpiDecelFilterEnabled / Inp_Global_F_DPI_BlockOnDeceleration
// / Inp_Global_F_DPI_HistTrackingEnabled. Tuning params for DPI (CCI period, EMA periods, thresholds) stay here.
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
// F-AUDIT 2026-06: Inp_RRM_ORG_DPI_HistTrackingEnabled removed (see grouped removal note above)
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
input bool        Inp_RRM_ORG_DPI_RequireResetRecovery   = false;    // RRM ORG DPI: Require CCI reset→recovery cycle before entry  [SYNC 2026-06-04: true→false to match SignalScan, which never seeds this gate (zero-init=false). JUDGMENT CALL — see note.]
input bool        Inp_RRM_ORG_DPI_GrantFirstEntry        = true;     // RRM ORG DPI: Grant the FIRST trade of the session without waiting for a reset→recovery cycle (removes cold-start lockout; has no effect if RequireResetRecovery=false)
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
input group "    📐 PRESET_RRM_ORG  ★ ACTIVE";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 RRM_ORG: (TP) TAKE PROFIT TARGET";
input group "╚════════════════════════════════════════════════════════╝";
input ETPMode     Inp_RRM_ORG_TPMode               = TP_MODE_RR;     // RRM ORG TP: TP_MODE=*: *FIXED_PIPS, *FRACTAL, *NONE, *PSAR_FLIP, *RR
input double      Inp_RRM_ORG_RRRatio              = 2.5;             // RRM ORG TP: RR ratio — 2.5 = TP at 2.5× SL distance. Oracle: winners should outpace losers. Was 1.25 (negative expected value at 52% win rate).
//
// Inp_RRM_ORG_TPMode - Take profit mode:
// TP_MODE_FIXED_PIPS: TP at fixed pip distance
// TP_MODE_RR:         TP derived from SL distance × RR ratio (recommended)
// TP_MODE_FRACTAL:    TP at next fractal level
// TP_MODE_PSAR_FLIP:  No fixed TP, exit on PSAR flip
// TP_MODE_NONE:       No TP target, rely on trailing stop only (LPR mode)
//
// Inp_RRM_ORG_RRRatio - Risk:Reward ratio: TP distance = SL distance × RR
// Example: RR=2.5 and SL=20 pips → TP=50 pips
// Only used when TPMode = TP_MODE_RR
//
// ⚠️ TP vs trailing interaction:
// TPMode != TP_MODE_NONE → TP stays fixed, trailing runs underneath.
// TPMode == TP_MODE_NONE → no TP cap, trailing manages full exit.
//
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 RRM_ORG: (SL) INITIAL STOP LOSS PLACEMENT";
input group "╚════════════════════════════════════════════════════════╝";
// 2026-07: changed from SL_MODE_PSAR_DOT to SL_MODE_SWING.
// PSAR on M1/M5 sits 2-8 pips from price during consolidation → SL hit by spread + 1 tick of noise.
// XAUUSD was the ONLY profitable pair because its PSAR naturally lands 100-200 pips away.
// SWING SL places the stop under the most recent definable swing low (Oracle Stop Loss card).
// With lookback=13, M5 swing SL ≈ 12-25 pips FX / 150-300 pts XAU — above noise floor.
input ESLMode     Inp_RRM_ORG_SLMode               = SL_MODE_SWING;    // RRM ORG SL: SL_MODE_=*: *ATR, *FIXED_PIPS, *FRACTAL, *PERCENT, *PSAR_DOT, *SWING
input int         Inp_RRM_ORG_SwingLookback        = 34;              // RRM ORG SL: SWING lookback bars — search window for the most recent swing high/low. Larger window = more likely to find a structurally meaningful level. 34 bars: M1=34min · M5=170min · H1=34h. If swing is 15 bars ago and window=13, it's missed; window=34 finds it.
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
// 2026-07: changed from TRAIL_EMA to TRAIL_PSAR with TrailStartsAfterBE=true.
// TRAIL_EMA on M1/M5 trails too tightly — EMA hugs price and closes winners at ~0.5R before TP.
// TRAIL_PSAR after BE: PSAR only activates once BE is reached, letting the trade breathe to TP.
// Oracle trailing: "move stop loss as each new PSAR dot progresses past break-even level."
input ETrailingMode Inp_RRM_ORG_TrailMode             = TRAIL_PSAR;   // RRM ORG TS: *BREAKEVEN, *EMA, *FIXED_PIPS, *FRACTAL, *NONE, *PROFIT_PERCENT, *PSAR, *PSAR_FLIP_EXIT
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
input EEmaRole    Inp_RRM_ORG_TrailEMA_RibbonRole     = ROLE_EMA2;   // RRM ORG TS: which ribbon EMA to trail (EMA1=5,EMA2=13,EMA3=34,EMA4=89) when Period=0
input int         Inp_RRM_ORG_TrailEMA_Period         = 0;           // RRM ORG TS: EMA period (0=use ribbon role selector below)
input int         Inp_RRM_ORG_TrailEMA_Shift          = 1;           // RRM ORG TS: bar shift for EMA read (1=last closed bar, 2=two bars back, 3=three bars back)
input double      Inp_RRM_ORG_TrailEMA_CushionPips    = 0.0;         // RRM ORG TS: EMA trail cushion pips (0=use ATR mode)
input double      Inp_RRM_ORG_TrailEMA_CushionAtrMult = 0.1;         // RRM ORG TS: EMA cushion = ATR×this (0=disabled; 0.1=recommended)
input int         Inp_RRM_ORG_TrailEMA_CushionAtrPeriod = 14;        // RRM ORG TS: ATR period for EMA cushion
input ETrailTrigger Inp_RRM_ORG_TrailTrigger          = TRIGGER_IMMEDIATE; // RRM ORG TS: *BREAKEVEN, *IMMEDIATE, *PROFIT_PERCENT, *PROFIT_PIPS, *PSAR_ALIGN
input bool        Inp_RRM_ORG_TrailStartsAfterBE      = true;        // RRM ORG TS: PSAR trail activates only after BE is reached — lets trade breathe toward TP before trailing takes over
input bool        Inp_RRM_ORG_TrailLockProfit         = true;        // RRM ORG TS: never move SL backwards (lock profit)
input double      Inp_RRM_ORG_TrailStepPips           = 5.0;         // RRM ORG TS: step size for fixed-step trail modes
// PRESET ISOLATION 2026-06: dedicated RRM_ORG freeze-on-flip input
// (previously RRM_ORG block read Inp_RRM_FreezeTrailOnFlip — an RRM-preset input).
input bool        Inp_RRM_ORG_FreezeTrailOnFlip       = true;        // RRM ORG TS: FREEZE trail on PSAR flip (pause SL moves until corrected)
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
input EBeMode     Inp_RRM_ORG_BE_Mode                 = BE_MODE_R_MULTIPLE;  // RRM ORG BE: Breakeven trigger mode
input double      Inp_RRM_ORG_BE_RMultiple            = 0.7;         // RRM ORG BE: BE trigger as R multiple
input double      Inp_RRM_ORG_BE_ProgressPct          = 70.0;        // RRM ORG BE: BE trigger as TP progress %
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
input bool        Inp_RRM_ORG_RequireRecoveryIntraday = false;        // RRM ORG QA: Require recovery <M15
input bool        Inp_RRM_ORG_HtfFilter            = false;           // RRM ORG QA: HTF Trend Filter
input bool        Inp_RRM_ORG_MTF_RequirePhase     = false;           // RRM ORG QA: HTF slope-confirm (both EMAs must slope with position; blocks 'drifting' HTFs)
// F-AUDIT 2026-06: Inp_RRM_ORG_ClimaxGuard_Enabled removed — toggle globalized to Inp_Global_F_ClimaxGuard_Enabled
input int         Inp_RRM_ORG_Ema1Period           = 5;              // RRM ORG QA: EMA1 period
input int         Inp_RRM_ORG_Ema2Period           = 13;             // RRM ORG QA: EMA2 period
input int         Inp_RRM_ORG_Ema3Period           = 34;             // RRM ORG QA: EMA3 period
input int         Inp_RRM_ORG_Ema4Period           = 89;             // RRM ORG QA: EMA4 period
input int         Inp_RRM_ORG_PhaseConfirmM5       = 0;              // RRM ORG QA: PhaseConfirmBars <M5
input int         Inp_RRM_ORG_PhaseConfirmM30      = 0;              // RRM ORG QA: PhaseConfirmBars <M30
input int         Inp_RRM_ORG_PhaseConfirmH1plus   = 0;              // RRM ORG QA: PhaseConfirmBars H1+
input int         Inp_RRM_ORG_MinBarsAfterUNOExit  = 0;              // RRM ORG QA: Min bars after UNO exit before any layer DETECTED→RECOVERED transition is allowed (0=disabled; try 2-3 for M1)
input int         Inp_RRM_ORG_UNO_ToleranceBars    = 2;              // RRM ORG PB: consecutive UNO bars tolerated before layer states are wiped. A transient UNO flicker that resolves back to the SAME direction within this many bars PRESERVES DETECTED/RECOVERED (0=strict: reset on the first UNO bar)
input bool        Inp_RRM_ORG_LayerS_TMOnly        = false;          // RRM ORG QA: Restrict LayerS (EMA3/EMA4) entries to TRENDING phase only (per canonical RRM); false=legacy (LayerS allowed in EM+TM)
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 RRM_ORG: LAYER WMS Pullback & Recovery";
input group "╚════════════════════════════════════════════════════════╝";
input bool        Inp_RRM_ORG_LayerPBEnabled       = true;           // RRM ORG PB: Enable pullback-recovery state machine (P2?)
input int         Inp_RRM_ORG_LayerPBLookback      = 21;              // RRM ORG PB: Global baseline lookback (fallback; per-layer below)
input int         Inp_RRM_ORG_LayerPBLookback_W    = 13;            // RRM ORG PB: LayerW baseline lookback (fast/responsive) // NOTE 2026-07: original value. Longer lookback = cleaner baseline (less contaminated by in-progress pullback bars) = lower effective ratio = easier pullback detection. Shorter lookbacks counter-intuitively harm detection.
input int         Inp_RRM_ORG_LayerPBLookback_M    = 21;            // RRM ORG PB: LayerM baseline lookback (medium) // NOTE 2026-07: original value restored.
input int         Inp_RRM_ORG_LayerPBLookback_S    = 34;            // RRM ORG PB: LayerS baseline lookback (slow/stable) // NOTE 2026-07: original value restored. At LB_S=34, a 40%-deep pullback lasting 12 bars still produces ratio=0.507 vs 0.65 threshold = DETECTED. At LB_S=21, same pullback produces ratio=0.609 = DETECTED. At LB_S=8, ratio=N/A (window exhausted by pullback alone).
// F-AUDIT 2026-07 (round 2): Inp_RRM_ORG_LayerPBPullbackRatio REMOVED -- fed LayerPullbackRatio_Legacy,
// a proven dead sink (already documented in README_SEA_SIGNAL_REFERENCE.md / README_SEA_TRADE_LOGIC.md /
// README_SEA_PRESETS.md as inert under the Path-2 slope model). This input had an extensive tuning
// history in its old comment (0.50->0.65 "for sensitivity") that was already meaningless by the time
// it was written -- the exact optimizer-sweep trap this audit exists to catch. See
// Readme/README_SEA_PARAMETER_MAPPING.md "Input Surface Audit".
// F-AUDIT 2026-07 (round 2): Inp_RRM_ORG_LayerPBRecoveryRatio REMOVED -- fed LayerRecoveryRatio,
// a proven dead sink. Traced: GetLayerRecovery() -> UpdateSingleLayerPullback()'s recovery_ratio
// parameter, which the function's own comment says is "no longer consulted" -- only reaches a
// debug log string. See Readme/README_SEA_PARAMETER_MAPPING.md "Input Surface Audit".
// F-AUDIT 2026-07: Inp_RRM_ORG_LayerPB_RecoveryOnSlope REMOVED — fed Settings.LayerRecoveryOnSlope,
// a proven dead sink (never read). See Readme/README_SEA_PARAMETER_MAPPING.md "Input Surface Audit".
input double      Inp_RRM_ORG_LayerPBFlatRatio     = 0.1;      // RRM ORG PB: Flat threshold (|ratio|<this = flat)
input bool        Inp_RRM_ORG_LayerPBAllowReversal = true;  // RRM ORG PB: Count slope reversal as pullback // NOTE 2026-07: already true (correct). This is the ONLY mechanism that detects shallow pullbacks (EMA decelerating to 60-80% of baseline pace) because their magnitude ratio stays above 0.65 regardless of threshold. When EMA direction reverses even briefly (current_bullish != baseline_bullish), is_pullback fires regardless of ratio. Critical for M5/M15 trending pullbacks where EMA5 barely decelerates before recovering.
// S2 2026-07: price-zone DETECTED gate. zone = EMA_slow + (1-PullbackRatio)*(EMA_fast-EMA_slow).
// Path 2 (2026-07): the layer model is pure position+slope. Price-touch mixes a
// PRICE test into pullback detection and is DISABLED by default. The input is
// retained for back-compat only; leaving it true has no effect (the S2 gate code
// was removed from UpdateSingleLayerPullback).
input bool        Inp_RRM_ORG_LayerPriceTouchEnabled = false; // RRM ORG PB: (deprecated/no-op) price-zone touch — off under the slope model
// A21: minimum bars in DETECTED before RECOVERED is allowed. Path 2: a pullback
// cannot complete in one bar, so the floor is 2 on every layer/timeframe.
input int         Inp_RRM_ORG_MinPBBars_W   = 2;            // RRM ORG PB: A21 - LayerW min bars in DETECTED before RECOVERED (2/2/2 default)
input int         Inp_RRM_ORG_MinPBBars_M   = 2;            // RRM ORG PB: A21 - LayerM min bars in DETECTED before RECOVERED (2/2/2 default)
input int         Inp_RRM_ORG_MinPBBars_S   = 2;            // RRM ORG PB: A21 - LayerS min bars in DETECTED before RECOVERED (2/2/2 default)
// F-AUDIT 2026-07 (round 2): Inp_RRM_ORG_RecoveryRatio_W/M/S REMOVED -- same proven-dead sink
// as Inp_RRM_ORG_LayerPBRecoveryRatio above (LayerRecoveryRatio_W/M/S, unused-in-decision-logic
// trace). See Readme/README_SEA_PARAMETER_MAPPING.md "Input Surface Audit".
// Path 2 (2026-07): pullback OBSERVATION WINDOW (distinct from the baseline slope
// lookback 13/21/34). Bounds how long a RECOVERED layer stays entry-eligible before
// it is treated as stale (the "not-too-late" cap). Per-layer; 0 = use the global.
input int         Inp_RRM_ORG_LayerPullbackWindow_W = 21;         // RRM ORG PB: LayerW observation window (bars; 0=use global)
input int         Inp_RRM_ORG_LayerPullbackWindow_M = 34;         // RRM ORG PB: LayerM observation window (bars; 0=use global)
input int         Inp_RRM_ORG_LayerPullbackWindow_S = 55;         // RRM ORG PB: LayerS observation window (bars; 0=use global)
input int         Inp_RRM_ORG_LayerPullbackWindow   = 0;          // RRM ORG PB: GLOBAL observation-window override (bars; 0=disabled, use per-layer)
input bool        Inp_RRM_ORG_LayerRecoveryMaxAgeEnabled = true;  // RRM ORG PB: expire a RECOVERED layer that has waited > its observation window to fire (prevents stale chase-entries)
input bool        Inp_RRM_ORG_AllowLayerS          = true;                          // RRM ORG PB: allow Layer S (EMA3/4) entries
input bool        Inp_RRM_ORG_AllowLayerM          = true;                          // RRM ORG PB: allow Layer M (EMA2/3) entries
input bool        Inp_RRM_ORG_AllowLayerW          = true;                          // RRM ORG PB: allow Layer W (EMA1/2) entries
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 RRM_ORG: EMA Fan Filter (pips)";
input group "╚════════════════════════════════════════════════════════╝";
// F-AUDIT 2026-06: Inp_RRM_ORG_EmaFanFilter removed — toggle globalized to Inp_Global_F_EmaFanFilterEnabled
input double      Inp_RRM_ORG_EmaFan_M5Pips        = 25.0;           // RRM ORG Fan: pips <M5
input double      Inp_RRM_ORG_EmaFan_M30Pips       = 40.0;           // RRM ORG Fan: pips <M30
input double      Inp_RRM_ORG_EmaFan_H1Pips        = 60.0;           // RRM ORG Fan: pips H1
input double      Inp_RRM_ORG_EmaFan_H4Pips        = 100.0;          // RRM ORG Fan: pips H4
input double      Inp_RRM_ORG_EmaFan_DailyPips     = 180.0;          // RRM ORG Fan: pips D1+
input double      Inp_RRM_ORG_EmaFan_MaxPct        = 0.0;            // RRM ORG Fan: max gap % of price (>0 overrides pips; universal for all instruments)
// F-AUDIT 2026-06: Inp_RRM_ORG_PriceExtFilter removed — toggle globalized to Inp_Global_F_PriceExtFilterEnabled
input int         Inp_RRM_ORG_PriceExtRefEma       = 3;              // RRM ORG OverExt: ref EMA 1..4 (1=5 2=13 3=34 4=89)
input double      Inp_RRM_ORG_PriceExtMaxATR       = 2.5;            // RRM ORG OverExt: block if |close-refEMA| > this x ATR
input int         Inp_RRM_ORG_PriceExtAtrPeriod    = 14;             // RRM ORG OverExt: ATR period for distance
input double      Inp_RRM_ORG_JpyGateMultiplier    = 1.3;            // RRM ORG Fan: JPY Gate Multiplier (1.0=disabled)

input group " ";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "    📐 PRESET_RRM_ORG — INDICATORS";
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
input int         Inp_RRM_ORG_Adx_PercentileRefreshSec = 14400;      // RRM ORG ADX: DYNAMIC_PERCENTILE refresh interval (sec). M1 chart: try 900 (15min); H1+: 14400 (4h)
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
input int         Inp_RRM_ORG_CandleBody_AvgPeriod    = 14;          // RRM ORG CBody: CBody Average period       [SYNC 2026-06-04: 5→14 to match SignalScan CB_AvgPeriod]
input int         Inp_RRM_ORG_CandleBody_CheckBars    = 1;           // RRM ORG CBody: CBody Bars to check        [SYNC 2026-06-04: 3→1 to match SignalScan CB_CheckBars (inert — engine no longer uses CheckBars in ATR spike test)]
input double      Inp_RRM_ORG_CandleBody_MaxMult      = 3.0;         // RRM ORG CBody: CBody Max multiplier       [SYNC 2026-06-04: 4.0→3.0 to match SignalScan CB_MaxMult]
input double      Inp_RRM_ORG_CandleBody_MinCloseRatio = 0.0;        // RRM ORG CBody: Min close ratio (0=off, 0.75=TopInvestor — rejects doji-like signal bars)
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
input int         Inp_RRM_ORG_CciPeriod            = 20;             // RRM ORG CCI: CCI Period   [SYNC 2026-06-04: 14→20 to match SignalScan CCI_Period (inert — standalone CCI voter OFF on both sides; parity only)]
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 RRM_ORG: CI Settings";
input group "╚════════════════════════════════════════════════════════╝";
input int         Inp_RRM_ORG_CiPeriod             = 14;             // RRM ORG CI: CI Period
input double      Inp_RRM_ORG_CiRangingThreshold   = 61.8;           // RRM ORG CI: CI Threshold
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 RRM_ORG: MACD Settings";
input group "╚════════════════════════════════════════════════════════╝";
// F-AUDIT 2026-07: Inp_RRM_ORG_MacdMode REMOVED — never referenced anywhere outside its
// own declaration. Settings.MacdVoteMode (the field SEA_SignalEngine.mqh actually
// switches on) is hardcoded MACD_HISTOGRAM per-preset in SEA_Presets.mqh; this input's
// default happened to match, masking the disconnect. See Readme/README_SEA_PARAMETER_MAPPING.md
// "Input Surface Audit" section.
input bool        Inp_RRM_ORG_MacdSlope            = false;          // RRM ORG MACD: MACD require SLO
input bool        Inp_RRM_ORG_MacdDiv              = false;          // RRM ORG MACD: BLOCK entry on MACD trend-exhaustion divergence (price HH but MACD LH for LONG; mirror for SHORT)
input int         Inp_RRM_ORG_MacdDivLookback      = 10;             // RRM ORG MACD: Divergence detection window in bars (two non-overlapping windows of this size)
input int         Inp_RRM_ORG_MacdFast             = 8;              // RRM ORG MACD: MACD Fast
input int         Inp_RRM_ORG_MacdSlow             = 13;             // RRM ORG MACD: MACD Slow
input int         Inp_RRM_ORG_MacdSig              = 5;              // RRM ORG MACD: MACD Signal
input int         Inp_RRM_ORG_MacdFreshBars        = 3;              // RRM ORG MACD: max bars since last zero-cross to be "fresh"
input double      Inp_RRM_ORG_MacdSlopeMin         = 0.00001;        // RRM ORG MACD: minimum histogram slope magnitude
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 RRM_ORG: MFI Settings";
input group "╚════════════════════════════════════════════════════════╝";
// F-AUDIT 2026-07: Inp_RRM_ORG_Mfi_Mode REMOVED — fed Settings.MfiMode, a proven dead sink;
// Check_MFI() never branches on it. See Readme/README_SEA_PARAMETER_MAPPING.md "Input Surface Audit".
input int         Inp_RRM_ORG_Mfi_Period           = 14;             // RRM ORG MFI: MFI Period
input double      Inp_RRM_ORG_Mfi_OB               = 80.0;           // RRM ORG MFI: MFI Overbought
input double      Inp_RRM_ORG_Mfi_OS               = 20.0;           // RRM ORG MFI: MFI Oversold
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 RRM_ORG: PSAR Settings";
input group "╚════════════════════════════════════════════════════════╝";
input bool        Inp_RRM_ORG_Vote_AllowPsarFlip   = true;          // RRM ORG PSAR: PSAR Enable Flip   [SYNC 2026-06-04: true→false to match SignalScan TS_PSAR_Flip=false (PSAR votes on dot position only, no flip window)]
input int         Inp_RRM_ORG_Vote_PsarFlipDelay   = -1;             // RRM ORG PSAR: PSAR Flip delay (-1=persistent, 0-10=bars after flip) // BUGFIX A1 2026-07: changed 5→-1. Default 5 expired the PSAR vote after 25 min on M5, blocking every bar in a sustained trend after the initial flip. Persistent mode (dot-position check only) allows entry at any bar where the PSAR dot is on the correct side, regardless of when the last flip occurred. Use per-layer overrides below to restore time-gating on specific layers.
input int         Inp_RRM_ORG_TrailPsarDotShift    = 1;              // RRM ORG QA: PSAR trail shift (1–3 bars back)
input int         Inp_RRM_ORG_PsarFlipDelay_W      = 5;              // RRM ORG PSAR: PSAR Flip delay LayerW override (-99=use global, 0=flip bar, 1-10=window) // BUGFIX A1 2026-07: changed -99→5. LayerW (EMA1/2 pair) is the fastest layer and most susceptible to whipsaw entries immediately after a trend re-entry; the 5-bar window provides a minimal freshness gate. Overrides the global -1 for this layer only.
input int         Inp_RRM_ORG_PsarFlipDelay_M      = -1;             // RRM ORG PSAR: PSAR Flip delay LayerM override (-99=use global, 0=flip bar, 1-10=window) // BUGFIX A1 2026-07: changed -99→-1. LayerM (EMA2/3) entries confirmed by EMA13/34 structural alignment; persistent dot-position check is sufficient. Allows entries throughout the trend without requiring a fresh flip.
input int         Inp_RRM_ORG_PsarFlipDelay_S      = -1;             // RRM ORG PSAR: PSAR Flip delay LayerS override (-99=use global, 0=flip bar, 1-10=window) // BUGFIX A1 2026-07: changed -99→-1. LayerS (EMA3/4) is the slowest, highest-conviction layer; a time-based flip gate adds no structural filtering value. Persistent mode.
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
input int         Inp_RRM_ORG_VRC_RefreshSec       = 14400;          // RRM ORG VRC: percentile refresh interval (sec). M1: try 900; H1+: 14400 (4h)
// F-AUDIT 2026-07: Inp_RRM_ORG_VRC_ATR_Period REMOVED — fed Settings.VRC_ATR_Period, a proven
// dead sink; VRC's shared ATR handle actually uses Settings.P_Atr. See
// Readme/README_SEA_PARAMETER_MAPPING.md "Input Surface Audit".
#endif // SEA_PRESET_RRM_ORG

#ifdef SEA_PRESET_TOPINVESTOR
input group " ";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "    📐 PRESET_TOPINVESTOR";
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
// PRESET ISOLATION 2026-06: dedicated TI trail-start input
// (previously TI block did not set RRM_TrailStartsAfterBE at all — it inherited
// the runtime-default value of false from SEA_Inputs.mqh:1626).
// Default preserved as false to match the inherited behavior.
input bool        Inp_TI_TrailStartsAfterBE        = false;          // TI Exit: Safety override: trail after BE
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 TOPINVESTOR: STANDARD — EMA Fan Filter";
input group "╚════════════════════════════════════════════════════════╝";
// F-AUDIT 2026-06: Inp_TI_EmaFanFilterEnabled removed — toggle globalized to Inp_Global_F_EmaFanFilterEnabled
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
input group "    📐 PRESET_TOPINVESTOR — PROFILES";
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
input int         Inp_TI_ADX_PercentileRefreshSec  = 14400;          // TI Con: DYNAMIC_PERCENTILE refresh interval (sec). M1: try 900 (15min); H1+: 14400 (4h)
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
input group "    ⚠️  ENGINE SEED DEFAULTS — SIGNAL (used by all presets unless overridden)"; // STEP9 2026-06: was "PRESET_CUSTOM — SIGNAL (user-built)"; CUSTOM preset retired in Step 4
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "    ▸ TS voters (B·P·F·L·I) — these are engine seed defaults; presets override most via SEA_Presets.mqh"; // STEP9 2026-06: was "only PRESET_CUSTOM edits these live"; CUSTOM preset retired in Step 4
input group "╔════════════════════════════════════════════════════════╗";
input group "║   🔧 STEP 1: BIAS (Major Trend Direction)";
input group "╚════════════════════════════════════════════════════════╝";
input EManualSide Inp_Global_ManualSide            = SIDE_BOTH;      // Override: Bias Side
input group "╔════════════════════════════════════════════════════════╗";
input group "║   🔧 STEP 2: MA | EMA";
input group "╚════════════════════════════════════════════════════════╝";
input group "╔════════════════════════════════════════════════════════╗";
input group "║   🔧 STEP 3: ENTRY Signal (Timing Strategy)";
input group "╚════════════════════════════════════════════════════════╝";
input group "╔════════════════════════════════════════════════════════╗";
input group "║   🔧 STEP 3b: PHASE / LAYER / VPRR (4-EMA Architecture)";
input group "╚════════════════════════════════════════════════════════╝";
input bool        Inp_Global_LayerPullbackEnabled  = false;          // Override: [LY] Enable layer pullback-recovery state machine
input bool        Inp_Global_LayerS_Require_DirAlign  = true;       // [LY] Require Layer S (EMA3/EMA4) pos+slope w/ bias to allow M/W entries
input bool        Inp_Global_Guard1_SkipFirstPostFlipPR = false;    // [LY] GUARD 1: after a bias flip, skip the FIRST completed pullback-recovery per layer (default OFF - under test)
input bool        Inp_Global_LayerReset_OnRealign      = false;      // [LY] Reset layer pullback states on confirmed market-phase change
input int         Inp_Global_LayerReset_PhaseConfirm   = 2;          // [LY]   ^ bars new phase must hold first (1=catch 1-bar phases)
// F-AUDIT 2026-06: Inp_CUSTOM_ClimaxGuard_Enabled removed — toggle globalized to Inp_Global_F_ClimaxGuard_Enabled
input bool        Inp_Global_VPRR_Enabled          = false;          // Override: [VP] Enable Volume Pullback-Recovery Ratio voter
// Theme3 2026-06: per-layer VPRR threshold overrides (0 = fall back to VPRR_MinRatio).
// Useful for tuning L1 (fast/noisy) stricter and L3 (slow/cleaner) looser. Defaults to 0
// for all three = no override = backward-compatible (existing VPRR_MinRatio applies to every layer).
input double      Inp_Global_VPRR_MinRatio_W       = 0.0;            // Override: [VP] LayerW (EMA1/EMA2) min ratio (0=use VPRR_MinRatio)
input double      Inp_Global_VPRR_MinRatio_M       = 0.0;            // Override: [VP] LayerM (EMA2/EMA3) min ratio (0=use VPRR_MinRatio)
input double      Inp_Global_VPRR_MinRatio_S       = 0.0;            // Override: [VP] LayerS (EMA3/EMA4) min ratio (0=use VPRR_MinRatio)
input group "╔════════════════════════════════════════════════════════╗";
input group "║   🔧 STEP 4: Candle Close & Candle Body";
input group "╚════════════════════════════════════════════════════════╝";
input group "╔════════════════════════════════════════════════════════╗";
input group "║   🔧 STEP 5: Pullback Gate";
input group "╚════════════════════════════════════════════════════════╝";
// Pullback gate uses pure distance comparison: the current EMA gap must exceed the prior EMA gap (no pip threshold).
input group "╔════════════════════════════════════════════════════════╗";
input group "║   🔧 STEP X: Trail EMA (engine seed defaults)"; // STEP9 2026-06: was "(PRESET_CUSTOM)"; CUSTOM preset retired in Step 4
input group "╚════════════════════════════════════════════════════════╝";
input int         Inp_Global_TrailEMA_Period       = 9;              // Override: [Trail] EMA period for TRAIL_EMA mode
input int         Inp_Global_TrailEMA_Shift        = 1;              // Override: [Trail] EMA shift (1=current bar, 2=one bar cushion)

// ── PRESET ISOLATION 2026-06: dedicated CUSTOM TM inputs ─────────────
// Previously CUSTOM block read Inp_RRM_ORG_* for these fields, which
// violated preset isolation (CUSTOM should not depend on RRM_ORG inputs).
// Defaults match the previously-leaked Inp_RRM_ORG_* defaults so behavior
// is unchanged for existing .set files that did not override them.

// ── PRESET ISOLATION 2026-06 (PART 2): non-TM CUSTOM inputs ──────────
// Previously CUSTOM block read 33 Inp_RRM_ORG_* inputs across HTF, MTF,
// EMA-fan, Phase, DPI, VPRR, JPY-gate, layer-recovery and drawdown
// protection. CUSTOM should be a standalone preset, not a RRM_ORG mirror.
// Each new Inp_CUSTOM_* default matches the previously-leaked Inp_RRM_ORG_*
// default — behavior is unchanged for existing .set files that did not
// override these inputs.
// F-AUDIT 2026-06: Inp_CUSTOM_EmaFanFilter removed — toggle globalized to Inp_Global_F_EmaFanFilterEnabled
// PRESET ISOLATION 2026-06 (Carry-over 2 / VRC): dedicated CUSTOM VRC inputs.
// Previously the CUSTOM block did not assign cfg.VRC_* at all — fields silently
// inherited from struct default or prior preset's leftover state. Defaults
// match the hardcoded values used by FPM/MA/TI/TEST for consistency.

input group " ";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "    ⚠️  ENGINE SEED DEFAULTS — INDICATORS"; // STEP9 2026-06: was "PRESET_CUSTOM — INDICATORS"; CUSTOM preset retired in Step 4
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📊 ADX (Average Directional Index - Strength of Market Trend)";
input group "╚════════════════════════════════════════════════════════╝";
input int         Inp_Global_Ind_Adx_PercentileRefreshSec = 14400;   // Ind [ADX]: DYNAMIC_PERCENTILE refresh interval (sec). M1: try 900 (15min); H1+: 14400 (4h)
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📊 ATR (Average True Range - Market Volatility - Non-directional)";
input group "╚════════════════════════════════════════════════════════╝";
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📊 BB (Bollinger Bands - Market Volatility and Over bought/sold Levels)";
input group "╚════════════════════════════════════════════════════════╝";
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📊 CBody (Candle Body - Votes Against Overextended Candles (news/spikes))";
input group "╚════════════════════════════════════════════════════════╝";
input double      Inp_Global_Ind_CandleBody_MinCloseRatio = 0.0;         // Ind [CBody]: Min close ratio (0=off, 0.75=TopInvestor)
input bool        Inp_Global_Ind_CandleBody_CarryOnOverext = true;       // Ind [CBody]: carry CB=0 over-ext until next layer pullback-recovery
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📊 CCI (Commodity Channel Index - Momentum Oscilator)";
input group "╚════════════════════════════════════════════════════════╝";
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📊 CI (Choppiness Index - Block Trades in Ranging Market)";
input group "╚════════════════════════════════════════════════════════╝";
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📊 Fib (Fibonacci Retracement Voter)";
input group "╚════════════════════════════════════════════════════════╝";
input bool        Inp_Global_Ind_Fib_Enabled       = false;          // Ind [Fib]: Enable
input double      Inp_Global_Ind_Fib_MinRetracement    = 0.38;           // Ind [Fib]: Min pullback depth
input double      Inp_Global_Ind_Fib_MaxRetracement    = 0.618;          // Ind [Fib]: Max pullback depth
input int         Inp_Global_Ind_Fib_SwingLookback     = 50;             // Ind [Fib]: Swing search bars
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📊 MACD (Moving Average Convergence Divergence - Trend-Following Momentum)";
input group "╚════════════════════════════════════════════════════════╝";
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📊 MFI (Money Flow Index - Oscillator Buying Selling Pressure)";
input group "╚════════════════════════════════════════════════════════╝";
input double      Inp_Global_Ind_Mfi_Level         = 50.0;           // Ind: TI Full: [MFI] Threshold/level
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📊 P123 (Mark Crisp 1-2-3 fractal breakout pattern (see Ross Hook))";
input group "╚════════════════════════════════════════════════════════╝";
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📊 PSAR (Parabolic Stop and Reverse - Trend-Following Indicator)";
input group "╚════════════════════════════════════════════════════════╝";
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📊 Ross Hook (Trend Momentum (see to P123))";
input group "╚════════════════════════════════════════════════════════╝";
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📊 RSI (Relative Strength Index - Monentum Oscilator)";
input group "╚════════════════════════════════════════════════════════╝";
input group "╔════════════════════════════=═══════════════════════════╗";
input group "║   📊 STO (Stochastic Oscillator - Momentum Potential Market Reversals)";
input group "╚════════════════════════════════════════════════════════╝";
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📊 VRC (Volatility Regime Classifier - Reject Trades in Low Volatility (quiet/choppy markets))";
input group "╚════════════════════════════════════════════════════════╝";

input group " ";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "    🎯 ENGINE SEED DEFAULTS — EXITS (TP / SL / TS / BE)"; // STEP9 2026-06: was "PRESET_CUSTOM — EXITS"; CUSTOM preset retired in Step 4
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "╔════════════════════════════════════════════════════════╗";
input group "║   🎯 (TP) TAKE PROFIT (engine seed defaults)"; // STEP9 2026-06: was "(CUSTOM only)"; CUSTOM preset retired
input group "╚════════════════════════════════════════════════════════╝";
input group "╔════════════════════════════════════════════════════════╗";
input group "║   🎯 EXIT PROFILES";
input group "╚════════════════════════════════════════════════════════╝";
// STEP2 2026-06: was "Active for: PRESET_TEST & PRESET_CUSTOM" — TEST removed; only CUSTOM uses direct exit-input control now.
// input string   Inp_Exit_Zone_Info1              = "Active for: PRESET_CUSTOM (direct input control)";
// input string   Inp_Exit_Zone_Info2              = "Other presets override exits with strategy-optimized values";
// input string   Inp_CUSTOM_ExitProfile_Info      = "RRM: Swing-based SL, PSAR trail, no ATR multipliers";
input group "╔════════════════════════════════════════════════════════╗";
input group "║   🛑 (SL) STOP LOSS (engine seed defaults)"; // STEP9 2026-06: was "(CUSTOM only)"; CUSTOM preset retired
input group "╚════════════════════════════════════════════════════════╝";
input bool        Inp_Global_SL_WidenToMinimum     = false;          // Custom: If true: widen to min.; if false: block TE
// input string   Inp_SL_Help1                     = "FIXED_PIPS: Simple pip distance";
// input string   Inp_SL_Help2                     = "MODE_SWING: Recent structure high/low";
// input string   Inp_SL_Help3                     = "PSAR_DOT: PSAR level  |  PERCENT: % of price  |  FRACTAL: Bill Williams";
// input string   Inp_SL_TFCushion_Note            = "PSAR/Swing cushions auto-set by timeframe (M15=5, H1=10, H4=20 pips)";
input double      Inp_Global_SL_FixedPips          = 20.0;           // Custom: SL distance (pips SL_MODE_FIXED_PIPS)
input double      Inp_Global_SL_MinPips            = 3.0;            // Custom: Min. SL pips (0 = no user floor, broker minimum still applies)
input int         Inp_Global_SL_AtrPeriod          = 14;             // Custom: ATR period (SL_MODE_ATR only)
input double      Inp_Global_SL_AtrMult            = 1.0;            // Custom: ATR multiplier — SL = swing_anchor − ATR×N (SL_MODE_ATR; 0.5–1.5 typical)
// input group "--- SL Configuration Examples ---";
// input string   Inp_Ex1_Header                   = "Example 1 - Simple Fixed SL: Inp_CUSTOM_SLMode=SL_MODE_FIXED_PIPS, Inp_Global_SL_FixedPips=20";
// input string   Inp_Ex2_Header                   = "Example 2 - Swing Structure: Inp_CUSTOM_SLMode=SL_MODE_SWING, Inp_CUSTOM_SwingLookback=20";
// input string   Inp_Ex3_Header                   = "Example 3 - Fractal SL:      Inp_CUSTOM_SLMode=SL_MODE_FRACTAL, Inp_CUSTOM_FractalPeriod=5, Inp_CUSTOM_TPFractalOffset=1";

input group "╔════════════════════════════════════════════════════════╗";
input group "║   🛑 (SL) STOP LOSS FRACTAL: used with SL_FRACTAL & SL_PSAR_DOT";
input group "╚════════════════════════════════════════════════════════╝";
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📈 (TS) TRAILING STOP (engine seed defaults)"; // STEP9 2026-06: was "(CUSTOM only)"; CUSTOM preset retired
input group "╚════════════════════════════════════════════════════════╝";
// PSAR trail cushion (used by CUSTOM preset when TrailMode=TRAIL_PSAR):
// PRESET ISOLATION 2026-06: Mult/Pct defaults updated from 0.5/0.04 → 1.0/25.0
// to match the previously-hardcoded values in the CUSTOM block (CUSTOM block now
// reads its own inputs; without this default change CUSTOM users would see a
// behavior shift when leaving the inputs at default). The previous 0.5/0.04
// defaults were dead — never reached the cfg struct.
// Trail trigger: % of RISK (R-multiple based)
// Examples: 50 = 0.5R, 100 = 1.0R, 150 = 1.5R
input group "╔════════════════════════════════════════════════════════╗";
input group "║   ⚖️ (BE) BREAK-EVEN (engine seed defaults)"; // STEP9 2026-06: was "(CUSTOM only)"; CUSTOM preset retired
input group "╚════════════════════════════════════════════════════════╝";
// input string   Inp_RRM_Info1                    = "RRM uses % of TP distance for BE — not absolute pips";
// input string   Inp_RRM_Info2                    = "Only active when ExitProfile = EXIT_PROFILE_RRM";
// input string   Inp_RRM_Info3                    = "Example: SL=10 pips, TP=30 pips (3:1 RR), BE@33% → triggers at +10 pips profit";
input group "╔════════════════════════════════════════════════════════╗";
input group "║   🛡 (TE) COOLDOWN BARS Post-Trade Protection";
input group "╚════════════════════════════════════════════════════════╝";
input int         Inp_Global_MinBarsAfterClose      = 2;             // Custom: TE: Min bars cooldown (0=off)
input int         Inp_Global_MinBarsAfterWeekendGap = 2;             // Custom: TS: Bars skip weekend gap (0=off, recommended 1-2)

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
   // Gold — must match before Silver to avoid XAG prefix collision
   if(StringFind(sym, "XAUUSD") >= 0) return PAIR_TYPE_GOLD;
   if(StringFind(sym, "GOLD")   >= 0) return PAIR_TYPE_GOLD;
   // Silver — ADD 2026-07
   if(StringFind(sym, "XAGUSD") >= 0) return PAIR_TYPE_SILVER;
   if(StringFind(sym, "XAG")    >= 0) return PAIR_TYPE_SILVER;
   if(StringFind(sym, "SILVER") >= 0) return PAIR_TYPE_SILVER;
   // US Equity Indices — ADD 2026-07
   if(StringFind(sym, "NAS")    >= 0) return PAIR_TYPE_INDICES;   // NAS100, NASDAQ
   if(StringFind(sym, "US100")  >= 0) return PAIR_TYPE_INDICES;
   if(StringFind(sym, "SPX")    >= 0) return PAIR_TYPE_INDICES;   // SPX500, SP500
   if(StringFind(sym, "SP500")  >= 0) return PAIR_TYPE_INDICES;
   if(StringFind(sym, "US30")   >= 0) return PAIR_TYPE_INDICES;   // Dow Jones
   if(StringFind(sym, "DJ30")   >= 0) return PAIR_TYPE_INDICES;
   if(StringFind(sym, "USTEC")  >= 0) return PAIR_TYPE_INDICES;
   // EU/UK Equity Indices — ADD 2026-07
   if(StringFind(sym, "DAX")    >= 0) return PAIR_TYPE_INDICES;   // DAX40/GER40
   if(StringFind(sym, "GER40")  >= 0) return PAIR_TYPE_INDICES;
   if(StringFind(sym, "FTSE")   >= 0) return PAIR_TYPE_INDICES;   // FTSE100/UK100
   if(StringFind(sym, "UK100")  >= 0) return PAIR_TYPE_INDICES;
   if(StringFind(sym, "CAC")    >= 0) return PAIR_TYPE_INDICES;   // CAC40/FRA40
   if(StringFind(sym, "FRA40")  >= 0) return PAIR_TYPE_INDICES;
   if(StringFind(sym, "EUSTX50")>= 0) return PAIR_TYPE_INDICES;   // EuroStoxx50
   // Crypto — ADD 2026-07: extended roster
   if(StringFind(sym, "BTC") >= 0) return PAIR_TYPE_CRYPTO;
   if(StringFind(sym, "ETH") >= 0) return PAIR_TYPE_CRYPTO;
   if(StringFind(sym, "BNB") >= 0) return PAIR_TYPE_CRYPTO;
   if(StringFind(sym, "SOL") >= 0) return PAIR_TYPE_CRYPTO;
   if(StringFind(sym, "XRP") >= 0) return PAIR_TYPE_CRYPTO;
   if(StringFind(sym, "LTC") >= 0) return PAIR_TYPE_CRYPTO;
   if(StringFind(sym, "ADA") >= 0) return PAIR_TYPE_CRYPTO;
   if(StringFind(sym, "DOT") >= 0) return PAIR_TYPE_CRYPTO;
   if(StringFind(sym, "LINK")>= 0) return PAIR_TYPE_CRYPTO;
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
      case PAIR_TYPE_MAJOR:   return adaptive.Spread_Major;
      case PAIR_TYPE_MINOR:   return adaptive.Spread_Minor;
      case PAIR_TYPE_EXOTIC:  return adaptive.Spread_Exotic;
      case PAIR_TYPE_GOLD:    return adaptive.Spread_Gold;
      case PAIR_TYPE_SILVER:  return adaptive.Spread_Silver;   // ADD 2026-07
      case PAIR_TYPE_INDICES: return adaptive.Spread_Indices;  // ADD 2026-07
      case PAIR_TYPE_CRYPTO:  return adaptive.Spread_Crypto;
      default:                return adaptive.Spread_Minor;
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
   // F-AUDIT 2026-07: Settings.Stats_TrackRejections / Stats_TrackPasses REMOVED as proven dead
   // sinks — neither field is read anywhere; only Stats_FullEvaluation gates the stats logic.
   // Inp_Debug_Stats_TrackRejections / Inp_Debug_Stats_TrackPasses (which fed them) are removed.
   // See Readme/README_SEA_PARAMETER_MAPPING.md "Input Surface Audit".
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
   Settings.CloseOnReverse          = false;
   Settings.RiskPercent             = Inp_RM_RiskPercentDefault;
   Settings.RiskCapMultiple         = (Inp_RM_RiskCapMultiple > 0.0) ? Inp_RM_RiskCapMultiple : 1.5;
   Settings.FixedLotSize            = 0.0; // 0 = risk-based sizing (default)
   Settings.MaxSpread               = Inp_Global_VETO_MaxSpread;
   Settings.UseSpread               = Inp_Global_VETO_UseSpread;
   Settings.ATR_VoteMinPips         = 5.0;
   Settings.ATR_VoteMaxPips         = 50.0;

   Settings.CandleBody_AvgPeriod    = MathMax(1, 5);
   Settings.CandleBody_MaxMult      = 4.0;
   Settings.CandleBody_CheckBars    = MathMax(1, 3);
   Settings.CandleBody_RequireDirection = true;

   Settings.UseMACompatSizer        = false;
   Settings.MA_MaximumRiskPct       = 0.02;   // default (MA preset only; overwritten by ApplyPreset)
   Settings.MA_DecreaseFactor       = 3.0;    // default (MA preset only; overwritten by ApplyPreset)
   // B5 2026-06: was hardcoded false. Now reads Inp_CUSTOM_RequirePriceCross
   // (default false preserves prior behavior). Only consulted when CUSTOM
   // is the active preset AND BiasMode=BIAS_2EMA AND AutoStrat=STRAT_2EMA_CROSS_PRICE
   // (see SEA_SignalEngine.mqh:~6614). All non-CUSTOM presets explicitly set
   // RequirePriceCross in their preset block, overriding this seed.
   Settings.RequirePriceCross       = false;
   Settings.MABenchmarkStrict       = false;

   Settings.RRM_Lookback               = 5;
   Settings.RequireRecoveryMomentum    = false;
   
   Settings.Gate_Recovery.mode         = GATE_SCALE_OFF;
   Settings.Gate_Recovery.value        = 0.0;
   Settings.Gate_EmaDiv.mode           = GATE_SCALE_OFF;
   Settings.Gate_EmaDiv.value          = 0.0;
   Settings.Gate_CandleDirection.mode  = GATE_SCALE_OFF;
   Settings.Gate_CandleDirection.value = 0.0;

   // Bias
   Settings.BiasEnabled          = true;
   Settings.BiasMode             = BIAS_4EMA;
   Settings.ManSide              = Inp_Global_ManualSide;
   Settings.BiasFastID           = MathMax(0, MathMin(3, 2));
   Settings.BiasSlowID           = MathMax(0, MathMin(3, 3));
   Settings.AutoStrat            = STRAT_4EMA_LAYER;
   Settings.MaType               = METHOD_EMA;
   Settings.ma_h_shift           = 1;
   Settings.ma_v_shift           = 1;
   
   // Filters
   Settings.UseNews              = Inp_Global_VETO_UseNews;
   Settings.NewsPre              = Inp_Global_VETO_NewsPreMinutes;
   Settings.NewsPost             = Inp_Global_VETO_NewsPostMinutes;
   Settings.NewsImpactFilter     = Inp_Global_VETO_NewsImpactFilter;       // F-AUDIT 2026-06
   // ── TRADING HOURS FILTER ─────────────────────────────────────────────
   // Wire named-session inputs and compute start/end hours from margins.
   Settings.TradingHoursEnabled  = Inp_Session_Enabled;
   // London: default 09–17 EET
   Settings.Session_London       = Inp_Session_London;
   { int m = MathMax(0, Inp_Session_London_Margin);
     Settings.Session_London_Start = MathMax(0,  9 - m);
     Settings.Session_London_End   = MathMin(23, 17 + m); }
   // New York: default 14–22 EET
   Settings.Session_NY           = Inp_Session_NY;
   { int m = MathMax(0, Inp_Session_NY_Margin);
     Settings.Session_NY_Start   = MathMax(0, 14 - m);
     Settings.Session_NY_End     = MathMin(23, 22 + m); }
   // Asian: default 01–09 EET
   Settings.Session_Asia         = Inp_Session_Asia;
   { int m = MathMax(0, Inp_Session_Asia_Margin);
     Settings.Session_Asia_Start = MathMax(0,  1 - m);
     Settings.Session_Asia_End   = MathMin(23,  9 + m); }
   // Custom windows
   Settings.Session_Win1         = Inp_Session_Win1;
   Settings.Session_Win1_Start   = Inp_Session_Win1_Start;
   Settings.Session_Win1_End     = Inp_Session_Win1_End;
   Settings.Session_Win2         = Inp_Session_Win2;
   Settings.Session_Win2_Start   = Inp_Session_Win2_Start;
   Settings.Session_Win2_End     = Inp_Session_Win2_End;
   if(Settings.TradingHoursEnabled)
   {
      PrintFormat("[SESSION] Filter ON — London:%s NY:%s Asia:%s Win1:%s Win2:%s",
                  Settings.Session_London ? StringFormat("✓ %02d-%02d", Settings.Session_London_Start, Settings.Session_London_End) : "off",
                  Settings.Session_NY     ? StringFormat("✓ %02d-%02d", Settings.Session_NY_Start,     Settings.Session_NY_End)     : "off",
                  Settings.Session_Asia   ? StringFormat("✓ %02d-%02d", Settings.Session_Asia_Start,   Settings.Session_Asia_End)   : "off",
                  Settings.Session_Win1   ? StringFormat("✓ %02d-%02d", Settings.Session_Win1_Start,   Settings.Session_Win1_End)   : "off",
                  Settings.Session_Win2   ? StringFormat("✓ %02d-%02d", Settings.Session_Win2_Start,   Settings.Session_Win2_End)   : "off");
   }
   Settings.Ind_MTF_Enabled      = Inp_Ind_MTF_Enabled;
   Settings.MTF_TF1              = Inp_Global_MTF_TF1;
   Settings.MTF_TF2              = Inp_Global_MTF_TF2;
   Settings.MTF_EMA_Fast         = MathMax(1, Inp_Global_MTF_EMA_Fast);
   Settings.MTF_EMA_Slow         = MathMax(1, Inp_Global_MTF_EMA_Slow);
   Settings.MTF_RequirePhase     = Inp_Global_MTF_RequirePhase;
   // F-AUDIT 2026-07: Settings.MTF_StrictAlignment is a PROVEN DEAD SINK — SEA_SignalEngine.mqh
   // documents it directly: "MTF_StrictAlignment is retained for compatibility but the gate is
   // strict-by-construction; the flag no longer relaxes it." Inp_Global_MTF_StrictAlignment (which
   // fed this) is removed. Literal `true` preserves the field's value for ConfigSync round-tripping.
   Settings.MTF_StrictAlignment  = true;

   // Fibonacci voter (globally available)
   Settings.Ind_Fib_Enabled      = Inp_Global_Ind_Fib_Enabled;
   Settings.Fib_MinRetracement   = MathMax(0.0, MathMin(1.0, Inp_Global_Ind_Fib_MinRetracement));
   Settings.Fib_MaxRetracement   = MathMax(Settings.Fib_MinRetracement, MathMin(1.0, Inp_Global_Ind_Fib_MaxRetracement));
   Settings.Fib_SwingLookback    = MathMax(10, Inp_Global_Ind_Fib_SwingLookback);

   // CandleBody close-ratio extension
   Settings.CandleBody_MinCloseRatio = MathMax(0.0, MathMin(1.0, Inp_Global_Ind_CandleBody_MinCloseRatio));
   Settings.CandleBody_CarryOnOverext = Inp_Global_Ind_CandleBody_CarryOnOverext;

   // TRAIL_EMA period
   Settings.TrailEMA_Period           = MathMax(0, Inp_Global_TrailEMA_Period);
   Settings.TrailEMA_RibbonRole       = 0;  // CUSTOM: EMA1 as fallback
   Settings.TrailEMA_Shift            = MathMax(1, MathMin(5, Inp_Global_TrailEMA_Shift));
   Settings.TrailEMA_CushionPips      = 0.0;   // CUSTOM: set via preset or direct cfg override
   Settings.TrailEMA_CushionAtrMult   = 0.0;   // CUSTOM: 0 = disabled (falls back to pip or PSAR)
   Settings.TrailEMA_CushionAtrPeriod = 14;

   // Voting

   // Indicator periods / thresholds
   Settings.P_Ema1               = 5;
   Settings.P_Ema2               = 13;
   Settings.P_Ema3               = 34;
   Settings.P_Ema4               = 89;
   Settings.P_Adx                = 14;
   Settings.T_Adx                = 20;
   Settings.ADX_Mode                  = ADX_MODE_STATIC;
   Settings.ADX_Percentile            = 50.0;
   Settings.ADX_Lookback              = 100;
   Settings.ADX_PercentileRefreshSec  = Inp_Global_Ind_Adx_PercentileRefreshSec;
   Settings.ADX_Threshold_Accumulation= 12.0;
   Settings.ADX_Threshold_Trending    = 25.0;
   Settings.ADX_Threshold_Distribution= 18.0;
   Settings.P_MacdFast           = 8;
   Settings.P_MacdSlow           = 13;
   Settings.P_MacdSig            = 5;
   Settings.P_Rsi                = 14;
   Settings.T_RsiOB              = 70.0;
   Settings.T_RsiOS              = 30.0;
   Settings.P_Cci                = 14;
   Settings.P_Mfi                = 14;
   Settings.T_Mfi                = Inp_Global_Ind_Mfi_Level;
   Settings.T_MfiOB              = Inp_Global_Ind_Mfi_Level;
   Settings.T_MfiOS              = Inp_Global_Ind_Mfi_Level;
   Settings.P_StoK               = 5;
   Settings.P_StoD               = 3;
   Settings.P_StoSlow            = 3;
   Settings.T_StoOB              = 80.0;
   Settings.T_StoOS              = 20.0;
   Settings.P_Bb                 = 20;
   Settings.P_BbDev              = 2.0;
   Settings.P_PsarStep           = 0.05;
   Settings.P_PsarMax            = 0.5;
   Settings.P_Atr                = 14;

   // Modes
   Settings.MacdRequireSlope     = false;
   // Theme5a-extension 2026-06: MacdRequireDivergence → MacdBlockOnDivergence rename.
   // Old name had REVERSAL-confirmation semantics (wrong for RRM_ORG trend-following);
   // new name + new logic blocks on trend-exhaustion divergence at price highs/lows.
   // Off by default, opt-in via Inp_RRM_ORG_MacdDiv. See ST_Settings comment for details.
   Settings.MacdBlockOnDivergence= false;
   Settings.MacdDivLookback      = 10;
   Settings.MacdRequireHook      = false;
   Settings.MacdFreshBars        = 3;
   Settings.MacdHistDecelEnabled = false;  // STEP3 2026-06: was "RRM-only; set true by PRESET_RRM" — RRM removed. All remaining presets explicitly set false or don't override.
   Settings.MacdSlopeMin         = 0.00001;
   Settings.RsiMode              = RSI_TREND_ABOVE_50;
   Settings.CciMode              = CCI_TREND_ZERO;
   Settings.StoMode              = STO_CROSS_SIGNAL;
   Settings.BbMode               = BB_TREND_FOLLOW;
   Settings.MfiMode              = MFI_ZONE_FILTER;

   // Active votes
   Settings.Ind_Adx_Enabled      = false;
   Settings.Ind_Macd_Enabled     = false;
   Settings.Ind_Rsi_Enabled      = false;
   Settings.Ind_Cci_Enabled      = false;
   Settings.Ind_Mfi_Enabled      = false;
   Settings.Ind_Sto_Enabled      = false;
   Settings.Ind_Bb_Enabled       = false;
   Settings.Ind_Psar_Enabled     = true;
   Settings.Ind_P123_Enabled     = false;
   Settings.Ind_Ross_Enabled     = false;
   Settings.Ind_Atr_Enabled      = false;
   Settings.Ind_CandleBody_Enabled = true;
   Settings.Ind_CI_Enabled        = false;
   Settings.Ind_VRC_Enabled       = false;
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
    // Theme5a 2026-06: DPI exhaustion-divergence sub-filter defaults (off; RRM_ORG preset wires the user inputs)
    Settings.DpiBlockOnDivergence        = false;
    Settings.DpiDivLookback              = 10;
    Settings.DPI_HistMomentumThreshold   = Inp_RRM_ORG_DPI_HistMomentumThreshold;
    Settings.DPI_HistDecelLookback       = MathMax(1, MathMin(9, Inp_RRM_ORG_DPI_HistDecelLookback));
    // F-AUDIT 2026-06: was Inp_RRM_ORG_DPI_HistTrackingEnabled / DPI_BlockOnDeceleration
    // (cross-preset bleed: all 7 presets inherited RRM_ORG's value). Now globalized.
    Settings.DPI_HistTrackingEnabled     = Inp_Global_F_DPI_HistTrackingEnabled;
    Settings.DPI_BlockOnDeceleration     = Inp_Global_F_DPI_BlockOnDeceleration;
    Settings.DPI_ExitOnHistDisappear     = Inp_RRM_ORG_DPI_ExitOnHistDisappear;
    Settings.DPI_ExitThreshold           = MathMax(0.0, Inp_RRM_ORG_DPI_ExitThreshold);
    // DPI CCI Reset-Recovery
    Settings.DPI_RequireResetRecovery    = Inp_RRM_ORG_DPI_RequireResetRecovery;
    Settings.DPI_GrantFirstEntry         = Inp_RRM_ORG_DPI_GrantFirstEntry;
    Settings.DPI_ResetRecoveryBars       = MathMax(0, Inp_RRM_ORG_DPI_ResetRecoveryBars);
    Settings.DPI_ResetRequireGreen       = Inp_RRM_ORG_DPI_ResetRequireGreen;
    // Choppiness Index
    // BUGFIX A6 2026-06: was `MathMax(5, 14)` / `MathMax(0.0, 61.8)` which are
    // compile-time constants masquerading as clamped input reads. No Inp_CI_*
    // input variables exist in SEA_Inputs.mqh. Documented as honest seed defaults;
    // PRESET_RRM_ORG overrides CI_Period via its preset block. To make CI_Period
    // or CI_RangingThreshold tunable, add Inp_CI_* inputs and wire them here.
    Settings.CI_Period             = 14;    // seed default (overwritten by presets that use CI)
    Settings.CI_RangingThreshold   = 61.8;  // seed default (standard Dreiss threshold)

   // VRC
   Settings.VRC_ATR_Period        = MathMax(1, 14);
   Settings.VRC_Lookback          = MathMax(10, 100);
   Settings.VRC_LowThreshold      = MathMax(0.0, MathMin(100.0, 33.0));
   Settings.VRC_RefreshSec        = 14400;

   // Exits
   Settings.SL_FixedPips         = Inp_Global_SL_FixedPips;
   Settings.SL_MinPips           = MathMax(0.0, Inp_Global_SL_MinPips);
   Settings.SL_WidenToMinimum    = Inp_Global_SL_WidenToMinimum;
   Settings.SLMode               = SL_MODE_PSAR_DOT;
   Settings.TPMode               = TP_MODE_RR;
   Settings.FixedTPPips          = 40.0;
   Settings.SLPercent            = 0.5;
   Settings.SL_AtrPeriod         = Inp_Global_SL_AtrPeriod;   // CUSTOM: user-controlled; overridden by TI/RRM/RRM_ORG preset blocks
   Settings.SL_AtrMult           = Inp_Global_SL_AtrMult;     // CUSTOM: user-controlled; overridden by TI/RRM/RRM_ORG preset blocks
   Settings.RRRatio              = 2.5;
   Settings.SwingLookback        = 34;
   Settings.FractalPeriod        = 5;
   Settings.TPFractalOffset      = 1;
   Settings.ShowSwingMarkers     = Inp_UI_ShowSwingMarkers;
   Settings.ShowFractalMarkers   = Inp_UI_ShowFractalMarkers;
   Settings.MarkerLookback       = MathMax(0, Inp_UI_MarkerLookback);
   Settings.ShowMarkerLabels     = Inp_UI_ShowMarkerLabels;
   Settings.SwingHighColor       = Inp_UI_SwingHighColor;
   Settings.SwingLowColor        = Inp_UI_SwingLowColor;
   Settings.SwingMarkerSize      = MathMax(1, MathMin(5, Inp_UI_SwingMarkerSize));
   Settings.FractalHighColor     = Inp_UI_FractalHighColor;
   Settings.FractalLowColor      = Inp_UI_FractalLowColor;
   Settings.FractalMarkerSize    = MathMax(1, MathMin(5, Inp_UI_FractalMarkerSize));

   Settings.TrailTrigger         = TRIGGER_IMMEDIATE;
   Settings.TrailDistancePips    = 5.0;
   Settings.BEThresholdPips      = 5.0;
   Settings.TrailProfitPercent   = 25.0;
   Settings.TrailProfitPercentLPR= 25.0;
   Settings.TrailStepPips        = 5.0;
   Settings.TrailLockProfit      = true;
   Settings.TP_Enabled           = true;
   Settings.TrailMode            = TRAIL_EMA;
   Settings.PSAR_TrailCushionMode   = PSAR_CUSHION_ATR; // default; overwritten by ApplyPreset
   Settings.PSAR_TrailCushionAtrPeriod = 14;  // default; overwritten by ApplyPreset
   Settings.PSAR_TrailCushionAtrMult   = 0.5; // default; overwritten by ApplyPreset
   Settings.PSAR_TrailCushionPct       = 0.0; // default; overwritten by ApplyPreset
   Settings.PSAR_TrailDelay         = 2;      // default; overwritten by ApplyPreset

   Settings.ExitProfile             = EXIT_PROFILE_RRM;
   Settings.BE_Mode                 = BE_MODE_TP_PROGRESS_PCT;
   Settings.RRM_BE_ProgressPct      = 50.0;   // default; overwritten by ApplyPreset
   Settings.RRM_BE_RMultiple        = 1.0;    // default; overwritten by ApplyPreset
   Settings.RRM_TrailPsarDotShift = 2;      // default; overwritten by ApplyPreset
   Settings.RRM_FreezeTrailOnFlip   = true;   // default; overwritten by ApplyPreset
   Settings.RRM_TrailStartsAfterBE  = false;  // default; overwritten by ApplyPreset

   Settings.Vote_EvalShift       = 1;
   Settings.Vote_AllowPsarFlip   = false;
   Settings.Vote_PsarFlipDelay   = (10 < -1) ? -1 : (10 > 10) ? 10 : 10;
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
   Settings.Adaptive.Spread_Silver     = Inp_Adaptive_Spread_Silver;    // ADD 2026-07
   Settings.Adaptive.Spread_Indices    = Inp_Adaptive_Spread_Indices;   // ADD 2026-07
   Settings.Adaptive.Spread_Crypto     = Inp_Adaptive_Spread_Crypto;

   if(Settings.Adaptive.PairType == PAIR_TYPE_AUTO)
      Settings.Adaptive.PairType = DetectPairType(_Symbol);

   Settings.MaxSpread = GetAdaptiveSpreadLimit(Settings.Adaptive.PairType, Settings.Adaptive);

   Settings.PhaseDetectionEnabled        = true;
   Settings.BlockUnorderedPhase          = true;
   Settings.BlockEmergingPhase           = false;
   Settings.RequireMinPhaseConfirm       = false;
   Settings.MinPhaseConfirmBars          = 0;
   
   Settings.Emerging_AllowWeakTrades     = true;
   Settings.Emerging_AllowMediumTrades   = true;
   Settings.Emerging_AllowStrongTrades   = true;
   Settings.Trending_AllowWeakTrades     = true;
   Settings.Trending_AllowMediumTrades   = true;
   Settings.Trending_AllowStrongTrades   = true;

    Settings.EnableLayerDetection         = true;
    Settings.AllowLayer1_Entries          = true;
    Settings.AllowLayer2_Entries          = true;
    Settings.AllowLayer3_Entries          = true;
   Settings.RRM_EnableDrawdownProtection = false; // default; overwritten by ApplyPreset
   Settings.RRM_MaxConsecutiveLosses     = 4;     // default; overwritten by ApplyPreset
   Settings.RRM_MaxTradesPerDay          = 5;     // default; overwritten by ApplyPreset
   Settings.RRM_MaxDailyDrawdownPct      = 2.0;   // default; overwritten by ApplyPreset

   // Account-level safety guards (preset-independent; mapped here so they are
   // never cleared by preset overrides applied later in ApplyPreset()).
   Settings.Safety_MaxEquityDrawdownPct  = Inp_Global_Safety_MaxEquityDrawdownPct;
   Settings.Safety_MinEquityFloor        = Inp_Global_Safety_MinEquityFloor;
   Settings.Safety_MinRewardRiskRatio    = Inp_Global_Safety_MinRewardRiskRatio;
   Settings.Safety_CountBEInAggregateRisk = Inp_Global_Safety_CountBEInAggregateRisk;
   Settings.Safety_MaxPositionsPerDir    = MathMax(0, Inp_Global_Safety_MaxPositionsPerDir);
   Settings.Safety_DelayTrailUntilR      = Inp_Global_Safety_DelayTrailUntilR;
   Settings.Safety_TrailActivateR        = Inp_Global_Safety_TrailActivateR;
   Settings.Safety_RequirePriorAtBEToAdd = Inp_Global_Safety_RequirePriorAtBEToAdd;

   // B6 2026-06: was hardcoded 1. Now reads Inp_CUSTOM_SlopeLookbackBars
   // (default 1 preserves prior behavior). Clamped 1..5 to match the runtime
   // clamp in EvaluateBias (SEA_SignalEngine.mqh:~6511-6513). Only meaningful
   // when CUSTOM is active AND BiasMode=BIAS_1EMA/BIAS_2EMA. All non-CUSTOM
   // presets explicitly set SlopeLookbackBars in their preset block.
   Settings.SlopeLookbackBars      = MathMax(1, MathMin(5, 1));
   Settings.LayerPullbackEnabled        = Inp_Global_LayerPullbackEnabled;
   Settings.LayerS_RequireDirAlign      = Inp_Global_LayerS_Require_DirAlign;
   // GUARD 1: mapped here (global, preset-independent) and deliberately NOT written by
   // any ApplyPreset block, so it stays user-controlled under every preset and hooks the
   // bias-direction signal rather than any preset's EMA arithmetic.
   Settings.Guard1_SkipFirstPostFlipPR  = Inp_Global_Guard1_SkipFirstPostFlipPR;
   Settings.LayerResetOnRealign         = Inp_Global_LayerReset_OnRealign;
   Settings.LayerResetPhaseConfirmBars  = Inp_Global_LayerReset_PhaseConfirm;
   // UNO-exit cooldown default (disabled; only RRM_ORG preset wires the user input).
   // Other presets keep the legacy behaviour (cycles can complete immediately after
   // a UNO exit). RRM_ORG users can opt in via Inp_RRM_ORG_MinBarsAfterUNOExit.
   Settings.MinBarsAfterUNOExit         = 0;
   // UNO tolerance default: preserve layer states across a short (<=2 bar) UNO
   // flicker that resolves back to the same direction. EA-wide (all presets).
   Settings.UNO_ToleranceBars           = 2;
   // Pullback observation window (EA-wide defaults; RRM_ORG overlays its inputs).
   Settings.LayerPullbackWindow_W       = 21;
   Settings.LayerPullbackWindow_M       = 34;
   Settings.LayerPullbackWindow_S       = 55;
   Settings.LayerPullbackWindow         = 0;      // 0 = use per-layer values
   Settings.LayerRecoveryMaxAgeEnabled  = true;
   // LayerS=TM-only default (disabled = legacy behavior). RRM_ORG users can opt in
   // via Inp_RRM_ORG_LayerS_TMOnly to match the canonical RRM Trade Setups card.
   Settings.LayerS_TMOnly               = false;
   Settings.LayerBaselineLookback       = 10;     // default; overwritten by ApplyPreset
   // Per-layer pullback-recovery defaults (seed for ALL presets so the shared
   // magnitude logic is safe; RRM_ORG/CUSTOM override these via ApplyPreset).
   Settings.LayerBaselineLookback_W     = 0;     // 0 = fall back to global lookback
   Settings.LayerBaselineLookback_M     = 0;
   Settings.LayerBaselineLookback_S     = 0;
   // F-AUDIT 2026-07 (round 2): LayerPullbackRatio_Legacy is a PROVEN DEAD SINK, confirmed by
   // three existing READMEs (README_SEA_SIGNAL_REFERENCE.md, README_SEA_TRADE_LOGIC.md,
   // README_SEA_PRESETS.md) which already documented it as inert under the Path-2 slope model --
   // a documentation cross-reference this audit's first pass missed. Inp_RRM_ORG_LayerPBPullbackRatio
   // (which fed this) is removed. See Readme/README_SEA_PARAMETER_MAPPING.md "Input Surface Audit".
   Settings.LayerPullbackRatio_Legacy          = 0.5;
   Settings.LayerFlatRatio              = 0.1;
   Settings.LayerRecoveryRatio          = 0.3;
   Settings.LayerRecoveryOnSlope        = false;  // default; overwritten by ApplyPreset
   Settings.LayerRecoveryRatio_W        = -1.0;  // -1 = use global
   Settings.LayerRecoveryRatio_M        = -1.0;
   Settings.LayerRecoveryRatio_S        = -1.0;
   Settings.LayerAllowReversalPullback  = true;

   // F-AUDIT 2026-06: Climax guard. Sub-params already global; master toggle now
   // also global (was per-preset via Inp_CUSTOM_ClimaxGuard_Enabled / Inp_RRM_ORG_ClimaxGuard_Enabled;
   // 5/7 presets had no input at all). Climax is conceptually an F sub-filter
   // (market-state filter) — see EvaluateF.
   Settings.ClimaxGuard_Enabled         = Inp_Global_F_ClimaxGuard_Enabled;
   Settings.ClimaxGuard_Lookback        = MathMax(1, Inp_Global_ClimaxGuard_Lookback);
   Settings.ClimaxGuard_ATRPeriod       = MathMax(1, Inp_Global_ClimaxGuard_ATRPeriod);
   Settings.ClimaxGuard_BarATRMult      = MathMax(0.0, Inp_Global_ClimaxGuard_BarATRMult);
   Settings.ClimaxGuard_MoveATRMult     = MathMax(0.0, Inp_Global_ClimaxGuard_MoveATRMult);
   Settings.ClimaxGuard_ResetPullback   = Inp_Global_ClimaxGuard_ResetPullback;

    // VPRR defaults (disabled — only RRM_ORG preset wires it on)
    Settings.VPRR_Enabled         = Inp_Global_VPRR_Enabled;
    Settings.VPRR_VolumeType      = (int)VPRR_VOL_AUTO;
    Settings.VPRR_RecoveryBars    = 3;
    Settings.VPRR_MinRecoveryBars = 2;
    Settings.VPRR_MinRatio        = 1.0;
    // Theme3 2026-06: per-layer VPRR threshold overrides (0 = use VPRR_MinRatio above)
    Settings.VPRR_MinRatio_W      = MathMax(0.0, Inp_Global_VPRR_MinRatio_W);
    Settings.VPRR_MinRatio_M      = MathMax(0.0, Inp_Global_VPRR_MinRatio_M);
    Settings.VPRR_MinRatio_S      = MathMax(0.0, Inp_Global_VPRR_MinRatio_S);
    Settings.VPRR_ExternalSymbol  = "";

    // BarClose (bcX) settings
    Settings.BarClose_Enabled    = true;
   Settings.BarClose_Mode       = BC_LAYER_AWARE;
   Settings.BarClose_DefaultEMA = ROLE_EMA1;

   // Re-entry after breakeven: disabled by default; enabled by RRM presets
   Settings.AllowReEntryAfterBE = false;
   Settings.ReEntryLotScalePct  = 0;    // 0 = full size (default for CUSTOM; overridden by RRM/RRM_ORG/TI presets)

   // Post-trade cooldown: disabled by default; presets may override
   Settings.MinBarsAfterClose      = Inp_Global_MinBarsAfterClose;
   Settings.MinBarsAfterWeekendGap = MathMax(0, Inp_Global_MinBarsAfterWeekendGap);

   // Spread retry cap: kill carry after N consecutive spread-blocked bars (0=unlimited)
   Settings.MaxSpreadRetryBars    = Inp_Global_VETO_MaxSpreadRetryBars;

   // F-AUDIT 2026-06: F-filter master toggles now globalized. Tuning sub-params
   // (EmaFanMaxTotalPips/MaxPct, PriceExtMaxATR/RefEma/AtrPeriod) remain
   // preset-tuned via the preset blocks; if a preset has no tuning wiring,
   // these seed defaults apply.
   Settings.EmaFanFilterEnabled   = Inp_Global_F_EmaFanFilterEnabled;
   Settings.EmaFanMaxTotalPips    = 60.0;    // default; overwritten by ApplyPreset for tuned presets
   Settings.EmaFanMaxPct          = 0.0;     // default; overwritten by ApplyPreset for tuned presets
   Settings.PriceExtFilterEnabled = Inp_Global_F_PriceExtFilterEnabled;
   Settings.PriceExtRefEma        = 3;        // default; overwritten by ApplyPreset for tuned presets
   Settings.PriceExtMaxATR        = 2.5;      // default; overwritten by ApplyPreset for tuned presets
   Settings.PriceExtAtrPeriod     = 14;       // default; overwritten by ApplyPreset for tuned presets

   // F-AUDIT 2026-06: DPI deceleration master toggle globalized (was bleeding
   // from Inp_RRM_ORG_DPI_Decel_Filter into all non-RRM_ORG presets).
   Settings.DpiDecelFilterEnabled = Inp_Global_F_DpiDecelFilterEnabled;

   // ── PHASE B: TE-side gates (user-configurable veto controls) ──
   Settings.TE_RecheckBarClose    = Inp_Global_VETO_TE_RecheckBarClose;
   Settings.TE_BC_TolerancePips   = MathMax(0.0, Inp_Global_VETO_TE_BC_TolerancePips);
   Settings.TE_OpenDelaySeconds   = Inp_Global_VETO_TE_OpenDelaySeconds;
   Settings.TE_SpreadMedianTicks  = Inp_Global_VETO_TE_SpreadMedianTicks;

   // ── PHASE B: Recovery-sensitivity tuning defaults (all off; PRESET_RRM_ORG may override) ──
   Settings.DPI_IgnoreCCIForVote  = false;
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

