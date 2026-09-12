//  SAVE AS UTF-16 LE WITH BOM
//+------------------------------------------------------------------+
//| SEA_Inputs.mqh — EA input parameter declarations                 |
//| Included by: SimpleEA, SEA_Presets, SEA_TradeExecutor, SEA_UI    |
//| NOT included by: SEA_IND_SignalScan (keeps scanner dialog clean) |
//+------------------------------------------------------------------+
#include <RRMS\SEA_Config.mqh>

//+------------------------------------------------------------------+
//| INPUT PARAMETERS — MAP OF THIS FILE (2026-09-10 reorganisation)   |
//|                                                                  |
//|  1  START            preset selector, magic, manual bias override |
//|  2  RISK & MONEY     RM caps, adaptive risk, margin, safety,      |
//|                      portfolio layer                  (TE / RC)   |
//|  3  ENTRY VETOES     session, spread, news, TE gates, cooldown    |
//|                                                       (TE side)   |
//|  4  SIGNAL FILTERS   F-filters, climax guard, layer guards        |
//|                      — all presets                    (TS side)   |
//|  5  EXIT MGMT        R-ladder, daily target, global trail EMA    |
//|                      — all presets                    (TM side)   |
//|  6  META GATE        optional ML trade filter (SEA_MetaGate.mqh)  |
//|  7  VPRR             volume measurement (never votes)             |
//|  8  UI               panels, colours, markers                     |
//|  9  DEBUG            journal levels, eval window, CSV reporting   |
//| 10  PRESET_RRM_ORG   ★ active preset — B/P, L, I, F, TM, TE      |
//| 11  OTHER PRESETS    FPM, TOPINVESTOR, XEMA, TURTLE, TREND,       |
//|                      RH_REBELLION, RH_1MS/STS/SS/GS/SM, MA        |
//| 12  SEED DEFAULTS    engine fallbacks presets override            |
//|                                                                  |
//| Rules: one section = ▓ banner; one sub-group = "=== NAME ===";   |
//| inside a sub-group: enable/mode → int → double. Long rationale   |
//| lives in the // block above its group, not in the trailing text. |
//| Names, types and defaults are unchanged by the reorganisation.   |
//+------------------------------------------------------------------+

input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "    🎯 1. START — preset selector (GLOBAL)";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
//
// Pick ONE preset (type PRESET_ to autocomplete). A preset only works if its compile switch #define
//    SEA_BUILD_<name> is uncommented in SEA_Config.mqh. A preset LOCKS its strategy-critical fields; everything in
//    sections 2-9 stays user-editable under every preset (Policy A). Inp_Global_ManualSide is read only when the
//    active preset runs BIAS_MANUAL (TURTLE/TREND) — it is the direction override; SIDE_BOTH lets the strategy
//    decide.
//
input ulong              Inp_Global_MagicNum                          = 12345;                   // Magic number (trade identifier)
input EStrategyPreset    Inp_Global_Preset                            = PRESET_RRM_ORG;          // Strategy preset (needs its SEA_BUILD_* switch on)
input EManualSide        Inp_Global_ManualSide                        = SIDE_BOTH;               // Manual bias side (BIAS_MANUAL presets only): LONG / SHORT / BOTH

input group " ";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "    💰 2. RISK & MONEY MANAGEMENT (RM / RC) — all presets";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
//
// What: per-trade sizing, account-wide caps and the hard safety rails. Where: TE (entry) and RC (risk control)
//    gates in SEA_TradeExecutor.mqh. Applies to every preset; presets never lock these (Policy A). Docs: README.md
//    "TE Equation", Readme/README_SEA_VETO_REFERENCE.md §3, Readme/README_SEA_PORTFOLIO_RISK.md.
//

input group "=== RM — CORE CAPS ===";
input int                Inp_RM_MaxOpenTrades                         = 3;                       // RM: Max concurrent trades (0 = unlimited)
input double             Inp_RM_RiskPercentDefault                    = 2.0;                     // RM: Default risk % per trade
input double             Inp_RM_MaxTotalRisk                          = 6.0;                     // RM: Max total active risk (%; 0 = unlimited)
input double             Inp_RM_RiskCapMultiple                       = 1.5;                     // RM: Hard per-trade risk cap (× target; clamps oversized lots, circuit breaker)
input double             Inp_RM_MarginUsageLimit                      = 0.0;                     // RM: Max % of free margin per trade (0 = use 100%)
input double             Inp_RM_MinMarginLevel                        = 200.0;                   // RM: Min margin level (%) required to allow new entries (0 = disabled)
input double             Inp_RM_EmergencyMarginLevel                  = 0.0;                     // RM: Emergency margin level (%) to force-close worst position (0 = disabled)

input group "=== RM — ADAPTIVE RISK (by timeframe / instrument) ===";
input bool               Inp_RM_UseAdaptiveRisk                       = true;                    // RM Adaptive: Enable TF-based risk scaling
input bool               Inp_RM_UseMarginAdjustment                   = true;                    // RM Adaptive: Enable instrument-aware margin adjustment
input double             Inp_RM_AdaptiveRisk_M1                       = 1.0;                     // RM Adaptive: risk % on M1
input double             Inp_RM_AdaptiveRisk_M5                       = 1.5;                     // RM Adaptive: risk % on M5
input double             Inp_RM_AdaptiveRisk_M15Plus                  = 2.0;                     // RM Adaptive: risk % on M15+
input double             Inp_RM_MarginAdj_Gold                        = 0.8;                     // RM Margin: Gold/Metals multiplier (0.8 = 80%)
input double             Inp_RM_MarginAdj_Crypto                      = 0.7;                     // RM Margin: Crypto multiplier (0.7 = 70%)
input double             Inp_RM_MarginAdj_Exotic                      = 0.85;                    // RM Margin: Exotic pairs multiplier (0.85 = 85%)
input double             Inp_RM_MarginAdj_JPY                         = 0.9;                     // RM Margin: JPY pairs multiplier (0.9 = 90%)

input group "=== RM — CUSHION OVERRIDES (0 = TF-adaptive auto) ===";
input double             Inp_RM_Override_SL_Cushion                   = 0.0;                     // RM Override: SL cushion pips (0=auto)
input double             Inp_RM_Override_Trail_Cushion                = 0.0;                     // RM Override: Trail cushion pips (0=auto)
input double             Inp_RM_Override_BE_Cushion                   = 0.0;                     // RM Override: BE cushion pips (0=auto)

input group "=== RM — SAFETY GUARDS (off by default) ===";
input bool               Inp_Global_Safety_CountBEInAggregateRisk     = false;                   // SAFETY: Count BE positions toward MaxTotalRisk (closes pyramiding gap)
input bool               Inp_Global_Safety_DelayTrailUntilR           = false;                   // SAFETY: Delay trailing until open profit reaches R-multiple
input bool               Inp_Global_Safety_RequirePriorAtBEToAdd      = false;                   // SAFETY: New trade only if all open same-symbol positions are at BE+
input int                Inp_Global_Safety_MaxPositionsPerDir         = 2;                       // SAFETY: Max concurrent positions per direction (0=off)
input double             Inp_Global_Safety_TrailActivateR             = 0.0;                     // SAFETY: R-multiple of profit before trailing engages (0=off)
input double             Inp_Global_Safety_MaxEquityDrawdownPct       = 0.0;                     // SAFETY: Pause new entries if peak→trough equity DD ≥ % (0=off)
input double             Inp_Global_Safety_MinEquityFloor             = 0.0;                     // SAFETY: Pause new entries if equity ≤ absolute value (0=off)
input double             Inp_Global_Safety_MinRewardRiskRatio         = 0.0;                     // SAFETY: Reject entries with TP:SL ratio below this (0=off)

input group "=== RM — PORTFOLIO LAYER (account-wide, all charts with this magic; default OFF) ===";
input bool               Inp_Global_Portfolio_Enabled                 = false;                   // PORTFOLIO: master switch (OFF = per-chart sizing, unchanged)
input bool               Inp_Global_Portfolio_VolParity               = false;                   // PORTFOLIO: scale new lot toward equal-risk-per-slot
input int                Inp_Global_Portfolio_TargetSlots             = 6;                       // PORTFOLIO: intended basket size (vol-parity target = MaxAccountRisk/slots)
input double             Inp_Global_Portfolio_MaxAccountRisk          = 6.0;                     // PORTFOLIO: cap on total open risk across ALL charts, %% equity
input double             Inp_Global_Portfolio_MaxCurrencyRisk         = 3.0;                     // PORTFOLIO: cap on net risk per currency (correlation cap), %%

input group " ";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "    🚫 3. ENTRY VETOES — TE side (bar open) — all presets";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
//
// What: "is RIGHT NOW an acceptable moment to execute a TS=1 signal?" — evaluated at shift=0 by EvaluateTE().
//    These never re-evaluate the signal; they only allow or block the order. All hours are BROKER time. Docs:
//    Readme/README_SEA_VETO_REFERENCE.md §1-2, README.md "TE Equation".
//

input group "=== VETO — SESSION / TIME ===";
input bool               Inp_Session_Enabled                          = true;                    // VSession_Enabled: true=only trade in enabled sessions | false=trade 24h
input bool               Inp_Session_London                           = true;                    // VSession_LDN: (09:00–17:00 EET by default)
input int                Inp_Session_London_Margin                    = 1;                       // VSession_LDM_Margin: ±N hours: 0=exact 09-17 · 1→08-18 · 2→07-19
input bool               Inp_Session_NY                               = true;                    // VSession_NY: (14:00–22:00 EET by default)
input int                Inp_Session_NY_Margin                        = 0;                       // VSession_NY_Margin: ±N hours: 0=exact 14-22 · 1→13-23 · 2→12-24
input bool               Inp_Session_Asia                             = false;                   // VSession_TKY: (01:00–09:00 EET by default)
input int                Inp_Session_Asia_Margin                      = 0;                       // VSession_TKY_Margin: ±N hours: 0=exact 01-09 · 1→00-10
input bool               Inp_Session_Win1                             = true;                    // VSession_Win1: (e.g. morning only: 08-12)
input int                Inp_Session_Win1_Start                       = 7;                       // VSession_Win1_Start: (broker time, 0-23)
input int                Inp_Session_Win1_End                         = 12;                      // VSession_Win1_End
input bool               Inp_Session_Win2                             = false;                   // VSession_Win2: (e.g. afternoon: 16-21)
input int                Inp_Session_Win2_Start                       = 16;                      // VSession_Win2_Start: (broker time, 0-23)
input int                Inp_Session_Win2_End                         = 21;                      // VSession_Win2_End
//
// Spread is checked in two layers. VETO SPREAD is the master gate (UseSpread + MaxSpread + retry bars). The PAIR
//    table below is the pair-class-adaptive limit used by GetAdaptiveSpreadLimit(): PairType AUTO detects the
//    class from the symbol name (see DetectPairType at the end of this file); override it per chart if detection
//    is wrong.
//

input group "=== VETO — SPREAD (master) ===";
input bool               Inp_Global_VETO_UseSpread                    = false;                   // VSpread: enable
input int                Inp_Global_VETO_MaxSpreadRetryBars           = 3;                       // VSpread: retry bars (0=unlimited)
input double             Inp_Global_VETO_MaxSpread                    = 3.0;                     // VSpread: max pips

input group "=== VETO — SPREAD LIMIT BY PAIR CLASS (pips; indices in points) ===";
//
// Inp_Adaptive_Spread_Gold — Pair: Max spread gold/XAU (pips) // BUGFIX D1 2026-07: changed 6.0→20.0. XAUUSD
//    spread on MetaQuotes demo (and IC Markets raw) is 12-18 pips at London+NY overlap. The 6.0-pip cap was
//    activating the TE SPREAD VETO on every bar, blocking all XAUUSD TE execution regardless of TS signal quality.
//    20.0 allows entry up to typical peak-session spread; tighten to 15.0 on IC Markets raw once live spread data
//    is available. Inp_Adaptive_Spread_Silver — Pair: Max spread silver/XAG (native XAG pips, pip=0.001) // ADD
//    2026-07: XAG/USD has digits=3, pip=$0.001; IC Markets spread ~$0.03-0.08 = 30-80 native pips. 150 is a
//    permissive ceiling; tighten to 80 once average session spread is observed. Inp_Adaptive_Spread_Indices —
//    Pair: Max spread indices (native index-points) // ADD 2026-07: DAX ~1-3 pts, NAS100 ~2-5 pts, US30 ~1-3 pts,
//    SPX500 ~0.5-1 pt. 20 is a generous ceiling covering all major indices at peak spread; tighten per-instrument
//    via the Inp_Adaptive_PairType override on each chart.
//
input EPairType          Inp_Adaptive_PairType                        = PAIR_TYPE_AUTO;          // Pair: class (AUTO = detect from symbol name)
input double             Inp_Adaptive_Spread_Major                    = 3.0;                     // Pair: Max spread major (pips)
input double             Inp_Adaptive_Spread_Minor                    = 5.0;                     // Pair: Max spread minor (pips)
input double             Inp_Adaptive_Spread_Exotic                   = 11.0;                    // Pair: Max spread exotic (pips)
input double             Inp_Adaptive_Spread_Gold                     = 20.0;                    // Pair: Max spread gold/XAU (pips) — see note above
input double             Inp_Adaptive_Spread_Silver                   = 150.0;                   // Pair: Max spread silver/XAG (native pips, pip=0.001) — see note
input double             Inp_Adaptive_Spread_Indices                  = 20.0;                    // Pair: Max spread indices (native index points) — see note
input double             Inp_Adaptive_Spread_Crypto                   = 50.0;                    // Pair: Max spread crypto (pips)

//
// NEWS VETO (TE gate, shift=0). Blocks new entries from NewsPreMinutes before to NewsPostMinutes after every
//    event that matches the chart pair's BASE or QUOTE currency AND the impact filter. NEWS-SRC 2026-09-10: the
//    event list comes from the MT5 built-in economic calendar (NewsSource AUTO/CALENDAR); the hand-made CSV is a
//    fallback (AUTO) or the sole source (CSV). Resolved ONCE at OnInit and printed as one journal line:
//       [NEWS] source=CALENDAR|CSV|NONE events=N window=-Pre/+Post impact=<enum> tz=server
//    FAIL-OPEN: source=NONE means the veto never blocks even with UseNews=true — the journal says so loudly.
//    Live/demo: the calendar is re-read once per hour (window now-Post .. now+Pre+24h). Strategy Tester: the
//    calendar API is not available by platform design (error 4014), so the tester resolves to CSV-if-readable,
//    otherwise NONE + warning; no re-polling in the tester.
//    CSV contract (NewsFile, in <terminal>\MQL5\Files, NOT Common): header row, 4 columns
//       Date,Event,Impact,Currency   e.g.   "2026, September 12, 14:30",Nonfarm Payrolls,High,USD
//    Date is quoted "YYYY, Month DD, HH:MI" with English month names; Impact high/medium/low; Currency ISO code.
//    CSV times are read as BROKER/SERVER time; NewsCsvTzOffsetMin is ADDED to each CSV time if the file is in
//    another zone (e.g. file in UTC, broker EET summer → +180). Sample file: Readme/calendar_statement.csv.
//
input group "=== VETO — NEWS ===";
input bool               Inp_Global_VETO_UseNews                      = false;                   // VNews: enable
input ENewsSource        Inp_Global_VETO_NewsSource                   = NEWS_SRC_AUTO;           // VNews: source (AUTO = MT5 calendar, CSV fallback)
input ENewsImpactLevel   Inp_Global_VETO_NewsImpactFilter             = NEWS_IMPACT_MED_PLUS;    // VNews: impact
input string             Inp_Global_VETO_NewsFile                     = "calendar_statement.csv"; // VNews: CSV filename
input int                Inp_Global_VETO_NewsPreMinutes               = 60;                      // VNews: block minutes before
input int                Inp_Global_VETO_NewsPostMinutes              = 60;                      // VNews: block minutes after
input int                Inp_Global_VETO_NewsCsvTzOffsetMin           = 0;                       // VNews: CSV time offset to server time (minutes, 0=file already in server time)

input group "=== VETO — TE QUALITY GATES (optional) ===";
input bool               Inp_Global_VETO_TE_RecheckBarClose           = false;                   // Veto TE: re-check price drift vs Close[1]
input int                Inp_Global_VETO_TE_OpenDelaySeconds          = 0;                       // Veto TE: open delay seconds (0=off)
input int                Inp_Global_VETO_TE_SpreadMedianTicks         = 0;                       // Veto TE: spread median filter ticks (0=off)
input double             Inp_Global_VETO_TE_BC_TolerancePips          = 3.0;                     // Veto TE: drift tolerance pips

input group "=== VETO — COOLDOWN (seed defaults; RRM_ORG has its own MinBarsAfterClose) ===";
input int                Inp_Global_MinBarsAfterClose                 = 0;                       // COOLDOWN Global_MinBarsAfterClose: TE: Min bars cooldown (0=off)
input int                Inp_Global_MinBarsAfterWeekendGap            = 2;                       // COOLDOWN Global_MinBarsAfterWeekendGap: TS: Bars skip weekend gap (0=off, recommended 1-2)

