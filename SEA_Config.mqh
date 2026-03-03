//+------------------------------------------------------------------+
//|                                                   SEA_Config.mqh |
//|                                   Copyright 2026, SimpleEA System|
//+------------------------------------------------------------------+
#property strict

//+------------------------------------------------------------------+
//| TYPES (ENUMS / STRUCTS)                                          |
//+------------------------------------------------------------------+

// --- STRATEGY PRESETS ---
enum EStrategyPreset
{
   PRESET_CUSTOM,             // CUSTOM - User controlled (no preset overrides)
   PRESET_MA_BENCHMARK,       // PRESET - MT5 MA "Moving Average" compatibility
   PRESET_TREND_REVERSAL,     // PRESET - Trend Reversal (Baseline)
   PRESET_TREND_SCALP,        // PRESET - Trend Scalp (Intraday confluence)
   PRESET_TREND_SWING,        // PRESET - Trend Swing (Institutional)
   PRESET_RANGE_GRID,         // PRESET - Range Grid (Conservative mean reversion)
   PRESET_RRM_ATR,            // PRESET - RRM ATR Trend Pullback (OPTIMIZED)
   PRESET_RRM                 // PRESET - RRM Strict No-ATR Trend Pullback
};

// --- RRM MODE (for PRESET_RRM / PRESET_RRM_ATR) ---
enum ERRMMode
{
   RRM_AUTO_BY_TF,            // RRM_Auto: M1/M5/M15 => SCALP; H1/H4+ => SWING
   RRM_SCALP,                 // RRM_Scalp: faster bias pair (EMA1/EMA2)
   RRM_SWING                  // RRM_Swing: slower bias pair (EMA3/EMA4)
};

// --- SIMPLE EMA SELECTOR ---
enum EEmaStrategy
{
   EMA_STRAT_1_PRICE_CROSS,   // EMA_STRAT_1 EMA: Buy if Price > EMA1 (Benchmark)
   EMA_STRAT_2_CROSS_1_2,     // EMA_STRAT_2 EMAs: Buy if EMA1 > EMA2 (Golden Cross)
   EMA_STRAT_2_CROSS_3_4,     // EMA_STRAT_2 EMAs: Buy if EMA3 > EMA4 (Slow Trend)
   EMA_STRAT_CUSTOM           // EMA_STRAT_CUSTOM Manual: Use "Advanced Bias" inputs below
};

// --- MA METHOD SELECTOR ---
enum EMaMethod
{
   METHOD_EMA,                // Exponential
   METHOD_SMA                 // Simple
};

enum EBiasMode
{
   BIAS_MANUAL,
   BIAS_AUTO
};

enum EManualSide
{
   SIDE_BOTH,
   SIDE_LONG,
   SIDE_SHORT
};

enum EAutoStrategy
{
   STRAT_SINGLE_SLOPE,
   STRAT_PAIR_CROSS,
   STRAT_PRICE_CROSS
};

enum EEmaRole
{
   ROLE_EMA1,
   ROLE_EMA2,
   ROLE_EMA3,
   ROLE_EMA4
};

// Indicator Modes
enum EMacdMode
{
   MACD_SIGNAL_ALIGN,
   MACD_ZERO_CROSS
};

enum ERsiMode
{
   RSI_FILTER_EXTREME,
   RSI_TREND_ABOVE_50,
   RSI_CROSS_LEVEL
};

enum ECciMode
{
   CCI_TREND_ZERO,
   CCI_IMPULSE_100
};

enum EStochMode
{
   STO_CROSS_SIGNAL,
   STO_ZONE_FILTER
};

enum EBbMode
{
   BB_TREND_FOLLOW,
   BB_MEAN_REVERSION
};

// TR - Trailing Stop: Exit Logic
enum ETrailingMode
{
   TRAIL_NONE,
   TRAIL_ATR,
   TRAIL_PSAR,
   TRAIL_FRACTAL
};

// SL - Stop Loss: Initial SL Placement Methods
enum ESlPlacementMode
{
   SL_ATR,
   SL_PSAR_ATR,
   SL_PSAR_PIPS,
   SL_SWING_HIGHLOW,
   SL_FIXED_PIPS
};

// TR - Trailing Stop: PSAR Trailing Cushion Mode
enum EPsarTrailCushionMode
{
   PSAR_CUSHION_ATR,
   PSAR_CUSHION_PIPS
};

// --- EXIT PROFILE SELECTOR ---
// Selects the exit contract for a trade. LEGACY preserves current ATR-based behavior.
// RRM_STRICT_NO_ATR is reserved for future strict non-ATR RRM execution (PR 2+).
enum EExitProfile
{
   EXIT_PROFILE_LEGACY,             // Legacy: ATR-based exits (current behavior, default)
   EXIT_PROFILE_RRM_STRICT_NO_ATR   // Strict non-ATR RRM exits (future; no ATR cushion/BE/TP/trail fallback)
};

// --- BREAKEVEN MODE SELECTOR ---
// Controls how breakeven is triggered under the strict non-ATR RRM exit profile.
// BE_MODE_OFF maps to existing behavior (executor uses legacy Use_BE/BE_Trig/BE_Buff untouched).
enum EBeMode
{
   BE_MODE_OFF,                // Breakeven disabled (default; legacy ATR fields still in effect)
   BE_MODE_TP_PROGRESS_PCT,    // BE triggers at % progress toward TP (used with TP enabled)
   BE_MODE_R_MULTIPLE          // BE triggers at k*R multiple (used when TP is disabled)
};

// --- GATE SCALING MODES ---
enum EGateScaleMode
{
   GATE_SCALE_OFF,        // Gate disabled
   GATE_SCALE_FIXED,      // Use fixed pip value
   GATE_SCALE_AUTO_TF     // Auto-scale by timeframe/pair
};

// --- VOTE MODE SELECTOR ---
enum EVoteMode
{
   VOTE_MODE_THRESHOLD,   // THRESHOLD: minimum weighted votes required (default)
   VOTE_MODE_ALL          // ALL: every enabled indicator must agree
};

struct SGateConfig
{
   EGateScaleMode mode;
   double         value;  // Fixed pips or TF scaling factor
};

// --- UI FRAME MODE (Panels) ---
enum EUIFrameMode
{
   UI_FRAME_BG,              // Rectangle background (default)
   UI_FRAME_NONE,            // Text only (no rectangle)
   UI_FRAME_TEXT_BOUNDS      // Text bounds markers (BEGIN/END), no rectangle
};

// --- STRUCTURES ---
struct SNewsEvent
{
   datetime time;
   string   currency;
   string   impact;
};

// Vote state snapshot for runtime display
struct SVoteSnapshot
{
   string name;        // "MACD", "PSAR", etc.
   string state;       // "BUY", "SELL", "FLAT", "PASS"
   string reason;      // Brief explanation
   bool   enabled;     // Is this vote enabled in config?
   int    vote_result; // +1 = pass (matches bias), 0 = fail
};

