//+------------------------------------------------------------------+
//|                                             SEA_SignalEngine.mqh |
//|                              MJS Institutional Trading Solutions |
//|                                                                  |
//| Purpose: Signal Logic, Indicator Management, Voting & Filters    |
//| Status:  PRODUCTION READY (Revision M: Full Dual Shift Support)  |
//| TASK1 OPT: Added MaxATR upper volatility bound                   |
//+------------------------------------------------------------------+
// SAVE AS UTF-16 LE WITH BOM
//+------------------------------------------------------------------+
// PURPOSE:
// Core signal processing engine implementing 9-step pipeline for trade signals
//
// SIGNAL PROCESSING PIPELINE:
// Step 1: PRE-FILTERS - Check spread, ATR, time filters
// Step 2: MARKET BIAS - Determine trend direction (LONG/SHORT/NEUTRAL)
// Step 3: AUTOSTRAT SIGNAL - Generate entry timing signal
// Step 4: SIGNAL VALIDATION - Verify signal matches bias
// Step 5: HTF FILTER - Check higher timeframe alignment
// Step 6: RRM GATES - Optional pullback/divergence checks
// Step 7: VOTING BYPASS - Check if voting required
// Step 8: INDICATOR VOTING - Get indicator consensus
// Step 9: FINAL DECISION - Accept or reject trade
//
// KEY CONCEPTS:
// - Market Bias: Primary trend filter (EMA position + slope)
// - Entry Signal: Timing signal within bias context
// - Voting: Indicators confirm or reject the bias
// - RRM Gates: Optional quality filters (pullback, divergence)
//
// RETURN VALUES:
// GetDirection() returns: 1 (LONG), -1 (SHORT), 0 (NO TRADE)
//
// See README.md for complete documentation
//+------------------------------------------------------------------+

#property strict

// --- Anti-stale build lock (MQL5-safe: no #if, no #error)
#ifndef SEA_BUILD_TOKEN_103001
enum { __SEA_BUILD_TOKEN_MISSING_SIGNALENGINE_103001 = SEA_BUILD_TOKEN_103001 };
#endif

#define SEA_MOD_SIGNALENGINE_103001 1


