//+------------------------------------------------------------------+
//|                                                   SEA_Config.mqh |
//|                                   Copyright 2026, SimpleEA System|
//+------------------------------------------------------------------+
#property strict

#define SEA_STATUS_EVALUATING "Evaluating..."

// ── ACTIVE PRESET SELECTOR ──────────────────────────────────────────────────
// Uncomment EXACTLY ONE line before compiling. Only that preset's inputs
// will be compiled, keeping total input count under MT5's 1024 limit.
// After changing: recompile SimpleEA_v1-05.mq5 in MetaEditor.
//
//#define SEA_PRESET_MA
//#define SEA_PRESET_FPM
//#define SEA_PRESET_RRM
#define SEA_PRESET_RRM_ORG
//#define SEA_PRESET_TOPINVESTOR
//#define SEA_PRESET_TEST
//
// DO NOT EDIT BELOW — auto-derived helper:
// SEA_PRESET_RRM_FAMILY = defined when RRM or RRM_ORG is active.
// Covers the shared Inp_RRM_* inputs used by both presets.
#ifdef SEA_PRESET_RRM
#define SEA_PRESET_RRM_FAMILY
#endif
#ifdef SEA_PRESET_RRM_ORG
#define SEA_PRESET_RRM_FAMILY
#endif
// ─────────────────────────────────────────────────────────────────────────────

// TFToString: returns clean TF label (e.g. "M5", "H1") — EnumToString gives "PERIOD_M5".
string TFToString(ENUM_TIMEFRAMES tf = PERIOD_CURRENT) {
   ENUM_TIMEFRAMES resolved = (tf == PERIOD_CURRENT) ? (ENUM_TIMEFRAMES)Period() : tf;
   string s = EnumToString(resolved);
   // Strip "PERIOD_" prefix if present
   if(StringFind(s, "PERIOD_") == 0) s = StringSubstr(s, 7);
   return s;
}

// Forward declaration: SEA_UI_StoreVPRRContent is defined in SEA_UI.mqh
// but called from SEA_Presets.mqh which is included first.
void SEA_UI_StoreVPRRContent(const string &lines[], const color &clrs[]);



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
   PRESET_TOPINVESTOR,     // PRESET_TOPINVESTOR: Dr Świerk TopInvestor / OXO methodology (EMA50/200 confluence)
   PRESET_FPM,             // PRESET_FPM: Five-Point Method (PSAR+MACD+BB+SMA10/20)
   PRESET_RRM_ORG          // PRESET_RRM_ORG: Russ Horn Original RRM with inline DPI momentum voter
};
enum ETIProfile
{
   TI_CONSERVATIVE,        // TI_CONSERVATIVE: 4 voters (PSAR, ADX, CBody, MTF)
   TI_MODERATE,            // TI_MODERATE: 7 voters (+ MACD, CCI, BB)
   TI_FULL                 // TI_FULL: 10 voters (+ DPI, SmaConv, Fib, CB 75%)
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
   LAYER_NONE        = 0,  // LAYER_NONE: No layer detected or detection disabled 0b0000
   LAYER_1_WEAK      = 1,  // LAYER_WEAK: L1: EMA1-2 "Ribbon" zone (shallow pullback) 0b0001
   LAYER_2_MEDIUM    = 2,  // LAYER_MEDIUM: L2: EMA2-3 "Ghost" zone (medium pullback) 0b0010
   LAYER_3_STRONG    = 4,  // LAYER_STRONG: L3: EMA3-4 "Shark" zone (deep pullback) 0b0100
   LAYER_1_2         = 3,  // LAYER_12: L1+L2 simultaneously 0b0011
   LAYER_2_3         = 6,  // LAYER_23: L2+L3 simultaneously 0b0110
   LAYER_1_2_3       = 7   // LAYER_123: L1+L2+L3 simultaneously 0b0111
};
//+------------------------------------------------------------------+
//| Layer Pullback State Machine                                     |
//+------------------------------------------------------------------+
enum ELayerPullbackState
{
   LAYER_PB_NONE,        // LAYER_PB_NONE: No pullback detected yet (initial trending)
   LAYER_PB_DETECTED,    // LAYER_PB_DETECTED: Pullback or flat phase observed
   LAYER_PB_RECOVERED    // LAYER_PB_RECOVERED: Recovery confirmed (ready to trade)
};
// VPRR: Volume Pullback-Recovery Ratio — volume source selection
enum EVPRRVolumeType
{
   VPRR_VOL_AUTO=0,      // VPRR_VOL_AUTO: fall back to VOLUME_TICK if unavailable
   VPRR_VOL_REAL=1,      // VPRR_VOL_REAL: exchange volume; metals/indices/equities/futures
   VPRR_VOL_TICK=2,      // VPRR_VOL_TICK: tick count; available everywhere, poor on forex
   VPRR_VOL_EXTERNAL=3   // VPRR_VOL_EXTERNAL: CopyRealVolume from proxy symbol (e.g. "GC" for XAUUSD on CFD broker)
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
   BC_DISABLED    = 0,     // BC_DISABLED: always returns 1 (skip bar close check)
   BC_FIXED_EMA   = 1,     // BC_FIXED_EMA: always check vs BarClose_DefaultEMA
   BC_LAYER_AWARE = 2,     // BC_LAYER_AWARE: bcW=EMA1, bcM=EMA2, bcS=EMA3
   BC_BIAS_FAST   = 3      // BC_BIAS_FAST: ID EMA
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
   CCI_TREND_ZERO,         // CCI_TREND_ZERO based on zero line (>0 bull, <0 bear)
   CCI_IMPULSE_100         // CCI_IMPULSE_100 (>100 or <-100)
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
   VOLATILITY_LOW = 0,    // VOLATILITY_LOW: too quiet, likely choppy
   VOLATILITY_NORMAL,     // VOLATILITY_NORMAL: acceptable trading conditions
   VOLATILITY_HIGH        // VOLATILITY_HIGH: explosive - reserved for future use
};