// Single settings struct used across the EA
// NOTE: Architecture currently expects a global "Settings" instance of this type.
struct ST_Settings
{
   // Logic
   bool CloseOnReverse;

   // Risk
   double RiskPercent;
   double MaxSpread;
   double MinATR;
   double MaxATR;
   bool   ATR_HardGate;
   bool   Use_ATRVote;

   // MT5 Moving Average benchmark compatibility
   bool   UseMACompatSizer;
   double MA_MaximumRiskPct;
   double MA_DecreaseFactor;
   bool   RequirePriceCross;
   bool   MABenchmarkStrict;

   // RRM (Trend Pullback)
   bool   RRM_RequirePullbackReclaim;
   bool   RRM_RequireEmaDiv;
   int    RRM_Lookback;
   double RRM_MinDivPips;

   // Bias
   bool          BiasEnabled;
   EBiasMode     BiasMode;
   EManualSide   ManSide;
   EAutoStrategy AutoStrat;
   int           BiasFastID;
   int           BiasSlowID;

   // Execution Logic
   EMaMethod MaType;
   int       ma_h_shift;
   int       ma_v_shift;

   // Filters
   bool            UseTime;
   int             StartHr;
   int             EndHr;
   bool            UseNews;
   int             NewsPre;
   int             NewsPost;
   bool            UseHTF;
   ENUM_TIMEFRAMES HtfPeriod;
   int             P_HtfEma;

   // Voting
   int       VoteThreshold;
   EVoteMode VoteMode;        // THRESHOLD: weighted sum >= VoteThreshold; ALL: every indicator must agree (weights ignored)

   // Per-indicator weights (1.0 = standard; only used in VOTE_MODE_THRESHOLD for weighted sum)
   // In VOTE_MODE_ALL, weights are ignored — all enabled indicators must simply agree.
   double W_EmaSig;
   double W_Adx;
   double W_Macd;
   double W_Rsi;
   double W_Cci;
   double W_Mfi;
   double W_Sto;
   double W_Bb;
   double W_Psar;
   double W_P123;
   double W_Ross;

   // Indicators (Periods)
   int    P_Ema1;
   int    P_Ema2;
   int    P_Ema3;
   int    P_Ema4;
   int    P_Adx;
   int    T_Adx;
   int    P_MacdFast;
   int    P_MacdSlow;
   int    P_MacdSig;
   int    P_Rsi;
   double T_RsiOB;
   double T_RsiOS;
   int    P_Cci;
   int    P_Mfi;
   double T_Mfi;
   int    P_Atr;
   int    P_StoK;
   int    P_StoD;
   int    P_StoSlow;
   double T_StoOB;
   double T_StoOS;
   int    P_Bb;
   double P_BbDev;
   double P_PsarStep;
   double P_PsarMax;
   double P_PsarTrailCushionATR;
   double T_MfiOB;
   double T_MfiOS;

   // Modes
   EMacdMode  MacdMode;
   ERsiMode   RsiMode;
   ECciMode   CciMode;
   EStochMode StoMode;
   EBbMode    BbMode;

   // Active Votes
   bool Use_EmaSig;
   bool Use_Adx;
   bool Use_Macd;
   bool Use_Rsi;
   bool Use_Cci;
   bool Use_Mfi;
   bool Use_Sto;
   bool Use_Bb;
   bool Use_Psar;
   bool Use_P123;
   bool Use_Ross;

   // SL - Initial SL Placement
   ESlPlacementMode SL_PlacementMode;
   double           SL_Mult;
   double           SL_PsarPipsCushion;
   double           SL_SwingPipsCushion;
   double           SL_FixedPips;

   // TS - Trailing SL / TP / BE
   double              TP_Mult;
   bool                Use_BE;
   double              BE_Trig;
   double              BE_Buff;
   ETrailingMode       TrailMode;
   double              Trail_Mult;
   EPsarTrailCushionMode PSAR_TrailCushionMode;
   double              PSAR_TrailPipsCushion;

   // --- Strict non-ATR RRM exit contract (for future PRs; defaults preserve current behavior) ---
   EExitProfile ExitProfile;            // Exit profile selector; EXIT_PROFILE_LEGACY = current ATR-based behavior
   bool         TP_Enabled;             // Whether TP is active; true preserves existing TP_Mult>0 semantics
   EBeMode      BE_Mode;                // BE mode for strict non-ATR RRM; BE_MODE_OFF = legacy ATR BE untouched

   // Strict RRM parameters (reserved for future implementation; no executor reads these yet)
   double RRM_BE_ProgressPct;           // BE trigger: % progress toward TP (0..100); used with BE_MODE_TP_PROGRESS_PCT
   double RRM_BE_RMultiple;             // BE trigger: R-multiple threshold (e.g. 1.0); used with BE_MODE_R_MULTIPLE
   double RRM_BE_BufferPips;            // BE buffer in pips for strict non-ATR mode
   int    RRM_TrailPsarShiftDelay;      // PSAR trail bar-shift delay (1..3)
   bool   RRM_FreezeTrailOnFlip;        // Freeze trailing stop on PSAR flip signal
   bool   RRM_TrailStartsAfterBE;       // Delay trail activation until BE is triggered

   // Gate system (reusable hard gates for any preset)
   bool        RequirePullback;          // Dynamic structure pullback gate (replaces pip-based Gate_Pullback)
   int         PullbackLookback;         // Bars to look back for pullback structure
   bool        RequireRecoveryMomentum;  // Require recovery bar to close in trend direction
   bool        Gate_UseMultiLayer;       // Enable multi-layer cascading EMA pullback detection (RRM standard)
   SGateConfig Gate_Recovery;           // Multi-bar recovery gate
   int         Gate_RecoveryLookback;   // Bars to look back for recovery
   SGateConfig Gate_EmaDiv;             // EMA divergence gate
   SGateConfig Gate_CandleDirection;    // Candle direction confirmation gate
   int         Gate_CandleCheckShift;   // Which bar(s) to check for candle direction
   int         Vote_EvalShift;          // Shift for vote evaluation
   bool        Vote_AllowPsarFlip;      // Allow PSAR flip signal in votes

   // Reporting
   bool ExportCSV;

   // --- AdminOverride system ---
   bool AdminOverridePreset;

   // --- Global toggles allowed under presets ---
   bool PrintEffectiveConfig;
   bool DebugFlow;

   // UI
   bool UI_ShowStatusPanel;
   bool UI_ShowCockpitPanel;
   bool UI_ManageChartIndicators;
   bool DrawEntryLines;
   bool DrawTradeLines;

   // Reporting
   bool ExportUseCommonFiles;
};

