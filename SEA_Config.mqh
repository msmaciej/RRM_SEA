//+------------------------------------------------------------------+
//|                                                   SEA_Config.mqh |
//|                                   Copyright 2026, SimpleEA System|
//+------------------------------------------------------------------+
#property strict

//+------------------------------------------------------------------+
//| TYPES (ENUMS / STRUCTS)                                          |
//+------------------------------------------------------------------+

// --- STRATEGY PRESETS ---
enum EStrategyPreset {
   PRESET_CUSTOM,             // CUSTOM - User controlled (no preset overrides)
   PRESET_MA_BENCHMARK,       // PRESET - MT5 MA "Moving Average" compatibility
   PRESET_TREND_REVERSAL,     // PRESET - Trend Reversal (Baseline)
   PRESET_TREND_SCALP,        // PRESET - Trend Scalp (Intraday confluence)
   PRESET_TREND_SWING,        // PRESET - Trend Swing (Institutional)
   PRESET_RANGE_GRID,         // PRESET - Range Grid (Conservative mean reversion)
   PRESET_RRM_ATR,            // PRESET - RRM ATR Trend Pullback (OPTIMIZED)
   PRESET_RRM                 // PRESET - RRM ORG Trend Pullback ORG
};

// --- RRM MODE (for PRESET_RRM) ---
enum ERRMMode {
   RRM_AUTO_BY_TF,            // RRM_Auto: M1/M5/M15 => SCALP; H1/H4+ => SWING
   RRM_SCALP,                 // RRM_Scalp: faster bias pair (EMA1/EMA2)
   RRM_SWING                  // RRM_Swing: slower bias pair (EMA3/EMA4)
};

// --- SIMPLE EMA SELECTOR ---
enum EEmaStrategy {
   EMA_STRAT_1_PRICE_CROSS,   // EMA_STRAT_1 EMA: Buy if Price > EMA1 (Benchmark)
   EMA_STRAT_2_CROSS_1_2,     // EMA_STRAT_2 EMAs: Buy if EMA1 > EMA2 (Golden Cross)
   EMA_STRAT_2_CROSS_3_4,     // EMA_STRAT_2 EMAs: Buy if EMA3 > EMA4 (Slow Trend)
   EMA_STRAT_CUSTOM           // EMA_STRAT_CUSTOM Manual: Use "Advanced Bias" inputs below
};

// --- MA METHOD SELECTOR ---
enum EMaMethod {
   METHOD_EMA,          // MA METHOD_EMA - Exponential (Reacts faster, standard for this EA)
   METHOD_SMA           // MA METHOD_SMA - Simple (Smoother, standard for MT5 Benchmarks)
};

enum EBiasMode { 
   BIAS_MANUAL,         // BIAS_MANUAL - User Manually sets Direction
   BIAS_AUTO            // BIAS_AUTO - EA determines Direction automatically
};

enum EManualSide { 
   SIDE_BOTH,           // SIDE_BOTH - Trade Both Long and Short
   SIDE_LONG,           // SIDE_LONG - Long Only
   SIDE_SHORT           // SIDE_SHORT - Short Only
};

enum EAutoStrategy { 
   STRAT_SINGLE_SLOPE,  // STRAT_SINGLE_SLOPE - of BiasFast MA
   STRAT_PAIR_CROSS,    // STRAT_PAIR_CROSS - of BiasFast > BiasSlow (MA vs MA)
   STRAT_PRICE_CROSS    // STRAT_PRICE_CROSS - of Price > BiasFast MA (Benchmark Mode)
};

enum EEmaRole { 
   ROLE_EMA1,
   ROLE_EMA2,
   ROLE_EMA3,
   ROLE_EMA4 
};

// Indicator Modes
enum EMacdMode { 
   MACD_SIGNAL_ALIGN,   // MACD_SIGNAL - Buy if Main > Signal
   MACD_ZERO_CROSS      // MACD_ZERO - Buy if Main > 0
};

