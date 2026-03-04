//+------------------------------------------------------------------+
//|                                          SimpleEA_v1-02-012d.mq5 |
//|                                  Institutional Trading Solutions |
//|             GOLDEN MASTER: Reversal Logic | Presets | Formatted  |
//+------------------------------------------------------------------+
#property copyright "SimpleEA Redesign v1.02.12d"
#property version   "102.012" //01.02.012d
#property strict

#include <Trade\Trade.mqh>

//--- ENUMS FOR CONFIGURATION ---

// 1. BIAS & STRATEGY
enum EStrategyPreset {
   PRESET_CUSTOM,             // Use Inputs from the properties window
   PRESET_TREND_REVERSAL,     // "Standard EA" Mode (Always In, Flip on Signal)
   PRESET_TREND_SCALP,        // "Sniper Mode" (Fixed TP/SL, One shot)
   PRESET_RANGE_GRID          // "Conservative" (High Voting, Filters)
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
   STRAT_PAIR_CROSS    // Cross of BiasFast > BiasSlow
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

//--- NEWS EVENT STRUCTURE ---
struct SNewsEvent {
   datetime time;
   string   currency;
   string   impact;
};

//--- SETTINGS STRUCTURE (Decoupled Logic) ---
struct ST_Settings {
   // Logic
   bool CloseOnReverse;
   // Risk
   double RiskPercent; double MaxSpread; double MinATR;
   // Bias
   bool BiasEnabled; EBiasMode BiasMode; EManualSide ManSide; EAutoStrategy AutoStrat;
   int BiasFastID; int BiasSlowID;
   // Filters
   bool UseTime; int StartHr; int EndHr;
   bool UseNews; int NewsPre; int NewsPost;
   bool UseHTF;  ENUM_TIMEFRAMES HtfPeriod;
   // Voting
   int VoteThreshold;
   // Indicators (Periods & Params)
   int P_Ema1; int P_Ema2; int P_Ema3; int P_Ema4;
   int P_Adx; int T_Adx; // Period, Threshold
   int P_MacdFast; int P_MacdSlow; int P_MacdSig;
   int P_Rsi; double T_RsiOB; double T_RsiOS;
   int P_Cci; 
   int P_Mfi; double T_Mfi;
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

//--- GLOBAL OBJECTS ---
CTrade      trade;
ST_Settings Settings;         // The Active Settings Instance
SNewsEvent  g_news_events[];  // News Cache

// Indicator Handles
int    g_h_ema1, g_h_ema2, g_h_ema3, g_h_ema4;
int    g_h_macd, g_h_rsi, g_h_cci, g_h_sto, g_h_atr, g_h_bb, g_h_psar, g_h_fractals, g_h_adx, g_h_mfi;
int    g_h_htf_ema;

// State Variables
datetime g_last_bar_time = 0;
datetime g_start_time = 0;     // For Report Filename
datetime g_last_trade_bar = 0; // Re-Entry Lock

//--- FUNCTION PROTOTYPES ---
bool CheckSignal_EMA1(int bias);
bool CheckSignal_ADX();
bool CheckSignal_MACD(int bias);
bool CheckSignal_RSI(int bias);
bool CheckSignal_CCI(int bias);
bool CheckSignal_MFI(int bias);
bool CheckSignal_Sto(int bias);
bool CheckSignal_BB(int bias);
bool CheckSignal_PSAR(int bias);
bool CheckSignal_Pattern123(int bias);
bool CheckSignal_RossHook(int bias);
bool CheckHTF(int bias);
bool CheckTimeFilter();
bool CheckNewsFilter();
void LoadNewsCSV();
void GenerateReport(); 
int  GetSlope(int handle);
double GetIndValue(int handle, int shift);
bool GetIndBuffer(int handle, int buf_idx, int shift, double &arr[]);
double GetFractal(int shift, int mode);
void ManageExit();
void ManageBreakeven(double atr);
void ExecuteTrade(ENUM_ORDER_TYPE type);
bool IsNewBar();
bool CheckBasicFilters();
int  GetBias();
int  GetHandleByRole(EEmaRole role);
void ApplySettings();

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                 |
//+------------------------------------------------------------------+
input group "=== 0. MASTER PRESET ==="
input EStrategyPreset InpPreset = PRESET_CUSTOM; // Select 'TREND_REVERSAL' to mimic Standard EA

input group "=== 1. CUSTOM: LOGIC & RISK ==="
input bool   Inp_CloseOnReverse   = true;     // Close Opposite Trade on Signal? (Reversal Logic)
input double Inp_RiskPercent      = 2.0;      // Risk per trade (%)
input double Inp_MaxSpreadPips    = 3.0;      // Max Spread (Pips)
input double Inp_MinATRPips       = 5.0;      // Min Volatility (ATR Pips)

input group "=== 2. CUSTOM: MARKET BIAS ==="
input bool          Inp_BiasEnabled   = true;        // Master Bias Switch
input EBiasMode     Inp_BiasMode      = BIAS_AUTO;   // Mode: MANUAL or AUTO
input EManualSide   Inp_ManualSide    = SIDE_BOTH;   // Manual Side
input EAutoStrategy Inp_AutoStrat     = STRAT_PAIR_CROSS; // Auto Strategy
input EEmaRole      Inp_BiasFast      = ROLE_EMA3;   // Auto Fast MA
input EEmaRole      Inp_BiasSlow      = ROLE_EMA4;   // Auto Slow MA

input group "=== 3. CUSTOM: FILTERS ==="
input bool   Inp_UseTime         = true;     // Use Time Scheduler?
input int    Inp_StartHour       = 8;        // Start Trading Hour (0-23)
input int    Inp_EndHour         = 20;       // End Trading Hour (0-23)
input bool   Inp_UseNews         = true;     // Use CSV News Filter?
input string Inp_NewsFile        = "calendar_statement.csv"; // File Name
input int    Inp_NewsPre         = 60;       // Pause Mins BEFORE News
input int    Inp_NewsPost        = 60;       // Pause Mins AFTER News
input bool   Inp_UseHTF          = false;    // Master Filter: HTF Trend
input ENUM_TIMEFRAMES Inp_HtfPeriod = PERIOD_H4; // HTF Period

input group "=== 4. CUSTOM: VOTING ==="
input int    Inp_VoteThreshold   = 4;        // MINIMUM Votes required

input group "=== 5. CUSTOM: INDICATORS (Settings) ==="
// EMA
input int    InpEma1Period = 13;
input int    InpEma2Period = 21;
input int    InpEma3Period = 34;
input int    InpEma4Period = 55;

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
input double InpPsarStep      = 0.02;
input double InpPsarMax       = 0.2;

input group "=== 6. CUSTOM: ACTIVE VOTES (True/False) ==="
input bool   Inp_Use_EmaSig = true;     // Vote 1: EMA Recovery
input bool   Inp_Use_Adx    = true;     // Vote 2: ADX Strength
input bool   Inp_Use_Macd   = true;     // Vote 3: MACD
input bool   Inp_Use_Rsi    = true;     // Vote 4: RSI
input bool   Inp_Use_Cci    = true;     // Vote 5: CCI
input bool   Inp_Use_Mfi    = true;     // Vote 6: MFI
input bool   Inp_Use_Sto    = false;    // Vote 7: Stochastic
input bool   Inp_Use_Bb     = false;    // Vote 8: Bollinger
input bool   Inp_Use_Psar   = false;    // Vote 9: PSAR
input bool   Inp_Use_P123   = false;    // Vote 10: Pattern 123
input bool   Inp_Use_Ross   = false;    // Vote 11: Ross Hook

input group "=== 7. CUSTOM: EXIT & BREAKEVEN ==="
input double Inp_SL_Mult    = 2.0;      // SL (ATR Multiplier)
input double Inp_TP_Mult    = 4.0;      // TP (ATR Multiplier)
input bool   Inp_Use_BE     = true;     // Move SL to Entry?
input double Inp_BE_Trig    = 1.0;      // Breakeven Trigger (ATR)
input double Inp_BE_Buff    = 0.1;      // Breakeven Buffer (ATR)
input ETrailingMode Inp_TrailMode = TRAIL_ATR; // Trailing Logic
input double Inp_Trail_Mult = 1.5;      // ATR Trail Distance
input bool   Inp_ExportCSV  = true;     // Export Detailed Report?

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("=== SimpleEA v1.02.012d Init ===");
   g_start_time = TimeCurrent();
   
