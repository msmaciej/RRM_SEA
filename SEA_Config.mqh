//+------------------------------------------------------------------+
//|                                                   SEA_Config.mqh |
//|                                   Copyright 2026, SimpleEA System|
//+------------------------------------------------------------------+
#property strict

//+------------------------------------------------------------------+
//| ENUMS
//+------------------------------------------------------------------+
enum EDebugLevel
{
   DEBUG_SILENT,           // DEBUG_SILENT: No per-bar output (statistics only at end)
   DEBUG_SUMMARY,          // DEBUG_SUMMARY: Per-bar: signal result + rejection reason (1-2 lines)
   DEBUG_INDICATORS,       // DEBUG_INDICATORS: Per-bar: indicator pass/fail + summary (20-30 lines)
   DEBUG_FULL,             // DEBUG_FULL: Everything: all internal steps + diagnostics (50+ lines)
   DEBUG_SIGNALS_ONLY      // DEBUG_SIGNALS_ONLY: FULL debug ONLY for confirmed signals (TS≠0)
};
enum EStrategyPreset
{
   PRESET_CUSTOM,          // PRESET_CUSTOM: user-defined settings
   PRESET_MA,              // PRESET_MA: benchmark: MT5 MA EA compatibility
   PRESET_RRM,             // PRESET_RRM: phase-based layer detection system
   PRESET_TEST,            // PRESET_TEST: development/debugging preset
   PRESET_FPM,             // PRESET_FPM: Five-Point Method (PSAR+MACD+BB+SMA10/20)
   PRESET_RRM_ORG          // PRESET_RRM_ORG: Russ Horn Original RRM with inline DPI momentum voter
};
enum EEmaStrategy
{
   EMA_STRAT_1_PRICE_CROSS,// EMA_STRAT_1: Buy if Price > EMA1 (Benchmark)
   EMA_STRAT_2_CROSS_1_2,  // EMA_STRAT_2: Buy if EMA1 > EMA2 (Golden Cross)
   EMA_STRAT_2_CROSS_3_4,  // EMA_STRAT_2: Buy if EMA3 > EMA4 (Slow Trend)
   EMA_STRAT_CUSTOM        // EMA_STRAT_CUSTOM: manual: use "Advanced Bias" inputs below
};
enum EMaMethod
{
   METHOD_EMA,             // METHOD_EMA: exponential
   METHOD_SMA              // METHOD_SMA: simple
};
enum EBiasMode
{
   BIAS_MANUAL,            // BIAS_MANUAL: User fixed (Long/Short/Both)
   BIAS_1EMA,              // BIAS_1EMA: slope only
   BIAS_2EMA,              // BIAS_2EMAs: cross or pos+slope
   BIAS_4EMA               // BIAS_4EMAs: phase detection (TRENDING/EMERGING/UNORDERED)
};
enum EMarketPhase {
   PHASE_UNORDERED,        // PHASE_UNO: block all trades (TS = 0) — EMA2 sandwiched or no clear arrangement
   PHASE_EMERGING,         // PHASE_EM: legacy non-directional emerging (use EMERGING_UP/DN)
   PHASE_TRENDING,         // PHASE_TM: legacy non-directional trending (use TRENDING_UP/DN)
   PHASE_TRENDING_UP,      // PHASE_TM_UP: EMA2 > EMA3 > EMA4 (ascending stack, bullish)
   PHASE_TRENDING_DN,      // PHASE_TM_DN: EMA4 > EMA3 > EMA2 (descending stack, bearish)
   PHASE_EMERGING_UP,      // PHASE_EM_UP: EMA2 > EMA4 > EMA3 (EMA4 sandwiched, bullish emerging)
   PHASE_EMERGING_DN       // PHASE_EM_DN: EMA3 > EMA4 > EMA2 (EMA4 sandwiched, bearish emerging)
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
//+------------------------------------------------------------------+
//| Layer Pullback State Machine                                     |
//+------------------------------------------------------------------+
enum ELayerPullbackState
{
   LAYER_PB_NONE,        // No pullback detected yet (initial trending)
   LAYER_PB_DETECTED,    // Pullback or flat phase observed
   LAYER_PB_RECOVERED    // Recovery confirmed (ready to trade)
};
enum EManualSide
{
   SIDE_BOTH,              // SIDE_BOTH ... L-S: Allow both long and short trades
   SIDE_LONG,              // SIDE_LONG ... L: Long trades only
   SIDE_SHORT              // SIDE_SHORT ... S: Short trades only
};
enum EAutoStrategy
{
   STRAT_1EMA_SLOPE,       // STRAT_1EMA_SLOPE ... ONLY for BIAS_1EMA: single EMA slope direction
   STRAT_2EMA_CROSS_EMA,   // STRAT_2EMA_CROSS_EMA ... ONLY for BIAS_2EMA: two EMAs crossover (one-bar signal)
   STRAT_2EMA_CROSS_PRICE, // STRAT_2EMA_CROSS_PRICE ... ONLY for BIAS_2EMA: price crosses EMA (one-bar signal at cross point)
   STRAT_2EMA_POSITION,    // STRAT_2EMA_POS ... ONLY for BIAS_2EMA: EMA position + slope confirmation (persistent bias)
   STRAT_4EMA_LAYER        // STRAT_4EMA_LAYER ... ONLY for BIAS_4EMA: four EMAs with LayerW/M/S pullback detection
};
enum EEmaRole
{
   ROLE_EMA1,              // ROLE_EMA1: Fast EMA (5-period default) - L1_WEAK layer
   ROLE_EMA2,              // ROLE_EMA2: Medium-fast EMA (13-period default) - L2_MEDIUM layer
   ROLE_EMA3,              // ROLE_EMA3: Medium-slow EMA (34-period default) - L3_STRONG layer
   ROLE_EMA4               // ROLE_EMA4: Slow EMA (144-period default) - Trend filter
};

//+------------------------------------------------------------------+
//| BarClose Mode: Which EMA to check for bar close confirmation     |
//| Used by bcX component in the signal formula                      |
//+------------------------------------------------------------------+
enum EBarCloseMode
{
   BC_DISABLED    = 0,     // BC_Disabled: always returns 1 (skip bar close check)
   BC_FIXED_EMA   = 1,     // BC_Fixed_EMA: always check vs BarClose_DefaultEMA
   BC_LAYER_AWARE = 2,     // BC_Layer_Aware: bcW=EMA1, bcM=EMA2, bcS=EMA3
   BC_BIAS_FAST   = 3      // BC_Bias_Fast: ID EMA
};

//+------------------------------------------------------------------+
//| Indicator Modes
//+------------------------------------------------------------------+
enum EADXMode {
   ADX_MODE_STATIC = 0,          // ADX_STATIC: Fixed threshold (current behavior)
   ADX_MODE_DYNAMIC_PERCENTILE,  // ADX_DYNAMIC: Adaptive threshold based on historical percentile
   ADX_MODE_PHASE_AWARE          // ADX_PHASE: Phase-specific thresholds
};
enum EBbMode
{
   BB_TREND_FOLLOW,        // BB_TREND_FOLLOW: Price near outer band = trend continuation
   BB_MEAN_REVERSION,      // BB_MEAN_REVERSION: Price at outer band = reversion to middle
   BB_WIDENING             // BB_WIDENING: Bands actively expanding (upper-lower gap increasing bar-to-bar)
};
enum ECciMode
{
   CCI_TREND_ZERO,         // CCI_Trend_Zero based on zero line (>0 bull, <0 bear)
   CCI_IMPULSE_100         // CCI_Impulse_100 (>100 or <-100)
};
enum EMacdVoteMode
{
   // === SINGLE CHECKS (persistent) ===
   MACD_ZERO_LINE,         // MACD_ZERO_LINE: Main > 0 (bullish momentum zone)
   MACD_HISTOGRAM,         // MACD_HISTOGRAM: Histogram > 0 (acceleration)
   MACD_CROSSOVER,         // MACD_CROSSOVER: Main > Signal (momentum shift)

   // === COMBINATION CHECKS (persistent, strict) ===
   MACD_ZERO_AND_CROSS,    // MACD_ZERO_&_CROSS (RRM default, industry "traditional")
   MACD_ZERO_AND_HIST,     // MACD_ZERO_&_HIST (strict momentum)
   MACD_TRIPLE,            // MACD_TRIPLE: Zero+Cross+Histogram (ultra-strict)

   // === TIME-LIMITED (fresh signals only) ===
   MACD_CROSSOVER_N,       // MACD_CROSS_N: Fresh crossover (within N bars)
   MACD_ZERO_CROSS_N       // MACD_ZERO_CROSS_N: Fresh zero cross (within N bars)
};
enum EMfiMode
{
   MFI_ZONE_FILTER,        // MFI_ZONE: Zone-based filtering (>80 overbought, <20 oversold)
   MFI_TREND_50            // MFI_TREND: Trend following (>50 bullish, <50 bearish)
};
enum ERsiMode
{
   RSI_FILTER_EXTREME,     // RSI_FILTER: Extreme zones only (>70 overbought, <30 oversold)
   RSI_TREND_ABOVE_50,     // RSI_TREND: Trend following (>50 bullish, <50 bearish)
   RSI_CROSS_LEVEL         // RSI_CROSS: Cross 50-level signal
};
enum EStochMode
{
   STO_CROSS_SIGNAL,       // STO_CROSS: %K crosses %D signal line
   STO_ZONE_FILTER         // STO_ZONE: Overbought/oversold zones (>80 / <20)
};
enum EVolatilityRegime {
   VOLATILITY_LOW = 0,    // Below low threshold (too quiet, likely choppy)
   VOLATILITY_NORMAL,     // Between thresholds (acceptable trading conditions)
   VOLATILITY_HIGH        // Above high threshold (explosive) - reserved for future use
};

//+------------------------------------------------------------------+
//| CUSHION | TRAIL | SL | TP | BE | EXIT
//+------------------------------------------------------------------+
enum EPsarTrailCushionMode
{
   PSAR_CUSHION_PIPS       // PSAR: Fixed pips cushion
};
enum ETrailTrigger
{
   TRIGGER_IMMEDIATE,      // TRIGGER_IMMEDIATE: Tr from entry (default)
   TRIGGER_BREAKEVEN,      // TRIGGER_BREAKEVEN: Tr after breakeven threshold reached
   TRIGGER_PROFIT_PIPS,    // TRIGGER_PROFIT_PIPS: Tr after X pips profit (TrailDistancePips)
   TRIGGER_PROFIT_PERCENT, // TRIGGER_PROFIT_PERCENT: Tr after X% profit (TrailProfitPercent)
   TRIGGER_PSAR_ALIGN      // TRIGGER_PSAR_ALIGN: Tr when PSAR aligns with position direction
};
enum ETrailingMode
{
   TRAIL_BREAKEVEN,        // TRAIL_BREAKEVEN: move to breakeven then trail fixed pips
   TRAIL_FIXED_PIPS,       // TRAIL_FIXED_PIPS: fixed pip distance trailing
   TRAIL_FRACTAL,          // TRAIL_FRACTAL: fractal-based trailing
   TRAIL_NONE,             // TRAIL_NONE: no trailing stop
   TRAIL_PROFIT_PERCENT,   // TRAIL_PROFIT_PERCENT: trail after profit % threshold reached
   TRAIL_PSAR,             // TRAIL_PSAR: dot trailing
   TRAIL_PSAR_FLIP_EXIT    // TRAIL_PSAR_FLIP_EXIT: close position on PSAR flip
};
enum ESLMode
{
   SL_MODE_FIXED_PIPS,     // SL_MODE_FIXED_PIPS: Fixed pips (default)
   SL_MODE_FRACTAL,        // SL_MODE_FRACTAL: Last fractal level (Bill Williams)
   SL_MODE_PERCENT,        // SL_MODE_PERCENT: Percentage of entry price
   SL_MODE_SWING,          // SL_MODE_SWING: Recent swing high/low (SwingLookback bars)
   SL_MODE_PSAR_DOT        // SL_MODE_PSAR_DOT: PSAR dot position
};
enum ETPMode
{
   TP_MODE_FIXED_PIPS,     // TP_MODE_FIXED_PIPS: (default)
   TP_MODE_RR,             // TP_MODE_RR: (TP = SL distance × RRRatio)
   TP_MODE_FRACTAL,        // TP_MODE_FRACTAL: Next fractal level as TP target
   TP_MODE_PSAR_FLIP,      // TP_MODE_PSAR_FLIP: Exit when PSAR flips (TP handled by TM)
   TP_MODE_NONE            // TP_MODE_NONE: No TP, rely on trailing stop only
};
enum EBeMode
{
   BE_MODE_OFF,            // BE_MODE_OFF: Breakeven disabled (default)
   BE_MODE_TP_PROGRESS_PCT,// BE_MODE_TP_PROGRESS_PCT: BE triggers at % progress toward TP (used with TP enabled)
   BE_MODE_R_MULTIPLE      // BE_MODE_R_MULTIPLE: BE triggers at k*R multiple (used when TP is disabled)
};
enum EExitProfile
{
   EXIT_PROFILE_NONE,      // EXIT_PROFILE_NONE: No exit profile (manual management)
   EXIT_PROFILE_SIMPLE,    // EXIT_PROFILE_SIMPLE: Simple: Fixed SL/TP, basic trailing
   EXIT_PROFILE_RRM        // EXIT_PROFILE_RRM: RRM: Swing-based SL, PSAR trail, no ATR multipliers
};


enum EGateScaleMode
{
   GATE_SCALE_OFF,         // GATE_OFF: Gate disabled
   GATE_SCALE_FIXED,       // GATE_FIXED: Use fixed pip value
   GATE_SCALE_AUTO_TF      // GATE_AUTO: Auto-scale by timeframe/pair
};
enum EVoteMode
{
   VOTE_MODE_THRESHOLD,    // VOTE_THRESHOLD: minimum weighted votes required (default)
   VOTE_MODE_ALL           // VOTE_ALL: every enabled indicator must agree
};
enum EPairType
{
   PAIR_TYPE_AUTO,         // PAIR_AUTO : Auto-detect from symbol name
   PAIR_TYPE_MAJOR,        // PAIR_MAJOR : EUR/USD, GBP/USD, etc (tight spreads 1-2 pips)
   PAIR_TYPE_MINOR,        // PAIR_MINOR : EUR/GBP, EUR/AUD, etc (medium spreads 2-4 pips)
   PAIR_TYPE_EXOTIC,       // PAIR_EXOTIC : USD/TRY, USD/ZAR, etc (wide spreads 5-15 pips)
   PAIR_TYPE_GOLD,         // PAIR_GOLD : XAU/USD (medium spreads 3-5 pips, high volatility)
   PAIR_TYPE_CRYPTO        // PAIR_CRYPTO : BTC/USD (very wide spreads, extreme volatility)
};
enum EUIFrameMode
{
   UI_FRAME_BG,            // UI: Rectangle background (default)
   UI_FRAME_NONE,          // UI: Text only (no rectangle)
   UI_FRAME_TEXT_BOUNDS    // UI: Text bounds markers (BEGIN/END), no rectangle
};
//+------------------------------------------------------------------+
//| STRUCTURES
//+------------------------------------------------------------------+
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
struct SGateConfig
{
   EGateScaleMode mode;
   double         value;   // Fixed pips or TF scaling factor
};
struct SNewsEvent
{
   datetime time;
   string   currency;
   string   impact;
};
struct SVoteSnapshot
{
   string name;            // "MACD", "PSAR", etc.
   string state;           // "BUY", "SELL", "FLAT", "PASS"
   string reason;          // Brief explanation
   bool   enabled;         // Is this vote enabled in config?
   int    vote_result;     // +1 = pass (matches bias), 0 = fail
};

// Single settings struct used across the EA
// NOTE: Architecture currently expects a global "Settings" instance of this type.
struct ST_Settings
{

