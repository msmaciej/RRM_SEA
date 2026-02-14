//+------------------------------------------------------------------+
//|                                  SEA_SignalEngine_v1-02-016d.mqh |
//|                              MJS Institutional Trading Solutions |
//|                                                                  |
//| Purpose: Signal Logic, Indicator Management, Voting & Filters    |
//| Status:  PRODUCTION READY (Revision M: Full Dual Shift Support)  |
//| TASK1 OPT: Added MaxATR upper volatility bound                    |
//+------------------------------------------------------------------+
// SAVE AS UTF-16 LE WITH BOM
#property strict

// --- Anti-stale build lock (MQL5-safe: no #if, no #error)
#ifndef SEA_BUILD_TOKEN_102016D
enum { __SEA_BUILD_TOKEN_MISSING_SIGNALENGINE_102016D = SEA_BUILD_TOKEN_102016D };
#endif

#define SEA_MOD_SIGNALENGINE_102016D 1


// Note: Requires ST_Settings and SNewsEvent structs to be defined in main file

class CSignalEngine {
private:
   // --- 1. INDICATOR HANDLES ---
   int h_ema1;    // Period 1 (Fastest)
   int h_ema2;    // Period 2
   int h_ema3;    // Period 3
   int h_ema4;    // Period 4 (Slowest)
   
   int h_macd, h_rsi, h_cci, h_sto;      // Oscillators
   int h_atr, h_bb, h_psar, h_fractals;  // Volatility & Trend
   int h_adx, h_mfi;                     // Strength & Volume
   
   int h_htf_ema; // Higher Timeframe Filter

   // --- 2. INTERNAL DATA ---
   ST_Settings m_settings;
   SNewsEvent  m_news_events[];
   string      m_symbol;
   int         m_news_count;
   datetime    m_last_news_block_log;

   // --- 2b. DIAGNOSTICS (for Cockpit/UI) ---
   int         m_diag_last_bias;
   int         m_diag_last_votes;
   string      m_diag_last_reason;
   double      m_diag_last_atr_pips;
   bool        m_diag_last_atr_ok;

   // --- 3. DATA HELPERS ---
   // Simplified buffer access for cleaner logic code
   double GetVal(int handle, int shift, int buffer_num=0) const {
      double b[1];
      if(CopyBuffer(handle, buffer_num, shift, 1, b) > 0) return b[0];
      return 0.0;
   }

   // NOTE: In MT5, the iMA() 'ma_shift' parameter already shifts the indicator line.
   // Therefore CopyBuffer() returns a series aligned to that shifted plot.
   // IMPORTANT: Do NOT apply ma_h_shift a second time in logic reads.
   double GetMAVal(const int handle, const int shift, const int buffer_num=0) {
      return GetVal(handle, shift, buffer_num);
   }

   bool GetBuf(int handle, int buf_idx, int shift, double &arr[]) {
      return (CopyBuffer(handle, buf_idx, shift, 1, arr) > 0);
   }

   // --- 4. PATTERN RECOGNITION HELPERS ---
   // Finds the price of the Nth fractal (1 = Latest detected)
   double GetFractalPrice(int mode, int limit_bars=30) {
      double r[1];
      int found = 0;
      // Start from bar 2 to ensure fractal is confirmed (repaint safety)
      for(int i=2; i<limit_bars; i++) {
         if(CopyBuffer(h_fractals, mode, i, 1, r) > 0 && r[0] != DBL_MAX && r[0] > 0) {
            found++;
            if(found == 1) return r[0]; // Return the first one found
         }
      }
      return 0.0;
   }

   // --- 5. SIGNAL CHECKS (VOTING LOGIC) ---
   
   // Vote 1: EMA Recovery (Price vs EMA1)
   bool Check_EMA1(int bias, int shift) {
      double p = iClose(m_symbol, PERIOD_CURRENT, shift);
      double e = GetMAVal(h_ema1, shift);
      return (bias == 1) ? (p > e) : (p < e);
   }
   
   // Vote 2: ADX Strength (Trend Strength)
   bool Check_ADX(int shift) { 
      return GetVal(h_adx, shift) > m_settings.T_Adx; 
   }
   
   // Vote 3: MACD (Alignment or Zero Cross)
   // 
   // MACD Indicator has 3 buffer outputs:
   //   Buffer 0 = MACD Main Line (fast EMA - slow EMA)
   //   Buffer 1 = MACD Signal Line (SMA of Main Line)
   //   Buffer 2 = MACD Histogram (Main - Signal) [NOT USED HERE]
   //
   // WHY NOT USE HISTOGRAM?
   // - Histogram only shows RELATIVE position (main vs signal)
   // - We need ABSOLUTE position (main vs zero line) for RRM rules
   // - Example: Histogram rising but both lines below zero = FALSE bullish signal
   // 
   // RRM REQUIREMENT:
   // - LONG: MACD must be ABOVE zero (bullish momentum) AND rising (main > signal)
   // - SHORT: MACD must be BELOW zero (bearish momentum) AND falling (main < signal)
   //
   bool Check_MACD(int bias, int shift) {
      // Read MACD values at specified bar shift
      // shift parameter = which bar (0=current, 1=previous, 2=two bars ago)
      // buffer index = which line (0=main, 1=signal, 2=histogram)
      double m = GetVal(h_macd, shift, 0); // Main Line at bar 'shift'
      double s = GetVal(h_macd, shift, 1); // Signal Line at bar 'shift'
      
      if(m_settings.MacdMode == MACD_SIGNAL_ALIGN) {
         // RRM FIX: Require BOTH zero-line position AND histogram direction
         // This prevents taking longs when MACD is bearish (below zero)
         // and prevents taking shorts when MACD is bullish (above zero)
         if(bias == 1) {
            // LONG: MACD must be above zero AND main above signal
            // Equivalent to: "MACD is bullish AND accelerating upward"
            return (m > 0 && m > s);
         } else {
            // SHORT: MACD must be below zero AND main below signal
            // Equivalent to: "MACD is bearish AND accelerating downward"
            return (m < 0 && m < s);
         }
      }
      // Zero Cross Mode (unchanged)
      // Only checks if MACD main line is above/below zero
      // Does NOT require alignment with signal line
      return (bias==1) ? (m > 0) : (m < 0);
   }
   