   // 1. APPLY SETTINGS (Preset vs Custom)
   ApplySettings();
   
   // 2. INITIALIZE INDICATORS (Using 'Settings' not 'Inputs')
   g_h_ema1 = iMA(_Symbol, PERIOD_CURRENT, Settings.P_Ema1, 0, MODE_EMA, PRICE_CLOSE);
   g_h_ema2 = iMA(_Symbol, PERIOD_CURRENT, Settings.P_Ema2, 0, MODE_EMA, PRICE_CLOSE);
   g_h_ema3 = iMA(_Symbol, PERIOD_CURRENT, Settings.P_Ema3, 0, MODE_EMA, PRICE_CLOSE);
   g_h_ema4 = iMA(_Symbol, PERIOD_CURRENT, Settings.P_Ema4, 0, MODE_EMA, PRICE_CLOSE);
   g_h_atr  = iATR(_Symbol, PERIOD_CURRENT, 14); 
   g_h_macd = iMACD(_Symbol, PERIOD_CURRENT, Settings.P_MacdFast, Settings.P_MacdSlow, Settings.P_MacdSig, PRICE_CLOSE);
   g_h_rsi  = iRSI(_Symbol, PERIOD_CURRENT, Settings.P_Rsi, PRICE_CLOSE);
   g_h_cci  = iCCI(_Symbol, PERIOD_CURRENT, Settings.P_Cci, PRICE_CLOSE);
   g_h_adx  = iADX(_Symbol, PERIOD_CURRENT, Settings.P_Adx);
   g_h_mfi  = iMFI(_Symbol, PERIOD_CURRENT, Settings.P_Mfi, VOLUME_TICK); 
   g_h_sto  = iStochastic(_Symbol, PERIOD_CURRENT, Settings.P_StoK, Settings.P_StoD, Settings.P_StoSlow, MODE_SMA, STO_LOWHIGH);
   g_h_bb   = iBands(_Symbol, PERIOD_CURRENT, Settings.P_Bb, 0, Settings.P_BbDev, PRICE_CLOSE);
   g_h_psar = iSAR(_Symbol, PERIOD_CURRENT, Settings.P_PsarStep, Settings.P_PsarMax); 
   g_h_fractals = iFractals(_Symbol, PERIOD_CURRENT);
   
   // HTF Indicator
   if(Settings.UseHTF) {
      g_h_htf_ema = iMA(_Symbol, Settings.HtfPeriod, 55, 0, MODE_EMA, PRICE_CLOSE);
      if(g_h_htf_ema == INVALID_HANDLE) Print("Warning: Failed to create HTF Handle");
   }

