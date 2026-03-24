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
   PRESET_CUSTOM,          // PRESET_CUSTOM: user-defined settings
   PRESET_MA,              // PRESET_MA: benchmark: MT5 MA EA compatibility
   PRESET_RRM,             // PRESET_RRM: phase-based layer detection system
   PRESET_TEST             // PRESET_TEST: development/debugging preset
};

// --- SIMPLE EMA SELECTOR ---
enum EEmaStrategy
{
   EMA_STRAT_1_PRICE_CROSS,   // EMA_STRAT_1: Buy if Price > EMA1 (Benchmark)
   EMA_STRAT_2_CROSS_1_2,     // EMA_STRAT_2: Buy if EMA1 > EMA2 (Golden Cross)
   EMA_STRAT_2_CROSS_3_4,     // EMA_STRAT_2: Buy if EMA3 > EMA4 (Slow Trend)
   EMA_STRAT_CUSTOM           // EMA_STRAT_CUSTOM: manual: use "Advanced Bias" inputs below
};

// --- MA METHOD SELECTOR ---
enum EMaMethod
{
   METHOD_EMA,       // METHOD_EMA: exponential
   METHOD_SMA        // METHOD_SMA: simple
};

// --- BIAS MODE: how market direction is determined ---
enum EBiasMode
{
   BIAS_MANUAL,      // BIAS_MANUAL: direction (LONG_ONLY, SHORT_ONLY, BOTH)
   BIAS_AUTO,        // BIAS_AUTO: direction and slope (single or dual EMA)
   BIAS_AUTO_PHASE   // BIAS_AUTO_PHASE: market phase bias (4-EMA structure → TRENDING/EMERGING/UNORDERED)
};

// --- MARKET PHASE: used by BIAS_AUTO_PHASE (4-EMA structure analysis) ---
enum EMarketPhase {
   PHASE_UNORDERED,     // PHASE_UNO: block all trades (TS = 0)
   PHASE_EMERGING,      // PHASE_EM: Trend forming (EMA4 between EMA2/EMA3)
   PHASE_TRENDING,      // PHASE_MT: strong established trend
   PHASE_TRENDING_UP,   // PHASE_MT_UP: trending bullish: slopes up + EMA2>EMA3>EMA4
   PHASE_TRENDING_DN,   // PHASE_MT_DN: trending bearish: slopes down + EMA2<EMA3<EMA4
   PHASE_EMERGING_UP,   // PHASE_EM_UP: emerging bullish: slopes up + EMA4 between EMA2 and EMA3
   PHASE_EMERGING_DN    // PHASE_EM_DN: emerging bearish: slopes down + EMA4 between EMA2 and EMA3
};

// --- ENTRY LAYER: bitfield identifying EMA pullback zone (Layer 1/2/3) ---
// Each layer is a power-of-2 flag (combinable via OR).
enum EEntryLayer {
   LAYER_NONE        = 0,  // LAYER_NONE: 0b0000 — No layer detected or detection disabled
   LAYER_1_WEAK      = 1,  // LAYER_WEAK: 0b0001 — Layer 1: EMA1-EMA2 "Ribbon" zone (shallow pullback)
   LAYER_2_MEDIUM    = 2,  // LAYER_MEDIUM: 0b0010 — Layer 2: EMA2-EMA3 "Ghost" zone (medium pullback)
   LAYER_3_STRONG    = 4,  // LAYER_STRONG: 0b0100 — Layer 3: EMA3-EMA4 "Shark" zone (deep pullback)
   LAYER_1_2         = 3,  // LAYER_1-2: 0b0011 — L1 + L2 active simultaneously
   LAYER_2_3         = 6,  // LAYER_2-3: 0b0110 — L2 + L3 active simultaneously
   LAYER_1_2_3       = 7   // LAYER_1-2-3: 0b0111 — All three layers active simultaneously
};

enum EManualSide
{
   SIDE_BOTH,     // SIDE_L-S: Allow both long and short trades
   SIDE_LONG,     // SIDE_L: Long trades only
   SIDE_SHORT     // SIDE_S: Short trades only
};

enum EAutoStrategy
{
   STRAT_SINGLE_SLOPE,      // STRAT_SINGLE_SLOPE: 1EMA slope direction
   STRAT_PAIR_CROSS,        // STRAT_PAIR_CROSS: 2EMAs cross (one-bar signal at cross point)
   STRAT_PRICE_CROSS,       // STRAT_PRICE_CROSS: Price crosses EMA (one-bar signal at cross point)
   STRAT_POSITION_SLOPE,    // STRAT_POSITION_SLOPE: EMA position + slope confirmation (persistent bias)
   STRAT_LAYER_DETECTION    // STRAT_LAYER_DETECTION: Layer-based pullback detection (Strong/Medium/Weak layers)
};

enum EDebugLevel
{
   DEBUG_SILENT,      // DEBUG_SILENT: No per-bar output (statistics only at end)
   DEBUG_SUMMARY,     // DEBUG_SUMMARY: Per-bar: signal result + rejection reason (1-2 lines)
   DEBUG_INDICATORS,  // DEBUG_INDICATORS: Per-bar: indicator pass/fail + summary (20-30 lines)
   DEBUG_FULL         // DEBUG_FULL: Everything: all internal steps + diagnostics (50+ lines)
};

enum EEmaRole
{
   ROLE_EMA1,     // ROLE_EMA1: Fast EMA (5-period default) - L1_WEAK layer
   ROLE_EMA2,     // ROLE_EMA2: Medium-fast EMA (13-period default) - L2_MEDIUM layer
   ROLE_EMA3,     // ROLE_EMA3: Medium-slow EMA (34-period default) - L3_STRONG layer
   ROLE_EMA4      // ROLE_EMA4: Slow EMA (144-period default) - Trend filter
};

// Indicator Modes

// MACD Vote Mode: two-tier architecture (base mode + optional filters)
enum EMacdVoteMode
{
   // === SINGLE CHECKS (persistent) ===
   MACD_ZERO_LINE,      // MACD_ZERO_LINE: Main > 0 (bullish momentum zone)
   MACD_HISTOGRAM,      // MACD_HISTOGRAM: Histogram > 0 (acceleration)
   MACD_CROSSOVER,      // MACD_CROSSOVER: Main > Signal (momentum shift)

   // === COMBINATION CHECKS (persistent, strict) ===
   MACD_ZERO_AND_CROSS, // MACD_Zero+Crossover (RRM default, industry "traditional")
   MACD_ZERO_AND_HIST,  // MACD_Zero+Histogram (strict momentum)
   MACD_TRIPLE,         // MACD_Zero+Cross+Histogram (ultra-strict)

   // === TIME-LIMITED (fresh signals only) ===
   MACD_CROSSOVER_N,    // MACD_CROSS_N: Fresh crossover (within N bars)
   MACD_ZERO_CROSS_N    // MACD_ZERO_CROSS_N: Fresh zero cross (within N bars)
};

// Returns human-readable description of active MACD configuration
string GetMACDModeDescription(EMacdVoteMode mode, bool has_slope, bool has_div, bool has_hook)
{
   string base = "";
   switch(mode) {
      case MACD_ZERO_LINE:      base = "Main>0 (momentum zone)"; break;
      case MACD_HISTOGRAM:      base = "Histogram>0 (acceleration)"; break;
      case MACD_CROSSOVER:      base = "Main>Signal (shift)"; break;
      case MACD_ZERO_AND_CROSS: base = "Main>0 AND Main>Signal (traditional)"; break;
      case MACD_ZERO_AND_HIST:  base = "Main>0 AND Histogram>0 (strict)"; break;
      case MACD_TRIPLE:         base = "Zero+Cross+Hist (ultra-strict)"; break;
      case MACD_CROSSOVER_N:    base = "Fresh crossover (within N bars)"; break;
      case MACD_ZERO_CROSS_N:   base = "Fresh zero cross (within N bars)"; break;
   }
   string filters = "";
   if(has_slope) filters += " +SLOPE";
   if(has_div)   filters += " +DIVERGENCE";
   if(has_hook)  filters += " +HOOK";
   return base + filters;
}

enum ERsiMode
{
   RSI_FILTER_EXTREME,    // Extreme zones only (>70 overbought, <30 oversold)
   RSI_TREND_ABOVE_50,    // Trend following (>50 bullish, <50 bearish)
   RSI_CROSS_LEVEL        // Cross 50-level signal
};

enum ECciMode
{
   CCI_TREND_ZERO,        // Trend based on zero line (>0 bull, <0 bear)
   CCI_IMPULSE_100        // Strong impulse (>100 or <-100)
};

enum EStochMode
{
   STO_CROSS_SIGNAL,      // %K crosses %D signal line
   STO_ZONE_FILTER        // Overbought/oversold zones (>80 / <20)
};

enum EBbMode
{
   BB_TREND_FOLLOW,       // BE_TREND_FOLLOW: Price near outer band = trend continuation
   BB_MEAN_REVERSION      // BE_MEAN_REVERSION: Price at outer band = reversion to middle
};

// --- TRAILING STOP MODE ---
enum ETrailingMode
{
   TRAIL_BREAKEVEN,       // TRAIL_BREAKEVEN: move to breakeven then trail fixed pips
   TRAIL_FIXED_PIPS,      // TRAIL_FIXED_PIPS: fixed pip distance trailing
   TRAIL_FRACTAL,         // TRAIL_FRACTAL: fractal-based trailing
   TRAIL_NONE,            // TRAIL_NONE: no trailing stop
   TRAIL_PROFIT_PERCENT,  // TRAIL_PROFIT_PERCENT: trail after profit % threshold reached
   TRAIL_PSAR,            // TRAIL_PSAR: dot trailing
   TRAIL_PSAR_FLIP_EXIT   // TRAIL_PSAR_FLIP_EXIT: close position on PSAR flip
};

// --- PSAR TRAIL CUSHION MODE ---
enum EPsarTrailCushionMode
{
   PSAR_CUSHION_PIPS      // Fixed pips cushion
};

// --- STOP LOSS STRATEGY MODE ---
enum ESLMode
{
   SL_MODE_FIXED_PIPS,  // SL_MODE_FIXED_PIPS: Fixed pips (default)
   SL_MODE_FRACTAL,     // SL_MODE_FRACTAL: Last fractal level (Bill Williams)
   SL_MODE_PERCENT,     // SL_MODE_PERCENT: Percentage of entry price
   SL_MODE_SWING,       // SL_MODE_SWING: Recent swing high/low (SwingLookback bars)
   SL_MODE_PSAR_DOT     // SL_MODE_PSAR_DOT: PSAR dot position
};

// --- TAKE PROFIT STRATEGY MODE ---
enum ETPMode
{
   TP_MODE_FIXED_PIPS,  // TP_MODE_FIXED_PIPS: (default)
   TP_MODE_RR,          // TP_MODE_RR: (TP = SL distance × RRRatio)
   TP_MODE_FRACTAL,     // TP_MODE_FRACTAL: Next fractal level as TP target
   TP_MODE_PSAR_FLIP,   // TP_MODE_PSAR_FLIP: Exit when PSAR flips (TP handled by TM)
   TP_MODE_NONE         // TP_MODE_NONE: No TP, rely on trailing stop only
};

// --- TRAILING STOP TRIGGER CONDITION ---
enum ETrailTrigger
{
   TRIGGER_IMMEDIATE,       // TRIGGER_IMMEDIATE: Tr from entry (default)
   TRIGGER_BREAKEVEN,       // TRIGGER_BREAKEVEN: Tr after breakeven threshold reached
   TRIGGER_PROFIT_PIPS,     // TRIGGER_PROFIT_PIPS: Tr after X pips profit (TrailDistancePips)
   TRIGGER_PROFIT_PERCENT,  // TRIGGER_PROFIT_PERCENT: Tr after X% profit (TrailProfitPercent)
   TRIGGER_PSAR_ALIGN       // TRIGGER_PSAR_ALIGN: Tr when PSAR aligns with position direction
};

// --- EXIT PROFILE SELECTOR ---
// Selects the exit contract for a trade.
enum EExitProfile
{
   EXIT_PROFILE_NONE,      // EXIT_PROFILE_NONE: No exit profile (manual management)
   EXIT_PROFILE_SIMPLE,    // EXIT_PROFILE_SIMPLE: Simple: Fixed SL/TP, basic trailing
   EXIT_PROFILE_RRM        // EXIT_PROFILE_RRM: RRM: Swing-based SL, PSAR trail, no ATR multipliers
};