   // Vote 4: RSI (Extreme Filter or Trend)
   bool Check_RSI(int bias, int shift) {
      double r = GetVal(h_rsi, shift);
      
      if(m_settings.RsiMode == RSI_FILTER_EXTREME) {
         // Buy if NOT Overbought, Sell if NOT Oversold
         return (bias==1) ? (r < m_settings.T_RsiOB) : (r > m_settings.T_RsiOS);
      }
      if(m_settings.RsiMode == RSI_TREND_ABOVE_50) {
         return (bias==1) ? (r > 50) : (r < 50);
      }
      // Cross Level Mode
      return (bias==1) ? (r > m_settings.T_RsiOS) : (r < m_settings.T_RsiOB);
   }
   
   // Vote 5: CCI (Zero or Impulse)
   bool Check_CCI(int bias, int shift) {
      double c = GetVal(h_cci, shift);
      if(m_settings.CciMode == CCI_TREND_ZERO) return (bias==1) ? (c > 0) : (c < 0);
      return (bias==1) ? (c > 100) : (c < -100);
   }
   
   // Vote 6: MFI (Money Flow)
   bool Check_MFI(int bias, int shift) {
      double m = GetVal(h_mfi, shift);
      return (bias==1) ? (m > m_settings.T_Mfi) : (m < (100-m_settings.T_Mfi));
   }
   
   // Vote 7: Stochastic
   bool Check_Sto(int bias, int shift) {
      double k = GetVal(h_sto, shift, 0);
      double d = GetVal(h_sto, shift, 1);
      
      if(m_settings.StoMode == STO_CROSS_SIGNAL) 
         return (bias==1) ? (k > d) : (k < d);
         
      // Zone Filter: Buy if NOT overbought
      return (bias==1) ? (k < 80) : (k > 20);
   }
   
   // Vote 8: Bollinger Bands
   bool Check_BB(int bias, int shift) {
      double mid = GetVal(h_bb, shift, 0);
      double cl  = iClose(m_symbol, PERIOD_CURRENT, shift);
      
      if(m_settings.BbMode == BB_TREND_FOLLOW) 
         return (bias==1) ? (cl > mid) : (cl < mid);
      
      // Mean Reversion: Price touched Lower/Upper Band
      double lower = GetVal(h_bb, shift, 2);
      double upper = GetVal(h_bb, shift, 1);
      double low   = iLow(m_symbol, PERIOD_CURRENT, shift);
      double high  = iHigh(m_symbol, PERIOD_CURRENT, shift);
      
      return (bias==1) ? (low <= lower) : (high >= upper);
   }
   
   // Vote 9: PSAR
   bool Check_PSAR(int bias, int shift) {
      double p = GetVal(h_psar, shift);
      double cl = iClose(m_symbol, PERIOD_CURRENT, shift);
      return (bias==1) ? (cl > p) : (cl < p);
   }
   
   // Vote 10: Pattern 1-2-3 (Breakout)
   bool Check_P123(int bias, int shift) {
      // 1. Get most recent Upper and Lower Fractals
      double last_up   = GetFractalPrice(0); // 0 = UPPER
      double last_down = GetFractalPrice(1); // 1 = LOWER
      double close     = iClose(m_symbol, PERIOD_CURRENT, shift);
      
      // Buy: Breakout above last Upper Fractal
      if(bias == 1  && last_up > 0   && close > last_up)   return true;
      // Sell: Breakout below last Lower Fractal
      if(bias == -1 && last_down > 0 && close < last_down) return true;
      
      m_diag_last_reason="NEWS";
                  return false;
   }
   
   // Vote 11: Ross Hook (Trend-Following Momentum Interlock)
   bool Check_Ross(int bias, int shift) {
      // 1. PRICE ACTION BREAKOUT
      bool fractalBreakout = Check_P123(bias, shift);
      
      // 2. DYNAMIC EMA SLOPE CHECK (SECURE)
      int hf = (m_settings.BiasFastID==0)?h_ema1 : (m_settings.BiasFastID==1)?h_ema2 : (m_settings.BiasFastID==2)?h_ema3 : h_ema4;
      
      // Get slope based on current vertical shift
      double c = GetMAVal(hf, shift);
      double p = GetMAVal(hf, shift + 1);
      int trendSlope = (c > p) ? 1 : (c < p) ? -1 : 0;
      
      // 3. THE "PURIST" INTERLOCK (Breakout + Momentum Alignment)
      if(fractalBreakout && trendSlope == bias) {
         return true; 
      }
      
      return false;
   }

   // --- 12. NEWS HELPERS (CSV calendar_statement.csv) ---
   string TrimStr(string s) {
      StringTrimLeft(s);
      StringTrimRight(s);
      return s;
   }

   int MonthToInt(string month) {
      month = TrimStr(month);
      StringToLower(month);
      if(month == "january")   return 1;
      if(month == "february")  return 2;
      if(month == "march")     return 3;
      if(month == "april")     return 4;
      if(month == "may")       return 5;
      if(month == "june")      return 6;
      if(month == "july")      return 7;
      if(month == "august")    return 8;
      if(month == "september") return 9;
      if(month == "october")   return 10;
      if(month == "november")  return 11;
      if(month == "december")  return 12;
      return 0;
   }

   // Expected format (from CSV): "YYYY, Month DD, HH:MI"
   datetime ParseNewsDateTime(string s) {
      s = TrimStr(s);
      // FileReadString(FILE_CSV) already strips surrounding quotes in most cases,
      // but tolerate them if present.
      if(StringLen(s) >= 2 && StringGetCharacter(s, 0) == '"' && StringGetCharacter(s, StringLen(s)-1) == '"')
         s = StringSubstr(s, 1, StringLen(s)-2);

      string parts[];
      int n = StringSplit(s, ',', parts);
      if(n < 3) return (datetime)0;

      int year = (int)StringToInteger(TrimStr(parts[0]));

      string md = TrimStr(parts[1]);   // e.g. "January 12"
      string t  = TrimStr(parts[2]);   // e.g. "09:00"

      string md_parts[];
      int mdc = StringSplit(md, ' ', md_parts);
      if(mdc < 2) return (datetime)0;

      int month = MonthToInt(md_parts[0]);
      int day   = (int)StringToInteger(TrimStr(md_parts[1]));
      if(year <= 1970 || month <= 0 || day <= 0) return (datetime)0;

      string dt = StringFormat("%04d.%02d.%02d %s", year, month, day, t);
      return StringToTime(dt);
   }