   if(g_h_ema1 == INVALID_HANDLE || g_h_atr == INVALID_HANDLE) {
      Print("CRITICAL: Failed to create essential indicator handles.");
      return INIT_FAILED;
   }
   
   // 3. LOAD NEWS
   if(Settings.UseNews) LoadNewsCSV();
   
   // 4. PRINT ACTIVE CONFIGURATION (Audit Trail - Restored)
   Print("------------------------------------------");
   Print("--- Active Strategy Configuration ---");
   Print("Symbol: ", _Symbol);
   Print("Mode Used: ", EnumToString(InpPreset));
   Print("Bias Mode: ", EnumToString(Settings.BiasMode));
   Print("HTF Filter: ", Settings.UseHTF ? "ON ("+EnumToString(Settings.HtfPeriod)+")" : "OFF");
   Print("Voting Threshold: ", Settings.VoteThreshold, " votes required.");
   Print("Reversal Logic: ", Settings.CloseOnReverse ? "ON (Standard EA Mode)" : "OFF (Fixed SL/TP)");
   
   Print("--- Filters ---");
   Print("Time Filter: ", Settings.UseTime ? "ON ("+(string)Settings.StartHr+":00 - "+(string)Settings.EndHr+":00)" : "OFF");
   Print("News Filter: ", Settings.UseNews ? "ON ("+(string)ArraySize(g_news_events)+" events loaded)" : "OFF");
   Print("Breakeven: ", Settings.Use_BE ? "ON" : "OFF");
   Print("Reporting: ", Settings.ExportCSV ? "ON" : "OFF");
   