enum ERsiMode { 
   RSI_FILTER_EXTREME,  // RSI_FILTER - Pass if NOT Overbought (>70)
   RSI_TREND_ABOVE_50,  // RSI_TREND - Pass if RSI > 50
   RSI_CROSS_LEVEL      // RSI_CROSS - Signal on Level Breakout
};

enum ECciMode { 
   CCI_TREND_ZERO,      // CCI_TREND_0 - Buy if CCI > 0
   CCI_IMPULSE_100      // CCI_IMPULSE_100 - Buy if CCI > 100
};

enum EStochMode { 
   STO_CROSS_SIGNAL,    // STO_CROSS - Signal: K line crosses D line
   STO_ZONE_FILTER      // STO_ZONE - Filter: K is not in extreme zones (OPTIMIZED)
};

enum EBbMode { 
   BB_TREND_FOLLOW,     // BB_TREND_FOLLOW - Price > Middle Band
   BB_MEAN_REVERSION    // BB_MEAN_REVERSION - Price touches Lower Band
};

// TR - Trailing Stop: Exit Logic
enum ETrailingMode { 
   TRAIL_NONE,          // TRAIL_NONE - Fixed SL only
   TRAIL_ATR,           // TRAIL_ATR - Volatility based (Smooth)
   TRAIL_PSAR,          // TRAIL_PSAR - Parabolic SAR (Trend Lock)
   TRAIL_FRACTAL        // TRAIL_FRACTAL - Market Structure (Swing High/Low)
};

// SL - Stop Loss: Initial SL Placement Methods
enum ESlPlacementMode {
   SL_ATR,              // SL_ATR - ATR based (current default)
   SL_PSAR_ATR,         // SL_PSAR_ATR - PSAR dot + ATR cushion
   SL_PSAR_PIPS,        // SL_PSAR_PIPS - PSAR dot + Pips cushion (TF + currency aware)
   SL_SWING_HIGHLOW,    // SL_SWING_HL - Last swing high/low (Fractal) + Pips cushion
   SL_FIXED_PIPS        // SL_PIPS - Fixed pips value
};

// TR - Trailing Stop: PSAR Trailing Cushion Mode
enum EPsarTrailCushionMode {
   PSAR_CUSHION_ATR,    // TRAIL_CUSHION_ATR - PSAR ATR multiplier (current)
   PSAR_CUSHION_PIPS    // TRAIL_CUSHION_PSAR - PSAR PIPS Fixed pips cushion
};

// --- STRUCTURES ---
struct SNewsEvent { 
   datetime time; 
   string currency; 
   string impact; 
};

struct ST_Settings {
   // Logic
   bool CloseOnReverse;
   
   // Risk
   double RiskPercent; 
   double MaxSpread;
   double MinATR;
   double MaxATR;             // NEW: upper volatility bound (OPTIMIZED)
   bool   ATR_HardGate;       // ATR gating mode: true=HARD filter, false=soft (vote/management only)
   bool   Use_ATRVote;        // If true, ATR contributes an additional vote when inside [MinATR,MaxATR]
   
   // MT5 Moving Average benchmark compatibility
   bool   UseMACompatSizer;
   double MA_MaximumRiskPct;      
   double MA_DecreaseFactor;      
   bool   RequirePriceCross;      
   bool   MABenchmarkStrict;

   // RRM (Trend Pullback)
   bool   RRM_RequirePullbackReclaim; // OPTIMIZED: NOW TRUE by default
   bool   RRM_RequireEmaDiv;          // OPTIMIZED: NOW TRUE by default
   int    RRM_Lookback;               
   double RRM_MinDivPips;

   // Bias
   bool BiasEnabled; 
   EBiasMode BiasMode; 
   EManualSide ManSide;
   EAutoStrategy AutoStrat; 
   int BiasFastID; 
   int BiasSlowID;

   // Execution Logic
   EMaMethod MaType;
   int ma_h_shift;      
   int ma_v_shift;      
   
   // Filters
   bool UseTime; 
   int StartHr;
   int EndHr;
   bool UseNews; 
   int NewsPre; 
   int NewsPost;
   bool UseHTF;  
   ENUM_TIMEFRAMES HtfPeriod; 
   int P_HtfEma;
   