// Global Configuration Instance
ST_Settings Settings;

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                 |
//+------------------------------------------------------------------+
//
// NOTE: MT5 uses the trailing inline `// ...` comment as the input description.
// Many inputs are overridden by presets; descriptions below include applicability tags.
//
// Input Zone Layout:
//   🎯 ZONE 1  — Preset Selection         : choose preset & magic number
//   ✅ ZONE 2  — User Controls (Policy A) : always editable, gates & UI
//   ℹ️ ZONE 3A — Preset Info              : reference defaults; presets override when active
//   🔓 ZONE 3B — Admin Override (§1–§4)  : unlock preset parameters for testing
//
// Tags used in descriptions:
//   (Global; allowed under presets)                 - always honored (Zone 2)
//   (Operator gate; preserved under presets)        - Policy A: user-controlled even under presets (Zone 2)
//   (CUSTOM; presets override)                      - effective mainly in PRESET_CUSTOM (Zone 3A)
//   (CUSTOM; most presets override; strict sets 0)  - ATR gates forced off under strict RRM (Zone 3A)

// ════════════════════════════════════════════════════════════════════
// 🎯 ZONE 1 — PRESET SELECTION
// ════════════════════════════════════════════════════════════════════
input group "══════════ 🎯 ZONE 1: PRESET SELECTION ══════════"
input ulong           Inp_MagicNum               = 12345;       // (Global) Magic number (trade identifier)
input EStrategyPreset InpPreset                 = PRESET_RRM;   // (Global) Strategy preset (presets may override many inputs below)

// ════════════════════════════════════════════════════════════════════
// ✅ ZONE 2 — USER CONTROLS  (Policy A gates — always editable)
// These inputs are always respected regardless of which preset is active.
// ════════════════════════════════════════════════════════════════════
input group "══════════ ✅ ZONE 2: USER CONTROLS (Policy A — always editable) ══════════"

input group "--- ✅ Operator Gates: Spread & ATR Limits ---"
input double         Inp_MaxSpreadPips          = 3.0;    // (Operator gate; preserved under presets) Max spread (pips)
input double         Inp_MinATRPips             = 0.0;    // (Operator gate; preserved under presets) Min ATR gate (pips; 0=off)
input double         Inp_MaxATRPips             = 20.0;   // (Operator gate; preserved under presets) Max ATR gate (pips; 0=off)

input group "--- ✅ Operator Gates: Session Time Filter ---"
input bool            Inp_UseTime                = false;              // (Operator gate; preserved under presets) Enable session/time filter
input int             Inp_StartHour              = 8;                  // (Operator gate; preserved under presets) Session start hour (broker time)
input int             Inp_EndHour                = 20;                 // (Operator gate; preserved under presets) Session end hour (broker time)

input group "--- ✅ Operator Gates: News Filter ---"
input bool            Inp_UseNews                = false;              // (Operator gate; preserved under presets) Enable news filter (CSV calendar)
input string          Inp_NewsFile               = "calendar_statement.csv"; // (Operator gate; preserved under presets) News CSV filename
input int             Inp_NewsPre                = 60;                 // (Operator gate; preserved under presets) Minutes before news to block entries
input int             Inp_NewsPost               = 60;                 // (Operator gate; preserved under presets) Minutes after news to block entries

input group "--- ✅ Operator Gates: HTF Trend Filter ---"
input bool            Inp_UseHTF                 = false;              // (Operator gate; preserved under presets) Enable HTF trend filter
input ENUM_TIMEFRAMES Inp_HtfPeriod              = PERIOD_H4;          // (Operator gate; preserved under presets) HTF timeframe
input int             Inp_HtfEmaPeriod           = 89;                 // (Operator gate; preserved under presets) HTF EMA period

input group "--- ✅ UI: Status Panel ---"
input bool             Inp_UI_ShowStatusPanel     = false;      // (Global; allowed under presets) Show status panel
input bool             Inp_UI_ManageChartIndicators = false;    // (Global; allowed under presets) Auto-add/remove chart indicators
input ENUM_BASE_CORNER Inp_UI_PanelCorner       = CORNER_LEFT_UPPER; // (Global; allowed under presets) Status panel corner
input int              Inp_UI_PanelX            = 30;           // (Global; allowed under presets) Status panel X (px)
input int              Inp_UI_PanelY            = 30;           // (Global; allowed under presets) Status panel Y (px)
input int              Inp_UI_PanelFontSize     = 10;           // (Global; allowed under presets) Status panel font size
input int              Inp_UI_LineSpacingPx     = 28;           // (Global; allowed under presets) Status panel line spacing (px)
input string           Inp_UI_PanelFont         = "Arial";      // (Global; allowed under presets) Status panel font

input group "--- ✅ UI: Cockpit Panel ---"
input bool             Inp_UI_ShowCockpitPanel    = true;       // (Global; allowed under presets) Show cockpit panel
input ENUM_BASE_CORNER Inp_UI_CockpitCorner     = CORNER_LEFT_UPPER; // (Global; allowed under presets) Cockpit panel corner
input int              Inp_UI_CockpitX          = 30;           // (Global; allowed under presets) Cockpit panel X (px)
input int              Inp_UI_CockpitY          = 30;           // (Global; allowed under presets) Cockpit panel Y (px)
input int              Inp_UI_CockpitFontSize   = 10;           // (Global; allowed under presets) Cockpit panel font size
input int              Inp_UI_CockpitLineSpacingPx = 28;        // (Global; allowed under presets) Cockpit panel line spacing (px)
input string           Inp_UI_CockpitFont       = "Arial";      // (Global; allowed under presets) Cockpit panel font

input group "--- ✅ UI: Signal Markers ---"
input bool           Inp_DrawEntryLines         = true;         // (Global; allowed under presets) Draw entry marker lines
input bool           Inp_DrawTradeLines         = true;         // (Global; allowed under presets) Draw trade management lines

input group "--- ✅ UI: Colors & Framing ---"
input bool             Inp_UI_UseCustomColors   = true;         // (Global; allowed under presets) Use custom panel colors (else follow chart theme)
input color            Inp_UI_FontColor         = clrYellow;    // (Global; allowed under presets) UI font color (when custom colors enabled)
input int              Inp_UI_PanelBgAlpha      = 110;          // (Global; allowed under presets) Panel background alpha (0..255)
input EUIFrameMode     Inp_UI_FrameMode          = UI_FRAME_NONE; // (Global; allowed under presets) Panel frame mode (BG/NONE/TEXT_BOUNDS)
input int              Inp_UI_FramePadPx         = 6;           // (Global; allowed under presets) Panel padding (px)

input group "--- ✅ Diagnostics ---"
input bool           Inp_PrintEffectiveConfig   = true;         // (Global; allowed under presets) Print effective config on init
input bool           Inp_DebugFlow              = false;        // (Global; allowed under presets) Print OnInit/OnTick/OnDeinit flow

input group "--- ✅ Reporting ---"
input bool           Inp_ExportCSV              = false;        // (Global; allowed under presets) Export CSV reporting
input bool           Inp_ExportUseCommonFiles   = false;        // (Global; allowed under presets) Use terminal Common Files folder for export

