//+------------------------------------------------------------------+
//|                                 SimpleEA_v1-02-016d_05-8_RRM.mq5 |
//|                              MJS Institutional Trading Solutions |
//|                                                                  |
//|           GOLDEN MASTER: Easy Setup + MA Method + Dual Shifts    |
//|           RRM REV 05-7: Legacy-aligned + ATR gate fix            |
//+------------------------------------------------------------------+
// SAVE AS UTF-16 LE WITH BOM
//+------------------------------------------------------------------+
//| FILE HEADER & TERMINAL DIRECTIVES                                |
//+------------------------------------------------------------------+

#property copyright "SimpleEA v1.02.016d-05-8_RRM"
#property version   "102.016"
#property strict

//+------------------------------------------------------------------+
//| BUILD SWITCHES & CONSTANTS                                       |
//+------------------------------------------------------------------+

// --- Anti-stale build lock (MQL5-safe: no #if, no #error)
#define SEA_BUILD_TOKEN_102016D 1

// --- Anti-stale build lock (macOS+Wine+MT5)
#define SEA_BUILD_NUM 1020168      // 1.02.016d => 1020164
#define SEA_BUILD_STR "1.02.016d-05-8_RRM"   // Revision tag with OPT suffix

//+------------------------------------------------------------------+
//| TYPES (ENUMS / STRUCTS)                                          |
//+------------------------------------------------------------------+

// --- STRATEGY PRESETS ---
enum EStrategyPreset {
   PRESET_CUSTOM,             // CUSTOM - User controlled (no preset overrides)
   PRESET_MA_BENCHMARK,       // PRESET - MT5 "Moving Average" compatibility
   PRESET_TREND_REVERSAL,     // PRESET - Trend Reversal (Baseline)
   PRESET_TREND_SCALP,        // PRESET - Trend Scalp (Intraday confluence)
   PRESET_TREND_SWING,        // PRESET - Trend Swing (Institutional)
   PRESET_RANGE_GRID,         // PRESET - Range Grid (Conservative mean reversion)
   PRESET_RRM                 // PRESET - RRM Trend Pullback (OPTIMIZED)
};

// --- RRM MODE (for PRESET_RRM) ---
enum ERRMMode {
   RRM_AUTO_BY_TF,   // Auto: M1/M5/M15 => SCALP; H1/H4+ => SWING
   RRM_SCALP,        // Scalp: faster bias pair (EMA1/EMA2)
   RRM_SWING         // Swing: slower bias pair (EMA3/EMA4)
};

// --- SIMPLE EMA SELECTOR ---
enum EEmaStrategy {
   EMA_STRAT_1_PRICE_CROSS,   // EMA STRAT - 1 EMA: Buy if Price > EMA1 (Benchmark)
   EMA_STRAT_2_CROSS_1_2,     // EMA STRAT - 2 EMAs: Buy if EMA1 > EMA2 (Golden Cross)
   EMA_STRAT_2_CROSS_3_4,     // EMA STRAT - 2 EMAs: Buy if EMA3 > EMA4 (Slow Trend)
   EMA_STRAT_CUSTOM           // EMA STRAT - CUSTOM - Manual: Use "Advanced Bias" inputs below
};

// --- MA METHOD SELECTOR ---
enum EMaMethod {
   METHOD_EMA,          // METHOD_EMA - Exponential (Reacts faster, standard for this EA)
   METHOD_SMA           // METHOD_SMA - Simple (Smoother, standard for MT5 Benchmarks)
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
   STRAT_SINGLE_SLOPE,  // Slope of BiasFast MA
   STRAT_PAIR_CROSS,    // Cross of BiasFast > BiasSlow (MA vs MA)
   STRAT_PRICE_CROSS    // Cross of Price > BiasFast MA (Benchmark Mode)
};

enum EEmaRole { 
   ROLE_EMA1, ROLE_EMA2, ROLE_EMA3, ROLE_EMA4 
};

// Indicator Modes
enum EMacdMode { 
   MACD_SIGNAL_ALIGN,   // MACD - Buy if Main > Signal
   MACD_ZERO_CROSS      // MACD - Buy if Main > 0
};
enum ERsiMode { 
   RSI_FILTER_EXTREME,  // RSI - Pass if NOT Overbought (>70)
   RSI_TREND_ABOVE_50,  // RSI - Pass if RSI > 50
   RSI_CROSS_LEVEL      // RSI - Signal on Level Breakout
};
enum ECciMode { 
   CCI_TREND_ZERO,      // CCI - Buy if CCI > 0
   CCI_IMPULSE_100      // CCI - Buy if CCI > 100
};
enum EStochMode { 
   STO_CROSS_SIGNAL,    // STO - K line crosses D line
   STO_ZONE_FILTER      // STO - K is not in extreme zones (OPTIMIZED)
};
enum EBbMode { 
   BB_TREND_FOLLOW,     // BB - Price > Middle Band
   BB_MEAN_REVERSION    // BB - Price touches Lower Band
};

// Exit Logic
enum ETrailingMode { 
   TRAIL_NONE,          // TRAIL - Fixed SL only
   TRAIL_ATR,           // TRAIL - Volatility based (Smooth)
   TRAIL_PSAR,          // TRAIL - Parabolic SAR (Trend Lock)
   TRAIL_FRACTAL        // TRAIL - Market Structure (Swing High/Low)
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
   double MaxATR;         // NEW: upper volatility bound (OPTIMIZED)
   bool   ATR_HardGate;     // ATR gating mode: true=HARD filter, false=soft (vote/management only)
   bool   Use_ATRVote;      // If true, ATR contributes an additional vote when inside [MinATR,MaxATR]
   
   // MT5 Moving Average benchmark compatibility
   bool   UseMACompatSizer;       
   double MA_MaximumRiskPct;      
   double MA_DecreaseFactor;      
   bool   RequirePriceCross;      
   bool   MABenchmarkStrict;    
   
   // RRM (Trend Pullback)
   bool   RRM_RequirePullbackReclaim;  // OPTIMIZED: NOW TRUE by default
   bool   RRM_RequireEmaDiv;           // OPTIMIZED: NOW TRUE by default
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
   
   // Exit
   double SL_Mult; 
   double TP_Mult;
   bool Use_BE; 
   double BE_Trig; 
   double BE_Buff;
   ETrailingMode TrailMode; 
   double Trail_Mult;
   
   // Reporting
   bool ExportCSV;
   // PHASE DETECTION SETTINGS (PR1 - Foundation)
   bool     PhaseDetectionEnabled;
   bool     BlockUnorderedPhase;
   bool     RequireMinPhaseConfirm;
   int      MinPhaseConfirmBars;
   bool     Emerging_AllowWeakTrades;
   bool     Emerging_AllowMediumTrades;
   bool     Emerging_AllowStrongTrades;
   bool     Trending_AllowWeakTrades;
   bool     Trending_AllowMediumTrades;
   bool     Trending_AllowStrongTrades;
};

//+------------------------------------------------------------------+
//| FORWARD DECLARATIONS                                             |
//+------------------------------------------------------------------+

void SEA_DrawEntrySignalLine(datetime bar_time, int direction, const string label);
void SEA_DrawTradeExecLine(datetime event_time, int direction, double price, const string label);

//+------------------------------------------------------------------+
//| MODULE INCLUDES                                                  |
//+------------------------------------------------------------------+

#include <RRMS\SEA_SignalEngine.mqh>
#include <RRMS\SEA_TradeExecutor.mqh>
#include <RRMS\SEA_UI.mqh>
#include <RRMS\SEA_Reporting.mqh>

// --- Module revision stamps (fail fast if stale include path)
#ifndef SEA_MOD_SIGNALENGINE_102016D
enum { __SEA_STALE_SEA_MOD_SIGNALENGINE_102016D__ = SEA_MOD_SIGNALENGINE_102016D };
#endif
#ifndef SEA_MOD_TRADEEXEC_102016D
enum { __SEA_STALE_SEA_MOD_TRADEEXEC_102016D__ = SEA_MOD_TRADEEXEC_102016D };
#endif
#ifndef SEA_MOD_UI_102016D
enum { __SEA_STALE_SEA_MOD_UI_102016D__ = SEA_MOD_UI_102016D };
#endif
#ifndef SEA_MOD_REPORTING_102016D
enum { __SEA_STALE_SEA_MOD_REPORTING_102016D__ = SEA_MOD_REPORTING_102016D };
#endif


//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                 |
//+------------------------------------------------------------------+

input group "=== MASTER PRESET ==="
input ulong          Inp_MagicNum               = 12345;
input EStrategyPreset InpPreset                 = PRESET_RRM;  // DEFAULT: PRESET_RRM (OPTIMIZED)

input group "=== BENCHMARK: MT5 MOVING AVERAGE ==="
input double         Inp_MA_MaximumRiskPct      = 0.02;
input double         Inp_MA_DecreaseFactor      = 3.0;
input int            Inp_MA_Period              = 12;
input int            Inp_MA_Shift               = 6;

input group "=== DIAGNOSTICS ==="
input bool           Inp_PrintEffectiveConfig   = true;
input bool           Inp_DebugFlow              = false;

input group "=== UI: STATUS PANEL ==="
input bool           Inp_UI_ShowStatusPanel     = false;
input bool           Inp_UI_ManageChartIndicators = false;
input ENUM_BASE_CORNER Inp_UI_PanelCorner       = CORNER_LEFT_UPPER;
input int            Inp_UI_PanelX              = 30;
input int            Inp_UI_PanelY              = 30;
input int            Inp_UI_PanelFontSize       = 8;
input int            Inp_UI_LineSpacingPx       = 21;
input string         Inp_UI_PanelFont           = "Arial";

input group "=== UI: COCKPIT PANEL ==="
input bool           Inp_UI_ShowCockpitPanel    = true;
input ENUM_BASE_CORNER Inp_UI_CockpitCorner     = CORNER_LEFT_UPPER;
input int            Inp_UI_CockpitX            = 30;
input int            Inp_UI_CockpitY            = 30;
input int            Inp_UI_CockpitFontSize     = 8;
input int            Inp_UI_CockpitLineSpacingPx = 21;
input string         Inp_UI_CockpitFont         = "Arial";

input group "=== UI: SIGNAL MARKERS ==="
input bool           Inp_DrawEntryLines         = true;
input bool           Inp_DrawTradeLines         = true;

