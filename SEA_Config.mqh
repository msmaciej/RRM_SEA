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
   int VoteThreshold;

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
// Tags:
//   (Global; allowed under presets)                 - always honored
//   (Operator gate; preserved under presets)        - Policy A: user-controlled even under presets
//   (CUSTOM; presets override)                      - effective mainly in PRESET_CUSTOM
//   (CUSTOM; most presets override; strict sets 0)  - ATR gates forced off under strict RRM

input group "=== MASTER PRESET ==="
input ulong           Inp_MagicNum               = 12345;       // (Global) Magic number (trade identifier)
input EStrategyPreset InpPreset                 = PRESET_RRM;   // (Global) Strategy preset (presets may override many inputs below)

input group "=== ADMIN OVERRIDE: PRESET TESTING ==="
input bool           Inp_AdminOverridePreset        = false; // [Admin] Unlock preset parameters for testing (true=admin mode, false=normal user)

input group "--- ADMIN OVERRIDE: STRATEGY PARAMETERS ---"
input EAutoStrategy  Inp_Override_AutoStrat          = STRAT_PAIR_CROSS; // [Admin] Override AutoStrat when AdminOverride=true
input int            Inp_Override_VoteThreshold       = 4;                // [Admin] Override Vote Threshold when AdminOverride=true
input int            Inp_Override_EMA1               = 5;                 // [Admin] Override EMA1 period when AdminOverride=true
input int            Inp_Override_EMA2               = 13;                // [Admin] Override EMA2 period when AdminOverride=true
input int            Inp_Override_EMA3               = 34;                // [Admin] Override EMA3 period when AdminOverride=true
input int            Inp_Override_EMA4               = 89;                // [Admin] Override EMA4 period when AdminOverride=true
input int            Inp_Override_MACD_Fast           = 8;                // [Admin] Override MACD Fast period when AdminOverride=true
input int            Inp_Override_MACD_Slow           = 13;               // [Admin] Override MACD Slow period when AdminOverride=true
input int            Inp_Override_MACD_Signal         = 8;                // [Admin] Override MACD Signal period when AdminOverride=true
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

input group "--- ADMIN OVERRIDE: INDICATOR PARAMETERS ---"
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

input group "=== BENCHMARK: MT5 MOVING AVERAGE ==="
input double         Inp_MA_MaximumRiskPct      = 0.02;         // (PRESET_MA_BENCHMARK only) Max risk (%) for MA benchmark sizer
input double         Inp_MA_DecreaseFactor      = 3.0;          // (PRESET_MA_BENCHMARK only) Lot decrease factor
input int            Inp_MA_Period              = 12;           // (PRESET_MA_BENCHMARK only) MA period
input int            Inp_MA_Shift               = 6;            // (PRESET_MA_BENCHMARK only) MA shift

input group "=== DIAGNOSTICS ==="
input bool           Inp_PrintEffectiveConfig   = true;         // (Global; allowed under presets) Print effective config on init
input bool           Inp_DebugFlow              = false;        // (Global; allowed under presets) Print OnInit/OnTick/OnDeinit flow

input group "=== UI: STATUS PANEL ==="
input bool             Inp_UI_ShowStatusPanel     = false;      // (Global; allowed under presets) Show status panel
input bool             Inp_UI_ManageChartIndicators = false;    // (Global; allowed under presets) Auto-add/remove chart indicators
input ENUM_BASE_CORNER Inp_UI_PanelCorner       = CORNER_LEFT_UPPER; // (Global; allowed under presets) Status panel corner
input int              Inp_UI_PanelX            = 30;           // (Global; allowed under presets) Status panel X (px)
input int              Inp_UI_PanelY            = 30;           // (Global; allowed under presets) Status panel Y (px)
input int              Inp_UI_PanelFontSize     = 8;            // (Global; allowed under presets) Status panel font size
input int              Inp_UI_LineSpacingPx     = 21;           // (Global; allowed under presets) Status panel line spacing (px)
input string           Inp_UI_PanelFont         = "Arial";      // (Global; allowed under presets) Status panel font