   // --- UI Theme & Dashboards ---
   color clr_Header;       // Header Text Color
   color clr_Value;        // Market Data Color
   color clr_Pass;         // Logic PASS Color
   color clr_Fail;         // Logic FAIL Color
   color clr_Disabled;     // Logic DISABLED Color
   
   bool  UseCustomColors;  // Toggle for Inp_UI_UseCustomColors
   color UI_FontColor;     // From Inp_UI_FontColor (Yellow)
   
   // --- UI ---
   bool UI_ShowStatusPanel;
   bool UI_ShowCockpitPanel;
   bool UI_ManageChartIndicators;
   bool DrawEntryLines;
   bool DrawTradeLines;
   
   // Logic
   bool CloseOnReverse;

   // Risk
   double RiskPercent;
   double MaxTotalRisk;          // Max % of account at risk simultaneously (e.g., 4.0)
   int    MaxOpenTrades;         // Max number of concurrent trades (0 = no limit)
   bool   CountBEasZeroRisk;     // If true, trades at breakeven don't count toward risk
   double MarginUsageLimit;      // Max % of free margin allowed per trade (0 = use 100%)
   double MinMarginLevel;        // Block new entries if margin level (%) is below this threshold (0 = disabled)
   double EmergencyMarginLevel;  // Emergency TM threshold (%) to cut worst position (0 = disabled)
   double MaxSpread;
   bool   UseSpread;             // Enable spread filter (false = bypass spread gate)

   // Candle Body Overextension Indicator (voting)
   int    CandleBody_AvgPeriod;        // Bars used to compute average body size
   double CandleBody_MaxMult;          // Block if body > avg * multiplier
   int    CandleBody_CheckBars;        // Number of recent closed candles to check
   bool   CandleBody_RequireDirection; // CandleBody: Require signal bar to close in trade direction
   
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
   EVoteMode VoteMode; // ALL: every enabled indicator must agree (recommended); THRESHOLD: uses same all_pass logic as ALL mode

   // Per-indicator weights (1 = standard; only used in VOTE_MODE_THRESHOLD for weighted sum)
   // In VOTE_MODE_ALL, weights are ignored — all enabled indicators must simply agree.
   int Ind_Adx_Weight;
   int Ind_Atr_Weight;
   int Ind_Bb_Weight;
   int Ind_CandleBody_Weight;
   int Ind_Cci_Weight;
   int Ind_CI_Weight;
   int Ind_Mfi_Weight;
   int Ind_Macd_Weight;
   int Ind_Psar_Weight;
   int Ind_P123_Weight;
   int Ind_Ross_Weight;
   int Ind_Rsi_Weight;
   int Ind_SmaConverge_Weight;  // Weight for VOTE_MODE_THRESHOLD
   int Ind_Sto_Weight;
   int Ind_VRC_Weight;

   // Choppiness Index
   int    CI_Period;
   double CI_RangingThreshold;

   // VRC (Volatility Regime Classifier)
   bool   Ind_VRC_Enabled;
   bool   Ind_SmaConverge_Enabled;  // SMA Convergence vote (gap narrowing = pullback signal)
   bool   Ind_Dpi_Enabled;          // DPI vote (inline v31 MACD-core momentum indicator)
   int    Ind_Dpi_Weight;           // DPI vote weight
   int    DPI_MACD_Fast;            // MACD fast EMA period (default 8)
   int    DPI_MACD_Slow;            // MACD slow EMA period (default 13)
   int    DPI_RedSignalType;        // Red signal line type: 1=EMA_A 2=EMA_B 3=EMA_C 4=EMA_D 5=Double
   int    DPI_RedEMA_A;             // EMA period for type 1 (default 5)
   int    DPI_RedEMA_B;             // EMA period for type 2 (default 8)
   int    DPI_RedEMA_C;             // EMA period for type 3 (default 13)
   int    DPI_RedEMA_D;             // EMA period for type 4 (default 21)
   int    DPI_DoubleSmoothFirst;    // First EMA in double-smooth path (default 5)
   int    DPI_DoubleSmoothSecond;   // Second EMA in double-smooth path (default 8)
   bool   DPI_UseCCIReset;          // Enable CCI trend filter (default true)
   int    DPI_CCI_Period;           // CCI period (default 13)
   int    DPI_CCI_AppliedPrice;     // CCI price type ENUM_APPLIED_PRICE (default PRICE_TYPICAL)
   bool   DPI_UseGreenHist;         // Enable GREEN momentum overlay (false = v29-equivalent)
   // DPI Histogram Tracking
   double DPI_HistMomentumThreshold; // Momentum threshold for CCI-delta change (dimensionless)
   int    DPI_HistDecelLookback;     // Bars to analyze for deceleration
   bool   DPI_HistTrackingEnabled;   // Master enable for histogram tracking
   int    VRC_ATR_Period;
   int    VRC_Lookback;
   double VRC_LowThreshold;         // Below this percentile = LOW regime (reject trade)

   // Indicators (Periods)
   int    P_Ema1;
   int    P_Ema2;
   int    P_Ema3;
   int    P_Ema4;
   int    P_Adx;
   double    T_Adx;
   
   // ADX mode configuration (EADXMode)
   EADXMode ADX_Mode;                    // Which ADX validation mode to use
   double   ADX_Percentile;              // Percentile for DYNAMIC_PERCENTILE mode (default 50.0)
   int      ADX_Lookback;                // Bars to analyse for DYNAMIC_PERCENTILE mode (default 100)
   double   ADX_Threshold_Accumulation;  // PHASE_AWARE: lower threshold for unordered/emerging phases
   double   ADX_Threshold_Trending;      // PHASE_AWARE: higher threshold for strong trending phases
   double   ADX_Threshold_Distribution;  // PHASE_AWARE: medium threshold for transitional phases
   
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
   double ATR_VoteMinPips;       // ATR voting threshold: minimum pips
   double ATR_VoteMaxPips;       // ATR voting threshold: maximum pips

   // Modes
   EMacdVoteMode MacdVoteMode;          // MACD base vote mode
   bool          MacdRequireSlope;      // Filter: require acceleration
   bool          MacdRequireDivergence; // Filter: require divergence
   bool          MacdRequireHook;       // Filter: require histogram flip
   int           MacdFreshBars;         // For _N modes: fresh signal validity
   double        MacdSlopeMin;          // Min slope threshold (0=disabled)
   ERsiMode   RsiMode;
   ECciMode   CciMode;
   EStochMode StoMode;
   EBbMode    BbMode;

   // Active Votes
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
   SGateConfig Gate_CandleDirection;// Candle direction gate config

   // Fixed lot sizing (0 = use risk-based sizing)
   double FixedLotSize;             // Fixed lot size (0 = risk-based; >0 = fixed)

   // SL - Initial SL Placement
   double   SL_PsarPipsCushion;
   double   SL_SwingPipsCushion;
   double   SL_FixedPips;
   double   SL_MinPips;          // Minimum allowed SL distance (pips; 0 = no user floor, broker min still enforced)
   bool     SL_WidenToMinimum;   // If true widen too-close SL, otherwise block trade (return 0.0)
   
   // SL/TP Strategy Configuration
   ESLMode  SLMode;              // How to calculate SL distance
   ETPMode  TPMode;              // How to calculate TP distance
   double   FixedTPPips;         // Fixed TP distance in pips (TP_MODE_FIXED_PIPS)
   double   SLPercent;           // SL as % of entry price (SL_MODE_PERCENT, e.g. 0.5 = 0.5%)
   double   RRRatio;             // Risk:Reward ratio (TP_MODE_RR, e.g. 2.0 = 1:2)
   int      SwingLookback;       // Bars to look back for swing high/low (SL_MODE_SWING)

   // === Fractal Settings (NEW: Phase 2.2) ===
   int      FractalPeriod;       // Fractal indicator period (default: 5)
   int      TPFractalOffset;     // How many fractals ahead for TP (default: 1)
   
   // Visual markers
   bool     ShowSwingMarkers;
   bool     ShowFractalMarkers;
   int      MarkerLookback;
   bool     ShowMarkerLabels;
   color    SwingHighColor;
   color    SwingLowColor;
   int      SwingMarkerSize;
   color    FractalHighColor;
   color    FractalLowColor;
   int      FractalMarkerSize;

   // Advanced Trailing Settings
   ETrailTrigger TrailTrigger;   // When to begin trailing (default: TRIGGER_IMMEDIATE)
   double   BEThresholdPips;     // Profit pips required before moving to breakeven
   double   TrailDistancePips;   // Fixed trail distance in pips (TRAIL_FIXED_PIPS / trigger threshold)
   double   TrailProfitPercent;  // Profit % threshold for TRIGGER_PROFIT_PERCENT
   double   TrailStepPips;       // Minimum pips movement before updating SL
   bool     TrailLockProfit;     // Lock in profit (never move SL backwards)

   // TS - Trailing SL / TP / BE
   ETrailingMode       TrailMode;
   EPsarTrailCushionMode PSAR_TrailCushionMode;
   double              PSAR_TrailPipsCushion;
   int                 PSAR_TrailDelay;       // PSAR trailing bar-shift delay (1-3)

   // RRM exit contract
   EExitProfile ExitProfile;        // Exit profile selector
   bool         TP_Enabled;         // Whether TP is active
   EBeMode      BE_Mode;            // BE mode for RRM

   // RRM parameters
   double RRM_BE_ProgressPct;       // RRM_BE trigger: % progress toward TP (0..100); used with BE_MODE_TP_PROGRESS_PCT
   double RRM_BE_RMultiple;         // RRM_BE trigger: R-multiple threshold (e.g. 1.0); used with BE_MODE_R_MULTIPLE
   double RRM_BE_BufferPips;        // RRM_BE buffer in pips
   int    RRM_TrailPsarShiftDelay;  // RRM_PSAR trail bar-shift delay (1..3)
   bool   RRM_FreezeTrailOnFlip;    // RRM_Freeze trailing stop on PSAR flip signal
   bool   RRM_TrailStartsAfterBE;   // RRM_Delay trail activation until BE is triggered

   // Gate system (reusable hard gates for any preset)
   bool        RequireRecoveryMomentum;// Require recovery bar to close in trend direction
   int         Vote_EvalShift;         // Shift for vote evaluation
   bool        Vote_AllowPsarFlip;     // Allow PSAR flip signal in votes
   
