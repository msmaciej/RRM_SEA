//+------------------------------------------------------------------+
//|                                             SEA_SignalEngine.mqh |
//|                              MJS Institutional Trading Solutions |
//|                                                                  |
//| Purpose: Signal Logic, Indicator Management, Voting & Filters    |
//| Status:  PRODUCTION READY (Revision M: Full Dual Shift Support)  |
//+------------------------------------------------------------------+
// SAVE AS UTF-16 LE WITH BOM
//+------------------------------------------------------------------+
// PURPOSE:
// Core signal processing engine implementing 9-step pipeline for trade signals
//
// SIGNAL PROCESSING PIPELINE:
// Step 1: PRE-FILTERS - Check spread, time filters
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
// EvaluateTS() returns: 1 (LONG), -1 (SHORT), 0 (NO TRADE)
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

// Granular per-reason rejection statistics for EvaluateTS()
struct SRejectionStats {
   int total_bars;

   // Non-directional gates (passed + rejected)
   int passed_spread,       rejected_spread;
   int passed_time,         rejected_time;
   int passed_news,         rejected_news;
   int passed_candle_body,  rejected_candle_body;
   int passed_ci,           rejected_ci;
   int passed_vrc,          rejected_vrc;           // VRC (low volatility)

   // Bias & Layer (passed + rejected)
   int passed_bias,         rejected_bias;
   int passed_phase,        rejected_phase;
   int passed_layer_none,   rejected_layer_none;
   int passed_layer_blocked,rejected_layer_blocked;

   // Directional indicators (passed + rejected)
   int passed_emasig,  rejected_emasig;
   int passed_macd,    rejected_macd;
   int passed_psar,    rejected_psar;
   int passed_cci,     rejected_cci;
   int passed_rsi,     rejected_rsi;
   int passed_adx,     rejected_adx;
   int passed_mfi,     rejected_mfi;
   int passed_sto,     rejected_sto;
   int passed_bb,      rejected_bb;
   int passed_p123,    rejected_p123;
   int passed_ross,    rejected_ross;

