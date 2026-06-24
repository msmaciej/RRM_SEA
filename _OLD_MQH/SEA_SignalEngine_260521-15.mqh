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
// Step 5: MTF FILTER - Check higher timeframe alignment (global filter)
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
// EvaluateTS() returns: 1 (signal confirmed), 0 (no trade). Direction in LastBias().
//
// See README.md for complete documentation
//+------------------------------------------------------------------+

#property strict

// --- Anti-stale build lock (MQL5-safe: no #if, no #error)
#ifndef SEA_BUILD_TOKEN_104001
enum { __SEA_BUILD_TOKEN_MISSING_SIGNALENGINE_104001 = SEA_BUILD_TOKEN_104001 };
#endif

#define SEA_MOD_SIGNALENGINE_104001 1
#define SEA_LAYER_SLOPE_EPSILON 0.00000001
#define SEA_MIN_WEEKEND_GAP_SECONDS (2 * 24 * 60 * 60)
#define SEA_WEEKEND_GAP_SCAN_BUFFER_BARS 8
#define SEA_DOW_SUNDAY 0
#define SEA_DOW_MONDAY 1
#define SEA_DOW_FRIDAY 5
#define SEA_DOW_SATURDAY 6


#include <RRMS\SEA_Config.mqh>


// Note: Requires ST_Settings and SNewsEvent structs to be defined in main file

// UI Telemetry State
struct ST_SignalTelemetry {
   int    bias;
   int    phase;
   int    layer;
   int    votes_for;
   int    votes_total;
   string rejection_reason;
   string active_indicators;
   int    diag_layer_w;   // Raw result for L1 WEAK  sub-market: 1=pass, 0=none, -1=contra
   int    diag_layer_m;   // Raw result for L2 MEDIUM sub-market
   int    diag_layer_s;   // Raw result for L3 STRONG sub-market
   bool   phase_detection_enabled;  // True when BiasMode == BIAS_4EMA and PhaseDetectionEnabled
   bool   layer_detection_enabled;  // True when EnableLayerDetection && BiasMode == BIAS_4EMA
   string mtf_status;               // MTF alignment status for cockpit/UI
};