   // PSAR flip validation parameters (when Vote_AllowPsarFlip=true)
   int         Vote_PsarFlipDelay;     // Flip timer mode: -1 = PERSISTENT, 0 = FLIP_BAR, 1-10 = COUNTDOWN

   // Reporting
   bool ExportCSV;
   
   // --- Global toggles allowed under presets ---
   bool         PrintEffectiveConfig;
   bool         DebugFlow;             // Master on/off switch (true = DEBUG_FULL verbosity)
   EDebugLevel  DebugLevel;            // Debug verbosity level
   
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
   bool     PhaseDetectionEnabled;        // Master switch for phase system
   bool     BlockUnorderedPhase;          // Block trades during UNORDERED phase
   bool     BlockEmergingPhase;           // Block trades during EMERGING phase (trend forming, unconfirmed)
   bool     RequireMinPhaseConfirm;       // Require N consecutive bars in same phase
   int      MinPhaseConfirmBars;          // Minimum bars to confirm phase stability
   
   // Phase-specific trade permissions
   bool     Emerging_AllowWeakTrades;     // EMERGING phase: Allow EMA1/EMA2 entries
   bool     Emerging_AllowMediumTrades;   // EMERGING phase: Allow EMA2/EMA3 entries
   bool     Emerging_AllowStrongTrades;   // EMERGING phase: Allow EMA3/EMA4 entries
   
   bool     Trending_AllowWeakTrades;     // TRENDING phase: Allow EMA1/EMA2 entries
   bool     Trending_AllowMediumTrades;   // TRENDING phase: Allow EMA2/EMA3 entries
   bool     Trending_AllowStrongTrades;   // TRENDING phase: Allow EMA3/EMA4 entries

   // Layer detection settings
    bool     EnableLayerDetection;         // Master switch for multi-layer pullback detection
    bool     AllowLayer1_Entries;          // Allow Layer 1 (EMA1/EMA2 touch) entries
    bool     AllowLayer2_Entries;          // Allow Layer 2 (EMA2/EMA3 touch) entries
    bool     AllowLayer3_Entries;          // Allow Layer 3 (EMA3/EMA4 touch) entries
    // Layer Pullback-Recovery Detection
    bool     LayerPullbackEnabled;         // Master enable for pullback detection
    int      LayerBaselineLookback;        // Bars for baseline slope calculation
    double   LayerPullbackRatio;           // Threshold for pullback detection (dimensionless)
    double   LayerRecoveryRatio;           // Threshold for recovery confirmation (dimensionless)
    double   LayerFlatRatio;               // Threshold for flat market detection (dimensionless)
    bool     LayerAllowReversalPullback;   // Allow slope sign reversal as pullback

    // Diagnostics: statistics configuration
    bool Stats_TrackRejections;      // Track rejection counts per indicator
    bool Stats_TrackPasses;          // Track pass counts (positive stats)
    bool Stats_FullEvaluation;       // Evaluate ALL indicators per bar (no early exit)

   // Targeted bar evaluation debug (force-print window or pinpoint, independent of TS outcome)
   datetime    DebugEvalFrom;       // Force debug output from this bar time (0=disabled)
   datetime    DebugEvalTo;         // Force debug output up to this bar time (0=disabled; paired with From)
   datetime    DebugEvalAt;         // Force debug output at this exact bar time (0=disabled)
   EDebugLevel DebugEvalMode;       // Debug level to apply during forced printing (default: DEBUG_FULL)

   // ================================================================
   // SLOPE CALCULATION CONFIGURATION
   // ================================================================
   int    SlopeLookbackBars;

   // ════════════════════════════════════════════════════════════════
   // BAR CLOSE (bcX) CONFIGURATION
   // ════════════════════════════════════════════════════════════════
   // Formula: TS = Bias × LayerX × bcX × IndicatorX × FilterX
   // bcX checks candle close position vs target EMA, separate from LayerX
   bool          BarClose_Enabled;      // Master enable/disable for bcX check
   EBarCloseMode BarClose_Mode;         // Which EMA to check (see EBarCloseMode)
   EEmaRole      BarClose_DefaultEMA;   // EMA for BC_FIXED_EMA mode (fallback)

   // Re-entry after breakeven
   bool          AllowReEntryAfterBE;   // When true, bypass ALREADY_IN_POSITION if position is at BE

   // Post-trade cooldown
   int           MinBarsAfterClose;     // bars to wait after trade close before new entry (0 = off)

   // Spread retry cap — kill carry after N consecutive spread-blocked TE attempts (0=unlimited)
   int    MaxSpreadRetryBars;

   // EMA fan overextension filter — block TS=1 when EMA1–EMA4 gap is wide AND still expanding
   // EmaFanMaxTotalPips=25.0 is an empirically chosen starting point for M1/M5 with EMA5/13/34/89.
   // Adjust per timeframe: M15/H1 consider 40–60 pips; H4+ consider 80–120 pips.
   // JPY pairs (~3-digit): GlobalPipSize() returns the correct pip unit; no special-casing needed.
   bool   EmaFanFilterEnabled;
   double EmaFanMaxTotalPips;

   // DPI momentum deceleration filter — block TS=1 when directionally-aligned DPI histogram shrinks
   // Only activates when DpiDecelFilterEnabled=true AND Ind_Dpi_Enabled=true.
   bool   DpiDecelFilterEnabled;