//+------------------------------------------------------------------+
//| CUSHION | TRAIL | SL | TP | BE | EXIT
//+------------------------------------------------------------------+
enum EPsarTrailCushionMode
{
   PSAR_CUSHION_PIPS,      // PSAR_CUSHION_PIPS: Fixed pips × pipSize (legacy)
   PSAR_CUSHION_ATR,       // PSAR_CUSHION_ATR: (period) × multiplier (volatility-aware, universal)
   PSAR_CUSHION_PERCENT    // PSAR_CUSHION_PERCENT: of price (price × pct/100, universal)
};
enum ETrailTrigger
{
   TRIGGER_IMMEDIATE,      // TRIGGER_IMMEDIATE: Tr from entry (default)
   TRIGGER_BREAKEVEN,      // TRIGGER_BREAKEVEN: Tr after breakeven threshold reached
   TRIGGER_PROFIT_PIPS,    // TRIGGER_PROFIT_PIPS: Tr after X pips profit (TrailDistancePips)
   TRIGGER_PROFIT_PERCENT, // TRIGGER_PROFIT_PERCENT: Tr after X% of risk / R-multiple (TrailProfitPercent)
   TRIGGER_PSAR_ALIGN      // TRIGGER_PSAR_ALIGN: Tr when PSAR aligns with position direction
};
enum ETrailingMode
{
   TRAIL_BREAKEVEN,        // TRAIL_BREAKEVEN: move to breakeven then trail fixed pips
   TRAIL_FIXED_PIPS,       // TRAIL_FIXED_PIPS: fixed pip distance trailing
   TRAIL_FRACTAL,          // TRAIL_FRACTAL: fractal-based trailing
   TRAIL_NONE,             // TRAIL_NONE: no trailing stop
   TRAIL_PROFIT_PERCENT,   // TRAIL_PROFIT_PERCENT: trail at % behind peak profit
   TRAIL_PSAR,             // TRAIL_PSAR: dot trailing
   TRAIL_PSAR_FLIP_EXIT,   // TRAIL_PSAR_FLIP_EXIT: close position on PSAR flip
   TRAIL_EMA               // TRAIL_EMA: exit when close crosses EMA against bias
};
enum ESLMode
{
   SL_MODE_FIXED_PIPS  = 0, // SL_MODE_FIXED_PIPS: Fixed pips distance from entry
   SL_MODE_FRACTAL     = 1, // SL_MODE_FRACTAL: Last fractal level (Bill Williams)
   SL_MODE_PERCENT     = 2, // SL_MODE_PERCENT: Percentage of entry price
   SL_MODE_SWING       = 3, // SL_MODE_SWING: Recent swing high/low (SwingLookback bars)
   SL_MODE_PSAR_DOT    = 4, // SL_MODE_PSAR_DOT: PSAR dot position (keep for FX pairs)
   SL_MODE_ATR         = 5  // SL_MODE_ATR: Swing anchor − ATR(period) × multiplier (industry standard; prevents under-sized SL on volatile instruments)
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
   GATE_SCALE_FIXED,       // GATE_FIXED: Use a fixed dimensionless gate value instead of adaptive TF scaling
   GATE_SCALE_AUTO_TF      // GATE_AUTO: Auto-scale by timeframe/pair
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
   UI_FRAME_BG,            // UI_FRAME_BG: Rectangle background (default)
   UI_FRAME_NONE,          // UI_FRAME_NONE: Text only (no rectangle)
   UI_FRAME_TEXT_BOUNDS    // UI_FRAME_TEXT: Text bounds markers (BEGIN/END), no rectangle
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
   double RiskCapMultiple;       // Hard per-trade cap: lots clamped so worst-case loss <= RiskCapMultiple × target risk (circuit breaker; default 1.5)
   int    MaxOpenTrades;         // Max number of concurrent trades (0 = no limit)
   bool   CountBEasZeroRisk;     // If true, trades at breakeven don't count toward risk
   double MarginUsageLimit;      // Max % of free margin allowed per trade (0 = use 100%)
   double MinMarginLevel;        // Block new entries if margin level (%) is below this threshold (0 = disabled)
   // Adaptive risk & margin
   bool   UseAdaptiveRisk;         // Enable TF-based risk scaling
   double AdaptiveRisk_M1;         // M1 risk % (default: 1.0)
   double AdaptiveRisk_M5;         // M5 risk % (default: 1.5)
   double AdaptiveRisk_M15Plus;    // M15+ risk % (default: 2.0)
   double Override_SL_Cushion;     // User override for SL cushion (0 = auto)
   double Override_Trail_Cushion;  // User override for trail cushion (0 = auto)
   double Override_BE_Cushion;     // User override for BE cushion (0 = auto)
   bool   UseMarginAdjustment;     // Enable instrument margin adjustment
   double MarginAdj_Gold;          // Gold/metals multiplier
   double MarginAdj_Crypto;        // Crypto multiplier
   double MarginAdj_Exotic;        // Exotic multiplier
   double MarginAdj_JPY;           // JPY multiplier
   double EmergencyMarginLevel;  // Emergency TM threshold (%) to cut worst position (0 = disabled)
   double MaxSpread;
   bool   UseSpread;             // Enable spread filter (false = bypass spread gate)