   Print("--- Enabled Indicators ---");
   if(Settings.Use_EmaSig) Print("+ Vote: EMA Recovery");
   if(Settings.Use_Adx)    Print("+ Vote: ADX Strength (Per: ", Settings.P_Adx, ")");
   if(Settings.Use_Macd)   Print("+ Vote: MACD (", EnumToString(Settings.MacdMode), ")");
   if(Settings.Use_Rsi)    Print("+ Vote: RSI (", EnumToString(Settings.RsiMode), ")");
   if(Settings.Use_Cci)    Print("+ Vote: CCI");
   if(Settings.Use_Mfi)    Print("+ Vote: MFI (Volume)");
   if(Settings.Use_Sto)    Print("+ Vote: Stochastic");
   if(Settings.Use_Bb)     Print("+ Vote: Bollinger");
   if(Settings.Use_Psar)   Print("+ Vote: PSAR");
   if(Settings.Use_P123)   Print("+ Vote: Mark Crisp 1-2-3");
   if(Settings.Use_Ross)   Print("+ Vote: Ross Hook");
   Print("------------------------------------------");
   
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) {
   IndicatorRelease(g_h_ema1); IndicatorRelease(g_h_ema2);
   IndicatorRelease(g_h_ema3); IndicatorRelease(g_h_ema4);
   IndicatorRelease(g_h_atr); IndicatorRelease(g_h_macd);
   IndicatorRelease(g_h_rsi); IndicatorRelease(g_h_cci);
   IndicatorRelease(g_h_adx); IndicatorRelease(g_h_mfi);
   IndicatorRelease(g_h_sto); IndicatorRelease(g_h_bb);
   IndicatorRelease(g_h_psar); IndicatorRelease(g_h_fractals);
   if(Settings.UseHTF) IndicatorRelease(g_h_htf_ema);
   
   // --- GENERATE REPORT IF ENABLED ---
   if(Settings.ExportCSV) GenerateReport();
   
   Print("=== SimpleEA Shutdown ===");
}

//+------------------------------------------------------------------+
//| CONFIGURATION LOGIC                                              |
//+------------------------------------------------------------------+
void ApplySettings() {
   // A. DEFAULT: LOAD CUSTOM INPUTS
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
   
   Settings.VoteThreshold = Inp_VoteThreshold;
   
   // Indicators - Periods
   Settings.P_Ema1 = InpEma1Period; Settings.P_Ema2 = InpEma2Period; 
   Settings.P_Ema3 = InpEma3Period; Settings.P_Ema4 = InpEma4Period;
   Settings.P_Adx = InpAdxPeriod; Settings.T_Adx = InpAdxThreshold;
   Settings.P_MacdFast = InpMacdFast; Settings.P_MacdSlow = InpMacdSlow; Settings.P_MacdSig = InpMacdSig;
   Settings.P_Rsi = InpRsiPeriod; Settings.T_RsiOB = InpRsiOverbought; Settings.T_RsiOS = InpRsiOversold;
   Settings.P_Cci = InpCciPeriod;
   Settings.P_Mfi = InpMfiPeriod; Settings.T_Mfi = InpMfiLevel;
   Settings.P_StoK = InpStoK; Settings.P_StoD = InpStoD; Settings.P_StoSlow = InpStoSlow;
   Settings.P_Bb = InpBbPeriod; Settings.P_BbDev = InpBbDev;
   Settings.P_PsarStep = InpPsarStep; Settings.P_PsarMax = InpPsarMax;
   
   // Indicators - Modes
   Settings.MacdMode = InpMacdMode;
   Settings.RsiMode  = InpRsiMode;
   Settings.CciMode  = InpCciMode;
   Settings.StoMode  = InpStoMode;
   Settings.BbMode   = InpBbMode;
   
   // Indicators - Active
   Settings.Use_EmaSig = Inp_Use_EmaSig; Settings.Use_Adx = Inp_Use_Adx;
   Settings.Use_Macd = Inp_Use_Macd; Settings.Use_Rsi = Inp_Use_Rsi;
   Settings.Use_Cci = Inp_Use_Cci; Settings.Use_Mfi = Inp_Use_Mfi;
   Settings.Use_Sto = Inp_Use_Sto; Settings.Use_Bb = Inp_Use_Bb;
   Settings.Use_Psar = Inp_Use_Psar; Settings.Use_P123 = Inp_Use_P123;
   Settings.Use_Ross = Inp_Use_Ross;
   
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


   // B. PRESET: TREND REVERSAL (Standard EA Clone)
   if(InpPreset == PRESET_TREND_REVERSAL) {
      Settings.CloseOnReverse = true;  // KEY: Enable Reversal Logic
      Settings.MaxSpread = 5.0;
      Settings.MinATR = 0.0;
      
      Settings.UseTime   = false; 
      Settings.UseNews   = false;
      Settings.UseHTF    = false; 
      
      Settings.VoteThreshold = 1;      // One signal is enough
      
      Settings.P_Ema1 = 12;            // Standard Fast
      Settings.P_Ema3 = 34; Settings.P_Ema4 = 55;
      
      // Indicators: Only EMA Signal needed
      Settings.Use_EmaSig = true;      
      Settings.Use_Adx    = false;        
      Settings.Use_Macd   = false;
      Settings.Use_Psar   = false;
      Settings.Use_Ross   = false;
      Settings.Use_Rsi    = false;
      Settings.Use_Cci    = false;
      
      // Exit: Disable all safety nets to allow full trend runs
      Settings.SL_Mult = 0.0;          // NO SL
      Settings.TP_Mult = 0.0;          // NO TP
      Settings.Use_BE  = false;         
      Settings.TrailMode = TRAIL_NONE;
   }
}

//+------------------------------------------------------------------+
//| Main OnTick                                                      |
//+------------------------------------------------------------------+
void OnTick()
{
   // 1. Manage Open Positions (Tick based)
   if(PositionSelect(_Symbol)) {
      ManageExit();
   }

   // 2. Filters & New Bar
   if(!IsNewBar()) return;
   
   // 3. Re-Entry Lock: Prevent multiple trades on same candle
   if(g_last_trade_bar == iTime(_Symbol, PERIOD_CURRENT, 0)) return;

   // 4. Global Filters
   if(!CheckBasicFilters()) return;
   if(Settings.UseTime && !CheckTimeFilter()) return;
   if(Settings.UseNews && !CheckNewsFilter()) return;

   // 5. BIAS (Context)
   int bias = GetBias();
   if(bias == 0) return;
   
   if(Settings.UseHTF) {
      if(!CheckHTF(bias)) return;
   }

   // 6. VOTING
   int votes = 0;
   
   if(Settings.Use_EmaSig && CheckSignal_EMA1(bias))    votes++;
   if(Settings.Use_Adx    && CheckSignal_ADX())         votes++; 
   if(Settings.Use_Macd   && CheckSignal_MACD(bias))    votes++;
   if(Settings.Use_Rsi    && CheckSignal_RSI(bias))     votes++;
   if(Settings.Use_Cci    && CheckSignal_CCI(bias))     votes++;
   if(Settings.Use_Mfi    && CheckSignal_MFI(bias))     votes++;
   if(Settings.Use_Sto    && CheckSignal_Sto(bias))     votes++;
   if(Settings.Use_Bb     && CheckSignal_BB(bias))      votes++;
   if(Settings.Use_Psar   && CheckSignal_PSAR(bias))    votes++;
   if(Settings.Use_P123   && CheckSignal_Pattern123(bias)) votes++;
   if(Settings.Use_Ross   && CheckSignal_RossHook(bias))   votes++;

   // 7. EXECUTE
   if(votes >= Settings.VoteThreshold) {
      if(bias == 1)      ExecuteTrade(ORDER_TYPE_BUY);
      else if(bias == -1) ExecuteTrade(ORDER_TYPE_SELL);
   }
}

//+------------------------------------------------------------------+
//| EXECUTION & MANAGEMENT                                           |
//+------------------------------------------------------------------+
void ExecuteTrade(ENUM_ORDER_TYPE signalType) {
   // Check Existing Position
   if(PositionSelect(_Symbol)) {
      long posType = PositionGetInteger(POSITION_TYPE);
      
      // If we are already in the correct direction, do nothing
      if((signalType == ORDER_TYPE_BUY && posType == POSITION_TYPE_BUY) ||
         (signalType == ORDER_TYPE_SELL && posType == POSITION_TYPE_SELL)) {
         return; 
      }
      
      // If Opposite Direction...
      if(Settings.CloseOnReverse) {
         trade.PositionClose(_Symbol); // REVERSAL LOGIC: Close current
         // Proceed to open new...
      } else {
         return; // Logic blocked by existing trade (No Hedging/Martingale)
      }
   }

   // Open New Trade
   double atr = GetIndValue(g_h_atr, 1);
   double sl_dist = (Settings.SL_Mult > 0) ? atr * Settings.SL_Mult : 0;
   double tp_dist = (Settings.TP_Mult > 0) ? atr * Settings.TP_Mult : 0;
   
   double price = (signalType==ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl = 0, tp = 0;
   
   if(sl_dist > 0) sl = (signalType==ORDER_TYPE_BUY) ? price-sl_dist : price+sl_dist;
   if(tp_dist > 0) tp = (signalType==ORDER_TYPE_BUY) ? price+tp_dist : price-tp_dist;
   
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   if(sl>0) sl = NormalizeDouble(sl, digits);
   if(tp>0) tp = NormalizeDouble(tp, digits);
   
   double lot = 0.01; // Simple lots for testing
   
   if(trade.PositionOpen(_Symbol, signalType, lot, price, sl, tp, "SimpleEA v1.02.12d")) {
      Print("Trade Opened: ", EnumToString(signalType));
      
      // RECORD TRADE TIME TO PREVENT RE-ENTRY
      g_last_trade_bar = iTime(_Symbol, PERIOD_CURRENT, 0); 
   }
}

//+------------------------------------------------------------------+
//| REPORT GENERATION (Excel Ready)                                  |
//+------------------------------------------------------------------+
void GenerateReport() {
   if(!MQLInfoInteger(MQL_TESTER)) return; // Only in Tester
   
   string start_str = TimeToString(g_start_time, TIME_DATE);
   string end_str   = TimeToString(TimeCurrent(), TIME_DATE);
   StringReplace(start_str, ".", "-"); 
   StringReplace(end_str, ".", "-");
   
   string filename = StringFormat("Report_SimpleEA_%s_%s_%s_%s.csv", 
                                  _Symbol, 
                                  EnumToString(_Period), 
                                  start_str,
                                  end_str);
                                  
   // FIX: Removed FILE_COMMON. Now saves to MQL5/Files (Standard Data Folder)
   int handle = FileOpen(filename, FILE_CSV|FILE_WRITE|FILE_ANSI, ",");
   if(handle == INVALID_HANDLE) {
      Print("Report: Failed to write ", filename);
      return;
   }
   
   // --- SECTION 1: FULL CONFIGURATION ---
   FileWrite(handle, "=== TEST CONFIGURATION ===");
   FileWrite(handle, "Preset Mode", EnumToString(InpPreset));
   FileWrite(handle, "Logic: CloseOnReverse", Settings.CloseOnReverse);
   FileWrite(handle, "Risk: Percent", Settings.RiskPercent);
   FileWrite(handle, "Bias: Enabled", Settings.BiasEnabled);
   FileWrite(handle, "Bias: Mode", EnumToString(Settings.BiasMode));
   FileWrite(handle, "Filters: Time/News/HTF", (string)Settings.UseTime + "/" + (string)Settings.UseNews + "/" + (string)Settings.UseHTF);
   FileWrite(handle, "Voting: Threshold", Settings.VoteThreshold);
   FileWrite(handle, "Exit: SL Mult", Settings.SL_Mult);
   FileWrite(handle, "Exit: TP Mult", Settings.TP_Mult);
   FileWrite(handle, "Exit: Breakeven", Settings.Use_BE);
   FileWrite(handle, "Indicators:", 
      "EMA="+ (string)Settings.Use_EmaSig, 
      "ADX="+ (string)Settings.Use_Adx, 
      "MACD="+ (string)Settings.Use_Macd);
   FileWrite(handle, ""); // Spacer
   
   // --- SECTION 2: METRICS ---
   FileWrite(handle, "=== PERFORMANCE METRICS ===");
   FileWrite(handle, "Net Profit", DoubleToString(TesterStatistics(STAT_PROFIT), 2));
   FileWrite(handle, "Total Trades", DoubleToString(TesterStatistics(STAT_TRADES), 0));
   FileWrite(handle, "Profit Factor", DoubleToString(TesterStatistics(STAT_PROFIT_FACTOR), 2));
   FileWrite(handle, "Sharpe Ratio", DoubleToString(TesterStatistics(STAT_SHARPE_RATIO), 2));
   FileWrite(handle, "Drawdown Equity %", DoubleToString(TesterStatistics(STAT_EQUITY_DDREL_PERCENT), 2) + "%");
   FileWrite(handle, "Win Rate %", DoubleToString((TesterStatistics(STAT_PROFIT_TRADES)/TesterStatistics(STAT_TRADES))*100, 1) + "%");
   FileWrite(handle, ""); 
   
   // --- SECTION 3: DEAL HISTORY ---
   FileWrite(handle, "=== DEAL HISTORY (Graph Data) ===");
   FileWrite(handle, "Time", "Symbol", "Type", "Volume", "Price", "Profit", "Balance");
   
   HistorySelect(0, TimeCurrent());
   int deals = HistoryDealsTotal();
   double balance = TesterStatistics(STAT_INITIAL_DEPOSIT); 
   
   for(int i=0; i<deals; i++) {
      ulong ticket = HistoryDealGetTicket(i);
      long type = HistoryDealGetInteger(ticket, DEAL_TYPE);
      
      // Filter for actual trades
      if(type == DEAL_TYPE_BUY || type == DEAL_TYPE_SELL) {
         datetime time = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
         double vol    = HistoryDealGetDouble(ticket, DEAL_VOLUME);
         double price  = HistoryDealGetDouble(ticket, DEAL_PRICE);
         double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT) + 
                         HistoryDealGetDouble(ticket, DEAL_SWAP) + 
                         HistoryDealGetDouble(ticket, DEAL_COMMISSION);
         
         balance += profit; 
         string s_type = (type==DEAL_TYPE_BUY) ? "Buy" : "Sell";
         string s_time = TimeToString(time, TIME_DATE|TIME_MINUTES);
         
         FileWrite(handle, s_time, _Symbol, s_type, DoubleToString(vol, 2), DoubleToString(price, 5), DoubleToString(profit, 2), DoubleToString(balance, 2));
      }
   }
   
   FileClose(handle);
   Print(">> REPORT SAVED: MQL5/Files/", filename, " <<");
}

//+------------------------------------------------------------------+
//| UTILITIES & FILTERS                                              |
//+------------------------------------------------------------------+
bool IsNewBar() { 
   datetime c = iTime(_Symbol, PERIOD_CURRENT, 0); 
   if(c != g_last_bar_time) { 
      g_last_bar_time = c; 
      return true; 
   } 
   return false; 
}

int GetHandleByRole(EEmaRole role) { 
   if(role==ROLE_EMA1) return g_h_ema1; 
   if(role==ROLE_EMA2) return g_h_ema2; 
   if(role==ROLE_EMA3) return g_h_ema3; 
   return g_h_ema4; 
}

double GetIndValue(int handle, int shift) { 
   double b[1]; 
   if(CopyBuffer(handle, 0, shift, 1, b) > 0) return b[0]; 
   return 0.0; 
}

bool GetIndBuffer(int handle, int buf_idx, int shift, double &arr[]) { 
   return (CopyBuffer(handle, buf_idx, shift, 1, arr) > 0); 
}

int GetSlope(int handle) { 
   double c=GetIndValue(handle,1); 
   double p=GetIndValue(handle,2); 
   return (c>p)?1:(c<p)?-1:0; 
}

double GetFractal(int shift, int mode) { 
   double r[1]; 
   if(CopyBuffer(g_h_fractals, mode, shift, 1, r) > 0 && r[0] != DBL_MAX) return r[0]; 
   return 0.0; 
}

bool CheckBasicFilters() { 
   double s = (SymbolInfoDouble(_Symbol, SYMBOL_ASK)-SymbolInfoDouble(_Symbol, SYMBOL_BID))/_Point; 
   if(s > Settings.MaxSpread * 10) return false;
   
   return (GetIndValue(g_h_atr,1)/(_Point*10) >= Settings.MinATR);
}

int GetBias() {
   if(!Settings.BiasEnabled) return 0;
   
   if(Settings.BiasMode == BIAS_MANUAL) {
      if(Settings.ManSide == SIDE_LONG) return 1;
      if(Settings.ManSide == SIDE_SHORT) return -1;
      return GetSlope(g_h_ema4);
   }
   
   int hf = GetHandleByRole(Settings.BiasFastID == 0 ? ROLE_EMA1 : Settings.BiasFastID == 1 ? ROLE_EMA2 : Settings.BiasFastID == 2 ? ROLE_EMA3 : ROLE_EMA4);
   int hs = GetHandleByRole(Settings.BiasSlowID == 0 ? ROLE_EMA1 : Settings.BiasSlowID == 1 ? ROLE_EMA2 : Settings.BiasSlowID == 2 ? ROLE_EMA3 : ROLE_EMA4);
   
   if(Settings.AutoStrat == STRAT_SINGLE_SLOPE) return GetSlope(hf);
   
   double f = GetIndValue(hf,1); 
   double s = GetIndValue(hs,1);
   return (f>s)?1:(f<s)?-1:0;
}

bool CheckHTF(int bias) {
   double b[2]; 
   if(CopyBuffer(g_h_htf_ema,0,1,2,b)<2) return true;
   return (bias == ((b[1]>b[0])?1:-1));
}

bool CheckTimeFilter() {
   MqlDateTime dt; 
   TimeCurrent(dt);
   
   if(Settings.StartHr < Settings.EndHr) 
      return (dt.hour >= Settings.StartHr && dt.hour < Settings.EndHr);
   else 
      return (dt.hour >= Settings.StartHr || dt.hour < Settings.EndHr);
}

bool CheckNewsFilter() {
   if(ArraySize(g_news_events) == 0) return true; 
   
   datetime now = TimeCurrent();
   string base = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_BASE);
   string profit = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_PROFIT);
   
   for(int i=0; i<ArraySize(g_news_events); i++) {
      if(g_news_events[i].currency != base && g_news_events[i].currency != profit && g_news_events[i].currency != "USD") continue;
      
      long diff = (long)now - (long)g_news_events[i].time;
      
      if(diff < 0 && MathAbs(diff) <= Settings.NewsPre * 60) return false;
      if(diff >= 0 && diff <= Settings.NewsPost * 60) return false;
   }
   return true;
}