   // ── PHASE B: TE-side hardening (read by SEA_TradeExecutor::EvaluateTE) ──
   bool   TE_RecheckBarClose;       // Re-confirm bar-close BC vs live bid at shift=0
   int    TE_OpenDelaySeconds;      // Defer EvaluateTE() by N sec after new bar
   int    TE_SpreadMedianTicks;     // Median spread over last N ticks (0=disabled)
};

// Global Configuration Instance
ST_Settings Settings;


//+------------------------------------------------------------------+
//| Validate BiasMode and AutoStrat compatibility                    |
//| Returns: true if combination is valid, false otherwise           |
//+------------------------------------------------------------------+
bool ValidateBiasStratCombo(EBiasMode bias, EAutoStrategy strat)
{
   switch(bias)
   {
      case BIAS_MANUAL:
         return true; // Manual mode doesn't use AutoStrat

      case BIAS_1EMA:
         return (strat == STRAT_1EMA_SLOPE);

      case BIAS_2EMA:
         return (strat == STRAT_2EMA_CROSS_EMA ||
                 strat == STRAT_2EMA_CROSS_PRICE ||
                 strat == STRAT_2EMA_POSITION);

      case BIAS_4EMA:
         return (strat == STRAT_4EMA_LAYER);

      default:
         Print("[ERROR] Unknown BiasMode: ", EnumToString(bias));
         return false;
   }
}


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


//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                 |
//+------------------------------------------------------------------+

//input group "-";
//input group "╔════════════════════════════════════════════════════════╗";
//input group "║  📖 NAVIGATION GUIDE (Scroll to find your section)     ║";
//input group "╠════════════════════════════════════════════════════════╣";
//input group "║  ✅ ZONE 2A: OPERATOR GATES & UI (always editable)      ║";
//input group "║  ⚠️  ZONE 3A: Pipeline Config (Steps 1–9)              ║";
//input group "║     └─ ZONE 3A.9: EXIT MANAGEMENT ← START HERE         ║";
//input group "╚════════════════════════════════════════════════════════╝";
input ulong     Inp_MagicNum                 = 12345;             // Magic number (trade identifier)

input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "    🎯 PRESET";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input EStrategyPreset InpPreset              = PRESET_RRM_ORG;    // Strategy preset

input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "    ✅✅ FILTERS | UI | DEBUG (works in ALL presets)";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "╔════════════════════════════════════════════════════════╗";
input group "║   � FILTER: SPREAD (GLOBAL)";
input group "╚════════════════════════════════════════════════════════╝";
input bool        Inp_UseSpread              = false;       // Spread: Enable filter
input double      Inp_MaxSpreadPips          = 3.0;         // Spread: Max (pips; ignored if UseSpread=false)
input int         Inp_MaxSpreadRetryBars     = 3;           // Spread: Kill carry after N bars of spread blocking (0=unlimited)
input group "╔════════════════════════════════════════════════════════╗";
input group "║   ⏰ FILTER: TIME (GLOBAL)";
input group "╚════════════════════════════════════════════════════════╝";
input bool        Inp_UseTime                = false;       // Session: Enable time filter
input int         Inp_StartHour              = 8;           // Session: Start hour (broker time)
input int         Inp_EndHour                = 20;          // Session: End hour (broker time)
input group "╔════════════════════════════════════════════════════════╗";
input group "║   � FILTER: NEWS (GLOBAL)";
input group "╚════════════════════════════════════════════════════════╝";
input bool        Inp_UseNews                = false;       // News: Enable news filter (CSV calendar)
input string      Inp_NewsFile               = "calendar_statement.csv"; // News: CSV filename
input int         Inp_NewsPre                = 60;          // News: Minutes before news to block entries
input int         Inp_NewsPost               = 60;          // NEws: Minutes after news to block entries
input group "╔════════════════════════════════════════════════════════╗";
input group "║   � FILTER: HTF (GLOBAL)";
input group "╚════════════════════════════════════════════════════════╝";
input bool        Inp_UseHTF                 = false;       // HTF: Enable HTF trend filter
input ENUM_TIMEFRAMES Inp_HtfPeriod          = PERIOD_H4;   // HTF: timeframe
input int         Inp_HtfEmaPeriod           = 89;          // HTF: EMA period

input group "╔════════════════════════════════════════════════════════╗";
input group "║   🎨 UI: COCKPIT PANEL";
input group "╚════════════════════════════════════════════════════════╝";
input bool        Inp_UI_ShowCockpitPanel    = true;        // UI CP: COCKPIT PANEL
input ENUM_BASE_CORNER  Inp_UI_CockpitCorner = CORNER_LEFT_UPPER; // UI CP: corner
input int         Inp_UI_CockpitX            = 30;          // UI CP: Cockpit panel X (px)
input int         Inp_UI_CockpitY            = 30;          // UI CP: Cockpit panel Y (px)
input int         Inp_UI_CockpitFontSize     = 10;          // UI CP: Cockpit panel font size
input int         Inp_UI_CockpitLineSpacingPx = 28;         // UI CP: Cockpit panel line spacing (px)
input string      Inp_UI_CockpitFont         = "Arial";     // UI CP: Cockpit panel font
input group "╔════════════════════════════════════════════════════════╗";
input group "║   🎨 UI: COCKPIT PANEL COLORS";
input group "╚════════════════════════════════════════════════════════╝";
input color       Inp_UI_clr_Header          = clrGold;       // UI CP: Header Text Color
input color       Inp_UI_clr_Value           = clrWhite;      // UI CP: Market Data Color
input color       Inp_UI_clr_Pass            = clrLimeGreen;  // UI CP: Logic PASS Color
input color       Inp_UI_clr_Fail            = clrOrangeRed;  // UI CP: Logic FAIL Color
input color       Inp_UI_clr_Disabled        = clrGray;       // UI CP: Logic DISABLED Color
input group "╔════════════════════════════════════════════════════════╗";
input group "║   🎨 UI: STATUS PANEL";
input group "╚════════════════════════════════════════════════════════╝";
input bool        Inp_UI_ShowStatusPanel     = false;       // UI SP: STATUS PANEL
input bool        Inp_UI_ManageChartIndicators = false;     // UI SP: Auto-add/remove chart indicators
input ENUM_BASE_CORNER Inp_UI_PanelCorner    = CORNER_LEFT_UPPER; // UI SP: Status panel corner
input int         Inp_UI_PanelX              = 30;          // UI SP: Status panel X (px)
input int         Inp_UI_PanelY              = 30;          // UI SP: Status panel Y (px)
input int         Inp_UI_PanelFontSize       = 10;          // UI SP: Status panel font size
input int         Inp_UI_LineSpacingPx       = 28;          // UI SP: Status panel line spacing (px)
input string      Inp_UI_PanelFont           = "Arial";     // UI SP: Status panel font
input group "╔════════════════════════════════════════════════════════╗";
input group "║   🎨 UI: SIGNAL MARKERS & COLORS";
input group "╚════════════════════════════════════════════════════════╝";
input EUIFrameMode Inp_UI_FrameMode          = UI_FRAME_NONE; // UI: Panel frame mode
input bool        Inp_DrawEntryLines         = true;        // UI: Draw entry marker lines
input bool        Inp_DrawTradeLines         = true;        // UI: Draw trade management lines
input bool        Inp_UI_UseCustomColors     = true;        // UI: Use custom panel colors
input color       Inp_UI_FontColor           = clrYellow;   // UI: font color
input int         Inp_UI_PanelBgAlpha        = 110;         // UI: Panel background alpha (0..255)
input int         Inp_UI_FramePadPx          = 6;           // UI: Panel padding (px)

input group "╔════════════════════════════════════════════════════════╗";
input group "║   🔍 DEBUG: DIAGNOSTICS";
input group "╚════════════════════════════════════════════════════════╝";
input EDebugLevel Inp_DebugLevel             = DEBUG_SILENT; // Debug: Level
input bool        Inp_DebugFlow              = true;        // Debug: Print OnInit/OnTick/OnDeinit flow ... have to be true with DEBUG_SIGNALS_ONLY
input bool        Inp_PrintEffectiveConfig   = true;        // Debug: Print effective config on init
input group "╔════════════════════════════════════════════════════════╗";
input group "║   🔍 DEBUG: DIAGNOSTICS: STATISTICS";
input group "╚════════════════════════════════════════════════════════╝";
input bool        Inp_Stats_TrackRejections  = true;        // Stats: Track rejection counts
input bool        Inp_Stats_TrackPasses      = true;        // Stats: Track pass counts
input bool        Inp_Stats_FullEvaluation   = true;        // Stats: Evaluate ALL indicators per bar
//input string    Inp_Stats_Info1            = "FullEvaluation=false: waterfall (stop at first fail)";
//input string    Inp_Stats_Info2            = "FullEvaluation=true: evaluate all, identify true bottlenecks";
input group "╔════════════════════════════════════════════════════════╗";
input group "║   🔬 DEBUG: TARGETED BAR EVALUATION";
input group "╚════════════════════════════════════════════════════════╝";
input EDebugLevel Inp_DebugEvalMode          = DEBUG_FULL;  // Forced eval: debug level to apply
input datetime    Inp_DebugEvalFrom          = 0;           // Debug window: force eval print from (0=off)
input datetime    Inp_DebugEvalTo            = 0;           // Debug window: force eval print to (0=off; use with From)
input datetime    Inp_DebugEvalAt            = 0;           // Debug pinpoint: force eval at exact bar time (0=off)
input group "╔════════════════════════════════════════════════════════╗";
input group "║   🔍 DEBUG: REPORTING";
input group "╚════════════════════════════════════════════════════════╝";
input bool        Inp_ExportCSV              = false;       // Report: Export CSV reporting
input bool        Inp_ExportUseCommonFiles   = false;       // Report: Use terminal Common Files folder

input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "    📐 PRESET: MA";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "╔════════════════════════════════════════════════════════╗";
input group "║   🛑 MT5 Moving Average Benchmark (PRESET_MA)";
input group "╚════════════════════════════════════════════════════════╝";
input double      Inp_MA_MaximumRiskPct      = 0.02;        // MA Max risk (%)
input double      Inp_MA_DecreaseFactor      = 3.0;         // MA Lot decrease factor
input int         Inp_MA_Period              = 12;          // MA period
input int         Inp_MA_Shift               = 6;           // MA shift

input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "    📐 PRESET: FPM";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 FPM: (TP) Take Profit Settings";
input group "╚════════════════════════════════════════════════════════╝";
input ETPMode     Inp_FPM_TPMode             = TP_MODE_RR;     // FPM TP mode: RR=derive TP from SL distance (recommended); FIXED_PIPS=TF-based cheat sheet pips
input double      Inp_FPM_RRRatio            = 1.5;            // FPM R:R ratio (used with TP_MODE_RR, e.g. 1.5, 2.0, 3.0)
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 FPM: (SL) Stop Loss Settings";
input group "╚════════════════════════════════════════════════════════╝";
input ESLMode     Inp_FPM_SLMode             = SL_MODE_SWING;  // FPM SL mode: SWING (recent high/low) or FIXED_PIPS
input int         Inp_FPM_SwingLookback      = 20;             // FPM SL swing lookback bars — advisory; PRESET_FPM uses GetFPMSwingLookback() internally
input double      Inp_FPM_SLFixedPips        = 15.0;           // FPM SL fixed distance in pips (SL_MODE_FIXED_PIPS only)
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 FPM: (TS) Trailing Stop (Optional)";
input group "╚════════════════════════════════════════════════════════╝";
input bool        Inp_FPM_UseTrailing        = true;           // FPM: Enable optional trailing stop
input double      Inp_FPM_TrailDistancePips  = 15.0;           // FPM: Trailing distance in pips (15 = cheat sheet default)
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 FPM: MACD Settings";
input group "╚════════════════════════════════════════════════════════╝";
input int         Inp_FPM_MacdFast           = 12;             // FPM MACD Fast period
input int         Inp_FPM_MacdSlow           = 26;             // FPM MACD Slow period
input int         Inp_FPM_MacdSig            = 9;              // FPM MACD Signal period
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 FPM: PSAR Settings";
input group "╚════════════════════════════════════════════════════════╝";
input double      Inp_FPM_PsarStep           = 0.02;           // FPM PSAR Step
input double      Inp_FPM_PsarMax            = 0.2;            // FPM PSAR Max
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📊 FPM: SMA Convergence";
input group "╚════════════════════════════════════════════════════════╝";
input bool        Inp_Ind_SmaConverge_Enabled = false;         // FPM [SmaConv] Enable SMA convergence vote (FPM Condition 4)

input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "    📐 PRESET: RRM";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 RRM: (RR) Risk Reward";
input group "╚════════════════════════════════════════════════════════╝";
input ETPMode     Inp_RRM_TPMode             = TP_MODE_RR;     // RRM TP mode
input double      Inp_RRM_RRRatio            = 1.0;            // RRM R:R ratio (used with TP_MODE_RR)
input group "╔════════════════════════════════════════════════════════╗";
input group "║   🛑 RRM: (BE) Breakeven (% Progress)";
input group "╚════════════════════════════════════════════════════════╝";
input double      Inp_RRM_BE_ProgressPct     = 10.0;           // BE at % to TP
input double      Inp_RRM_BE_RMultiple       = 1.0;            // BE at R-multiple
// input string   Inp_RRM_BE_Buffer_Note     = "BE buffer auto-set by timeframe (M15=5, H1=10, H4=20 pips)";
// input string   Inp_RRM_BE_Example         = "Example: SL=10, TP=30 (3:1), BE@33% → triggers at +10 pips; SL locks at entry + TF-cushion";
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 RRM: Layer Filter (sub-markets)";
input group "╚════════════════════════════════════════════════════════╝";
input bool        Inp_RRM_AllowWeak          = true;           // RRM: Allow WEAK   trades (L1 EMA1/EMA2)
input bool        Inp_RRM_AllowMedium        = true;           // RRM: Allow MEDIUM trades (L2 EMA2/EMA3)
input bool        Inp_RRM_AllowStrong        = true;           // RRM: Allow STRONG trades (L3 EMA3/EMA4, TRENDING only)
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 RRM: Layer Pullback-Recovery Detection";
input group "╚════════════════════════════════════════════════════════╝";
input bool        Inp_LayerPullbackEnabled   = false;          // Layer PB: Enable pullback-recovery detection
input int         Inp_LayerBaselineLookback  = 10;             // Layer PB: Baseline slope lookback (bars, recommended 3+)
input double      Inp_LayerPullbackRatio     = 0.5;            // Layer PB: Pullback threshold ratio (min 0.1)
input double      Inp_LayerRecoveryRatio     = 0.3;            // Layer PB: Recovery threshold ratio (min 0.1)
input double      Inp_LayerFlatRatio         = 0.1;            // Layer PB: Flat threshold ratio (min 0.05; independent of pullback ratio)
input bool        Inp_LayerAllowReversalPullback = true;       // Layer PB: Count slope reversal as pullback
input group "╔════════════════════════════════════════════════════════╗";
input group "║   🔧 RRM: (DP) Drawdown Protection";
input group "╚════════════════════════════════════════════════════════╝";
input bool        Inp_RRM_EnableDrawdownProtection = false;    // RRM: Enable drawdown protection
input int         Inp_RRM_MaxConsecutiveLosses  = 5;           // RRM: Max consecutive losses before pause
input int         Inp_RRM_MaxTradesPerDay       = 15;          // RRM: Max trades per day
input double      Inp_RRM_MaxDailyDrawdownPct   = 3.0;         // RRM: Max daily drawdown %
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 RRM: (SL) Stop Loss";
input group "╚════════════════════════════════════════════════════════╝";
input ESLMode    Inp_RRM_SLMode                 = SL_MODE_SWING; // RRM SL placement mode
input int        Inp_RRM_SwingLookback          = 20;          // RRM Swing lookback bars (used with SL_MODE_SWING)
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 RRM: (TS) Trailing Stop";
input group "╚════════════════════════════════════════════════════════╝";
input ETrailingMode Inp_RRM_TrailMode           = TRAIL_PSAR;  // RRM Trailing stop mode
input group "╔════════════════════════════════════════════════════════╗";
input group "║   🛑 RRM: (TS) PSAR Trailing Stop";
input group "╚════════════════════════════════════════════════════════╝";
input EPsarTrailCushionMode Inp_PSAR_TrailCushionMode = PSAR_CUSHION_PIPS; // PSAR trail cushion mode
input bool        Inp_RRM_TrailStartsAfterBE    = false;       // Start trailing only after BE is reached
input bool        Inp_RRM_FreezeTrailOnFlip     = true;        // Freeze trail on PSAR flip
input int         Inp_PSAR_TrailDelay           = 1;           // PSAR trailing delay
input int         Inp_RRM_TrailPsarShiftDelay   = 1;           // PSAR shift delay
// input string   Inp_PSAR_TrailCushion_Note    = "PSAR trail cushion auto-set by timeframe (M15=3, H1=7, H4=10 pips)"
// input string   Inp_RRM_Trail_Info            = "RRM trailing: PSAR-based with bar shift delay for flip stability";
input group "╔════════════════════════════════════════════════════════╗";
input group "║   🔧 RRM: (Pullback)";
input group "╚════════════════════════════════════════════════════════╝";
input bool        Inp_Gate_RequireRecoveryMomentum = false;    // RRM Gate (CUSTOM; presets override)
input int         Inp_RRM_Lookback           = 5;              // RRM Lookback (CUSTOM; presets override)
input double      Inp_RRM_MinDivPips         = 0.5;            // RRM MinDivPips (CUSTOM; presets override)
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 RRM: Indicators — Enable/Disable";
input group "╚════════════════════════════════════════════════════════╝";
input bool        Inp_RRM_Use_Adx            = false;          // RRM: ADX vote enabled
input bool        Inp_RRM_Use_Bb             = false;          // RRM: Bollinger Bands vote enabled
input bool        Inp_RRM_Use_CandleBody     = true;           // RRM: Candle body vote enabled
input bool        Inp_RRM_Use_Cci            = false;          // RRM: CCI vote enabled
input bool        Inp_RRM_Use_CI             = true;          // RRM: CI vote ranging market filter
input bool        Inp_RRM_Use_Macd           = true;           // RRM: MACD vote enabled
input bool        Inp_RRM_Use_Mfi            = false;          // RRM: MFI vote enabled
input bool        Inp_RRM_Use_Psar           = true;           // RRM: PSAR vote enabled
input bool        Inp_RRM_Use_Rsi            = false;          // RRM: RSI vote enabled
input bool        Inp_RRM_Use_Stoch          = false;          // RRM: Stochastic vote enabled
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 RRM: ADX Settings";
input group "╚════════════════════════════════════════════════════════╝";
input int         Inp_RRM_AdxPeriod          = 14;             // RRM ADX Period
input double      Inp_RRM_AdxThreshold       = 20.0;           // RRM ADX Threshold
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 RRM: CCI Settings";
input group "╚════════════════════════════════════════════════════════╝";
input ECciMode    Inp_RRM_CciMode            = CCI_TREND_ZERO; // RRM CCI Mode
input int         Inp_RRM_CciPeriod          = 14;             // RRM CCI Period
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 RRM: CI Settings";
input group "╚════════════════════════════════════════════════════════╝";
input int         Inp_RRM_CiPeriod           = 14;             // RRM CI Period
input double      Inp_RRM_CiRangingThreshold = 61.8;           // RRM CI Ranging Threshold
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 RRM: EMA Periods";
input group "╚════════════════════════════════════════════════════════╝";
input int         Inp_RRM_Ema1Period         = 5;              // RRM EMA1 Period (default: 5)
input int         Inp_RRM_Ema2Period         = 13;             // RRM EMA2 Period (default: 13)
input int         Inp_RRM_Ema3Period         = 34;             // RRM EMA3 Period (default: 34)
input int         Inp_RRM_Ema4Period         = 89;             // RRM EMA4 Period (default: 89)
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 RRM: MACD Settings";
input group "╚════════════════════════════════════════════════════════╝";
input EMacdVoteMode Inp_RRM_MacdMode         = MACD_ZERO_AND_HIST; // RRM MACD vote mode
input bool        Inp_RRM_MacdSlope          = true;           // RRM MACD require slope
input bool        Inp_RRM_MacdDiv            = true;           // RRM MACD require divergence
input int         Inp_RRM_MacdFast           = 12;             // RRM MACD Fast period ORG 12
input int         Inp_RRM_MacdSlow           = 26;             // RRM MACD Slow period ORG 26
input int         Inp_RRM_MacdSig            = 9;              // RRM MACD Signal period ORG 9
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 RRM: PSAR Settings";
input group "╚════════════════════════════════════════════════════════╝";
input double      Inp_RRM_PsarStep           = 0.05;           // RRM PSAR Step
input double      Inp_RRM_PsarMax            = 0.5;            // RRM PSAR Max
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 RRM: RSI Settings";
input group "╚════════════════════════════════════════════════════════╝";
input ERsiMode    Inp_RRM_RsiMode            = RSI_TREND_ABOVE_50; // RRM RSI Mode
input int         Inp_RRM_RsiPeriod          = 14;             // RRM RSI Period
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 RRM: EMA Fan & DPI Filters";
input group "╚════════════════════════════════════════════════════════╝";
input bool        Inp_EmaFanFilterEnabled   = false;           // RRM: Block entry on overextended EMA fan
input bool        Inp_DpiDecelFilterEnabled = false;           // RRM: Block entry on DPI histogram deceleration
input double      Inp_EmaFanMaxTotalPips    = 0.0;             // RRM: EMA1–EMA4 max total gap pips (0=disabled; M1/M5 start: 25.0)

input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "    📐 PRESET: RRM_ORG";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 RRM_ORG: DPI v31 Settings";
input group "╚════════════════════════════════════════════════════════╝";
input bool        Inp_Ind_Dpi_Enabled              = true;        // DPI: Enable DPI vote in TS equation
input int         Inp_Ind_Dpi_Weight               = 1;           // DPI: Vote weight
input int         Inp_RRM_ORG_MACD_Fast            = 8;           // RRM_ORG: DPI MACD fast EMA period
input int         Inp_RRM_ORG_MACD_Slow            = 13;          // RRM_ORG: DPI MACD slow EMA period
input int         Inp_RRM_ORG_DPI_RedSignalType    = 3;           // DPI: Red line type (1=EMA_A 2=EMA_B 3=EMA_C 4=EMA_D 5=Double)
input int         Inp_RRM_ORG_DPI_RedEMA_A         = 5;           // DPI: Red EMA period A (type 1)
input int         Inp_RRM_ORG_DPI_RedEMA_B         = 8;           // DPI: Red EMA period B (type 2)
input int         Inp_RRM_ORG_DPI_RedEMA_C         = 13;          // DPI: Red EMA period C (type 3, default)
input int         Inp_RRM_ORG_DPI_RedEMA_D         = 21;          // DPI: Red EMA period D (type 4)
input int         Inp_RRM_ORG_DPI_DoubleSmoothFirst  = 5;         // DPI: Double-smooth first EMA
input int         Inp_RRM_ORG_DPI_DoubleSmoothSecond = 8;         // DPI: Double-smooth second EMA
input bool        Inp_RRM_ORG_DPI_UseCCIReset      = true;        // DPI: Enable CCI trend filter
input int         Inp_RRM_ORG_DPI_CCI_Period       = 13;          // DPI: CCI period
input ENUM_APPLIED_PRICE Inp_RRM_ORG_DPI_CCI_Price = PRICE_TYPICAL; // DPI: CCI applied price
input bool        Inp_RRM_ORG_DPI_UseGreenHist     = false;       // DPI: Enable GREEN momentum overlay (false=v29 behaviour)
input double      Inp_DPI_HistMomentumThreshold    = 0.0001;      // DPI: Histogram momentum threshold (CCI-delta units)
input int         Inp_DPI_HistDecelLookback        = 3;           // DPI: Deceleration lookback (bars)
input bool        Inp_DPI_HistTrackingEnabled      = false;       // DPI: Enable histogram tracking

input group "╔════════════════════════════════════════════════════════╗";
input group "║   📐 RRM_ORG: Phase A Quality Gates (TS=1 / TE=1)";
input group "╚════════════════════════════════════════════════════════╝";
// ── TS-side gates (signal evaluation, shift=1) ────────────────────────────
input bool        Inp_RRM_ORG_ForceDpiOn          = true;         // RRM_ORG: Force DPI voter ON (matches reference methodology)
input bool        Inp_RRM_ORG_EmaFanFilter        = true;         // RRM_ORG: Block entry on overextended EMA fan
input double      Inp_RRM_ORG_EmaFan_M5Pips       = 25.0;         // RRM_ORG: Fan max pips on M1–M5
input double      Inp_RRM_ORG_EmaFan_M30Pips      = 40.0;         // RRM_ORG: Fan max pips on M6–M30
input double      Inp_RRM_ORG_EmaFan_H1Pips       = 60.0;         // RRM_ORG: Fan max pips on H1
input double      Inp_RRM_ORG_EmaFan_H4Pips       = 100.0;        // RRM_ORG: Fan max pips on H4
input double      Inp_RRM_ORG_EmaFan_DailyPips    = 180.0;        // RRM_ORG: Fan max pips on D1+

input int         Inp_RRM_ORG_PhaseConfirmM5      = 1;            // RRM_ORG:1 MinPhaseConfirmBars on M1–M5
input int         Inp_RRM_ORG_PhaseConfirmM30     = 1;            // RRM_ORG:2 MinPhaseConfirmBars on M6–M30
input int         Inp_RRM_ORG_PhaseConfirmH1plus  = 1;            // RRM_ORG:3 MinPhaseConfirmBars on H1 and above

input bool        Inp_RRM_ORG_RequireRecoveryIntraday = true;     // RRM_ORG: Require recovery momentum on M15-and-down
input double      Inp_RRM_ORG_JpyGateMultiplier   = 1.3;          // RRM_ORG: Recovery+EmaDiv gate scale for JPY pairs (1.0=disabled)
input bool        Inp_RRM_ORG_HtfFilter           = true;         // RRM_ORG: Force HTF trend filter ON
input int         Inp_RRM_ORG_HtfEmaPeriod        = 89;           // RRM_ORG: HTF EMA period (0=use Inp_HtfEmaPeriod)
input bool        Inp_RRM_ORG_DpiDecelFilter      = true;         // RRM_ORG: Block entry on DPI histogram deceleration
input bool        Inp_RRM_ORG_ForceDDProtection   = true;         // RRM_ORG: Force drawdown protection ON
input int         Inp_RRM_ORG_DDMaxConsecLosses   = 4;            // RRM_ORG: Override max consecutive losses (0=use Inp_RRM_*)
input double      Inp_RRM_ORG_DDMaxDailyPct       = 2.0;          // RRM_ORG: Override max daily DD % (0=use Inp_RRM_*)

// ── TE-side gates (execution evaluation, shift=0) ─────────────────────────
input bool        Inp_RRM_ORG_TE_RecheckBarClose  = true;         // RRM_ORG: At TE, re-confirm shift=1 BC vs current bid
input int         Inp_RRM_ORG_TE_OpenDelaySecsM5  = 10;           // RRM_ORG: Defer TE by N sec at new bar (M1–M5)
input int         Inp_RRM_ORG_TE_OpenDelaySecsM30 = 5;            // RRM_ORG: Defer TE by N sec at new bar (M6–M30)
input int         Inp_RRM_ORG_TE_OpenDelaySecsHi  = 0;            // RRM_ORG: Defer TE by N sec at new bar (H1+)
input int         Inp_RRM_ORG_TE_SpreadMedianTicks = 8;           // RRM_ORG: Median spread over last N ticks (0=disabled)

input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "    ⚠️  PRESETS OVERRIDES! (Step1-5)";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "╔════════════════════════════════════════════════════════╗";
input group "║   🔧 STEP 1: Bias (Major Trend Direction)";
input group "╚════════════════════════════════════════════════════════╝";
input EBiasMode   Inp_BiasMode                  = BIAS_2EMA;   // Bias: Mode: Manual, 2-EMA, or 4-EMA (CUSTOM; presets override)
input EManualSide Inp_ManualSide                = SIDE_BOTH;   // Bias Side (CUSTOM; presets override)
input bool        Inp_BiasEnabled               = true;        // Bias Enabled (CUSTOM; presets override)
input int         Inp_BiasFastID                = 2;           // Bias Fast ID (CUSTOM; presets override)
input int         Inp_BiasSlowID                = 3;           // Bias Slow ID (CUSTOM; presets override)
input group "╔════════════════════════════════════════════════════════╗";
input group "║   🔧 STEP 2: MA | EMA                                 ";
input group "╚════════════════════════════════════════════════════════╝";
input EMaMethod   Inp_MaType                    = METHOD_EMA;  // MA (CUSTOM; presets override)
input int         Inp_MaHorShift                = 1;           // MA Hor Shift (CUSTOM; presets override)
input int         Inp_MaVerShift                = 1;           // MA Ver Shift (CUSTOM; presets override)
input int         InpEma1Period                 = 5;           // EMA1 Period (CUSTOM; presets override)
input int         InpEma2Period                 = 13;          // EMA2 Period (CUSTOM; presets override)
input int         InpEma3Period                 = 34;          // EMA3 Period (CUSTOM; presets override)
input int         InpEma4Period                 = 89;          // Ema4 Period (CUSTOM; presets override)
input group "╔════════════════════════════════════════════════════════╗";
input group "║   🔧 STEP 3: Entry Signal (Timing Strategy)";
input group "╚════════════════════════════════════════════════════════╝";
input EAutoStrategy  Inp_AutoStrat              = STRAT_2EMA_POSITION;  // Entry AutoStrat (CUSTOM; presets override)
input double      Inp_LayerTolerance            = 0.01;        // Entry Layer Tolerance (DEPRECATED v1.04+: KISS refactor removed wick-touch tolerance; see EvaluateLayerX/EvaluateBcX)
input bool        Inp_RRM_EnableInCustom        = false;       // Entry RRM Enable In Custom (CUSTOM only)
input bool        Inp_CloseOnReverse            = false;       // Entry Close On REverse (CUSTOM; presets may override)
input group "╔════════════════════════════════════════════════════════╗";
input group "║   🔧 STEP 4: Bar Close (bcX - Candle Close Beyond EMA)";
input group "╚════════════════════════════════════════════════════════╝";
input EBarCloseMode  Inp_BarClose_Mode          = BC_LAYER_AWARE; // [bcX] Mode: DISABLED/FIXED_EMA/LAYER_AWARE/BIAS_FAST (CUSTOM; presets override)
input EEmaRole    Inp_BarClose_DefaultEMA       = ROLE_EMA1;      // [bcX] EMA to check in FIXED mode (CUSTOM; presets override)
input bool        Inp_BarClose_Enabled          = true;           // [bcX] Enable bar close confirmation (CUSTOM; presets override)
input group "╔════════════════════════════════════════════════════════╗";
input group "║   🔧 STEP 5: Voting Weight Configuration";
input group "╚════════════════════════════════════════════════════════╝";
input bool        Inp_VoteMode_All           = true;              // VOTE All (CUSTOM; presets override)
input int         Inp_Ind_Adx_Weight         = 1;                 // [ADX] Vote weight
input int         Inp_Ind_Atr_Weight         = 1;                 // [ATR] Vote weight
input int         Inp_Ind_Bb_Weight          = 1;                 // [BB] Vote weight
input int         Inp_Ind_CandleBody_Weight  = 1;                 // [CandleBody] Vote weight
input int         Inp_Ind_Cci_Weight         = 1;                 // [CCI] Vote weight
input int         Inp_Ind_CI_Weight          = 1;                 // [CI] Vote weight
input int         Inp_Ind_Macd_Weight        = 1;                 // [MACD] Vote weight
input int         Inp_Ind_Mfi_Weight         = 1;                 // [MFI] Vote weight
input int         Inp_Ind_P123_Weight        = 1;                 // [P123] Vote weight
input int         Inp_Ind_Psar_Weight        = 1;                 // [PSAR] Vote weight
input int         Inp_Ind_Ross_Weight        = 1;                 // [Ross] Vote weight
input int         Inp_Ind_Rsi_Weight         = 1;                 // [RSI] Vote weight
input int         Inp_Ind_SmaConverge_Weight = 1;                 // [SmaConv] Vote weight
input int         Inp_Ind_Sto_Weight         = 1;                 // [Sto] Vote weight
input int         Inp_Ind_VRC_Weight         = 1;                 // [VRC] Vote weight

input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "    ⚠️  INDICATORS";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📊 ADX (Average Directional Index - Strength of Market Trend)";
input group "╚════════════════════════════════════════════════════════╝";
input bool        Inp_Ind_Adx_Enabled           = false;          // [ADX] Enable ADX vote
input EADXMode    Inp_Ind_Adx_Mode              = ADX_MODE_STATIC; // [ADX] Mode
input int         Inp_Ind_Adx_Period            = 14;             // [ADX] Period
input int         Inp_Ind_Adx_Threshold         = 20;             // [ADX] Threshold (Static mode)
input double      Inp_Ind_Adx_Percentile        = 50.0;           // [ADX] Percentile
input int         Inp_Ind_Adx_Lookback          = 100;            // [ADX] Lookback bars
input double      Inp_Ind_Adx_Thr_Accum         = 12.0;           // [ADX] Accumulation
input double      Inp_Ind_Adx_Thr_Trending      = 25.0;           // [ADX] Trending
input double      Inp_Ind_Adx_Thr_Distrib       = 18.0;           // [ADX] Distribution
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📊 ATR (Average True Range - Market Volatility - Non-directional)";
input group "╚════════════════════════════════════════════════════════╝";
input bool        Inp_Ind_Atr_Enabled           = false;          // [ATR] Enable ATR vote
input int         Inp_Ind_Atr_Period            = 14;             // [ATR] Period
input double      Inp_Ind_Atr_VoteMinPips       = 5.0;            // [ATR] Voting min pips
input double      Inp_Ind_Atr_VoteMaxPips       = 50.0;           // [ATR] Voting max pips
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📊 BB (Bollinger Bands - Market Volatility and Over bought/sold Levels)";
input group "╚════════════════════════════════════════════════════════╝";
input bool        Inp_Ind_Bb_Enabled            = false;          // [BB] Enable Bollinger Bands vote
input EBbMode     Inp_Ind_Bb_Mode               = BB_TREND_FOLLOW; // [BB] Mode
input int         Inp_Ind_Bb_Period             = 20;             // [BB] Period
input double      Inp_Ind_Bb_Dev                = 2.0;            // [BB] Deviation
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📊 CBody (Candle Body - Votes Against Overextended Candles (news/spikes))";
input group "╚════════════════════════════════════════════════════════╝";
input bool        Inp_Ind_CandleBody_Enabled    = false;          // [CandleBody] Enable voting indicator
input bool        Inp_Ind_CandleBody_RequireDirection = true;     // [CandleBody] Require signal bar to close in trade direction
input int         Inp_Ind_CandleBody_AvgPeriod  = 10;             // [CandleBody] Average body period
input double      Inp_Ind_CandleBody_MaxMult    = 3.0;            // [CandleBody] Max body multiplier
input int         Inp_Ind_CandleBody_CheckBars  = 1;              // [CandleBody] Bars to check
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📊 CCI (Commodity Channel Index - Momentum Oscilator)";
input group "╚════════════════════════════════════════════════════════╝";
input bool        Inp_Ind_Cci_Enabled        = false;             // [CCI] Enable CCI vote
input ECciMode    Inp_Ind_Cci_Mode           = CCI_TREND_ZERO;    // [CCI] Mode
input int         Inp_Ind_Cci_Period         = 14;                // [CCI] Period
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📊 CI (Choppiness Index - Block Trades in Ranging Market)";
input group "╚════════════════════════════════════════════════════════╝";
input bool        Inp_Ind_CI_Enabled         = false;             // [CI] Enable ranging market filter
input int         Inp_CI_Period              = 14;                // [CI] Calculation period
input double      Inp_CI_RangingThreshold    = 61.8;              // [CI] Ranging threshold (>= this value = reject)
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📊 MACD (Moving Average Convergence Divergence - Trend-Following Momentum)";
input group "╚════════════════════════════════════════════════════════╝";
input bool        Inp_Ind_Macd_Enabled       = false;             // [MACD] Enable MACD vote
input EMacdVoteMode  Inp_MacdVoteMode        = MACD_ZERO_AND_HIST; // [MACD] base mode
input bool        Inp_MacdRequireSlope       = false;             // [MACD] Require MACD rising/falling
input bool        Inp_MacdRequireDivergence  = false;             // [MACD] Require price/MACD divergence
input bool        Inp_MacdRequireHook        = false;             // [MACD] Require histogram flip
input int         Inp_P_MacdFast             = 8;                 // [MACD] Fast EMA period
input int         Inp_P_MacdSlow             = 13;                // [MACD] Slow EMA period
input int         Inp_P_MacdSig              = 5;                 // [MACD] Signal SMA period
input int         Inp_MacdFreshBars          = 3;                 // [MACD] Fresh signal validity
input double      Inp_MacdSlopeMin           = 0.000001;          // [MACD] Min slope change per bar
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📊 MFI (Money Flow Index - Oscillator Buying Selling Pressure)";
input group "╚════════════════════════════════════════════════════════╝";
input bool        Inp_Ind_Mfi_Enabled        = false;             // [MFI] Enable MFI vote
input EMfiMode    Inp_Ind_Mfi_Mode           = MFI_ZONE_FILTER;   // [MFI] Mode
input int         Inp_Ind_Mfi_Period         = 14;                // [MFI] Period
input double      Inp_Ind_Mfi_Level          = 50.0;              // [MFI] Threshold/level
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📊 P123 (Mark Crisp 1-2-3 fractal breakout pattern (see Ross Hook))";
input group "╚════════════════════════════════════════════════════════╝";
input bool        Inp_Ind_P123_Enabled       = false;             // [P123] Enable 1-2-3 pattern vote
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📊 PSAR (Parabolic Stop and Reverse - Trend-Following Indicator)";
input group "╚════════════════════════════════════════════════════════╝";
input bool        Inp_Ind_Psar_Enabled       = true;              // [PSAR] Enable PSAR vote
input double      Inp_Ind_Psar_Step          = 0.05;              // [PSAR] Step
input double      Inp_Ind_Psar_Max           = 0.5;               // [PSAR] Maximum
input int         Inp_Vote_PsarFlipDelay     = 10;                // [PSAR] Flip timer: -1=persistent, 0=flip bar, 1-10=countdown
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📊 Ross Hook (Trend Momentum (see to P123))";
input group "╚════════════════════════════════════════════════════════╝";
input bool        Inp_Ind_Ross_Enabled       = false;             // [Ross] Enable Ross hook vote
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📊 RSI (Relative Strength Index - Monentum Oscilator)";
input group "╚════════════════════════════════════════════════════════╝";
input bool        Inp_Ind_Rsi_Enabled        = false;             // [RSI] Enable RSI vote
input ERsiMode    Inp_Ind_Rsi_Mode           = RSI_FILTER_EXTREME; // [RSI] Mode
input int         Inp_Ind_Rsi_Period         = 14;                // [RSI] Period
input double      Inp_Ind_Rsi_OB             = 70.0;              // [RSI] Overbought level
input double      Inp_Ind_Rsi_OS             = 30.0;              // [RSI] Oversold level
input group "╔════════════════════════════=═══════════════════════════╗";
input group "║   📊 STO (Stochastic Oscillator - Momentum Potential Market Reversals)";
input group "╚════════════════════════════════════════════════════════╝";
input bool        Inp_Ind_Sto_Enabled        = false;             // [Sto] Enable Stochastic vote
input EStochMode  Inp_Ind_Sto_Mode           = STO_ZONE_FILTER;   // [Sto] Mode
input int         Inp_Ind_Sto_K              = 5;                 // [Sto] %K period
input int         Inp_Ind_Sto_D              = 3;                 // [Sto] %D period
input int         Inp_Ind_Sto_Slow           = 3;                 // [Sto] Slowing
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📊 VRC (Volatility Regime Classifier - Reject Trades in Low Volatility (quiet/choppy markets))";
input group "╚════════════════════════════════════════════════════════╝";
input bool        Inp_Ind_VRC_Enabled        = false;             // [VRC] Enable volatility regime filter
input int         Inp_Ind_VRC_ATR_Period     = 14;                // [VRC] ATR period
input int         Inp_Ind_VRC_Lookback       = 100;               // [VRC] Lookback bars for percentile
input double      Inp_Ind_VRC_LowThreshold   = 33.0;              // [VRC] Low volatility threshold (percentile)

input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "    🔧 PAIR SETTINGS (Type | Spread)";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "╔════════════════════════════════════════════════════════╗";
input group "║   🔧 Pair Type Detection";
input group "╚════════════════════════════════════════════════════════╝";
// input string   Inp_Adaptive_PairInfo      = "AUTO: EURUSD/GBPUSD/USDJPY=MAJOR; XAUUSD/GOLD=GOLD; BTC/ETH=CRYPTO; TRY/ZAR/MXN=EXOTIC; others=MINOR";
input EPairType   Inp_Adaptive_PairType      = PAIR_TYPE_AUTO;    // Pair type (AUTO detects from symbol name)
input group "╔════════════════════════════════════════════════════════╗";
input group "║   🔧 Max Spread by Pair Type (pips)";
input group "╚════════════════════════════════════════════════════════╝";
input double      Inp_Adaptive_Spread_Major  = 2.0;               // Max spread for major pairs (pips)
input double      Inp_Adaptive_Spread_Minor  = 4.0;               // Max spread for minor pairs (pips)
input double      Inp_Adaptive_Spread_Exotic = 10.0;              // Max spread for exotic pairs (pips)
input double      Inp_Adaptive_Spread_Gold   = 5.0;               // Max spread for gold/XAU (pips)
input double      Inp_Adaptive_Spread_Crypto = 50.0;              // Max spread for crypto (pips)
// input string   Inp_Adaptive_Note1         = "📝 Note: SL/TP cushions auto-adjust by timeframe (no input needed)";
// input string   Inp_Adaptive_Note2         = "📝 M15=5 pips, H1=10 pips, H4=20 pips (see GetTFBasedCushion)";

input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "    🎯 TRADE MANAGEMENT";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "╔════════════════════════════════════════════════════════╗";
input group "║   💰 (RM) Risk Management (GLOBAL)";
input group "╚════════════════════════════════════════════════════════╝";
input double      Inp_RiskPercent            = 2.0;               // Risk per trade (%)
input int         Inp_MaxOpenTrades          = 4;                 // Max concurrent trades (0 = unlimited)
input double      Inp_MaxTotalRisk           = 6.0;               // Max total active risk (%; 0 = unlimited)
input double      Inp_MarginUsageLimit       = 80.0;              // Max % of free margin per trade (0 = use 100%)
input double      Inp_MinMarginLevel         = 100.0;             // Min margin level (%) required to allow new entries (0 = disabled)
input double      Inp_EmergencyMarginLevel   = 80.0;              // Emergency margin level (%) to force-close worst position (0 = disabled)
// input string   Inp_Step9_Ref1             = "Risk per trade applies to all presets unless overridden by Admin Override";
// input string   Inp_Step9_Ref2             = "To adjust exits under a strict preset: use PRESET_CUSTOM mode";

input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "    🎯 STRATEGY SETTINGS (PRESET_CUSTOM Only)";
input group "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓";
input group "╔════════════════════════════════════════════════════════╗";
input group "║   🎯 EXIT PROFILES";
input group "╚════════════════════════════════════════════════════════╝";
input EExitProfile   Inp_ExitProfile         = EXIT_PROFILE_NONE; // Exit profile selector
// input string   Inp_Exit_Zone_Info1        = "Active for: PRESET_TEST & PRESET_CUSTOM (direct input control)";
// input string   Inp_Exit_Zone_Info2        = "Other presets override exits with strategy-optimized values";
// input string   Inp_ExitProfile_Info       = "RRM: Swing-based SL, PSAR trail, no ATR multipliers";
input group "╔════════════════════════════════════════════════════════╗";
input group "║   🛑 (SL) STOP LOSS (CUSTOM only)";
input group "╚════════════════════════════════════════════════════════╝";
input ESLMode     Inp_SLMode                 = SL_MODE_SWING;     // SL calculation method
// input string   Inp_SL_Help1               = "FIXED_PIPS: Simple pip distance  |  SWING: Recent structure high/low";
// input string   Inp_SL_Help2               = "PSAR_DOT: PSAR level  |  PERCENT: % of price  |  FRACTAL: Bill Williams";
input double      Inp_SL_FixedPips           = 20.0;              // SL distance (pips; for SL_MODE_FIXED_PIPS)
input double      Inp_SL_MinPips             = 3.0;               // Minimum SL distance in pips (0 = no user floor, broker minimum still applies)
input bool        Inp_SL_WidenToMinimum      = false;             // If true, widen SL to meet minimum distance; if false, block trade entry
// input string   Inp_SL_TFCushion_Note      = "PSAR/Swing cushions auto-set by timeframe (M15=5, H1=10, H4=20 pips)";
input int         Inp_SwingLookback          = 20;                // Swing lookback (bars; for SL_MODE_SWING)
input double      Inp_SLPercent              = 0.5;               // SL as % of entry
input group "╔════════════════════════════════════════════════════════╗";
input group "║   🛑 (SL) STOP LOSS FRACTAL: used with SL_FRACTAL & SL_PSAR_DOT";
input group "╚════════════════════════════════════════════════════════╝";
input int         Inp_FractalPeriod          = 5;                 // Fractal period for SL/TP
input int         Inp_TPFractalOffset        = 1;                 // Fractal offset for TP
input group "╔════════════════════════════════════════════════════════╗";
input group "║   🎨 (SL) VISUALISATION (Swing & Fractals)";
input group "╚════════════════════════════════════════════════════════╝";
input bool        Inp_ShowSwingMarkers       = false;             // Show Swing High/Low markers
input bool        Inp_ShowFractalMarkers     = true;              // Show Fractal SL markers
input int         Inp_MarkerLookback         = 50;                // Bars to show markers (0 = all history)
input bool        Inp_ShowMarkerLabels       = false;             // Show price labels on markers
input color       Inp_SwingHighColor         = clrCrimson;        // Swing High color
input color       Inp_SwingLowColor          = clrDodgerBlue;     // Swing Low color
input int         Inp_SwingMarkerSize        = 1;                 // Swing marker width (1-5) - tiny like built-in Fractals
input color       Inp_FractalHighColor       = clrGray;           // Fractal High color
input color       Inp_FractalLowColor        = clrGray;           // Fractal Low color
input int         Inp_FractalMarkerSize      = 1;                 // Fractal marker width (1-5) - tiny like built-in Fractals
// input group "--- SL Configuration Examples ---";
// input string   Inp_Ex1_Header             = "Example 1 - Simple Fixed SL: Inp_SLMode=SL_MODE_FIXED_PIPS, Inp_SL_FixedPips=20";
// input string   Inp_Ex2_Header             = "Example 2 - Swing Structure: Inp_SLMode=SL_MODE_SWING, Inp_SwingLookback=20";
// input string   Inp_Ex3_Header             = "Example 3 - Fractal SL:      Inp_SLMode=SL_MODE_FRACTAL, Inp_FractalPeriod=5, Inp_TPFractalOffset=1";
input group "╔════════════════════════════════════════════════════════╗";
input group "║   📈 (TS) TRAILING STOP (CUSTOM only)";
input group "╚════════════════════════════════════════════════════════╝";
input ETrailingMode  Inp_TrailMode           = TRAIL_PSAR;        // Trailing method
input ETrailTrigger  Inp_TrailTrigger        = TRIGGER_IMMEDIATE; // When to start trailing
input bool        Inp_TrailLockProfit        = true;              // Never move SL backwards
input double      Inp_TrailDistancePips      = 5.0;               // Fixed trail distance
input double      Inp_BEThresholdPips        = 5.0;               // Pips profit to trigger breakeven
input double      Inp_TrailProfitPercent     = 10.0;              // Profit % to start trailing
input double      Inp_TrailStepPips          = 5.0;               // Minimum pips to move SL each step
input group "╔════════════════════════════════════════════════════════╗";
input group "║   ⚖️ (BE) BREAK-EVEN (CUSTOM only)";
input group "╚════════════════════════════════════════════════════════╝";
input EBeMode     Inp_BE_Mode                = BE_MODE_TP_PROGRESS_PCT; // RRM BE mode
// input string   Inp_RRM_Info1              = "RRM uses % of TP distance for BE — not absolute pips";
// input string   Inp_RRM_Info2              = "Only active when ExitProfile = EXIT_PROFILE_RRM";
// input string   Inp_RRM_Info3              = "Example: SL=10 pips, TP=30 pips (3:1 RR), BE@33% → triggers at +10 pips profit";
input group "╔════════════════════════════════════════════════════════╗";
input group "║   🎯 (TP) TAKE PROFIT (CUSTOM only)";
input group "╚════════════════════════════════════════════════════════╝";
input bool        Inp_TP_Enabled             = true;              // Enable take profit
input ETPMode     Inp_TPMode                 = TP_MODE_RR;        // TP calculation method
input double      Inp_RRRatio                = 2.0;               // Risk:Reward ratio
input double      Inp_FixedTPPips            = 40.0;              // Fixed TP distance
input group "╔════════════════════════════════════════════════════════╗";
input group "║   🛡 (TE) COOLDOWN BARS Post-Trade Protection";
input group "╚════════════════════════════════════════════════════════╝";
input int         Inp_MinBarsAfterClose      = 1;                 // TE: Min bars cooldown after trade close (0=off)

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
   Settings.PrintEffectiveConfig     = Inp_PrintEffectiveConfig;