   // Candle Body Overextension Indicator (voting)
   int    CandleBody_AvgPeriod;        // Bars used to compute average body size
   double CandleBody_MaxMult;          // Block if body > avg * multiplier
   int    CandleBody_CheckBars;        // Number of recent closed candles to check
   bool   CandleBody_RequireDirection; // CandleBody: Require signal bar to close in trade direction
   double CandleBody_MinCloseRatio;   // CandleBody: Min close-to-range ratio (0.0=disabled, 0.75=TopInvestor 75% rule)
   
   // MT5 Moving Average benchmark compatibility
   bool   UseMACompatSizer;
   double MA_MaximumRiskPct;
   double MA_DecreaseFactor;
   bool   RequirePriceCross;
   bool   MABenchmarkStrict;
   
   // RRM (Trend Pullback)
   int    RRM_Lookback;

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
   bool            Ind_MTF_Enabled;    // MTF vote enabled
   ENUM_TIMEFRAMES MTF_TF1;            // MTF confirmation timeframe 1
   ENUM_TIMEFRAMES MTF_TF2;            // MTF confirmation timeframe 2 (PERIOD_CURRENT = single TF mode)
   int             MTF_EMA_Fast;       // MTF fast EMA period
   int             MTF_EMA_Slow;       // MTF slow EMA period
   bool            MTF_RequirePhase;   // Veto MTF: require trending phase
   bool            MTF_StrictAlignment;// MTF: strict all-TF alignment

   // Fibonacci Retracement voter
   bool   Ind_Fib_Enabled;             // Fibonacci retracement depth voter
   double Fib_MinRetracement;          // Min pullback depth (default 0.38)
   double Fib_MaxRetracement;          // Max pullback depth (default 0.618)
   int    Fib_SwingLookback;           // Bars to find swing H/L (default 50)

   // TRAIL_EMA
   int    TrailEMA_Period;             // EMA period for trailing (0=use ribbon role below)
   int    TrailEMA_RibbonRole;         // 0=EMA1,1=EMA2,2=EMA3,3=EMA4 (used when TrailEMA_Period=0)
   int    TrailEMA_Shift;              // bar shift for EMA read: 1=last closed bar, 2=two bars back, etc.
   double TrailEMA_CushionPips;        // EMA trail cushion in pips (0 = use ATR mode if mult>0, else PSAR fallback)
   double TrailEMA_CushionAtrMult;     // EMA trail cushion as ATR multiple (0=disabled; recommended 0.05-0.15 for H1)
   int    TrailEMA_CushionAtrPeriod;   // ATR period for EMA cushion (default 14)

