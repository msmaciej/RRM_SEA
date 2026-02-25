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
   PRESET_RRM,                // PRESET - RRM Strict No-ATR Trend Pullback
   PRESET_RRM_STRICT,         // PRESET - RRM (deprecated alias of PRESET_RRM)
   PRESET_RRM_LEGACY          // PRESET - RRM Legacy/old behavior
   PRESET_RRM,                // PRESET - RRM Strict No-ATR Trend Pullback (default)
   PRESET_RRM_STRICT,         // PRESET - DEPRECATED: alias for PRESET_RRM (kept for .set file compatibility)
   PRESET_RRM_LEGACY          // PRESET - RRM Legacy Trend Pullback (original pre-PR3 behavior)
};

// --- RRM MODE (for PRESET_RRM / PRESET_RRM_ATR / PRESET_RRM_LEGACY) ---
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
   int    P_StoK;
   int    P_StoD;
   int    P_StoSlow;
   int    P_Bb;
   double P_BbDev;
   double P_PsarStep;
   double P_PsarMax;
   double P_PsarTrailCushionATR;

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
//| INPUT PARAMETERS                                                  |
//+------------------------------------------------------------------+

input group "=== MASTER PRESET ==="
input ulong           Inp_MagicNum               = 12345;       // Unique Magic Number
input EStrategyPreset InpPreset                 = PRESET_RRM;   // Select Preset Mode

input group "=== BENCHMARK: MT5 MOVING AVERAGE ==="
input double         Inp_MA_MaximumRiskPct      = 0.02;         // (MA_BENCHMARK only) Max risk fraction per lot step
input double         Inp_MA_DecreaseFactor      = 3.0;          // (MA_BENCHMARK only) Lot decrease factor
input int            Inp_MA_Period              = 12;           // (MA_BENCHMARK only) Moving average period
input int            Inp_MA_Shift               = 6;            // (MA_BENCHMARK only) MA bar shift

input group "=== DIAGNOSTICS ==="
// global allowed under presets
input bool           Inp_PrintEffectiveConfig   = true;         // (Global) Print effective config on init
// global allowed under presets
input bool           Inp_DebugFlow              = false;        // (Global) Print OnInit/OnTick/OnDeinit flow

input group "=== UI: STATUS PANEL ==="
// global allowed under presets
input bool             Inp_UI_ShowStatusPanel     = false;       // (Global) Show status panel on chart
// global allowed under presets
input bool             Inp_UI_ManageChartIndicators = false;     // (Global) Auto-manage chart indicators
input ENUM_BASE_CORNER Inp_UI_PanelCorner       = CORNER_LEFT_UPPER;
input int              Inp_UI_PanelX            = 30;
input int              Inp_UI_PanelY            = 30;
input int              Inp_UI_PanelFontSize     = 8;
input int              Inp_UI_LineSpacingPx     = 21;
input string           Inp_UI_PanelFont         = "Arial";

input group "=== UI: COCKPIT PANEL ==="
// global allowed under presets
input bool             Inp_UI_ShowCockpitPanel    = true;        // (Global) Show cockpit panel on chart
input ENUM_BASE_CORNER Inp_UI_CockpitCorner     = CORNER_LEFT_UPPER;
input int              Inp_UI_CockpitX          = 30;
input int              Inp_UI_CockpitY          = 30;
input int              Inp_UI_CockpitFontSize   = 8;
input int              Inp_UI_CockpitLineSpacingPx = 21;
input string           Inp_UI_CockpitFont       = "Arial";

input group "=== UI: SIGNAL MARKERS ==="
// global allowed under presets
input bool           Inp_DrawEntryLines         = true;          // (Global) Draw entry signal lines on chart
// global allowed under presets
input bool           Inp_DrawTradeLines         = true;          // (Global) Draw active trade lines on chart

input group "=== UI: COLORS ==="
// global allowed under presets
input bool             Inp_UI_UseCustomColors   = false;        // If false, follow chart theme
input color            Inp_UI_FontColor         = clrYellow;    // Used only if UseCustomColors=true
input int              Inp_UI_PanelBgAlpha      = 110;          // 0..255 (higher = more opaque)

