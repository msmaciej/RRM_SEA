//+------------------------------------------------------------------+
//|                                          SimpleEA_v1-02-012j.mq5 |
//|                              MJS Institutional Trading Solutions |
//|             GOLDEN MASTER: Broken Memory & New Bar Execution     |
//+------------------------------------------------------------------+
// SAVE AS UTF-16 LE WITH BOM
#property copyright "SimpleEA Redesign v1.02.12j"
#property version   "102.012"
#property strict

// --- 1. DEFINITIONS & ENUMS ---

// 1. BIAS & STRATEGY
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

// 2. INDICATOR MODES
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

// 3. EXIT & TRAILING LOGIC
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
   EAutoStrategy AutoStrat;
   int BiasFastID; int BiasSlowID;
   // Filters
   bool UseTime; int StartHr; int EndHr;
   bool UseNews; int NewsPre; int NewsPost;
   bool UseHTF;  ENUM_TIMEFRAMES HtfPeriod; int P_HtfEma;
   // Voting
   int VoteThreshold;
   // Indicators (Periods & Params)
   int P_Ema1; int P_Ema2; int P_Ema3; int P_Ema4;
   int P_Adx; int T_Adx;
   int P_MacdFast; int P_MacdSlow; int P_MacdSig;
   int P_Rsi; double T_RsiOB; double T_RsiOS;
   int P_Cci; int P_Mfi; double T_Mfi;
   int P_StoK; int P_StoD; int P_StoSlow;
   int P_Bb; double P_BbDev;
   double P_PsarStep; double P_PsarMax;
   // Indicators (Modes)
   EMacdMode MacdMode; ERsiMode RsiMode; ECciMode CciMode; EStochMode StoMode; EBbMode BbMode;
   // Indicators (Active)
   bool Use_EmaSig; bool Use_Adx; bool Use_Macd; bool Use_Rsi; bool Use_Cci;
   bool Use_Mfi; bool Use_Sto; bool Use_Bb; bool Use_Psar; bool Use_P123; bool Use_Ross;
   // Exit
   double SL_Mult; double TP_Mult;
   bool Use_BE; double BE_Trig; double BE_Buff;
   ETrailingMode TrailMode; double Trail_Mult;
   // Reporting
   bool ExportCSV;
};

// --- 2. INCLUDES (SERVICES) ---
#include <RRMS\SEA_TradeExecutor.mqh>
#include <RRMS\SEA_SignalEngine.mqh>

// --- 3. INPUT PARAMETERS (RENAMED TO FORCE RESET) ---
input group "=== 0. MASTER PRESET ==="
input ulong         Inp_MagicNum       = 12345;         // Unique Magic Number
input EStrategyPreset InpPreset_Clean  = PRESET_CUSTOM; // Select Preset Mode (RENAMED)

input group "=== 1. CUSTOM: LOGIC & RISK ==="
input bool   Inp_CloseOnReverse     = true; // Close Opposite Trade on Signal? (Reversal Logic)
input double Inp_RiskPercent        = 2.0;  // Risk per trade (%)
input double Inp_MaxSpreadPips      = 3.0;  // Max Spread (Pips)
input double Inp_MinATRPips         = 5.0;  // Min Volatility (ATR Pips)

input group "=== 2. CUSTOM: MARKET BIAS ==="
input bool          Inp_BiasEnabled = true;               // Master Bias Switch
input EBiasMode     Inp_BiasMode    = BIAS_AUTO;          // Mode: MANUAL or AUTO
input EManualSide   Inp_ManualSide  = SIDE_BOTH;          // Manual Side
input EAutoStrategy Inp_AutoStrat   = STRAT_PRICE_CROSS;  // Auto Strategy
input EEmaRole      Inp_BiasFast    = ROLE_EMA3;          // Auto Fast MA
input EEmaRole      Inp_BiasSlow    = ROLE_EMA4;          // Auto Slow MA

input group "=== 3. CUSTOM: FILTERS ==="
input bool   Inp_UseTime            = false;             // Use Time Scheduler?
input int    Inp_StartHour          = 8;                 // Start Trading Hour (0-23)
input int    Inp_EndHour            = 20;                // End Trading Hour (0-23)
input bool   Inp_UseNews            = false;             // Use CSV News Filter?
input string Inp_NewsFile           = "calendar_statement.csv"; // File Name
input int    Inp_NewsPre            = 60;                // Pause Mins BEFORE News
input int    Inp_NewsPost           = 60;                // Pause Mins AFTER News
input bool   Inp_UseHTF             = true;              // Master Filter: HTF Trend
input ENUM_TIMEFRAMES Inp_HtfPeriod = PERIOD_H4;         // HTF Period
input int    Inp_HtfEmaPeriod       = 89;                // HTF EMA Period