struct SMTFSegment {
   string text;
   color  clr;
};

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
   int passed_atr,          rejected_atr;           // ATR (volatility range)

   // Bias & Layer (passed + rejected)
   int passed_bias,         rejected_bias;
   int passed_bias_long,    passed_bias_short;   // Direction breakdown for diagnostics
   int passed_phase,        rejected_phase;
   int passed_layer_none,   rejected_layer_none;
   int passed_layer_blocked,rejected_layer_blocked;

   // Directional indicators (passed + rejected)
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
   int passed_sma_converge, rejected_sma_converge;
   int passed_dpi,          rejected_dpi;
   int passed_fib,          rejected_fib;

   // ── PHASE A.1: Pre-filter quality gates (TS=1 hardening) ──────────────
   int passed_emafan,     rejected_emafan;     // EMA fan overextension
   int passed_dpi_decel,  rejected_dpi_decel;  // DPI histogram deceleration
   int exits_dpi_hist;                          // Trades closed by DPI histogram exit
   int passed_phase_age,  rejected_phase_age;  // MinPhaseConfirmBars not met
   int passed_htf_align,  rejected_htf_align;  // Legacy field retained for compatibility
   int passed_mtf,        rejected_mtf;        // MTF global filter statistics

   // ── PHASE A.1: TE-side gates (incremented from SEA_TradeExecutor via AddTeStats) ──
   int passed_te_open_delay,    rejected_te_open_delay;
   int passed_te_bc_recheck,    rejected_te_bc_recheck;
   int passed_te_spread_median, rejected_te_spread_median;

   int signals_confirmed;
   int signals_confirmed_long, signals_confirmed_short;
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
   int h_ci, h_vrc;                      // Choppiness & Volatility Regime
   
   int h_mtf_tf1_fast;
   int h_mtf_tf1_slow;
   int h_mtf_tf2_fast;
   int h_mtf_tf2_slow;

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
   
   string      m_ts_status_string;   // Legacy compatibility
   string      m_ts_status_str;      // New Telemetry Shift 1
   string      m_te_status_str;      // New Telemetry Shift 0
      
   // Phase Detection Diagnostics
   EMarketPhase m_diag_last_phase;       // Last detected market phase
   int          m_diag_phase_confirm_bars; // Number of consecutive bars in current phase

   // --- 2c. KISS LAYER DIAGNOSTICS ---
    int         m_diag_layer_w;       // Last evaluated LayerW result (0/1)
    int         m_diag_layer_m;       // Last evaluated LayerM result (0/1)
    int         m_diag_layer_s;       // Last evaluated LayerS result (0/1)
    int         m_last_layer;         // Active layer that won (1=Weak, 2=Medium, 3=Strong, 0=none)
    // --- 2c.1 LAYER PULLBACK-RECOVERY STATE ---
    ELayerPullbackState m_layer_w_pb_state;   // LayerW pullback state
    ELayerPullbackState m_layer_m_pb_state;   // LayerM pullback state
    ELayerPullbackState m_layer_s_pb_state;   // LayerS pullback state
    double              m_layer_w_baseline;   // LayerW baseline slope
    double              m_layer_m_baseline;   // LayerM baseline slope
    double              m_layer_s_baseline;   // LayerS baseline slope
    datetime            m_layer_pb_last_update; // Last update timestamp

    // --- 2d. REJECTION STATISTICS ---
    int         m_bars_evaluated;     // Total bars evaluated by EvaluateTS()
    int         m_signals_generated;  // Signals returned (TS != 0)
    int         m_reject_filter;      // Rejections at pre-filter step (spread, time, news)
   int         m_reject_bias;        // Rejections at bias step (no trend, signal mismatch)
   int         m_reject_gate;        // Rejections at gate step (HTF, RRM, structure gates)
   int         m_reject_votes;       // Rejections at vote step

   // --- 2e. GRANULAR REJECTION STATISTICS ---
   ST_SignalTelemetry m_telemetry; // Active UI Telemetry state
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

   // --- 2i. KISS EVALUATION STATE (reset each bar, shared between KISS component functions) ---
   bool     m_eval_any_failure;          // True if any filter/gate failed this evaluation
   string   m_eval_first_failure;        // Reason string for the first failure encountered
   string   m_eval_str_F;                // Filter status telemetry string ("OK", "SPREAD", etc.)
   string   m_eval_str_B;                // Bias status telemetry string ("+", "POS", "SLOPE", etc.)
   string   m_eval_str_I;                // Indicator status telemetry string (e.g., "2/4")
   int      m_eval_layer_w;              // LayerW alignment result (0/1) set by EvaluateLayerX
   int      m_eval_layer_m;              // LayerM alignment result (0/1) set by EvaluateLayerX
   int      m_eval_layer_s;              // LayerS alignment result (0/1) set by EvaluateLayerX
   // Per-indicator results (set by EvaluateIndicatorX, read by TS_SUMMARY in EvaluateTS)
   bool     m_eval_ind_res_adx;
   bool     m_eval_ind_res_macd;
   bool     m_eval_ind_res_rsi;
   bool     m_eval_ind_res_cci;
   bool     m_eval_ind_res_mfi;
   bool     m_eval_ind_res_sto;
   bool     m_eval_ind_res_bb;
   bool     m_eval_ind_res_psar;
   bool     m_eval_ind_res_p123;
   bool     m_eval_ind_res_ross;
   bool     m_eval_ind_res_sma_converge;
   bool     m_eval_ind_res_fib;
   bool     m_eval_ind_res_dpi;
   bool     m_eval_ind_res_atr;
   bool     m_eval_ind_res_candle_body;
   bool     m_eval_ind_res_ci;
   bool     m_eval_ind_res_vrc;
   double   m_eval_vote_weight;          // Total vote weight from EvaluateIndicatorX (informational; does not gate trade decisions)
   bool     m_eval_all_pass;             // True if all enabled indicators passed

   // --- 2j. BUFFERED LOGGING (for DEBUG_SIGNALS_ONLY mode) ---
   string   m_debug_buffer[];            // Memory buffer for debug lines
   int      m_debug_buffer_size;         // Current number of lines in buffer
   bool         m_forced_debug_active;   // True while a forced-debug bar is being evaluated
   EDebugLevel  m_saved_debug_level;     // DebugLevel saved before forced override
   bool         m_saved_debug_flow;      // DebugFlow saved before forced override

   enum { DPI_HIST_BUFFER_CAPACITY = 10 };

   // --- 2j.1 DPI HISTOGRAM STATE TRACKING ---
   double   m_dpi_hist_values[DPI_HIST_BUFFER_CAPACITY]; // Rolling buffer of histogram values
   int      m_dpi_hist_buffer_size;      // Current number of values in buffer
   double   m_dpi_hist_current;          // Current histogram value
   int      m_dpi_hist_trend;            // +1 = CCI positive, -1 = CCI negative, 0 = flat
   bool     m_dpi_hist_decelerating;     // True if momentum is decreasing
   bool     m_dpi_hist_green_present;    // True if GREEN area exists (Blue & hist same side of zero)
   datetime m_dpi_hist_last_update;      // Last update timestamp

   // --- 2k. INDICATOR RESULT CACHE (eliminates duplicate checks per bar) ---
   struct SIndicatorCache {
      int    cached_shift;        // Bar shift that's cached (-1 = invalid)
      datetime cached_bar_time;   // Bar timestamp that's cached (0 = invalid)
      int    cached_bias;         // Bias for directional indicator cache (0 = invalid)

      // Cached indicator results (int: -1=not cached, 0=fail, 1=pass)
      int    adx_result;
      int    macd_result;
      int    rsi_result;
      int    cci_result;
      int    mfi_result;
      int    sto_result;
      int    bb_result;
      int    psar_result;
      int    psar_flip_result;
      int    atr_result;
      int    candlebody_result;
      int    ci_result;
      int    vrc_result;
      int    sma_converge_result;
      int    dpi_result;

      // Cached indicator values (for debug logging)
      double adx_value;
      double macd_main;
      double macd_signal;
      double rsi_value;
      double cci_value;
      double mfi_value;
      double sto_main;
      double sto_signal;
      double bb_mid;
      double bb_close;
      double psar_value;
      double psar_close;
   };

   SIndicatorCache m_ind_cache;

   //+------------------------------------------------------------------+
   //| DebugLog: Buffered logging for DEBUG_SIGNALS_ONLY mode           |
   //| - In normal modes: prints immediately                            |
   //| - In DEBUG_SIGNALS_ONLY: stores in buffer, prints only if TS≠0   |
   //+------------------------------------------------------------------+
   void DebugLog(string message)
   {
      if(m_settings.DebugLevel != DEBUG_SIGNALS_ONLY) {
         Print(message);
         return;
      }

      ArrayResize(m_debug_buffer, m_debug_buffer_size + 1);
      m_debug_buffer[m_debug_buffer_size] = message;
      m_debug_buffer_size++;
   }

   //+------------------------------------------------------------------+
   //| FlushOrClearDebugBuffer: Print buffer if signal, discard if not  |
   //+------------------------------------------------------------------+
   void FlushOrClearDebugBuffer(int ts_result)
   {
      if(m_settings.DebugLevel != DEBUG_SIGNALS_ONLY) return;

      bool should_flush = (ts_result != 0) || m_forced_debug_active;

      if(should_flush)
      {
         Print("════════════════════════════════════════════════════════════");
         if(ts_result != 0)
            Print(StringFormat("[SIGNAL] CONFIRMED: %s", (ts_result > 0 ? "LONG" : "SHORT")));
         else
            Print(StringFormat("[FORCED_DEBUG] TS=0 (no signal) | DebugEvalMode=%s", EnumToString(m_settings.DebugEvalMode)));
         Print("════════════════════════════════════════════════════════════");

         for(int i = 0; i < m_debug_buffer_size; i++)
            Print(m_debug_buffer[i]);
      }

      m_debug_buffer_size = 0;
      ArrayResize(m_debug_buffer, 0);
   }

   //+------------------------------------------------------------------+
   //| ApplyForcedDebug: Temporarily override debug level for this bar  |
   //| Called at start of EvaluateTS() with the bar's timestamp.       |
   //| If bar matches DebugEvalFrom/To window or DebugEvalAt pinpoint,  |
   //| overrides DebugLevel/DebugFlow to DebugEvalMode for this eval.   |
   //+------------------------------------------------------------------+
   void ApplyForcedDebug(datetime bar_time)
   {
      m_forced_debug_active = false;

      bool window_active = (m_settings.DebugEvalFrom > 0
                            && m_settings.DebugEvalTo   > 0
                            && bar_time >= m_settings.DebugEvalFrom
                            && bar_time <= m_settings.DebugEvalTo);

      bool at_active = (m_settings.DebugEvalAt > 0
                        && bar_time == m_settings.DebugEvalAt);

      if(!window_active && !at_active)
         return;

      m_forced_debug_active = true;
      m_saved_debug_level   = m_settings.DebugLevel;
      m_saved_debug_flow    = m_settings.DebugFlow;

      m_settings.DebugLevel = m_settings.DebugEvalMode;
      m_settings.DebugFlow  = (m_settings.DebugLevel >= DEBUG_FULL);
   }

   //+------------------------------------------------------------------+
   //| RestoreForcedDebug: Restore saved debug level after forced eval  |
   //| Must be called at every return point in EvaluateTS(), AFTER the  |
   //| FlushOrClearDebugBuffer() call.                                  |
   //+------------------------------------------------------------------+
   void RestoreForcedDebug()
   {
      if(!m_forced_debug_active)
         return;
      m_settings.DebugLevel = m_saved_debug_level;
      m_settings.DebugFlow  = m_saved_debug_flow;
      m_forced_debug_active = false;
   }

   void InvalidateIndicatorCache(int shift)
   {
      m_ind_cache.cached_shift = shift;
      m_ind_cache.cached_bar_time = iTime(m_symbol, PERIOD_CURRENT, shift);
      m_ind_cache.cached_bias  = 0;
      m_ind_cache.adx_result = -1;
      m_ind_cache.macd_result = -1;
      m_ind_cache.rsi_result = -1;
      m_ind_cache.cci_result = -1;
      m_ind_cache.mfi_result = -1;
      m_ind_cache.sto_result = -1;
      m_ind_cache.bb_result = -1;
      m_ind_cache.psar_result = -1;
      m_ind_cache.psar_flip_result = -1;
      m_ind_cache.atr_result = -1;
      m_ind_cache.candlebody_result = -1;
      m_ind_cache.ci_result = -1;
      m_ind_cache.vrc_result = -1;
      m_ind_cache.sma_converge_result = -1;
      m_ind_cache.dpi_result = -1;
   }

   bool IsCacheValidForShift(int shift) const
   {
      if(shift != m_ind_cache.cached_shift) return false;
      if(m_ind_cache.cached_bar_time == 0)  return false;
      return (iTime(m_symbol, PERIOD_CURRENT, shift) == m_ind_cache.cached_bar_time);
   }

   // Simplified buffer access for cleaner logic code

   // Version 1: No validity checking (backward compatible)
   double GetVal(int handle, int shift, int buffer_num=0) const {
      bool ignored_valid = false;
      return GetVal(handle, shift, buffer_num, ignored_valid);
   }

   bool IsValidIndicatorValue(const double value) const
   {
      return (MathIsValidNumber(value) &&
              value != EMPTY_VALUE &&
              value > -DBL_MAX &&
              value < DBL_MAX);
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

      if(!IsValidIndicatorValue(b[0])) {
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

   int GetMTFBias(const int h_fast, const int h_slow)
   {
      if(h_fast == INVALID_HANDLE || h_slow == INVALID_HANDLE)
         return 0;
   
      double fast[];  // ✅ DYNAMIC ALLOCATION
      double slow[];  // ✅ DYNAMIC ALLOCATION
      
      ArraySetAsSeries(fast, true);  // ✅ Now valid
      ArraySetAsSeries(slow, true);  // ✅ Now valid
      
      if(CopyBuffer(h_fast, 0, 0, 2, fast) != 2) return 0;
      if(CopyBuffer(h_slow, 0, 0, 2, slow) != 2) return 0;

      // Legacy compatibility mode: single-EMA slope behavior (old HTF filter)
      if(m_settings.MTF_EMA_Fast == m_settings.MTF_EMA_Slow)
      {
         double pip = GlobalPipSize(m_symbol);
         if(pip <= 0.0) return 0;
         double slope = (fast[0] - fast[1]) / pip;
         if(slope > 0.5)  return +1;
         if(slope < -0.5) return -1;
         return 0;
      }

      if(m_settings.MTF_RequirePhase)
      {
         // Require both EMAs to slope in the same direction as their position.
         // This confirms the HTF trend is active, not just a leftover crossover.
         // No fixed pip threshold — just check direction of movement.
         bool fast_rising = (fast[0] > fast[1]);
         bool slow_rising = (slow[0] > slow[1]);
         bool fast_above  = (fast[0] > slow[0]);
         
         // Bullish phase: fast above slow AND both rising (or at least not contradicting)
         // Bearish phase: fast below slow AND both falling
         if(fast_above && !fast_rising && !slow_rising)
            return 0;  // Position says bull but both EMAs falling → unclear
         if(!fast_above && fast_rising && slow_rising)
            return 0;  // Position says bear but both EMAs rising → unclear
      }

      if(fast[0] > slow[0]) return +1;
      if(fast[0] < slow[0]) return -1;
      return 0;
   }

   string MTFBiasLabel(const int mtf_bias) const
   {
      if(mtf_bias ==  1) return "LONG";
      if(mtf_bias == -1) return "SHORT";
      return "-";
   }

   string GetCompactTFLabel(const ENUM_TIMEFRAMES tf) const
   {
      switch(tf)
      {
         case PERIOD_M1:  return "M1";
         case PERIOD_M5:  return "M5";
         case PERIOD_M15: return "M15";
         case PERIOD_M30: return "M30";
         case PERIOD_H1:  return "H1";
         case PERIOD_H4:  return "H4";
         case PERIOD_D1:  return "D1";
         case PERIOD_W1:  return "W1";
         case PERIOD_MN1: return "MN";
         default:         return "??";
      }
   }

   int CheckMTFFilter(const int bias, string &reason, string &diag)
   {
      if(!m_settings.Ind_MTF_Enabled)
      {
         reason = "MTF_DISABLED";
         diag   = "[MTF] Disabled";
         return +1;
      }

      int mtf_tf1 = GetMTFBias(h_mtf_tf1_fast, h_mtf_tf1_slow);
      string tf1_label = EnumToString(m_settings.MTF_TF1);

      bool single_tf_mode = (h_mtf_tf2_fast == INVALID_HANDLE ||
                             m_settings.MTF_TF2 == PERIOD_CURRENT ||
                             m_settings.MTF_TF2 == m_settings.MTF_TF1);

      if(single_tf_mode)
      {
         if(bias == mtf_tf1)
         {
            reason = "MTF_TF1_ALIGNED";
            diag = StringFormat("[MTF] %s:%s ✓", tf1_label, MTFBiasLabel(mtf_tf1));
            return +1;
         }
         if(mtf_tf1 == 0)
         {
            reason = "MTF_TF1_UNCLEAR";
            diag = StringFormat("[MTF] %s:- (unclear)", tf1_label);
            return 0;
         }

         reason = "MTF_TF1_CONFLICT";
         diag = StringFormat("[MTF] %s:%s ✗ (vs %s)",
                            tf1_label, MTFBiasLabel(mtf_tf1), MTFBiasLabel(bias));
         return 0;
      }

      int mtf_tf2 = GetMTFBias(h_mtf_tf2_fast, h_mtf_tf2_slow);
      string tf2_label = EnumToString(m_settings.MTF_TF2);

      if(m_settings.MTF_StrictAlignment)
      {
         if(bias == mtf_tf1 && bias == mtf_tf2)
         {
            reason = "MTF_ALL_ALIGNED";
            diag = StringFormat("[MTF] %s:%s %s:%s ✓",
                                tf1_label, MTFBiasLabel(mtf_tf1),
                                tf2_label, MTFBiasLabel(mtf_tf2));
            return +1;
         }

         reason = "MTF_CONFLICT";
         diag = StringFormat("[MTF] %s:%s %s:%s ✗ (vs %s)",
                             tf1_label, MTFBiasLabel(mtf_tf1),
                             tf2_label, MTFBiasLabel(mtf_tf2),
                             MTFBiasLabel(bias));
         return 0;
      }

      int votes_agree = 0;
      if(bias == mtf_tf1) votes_agree++;
      if(bias == mtf_tf2) votes_agree++;

      if(votes_agree >= 1)
      {
         reason = "MTF_MAJORITY";
         diag = StringFormat("[MTF] %s:%s %s:%s (%d/2 agree)",
                             tf1_label, MTFBiasLabel(mtf_tf1),
                             tf2_label, MTFBiasLabel(mtf_tf2),
                             votes_agree);
         return +1;
      }

      reason = "MTF_ALL_DISAGREE";
      diag = StringFormat("[MTF] %s:%s %s:%s ✗ (0/2 agree)",
                          tf1_label, MTFBiasLabel(mtf_tf1),
                          tf2_label, MTFBiasLabel(mtf_tf2));
      return 0;
   }

   //+------------------------------------------------------------------+
   //| Check_MTF — Bool wrapper for MTF voter (EvaluateIndicatorX)      |
   //| Uses the same CheckMTFFilter logic but returns true/false        |
   //| for CAST_VOTE_STAT compatibility.                                |
   //+------------------------------------------------------------------+
   bool Check_MTF(int bias)
   {
      string reason = "";
      string diag   = "";
      return (CheckMTFFilter(bias, reason, diag) != 0);
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

      if(!IsValidIndicatorValue(arr[0])) {
         out_error = -2;
         return false;
      }

      out_error = 0;
      return true;
   }

   bool HasValidBarData(const int shift) const
   {
      if(shift < 0) return false;
      datetime t = iTime(m_symbol, PERIOD_CURRENT, shift);
      if(t <= 0) return false;

      double o = iOpen(m_symbol, PERIOD_CURRENT, shift);
      double h = iHigh(m_symbol, PERIOD_CURRENT, shift);
      double l = iLow(m_symbol, PERIOD_CURRENT, shift);
      double c = iClose(m_symbol, PERIOD_CURRENT, shift);

      if(!MathIsValidNumber(o) || !MathIsValidNumber(h) || !MathIsValidNumber(l) || !MathIsValidNumber(c))
         return false;
      if(o <= 0.0 || h <= 0.0 || l <= 0.0 || c <= 0.0)
         return false;

      return true;
   }

   bool IsWeekendGapBetween(const datetime newer_bar_time, const datetime older_bar_time) const
   {
      if(newer_bar_time <= 0 || older_bar_time <= 0 || newer_bar_time <= older_bar_time)
         return false;

      int gap_duration_seconds = (int)(newer_bar_time - older_bar_time);
      if(gap_duration_seconds < SEA_MIN_WEEKEND_GAP_SECONDS)
         return false;

      MqlDateTime newer_dt, older_dt;
      TimeToStruct(newer_bar_time, newer_dt);
      TimeToStruct(older_bar_time, older_dt);

      bool older_is_friday = (older_dt.day_of_week == SEA_DOW_FRIDAY);
      bool newer_is_monday = (newer_dt.day_of_week == SEA_DOW_MONDAY);
      return (older_is_friday && newer_is_monday);
   }

   bool IsWithinWeekendGapCooldown(const int v_shift, int &out_bars_since_gap) const
   {
      out_bars_since_gap = -1;
      if(m_settings.MinBarsAfterWeekendGap <= 0)
         return false;

      int bars_total = iBars(m_symbol, PERIOD_CURRENT);
      if(bars_total <= (v_shift + 2))
         return false;

      // Extra scan buffer catches the first valid post-gap bars even when eval shift
      // and session offsets move the detected boundary a few bars deeper.
      int scan_limit_shift = v_shift + m_settings.MinBarsAfterWeekendGap + SEA_WEEKEND_GAP_SCAN_BUFFER_BARS;
      int max_scan_shift = MathMin(bars_total - 2, scan_limit_shift);
      for(int i = v_shift; i <= max_scan_shift; i++)
      {
         datetime newer = iTime(m_symbol, PERIOD_CURRENT, i);
         datetime older = iTime(m_symbol, PERIOD_CURRENT, i + 1);
         if(IsWeekendGapBetween(newer, older))
         {
            out_bars_since_gap = i - v_shift;
            return (out_bars_since_gap < m_settings.MinBarsAfterWeekendGap);
         }
      }

      return false;
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

   //+------------------------------------------------------------------+
   // --- 5. SIGNAL CHECKS (VOTING LOGIC) ---
   //+------------------------------------------------------------------+


   //+------------------------------------------------------------------+
   // Check_ADX: ADX Strength (Trend Strength)
   //+------------------------------------------------------------------+
   // Supports three modes: 
   //    STATIC (fixed threshold), 
   //    DYNAMIC_PERCENTILE (percentile-based adaptive),
   //    PHASE_AWARE (different thresholds per market phase)
   //
   bool Check_ADX(int shift) {
      if(IsCacheValidForShift(shift) && m_ind_cache.adx_result != -1)
         return (m_ind_cache.adx_result == 1);

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
      m_ind_cache.adx_value = adx;
      m_ind_cache.adx_result = result ? 1 : 0;
      if(m_settings.DebugFlow) {
         if(m_settings.Ind_Adx_Enabled)
            DebugLog(StringFormat("[IND_ADX] ENABLED | Value=%.2f | Threshold=%.2f | Mode=%s | Result: %s",
                                  adx, threshold, modeStr, result ? "PASS" : "FAIL"));
         else
            DebugLog("[IND_ADX] DISABLED - skipped");
      }
      return result;
   }


   //+------------------------------------------------------------------+
   // Check_ATR: Volatility Range Filter (non-directional)
   //+------------------------------------------------------------------+
   // Returns: true if ATR is within configured minimum/maximum pips
   bool Check_ATR(int bias, int shift)
   {
      if(IsCacheValidForShift(shift) && m_ind_cache.atr_result != -1)
         return (m_ind_cache.atr_result == 1);

      // Utilizing the cached ATR pip value calculated during CheckFilters()
      double atr_pips = m_diag_last_atr_pips; 
      bool pass = true;
      
      if(m_settings.ATR_VoteMinPips > 0.0 && atr_pips < m_settings.ATR_VoteMinPips) pass = false;
      if(m_settings.ATR_VoteMaxPips > 0.0 && atr_pips > m_settings.ATR_VoteMaxPips) pass = false;
      m_ind_cache.atr_result = pass ? 1 : 0;
      
      if(m_settings.DebugFlow) {
         if(m_settings.Ind_Atr_Enabled)
            DebugLog(StringFormat("[IND_ATR] ENABLED | ATR=%.1f pips (Min=%.1f, Max=%.1f) | Result: %s",
                                  atr_pips, m_settings.ATR_VoteMinPips, m_settings.ATR_VoteMaxPips, pass ? "PASS" : "FAIL"));
         else
            DebugLog("[IND_ATR] DISABLED - skipped");
      }
      return pass;
   }

   //+------------------------------------------------------------------+
   // Check_BB: Bollinger Bands
   //+------------------------------------------------------------------+
   bool Check_BB(int bias, int shift) {
      if(IsCacheValidForShift(shift) &&
         m_ind_cache.bb_result != -1 &&
         m_ind_cache.cached_bias == bias)
         return (m_ind_cache.bb_result == 1);

      double mid = GetVal(h_bb, shift, 0);
      double cl  = iClose(m_symbol, PERIOD_CURRENT, shift);
      bool result;
      
      if(m_settings.BbMode == BB_TREND_FOLLOW) {
         result = (bias==1) ? (cl > mid) : (cl < mid);
      }
      else if(m_settings.BbMode == BB_WIDENING) {
         double upper_now  = GetVal(h_bb, shift,   1);
         double lower_now  = GetVal(h_bb, shift,   2);
         double upper_prev = GetVal(h_bb, shift+1, 1);
         double lower_prev = GetVal(h_bb, shift+1, 2);
         double bw_now  = upper_now  - lower_now;
         double bw_prev = upper_prev - lower_prev;
         // Fail on missing data — do not trade on invalid reads
         if(upper_now == 0.0 || lower_now == 0.0 || upper_prev == 0.0 || lower_prev == 0.0)
            result = false;
         else
            result = (bw_now > bw_prev);
         if(m_settings.DebugFlow)
            DebugLog(StringFormat("[IND_BB] BB_WIDENING | BW_now=%.5f BW_prev=%.5f | Result: %s",
                                  bw_now, bw_prev, result ? "PASS" : "FAIL"));
      }
      else {
         // Mean Reversion: Price touched Lower/Upper Band
         double lower = GetVal(h_bb, shift, 2);
         double upper = GetVal(h_bb, shift, 1);
         double low   = iLow(m_symbol, PERIOD_CURRENT, shift);
         double high  = iHigh(m_symbol, PERIOD_CURRENT, shift);
         result = (bias==1) ? (low <= lower) : (high >= upper);
      }
      m_ind_cache.cached_bias = bias;
      m_ind_cache.bb_mid = mid;
      m_ind_cache.bb_close = cl;
      m_ind_cache.bb_result = result ? 1 : 0;
      if(m_settings.DebugFlow) {
         if(m_settings.Ind_Bb_Enabled)
            DebugLog(StringFormat("[IND_BB] ENABLED | Mid=%.5f Close=%.5f | Result: %s",
                                  mid, cl, result ? "PASS" : "FAIL"));
         else
            DebugLog("[IND_BB] DISABLED - skipped");
      }
      return result;
   }

   //+------------------------------------------------------------------+
   //| Check_BarClose(): Layer-aware price position gate                |
   //|                                                                  |
   //| LAYER-AWARE BEHAVIOR:                                            |
   //|   LayerW → Checks price vs EMA1 (fast layer boundary)           |
   //|   LayerM → Checks price vs EMA2 (medium layer boundary)         |
   //|   LayerS → Checks price vs EMA3 (strong layer boundary)         |
   //|   Non-layer mode → Uses BarClose_DefaultEMA setting             |
   //|                                                                  |
   //| MODES:                                                           |
   //|   BC_DISABLED:    Always returns 1 (bcX disabled)               |
   //|   BC_FIXED_EMA:   Check vs BarClose_DefaultEMA (fixed EMA)      |
   //|   BC_LAYER_AWARE: Layer-aware check (bcW/bcM/bcS)               |
   //|     • LayerW (LAYER_1_WEAK)   → bcW: Close beyond EMA1          |
   //|     • LayerM (LAYER_2_MEDIUM) → bcM: Close beyond EMA2          |
   //|     • LayerS (LAYER_3_STRONG) → bcS: Close beyond EMA3          |
   //|   BC_BIAS_FAST:   Check vs BiasFastID EMA                       |
   //|                                                                  |
   //| Returns: 1 = pass, 0 = fail                                      |
   //+------------------------------------------------------------------+
   int Check_BarClose(int v_shift, int bias, int active_layer)
   {
      // ════════════════════════════════════════════════════════════════
      // Check if enabled
      // ════════════════════════════════════════════════════════════════
      if(!m_settings.BarClose_Enabled || m_settings.BarClose_Mode == BC_DISABLED)
      {
         if(m_settings.DebugFlow)
            DebugLog("[bcX] DISABLED → PASS (returns 1)");
         return 1;
      }
      
      // ════════════════════════════════════════════════════════════════
      // Determine which EMA to check
      // ════════════════════════════════════════════════════════════════
      double check_ema = 0.0;
      string bc_label = "bc";
      string ema_name = "";
      
      if(m_settings.BarClose_Mode == BC_LAYER_AWARE && active_layer != LAYER_NONE)
      {
         // Layer-aware mode: bcW/bcM/bcS
         switch(active_layer)
         {
            case LAYER_1_WEAK:
               check_ema = GetMAVal(h_ema1, v_shift);
               bc_label = "bcW";
               ema_name = "EMA1";
               break;
            
            case LAYER_2_MEDIUM:
               check_ema = GetMAVal(h_ema2, v_shift);
               bc_label = "bcM";
               ema_name = "EMA2";
               break;
            
            case LAYER_3_STRONG:
               check_ema = GetMAVal(h_ema3, v_shift);
               bc_label = "bcS";
               ema_name = "EMA3";
               break;
            
            default:
               check_ema = GetMAVal(h_ema1, v_shift);
               bc_label = "bc";
               ema_name = "EMA1";
               break;
         }
      }
      else if(m_settings.BarClose_Mode == BC_BIAS_FAST)
      {
         // Use BiasFastID
         switch(m_settings.BiasFastID)
         {
            case (int)ROLE_EMA1: check_ema = GetMAVal(h_ema1, v_shift); ema_name = "EMA1"; break;
            case (int)ROLE_EMA2: check_ema = GetMAVal(h_ema2, v_shift); ema_name = "EMA2"; break;
            case (int)ROLE_EMA3: check_ema = GetMAVal(h_ema3, v_shift); ema_name = "EMA3"; break;
            case (int)ROLE_EMA4: check_ema = GetMAVal(h_ema4, v_shift); ema_name = "EMA4"; break;
            default:             check_ema = GetMAVal(h_ema1, v_shift); ema_name = "EMA1"; break;
         }
         bc_label = "bc";
      }
      else  // BC_FIXED_EMA
      {
         // Use BarClose_DefaultEMA
         switch(m_settings.BarClose_DefaultEMA)
         {
            case ROLE_EMA1: check_ema = GetMAVal(h_ema1, v_shift); ema_name = "EMA1"; break;
            case ROLE_EMA2: check_ema = GetMAVal(h_ema2, v_shift); ema_name = "EMA2"; break;
            case ROLE_EMA3: check_ema = GetMAVal(h_ema3, v_shift); ema_name = "EMA3"; break;
            case ROLE_EMA4: check_ema = GetMAVal(h_ema4, v_shift); ema_name = "EMA4"; break;
            default:        check_ema = GetMAVal(h_ema1, v_shift); ema_name = "EMA1"; break;
         }
         bc_label = "bc";
      }
      
      // ════════════════════════════════════════════════════════════════
      // Check close vs EMA (with optional pip tolerance)
      // ════════════════════════════════════════════════════════════════
      double close_price = iClose(_Symbol, _Period, v_shift);
      bool passed = false;

      // BarClose_PipTolerance: allow close within N pips of the target EMA.
      // Default=0 (strict: close must be beyond EMA in trade direction).
      // Positive tolerance relaxes the check: LONG passes when close >= EMA - tol;
      // SHORT passes when close <= EMA + tol. Enables entries where price touches
      // the EMA precisely but doesn't close strictly beyond it.
      double bc_tol = m_settings.BarClose_PipTolerance * GlobalPipSize(_Symbol);
      
      if(bias == 1)  // LONG: Close must be at or above EMA (within tolerance)
      {
         passed = (close_price >= check_ema - bc_tol);
         
         if(m_settings.DebugFlow)
            DebugLog(StringFormat("[%s] LONG: Close=%s vs %s=%s tol=%.5f → %s",
                                  bc_label,
                                  DoubleToString(close_price, _Digits),
                                  ema_name,
                                  DoubleToString(check_ema, _Digits),
                                  bc_tol,
                                  (passed ? "PASS (Close >= EMA-tol)" : "FAIL (Close < EMA-tol)")));
      }
      else if(bias == -1)  // SHORT: Close must be at or below EMA (within tolerance)
      {
         passed = (close_price <= check_ema + bc_tol);
         
         if(m_settings.DebugFlow)
            DebugLog(StringFormat("[%s] SHORT: Close=%s vs %s=%s tol=%.5f → %s",
                                  bc_label,
                                  DoubleToString(close_price, _Digits),
                                  ema_name,
                                  DoubleToString(check_ema, _Digits),
                                  bc_tol,
                                  (passed ? "PASS (Close <= EMA+tol)" : "FAIL (Close > EMA+tol)")));
      }
      
      return passed ? 1 : 0;
   }

   //+------------------------------------------------------------------+
   // Check_CB: CandleBody - Overextension Filter (non-directional)
   //+------------------------------------------------------------------+
   // Wraps the existing price-action check into the standard vote API
   bool Check_CandleBody(int bias, int shift)
   {
      if(IsCacheValidForShift(shift) && m_ind_cache.candlebody_result != -1)
         return (m_ind_cache.candlebody_result == 1);

      bool pass = CheckCandleBodyIndicator(bias);
      m_ind_cache.candlebody_result = pass ? 1 : 0;
      
      if(m_settings.DebugFlow) {
         if(m_settings.Ind_CandleBody_Enabled)
            DebugLog(StringFormat("[IND_CANDLEBODY] ENABLED | Extension Check | Result: %s", pass ? "PASS" : "FAIL"));
         else
            DebugLog("[IND_CANDLEBODY] DISABLED - skipped");
      }
      return pass;
   }

   //+------------------------------------------------------------------+
   // Check_CCI: CCI (Zero or Impulse)
   //+------------------------------------------------------------------+
   bool Check_CCI(int bias, int shift) {
      if(IsCacheValidForShift(shift) &&
         m_ind_cache.cci_result != -1 &&
         m_ind_cache.cached_bias == bias)
         return (m_ind_cache.cci_result == 1);

      double c = GetVal(h_cci, shift);
      bool result;
      if(m_settings.CciMode == CCI_TREND_ZERO) result = (bias==1) ? (c > 0) : (c < 0);
      else result = (bias==1) ? (c > 100) : (c < -100);
      m_ind_cache.cached_bias = bias;
      m_ind_cache.cci_value = c;
      m_ind_cache.cci_result = result ? 1 : 0;
      if(m_settings.DebugFlow) {
         if(m_settings.Ind_Cci_Enabled)
            DebugLog(StringFormat("[IND_CCI] ENABLED | Value=%.2f | Result: %s",
                                  c, result ? "PASS" : "FAIL"));
         else
            DebugLog("[IND_CCI] DISABLED - skipped");
      }
      return result;
   }
   
      //+------------------------------------------------------------------+
   //| ComputeDPI_CCI — inline CCI matching DPI_mc_main.mq5             |
   //|                                                                   |
   //| Bit-identical to CalculateCCI() in DPI_mc_main.mq5 so the EA's   |
   //| CCI vote matches the on-chart ribbon color exactly.              |
   //|                                                                   |
   //| Formula: CCI = (price - SMA) / (0.015 * mean_deviation)          |
   //|   price = applied price selected via DPI_CCI_AppliedPrice         |
   //|   SMA   = simple moving average over DPI_CCI_Period bars         |
   //|                                                                   |
   //| Returns CCI value at v_shift, or 0.0 if insufficient bars.       |
   //| No handles, no CopyBuffer — safe under MQL5 on macOS/Wine.       |
   //+------------------------------------------------------------------+
   double ComputeDPI_CCI(const int v_shift)
   {
      const int period = MathMax(1, m_settings.DPI_CCI_Period);
      const int ap     = m_settings.DPI_CCI_AppliedPrice;

      // Need v_shift + period bars available
      if(Bars(m_symbol, PERIOD_CURRENT) < v_shift + period + 1)
         return 0.0;

      // Pull period prices starting at v_shift (working back into history)
      double prices[];
      ArrayResize(prices, period);

      double sum = 0.0;
      for(int i = 0; i < period; i++)
      {
         int idx = v_shift + i;
         double p = GetDPI_CCI_Price(idx, ap);
         prices[i] = p;
         sum += p;
      }

      double sma = sum / (double)period;

      double mean_deviation = 0.0;
      for(int i = 0; i < period; i++)
         mean_deviation += MathAbs(prices[i] - sma);
      mean_deviation /= (double)period;

      if(mean_deviation == 0.0)
         return 0.0;

      double current_price = GetDPI_CCI_Price(v_shift, ap);
      return (current_price - sma) / (0.015 * mean_deviation);
   }

   //+------------------------------------------------------------------+
   //| UpdateDPIHistogramState — Track DPI histogram momentum & trend   |
   //|                                                                   |
   //| Called once per bar in EvaluateTS() to update histogram state.   |
   //| Calculates:                                                       |
   //|   - Current CCI value (from ComputeDPI_CCI)                      |
   //|   - CCI trend direction (+1 positive, -1 negative, 0 flat)       |
   //|   - GREEN presence (Blue & hist aligned on same side of zero)    |
   //|     GREEN above zero = bullish momentum confirmation             |
   //|     GREEN below zero = bearish momentum confirmation             |
   //|     GREEN declining/vanished = OB/OS, pullback likely            |
   //|   - Deceleration (momentum decreasing over lookback period)      |
   //|                                                                   |
   //| Returns: void (updates internal state only)                      |
   //+------------------------------------------------------------------+
   void UpdateDPIHistogramState(const int v_shift)
   {
      if(!m_settings.DPI_HistTrackingEnabled) return;

      datetime bar_time = iTime(m_symbol, PERIOD_CURRENT, v_shift);

      // Update only once per bar
      if(m_dpi_hist_last_update == bar_time) return;
      m_dpi_hist_last_update = bar_time;

      // Calculate current CCI value (histogram proxy)
      double cci = ComputeDPI_CCI(v_shift);
      m_dpi_hist_current = cci;

      // Shift rolling buffer (newest at index 0)
      for(int i = DPI_HIST_BUFFER_CAPACITY - 1; i > 0; i--)
         m_dpi_hist_values[i] = m_dpi_hist_values[i - 1];

      m_dpi_hist_values[0] = cci;
      if(m_dpi_hist_buffer_size < DPI_HIST_BUFFER_CAPACITY) m_dpi_hist_buffer_size++;

      // Determine CCI trend direction (note: this is CCI sign, NOT green presence)
      if(cci > 0.0)      m_dpi_hist_trend = 1;   // CCI positive
      else if(cci < 0.0) m_dpi_hist_trend = -1;  // CCI negative
      else               m_dpi_hist_trend = 0;   // Flat

      // ── GREEN presence: Blue and hist on same side of zero ──
      // GREEN exists both above zero (bullish) and below zero (bearish).
      // It represents momentum alignment, not direction.
      // Uses ComputeDPIMainHist to get actual Blue/hist state.
      m_dpi_hist_green_present = false;
      {
         double hist_cur = 0.0, hist_prev = 0.0;
         bool   dpi_green = false, dpi_macd_agree = false;
         double green_mag_cur = 0.0, green_mag_prev = 0.0;
         if(ComputeDPIMainHist(v_shift, hist_cur, hist_prev, dpi_green, dpi_macd_agree,
                               green_mag_cur, green_mag_prev))
         {
            m_dpi_hist_green_present = (green_mag_cur > 0.0);
         }
      }

      // Detect deceleration (momentum decreasing)
      m_dpi_hist_decelerating = false;
      int lookback_max = DPI_HIST_BUFFER_CAPACITY - 1;
      int lookback = MathMax(1, MathMin(lookback_max, m_settings.DPI_HistDecelLookback));
      if(m_dpi_hist_buffer_size >= lookback + 1)
      {
         double momentum_threshold = MathMax(0.0, m_settings.DPI_HistMomentumThreshold);
         bool is_decelerating = true;
         for(int i = 1; i < lookback; i++)
         {
            double delta_newer = MathAbs(m_dpi_hist_values[i - 1] - m_dpi_hist_values[i]);
            double delta_older = MathAbs(m_dpi_hist_values[i] - m_dpi_hist_values[i + 1]);

            // Ignore tiny momentum changes below configured threshold
            if(delta_older < momentum_threshold)
            {
               is_decelerating = false;
               break;
            }

            // If any recent bar shows increasing momentum, not decelerating
            if(delta_newer + momentum_threshold >= delta_older)
            {
               is_decelerating = false;
               break;
            }
         }
         m_dpi_hist_decelerating = is_decelerating;
      }

      // Debug logging
      if(m_settings.DebugFlow)
      {
         DebugLog(StringFormat("[DPI_HIST] CCI=%.2f | CCI_Trend=%s | GREEN=%s | Decel=%s | Buffer=%d/%d",
                               cci,
                               (m_dpi_hist_trend == 1 ? "POS" : m_dpi_hist_trend == -1 ? "NEG" : "FLAT"),
                               m_dpi_hist_green_present ? "YES" : "NO",
                               m_dpi_hist_decelerating ? "YES" : "NO",
                               m_dpi_hist_buffer_size, DPI_HIST_BUFFER_CAPACITY));
      }
   }

   //+------------------------------------------------------------------+
   //| CalculateSlopeRatio — Ratio-based slope analysis                 |
   //+------------------------------------------------------------------+
   double CalculateSlopeRatio(int ema_handle, int shift, int lookback, double &out_baseline)
   {
      out_baseline = 0.0;
      if(ema_handle == INVALID_HANDLE || lookback < 1)
         return 0.0;

      double ema_now  = GetMAVal(ema_handle, shift);
      double ema_then = GetMAVal(ema_handle, shift + lookback);
      double ema_prev = GetMAVal(ema_handle, shift + 1);

      if(ema_now == EMPTY_VALUE || ema_then == EMPTY_VALUE || ema_prev == EMPTY_VALUE)
         return 0.0;

      double baseline_slope = (ema_now - ema_then) / (double)lookback;
      out_baseline = baseline_slope;

      double current_change = ema_now - ema_prev;
      if(MathAbs(baseline_slope) < SEA_LAYER_SLOPE_EPSILON)
         return 0.0;

      return current_change / baseline_slope;
   }

   //+------------------------------------------------------------------+
   //| UpdateSingleLayerPullback — State machine for one layer          |
   //+------------------------------------------------------------------+
   // P2: recovery_ratio parameter allows per-layer override.
   // Caller passes the effective ratio (per-layer or global fallback).
   void UpdateSingleLayerPullback(int fast_ema_handle, int v_shift, int lookback,
                                  ELayerPullbackState &state, double &baseline, string label,
                                  double recovery_ratio)
   {
      double baseline_slope = 0.0;
      double ratio = CalculateSlopeRatio(fast_ema_handle, v_shift, lookback, baseline_slope);
      baseline = baseline_slope;
      bool baseline_bullish = (baseline_slope > 0.0);
      // FIX: current direction must come from the actual slope direction (current_change),
      // not from ratio sign. ratio = current_change / baseline_slope is a MAGNITUDE measure.
      // When both are negative (decline): neg/neg = positive ratio, which is NOT bullish.
      double ema_now  = GetMAVal(fast_ema_handle, v_shift);
      double ema_prev = GetMAVal(fast_ema_handle, v_shift + 1);
      bool current_bullish  = (ema_now > ema_prev);

      // Keep the thresholds separate because users can tune them independently.
      // If they overlap, either threshold can trigger the pullback state.
      bool is_weakened = (MathAbs(ratio) < m_settings.LayerPullbackRatio);
      bool is_flat     = (MathAbs(ratio) < m_settings.LayerFlatRatio);
      bool is_pullback = (is_weakened || is_flat);
      if(m_settings.LayerAllowReversalPullback)
      {
         if(baseline_bullish != current_bullish)
            is_pullback = true;
      }

      bool is_recovery = false;
      if(state == LAYER_PB_DETECTED)
      {
         // P2: use per-layer recovery_ratio instead of global
         if(baseline_bullish == current_bullish &&
            MathAbs(ratio) >= recovery_ratio)
            is_recovery = true;
      }

      ELayerPullbackState prev_state = state;
      if(state == LAYER_PB_NONE && is_pullback)
         state = LAYER_PB_DETECTED;
      else if(state == LAYER_PB_DETECTED && is_recovery)
         state = LAYER_PB_RECOVERED;
      else if(state == LAYER_PB_RECOVERED && is_pullback)
         state = LAYER_PB_DETECTED;

      if(m_settings.DebugFlow && state != prev_state)
      {
         DebugLog(StringFormat("[%s_PB] State: %s -> %s | Ratio=%.2f | RecoveryThreshold=%.2f | Baseline=%.5f",
                               label,
                               EnumToString(prev_state),
                               EnumToString(state),
                               ratio,
                               recovery_ratio,
                               baseline_slope));
      }
   }

   //+------------------------------------------------------------------+
   //| UpdateLayerPullbackStates — Update pullback state for all layers |
   //+------------------------------------------------------------------+
   void UpdateLayerPullbackStates(int v_shift)
   {
      if(!m_settings.LayerPullbackEnabled) return;

      datetime bar_time = iTime(m_symbol, PERIOD_CURRENT, v_shift);
      if(m_layer_pb_last_update == bar_time) return;
      m_layer_pb_last_update = bar_time;

      int lookback = m_settings.LayerBaselineLookback;
      double global_rr = m_settings.LayerRecoveryRatio;

      // P2: Resolve per-layer recovery ratio (-1.0 = use global)
      double rr_w = (m_settings.LayerRecoveryRatio_W >= 0.0) ? m_settings.LayerRecoveryRatio_W : global_rr;
      double rr_m = (m_settings.LayerRecoveryRatio_M >= 0.0) ? m_settings.LayerRecoveryRatio_M : global_rr;
      double rr_s = (m_settings.LayerRecoveryRatio_S >= 0.0) ? m_settings.LayerRecoveryRatio_S : global_rr;

      UpdateSingleLayerPullback(h_ema1, v_shift, lookback,
                                m_layer_w_pb_state, m_layer_w_baseline, "LayerW", rr_w);
      UpdateSingleLayerPullback(h_ema2, v_shift, lookback,
                                m_layer_m_pb_state, m_layer_m_baseline, "LayerM", rr_m);
      UpdateSingleLayerPullback(h_ema3, v_shift, lookback,
                                m_layer_s_pb_state, m_layer_s_baseline, "LayerS", rr_s);
   }

   //+------------------------------------------------------------------+
   //| GetDPI_CCI_Price — applied-price selector matching DPI_mc_main   |
   //|                                                                   |
   //| Mapping (matches ENUM_CCI_PRICE in DPI_mc_main.mq5):             |
   //|   0 = TYPICAL  (H+L+C)/3                                         |
   //|   1 = CLOSE                                                       |
   //|   2 = OPEN                                                        |
   //|   3 = HIGH                                                        |
   //|   4 = LOW                                                         |
   //|   5 = MEDIAN   (H+L)/2                                           |
   //|   6 = WEIGHTED (H+L+C+C)/4                                       |
   //+------------------------------------------------------------------+
   double GetDPI_CCI_Price(const int shift, const int applied_price)
   {
      double h = iHigh (m_symbol, PERIOD_CURRENT, shift);
      double l = iLow  (m_symbol, PERIOD_CURRENT, shift);
      double c = iClose(m_symbol, PERIOD_CURRENT, shift);
      double o = iOpen (m_symbol, PERIOD_CURRENT, shift);

      switch(applied_price)
      {
         case 0: return (h + l + c) / 3.0;          // TYPICAL
         case 1: return c;                           // CLOSE
         case 2: return o;                           // OPEN
         case 3: return h;                           // HIGH
         case 4: return l;                           // LOW
         case 5: return (h + l) / 2.0;              // MEDIAN
         case 6: return (h + l + c + c) / 4.0;      // WEIGHTED
         default: return (h + l + c) / 3.0;
      }
   }
   
   //+------------------------------------------------------------------+
   // CalculateCI: Calculate Choppiness Index for given shift
   //+------------------------------------------------------------------+
   // Formula: 100 * log10(Σ TR) / log10(range)
   // Returns: CI value (0-100), where >61.8 indicates ranging market
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
   
      // ══════════════════════════════════════════════════════════════════
      // SAFETY: Reject invalid data BEFORE taking logarithms
      // ══════════════════════════════════════════════════════════════════
      const double min_value = 0.00001;  // 1 pip for 5-digit brokers
      
      // Zero or near-zero range = flat market = maximum choppiness
      if(range < min_value) return 100.0;
      
      // Zero or negative sum_tr = invalid data = maximum choppiness
      if(sum_tr < min_value) return 100.0;
   
      // ══════════════════════════════════════════════════════════════════
      // CORRECTED Choppiness Index Formula (TradingView standard)
      // ══════════════════════════════════════════════════════════════════
      // CI = 100 * log10(sum_TR) / log10(range)
      // Lower values (0-38.2) = strong trend
      // Higher values (61.8-100) = choppy/ranging market
      double ci = 100.0 * MathLog10(sum_tr) / MathLog10(range);
      
      // Clamp result to valid range [0, 100]
      if(ci < 0.0) ci = 0.0;
      if(ci > 100.0) ci = 100.0;
   
      return ci;
   }

   //+------------------------------------------------------------------+
   // Check_CI: Choppiness Index vote (non-directional ranging market filter)
   //+------------------------------------------------------------------+
   // Returns: true if market is NOT ranging (CI < threshold)
   bool Check_CI(int bias, int shift)
   {
      if(IsCacheValidForShift(shift) && m_ind_cache.ci_result != -1)
         return (m_ind_cache.ci_result == 1);

      double ci = CalculateCI(shift);

      // Reject if CI indicates ranging market
      bool is_trending = (ci < m_settings.CI_RangingThreshold);
      m_ind_cache.ci_result = is_trending ? 1 : 0;

      if(m_settings.DebugFlow) {
         DebugLog(StringFormat("[IND_CI] CI=%.2f | Threshold=%.2f | %s | Result: %s",
                               ci, m_settings.CI_RangingThreshold,
                               is_trending ? "TRENDING" : "RANGING",
                               is_trending ? "PASS" : "FAIL"));
      }

      return is_trending;
   }

   //+------------------------------------------------------------------+
   // Check_MACD: MACD — two-tier architecture (base mode + optional filters)
   //+------------------------------------------------------------------+
   // MACD Indicator buffer outputs:
   //   Buffer 0 = MACD Main Line (fast EMA - slow EMA)
   //   Buffer 1 = MACD Signal Line (SMA of Main Line)
   //   Buffer 2 = MACD Histogram (Main - Signal)
   //
   bool Check_MACD(int bias, int shift) {
      if(!m_settings.Ind_Macd_Enabled) {
         if(m_settings.DebugFlow) DebugLog("[IND_MACD] DISABLED - skipped");
         return false;
      }

      if(IsCacheValidForShift(shift) &&
         m_ind_cache.macd_result != -1 &&
         m_ind_cache.cached_bias == bias)
         return (m_ind_cache.macd_result == 1);

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
            DebugLog(StringFormat("[IND_MACD] ENABLED | Main=%.5f Signal=%.5f | Result: FAIL (base mode)",
                                  m, s));
         m_ind_cache.cached_bias = bias;
         m_ind_cache.macd_main = m;
         m_ind_cache.macd_signal = s;
         m_ind_cache.macd_result = 0;
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
               DebugLog(StringFormat("[IND_MACD] ENABLED | Main=%.5f Signal=%.5f | Result: FAIL (slope min)",
                                     m, s));
            m_ind_cache.cached_bias = bias;
            m_ind_cache.macd_main = m;
            m_ind_cache.macd_signal = s;
            m_ind_cache.macd_result = 0;
            return false;
         }

         // Check direction matches bias
         bool accelerating = (bias == 1) ? (slope > 0) : (slope < 0);
         if(!accelerating) {
            if(m_settings.DebugFlow)
               DebugLog(StringFormat("[IND_MACD] ENABLED | Main=%.5f Signal=%.5f | Result: FAIL (slope dir)",
                                     m, s));
            m_ind_cache.cached_bias = bias;
            m_ind_cache.macd_main = m;
            m_ind_cache.macd_signal = s;
            m_ind_cache.macd_result = 0;
            return false;
         }
      }

      // Filter B: Divergence (price vs MACD disagreement)
      if(m_settings.MacdRequireDivergence) {
         if(!CheckMACDDivergence(bias, shift)) {
            if(m_settings.DebugFlow)
               DebugLog(StringFormat("[IND_MACD] ENABLED | Main=%.5f Signal=%.5f | Result: FAIL (divergence)",
                                     m, s));
            m_ind_cache.cached_bias = bias;
            m_ind_cache.macd_main = m;
            m_ind_cache.macd_signal = s;
            m_ind_cache.macd_result = 0;
            return false;
         }
      }

      // Filter C: Hook (histogram reversal)
      if(m_settings.MacdRequireHook) {
         double h_prev = GetVal(h_macd, shift + 1, 0) - GetVal(h_macd, shift + 1, 1);
         bool hook = (bias == 1) ? (h > 0 && h_prev <= 0) : (h < 0 && h_prev >= 0);
         if(!hook) {
            if(m_settings.DebugFlow)
               DebugLog(StringFormat("[IND_MACD] ENABLED | Main=%.5f Signal=%.5f | Result: FAIL (hook)",
                                     m, s));
            m_ind_cache.cached_bias = bias;
            m_ind_cache.macd_main = m;
            m_ind_cache.macd_signal = s;
            m_ind_cache.macd_result = 0;
            return false;
         }
      }

      m_ind_cache.cached_bias = bias;
      m_ind_cache.macd_main = m;
      m_ind_cache.macd_signal = s;
      m_ind_cache.macd_result = 1;
      if(m_settings.DebugFlow)
         DebugLog(StringFormat("[IND_MACD] ENABLED | Main=%.5f Signal=%.5f | Result: PASS",
                               m, s));
      return true;  // Base + all filters passed
   }

   // MACD Helper: Detect bars since MACD main/signal crossover
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

   // MACD Helper: Detect bars since MACD zero line cross
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

   // MACD Helper: Check for bullish/bearish divergence
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

   // MACD Mode description: returns human-readable string for active MACD configuration
   string GetMACDModeDescription()
   {
      return ::GetMACDModeDescription(
         m_settings.MacdVoteMode,
         m_settings.MacdRequireSlope,
         m_settings.MacdRequireDivergence,
         m_settings.MacdRequireHook
      );
   }

   //+------------------------------------------------------------------+
   // Check_MFI: MFI (Money Flow)
   //+------------------------------------------------------------------+
   bool Check_MFI(int bias, int shift) {
      if(IsCacheValidForShift(shift) &&
         m_ind_cache.mfi_result != -1 &&
         m_ind_cache.cached_bias == bias)
         return (m_ind_cache.mfi_result == 1);

      double mfi = GetVal(h_mfi, shift);
      bool result = (bias==1) ? (mfi > m_settings.T_MfiOB) : (mfi < m_settings.T_MfiOS);
      m_ind_cache.cached_bias = bias;
      m_ind_cache.mfi_value = mfi;
      m_ind_cache.mfi_result = result ? 1 : 0;
      if(m_settings.DebugFlow) {
         if(m_settings.Ind_Mfi_Enabled)
            DebugLog(StringFormat("[IND_MFI] ENABLED | Value=%.2f | Result: %s",
                                  mfi, result ? "PASS" : "FAIL"));
         else
            DebugLog("[IND_MFI] DISABLED - skipped");
      }
      return result;
   }

   //+------------------------------------------------------------------+
   // Check_PSAR: PSAR (basic price vs. PSAR position check)
   //+------------------------------------------------------------------+
   bool Check_PSAR(int bias, int shift) {
      if(IsCacheValidForShift(shift) &&
         m_ind_cache.psar_result != -1 &&
         m_ind_cache.cached_bias == bias)
         return (m_ind_cache.psar_result == 1);

      double p = GetVal(h_psar, shift);
      double cl = iClose(m_symbol, PERIOD_CURRENT, shift);

      bool result = (bias==1) ? (cl > p) : (cl < p);

      // PSAR_FlipGraceBars: when the dot is on the wrong side but recently flipped there
      // (adverse flip within N bars), still pass the vote.  This handles pullback scenarios
      // where PSAR temporarily flips against the trend direction and hasn't flipped back yet
      // at the entry bar.  Default=0 (disabled).
      if(!result && m_settings.PSAR_FlipGraceBars > 0)
      {
         datetime adverse_flip = (bias ==  1) ? m_psar_last_flip_time_bear
                                              : m_psar_last_flip_time_bull;
         if(adverse_flip > 0)
         {
            int flip_bar   = iBarShift(m_symbol, PERIOD_CURRENT, adverse_flip, false);
            int bars_since = (flip_bar >= 0) ? (flip_bar - shift) : INT_MAX;
            if(bars_since >= 0 && bars_since <= m_settings.PSAR_FlipGraceBars)
            {
               if(m_settings.DebugFlow)
                  DebugLog(StringFormat("[PSAR_GRACE] dot wrong side but %d bars since adverse flip (grace=%d) → PASS",
                                        bars_since, m_settings.PSAR_FlipGraceBars));
               result = true;
            }
         }
      }

      m_ind_cache.cached_bias = bias;
      m_ind_cache.psar_value = p;
      m_ind_cache.psar_close = cl;
      m_ind_cache.psar_result = result ? 1 : 0;

      if(m_settings.DebugFlow) {
         datetime bar_time = iTime(m_symbol, PERIOD_CURRENT, shift);
         DebugLog(StringFormat("[PSAR_DOT_CHECK] Bar: %s | Bias: %s | PSAR=%.5f | Close=%.5f | Dot position: %s | Result: %s",
                               TimeToString(bar_time, TIME_DATE|TIME_MINUTES),
                               (bias > 0 ? "LONG" : "SHORT"),
                               p, cl,
                               (cl > p ? "BELOW price" : "ABOVE price"),
                               (result ? "PASS" : "FAIL (dot on wrong side)")));
      }

      return result;
   }

   //+------------------------------------------------------------------+
   // Detect PSAR flip
   //+------------------------------------------------------------------+
   // detect if a flip occurred at the given bar shift.
   // A flip occurs when PSAR crosses 
   //    from above price to below price (bullish: +1) or
   //    from below price to above price (bearish: -1).
   // Returns 1 (bullish flip), -1 (bearish flip), or 0 (no flip / insufficient data).
   // Uses closed bars only: checks shift vs shift+1 (shift+1 is the previous closed bar).
   int DetectPSARFlipAt(int shift) {
      // Log handle status periodically
      static datetime last_log_time = 0;
      datetime current_time = TimeCurrent();
      
      if(current_time - last_log_time > 86400) { // Log once per day
         last_log_time = current_time;
         DebugLog(StringFormat("[PSAR_HEALTH] Date: %s | Handle: %d | Valid: %s",
                               TimeToString(current_time, TIME_DATE),
                               h_psar,
                               (h_psar != INVALID_HANDLE) ? "YES" : "NO"));
      }
      // Check if handle is still valid
      if(h_psar == INVALID_HANDLE) {
         if(m_settings.DebugFlow)
            DebugLog("[PSAR_ERROR] Handle became INVALID! Need to reinitialize.");
         return 0;
      }
      
      bool psar_curr_valid = false;
      bool psar_prev_valid = false;

      double psar_curr = GetVal(h_psar, shift, 0, psar_curr_valid);
      double psar_prev = GetVal(h_psar, shift + 1, 0, psar_prev_valid);

      if(!psar_curr_valid || !psar_prev_valid) {
         if(m_settings.DebugFlow)
            DebugLog(StringFormat("[PSAR_FLIP_DETECT] shift=%d | SKIP: PSAR data not ready (history loading)", shift));
         return 0;
      }

      double cl_curr = iClose(m_symbol, PERIOD_CURRENT, shift);
      double cl_prev = iClose(m_symbol, PERIOD_CURRENT, shift + 1);

      if(cl_curr == 0.0 || cl_prev == 0.0) {
         if(m_settings.DebugFlow)
            DebugLog(StringFormat("[PSAR_FLIP_DETECT] shift=%d | SKIP: close price not available", shift));
         return 0;
      }

      if(m_settings.DebugFlow)
         DebugLog(StringFormat("[PSAR_FLIP_DETECT] shift=%d | psar_curr=%.5f cl_curr=%.5f psar_prev=%.5f cl_prev=%.5f",
                               shift, psar_curr, cl_curr, psar_prev, cl_prev));

      bool curr_bullish = (cl_curr > psar_curr);
      bool prev_bullish = (cl_prev > psar_prev);

      int flip = 0;
      if(curr_bullish && !prev_bullish) flip =  1;   // Bullish flip: PSAR moved below price
      if(!curr_bullish && prev_bullish) flip = -1;   // Bearish flip: PSAR moved above price

      if(m_settings.DebugFlow)
         DebugLog(StringFormat("[PSAR_FLIP_DETECT] curr_bullish=%s prev_bullish=%s -> result=%s",
                               (curr_bullish ? "true" : "false"),
                               (prev_bullish ? "true" : "false"),
                               (flip == 1 ? "BULLISH FLIP" : (flip == -1 ? "BEARISH FLIP" : "NO FLIP (same side)"))));

      if(m_settings.DebugFlow && flip != 0) {
         datetime bar_time = iTime(m_symbol, PERIOD_CURRENT, shift);
         DebugLog("[PSAR_FLIP_DETECT] ══════════════════════════════════");
         DebugLog(StringFormat("[PSAR_FLIP_DETECT] Bar: %s (shift=%d)",
                               TimeToString(bar_time, TIME_DATE|TIME_MINUTES), shift));
         DebugLog(StringFormat("[PSAR_FLIP_DETECT] Flip type: %s",
                               (flip == 1 ? "BULLISH (dot moved BELOW price)" : "BEARISH (dot moved ABOVE price)")));
         DebugLog(StringFormat("[PSAR_FLIP_DETECT] Previous bar: PSAR=%.5f Close=%.5f (close %s PSAR)",
                               psar_prev, cl_prev, (prev_bullish ? "ABOVE" : "BELOW")));
         DebugLog(StringFormat("[PSAR_FLIP_DETECT] Current bar:  PSAR=%.5f Close=%.5f (close %s PSAR)",
                               psar_curr, cl_curr, (curr_bullish ? "ABOVE" : "BELOW")));
      }

      return flip;
   }

   //+------------------------------------------------------------------+
   // PSAR flip tracker 
   //+------------------------------------------------------------------+
   // call once per bar close to record the most recent flip.
   // Stores direction-specific timestamps so bullish and bearish flips are tracked independently.
   void UpdatePSARFlipTracking(int shift = 1) {
      if(m_settings.DebugFlow)
         DebugLog("[DEBUG_TEST] UpdatePSARFlipTracking() CALLED");
      int flip = DetectPSARFlipAt(shift);
      if(flip != 0) {
         datetime flip_time = iTime(m_symbol, PERIOD_CURRENT, shift);
         if(flip == 1) {
            m_psar_last_flip_time_bull = flip_time;
            if(m_settings.DebugFlow)
               DebugLog(StringFormat("[PSAR_FLIP_TRACK] BULLISH flip REGISTERED at %s (stored in m_psar_last_flip_time_bull)",
                                     TimeToString(flip_time, TIME_DATE|TIME_MINUTES)));
         }
         else if(flip == -1) {
            m_psar_last_flip_time_bear = flip_time;
            if(m_settings.DebugFlow)
               DebugLog(StringFormat("[PSAR_FLIP_TRACK] BEARISH flip REGISTERED at %s (stored in m_psar_last_flip_time_bear)",
                                     TimeToString(flip_time, TIME_DATE|TIME_MINUTES)));
         }
      }
   }

   //+------------------------------------------------------------------+
   // Get Bars Since Last Flip
   //+------------------------------------------------------------------+
   // Returns the number of bars elapsed since the last recorded PSAR flip 
   // in the given bias direction, measured from current_shift. 
   // Returns INT_MAX if no flip has been recorded for that direction.
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

   //+------------------------------------------------------------------+
   // GetEffectivePsarFlipDelay — P1: Resolve layer-aware PSAR flip delay
   //+------------------------------------------------------------------+
   // Returns the effective delay for the current active layer.
   // m_last_layer is set by EvaluateL() which runs BEFORE EvaluateI(),
   // so the active layer is always known when PSAR votes.
   // -99 = no override → fall back to global Vote_PsarFlipDelay.
   int GetEffectivePsarFlipDelay()
   {
      int layer_delay = -99;
      switch(m_last_layer)
      {
         case 1: layer_delay = m_settings.Vote_PsarFlipDelay_W; break;
         case 2: layer_delay = m_settings.Vote_PsarFlipDelay_M; break;
         case 3: layer_delay = m_settings.Vote_PsarFlipDelay_S; break;
      }

      int effective = (layer_delay > -99) ? layer_delay : m_settings.Vote_PsarFlipDelay;

      if(m_settings.DebugFlow && layer_delay > -99)
         DebugLog(StringFormat("[PSAR_FLIP_DELAY] Layer L%d override: delay=%d (global=%d)",
                               m_last_layer, effective, m_settings.Vote_PsarFlipDelay));
      return effective;
   }

   //+------------------------------------------------------------------+
   // Check_Psar_WithFlip
   //+------------------------------------------------------------------+
   // Vote 9 (enhanced): PSAR with countdown-based flip validation.
   // Passes only if:
   //   1. PSAR dot is on the correct side of price (basic position check)
   //   2. A flip in the matching direction has been recorded
   //   3. The flip occurred within the last Vote_PsarFlipDelay bars
   //   P1: delay is now layer-aware via GetEffectivePsarFlipDelay()
   bool Check_PSAR_WithFlip(int bias, int shift) {
      if(IsCacheValidForShift(shift) &&
         m_ind_cache.psar_flip_result != -1 &&
         m_ind_cache.cached_bias == bias)
         return (m_ind_cache.psar_flip_result == 1);

      if(m_settings.DebugFlow) {
         DebugLog("[DEBUG_TEST] Check_PSAR_WithFlip() CALLED");
         DebugLog(StringFormat("[DEBUG_TEST] bias=%d shift=%d DebugFlow=%s",
                               bias, shift, m_settings.DebugFlow ? "TRUE" : "FALSE"));
      }

      // P1: Resolve effective delay (layer-aware or global fallback)
      int effective_delay = GetEffectivePsarFlipDelay();

      // Fast-path: persistent mode (-1) — check dot position only, no flip tracking
      if(effective_delay == -1) {
         bool result = Check_PSAR(bias, shift);
         if(m_settings.DebugFlow)
            DebugLog(StringFormat("[PSAR_FLIP_CHECK] PERSISTENT mode: dot check only → %s", result ? "PASS" : "FAIL"));
         m_ind_cache.cached_bias = bias;
         m_ind_cache.psar_flip_result = result ? 1 : 0;
         return result;
      }

      // START DEBUG LOGGING BANNER
      if(m_settings.DebugFlow) {
         datetime eval_bar_time = iTime(m_symbol, PERIOD_CURRENT, shift);
         DebugLog("[PSAR_FLIP_CHECK] ===========================================");
         DebugLog(StringFormat("[PSAR_FLIP_CHECK] Evaluating bar: %s (shift=%d)",
                               TimeToString(eval_bar_time, TIME_DATE|TIME_MINUTES), shift));
         DebugLog(StringFormat("[PSAR_FLIP_CHECK] Required bias: %s", (bias > 0 ? "LONG" : "SHORT")));
      }

      // 1. PSAR dot must be on correct side NOW
      double psar_val  = GetVal(h_psar, shift);
      double close_val = iClose(m_symbol, PERIOD_CURRENT, shift);
      bool dot_correct = Check_PSAR(bias, shift);

      if(!dot_correct) {
         m_diag_last_reason = "PSAR_DOT_WRONG_SIDE";

         if(m_settings.DebugFlow) {
            DebugLog("[PSAR_FLIP_CHECK] STEP 1 FAILED: DOT WRONG SIDE");
            DebugLog(StringFormat("[PSAR_FLIP_CHECK]    PSAR=%.5f | Close=%.5f | Dot is %s",
                                  psar_val, close_val,
                                  (close_val > psar_val ? "BELOW price (bullish)" : "ABOVE price (bearish)")));
            DebugLog(StringFormat("[PSAR_FLIP_CHECK]    Need: %s | Got: %s",
                                  (bias > 0 ? "dot BELOW price" : "dot ABOVE price"),
                                  (close_val > psar_val ? "dot BELOW price" : "dot ABOVE price")));
         }

          m_ind_cache.cached_bias = bias;
          m_ind_cache.psar_flip_result = 0;
          return false;
      }

      if(m_settings.DebugFlow)
         DebugLog("[PSAR_FLIP_CHECK] STEP 1 PASSED: Dot on correct side");

      // 2. Check if a flip was recorded for this direction
      datetime flip_time = (bias > 0) ? m_psar_last_flip_time_bull : m_psar_last_flip_time_bear;

      // Display flip countdown status
      if(m_settings.DebugFlow) {
         if(flip_time == 0) {
            DebugLog(StringFormat("[PSAR_FLIP_CHECK] STEP 2: No %s flip recorded yet",
                                  (bias > 0 ? "BULLISH" : "BEARISH")));
         } else {
            int bars_elapsed   = GetBarsSinceLastFlip(bias, shift);
            int bars_remaining = effective_delay - bars_elapsed;
            bool is_valid      = (bars_elapsed <= effective_delay);

            DebugLog(StringFormat("[PSAR_FLIP_CHECK] STEP 2: Flip recorded at %s",
                                  TimeToString(flip_time, TIME_DATE|TIME_MINUTES)));
            DebugLog(StringFormat("[PSAR_FLIP_CHECK]    Flip age: %d bars | Delay limit: %d bars (L%d) | Remaining: %d bars",
                                  bars_elapsed,
                                  effective_delay,
                                  m_last_layer,
                                  bars_remaining));
            DebugLog(StringFormat("[PSAR_FLIP_CHECK]    Status: %s",
                                  is_valid ? "VALID (within delay window)" : "EXPIRED (too old)"));
         }
      }

      if(flip_time == 0) {
         m_diag_last_reason = StringFormat("PSAR_NO_FLIP_RECORDED (bias=%d)", bias);

         if(m_settings.DebugFlow) {
            DebugLog("[PSAR_FLIP_CHECK] STEP 2 FAILED: NO FLIP RECORDED");
            DebugLog(StringFormat("[PSAR_FLIP_CHECK]    No %s flip has been registered yet",
                                  (bias > 0 ? "bullish" : "bearish")));
            DebugLog(StringFormat("[PSAR_FLIP_CHECK]    m_psar_last_flip_time_%s = 0",
                                  (bias > 0 ? "bull" : "bear")));
         }

          m_ind_cache.cached_bias = bias;
          m_ind_cache.psar_flip_result = 0;
          return false;
      }

      if(m_settings.DebugFlow)
         DebugLog(StringFormat("[PSAR_FLIP_CHECK] STEP 2 PASSED: Flip recorded at %s",
                               TimeToString(flip_time, TIME_DATE|TIME_MINUTES)));

      // 3. Calculate bars since flip
      int flip_bar   = iBarShift(m_symbol, PERIOD_CURRENT, flip_time, false);
      int bars_since = (flip_bar >= 0) ? (flip_bar - shift) : INT_MAX;
      int delay      = effective_delay;  // P1: layer-aware delay

      if(m_settings.DebugFlow) {
         DebugLog("[PSAR_FLIP_CHECK] STEP 3: Calculate flip age");
         DebugLog(StringFormat("[PSAR_FLIP_CHECK]    Flip time: %s", TimeToString(flip_time, TIME_DATE|TIME_MINUTES)));
         DebugLog(StringFormat("[PSAR_FLIP_CHECK]    Flip bar index: %d", flip_bar));
         DebugLog(StringFormat("[PSAR_FLIP_CHECK]    Current shift: %d", shift));
         DebugLog(StringFormat("[PSAR_FLIP_CHECK]    Bars since flip: %d", bars_since));
         DebugLog(StringFormat("[PSAR_FLIP_CHECK]    Delay setting: %d bars", delay));
      }

      if(bars_since == INT_MAX) {
         m_diag_last_reason = "PSAR_FLIP_INVALID";

         if(m_settings.DebugFlow)
            DebugLog("[PSAR_FLIP_CHECK] STEP 3 FAILED: iBarShift returned invalid index");

          m_ind_cache.cached_bias = bias;
          m_ind_cache.psar_flip_result = 0;
          return false;
      }

      // 4. Check if flip is within delay window
      if(bars_since > delay) {
         m_diag_last_reason = StringFormat("PSAR_FLIP_EXPIRED (bars_since=%d, delay=%d)",
                                           bars_since, delay);

         if(m_settings.DebugFlow) {
            DebugLog("[PSAR_FLIP_CHECK] STEP 3 FAILED: FLIP EXPIRED");
            DebugLog(StringFormat("[PSAR_FLIP_CHECK]    %d bars elapsed > %d delay window",
                                  bars_since, delay));
         }

          m_ind_cache.cached_bias = bias;
          m_ind_cache.psar_flip_result = 0;
          return false;
      }

      // SUCCESS
      if(m_settings.DebugFlow) {
         DebugLog("[PSAR_FLIP_CHECK] STEP 3 PASSED: Flip within delay window");
         DebugLog("[PSAR_FLIP_CHECK] ===========================================");
         DebugLog("[PSAR_FLIP_CHECK] ALL CHECKS PASSED");
         DebugLog(StringFormat("[PSAR_FLIP_CHECK]    %s flip from %s is valid (%d bars ago, delay=%d)",
                               (bias > 0 ? "Bullish" : "Bearish"),
                               TimeToString(flip_time, TIME_DATE|TIME_MINUTES),
                               bars_since, delay));
      }

       m_ind_cache.cached_bias = bias;
       m_ind_cache.psar_flip_result = 1;
       return true;
   }

   //+------------------------------------------------------------------+
   // Check_RSI: RSI
   //+------------------------------------------------------------------+
   bool Check_RSI(int bias, int shift) {
      if(!m_settings.Ind_Rsi_Enabled) {
         if(m_settings.DebugFlow) DebugLog("[IND_RSI] DISABLED - skipped");
         return true;
      }
      if(IsCacheValidForShift(shift) &&
         m_ind_cache.rsi_result != -1 &&
         m_ind_cache.cached_bias == bias)
         return (m_ind_cache.rsi_result == 1);
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
      m_ind_cache.cached_bias = bias;
      m_ind_cache.rsi_value = r;
      m_ind_cache.rsi_result = result ? 1 : 0;
      if(m_settings.DebugFlow)
         DebugLog(StringFormat("[IND_RSI] ENABLED | Value=%.2f | Result: %s",
                               r, result ? "PASS" : "FAIL"));
      return result;
   }
     
   //+------------------------------------------------------------------+
   // Check_STO: Stochastic
   //+------------------------------------------------------------------+
   bool Check_Sto(int bias, int shift) {
      if(IsCacheValidForShift(shift) &&
         m_ind_cache.sto_result != -1 &&
         m_ind_cache.cached_bias == bias)
         return (m_ind_cache.sto_result == 1);

      double k = GetVal(h_sto, shift, 0);
      double d = GetVal(h_sto, shift, 1);
      bool result;
      
      if(m_settings.StoMode == STO_CROSS_SIGNAL) 
         result = (bias==1) ? (k > d) : (k < d);
      else
         // Zone Filter: Buy if NOT overbought
         result = (bias==1) ? (k < m_settings.T_StoOB) : (k > m_settings.T_StoOS);
      m_ind_cache.cached_bias = bias;
      m_ind_cache.sto_main = k;
      m_ind_cache.sto_signal = d;
      m_ind_cache.sto_result = result ? 1 : 0;

      if(m_settings.DebugFlow) {
         if(m_settings.Ind_Sto_Enabled)
            DebugLog(StringFormat("[IND_STOCH] ENABLED | K=%.2f D=%.2f | Result: %s",
                                  k, d, result ? "PASS" : "FAIL"));
         else
            DebugLog("[IND_STOCH] DISABLED - skipped");
      }
      return result;
   }
   
   
   //+------------------------------------------------------------------+
   // Check_P123: Pattern 1-2-3 (Breakout)
   //+------------------------------------------------------------------+
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
   
   //+------------------------------------------------------------------+
   // Check Ross Hook: Ross Hook (Trend-Following Momentum Interlock)
   //+------------------------------------------------------------------+
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

   //+------------------------------------------------------------------+
   // Check_VRC: Volatility Regime Classifier vote (non-directional)
   //+------------------------------------------------------------------+
   // Returns: true if volatility is acceptable, false if too low
   // Pattern: Same as Check_CI() – independent of trade direction
   bool Check_VRC(int bias, int shift)
   {
      if(IsCacheValidForShift(shift) && m_ind_cache.vrc_result != -1)
         return (m_ind_cache.vrc_result == 1);

      // ATR handle must be valid (h_atr created in Init())
      if(h_atr == INVALID_HANDLE) {
         if(m_settings.DebugFlow) DebugLog("VRC: ATR handle invalid");
         m_ind_cache.vrc_result = 0;
         return false;
      }

      // Get current volatility regime
      EVolatilityRegime regime = GetVolatilityRegime();

      // FAIL if volatility is too low (market too quiet, likely choppy/ranging)
      if(regime == VOLATILITY_LOW) {
         if(m_settings.DebugFlow) DebugLog("VRC: FAIL (volatility too low for reliable trend)");
         m_ind_cache.vrc_result = 0;
         return false;
      }

      // PASS if volatility is acceptable (NORMAL or HIGH)
      if(m_settings.DebugFlow) DebugLog("VRC: PASS (volatility acceptable)");
      m_ind_cache.vrc_result = 1;
      return true;
   }


   //+------------------------------------------------------------------+
   // Check_SmaConverge: SMA/EMA 10+20 Convergence (FPM Condition 4)
   // PASS when the gap between EMA1 and EMA2 is narrowing (converging).
   // Bias-neutral: same check for BUY and SELL entries.
   // Rationale: narrowing gap = price pulling back toward SMAs = setup.
   //+------------------------------------------------------------------+
   bool Check_SmaConverge(int shift)
   {
      if(IsCacheValidForShift(shift) && m_ind_cache.sma_converge_result != -1)
         return (m_ind_cache.sma_converge_result == 1);

      double e1_now  = GetMAVal(h_ema1, shift);
      double e2_now  = GetMAVal(h_ema2, shift);
      double e1_prev = GetMAVal(h_ema1, shift + 1);
      double e2_prev = GetMAVal(h_ema2, shift + 1);

      if(e1_now == 0.0 || e2_now == 0.0 || e1_prev == 0.0 || e2_prev == 0.0)
      {
         m_ind_cache.sma_converge_result = 0;
         return false;
      }

      double gap_now  = MathAbs(e1_now  - e2_now);
      double gap_prev = MathAbs(e1_prev - e2_prev);
      bool result = (gap_now < gap_prev);

      m_ind_cache.sma_converge_result = result ? 1 : 0;

      if(m_settings.DebugFlow)
      {
         if(m_settings.Ind_SmaConverge_Enabled)
            DebugLog(StringFormat("[IND_SMA_CONV] ENABLED | GapNow=%.5f | GapPrev=%.5f | Result: %s",
                                  gap_now, gap_prev, result ? "PASS (narrowing)" : "FAIL (widening)"));
         else
            DebugLog("[IND_SMA_CONV] DISABLED - skipped");
      }
      return result;
   }

   //+------------------------------------------------------------------+
   //| Check_Fib: Fibonacci Retracement Depth Voter                     |
   //| Confirms pullback depth is within 0.38–0.618 of last swing.      |
   //| K-score element from TopInvestor methodology (globally available).|
   //| Logic:                                                            |
   //|   1. Find highest high and lowest low in lookback window.         |
   //|   2. LONG:  ratio = (swing_high - close) / swing_range           |
   //|      SHORT: ratio = (close - swing_low) / swing_range            |
   //|   3. PASS if Fib_MinRetracement <= ratio <= Fib_MaxRetracement.  |
   //+------------------------------------------------------------------+
   bool Check_Fib(int bias, int shift)
   {
      if(!m_settings.Ind_Fib_Enabled) return true;

      int lookback = m_settings.Fib_SwingLookback;
      if(lookback < 10) lookback = 50;

      int start = shift + 1;
      int total = iBars(m_symbol, PERIOD_CURRENT);
      if(start + lookback >= total) return true;

      int hi_idx = iHighest(m_symbol, PERIOD_CURRENT, MODE_HIGH, lookback, start);
      int lo_idx = iLowest(m_symbol, PERIOD_CURRENT, MODE_LOW, lookback, start);

      if(hi_idx < 0 || lo_idx < 0) return true;

      double swing_high = iHigh(m_symbol, PERIOD_CURRENT, hi_idx);
      double swing_low  = iLow(m_symbol, PERIOD_CURRENT, lo_idx);
      double swing_range = swing_high - swing_low;

      if(swing_range <= 0.0) return false;

      double current_close = iClose(m_symbol, PERIOD_CURRENT, shift);
      double ratio = 0.0;

      if(bias == 1)
      {
         if(hi_idx >= lo_idx) return true;
         ratio = (swing_high - current_close) / swing_range;
      }
      else if(bias == -1)
      {
         if(lo_idx >= hi_idx) return true;
         ratio = (current_close - swing_low) / swing_range;
      }
      else return true;

      bool result = (ratio >= m_settings.Fib_MinRetracement &&
                     ratio <= m_settings.Fib_MaxRetracement);

      if(m_settings.DebugFlow)
      {
         if(m_settings.Ind_Fib_Enabled)
            DebugLog(StringFormat("[IND_FIB] SwingH=%.5f SwingL=%.5f | Ratio=%.3f (%.1f%%) | Range=[%.2f-%.2f] | %s",
                                  swing_high, swing_low, ratio, ratio * 100.0,
                                  m_settings.Fib_MinRetracement,
                                  m_settings.Fib_MaxRetracement,
                                  result ? "PASS" : "FAIL"));
      }

      return result;
   }

    //+------------------------------------------------------------------+
    //| Check_DPI: DPI v31 voter — MACD-core Blue/Red/hist architecture  |
    //| Blue(i) = EMA(Fast,close)(i) − EMA(Slow,close)(i)               |
    //| Red(i)  = EMA(RedSignalType, Blue)(i)  [or double-smooth]        |
    //| hist(i) = Blue(i) − Red(i)                                       |
    //| Vote: dir agrees with bias AND (if UseCCIReset) CCI confirms      |
    //|       AND (if UseGreenHist) Blue/hist aligned same side of zero   |
    //| No static locals, no lambdas — safe for MQL5 on macOS/Wine.      |
    //+------------------------------------------------------------------+
   bool Check_DPI(int bias, int v_shift)
   {
      if(!m_settings.Ind_Dpi_Enabled) return true;

      if(IsCacheValidForShift(v_shift) && m_ind_cache.cached_bias == bias && m_ind_cache.dpi_result != -1)
         return (m_ind_cache.dpi_result == 1);

      double hist_cur = 0.0, hist_prev = 0.0;
      bool   dpi_green = false, dpi_macd_agree = false;
      double _unused_green_cur = 0.0, _unused_green_prev = 0.0;
      if(!ComputeDPIMainHist(v_shift, hist_cur, hist_prev, dpi_green, dpi_macd_agree,
                             _unused_green_cur, _unused_green_prev))
      {
         // Insufficient bars — DPI passes silently (neither counted as pass nor fail).
         // In VOTE_MODE_ALL this ensures DPI does not block trades when warmup data is missing.
         m_ind_cache.cached_bias = bias;
         m_ind_cache.dpi_result  = 1;
         return true;
      }

      // Direction: sign of histogram
      int dir = (hist_cur > 0.0) ? 1 : ((hist_cur < 0.0) ? -1 : 0);

      bool dir_ok  = (dir == bias);
      // DPI_IgnoreCCIForVote: bypass CCI-reset check — vote on raw histogram direction only.
      // Useful when a valid pullback-recovery causes CCI to temporarily flip against the
      // histogram, causing the vote to fail despite correct momentum direction.
      bool cci_ok  = (m_settings.DPI_IgnoreCCIForVote || !m_settings.DPI_UseCCIReset || dpi_macd_agree);
      bool green_ok= (!m_settings.DPI_UseGreenHist  || dpi_green);

      bool result  = dir_ok && cci_ok && green_ok;

      m_ind_cache.cached_bias = bias;
      m_ind_cache.dpi_result  = result ? 1 : 0;

      if(m_settings.DebugFlow)
      {
         string sub = "";
         if(!dir_ok)   sub = sub + "DIR_MISMATCH ";
         if(!cci_ok)   sub = sub + "CCI_RESET ";
         if(!green_ok) sub = sub + "NO_GREEN ";
         DebugLog(StringFormat("[IND_DPI] bias=%d hist=%.6f dir=%d green=%d cciagreed=%d ignoreCCI=%s → %s%s",
                               bias, hist_cur, dir,
                               dpi_green ? 1 : 0, dpi_macd_agree ? 1 : 0,
                               m_settings.DPI_IgnoreCCIForVote ? "Y" : "N",
                               result ? "PASS" : "FAIL ",
                               result ? "" : ("(" + sub + ")")));
      }
      return result;
   }

   //+------------------------------------------------------------------+

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

   //+------------------------------------------------------------------+
   // Calculate slope direction from two adjacent points
   //+------------------------------------------------------------------+
   int CalculateSlope(double curr, double prev)
   {
      if(curr > prev) return 1;
      if(curr < prev) return -1;
      return 0;
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

   //==========================================================================
   // CheckLayerPairAlign — Structural alignment check (position + slope)
   // Returns 1 if the EMA pair is aligned with bias direction, 0 otherwise.
   //
   // layer_type: 1=LayerW (EMA1/EMA2), 2=LayerM (EMA2/EMA3), 3=LayerS (EMA3/EMA4)
   //
   // Position: fast EMA must be on the correct side of slow EMA.
   // Slope: BOTH EMAs must be moving in the bias direction.
   //   - During pullback: fast EMA slope flattens/reverses → returns 0 naturally.
   //   - On recovery: both slopes realign → returns 1 again.
   //   - No wick-touch or pip-tolerance arithmetic needed.
   //
   // SlopeLookbackBars: adaptive lookback from settings (default=1 for short TF,
   //   2 for H1+ swing). Higher values reduce noise sensitivity on lower timeframes.
   //==========================================================================
   int CheckLayerPairAlign(int bias, int layer_type)
   {
      int h_fast = INVALID_HANDLE, h_slow = INVALID_HANDLE;
      ELayerPullbackState current_state = LAYER_PB_NONE;
      string layer_label = "";
      switch(layer_type)
      {
         case 1: h_fast = h_ema1; h_slow = h_ema2; current_state = m_layer_w_pb_state; layer_label = "LayerW"; break;
         case 2: h_fast = h_ema2; h_slow = h_ema3; current_state = m_layer_m_pb_state; layer_label = "LayerM"; break;
         case 3: h_fast = h_ema3; h_slow = h_ema4; current_state = m_layer_s_pb_state; layer_label = "LayerS"; break;
         default: return 0;
      }

      double ema_fast      = GetMAVal(h_fast, 1);
      double ema_slow      = GetMAVal(h_slow, 1);
      // Warmup check: EMPTY_VALUE is normal during indicator initialization
      if(ema_fast == EMPTY_VALUE || ema_slow == EMPTY_VALUE) {
         if(m_settings.DebugFlow)
            PrintFormat("[LayerAlign] WARMUP: EMA data not ready (fast=%.5f slow=%.5f)",
                        ema_fast, ema_slow);
         return 0;  // Normal during warmup period
      }

      // Data integrity check: reject suspicious zero/negative values (actual errors)
      if((ema_fast == 0.0 && ema_slow == 0.0) || ema_fast < 0.0 || ema_slow < 0.0) {
         if(m_settings.DebugFlow)
            PrintFormat("[LayerAlign] ERROR: Invalid EMA data (fast=%.5f slow=%.5f)",
                        ema_fast, ema_slow);
         return 0;
      }

      // ── Position check: fast must be on the correct side of slow ──
      bool position_aligned = (bias == 1)  ? (ema_fast > ema_slow) :
                              (bias == -1) ? (ema_fast < ema_slow) : false;
      if(!position_aligned) return 0;

      // ── Slope check: use SlopeLookbackBars for timeframe-adaptive sensitivity ──
      int lookback = m_settings.SlopeLookbackBars;
      if(lookback < 1) lookback = 1;
      if(lookback > 5) lookback = 5;

      double ema_fast_prev = GetMAVal(h_fast, 1 + lookback);
      double ema_slow_prev = GetMAVal(h_slow, 1 + lookback);
      // Warmup check: EMPTY_VALUE is normal during indicator initialization
      if(ema_fast_prev == EMPTY_VALUE || ema_slow_prev == EMPTY_VALUE) {
         if(m_settings.DebugFlow)
            PrintFormat("[LayerAlign] WARMUP: Previous bar EMA data not ready");
         return 0;  // Normal during warmup period
      }

      // Data integrity check: reject suspicious zero/negative values (actual errors)
      if((ema_fast_prev == 0.0 && ema_slow_prev == 0.0) || ema_fast_prev < 0.0 || ema_slow_prev < 0.0) {
         if(m_settings.DebugFlow)
            PrintFormat("[LayerAlign] ERROR: Invalid previous bar EMA data (fast=%.5f slow=%.5f)",
                        ema_fast_prev, ema_slow_prev);
         return 0;
      }

      bool slope_fast_aligned, slope_slow_aligned;

      double slope_tol = m_settings.Layer_SlopeTolerance * GlobalPipSize(m_symbol);
      if(slope_tol > 0.0)
      {
         // Tolerance mode: slope is "aligned" when EMA didn't move MORE than slope_tol
         // in the wrong direction.  Allows flat / marginally-reversed slopes that occur
         // during early pullback-recovery (fast EMA still decelerating but not truly reversing).
         slope_fast_aligned = (bias ==  1) ? (ema_fast >= ema_fast_prev - slope_tol) :
                              (bias == -1) ? (ema_fast <= ema_fast_prev + slope_tol) : false;
         slope_slow_aligned = (bias ==  1) ? (ema_slow >= ema_slow_prev - slope_tol) :
                              (bias == -1) ? (ema_slow <= ema_slow_prev + slope_tol) : false;
      }
      else
      {
         // Strict mode (default): both EMAs must be strictly rising (LONG) or falling (SHORT).
         slope_fast_aligned = (bias ==  1) ? (ema_fast > ema_fast_prev) :
                              (bias == -1) ? (ema_fast < ema_fast_prev) : false;
         slope_slow_aligned = (bias ==  1) ? (ema_slow > ema_slow_prev) :
                              (bias == -1) ? (ema_slow < ema_slow_prev) : false;
      }

      int base_result = (slope_fast_aligned && slope_slow_aligned) ? 1 : 0;

      if(m_settings.LayerPullbackEnabled && base_result == 1)
      {
         // NONE and DETECTED stay blocked until a recovery has been observed.
         if(current_state != LAYER_PB_RECOVERED)
         {
            if(m_settings.DebugFlow)
               DebugLog(StringFormat("[%s] BLOCKED by pullback gate | State=%s (need RECOVERED)",
                                     layer_label, EnumToString(current_state)));
            return 0;
         }
      }

      if(m_settings.DebugFlow)
      {
         string pair_name = (layer_type == 1) ? "LayerW(EMA1/2)" :
                            (layer_type == 2) ? "LayerM(EMA2/3)" : "LayerS(EMA3/4)";
         double slope_tol_dbg = m_settings.Layer_SlopeTolerance * GlobalPipSize(m_symbol);
         PrintFormat("[LayerAlign] %s | bias=%d | fast=%.5f prev=%.5f (%s) | slow=%.5f prev=%.5f (%s) | pos=%s slope=%s tol=%.5f → %s",
                     pair_name, bias,
                     ema_fast, ema_fast_prev, slope_fast_aligned ? "OK" : "FAIL",
                     ema_slow, ema_slow_prev, slope_slow_aligned ? "OK" : "FAIL",
                     position_aligned ? "OK" : "FAIL",
                     (base_result == 1) ? "OK" : "FAIL",
                     slope_tol_dbg,
                     (base_result == 1) ? "PASS" : "REJECT");
      }

      return base_result;
   }

   //==========================================================================
   // Eval_BarClose — Wrapper: delegates to Check_BarClose() (handle-based access)
   // layer_id: LAYER_1_WEAK / LAYER_2_MEDIUM / LAYER_3_STRONG
   //==========================================================================
   int Eval_BarClose(int v_shift, int bias, int layer_id)
   {
      return Check_BarClose(v_shift, bias, layer_id);
   }

   bool Check_BarClose_MultiBar(int v_shift, int bias, int active_layer, int lookback)
   {
      int bars = MathMax(1, MathMin(4, lookback));
      for(int i = 0; i < bars; i++)
      {
         int bc = Eval_BarClose(v_shift + i, bias, active_layer);
         if(bc == 1) return true;
      }
      return false;
   }

   bool Check_Progressive_Momentum(int v_shift, int bias, int lookback)
   {
      int bars = MathMax(1, MathMin(4, lookback));
      if(bars <= 1 || bias == 0) return true;

      int improvements = 0;
      for(int i = 1; i < bars; i++)
      {
         double close_prev = iClose(m_symbol, PERIOD_CURRENT, v_shift + i);
         double close_curr = iClose(m_symbol, PERIOD_CURRENT, v_shift + i - 1);
         bool improved = (bias == 1) ? (close_curr > close_prev) : (close_curr < close_prev);
         if(improved) improvements++;
      }

      // Require a 2/3 directional-improvement majority across lookback transitions.
      int required = MathMax(1, (bars - 1) * 2 / 3);
      return (improvements >= required);
   }

   bool Check_DPI_Histogram_Growing(int v_shift, int bias, int lookback)
   {
      if(!m_settings.DPI_HistTrackingEnabled || bias == 0) return false;

      int bars = MathMax(1, MathMin(4, lookback));
      if(bars <= 1) return false;

      double hist_values[4];
      for(int i = 0; i < bars; i++)
         // Convert shift-based newest-first access into oldest→newest array order.
         hist_values[i] = ComputeDPI_CCI(v_shift + (bars - 1 - i));

      bool all_same_sign = true;
      bool growing = true;
      for(int i = 0; i < bars; i++)
      {
         if((bias == 1 && hist_values[i] <= 0.0) || (bias == -1 && hist_values[i] >= 0.0))
            all_same_sign = false;
         if(i > 0)
         {
            double older_abs = MathAbs(hist_values[i - 1]);
            double newer_abs = MathAbs(hist_values[i]);
            if(newer_abs <= older_abs)
               growing = false;
         }
      }

      return (all_same_sign && growing);
   }

public:
   // Public Accessors for the UI/Cockpit
   string            GetTSStatusString() const { return m_ts_status_str; }
   string            GetTEStatusString() const { return m_te_status_str; }
   void              SetTEStatusString(string status)  { m_te_status_str = status; }
   
   ST_SignalTelemetry GetTelemetry() const { return m_telemetry; }

   void GetMTFCockpitData(SMTFSegment &segments[])
   {
      ArrayResize(segments, 0);

      if(!m_settings.Ind_MTF_Enabled)
      {
         ArrayResize(segments, 1);
         segments[0].text = "MTF: [DISABLED]";
         segments[0].clr  = m_settings.clr_Disabled;
         return;
      }

      int base_bias = m_diag_last_bias;
      int tf1_bias  = GetMTFBias(h_mtf_tf1_fast, h_mtf_tf1_slow);
      int tf2_bias  = 0;

      bool single_tf_mode = (h_mtf_tf2_fast == INVALID_HANDLE ||
                             m_settings.MTF_TF2 == PERIOD_CURRENT ||
                             m_settings.MTF_TF2 == m_settings.MTF_TF1);

      if(!single_tf_mode)
         tf2_bias = GetMTFBias(h_mtf_tf2_fast, h_mtf_tf2_slow);

      int idx = 0;
      string up = ShortToString(0x25B2);   // ▲
      string dn = ShortToString(0x25BC);   // ▼

      // Segment 0: header label
      ArrayResize(segments, idx + 1);
      segments[idx].text = "MTF: ";
      segments[idx].clr  = m_settings.clr_Header;
      idx++;

      // Build one combined string: "M1▲ | H1▲" or "M1▲ | H1▼ | H4▲"
      // Color = overall alignment result (green if all agree, red if conflict)
      string base_label = GetCompactTFLabel((ENUM_TIMEFRAMES)_Period);
      string base_sym   = (base_bias == 1) ? up : (base_bias == -1) ? dn : "-";

      string tf1_label  = GetCompactTFLabel(m_settings.MTF_TF1);
      string tf1_sym    = (tf1_bias == 1) ? up : (tf1_bias == -1) ? dn : "-";

      string combined = base_label + base_sym + " | " + tf1_label + tf1_sym;

      if(!single_tf_mode)
      {
         string tf2_label = GetCompactTFLabel(m_settings.MTF_TF2);
         string tf2_sym   = (tf2_bias == 1) ? up : (tf2_bias == -1) ? dn : "-";
         combined += " | " + tf2_label + tf2_sym;
      }

      // Overall color: green if HTF agrees with current TF, red if conflict, gray if unclear
      bool all_aligned = (base_bias != 0 && tf1_bias == base_bias);
      if(!single_tf_mode && tf2_bias != base_bias) all_aligned = false;
      color overall_clr = (base_bias == 0) ? m_settings.clr_Disabled
                        : all_aligned ? m_settings.clr_Pass
                        : m_settings.clr_Fail;

      ArrayResize(segments, idx + 1);
      segments[idx].text = combined;
      segments[idx].clr  = overall_clr;
      idx++;
   }
   

   // --- UNIVERSAL CLASS METHOD: UpdateTelemetry (Verified Fix) ---
   void UpdateTelemetry(int bias)
   {
      // 1. Core Diagnostic Sync
      m_telemetry.bias             = bias;
      m_telemetry.votes_for        = m_diag_last_votes;
      m_telemetry.votes_total      = GetEnabledIndicatorCount(m_settings);

      // 2. Map BIAS to Symbol
      string bias_sym = (bias > 0) ? "(+)" : (bias < 0 ? "(-)" : "(.)");

      // 3. Dynamic Status (Replaces 'SIGNAL FLAT')
      // This identifies EXACTLY which of the 9 steps failed
      string status_msg = "ELIGIBLE"; 
      if(bias == 0 && m_diag_last_reason == "") status_msg = "WAITING";
      else if(m_diag_last_reason != "")         status_msg = m_diag_last_reason;

      // 4. Dynamic Indicator Row (All 5+ Indicators)
      SVoteSnapshot snaps[]; 
      int count = 0;
      CaptureVoteSnapshots(snaps, count, bias);

      string ind_row = "";
      for(int i = 0; i < count; i++) 
      {
         string icon = "(.)";
         if(snaps[i].state == "BUY")  icon = "(+)";
         if(snaps[i].state == "SELL") icon = "(-)";
         ind_row += snaps[i].name + icon + (i < count - 1 ? " " : "");
      }

      // 5. Build Final Output String
      // Logic: If we aren't using 4-EMA Phase logic, don't show "UNORDERED"
      bool show_phase = (m_settings.BiasMode == BIAS_4EMA);
      
      string final_ui = StringFormat("BIAS%s | %s\n%s", 
                                     bias_sym, 
                                     status_msg, 
                                     ind_row);

      m_telemetry.active_indicators = final_ui;
      m_telemetry.diag_layer_w = m_diag_layer_w;
      m_telemetry.diag_layer_m = m_diag_layer_m;
      m_telemetry.diag_layer_s = m_diag_layer_s;
      m_telemetry.phase_detection_enabled = (m_settings.BiasMode == BIAS_4EMA && m_settings.PhaseDetectionEnabled);
      m_telemetry.layer_detection_enabled = (m_settings.EnableLayerDetection && m_settings.BiasMode == BIAS_4EMA);
      if(!m_settings.Ind_MTF_Enabled)
         m_telemetry.mtf_status = "N/A";
   }


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
   int GetMtfTf1FastHandle() const { return h_mtf_tf1_fast; }
   int GetMtfTf1SlowHandle() const { return h_mtf_tf1_slow; }
   int GetMtfTf2FastHandle() const { return h_mtf_tf2_fast; }
   int GetMtfTf2SlowHandle() const { return h_mtf_tf2_slow; }
   int GetFractalHandle() const { return h_fractals; } // ADD THIS
   
   // Pattern indicators (return INVALID_HANDLE if not implemented yet)
   int GetP123Handle() const { return INVALID_HANDLE; } // TODO: Implement when P123 indicator ready
   int GetRossHandle() const { return INVALID_HANDLE; } // TODO: Implement when Ross Hook ready

   // Atr Ci Vrc Handle Getters for UI ---
   int GetAtrHandle() const { return h_atr; }
   int GetCiHandle()  const { return h_ci; }
   int GetVrcHandle() const { return h_vrc; }

   CSignalEngine() : m_symbol(""), m_news_count(0), m_last_news_block_log(0)
   {
      // Defensive init of indicator handles (prevents stale handles across re-inits)
      h_ema1 = h_ema2 = h_ema3 = h_ema4 = INVALID_HANDLE;
      h_macd = h_rsi = h_cci = h_sto = INVALID_HANDLE;
      h_atr = h_bb = h_psar = h_fractals = INVALID_HANDLE;
      h_adx = h_mfi = INVALID_HANDLE;
      h_mtf_tf1_fast = h_mtf_tf1_slow = INVALID_HANDLE;
      h_mtf_tf2_fast = h_mtf_tf2_slow = INVALID_HANDLE;
      h_ci  = INVALID_HANDLE;
      h_vrc = INVALID_HANDLE;

      m_diag_last_bias   = 0;
      m_diag_last_votes  = 0;
      m_diag_last_reason = "";
      m_diag_last_atr_pips = 0.0;

      // Initialize phase diagnostics
      m_diag_last_phase = PHASE_UNORDERED;
      m_diag_phase_confirm_bars = 0;

      m_diag_layer_w      = 0;
      m_diag_layer_m      = 0;
      m_diag_layer_s      = 0;
      m_last_layer        = 0;

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

      // Initialize DEBUG_SIGNALS_ONLY buffer
      m_debug_buffer_size = 0;
      ArrayResize(m_debug_buffer, 0);
      m_forced_debug_active = false;
      m_saved_debug_level   = DEBUG_SILENT;
      m_saved_debug_flow    = false;

      // Initialize indicator cache state
      m_ind_cache.cached_shift = -1;
      m_ind_cache.cached_bar_time = 0;
      m_ind_cache.cached_bias  = 0;
      m_ind_cache.adx_result = -1;
      m_ind_cache.macd_result = -1;
      m_ind_cache.rsi_result = -1;
      m_ind_cache.cci_result = -1;
      m_ind_cache.mfi_result = -1;
      m_ind_cache.sto_result = -1;
      m_ind_cache.bb_result = -1;
      m_ind_cache.psar_result = -1;
      m_ind_cache.psar_flip_result = -1;
      m_ind_cache.atr_result = -1;
      m_ind_cache.candlebody_result = -1;
      m_ind_cache.ci_result = -1;
      m_ind_cache.vrc_result = -1;

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

   // --- TE Gate: Read-only news check for EvaluateTE() (shift=0) ---
   // Returns true if a high-impact news event is currently active for this symbol.
   // No stat updates — pure read-only check.
   bool IsNewsBlocked()
   {
      if(!m_settings.UseNews || m_news_count == 0) return false;
      string base, quote;
      GetSymbolCurrencies(m_symbol, base, quote);
      if(base == "" || quote == "") return false;
      datetime now     = TimeCurrent();
      int      pre_sec = m_settings.NewsPre  * 60;
      int      post_sec= m_settings.NewsPost * 60;
      for(int i = 0; i < m_news_count; i++)
      {
         string ccy = m_news_events[i].currency;
         if(ccy != base && ccy != quote) continue;
         if(!NewsImpactPass(m_news_events[i].impact)) continue;
         datetime t = m_news_events[i].time;
         if(now >= (t - pre_sec) && now <= (t + post_sec)) return true;
      }
      return false;
   }

   // 260304_PR1: Phase Detection Diagnostics
   EMarketPhase GetLastDetectedPhase() const { return m_diag_last_phase; }
   int          GetPhaseConfirmBars() const { return m_diag_phase_confirm_bars; }

   //+------------------------------------------------------------------+
   //| DPI Histogram Diagnostic Getters                                 |
   //+------------------------------------------------------------------+
   double GetDPIHistCurrent()      const { return m_dpi_hist_current; }
   int    GetDPIHistTrend()        const { return m_dpi_hist_trend; }
   bool   GetDPIHistDecelerating() const { return m_dpi_hist_decelerating; }
   bool   GetDPIHistGreenPresent() const { return m_dpi_hist_green_present; }
   int    GetDPIHistBufferSize()   const { return m_dpi_hist_buffer_size; }

   //+------------------------------------------------------------------+
   //| Layer Pullback-Recovery Diagnostic Getters                       |
   //+------------------------------------------------------------------+
   ELayerPullbackState GetLayerWPullbackState() const { return m_layer_w_pb_state; }
   ELayerPullbackState GetLayerMPullbackState() const { return m_layer_m_pb_state; }
   ELayerPullbackState GetLayerSPullbackState() const { return m_layer_s_pb_state; }
   double              GetLayerWBaseline()      const { return m_layer_w_baseline; }
   double              GetLayerMBaseline()      const { return m_layer_m_baseline; }
   double              GetLayerSBaseline()      const { return m_layer_s_baseline; }

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

   // KISS layer diagnostic getters
   int    DiagLayerW()        const { return m_diag_layer_w; }
   int    DiagLayerM()        const { return m_diag_layer_m; }
   int    DiagLayerS()        const { return m_diag_layer_s; }

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

   // ── PHASE A.1: aggregate TE-side counters into m_stats before reporting ─
   // Called from SimpleEA OnDeinit() to bridge counters maintained on
   // CTradeExecutor into the engine's m_stats so PrintEnhancedStatistics
   // can include them in the per-gate breakdown.
   void AddTeStats(int rej_open_delay, int rej_bc_recheck, int rej_spread_median,
                   int pass_open_delay, int pass_bc_recheck, int pass_spread_median)
   {
      m_stats.rejected_te_open_delay     += rej_open_delay;
      m_stats.rejected_te_bc_recheck     += rej_bc_recheck;
      m_stats.rejected_te_spread_median  += rej_spread_median;
      m_stats.passed_te_open_delay       += pass_open_delay;
      m_stats.passed_te_bc_recheck       += pass_bc_recheck;
      m_stats.passed_te_spread_median    += pass_spread_median;
   }

   // Bridge DPI histogram exit counter from CTradeExecutor into session stats.
   void AddDPIExitStats(int exits_dpi_hist)
   {
      m_stats.exits_dpi_hist += exits_dpi_hist;
   }

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

      // KISS Layer status (always shown)
      diag += StringFormat("LayerW=%d LayerM=%d LayerS=%d\n",
                           m_diag_layer_w, m_diag_layer_m, m_diag_layer_s);

      // Rejection statistics for this session
      diag += StringFormat("Stats: eval=%d sig=%d rejF=%d rejB=%d rejG=%d rejV=%d",
                           m_bars_evaluated, m_signals_generated,
                           m_reject_filter, m_reject_bias, m_reject_gate, m_reject_votes);
      return diag;
   }

   // This goes inside CSignalEngine or as a global utility
   int CalcVoteResult(const int bias, const string state)
   {
      // 1. Scrub the data
      if(state == "" || state == "NONE" || state == "WAIT") return 0;
   
      // 2. Logic for the UI (The 1/5, 4/5 result)
      // We count the vote if it is ACTIVE, regardless of Bias direction.
      // This ensures that if the Icon is Green, the counter goes UP.
      if(state == "BUY" || state == "SELL" || state == "OK" || state == "PASS") 
      {
         return 1; 
      }
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
      SReason reasons[34];   // PHASE A.1: was [27], +7 for new gates
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

      reasons[idx].name = "ATR";
      reasons[idx].count = m_stats.rejected_atr;
      reasons[idx++].pct = m_stats.rejected_atr * 100.0 / m_stats.total_bars;

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

      reasons[idx].name = "SmaConverge";
      reasons[idx].count = m_stats.rejected_sma_converge;
      reasons[idx++].pct = m_stats.rejected_sma_converge * 100.0 / m_stats.total_bars;

      reasons[idx].name = "DPI";
      reasons[idx].count = m_stats.rejected_dpi;
      reasons[idx++].pct = m_stats.rejected_dpi * 100.0 / m_stats.total_bars;

      // ── PHASE A.1: new pre-filter gates ───────────────────────────────
      reasons[idx].name = "EMA Overext";
      reasons[idx].count = m_stats.rejected_emafan;
      reasons[idx++].pct = m_stats.rejected_emafan * 100.0 / m_stats.total_bars;

      reasons[idx].name = "DPI Decel";
      reasons[idx].count = m_stats.rejected_dpi_decel;
      reasons[idx++].pct = m_stats.rejected_dpi_decel * 100.0 / m_stats.total_bars;

      reasons[idx].name = "Phase Age";
      reasons[idx].count = m_stats.rejected_phase_age;
      reasons[idx++].pct = m_stats.rejected_phase_age * 100.0 / m_stats.total_bars;

      reasons[idx].name = "MTF Conflict";
      reasons[idx].count = m_stats.rejected_mtf;
      reasons[idx++].pct = m_stats.rejected_mtf * 100.0 / m_stats.total_bars;

      reasons[idx].name = "TE Open Delay";
      reasons[idx].count = m_stats.rejected_te_open_delay;
      reasons[idx++].pct = m_stats.rejected_te_open_delay * 100.0 / m_stats.total_bars;

      reasons[idx].name = "TE BC Stale";
      reasons[idx].count = m_stats.rejected_te_bc_recheck;
      reasons[idx++].pct = m_stats.rejected_te_bc_recheck * 100.0 / m_stats.total_bars;

      reasons[idx].name = "TE Spread Median";
      reasons[idx].count = m_stats.rejected_te_spread_median;
      reasons[idx++].pct = m_stats.rejected_te_spread_median * 100.0 / m_stats.total_bars;

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
      PrintFormat("  Signals Confirmed : %d (%.2f%%)  [LONG=%d  SHORT=%d]",
                  m_stats.signals_confirmed, m_stats.signals_confirmed * 100.0 / m_stats.total_bars,
                  m_stats.signals_confirmed_long, m_stats.signals_confirmed_short);
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
      Print("1b. PRE-FILTER QUALITY GATES (Phase A.1 — TS=1 hardening)");
      Print("================================================================");
      PrintFormat("%-18s %-8s %7s %7s %7s   %s", "Gate", "Status", "Passed", "Failed", "Pass%", "Impact");
      Print("----------------------------------------------------------------");
      PrintGateStat("EMA Fan",
                    m_settings.EmaFanFilterEnabled,
                    m_stats.passed_emafan,
                    m_stats.rejected_emafan,
                    m_settings.EmaFanFilterEnabled
                       ? StringFormat("%.1f pips max", m_settings.EmaFanMaxTotalPips)
                       : "(disabled)");
      PrintGateStat("DPI Decel",
                    (m_settings.DpiDecelFilterEnabled && m_settings.Ind_Dpi_Enabled),
                    m_stats.passed_dpi_decel,
                    m_stats.rejected_dpi_decel,
                    (m_settings.DpiDecelFilterEnabled && m_settings.Ind_Dpi_Enabled)
                       ? "histogram shrinking"
                       : (!m_settings.Ind_Dpi_Enabled ? "(DPI off)" : "(disabled)"));
      PrintGateStat("DPI Blk Decel",
                    (m_settings.DPI_BlockOnDeceleration && m_settings.DPI_HistTrackingEnabled),
                    m_stats.passed_dpi_decel,
                    m_stats.rejected_dpi_decel,
                    (m_settings.DPI_BlockOnDeceleration && m_settings.DPI_HistTrackingEnabled)
                       ? "momentum decelerating"
                       : "(disabled)");
      PrintGateStat("Phase Age",
                    (m_settings.MinPhaseConfirmBars > 0),
                    m_stats.passed_phase_age,
                    m_stats.rejected_phase_age,
                    (m_settings.MinPhaseConfirmBars > 0)
                       ? StringFormat(">=%d bars", m_settings.MinPhaseConfirmBars)
                       : "(disabled)");
       PrintGateStat("TE Open Delay",
                    (m_settings.TE_OpenDelaySeconds > 0),
                    m_stats.passed_te_open_delay,
                    m_stats.rejected_te_open_delay,
                    (m_settings.TE_OpenDelaySeconds > 0)
                       ? StringFormat("%d sec defer", m_settings.TE_OpenDelaySeconds)
                       : "(disabled)");
      PrintGateStat("TE BC Recheck",
                    m_settings.TE_RecheckBarClose,
                    m_stats.passed_te_bc_recheck,
                    m_stats.rejected_te_bc_recheck,
                    m_settings.TE_RecheckBarClose ? "shift=1 BC vs live" : "(disabled)");
      PrintGateStat("TE Spread Med",
                    (m_settings.TE_SpreadMedianTicks > 0),
                    m_stats.passed_te_spread_median,
                    m_stats.rejected_te_spread_median,
                    (m_settings.TE_SpreadMedianTicks > 0)
                       ? StringFormat("median over %d ticks", m_settings.TE_SpreadMedianTicks)
                       : "(disabled)");
      Print("----------------------------------------------------------------");
      PrintFormat("Pre-filter blocks: %d bars (TS), %d (TE), %d exits (DPI Hist)",
                  m_stats.rejected_emafan + m_stats.rejected_dpi_decel +
                  m_stats.rejected_phase_age,
                  m_stats.rejected_te_open_delay + m_stats.rejected_te_bc_recheck +
                  m_stats.rejected_te_spread_median,
                  m_stats.exits_dpi_hist);
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
      PrintFormat("Bias direction: LONG=%d  SHORT=%d  (of %d passed)",
                  m_stats.passed_bias_long, m_stats.passed_bias_short, m_stats.passed_bias);
      Print("");
      Print("================================================================");
      Print("3. DIRECTIONAL INDICATORS (Must agree with detected bias)");
      Print("================================================================");
      PrintFormat("%-14s %-8s %7s %7s %7s   %-12s %s", "Indicator", "Status", "Passed", "Failed", "Pass%", "Agreement", "Impact");
      Print("----------------------------------------------------------------");
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
      PrintIndicatorStat("SmaConverge",  m_settings.Ind_SmaConverge_Enabled, m_stats.passed_sma_converge, m_stats.rejected_sma_converge);
      PrintIndicatorStat("ATR",          m_settings.Ind_Atr_Enabled, m_stats.passed_atr, m_stats.rejected_atr);
      PrintIndicatorStat("DPI",          m_settings.Ind_Dpi_Enabled, m_stats.passed_dpi,          m_stats.rejected_dpi);
      PrintIndicatorStat("Fib",          m_settings.Ind_Fib_Enabled, m_stats.passed_fib,          m_stats.rejected_fib);
      PrintIndicatorStat("MTF",          m_settings.Ind_MTF_Enabled, m_stats.passed_mtf,          m_stats.rejected_mtf);
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
      SBottleneck bn[27]; // Gates(3) + Bias/Phase/Layer(4) + Indicators(16 incl. DPI) = up to 27 entries
      int idx = 0;
      if(m_stats.rejected_spread > 0)         { bn[idx].name="Spread";         bn[idx].rejected=m_stats.rejected_spread;        bn[idx++].pct=m_stats.rejected_spread*100.0/m_stats.total_bars; }
      if(m_stats.rejected_time > 0)           { bn[idx].name="Time Window";    bn[idx].rejected=m_stats.rejected_time;          bn[idx++].pct=m_stats.rejected_time*100.0/m_stats.total_bars; }
      if(m_stats.rejected_news > 0)           { bn[idx].name="News Filter";    bn[idx].rejected=m_stats.rejected_news;          bn[idx++].pct=m_stats.rejected_news*100.0/m_stats.total_bars; }
      if(m_stats.rejected_bias > 0)           { bn[idx].name="Bias=0";         bn[idx].rejected=m_stats.rejected_bias;          bn[idx++].pct=m_stats.rejected_bias*100.0/m_stats.total_bars; }
      if(m_stats.rejected_phase > 0)          { bn[idx].name="Phase=UNORD";    bn[idx].rejected=m_stats.rejected_phase;         bn[idx++].pct=m_stats.rejected_phase*100.0/m_stats.total_bars; }
      if(m_stats.rejected_layer_none > 0)     { bn[idx].name="Layer=NONE";     bn[idx].rejected=m_stats.rejected_layer_none;    bn[idx++].pct=m_stats.rejected_layer_none*100.0/m_stats.total_bars; }
      if(m_stats.rejected_layer_blocked > 0)  { bn[idx].name="Layer blocked";  bn[idx].rejected=m_stats.rejected_layer_blocked; bn[idx++].pct=m_stats.rejected_layer_blocked*100.0/m_stats.total_bars; }
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
      if(m_settings.Ind_Atr_Enabled    && m_stats.rejected_atr    > 0) { bn[idx].name="ATR";           bn[idx].rejected=m_stats.rejected_atr; bn[idx++].pct=m_stats.rejected_atr*100.0/m_stats.total_bars; }
      if(m_settings.Ind_SmaConverge_Enabled && m_stats.rejected_sma_converge > 0) { bn[idx].name="SmaConverge"; bn[idx].rejected=m_stats.rejected_sma_converge; bn[idx++].pct=m_stats.rejected_sma_converge*100.0/m_stats.total_bars; }
      if(m_settings.Ind_Dpi_Enabled         && m_stats.rejected_dpi         > 0) { bn[idx].name="DPI";         bn[idx].rejected=m_stats.rejected_dpi;         bn[idx++].pct=m_stats.rejected_dpi*100.0/m_stats.total_bars; }
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
      if(m_settings.Ind_SmaConverge_Enabled && m_stats.rejected_sma_converge > worst_cnt) { worst_cnt=m_stats.rejected_sma_converge; worst_ind="SmaConverge"; }
      if(m_settings.Ind_Atr_Enabled        && m_stats.rejected_atr        > worst_cnt) { worst_cnt=m_stats.rejected_atr;        worst_ind="ATR"; }
      if(m_settings.Ind_Dpi_Enabled        && m_stats.rejected_dpi        > worst_cnt) { worst_cnt=m_stats.rejected_dpi;        worst_ind="DPI"; }
      if(m_settings.Ind_MTF_Enabled        && m_stats.rejected_mtf        > worst_cnt) { worst_cnt=m_stats.rejected_mtf;        worst_ind="MTF"; }
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
      ArrayResize(out, 17); // 16 possible indicators + 1 spare
      
      // We use the EXACT same shift used for the numerical calculation
      int v_shift = m_settings.Vote_EvalShift;

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
         bool pass = CheckCandleBodyIndicator(current_bias);
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

      // SmaConverge (SMA convergence – direction-neutral vote)
      if(m_settings.Ind_SmaConverge_Enabled && h_ema1 != INVALID_HANDLE && h_ema2 != INVALID_HANDLE)
      {
         bool pass = Check_SmaConverge(v_shift);
         out[count].name    = "SmaConv";
         out[count].enabled = true;
         if(pass) { out[count].state = (current_bias == 1 ? "BUY" : (current_bias == -1 ? "SELL" : "FLAT")); out[count].reason = "(SMA gap converging)"; }
         else     { out[count].state = "FLAT"; out[count].reason = "(SMA gap diverging)"; }
         out[count].vote_result = pass ? 1 : -1;
         count++;
      }

      // DPI (inline MACD momentum voter – directional vote)
      if(m_settings.Ind_Dpi_Enabled)
      {
         bool b = Check_DPI( 1, v_shift);
         bool s = Check_DPI(-1, v_shift);
         out[count].name    = "DPI";
         out[count].enabled = true;
         if(b && !s)      { out[count].state = "BUY";  out[count].reason = StringFormat("(F=%d S=%d RedT=%d BUY)", m_settings.DPI_MACD_Fast, m_settings.DPI_MACD_Slow, m_settings.DPI_RedSignalType); }
         else if(s && !b) { out[count].state = "SELL"; out[count].reason = StringFormat("(F=%d S=%d RedT=%d SELL)", m_settings.DPI_MACD_Fast, m_settings.DPI_MACD_Slow, m_settings.DPI_RedSignalType); }
         else             { out[count].state = "FLAT"; out[count].reason = "(no momentum or conditions not met)"; }
         out[count].vote_result = CalcVoteResult(current_bias, out[count].state);
         count++;
      }
      ArrayResize(out, count);
   }


   bool Init(ST_Settings &sets, string symbol) {
      m_settings = sets;
      m_symbol   = symbol;
      m_debug_buffer_size = 0;
      ArrayResize(m_debug_buffer, 0);
      m_ind_cache.cached_shift = -1;
      m_ind_cache.cached_bar_time = 0;
      m_ind_cache.cached_bias  = 0;

      // Initialize ADX history tracking from settings
      m_adxHistoryMaxSize  = (m_settings.ADX_Lookback > 0 ? m_settings.ADX_Lookback : 100);
      ArrayResize(m_adxHistory, 0);
      m_adxHistorySize     = 0;
      m_cachedADXThreshold = (double)m_settings.T_Adx;
      m_lastADXCalculation = 0;

      // Initialize DPI histogram tracking
      ArrayInitialize(m_dpi_hist_values, 0.0);
      m_dpi_hist_buffer_size = 0;
      m_dpi_hist_current = 0.0;
      m_dpi_hist_trend = 0;
      m_dpi_hist_decelerating = false;
      m_dpi_hist_green_present = false;
      m_dpi_hist_last_update = 0;
      m_layer_w_pb_state = LAYER_PB_NONE;
      m_layer_m_pb_state = LAYER_PB_NONE;
      m_layer_s_pb_state = LAYER_PB_NONE;
      m_layer_w_baseline = 0.0;
      m_layer_m_baseline = 0.0;
      m_layer_s_baseline = 0.0;
      m_layer_pb_last_update = 0;
      m_diag_last_bias = 0;
      m_diag_last_votes = 0;
      m_diag_last_reason = "";
      m_diag_last_atr_pips = 0.0;
      m_ts_status_string = "B[0] | I[0/0] | F[OK]";
      m_ts_status_str = "";
      m_te_status_str = "";
      m_diag_last_phase = PHASE_UNORDERED;
      m_diag_phase_confirm_bars = 0;
      m_diag_layer_w = 0;
      m_diag_layer_m = 0;
      m_diag_layer_s = 0;
      m_last_layer = 0;
      m_bars_evaluated = 0;
      m_signals_generated = 0;
      m_reject_filter = 0;
      m_reject_bias = 0;
      m_reject_gate = 0;
      m_reject_votes = 0;
      m_telemetry.bias = 0;
      m_telemetry.phase = (int)PHASE_UNORDERED;
      m_telemetry.layer = 0;
      m_telemetry.votes_for = 0;
      m_telemetry.votes_total = GetEnabledIndicatorCount(m_settings);
      m_telemetry.rejection_reason = SEA_STATUS_EVALUATING;
      m_telemetry.active_indicators = "0/0";
      m_telemetry.diag_layer_w = 0;
      m_telemetry.diag_layer_m = 0;
      m_telemetry.diag_layer_s = 0;
      m_telemetry.phase_detection_enabled = (m_settings.BiasMode == BIAS_4EMA && m_settings.PhaseDetectionEnabled);
      m_telemetry.layer_detection_enabled = (m_settings.EnableLayerDetection && m_settings.BiasMode == BIAS_4EMA);
      m_telemetry.mtf_status = "N/A";
      ZeroMemory(m_stats);

      ENUM_MA_METHOD method = (m_settings.MaType == METHOD_SMA) ? MODE_SMA : MODE_EMA;
      int h_shift = m_settings.ma_h_shift;
      
      // A. Create Standard Indicators (Using Dynamic Method and Horizontal Shift)
      h_ema1 = iMA(m_symbol, PERIOD_CURRENT, m_settings.P_Ema1, h_shift, method, PRICE_CLOSE);
      h_ema2 = iMA(m_symbol, PERIOD_CURRENT, m_settings.P_Ema2, h_shift, method, PRICE_CLOSE);
      h_ema3 = iMA(m_symbol, PERIOD_CURRENT, m_settings.P_Ema3, h_shift, method, PRICE_CLOSE);
      h_ema4 = iMA(m_symbol, PERIOD_CURRENT, m_settings.P_Ema4, h_shift, method, PRICE_CLOSE);

      // --- NEW: ATR, CI, and VRC Indicator Initialization ---
      bool need_atr = m_settings.Ind_Atr_Enabled;
      h_atr = (need_atr ? iATR(m_symbol, PERIOD_CURRENT, m_settings.P_Atr) : INVALID_HANDLE);
      
      h_ci  = (m_settings.Ind_CI_Enabled ? iCustom(m_symbol, PERIOD_CURRENT, "ChoppinessIndex", m_settings.CI_Period) : INVALID_HANDLE);
      h_vrc = (m_settings.Ind_VRC_Enabled ? iCustom(m_symbol, PERIOD_CURRENT, "VRC_Indicator") : INVALID_HANDLE);
      // ------------------------------------------------------

      // Optional indicators: create only when used
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
      
      // B. Create MTF confirmation handles (if enabled)
      if(m_settings.Ind_MTF_Enabled) {
         h_mtf_tf1_fast = iMA(m_symbol, m_settings.MTF_TF1, m_settings.MTF_EMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
         h_mtf_tf1_slow = iMA(m_symbol, m_settings.MTF_TF1, m_settings.MTF_EMA_Slow, 0, MODE_EMA, PRICE_CLOSE);

         if(m_settings.MTF_TF2 != PERIOD_CURRENT && m_settings.MTF_TF2 != m_settings.MTF_TF1)
         {
            h_mtf_tf2_fast = iMA(m_symbol, m_settings.MTF_TF2, m_settings.MTF_EMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
            h_mtf_tf2_slow = iMA(m_symbol, m_settings.MTF_TF2, m_settings.MTF_EMA_Slow, 0, MODE_EMA, PRICE_CLOSE);
         }
      }
      
      // C. Validation Checkpoints
      if(h_ema1 == INVALID_HANDLE) {
         Print("CRITICAL ERROR: Failed to create essential indicators (EMA).");
         return false;
      }
      if(need_atr && h_atr == INVALID_HANDLE) {
         Print("CRITICAL ERROR: Failed to create ATR indicator (used for voting).");
         return false;
      }
      if(m_settings.Ind_CI_Enabled && h_ci == INVALID_HANDLE) {
         Print("CRITICAL ERROR: Failed to create Choppiness Index (CI) indicator.");
         return false;
      }
      if(m_settings.Ind_VRC_Enabled && h_vrc == INVALID_HANDLE) {
         Print("CRITICAL ERROR: Failed to create VRC indicator.");
         return false;
      }
      if(m_settings.Ind_MTF_Enabled && (h_mtf_tf1_fast == INVALID_HANDLE || h_mtf_tf1_slow == INVALID_HANDLE)) {
         Print("CRITICAL ERROR: Failed to create MTF TF1 EMA handles.");
         return false;
      }
      if(m_settings.Ind_MTF_Enabled && m_settings.MTF_TF2 != PERIOD_CURRENT && m_settings.MTF_TF2 != m_settings.MTF_TF1 &&
         (h_mtf_tf2_fast == INVALID_HANDLE || h_mtf_tf2_slow == INVALID_HANDLE)) {
         Print("CRITICAL ERROR: Failed to create MTF TF2 EMA handles.");
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

      // --- NEW: Handle cleanup for ATR, CI, and VRC ---
      if(h_atr  != INVALID_HANDLE) { IndicatorRelease(h_atr);  h_atr  = INVALID_HANDLE; }
      if(h_ci   != INVALID_HANDLE) { IndicatorRelease(h_ci);   h_ci   = INVALID_HANDLE; }
      if(h_vrc  != INVALID_HANDLE) { IndicatorRelease(h_vrc);  h_vrc  = INVALID_HANDLE; }
      // ------------------------------------------------

      if(h_macd != INVALID_HANDLE) { IndicatorRelease(h_macd); h_macd = INVALID_HANDLE; }
      if(h_rsi  != INVALID_HANDLE) { IndicatorRelease(h_rsi);  h_rsi  = INVALID_HANDLE; }
      if(h_cci  != INVALID_HANDLE) { IndicatorRelease(h_cci);  h_cci  = INVALID_HANDLE; }
      if(h_adx  != INVALID_HANDLE) { IndicatorRelease(h_adx);  h_adx  = INVALID_HANDLE; }
      if(h_mfi  != INVALID_HANDLE) { IndicatorRelease(h_mfi);  h_mfi  = INVALID_HANDLE; }
      if(h_sto  != INVALID_HANDLE) { IndicatorRelease(h_sto);  h_sto  = INVALID_HANDLE; }
      if(h_bb   != INVALID_HANDLE) { IndicatorRelease(h_bb);   h_bb   = INVALID_HANDLE; }
      if(h_psar != INVALID_HANDLE) { IndicatorRelease(h_psar); h_psar = INVALID_HANDLE; }
      if(h_fractals != INVALID_HANDLE) { IndicatorRelease(h_fractals); h_fractals = INVALID_HANDLE; }

      if(h_mtf_tf1_fast != INVALID_HANDLE) { IndicatorRelease(h_mtf_tf1_fast); h_mtf_tf1_fast = INVALID_HANDLE; }
      if(h_mtf_tf1_slow != INVALID_HANDLE) { IndicatorRelease(h_mtf_tf1_slow); h_mtf_tf1_slow = INVALID_HANDLE; }
      if(h_mtf_tf2_fast != INVALID_HANDLE) { IndicatorRelease(h_mtf_tf2_fast); h_mtf_tf2_fast = INVALID_HANDLE; }
      if(h_mtf_tf2_slow != INVALID_HANDLE) { IndicatorRelease(h_mtf_tf2_slow); h_mtf_tf2_slow = INVALID_HANDLE; }
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

   double PipSize() const { return GlobalPipSize(m_symbol); }
   double SpreadPips() const { return GlobalSpreadPips(m_symbol); }
   
   // GetATR() retrieves the value from h_atr at shift 1
   double AtrPips() const { return GlobalAtrPips(GetATR(), m_symbol); }
   

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

   // --- CANDLE DIRECTION GATE (hard gate, always active when CandleBody_RequireDirection=true) ---
   // Checks that the signal bar (shift=1) closed in the trade direction.
   // This is a binary 0/1 multiplication factor independent of the overextension voter.
   bool CheckCandleDirectionGate(int bias) {
      if(!m_settings.CandleBody_RequireDirection) return true;   // gate disabled
      if(bias == 0)                               return true;   // no directional bias to check

      double o = iOpen(m_symbol, PERIOD_CURRENT, 1);
      double c = iClose(m_symbol, PERIOD_CURRENT, 1);

      if(bias == 1  && c <= o) {   // BUY: reject unless close strictly above open (bullish bar)
         if(m_settings.DebugFlow)
            DebugLog("[GATE] CandleDir: bar not in trade direction (BUY needs bullish close)");
         return false;
      }
      if(bias == -1 && c >= o) {   // SELL: reject unless close strictly below open (bearish bar)
         if(m_settings.DebugFlow)
            DebugLog("[GATE] CandleDir: bar not in trade direction (SELL needs bearish close)");
         return false;
      }
      return true;
   }

   // --- 9b. CANDLE BODY OVEREXTENSION INDICATOR (voting) ---
   bool CheckCandleBodyIndicator(int bias) {
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

      // Close-ratio quality filter (TopInvestor 75% rule)
      // Signal bar close must be in the "strong" portion of its range.
      // LONG:  (close - low)  / (high - low) >= MinCloseRatio
      // SHORT: (high - close) / (high - low) >= MinCloseRatio
      if(m_settings.CandleBody_MinCloseRatio > 0.0)
      {
         double h = iHigh(m_symbol, PERIOD_CURRENT, 1);
         double l = iLow(m_symbol, PERIOD_CURRENT, 1);
         double c = iClose(m_symbol, PERIOD_CURRENT, 1);
         double range = h - l;

         if(range > 0.0)
         {
            double close_ratio = 0.0;
            if(bias == 1)
               close_ratio = (c - l) / range;
            else if(bias == -1)
               close_ratio = (h - c) / range;

            if(close_ratio < m_settings.CandleBody_MinCloseRatio)
            {
               if(m_settings.DebugFlow)
                  DebugLog(StringFormat("[IND_CB_RATIO] CloseRatio=%.2f < Min=%.2f | FAIL",
                                        close_ratio, m_settings.CandleBody_MinCloseRatio));
               return false;
            }
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
   //| UpdateATRHistory(): Update rolling ATR buffer                    |
   //| Called every time GetVolatilityRegime() is invoked              |
   //+------------------------------------------------------------------+
   void UpdateATRHistory(double currentATR)
   {
      if(m_settings.VRC_Lookback <= 0) return;

      // Cap at fixed buffer size
      int maxSize = MathMin(m_settings.VRC_Lookback, 100);

      // Shift existing values right (oldest value falls off at end)
      ArrayCopy(m_atrHistory, m_atrHistory, 1, 0, maxSize - 1);

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
         if(m_settings.DebugFlow) PrintFormat("[VRC] Invalid ATR (%.5f), bypassing filter (insufficient data – handle=%d)", atr, h_atr);
         return VOLATILITY_NORMAL; // Fail-safe: don't filter when data unavailable
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
   // KISS COMPONENT FUNCTIONS
   // Implement the KISS formula: TS = Bias × LayerX × bcX × IndicatorX × FilterX
   // Each component runs independently and returns 0 (fail) or 1/±bias (pass).
   //==========================================================================

   // ─────────────────────────────────────────────────────────────────────────
   // EvaluateFilterX — Non-directional gates (time, news, spread)
   // Returns 1 (all filters pass) or 0 (at least one filter failed).
   // In Stats_FullEvaluation mode: updates m_eval_any_failure but continues.
   // ─────────────────────────────────────────────────────────────────────────
   int EvaluateFilterX(int v_shift)
   {
      // --- Time Window ---
      if(m_settings.UseTime) {
         MqlDateTime dt;
         TimeCurrent(dt);
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
            m_eval_str_F = "TIME";
            if(m_eval_first_failure == "") m_eval_first_failure = "TIME";
            m_eval_any_failure = true;
            if(!m_settings.Stats_FullEvaluation) {
               m_diag_last_reason = "TIME";
               m_reject_filter++;
               return 0;
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
            m_eval_str_F = "NEWS";
            if(m_eval_first_failure == "") m_eval_first_failure = "NEWS";
            m_eval_any_failure = true;
            if(!m_settings.Stats_FullEvaluation) {
               m_diag_last_reason = "NEWS";
               m_reject_filter++;
               return 0;
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
         m_eval_str_F = "SPREAD";
         if(m_eval_first_failure == "") m_eval_first_failure = "SPREAD";
         m_eval_any_failure = true;
         if(!m_settings.Stats_FullEvaluation) {
            m_diag_last_reason = "SPREAD";
            m_reject_filter++;
            return 0;
         }
      }

      if(m_eval_any_failure && m_settings.Stats_FullEvaluation) m_reject_filter++;

      return m_eval_any_failure ? 0 : 1;
   }

   // ─────────────────────────────────────────────────────────────────────────
   // EvaluateBias — Directional market condition (all BiasMode variants)
   // Returns +1 (LONG), -1 (SHORT), or 0 (no directional bias / reject).
   // Includes: BiasEnabled gate, phase filtering, bias computation, AutoStrat,
   //           entry signal validation, and HTF filter.
   // ─────────────────────────────────────────────────────────────────────────
   int EvaluateBias(int v_shift)
   {
      // Master bias gate
      if(!m_settings.BiasEnabled) {
         m_diag_last_reason = "BIAS_DISABLED";
         m_reject_bias++;
         m_stats.rejected_bias++;
         m_ts_status_string = StringFormat("B[-] | I[-] | F[%s]", m_eval_str_F);
         return 0;
      }

      // 2. Determine MASTER BIAS (Strategy)
      int bias = 0;

      int hf = BiasFastHandle();
      int hs = BiasSlowHandle();
      double f_curr = GetMAVal(hf, v_shift, 0);
      double s_curr = GetMAVal(hs, v_shift, 0);

      if(m_settings.BiasMode == BIAS_4EMA)
      {
         bias = GetBias_PhaseBased(v_shift);
         if(m_settings.DebugFlow) {
            datetime bar_time = iTime(m_symbol, PERIOD_CURRENT, v_shift);
            DebugLog(StringFormat("STEP 1 BIAS[%s]: BIAS_4EMA mode → bias=%d", TimeToString(bar_time), bias));
         }
         m_eval_str_B = (bias != 0) ? "+" : "POS";

         if(bias == 0) {
            m_diag_last_bias = 0;
            m_diag_last_reason = "BIAS_ZERO";
            m_reject_bias++;
            m_stats.rejected_bias++;
            if(!m_settings.Stats_FullEvaluation) {
               m_ts_status_string = StringFormat("B[%s] | I[%s] | F[%s]", m_eval_str_B, m_eval_str_I, m_eval_str_F);
               return 0;
            }
            if(m_eval_first_failure == "") m_eval_first_failure = "BIAS_ZERO";
            m_eval_any_failure = true;
         }
         m_diag_last_bias = bias;
      }
      else if(m_settings.BiasMode == BIAS_MANUAL) {
         if(m_settings.ManSide == SIDE_LONG) bias = 1;
         else if(m_settings.ManSide == SIDE_SHORT) bias = -1;
         else bias = 0;

         if((bias == 1 && f_curr <= s_curr) || (bias == -1 && f_curr >= s_curr)) {
            m_eval_str_B = "MAN";
         } else {
            m_eval_str_B = "+";
         }

         if(m_settings.DebugFlow) {
            datetime bar_time = iTime(m_symbol, PERIOD_CURRENT, v_shift);
            DebugLog(StringFormat("STEP 1 BIAS[%s]: MANUAL mode → bias=%d", TimeToString(bar_time), bias));
         }
      }
      else {
         int fast_period = (m_settings.BiasFastID==0) ? m_settings.P_Ema1 : (m_settings.BiasFastID==1) ? m_settings.P_Ema2 : (m_settings.BiasFastID==2) ? m_settings.P_Ema3 : m_settings.P_Ema4;
         int slow_period = (m_settings.BiasSlowID==0) ? m_settings.P_Ema1 : (m_settings.BiasSlowID==1) ? m_settings.P_Ema2 : (m_settings.BiasSlowID==2) ? m_settings.P_Ema3 : m_settings.P_Ema4;
         string ema_fast_name = StringFormat("EMA%d(%d)", m_settings.BiasFastID+1, fast_period);
         string ema_slow_name = StringFormat("EMA%d(%d)", m_settings.BiasSlowID+1, slow_period);

         int lookback = m_settings.SlopeLookbackBars;
         if(lookback < 1) lookback = 1;
         if(lookback > 5) lookback = 5;

         double f_prev = GetMAVal(hf, v_shift + lookback, 0);
         double s_prev = GetMAVal(hs, v_shift + lookback, 0);

         double pip = PipSize();

         int fast_slope = CalculateSlope(f_curr, f_prev);
         int slow_slope = CalculateSlope(s_curr, s_prev);

         int market_bias = 0;

         if(m_settings.BiasFastID == m_settings.BiasSlowID)
         {
            if(fast_slope == 1) { market_bias = 1; m_eval_str_B = "+"; }
            else if(fast_slope == -1) { market_bias = -1; m_eval_str_B = "+"; }
            else m_eval_str_B = "SLOPE";

            if(m_settings.DebugFlow) {
               datetime bar_time = iTime(m_symbol, PERIOD_CURRENT, v_shift);
               double change_pips = (f_curr - f_prev) / pip;
               DebugLog(StringFormat("STEP 1 BIAS[%s]: SINGLE_SLOPE %s | curr=%.5f prev=%.5f change=%.2f pips slope=%s lookback=%d → bias=%d",
                                     TimeToString(bar_time), ema_fast_name, f_curr, f_prev, change_pips,
                                     (fast_slope==1)?"RISING":(fast_slope==-1)?"FALLING":"FLAT", lookback, market_bias));
            }
         }
         else
         {
            if(f_curr > s_curr && fast_slope == 1)       { market_bias = 1;  m_eval_str_B = "+"; }
            else if(f_curr < s_curr && fast_slope == -1) { market_bias = -1; m_eval_str_B = "+"; }
            else m_eval_str_B = "SLOPE";

            if(m_settings.DebugFlow) {
               datetime bar_time = iTime(m_symbol, PERIOD_CURRENT, v_shift);
               double fast_change_pips = (f_curr - f_prev) / pip;
               double slow_change_pips = (s_curr - s_prev) / pip;
               string position = (f_curr > s_curr) ? "ABOVE" : (f_curr < s_curr) ? "BELOW" : "EQUAL";
               DebugLog(StringFormat("STEP 1 BIAS[%s]: PAIR %s vs %s | fast=%.5f(%+.2fp %s) slow=%.5f(%+.2fp %s) pos=%s lookback=%d → bias=%d",
                                     TimeToString(bar_time), ema_fast_name, ema_slow_name,
                                     f_curr, fast_change_pips, (fast_slope==1)?"UP":(fast_slope==-1)?"DN":"FLAT",
                                     s_curr, slow_change_pips, (slow_slope==1)?"UP":(slow_slope==-1)?"DN":"FLAT",
                                     position, lookback, market_bias));
            }
         }

         if(market_bias == 0) {
            m_diag_last_bias = 0;
            m_diag_last_reason = "BIAS_ZERO";
            m_reject_bias++;
            m_stats.rejected_bias++;

            if(m_settings.DebugFlow) {
               datetime bar_time = iTime(m_symbol, PERIOD_CURRENT, v_shift);
               DebugLog(StringFormat("STEP 1 BIAS[%s]: bias=0 → REJECT (no trend)", TimeToString(bar_time)));
            }

            if(!m_settings.Stats_FullEvaluation) {
               m_ts_status_string = StringFormat("B[%s] | I[%s] | F[%s]", m_eval_str_B, m_eval_str_I, m_eval_str_F);
               return 0;
            }
            if(m_eval_first_failure == "") m_eval_first_failure = "BIAS_ZERO";
            m_eval_any_failure = true;
         }

         // === STEP 2: Evaluate AutoStrat for Entry Signal ===
         int entry_signal = 0;

         if(m_settings.AutoStrat == STRAT_1EMA_SLOPE) {
            entry_signal = fast_slope;
            if(m_settings.DebugFlow) {
               datetime bar_time = iTime(m_symbol, PERIOD_CURRENT, v_shift);
               DebugLog(StringFormat("STEP 2 ENTRY[%s]: STRAT_1EMA_SLOPE %s slope=%d → signal=%d", TimeToString(bar_time), ema_fast_name, fast_slope, entry_signal));
            }
         }
         else if(m_settings.AutoStrat == STRAT_2EMA_CROSS_PRICE) {
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
               DebugLog(StringFormat("STEP 2 ENTRY[%s]: STRAT_2EMA_CROSS_PRICE %s price=%.5f ma=%.5f → signal=%d", TimeToString(bar_time), ema_fast_name, price, ma, entry_signal));
            }
         }
         else if(m_settings.AutoStrat == STRAT_2EMA_POSITION) {
            entry_signal = market_bias;
            if(m_settings.DebugFlow) {
               datetime bar_time = iTime(m_symbol, PERIOD_CURRENT, v_shift);
               string direction = (entry_signal == 1) ? "LONG (position + slopes aligned UP)" :
                                  (entry_signal == -1) ? "SHORT (position + slopes aligned DOWN)" : "NEUTRAL (slopes not aligned or conflicting)";
               DebugLog(StringFormat("[BIAS_POSITION_SLOPE][%s] Fast=%.5f Slow=%.5f | SlopeFast=%d SlopeSlow=%d → %s",
                                     TimeToString(bar_time), f_curr, s_curr, fast_slope, slow_slope, direction));
            }
         }
         else if(m_settings.AutoStrat == STRAT_4EMA_LAYER) {
            // KISS design: pass bias directly to pipeline.
            // Layer qualification (position+slope per EMA pair) is handled in EvaluateLayerX().
            // Bar close confirmation is handled in EvaluateBcX().
            // DetectLayerSignal() (wick-touch) is NOT used — it contradicts the design intent.
            entry_signal = market_bias;
            if(m_settings.DebugFlow) {
               datetime bar_time = iTime(m_symbol, PERIOD_CURRENT, v_shift);
               DebugLog(StringFormat("STEP 2 ENTRY[%s]: STRAT_4EMA_LAYER → bias=%d passed to KISS pipeline",
                                     TimeToString(bar_time), entry_signal));
            }
         }
         else {  // STRAT_2EMA_CROSS_EMA
            double f_curr_cross = GetMAVal(hf, v_shift, 0);
            double f_prev_cross = GetMAVal(hf, v_shift + 1, 0);
            double s_curr_cross = GetMAVal(hs, v_shift, 0);
            double s_prev_cross = GetMAVal(hs, v_shift + 1, 0);

            bool bullish_cross = (f_prev_cross <= s_prev_cross && f_curr_cross > s_curr_cross);
            bool bearish_cross = (f_prev_cross >= s_prev_cross && f_curr_cross < s_curr_cross);
            bool has_crossover = (bullish_cross || bearish_cross);

            if(bullish_cross) entry_signal = 1;
            else if(bearish_cross) entry_signal = -1;
            else if(m_settings.ExitProfile == EXIT_PROFILE_RRM && market_bias != 0) {
               bool ema_position_matches_bias = (market_bias == 1) ? (f_curr_cross > s_curr_cross) : (f_curr_cross < s_curr_cross);
               if(ema_position_matches_bias) {
                  entry_signal = market_bias;
                  if(m_settings.DebugFlow) {
                     datetime bar_time = iTime(m_symbol, PERIOD_CURRENT, v_shift);
                     DebugLog(StringFormat("STEP 2 ENTRY[%s]: RRM CONTINUATION bias=%d trend intact f=%.5f %s s=%.5f → signal=%d",
                                           TimeToString(bar_time), market_bias, f_curr_cross, (market_bias == 1 ? ">" : "<"), s_curr_cross, entry_signal));
                  }
               }
               else {
                  entry_signal = 0;
                  if(m_settings.DebugFlow) {
                     datetime bar_time = iTime(m_symbol, PERIOD_CURRENT, v_shift);
                     DebugLog(StringFormat("STEP 2 ENTRY[%s]: RRM CONTINUATION rejected f=%.5f vs s=%.5f bias=%d → signal=0",
                                           TimeToString(bar_time), f_curr_cross, s_curr_cross, market_bias));
                  }
               }
            }
            else {
               entry_signal = 0;
               if(m_settings.DebugFlow) {
                  datetime bar_time = iTime(m_symbol, PERIOD_CURRENT, v_shift);
                  DebugLog(StringFormat("STEP 2 ENTRY[%s]: STRAT_2EMA_CROSS_EMA no crossover → signal=0", TimeToString(bar_time)));
               }
            }

            if(m_settings.DebugFlow && has_crossover) {
               datetime bar_time = iTime(m_symbol, PERIOD_CURRENT, v_shift);
               DebugLog(StringFormat("STEP 2 ENTRY[%s]: STRAT_2EMA_CROSS_EMA %s vs %s prev: %.5f vs %.5f curr: %.5f vs %.5f → signal=%d",
                                     TimeToString(bar_time), ema_fast_name, ema_slow_name, f_prev_cross, s_prev_cross, f_curr_cross, s_curr_cross, entry_signal));
            }
         }

         // === STEP 3: Validate Entry Signal Against Market Bias ===
         if(entry_signal == market_bias) {
            bias = market_bias;
            if(m_settings.DebugFlow) {
               datetime bar_time = iTime(m_symbol, PERIOD_CURRENT, v_shift);
               DebugLog(StringFormat("STEP 3 MATCH[%s]: entry=%d matches bias=%d → PASS", TimeToString(bar_time), entry_signal, market_bias));
            }
         }
         else {
            bias = 0;
            m_diag_last_bias = 0;
            m_diag_last_reason = "SIGNAL_MISMATCH";

            if(m_settings.DebugFlow) {
               datetime bar_time = iTime(m_symbol, PERIOD_CURRENT, v_shift);
               DebugLog(StringFormat("STEP 3 MATCH[%s]: entry=%d != bias=%d → REJECT", TimeToString(bar_time), entry_signal, market_bias));
            }
            m_reject_bias++;
            m_stats.rejected_bias++;
            if(!m_settings.Stats_FullEvaluation) {
               m_ts_status_string = StringFormat("B[%s] | I[%s] | F[%s]", m_eval_str_B, m_eval_str_I, m_eval_str_F);
               return 0;
            }
            if(m_eval_first_failure == "") m_eval_first_failure = "SIGNAL_MISMATCH";
            m_eval_any_failure = true;
         }
      }

      m_diag_last_bias = bias;
      if(bias == 0) {
         m_diag_last_reason = "BIAS_ZERO";
         m_reject_bias++;
         m_stats.rejected_bias++;
         if(!m_settings.Stats_FullEvaluation) {
            m_ts_status_string = StringFormat("B[%s] | I[%s] | F[%s]", m_eval_str_B, m_eval_str_I, m_eval_str_F);
            return 0;
         }
         if(m_eval_first_failure == "") m_eval_first_failure = "BIAS_ZERO";
         m_eval_any_failure = true;
      }
      else {
         m_stats.passed_bias++;
         if(bias > 0) m_stats.passed_bias_long++;
         else         m_stats.passed_bias_short++;
      }

      return bias;
   }

   // ─────────────────────────────────────────────────────────────────────────
   // EvaluateLayerX — KISS Component: Phase + EMA pair structural alignment
   // Checks all 3 layers (W/M/S) and stores results in m_eval_layer_{w/m/s}.
   // Returns 1 if at least one layer is aligned, 0 if none are aligned.
   // Guard: returns 1 (pass) when EnableLayerDetection=false or BiasMode!=BIAS_4EMA.
   // ─────────────────────────────────────────────────────────────────────────
   int EvaluateLayerX(int v_shift, int bias)
   {
      // Layer detection only applies to BIAS_4EMA phase system
      if(!m_settings.EnableLayerDetection || m_settings.BiasMode != BIAS_4EMA)
      {
         m_eval_layer_w = 1;
         m_eval_layer_m = 1;
         m_eval_layer_s = 1;
         m_diag_layer_w = 1;
         m_diag_layer_m = 1;
         m_diag_layer_s = 1;
         if(m_settings.DebugFlow) DebugLog("STEP 3 LAYER: Disabled/N.A. (non-4EMA mode) → PASS");
         return 1;
      }

      // ═══════════════════════════════════════════════════════════════
      // KISS: Evaluate LayerX (structural alignment per EMA pair)
      // ═══════════════════════════════════════════════════════════════
      m_eval_layer_w = CheckLayerPairAlign(bias, 1);
      m_eval_layer_m = CheckLayerPairAlign(bias, 2);
      m_eval_layer_s = CheckLayerPairAlign(bias, 3);

      if(m_settings.DebugLevel >= DEBUG_INDICATORS) {
         DebugLog(StringFormat("[KISS] Step3 LayerW=%d LayerM=%d LayerS=%d (bias=%d)", m_eval_layer_w, m_eval_layer_m, m_eval_layer_s, bias));
      }

      if(m_eval_layer_w == 0 && m_eval_layer_m == 0 && m_eval_layer_s == 0) {
         m_diag_last_reason = "LAYER_NONE_ALIGNED";
         m_reject_gate++;
         if(m_settings.DebugFlow) DebugLog("STEP 3 LAYER: No layer aligned → REJECT");
         m_ts_status_string = StringFormat("B[%s] | I[%s] | F[%s]", m_eval_str_B, m_eval_str_I, m_eval_str_F);
         return 0;
      }
      if(m_settings.DebugFlow) DebugLog("STEP 3 LAYER: At least one layer aligned → PASS");

      m_diag_layer_w = m_eval_layer_w;
      m_diag_layer_m = m_eval_layer_m;
      m_diag_layer_s = m_eval_layer_s;

      return 1;
   }

   // ─────────────────────────────────────────────────────────────────────────
   // EvaluateBcX — KISS Component: Bar close confirmation (bcX)
   // Uses m_eval_layer_{w/m/s} from EvaluateLayerX to check active layers only.
   // Layer-aware: LayerW→EMA1, LayerM→EMA2, LayerS→EMA3
   // Returns 1 if at least one active layer has its bar close confirmed, 0 otherwise.
   // ─────────────────────────────────────────────────────────────────────────
   int EvaluateBcX(int v_shift, int bias)
   {
      // For non-4EMA modes (layer detection disabled), use a direct bc check
      if(!m_settings.EnableLayerDetection || m_settings.BiasMode != BIAS_4EMA)
      {
         int bc_result = Eval_BarClose(v_shift, bias, LAYER_NONE);

         if(m_settings.DebugLevel >= DEBUG_INDICATORS) {
            DebugLog(StringFormat("[KISS] Step4 bcX=%d (non-layer mode, bias=%d, mode=%s)",
                                  bc_result, bias, EnumToString(m_settings.BarClose_Mode)));
         }
         if(bc_result == 0) {
            m_diag_last_reason = "BC_NOT_CONFIRMED";
            m_reject_gate++;
            if(m_settings.DebugFlow) DebugLog("STEP 4 BCX: Bar close not confirmed → REJECT");
            m_ts_status_string = StringFormat("B[%s] | I[%s] | F[%s]", m_eval_str_B, m_eval_str_I, m_eval_str_F);
            return 0;
         }
         if(m_settings.DebugFlow) DebugLog("STEP 4 BCX: Bar close confirmed → PASS");
         return 1;
      }

      // ═══════════════════════════════════════════════════════════════
      // KISS: bcX (Bar close confirmation, layer-aware)
      // Only evaluate bcX for active layers; inactive layers default to pass (1)
      // ═══════════════════════════════════════════════════════════════
      int bc_w = (m_eval_layer_w == 1) ? Eval_BarClose(v_shift, bias, LAYER_1_WEAK)   : 1;
      int bc_m = (m_eval_layer_m == 1) ? Eval_BarClose(v_shift, bias, LAYER_2_MEDIUM) : 1;
      int bc_s = (m_eval_layer_s == 1) ? Eval_BarClose(v_shift, bias, LAYER_3_STRONG) : 1;

      if(m_settings.DebugLevel >= DEBUG_INDICATORS) {
         DebugLog(StringFormat("[KISS] Step4 bcW=%d bcM=%d bcS=%d (bias=%d, mode=%s)",
                               bc_w, bc_m, bc_s, bias, EnumToString(m_settings.BarClose_Mode)));
      }

      // At least one active layer must have its bcX confirmed
      bool bc_any = ((m_eval_layer_w == 1 && bc_w == 1) ||
                     (m_eval_layer_m == 1 && bc_m == 1) ||
                     (m_eval_layer_s == 1 && bc_s == 1));

      if(!bc_any) {
         m_diag_last_reason = "BC_NOT_CONFIRMED";
         m_reject_gate++;
         if(m_settings.DebugFlow) DebugLog("STEP 4 BCX: No active layer close confirmed → REJECT");
         m_ts_status_string = StringFormat("B[%s] | I[%s] | F[%s]", m_eval_str_B, m_eval_str_I, m_eval_str_F);
         return 0;
      }
      if(m_settings.DebugFlow) DebugLog("STEP 4 BCX: Active layer close confirmed → PASS");

      // Determine active setup type and store KISS diagnostics
      string active_setup = "";
      if(m_eval_layer_w == 1 && bc_w == 1)       active_setup = "LayerW (Weak/Ribbon) - Shallow pullback EMA1/2";
      else if(m_eval_layer_m == 1 && bc_m == 1)  active_setup = "LayerM (Medium/Ghost) - Medium pullback EMA2/3";
      else if(m_eval_layer_s == 1 && bc_s == 1)  active_setup = "LayerS (Strong/Shark) - Deep pullback EMA3/4";
      else                                        active_setup = "None (no active layer confirmed)";

      if(m_settings.DebugLevel >= DEBUG_INDICATORS) {
         DebugLog(StringFormat("[KISS] Setup: %s | Bias=%d | Layers: W=%d M=%d S=%d | bcX: W=%d M=%d S=%d",
                               active_setup, bias, m_eval_layer_w, m_eval_layer_m, m_eval_layer_s, bc_w, bc_m, bc_s));
      }

      return 1;
   }

   // ─────────────────────────────────────────────────────────────────────────
   // EvaluateIndicatorX — KISS Component: Voting consensus
   // Casts all enabled indicator votes, logs diagnostics, applies vote mode.
   // Returns bias if voting passes, 0 if consensus fails.
   // ─────────────────────────────────────────────────────────────────────────
   int EvaluateIndicatorX(int v_shift, int bias)
   {
      // ═══════════════════════════════════════════════════════════════
      // 4. Voting Logic — All enabled indicators must agree (VOTE_MODE_ALL)
      // vote_weight is accumulated for statistics only; trade decisions use all_pass
      // ═══════════════════════════════════════════════════════════════
      double vote_weight = 0.0;
      bool   all_pass    = true;

      #define CAST_VOTE_STAT(use_flag, weight_field, check_expr, stat_rej_field, stat_pass_field) \
         if(use_flag) { \
            bool _cv_pass = (check_expr); \
            if(_cv_pass) { vote_weight += weight_field; stat_pass_field++; } \
            else { all_pass = false; stat_rej_field++; } \
         }

      CAST_VOTE_STAT(m_settings.Ind_Adx_Enabled,    m_settings.Ind_Adx_Weight,    Check_ADX(v_shift),        m_stats.rejected_adx, m_stats.passed_adx)
      CAST_VOTE_STAT(m_settings.Ind_Macd_Enabled,   m_settings.Ind_Macd_Weight,   Check_MACD(bias, v_shift), m_stats.rejected_macd, m_stats.passed_macd)
      CAST_VOTE_STAT(m_settings.Ind_Rsi_Enabled,    m_settings.Ind_Rsi_Weight,    Check_RSI(bias, v_shift),  m_stats.rejected_rsi, m_stats.passed_rsi)
      CAST_VOTE_STAT(m_settings.Ind_Cci_Enabled,    m_settings.Ind_Cci_Weight,    Check_CCI(bias, v_shift),  m_stats.rejected_cci, m_stats.passed_cci)
      CAST_VOTE_STAT(m_settings.Ind_Mfi_Enabled,    m_settings.Ind_Mfi_Weight,    Check_MFI(bias, v_shift),  m_stats.rejected_mfi, m_stats.passed_mfi)
      CAST_VOTE_STAT(m_settings.Ind_Sto_Enabled,    m_settings.Ind_Sto_Weight,    Check_Sto(bias, v_shift),  m_stats.rejected_sto, m_stats.passed_sto)
      CAST_VOTE_STAT(m_settings.Ind_Bb_Enabled,     m_settings.Ind_Bb_Weight,     Check_BB(bias, v_shift),   m_stats.rejected_bb, m_stats.passed_bb)
      CAST_VOTE_STAT(m_settings.Ind_Psar_Enabled,   m_settings.Ind_Psar_Weight,   (m_settings.Vote_AllowPsarFlip ? Check_PSAR_WithFlip(bias, v_shift) : Check_PSAR(bias, v_shift)), m_stats.rejected_psar, m_stats.passed_psar)
      CAST_VOTE_STAT(m_settings.Ind_P123_Enabled,   m_settings.Ind_P123_Weight,   Check_P123(bias, v_shift), m_stats.rejected_p123, m_stats.passed_p123)
      CAST_VOTE_STAT(m_settings.Ind_Ross_Enabled,   m_settings.Ind_Ross_Weight,   Check_Ross(bias, v_shift), m_stats.rejected_ross, m_stats.passed_ross)

      // --- NON-DIRECTIONAL SYSTEM FILTERS ---
      CAST_VOTE_STAT(m_settings.Ind_Atr_Enabled,        m_settings.Ind_Atr_Weight,        Check_ATR(bias, v_shift),        m_stats.rejected_atr, m_stats.passed_atr)
      CAST_VOTE_STAT(m_settings.Ind_CandleBody_Enabled, m_settings.Ind_CandleBody_Weight, Check_CandleBody(bias, v_shift), m_stats.rejected_candle_body, m_stats.passed_candle_body)
      CAST_VOTE_STAT(m_settings.Ind_CI_Enabled,         m_settings.Ind_CI_Weight,         Check_CI(bias, v_shift),         m_stats.rejected_ci, m_stats.passed_ci)
      CAST_VOTE_STAT(m_settings.Ind_VRC_Enabled,        m_settings.Ind_VRC_Weight,        Check_VRC(bias, v_shift),        m_stats.rejected_vrc, m_stats.passed_vrc)
      CAST_VOTE_STAT(m_settings.Ind_SmaConverge_Enabled, m_settings.Ind_SmaConverge_Weight, Check_SmaConverge(v_shift),      m_stats.rejected_sma_converge, m_stats.passed_sma_converge)
      CAST_VOTE_STAT(m_settings.Ind_Dpi_Enabled,         m_settings.Ind_Dpi_Weight,         Check_DPI(bias, v_shift),         m_stats.rejected_dpi,          m_stats.passed_dpi)
      CAST_VOTE_STAT(m_settings.Ind_Fib_Enabled,         m_settings.Ind_Fib_Weight,         Check_Fib(bias, v_shift),         m_stats.rejected_fib,          m_stats.passed_fib)
      CAST_VOTE_STAT(m_settings.Ind_MTF_Enabled,         m_settings.Ind_MTF_Weight,         Check_MTF(bias),                  m_stats.rejected_mtf,          m_stats.passed_mtf)
      #undef CAST_VOTE_STAT

      // Calculate indicator pass counts for telemetry (all enabled indicators, including non-directional filters)
      int s_enabled=0, s_passed=0;
      if(m_settings.Ind_Adx_Enabled)         { s_enabled++; if(Check_ADX(v_shift)) s_passed++; }
      if(m_settings.Ind_Macd_Enabled)        { s_enabled++; if(Check_MACD(bias, v_shift)) s_passed++; }
      if(m_settings.Ind_Rsi_Enabled)         { s_enabled++; if(Check_RSI(bias, v_shift)) s_passed++; }
      if(m_settings.Ind_Cci_Enabled)         { s_enabled++; if(Check_CCI(bias, v_shift)) s_passed++; }
      if(m_settings.Ind_Mfi_Enabled)         { s_enabled++; if(Check_MFI(bias, v_shift)) s_passed++; }
      if(m_settings.Ind_Sto_Enabled)         { s_enabled++; if(Check_Sto(bias, v_shift)) s_passed++; }
      if(m_settings.Ind_Bb_Enabled)          { s_enabled++; if(Check_BB(bias, v_shift)) s_passed++; }
      if(m_settings.Ind_Psar_Enabled)        { s_enabled++; if(m_settings.Vote_AllowPsarFlip ? Check_PSAR_WithFlip(bias, v_shift) : Check_PSAR(bias, v_shift)) s_passed++; }
      if(m_settings.Ind_P123_Enabled)        { s_enabled++; if(Check_P123(bias, v_shift)) s_passed++; }
      if(m_settings.Ind_Ross_Enabled)        { s_enabled++; if(Check_Ross(bias, v_shift)) s_passed++; }
      if(m_settings.Ind_SmaConverge_Enabled) { s_enabled++; if(Check_SmaConverge(v_shift)) s_passed++; }
      if(m_settings.Ind_Dpi_Enabled)         { s_enabled++; if(Check_DPI(bias, v_shift)) s_passed++; }
      if(m_settings.Ind_Fib_Enabled)         { s_enabled++; if(Check_Fib(bias, v_shift)) s_passed++; }
      if(m_settings.Ind_Atr_Enabled)         { s_enabled++; if(Check_ATR(bias, v_shift)) s_passed++; }
      if(m_settings.Ind_CandleBody_Enabled)  { s_enabled++; if(Check_CandleBody(bias, v_shift)) s_passed++; }
      if(m_settings.Ind_CI_Enabled)          { s_enabled++; if(Check_CI(bias, v_shift)) s_passed++; }
      if(m_settings.Ind_VRC_Enabled)         { s_enabled++; if(Check_VRC(bias, v_shift)) s_passed++; }
      if(m_settings.Ind_MTF_Enabled)         { s_enabled++; if(Check_MTF(bias)) s_passed++; }

      // Always use indicator pass count for display (vote_weight is informational only, does not gate trades)
      m_diag_last_votes = s_passed;

      m_eval_str_I = StringFormat("%d/%d", s_passed, s_enabled);
      m_ts_status_string = StringFormat("B[%s] | I[%s] | F[%s]", m_eval_str_B, m_eval_str_I, m_eval_str_F);

      // Per-indicator results for diagnostic logging
      bool _res_adx=false, _res_macd=false, _res_rsi=false,
           _res_cci=false, _res_mfi=false, _res_sto=false, _res_bb=false,
           _res_psar=false, _res_p123=false, _res_ross=false, _res_dpi=false, _res_fib=false,
           _res_atr=false, _res_candle_body=false, _res_ci=false, _res_vrc=false;

      // ===== DIAGNOSTIC LOGGING FOR VOTE ANALYSIS: BEGIN =====
      if(m_settings.DebugLevel >= DEBUG_INDICATORS) {
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
          if(m_settings.Ind_Dpi_Enabled)         _res_dpi         = Check_DPI(bias, v_shift);
          if(m_settings.Ind_Fib_Enabled)         _res_fib         = Check_Fib(bias, v_shift);
          if(m_settings.Ind_Atr_Enabled)         _res_atr         = Check_ATR(bias, v_shift);
          if(m_settings.Ind_CandleBody_Enabled)  _res_candle_body = Check_CandleBody(bias, v_shift);
          if(m_settings.Ind_CI_Enabled)          _res_ci          = Check_CI(bias, v_shift);
          if(m_settings.Ind_VRC_Enabled)         _res_vrc         = Check_VRC(bias, v_shift);

         if(m_settings.DebugLevel >= DEBUG_FULL) {
            string mode_str = (m_settings.VoteMode == VOTE_MODE_ALL ? "ALL" : "THRESHOLD");
            DebugLog(StringFormat("[IND] --- Indicators (mode=%s bias=%d weight=%.2f) ---",
                                  mode_str, bias, vote_weight));

            if(m_settings.Ind_Adx_Enabled) {
               double adx = GetVal(h_adx, v_shift);
               DebugLog(StringFormat("[IND] ADX: %.2f / threshold=%.2f → %s (w=%d)",
                                     adx, m_cachedADXThreshold, _res_adx ? "PASS" : "FAIL", m_settings.Ind_Adx_Weight));
            } else DebugLog("[IND] ADX: DISABLED → SKIP");

            if(m_settings.Ind_Macd_Enabled) {
               double macd_m = GetVal(h_macd, v_shift, 0);
               double macd_s = GetVal(h_macd, v_shift, 1);
               DebugLog(StringFormat("[IND] MACD: main=%.6f signal=%.6f hist=%.6f → %s (w=%d)",
                                     macd_m, macd_s, macd_m - macd_s, _res_macd ? "PASS" : "FAIL", m_settings.Ind_Macd_Weight));
            } else DebugLog("[IND] MACD: DISABLED → SKIP");

            if(m_settings.Ind_Rsi_Enabled) {
               double r = GetVal(h_rsi, v_shift);
               DebugLog(StringFormat("[IND] RSI: %.2f (OB=%.0f OS=%.0f) → %s (w=%d)",
                                     r, m_settings.T_RsiOB, m_settings.T_RsiOS, _res_rsi ? "PASS" : "FAIL", m_settings.Ind_Rsi_Weight));
            } else DebugLog("[IND] RSI: DISABLED → SKIP");

            if(m_settings.Ind_Cci_Enabled) {
               double c = GetVal(h_cci, v_shift);
               DebugLog(StringFormat("[IND] CCI: %.2f → %s (w=%d)",
                                     c, _res_cci ? "PASS" : "FAIL", m_settings.Ind_Cci_Weight));
            } else DebugLog("[IND] CCI: DISABLED → SKIP");

            if(m_settings.Ind_Mfi_Enabled) {
               double mfi = GetVal(h_mfi, v_shift);
               DebugLog(StringFormat("[IND] MFI: %.2f (OB=%.0f OS=%.0f) → %s (w=%d)",
                                     mfi, m_settings.T_MfiOB, m_settings.T_MfiOS, _res_mfi ? "PASS" : "FAIL", m_settings.Ind_Mfi_Weight));
            } else DebugLog("[IND] MFI: DISABLED → SKIP");

            if(m_settings.Ind_Sto_Enabled) {
               double sk = GetVal(h_sto, v_shift, 0);
               double sd = GetVal(h_sto, v_shift, 1);
               DebugLog(StringFormat("[IND] Stoch: K=%.2f D=%.2f (OB=%.0f OS=%.0f) → %s (w=%d)",
                                     sk, sd, m_settings.T_StoOB, m_settings.T_StoOS, _res_sto ? "PASS" : "FAIL", m_settings.Ind_Sto_Weight));
            } else DebugLog("[IND] Stoch: DISABLED → SKIP");

            if(m_settings.Ind_Bb_Enabled) {
               double bb_mid = GetVal(h_bb, v_shift, 0);
               double cl_bb  = iClose(m_symbol, PERIOD_CURRENT, v_shift);
               DebugLog(StringFormat("[IND] BB: mid=%.5f close=%.5f → %s (w=%d)",
                                     bb_mid, cl_bb, _res_bb ? "PASS" : "FAIL", m_settings.Ind_Bb_Weight));
            } else DebugLog("[IND] BB: DISABLED → SKIP");

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
               DebugLog(StringFormat("[IND] PSAR: dot=%.5f close=%.5f%s → %s (w=%d)",
                                     psar_v, cl_p, flip_info, _res_psar ? "PASS" : "FAIL", m_settings.Ind_Psar_Weight));
            } else DebugLog("[IND] PSAR: DISABLED → SKIP");

            if(m_settings.Ind_P123_Enabled) {
               DebugLog(StringFormat("[IND] P123: → %s (w=%d)", _res_p123 ? "PASS" : "FAIL", m_settings.Ind_P123_Weight));
            } else DebugLog("[IND] P123: DISABLED → SKIP");

            if(m_settings.Ind_Ross_Enabled) {
               DebugLog(StringFormat("[IND] RossHook: → %s (w=%d)", _res_ross ? "PASS" : "FAIL", m_settings.Ind_Ross_Weight));
            } else DebugLog("[IND] RossHook: DISABLED → SKIP");

            if(m_settings.Ind_Dpi_Enabled) {
               DebugLog(StringFormat("[IND] DPI v31: F=%d S=%d RedType=%d CCI=%d Green=%d → %s (w=%d)",
                                     m_settings.DPI_MACD_Fast, m_settings.DPI_MACD_Slow, m_settings.DPI_RedSignalType,
                                     m_settings.DPI_UseCCIReset ? m_settings.DPI_CCI_Period : 0,
                                     m_settings.DPI_UseGreenHist ? 1 : 0,
                                     _res_dpi ? "PASS" : "FAIL", m_settings.Ind_Dpi_Weight));
            } else DebugLog("[IND] DPI: DISABLED → SKIP");

            if(m_settings.Ind_Atr_Enabled) {
               double atr_v_pips = m_diag_last_atr_pips;
               bool   atr_v_ok   = true;
               if(m_settings.ATR_VoteMinPips > 0.0 && atr_v_pips < m_settings.ATR_VoteMinPips) atr_v_ok = false;
               if(m_settings.ATR_VoteMaxPips > 0.0 && atr_v_pips > m_settings.ATR_VoteMaxPips) atr_v_ok = false;
               DebugLog(StringFormat("[IND] ATR Vote: %.1f pips (min=%.1f max=%.1f) → %s (w=1)",
                                     atr_v_pips, m_settings.ATR_VoteMinPips, m_settings.ATR_VoteMaxPips,
                                     atr_v_ok ? "PASS" : "FAIL"));
            } else
               DebugLog("[IND] ATR Vote: DISABLED → SKIP");

            if(m_settings.Ind_CandleBody_Enabled) {
               bool cb_ok = CheckCandleBodyIndicator(bias);
               DebugLog(StringFormat("[IND] CandleBody: avg period=%d max=x%.1f check=%d → %s (w=%d)",
                                     m_settings.CandleBody_AvgPeriod, m_settings.CandleBody_MaxMult,
                                     m_settings.CandleBody_CheckBars, cb_ok ? "PASS" : "FAIL",
                                     m_settings.Ind_CandleBody_Weight));
            } else
               DebugLog("[IND] CandleBody: DISABLED → SKIP");

            if(m_settings.Ind_CI_Enabled) {
               double ci_val = CalculateCI(v_shift);
               bool ci_ok = Check_CI(bias, v_shift);
               string ci_status = (ci_val >= m_settings.CI_RangingThreshold ? "RANGING" : "TRENDING");
               DebugLog(StringFormat("[IND] ChoppinessIndex: CI=%.1f threshold=%.1f status=%s → %s (w=%d)",
                                     ci_val, m_settings.CI_RangingThreshold, ci_status,
                                     ci_ok ? "PASS" : "FAIL", m_settings.Ind_CI_Weight));
            } else
               DebugLog("[IND] ChoppinessIndex: DISABLED → SKIP");
         }
      }
      // ===== DIAGNOSTIC LOGGING FOR VOTE ANALYSIS: END =====

      // Store results for TS_SUMMARY diagnostic block in EvaluateTS()
      m_eval_ind_res_adx    = _res_adx;
      m_eval_ind_res_macd   = _res_macd;
      m_eval_ind_res_rsi    = _res_rsi;
      m_eval_ind_res_cci    = _res_cci;
      m_eval_ind_res_mfi    = _res_mfi;
      m_eval_ind_res_sto    = _res_sto;
      m_eval_ind_res_bb     = _res_bb;
      m_eval_ind_res_psar   = _res_psar;
      m_eval_ind_res_p123   = _res_p123;
      m_eval_ind_res_ross   = _res_ross;
      m_eval_ind_res_sma_converge = (m_settings.Ind_SmaConverge_Enabled ? Check_SmaConverge(v_shift) : false);
      m_eval_ind_res_dpi          = _res_dpi;
      m_eval_ind_res_fib          = _res_fib;
      m_eval_ind_res_atr          = _res_atr;
      m_eval_ind_res_candle_body  = _res_candle_body;
      m_eval_ind_res_ci           = _res_ci;
      m_eval_ind_res_vrc          = _res_vrc;
      m_eval_vote_weight    = vote_weight;
      m_eval_all_pass       = all_pass;

      // Apply vote mode and return result
      if(all_pass) {
         m_diag_last_reason = "OK";
         m_signals_generated++;
         m_stats.signals_confirmed++;
         if(bias > 0) m_stats.signals_confirmed_long++;
         else         m_stats.signals_confirmed_short++;
         if(m_settings.DebugFlow) DebugLog(StringFormat("[RESULT] TS=%d (ALL votes pass, weight=%.2f)", bias, vote_weight));
         return bias;
      }
      else {
         m_diag_last_reason = StringFormat("NOT_ALL_PASS (%d/%d)", s_passed, s_enabled);
         m_reject_votes++;
         // SHORT rejection trace (temporary diagnostic)
         if(bias < 0) {
            string fails = "";
            if(m_settings.Ind_Psar_Enabled && !(m_settings.Vote_AllowPsarFlip ? Check_PSAR_WithFlip(bias, v_shift) : Check_PSAR(bias, v_shift))) fails += "PSAR ";
            if(m_settings.Ind_Dpi_Enabled && !Check_DPI(bias, v_shift)) fails += "DPI ";
            if(m_settings.Ind_CandleBody_Enabled && !Check_CandleBody(bias, v_shift)) fails += "CBODY ";
            if(m_settings.Ind_MTF_Enabled && !Check_MTF(bias)) fails += "MTF ";
            if(m_settings.Ind_Adx_Enabled && !Check_ADX(v_shift)) fails += "ADX ";
            if(m_settings.Ind_Macd_Enabled && !Check_MACD(bias, v_shift)) fails += "MACD ";
            if(m_settings.Ind_Cci_Enabled && !Check_CCI(bias, v_shift)) fails += "CCI ";
            datetime bar_time = iTime(m_symbol, PERIOD_CURRENT, v_shift);
            PrintFormat("[SHORT_REJECT] %s | %d/%d pass | FAILED: %s",
                        TimeToString(bar_time, TIME_DATE|TIME_MINUTES), s_passed, s_enabled, fails);
         }
         if(m_settings.DebugFlow) DebugLog(StringFormat("[RESULT] TS=0 REJECT (%s)", m_diag_last_reason));
         return 0;
      }
   }

   // ─────────────────────────────────────────────────────────────────────────
   // GetBias_4EMA_Direction — Internal helper for EvaluateB (BIAS_4EMA only)
   // Returns market direction from phase WITHOUT applying phase-gate blocking.
   // Phase blocking is the responsibility of EvaluateP, not this function.
   // Returns: +1 (LONG), -1 (SHORT), 0 (UNORDERED — no clear direction)
   // ─────────────────────────────────────────────────────────────────────────
   int GetBias_4EMA_Direction(const int v_shift = 1)
   {
      bool diag_bias = (m_settings.DebugFlow || m_settings.DebugLevel >= DEBUG_SUMMARY);
      if(diag_bias) {
         PrintFormat("[GET_BIAS_4EMA] shift=%d phaseEnabled=%s", v_shift, m_settings.PhaseDetectionEnabled ? "TRUE" : "FALSE");
      }

      if(!m_settings.PhaseDetectionEnabled) {
         if(diag_bias)
            Print("[GET_BIAS_4EMA] PhaseDetectionEnabled=FALSE -> returning 0 (NEUTRAL)");
         return 0;
      }

      EMarketPhase phase = DetectMarketPhase(v_shift);
      m_diag_last_phase = phase;
      if(diag_bias)
         Print("[GET_BIAS_4EMA] phase=", EnumToString(phase));

      if(m_settings.RequireMinPhaseConfirm && m_settings.MinPhaseConfirmBars > 0) {
         if(!ConfirmPhaseStability(phase, m_settings.MinPhaseConfirmBars)) {
            if(diag_bias)
               Print("[GET_BIAS_4EMA] Phase not stable -> returning 0");
            return 0;
         }
      }

      int result = 0;
      switch(phase)
      {
         case PHASE_TRENDING_UP:
         case PHASE_EMERGING_UP:
            result = 1;
            break;
         case PHASE_TRENDING_DN:
         case PHASE_EMERGING_DN:
            result = -1;
            break;
         case PHASE_TRENDING:
         case PHASE_EMERGING: {
            double ema2 = GetMAVal(h_ema2, v_shift, 0);
            double ema4 = GetMAVal(h_ema4, v_shift, 0);
            double tol  = 2.0 * SymbolInfoDouble(m_symbol, SYMBOL_POINT);
            if(ema2 > ema4 + tol) result = 1;
            else if(ema4 > ema2 + tol) result = -1;
            else result = 0;
            break;
         }
         case PHASE_UNORDERED:
         default:
            result = 0;
            break;
      }

      if(diag_bias) {
         Print("[GET_BIAS_4EMA] Returning bias: ", result,
               " (", result == 1 ? "LONG" : (result == -1 ? "SHORT" : "NEUTRAL"), ")");
      }
      return result;
   }

   // ─────────────────────────────────────────────────────────────────────────
   // EvaluateB — Bias (TS equation factor B)
   // Returns +1 (LONG), -1 (SHORT), or 0 (no directional bias → blocked).
   //
   // For BIAS_4EMA: uses slowest EMA pair (EMA3/EMA4) via phase classification.
   //   Direction is returned WITHOUT phase-gate blocking; EvaluateP handles that.
   // For all other modes: delegates to the existing EvaluateBias() implementation.
   // ─────────────────────────────────────────────────────────────────────────
   int EvaluateB(int v_shift)
   {
      if(m_settings.BiasMode != BIAS_4EMA)
         return EvaluateBias(v_shift);  // Non-4EMA: existing logic unchanged

      bool diag_bias = (m_settings.DebugFlow || m_settings.DebugLevel >= DEBUG_SUMMARY);
      if(diag_bias) {
         datetime bar_time = iTime(m_symbol, PERIOD_CURRENT, v_shift);
         double ema2 = GetMAVal(h_ema2, v_shift, 0);
         double ema3 = GetMAVal(h_ema3, v_shift, 0);
         double ema4 = GetMAVal(h_ema4, v_shift, 0);
         double price = iClose(m_symbol, PERIOD_CURRENT, v_shift);
         EMarketPhase detected_phase = DetectMarketPhase(v_shift);

         PrintFormat("[BIAS_DIAGNOSTIC] bar=%s shift=%d mode=%s biasEnabled=%s phaseEnabled=%s",
                     TimeToString(bar_time, TIME_DATE|TIME_MINUTES), v_shift, EnumToString(m_settings.BiasMode),
                     m_settings.BiasEnabled ? "TRUE" : "FALSE", m_settings.PhaseDetectionEnabled ? "TRUE" : "FALSE");
         PrintFormat("[BIAS_DIAGNOSTIC] price=%s ema2(%d)=%s ema3(%d)=%s ema4(%d)=%s phase_direct=%s phase_prev=%s",
                     DoubleToString(price, _Digits), m_settings.P_Ema2, DoubleToString(ema2, _Digits),
                     m_settings.P_Ema3, DoubleToString(ema3, _Digits), m_settings.P_Ema4, DoubleToString(ema4, _Digits),
                     EnumToString(detected_phase), EnumToString(m_diag_last_phase));
      }

      // ── BIAS_4EMA path: direction from phase, no phase-gate blocking ──
      if(!m_settings.BiasEnabled) {
         if(diag_bias)
            Print("[BIAS_DIAGNOSTIC] BIAS_DISABLED -> returning 0");
         m_diag_last_reason = "BIAS_DISABLED";
         m_reject_bias++;
         m_stats.rejected_bias++;
         m_eval_str_B = "0";
         m_ts_status_string = "B[-] | P[-] | L[-] | I[-]";
         return 0;
      }

      int bias = GetBias_4EMA_Direction(v_shift);
      m_eval_str_B = (bias != 0) ? "+" : "POS";
      if(diag_bias) {
         Print("[BIAS_DIAGNOSTIC] GetBias_4EMA_Direction returned: ", bias,
               " (", bias == 1 ? "LONG" : (bias == -1 ? "SHORT" : "NEUTRAL"), ")");
         Print("[BIAS_DIAGNOSTIC] m_diag_last_phase (post): ", EnumToString(m_diag_last_phase));
      }

      if(m_settings.DebugFlow) {
         datetime bar_time = iTime(m_symbol, PERIOD_CURRENT, v_shift);
         DebugLog(StringFormat("EvaluateB[%s]: BIAS_4EMA phase=%s → bias=%d",
                               TimeToString(bar_time), EnumToString(m_diag_last_phase), bias));
      }

      if(bias == 0) {
         m_diag_last_reason = "BIAS_ZERO";
         m_reject_bias++;
         m_stats.rejected_bias++;
         if(!m_settings.Stats_FullEvaluation) {
            m_ts_status_string = StringFormat("B[%s] | I[%s] | F[%s]", m_eval_str_B, m_eval_str_I, m_eval_str_F);
            m_diag_last_bias = 0;
            return 0;
         }
         if(m_eval_first_failure == "") m_eval_first_failure = "BIAS_ZERO";
         m_eval_any_failure = true;
       } else {
          m_stats.passed_bias++;
          if(bias > 0) m_stats.passed_bias_long++;
          else         m_stats.passed_bias_short++;
       }

      m_diag_last_bias = bias;
      return bias;
   }

   // ─────────────────────────────────────────────────────────────────────────
   // EvaluateP — Phase (TS equation factor P)
   // Returns 1 (phase allows trading) or 0 (phase blocks trading).
   //
   // Only meaningful for BiasMode == BIAS_4EMA with PhaseDetectionEnabled.
   // For all other configurations returns 1 (not applicable, pass through).
   //
   //   PHASE_UNORDERED  → always 0 (no market structure)
   //   PHASE_EMERGING_* → 0 if BlockEmergingPhase=true, else 1
   //   PHASE_TRENDING_* → 1 (fully aligned market structure)
   // ─────────────────────────────────────────────────────────────────────────
   int EvaluateP(int v_shift, int bias)
   {
      if(m_settings.BiasMode != BIAS_4EMA || !m_settings.PhaseDetectionEnabled)
         return 1;  // Not applicable for non-4EMA modes → pass

      // m_diag_last_phase was set by GetBias_4EMA_Direction inside EvaluateB
      EMarketPhase phase = m_diag_last_phase;

      if(m_settings.DebugFlow) {
         datetime bar_time = iTime(m_symbol, PERIOD_CURRENT, v_shift);
         DebugLog(StringFormat("EvaluateP[%s]: phase=%s bias=%d",
                               TimeToString(bar_time), EnumToString(phase), bias));
      }

      // UNORDERED: no clear market structure → block when BlockUnorderedPhase=true.
      // Note: GetBias_4EMA_Direction() already returns 0 for UNORDERED (no direction
      // is possible when EMA stack is chaotic), so EvaluateB returns B=0 in this case.
      // EvaluateP always runs this check; in non-full_eval mode EvaluateTS will have
      // already returned early when B=0, so this check mainly applies in full_eval mode
      // for complete per-factor stat attribution.
      if(phase == PHASE_UNORDERED && m_settings.BlockUnorderedPhase) {
         m_diag_last_reason = "PHASE_UNORDERED";
         m_reject_gate++;
         if(m_settings.DebugFlow) Print("[EvaluateP] UNORDERED phase → no market structure");
         if(!m_settings.Stats_FullEvaluation) {
            m_ts_status_string = StringFormat("B[%s] | I[%s] | F[%s]", m_eval_str_B, m_eval_str_I, m_eval_str_F);
            return 0;
         }
         if(m_eval_first_failure == "") m_eval_first_failure = "PHASE_UNORDERED";
         m_eval_any_failure = true;
         return 0;
      }

      // EMERGING: trend forming — configurable gate
      bool is_emerging = (phase == PHASE_EMERGING_UP || phase == PHASE_EMERGING_DN ||
                          phase == PHASE_EMERGING);
      if(is_emerging && m_settings.BlockEmergingPhase) {
         m_diag_last_reason = "PHASE_EMERGING";
         m_reject_gate++;
         if(m_settings.DebugFlow) Print("[EvaluateP] EMERGING phase blocked (BlockEmergingPhase=true)");
         if(!m_settings.Stats_FullEvaluation) {
            m_ts_status_string = StringFormat("B[%s] | I[%s] | F[%s]", m_eval_str_B, m_eval_str_I, m_eval_str_F);
            return 0;
         }
         if(m_eval_first_failure == "") m_eval_first_failure = "PHASE_EMERGING";
         m_eval_any_failure = true;
         return 0;
      }

      return 1;  // TRENDING or allowed EMERGING → pass
   }

   // ─────────────────────────────────────────────────────────────────────────
   // EvaluateL — Layer (TS equation factor L)
   // Evaluates pullback-recovery timing via EMA pair alignment with L3→L2→L1 priority.
   //
   // Per-layer sub-equation: L_x = pos_x × slope_x × BC_x × BD_x
   //   pos   = fast EMA correctly above/below slow EMA for bias direction
   //   slope = both EMAs slope in bias direction (recovery confirmed)
   //   BC    = bar close price beyond fast EMA of that layer (no wicks)
   //   BD    = bar direction matches bias (close > open LONG / close < open SHORT)
   //
   // Priority: L3 (Strong/EMA3-EMA4) → L2 (Medium/EMA2-EMA3) → L1 (Weak/EMA1-EMA2)
   // First layer passing ALL 4 checks wins; active layer stored in m_last_layer.
   //
   // Returns 1 if any layer passes, 0 if none.
   // If EnableLayerDetection=false or BiasMode!=BIAS_4EMA → returns 1 (N/A, pass).
   // ─────────────────────────────────────────────────────────────────────────
   int EvaluateL(int v_shift, int bias)
   {
      if(!m_settings.EnableLayerDetection || m_settings.BiasMode != BIAS_4EMA)
      {
         m_eval_layer_w = 1; m_eval_layer_m = 1; m_eval_layer_s = 1;
         m_diag_layer_w = 1; m_diag_layer_m = 1; m_diag_layer_s = 1;
         m_last_layer   = 0;
         if(m_settings.DebugFlow) DebugLog("EvaluateL: Disabled/N/A (non-4EMA mode) → PASS");
         return 1;
      }

      // Step 1: pos × slope alignment check for all three layers
      m_eval_layer_w = CheckLayerPairAlign(bias, 1);
      m_eval_layer_m = CheckLayerPairAlign(bias, 2);
      m_eval_layer_s = CheckLayerPairAlign(bias, 3);
      m_diag_layer_w = m_eval_layer_w;
      m_diag_layer_m = m_eval_layer_m;
      m_diag_layer_s = m_eval_layer_s;

      if(m_settings.DebugLevel >= DEBUG_INDICATORS) {
         DebugLog(StringFormat("[EvaluateL] LayerW=%d LayerM=%d LayerS=%d (bias=%d)",
                               m_eval_layer_w, m_eval_layer_m, m_eval_layer_s, bias));
      }

      // Step 2: BD (Bar Direction) — same bar, applies equally to all layers
      bool bd_pass = CheckCandleDirectionGate(bias);

      int lookback = MathMax(1, MathMin(4, m_settings.BarClose_LookbackBars));
      bool momentum_confirmed = true;
      if(lookback > 1 && m_settings.Require_Progressive_Momentum)
      {
         momentum_confirmed = Check_Progressive_Momentum(v_shift, bias, lookback);
         if(!momentum_confirmed && m_settings.DPI_Histogram_Growth_Boost)
            momentum_confirmed = Check_DPI_Histogram_Growing(v_shift, bias, lookback);
      }

      // Step 3: Priority walk L3 → L2 → L1; each layer also needs BC and BD
      if(m_eval_layer_s == 1) {
         int bc_s = Eval_BarClose(v_shift, bias, LAYER_3_STRONG);
         if(bc_s == 0 && lookback > 1)
            bc_s = Check_BarClose_MultiBar(v_shift, bias, LAYER_3_STRONG, lookback) ? 1 : 0;
         if(bc_s == 1 && bd_pass && momentum_confirmed) {
            m_last_layer = 3;
            if(m_settings.DebugFlow) DebugLog("EvaluateL: L3 (Strong/EMA3-EMA4) PASS → L=1");
            return 1;
         }
      }

      if(m_eval_layer_m == 1) {
         int bc_m = Eval_BarClose(v_shift, bias, LAYER_2_MEDIUM);
         if(bc_m == 0 && lookback > 1)
            bc_m = Check_BarClose_MultiBar(v_shift, bias, LAYER_2_MEDIUM, lookback) ? 1 : 0;
         if(bc_m == 1 && bd_pass && momentum_confirmed) {
            m_last_layer = 2;
            if(m_settings.DebugFlow) DebugLog("EvaluateL: L2 (Medium/EMA2-EMA3) PASS → L=1");
            return 1;
         }
      }

      if(m_eval_layer_w == 1) {
         int bc_w = Eval_BarClose(v_shift, bias, LAYER_1_WEAK);
         if(bc_w == 0 && lookback > 1)
            bc_w = Check_BarClose_MultiBar(v_shift, bias, LAYER_1_WEAK, lookback) ? 1 : 0;
         if(bc_w == 1 && bd_pass && momentum_confirmed) {
            m_last_layer = 1;
            if(m_settings.DebugFlow) DebugLog("EvaluateL: L1 (Weak/EMA1-EMA2) PASS → L=1");
            return 1;
         }
      }

      // No layer passed all checks
      m_last_layer = 0;
      if(m_eval_layer_w == 0 && m_eval_layer_m == 0 && m_eval_layer_s == 0)
         m_diag_last_reason = "LAYER_NONE_ALIGNED";
      else if(!bd_pass)
         m_diag_last_reason = "CandleDir: bar not in trade direction";
      else if(!momentum_confirmed)
         m_diag_last_reason = "MOMENTUM_NOT_CONFIRMED";
      else
         m_diag_last_reason = "BC_NOT_CONFIRMED";

      m_reject_gate++;
      if(m_settings.DebugFlow) DebugLog(StringFormat("EvaluateL: REJECT (%s)", m_diag_last_reason));
      if(!m_settings.Stats_FullEvaluation) {
         m_ts_status_string = StringFormat("B[%s] | I[%s] | F[%s]", m_eval_str_B, m_eval_str_I, m_eval_str_F);
         return 0;
      }
      if(m_eval_first_failure == "") m_eval_first_failure = m_diag_last_reason;
      m_eval_any_failure = true;
      return 0;
   }

   // ─────────────────────────────────────────────────────────────────────────
   // EvaluateI — Indicators (TS equation factor I)
   // Thin wrapper: all indicator voting logic, diagnostics, and counters are
   // preserved exactly as in EvaluateIndicatorX.
   // Returns +bias (all enabled indicators pass) or 0 (consensus not reached).
   // ─────────────────────────────────────────────────────────────────────────
   int EvaluateI(int v_shift, int bias)
   {
      return EvaluateIndicatorX(v_shift, bias);
   }

   // ───────────────────────────────────────────────────────────────────────────
   // ComputeDPIMainHist — DPI v31 inline histogram computation
   // Architecture (mirrors DPI_v31_CLEAN_22_OK_FINAL_WORKING.mq5):
   //   Blue(i) = EMA(DPI_MACD_Fast, close)(i) − EMA(DPI_MACD_Slow, close)(i)
   //   Red(i)  = EMA(RedSignalType, Blue)(i)   [or double-smooth of Blue]
   //   hist(i) = Blue(i) − Red(i)
   //
   //   out_hist_cur   = hist at v_shift   (current bar)
   //   out_hist_prev  = hist at v_shift+1 (previous bar)
   //   out_green      = (DPI_UseGreenHist) ? Blue and hist on same side of zero : false
   //   out_macd_agree = (DPI_UseCCIReset)  ? hist sign agrees with CCI sign     : (hist >= 0)
   //
   // Returns false if insufficient bars, DPI not enabled, or computation fails.
   // Used by: DPI deceleration pre-filter in EvaluateTS, and Check_DPI voter.
   // No static locals, no lambdas — safe for MQL5 on macOS/Wine.
   // ───────────────────────────────────────────────────────────────────────────
   bool ComputeDPIMainHist(int v_shift, double &out_hist_cur, double &out_hist_prev,
                           bool &out_green, bool &out_macd_agree,
                           double &out_green_mag_cur, double &out_green_mag_prev)
   {
      if(!m_settings.Ind_Dpi_Enabled) return false;

      int MFast  = m_settings.DPI_MACD_Fast;
      int MSlow  = m_settings.DPI_MACD_Slow;
      int RST    = m_settings.DPI_RedSignalType;

      // Determine Red-EMA period(s) based on signal type
      int redPer1 = 1;  // primary EMA period for Red line
      int redPer2 = 1;  // secondary EMA period (only used when RST == 5 double-smooth)
      switch(RST)
      {
         case 1: redPer1 = m_settings.DPI_RedEMA_A;           redPer2 = redPer1; break;
         case 2: redPer1 = m_settings.DPI_RedEMA_B;           redPer2 = redPer1; break;
         case 3: redPer1 = m_settings.DPI_RedEMA_C;           redPer2 = redPer1; break;
         case 4: redPer1 = m_settings.DPI_RedEMA_D;           redPer2 = redPer1; break;
         case 5: redPer1 = m_settings.DPI_DoubleSmoothFirst;  redPer2 = m_settings.DPI_DoubleSmoothSecond; break;
         default: redPer1 = m_settings.DPI_RedEMA_C;          redPer2 = redPer1; break;
      }

      // bars_needed: Slow-EMA warmup + max(Red EMA) + 1 prev-bar capture + v_shift + 5 safety
      int maxRed = MathMax(redPer1, redPer2);
      int bars_needed = MSlow + maxRed + v_shift + 7;
      if(iBars(m_symbol, PERIOD_CURRENT) <= bars_needed) return false;

      double alphaFast  = 2.0 / (double)(MFast  + 1);
      double alphaSlow  = 2.0 / (double)(MSlow  + 1);
      double alphaRed1  = 2.0 / (double)(redPer1 + 1);
      double alphaRed2  = 2.0 / (double)(redPer2 + 1);

      double ema_fast = 0.0, ema_slow = 0.0;
      double blue     = 0.0;
      double red1     = 0.0, red2 = 0.0;  // red2 only used for double-smooth
      double hist     = 0.0;

      out_hist_cur       = 0.0;
      out_hist_prev      = 0.0;
      out_green          = false;
      out_macd_agree     = false;
      out_green_mag_cur  = 0.0;
      out_green_mag_prev = 0.0;

      // Seed EMAs at the oldest bar so that initial Blue = 0 (fast = slow = seed price).
      double seed = iClose(m_symbol, PERIOD_CURRENT, bars_needed);
      ema_fast = seed;
      ema_slow = seed;
      // Blue starts at 0 → Red EMA(s) start at 0 for consistency.
      red1 = 0.0;
      red2 = 0.0;

      // ── Capture variables for GREEN at prev bar (v_shift+1) ──
      double blue_prev = 0.0, hist_at_prev = 0.0;

      // Iterate from oldest bar toward v_shift (capturing hist at v_shift+1 en route).
      for(int i = bars_needed - 1; i >= v_shift; i--)
      {
         double cl = iClose(m_symbol, PERIOD_CURRENT, i);

         // Blue line = EMA(Fast, close) − EMA(Slow, close)
         ema_fast = alphaFast * cl   + (1.0 - alphaFast) * ema_fast;
         ema_slow = alphaSlow * cl   + (1.0 - alphaSlow) * ema_slow;
         blue     = ema_fast - ema_slow;

         // Red signal line
         if(RST == 5)
         {
            // Double-smooth: EMA(DoubleSmoothFirst, Blue) then EMA(DoubleSmoothSecond, that)
            red1 = alphaRed1 * blue + (1.0 - alphaRed1) * red1;
            red2 = alphaRed2 * red1 + (1.0 - alphaRed2) * red2;
            hist = blue - red2;
         }
         else
         {
            // Single EMA of Blue
            red1 = alphaRed1 * blue + (1.0 - alphaRed1) * red1;
            hist = blue - red1;
         }

         if(i == v_shift + 1)
         {
            out_hist_prev = hist;
            blue_prev    = blue;
            hist_at_prev = hist;
         }
      }
      out_hist_cur = hist;

      // out_green: Blue and hist on the same side of zero (momentum alignment)
      if(m_settings.DPI_UseGreenHist)
         out_green = ((blue > 0.0 && hist > 0.0) || (blue < 0.0 && hist < 0.0));
      else
         out_green = false;

      // ── GREEN magnitude: min(|Blue|, |hist|) when aligned, else 0 ──
      // GREEN = the area from 0 to the closer of Blue/hist (both same side).
      // Matches DPI_mc_main.mq5 rendering logic.
      bool green_present_cur = ((blue > 0.0 && hist > 0.0) || (blue < 0.0 && hist < 0.0));
      out_green_mag_cur  = green_present_cur ? MathMin(MathAbs(blue), MathAbs(hist)) : 0.0;

      bool green_present_prev = ((blue_prev > 0.0 && hist_at_prev > 0.0) || (blue_prev < 0.0 && hist_at_prev < 0.0));
      out_green_mag_prev = green_present_prev ? MathMin(MathAbs(blue_prev), MathAbs(hist_at_prev)) : 0.0;

      // out_macd_agree: trend filter flag — dual-use:
      //   DPI_UseCCIReset=true  → true when hist sign agrees with CCI sign (no CCI reset warning)
      //   DPI_UseCCIReset=false → true when hist >= 0 (pass-through; caller uses for decel filter)
      if(m_settings.DPI_UseCCIReset)
      {
         // FIXED — inline CCI, bit-identical to DPI_mc_main.mq5:
         double cci_v = ComputeDPI_CCI(v_shift);
         out_macd_agree = ((hist >= 0.0 && cci_v >= 0.0) || (hist < 0.0 && cci_v < 0.0));
      }
      else
      {
         out_macd_agree = (hist >= 0.0);
      }

      return true;
   }

   // ══════════════════════════════════════════════════════════════════════
   // SIGNAL EVALUATION — TS/TE EQUATION
   //
   // TS = B × P × L × I        (bar close, shift=1)
   // TE = F                     (bar open, shift=0)
   //
   // B  Bias:       Direction from slowest EMA pair (+1 LONG / -1 SHORT / 0 block)
   // P  Phase:      Market type — TM/EM allowed, UNO always blocks
   //                Evaluated via EMA2/EMA3/EMA4 position only (no slopes)
   // L  Layer:      Pullback-recovery timing (L3 > L2 > L1 priority)
   //                Per layer: pos × slope × BC × BD
   //                  BC = bar close beyond fast EMA (close price vs EMA, no wicks)
   //                  BD = bar direction in bias (close > open LONG / close < open SHORT)
   // I  Indicators: All enabled must agree (MACD, PSAR, RSI, CCI, ADX, ...)
   //                CandleBody (spike filter) belongs here, not in L
   // F  Filters:    Spread × session × news (execution-moment, TE only)
   //
   // Any factor = 0 → whole equation = 0 → NO TRADE
   // ══════════════════════════════════════════════════════════════════════
   int EvaluateTS()
   {
      int v_shift = m_settings.Vote_EvalShift;
      m_debug_buffer_size = 0;
      ArrayResize(m_debug_buffer, 0);

      // Invalidate indicator cache if evaluating a different bar
      datetime eval_bar_time = iTime(m_symbol, PERIOD_CURRENT, v_shift);
      ApplyForcedDebug(eval_bar_time);
      if(v_shift != m_ind_cache.cached_shift || eval_bar_time != m_ind_cache.cached_bar_time)
         InvalidateIndicatorCache(v_shift);

      // Update DPI histogram state (once per bar)
      UpdateDPIHistogramState(v_shift);

      if(m_settings.DebugFlow) {
         DebugLog("[DEBUG_TEST] EvaluateTS() CALLED");
         DebugLog(StringFormat("[DEBUG_TEST] m_settings.DebugFlow = %s", m_settings.DebugFlow ? "TRUE" : "FALSE"));
         DebugLog(StringFormat("[DEBUG_TEST] Current time: %s", TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES)));
      }

      // Update PSAR flip tracking on each bar close (uses shift=1 for closed bar)
      if(m_settings.Vote_AllowPsarFlip)
         UpdatePSARFlipTracking(m_settings.Vote_EvalShift);

      UpdatePhaseDiagnostics(m_settings.ma_v_shift);

      // ═══════════════════════════════════════════════════════════════
      // Reset diagnostics, telemetry, and evaluation state
      // ═══════════════════════════════════════════════════════════════
      m_diag_last_bias   = 0;
      m_diag_last_votes  = 0;
      m_diag_last_reason = "";
      m_ts_status_string = "B[0] | I[0/0] | F[OK]";

      m_telemetry.bias = 0;
      m_telemetry.phase = 0;
      m_telemetry.layer = 0;
      m_telemetry.votes_for = 0;
      m_telemetry.votes_total = 0;
      m_telemetry.rejection_reason = SEA_STATUS_EVALUATING;
      m_telemetry.active_indicators = "0/0";
      m_telemetry.mtf_status = (m_settings.Ind_MTF_Enabled ? "[MTF] Pending" : "N/A");
      m_bars_evaluated++;
      m_stats.total_bars++;

      // Reset evaluation state (shared between named component functions)
      m_eval_any_failure   = false;
      m_eval_first_failure = "";
      m_eval_str_F         = "OK";
      m_eval_str_B         = "0";
      m_eval_str_I         = "0/0";
      m_eval_layer_w       = 0;
      m_eval_layer_m       = 0;
      m_eval_layer_s       = 0;
      m_eval_vote_weight   = 0.0;
      m_eval_all_pass      = false;
      m_last_layer         = 0;
      bool full_eval       = m_settings.Stats_FullEvaluation;

      // Data readiness guard: prevents indicator/price math on weekend-gap holes
      // and short-history startup states (common during long-period tests).
      int min_required_bars = v_shift + 2 + MathMax(0, m_settings.MinBarsAfterWeekendGap);
      bool bars_ready = (iBars(m_symbol, PERIOD_CURRENT) > min_required_bars);
      bool bar_now_valid  = HasValidBarData(v_shift);
      bool bar_prev_valid = HasValidBarData(v_shift + 1);
      if(!bars_ready || !bar_now_valid || !bar_prev_valid)
      {
         if(m_settings.DebugFlow)
            DebugLog(StringFormat("[TS_PREFILTER] DATA_GAP: bars_ready=%s bar[%d]=%s bar[%d]=%s → TS=0",
                                  bars_ready ? "true" : "false",
                                  v_shift, bar_now_valid ? "valid" : "invalid",
                                  v_shift + 1, bar_prev_valid ? "valid" : "invalid"));
         m_diag_last_reason = "DATA_GAP";
         m_reject_filter++;
         if(!full_eval) {
            m_ts_status_string = StringFormat("B[%s] | I[%s] | F[%s]", m_eval_str_B, m_eval_str_I, m_eval_str_F);
            UpdateTelemetry(0);
            FlushOrClearDebugBuffer(0);
            RestoreForcedDebug();
            return 0;
         }
         if(m_eval_first_failure == "") m_eval_first_failure = "DATA_GAP";
         m_eval_any_failure = true;
      }

      int bars_since_weekend_gap = -1;
      if(IsWithinWeekendGapCooldown(v_shift, bars_since_weekend_gap))
      {
         if(m_settings.DebugFlow)
            DebugLog(StringFormat("[TS_PREFILTER] WEEKEND_GAP: cooldown active (%d/%d bars) → TS=0",
                                  bars_since_weekend_gap, m_settings.MinBarsAfterWeekendGap));
         m_diag_last_reason = "WEEKEND_GAP";
         m_reject_filter++;
         if(!full_eval) {
            m_ts_status_string = StringFormat("B[%s] | I[%s] | F[%s]", m_eval_str_B, m_eval_str_I, m_eval_str_F);
            UpdateTelemetry(0);
            FlushOrClearDebugBuffer(0);
            RestoreForcedDebug();
            return 0;
         }
         if(m_eval_first_failure == "") m_eval_first_failure = "WEEKEND_GAP";
         m_eval_any_failure = true;
      }

      // Bar-close diagnostic banner
      if(m_settings.DebugFlow) {
         datetime bar_time = iTime(m_symbol, PERIOD_CURRENT, m_settings.ma_v_shift);
         DebugLog("[EVAL_START] ===========================================");
         DebugLog(StringFormat("[EVAL_START] Bar: %s (shift=%d)",
                               TimeToString(bar_time, TIME_DATE|TIME_MINUTES), m_settings.ma_v_shift));
         DebugLog("[EVAL_START] ===========================================");
      }

      // ── B: Bias ──────────────────────────────────────────────────
      int B = EvaluateB(v_shift);
      if(B == 0 && !full_eval) {
         m_ts_status_string = StringFormat("B[%s] | I[%s] | F[%s]", m_eval_str_B, m_eval_str_I, m_eval_str_F);
         UpdateTelemetry(0);
         FlushOrClearDebugBuffer(0);
         RestoreForcedDebug();
         return 0;
      }

      // ── P: Phase ─────────────────────────────────────────────────
      int P = EvaluateP(v_shift, B);
      if(P == 0 && !full_eval) {
         m_ts_status_string = StringFormat("B[%s] | I[%s] | F[%s]", m_eval_str_B, m_eval_str_I, m_eval_str_F);
         UpdateTelemetry(0);
         FlushOrClearDebugBuffer(0);
         RestoreForcedDebug();
         return 0;
      }

      // ── MTF: moved to indicator voting (EvaluateIndicatorX) ─────────
      // MTF is a voter with weight Ind_MTF_Weight, not a hard gate.
      // Telemetry updated inside EvaluateIndicatorX alongside other voters.
      if(m_settings.Ind_MTF_Enabled)
      {
         string mtf_reason = "";
         string mtf_diag   = "";
         CheckMTFFilter(B, mtf_reason, mtf_diag);
         m_telemetry.mtf_status = mtf_diag;
      }

      // ══════════════════════════════════════════════════════════════════
      // FIX Bug6: TS_PREFILTER blocks (EMA_FAN, DPI_DECEL) moved BEFORE EvaluateL
      // so cheap guards abort the pipeline before the expensive 4-EMA LayerAlign scan.
      // ══════════════════════════════════════════════════════════════════

      // ══════════════════════════════════════════════════════════════════
      // PRE-FILTER: EMA Fan Overextension
      // Block when EMA1–EMA4 spread > threshold AND still expanding.
      // Avoids chasing overextended trend runs.
      // EmaFanMaxTotalPips=25.0 is a starting default for M1/M5; review per TF.
      // JPY pairs (~3-digit pricing): GlobalPipSize() already returns the correct
      // pip unit so the comparison works without special-casing.
      // ══════════════════════════════════════════════════════════════════
      if(m_settings.EmaFanFilterEnabled && m_settings.EmaFanMaxTotalPips > 0.0)
      {
         double pip  = GlobalPipSize(m_symbol);
         double e1_1 = GetMAVal(h_ema1, v_shift);
         double e4_1 = GetMAVal(h_ema4, v_shift);
         double e1_2 = GetMAVal(h_ema1, v_shift + 1);
         double e4_2 = GetMAVal(h_ema4, v_shift + 1);

         if(e1_1 > 0.0 && e4_1 > 0.0 && e1_2 > 0.0 && e4_2 > 0.0 && pip > 0.0)
         {
            double gap_now  = MathAbs(e1_1 - e4_1) / pip;
            double gap_prev = MathAbs(e1_2 - e4_2) / pip;

            if(gap_now > m_settings.EmaFanMaxTotalPips && gap_now > gap_prev)
            {
               if(m_settings.DebugFlow)
                  PrintFormat("[TS_PREFILTER] EMA_FAN: gap_now=%.1f pips > max=%.1f (prev=%.1f) → TS=0",
                              gap_now, m_settings.EmaFanMaxTotalPips, gap_prev);
               m_diag_last_reason = "EMA_OVEREXT";
               m_reject_filter++;
               m_stats.rejected_emafan++;       // PHASE A.1
               if(!full_eval) {
                  m_ts_status_string = StringFormat("B[%s] | I[%s] | F[%s]", m_eval_str_B, m_eval_str_I, m_eval_str_F);
                  UpdateTelemetry(0);
                  FlushOrClearDebugBuffer(0);
                  RestoreForcedDebug();
                  return 0;
               }
               if(m_eval_first_failure == "") m_eval_first_failure = "EMA_OVEREXT";
               m_eval_any_failure = true;
            }
         }
      }

      // ══════════════════════════════════════════════════════════════════
      // PRE-FILTER: DPI GREEN Momentum Deceleration
      // Block when GREEN histogram is shrinking or disappearing bar-over-bar.
      // GREEN = min(|Blue|, |hist|) when Blue & hist same side of zero.
      // Per README_SEA_DPI_mc_main.md: "Blocks entry when GREEN[shift] < GREEN[shift+1]"
      // Only active when DpiDecelFilterEnabled=true AND Ind_Dpi_Enabled=true.
      // Silently passes if histogram data unavailable.
      // ══════════════════════════════════════════════════════════════════
      if(m_settings.DpiDecelFilterEnabled && m_settings.Ind_Dpi_Enabled)
      {
         double hist_cur = 0.0, hist_prev = 0.0;
         bool   dpi_green = false, dpi_macd_agree = false;
         double green_mag_cur = 0.0, green_mag_prev = 0.0;

         if(ComputeDPIMainHist(v_shift, hist_cur, hist_prev, dpi_green, dpi_macd_agree,
                               green_mag_cur, green_mag_prev))
         {
            // GREEN deceleration: momentum confirmation weakening or vanishing.
            //
            // Case 1: GREEN present on both bars but shrinking → momentum fading → BLOCK
            // Case 2: GREEN was present, now gone → momentum just died (OB/OS) → BLOCK
            // Case 3: GREEN absent on both bars → no momentum to decelerate → PASS
            //         (ribbon-only setups are valid — direction without momentum
            //          is not deceleration, it's a different market state)
            // Case 4: GREEN was absent, now appeared → momentum arriving → PASS

            bool green_was_present = (green_mag_prev > 0.0);
            bool green_is_present  = (green_mag_cur  > 0.0);
            bool blocked = false;

            if(green_was_present && green_is_present && green_mag_cur < green_mag_prev)
            {
               // Case 1: GREEN shrinking — momentum fading
               blocked = true;
               if(m_settings.DebugFlow)
                  PrintFormat("[TS_PREFILTER] DPI_DECEL: GREEN shrinking cur=%.6f < prev=%.6f → TS=0",
                              green_mag_cur, green_mag_prev);
            }
            else if(green_was_present && !green_is_present)
            {
               // Case 2: GREEN just disappeared — exhaustion / OB/OS
               blocked = true;
               if(m_settings.DebugFlow)
                  PrintFormat("[TS_PREFILTER] DPI_DECEL: GREEN disappeared (prev=%.6f, cur=0) → TS=0",
                              green_mag_prev);
            }

            if(blocked)
            {
               m_diag_last_reason = "DPI_DECEL";
               m_reject_filter++;
               m_stats.rejected_dpi_decel++;    // PHASE A.1
               if(!full_eval) {
                  m_ts_status_string = StringFormat("B[%s] | I[%s] | F[%s]", m_eval_str_B, m_eval_str_I, m_eval_str_F);
                  UpdateTelemetry(0);
                  FlushOrClearDebugBuffer(0);
                  RestoreForcedDebug();
                  return 0;
               }
               if(m_eval_first_failure == "") m_eval_first_failure = "DPI_DECEL";
               m_eval_any_failure = true;
            }
         }
      }

      // ══════════════════════════════════════════════════════════════════
      // PRE-FILTER (PHASE A.1): DPI Histogram Deceleration (PR #3)
      // Uses m_dpi_hist_decelerating from UpdateDPIHistogramState() (PR #1).
      // Rejects entries when momentum is decelerating (approaching exhaustion).
      // ══════════════════════════════════════════════════════════════════
      if(m_settings.DPI_BlockOnDeceleration && m_settings.DPI_HistTrackingEnabled)
      {
         if(m_dpi_hist_decelerating)
         {
            if(m_settings.DebugFlow)
               DebugLog(StringFormat("[FILTER_DPI_DECEL] REJECT | DPI histogram decelerating (approaching exhaustion) | CCI=%.2f | Trend=%s",
                                     m_dpi_hist_current,
                                     (m_dpi_hist_trend == 1 ? "GREEN" : m_dpi_hist_trend == -1 ? "RED" : "FLAT")));
            m_diag_last_reason = "DPI_DECEL";
            m_reject_filter++;
            m_stats.rejected_dpi_decel++;
            if(!full_eval) {
               m_ts_status_string = StringFormat("B[%s] | I[%s] | F[%s]", m_eval_str_B, m_eval_str_I, m_eval_str_F);
               UpdateTelemetry(0);
               FlushOrClearDebugBuffer(0);
               RestoreForcedDebug();
               return 0;
            }
            if(m_eval_first_failure == "") m_eval_first_failure = "DPI_DECEL";
            m_eval_any_failure = true;
         }
      }

      // ══════════════════════════════════════════════════════════════════
      // PRE-FILTER (PHASE A.1): Phase-age confirmation
      // Reject when MinPhaseConfirmBars > 0 and the current phase has not
      // persisted for at least that many bars. Catches single-bar TM
      // flickers (Pattern D in 100-trades analysis).
      // ══════════════════════════════════════════════════════════════════
      if(m_settings.MinPhaseConfirmBars > 0 &&
         m_diag_phase_confirm_bars < m_settings.MinPhaseConfirmBars)
      {
         if(m_settings.DebugFlow)
            PrintFormat("[TS_PREFILTER] PHASE_AGE: bars=%d < required=%d → TS=0",
                        m_diag_phase_confirm_bars, m_settings.MinPhaseConfirmBars);
         m_diag_last_reason = "PHASE_AGE";
         m_reject_filter++;
         m_stats.rejected_phase_age++;
         if(!full_eval) {
            m_ts_status_string = StringFormat("B[%s] | I[%s] | F[%s]", m_eval_str_B, m_eval_str_I, m_eval_str_F);
            UpdateTelemetry(0);
            FlushOrClearDebugBuffer(0);
            RestoreForcedDebug();
            return 0;
         }
         if(m_eval_first_failure == "") m_eval_first_failure = "PHASE_AGE";
         m_eval_any_failure = true;
      }

      // ── PHASE A.1: Increment passed_* counters for active gates that survived ──
      // We only increment when the gate was actually evaluated (enable flag on)
      // so the Pass% column reflects accuracy among bars where the gate fired.
      if(m_settings.EmaFanFilterEnabled && m_settings.EmaFanMaxTotalPips > 0.0)
         m_stats.passed_emafan++;
      if((m_settings.DpiDecelFilterEnabled && m_settings.Ind_Dpi_Enabled) ||
         (m_settings.DPI_BlockOnDeceleration && m_settings.DPI_HistTrackingEnabled))
         m_stats.passed_dpi_decel++;
      if(m_settings.MinPhaseConfirmBars > 0)
         m_stats.passed_phase_age++;

      if(m_settings.BiasMode == BIAS_4EMA)
         UpdateLayerPullbackStates(v_shift);

      // ── L: Layer ─────────────────────────────────────────────────
      int L = EvaluateL(v_shift, B);
      if(L == 0 && !full_eval) {
         m_ts_status_string = StringFormat("B[%s] | I[%s] | F[%s]", m_eval_str_B, m_eval_str_I, m_eval_str_F);
         UpdateTelemetry(0);
         FlushOrClearDebugBuffer(0);
         RestoreForcedDebug();
         return 0;
      }
      // ── I: Indicators ─────────────────────────────────────────────
      int I = EvaluateI(v_shift, B);

      // ════════════════════════════════════════════════════════════
      // FINAL DECISION: TS = B × P × L × I
      // ════════════════════════════════════════════════════════════
      int final_signal = 0;

      if(m_eval_any_failure) {
         // Stats_FullEvaluation mode: accumulated failure from B, P, or L
         if(m_diag_last_reason == "") m_diag_last_reason = m_eval_first_failure;
         if(m_settings.DebugFlow) DebugLog(StringFormat("[RESULT] TS=0 REJECT (%s)", m_diag_last_reason));
      }
      else if(I == 0) {
         // Indicator voting failed (reason already set by EvaluateI/EvaluateIndicatorX)
         if(m_settings.DebugFlow) DebugLog(StringFormat("[RESULT] TS=0 REJECT (%s)", m_diag_last_reason));
      }
      else {
         // All factors passed → signal confirmed
         // TS = 1 (confirmed) or 0 (rejected). Direction is in m_diag_last_bias (+1/-1).
         final_signal = 1;
         // Note: m_diag_last_bias was already set by EvaluateB; update for consistency
         m_diag_last_bias = B;
         m_ts_status_string = StringFormat("B[%s] | P[%s] | L[L%d] | I[OK]",
                                            (B > 0 ? "L" : (B < 0 ? "S" : "0")),
                                            EnumToString(m_diag_last_phase),
                                            m_last_layer);
         if(m_settings.DebugFlow && final_signal != 0)
            DebugLog(StringFormat("[RESULT] TS=%d (Votes: %.2f)", final_signal, m_eval_vote_weight));
      }

      // Ensure UI vote counter is up-to-date
      // In VOTE_MODE_ALL, m_diag_last_votes is already set to indicator pass count.
      // In VOTE_MODE_THRESHOLD, fall back to rounded vote_weight if count is unavailable.
      if(m_settings.VoteMode == VOTE_MODE_THRESHOLD && m_eval_vote_weight > 0 && m_diag_last_votes == 0)
         m_diag_last_votes = (int)MathRound(m_eval_vote_weight);

      // ===== TS PIPELINE SUMMARY =====
      if(m_settings.DebugLevel >= DEBUG_INDICATORS) {
         datetime sum_bar_time = iTime(m_symbol, PERIOD_CURRENT, m_settings.ma_v_shift);
         DebugLog("════════════════════════════════════════════════════════════");
         DebugLog(StringFormat("[TS_SUMMARY] Bar: %s (shift=%d)",
                               TimeToString(sum_bar_time, TIME_DATE|TIME_MINUTES),
                               m_settings.ma_v_shift));
         DebugLog("════════════════════════════════════════════════════════════");
         DebugLog("");

         // F (FILTERS) NOTE — evaluated at TE (bar open), not at TS (bar close)
         DebugLog("F (FILTERS) — spread/time/news evaluated at TE, MTF evaluated at TS:");
         DebugLog("  ⏭️  Spread: checked at TE (" + (m_settings.UseSpread ? "enabled" : "disabled") + ")");
         DebugLog("  ⏭️  Time window: checked at TE (" + (m_settings.UseTime ? "active" : "disabled") + ")");
         DebugLog("  ⏭️  News filter: checked at TE (" + (m_settings.UseNews ? "active" : "disabled") + ")");
         DebugLog("  ✅ MTF filter: checked at TS (" + (m_settings.Ind_MTF_Enabled ? "enabled" : "disabled") + ")");
         DebugLog("");

         // BIAS & STRUCTURE SECTION
         DebugLog("BIAS & STRUCTURE:");
         if(B == 0) {
            DebugLog(StringFormat("  ❌ Bias (B): NEUTRAL (%s)", m_diag_last_reason));
         } else {
            DebugLog(StringFormat("  ✅ Bias (B): %s (EMAs aligned)", B > 0 ? "LONG" : "SHORT"));
         }
         if(m_settings.PhaseDetectionEnabled) {
            string phase_str = EnumToString(m_diag_last_phase);
            bool is_emerging_phase = (m_diag_last_phase == PHASE_EMERGING_UP ||
                                      m_diag_last_phase == PHASE_EMERGING_DN ||
                                      m_diag_last_phase == PHASE_EMERGING);
            bool phase_blocked = (m_diag_last_phase == PHASE_UNORDERED && m_settings.BlockUnorderedPhase) ||
                                 (is_emerging_phase && m_settings.BlockEmergingPhase);
            DebugLog(StringFormat("  %s Phase (P): %s%s",
                                  phase_blocked ? "❌" : "✅", phase_str,
                                  phase_blocked ? " (blocked)" : ""));
         } else {
            DebugLog("  ⏭️  Phase (P): disabled");
         }
         if(m_settings.EnableLayerDetection && m_settings.BiasMode == BIAS_4EMA) {
            DebugLog(StringFormat("  %s Layer (L): W=%d M=%d S=%d → active=L%d",
                                  (L == 1) ? "✅" : "❌",
                                  m_diag_layer_w, m_diag_layer_m, m_diag_layer_s, m_last_layer));
         } else {
            DebugLog("  └  Layer (L): disabled (non-4EMA mode)");
         }
         DebugLog("");

         // INDICATORS SECTION
         int s_enabled=0, s_disabled=0, s_passed=0;
         if(m_settings.Ind_Adx_Enabled)         s_enabled++; else s_disabled++;
         if(m_settings.Ind_Macd_Enabled)        s_enabled++; else s_disabled++;
         if(m_settings.Ind_Rsi_Enabled)         s_enabled++; else s_disabled++;
         if(m_settings.Ind_Cci_Enabled)         s_enabled++; else s_disabled++;
         if(m_settings.Ind_Mfi_Enabled)         s_enabled++; else s_disabled++;
         if(m_settings.Ind_Sto_Enabled)         s_enabled++; else s_disabled++;
         if(m_settings.Ind_Bb_Enabled)          s_enabled++; else s_disabled++;
         if(m_settings.Ind_Psar_Enabled)        s_enabled++; else s_disabled++;
         if(m_settings.Ind_P123_Enabled)        s_enabled++; else s_disabled++;
         if(m_settings.Ind_Ross_Enabled)        s_enabled++; else s_disabled++;
         if(m_settings.Ind_Atr_Enabled)         s_enabled++; else s_disabled++;
         if(m_settings.Ind_CandleBody_Enabled)  s_enabled++; else s_disabled++;
         if(m_settings.Ind_CI_Enabled)          s_enabled++; else s_disabled++;
         if(m_settings.Ind_VRC_Enabled)         s_enabled++; else s_disabled++;
         if(m_settings.Ind_SmaConverge_Enabled) s_enabled++; else s_disabled++;
         if(m_settings.Ind_Dpi_Enabled)         s_enabled++; else s_disabled++;
         if(m_settings.Ind_Fib_Enabled)         s_enabled++; else s_disabled++;

         DebugLog(StringFormat("INDICATORS (%d enabled, %d disabled):", s_enabled, s_disabled));

         string saved_reason = m_diag_last_reason;

         if(m_settings.Ind_Adx_Enabled) {
            DebugLog(StringFormat("  %s ADX", m_eval_ind_res_adx ? "✅" : "❌"));
            if(m_eval_ind_res_adx) s_passed++;
         } else DebugLog("  ⏭️  ADX: disabled");

         if(m_settings.Ind_Macd_Enabled) {
            DebugLog(StringFormat("  %s MACD", m_eval_ind_res_macd ? "✅" : "❌"));
            if(m_eval_ind_res_macd) s_passed++;
         } else DebugLog("  ⏭️  MACD: disabled");

         if(m_settings.Ind_Rsi_Enabled) {
            DebugLog(StringFormat("  %s RSI", m_eval_ind_res_rsi ? "✅" : "❌"));
            if(m_eval_ind_res_rsi) s_passed++;
         } else DebugLog("  ⏭️  RSI: disabled");

         if(m_settings.Ind_Cci_Enabled) {
            DebugLog(StringFormat("  %s CCI", m_eval_ind_res_cci ? "✅" : "❌"));
            if(m_eval_ind_res_cci) s_passed++;
         } else DebugLog("  ⏭️  CCI: disabled");

         if(m_settings.Ind_Mfi_Enabled) {
            DebugLog(StringFormat("  %s MFI", m_eval_ind_res_mfi ? "✅" : "❌"));
            if(m_eval_ind_res_mfi) s_passed++;
         } else DebugLog("  ⏭️  MFI: disabled");

         if(m_settings.Ind_Sto_Enabled) {
            DebugLog(StringFormat("  %s Stochastic", m_eval_ind_res_sto ? "✅" : "❌"));
            if(m_eval_ind_res_sto) s_passed++;
         } else DebugLog("  ⏭️  Stochastic: disabled");

         if(m_settings.Ind_Bb_Enabled) {
            DebugLog(StringFormat("  %s Bollinger Bands", m_eval_ind_res_bb ? "✅" : "❌"));
            if(m_eval_ind_res_bb) s_passed++;
         } else DebugLog("  ⏭️  Bollinger Bands: disabled");

         if(m_settings.Ind_Psar_Enabled) {
            string psar_mode = !m_settings.Vote_AllowPsarFlip ? "DOT" : (m_settings.Vote_PsarFlipDelay == -1) ? "PERSISTENT" : "FLIP";
            DebugLog(StringFormat("  %s PSAR (%s mode)", m_eval_ind_res_psar ? "✅" : "❌", psar_mode));
            if(m_eval_ind_res_psar) s_passed++;
         } else DebugLog("  ⏭️  PSAR: disabled");

         if(m_settings.Ind_P123_Enabled) {
            DebugLog(StringFormat("  %s Pattern 1-2-3", m_eval_ind_res_p123 ? "✅" : "❌"));
            if(m_eval_ind_res_p123) s_passed++;
         } else DebugLog("  ⏭️  Pattern 1-2-3: disabled");

         if(m_settings.Ind_Ross_Enabled) {
            DebugLog(StringFormat("  %s Ross Hook", m_eval_ind_res_ross ? "✅" : "❌"));
            if(m_eval_ind_res_ross) s_passed++;
         } else DebugLog("  ⏭️  Ross Hook: disabled");

         if(m_settings.Ind_SmaConverge_Enabled) {
            DebugLog(StringFormat("  %s SMA Convergence", m_eval_ind_res_sma_converge ? "✅" : "❌"));
            if(m_eval_ind_res_sma_converge) s_passed++;
         } else DebugLog("  ⏭️  SMA Convergence: disabled");

         if(m_settings.Ind_Dpi_Enabled) {
            DebugLog(StringFormat("  %s DPI", m_eval_ind_res_dpi ? "✅" : "❌"));
            if(m_eval_ind_res_dpi) s_passed++;
         } else DebugLog("  ⏭️  DPI: disabled");

         if(m_settings.Ind_Fib_Enabled) {
            DebugLog(StringFormat("  %s Fibonacci", m_eval_ind_res_fib ? "✅" : "❌"));
            if(m_eval_ind_res_fib) s_passed++;
         } else DebugLog("  ⏭️  Fibonacci: disabled");

         if(m_settings.Ind_Atr_Enabled) {
            DebugLog(StringFormat("  %s ATR (volatility filter)", m_eval_ind_res_atr ? "✅" : "❌"));
            if(m_eval_ind_res_atr) s_passed++;
         } else DebugLog("  ⏭️  ATR: disabled");

         if(m_settings.Ind_CandleBody_Enabled) {
            DebugLog(StringFormat("  %s CandleBody (spike filter)", m_eval_ind_res_candle_body ? "✅" : "❌"));
            if(m_eval_ind_res_candle_body) s_passed++;
         } else DebugLog("  ⏭️  CandleBody: disabled");

         if(m_settings.Ind_CI_Enabled) {
            DebugLog(StringFormat("  %s Choppiness Index", m_eval_ind_res_ci ? "✅" : "❌"));
            if(m_eval_ind_res_ci) s_passed++;
         } else DebugLog("  ⏭️  Choppiness Index: disabled");

         if(m_settings.Ind_VRC_Enabled) {
            DebugLog(StringFormat("  %s VRC (volatility regime)", m_eval_ind_res_vrc ? "✅" : "❌"));
            if(m_eval_ind_res_vrc) s_passed++;
         } else DebugLog("  ⏭️  VRC: disabled");

         DebugLog("");

         // VOTING SUMMARY
         if(s_enabled > 0) {
            double pass_pct = (double)s_passed / s_enabled * 100.0;
            DebugLog(StringFormat("VOTING: %d/%d passed (%.1f%%) - requires %s",
                                  s_passed, s_enabled, pass_pct,
                                  m_settings.VoteMode == VOTE_MODE_ALL ? "ALL (100%)" : "THRESHOLD"));
         }
         DebugLog("");

         // FINAL RESULT
         DebugLog("════════════════════════════════════════════════════════════");
         if(final_signal == 0) {
            DebugLog(StringFormat("[TS_RESULT] ❌ REJECTED - Reason: %s", saved_reason));
         } else {
            DebugLog(StringFormat("[TS_RESULT] ✅✅✅ SIGNAL CONFIRMED: %s ✅✅✅",
                                  final_signal > 0 ? "LONG" : "SHORT"));
         }
         DebugLog("════════════════════════════════════════════════════════════");
         DebugLog("");
      }
      // ===== TS PIPELINE SUMMARY: END =====

      // DEBUG_SUMMARY: 1-2 line per-bar result
      if(m_settings.DebugLevel >= DEBUG_SUMMARY) {
         datetime sum_bar_time = iTime(m_symbol, PERIOD_CURRENT, m_settings.ma_v_shift);
         if(final_signal != 0)
            DebugLog(StringFormat("%s: %s CONFIRMED [%s]",
                                  TimeToString(sum_bar_time, TIME_DATE|TIME_MINUTES),
                                  final_signal > 0 ? "LONG" : "SHORT", m_ts_status_string));
         else
            DebugLog(StringFormat("%s: REJECTED (%s) [%s]",
                                  TimeToString(sum_bar_time, TIME_DATE|TIME_MINUTES),
                                  m_diag_last_reason, m_ts_status_string));
      }

      // ═══════════════════════════════════════════════════════════════
      // TELEMETRY INJECTION (B|I|F Construction)
      // ═══════════════════════════════════════════════════════════════

      // 1. Filter Interrogation
      if(m_diag_last_reason == "TIME" || m_diag_last_reason == "NEWS" || m_diag_last_reason == "SPREAD") {
         m_eval_str_F = m_diag_last_reason;
      }

      // 2. Bias Interrogation
      if(B != 0) {
         m_eval_str_B = "+";
      } else {
         double f_val = GetMAVal(BiasFastHandle(), v_shift);
         double s_val = GetMAVal(BiasSlowHandle(), v_shift);
         int f_slope = GetSlope(BiasFastHandle(), v_shift);

         if(m_diag_last_reason == "PHASE_UNORDERED" || m_diag_last_reason == "PHASE") m_eval_str_B = "PHASE";
         else if((f_val > s_val && f_slope <= 0) || (f_val < s_val && f_slope >= 0)) m_eval_str_B = "SLOPE";
         else m_eval_str_B = "POS";
      }

      // 3. Indicator Interrogation
      int total_enabled = CountEnabledIndicators();
      m_eval_str_I = StringFormat("%d/%d", m_diag_last_votes, total_enabled);

      // 4. Final String Assembly
      m_ts_status_str = StringFormat("B[%s] | I[%s] | F[%s]", m_eval_str_B, m_eval_str_I, m_eval_str_F);

      // 5. Populate Final UI Telemetry Snapshot
      m_telemetry.bias = m_diag_last_bias;  // Direction (+1/-1), not TS result (1/0)
      m_telemetry.phase = (int)m_diag_last_phase;
      m_telemetry.layer = (int)m_diag_layer_w | (m_diag_layer_m << 1) | (m_diag_layer_s << 2);
      m_telemetry.votes_for = m_diag_last_votes;
      m_telemetry.votes_total = total_enabled;

      if(final_signal != 0) {
         m_telemetry.rejection_reason = "Valid Signal";
      } else {
         if(m_eval_str_F != "OK") {
            m_telemetry.rejection_reason = "TE: " + m_eval_str_F + " Check Failed";
         } else {
            m_telemetry.rejection_reason = "TS: " + (m_diag_last_reason != "" ? m_diag_last_reason : "Unknown Mismatch");
         }
      }

      // --- AUDITED TERMINATION ---
      // Pass the raw bias (not the final filtered signal) so the UI shows
      // BIAS: LONG [+] even when the pipeline rejected on indicators/gates.
      // The rejection_reason already explains WHY the signal was blocked.
      UpdateTelemetry(m_diag_last_bias);
      FlushOrClearDebugBuffer(final_signal);
      RestoreForcedDebug();
      return final_signal;
   } // === EvaluateTS: END ===


   int BiasFastHandle() {
      return (m_settings.BiasFastID==0)?h_ema1 : (m_settings.BiasFastID==1)?h_ema2 : (m_settings.BiasFastID==2)?h_ema3 : h_ema4; }

   int BiasSlowHandle() {
      return (m_settings.BiasSlowID==0)?h_ema1 : (m_settings.BiasSlowID==1)?h_ema2 : (m_settings.BiasSlowID==2)?h_ema3 : h_ema4; }

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
   //| Phase-Based Bias Calculation                        |
   //| Uses market phase detection to determine trading bias           |
   //| Requires PhaseDetectionEnabled = true                           |
   //+------------------------------------------------------------------+
   int GetBias_PhaseBased(const int v_shift = 1)
   {
      // Validate that phase detection is enabled
      if(!m_settings.PhaseDetectionEnabled)
      {
         if(m_settings.DebugFlow)
            Print("[260304_BIAS] ERROR: BIAS_4EMA selected but PhaseDetectionEnabled=false");
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
      
      // Block EMERGING phase if configured
      bool is_emerging = (current_phase == PHASE_EMERGING_UP ||
                          current_phase == PHASE_EMERGING_DN ||
                          current_phase == PHASE_EMERGING);
      if(is_emerging && m_settings.BlockEmergingPhase)
      {
         if(m_settings.DebugFlow)
            Print("[260304_BIAS] EMERGING phase blocked - trend forming but not yet confirmed");
         return 0;  // No bias until trend is confirmed TRENDING
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
   //| Detect Market Phase by pure EMA2/EMA3/EMA4 positional check    |
   //| EMA1 is ignored entirely. No slopes. No voting.                 |
   //|                                                                  |
   //| TM (Trending):                                                   |
   //|   Bullish: EMA2 > EMA3 > EMA4  (ascending stack)               |
   //|   Bearish: EMA4 > EMA3 > EMA2  (descending stack)              |
   //| EM (Emerging — EMA4 sandwiched):                                |
   //|   Bullish: EMA2 > EMA4 > EMA3                                   |
   //|   Bearish: EMA3 > EMA4 > EMA2                                   |
   //| UNO (Unordered — EMA2 sandwiched or other): NO TRADE           |
   //+------------------------------------------------------------------+
   EMarketPhase DetectMarketPhase(const int shift = 1)
   {
      double ema2 = GetMAVal(h_ema2, shift, 0);
      double ema3 = GetMAVal(h_ema3, shift, 0);
      double ema4 = GetMAVal(h_ema4, shift, 0);
      
      if(ema2 == EMPTY_VALUE || ema3 == EMPTY_VALUE || ema4 == EMPTY_VALUE)
         return PHASE_UNORDERED;
      
      // TM: perfect ascending/descending stack
      if(ema2 > ema3 && ema3 > ema4) return PHASE_TRENDING_UP;
      if(ema4 > ema3 && ema3 > ema2) return PHASE_TRENDING_DN;
      
      // EM: EMA4 (slowest) sandwiched between EMA2 and EMA3
      if(ema2 > ema4 && ema4 > ema3) return PHASE_EMERGING_UP;
      if(ema3 > ema4 && ema4 > ema2) return PHASE_EMERGING_DN;
      
      // UNO: EMA2 sandwiched or any other arrangement
      return PHASE_UNORDERED;
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

};

//+--END OF SEA_SignalEngine.mqh--+