input group "=== UI: FRAMING (PANELS) ==="
// global allowed under presets
input EUIFrameMode     Inp_UI_FrameMode          = UI_FRAME_BG;   // BG | NONE | TEXT_BOUNDS
input int              Inp_UI_FramePadPx         = 6;             // Padding used for text + BG sizing

input group "=== RRM STRICT (NON-ATR) ==="
// Selects exit contract; default LEGACY preserves all current ATR-based behavior (no behavior change in PR 1).
input EExitProfile Inp_ExitProfile = EXIT_PROFILE_LEGACY;  // Exit profile (LEGACY = current behavior)

input group "=== PRESET_RRM: TREND PULLBACK ==="
input ERRMMode       Inp_RRM_Mode               = RRM_AUTO_BY_TF;      // (RRM/RRM_ATR/RRM_LEGACY) Scalp or swing auto/manual
input bool           Inp_RRM_EnableInCustom     = false;               // (CUSTOM only) Enable RRM pullback trigger
input EAutoStrategy  Inp_RRM_AutoStrat          = STRAT_PRICE_CROSS;   // (CUSTOM; presets override) RRM bias strategy
input EEmaRole       Inp_RRM_BiasEMA            = ROLE_EMA2;           // (CUSTOM; presets override) EMA role for RRM bias
input int            Inp_RRM_Lookback           = 5;                   // (CUSTOM; presets override) Lookback bars for pullback
input double         Inp_RRM_MinDivPips         = 0.5;                 // (CUSTOM; presets override) Min EMA divergence pips
input bool           Inp_RRM_RequirePullbackReclaim = false;           // (CUSTOM; presets override) Require price reclaim
input bool           Inp_RRM_RequireEmaDiv          = false;           // (CUSTOM; presets override) Require EMA divergence

input group "=== CUSTOM: LOGIC & RISK ==="
input bool           Inp_CloseOnReverse         = false;  // (CUSTOM; presets override) Close on opposing signal
input double         Inp_RiskPercent            = 2.0;    // (CUSTOM; presets override) Risk % of account per trade
input double         Inp_MaxSpreadPips          = 3.0;    // (Operator gate; preserved under presets) Max spread pips
input double         Inp_MinATRPips             = 0.0;    // (Operator gate; most presets restore; strict sets 0) Min ATR
input double         Inp_MaxATRPips             = 20.0;   // (Operator gate; most presets restore; strict sets 0) Max ATR

input group "=== CUSTOM: MARKET BIAS ==="
input bool           Inp_BiasEnabled            = true;                      // (CUSTOM; presets override) Enable directional bias
input EBiasMode      Inp_BiasMode               = BIAS_AUTO;                 // (CUSTOM; presets override) Manual or auto bias
input EEmaStrategy   Inp_EmaStrategy            = EMA_STRAT_2_CROSS_3_4;      // (CUSTOM; presets override) EMA pair for bias

input group "=== CUSTOM: ADVANCED AUTO MAPPING ==="
input EManualSide    Inp_ManualSide             = SIDE_BOTH;                 // (CUSTOM; presets override) Manual trade side
input EEmaRole       Inp_BiasFast_Adv           = ROLE_EMA3;                 // (CUSTOM; presets override) Fast EMA for custom bias
input EEmaRole       Inp_BiasSlow_Adv           = ROLE_EMA4;                 // (CUSTOM; presets override) Slow EMA for custom bias

input group "=== CUSTOM: FILTERS ==="
input bool            Inp_UseTime                = false;                    // (Operator gate; preserved under presets) Use session filter
input int             Inp_StartHour              = 8;                        // (Operator gate; preserved under presets) Session start hour
input int             Inp_EndHour                = 20;                       // (Operator gate; preserved under presets) Session end hour
input bool            Inp_UseNews                = false;                    // (Operator gate; preserved under presets) Use news filter
input string          Inp_NewsFile               = "calendar_statement.csv";
input int             Inp_NewsPre                = 60;                       // (Operator gate; preserved under presets) Mins blocked pre-news
input int             Inp_NewsPost               = 60;                       // (Operator gate; preserved under presets) Mins blocked post-news
input bool            Inp_UseHTF                 = false;                    // (Operator gate; preserved under presets) Use higher TF filter
input ENUM_TIMEFRAMES Inp_HtfPeriod              = PERIOD_H4;                // (Operator gate; preserved under presets) Higher timeframe
input int             Inp_HtfEmaPeriod           = 89;                       // (Operator gate; preserved under presets) HTF EMA period

