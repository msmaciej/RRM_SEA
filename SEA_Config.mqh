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
   PRESET_TEST_INDICATOR      // PRESET - Isolated Indicator Testing (minimal, one indicator at a time)
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

//+------------------------------------------------------------------+
//| Bias Mode (How to Determine Market Direction)                    |
//|                                                                  |
//| Three methods for calculating trend bias (market direction).     |
//| Each method differs in how many EMAs it uses and how it         |
//| determines the prevailing trend.                                 |
//|                                                                  |
//| BIAS_MANUAL:                                                     |
//|   Uses: Operator-set fixed direction                             |
//|   Logic: Always returns configured side (LONG, SHORT, or BOTH)  |
//|   When to use: Override mode, backtesting a single direction     |
//|   MarketPhase: NOT calculated (always = 1)                      |
//|   EntryLayer: Can still be used (if enabled)                    |
//|                                                                  |
//| BIAS_AUTO (Traditional EMA method):                              |
//|   Uses: Fast EMA vs Slow EMA comparison                         |
//|   Logic:                                                         |
//|     - EMA_Fast > EMA_Slow (both slopes up)   → Bias = 1 (LONG) |
//|     - EMA_Fast < EMA_Slow (both slopes down) → Bias = -1 (SHORT)|
//|     - EMAs crossing or flat                  → Bias = 0 (NEUTRAL)|
//|   When to use: Standard trend-following strategies               |
//|   MarketPhase: NOT calculated (always = 1)                      |
//|   EntryLayer: Can still be used (if enabled)                    |
//|                                                                  |
//| BIAS_AUTO_PHASE (Market Phase method):                           |
//|   Uses: 4 EMAs (EMA1, EMA2, EMA3, EMA4) structure analysis     |
//|   Logic:                                                         |
//|     1. Analyze EMA2, EMA3, EMA4 relative positions and slopes   |
//|     2. Determine Market Phase (TRENDING/EMERGING/UNORDERED)     |
//|     3. Extract Bias direction from phase structure              |
//|   When to use: RRM strategy, advanced trend detection            |
//|   MarketPhase: CALCULATED (TRENDING/EMERGING/UNORDERED)        |
//|   EntryLayer: Can still be used (if enabled)                    |
//|   Special: UNORDERED phase blocks all trades (TS = 0)          |
//+------------------------------------------------------------------+
enum EBiasMode
{
   BIAS_MANUAL,       // Manual direction (LONG_ONLY, SHORT_ONLY, BOTH)
   BIAS_AUTO,         // Auto: Traditional EMA-based bias (single or dual EMA)
   BIAS_AUTO_PHASE    // Auto: Market Phase bias (4-EMA structure → TRENDING/EMERGING/UNORDERED)
};

//+------------------------------------------------------------------+
//| Market Phase (for 4-EMA Bias Mode)                               |
//|                                                                  |
//| Analyzes EMA slopes + ordering for instant market structure.     |
//| Only used when BiasMode = BIAS_AUTO_PHASE.                       |
//|                                                                  |
//| PHASE_TRENDING_UP / PHASE_TRENDING_DN:                           |
//|   - EMA3 and EMA4 slopes agree (both up or both down)           |
//|   - EMAs properly ordered (EMA2>EMA3>EMA4 for UP)               |
//|   - Strong, clear trend structure                               |
//|   → Allow all layers (L1, L2, L3), Bias = 1 or -1              |
//|                                                                  |
//| PHASE_EMERGING_UP / PHASE_EMERGING_DN:                           |
//|   - EMA3 and EMA4 slopes agree (both up or both down)           |
//|   - EMA4 sandwiched between EMA2 and EMA3 (trend forming)       |
//|   - Transitioning towards TRENDING phase                        |
//|   → Allow L1/L2 only (block L3), Bias = 1 or -1                |
//|                                                                  |
//| PHASE_UNORDERED:                                                 |
//|   - EMA3/EMA4 slopes conflict, or either is flat                |
//|   - Any other EMA configuration not matching above              |
//|   - Mixed or choppy market                                      |
//|   → Block all trades (TS = 0), Bias = 0                        |
//+------------------------------------------------------------------+
enum EMarketPhase {
   PHASE_UNORDERED,      // No clear structure - block all trades (TS = 0)
   PHASE_EMERGING,       // Trend forming (EMA4 between EMA2/EMA3) - allow trades (legacy; use UP/DN variants)
   PHASE_TRENDING,       // EMAs fully stacked, strong established trend (legacy; use UP/DN variants)
   PHASE_TRENDING_UP,    // Trending bullish: slopes up + EMA2>EMA3>EMA4
   PHASE_TRENDING_DN,    // Trending bearish: slopes down + EMA2<EMA3<EMA4
   PHASE_EMERGING_UP,    // Emerging bullish: slopes up + EMA4 between EMA2 and EMA3
   PHASE_EMERGING_DN     // Emerging bearish: slopes down + EMA4 between EMA2 and EMA3
};

//+------------------------------------------------------------------+
//| Entry Layer (Pullback-Recovery Detection)                        |
//|                                                                  |
//| Identifies which EMA pair price is pulling back to, based on    |
//| a pullback-recovery pattern. Can be used with ANY bias mode     |
//| (independent of Market Phase).                                   |
//|                                                                  |
//| With 4 active EMAs, we have 3 EMA pairs representing different  |
//| trade aggressiveness levels:                                     |
//|                                                                  |
//| LAYER_1_WEAK (EMA1-EMA2) "Ribbon":                              |
//|   - Shallow pullback to fast EMAs                               |
//|   - Less aggressive entry, tighter stops                        |
//|   - Lower risk, lower reward potential                          |
//|   - Best for: Scalping, quick entries in strong trends          |
//|                                                                  |
//| LAYER_2_MEDIUM (EMA2-EMA3) "Ghost":                             |
//|   - Medium pullback to mid EMAs                                 |
//|   - Moderate entry, balanced stops                              |
//|   - Balanced risk/reward                                        |
//|   - Best for: Swing trading, standard trend setups              |
//|                                                                  |
//| LAYER_3_STRONG (EMA3-EMA4) "Shark":                             |
//|   - Deep pullback to slow EMAs                                  |
//|   - Aggressive entry, wider stops                               |
//|   - Higher risk, higher reward potential                        |
//|   - Best for: Position trading, major trend continuations       |
//|                                                                  |
//| Detection Logic (Pullback-Recovery Pattern):                    |
//|   1. Pullback: EMA_fast slope moves toward EMA_slow (flattens) |
//|   2. Flat:     EMA_fast slope becomes flat (consolidation)     |
//|   3. Recovery: EMA_fast slope resumes trend direction           |
//|   4. Confirm:  Price candle body closes beyond EMA_fast         |
//|                (in bias direction)                              |
//|                                                                  |
//| Return Values from layer check:                                  |
//|    1  = Pullback-recovery detected, matches bias (PASS)         |
//|    0  = No pullback-recovery detected (FAIL)                    |
//|   -1  = Pullback-recovery contradicts bias direction (FAIL)    |
//+------------------------------------------------------------------+
// 260308_PR: Bitfield enum — each layer is a power-of-2 flag so multiple layers
// can be OR-combined into a single value (e.g. L1+L2 = 3, L2+L3 = 6, L1+L2+L3 = 7).
enum EEntryLayer {
   LAYER_NONE          = 0,   // 0b0000 — No layer detected or detection disabled
   LAYER_1_WEAK        = 1,   // 0b0001 — Layer 1: EMA1-EMA2 "Ribbon" zone (shallow pullback)
   LAYER_2_MEDIUM      = 2,   // 0b0010 — Layer 2: EMA2-EMA3 "Ghost" zone (medium pullback)
   LAYER_3_STRONG      = 4,   // 0b0100 — Layer 3: EMA3-EMA4 "Shark" zone (deep pullback)
   LAYER_1_2           = 3,   // 0b0011 — L1 + L2 active simultaneously
   LAYER_2_3           = 6,   // 0b0110 — L2 + L3 active simultaneously
   LAYER_1_2_3         = 7    // 0b0111 — All three layers active simultaneously
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
   STRAT_PRICE_CROSS,
   STRAT_LAYER_DETECTION    // Layer-based pullback detection (Ribbon/Ghost/Shark patterns)
};