void LoadNewsCSV() {
   int handle = FileOpen(Inp_NewsFile, FILE_READ|FILE_CSV|FILE_ANSI, ",");
   if(handle == INVALID_HANDLE) { 
      Print("News: File Not Found"); 
      return; 
   }
   
   if(!FileIsEnding(handle)) { 
      string d = FileReadString(handle); 
      if(StringFind(d, "Date") >= 0) { 
         FileReadString(handle); FileReadString(handle); FileReadString(handle); 
      } else {
         FileSeek(handle, 0, SEEK_SET); 
      }
   }
   
   while(!FileIsEnding(handle)) {
      string d1 = FileReadString(handle); 
      string d2 = FileReadString(handle); 
      string d3 = FileReadString(handle);
      string full = d1 + "," + d2 + "," + d3; 
      StringReplace(full, "\"", "");
      
      string event = FileReadString(handle); 
      string impact = FileReadString(handle); 
      string curr = FileReadString(handle);
      
      if(impact == "High" || impact == "Medium") {
         string p[]; StringSplit(full, ',', p);
         if(ArraySize(p) >= 3) {
            string db = p[1]; StringTrimLeft(db); 
            string md[]; StringSplit(db, ' ', md);
            int m = 1; 
            if(md[0]=="February")m=2; else if(md[0]=="March")m=3; else if(md[0]=="April")m=4; 
            else if(md[0]=="May")m=5; else if(md[0]=="June")m=6; else if(md[0]=="July")m=7; 
            else if(md[0]=="August")m=8; else if(md[0]=="September")m=9; else if(md[0]=="October")m=10; 
            else if(md[0]=="November")m=11; else if(md[0]=="December")m=12;
            
            datetime t = StringToTime(p[0] + "." + (string)m + "." + md[1] + " " + p[2]);
            int s = ArraySize(g_news_events); ArrayResize(g_news_events, s+1);
            g_news_events[s].time = t; 
            g_news_events[s].currency = curr; 
            g_news_events[s].impact = impact;
         }
      }
   }
   FileClose(handle);
}