input group " ";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "    🔍 4. SIGNAL FILTERS — TS side (bar close) — all presets";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
//
// What: the F factor of TS = B × P × F × L × I (plus the Climax veto), evaluated at shift=1 by EvaluateF(). A
//    blocked bar is a NO-SIGNAL bar, not a delayed one. The pip/ATR thresholds the RRM_ORG filters use live in
//    section 10 (EMA FAN / PRICE EXT). DPI decel/tracking toggles are read by InitializeConfig() under every
//    preset, so they are declared here, outside any preset #ifdef (moved 2026-09-10 from the RRM_ORG block; values
//    unchanged). Docs: README.md "F — Filters", Readme/README_SEA_SIGNAL_REFERENCE_DPI.md §4b/§6b.
//

input group "=== F — OVER-EXTENSION FILTERS ===";
input bool               Inp_Global_F_EmaFanFilterEnabled             = true;                    // F-Filter: EMA-fan over-extension master toggle
input bool               Inp_Global_F_PriceExtFilterEnabled           = true;                    // F-Filter: price-vs-EMA over-extension master toggle

input group "=== F — DPI DECELERATION / TRACKING ===";
input bool               Inp_Global_F_DpiDecelFilterEnabled           = true;                    // F-Filter: DPI GREEN deceleration master toggle (stateless)
input bool               Inp_Global_F_DPI_HistTrackingEnabled         = true;                    // F-Filter: DPI histogram tracking master (prereq for hist-decel block)
input bool               Inp_Global_F_DPI_BlockOnDeceleration         = true;                    // F-Filter: Block on DPI histogram decel (requires hist-tracking on)

input group "=== F — CLIMAX / EXHAUSTION GUARD (checked last) ===";
input bool               Inp_Global_F_ClimaxGuard_Enabled             = false;                    // Climax: F-Filter/ exhaustion-guard master toggle
input int                Inp_Global_ClimaxGuard_Lookback              = 13;                      // Climax: window (bars) scanned for an impulse
input int                Inp_Global_ClimaxGuard_ATRPeriod             = 14;                      // Climax: ATR baseline period (measured pre-impulse)
input double             Inp_Global_ClimaxGuard_BarATRMult            = 2.0;                     // Climax: single-bar range threshold (x ATR)
input double             Inp_Global_ClimaxGuard_MoveATRMult           = 3.0;                     // Climax: cumulative move threshold (x ATR)
//
// Layer-machine guards (L factor, all presets that run the pullback-recovery machine). Guard1 skips the FIRST
//    pullback-recovery after a bias flip — a HYPOTHESIS under A/B, see Readme/README_SEA_TRADE_LOGIC.md §1.2.
//    LayerReset_* clears layer states on a confirmed phase change after N bars.
//

input group "=== F — LAYER GUARDS ===";
input bool               Inp_Global_LayerPullbackEnabled              = true;                    // Layer: run the pullback-recovery state machine
input bool               Inp_Global_LayerS_Require_DirAlign           = true;                    // Layer: LayerS entries also need EMA3 slope aligned with bias
input bool               Inp_Global_Guard1_SkipFirstPostFlipPR        = true;                    // Layer GUARD1: skip first pullback-recovery after a bias flip (hypothesis)
input bool               Inp_Global_LayerReset_OnRealign              = true;                    // Layer: reset pullback states on a confirmed phase change
input int                Inp_Global_LayerReset_PhaseConfirm           = 5;                       // Layer: bars the new phase must hold before that reset (1 = immediate)

input group " ";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "    🎯 5. EXIT MANAGEMENT — TM side — all presets except MA";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
//
// Universal exit add-ons layered on top of each preset's own SL/BE/trail. LPR locks profit at R-multiples
//    (trigger/lock pairs; step 3 optional). Daily target blocks NEW entries once the day's realized P&L reaches
//    the %. TrailEMA period/shift are the engine seeds for TRAIL_EMA; RRM_ORG overrides them in section 10.
//

input group "=== TM — LET PROFIT RUN (R-ladder) ===";
input bool               Inp_Global_LPR_Enabled                       = true;                   // LPR: enable R-ladder profit lock (OFF preserves existing preset exits)
input double             Inp_Global_LPR_Trig1                         = 3.0;                     // LPR: at 3R ...
input double             Inp_Global_LPR_Lock1                         = 2.0;                     // LPR: ... lock 2R
input double             Inp_Global_LPR_Trig2                         = 4.0;                     // LPR: at 4R ...
input double             Inp_Global_LPR_Lock2                         = 3.0;                     // LPR: ... lock 3R
input double             Inp_Global_LPR_Trig3                         = 0.0;                     // LPR: step 3 trigger (0 = off)
input double             Inp_Global_LPR_Lock3                         = 0.0;                     // LPR: step 3 lock

input group "=== TM — DAILY PROFIT TARGET ===";
input bool               Inp_Global_DailyTarget_Enabled               = false;                   // DPT: stop new entries when day's realized P&L hits target
input double             Inp_Global_DailyTarget_Pct                   = 50.0;                    // DPT: target % of day-start balance

input group "=== TM — TRAIL EMA (engine seed) ===";
input int                Inp_Global_TrailEMA_Period                   = 34;                      // Global_TrailEMA_Period: for TRAIL_EMA mode
input int                Inp_Global_TrailEMA_Shift                    = 3;                       // Global_TrailEMA_Shift: 1=current bar, 2=one bar cushion

input group " ";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "    🛡 6. META GATE — ML trade filter (all presets)";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
//
// Optional logistic-regression "second opinion" on trades TS already approved. It can only SKIP or SHRINK a trade
//    — never create one, move a stop, or edit an input. Logic lives in SEA_MetaGate.mqh; only the inputs are here.
//    Workflow (Readme/README_META_SEQUENCE.md): COLLECT → VALIDATE (rrm_validate.py) → TRAIN (rrm_meta.py) → GATE.
//   COLLECT : LogFeatures=true,  Enabled=false → writes TS_events_/TS_outcomes_<PRESET>_<SYM>_<TF>.csv (Common\Files)
//   GATE    : LogFeatures=false, Enabled=true  → loads MetaModel_<PRESET>_<SYM>_<TF>.csv from MQL5\Files
// Both false (default) = today's behaviour, byte-identical. Re-COLLECT after ANY engine or exit change (delete the
//    pair's two CSVs first — the writer de-dups by event_time). One model per preset: keep PresetName in sync.
//

input group "=== META — RUN MODE ===";
input bool               Inp_META_Enabled                             = true;      // META: gate ON — skip/scale trades below model threshold (needs model file)
input bool               Inp_META_LogFeatures                         = false;      // META: COLLECT mode — log every TS=1 + realized outcome to CSV
input string             Inp_META_PresetName                          = "RRM_ORG";  // META: tag in CSV / model file names (one model per preset)

input group "=== META — GATE PARAMETERS ===";
input double             Inp_META_Threshold                           = 0.50;       // META: fallback score threshold when the model file carries none
input bool               Inp_META_SizeByScore                         = false;      // META: scale lots 0.5x..1.5x by model confidence (false = fixed size)

input group "=== META — LEGACY LABEL (fallback only, when no TS_outcomes file exists) ===";
input double             Inp_META_LabelRR                             = 2.5;        // META: legacy fixed RR×SL label (B labels on realized BE-or-profit normally)
input int                Inp_META_LabelBars                           = 34;         // META: legacy fixed time-barrier bars

input group " ";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "    📊 7. VPRR — volume measurement (all presets; NEVER votes)";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
//
// Copied verbatim from the previous layout (2026-09-10). VPRR records readings to SEA_VPRR_<sym>_<tf>.csv and
//    cannot block a trade under any setting. Docs: README.md "VPRR", Readme/README_SEA_VPRR_MEASUREMENT.md.
//
//
// Effective MinRatio = base x TF multiplier (auto-applied at EA start).
// Restart EA after instrument or TF change to auto-update settings.
//
input bool        Inp_VPRR_TF_ReduceRecBars        = true;           // VPRR TF: Reduce RecBars by 1 on H4+ and M5
input int         Inp_VPRR_MinRecoveryBars         = -1;             // VPRR: bars of recovery volume required before the ratio is VALID. -1 = auto (RecoveryBars-1, the legacy derivation); 1-10 = explicit. Separates "how many bars to MEASURE" (RecoveryBars) from "how many before the ratio COUNTS" (this). Added 2026-07-24: previously derived at two sites with no input, so its value was invisible to the operator.
input string      Inp_VPRR_ExternalSymbol          = "";             // VPRR EXTERNAL: proxy symbol for real volume ("GC" gold futures, "MGC" micro gold). Only used when VolumeType=VPRR_VOL_EXTERNAL. Symbol must be in Market Watch.
//
// VPRR is MEASUREMENT-ONLY: it records a reading and cannot block a trade.
// These inputs configure what is measured. None of them can enable a veto.
//
// TWO-KEY GATE. Inp_VPRR_Validated is the second key. VPRR may influence a
// trading decision ONLY when (a) a real-volume source is confirmed AND (b)
// this flag is deliberately set true by an operator who has reviewed logged
// data. It ships false and must never be flipped as a side effect of
// configuring a proxy symbol - that was defect V4. Nothing in the codebase
// reads it as permission to vote today; it exists so that re-arming VPRR is
// an explicit act rather than an accident.
//
input bool        Inp_VPRR_Validated               = false;          // VPRR: thresholds validated against outcome data? (2nd key; ships false - see README "VPRR - measurement-only")
input int         Inp_VPRR_RVOL_Sessions           = 20;             // VPRR RVOL: trailing sessions used for the same-minute-of-day volume baseline (0=disable RVOL)
input int         Inp_VPRR_RVOL_MinSamples         = 5;              // VPRR RVOL: minimum valid samples before RVOL is considered computable
input bool        Inp_VPRR_LogPerSignal            = true;           // VPRR: append a CSV row of raw components on every signal bar (measurement corpus)
//
// RESEARCH TICK MODE. Allows VPRR to MEASURE
// using tick volume when no real volume exists - for DATA COLLECTION ONLY.
//
// WHY THIS IS NOT A REVERSAL OF THE REAL-VOLUME RULE. That rule exists because a
// tick-derived number must never BLOCK A TRADE. VPRR no longer votes, so there is
// no trade to block. The V9 fail-closed rule was calibrated for a voter and, once
// the voter was removed, it stopped protecting a decision and merely prevented
// measurement - blocking the very data collection that would settle whether any
// of this works.
//
// The objection to tick volume is that it is a broker-specific COUNT rather than a
// quantity. RVOL normalisation cancels exactly that: dividing by the same broker's
// own median at the same minute-of-day removes broker scale and leaves relative
// activity. Weaker than real volume, unsigned, and NOT order flow - but testable
// today, on the instrument you actually trade, at zero cost.
//
// HARD INVARIANT: a tick-sourced reading can never influence a decision.
// VPRR_MayInfluenceDecisions() requires a REAL source regardless of this input.
//
input bool        Inp_VPRR_ResearchTickMode        = false;          // VPRR: allow TICK volume for MEASUREMENT/LOGGING only when no real volume exists (never influences a decision)

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
input double      Inp_VPRR_MinRatio_NonFXTick      = 0.8;            // DEPRECATED (V10 2026-07-27): DEAD — no reader. Was a tick-volume fallback threshold; VPRR is real-volume-only, so it can never apply. Kept so existing .set files still load; delete once no live .set references it.

input group "=== VPRR TF ===";
input double      Inp_VPRR_TF_Mult_M5              = 0.85;           // VPRR TF: M5 multiplier (noisier, loosen 15%%)
input double      Inp_VPRR_TF_Mult_M15             = 1.00;           // VPRR TF: M15 multiplier (baseline)
input double      Inp_VPRR_TF_Mult_H1              = 0.95;           // VPRR TF: H1 multiplier (fewer bars, loosen slightly)
input double      Inp_VPRR_TF_Mult_H4Plus          = 0.90;           // VPRR TF: H4+ multiplier (very few cycles, loosen)

input group "=== VPRR VOL ===";
input EVPRRVolumeType Inp_RRM_ORG_VPRR_VolumeType  = VPRR_VOL_AUTO;  // RRM ORG VPRR: AUTO, EXTERNAL, REAL, TICK (Auto=real then tick fallback)
input bool        Inp_RRM_ORG_VPRR_AutoEnable      = false;          // RRM ORG VPRR: Auto-enable VPRR based on instrument type (ON=auto; OFF=use manual Enabled toggle below)
input bool        Inp_RRM_ORG_VPRR_Enabled         = false;          // RRM ORG VPRR: Manual enable (only used when AutoEnable=OFF)
input int         Inp_RRM_ORG_VPRR_RecoveryBars    = 5;              // RRM ORG VPRR: Default recovery bars (1-10); per-instrument overrides in shared block below


input group " ";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "    🖥 8. UI — panels, colours, chart markers";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";

input group "=== UI — ALL PANELS ===";
input int                Inp_UI_PanelFontSize                         = 10;                      // UI: Font size (all panels)
input int                Inp_UI_PanelLineSpacingPx                    = 15;                      // UI: Line spacing px (all panels)
input string             Inp_UI_PanelFont                             = "Arial";                 // UI: Font name (all panels)

input group "=== UI — COCKPIT PANEL ===";
input bool               Inp_UI_ShowCockpitPanel                      = true;                    // UI CP: COCKPIT PANEL
input ENUM_BASE_CORNER   Inp_UI_CockpitCorner                         = CORNER_LEFT_UPPER;       // UI CP: corner
input int                Inp_UI_CockpitX                              = 10;                      // UI CP: Cockpit panel X (px)
input int                Inp_UI_CockpitY                              = 10;                      // UI CP: Cockpit panel Y (px)
input color              Inp_UI_clr_Header                            = clrGold;                 // UI CP: Header Text Color
input color              Inp_UI_clr_Value                             = clrWhite;                // UI CP: Market Data Color
input color              Inp_UI_clr_Pass                              = clrLimeGreen;            // UI CP: Logic PASS Color
input color              Inp_UI_clr_Fail                              = clrOrangeRed;            // UI CP: Logic FAIL Color
input color              Inp_UI_clr_Disabled                          = clrGray;                 // UI CP: Logic DISABLED Color
input color              Inp_UI_clr_Waiting                           = clrYellow;               // UI CP: Logic WAITING Color (aligned, not firing)

input group "=== UI — STATUS PANEL ===";
input bool               Inp_UI_ShowStatusPanel                       = false;                   // UI SP: STATUS PANEL
input bool               Inp_UI_ManageChartIndicators                 = false;                   // UI SP: Auto-add/remove chart indicators
input ENUM_BASE_CORNER   Inp_UI_PanelCorner                           = CORNER_RIGHT_UPPER;      // UI SP: Status panel corner
input int                Inp_UI_PanelX                                = 10;                      // UI SP: Status panel X (px)
input int                Inp_UI_PanelY                                = 10;                      // UI SP: Status panel Y (px)

input group "=== UI — VPRR PANELS ===";
input bool               Inp_UI_ShowVPRRPanel                         = false;                   // UI VPRR panel
input ENUM_BASE_CORNER   Inp_UI_VPRRCorner                            = CORNER_RIGHT_LOWER;      // UI VPRR panel corner
input int                Inp_UI_VPRR_X                                = 10;                      // UI VPRR panel X (px)
input int                Inp_UI_VPRR_Y                                = 10;                      // UI VPRR panel Y (px)
input bool               Inp_UI_ShowVPRRInitPanel                     = true;                    // UI VPRR Init Check panel (startup validation; set false after verified)
input ENUM_BASE_CORNER   Inp_UI_VPRRInitCorner                        = CORNER_RIGHT_LOWER;      // UI VPRR Init Check panel corner
input int                Inp_UI_VPRRInit_X                            = 10;                      // UI VPRR Init Check panel X (px)
input int                Inp_UI_VPRRInit_Y                            = 10;                      // UI VPRR Init Check panel Y (px)

input group "=== UI — FRAME & SIGNAL MARKERS ===";
input EUIFrameMode       Inp_UI_FrameMode                             = UI_FRAME_NONE;           // UI SM: Panel frame mode
input bool               Inp_UI_DrawEntryLines                        = true;                    // UI SM: Draw entry marker lines
input bool               Inp_UI_UseCustomColors                       = true;                    // UI SM: Use custom panel colors
input color              Inp_UI_FontColor                             = clrYellow;               // UI SM: font color
input int                Inp_UI_FramePadPx                            = 6;                       // UI SM: Panel padding (px)