   // Voting

   // Per-indicator weights (1 = standard; only used in VOTE_MODE_THRESHOLD for weighted sum)
   // In VOTE_MODE_ALL, weights are ignored — all enabled indicators must simply agree.


   // Choppiness Index
   int    CI_Period;
   double CI_RangingThreshold;

   // VRC (Volatility Regime Classifier)
   bool   Ind_VRC_Enabled;
   bool   Ind_SmaConverge_Enabled;     // SMA Convergence vote (gap narrowing = pullback signal)
   bool   Ind_Dpi_Enabled;             // DPI vote (inline v31 MACD-core momentum indicator)
   int    DPI_MACD_Fast;               // MACD fast EMA period (default 8)
   int    DPI_MACD_Slow;               // MACD slow EMA period (default 13)
   int    DPI_RedSignalType;           // Red signal line type: 1=EMA_A 2=EMA_B 3=EMA_C 4=EMA_D 5=Double
   int    DPI_RedEMA_A;                // EMA period for type 1 (default 5)
   int    DPI_RedEMA_B;                // EMA period for type 2 (default 8)
   int    DPI_RedEMA_C;                // EMA period for type 3 (default 13)
   int    DPI_RedEMA_D;                // EMA period for type 4 (default 21)
   int    DPI_DoubleSmoothFirst;       // First EMA in double-smooth path (default 5)
   int    DPI_DoubleSmoothSecond;      // Second EMA in double-smooth path (default 8)
   bool   DPI_UseCCIReset;             // Enable CCI trend filter (default true)
   int    DPI_CCI_Period;              // CCI period (default 13)
   int    DPI_CCI_AppliedPrice;        // CCI price type ENUM_APPLIED_PRICE (default PRICE_TYPICAL)
   bool   DPI_UseGreenHist;            // Enable GREEN momentum overlay (false = v29-equivalent)
   // DPI Histogram Tracking
   double DPI_HistMomentumThreshold;   // Momentum threshold for CCI-delta change (dimensionless)
   int    DPI_HistDecelLookback;       // Bars to analyze for deceleration
   bool   DPI_HistTrackingEnabled;     // Master enable for histogram tracking
   // DPI Histogram Entry/Exit Logic
   bool   DPI_BlockOnDeceleration;     // Block new entries when histogram decelerating
   bool   DPI_ExitOnHistDisappear;     // Close positions when green histogram vanishes
   double DPI_ExitThreshold;           // Exit when |CCI| falls below this value
   // DPI CCI Reset-Recovery Entry Gate
   // When enabled, entries are only allowed AFTER a CCI reset has occurred and recovered.
   // A reset = CCI flipped against histogram (ribbon color changed during pullback).
   // Recovery = CCI flipped back (ribbon color restored), held for N bars.
   // This filters for setups where the pullback was real (CCI confirmed it)
   // and the trend survived (CCI recovered), producing higher-reliability entries.
   bool   DPI_RequireResetRecovery;    // Master switch: require CCI reset→recovery before entry
   int    DPI_ResetRecoveryBars;       // Bars of recovery after CCI flip-back (0=immediate, 1+=confirmed)
   bool   DPI_ResetRequireGreen;       // Also require GREEN to reappear during recovery
   int    VRC_ATR_Period;
   int    VRC_Lookback;
   double VRC_LowThreshold;            // Below this percentile = LOW regime (reject trade)

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
   bool          MacdHistDecelEnabled;  // Filter D: block when MACD histogram shrinking bar-over-bar (momentum decelerating)
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
   int      SL_AtrPeriod;        // ATR period for SL_MODE_ATR (default 14)
   double   SL_AtrMult;          // ATR multiplier for SL_MODE_ATR: cushion = ATR × this (default 1.0; 0.5–1.5 range)
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
   ETrailTrigger TrailTrigger;      // When to begin trailing (default: TRIGGER_IMMEDIATE)
   double   BEThresholdPips;        // Profit pips required before moving to breakeven
   double   TrailDistancePips;      // Fixed trail distance in pips (TRAIL_FIXED_PIPS / trigger threshold)
   double   TrailProfitPercent;     // Trigger threshold as % of risk (R-multiple) for TRIGGER_PROFIT_PERCENT
   double   TrailProfitPercentLPR;  // Trail at X% behind peak profit for TRAIL_PROFIT_PERCENT
   double   TrailStepPips;          // Minimum pips movement before updating SL
   bool     TrailLockProfit;        // Lock in profit (never move SL backwards)