//+------------------------------------------------------------------+
//| SIGNAL CHECKS                                                    |
//+------------------------------------------------------------------+
bool CheckSignal_EMA1(int bias) {
   double price = iClose(_Symbol, PERIOD_CURRENT, 1);
   double ema   = GetIndValue(g_h_ema1, 1);
   
   if(bias == 1) return (price > ema);
   if(bias == -1) return (price < ema);
   return false;
}

bool CheckSignal_ADX() {
   return (GetIndValue(g_h_adx, 1) > Settings.T_Adx);
}

bool CheckSignal_MFI(int bias) {
   double mfi = GetIndValue(g_h_mfi, 1);
   
   if(bias == 1) return (mfi > Settings.T_Mfi);
   if(bias == -1) return (mfi < (100 - Settings.T_Mfi)); 
   return false;
}

bool CheckSignal_MACD(int bias) {
   double main[], sig[];
   if(!GetIndBuffer(g_h_macd, 0, 1, main)) return false;
   if(!GetIndBuffer(g_h_macd, 1, 1, sig)) return false;
   
   if(Settings.MacdMode == MACD_SIGNAL_ALIGN) {
      if(bias == 1) return (main[0] > sig[0]);
      if(bias == -1) return (main[0] < sig[0]);
   }
   if(Settings.MacdMode == MACD_ZERO_CROSS) {
      if(bias == 1) return (main[0] > 0);
      if(bias == -1) return (main[0] < 0);
   }
   return false;
}