// ════════════════════════════════════════════════════════════════════
// ℹ️ ZONE 3A — PIPELINE CONFIG  (reference defaults by pipeline step)
// Organized by the 9-step signal processing pipeline.
// When a preset is active these are overridden by the preset.
// In PRESET_CUSTOM mode all inputs below are fully respected.
// Steps 3 (Signal-Bias Match), 7 (Position Check) have no user inputs.
// Steps 4 (HTF) and 8 (Operator Gates) are in Zone 2 (always editable).
// ════════════════════════════════════════════════════════════════════
input group "══════════ ℹ️ ZONE 3A: PIPELINE CONFIG (presets override these when active) ══════════"

// ── Step 1: Bias Calculation ─────────────────────────────────────────
input group "--- ℹ️ Step 1: Bias Calculation (EMA selection & method) ---"
input bool           Inp_BiasEnabled            = true;                 // (CUSTOM; presets override) Enable market bias filter
input EBiasMode      Inp_BiasMode               = BIAS_AUTO;            // (CUSTOM; presets override) Bias mode (AUTO/MANUAL)
input EEmaStrategy   Inp_EmaStrategy            = EMA_STRAT_2_CROSS_3_4; // (CUSTOM; presets override) EMA bias strategy mapping
input EManualSide    Inp_ManualSide             = SIDE_BOTH;            // (CUSTOM; presets override) Manual direction (BOTH/LONG/SHORT)
input EEmaRole       Inp_BiasFast_Adv           = ROLE_EMA3;            // (CUSTOM; presets override) Advanced bias fast EMA role (EMA_STRAT_CUSTOM only)
input EEmaRole       Inp_BiasSlow_Adv           = ROLE_EMA4;            // (CUSTOM; presets override) Advanced bias slow EMA role (EMA_STRAT_CUSTOM only)
input EMaMethod      Inp_MaType                 = METHOD_EMA;          // (CUSTOM; presets override) MA method (EMA/SMA)
input int            Inp_MaHorShift             = 0;                   // (CUSTOM; presets override) MA horizontal shift (bars)
input int            Inp_MaVerShift             = 1;                   // (CUSTOM; presets override) MA vertical shift (pips)
input int            InpEma1Period              = 5;                   // (CUSTOM; presets override) EMA1 period
input int            InpEma2Period              = 13;                  // (CUSTOM; presets override) EMA2 period
input int            InpEma3Period              = 34;                  // (CUSTOM; presets override) EMA3 period (RRM bias fast)
input int            InpEma4Period              = 89;                  // (CUSTOM; presets override) EMA4 period (RRM bias slow)

// ── Step 2: Entry Signal ─────────────────────────────────────────────
input group "--- ℹ️ Step 2: Entry Signal (strategy & continuation) ---"
input ERRMMode       Inp_RRM_Mode               = RRM_AUTO_BY_TF; // (RRM presets) RRM mode (AUTO uses timeframe mapping)
input bool           Inp_RRM_EnableInCustom     = false;          // (CUSTOM only) Enable RRM logic while using PRESET_CUSTOM
input EAutoStrategy  Inp_RRM_AutoStrat          = STRAT_PRICE_CROSS; // (CUSTOM; presets override) Auto strategy mapping (price cross / pair cross)
input EEmaRole       Inp_RRM_BiasEMA            = ROLE_EMA2;      // (CUSTOM; presets override) Bias EMA role (manual bias tuning)
input bool           Inp_CloseOnReverse         = false;          // (CUSTOM; presets may override) Close on reverse signal
input EExitProfile   Inp_ExitProfile            = EXIT_PROFILE_LEGACY; // (CUSTOM; presets override) Exit profile (strict presets force strict)

// ── Step 5: Structure Gate (Multi-layer pullback) ─────────────────────
input group "--- ℹ️ Step 5: Structure Gate (pullback & multi-layer) ---"
input bool           Inp_UseMultiLayer              = false;      // (CUSTOM; presets override) Enable multi-layer cascading EMA pullback detection
input bool           Inp_RequirePullback            = false;      // (CUSTOM; presets override) Require dynamic structure pullback gate
input int            Inp_PullbackLookback           = 10;         // (CUSTOM; presets override) Pullback lookback (bars)
input bool           Inp_RequireRecoveryMomentum    = false;      // (CUSTOM; presets override) Require recovery bar to close in trend direction
input bool           Inp_RRM_RequirePullbackReclaim = false;      // (CUSTOM; presets override) Require pullback + reclaim condition
input bool           Inp_RRM_RequireEmaDiv          = false;      // (CUSTOM; presets override) Require EMA divergence gate
input int            Inp_RRM_Lookback           = 5;              // (CUSTOM; presets override) Pullback lookback bars
input double         Inp_RRM_MinDivPips         = 0.5;            // (CUSTOM; presets override) Min EMA divergence (pips)

// ── Step 6: Indicator Voting ──────────────────────────────────────────
input group "--- ℹ️ Step 6: Indicator Voting (mode & threshold) ---"
input int            Inp_VoteThreshold          = 2;                    // (CUSTOM; presets override) Votes required to enter (threshold; weighted sum in THRESHOLD mode)
input EVoteMode      Inp_VoteMode               = VOTE_MODE_THRESHOLD;  // (CUSTOM; presets override) Vote mode: THRESHOLD (weighted sum) or ALL (every indicator must agree)

input group "--- ℹ️ Step 6 · EmaSig: EMA Price Signal ---"
input bool           Inp_Use_EmaSig             = true;                // (CUSTOM; presets override) Enable EMA signal vote
input double         Inp_W_EmaSig               = 1.0;                 // (CUSTOM; presets override) EMA signal vote weight

input group "--- ℹ️ Step 6 · ADX: Trend Strength ---"
input bool           Inp_Use_Adx                = false;               // (CUSTOM; presets override) Enable ADX vote
input double         Inp_W_Adx                  = 1.0;                 // (CUSTOM; presets override) ADX vote weight
input int            InpAdxPeriod               = 14;                  // (CUSTOM; presets override) ADX period
input int            InpAdxThreshold            = 20;                  // (CUSTOM; presets override) ADX threshold

input group "--- ℹ️ Step 6 · MACD: Momentum ---"
input bool           Inp_Use_Macd               = true;                // (CUSTOM; presets override) Enable MACD vote
input double         Inp_W_Macd                 = 1.0;                 // (CUSTOM; presets override) MACD vote weight
input EMacdMode      InpMacdMode                = MACD_SIGNAL_ALIGN;   // (CUSTOM; presets override) MACD mode (signal align / zero cross)
input int            InpMacdFast                = 12;                  // (CUSTOM; presets override) MACD fast period
input int            InpMacdSlow                = 26;                  // (CUSTOM; presets override) MACD slow period
input int            InpMacdSig                 = 9;                   // (CUSTOM; presets override) MACD signal period