enum EEmaRole
{
   ROLE_EMA1,
   ROLE_EMA2,
   ROLE_EMA3,
   ROLE_EMA4
};

// Indicator Modes

// MACD Vote Mode: two-tier architecture (base mode + optional filters)
enum EMacdVoteMode
{
   // === SINGLE CHECKS (persistent) ===
   MACD_ZERO_LINE,        // Main > 0 (bullish momentum zone)
   MACD_HISTOGRAM,        // Histogram > 0 (acceleration)
   MACD_CROSSOVER,        // Main > Signal (momentum shift)

   // === COMBINATION CHECKS (persistent, strict) ===
   MACD_ZERO_AND_CROSS,   // Zero + Crossover (RRM default, industry "traditional")
   MACD_ZERO_AND_HIST,    // Zero + Histogram (strict momentum)
   MACD_TRIPLE,           // Zero + Cross + Hist (ultra-strict)

   // === TIME-LIMITED (fresh signals only) ===
   MACD_CROSSOVER_N,      // Fresh crossover (within N bars)
   MACD_ZERO_CROSS_N      // Fresh zero cross (within N bars)
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
   TRAIL_FRACTAL,
   TRAIL_PSAR_FLIP_EXIT,    // NEW: Close position when PSAR flips
   TRAIL_FIXED_PIPS,        // NEW: Fixed pips trailing stop
   TRAIL_BREAKEVEN,         // NEW: Trail to breakeven then fixed pips
   TRAIL_PROFIT_PERCENT     // NEW: Trail after profit % threshold
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

//+------------------------------------------------------------------+
//| Stop Loss Strategy Mode (new; ATR-optional, strategy-based)      |
//| Defines how SL distance is calculated in GetStopLossPips()       |
//+------------------------------------------------------------------+
enum ESLMode
{
   SL_MODE_FIXED_PIPS,    // Fixed pips (default, ATR-independent)
   SL_MODE_ATR,           // ATR-based (optional, requires UseATRforSL=true)
   SL_MODE_PERCENT,       // Percentage of entry price
   SL_MODE_SWING,         // Based on recent swing high/low (SwingLookback bars)
   SL_FRACTAL,            // NEW: Last fractal level (Bill Williams)
   SL_PSAR_DOT            // NEW: PSAR dot position
};

//+------------------------------------------------------------------+
//| Take Profit Strategy Mode (new; ATR-optional, strategy-based)    |
//| Defines how TP distance is calculated in GetTakeProfitPips()     |
//+------------------------------------------------------------------+
enum ETPMode
{
   TP_MODE_FIXED_PIPS,    // Fixed pips (default)
   TP_MODE_RR,            // Risk:Reward ratio (TP = SL distance × RRRatio)
   TP_MODE_ATR,           // ATR-based (optional, requires UseATRforTP=true)
   TP_FRACTAL,            // NEW: Next fractal level as TP target
   TP_PSAR_FLIP,          // NEW: Exit when PSAR flips (TP handled by TM)
   TP_NONE                // NEW: No TP, rely on trailing stop only
};

//+------------------------------------------------------------------+
//| Trailing Stop Trigger Condition (NEW: Phase 2.2)                 |
//| Determines when trailing stop activation begins                   |
//+------------------------------------------------------------------+
enum ETrailTrigger
{
   TRIGGER_IMMEDIATE,       // Trail from entry (default)
   TRIGGER_BREAKEVEN,       // Trail after breakeven threshold reached
   TRIGGER_PROFIT_PIPS,     // Trail after X pips profit (TrailDistancePips)
   TRIGGER_PROFIT_PERCENT,  // Trail after X% profit (TrailProfitPercent)
   TRIGGER_PSAR_ALIGN       // Trail when PSAR aligns with position direction
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

// --- ADAPTIVE SETTINGS: PAIR TYPE ---
enum EPairType
{
   PAIR_TYPE_AUTO,           // Auto-detect from symbol name
   PAIR_TYPE_MAJOR,          // EUR/USD, GBP/USD, etc (tight spreads 1-2 pips)
   PAIR_TYPE_MINOR,          // EUR/GBP, EUR/AUD, etc (medium spreads 2-4 pips)
   PAIR_TYPE_EXOTIC,         // USD/TRY, USD/ZAR, etc (wide spreads 5-15 pips)
   PAIR_TYPE_GOLD,           // XAU/USD (medium spreads 3-5 pips, high volatility)
   PAIR_TYPE_CRYPTO          // BTC/USD (very wide spreads, extreme volatility)
};

// --- ADAPTIVE SETTINGS: TIMEFRAME SCALING MODE ---
enum ETFScaling
{
   TF_SCALE_AUTO,            // Auto-detect from chart timeframe
   TF_SCALE_MANUAL           // User provides base values directly (no auto-scale)
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

   // ATR limits scaling mode and base values (pips at M15 reference)
   ETFScaling ATR_Mode;
   double ATR_Min_Base;
   double ATR_Max_Base;

   // Adaptive SL/TP base distances (pips at M15 reference)
   double SL_Base;
   double TP_Base;
   bool   UseSL;
   bool   UseTP;

   // Adaptive trailing stop cushion base distance (pips at M15 reference)
   double TrailCushion_Base;
   bool   UseTrailCushion;

   // PSAR trail cushion (adaptive)
   double PsarCushion_Pips;      // Fixed pips cushion (when PsarUseATR=false)
   bool   PsarUseATR;            // Use ATR multiplier instead of fixed pips
   double PsarATR_Multiplier;    // PSAR cushion as fraction of ATR (when PsarUseATR=true)
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

   // SL - Initial SL Placement
   ESlPlacementMode SL_PlacementMode;
   double           SL_Mult;
   double           SL_PsarPipsCushion;
   double           SL_SwingPipsCushion;
   double           SL_FixedPips;

   // SL/TP Strategy Configuration (new; ATR-optional, strategy-based)
   ESLMode  SLMode;           // How to calculate SL distance (new strategy enums)
   ETPMode  TPMode;           // How to calculate TP distance (new strategy enums)
   double   FixedTPPips;      // Fixed TP distance in pips (TP_MODE_FIXED_PIPS)
   bool     UseATRforSL;      // Enable ATR-based SL (SL_MODE_ATR only)
   bool     UseATRforTP;      // Enable ATR-based TP (TP_MODE_ATR only)
   double   SLPercent;        // SL as % of entry price (SL_MODE_PERCENT, e.g. 0.5 = 0.5%)
   double   RRRatio;          // Risk:Reward ratio (TP_MODE_RR, e.g. 2.0 = 1:2)
   int      SwingLookback;    // Bars to look back for swing high/low (SL_MODE_SWING)

   // === Fractal Settings (NEW: Phase 2.2) ===
   int      FractalPeriod;        // Fractal indicator period (default: 5)
   int      TPFractalOffset;      // How many fractals ahead for TP (default: 1)

   // === PSAR SL/TP Settings (NEW: Phase 2.2) ===
   double   PSARStep;             // PSAR step for SL/TP calculations (default: 0.02)
   double   PSARMax;              // PSAR max for SL/TP calculations (default: 0.2)