   // Map debug level first; DebugFlow=false forces SILENT mode
   Settings.DebugLevel               = Inp_DebugFlow ? Inp_DebugLevel : DEBUG_SILENT;
   Settings.DebugFlow                = (Settings.DebugLevel >= DEBUG_FULL);
   Settings.DebugEvalFrom            = Inp_DebugEvalFrom;
   Settings.DebugEvalTo              = Inp_DebugEvalTo;
   Settings.DebugEvalAt              = Inp_DebugEvalAt;
   Settings.DebugEvalMode            = Inp_DebugEvalMode;
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
   Settings.CloseOnReverse          = Inp_CloseOnReverse;
   Settings.RiskPercent             = Inp_RiskPercent;
   Settings.FixedLotSize            = 0.0; // 0 = risk-based sizing (default)
   Settings.MaxSpread               = Inp_MaxSpreadPips;
   Settings.UseSpread               = Inp_UseSpread;
   Settings.ATR_VoteMinPips         = Inp_Ind_Atr_VoteMinPips;
   Settings.ATR_VoteMaxPips         = Inp_Ind_Atr_VoteMaxPips;

   Settings.CandleBody_AvgPeriod    = MathMax(1, Inp_Ind_CandleBody_AvgPeriod);
   Settings.CandleBody_MaxMult      = Inp_Ind_CandleBody_MaxMult;
   Settings.CandleBody_CheckBars    = MathMax(1, Inp_Ind_CandleBody_CheckBars);
   Settings.CandleBody_RequireDirection = Inp_Ind_CandleBody_RequireDirection;