   // Voting
   int VoteThreshold;

   // Indicators (Periods)
   int P_Ema1; 
   int P_Ema2; 
   int P_Ema3; 
   int P_Ema4;
   int P_Adx; 
   int T_Adx;
   int P_MacdFast;
   int P_MacdSlow; 
   int P_MacdSig;
   int P_Rsi; 
   double T_RsiOB; 
   double T_RsiOS;
   int P_Cci; 
   int P_Mfi; 
   double T_Mfi;
   int P_StoK; 
   int P_StoD;
   int P_StoSlow;
   int P_Bb; 
   double P_BbDev;
   double P_PsarStep; 
   double P_PsarMax;
   double P_PsarTrailCushionATR;
   
   // Modes
   EMacdMode MacdMode; 
   ERsiMode RsiMode;
   ECciMode CciMode; 
   EStochMode StoMode; 
   EBbMode BbMode;
   
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
   ESlPlacementMode SL_PlacementMode; // Which method to use for initial SL
   double SL_Mult;                    // ATR multiplier (for SL_ATR mode)
   double SL_PsarPipsCushion;         // Fixed pips cushion for PSAR SL
   double SL_SwingPipsCushion;        // Fixed pips cushion for Swing High/Low SL
   double SL_FixedPips;               // Fixed pips value for SL_FIXED_PIPS mode
   
   // TS - Trailing SL
   double TP_Mult;
   bool Use_BE; 
   double BE_Trig; 
   double BE_Buff;
   ETrailingMode TrailMode; 
   double Trail_Mult;
   EPsarTrailCushionMode PSAR_TrailCushionMode;  // ATR or Pips
   double PSAR_TrailPipsCushion;      // Fixed pips cushion for PSAR trailing

   // Reporting
   bool ExportCSV;
};

// Global Configuration Instance
ST_Settings Settings;

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                 |
//+------------------------------------------------------------------+

input group "=== MASTER PRESET ==="
input ulong          Inp_MagicNum               = 12345;             // Unique Magic Number
input EStrategyPreset InpPreset                 = PRESET_RRM;        // Select Preset Mode

input group "=== BENCHMARK: MT5 MOVING AVERAGE ==="
input double         Inp_MA_MaximumRiskPct      = 0.02;              // ONLY when Preset=PRESET_MA_BENCHMARK. Maximum Risk in percentage (e.g., 0.02 = 0.02%).
input double         Inp_MA_DecreaseFactor      = 3.0;               // ONLY when Preset=PRESET_MA_BENCHMARK. Decrease factor (lot reduction after consecutive losses).
input int            Inp_MA_Period              = 12;                // ONLY when Preset=PRESET_MA_BENCHMARK. Moving Average period.
input int            Inp_MA_Shift               = 6;                 // ONLY when Preset=PRESET_MA_BENCHMARK. Moving Average shift.

input group "=== DIAGNOSTICS ==="
input bool           Inp_PrintEffectiveConfig   = true;              // Print effective configuration on init
input bool           Inp_DebugFlow              = false;             // Print explicit OnInit/OnTick/OnDeinit flow

input group "=== UI: STATUS PANEL ==="
input bool           Inp_UI_ShowStatusPanel     = false;             // Show on-chart effective settings panel
input bool           Inp_UI_ManageChartIndicators = false;           // If true, EA clears chart indicators and re-adds only key overlays used by the active preset (Tester clarity; modifies chart)
input ENUM_BASE_CORNER Inp_UI_PanelCorner       = CORNER_LEFT_UPPER; // Panel corner
input int            Inp_UI_PanelX              = 30;                // Panel X offset (pixels)
input int            Inp_UI_PanelY              = 30;                // Panel Y offset (pixels)
input int            Inp_UI_PanelFontSize       = 8;                 // Panel font size
input int            Inp_UI_LineSpacingPx       = 21;                // Panel line spacing in pixels (0=auto, min=8)
input string         Inp_UI_PanelFont           = "Arial";           // Panel font