input group "=== 4. CUSTOM: VOTING ==="
input int    Inp_VoteThreshold_Clean = 1; // MINIMUM Votes required (RENAMED)

input group "=== 5. CUSTOM: INDICATORS (Settings) ==="
// EMA
input int    InpEma1Period    = 13;
input int    InpEma2Period    = 21;
input int    InpEma3Period    = 34;
input int    InpEma4Period    = 55;
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
input double Inp_SL_Mult    = 2.0;  // SL (ATR Multiplier)
input double Inp_TP_Mult    = 4.0;  // TP (ATR Multiplier)
input bool   Inp_Use_BE     = true; // Move SL to Entry?
input double Inp_BE_Trig    = 1.0;  // Breakeven Trigger (ATR)
input double Inp_BE_Buff    = 0.1;  // Breakeven Buffer (ATR)
input ETrailingMode Inp_TrailMode = TRAIL_NONE; // Trailing Logic (Disabled for Safety)
input double Inp_Trail_Mult = 1.5;  // ATR Trail Distance
input bool   Inp_ExportCSV  = true; // Export Detailed Report?

// --- 4. GLOBAL OBJECTS ---
CSignalEngine  Signal;
CTradeExecutor Executor;
ST_Settings    Settings;
datetime       g_last_bar_time = 0;
datetime       g_start_time = 0;

// --- 5. INITIALIZATION ---
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
   Print("--- SimpleEA v1.02.12j (Clean Install) ---");
   Print("Symbol: ", _Symbol, " | Magic: ", Inp_MagicNum);
   Print("Mode Used: ", EnumToString(InpPreset_Clean));
   Print("Voting Threshold: ", Settings.VoteThreshold, " votes required.");
   
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

// --- 6. MAIN TICK LOOP ---
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
      int direction = Signal.GetDirection(); // Returns 1, -1, 0
   
      if(direction != 0) {
         Executor.ProcessSignal(direction, atr);
      }
   }
   
   // Note: The 'else' block is intentionally empty.
   // The EA does NOTHING between bars. This is the "New Bar" model.
}