input group "=== CUSTOM: VOTING ==="
input int            Inp_VoteThreshold          = 2;                         // (CUSTOM; presets override) Min votes needed to enter

input group "=== INDICATORS: SETTINGS ==="
input EMaMethod      Inp_MaType                 = METHOD_EMA;                // (CUSTOM; presets override) MA type: EMA or SMA
input int            Inp_MaHorShift             = 0;                         // (CUSTOM; presets override) MA horizontal bar offset
input int            Inp_MaVerShift             = 1;                         // (CUSTOM; presets override) MA vertical price offset

// EMA
input group "--- INDICATORS: EMA ---"
input int            InpEma1Period              = 5;                         // (CUSTOM; presets override) EMA1 period (scalp fast)
input int            InpEma2Period              = 13;                        // (CUSTOM; presets override) EMA2 period (scalp slow)
input int            InpEma3Period              = 34;                        // (CUSTOM; presets override) EMA3 period (swing fast)
input int            InpEma4Period              = 89;                        // (CUSTOM; presets override) EMA4 period (swing slow)

// ADX
input group "--- INDICATORS: ADX ---"
input int            InpAdxPeriod               = 14;                        // (CUSTOM; presets override) ADX period
input int            InpAdxThreshold            = 20;                        // (CUSTOM; presets override) ADX trend-strength threshold

// MACD
input group "--- INDICATORS: MACD ---"
input EMacdMode      InpMacdMode                = MACD_SIGNAL_ALIGN;         // (CUSTOM; presets override) MACD mode
input int            InpMacdFast                = 12;                        // (CUSTOM; presets override) MACD fast period
input int            InpMacdSlow                = 26;                        // (CUSTOM; presets override) MACD slow period
input int            InpMacdSig                 = 9;                         // (CUSTOM; presets override) MACD signal period

// RSI
input group "--- INDICATORS: RSI ---"
input ERsiMode       InpRsiMode                 = RSI_FILTER_EXTREME;        // (CUSTOM; presets override) RSI mode
input int            InpRsiPeriod               = 14;                        // (CUSTOM; presets override) RSI period
input double         InpRsiOverbought           = 70.0;                      // (CUSTOM; presets override) RSI overbought level
input double         InpRsiOversold             = 30.0;                      // (CUSTOM; presets override) RSI oversold level

// CCI
input group "--- INDICATORS: CCI ---"
input ECciMode       InpCciMode                 = CCI_TREND_ZERO;            // (CUSTOM; presets override) CCI mode
input int            InpCciPeriod               = 14;                        // (CUSTOM; presets override) CCI period

// MFI
input group "--- INDICATORS: MFI ---"
input int            InpMfiPeriod               = 14;                        // (CUSTOM; presets override) MFI period
input double         InpMfiLevel                = 50.0;                      // (CUSTOM; presets override) MFI threshold level

// Stochastic
input group "--- INDICATORS: STOCHASTIC ---"
input EStochMode     InpStoMode                 = STO_ZONE_FILTER;           // (CUSTOM; presets override) Stochastic mode
input int            InpStoK                    = 5;                         // (CUSTOM; presets override) Stochastic %K period
input int            InpStoD                    = 3;                         // (CUSTOM; presets override) Stochastic %D period
input int            InpStoSlow                 = 3;                         // (CUSTOM; presets override) Stochastic slowing period

// Bollinger
input group "--- INDICATORS: BOLLINGER BANDS ---"
input EBbMode        InpBbMode                  = BB_TREND_FOLLOW;           // (CUSTOM; presets override) Bollinger Bands mode
input int            InpBbPeriod                = 20;                        // (CUSTOM; presets override) Bollinger Bands period
input double         InpBbDev                   = 2.0;                       // (CUSTOM; presets override) Bollinger Bands deviation