input group "=== UI: COCKPIT PANEL ==="
input bool             Inp_UI_ShowCockpitPanel    = true;       // (Global; allowed under presets) Show cockpit panel
input ENUM_BASE_CORNER Inp_UI_CockpitCorner     = CORNER_LEFT_UPPER; // (Global; allowed under presets) Cockpit panel corner
input int              Inp_UI_CockpitX          = 30;           // (Global; allowed under presets) Cockpit panel X (px)
input int              Inp_UI_CockpitY          = 30;           // (Global; allowed under presets) Cockpit panel Y (px)
input int              Inp_UI_CockpitFontSize   = 8;            // (Global; allowed under presets) Cockpit panel font size
input int              Inp_UI_CockpitLineSpacingPx = 21;        // (Global; allowed under presets) Cockpit panel line spacing (px)
input string           Inp_UI_CockpitFont       = "Arial";      // (Global; allowed under presets) Cockpit panel font

input group "=== UI: SIGNAL MARKERS ==="
input bool           Inp_DrawEntryLines         = true;         // (Global; allowed under presets) Draw entry marker lines
input bool           Inp_DrawTradeLines         = true;         // (Global; allowed under presets) Draw trade management lines

input group "=== UI: COLORS ==="
input bool             Inp_UI_UseCustomColors   = false;        // (Global; allowed under presets) Use custom panel colors (else follow chart theme)
input color            Inp_UI_FontColor         = clrYellow;    // (Global; allowed under presets) UI font color (when custom colors enabled)
input int              Inp_UI_PanelBgAlpha      = 110;          // (Global; allowed under presets) Panel background alpha (0..255)

input group "=== UI: FRAMING (PANELS) ==="
input EUIFrameMode     Inp_UI_FrameMode          = UI_FRAME_BG; // (Global; allowed under presets) Panel frame mode (BG/NONE/TEXT_BOUNDS)
input int              Inp_UI_FramePadPx         = 6;           // (Global; allowed under presets) Panel padding (px)

input group "=== RRM STRICT (NON-ATR) ==="
input EExitProfile Inp_ExitProfile = EXIT_PROFILE_LEGACY;       // (CUSTOM; presets override) Exit profile override (strict presets force strict)

input group "=== PRESET_RRM: TREND PULLBACK ==="
input ERRMMode       Inp_RRM_Mode               = RRM_AUTO_BY_TF; // (RRM presets) RRM mode (AUTO uses timeframe mapping)
input bool           Inp_RRM_EnableInCustom     = false;          // (CUSTOM only) Enable RRM logic while using PRESET_CUSTOM
input EAutoStrategy  Inp_RRM_AutoStrat          = STRAT_PRICE_CROSS; // (CUSTOM; presets override) Auto strategy mapping (price cross / pair cross)
input EEmaRole       Inp_RRM_BiasEMA            = ROLE_EMA2;      // (CUSTOM; presets override) Bias EMA role (manual bias tuning)
input int            Inp_RRM_Lookback           = 5;              // (CUSTOM; presets override) Pullback lookback bars
input double         Inp_RRM_MinDivPips         = 0.5;            // (CUSTOM; presets override) Min EMA divergence (pips)
input bool           Inp_RRM_RequirePullbackReclaim = false;      // (CUSTOM; presets override) Require pullback + reclaim condition
input bool           Inp_RRM_RequireEmaDiv          = false;      // (CUSTOM; presets override) Require EMA divergence gate

input group "=== CUSTOM: LOGIC & RISK ==="
input bool           Inp_CloseOnReverse         = false;  // (CUSTOM; presets may override) Close on reverse signal
input double         Inp_RiskPercent            = 2.0;    // (CUSTOM; presets may override) Risk per trade (%)
input double         Inp_MaxSpreadPips          = 3.0;    // (Operator gate; preserved under presets) Max spread (pips)
input double         Inp_MinATRPips             = 0.0;    // (CUSTOM; most presets override; strict sets 0) Min ATR (pips)
input double         Inp_MaxATRPips             = 20.0;   // (CUSTOM; most presets override; strict sets 0) Max ATR (pips; 0=off)

input group "=== CUSTOM: MARKET BIAS ==="
input bool           Inp_BiasEnabled            = true;                 // (CUSTOM; presets override) Enable market bias filter
input EBiasMode      Inp_BiasMode               = BIAS_AUTO;            // (CUSTOM; presets override) Bias mode (AUTO/MANUAL)
input EEmaStrategy   Inp_EmaStrategy            = EMA_STRAT_2_CROSS_3_4; // (CUSTOM; presets override) EMA bias strategy mapping

input group "=== CUSTOM: ADVANCED AUTO MAPPING ==="
input EManualSide    Inp_ManualSide             = SIDE_BOTH;            // (CUSTOM; presets override) Manual direction (BOTH/LONG/SHORT)
input EEmaRole       Inp_BiasFast_Adv           = ROLE_EMA3;            // (CUSTOM; presets override) Advanced bias fast EMA role
input EEmaRole       Inp_BiasSlow_Adv           = ROLE_EMA4;            // (CUSTOM; presets override) Advanced bias slow EMA role