input group "=== UI — SWING / FRACTAL VISUALS ===";
input bool               Inp_UI_ShowSwingMarkers                      = false;                   // UI Vis: Show Swing
input bool               Inp_UI_ShowFractalMarkers                    = true;                    // UI Vis: Show Fractal
input bool               Inp_UI_ShowMarkerLabels                      = false;                   // UI Vis: Show Labels
input int                Inp_UI_MarkerLookback                        = 55;                      // UI Vis: Bars (0 = all history)
input int                Inp_UI_SwingMarkerSize                       = 1;                       // UI Vis: Swing Marker (1-5)
input int                Inp_UI_FractalMarkerSize                     = 1;                       // UI Vis: Fractal marker (1-5)
input color              Inp_UI_SwingHighColor                        = clrCrimson;              // UI Vis: Swing High color
input color              Inp_UI_SwingLowColor                         = clrDodgerBlue;           // UI Vis: Swing Low color
input color              Inp_UI_FractalHighColor                      = clrOrange;               // UI Vis: Fractal High color
input color              Inp_UI_FractalLowColor                       = clrGray;                 // UI Vis: Fractal Low color

input group " ";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "    🐞 9. DEBUG & REPORTING";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
//
// Debug_Flow must be true for DEBUG_SIGNAL output. Stats_FullEvaluation=false = waterfall (stop at first fail);
//    true = evaluate every factor per bar to identify true bottlenecks. Eval window narrows verbose output to a
//    date range or a single bar (0 = off).
//

input group "=== DEBUG — JOURNAL ===";
input EDebugLevel        Inp_Debug_Level                              = DEBUG_SILENT;            // Debug: Level
input bool               Inp_Debug_Flow                               = true;                    // Debug: print OnInit/OnTick/OnDeinit flow (required for DEBUG_SIGNAL)
input bool               Inp_Debug_PrintEffectiveConfig               = true;                    // Debug: Print effective config on init
input bool               Inp_Debug_Stats_FullEvaluation               = true;                    // Stats: Evaluate ALL indicators per bar

input group "=== DEBUG — EVAL WINDOW ===";
input EDebugLevel        Inp_Debug_EvalMode                           = DEBUG_SUMMARY;           // Debug Eval: level to apply
input datetime           Inp_Debug_EvalFrom                           = 0;                       // Debug Eval: from datetime (0=off)
input datetime           Inp_Debug_EvalTo                             = 0;                       // Debug Eval: to datetime (0=off)
input datetime           Inp_Debug_EvalAt                             = 0;                       // Debug Eval: pinpoint bar time (0=off)

input group "=== DEBUG — CSV REPORTING ===";
input bool               Inp_Debug_ExportCSV                          = false;                   // Report: Export CSV reporting
input bool               Inp_Debug_ExportUseCommonFiles               = false;                   // Report: Use terminal Common Files folder

#ifdef SEA_BUILD_RRM_ORG

input group " ";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "    📐 10. PRESET_RRM_ORG ★ ACTIVE — Russ Horn RRM (5/13/34/89)";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
//
// Sub-groups follow the pipeline: B/P (ribbon & phase) → L (layer pullback-recovery, FreshX, UNO Shark) → I (voter
//    ON/OFF, then each voter's parameters) → F (RRM_ORG-owned filter thresholds) → TM (SL, BE, trail, TP, stale
//    exit, DD caps) → TE (re-entry, cooldown, spread retry). Values are the single source of truth — READMEs name
//    the input, not the number. Docs: README.md, Readme/README_SEA_PRESETS.md "PRESET_RRM_ORG",
//    Readme/README_SEA_FRAMEWORK.md Part G, Readme/_SEA-RRM-ORG/_FX-RRM-ORG-Trading_System_v07.md.
//
//
// B — bias is the ribbon order of EMA2/EMA3/EMA4 (TM / EM / UNO, see the Market Phases card). LayerS_TMOnly keeps
//    Strong (34/89) entries out of EMERGING (Trade Setups card: "during the Trending Phase"). UNO_ToleranceBars: a
//    transient UNO flicker that resolves back to the SAME direction within N bars preserves DETECTED/IN-TREND (0 =
//    strict). MinBarsAfterUNOExit delays any DETECTED→IN-TREND edge after UNO ends (0 = off; 2-3 on M1). UNO Shark
//    (manual II.C/III): Layer S may fire in UNORDERED while EMA3/EMA4 are still ordered (13 sandwiched between 34
//    and 89 = failed Emerging / deep pullback); W and M stay blocked in UNO.
//

input group "=== RRM_ORG — B/P: RIBBON & PHASE ===";
input bool               Inp_RRM_ORG_LayerS_TMOnly                    = true;                    // RRM ORG QA: Restrict LayerS (EMA3/EMA4) entries to TRENDING phase only (per canonical RRM);
input bool               Inp_RRM_ORG_UNO_AllowStrongShark             = true;                    // RRM ORG UNO: allow Layer S (Shark) in UNORDERED when EMA3/EMA4 still ordered
input int                Inp_RRM_ORG_Ema1Period                       = 5;                       // RRM ORG QA: EMA1 period
input int                Inp_RRM_ORG_Ema2Period                       = 8;                      // RRM ORG QA: EMA2 period
input int                Inp_RRM_ORG_Ema3Period                       = 34;                      // RRM ORG QA: EMA3 period
input int                Inp_RRM_ORG_Ema4Period                       = 89;                      // RRM ORG QA: EMA4 period
input int                Inp_RRM_ORG_UNO_ToleranceBars                = 2;                       // RRM ORG PB: consecutive UNO bars tolerated before layer states wipe (0=strict)
input int                Inp_RRM_ORG_MinBarsAfterUNOExit              = 2;                       // RRM ORG QA: min bars after UNO exit before a DETECTED→IN-TREND edge (0=off)
//
// L — each layer (W=EMA1/2, M=EMA2/3, S=EMA3/4) runs NONE → DETECTED → IN-TREND on EMA position + slope only (no
//    price term; price is the separate BC/BD gate). Baseline lookback = span of the slope baseline; current pace =
//    slope over lookback/4 bars. Longer lookback = cleaner baseline = easier detection (shorter lookbacks counter-
//    intuitively harm it). FlatRatio: |pace ratio| below this = flat = pullback. AllowReversal counts a slope sign
//    flip as a pullback — the ONLY mechanism that catches shallow pullbacks whose ratio never drops below the
//    threshold; critical on M5/M15. MinPBBars (A21): a pullback cannot complete in one bar. Observation window
//    bounds how long a cycle is tracked. Walk order S → M → W; first eligible layer wins; one entry per pullback-
//    recovery.
//

input group "=== RRM_ORG — L: LAYER PULLBACK-RECOVERY ===";
//
// Inp_RRM_ORG_LayerPBLookback_S — RRM ORG PB: LayerS baseline lookback (slow/stable) // NOTE 2026-07: original
//    value restored. At LB_S=34, a 40%-deep pullback lasting 12 bars still produces ratio=0.507 vs 0.65 threshold
//    = DETECTED. At LB_S=21, same pullback produces ratio=0.609 = DETECTED. At LB_S=8, ratio=N/A (window exhausted
//    by pullback alone).
//
input bool               Inp_RRM_ORG_LayerPBEnabled                   = true;                    // RRM ORG PB: enable the pullback-recovery state machine
input bool               Inp_RRM_ORG_LayerPBAllowReversal             = true;                    // RRM ORG PB: count fast-EMA slope reversal as a pullback (see note)
input bool               Inp_RRM_ORG_AllowLayerS                      = true;                    // RRM ORG PB: allow Layer S (EMA3/4) entries
input bool               Inp_RRM_ORG_AllowLayerM                      = true;                    // RRM ORG PB: allow Layer M (EMA2/3) entries
input bool               Inp_RRM_ORG_AllowLayerW                      = false;                   // RRM ORG PB: allow Layer W (EMA1/2) entries
input group " ";
input int                Inp_RRM_ORG_LayerPBLookback                  = 0;                       // RRM ORG PB: global baseline lookback (0 = use per-layer values below)
input int                Inp_RRM_ORG_LayerPBLookback_W                = 8;                      // RRM ORG PB: LayerW baseline lookback (fast) — see note
input int                Inp_RRM_ORG_LayerPBLookback_M                = 13;                      // RRM ORG PB: LayerM baseline lookback (medium)
input int                Inp_RRM_ORG_LayerPBLookback_S                = 21;                      // RRM ORG PB: LayerS baseline lookback (slow) — see note
input group " ";
input int                Inp_RRM_ORG_LayerPullbackWindow              = 0;                       // RRM ORG PB: global observation window (bars; 0 = per-layer values below)
input int                Inp_RRM_ORG_LayerPullbackWindow_W            = 8;                      // RRM ORG PB: LayerW observation window (bars; 0=use global)
input int                Inp_RRM_ORG_LayerPullbackWindow_M            = 13;                      // RRM ORG PB: LayerM observation window (bars; 0=use global)
input int                Inp_RRM_ORG_LayerPullbackWindow_S            = 21;                      // RRM ORG PB: LayerS observation window (bars; 0=use global)
input group " ";
input int                Inp_RRM_ORG_MinPBBars_W                      = 2;                       // RRM ORG PB: A21 — LayerW min bars in DETECTED before IN-TREND
input int                Inp_RRM_ORG_MinPBBars_M                      = 1;                       // RRM ORG PB: A21 — LayerM min bars in DETECTED before IN-TREND
input int                Inp_RRM_ORG_MinPBBars_S                      = 1;                       // RRM ORG PB: A21 — LayerS min bars in DETECTED before IN-TREND
input double             Inp_RRM_ORG_LayerPBFlatRatio                 = 0.01;                     // RRM ORG PB: Flat threshold (|ratio|<this = flat)
//
// Fresh-trend gate (2026-09, 100-trades study §3.1): a layer fires only on one of the FIRST pullbacks after the
//    cross that started the trend it rides. Reference cross per layer: W → EMA2×EMA3 (the ribbon's own 5/13 pair
//    flips on every pullback, so the next-slower pair is the trend clock); M → EMA2×EMA3 (own pair; a 13/34 cross
//    against bias = UNO = M invalid anyway); S → EMA3×EMA4 (own pair). A "pullback" is the layer machine's own
//    slope-defined event, never a price touch. Caps: W first 2, M first 3, S unlimited (0 = measured for
//    diagnostics, not gated). MaxBars caps are off — pullback counting is fractal, so the rule is the same on M1
//    and D1. No cross inside Lookback = stale. Sharks (S) worked at any trend age in the 100-trade set, hence S
//    unlimited.
//

input group "=== RRM_ORG — L: FRESH-TREND GATE (FreshX) ===";
input bool               Inp_RRM_ORG_FreshX_Enabled                   = true;                    // RRM ORG FreshX: enable fresh-trend (first-pullback) gate
input EFreshXPair        Inp_RRM_ORG_FreshX_RefPair_W                 = FRESHX_EMA2x4;           // RRM ORG FreshX: LayerW reference cross (next-slower pair 13/34)
input EFreshXPair        Inp_RRM_ORG_FreshX_RefPair_M                 = FRESHX_EMA2x4;           // RRM ORG FreshX: LayerM reference cross (own pair 13/34)
input EFreshXPair        Inp_RRM_ORG_FreshX_RefPair_S                 = FRESHX_EMA3x4;           // RRM ORG FreshX: LayerS reference cross (own pair 34/89)
input int                Inp_RRM_ORG_FreshX_MaxPullbacks_W            = 2;                       // RRM ORG FreshX: LayerW max slope-pullbacks since cross (0=unlimited)
input int                Inp_RRM_ORG_FreshX_MaxPullbacks_M            = 1;                       // RRM ORG FreshX: LayerM max slope-pullbacks since cross (0=unlimited)
input int                Inp_RRM_ORG_FreshX_MaxPullbacks_S            = 0;                       // RRM ORG FreshX: LayerS max slope-pullbacks since cross (0=unlimited)
input int                Inp_RRM_ORG_FreshX_MaxBars_W                 = 0;                       // RRM ORG FreshX: LayerW max bars since cross (0=off; ~40 = tally cut-off)
input int                Inp_RRM_ORG_FreshX_MaxBars_M                 = 0;                       // RRM ORG FreshX: LayerM max bars since cross (0=off)
input int                Inp_RRM_ORG_FreshX_MaxBars_S                 = 0;                       // RRM ORG FreshX: LayerS max bars since cross (0=off)
input int                Inp_RRM_ORG_FreshX_Lookback                  = 300;                     // RRM ORG FreshX: scan window bars (no cross inside = stale)
//
// I — unanimous AND of every enabled voter (VOTE_MODE_ALL). RRM_ORG core: DPI + PSAR + CandleBody + MTF. Disabled
//    voters contribute 1. VPRR never votes (section 7). Parameters for each voter follow below.
//

input group "=== RRM_ORG — I: VOTERS ON / OFF ===";
input bool               Inp_RRM_ORG_DPI_Enabled                      = true;                    // RRM ORG DPI: Enable DPI vote in TS equation
input bool               Inp_RRM_ORG_Use_Psar                         = false;                    // RRM ORG Ind: PSAR vote
input bool               Inp_RRM_ORG_Use_CandleBody                   = false;                    // RRM ORG Ind: CBody vote
input bool               Inp_RRM_ORG_Use_MTF                          = true;                    // RRM ORG Ind: MTF/HTF vote
input bool               Inp_RRM_ORG_Use_Adx                          = false;                   // RRM ORG Ind: ADX vote
input bool               Inp_RRM_ORG_Use_Atr                          = false;                   // RRM ORG Ind: ATR vote
input bool               Inp_RRM_ORG_Use_Bb                           = false;                   // RRM ORG Ind: BB vote
input bool               Inp_RRM_ORG_Use_Cci                          = false;                   // RRM ORG Ind: CCI vote
input bool               Inp_RRM_ORG_Use_CI                           = false;                   // RRM ORG Ind: CI vote
input bool               Inp_RRM_ORG_Use_Macd                         = false;                   // RRM ORG Ind: MACD vote
input bool               Inp_RRM_ORG_Use_Mfi                          = false;                   // RRM ORG Ind: MFI vote
input bool               Inp_RRM_ORG_Use_P123                         = false;                   // RRM ORG Ind: P123
input bool               Inp_RRM_ORG_Use_Ross                         = false;                   // RRM ORG Ind: Ross vote
input bool               Inp_RRM_ORG_Use_Rsi                          = false;                   // RRM ORG Ind: RSI vote
input bool               Inp_RRM_ORG_Use_Stoch                        = false;                   // RRM ORG Ind: STO vote
input bool               Inp_RRM_ORG_Use_VRC                          = false;                   // RRM ORG Ind: VRC vote
//
// DPI (Dynamic Price Index) — the momentum voter. Blue = EMA(fast) − EMA(slow); Red = EMA(RedSignalType) of Blue;
//    hist = Blue − Red. Ribbon colour drives the vote: YELLOW = BUY, RED = SELL. With UseCCIReset the CCI sign
//    sets the colour (a CCI flip against trend = a "reset"); IgnoreCCIForVote falls back to raw hist direction.
//    GREEN = Blue and hist on the same side of zero (momentum confirmation); UseGreenHist requires it. DpiDiv
//    blocks on price-vs-histogram divergence over DpiDivLookback bars. Canonical logic:
//    Readme/README_SEA_SIGNAL_REFERENCE_DPI.md.
//

input group "=== RRM_ORG — I: DPI CALCULATION ===";
input ENUM_APPLIED_PRICE Inp_RRM_ORG_DPI_CCI_Price                    = PRICE_TYPICAL;           // RRM ORG DPI: CCI applied price
input int                Inp_RRM_ORG_DPI_MacdFast                     = 8;                       // RRM ORG DPI: MACD fast EMA period
input int                Inp_RRM_ORG_DPI_MacdSlow                     = 13;                      // RRM ORG DPI: MACD slow EMA period
input int                Inp_RRM_ORG_DPI_RedSignalType                = 3;                       // RRM ORG DPI: Red line type (1=EMA_A 2=EMA_B 3=EMA_C 4=EMA_D 5=Double)
input int                Inp_RRM_ORG_DPI_RedEMA_A                     = 5;                       // RRM ORG DPI: Red EMA period A (type 1)
input int                Inp_RRM_ORG_DPI_RedEMA_B                     = 8;                       // RRM ORG DPI: Red EMA period B (type 2)
input int                Inp_RRM_ORG_DPI_RedEMA_C                     = 13;                      // RRM ORG DPI: Red EMA period C (type 3, default)
input int                Inp_RRM_ORG_DPI_RedEMA_D                     = 21;                      // RRM ORG DPI: Red EMA period D (type 4)
input int                Inp_RRM_ORG_DPI_DoubleSmoothFirst            = 5;                       // RRM ORG DPI: Double-smooth first EMA
input int                Inp_RRM_ORG_DPI_DoubleSmoothSecond           = 8;                       // RRM ORG DPI: Double-smooth second EMA
input int                Inp_RRM_ORG_DPI_CCI_Period                   = 13;                      // RRM ORG DPI: CCI period