   Settings.UseMACompatSizer        = false;
   Settings.MA_MaximumRiskPct       = Inp_MA_MaximumRiskPct;
   Settings.MA_DecreaseFactor       = Inp_MA_DecreaseFactor;
   Settings.RequirePriceCross       = false;
   Settings.MABenchmarkStrict       = false;

   Settings.RRM_Lookback               = Inp_RRM_Lookback;
   Settings.RRM_MinDivPips             = Inp_RRM_MinDivPips;
   Settings.RequireRecoveryMomentum    = Inp_Gate_RequireRecoveryMomentum;
   
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
   Settings.BiasFastID           = MathMax(0, MathMin(3, Inp_BiasFastID));
   Settings.BiasSlowID           = MathMax(0, MathMin(3, Inp_BiasSlowID));
   Settings.AutoStrat            = Inp_AutoStrat;
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
   Settings.Ind_VRC_Enabled       = Inp_Ind_VRC_Enabled;
   Settings.Ind_SmaConverge_Enabled = Inp_Ind_SmaConverge_Enabled;

   // Weights
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
   Settings.Ind_VRC_Weight        = Inp_Ind_VRC_Weight;
   Settings.Ind_SmaConverge_Weight = Inp_Ind_SmaConverge_Weight;

   // DPI v31 (disabled by default; enabled and parameterised by PRESET_RRM_ORG)
   Settings.Ind_Dpi_Enabled             = Inp_Ind_Dpi_Enabled;
   Settings.Ind_Dpi_Weight              = Inp_Ind_Dpi_Weight;
   Settings.DPI_MACD_Fast               = MathMax(1, Inp_RRM_ORG_MACD_Fast);
   Settings.DPI_MACD_Slow               = MathMax(1, Inp_RRM_ORG_MACD_Slow);
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
    Settings.DPI_HistMomentumThreshold   = Inp_DPI_HistMomentumThreshold;
    Settings.DPI_HistDecelLookback       = MathMax(1, MathMin(9, Inp_DPI_HistDecelLookback));
    Settings.DPI_HistTrackingEnabled     = Inp_DPI_HistTrackingEnabled;
    // Choppiness Index
    Settings.CI_Period             = MathMax(5, Inp_CI_Period);
    Settings.CI_RangingThreshold   = MathMax(0.0, Inp_CI_RangingThreshold);