// --- MFI MODE SELECTOR ---
enum EMfiMode
{
   MFI_ZONE_FILTER,       // Zone-based filtering (>80 overbought, <20 oversold)
   MFI_TREND_50           // Trend following (>50 bullish, <50 bearish)
};

// --- RRM MODE SELECTOR (for PRESET_RRM adaptive configuration) ---
enum ERRMMode
{
   RRM_AUTO_BY_TF,        // RRM_AUTO_BY_TF: Auto-select scalp/swing based on timeframe (M1-M15=scalp, M30+=swing)
   RRM_SCALP,             // RRM_SCALP: Scalp: Tight SL/TP, Layer 1 entries, fast exits
   RRM_SWING              // RRM_SWING: Swing: Wide SL/TP, Layer 2-3 entries, patient exits
};

// --- BREAKEVEN MODE SELECTOR ---
// Controls how breakeven is triggered under the non-ATR RRM exit profile.
enum EBeMode
{
   BE_MODE_OFF,                // BE_MODE_OFF: Breakeven disabled (default)
   BE_MODE_TP_PROGRESS_PCT,    // BE_MODE_TP_PROGRESS_PCT: BE triggers at % progress toward TP (used with TP enabled)
   BE_MODE_R_MULTIPLE          // BE_MODE_R_MULTIPLE: BE triggers at k*R multiple (used when TP is disabled)
};

// --- GATE SCALING MODES ---
enum EGateScaleMode
{
   GATE_SCALE_OFF,        // GATE_OFF: Gate disabled
   GATE_SCALE_FIXED,      // GATE_FIXED: Use fixed pip value
   GATE_SCALE_AUTO_TF     // GATE_AUTO: Auto-scale by timeframe/pair
};

// --- VOTE MODE SELECTOR ---
enum EVoteMode
{
   VOTE_MODE_THRESHOLD,   // VOTE_THRESHOLD: minimum weighted votes required (default)
   VOTE_MODE_ALL          // VOTE_ALL: every enabled indicator must agree
};

// --- ADX VALIDATION MODES ---
enum EADXMode {
   ADX_MODE_STATIC = 0,           // Fixed threshold (current behavior)
   ADX_MODE_DYNAMIC_PERCENTILE,   // Adaptive threshold based on historical percentile
   ADX_MODE_PHASE_AWARE           // Phase-specific thresholds
};

// --- ADAPTIVE SETTINGS: PAIR TYPE ---
enum EPairType
{
   PAIR_TYPE_AUTO,         // Auto-detect from symbol name
   PAIR_TYPE_MAJOR,        // EUR/USD, GBP/USD, etc (tight spreads 1-2 pips)
   PAIR_TYPE_MINOR,        // EUR/GBP, EUR/AUD, etc (medium spreads 2-4 pips)
   PAIR_TYPE_EXOTIC,       // USD/TRY, USD/ZAR, etc (wide spreads 5-15 pips)
   PAIR_TYPE_GOLD,         // XAU/USD (medium spreads 3-5 pips, high volatility)
   PAIR_TYPE_CRYPTO        // BTC/USD (very wide spreads, extreme volatility)
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

//+------------------------------------------------------------------+
//| ENUM: Slope Measurement Mode                                     |
//+------------------------------------------------------------------+
enum ESlopeMeasure
{
   SLOPE_MEASURE_PIPS,       // Absolute pips movement
   SLOPE_MEASURE_PERCENT     // Percentage change relative to EMA value
};

// --- ADAPTIVE SETTINGS STRUCT ---
struct ST_AdaptiveSettings
{
   // Pair type detection
   EPairType PairType;

   // Spread limits by pair type (pips)
   double Spread_Major;
   double Spread_Minor;
   double Spread_Exotic;
   double Spread_Gold;
   double Spread_Crypto;
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
   double MaxTotalRisk;          // Max % of account at risk simultaneously (e.g., 4.0)
   int    MaxOpenTrades;         // Max number of concurrent trades (0 = no limit)
   bool   CountBEasZeroRisk;     // If true, trades at breakeven don't count toward risk
   double MaxSpread;
   bool   UseSpread;      // Enable spread filter (false = bypass spread gate)

   // Candle Body Overextension Indicator (voting)
   int    CandleBody_AvgPeriod;   // Bars used to compute average body size
   double CandleBody_MaxMult;     // Block if body > avg * multiplier
   int    CandleBody_CheckBars;   // Number of recent closed candles to check
   
   // MT5 Moving Average benchmark compatibility
   bool   UseMACompatSizer;
   double MA_MaximumRiskPct;
   double MA_DecreaseFactor;
   bool   RequirePriceCross;
   bool   MABenchmarkStrict;

   // RRM (Trend Pullback)
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
   EVoteMode VoteMode;        // ALL: every enabled indicator must agree (recommended); THRESHOLD: uses same all_pass logic as ALL mode

   // Per-indicator weights (1 = standard; only used in VOTE_MODE_THRESHOLD for weighted sum)
   // In VOTE_MODE_ALL, weights are ignored — all enabled indicators must simply agree.
   int Ind_EmaSig_Weight;
   int Ind_Adx_Weight;
   int Ind_Macd_Weight;
   int Ind_Rsi_Weight;
   int Ind_Cci_Weight;
   int Ind_Mfi_Weight;
   int Ind_Sto_Weight;
   int Ind_Bb_Weight;
   int Ind_Psar_Weight;
   int Ind_P123_Weight;
   int Ind_Ross_Weight;
   int Ind_Atr_Weight;
   int Ind_CandleBody_Weight;
   int Ind_CI_Weight;

   // Choppiness Index
   int    CI_Period;
   double CI_RangingThreshold;

   // Indicators (Periods)
   int    P_Ema1;
   int    P_Ema2;
   int    P_Ema3;
   int    P_Ema4;
   int    P_Adx;
   int    T_Adx;
   // ADX mode configuration (EADXMode)
   EADXMode ADX_Mode;                       // Which ADX validation mode to use
   double   ADX_Percentile;                 // Percentile for DYNAMIC_PERCENTILE mode (default 50.0)
   int      ADX_Lookback;                   // Bars to analyse for DYNAMIC_PERCENTILE mode (default 100)
   double   ADX_Threshold_Accumulation;     // PHASE_AWARE: lower threshold for unordered/emerging phases
   double   ADX_Threshold_Trending;         // PHASE_AWARE: higher threshold for strong trending phases
   double   ADX_Threshold_Distribution;     // PHASE_AWARE: medium threshold for transitional phases
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
   double T_MfiOB;
   double T_MfiOS;
   double ATR_VoteMinPips;    // ATR voting threshold: minimum pips
   double ATR_VoteMaxPips;    // ATR voting threshold: maximum pips

   // Modes
   EMacdVoteMode MacdVoteMode;           // MACD base vote mode
   bool          MacdRequireSlope;       // Filter: require acceleration
   bool          MacdRequireDivergence;  // Filter: require divergence
   bool          MacdRequireHook;        // Filter: require histogram flip
   int           MacdFreshBars;          // For _N modes: fresh signal validity
   double        MacdSlopeMin;           // Min slope threshold (0=disabled)
   ERsiMode   RsiMode;
   ECciMode   CciMode;
   EStochMode StoMode;
   EBbMode    BbMode;

   // Active Votes
   bool Ind_EmaSig_Enabled;
   bool Ind_Adx_Enabled;
   bool Ind_Macd_Enabled;
   bool Ind_Rsi_Enabled;
   bool Ind_Cci_Enabled;
   bool Ind_Mfi_Enabled;
   bool Ind_Sto_Enabled;
   bool Ind_Bb_Enabled;
   bool Ind_Psar_Enabled;
   bool Ind_P123_Enabled;
   bool Ind_Ross_Enabled;
   bool Ind_Atr_Enabled;
   bool Ind_CandleBody_Enabled;
   bool Ind_CI_Enabled;

   // MFI mode
   EMfiMode MfiMode;                // MFI vote mode (ZONE_FILTER or TREND_50)

   // RRM gate structures (SGateConfig defined above)
   SGateConfig Gate_Recovery;       // Recovery momentum gate config
   SGateConfig Gate_EmaDiv;         // EMA divergence gate config
   SGateConfig Gate_CandleDirection; // Candle direction gate config

   // Fixed lot sizing (0 = use risk-based sizing)
   double FixedLotSize;             // Fixed lot size (0 = risk-based; >0 = fixed)

   // SL - Initial SL Placement
   double           SL_PsarPipsCushion;
   double           SL_SwingPipsCushion;
   double           SL_FixedPips;

   // SL/TP Strategy Configuration
   ESLMode  SLMode;           // How to calculate SL distance
   ETPMode  TPMode;           // How to calculate TP distance
   double   FixedTPPips;      // Fixed TP distance in pips (TP_MODE_FIXED_PIPS)
   double   SLPercent;        // SL as % of entry price (SL_MODE_PERCENT, e.g. 0.5 = 0.5%)
   double   RRRatio;          // Risk:Reward ratio (TP_MODE_RR, e.g. 2.0 = 1:2)
   int      SwingLookback;    // Bars to look back for swing high/low (SL_MODE_SWING)

   // === Fractal Settings (NEW: Phase 2.2) ===
   int      FractalPeriod;    // Fractal indicator period (default: 5)
   int      TPFractalOffset;  // How many fractals ahead for TP (default: 1)

   // === PSAR SL/TP Settings (NEW: Phase 2.2) ===
   double   PSARStep;         // PSAR step for SL/TP calculations (default: 0.02)
   double   PSARMax;          // PSAR max for SL/TP calculations (default: 0.2)

   // Advanced Trailing Settings
   ETrailTrigger TrailTrigger;       // When to begin trailing (default: TRIGGER_IMMEDIATE)
   double   BEThresholdPips;         // Profit pips required before moving to breakeven
   double   TrailDistancePips;       // Fixed trail distance in pips (TRAIL_FIXED_PIPS / trigger threshold)
   double   TrailProfitPercent;      // Profit % threshold for TRIGGER_PROFIT_PERCENT
   double   TrailStepPips;           // Minimum pips movement before updating SL
   bool     TrailLockProfit;         // Lock in profit (never move SL backwards)

   // TS - Trailing SL / TP / BE
   ETrailingMode       TrailMode;
   EPsarTrailCushionMode PSAR_TrailCushionMode;
   double              PSAR_TrailPipsCushion;
   int                 PSAR_TrailDelay;         // PSAR trailing bar-shift delay (1-3)

   // RRM exit contract
   EExitProfile ExitProfile;           // Exit profile selector
   bool         TP_Enabled;            // Whether TP is active
   EBeMode      BE_Mode;               // BE mode for RRM

   // RRM parameters
   double RRM_BE_ProgressPct;          // RRM_BE trigger: % progress toward TP (0..100); used with BE_MODE_TP_PROGRESS_PCT
   double RRM_BE_RMultiple;            // RRM_BE trigger: R-multiple threshold (e.g. 1.0); used with BE_MODE_R_MULTIPLE
   double RRM_BE_BufferPips;           // RRM_BE buffer in pips
   int    RRM_TrailPsarShiftDelay;     // RRM_PSAR trail bar-shift delay (1..3)
   bool   RRM_FreezeTrailOnFlip;       // RRM_Freeze trailing stop on PSAR flip signal
   bool   RRM_TrailStartsAfterBE;      // RRM_Delay trail activation until BE is triggered

   // Gate system (reusable hard gates for any preset)
   bool        RequirePullback;        // Dynamic structure pullback gate (replaces pip-based Gate_Pullback)
   int         PullbackLookback;       // Bars to look back for pullback structure
   bool        RequireRecoveryMomentum;// Require recovery bar to close in trend direction
   bool        Gate_UseMultiLayer;     // Enable multi-layer cascading EMA pullback detection (RRM standard)
   int         Vote_EvalShift;         // Shift for vote evaluation
   bool        Vote_AllowPsarFlip;     // Allow PSAR flip signal in votes
   // PSAR flip validation parameters (when Vote_AllowPsarFlip=true)
   int         Vote_PsarFlipDelay;     // Flip timer mode:
                                       //   -1 = PERSISTENT: check dot position only (no flip tracking)
                                       //    0 = FLIP_BAR:   signal valid on flip bar only
                                       //  1-10 = COUNTDOWN: signal valid for N bars after flip

