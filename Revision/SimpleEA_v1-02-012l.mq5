//+------------------------------------------------------------------+
//|                                          SimpleEA_v1-02-012l.mq5 |
//|                              MJS Institutional Trading Solutions |
//|             GOLDEN MASTER: Easy Setup + Full Logging & Format    |
//+------------------------------------------------------------------+
// SAVE AS UTF-16 LE WITH BOM
#property copyright "SimpleEA Redesign v1.02.12l"
#property version   "102.012"
#property strict

//+------------------------------------------------------------------+
//| 1. DEFINITIONS & ENUMS                                           |
//+------------------------------------------------------------------+

// --- MA METHOD SELECTOR ---
enum EMaMethod {
   METHOD_EMA, // Exponential (Reacts faster, standard for this EA)
   METHOD_SMA  // Simple (Smoother, standard for MT5 Benchmarks)
};

// --- SIMPLE EMA SELECTOR ---
enum EEmaStrategy {
   EMA_STRAT_1_PRICE_CROSS,      // 1 EMA: Buy if Price > EMA1 (Benchmark)
   EMA_STRAT_2_CROSS_1_2,        // 2 EMAs: Buy if EMA1 > EMA2 (Golden Cross)
   EMA_STRAT_2_CROSS_3_4,        // 2 EMAs: Buy if EMA3 > EMA4 (Slow Trend)
   EMA_STRAT_CUSTOM              // Manual: Use "Advanced Bias" inputs below
};

// --- EXISTING ENUMS (RESTORED COMMENTS) ---
enum EStrategyPreset {
   PRESET_CUSTOM,             // Use Inputs from the properties window
   PRESET_TREND_REVERSAL,     // "Standard EA" Mode (Always In, Flip on Signal)
   PRESET_TREND_SCALP,        // "Sniper Mode" (Fixed TP/SL, High Confluence)
   PRESET_RANGE_GRID          // "Conservative" (Pullbacks, HTF Filter, High Voting)
};

enum EBiasMode { 
   BIAS_MANUAL,   // User Manually sets Direction
   BIAS_AUTO      // EA determines Direction (EMA Slope/Cross)
};

enum EManualSide { 
   SIDE_BOTH,     // Trade Both Long and Short
   SIDE_LONG,     // Long Only (Filter Short signals)
   SIDE_SHORT     // Short Only (Filter Long signals)
};

enum EAutoStrategy { 
   STRAT_SINGLE_SLOPE, // Slope of BiasFast MA
   STRAT_PAIR_CROSS,   // Cross of BiasFast > BiasSlow
   STRAT_PRICE_CROSS   // Cross of Price > BiasFast MA (Benchmark Mode)
};

enum EEmaRole { 
   ROLE_EMA1, ROLE_EMA2, ROLE_EMA3, ROLE_EMA4 
};

// Indicator Modes
enum EMacdMode { 
   MACD_SIGNAL_ALIGN, // Buy if Main > Signal
   MACD_ZERO_CROSS    // Buy if Main > 0
};
enum ERsiMode { 
   RSI_FILTER_EXTREME, // Pass if NOT Overbought (>70)
   RSI_TREND_ABOVE_50, // Pass if RSI > 50
   RSI_CROSS_LEVEL     // Signal on Level Breakout
};
enum ECciMode { 
   CCI_TREND_ZERO,     // Buy if CCI > 0
   CCI_IMPULSE_100     // Buy if CCI > 100
};
enum EStochMode { 
   STO_CROSS_SIGNAL,   // K line crosses D line
   STO_ZONE_FILTER     // K is not in extreme zones
};
enum EBbMode { 
   BB_TREND_FOLLOW,    // Price > Middle Band
   BB_MEAN_REVERSION   // Price touches Lower Band
};

// Exit & Trailing
enum ETrailingMode { 
   TRAIL_NONE,       // Fixed SL only
   TRAIL_ATR,        // Volatility based (Smooth)
   TRAIL_PSAR,       // Parabolic SAR (Trend Lock)
   TRAIL_FRACTAL     // Market Structure (Swing High/Low)
};

// --- STRUCTURES ---
struct SNewsEvent {
   datetime time;
   string   currency;
   string   impact;
};

