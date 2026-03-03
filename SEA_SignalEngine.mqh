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

   double GetAdaptiveRecoveryPips(ENUM_TIMEFRAMES tf, string symbol)
   {
      return GetAdaptivePullbackPips(tf, symbol) * 0.6;
   }

   double GetAdaptiveEmaDivPips(ENUM_TIMEFRAMES tf, string symbol)
   {
      bool is_jpy = (StringFind(symbol, "JPY") >= 0);
      double base = 0;
      switch(tf)
      {
         case PERIOD_M1:  base = 0.5; break;
         case PERIOD_M5:  base = 1.0; break;
         case PERIOD_M15: base = 2.0; break;
         case PERIOD_H1:  base = 3.0; break;
         case PERIOD_H4:  base = 5.0; break;
         case PERIOD_D1:  base = 10.0; break;
         default:         base = 2.0;
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

   // HARD GATE 2: Multi-bar recovery detection
   bool Check_Gate_Recovery(const int bias)
   {
      if(m_settings.Gate_Recovery.mode == GATE_SCALE_OFF) return true;

      double min_recovery_pips = 0;
      switch(m_settings.Gate_Recovery.mode)
      {
         case GATE_SCALE_AUTO_TF:
            min_recovery_pips = GetAdaptiveRecoveryPips(_Period, m_symbol) * m_settings.Gate_Recovery.value;
            break;
         case GATE_SCALE_FIXED:
            min_recovery_pips = m_settings.Gate_Recovery.value;
            break;
         default: break;
      }

      double pip = PipSize();
      double min_recovery = min_recovery_pips * pip;
      int lookback = m_settings.Gate_RecoveryLookback;

      double start_price = iClose(m_symbol, PERIOD_CURRENT, lookback);
      double end_price   = iClose(m_symbol, PERIOD_CURRENT, 1);
      double recovery    = (bias == 1) ? (end_price - start_price) : (start_price - end_price);

      if(recovery < min_recovery) { m_diag_last_reason = "GATE_NO_RECOVERY"; return false; }
      return true;
   }

   // HARD GATE 3: EMA divergence (uses adaptive scaling, updates RRM_MinDivPips)
   bool Check_Gate_EmaDiv(const int bias)
   {
      if(m_settings.Gate_EmaDiv.mode == GATE_SCALE_OFF) return true;

      double min_div_pips = 0;
      switch(m_settings.Gate_EmaDiv.mode)
      {
         case GATE_SCALE_AUTO_TF:
            min_div_pips = GetAdaptiveEmaDivPips(_Period, m_symbol) * m_settings.Gate_EmaDiv.value;
            break;
         case GATE_SCALE_FIXED:
            min_div_pips = m_settings.Gate_EmaDiv.value;
            break;
         default: break;
      }

      m_settings.RRM_MinDivPips = min_div_pips;
      return Check_RRM_EmaDiv(bias);
   }

   // HARD GATE 4: Candle direction confirmation
   bool Check_Gate_CandleDirection(const int bias)
   {
      if(m_settings.Gate_CandleDirection.mode == GATE_SCALE_OFF) return true;

      int check_shift = m_settings.Gate_CandleCheckShift;
      // Check check_shift bar, and optionally check_shift-1 bar as fallback
      int s_from = check_shift;
      int s_to   = MathMax(1, check_shift - 1);
      for(int s = s_from; s >= s_to; s--)
      {
         double open_price  = iOpen(m_symbol, PERIOD_CURRENT, s);
         double close_price = iClose(m_symbol, PERIOD_CURRENT, s);
         if(bias == 1 && close_price > open_price) return true;  // bullish candle confirms LONG
         if(bias == -1 && close_price < open_price) return true; // bearish candle confirms SHORT
      }

      m_diag_last_reason = "GATE_CANDLE_DIR";
      return false;
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

      // Use Vertical/Bar Shift from Settings (0 for current bar, 1 for closed bar)
      int v_shift = m_settings.ma_v_shift;
      
      // 2. Determine MASTER BIAS (Strategy)
      int bias = 0;
      
      // === MANUAL BIAS MODE ===
      if(m_settings.BiasMode == BIAS_MANUAL) {
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

      // 3b. RRM mandatory gates (only active when enabled in settings)
      if(m_settings.RRM_RequirePullbackReclaim) {
         if(!Check_RRM_PullbackReclaim(bias)) { 
            m_diag_last_reason="RRM_PULLBACK";
            m_reject_gate++;
            return 0; 
         }
      }
      if(m_settings.RRM_RequireEmaDiv) {
         if(!Check_RRM_EmaDiv(bias)) { 
            m_diag_last_reason="RRM_EMA_DIV";
            m_reject_gate++;
            return 0; 
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
      if(m_settings.Gate_Recovery.mode != GATE_SCALE_OFF) {
         if(!Check_Gate_Recovery(bias)) {
            if(m_settings.DebugFlow) Print("STEP 5 STRUCTURE: Recovery → REJECT (", m_diag_last_reason, ")");
            m_reject_gate++;
            return 0;
         }
         if(m_settings.DebugFlow) Print("STEP 5 STRUCTURE: Recovery → PASS");
      }
      if(m_settings.Gate_EmaDiv.mode != GATE_SCALE_OFF) {
         if(!Check_Gate_EmaDiv(bias)) {
            if(m_settings.DebugFlow) Print("STEP 5 STRUCTURE: EMA Divergence → REJECT (", m_diag_last_reason, ")");
            m_reject_gate++;
            return 0;
         }
         if(m_settings.DebugFlow) Print("STEP 5 STRUCTURE: EMA Divergence → PASS");
      }
      if(m_settings.Gate_CandleDirection.mode != GATE_SCALE_OFF) {
         if(!Check_Gate_CandleDirection(bias)) {
            if(m_settings.DebugFlow) Print("STEP 5 STRUCTURE: Candle Direction → REJECT (", m_diag_last_reason, ")");
            m_reject_gate++;
            return 0;
         }
         if(m_settings.DebugFlow) Print("STEP 5 STRUCTURE: Candle Direction → PASS");
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
      CAST_VOTE(m_settings.Ind_Psar_Enabled,   m_settings.Ind_Psar_Weight,   Check_PSAR(bias, v_shift))
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
            bool pass = Check_PSAR(bias, v_shift);
            vote_details += StringFormat(" | PSAR: sar=%.5f cl=%.5f %s(w=%d)", p, cl, pass?"PASS":"FAIL", m_settings.Ind_Psar_Weight);
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
};

//+--END OF SEA_SignalEngine.mqh--+