#include <RRMS\SEA_Config.mqh>


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

   // 260304_PR1: Phase Detection Diagnostics
   EMarketPhase m_diag_last_phase;       // Last detected market phase
   int          m_diag_phase_confirm_bars; // Number of consecutive bars in current phase

   // 260304_PR3: Layer Detection Diagnostics
   EEntryLayer  m_diag_last_layer;       // Last detected entry layer
   double       m_diag_layer_distance;   // Distance to nearest EMA layer in pips

   EEntryLayer  m_diag_last_entry_layer;  // 260304_PR4: Last detected entry layer
   bool         m_layer_allowed;          // 260304_PR7: Whether current entry layer is allowed in current phase

   // --- 2c. STRUCTURE GATE DIAGNOSTICS ---
   int         m_active_layer;       // Active EMA layer (1/2/3/0=none)
   bool        m_pullback_found;     // Was a pullback detected?
   int         m_pullback_bar;       // Bar index of pullback extreme
   double      m_pullback_extreme;   // Price at pullback extreme
   bool        m_recovery_detected;  // Was recovery detected?

   // --- 2d. REJECTION STATISTICS ---
   int         m_bars_evaluated;     // Total bars evaluated by GetDirection()
   int         m_signals_generated;  // Signals returned (TS != 0)
   int         m_reject_filter;      // Rejections at pre-filter step (spread, ATR, time, news)
   int         m_reject_bias;        // Rejections at bias step (no trend, signal mismatch)
   int         m_reject_gate;        // Rejections at gate step (HTF, RRM, structure gates)
   int         m_reject_votes;       // Rejections at vote step

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
   
   // Vote 3: MACD — two-tier architecture (base mode + optional filters)
   //
   // MACD Indicator buffer outputs:
   //   Buffer 0 = MACD Main Line (fast EMA - slow EMA)
   //   Buffer 1 = MACD Signal Line (SMA of Main Line)
   //   Buffer 2 = MACD Histogram (Main - Signal)
   //
   bool Check_MACD(int bias, int shift) {
      if(!m_settings.Ind_Macd_Enabled) return false;

      double m = GetVal(h_macd, shift, 0);  // Main line
      double s = GetVal(h_macd, shift, 1);  // Signal line
      double h = m - s;                      // Histogram

      // ══════════════════════════════════════════════════════════
      // STEP 1: Base Mode Check
      // ══════════════════════════════════════════════════════════
      bool base_pass = false;

      switch(m_settings.MacdVoteMode) {
         case MACD_ZERO_LINE:
            base_pass = (bias == 1) ? (m > 0) : (m < 0);
            break;

         case MACD_HISTOGRAM:
            base_pass = (bias == 1) ? (h > 0) : (h < 0);
            break;

         case MACD_CROSSOVER:
            base_pass = (bias == 1) ? (m > s) : (m < s);
            break;

         case MACD_ZERO_AND_CROSS:  // RRM default (industry "traditional")
            base_pass = (bias == 1) ? (m > 0 && m > s) : (m < 0 && m < s);
            break;

         case MACD_ZERO_AND_HIST:
            base_pass = (bias == 1) ? (m > 0 && h > 0) : (m < 0 && h < 0);
            break;

         case MACD_TRIPLE:
            base_pass = (bias == 1) ? (m > 0 && m > s && h > 0) :
                                      (m < 0 && m < s && h < 0);
            break;

         case MACD_CROSSOVER_N: {
            int bars_since = GetBarsSinceMACDCrossover(bias, shift);
            base_pass = (bars_since >= 0 && bars_since <= m_settings.MacdFreshBars);
            break;
         }

         case MACD_ZERO_CROSS_N: {
            int bars_since_zero = GetBarsSinceMACDZeroCross(bias, shift);
            base_pass = (bars_since_zero >= 0 && bars_since_zero <= m_settings.MacdFreshBars);
            break;
         }
      }

      if(!base_pass) return false;

      // ══════════════════════════════════════════════════════════
      // STEP 2: Advanced Filters (optional add-ons)
      // ══════════════════════════════════════════════════════════

      // Filter A: Slope (MACD accelerating)
      if(m_settings.MacdRequireSlope) {
         double m_prev = GetVal(h_macd, shift + 1, 0);
         double slope  = m - m_prev;

         // Check minimum slope threshold (if configured)
         if(m_settings.MacdSlopeMin > 0 && MathAbs(slope) < m_settings.MacdSlopeMin)
            return false;

         // Check direction matches bias
         bool accelerating = (bias == 1) ? (slope > 0) : (slope < 0);
         if(!accelerating) return false;
      }

      // Filter B: Divergence (price vs MACD disagreement)
      if(m_settings.MacdRequireDivergence) {
         if(!CheckMACDDivergence(bias, shift)) return false;
      }

      // Filter C: Hook (histogram reversal)
      if(m_settings.MacdRequireHook) {
         double h_prev = GetVal(h_macd, shift + 1, 0) - GetVal(h_macd, shift + 1, 1);
         bool hook = (bias == 1) ? (h > 0 && h_prev <= 0) : (h < 0 && h_prev >= 0);
         if(!hook) return false;
      }

      return true;  // Base + all filters passed
   }

   // Helper: Detect bars since MACD main/signal crossover
   int GetBarsSinceMACDCrossover(int bias, int shift) {
      static const int MACD_EVENT_LOOKBACK = 20;  // Max bars to look back for a recent MACD event
      for(int i = shift; i < shift + MACD_EVENT_LOOKBACK; i++) {
         double m_curr = GetVal(h_macd, i,     0);
         double s_curr = GetVal(h_macd, i,     1);
         double m_prev = GetVal(h_macd, i + 1, 0);
         double s_prev = GetVal(h_macd, i + 1, 1);

         // Bullish crossover: main crosses above signal
         if(bias == 1 && m_prev <= s_prev && m_curr > s_curr)
            return (i - shift);

         // Bearish crossover: main crosses below signal
         if(bias == -1 && m_prev >= s_prev && m_curr < s_curr)
            return (i - shift);
      }
      return -1;  // No recent crossover found
   }

   // Helper: Detect bars since MACD zero line cross
   int GetBarsSinceMACDZeroCross(int bias, int shift) {
      static const int MACD_EVENT_LOOKBACK = 20;  // Max bars to look back for a recent MACD event
      for(int i = shift; i < shift + MACD_EVENT_LOOKBACK; i++) {
         double m_curr = GetVal(h_macd, i,     0);
         double m_prev = GetVal(h_macd, i + 1, 0);

         // Bullish: crosses above zero
         if(bias == 1 && m_prev <= 0 && m_curr > 0)
            return (i - shift);

         // Bearish: crosses below zero
         if(bias == -1 && m_prev >= 0 && m_curr < 0)
            return (i - shift);
      }
      return -1;  // No recent zero cross
   }

   // Helper: Check for bullish/bearish divergence
   bool CheckMACDDivergence(int bias, int shift) {
      // Simple divergence check using two non-overlapping 10-bar windows
      // Bullish divergence: price makes lower low, MACD makes higher low
      // Bearish divergence: price makes higher high, MACD makes lower high

      if(shift + 20 >= Bars(m_symbol, PERIOD_CURRENT)) return false;

      if(bias == 1) {
         // Recent swing low (bars shift..shift+9) vs prior swing low (bars shift+10..shift+19)
         int price_low_idx  = iLowest(m_symbol, PERIOD_CURRENT, MODE_LOW, 10, shift);
         int price_low_idx2 = iLowest(m_symbol, PERIOD_CURRENT, MODE_LOW, 10, shift + 10);
         double price_low_curr = iLow(m_symbol, PERIOD_CURRENT, price_low_idx);
         double price_low_prev = iLow(m_symbol, PERIOD_CURRENT, price_low_idx2);
         double macd_low_curr  = GetVal(h_macd, price_low_idx,  0);
         double macd_low_prev  = GetVal(h_macd, price_low_idx2, 0);

         // Bullish divergence: price lower low, MACD higher low
         return (price_low_curr < price_low_prev && macd_low_curr > macd_low_prev);
      }
      else {
         // Recent swing high (bars shift..shift+9) vs prior swing high (bars shift+10..shift+19)
         int price_high_idx  = iHighest(m_symbol, PERIOD_CURRENT, MODE_HIGH, 10, shift);
         int price_high_idx2 = iHighest(m_symbol, PERIOD_CURRENT, MODE_HIGH, 10, shift + 10);
         double price_high_curr = iHigh(m_symbol, PERIOD_CURRENT, price_high_idx);
         double price_high_prev = iHigh(m_symbol, PERIOD_CURRENT, price_high_idx2);
         double macd_high_curr  = GetVal(h_macd, price_high_idx,  0);
         double macd_high_prev  = GetVal(h_macd, price_high_idx2, 0);

         // Bearish divergence: price higher high, MACD lower high
         return (price_high_curr > price_high_prev && macd_high_curr < macd_high_prev);
      }
   }

   // Mode description: returns human-readable string for active MACD configuration
   string GetMACDModeDescription()
   {
      return ::GetMACDModeDescription(
         m_settings.MacdVoteMode,
         m_settings.MacdRequireSlope,
         m_settings.MacdRequireDivergence,
         m_settings.MacdRequireHook
      );
   }


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
      return (bias==1) ? (m > m_settings.T_MfiOB) : (m < m_settings.T_MfiOS);
   }
   
   // Vote 7: Stochastic
   bool Check_Sto(int bias, int shift) {
      double k = GetVal(h_sto, shift, 0);
      double d = GetVal(h_sto, shift, 1);
      
      if(m_settings.StoMode == STO_CROSS_SIGNAL) 
         return (bias==1) ? (k > d) : (k < d);
         
      // Zone Filter: Buy if NOT overbought
      return (bias==1) ? (k < m_settings.T_StoOB) : (k > m_settings.T_StoOS);
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
   
   // Vote 9: PSAR (basic price vs. PSAR position check)
   bool Check_PSAR(int bias, int shift) {
      double p = GetVal(h_psar, shift);
      double cl = iClose(m_symbol, PERIOD_CURRENT, shift);
      return (bias==1) ? (cl > p) : (cl < p);
   }

   // PSAR helper: count direction-changes (flips) in the PSAR signal over a lookback window.
   // A flip occurs when PSAR switches from above price to below price (or vice-versa).
   // Returns the number of such flips in bars [lookback..1] (bar 0 is forming, excluded).
   int CountPSARFlips(int lookback = 3) {
      if(lookback < 3) return 0;

      double psar0 = GetVal(h_psar, lookback);
      double cl0   = iClose(m_symbol, PERIOD_CURRENT, lookback);
      if(psar0 == 0.0 || cl0 == 0.0) return 0;
      bool prev_bullish = (cl0 > psar0);

      int flips = 0;
      for(int i = lookback - 1; i >= 1; i--)
      {
         double psar_i = GetVal(h_psar, i);
         double cl_i   = iClose(m_symbol, PERIOD_CURRENT, i);
         if(psar_i == 0.0 || cl_i == 0.0) continue;
         bool curr_bullish = (cl_i > psar_i);
         if(curr_bullish != prev_bullish) flips++;
         prev_bullish = curr_bullish;
      }
      return flips;
   }

   // Vote 9 (enhanced): PSAR with flip-count validation.
   // Requires basic PSAR position check AND a recent trend change (1–2 flips in the
   // lookback window) to confirm the signal reflects a genuine fresh reversal rather
   // than a stale or choppy market condition.  Mirrors the Python system's logic.
   bool Check_PSAR_WithFlip(int bias, int shift) {
      // Basic direction check first
      if(!Check_PSAR(bias, shift)) return false;

      // Require 1 or 2 flips in the most recent 3 bars (fresh reversal):
      //   0 flips = stale trend (PSAR hasn't changed sides recently)
      //   3+ flips = choppy/oscillating (unreliable signal)
      int flips = CountPSARFlips(3);
      if(flips < 1 || flips > 2)
      {
         m_diag_last_reason = StringFormat("PSAR_FLIP_COUNT_INVALID(%d)", flips);
         return false;
      }
      return true;
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

   // --- ADAPTIVE GATE SCALING HELPERS ---

   double GetAdaptivePullbackPips(ENUM_TIMEFRAMES tf, string symbol)
   {
      bool is_jpy = (StringFind(symbol, "JPY") >= 0);
      double base = 0;
      switch(tf)
      {
         case PERIOD_M1:  base = 2.0;  break;
         case PERIOD_M5:  base = 5.0;  break;
         case PERIOD_M15: base = 8.0;  break;
         case PERIOD_H1:  base = 15.0; break;
         case PERIOD_H4:  base = 30.0; break;
         case PERIOD_D1:  base = 60.0; break;
         default:         base = 10.0;
      }
      if(is_jpy) base *= 100.0;
      return base;
   }

   // --- HARD GATES ---

   //+------------------------------------------------------------------+
   //| Detect which EMA layer is currently valid and active             |
   //| Returns: 1=Layer1(EMA1-2), 2=Layer2(EMA2-3), 3=Layer3(EMA3-4), 0=none |
   //| Selection: layers checked shallow-first (1→2→3); first valid    |
   //| layer returned. Each layer is validated independently — a broken |
   //| shallow layer does not prevent a deeper layer from being active. |
   //+------------------------------------------------------------------+
   int DetectActiveLayer(const int bias)
   {
      double e1    = GetMAVal(h_ema1, 1);
      double e2    = GetMAVal(h_ema2, 1);
      double e3    = GetMAVal(h_ema3, 1);
      double e4    = GetMAVal(h_ema4, 1);
      double price = iClose(m_symbol, PERIOD_CURRENT, 1);

      if(bias == -1) {  // SHORT: faster EMA must be below slower EMA (downtrend aligned)
         if(e1 < e2 && price <= e2) return 1;  // Layer 1 valid: EMA1-2 aligned, price within range
         if(e2 < e3 && price <= e3) return 2;  // Layer 2 valid: EMA2-3 aligned, price within range
         if(e3 < e4 && price <= e4) return 3;  // Layer 3 valid: EMA3-4 aligned, price within range
      }
      else {            // LONG: faster EMA must be above slower EMA (uptrend aligned)
         if(e1 > e2 && price >= e2) return 1;  // Layer 1 valid: EMA1-2 aligned, price within range
         if(e2 > e3 && price >= e3) return 2;  // Layer 2 valid: EMA2-3 aligned, price within range
         if(e3 > e4 && price >= e4) return 3;  // Layer 3 valid: EMA3-4 aligned, price within range
      }
      return 0;
   }

   // HARD GATE 1: Dynamic structure-based pullback detection (no pip thresholds)
   // Single-layer: 5-level check (1) current reclaimed, (2) pullback found, (3) prior trend,
   //               (4) optional momentum, (5) comprehensive logging
   // Multi-layer:  Recovery-based detection — (1) EMA-alignment layer selection, (2) pullback extreme,
   //               (3) recovery started, (4) optional momentum, (5) layer intact at extreme
   bool Check_Gate_DynamicPullback(const int bias)
   {
      if(!m_settings.RequirePullback) return true;

      // Reset structure diagnostics
      m_active_layer      = 0;
      m_pullback_found    = false;
      m_pullback_bar      = 0;
      m_pullback_extreme  = 0.0;
      m_recovery_detected = false;

      int lookback = m_settings.PullbackLookback;

      // === MULTI-LAYER MODE (RRM standard) ===
      if(m_settings.Gate_UseMultiLayer)
      {
         // Step 1: Determine active layer by EMA alignment only (no price-position requirement).
         // This allows recovery detection even when price is still in the pullback zone.
         double e1 = GetMAVal(h_ema1, 1);
         double e2 = GetMAVal(h_ema2, 1);
         double e3 = GetMAVal(h_ema3, 1);
         double e4 = GetMAVal(h_ema4, 1);

         int    active_layer = 0;
         int    fast_handle  = INVALID_HANDLE, slow_handle = INVALID_HANDLE;
         string layer_name   = "";
         int    fast_period  = 0, slow_period = 0;

         if(bias == -1)  // SHORT: fast EMA must be below slow EMA
         {
            if(e1 < e2)      { active_layer = 1; fast_handle = h_ema1; slow_handle = h_ema2; layer_name = "EMA1-EMA2"; fast_period = m_settings.P_Ema1; slow_period = m_settings.P_Ema2; }
            else if(e2 < e3) { active_layer = 2; fast_handle = h_ema2; slow_handle = h_ema3; layer_name = "EMA2-EMA3"; fast_period = m_settings.P_Ema2; slow_period = m_settings.P_Ema3; }
            else if(e3 < e4) { active_layer = 3; fast_handle = h_ema3; slow_handle = h_ema4; layer_name = "EMA3-EMA4"; fast_period = m_settings.P_Ema3; slow_period = m_settings.P_Ema4; }
         }
         else             // LONG: fast EMA must be above slow EMA
         {
            if(e1 > e2)      { active_layer = 1; fast_handle = h_ema1; slow_handle = h_ema2; layer_name = "EMA1-EMA2"; fast_period = m_settings.P_Ema1; slow_period = m_settings.P_Ema2; }
            else if(e2 > e3) { active_layer = 2; fast_handle = h_ema2; slow_handle = h_ema3; layer_name = "EMA2-EMA3"; fast_period = m_settings.P_Ema2; slow_period = m_settings.P_Ema3; }
            else if(e3 > e4) { active_layer = 3; fast_handle = h_ema3; slow_handle = h_ema4; layer_name = "EMA3-EMA4"; fast_period = m_settings.P_Ema3; slow_period = m_settings.P_Ema4; }
         }

         m_active_layer = active_layer;

         if(active_layer == 0)
         {
            m_diag_last_reason = "DYN_PB_NO_VALID_LAYER";
            if(m_settings.DebugFlow)
               Print("DYN_PULLBACK: No valid EMA layer (all layers broken) → REJECT");
            return false;
         }

         // Step 2: Find pullback extreme — bar in [2..lookback] with most price movement against bias
         int    extreme_bar   = -1;
         double extreme_price = 0;

         for(int i = 2; i <= lookback; i++)
         {
            if(bias == -1)  // SHORT: pullback is price rising — find highest high
            {
               double hi = iHigh(m_symbol, PERIOD_CURRENT, i);
               if(extreme_bar == -1 || hi > extreme_price) { extreme_bar = i; extreme_price = hi; }
            }
            else            // LONG: pullback is price falling — find lowest low
            {
               double lo = iLow(m_symbol, PERIOD_CURRENT, i);
               if(extreme_bar == -1 || lo < extreme_price) { extreme_bar = i; extreme_price = lo; }
            }
         }

         if(extreme_bar == -1)
         {
            m_diag_last_reason = "DYN_PB_NOT_FOUND_" + layer_name;
            return false;
         }

         m_pullback_found   = true;
         m_pullback_bar     = extreme_bar;
         m_pullback_extreme = extreme_price;

         // Step 3: Verify recovery started — current bar has moved back from pullback extreme
         double curr_close       = iClose(m_symbol, PERIOD_CURRENT, 1);
         bool   recovery_started = (bias == -1) ? (curr_close < extreme_price) : (curr_close > extreme_price);
         m_recovery_detected = recovery_started;
         if(!recovery_started)
         {
            m_diag_last_reason = "DYN_PB_NO_RECOVERY_" + layer_name;
            return false;
         }

         // Step 4: Optional momentum — current candle closes in bias direction
         if(m_settings.RequireRecoveryMomentum)
         {
            double bar1_open    = iOpen(m_symbol, PERIOD_CURRENT, 1);
            bool   has_momentum = (bias == 1) ? (curr_close > bar1_open) : (curr_close < bar1_open);
            if(!has_momentum)
            {
               m_diag_last_reason = "DYN_PB_NO_MOMENTUM_" + layer_name;
               return false;
            }
         }

         // Step 5: Validate layer intact at extreme bar (EMAs still aligned at pullback peak)
         double fast_at_extreme = GetMAVal(fast_handle, extreme_bar);
         double slow_at_extreme = GetMAVal(slow_handle, extreme_bar);
         bool   layer_intact    = (bias == 1) ? (fast_at_extreme > slow_at_extreme) : (fast_at_extreme < slow_at_extreme);
         if(!layer_intact)
         {
            m_diag_last_reason = "DYN_PB_LAYER_BROKEN_" + layer_name;
            return false;
         }

         if(m_settings.DebugFlow)
            PrintFormat("DYN_PULLBACK[bias=%d]: Layer%d (%s: %d-%d periods) extreme_bar=%d recovery=YES layer_intact=YES → PASS",
                        bias, active_layer, layer_name, fast_period, slow_period, extreme_bar);

         return true;
      }

      // === SINGLE-LAYER MODE (fallback for other presets) ===
      int hf = BiasFastHandle();

      // Level 1: Current bar is with the trend (price has reclaimed the EMA)
      double ema1   = GetMAVal(hf, 1);
      double close1 = iClose(m_symbol, PERIOD_CURRENT, 1);
      bool reclaimed = (bias == 1) ? (close1 > ema1) : (close1 < ema1);
      if(!reclaimed)
      {
         m_diag_last_reason = "DYN_PB_NOT_RECLAIMED";
         return false;
      }

      // Level 2: Pullback found — any bar in lookback window touched the EMA
      int pb_bar = 0;
      for(int i = 2; i <= lookback + 1; i++)
      {
         double ema  = GetMAVal(hf, i);
         double low  = iLow(m_symbol,  PERIOD_CURRENT, i);
         double high = iHigh(m_symbol, PERIOD_CURRENT, i);
         if(bias == 1  && low  <= ema) { pb_bar = i; break; }
         if(bias == -1 && high >= ema) { pb_bar = i; break; }
      }
      if(pb_bar == 0)
      {
         m_diag_last_reason = "DYN_PB_NOT_FOUND";
         return false;
      }

      m_pullback_found   = true;
      m_pullback_bar     = pb_bar;
      m_pullback_extreme = (bias == 1) ? iLow(m_symbol, PERIOD_CURRENT, pb_bar) : iHigh(m_symbol, PERIOD_CURRENT, pb_bar);
      m_recovery_detected = true; // reclaimed = recovery confirmed in single-layer mode

      // Level 3: Prior trend verified — EMA was sloping with trend before pullback
      double ema_pb   = GetMAVal(hf, pb_bar);
      double ema_prev = GetMAVal(hf, pb_bar + 1);
      bool prior_trend = (bias == 1) ? (ema_pb >= ema_prev) : (ema_pb <= ema_prev);
      if(!prior_trend)
      {
         m_diag_last_reason = "DYN_PB_NO_PRIOR_TREND";
         return false;
      }

      // Level 4: Optional momentum — recovery bar closes in trend direction
      if(m_settings.RequireRecoveryMomentum)
      {
         double open1 = iOpen(m_symbol, PERIOD_CURRENT, 1);
         bool momentum = (bias == 1) ? (close1 > open1) : (close1 < open1);
         if(!momentum)
         {
            m_diag_last_reason = "DYN_PB_NO_MOMENTUM";
            return false;
         }
      }

      // Level 5: Log structure found
      if(m_settings.DebugFlow)
         PrintFormat("DYN_PULLBACK[bias=%d]: reclaimed=YES pb_bar=%d prior_trend=YES%s → PASS",
                     bias, pb_bar,
                     m_settings.RequireRecoveryMomentum ? " momentum=YES" : "");

      return true;
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
   // Expose primary MA handle (EMA1/SMA1) for chart attachment (benchmark visualization)
   int GetPrimaryMAHandle() const { return h_ema1; }
   int GetPsarHandle() const { return h_psar; }
   int GetMacdHandle() const { return h_macd; }
   int GetRsiHandle() const { return h_rsi; }       // ADD THIS
   int GetCciHandle() const { return h_cci; }       // ADD THIS
   int GetMfiHandle() const { return h_mfi; }       // ADD THIS
   int GetStoHandle() const { return h_sto; }       // ADD THIS
   int GetAdxHandle() const { return h_adx; }       // ADD THIS
   int GetBbHandle() const { return h_bb; }         // ADD THIS
   int GetHtfEmaHandle() const { return h_htf_ema; }// ADD THIS
   int GetFractalHandle() const { return h_fractals; } // ADD THIS
   
   // Pattern indicators (return INVALID_HANDLE if not implemented yet)
   int GetP123Handle() const { return INVALID_HANDLE; } // TODO: Implement when P123 indicator ready
   int GetRossHandle() const { return INVALID_HANDLE; } // TODO: Implement when Ross Hook ready

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

      // 260304_PR1: Initialize phase diagnostics
      m_diag_last_phase = PHASE_UNORDERED;
      m_diag_phase_confirm_bars = 0;

      // 260304_PR3: Initialize layer diagnostics
      m_diag_last_layer = LAYER_NONE;
      m_diag_layer_distance = 0.0;

      // 260304_PR4: Initialize entry layer diagnostic
      m_diag_last_entry_layer = LAYER_NONE;

      // 260304_PR7: Initialize layer-allowed diagnostic
      m_layer_allowed = false;

      m_active_layer      = 0;
      m_pullback_found    = false;
      m_pullback_bar      = 0;
      m_pullback_extreme  = 0.0;
      m_recovery_detected = false;

      m_bars_evaluated    = 0;
      m_signals_generated = 0;
      m_reject_filter     = 0;
      m_reject_bias       = 0;
      m_reject_gate       = 0;
      m_reject_votes      = 0;
   }

   // --- DIAGNOSTIC GETTERS (for Cockpit/UI) ---
   int    LastBias()   const { return m_diag_last_bias; }
   int    LastVotes()  const { return m_diag_last_votes; }
   string LastReason() const { return m_diag_last_reason; }

   // 260304_PR1: Phase Detection Diagnostics
   EMarketPhase GetLastDetectedPhase() const { return m_diag_last_phase; }
   int          GetPhaseConfirmBars() const { return m_diag_phase_confirm_bars; }

   // 260304_PR3: Layer Detection Diagnostics
   EEntryLayer  GetLastDetectedLayer() const { return m_diag_last_layer; }

   // 260304_PR7: Entry layer and phase-filter diagnostics for UI
   EEntryLayer  GetLastEntryLayer()    const { return m_diag_last_entry_layer; }
   bool         GetLayerAllowed()      const { return m_layer_allowed; }

   // Returns true if the given entry layer is permitted in the given phase.
   // Requires PhaseDetectionEnabled AND EnableLayerDetection to activate filtering.
   // Filtering rules (260304_PR5 methodology):
   //   UNORDERED  -> no layers allowed (choppy market)
   //   EMERGING   -> L1 (WEAK) and L2 (MEDIUM) allowed; L3 (STRONG) blocked
   //   TRENDING   -> all layers allowed (strong established trend)
   bool IsLayerAllowed(EEntryLayer layer, EMarketPhase phase) const
   {
      if(!m_settings.PhaseDetectionEnabled || !m_settings.EnableLayerDetection)
         return true;  // Filtering disabled - all layers allowed

      if(layer == LAYER_NONE)
         return false;  // No layer detected

      if(phase == PHASE_UNORDERED)
         return false;  // Choppy market - block all entries

      if(phase == PHASE_EMERGING && layer == LAYER_3_STRONG)
         return false;  // Deep pullbacks too risky in forming trend

      return true;  // TRENDING allows all; EMERGING allows L1/L2
   }

   // Structure gate diagnostics
   int    ActiveLayer()       const { return m_active_layer; }
   bool   PullbackFound()     const { return m_pullback_found; }
   int    PullbackBar()       const { return m_pullback_bar; }
   double PullbackExtreme()   const { return m_pullback_extreme; }
   bool   RecoveryDetected()  const { return m_recovery_detected; }

   // Rejection statistics
   int    BarsEvaluated()     const { return m_bars_evaluated; }
   int    SignalsGenerated()   const { return m_signals_generated; }
   int    RejectFilter()      const { return m_reject_filter; }
   int    RejectBias()        const { return m_reject_bias; }
   int    RejectGate()        const { return m_reject_gate; }
   int    RejectVotes()       const { return m_reject_votes; }

   // Returns the number of currently enabled indicator votes.
   int CountEnabledIndicators() const
   {
      int count = 0;
      if(m_settings.Ind_EmaSig_Enabled) count++;
      if(m_settings.Ind_Adx_Enabled)    count++;
      if(m_settings.Ind_Macd_Enabled)   count++;
      if(m_settings.Ind_Rsi_Enabled)    count++;
      if(m_settings.Ind_Cci_Enabled)    count++;
      if(m_settings.Ind_Mfi_Enabled)    count++;
      if(m_settings.Ind_Sto_Enabled)    count++;
      if(m_settings.Ind_Bb_Enabled)     count++;
      if(m_settings.Ind_Psar_Enabled)   count++;
      if(m_settings.Ind_P123_Enabled)   count++;
      if(m_settings.Ind_Ross_Enabled)   count++;
      return count;
   }

   // Returns a formatted multi-line diagnostics string for cockpit/UI display.
   // Shows EMA values with price distance, active structure layer, pullback/recovery
   // status, and session-level rejection statistics.
   string GetDiagnosticsString()
   {
      if(h_ema1 == INVALID_HANDLE) return "";

      int    shift = m_settings.ma_v_shift;
      double price = iClose(m_symbol, PERIOD_CURRENT, shift);
      double pip   = PipSize();
      if(pip <= 0.0) pip = _Point;

      double e1 = GetMAVal(h_ema1, shift);
      double e2 = GetMAVal(h_ema2, shift);
      double e3 = GetMAVal(h_ema3, shift);
      double e4 = GetMAVal(h_ema4, shift);

      string diag = "";

      // EMA values with price distance in pips
      diag += StringFormat("EMA1(%d)=%.5f(%+.1fp) EMA2(%d)=%.5f(%+.1fp)\n",
                           m_settings.P_Ema1, e1, (price - e1) / pip,
                           m_settings.P_Ema2, e2, (price - e2) / pip);
      diag += StringFormat("EMA3(%d)=%.5f(%+.1fp) EMA4(%d)=%.5f(%+.1fp)\n",
                           m_settings.P_Ema3, e3, (price - e3) / pip,
                           m_settings.P_Ema4, e4, (price - e4) / pip);

      // Structure gate status (only shown when gate is active)
      if(m_settings.RequirePullback)
      {
         string layer_str = (m_active_layer > 0 ? StringFormat("L%d", m_active_layer) : "NONE");
         string pb_str    = (m_pullback_found
                             ? StringFormat("bar[%d]@%.5f", m_pullback_bar, m_pullback_extreme)
                             : "NONE");
         string rec_str   = (m_recovery_detected ? "YES" : "NO");
         diag += StringFormat("Layer=%s PB=%s Recov=%s\n", layer_str, pb_str, rec_str);
      }

      // Rejection statistics for this session
      diag += StringFormat("Stats: eval=%d sig=%d rejF=%d rejB=%d rejG=%d rejV=%d",
                           m_bars_evaluated, m_signals_generated,
                           m_reject_filter, m_reject_bias, m_reject_gate, m_reject_votes);
      return diag;
   }

   // Returns +1 if vote state matches the given bias direction, 0 otherwise
   static int CalcVoteResult(const int bias, const string &state)
   {
      if(bias == 0) return 0;
      if(bias ==  1 && state == "BUY")  return 1;
      if(bias == -1 && state == "SELL") return 1;
      return 0;
   }

   // --- VOTE SNAPSHOT (for Cockpit per-vote display) ---
   // Evaluates each enabled vote independently (BUY/SELL/FLAT) without changing internal state.
   void CaptureVoteSnapshots(SVoteSnapshot &out[], int &count, const int current_bias = 0)
   {
      int shift = m_settings.ma_v_shift;
      count = 0;
      ArrayResize(out, 12);

      if(m_settings.Ind_EmaSig_Enabled && h_ema1 != INVALID_HANDLE)
      {
         double p = iClose(m_symbol, PERIOD_CURRENT, shift);
         double e = GetMAVal(h_ema1, shift);
         out[count].name    = "EmaSig";
         out[count].enabled = true;
         if(p > e)      { out[count].state = "BUY";  out[count].reason = "(price>EMA1)"; }
         else if(p < e) { out[count].state = "SELL"; out[count].reason = "(price<EMA1)"; }
         else           { out[count].state = "FLAT"; out[count].reason = "(price=EMA1)"; }
         out[count].vote_result = CalcVoteResult(current_bias, out[count].state);
         count++;
      }

      if(m_settings.Ind_Adx_Enabled && h_adx != INVALID_HANDLE)
      {
         double adx = GetVal(h_adx, shift);
         bool pass = (adx > m_settings.T_Adx);
         out[count].name    = "ADX";
         out[count].enabled = true;
         if(pass && m_diag_last_bias ==  1) { out[count].state = "BUY";  out[count].reason = StringFormat("(ADX=%.0f>%d)", adx, m_settings.T_Adx); }
         else if(pass && m_diag_last_bias == -1) { out[count].state = "SELL"; out[count].reason = StringFormat("(ADX=%.0f>%d)", adx, m_settings.T_Adx); }
         else                               { out[count].state = "FLAT"; out[count].reason = StringFormat("(ADX=%.0f%s%d)", adx, pass?">=":"<=", m_settings.T_Adx); }
         out[count].vote_result = CalcVoteResult(current_bias, out[count].state);
         count++;
      }

      if(m_settings.Ind_Macd_Enabled && h_macd != INVALID_HANDLE)
      {
         bool b = Check_MACD(1, shift);
         bool s = Check_MACD(-1, shift);
         double m = GetVal(h_macd, shift, 0);
         double sig = GetVal(h_macd, shift, 1);
         out[count].name    = "MACD";
         out[count].enabled = true;
         if(b)      { out[count].state = "BUY";  out[count].reason = StringFormat("(main=%.5f>sig,>0)", m); }
         else if(s) { out[count].state = "SELL"; out[count].reason = StringFormat("(main=%.5f<sig,<0)", m); }
         else       { out[count].state = "FLAT"; out[count].reason = StringFormat("(main=%.5f,sig=%.5f)", m, sig); }
         out[count].vote_result = CalcVoteResult(current_bias, out[count].state);
         count++;
      }

      if(m_settings.Ind_Rsi_Enabled && h_rsi != INVALID_HANDLE)
      {
         bool b = Check_RSI(1, shift);
         bool s = Check_RSI(-1, shift);
         double r = GetVal(h_rsi, shift);
         out[count].name    = "RSI";
         out[count].enabled = true;
         if(b && !s)      { out[count].state = "BUY";  out[count].reason = StringFormat("(RSI=%.0f buy)", r); }
         else if(s && !b) { out[count].state = "SELL"; out[count].reason = StringFormat("(RSI=%.0f sell)", r); }
         else             { out[count].state = "FLAT"; out[count].reason = StringFormat("(RSI=%.0f neutral)", r); }
         out[count].vote_result = CalcVoteResult(current_bias, out[count].state);
         count++;
      }

      if(m_settings.Ind_Cci_Enabled && h_cci != INVALID_HANDLE)
      {
         bool b = Check_CCI(1, shift);
         bool s = Check_CCI(-1, shift);
         double c = GetVal(h_cci, shift);
         out[count].name    = "CCI";
         out[count].enabled = true;
         if(b && !s)      { out[count].state = "BUY";  out[count].reason = StringFormat("(CCI=%.0f>0)", c); }
         else if(s && !b) { out[count].state = "SELL"; out[count].reason = StringFormat("(CCI=%.0f<0)", c); }
         else             { out[count].state = "FLAT"; out[count].reason = StringFormat("(CCI=%.0f)", c); }
         out[count].vote_result = CalcVoteResult(current_bias, out[count].state);
         count++;
      }

      if(m_settings.Ind_Mfi_Enabled && h_mfi != INVALID_HANDLE)
      {
         bool b = Check_MFI(1, shift);
         bool s = Check_MFI(-1, shift);
         double mfi = GetVal(h_mfi, shift);
         out[count].name    = "MFI";
         out[count].enabled = true;
         if(b && !s)      { out[count].state = "BUY";  out[count].reason = StringFormat("(MFI=%.0f)", mfi); }
         else if(s && !b) { out[count].state = "SELL"; out[count].reason = StringFormat("(MFI=%.0f)", mfi); }
         else             { out[count].state = "FLAT"; out[count].reason = StringFormat("(MFI=%.0f neutral)", mfi); }
         out[count].vote_result = CalcVoteResult(current_bias, out[count].state);
         count++;
      }

      if(m_settings.Ind_Sto_Enabled && h_sto != INVALID_HANDLE)
      {
         bool b = Check_Sto(1, shift);
         bool s = Check_Sto(-1, shift);
         double k = GetVal(h_sto, shift, 0);
         double d = GetVal(h_sto, shift, 1);
         out[count].name    = "Stoch";
         out[count].enabled = true;
         if(b && !s)      { out[count].state = "BUY";  out[count].reason = StringFormat("(K=%.0f>D=%.0f)", k, d); }
         else if(s && !b) { out[count].state = "SELL"; out[count].reason = StringFormat("(K=%.0f<D=%.0f)", k, d); }
         else             { out[count].state = "FLAT"; out[count].reason = StringFormat("(K=%.0f,D=%.0f)", k, d); }
         out[count].vote_result = CalcVoteResult(current_bias, out[count].state);
         count++;
      }

      if(m_settings.Ind_Bb_Enabled && h_bb != INVALID_HANDLE)
      {
         bool b = Check_BB(1, shift);
         bool s = Check_BB(-1, shift);
         double mid = GetVal(h_bb, shift, 0);
         double cl  = iClose(m_symbol, PERIOD_CURRENT, shift);
         out[count].name    = "BB";
         out[count].enabled = true;
         if(b && !s)      { out[count].state = "BUY";  out[count].reason = StringFormat("(price>mid=%.5f)", mid); }
         else if(s && !b) { out[count].state = "SELL"; out[count].reason = StringFormat("(price<mid=%.5f)", mid); }
         else             { out[count].state = "FLAT"; out[count].reason = StringFormat("(cl=%.5f,mid=%.5f)", cl, mid); }
         out[count].vote_result = CalcVoteResult(current_bias, out[count].state);
         count++;
      }

      if(m_settings.Ind_Psar_Enabled && h_psar != INVALID_HANDLE)
      {
         bool b = Check_PSAR(1, shift);
         bool s = Check_PSAR(-1, shift);
         double p = GetVal(h_psar, shift);
         out[count].name    = "PSAR";
         out[count].enabled = true;
         if(b)      { out[count].state = "BUY";  out[count].reason = StringFormat("(dot=%.5f<price)", p); }
         else if(s) { out[count].state = "SELL"; out[count].reason = StringFormat("(dot=%.5f>price)", p); }
         else       { out[count].state = "FLAT"; out[count].reason = "(no signal)"; }
         out[count].vote_result = CalcVoteResult(current_bias, out[count].state);
         count++;
      }

      if(m_settings.Ind_P123_Enabled && h_fractals != INVALID_HANDLE)
      {
         bool b = Check_P123(1, shift);
         bool s = Check_P123(-1, shift);
         out[count].name    = "P123";
         out[count].enabled = true;
         if(b)      { out[count].state = "BUY";  out[count].reason = "(above fractal)"; }
         else if(s) { out[count].state = "SELL"; out[count].reason = "(below fractal)"; }
         else       { out[count].state = "FLAT"; out[count].reason = "(no breakout)"; }
         out[count].vote_result = CalcVoteResult(current_bias, out[count].state);
         count++;
      }

      if(m_settings.Ind_Ross_Enabled && h_fractals != INVALID_HANDLE)
      {
         bool b = Check_Ross(1, shift);
         bool s = Check_Ross(-1, shift);
         out[count].name    = "Ross";
         out[count].enabled = true;
         if(b)      { out[count].state = "BUY";  out[count].reason = "(hook+trend)"; }
         else if(s) { out[count].state = "SELL"; out[count].reason = "(hook+trend)"; }
         else       { out[count].state = "FLAT"; out[count].reason = "(no hook)"; }
         out[count].vote_result = CalcVoteResult(current_bias, out[count].state);
         count++;
      }

      ArrayResize(out, count);
   }


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

      // Only create ATR when NOT using strict no-ATR RRM mode
      bool need_atr = (m_settings.ExitProfile != EXIT_PROFILE_RRM_STRICT_NO_ATR);
      h_atr  = (need_atr ? iATR(m_symbol, PERIOD_CURRENT, m_settings.P_Atr) : INVALID_HANDLE);

      // Optional indicators: create only when used by votes/filters/trailing (reduces Strategy Tester clutter)
      h_macd = (m_settings.Ind_Macd_Enabled ? iMACD(m_symbol, PERIOD_CURRENT, m_settings.P_MacdFast, m_settings.P_MacdSlow, m_settings.P_MacdSig, PRICE_CLOSE) : INVALID_HANDLE);
      h_rsi  = (m_settings.Ind_Rsi_Enabled  ? iRSI(m_symbol, PERIOD_CURRENT, m_settings.P_Rsi, PRICE_CLOSE) : INVALID_HANDLE);
      h_cci  = (m_settings.Ind_Cci_Enabled  ? iCCI(m_symbol, PERIOD_CURRENT, m_settings.P_Cci, PRICE_CLOSE) : INVALID_HANDLE);
      h_adx  = (m_settings.Ind_Adx_Enabled  ? iADX(m_symbol, PERIOD_CURRENT, m_settings.P_Adx) : INVALID_HANDLE);
      h_mfi  = (m_settings.Ind_Mfi_Enabled  ? iMFI(m_symbol, PERIOD_CURRENT, m_settings.P_Mfi, VOLUME_TICK) : INVALID_HANDLE);
      h_sto  = (m_settings.Ind_Sto_Enabled  ? iStochastic(m_symbol, PERIOD_CURRENT, m_settings.P_StoK, m_settings.P_StoD, m_settings.P_StoSlow, MODE_SMA, STO_LOWHIGH) : INVALID_HANDLE);
      h_bb   = (m_settings.Ind_Bb_Enabled   ? iBands(m_symbol, PERIOD_CURRENT, m_settings.P_Bb, 0, m_settings.P_BbDev, PRICE_CLOSE) : INVALID_HANDLE);

      bool need_psar = (m_settings.Ind_Psar_Enabled || m_settings.TrailMode == TRAIL_PSAR);
      h_psar = (need_psar ? iSAR(m_symbol, PERIOD_CURRENT, m_settings.P_PsarStep, m_settings.P_PsarMax) : INVALID_HANDLE);

      bool need_fractals = (m_settings.Ind_P123_Enabled || m_settings.Ind_Ross_Enabled || m_settings.TrailMode == TRAIL_FRACTAL);
      h_fractals = (need_fractals ? iFractals(m_symbol, PERIOD_CURRENT) : INVALID_HANDLE);
      // B. Create HTF Filter (If Enabled)
      if(m_settings.UseHTF) {
         h_htf_ema = iMA(m_symbol, m_settings.HtfPeriod, m_settings.P_HtfEma, h_shift, method, PRICE_CLOSE);
      }
      
      // C. Validation
      if(h_ema1 == INVALID_HANDLE) {
         Print("CRITICAL ERROR: Failed to create essential indicators (EMA).");
         return false;
      }
      if(need_atr && h_atr == INVALID_HANDLE) {
         Print("CRITICAL ERROR: Failed to create ATR indicator.");
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

   //==========================================================================
   // === GetDirection: BEGIN ===
   //==========================================================================
   // This function implements the 9-step signal validation pipeline.
   // Each step must pass before moving to the next.
   // If any step fails, the function returns 0 (no trade).
   //
   // PROCESS FLOW:
   // 1. PRE-FILTERS: Spread, ATR, time checks
   // 2. MARKET BIAS: Check EMA position and slopes
   //    - SINGLE_SLOPE: EMA rising/falling (when BiasFastID == BiasSlowID)
   //    - PAIR: Fast > Slow AND both rising (LONG) or Fast < Slow AND both falling (SHORT)
   //    - NEUTRAL: Neither condition met -> REJECT
   // 3. AUTOSTRAT: Generate entry signal based on strategy
   //    - STRAT_SINGLE_SLOPE: Single EMA direction
   //    - STRAT_PRICE_CROSS: Price vs EMA
   //    - STRAT_PAIR_CROSS: EMA crossover
   // 4. SIGNAL VALIDATION: Entry signal must match bias
   // 5. HTF FILTER: Higher timeframe must agree with bias
   // 6. RRM GATES: Check pullback/divergence if enabled
   // 7. VOTING BYPASS: Skip voting if threshold <= 1
   // 8. INDICATOR VOTING: Count indicator confirmations
   // 9. FINAL DECISION: Accept if votes >= threshold
   //
   // RETURNS: 1 (LONG), -1 (SHORT), 0 (NO TRADE)
   //==========================================================================
   // GetDirection() - Main Signal Processing Pipeline (WITH DIAGNOSTICS)
   //==========================================================================
   int GetDirection() 
   {
      // ═══════════════════════════════════════════════════════════════
      // 260304_PR1: Update phase diagnostics (passive - doesn't affect logic)
      // Phase detection is DISABLED by default (PhaseDetectionEnabled = false)
      // This only logs phase information when DebugFlow = true
      // ═══════════════════════════════════════════════════════════════
      UpdatePhaseDiagnostics(m_settings.ma_v_shift);

      // ═══════════════════════════════════════════════════════════════
      // 260304_PR3: Update layer diagnostics (passive - doesn't affect logic)
      // Layer detection is DISABLED by default (EnableLayerDetection = false)
      // ═══════════════════════════════════════════════════════════════
      UpdateLayerDiagnostics(m_settings.ma_v_shift);

      // Diagnostics reset (for Cockpit/UI)
      m_diag_last_bias   = 0;
      m_diag_last_votes  = 0;
      m_diag_last_reason = "";

      m_bars_evaluated++;

      // Bar-close diagnostic banner
      if(m_settings.DebugFlow)
      {
         datetime bar_time = iTime(m_symbol, PERIOD_CURRENT, m_settings.ma_v_shift);
         Print("========================================");
         PrintFormat("BAR CLOSE: %s", TimeToString(bar_time, TIME_DATE|TIME_MINUTES));
         Print("========================================");
      }

      // 1. Check Filters First
      if(!CheckFilters()) { m_reject_filter++; return 0; }

      // 1b. Master bias gate (BiasEnabled)
      if(!m_settings.BiasEnabled) { m_diag_last_reason="BIAS_DISABLED"; m_reject_bias++; return 0; }

      // Use Vote_EvalShift for signal/vote evaluation (defaults to 1 = closed bar).
      // This ensures all indicator checks use the last fully-closed bar, matching
      // the Python system's behavior of always evaluating completed bars (shift=1).
      int v_shift = m_settings.Vote_EvalShift;
      
      // ═══════════════════════════════════════════════════════════════
      // 260304_PR4: Detect entry layer (passive detection - no filtering yet)
      // Layer detection is DISABLED by default (EnableLayerDetection = false)
      // This only detects and logs layer information when DebugFlow = true
      // ═══════════════════════════════════════════════════════════════
      m_diag_last_entry_layer = DetectEntryLayer(v_shift);
      if(m_settings.DebugFlow) {
         PrintFormat("ENTRY LAYER[%s]: Detected %s",
                     TimeToString(iTime(m_symbol, PERIOD_CURRENT, v_shift)),
                     EnumToString(m_diag_last_entry_layer));
      }

      //+------------------------------------------------------------------+
      //| 260304_PR5: Phase-Based Layer Filtering                          |
      //|                                                                  |
      //| Enforces RRM methodology rules for entry filtering:              |
      //| - UNORDERED: Block ALL trades (choppy, no clear trend)           |
      //| - EMERGING: Block STRONG trades (deep pullbacks too risky)       |
      //| - TRENDING: Allow all layers (strong established trend)          |
      //|                                                                  |
      //| Requires BOTH PhaseDetectionEnabled=true AND                     |
      //| EnableLayerDetection=true to activate filtering                  |
      //+------------------------------------------------------------------+
      // ═══════════════════════════════════════════════════════════════
      // 260304_PR5: Phase-based layer filtering
      // If both phase detection and layer detection are enabled,
      // enforce RRM methodology rules for trade filtering by phase
      // ═══════════════════════════════════════════════════════════════
      if(m_settings.EnableLayerDetection && 
         m_settings.PhaseDetectionEnabled &&
         m_diag_last_entry_layer != LAYER_NONE)
      {
         EMarketPhase phase = m_diag_last_phase;
         
         // Rule 1: UNORDERED phase blocks ALL trades (choppy market)
         if(phase == PHASE_UNORDERED) {
            m_diag_last_reason = "PHASE_UNORDERED_BLOCKS_ALL";
            m_reject_bias++;
            
            if(m_settings.DebugFlow) {
               PrintFormat("[260304_PR5] UNORDERED phase detected - blocking ALL trades (layer=%s)",
                           EnumToString(m_diag_last_entry_layer));
            }
            return 0;
         }
         
         // Rule 2: EMERGING phase blocks STRONG (Layer 3) trades only
         if(phase == PHASE_EMERGING && m_diag_last_entry_layer == LAYER_3_STRONG) {
            m_diag_last_reason = "PHASE_EMERGING_BLOCKS_STRONG";
            m_reject_bias++;
            
            if(m_settings.DebugFlow) {
               Print("[260304_PR5] EMERGING phase detected - blocking STRONG layer trade (deep pullback too risky)");
            }
            return 0;
         }
         
         // Rule 3: TRENDING phase allows all layers (no blocking)
         if(m_settings.DebugFlow && phase == PHASE_TRENDING) {
            PrintFormat("[260304_PR5] TRENDING phase detected - allowing %s layer trade",
                        EnumToString(m_diag_last_entry_layer));
         }
      }

      // 260304_PR7: Store layer-allowed state for UI diagnostics
      m_layer_allowed = IsLayerAllowed(m_diag_last_entry_layer, m_diag_last_phase);

      // 2. Determine MASTER BIAS (Strategy)
      int bias = 0;
      
      // 260304_PR2: Route to phase-based bias if selected
      if(m_settings.BiasMode == BIAS_AUTO_PHASE)
      {
         bias = GetBias_PhaseBased(v_shift);
         
         if(m_settings.DebugFlow) {
            datetime bar_time = iTime(m_symbol, PERIOD_CURRENT, v_shift);
            PrintFormat("STEP 1 BIAS[%s]: BIAS_AUTO_PHASE mode → bias=%d", TimeToString(bar_time), bias);
         }
         
         if(bias == 0) {
            m_diag_last_bias = 0;
            m_diag_last_reason = "BIAS_ZERO";
            m_reject_bias++;
            return 0;
         }
         
         m_diag_last_bias = bias;
      }
      // === MANUAL BIAS MODE ===
      else if(m_settings.BiasMode == BIAS_MANUAL) {
         if(m_settings.ManSide == SIDE_LONG)
            bias = 1;
         else if(m_settings.ManSide == SIDE_SHORT)
            bias = -1;
         else
            bias = 0; // ManSide is SIDE_NONE
            
         if(m_settings.DebugFlow) {
            datetime bar_time = iTime(m_symbol, PERIOD_CURRENT, v_shift);
            PrintFormat("STEP 1 BIAS[%s]: MANUAL mode → bias=%d", TimeToString(bar_time), bias);
         }
      }
      // === AUTO BIAS MODE ===
      else {
         // Get EMA handles for bias calculation
         int hf = (m_settings.BiasFastID==0)?h_ema1 : (m_settings.BiasFastID==1)?h_ema2 : (m_settings.BiasFastID==2)?h_ema3 : h_ema4;
         int hs = (m_settings.BiasSlowID==0)?h_ema1 : (m_settings.BiasSlowID==1)?h_ema2 : (m_settings.BiasSlowID==2)?h_ema3 : h_ema4;
         
         // ★★★ Get ACTUAL periods for diagnostic display ★★★
         int fast_period = (m_settings.BiasFastID==0) ? m_settings.P_Ema1 : 
                           (m_settings.BiasFastID==1) ? m_settings.P_Ema2 : 
                           (m_settings.BiasFastID==2) ? m_settings.P_Ema3 : m_settings.P_Ema4;
         
         int slow_period = (m_settings.BiasSlowID==0) ? m_settings.P_Ema1 : 
                           (m_settings.BiasSlowID==1) ? m_settings.P_Ema2 : 
                           (m_settings.BiasSlowID==2) ? m_settings.P_Ema3 : m_settings.P_Ema4;
         
         // Build display names with ACTUAL periods
         string ema_fast_name = StringFormat("EMA%d(%d)", m_settings.BiasFastID+1, fast_period);
         string ema_slow_name = StringFormat("EMA%d(%d)", m_settings.BiasSlowID+1, slow_period);
         
         // Get EMA values
         double f_curr = GetMAVal(hf, v_shift, 0);
         double f_prev = GetMAVal(hf, v_shift + 1, 0);
         double s_curr = GetMAVal(hs, v_shift, 0);
         double s_prev = GetMAVal(hs, v_shift + 1, 0);
         
         // Calculate slopes with minimum threshold (to avoid noise)
         double pip = PipSize();
         double min_slope = 0.0 * pip; // Set to 0.5 or 1.0 to require minimum movement
         
         int fast_slope = 0;
         if((f_curr - f_prev) > min_slope) fast_slope = 1;
         else if((f_prev - f_curr) > min_slope) fast_slope = -1;
         
         int slow_slope = 0;
         if((s_curr - s_prev) > min_slope) slow_slope = 1;
         else if((s_prev - s_curr) > min_slope) slow_slope = -1;
         
         // === STEP 1: Determine Market Bias (Primary Filter) ===
         int market_bias = 0;
         
         // ★★★ SPECIAL CASE: SINGLE_SLOPE (Fast == Slow) ★★★
         if(m_settings.BiasFastID == m_settings.BiasSlowID)
         {
            // For SINGLE_SLOPE, use only the EMA slope direction
            if(fast_slope == 1)
               market_bias = 1;
            else if(fast_slope == -1)
               market_bias = -1;
            // else market_bias = 0 (EMA flat)
            
            // DIAGNOSTIC LOGGING
            if(m_settings.DebugFlow) {
               datetime bar_time = iTime(m_symbol, PERIOD_CURRENT, v_shift);
               double change_pips = (f_curr - f_prev) / pip;
               PrintFormat("STEP 1 BIAS[%s]: SINGLE_SLOPE %s | curr=%.5f prev=%.5f change=%.2f pips slope=%s → bias=%d",
                           TimeToString(bar_time),
                           ema_fast_name,
                           f_curr,
                           f_prev,
                           change_pips,
                           (fast_slope==1)?"RISING":(fast_slope==-1)?"FALLING":"FLAT",
                           market_bias);
            }
         }
         // ★★★ PAIR MODE (Fast ≠ Slow) ★★★
         else
         {
            // Standard PAIR logic: require position AND slope alignment
            // LONG: Fast > Slow AND both rising
            if(f_curr > s_curr && fast_slope == 1 && slow_slope == 1)
               market_bias = 1;
            // SHORT: Fast < Slow AND both falling
            else if(f_curr < s_curr && fast_slope == -1 && slow_slope == -1)
               market_bias = -1;
            // else market_bias = 0 (invalid/neutral)
            
            // DIAGNOSTIC LOGGING
            if(m_settings.DebugFlow) {
               datetime bar_time = iTime(m_symbol, PERIOD_CURRENT, v_shift);
               double fast_change_pips = (f_curr - f_prev) / pip;
               double slow_change_pips = (s_curr - s_prev) / pip;
               string position = (f_curr > s_curr) ? "ABOVE" : (f_curr < s_curr) ? "BELOW" : "EQUAL";
               PrintFormat("STEP 1 BIAS[%s]: PAIR %s vs %s | fast=%.5f(%+.2fp %s) slow=%.5f(%+.2fp %s) pos=%s → bias=%d",
                           TimeToString(bar_time),
                           ema_fast_name, ema_slow_name,
                           f_curr, fast_change_pips, (fast_slope==1)?"UP":(fast_slope==-1)?"DN":"FLAT",
                           s_curr, slow_change_pips, (slow_slope==1)?"UP":(slow_slope==-1)?"DN":"FLAT",
                           position,
                           market_bias);
            }
         }
         
         // If no valid market bias, reject immediately
         if(market_bias == 0) {
            m_diag_last_bias = 0;
            m_diag_last_reason = "BIAS_ZERO";
            m_reject_bias++;
            
            if(m_settings.DebugFlow) {
               datetime bar_time = iTime(m_symbol, PERIOD_CURRENT, v_shift);
               PrintFormat("STEP 1 BIAS[%s]: bias=0 → REJECT (no trend)", TimeToString(bar_time));
            }
            
            return 0;
         }
         
         // === STEP 2: Evaluate AutoStrat for Entry Signal ===
         int entry_signal = 0;
         
         if(m_settings.AutoStrat == STRAT_SINGLE_SLOPE) {
            // Entry signal from EMA slope (same as bias calculation for SINGLE_SLOPE)
            entry_signal = fast_slope;
            
            if(m_settings.DebugFlow) {
               datetime bar_time = iTime(m_symbol, PERIOD_CURRENT, v_shift);
               PrintFormat("STEP 2 ENTRY[%s]: STRAT_SINGLE_SLOPE %s slope=%d → signal=%d",
                           TimeToString(bar_time), ema_fast_name, fast_slope, entry_signal);
            }
         }
         else if(m_settings.AutoStrat == STRAT_PRICE_CROSS) {
            if(m_settings.RequirePriceCross) {
               entry_signal = PriceCrossDirection(hf, v_shift);
            } else {
               double price = iClose(m_symbol, PERIOD_CURRENT, v_shift);
               double ma    = GetMAVal(hf, v_shift, 0);
               entry_signal = (price > ma) ? 1 : -1;
            }
            
            if(m_settings.DebugFlow) {
               datetime bar_time = iTime(m_symbol, PERIOD_CURRENT, v_shift);
               double price = iClose(m_symbol, PERIOD_CURRENT, v_shift);
               double ma    = GetMAVal(hf, v_shift, 0);
               PrintFormat("STEP 2 ENTRY[%s]: STRAT_PRICE_CROSS %s price=%.5f ma=%.5f → signal=%d",
                           TimeToString(bar_time), ema_fast_name, price, ma, entry_signal);
            }
         }
         else {  // STRAT_PAIR_CROSS
            // Check for EMA crossover
            double f_curr_cross = GetMAVal(hf, v_shift, 0);
            double f_prev_cross = GetMAVal(hf, v_shift + 1, 0);
            double s_curr_cross = GetMAVal(hs, v_shift, 0);
            double s_prev_cross = GetMAVal(hs, v_shift + 1, 0);
            
            bool bullish_cross = (f_prev_cross <= s_prev_cross && f_curr_cross > s_curr_cross);
            bool bearish_cross = (f_prev_cross >= s_prev_cross && f_curr_cross < s_curr_cross);
            bool has_crossover = (bullish_cross || bearish_cross);
            
            // Bullish cross: fast was below, now above
            if(bullish_cross)
               entry_signal = 1;
            // Bearish cross: fast was above, now below
            else if(bearish_cross)
               entry_signal = -1;
            // No fresh crossover - check for RRM continuation mode
            else if(m_settings.ExitProfile == EXIT_PROFILE_RRM_STRICT_NO_ATR && market_bias != 0) {
               // Allow entries within established trend when bias is valid and EMA position matches
               bool ema_position_matches_bias = (market_bias == 1) ? (f_curr_cross > s_curr_cross) : (f_curr_cross < s_curr_cross);
               if(ema_position_matches_bias) {
                  entry_signal = market_bias;
                  
                  if(m_settings.DebugFlow) {
                     datetime bar_time = iTime(m_symbol, PERIOD_CURRENT, v_shift);
                     PrintFormat("STEP 2 ENTRY[%s]: RRM CONTINUATION bias=%d trend intact f=%.5f %s s=%.5f → signal=%d",
                                 TimeToString(bar_time), market_bias, f_curr_cross,
                                 (market_bias == 1 ? ">" : "<"), s_curr_cross, entry_signal);
                  }
               }
               else {
                  entry_signal = 0;
                  
                  if(m_settings.DebugFlow) {
                     datetime bar_time = iTime(m_symbol, PERIOD_CURRENT, v_shift);
                     PrintFormat("STEP 2 ENTRY[%s]: RRM CONTINUATION rejected f=%.5f vs s=%.5f bias=%d → signal=0",
                                 TimeToString(bar_time), f_curr_cross, s_curr_cross, market_bias);
                  }
               }
            }
            else {
               entry_signal = 0;
               
               if(m_settings.DebugFlow) {
                  datetime bar_time = iTime(m_symbol, PERIOD_CURRENT, v_shift);
                  PrintFormat("STEP 2 ENTRY[%s]: STRAT_PAIR_CROSS no crossover → signal=0",
                              TimeToString(bar_time));
               }
            }
            
            if(m_settings.DebugFlow && has_crossover) {
               datetime bar_time = iTime(m_symbol, PERIOD_CURRENT, v_shift);
               PrintFormat("STEP 2 ENTRY[%s]: STRAT_PAIR_CROSS %s vs %s prev: %.5f vs %.5f curr: %.5f vs %.5f → signal=%d",
                           TimeToString(bar_time), ema_fast_name, ema_slow_name,
                           f_prev_cross, s_prev_cross, f_curr_cross, s_curr_cross, entry_signal);
            }
         }
         
         // === STEP 3: Validate Entry Signal Against Market Bias ===
         // Entry signal must match market bias, otherwise reject
         if(entry_signal == market_bias) {
            bias = market_bias;
            
            if(m_settings.DebugFlow) {
               datetime bar_time = iTime(m_symbol, PERIOD_CURRENT, v_shift);
               PrintFormat("STEP 3 MATCH[%s]: entry=%d matches bias=%d → PASS",
                           TimeToString(bar_time), entry_signal, market_bias);
            }
         }
         else {
            bias = 0;
            m_diag_last_bias = 0;
            m_diag_last_reason = "SIGNAL_MISMATCH";
            
            if(m_settings.DebugFlow) {
               datetime bar_time = iTime(m_symbol, PERIOD_CURRENT, v_shift);
               PrintFormat("STEP 3 MATCH[%s]: entry=%d != bias=%d → REJECT",
                           TimeToString(bar_time), entry_signal, market_bias);
            }
            m_reject_bias++;
            return 0;
         }
      }
      
      m_diag_last_bias = bias;

      if(bias == 0) { 
         m_diag_last_reason="BIAS_ZERO";
         m_reject_bias++;
         return 0; 
      }

      // 3. HTF Filter Check
      if(m_settings.UseHTF) {
         double curr = GetMAVal(h_htf_ema, 1);
         double prev = GetMAVal(h_htf_ema, 2);
         int htf_dir = (curr > prev) ? 1 : -1;
         
         if(bias != htf_dir) { 
            m_diag_last_reason="HTF_VETO";
            m_reject_gate++;
            
            if(m_settings.DebugFlow) {
               datetime bar_time = iTime(m_symbol, PERIOD_CURRENT, v_shift);
               PrintFormat("STEP 4 HTF[%s]: bias=%d htf_dir=%d → VETO",
                           TimeToString(bar_time), bias, htf_dir);
            }
            
            return 0; 
         }
         if(m_settings.DebugFlow) {
            datetime bar_time = iTime(m_symbol, PERIOD_CURRENT, v_shift);
            PrintFormat("STEP 4 HTF[%s]: bias=%d htf_dir=%d → PASS",
                        TimeToString(bar_time), bias, htf_dir);
         }
      }

      // 3c. Sequential hard gates (any fail = reject)
      if(m_settings.RequirePullback) {
         if(!Check_Gate_DynamicPullback(bias)) {
            if(m_settings.DebugFlow) Print("STEP 5 STRUCTURE: Dynamic Pullback → REJECT (", m_diag_last_reason, ")");
            m_reject_gate++;
            return 0;
         }
         if(m_settings.DebugFlow) Print("STEP 5 STRUCTURE: Dynamic Pullback → PASS");
      }

      // 4. VOTING BYPASS (Speed Mode)
      if(m_settings.VoteThreshold <= 1) { 
         m_diag_last_votes=0; 
         m_diag_last_reason="BYPASS";
         m_signals_generated++;
         return bias; 
      }

      // 5. Voting Logic — Dynamic weight-based consensus
      // VOTE_MODE_ALL:       every enabled indicator must agree (weights ignored)
      // VOTE_MODE_THRESHOLD: weighted vote sum must reach VoteThreshold
      double vote_weight = 0.0;
      bool   all_pass    = true;

      // Helper lambda-style macro not available in MQL5; use inline checks
      #define CAST_VOTE(use_flag, weight_field, check_expr) \
         if(use_flag) { \
            bool _cv_pass = (check_expr); \
            if(_cv_pass) vote_weight += weight_field; \
            else         all_pass    = false; \
         }

      CAST_VOTE(m_settings.Ind_EmaSig_Enabled, m_settings.Ind_EmaSig_Weight, Check_EMA1(bias, v_shift))
      CAST_VOTE(m_settings.Ind_Adx_Enabled,    m_settings.Ind_Adx_Weight,    Check_ADX(v_shift))
      CAST_VOTE(m_settings.Ind_Macd_Enabled,   m_settings.Ind_Macd_Weight,   Check_MACD(bias, v_shift))
      CAST_VOTE(m_settings.Ind_Rsi_Enabled,    m_settings.Ind_Rsi_Weight,    Check_RSI(bias, v_shift))
      CAST_VOTE(m_settings.Ind_Cci_Enabled,    m_settings.Ind_Cci_Weight,    Check_CCI(bias, v_shift))
      CAST_VOTE(m_settings.Ind_Mfi_Enabled,    m_settings.Ind_Mfi_Weight,    Check_MFI(bias, v_shift))
      CAST_VOTE(m_settings.Ind_Sto_Enabled,    m_settings.Ind_Sto_Weight,    Check_Sto(bias, v_shift))
      CAST_VOTE(m_settings.Ind_Bb_Enabled,     m_settings.Ind_Bb_Weight,     Check_BB(bias, v_shift))
      CAST_VOTE(m_settings.Ind_Psar_Enabled,   m_settings.Ind_Psar_Weight,
                (m_settings.Vote_AllowPsarFlip ? Check_PSAR_WithFlip(bias, v_shift) : Check_PSAR(bias, v_shift)))
      CAST_VOTE(m_settings.Ind_P123_Enabled,   m_settings.Ind_P123_Weight,   Check_P123(bias, v_shift))
      CAST_VOTE(m_settings.Ind_Ross_Enabled,   m_settings.Ind_Ross_Weight,   Check_Ross(bias, v_shift))

      #undef CAST_VOTE

      // Volatility regime vote (soft; ATR has no weight field — always weight 1.0)
      if(m_settings.Use_ATRVote)
      {
         if(m_diag_last_atr_ok) vote_weight += 1.0;
         else                   all_pass     = false;
      }

      // Store integer-rounded weight for display (backward-compatible diagnostics)
      m_diag_last_votes = (int)MathRound(vote_weight);

      // ===== DIAGNOSTIC LOGGING FOR VOTE ANALYSIS: BEGIN =====
      if(m_settings.DebugFlow) {
         datetime bar_time = iTime(m_symbol, PERIOD_CURRENT, v_shift);
         string mode_str = (m_settings.VoteMode == VOTE_MODE_ALL ? "ALL" : "THRESHOLD");
         string vote_details = StringFormat("STEP 6 VOTES[%s]: mode=%s bias=%d weight=%.2f/%d",
                                           TimeToString(bar_time),
                                           mode_str, bias, vote_weight, m_settings.VoteThreshold);
         
         // Log each enabled vote with actual indicator values
         if(m_settings.Ind_EmaSig_Enabled) {
            double p = iClose(m_symbol, PERIOD_CURRENT, v_shift);
            double e = GetMAVal(h_ema1, v_shift);
            bool pass = Check_EMA1(bias, v_shift);
            vote_details += StringFormat(" | EmaSig: p=%.5f e=%.5f %s(w=%d)", p, e, pass?"PASS":"FAIL", m_settings.Ind_EmaSig_Weight);
         }
         
         if(m_settings.Ind_Adx_Enabled) {
            double adx = GetVal(h_adx, v_shift);
            bool pass = Check_ADX(v_shift);
            vote_details += StringFormat(" | ADX: %.2f %s(w=%d)", adx, pass?"PASS":"FAIL", m_settings.Ind_Adx_Weight);
         }
         
         if(m_settings.Ind_Macd_Enabled) {
            double m = GetVal(h_macd, v_shift, 0);
            double s = GetVal(h_macd, v_shift, 1);
            bool pass = Check_MACD(bias, v_shift);
            vote_details += StringFormat(" | MACD: main=%.6f sig=%.6f %s(w=%d)", m, s, pass?"PASS":"FAIL", m_settings.Ind_Macd_Weight);
         }
         
         if(m_settings.Ind_Rsi_Enabled) {
            double r = GetVal(h_rsi, v_shift);
            bool pass = Check_RSI(bias, v_shift);
            vote_details += StringFormat(" | RSI: %.2f %s(w=%d)", r, pass?"PASS":"FAIL", m_settings.Ind_Rsi_Weight);
         }
         
         if(m_settings.Ind_Cci_Enabled) {
            double c = GetVal(h_cci, v_shift);
            bool pass = Check_CCI(bias, v_shift);
            vote_details += StringFormat(" | CCI: %.2f %s(w=%d)", c, pass?"PASS":"FAIL", m_settings.Ind_Cci_Weight);
         }
         
         if(m_settings.Ind_Mfi_Enabled) {
            double mfi = GetVal(h_mfi, v_shift);
            bool pass = Check_MFI(bias, v_shift);
            vote_details += StringFormat(" | MFI: %.2f %s(w=%d)", mfi, pass?"PASS":"FAIL", m_settings.Ind_Mfi_Weight);
         }
         
         if(m_settings.Ind_Sto_Enabled) {
            double k = GetVal(h_sto, v_shift, 0);
            double d = GetVal(h_sto, v_shift, 1);
            bool pass = Check_Sto(bias, v_shift);
            vote_details += StringFormat(" | STO: k=%.2f d=%.2f %s(w=%d)", k, d, pass?"PASS":"FAIL", m_settings.Ind_Sto_Weight);
         }
         
         if(m_settings.Ind_Bb_Enabled) {
            double mid = GetVal(h_bb, v_shift, 0);
            double cl = iClose(m_symbol, PERIOD_CURRENT, v_shift);
            bool pass = Check_BB(bias, v_shift);
            vote_details += StringFormat(" | BB: mid=%.5f cl=%.5f %s(w=%d)", mid, cl, pass?"PASS":"FAIL", m_settings.Ind_Bb_Weight);
         }
         
         if(m_settings.Ind_Psar_Enabled) {
            double p = GetVal(h_psar, v_shift);
            double cl = iClose(m_symbol, PERIOD_CURRENT, v_shift);
            bool pass = (m_settings.Vote_AllowPsarFlip ? Check_PSAR_WithFlip(bias, v_shift) : Check_PSAR(bias, v_shift));
            int flips = (m_settings.Vote_AllowPsarFlip ? CountPSARFlips(3) : -1);
            string flip_info = (m_settings.Vote_AllowPsarFlip ? StringFormat(" flips=%d", flips) : "");
            vote_details += StringFormat(" | PSAR: sar=%.5f cl=%.5f%s %s(w=%d)", p, cl, flip_info, pass?"PASS":"FAIL", m_settings.Ind_Psar_Weight);
         }
         
         if(m_settings.Ind_P123_Enabled) {
            bool pass = Check_P123(bias, v_shift);
            vote_details += StringFormat(" | P123: %s(w=%d)", pass?"PASS":"FAIL", m_settings.Ind_P123_Weight);
         }
         
         if(m_settings.Ind_Ross_Enabled) {
            bool pass = Check_Ross(bias, v_shift);
            vote_details += StringFormat(" | ROSS: %s(w=%d)", pass?"PASS":"FAIL", m_settings.Ind_Ross_Weight);
         }
         
         Print(vote_details);
      }
      // ===== DIAGNOSTIC LOGGING FOR VOTE ANALYSIS: END =====

      // Final Decision
      if(m_settings.VoteMode == VOTE_MODE_ALL)
      {
         // ALL mode: every enabled indicator must agree
         if(all_pass) {
            m_diag_last_reason="OK";
            m_signals_generated++;
            if(m_settings.DebugFlow) PrintFormat("STEP 9 RESULT: TS=%d (ALL votes pass)", bias);
            return bias;
         }
         m_diag_last_reason = StringFormat("NOT_ALL_PASS w=%.2f", vote_weight);
         m_reject_votes++;
         if(m_settings.DebugFlow) PrintFormat("STEP 9 RESULT: TS=0 REJECT (%s)", m_diag_last_reason);
         return 0;
      }
      else
      {
         // THRESHOLD mode: weighted sum >= VoteThreshold
         if(vote_weight >= (double)m_settings.VoteThreshold) { 
            m_diag_last_reason="OK";
            m_signals_generated++;
            if(m_settings.DebugFlow) PrintFormat("STEP 9 RESULT: TS=%d (votes %.2f>=%d)", bias, vote_weight, m_settings.VoteThreshold);
            return bias; 
         }
         m_diag_last_reason = StringFormat("VOTES %.2f/%d", vote_weight, m_settings.VoteThreshold);
         m_reject_votes++;
         if(m_settings.DebugFlow) PrintFormat("STEP 9 RESULT: TS=0 REJECT (%s)", m_diag_last_reason);
         return 0;
      }

   } // === GetDirection: END ===

   //==========================================================================
   // === EvaluateTE: BEGIN ===
   //==========================================================================
   // EvaluateTE() — Trade Entry evaluation on the OPENING bar (shift=0).
   //
   // Called on the first tick of bar N+1, AFTER GetDirection() confirmed a TS
   // signal on bar N (shift=1).  This method validates that the conditions
   // at the moment of execution are still clean before entering a trade.
   //
   // Checks performed at shift=0 (forming/current candle):
   //   1. Spread filter  — reject if spread is too wide right now.
   //   2. Time filter    — reject if outside the allowed session window.
   //   3. News filter    — reject if a high-impact news event is imminent.
   //   4. Basic bias     — reject if current price is now on the WRONG side
   //                       of the fast bias EMA at shift=0 (price gapped or
   //                       reversed against the TS direction).
   //
   // Parameters:
   //   ts_direction : 1 (LONG) or -1 (SHORT) from the prior TS evaluation.
   //
   // Returns : ts_direction if all TE conditions pass, 0 if any check fails.
   //==========================================================================
   int EvaluateTE(int ts_direction)
   {
      if(ts_direction == 0) return 0;

      // 1-3. Reuse the existing filter suite (spread / time / news / ATR guard).
      //      These always evaluate live conditions (no shift involved), so they
      //      are appropriate for confirming the execution moment is clean.
      if(!CheckFilters())
      {
         if(m_settings.DebugFlow)
            PrintFormat("[TE FILTER FAIL] TE rejected by live filters: %s", m_diag_last_reason);
         return 0;
      }

      // 4. Basic price-direction check at shift=0 (forming candle).
      //    Confirm the current close (best available for shift=0) is still on
      //    the correct side of the fast bias EMA.  This catches gaps against
      //    the TS direction.
      int hf = BiasFastHandle();
      if(hf != INVALID_HANDLE)
      {
         double price    = iClose(m_symbol, PERIOD_CURRENT, 0);
         double ema_fast = GetMAVal(hf, 0, 0);

         if(ema_fast != 0.0)
         {
            bool price_ok = (ts_direction == 1) ? (price > ema_fast) : (price < ema_fast);
            if(!price_ok)
            {
               m_diag_last_reason = "TE_PRICE_DIRECTION";
               if(m_settings.DebugFlow)
                  PrintFormat("[TE REJECT] Price %.5f vs EMA %.5f does not confirm %s direction",
                              price, ema_fast, (ts_direction > 0 ? "BUY" : "SELL"));
               return 0;
            }
         }
      }

      if(m_settings.DebugFlow)
         PrintFormat("[TE PASS] TE conditions confirmed at shift=0 for %s",
                     (ts_direction > 0 ? "BUY" : "SELL"));

      return ts_direction;
   }
   // === EvaluateTE: END ===

   int BiasFastHandle() {
      return (m_settings.BiasFastID==0)?h_ema1 : (m_settings.BiasFastID==1)?h_ema2 : (m_settings.BiasFastID==2)?h_ema3 : h_ema4;
   }

   int BiasSlowHandle() {
      return (m_settings.BiasSlowID==0)?h_ema1 : (m_settings.BiasSlowID==1)?h_ema2 : (m_settings.BiasSlowID==2)?h_ema3 : h_ema4;
   }

   // --- UTILS ---
   int GetSlope(int handle) {
      // In this EA, slope checks are currently only used on MA handles.
      double c = GetMAVal(handle, 1);
      double p = GetMAVal(handle, 2);
      return (c > p) ? 1 : (c < p) ? -1 : 0;
   }

   //+------------------------------------------------------------------+
   //| 260304_PR2: Phase-Based Bias Calculation                        |
   //| Uses market phase detection to determine trading bias           |
   //| Requires PhaseDetectionEnabled = true                           |
   //+------------------------------------------------------------------+
   int GetBias_PhaseBased(const int v_shift = 1)
   {
      // Validate that phase detection is enabled
      if(!m_settings.PhaseDetectionEnabled)
      {
         if(m_settings.DebugFlow)
            Print("[260304_BIAS] ERROR: BIAS_AUTO_PHASE selected but PhaseDetectionEnabled=false");
         return 0;  // No bias - configuration error
      }
      
      // Detect current market phase
      EMarketPhase current_phase = DetectMarketPhase(v_shift);
      
      // Update diagnostics
      m_diag_last_phase = current_phase;
      
      // Check phase stability if required
      if(m_settings.RequireMinPhaseConfirm)
      {
         bool is_stable = ConfirmPhaseStability(current_phase, m_settings.MinPhaseConfirmBars);
         
         if(!is_stable)
         {
            if(m_settings.DebugFlow)
               PrintFormat("[260304_BIAS] Phase %s not stable (%d/%d bars) - no bias", 
                           EnumToString(current_phase), 
                           m_diag_phase_confirm_bars, 
                           m_settings.MinPhaseConfirmBars);
            return 0;  // Phase not stable enough
         }
      }
      
      // Block UNORDERED phase if configured
      if(current_phase == PHASE_UNORDERED && m_settings.BlockUnorderedPhase)
      {
         if(m_settings.DebugFlow)
            Print("[260304_BIAS] UNORDERED phase blocked - no clear market structure");
         return 0;  // No bias in choppy markets
      }
      
      // Determine bias based on phase
      int bias = 0;
      
      // Get EMA values to determine direction within phase
      double ema13 = GetMAVal(h_ema2, v_shift, 0);  // EMA2 = 13-period
      double ema34 = GetMAVal(h_ema3, v_shift, 0);  // EMA3 = 34-period
      double ema89 = GetMAVal(h_ema4, v_shift, 0);  // EMA4 = 89-period
      
      if(ema13 == EMPTY_VALUE || ema34 == EMPTY_VALUE || ema89 == EMPTY_VALUE)
      {
         if(m_settings.DebugFlow)
            Print("[260304_BIAS] ERROR: Invalid EMA values");
         return 0;
      }
      
      double tolerance = 2.0 * SymbolInfoDouble(m_symbol, SYMBOL_POINT);  // 2 pips
      
      // Map phase to bias direction
      switch(current_phase)
      {
         case PHASE_TRENDING:
            // TRENDING: EMAs fully stacked
            if(ema13 > ema34 + tolerance && ema34 > ema89 + tolerance)
            {
               bias = 1;  // LONG (bullish trend)
               if(m_settings.DebugFlow)
                  Print("[260304_BIAS] TRENDING Bullish → LONG bias");
            }
            else if(ema89 > ema34 + tolerance && ema34 > ema13 + tolerance)
            {
               bias = -1;  // SHORT (bearish trend)
               if(m_settings.DebugFlow)
                  Print("[260304_BIAS] TRENDING Bearish → SHORT bias");
            }
            break;
            
         case PHASE_EMERGING:
            // EMERGING: Trend forming (EMA4 sandwiched)
            if(ema13 > ema89 + tolerance && ema89 > ema34 + tolerance)
            {
               bias = 1;  // LONG (bullish emerging)
               if(m_settings.DebugFlow)
                  Print("[260304_BIAS] EMERGING Bullish → LONG bias (trend forming)");
            }
            else if(ema34 > ema89 + tolerance && ema89 > ema13 + tolerance)
            {
               bias = -1;  // SHORT (bearish emerging)
               if(m_settings.DebugFlow)
                  Print("[260304_BIAS] EMERGING Bearish → SHORT bias (trend forming)");
            }
            break;
            
         case PHASE_UNORDERED:
            // UNORDERED: No bias (choppy/mixed structure)
            bias = 0;
            if(m_settings.DebugFlow)
               Print("[260304_BIAS] UNORDERED phase → NO BIAS");
            break;
      }
      
      return bias;
   }

   //+------------------------------------------------------------------+
   //| 260304_PR1: Detect Market Phase Based on 3 Slowest EMAs         |
   //| Uses EMA2(13), EMA3(34), EMA4(89) to classify market structure  |
   //| EMERGING phase: EMA4(89) sandwiched between EMA2(13) and EMA3(34)|
   //+------------------------------------------------------------------+
   EMarketPhase DetectMarketPhase(const int shift = 1)
   {
      // Get the 3 key EMAs for phase classification
      double ema13 = GetMAVal(h_ema2, shift, 0);  // EMA2 = 13-period
      double ema34 = GetMAVal(h_ema3, shift, 0);  // EMA3 = 34-period
      double ema89 = GetMAVal(h_ema4, shift, 0);  // EMA4 = 89-period
      
      if(ema13 == EMPTY_VALUE || ema34 == EMPTY_VALUE || ema89 == EMPTY_VALUE)
      {
         if(m_settings.DebugFlow)
            Print("[260304_PHASE] ERROR: Invalid EMA values at shift ", shift);
         return PHASE_UNORDERED;
      }
      
      // Tolerance for "approximate equality" to avoid false transitions on flat markets
      double tolerance = 2.0 * SymbolInfoDouble(m_symbol, SYMBOL_POINT);  // 2 pips
      
      //==========================================================================
      // BULLISH PHASE DETECTION
      //==========================================================================
      
      // TRENDING Bullish: 13 > 34 > 89 (fully stacked ascending order)
      if(ema13 > ema34 + tolerance && ema34 > ema89 + tolerance)
      {
         if(m_settings.DebugFlow)
            PrintFormat("[260304_PHASE] TRENDING Bullish (13=%.5f > 34=%.5f > 89=%.5f) - Established uptrend", 
                        ema13, ema34, ema89);
         return PHASE_TRENDING;
      }
      
      // EMERGING Bullish: 13 > 89 > 34 
      // EMA4(89) is SANDWICHED between EMA2(13) and EMA3(34)
      // EMA34 is approaching EMA89 from below - trend forming
      if(ema13 > ema89 + tolerance && ema89 > ema34 + tolerance)
      {
         if(m_settings.DebugFlow)
            PrintFormat("[260304_PHASE] EMERGING Bullish (13=%.5f > 89=%.5f > 34=%.5f) - EMA34 converging to EMA89, trend forming", 
                        ema13, ema89, ema34);
         return PHASE_EMERGING;
      }
      
      //==========================================================================
      // BEARISH PHASE DETECTION
      //==========================================================================
      
      // TRENDING Bearish: 89 > 34 > 13 (fully stacked descending order)
      if(ema89 > ema34 + tolerance && ema34 > ema13 + tolerance)
      {
         if(m_settings.DebugFlow)
            PrintFormat("[260304_PHASE] TRENDING Bearish (89=%.5f > 34=%.5f > 13=%.5f) - Established downtrend", 
                        ema89, ema34, ema13);
         return PHASE_TRENDING;
      }
      
      // EMERGING Bearish: 34 > 89 > 13
      // EMA4(89) is SANDWICHED between EMA3(34) and EMA2(13)
      // EMA13 is approaching EMA89 from above - trend forming
      if(ema34 > ema89 + tolerance && ema89 > ema13 + tolerance)
      {
         if(m_settings.DebugFlow)
            PrintFormat("[260304_PHASE] EMERGING Bearish (34=%.5f > 89=%.5f > 13=%.5f) - EMA13 converging to EMA89, trend forming", 
                        ema34, ema89, ema13);
         return PHASE_EMERGING;
      }
      
      //==========================================================================
      // UNORDERED (Default): None of the above patterns matched
      // EMAs are crossed/mixed - no clear directional structure
      //==========================================================================
      
      if(m_settings.DebugFlow)
         PrintFormat("[260304_PHASE] UNORDERED (13=%.5f, 34=%.5f, 89=%.5f) - Choppy/mixed structure", 
                     ema13, ema34, ema89);
      
      return PHASE_UNORDERED;
   }
   
   //+------------------------------------------------------------------+
   //| 260304_PR1: Confirm Phase Stability                             |
   //| Requires N consecutive bars in same phase to avoid whipsaws     |
   //+------------------------------------------------------------------+
   bool ConfirmPhaseStability(const EMarketPhase current_phase, const int min_bars)
   {
      if(min_bars <= 1) return true;  // No confirmation required
      
      // Count consecutive bars in current phase
      int confirmed_bars = 1;  // Current bar (shift=1) counts as 1
      
      for(int i = 2; i <= min_bars; i++)
      {
         EMarketPhase past_phase = DetectMarketPhase(i);
         
         if(past_phase == current_phase)
         {
            confirmed_bars++;
         }
         else
         {
            // Phase changed - not stable
            if(m_settings.DebugFlow)
               PrintFormat("[260304_PHASE] UNSTABLE: Current=%s, Bar[%d]=%s (need %d consecutive bars)", 
                           EnumToString(current_phase), i, EnumToString(past_phase), min_bars);
            
            m_diag_phase_confirm_bars = confirmed_bars;
            return false;
         }
      }
      
      // Phase is stable for required number of bars
      m_diag_phase_confirm_bars = confirmed_bars;
      
      if(m_settings.DebugFlow)
         PrintFormat("[260304_PHASE] STABLE: %s confirmed for %d/%d consecutive bars", 
                     EnumToString(current_phase), confirmed_bars, min_bars);
      
      return true;
   }
   
   //+------------------------------------------------------------------+
   //| 260304_PR1: Update Phase Diagnostics (passive observation only) |
   //+------------------------------------------------------------------+
   void UpdatePhaseDiagnostics(const int v_shift = 1)
   {
      // If phase detection is disabled, reset diagnostics
      if(!m_settings.PhaseDetectionEnabled)
      {
         m_diag_last_phase = PHASE_UNORDERED;
         m_diag_phase_confirm_bars = 0;
         return;
      }
      
      // Detect current phase
      m_diag_last_phase = DetectMarketPhase(v_shift);
      
      // Check phase stability if required
      if(m_settings.RequireMinPhaseConfirm)
      {
         ConfirmPhaseStability(m_diag_last_phase, m_settings.MinPhaseConfirmBars);
      }
      else
      {
         m_diag_phase_confirm_bars = 0;  // Stability check disabled
      }
   }

   //+------------------------------------------------------------------+
   //| 260304_PR4: Entry Layer Detection                                |
   //| Classifies pullback depth based on which EMAs price touched      |
   //|                                                                  |
   //| Returns:                                                         |
   //|   LAYER_1_WEAK   - Price within tolerance of EMA1/EMA2 zone     |
   //|   LAYER_2_MEDIUM - Price within tolerance of EMA2/EMA3 zone     |
   //|   LAYER_3_STRONG - Price within tolerance of EMA3/EMA4 zone     |
   //|   LAYER_NONE     - Detection disabled or no EMA touch found     |
   //|                                                                  |
   //| Note: Detection is PASSIVE - results stored in diagnostic field |
   //|       but do not affect trade execution (filtering not enabled) |
   //+------------------------------------------------------------------+
   EEntryLayer DetectEntryLayer(const int v_shift = 1)
   {
      if(!m_settings.EnableLayerDetection) return LAYER_NONE;

      double ema1 = GetMAVal(h_ema1, v_shift, 0);
      double ema2 = GetMAVal(h_ema2, v_shift, 0);
      double ema3 = GetMAVal(h_ema3, v_shift, 0);
      double ema4 = GetMAVal(h_ema4, v_shift, 0);

      if(ema1 == EMPTY_VALUE || ema1 == 0.0 ||
         ema2 == EMPTY_VALUE || ema2 == 0.0 ||
         ema3 == EMPTY_VALUE || ema3 == 0.0 ||
         ema4 == EMPTY_VALUE || ema4 == 0.0)
         return LAYER_NONE;

      double price = iClose(m_symbol, PERIOD_CURRENT, v_shift);
      double tol   = m_settings.LayerTouchTolerancePips * SymbolInfoDouble(m_symbol, SYMBOL_POINT) * 10.0;

      // Layer 3: price touches EMA3 or EMA4 zone (checked first - deepest layer has priority)
      if(MathAbs(price - ema3) <= tol || MathAbs(price - ema4) <= tol)
      {
         if(m_settings.DebugFlow)
            PrintFormat("[260304_ENTRY] STRONG layer detected: Price=%.5f touched EMA3(%.5f) tolerance=%.5f",
                        price, ema3, tol);
         return LAYER_3_STRONG;
      }

      // Layer 2: price touches EMA2 or EMA3 zone
      if(MathAbs(price - ema2) <= tol || MathAbs(price - ema3) <= tol)
      {
         if(m_settings.DebugFlow)
            PrintFormat("[260304_ENTRY] MEDIUM layer detected: Price=%.5f touched EMA2(%.5f) tolerance=%.5f",
                        price, ema2, tol);
         return LAYER_2_MEDIUM;
      }

      // Layer 1: price touches EMA1 or EMA2 zone
      if(MathAbs(price - ema1) <= tol || MathAbs(price - ema2) <= tol)
      {
         if(m_settings.DebugFlow)
            PrintFormat("[260304_ENTRY] WEAK layer detected: Price=%.5f touched EMA1(%.5f) tolerance=%.5f",
                        price, ema1, tol);
         return LAYER_1_WEAK;
      }

      return LAYER_NONE;
   }

   //+------------------------------------------------------------------+
   //| 260304_PR3: Update Layer Diagnostics (passive observation only) |
   //+------------------------------------------------------------------+
   void UpdateLayerDiagnostics(const int v_shift = 1)
   {
      if(!m_settings.EnableLayerDetection)
      {
         m_diag_last_layer    = LAYER_NONE;
         m_diag_layer_distance = 0.0;
         return;
      }

      m_diag_last_layer = DetectEntryLayer(v_shift);
   }
};

//+--END OF SEA_SignalEngine.mqh--+