   // Forex-like extraction: "EURUSD", tolerates broker suffixes (e.g. "EURUSD.a")
   void GetSymbolCurrencies(string sym, string &base, string &quote) {
      base = "";
      quote = "";

      // Keep only letters A-Z.
      string letters = "";
      for(int i=0; i<StringLen(sym); i++) {
         int c = StringGetCharacter(sym, i);
         if(c >= 'A' && c <= 'Z') letters += StringSubstr(sym, i, 1);
         else if(c >= 'a' && c <= 'z') letters += StringSubstr(sym, i, 1);
      }
      StringToUpper(letters);
      if(StringLen(letters) < 6) return;

      // Common: 3+3
      base  = StringSubstr(letters, 0, 3);
      quote = StringSubstr(letters, 3, 3);

      // Metals/indices often start with XAU/XAG but still quote is the last 3.
      // Leave as-is; this keeps the filter predictable.
   }

   bool NewsImpactPass(string impact) {
      impact = TrimStr(impact);
      StringToLower(impact);
      if(impact == "") return true;
      // Reduce excessive blocking: ignore explicit "Low" by default.
      if(StringFind(impact, "low") == 0) return false;
      return true; // Medium / High / anything else treated as relevant
   }

public:

   // --- UI helpers (chart overlays) ---
   int GetEmaHandle(const int role) const
   {
      if(role == 0) return h_ema1;
      if(role == 1) return h_ema2;
      if(role == 2) return h_ema3;
      if(role == 3) return h_ema4;
      return INVALID_HANDLE;
   }
   int GetPsarHandle() const { return h_psar; }
   int GetMacdHandle() const { return h_macd; }


   CSignalEngine() : m_symbol(""), m_news_count(0), m_last_news_block_log(0)
   {
      // Defensive init of indicator handles (prevents stale handles across re-inits)
      h_ema1 = h_ema2 = h_ema3 = h_ema4 = INVALID_HANDLE;
      h_macd = h_rsi = h_cci = h_sto = INVALID_HANDLE;
      h_atr = h_bb = h_psar = h_fractals = INVALID_HANDLE;
      h_adx = h_mfi = INVALID_HANDLE;
      h_htf_ema = INVALID_HANDLE;

      m_diag_last_bias   = 0;
      m_diag_last_votes  = 0;
      m_diag_last_reason = "";
   }

   // --- DIAGNOSTIC GETTERS (for Cockpit/UI) ---
   int    LastBias()   const { return m_diag_last_bias; }
   int    LastVotes()  const { return m_diag_last_votes; }
   string LastReason() const { return m_diag_last_reason; }


   // --- 6. INITIALIZATION ---
   bool Init(ST_Settings &sets, string symbol) {
      m_settings = sets;
      m_symbol   = symbol;
      
      // CONVERT ENUM TO MT5 CONSTANT
      ENUM_MA_METHOD method = (m_settings.MaType == METHOD_SMA) ? MODE_SMA : MODE_EMA;
      int h_shift = m_settings.ma_h_shift; // Horizontal Shift support
      
      // A. Create Standard Indicators (Using Dynamic Method and Horizontal Shift)
      h_ema1 = iMA(m_symbol, PERIOD_CURRENT, m_settings.P_Ema1, h_shift, method, PRICE_CLOSE);
      h_ema2 = iMA(m_symbol, PERIOD_CURRENT, m_settings.P_Ema2, h_shift, method, PRICE_CLOSE);
      h_ema3 = iMA(m_symbol, PERIOD_CURRENT, m_settings.P_Ema3, h_shift, method, PRICE_CLOSE);
      h_ema4 = iMA(m_symbol, PERIOD_CURRENT, m_settings.P_Ema4, h_shift, method, PRICE_CLOSE);
      h_atr  = iATR(m_symbol, PERIOD_CURRENT, 14);

      // Optional indicators: create only when used by votes/filters/trailing (reduces Strategy Tester clutter)
      h_macd = (m_settings.Use_Macd ? iMACD(m_symbol, PERIOD_CURRENT, m_settings.P_MacdFast, m_settings.P_MacdSlow, m_settings.P_MacdSig, PRICE_CLOSE) : INVALID_HANDLE);
      h_rsi  = (m_settings.Use_Rsi  ? iRSI(m_symbol, PERIOD_CURRENT, m_settings.P_Rsi, PRICE_CLOSE) : INVALID_HANDLE);
      h_cci  = (m_settings.Use_Cci  ? iCCI(m_symbol, PERIOD_CURRENT, m_settings.P_Cci, PRICE_CLOSE) : INVALID_HANDLE);
      h_adx  = (m_settings.Use_Adx  ? iADX(m_symbol, PERIOD_CURRENT, m_settings.P_Adx) : INVALID_HANDLE);
      h_mfi  = (m_settings.Use_Mfi  ? iMFI(m_symbol, PERIOD_CURRENT, m_settings.P_Mfi, VOLUME_TICK) : INVALID_HANDLE);
      h_sto  = (m_settings.Use_Sto  ? iStochastic(m_symbol, PERIOD_CURRENT, m_settings.P_StoK, m_settings.P_StoD, m_settings.P_StoSlow, MODE_SMA, STO_LOWHIGH) : INVALID_HANDLE);
      h_bb   = (m_settings.Use_Bb   ? iBands(m_symbol, PERIOD_CURRENT, m_settings.P_Bb, 0, m_settings.P_BbDev, PRICE_CLOSE) : INVALID_HANDLE);

      bool need_psar = (m_settings.Use_Psar || m_settings.TrailMode == TRAIL_PSAR);
      h_psar = (need_psar ? iSAR(m_symbol, PERIOD_CURRENT, m_settings.P_PsarStep, m_settings.P_PsarMax) : INVALID_HANDLE);

      bool need_fractals = (m_settings.Use_P123 || m_settings.Use_Ross || m_settings.TrailMode == TRAIL_FRACTAL);
      h_fractals = (need_fractals ? iFractals(m_symbol, PERIOD_CURRENT) : INVALID_HANDLE);
      // B. Create HTF Filter (If Enabled)
      if(m_settings.UseHTF) {
         h_htf_ema = iMA(m_symbol, m_settings.HtfPeriod, m_settings.P_HtfEma, h_shift, method, PRICE_CLOSE);
      }
      
      // C. Validation
      if(h_ema1 == INVALID_HANDLE || h_atr == INVALID_HANDLE) {
         Print("CRITICAL ERROR: Failed to create essential indicators (EMA/ATR).");
         return false;
      }
      return true;
   }