bool CheckSignal_RSI(int bias) {
   double rsi = GetIndValue(g_h_rsi, 1);
   
   if(Settings.RsiMode == RSI_FILTER_EXTREME) {
      if(bias == 1) return (rsi < Settings.T_RsiOB);
      if(bias == -1) return (rsi > Settings.T_RsiOS);
   }
   if(Settings.RsiMode == RSI_TREND_ABOVE_50) {
      if(bias == 1) return (rsi > 50);
      if(bias == -1) return (rsi < 50);
   }
   if(Settings.RsiMode == RSI_CROSS_LEVEL) {
       if(bias == 1) return (rsi > Settings.T_RsiOS); 
       if(bias == -1) return (rsi < Settings.T_RsiOB);
   }
   return false;
}

bool CheckSignal_CCI(int bias) {
   double cci = GetIndValue(g_h_cci, 1);
   
   if(Settings.CciMode == CCI_TREND_ZERO) {
      if(bias == 1) return (cci > 0);
      if(bias == -1) return (cci < 0);
   }
   if(Settings.CciMode == CCI_IMPULSE_100) {
      if(bias == 1) return (cci > 100);
      if(bias == -1) return (cci < -100);
   }
   return false;
}

bool CheckSignal_Sto(int bias) {
   double k[1], d[1];
   CopyBuffer(g_h_sto, 0, 1, 1, k); 
   CopyBuffer(g_h_sto, 1, 1, 1, d);
   
   if(Settings.StoMode == STO_CROSS_SIGNAL) {
      if(bias == 1) return (k[0] > d[0]);
      if(bias == -1) return (k[0] < d[0]);
   }
   if(Settings.StoMode == STO_ZONE_FILTER) {
      if(bias == 1) return (k[0] < 80);
      if(bias == -1) return (k[0] > 20); 
   }
   return false;
}

bool CheckSignal_BB(int bias) {
   double mid = GetIndValue(g_h_bb, 0); 
   double lower = GetIndValue(g_h_bb, 2); 
   double close = iClose(_Symbol, PERIOD_CURRENT, 1);
   
   if(Settings.BbMode == BB_TREND_FOLLOW) {
      if(bias == 1) return (close > mid);
      if(bias == -1) return (close < mid);
   }
   if(Settings.BbMode == BB_MEAN_REVERSION) {
       if(bias == 1) return (iLow(_Symbol, PERIOD_CURRENT, 1) < lower);
       
       double upper = GetIndValue(g_h_bb, 1);
       if(bias == -1) return (iHigh(_Symbol, PERIOD_CURRENT, 1) > upper);
   }
   return false;
}

bool CheckSignal_PSAR(int bias) {
   if(!Inp_Use_Psar) return false;
   
   double psar = GetIndValue(g_h_psar, 1); 
   double close = iClose(_Symbol, PERIOD_CURRENT, 1);
   
   if(bias == 1) return (close > psar);
   if(bias == -1) return (close < psar);
   return false;
}