input group "=== RRM_ORG — I: DPI VOTE ===";
input bool               Inp_RRM_ORG_DPI_UseCCIReset                  = true;                    // RRM ORG DPI: CCI can reset ribbon color (trend filter)
input bool               Inp_RRM_ORG_DPI_IgnoreCCIForVote             = false;                   // RRM ORG DPI: Skip CCI check — vote on raw histogram direction only
input bool               Inp_RRM_ORG_DPI_UseGreenHist                 = false;                    // RRM ORG DPI: Also require GREEN overlay for vote pass
input bool               Inp_RRM_ORG_DpiDiv                           = false;                   // RRM ORG DPI: Require price-vs-DPI-histogram divergence (off by default)
input int                Inp_RRM_ORG_DpiDivLookback                   = 55;                      // RRM ORG DPI: Divergence detection window in bars (two non-overlapping windows)
//
// CCI RESET→RECOVERY entry gate (RequireResetRecovery). The entry pipeline tracks the reset lifecycle:
//   1 IDLE — ribbon colour correct for bias, waiting for a reset;  2 RESET_DETECTED — colour flipped against
//   trend (pullback);  3 RECOVERY_COUNTING — colour flipped back, counting bars;  4 ENTRY_ALLOWED — recovery held
//   for ResetRecoveryBars (0 = immediate, 1 = confirms it is not a one-bar fake, 2+ = stricter).
// Entries then happen only AFTER a proven pullback where the trend survived. ResetRequireGreen also demands GREEN
//    to reappear during recovery. GrantFirstEntry lets the first trade after start skip the wait (no effect when
//    the gate is off). History note on RequireResetRecovery: [SYNC 2026-06-04: true→false to match SignalScan,
//    which never seeds this gate (zero-init=false). JUDGMENT CALL] — current committed default is shown on the
//    line.
//

input group "=== RRM_ORG — I: DPI RESET → RECOVERY GATE ===";
input bool               Inp_RRM_ORG_DPI_RequireResetRecovery         = true;                    // RRM ORG DPI: require a CCI reset→recovery cycle before entry (see note)
input bool               Inp_RRM_ORG_DPI_GrantFirstEntry              = false;                   // RRM ORG DPI: first trade after start may skip the reset→recovery wait
input int                Inp_RRM_ORG_DPI_ResetRecoveryBars            = 1;                       // RRM ORG DPI: Recovery bars after CCI flip-back (0=immediate)
input bool               Inp_RRM_ORG_DPI_ResetRequireGreen            = false;                   // RRM ORG DPI: Also require GREEN reappearance during recovery
//
// DPI TRACKING subsystem — a separate CCI-value deceleration system (not ribbon/GREEN). Master switch is
//    Inp_Global_F_DPI_HistTrackingEnabled (section 4); when OFF everything below is inactive. Growth_Boost lets
//    GREEN/CCI growth override a failed layer-momentum check. ExitOnHistDisappear closes open trades when the CCI
//    trend flips (GREEN vanished = OB/OS); ExitThreshold closes when |CCI| drops below it (0 = off).
//

input group "=== RRM_ORG — I: DPI TRACKING & EXITS (need tracking ON) ===";
input bool               Inp_RRM_ORG_DPI_Histogram_Growth_Boost       = false;                   // RRM ORG DPI: Use histogram growth as layer momentum boost (needs tracking ON)
input bool               Inp_RRM_ORG_DPI_ExitOnHistDisappear          = false;                   // RRM ORG DPI: Close trades when CCI trend flips (needs tracking ON)
input int                Inp_RRM_ORG_DPI_HistDecelLookback            = 3;                       // RRM ORG DPI: CCI deceleration lookback bars (needs tracking ON)
input double             Inp_RRM_ORG_DPI_HistMomentumThreshold        = 0.0001;                  // RRM ORG DPI: Ignore CCI-delta below this (needs tracking ON)
input double             Inp_RRM_ORG_DPI_ExitThreshold                = 0.0;                     // RRM ORG DPI: Exit when |CCI| below threshold, 0=disable (needs tracking ON)
//
// PSAR vote — dot must be on the bias side of the candle BODY at shift=1 (absolute, no grace). With AllowPsarFlip
//    a flip window is then applied: -1 = persistent (dot side only, no recency test) | 0 = flip must fall on this
//    bar | 1..10 = flip within the last N closed bars. The dot-side test runs FIRST, so a window can only make an
//    already- correct-side dot stricter — never admit a wrong-side one. KNOWN PROPERTY of any window mode (>= 0):
//    once the dot has been correctly-sided for longer than the window there is no opposite-side bar left in it, so
//    PSAR fails PSAR_FLIP_STALE until the next flip — a window expires the vote inside a sustained trend (observed
//    2026-07 on M5). Accepted cost of a freshness gate, not a defect. Per-layer overrides take precedence whenever
//    they are not -99 (resolved by GetEffectivePsarFlipDelay). Rationale: W is the fastest pair and most exposed
//    to whipsaw right after re-entry (window it tighter); M is already confirmed by EMA13/34 alignment and S is
//    the slowest, highest- conviction pair (persistent is defensible; windowing them is uniformity — neither is
//    derived). Runtime ground truth is the [PSAR_RESOLVED] startup line and the cockpit PSAR row, which read live
//    Settings — not this source default, which the MT5 dialog can override. Chart PSAR must use the same Step/Max
//    to show the dots the EA votes on.
//

input group "=== RRM_ORG — I: PSAR ===";
input bool               Inp_RRM_ORG_Vote_AllowPsarFlip               = true;                    // RRM ORG PSAR: PSAR Enable Flip
input int                Inp_RRM_ORG_Vote_PsarFlipDelay               = -1;                      // RRM ORG PSAR: global flip window: -1 persistent | 0 this bar | 1..10 last N bars
input int                Inp_RRM_ORG_PsarFlipDelay_W                  = 3;                       // RRM ORG PSAR: LayerW window override (-99 = use global)
input int                Inp_RRM_ORG_PsarFlipDelay_M                  = 4;                       // RRM ORG PSAR: LayerM window override (-99 = use global)
input int                Inp_RRM_ORG_PsarFlipDelay_S                  = 5;                       // RRM ORG PSAR: LayerS window override (-99 = use global)
input double             Inp_RRM_ORG_PsarStep                         = 0.08;                    // RRM ORG PSAR: PSAR Step
input double             Inp_RRM_ORG_PsarMax                          = 0.5;                     // RRM ORG PSAR: PSAR Max
//
// MTF — higher-timeframe confirmation voter. TF1 must be higher than the chart TF (4:1 rule of thumb: M1→M5+M15,
//    M5→M15+H1, M15→H1+H4, H1→H4+D1); TF2 = PERIOD_CURRENT means single-HTF. EMA pair 34/89 = the HTF S-pair
//    (2026-09: was 21/21 legacy single-EMA slope; 34/89 is also required for MTF FreshX). RequirePhase: HTF ribbon
//    must be trending. MTF FreshX ("nested fresh trend"): an S trade is taken only if TF1 is itself young — its
//    own 34/89 cross within Lookback TF1 bars and at most MaxPullbacks slope-pullbacks since; TF2 confirms
//    direction only unless ApplyTF2. Layers: 0 = all, 1 = W, 2 = M, 3 = S. [2026-09 PY test: as a VETO it removed
//    good trades on H1/M1 — keep OFF and read the [MTF-FreshX] diag as a grade tag.]
//

input group "=== RRM_ORG — I: MTF (higher timeframe) ===";
input bool               Inp_RRM_ORG_MTF_RequirePhase                 = true;                    // RRM ORG MTF: require trending HTF
input ENUM_TIMEFRAMES    Inp_RRM_ORG_MTF_TF1                          = PERIOD_M15;               // RRM ORG MTF: TF1 (primary)
input ENUM_TIMEFRAMES    Inp_RRM_ORG_MTF_TF2                          = PERIOD_H1;              // RRM ORG MTF: TF2 (PERIOD_CURRENT = single TF)
input int                Inp_RRM_ORG_MTF_EMA_Fast                     = 34;                      // RRM ORG MTF: fast EMA period (34 = HTF S-pair; 21/21 = legacy slope)
input int                Inp_RRM_ORG_MTF_EMA_Slow                     = 89;                      // RRM ORG MTF: slow EMA period (89; needed for MTF FreshX)

input group "=== RRM_ORG — I: MTF FRESH-TREND (nested FreshX on TF1) ===";
input bool               Inp_RRM_ORG_MTF_FreshX_Enabled               = true;                   // RRM ORG MTF FreshX: require TF1 in its first pullbacks after its cross (see note)
input bool               Inp_RRM_ORG_MTF_FreshX_ApplyTF2              = false;                   // RRM ORG MTF FreshX: also require the young structure on TF2
input int                Inp_RRM_ORG_MTF_FreshX_Layers                = 3;                       // RRM ORG MTF FreshX: apply to 0=all layers | 1=W | 2=M | 3=S only
input int                Inp_RRM_ORG_MTF_FreshX_MaxPullbacks          = 2;                       // RRM ORG MTF FreshX: max TF1 slope-pullbacks since its cross (0=unlimited)
input int                Inp_RRM_ORG_MTF_FreshX_MaxBars               = 0;                       // RRM ORG MTF FreshX: max TF1 bars since its cross (0=off)
input int                Inp_RRM_ORG_MTF_FreshX_Lookback              = 200;                     // RRM ORG MTF FreshX: TF1 scan window in TF1 bars
input int                Inp_RRM_ORG_MTF_FreshX_PBLookback            = 13;                      // RRM ORG MTF FreshX: TF1 slope baseline lookback (S-layer default)
//
// CandleBody — blocks over-extended signal bars (body > MaxMult × average of AvgPeriod bars), optionally requires
//    the bar to close in the bias direction and in its top/bottom (1-MinCloseRatio) of range (0.75 = TopInvestor
//    rule). [SYNC 2026-06-04: AvgPeriod 5→14, MaxMult 4.0→3.0 to match SignalScan.] BarClose (BC/"CC") — close
//    must be beyond the layer's fast EMA; PipTolerance admits closes within N pips (0 = strict);
//    Progressive_Momentum requires progress over the last LookbackBars.
//

input group "=== RRM_ORG — I: CANDLE BODY ===";
input bool               Inp_RRM_ORG_CandleBody_RequireDir            = true;                    // RRM ORG CBody: CBody Require direction
input int                Inp_RRM_ORG_CandleBody_AvgPeriod             = 14;                      // RRM ORG CBody: average period
input double             Inp_RRM_ORG_CandleBody_MaxMult               = 3.0;                     // RRM ORG CBody: max multiplier of average body
input double             Inp_RRM_ORG_CandleBody_MinCloseRatio         = 0.75;                    // RRM ORG CBody: Min close ratio (0=off, 0.75=TopInvestor — rejects doji-like signal bars)

input group "=== RRM_ORG — I: BAR CLOSE (BC) ===";
input bool               Inp_RRM_ORG_BarClose_Require_Progressive_Momentum = true;               // RRM ORG CC: Momentum
input int                Inp_RRM_ORG_BarClose_LookbackBars            = 5;                       // RRM ORG CC: Lookback (1-4 bars)
input double             Inp_RRM_ORG_BarClose_PipTolerance            = 0.0;                     // RRM ORG CC: Allow N pips of target EMA (0=strict close>EMA)
//
// Optional voters — all OFF in RRM_ORG by default; parameters apply only when the matching Use_* toggle is on.
//

input group "=== RRM_ORG — I: ADX ===";
input EADXMode           Inp_RRM_ORG_Adx_Mode                         = ADX_MODE_STATIC;         // RRM ORG ADX: ADX Mode
input int                Inp_RRM_ORG_AdxPeriod                        = 14;                      // RRM ORG ADX: ADX Period
input int                Inp_RRM_ORG_Adx_Lookback                     = 55;                      // RRM ORG ADX: ADX Lookback bars
input int                Inp_RRM_ORG_Adx_PercentileRefreshSec         = 14400;                   // RRM ORG ADX: DYNAMIC_PERCENTILE refresh sec (M1: 900; H1+: 14400)
input double             Inp_RRM_ORG_AdxThreshold                     = 20.0;                    // RRM ORG ADX: ADX Threshold
input double             Inp_RRM_ORG_Adx_Percentile                   = 50.0;                    // RRM ORG ADX: ADX Percentile
input double             Inp_RRM_ORG_Adx_Thr_Accum                    = 12.0;                    // RRM ORG ADX: ADX Thr Accumulation
input double             Inp_RRM_ORG_Adx_Thr_Trending                 = 25.0;                    // RRM ORG ADX: ADX Thr Trending
input double             Inp_RRM_ORG_Adx_Thr_Distrib                  = 18.0;                    // RRM ORG ADX: ADX Tht Distribution

input group "=== RRM_ORG — I: ATR ===";
input int                Inp_RRM_ORG_P_Atr                            = 14;                      // RRM ORG ATR: ATR period (used when ATR voter enabled)
input double             Inp_RRM_ORG_ATR_VoteMinPips                  = 5.0;                     // RRM ORG ATR: min ATR pips to allow trade
input double             Inp_RRM_ORG_ATR_VoteMaxPips                  = 50.0;                    // RRM ORG ATR: max ATR pips to allow trade

input group "=== RRM_ORG — I: BOLLINGER ===";
input EBbMode            Inp_RRM_ORG_Bb_Mode                          = BB_TREND_FOLLOW;         // RRM ORG BB: BB Mode
input int                Inp_RRM_ORG_Bb_Period                        = 20;                      // RRM ORG BB: BB Period
input double             Inp_RRM_ORG_Bb_Deviation                     = 2.0;                     // RRM ORG BB: BB Deviation

input group "=== RRM_ORG — I: CCI ===";
input ECciMode           Inp_RRM_ORG_CciMode                          = CCI_TREND_ZERO;          // RRM ORG CCI: CCI Mode
input int                Inp_RRM_ORG_CciPeriod                        = 20;                      // RRM ORG CCI: period (20 = SignalScan parity; voter OFF by default)

input group "=== RRM_ORG — I: CHOPPINESS (CI) ===";
input int                Inp_RRM_ORG_CiPeriod                         = 14;                      // RRM ORG CI: CI Period
input double             Inp_RRM_ORG_CiRangingThreshold               = 61.8;                    // RRM ORG CI: CI Threshold

input group "=== RRM_ORG — I: MACD ===";
input bool               Inp_RRM_ORG_MacdSlope                        = false;                   // RRM ORG MACD: SLOPE
input bool               Inp_RRM_ORG_MacdDiv                          = false;                   // RRM ORG MACD: DIVERGENCE block on trend-exhaustion divergence (price HH, MACD LH; mirror SHORT)
input int                Inp_RRM_ORG_MacdDivLookback                  = 10;                      // RRM ORG MACD: DIV LOOKBACK detection window in bars (two non-overlapping windows of this size)
input int                Inp_RRM_ORG_MacdFast                         = 8;                       // RRM ORG MACD: FAST
input int                Inp_RRM_ORG_MacdSlow                         = 13;                      // RRM ORG MACD: SLOW
input int                Inp_RRM_ORG_MacdSig                          = 5;                       // RRM ORG MACD: SIGNAL
input int                Inp_RRM_ORG_MacdFreshBars                    = 3;                       // RRM ORG MACD: fresh bars since last zero-cross to be "fresh"
input double             Inp_RRM_ORG_MacdSlopeMin                     = 0.00001;                 // RRM ORG MACD: minimum histogram slope magnitude

input group "=== RRM_ORG — I: MFI ===";
input int                Inp_RRM_ORG_Mfi_Period                       = 14;                      // RRM ORG MFI: MFI Period
input double             Inp_RRM_ORG_Mfi_OB                           = 80.0;                    // RRM ORG MFI: MFI Overbought
input double             Inp_RRM_ORG_Mfi_OS                           = 20.0;                    // RRM ORG MFI: MFI Oversold

input group "=== RRM_ORG — I: RSI ===";
input ERsiMode           Inp_RRM_ORG_RsiMode                          = RSI_TREND_ABOVE_50;      // RRM ORG RSI: RSI Mode
input int                Inp_RRM_ORG_RsiPeriod                        = 14;                      // RRM ORG RSI: RSI Period
input double             Inp_RRM_ORG_Rsi_OB                           = 70.0;                    // RRM ORG RSI: RSI Overbought
input double             Inp_RRM_ORG_Rsi_OS                           = 30.0;                    // RRM ORG RSI: RSI Oversold

input group "=== RRM_ORG — I: STOCHASTIC ===";
input EStochMode         Inp_RRM_ORG_Sto_Mode                         = STO_CROSS_SIGNAL;        // RRM ORG STO: Sto Mode
input int                Inp_RRM_ORG_Sto_K                            = 5;                       // RRM ORG STO: Sto K period
input int                Inp_RRM_ORG_Sto_D                            = 3;                       // RRM ORG STO: Sto D period
input int                Inp_RRM_ORG_Sto_Slow                         = 3;                       // RRM ORG STO: Sto Slowing period
input double             Inp_RRM_ORG_Sto_OB                           = 80.0;                    // RRM ORG STO: Sto Overbought
input double             Inp_RRM_ORG_Sto_OS                           = 20.0;                    // RRM ORG STO: Sto Oversold