   // TS - Trailing SL / TP / BE
   ETrailingMode       TrailMode;
   EPsarTrailCushionMode PSAR_TrailCushionMode;
   int                 PSAR_TrailCushionAtrPeriod;    // ATR period for PSAR_CUSHION_ATR
   double              PSAR_TrailCushionAtrMult;      // ATR multiplier for PSAR_CUSHION_ATR
   double              PSAR_TrailCushionPct;          // % of price for PSAR_CUSHION_PERCENT and the safety floor
   double              PSAR_TrailPipsCushion;
   int                 PSAR_TrailDelay;               // PSAR trailing bar-shift delay (1-3)

   // RRM exit contract
   EExitProfile ExitProfile;           // Exit profile selector
   bool         TP_Enabled;            // Whether TP is active
   EBeMode      BE_Mode;               // BE mode for RRM

   // RRM parameters
   double RRM_BE_ProgressPct;          // RRM_BE trigger: % progress toward TP (0..100); used with BE_MODE_TP_PROGRESS_PCT
   double RRM_BE_RMultiple;            // RRM_BE trigger: R-multiple threshold (e.g. 1.0); used with BE_MODE_R_MULTIPLE
   double RRM_BE_BufferPips;           // RRM_BE buffer in pips
   int    RRM_TrailPsarDotShift;     // RRM_PSAR trail bar-shift delay (1..3)
   bool   RRM_FreezeTrailOnFlip;       // RRM_Freeze trailing stop on PSAR flip signal
   bool   RRM_TrailStartsAfterBE;      // RRM_Delay trail activation until BE is triggered

   // Gate system (reusable hard gates for any preset)
   bool        RequireRecoveryMomentum;// Require recovery bar to close in trend direction
   int         Vote_EvalShift;         // Shift for vote evaluation
   bool        Vote_AllowPsarFlip;     // Allow PSAR flip signal in votes
   
   // PSAR flip validation parameters (when Vote_AllowPsarFlip=true)
   int         Vote_PsarFlipDelay;     // Flip timer mode: -1 = PERSISTENT, 0 = FLIP_BAR, 1-10 = COUNTDOWN
   
   // P1: Layer-aware PSAR flip delay overrides (when > -99, overrides Vote_PsarFlipDelay per layer)
   // -99 = use global Vote_PsarFlipDelay (no override)
   // -1  = persistent, 0 = flip bar only, 1-10 = countdown window
   int         Vote_PsarFlipDelay_W;   // LayerW override (-99=use global)
   int         Vote_PsarFlipDelay_M;   // LayerM override (-99=use global)
   int         Vote_PsarFlipDelay_S;   // LayerS override (-99=use global)

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

   // ── Optional Account-Level Safety Guards (all OFF/0 by default) ──
   // These are independent of the daily-scoped RRM Drawdown Protection above
   // and are NOT zeroed by preset overrides, so they work under any preset.
   double   Safety_MaxEquityDrawdownPct;   // Pause new entries if peak→trough equity DD ≥ this %. 0 = off.
   double   Safety_MinEquityFloor;         // Pause new entries if equity ≤ this absolute value. 0 = off.
   double   Safety_MinRewardRiskRatio;     // Reject entries whose TP:SL ratio < this. 0 = off.
   bool     Safety_CountBEInAggregateRisk; // If true, BE positions still count toward MaxTotalRisk (closes the pyramiding gap). Default false.
   int      Safety_MaxPositionsPerDir;     // Max concurrent positions per direction (LONG/SHORT). 0 = off (use MaxOpenTrades only).
   bool     Safety_DelayTrailUntilR;       // If true, trailing only activates after price reaches Safety_TrailActivateR multiples of risk. Default false.
   double   Safety_TrailActivateR;         // R-multiple of open profit required before trailing engages. 0 = off.
   bool     Safety_RequirePriorAtBEToAdd;  // If true, a new position may only open when ALL existing same-symbol positions have SL at break-even or better. Enforces the staged-risk model. Default false.
   
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
    bool     EnableLayerDetection;        // Master switch for multi-layer pullback detection
    bool     AllowLayer1_Entries;         // Allow Layer 1 (EMA1/EMA2 touch) entries
    bool     AllowLayer2_Entries;         // Allow Layer 2 (EMA2/EMA3 touch) entries
    bool     AllowLayer3_Entries;         // Allow Layer 3 (EMA3/EMA4 touch) entries
    // Layer Pullback-Recovery Detection
    bool     LayerPullbackEnabled;        // Master enable for pullback detection
    int      LayerBaselineLookback;       // Bars for baseline direction lookback