input group "=== CUSTOM: FILTERS ==="
input bool            Inp_UseTime                = false;              // (Operator gate; preserved under presets) Enable session/time filter
input int             Inp_StartHour              = 8;                  // (Operator gate; preserved under presets) Session start hour (broker time)
input int             Inp_EndHour                = 20;                 // (Operator gate; preserved under presets) Session end hour (broker time)
input bool            Inp_UseNews                = false;              // (Operator gate; preserved under presets) Enable news filter (CSV calendar)
input string          Inp_NewsFile               = "calendar_statement.csv"; // (Operator gate; preserved under presets) News CSV filename
input int             Inp_NewsPre                = 60;                 // (Operator gate; preserved under presets) Minutes before news to block entries
input int             Inp_NewsPost               = 60;                 // (Operator gate; preserved under presets) Minutes after news to block entries
input bool            Inp_UseHTF                 = false;              // (Operator gate; preserved under presets) Enable HTF trend filter
input ENUM_TIMEFRAMES Inp_HtfPeriod              = PERIOD_H4;          // (Operator gate; preserved under presets) HTF timeframe
input int             Inp_HtfEmaPeriod           = 89;                 // (Operator gate; preserved under presets) HTF EMA period

input group "=== CUSTOM: VOTING ==="
input int            Inp_VoteThreshold          = 2;                   // (CUSTOM; presets override) Votes required to enter (threshold)

input group "=== INDICATORS: SETTINGS ==="
input EMaMethod      Inp_MaType                 = METHOD_EMA;          // (CUSTOM; presets override) MA method (EMA/SMA)
input int            Inp_MaHorShift             = 0;                   // (CUSTOM; presets override) MA horizontal shift (bars)
input int            Inp_MaVerShift             = 1;                   // (CUSTOM; presets override) MA vertical shift (pips)

input group "--- INDICATORS: EMA ---"
input int            InpEma1Period              = 5;                   // (CUSTOM; presets override) EMA1 period
input int            InpEma2Period              = 13;                  // (CUSTOM; presets override) EMA2 period
input int            InpEma3Period              = 34;                  // (CUSTOM; presets override) EMA3 period
input int            InpEma4Period              = 89;                  // (CUSTOM; presets override) EMA4 period

input group "--- INDICATORS: ADX ---"
input int            InpAdxPeriod               = 14;                  // (CUSTOM; presets override) ADX period
input int            InpAdxThreshold            = 20;                  // (CUSTOM; presets override) ADX threshold

input group "--- INDICATORS: MACD ---"
input EMacdMode      InpMacdMode                = MACD_SIGNAL_ALIGN;   // (CUSTOM; presets override) MACD mode (signal align / zero cross)
input int            InpMacdFast                = 12;                  // (CUSTOM; presets override) MACD fast period
input int            InpMacdSlow                = 26;                  // (CUSTOM; presets override) MACD slow period
input int            InpMacdSig                 = 9;                   // (CUSTOM; presets override) MACD signal period

input group "--- INDICATORS: RSI ---"
input ERsiMode       InpRsiMode                 = RSI_FILTER_EXTREME;  // (CUSTOM; presets override) RSI mode
input int            InpRsiPeriod               = 14;                  // (CUSTOM; presets override) RSI period
input double         InpRsiOverbought           = 70.0;                // (CUSTOM; presets override) RSI overbought level
input double         InpRsiOversold             = 30.0;                // (CUSTOM; presets override) RSI oversold level

input group "--- INDICATORS: CCI ---"
input ECciMode       InpCciMode                 = CCI_TREND_ZERO;      // (CUSTOM; presets override) CCI mode
input int            InpCciPeriod               = 14;                  // (CUSTOM; presets override) CCI period

input group "--- INDICATORS: MFI ---"
input int            InpMfiPeriod               = 14;                  // (CUSTOM; presets override) MFI period
input double         InpMfiLevel                = 50.0;                // (CUSTOM; presets override) MFI threshold/level

input group "--- INDICATORS: STOCHASTIC ---"
input EStochMode     InpStoMode                 = STO_ZONE_FILTER;     // (CUSTOM; presets override) Stochastic mode
input int            InpStoK                    = 5;                   // (CUSTOM; presets override) Stochastic %K period
input int            InpStoD                    = 3;                   // (CUSTOM; presets override) Stochastic %D period
input int            InpStoSlow                 = 3;                   // (CUSTOM; presets override) Stochastic slowing