input group "=== UI: COCKPIT PANEL ==="
input bool           Inp_UI_ShowCockpitPanel    = true;              // Show on-chart trade cockpit (updates once per new bar)
input ENUM_BASE_CORNER Inp_UI_CockpitCorner     = CORNER_LEFT_UPPER; // Cockpit corner
input int            Inp_UI_CockpitX            = 30;                // Cockpit X offset (pixels)
input int            Inp_UI_CockpitY            = 30;                // Cockpit Y offset (pixels)
input int            Inp_UI_CockpitFontSize     = 8;                 // Cockpit font size
input int            Inp_UI_CockpitLineSpacingPx = 21;               // Cockpit line spacing (0=auto, min=8)
input string         Inp_UI_CockpitFont         = "Arial";           // Cockpit font

input group "=== UI: SIGNAL MARKERS ==="
input bool           Inp_DrawEntryLines         = true;              // Draw vertical line when an entry becomes ELIGIBLE (all gates pass)
input bool           Inp_DrawTradeLines         = true;              // Draw vertical line when a trade is EXECUTED (order opened)

input group "=== PRESET_RRM: TREND PULLBACK ==="               
input ERRMMode       Inp_RRM_Mode               = RRM_AUTO_BY_TF;    // RRM mode: auto/scalp/swing
input bool           Inp_RRM_EnableInCustom     = false;             // Allow RRM trigger gates also in PRESET_CUSTOM
input EAutoStrategy  Inp_RRM_AutoStrat          = STRAT_PRICE_CROSS; // RRM Entry Strategy: PAIR_CROSS / PRICE_CROSS / SINGLE_SLOPE
input EEmaRole       Inp_RRM_BiasEMA            = ROLE_EMA2;         // RRM Bias EMA: Which EMA for bias (ROLE_EMA1=5, EMA2=13, EMA3=34, EMA4=89)
input int            Inp_RRM_Lookback           = 5;                 // 5 | EMA convergence lookback (bars)
input double         Inp_RRM_MinDivPips         = 0.5;               // 0.5 | Minimum EMA divergence increase (pips)
input bool           Inp_RRM_RequirePullbackReclaim   = false;       // false | RRM gate: require pullback+reclaim (Legacy RRM: OFF)
input bool           Inp_RRM_RequireEmaDiv            = false;       // false | RRM gate: require EMA converge->diverge (Legacy RRM: OFF)

input group "=== CUSTOM: LOGIC & RISK ==="
input bool           Inp_CloseOnReverse         = false;             // OPTIMIZED: true was false | Close Opposite Trade on Signal?
input double         Inp_RiskPercent            = 2.0;               // OPTIMIZED: 0.25 was 2.0 (reduced for scalp safety) | Risk per trade (%)
input double         Inp_MaxSpreadPips          = 3.0;               // OPTIMIZED: 2.0 was 3.0 (tightened) | Max Spread (Pips) 
input double         Inp_MinATRPips             = 0.0;               // OPTIMIZED: 5.0 was 0.0 | Min Volatility (ATR Pips)
input double         Inp_MaxATRPips             = 20.0;              // NEW: upper volatility bound  

input group "=== CUSTOM: MARKET BIAS ==="
input bool           Inp_BiasEnabled            = true;              // Master Bias Switch
input EBiasMode      Inp_BiasMode               = BIAS_AUTO;         // Mode: MANUAL or AUTO
input EEmaStrategy   Inp_EmaStrategy            = EMA_STRAT_2_CROSS_3_4; // Select Strategy Configuration

input group "=== CUSTOM: ADVANCED AUTO MAPPING ==="
input EManualSide    Inp_ManualSide             = SIDE_BOTH;         // Manual Side (MANUAL: LONG/SHORT; BOTH=no restriction -> AUTO decides)
input EEmaRole       Inp_BiasFast_Adv           = ROLE_EMA3;         // Fast MA Slot (AUTO+CUST)
input EEmaRole       Inp_BiasSlow_Adv           = ROLE_EMA4;         // Slow MA Slot (AUTO+CUST)