   int signals_confirmed;
};

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

   // 260304_PR1: Phase Detection Diagnostics
   EMarketPhase m_diag_last_phase;       // Last detected market phase
   int          m_diag_phase_confirm_bars; // Number of consecutive bars in current phase

   // 260304_PR3: Layer Detection Diagnostics
   EEntryLayer  m_diag_last_layer;       // Last detected entry layer
   double       m_diag_layer_distance;   // Distance to nearest EMA layer in pips

   EEntryLayer  m_diag_last_entry_layer;  // 260304_PR4: Last detected entry layer
   bool         m_layer_allowed;          // 260304_PR7: Whether current entry layer is allowed in current phase
   EEntryLayer  m_current_layer;          // Layer detected by STRAT_LAYER_DETECTION signal

   // --- 2c. STRUCTURE GATE DIAGNOSTICS ---
   int         m_active_layer;       // Active EMA layer (1/2/3/0=none)
   bool        m_pullback_found;     // Was a pullback detected?
   int         m_pullback_bar;       // Bar index of pullback extreme
   double      m_pullback_extreme;   // Price at pullback extreme
   bool        m_recovery_detected;  // Was recovery detected?

   // --- 2d. REJECTION STATISTICS ---
   int         m_bars_evaluated;     // Total bars evaluated by EvaluateTS()
   int         m_signals_generated;  // Signals returned (TS != 0)
   int         m_reject_filter;      // Rejections at pre-filter step (spread, time, news)
   int         m_reject_bias;        // Rejections at bias step (no trend, signal mismatch)
   int         m_reject_gate;        // Rejections at gate step (HTF, RRM, structure gates)
   int         m_reject_votes;       // Rejections at vote step

   // --- 2e. GRANULAR REJECTION STATISTICS ---
   SRejectionStats m_stats;

   // --- 2f. PSAR FLIP TRACKING ---
   datetime m_psar_last_flip_time_bull;  // Timestamp of last bullish flip (0 = none recorded)
   datetime m_psar_last_flip_time_bear;  // Timestamp of last bearish flip (0 = none recorded)

   // --- 2g. ADX HISTORY TRACKING (for DYNAMIC_PERCENTILE and PHASE_AWARE modes) ---
   double   m_adxHistory[];              // Rolling buffer of ADX values
   int      m_adxHistorySize;            // Current number of entries in buffer
   int      m_adxHistoryMaxSize;         // Maximum buffer size (from ADX_Lookback)
   double   m_cachedADXThreshold;        // Last calculated dynamic threshold
   datetime m_lastADXCalculation;        // Time of last threshold recalculation

   // --- 2h. VRC (Volatility Regime Classifier) STATE ---
   double   m_atrHistory[100];           // Rolling ATR buffer for percentile calculation
   int      m_atrHistorySize;            // Current history size
   datetime m_lastVRCCalculation;        // Last cache update timestamp
   double   m_cachedVRCLowThreshold;     // Cached ATR value at low percentile

   // Simplified buffer access for cleaner logic code

   // Version 1: No validity checking (backward compatible)
   double GetVal(int handle, int shift, int buffer_num=0) const {
      bool ignored_valid = false;
      return GetVal(handle, shift, buffer_num, ignored_valid);
   }

   // Version 2: With validity checking via MQL5 reference parameter
   double GetVal(int handle, int shift, int buffer_num, bool &out_valid) const {
      if(handle == INVALID_HANDLE) {
         out_valid = false;
         return 0.0;
      }

      double b[1];
      int result = CopyBuffer(handle, buffer_num, shift, 1, b);

      if(result <= 0) {
         int error = GetLastError();

         // Distinguish temporary vs permanent errors
         // MQL5 error codes: 4066 = ERR_HISTORY_WILL_UPDATED, 4073 = ERR_NO_HISTORY_DATA
         if(error == 4066 || error == 4073) {
            // Temporary - data loading
            out_valid = false;
            return 0.0;
         }

         // Permanent error - log if DebugFlow enabled
         if(m_settings.DebugFlow) {
            PrintFormat("[IND_ERROR] Handle=%d Buffer=%d Shift=%d Error=%d",
                        handle, buffer_num, shift, error);
         }
         out_valid = false;
         return 0.0;
      }

      out_valid = true;
      return b[0];
   }

   // NOTE: In MT5, the iMA() 'ma_shift' parameter already shifts the indicator line.
   // Therefore CopyBuffer() returns a series aligned to that shifted plot.
   // IMPORTANT: Do NOT apply ma_h_shift a second time in logic reads.

   // Version 1: No validity checking (backward compatible)
   double GetMAVal(const int handle, const int shift, const int buffer_num=0) {
      bool ignored_valid = false;
      return GetVal(handle, shift, buffer_num, ignored_valid);
   }

   // Version 2: With validity checking via MQL5 reference parameter
   double GetMAVal(const int handle, const int shift, const int buffer_num, bool &out_valid) {
      return GetVal(handle, shift, buffer_num, out_valid);
   }

   // Version 1: No error reporting (backward compatible)
   bool GetBuf(int handle, int buf_idx, int shift, double &arr[]) {
      int ignored_error = 0;
      return GetBuf(handle, buf_idx, shift, arr, ignored_error);
   }

   // Version 2: With error reporting via MQL5 reference parameter
   bool GetBuf(int handle, int buf_idx, int shift, double &arr[], int &out_error) {
      if(handle == INVALID_HANDLE) {
         out_error = -1;
         return false;
      }

      int result = CopyBuffer(handle, buf_idx, shift, 1, arr);
      if(result <= 0) {
         out_error = GetLastError();
         return false;
      }

      out_error = 0;
      return true;
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
      bool result = (bias == 1) ? (p > e) : (p < e);
      if(m_settings.DebugFlow)
         PrintFormat("[IND_EMASIG] ENABLED | Price=%.5f EMA=%.5f | Result: %s",
                     p, e, result ? "PASS" : "FAIL");
      return result;
   }
   
   // Vote 2: ADX Strength (Trend Strength)
   // Supports three modes: STATIC (fixed threshold), DYNAMIC_PERCENTILE (percentile-based adaptive),
   // and PHASE_AWARE (different thresholds per market phase).
   bool Check_ADX(int shift) {
      double adx = GetVal(h_adx, shift);

      // Update rolling history for dynamic modes (skip for static — no history needed)
      if(m_settings.ADX_Mode != ADX_MODE_STATIC)
         UpdateADXHistory(adx);

      double threshold = 0.0;
      string modeStr   = "";

      switch(m_settings.ADX_Mode) {
         case ADX_MODE_STATIC:
         default:
            threshold = (double)m_settings.T_Adx;
            modeStr   = "STATIC";
            break;

         case ADX_MODE_DYNAMIC_PERCENTILE:
            // Recalculate every 4 hours or when buffer has just filled
            if(m_adxHistorySize >= m_adxHistoryMaxSize ||
               TimeCurrent() - m_lastADXCalculation >= 14400) {
               m_cachedADXThreshold = CalculateADXPercentile(m_settings.ADX_Percentile);
               m_lastADXCalculation = TimeCurrent();
            }
            threshold = m_cachedADXThreshold;
            modeStr   = StringFormat("DYNAMIC_P%.0f", m_settings.ADX_Percentile);
            break;

         case ADX_MODE_PHASE_AWARE:
            threshold = GetPhaseAwareThreshold(m_diag_last_phase);
            modeStr   = StringFormat("PHASE_%s", EnumToString(m_diag_last_phase));
            break;
      }

      bool result = adx >= threshold;
      // Cache the effective threshold for diagnostic display (GetVoteSnapshot, debug logs)
      m_cachedADXThreshold = threshold;
      if(m_settings.DebugFlow) {
         if(m_settings.Ind_Adx_Enabled)
            PrintFormat("[IND_ADX] ENABLED | Value=%.2f | Threshold=%.2f | Mode=%s | Result: %s",
                        adx, threshold, modeStr, result ? "PASS" : "FAIL");
         else
            Print("[IND_ADX] DISABLED - skipped");
      }
      return result;
   }

   // Vote 3: MACD — two-tier architecture (base mode + optional filters)
   //
   // MACD Indicator buffer outputs:
   //   Buffer 0 = MACD Main Line (fast EMA - slow EMA)
   //   Buffer 1 = MACD Signal Line (SMA of Main Line)
   //   Buffer 2 = MACD Histogram (Main - Signal)
   //
   bool Check_MACD(int bias, int shift) {
      if(!m_settings.Ind_Macd_Enabled) {
         if(m_settings.DebugFlow) Print("[IND_MACD] DISABLED - skipped");
         return false;
      }

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

      if(!base_pass) {
         if(m_settings.DebugFlow)
            PrintFormat("[IND_MACD] ENABLED | Main=%.5f Signal=%.5f | Result: FAIL (base mode)",
                        m, s);
         return false;
      }

      // ══════════════════════════════════════════════════════════
      // STEP 2: Advanced Filters (optional add-ons)
      // ══════════════════════════════════════════════════════════

      // Filter A: Slope (MACD accelerating)
      if(m_settings.MacdRequireSlope) {
         double m_prev = GetVal(h_macd, shift + 1, 0);
         double slope  = m - m_prev;

         // Check minimum slope threshold (if configured)
         if(m_settings.MacdSlopeMin > 0 && MathAbs(slope) < m_settings.MacdSlopeMin) {
            if(m_settings.DebugFlow)
               PrintFormat("[IND_MACD] ENABLED | Main=%.5f Signal=%.5f | Result: FAIL (slope min)",
                           m, s);
            return false;
         }

         // Check direction matches bias
         bool accelerating = (bias == 1) ? (slope > 0) : (slope < 0);
         if(!accelerating) {
            if(m_settings.DebugFlow)
               PrintFormat("[IND_MACD] ENABLED | Main=%.5f Signal=%.5f | Result: FAIL (slope dir)",
                           m, s);
            return false;
         }
      }

      // Filter B: Divergence (price vs MACD disagreement)
      if(m_settings.MacdRequireDivergence) {
         if(!CheckMACDDivergence(bias, shift)) {
            if(m_settings.DebugFlow)
               PrintFormat("[IND_MACD] ENABLED | Main=%.5f Signal=%.5f | Result: FAIL (divergence)",
                           m, s);
            return false;
         }
      }

      // Filter C: Hook (histogram reversal)
      if(m_settings.MacdRequireHook) {
         double h_prev = GetVal(h_macd, shift + 1, 0) - GetVal(h_macd, shift + 1, 1);
         bool hook = (bias == 1) ? (h > 0 && h_prev <= 0) : (h < 0 && h_prev >= 0);
         if(!hook) {
            if(m_settings.DebugFlow)
               PrintFormat("[IND_MACD] ENABLED | Main=%.5f Signal=%.5f | Result: FAIL (hook)",
                           m, s);
            return false;
         }
      }

      if(m_settings.DebugFlow)
         PrintFormat("[IND_MACD] ENABLED | Main=%.5f Signal=%.5f | Result: PASS",
                     m, s);
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
      if(!m_settings.Ind_Rsi_Enabled) {
         if(m_settings.DebugFlow) Print("[IND_RSI] DISABLED - skipped");
         return true;
      }
      double r = GetVal(h_rsi, shift);
      bool result;
      
      if(m_settings.RsiMode == RSI_FILTER_EXTREME) {
         // Buy if NOT Overbought, Sell if NOT Oversold
         result = (bias==1) ? (r < m_settings.T_RsiOB) : (r > m_settings.T_RsiOS);
      }
      else if(m_settings.RsiMode == RSI_TREND_ABOVE_50) {
         result = (bias==1) ? (r > 50) : (r < 50);
      }
      else {
         // Cross Level Mode
         result = (bias==1) ? (r > m_settings.T_RsiOS) : (r < m_settings.T_RsiOB);
      }
      if(m_settings.DebugFlow)
         PrintFormat("[IND_RSI] ENABLED | Value=%.2f | Result: %s",
                     r, result ? "PASS" : "FAIL");
      return result;
   }
   
   // Vote 5: CCI (Zero or Impulse)
   bool Check_CCI(int bias, int shift) {
      double c = GetVal(h_cci, shift);
      bool result;
      if(m_settings.CciMode == CCI_TREND_ZERO) result = (bias==1) ? (c > 0) : (c < 0);
      else result = (bias==1) ? (c > 100) : (c < -100);
      if(m_settings.DebugFlow) {
         if(m_settings.Ind_Cci_Enabled)
            PrintFormat("[IND_CCI] ENABLED | Value=%.2f | Result: %s",
                        c, result ? "PASS" : "FAIL");
         else
            Print("[IND_CCI] DISABLED - skipped");
      }
      return result;
   }
   
   // Vote 6: MFI (Money Flow)
   bool Check_MFI(int bias, int shift) {
      double mfi = GetVal(h_mfi, shift);
      bool result = (bias==1) ? (mfi > m_settings.T_MfiOB) : (mfi < m_settings.T_MfiOS);
      if(m_settings.DebugFlow) {
         if(m_settings.Ind_Mfi_Enabled)
            PrintFormat("[IND_MFI] ENABLED | Value=%.2f | Result: %s",
                        mfi, result ? "PASS" : "FAIL");
         else
            Print("[IND_MFI] DISABLED - skipped");
      }
      return result;
   }
   
   // Vote 7: Stochastic
   bool Check_Sto(int bias, int shift) {
      double k = GetVal(h_sto, shift, 0);
      double d = GetVal(h_sto, shift, 1);
      bool result;
      
      if(m_settings.StoMode == STO_CROSS_SIGNAL) 
         result = (bias==1) ? (k > d) : (k < d);
      else
         // Zone Filter: Buy if NOT overbought
         result = (bias==1) ? (k < m_settings.T_StoOB) : (k > m_settings.T_StoOS);

      if(m_settings.DebugFlow) {
         if(m_settings.Ind_Sto_Enabled)
            PrintFormat("[IND_STOCH] ENABLED | K=%.2f D=%.2f | Result: %s",
                        k, d, result ? "PASS" : "FAIL");
         else
            Print("[IND_STOCH] DISABLED - skipped");
      }
      return result;
   }
   
   // Vote 8: Bollinger Bands
   bool Check_BB(int bias, int shift) {
      double mid = GetVal(h_bb, shift, 0);
      double cl  = iClose(m_symbol, PERIOD_CURRENT, shift);
      bool result;
      
      if(m_settings.BbMode == BB_TREND_FOLLOW) {
         result = (bias==1) ? (cl > mid) : (cl < mid);
      }
      else {
         // Mean Reversion: Price touched Lower/Upper Band
         double lower = GetVal(h_bb, shift, 2);
         double upper = GetVal(h_bb, shift, 1);
         double low   = iLow(m_symbol, PERIOD_CURRENT, shift);
         double high  = iHigh(m_symbol, PERIOD_CURRENT, shift);
         result = (bias==1) ? (low <= lower) : (high >= upper);
      }
      if(m_settings.DebugFlow) {
         if(m_settings.Ind_Bb_Enabled)
            PrintFormat("[IND_BB] ENABLED | Mid=%.5f Close=%.5f | Result: %s",
                        mid, cl, result ? "PASS" : "FAIL");
         else
            Print("[IND_BB] DISABLED - skipped");
      }
      return result;
   }
   
   // Vote 9: PSAR (basic price vs. PSAR position check)
   bool Check_PSAR(int bias, int shift) {
      double p = GetVal(h_psar, shift);
      double cl = iClose(m_symbol, PERIOD_CURRENT, shift);

      bool result = (bias==1) ? (cl > p) : (cl < p);

      if(m_settings.DebugFlow) {
         datetime bar_time = iTime(m_symbol, PERIOD_CURRENT, shift);
         PrintFormat("[PSAR_DOT_CHECK] Bar: %s | Bias: %s | PSAR=%.5f | Close=%.5f | Dot position: %s | Result: %s",
                     TimeToString(bar_time, TIME_DATE|TIME_MINUTES),
                     (bias > 0 ? "LONG" : "SHORT"),
                     p, cl,
                     (cl > p ? "BELOW price" : "ABOVE price"),
                     (result ? "PASS" : "FAIL (dot on wrong side)"));
      }

      return result;
   }

   // PSAR flip helper: detect if a flip occurred at the given bar shift.
   // A flip occurs when PSAR crosses from above price to below price (bullish: +1)
   // or from below price to above price (bearish: -1).
   // Returns 1 (bullish flip), -1 (bearish flip), or 0 (no flip / insufficient data).
   // Uses closed bars only: checks shift vs shift+1 (shift+1 is the previous closed bar).
   int DetectPSARFlipAt(int shift) {
      // Log handle status periodically
      static datetime last_log_time = 0;
      datetime current_time = TimeCurrent();
      
      if(current_time - last_log_time > 86400) { // Log once per day
         last_log_time = current_time;
         PrintFormat("[PSAR_HEALTH] Date: %s | Handle: %d | Valid: %s",
                     TimeToString(current_time, TIME_DATE),
                     h_psar,
                     (h_psar != INVALID_HANDLE) ? "YES" : "NO");
      }
      // Check if handle is still valid
      if(h_psar == INVALID_HANDLE) {
         if(m_settings.DebugFlow)
            PrintFormat("[PSAR_ERROR] Handle became INVALID! Need to reinitialize.");
         return 0;
      }
      
      bool psar_curr_valid = false;
      bool psar_prev_valid = false;

      double psar_curr = GetVal(h_psar, shift, 0, psar_curr_valid);
      double psar_prev = GetVal(h_psar, shift + 1, 0, psar_prev_valid);

      if(!psar_curr_valid || !psar_prev_valid) {
         if(m_settings.DebugFlow)
            PrintFormat("[PSAR_FLIP_DETECT] shift=%d | SKIP: PSAR data not ready (history loading)", shift);
         return 0;
      }

      double cl_curr = iClose(m_symbol, PERIOD_CURRENT, shift);
      double cl_prev = iClose(m_symbol, PERIOD_CURRENT, shift + 1);

      if(cl_curr == 0.0 || cl_prev == 0.0) {
         if(m_settings.DebugFlow)
            PrintFormat("[PSAR_FLIP_DETECT] shift=%d | SKIP: close price not available", shift);
         return 0;
      }

      if(m_settings.DebugFlow)
         PrintFormat("[PSAR_FLIP_DETECT] shift=%d | psar_curr=%.5f cl_curr=%.5f psar_prev=%.5f cl_prev=%.5f",
                     shift, psar_curr, cl_curr, psar_prev, cl_prev);

      bool curr_bullish = (cl_curr > psar_curr);
      bool prev_bullish = (cl_prev > psar_prev);

      int flip = 0;
      if(curr_bullish && !prev_bullish) flip =  1;   // Bullish flip: PSAR moved below price
      if(!curr_bullish && prev_bullish) flip = -1;   // Bearish flip: PSAR moved above price

      if(m_settings.DebugFlow)
         PrintFormat("[PSAR_FLIP_DETECT] curr_bullish=%s prev_bullish=%s -> result=%s",
                     (curr_bullish ? "true" : "false"),
                     (prev_bullish ? "true" : "false"),
                     (flip == 1 ? "BULLISH FLIP" : (flip == -1 ? "BEARISH FLIP" : "NO FLIP (same side)")));

      if(m_settings.DebugFlow && flip != 0) {
         datetime bar_time = iTime(m_symbol, PERIOD_CURRENT, shift);
         PrintFormat("[PSAR_FLIP_DETECT] ══════════════════════════════════");
         PrintFormat("[PSAR_FLIP_DETECT] Bar: %s (shift=%d)",
                     TimeToString(bar_time, TIME_DATE|TIME_MINUTES), shift);
         PrintFormat("[PSAR_FLIP_DETECT] Flip type: %s",
                     (flip == 1 ? "BULLISH (dot moved BELOW price)" : "BEARISH (dot moved ABOVE price)"));
         PrintFormat("[PSAR_FLIP_DETECT] Previous bar: PSAR=%.5f Close=%.5f (close %s PSAR)",
                     psar_prev, cl_prev, (prev_bullish ? "ABOVE" : "BELOW"));
         PrintFormat("[PSAR_FLIP_DETECT] Current bar:  PSAR=%.5f Close=%.5f (close %s PSAR)",
                     psar_curr, cl_curr, (curr_bullish ? "ABOVE" : "BELOW"));
      }

      return flip;
   }

   // PSAR flip tracker: call once per bar close to record the most recent flip.
   // Stores direction-specific timestamps so bullish and bearish flips are tracked independently.
   void UpdatePSARFlipTracking(int shift = 1) {
      if(m_settings.DebugFlow)
         Print("[DEBUG_TEST] UpdatePSARFlipTracking() CALLED");
      int flip = DetectPSARFlipAt(shift);
      if(flip != 0) {
         datetime flip_time = iTime(m_symbol, PERIOD_CURRENT, shift);
         if(flip == 1) {
            m_psar_last_flip_time_bull = flip_time;
            if(m_settings.DebugFlow)
               PrintFormat("[PSAR_FLIP_TRACK] BULLISH flip REGISTERED at %s (stored in m_psar_last_flip_time_bull)",
                           TimeToString(flip_time, TIME_DATE|TIME_MINUTES));
         }
         else if(flip == -1) {
            m_psar_last_flip_time_bear = flip_time;
            if(m_settings.DebugFlow)
               PrintFormat("[PSAR_FLIP_TRACK] BEARISH flip REGISTERED at %s (stored in m_psar_last_flip_time_bear)",
                           TimeToString(flip_time, TIME_DATE|TIME_MINUTES));
         }
      }
   }

   // Returns the number of bars elapsed since the last recorded PSAR flip in the given bias direction,
   // measured from current_shift. Returns INT_MAX if no flip has been recorded for that direction.
   // bias: 1 = bullish, -1 = bearish.
   int GetBarsSinceLastFlip(int bias, int current_shift) {
      datetime flip_time = (bias == 1) ? m_psar_last_flip_time_bull : m_psar_last_flip_time_bear;
      if(flip_time == 0) return INT_MAX;
      // Find the bar index of the flip time
      int flip_bar = iBarShift(m_symbol, PERIOD_CURRENT, flip_time, false);
      if(flip_bar < 0) return INT_MAX;
      int elapsed = flip_bar - current_shift;
      // If elapsed is negative, the flip is in the future relative to current_shift (shouldn't occur)
      return (elapsed < 0) ? INT_MAX : elapsed;
   }

   // Vote 9 (enhanced): PSAR with countdown-based flip validation.
   // Passes only if:
   //   1. PSAR dot is on the correct side of price (basic position check)
   //   2. A flip in the matching direction has been recorded
   //   3. The flip occurred within the last Vote_PsarFlipDelay bars
   bool Check_PSAR_WithFlip(int bias, int shift) {
      if(m_settings.DebugFlow) {
         Print("[DEBUG_TEST] Check_PSAR_WithFlip() CALLED");
         PrintFormat("[DEBUG_TEST] bias=%d shift=%d DebugFlow=%s",
                     bias, shift, m_settings.DebugFlow ? "TRUE" : "FALSE");
      }

      // Fast-path: persistent mode (-1) — check dot position only, no flip tracking
      if(m_settings.Vote_PsarFlipDelay == -1) {
         bool result = Check_PSAR(bias, shift);
         if(m_settings.DebugFlow)
            PrintFormat("[PSAR_FLIP_CHECK] PERSISTENT mode: dot check only → %s", result ? "PASS" : "FAIL");
         return result;
      }

      // START DEBUG LOGGING BANNER
      if(m_settings.DebugFlow) {
         datetime eval_bar_time = iTime(m_symbol, PERIOD_CURRENT, shift);
         PrintFormat("[PSAR_FLIP_CHECK] ===========================================");
         PrintFormat("[PSAR_FLIP_CHECK] Evaluating bar: %s (shift=%d)",
                     TimeToString(eval_bar_time, TIME_DATE|TIME_MINUTES), shift);
         PrintFormat("[PSAR_FLIP_CHECK] Required bias: %s", (bias > 0 ? "LONG" : "SHORT"));
      }

      // 1. PSAR dot must be on correct side NOW
      double psar_val  = GetVal(h_psar, shift);
      double close_val = iClose(m_symbol, PERIOD_CURRENT, shift);
      bool dot_correct = Check_PSAR(bias, shift);

      if(!dot_correct) {
         m_diag_last_reason = "PSAR_DOT_WRONG_SIDE";

         if(m_settings.DebugFlow) {
            PrintFormat("[PSAR_FLIP_CHECK] STEP 1 FAILED: DOT WRONG SIDE");
            PrintFormat("[PSAR_FLIP_CHECK]    PSAR=%.5f | Close=%.5f | Dot is %s",
                        psar_val, close_val,
                        (close_val > psar_val ? "BELOW price (bullish)" : "ABOVE price (bearish)"));
            PrintFormat("[PSAR_FLIP_CHECK]    Need: %s | Got: %s",
                        (bias > 0 ? "dot BELOW price" : "dot ABOVE price"),
                        (close_val > psar_val ? "dot BELOW price" : "dot ABOVE price"));
         }

         return false;
      }

      if(m_settings.DebugFlow)
         PrintFormat("[PSAR_FLIP_CHECK] STEP 1 PASSED: Dot on correct side");

      // 2. Check if a flip was recorded for this direction
      datetime flip_time = (bias > 0) ? m_psar_last_flip_time_bull : m_psar_last_flip_time_bear;

      // Display flip countdown status
      if(m_settings.DebugFlow) {
         if(flip_time == 0) {
            PrintFormat("[PSAR_FLIP_CHECK] STEP 2: No %s flip recorded yet",
                        (bias > 0 ? "BULLISH" : "BEARISH"));
         } else {
            int bars_elapsed   = GetBarsSinceLastFlip(bias, shift);
            int bars_remaining = m_settings.Vote_PsarFlipDelay - bars_elapsed;
            bool is_valid      = (bars_elapsed <= m_settings.Vote_PsarFlipDelay);

            PrintFormat("[PSAR_FLIP_CHECK] STEP 2: Flip recorded at %s",
                        TimeToString(flip_time, TIME_DATE|TIME_MINUTES));
            PrintFormat("[PSAR_FLIP_CHECK]    Flip age: %d bars | Delay limit: %d bars | Remaining: %d bars",
                        bars_elapsed,
                        m_settings.Vote_PsarFlipDelay,
                        bars_remaining);
            PrintFormat("[PSAR_FLIP_CHECK]    Status: %s",
                        is_valid ? "VALID (within delay window)" : "EXPIRED (too old)");
         }
      }

      if(flip_time == 0) {
         m_diag_last_reason = StringFormat("PSAR_NO_FLIP_RECORDED (bias=%d)", bias);

         if(m_settings.DebugFlow) {
            PrintFormat("[PSAR_FLIP_CHECK] STEP 2 FAILED: NO FLIP RECORDED");
            PrintFormat("[PSAR_FLIP_CHECK]    No %s flip has been registered yet",
                        (bias > 0 ? "bullish" : "bearish"));
            PrintFormat("[PSAR_FLIP_CHECK]    m_psar_last_flip_time_%s = 0",
                        (bias > 0 ? "bull" : "bear"));
         }

         return false;
      }

      if(m_settings.DebugFlow)
         PrintFormat("[PSAR_FLIP_CHECK] STEP 2 PASSED: Flip recorded at %s",
                     TimeToString(flip_time, TIME_DATE|TIME_MINUTES));

      // 3. Calculate bars since flip
      int flip_bar   = iBarShift(m_symbol, PERIOD_CURRENT, flip_time, false);
      int bars_since = (flip_bar >= 0) ? (flip_bar - shift) : INT_MAX;
      int delay      = m_settings.Vote_PsarFlipDelay;

      if(m_settings.DebugFlow) {
         PrintFormat("[PSAR_FLIP_CHECK] STEP 3: Calculate flip age");
         PrintFormat("[PSAR_FLIP_CHECK]    Flip time: %s", TimeToString(flip_time, TIME_DATE|TIME_MINUTES));
         PrintFormat("[PSAR_FLIP_CHECK]    Flip bar index: %d", flip_bar);
         PrintFormat("[PSAR_FLIP_CHECK]    Current shift: %d", shift);
         PrintFormat("[PSAR_FLIP_CHECK]    Bars since flip: %d", bars_since);
         PrintFormat("[PSAR_FLIP_CHECK]    Delay setting: %d bars", delay);
      }

      if(bars_since == INT_MAX) {
         m_diag_last_reason = "PSAR_FLIP_INVALID";

         if(m_settings.DebugFlow)
            PrintFormat("[PSAR_FLIP_CHECK] STEP 3 FAILED: iBarShift returned invalid index");

         return false;
      }

      // 4. Check if flip is within delay window
      if(bars_since > delay) {
         m_diag_last_reason = StringFormat("PSAR_FLIP_EXPIRED (bars_since=%d, delay=%d)",
                                           bars_since, delay);

         if(m_settings.DebugFlow) {
            PrintFormat("[PSAR_FLIP_CHECK] STEP 3 FAILED: FLIP EXPIRED");
            PrintFormat("[PSAR_FLIP_CHECK]    %d bars elapsed > %d delay window",
                        bars_since, delay);
         }

         return false;
      }

      // SUCCESS
      if(m_settings.DebugFlow) {
         PrintFormat("[PSAR_FLIP_CHECK] STEP 3 PASSED: Flip within delay window");
         PrintFormat("[PSAR_FLIP_CHECK] ===========================================");
         PrintFormat("[PSAR_FLIP_CHECK] ALL CHECKS PASSED");
         PrintFormat("[PSAR_FLIP_CHECK]    %s flip from %s is valid (%d bars ago, delay=%d)",
                     (bias > 0 ? "Bullish" : "Bearish"),
                     TimeToString(flip_time, TIME_DATE|TIME_MINUTES),
                     bars_since, delay);
      }

      return true;
   }

   
   // Vote 10: Pattern 1-2-3 (Breakout)
   bool Check_P123(int bias, int shift) {
      // 1. Get most recent Upper and Lower Fractals
      double last_up   = GetFractalPrice(0); // 0 = UPPER
      double last_down = GetFractalPrice(1); // 1 = LOWER
      double close     = iClose(m_symbol, PERIOD_CURRENT, shift);
      
      bool result = false;
      // Buy: Breakout above last Upper Fractal
      if(bias == 1  && last_up > 0   && close > last_up)   result = true;
      // Sell: Breakout below last Lower Fractal
      if(bias == -1 && last_down > 0 && close < last_down) result = true;
      
      if(m_settings.DebugFlow) {
         if(m_settings.Ind_P123_Enabled)
            PrintFormat("[IND_P123] ENABLED | Result: %s", result ? "PASS" : "FAIL");
         else
            Print("[IND_P123] DISABLED - skipped");
      }
      if(!result) m_diag_last_reason = "P123_NO_FRACTAL_BREAKOUT"; // no fractal breakout found
      return result;
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
      bool result = (fractalBreakout && trendSlope == bias);

      if(m_settings.DebugFlow) {
         if(m_settings.Ind_Ross_Enabled)
            PrintFormat("[IND_ROSS] ENABLED | Result: %s", result ? "PASS" : "FAIL");
         else
            Print("[IND_ROSS] DISABLED - skipped");
      }
      return result;
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

   //+------------------------------------------------------------------+
   //| Calculate slope direction with configurable threshold            |
   //+------------------------------------------------------------------+
   int CalculateSlope(double curr, double prev, double min_threshold)
   {
      double change = curr - prev;
      double abs_change = MathAbs(change);

      // Check if movement exceeds threshold
      if(abs_change <= min_threshold)
         return 0; // Flat (within noise range)

      // Determine direction
      return (change > 0) ? 1 : -1;
   }

   //+------------------------------------------------------------------+
   //| Get adaptive threshold based on TF and pair                      |
   //+------------------------------------------------------------------+
   double GetAdaptiveThresholdPips()
   {
      // === TIMEFRAME COMPONENT ===
      ENUM_TIMEFRAMES tf = Period();
      double tf_multiplier = 1.0;

      switch(tf)
      {
         case PERIOD_M1:  tf_multiplier = 0.3; break;  // Very sensitive
         case PERIOD_M5:  tf_multiplier = 0.5; break;
         case PERIOD_M15: tf_multiplier = 0.8; break;
         case PERIOD_M30: tf_multiplier = 1.0; break;
         case PERIOD_H1:  tf_multiplier = 1.5; break;
         case PERIOD_H4:  tf_multiplier = 2.5; break;
         case PERIOD_D1:  tf_multiplier = 4.0; break;
         default:         tf_multiplier = 1.0;
      }

      // === PAIR COMPONENT ===
      string symbol = m_symbol;
      double pair_base = 0.5; // Default base threshold in pips

      // Major pairs (tight spreads, need tighter thresholds)
      if(StringFind(symbol, "EURUSD") >= 0 ||
         StringFind(symbol, "GBPUSD") >= 0 ||
         StringFind(symbol, "USDJPY") >= 0 ||
         StringFind(symbol, "USDCHF") >= 0)
         pair_base = 0.5;

      // Cross pairs (wider spreads, need looser thresholds)
      else if(StringFind(symbol, "EURJPY") >= 0 ||
              StringFind(symbol, "GBPJPY") >= 0 ||
              StringFind(symbol, "EURGBP") >= 0)
         pair_base = 0.8;

      // Commodity currencies
      else if(StringFind(symbol, "AUD") >= 0 ||
              StringFind(symbol, "NZD") >= 0 ||
              StringFind(symbol, "CAD") >= 0)
         pair_base = 0.7;

      // Gold/metals (higher pip values)
      else if(StringFind(symbol, "XAU") >= 0 ||
              StringFind(symbol, "GOLD") >= 0)
         pair_base = 2.0;

      // Silver
      else if(StringFind(symbol, "XAG") >= 0 ||
              StringFind(symbol, "SILVER") >= 0)
         pair_base = 1.5;

      // Crypto (if supported)
      else if(StringFind(symbol, "BTC") >= 0 ||
              StringFind(symbol, "ETH") >= 0)
         pair_base = 10.0;

      // === PRESET ADJUSTMENTS ===
      double threshold = pair_base * tf_multiplier;

      // RRM preset is stricter - reduce threshold by 20%
      if(m_settings.Preset == PRESET_RRM)
         threshold *= 0.8;

      return threshold;
   }

   //+------------------------------------------------------------------+
   //| Get minimum slope threshold (adaptive or fixed)                  |
   //+------------------------------------------------------------------+
   double GetMinSlopeThreshold(double ema_curr_fast, double ema_curr_slow)
   {
      if(!m_settings.UseSlopeThreshold)
         return 0.0; // No threshold - any movement counts

      // === PERCENTAGE MODE ===
      if(m_settings.SlopeMeasureMode == SLOPE_MEASURE_PERCENT)
      {
         // 0.01% threshold (e.g., EMA at 1.08000 must move 0.000108 price units ~ 1.08 pips)
         double avg_ema = (ema_curr_fast + ema_curr_slow) / 2.0;
         return avg_ema * 0.0001; // 0.01% of EMA value
      }

      // === PIPS MODE ===
      // Adaptive or fixed threshold
      double threshold_pips = m_settings.SlopeThresholdAdaptive
                              ? GetAdaptiveThresholdPips()
                              : m_settings.SlopeThresholdPips;

      // Convert to price units
      double pip = PipSize();
      return threshold_pips * pip;
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
      m_diag_last_atr_pips = 0.0;

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

      // Initialize STRAT_LAYER_DETECTION layer
      m_current_layer = LAYER_NONE;

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

      ZeroMemory(m_stats);

      // Initialize PSAR flip tracking
      m_psar_last_flip_time_bull = 0;
      m_psar_last_flip_time_bear = 0;

      // Initialize ADX history tracking
      ArrayResize(m_adxHistory, 0);
      m_adxHistorySize      = 0;
      m_adxHistoryMaxSize   = 100;
      m_cachedADXThreshold  = 20.0;
      m_lastADXCalculation  = 0;

      // Initialize VRC history tracking
      m_atrHistorySize         = 0;
      m_lastVRCCalculation     = 0;
      m_cachedVRCLowThreshold  = 0.0;
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
   //
   // 260308_PR: layer_bitfield may contain multiple layer flags OR-combined.
   // All active layers in the bitfield must pass the phase-layer rules.
   //
   // Phase-layer filtering rules:
   //   UNORDERED → Block ALL layers (L1, L2, L3)  — choppy/mixed market, no clear trend
   //   EMERGING  → ALLOW L1/L2 only; BLOCK L3     — trend forming, avoid deep pullbacks
   //   TRENDING  → ALLOW L1/L2/L3 (ALL layers)    — strong established trend, all depths valid
   bool IsLayerAllowed(EEntryLayer layer_bitfield, EMarketPhase phase) const
   {
      if(!m_settings.PhaseDetectionEnabled || !m_settings.EnableLayerDetection)
         return true;  // Filtering disabled - all layers allowed

      if(layer_bitfield == LAYER_NONE)
         return false;  // No layer detected - nothing to allow

      bool is_emerging = (phase == PHASE_EMERGING || phase == PHASE_EMERGING_UP || phase == PHASE_EMERGING_DN);
      bool is_trending = (phase == PHASE_TRENDING || phase == PHASE_TRENDING_UP || phase == PHASE_TRENDING_DN);

      if(phase == PHASE_UNORDERED)
      {
         // Choppy/mixed market → Block ALL (L1, L2, L3)
         return false;
      }
      else if(is_emerging)
      {
         // Trend forming but not confirmed → ALLOW L1/L2 only; BLOCK L3 (STRONG)
         // Deep pullbacks (L3/Shark) are too risky before the trend is established.
         // 260308_PR: If L3 flag is set in the bitfield, the whole signal is blocked.
         if(IsLayerActive(layer_bitfield, LAYER_3_STRONG))
            return false;  // L3 component blocked in EMERGING
         return (IsLayerActive(layer_bitfield, LAYER_1_WEAK) || IsLayerActive(layer_bitfield, LAYER_2_MEDIUM));
      }
      else if(is_trending)
      {
         // Strong established trend → ALLOW ALL layers (L1/L2/L3)
         // Deep pullbacks (L3/Shark) are valid — the trend has the strength to recover
         return true;
      }

      return false;
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

   // Returns granular per-reason rejection stats for system analysis report
   // Return by value instead of reference
   SRejectionStats GetStats() const { return m_stats; }

   // Returns the number of currently enabled indicator votes.
   int CountEnabledIndicators() const
   {
      return GetEnabledIndicatorCount(m_settings);
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

   // Prints a sorted summary of top rejection reasons to the MT5 log.
   // Call from OnDeinit() to diagnose why trades are being filtered.
   void PrintRejectionStatistics()
   {
      if(m_stats.total_bars == 0) return;

      Print("════════════════════════════════════════════════");
      Print("  REJECTION STATISTICS");
      Print("════════════════════════════════════════════════");
      PrintFormat("Bars evaluated: %d", m_stats.total_bars);
      PrintFormat("Signals confirmed: %d (%.2f%%)",
                  m_stats.signals_confirmed,
                  m_stats.signals_confirmed * 100.0 / m_stats.total_bars);
      Print("");
      Print("TOP REJECTION REASONS:");

      // Build sortable array of reason/count pairs
      struct SReason { string name; int count; double pct; };
      SReason reasons[23];
      int idx = 0;

      reasons[idx].name = "Phase=UNORDERED";
      reasons[idx].count = m_stats.rejected_phase;
      reasons[idx++].pct = m_stats.rejected_phase * 100.0 / m_stats.total_bars;

      reasons[idx].name = "Bias=0";
      reasons[idx].count = m_stats.rejected_bias;
      reasons[idx++].pct = m_stats.rejected_bias * 100.0 / m_stats.total_bars;

      reasons[idx].name = "Layer=NONE";
      reasons[idx].count = m_stats.rejected_layer_none;
      reasons[idx++].pct = m_stats.rejected_layer_none * 100.0 / m_stats.total_bars;

      reasons[idx].name = "Layer blocked";
      reasons[idx].count = m_stats.rejected_layer_blocked;
      reasons[idx++].pct = m_stats.rejected_layer_blocked * 100.0 / m_stats.total_bars;

      reasons[idx].name = "MACD";
      reasons[idx].count = m_stats.rejected_macd;
      reasons[idx++].pct = m_stats.rejected_macd * 100.0 / m_stats.total_bars;

      reasons[idx].name = "PSAR";
      reasons[idx].count = m_stats.rejected_psar;
      reasons[idx++].pct = m_stats.rejected_psar * 100.0 / m_stats.total_bars;

      reasons[idx].name = "CCI";
      reasons[idx].count = m_stats.rejected_cci;
      reasons[idx++].pct = m_stats.rejected_cci * 100.0 / m_stats.total_bars;

      reasons[idx].name = "EmaSig";
      reasons[idx].count = m_stats.rejected_emasig;
      reasons[idx++].pct = m_stats.rejected_emasig * 100.0 / m_stats.total_bars;

      reasons[idx].name = "RSI";
      reasons[idx].count = m_stats.rejected_rsi;
      reasons[idx++].pct = m_stats.rejected_rsi * 100.0 / m_stats.total_bars;

      reasons[idx].name = "ADX";
      reasons[idx].count = m_stats.rejected_adx;
      reasons[idx++].pct = m_stats.rejected_adx * 100.0 / m_stats.total_bars;

      reasons[idx].name = "Spread";
      reasons[idx].count = m_stats.rejected_spread;
      reasons[idx++].pct = m_stats.rejected_spread * 100.0 / m_stats.total_bars;

      reasons[idx].name = "Time filter";
      reasons[idx].count = m_stats.rejected_time;
      reasons[idx++].pct = m_stats.rejected_time * 100.0 / m_stats.total_bars;

      reasons[idx].name = "News filter";
      reasons[idx].count = m_stats.rejected_news;
      reasons[idx++].pct = m_stats.rejected_news * 100.0 / m_stats.total_bars;

      reasons[idx].name = "CandleBody";
      reasons[idx].count = m_stats.rejected_candle_body;
      reasons[idx++].pct = m_stats.rejected_candle_body * 100.0 / m_stats.total_bars;

      reasons[idx].name = "ChoppinessIdx";
      reasons[idx].count = m_stats.rejected_ci;
      reasons[idx++].pct = m_stats.rejected_ci * 100.0 / m_stats.total_bars;

      reasons[idx].name = "VRC";
      reasons[idx].count = m_stats.rejected_vrc;
      reasons[idx++].pct = m_stats.rejected_vrc * 100.0 / m_stats.total_bars;

      reasons[idx].name = "MFI";
      reasons[idx].count = m_stats.rejected_mfi;
      reasons[idx++].pct = m_stats.rejected_mfi * 100.0 / m_stats.total_bars;

      reasons[idx].name = "Stoch";
      reasons[idx].count = m_stats.rejected_sto;
      reasons[idx++].pct = m_stats.rejected_sto * 100.0 / m_stats.total_bars;

      reasons[idx].name = "BB";
      reasons[idx].count = m_stats.rejected_bb;
      reasons[idx++].pct = m_stats.rejected_bb * 100.0 / m_stats.total_bars;

      reasons[idx].name = "P123";
      reasons[idx].count = m_stats.rejected_p123;
      reasons[idx++].pct = m_stats.rejected_p123 * 100.0 / m_stats.total_bars;

      reasons[idx].name = "Ross";
      reasons[idx].count = m_stats.rejected_ross;
      reasons[idx++].pct = m_stats.rejected_ross * 100.0 / m_stats.total_bars;

      // Bubble sort descending by count
      for(int i = 0; i < idx - 1; i++) {
         for(int j = i + 1; j < idx; j++) {
            if(reasons[j].count > reasons[i].count) {
               SReason temp = reasons[i];
               reasons[i] = reasons[j];
               reasons[j] = temp;
            }
         }
      }

      // Print top 10 non-zero reasons
      int printed = 0;
      for(int i = 0; i < idx && printed < 10; i++) {
         if(reasons[i].count > 0) {
            PrintFormat("  %2d. %-20s: %5d bars (%.1f%%)",
                        printed + 1, reasons[i].name, reasons[i].count, reasons[i].pct);
            printed++;
         }
      }

      if(printed == 0)
         Print("  (no rejections recorded)");

      Print("════════════════════════════════════════════════");
   }


   void PrintEnhancedStatistics()
   {
      if(m_stats.total_bars == 0) return;
      Print("================================================================");
      Print("  EVALUATION STATISTICS REPORT");
      PrintFormat("  %s %s | %d bars evaluated", m_symbol, EnumToString(PERIOD_CURRENT), m_stats.total_bars);
      if(m_settings.Stats_FullEvaluation)
         Print("  Mode: FULL EVALUATION (all indicators per bar)");
      else
         Print("  Mode: WATERFALL (stop at first failure)");
      Print("================================================================");
      Print("");
      Print("SUMMARY:");
      PrintFormat("  Signals Confirmed : %d (%.2f%%)", m_stats.signals_confirmed, m_stats.signals_confirmed * 100.0 / m_stats.total_bars);
      PrintFormat("  Total Rejections  : %d (%.2f%%)", m_stats.total_bars - m_stats.signals_confirmed, (m_stats.total_bars - m_stats.signals_confirmed) * 100.0 / m_stats.total_bars);
      Print("");
      Print("================================================================");
      Print("1. NON-DIRECTIONAL GATES");
      Print("================================================================");
      PrintFormat("%-18s %-8s %7s %7s %7s   %s", "Gate", "Status", "Passed", "Failed", "Pass%", "Impact");
      Print("----------------------------------------------------------------");
      PrintGateStat("Spread",      m_settings.UseSpread,                          m_stats.passed_spread,        m_stats.rejected_spread,       StringFormat("%.1f pips max", m_settings.MaxSpread));
      PrintGateStat("Time Window", m_settings.UseTime,     m_stats.passed_time,          m_stats.rejected_time,         m_settings.UseTime ? StringFormat("%02d:00-%02d:00", m_settings.StartHr, m_settings.EndHr) : "(disabled)");
      PrintGateStat("News Filter", m_settings.UseNews,     m_stats.passed_news,          m_stats.rejected_news,         m_settings.UseNews  ? StringFormat("%dm pre/post", m_settings.NewsPre) : "(disabled)");
      Print("----------------------------------------------------------------");
      PrintFormat("Gates blocked: %d bars", m_stats.rejected_spread + m_stats.rejected_time + m_stats.rejected_news);
      Print("");
      Print("================================================================");
      Print("2. BIAS & LAYER DETECTION");
      Print("================================================================");
      PrintFormat("%-20s %-8s %7s %7s %7s   %s", "Component", "Status", "Passed", "Failed", "Pass%", "Impact");
      Print("----------------------------------------------------------------");
      PrintGateStat("Bias Detection",   true,                             m_stats.passed_bias,          m_stats.rejected_bias,         StringFormat("Mode: %s", EnumToString(m_settings.BiasMode)));
      PrintGateStat("Phase Check",      (m_settings.PhaseDetectionEnabled && m_settings.BlockUnorderedPhase), m_stats.passed_phase, m_stats.rejected_phase, m_settings.PhaseDetectionEnabled ? "BlockUnordered" : "(disabled)");
      PrintGateStat("Layer (none)",      m_settings.EnableLayerDetection, m_stats.passed_layer_none,    m_stats.rejected_layer_none,   m_settings.EnableLayerDetection ? "L1/L2/L3 pullback" : "(disabled)");
      PrintGateStat("Layer-Phase Rules", m_settings.EnableLayerDetection, m_stats.passed_layer_blocked, m_stats.rejected_layer_blocked, m_settings.EnableLayerDetection ? "L3 blocked in EMERGING" : "(disabled)");
      Print("----------------------------------------------------------------");
      PrintFormat("No-bias bars: %d", m_stats.rejected_bias);
      Print("");
      Print("================================================================");
      Print("3. DIRECTIONAL INDICATORS (Must agree with detected bias)");
      Print("================================================================");
      PrintFormat("%-14s %-8s %7s %7s %7s   %-12s %s", "Indicator", "Status", "Passed", "Failed", "Pass%", "Agreement", "Impact");
      Print("----------------------------------------------------------------");
      PrintIndicatorStat("EmaSig",     m_settings.Ind_EmaSig_Enabled, m_stats.passed_emasig, m_stats.rejected_emasig);
      PrintIndicatorStat("MACD",       m_settings.Ind_Macd_Enabled,   m_stats.passed_macd,   m_stats.rejected_macd);
      PrintIndicatorStat("PSAR",       m_settings.Ind_Psar_Enabled,   m_stats.passed_psar,   m_stats.rejected_psar);
      PrintIndicatorStat("CCI",        m_settings.Ind_Cci_Enabled,    m_stats.passed_cci,    m_stats.rejected_cci);
      PrintIndicatorStat("RSI",        m_settings.Ind_Rsi_Enabled,    m_stats.passed_rsi,    m_stats.rejected_rsi);
      PrintIndicatorStat("ADX",        m_settings.Ind_Adx_Enabled,    m_stats.passed_adx,    m_stats.rejected_adx);
      PrintIndicatorStat("MFI",        m_settings.Ind_Mfi_Enabled,    m_stats.passed_mfi,    m_stats.rejected_mfi);
      PrintIndicatorStat("Stochastic", m_settings.Ind_Sto_Enabled,    m_stats.passed_sto,    m_stats.rejected_sto);
      PrintIndicatorStat("BB",         m_settings.Ind_Bb_Enabled,     m_stats.passed_bb,     m_stats.rejected_bb);
      PrintIndicatorStat("P123",       m_settings.Ind_P123_Enabled,   m_stats.passed_p123,   m_stats.rejected_p123);
      PrintIndicatorStat("Ross Hook",  m_settings.Ind_Ross_Enabled,   m_stats.passed_ross,   m_stats.rejected_ross);
      PrintIndicatorStat("CandleBody", m_settings.Ind_CandleBody_Enabled, m_stats.passed_candle_body, m_stats.rejected_candle_body);
      PrintIndicatorStat("ChoppinessIdx", m_settings.Ind_CI_Enabled, m_stats.passed_ci, m_stats.rejected_ci);
      PrintIndicatorStat("VRC",          m_settings.Ind_VRC_Enabled, m_stats.passed_vrc, m_stats.rejected_vrc);
      Print("----------------------------------------------------------------");
      PrintFormat("Indicators: %d enabled (ALL must pass)", GetEnabledIndicatorCount(m_settings));
      Print("");
      Print("================================================================");
      Print("4. BOTTLENECK ANALYSIS (Ranked by impact)");
      Print("================================================================");
      PrintBottleneckAnalysis();
      Print("");
      Print("================================================================");
      Print("5. RECOMMENDATIONS");
      Print("================================================================");
      PrintRecommendations();
      Print("================================================================");
   }

   void PrintGateStat(string name, bool enabled, int passed, int failed, string note)
   {
      int    total    = passed + failed;
      double pass_pct = (total > 0) ? (passed * 100.0 / total) : 0.0;
      string status   = enabled ? "ON"  : "OFF";
      string impact   = "";
      if(!enabled) {
         impact = "(disabled)";
      } else if(total == 0 || (failed == 0 && total > 0)) {
         impact = "No blocks";
      } else if(m_stats.total_bars > 0) {
         double block_pct = failed * 100.0 / m_stats.total_bars;
         if(block_pct < 5)       impact = "Minor";
         else if(block_pct < 20) impact = StringFormat("%.1f%% blocked", block_pct);
         else                    impact = StringFormat("%.1f%% BLOCKED", block_pct);
      }
      if(enabled)
         PrintFormat("%-18s %-8s %7d %7d %6.1f%%   %s  (%s)", name, status, passed, failed, pass_pct, impact, note);
      else
         PrintFormat("%-18s %-8s %7s %7s %7s   %s", name, status, "-", "-", "-", impact);
   }

   void PrintIndicatorStat(string name, bool enabled, int passed, int failed)
   {
      if(!enabled) {
         PrintFormat("%-14s %-8s %7s %7s %7s   %-12s %s", name, "OFF", "-", "-", "-", "(disabled)", "-");
         return;
      }
      int    total    = passed + failed;
      double pass_pct = (total > 0) ? (passed * 100.0 / total) : 0.0;
      string agreement = (pass_pct >= 90) ? "Very High" : (pass_pct >= 75) ? "High" : (pass_pct >= 50) ? "Medium" : (pass_pct >= 25) ? "Low" : "Very Low";
      string impact    = (pass_pct >= 90) ? "Good"      : (pass_pct >= 70) ? "OK"   : (pass_pct >= 50) ? "Check"  : (pass_pct >= 25) ? "Issue" : "BLOCKER!";
      PrintFormat("%-14s %-8s %7d %7d %6.1f%%   %-12s %s", name, "ON", passed, failed, pass_pct, agreement, impact);
   }

   void PrintBottleneckAnalysis()
   {
      if(m_stats.total_bars == 0) return;
      struct SBottleneck { string name; int rejected; double pct; };
      SBottleneck bn[25]; // Gates(3) + Bias/Phase/Layer(4) + Indicators(13 + CandleBody + CI + VRC) = up to 22 entries
      int idx = 0;
      if(m_stats.rejected_spread > 0)         { bn[idx].name="Spread";         bn[idx].rejected=m_stats.rejected_spread;        bn[idx++].pct=m_stats.rejected_spread*100.0/m_stats.total_bars; }
      if(m_stats.rejected_time > 0)           { bn[idx].name="Time Window";    bn[idx].rejected=m_stats.rejected_time;          bn[idx++].pct=m_stats.rejected_time*100.0/m_stats.total_bars; }
      if(m_stats.rejected_news > 0)           { bn[idx].name="News Filter";    bn[idx].rejected=m_stats.rejected_news;          bn[idx++].pct=m_stats.rejected_news*100.0/m_stats.total_bars; }
      if(m_stats.rejected_bias > 0)           { bn[idx].name="Bias=0";         bn[idx].rejected=m_stats.rejected_bias;          bn[idx++].pct=m_stats.rejected_bias*100.0/m_stats.total_bars; }
      if(m_stats.rejected_phase > 0)          { bn[idx].name="Phase=UNORD";    bn[idx].rejected=m_stats.rejected_phase;         bn[idx++].pct=m_stats.rejected_phase*100.0/m_stats.total_bars; }
      if(m_stats.rejected_layer_none > 0)     { bn[idx].name="Layer=NONE";     bn[idx].rejected=m_stats.rejected_layer_none;    bn[idx++].pct=m_stats.rejected_layer_none*100.0/m_stats.total_bars; }
      if(m_stats.rejected_layer_blocked > 0)  { bn[idx].name="Layer blocked";  bn[idx].rejected=m_stats.rejected_layer_blocked; bn[idx++].pct=m_stats.rejected_layer_blocked*100.0/m_stats.total_bars; }
      if(m_settings.Ind_EmaSig_Enabled && m_stats.rejected_emasig > 0) { bn[idx].name="EmaSig";    bn[idx].rejected=m_stats.rejected_emasig; bn[idx++].pct=m_stats.rejected_emasig*100.0/m_stats.total_bars; }
      if(m_settings.Ind_Macd_Enabled   && m_stats.rejected_macd   > 0) { bn[idx].name="MACD";      bn[idx].rejected=m_stats.rejected_macd;   bn[idx++].pct=m_stats.rejected_macd*100.0/m_stats.total_bars; }
      if(m_settings.Ind_Psar_Enabled   && m_stats.rejected_psar   > 0) { bn[idx].name="PSAR";      bn[idx].rejected=m_stats.rejected_psar;   bn[idx++].pct=m_stats.rejected_psar*100.0/m_stats.total_bars; }
      if(m_settings.Ind_Cci_Enabled    && m_stats.rejected_cci    > 0) { bn[idx].name="CCI";       bn[idx].rejected=m_stats.rejected_cci;    bn[idx++].pct=m_stats.rejected_cci*100.0/m_stats.total_bars; }
      if(m_settings.Ind_Rsi_Enabled    && m_stats.rejected_rsi    > 0) { bn[idx].name="RSI";       bn[idx].rejected=m_stats.rejected_rsi;    bn[idx++].pct=m_stats.rejected_rsi*100.0/m_stats.total_bars; }
      if(m_settings.Ind_Adx_Enabled    && m_stats.rejected_adx    > 0) { bn[idx].name="ADX";       bn[idx].rejected=m_stats.rejected_adx;    bn[idx++].pct=m_stats.rejected_adx*100.0/m_stats.total_bars; }
      if(m_settings.Ind_Mfi_Enabled    && m_stats.rejected_mfi    > 0) { bn[idx].name="MFI";       bn[idx].rejected=m_stats.rejected_mfi;    bn[idx++].pct=m_stats.rejected_mfi*100.0/m_stats.total_bars; }
      if(m_settings.Ind_Sto_Enabled    && m_stats.rejected_sto    > 0) { bn[idx].name="Stochastic";bn[idx].rejected=m_stats.rejected_sto;    bn[idx++].pct=m_stats.rejected_sto*100.0/m_stats.total_bars; }
      if(m_settings.Ind_Bb_Enabled     && m_stats.rejected_bb     > 0) { bn[idx].name="BB";        bn[idx].rejected=m_stats.rejected_bb;     bn[idx++].pct=m_stats.rejected_bb*100.0/m_stats.total_bars; }
      if(m_settings.Ind_P123_Enabled   && m_stats.rejected_p123   > 0) { bn[idx].name="P123";      bn[idx].rejected=m_stats.rejected_p123;   bn[idx++].pct=m_stats.rejected_p123*100.0/m_stats.total_bars; }
      if(m_settings.Ind_Ross_Enabled   && m_stats.rejected_ross   > 0) { bn[idx].name="Ross Hook"; bn[idx].rejected=m_stats.rejected_ross;   bn[idx++].pct=m_stats.rejected_ross*100.0/m_stats.total_bars; }
      if(m_settings.Ind_CandleBody_Enabled && m_stats.rejected_candle_body > 0) { bn[idx].name="CandleBody"; bn[idx].rejected=m_stats.rejected_candle_body; bn[idx++].pct=m_stats.rejected_candle_body*100.0/m_stats.total_bars; }
      if(m_settings.Ind_CI_Enabled     && m_stats.rejected_ci     > 0) { bn[idx].name="ChoppinessIdx"; bn[idx].rejected=m_stats.rejected_ci; bn[idx++].pct=m_stats.rejected_ci*100.0/m_stats.total_bars; }
      if(m_settings.Ind_VRC_Enabled    && m_stats.rejected_vrc    > 0) { bn[idx].name="VRC";           bn[idx].rejected=m_stats.rejected_vrc; bn[idx++].pct=m_stats.rejected_vrc*100.0/m_stats.total_bars; }
      if(idx == 0) { Print("  (no rejections recorded)"); return; }
      for(int i = 0; i < idx-1; i++)
         for(int j = i+1; j < idx; j++)
            if(bn[j].rejected > bn[i].rejected) { SBottleneck tmp=bn[i]; bn[i]=bn[j]; bn[j]=tmp; }
      int show = (idx < 5) ? idx : 5;
      for(int i = 0; i < show; i++) {
         string sev = (bn[i].pct > 50) ? "PRIMARY" : (bn[i].pct > 20) ? "SECONDARY" : "MINOR";
         PrintFormat("  #%d: %-18s %5d bars (%.1f%%)  [%s]", i+1, bn[i].name, bn[i].rejected, bn[i].pct, sev);
      }
   }

   void PrintRecommendations()
   {
      if(m_stats.total_bars == 0) return;
      bool any_rec = false;
      if(m_settings.Ind_Psar_Enabled && m_stats.rejected_psar > m_stats.total_bars / 2) {
         any_rec = true;
         PrintFormat("Priority 1: PSAR is blocking %.1f%% of bars.", m_stats.rejected_psar * 100.0 / m_stats.total_bars);
         Print("  -> Consider disabling PSAR on higher timeframes.");
         Print("  -> PSAR is most effective on M5/M15 scalping.");
         Print("");
      }
      if(m_stats.rejected_bias > m_stats.total_bars / 5) {
         any_rec = true;
         PrintFormat("Priority 2: Bias=0 blocks %.1f%% of bars (ranging market).", m_stats.rejected_bias * 100.0 / m_stats.total_bars);
         PrintFormat("  -> Current bias mode: %s", EnumToString(m_settings.BiasMode));
         Print("  -> Consider a simpler bias mode or a more trending instrument.");
         Print("");
      }
      string worst_ind = ""; int worst_cnt = 0;
      if(m_settings.Ind_EmaSig_Enabled && m_stats.rejected_emasig > worst_cnt) { worst_cnt=m_stats.rejected_emasig; worst_ind="EmaSig"; }
      if(m_settings.Ind_Macd_Enabled   && m_stats.rejected_macd   > worst_cnt) { worst_cnt=m_stats.rejected_macd;   worst_ind="MACD"; }
      if(m_settings.Ind_Psar_Enabled   && m_stats.rejected_psar   > worst_cnt) { worst_cnt=m_stats.rejected_psar;   worst_ind="PSAR"; }
      if(m_settings.Ind_Cci_Enabled    && m_stats.rejected_cci    > worst_cnt) { worst_cnt=m_stats.rejected_cci;    worst_ind="CCI"; }
      if(m_settings.Ind_Rsi_Enabled    && m_stats.rejected_rsi    > worst_cnt) { worst_cnt=m_stats.rejected_rsi;    worst_ind="RSI"; }
      if(m_settings.Ind_Adx_Enabled    && m_stats.rejected_adx    > worst_cnt) { worst_cnt=m_stats.rejected_adx;    worst_ind="ADX"; }
      if(m_settings.Ind_Mfi_Enabled    && m_stats.rejected_mfi    > worst_cnt) { worst_cnt=m_stats.rejected_mfi;    worst_ind="MFI"; }
      if(m_settings.Ind_Sto_Enabled    && m_stats.rejected_sto    > worst_cnt) { worst_cnt=m_stats.rejected_sto;    worst_ind="Stochastic"; }
      if(m_settings.Ind_Bb_Enabled     && m_stats.rejected_bb     > worst_cnt) { worst_cnt=m_stats.rejected_bb;     worst_ind="BB"; }
      if(m_settings.Ind_P123_Enabled   && m_stats.rejected_p123   > worst_cnt) { worst_cnt=m_stats.rejected_p123;   worst_ind="P123"; }
      if(m_settings.Ind_Ross_Enabled   && m_stats.rejected_ross   > worst_cnt) { worst_cnt=m_stats.rejected_ross;   worst_ind="Ross Hook"; }
      if(m_settings.Ind_CandleBody_Enabled && m_stats.rejected_candle_body > worst_cnt) { worst_cnt=m_stats.rejected_candle_body; worst_ind="CandleBody"; }
      if(m_settings.Ind_CI_Enabled         && m_stats.rejected_ci         > worst_cnt) { worst_cnt=m_stats.rejected_ci;         worst_ind="ChoppinessIdx"; }
      if(m_settings.Ind_VRC_Enabled        && m_stats.rejected_vrc        > worst_cnt) { worst_cnt=m_stats.rejected_vrc;        worst_ind="VRC"; }
      if(worst_ind != "" && m_stats.total_bars > 0 && worst_cnt * 100.0 / m_stats.total_bars > 30) {
         any_rec = true;
         PrintFormat("Priority 3: %s is the top indicator bottleneck (%.1f%% blocked).", worst_ind, worst_cnt * 100.0 / m_stats.total_bars);
         PrintFormat("  -> Disable %s to test signal frequency impact.", worst_ind);
         Print("");
      }
      if(!any_rec)
         Print("  No critical bottlenecks detected. Configuration appears balanced.");
   }

   // --- VOTE SNAPSHOT (for Cockpit per-vote display) ---
   // Evaluates each enabled vote independently (BUY/SELL/FLAT) without changing internal state.
   void CaptureVoteSnapshots(SVoteSnapshot &out[], int &count, const int current_bias = 0)
   {
      int shift = m_settings.ma_v_shift;
      count = 0;
      ArrayResize(out, 16); // 15 possible indicators + 1 spare

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
         bool pass = (adx >= m_cachedADXThreshold);
         out[count].name    = "ADX";
         out[count].enabled = true;
         if(pass && m_diag_last_bias ==  1) { out[count].state = "BUY";  out[count].reason = StringFormat("(ADX=%.0f>=%.0f)", adx, m_cachedADXThreshold); }
         else if(pass && m_diag_last_bias == -1) { out[count].state = "SELL"; out[count].reason = StringFormat("(ADX=%.0f>=%.0f)", adx, m_cachedADXThreshold); }
         else                               { out[count].state = "FLAT"; out[count].reason = StringFormat("(ADX=%.0f%s%.0f)", adx, pass?">=":"<", m_cachedADXThreshold); }
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

      // ATR (volatility regime – non-directional vote)
      if(m_settings.Ind_Atr_Enabled && h_atr != INVALID_HANDLE)
      {
         double atr_pips = m_diag_last_atr_pips;
         bool   pass     = true;
         if(m_settings.ATR_VoteMinPips > 0.0 && atr_pips < m_settings.ATR_VoteMinPips) pass = false;
         if(m_settings.ATR_VoteMaxPips > 0.0 && atr_pips > m_settings.ATR_VoteMaxPips) pass = false;
         out[count].name    = "ATR";
         out[count].enabled = true;
         if(pass) { out[count].state = (current_bias == 1 ? "BUY" : (current_bias == -1 ? "SELL" : "FLAT")); out[count].reason = StringFormat("(ATR=%.1fpips ok)", atr_pips); }
         else     { out[count].state = "FLAT"; out[count].reason = StringFormat("(ATR=%.1fpips out-of-range)", atr_pips); }
         out[count].vote_result = pass ? 1 : -1;
         count++;
      }

      // CandleBody (overextension filter – non-directional vote)
      if(m_settings.Ind_CandleBody_Enabled)
      {
         bool pass = CheckCandleBodyIndicator();
         out[count].name    = "CBody";
         out[count].enabled = true;
         if(pass) { out[count].state = (current_bias == 1 ? "BUY" : (current_bias == -1 ? "SELL" : "FLAT")); out[count].reason = "(body ok)"; }
         else     { out[count].state = "FLAT"; out[count].reason = "(overextended)"; }
         out[count].vote_result = pass ? 1 : -1;
         count++;
      }

      // Choppiness Index (ranging market filter – non-directional vote)
      if(m_settings.Ind_CI_Enabled)
      {
         double ci_val = CalculateCI(shift);
         bool pass = (ci_val < m_settings.CI_RangingThreshold);
         out[count].name    = "CI";
         out[count].enabled = true;
         if(pass) { out[count].state = (current_bias == 1 ? "BUY" : (current_bias == -1 ? "SELL" : "FLAT")); out[count].reason = StringFormat("(CI=%.1f trending)", ci_val); }
         else     { out[count].state = "FLAT"; out[count].reason = StringFormat("(CI=%.1f ranging)", ci_val); }
         out[count].vote_result = pass ? 1 : -1;
         count++;
      }

      // VRC (low volatility filter – non-directional vote)
      if(m_settings.Ind_VRC_Enabled && h_atr != INVALID_HANDLE)
      {
         EVolatilityRegime regime = GetVolatilityRegime();
         double atr = GetVal(h_atr, shift, 0);

         out[count].name    = "VRC";
         out[count].enabled = true;

         if(regime == VOLATILITY_LOW) {
            out[count].state  = "FLAT";
            out[count].reason = StringFormat("(LOW volatility ATR=%.5f)", atr);
         } else {
            out[count].state  = (current_bias == 1 ? "BUY" : (current_bias == -1 ? "SELL" : "FLAT"));
            out[count].reason = StringFormat("(NORMAL volatility ATR=%.5f)", atr);
         }

         out[count].vote_result = (regime == VOLATILITY_LOW) ? -1 : 1;
         count++;
      }

      ArrayResize(out, count);
   }


   bool Init(ST_Settings &sets, string symbol) {
      m_settings = sets;
      m_symbol   = symbol;

      // Initialize ADX history tracking from settings
      m_adxHistoryMaxSize  = (m_settings.ADX_Lookback > 0 ? m_settings.ADX_Lookback : 100);
      ArrayResize(m_adxHistory, 0);
      m_adxHistorySize     = 0;
      m_cachedADXThreshold = (double)m_settings.T_Adx;
      m_lastADXCalculation = 0;

      ENUM_MA_METHOD method = (m_settings.MaType == METHOD_SMA) ? MODE_SMA : MODE_EMA;
      int h_shift = m_settings.ma_h_shift; // Horizontal Shift support
      
      // A. Create Standard Indicators (Using Dynamic Method and Horizontal Shift)
      h_ema1 = iMA(m_symbol, PERIOD_CURRENT, m_settings.P_Ema1, h_shift, method, PRICE_CLOSE);
      h_ema2 = iMA(m_symbol, PERIOD_CURRENT, m_settings.P_Ema2, h_shift, method, PRICE_CLOSE);
      h_ema3 = iMA(m_symbol, PERIOD_CURRENT, m_settings.P_Ema3, h_shift, method, PRICE_CLOSE);
      h_ema4 = iMA(m_symbol, PERIOD_CURRENT, m_settings.P_Ema4, h_shift, method, PRICE_CLOSE);

      // Create ATR for ATR voting indicator
      bool need_atr = m_settings.Ind_Atr_Enabled;
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

      if(need_psar && h_psar == INVALID_HANDLE) {
         PrintFormat("CRITICAL ERROR: Failed to create PSAR indicator (Step=%.4f Max=%.4f Error=%d)",
                     m_settings.P_PsarStep, m_settings.P_PsarMax, GetLastError());
         return false;
      }

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
         Print("CRITICAL ERROR: Failed to create ATR indicator (used for voting).");
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
   // This keeps user-facing inputs (MaxSpreadPips) meaningful across instruments.
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

   // --- 9b. CANDLE BODY OVEREXTENSION INDICATOR (voting) ---
   bool CheckCandleBodyIndicator() {
      if(!m_settings.Ind_CandleBody_Enabled) return true;

      // Calculate average body over past N bars (starting at shift 2 to exclude current bar)
      double sum_body = 0.0;
      int    period   = m_settings.CandleBody_AvgPeriod;
      for(int i = 2; i < period + 2; i++)
      {
         double o = iOpen(m_symbol, PERIOD_CURRENT, i);
         double c = iClose(m_symbol, PERIOD_CURRENT, i);
         sum_body += MathAbs(c - o);
      }
      double avg_body = sum_body / period;

      // Check the most recent closed candles for overextension
      for(int i = 1; i <= m_settings.CandleBody_CheckBars; i++)
      {
         double o    = iOpen(m_symbol, PERIOD_CURRENT, i);
         double c    = iClose(m_symbol, PERIOD_CURRENT, i);
         double body = MathAbs(c - o);
         if(body > avg_body * m_settings.CandleBody_MaxMult)
         {
            return false;
         }
      }
      return true;
   }

   //+------------------------------------------------------------------+
   //| UpdateADXHistory(): append ADX value to rolling history buffer  |
   //+------------------------------------------------------------------+
   void UpdateADXHistory(double currentADX) {
      if(m_adxHistorySize < m_adxHistoryMaxSize) {
         // Buffer not yet full — just append
         ArrayResize(m_adxHistory, m_adxHistorySize + 1);
         m_adxHistory[m_adxHistorySize] = currentADX;
         m_adxHistorySize++;
      } else {
         // Buffer full — shift left (remove oldest) and append newest
         for(int i = 0; i < m_adxHistoryMaxSize - 1; i++)
            m_adxHistory[i] = m_adxHistory[i + 1];
         m_adxHistory[m_adxHistoryMaxSize - 1] = currentADX;
      }
   }

   //+------------------------------------------------------------------+
   //| CalculateADXPercentile(): percentile of current ADX history      |
   //| Returns static threshold when history is too short (<10 bars)    |
   //+------------------------------------------------------------------+
   double CalculateADXPercentile(double percentile) {
      if(m_adxHistorySize < 10)
         return (double)m_settings.T_Adx;

      // Sort a copy of the history
      double sorted[];
      ArrayResize(sorted, m_adxHistorySize);
      ArrayCopy(sorted, m_adxHistory, 0, 0, m_adxHistorySize);
      ArraySort(sorted);

      // Interpolate the requested percentile
      double index      = (percentile / 100.0) * (m_adxHistorySize - 1);
      int    lowerIndex = (int)MathFloor(index);
      int    upperIndex = (int)MathCeil(index);

      if(lowerIndex == upperIndex)
         return sorted[lowerIndex];

      double fraction = index - lowerIndex;
      return sorted[lowerIndex] + (sorted[upperIndex] - sorted[lowerIndex]) * fraction;
   }

   //+------------------------------------------------------------------+
   //| GetPhaseAwareThreshold(): ADX threshold based on market phase    |
   //+------------------------------------------------------------------+
   double GetPhaseAwareThreshold(EMarketPhase phase) {
      switch(phase) {
         case PHASE_TRENDING:
         case PHASE_TRENDING_UP:
         case PHASE_TRENDING_DN:
            // Strong trend confirmed — require higher ADX
            return m_settings.ADX_Threshold_Trending;

         case PHASE_EMERGING:
         case PHASE_EMERGING_UP:
         case PHASE_EMERGING_DN:
            // Trend forming (emerging/transitional) — use distribution threshold as medium filter
            return m_settings.ADX_Threshold_Distribution;

         case PHASE_UNORDERED:
         default:
            // Unordered/unknown — use accumulation (lowest) threshold
            return m_settings.ADX_Threshold_Accumulation;
      }
   }

   //+------------------------------------------------------------------+
   //| CalculateCI(): Calculate Choppiness Index for given shift       |
   //| Formula: 100 * log10(Σ TR) / log10(Highest High - Lowest Low)   |
   //| Returns: CI value (0-100), where >61.8 indicates ranging market  |
   //+------------------------------------------------------------------+
   double CalculateCI(int shift)
   {
      int period = m_settings.CI_Period;

      // Sum of True Ranges over period
      double sum_tr = 0.0;
      for(int i = shift; i < shift + period; i++)
      {
         double h = iHigh(m_symbol, PERIOD_CURRENT, i);
         double l = iLow(m_symbol, PERIOD_CURRENT, i);
         double c_prev = iClose(m_symbol, PERIOD_CURRENT, i + 1);

         // True Range = max(H-L, |H-C_prev|, |L-C_prev|)
         double tr = MathMax(h - l, MathMax(MathAbs(h - c_prev), MathAbs(l - c_prev)));
         sum_tr += tr;
      }

      // Highest high and lowest low over period
      int highest_idx = iHighest(m_symbol, PERIOD_CURRENT, MODE_HIGH, period, shift);
      int lowest_idx  = iLowest(m_symbol, PERIOD_CURRENT, MODE_LOW, period, shift);
      double highest  = iHigh(m_symbol, PERIOD_CURRENT, highest_idx);
      double lowest   = iLow(m_symbol, PERIOD_CURRENT, lowest_idx);
      double range    = highest - lowest;

      // Avoid division by zero (flat market = max choppiness)
      // 0.00001 is sub-pip level: any real price range will exceed this
      if(range < 0.00001) return 100.0;

      // Calculate CI
      double ci = 100.0 * MathLog10(sum_tr) / MathLog10(range);

      return ci;
   }

   //+------------------------------------------------------------------+
   //| Check_CI(): Choppiness Index vote (non-directional)             |
   //| Returns: true if market is NOT ranging (CI < threshold)         |
   //+------------------------------------------------------------------+
   bool Check_CI(int bias, int shift)
   {
      double ci = CalculateCI(shift);

      // Reject if CI indicates ranging market
      if(ci >= m_settings.CI_RangingThreshold)
         return false;  // Ranging/choppy market

      return true;  // Trending market (acceptable)
   }

   //+------------------------------------------------------------------+
   //| UpdateATRHistory(): Update rolling ATR buffer                    |
   //| Called every time GetVolatilityRegime() is invoked              |
   //+------------------------------------------------------------------+
   void UpdateATRHistory(double currentATR)
   {
      if(m_settings.VRC_Lookback <= 0) return;

      // Cap at fixed buffer size
      int maxSize = MathMin(m_settings.VRC_Lookback, 100);

      // Shift existing values right (oldest value falls off at end)
      for(int i = maxSize - 1; i > 0; i--) {
         m_atrHistory[i] = m_atrHistory[i - 1];
      }

      // Insert new value at front
      m_atrHistory[0] = currentATR;

      // Track current size (up to max lookback)
      if(m_atrHistorySize < maxSize) {
         m_atrHistorySize++;
      }
   }

   //+------------------------------------------------------------------+
   //| CalculateATRPercentile(): ATR percentile with linear interp      |
   //| Returns: ATR value at specified percentile (0-100 scale)         |
   //+------------------------------------------------------------------+
   double CalculateATRPercentile(double percentile)
   {
      // Need minimum history for statistical validity
      if(m_atrHistorySize < 10) {
         if(m_settings.DebugFlow) Print("VRC: Insufficient history (", m_atrHistorySize, " bars)");
         return 0.0;
      }

      // Copy to temp array for sorting
      double sorted[];
      ArrayResize(sorted, m_atrHistorySize);
      ArrayCopy(sorted, m_atrHistory, 0, 0, m_atrHistorySize);
      ArraySort(sorted);

      // Calculate percentile position (0-100 scale)
      double position   = (percentile / 100.0) * (m_atrHistorySize - 1);
      int    lowerIndex = (int)MathFloor(position);
      int    upperIndex = (int)MathCeil(position);

      // Linear interpolation between two nearest values
      if(lowerIndex == upperIndex) {
         return sorted[lowerIndex];
      }

      double fraction = position - lowerIndex;
      return sorted[lowerIndex] + fraction * (sorted[upperIndex] - sorted[lowerIndex]);
   }

   //+------------------------------------------------------------------+
   //| GetVolatilityRegime(): Classify current volatility regime        |
   //| Updates cache every 4 hours for performance                      |
   //| Returns: VOLATILITY_LOW if below threshold, else NORMAL          |
   //+------------------------------------------------------------------+
   EVolatilityRegime GetVolatilityRegime()
   {
      // Get current ATR value from indicator (use closed bar, shift=1)
      double atr = GetVal(h_atr, 1, 0);
      if(atr <= 0.0) {
         if(m_settings.DebugFlow) Print("VRC: Invalid ATR value, defaulting to LOW");
         return VOLATILITY_LOW; // Guard against invalid data
      }

      // Update rolling history with current ATR
      UpdateATRHistory(atr);

      // Update cache every 4 hours (14400 seconds) or on first call
      datetime now = TimeCurrent();
      if(now - m_lastVRCCalculation > 14400 || m_cachedVRCLowThreshold == 0.0) {
         m_cachedVRCLowThreshold = CalculateATRPercentile(m_settings.VRC_LowThreshold);
         m_lastVRCCalculation    = now;

         if(m_settings.DebugFlow) {
            Print("VRC: Cache updated. Low threshold (", m_settings.VRC_LowThreshold,
                  "th percentile) = ", DoubleToString(m_cachedVRCLowThreshold, 5));
         }
      }

      // Insufficient history: allow trade (don't filter on startup)
      if(m_cachedVRCLowThreshold == 0.0)
         return VOLATILITY_NORMAL;

      // Classify regime based on cached threshold
      if(atr < m_cachedVRCLowThreshold) {
         if(m_settings.DebugFlow) {
            Print("VRC: LOW regime (ATR=", DoubleToString(atr, 5),
                  " < threshold=", DoubleToString(m_cachedVRCLowThreshold, 5), ")");
         }
         return VOLATILITY_LOW;
      }

      if(m_settings.DebugFlow) {
         Print("VRC: NORMAL regime (ATR=", DoubleToString(atr, 5),
               " >= threshold=", DoubleToString(m_cachedVRCLowThreshold, 5), ")");
      }
      return VOLATILITY_NORMAL;
   }

   //+------------------------------------------------------------------+
   //| Check_VRC(): Volatility Regime Classifier vote (non-directional) |
   //| Returns: true if volatility is acceptable, false if too low      |
   //| Pattern: Same as Check_CI() – independent of trade direction     |
   //+------------------------------------------------------------------+
   bool Check_VRC(int bias, int shift)
   {
      // ATR handle must be valid (h_atr created in Init())
      if(h_atr == INVALID_HANDLE) {
         if(m_settings.DebugFlow) Print("VRC: ATR handle invalid");
         return false;
      }

      // Get current volatility regime
      EVolatilityRegime regime = GetVolatilityRegime();

      // FAIL if volatility is too low (market too quiet, likely choppy/ranging)
      if(regime == VOLATILITY_LOW) {
         if(m_settings.DebugFlow) Print("VRC: FAIL (volatility too low for reliable trend)");
         return false;
      }

      // PASS if volatility is acceptable (NORMAL or HIGH)
      if(m_settings.DebugFlow) Print("VRC: PASS (volatility acceptable)");
      return true;
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
                  m_diag_last_reason = "NEWS";
                  return false;
               }
            }
         }
      }
      
      // C. Spread Check
      double spread_pips = SpreadPips();
      if(m_settings.UseSpread && m_settings.MaxSpread > 0.0 && spread_pips > m_settings.MaxSpread) { m_diag_last_reason="SPREAD"; return false; }
      
      // Cache ATR for diagnostics and voting section
      m_diag_last_atr_pips = AtrPips();

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
   // === EvaluateTS: BEGIN ===
   //==========================================================================
   // This function implements the 9-step signal validation pipeline.
   // Each step must pass before moving to the next.
   // If any step fails, the function returns 0 (no trade).
   //
   // PROCESS FLOW:
   // 1. PRE-FILTERS: Spread, time checks
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
   // EvaluateTS() - Main Signal Processing Pipeline (WITH DIAGNOSTICS)
   //==========================================================================
   int EvaluateTS() 
   {
      if(m_settings.DebugFlow) {
         Print("[DEBUG_TEST] EvaluateTS() CALLED");
         PrintFormat("[DEBUG_TEST] m_settings.DebugFlow = %s", m_settings.DebugFlow ? "TRUE" : "FALSE");
         PrintFormat("[DEBUG_TEST] Current time: %s", TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES));
      }

      // Update PSAR flip tracking on each bar close (uses shift=1 for closed bar)
      if(m_settings.Vote_AllowPsarFlip)
         UpdatePSARFlipTracking(m_settings.Vote_EvalShift);

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
      // Note: m_diag_last_atr_pips intentionally NOT reset here (set by CheckFilters, retained across bars)

      m_bars_evaluated++;
      m_stats.total_bars++;

      // Bar-close diagnostic banner
      if(m_settings.DebugFlow)
      {
         datetime bar_time = iTime(m_symbol, PERIOD_CURRENT, m_settings.ma_v_shift);
         PrintFormat("[EVAL_START] ===========================================");
         PrintFormat("[EVAL_START] Bar: %s (shift=%d)",
                     TimeToString(bar_time, TIME_DATE|TIME_MINUTES), m_settings.ma_v_shift);
         PrintFormat("[EVAL_START] ===========================================");
      }

      // 1. Check Filters (inline for full-eval mode support and per-filter pass tracking)
      // In waterfall mode: return early on first failure (existing behavior).
      // In full-eval mode: evaluate ALL filters, track pass/fail, continue to indicators.
      bool any_failure  = false;
      string first_failure = "";

      // --- Time Window ---
      if(m_settings.UseTime) {
         MqlDateTime dt; TimeCurrent(dt);
         bool time_pass = (m_settings.StartHr < m_settings.EndHr) ?
                          (dt.hour >= m_settings.StartHr && dt.hour < m_settings.EndHr) :
                          (dt.hour >= m_settings.StartHr || dt.hour < m_settings.EndHr);
         if(time_pass) m_stats.passed_time++;
         else m_stats.rejected_time++;
         if(m_settings.DebugFlow)
            PrintFormat("[GATE] Time: hour=%d window=[%d-%d] → %s",
                        dt.hour, m_settings.StartHr, m_settings.EndHr,
                        time_pass ? "PASS" : "FAIL");
         if(!time_pass) {
            if(first_failure == "") first_failure = "TIME";
            any_failure = true;
            if(!m_settings.Stats_FullEvaluation) {
               m_diag_last_reason = "TIME"; m_reject_filter++; return 0;
            }
         }
      }
      else if(m_settings.DebugFlow)
         Print("[GATE] Time: DISABLED → SKIP");

      // --- News Filter ---
      if(m_settings.UseNews && m_news_count > 0) {
         bool news_pass = true;
         string base, quote;
         GetSymbolCurrencies(m_symbol, base, quote);
         if(base != "" && quote != "") {
            datetime now = TimeCurrent();
            int pre_sec  = m_settings.NewsPre  * 60;
            int post_sec = m_settings.NewsPost * 60;
            for(int i=0; i<m_news_count; i++) {
               if(!NewsImpactPass(m_news_events[i].impact)) continue;
               string ccy = m_news_events[i].currency;
               if(ccy != base && ccy != quote) continue;
               datetime t = m_news_events[i].time;
               if(now >= (t - pre_sec) && now <= (t + post_sec)) {
                  news_pass = false;
                  if(m_last_news_block_log == 0 || (now - m_last_news_block_log) >= 60) {
                     PrintFormat("News Filter: blocked %s due to %s %s event at %s (window -%d/+%d min)",
                                 m_symbol, ccy,
                                 (m_news_events[i].impact==""?"(impact n/a)":m_news_events[i].impact),
                                 TimeToString(t, TIME_DATE|TIME_MINUTES),
                                 m_settings.NewsPre, m_settings.NewsPost);
                     m_last_news_block_log = now;
                  }
                  break;
               }
            }
         }
         if(news_pass) m_stats.passed_news++;
         else m_stats.rejected_news++;
         if(m_settings.DebugFlow)
            PrintFormat("[GATE] News: %s", news_pass ? "PASS" : "FAIL (event active)");
         if(!news_pass) {
            if(first_failure == "") first_failure = "NEWS";
            any_failure = true;
            if(!m_settings.Stats_FullEvaluation) {
               m_diag_last_reason = "NEWS"; m_reject_filter++; return 0;
            }
         }
      }
      else if(m_settings.DebugFlow)
         Print("[GATE] News: DISABLED → SKIP");

      // --- Spread ---
      double spread_pips = SpreadPips();
      bool spread_pass = !(m_settings.UseSpread && m_settings.MaxSpread > 0.0 && spread_pips > m_settings.MaxSpread);
      if(spread_pass) m_stats.passed_spread++;
      else m_stats.rejected_spread++;
      if(m_settings.DebugFlow) {
         if(!m_settings.UseSpread || m_settings.MaxSpread <= 0.0)
            Print("[GATE] Spread: DISABLED → SKIP");
         else
            PrintFormat("[GATE] Spread: %.1f pips / %.1f max → %s",
                        spread_pips, m_settings.MaxSpread, spread_pass ? "PASS" : "FAIL");
      }
      if(!spread_pass) {
         if(first_failure == "") first_failure = "SPREAD";
         any_failure = true;
         if(!m_settings.Stats_FullEvaluation) {
            m_diag_last_reason = "SPREAD"; m_reject_filter++; return 0;
         }
      }

      // --- ATR: cache for voting section (set in CheckFilters, but also update here for EvaluateTS path) ---
      // m_diag_last_atr_pips is already set in CheckFilters()

      // In full-eval mode, track filter rejection if any filter failed (waterfall would have exited above)
      if(any_failure && m_settings.Stats_FullEvaluation) m_reject_filter++;

      // 1b. Master bias gate (BiasEnabled) — always a hard gate regardless of eval mode
      if(!m_settings.BiasEnabled) { m_diag_last_reason="BIAS_DISABLED"; m_reject_bias++; m_stats.rejected_bias++; return 0; }


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
         PrintFormat("ENTRY LAYER[%s]: Detected %s (bitfield=%d)",
                     TimeToString(iTime(m_symbol, PERIOD_CURRENT, v_shift)),
                     LayerBitfieldToString((int)m_diag_last_entry_layer),
                     (int)m_diag_last_entry_layer);
      }

      //+------------------------------------------------------------------+
      //| 260304_PR5: Phase-Based Layer Filtering                          |
      //|                                                                  |
      //| Enforces RRM methodology rules for entry filtering:              |
      //| - UNORDERED: Block ALL layers (L1, L2, L3) — choppy market      |
      //| - EMERGING:  ALLOW L1/L2 only; Block L3 — trend forming         |
      //| - TRENDING:  ALLOW ALL layers (L1/L2/L3) — strong established   |
      //|              trend; deep pullbacks (L3/Shark) are valid here     |
      //|                                                                  |
      //| Requires BOTH PhaseDetectionEnabled=true AND                     |
      //| EnableLayerDetection=true to activate filtering                  |
      //+------------------------------------------------------------------+
      // ═══════════════════════════════════════════════════════════════
      // 260304_PR5 / 260308_PR: Phase-based layer filtering
      // If both phase detection and layer detection are enabled,
      // enforce RRM methodology rules for trade filtering by phase.
      // 260308_PR: m_diag_last_entry_layer is now a bitfield — check
      // individual layer flags rather than equality comparisons.
      // ═══════════════════════════════════════════════════════════════
      if(m_settings.EnableLayerDetection && 
         m_settings.PhaseDetectionEnabled &&
         m_diag_last_entry_layer != LAYER_NONE)
      {
         EMarketPhase phase = m_diag_last_phase;
         bool is_emerging = (phase == PHASE_EMERGING || phase == PHASE_EMERGING_UP || phase == PHASE_EMERGING_DN);
         bool is_trending = (phase == PHASE_TRENDING || phase == PHASE_TRENDING_UP || phase == PHASE_TRENDING_DN);
         
         // Rule 1: UNORDERED phase blocks ALL trades (choppy market)
         if(phase == PHASE_UNORDERED) {
            m_diag_last_reason = "PHASE_UNORDERED_BLOCKS_ALL";
            m_reject_bias++;
            m_stats.rejected_phase++;
            
            if(m_settings.DebugFlow) {
               PrintFormat("[260308_PR5] UNORDERED phase detected - blocking ALL trades (layers=%s)",
                           LayerBitfieldToString((int)m_diag_last_entry_layer));
            }
            if(!m_settings.Stats_FullEvaluation) return 0;
            if(first_failure == "") first_failure = "PHASE_UNORDERED";
            any_failure = true;
         }
         else {
            m_stats.passed_phase++;
         }
         
         // Rule 2: EMERGING phase blocks STRONG (Layer 3) trades only
         // 260308_PR: Check L3 flag in bitfield rather than equality
         if(is_emerging && IsLayerActive(m_diag_last_entry_layer, LAYER_3_STRONG)) {
            m_diag_last_reason = "PHASE_EMERGING_BLOCKS_STRONG";
            m_reject_bias++;
            m_stats.rejected_layer_blocked++;
            
            if(m_settings.DebugFlow) {
               PrintFormat("[260308_PR5] %s phase detected - blocking L3 component (deep pullback too risky); layers=%s",
                           EnumToString(phase), LayerBitfieldToString((int)m_diag_last_entry_layer));
            }
            if(!m_settings.Stats_FullEvaluation) return 0;
            if(first_failure == "") first_failure = "PHASE_EMERGING_L3";
            any_failure = true;
         }
         else if(phase != PHASE_UNORDERED) {
            m_stats.passed_layer_blocked++;
         }
         
         // Rule 3: TRENDING phase allows ALL layers (L1/L2/L3 — no blocking)
         if(m_settings.DebugFlow && is_trending) {
            PrintFormat("[260308_PR5] %s phase - allowing ALL layers (%s); deep pullbacks valid in strong trend",
                        EnumToString(phase), LayerBitfieldToString((int)m_diag_last_entry_layer));
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
            m_stats.rejected_bias++;
            if(!m_settings.Stats_FullEvaluation) return 0;
            if(first_failure == "") first_failure = "BIAS_ZERO";
            any_failure = true;
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

         // === CONFIGURABLE LOOKBACK ===
         int lookback = m_settings.SlopeLookbackBars;
         if(lookback < 1) lookback = 1;
         if(lookback > 5) lookback = 5; // Safety limit

         // Get EMA values with configurable lookback
         double f_curr = GetMAVal(hf, v_shift, 0);
         double f_prev = GetMAVal(hf, v_shift + lookback, 0);  // Configurable lookback
         double s_curr = GetMAVal(hs, v_shift, 0);
         double s_prev = GetMAVal(hs, v_shift + lookback, 0);  // Configurable lookback

         // === CONFIGURABLE MIN SLOPE THRESHOLD ===
         double min_slope = GetMinSlopeThreshold(f_curr, s_curr);
         double pip = PipSize();

         // Calculate slopes with configurable threshold
         int fast_slope = CalculateSlope(f_curr, f_prev, min_slope);
         int slow_slope = CalculateSlope(s_curr, s_prev, min_slope);
         
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
               double threshold_pips = (pip > 0) ? min_slope / pip : 0.0;
               PrintFormat("STEP 1 BIAS[%s]: SINGLE_SLOPE %s | curr=%.5f prev=%.5f change=%.2f pips slope=%s thresh=%.2fp lookback=%d → bias=%d",
                           TimeToString(bar_time),
                           ema_fast_name,
                           f_curr,
                           f_prev,
                           change_pips,
                           (fast_slope==1)?"RISING":(fast_slope==-1)?"FALLING":"FLAT",
                           threshold_pips,
                           lookback,
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
               double threshold_pips = (pip > 0) ? min_slope / pip : 0.0;
               string position = (f_curr > s_curr) ? "ABOVE" : (f_curr < s_curr) ? "BELOW" : "EQUAL";
               PrintFormat("STEP 1 BIAS[%s]: PAIR %s vs %s | fast=%.5f(%+.2fp %s) slow=%.5f(%+.2fp %s) pos=%s thresh=%.2fp lookback=%d → bias=%d",
                           TimeToString(bar_time),
                           ema_fast_name, ema_slow_name,
                           f_curr, fast_change_pips, (fast_slope==1)?"UP":(fast_slope==-1)?"DN":"FLAT",
                           s_curr, slow_change_pips, (slow_slope==1)?"UP":(slow_slope==-1)?"DN":"FLAT",
                           position,
                           threshold_pips,
                           lookback,
                           market_bias);
            }
         }
         
         // If no valid market bias, reject immediately
         if(market_bias == 0) {
            m_diag_last_bias = 0;
            m_diag_last_reason = "BIAS_ZERO";
            m_reject_bias++;
            m_stats.rejected_bias++;
            
            if(m_settings.DebugFlow) {
               datetime bar_time = iTime(m_symbol, PERIOD_CURRENT, v_shift);
               PrintFormat("STEP 1 BIAS[%s]: bias=0 → REJECT (no trend)", TimeToString(bar_time));
            }
            
            if(!m_settings.Stats_FullEvaluation) return 0;
            if(first_failure == "") first_failure = "BIAS_ZERO";
            any_failure = true;
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
         else if(m_settings.AutoStrat == STRAT_POSITION_SLOPE) {
            // Entry signal from EMA position + slope: persistent bias that lasts for many bars.
            // market_bias in STEP 1 already encodes "Fast > Slow AND both rising" (or reverse),
            // so we simply propagate it as the entry signal (no one-bar crossover required).
            entry_signal = market_bias;
            
            if(m_settings.DebugFlow) {
               datetime bar_time = iTime(m_symbol, PERIOD_CURRENT, v_shift);
               string direction = (entry_signal == 1) ? "LONG (position + slopes aligned UP)" :
                                  (entry_signal == -1) ? "SHORT (position + slopes aligned DOWN)" :
                                  "NEUTRAL (slopes not aligned or conflicting)";
               PrintFormat("[BIAS_POSITION_SLOPE][%s] Fast=%.5f Slow=%.5f | SlopeFast=%d SlopeSlow=%d → %s",
                           TimeToString(bar_time), f_curr, s_curr, fast_slope, slow_slope, direction);
            }
         }
         else if(m_settings.AutoStrat == STRAT_LAYER_DETECTION) {
            // Entry signal from layer-based pullback detection (Ribbon/Ghost/Shark patterns)
            EEntryLayer layer = DetectLayerSignal(v_shift, market_bias);
            m_current_layer = layer;

            if(layer != LAYER_NONE) {
               entry_signal = market_bias;
               m_stats.passed_layer_none++;
            } else {
               entry_signal = 0;
               m_diag_last_reason = "LAYER_NONE";
               m_stats.rejected_layer_none++;
            }

            if(m_settings.DebugFlow) {
               datetime bar_time = iTime(m_symbol, PERIOD_CURRENT, v_shift);
               if(layer != LAYER_NONE)
                  PrintFormat("STEP 2 ENTRY[%s]: STRAT_LAYER_DETECTION %s detected → signal=%d",
                              TimeToString(bar_time), GetLayerName(layer), entry_signal);
               else
                  PrintFormat("STEP 2 ENTRY[%s]: STRAT_LAYER_DETECTION no layer → signal=0",
                              TimeToString(bar_time));
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
            else if(m_settings.ExitProfile == EXIT_PROFILE_RRM && market_bias != 0) {
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
            m_stats.rejected_bias++;
            if(!m_settings.Stats_FullEvaluation) return 0;
            if(first_failure == "") first_failure = "SIGNAL_MISMATCH";
            any_failure = true;
         }
      }
      
      m_diag_last_bias = bias;

      if(bias == 0) { 
         m_diag_last_reason="BIAS_ZERO";
         m_reject_bias++;
         m_stats.rejected_bias++;
         if(!m_settings.Stats_FullEvaluation) return 0;
         if(first_failure == "") first_failure = "BIAS_ZERO";
         any_failure = true;
      }
      else {
         m_stats.passed_bias++;
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

      // 4. Voting Logic — Dynamic weight-based consensus
      // VOTE_MODE_ALL:       every enabled indicator must agree (weights ignored)
      // VOTE_MODE_THRESHOLD: weighted vote sum must reach enabled-indicator count
      double vote_weight = 0.0;
      bool   all_pass    = true;

      // Helper lambda-style macro not available in MQL5; use inline checks
      // CAST_VOTE_STAT also increments the granular rejection counter when indicator fails
      #define CAST_VOTE(use_flag, weight_field, check_expr) \
         if(use_flag) { \
            bool _cv_pass = (check_expr); \
            if(_cv_pass) vote_weight += weight_field; \
            else         all_pass    = false; \
         }

      #define CAST_VOTE_STAT(use_flag, weight_field, check_expr, stat_rej_field, stat_pass_field) \
         if(use_flag) { \
            bool _cv_pass = (check_expr); \
            if(_cv_pass) { vote_weight += weight_field; stat_pass_field++; } \
            else { all_pass = false; stat_rej_field++; } \
         }

      CAST_VOTE_STAT(m_settings.Ind_EmaSig_Enabled, m_settings.Ind_EmaSig_Weight, Check_EMA1(bias, v_shift), m_stats.rejected_emasig, m_stats.passed_emasig)
      CAST_VOTE_STAT(m_settings.Ind_Adx_Enabled,    m_settings.Ind_Adx_Weight,    Check_ADX(v_shift),        m_stats.rejected_adx, m_stats.passed_adx)
      CAST_VOTE_STAT(m_settings.Ind_Macd_Enabled,   m_settings.Ind_Macd_Weight,   Check_MACD(bias, v_shift), m_stats.rejected_macd, m_stats.passed_macd)
      CAST_VOTE_STAT(m_settings.Ind_Rsi_Enabled,    m_settings.Ind_Rsi_Weight,    Check_RSI(bias, v_shift),  m_stats.rejected_rsi, m_stats.passed_rsi)
      CAST_VOTE_STAT(m_settings.Ind_Cci_Enabled,    m_settings.Ind_Cci_Weight,    Check_CCI(bias, v_shift),  m_stats.rejected_cci, m_stats.passed_cci)
      CAST_VOTE_STAT(m_settings.Ind_Mfi_Enabled,    m_settings.Ind_Mfi_Weight,    Check_MFI(bias, v_shift),  m_stats.rejected_mfi, m_stats.passed_mfi)
      CAST_VOTE_STAT(m_settings.Ind_Sto_Enabled,    m_settings.Ind_Sto_Weight,    Check_Sto(bias, v_shift),  m_stats.rejected_sto, m_stats.passed_sto)
      CAST_VOTE_STAT(m_settings.Ind_Bb_Enabled,     m_settings.Ind_Bb_Weight,     Check_BB(bias, v_shift),   m_stats.rejected_bb, m_stats.passed_bb)
      CAST_VOTE_STAT(m_settings.Ind_Psar_Enabled,   m_settings.Ind_Psar_Weight,
                (m_settings.Vote_AllowPsarFlip ? Check_PSAR_WithFlip(bias, v_shift) : Check_PSAR(bias, v_shift)), m_stats.rejected_psar, m_stats.passed_psar)
      CAST_VOTE_STAT(m_settings.Ind_P123_Enabled,   m_settings.Ind_P123_Weight,   Check_P123(bias, v_shift), m_stats.rejected_p123, m_stats.passed_p123)
      CAST_VOTE_STAT(m_settings.Ind_Ross_Enabled,   m_settings.Ind_Ross_Weight,   Check_Ross(bias, v_shift), m_stats.rejected_ross, m_stats.passed_ross)

      #undef CAST_VOTE_STAT
      #undef CAST_VOTE

      // Volatility regime vote (ATR as non-directional voting indicator)
      if(m_settings.Ind_Atr_Enabled)
      {
         double atr_vote_pips = m_diag_last_atr_pips;
         bool   atr_vote_ok   = true;
         if(m_settings.ATR_VoteMinPips > 0.0 && atr_vote_pips < m_settings.ATR_VoteMinPips) atr_vote_ok = false;
         if(m_settings.ATR_VoteMaxPips > 0.0 && atr_vote_pips > m_settings.ATR_VoteMaxPips) atr_vote_ok = false;

         if(atr_vote_ok) vote_weight += 1.0;
         else            all_pass     = false;
      }

      // Candle Body Overextension (non-directional voting indicator)
      if(m_settings.Ind_CandleBody_Enabled)
      {
         bool candle_ok = CheckCandleBodyIndicator();
         if(candle_ok) { vote_weight += m_settings.Ind_CandleBody_Weight; m_stats.passed_candle_body++; }
         else          { all_pass = false; m_stats.rejected_candle_body++; }
      }

      // Choppiness Index (non-directional ranging market filter)
      if(m_settings.Ind_CI_Enabled)
      {
         bool ci_ok = Check_CI(bias, v_shift);
         if(ci_ok) { vote_weight += m_settings.Ind_CI_Weight; m_stats.passed_ci++; }
         else      { all_pass = false; m_stats.rejected_ci++; }
      }

      // Volatility Regime Classifier (non-directional volatility filter)
      if(m_settings.Ind_VRC_Enabled)
      {
         bool vrc_ok = Check_VRC(bias, v_shift);
         if(vrc_ok) { vote_weight += m_settings.Ind_VRC_Weight; m_stats.passed_vrc++; }
         else       { all_pass = false; m_stats.rejected_vrc++; }
      }

      // Store integer-rounded weight for display (backward-compatible diagnostics)
      m_diag_last_votes = (int)MathRound(vote_weight);

      // Per-indicator results captured during diagnostic logging (used by pipeline summary)
      bool _res_emasig=false, _res_adx=false, _res_macd=false, _res_rsi=false,
           _res_cci=false, _res_mfi=false, _res_sto=false, _res_bb=false,
           _res_psar=false, _res_p123=false, _res_ross=false;

      // ===== DIAGNOSTIC LOGGING FOR VOTE ANALYSIS: BEGIN =====
      // DEBUG_INDICATORS: populate _res_* for TS_SUMMARY (pass/fail per indicator)
      // DEBUG_FULL: also print detailed [IND] lines with indicator values
      if(m_settings.DebugLevel >= DEBUG_INDICATORS) {
         // Populate _res_* results for the TS_SUMMARY block below
         if(m_settings.Ind_EmaSig_Enabled) _res_emasig = Check_EMA1(bias, v_shift);
         if(m_settings.Ind_Adx_Enabled)    _res_adx    = Check_ADX(v_shift);
         if(m_settings.Ind_Macd_Enabled)   _res_macd   = Check_MACD(bias, v_shift);
         if(m_settings.Ind_Rsi_Enabled)    _res_rsi    = Check_RSI(bias, v_shift);
         if(m_settings.Ind_Cci_Enabled)    _res_cci    = Check_CCI(bias, v_shift);
         if(m_settings.Ind_Mfi_Enabled)    _res_mfi    = Check_MFI(bias, v_shift);
         if(m_settings.Ind_Sto_Enabled)    _res_sto    = Check_Sto(bias, v_shift);
         if(m_settings.Ind_Bb_Enabled)     _res_bb     = Check_BB(bias, v_shift);
         if(m_settings.Ind_Psar_Enabled)   _res_psar   = (m_settings.Vote_AllowPsarFlip ? Check_PSAR_WithFlip(bias, v_shift) : Check_PSAR(bias, v_shift));
         if(m_settings.Ind_P123_Enabled)   _res_p123   = Check_P123(bias, v_shift);
         if(m_settings.Ind_Ross_Enabled)   _res_ross   = Check_Ross(bias, v_shift);

         // DEBUG_FULL: print detailed [IND] lines with indicator values
         if(m_settings.DebugLevel >= DEBUG_FULL) {
            string mode_str = (m_settings.VoteMode == VOTE_MODE_ALL ? "ALL" : "THRESHOLD");
            PrintFormat("[IND] --- Indicators (mode=%s bias=%d weight=%.2f) ---",
                        mode_str, bias, vote_weight);

            // EmaSig
            if(m_settings.Ind_EmaSig_Enabled) {
               double p = iClose(m_symbol, PERIOD_CURRENT, v_shift);
               double e = GetMAVal(h_ema1, v_shift);
               PrintFormat("[IND] EmaSig: price=%.5f ema=%.5f → %s (w=%d)",
                           p, e, _res_emasig ? "PASS" : "FAIL", m_settings.Ind_EmaSig_Weight);
            } else Print("[IND] EmaSig: DISABLED → SKIP");

            // ADX
            if(m_settings.Ind_Adx_Enabled) {
               double adx = GetVal(h_adx, v_shift);
               PrintFormat("[IND] ADX: %.2f / threshold=%.2f → %s (w=%d)",
                           adx, m_cachedADXThreshold, _res_adx ? "PASS" : "FAIL", m_settings.Ind_Adx_Weight);
            } else Print("[IND] ADX: DISABLED → SKIP");

            // MACD
            if(m_settings.Ind_Macd_Enabled) {
               double macd_m = GetVal(h_macd, v_shift, 0);
               double macd_s = GetVal(h_macd, v_shift, 1);
               PrintFormat("[IND] MACD: main=%.6f signal=%.6f hist=%.6f → %s (w=%d)",
                           macd_m, macd_s, macd_m - macd_s, _res_macd ? "PASS" : "FAIL", m_settings.Ind_Macd_Weight);
            } else Print("[IND] MACD: DISABLED → SKIP");

            // RSI
            if(m_settings.Ind_Rsi_Enabled) {
               double r = GetVal(h_rsi, v_shift);
               PrintFormat("[IND] RSI: %.2f (OB=%.0f OS=%.0f) → %s (w=%d)",
                           r, m_settings.T_RsiOB, m_settings.T_RsiOS, _res_rsi ? "PASS" : "FAIL", m_settings.Ind_Rsi_Weight);
            } else Print("[IND] RSI: DISABLED → SKIP");

            // CCI
            if(m_settings.Ind_Cci_Enabled) {
               double c = GetVal(h_cci, v_shift);
               PrintFormat("[IND] CCI: %.2f → %s (w=%d)",
                           c, _res_cci ? "PASS" : "FAIL", m_settings.Ind_Cci_Weight);
            } else Print("[IND] CCI: DISABLED → SKIP");

            // MFI
            if(m_settings.Ind_Mfi_Enabled) {
               double mfi = GetVal(h_mfi, v_shift);
               PrintFormat("[IND] MFI: %.2f (OB=%.0f OS=%.0f) → %s (w=%d)",
                           mfi, m_settings.T_MfiOB, m_settings.T_MfiOS, _res_mfi ? "PASS" : "FAIL", m_settings.Ind_Mfi_Weight);
            } else Print("[IND] MFI: DISABLED → SKIP");

            // Stochastic
            if(m_settings.Ind_Sto_Enabled) {
               double sk = GetVal(h_sto, v_shift, 0);
               double sd = GetVal(h_sto, v_shift, 1);
               PrintFormat("[IND] Stoch: K=%.2f D=%.2f (OB=%.0f OS=%.0f) → %s (w=%d)",
                           sk, sd, m_settings.T_StoOB, m_settings.T_StoOS, _res_sto ? "PASS" : "FAIL", m_settings.Ind_Sto_Weight);
            } else Print("[IND] Stoch: DISABLED → SKIP");

            // Bollinger Bands
            if(m_settings.Ind_Bb_Enabled) {
               double bb_mid = GetVal(h_bb, v_shift, 0);
               double cl_bb  = iClose(m_symbol, PERIOD_CURRENT, v_shift);
               PrintFormat("[IND] BB: mid=%.5f close=%.5f → %s (w=%d)",
                           bb_mid, cl_bb, _res_bb ? "PASS" : "FAIL", m_settings.Ind_Bb_Weight);
            } else Print("[IND] BB: DISABLED → SKIP");

            // PSAR
            if(m_settings.Ind_Psar_Enabled) {
               double psar_v = GetVal(h_psar, v_shift);
               double cl_p   = iClose(m_symbol, PERIOD_CURRENT, v_shift);
               string flip_info = "";
               if(m_settings.Vote_AllowPsarFlip) {
                  if(m_settings.Vote_PsarFlipDelay == -1) {
                     flip_info = " [PERSISTENT]";
                  } else {
                     int bars_since_flip = GetBarsSinceLastFlip(bias, v_shift);
                     if(bars_since_flip == INT_MAX)
                        flip_info = " flip=none";
                     else
                        flip_info = StringFormat(" flip=%d bars ago (N=%d)", bars_since_flip,
                                                 MathMax(0, m_settings.Vote_PsarFlipDelay - bars_since_flip));
                  }
               }
               PrintFormat("[IND] PSAR: dot=%.5f close=%.5f%s → %s (w=%d)",
                           psar_v, cl_p, flip_info, _res_psar ? "PASS" : "FAIL", m_settings.Ind_Psar_Weight);
            } else Print("[IND] PSAR: DISABLED → SKIP");

            // P123
            if(m_settings.Ind_P123_Enabled) {
               PrintFormat("[IND] P123: → %s (w=%d)", _res_p123 ? "PASS" : "FAIL", m_settings.Ind_P123_Weight);
            } else Print("[IND] P123: DISABLED → SKIP");

            // Ross Hook
            if(m_settings.Ind_Ross_Enabled) {
               PrintFormat("[IND] RossHook: → %s (w=%d)", _res_ross ? "PASS" : "FAIL", m_settings.Ind_Ross_Weight);
            } else Print("[IND] RossHook: DISABLED → SKIP");

            // ATR Vote (non-directional voting indicator)
            if(m_settings.Ind_Atr_Enabled) {
               double atr_v_pips = m_diag_last_atr_pips;
               bool   atr_v_ok   = true;
               if(m_settings.ATR_VoteMinPips > 0.0 && atr_v_pips < m_settings.ATR_VoteMinPips) atr_v_ok = false;
               if(m_settings.ATR_VoteMaxPips > 0.0 && atr_v_pips > m_settings.ATR_VoteMaxPips) atr_v_ok = false;
               PrintFormat("[IND] ATR Vote: %.1f pips (min=%.1f max=%.1f) → %s (w=1)",
                           atr_v_pips, m_settings.ATR_VoteMinPips, m_settings.ATR_VoteMaxPips,
                           atr_v_ok ? "PASS" : "FAIL");
            } else
               Print("[IND] ATR Vote: DISABLED → SKIP");

            // CandleBody Vote (non-directional voting indicator)
            if(m_settings.Ind_CandleBody_Enabled) {
               bool cb_ok = CheckCandleBodyIndicator();
               PrintFormat("[IND] CandleBody: avg period=%d max=x%.1f check=%d → %s (w=%d)",
                           m_settings.CandleBody_AvgPeriod, m_settings.CandleBody_MaxMult,
                           m_settings.CandleBody_CheckBars, cb_ok ? "PASS" : "FAIL",
                           m_settings.Ind_CandleBody_Weight);
            } else
               Print("[IND] CandleBody: DISABLED → SKIP");

            // Choppiness Index
            if(m_settings.Ind_CI_Enabled) {
               double ci_val = CalculateCI(v_shift);
               bool ci_ok = Check_CI(bias, v_shift);
               string ci_status = (ci_val >= m_settings.CI_RangingThreshold ? "RANGING" : "TRENDING");
               PrintFormat("[IND] ChoppinessIndex: CI=%.1f threshold=%.1f status=%s → %s (w=%d)",
                           ci_val, m_settings.CI_RangingThreshold, ci_status,
                           ci_ok ? "PASS" : "FAIL", m_settings.Ind_CI_Weight);
            } else
               Print("[IND] ChoppinessIndex: DISABLED → SKIP");
         }
      }
      // ===== DIAGNOSTIC LOGGING FOR VOTE ANALYSIS: END =====

      // Final Decision — compute result without returning yet so summary can be printed
      int final_signal = 0;
      if(m_settings.VoteMode == VOTE_MODE_ALL)
      {
         // ALL mode: every enabled indicator must agree (pure multiplicative)
         if(all_pass && !any_failure) {
            m_diag_last_reason="OK";
            m_signals_generated++;
            m_stats.signals_confirmed++;
            if(m_settings.DebugFlow) PrintFormat("[RESULT] TS=%d (ALL votes pass, weight=%.2f)", bias, vote_weight);
            final_signal = bias;
         }
         else if(any_failure) {
            if(m_diag_last_reason == "") m_diag_last_reason = first_failure;
            if(m_settings.DebugFlow) PrintFormat("[RESULT] TS=0 REJECT (%s)", m_diag_last_reason);
         }
         else {
            m_diag_last_reason = StringFormat("NOT_ALL_PASS w=%.2f", vote_weight);
            m_reject_votes++;
            if(m_settings.DebugFlow) PrintFormat("[RESULT] TS=0 REJECT (%s)", m_diag_last_reason);
         }
      }
      else
      {
         // THRESHOLD mode: weighted sum >= total enabled-indicator weight
         if(all_pass && !any_failure) {
            m_diag_last_reason="OK";
            m_signals_generated++;
            m_stats.signals_confirmed++;
            if(m_settings.DebugFlow) PrintFormat("[RESULT] TS=%d (votes %.2f all pass)", bias, vote_weight);
            final_signal = bias;
         }
         else if(any_failure) {
            if(m_diag_last_reason == "") m_diag_last_reason = first_failure;
            if(m_settings.DebugFlow) PrintFormat("[RESULT] TS=0 REJECT (%s)", m_diag_last_reason);
         }
         else {
            m_diag_last_reason = StringFormat("NOT_ALL_PASS w=%.2f", vote_weight);
            m_reject_votes++;
            if(m_settings.DebugFlow) PrintFormat("[RESULT] TS=0 REJECT (%s)", m_diag_last_reason);
         }
      }

      // ===== TS PIPELINE SUMMARY =====
      // DEBUG_INDICATORS+: show per-bar gate/bias/indicator summary (20-30 lines)
      if(m_settings.DebugLevel >= DEBUG_INDICATORS) {
         datetime sum_bar_time = iTime(m_symbol, PERIOD_CURRENT, m_settings.ma_v_shift);
         Print("════════════════════════════════════════════════════════════");
         PrintFormat("[TS_SUMMARY] Bar: %s (shift=%d)",
                     TimeToString(sum_bar_time, TIME_DATE|TIME_MINUTES),
                     m_settings.ma_v_shift);
         Print("════════════════════════════════════════════════════════════");
         Print("");

         // GATES SECTION
         Print("GATES:");
         if(m_settings.UseSpread && m_settings.MaxSpread > 0.0) {
            PrintFormat("  %s Spread: %.1f / %.1f pips max",
                        spread_pass ? "✅" : "❌", spread_pips, m_settings.MaxSpread);
         } else {
            Print("  ⏭️  Spread: disabled");
         }
         Print("  ⏭️  Time window: " + (m_settings.UseTime ? "active" : "disabled"));
         Print("  ⏭️  News filter: " + (m_settings.UseNews ? "active" : "disabled"));
         Print("");

         // BIAS & STRUCTURE SECTION
         Print("BIAS & STRUCTURE:");
         if(bias == 0) {
            PrintFormat("  ❌ Bias: NEUTRAL (%s)", m_diag_last_reason);
         } else {
            PrintFormat("  ✅ Bias: %s (EMAs aligned)", bias > 0 ? "LONG" : "SHORT");
         }
         if(m_settings.PhaseDetectionEnabled) {
            string phase_str = EnumToString(m_diag_last_phase);
            bool phase_blocked = (m_diag_last_phase == PHASE_UNORDERED && m_settings.BlockUnorderedPhase);
            PrintFormat("  %s Phase: %s%s",
                        phase_blocked ? "❌" : "✅", phase_str,
                        phase_blocked ? " (blocked)" : "");
         } else {
            Print("  ⏭️  Phase: disabled");
         }
         if(m_settings.EnableLayerDetection) {
            PrintFormat("  ✅ Layer: %s", LayerBitfieldToString((int)m_diag_last_entry_layer));
         } else {
            Print("  ⏭️  Layer: disabled");
         }
         Print("");

         // INDICATORS SECTION
         int s_enabled=0, s_disabled=0, s_passed=0;
         if(m_settings.Ind_EmaSig_Enabled) s_enabled++; else s_disabled++;
         if(m_settings.Ind_Adx_Enabled)    s_enabled++; else s_disabled++;
         if(m_settings.Ind_Macd_Enabled)   s_enabled++; else s_disabled++;
         if(m_settings.Ind_Rsi_Enabled)    s_enabled++; else s_disabled++;
         if(m_settings.Ind_Cci_Enabled)    s_enabled++; else s_disabled++;
         if(m_settings.Ind_Mfi_Enabled)    s_enabled++; else s_disabled++;
         if(m_settings.Ind_Sto_Enabled)    s_enabled++; else s_disabled++;
         if(m_settings.Ind_Bb_Enabled)     s_enabled++; else s_disabled++;
         if(m_settings.Ind_Psar_Enabled)   s_enabled++; else s_disabled++;
         if(m_settings.Ind_P123_Enabled)   s_enabled++; else s_disabled++;
         if(m_settings.Ind_Ross_Enabled)   s_enabled++; else s_disabled++;

         PrintFormat("INDICATORS (%d enabled, %d disabled):", s_enabled, s_disabled);

         string saved_reason = m_diag_last_reason;

         if(m_settings.Ind_EmaSig_Enabled) {
            PrintFormat("  %s EmaSig", _res_emasig ? "✅" : "❌");
            if(_res_emasig) s_passed++;
         } else Print("  ⏭️  EmaSig: disabled");

         if(m_settings.Ind_Adx_Enabled) {
            PrintFormat("  %s ADX", _res_adx ? "✅" : "❌");
            if(_res_adx) s_passed++;
         } else Print("  ⏭️  ADX: disabled");

         if(m_settings.Ind_Macd_Enabled) {
            PrintFormat("  %s MACD", _res_macd ? "✅" : "❌");
            if(_res_macd) s_passed++;
         } else Print("  ⏭️  MACD: disabled");

         if(m_settings.Ind_Rsi_Enabled) {
            PrintFormat("  %s RSI", _res_rsi ? "✅" : "❌");
            if(_res_rsi) s_passed++;
         } else Print("  ⏭️  RSI: disabled");

         if(m_settings.Ind_Cci_Enabled) {
            PrintFormat("  %s CCI", _res_cci ? "✅" : "❌");
            if(_res_cci) s_passed++;
         } else Print("  ⏭️  CCI: disabled");

         if(m_settings.Ind_Mfi_Enabled) {
            PrintFormat("  %s MFI", _res_mfi ? "✅" : "❌");
            if(_res_mfi) s_passed++;
         } else Print("  ⏭️  MFI: disabled");

         if(m_settings.Ind_Sto_Enabled) {
            PrintFormat("  %s Stochastic", _res_sto ? "✅" : "❌");
            if(_res_sto) s_passed++;
         } else Print("  ⏭️  Stochastic: disabled");

         if(m_settings.Ind_Bb_Enabled) {
            PrintFormat("  %s Bollinger Bands", _res_bb ? "✅" : "❌");
            if(_res_bb) s_passed++;
         } else Print("  ⏭️  Bollinger Bands: disabled");

         if(m_settings.Ind_Psar_Enabled) {
            string psar_mode;
            if(!m_settings.Vote_AllowPsarFlip)
               psar_mode = "DOT";
            else if(m_settings.Vote_PsarFlipDelay == -1)
               psar_mode = "PERSISTENT";
            else
               psar_mode = "FLIP";
            PrintFormat("  %s PSAR (%s mode)",
                        _res_psar ? "✅" : "❌",
                        psar_mode);
            if(_res_psar) s_passed++;
         } else Print("  ⏭️  PSAR: disabled");

         if(m_settings.Ind_P123_Enabled) {
            PrintFormat("  %s Pattern 1-2-3", _res_p123 ? "✅" : "❌");
            if(_res_p123) s_passed++;
         } else Print("  ⏭️  Pattern 1-2-3: disabled");

         if(m_settings.Ind_Ross_Enabled) {
            PrintFormat("  %s Ross Hook", _res_ross ? "✅" : "❌");
            if(_res_ross) s_passed++;
         } else Print("  ⏭️  Ross Hook: disabled");

         Print("");

         // VOTING SUMMARY
         if(s_enabled > 0) {
            double pass_pct = (double)s_passed / s_enabled * 100.0;
            PrintFormat("VOTING: %d/%d passed (%.1f%%) - requires %s",
                        s_passed, s_enabled, pass_pct,
                        m_settings.VoteMode == VOTE_MODE_ALL ? "ALL (100%)" : "THRESHOLD");
         }
         Print("");

         // FINAL RESULT
         Print("════════════════════════════════════════════════════════════");
         if(final_signal == 0) {
            PrintFormat("[TS_RESULT] ❌ REJECTED - Reason: %s", saved_reason);
         } else {
            PrintFormat("[TS_RESULT] ✅✅✅ SIGNAL CONFIRMED: %s ✅✅✅",
                        final_signal > 0 ? "LONG" : "SHORT");
         }
         Print("════════════════════════════════════════════════════════════");
         Print("");
      }
      // ===== TS PIPELINE SUMMARY: END =====

      // DEBUG_SUMMARY: 1-2 line per-bar result (not shown when DEBUG_INDICATORS+ already printed it)
      else if(m_settings.DebugLevel >= DEBUG_SUMMARY) {
         datetime sum_bar_time = iTime(m_symbol, PERIOD_CURRENT, m_settings.ma_v_shift);
         if(final_signal != 0)
            PrintFormat("%s: %s CONFIRMED",
                        TimeToString(sum_bar_time, TIME_DATE|TIME_MINUTES),
                        final_signal > 0 ? "LONG" : "SHORT");
         else
            PrintFormat("%s: REJECTED (%s)",
                        TimeToString(sum_bar_time, TIME_DATE|TIME_MINUTES),
                        m_diag_last_reason);
      }

      return final_signal;

   } // === EvaluateTS: END ===



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
   
   // Shift-aware slope: compares MA at [shift] vs [shift+1]
   int GetSlope(int handle, int shift) {
      double c = GetMAVal(handle, shift);
      double p = GetMAVal(handle, shift + 1);
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
      
      // Detect current market phase (instant EMA + slope check)
      EMarketPhase current_phase = DetectMarketPhase(v_shift);
      
      // Update diagnostics
      m_diag_last_phase = current_phase;
      
      // Check phase stability if required (optional, default min_bars=0 = instant)
      if(m_settings.RequireMinPhaseConfirm && m_settings.MinPhaseConfirmBars > 0)
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
      
      // Map phase directly to bias direction (phase encodes direction)
      switch(current_phase)
      {
         case PHASE_TRENDING_UP:
            if(m_settings.DebugFlow) Print("[260304_BIAS] TRENDING_UP → LONG bias");
            return 1;
            
         case PHASE_TRENDING_DN:
            if(m_settings.DebugFlow) Print("[260304_BIAS] TRENDING_DN → SHORT bias");
            return -1;
            
         case PHASE_EMERGING_UP:
            if(m_settings.DebugFlow) Print("[260304_BIAS] EMERGING_UP → LONG bias (trend forming)");
            return 1;
            
         case PHASE_EMERGING_DN:
            if(m_settings.DebugFlow) Print("[260304_BIAS] EMERGING_DN → SHORT bias (trend forming)");
            return -1;
            
         case PHASE_TRENDING:
         {
            // Legacy: re-evaluate direction from EMA values for backward compat
            double ema13 = GetMAVal(h_ema2, v_shift, 0);
            double ema89 = GetMAVal(h_ema4, v_shift, 0);
            double tolerance = 2.0 * SymbolInfoDouble(m_symbol, SYMBOL_POINT);
            if(ema13 > ema89 + tolerance) { if(m_settings.DebugFlow) Print("[260304_BIAS] TRENDING Bullish → LONG"); return 1; }
            if(ema89 > ema13 + tolerance) { if(m_settings.DebugFlow) Print("[260304_BIAS] TRENDING Bearish → SHORT"); return -1; }
            return 0;
         }
            
         case PHASE_EMERGING:
         {
            // Legacy: re-evaluate direction from EMA values for backward compat
            double ema13 = GetMAVal(h_ema2, v_shift, 0);
            double ema89 = GetMAVal(h_ema4, v_shift, 0);
            double tolerance = 2.0 * SymbolInfoDouble(m_symbol, SYMBOL_POINT);
            if(ema13 > ema89 + tolerance) { if(m_settings.DebugFlow) Print("[260304_BIAS] EMERGING Bullish → LONG"); return 1; }
            if(ema89 > ema13 + tolerance) { if(m_settings.DebugFlow) Print("[260304_BIAS] EMERGING Bearish → SHORT"); return -1; }
            return 0;
         }
            
         case PHASE_UNORDERED:
         default:
            if(m_settings.DebugFlow) Print("[260304_BIAS] UNORDERED phase → NO BIAS");
            return 0;
      }
   }

   //+------------------------------------------------------------------+
   //| ValidateLayer: Check alignment of a single EMA pair            |
   //| Returns: 1=LONG, -1=SHORT, 0=INVALID                           |
   //+------------------------------------------------------------------+
   int ValidateLayer(double ema_fast, double ema_slow, int slope_fast, int slope_slow, string layer_name)
   {
      bool fast_above_slow = (ema_fast > ema_slow);
      
      if(fast_above_slow && slope_fast > 0 && slope_slow > 0) 
      {
         if(m_settings.DebugFlow)
            PrintFormat("[LAYER %s] LONG: FastEMA %.5f > SlowEMA %.5f slopes %d/%d", 
                        layer_name, ema_fast, ema_slow, slope_fast, slope_slow);
         return 1;
      }
      
      if(!fast_above_slow && slope_fast < 0 && slope_slow < 0) 
      {
         if(m_settings.DebugFlow)
            PrintFormat("[LAYER %s] SHORT: SlowEMA %.5f > FastEMA %.5f slopes %d/%d", 
                        layer_name, ema_slow, ema_fast, slope_fast, slope_slow);
         return -1;
      }
      
      if(m_settings.DebugFlow)
         PrintFormat("[LAYER %s] INVALID: pos=%s slopeF=%d slopeS=%d", 
                     layer_name, fast_above_slow ? "F>S" : "S>F", slope_fast, slope_slow);
      return 0;
   }

   //+------------------------------------------------------------------+
   //| 260304_PR1: Detect Market Phase Based on 3-Layer EMA Voting     |
   //| Checks all 4 EMAs across 3 layers; requires majority agreement  |
   //| Returns directional phases (UP/DN) for direct bias mapping      |
   //+------------------------------------------------------------------+
   EMarketPhase DetectMarketPhase(const int shift = 1)
   {
      double ema1 = GetMAVal(h_ema1, shift, 0);
      double ema2 = GetMAVal(h_ema2, shift, 0);
      double ema3 = GetMAVal(h_ema3, shift, 0);
      double ema4 = GetMAVal(h_ema4, shift, 0);
      
      if(ema1 == EMPTY_VALUE || ema2 == EMPTY_VALUE || 
         ema3 == EMPTY_VALUE || ema4 == EMPTY_VALUE)
         return PHASE_UNORDERED;
      
      int slope1 = GetSlope(h_ema1, shift);
      int slope2 = GetSlope(h_ema2, shift);
      int slope3 = GetSlope(h_ema3, shift);
      int slope4 = GetSlope(h_ema4, shift);
      
      int layer1 = ValidateLayer(ema1, ema2, slope1, slope2, "L1_WEAK");
      int layer2 = ValidateLayer(ema2, ema3, slope2, slope3, "L2_MEDIUM");
      int layer3 = ValidateLayer(ema3, ema4, slope3, slope4, "L3_STRONG");
      
      int long_votes = 0;
      int short_votes = 0;

      // Phase determined by VOTE COUNT across all 3 layers
      if(layer1 == 1) long_votes++;
      if(layer1 == -1) short_votes++;
      if(layer2 == 1) long_votes++;
      if(layer2 == -1) short_votes++;
      if(layer3 == 1) long_votes++;
      if(layer3 == -1) short_votes++;
      
      if(long_votes == 3) return PHASE_TRENDING_UP;   // all 3 agree
      if(short_votes == 3) return PHASE_TRENDING_DN;  // all 3 agree
      if(long_votes == 2) return PHASE_EMERGING_UP;   // 2 of 3 agree
      if(short_votes == 2) return PHASE_EMERGING_DN;  // 2 of 3 agree
      
      return PHASE_UNORDERED; // <2 agree
   }
   
   //+------------------------------------------------------------------+
   //| 260304_PR1: Confirm Phase Stability (Optional)                  |
   //| Checks N consecutive bars in same phase (min_bars=0 = instant)  |
   //+------------------------------------------------------------------+
   bool ConfirmPhaseStability(const EMarketPhase current_phase, const int min_bars)
   {
      if(min_bars <= 0) return true;  // 0=instant (no confirmation required)
      
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
   //| 260308_PR: Returns a BITFIELD of all active layers so that      |
   //| simultaneous multi-layer signals are captured.                  |
   //|                                                                  |
   //| Returns:                                                         |
   //|   Bitfield of LAYER_x flags (OR-combined)                       |
   //|   LAYER_NONE (0)  - Detection disabled or no EMA touch found   |
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

      int active_layers = 0;  // 260308_PR: Bitfield accumulator — check ALL layers

      // Layer 1: price touches EMA1 or EMA2 zone
      if(MathAbs(price - ema1) <= tol || MathAbs(price - ema2) <= tol)
      {
         active_layers |= (int)LAYER_1_WEAK;
         if(m_settings.DebugFlow)
            PrintFormat("[260304_ENTRY] WEAK layer detected: Price=%.5f touched EMA1(%.5f) tolerance=%.5f",
                        price, ema1, tol);
      }

      // Layer 2: price touches EMA2 or EMA3 zone
      if(MathAbs(price - ema2) <= tol || MathAbs(price - ema3) <= tol)
      {
         active_layers |= (int)LAYER_2_MEDIUM;
         if(m_settings.DebugFlow)
            PrintFormat("[260304_ENTRY] MEDIUM layer detected: Price=%.5f touched EMA2(%.5f) tolerance=%.5f",
                        price, ema2, tol);
      }

      // Layer 3: price touches EMA3 or EMA4 zone
      if(MathAbs(price - ema3) <= tol || MathAbs(price - ema4) <= tol)
      {
         active_layers |= (int)LAYER_3_STRONG;
         if(m_settings.DebugFlow)
            PrintFormat("[260304_ENTRY] STRONG layer detected: Price=%.5f touched EMA3(%.5f) tolerance=%.5f",
                        price, ema3, tol);
      }

      return (EEntryLayer)active_layers;
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

   //+------------------------------------------------------------------+
   //| 260308_PR: Convert layer bitfield to readable string            |
   //| Examples: 0→"NONE", 1→"L1", 3→"L1+L2", 7→"L1+L2+L3"         |
   //+------------------------------------------------------------------+
   string LayerBitfieldToString(int bitfield)
   {
      if(bitfield == 0) return "NONE";

      string result = "";
      if((bitfield & (int)LAYER_1_WEAK)   != 0) result += (result == "" ? "" : "+") + "L1";
      if((bitfield & (int)LAYER_2_MEDIUM) != 0) result += (result == "" ? "" : "+") + "L2";
      if((bitfield & (int)LAYER_3_STRONG) != 0) result += (result == "" ? "" : "+") + "L3";

      return result;
   }

   //+------------------------------------------------------------------+
   //| 260308_PR: Check if a specific layer flag is set in a bitfield  |
   //+------------------------------------------------------------------+
   bool IsLayerActive(EEntryLayer bitfield, EEntryLayer layer) const
   {
      return ((int)bitfield & (int)layer) != 0;
   }

   //+------------------------------------------------------------------+
   //| STRAT_LAYER_DETECTION: Detect pullback-recovery layer(s)        |
   //|                                                                  |
   //| 260308_PR: Returns a BITFIELD of all active layers so that      |
   //| simultaneous multi-layer signals (e.g. L1+L2) are captured.    |
   //|                                                                  |
   //| Implements Python EA TrSet patterns:                             |
   //|   LAYER_1_WEAK   (Ribbon): Low touches EMA1, Close beyond EMA2  |
   //|   LAYER_2_MEDIUM (Ghost):  Low touches EMA2, Close beyond EMA3  |
   //|   LAYER_3_STRONG (Shark):  Low touches EMA3, Close beyond EMA4  |
   //|                                                                  |
   //| Parameters:                                                      |
   //|   v_shift - bar shift (1 = last closed bar)                     |
   //|   bias    - market bias (1=LONG, -1=SHORT)                      |
   //+------------------------------------------------------------------+
   EEntryLayer DetectLayerSignal(const int v_shift, const int bias)
   {
      if(bias == 0) return LAYER_NONE;

      double ema1 = GetMAVal(h_ema1, v_shift, 0);
      double ema2 = GetMAVal(h_ema2, v_shift, 0);
      double ema3 = GetMAVal(h_ema3, v_shift, 0);
      double ema4 = GetMAVal(h_ema4, v_shift, 0);

      if(ema1 == EMPTY_VALUE || ema1 == 0.0 ||
         ema2 == EMPTY_VALUE || ema2 == 0.0 ||
         ema3 == EMPTY_VALUE || ema3 == 0.0 ||
         ema4 == EMPTY_VALUE || ema4 == 0.0)
         return LAYER_NONE;

      double high  = iHigh(m_symbol,  PERIOD_CURRENT, v_shift);
      double low   = iLow(m_symbol,   PERIOD_CURRENT, v_shift);
      double close = iClose(m_symbol, PERIOD_CURRENT, v_shift);

      double tol = m_settings.LayerTouchTolerance;  // Percentage tolerance (e.g. 0.01 = 1%)

      int active_layers = 0;  // 260308_PR: Bitfield accumulator — check ALL layers

      if(bias == 1)  // LONG: look for bullish pullback-recovery
      {
         // LAYER_1_WEAK (Ribbon): Low touched EMA1, Close beyond EMA2
         if(low <= ema1 * (1.0 + tol) && close > ema2 && ema1 > ema2)
         {
            active_layers |= (int)LAYER_1_WEAK;
            if(m_settings.DebugFlow)
               PrintFormat("[LAYER] LAYER_1_WEAK (Ribbon): Low=%.5f touched EMA1=%.5f, Close=%.5f > EMA2=%.5f",
                           low, ema1, close, ema2);
         }
         // LAYER_2_MEDIUM (Ghost): Low touched EMA2, Close beyond EMA3
         if(low <= ema2 * (1.0 + tol) && close > ema3 && ema2 > ema3)
         {
            active_layers |= (int)LAYER_2_MEDIUM;
            if(m_settings.DebugFlow)
               PrintFormat("[LAYER] LAYER_2_MEDIUM (Ghost): Low=%.5f touched EMA2=%.5f, Close=%.5f > EMA3=%.5f",
                           low, ema2, close, ema3);
         }
         // LAYER_3_STRONG (Shark): Low touched EMA3, Close beyond EMA4
         if(low <= ema3 * (1.0 + tol) && close > ema4 && ema3 > ema4)
         {
            active_layers |= (int)LAYER_3_STRONG;
            if(m_settings.DebugFlow)
               PrintFormat("[LAYER] LAYER_3_STRONG (Shark): Low=%.5f touched EMA3=%.5f, Close=%.5f > EMA4=%.5f",
                           low, ema3, close, ema4);
         }
      }
      else  // SHORT (bias == -1): look for bearish pullback-recovery
      {
         // LAYER_1_WEAK (Ribbon): High touched EMA1, Close beyond EMA2
         if(high >= ema1 * (1.0 - tol) && close < ema2 && ema1 < ema2)
         {
            active_layers |= (int)LAYER_1_WEAK;
            if(m_settings.DebugFlow)
               PrintFormat("[LAYER] LAYER_1_WEAK (Ribbon): High=%.5f touched EMA1=%.5f, Close=%.5f < EMA2=%.5f",
                           high, ema1, close, ema2);
         }
         // LAYER_2_MEDIUM (Ghost): High touched EMA2, Close beyond EMA3
         if(high >= ema2 * (1.0 - tol) && close < ema3 && ema2 < ema3)
         {
            active_layers |= (int)LAYER_2_MEDIUM;
            if(m_settings.DebugFlow)
               PrintFormat("[LAYER] LAYER_2_MEDIUM (Ghost): High=%.5f touched EMA2=%.5f, Close=%.5f < EMA3=%.5f",
                           high, ema2, close, ema3);
         }
         // LAYER_3_STRONG (Shark): High touched EMA3, Close beyond EMA4
         if(high >= ema3 * (1.0 - tol) && close < ema4 && ema3 < ema4)
         {
            active_layers |= (int)LAYER_3_STRONG;
            if(m_settings.DebugFlow)
               PrintFormat("[LAYER] LAYER_3_STRONG (Shark): High=%.5f touched EMA3=%.5f, Close=%.5f < EMA4=%.5f",
                           high, ema3, close, ema4);
         }
      }

      if(m_settings.DebugFlow)
         PrintFormat("[260308_LAYER] Active layers: %s (bitfield=%d)", LayerBitfieldToString(active_layers), active_layers);

      return (EEntryLayer)active_layers;
   }

   //+------------------------------------------------------------------+
   //| Get human-readable layer name (for diagnostics)                 |
   //| 260308_PR: Handles bitfield values via LayerBitfieldToString()  |
   //+------------------------------------------------------------------+
   string GetLayerName(EEntryLayer layer)
   {
      switch(layer)
      {
         case LAYER_1_WEAK:    return "LAYER_1_WEAK (Ribbon)";
         case LAYER_2_MEDIUM:  return "LAYER_2_MEDIUM (Ghost)";
         case LAYER_3_STRONG:  return "LAYER_3_STRONG (Shark)";
         case LAYER_NONE:      return "LAYER_NONE";
         default:              return LayerBitfieldToString((int)layer);
      }
   }
};

//+--END OF SEA_SignalEngine.mqh--+