bool CheckSignal_Pattern123(int bias) {
   double f1_val=0, f2_val=0, f3_val=0; 
   int f1_idx=0, f2_idx=0, f3_idx=0;
   
   if(bias == 1) { // BUY
      int found_down = 0; 
      int found_up = 0;
      for(int i=2; i<40; i++) {
         double up = GetFractal(i, 0); 
         double down = GetFractal(i, 1); 
         
         if(down > 0) {
            if(found_down == 0) { f3_val = down; f3_idx = i; found_down++; } 
            else if(found_down == 1 && found_up == 1) { f1_val = down; f1_idx = i; found_down++; break; } 
         }
         if(up > 0) { 
            if(found_down == 1 && found_up == 0) { f2_val = up; f2_idx = i; found_up++; } 
         }
      }
      if(f1_val > 0 && f2_val > 0 && f3_val > 0) { 
         if(f3_val > f1_val) { 
            if(iClose(_Symbol, PERIOD_CURRENT, 1) > f2_val) return true; 
         } 
      }
   }
   
   if(bias == -1) { // SELL
      int found_up = 0; 
      int found_down = 0;
      for(int i=2; i<40; i++) {
         double up = GetFractal(i, 0); 
         double down = GetFractal(i, 1); 
         
         if(up > 0) {
            if(found_up == 0) { f3_val = up; f3_idx = i; found_up++; } 
            else if(found_up == 1 && found_down == 1) { f1_val = up; f1_idx = i; found_up++; break; } 
         }
         if(down > 0) { 
            if(found_up == 1 && found_down == 0) { f2_val = down; f2_idx = i; found_down++; } 
         }
      }
      if(f1_val > 0 && f2_val > 0 && f3_val > 0) { 
         if(f3_val < f1_val) { 
            if(iClose(_Symbol, PERIOD_CURRENT, 1) < f2_val) return true; 
         } 
      }
   }
   return false;
}

bool CheckSignal_RossHook(int bias) {
   for(int i=2; i<=20; i++) {
      double up = GetFractal(i, 0); 
      double down = GetFractal(i, 1);
      
      if(bias == 1 && up > 0) 
         return (iClose(_Symbol, PERIOD_CURRENT, 1) > up); 
         
      if(bias == -1 && down > 0) 
         return (iClose(_Symbol, PERIOD_CURRENT, 1) < down); 
   }
   return false;
}

//+------------------------------------------------------------------+
//| EXECUTION & MANAGEMENT                                           |
//+------------------------------------------------------------------+
void ManageExit() {
   if(!PositionSelect(_Symbol)) return;
   
   double atr = GetIndValue(g_h_atr, 1);
   if(Settings.Use_BE) ManageBreakeven(atr);
   if(Settings.TrailMode == TRAIL_NONE) return;
   
   ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   double current_sl = PositionGetDouble(POSITION_SL);
   double current_price = PositionGetDouble(POSITION_PRICE_CURRENT);
   double new_sl = 0.0;
   
   if(Settings.TrailMode == TRAIL_ATR) {
      double dist = atr * Settings.Trail_Mult;
      new_sl = (type == POSITION_TYPE_BUY) ? 
         SymbolInfoDouble(_Symbol, SYMBOL_BID) - dist : SymbolInfoDouble(_Symbol, SYMBOL_ASK) + dist;
   }
   else if(Settings.TrailMode == TRAIL_PSAR) {
      new_sl = GetIndValue(g_h_psar, 1);
      if((type == POSITION_TYPE_BUY && new_sl > current_price) || 
         (type == POSITION_TYPE_SELL && new_sl < current_price)) return;
   }
   else if(Settings.TrailMode == TRAIL_FRACTAL) {
      for(int i=2; i<20; i++) {
         double up = GetFractal(i, 0); 
         double down = GetFractal(i, 1);
         if(type == POSITION_TYPE_BUY && down > 0) { new_sl = down; break; }
         if(type == POSITION_TYPE_SELL && up > 0) { new_sl = up; break; }
      }
   }

   if(new_sl != 0.0) {
      int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
      new_sl = NormalizeDouble(new_sl, digits);
      bool modify = false;
      
      if(type == POSITION_TYPE_BUY) { 
         if(new_sl > current_sl && new_sl < current_price) modify = true; 
      } 
      else { 
         if((new_sl < current_sl || current_sl == 0) && new_sl > current_price) modify = true; 
      }
      
      if(modify) trade.PositionModify(_Symbol, new_sl, PositionGetDouble(POSITION_TP));
   }
}

void ManageBreakeven(double atr) {
   if(PositionGetInteger(POSITION_MAGIC) == 0 && StringFind(PositionGetString(POSITION_COMMENT), "SimpleEA") < 0) return; 
   
   ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   double open = PositionGetDouble(POSITION_PRICE_OPEN);
   double curr = PositionGetDouble(POSITION_PRICE_CURRENT);
   double sl = PositionGetDouble(POSITION_SL);
   double trig = atr * Settings.BE_Trig;
   double buff = atr * Settings.BE_Buff;
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   
   if(type == POSITION_TYPE_BUY && curr >= open + trig) {
      double t_sl = NormalizeDouble(open + buff, digits);
      if(sl < t_sl) trade.PositionModify(_Symbol, t_sl, PositionGetDouble(POSITION_TP));
   }
   else if(type == POSITION_TYPE_SELL && curr <= open - trig) {
      double t_sl = NormalizeDouble(open - buff, digits);
      if(sl > t_sl || sl == 0) trade.PositionModify(_Symbol, t_sl, PositionGetDouble(POSITION_TP));
   }
}
//+------------------------------------------------------------------+