input group "--- INDICATORS: BOLLINGER BANDS ---"
input EBbMode        InpBbMode                  = BB_TREND_FOLLOW;     // (CUSTOM; presets override) Bollinger mode
input int            InpBbPeriod                = 20;                  // (CUSTOM; presets override) Bollinger period
input double         InpBbDev                   = 2.0;                 // (CUSTOM; presets override) Bollinger deviation

input group "--- INDICATORS: PSAR ---"
input double         InpPsarStep                = 0.05;                // (CUSTOM; presets override) PSAR step
input double         InpPsarMax                 = 0.5;                 // (CUSTOM; presets override) PSAR max

input group "=== VOTING: ENABLED VOTES ==="
input bool           Inp_Use_EmaSig             = true;                // (CUSTOM; presets override) Vote: EMA signal
input bool           Inp_Use_Adx                = false;               // (CUSTOM; presets override) Vote: ADX
input bool           Inp_Use_Macd               = true;                // (CUSTOM; presets override) Vote: MACD
input bool           Inp_Use_Rsi                = false;               // (CUSTOM; presets override) Vote: RSI
input bool           Inp_Use_Cci                = true;                // (CUSTOM; presets override) Vote: CCI
input bool           Inp_Use_Mfi                = false;               // (CUSTOM; presets override) Vote: MFI
input bool           Inp_Use_Sto                = false;               // (CUSTOM; presets override) Vote: Stochastic
input bool           Inp_Use_Bb                 = false;               // (CUSTOM; presets override) Vote: Bollinger
input bool           Inp_Use_Psar               = true;                // (CUSTOM; presets override) Vote: PSAR
input bool           Inp_Use_P123               = false;               // (CUSTOM; presets override) Vote: 1-2-3 pattern
input bool           Inp_Use_Ross               = false;               // (CUSTOM; presets override) Vote: Ross hook

input group "=== EXITS: INITIAL SL PLACEMENT ==="
input ESlPlacementMode Inp_SL_PlacementMode     = SL_SWING_HIGHLOW;    // (CUSTOM; presets override) SL placement method
input double         Inp_SL_Mult                = 1.5;                 // (CUSTOM; presets override) SL multiplier (ATR modes only; ignored in strict)
input double         Inp_SL_PsarPipsCushion     = 5.0;                 // (CUSTOM; presets override) SL PSAR cushion (pips)
input double         Inp_SL_SwingPipsCushion    = 10.0;                // (CUSTOM; presets override) SL swing cushion (pips)
input double         Inp_SL_FixedPips           = 20.0;                // (CUSTOM; presets override) SL fixed distance (pips)

input group "=== EXITS: TP, BREAKEVEN, TRAILING ==="
input double         Inp_TP_Mult                = 3.0;                 // (CUSTOM; presets override) TP R-multiple (legacy TP_Mult)
input bool           Inp_Use_BE                 = false;               // (CUSTOM; presets override) Use legacy BE (strict uses BE_Mode instead)
input double         Inp_BE_Trig                = 1.0;                 // (CUSTOM; presets override) Legacy BE trigger (R multiple)
input double         Inp_BE_Buff                = 0.1;                 // (CUSTOM; presets override) Legacy BE buffer (pips)

input group "=== EXITS: TRAILING STOP ==="
input ETrailingMode  Inp_TrailMode              = TRAIL_PSAR;          // (CUSTOM; presets override) Trailing stop mode
input double         Inp_Trail_Mult             = 3.0;                 // (CUSTOM; presets override) Trail multiplier (ATR modes only; ignored in strict)
input EPsarTrailCushionMode Inp_PSAR_TrailCushionMode = PSAR_CUSHION_PIPS; // (CUSTOM; presets override) PSAR trail cushion mode
input double         Inp_PSAR_TrailPipsCushion  = 5.0;                 // (CUSTOM; presets override) PSAR trail cushion (pips)
input double         Inp_PSAR_TrailCushionATR   = 0.2;                 // (CUSTOM; presets override) PSAR trail cushion (ATR)

input group "=== REPORTING ==="
input bool           Inp_ExportCSV              = false;               // (Global; allowed under presets) Export CSV reporting
input bool           Inp_ExportUseCommonFiles   = false;               // (Global; allowed under presets) Use terminal Common Files folder for export

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
}

//+------------------------------------------------------------------+
//| END OF FILE                                                      |
//+------------------------------------------------------------------+