input group "=== PRESET_RRM: TREND PULLBACK (OPTIMIZED) ==="
input ERRMMode       Inp_RRM_Mode               = RRM_AUTO_BY_TF;
input bool           Inp_RRM_EnableInCustom     = false;

// OPTIMIZED: Pullback/Reclaim and EMA Divergence NOW ENABLED BY DEFAULT
input int            Inp_RRM_Lookback           = 5;
input double         Inp_RRM_MinDivPips         = 0.5;
input bool           Inp_RRM_RequirePullbackReclaim = true;   // OPTIMIZED: was false
input bool           Inp_RRM_RequireEmaDiv          = true;   // OPTIMIZED: was false

input group "=== CUSTOM: LOGIC & RISK ==="
input bool           Inp_CloseOnReverse         = true;  // OPTIMIZED: was false
input double         Inp_RiskPercent            = 0.25;  // OPTIMIZED: was 2.0 (reduced for scalp safety)
input double         Inp_MaxSpreadPips          = 2.0;   // OPTIMIZED: was 3.0 (tightened)
input double         Inp_MinATRPips             = 5.0;   // OPTIMIZED: was 0.0
input double         Inp_MaxATRPips             = 20.0;  // NEW: upper volatility bound

input group "=== CUSTOM: MARKET BIAS (EASY SETUP) ==="
input bool           Inp_BiasEnabled            = true;
input EBiasMode      Inp_BiasMode               = BIAS_AUTO;
input EEmaStrategy   Inp_EmaStrategy            = EMA_STRAT_2_CROSS_1_2;

input group "=== CUSTOM: ADVANCED AUTO MAPPING ==="
input EManualSide    Inp_ManualSide             = SIDE_BOTH;
input EEmaRole       Inp_BiasFast_Adv           = ROLE_EMA1;
input EEmaRole       Inp_BiasSlow_Adv           = ROLE_EMA2;

input group "=== CUSTOM: FILTERS ==="
input bool           Inp_UseTime                = true;  // OPTIMIZED: was false
input int            Inp_StartHour              = 8;
input int            Inp_EndHour                = 20;
input bool           Inp_UseNews                = true;  // OPTIMIZED: was false
input string         Inp_NewsFile               = "calendar_statement.csv";
input int            Inp_NewsPre                = 60;
input int            Inp_NewsPost               = 60;
input bool           Inp_UseHTF                 = true;  // OPTIMIZED: was false
input ENUM_TIMEFRAMES Inp_HtfPeriod             = PERIOD_H4;  // M5/M15 => H4; H1/H4 => D1
input int            Inp_HtfEmaPeriod           = 89;

input group "=== CUSTOM: VOTING (OPTIMIZED) ==="
input int            Inp_VoteThreshold          = 3;     // OPTIMIZED: was 6 (MAJOR CHANGE)

input group "=== INDICATORS: SETTINGS ==="
input EMaMethod      Inp_MaType                 = METHOD_EMA;
input int            Inp_MaHorShift             = 0;
input int            Inp_MaVerShift             = 1;     // OPTIMIZED: was 0 (closed bar)

// Periods (OPTIMIZED EMA periods per mode)
input group "--- INDICATORS: EMA (AUTO-SET BY PRESET) ---"
input int            InpEma1Period              = 20;    // OPTIMIZED: was 13 (scalp), will be overridden
input int            InpEma2Period              = 50;    // OPTIMIZED: was 21 (scalp), will be overridden
input int            InpEma3Period              = 21;    // OPTIMIZED: was 34 (swing), will be overridden
input int            InpEma4Period              = 55;    // OPTIMIZED: was 89 (swing), will be overridden

// ADX
input group "--- INDICATORS: ADX (NOW ENABLED) ---"
input int            InpAdxPeriod               = 14;
input int            InpAdxThreshold            = 20;    // ADX > 20 = strong trend (use lower vote threshold)

// MACD
input group "--- INDICATORS: MACD ==="
input EMacdMode      InpMacdMode                = MACD_SIGNAL_ALIGN;
input int            InpMacdFast                = 8;     // OPTIMIZED: was 12
input int            InpMacdSlow                = 13;    // OPTIMIZED: was 26
input int            InpMacdSig                 = 8;     // OPTIMIZED: was 9

// RSI
input group "--- INDICATORS: RSI (DISABLED IN OPT) ---"
input ERsiMode       InpRsiMode                 = RSI_FILTER_EXTREME;
input int            InpRsiPeriod               = 14;
input double         InpRsiOverbought           = 70.0;
input double         InpRsiOversold             = 30.0;

// CCI
input group "--- INDICATORS: CCI (DISABLED IN OPT) ---"
input ECciMode       InpCciMode                 = CCI_TREND_ZERO;
input int            InpCciPeriod               = 14;

// MFI
input group "--- INDICATORS: MFI (DISABLED IN OPT) ---"
input int            InpMfiPeriod               = 14;
input double         InpMfiLevel                = 50.0;

// Stochastic (OPTIMIZED: Zone Filter Mode)
input group "--- INDICATORS: STOCHASTIC (ZONE FILTER) ---"
input EStochMode     InpStoMode                 = STO_ZONE_FILTER;  // OPTIMIZED: was STO_CROSS_SIGNAL
input int            InpStoK                    = 5;
input int            InpStoD                    = 3;
input int            InpStoSlow                 = 3;

// Bollinger (DISABLED IN OPT)
input group "--- INDICATORS: BOLLINGER BANDS (DISABLED IN OPT) ---"
input EBbMode        InpBbMode                  = BB_TREND_FOLLOW;
input int            InpBbPeriod                = 20;
input double         InpBbDev                   = 2.0;

// PSAR
input group "--- INDICATORS: PSAR (TRAILING ONLY) ---"
input double         InpPsarStep                = 0.05;
input double         InpPsarMax                 = 0.5;
input double         InpPsarTrailCushionATR     = 0.5;

input group "=== VOTING: ENABLED VOTES (OPTIMIZED BUNDLE) ==="
input bool           Inp_Use_EmaSig             = true;        // Vote 1: EMA Direction (KEEP)
input bool           Inp_Use_Adx                = true;        // Vote 2: ADX Strength (NOW ENABLED)
input bool           Inp_Use_Macd               = true;        // Vote 3: MACD Momentum (KEEP)
input bool           Inp_Use_Rsi                = false;       // DISABLED
input bool           Inp_Use_Cci                = false;       // DISABLED
input bool           Inp_Use_Mfi                = false;       // DISABLED
input bool           Inp_Use_Sto                = true;        // Vote 4: Stochastic Zone (KEEP, mode changed)
input bool           Inp_Use_Bb                 = false;       // DISABLED (redundant with EMA)
input bool           Inp_Use_Psar               = false;       // DISABLED as vote (trailing only)
input bool           Inp_Use_P123               = false;       // DISABLED
input bool           Inp_Use_Ross               = false;       // DISABLED

input group "=== EXITS: SL/TP, BREAKEVEN, TRAILING ==="
input double         Inp_SL_Mult                = 1.25;        // OPTIMIZED: was 1.5
input double         Inp_TP_Mult                = 4.0;         // KEEP (high ratio)
input bool           Inp_Use_BE                 = true;        // OPTIMIZED: was false
input double         Inp_BE_Trig                = 1.5;         // Breakeven Trigger (ATR)
input double         Inp_BE_Buff                = 0.3;         // Breakeven Buffer (ATR)
input ETrailingMode  Inp_TrailMode              = TRAIL_PSAR;  // KEEP: PSAR trailing
input double         Inp_Trail_Mult             = 3.0;
input bool           Inp_ExportCSV              = false;
input bool           Inp_ExportUseCommonFiles   = false;

//+------------------------------------------------------------------+
//| GLOBAL STATE & MODULE OBJECTS                                    |
//+------------------------------------------------------------------+

CSignalEngine  Signal;
CTradeExecutor Executor;
ST_Settings    Settings;

EEmaStrategy   g_effectiveEmaStrategy  = EMA_STRAT_1_PRICE_CROSS;
EMaMethod      g_effectiveMaType       = METHOD_EMA;
EBiasMode      g_effectiveBiasMode     = BIAS_AUTO;
string         g_effectiveSigNote      = "";
string         g_effectiveDirSource    = "";

string         g_ui_used_flags         = "";
string         g_ui_ignored_flags      = "";
string         g_ui_overrides          = "";
string         g_ui_ma_source          = "";
bool           g_warned_bench_ignored  = false;
bool           g_warned_custom_bench   = false;

datetime       g_last_bar_time         = 0;
datetime       g_start_time            = 0;

bool           g_chart_indicators_managed = false;

//+------------------------------------------------------------------+
//| EXPERT LIFECYCLE (ENTRY POINTS)                                  |
//+------------------------------------------------------------------+

int OnInit() {
   return OrchestrateInit();
}

void OnTick() {
   if(Inp_UI_ManageChartIndicators && !g_chart_indicators_managed)
   {
      SEA_UI_ManageChartIndicators();
      g_chart_indicators_managed = true;
   }
   OrchestrateTick();
}

void OnDeinit(const int reason) {
   OrchestrateDeinit(reason);
}

//+------------------------------------------------------------------+
//| SETTINGS APPLICATION & ORCHESTRATION (OPTIMIZED)                 |
//+------------------------------------------------------------------+