   // --- 7. CLEANUP ---
   void Release()
   {
      // Release only valid handles and reset to INVALID_HANDLE
      if(h_ema1 != INVALID_HANDLE) { IndicatorRelease(h_ema1); h_ema1 = INVALID_HANDLE; }
      if(h_ema2 != INVALID_HANDLE) { IndicatorRelease(h_ema2); h_ema2 = INVALID_HANDLE; }
      if(h_ema3 != INVALID_HANDLE) { IndicatorRelease(h_ema3); h_ema3 = INVALID_HANDLE; }
      if(h_ema4 != INVALID_HANDLE) { IndicatorRelease(h_ema4); h_ema4 = INVALID_HANDLE; }

      if(h_atr  != INVALID_HANDLE) { IndicatorRelease(h_atr);  h_atr  = INVALID_HANDLE; }
      if(h_macd != INVALID_HANDLE) { IndicatorRelease(h_macd); h_macd = INVALID_HANDLE; }
      if(h_rsi  != INVALID_HANDLE) { IndicatorRelease(h_rsi);  h_rsi  = INVALID_HANDLE; }
      if(h_cci  != INVALID_HANDLE) { IndicatorRelease(h_cci);  h_cci  = INVALID_HANDLE; }
      if(h_adx  != INVALID_HANDLE) { IndicatorRelease(h_adx);  h_adx  = INVALID_HANDLE; }
      if(h_mfi  != INVALID_HANDLE) { IndicatorRelease(h_mfi);  h_mfi  = INVALID_HANDLE; }
      if(h_sto  != INVALID_HANDLE) { IndicatorRelease(h_sto);  h_sto  = INVALID_HANDLE; }
      if(h_bb   != INVALID_HANDLE) { IndicatorRelease(h_bb);   h_bb   = INVALID_HANDLE; }
      if(h_psar != INVALID_HANDLE) { IndicatorRelease(h_psar); h_psar = INVALID_HANDLE; }
      if(h_fractals != INVALID_HANDLE) { IndicatorRelease(h_fractals); h_fractals = INVALID_HANDLE; }

      if(m_settings.UseHTF && h_htf_ema != INVALID_HANDLE) { IndicatorRelease(h_htf_ema); h_htf_ema = INVALID_HANDLE; }
   }

   // --- 7a. MA VALIDATION & REPORTING (Deterministic Diagnostics) ---
   int ClampRoleID(const int role_id) const
   {
      if(role_id < 0) return 0;
      if(role_id > 3) return 3;
      return role_id;
   }

   int HandleByRole(const int role_id) const
   {
      switch(ClampRoleID(role_id))
      {
         case 0: return h_ema1;
         case 1: return h_ema2;
         case 2: return h_ema3;
         case 3: return h_ema4;
      }
      return h_ema1;
   }

   int PeriodByRole(const int role_id) const
   {
      switch(ClampRoleID(role_id))
      {
         case 0: return m_settings.P_Ema1;
         case 1: return m_settings.P_Ema2;
         case 2: return m_settings.P_Ema3;
         case 3: return m_settings.P_Ema4;
      }
      return m_settings.P_Ema1;
   }

   string RoleName(const int role_id) const
   {
      switch(ClampRoleID(role_id))
      {
         case 0: return "EMA1";
         case 1: return "EMA2";
         case 2: return "EMA3";
         case 3: return "EMA4";
      }
      return "EMA1";
   }

   string GetMaMethodName() const
   {
      // m_settings.MaType is ENUM_MA_METHOD
      if(m_settings.MaType == METHOD_SMA) return "SMA";
      if(m_settings.MaType == METHOD_EMA) return "EMA";
      return "MA";
   }

   bool ValidateAndReportMA(const bool print_details = true)
   {
      bool ok = true;
      const string method = GetMaMethodName();
      const int h_shift = m_settings.ma_h_shift;
      const int v_shift = m_settings.ma_v_shift;

      for(int r=0; r<4; r++)
      {
         int h = HandleByRole(r);
         int p = PeriodByRole(r);

         if(h == INVALID_HANDLE)
         {
            Print("CRITICAL ERROR: MA handle INVALID for ", RoleName(r), " (period=", p, ", method=", method, ").");
            ok = false;
            continue;
         }

         if(print_details)
         {
            PrintFormat("MA_SETUP: role=%s method=%s period=%d h_shift=%d v_shift=%d handle=%d",
                        RoleName(r), method, p, h_shift, v_shift, h);
         }
      }

      if(print_details)
         Print("MA_SETUP: expected method from settings = ", method);

      return ok;
   }

   double GetATR() const { return GetVal(h_atr, 1); }

   // --- 7b. PRICE UNIT NORMALIZATION ("pips" that work across FX/JPY/metals/CFDs) ---
   // Define a "pip" as:
   //  - 10 points for 5-digit/3-digit symbols (e.g. EURUSD 1.12345, USDJPY 145.123)
   //  - 1 point for 4-digit/2-digit and most CFDs/metals
   // This keeps user-facing inputs (MaxSpreadPips, MinATRPips) meaningful across instruments.
   double PipSize() const
   {
      double point  = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      int digits    = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
      if(digits == 3 || digits == 5)
         return point * 10.0;
      return point;
   }

   double SpreadPips() const
   {
      double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
      double pip = PipSize();
      if(pip <= 0.0) return 0.0;
      return (ask - bid) / pip;
   }