// PSAR
input group "--- INDICATORS: PSAR ---"
input double         InpPsarStep                = 0.05;                      // (CUSTOM; presets override) PSAR acceleration step
input double         InpPsarMax                 = 0.5;                       // (CUSTOM; presets override) PSAR max acceleration

input group "=== VOTING: ENABLED VOTES ==="
input bool           Inp_Use_EmaSig             = true;                      // (CUSTOM; presets override) Use EMA signal vote
input bool           Inp_Use_Adx                = false;                     // (CUSTOM; presets override) Use ADX vote
input bool           Inp_Use_Macd               = true;                      // (CUSTOM; presets override) Use MACD vote
input bool           Inp_Use_Rsi                = false;                     // (CUSTOM; presets override) Use RSI vote
input bool           Inp_Use_Cci                = true;                      // (CUSTOM; presets override) Use CCI vote
input bool           Inp_Use_Mfi                = false;                     // (CUSTOM; presets override) Use MFI vote
input bool           Inp_Use_Sto                = false;                     // (CUSTOM; presets override) Use Stochastic vote
input bool           Inp_Use_Bb                 = false;                     // (CUSTOM; presets override) Use Bollinger Bands vote
input bool           Inp_Use_Psar               = true;                      // (CUSTOM; presets override) Use PSAR vote
input bool           Inp_Use_P123               = false;                     // (CUSTOM; presets override) Use P123 pattern vote
input bool           Inp_Use_Ross               = false;                     // (CUSTOM; presets override) Use Ross hook vote

input group "=== EXITS: INITIAL SL PLACEMENT ==="
input ESlPlacementMode Inp_SL_PlacementMode     = SL_SWING_HIGHLOW;          // (CUSTOM; presets override) SL placement method
input double         Inp_SL_Mult                = 1.5;                       // (CUSTOM; presets override) ATR multiplier for SL
input double         Inp_SL_PsarPipsCushion     = 5.0;                       // (CUSTOM; presets override) PSAR SL pip cushion
input double         Inp_SL_SwingPipsCushion    = 10.0;                      // (CUSTOM; presets override) Swing SL pip cushion
input double         Inp_SL_FixedPips           = 20.0;                      // (CUSTOM; presets override) Fixed SL in pips

input group "=== EXITS: TP, BREAKEVEN, TRAILING ==="
input double         Inp_TP_Mult                = 3.0;                       // (CUSTOM; presets override) TP as R-multiple of SL
input bool           Inp_Use_BE                 = false;                     // (CUSTOM; presets override) Enable breakeven stop
input double         Inp_BE_Trig                = 1.0;                       // (CUSTOM; presets override) BE trigger: R-multiple of SL
input double         Inp_BE_Buff                = 0.1;                       // (CUSTOM; presets override) BE buffer in ATR units

input group "=== EXITS: TRAILING STOP ==="
input ETrailingMode  Inp_TrailMode              = TRAIL_PSAR;                // (CUSTOM; presets override) Trailing stop mode
input double         Inp_Trail_Mult             = 3.0;                       // (CUSTOM; presets override) ATR trailing multiplier
input EPsarTrailCushionMode Inp_PSAR_TrailCushionMode = PSAR_CUSHION_PIPS;   // (CUSTOM; presets override) PSAR trail cushion type
input double         Inp_PSAR_TrailPipsCushion  = 5.0;                       // (CUSTOM; presets override) PSAR trail pip cushion
input double         Inp_PSAR_TrailCushionATR   = 0.2;                       // (CUSTOM; presets override) PSAR trail ATR multiplier

input group "=== REPORTING ==="
// global allowed under presets
input bool           Inp_ExportCSV              = false;                     // (Global) Export trade log to CSV
// global allowed under presets
input bool           Inp_ExportUseCommonFiles   = false;                     // (Global) Use MT5 common files folder for CSV

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
   Settings.P_StoK               = InpStoK;
   Settings.P_StoD               = InpStoD;
   Settings.P_StoSlow            = InpStoSlow;
   Settings.P_Bb                 = InpBbPeriod;
   Settings.P_BbDev              = InpBbDev;
   Settings.P_PsarStep           = InpPsarStep;
   Settings.P_PsarMax            = InpPsarMax;
   Settings.P_PsarTrailCushionATR= Inp_PSAR_TrailCushionATR;

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