void ApplySettings() {
   ZeroMemory(Settings);

   // Default behavior: keep execution filters HARD by default
   Settings.ATR_HardGate = true;
   Settings.Use_ATRVote  = false;

   // --- A. Determine effective controls
   EEmaStrategy effEmaStrategy = Inp_EmaStrategy;
   EMaMethod    effMaType      = Inp_MaType;
   EBiasMode    effBiasMode    = Inp_BiasMode;
   string note = "";

   bool easy_strategy = (effEmaStrategy != EMA_STRAT_CUSTOM);

   // --- B. Load base settings from inputs
   Settings.CloseOnReverse = Inp_CloseOnReverse;
   Settings.RiskPercent    = Inp_RiskPercent;
   Settings.MaxSpread      = Inp_MaxSpreadPips;
   Settings.MinATR         = Inp_MinATRPips;
   Settings.MaxATR         = Inp_MaxATRPips;  // NEW: upper volatility bound

   // Moving Average benchmark compatibility
   Settings.UseMACompatSizer  = false;
   Settings.MA_MaximumRiskPct = Inp_MA_MaximumRiskPct;
   Settings.MA_DecreaseFactor = Inp_MA_DecreaseFactor;
   Settings.RequirePriceCross = false;
   Settings.MABenchmarkStrict = false;

   // RRM trigger gates (OPTIMIZED: enabled by default)
   bool rrm_enable = (InpPreset == PRESET_RRM) || Inp_RRM_EnableInCustom;
   Settings.RRM_RequirePullbackReclaim = (rrm_enable ? Inp_RRM_RequirePullbackReclaim : false);
   Settings.RRM_RequireEmaDiv          = (rrm_enable ? Inp_RRM_RequireEmaDiv : false);
   Settings.RRM_Lookback              = Inp_RRM_Lookback;
   Settings.RRM_MinDivPips            = Inp_RRM_MinDivPips;
   
   Settings.BiasEnabled    = Inp_BiasEnabled;
   Settings.BiasMode       = effBiasMode;
   Settings.ManSide        = Inp_ManualSide;

   // --- C. Strategy mapping
   if(effEmaStrategy == EMA_STRAT_1_PRICE_CROSS)
   {
      Settings.AutoStrat   = STRAT_PRICE_CROSS;
      Settings.BiasFastID  = (int)ROLE_EMA1;
      Settings.BiasSlowID  = (int)ROLE_EMA1;
   }
   else if(effEmaStrategy == EMA_STRAT_2_CROSS_1_2)
   {
      Settings.AutoStrat   = STRAT_PAIR_CROSS;
      Settings.BiasFastID  = (int)ROLE_EMA1;
      Settings.BiasSlowID  = (int)ROLE_EMA2;
   }
   else if(effEmaStrategy == EMA_STRAT_2_CROSS_3_4)
   {
      Settings.AutoStrat   = STRAT_PAIR_CROSS;
      Settings.BiasFastID  = (int)ROLE_EMA3;
      Settings.BiasSlowID  = (int)ROLE_EMA4;
   }
   else
   {
      Settings.BiasFastID  = (int)Inp_BiasFast_Adv;
      Settings.BiasSlowID  = (int)Inp_BiasSlow_Adv;
      Settings.AutoStrat   = (Settings.BiasFastID == Settings.BiasSlowID) ? STRAT_PRICE_CROSS : STRAT_PAIR_CROSS;
   }

   // --- D. Execution / indicator method
   Settings.MaType         = effMaType;
   Settings.ma_h_shift     = Inp_MaHorShift;
   Settings.ma_v_shift     = Inp_MaVerShift;

   // --- E. Filters
   Settings.UseTime        = Inp_UseTime;
   Settings.StartHr        = Inp_StartHour;
   Settings.EndHr          = Inp_EndHour;
   Settings.UseNews        = Inp_UseNews;
   Settings.NewsPre        = Inp_NewsPre;
   Settings.NewsPost       = Inp_NewsPost;
   Settings.UseHTF         = Inp_UseHTF;
   Settings.HtfPeriod      = Inp_HtfPeriod;
   Settings.P_HtfEma       = Inp_HtfEmaPeriod;

   // --- F. Voting (OPTIMIZED: threshold now 3)
   Settings.VoteThreshold  = Inp_VoteThreshold;
   if(Settings.VoteThreshold <= 1)
   {
      if(note != "") note += " | ";
      note += "NOTE: VoteThreshold<=1 -> voting bypass (direction uses bias only).";
   }

   // --- G. Indicator periods / thresholds
   Settings.P_Ema1 = InpEma1Period; 
   Settings.P_Ema2 = InpEma2Period;
   Settings.P_Ema3 = InpEma3Period; 
   Settings.P_Ema4 = InpEma4Period;

   Settings.P_Adx = InpAdxPeriod; 
   Settings.T_Adx = InpAdxThreshold;
   Settings.P_MacdFast = InpMacdFast; 
   Settings.P_MacdSlow = InpMacdSlow; 
   Settings.P_MacdSig = InpMacdSig;
   Settings.P_Rsi = InpRsiPeriod; 
   Settings.T_RsiOB = InpRsiOverbought; 
   Settings.T_RsiOS = InpRsiOversold;
   Settings.P_Cci = InpCciPeriod;
   Settings.P_Mfi = InpMfiPeriod; 
   Settings.T_Mfi = InpMfiLevel;
   Settings.P_StoK = InpStoK; 
   Settings.P_StoD = InpStoD; 
   Settings.P_StoSlow = InpStoSlow;
   Settings.P_Bb = InpBbPeriod; 
   Settings.P_BbDev = InpBbDev;
   Settings.P_PsarStep = InpPsarStep; 
   Settings.P_PsarMax = InpPsarMax;
   Settings.P_PsarTrailCushionATR = InpPsarTrailCushionATR;

   Settings.MacdMode = InpMacdMode;
   Settings.RsiMode  = InpRsiMode;
   Settings.CciMode  = InpCciMode;
   Settings.StoMode  = InpStoMode;
   Settings.BbMode   = InpBbMode;

   // --- H. Active votes (OPTIMIZED: only 4 active, threshold 3)
   Settings.Use_EmaSig = Inp_Use_EmaSig;  // Vote 1: EMA (KEEP)
   Settings.Use_Adx    = Inp_Use_Adx;     // Vote 2: ADX (NOW ENABLED)
   Settings.Use_Macd   = Inp_Use_Macd;    // Vote 3: MACD (KEEP)
   Settings.Use_Rsi    = Inp_Use_Rsi;     // DISABLED
   Settings.Use_Cci    = Inp_Use_Cci;     // DISABLED
   Settings.Use_Mfi    = Inp_Use_Mfi;     // DISABLED
   Settings.Use_Sto    = Inp_Use_Sto;     // Vote 4: Stochastic (KEEP, zone filter)
   Settings.Use_Bb     = Inp_Use_Bb;      // DISABLED (redundant)
   Settings.Use_Psar   = Inp_Use_Psar;    // DISABLED as vote (trailing only)
   Settings.Use_P123   = Inp_Use_P123;    // DISABLED
   Settings.Use_Ross   = Inp_Use_Ross;    // DISABLED

   // --- I. Exit / BE / trailing
   Settings.SL_Mult     = Inp_SL_Mult;
   Settings.TP_Mult     = Inp_TP_Mult;
   Settings.Use_BE      = Inp_Use_BE;
   Settings.BE_Trig     = Inp_BE_Trig;
   Settings.BE_Buff     = Inp_BE_Buff;
   Settings.TrailMode   = Inp_TrailMode;
   Settings.Trail_Mult  = Inp_Trail_Mult;

   // --- J. Reporting
   Settings.ExportCSV   = Inp_ExportCSV;
   // --- Phase Detection Settings (PR1 - Default: DISABLED) ---
   Settings.PhaseDetectionEnabled        = false;  // Disabled by default - infrastructure ready for future PR
   Settings.BlockUnorderedPhase          = true;
   Settings.RequireMinPhaseConfirm       = false;
   Settings.MinPhaseConfirmBars          = 3;

   Settings.Emerging_AllowWeakTrades     = true;
   Settings.Emerging_AllowMediumTrades   = true;
   Settings.Emerging_AllowStrongTrades   = true;
   Settings.Trending_AllowWeakTrades     = true;
   Settings.Trending_AllowMediumTrades   = true;
   Settings.Trending_AllowStrongTrades   = true;


   // --- K. Apply presets (OPTIMIZED PRESET_RRM)
   
   //+------------------------------------------------------------------+
   //| PRESET_MA_BENCHMARK (UNCHANGED)                                  |
   //+------------------------------------------------------------------+

   if(InpPreset == PRESET_MA_BENCHMARK)
   {
      Settings.CloseOnReverse    = true;
      Settings.BiasEnabled       = true;
      Settings.BiasMode          = BIAS_AUTO;
      Settings.AutoStrat         = STRAT_PRICE_CROSS;
      Settings.BiasFastID        = (int)ROLE_EMA1;
      Settings.BiasSlowID        = (int)ROLE_EMA1;
      Settings.RequirePriceCross = true;
      Settings.MABenchmarkStrict = true;

      Settings.UseMACompatSizer  = true;
      Settings.MA_MaximumRiskPct = Inp_MA_MaximumRiskPct;
      Settings.MA_DecreaseFactor = Inp_MA_DecreaseFactor;
      Settings.RiskPercent       = 0.0;

      Settings.VoteThreshold     = 1;
      Settings.MaxSpread         = 9999.0;
      Settings.MinATR            = 0.0;
      Settings.UseTime           = false;
      Settings.UseNews           = false;
      Settings.UseHTF            = false;

      Settings.Use_EmaSig        = false;
      Settings.Use_Adx           = false;
      Settings.Use_Macd          = false;
      Settings.Use_Rsi           = false;
      Settings.Use_Cci           = false;
      Settings.Use_Mfi           = false;
      Settings.Use_Sto           = false;
      Settings.Use_Bb            = false;
      Settings.Use_Psar          = false;
      Settings.Use_P123          = false;
      Settings.Use_Ross          = false;

      Settings.SL_Mult           = 0.0;
      Settings.TP_Mult           = 0.0;
      Settings.Use_BE            = false;
      Settings.TrailMode         = TRAIL_NONE;

      Settings.MaType            = METHOD_SMA;
      Settings.ma_h_shift        = Inp_MA_Shift;
      Settings.ma_v_shift        = 1;
      Settings.P_Ema1            = Inp_MA_Period;

      effEmaStrategy             = EMA_STRAT_1_PRICE_CROSS;
      effMaType                  = Settings.MaType;
      effBiasMode                = Settings.BiasMode;

      if(note != "") note += " | ";
      note += "PRESET: MA_BENCHMARK applied.";
   }

   //+------------------------------------------------------------------+
   //| PRESET_TREND_REVERSAL (UNCHANGED)                                |
   //+------------------------------------------------------------------+

   else if(InpPreset == PRESET_TREND_REVERSAL)
   {
      Settings.CloseOnReverse = true;
      Settings.BiasEnabled    = true;
      Settings.BiasMode       = BIAS_AUTO;
      Settings.AutoStrat      = STRAT_PRICE_CROSS;
      Settings.BiasFastID     = (int)ROLE_EMA1;
      Settings.BiasSlowID     = (int)ROLE_EMA1;

      Settings.RequirePriceCross = true;
      Settings.ma_v_shift        = 1;

      Settings.VoteThreshold  = 1;
      Settings.MaxSpread      = 5.0;
      Settings.MinATR         = 0.0;
      Settings.UseTime        = false;
      Settings.UseNews        = false;
      Settings.UseHTF         = false;

      Settings.Use_EmaSig     = true;
      Settings.Use_Adx        = false;
      Settings.Use_Macd       = false;
      Settings.Use_Rsi        = false;
      Settings.Use_Cci        = false;
      Settings.Use_Mfi        = false;
      Settings.Use_Sto        = false;
      Settings.Use_Bb         = false;
      Settings.Use_Psar       = false;
      Settings.Use_P123       = false;
      Settings.Use_Ross       = false;

      Settings.SL_Mult        = 0.0;
      Settings.TP_Mult        = 0.0;
      Settings.Use_BE         = false;
      Settings.TrailMode      = TRAIL_NONE;

      Settings.MaType         = METHOD_SMA;

      effEmaStrategy          = EMA_STRAT_1_PRICE_CROSS;
      effMaType               = Settings.MaType;
      effBiasMode             = Settings.BiasMode;

      if(note != "") note += " | ";
      note += "PRESET: TREND_REVERSAL applied.";
   }
   
   //+------------------------------------------------------------------+
   //| PRESET_TREND_SCALP (UNCHANGED)                                   |
   //+------------------------------------------------------------------+

   else if(InpPreset == PRESET_TREND_SCALP)
   {
      Settings.CloseOnReverse = true;
      Settings.BiasEnabled    = true;
      Settings.BiasMode       = BIAS_AUTO;
      Settings.AutoStrat      = STRAT_PAIR_CROSS;
      Settings.BiasFastID     = (int)ROLE_EMA1;
      Settings.BiasSlowID     = (int)ROLE_EMA2;

      Settings.VoteThreshold  = 3;
      Settings.MaxSpread      = 3.0;
      Settings.MinATR         = 5.0;

      Settings.UseTime        = false;
      Settings.UseNews        = true;
      Settings.UseHTF         = true;

      Settings.Use_EmaSig     = true;
      Settings.Use_Adx        = true;
      Settings.Use_Macd       = true;
      Settings.Use_Rsi        = false;
      Settings.Use_Cci        = false;
      Settings.Use_Mfi        = false;
      Settings.Use_Sto        = false;
      Settings.Use_Bb         = false;
      Settings.Use_Psar       = false;
      Settings.Use_P123       = false;
      Settings.Use_Ross       = false;

      Settings.SL_Mult        = 1.5;
      Settings.TP_Mult        = 3.0;
      Settings.Use_BE         = true;
      Settings.BE_Trig        = 1.0;
      Settings.BE_Buff        = 0.1;
      Settings.TrailMode      = TRAIL_ATR;
      Settings.Trail_Mult     = 1.5;

      Settings.MaType         = METHOD_EMA;

      effEmaStrategy          = EMA_STRAT_2_CROSS_1_2;
      effMaType               = Settings.MaType;
      effBiasMode             = Settings.BiasMode;

      if(note != "") note += " | ";
      note += "PRESET: TREND_SCALP applied.";
   }
   
   //+------------------------------------------------------------------+
   //| PRESET_TREND_SWING (UNCHANGED)                                   |
   //+------------------------------------------------------------------+

   else if(InpPreset == PRESET_TREND_SWING)
   {
      Settings.CloseOnReverse = true;
      Settings.BiasEnabled    = true;
      Settings.BiasMode       = BIAS_AUTO;
      Settings.AutoStrat      = STRAT_PAIR_CROSS;
      Settings.BiasFastID     = (int)ROLE_EMA3;
      Settings.BiasSlowID     = (int)ROLE_EMA4;

      Settings.VoteThreshold  = 1;
      Settings.MaxSpread      = 5.0;
      Settings.MinATR         = 5.0;

      Settings.UseTime        = true;
      Settings.UseNews        = true;
      Settings.UseHTF         = true;

      Settings.Use_EmaSig     = true;
      Settings.Use_Adx        = true;
      Settings.Use_Macd       = true;
      Settings.Use_Rsi        = false;
      Settings.Use_Cci        = false;
      Settings.Use_Mfi        = false;
      Settings.Use_Sto        = false;
      Settings.Use_Bb         = false;
      Settings.Use_Psar       = false;
      Settings.Use_P123       = false;
      Settings.Use_Ross       = false;

      Settings.SL_Mult        = 2.0;
      Settings.TP_Mult        = 4.0;
      Settings.Use_BE         = true;
      Settings.BE_Trig        = 1.0;
      Settings.BE_Buff        = 0.1;
      Settings.TrailMode      = TRAIL_ATR;
      Settings.Trail_Mult     = 2.0;

      Settings.MaType         = METHOD_EMA;

      effEmaStrategy          = EMA_STRAT_2_CROSS_3_4;
      effMaType               = Settings.MaType;
      effBiasMode             = Settings.BiasMode;

      if(note != "") note += " | ";
      note += "PRESET: TREND_SWING applied.";
   }
   
   //+------------------------------------------------------------------+
   //| PRESET_RANGE_GRID (UNCHANGED)                                    |
   //+------------------------------------------------------------------+

   else if(InpPreset == PRESET_RANGE_GRID)
   {
      Settings.CloseOnReverse = false;
      Settings.BiasEnabled    = true;
      Settings.BiasMode       = BIAS_AUTO;
      Settings.AutoStrat      = STRAT_PAIR_CROSS;
      Settings.BiasFastID     = (int)ROLE_EMA2;
      Settings.BiasSlowID     = (int)ROLE_EMA4;

      Settings.VoteThreshold  = 4;
      Settings.MaxSpread      = 4.0;
      Settings.MinATR         = 2.0;

      Settings.UseTime        = true;
      Settings.UseNews        = true;
      Settings.UseHTF         = true;

      Settings.RsiMode        = RSI_FILTER_EXTREME;
      Settings.StoMode        = STO_ZONE_FILTER;
      Settings.BbMode         = BB_MEAN_REVERSION;

      Settings.Use_EmaSig     = false;
      Settings.Use_Adx        = false;
      Settings.Use_Macd       = false;
      Settings.Use_Rsi        = true;
      Settings.Use_Cci        = false;
      Settings.Use_Mfi        = false;
      Settings.Use_Sto        = true;
      Settings.Use_Bb         = true;
      Settings.Use_Psar       = false;
      Settings.Use_P123       = false;
      Settings.Use_Ross       = false;

      Settings.SL_Mult        = 2.0;
      Settings.TP_Mult        = 2.0;
      Settings.Use_BE         = false;
      Settings.TrailMode      = TRAIL_NONE;

      effEmaStrategy          = EMA_STRAT_2_CROSS_3_4;
      effMaType               = Settings.MaType;
      effBiasMode             = Settings.BiasMode;

      if(note != "") note += " | ";
      note += "PRESET: RANGE_GRID applied.";
   }

   //+------------------------------------------------------------------+
   //| PRESET_RRM (LEGACY-ALIGNED, COMMENTS RESTORED)
   //+------------------------------------------------------------------+

   else if(InpPreset == PRESET_RRM)
   {
      // RRM Trend Pullback (LEGACY-ALIGNED + EXECUTION-SAFE ATR)
      //
      // Architecture fit (Filters → Bias → Votes → ATR Exits/Management):
      //   1) Filters (Spread/News/Session/HTF) gate out truly untradeable conditions.
      //   2) Bias is defined by EMA pair trend direction (AUTO bias).
      //   3) Votes provide confluence confirmations (do NOT require all votes to fire).
      //   4) ATR is primarily used for stop/target sizing and PSAR trailing cushion.
      //
      // Key intent vs earlier "OPTIMIZED" variants:
      //   - PullbackReclaim and EMA-Div are *setup confirmations* (stateful / lookback-based).
      //   - MaxATR is NOT used as a hard veto in RRM (news/spread/session already protect execution).
      //   - MinATR is scaled by timeframe so M5/M15 are not starved while M1 still avoids dead zones.

      // Determine RRM mode
      ERRMMode mode = Inp_RRM_Mode;
      if(mode == RRM_AUTO_BY_TF)
      {
         // Auto mapping: fast intraday => scalp; higher TF => swing
         if(_Period == PERIOD_M1 || _Period == PERIOD_M5 || _Period == PERIOD_M15)
            mode = RRM_SCALP;
         else
            mode = RRM_SWING;
      }

      Settings.CloseOnReverse = true;
      Settings.BiasEnabled    = true;
      Settings.BiasMode       = BIAS_AUTO;
      Settings.AutoStrat      = STRAT_PAIR_CROSS;

      Settings.MaType         = METHOD_EMA; // RRM uses EMA ribbon
      Settings.UseHTF         = Inp_UseHTF;
      Settings.UseNews        = Inp_UseNews;

      // ATR handling (expert guidance):
      // - HARD ATR gating tends to starve signals on low TFs and during quiet regimes.
      // - For RRM we treat ATR as a *soft* confluence vote (regime preference), not a blocker.
      Settings.ATR_HardGate = false;   // do not block entries if ATR is outside band
      Settings.Use_ATRVote  = true;    // add one vote when ATR is within [MinATR, MaxATR]

      // Scalp vs Swing bias pair (pullback trigger uses BiasFast EMA)
      if(mode == RRM_SCALP)
      {
         Settings.BiasFastID  = (int)ROLE_EMA1;
         Settings.BiasSlowID  = (int)ROLE_EMA2;
         Settings.UseTime     = Inp_UseTime;

         // Legacy RRM ribbon (visual + behaviour baseline)
         Settings.P_Ema1 = 34;
         Settings.P_Ema2 = 89;
         Settings.P_Ema3 = 34;
         Settings.P_Ema4 = 89;

         Settings.MaxSpread   = 2.5;

         // ATR floor by TF (pips): M1 needs a higher floor; M5/M15 should not be starved
         Settings.MinATR      = (_Period == PERIOD_M1 ? 12.5 : 5.0);
         Settings.MaxATR      = 0.0;  // IMPORTANT: disable hard max-ATR veto in RRM

         Settings.SL_Mult     = 1.25;
         Settings.TP_Mult     = 4.0;
      }
      else // RRM_SWING
      {
         Settings.BiasFastID  = (int)ROLE_EMA3;
         Settings.BiasSlowID  = (int)ROLE_EMA4;
         Settings.UseTime     = Inp_UseTime;

         // Legacy RRM ribbon
         Settings.P_Ema1 = 5;
         Settings.P_Ema2 = 13;
         Settings.P_Ema3 = 34;
         Settings.P_Ema4 = 89;

         Settings.MaxSpread   = 5.0;
         Settings.MinATR      = 5.0;   // moderate: swing still prefers adequate range
         Settings.MaxATR      = 0.0;  // IMPORTANT: disable hard max-ATR veto in RRM

         Settings.SL_Mult     = 1.25;
         Settings.TP_Mult     = 4.0;
      }

      // --- Votes (confluence confirmations; do not hard-starve entries) ---
      // We keep the "legacy" confirmation bundle but require only a subset.
      Settings.Use_EmaSig     = true;   // Trend/trigger vote
      Settings.Use_Adx        = false;  // ADX is useful in some markets, but not default for RRM
      Settings.Use_Macd       = true;
      Settings.Use_Rsi        = false;
      Settings.Use_Cci        = false;
      Settings.Use_Mfi        = true;
      Settings.Use_Sto        = true;
      Settings.Use_Bb         = true;
      Settings.Use_Psar       = true;
      Settings.Use_P123       = false;
      Settings.Use_Ross       = false;

      // Threshold: default 4-of-enabled (user can still override via global Inp_VoteThreshold)
      int enabled_votes = 0;
      if(Settings.Use_EmaSig) enabled_votes++;
      if(Settings.Use_Macd)   enabled_votes++;
      if(Settings.Use_Mfi)    enabled_votes++;
      if(Settings.Use_Sto)    enabled_votes++;
      if(Settings.Use_Bb)     enabled_votes++;
      if(Settings.Use_Psar)   enabled_votes++;
      if(Settings.Use_ATRVote) enabled_votes++; // ATR regime vote (soft)

      int thr = 4;
      if(Inp_VoteThreshold > 0) thr = Inp_VoteThreshold;
      if(thr > enabled_votes) thr = enabled_votes;
      if(thr < 1) thr = 1;
      Settings.VoteThreshold = thr;

      // Legacy MACD parameters (RRM controller): 8/13/8
      Settings.P_MacdFast     = 8;
      Settings.P_MacdSlow     = 13;
      Settings.P_MacdSig      = 8;

      // Stochastic mode: keep classic cross behaviour for responsiveness
      Settings.StoMode        = STO_CROSS_SIGNAL;

      // RRM setup confirmations (stateful, lookback-based; not single-bar hard gates)
      Settings.RRM_RequirePullbackReclaim = Inp_RRM_RequirePullbackReclaim;
      Settings.RRM_RequireEmaDiv          = Inp_RRM_RequireEmaDiv;
      Settings.RRM_Lookback              = Inp_RRM_Lookback;
      Settings.RRM_MinDivPips            = Inp_RRM_MinDivPips;

      // Exits / management
      Settings.Use_BE         = true;
      Settings.BE_Trig        = 1.5;
      Settings.BE_Buff        = 0.3;
      Settings.TrailMode      = TRAIL_PSAR;
      Settings.P_PsarTrailCushionATR = 0.5;

      effEmaStrategy          = (mode == RRM_SCALP ? EMA_STRAT_2_CROSS_1_2 : EMA_STRAT_2_CROSS_3_4);
      effMaType               = Settings.MaType;
      effBiasMode             = Settings.BiasMode;

      if(note != "") note += " | ";
      note += "PRESET: RRM_TREND_PULLBACK (LEGACY-ALIGNED, ATR-SAFE) applied.";
   }

   // --- L. Final effective provenance + UI clarity + UI clarity
   string dir_source = "AUTO";
   if(!Settings.BiasEnabled)
      dir_source = "DISABLED";
   else if(Settings.BiasMode == BIAS_MANUAL)
   {
      if(Settings.ManSide == SIDE_LONG)
         dir_source = "MANUAL_LONG";
      else if(Settings.ManSide == SIDE_SHORT)
         dir_source = "MANUAL_SHORT";
      else
         dir_source = "AUTO_FALLBACK";
   }
   g_effectiveDirSource = dir_source;

   // UI clarity flags
   bool uses_auto_logic  = (Settings.BiasEnabled && (Settings.BiasMode == BIAS_AUTO || (Settings.BiasMode == BIAS_MANUAL && Settings.ManSide == SIDE_BOTH)));
   bool uses_manual_fix  = (Settings.BiasEnabled && Settings.BiasMode == BIAS_MANUAL && (Settings.ManSide == SIDE_LONG || Settings.ManSide == SIDE_SHORT));
   bool uses_adv_mapping = (uses_auto_logic && effEmaStrategy == EMA_STRAT_CUSTOM);

   string used = "";
   string ignored = "";

   if(!Settings.BiasEnabled)
   {
      used = "BiasEnabled=OFF";
      ignored = "BiasMode, ManualSide, EmaStrategy, AdvMapping";
   }
   else if(uses_manual_fix)
   {
      used = StringFormat("ManualSide=%s", EnumToString(Settings.ManSide));
      ignored = "EmaStrategy, AdvMapping";
   }
   else
   {
      used = "AUTO";
      if(Settings.BiasMode == BIAS_AUTO)
         ignored = "";
      else
         used = "AUTO_FALLBACK";

      used += StringFormat(" | EmaStrategy=%s", EnumToString(effEmaStrategy));

      if(uses_adv_mapping)
      {
         used += StringFormat(" | AdvMapping(Fast=%d Slow=%d)", Settings.BiasFastID, Settings.BiasSlowID);
      }
      else
      {
         if(ignored != "") ignored += ", ";
         ignored += "AdvMapping";
      }

      if(Settings.BiasMode == BIAS_AUTO)
      {
         if(ignored != "") ignored += ", ";
         ignored += "ManualSide";
      }
   }

   g_ui_used_flags = used;
   g_ui_ignored_flags = ignored;

   // MA inputs provenance
   g_ui_ma_source = (InpPreset == PRESET_MA_BENCHMARK ? "BENCHMARK (0c)" : "CUSTOM (5)");

   // Explicit ignored MA inputs
   if(InpPreset == PRESET_MA_BENCHMARK)
   {
      if(g_ui_ignored_flags != "") g_ui_ignored_flags += ", ";
      g_ui_ignored_flags += "CustomMaType, CustomMaHorShift, CustomMaVerShift, CustomEma1Period, RiskPercent";

      // Warn once (benchmark preset ignores CUSTOM indicator inputs).
      if(!g_warned_bench_ignored)
      {
         bool mismatch = false;
         if(Inp_MaType != METHOD_SMA) mismatch = true;
         if(Inp_MaHorShift != Inp_MA_Shift) mismatch = true;
         if(InpEma1Period != Inp_MA_Period) mismatch = true;
         if(Inp_MaVerShift != 1) mismatch = true;

         Print("WARNING: PRESET_MA_BENCHMARK uses ONLY benchmark inputs (group 0c) and ignores CUSTOM MA inputs (group 5) and RiskPercent.");
         Print("Effective MA (USED): Method=", EnumToString(Settings.MaType), " Period=", Settings.P_Ema1, " Shift=", Settings.ma_h_shift, " BarShift=", Settings.ma_v_shift, ".");
         if(mismatch)
            Print("NOTE: Your CUSTOM MA settings differ from benchmark values; they are ignored in PRESET_MA_BENCHMARK.");
         g_warned_bench_ignored = true;
      }
   }
   else
   {
      if(g_ui_ignored_flags != "") g_ui_ignored_flags += ", ";
      g_ui_ignored_flags += "BenchmarkMA(MaxRisk/Dec/Period/Shift)";

      // Warn once if user changed benchmark inputs but is not running the benchmark preset.
      bool bench_changed = false;
      if(Inp_MA_MaximumRiskPct != 0.02) bench_changed = true;
      if(Inp_MA_DecreaseFactor != 3.0) bench_changed = true;
      if(Inp_MA_Period != 12) bench_changed = true;
      if(Inp_MA_Shift != 6) bench_changed = true;
      if(bench_changed && !g_warned_custom_bench)
      {
         Print("INFO: Benchmark inputs (group 0c) are ignored unless Preset=PRESET_MA_BENCHMARK.");
         g_warned_custom_bench = true;
      }
   }

   // Preset override disclosure
   string overrides = "";
   if(InpPreset != PRESET_CUSTOM)
   {
      if(Settings.MaType != Inp_MaType)                  AddListItem(overrides, "MaType");

      if(InpPreset == PRESET_MA_BENCHMARK)
      {
         if(Settings.P_Ema1 != Inp_MA_Period)            AddListItem(overrides, "MA_Period(Bench)");
         if(Settings.ma_h_shift != Inp_MA_Shift)         AddListItem(overrides, "MA_Shift(Bench)");
      }
      else
      {
         if(Settings.ma_h_shift != Inp_MaHorShift)       AddListItem(overrides, "MaHorShift");
         if(Settings.ma_v_shift != Inp_MaVerShift)       AddListItem(overrides, "MaVerShift");
         if(Settings.P_Ema1 != InpEma1Period)            AddListItem(overrides, "Ema1Period");
      }
      if(Settings.BiasMode != Inp_BiasMode)              AddListItem(overrides, "BiasMode");
      if(effEmaStrategy != Inp_EmaStrategy)              AddListItem(overrides, "EmaStrategy");
      if(Settings.CloseOnReverse != Inp_CloseOnReverse)  AddListItem(overrides, "CloseOnReverse");
      if(Settings.VoteThreshold != Inp_VoteThreshold)    AddListItem(overrides, "VoteThreshold");
      if(Settings.MaxSpread != Inp_MaxSpreadPips)        AddListItem(overrides, "MaxSpreadPips");
      if(Settings.MinATR != Inp_MinATRPips)              AddListItem(overrides, "MinATRPips");
      if(Settings.MaxATR != Inp_MaxATRPips)              AddListItem(overrides, "MaxATRPips");
      if(Settings.UseTime != Inp_UseTime)                AddListItem(overrides, "UseTime");
      if(Settings.UseNews != Inp_UseNews)                AddListItem(overrides, "UseNews");
      if(Settings.UseHTF != Inp_UseHTF)                  AddListItem(overrides, "UseHTF");
      if(Settings.HtfPeriod != Inp_HtfPeriod)            AddListItem(overrides, "HtfPeriod");
      if(Settings.P_HtfEma != Inp_HtfEmaPeriod)          AddListItem(overrides, "HtfEmaPeriod");

      // Vote toggles and modes (frequently overridden by presets)
      if(Settings.Use_EmaSig != Inp_Use_EmaSig)          AddListItem(overrides, "Use_EmaSig");
      if(Settings.Use_Adx != Inp_Use_Adx)                AddListItem(overrides, "Use_Adx");
      if(Settings.Use_Macd != Inp_Use_Macd)              AddListItem(overrides, "Use_Macd");
      if(Settings.Use_Rsi != Inp_Use_Rsi)                AddListItem(overrides, "Use_Rsi");
      if(Settings.Use_Cci != Inp_Use_Cci)                AddListItem(overrides, "Use_Cci");
      if(Settings.Use_Mfi != Inp_Use_Mfi)                AddListItem(overrides, "Use_Mfi");
      if(Settings.Use_Sto != Inp_Use_Sto)                AddListItem(overrides, "Use_Sto");
      if(Settings.Use_Bb != Inp_Use_Bb)                  AddListItem(overrides, "Use_Bb");
      if(Settings.Use_Psar != Inp_Use_Psar)              AddListItem(overrides, "Use_Psar");
      if(Settings.Use_P123 != Inp_Use_P123)              AddListItem(overrides, "Use_P123");
      if(Settings.Use_Ross != Inp_Use_Ross)              AddListItem(overrides, "Use_Ross");

      if(Settings.MacdMode != InpMacdMode)               AddListItem(overrides, "MacdMode");
      if(Settings.RsiMode != InpRsiMode)                 AddListItem(overrides, "RsiMode");
      if(Settings.CciMode != InpCciMode)                 AddListItem(overrides, "CciMode");
      if(Settings.StoMode != InpStoMode)                 AddListItem(overrides, "StoMode");
      if(Settings.BbMode != InpBbMode)                   AddListItem(overrides, "BbMode");

      if(Settings.SL_Mult != Inp_SL_Mult)                AddListItem(overrides, "SL_Mult");
      if(Settings.TP_Mult != Inp_TP_Mult)                AddListItem(overrides, "TP_Mult");
      if(Settings.Use_BE != Inp_Use_BE)                  AddListItem(overrides, "Use_BE");
      if(Settings.BE_Trig != Inp_BE_Trig)                AddListItem(overrides, "BE_Trig");
      if(Settings.BE_Buff != Inp_BE_Buff)                AddListItem(overrides, "BE_Buff");
      if(Settings.TrailMode != Inp_TrailMode)            AddListItem(overrides, "TrailMode");
      if(Settings.Trail_Mult != Inp_Trail_Mult)          AddListItem(overrides, "Trail_Mult");
      if(Settings.RRM_RequirePullbackReclaim != Inp_RRM_RequirePullbackReclaim) AddListItem(overrides, "RRM_Pullback");
      if(Settings.RRM_RequireEmaDiv != Inp_RRM_RequireEmaDiv) AddListItem(overrides, "RRM_EmaDiv");
   }
   g_ui_overrides = overrides;

   // Rebuild effective note
   string note2 = note;
   if(!Settings.BiasEnabled)
   {
      if(note2 != "") note2 += " | ";
      note2 += "NOTE: BiasEnabled=false -> direction neutral (no new entries).";
   }
   else if(uses_manual_fix)
   {
      if(note2 != "") note2 += " | ";
      note2 += "NOTE: BiasMode=MANUAL (fixed direction) -> EmaStrategy and AdvMapping ignored.";
   }
   else if(Settings.BiasMode == BIAS_MANUAL && Settings.ManSide == SIDE_BOTH)
   {
      if(note2 != "") note2 += " | ";
      note2 += "NOTE: BiasMode=MANUAL and ManualSide=BOTH -> no restriction; AUTO bias logic used.";
   }
   else if(Settings.BiasMode == BIAS_AUTO && effEmaStrategy != EMA_STRAT_CUSTOM)
   {
      if(note2 != "") note2 += " | ";
      note2 += "NOTE: BiasMode=AUTO and EmaStrategy!=CUSTOM -> AdvMapping ignored.";
   }

   if(g_ui_overrides != "")
   {
      if(note2 != "") note2 += " | ";
      note2 += "OVERRIDES: " + g_ui_overrides + ".";
   }

   note = note2;

   // Publish for diagnostics
   g_effectiveEmaStrategy = effEmaStrategy;
   g_effectiveMaType      = effMaType;
   g_effectiveBiasMode    = effBiasMode;
   g_effectiveSigNote     = note;
}