   double AtrPips() const
   {
      double pip = PipSize();
      if(pip <= 0.0) return 0.0;
      double atr = GetATR();
      if(atr <= 0.0) return 0.0;
      return atr / pip;
   }
   // --- 8. NEWS FILTER LOGIC ---
   void LoadNews(string filename) {
      m_news_count = 0;
      ArrayResize(m_news_events, 0);

      // Prefer UTF-8 (common for downloaded calendars), fall back to ANSI.
      int handle = FileOpen(filename, FILE_CSV|FILE_READ|FILE_ANSI, ",");
      if(handle == INVALID_HANDLE)
         handle = FileOpen(filename, FILE_CSV|FILE_READ|FILE_UNICODE, ",");
      if(handle == INVALID_HANDLE) {
         Print("News: Calendar file not found or unreadable (", filename, "). News Filter Disabled.");
         return;
      }

      // Expect header: Date,Event,Impact,Currency
      if(!FileIsEnding(handle)) {
         // Read and discard header fields (4 columns)
         FileReadString(handle);
         FileReadString(handle);
         FileReadString(handle);
         FileReadString(handle);
      }

      while(!FileIsEnding(handle)) {
         string s_date    = FileReadString(handle);
         string s_event   = FileReadString(handle);
         string s_impact  = FileReadString(handle);
         string s_ccy     = FileReadString(handle);

         // Defensive: if the row is malformed, stop cleanly.
         if(FileIsEnding(handle) && (s_date == "" && s_event == "" && s_impact == "" && s_ccy == ""))
            break;

         datetime t = ParseNewsDateTime(s_date);
         string ccy = TrimStr(s_ccy);
         StringToUpper(ccy);
         string imp = TrimStr(s_impact);

         if(t == 0 || ccy == "")
            continue;

         int idx = m_news_count;
         ArrayResize(m_news_events, m_news_count + 1);
         m_news_events[idx].time     = t;
         m_news_events[idx].currency = ccy;
         m_news_events[idx].impact   = imp;
         m_news_count++;
      }

      FileClose(handle);
      Print("News: Loaded ", m_news_count, " events from ", filename);
   }
   
   // --- 9. GLOBAL FILTERS ---
   bool CheckFilters() {
      // A. Time Scheduler
      if(m_settings.UseTime) {
         MqlDateTime dt; TimeCurrent(dt);
         bool pass = (m_settings.StartHr < m_settings.EndHr) ? 
                     (dt.hour >= m_settings.StartHr && dt.hour < m_settings.EndHr) : 
                     (dt.hour >= m_settings.StartHr || dt.hour < m_settings.EndHr);
         if(!pass) { m_diag_last_reason="TIME"; return false; }
      }

      // B. News Filter (CSV calendar_statement.csv)
      if(m_settings.UseNews && m_news_count > 0) {
         string base, quote;
         GetSymbolCurrencies(m_symbol, base, quote);

         // If the symbol can't   be mapped to 2 currencies reliably, do not block.

         //+------------------------------------------------------------------+
         //|                    SEA_SignalEngine PART 2 - CheckFilters Cont    |
         //+------------------------------------------------------------------+
         // CONTINUATION - Paste after line with "GetSymbolCurrencies(m_symbol, base, quote);"

         if(base != "" && quote != "") {
            datetime now = TimeCurrent();
            int pre_sec  = m_settings.NewsPre  * 60;
            int post_sec = m_settings.NewsPost * 60;

            for(int i=0; i<m_news_count; i++) {
               if(!NewsImpactPass(m_news_events[i].impact))
                  continue;

               string ccy = m_news_events[i].currency;
               if(ccy != base && ccy != quote)
                  continue;

               datetime t = m_news_events[i].time;
               if(now >= (t - pre_sec) && now <= (t + post_sec)) {
                  // Throttle log spam (at most once per minute per engine instance)
                  if(m_last_news_block_log == 0 || (now - m_last_news_block_log) >= 60) {
                     PrintFormat("News Filter: blocked %s due to %s %s event at %s (window -%d/+%d min)",
                                 m_symbol,
                                 ccy,
                                 (m_news_events[i].impact==""?"(impact n/a)":m_news_events[i].impact),
                                 TimeToString(t, TIME_DATE|TIME_MINUTES),
                                 m_settings.NewsPre,
                                 m_settings.NewsPost);
                     m_last_news_block_log = now;
                  }
                  return false;
               }
            }
         }
      }
      
      // C. Spread Check
      double spread_pips = SpreadPips();
      if(m_settings.MaxSpread > 0.0 && spread_pips > m_settings.MaxSpread) { m_diag_last_reason="SPREAD"; return false; }
      
      // D. Volatility regime (ATR in pips)
      double atr_pips = AtrPips();
      bool atr_ok = true;
      if(m_settings.MinATR > 0.0 && atr_pips < m_settings.MinATR) atr_ok = false;
      if(m_settings.MaxATR > 0.0 && atr_pips > m_settings.MaxATR) atr_ok = false;

      // Cache for diagnostics and (optional) ATR-as-vote
      m_diag_last_atr_pips = atr_pips;
      m_diag_last_atr_ok   = atr_ok;

      // Expert guidance:
      // - HARD ATR gating is useful as an execution safeguard, but it can starve signals on low TFs.
      // - When ATR_HardGate=false, ATR is treated as a soft regime preference (vote/management), not a blocker.
      if(m_settings.ATR_HardGate && !atr_ok)
      {
         m_diag_last_reason = (atr_pips < m_settings.MinATR ? "MIN_ATR" : "MAX_ATR");
         return false;
      }

      return true;
   }

   // --- 10. MAIN DIRECTION LOGIC (THE BRAIN) ---
   // MetaQuotes 'Moving Average' example logic uses a completed bar that STRADDLES the MA:
   //  - BUY  when Open < MA and Close > MA (up-cross)
   //  - SELL when Open > MA and Close < MA (down-cross)
   // This function evaluates a CLOSED bar (v_shift should be 1 in benchmark mode).
   int PriceCrossDirection(const int ma_handle, const int v_shift) {
      // MetaQuotes Moving Average EA compares the completed bar (rt[0]) to CopyBuffer(..., shift=0).
      // Because iMA() uses the MA shift internally (ma_shift), the indicator output is already offset.
      // For strict MT5 compatibility we MUST use MA buffer shift=0 while using bar shift=1 for prices.
      int ma_shift = v_shift;
      if(m_settings.MABenchmarkStrict)
         ma_shift = 0;

      double ma = GetMAVal(ma_handle, ma_shift, 0);
      if(ma == 0.0) return 0;

      double o = iOpen(m_symbol, PERIOD_CURRENT, v_shift);
      double c = iClose(m_symbol, PERIOD_CURRENT, v_shift);

      if(o < ma && c > ma) return 1;  // up-cross
      if(o > ma && c < ma) return -1; // down-cross
      return 0;
   }