   // VRC
   Settings.VRC_ATR_Period        = MathMax(1, Inp_Ind_VRC_ATR_Period);
   Settings.VRC_Lookback          = MathMax(10, Inp_Ind_VRC_Lookback);
   Settings.VRC_LowThreshold      = MathMax(0.0, MathMin(100.0, Inp_Ind_VRC_LowThreshold));

   // Exits
   Settings.SL_FixedPips         = Inp_SL_FixedPips;
   Settings.SL_MinPips           = MathMax(0.0, Inp_SL_MinPips);
   Settings.SL_WidenToMinimum    = Inp_SL_WidenToMinimum;
   Settings.SLMode               = Inp_SLMode;
   Settings.TPMode               = Inp_TPMode;
   Settings.FixedTPPips          = Inp_FixedTPPips;
   Settings.SLPercent            = Inp_SLPercent;
   Settings.RRRatio              = Inp_RRRatio;
   Settings.SwingLookback        = Inp_SwingLookback;
   Settings.FractalPeriod        = Inp_FractalPeriod;
   Settings.TPFractalOffset      = Inp_TPFractalOffset;
   Settings.ShowSwingMarkers     = Inp_ShowSwingMarkers;
   Settings.ShowFractalMarkers   = Inp_ShowFractalMarkers;
   Settings.MarkerLookback       = MathMax(0, Inp_MarkerLookback);
   Settings.ShowMarkerLabels     = Inp_ShowMarkerLabels;
   Settings.SwingHighColor       = Inp_SwingHighColor;
   Settings.SwingLowColor        = Inp_SwingLowColor;
   Settings.SwingMarkerSize      = MathMax(1, MathMin(5, Inp_SwingMarkerSize));
   Settings.FractalHighColor     = Inp_FractalHighColor;
   Settings.FractalLowColor      = Inp_FractalLowColor;
   Settings.FractalMarkerSize    = MathMax(1, MathMin(5, Inp_FractalMarkerSize));

   Settings.TrailTrigger         = Inp_TrailTrigger;
   Settings.TrailDistancePips    = Inp_TrailDistancePips;
   Settings.BEThresholdPips      = Inp_BEThresholdPips;
   Settings.TrailProfitPercent   = Inp_TrailProfitPercent;
   Settings.TrailStepPips        = Inp_TrailStepPips;
   Settings.TrailLockProfit      = Inp_TrailLockProfit;
   Settings.TP_Enabled           = Inp_TP_Enabled;
   Settings.TrailMode            = Inp_TrailMode;
   Settings.PSAR_TrailCushionMode= Inp_PSAR_TrailCushionMode;
   Settings.PSAR_TrailDelay      = (Inp_PSAR_TrailDelay < 1) ? 1 : (Inp_PSAR_TrailDelay > 3) ? 3 : Inp_PSAR_TrailDelay;

   Settings.ExitProfile             = Inp_ExitProfile;
   Settings.BE_Mode                 = Inp_BE_Mode;
   Settings.RRM_BE_ProgressPct      = Inp_RRM_BE_ProgressPct;
   Settings.RRM_BE_RMultiple        = Inp_RRM_BE_RMultiple;
   Settings.RRM_TrailPsarShiftDelay = (Inp_RRM_TrailPsarShiftDelay < 1) ? 1 : (Inp_RRM_TrailPsarShiftDelay > 3) ? 3 : Inp_RRM_TrailPsarShiftDelay;
   Settings.RRM_FreezeTrailOnFlip   = Inp_RRM_FreezeTrailOnFlip;
   Settings.RRM_TrailStartsAfterBE  = Inp_RRM_TrailStartsAfterBE;

   Settings.Vote_EvalShift       = 1;
   Settings.Vote_AllowPsarFlip   = false;
   Settings.Vote_PsarFlipDelay   = (Inp_Vote_PsarFlipDelay < -1) ? -1 : (Inp_Vote_PsarFlipDelay > 10) ? 10 : Inp_Vote_PsarFlipDelay;

   Settings.MaxTotalRisk         = MathMax(0.0, Inp_MaxTotalRisk);
   Settings.MaxOpenTrades        = MathMax(0, Inp_MaxOpenTrades);
   Settings.CountBEasZeroRisk    = true;
   Settings.MarginUsageLimit     = MathMax(0.0, Inp_MarginUsageLimit);
   Settings.MinMarginLevel       = MathMax(0.0, Inp_MinMarginLevel);
   Settings.EmergencyMarginLevel = MathMax(0.0, Inp_EmergencyMarginLevel);

   Settings.Adaptive.PairType          = Inp_Adaptive_PairType;
   Settings.Adaptive.Spread_Major      = Inp_Adaptive_Spread_Major;
   Settings.Adaptive.Spread_Minor      = Inp_Adaptive_Spread_Minor;
   Settings.Adaptive.Spread_Exotic     = Inp_Adaptive_Spread_Exotic;
   Settings.Adaptive.Spread_Gold       = Inp_Adaptive_Spread_Gold;
   Settings.Adaptive.Spread_Crypto     = Inp_Adaptive_Spread_Crypto;

   if(Settings.Adaptive.PairType == PAIR_TYPE_AUTO)
      Settings.Adaptive.PairType = DetectPairType(_Symbol);

   Settings.MaxSpread = GetAdaptiveSpreadLimit(Settings.Adaptive.PairType, Settings.Adaptive);

   Settings.PhaseDetectionEnabled        = false;
   Settings.BlockUnorderedPhase          = true;
   Settings.BlockEmergingPhase           = false;   // default off for backward compat
   Settings.RequireMinPhaseConfirm       = false;
   Settings.MinPhaseConfirmBars          = 0;
   