   // === Advanced Trailing Settings (NEW: Phase 2.2) ===
   ETrailTrigger TrailTrigger;       // When to begin trailing (default: TRIGGER_IMMEDIATE)
   double   TrailDistancePips;       // Fixed trail distance in pips (TRAIL_FIXED_PIPS / trigger threshold)
   double   TrailATRMultiplier;      // ATR multiplier for trail distance (TRAIL_ATR mode)
   double   BEThresholdPips;         // Profit pips required before moving to breakeven
   double   TrailProfitPercent;      // Profit % threshold for TRIGGER_PROFIT_PERCENT
   double   TrailStepPips;           // Minimum pips movement before updating SL
   bool     TrailLockProfit;         // Lock in profit (never move SL backwards)

   // TS - Trailing SL / TP / BE
   double              TP_Mult;
   bool                Use_BE;
   double              BE_Trig;
   double              BE_Buff;
   ETrailingMode       TrailMode;
   double              Trail_Mult;
   EPsarTrailCushionMode PSAR_TrailCushionMode;
   double              PSAR_TrailPipsCushion;
   int                 PSAR_TrailDelay;         // PSAR trailing bar-shift delay (1-3)

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
   int         Vote_EvalShift;          // Shift for vote evaluation
   bool        Vote_AllowPsarFlip;      // Allow PSAR flip signal in votes
   // PSAR flip validation parameters (when Vote_AllowPsarFlip=true)
   int         Vote_PsarFlipDelay;      // Bars countdown after flip (0-10)

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

   // Adaptive settings (pair-aware spread, TF-aware ATR/SL/TP/trail)
   ST_AdaptiveSettings Adaptive;

   // RRM Drawdown Protection (§6)
   bool     RRM_EnableDrawdownProtection;
   int      RRM_MaxConsecutiveLosses;
   int      RRM_MaxTradesPerDay;
   double   RRM_MaxDailyDrawdownPct;


   //==========================================================================
   // 260304_PR1: PHASE DETECTION SETTINGS (Foundation - Not used yet)
   //==========================================================================
   bool     PhaseDetectionEnabled;         // Master switch for phase system (default: false)
   bool     BlockUnorderedPhase;           // Block trades during UNORDERED phase
   bool     RequireMinPhaseConfirm;        // Require N consecutive bars in same phase
   int      MinPhaseConfirmBars;           // Minimum bars to confirm phase stability (e.g., 3)
   
   // Phase-specific trade permissions (for future use in PRESET_RRM and PRESET_CUSTOM)
   bool     Emerging_AllowWeakTrades;      // EMERGING phase: Allow EMA1/EMA2 entries (shallow pullbacks)
   bool     Emerging_AllowMediumTrades;    // EMERGING phase: Allow EMA2/EMA3 entries (medium pullbacks)
   bool     Emerging_AllowStrongTrades;    // EMERGING phase: Allow EMA3/EMA4 entries (deep pullbacks)
   
   bool     Trending_AllowWeakTrades;      // TRENDING phase: Allow EMA1/EMA2 entries
   bool     Trending_AllowMediumTrades;    // TRENDING phase: Allow EMA2/EMA3 entries
   bool     Trending_AllowStrongTrades;    // TRENDING phase: Allow EMA3/EMA4 entries

   //==========================================================================
   // 260304_PR3: LAYER DETECTION SETTINGS
   //==========================================================================
   bool     EnableLayerDetection;          // Master switch for multi-layer pullback detection
   double   LayerTouchTolerancePips;       // Pip tolerance for EMA touch detection (legacy)
   double   LayerTouchTolerance;           // Percentage tolerance for EMA touch detection (e.g. 0.01 = 1%)
   bool     AllowLayer1_Entries;           // Allow Layer 1 (EMA1/EMA2 touch) entries
   bool     AllowLayer2_Entries;           // Allow Layer 2 (EMA2/EMA3 touch) entries
   bool     AllowLayer3_Entries;           // Allow Layer 3 (EMA3/EMA4 touch) entries