   // === GetDirection: BEGIN ===
   int GetDirection() 
   {
      // Diagnostics reset (for Cockpit/UI)
      m_diag_last_bias   = 0;
      m_diag_last_votes  = 0;
      m_diag_last_reason = "";

      // 1. Check Filters First
      if(!CheckFilters()) return 0;

      // 1b. Master bias gate (BiasEnabled)
      if(!m_settings.BiasEnabled) { m_diag_last_reason="BIAS_DISABLED"; return 0; }

      // Use Vertical/Bar Shift from Settings (0 for current bar, 1 for closed bar)
      int v_shift = m_settings.ma_v_shift;
      
      // 2. Determine MASTER BIAS (Strategy)
      int bias = 0;
      
      if(m_settings.BiasMode == BIAS_MANUAL) {
         if(m_settings.ManSide == SIDE_LONG)
            bias = 1;
         else if(m_settings.ManSide == SIDE_SHORT)
            bias = -1;
         else
         {
            // RRM RULE: Market Bias is the master filter
            // LONG: Fast > Slow AND both EMAs rising
            // SHORT: Fast < Slow AND both EMAs falling
            // If neither condition met → bias = 0 (neutral/invalid, trade rejected)
             
            int hf = (m_settings.BiasFastID==0)?h_ema1 : (m_settings.BiasFastID==1)?h_ema2 : (m_settings.BiasFastID==2)?h_ema3 : h_ema4;
            int hs = (m_settings.BiasSlowID==0)?h_ema1 : (m_settings.BiasSlowID==1)?h_ema2 : (m_settings.BiasSlowID==2)?h_ema3 : h_ema4;
            
            // Get EMA values
            double f_curr = GetMAVal(hf, v_shift, 0);
            double f_prev = GetMAVal(hf, v_shift + 1, 0);
            double s_curr = GetMAVal(hs, v_shift, 0);
            double s_prev = GetMAVal(hs, v_shift + 1, 0);
             
            // Calculate slopes
            int fast_slope = (f_curr > f_prev) ? 1 : (f_curr < f_prev) ? -1 : 0;
            int slow_slope = (s_curr > s_prev) ? 1 : (s_curr < s_prev) ? -1 : 0;
             
            // === STEP 1: Determine Market Bias (Primary Filter) ===
            int market_bias = 0;
             
            // LONG: Fast > Slow AND both rising
            if(f_curr > s_curr && fast_slope == 1 && slow_slope == 1)
               market_bias = 1;
            // SHORT: Fast < Slow AND both falling
            else if(f_curr < s_curr && fast_slope == -1 && slow_slope == -1)
               market_bias = -1;
            // ELSE: Neither condition met → market_bias = 0 (invalid/neutral)
             
            // If no valid market bias, reject immediately
            if(market_bias == 0) {
               bias = 0;
            }
            else {
               // === STEP 2: Evaluate AutoStrat for Entry Signal ===
               int entry_signal = 0;
                
               if(m_settings.AutoStrat == STRAT_SINGLE_SLOPE) {
                  entry_signal = GetSlope(hf);
               }
               else if(m_settings.AutoStrat == STRAT_PRICE_CROSS) {
                  if(m_settings.RequirePriceCross) {
                     entry_signal = PriceCrossDirection(hf, v_shift);
                  } else {
                     double price = iClose(m_symbol, PERIOD_CURRENT, v_shift);
                     double ma    = GetMAVal(hf, v_shift, 0);
                     entry_signal = (price > ma) ? 1 : -1;
                  }
               }
               else {  // STRAT_PAIR_CROSS
                  // Check for EMA crossover
                  double f_curr_cross = GetMAVal(hf, v_shift, 0);
                  double f_prev_cross = GetMAVal(hf, v_shift + 1, 0);
                  double s_curr_cross = GetMAVal(hs, v_shift, 0);
                  double s_prev_cross = GetMAVal(hs, v_shift + 1, 0);
                   
                  // Bullish cross: fast was below, now above
                  if(f_prev_cross <= s_prev_cross && f_curr_cross > s_curr_cross)
                     entry_signal = 1;
                  // Bearish cross: fast was above, now below
                  else if(f_prev_cross >= s_prev_cross && f_curr_cross < s_curr_cross)
                     entry_signal = -1;
                  // No cross
                  else
                     entry_signal = 0;
               }
                
               // === STEP 3: Validate Entry Signal Against Market Bias ===
               // Entry signal must match market bias, otherwise reject
               if(entry_signal == market_bias)
                  bias = market_bias;
               else
                  bias = 0;
            }
         }
      }
      else {
         // RRM RULE: Market Bias is the master filter
         // LONG: Fast > Slow AND both EMAs rising
         // SHORT: Fast < Slow AND both EMAs falling
         // If neither condition met → bias = 0 (neutral/invalid, trade rejected)
         
         int hf = (m_settings.BiasFastID==0)?h_ema1 : (m_settings.BiasFastID==1)?h_ema2 : (m_settings.BiasFastID==2)?h_ema3 : h_ema4;
         int hs = (m_settings.BiasSlowID==0)?h_ema1 : (m_settings.BiasSlowID==1)?h_ema2 : (m_settings.BiasSlowID==2)?h_ema3 : h_ema4;
         
         // Get EMA values
         double f_curr = GetMAVal(hf, v_shift, 0);
         double f_prev = GetMAVal(hf, v_shift + 1, 0);
         double s_curr = GetMAVal(hs, v_shift, 0);
         double s_prev = GetMAVal(hs, v_shift + 1, 0);
         
         // Calculate slopes
         int fast_slope = (f_curr > f_prev) ? 1 : (f_curr < f_prev) ? -1 : 0;
         int slow_slope = (s_curr > s_prev) ? 1 : (s_curr < s_prev) ? -1 : 0;
         
         // === STEP 1: Determine Market Bias (Primary Filter) ===
         int market_bias = 0;
         
         // LONG: Fast > Slow AND both rising
         if(f_curr > s_curr && fast_slope == 1 && slow_slope == 1)
            market_bias = 1;
         // SHORT: Fast < Slow AND both falling
         else if(f_curr < s_curr && fast_slope == -1 && slow_slope == -1)
            market_bias = -1;
         // ELSE: Neither condition met → market_bias = 0 (invalid/neutral)
         
         // If no valid market bias, reject immediately
         if(market_bias == 0) {
            bias = 0;
         }
         else {
            // === STEP 2: Evaluate AutoStrat for Entry Signal ===
            int entry_signal = 0;
            
            if(m_settings.AutoStrat == STRAT_SINGLE_SLOPE) {
               entry_signal = GetSlope(hf);
            }
            else if(m_settings.AutoStrat == STRAT_PRICE_CROSS) {
               if(m_settings.RequirePriceCross) {
                  entry_signal = PriceCrossDirection(hf, v_shift);
               } else {
                  double price = iClose(m_symbol, PERIOD_CURRENT, v_shift);
                  double ma    = GetMAVal(hf, v_shift, 0);
                  entry_signal = (price > ma) ? 1 : -1;
               }
            }
            else {  // STRAT_PAIR_CROSS
               // Check for EMA crossover
               double f_curr_cross = GetMAVal(hf, v_shift, 0);
               double f_prev_cross = GetMAVal(hf, v_shift + 1, 0);
               double s_curr_cross = GetMAVal(hs, v_shift, 0);
               double s_prev_cross = GetMAVal(hs, v_shift + 1, 0);
               
               // Bullish cross: fast was below, now above
               if(f_prev_cross <= s_prev_cross && f_curr_cross > s_curr_cross)
                  entry_signal = 1;
               // Bearish cross: fast was above, now below
               else if(f_prev_cross >= s_prev_cross && f_curr_cross < s_curr_cross)
                  entry_signal = -1;
               // No cross
               else
                  entry_signal = 0;
            }
            
            // === STEP 3: Validate Entry Signal Against Market Bias ===
            // Entry signal must match market bias, otherwise reject
            if(entry_signal == market_bias)
               bias = market_bias;
            else
               bias = 0;
         }
      }
      
      m_diag_last_bias = bias;

      if(bias == 0) { m_diag_last_reason="BIAS_ZERO"; return 0; }

      // 3. HTF Filter Check
      if(m_settings.UseHTF) {
         double curr = GetMAVal(h_htf_ema, 1);
         double prev = GetMAVal(h_htf_ema, 2);
         int htf_dir = (curr > prev) ? 1 : -1;
         
         if(bias != htf_dir) { m_diag_last_reason="HTF_VETO"; return 0; }
      }


      // 3b. RRM mandatory gates (only active when enabled in settings)
      if(m_settings.RRM_RequirePullbackReclaim) {
         if(!Check_RRM_PullbackReclaim(bias)) { m_diag_last_reason="RRM_PULLBACK"; return 0; }
      }
      if(m_settings.RRM_RequireEmaDiv) {
         if(!Check_RRM_EmaDiv(bias)) { m_diag_last_reason="RRM_EMA_DIV"; return 0; }
      }

      // 4. VOTING BYPASS (Speed Mode)
      if(m_settings.VoteThreshold <= 1) { m_diag_last_votes=0; m_diag_last_reason="BYPASS"; return bias; }

      // 5. Voting Logic (Consensus)
      int votes = 0;
      
      if(m_settings.Use_EmaSig && Check_EMA1(bias, v_shift)) votes++;
      if(m_settings.Use_Adx    && Check_ADX(v_shift))      votes++;
      if(m_settings.Use_Macd   && Check_MACD(bias, v_shift)) votes++;
      if(m_settings.Use_Rsi    && Check_RSI(bias, v_shift))  votes++;
      if(m_settings.Use_Cci    && Check_CCI(bias, v_shift))  votes++;
      if(m_settings.Use_Mfi    && Check_MFI(bias, v_shift))  votes++;
      if(m_settings.Use_Sto    && Check_Sto(bias, v_shift))  votes++;
      if(m_settings.Use_Bb     && Check_BB(bias, v_shift))   votes++;
      if(m_settings.Use_Psar   && Check_PSAR(bias, v_shift)) votes++;
      if(m_settings.Use_P123   && Check_P123(bias, v_shift)) votes++;
      if(m_settings.Use_Ross   && Check_Ross(bias, v_shift)) votes++;
      
      // Volatility regime vote (soft)
      if(m_settings.Use_ATRVote)
      {
         // m_diag_last_atr_ok is computed in CheckFilters().
         if(m_diag_last_atr_ok) votes++;
      }

      // Final Decision
      m_diag_last_votes = votes;


      // ===== DIAGNOSTIC LOGGING FOR VOTE ANALYSIS: BEGUN =====
      #ifdef __MQL5__
      if(MQLInfoInteger(MQL_TESTER)) {
         datetime bar_time = iTime(m_symbol, PERIOD_CURRENT, v_shift);
         string vote_details = StringFormat("VOTE_DETAIL[%s]: bias=%d v_shift=%d votes=%d/%d",
                                            TimeToString(bar_time),
                                            bias, v_shift, votes, m_settings.VoteThreshold);
         
         // Log each enabled vote with actual indicator values
         if(m_settings.Use_EmaSig) {
            double p = iClose(m_symbol, PERIOD_CURRENT, v_shift);
            double e = GetMAVal(h_ema1, v_shift);
            bool pass = Check_EMA1(bias, v_shift);
            vote_details += StringFormat(" | EMA1: p=%.5f e=%.5f %s", p, e, pass?"PASS":"FAIL");
         }
         
         if(m_settings.Use_Adx) {
            double adx = GetVal(h_adx, v_shift);
            bool pass = Check_ADX(v_shift);
            vote_details += StringFormat(" | ADX: %.2f %s", adx, pass?"PASS":"FAIL");
         }
         
         if(m_settings.Use_Macd) {
            double m = GetVal(h_macd, v_shift, 0);
            double s = GetVal(h_macd, v_shift, 1);
            bool pass = Check_MACD(bias, v_shift);
            vote_details += StringFormat(" | MACD: main=%.6f sig=%.6f %s", m, s, pass?"PASS":"FAIL");
         }
         
         if(m_settings.Use_Rsi) {
            double r = GetVal(h_rsi, v_shift);
            bool pass = Check_RSI(bias, v_shift);
            vote_details += StringFormat(" | RSI: %.2f %s", r, pass?"PASS":"FAIL");
         }
         
         if(m_settings.Use_Cci) {
            double c = GetVal(h_cci, v_shift);
            bool pass = Check_CCI(bias, v_shift);
            vote_details += StringFormat(" | CCI: %.2f %s", c, pass?"PASS":"FAIL");
         }
         
         if(m_settings.Use_Mfi) {
            double mfi = GetVal(h_mfi, v_shift);
            bool pass = Check_MFI(bias, v_shift);
            vote_details += StringFormat(" | MFI: %.2f %s", mfi, pass?"PASS":"FAIL");
         }
         
         if(m_settings.Use_Sto) {
            double k = GetVal(h_sto, v_shift, 0);
            double d = GetVal(h_sto, v_shift, 1);
            bool pass = Check_Sto(bias, v_shift);
            vote_details += StringFormat(" | STO: k=%.2f d=%.2f %s", k, d, pass?"PASS":"FAIL");
         }
         
         if(m_settings.Use_Bb) {
            double mid = GetVal(h_bb, v_shift, 0);
            double cl = iClose(m_symbol, PERIOD_CURRENT, v_shift);
            bool pass = Check_BB(bias, v_shift);
            vote_details += StringFormat(" | BB: mid=%.5f cl=%.5f %s", mid, cl, pass?"PASS":"FAIL");
         }
         
         if(m_settings.Use_Psar) {
            double p = GetVal(h_psar, v_shift);
            double cl = iClose(m_symbol, PERIOD_CURRENT, v_shift);
            bool pass = Check_PSAR(bias, v_shift);
            vote_details += StringFormat(" | PSAR: sar=%.5f cl=%.5f %s", p, cl, pass?"PASS":"FAIL");
         }
         
         if(m_settings.Use_P123) {
            bool pass = Check_P123(bias, v_shift);
            vote_details += StringFormat(" | P123: %s", pass?"PASS":"FAIL");
         }
         
         if(m_settings.Use_Ross) {
            bool pass = Check_Ross(bias, v_shift);
            vote_details += StringFormat(" | ROSS: %s", pass?"PASS":"FAIL");
         }
         
         Print(vote_details);
      }
      #endif
      // ===== DIAGNOSTIC LOGGING FOR VOTE ANALYSIS: END =====


      if(votes >= m_settings.VoteThreshold) { m_diag_last_reason="OK"; return bias; }
      
      m_diag_last_reason = StringFormat("VOTES %d/%d", votes, m_settings.VoteThreshold);
      return 0; // Not enough consensus

   } // === GetDirection: END ===