   // Reporting
   bool ExportCSV;

   // --- Global toggles allowed under presets ---
   bool         PrintEffectiveConfig;
   bool         DebugFlow;             // Master on/off switch (true = DEBUG_FULL verbosity)
   EDebugLevel  DebugLevel;            // Debug verbosity level

   // UI
   bool UI_ShowStatusPanel;
   bool UI_ShowCockpitPanel;
   bool UI_ManageChartIndicators;
   bool DrawEntryLines;
   bool DrawTradeLines;

   // Reporting
   bool ExportUseCommonFiles;

   // Adaptive settings (pair-aware spread, TF-aware ATR/SL/TP/trail)
   ST_AdaptiveSettings Adaptive;

   // RRM Drawdown Protection (§6)
   bool     RRM_EnableDrawdownProtection;
   int      RRM_MaxConsecutiveLosses;
   int      RRM_MaxTradesPerDay;
   double   RRM_MaxDailyDrawdownPct;


   // Phase detection settings
   bool     PhaseDetectionEnabled;         // Master switch for phase system
   bool     BlockUnorderedPhase;           // Block trades during UNORDERED phase
   bool     RequireMinPhaseConfirm;        // Require N consecutive bars in same phase
   int      MinPhaseConfirmBars;           // Minimum bars to confirm phase stability
   
   // Phase-specific trade permissions
   bool     Emerging_AllowWeakTrades;      // EMERGING phase: Allow EMA1/EMA2 entries
   bool     Emerging_AllowMediumTrades;    // EMERGING phase: Allow EMA2/EMA3 entries
   bool     Emerging_AllowStrongTrades;    // EMERGING phase: Allow EMA3/EMA4 entries
   
   bool     Trending_AllowWeakTrades;      // TRENDING phase: Allow EMA1/EMA2 entries
   bool     Trending_AllowMediumTrades;    // TRENDING phase: Allow EMA2/EMA3 entries
   bool     Trending_AllowStrongTrades;    // TRENDING phase: Allow EMA3/EMA4 entries

   // Layer detection settings
   bool     EnableLayerDetection;          // Master switch for multi-layer pullback detection
   double   LayerTouchTolerancePips;       // Pip tolerance for EMA touch detection
   double   LayerTouchTolerance;           // Percentage tolerance for EMA touch detection (e.g. 0.01 = 1%)
   bool     AllowLayer1_Entries;           // Allow Layer 1 (EMA1/EMA2 touch) entries
   bool     AllowLayer2_Entries;           // Allow Layer 2 (EMA2/EMA3 touch) entries
   bool     AllowLayer3_Entries;           // Allow Layer 3 (EMA3/EMA4 touch) entries

   // Diagnostics: statistics configuration
   bool Stats_TrackRejections;  // Track rejection counts per indicator
   bool Stats_TrackPasses;      // Track pass counts (positive stats)
   bool Stats_FullEvaluation;   // Evaluate ALL indicators per bar (no early exit)

   // ================================================================
   // SLOPE CALCULATION CONFIGURATION
   // ================================================================

   // Lookback period for slope calculation (1-5 bars)
   // 1 = Compare current bar to previous bar (responsive, noisy)
   // 2 = Compare current bar to 2 bars ago (smoother)
   // 3 = Compare current bar to 3 bars ago (very smooth)
   int    SlopeLookbackBars;

   // Minimum slope threshold (flat zone definition)
   bool   UseSlopeThreshold;        // Enable minimum slope filtering
   double SlopeThresholdPips;       // Min movement to consider as slope (pips; 0=adaptive)
   bool   SlopeThresholdAdaptive;   // Auto-adjust by TF and pair