input group "=== RRM_ORG — I: VRC (volatility regime) ===";
input int                Inp_RRM_ORG_VRC_Lookback                     = 100;                     // RRM ORG VRC: lookback bars for regime classification
input int                Inp_RRM_ORG_VRC_RefreshSec                   = 14400;                   // RRM ORG VRC: percentile refresh interval (sec). M1: try 900; H1+: 14400 (4h)
input double             Inp_RRM_ORG_VRC_LowThreshold                 = 33.0;                    // RRM ORG VRC: low-volatility percentile threshold
//
// F — thresholds for the global filters of section 4. EMA fan: block when the EMA1–EMA4 spread exceeds the per-TF
//    pips (or MaxPct of price when > 0; universal); JpyGateMultiplier scales the pip gates on JPY pairs (1.0 =
//    off). Price over-extension: block if |close − refEMA| > MaxATR × ATR(period) — Oracle "Early Entry": too far
//    from the MA.
//

input group "=== RRM_ORG — F: EMA FAN OVER-EXTENSION ===";
input double             Inp_RRM_ORG_EmaFan_M5Pips                    = 25.0;                    // RRM ORG Fan: pips <M5
input double             Inp_RRM_ORG_EmaFan_M30Pips                   = 40.0;                    // RRM ORG Fan: pips <M30
input double             Inp_RRM_ORG_EmaFan_H1Pips                    = 60.0;                    // RRM ORG Fan: pips H1
input double             Inp_RRM_ORG_EmaFan_H4Pips                    = 100.0;                   // RRM ORG Fan: pips H4
input double             Inp_RRM_ORG_EmaFan_DailyPips                 = 180.0;                   // RRM ORG Fan: pips D1+
input double             Inp_RRM_ORG_EmaFan_MaxPct                    = 0.0;                     // RRM ORG Fan: max gap % of price (>0 overrides pips; universal for all instruments)
input double             Inp_RRM_ORG_JpyGateMultiplier                = 1.3;                     // RRM ORG Fan: JPY Gate Multiplier (1.0=disabled)

input group "=== RRM_ORG — F: PRICE OVER-EXTENSION ===";
input int                Inp_RRM_ORG_PriceExtRefEma                   = 3;                       // RRM ORG OverExt: ref EMA 1..4 (1=5 2=13 3=34 4=89)
input int                Inp_RRM_ORG_PriceExtAtrPeriod                = 14;                      // RRM ORG OverExt: ATR period for distance
input double             Inp_RRM_ORG_PriceExtMaxATR                   = 2.5;                     // RRM ORG OverExt: block if |close-refEMA| > this x ATR
//
// TM — SL INITIAL. SLMode: SL_MODE_SWING = recent swing high/low within SwingLookback bars (+ TF cushion);
//    SL_MODE_ATR = swing anchor − ATR(period)×mult (prevents under-sized SL on Gold/indices; 0.5–1.5 typical, Gold
//    M15 1.0–1.5); SL_MODE_PSAR_DOT = current PSAR dot + cushion (Oracle alternative, FX); SL_MODE_FRACTAL;
//    SL_MODE_FIXED_PIPS; SL_MODE_PERCENT. SwingLookback is a SEARCH WINDOW, not an exact bar: larger = more likely
//    to find a structurally meaningful level (34 bars: M1=34min · M5=170min · H1=34h; a swing 15 bars back is
//    missed by window 13, found by 34). Guide: M5 21-34, M15 34-55, H1 55-89, H4 89-144. Oracle: manual IV.A "a
//    few pips beyond the most recent swing".
//

input group "=== RRM_ORG — TM: STOP LOSS (initial) ===";
input ESLMode            Inp_RRM_ORG_SLMode                           = SL_MODE_SWING;           // RRM ORG SL: SL_MODE_=*: *ATR, *FIXED_PIPS, *FRACTAL, *PERCENT, *PSAR_DOT, *SWING
input int                Inp_RRM_ORG_SwingLookback                    = 21;                      // RRM ORG SL: SWING search window (bars) for the most recent swing — see note
input int                Inp_RRM_ORG_SL_AtrPeriod                     = 14;                      // RRM ORG SL: ATR period (SL_MODE_ATR only)
input double             Inp_RRM_ORG_SL_AtrMult                       = 1.0;                     // RRM ORG SL: ATR multiplier — SL = swing_anchor − ATR×N (SL_MODE_ATR only)
//
// TM — BREAK-EVEN. Mode: BE_MODE_OFF | BE_MODE_R_MULTIPLE (SL to entry+buffer at X× initial risk; Oracle = 0.7R,
//    ~70% of the initial stop — Stop Loss card, manual IV.E) | BE_MODE_TP_PROGRESS_PCT (at X% of the path to TP).
//    TriggerSource = which price sample fires it: BE_SRC_TICK (Oracle: an intrabar TOUCH is enough, evaluated
//    every tick) | BE_SRC_BAR_EXTREME (closed bar high/low, one bar late) | BE_SRC_BAR_CLOSE (legacy, misses
//    intrabar touches). The lock is one-time per ticket; buffer pips are TF-adaptive via GetTFBasedCushion().
//

input group "=== RRM_ORG — TM: BREAK-EVEN ===";
input EBeMode            Inp_RRM_ORG_BE_Mode                          = BE_MODE_R_MULTIPLE;      // RRM ORG BE: Breakeven trigger mode
input EBeTriggerSource   Inp_RRM_ORG_BE_TriggerSource                 = BE_SRC_BAR_CLOSE;        // RRM ORG BE: price sample — TICK (Oracle touch) / BAR_EXTREME / BAR_CLOSE (legacy)
input double             Inp_RRM_ORG_BE_RMultiple                     = 0.70;                    // RRM ORG BE: BE trigger as R multiple
input double             Inp_RRM_ORG_BE_ProgressPct                   = 25.0;                    // RRM ORG BE: BE trigger as TP progress %
//
// TM — TRAIL METHOD (how the stop moves): TRAIL_PSAR = follow PSAR dots + cushion (Oracle default) | TRAIL_EMA =
//    behind a ribbon EMA (role/period/shift + cushion) | TRAIL_SWING | TRAIL_FRACTAL | TRAIL_FIXED_PIPS
//    (TrailStepPips) | TRAIL_PROFIT_PERCENT = Let-Profit-Run, X% behind the peak profit (TrailProfitPercentLPR) |
//    TRAIL_NONE (BE-lock only). TRAIL_PSAR_FLIP_EXIT is a HARD EXIT handled in EvaluateTM, not a trail method.
//    PSAR cushion: PIPS = fixed × pipSize | ATR = ATR(period) × mult (volatility-aware, default) | PERCENT of
//    price. EMA trail: period 0 = use the ribbon role; shift 1 = last closed bar; CushionPips 0 = use the ATR
//    cushion (mult 0 = disabled; 0.1 recommended). TrailPsarDotShift reads the dot 1–3 bars back.
//

input group "=== RRM_ORG — TM: TRAIL METHOD & CUSHION ===";
input ETrailingMode      Inp_RRM_ORG_TrailMode                        = TRAIL_EMA;               // RRM ORG TS METHOD: PSAR(Oracle) / EMA / SWING / FRACTAL / FIXED_PIPS / PROFIT_PERCENT / NONE
input EPsarTrailCushionMode Inp_RRM_ORG_PSAR_TrailCushionMode         = PSAR_CUSHION_ATR;     // RRM ORG TS: PSAR cushion mode (PIPS / ATR / PERCENT)
input EEmaRole           Inp_RRM_ORG_TrailEMA_RibbonRole              = ROLE_EMA3;               // RRM ORG TS: which ribbon EMA to trail (EMA1=5,EMA2=13,EMA3=34,EMA4=89) when Period=0
input group " ";
input int                Inp_RRM_ORG_TrailPsarDotShift                = 3;                       // RRM ORG QA: PSAR trail shift (1–3 bars back)
input group " ";
input double             Inp_RRM_ORG_TrailStepPips                    = 5.0;                     // RRM ORG TS: step size for fixed-step trail modes
input double             Inp_RRM_ORG_TrailCushionPct                  = 25.0;                    // RRM ORG TS: cushion % of price (PERCENT mode + safety floor)
input double             Inp_RRM_ORG_TrailProfitPercentLPR            = 25.0;                    // RRM ORG TS: LPR trailing percent behind peak
input group " ";
input int                Inp_RRM_ORG_TrailCushionAtrPeriod            = 14;                      // RRM ORG TS: ATR period (ATR mode)
input double             Inp_RRM_ORG_TrailCushionAtrMult              = 2.0;                     // RRM ORG TS: cushion ATR multiplier (cushion = ATR × this)
input group " ";
input int                Inp_RRM_ORG_TrailEMA_Period                  = 0;                       // RRM ORG TS: EMA period (0=use ribbon role selector below)
input int                Inp_RRM_ORG_TrailEMA_Shift                   = 1;                       // RRM ORG TS: bar shift for EMA read (1=last closed bar, 2=two bars back, 3=three bars back)
input int                Inp_RRM_ORG_TrailEMA_CushionAtrPeriod        = 14;                      // RRM ORG TS: ATR period for EMA cushion
input double             Inp_RRM_ORG_TrailEMA_CushionPips             = 0.0;                     // RRM ORG TS: EMA trail cushion pips (0=use ATR mode)
input double             Inp_RRM_ORG_TrailEMA_CushionAtrMult          = 0.3;                     // RRM ORG TS: EMA cushion = ATR×this (0=disabled; 0.1=recommended)
//
// TM — TRAIL START & FLAGS (when trailing begins, separate axis from the method). TrailTrigger: TRIGGER_IMMEDIATE
//    (Oracle: from entry) | BREAKEVEN | PROFIT_PERCENT(R) | PROFIT_PIPS | PSAR_ALIGN — now LIVE on the RRM path
//    (was read only on SIMPLE profiles). TrailStartsAfterBE: hold the trail back until BE fires — the Oracle
//    (manual IV.B) starts trailing as soon as the trade moves in your favour, so FALSE is the Oracle-conformant
//    value; TRUE = pre-2026-07 behaviour. TrailAllowLossSide: let the trail tighten the SL while it is STILL AT A
//    LOSS (Stop Loss card: "Move Stop Loss Towards Entry"); FALSE = SL frozen at its initial level until BE
//    (pre-2026-07). TrailLockProfit: never move the SL backwards (Oracle manual IV.B p.84) — keep true.
//    FreezeTrailOnFlip pauses SL moves on an adverse PSAR flip. The active shape is printed at start as [EXIT
//    SHAPE].
//

input group "=== RRM_ORG — TM: TRAIL START & FLAGS ===";
input ETrailTrigger      Inp_RRM_ORG_TrailTrigger                     = TRIGGER_IMMEDIATE;       // RRM ORG TS START: IMMEDIATE(Oracle) / BREAKEVEN / PROFIT_PERCENT / PROFIT_PIPS / PSAR_ALIGN
input bool               Inp_RRM_ORG_TrailStartsAfterBE               = true;                    // RRM ORG TS: hold trail until BE fires (Oracle value = false; true = pre-2026-07)
input bool               Inp_RRM_ORG_TrailAllowLossSide               = false;                   // RRM ORG TS: trail may tighten SL while still at a loss (Oracle value = true)
input bool               Inp_RRM_ORG_TrailLockProfit                  = true;                    // RRM ORG TS: never move SL backwards (lock profit)
input bool               Inp_RRM_ORG_FreezeTrailOnFlip                = true;                    // RRM ORG TS: FREEZE trail on PSAR flip (pause SL moves until corrected)
//
// TM — TAKE PROFIT. TP_MODE_FIXED_PIPS | TP_MODE_RR (TP = SL distance × RRRatio; e.g. RR 2.5 and SL 20 pips → TP
//    50) | TP_MODE_FRACTAL | TP_MODE_PSAR_FLIP (no fixed TP, exit on flip) | TP_MODE_NONE (no cap — trailing
//    manages the whole exit; LPR mode). TPMode != NONE → TP stays fixed and trailing runs underneath. RRRatio
//    history: was 1.25 (negative expectancy at ~52% win rate); Oracle: winners should outpace losers. Stale exit
//    (manual VII.D "sideways market … get out at break even"): close if MFE < MinR × initial risk after Bars.
//

input group "=== RRM_ORG — TM: TAKE PROFIT ===";
input ETPMode            Inp_RRM_ORG_TPMode                           = TP_MODE_NONE;            // RRM ORG TP: TP_MODE=*: *FIXED_PIPS, *FRACTAL, *NONE, *PSAR_FLIP, *RR
input double             Inp_RRM_ORG_RRRatio                          = 2.5;                     // RRM ORG TP: RR ratio — TP at N× SL distance (TP_MODE_RR only)

input group "=== RRM_ORG — TM: STALE-TRADE SCRATCH EXIT ===";
input bool               Inp_RRM_ORG_StaleExit_Enabled                = false;                   // RRM ORG StaleExit: close if no progress after N bars
input int                Inp_RRM_ORG_StaleExit_Bars                   = 21;                      // RRM ORG StaleExit: closed bars after entry before the check
input double             Inp_RRM_ORG_StaleExit_MinR                   = 1.0;                     // RRM ORG StaleExit: required MFE as multiple of initial risk

input group "=== RRM_ORG — TM: DRAWDOWN CAPS ===";
input bool               Inp_RRM_ORG_ForceDDProtection                = false;                   // RRM ORG DD: Force DrawDown protection
input int                Inp_RRM_ORG_DDMaxConsecLosses                = 3;                       // RRM ORG DD: Override max consecutive losses (0=use Inp_RRM_*)
input int                Inp_RRM_ORG_DDMaxTradesPerDay                = 8;                       // RRM ORG DD: Override max trades per day (0=use Inp_RRM_*)
input double             Inp_RRM_ORG_DDMaxDailyPct                    = 8.0;                     // RRM ORG DD: Override max daily DD % (0=use Inp_RRM_*)
//
// TE — RRM_ORG entry housekeeping: re-entry after the first position reaches BE (risk-free), its lot scale, post-
//    trade cooldown, and how many bars a spread-blocked signal is retried (0 = no retry).
//

input group "=== RRM_ORG — TE: RE-ENTRY, COOLDOWN, RETRY ===";
input bool               Inp_RRM_ORG_AllowReEntryAfterBE              = true;                    // RRM ORG: ALLOW re-entry after BE
input int                Inp_RRM_ORG_ReEntryLotScalePct               = 50;                      // RRM ORG Re-entry: lot size % for re-entry after BE (0=full size; 50=half)
input int                Inp_RRM_ORG_MinBarsAfterClose                = 3;                       // RRM ORG SL: post-trade cooldown bars (0=off)
input int                Inp_RRM_ORG_MaxSpreadRetryBars               = 0;                       // RRM ORG: SPREAD bars retry (if TE block)
#endif // SEA_BUILD_RRM_ORG


//+------------------------------------------------------------------+
//| 11. OTHER PRESETS — blocks copied verbatim (2026-09-10); only the |
//|     position in the file changed. Each is inert unless selected.  |
//+------------------------------------------------------------------+

#ifdef SEA_BUILD_FPM
input group " ";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "    📐 PRESET_FPM";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";

input ETPMode     Inp_FPM_TPMode                   = TP_MODE_RR;     // FPM TP: TP mode — RR=derive from SL distance (recommended); FIXED_PIPS=TF cheat sheet pips
input double      Inp_FPM_RRRatio                  = 1.5;            // FPM TP: R:R ratio (used with TP_MODE_RR, e.g. 1.5, 2.0, 3.0)
input double      Inp_FPM_SLFixedPips              = 15.0;           // FPM SL: fixed distance in pips (SL_MODE_FIXED_PIPS only — unreachable under FPM's current SWING lock; retained for TradeExecutor's general SL_MODE_FIXED_PIPS path)
input bool        Inp_FPM_UseTrailing              = true;           // FPM TS: Enable optional trailing stop
input double      Inp_FPM_TrailDistancePips        = 15.0;           // FPM TS: Trailing distance in pips (15 = cheat sheet default)

input group "FPM — CORE: ON / OFF (core; default true)";
input bool        Inp_FPM_Use_Psar                 = true;           // Condition 1: PSAR position
input bool        Inp_FPM_Use_Macd                 = true;           // Condition 2: MACD vs signal
input bool        Inp_FPM_Use_Bb                   = true;           // Condition 3: BB widening
input bool        Inp_FPM_Use_BarClose             = true;           // Condition 4: bar-close confirmation

input group "FPM — OPTIONAL: ON / OFF (default false)";
input bool        Inp_FPM_Use_Adx                  = false;          // FPM: add ADX trend-strength gate
input bool        Inp_FPM_Use_CI                   = false;          // FPM: add Choppiness Index gate
input bool        Inp_FPM_Use_CandleBody           = false;          // FPM: add CandleBody voter
input bool        Inp_FPM_Use_Dpi                  = false;          // FPM: add DPI voter (params global)
input bool        Inp_FPM_Use_P123                 = false;          // FPM: add P123 fractal-breakout confirm
input bool        Inp_FPM_Use_Ross                 = false;          // FPM: add Ross Hook confirm
input bool        Inp_FPM_Use_Mtf                  = false;          // FPM: add HTF/MTF confirmation (methodology excludes it; params global)