struct ST_Settings {
   // Logic
   bool CloseOnReverse;
   // Risk
   double RiskPercent; double MaxSpread; double MinATR;
   // Bias
   bool BiasEnabled; EBiasMode BiasMode; EManualSide ManSide;
   EAutoStrategy AutoStrat; int BiasFastID; int BiasSlowID;
   // Filters
   bool UseTime; int StartHr; int EndHr;
   bool UseNews; int NewsPre; int NewsPost;
   bool UseHTF;  ENUM_TIMEFRAMES HtfPeriod; int P_HtfEma;
   // Voting
   int VoteThreshold;
   // Indicators (Periods)
   int P_Ema1; int P_Ema2; int P_Ema3; int P_Ema4;
   int P_Adx; int T_Adx;
   int P_MacdFast; int P_MacdSlow; int P_MacdSig;
   int P_Rsi; double T_RsiOB; double T_RsiOS;
   int P_Cci; int P_Mfi; double T_Mfi;
   int P_StoK; int P_StoD; int P_StoSlow;
   int P_Bb; double P_BbDev;
   double P_PsarStep; double P_PsarMax;
   EMaMethod MaType;
   // Modes
   EMacdMode MacdMode; ERsiMode RsiMode; ECciMode CciMode; EStochMode StoMode; EBbMode BbMode;
   // Active Votes
   bool Use_EmaSig; bool Use_Adx; bool Use_Macd; bool Use_Rsi; bool Use_Cci;
   bool Use_Mfi; bool Use_Sto; bool Use_Bb; bool Use_Psar; bool Use_P123; bool Use_Ross;
   // Exits
   double SL_Mult; double TP_Mult;
   bool Use_BE; double BE_Trig; double BE_Buff;
   ETrailingMode TrailMode; double Trail_Mult;
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
//| 2. INCLUDES                                                      |
//+------------------------------------------------------------------+
#include <RRMS\SEA_TradeExecutor.mqh>
#include <RRMS\SEA_SignalEngine.mqh>

//+------------------------------------------------------------------+
//| 3. INPUT PARAMETERS                                              |
//+------------------------------------------------------------------+
input group "=== 0. MASTER PRESET ==="
input ulong         Inp_MagicNum       = 12345;         // Unique Magic Number
input EStrategyPreset InpPreset_Clean  = PRESET_CUSTOM; // Select Preset Mode (Forces Reset)

input group "=== 1. CUSTOM: LOGIC & RISK ==="
input bool   Inp_CloseOnReverse        = true;  // Close Opposite Trade on Signal?
input double Inp_RiskPercent           = 2.0;   // Risk per trade (%)
input double Inp_MaxSpreadPips         = 3.0;   // Max Spread (Pips)
input double Inp_MinATRPips            = 5.0;   // Min Volatility (ATR Pips)

input group "=== 2. CUSTOM: MARKET BIAS (EASY SETUP) ==="
input bool          Inp_BiasEnabled    = false;          // Master Bias Switch
input EBiasMode     Inp_BiasMode       = BIAS_AUTO;      // Mode: MANUAL or AUTO
input EEmaStrategy  Inp_EmaStrategy    = EMA_STRAT_1_PRICE_CROSS; // Select Strategy (EASY MODE)

input group "=== 2a. ADVANCED BIAS (Only if Custom) ==="
input EManualSide   Inp_ManualSide     = SIDE_BOTH;          // Manual Side
input EAutoStrategy Inp_AutoStrat_Adv  = STRAT_PRICE_CROSS;  // Auto Strategy (Manual)
input EEmaRole      Inp_BiasFast_Adv   = ROLE_EMA1;          // Fast MA Role
input EEmaRole      Inp_BiasSlow_Adv   = ROLE_EMA2;          // Slow MA Role
// METHOD_EMA | METHOD_SMA
input EMaMethod     Inp_MaType         = METHOD_SMA;         // Select Moving Average Type

input group "=== 3. CUSTOM: FILTERS ==="
input bool   Inp_UseTime               = false;             // Use Time Scheduler?
input int    Inp_StartHour             = 8;                 // Start Trading Hour (0-23)
input int    Inp_EndHour               = 20;                // End Trading Hour (0-23)
input bool   Inp_UseNews               = false;             // Use CSV News Filter?
input string Inp_NewsFile              = "calendar_statement.csv"; // File Name
input int    Inp_NewsPre               = 60;                // Pause Mins BEFORE News
input int    Inp_NewsPost              = 60;                // Pause Mins AFTER News
input bool   Inp_UseHTF                = false;              // Master Filter: HTF Trend
input ENUM_TIMEFRAMES Inp_HtfPeriod    = PERIOD_H4;         // HTF Period
input int    Inp_HtfEmaPeriod          = 89;                // HTF EMA Period

input group "=== 4. CUSTOM: VOTING ==="
input int    Inp_VoteThreshold_Clean   = 2; // MINIMUM Votes required (Renamed)

input group "=== 5. CUSTOM: INDICATORS (Settings) ==="
// EMA Settings
input int    InpEma1Period    = 13;  // EMA 1 (Fast)
input int    InpEma2Period    = 21;  // EMA 2 (Medium)
input int    InpEma3Period    = 34;  // EMA 3 (Slow)
input int    InpEma4Period    = 55;  // EMA 4 (Trend)
// ADX
input int    InpAdxPeriod     = 14;
input int    InpAdxThreshold  = 20;
// MACD
input EMacdMode InpMacdMode   = MACD_SIGNAL_ALIGN;
input int    InpMacdFast      = 12;
input int    InpMacdSlow      = 26;
input int    InpMacdSig       = 9;
// RSI
input ERsiMode InpRsiMode     = RSI_FILTER_EXTREME;
input int    InpRsiPeriod     = 14;
input double InpRsiOverbought = 70.0;
input double InpRsiOversold   = 30.0;
// CCI
input ECciMode InpCciMode     = CCI_TREND_ZERO;
input int    InpCciPeriod     = 14;
// MFI
input int    InpMfiPeriod     = 14;
input double InpMfiLevel      = 50.0;
// Stochastic
input EStochMode InpStoMode   = STO_CROSS_SIGNAL;
input int    InpStoK          = 5;
input int    InpStoD          = 3;
input int    InpStoSlow       = 3;
// Bollinger
input EBbMode InpBbMode       = BB_TREND_FOLLOW;
input int    InpBbPeriod      = 20;
input double InpBbDev         = 2.0;
// PSAR
input double InpPsarStep      = 0.05;
input double InpPsarMax       = 0.5;

input group "=== 6. CUSTOM: ACTIVE VOTES (True/False) ==="
input bool   Inp_Use_EmaSig = true;  // Vote 1: EMA Recovery
input bool   Inp_Use_Adx    = true;  // Vote 2: ADX Strength
input bool   Inp_Use_Macd   = false; // Vote 3: MACD
input bool   Inp_Use_Rsi    = false; // Vote 4: RSI
input bool   Inp_Use_Cci    = false; // Vote 5: CCI
input bool   Inp_Use_Mfi    = false; // Vote 6: MFI
input bool   Inp_Use_Sto    = false; // Vote 7: Stochastic
input bool   Inp_Use_Bb     = false; // Vote 8: Bollinger
input bool   Inp_Use_Psar   = false; // Vote 9: PSAR
input bool   Inp_Use_P123   = false; // Vote 10: Pattern 123
input bool   Inp_Use_Ross   = false; // Vote 11: Ross Hook

input group "=== 7. CUSTOM: EXIT & BREAKEVEN ==="
input double Inp_SL_Mult    = 0.0;  // SL (ATR Multiplier) 2.0
input double Inp_TP_Mult    = 0.0;  // TP (ATR Multiplier) 4.0
input bool   Inp_Use_BE     = true; // Move SL to Entry?
input double Inp_BE_Trig    = 1.0;  // Breakeven Trigger (ATR)
input double Inp_BE_Buff    = 0.1;  // Breakeven Buffer (ATR)
input ETrailingMode Inp_TrailMode = TRAIL_ATR; // Trailing Logic (Disabled for Safety)
input double Inp_Trail_Mult = 3.0;  // ATR Trail Distance
input bool   Inp_ExportCSV  = true; // Export Detailed Report?

//+------------------------------------------------------------------+
//| 4. GLOBAL OBJECTS                                                |
//+------------------------------------------------------------------+
CSignalEngine  Signal;
CTradeExecutor Executor;
ST_Settings    Settings;
datetime       g_last_bar_time = 0;
datetime       g_start_time = 0;

//+------------------------------------------------------------------+
//| 5. INITIALIZATION                                                |
//+------------------------------------------------------------------+
int OnInit() {
   g_start_time = TimeCurrent();

   // A. Apply Settings & Presets
   ApplySettings();
   
   // B. Init Services
   if(!Signal.Init(Settings, _Symbol)) return INIT_FAILED;
   Executor.Init(Inp_MagicNum, Settings);
   
   // C. Load News if needed
   if(Settings.UseNews) Signal.LoadNews(Inp_NewsFile);
   
   // D. Print Configuration
   Print("------------------------------------------");
   Print("--- SimpleEA v1.02.12l (Easy Setup) ---");
   Print("Symbol: ", _Symbol, " | Magic: ", Inp_MagicNum);
   Print("Mode Used: ", EnumToString(InpPreset_Clean));
   Print("EMA Strategy: ", EnumToString(Inp_EmaStrategy));
   Print("Voting Threshold: ", Settings.VoteThreshold, " votes required.");
   
   // --- RESTORED INDICATOR LOGGING ---
   Print("--- Enabled Indicators ---");
   if(Settings.Use_EmaSig) Print("+ Vote: EMA Recovery (Price vs EMA", Settings.P_Ema1, ")");
   if(Settings.Use_Adx)    Print("+ Vote: ADX Strength (Min: ", Settings.T_Adx, ")");
   if(Settings.Use_Macd)   Print("+ Vote: MACD (Mode: ", EnumToString(Settings.MacdMode), ")");
   if(Settings.Use_Rsi)    Print("+ Vote: RSI (Mode: ", EnumToString(Settings.RsiMode), ")");
   if(Settings.Use_Cci)    Print("+ Vote: CCI (Mode: ", EnumToString(Settings.CciMode), ")");
   if(Settings.Use_Mfi)    Print("+ Vote: MFI (Level: ", Settings.T_Mfi, ")");
   if(Settings.Use_Sto)    Print("+ Vote: Stochastic (Mode: ", EnumToString(Settings.StoMode), ")");
   if(Settings.Use_Bb)     Print("+ Vote: Bollinger Bands (Mode: ", EnumToString(Settings.BbMode), ")");
   if(Settings.Use_Psar)   Print("+ Vote: PSAR Trailing/Filter");
   if(Settings.Use_P123)   Print("+ Vote: Pattern 1-2-3");
   if(Settings.Use_Ross)   Print("+ Vote: Ross Hook");
   Print("------------------------------------------");
   
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) {
   Signal.Release();
   if(Settings.ExportCSV) GenerateReport();
   Print("=== SimpleEA Shutdown ===");
}

//+------------------------------------------------------------------+
//| 6. MAIN TICK LOOP                                                |
//+------------------------------------------------------------------+
void OnTick() {
   // 1. New Bar Check
   // We only perform calculations when a new candle closes.
   // This prevents "Tick Spam", server lag, and invalid stop loss modifications.
   datetime t = iTime(_Symbol, PERIOD_CURRENT, 0);
   
   if(t != g_last_bar_time) {
      g_last_bar_time = t;
      
      // Get ATR once for logic consistency
      double atr = Signal.GetATR();

      // A. Management (Trailing / Breakeven)
      // Done FIRST to protect profits before entering new trades
      Executor.ManageTrade(atr);
      
      // B. Signal Logic (Entry)
      int direction = Signal.GetDirection(); 
   
      if(direction != 0) {
         Executor.ProcessSignal(direction, atr);
      }
   }
}

//+------------------------------------------------------------------+
//| 7. CONFIGURATION LOGIC (THE BRAIN)                               |
//+------------------------------------------------------------------+
void ApplySettings() {
   // 1. DEFAULT: LOAD CUSTOM INPUTS
   Settings.CloseOnReverse = Inp_CloseOnReverse;
   Settings.RiskPercent    = Inp_RiskPercent;
   Settings.MaxSpread      = Inp_MaxSpreadPips;
   Settings.MinATR         = Inp_MinATRPips;
   Settings.BiasEnabled    = Inp_BiasEnabled;
   Settings.BiasMode       = Inp_BiasMode;
   Settings.MaType         = Inp_MaType;
   
   // --- LOGIC: AUTOMATIC STRATEGY MAPPING (Easy Mode) ---
   if(Inp_EmaStrategy == EMA_STRAT_1_PRICE_CROSS) {
      // 1 EMA Setup: Price vs EMA 1
      Settings.AutoStrat  = STRAT_PRICE_CROSS;
      Settings.BiasFastID = 0; // Role EMA1
      Settings.BiasSlowID = 0; // Ignored
   }
   else if(Inp_EmaStrategy == EMA_STRAT_2_CROSS_1_2) {
      // 2 EMA Setup: EMA 1 vs EMA 2
      Settings.AutoStrat  = STRAT_PAIR_CROSS;
      Settings.BiasFastID = 0; // Role EMA1
      Settings.BiasSlowID = 1; // Role EMA2
   }
   else if(Inp_EmaStrategy == EMA_STRAT_2_CROSS_3_4) {
      // 2 EMA Setup: EMA 3 vs EMA 4
      Settings.AutoStrat  = STRAT_PAIR_CROSS;
      Settings.BiasFastID = 2; // Role EMA3
      Settings.BiasSlowID = 3; // Role EMA4
   }
   else {
      // Custom: Use Advanced Inputs from Section 2a
      Settings.ManSide     = Inp_ManualSide;
      Settings.AutoStrat   = Inp_AutoStrat_Adv;
      Settings.BiasFastID  = (int)Inp_BiasFast_Adv;
      Settings.BiasSlowID  = (int)Inp_BiasSlow_Adv;
   }
   // -----------------------------------------------------

   Settings.UseTime     = Inp_UseTime;
   Settings.StartHr     = Inp_StartHour;
   Settings.EndHr       = Inp_EndHour;
   Settings.UseNews     = Inp_UseNews;
   Settings.NewsPre     = Inp_NewsPre;
   Settings.NewsPost    = Inp_NewsPost;
   Settings.UseHTF      = Inp_UseHTF;
   Settings.HtfPeriod   = Inp_HtfPeriod;
   Settings.P_HtfEma    = Inp_HtfEmaPeriod;
   
   // Voting
   Settings.VoteThreshold = Inp_VoteThreshold_Clean;
   
   // Indicators
   Settings.P_Ema1 = InpEma1Period; Settings.P_Ema2 = InpEma2Period; 
   Settings.P_Ema3 = InpEma3Period; Settings.P_Ema4 = InpEma4Period;
   Settings.P_Adx = InpAdxPeriod; Settings.T_Adx = InpAdxThreshold;
   Settings.P_MacdFast = InpMacdFast; Settings.P_MacdSlow = InpMacdSlow; Settings.P_MacdSig = InpMacdSig;
   Settings.P_Rsi = InpRsiPeriod;
   Settings.T_RsiOB = InpRsiOverbought; Settings.T_RsiOS = InpRsiOversold;
   Settings.P_Cci = InpCciPeriod;
   Settings.P_Mfi = InpMfiPeriod; Settings.T_Mfi = InpMfiLevel;
   Settings.P_StoK = InpStoK; Settings.P_StoD = InpStoD; Settings.P_StoSlow = InpStoSlow;
   Settings.P_Bb = InpBbPeriod; Settings.P_BbDev = InpBbDev;
   Settings.P_PsarStep = InpPsarStep; Settings.P_PsarMax = InpPsarMax;
   Settings.MacdMode = InpMacdMode; Settings.RsiMode = InpRsiMode;
   Settings.CciMode = InpCciMode; Settings.StoMode = InpStoMode; Settings.BbMode = InpBbMode;
   
   Settings.Use_EmaSig = Inp_Use_EmaSig;
   Settings.Use_Adx = Inp_Use_Adx;
   Settings.Use_Macd = Inp_Use_Macd; Settings.Use_Rsi = Inp_Use_Rsi;
   Settings.Use_Cci = Inp_Use_Cci; Settings.Use_Mfi = Inp_Use_Mfi;
   Settings.Use_Sto = Inp_Use_Sto; Settings.Use_Bb = Inp_Use_Bb;
   Settings.Use_Psar = Inp_Use_Psar; Settings.Use_P123 = Inp_Use_P123; Settings.Use_Ross = Inp_Use_Ross;
   
   Settings.SL_Mult = Inp_SL_Mult; Settings.TP_Mult = Inp_TP_Mult;
   Settings.Use_BE = Inp_Use_BE; Settings.BE_Trig = Inp_BE_Trig; Settings.BE_Buff = Inp_BE_Buff;
   Settings.TrailMode = Inp_TrailMode; Settings.Trail_Mult = Inp_Trail_Mult;
   Settings.ExportCSV = Inp_ExportCSV;
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


   // 2. PRESET: TREND REVERSAL
   if(InpPreset_Clean == PRESET_TREND_REVERSAL) {
      // Force 1 EMA Price Cross logic
      Settings.AutoStrat = STRAT_PRICE_CROSS; 
      Settings.BiasFastID = 0; 
      
      Settings.CloseOnReverse = true;
      Settings.VoteThreshold = 1;
      Settings.MaxSpread   = 5.0;
      Settings.MinATR      = 0.0;
      Settings.UseTime     = false;
      Settings.UseNews     = false;
      Settings.UseHTF      = false;
      Settings.Use_EmaSig  = true;
      Settings.Use_Adx     = false;
      Settings.Use_Macd    = false;
      Settings.Use_Rsi     = false;
      Settings.Use_Cci     = false;
      Settings.Use_Sto     = false;
      Settings.SL_Mult     = 0.0;
      Settings.TP_Mult     = 0.0;
      Settings.Use_BE      = false;         
      Settings.TrailMode   = TRAIL_NONE;
   }
   
   // 3. PRESET: TREND SCALP
   if(InpPreset_Clean == PRESET_TREND_SCALP) {
      Settings.CloseOnReverse = false;
      Settings.VoteThreshold  = 3;
      Settings.SL_Mult     = 1.5;
      Settings.TP_Mult     = 3.0;
      Settings.Use_BE      = true;
      Settings.BE_Trig     = 1.0;
      Settings.TrailMode   = TRAIL_ATR;
      Settings.Use_EmaSig  = true;
      Settings.Use_Macd    = true;
      Settings.Use_Adx     = true;
      Settings.Use_Rsi     = false;
      Settings.Use_Sto     = false;
      Settings.Use_Bb      = false;
   }
   
   // 4. PRESET: RANGE GRID
   if(InpPreset_Clean == PRESET_RANGE_GRID) {
      Settings.CloseOnReverse = false;
      Settings.VoteThreshold  = 4;
      Settings.MinATR         = 5.0;
      Settings.UseTime  = true;
      Settings.UseNews  = true;
      Settings.UseHTF   = true;
      Settings.Use_Rsi  = true;
      Settings.RsiMode  = RSI_FILTER_EXTREME; 
      Settings.Use_Sto  = true;
      Settings.Use_Bb   = true;
      Settings.BbMode   = BB_MEAN_REVERSION;
      Settings.SL_Mult  = 2.0;
      Settings.TP_Mult  = 2.0;
      Settings.TrailMode = TRAIL_NONE;
   }
}

//+------------------------------------------------------------------+
//| 8. REPORT GENERATION                                             |
//+------------------------------------------------------------------+
void GenerateReport() {
   if(!MQLInfoInteger(MQL_TESTER)) return;
   string start_str = TimeToString(g_start_time, TIME_DATE);
   string end_str   = TimeToString(TimeCurrent(), TIME_DATE);
   StringReplace(start_str, ".", "-"); 
   StringReplace(end_str, ".", "-");
   string filename = StringFormat("Report_SimpleEA_%s_%s_%s_%s.csv", _Symbol, EnumToString(_Period), start_str, end_str);
   
   int handle = FileOpen(filename, FILE_CSV|FILE_WRITE|FILE_ANSI, ",");
   if(handle == INVALID_HANDLE) { Print("Report: Failed to write ", filename); return; }
   
   FileWrite(handle, "=== TEST CONFIGURATION ===");
   FileWrite(handle, "Preset Mode", EnumToString(InpPreset_Clean));
   FileWrite(handle, "EMA Strategy", EnumToString(Inp_EmaStrategy));
   FileWrite(handle, "Vote Threshold", Settings.VoteThreshold);
   FileWrite(handle, "");
   
   FileWrite(handle, "=== CORE PERFORMANCE ===");
   FileWrite(handle, "Net Profit", DoubleToString(TesterStatistics(STAT_PROFIT), 2));
   FileWrite(handle, "Gross Profit", DoubleToString(TesterStatistics(STAT_GROSS_PROFIT), 2));
   FileWrite(handle, "Gross Loss", DoubleToString(TesterStatistics(STAT_GROSS_LOSS), 2));
   FileWrite(handle, "Profit Factor", DoubleToString(TesterStatistics(STAT_PROFIT_FACTOR), 2));
   FileWrite(handle, "Expected Payoff", DoubleToString(TesterStatistics(STAT_EXPECTED_PAYOFF), 2));
   FileWrite(handle, "Sharpe Ratio", DoubleToString(TesterStatistics(STAT_SHARPE_RATIO), 2));
   FileWrite(handle, "Recovery Factor", DoubleToString(TesterStatistics(STAT_RECOVERY_FACTOR), 2));
   FileWrite(handle, "");
   
   FileWrite(handle, "=== RISK & DRAWDOWN ===");
   FileWrite(handle, "Balance DD Relative %", DoubleToString(TesterStatistics(STAT_BALANCE_DDREL_PERCENT), 2) + "%");
   FileWrite(handle, "Equity DD Relative %", DoubleToString(TesterStatistics(STAT_EQUITY_DDREL_PERCENT), 2) + "%");
   FileWrite(handle, "Absolute Drawdown", DoubleToString(TesterStatistics(STAT_EQUITY_DD), 2));
   FileWrite(handle, "");

   FileWrite(handle, "=== TRADE STATISTICS ===");
   FileWrite(handle, "Total Trades", DoubleToString(TesterStatistics(STAT_TRADES), 0));
   double winRate = (TesterStatistics(STAT_PROFIT_TRADES) / (TesterStatistics(STAT_TRADES) > 0 ? TesterStatistics(STAT_TRADES) : 1)) * 100.0;
   FileWrite(handle, "Win Rate %", DoubleToString(winRate, 2) + "%");
   FileWrite(handle, "Winning Trades", DoubleToString(TesterStatistics(STAT_PROFIT_TRADES), 0));
   FileWrite(handle, "Losing Trades", DoubleToString(TesterStatistics(STAT_LOSS_TRADES), 0));
   FileWrite(handle, "");

   FileWrite(handle, "=== DEAL HISTORY ===");
   FileWrite(handle, "Time", "Symbol", "Type", "Volume", "Price", "Profit", "Balance");
   
   HistorySelect(0, TimeCurrent());
   int deals = HistoryDealsTotal();
   double balance = TesterStatistics(STAT_INITIAL_DEPOSIT);
   for(int i=0; i<deals; i++) {
      ulong ticket = HistoryDealGetTicket(i);
      long type = HistoryDealGetInteger(ticket, DEAL_TYPE);
      if(type == DEAL_TYPE_BUY || type == DEAL_TYPE_SELL) {
         datetime time = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
         double vol    = HistoryDealGetDouble(ticket, DEAL_VOLUME);
         double price  = HistoryDealGetDouble(ticket, DEAL_PRICE);
         double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT) + HistoryDealGetDouble(ticket, DEAL_SWAP) + HistoryDealGetDouble(ticket, DEAL_COMMISSION);
         balance += profit; 
         string s_type = (type==DEAL_TYPE_BUY) ? "Buy" : "Sell";
         string s_time = TimeToString(time, TIME_DATE|TIME_MINUTES);
         FileWrite(handle, s_time, _Symbol, s_type, DoubleToString(vol, 2), DoubleToString(price, 5), DoubleToString(profit, 2), DoubleToString(balance, 2));
      }
   }
   FileClose(handle);
   Print(">> REPORT SAVED: MQL5/Files/", filename, " <<");
}