   // --- RRM (Trend Pullback) helper checks ---
   int BiasFastHandle() {
      return (m_settings.BiasFastID==0)?h_ema1 : (m_settings.BiasFastID==1)?h_ema2 : (m_settings.BiasFastID==2)?h_ema3 : h_ema4;
   }

   int BiasSlowHandle() {
      return (m_settings.BiasSlowID==0)?h_ema1 : (m_settings.BiasSlowID==1)?h_ema2 : (m_settings.BiasSlowID==2)?h_ema3 : h_ema4;
   }

   // Pullback/Reclaim trigger:
   // Long: bar[2] closes BELOW fast EMA, then bar[1] closes ABOVE fast EMA.
   // Short: bar[2] closes ABOVE fast EMA, then bar[1] closes BELOW fast EMA.
   bool Check_RRM_PullbackReclaim(const int bias) {
      int hf = BiasFastHandle();
      double ema2 = GetMAVal(hf, 2);
      double ema1 = GetMAVal(hf, 1);
      double c2   = iClose(m_symbol, PERIOD_CURRENT, 2);
      double c1   = iClose(m_symbol, PERIOD_CURRENT, 1);

      if(bias > 0) return (c2 < ema2 && c1 > ema1);
      else         return (c2 > ema2 && c1 < ema1);
   }