input group "FPM - Indicator Settings";
input int         Inp_FPM_MacdFast                 = 12;             // FPM MACD: fast EMA period
input int         Inp_FPM_MacdSlow                 = 26;             // FPM MACD: slow EMA period
input int         Inp_FPM_MacdSig                  = 9;              // FPM MACD: signal period
input double      Inp_FPM_PsarStep                 = 0.02;           // FPM PSAR: step
input double      Inp_FPM_PsarMax                  = 0.2;            // FPM PSAR: max
input bool        Inp_FPM_Ind_Mfi_Enabled          = true;           // FPM MFI: Enable MFI volume gate (MFI>50 for longs, <50 for shorts)
input int         Inp_FPM_Mfi_Period               = 14;             // FPM MFI: period (default 14)
#endif // SEA_BUILD_FPM


#ifdef SEA_BUILD_TOPINVESTOR
input group " ";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "    📐 PRESET_TOPINVESTOR";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group " ";
input group "=== TI STD - EMA ===";
input int         Inp_TI_Ema1                      = 9;              // TI EMA1:   9 (trailing exit ref)
input int         Inp_TI_Ema2                      = 50;             // TI EMA2:  50 (primary bounce)
input int         Inp_TI_Ema3                      = 89;             // TI EMA3:  89 (intermediate structure)
input int         Inp_TI_Ema4                      = 200;            // TI EMA4: 200 (major trend anchor)
//input group " ";
input group "=== TI STD - STANDARD ===";
input bool        Inp_TI_BlockUnorderedPhase       = true;           // TI Arch: block unordered phase
input bool        Inp_TI_PhaseAllowEM              = true;           // TI Arch: allow Emerging phase
input bool        Inp_TI_Emerging_AllowStrong      = false;          // TI Arch: allow strong trades in EM phase
input bool        Inp_TI_CloseOnReverse            = false;          // TI Arch: close on bias reversal
input int         Inp_TI_LayerBaselineLookback     = 34;             // TI Layer: baseline lookback
//input group " ";
input bool        Inp_TI_MTF_Enabled               = true;           // TI HTF: MTF voter enable
input int         Inp_TI_MTF_EMA_Fast              = 50;             // TI HTF: fast EMA period
input int         Inp_TI_MTF_EMA_Slow              = 200;            // TI HTF: slow EMA period
//input group " ";
input group "=== TI STD - SL TP EXIT ===";
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
input bool        Inp_TI_TrailStartsAfterBE        = false;          // TI Exit: Safety override: trail after BE

input group "=== TI STD - EMA FAN ===";
input double      Inp_TI_EmaFanBase_M1M5           = 50.0;           // TI Fan: max pips M1–M5
input double      Inp_TI_EmaFanBase_M6M30          = 80.0;           // TI Fan: max pips M6–M30
input double      Inp_TI_EmaFanBase_H1             = 120.0;          // TI Fan: max pips H1
input double      Inp_TI_EmaFanBase_H2H4           = 200.0;          // TI Fan: max pips H2–H4
input double      Inp_TI_EmaFanBase_H4Plus         = 350.0;          // TI Fan: max pips H4+

input group "=== TI STD - DD ===";
input bool        Inp_TI_EnableDDProtection        = false;          // TI DD: enable
input int         Inp_TI_MaxConsecutiveLosses      = 4;              // TI DD: max consecutive losses
input int         Inp_TI_MaxTradesPerDay           = 0;              // TI DD: max trades/day (0=unlimited)
input double      Inp_TI_MaxDailyDrawdownPct       = 2.0;            // TI DD: max daily DD %

input group "=== TI STD - VPRR ===";
input bool        Inp_TI_VPRR_AutoEnable           = false;          // TI VPRR: Auto-enable VPRR based on instrument type (ON=auto; OFF=use manual toggle below)
input EVPRRVolumeType Inp_TI_VPRR_VolumeType       = VPRR_VOL_AUTO;  // TI VPRR: Volume source (Auto=real then tick fallback)
input bool        Inp_TI_VPRR_Enabled              = false;          // TI VPRR: Manual enable (only used when AutoEnable=OFF)
input int         Inp_TI_VPRR_RecoveryBars         = 5;              // TI VPRR: Default recovery bars (1-10); per-instrument overrides in shared block below
input group " ";
input group "╔════════════════════════════════════════════════════════╗";
input group "    📐 PRESET_TOPINVESTOR — PROFILES";
input group "╚════════════════════════════════════════════════════════╝";
input group " ";
input ETIProfile  Inp_TI_Profile                   = TI_MODERATE;    // TI: profile select
input int         Inp_TI_MinBarsAfterClose         = 3;              // TI: cooldown bars after close (0=off)
input int         Inp_TI_ReEntryLotScalePct        = 50;             // TI: Re-entry: lot size % for re-entry after BE (0=full size; 50=half)
input group " ";
input group "=== TI PROFILE CONSERVATIVE=C (always active) ===";
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
input group " ";
input group "=== TI PROFILE: MODERATE=M (+C) ===";
input int         Inp_TI_MACD_Fast                 = 12;             // TI Mod: MACD fast
input int         Inp_TI_MACD_Slow                 = 26;             // TI Mod: MACD slow
input int         Inp_TI_MACD_Signal               = 9;              // TI Mod: MACD signal
input int         Inp_TI_MACD_FreshBars            = 5;              // TI Mod: MACD fresh bars
input double      Inp_TI_MACD_SlopeMin             = 0.00001;        // TI Mod: MACD slope min
input int         Inp_TI_CCI_Period                = 14;             // TI Mod: CCI period
input int         Inp_TI_BB_Period                 = 20;             // TI Mod: BB period
input double      Inp_TI_BB_Deviation              = 2.0;            // TI Mod: BB deviation
input group " ";
input group "=== TI PROFILE: FULL=F (+M) ===";
input double      Inp_TI_Fib_MinRetracement        = 0.38;           // TI Full: Fib min retracement
input double      Inp_TI_Fib_MaxRetracement        = 0.618;          // TI Full: Fib max retracement
input int         Inp_TI_Fib_SwingLookback         = 50;             // TI Full: Fib swing lookback
input double      Inp_TI_CandleBody_FullRatio      = 0.75;           // TI Full: min close ratio for body quality gate
#endif // SEA_BUILD_TOPINVESTOR


#ifdef SEA_BUILD_XEMA
input group " ";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "    📐 PRESET_XEMA";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group " ";
input group "XEMA — Entry cross";
input int     Inp_XEMA_EmaFast            = 13;                   // XEMA: fast EMA (entry cross)
input int     Inp_XEMA_EmaSlow            = 34;                   // XEMA: slow EMA (entry cross)
input group " ";
input group "XEMA — HTF confirmation";
input bool    Inp_XEMA_MTF_Enabled        = true;                 // XEMA: HTF filter (KEEP ON - condition 1)
input bool    Inp_XEMA_MTF_Use_SecondHTF  = false;                // XEMA: use a 2nd HTF? true = require BOTH TF1 and TF2 (XEMA default); false = single-HTF (TF1 only)
input ENUM_TIMEFRAMES Inp_XEMA_MTF_TF1    = PERIOD_H1;            // XEMA: primary HTF #1 (>= chart TF)
input ENUM_TIMEFRAMES Inp_XEMA_MTF_TF2    = PERIOD_CURRENT;       // XEMA: 2nd HTF #2 — used ONLY when Use_SecondHTF=true; set HIGHER than TF1
input int     Inp_XEMA_MTF_EMA_Fast       = 13;                   // XEMA: HTF fast EMA (shared by TF1 and TF2)
input int     Inp_XEMA_MTF_EMA_Slow       = 34;                   // XEMA: HTF slow EMA (shared by TF1 and TF2)
input group " ";
input group "XEMA — Anti-range";
input bool    Inp_XEMA_Use_Adx            = true;                 // XEMA: ADX trend-strength gate (recommended)
input int     Inp_XEMA_ADX_Period         = 14;                   // XEMA: ADX period
input double  Inp_XEMA_ADX_Percentile     = 50.0;                 // XEMA: ADX dynamic percentile
input int     Inp_XEMA_ADX_Lookback       = 100;                  // XEMA: ADX percentile lookback
input group " ";
input bool    Inp_XEMA_Use_Bb             = true;                 // XEMA: BB-widening gate
input int     Inp_XEMA_BB_Period          = 20;                   // XEMA: BB period
input double  Inp_XEMA_BB_Deviation       = 2.0;                  // XEMA: BB deviation
input group " ";
input bool    Inp_XEMA_Use_CI             = true;                 // XEMA: CI Choppiness gate (native inline calc; no external file)
input int     Inp_XEMA_CI_Period          = 14;                   // XEMA: CI period
input double  Inp_XEMA_CI_RangingThresh   = 61.8;                 // XEMA: CI ranging threshold
input group " ";
input group "XEMA — optional voters";
input bool    Inp_XEMA_Use_Psar                 = false;          // XEMA: add Parabolic SAR voter
input double  Inp_XEMA_Psar_Step                = 0.08;           // XEMA: PSAR step 0.02
input double  Inp_XEMA_Psar_Max                 = 0.5;            // XEMA: PSAR max 0.2
input bool    Inp_XEMA_Use_CandleBody           = false;          // XEMA: add CandleBody voter
input bool    Inp_XEMA_CandleBody_RequireDir    = true;           // XEMA: CB RequireDir
input int     Inp_XEMA_CandleBody_AvgPeriod     = 14;             // XEMA: CB AvGPEriod 14
input double  Inp_XEMA_CandleBody_MaxMult       = 3.0;            // XEMA: CB MaxMult 3.0
input double  Inp_XEMA_CandleBody_MinCloseRatio = 0.75;           // XEMA: CB MinCloseRatio 0.75
input bool    Inp_XEMA_Use_Dpi                  = false;          // XEMA: add DPI voter (DPI params are global)
input group " ";
input group "XEMA — Stop loss";
input ESLMode Inp_XEMA_SLMode             = SL_MODE_SWING;        // XEMA: SL mode
input int     Inp_XEMA_SwingLookback      = 34;                   // XEMA: swing lookback
input int     Inp_XEMA_SL_AtrPeriod       = 14;                   // XEMA: ATR period (SL_MODE_ATR)
input double  Inp_XEMA_SL_AtrMult         = 1.0;                  // XEMA: ATR mult (SL_MODE_ATR)
input group " ";
input group "XEMA — BE / Exit";
input EBeMode Inp_XEMA_BE_Mode            = BE_MODE_OFF;          // XEMA: BE mode
input double  Inp_XEMA_BE_RMultiple       = 2.0;                  // XEMA: move SL to BE at N*R
input ETrailingMode Inp_XEMA_TrailMode    = TRAIL_NONE;           // XEMA: post-BE trail (NONE = rely on LPR ladder / reverse cross)
#endif // SEA_BUILD_XEMA


#ifdef SEA_BUILD_TURTLE
input group " ";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "    📐 PRESET_TURTLE (TUR)";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group " ";
input group "TURTLE — Donchian / SL periods";
input bool   Inp_TURTLE_Use_DonchianEntry = true;        // [TUR CORE] Donchian breakout ENTRY on/off (false = no entry source -> EA idles + warns)
input bool   Inp_TURTLE_Use_DonchianExit  = true;        // [TUR CORE] Donchian channel EXIT on/off. ON = exit on channel-break OR 2xATR stop (first hit); OFF = 2xATR stop is the ONLY exit
input int    Inp_TURTLE_DonchianEntry_Period = 40;       // [TUR CORE] Donchian ENTRY breakout lookback N (S1=20, S2=55, H4-FX=40)
input int    Inp_TURTLE_DonchianExit_Period  = 20;       // [TUR CORE] Donchian EXIT channel lookback M (S1=10, S2=20)
input int    Inp_TURTLE_SL_AtrPeriod      = 20;          // [TUR CORE] SL ATR period for the initial stop
input double Inp_TURTLE_SL_AtrMult        = 2.0;         // [TUR CORE] SL = mult x ATR — ALWAYS placed at entry, independent of Use_DonchianExit
input group " ";
input group "TURTLE — INDICATORS: ON / OFF";
input group " ";
input bool   Inp_TURTLE_Use_Mtf           = false;       // [TUR] HTF/MTF confirmation voter
input bool   Inp_TURTLE_MTF_Use_SecondHTF = false;       // [TUR] HTF2? false = single-HTF (TF1 only). true = require BOTH TF1 and TF2 to agree
input ENUM_TIMEFRAMES Inp_TURTLE_MTF_TF1  = PERIOD_H1;   // [TUR] HTF1 — set HIGHER than the chart TF (H1 for M5/M15). Trade dir must agree with its EMA trend
input ENUM_TIMEFRAMES Inp_TURTLE_MTF_TF2  = PERIOD_H4;   // [TUR] HTF2 — used ONLY when Use_SecondHTF=true; set HIGHER than TF1
input int    Inp_TURTLE_MTF_EMA_Fast      = 50;          // [TUR] HTF EMA Fast
input int    Inp_TURTLE_MTF_EMA_Slow      = 200;         // [TUR] HTF EMA Slow
input group " ";
input bool   Inp_TURTLE_Use_Adx           = false;       // [TUR] ADX trend-strength gate
input int    Inp_TURTLE_ADX_Period        = 14;          // [TUR] ADX Period
input double Inp_TURTLE_ADX_Percentile    = 50.0;        // [TUR] ADX Percentile
input int    Inp_TURTLE_ADX_Lookback      = 100;         // [TUR] ADX Lookback
input group " ";
input bool   Inp_TURTLE_Use_Bb            = false;       // [TUR] BB-widening gate
input int    Inp_TURTLE_BB_Period         = 20;          // [TUR] BB Period
input double Inp_TURTLE_BB_Deviation      = 2.0;         // [TUR] BB Deviation
input group " ";
input bool   Inp_TURTLE_Use_CandleBody    = false;       // [TUR] CB CandleBody voter
input bool   Inp_TURTLE_CandleBody_RequireDir    = true; // [TUR] CB CandleBody: require signal bar to close in trade direction
input int    Inp_TURTLE_CandleBody_AvgPeriod     = 14;   // [TUR] CB CandleBody: ATR baseline period
input double Inp_TURTLE_CandleBody_MaxMult       = 3.0;  // [TUR] CB CandleBody: block if range > mult x ATR (spike guard)
input double Inp_TURTLE_CandleBody_MinCloseRatio = 0.0;  // [TUR] CB CandleBody: min close-to-range ratio (0=off, 0.75=reject doji)
input group " ";
input bool   Inp_TURTLE_Use_CI            = false;       // [TUR] CI Choppiness Index range gate
input int    Inp_TURTLE_CI_Period         = 14;          // [TUR] CI Period
input double Inp_TURTLE_CI_RangingThresh  = 61.8;        // [TUR] CI Threshold
input group " ";
input bool   Inp_TURTLE_Use_Psar          = false;       // [TUR] PSAR voter
input double Inp_TURTLE_Psar_Step         = 0.02;        // [TUR] PSAR acceleration step
input double Inp_TURTLE_Psar_Max          = 0.2;         // [TUR] PSAR acceleration max
input group " ";
input group "TURTLE — INDICATORS using global settings ";
input bool   Inp_TURTLE_Use_P123          = false;       // [TUR] P123 fractal-breakout confirm
input bool   Inp_TURTLE_Use_Ross          = false;       // [TUR] Ross Hook confirm
input bool   Inp_TURTLE_Use_Dpi           = false;       // [TUR] DPI voter
input group " ";
input group "TURTLE — Add to winner (pyramiding)";
input EAddMode Inp_TURTLE_AddMode         = ADD_OFF;     // [TUR] ADD mode
input bool   Inp_TURTLE_SharedStop        = true;        // [TUR] SharedStop
input int    Inp_TURTLE_MaxUnits          = 4;           // [TUR] MaxUnits
input double Inp_TURTLE_AddStepATR        = 0.5;         // [TUR] AddStepATR
input double Inp_TURTLE_MaxAggRisk        = 6.0;         // [TUR] MaxAggRisk
input int    Inp_TURTLE_ReEntryScale      = 50;          // [TUR] ReEntryScale
#endif // SEA_BUILD_TURTLE