input group "--- ℹ️ Step 6 · RSI: Momentum Zones ---"
input bool           Inp_Use_Rsi                = false;               // (CUSTOM; presets override) Enable RSI vote
input double         Inp_W_Rsi                  = 1.0;                 // (CUSTOM; presets override) RSI vote weight
input ERsiMode       InpRsiMode                 = RSI_FILTER_EXTREME;  // (CUSTOM; presets override) RSI mode
input int            InpRsiPeriod               = 14;                  // (CUSTOM; presets override) RSI period
input double         InpRsiOverbought           = 70.0;                // (CUSTOM; presets override) RSI overbought level
input double         InpRsiOversold             = 30.0;                // (CUSTOM; presets override) RSI oversold level

input group "--- ℹ️ Step 6 · CCI: Cyclical ---"
input bool           Inp_Use_Cci                = true;                // (CUSTOM; presets override) Enable CCI vote
input double         Inp_W_Cci                  = 1.0;                 // (CUSTOM; presets override) CCI vote weight
input ECciMode       InpCciMode                 = CCI_TREND_ZERO;      // (CUSTOM; presets override) CCI mode
input int            InpCciPeriod               = 14;                  // (CUSTOM; presets override) CCI period

input group "--- ℹ️ Step 6 · MFI: Money Flow ---"
input bool           Inp_Use_Mfi                = false;               // (CUSTOM; presets override) Enable MFI vote
input double         Inp_W_Mfi                  = 1.0;                 // (CUSTOM; presets override) MFI vote weight
input int            InpMfiPeriod               = 14;                  // (CUSTOM; presets override) MFI period
input double         InpMfiLevel                = 50.0;                // (CUSTOM; presets override) MFI threshold/level

input group "--- ℹ️ Step 6 · Stochastic: Oscillator ---"
input bool           Inp_Use_Sto                = false;               // (CUSTOM; presets override) Enable Stochastic vote
input double         Inp_W_Sto                  = 1.0;                 // (CUSTOM; presets override) Stochastic vote weight
input EStochMode     InpStoMode                 = STO_ZONE_FILTER;     // (CUSTOM; presets override) Stochastic mode
input int            InpStoK                    = 5;                   // (CUSTOM; presets override) Stochastic %K period
input int            InpStoD                    = 3;                   // (CUSTOM; presets override) Stochastic %D period
input int            InpStoSlow                 = 3;                   // (CUSTOM; presets override) Stochastic slowing

input group "--- ℹ️ Step 6 · Bollinger Bands: Volatility ---"
input bool           Inp_Use_Bb                 = false;               // (CUSTOM; presets override) Enable Bollinger Bands vote
input double         Inp_W_Bb                   = 1.0;                 // (CUSTOM; presets override) Bollinger Bands vote weight
input EBbMode        InpBbMode                  = BB_TREND_FOLLOW;     // (CUSTOM; presets override) Bollinger mode
input int            InpBbPeriod                = 20;                  // (CUSTOM; presets override) Bollinger period
input double         InpBbDev                   = 2.0;                 // (CUSTOM; presets override) Bollinger deviation

input group "--- ℹ️ Step 6 · PSAR: Trend Direction ---"
input bool           Inp_Use_Psar               = true;                // (CUSTOM; presets override) Enable PSAR vote
input double         Inp_W_Psar                 = 1.0;                 // (CUSTOM; presets override) PSAR vote weight
input double         InpPsarStep                = 0.05;                // (CUSTOM; presets override) PSAR step
input double         InpPsarMax                 = 0.5;                 // (CUSTOM; presets override) PSAR max

input group "--- ℹ️ Step 6 · P123: 1-2-3 Pattern ---"
input bool           Inp_Use_P123               = false;               // (CUSTOM; presets override) Enable 1-2-3 pattern vote
input double         Inp_W_P123                 = 1.0;                 // (CUSTOM; presets override) 1-2-3 pattern vote weight

input group "--- ℹ️ Step 6 · Ross: Ross Hook ---"
input bool           Inp_Use_Ross               = false;               // (CUSTOM; presets override) Enable Ross hook vote
input double         Inp_W_Ross                 = 1.0;                 // (CUSTOM; presets override) Ross hook vote weight

// ── Step 9: Risk & Execution ──────────────────────────────────────────
input group "--- ℹ️ Step 9: Risk & Execution (SL, TP, trailing) ---"
input double         Inp_RiskPercent            = 2.0;    // (CUSTOM; presets may override) Risk per trade (%)

input group "--- ℹ️ Step 9 · Initial SL Placement ---"
input ESlPlacementMode Inp_SL_PlacementMode     = SL_SWING_HIGHLOW;    // (CUSTOM; presets override) SL placement method
input double         Inp_SL_Mult                = 1.5;                 // (CUSTOM; presets override) SL multiplier (ATR modes only; ignored in strict)
input double         Inp_SL_PsarPipsCushion     = 5.0;                 // (CUSTOM; presets override) SL PSAR cushion (pips)
input double         Inp_SL_SwingPipsCushion    = 10.0;                // (CUSTOM; presets override) SL swing cushion (pips)
input double         Inp_SL_FixedPips           = 20.0;                // (CUSTOM; presets override) SL fixed distance (pips)

input group "--- ℹ️ Step 9 · TP & Breakeven ---"
input double         Inp_TP_Mult                = 3.0;                 // (CUSTOM; presets override) TP R-multiple (legacy TP_Mult)
input bool           Inp_Use_BE                 = false;               // (CUSTOM; presets override) Use legacy BE (strict uses BE_Mode instead)
input double         Inp_BE_Trig                = 1.0;                 // (CUSTOM; presets override) Legacy BE trigger (R multiple)
input double         Inp_BE_Buff                = 0.1;                 // (CUSTOM; presets override) Legacy BE buffer (pips)

input group "--- ℹ️ Step 9 · Trailing Stop ---"
input ETrailingMode  Inp_TrailMode              = TRAIL_PSAR;          // (CUSTOM; presets override) Trailing stop mode
input double         Inp_Trail_Mult             = 3.0;                 // (CUSTOM; presets override) Trail multiplier (ATR modes only; ignored in strict)
input EPsarTrailCushionMode Inp_PSAR_TrailCushionMode = PSAR_CUSHION_PIPS; // (CUSTOM; presets override) PSAR trail cushion mode
input double         Inp_PSAR_TrailPipsCushion  = 5.0;                 // (CUSTOM; presets override) PSAR trail cushion (pips)
input double         Inp_PSAR_TrailCushionATR   = 0.2;                 // (CUSTOM; presets override) PSAR trail cushion (ATR)

input group "--- ℹ️ Benchmark: MT5 Moving Average ---"
input double         Inp_MA_MaximumRiskPct      = 0.02;         // (PRESET_MA_BENCHMARK only) Max risk (%) for MA benchmark sizer
input double         Inp_MA_DecreaseFactor      = 3.0;          // (PRESET_MA_BENCHMARK only) Lot decrease factor
input int            Inp_MA_Period              = 12;           // (PRESET_MA_BENCHMARK only) MA period
input int            Inp_MA_Shift               = 6;            // (PRESET_MA_BENCHMARK only) MA shift