   // Convergence->divergence (simple, bar-close stable):
   // Require the EMA distance to start expanding in the bias direction after a recent contraction.
   bool Check_RRM_EmaDiv(const int bias) {
      int hf = BiasFastHandle();
      int hs = BiasSlowHandle();

      double f1 = GetMAVal(hf, 1);
      double s1 = GetMAVal(hs, 1);
      double f2 = GetMAVal(hf, 2);
      double s2 = GetMAVal(hs, 2);

      double dist1 = MathAbs(f1 - s1);
      double dist2 = MathAbs(f2 - s2);

      // Must be diverging now (distance increasing) by at least MinDivPips
      int digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
      double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      double pip = (digits==3 || digits==5) ? (point*10.0) : point;
      double min_div = m_settings.RRM_MinDivPips * pip;
      if((dist1 - dist2) < min_div) return false;

      // Optional: ensure there was a contraction within lookback
      int look = m_settings.RRM_Lookback;
      if(look < 2) look = 2;
      double minDist = dist2;
      for(int i=2; i<=look+1; i++) {
         double fi = GetMAVal(hf, i);
         double si = GetMAVal(hs, i);
         double di = MathAbs(fi - si);
         if(di < minDist) minDist = di;
      }
      // Contraction means prior minDist is not greater than dist2 (we were 'tighter' recently)
      if(minDist > dist2) return false;

      // Bias direction must match fast-vs-slow ordering
      if(bias > 0) return (f1 > s1);
      else         return (f1 < s1);
   }

   // --- UTILS ---
   int GetSlope(int handle) {
      // In this EA, slope checks are currently only used on MA handles.
      double c = GetMAVal(handle, 1);
      double p = GetMAVal(handle, 2);
      return (c > p) ? 1 : (c < p) ? -1 : 0;
   }

   // Expose primary MA handle (EMA1/SMA1) for chart attachment (benchmark visualization)
   int GetPrimaryMAHandle() const { return h_ema1; }
};

//+--END OF SEA_SignalEngine.mqh--+