/*

What This Change Did

The change introduced a "Master Switch" for the Moving Average calculation method.

* Before: The EA was hardcoded to use Exponential Moving Average (EMA).
    * Problem: You could not scientifically compare it to the standard MT5 "Moving Average" EA, because that EA uses Simple Moving Average (SMA). SMAs are slower and smoother; EMAs are faster and more reactive. Comparing them was apples-to-oranges.
* Now: You have a dropdown menu (Inp_MaType) to choose between EMA and SMA.
    * Result: The EA dynamically re-programs all 4 internal Moving Averages (and the HTF filter) to use the math you selected.

2. How to Use It (Configuration Guide)
Here is how you combine the Strategy Selector (1, 2, 3, 4 EMAs) with the Method Selector (SMA vs EMA) to create any setup you need.

Scenario A: The "Scientific Benchmark" (Match MT5 Standard EA)
Goal: Prove that your EA logic works exactly like the free EA.
1. Preset: PRESET_CUSTOM
2. Strategy: EMA_STRAT_1_PRICE_CROSS
3. MA Method: METHOD_SMA (<-- Crucial)
4. Vote Threshold: 1
5. EMA 1 Period: 50 (or whatever the Standard EA is using).

Scenario B: The "High Performance" Mode (Your Original Logic)
Goal: Trade the same strategy, but with faster entries.
1. Preset: PRESET_CUSTOM
2. Strategy: EMA_STRAT_1_PRICE_CROSS
3. MA Method: METHOD_EMA (<-- Standard)
4. Vote Threshold: 1

Scenario C: The "Classic Golden Cross"
Goal: Trade 50 SMA crossing 200 SMA.
1. Preset: PRESET_CUSTOM
2. Strategy: EMA_STRAT_2_CROSS_1_2
3. MA Method: METHOD_SMA
4. EMA 1 Period: 50
5. EMA 2 Period: 200

---

The main change in Version 012l (and k) is the introduction of the "Easy Setup" Dropdown (Inp_EmaStrategy).
* Before: You had to act like a programmer. To set up a 1-EMA strategy, you had to manually set "Auto Strategy" to Price Cross and "Bias Fast ID" to Role EMA1. One wrong click meant the EA did nothing.
* Now: The EA acts like a smart assistant. You simply select "1 EMA Price Cross" from the list, and the code automatically configures the internal wiring to use the correct Strategy and the correct EMA variable.
It also acts as a Gatekeeper: It separates "Easy Mode" from "Advanced Mode," so you don't accidentally mix settings.

How to Configure 1, 2, 3, or 4 EMA Strategies
Here is the step-by-step guide for the most common setups using the new system.
Critical First Steps (For ALL Setups)
1. Preset: Set InpPreset_Clean to PRESET_CUSTOM.
    * Why? If you select any other preset (like "Trend Reversal"), it forces its own hardcoded settings and ignores your changes.
2. Threshold: Set Inp_VoteThreshold_Clean to 1.
    * Why? If this is higher (e.g., 4), the EA will see the MA Cross signal but Wait for 3 other indicators (like RSI or MACD) to agree before trading. For pure MA testing, it must be 1.

Scenario A: The "Benchmark" (1 EMA)
Mimics the standard MT5 Moving Average EA.
* Logic: Buy when Price > EMA. Sell when Price < EMA.
Input Parameter	Value
Inp_EmaStrategy	EMA_STRAT_1_PRICE_CROSS
InpEma1Period	Set your desired period (e.g., 50, 100, or 200)
(Other EMAs)	Ignored by the strategy.

Scenario B: The "Classic Cross" (2 EMAs)
The standard Golden Cross / Death Cross.
* Logic: Buy when Fast EMA > Slow EMA.
Input Parameter	Value
Inp_EmaStrategy	EMA_STRAT_2_CROSS_1_2
InpEma1Period	Set the FAST period (e.g., 13)
InpEma2Period	Set the SLOW period (e.g., 34)

Scenario C: The "Slow Trend" (Using EMAs 3 & 4)
If you want to keep your Fast settings (13/34) saved in inputs 1 & 2, but want to quickly test a slower strategy without re-typing everything.
* Logic: Buy when EMA 3 > EMA 4.
Input Parameter	Value
Inp_EmaStrategy	EMA_STRAT_2_CROSS_3_4
InpEma3Period	Set the FAST period (e.g., 89)
InpEma4Period	Set the SLOW period (e.g., 200)

Scenario D: The "Advanced / Custom" (Any Combination)
Use this if you want something weird, like crossing EMA 1 vs EMA 4.
Input Parameter	Value
Inp_EmaStrategy	EMA_STRAT_CUSTOM
Inp_AutoStrat_Adv	Select STRAT_PAIR_CROSS (or PRICE_CROSS)
Inp_BiasFast_Adv	Select ROLE_EMA1 (The Fast one)
Inp_BiasSlow_Adv	Select ROLE_EMA4 (The Slow one)

Summary of "Connected Settings"
When testing these EMA strategies, ensure these Filtering/Exit settings are also correct, otherwise, they might interfere with your results:
1. Filters (Group 3):
    * HTF Filter (Inp_UseHTF): Recommended FALSE for pure MA testing. If True, the EA will ignore a "Buy Cross" if the H4 trend is Down.
    * Time Filter (Inp_UseTime): FALSE (unless you specifically want to avoid night trading).
2. Exits (Group 7):
    * Close On Reverse (Inp_CloseOnReverse):
        * TRUE: Acts like a "Stop and Reverse" system (Always in the market).
        * FALSE: The trade hits TP or SL. A new signal in the opposite direction is ignored if a trade is open.
    * Trailing Stop (Inp_TrailMode): Defaults to TRAIL_NONE. Enable if you want to test trailing performance.


*/