// ════════════════════════════════════════════════════════════════════
// 🔓 ZONE 3B — ADMIN OVERRIDE  (preset testing for experienced users)
// Set Inp_AdminOverridePreset=true to activate §1–§4 override fields.
// Has no effect in PRESET_CUSTOM mode (all inputs already respected).
// ════════════════════════════════════════════════════════════════════
input group "══════════ 🔓 ZONE 3B: ADMIN OVERRIDE (set true to activate §1-§4 below) ══════════"
input bool           Inp_AdminOverridePreset        = false; // [Admin] Unlock preset parameters for testing (true=admin mode, false=normal user)

input group "--- 🔓 §1 Admin Override: Strategy, EMAs & Votes ---"
input EAutoStrategy  Inp_Override_AutoStrat          = STRAT_PAIR_CROSS; // [Admin] Override AutoStrat when AdminOverride=true
input int            Inp_Override_VoteThreshold       = 4;                // [Admin] Override Vote Threshold when AdminOverride=true
input int            Inp_Override_EMA1               = 5;                 // [Admin] Override EMA1 period when AdminOverride=true
input int            Inp_Override_EMA2               = 13;                // [Admin] Override EMA2 period when AdminOverride=true
input int            Inp_Override_EMA3               = 34;                // [Admin] Override EMA3 period when AdminOverride=true
input int            Inp_Override_EMA4               = 89;                // [Admin] Override EMA4 period when AdminOverride=true
input bool           Inp_Override_Use_EmaSig          = true;             // [Admin] Override EMA signal vote when AdminOverride=true
input bool           Inp_Override_Use_Macd            = true;             // [Admin] Override MACD vote when AdminOverride=true
input bool           Inp_Override_Use_Psar            = true;             // [Admin] Override PSAR vote when AdminOverride=true
input bool           Inp_Override_Use_Cci             = true;             // [Admin] Override CCI vote when AdminOverride=true
input bool           Inp_Override_Use_Rsi             = false;            // [Admin] Override RSI vote when AdminOverride=true
input bool           Inp_Override_Use_Adx             = false;            // [Admin] Override ADX vote when AdminOverride=true
input bool           Inp_Override_Use_Mfi             = false;            // [Admin] Override MFI vote when AdminOverride=true
input bool           Inp_Override_Use_Sto             = false;            // [Admin] Override Stochastic vote when AdminOverride=true
input bool           Inp_Override_Use_Bb              = false;            // [Admin] Override Bollinger vote when AdminOverride=true
input bool           Inp_Override_Use_P123            = false;            // [Admin] Override 1-2-3 pattern vote when AdminOverride=true
input bool           Inp_Override_Use_Ross            = false;            // [Admin] Override Ross hook vote when AdminOverride=true
input bool           Inp_Override_RRM_RequirePullbackReclaim = false;     // [Admin] Override RRM pullback reclaim gate when AdminOverride=true
input bool           Inp_Override_RRM_RequireEmaDiv          = false;     // [Admin] Override RRM EMA divergence gate when AdminOverride=true
input bool           Inp_Override_RequirePullback            = false;     // [Admin] Override RequirePullback when AdminOverride=true
input int            Inp_Override_PullbackLookback           = 10;        // [Admin] Override PullbackLookback when AdminOverride=true
input bool           Inp_Override_RequireRecoveryMomentum    = false;     // [Admin] Override RequireRecoveryMomentum when AdminOverride=true
input bool           Inp_Override_UseMultiLayer              = true;      // [Admin] Override UseMultiLayer (cascading EMA pullback) when AdminOverride=true

input group "--- 🔓 §2 Admin Override: Indicator Periods & Thresholds ---"
input int            Inp_Override_MACD_Fast           = 8;                // [Admin] Override MACD Fast period when AdminOverride=true
input int            Inp_Override_MACD_Slow           = 13;               // [Admin] Override MACD Slow period when AdminOverride=true
input int            Inp_Override_MACD_Signal         = 8;                // [Admin] Override MACD Signal period when AdminOverride=true
input int            Inp_Override_ADX_Period                 = 14;        // [Admin] Override ADX period when AdminOverride=true
input int            Inp_Override_ADX_Threshold              = 20;        // [Admin] Override ADX threshold when AdminOverride=true
input int            Inp_Override_RSI_Period                 = 14;        // [Admin] Override RSI period when AdminOverride=true
input double         Inp_Override_RSI_OB                     = 70.0;      // [Admin] Override RSI overbought level when AdminOverride=true
input double         Inp_Override_RSI_OS                     = 30.0;      // [Admin] Override RSI oversold level when AdminOverride=true
input int            Inp_Override_STO_K                      = 5;         // [Admin] Override Stochastic %K period when AdminOverride=true
input int            Inp_Override_STO_D                      = 3;         // [Admin] Override Stochastic %D period when AdminOverride=true
input int            Inp_Override_STO_Slow                   = 3;         // [Admin] Override Stochastic slowing period when AdminOverride=true
input double         Inp_Override_STO_OB                     = 80.0;      // [Admin] Override Stochastic overbought level when AdminOverride=true
input double         Inp_Override_STO_OS                     = 20.0;      // [Admin] Override Stochastic oversold level when AdminOverride=true
input double         Inp_Override_PSAR_Step                  = 0.05;      // [Admin] Override PSAR step when AdminOverride=true
input double         Inp_Override_PSAR_Max                   = 0.5;       // [Admin] Override PSAR maximum when AdminOverride=true
input int            Inp_Override_CCI_Period                 = 14;        // [Admin] Override CCI period when AdminOverride=true
input int            Inp_Override_BB_Period                  = 20;        // [Admin] Override Bollinger Bands period when AdminOverride=true
input double         Inp_Override_BB_Dev                     = 2.0;       // [Admin] Override Bollinger Bands deviation when AdminOverride=true
input int            Inp_Override_MFI_Period                 = 14;        // [Admin] Override MFI period when AdminOverride=true
input double         Inp_Override_MFI_OB                     = 50.0;      // [Admin] Override MFI overbought threshold when AdminOverride=true
input double         Inp_Override_MFI_OS                     = 50.0;      // [Admin] Override MFI oversold threshold when AdminOverride=true
input int            Inp_Override_ATR_Period                 = 14;        // [Admin] Override ATR period when AdminOverride=true
input double         Inp_Override_ATR_MinPips                = 0.0;       // [Admin] Override ATR min pips gate when AdminOverride=true
input double         Inp_Override_ATR_MaxPips                = 0.0;       // [Admin] Override ATR max pips gate when AdminOverride=true
input bool           Inp_Override_ATR_UseAsVote              = false;     // [Admin] Override ATR use-as-vote when AdminOverride=true