   // Slope measurement method
   ESlopeMeasure SlopeMeasureMode;  // Pips or Percentage
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
//   🎯 ZONE 1   — Preset Selection             : choose preset & magic number
//   ✅ ZONE 2A  — Operator Gates & UI          : Policy A; always honored by all presets
//   ℹ️ ZONE 3A  — Pipeline Config (Steps 1–9) : reference defaults; presets override when active
//                 └─ ZONE 3A.9: EXIT MANAGEMENT (Stop Loss, Take Profit, Breakeven, Trailing)
//   🔧 ZONE 3C  — Pair-Specific Spread Limits     : auto-detect spread limits by symbol type
//
// Tags used in descriptions:
//   (Global; allowed under presets)                 - always honored (Zone 2A)
//   (Operator gate; preserved under presets)        - Policy A: user-controlled even under presets (Zone 2A)
//   (CUSTOM/TEST: editable; presets override)       - used by PRESET_CUSTOM & PRESET_TEST (Zone 3A / Zone 3A.9)


// ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓
// 🎯 ZONE 1 — PRESET SELECTION
// ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓

input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "  🎯 ZONE 1: PRESET SELECTION";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";

input ulong           Inp_MagicNum              = 12345;       // Magic number (trade identifier)
input EStrategyPreset InpPreset                 = PRESET_TEST;   // Strategy preset

input group "╔════════════════════════════════════════════════════════╗";
input group "║  📖 NAVIGATION GUIDE (Scroll to find your section)     ║";
input group "╠════════════════════════════════════════════════════════╣";
input group "║  ✅ ZONE 2A: OPERATOR GATES & UI (always editable)      ║";
input group "║  ⚠️  ZONE 3A: Pipeline Config (Steps 1–9)              ║";
input group "║     └─ ZONE 3A.9: EXIT MANAGEMENT ← START HERE         ║";
input group "╚════════════════════════════════════════════════════════╝";


// ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓
// ✅ ZONE 2A — OPERATOR GATES & UI  (Policy A — always editable)
// These inputs are ALWAYS respected by all presets.
// ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓

input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "  ✅ ZONE 2A: OPERATOR GATES & UI";
input group "    (Works in ALL presets)";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";

input group "╔════════════════════════════════════════════════════════╗";
input group "║  🚫 SPREAD LIMITS                                      ║";
input group "╚════════════════════════════════════════════════════════╝";
input bool           Inp_UseSpread              = false;    // Enable spread filter
input double         Inp_MaxSpreadPips          = 3.0;      // Max spread (pips; ignored if UseSpread=false)

input group "╔════════════════════════════════════════════════════════╗";
input group "║  ⏰ SESSION TIME FILTER                                 ║";
input group "╚════════════════════════════════════════════════════════╝";
input bool            Inp_UseTime               = false;          // Enable session/time filter
input int             Inp_StartHour             = 8;              // Session start hour (broker time)
input int             Inp_EndHour               = 20;             // Session end hour (broker time)

input group "╔════════════════════════════════════════════════════════╗";
input group "║  📰 NEWS FILTER                                        ║";
input group "╚════════════════════════════════════════════════════════╝";
input bool            Inp_UseNews               = false;          // Enable news filter (CSV calendar)
input string          Inp_NewsFile              = "calendar_statement.csv"; // News CSV filename
input int             Inp_NewsPre               = 60;             // Minutes before news to block entries
input int             Inp_NewsPost              = 60;             // Minutes after news to block entries

input group "╔════════════════════════════════════════════════════════╗";
input group "║  📈 HTF TREND FILTER                                   ║";
input group "╚════════════════════════════════════════════════════════╝";
input bool            Inp_UseHTF                = false;          // Enable HTF trend filter
input ENUM_TIMEFRAMES Inp_HtfPeriod             = PERIOD_H4;      // HTF timeframe
input int             Inp_HtfEmaPeriod          = 89;             // HTF EMA period

input group "╔════════════════════════════════════════════════════════╗";
input group "║  🎨 UI: STATUS PANEL                                   ║";
input group "╚════════════════════════════════════════════════════════╝";
input bool             Inp_UI_ShowStatusPanel      = false;       // Show status panel
input bool             Inp_UI_ManageChartIndicators = false;      // Auto-add/remove chart indicators
input ENUM_BASE_CORNER Inp_UI_PanelCorner          = CORNER_LEFT_UPPER; // Status panel corner
input int              Inp_UI_PanelX               = 30;          // Status panel X (px)
input int              Inp_UI_PanelY               = 30;          // Status panel Y (px)
input int              Inp_UI_PanelFontSize        = 10;          // Status panel font size
input int              Inp_UI_LineSpacingPx        = 28;          // Status panel line spacing (px)
input string           Inp_UI_PanelFont            = "Arial";     // Status panel font

input group "╔════════════════════════════════════════════════════════╗";
input group "║  🎨 UI: COCKPIT PANEL                                  ║";
input group "╚════════════════════════════════════════════════════════╝";
input bool             Inp_UI_ShowCockpitPanel     = true;        // Show cockpit panel
input ENUM_BASE_CORNER Inp_UI_CockpitCorner        = CORNER_LEFT_UPPER; // Cockpit panel corner
input int              Inp_UI_CockpitX             = 30;          // Cockpit panel X (px)
input int              Inp_UI_CockpitY             = 30;          // Cockpit panel Y (px)
input int              Inp_UI_CockpitFontSize      = 10;          // Cockpit panel font size
input int              Inp_UI_CockpitLineSpacingPx = 28;          // Cockpit panel line spacing (px)
input string           Inp_UI_CockpitFont          = "Arial";     // Cockpit panel font

input group "╔════════════════════════════════════════════════════════╗";
input group "║  🎨 UI: SIGNAL MARKERS & COLORS                        ║";
input group "╚════════════════════════════════════════════════════════╝";
input bool           Inp_DrawEntryLines            = true;        // Draw entry marker lines
input bool           Inp_DrawTradeLines            = true;        // Draw trade management lines
input bool           Inp_UI_UseCustomColors        = true;        // Use custom panel colors (else follow chart theme)
input color          Inp_UI_FontColor              = clrYellow;   // UI font color (when custom colors enabled)
input int            Inp_UI_PanelBgAlpha           = 110;         // Panel background alpha (0..255)
input EUIFrameMode   Inp_UI_FrameMode              = UI_FRAME_NONE;  // Panel frame mode (BG/NONE/TEXT_BOUNDS)
input int            Inp_UI_FramePadPx             = 6;           // Panel padding (px)

input group "╔════════════════════════════════════════════════════════╗";
input group "║  🔍 DIAGNOSTICS                                        ║";
input group "╚════════════════════════════════════════════════════════╝";
input bool           Inp_PrintEffectiveConfig      = true;           // Print effective config on init
input bool           Inp_DebugFlow                 = true;           // Print OnInit/OnTick/OnDeinit flow
input EDebugLevel    Inp_DebugLevel                = DEBUG_SILENT;  // Debug verbosity (SILENT/SUMMARY/INDICATORS/FULL)

input group "╔════════════════════════════════════════════════════════╗";
input group "║  🔍 DIAGNOSTICS: STATISTICS                            ║";
input group "╚════════════════════════════════════════════════════════╝";
input bool     Inp_Stats_TrackRejections = true;   // Track rejection counts
input bool     Inp_Stats_TrackPasses = true;       // Track pass counts (positive stats)
input bool     Inp_Stats_FullEvaluation = true;    // Evaluate ALL indicators per bar (no early exit)
input string   Inp_Stats_Info1 = "FullEvaluation=false: waterfall (stop at first fail)"; // Info
input string   Inp_Stats_Info2 = "FullEvaluation=true: evaluate all, identify true bottlenecks"; // Info

input group "╔════════════════════════════════════════════════════════╗";
input group "║  🔍 REPORTING                                          ║";
input group "╚════════════════════════════════════════════════════════╝";
input bool           Inp_ExportCSV                 = false;        // Export CSV reporting
input bool           Inp_ExportUseCommonFiles      = false;        // Use terminal Common Files folder for export

input group "╔════════════════════════════════════════════════════════╗";
input group "║  🔧 RRM MODE & DRAWDOWN PROTECTION (Policy A)          ║";
input group "╚════════════════════════════════════════════════════════╝";
input ERRMMode       Inp_RRM_Mode                       = RRM_AUTO_BY_TF; // RRM mode (auto/scalp/swing; PRESET_RRM only)
input bool           Inp_RRM_EnableDrawdownProtection   = false;          // Enable RRM drawdown protection (PRESET_RRM only)
input int            Inp_RRM_MaxConsecutiveLosses       = 5;              // Max consecutive losses before pause (PRESET_RRM only)
input int            Inp_RRM_MaxTradesPerDay            = 15;             // Max trades per day (PRESET_RRM only)
input double         Inp_RRM_MaxDailyDrawdownPct        = 3.0;            // Max daily drawdown % (PRESET_RRM only)

// ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓
// ℹ️ ZONE 3A — PIPELINE CONFIG  (reference defaults by pipeline step)
// Organized by the 9-step signal processing pipeline.
// When a preset is active these are overridden by the preset.
// In PRESET_CUSTOM & PRESET_TEST mode all inputs are fully respected.
// Steps 3 (Signal-Bias Match), 7 (Position Check) have no user inputs.
// Steps 4 (HTF) and 8 (Operator Gates) are in Zone 2A.
// Step 9 (Exit Management) is in ZONE 3A.9 below.
// ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓

input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "  ⚠️  ZONE 3A: PIPELINE CONFIG";
input group "      (Steps 1-6 + ZONE 3A.9 Exit Mgmt; presets override)";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";

// ── Step 1: Bias Calculation ─────────────────────────────────────────
input group "╔════════════════════════════════════════════════════════╗";
input group "║  🔧 STEP 1: Bias Calculation                           ║";
input group "╚════════════════════════════════════════════════════════╝";
input string         Inp_Step1_Info             = "Configure major trend detection"; // Info
input bool           Inp_BiasEnabled            = true;              // (CUSTOM; presets override) Enable market bias filter
input EBiasMode      Inp_BiasMode               = BIAS_AUTO_PHASE;   // (CUSTOM; presets override) Bias mode (AUTO/MANUAL)
input int            Inp_BiasFastID             = 2;                 // (CUSTOM; presets override) Bias Fast EMA (0=EMA1/5, 1=EMA2/13, 2=EMA3/34, 3=EMA4/89)
input int            Inp_BiasSlowID             = 3;                 // (CUSTOM; presets override) Bias Slow EMA (0=EMA1/5, 1=EMA2/13, 2=EMA3/34, 3=EMA4/89)
input EManualSide    Inp_ManualSide             = SIDE_BOTH;         // (CUSTOM; presets override) Manual direction (BOTH/LONG/SHORT)
input EMaMethod      Inp_MaType                 = METHOD_EMA;        // (CUSTOM; presets override) MA method (EMA/SMA)
input int            Inp_MaHorShift             = 1;                 // (CUSTOM; presets override) MA horizontal shift (bars)
input int            Inp_MaVerShift             = 1;                 // (CUSTOM; presets override) MA vertical shift (pips)
input int            InpEma1Period              = 5;                 // (CUSTOM; presets override) EMA1 period
input int            InpEma2Period              = 13;                // (CUSTOM; presets override) EMA2 period
input int            InpEma3Period              = 34;                // (CUSTOM; presets override) EMA3 period (RRM bias fast)
input int            InpEma4Period              = 89;                // (CUSTOM; presets override) EMA4 period (RRM bias slow)

// ── Step 2: Entry Signal ─────────────────────────────────────────────
input group "╔════════════════════════════════════════════════════════╗";
input group "║  🔧 STEP 2: Entry Signal                               ║";
input group "╚════════════════════════════════════════════════════════╝";
input string         Inp_Step2_Info             = "Configure entry timing strategy"; // Info
input EAutoStrategy  Inp_AutoStrat              = STRAT_POSITION_SLOPE;  // (CUSTOM; presets override) Entry strategy (price cross / pair cross)
input double         Inp_LayerTolerance         = 0.01;             // (CUSTOM; presets override) Layer touch tolerance (%, e.g. 0.01=1%; used by STRAT_LAYER_DETECTION)
input bool           Inp_RRM_EnableInCustom     = false;          // (CUSTOM only) Enable RRM logic while using PRESET_CUSTOM
input bool           Inp_CloseOnReverse         = false;          // (CUSTOM; presets may override) Close on reverse signal

// ── Step 5: Structure Gate (Multi-layer pullback) ─────────────────────
input group "╔════════════════════════════════════════════════════════╗";
input group "║  🔧 STEP 5: Structure Gate (Pullback)                  ║";
input group "╚════════════════════════════════════════════════════════╝";
input string         Inp_Step5_Info             = "Configure pullback-recovery detection"; // Info
input bool           Inp_Gate_UseMultiLayer     = false;      // (CUSTOM; presets override) Enable multi-layer cascading EMA pullback detection
input bool           Inp_Gate_RequirePullback   = false;      // (CUSTOM; presets override) Enable pullback gate
input int            Inp_Gate_PullbackLookback  = 15;         // (CUSTOM; presets override) Pullback search bars
input bool           Inp_Gate_RequireRecoveryMomentum = false;     // (CUSTOM; presets override) Require bullish/bearish candle (recovery momentum)
input int            Inp_RRM_Lookback           = 5;              // (CUSTOM; presets override) Pullback lookback bars
input double         Inp_RRM_MinDivPips         = 0.5;            // (CUSTOM; presets override) Min EMA divergence (pips)

// ── Step 6: Indicator Voting ──────────────────────────────────────────
input group "╔════════════════════════════════════════════════════════╗";
input group "║  🔧 STEP 6: Voting Configuration                       ║";
input group "╚════════════════════════════════════════════════════════╝";
input string         Inp_Step6_Info             = "Configure multi-indicator consensus (ALL enabled must pass)"; // Info
input bool           Inp_VoteMode_All           = true;                 // (CUSTOM; presets override) Vote mode: TRUE=all must agree (recommended), FALSE=threshold

input group "╔════════════════════════════════════════════════════════╗";
input group "║  📊 Indicator: EmaSig                                  ║";
input group "╚════════════════════════════════════════════════════════╝";
input bool           Inp_Ind_EmaSig_Enabled     = true;                // [EmaSig] Enable EMA signal vote
input int            Inp_Ind_EmaSig_Weight      = 1;                   // [EmaSig] Vote weight
input string         Inp_Ind_EmaSig_Info        = "Price position vs EMA1"; // [EmaSig] Description

input group "╔════════════════════════════════════════════════════════╗";
input group "║  📊 Indicator: ADX                                     ║";
input group "╚════════════════════════════════════════════════════════╝";
input bool           Inp_Ind_Adx_Enabled        = false;               // [ADX] Enable ADX vote
input int            Inp_Ind_Adx_Weight         = 1;                   // [ADX] Vote weight
input string         Inp_Ind_Adx_Info           = "Trend strength filter"; // [ADX] Description
input int            Inp_Ind_Adx_Period         = 14;                  // [ADX] Period
input int            Inp_Ind_Adx_Threshold      = 20;                  // [ADX] Threshold (Static mode)
input EADXMode       Inp_Ind_Adx_Mode           = ADX_MODE_STATIC;    // [ADX] Mode (Static/Dynamic/PhaseAware)
input double         Inp_Ind_Adx_Percentile     = 50.0;               // [ADX] Percentile for Dynamic mode
input int            Inp_Ind_Adx_Lookback       = 100;                // [ADX] Lookback bars for Dynamic mode
input double         Inp_Ind_Adx_Thr_Accum      = 12.0;              // [ADX] Phase-Aware: Accumulation/Unordered threshold
input double         Inp_Ind_Adx_Thr_Trending   = 25.0;              // [ADX] Phase-Aware: Trending threshold
input double         Inp_Ind_Adx_Thr_Distrib    = 18.0;              // [ADX] Phase-Aware: Distribution/Emerging threshold

input group "╔════════════════════════════════════════════════════════╗";
input group "║  📊 Indicator: MACD                                    ║";
input group "╚════════════════════════════════════════════════════════╝";
input bool           Inp_Ind_Macd_Enabled       = false;               // [MACD] Enable MACD vote
input int            Inp_Ind_Macd_Weight        = 1;                   // [MACD] Vote weight

input group "╔════════════════════════════════════════════════════════╗";
input group "║  MACD: BASE MODE (Choose ONE)                          ║";
input group "╚════════════════════════════════════════════════════════╝";
input EMacdVoteMode  Inp_MacdVoteMode           = MACD_ZERO_AND_CROSS; // MACD base mode

input group "╔════════════════════════════════════════════════════════╗";
input group "║  MACD: ADVANCED FILTERS (Optional Add-Ons)             ║";
input group "╚════════════════════════════════════════════════════════╝";
input string         Inp_MacdFilterInfo         = "Enable filters below to add requirements to base mode";  // [Info]
input bool           Inp_MacdRequireSlope       = false;  // ✓ Add: Require MACD rising/falling (momentum acceleration)
input bool           Inp_MacdRequireDivergence  = false;  // ✓ Add: Require price/MACD divergence (reversal signal)
input bool           Inp_MacdRequireHook        = false;  // ✓ Add: Require histogram flip (early reversal)

input group "╔════════════════════════════════════════════════════════╗";
input group "║  MACD: PARAMETERS                                      ║";
input group "╚════════════════════════════════════════════════════════╝";
input int            Inp_P_MacdFast             = 8;      // MACD Fast EMA period
input int            Inp_P_MacdSlow             = 13;     // MACD Slow EMA period
input int            Inp_P_MacdSig              = 8;      // MACD Signal SMA period
input int            Inp_MacdFreshBars          = 3;      // Fresh signal validity (for _N modes, 0=disabled)
input double         Inp_MacdSlopeMin           = 0.00001; // Min slope change per bar (0=disabled, smaller = more permissive)

input group "╔════════════════════════════════════════════════════════╗";
input group "║  MACD: HELP                                            ║";
input group "╚════════════════════════════════════════════════════════╝";
input string         Inp_MacdHelp1              = "BASE MODE: Select primary logic from dropdown above";            // Line 1
input string         Inp_MacdHelp2              = "FILTERS: Check boxes to add extra requirements";                 // Line 2
input string         Inp_MacdHelp3              = "Example: ZERO_LINE + Slope = Main>0 AND rising";                // Line 3
input string         Inp_MacdHelp4              = "Example: CROSSOVER_N + Divergence = Fresh cross + bullish div"; // Line 4

input group "╔════════════════════════════════════════════════════════╗";
input group "║  📊 Indicator: RSI                                     ║";
input group "╚════════════════════════════════════════════════════════╝";
input bool           Inp_Ind_Rsi_Enabled        = false;               // [RSI] Enable RSI vote
input int            Inp_Ind_Rsi_Weight         = 1;                   // [RSI] Vote weight
input string         Inp_Ind_Rsi_Info           = "Relative Strength Index"; // [RSI] Description
input ERsiMode       Inp_Ind_Rsi_Mode           = RSI_FILTER_EXTREME;  // [RSI] Mode
input int            Inp_Ind_Rsi_Period         = 14;                  // [RSI] Period
input double         Inp_Ind_Rsi_OB             = 70.0;                // [RSI] Overbought level
input double         Inp_Ind_Rsi_OS             = 30.0;                // [RSI] Oversold level

input group "╔════════════════════════════════════════════════════════╗";
input group "║  📊 Indicator: CCI                                     ║";
input group "╚════════════════════════════════════════════════════════╝";
input bool           Inp_Ind_Cci_Enabled        = false;                // [CCI] Enable CCI vote
input int            Inp_Ind_Cci_Weight         = 1;                   // [CCI] Vote weight
input string         Inp_Ind_Cci_Info           = "Commodity Channel Index"; // [CCI] Description
input ECciMode       Inp_Ind_Cci_Mode           = CCI_TREND_ZERO;      // [CCI] Mode
input int            Inp_Ind_Cci_Period         = 14;                  // [CCI] Period

input group "╔════════════════════════════════════════════════════════╗";
input group "║  📊 Indicator: MFI                                     ║";
input group "╚════════════════════════════════════════════════════════╝";
input bool           Inp_Ind_Mfi_Enabled        = false;               // [MFI] Enable MFI vote
input int            Inp_Ind_Mfi_Weight         = 1;                   // [MFI] Vote weight
input string         Inp_Ind_Mfi_Info           = "Money Flow Index";  // [MFI] Description
input int            Inp_Ind_Mfi_Period         = 14;                  // [MFI] Period
input double         Inp_Ind_Mfi_Level          = 50.0;                // [MFI] Threshold/level
input EMfiMode       Inp_Ind_Mfi_Mode           = MFI_ZONE_FILTER;     // [MFI] Mode (ZONE_FILTER or TREND_50)

input group "╔════════════════════════════════════════════════════════╗";
input group "║  📊 Indicator: Stochastic                              ║";
input group "╚════════════════════════════════════════════════════════╝";
input bool           Inp_Ind_Sto_Enabled        = false;               // [Stoch] Enable Stochastic vote
input int            Inp_Ind_Sto_Weight         = 1;                   // [Stoch] Vote weight
input string         Inp_Ind_Sto_Info           = "Stochastic oscillator"; // [Stoch] Description
input EStochMode     Inp_Ind_Sto_Mode           = STO_ZONE_FILTER;     // [Stoch] Mode
input int            Inp_Ind_Sto_K              = 5;                   // [Stoch] %K period
input int            Inp_Ind_Sto_D              = 3;                   // [Stoch] %D period
input int            Inp_Ind_Sto_Slow           = 3;                   // [Stoch] Slowing

input group "╔════════════════════════════════════════════════════════╗";
input group "║  📊 Indicator: Bollinger Bands                         ║";
input group "╚════════════════════════════════════════════════════════╝";
input bool           Inp_Ind_Bb_Enabled         = false;               // [BB] Enable Bollinger Bands vote
input int            Inp_Ind_Bb_Weight          = 1;                   // [BB] Vote weight
input string         Inp_Ind_Bb_Info            = "Bollinger Bands channel"; // [BB] Description
input EBbMode        Inp_Ind_Bb_Mode            = BB_TREND_FOLLOW;     // [BB] Mode
input int            Inp_Ind_Bb_Period          = 20;                  // [BB] Period
input double         Inp_Ind_Bb_Dev             = 2.0;                 // [BB] Deviation

input group "╔════════════════════════════════════════════════════════╗";
input group "║  📊 Indicator: PSAR                                    ║";
input group "╚════════════════════════════════════════════════════════╝";
input bool           Inp_Ind_Psar_Enabled       = true;                // [PSAR] Enable PSAR vote
input int            Inp_Ind_Psar_Weight        = 1;                   // [PSAR] Vote weight
input string         Inp_Ind_Psar_Info          = "Parabolic SAR position"; // [PSAR] Description
input double         Inp_Ind_Psar_Step          = 0.05;                // [PSAR] Step
input double         Inp_Ind_Psar_Max           = 0.5;                 // [PSAR] Maximum
input int            Inp_Vote_PsarFlipDelay     = 10;                  // [PSAR] Flip timer: -1=persistent, 0=flip bar, 1-10=countdown

input group "╔════════════════════════════════════════════════════════╗";
input group "║  📊 Indicator: ATR (Volatility)                        ║";
input group "╚════════════════════════════════════════════════════════╝";
input bool           Inp_Ind_Atr_Enabled       = false;               // [ATR] Enable ATR vote
input int            Inp_Ind_Atr_Weight        = 1;                   // [ATR] Vote weight
input string         Inp_Ind_Atr_Info          = "Non-directional: validates volatility range (voting)"; // [ATR] Description
input int            Inp_Ind_Atr_Period        = 14;                  // [ATR] Period
input double         Inp_Ind_Atr_VoteMinPips   = 5.0;                 // [ATR] Voting min pips
input double         Inp_Ind_Atr_VoteMaxPips   = 50.0;                // [ATR] Voting max pips

input group "╔════════════════════════════════════════════════════════╗";
input group "║  📐 Slope Calculation Settings                         ║";
input group "╚════════════════════════════════════════════════════════╝";
input int            Inp_SlopeLookbackBars       = 1;                      // [Slope] Bars lookback (1=single bar, 2-3=smoother)
input bool           Inp_UseSlopeThreshold       = true;                   // [Slope] Enable minimum threshold
input double         Inp_SlopeThresholdPips      = 0.0;                    // [Slope] Min movement (pips; 0=adaptive)
input bool           Inp_SlopeThresholdAdaptive  = true;                   // [Slope] Auto-adjust by TF/pair
input ESlopeMeasure  Inp_SlopeMeasureMode        = SLOPE_MEASURE_PIPS;     // [Slope] Measure: pips or %
input string         Inp_SlopeInfo               = "Adaptive: M5=0.5p, H1=1.5p, H4=2.5p (scaled by pair)"; // [Slope] Info

input group "╔════════════════════════════════════════════════════════╗";
input group "║  📊 Indicator: Candle Body Overextension               ║";
input group "╚════════════════════════════════════════════════════════╝";
input bool           Inp_Ind_CandleBody_Enabled   = false;          // [CandleBody] Enable voting indicator
input int            Inp_Ind_CandleBody_Weight    = 1;              // [CandleBody] Vote weight
input string         Inp_Ind_CandleBody_Info      = "Votes against overextended candles (news/spikes)"; // [CandleBody] Description
input int            Inp_Ind_CandleBody_AvgPeriod = 10;             // [CandleBody] Average body period
input double         Inp_Ind_CandleBody_MaxMult   = 3.0;            // [CandleBody] Max body multiplier
input int            Inp_Ind_CandleBody_CheckBars = 1;              // [CandleBody] Bars to check

input group "╔════════════════════════════════════════════════════════╗";
input group "║  📊 Indicator: Choppiness Index (CI)                   ║";
input group "╚════════════════════════════════════════════════════════╝";
input bool   Inp_Ind_CI_Enabled        = false;           // [CI] Enable ranging market filter
input int    Inp_Ind_CI_Weight         = 1;               // [CI] Vote weight
input string Inp_Ind_CI_Info           = "Blocks trades when market is ranging/choppy (CI > threshold)"; // [CI] Description
input int    Inp_CI_Period             = 14;              // [CI] Calculation period
input double Inp_CI_RangingThreshold   = 61.8;            // [CI] Ranging threshold (>= this value = reject)

input group "╔════════════════════════════════════════════════════════╗";
input group "║  📊 Indicator: Pattern 1-2-3                           ║";
input group "╚════════════════════════════════════════════════════════╝";
input bool           Inp_Ind_P123_Enabled       = false;               // [P123] Enable 1-2-3 pattern vote
input int            Inp_Ind_P123_Weight        = 1;                   // [P123] Vote weight
input string         Inp_Ind_P123_Info          = "1-2-3 fractal breakout pattern"; // [P123] Description

input group "╔════════════════════════════════════════════════════════╗";
input group "║  📊 Indicator: Ross Hook                               ║";
input group "╚════════════════════════════════════════════════════════╝";
input bool           Inp_Ind_Ross_Enabled       = false;               // [Ross] Enable Ross hook vote
input int            Inp_Ind_Ross_Weight        = 1;                   // [Ross] Vote weight
input string         Inp_Ind_Ross_Info          = "Ross hook trend momentum"; // [Ross] Description

input group "╔════════════════════════════════════════════════════════╗";
input group "║  📊 TEMPLATE: Add Custom Indicator                     ║";
input group "╚════════════════════════════════════════════════════════╝";
input string         Inp_Ind_Template_Info      = "Copy a section above to add custom indicators"; // Instructions

// ── Step 9: Risk & Execution ──────────────────────────────────────────

// ════════════════════════════════════════════════════════════════════
// ℹ️ ZONE 3A.9 — EXIT MANAGEMENT  (Stop Loss, Take Profit, Breakeven, Trailing)
// Configure how trades are managed after entry.
// When a preset is active these may be overridden.
// In PRESET_CUSTOM mode all inputs below are fully respected.
// ════════════════════════════════════════════════════════════════════
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "  ℹ️ ZONE 3A.9: EXIT MANAGEMENT";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";

// ── Exit Profile (Contract Selector) ─────────────────────────────────
input group "═══ 🎯 Exit Profile (Strategy Contract) ═══";
input string         Inp_Exit_Zone_Info1        = "Active for: PRESET_TEST & PRESET_CUSTOM (direct input control)"; // [Zone 3A.9]
input string         Inp_Exit_Zone_Info2        = "Other presets override exits with strategy-optimized values";               // [Zone 3A.9]
input EExitProfile   Inp_ExitProfile            = EXIT_PROFILE_NONE; // Exit profile selector
input string         Inp_ExitProfile_Info       = "RRM: Swing-based SL, PSAR trail, no ATR multipliers"; // [Info]

// ── Stop Loss Configuration ──────────────────────────────────────────
input group "═══ 🛑 Stop Loss Configuration ═══";
input ESLMode        Inp_SLMode                 = SL_MODE_PERCENT; // SL calculation method
input string         Inp_SL_Help1               = "FIXED_PIPS: Simple pip distance  |  SWING: Recent structure high/low"; // [Info]
input string         Inp_SL_Help2               = "PSAR_DOT: PSAR level  |  PERCENT: % of price  |  FRACTAL: Bill Williams"; // [Info]
input double         Inp_SL_FixedPips           = 20.0;               // SL distance (pips; for SL_MODE_FIXED_PIPS)
input string         Inp_SL_TFCushion_Note      = "PSAR/Swing cushions auto-set by timeframe (M15=5, H1=10, H4=20 pips)"; // [Info]
input int            Inp_SwingLookback          = 20;                 // Swing lookback (bars; for SL_MODE_SWING)
input double         Inp_SLPercent              = 0.5;                // SL as % of entry (for SL_MODE_PERCENT; e.g. 0.5 = 0.5%)

input group "--- PSAR & Fractal SL/TP Settings ---";
input string         Inp_SL_FractalPsar_Note    = "Settings used by SL_FRACTAL and SL_PSAR_DOT modes"; // [Info]
input int            Inp_FractalPeriod          = 5;                   // Fractal period for SL/TP (SL_FRACTAL / TP_FRACTAL)
input int            Inp_TPFractalOffset        = 1;                   // Fractal offset for TP (1=nearest fractal)
input double         Inp_PSARStep               = 0.02;                // PSAR step for SL/TP (SL_PSAR_DOT / TP_PSAR_FLIP)
input double         Inp_PSARMax                = 0.2;                 // PSAR max for SL/TP

// ── Take Profit Configuration ────────────────────────────────────────
input group "═══ 🎯 Take Profit Configuration ═══";
input bool           Inp_TP_Enabled             = true;                // Enable take profit
input ETPMode        Inp_TPMode                 = TP_MODE_RR;         // TP calculation method
input double         Inp_RRRatio                = 2.0;                // Risk:Reward ratio (TP_MODE_RR only)
input double         Inp_FixedTPPips            = 40.0;               // Fixed TP distance (pips; TP_MODE_FIXED_PIPS only)

input group "--- SL Configuration Examples ---";
input string         Inp_Ex1_Header             = "Example 1 - Simple Fixed SL: Inp_SLMode=SL_MODE_FIXED_PIPS, Inp_SL_FixedPips=20"; // [Info]
input string         Inp_Ex2_Header             = "Example 2 - Swing Structure: Inp_SLMode=SL_MODE_SWING, Inp_SwingLookback=20 (cushion auto-set by TF)"; // [Info]
input string         Inp_Ex3_Header             = "Example 3 - Fractal SL:     Inp_SLMode=SL_MODE_FRACTAL, Inp_FractalPeriod=5, Inp_TPFractalOffset=1"; // [Info]

// ── Breakeven Configuration ──────────────────────────────────────────
input group "═══ ⚖️ Breakeven Configuration ═══";
input string         Inp_RRM_Info1              = "RRM uses % of TP distance for BE — not absolute pips"; // [RRM Info]
input string         Inp_RRM_Info2              = "Only active when ExitProfile = EXIT_PROFILE_RRM"; // [RRM Info]
input string         Inp_RRM_Info3              = "Example: SL=10 pips, TP=30 pips (3:1 RR), BE@33% → triggers at +10 pips profit"; // [RRM Info]
input EBeMode        Inp_BE_Mode                = BE_MODE_TP_PROGRESS_PCT;  // RRM BE mode: OFF / TP_PROGRESS_PCT / R_MULTIPLE

input group "--- RRM Breakeven (% Progress) ---";
input double         Inp_RRM_BE_ProgressPct     = 10.0; // BE at % to TP (33 = 33%; BE_MODE_TP_PROGRESS_PCT)
input double         Inp_RRM_BE_RMultiple       = 1.0;  // BE at R-multiple (BE_MODE_R_MULTIPLE)
input string         Inp_RRM_BE_Buffer_Note     = "BE buffer auto-set by timeframe (M15=5, H1=10, H4=20 pips)"; // [Info]
input string         Inp_RRM_BE_Example         = "Example: SL=10, TP=30 (3:1), BE@33% → triggers at +10 pips; SL locks at entry + TF-cushion"; // [Info]


// ── Trailing Stop Configuration ──────────────────────────────────────
input group "═══ 📈 Trailing Stop Configuration ═══";
input ETrailingMode  Inp_TrailMode              = TRAIL_PSAR;        // Trailing method
input ETrailTrigger  Inp_TrailTrigger           = TRIGGER_IMMEDIATE; // When to start trailing
input double         Inp_TrailDistancePips      = 5.0;              // Fixed trail distance / profit trigger (pips)
input double         Inp_BEThresholdPips        = 5.0;              // Pips profit to trigger breakeven (TRIGGER_BREAKEVEN)
input double         Inp_TrailProfitPercent     = 10.0;               // Profit % to start trailing (TRIGGER_PROFIT_PERCENT)
input double         Inp_TrailStepPips          = 5.0;               // Minimum pips to move SL each step
input bool           Inp_TrailLockProfit        = true;              // Never move SL backwards (lock in profit)

input group "--- PSAR Trailing (PSAR-specific) ---";
input EPsarTrailCushionMode Inp_PSAR_TrailCushionMode = PSAR_CUSHION_PIPS; // PSAR trail cushion mode
input string         Inp_PSAR_TrailCushion_Note = "PSAR trail cushion auto-set by timeframe (M15=3, H1=7, H4=10 pips)"; // [Info]
input int            Inp_PSAR_TrailDelay        = 1;                 // PSAR trailing delay (1=tight, 3=loose)
input bool           Inp_RRM_TrailStartsAfterBE = false;             // Start trailing only after BE is reached
input int            Inp_RRM_TrailPsarShiftDelay = 1;                // PSAR shift delay (1=tight, 3=loose)
input bool           Inp_RRM_FreezeTrailOnFlip  = true;              // Freeze trail on PSAR flip
input string         Inp_RRM_Trail_Info         = "RRM trailing: PSAR-based with bar shift delay for flip stability"; // [Info]

// ── Risk Management ──────────────────────────────────────────────────
input group "═══ 💰 Risk Management ═══";
input double         Inp_RiskPercent            = 2.0;    // Risk per trade (%)
input string         Inp_Step9_Ref1             = "Risk per trade applies to all presets unless overridden by Admin Override"; // [Reference]
input string         Inp_Step9_Ref2             = "To adjust exits under a strict preset: use PRESET_CUSTOM mode"; // [Reference]

input group "--- MT5 Moving Average Benchmark ---";
input double         Inp_MA_MaximumRiskPct      = 0.02;         // (PRESET_MA only) Max risk (%) for MA benchmark sizer
input double         Inp_MA_DecreaseFactor      = 3.0;          // (PRESET_MA only) Lot decrease factor
input int            Inp_MA_Period              = 12;           // (PRESET_MA only) MA period
input int            Inp_MA_Shift               = 6;            // (PRESET_MA only) MA shift

input group "══════════ ℹ️ END: ZONE 3A.9 EXIT MANAGEMENT ══════════";

// ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓
// 🔧 ZONE 3C — PAIR-SPECIFIC SPREAD LIMITS
// Auto-detect spread limits based on symbol type.
// Example: EURUSD (major) = 2 pips, XAUUSD (gold) = 5 pips, BTCUSD (crypto) = 50 pips
// ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓

input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "  🔧 ZONE 3C: PAIR-SPECIFIC SPREAD LIMITS";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";

input group "╔════════════════════════════════════════════════════════╗";
input group "║  🔧 Pair Type Detection                                ║";
input group "╚════════════════════════════════════════════════════════╝";
input EPairType      Inp_Adaptive_PairType      = PAIR_TYPE_AUTO; // Pair type (AUTO detects from symbol name)
input string         Inp_Adaptive_PairInfo      = "AUTO: EURUSD/GBPUSD/USDJPY=MAJOR; XAUUSD/GOLD=GOLD; BTC/ETH=CRYPTO; TRY/ZAR/MXN=EXOTIC; others=MINOR"; // Pair detection reference

input group "╔════════════════════════════════════════════════════════╗";
input group "║  🔧 Max Spread by Pair Type (pips)                     ║";
input group "╚════════════════════════════════════════════════════════╝";
input double         Inp_Adaptive_Spread_Major  = 2.0;           // Max spread for major pairs (pips)
input double         Inp_Adaptive_Spread_Minor  = 4.0;           // Max spread for minor pairs (pips)
input double         Inp_Adaptive_Spread_Exotic = 10.0;          // Max spread for exotic pairs (pips)
input double         Inp_Adaptive_Spread_Gold   = 5.0;           // Max spread for gold/XAU (pips)
input double         Inp_Adaptive_Spread_Crypto = 50.0;          // Max spread for crypto (pips)

input string         Inp_Adaptive_Note1 = "📝 Note: SL/TP cushions auto-adjust by timeframe (no input needed)"; // [Info]
input string         Inp_Adaptive_Note2 = "📝 M15=5 pips, H1=10 pips, H4=20 pips (see GetTFBasedCushion)"; // [Info]

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
//| Model A: Config always maps inputs -> struct; later stages decide |
//| what to override/ignore (presets) and what to print.             |
//+------------------------------------------------------------------+
void InitializeConfig()
{
   ZeroMemory(Settings);

   // === Global inputs allowed under presets (still mapped normally) ===
   Settings.PrintEffectiveConfig     = Inp_PrintEffectiveConfig;
   // Map debug level first; DebugFlow=false forces SILENT mode
   Settings.DebugLevel               = Inp_DebugFlow ? Inp_DebugLevel : DEBUG_SILENT;
   // DebugFlow=true only when running at full verbosity (maintains backward compat for all existing checks)
   Settings.DebugFlow                = (Settings.DebugLevel >= DEBUG_FULL);

   Settings.Stats_TrackRejections    = Inp_Stats_TrackRejections;
   Settings.Stats_TrackPasses        = Inp_Stats_TrackPasses;
   Settings.Stats_FullEvaluation     = Inp_Stats_FullEvaluation;

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
   Settings.FixedLotSize         = 0.0;  // 0 = risk-based sizing (default)
   Settings.MaxSpread            = Inp_MaxSpreadPips;
   Settings.UseSpread            = Inp_UseSpread;

   // Defaults for gating/vote semantics
   Settings.ATR_VoteMinPips      = Inp_Ind_Atr_VoteMinPips;
   Settings.ATR_VoteMaxPips      = Inp_Ind_Atr_VoteMaxPips;

   // Candle body overextension indicator
   Settings.CandleBody_AvgPeriod   = MathMax(1, Inp_Ind_CandleBody_AvgPeriod);
   Settings.CandleBody_MaxMult     = Inp_Ind_CandleBody_MaxMult;
   Settings.CandleBody_CheckBars   = MathMax(1, Inp_Ind_CandleBody_CheckBars);

   // MA benchmark inputs (strategy fields; preset may use/override semantics later)
   Settings.UseMACompatSizer     = false;
   Settings.MA_MaximumRiskPct    = Inp_MA_MaximumRiskPct;
   Settings.MA_DecreaseFactor    = Inp_MA_DecreaseFactor;
   Settings.RequirePriceCross    = false;
   Settings.MABenchmarkStrict    = false;

   // RRM trigger gates (inputs always mapped; preset may ignore/override later)
   Settings.RRM_Lookback               = Inp_RRM_Lookback;
   Settings.RRM_MinDivPips             = Inp_RRM_MinDivPips;
   Settings.RequirePullback            = Inp_Gate_RequirePullback;
   Settings.PullbackLookback           = Inp_Gate_PullbackLookback;
   Settings.RequireRecoveryMomentum    = Inp_Gate_RequireRecoveryMomentum;
   Settings.Gate_UseMultiLayer         = Inp_Gate_UseMultiLayer;

   // RRM gate structures (default: all gates disabled)
   Settings.Gate_Recovery.mode         = GATE_SCALE_OFF;
   Settings.Gate_Recovery.value        = 0.0;
   Settings.Gate_EmaDiv.mode           = GATE_SCALE_OFF;
   Settings.Gate_EmaDiv.value          = 0.0;
   Settings.Gate_CandleDirection.mode  = GATE_SCALE_OFF;
   Settings.Gate_CandleDirection.value = 0.0;

   // Bias
   Settings.BiasEnabled          = Inp_BiasEnabled;
   Settings.BiasMode             = Inp_BiasMode;
   Settings.ManSide              = Inp_ManualSide;

   // Strategy: direct bias EMA IDs (0=EMA1, 1=EMA2, 2=EMA3, 3=EMA4) + entry strategy
   // Clamp IDs to valid range 0..3 to prevent runtime errors from invalid user input
   Settings.BiasFastID           = MathMax(0, MathMin(3, Inp_BiasFastID));
   Settings.BiasSlowID           = MathMax(0, MathMin(3, Inp_BiasSlowID));
   Settings.AutoStrat            = Inp_AutoStrat;
   Settings.LayerTouchTolerance  = Inp_LayerTolerance;

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
   Settings.VoteMode             = (Inp_VoteMode_All ? VOTE_MODE_ALL : VOTE_MODE_THRESHOLD);

   // Indicator periods / thresholds
   Settings.P_Ema1               = InpEma1Period;
   Settings.P_Ema2               = InpEma2Period;
   Settings.P_Ema3               = InpEma3Period;
   Settings.P_Ema4               = InpEma4Period;
   Settings.P_Adx                = Inp_Ind_Adx_Period;
   Settings.T_Adx                = Inp_Ind_Adx_Threshold;
   Settings.ADX_Mode                  = Inp_Ind_Adx_Mode;
   Settings.ADX_Percentile            = Inp_Ind_Adx_Percentile;
   Settings.ADX_Lookback              = Inp_Ind_Adx_Lookback;
   Settings.ADX_Threshold_Accumulation= Inp_Ind_Adx_Thr_Accum;
   Settings.ADX_Threshold_Trending    = Inp_Ind_Adx_Thr_Trending;
   Settings.ADX_Threshold_Distribution= Inp_Ind_Adx_Thr_Distrib;
   Settings.P_MacdFast           = Inp_P_MacdFast;
   Settings.P_MacdSlow           = Inp_P_MacdSlow;
   Settings.P_MacdSig            = Inp_P_MacdSig;
   Settings.P_Rsi                = Inp_Ind_Rsi_Period;
   Settings.T_RsiOB              = Inp_Ind_Rsi_OB;
   Settings.T_RsiOS              = Inp_Ind_Rsi_OS;
   Settings.P_Cci                = Inp_Ind_Cci_Period;
   Settings.P_Mfi                = Inp_Ind_Mfi_Period;
   Settings.T_Mfi                = Inp_Ind_Mfi_Level;
   Settings.T_MfiOB              = Inp_Ind_Mfi_Level;
   Settings.T_MfiOS              = Inp_Ind_Mfi_Level;
   Settings.P_StoK               = Inp_Ind_Sto_K;
   Settings.P_StoD               = Inp_Ind_Sto_D;
   Settings.P_StoSlow            = Inp_Ind_Sto_Slow;
   Settings.T_StoOB              = 80.0;
   Settings.T_StoOS              = 20.0;
   Settings.P_Bb                 = Inp_Ind_Bb_Period;
   Settings.P_BbDev              = Inp_Ind_Bb_Dev;
   Settings.P_PsarStep           = Inp_Ind_Psar_Step;
   Settings.P_PsarMax            = Inp_Ind_Psar_Max;
   Settings.P_Atr                = Inp_Ind_Atr_Period;

   // Modes
   Settings.MacdVoteMode         = Inp_MacdVoteMode;
   Settings.MacdRequireSlope     = Inp_MacdRequireSlope;
   Settings.MacdRequireDivergence= Inp_MacdRequireDivergence;
   Settings.MacdRequireHook      = Inp_MacdRequireHook;
   Settings.MacdFreshBars        = Inp_MacdFreshBars;
   Settings.MacdSlopeMin         = Inp_MacdSlopeMin;
   Settings.RsiMode              = Inp_Ind_Rsi_Mode;
   Settings.CciMode              = Inp_Ind_Cci_Mode;
   Settings.StoMode              = Inp_Ind_Sto_Mode;
   Settings.BbMode               = Inp_Ind_Bb_Mode;
   Settings.MfiMode              = Inp_Ind_Mfi_Mode;

   // Active votes
   Settings.Ind_EmaSig_Enabled   = Inp_Ind_EmaSig_Enabled;
   Settings.Ind_Adx_Enabled      = Inp_Ind_Adx_Enabled;
   Settings.Ind_Macd_Enabled     = Inp_Ind_Macd_Enabled;
   Settings.Ind_Rsi_Enabled      = Inp_Ind_Rsi_Enabled;
   Settings.Ind_Cci_Enabled      = Inp_Ind_Cci_Enabled;
   Settings.Ind_Mfi_Enabled      = Inp_Ind_Mfi_Enabled;
   Settings.Ind_Sto_Enabled      = Inp_Ind_Sto_Enabled;
   Settings.Ind_Bb_Enabled       = Inp_Ind_Bb_Enabled;
   Settings.Ind_Psar_Enabled     = Inp_Ind_Psar_Enabled;
   Settings.Ind_P123_Enabled     = Inp_Ind_P123_Enabled;
   Settings.Ind_Ross_Enabled     = Inp_Ind_Ross_Enabled;
   Settings.Ind_Atr_Enabled      = Inp_Ind_Atr_Enabled;
   Settings.Ind_CandleBody_Enabled = Inp_Ind_CandleBody_Enabled;
   Settings.Ind_CI_Enabled        = Inp_Ind_CI_Enabled;

   // Per-indicator vote weights (1 = standard; used in VOTE_MODE_THRESHOLD for weighted sum)
   // In VOTE_MODE_ALL (recommended), weights are ignored — all enabled indicators must simply agree.
   Settings.Ind_EmaSig_Weight    = Inp_Ind_EmaSig_Weight;
   Settings.Ind_Adx_Weight       = Inp_Ind_Adx_Weight;
   Settings.Ind_Macd_Weight      = Inp_Ind_Macd_Weight;
   Settings.Ind_Rsi_Weight       = Inp_Ind_Rsi_Weight;
   Settings.Ind_Cci_Weight       = Inp_Ind_Cci_Weight;
   Settings.Ind_Mfi_Weight       = Inp_Ind_Mfi_Weight;
   Settings.Ind_Sto_Weight       = Inp_Ind_Sto_Weight;
   Settings.Ind_Bb_Weight        = Inp_Ind_Bb_Weight;
   Settings.Ind_Psar_Weight      = Inp_Ind_Psar_Weight;
   Settings.Ind_P123_Weight      = Inp_Ind_P123_Weight;
   Settings.Ind_Ross_Weight      = Inp_Ind_Ross_Weight;
   Settings.Ind_Atr_Weight       = Inp_Ind_Atr_Weight;
   Settings.Ind_CandleBody_Weight = Inp_Ind_CandleBody_Weight;
   Settings.Ind_CI_Weight         = Inp_Ind_CI_Weight;

   // Choppiness Index
   Settings.CI_Period             = MathMax(5, Inp_CI_Period);
   Settings.CI_RangingThreshold   = MathMax(0.0, Inp_CI_RangingThreshold);

   // Exits
   Settings.SL_FixedPips         = Inp_SL_FixedPips;

   // SL/TP strategy configuration
   Settings.SLMode         = Inp_SLMode;
   Settings.TPMode         = Inp_TPMode;
   Settings.FixedTPPips    = Inp_FixedTPPips;
   Settings.SLPercent      = Inp_SLPercent;
   Settings.RRRatio        = Inp_RRRatio;
   Settings.SwingLookback  = Inp_SwingLookback;

   // Fractal/PSAR SL/TP settings
   Settings.FractalPeriod      = Inp_FractalPeriod;
   Settings.TPFractalOffset    = Inp_TPFractalOffset;
   Settings.PSARStep           = Inp_PSARStep;
   Settings.PSARMax            = Inp_PSARMax;

   // Advanced trailing trigger settings
   Settings.TrailTrigger       = Inp_TrailTrigger;
   Settings.TrailDistancePips  = Inp_TrailDistancePips;
   Settings.BEThresholdPips    = Inp_BEThresholdPips;
   Settings.TrailProfitPercent = Inp_TrailProfitPercent;
   Settings.TrailStepPips      = Inp_TrailStepPips;
   Settings.TrailLockProfit    = Inp_TrailLockProfit;

   Settings.TP_Enabled           = Inp_TP_Enabled;

   Settings.TrailMode            = Inp_TrailMode;
   Settings.PSAR_TrailCushionMode= Inp_PSAR_TrailCushionMode;
   Settings.PSAR_TrailDelay      = (Inp_PSAR_TrailDelay < 1) ? 1 : (Inp_PSAR_TrailDelay > 3) ? 3 : Inp_PSAR_TrailDelay;

   // RRM exit contract
   Settings.ExitProfile             = Inp_ExitProfile;
   Settings.BE_Mode                 = Inp_BE_Mode;
   Settings.RRM_BE_ProgressPct      = Inp_RRM_BE_ProgressPct;
   Settings.RRM_BE_RMultiple        = Inp_RRM_BE_RMultiple;
   Settings.RRM_TrailPsarShiftDelay = (Inp_RRM_TrailPsarShiftDelay < 1) ? 1 : (Inp_RRM_TrailPsarShiftDelay > 3) ? 3 : Inp_RRM_TrailPsarShiftDelay;
   Settings.RRM_FreezeTrailOnFlip   = Inp_RRM_FreezeTrailOnFlip;
   Settings.RRM_TrailStartsAfterBE  = Inp_RRM_TrailStartsAfterBE;

   // ═══════════════════════════════════════════════════════════════
   // Auto-set cushions using TF-based functions (before preset application)
   // Placed here so the diagnostic print below reflects the final values.
   // ═══════════════════════════════════════════════════════════════
   // SL cushions (PSAR and Swing modes)
   Settings.SL_PsarPipsCushion    = GetRecommendedInitialSlCushionPips();
   Settings.SL_SwingPipsCushion   = GetRecommendedInitialSlCushionPips();

   // Trailing cushion (PSAR trailing mode)
   Settings.PSAR_TrailPipsCushion = GetRecommendedTrailPsarCushionPips();

   // Breakeven buffer (RRM BE modes) — auto from TF
   Settings.RRM_BE_BufferPips     = GetTFBasedCushion(Period());

   // ═══════════════════════════════════════════════════════════════
   // 🔍 DIAGNOSTIC: Log exit management mapping
   // ═══════════════════════════════════════════════════════════════
   if(Settings.DebugLevel >= DEBUG_SUMMARY || Settings.PrintEffectiveConfig)
   {
      Print("════════════════════════════════════════════════════════════");
      Print("🔍 DIAGNOSTIC: InitializeConfig() - Exit Management Mapping");
      Print("════════════════════════════════════════════════════════════");
      Print("");
      Print("📊 INPUTS → SETTINGS:");
      Print("  ExitProfile:");
      Print("    Input:  Inp_ExitProfile = ", EnumToString(Inp_ExitProfile));
      Print("    Mapped: Settings.ExitProfile = ", EnumToString(Settings.ExitProfile));
      Print("    ✓ Match: ", (Settings.ExitProfile == Inp_ExitProfile ? "YES" : "❌ NO - BUG!"));
      Print("");

      Print("  Stop Loss:");
      Print("    Input:  Inp_SLMode = ", EnumToString(Inp_SLMode));
      Print("    Mapped: Settings.SLMode = ", EnumToString(Settings.SLMode));
      Print("    ✓ Match: ", (Settings.SLMode == Inp_SLMode ? "YES" : "❌ NO - BUG!"));
      Print("    Auto:   Settings.SL_PsarPipsCushion = ", Settings.SL_PsarPipsCushion, " (TF-based)");
      Print("");

      Print("  Take Profit:");
      Print("    Input:  Inp_TPMode = ", EnumToString(Inp_TPMode));
      Print("    Mapped: Settings.TPMode = ", EnumToString(Settings.TPMode));
      Print("    ✓ Match: ", (Settings.TPMode == Inp_TPMode ? "YES" : "❌ NO - BUG!"));
      Print("    Input:  Inp_RRRatio = ", Inp_RRRatio);
      Print("    Mapped: Settings.RRRatio = ", Settings.RRRatio);
      Print("");

      Print("  Breakeven (RRM Mode):");
      Print("    Input:  Inp_BE_Mode = ", EnumToString(Inp_BE_Mode));
      Print("    Mapped: Settings.BE_Mode = ", EnumToString(Settings.BE_Mode));
      Print("    ✓ Match: ", (Settings.BE_Mode == Inp_BE_Mode ? "YES" : "❌ NO - BUG!"));
      Print("    Input:  Inp_RRM_BE_ProgressPct = ", Inp_RRM_BE_ProgressPct);
      Print("    Mapped: Settings.RRM_BE_ProgressPct = ", Settings.RRM_BE_ProgressPct);
      Print("    Auto:   Settings.RRM_BE_BufferPips = ", Settings.RRM_BE_BufferPips, " (TF-based)");
      Print("");

      Print("  Trailing Stop:");
      Print("    Input:  Inp_TrailMode = ", EnumToString(Inp_TrailMode));
      Print("    Mapped: Settings.TrailMode = ", EnumToString(Settings.TrailMode));
      Print("    ✓ Match: ", (Settings.TrailMode == Inp_TrailMode ? "YES" : "❌ NO - BUG!"));
      Print("    Auto:   Settings.PSAR_TrailPipsCushion = ", Settings.PSAR_TrailPipsCushion, " (TF-based)");
      Print("    Input:  Inp_PSAR_TrailDelay = ", Inp_PSAR_TrailDelay);
      Print("    Mapped: Settings.PSAR_TrailDelay = ", Settings.PSAR_TrailDelay);
      Print("    Input:  Inp_RRM_TrailStartsAfterBE = ", Inp_RRM_TrailStartsAfterBE);
      Print("    Mapped: Settings.RRM_TrailStartsAfterBE = ", Settings.RRM_TrailStartsAfterBE);
      Print("");

      Print("════════════════════════════════════════════════════════════");
      Print("✅ InitializeConfig() complete - values stored in Settings");
      Print("════════════════════════════════════════════════════════════");
      Print("");
   }

   // Gate system defaults (all gates off; presets may enable them)
   // RequirePullback, PullbackLookback, RequireRecoveryMomentum are mapped from inputs above
   Settings.Vote_EvalShift           = 1;
   Settings.Vote_AllowPsarFlip       = false;
   // PSAR flip defaults
   Settings.Vote_PsarFlipDelay       = (Inp_Vote_PsarFlipDelay < -1) ? -1 :
                                        (Inp_Vote_PsarFlipDelay > 10) ? 10 :
                                        Inp_Vote_PsarFlipDelay;  // Clamp to [-1, 10]

   // Risk management defaults
   Settings.MaxTotalRisk      = 0.0;  // 0 = no portfolio limit (backward compatible)
   Settings.MaxOpenTrades     = 0;    // 0 = unlimited (backward compatible)
   Settings.CountBEasZeroRisk = true; // BE trades have 0 risk

   // Adaptive settings: map inputs and derive effective values

   // 1. Map raw adaptive inputs into the struct
   Settings.Adaptive.PairType          = Inp_Adaptive_PairType;
   Settings.Adaptive.Spread_Major      = Inp_Adaptive_Spread_Major;
   Settings.Adaptive.Spread_Minor      = Inp_Adaptive_Spread_Minor;
   Settings.Adaptive.Spread_Exotic     = Inp_Adaptive_Spread_Exotic;
   Settings.Adaptive.Spread_Gold       = Inp_Adaptive_Spread_Gold;
   Settings.Adaptive.Spread_Crypto     = Inp_Adaptive_Spread_Crypto;

   // 2. Auto-detect pair type when set to AUTO
   if(Settings.Adaptive.PairType == PAIR_TYPE_AUTO)
      Settings.Adaptive.PairType = DetectPairType(_Symbol);

   // 3. Apply adaptive spread limit (overrides the operator-gate MaxSpread from Inp_MaxSpreadPips)
   //    The ZONE 2 input remains as a fallback but the adaptive value takes precedence.
   Settings.MaxSpread = GetAdaptiveSpreadLimit(Settings.Adaptive.PairType, Settings.Adaptive);

   // Phase Detection defaults (disabled by default; presets enable)
   Settings.PhaseDetectionEnabled        = false;
   Settings.BlockUnorderedPhase          = true;
   Settings.RequireMinPhaseConfirm       = false;
   Settings.MinPhaseConfirmBars          = 0;

   // Phase-specific permissions (default: allow all)
   Settings.Emerging_AllowWeakTrades     = true;
   Settings.Emerging_AllowMediumTrades   = true;
   Settings.Emerging_AllowStrongTrades   = true;
   Settings.Trending_AllowWeakTrades     = true;
   Settings.Trending_AllowMediumTrades   = true;
   Settings.Trending_AllowStrongTrades   = true;

   // Layer Detection defaults (disabled by default; presets enable)
   Settings.EnableLayerDetection         = false;
   Settings.LayerTouchTolerancePips      = 2.0;
   Settings.LayerTouchTolerance          = 0.01;
   Settings.AllowLayer1_Entries          = true;
   Settings.AllowLayer2_Entries          = true;
   Settings.AllowLayer3_Entries          = true;

   // RRM Drawdown Protection (map from inputs)
   Settings.RRM_EnableDrawdownProtection = Inp_RRM_EnableDrawdownProtection;
   Settings.RRM_MaxConsecutiveLosses     = Inp_RRM_MaxConsecutiveLosses;
   Settings.RRM_MaxTradesPerDay          = Inp_RRM_MaxTradesPerDay;
   Settings.RRM_MaxDailyDrawdownPct      = Inp_RRM_MaxDailyDrawdownPct;

   // Slope calculation settings
   Settings.SlopeLookbackBars      = Inp_SlopeLookbackBars;
   Settings.UseSlopeThreshold      = Inp_UseSlopeThreshold;
   Settings.SlopeThresholdPips     = Inp_SlopeThresholdPips;
   Settings.SlopeThresholdAdaptive = Inp_SlopeThresholdAdaptive;
   Settings.SlopeMeasureMode       = Inp_SlopeMeasureMode;

   // Validate lookback range
   if(Settings.SlopeLookbackBars < 1) Settings.SlopeLookbackBars = 1;
   if(Settings.SlopeLookbackBars > 5) Settings.SlopeLookbackBars = 5;
}

//+------------------------------------------------------------------+
//| INDICATOR REGISTRY SYSTEM                                        |
//|                                                                  |
//| Single source of truth for all 13 voting indicators.            |
//| Eliminates manual enumeration scattered across 15+ locations.   |
//|                                                                  |
//| Usage:                                                           |
//|   1. Call InitializeIndicatorRegistry(Settings) in OnInit()     |
//|      after ApplyPreset() so enabled flags are final.            |
//|   2. Use GetEnabledIndicatorCount(cfg) anywhere a count is      |
//|      needed – it accepts a cfg reference so no global state     |
//|      is required for validation / preset functions.             |
//|   3. Use GetEnabledIndicatorList(cfg, compact) for display.     |
//|   4. Use PrintIndicatorRegistry() for debug inspection.         |
//+------------------------------------------------------------------+

// Metadata for a single voting indicator (used by registry array).
struct SIndicatorMeta {
   string name;         // Full display name (e.g. "CandleBody")
   string short_name;   // Compact code for UI (e.g. "CBody")
   bool   is_enabled;   // Cached enabled state (set at init time)
   int    weight;       // Vote weight (1 for most indicators)
};

// Global registry – initialized once in OnInit() via InitializeIndicatorRegistry().
// Size 14: ADX, ATR, BB, CandleBody, ChoppinessIndex, CCI, EmaSig, MACD, MFI, P123, PSAR, Ross, RSI, Stochastic
SIndicatorMeta g_indicator_registry[14];

//+------------------------------------------------------------------+
//| InitializeIndicatorRegistry(): Populate registry from settings  |
//| Call once in OnInit() after InitializeConfig() + ApplyPreset()  |
//+------------------------------------------------------------------+
void InitializeIndicatorRegistry(const ST_Settings &cfg)
{
   int i = 0;

   // Alphabetical order – matches ordering used elsewhere in the codebase
   g_indicator_registry[i].name       = "ADX";
   g_indicator_registry[i].short_name = "ADX";
   g_indicator_registry[i].is_enabled = cfg.Ind_Adx_Enabled;
   g_indicator_registry[i].weight     = cfg.Ind_Adx_Weight;
   i++;

   g_indicator_registry[i].name       = "ATR";
   g_indicator_registry[i].short_name = "ATR";
   g_indicator_registry[i].is_enabled = cfg.Ind_Atr_Enabled;
   g_indicator_registry[i].weight     = cfg.Ind_Atr_Weight;
   i++;

   g_indicator_registry[i].name       = "BB";
   g_indicator_registry[i].short_name = "BB";
   g_indicator_registry[i].is_enabled = cfg.Ind_Bb_Enabled;
   g_indicator_registry[i].weight     = cfg.Ind_Bb_Weight;
   i++;

   g_indicator_registry[i].name       = "CandleBody";
   g_indicator_registry[i].short_name = "CBody";
   g_indicator_registry[i].is_enabled = cfg.Ind_CandleBody_Enabled;
   g_indicator_registry[i].weight     = cfg.Ind_CandleBody_Weight;
   i++;

   g_indicator_registry[i].name       = "ChoppinessIndex";
   g_indicator_registry[i].short_name = "CI";
   g_indicator_registry[i].is_enabled = cfg.Ind_CI_Enabled;
   g_indicator_registry[i].weight     = cfg.Ind_CI_Weight;
   i++;

   g_indicator_registry[i].name       = "CCI";
   g_indicator_registry[i].short_name = "CCI";
   g_indicator_registry[i].is_enabled = cfg.Ind_Cci_Enabled;
   g_indicator_registry[i].weight     = cfg.Ind_Cci_Weight;
   i++;

   g_indicator_registry[i].name       = "EmaSig";
   g_indicator_registry[i].short_name = "EmaSig";
   g_indicator_registry[i].is_enabled = cfg.Ind_EmaSig_Enabled;
   g_indicator_registry[i].weight     = cfg.Ind_EmaSig_Weight;
   i++;

   g_indicator_registry[i].name       = "MACD";
   g_indicator_registry[i].short_name = "MACD";
   g_indicator_registry[i].is_enabled = cfg.Ind_Macd_Enabled;
   g_indicator_registry[i].weight     = cfg.Ind_Macd_Weight;
   i++;

   g_indicator_registry[i].name       = "MFI";
   g_indicator_registry[i].short_name = "MFI";
   g_indicator_registry[i].is_enabled = cfg.Ind_Mfi_Enabled;
   g_indicator_registry[i].weight     = cfg.Ind_Mfi_Weight;
   i++;

   g_indicator_registry[i].name       = "P123";
   g_indicator_registry[i].short_name = "P123";
   g_indicator_registry[i].is_enabled = cfg.Ind_P123_Enabled;
   g_indicator_registry[i].weight     = cfg.Ind_P123_Weight;
   i++;

   g_indicator_registry[i].name       = "PSAR";
   g_indicator_registry[i].short_name = "PSAR";
   g_indicator_registry[i].is_enabled = cfg.Ind_Psar_Enabled;
   g_indicator_registry[i].weight     = cfg.Ind_Psar_Weight;
   i++;

   g_indicator_registry[i].name       = "Ross";
   g_indicator_registry[i].short_name = "Ross";
   g_indicator_registry[i].is_enabled = cfg.Ind_Ross_Enabled;
   g_indicator_registry[i].weight     = cfg.Ind_Ross_Weight;
   i++;

   g_indicator_registry[i].name       = "RSI";
   g_indicator_registry[i].short_name = "RSI";
   g_indicator_registry[i].is_enabled = cfg.Ind_Rsi_Enabled;
   g_indicator_registry[i].weight     = cfg.Ind_Rsi_Weight;
   i++;

   g_indicator_registry[i].name       = "Stochastic";
   g_indicator_registry[i].short_name = "Stoch";
   g_indicator_registry[i].is_enabled = cfg.Ind_Sto_Enabled;
   g_indicator_registry[i].weight     = cfg.Ind_Sto_Weight;
   // i++; // last entry – omitted intentionally
}

//+------------------------------------------------------------------+
//| GetEnabledIndicatorCount(): Count enabled voting indicators      |
//| Accepts cfg directly – works before InitializeIndicatorRegistry  |
//+------------------------------------------------------------------+
int GetEnabledIndicatorCount(const ST_Settings &cfg)
{
   int count = 0;
   if(cfg.Ind_Adx_Enabled)        count++;
   if(cfg.Ind_Atr_Enabled)        count++;
   if(cfg.Ind_Bb_Enabled)         count++;
   if(cfg.Ind_CandleBody_Enabled) count++;
   if(cfg.Ind_CI_Enabled)         count++;
   if(cfg.Ind_Cci_Enabled)        count++;
   if(cfg.Ind_EmaSig_Enabled)     count++;
   if(cfg.Ind_Macd_Enabled)       count++;
   if(cfg.Ind_Mfi_Enabled)        count++;
   if(cfg.Ind_P123_Enabled)       count++;
   if(cfg.Ind_Psar_Enabled)       count++;
   if(cfg.Ind_Ross_Enabled)       count++;
   if(cfg.Ind_Rsi_Enabled)        count++;
   if(cfg.Ind_Sto_Enabled)        count++;
   return count;
}

//+------------------------------------------------------------------+
//| GetEnabledIndicatorList(): Comma-separated list of active names  |
//| Uses cfg directly (same as GetEnabledIndicatorCount).            |
//| compact=true  → short name (e.g. "CBody")                        |
//| compact=false → full name  (e.g. "CandleBody")                   |
//+------------------------------------------------------------------+
string GetEnabledIndicatorList(const ST_Settings &cfg, bool compact = true)
{
   // Table of all 13 indicators: {full name, short name, enabled flag}
   string names[]  = {"ADX",      "ATR",  "BB",  "CandleBody", "CCI",  "EmaSig", "MACD",
                       "MFI",      "P123", "PSAR","Ross",       "RSI",  "Stochastic"};
   string shorts[] = {"ADX",      "ATR",  "BB",  "CBody",      "CCI",  "EmaSig", "MACD",
                       "MFI",      "P123", "PSAR","Ross",       "RSI",  "Stoch"};
   bool enabled[]  = {cfg.Ind_Adx_Enabled, cfg.Ind_Atr_Enabled, cfg.Ind_Bb_Enabled,
                       cfg.Ind_CandleBody_Enabled, cfg.Ind_Cci_Enabled, cfg.Ind_EmaSig_Enabled,
                       cfg.Ind_Macd_Enabled, cfg.Ind_Mfi_Enabled, cfg.Ind_P123_Enabled,
                       cfg.Ind_Psar_Enabled, cfg.Ind_Ross_Enabled, cfg.Ind_Rsi_Enabled,
                       cfg.Ind_Sto_Enabled};
   string list = "";
   for(int i = 0; i < 13; i++)
   {
      if(!enabled[i]) continue;
      if(list != "") list += compact ? ", " : "\n  + ";
      list += compact ? shorts[i] : names[i];
   }
   return (list == "" ? "None" : list);
}

//+------------------------------------------------------------------+
//| PrintIndicatorRegistry(): Debug dump of full registry state      |
//+------------------------------------------------------------------+
void PrintIndicatorRegistry()
{
   Print("--- Indicator Registry (13 entries) ---");
   for(int i = 0; i < 13; i++)
   {
      PrintFormat("  [%2d] %-12s  enabled=%-5s  weight=%d",
                  i,
                  g_indicator_registry[i].name,
                  (g_indicator_registry[i].is_enabled ? "true" : "false"),
                  g_indicator_registry[i].weight);
   }
}

//+------------------------------------------------------------------+
//| END OF FILE                                                      |
//+------------------------------------------------------------------+