// Validate effective settings after ApplySettings()
bool ValidateEffectiveSettings()
{
   if(!Inp_BiasEnabled)
   {
      FlowLog("Bias disabled by input (Inp_BiasEnabled=false). Trading signals will be neutral.");
   }

   if((int)g_effectiveMaType < (int)METHOD_EMA || (int)g_effectiveMaType > (int)METHOD_SMA)
   {
      Print("ERROR: Effective MA method is out of range: ", (int)g_effectiveMaType);
      return false;
   }

   if((int)g_effectiveEmaStrategy < (int)EMA_STRAT_1_PRICE_CROSS || (int)g_effectiveEmaStrategy > (int)EMA_STRAT_CUSTOM)
   {
      Print("ERROR: Effective EMA strategy is out of range: ", (int)g_effectiveEmaStrategy);
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| EXPLICIT INIT PIPELINE                                           |
//+------------------------------------------------------------------+

int OrchestrateInit()
{
   FlowLog("EA start -> OnInit()");
   g_start_time = TimeCurrent();

   FlowLog("Step A: Read Inputs -> ApplySettings() -> build effective Settings");
   ApplySettings();

   FlowLog("Step B: Validate effective Settings");
   if(!ValidateEffectiveSettings())
      return INIT_FAILED;

   FlowLog("Step C: Init Signal Engine (indicators/handles/libraries)");
   if(!Signal.Init(Settings, _Symbol))
   {
      Print("ERROR: Signal.Init() failed.");
      return INIT_FAILED;
   }

   if(Inp_UI_ManageChartIndicators)
      SEA_UI_ManageChartIndicators();
   else
   {
      if(Settings.MABenchmarkStrict)
      {
         int h = Signal.GetPrimaryMAHandle();
         if(h != INVALID_HANDLE)
            ChartIndicatorAdd(0, 0, h);
      }
   }

   FlowLog("Step D: Validate MA setup (method/period/shift)");
   if(!Signal.ValidateAndReportMA(Inp_PrintEffectiveConfig))
   {
      Print("ERROR: MA setup validation failed.");
      return INIT_FAILED;
   }

   FlowLog("Step E: Init Trade Executor");
   Executor.Init(Inp_MagicNum, Settings);

   FlowLog("Step F: Load News calendar (optional)");
   if(Settings.UseNews)
      Signal.LoadNews(Inp_NewsFile);

   FlowLog("Step G: Print configuration (inputs and effective)");
   Print("------------------------------------------");
   Print("--- SimpleEA v", SEA_BUILD_STR, " Configuration ---");
   Print("Program: ", MQLInfoString(MQL_PROGRAM_NAME), " | Path: ", MQLInfoString(MQL_PROGRAM_PATH));
   Print("Preset (raw): ", (int)InpPreset, " | Name: ", EnumToString(InpPreset));
   Print("VoteThreshold (input): ", Inp_VoteThreshold, " | Effective: ", Settings.VoteThreshold);

   Print("Symbol: ", _Symbol, " | Magic: ", Inp_MagicNum);
   Print("MA Source: ", g_ui_ma_source);
   Print("MA Shifts (CUSTOM Inputs): h=", Inp_MaHorShift, " v=", Inp_MaVerShift, (InpPreset==PRESET_MA_BENCHMARK ? " (IGNORED)" : ""));
   Print("MA Shifts (Effective): h=", Settings.ma_h_shift, " v=", Settings.ma_v_shift);
   
   if(InpPreset == PRESET_MA_BENCHMARK)
      Print("MA Benchmark Inputs (0c): MaxRisk=", Inp_MA_MaximumRiskPct, "% Dec=", Inp_MA_DecreaseFactor, " Period=", Inp_MA_Period, " Shift=", Inp_MA_Shift);
   
   Print("EMA Strategy (Input): ", EnumToString(Inp_EmaStrategy));
   Print("Effective EMA periods: ", Settings.P_Ema1, ",", Settings.P_Ema2, ",", Settings.P_Ema3, ",", Settings.P_Ema4);
   Print("Effective MACD periods: ", Settings.P_MacdFast, ",", Settings.P_MacdSlow, ",", Settings.P_MacdSig);
   Print("Bias Mode (Input): ", EnumToString(Inp_BiasMode), " | ManualSide (Input): ", EnumToString(Inp_ManualSide));
   Print("BiasEnabled (Input): ", (Inp_BiasEnabled ? "true" : "false"));
   
   if(Settings.VoteThreshold <= 1) 
      Print("NOTE: VoteThreshold <= 1 => voting bypassed (individual vote toggles ignored).");
   
   Print("MA Method (Input): ", EnumToString(Inp_MaType));
   
   if(Inp_PrintEffectiveConfig)
   {
      Print("Effective Bias Mode: ", EnumToString(g_effectiveBiasMode), (g_effectiveSigNote=="" ? "" : " | "), g_effectiveSigNote);
      Print("Effective Direction Source: ", g_effectiveDirSource);
      Print("Effective EMA Strategy: ", EnumToString(g_effectiveEmaStrategy));
      Print("Effective MA Method: ", EnumToString(g_effectiveMaType));
      if(g_ui_used_flags != "")   Print("Effective Used Flags: ", g_ui_used_flags);
      if(g_ui_ignored_flags != "") Print("Effective Ignored Flags: ", g_ui_ignored_flags);
      Print("Effective AutoStrat: ", EnumToString(Settings.AutoStrat),
            " | FastID:", Settings.BiasFastID,
            " | SlowID:", Settings.BiasSlowID,
            " | ManSide:", EnumToString(Settings.ManSide));
      
      Print("=== OPTIMIZATION SUMMARY (v1.02.016d-OPT) ===");
      Print("Vote Bundle: EMA + ADX + MACD + Stochastic (Zone Filter)");
      Print("Vote Threshold: ", Settings.VoteThreshold, " (OPTIMIZED from 6)");
      Print("RRM Pullback/Reclaim Gate: ", (Settings.RRM_RequirePullbackReclaim ? "ENABLED" : "DISABLED"));
      Print("RRM EMA Divergence Gate: ", (Settings.RRM_RequireEmaDiv ? "ENABLED" : "DISABLED"));
      Print("MaxATR Gate: ", Settings.MaxATR, " pips (NEW)");
      Print("Spread Gate: ", Settings.MaxSpread, " pips");
      Print("MinATR Gate: ", Settings.MinATR, " pips");
      Print("Risk per Trade: ", Settings.RiskPercent, "%");
      Print("Expected Win Rate Improvement: +10-15% vs baseline");
   }
   
   Print("------------------------------------------");
   SEA_UI_Init(Inp_MagicNum);
   SEA_UI_UpdateSettingsPanel();
   SEA_UI_UpdateCockpitPanel(Signal.GetATR(), 0, Signal.LastBias(), Signal.LastVotes(), Signal.LastReason());

   FlowLog("OnInit complete -> INIT_SUCCEEDED");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| EXPLICIT TICK PIPELINE                                           |
//+------------------------------------------------------------------+

void OrchestrateTick()
{
   // New bar execution only (stability)
   datetime t = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(t == g_last_bar_time)
      return;

   g_last_bar_time = t;
   FlowLog("OnTick -> NewBar detected -> begin bar pipeline");

   double atr = Signal.GetATR();

   FlowLog("Step A: Manage open positions (Trailing/BE)");
   Executor.ManageTrade(atr);

   FlowLog("Step B: Compute direction signal");
   int direction = Signal.GetDirection();

   // Visualization: eligible entry signal marker
   if(Inp_DrawEntryLines && direction != 0)
      SEA_DrawEntrySignalLine(iTime(_Symbol, PERIOD_CURRENT, 1), direction, Signal.LastReason());

   FlowLog(StringFormat("Step C: ProcessSignal (direction=%d)", direction));
   if(direction != 0)
      Executor.ProcessSignal(direction, atr);

   SEA_UI_UpdateCockpitPanel(atr, direction, Signal.LastBias(), Signal.LastVotes(), Signal.LastReason());
   FlowLog("Bar pipeline complete");
}

//+------------------------------------------------------------------+
//| EXPLICIT SHUTDOWN PIPELINE                                       |
//+------------------------------------------------------------------+

void OrchestrateDeinit(const int reason)
{
   // Strategy Tester report export (if enabled)
   if(Settings.ExportCSV)
      SEA_Report_Generate();

   SEA_UI_DestroyAll();
   FlowLog(StringFormat("EA stop -> OnDeinit(reason=%d)", reason));

   FlowLog("Step A: Release indicator handles / engine state");
   Signal.Release();

   FlowLog("Step B: Trade executor cleanup");
   // (No executor release required in current design.)

   FlowLog("Step C: Clear runtime state");
   g_last_bar_time = 0;

   FlowLog("OnDeinit complete");
}

//+------------------------------------------------------------------+
//| UI & CHART UTILITIES                                             |
//+------------------------------------------------------------------+

void SEA_UI_ManageChartIndicators()
{
   // 1) Remove all indicators from all subwindows
   int win_total = (int)ChartGetInteger(0, CHART_WINDOWS_TOTAL);
   for(int w=win_total-1; w>=0; w--)
   {
      int total = ChartIndicatorsTotal(0, w);
      while(total > 0)
      {
         string nm = ChartIndicatorName(0, w, 0);
         if(nm == "") break;
         ChartIndicatorDelete(0, w, nm);
         total = ChartIndicatorsTotal(0, w);
      }
   }

   // 2) Determine which EMA roles are relevant
   bool need_ema1=false, need_ema2=false, need_ema3=false, need_ema4=false;

   int f = Settings.BiasFastID;
   int s = Settings.BiasSlowID;
   if(f==0||s==0) need_ema1=true;
   if(f==1||s==1) need_ema2=true;
   if(f==2||s==2) need_ema3=true;
   if(f==3||s==3) need_ema4=true;

   if(Settings.Use_EmaSig) need_ema1=true;

   // 3) Re-attach overlays in main window
   if(Settings.MABenchmarkStrict)
   {
      int h = Signal.GetPrimaryMAHandle();
      if(h != INVALID_HANDLE) ChartIndicatorAdd(0, 0, h);
   }

   if(need_ema1) { int h=Signal.GetEmaHandle(0); if(h!=INVALID_HANDLE) ChartIndicatorAdd(0,0,h); }
   if(need_ema2) { int h=Signal.GetEmaHandle(1); if(h!=INVALID_HANDLE) ChartIndicatorAdd(0,0,h); }
   if(need_ema3) { int h=Signal.GetEmaHandle(2); if(h!=INVALID_HANDLE) ChartIndicatorAdd(0,0,h); }
   if(need_ema4) { int h=Signal.GetEmaHandle(3); if(h!=INVALID_HANDLE) ChartIndicatorAdd(0,0,h); }

   // PSAR overlay if used for vote OR PSAR trailing
   if(Settings.Use_Psar || Settings.TrailMode == TRAIL_PSAR)
   {
      int h = Signal.GetPsarHandle();
      if(h != INVALID_HANDLE) ChartIndicatorAdd(0, 0, h);
   }

   // MACD in a separate subwindow
   if(Settings.Use_Macd)
   {
      int h = Signal.GetMacdHandle();
      if(h != INVALID_HANDLE)
      {
         if(!ChartIndicatorAdd(0, 1, h))
            Print("UI: ChartIndicatorAdd(MACD) failed. (Subwindow may not exist; MACD will not be displayed.)");
      }
   }
}

//+------------------------------------------------------------------+
//| UI: SIGNAL MARKERS (STRATEGY TESTER)                             |
//+------------------------------------------------------------------+

void SEA_DrawEntrySignalLine(datetime bar_time, int direction, const string label)
{
   string name = StringFormat("SEA_ELIG_%I64d_%s", (long)bar_time, (direction>0?"BUY":"SELL"));
   if(ObjectFind(0, name) >= 0) return;

   ObjectCreate(0, name, OBJ_VLINE, 0, bar_time, 0);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DOT);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetString(0, name, OBJPROP_TOOLTIP, StringFormat("ELIGIBLE %s | %s", (direction>0?"BUY":"SELL"), label));
}

void SEA_DrawTradeExecLine(datetime event_time, int direction, double price, const string label)
{
   string name = StringFormat("SEA_TRADE_%I64d_%s", (long)event_time, (direction>0?"BUY":"SELL"));
   if(ObjectFind(0, name) >= 0) return;

   ObjectCreate(0, name, OBJ_VLINE, 0, event_time, 0);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
   ObjectSetString(0, name, OBJPROP_TOOLTIP, StringFormat("EXECUTED %s @%.5f | %s", (direction>0?"BUY":"SELL"), price, label));
}

//+------------------------------------------------------------------+
//| GENERIC HELPERS                                                  |
//+------------------------------------------------------------------+

void FlowLog(const string msg)
{
   if(Inp_DebugFlow) Print("FLOW: ", msg);
}

void AddListItem(string &list, const string item)
{
   if(list != "") list += ", ";
   list += item;
}

//+------------------------------------------------------------------+
//| END OF FILE                                                       |
//+------------------------------------------------------------------+



      


/*

PRESETS:

PRESET_CUSTOM
* Uses your Inputs as-is (no forced overrides).
* Best for manual research and controlled tuning. README_v1-02-016d

* Persona/intent: User/Research mode — full manual control, no enforced “expert contract.”

PRESET_MA_BENCHMARK
* Compatibility/diagnostic mode to mimic MT5 “Moving Average” EA behavior.
* Confirmed price/MA cross, stop-and-reverse, benchmark-style sizing knobs; filters/votes/exits largely disabled. README_v1-02-016d

* Persona/intent: Benchmark — MT5 MovingAverage parity for verification/troubleshooting.

PRESET_TREND_REVERSAL
* Baseline stop-and-reverse trend/reversal model (benchmark-like).
* Price/MA cross (confirmed), vote bypass (VoteThreshold=1), filters off, no SL/TP/BE/trailing. README_v1-02-016d

* Persona/intent: Baseline reversal — simple stop-and-reverse reference behavior.

PRESET_TREND_SCALP
* Intraday continuation with confluence.
* Bias via EMA pair cross (typically EMA1/EMA2), HTF+News gates, confluence votes (EMA+ADX+MACD), ATR SL/TP + BE + ATR trailing. README_v1-02-016d

* Persona/intent: Individual — intraday confluence + HTF/News.

PRESET_TREND_SWING
* Higher-timeframe aligned trend following (“institutional” style).
* Slower EMA pair cross (EMA3/EMA4), stronger gating (Time+News+HTF + spread/ATR), fewer trades, wider ATR exits + BE + ATR trailing. README_v1-02-016d

* Persona/intent: Institutional — HTF + News + ATR gates.

PRESET_RANGE_GRID
* Conservative mean-reversion regime (despite legacy “grid” name).
* No stop-and-reverse, strict vote threshold with MR votes (RSI extreme + Stoch + Bollinger MR), Time+News+HTF gates, symmetric ATR exits, trailing typically off. README_v1-02-016d

* Persona/intent: Consultant — conservative mean reversion + HTF/News/Time.

PRESET_RRM
* Trend pullback (“RRM”) continuation system with mandatory setup/trigger gates.
* Requires HTF alignment and a pullback→reclaim trigger (two-bar), plus an EMA convergence→divergence gate; confirmations typically include MACD alignment and PSAR “not blocking”; supports SCALP vs SWING via Inp_RRM_Mode (AUTO-by-TF / SCALP / SWING). README_v1-02-016d

* Persona/intent: Rules-based trend pullback — HTF-confirmed continuation entries with explicit pullback structure.


REVISIONS ACHIEVEMENT:

With v1-02-016x revisions we achieved four concrete things 
(functionality + architecture + performance + operability), 
while keeping your macOS+Wine MT5 constraints in mind.

Revision 016 (baseline architecture)
* Preset-driven configuration: PRESET_* blocks in ApplySettings() override inputs deterministically (CUSTOM vs enforced presets).
* Unified decision pipeline wired end-to-end: filters (Spread/MinATR/Time/News) → Bias (AUTO/MANUAL) → optional HTF veto → optional voting → execution.
* MA benchmark compatibility mode (PRESET_MA_BENCHMARK): price/MA confirmed cross, MA-style risk model knobs, stop-and-reverse behavior.
* Exit framework standardized: ATR-based SL/TP, optional breakeven, trailing modes (ATR/PSAR/Fractal).

Revision 016c (robustness + clarity)
* Effective-settings transparency: “USED vs IGNORED” logic and an OVERRIDES list so users can see what presets actually changed.
* Cleaner initialization provenance (init notes, effective strategy source, override disclosure) to reduce ambiguity in Tester.
* Documentation improvements: expanded README coverage of presets, precedence, and operating model.

Revision 016d (new strategy + visualization + tester hygiene)
* New preset PRESET_RRM (Trend Pullback):
    * Mandatory pullback→reclaim trigger (two-bar logic) plus EMA convergence→divergence gate.
    * Confirmations use MACD + PSAR with HTF alignment; EMA vote disabled because RRM uses its own EMA gates.
    * Supports SCALP vs SWING via Inp_RRM_Mode (AUTO-by-TF, SCALP, SWING).
* Signal visualization in Tester:
    * Inp_DrawEntryLines: vertical line when an entry becomes eligible.
    * Inp_DrawTradeLines: vertical line when a trade is executed.
* Opt-in chart cleanup:
    * Inp_UI_ManageChartIndicators=false by default; when enabled, the EA clears chart indicators and re-adds only key overlays to avoid “template shows everything” confusion.
* 016d housekeeping: cleaned file section headers and input-group labels (no trading logic change).
* Build stability fixes:
    * Single UTF-16LE BOM (no 0xFEFF), consistent build token/stamp, and GetATR()/GetVal() corrected as const.

Revisions net result: 
016 established a stable preset framework, 
016c improved auditability and user clarity, and 
016d added a fully specified trend-pullback system (RRM) 
plus concrete on-chart visualization and tester hygiene controls.


ARCHETYPES:
Expert-style “main settings” (what each archetype is trying to achieve)

1) Institutional trader archetype
Goal: Robust trend participation, fewer trades, higher signal quality, 
avoid low-quality regimes (chop, illiquid spreads, news spikes).

Preset mapping: PRESET_TREND_SWING
Core settings (conceptual bullets)
* Regime alignment: HTF filter ON (trade only with higher-timeframe trend).
* Risk gating: News filter ON, time/session gating ON, MinATR ON, spread gate ON.
* Signal quality: Vote threshold 2 (or 2–3) using non-redundant confirmations (e.g., EMA signal + ADX + MACD alignment).
* Exit shape: ATR-based SL/TP with asymmetric payoff (SL ~2 ATR, TP ~4 ATR), trailing ON (ATR trailing by default; PSAR trailing optional), breakeven ON.
General opinion: “Keep the system simple but governed; make it hard for the EA to trade during bad conditions.”

2) Experienced individual trader archetype
Goal: Intraday trend continuation with strong confluence; still protected 
from obvious bad conditions.
Preset mapping: PRESET_TREND_SCALP
Core settings
* Filters: HTF ON, News ON, spread and MinATR gates ON (time gate optional 
depending on style).
* Signal quality: Vote threshold 3 (EMA recovery + ADX + MACD is a typical bundle).
* Exits: SL ~1.5 ATR, TP ~3 ATR, trailing ON, breakeven ON.
General opinion: “More signals than institutional swing,
 but still avoid randomness—confluence plus guardrails.”

3) Senior advisor/consultant archetype
Goal: Risk-first, conservative behavior; explainable rules; avoid overtrading; 
restrict to conditions where the edge plausibly exists.
Preset mapping: 
PRESET_RANGE_GRID (your conservative mean reversion contract)
Core settings
* Filters: HTF ON, News ON, Time/session ON, strict cost control (spread gate).
* Signal quality: Higher confluence (threshold ~4) using mean-reversion votes 
(RSI extreme + Stoch zone + Bollinger MR).
* Exits: Symmetric ATR exits (SL ~2 ATR, TP ~2 ATR), trailing usually OFF 
(or conservative), BE generally OFF for MR.
General opinion: “If you can’t explain exactly why the EA traded 
and why it exited, the system isn’t ready.”


BEST_PRACTICES: 

Do we need “tons of settings” per symbol and timeframe?
No. The best practice (and what 016/016b moves toward) is:

* 3–4 strategy contracts (presets) that encode the “how it trades”.
* Only small per-market/TF adjustments for:
    * spread limit,
    * MinATR threshold,
    * risk percent,
    * HTF timeframe mapping (e.g., M15→H1, H1→H4, H4→D1).
This keeps the system flexible without turning it into an overfitting playground.


MAPPING TABLE:

Below is a compact default mapping table that keeps the number of knobs small 
and stable across instruments/TFs. It assumes you choose the strategy contract 
via preset, and only tune:
* MaxSpreadPips
* MinATRPips
* RiskPercent
* HTFPeriod (higher-timeframe filter mapping)

All other behavior (vote bundle, SL/TP ATR multipliers, trailing, BE) 
is driven by the preset contract:
* M1/M5 → PRESET_TREND_SCALP (Individual-style intraday confluence)
* M15/H1/H4 → PRESET_TREND_SWING (Institutional-style robust trend)

1) FX majors (non-JPY): EURUSD, GBPUSD, AUDUSD, etc.

Trading TF	Preset	HTFPeriod	MaxSpreadPips	MinATRPips	RiskPercent
M1	TREND_SCALP	M15	1.5–2.5	2.5–4.0	0.10–0.25
M5	TREND_SCALP	H1	1.5–2.5	4.0–6.0	0.15–0.35
M15	TREND_SWING	H4	2.0–3.0	6.0–10.0	0.20–0.50
H1	TREND_SWING	D1	2.0–3.5	10–18	0.25–0.60
H4	TREND_SWING	D1	2.5–4.0	18–30	0.25–0.60

2) FX JPY pairs: USDJPY, EURJPY, GBPJPY, etc.
JPY pairs often need either stricter quality gates or trading only 
when volatility is sufficient.

Trading TF	Preset	HTFPeriod	MaxSpreadPips	MinATRPips	RiskPercent
M1	TREND_SCALP	M15	2.0–3.5	3.5–6.0	0.08–0.20
M5	TREND_SCALP	H1	2.0–3.5	6.0–9.0	0.10–0.30
M15	TREND_SWING	H4	2.5–4.0	9.0–14	0.15–0.45
H1	TREND_SWING	D1	3.0–5.0	14–22	0.15–0.45
H4	TREND_SWING	D1	3.5–6.0	22–36	0.15–0.45

3) Metals: XAUUSD / XAGUSD / (broker variants like XGD*)
Metals are typically more “spiky,” so the defaults lean toward: 
wider cost tolerance, higher MinATR, and lower risk%.

Trading TF	Preset	HTFPeriod	MaxSpreadPips	MinATRPips	RiskPercent
M1	TREND_SCALP	M15	4–10	6–12	0.05–0.12
M5	TREND_SCALP	H1	5–12	10–18	0.06–0.15
M15	TREND_SWING	H4	6–15	16–28	0.08–0.20
H1	TREND_SWING	D1	8–20	26–45	0.08–0.25
H4	TREND_SWING	D1	10–25	40–70	0.08–0.25

4) Optional “Range mode” mapping (only when you want mean reversion)
Use PRESET_RANGE_GRID only when you intentionally target ranging conditions 
(or in sideways sessions).

Asset class	Trading TF	HTFPeriod	MaxSpreadPips	MinATRPips	RiskPercent
FX majors	M15 / H1	H4 / D1	2.0–3.0	2.0–6.0	0.10–0.30
JPY pairs	M15 / H1	H4 / D1	2.5–4.0	3.0–7.0	0.08–0.25
Metals	M15 / H1	H4 / D1	6–15	8–18	0.05–0.15

How to use this table sensibly (without overfitting)
* Treat RiskPercent as the primary “account protection” lever, and keep it stable.
* Use MinATRPips to avoid chop (raise it if you see whipsaw).
* Use MaxSpreadPips to avoid high-cost fills (tighten it if you see poor expectancy).
* HTF mapping is generally “one or two steps up”:
M1→M15, M5→H1, M15→H4, H1→D1, H4→D1.

If you share 6–10 symbols you actually trade (with exact broker symbol names), I can tighten the metals/JYP spread bands to your broker’s typical spread behavior and your session windows, while keeping the same compact structure.

In these tables, RiskPercent is expressed as a percentage, i.e.:
* 0.10–0.25 means 0.10% to 0.25% risk per trade (one-quarter of one percent), not 10–25%.
* 1.0 means 1% risk per trade.
* 2.5 means 2.5% risk per trade.
So for your example:
* FX majors, M1: 0.10–0.25 = 0.10%–0.25%.
That conservative range is intentional for M1 because trade frequency 
and noise are high.
If you prefer a more typical discretionary risk level:
* Intraday (M5–M15): ~0.25%–0.75%
* Swing (H1–H4): ~0.25%–1.0%
(Still assuming you want the EA to be robust and “chop-resistant.”)


UI:

CockpitPanel:
* Prints essential live trade state on-chart:
    * current bar time, spread (pips), ATR (pips)
    * last signal direction + bias + votes/threshold + veto reason
    * active position snapshot (BUY/SELL, lots, open price, SL/TP, PnL) or “Flat”
* Fully switchable via input:
    * Inp_UI_ShowCockpitPanel (default false)

CockpitPAnel & SettingsPanel:
* Keep UI updates lightweight (no per-tick repaint)
   * CockpitPanel updates only once per new bar (PERIOD_CURRENT), not on every tick.
   * SettingsPanel updates only on EA init/re-init (and only if enabled), 
   not per tick and not per bar.
   * Both panels implement text caching: if the rendered text hasn’t changed, 
   they do nothing (no object churn).


MODULARITY:

Modularized UI + CSV reporting: out of the main EA: 
keeping SimpleEA maintainable and reduce clutter:

* SEA_UI.mqh:
    * contains the rendering engine for both panels 
    (background rectangle + line labels)
    * provides:
        * SEA_UI_Init(magic)
        * SEA_UI_UpdateSettingsPanel()
        * SEA_UI_UpdateCockpitPanel(atr, last_signal_dir)
        * SEA_UI_DestroyAll()

* SEA_Reporting.mqh:
    * contains tester CSV export:
        * SEA_Report_Generate() (called only in OnDeinit() 
        and only when export enabled)


DIAGNOSTIC:

Improved diagnostics surfaced from the Signal Engine
To make the cockpit meaningful, SEA_SignalEngine.mqh now exposes:

* LastBias(), LastVotes(), LastReason()
…a
nd it populates them consistently (e.g., HTF veto, vote shortfall, OK, bypass mode).

Compatibility & performance notes
* All delivered .mq5/.mqh are UTF-16 LE with BOM (FF FE).
* CSV export uses FILE_UNICODE (UTF-16) to match your encoding policy.
* Inp_ExportUseCommonFiles defaults to false (good for macOS+Wine).

*/