    // Climax / Exhaustion Guard (blocks late entries into over-extended impulses)
    bool     ClimaxGuard_Enabled;         // Master enable
    int      ClimaxGuard_Lookback;        // Window (bars) scanned for an impulse
    int      ClimaxGuard_ATRPeriod;       // ATR baseline period (measured pre-impulse)
    double   ClimaxGuard_BarATRMult;      // Single-bar range climax threshold (x ATR)
    double   ClimaxGuard_MoveATRMult;     // Cumulative move climax threshold (x ATR)
    bool     ClimaxGuard_ResetPullback;   // On detection, reset all layer PB states

    // VPRR: Volume Pullback-Recovery Ratio (institutional participation confirmation)
    // Measures avg volume during recovery vs avg volume during pullback.
    // Ratio >= MinRatio => institutions backing the recovery (PASS).
    bool     VPRR_Enabled;                // Master toggle (default false = no-op)
    int      VPRR_VolumeType;             // EVPRRVolumeType: 0=AUTO, 1=REAL, 2=TICK
    int      VPRR_RecoveryBars;           // Recovery bars to measure (clamped 1-10, default 3)
    int      VPRR_MinRecoveryBars;        // Min recovery bars before ratio is valid (default RecoveryBars-1)
    double   VPRR_MinRatio;               // Min recovery/pullback ratio to PASS (default 1.0)
    string   VPRR_ExternalSymbol;         // Proxy symbol for VPRR_VOL_EXTERNAL (e.g. "GC", "MGC"); empty = block all entries

    // Diagnostics: statistics configuration
    bool Stats_TrackRejections;           // Track rejection counts per indicator
    bool Stats_TrackPasses;               // Track pass counts (positive stats)
    bool Stats_FullEvaluation;            // Evaluate ALL indicators per bar (no early exit)

   // Targeted bar evaluation debug (force-print window or pinpoint, independent of TS outcome)
   datetime    DebugEvalFrom;             // Force debug output from this bar time (0=disabled)
   datetime    DebugEvalTo;               // Force debug output up to this bar time (0=disabled; paired with From)
   datetime    DebugEvalAt;               // Force debug output at this exact bar time (0=disabled)
   EDebugLevel DebugEvalMode;             // Debug level to apply during forced printing (default: DEBUG_FULL)

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
   int           ReEntryLotScalePct;    // Re-entry lot scale % (0=full size; 50=half; since original is at BE, total risk stays controlled)

   // Post-trade cooldown
   int           MinBarsAfterClose;      // bars to wait after trade close before new entry (0 = off)
   int           MinBarsAfterWeekendGap; // TS: bars to wait after weekend gap before evaluating signals (0 = off)

   // Spread retry cap — kill carry after N consecutive spread-blocked TE attempts (0=unlimited)
   int    MaxSpreadRetryBars;

   // EMA fan overextension filter — block TS=1 when EMA1–EMA4 gap is wide AND still expanding
   // EmaFanMaxTotalPips=25.0 is an empirically chosen starting point for M1/M5 with EMA5/13/34/89.
   // Adjust per timeframe: M15/H1 consider 40–60 pips; H4+ consider 80–120 pips.
   // JPY pairs (~3-digit): GlobalPipSize() returns the correct pip unit; no special-casing needed.
   //
   // EmaFanMaxPct: normalized alternative — gap as % of midprice. Works universally across
   // all instruments (Forex, Gold, Silver, indices, crypto) without multipliers.
   // If EmaFanMaxPct > 0, it takes priority over EmaFanMaxTotalPips.
   // Reference: 0.36% ≈ 40 pips on EURUSD ≈ $8.60 on Gold ≈ 54 pips on USDJPY.
   bool   EmaFanFilterEnabled;
   double EmaFanMaxTotalPips;
   double EmaFanMaxPct;            // Max EMA1-EMA4 gap as % of price (0=use pips mode)

   // DPI momentum deceleration filter — block TS=1 when directionally-aligned DPI histogram shrinks
   // Only activates when DpiDecelFilterEnabled=true AND Ind_Dpi_Enabled=true.
   bool   DpiDecelFilterEnabled;