// --- 7. CONFIGURATION LOGIC ---
void ApplySettings() {
   // 1. DEFAULT: LOAD CUSTOM INPUTS
   Settings.CloseOnReverse = Inp_CloseOnReverse;
   Settings.RiskPercent = Inp_RiskPercent;
   Settings.MaxSpread   = Inp_MaxSpreadPips;
   Settings.MinATR      = Inp_MinATRPips;
   Settings.BiasEnabled = Inp_BiasEnabled;
   Settings.BiasMode    = Inp_BiasMode;
   Settings.ManSide     = Inp_ManualSide;
   Settings.AutoStrat   = Inp_AutoStrat;
   Settings.BiasFastID  = (int)Inp_BiasFast;
   Settings.BiasSlowID  = (int)Inp_BiasSlow;
   Settings.UseTime     = Inp_UseTime;
   Settings.StartHr     = Inp_StartHour;
   Settings.EndHr       = Inp_EndHour;
   Settings.UseNews     = Inp_UseNews;
   Settings.NewsPre     = Inp_NewsPre;
   Settings.NewsPost    = Inp_NewsPost;
   Settings.UseHTF      = Inp_UseHTF;
   Settings.HtfPeriod   = Inp_HtfPeriod;
   Settings.P_HtfEma    = Inp_HtfEmaPeriod;
   
   // --- MAPPING RENAMED INPUT TO SETTINGS ---
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

   // 2. PRESET: TREND REVERSAL (The Benchmark Beater)
   if(InpPreset_Clean == PRESET_TREND_REVERSAL) {
      Settings.CloseOnReverse = true;
      Settings.AutoStrat = STRAT_PRICE_CROSS; // <--- PRICE CROSS LOGIC ENABLED
      Settings.VoteThreshold = 1;             // <--- IMMEDIATE SIGNAL
      
      Settings.MaxSpread   = 5.0;
      Settings.MinATR      = 0.0;
      Settings.UseTime     = false;
      Settings.UseNews     = false;
      Settings.UseHTF      = false;
      Settings.BiasFastID  = 0; // ROLE_EMA1
      
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
   
   // 3. PRESET: TREND SCALP (The Sniper)
   if(InpPreset_Clean == PRESET_TREND_SCALP) {
      Settings.CloseOnReverse = false; // Fixed Targets Only
      Settings.VoteThreshold  = 3;     // High Confluence Required
      
      // Strict Risk
      Settings.SL_Mult     = 1.5; // Tight Stop
      Settings.TP_Mult     = 3.0; // 1:2 Risk:Reward
      Settings.Use_BE      = true; // Protect Profits
      Settings.BE_Trig     = 1.0;
      Settings.TrailMode   = TRAIL_ATR;
      // Momentum Indicators Only
      Settings.Use_EmaSig  = true;
      Settings.Use_Macd    = true; // Confirmation
      Settings.Use_Adx     = true; // Strength Check
      // Disable Reversion/Oscillators
      Settings.Use_Rsi     = false;
      Settings.Use_Sto     = false;
      Settings.Use_Bb      = false;
   }
   
   // 4. PRESET: RANGE GRID (The Conservative)
   if(InpPreset_Clean == PRESET_RANGE_GRID) {
      Settings.CloseOnReverse = false;
      Settings.VoteThreshold  = 4;      // Very High Consensus
      Settings.MinATR         = 5.0;    // Avoid dead markets
      
      // Filters Enabled
      Settings.UseTime  = true; // Avoid unpredictable hours
      Settings.UseNews  = true; // Avoid spikes
      Settings.UseHTF   = true; // Only trade if H4 agrees
      
      // Mean Reversion Indicators
      Settings.Use_Rsi  = true;
      Settings.RsiMode  = RSI_FILTER_EXTREME;   // Enter only if NOT extended
      Settings.Use_Sto  = true; // Stochastic Cross
      Settings.Use_Bb   = true; // Bollinger Band Logic
      Settings.BbMode   = BB_MEAN_REVERSION; // Buy at Lower Band
      
      // Targets
      Settings.SL_Mult  = 2.0;
      Settings.TP_Mult  = 2.0;
      Settings.TrailMode = TRAIL_NONE;
   }
}

// --- 8. REPORT GENERATION ---
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
   FileWrite(handle, "Magic Number", Inp_MagicNum);
   FileWrite(handle, "Risk Percent", Settings.RiskPercent);
   FileWrite(handle, "Vote Threshold", Settings.VoteThreshold);
   FileWrite(handle, "");
   
   // --- ENHANCED METRICS SECTION ---
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
   FileWrite(handle, "Short Trades (Won)", DoubleToString(TesterStatistics(STAT_SHORT_TRADES),0) + " (" + DoubleToString(TesterStatistics(STAT_PROFIT_SHORTTRADES),0) + ")");
   FileWrite(handle, "Long Trades (Won)", DoubleToString(TesterStatistics(STAT_LONG_TRADES),0) + " (" + DoubleToString(TesterStatistics(STAT_PROFIT_LONGTRADES),0) + ")");
   FileWrite(handle, "");
   
   FileWrite(handle, "=== STREAKS & AVERAGES ===");
   FileWrite(handle, "Max Consec Wins", DoubleToString(TesterStatistics(STAT_CONPROFITMAX_TRADES), 0));
   FileWrite(handle, "Max Consec Losses", DoubleToString(TesterStatistics(STAT_CONLOSSMAX_TRADES), 0));
   FileWrite(handle, "Max Consec Profit ($)", DoubleToString(TesterStatistics(STAT_CONPROFITMAX), 2));
   FileWrite(handle, "Max Consec Loss ($)", DoubleToString(TesterStatistics(STAT_CONLOSSMAX), 2));
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

Changes Implemented in this Version (v1.02.012j)
1. Nuclear Fix (Renamed Inputs): Renamed InpPreset to InpPreset_Clean and Inp_VoteThreshold to Inp_VoteThreshold_Clean. This forces MT5 to create a new settings entry, effectively erasing the "ghost" memory of the old Vote Threshold 4.
2. New Bar Execution Only: The OnTick function now strictly runs only once per bar.
    * Benefit: This solves your issue of "SL changing on every tick" and prevents journal spam.
    * Stability: It ensures the EA acts exactly like institutional systems (on Close), ignoring intraday wick noise.
3. Default Safety: Inp_TrailMode now defaults to TRAIL_NONE to ensure the benchmark tests run cleanly without interference.
You can save this file directly as SimpleEA_v1-02-012j.mq5 in your MQL5/Experts folder.

*/