   //==========================================================================
   // DIAGNOSTICS: STATISTICS CONFIGURATION
   //==========================================================================
   bool Stats_TrackRejections;  // Track rejection counts per indicator
   bool Stats_TrackPasses;      // Track pass counts (positive stats)
   bool Stats_FullEvaluation;   // Evaluate ALL indicators per bar (no early exit)
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
input bool           Inp_DebugFlow              = true;         // (Global; allowed under presets) Print OnInit/OnTick/OnDeinit flow

input group "════════════════════════════════════════════"
input group "  DIAGNOSTICS: STATISTICS CONFIGURATION"
input group "════════════════════════════════════════════"
input bool Inp_Stats_TrackRejections = true;   // Track rejection counts
input bool Inp_Stats_TrackPasses = true;       // Track pass counts (positive stats)
input bool Inp_Stats_FullEvaluation = true;    // Evaluate ALL indicators per bar (no early exit)
input string Inp_Stats_Info1 = "FullEvaluation=false: waterfall (stop at first fail)"; // Info
input string Inp_Stats_Info2 = "FullEvaluation=true: evaluate all, identify true bottlenecks"; // Info

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
input group "═══ 🔧 STEP 1: Bias Calculation ═══"
input string         Inp_Step1_Info             = "Configure major trend detection"; // Info
input bool           Inp_BiasEnabled            = true;              // (CUSTOM; presets override) Enable market bias filter
input EBiasMode      Inp_BiasMode               = BIAS_AUTO_PHASE;   // (CUSTOM; presets override) Bias mode (AUTO/MANUAL)
input int            Inp_BiasFastID             = 2;                 // (CUSTOM; presets override) Bias Fast EMA (0=EMA1/5, 1=EMA2/13, 2=EMA3/34, 3=EMA4/89)
input int            Inp_BiasSlowID             = 3;                 // (CUSTOM; presets override) Bias Slow EMA (0=EMA1/5, 1=EMA2/13, 2=EMA3/34, 3=EMA4/89)
input EManualSide    Inp_ManualSide             = SIDE_BOTH;         // (CUSTOM; presets override) Manual direction (BOTH/LONG/SHORT)
input EMaMethod      Inp_MaType                 = METHOD_EMA;        // (CUSTOM; presets override) MA method (EMA/SMA)
input int            Inp_MaHorShift             = 0;                 // (CUSTOM; presets override) MA horizontal shift (bars)
input int            Inp_MaVerShift             = 1;                 // (CUSTOM; presets override) MA vertical shift (pips)
input int            InpEma1Period              = 5;                 // (CUSTOM; presets override) EMA1 period
input int            InpEma2Period              = 13;                // (CUSTOM; presets override) EMA2 period
input int            InpEma3Period              = 34;                // (CUSTOM; presets override) EMA3 period (RRM bias fast)
input int            InpEma4Period              = 89;                // (CUSTOM; presets override) EMA4 period (RRM bias slow)

// ── Step 2: Entry Signal ─────────────────────────────────────────────
input group "═══ 🔧 STEP 2: Entry Signal ═══"
input string         Inp_Step2_Info             = "Configure entry timing strategy"; // Info
input EAutoStrategy  Inp_AutoStrat              = STRAT_PAIR_CROSS;  // (CUSTOM; presets override) Entry strategy (price cross / pair cross)
input double         Inp_LayerTolerance         = 0.01;             // (CUSTOM; presets override) Layer touch tolerance (%, e.g. 0.01=1%; used by STRAT_LAYER_DETECTION)
input ERRMMode       Inp_RRM_Mode               = RRM_AUTO_BY_TF; // (RRM presets) RRM mode (AUTO uses timeframe mapping)
input bool           Inp_RRM_EnableInCustom     = false;          // (CUSTOM only) Enable RRM logic while using PRESET_CUSTOM
input bool           Inp_CloseOnReverse         = false;          // (CUSTOM; presets may override) Close on reverse signal
input EExitProfile   Inp_ExitProfile            = EXIT_PROFILE_LEGACY; // (CUSTOM; presets override) Exit profile (strict presets force strict)

// ── Step 5: Structure Gate (Multi-layer pullback) ─────────────────────
input group "═══ 🔧 STEP 5: Structure Gate (Pullback) ═══"
input string         Inp_Step5_Info             = "Configure pullback-recovery detection"; // Info
input bool           Inp_Gate_UseMultiLayer         = false;      // (CUSTOM; presets override) Enable multi-layer cascading EMA pullback detection
input bool           Inp_Gate_RequirePullback        = false;      // (CUSTOM; presets override) Enable pullback gate
input int            Inp_Gate_PullbackLookback       = 15;         // (CUSTOM; presets override) Pullback search bars
input bool           Inp_Gate_RequireRecoveryMomentum = false;     // (CUSTOM; presets override) Require bullish/bearish candle (recovery momentum)
input int            Inp_RRM_Lookback           = 5;              // (CUSTOM; presets override) Pullback lookback bars
input double         Inp_RRM_MinDivPips         = 0.5;            // (CUSTOM; presets override) Min EMA divergence (pips)

// ── Step 6: Indicator Voting ──────────────────────────────────────────
input group "═══ 🔧 STEP 6: Voting Configuration ═══"
input string         Inp_Step6_Info             = "Configure multi-indicator consensus (ALL enabled must pass)"; // Info
input bool           Inp_VoteMode_All           = true;                 // (CUSTOM; presets override) Vote mode: TRUE=all must agree (recommended), FALSE=threshold

input group "═══ 📊 Indicator: EmaSig ═══"
input bool           Inp_Ind_EmaSig_Enabled     = true;                // [EmaSig] Enable EMA signal vote
input int            Inp_Ind_EmaSig_Weight      = 1;                   // [EmaSig] Vote weight
input string         Inp_Ind_EmaSig_Info        = "Price position vs EMA1"; // [EmaSig] Description

input group "═══ 📊 Indicator: ADX ═══"
input bool           Inp_Ind_Adx_Enabled        = false;               // [ADX] Enable ADX vote
input int            Inp_Ind_Adx_Weight         = 1;                   // [ADX] Vote weight
input string         Inp_Ind_Adx_Info           = "Trend strength filter"; // [ADX] Description
input int            Inp_Ind_Adx_Period         = 14;                  // [ADX] Period
input int            Inp_Ind_Adx_Threshold      = 20;                  // [ADX] Threshold

input group "═══ 📊 Indicator: MACD ═══"
input bool           Inp_Ind_Macd_Enabled       = true;                // [MACD] Enable MACD vote
input int            Inp_Ind_Macd_Weight        = 1;                   // [MACD] Vote weight

input group "=== MACD: BASE MODE (Choose ONE) ==="
input EMacdVoteMode  Inp_MacdVoteMode           = MACD_ZERO_AND_CROSS; // MACD base mode

input group "=== MACD: ADVANCED FILTERS (Optional Add-Ons) ==="
input string         Inp_MacdFilterInfo         = "Enable filters below to add requirements to base mode";  // [Info]
input bool           Inp_MacdRequireSlope       = false;  // ✓ Add: Require MACD rising/falling (momentum acceleration)
input bool           Inp_MacdRequireDivergence  = false;  // ✓ Add: Require price/MACD divergence (reversal signal)
input bool           Inp_MacdRequireHook        = false;  // ✓ Add: Require histogram flip (early reversal)

input group "=== MACD: PARAMETERS ==="
input int            Inp_P_MacdFast             = 8;      // MACD Fast EMA period
input int            Inp_P_MacdSlow             = 13;     // MACD Slow EMA period
input int            Inp_P_MacdSig              = 8;      // MACD Signal SMA period
input int            Inp_MacdFreshBars          = 3;      // Fresh signal validity (for _N modes, 0=disabled)
input double         Inp_MacdSlopeMin           = 0.00001; // Min slope change per bar (0=disabled, smaller = more permissive)

input group "=== MACD: HELP ==="
input string         Inp_MacdHelp1              = "BASE MODE: Select primary logic from dropdown above";            // Line 1
input string         Inp_MacdHelp2              = "FILTERS: Check boxes to add extra requirements";                 // Line 2
input string         Inp_MacdHelp3              = "Example: ZERO_LINE + Slope = Main>0 AND rising";                // Line 3
input string         Inp_MacdHelp4              = "Example: CROSSOVER_N + Divergence = Fresh cross + bullish div"; // Line 4

input group "═══ 📊 Indicator: RSI ═══"
input bool           Inp_Ind_Rsi_Enabled        = false;               // [RSI] Enable RSI vote
input int            Inp_Ind_Rsi_Weight         = 1;                   // [RSI] Vote weight
input string         Inp_Ind_Rsi_Info           = "Relative Strength Index"; // [RSI] Description
input ERsiMode       Inp_Ind_Rsi_Mode           = RSI_FILTER_EXTREME;  // [RSI] Mode
input int            Inp_Ind_Rsi_Period         = 14;                  // [RSI] Period
input double         Inp_Ind_Rsi_OB             = 70.0;                // [RSI] Overbought level
input double         Inp_Ind_Rsi_OS             = 30.0;                // [RSI] Oversold level

input group "═══ 📊 Indicator: CCI ═══"
input bool           Inp_Ind_Cci_Enabled        = true;                // [CCI] Enable CCI vote
input int            Inp_Ind_Cci_Weight         = 1;                   // [CCI] Vote weight
input string         Inp_Ind_Cci_Info           = "Commodity Channel Index"; // [CCI] Description
input ECciMode       Inp_Ind_Cci_Mode           = CCI_TREND_ZERO;      // [CCI] Mode
input int            Inp_Ind_Cci_Period         = 14;                  // [CCI] Period

input group "═══ 📊 Indicator: MFI ═══"
input bool           Inp_Ind_Mfi_Enabled        = false;               // [MFI] Enable MFI vote
input int            Inp_Ind_Mfi_Weight         = 1;                   // [MFI] Vote weight
input string         Inp_Ind_Mfi_Info           = "Money Flow Index"; // [MFI] Description
input int            Inp_Ind_Mfi_Period         = 14;                  // [MFI] Period
input double         Inp_Ind_Mfi_Level          = 50.0;                // [MFI] Threshold/level

input group "═══ 📊 Indicator: Stochastic ═══"
input bool           Inp_Ind_Sto_Enabled        = false;               // [Stoch] Enable Stochastic vote
input int            Inp_Ind_Sto_Weight         = 1;                   // [Stoch] Vote weight
input string         Inp_Ind_Sto_Info           = "Stochastic oscillator"; // [Stoch] Description
input EStochMode     Inp_Ind_Sto_Mode           = STO_ZONE_FILTER;     // [Stoch] Mode
input int            Inp_Ind_Sto_K              = 5;                   // [Stoch] %K period
input int            Inp_Ind_Sto_D              = 3;                   // [Stoch] %D period
input int            Inp_Ind_Sto_Slow           = 3;                   // [Stoch] Slowing

input group "═══ 📊 Indicator: Bollinger ═══"
input bool           Inp_Ind_Bb_Enabled         = false;               // [BB] Enable Bollinger Bands vote
input int            Inp_Ind_Bb_Weight          = 1;                   // [BB] Vote weight
input string         Inp_Ind_Bb_Info            = "Bollinger Bands channel"; // [BB] Description
input EBbMode        Inp_Ind_Bb_Mode            = BB_TREND_FOLLOW;     // [BB] Mode
input int            Inp_Ind_Bb_Period          = 20;                  // [BB] Period
input double         Inp_Ind_Bb_Dev             = 2.0;                 // [BB] Deviation

input group "═══ 📊 Indicator: PSAR ═══"
input bool           Inp_Ind_Psar_Enabled       = true;                // [PSAR] Enable PSAR vote
input int            Inp_Ind_Psar_Weight        = 1;                   // [PSAR] Vote weight
input string         Inp_Ind_Psar_Info          = "Parabolic SAR position"; // [PSAR] Description
input double         Inp_Ind_Psar_Step          = 0.05;                // [PSAR] Step
input double         Inp_Ind_Psar_Max           = 0.5;                 // [PSAR] Maximum
input int            Inp_Vote_PsarFlipDelay     = 2;                   // [PSAR] Bars flip remains valid (0-10; FLIP mode only)

input group "═══ 📊 Indicator: Pattern123 ═══"
input bool           Inp_Ind_P123_Enabled       = false;               // [P123] Enable 1-2-3 pattern vote
input int            Inp_Ind_P123_Weight        = 1;                   // [P123] Vote weight
input string         Inp_Ind_P123_Info          = "1-2-3 fractal breakout pattern"; // [P123] Description

input group "═══ 📊 Indicator: Ross Hook ═══"
input bool           Inp_Ind_Ross_Enabled       = false;               // [Ross] Enable Ross hook vote
input int            Inp_Ind_Ross_Weight        = 1;                   // [Ross] Vote weight
input string         Inp_Ind_Ross_Info          = "Ross hook trend momentum"; // [Ross] Description

input group "═══ 📊 TEMPLATE: Add Custom Indicator ═══"
input string         Inp_Ind_Template_Info      = "Copy a section above to add custom indicators"; // Instructions

// ── Step 9: Risk & Execution ──────────────────────────────────────────
input group "--- ℹ️ Step 9: Risk & Execution (SL, TP, trailing) ---"
input double         Inp_RiskPercent            = 2.0;    // (CUSTOM; presets may override) Risk per trade (%)

input group "--- ℹ️ Step 9 · Initial SL Placement ---"
input ESlPlacementMode Inp_SL_PlacementMode     = SL_SWING_HIGHLOW;    // (CUSTOM; presets override) SL placement method
input double         Inp_SL_Mult                = 1.5;                 // (CUSTOM; presets override) SL multiplier (ATR modes only; ignored in strict)
input double         Inp_SL_PsarPipsCushion     = 5.0;                 // (CUSTOM; presets override) SL PSAR cushion (pips)
input double         Inp_SL_SwingPipsCushion    = 10.0;                // (CUSTOM; presets override) SL swing cushion (pips)
input double         Inp_SL_FixedPips           = 20.0;                // (CUSTOM; presets override) SL fixed distance (pips)

input group "--- ℹ️ Step 9 · SL/TP Strategy (ATR-optional) ---"
input ESLMode        Inp_SLMode                 = SL_MODE_FIXED_PIPS; // (CUSTOM) SL strategy mode (SL_MODE_FIXED_PIPS by default)
input ETPMode        Inp_TPMode                 = TP_MODE_RR;         // (CUSTOM) TP strategy mode (TP_MODE_RR by default)
input double         Inp_FixedTPPips            = 40.0;               // (CUSTOM) Fixed TP distance in pips (TP_MODE_FIXED_PIPS only)
input bool           Inp_UseATRforSL            = false;              // (CUSTOM) Enable ATR-based SL (SL_MODE_ATR only)
input bool           Inp_UseATRforTP            = false;              // (CUSTOM) Enable ATR-based TP (TP_MODE_ATR only)
input double         Inp_SLPercent              = 0.5;                // (CUSTOM) SL as % of entry price (SL_MODE_PERCENT only)
input double         Inp_RRRatio                = 2.0;                // (CUSTOM) Risk:Reward ratio (TP_MODE_RR only)
input int            Inp_SwingLookback          = 20;                 // (CUSTOM) Swing high/low lookback bars (SL_MODE_SWING only)

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
input int            Inp_PSAR_TrailDelay        = 1;             // PSAR trailing delay (bar shift: 1-3; 1=last confirmed bar)
input double         Inp_PSAR_TrailCushionATR   = 0.2;                 // (CUSTOM; presets override) PSAR trail cushion (ATR)

input group "--- ℹ️ Step 9 · Fractal SL/TP (Phase 2.2) ---"
input int            Inp_FractalPeriod          = 5;                   // (CUSTOM) Fractal period for SL/TP (SL_FRACTAL / TP_FRACTAL)
input int            Inp_TPFractalOffset        = 1;                   // (CUSTOM) Fractal offset for TP (1=nearest fractal)

input group "--- ℹ️ Step 9 · PSAR SL/TP (Phase 2.2) ---"
input double         Inp_PSARStep               = 0.02;                // (CUSTOM) PSAR step for SL/TP (SL_PSAR_DOT / TP_PSAR_FLIP)
input double         Inp_PSARMax                = 0.2;                 // (CUSTOM) PSAR max for SL/TP

input group "--- ℹ️ Step 9 · Advanced Trailing Trigger (Phase 2.2) ---"
input ETrailTrigger  Inp_TrailTrigger           = TRIGGER_IMMEDIATE;   // (CUSTOM) When to start trailing
input double         Inp_TrailDistancePips      = 15.0;                // (CUSTOM) Fixed trail distance pips / profit trigger pips
input double         Inp_TrailATRMultiplier     = 1.5;                 // (CUSTOM) ATR multiplier for TRAIL_ATR mode
input double         Inp_BEThresholdPips        = 10.0;                // (CUSTOM) Pips profit needed before breakeven (TRIGGER_BREAKEVEN)
input double         Inp_TrailProfitPercent     = 1.0;                 // (CUSTOM) Profit % to trigger trailing (TRIGGER_PROFIT_PERCENT)
input double         Inp_TrailStepPips          = 5.0;                 // (CUSTOM) Minimum pips to move SL each step
input bool           Inp_TrailLockProfit        = true;                // (CUSTOM) Never move SL backwards (lock profit)

input group "--- ℹ️ Benchmark: MT5 Moving Average ---"
input double         Inp_MA_MaximumRiskPct      = 0.02;         // (PRESET_MA_BENCHMARK only) Max risk (%) for MA benchmark sizer
input double         Inp_MA_DecreaseFactor      = 3.0;          // (PRESET_MA_BENCHMARK only) Lot decrease factor
input int            Inp_MA_Period              = 12;           // (PRESET_MA_BENCHMARK only) MA period
input int            Inp_MA_Shift               = 6;            // (PRESET_MA_BENCHMARK only) MA shift

// ════════════════════════════════════════════════════════════════════
// 🔧 ZONE 3C — ADAPTIVE SETTINGS  (auto-scale by pair type & timeframe)
// These settings let the EA adapt spread limits, ATR gates, SL/TP distances,
// and trail cushions to the current pair and timeframe automatically.
// When pair type is AUTO, it is detected from the symbol name at init.
// When TF scaling is AUTO, all base values are multiplied by the TF factor.
// ════════════════════════════════════════════════════════════════════
input group "══════════ 🔧 ZONE 3C: ADAPTIVE SETTINGS (auto-scale by pair & timeframe) ══════════"

input group "═══ 🔧 Adaptive: Pair Type Detection ═══"
input EPairType      Inp_Adaptive_PairType      = PAIR_TYPE_AUTO; // Pair type (AUTO detects from symbol name)
input string         Inp_Adaptive_PairInfo      = "AUTO: EURUSD/GBPUSD/USDJPY=MAJOR; XAUUSD/GOLD=GOLD; BTC/ETH=CRYPTO; TRY/ZAR/MXN=EXOTIC; others=MINOR"; // Pair detection reference

input group "═══ 🔧 Adaptive: Spread Limits (by pair type) ═══"
input double         Inp_Adaptive_Spread_Major  = 2.0;           // Max spread for major pairs (pips)
input double         Inp_Adaptive_Spread_Minor  = 4.0;           // Max spread for minor pairs (pips)
input double         Inp_Adaptive_Spread_Exotic = 10.0;          // Max spread for exotic pairs (pips)
input double         Inp_Adaptive_Spread_Gold   = 5.0;           // Max spread for gold/XAU (pips)
input double         Inp_Adaptive_Spread_Crypto = 50.0;          // Max spread for crypto (pips)

input group "═══ 🔧 Adaptive: ATR Limits (by timeframe) ═══"
input ETFScaling     Inp_Adaptive_ATR_Mode      = TF_SCALE_AUTO; // ATR scaling mode (AUTO scales base values by TF multiplier)
input double         Inp_Adaptive_ATR_Min_Base  = 5.0;           // Base min ATR for M15 (pips; 0=off)
input double         Inp_Adaptive_ATR_Max_Base  = 20.0;          // Base max ATR for M15 (pips; 0=off)
input string         Inp_Adaptive_ATR_Info      = "AUTO scales: M1×0.5, M5×0.67, M15×1.0, M30×1.5, H1×2, H4×4, D1×8, W1×24"; // Scaling reference

input group "═══ 🔧 Adaptive: SL/TP Distance (by timeframe) ═══"
input double         Inp_Adaptive_SL_Base       = 20.0;          // Base SL distance for M15 (pips)
input double         Inp_Adaptive_TP_Base       = 40.0;          // Base TP distance for M15 (pips)
input bool           Inp_Adaptive_UseSL         = false;         // Apply adaptive SL (overrides SL_FixedPips when enabled)
input bool           Inp_Adaptive_UseTP         = false;         // Apply adaptive TP (sets TP distance when enabled)

input group "═══ 🔧 Adaptive: Trail Stop Cushion (by timeframe) ═══"
input double         Inp_Adaptive_TrailCushion_Base = 5.0;       // Base trail cushion for M15 (pips)
input bool           Inp_Adaptive_UseTrailCushion   = false;     // Apply adaptive trail cushion (replaces manual PSAR pips cushion)

input group "═══ 🔧 Adaptive: PSAR Trail Cushion (by volatility) ═══"
input double         Inp_Adaptive_PsarCushion_Pips  = 3.0;       // PSAR trail cushion when not using ATR mode (pips)
input bool           Inp_Adaptive_PsarUseATR         = false;    // Use ATR multiplier for PSAR cushion instead of fixed pips
input double         Inp_Adaptive_PsarATR_Multiplier = 0.5;      // PSAR cushion as fraction of ATR (e.g. 0.5 = half ATR)

// ════════════════════════════════════════════════════════════════════
// 🔓 ZONE 3B — ADMIN OVERRIDE  (preset testing for experienced users)
// Set Inp_AdminOverridePreset=true to activate §1–§5 override fields.
// Has no effect in PRESET_CUSTOM mode (all inputs already respected).
// ════════════════════════════════════════════════════════════════════
input group "══════════ 🔓 ZONE 3B: ADMIN OVERRIDE (set true to activate §1-§5 below) ══════════"
input bool           Inp_AdminOverridePreset        = false; // [Admin] Unlock preset parameters for testing (true=admin mode, false=normal user)
input string         _admin_info1                   = "OFF: Inp_Override_* inputs IGNORED (preset used)"; // [Info] Admin OFF behaviour
input string         _admin_info2                   = "ON:  Inp_Override_* inputs REPLACE preset values"; // [Info] Admin ON behaviour
input string         _admin_info3                   = "";                                                  // [Info] Spacer
input string         _admin_scope1                  = "Overridable: Bias, Phase, Layer, Indicators";       // [Info] Overridable settings scope
input string         _admin_scope2                  = "NOT overridable: Adaptive (use Zone 2)";            // [Info] Non-overridable scope

input group "════════════════════════════════════════════"
input group "  🔓 ADMIN OVERRIDE: §1 Strategy, EMAs & Votes"
input group "════════════════════════════════════════════"
input EAutoStrategy  Inp_Override_AutoStrat          = STRAT_PAIR_CROSS; // [Admin] Override AutoStrat when AdminOverride=true
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
input bool           Inp_Override_RequirePullback            = false;     // [Admin] Override RequirePullback when AdminOverride=true
input int            Inp_Override_PullbackLookback           = 10;        // [Admin] Override PullbackLookback when AdminOverride=true
input bool           Inp_Override_RequireRecoveryMomentum    = false;     // [Admin] Override RequireRecoveryMomentum when AdminOverride=true
input bool           Inp_Override_UseMultiLayer              = true;      // [Admin] Override UseMultiLayer (cascading EMA pullback) when AdminOverride=true

input group "════════════════════════════════════════════"
input group "  🔓 ADMIN OVERRIDE: §2 Indicator Parameters"
input group "════════════════════════════════════════════"
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

input group "════════════════════════════════════════════"
input group "  🔓 ADMIN OVERRIDE: §3 Risk & Entry"
input group "════════════════════════════════════════════"
input bool                Inp_Override_RequirePriceCross     = false;     // [Admin] Override RequirePriceCross when AdminOverride=true
input bool                Inp_Override_UseHTF                = false;     // [Admin] Override HTF filter enabled when AdminOverride=true
input bool                Inp_Override_CloseOnReverse        = true;      // [Admin] Override CloseOnReverse when AdminOverride=true
input double              Inp_Override_RiskPercent           = 2.0;       // [Admin] Override RiskPercent (%) when AdminOverride=true
input ESlPlacementMode    Inp_Override_SL_PlacementMode      = SL_ATR;    // [Admin] Override SL placement mode when AdminOverride=true
input double              Inp_Override_SL_Mult               = 1.5;       // [Admin] Override SL ATR multiplier when AdminOverride=true
input double              Inp_Override_SL_PsarPipsCushion    = 5.0;       // [Admin] Override SL PSAR cushion (pips) when AdminOverride=true
input double              Inp_Override_SL_SwingPipsCushion   = 10.0;      // [Admin] Override SL swing cushion (pips) when AdminOverride=true

input group "════════════════════════════════════════════"
input group "  🔓 ADMIN OVERRIDE: §4 Exits & Trailing"
input group "════════════════════════════════════════════"
input double              Inp_Override_TP_Mult               = 3.0;       // [Admin] Override TP multiplier when AdminOverride=true
input bool                Inp_Override_Use_BE                = false;      // [Admin] Override breakeven enabled when AdminOverride=true
input double              Inp_Override_BE_Trig               = 1.0;       // [Admin] Override BE trigger (R-multiple) when AdminOverride=true
input double              Inp_Override_BE_Buff               = 0.1;       // [Admin] Override BE buffer (pips) when AdminOverride=true
input ETrailingMode       Inp_Override_TrailMode             = TRAIL_NONE; // [Admin] Override trailing stop mode when AdminOverride=true
input double              Inp_Override_Trail_Mult            = 1.5;       // [Admin] Override trail ATR multiplier when AdminOverride=true
input EPsarTrailCushionMode Inp_Override_PSAR_TrailCushionMode = PSAR_CUSHION_PIPS; // [Admin] Override PSAR trail cushion mode when AdminOverride=true
input double              Inp_Override_PSAR_TrailPipsCushion = 5.0;       // [Admin] Override PSAR trail cushion (pips) when AdminOverride=true

input group "════════════════════════════════════════════"
input group "  🔓 ADMIN OVERRIDE: $5 Phase Settings"
input group "════════════════════════════════════════════"
input bool     Inp_Override_PhaseDetectionEnabled   = true;    // [Admin] Enable phase detection when AdminOverride=true
input bool     Inp_Override_BlockUnorderedPhase     = true;    // [Admin] Block all trades in UNORDERED phase when AdminOverride=true
input bool     Inp_Override_RequireMinPhaseConfirm  = true;    // [Admin] Require min-bar phase confirmation when AdminOverride=true
input int      Inp_Override_MinPhaseConfirmBars     = 0;       // [Admin] Min bars to confirm phase stability (0=instant, 1-10=delay) when AdminOverride=true

input group "════════════════════════════════════════════"
input group "  🔓 ADMIN OVERRIDE: $6 Layer Settings"
input group "════════════════════════════════════════════"
input bool     Inp_Override_EnableLayerDetection    = true;    // [Admin] Enable layer filtering when AdminOverride=true

input group "════════════════════════════════════════════"
input group "  🔓 ADMIN OVERRIDE: $6.1 Layer 1 (Weak/EMA1-EMA2)"
input group "════════════════════════════════════════════"
input bool     Inp_Override_Layer1_AllowTrending    = true;    // [Admin] Layer 1: Allow TRENDING phase when AdminOverride=true
input bool     Inp_Override_Layer1_AllowEmerging    = true;    // [Admin] Layer 1: Allow EMERGING phase when AdminOverride=true

input group "════════════════════════════════════════════"
input group "  🔓 ADMIN OVERRIDE: $6.2 Layer 2 (Medium/EMA2-EMA3)"
input group "════════════════════════════════════════════"
input bool     Inp_Override_Layer2_AllowTrending    = true;    // [Admin] Layer 2: Allow TRENDING phase when AdminOverride=true
input bool     Inp_Override_Layer2_AllowEmerging    = true;    // [Admin] Layer 2: Allow EMERGING phase when AdminOverride=true

input group "════════════════════════════════════════════"
input group "  🔓 ADMIN OVERRIDE: $6.3 Layer 3 (Strong/EMA3-EMA4)"
input group "════════════════════════════════════════════"
input bool     Inp_Override_Layer3_AllowTrending    = true;    // [Admin] Layer 3: Allow TRENDING phase when AdminOverride=true
input bool     Inp_Override_Layer3_AllowEmerging    = false;   // [Admin] Layer 3: Allow EMERGING phase when AdminOverride=true

//══════════════════════════════════════════════════════════════════════════════
// 🔓 ZONE 3B: ADMIN OVERRIDE (§6 — RRM Drawdown Protection)
//══════════════════════════════════════════════════════════════════════════════

input group "════════════════════════════════════════════"
input group "  🔓 ADMIN OVERRIDE: $7 RRM Drawdown Protection"
input group "════════════════════════════════════════════"
input bool   Inp_RRM_EnableDrawdownProtection = false;  // [Admin] Enable DD protection
input int    Inp_RRM_MaxConsecutiveLosses     = 5;      // [Admin] Pause after X consecutive losses
input int    Inp_RRM_MaxTradesPerDay          = 15;     // [Admin] Max trades per day (0=unlimited)
input double Inp_RRM_MaxDailyDrawdownPct      = 3.0;    // [Admin] Pause if daily DD exceeds % (0=disabled)

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

// Return a multiplier relative to M15 (base reference = 1.0).
// Used to scale pip-based values (SL, TP, ATR limits, trail cushion) by timeframe.
double GetTimeframeMultiplier(ENUM_TIMEFRAMES tf)
{
   switch(tf)
   {
      case PERIOD_M1:  return 0.5;
      case PERIOD_M5:  return 0.67;
      case PERIOD_M15: return 1.0;
      case PERIOD_M30: return 1.5;
      case PERIOD_H1:  return 2.0;
      case PERIOD_H4:  return 4.0;
      case PERIOD_D1:  return 8.0;
      case PERIOD_W1:  return 24.0;
      default:         return 1.0;
   }
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

// Return adaptive min ATR gate (pips) scaled by timeframe.
double GetAdaptiveATRMin(ENUM_TIMEFRAMES tf, const ST_AdaptiveSettings &adaptive)
{
   if(adaptive.ATR_Mode == TF_SCALE_MANUAL) return adaptive.ATR_Min_Base;
   return adaptive.ATR_Min_Base * GetTimeframeMultiplier(tf);
}

// Return adaptive max ATR gate (pips) scaled by timeframe.
double GetAdaptiveATRMax(ENUM_TIMEFRAMES tf, const ST_AdaptiveSettings &adaptive)
{
   if(adaptive.ATR_Mode == TF_SCALE_MANUAL) return adaptive.ATR_Max_Base;
   return adaptive.ATR_Max_Base * GetTimeframeMultiplier(tf);
}

// Return adaptive SL distance (pips) scaled by timeframe.  Returns 0 if UseSL=false.
double GetAdaptiveSL(ENUM_TIMEFRAMES tf, const ST_AdaptiveSettings &adaptive)
{
   if(!adaptive.UseSL) return 0.0;
   return adaptive.SL_Base * GetTimeframeMultiplier(tf);
}

// Return adaptive TP distance (pips) scaled by timeframe.  Returns 0 if UseTP=false.
double GetAdaptiveTP(ENUM_TIMEFRAMES tf, const ST_AdaptiveSettings &adaptive)
{
   if(!adaptive.UseTP) return 0.0;
   return adaptive.TP_Base * GetTimeframeMultiplier(tf);
}

// Return adaptive trail cushion (pips) scaled by timeframe.  Returns 0 if UseTrailCushion=false.
double GetAdaptiveTrailCushion(ENUM_TIMEFRAMES tf, const ST_AdaptiveSettings &adaptive)
{
   if(!adaptive.UseTrailCushion) return 0.0;
   return adaptive.TrailCushion_Base * GetTimeframeMultiplier(tf);
}

// Return adaptive PSAR cushion value.
// IMPORTANT: Return units differ by mode:
//   PsarUseATR=true  → returns a price-unit distance (current_atr × multiplier). Use directly as cushion.
//   PsarUseATR=false → returns a value in pips. Caller must convert to price units
//                      (e.g. pips * _Point * scale * (isJPY ? 100.0 : 10.0)).
double GetAdaptivePsarCushion(double current_atr, const ST_AdaptiveSettings &adaptive)
{
   if(adaptive.PsarUseATR)
      return current_atr * adaptive.PsarATR_Multiplier;
   return adaptive.PsarCushion_Pips;
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
   Settings.DebugFlow                = Inp_DebugFlow;
   Settings.AdminOverridePreset      = Inp_AdminOverridePreset;

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
   Settings.RRM_Lookback               = Inp_RRM_Lookback;
   Settings.RRM_MinDivPips             = Inp_RRM_MinDivPips;
   Settings.RequirePullback            = Inp_Gate_RequirePullback;
   Settings.PullbackLookback           = Inp_Gate_PullbackLookback;
   Settings.RequireRecoveryMomentum    = Inp_Gate_RequireRecoveryMomentum;
   Settings.Gate_UseMultiLayer         = Inp_Gate_UseMultiLayer;

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
   Settings.P_PsarTrailCushionATR= Inp_PSAR_TrailCushionATR;
   Settings.P_Atr                = 14;

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

   // Exits
   Settings.SL_PlacementMode     = Inp_SL_PlacementMode;
   Settings.SL_Mult              = Inp_SL_Mult;
   Settings.SL_PsarPipsCushion   = Inp_SL_PsarPipsCushion;
   Settings.SL_SwingPipsCushion  = Inp_SL_SwingPipsCushion;
   Settings.SL_FixedPips         = Inp_SL_FixedPips;

   // New strategy-based SL/TP configuration (ATR-optional)
   Settings.SLMode         = Inp_SLMode;
   Settings.TPMode         = Inp_TPMode;
   Settings.FixedTPPips    = Inp_FixedTPPips;
   Settings.UseATRforSL    = Inp_UseATRforSL;
   Settings.UseATRforTP    = Inp_UseATRforTP;
   Settings.SLPercent      = Inp_SLPercent;
   Settings.RRRatio        = Inp_RRRatio;
   Settings.SwingLookback  = Inp_SwingLookback;

   // Phase 2.2: Fractal/PSAR SL/TP settings
   Settings.FractalPeriod      = Inp_FractalPeriod;
   Settings.TPFractalOffset    = Inp_TPFractalOffset;
   Settings.PSARStep           = Inp_PSARStep;
   Settings.PSARMax            = Inp_PSARMax;

   // Phase 2.2: Advanced trailing trigger settings
   Settings.TrailTrigger       = Inp_TrailTrigger;
   Settings.TrailDistancePips  = Inp_TrailDistancePips;
   Settings.TrailATRMultiplier = Inp_TrailATRMultiplier;
   Settings.BEThresholdPips    = Inp_BEThresholdPips;
   Settings.TrailProfitPercent = Inp_TrailProfitPercent;
   Settings.TrailStepPips      = Inp_TrailStepPips;
   Settings.TrailLockProfit    = Inp_TrailLockProfit;

   Settings.TP_Mult              = Inp_TP_Mult;
   Settings.Use_BE               = Inp_Use_BE;
   Settings.BE_Trig              = Inp_BE_Trig;
   Settings.BE_Buff              = Inp_BE_Buff;

   Settings.TrailMode            = Inp_TrailMode;
   Settings.Trail_Mult           = Inp_Trail_Mult;
   Settings.PSAR_TrailCushionMode= Inp_PSAR_TrailCushionMode;
   Settings.PSAR_TrailPipsCushion= Inp_PSAR_TrailPipsCushion;
   Settings.PSAR_TrailDelay      = (Inp_PSAR_TrailDelay < 1) ? 1 : (Inp_PSAR_TrailDelay > 3) ? 3 : Inp_PSAR_TrailDelay;

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
   Settings.Vote_EvalShift           = 1;
   Settings.Vote_AllowPsarFlip       = false;
   // PSAR flip defaults
   Settings.Vote_PsarFlipDelay       = Inp_Vote_PsarFlipDelay;  // Countdown: bars after flip

   // Risk management defaults
   Settings.MaxTotalRisk      = 0.0;  // 0 = no portfolio limit (backward compatible)
   Settings.MaxOpenTrades     = 0;    // 0 = unlimited (backward compatible)
   Settings.CountBEasZeroRisk = true; // BE trades have 0 risk

   // === Adaptive settings: map inputs and derive effective values ===

   // 1. Map raw adaptive inputs into the struct
   Settings.Adaptive.PairType          = Inp_Adaptive_PairType;
   Settings.Adaptive.Spread_Major      = Inp_Adaptive_Spread_Major;
   Settings.Adaptive.Spread_Minor      = Inp_Adaptive_Spread_Minor;
   Settings.Adaptive.Spread_Exotic     = Inp_Adaptive_Spread_Exotic;
   Settings.Adaptive.Spread_Gold       = Inp_Adaptive_Spread_Gold;
   Settings.Adaptive.Spread_Crypto     = Inp_Adaptive_Spread_Crypto;

   Settings.Adaptive.ATR_Mode          = Inp_Adaptive_ATR_Mode;
   Settings.Adaptive.ATR_Min_Base      = Inp_Adaptive_ATR_Min_Base;
   Settings.Adaptive.ATR_Max_Base      = Inp_Adaptive_ATR_Max_Base;

   Settings.Adaptive.SL_Base           = Inp_Adaptive_SL_Base;
   Settings.Adaptive.TP_Base           = Inp_Adaptive_TP_Base;
   Settings.Adaptive.UseSL             = Inp_Adaptive_UseSL;
   Settings.Adaptive.UseTP             = Inp_Adaptive_UseTP;

   Settings.Adaptive.TrailCushion_Base = Inp_Adaptive_TrailCushion_Base;
   Settings.Adaptive.UseTrailCushion   = Inp_Adaptive_UseTrailCushion;

   Settings.Adaptive.PsarCushion_Pips  = Inp_Adaptive_PsarCushion_Pips;
   Settings.Adaptive.PsarUseATR        = Inp_Adaptive_PsarUseATR;
   Settings.Adaptive.PsarATR_Multiplier= Inp_Adaptive_PsarATR_Multiplier;

   // 2. Auto-detect pair type when set to AUTO
   if(Settings.Adaptive.PairType == PAIR_TYPE_AUTO)
      Settings.Adaptive.PairType = DetectPairType(_Symbol);

   // 3. Apply adaptive spread limit (overrides the operator-gate MaxSpread from Inp_MaxSpreadPips)
   //    The ZONE 2 input remains as a fallback but the adaptive value takes precedence.
   Settings.MaxSpread = GetAdaptiveSpreadLimit(Settings.Adaptive.PairType, Settings.Adaptive);

   // 4. Apply adaptive ATR limits (override Inp_MinATRPips / Inp_MaxATRPips)
   double atf_min = GetAdaptiveATRMin(Period(), Settings.Adaptive);
   double atf_max = GetAdaptiveATRMax(Period(), Settings.Adaptive);
   if(atf_min > 0.0) Settings.MinATR = atf_min;
   if(atf_max > 0.0) Settings.MaxATR = atf_max;

   // 5. Apply adaptive SL to SL_FixedPips when enabled.
   //    SL_FixedPips is the fixed-pip SL used by the executor in SL_FIXED_PIPS mode.
   //    Note: there is no equivalent TP_FixedPips field; adaptive TP distance is stored
   //    in Settings.Adaptive.TP_Base and accessible via GetAdaptiveTP() for callers.
   if(Inp_Adaptive_UseSL)
   {
      double adaptive_sl = GetAdaptiveSL(Period(), Settings.Adaptive);
      if(adaptive_sl > 0.0) Settings.SL_FixedPips = adaptive_sl;
   }

   // ═══════════════════════════════════════════════════════════════
   // 260304_PR1: Initialize Phase Detection Settings (DISABLED by default)
   // ═══════════════════════════════════════════════════════════════
   Settings.PhaseDetectionEnabled        = false;  // Not used yet - will be enabled in future updates
   Settings.BlockUnorderedPhase          = true;   // Block UNORDERED when enabled
   Settings.RequireMinPhaseConfirm       = false;  // No stability requirement by default
   Settings.MinPhaseConfirmBars          = 0;      // 0=instant EMA check (recommended)
   
   // Phase-specific permissions (default: allow all)
   Settings.Emerging_AllowWeakTrades     = true;
   Settings.Emerging_AllowMediumTrades   = true;
   Settings.Emerging_AllowStrongTrades   = true;
   Settings.Trending_AllowWeakTrades     = true;
   Settings.Trending_AllowMediumTrades   = true;
   Settings.Trending_AllowStrongTrades   = true;

   // ═══════════════════════════════════════════════════════════════
   // 260304_PR3: Initialize Layer Detection Settings (DISABLED by default)
   // ═══════════════════════════════════════════════════════════════
   Settings.EnableLayerDetection         = false;
   Settings.LayerTouchTolerancePips      = 2.0;
   Settings.LayerTouchTolerance          = 0.01;
   // Note: AllowLayer*_Entries defaults to true; these take effect once EnableLayerDetection = true
   Settings.AllowLayer1_Entries          = true;
   Settings.AllowLayer2_Entries          = true;
   Settings.AllowLayer3_Entries          = true;

   // 260304_PR5: Phase-based layer filtering
   // When BOTH PhaseDetectionEnabled AND EnableLayerDetection are true,
   // trades are filtered by phase rules:
   // - UNORDERED: blocks ALL trades
   // - EMERGING: blocks STRONG (Layer 3) trades
   // - TRENDING: allows all layers

   // ═══════════════════════════════════════════════════════════════
   // RRM Drawdown Protection (§6) - DISABLED by default
   // ═══════════════════════════════════════════════════════════════
   Settings.RRM_EnableDrawdownProtection = false;
   Settings.RRM_MaxConsecutiveLosses     = 5;
   Settings.RRM_MaxTradesPerDay          = 15;
   Settings.RRM_MaxDailyDrawdownPct      = 3.0;
}

//+------------------------------------------------------------------+
//| END OF FILE                                                      |
//+------------------------------------------------------------------+