#ifdef SEA_BUILD_TREND
input group " ";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "    📐 PRESET_TREND (TRE)";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
//=== TREND = TURTLE breakout + 3 EMAs + HTF ===
input group " ";
input group "TREND — Donchian / SL periods";
input bool   Inp_TREND_Use_DonchianEntry     = true;        // [TRE CORE] Donchian breakout ENTRY on/off (false = no entry source -> EA idles + warns)
input bool   Inp_TREND_Use_DonchianExit      = true;        // [TRE CORE] Donchian channel EXIT on/off. ON = exit on channel-break OR 2xATR stop (first hit); OFF = 2xATR stop is the ONLY exit
input int    Inp_TREND_DonchianEntry_Period  = 20;          // [TRE CORE] Donchian ENTRY breakout lookback N
input int    Inp_TREND_DonchianExit_Period   = 10;          // [TRE CORE] Donchian EXIT channel lookback M
input int    Inp_TREND_SL_AtrPeriod          = 20;          // [TRE CORE] SL ATR period for the initial stop
input double Inp_TREND_SL_AtrMult            = 2.0;         // [TRE CORE] SL = mult x ATR — ALWAYS placed at entry, independent of Use_DonchianExit
input group " ";
input group "TREND — EMA";
input bool   Inp_TREND_Use_EmaStack          = true;        // [TRE CORE] EMA require EMA(20/50/200) stack (false = pure Donchian channels)
input int    Inp_TREND_Ema_Fast              = 20;          // [TRE CORE] EMA fast
input int    Inp_TREND_Ema_Mid               = 50;          // [TRE CORE] EMA mid
input int    Inp_TREND_Ema_Slow              = 200;         // [TRE CORE] EMA slow (20>50>200 = long-only)
input bool   Inp_TREND_Use_PriceVsEma2       = false;       // [TRE opt] also require price beyond EMA2(50) in bias dir (doc Stage 2)
input bool   Inp_TREND_Use_Ema3Slope         = false;       // [TRE opt] also require EMA3(200) sloping in bias dir (doc Stage 1)
input group " ";
input group "TREND — MTF";
input bool   Inp_TREND_Use_Mtf               = true;        // [TRE CORE] HTF/MTF confirmation (keep ON)
input bool   Inp_TREND_MTF_Use_SecondHTF     = false;       // [TRE opt] HTF2? false = single-HTF (TF1 only). true = require BOTH TF1 and TF2 to agree
input ENUM_TIMEFRAMES Inp_TREND_MTF_TF1      = PERIOD_H1;   // [TRE CORE] HTF1 — set HIGHER than the chart TF (H1 for M5/M15). Trade dir must agree with its EMA trend
input ENUM_TIMEFRAMES Inp_TREND_MTF_TF2      = PERIOD_H4;   // [TRE opt] HTF2 — used ONLY when Use_SecondHTF=true; set HIGHER than TF1
input int    Inp_TREND_MTF_EMA_Fast          = 50;          // [TRE CORE] HTF EMA Fast
input int    Inp_TREND_MTF_EMA_Slow          = 200;         // [TRE CORE] HTF EMA Slow
input group " ";
input group "TREND — INDICATORS: ON / OFF";
input group " ";
input bool   Inp_TREND_Use_Adx               = false;       // [TRE] ADX trend-strength gate
input int    Inp_TREND_ADX_Period            = 14;          // [TRE] ADX Period
input double Inp_TREND_ADX_Percentile        = 50.0;        // [TRE] ADX Percentile
input int    Inp_TREND_ADX_Lookback          = 100;         // [TRE] ADX Lookback
input group " ";
input bool   Inp_TREND_Use_Bb                = false;       // [TRE] BB widening gate
input int    Inp_TREND_BB_Period             = 20;          // [TRE] BB Period
input double Inp_TREND_BB_Deviation          = 2.0;         // [TRE] BB Deviation
input group " ";
input bool   Inp_TREND_Use_CandleBody           = false;    // [TRE] CB CandleBody voter
input bool   Inp_TREND_CandleBody_RequireDir    = true;     // [TRE] CB RequireDir signal bar to close in trade direction
input int    Inp_TREND_CandleBody_AvgPeriod     = 14;       // [TRE] CB AVGPeriod ATR baseline period
input double Inp_TREND_CandleBody_MaxMult       = 3.0;      // [TRE] CB MaxMult block if range > mult x ATR (spike guard)
input double Inp_TREND_CandleBody_MinCloseRatio = 0.0;      // [TRE] CB MinClose-to-Range Ratio (0=off, 0.75=reject doji)
input group " ";
input bool   Inp_TREND_Use_CI                = false;       // [TRE] CI Choppiness Index range gate
input int    Inp_TREND_CI_Period             = 14;          // [TRE] CI Period
input double Inp_TREND_CI_RangingThresh      = 61.8;        // [TRE] CI Ranging Thresh.
input group " ";
input bool   Inp_TREND_Use_Psar              = false;       // [TRE] PSAR voter
input double Inp_TREND_Psar_Step             = 0.02;        // [TRE] PSAR acceleration step
input double Inp_TREND_Psar_Max              = 0.2;         // [TRE] PSAR acceleration max
input group " ";
input group "TREND — INDICATORS using global settings ";
input bool   Inp_TREND_Use_P123              = false;       // [TRE] P123 fractal-breakout confirm
input bool   Inp_TREND_Use_Ross              = false;       // [TRE] Ross Hook confirm
input bool   Inp_TREND_Use_Dpi               = false;       // [TRE] DPI voter
input group " ";
input group "TREND — Add to winner (pyramiding)";
input EAddMode Inp_TREND_AddMode             = ADD_OFF;     // [TRE] ADD mode
input bool   Inp_TREND_SharedStop            = true;        // [TRE] SharedStop
input int    Inp_TREND_MaxUnits              = 4;           // [TRE] MaxUnits
input double Inp_TREND_AddStepATR            = 0.5;         // [TRE] AddStepATR
input double Inp_TREND_MaxAggRisk            = 6.0;         // [TRE] MaxAggRisk
input int    Inp_TREND_ReEntryScale          = 50;          // [TRE] ReEntryScale
#endif // SEA_BUILD_TREND


#ifdef SEA_BUILD_RH_REBELLION
input group " ";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "    🇷🇭 PRESET_RH_REBELLION (Forex Rebellion)";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group " ";
input group "RH_REBELLION — Entry cross (Rule 2, direction/B)";
input int     Inp_RHR_EmaFast            = 4;                     // RHR: 4 faster EMA (4/5 cross)
input int     Inp_RHR_EmaSlow            = 5;                     // RHR: 5 slower EMA (4/5 cross)
input group " ";
input group "RH_REBELLION — Trend EMA (Rule 1)";
input int     Inp_RHR_TrendEmaPeriod     = 5;                     // RHR: 5 trend EMA period (the '5 EMA')
input int     Inp_RHR_TrendEmaShift      = 5;                     // RHR: 5 trend EMA forward shift (shift 5)
input group " ";
input group "RH_REBELLION — QQE (Rules 3 & 4)";
input bool    Inp_RHR_Use_QQE            = true;                  // RHR: QQE true voter (line-order + 50-zone) — KEEP ON
input int     Inp_RHR_QQE_SF             = 1;                     // RHR: QQE 1 smoothing factor (SF)
input int     Inp_RHR_QQE_RSI_Period     = 13;                    // RHR: QQE 13-8 RSI period
input int     Inp_RHR_QQE_WP             = 3;                     // RHR: QQE 3 Wilder period (WP)
input bool    Inp_RHR_QQE_RequireCross   = false;                 // RHR: false = static position (EA panel); true=fresh cross (manual-strict)
input group " ";
input group "RH_REBELLION — Stop loss";
input ESLMode Inp_RHR_SLMode             = SL_MODE_SWING;         // RHR: SL mode (SWING = manual's safest; ATR available)
input int     Inp_RHR_SwingLookback      = 21;                    // RHR: 21 swing lookback (bars)
input int     Inp_RHR_SL_AtrPeriod       = 14;                    // RHR: 14 ATR period (SL_MODE_ATR)
input double  Inp_RHR_SL_AtrMult         = 1.0;                   // RHR: 1 ATR mult (SL_MODE_ATR)
input group " ";
input group "RH_REBELLION — Exit / target";
input ETPMode Inp_RHR_TPMode             = TP_MODE_RR;            // RHR: TP mode. RR=the '100'/'1 Point 5'; or use Donchian channel exit below
input double  Inp_RHR_RRRatio            = 2.0;                   // RHR: 2.0-1.5 reward:risk (1.0='100', 1.5='1 Point 5')
input bool    Inp_RHR_UseDonchianExit    = true;                  // RHR: true-false - exit at opposite Donchian(21) wall instead of/again with RR
input int     Inp_RHR_DonchianExitPeriod = 13;                    // RHR: 13-21 Donchian exit channel period
input group " ";
input group "RH_REBELLION — Trade management";
input EBeMode Inp_RHR_BE_Mode            = BE_MODE_R_MULTIPLE;    // RHR: break-even mode (step SL to BE at N*R)
input double  Inp_RHR_BE_RMultiple       = 0.25;                  // RHR: 0.25-1.0 move SL to BE at +N*R (manual: at +1R)
input ETrailingMode Inp_RHR_TrailMode    = TRAIL_EMA;             // RHR: EMA post-BE trail (EMA = follow the 5 EMA)
input double  Inp_RHR_PendingBufferPips  = 1.0;                   // RHR: 1.0 pending stop-order buffer beyond the signal candle (pips)
#endif // SEA_BUILD_RH_REBELLION


#ifdef SEA_BUILD_RH_1MS
input group " ";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "    🇷🇭 PRESET_RH_1MS (1-Minute Scalper)";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group " ";
input group "RH_1MS — EMA stack (B: 50 vs 100)";
input int     Inp_RH1MS_EmaFast        = 50;     // RH1MS: 50 fast EMA (50>100 long / 50<100 short)
input int     Inp_RH1MS_EmaSlow        = 100;    // RH1MS: 100 slow EMA (also the SL clamp reference)
input group "RH_1MS — Stochastic trigger (I: 20/80 level-cross)";
input int     Inp_RH1MS_StoK           = 5;      // RH1MS: %K 5
input int     Inp_RH1MS_StoD           = 3;      // RH1MS: %D 3
input int     Inp_RH1MS_StoSlow        = 3;      // RH1MS: slowing 3
input double  Inp_RH1MS_StoOB          = 80.0;   // RH1MS: upper level (short: cross 80 down)
input double  Inp_RH1MS_StoOS          = 20.0;   // RH1MS: lower level (long: cross 20 up)
input group "RH_1MS — Stop loss (flexible)";
input ESLMode Inp_RH1MS_SLMode          = SL_MODE_SWING;      // RH1MS: SWING (manual) | FIXED_PIPS | ATR. NOTE: raw M1 swing stops ~1 pip get swept — see FixedSLPips / SL_MinPips
input int     Inp_RH1MS_SwingLookback   = 8;      // RH1MS: swing lookback (bars) — used by SL_MODE_SWING
input double  Inp_RH1MS_FixedSLPips     = 10.0;   // RH1MS: fixed SL pips — used by SL_MODE_FIXED_PIPS (research: 8-12 to clear M1 noise+spread)
input int     Inp_RH1MS_SL_AtrPeriod    = 14;     // RH1MS: ATR period — used by SL_MODE_ATR
input double  Inp_RH1MS_SL_AtrMult      = 2.0;    // RH1MS: ATR multiple — used by SL_MODE_ATR (caution: M1 ATR ~1 pip, so ATR stops stay tiny on M1)
input double  Inp_RH1MS_SL_MinPips      = 3.0;    // RH1MS: min SL floor (pips). Raise to force the stop OUTSIDE the M1 noise band
input bool    Inp_RH1MS_UseSlowMAClamp  = true;   // RH1MS: SL = nearer of {swing, 100 EMA} (manual 'or the 100 EMA')
input group "RH_1MS — Take profit (flexible)";
input ETPMode Inp_RH1MS_TPMode          = TP_MODE_FIXED_PIPS; // RH1MS: FIXED_PIPS (manual 7-12) | RR (target = SL distance x RRRatio)
input double  Inp_RH1MS_FixedTPPips     = 10.0;   // RH1MS: fixed TP pips — used by TP_MODE_FIXED_PIPS
input double  Inp_RH1MS_RRRatio         = 2.0;    // RH1MS: reward:risk — used by TP_MODE_RR (research: pair 2R with a wider stop)
#endif // SEA_BUILD_RH_1MS


#ifdef SEA_BUILD_RH_STS
input group " ";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "    🇷🇭 PRESET_RH_STS (Sea Trading System)";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group " ";
input group "RH_STS — Bias pair (B: MA3 vs MA20 mid-band)";
input int     Inp_RHSTS_MaFast          = 3;      // RHSTS: fast MA (manual: EMA3; preset approximates with SMA — see notes)
input int     Inp_RHSTS_MaSlow          = 20;     // RHSTS: slow MA = middle Bollinger band (SMA20)
input group "RH_STS — Voters (I: MACD-zero + RSI-50)";
input int     Inp_RHSTS_MacdFast        = 6;      // RHSTS: MACD fast
input int     Inp_RHSTS_MacdSlow        = 17;     // RHSTS: MACD slow
input int     Inp_RHSTS_MacdSig         = 1;      // RHSTS: MACD signal SMA (1 -> pure zero-line test)
input int     Inp_RHSTS_RsiPeriod       = 14;     // RHSTS: RSI period (>50 long / <50 short)
input group "RH_STS — Bollinger (SL/TP band; optional widen vote)";
input int     Inp_RHSTS_BbPeriod        = 20;     // RHSTS: Bollinger period (middle band = SMA20)
input double  Inp_RHSTS_BbDev           = 3.0;    // RHSTS: Bollinger deviation
input bool    Inp_RHSTS_UseBBWidenVote  = true;   // RHSTS: BB-widening as a 3rd vote. NOTE: canonical manual = MACD+RSI only; set false to match manual
input group "RH_STS — Stop / target (TM)";
input int     Inp_RHSTS_SwingLookback   = 10;     // RHSTS: swing lookback (bars) for SL
input ETPMode Inp_RHSTS_TPMode          = TP_MODE_RR;   // RHSTS: TP mode (manual: opposite band / TF-fixed pips; RR used as approximation)
input double  Inp_RHSTS_RRRatio         = 1.5;    // RHSTS: reward:risk when TPMode = RR
#endif // SEA_BUILD_RH_STS


#ifdef SEA_BUILD_RH_SS
input group " ";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "    🇷🇭 PRESET_RH_SS (Super System)";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group " ";
input group "RH_SS — EMAs (trigger EMA3xEMA5-open; 34/89 backbone)";
input int     Inp_RHSS_EmaFast          = 3;      // RHSS: EMA3 (close) — trigger fast
input int     Inp_RHSS_EmaSlow          = 5;      // RHSS: EMA5 (OPEN) — trigger slow
input int     Inp_RHSS_EmaTrendFast     = 34;     // RHSS: EMA34 backbone (trend filter — see notes)
input int     Inp_RHSS_EmaTrendSlow     = 89;     // RHSS: EMA89 backbone (trend filter — see notes)
input group "RH_SS — RSI(3) 80/20 momentum burst";
input int     Inp_RHSS_RsiPeriod        = 3;      // RHSS: RSI period
input double  Inp_RHSS_RsiOB            = 80.0;   // RHSS: RSI OB (long: burst above 80)
input double  Inp_RHSS_RsiOS            = 20.0;   // RHSS: RSI OS (short: burst below 20)
input group "RH_SS — Stochastic(5,3,3) main-vs-signal";
input int     Inp_RHSS_StoK             = 5;      // RHSS: %K 5
input int     Inp_RHSS_StoD             = 3;      // RHSS: %D 3   (spec (5,3,3) — corrects prior 5/5/5)
input int     Inp_RHSS_StoSlow          = 3;      // RHSS: slowing 3   (spec (5,3,3) — corrects prior 5/5/5)
input group "RH_SS — Stop / target (TM)";
input int     Inp_RHSS_SwingLookback    = 12;     // RHSS: swing lookback (bars) for SL
input double  Inp_RHSS_RRRatio          = 2.0;    // RHSS: reward:risk (manual 2R)
#endif // SEA_BUILD_RH_SS


#ifdef SEA_BUILD_RH_GS
input group " ";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "    🇷🇭 PRESET_RH_GS (Golden Strategy)";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group " ";
input group "RH_GS — 55 SMMA High/Low channel";
input int     Inp_RHGS_SmmaPeriod       = 55;     // RHGS: SMMA period (High on role0, Low on role1)
input group "RH_GS — Voters (Williams %R 55 + Stoch 5/5/5)";
input int     Inp_RHGS_WprPeriod        = 55;     // RHGS: Williams %R period
input double  Inp_RHGS_WprUpper         = -25.0;  // RHGS: %R upper (long: cross above -25)
input double  Inp_RHGS_WprLower         = -75.0;  // RHGS: %R lower (short: cross below -75)
input int     Inp_RHGS_StoK             = 5;      // RHGS: %K 5
input int     Inp_RHGS_StoD             = 5;      // RHGS: %D 5
input int     Inp_RHGS_StoSlow          = 5;      // RHGS: slowing 5
input group "RH_GS — Stop / target (TM)";
input bool    Inp_RHGS_UseSmmaRecrossExit = true; // RHGS: close when price re-crosses the entry SMMA(High)
input int     Inp_RHGS_SwingLookback    = 12;     // RHGS: swing lookback (bars) for SL
input double  Inp_RHGS_RRRatio          = 2.0;    // RHGS: reward:risk (manual 2R)
#endif // SEA_BUILD_RH_GS