   Settings.Emerging_AllowWeakTrades     = true;
   Settings.Emerging_AllowMediumTrades   = true;
   Settings.Emerging_AllowStrongTrades   = true;
   Settings.Trending_AllowWeakTrades     = true;
   Settings.Trending_AllowMediumTrades   = true;
   Settings.Trending_AllowStrongTrades   = true;

    Settings.EnableLayerDetection         = false;
    Settings.AllowLayer1_Entries          = true;
    Settings.AllowLayer2_Entries          = true;
    Settings.AllowLayer3_Entries          = true;

    Settings.RRM_EnableDrawdownProtection = Inp_RRM_EnableDrawdownProtection;
   Settings.RRM_MaxConsecutiveLosses     = Inp_RRM_MaxConsecutiveLosses;
   Settings.RRM_MaxTradesPerDay          = Inp_RRM_MaxTradesPerDay;
   Settings.RRM_MaxDailyDrawdownPct      = Inp_RRM_MaxDailyDrawdownPct;

    Settings.SlopeLookbackBars      = 1;
    Settings.LayerPullbackEnabled        = Inp_LayerPullbackEnabled;
    Settings.LayerBaselineLookback       = MathMax(3, Inp_LayerBaselineLookback);
    Settings.LayerPullbackRatio          = MathMax(0.1, Inp_LayerPullbackRatio);
    Settings.LayerRecoveryRatio          = MathMax(0.1, Inp_LayerRecoveryRatio);
    Settings.LayerFlatRatio              = MathMax(0.05, Inp_LayerFlatRatio);
    Settings.LayerAllowReversalPullback  = Inp_LayerAllowReversalPullback;

    // BarClose (bcX) settings
    Settings.BarClose_Enabled    = Inp_BarClose_Enabled;
   Settings.BarClose_Mode       = Inp_BarClose_Mode;
   Settings.BarClose_DefaultEMA = Inp_BarClose_DefaultEMA;

   // Re-entry after breakeven: disabled by default; enabled by RRM presets
   Settings.AllowReEntryAfterBE = false;

   // Post-trade cooldown: disabled by default; presets may override
   Settings.MinBarsAfterClose = Inp_MinBarsAfterClose;

   // Spread retry cap: kill carry after N consecutive spread-blocked bars (0=unlimited)
   Settings.MaxSpreadRetryBars    = Inp_MaxSpreadRetryBars;

   // EMA fan overextension filter: disabled by default (presets override)
   Settings.EmaFanFilterEnabled   = Inp_EmaFanFilterEnabled;
   Settings.EmaFanMaxTotalPips    = Inp_EmaFanMaxTotalPips;

   // DPI momentum deceleration filter: disabled by default (presets override)
   Settings.DpiDecelFilterEnabled = Inp_DpiDecelFilterEnabled;

   // ── PHASE B: TE-side gate defaults (off; PRESET_RRM_ORG turns them on) ──
   Settings.TE_RecheckBarClose    = false;
   Settings.TE_OpenDelaySeconds   = 0;
   Settings.TE_SpreadMedianTicks  = 0;

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

struct SIndicatorMeta {
   string name;               // Full display name (e.g. "CandleBody")
   string short_name;         // Compact code for UI (e.g. "CBody")
   bool   is_enabled;         // Cached enabled state (set at init time)
   int    weight;             // Vote weight (1 for most indicators)
   bool   prefers_subwindow;  // Indicates if the UI should draw this in a subwindow
};

SIndicatorMeta g_indicator_registry[17];

//+------------------------------------------------------------------+
//| InitializeIndicatorRegistry(): Populate registry from settings    |
//+------------------------------------------------------------------+
void InitializeIndicatorRegistry(const ST_Settings &cfg)
{
   int i = 0;
   g_indicator_registry[i].name       = "ADX";
   g_indicator_registry[i].short_name = "ADX";
   g_indicator_registry[i].is_enabled = cfg.Ind_Adx_Enabled;
   g_indicator_registry[i].weight     = cfg.Ind_Adx_Weight;
   g_indicator_registry[i].prefers_subwindow = true;
   i++;
   
   g_indicator_registry[i].name       = "ATR";
   g_indicator_registry[i].short_name = "ATR";
   g_indicator_registry[i].is_enabled = cfg.Ind_Atr_Enabled;
   g_indicator_registry[i].weight     = cfg.Ind_Atr_Weight;
   g_indicator_registry[i].prefers_subwindow = true;
   i++;

   g_indicator_registry[i].name       = "BB";
   g_indicator_registry[i].short_name = "BB";
   g_indicator_registry[i].is_enabled = cfg.Ind_Bb_Enabled;
   g_indicator_registry[i].weight     = cfg.Ind_Bb_Weight;
   g_indicator_registry[i].prefers_subwindow = false;
   i++;

   g_indicator_registry[i].name       = "CandleBody";
   g_indicator_registry[i].short_name = "CBody";
   g_indicator_registry[i].is_enabled = cfg.Ind_CandleBody_Enabled;
   g_indicator_registry[i].weight     = cfg.Ind_CandleBody_Weight;
   g_indicator_registry[i].prefers_subwindow = false;
   i++;
   
   g_indicator_registry[i].name       = "Choppiness Index";
   g_indicator_registry[i].short_name = "CI";
   g_indicator_registry[i].is_enabled = cfg.Ind_CI_Enabled;
   g_indicator_registry[i].weight     = cfg.Ind_CI_Weight;
   g_indicator_registry[i].prefers_subwindow = true;
   i++;

   g_indicator_registry[i].name       = "CCI";
   g_indicator_registry[i].short_name = "CCI";
   g_indicator_registry[i].is_enabled = cfg.Ind_Cci_Enabled;
   g_indicator_registry[i].weight     = cfg.Ind_Cci_Weight;
   g_indicator_registry[i].prefers_subwindow = true;
   i++;

   g_indicator_registry[i].name       = "MACD";
   g_indicator_registry[i].short_name = "MACD";
   g_indicator_registry[i].is_enabled = cfg.Ind_Macd_Enabled;
   g_indicator_registry[i].weight     = cfg.Ind_Macd_Weight;
   g_indicator_registry[i].prefers_subwindow = true;
   i++;

   g_indicator_registry[i].name       = "MFI";
   g_indicator_registry[i].short_name = "MFI";
   g_indicator_registry[i].is_enabled = cfg.Ind_Mfi_Enabled;
   g_indicator_registry[i].weight     = cfg.Ind_Mfi_Weight;
   g_indicator_registry[i].prefers_subwindow = true;
   i++;

   g_indicator_registry[i].name       = "P123";
   g_indicator_registry[i].short_name = "P123";
   g_indicator_registry[i].is_enabled = cfg.Ind_P123_Enabled;
   g_indicator_registry[i].weight     = cfg.Ind_P123_Weight;
   g_indicator_registry[i].prefers_subwindow = false;
   i++;
   
   g_indicator_registry[i].name       = "PSAR";
   g_indicator_registry[i].short_name = "PSAR";
   g_indicator_registry[i].is_enabled = cfg.Ind_Psar_Enabled;
   g_indicator_registry[i].weight     = cfg.Ind_Psar_Weight;
   g_indicator_registry[i].prefers_subwindow = false;
   i++;

   g_indicator_registry[i].name       = "Ross";
   g_indicator_registry[i].short_name = "Ross";
   g_indicator_registry[i].is_enabled = cfg.Ind_Ross_Enabled;
   g_indicator_registry[i].weight     = cfg.Ind_Ross_Weight;
   g_indicator_registry[i].prefers_subwindow = false;
   i++;

   g_indicator_registry[i].name       = "RSI";
   g_indicator_registry[i].short_name = "RSI";
   g_indicator_registry[i].is_enabled = cfg.Ind_Rsi_Enabled;
   g_indicator_registry[i].weight     = cfg.Ind_Rsi_Weight;
   g_indicator_registry[i].prefers_subwindow = true;
   i++;
   
   g_indicator_registry[i].name       = "Stochastic";
   g_indicator_registry[i].short_name = "Stoch";
   g_indicator_registry[i].is_enabled = cfg.Ind_Sto_Enabled;
   g_indicator_registry[i].weight     = cfg.Ind_Sto_Weight;
   g_indicator_registry[i].prefers_subwindow = true;
   i++;

   g_indicator_registry[i].name       = "VRC";
   g_indicator_registry[i].short_name = "VRC";
   g_indicator_registry[i].is_enabled = cfg.Ind_VRC_Enabled;
   g_indicator_registry[i].weight     = cfg.Ind_VRC_Weight;
   g_indicator_registry[i].prefers_subwindow = false;
   i++;

   g_indicator_registry[i].name             = "SmaConverge";
   g_indicator_registry[i].short_name       = "SmaConv";
   g_indicator_registry[i].is_enabled       = cfg.Ind_SmaConverge_Enabled;
   g_indicator_registry[i].weight           = cfg.Ind_SmaConverge_Weight;
   g_indicator_registry[i].prefers_subwindow = false;
   i++;

   g_indicator_registry[i].name             = "DPI";
   g_indicator_registry[i].short_name       = "DPI";
   g_indicator_registry[i].is_enabled       = cfg.Ind_Dpi_Enabled;
   g_indicator_registry[i].weight           = cfg.Ind_Dpi_Weight;
   g_indicator_registry[i].prefers_subwindow = true;
}

//+------------------------------------------------------------------+
//| GetEnabledIndicatorCount(): Count enabled voting indicators      |
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
   if(cfg.Ind_Macd_Enabled)       count++;
   if(cfg.Ind_Mfi_Enabled)        count++;
   if(cfg.Ind_P123_Enabled)       count++;
   if(cfg.Ind_Psar_Enabled)       count++;
   if(cfg.Ind_Ross_Enabled)       count++;
   if(cfg.Ind_Rsi_Enabled)        count++;
   if(cfg.Ind_Sto_Enabled)        count++;
   if(cfg.Ind_VRC_Enabled)        count++;
   if(cfg.Ind_SmaConverge_Enabled) count++;
   if(cfg.Ind_Dpi_Enabled)        count++;
   return count;
}

//+------------------------------------------------------------------+
//| GetEnabledIndicatorList(): Comma-separated list of active names  |
//+------------------------------------------------------------------+
string GetEnabledIndicatorList(const ST_Settings &cfg, bool compact = true)
{
   string names[]  = {"ADX", "ATR", "BB", "CandleBody", "Choppiness Index", "CCI", "MACD",
                      "MFI", "P123", "PSAR", "Ross", "RSI", "SmaConverge", "Stochastic", "VRC", "DPI"};
   string shorts[] = {"ADX", "ATR", "BB", "CBody", "CI", "CCI", "MACD",
                      "MFI", "P123", "PSAR", "Ross", "RSI", "SmaConv", "Stoch", "VRC", "DPI"};
   bool enabled[]  = {cfg.Ind_Adx_Enabled, cfg.Ind_Atr_Enabled, cfg.Ind_Bb_Enabled,
                      cfg.Ind_CandleBody_Enabled, cfg.Ind_CI_Enabled, cfg.Ind_Cci_Enabled,
                      cfg.Ind_Macd_Enabled, cfg.Ind_Mfi_Enabled,
                      cfg.Ind_P123_Enabled, cfg.Ind_Psar_Enabled, cfg.Ind_Ross_Enabled,
                      cfg.Ind_Rsi_Enabled, cfg.Ind_SmaConverge_Enabled,
                      cfg.Ind_Sto_Enabled, cfg.Ind_VRC_Enabled, cfg.Ind_Dpi_Enabled};
   string list = "";
   for(int i = 0; i < 16; i++)
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
   Print("--- Indicator Registry (17 entries) ---");
   for(int i = 0; i < 17; i++)
   {
      PrintFormat("  [%2d] %-12s  enabled=%-5s  weight=%d  subwindow=%-5s",
                  i,
                  g_indicator_registry[i].name,
                  (g_indicator_registry[i].is_enabled ? "true" : "false"),
                  g_indicator_registry[i].weight,
                  (g_indicator_registry[i].prefers_subwindow ? "true" : "false"));
   }
}

//+------------------------------------------------------------------+
//| Global Price Normalization Utils                                 |
//+------------------------------------------------------------------+
double GlobalPipSize(string symbol)
{
   double point  = SymbolInfoDouble(symbol, SYMBOL_POINT);
   int    digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   if(digits == 3 || digits == 5) return point * 10.0;
   return point;
}

double GlobalSpreadPips(string symbol)
{
   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
   double pip = GlobalPipSize(symbol);
   return (pip <= 0.0) ? 0.0 : (ask - bid) / pip;
}

//+------------------------------------------------------------------+
//| Global Volatility Normalization                                  |
//+------------------------------------------------------------------+
double GlobalAtrPips(double atr_value, string symbol)
{
   double pip = GlobalPipSize(symbol);
   if(pip <= 0.0 || atr_value <= 0.0) return 0.0;
   return atr_value / pip;
}

//+------------------------------------------------------------------+
//| END OF FILE                                                      |
//+------------------------------------------------------------------+