input group "--- 🔓 §3 Admin Override: Risk & Entry ---"
input bool                Inp_Override_RequirePriceCross     = false;     // [Admin] Override RequirePriceCross when AdminOverride=true
input bool                Inp_Override_UseHTF                = false;     // [Admin] Override HTF filter enabled when AdminOverride=true
input bool                Inp_Override_CloseOnReverse        = true;      // [Admin] Override CloseOnReverse when AdminOverride=true
input double              Inp_Override_RiskPercent           = 2.0;       // [Admin] Override RiskPercent (%) when AdminOverride=true
input ESlPlacementMode    Inp_Override_SL_PlacementMode      = SL_ATR;    // [Admin] Override SL placement mode when AdminOverride=true
input double              Inp_Override_SL_Mult               = 1.5;       // [Admin] Override SL ATR multiplier when AdminOverride=true
input double              Inp_Override_SL_PsarPipsCushion    = 5.0;       // [Admin] Override SL PSAR cushion (pips) when AdminOverride=true
input double              Inp_Override_SL_SwingPipsCushion   = 10.0;      // [Admin] Override SL swing cushion (pips) when AdminOverride=true

input group "--- 🔓 §4 Admin Override: Exits — TP, Breakeven & Trailing ---"
input double              Inp_Override_TP_Mult               = 3.0;       // [Admin] Override TP multiplier when AdminOverride=true
input bool                Inp_Override_Use_BE                = false;      // [Admin] Override breakeven enabled when AdminOverride=true
input double              Inp_Override_BE_Trig               = 1.0;       // [Admin] Override BE trigger (R-multiple) when AdminOverride=true
input double              Inp_Override_BE_Buff               = 0.1;       // [Admin] Override BE buffer (pips) when AdminOverride=true
input ETrailingMode       Inp_Override_TrailMode             = TRAIL_NONE; // [Admin] Override trailing stop mode when AdminOverride=true
input double              Inp_Override_Trail_Mult            = 1.5;       // [Admin] Override trail ATR multiplier when AdminOverride=true
input EPsarTrailCushionMode Inp_Override_PSAR_TrailCushionMode = PSAR_CUSHION_PIPS; // [Admin] Override PSAR trail cushion mode when AdminOverride=true
input double              Inp_Override_PSAR_TrailPipsCushion = 5.0;       // [Admin] Override PSAR trail cushion (pips) when AdminOverride=true