#ifdef SEA_BUILD_RH_SM
input group " ";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "    🇷🇭 PRESET_RH_SM (Secret Method)";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group " ";
input group "RH_SM — Bias (Heiken-Ashi vs 14 SMA)";
input int     Inp_RHSM_SmaPeriod        = 14;     // RHSM: SMA period (HA candle vs this line)
input group "RH_SM — Voters (OsMA zero + Momentum100 + RSI5-50)";
input int     Inp_RHSM_OsMAFast         = 12;     // RHSM: OsMA fast
input int     Inp_RHSM_OsMASlow         = 26;     // RHSM: OsMA slow
input int     Inp_RHSM_OsMASignal       = 9;      // RHSM: OsMA signal
input int     Inp_RHSM_MomentumPeriod   = 10;     // RHSM: Momentum period
input double  Inp_RHSM_MomentumLevel    = 100.0;  // RHSM: Momentum centre level (long > 100 / short < 100)
input int     Inp_RHSM_RsiPeriod        = 5;      // RHSM: RSI period (>50 long / <50 short)
input group "RH_SM — Stop / target (TM)";
input bool    Inp_RHSM_UseOsMAFlipExit  = true;   // RHSM: early exit when OsMA histogram flips across zero
input int     Inp_RHSM_SwingLookback    = 10;     // RHSM: swing lookback (bars) for SL
input double  Inp_RHSM_RRRatio          = 2.0;    // RHSM: reward:risk (manual 2R)
#endif // SEA_BUILD_RH_SM


#ifdef SEA_BUILD_MA
//
// Inp_MA_MaximumRiskPct / Inp_MA_DecreaseFactor REMOVED — Settings.MA_MaximumRiskPct
// and Settings.MA_DecreaseFactor (the fields SEA_TradeExecutor.mqh actually uses for MA-benchmark lot
// sizing) are hardcoded in InitializeConfig() and never touched by ApplyPreset() for any preset; these
// inputs were never read. Their defaults (0.02 / 3.0) coincidentally matched the hardcoded values,
// masking the disconnect. See Readme/README_SEA_PARAMETER_MAPPING.md "Input Surface Audit" section.
//
input group " ";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "    📐 PRESET_MA  (MT5 Moving Average Benchmark)";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input int         Inp_MA_Period                    = 12;             // MA period
input int         Inp_MA_Shift                     = 6;              // MA shift
#endif // SEA_BUILD_MA


#ifdef SEA_BUILD_CRISP
input group " ";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "    📐 PRESET_CRISP (Mark Crisp 1-2-3 Pattern)";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group " ";
input group "CRISP — Trend & Structure";
input int     Inp_CRISP_MinPatternBars    = 3;                    // CRISP: Minimum bars from Pt1 to Breakout
input int     Inp_CRISP_TrendEmaPeriod    = 50;                   // CRISP: Trend EMA filter (slope defines bias)
input int     Inp_CRISP_P123_Lookback     = 21;                   // CRISP: 1-2-3 Scan Window (bars)
input group "CRISP — Stop Loss";
input ESLMode Inp_CRISP_SLMode            = SL_MODE_SWING;        // CRISP: SL mode (Swing highly recommended for price action)
input int     Inp_CRISP_SwingLookback     = 21;                   // CRISP: Swing SL Lookback
input group "CRISP — Exit & Trade Management";
input ETPMode Inp_CRISP_TPMode            = TP_MODE_RR;           // CRISP: Take Profit Mode
input double  Inp_CRISP_RRRatio           = 2.5;                  // CRISP: Reward:Risk Ratio
input ETrailingMode Inp_CRISP_TrailMode   = TRAIL_EMA;          // CRISP: Trailing Mode (Swing or Fractal fits PA best)
#endif // SEA_BUILD_CRISP


#ifdef SEA_BUILD_ROSS
input group " ";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "    📐 PRESET_ROSS (Joe Ross Hook & TTE)";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group " ";
input group "ROSS — Trend & Structure";
input bool    Inp_ROSS_UseTTE             = false;                 // ROSS: Use Trader's Trick Entry (TTE)
input bool    Inp_ROSS_Use3x3MAC          = false;                 // ROSS: Filter using 3x3 MAC turnoverinput group "ROSS — Stop Loss";
input int     Inp_ROSS_TrendEmaPeriod     = 34;                   // ROSS: Trend EMA filter (slope defines bias)
input int     Inp_ROSS_Lookback           = 21;                   // ROSS: Hook Scan Window (bars)
input group "ROSS — Stop Loss";
input ESLMode Inp_ROSS_SLMode             = SL_MODE_SWING;        // ROSS: SL mode
input int     Inp_ROSS_SwingLookback      = 21;                   // ROSS: Swing SL Lookback
input group "ROSS — Exit & Trade Management";
input ETPMode Inp_ROSS_TPMode             = TP_MODE_RR;           // ROSS: Take Profit Mode
input double  Inp_ROSS_RRRatio            = 2.5;                  // ROSS: Reward:Risk Ratio
input ETrailingMode Inp_ROSS_TrailMode    = TRAIL_EMA;          // ROSS: Trailing Mode
#endif // SEA_BUILD_ROSS


input group " ";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "    ⚠️ 12. ENGINE SEED DEFAULTS — presets override these (rarely touched)";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
//
// Seed values read once by InitializeConfig(); every active preset overrides most of them in ApplyPreset(). They
//    are load-bearing (a field falls back to them for any preset that does not override it) but NOT the place to
//    tune the active preset — use section 10. See Readme/README_SEA_PARAMETER_MAPPING.md "seed-then-override
//    architecture".
//

input group "=== SEED — INDICATORS ===";
input int                Inp_Global_Ind_Adx_PercentileRefreshSec      = 14400;                   // ADX: Global: DYNAMIC_PERCENTILE refresh interval (sec). M1: try 900 (15min); H1+: 14400 (4h)
input group " ";
input bool               Inp_Global_Ind_CandleBody_CarryOnOverext     = true;                    // CB Global: carry CB=0 over-ext until next layer pullback-recovery
input double             Inp_Global_Ind_CandleBody_MinCloseRatio      = 0.75;                    // CB Global: Min close ratio (0=off, 0.75=TopInvestor)
input group " ";
input bool               Inp_Global_Ind_Fib_Enabled                   = false;                   // FIB Global: Enable
input int                Inp_Global_Ind_Fib_SwingLookback             = 50;                      // FIB Global: Swing search bars
input double             Inp_Global_Ind_Fib_MinRetracement            = 0.38;                    // FIB Global: Min pullback depth
input double             Inp_Global_Ind_Fib_MaxRetracement            = 0.618;                   // FIB Global: Max pullback depth
input group " ";
input double             Inp_Global_Ind_Mfi_Level                     = 50.0;                    // MFI Global: Threshold/level

input group "=== PATTERN 1-2-3 & ROSS HOOK ===";
input int                Inp_Global_P123_Lookback                     = 34;                      // P123: Structural scan window
input bool               Inp_Global_Ross_UseTTE                       = true;                    // Ross: Use Trader's Trick Entry (TTE)
input int                Inp_Global_Ross_Lookback                     = 55;                      // Ross: Structural scan window

input group "=== SEED — VPRR ===";
input bool               Inp_Global_VPRR_Enabled                      = false;                   // Global_VPRR_Enabled: Volume Pullback-Recovery Ratio voter
input double             Inp_Global_VPRR_MinRatio_W                   = 0.0;                     // Global_VPRR_MinRatio_W: (EMA1/EMA2) min ratio (0=use VPRR_MinRatio)
input double             Inp_Global_VPRR_MinRatio_M                   = 0.0;                     // Global_VPRR_MinRatio_M: (EMA2/EMA3) min ratio (0=use VPRR_MinRatio)
input double             Inp_Global_VPRR_MinRatio_S                   = 0.0;                     // Global_VPRR_MinRatio_S: (EMA3/EMA4) min ratio (0=use VPRR_MinRatio)

input group "=== SEED — STOP LOSS ===";
input bool               Inp_Global_SL_WidenToMinimum                 = true;                    // SL Global_WidenToMinimum: If true: widen to min.; if false: block TE
input int                Inp_Global_SL_AtrPeriod                      = 14;                      // SL Global_AtrPeriod: ATR period (SL_MODE_ATR only)
input double             Inp_Global_SL_FixedPips                      = 20.0;                    // SL Global_FixedPips: SL distance (pips SL_MODE_FIXED_PIPS)
input double             Inp_Global_SL_MinPips                        = 3.0;                     // SL Global_MinPips: Min. SL pips (0 = no user floor, broker minimum still applies)
input double             Inp_Global_SL_AtrMult                        = 1.0;                     // SL Global_AtrMult: ATR multiplier — SL = swing_anchor − ATR×N (SL_MODE_ATR; 0.5–1.5 typical)

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

   Settings.DrawEntryLines           = Inp_UI_DrawEntryLines;
   Settings.ExportCSV                = Inp_Debug_ExportCSV;
   
   // === Tactical UI Theme Mapping ===
   Settings.clr_Header              = Inp_UI_clr_Header;   // Gold 
   Settings.clr_Value               = Inp_UI_clr_Value;    // White 
   Settings.clr_Pass                = Inp_UI_clr_Pass;     // LimeGreen 
   Settings.clr_Fail                = Inp_UI_clr_Fail;     // OrangeRed 
   Settings.clr_Disabled            = Inp_UI_clr_Disabled; // Gray
   Settings.clr_Waiting             = Inp_UI_clr_Waiting;  // Yellow
   
   // Master Toggle and Global Font Color

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
   Settings.NewsSource           = Inp_Global_VETO_NewsSource;             // NEWS-SRC 2026-09-10
   Settings.NewsCsvTzOffsetMin   = Inp_Global_VETO_NewsCsvTzOffsetMin;     // NEWS-SRC 2026-09-10
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
   Settings.Ind_MTF_Enabled      = false;   // base default; preset sets its own in ApplyPreset
   Settings.MTF_TF1              = PERIOD_H2;   // base defaults; each preset sets its own MTF params in ApplyPreset
   Settings.MTF_TF2              = PERIOD_H4;
   Settings.MTF_EMA_Fast         = 20;
   Settings.MTF_EMA_Slow         = 50;
   Settings.MTF_UseSecondHTF     = true;   // base default: honour the TF2 sentinel (backward-compat). TURTLE/TREND override to opt-in.
   Settings.MTF_RequirePhase     = true;
   // F-AUDIT 2026-07: Settings.MTF_StrictAlignment is a PROVEN DEAD SINK — SEA_SignalEngine.mqh
   // documents it directly: "MTF_StrictAlignment is retained for compatibility but the gate is
   // strict-by-construction; the flag no longer relaxes it." Inp_Global_MTF_StrictAlignment (which
   // fed this) is removed. Literal `true` preserves the field's value for ConfigSync round-tripping.

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
   
   Settings.Crisp_P123_Lookback  = MathMax(10, Inp_Global_P123_Lookback);
   Settings.Ross_Lookback        = MathMax(15, Inp_Global_Ross_Lookback);
   Settings.Ross_UseTTE          = Inp_Global_Ross_UseTTE;
   
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

   Settings.ExitProfile             = EXIT_PROFILE_RRM;
   Settings.BE_Mode                 = BE_MODE_TP_PROGRESS_PCT;
   Settings.RRM_BE_ProgressPct      = 50.0;   // default; overwritten by ApplyPreset
   Settings.RRM_BE_RMultiple        = 1.0;    // default; overwritten by ApplyPreset
   // Baseline is the LEGACY sampler on purpose: every preset that does not
   // explicitly opt in keeps its pre-2026-07 behaviour. Only PRESET_RRM_ORG
   // opts in, via Inp_RRM_ORG_BE_TriggerSource.
   Settings.BE_TriggerSource        = BE_SRC_BAR_CLOSE;
   Settings.RRM_TrailPsarDotShift = 2;      // default; overwritten by ApplyPreset
   Settings.RRM_FreezeTrailOnFlip   = true;   // default; overwritten by ApplyPreset
   Settings.RRM_TrailStartsAfterBE  = false;  // default; overwritten by ApplyPreset
   // Baseline is the pre-2026-07 behaviour on purpose: every preset that does not
   // explicitly opt in keeps a stop that is frozen until BE. Only PRESET_RRM_ORG
   // opts in, via Inp_RRM_ORG_TrailAllowLossSide.
   Settings.TrailAllowLossSide      = false;

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
   // Universal LPR ladder (pack non-zero ascending pairs)
   Settings.LPR_LadderEnabled = Inp_Global_LPR_Enabled;
   {
      int lc = 0;
      double lt[3] = {Inp_Global_LPR_Trig1, Inp_Global_LPR_Trig2, Inp_Global_LPR_Trig3};
      double ll[3] = {Inp_Global_LPR_Lock1, Inp_Global_LPR_Lock2, Inp_Global_LPR_Lock3};
      for(int i = 0; i < 3; i++)
         if(lt[i] > 0.0 && ll[i] > 0.0 && ll[i] < lt[i])
         { Settings.LPR_LadderTriggerR[lc] = lt[i]; Settings.LPR_LadderLockR[lc] = ll[i]; lc++; }
      Settings.LPR_LadderCount = lc;
   }
   // Universal daily target
   Settings.DailyTarget_Enabled = Inp_Global_DailyTarget_Enabled;
   Settings.DailyTarget_Pct     = MathMax(0.0, Inp_Global_DailyTarget_Pct);
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
   
   Settings.Emerging_AllowStrongTrades   = true;

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
   Settings.Portfolio_Enabled        = Inp_Global_Portfolio_Enabled;
   Settings.Portfolio_MaxAccountRisk = MathMax(0.0, Inp_Global_Portfolio_MaxAccountRisk);
   Settings.Portfolio_MaxCurrencyRisk= MathMax(0.0, Inp_Global_Portfolio_MaxCurrencyRisk);
   Settings.Portfolio_TargetSlots    = MathMax(1, Inp_Global_Portfolio_TargetSlots);
   Settings.Portfolio_VolParity      = Inp_Global_Portfolio_VolParity;

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
   Settings.LayerFlatRatio              = 0.1;
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
   // F-AUDIT 2026-07: ClimaxGuard_ResetPullback mapping REMOVED with its input and struct field.

    // VPRR defaults (disabled — only RRM_ORG preset wires it on)
    Settings.VPRR_Enabled         = Inp_Global_VPRR_Enabled;
    Settings.VPRR_VolumeType      = (int)VPRR_VOL_AUTO;
    Settings.VPRR_RecoveryBars    = 3;
    // -1 sentinel = derive from RecoveryBars; presets re-resolve this after ApplyPreset.
    Settings.VPRR_MinRecoveryBars = (Inp_VPRR_MinRecoveryBars > 0)
                                    ? MathMax(1, MathMin(10, Inp_VPRR_MinRecoveryBars))
                                    : 2;
    Settings.VPRR_MinRatio        = 1.0;
    // Theme3 2026-06: per-layer VPRR threshold overrides (0 = use VPRR_MinRatio above)
    Settings.VPRR_MinRatio_W      = MathMax(0.0, Inp_Global_VPRR_MinRatio_W);
    Settings.VPRR_MinRatio_M      = MathMax(0.0, Inp_Global_VPRR_MinRatio_M);
    Settings.VPRR_MinRatio_S      = MathMax(0.0, Inp_Global_VPRR_MinRatio_S);
    Settings.VPRR_ExternalSymbol  = "";
    // VPRR measurement layer (2026-07-27). Seeded here for EVERY preset, including
    // ones that never mention VPRR - the FPM/MA fall-through that caused defect V3.
    Settings.VPRR_Validated       = Inp_VPRR_Validated;
    Settings.VPRR_RVOL_Sessions   = MathMax(0, Inp_VPRR_RVOL_Sessions);
    Settings.VPRR_RVOL_MinSamples = MathMax(1, Inp_VPRR_RVOL_MinSamples);
    Settings.VPRR_LogPerSignal    = Inp_VPRR_LogPerSignal;
    Settings.VPRR_ResearchTickMode = Inp_VPRR_ResearchTickMode;

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

   // Fresh-trend gate + stale exit: OFF globally, wired from Inp_RRM_ORG_* inside the RRM_ORG preset.
   Settings.FreshX_Enabled        = false;
   Settings.FreshX_RefPair_W      = (int)FRESHX_OFF;
   Settings.FreshX_RefPair_M      = (int)FRESHX_OFF;
   Settings.FreshX_RefPair_S      = (int)FRESHX_OFF;
   Settings.FreshX_MaxPullbacks_W = 0; Settings.FreshX_MaxPullbacks_M = 0; Settings.FreshX_MaxPullbacks_S = 0;
   Settings.FreshX_MaxBars_W      = 0; Settings.FreshX_MaxBars_M      = 0; Settings.FreshX_MaxBars_S      = 0;
   Settings.FreshX_Lookback       = 300;
   Settings.StaleExit_Enabled     = false;
   Settings.StaleExit_Bars        = 12;
   Settings.StaleExit_MinR        = 1.0;
   Settings.UNO_AllowStrongShark  = false;   // wired from Inp_RRM_ORG_* inside the RRM_ORG preset
   Settings.MTF_FreshX_Enabled      = false;   // wired inside the RRM_ORG preset
   Settings.MTF_FreshX_Layers       = 3;
   Settings.MTF_FreshX_MaxPullbacks = 2;
   Settings.MTF_FreshX_MaxBars      = 0;
   Settings.MTF_FreshX_Lookback     = 200;
   Settings.MTF_FreshX_PBLookback   = 55;
   Settings.MTF_FreshX_ApplyTF2     = false;

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