   // ── PHASE B: Recovery-sensitivity tuning (all opt-in, default disabled/0) ──────────────────
   // These settings allow pullback-recovery setups to pass filters they previously failed when
   // EMAs/bars are near the threshold.  Default=off to preserve the existing PRESET_RRM_ORG
   // contract.  Enable via the corresponding Inp_RRM_ORG_* inputs.
   bool   DPI_IgnoreCCIForVote;        // DPI vote: use raw histogram direction only (skip CCI-reset)
   bool   DPI_AllowTransition;         // DPI vote: pass when hist rising toward zero
   double Layer_SlopeTolerance;        // Layer slope tolerance in pips (0=strict; N pips = flat allowed)
   double BarClose_PipTolerance;       // Bar-close tolerance in pips (0=strict close>EMA; N=within N pips)
   // ── Multi-Bar Momentum Detection ──
   int    BarClose_LookbackBars;          // BC lookback window (1-4 bars, default 3)
   bool   Require_Progressive_Momentum;   // Require consecutive close improvement (default true)
   bool   DPI_Histogram_Growth_Boost;     // Use DPI histogram growth as confirmation (default true)
   int    PSAR_FlipGraceBars;             // PSAR grace bars after an adverse flip (0=disabled)

   // ── PHASE B: TE-side hardening (read by SEA_TradeExecutor::EvaluateTE) ──
   bool   TE_RecheckBarClose;          // Re-confirm bar-close BC vs live bid at shift=0
   double TE_BC_TolerancePips;         // Allowed shift=0 drift from Close[1] in pips
   int    TE_OpenDelaySeconds;         // Defer EvaluateTE() by N sec after new bar
   int    TE_SpreadMedianTicks;        // Median spread over last N ticks (0=disabled)
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


// Input declarations moved to SEA_Inputs.mqh

struct SIndicatorMeta {
   string name;               // Full display name (e.g. "CandleBody")
   string short_name;         // Compact code for UI (e.g. "CBody")
   bool   is_enabled;         // Cached enabled state (set at init time)
   bool   prefers_subwindow;  // Indicates if the UI should draw this in a subwindow
};

SIndicatorMeta g_indicator_registry[19];

//+------------------------------------------------------------------+
//| InitializeIndicatorRegistry(): Populate registry from settings    |
//+------------------------------------------------------------------+
void InitializeIndicatorRegistry(const ST_Settings &cfg)
{
   int i = 0;
   g_indicator_registry[i].name       = "ADX";
   g_indicator_registry[i].short_name = "ADX";
   g_indicator_registry[i].is_enabled = cfg.Ind_Adx_Enabled;   g_indicator_registry[i].prefers_subwindow = true;
   i++;
   
   g_indicator_registry[i].name       = "ATR";
   g_indicator_registry[i].short_name = "ATR";
   g_indicator_registry[i].is_enabled = cfg.Ind_Atr_Enabled;   g_indicator_registry[i].prefers_subwindow = true;
   i++;

   g_indicator_registry[i].name       = "BB";
   g_indicator_registry[i].short_name = "BB";
   g_indicator_registry[i].is_enabled = cfg.Ind_Bb_Enabled;   g_indicator_registry[i].prefers_subwindow = false;
   i++;

   g_indicator_registry[i].name       = "CandleBody";
   g_indicator_registry[i].short_name = "CBody";
   g_indicator_registry[i].is_enabled = cfg.Ind_CandleBody_Enabled;   g_indicator_registry[i].prefers_subwindow = false;
   i++;
   
   g_indicator_registry[i].name       = "Choppiness Index";
   g_indicator_registry[i].short_name = "CI";
   g_indicator_registry[i].is_enabled = cfg.Ind_CI_Enabled;   g_indicator_registry[i].prefers_subwindow = true;
   i++;

   g_indicator_registry[i].name       = "CCI";
   g_indicator_registry[i].short_name = "CCI";
   g_indicator_registry[i].is_enabled = cfg.Ind_Cci_Enabled;   g_indicator_registry[i].prefers_subwindow = true;
   i++;

   g_indicator_registry[i].name       = "MACD";
   g_indicator_registry[i].short_name = "MACD";
   g_indicator_registry[i].is_enabled = cfg.Ind_Macd_Enabled;   g_indicator_registry[i].prefers_subwindow = true;
   i++;

   g_indicator_registry[i].name       = "MFI";
   g_indicator_registry[i].short_name = "MFI";
   g_indicator_registry[i].is_enabled = cfg.Ind_Mfi_Enabled;   g_indicator_registry[i].prefers_subwindow = true;
   i++;

   g_indicator_registry[i].name       = "P123";
   g_indicator_registry[i].short_name = "P123";
   g_indicator_registry[i].is_enabled = cfg.Ind_P123_Enabled;   g_indicator_registry[i].prefers_subwindow = false;
   i++;
   
   g_indicator_registry[i].name       = "PSAR";
   g_indicator_registry[i].short_name = "PSAR";
   g_indicator_registry[i].is_enabled = cfg.Ind_Psar_Enabled;   g_indicator_registry[i].prefers_subwindow = false;
   i++;

   g_indicator_registry[i].name       = "Ross";
   g_indicator_registry[i].short_name = "Ross";
   g_indicator_registry[i].is_enabled = cfg.Ind_Ross_Enabled;   g_indicator_registry[i].prefers_subwindow = false;
   i++;

   g_indicator_registry[i].name       = "RSI";
   g_indicator_registry[i].short_name = "RSI";
   g_indicator_registry[i].is_enabled = cfg.Ind_Rsi_Enabled;   g_indicator_registry[i].prefers_subwindow = true;
   i++;
   
   g_indicator_registry[i].name       = "Stochastic";
   g_indicator_registry[i].short_name = "Stoch";
   g_indicator_registry[i].is_enabled = cfg.Ind_Sto_Enabled;   g_indicator_registry[i].prefers_subwindow = true;
   i++;

   g_indicator_registry[i].name       = "VRC";
   g_indicator_registry[i].short_name = "VRC";
   g_indicator_registry[i].is_enabled = cfg.Ind_VRC_Enabled;   g_indicator_registry[i].prefers_subwindow = false;
   i++;

   g_indicator_registry[i].name             = "SmaConverge";
   g_indicator_registry[i].short_name       = "SmaConv";
   g_indicator_registry[i].is_enabled       = cfg.Ind_SmaConverge_Enabled;   g_indicator_registry[i].prefers_subwindow = false;
   i++;

   g_indicator_registry[i].name             = "DPI";
   g_indicator_registry[i].short_name       = "DPI";
   g_indicator_registry[i].is_enabled       = cfg.Ind_Dpi_Enabled;   g_indicator_registry[i].prefers_subwindow = true;
   i++;

   g_indicator_registry[i].name             = "MTF";
   g_indicator_registry[i].short_name       = "MTF";
   g_indicator_registry[i].is_enabled       = cfg.Ind_MTF_Enabled;   g_indicator_registry[i].prefers_subwindow = false;
   i++;

   g_indicator_registry[i].name             = "VPRR";
   g_indicator_registry[i].short_name       = "VPRR";
   g_indicator_registry[i].is_enabled       = cfg.VPRR_Enabled;   g_indicator_registry[i].prefers_subwindow = true;
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
   if(cfg.Ind_Fib_Enabled)        count++;
   if(cfg.Ind_MTF_Enabled)        count++;
   if(cfg.VPRR_Enabled)           count++;
   return count;
}

//+------------------------------------------------------------------+
//| GetEnabledIndicatorList(): Comma-separated list of active names  |
//+------------------------------------------------------------------+
string GetEnabledIndicatorList(const ST_Settings &cfg, bool compact = true)
{
   string names[]  = {"ADX", "ATR", "BB", "CandleBody", "Choppiness Index", "CCI", "MACD",
                      "MFI", "P123", "PSAR", "Ross", "RSI", "SmaConverge", "Stochastic", "VRC", "DPI", "MTF", "Fib", "VPRR"};
   string shorts[] = {"ADX", "ATR", "BB", "CBody", "CI", "CCI", "MACD",
                      "MFI", "P123", "PSAR", "Ross", "RSI", "SmaConv", "Stoch", "VRC", "DPI", "MTF", "Fib", "VPRR"};
   bool enabled[]  = {cfg.Ind_Adx_Enabled, cfg.Ind_Atr_Enabled, cfg.Ind_Bb_Enabled,
                      cfg.Ind_CandleBody_Enabled, cfg.Ind_CI_Enabled, cfg.Ind_Cci_Enabled,
                      cfg.Ind_Macd_Enabled, cfg.Ind_Mfi_Enabled,
                      cfg.Ind_P123_Enabled, cfg.Ind_Psar_Enabled, cfg.Ind_Ross_Enabled,
                      cfg.Ind_Rsi_Enabled, cfg.Ind_SmaConverge_Enabled,
                      cfg.Ind_Sto_Enabled, cfg.Ind_VRC_Enabled, cfg.Ind_Dpi_Enabled, cfg.Ind_MTF_Enabled, cfg.Ind_Fib_Enabled,
                      cfg.VPRR_Enabled};
   string list = "";
   for(int i = 0; i < 19; i++)
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
   Print("--- Indicator Registry (19 entries) ---");
   for(int i = 0; i < 19; i++)
   {
      PrintFormat("  [%2d] %-12s  enabled=%-5s  subwindow=%-5s",
                  i,
                  g_indicator_registry[i].name,
                  (g_indicator_registry[i].is_enabled ? "true" : "false"),
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