input group "=== CUSTOM: FILTERS ==="
input bool           Inp_UseTime                = false;             // Use Time Scheduler?
input int            Inp_StartHour              = 8;                 // Start Trading Hour (0-23)
input int            Inp_EndHour                = 20;                // End Trading Hour (0-23)
input bool           Inp_UseNews                = false;             // Use CSV News Filter?
input string         Inp_NewsFile               = "calendar_statement.csv"; // File Name
input int            Inp_NewsPre                = 60;                // Pause Mins BEFORE News
input int            Inp_NewsPost               = 60;                // Pause Mins AFTER News
input bool           Inp_UseHTF                 = false;             // Master Filter: HTF Trend
input ENUM_TIMEFRAMES Inp_HtfPeriod             = PERIOD_H4;         // HTF Period
input int            Inp_HtfEmaPeriod           = 89;                // HTF EMA Period

input group "=== CUSTOM: VOTING ==="
input int            Inp_VoteThreshold          = 2;                 // MINIMUM Votes required // OPTIMIZED: 3 was 6 (MAJOR CHANGE)

input group "=== INDICATORS: SETTINGS ==="
input EMaMethod      Inp_MaType                 = METHOD_EMA;        // CUSTOM Moving Average Math. IGNORED when Preset=PRESET_MA_BENCHMARK.
input int            Inp_MaHorShift             = 0;                 // CUSTOM Horizontal MA Shift (Indicator Offset). IGNORED when Preset=PRESET_MA_BENCHMARK.
input int            Inp_MaVerShift             = 1;                 // CUSTOM Vertical MA Bar Shift: 0=Aggressive (Current Bar), 1=Safe (Closed Bar). IGNORED when Preset=PRESET_MA_BENCHMARK.

// EMA
input group "--- INDICATORS: EMA ---"
input int            InpEma1Period              = 5;                 // OPTIMIZED: 20 was 13 (scalp), will be overridden
input int            InpEma2Period              = 13;                // OPTIMIZED: 50 was 21 (scalp), will be overridden
input int            InpEma3Period              = 34;                // OPTIMIZED: 21 was 34 (swing), will be overridden
input int            InpEma4Period              = 89;                // OPTIMIZED: 55 was 89 (swing), will be overridden

// ADX
input group "--- INDICATORS: ADX ---"
input int            InpAdxPeriod               = 14;
input int            InpAdxThreshold            = 20;                // ADX > 20 = strong trend (use lower vote threshold)

// MACD
input group "--- INDICATORS: MACD ---"
input EMacdMode      InpMacdMode                = MACD_SIGNAL_ALIGN;
input int            InpMacdFast                = 12;                // OPTIMIZED: 8 was 12
input int            InpMacdSlow                = 26;                // OPTIMIZED: 13 was 26
input int            InpMacdSig                 = 9;                 // OPTIMIZED: 8 was 9

// RSI
input group "--- INDICATORS: RSI ---"
input ERsiMode       InpRsiMode                 = RSI_FILTER_EXTREME;
input int            InpRsiPeriod               = 14;
input double         InpRsiOverbought           = 70.0;
input double         InpRsiOversold             = 30.0;

// CCI
input group "--- INDICATORS: CCI ---"
input ECciMode       InpCciMode                 = CCI_TREND_ZERO;
input int            InpCciPeriod               = 14;

// MFI
input group "--- INDICATORS: MFI ---"
input int            InpMfiPeriod               = 14;
input double         InpMfiLevel                = 50.0;

// Stochastic (OPTIMIZED: Zone Filter Mode)
input group "--- INDICATORS: STOCHASTIC ---"
input EStochMode     InpStoMode                 = STO_ZONE_FILTER;   // OPTIMIZED: STO_ZONE_FILTER was STO_CROSS_SIGNAL
input int            InpStoK                    = 5;
input int            InpStoD                    = 3;
input int            InpStoSlow                 = 3;

// Bollinger (DISABLED IN OPT)
input group "--- INDICATORS: BOLLINGER BANDS ---"
input EBbMode        InpBbMode                  = BB_TREND_FOLLOW;
input int            InpBbPeriod                = 20;
input double         InpBbDev                   = 2.0;