//+------------------------------------------------------------------+
//| InitializeConfig(): maps inputs into Settings (NO preset logic)   |
//| Model A: Config always maps inputs -> struct; later stages decide |
//| what to override/ignore (presets) and what to print.             |
//+------------------------------------------------------------------+
void InitializeConfig()
{
   ZeroMemory(Settings);

   // === Global inputs allowed under presets (still mapped normally) ===
   Settings.PrintEffectiveConfig     = Inp_PrintEffectiveConfig;
   Settings.DebugFlow                = Inp_DebugFlow;
   Settings.AdminOverridePreset      = Inp_AdminOverridePreset;

   Settings.UI_ShowStatusPanel       = Inp_UI_ShowStatusPanel;
   Settings.UI_ShowCockpitPanel      = Inp_UI_ShowCockpitPanel;
   Settings.UI_ManageChartIndicators = Inp_UI_ManageChartIndicators;
   Settings.DrawEntryLines           = Inp_DrawEntryLines;
   Settings.DrawTradeLines           = Inp_DrawTradeLines;

   Settings.ExportCSV                = Inp_ExportCSV;
   Settings.ExportUseCommonFiles     = Inp_ExportUseCommonFiles;

   // === Strategy inputs (mapped regardless of preset; presets may override later) ===

   // Base settings from inputs
   Settings.CloseOnReverse       = Inp_CloseOnReverse;
   Settings.RiskPercent          = Inp_RiskPercent;
   Settings.MaxSpread            = Inp_MaxSpreadPips;
   Settings.MinATR               = Inp_MinATRPips;
   Settings.MaxATR               = Inp_MaxATRPips;

   // Defaults for gating/vote semantics
   // (If you later add explicit inputs for these, map them here.)
   Settings.ATR_HardGate         = false;
   Settings.Use_ATRVote          = false;

   // MA benchmark inputs (strategy fields; preset may use/override semantics later)
   Settings.UseMACompatSizer     = false;
   Settings.MA_MaximumRiskPct    = Inp_MA_MaximumRiskPct;
   Settings.MA_DecreaseFactor    = Inp_MA_DecreaseFactor;
   Settings.RequirePriceCross    = false;
   Settings.MABenchmarkStrict    = false;

   // RRM trigger gates (inputs always mapped; preset may ignore/override later)
   Settings.RRM_RequirePullbackReclaim = Inp_RRM_RequirePullbackReclaim;
   Settings.RRM_RequireEmaDiv          = Inp_RRM_RequireEmaDiv;
   Settings.RRM_Lookback               = Inp_RRM_Lookback;
   Settings.RRM_MinDivPips             = Inp_RRM_MinDivPips;
   Settings.RequirePullback            = Inp_RequirePullback;
   Settings.PullbackLookback           = Inp_PullbackLookback;
   Settings.RequireRecoveryMomentum    = Inp_RequireRecoveryMomentum;
   Settings.Gate_UseMultiLayer         = Inp_UseMultiLayer;

   // Bias
   Settings.BiasEnabled          = Inp_BiasEnabled;
   Settings.BiasMode             = Inp_BiasMode;
   Settings.ManSide              = Inp_ManualSide;

   // Strategy selector -> AutoStrat + EMA roles
   // BiasFastID/BiasSlowID are role indices (0..3): 0=EMA1, 1=EMA2, 2=EMA3, 3=EMA4
   if(Inp_EmaStrategy == EMA_STRAT_1_PRICE_CROSS)
   {
      Settings.AutoStrat  = STRAT_PRICE_CROSS;
      Settings.BiasFastID = (int)ROLE_EMA1;
      Settings.BiasSlowID = (int)ROLE_EMA1;
   }
   else if(Inp_EmaStrategy == EMA_STRAT_2_CROSS_1_2)
   {
      Settings.AutoStrat  = STRAT_PAIR_CROSS;
      Settings.BiasFastID = (int)ROLE_EMA1;
      Settings.BiasSlowID = (int)ROLE_EMA2;
   }
   else if(Inp_EmaStrategy == EMA_STRAT_2_CROSS_3_4)
   {
      Settings.AutoStrat  = STRAT_PAIR_CROSS;
      Settings.BiasFastID = (int)ROLE_EMA3;
      Settings.BiasSlowID = (int)ROLE_EMA4;
   }
   else // EMA_STRAT_CUSTOM
   {
      Settings.BiasFastID = (int)Inp_BiasFast_Adv;
      Settings.BiasSlowID = (int)Inp_BiasSlow_Adv;
      Settings.AutoStrat  = (Settings.BiasFastID == Settings.BiasSlowID) ? STRAT_PRICE_CROSS : STRAT_PAIR_CROSS;
   }

   // Execution / indicator method
   Settings.MaType               = Inp_MaType;
   Settings.ma_h_shift           = Inp_MaHorShift;
   Settings.ma_v_shift           = Inp_MaVerShift;

   // Filters
   Settings.UseTime              = Inp_UseTime;
   Settings.StartHr              = Inp_StartHour;
   Settings.EndHr                = Inp_EndHour;
   Settings.UseNews              = Inp_UseNews;
   Settings.NewsPre              = Inp_NewsPre;
   Settings.NewsPost             = Inp_NewsPost;
   Settings.UseHTF               = Inp_UseHTF;
   Settings.HtfPeriod            = Inp_HtfPeriod;
   Settings.P_HtfEma             = Inp_HtfEmaPeriod;

   // Voting
   Settings.VoteThreshold        = Inp_VoteThreshold;
   Settings.VoteMode             = Inp_VoteMode;

   // Indicator periods / thresholds
   Settings.P_Ema1               = InpEma1Period;
   Settings.P_Ema2               = InpEma2Period;
   Settings.P_Ema3               = InpEma3Period;
   Settings.P_Ema4               = InpEma4Period;
   Settings.P_Adx                = InpAdxPeriod;
   Settings.T_Adx                = InpAdxThreshold;
   Settings.P_MacdFast           = InpMacdFast;
   Settings.P_MacdSlow           = InpMacdSlow;
   Settings.P_MacdSig            = InpMacdSig;
   Settings.P_Rsi                = InpRsiPeriod;
   Settings.T_RsiOB              = InpRsiOverbought;
   Settings.T_RsiOS              = InpRsiOversold;
   Settings.P_Cci                = InpCciPeriod;
   Settings.P_Mfi                = InpMfiPeriod;
   Settings.T_Mfi                = InpMfiLevel;
   Settings.T_MfiOB              = InpMfiLevel;
   Settings.T_MfiOS              = InpMfiLevel;
   Settings.P_StoK               = InpStoK;
   Settings.P_StoD               = InpStoD;
   Settings.P_StoSlow            = InpStoSlow;
   Settings.T_StoOB              = 80.0;
   Settings.T_StoOS              = 20.0;
   Settings.P_Bb                 = InpBbPeriod;
   Settings.P_BbDev              = InpBbDev;
   Settings.P_PsarStep           = InpPsarStep;
   Settings.P_PsarMax            = InpPsarMax;
   Settings.P_PsarTrailCushionATR= Inp_PSAR_TrailCushionATR;
   Settings.P_Atr                = 14;

   // Modes
   Settings.MacdMode             = InpMacdMode;
   Settings.RsiMode              = InpRsiMode;
   Settings.CciMode              = InpCciMode;
   Settings.StoMode              = InpStoMode;
   Settings.BbMode               = InpBbMode;

   // Active votes
   Settings.Use_EmaSig           = Inp_Use_EmaSig;
   Settings.Use_Adx              = Inp_Use_Adx;
   Settings.Use_Macd             = Inp_Use_Macd;
   Settings.Use_Rsi              = Inp_Use_Rsi;
   Settings.Use_Cci              = Inp_Use_Cci;
   Settings.Use_Mfi              = Inp_Use_Mfi;
   Settings.Use_Sto              = Inp_Use_Sto;
   Settings.Use_Bb               = Inp_Use_Bb;
   Settings.Use_Psar             = Inp_Use_Psar;
   Settings.Use_P123             = Inp_Use_P123;
   Settings.Use_Ross             = Inp_Use_Ross;

   // Per-indicator vote weights (1.0 = standard; weighted sum compared to VoteThreshold in THRESHOLD mode)
   Settings.W_EmaSig             = Inp_W_EmaSig;
   Settings.W_Adx                = Inp_W_Adx;
   Settings.W_Macd               = Inp_W_Macd;
   Settings.W_Rsi                = Inp_W_Rsi;
   Settings.W_Cci                = Inp_W_Cci;
   Settings.W_Mfi                = Inp_W_Mfi;
   Settings.W_Sto                = Inp_W_Sto;
   Settings.W_Bb                 = Inp_W_Bb;
   Settings.W_Psar               = Inp_W_Psar;
   Settings.W_P123               = Inp_W_P123;
   Settings.W_Ross               = Inp_W_Ross;

   // Exits
   Settings.SL_PlacementMode     = Inp_SL_PlacementMode;
   Settings.SL_Mult              = Inp_SL_Mult;
   Settings.SL_PsarPipsCushion   = Inp_SL_PsarPipsCushion;
   Settings.SL_SwingPipsCushion  = Inp_SL_SwingPipsCushion;
   Settings.SL_FixedPips         = Inp_SL_FixedPips;

   Settings.TP_Mult              = Inp_TP_Mult;
   Settings.Use_BE               = Inp_Use_BE;
   Settings.BE_Trig              = Inp_BE_Trig;
   Settings.BE_Buff              = Inp_BE_Buff;

   Settings.TrailMode            = Inp_TrailMode;
   Settings.Trail_Mult           = Inp_Trail_Mult;
   Settings.PSAR_TrailCushionMode= Inp_PSAR_TrailCushionMode;
   Settings.PSAR_TrailPipsCushion= Inp_PSAR_TrailPipsCushion;

   // === Strict non-ATR RRM exit contract (PR 1: config only, no executor reads these yet) ===
   // Defaults preserve existing behavior for all presets and CUSTOM mode.
   Settings.ExitProfile             = Inp_ExitProfile;    // LEGACY by default
   Settings.TP_Enabled              = true;               // TP active (mirrors TP_Mult>0 semantic)
   Settings.BE_Mode                 = BE_MODE_OFF;        // OFF = legacy ATR BE fields remain authoritative
   Settings.RRM_BE_ProgressPct      = 0.0;
   Settings.RRM_BE_RMultiple        = 1.0;
   Settings.RRM_BE_BufferPips       = 0.0;
   Settings.RRM_TrailPsarShiftDelay = 1;
   Settings.RRM_FreezeTrailOnFlip   = false;
   Settings.RRM_TrailStartsAfterBE  = false;

   // Gate system defaults (all gates off; presets may enable them)
   // RequirePullback, PullbackLookback, RequireRecoveryMomentum are mapped from inputs above
   Settings.Gate_Recovery.mode       = GATE_SCALE_OFF;
   Settings.Gate_Recovery.value      = 0.0;
   Settings.Gate_RecoveryLookback    = 5;
   Settings.Gate_EmaDiv.mode         = GATE_SCALE_OFF;
   Settings.Gate_EmaDiv.value        = 0.0;
   Settings.Gate_CandleDirection.mode  = GATE_SCALE_OFF;
   Settings.Gate_CandleDirection.value = 0.0;
   Settings.Gate_CandleCheckShift    = 1;
   Settings.Vote_EvalShift           = 1;
   Settings.Vote_AllowPsarFlip       = false;
}

//+------------------------------------------------------------------+
//| END OF FILE                                                      |
//+------------------------------------------------------------------+