// PSAR
input group "--- INDICATORS: PSAR ---"
input double         InpPsarStep                = 0.05;
input double         InpPsarMax                 = 0.5;

input group "=== VOTING: ENABLED VOTES ==="
input bool           Inp_Use_EmaSig             = true;              // Vote 1: EMA Recovery
input bool           Inp_Use_Adx                = false;             // Vote 2: ADX Strength
input bool           Inp_Use_Macd               = true;              // Vote 3: MACD
input bool           Inp_Use_Rsi                = false;             // Vote 4: RSI
input bool           Inp_Use_Cci                = true;              // Vote 5: CCI
input bool           Inp_Use_Mfi                = false;             // Vote 6: MFI
input bool           Inp_Use_Sto                = false;             // Vote 7: Stochastic
input bool           Inp_Use_Bb                 = false;             // Vote 8: Bollinger
input bool           Inp_Use_Psar               = true;              // Vote 9: PSAR
input bool           Inp_Use_P123               = false;             // Vote 10: Pattern 123
input bool           Inp_Use_Ross               = false;             // Vote 11: Ross Hook

input group "=== EXITS: SL/TP, BREAKEVEN, TRAILING ==="

input group "=== EXITS: INITIAL SL PLACEMENT ==="
input ESlPlacementMode Inp_SL_PlacementMode     = SL_SWING_HIGHLOW;  // Initial SL Method, SL_ATR, SL_FIXED_PIPS, SL_PSAR_ATR, SL_PSAR_PIPS, SL_SWING_HIGHLOW
input double         Inp_SL_Mult                = 1.5;               // 1.5 | ATR Multiplier (for SL_ATR mode)
input double         Inp_SL_PsarPipsCushion     = 5.0;               // 5.0 | PSAR Pips Cushion (auto-scaled by TF/currency)
input double         Inp_SL_SwingPipsCushion    = 10.0;              // 10.0 | Swing High/Low Pips Cushion (auto-scaled)
input double         Inp_SL_FixedPips           = 20.0;              // 20.0 | Fixed Pips SL (for SL_FIXED_PIPS mode)

input group "=== EXITS: TP, BREAKEVEN, TRAILING ==="
input double         Inp_TP_Mult                = 3.0;               // 3.0 | 4.0 | TP (ATR Multiplier)
input bool           Inp_Use_BE                 = false;             // true | Move SL to Entry?
input double         Inp_BE_Trig                = 1.0;               // Breakeven Trigger (ATR)
input double         Inp_BE_Buff                = 0.1;               // Breakeven Buffer (ATR)

input group "=== EXITS: TRAILING STOP ==="
input ETrailingMode  Inp_TrailMode              = TRAIL_PSAR;        // TRAIL .._ATR, .._FRACTAL, .._NONE, .._PSAR | Trailing Logic
input double         Inp_Trail_Mult             = 3.0;               // 3.0 | 1.5 | ATR Trail Distance
input EPsarTrailCushionMode Inp_PSAR_TrailCushionMode = PSAR_CUSHION_PIPS; // PSAR_CUSHION .._ATR, .._PIPS; PSAR Trail Cushion Mode
input double         Inp_PSAR_TrailPipsCushion  = 5.0;               // PSAR Trailing Pips Cushion (when Mode=PIPS, auto-scaled)
input double         Inp_PSAR_TrailCushionATR   = 0.2;               // PSAR trailing cushion (ATR multiplier). Used only when TrailMode=TRAIL_PSAR.

input group "=== REPORTING ==="
input bool           Inp_ExportCSV              = false;             // Export Detailed Report?
input bool           Inp_ExportUseCommonFiles   = false;             // Export CSV into COMMON Files folder (Windows). On Wine/macOS this may not be accessible; keep false.

//+------------------------------------------------------------------+
//| Initialization Function                                          |
//+------------------------------------------------------------------+
void InitializeConfig() {
    ZeroMemory(Settings);
}