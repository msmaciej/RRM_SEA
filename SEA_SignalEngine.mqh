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
#ifndef SEA_BUILD_TOKEN_105001
enum { __SEA_BUILD_TOKEN_MISSING_SIGNALENGINE_105001 = SEA_BUILD_TOKEN_105001 };
#endif

#define SEA_MOD_SIGNALENGINE_105001 1
#define SEA_LAYER_SLOPE_EPSILON 0.00000001
#define SEA_MIN_WEEKEND_GAP_SECONDS (2 * 24 * 60 * 60)
#define SEA_WEEKEND_GAP_SCAN_BUFFER_BARS 8
#define SEA_DOW_SUNDAY 0
#define SEA_DOW_MONDAY 1
#define SEA_DOW_FRIDAY 5
#define SEA_DOW_SATURDAY 6


#include <RRMS\SEA_Config.mqh>


// Note: Requires ST_Settings and SNewsEvent structs to be defined in main file

//+------------------------------------------------------------------+
//| SRibbonSnapshot — single source of truth for ribbon EMA values   |
//+------------------------------------------------------------------+
// Refreshed once per evaluation pass via RefreshRibbonSnapshot(shift).
// Every downstream consumer (cockpit, phase, layers, fan, trail, bias)
// reads through accessors GetEma1()..GetEma4() and IsRibbonValid().
//
// Slot identity is preserved across the engine: [0] = slot 1 = h_ema1
// (period m_settings.P_Ema1), [1] = slot 2 = h_ema2, etc. Periods are
// configurable inputs — they are NEVER hardcoded as field names.
//
// The snapshot covers TWO shifts: the current evaluation shift, and the
// previous bar (shift+1). Two-shift consumers (fan filter, S-layer
// alignment, sma convergence) read prev[] fields. Single-shift consumers
// (phase, bias, layer detection) read the unsuffixed fields.
//
// Provenance: each slot records which tier produced its value:
//   "iMA"  — MT5 indicator buffer via CopyBuffer succeeded (normal)
//   "MAN"  — CopyBuffer failed, computed manually from raw closes
//   "ERR"  — both tiers failed; valid[i] = false; consumer must skip
struct SRibbonSnapshot {
   // Current bar (shift = m_ribbon.shift)
   double   ema[4];          // slot-indexed EMA values
   bool     valid[4];        // per-slot validity
   string   src[4];          // per-slot provenance ("iMA" / "MAN" / "ERR")
   // Previous bar (shift = m_ribbon.shift + 1)
   double   ema_prev[4];
   bool     valid_prev[4];
   string   src_prev[4];
   // Metadata
   datetime bar;             // closed-bar timestamp these values belong to
   int      shift;           // the shift the snapshot was taken at
   bool     all_valid;       // current bar: all four slots usable
   bool     all_valid_prev;  // previous bar: all four slots usable
};

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
   bool   vprr_enabled;             // VPRR voter active
   double vprr_ratio;               // Active-layer VPRR ratio (recovery_vol / pullback_vol)
   double vprr_min_ratio;           // Configured pass threshold
   bool   vprr_pass;                // Whether the active-layer ratio passed
   string vprr_vol_source;          // "REAL" or "TICK" — which volume feed is in use
   // A14/A20 2026-07: I-factor suppression flag (display I[?] instead of I[+/-])
   // True when L failed for a structural reason (no layer aligned = L_NONE_ALIGNED),
   // meaning the I factor was never evaluated — showing I[-] would be misleading.
   // UI uses this to display "?" in the TS equation and "--/N [L-blocked]" in VOTE.
   bool   i_suppressed;             // true = I not evaluated (L structurally blocked)
   // ── Ribbon EMA snapshot (single source of truth, slot-indexed) ──
   // Mirrors m_ribbon at the end of each EvaluateTS pass. Cockpit reads from
   // this for display. Periods are NOT hardcoded — labels are rendered from
   // m_settings.P_Ema1..4 at display time.
   SRibbonSnapshot ribbon;
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
   int passed_vprr,         rejected_vprr;

   // ── PHASE A.1: Pre-filter quality gates (TS=1 hardening) ──────────────
   int passed_emafan,     rejected_emafan;     // EMA fan overextension
   int passed_dpi_decel,  rejected_dpi_decel;  // DPI histogram deceleration
   int exits_dpi_hist;                          // Trades closed by DPI histogram exit
   int passed_phase_age,  rejected_phase_age;  // MinPhaseConfirmBars not met
   int passed_htf_align,  rejected_htf_align;  // Legacy field retained for compatibility
   int passed_mtf,        rejected_mtf;        // MTF global filter statistics
   // F-AUDIT 2026-06: previously rolled into m_reject_filter only; now have
   // their own stats for the per-gate report.
   int passed_priceext,   rejected_priceext;   // Price over-extension (ATR units)
   int passed_climax,     rejected_climax;     // Climax / exhaustion guard (merged into F)

   // ── PHASE A.1: TE-side gates (incremented from SEA_TradeExecutor via AddTeStats) ──
   int passed_te_open_delay,    rejected_te_open_delay;
   int passed_te_bc_recheck,    rejected_te_bc_recheck;
   int passed_te_spread_median, rejected_te_spread_median;

   int signals_confirmed;
   int signals_confirmed_long, signals_confirmed_short;
};

//+------------------------------------------------------------------+
//| Per-factor breakdown of the shared TS decision core (P*F*L*I+CG). |
//| Filled by CSignalEngine::EvaluateTS_Breakdown. 1=pass, 0=fail,    |
//| -1=not-evaluated (waterfall short-circuit). bias (B) is the input.|
//+------------------------------------------------------------------+
struct STSBreakdown
{
   int    P;          // phase
   string P_reason;   // why P==0 (PHASE_UNORDERED / PHASE_EMERGING)
   int    F;          // pre-filters (1/0)
   string F_reason;   // sub-filter that blocked when F==0
   int    L;          // layer
   string L_reason;   // why L==0 (L_NONE_ALIGNED / L_BC_FAIL / L_BD_FAIL / L_MOMENTUM_FAIL / L_S_NOT_DIR_ALIGNED / L_S_BLOCK_EM)
   int    L_layer;    // winning layer when L==1 (1=W, 2=M, 3=S; 0=none)
   int    I;          // indicators (normalized 1/0)
   string I_reason;   // failing voter names when I==0 (e.g. "DPI,PSAR")
   int    CG;         // climax guard: 1=pass, 0=climax veto
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
   string      m_diag_i_fails;        // compact failing-voter names for I (inspector), e.g. "DPI,PSAR"
   string      m_last_f_reason;      // which F sub-filter blocked (caller telemetry); "" = passed
   // STEP7 2026-06: m_diag_last_atr_pips field removed — was always 0.0 (latent bug).
   // All reads now call AtrPips() directly (see Check_ATR + cockpit panel + DebugFlow log).
   
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
    // --- 2c.1b PHASE-CHANGE REALIGN RESET (optional) ---
    EMarketPhase m_phase_reset_pending;   // raw phase currently being debounced
    EMarketPhase m_phase_reset_confirmed; // last phase that triggered a realign reset
    int          m_phase_reset_count;     // consecutive bars the pending phase has held
    // --- 2c.1b.2 UNO-EXIT COOLDOWN (Theme 2026-06, optional) ---
    // Counts consecutive non-UNO bars since the last UNO bar. Used by
    // UpdateSingleLayerPullback to BLOCK the DETECTED→RECOVERED transition until
    // m_settings.MinBarsAfterUNOExit bars have accumulated. Reset to 0 on every
    // UNO bar (the B==0 branch of the per-bar dispatch in EvaluateTS). Incremented
    // on every non-UNO bar (B != 0 branch). Only meaningful in BIAS_4EMA mode.
    // Sentinel large value at constructor + Reset so the very first bar always
    // satisfies any user-configured minimum (no first-load false trigger).
    int          m_bars_since_uno_exit;
    // Consecutive UNO (B==0) bars seen so far in the current UNO run. Used with
    // m_settings.UNO_ToleranceBars: a transient UNO flicker that resolves back to
    // the SAME direction within tolerance PRESERVES layer states (does not wipe
    // DETECTED/RECOVERED). Reset to 0 on every non-UNO bar.
    int          m_uno_run;
    // --- 2c.1c CANDLEBODY OVER-EXTENSION CARRY (CBOEB, optional) ---
    bool         m_cb_oeb_blocked;        // CBOEB=0: hold CB vote at 0 (over-extension carry active)
    bool         m_cb_prev_any_rec;       // prev-bar 'any layer recovered' (fresh-recovery edge)
    // --- 2c.1d DIRECTIONAL STATE SYMMETRY (long/short parity) ---
    // Tracks the bias direction under which the per-direction state
    // machines (layer pullback, DPI CCI reset, CB OEB) were last advanced.
    // When the bias seen by UpdateLayerPullbackStates differs from this
    // value (including LONG↔SHORT flips and transitions through neutral),
    // ResetDirectionalState() is called so the new direction starts from
    // a clean baseline — architectural equivalent of SignalScan's
    // two-engine isolation in our single-engine model.
    // Sentinel 999 = uninitialized → forces a clean reset on the first
    // real bar regardless of which direction it carries.
    int          m_last_dir_state_bias;
    // --- 2c.2 VPRR VOLUME TRACKING (per layer) ---
    double   m_layer_w_vol_pb_avg, m_layer_m_vol_pb_avg, m_layer_s_vol_pb_avg;     // Running avg pullback volume
    int      m_layer_w_vol_pb_bars, m_layer_m_vol_pb_bars, m_layer_s_vol_pb_bars;  // Bars counted in DETECTED
    double   m_layer_w_vol_rec_avg, m_layer_m_vol_rec_avg, m_layer_s_vol_rec_avg;  // Running avg recovery volume
    int      m_layer_w_vol_rec_bars, m_layer_m_vol_rec_bars, m_layer_s_vol_rec_bars; // Bars counted in RECOVERED
    double   m_layer_w_vprr, m_layer_m_vprr, m_layer_s_vprr;                       // Final ratios
    bool     m_vprr_last_real;   // True if the last volume read used VOLUME_REAL (for UI source label)
    // A21 2026-07: bars spent in DETECTED state per layer (for MinPullbackBars gate)
    int      m_layer_w_bars_det, m_layer_m_bars_det, m_layer_s_bars_det;
    // Path 2 2026-07: bars spent in RECOVERED state per layer (for the recovery
    // max-age cap). Self-managed inside UpdateSingleLayerPullback (incremented
    // while RECOVERED, zeroed otherwise) — needs no external reset.
    int      m_layer_w_bars_rec, m_layer_m_bars_rec, m_layer_s_bars_rec;
    // ── GUARD 1 (2026-07): first-post-flip pullback-recovery skip ──────────────
    // Counts COMPLETED pullback-recovery CYCLES per layer since the last genuine
    // signed bias flip. The unit is the cycle, not the RECOVERED transition: a
    // relapse (RECOVERED→DETECTED→RECOVERED, which never passes through NONE) is the
    // SAME cycle re-completing and must NOT increment, or the guard would defeat
    // itself in exactly the choppy market it targets. m_layer_*_g1_counted is the
    // "this cycle already counted" latch; it is cleared at the single NONE→DETECTED
    // transition — the only exit from NONE — so every external reset-to-NONE path
    // (TS=1 consumption, max-age, cross, phase-clear, climax, sustained-UNO) clears it
    // for free, exactly as bars_rec self-manages.
    int      m_layer_w_g1_recov,   m_layer_m_g1_recov,   m_layer_s_g1_recov;
    bool     m_layer_w_g1_counted, m_layer_m_g1_counted, m_layer_s_g1_counted;
    // Armed only by a GENUINE ±1→∓1 flip. The 999 sentinel (cold start / warm-up
    // hand-off) must NOT arm it, or the EA would skip its first pullback-recovery
    // after every load, recompile and optimisation pass — silently corrupting any A/B.
    bool     m_g1_armed;
    // Set by CheckLayerPairAlign when GUARD 1 (and not the P-R gate) rejected a layer,
    // so EvaluateL / the inspector can report L_G1_POSTFLIP instead of the misleading
    // L_NONE_ALIGNED. Cleared once per bar alongside m_eval_layer_*.
    bool     m_eval_g1_blocked;
    bool     m_vprr_real_warned; // One-shot guard: have we already warned the user that VPRR_VOL_REAL is
                                 // selected but the broker returned zero real volume? Without this, VPRR
                                 // votes silently fail every bar because GetCurrentBarVolume returns 0 →
                                 // ratio = 0 < VPRR_MinRatio. The warning fires once on the first such
                                 // miss so the user can switch to AUTO or TICK rather than wondering why
                                 // VPRR never passes.

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

   // --- 2e-bis. RIBBON SNAPSHOT (single source of truth for EMA values) ---
   // Refreshed at the top of every EvaluateTS pass via RefreshRibbonSnapshot.
   // All ribbon reads in the engine go through accessors GetEma1..4() that
   // read this snapshot — no direct GetMAVal(h_ema*) calls outside the
   // refresh function itself.
   SRibbonSnapshot m_ribbon;
   
   // --- 2f. PSAR FLIP TRACKING ---
   datetime m_psar_last_flip_time_bull;  // Timestamp of last bullish flip (0 = none recorded)
   datetime m_psar_last_flip_time_bear;  // Timestamp of last bearish flip (0 = none recorded)
   datetime m_psar_health_last_log;      // BUGFIX A2: replaces static local in DetectPSARFlipAt (no-static-locals constraint)

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
   int      m_eval_layer_w;  // LayerW positional alignment result (0/1) — set by EvaluateL
   int      m_eval_layer_m;  // LayerM positional alignment result (0/1) — set by EvaluateL
   int      m_eval_layer_s;  // LayerS positional alignment result (0/1) — set by EvaluateL
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

   // CCI Reset-Recovery state machine
   // Tracks the cycle: CCI agrees → CCI resets (flips) → CCI recovers → entry allowed
   //   0 = IDLE:               CCI agrees with hist. Waiting for a reset.
   //   1 = RESET_DETECTED:     CCI flipped against hist (ribbon color changed). Pullback.
   //   2 = RECOVERY_COUNTING:  CCI flipped back. Counting recovery bars.
   //   3 = ENTRY_ALLOWED:      Recovery confirmed for N bars. Entry gate open.
   int      m_dpi_reset_state;           // Current state (0-3)
   int      m_dpi_reset_recovery_bars;   // Bars counted since CCI recovered
   bool     m_dpi_reset_colour_prev;     // Previous bar's ribbon colour (true=yellow) — flip detection
   bool     m_dpi_reset_colour_ref;      // Trend colour to recover to (true=yellow), frozen at reset
   bool     m_dpi_reset_initialized;     // False until colour_prev has been seeded by a real observation.
                                         // Prevents a spurious IDLE→RESET_DETECTED transition on the first
                                         // call (or first call after a bias-flip reset) caused by the init
                                         // default colour_prev=false disagreeing with whatever the live
                                         // ribbon colour happens to be. Without this guard, opening on a
                                         // yellow uptrend would lock the gate at colour_ref=red — never
                                         // reachable — and block every entry for the entire session.
   bool     m_dpi_first_entry_consumed;  // Session-once flag for DPI_GrantFirstEntry. Starts false on EA load
                                         // (member default in class constructor). Set true by
                                         // ResetDPIResetState() — which is called immediately after a
                                         // successful trade execution — so the first-entry grant fires at
                                         // most once per session. Intentionally NOT cleared by Init() /
                                         // ResetDirectionalState() / warmup resets, so internal resets
                                         // (bias flip, etc.) cannot re-grant. Only a full EA reload clears
                                         // it (which is correct — that's effectively a new session).

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
      double dpi_diag_hist;       // last DPI histogram value (inspector diagnostic)
      int    dpi_diag_sub;        // last DPI fail sub-reason: 0=none 1=DIR(colour) 3=GREEN 4=RESET
      bool   dpi_diag_yellow;     // last DPI ribbon colour: true=YELLOW (long), false=RED (short)
      int    psar_diag_sub;       // last PSAR fail sub-reason: 0=none/dot 1=NoFlip 3=Valid(pass) 4=Expired
                                  // NOTE: 2 is intentionally unused, mirroring dpi_diag_sub's value scheme.
                                  // Readers map: 1→NoF, 4→EXP, else→DOT. Was previously documented as 0/1/2
                                  // (and reader mapped 2→EXP) but setters never wrote 2 — expired rejects
                                  // were silently mislabeled DOT in journal output until 2026-06 fix.
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
      m_ind_cache.dpi_diag_hist = 0.0;
      m_ind_cache.dpi_diag_sub  = 0;
      m_ind_cache.dpi_diag_yellow = false;
      m_ind_cache.psar_diag_sub = 0;
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

   //+------------------------------------------------------------------+
   // IndReadOK — validity-checked single-buffer read for VOTE gating
   //+------------------------------------------------------------------+
   // Returns true and sets `out` only when the buffer read is READY and valid
   // (not EMPTY_VALUE, no CopyBuffer error). On a not-ready read it returns
   // false — callers MUST fail-closed rather than compute on the silent 0.0
   // that GetVal returns on failure. Buffer-voter analogue of the PSAR A22 fix
   // and GetMAValSafe: a 0.0 read compared against a threshold or price level
   // would otherwise manufacture a spurious directional PASS.
   bool IndReadOK(int handle, int shift, int buf, double &out)
   {
      bool ok = false;
      out = GetVal(handle, shift, buf, ok);
      return ok;
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

   //+------------------------------------------------------------------+
   //| ManualEMA — exponential MA computed from raw closes              |
   //+------------------------------------------------------------------+
   // Fallback path when MT5's iMA/CopyBuffer fails. Uses CopyClose (a
   // different MT5 code path than CopyBuffer on an indicator handle —
   // much more reliable in practice).
   //
   // Method: seed with SMA over the first `period` closes in the read
   // window, then iterate the EMA recursion forward to the target shift.
   // The read window is `period * 4` bars deep, which is enough that any
   // residual seeding error decays to negligible by the target bar.
   //
   // Returns the EMA value with out_valid=true on success. On failure
   // (insufficient history, CopyClose error) returns 0.0 with
   // out_valid=false — the caller MUST check out_valid before use.
   double ManualEMA(const int period, const int shift, bool &out_valid)
   {
      out_valid = false;
      if(period < 2 || shift < 0) return 0.0;

      const int seed_bars  = period * 4;          // seed depth for clean convergence
      const int total_bars = seed_bars + shift + 1;

      double closes[];
      ArraySetAsSeries(closes, true);
      int got = CopyClose(m_symbol, PERIOD_CURRENT, 0, total_bars, closes);
      if(got < period + shift + 1) return 0.0;    // not enough history

      const double alpha = 2.0 / (period + 1.0);

      // Seed = SMA of the oldest `period` closes in the window.
      // closes[] is series-indexed: index 0 = forming bar, index 1 = last
      // closed bar, ... index (got-1) = oldest fetched bar.
      double sma = 0.0;
      for(int i = got - 1; i >= got - period; i--)
         sma += closes[i];
      sma /= (double)period;

      // Iterate EMA from (got - period - 1) down to (shift), oldest -> newest.
      double ema = sma;
      for(int i = got - period - 1; i >= shift; i--)
         ema = alpha * closes[i] + (1.0 - alpha) * ema;

      out_valid = true;
      return ema;
   }

   //+------------------------------------------------------------------+
   //| RefreshRibbonSnapshot — populates m_ribbon for the given shift   |
   //+------------------------------------------------------------------+
   // Single source of truth for ribbon EMA values. Must be called once at
   // the top of every per-bar evaluation pass, BEFORE any consumer reads
   // ribbon values via the GetEma1..4() accessors.
   //
   // For each of the 4 ribbon slots:
   //   1. Try iMA buffer via GetMAVal — the normal path
   //   2. If iMA failed (CopyBuffer error or invalid handle), fall back
   //      to ManualEMA computed from raw closes
   //   3. If both fail, mark the slot invalid (valid[i]=false) — every
   //      consumer must check IsRibbonValid() or GetEmaValid(slot) and
   //      bail safely if a needed slot is unusable
   //
   // Logs one journal line per evaluation pass that involved a fallback,
   // for forensic visibility into MT5 reliability over time.
   //+------------------------------------------------------------------+
   //| ReadEmaSafe — iMA-then-manual chain for one slot at one shift     |
   //+------------------------------------------------------------------+
   // Core read primitive. Returns the EMA value for the given slot at the
   // given shift, trying iMA's CopyBuffer first and falling back to
   // ManualEMA from raw closes if iMA fails. Caller receives the value,
   // a validity flag, and a source string ("iMA" / "MAN" / "ERR").
   //
   // Used by RefreshRibbonSnapshot to populate the per-bar cache, AND
   // by historical-scan callers (WarmUpLayerPullbackStates, scanner-
   // style DetectMarketPhase loops) that need EMA values at shifts other
   // than the cached snapshot bar.
   double ReadEmaSafe(const int slot1based, const int shift,
                      bool &out_valid, string &out_src)
   {
      out_valid = false;
      out_src   = "ERR";
      if(slot1based < 1 || slot1based > 4) return 0.0;

      int handle = INVALID_HANDLE;
      int period = 0;
      switch(slot1based)
      {
         case 1: handle = h_ema1; period = m_settings.P_Ema1; break;
         case 2: handle = h_ema2; period = m_settings.P_Ema2; break;
         case 3: handle = h_ema3; period = m_settings.P_Ema3; break;
         case 4: handle = h_ema4; period = m_settings.P_Ema4; break;
      }

      // Tier 1: iMA buffer
      bool ok = false;
      double v = GetMAVal(handle, shift, 0, ok);
      if(ok) { out_valid = true; out_src = "iMA"; return v; }

      // Tier 2: manual computation from raw closes
      v = ManualEMA(period, shift, ok);
      if(ok) { out_valid = true; out_src = "MAN"; return v; }

      // Both tiers failed
      out_valid = false;
      out_src   = "ERR";
      return 0.0;
   }

   //+------------------------------------------------------------------+
   //| RefreshRibbonSnapshot — populates m_ribbon for the given shift   |
   //+------------------------------------------------------------------+
   // Single source of truth for ribbon EMA values. Must be called once at
   // the top of every per-bar evaluation pass, BEFORE any consumer reads
   // ribbon values via the GetEma1..4() accessors.
   //
   // Populates BOTH the current shift and shift+1 (previous bar) so that
   // two-shift consumers (fan filter, S-layer alignment, sma convergence)
   // can read prev values from the same single source.
   //
   // Logs one journal line per evaluation pass that involved a fallback,
   // for forensic visibility into MT5 reliability over time.
   void RefreshRibbonSnapshot(const int shift)
   {
      bool any_fallback = false;

      // Current bar
      for(int i = 0; i < 4; i++)
      {
         bool ok; string src;
         m_ribbon.ema[i]   = ReadEmaSafe(i + 1, shift, ok, src);
         m_ribbon.valid[i] = ok;
         m_ribbon.src[i]   = src;
         if(src != "iMA") any_fallback = true;
      }

      // Previous bar (shift + 1)
      for(int i = 0; i < 4; i++)
      {
         bool ok; string src;
         m_ribbon.ema_prev[i]   = ReadEmaSafe(i + 1, shift + 1, ok, src);
         m_ribbon.valid_prev[i] = ok;
         m_ribbon.src_prev[i]   = src;
         if(src != "iMA") any_fallback = true;
      }

      m_ribbon.bar            = iTime(m_symbol, PERIOD_CURRENT, shift);
      m_ribbon.shift          = shift;
      m_ribbon.all_valid      = m_ribbon.valid[0] && m_ribbon.valid[1] &&
                                m_ribbon.valid[2] && m_ribbon.valid[3];
      m_ribbon.all_valid_prev = m_ribbon.valid_prev[0] && m_ribbon.valid_prev[1] &&
                                m_ribbon.valid_prev[2] && m_ribbon.valid_prev[3];

      if(any_fallback)
      {
         PrintFormat("[EMA_FALLBACK] %s shift=%d  cur:E1=%s/%.5f E2=%s/%.5f E3=%s/%.5f E4=%s/%.5f  prev:E1=%s/%.5f E2=%s/%.5f E3=%s/%.5f E4=%s/%.5f",
                     m_symbol, shift,
                     m_ribbon.src[0], m_ribbon.ema[0],
                     m_ribbon.src[1], m_ribbon.ema[1],
                     m_ribbon.src[2], m_ribbon.ema[2],
                     m_ribbon.src[3], m_ribbon.ema[3],
                     m_ribbon.src_prev[0], m_ribbon.ema_prev[0],
                     m_ribbon.src_prev[1], m_ribbon.ema_prev[1],
                     m_ribbon.src_prev[2], m_ribbon.ema_prev[2],
                     m_ribbon.src_prev[3], m_ribbon.ema_prev[3]);
      }
   }

   //+------------------------------------------------------------------+
   //| Ribbon accessors — the ONLY API for reading ribbon values        |
   //+------------------------------------------------------------------+
   // All callers must use these accessors. They read from the snapshot
   // populated by RefreshRibbonSnapshot. Slot numbering matches the rest
   // of the codebase: 1=h_ema1, 2=h_ema2, etc.
   //
   // Current bar accessors (snapshot.shift):
   double GetEma1() const { return m_ribbon.ema[0]; }
   double GetEma2() const { return m_ribbon.ema[1]; }
   double GetEma3() const { return m_ribbon.ema[2]; }
   double GetEma4() const { return m_ribbon.ema[3]; }

   // Previous bar accessors (snapshot.shift + 1):
   double GetEma1Prev() const { return m_ribbon.ema_prev[0]; }
   double GetEma2Prev() const { return m_ribbon.ema_prev[1]; }
   double GetEma3Prev() const { return m_ribbon.ema_prev[2]; }
   double GetEma4Prev() const { return m_ribbon.ema_prev[3]; }

   // Slot-by-index accessor (for callers that determine slot dynamically
   // from a role parameter, e.g. Check_BarClose).
   double GetEmaBySlot(const int slot1based) const
   {
      if(slot1based < 1 || slot1based > 4) return 0.0;
      return m_ribbon.ema[slot1based - 1];
   }

   // Per-slot validity check (slot is 1-based to match codebase convention)
   bool GetEmaValid(const int slot1based) const
   {
      if(slot1based < 1 || slot1based > 4) return false;
      return m_ribbon.valid[slot1based - 1];
   }
   bool GetEmaValidPrev(const int slot1based) const
   {
      if(slot1based < 1 || slot1based > 4) return false;
      return m_ribbon.valid_prev[slot1based - 1];
   }

   // True iff all four slots are usable on the current bar
   bool IsRibbonValid() const { return m_ribbon.all_valid; }
   // True iff all four slots are usable on the previous bar
   bool IsRibbonValidPrev() const { return m_ribbon.all_valid_prev; }

   // Full snapshot accessor for telemetry copy and other bulk consumers
   SRibbonSnapshot GetRibbonSnapshot() const { return m_ribbon; }

   //+------------------------------------------------------------------+
   //| HandleToSlot — identify which ribbon slot (if any) a handle is   |
   //+------------------------------------------------------------------+
   // Returns 1..4 if `handle` matches one of the four ribbon EMA handles
   // (h_ema1..h_ema4), or 0 if it's something else (BB, MFI, ATR, etc.).
   // Used by GetMAValSafe to route ribbon reads through the snapshot and
   // pass non-ribbon reads through to the direct GetMAVal path.
   int HandleToSlot(const int handle) const
   {
      if(handle == h_ema1) return 1;
      if(handle == h_ema2) return 2;
      if(handle == h_ema3) return 3;
      if(handle == h_ema4) return 4;
      return 0;
   }

   //+------------------------------------------------------------------+
   //| GetMAValSafe — universal safe accessor for any MA handle         |
   //+------------------------------------------------------------------+
   // Drop-in replacement for GetMAVal(handle, shift) at callsites that
   // hold an indirect/variable handle (e.g. `int hf = h_emaN`, layer
   // dispatcher h_fast/h_slow, PriceExtFilter `rh`). The routing:
   //
   //   • Ribbon handle (h_ema1..4) + snapshot shift     → snapshot read
   //   • Ribbon handle (h_ema1..4) + historical shift   → ReadEmaSafe
   //     (full iMA → manual fallback chain)
   //   • Non-ribbon handle (BB, MFI, ATR, etc.)         → direct GetMAVal
   //     with validity check
   //
   // Caller MUST check out_valid before using the returned value.
   double GetMAValSafe(const int handle, const int shift, bool &out_valid)
   {
      int slot = HandleToSlot(handle);
      if(slot >= 1 && slot <= 4)
      {
         // Ribbon slot — prefer snapshot
         if(shift == m_ribbon.shift)
         {
            out_valid = m_ribbon.valid[slot - 1];
            return m_ribbon.ema[slot - 1];
         }
         if(shift == m_ribbon.shift + 1)
         {
            out_valid = m_ribbon.valid_prev[slot - 1];
            return m_ribbon.ema_prev[slot - 1];
         }
         // Historical/scanner shift — full safe chain
         string ignored;
         return ReadEmaSafe(slot, shift, out_valid, ignored);
      }
      // Non-ribbon handle — direct read with validity
      return GetMAVal(handle, shift, 0, out_valid);
   }


   int GetMTFBias(const int h_fast, const int h_slow, const ENUM_TIMEFRAMES htf, const int m15_shift = 1)
   {
      if(h_fast == INVALID_HANDLE || h_slow == INVALID_HANDLE)
         return 0;
   
      double fast[];  // ✅ DYNAMIC ALLOCATION
      double slow[];  // ✅ DYNAMIC ALLOCATION
      
      ArraySetAsSeries(fast, true);  // ✅ Now valid
      ArraySetAsSeries(slow, true);  // ✅ Now valid
      
      // Map the M15 signal bar to the HTF bar that was FULLY CLOSED as of that bar.
      // hb = HTF bar containing the signal bar's time; hb+1 = the prior HTF bar, which
      // closed before the signal bar opened -> never the forming HTF bar (no repaint)
      // and never look-ahead. Cardinal rule: never read shift 0.
      int mtf_s = (m15_shift < 1) ? 1 : m15_shift;
      int hb = iBarShift(m_symbol, htf, iTime(m_symbol, PERIOD_CURRENT, mtf_s), false);
      if(hb < 0) hb = 0;
      int htf_base = hb + 1;
      if(CopyBuffer(h_fast, 0, htf_base, 2, fast) != 2) return 0;
      if(CopyBuffer(h_slow, 0, htf_base, 2, slow) != 2) return 0;

      // A22: CopyBuffer can return the requested count with EMPTY_VALUE contents
      // during HTF warmup. Validate the values so a not-yet-computed HTF EMA can't
      // produce a spurious ±1 that aligns with bias. Invalid -> unclear (0) ->
      // CheckMTFFilter fails-closed (blocks). Matches IsValidIndicatorValue in GetVal.
      if(!IsValidIndicatorValue(fast[0]) || !IsValidIndicatorValue(fast[1]) ||
         !IsValidIndicatorValue(slow[0]) || !IsValidIndicatorValue(slow[1]))
         return 0;

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

   int CheckMTFFilter(const int bias, string &reason, string &diag, const int m15_shift = 1)
   {
      if(!m_settings.Ind_MTF_Enabled)
      {
         reason = "MTF_DISABLED";
         diag   = "[MTF] Disabled";
         return +1;
      }

      int mtf_tf1 = GetMTFBias(h_mtf_tf1_fast, h_mtf_tf1_slow, m_settings.MTF_TF1, m15_shift);
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

      int mtf_tf2 = GetMTFBias(h_mtf_tf2_fast, h_mtf_tf2_slow, m_settings.MTF_TF2, m15_shift);
      string tf2_label = EnumToString(m_settings.MTF_TF2);

      // HTF is a directional gate: with two HTFs configured, BOTH must agree
      // with the trade direction. No majority/pullback exception — a trade is
      // only allowed in the direction of the higher-TF trend(s).
      // (MTF_StrictAlignment is retained for compatibility but the gate is
      //  strict-by-construction; the flag no longer relaxes it.)
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

   //+------------------------------------------------------------------+
   //| Check_MTF — Bool wrapper for MTF voter (EvaluateIndicatorX)      |
   //| Uses the same CheckMTFFilter logic but returns true/false        |
   //| for CAST_VOTE_STAT compatibility.                                |
   //+------------------------------------------------------------------+
   bool Check_MTF(int bias, int shift = 1)
   {
      string reason = "";
      string diag   = "";
      return (CheckMTFFilter(bias, reason, diag, shift) != 0);
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

      double adx = 0.0;
      if(!IndReadOK(h_adx, shift, 0, adx)) {          // A22: not-ready -> reject, uncached,
         if(m_settings.DebugFlow)                      // and never push 0.0 into the percentile buffer
            DebugLog(StringFormat("[IND_ADX] shift=%d not ready -> FAIL (uncached)", shift));
         return false;
      }

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
            // Recalculate when the rolling buffer fills, or after the user-configured
            // refresh interval elapses. Previously the interval was hardcoded to
            // 14400 seconds (4 hours) which is sensible on H4+ but means up to 240
            // bars of stale threshold on an M1 chart. Now exposed as
            // ADX_PercentileRefreshSec for per-preset/per-timeframe tuning. The 60-
            // second floor prevents an accidentally-tiny value from recomputing the
            // percentile on every tick (CPU-expensive on long lookback buffers).
            {
               int refresh_sec = (m_settings.ADX_PercentileRefreshSec >= 60
                                    ? m_settings.ADX_PercentileRefreshSec
                                    : 60);
               if(m_adxHistorySize >= m_adxHistoryMaxSize ||
                  TimeCurrent() - m_lastADXCalculation >= refresh_sec) {
                  m_cachedADXThreshold = CalculateADXPercentile(m_settings.ADX_Percentile);
                  m_lastADXCalculation = TimeCurrent();
               }
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

      // STEP7 2026-06: FIXED LATENT BUG. Previously this read m_diag_last_atr_pips
      // which was historically refreshed inside CheckFilters() but the F-audit
      // removed that path, leaving the value always 0.0. That made both < / >
      // comparisons silently false, so Check_ATR always returned true (ATR voter
      // never filtered anything). Fix: call AtrPips() directly to get the live
      // ATR value in pips. For default users (Inp_RRM_ORG_Use_Atr=false) zero
      // behavior change. For users who enable the voter, ATR_VoteMinPips /
      // ATR_VoteMaxPips now actually filter as documented.
      // A22: validity-check the ATR read. Previously AtrPips() -> GetATR() (single-arg,
      // discards validity) returned 0.0 on a not-ready read, making this gate's outcome
      // config-dependent (Min set -> block; Max-only -> spurious pass). Now deterministic:
      // a not-ready read rejects (fail-closed), uncached, so the next tick recomputes.
      bool   atr_ok  = false;
      double atr_raw = GetVal(h_atr, 1, 0, atr_ok);
      if(!atr_ok || atr_raw <= 0.0) {
         if(m_settings.DebugFlow) DebugLog("[IND_ATR] ATR not ready -> FAIL (uncached)");
         return false;   // fail-closed; leave atr_result at -1 so next tick recomputes
      }
      double atr_pips = GlobalAtrPips(atr_raw, m_symbol);
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

      double mid = 0.0;
      if(!IndReadOK(h_bb, shift, 0, mid)) {           // A22: BB handle not ready -> reject both dirs, uncached
         if(m_settings.DebugFlow)
            DebugLog(StringFormat("[IND_BB] shift=%d not ready -> FAIL (uncached)", shift));
         return false;
      }
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
         double lower = 0.0, upper = 0.0;
         if(!IndReadOK(h_bb, shift, 2, lower) || !IndReadOK(h_bb, shift, 1, upper)) {
            m_ind_cache.cached_bias = bias;             // A22: bands not ready -> reject, uncached
            m_ind_cache.bb_result   = -1;               // leave uncached so next tick recomputes
            return false;
         }
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
      // Determine which EMA to check (slot 1..4 selected by mode + config)
      // ════════════════════════════════════════════════════════════════
      double check_ema = 0.0;
      string bc_label = "bc";
      string ema_name = "";
      int    slot     = 1;     // 1..4, set per mode below

      if(m_settings.BarClose_Mode == BC_LAYER_AWARE && active_layer != LAYER_NONE)
      {
         // Layer-aware mode: bcW/bcM/bcS
         switch(active_layer)
         {
            case LAYER_1_WEAK:   slot = 1; bc_label = "bcW"; break;
            case LAYER_2_MEDIUM: slot = 2; bc_label = "bcM"; break;
            case LAYER_3_STRONG: slot = 3; bc_label = "bcS"; break;
            default:             slot = 1; bc_label = "bc";  break;
         }
      }
      else if(m_settings.BarClose_Mode == BC_BIAS_FAST)
      {
         // Use BiasFastID
         switch(m_settings.BiasFastID)
         {
            case (int)ROLE_EMA1: slot = 1; break;
            case (int)ROLE_EMA2: slot = 2; break;
            case (int)ROLE_EMA3: slot = 3; break;
            case (int)ROLE_EMA4: slot = 4; break;
            default:             slot = 1; break;
         }
         bc_label = "bc";
      }
      else  // BC_FIXED_EMA
      {
         // Use BarClose_DefaultEMA
         switch(m_settings.BarClose_DefaultEMA)
         {
            case ROLE_EMA1: slot = 1; break;
            case ROLE_EMA2: slot = 2; break;
            case ROLE_EMA3: slot = 3; break;
            case ROLE_EMA4: slot = 4; break;
            default:        slot = 1; break;
         }
         bc_label = "bc";
      }

      // Read EMA from ribbon snapshot. Refuse the gate if the slot is invalid.
      if(!GetEmaValid(slot))
      {
         if(m_settings.DebugFlow)
            DebugLog(StringFormat("[%s] EMA%d INVALID at v_shift=%d → REFUSE gate", bc_label, slot, v_shift));
         return 0;
      }
      check_ema = GetEmaBySlot(slot);
      ema_name  = StringFormat("EMA%d", slot);
      
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

      bool pass = CheckCandleBodyIndicator(bias, shift);
      // CBOEB carry: hold the vote at 0 from an over-extended bar until the next
      // layer pullback-recovery clears it (CB = body * CBOEB).
      if(m_settings.Ind_CandleBody_Enabled && m_settings.CandleBody_CarryOnOverext && m_cb_oeb_blocked)
         pass = false;
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

      double c = 0.0;
      if(!IndReadOK(h_cci, shift, 0, c)) {            // A22: not ready -> reject, uncached
         if(m_settings.DebugFlow)
            DebugLog(StringFormat("[IND_CCI] shift=%d not ready -> FAIL (uncached)", shift));
         return false;
      }
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
      datetime bar_time = iTime(m_symbol, PERIOD_CURRENT, v_shift);

      // Update only once per bar (covers both the reset machine and the tracking subsystem)
      if(m_dpi_hist_last_update == bar_time) return;
      m_dpi_hist_last_update = bar_time;

      // ── CCI Reset→Recovery state machine (canonical §5) ───────────────────────────
      // Runs whenever RequireResetRecovery, INDEPENDENT of HistTrackingEnabled (decoupled
      // 260601 — the reset needs only the ribbon colour, which is always computed). Reset =
      // ribbon COLOUR flip away from the trend colour; recovery = colour returns and holds for
      // ResetRecoveryBars (+ optional GREEN). Bias-independent (R1): direction is enforced by
      // BASE in Check_DPI (colour == bias), so this machine only certifies a reset→recovery cycle.
      if(m_settings.DPI_RequireResetRecovery)
      {
         double h_cur=0.0, h_prev=0.0, gm_c=0.0, gm_p=0.0;
         bool   g=false, ma=false, colour_yellow=false;
         if(ComputeDPIMainHist(v_shift, h_cur, h_prev, g, ma, gm_c, gm_p, colour_yellow))
         {
            // COLD-START GUARD: on the very first observation (or first after a
            // ResetDPIResetState / ResetDirectionalState call), seed colour_prev
            // to whatever the ribbon actually is, then skip the transition test
            // this bar. Otherwise the init-default colour_prev=false would
            // disagree with a yellow uptrend, fire IDLE→RESET_DETECTED, freeze
            // colour_ref at red, and lock the gate forever on a session that
            // never sees a real flip back to red.
            //
            // FIRST-ENTRY GRANT (DPI_GrantFirstEntry): when the session has not
            // yet executed a trade AND the operator enabled this convenience,
            // the cold start also pre-arms the gate at ENTRY_ALLOWED with
            // colour_ref = current ribbon colour. The gate is therefore open
            // immediately and stays open until the ribbon flips (which would
            // trigger a normal RESET_DETECTED on the next bar). Without this
            // grant the user is locked out of the very first opportunity by
            // construction — the gate cannot certify a reset→recovery cycle
            // that, by definition, has not happened yet. After the first
            // trade, ResetDPIResetState() sets m_dpi_first_entry_consumed=true,
            // so this branch never fires again for the rest of the session and
            // the gate enforces its full discipline for every subsequent trade.
            if(!m_dpi_reset_initialized)
            {
               m_dpi_reset_colour_prev = colour_yellow;
               bool grant = (m_settings.DPI_GrantFirstEntry && !m_dpi_first_entry_consumed);
               if(grant)
               {
                  m_dpi_reset_colour_ref = colour_yellow;   // current colour IS the "trend" to return to
                  m_dpi_reset_state      = 3;               // ENTRY_ALLOWED — first-trade grant
               }
               m_dpi_reset_initialized = true;
               if(m_settings.DebugFlow)
                  DebugLog(StringFormat("[DPI_RESET] init seeded prev=%s | first_entry_grant=%s | state=%s",
                                        colour_yellow?"YELLOW":"RED",
                                        grant?"YES":"NO",
                                        grant?"ENTRY_ALLOWED":"IDLE"));
            }
            else
            {
               bool green_present = (gm_c > 0.0);
               int  prev_state = m_dpi_reset_state;
            switch(m_dpi_reset_state)
            {
               case 0: // IDLE — a colour flip away from the prevailing colour starts a reset
                  if(colour_yellow != m_dpi_reset_colour_prev)
                  {
                     m_dpi_reset_colour_ref    = m_dpi_reset_colour_prev; // trend colour to return to
                     m_dpi_reset_state         = 1;
                     m_dpi_reset_recovery_bars = 0;
                  }
                  break;

               case 1: // RESET_DETECTED — wait for colour to return to the trend colour
                  if(colour_yellow == m_dpi_reset_colour_ref)
                  {
                     m_dpi_reset_state         = 2;
                     m_dpi_reset_recovery_bars = 0;
                  }
                  break;

               case 2: // RECOVERY_COUNTING — colour back on trend; count confirm bars
                  if(colour_yellow != m_dpi_reset_colour_ref)
                  {
                     m_dpi_reset_state         = 1;   // flipped away again before confirm
                     m_dpi_reset_recovery_bars = 0;
                  }
                  else
                  {
                     m_dpi_reset_recovery_bars++;
                     bool green_ok = (!m_settings.DPI_ResetRequireGreen || green_present);
                     if(m_dpi_reset_recovery_bars >= m_settings.DPI_ResetRecoveryBars && green_ok)
                        m_dpi_reset_state = 3;          // ENTRY_ALLOWED
                  }
                  break;

               case 3: // ENTRY_ALLOWED — open until a new colour flip starts another cycle
                  if(colour_yellow != m_dpi_reset_colour_ref)
                  {
                     m_dpi_reset_state         = 1;
                     m_dpi_reset_recovery_bars = 0;
                  }
                  // Resets to IDLE after a trade is taken (external ResetDPIResetState()).
                  break;
            }
            m_dpi_reset_colour_prev = colour_yellow;

            if(m_settings.DebugFlow && m_dpi_reset_state != prev_state)
            {
               string s_prev = (prev_state==0?"IDLE":prev_state==1?"RESET_DETECTED":prev_state==2?"RECOVERY_COUNTING":"ENTRY_ALLOWED");
               string s_now  = (m_dpi_reset_state==0?"IDLE":m_dpi_reset_state==1?"RESET_DETECTED":m_dpi_reset_state==2?"RECOVERY_COUNTING":"ENTRY_ALLOWED");
               DebugLog(StringFormat("[DPI_RESET] %s → %s | colour=%s ref=%s | recovery_bars=%d/%d",
                                     s_prev, s_now, colour_yellow?"YELLOW":"RED",
                                     m_dpi_reset_colour_ref?"YELLOW":"RED",
                                     m_dpi_reset_recovery_bars, m_settings.DPI_ResetRecoveryBars));
            }
            }  // end else (state machine block — only runs after init seeded)
         }
      }

      // ── CCI histogram TRACKING subsystem (decel / green-present) ───────────────────
      // Gated by the HistTrackingEnabled master switch (off in RRM_ORG).
      if(!m_settings.DPI_HistTrackingEnabled) return;

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
         bool   dpi_green = false, dpi_macd_agree = false, dpi_wants_yellow = false;
         double green_mag_cur = 0.0, green_mag_prev = 0.0;
         if(ComputeDPIMainHist(v_shift, hist_cur, hist_prev, dpi_green, dpi_macd_agree,
                               green_mag_cur, green_mag_prev, dpi_wants_yellow))
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

   //+------------------------------------------------------------------+
   //| GetCurrentBarVolume — VPRR volume reader (real-first, tick-back) |
   //+------------------------------------------------------------------+
   // Reads the volume of the closed bar at 'shift'. Honors VPRR_VolumeType:
   //   AUTO/REAL:  try CopyRealVolume on m_symbol; tick fallback for AUTO.
   //   EXTERNAL:   CopyRealVolume from proxy symbol (e.g. "GC" futures).
   //               Falls back to tick on m_symbol if proxy returns 0.
   //   TICK:       CopyTickVolume on m_symbol always.
   // Records which source was used in m_vprr_last_real for the UI label.
   long GetCurrentBarVolume(int shift)
   {
      // ── EXTERNAL: read real volume from proxy symbol ─────────────────
      if(m_settings.VPRR_VolumeType == VPRR_VOL_EXTERNAL)
      {
         if(StringLen(m_settings.VPRR_ExternalSymbol) > 0)
         {
            long ext_vol[];
            if(CopyRealVolume(m_settings.VPRR_ExternalSymbol, PERIOD_CURRENT, shift, 1, ext_vol) == 1 && ext_vol[0] > 0)
            {
               m_vprr_last_real = true;
               return ext_vol[0];
            }
         }
         // Proxy unavailable or symbol not configured — fall back to tick on primary symbol
         m_vprr_last_real = false;
         long tick_fb[];
         if(CopyTickVolume(m_symbol, PERIOD_CURRENT, shift, 1, tick_fb) == 1)
            return tick_fb[0];
         return 0;
      }

      // ── REAL / AUTO: try real volume on primary symbol ───────────────
      if(m_settings.VPRR_VolumeType == VPRR_VOL_REAL ||
         m_settings.VPRR_VolumeType == VPRR_VOL_AUTO)
      {
         long real_vol[];
         if(CopyRealVolume(m_symbol, PERIOD_CURRENT, shift, 1, real_vol) == 1 && real_vol[0] > 0)
         {
            m_vprr_last_real = true;
            return real_vol[0];
         }
         // REAL forced but unavailable → nothing usable; AUTO continues to tick.
         if(m_settings.VPRR_VolumeType == VPRR_VOL_REAL)
         {
            // One-shot user warning. Without this, the user would see VPRR
            // always failing and have no clue why — the cockpit just shows
            // "ratio 0.00 < min" with no hint that the broker simply isn't
            // supplying real volume on this symbol. The warning is logged
            // unconditionally (not gated by DebugFlow) because it changes
            // user behaviour (switch to AUTO or TICK).
            if(!m_vprr_real_warned)
            {
               PrintFormat("[VPRR] WARN: VPRR_VolumeType=REAL but %s returned no real volume on %s. "
                           "VPRR will fail every bar until the source is changed. Use AUTO for "
                           "automatic fallback to TICK volume, or TICK explicitly.",
                           "CopyRealVolume", m_symbol);
               m_vprr_real_warned = true;
            }
            m_vprr_last_real = false;
            return 0;
         }
      }
      long tick_vol[];
      if(CopyTickVolume(m_symbol, PERIOD_CURRENT, shift, 1, tick_vol) == 1)
      {
         m_vprr_last_real = false;
         return tick_vol[0];
      }
      return 0;
   }

   //+------------------------------------------------------------------+
   //| UpdateSingleLayerPullback — State machine for one layer          |
   //+------------------------------------------------------------------+
   // Path 2 (2026-07) — pure position+slope, evaluated vs bias_dir:
   //   Pullback (DETECTED) = fast-EMA slope LEAVES the trend: FLAT or REVERSED
   //                         (a shallower-but-same-direction slope is NOT a
   //                          pullback). Price-vs-EMA is not used here.
   //   Recovery (RECOVERED)= BOTH layer EMA slopes (fast AND slow) back in
   //                         bias_dir. Slope-only — NOT close-vs-EMA (that is
   //                         the separate BC gate) and NOT vs the historical
   //                         baseline (which sits inside the dip).
   // VPRR: volume tracking fields accumulated per state, once-per-bar.
   void UpdateSingleLayerPullback(int fast_ema_handle, int v_shift, int lookback,
                                  double recovery_ratio,
                                  ELayerPullbackState &state, double &baseline, string label,
                                  double &vol_pb_avg, int &vol_pb_bars,
                                  double &vol_rec_avg, int &vol_rec_bars,
                                  double &vprr, int &bars_det, int &bars_rec,
                                  int &g1_recov, bool &g1_counted,
                                  int bias_dir = 0,
                                  int slow_ema_handle = INVALID_HANDLE,
                                  bool use_price_touch = false,
                                  int min_pb_bars = 0,
                                  int window = 0,
                                  bool maxage_enabled = false)
   {
      // -- Baseline DIRECTION (refined, kept): sign of the EMA slope on the bar
      //    JUST BEFORE the lookback window, so an in-progress pullback cannot
      //    contaminate the trend direction we measure against.
      double ema_baseline_old = GetMAVal(fast_ema_handle, v_shift + lookback + 1);
      double ema_baseline_new = GetMAVal(fast_ema_handle, v_shift + lookback);
      double baseline_slope   = ema_baseline_new - ema_baseline_old;   // sign = pre-pullback dir
      baseline = baseline_slope;
      bool baseline_bullish   = (baseline_slope > 0.0);

      // -- Baseline PACE (ratio denominator): AVERAGED per-bar slope over the
      //    lookback window ending just before the current bar. Averaging (vs a
      //    single-bar value) is the fix that stops slow EMAs (34/89) reading as
      //    falsely "weakened" -- the bug that originally got magnitude removed.
      double ema_pace_old = GetMAVal(fast_ema_handle, v_shift + lookback + 1);
      double ema_pace_new = GetMAVal(fast_ema_handle, v_shift + 1);
      double baseline_pace = (lookback > 0) ? (ema_pace_new - ema_pace_old) / (double)lookback : 0.0;

      // -- Current PACE (ratio numerator): k-bar recent slope, NOT one bar.
      //    k auto-scales with the (per-layer) lookback, so the slow S layer is
      //    smoothed more than the fast W layer. This + the averaged denominator
      //    is the slow-EMA root-cause fix.
      int    k        = (int)MathMax(2.0, (double)lookback / 4.0);
      double ema_now  = GetMAVal(fast_ema_handle, v_shift);
      double ema_kago = GetMAVal(fast_ema_handle, v_shift + k);
      double current_pace    = (ema_now - ema_kago) / (double)k;
      bool   current_bullish = (current_pace > 0.0);

      // -- Magnitude ratio: |recent pace| relative to |normal trend pace|
      double ratio = 0.0;
      if(MathAbs(baseline_pace) >= SEA_LAYER_SLOPE_EPSILON)
         ratio = MathAbs(current_pace) / MathAbs(baseline_pace);

      // -- Path 2 (2026-07): POSITION (cross) invalidation. If the fast EMA has
      //    crossed to the WRONG side of the slow EMA, the ribbon is no longer
      //    "on the proper side" (Oracle) and THIS layer's setup is invalid.
      //    Reset the state machine to NONE so a FRESH pullback→recovery cycle is
      //    required once position is restored — and skip pullback/recovery
      //    processing this bar. EvaluateL's read-only cascade (CheckLayerPairAlign)
      //    independently walks to the next-deeper layer (W→M→S). Only applied when
      //    bias is known and a slow handle was supplied.
      if(bias_dir != 0 && slow_ema_handle != INVALID_HANDLE)
      {
         double pos_fast = GetMAVal(fast_ema_handle, v_shift);
         double pos_slow = GetMAVal(slow_ema_handle, v_shift);
         if(pos_fast > 0.0 && pos_slow > 0.0)
         {
            bool position_ok = (bias_dir > 0) ? (pos_fast > pos_slow) : (pos_fast < pos_slow);
            if(!position_ok)
            {
               if(state != LAYER_PB_NONE && m_settings.DebugFlow)
                  DebugLog(StringFormat("[%s_PB] CROSS invalidation: fast/slow crossed (position lost) -> reset to NONE",
                                        label));
               state       = LAYER_PB_NONE;
               bars_det    = 0;
               bars_rec    = 0;
               // Mirror the NONE-branch VPRR invariant (external reset path).
               vol_pb_avg  = 0.0; vol_pb_bars  = 0;
               vol_rec_avg = 0.0; vol_rec_bars = 0;
               vprr        = 0.0;
               return;   // invalidated layer — no pullback/recovery this bar
            }
         }
      }

      // -- Pullback (Path 2, 2026-07): DETECTED when the fast EMA's slope has
      //    LEFT the trend — FLAT or REVERSED. A fast EMA still sloping in the
      //    trend direction, merely at a shallower angle, is normal trend
      //    breathing and is NOT a pullback: the old magnitude-ratio
      //    'is_weakened' trigger is removed (it oscillated state and produced
      //    noise entries). 'ratio' is still used for the flat test below.
      bool is_flat     = (ratio < m_settings.LayerFlatRatio);
      bool is_pullback = is_flat;
      // Reversed: fast-EMA slope sign now OPPOSITE the trend. Anchored to the
      // LIVE bias (bias_dir) when supplied — the pre-pullback baseline is only
      // a fallback for bias-less (warmup) calls.
      bool slope_reversed;
      if(bias_dir != 0)
         slope_reversed = (current_pace != 0.0) && ((bias_dir > 0) != (current_pace > 0.0));
      else
         slope_reversed = (baseline_bullish != current_bullish) && (current_pace != 0.0);
      if(m_settings.LayerAllowReversalPullback && slope_reversed)
         is_pullback = true;

      // -- Path 2 (2026-07): the S2 price-zone-touch DETECTED gate and the raw
      //    close-vs-EMA recovery_cond have been REMOVED. The layer model is now
      //    pure position+slope (see header) — price-vs-EMA is confirmed only at
      //    the separate BC gate, never inside the pullback-recovery machine.
      //    `use_price_touch` is retained in the signature for ABI/back-compat but
      //    is inert (LayerPriceTouchEnabled defaults false).

      // -- Recovery (from DETECTED) — Path 2 (2026-07): RECOVERED when BOTH of the
      //    layer's EMA slopes (fast AND slow) point in bias_dir again — momentum
      //    has resumed in the trade direction. PURE SLOPE vs the LIVE bias:
      //      * NOT close-vs-EMA: the previous close-based test duplicated the
      //        separate BC gate (recovery == BC). Recovery is now structurally
      //        distinct from BC.
      //      * NOT baseline_bullish: a baseline measured 'lookback' bars back
      //        sits INSIDE the dip and points the WRONG way after a counter-trend
      //        pullback, so a valid recovery could never confirm (the proven
      //        DET-but-never-REC block). bias_dir (the live B-factor direction) is
      //        the correct, un-contaminated reference.
      //    Requiring the SLOW EMA slope too filters the single-bar V-bounce false
      //    recovery: the slow EMA does not flip on one violent counter-bar.
      //    recovery_ratio / recovery_cond are no longer consulted here (retained
      //    in the signature for ABI/back-compat and VPRR callers).
      bool is_recovery = false;
      if(state == LAYER_PB_DETECTED)
      {
         if(bias_dir != 0)
         {
            // Fast EMA k-bar slope (== current_pace) resumed in bias_dir.
            bool fast_in_bias = (current_pace != 0.0) &&
                                ((bias_dir > 0) == (current_pace > 0.0));
            // Slow EMA k-bar slope (same k window) in bias_dir.
            bool slow_in_bias = true;   // defensive default if no slow handle
            if(slow_ema_handle != INVALID_HANDLE)
            {
               double slow_now  = GetMAVal(slow_ema_handle, v_shift);
               double slow_kago = GetMAVal(slow_ema_handle, v_shift + k);
               double slow_pace = (slow_now - slow_kago) / (double)k;
               slow_in_bias = (slow_pace != 0.0) &&
                              ((bias_dir > 0) == (slow_pace > 0.0));
            }
            is_recovery = fast_in_bias && slow_in_bias;
         }
         else
         {
            // Back-compat fallback when no bias is supplied (bias_dir == 0):
            // 1-bar slope-sign test against the historical baseline direction.
            double ema_rec_now  = GetMAVal(fast_ema_handle, v_shift);
            double ema_rec_prev = GetMAVal(fast_ema_handle, v_shift + 1);
            double rec_slope    = ema_rec_now - ema_rec_prev;
            is_recovery = (rec_slope != 0.0) && (baseline_bullish == (rec_slope > 0.0));
         }
      }

      // -- Relapse trigger (RECOVERED -> DETECTED): a COMPLETED recovery is
      //    only invalidated by a genuine counter-trend reversal, NOT by mere
      //    slope weakening/flattening. Transient weakening one bar after a
      //    1-bar-sign recovery would otherwise oscillate the state and keep
      //    resetting VPRR's recovery-volume window (vol_rec_bars), starving the
      //    VPRR ratio so it never passes the I-factor vote. Requiring a true
      //    reversal keeps RECOVERED durable across normal consolidation, which
      //    both restores the pre-change trade frequency and lets VPRR measure.
      // Anchored to bias_dir (matches the recovery/pullback reference); falls
      // back to the pre-pullback baseline only for bias-less (warmup) calls.
      bool is_relapse_reversal;
      if(bias_dir != 0)
         is_relapse_reversal = (current_pace != 0.0) && ((bias_dir > 0) != (current_pace > 0.0));
      else
         is_relapse_reversal = (baseline_bullish != current_bullish) && (current_pace != 0.0);

      // A21 2026-07: advance bars_det counter before transition logic.
      // Counts consecutive bars spent in DETECTED; resets to 0 when not in DETECTED.
      // Transition DETECTED→RECOVERED is gated: bars_det must reach min_pb_bars first.
      if(state == LAYER_PB_DETECTED)
         bars_det++;
      else
         bars_det = 0;

      // Path 2 2026-07: advance bars_rec (bars spent in RECOVERED) for the
      // recovery max-age cap. Self-managed — zeroed whenever not RECOVERED, so
      // an external reset to NONE clears it on the next bar without extra wiring.
      if(state == LAYER_PB_RECOVERED)
         bars_rec++;
      else
         bars_rec = 0;

      ELayerPullbackState prev_state = state;
      if(state == LAYER_PB_NONE && is_pullback)
      {
         // Path 2 (2026-07): a fresh pullback always enters DETECTED. The former
         // S2 one-bar NONE→RECOVERED shortcut (wick touch + same-bar close
         // recovery) is REMOVED — a pullback→recovery cycle cannot complete in a
         // single bar, and the A21 minimum-duration gate below is never bypassed.
         state    = LAYER_PB_DETECTED;
         bars_det = 1;   // first bar of a fresh DETECTED cycle
         // GUARD 1: a NEW pullback-recovery cycle begins here. This is the ONLY exit
         // from NONE, so clearing the latch here covers every reset-to-NONE path
         // (consumption / max-age / cross / phase-clear / climax / sustained-UNO)
         // without wiring any of them. A relapse from RECOVERED does NOT come through
         // this branch, so it correctly leaves the latch set (same cycle).
         g1_counted = false;
      }
      else if(state == LAYER_PB_DETECTED && is_recovery)
      {
         // A21 gate: require minimum bars in DETECTED before allowing RECOVERED.
         if(bars_det < min_pb_bars)
         {
            if(m_settings.DebugFlow)
               DebugLog(StringFormat("[%s_PB] DET→REC BLOCKED by MinPullbackBars: %d bars < required %d (state stays DETECTED)",
                                     label, bars_det, min_pb_bars));
            // state stays DETECTED; bars_det already incremented above
         }
         // Theme 2026-06 (UNO-exit cooldown): when MinBarsAfterUNOExit > 0, block
         // the DETECTED→RECOVERED transition until that many non-UNO bars have
         // accumulated since the last UNO bar. Rationale: EMA1/EMA2 geometry on
         // the first non-UNO bars carries trailing influence from UNO-period
         // price action; a "recovery" detected there isn't a true post-UNO cycle.
         // State stays DETECTED — the next bar can re-attempt the transition
         // when the cooldown has further progressed. Diagnostic line emitted at
         // DEBUG_FLOW level so the operator can verify on the bar of interest.
         else if(m_settings.MinBarsAfterUNOExit > 0 &&
                 m_bars_since_uno_exit < m_settings.MinBarsAfterUNOExit)
         {
            if(m_settings.DebugFlow)
               DebugLog(StringFormat("[%s_PB] DET→REC BLOCKED by UNO-exit cooldown: %d bars since UNO exit < required %d (state stays DETECTED)",
                                     label, m_bars_since_uno_exit, m_settings.MinBarsAfterUNOExit));
         }
         else
         {
            state = LAYER_PB_RECOVERED;
            // GUARD 1: this is the ONE place the engine writes LAYER_PB_RECOVERED, so it
            // is the canonical "pullback-recovery completed" event. Count it ONCE per
            // cycle — a relapse that re-recovers must not advance the count.
            if(!g1_counted)
            {
               g1_counted = true;
               if(g1_recov < 1000000) g1_recov++;
               if(m_settings.DebugFlow)
                  DebugLog(StringFormat("[%s_G1] pullback-recovery cycle #%d completed since last bias flip",
                                        label, g1_recov));
            }
         }
      }
      else if(state == LAYER_PB_RECOVERED && is_relapse_reversal)
      {
         state    = LAYER_PB_DETECTED;
         bars_det = 1;   // first bar of a relapse DETECTED cycle
      }
      else if(state == LAYER_PB_RECOVERED && maxage_enabled && window > 0 && bars_rec >= window)
      {
         // Recovery max-age (Path 2): a RECOVERED layer that has waited longer than
         // its observation window to fire is stale — expire to NONE so a fresh
         // pullback→recovery cycle is required (prevents a chase-entry far from the
         // recovery point). Relapse (counter-trend reversal) takes precedence via
         // the branch above; this is the quiet-timeout fallback.
         state = LAYER_PB_NONE;
         if(m_settings.DebugFlow)
            DebugLog(StringFormat("[%s_PB] RECOVERED expired by max-age: %d bars >= window %d -> NONE",
                                  label, bars_rec, window));
      }

      if(m_settings.DebugFlow && state != prev_state)
      {
         DebugLog(StringFormat("[%s_PB] State: %s -> %s | Ratio=%.2f | RecThresh=%.2f | Pace cur/base=%.6f/%.6f | Dir %s/%s",
                               label,
                               EnumToString(prev_state),
                               EnumToString(state),
                               ratio,
                               recovery_ratio,
                               current_pace,
                               baseline_pace,
                               baseline_bullish ? "UP" : "DN",
                               current_bullish  ? "UP" : "DN"));
      }

      // ── VPRR: volume tracking per (post-transition) state ──────────────
      // Runs once per bar (caller guards via m_layer_pb_last_update).
      if(m_settings.VPRR_Enabled)
      {
         long vol_current = GetCurrentBarVolume(v_shift);

         if(state == LAYER_PB_DETECTED)
         {
            // Fresh entry into DETECTED (incl. RECOVERED→DETECTED relapse):
            // restart recovery measurement so a stale ratio can't carry over.
            if(prev_state != LAYER_PB_DETECTED)
            {
               vol_rec_avg = 0.0;
               vol_rec_bars = 0;
               vprr = 0.0;
            }
            // Accumulate running average of pullback volume.
            // A22: skip bars whose volume read failed / returned 0. Averaging a spurious
            // 0 into the PULLBACK volume lowers vol_pb_avg and INFLATES the ratio
            // (vprr = rec/pb) -> spurious PASS. A genuine 0-volume bar is meaningless for
            // the ratio too, so skipping <=0 is correct either way. Persistent no-volume
            // then leaves vol_pb_bars=0 -> ratio never computed -> VPRR fails every bar
            // (fail-closed), matching the documented REAL-mode warning.
            if(vol_current > 0)
            {
               vol_pb_avg = ((vol_pb_avg * vol_pb_bars) + (double)vol_current) / (vol_pb_bars + 1);
               vol_pb_bars++;
            }
         }
         else if(state == LAYER_PB_RECOVERED)
         {
            // Measure recovery volume over the first N bars only.
            // A22: same skip-on-invalid guard as the pullback branch (a 0 read here
            // lowers rec_avg -> deflates the ratio, the safe direction, but skipping
            // keeps the average built only from real volume bars for both sides).
            if(vol_current > 0 && vol_rec_bars < m_settings.VPRR_RecoveryBars)
            {
               vol_rec_avg = ((vol_rec_avg * vol_rec_bars) + (double)vol_current) / (vol_rec_bars + 1);
               vol_rec_bars++;
            }
            // Compute ratio once enough recovery bars are collected.
            if(vol_rec_bars >= m_settings.VPRR_MinRecoveryBars && vol_pb_avg > 0.0)
               vprr = vol_rec_avg / vol_pb_avg;
         }
         else // LAYER_PB_NONE
         {
            vol_pb_avg = 0.0; vol_pb_bars = 0;
            vol_rec_avg = 0.0; vol_rec_bars = 0;
            vprr = 0.0;
         }
      }
   }

   //+------------------------------------------------------------------+
   //| GetLayerLookback / GetLayerRecovery -- per-layer resolvers       |
   //| layer: 1=W, 2=M, 3=S. Per-layer 0/<0 falls back to the global.   |
   //+------------------------------------------------------------------+
   int GetLayerLookback(int layer)
   {
      int lb = (layer == 1) ? m_settings.LayerBaselineLookback_W :
               (layer == 2) ? m_settings.LayerBaselineLookback_M :
                              m_settings.LayerBaselineLookback_S;
      if(lb <= 0) lb = m_settings.LayerBaselineLookback;   // fall back to global
      if(lb < 1)  lb = 1;
      return lb;
   }
   double GetLayerRecovery(int layer)
   {
      double rr = (layer == 1) ? m_settings.LayerRecoveryRatio_W :
                  (layer == 2) ? m_settings.LayerRecoveryRatio_M :
                                 m_settings.LayerRecoveryRatio_S;
      if(rr < 0.0) rr = m_settings.LayerRecoveryRatio;     // -1 = use global
      return rr;
   }

   // A21 2026-07: per-layer minimum pullback bar count before RECOVERED is allowed.
   int GetLayerMinPBBars(int layer)
   {
      int v = (layer == 1) ? m_settings.LayerMinPullbackBars_W :
              (layer == 2) ? m_settings.LayerMinPullbackBars_M :
                             m_settings.LayerMinPullbackBars_S;
      return MathMax(0, v);
   }

   // Path 2 2026-07: per-layer pullback OBSERVATION WINDOW (bars). Per-layer value,
   // else the global override, else a hard 21/34/55 default. Also the default
   // recovery max-age cap.
   int GetLayerWindow(int layer)
   {
      int w = (layer == 1) ? m_settings.LayerPullbackWindow_W :
              (layer == 2) ? m_settings.LayerPullbackWindow_M :
                             m_settings.LayerPullbackWindow_S;
      if(w <= 0) w = m_settings.LayerPullbackWindow;               // global override
      if(w <= 0) w = (layer == 1) ? 21 : (layer == 2) ? 34 : 55;  // hard default
      return w;
   }

   //+------------------------------------------------------------------+
   //| MaybeResetLayersOnPhaseChange (optional)                         |
   //| Clear stale layer pullback-recovery states when the market re-   |
   //| orders into a new (debounced) phase, so the new phase's first    |
   //| pullback is evaluated fresh. Debounced by LayerResetPhaseConfirm |
   //| Bars to ignore 1-bar boundary flicker (set =1 to act on genuine  |
   //| 1-bar phases such as a brief EMERGING). Symmetric: fires on any   |
   //| UNO/EM/TM transition and on direction flips (distinct enum vals). |
   //+------------------------------------------------------------------+
   void MaybeResetLayersOnPhaseChange(int v_shift)
   {
      if(!m_settings.LayerResetOnRealign) return;
      EMarketPhase ph_now = DetectMarketPhase(v_shift);
      if(ph_now == m_phase_reset_pending)
      {
         if(m_phase_reset_count < 1000000) m_phase_reset_count++;
      }
      else
      {
         m_phase_reset_pending = ph_now;
         m_phase_reset_count   = 1;
      }
      int confirm_need = m_settings.LayerResetPhaseConfirmBars;
      if(confirm_need < 1) confirm_need = 1;
      if(m_phase_reset_count >= confirm_need && m_phase_reset_pending != m_phase_reset_confirmed)
      {
         m_phase_reset_confirmed = m_phase_reset_pending;
         // STALE-ONLY reset: clear a RECOVERED cycle earned under the OLD phase
         // (genuinely stale), but PRESERVE an in-progress DETECTED pullback. A
         // pullback's bounce is often what reorders the EMAs and triggers the
         // phase change itself, so a full reset to NONE here would erase the
         // DETECTED half right at the pullback->recovery boundary, stranding the
         // layer at NONE through the entire recovery (recovery is reachable only
         // from DETECTED, and recovery bars are not themselves pullbacks). Keeping
         // DETECTED lets a pullback that began just before the new-phase
         // confirmation complete its recovery inside the new phase.
         // STEP12 2026-06: VPRR invariant. UpdateSingleLayerPullback's NONE
         // branch zeros vol_pb_avg/bars/vol_rec_avg/bars/vprr/baseline whenever
         // state reaches NONE through normal flow. External resets that set
         // state to NONE WITHOUT going through that branch must mirror that
         // cleanup, or a subsequent NONE→DETECTED transition will accumulate
         // the new pullback's pb_avg on top of the stale cycle's value
         // (contaminated VPRR ratio, depressed by carry-over). Same fix lives
         // in ResetAllLayerPullback (CLIMAX path).
         if(m_layer_w_pb_state == LAYER_PB_RECOVERED) {
            m_layer_w_pb_state    = LAYER_PB_NONE;
            m_layer_w_vol_pb_avg  = 0.0; m_layer_w_vol_pb_bars  = 0;
            m_layer_w_vol_rec_avg = 0.0; m_layer_w_vol_rec_bars = 0;
            m_layer_w_vprr        = 0.0;
            m_layer_w_baseline    = 0.0;
            m_layer_w_bars_det    = 0;   // A21 2026-07
         }
         if(m_layer_m_pb_state == LAYER_PB_RECOVERED) {
            m_layer_m_pb_state    = LAYER_PB_NONE;
            m_layer_m_vol_pb_avg  = 0.0; m_layer_m_vol_pb_bars  = 0;
            m_layer_m_vol_rec_avg = 0.0; m_layer_m_vol_rec_bars = 0;
            m_layer_m_vprr        = 0.0;
            m_layer_m_baseline    = 0.0;
            m_layer_m_bars_det    = 0;   // A21 2026-07
         }
         if(m_layer_s_pb_state == LAYER_PB_RECOVERED) {
            m_layer_s_pb_state    = LAYER_PB_NONE;
            m_layer_s_vol_pb_avg  = 0.0; m_layer_s_vol_pb_bars  = 0;
            m_layer_s_vol_rec_avg = 0.0; m_layer_s_vol_rec_bars = 0;
            m_layer_s_vprr        = 0.0;
            m_layer_s_baseline    = 0.0;
            m_layer_s_bars_det    = 0;   // A21 2026-07
         }
         if(m_settings.DebugFlow)
            DebugLog(StringFormat("[PHASE_RESET] Phase confirmed %s -> stale RECOVERED cleared, DETECTED preserved",
                                  EnumToString(m_phase_reset_confirmed)));
      }
   }

   //+------------------------------------------------------------------+
   //| UpdateLayerPullbackStates -- Update pullback state for all layers|
   //+------------------------------------------------------------------+
   //+------------------------------------------------------------------+
   //| CB_BodyOverExtended -- bias-agnostic body-spike at `shift`        |
   //| (the over-extension core of CandleBody; no direction/close-ratio).|
   //+------------------------------------------------------------------+
   bool CB_BodyOverExtended(int shift) { return CB_IsSpike(shift); }

   //+------------------------------------------------------------------+
   //| CB_IsSpike — the ONE correct over-extension (spike) test.        |
   //|                                                                   |
   //| A bar is a "spike" when its full range (high-low) exceeds        |
   //| SpikeMult × ATR(N), where ATR is measured over the N bars        |
   //| BEFORE the signal bar. ATR is a STABLE volatility reference that |
   //| does NOT collapse during consolidation — so a normal breakout    |
   //| candle (~1.5-2.5×ATR) PASSES, while a genuine news spike or      |
   //| blow-off (~4-6×ATR) is REJECTED. Self-scaling ATR makes this     |
   //| robust across every timeframe and instrument, unlike the old     |
   //| "body vs recent-average-body" rule which collapsed out of a      |
   //| consolidation and vetoed the very breakouts the RRM method takes.|
   //|                                                                   |
   //| Evaluates the SIGNAL BAR only (one bar = one spike). Reuses the   |
   //| existing CandleBody knobs so no new inputs are needed:            |
   //|    CandleBody_AvgPeriod → ATR period N      (use ~14-20)          |
   //|    CandleBody_MaxMult   → SpikeMult (× ATR) (use ~3)              |
   //+------------------------------------------------------------------+
   bool CB_IsSpike(int shift)
   {
      int base = (shift < 1) ? 1 : shift;
      int n    = (m_settings.CandleBody_AvgPeriod < 1) ? 1 : m_settings.CandleBody_AvgPeriod;
      double atr = ManualATR(n, base + 1);   // volatility of the bars BEFORE the signal bar
      if(atr <= 0.0) return false;           // no baseline yet → never block
      double rng = iHigh(m_symbol, PERIOD_CURRENT, base) - iLow(m_symbol, PERIOD_CURRENT, base);
      return (rng > m_settings.CandleBody_MaxMult * atr);
   }

   //+------------------------------------------------------------------+
   //| UpdateCBOverExtCarry (CBOEB) -- stateful CandleBody carry.        |
   //| When CB flags an over-extended bar, hold the CB vote at 0 until   |
   //| the next layer pullback-recovery (first of W/M/S to RECOVER).     |
   //| Edge-detected so a layer already recovered at trip-time does not  |
   //| clear it. Runs once per bar AFTER the layer states are current,   |
   //| so live and scanner advance identically.                         |
   //+------------------------------------------------------------------+
   void UpdateCBOverExtCarry(int v_shift)
   {
      if(!m_settings.Ind_CandleBody_Enabled || !m_settings.CandleBody_CarryOnOverext)
      {
         m_cb_oeb_blocked = false;
         return;
      }
      bool any_rec = (m_layer_w_pb_state == LAYER_PB_RECOVERED
                   || m_layer_m_pb_state == LAYER_PB_RECOVERED
                   || m_layer_s_pb_state == LAYER_PB_RECOVERED);
      bool fresh_rec = any_rec && !m_cb_prev_any_rec;
      if(CB_BodyOverExtended(v_shift))
         m_cb_oeb_blocked = true;                 // (re)arm on an over-extended bar
      else if(m_cb_oeb_blocked && fresh_rec)
         m_cb_oeb_blocked = false;                // clear on the next pullback-recovery
      m_cb_prev_any_rec = any_rec;
   }

   void UpdateLayerPullbackStates(int v_shift, int bias_dir = 0)
   {
      if(!m_settings.LayerPullbackEnabled) return;

      datetime bar_time = iTime(m_symbol, PERIOD_CURRENT, v_shift);
      if(m_layer_pb_last_update == bar_time) return;
      m_layer_pb_last_update = bar_time;

      // ── LONG/SHORT SYMMETRY: reset direction-dependent state on bias flip ──
      // Whenever the bias direction handed to this update differs from the
      // direction the engine's state machines were last advanced under
      // (including LONG↔SHORT flips AND transitions through neutral),
      // wipe ALL direction-dependent state so the new direction starts
      // from a clean baseline.
      //
      // This makes the EA's single-engine evaluation directionally
      // symmetric with SignalScan's two-engine model: in SignalScan, the
      // idle engine is reset every bar (lines 813-817 of SEA_IND_SignalScan.mq5),
      // so when a direction takes control its state is uncontaminated by
      // history under the opposite bias. ResetDirectionalState() provides
      // the same guarantee here in a single-engine form.
      //
      // The sentinel value 999 (set in constructor / Reset / warmup paths)
      // guarantees the first real call triggers a clean reset regardless
      // of starting bias.
      if(bias_dir != m_last_dir_state_bias)
      {
         if(m_settings.DebugFlow && m_last_dir_state_bias != 999)
            DebugLog(StringFormat("[DIR_SYMMETRY] Bias changed %d→%d — resetting direction-dependent state",
                                  m_last_dir_state_bias, bias_dir));
         // GUARD 1: ARM only on a GENUINE signed flip. This function is never called
         // with bias_dir == 0 (the UNO branch in EvaluateTS handles B==0 separately and
         // preserves m_last_dir_state_bias), so m_last_dir_state_bias only ever holds
         // ±1 or the 999 sentinel — which makes this test exactly "±1 → ∓1", i.e. the
         // spec's flip definition, with UNO transparent by construction.
         // The 999 sentinel is EA load / cold start, NOT a flip: arming there would make
         // the EA skip its first pullback-recovery after every load and optimisation pass.
         if(m_last_dir_state_bias != 999)
         {
            m_g1_armed = true;
            if(m_settings.DebugFlow && m_settings.Guard1_SkipFirstPostFlipPR)
               DebugLog(StringFormat("[GUARD1] Bias flip %d→%d — armed; first completed P-R cycle on each layer will be skipped",
                                     m_last_dir_state_bias, bias_dir));
         }
         ResetDirectionalState();   // zeroes the GUARD 1 cycle counters
         m_last_dir_state_bias = bias_dir;
      }

      MaybeResetLayersOnPhaseChange(v_shift);

      UpdateSingleLayerPullback(h_ema1, v_shift, GetLayerLookback(1), GetLayerRecovery(1),
                                m_layer_w_pb_state, m_layer_w_baseline, "LayerW",
                                m_layer_w_vol_pb_avg, m_layer_w_vol_pb_bars,
                                m_layer_w_vol_rec_avg, m_layer_w_vol_rec_bars, m_layer_w_vprr,
                                m_layer_w_bars_det, m_layer_w_bars_rec,
                                m_layer_w_g1_recov, m_layer_w_g1_counted, bias_dir,
                                h_ema2, m_settings.LayerPriceTouchEnabled, GetLayerMinPBBars(1), GetLayerWindow(1), m_settings.LayerRecoveryMaxAgeEnabled);
      UpdateSingleLayerPullback(h_ema2, v_shift, GetLayerLookback(2), GetLayerRecovery(2),
                                m_layer_m_pb_state, m_layer_m_baseline, "LayerM",
                                m_layer_m_vol_pb_avg, m_layer_m_vol_pb_bars,
                                m_layer_m_vol_rec_avg, m_layer_m_vol_rec_bars, m_layer_m_vprr,
                                m_layer_m_bars_det, m_layer_m_bars_rec,
                                m_layer_m_g1_recov, m_layer_m_g1_counted, bias_dir,
                                h_ema3, m_settings.LayerPriceTouchEnabled, GetLayerMinPBBars(2), GetLayerWindow(2), m_settings.LayerRecoveryMaxAgeEnabled);
      UpdateSingleLayerPullback(h_ema3, v_shift, GetLayerLookback(3), GetLayerRecovery(3),
                                m_layer_s_pb_state, m_layer_s_baseline, "LayerS",
                                m_layer_s_vol_pb_avg, m_layer_s_vol_pb_bars,
                                m_layer_s_vol_rec_avg, m_layer_s_vol_rec_bars, m_layer_s_vprr,
                                m_layer_s_bars_det, m_layer_s_bars_rec,
                                m_layer_s_g1_recov, m_layer_s_g1_counted, bias_dir,
                                h_ema4, m_settings.LayerPriceTouchEnabled, GetLayerMinPBBars(3), GetLayerWindow(3), m_settings.LayerRecoveryMaxAgeEnabled);

      UpdateCBOverExtCarry(v_shift);
   }

   //+------------------------------------------------------------------+
   //| GetActiveLayerVPRR — ratio for the layer that won (m_last_layer) |
   //+------------------------------------------------------------------+
   // m_last_layer is set by EvaluateL() which runs BEFORE EvaluateI(),
   // so the active layer is resolved by the time the voter calls this.
   double GetActiveLayerVPRR()
   {
      switch(m_last_layer)
      {
         case 1: return m_layer_w_vprr;
         case 2: return m_layer_m_vprr;
         case 3: return m_layer_s_vprr;
      }
      return 0.0;
   }

   //+------------------------------------------------------------------+
   //| Check_VPRR — voter: recovery volume must back the recovery       |
   //+------------------------------------------------------------------+
   bool Check_VPRR(int v_shift)
   {
      double active_vprr = GetActiveLayerVPRR();

      // Theme3 2026-06: resolve per-layer threshold; 0 = "use VPRR_MinRatio global".
      // Rationale: L1 (fastest, EMA1/EMA2) recovers in 1-3 bars on M1 metals — rarely
      // enough volume to differentiate, so a higher per-L1 threshold filters noise.
      // L3 (slowest, EMA3/EMA4) has multi-bar recoveries with more reliable signal;
      // a lower per-L3 threshold accepts more entries. Defaults of 0 preserve legacy
      // behavior (single VPRR_MinRatio for all layers).
      double layer_threshold = m_settings.VPRR_MinRatio;
      switch(m_last_layer)
      {
         case 1: if(m_settings.VPRR_MinRatio_W > 0.0) layer_threshold = m_settings.VPRR_MinRatio_W; break;
         case 2: if(m_settings.VPRR_MinRatio_M > 0.0) layer_threshold = m_settings.VPRR_MinRatio_M; break;
         case 3: if(m_settings.VPRR_MinRatio_S > 0.0) layer_threshold = m_settings.VPRR_MinRatio_S; break;
      }
      bool pass = (active_vprr >= layer_threshold);

      if(m_settings.DebugFlow)
      {
         double pb_avg = 0.0, rec_avg = 0.0;
         int pb_bars = 0, rec_bars = 0;
         switch(m_last_layer)
         {
            case 1: pb_avg=m_layer_w_vol_pb_avg; pb_bars=m_layer_w_vol_pb_bars; rec_avg=m_layer_w_vol_rec_avg; rec_bars=m_layer_w_vol_rec_bars; break;
            case 2: pb_avg=m_layer_m_vol_pb_avg; pb_bars=m_layer_m_vol_pb_bars; rec_avg=m_layer_m_vol_rec_avg; rec_bars=m_layer_m_vol_rec_bars; break;
            case 3: pb_avg=m_layer_s_vol_pb_avg; pb_bars=m_layer_s_vol_pb_bars; rec_avg=m_layer_s_vol_rec_avg; rec_bars=m_layer_s_vol_rec_bars; break;
         }
         // Theme3 2026-06: log shows the EFFECTIVE threshold (per-layer or global) so the
         // operator can see immediately which threshold is in force on this bar.
         string thr_source = (layer_threshold == m_settings.VPRR_MinRatio) ? "global" : "L-override";
         DebugLog(StringFormat("[IND_VPRR] L%d | Ratio=%.2f (Min=%.2f %s) | PB_vol=%.0f (%d bars) | REC_vol=%.0f (%d bars) | Src=%s | %s",
                               m_last_layer, active_vprr, layer_threshold, thr_source,
                               pb_avg, pb_bars, rec_avg, rec_bars,
                               m_vprr_last_real ? "REAL" : "TICK",
                               pass ? "PASS" : "FAIL"));
      }
      return pass;
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
      // Choppiness Index Formula (Dreiss / TradingView standard)
      // ══════════════════════════════════════════════════════════════════
      // CI = 100 * log10( Σ TR / (HH − LL) ) / log10(period)
      // Lower values (0-38.2) = strong trend
      // Higher values (61.8-100) = choppy/ranging market
      //
      // BUGFIX A7 2026-06: was `100 * log10(sum_tr) / log10(range)` which
      // divides by log10(range) instead of log10(period) and omits the
      // log10(sum_tr/range) ratio. The old formula produces values >100
      // whenever sum_tr > range^1 (common), clamped to 100 → CI voter
      // blocked nearly every bar as "ranging" when enabled.
      double ci = 100.0 * MathLog10(sum_tr / range) / MathLog10((double)period);
      
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

      double m = 0.0, s = 0.0;                          // A22: both reads must be ready
      if(!IndReadOK(h_macd, shift, 0, m) || !IndReadOK(h_macd, shift, 1, s)) {
         if(m_settings.DebugFlow)
            DebugLog(StringFormat("[IND_MACD] shift=%d not ready -> FAIL (uncached)", shift));
         return false;
      }
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
            if(bars_since == INT_MIN) return false;   // A22: not-ready -> reject, uncached
            base_pass = (bars_since >= 0 && bars_since <= m_settings.MacdFreshBars);
            break;
         }

         case MACD_ZERO_CROSS_N: {
            int bars_since_zero = GetBarsSinceMACDZeroCross(bias, shift);
            if(bars_since_zero == INT_MIN) return false;   // A22: not-ready -> reject, uncached
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
         double m_prev = 0.0;
         if(!IndReadOK(h_macd, shift + 1, 0, m_prev)) return false;   // A22: not-ready -> reject, uncached
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

      // Filter B: trend-exhaustion divergence (price vs MACD disagreement at trend extremes).
      // Theme5a-extension 2026-06: semantics inverted from pre-2026-06 (was "require divergence
      // to pass" with reversal-at-pullback-extremes logic; now "block if exhaustion divergence
      // present" with trend-extremes logic). See ST_Settings comment for full description.
      if(m_settings.MacdBlockOnDivergence) {
         bool div_ready = true;
         bool div = CheckMACDDivergence(bias, shift, div_ready);
         if(!div_ready) return false;   // A22: not-ready -> reject, uncached
         if(div) {
            if(m_settings.DebugFlow)
               DebugLog(StringFormat("[IND_MACD] bias=%d Main=%.5f Signal=%.5f → FAIL (%s exhaustion divergence)",
                                     bias, m, s, (bias == 1) ? "BEARISH" : "BULLISH"));
            m_ind_cache.cached_bias = bias;
            m_ind_cache.macd_main = m;
            m_ind_cache.macd_signal = s;
            m_ind_cache.macd_result = 0;
            return false;
         }
      }

      // Filter C: Hook (histogram reversal)
      if(m_settings.MacdRequireHook) {
         double hp_m = 0.0, hp_s = 0.0;
         if(!IndReadOK(h_macd, shift + 1, 0, hp_m) || !IndReadOK(h_macd, shift + 1, 1, hp_s))
            return false;   // A22: not-ready -> reject, uncached
         double h_prev = hp_m - hp_s;
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

      // Filter D: Histogram Deceleration (analogous to DPI_BlockOnDeceleration for RRM)
      // Blocks when the MACD histogram is shrinking bar-over-bar — momentum weakening
      // even though direction is still correct. Prevents entering into fading moves.
      // Condition: |h[shift]| < |h[shift+1]| AND both same sign (direction still holds).
      if(m_settings.MacdHistDecelEnabled) {
         double hp_m = 0.0, hp_s = 0.0;
         if(!IndReadOK(h_macd, shift + 1, 0, hp_m) || !IndReadOK(h_macd, shift + 1, 1, hp_s))
            return false;   // A22: not-ready -> reject, uncached
         double h_prev = hp_m - hp_s;
         bool same_sign = (h > 0 && h_prev > 0) || (h < 0 && h_prev < 0);
         if(same_sign && MathAbs(h) < MathAbs(h_prev)) {
            if(m_settings.DebugFlow)
               DebugLog(StringFormat("[IND_MACD] ENABLED | Main=%.5f Signal=%.5f | hist=%.6f prev=%.6f | Result: FAIL (hist decel — momentum shrinking)",
                                     m, s, h, h_prev));
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
         double m_curr = 0.0, s_curr = 0.0, m_prev = 0.0, s_prev = 0.0;
         if(!IndReadOK(h_macd, i,     0, m_curr) || !IndReadOK(h_macd, i,     1, s_curr) ||
            !IndReadOK(h_macd, i + 1, 0, m_prev) || !IndReadOK(h_macd, i + 1, 1, s_prev))
            return INT_MIN;   // A22: not-ready before a crossover was found -> caller fails-closed

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
         double m_curr = 0.0, m_prev = 0.0;
         if(!IndReadOK(h_macd, i, 0, m_curr) || !IndReadOK(h_macd, i + 1, 0, m_prev))
            return INT_MIN;   // A22: not-ready before a zero-cross was found -> caller fails-closed

         // Bullish: crosses above zero
         if(bias == 1 && m_prev <= 0 && m_curr > 0)
            return (i - shift);

         // Bearish: crosses below zero
         if(bias == -1 && m_prev >= 0 && m_curr < 0)
            return (i - shift);
      }
      return -1;  // No recent zero cross
   }

   // CheckMACDDivergence — Theme5a-extension 2026-06: TREND-EXHAUSTION semantics.
   //
   // Returns true when contra-trend exhaustion divergence is PRESENT (caller should
   // BLOCK the entry). Returns false when no divergence (safe to proceed) or when
   // computation can't be performed (warmup / insufficient bars — fail-safe permissive).
   //
   // Mirrors CheckDPIDivergence exactly (just substitutes the MACD main buffer for
   // the DPI histogram); both helpers use the same two-non-overlapping-windows pattern.
   //
   // Two windows of `lookback` bars each (configurable via Inp_RRM_ORG_MacdDivLookback):
   //   recent: bars [shift              .. shift +   lookback - 1]
   //   prior:  bars [shift +  lookback   .. shift + 2*lookback - 1]
   //
   // LONG (bias=1):  bearish divergence when price_high_recent > price_high_prior
   //                 AND macd_main at price_high_recent < macd_main at price_high_prior.
   //                 (Trend made new HH but momentum failed to confirm.)
   // SHORT (bias=-1): bullish divergence when price_low_recent < price_low_prior
   //                 AND macd_main at price_low_recent > macd_main at price_low_prior.
   //                 (Trend made new LL but momentum failed to confirm.)
   bool CheckMACDDivergence(int bias, int shift, bool &ready) {
      ready = true;   // A22: set false only on a genuine buffer read failure (not warmup/insufficient bars)
      int lookback = m_settings.MacdDivLookback;
      if(lookback < 3) return false;
      if(shift + 2 * lookback + 1 >= Bars(m_symbol, PERIOD_CURRENT)) return false;

      if(bias == 1) {
         // Two highest-high bars in non-overlapping windows
         int hi_r = iHighest(m_symbol, PERIOD_CURRENT, MODE_HIGH, lookback, shift);
         int hi_p = iHighest(m_symbol, PERIOD_CURRENT, MODE_HIGH, lookback, shift + lookback);
         if(hi_r < 0 || hi_p < 0) return false;
         double price_high_recent = iHigh(m_symbol, PERIOD_CURRENT, hi_r);
         double price_high_prior  = iHigh(m_symbol, PERIOD_CURRENT, hi_p);
         double macd_recent = 0.0, macd_prior = 0.0;
         if(!IndReadOK(h_macd, hi_r, 0, macd_recent) || !IndReadOK(h_macd, hi_p, 0, macd_prior)) { ready = false; return false; }

         // Bearish exhaustion divergence: new HH in price, lower MACD at the new HH.
         return (price_high_recent > price_high_prior && macd_recent < macd_prior);
      }

      if(bias == -1) {
         // Two lowest-low bars in non-overlapping windows
         int lo_r = iLowest(m_symbol, PERIOD_CURRENT, MODE_LOW, lookback, shift);
         int lo_p = iLowest(m_symbol, PERIOD_CURRENT, MODE_LOW, lookback, shift + lookback);
         if(lo_r < 0 || lo_p < 0) return false;
         double price_low_recent = iLow(m_symbol, PERIOD_CURRENT, lo_r);
         double price_low_prior  = iLow(m_symbol, PERIOD_CURRENT, lo_p);
         double macd_recent = 0.0, macd_prior = 0.0;
         if(!IndReadOK(h_macd, lo_r, 0, macd_recent) || !IndReadOK(h_macd, lo_p, 0, macd_prior)) { ready = false; return false; }

         // Bullish exhaustion divergence: new LL in price, higher MACD at the new LL.
         return (price_low_recent < price_low_prior && macd_recent > macd_prior);
      }

      return false;
   }

   // MACD Mode description: returns human-readable string for active MACD configuration
   string GetMACDModeDescription()
   {
      return ::GetMACDModeDescription(
         m_settings.MacdVoteMode,
         m_settings.MacdRequireSlope,
         m_settings.MacdBlockOnDivergence,
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

      double mfi = 0.0;
      if(!IndReadOK(h_mfi, shift, 0, mfi)) {          // A22: not ready -> reject, uncached
         if(m_settings.DebugFlow)
            DebugLog(StringFormat("[IND_MFI] shift=%d not ready -> FAIL (uncached)", shift));
         return false;
      }
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
   // ComputePSARManual — self-contained Wilder Parabolic SAR (fallback)
   //+------------------------------------------------------------------+
   // Runs ONLY when the iSAR handle read is not-ready (would return 0.0) at a
   // bar boundary. Computed from OHLC — which is populated before indicator
   // buffers — so it never yields the spurious 0.0 that used to make (cl>p)
   // pass every LONG and fail every SHORT. Uses the SAME Step/Max as the iSAR
   // handle. PSAR is self-correcting: after the first flip inside the warm-up
   // window the seed error washes out, so the value at `shift` tracks iSAR
   // closely. iSAR stays PRIMARY (exact chart parity); this is last-resort.
   double ComputePSARManual(int shift, bool &out_valid)
   {
      out_valid = false;
      double step  = m_settings.P_PsarStep;
      double maxaf = m_settings.P_PsarMax;
      if(step <= 0.0 || maxaf <= 0.0 || shift < 0) return 0.0;

      const int WARM = 300;                          // warm-up depth (PSAR self-corrects within it)
      int total = Bars(m_symbol, PERIOD_CURRENT);
      int start = shift + WARM;
      if(start > total - 2) start = total - 2;       // need bar start+1 to exist
      if(start <= shift) return 0.0;                 // insufficient history

      double h_s  = iHigh(m_symbol, PERIOD_CURRENT, start);
      double l_s  = iLow (m_symbol, PERIOD_CURRENT, start);
      double h_s1 = iHigh(m_symbol, PERIOD_CURRENT, start + 1);
      double l_s1 = iLow (m_symbol, PERIOD_CURRENT, start + 1);
      if(h_s <= 0.0 || l_s <= 0.0 || h_s1 <= 0.0 || l_s1 <= 0.0) return 0.0;

      bool   is_long = (h_s >= h_s1);                // initial trend guess (washes out)
      double af      = step;
      double ep      = is_long ? h_s  : l_s;         // extreme point
      double sar     = is_long ? l_s1 : h_s1;        // seed from prior-bar extreme

      for(int i = start - 1; i >= shift; i--)
      {
         double hi  = iHigh(m_symbol, PERIOD_CURRENT, i);
         double lo  = iLow (m_symbol, PERIOD_CURRENT, i);
         double hi1 = iHigh(m_symbol, PERIOD_CURRENT, i + 1);
         double lo1 = iLow (m_symbol, PERIOD_CURRENT, i + 1);
         if(hi <= 0.0 || lo <= 0.0 || hi1 <= 0.0 || lo1 <= 0.0) return 0.0;

         sar = sar + af * (ep - sar);

         if(is_long)
         {
            if(sar > lo1) sar = lo1;                 // SAR may not pierce prior/current low
            if(sar > lo)  sar = lo;
            if(hi > ep) { ep = hi; af = MathMin(af + step, maxaf); }
            if(lo < sar) { is_long = false; sar = ep; ep = lo; af = step; }   // flip to short
         }
         else
         {
            if(sar < hi1) sar = hi1;                 // SAR may not pierce prior/current high
            if(sar < hi)  sar = hi;
            if(lo < ep) { ep = lo; af = MathMin(af + step, maxaf); }
            if(hi > sar) { is_long = true; sar = ep; ep = hi; af = step; }    // flip to long
         }
      }
      out_valid = true;
      return sar;
   }

   //+------------------------------------------------------------------+
   // GetPSARValue — validity-checked read: iSAR primary, manual fallback
   //+------------------------------------------------------------------+
   // Guarantees a REAL SAR value or out_valid=false — never a silent 0.0.
   // Symmetric by construction: the identical value feeds LONG and SHORT.
   double GetPSARValue(int shift, bool &out_valid)
   {
      double p = GetVal(h_psar, shift, 0, out_valid);      // PRIMARY: iSAR (chart parity)
      if(out_valid && p > 0.0)
         return p;

      bool man_valid = false;                              // FALLBACK: manual Wilder SAR
      double pm = ComputePSARManual(shift, man_valid);
      if(man_valid && pm > 0.0)
      {
         if(m_settings.DebugFlow)
            DebugLog(StringFormat("[PSAR_READ] shift=%d iSAR not ready → manual SAR=%.5f", shift, pm));
         out_valid = true;
         return pm;
      }

      out_valid = false;                                   // both failed → caller must fail-closed
      return 0.0;
   }

   //+------------------------------------------------------------------+
   // Check_PSAR: PSAR (basic price vs. PSAR position check)
   //+------------------------------------------------------------------+
   bool Check_PSAR(int bias, int shift) {
      if(IsCacheValidForShift(shift) &&
         m_ind_cache.psar_result != -1 &&
         m_ind_cache.cached_bias == bias)
         return (m_ind_cache.psar_result == 1);

      bool   psar_valid = false;
      double p  = GetPSARValue(shift, psar_valid);        // iSAR primary, manual fallback
      double cl = iClose(m_symbol, PERIOD_CURRENT, shift);

      // A22 HARDENING — symmetric fail-closed. If neither iSAR nor the manual
      // fallback yields a valid dot (or the close is unavailable), BLOCK both
      // LONG and SHORT identically and DO NOT cache, so the next tick (data
      // ready) recomputes the true verdict. Removes the old asymmetry where an
      // unreadable read returned 0.0 → (cl > 0.0) passed every LONG while
      // (cl < 0.0) failed every SHORT.
      if(!psar_valid || p <= 0.0 || cl <= 0.0) {
         if(m_settings.DebugFlow)
            DebugLog(StringFormat("[PSAR_DOT_CHECK] shift=%d NOT READY (p=%.5f cl=%.5f) -> FAIL both dirs (uncached)",
                                  shift, p, cl));
         return false;
      }

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
      // BUGFIX A2: was `static datetime last_log_time = 0;` — static locals are
      // banned under the macOS/Wine/MQL5 constraint (persist across EA reinits).
      // Replaced with member m_psar_health_last_log (zeroed in constructor).
      datetime current_time = TimeCurrent();
      
      if(current_time - m_psar_health_last_log > 86400) { // Log once per day
         m_psar_health_last_log = current_time;
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

      double psar_curr = GetPSARValue(shift,     psar_curr_valid);   // iSAR primary, manual fallback
      double psar_prev = GetPSARValue(shift + 1, psar_prev_valid);

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
   // Call once per bar close to record the most recent flip.
   // At any moment at most ONE direction has a live timestamp — the most
   // recent flip. Writing one direction clears the opposite, because a
   // bull flip ends any prior bearish episode and vice versa. This makes
   // the state machine single-state ("here is the last flip and when it
   // happened") and removes stale counters from diagnostics.
   // Vote outcomes are unchanged — Check_PSAR_WithFlip's step 1 (dot side)
   // already rejected the cases where the cleared counter would have been
   // read, and PSAR_FlipGraceBars reads the freshly-written opposite-side
   // timestamp, never the cleared one.
   void UpdatePSARFlipTracking(int shift = 1) {
      if(m_settings.DebugFlow)
         DebugLog("[DEBUG_TEST] UpdatePSARFlipTracking() CALLED");
      int flip = DetectPSARFlipAt(shift);
      if(flip != 0) {
         datetime flip_time = iTime(m_symbol, PERIOD_CURRENT, shift);
         if(flip == 1) {
            m_psar_last_flip_time_bull = flip_time;
            m_psar_last_flip_time_bear = 0;   // opposite cleared by own flip
            if(m_settings.DebugFlow)
               DebugLog(StringFormat("[PSAR_FLIP_TRACK] BULLISH flip REGISTERED at %s | bear record cleared",
                                     TimeToString(flip_time, TIME_DATE|TIME_MINUTES)));
         }
         else if(flip == -1) {
            m_psar_last_flip_time_bear = flip_time;
            m_psar_last_flip_time_bull = 0;   // opposite cleared by own flip
            if(m_settings.DebugFlow)
               DebugLog(StringFormat("[PSAR_FLIP_TRACK] BEARISH flip REGISTERED at %s | bull record cleared",
                                     TimeToString(flip_time, TIME_DATE|TIME_MINUTES)));
         }
      }
   }

   //+------------------------------------------------------------------+
   // Get Bars Since Last Flip
   //+------------------------------------------------------------------+
   // Returns the number of bars elapsed since the last LIVE PSAR flip
   // record in the given bias direction, measured from current_shift.
   // Returns INT_MAX if no live record exists — either none has occurred
   // yet, or it was cleared when the opposite-direction flip occurred.
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
         // Stamp the sub-code so journal/cockpit readers don't pick up a stale
         // value from a previous bar/call. In persistent mode, a fail is always
         // "dot on wrong side" (no flip-aging logic applies), so use the DOT
         // catch-all (0). On pass, mirror the within-window pass code (3) for
         // consistency with the flip-mode path.
         m_ind_cache.psar_diag_sub    = (result ? 3 : 0);
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
         m_ind_cache.psar_diag_sub = 0;   // dot wrong side

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
            DebugLog(StringFormat("[PSAR_FLIP_CHECK] STEP 2: No live %s flip record",
                                  (bias > 0 ? "BULLISH" : "BEARISH")));
            DebugLog("[PSAR_FLIP_CHECK]    (either none seen yet, or it was cleared when the opposite-direction flip occurred)");
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
         m_ind_cache.psar_diag_sub = 1;   // no flip recorded

         if(m_settings.DebugFlow) {
            DebugLog("[PSAR_FLIP_CHECK] STEP 2 FAILED: NO LIVE FLIP RECORD");
            DebugLog(StringFormat("[PSAR_FLIP_CHECK]    No live %s flip — either none has occurred yet,",
                                  (bias > 0 ? "bullish" : "bearish")));
            DebugLog("[PSAR_FLIP_CHECK]    or it was cleared when the opposite-direction flip occurred.");
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
         // Internal error: flip_time is non-zero (passed step 2) but iBarShift
         // can't resolve it. Should not happen on healthy data; treat as a
         // catch-all reject so readers don't inherit a stale sub-code.
         m_ind_cache.psar_diag_sub = 0;

         if(m_settings.DebugFlow)
            DebugLog("[PSAR_FLIP_CHECK] STEP 3 FAILED: iBarShift returned invalid index");

          m_ind_cache.cached_bias = bias;
          m_ind_cache.psar_flip_result = 0;
          return false;
      }

      // 4. Flip-age check — GATE (enforces the TS equation).
      //
      // PSAR is a binary {0,1} factor of I; its evaluation mode determines HOW
      // it resolves to 0 or 1, but the output is always {0,1}, never advisory.
      // When flip+N-delay mode is active (effective_delay ∈ [0..10]):
      //
      //     PSAR = 1   iff   dot on correct side  AND  bars_since_flip ≤ N
      //     PSAR = 0   otherwise
      //
      // Mode recap:
      //   -1   = persistent      → handled at function top (fast-path)
      //    0   = flip bar only   → window of zero bars (bars_since must == 0)
      //   1..10 = N-bar window   → window of N bars (bars_since ∈ [0..N])
      //
      // Outside the window the flip-derived signal has expired by the user's
      // contract: a mature trend whose last flip is 6+ bars in the past gets
      // PSAR=0 unless the operator chose persistent (-1) mode for that layer.
      // (Layer-aware delays via GetEffectivePsarFlipDelay() let LayerW/M/S be
      // set to -1 if persistent behavior is desired for some layers.)
      if(bars_since > delay) {
         m_diag_last_reason = StringFormat("PSAR_FLIP_EXPIRED (bars_since=%d > delay=%d)",
                                           bars_since, delay);
         m_ind_cache.psar_diag_sub = 4;   // expired (outside N-window)

         if(m_settings.DebugFlow) {
            DebugLog("[PSAR_FLIP_CHECK] STEP 4 FAILED: FLIP EXPIRED");
            DebugLog(StringFormat("[PSAR_FLIP_CHECK]    %d bars elapsed > delay limit %d — outside N-window",
                                  bars_since, delay));
            DebugLog(StringFormat("[PSAR_FLIP_CHECK]    PSAR=0 (flip-derived signal has expired; use Vote_PsarFlipDelay=-1 for persistent mode)",
                                  bars_since, delay));
         }

         m_ind_cache.cached_bias       = bias;
         m_ind_cache.psar_flip_result  = 0;
         return false;
      }

      m_ind_cache.psar_diag_sub = 3;   // within N-window

      if(m_settings.DebugFlow) {
         DebugLog("[PSAR_FLIP_CHECK] STEP 4 PASSED: Within N-window");
         DebugLog(StringFormat("[PSAR_FLIP_CHECK]    %d bars elapsed ≤ delay limit %d (fresh)",
                               bars_since, delay));
      }

      // SUCCESS
      if(m_settings.DebugFlow) {
         DebugLog("[PSAR_FLIP_CHECK] ===========================================");
         DebugLog("[PSAR_FLIP_CHECK] ALL CHECKS PASSED");
         DebugLog(StringFormat("[PSAR_FLIP_CHECK]    %s flip from %s | within window (%d bars ago, N=%d)",
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
      double r = 0.0;
      if(!IndReadOK(h_rsi, shift, 0, r)) {            // A22: not ready -> reject, uncached
         if(m_settings.DebugFlow)
            DebugLog(StringFormat("[IND_RSI] shift=%d not ready -> FAIL (uncached)", shift));
         return false;
      }
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

      double k = 0.0, d = 0.0;                          // A22: both reads must be ready
      if(!IndReadOK(h_sto, shift, 0, k) || !IndReadOK(h_sto, shift, 1, d)) {
         if(m_settings.DebugFlow)
            DebugLog(StringFormat("[IND_STOCH] shift=%d not ready -> FAIL (uncached)", shift));
         return false;
      }
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

      // Get slope based on current vertical shift. Use GetMAValSafe so the
      // read routes through the ribbon snapshot (with manual fallback if
      // MT5 returns garbage). Refuse the gate if either read is invalid.
      bool ok_c, ok_p;
      double c = GetMAValSafe(hf, shift, ok_c);
      double p = GetMAValSafe(hf, shift + 1, ok_p);
      if(!ok_c || !ok_p) {
         if(m_settings.DebugFlow)
            DebugLog("[IND_ROSS] Bias EMA read invalid → FAIL");
         return false;
      }
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

      // A22: fail-closed on a not-ready ATR read (operator chose fail-closed for the
      // VRC vote, to match Check_ATR and the directional voters). GetVolatilityRegime()
      // itself still fail-opens (returns NORMAL) for any non-vote caller by design; here
      // the VOTE blocks instead. Uncached, so the next tick recomputes when data is ready.
      bool   atr_ok  = false;
      double atr_chk = GetVal(h_atr, 1, 0, atr_ok);
      if(!atr_ok || atr_chk <= 0.0) {
         if(m_settings.DebugFlow) DebugLog("VRC: ATR not ready -> FAIL (uncached)");
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

      // Ribbon snapshot: slots 1 and 2, current and previous bar.
      // Refuse the gate if any required slot is invalid on either bar.
      if(!GetEmaValid(1) || !GetEmaValid(2) ||
         !GetEmaValidPrev(1) || !GetEmaValidPrev(2))
      {
         m_ind_cache.sma_converge_result = 0;
         return false;
      }
      double e1_now  = GetEma1();
      double e2_now  = GetEma2();
      double e1_prev = GetEma1Prev();
      double e2_prev = GetEma2Prev();

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
      if(!m_settings.Ind_Fib_Enabled) return true;  // disabled = no opinion = pass

      // User-input clamp: Fib retracement math needs at least ~10 bars to
      // meaningfully resolve a swing. PREVIOUSLY: any value <10 silently
      // jumped to 50 (a hardcoded number that buried the user's intent —
      // someone setting Fib_SwingLookback=5 expecting tight swing detection
      // would unknowingly get a 50-bar lookback). Now we clamp to 10 (the
      // documented minimum) so the user's chosen value is honoured for every
      // legal setting >= 10 and the override is minimal & traceable when not.
      int lookback = m_settings.Fib_SwingLookback;
      if(lookback < 10) {
         if(m_settings.DebugFlow)
            DebugLog(StringFormat("[IND_FIB] WARN: Fib_SwingLookback=%d below minimum 10; clamped to 10. Set >= 10 to silence this warning.", lookback));
         lookback = 10;
      }

      int start = shift + 1;
      int total = iBars(m_symbol, PERIOD_CURRENT);
      if(start + lookback >= total) {
         if(m_settings.DebugFlow)
            DebugLog(StringFormat("[IND_FIB] FAIL: insufficient bars (need %d, have %d) — TS contract: enabled indicator with no data = 0",
                                  start + lookback + 1, total));
         return false;
      }

      int hi_idx = iHighest(m_symbol, PERIOD_CURRENT, MODE_HIGH, lookback, start);
      int lo_idx = iLowest(m_symbol, PERIOD_CURRENT, MODE_LOW, lookback, start);

      if(hi_idx < 0 || lo_idx < 0) {
         if(m_settings.DebugFlow)
            DebugLog("[IND_FIB] FAIL: no swing high/low detected in lookback window");
         return false;
      }

      double swing_high = iHigh(m_symbol, PERIOD_CURRENT, hi_idx);
      double swing_low  = iLow(m_symbol, PERIOD_CURRENT, lo_idx);
      double swing_range = swing_high - swing_low;

      if(swing_range <= 0.0) {
         if(m_settings.DebugFlow)
            DebugLog("[IND_FIB] FAIL: swing range is zero or negative");
         return false;
      }

      double current_close = iClose(m_symbol, PERIOD_CURRENT, shift);
      double ratio = 0.0;

      if(bias == 1)
      {
         // LONG: want a swing high formed BEFORE the swing low (down-leg first)?
         // No — we want a swing low formed FIRST, then swing high, then retracement.
         // i.e. lo_idx > hi_idx (lo is OLDER, hi is more recent). If hi_idx >= lo_idx,
         // the hi is older than the lo (down-leg is the recent move) → no LONG Fib setup.
         if(hi_idx >= lo_idx) {
            if(m_settings.DebugFlow)
               DebugLog("[IND_FIB] FAIL (LONG): swing-high precedes swing-low — no valid retracement setup");
            return false;
         }
         ratio = (swing_high - current_close) / swing_range;
      }
      else if(bias == -1)
      {
         // SHORT: want a swing high formed first (up-leg), then swing low (retracement).
         // i.e. hi_idx > lo_idx (hi is OLDER). If lo_idx >= hi_idx, the lo is older
         // than the hi (up-leg is the recent move) → no SHORT Fib setup.
         if(lo_idx >= hi_idx) {
            if(m_settings.DebugFlow)
               DebugLog("[IND_FIB] FAIL (SHORT): swing-low precedes swing-high — no valid retracement setup");
            return false;
         }
         ratio = (current_close - swing_low) / swing_range;
      }
      else {
         // Invalid bias (== 0); the indicator is enabled but has nothing to evaluate against.
         // Per TS contract: enabled with no decision = 0.
         if(m_settings.DebugFlow)
            DebugLog(StringFormat("[IND_FIB] FAIL: invalid bias=%d (must be ±1)", bias));
         return false;
      }

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
   //+------------------------------------------------------------------+
   //| CheckDPIDivergence — Theme5a 2026-06                             |
   //|                                                                  |
   //| Detects price-vs-DPI-histogram EXHAUSTION divergence in the bias |
   //| direction. Returns true when divergence is PRESENT (caller       |
   //| should BLOCK the entry). Returns false when no divergence (safe  |
   //| to proceed) OR when computation can't be performed (warmup /     |
   //| insufficient bars — fail-safe permissive on divergence, the      |
   //| underlying Check_DPI gates still apply).                         |
   //|                                                                  |
   //| Two non-overlapping windows of `lookback` bars each:             |
   //|   recent: bars [v_shift     .. v_shift +   lookback - 1]         |
   //|   prior:  bars [v_shift+lookback .. v_shift + 2*lookback - 1]    |
   //|                                                                  |
   //| LONG (bias=1):  bearish divergence when                          |
   //|   price_high_recent > price_high_prior  (still trending up)      |
   //|   AND dpi_hist at price_high_recent < dpi_hist at price_high_prior|
   //|       (momentum NOT confirming the new high)                     |
   //|                                                                  |
   //| SHORT (bias=-1): bullish divergence when                         |
   //|   price_low_recent  < price_low_prior  (still trending down)     |
   //|   AND dpi_hist at price_low_recent > dpi_hist at price_low_prior |
   //|       (momentum NOT confirming the new low)                      |
   //+------------------------------------------------------------------+
   bool CheckDPIDivergence(int bias, int v_shift, int lookback,
                           double &out_p_recent, double &out_p_prior,
                           double &out_d_recent, double &out_d_prior,
                           int    &out_b_recent, int    &out_b_prior)
   {
      out_p_recent = out_p_prior = out_d_recent = out_d_prior = 0.0;
      out_b_recent = out_b_prior = -1;

      // Need 2*lookback bars beyond v_shift plus headroom for DPI computation
      // (ComputeDPIMainHist needs ~MFast+MSlow+RedEMAs of history at any shift it's called).
      if(lookback < 3) return false;
      if(v_shift + 2 * lookback + 1 >= Bars(m_symbol, PERIOD_CURRENT)) return false;

      if(bias == 1)
      {
         // LONG: compare two highest-high bars
         int hi_r = iHighest(m_symbol, PERIOD_CURRENT, MODE_HIGH, lookback, v_shift);
         int hi_p = iHighest(m_symbol, PERIOD_CURRENT, MODE_HIGH, lookback, v_shift + lookback);
         if(hi_r < 0 || hi_p < 0) return false;
         double price_recent = iHigh(m_symbol, PERIOD_CURRENT, hi_r);
         double price_prior  = iHigh(m_symbol, PERIOD_CURRENT, hi_p);

         // Sample DPI histogram at each swing-high bar.
         double dpi_r = 0.0, dpi_p = 0.0;
         double _hp = 0.0;
         bool   _g  = false, _ma = false, _yc = false;
         double _gmc = 0.0, _gmp = 0.0;
         if(!ComputeDPIMainHist(hi_r, dpi_r, _hp, _g, _ma, _gmc, _gmp, _yc)) return false;
         if(!ComputeDPIMainHist(hi_p, dpi_p, _hp, _g, _ma, _gmc, _gmp, _yc)) return false;

         out_p_recent = price_recent; out_p_prior = price_prior;
         out_d_recent = dpi_r;        out_d_prior = dpi_p;
         out_b_recent = hi_r;         out_b_prior = hi_p;

         // Bearish divergence: new HH in price, lower DPI hist value at the new HH.
         return (price_recent > price_prior && dpi_r < dpi_p);
      }

      if(bias == -1)
      {
         // SHORT: compare two lowest-low bars
         int lo_r = iLowest(m_symbol, PERIOD_CURRENT, MODE_LOW, lookback, v_shift);
         int lo_p = iLowest(m_symbol, PERIOD_CURRENT, MODE_LOW, lookback, v_shift + lookback);
         if(lo_r < 0 || lo_p < 0) return false;
         double price_recent = iLow(m_symbol, PERIOD_CURRENT, lo_r);
         double price_prior  = iLow(m_symbol, PERIOD_CURRENT, lo_p);

         double dpi_r = 0.0, dpi_p = 0.0;
         double _hp = 0.0;
         bool   _g  = false, _ma = false, _yc = false;
         double _gmc = 0.0, _gmp = 0.0;
         if(!ComputeDPIMainHist(lo_r, dpi_r, _hp, _g, _ma, _gmc, _gmp, _yc)) return false;
         if(!ComputeDPIMainHist(lo_p, dpi_p, _hp, _g, _ma, _gmc, _gmp, _yc)) return false;

         out_p_recent = price_recent; out_p_prior = price_prior;
         out_d_recent = dpi_r;        out_d_prior = dpi_p;
         out_b_recent = lo_r;         out_b_prior = lo_p;

         // Bullish divergence: new LL in price, higher DPI hist value at the new LL.
         return (price_recent < price_prior && dpi_r > dpi_p);
      }

      return false;
   }

   bool Check_DPI(int bias, int v_shift)
   {
      if(!m_settings.Ind_Dpi_Enabled) return true;

      if(IsCacheValidForShift(v_shift) && m_ind_cache.cached_bias == bias && m_ind_cache.dpi_result != -1)
         return (m_ind_cache.dpi_result == 1);

      double hist_cur = 0.0, hist_prev = 0.0;
      bool   dpi_green = false, dpi_macd_agree = false, dpi_wants_yellow = false;
      double _unused_green_cur = 0.0, _unused_green_prev = 0.0;
      if(!ComputeDPIMainHist(v_shift, hist_cur, hist_prev, dpi_green, dpi_macd_agree,
                             _unused_green_cur, _unused_green_prev, dpi_wants_yellow))
      {
         // Insufficient bars for DPI computation (typically during warmup of
         // first ~550 bars). Per TS equation contract: an enabled indicator
         // with no decision = 0, never silently 1. If the operator wants the
         // EA to trade during DPI warmup, the proper switch is to disable DPI
         // (Ind_Dpi_Enabled=false), not to make this gate permissive.
         if(m_settings.DebugFlow)
            DebugLog(StringFormat("[IND_DPI] FAIL: insufficient bars for DPI computation at shift=%d (warmup)", v_shift));
         m_ind_cache.cached_bias = bias;
         m_ind_cache.dpi_result  = 0;
         return false;
      }

      // BASE = ribbon COLOUR vs bias (canonical §3): YELLOW→LONG(+1), RED→SHORT(-1).
      // Colour (dpi_wants_yellow) is lifted verbatim from mc_main; always ±1, no neutral (§8/O5).
      int  colour_dir = dpi_wants_yellow ? 1 : -1;
      bool base_ok    = (colour_dir == bias);
      // GREEN gate (canonical §6) — unchanged.
      bool green_ok   = (!m_settings.DPI_UseGreenHist || dpi_green);
      // CCI_RESET (canonical §5): reset→recovery requirement, owned by RequireResetRecovery
      // alone (decoupled from HistTrackingEnabled). Pass when off, or state == ENTRY_ALLOWED(3).
      bool reset_ok   = (!m_settings.DPI_RequireResetRecovery || m_dpi_reset_state == 3);
      // NOTE: the old same-bar hist-vs-CCI agreement gate is REMOVED (canonical §7);
      //       CCI now drives the ribbon colour inside ComputeDPIMainHist instead.

      // Theme5a 2026-06: DPI exhaustion-divergence sub-filter.
      // Evaluated AFTER the base gates so the diagnostic priority is preserved
      // (colour/green/reset failures dominate; divergence only matters when the
      // earlier gates would have passed). Failing here counts as a DPI fail with
      // its own sub-reason for cockpit / SignalScan attribution.
      bool div_ok = true;
      double div_p_r = 0.0, div_p_p = 0.0, div_d_r = 0.0, div_d_p = 0.0;
      int    div_b_r = -1,  div_b_p = -1;
      if(m_settings.DpiBlockOnDivergence)
      {
         bool divergence_present = CheckDPIDivergence(bias, v_shift,
                                                     m_settings.DpiDivLookback,
                                                     div_p_r, div_p_p,
                                                     div_d_r, div_d_p,
                                                     div_b_r, div_b_p);
         div_ok = !divergence_present;
      }

      bool result  = base_ok && green_ok && reset_ok && div_ok;

      m_ind_cache.cached_bias = bias;
      m_ind_cache.dpi_result  = result ? 1 : 0;
      m_ind_cache.dpi_diag_hist = hist_cur;
      m_ind_cache.dpi_diag_sub  = (!base_ok ? 1 : (!green_ok ? 3 : (!reset_ok ? 4 : (!div_ok ? 5 : 0))));
      m_ind_cache.dpi_diag_yellow = dpi_wants_yellow;

      if(m_settings.DebugFlow)
      {
         string sub = "";
         if(!base_ok)  sub = sub + "COLOUR_MISMATCH ";
         if(!green_ok) sub = sub + "NO_GREEN ";
         if(!reset_ok) sub = sub + "RESET_WAIT ";
         if(!div_ok)   sub = sub + "DIV_EXHAUSTION ";
         DebugLog(StringFormat("[IND_DPI] bias=%d hist=%.6f colour=%s green=%d reset_state=%d ignoreCCI=%s → %s%s",
                               bias, hist_cur, dpi_wants_yellow ? "YELLOW" : "RED",
                               dpi_green ? 1 : 0, m_dpi_reset_state,
                               m_settings.DPI_IgnoreCCIForVote ? "Y" : "N",
                               result ? "PASS" : "FAIL ",
                               result ? "" : ("(" + sub + ")")));
         if(!div_ok)
            DebugLog(StringFormat("[IND_DPI/DIV] %s divergence | bias=%d | price[%d]=%.5f vs price[%d]=%.5f | DPI[%d]=%.6f vs DPI[%d]=%.6f",
                                  (bias == 1) ? "BEARISH" : "BULLISH",
                                  bias, div_b_r, div_p_r, div_b_p, div_p_p,
                                  div_b_r, div_d_r, div_b_p, div_d_p));
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

   // Symbol-currency extraction for news filtering.
   //
   // Preferred path: MQL5's broker-canonical currency lookup
   // (SymbolInfoString SYMBOL_CURRENCY_BASE / SYMBOL_CURRENCY_PROFIT) — returns
   // ISO 4217 codes regardless of symbol-name format. Works for "GOLD", "BTCUSD",
   // broker-suffixed "EURUSD.r", and any other naming convention the broker uses.
   //
   // Fallback path (preserved from original): strip non-letters then take 3+3.
   // Triggered only when the broker hasn't populated the currency fields, which
   // is rare but possible on some custom CFD / index symbols. The fallback is
   // intentionally tolerant of broker suffixes (e.g. "EURUSD.a" → "EUR"/"USD"),
   // but for non-FX-style names (e.g. "GOLD") it may silently return empty —
   // the news filter then bypasses cleanly (IsNewsBlocked returns false on
   // empty base/quote, line 4519).
   void GetSymbolCurrencies(string sym, string &base, string &quote) {
      base = "";
      quote = "";

      // Step19-audit 2026-06: prefer broker-canonical lookup over name slicing.
      string b = SymbolInfoString(sym, SYMBOL_CURRENCY_BASE);
      string p = SymbolInfoString(sym, SYMBOL_CURRENCY_PROFIT);
      if(StringLen(b) >= 3 && StringLen(p) >= 3) {
         base  = b;
         quote = p;
         return;
      }

      // Fallback: alphabetic 3+3 slice (legacy path).
      // Keep only letters A-Z (tolerant of broker suffixes like "EURUSD.a").
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
      // F-AUDIT 2026-06: was hardcoded "block on low" / "pass on medium+/high".
      // Now consults m_settings.NewsImpactFilter (user-tunable):
      //   NEWS_IMPACT_ALL        — every event blocks (incl. low and unparsed/empty)
      //   NEWS_IMPACT_MED_PLUS   — medium+high block (legacy default; low ignored; empty=block)
      //   NEWS_IMPACT_HIGH_ONLY  — only high blocks
      // Empty impact strings (unparsed feed) treated as "relevant" for safety
      // under MED_PLUS (legacy); ALL also treats empty as relevant; HIGH_ONLY
      // does NOT block empty (no way to know if it's high).
      impact = TrimStr(impact);
      StringToLower(impact);

      switch(m_settings.NewsImpactFilter) {
         case NEWS_IMPACT_ALL:
            return true;   // every event blocks
         case NEWS_IMPACT_HIGH_ONLY:
            return (StringFind(impact, "high") == 0);
         case NEWS_IMPACT_MED_PLUS:
         default:
            if(impact == "") return true;                          // safety: unparsed = relevant
            if(StringFind(impact, "low") == 0) return false;       // low ignored
            return true;                                            // medium/high/other treated as relevant
      }
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
   int CheckLayerPairAlign(int bias, int layer_type) { return CheckLayerPairAlign(bias, layer_type, 1); }
   int CheckLayerPairAlign(int bias, int layer_type, int shift)
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

      // Route through ribbon snapshot via GetMAValSafe (handles iMA → manual
      // fallback for ribbon handles). Refuse on invalid — fails safe.
      bool ok_fast, ok_slow;
      double ema_fast      = GetMAValSafe(h_fast, shift, ok_fast);
      double ema_slow      = GetMAValSafe(h_slow, shift, ok_slow);
      if(!ok_fast || !ok_slow) {
         if(m_settings.DebugFlow)
            PrintFormat("[LayerAlign] %s: EMA read invalid (fast_ok=%d slow_ok=%d) → no alignment",
                        layer_label, (int)ok_fast, (int)ok_slow);
         return 0;
      }
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

      // ── Theme 2026-06: LayerS=TM-only phase gate ──
      // Canonical RRM Trade Setups card restricts Strong (LayerS, EMA3/EMA4) trades
      // to TRENDING phase only. The EMA3/EMA4 pair has its position swapped in
      // EM vs TM (e.g. EM_DN has EMA3>EMA4 while TM_DN has EMA3<EMA4), so a LayerS
      // pullback-recovery cycle that completes in EM is geometrically counter-trend
      // on its own EMA pair even though the position check above might pass during
      // the EM→TM transition. Block here to match the canonical rule.
      // Default off (legacy behavior); opt-in via Inp_RRM_ORG_LayerS_TMOnly.
      if(layer_type == 3 && m_settings.LayerS_TMOnly)
      {
         EMarketPhase ph_now = DetectMarketPhase(shift);
         bool is_tm = (ph_now == PHASE_TRENDING_UP || ph_now == PHASE_TRENDING_DN);
         if(!is_tm)
         {
            if(m_settings.DebugFlow)
               DebugLog(StringFormat("[%s] BLOCKED by LayerS_TMOnly: current phase %s is not TRENDING",
                                     layer_label, EnumToString(ph_now)));
            return 0;
         }
      }

      // ── Layer result: purely positional ──
      // Slope per bar is NOT checked here — it blocked entries on consolidating bars
      // even when all EMAs were correctly stacked (e.g. EMA1>EMA2>EMA3>EMA4 for LONG).
      // Positional alignment already covers counter-trend crossovers.
      // Bar-close direction is enforced separately by Eval_BarClose / Check_BarClose.
      int base_result = position_aligned ? 1 : 0;

      if(m_settings.LayerPullbackEnabled && base_result == 1)
      {
         // Gate logic:
         //   NONE     = no pullback seen yet → BLOCK (must earn recovery first)
         //   DETECTED = actively in pullback → BLOCK (wait for recovery)
         //   RECOVERED= pullback completed and trend resumed → ALLOW
         //
         // A trade is only valid after a confirmed pullback-recovery cycle.
         // NONE after reset (post-TS=1) means the cycle was consumed and a
         // fresh pullback is required before the next entry is allowed.
         // This prevents trend-extension entries with no preceding pullback.
         if(current_state != LAYER_PB_RECOVERED)
         {
            if(m_settings.DebugFlow)
               DebugLog(StringFormat("[%s] BLOCKED: no pullback-recovery cycle (State=%s)",
                                     layer_label, EnumToString(current_state)));
            return 0;
         }

         // ── GUARD 1 (2026-07): skip the FIRST completed post-flip P-R cycle ──────
         // Reached only when the layer is positionally aligned AND RECOVERED — i.e. on
         // a bar that would otherwise be entry-eligible. Event-indexed: the counter is
         // driven by cycle completions, never by a bar count. Per-layer, so W/M/S each
         // burn their own skip (P-R typically begins in W, then M, then S).
         // Hard block when enabled (no size-reduction variant), and inert until a
         // genuine ±1→∓1 flip has armed it.
         if(m_settings.Guard1_SkipFirstPostFlipPR && m_g1_armed)
         {
            int g1_n = (layer_type == 1) ? m_layer_w_g1_recov :
                       (layer_type == 2) ? m_layer_m_g1_recov : m_layer_s_g1_recov;
            if(g1_n <= 1)
            {
               m_eval_g1_blocked = true;   // so the reason reads L_G1_POSTFLIP, not L_NONE_ALIGNED
               if(m_settings.DebugFlow)
                  DebugLog(StringFormat("[%s] BLOCKED by GUARD1: first post-flip pullback-recovery (cycle %d of the current bias leg)",
                                        layer_label, g1_n));
               return 0;
            }
         }
      }

      if(m_settings.DebugFlow)
      {
         string pair_name = (layer_type == 1) ? "LayerW(EMA1/2)" :
                            (layer_type == 2) ? "LayerM(EMA2/3)" : "LayerS(EMA3/4)";
         PrintFormat("[LayerAlign] %s | bias=%d | fast=%.5f slow=%.5f | pos=%s → %s",
                     pair_name, bias, ema_fast, ema_slow,
                     position_aligned ? "OK" : "FAIL",
                     (base_result == 1) ? "PASS" : "REJECT");
      }

      return base_result;
   }

   //==========================================================================
   // Climax / Exhaustion Guard
   //   Blocks signals that land into an over-extended impulse and (optionally)
   //   resets ALL layer pullback-recovery states so a fresh cycle is required
   //   before the next entry. Detection is side-effect-free; the reset is
   //   performed explicitly by the caller via ResetAllLayerPullback().
   //==========================================================================
   double ManualATR(int period, int start_shift)
   {
      int p = MathMax(1, period);
      double sum = 0.0; int n = 0;
      for(int i = start_shift; i < start_shift + p; i++)
      {
         double h  = iHigh (m_symbol, PERIOD_CURRENT, i);
         double l  = iLow  (m_symbol, PERIOD_CURRENT, i);
         double pc = iClose(m_symbol, PERIOD_CURRENT, i + 1);
         if(h == 0.0 && l == 0.0) continue;
         double tr = MathMax(h - l, MathMax(MathAbs(h - pc), MathAbs(l - pc)));
         sum += tr; n++;
      }
      return (n > 0) ? sum / n : 0.0;
   }

   void ResetAllLayerPullback()
   {
      // STEP12 2026-06: extended to also clear VPRR volume metrics and baseline,
      // mirroring the invariant in UpdateSingleLayerPullback's NONE branch.
      // Previously only set pb_state to NONE, leaving stale vol_pb_avg/bars/
      // vol_rec_avg/bars/vprr/baseline behind — which then contaminated the
      // NEXT pullback cycle's measurement (depressed VPRR ratio). Same fix
      // lives in MaybeResetLayersOnPhaseChange (phase-change path).
      m_layer_w_pb_state    = LAYER_PB_NONE;
      m_layer_w_vol_pb_avg  = 0.0; m_layer_w_vol_pb_bars  = 0;
      m_layer_w_vol_rec_avg = 0.0; m_layer_w_vol_rec_bars = 0;
      m_layer_w_vprr        = 0.0;
      m_layer_w_baseline    = 0.0;
      m_layer_w_bars_det    = 0;   // A21 2026-07

      m_layer_m_pb_state    = LAYER_PB_NONE;
      m_layer_m_vol_pb_avg  = 0.0; m_layer_m_vol_pb_bars  = 0;
      m_layer_m_vol_rec_avg = 0.0; m_layer_m_vol_rec_bars = 0;
      m_layer_m_vprr        = 0.0;
      m_layer_m_baseline    = 0.0;
      m_layer_m_bars_det    = 0;   // A21 2026-07

      m_layer_s_pb_state    = LAYER_PB_NONE;
      m_layer_s_vol_pb_avg  = 0.0; m_layer_s_vol_pb_bars  = 0;
      m_layer_s_vol_rec_avg = 0.0; m_layer_s_vol_rec_bars = 0;
      m_layer_s_vprr        = 0.0;
      m_layer_s_baseline    = 0.0;
      m_layer_s_bars_det    = 0;   // A21 2026-07
      if(m_settings.DebugFlow)
         DebugLog("[CLIMAX] All layer pullback states reset -> NONE (await fresh pullback-recovery)");
   }

   //==========================================================================
   // ResetDirectionalState — long/short symmetry primitive
   //
   // Clears EVERY piece of engine state whose evolution depends on the trade
   // direction (LONG / SHORT). Called from UpdateLayerPullbackStates whenever
   // the current bar's bias differs from the bias under which this state was
   // last advanced — including LONG↔SHORT flips and transitions through
   // neutral (bias = 0).
   //
   // Rationale (symmetry contract):
   //   SignalScan instantiates TWO independent CSignalEngine objects, one
   //   per direction, and resets the idle one every bar (lines 813-817 of
   //   SEA_IND_SignalScan.mq5). The result is that whichever direction
   //   takes control starts from a clean state machine — its evaluation
   //   cannot be contaminated by the other direction's prior history.
   //   The EA uses a SINGLE engine for both directions, so without this
   //   reset, state machines that were advanced under LONG bias persist
   //   into the first SHORT bar (and vice versa), causing path-dependent
   //   asymmetry between the two evaluation directions.
   //
   //   This function is the architectural equivalent in a single-engine
   //   model: at the moment the engine switches direction, ALL
   //   direction-dependent state is cleared so the new direction's
   //   evaluation starts symmetrically.
   //
   // What is reset (direction-asymmetric state):
   //   • Layer pullback-recovery state machines (W / M / S)
   //   • Layer slope baselines
   //   • Layer VPRR volume tracking buffers
   //   • DPI CCI reset-recovery state machine (the frozen "trend colour
   //     to recover to" becomes stale on a direction flip)
   //   • CandleBody over-extension carry (tied to layer recovery, which
   //     is direction-dependent)
   //
   // What is NOT reset (already direction-symmetric):
   //   • PSAR flip timestamps — separate bull/bear variables
   //   • DPI histogram tracking — magnitude/sign reads through bias
   //   • Phase debounce — phase enum already encodes direction
   //   • All per-bar caches — invalidated on each new bar
   //
   // INVARIANT for future maintainers: any new engine member whose value
   // would differ between a LONG-context evaluation and a SHORT-context
   // evaluation of the SAME bar must be added to this function.
   //==========================================================================
   void ResetDirectionalState()
   {
      // Layer pullback-recovery state machines
      m_layer_w_pb_state = LAYER_PB_NONE;
      m_layer_m_pb_state = LAYER_PB_NONE;
      m_layer_s_pb_state = LAYER_PB_NONE;
      // Layer slope baselines
      m_layer_w_baseline = 0.0;
      m_layer_m_baseline = 0.0;
      m_layer_s_baseline = 0.0;
      // A21 2026-07: bars_det counters
      m_layer_w_bars_det = 0;
      m_layer_m_bars_det = 0;
      m_layer_s_bars_det = 0;
      // Layer VPRR volume tracking
      m_layer_w_vol_pb_avg  = 0.0; m_layer_w_vol_pb_bars  = 0;
      m_layer_w_vol_rec_avg = 0.0; m_layer_w_vol_rec_bars = 0;
      m_layer_w_vprr        = 0.0;
      m_layer_m_vol_pb_avg  = 0.0; m_layer_m_vol_pb_bars  = 0;
      m_layer_m_vol_rec_avg = 0.0; m_layer_m_vol_rec_bars = 0;
      m_layer_m_vprr        = 0.0;
      m_layer_s_vol_pb_avg  = 0.0; m_layer_s_vol_pb_bars  = 0;
      m_layer_s_vol_rec_avg = 0.0; m_layer_s_vol_rec_bars = 0;
      m_layer_s_vprr        = 0.0;
      // DPI CCI reset-recovery cycle (trend colour reference becomes stale)
      m_dpi_reset_state         = 0;
      m_dpi_reset_recovery_bars = 0;
      m_dpi_reset_colour_prev   = false;
      m_dpi_reset_colour_ref    = false;
      m_dpi_reset_initialized   = false;     // Re-seed colour_prev on next bar (cold-start guard)
      // CandleBody over-extension carry
      m_cb_oeb_blocked  = false;
      m_cb_prev_any_rec = false;
      // GUARD 1: completed-cycle counters are per-flip — zero them here. (Arming is NOT
      // done here: this function is also reached on the 999 sentinel, where no flip
      // occurred. The two flip call sites arm explicitly.)
      m_layer_w_g1_recov   = 0; m_layer_m_g1_recov   = 0; m_layer_s_g1_recov   = 0;
      m_layer_w_g1_counted = false; m_layer_m_g1_counted = false; m_layer_s_g1_counted = false;
   }

   // Returns true if an over-extended impulse in `bias` direction is detected
   // within the recent ClimaxGuard_Lookback window, measured against a
   // pre-impulse ATR baseline (so the impulse itself does not inflate it).
   bool DetectClimax(int bias, int shift)
   {
      if(!m_settings.ClimaxGuard_Enabled || bias == 0) return false;
      int K    = MathMax(1, m_settings.ClimaxGuard_Lookback);
      int atrp = MathMax(1, m_settings.ClimaxGuard_ATRPeriod);
      double atr = ManualATR(atrp, shift + K);   // baseline from bars BEFORE the window
      if(atr <= 0.0) return false;

      // (1) Single over-extended bar (full range, not just body) in bias direction.
      for(int i = shift; i < shift + K; i++)
      {
         double o = iOpen (m_symbol, PERIOD_CURRENT, i);
         double c = iClose(m_symbol, PERIOD_CURRENT, i);
         double h = iHigh (m_symbol, PERIOD_CURRENT, i);
         double l = iLow  (m_symbol, PERIOD_CURRENT, i);
         bool directional = (bias == 1) ? (c > o) : (c < o);
         if(directional && (h - l) > m_settings.ClimaxGuard_BarATRMult * atr)
         {
            if(m_settings.DebugFlow)
               DebugLog(StringFormat("[CLIMAX] bar[%d] range=%.5f > %.2fxATR(%.5f)",
                                     i, h - l, m_settings.ClimaxGuard_BarATRMult, atr));
            return true;
         }
      }

      // (2) Cumulative directional move over the window vs ATR.
      double c_now  = iClose(m_symbol, PERIOD_CURRENT, shift);
      double c_prev = iClose(m_symbol, PERIOD_CURRENT, shift + K);
      double move   = (bias == 1) ? (c_now - c_prev) : (c_prev - c_now);
      if(move > m_settings.ClimaxGuard_MoveATRMult * atr)
      {
         if(m_settings.DebugFlow)
            DebugLog(StringFormat("[CLIMAX] move(%d bars)=%.5f > %.2fxATR(%.5f)",
                                  K, move, m_settings.ClimaxGuard_MoveATRMult, atr));
         return true;
      }
      return false;
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
      // Per TS equation contract: an enabled momentum factor with degenerate
      // inputs (single bar or no bias) cannot confirm momentum, so returns 0.
      if(bars <= 1 || bias == 0) return false;

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
   // ── Scanner API — thin public wrappers for SEA_IND_SignalScan ────
   // These expose selected private functions needed by the scanner
   // indicator without changing the engine's internal structure.
   void   Scanner_UpdateLayerPullback(int shift, int dir = 0) { UpdateLayerPullbackStates(shift, dir); }
   void   Scanner_UpdatePSARFlip(int shift)      { if(m_settings.Ind_Psar_Enabled) UpdatePSARFlipTracking(shift); }
   void   Scanner_UpdateDPIHistogramState(int shift) { UpdateDPIHistogramState(shift); }  // replays DPI reset-recovery/decel state per bar (no-op when tracking off)

   //==========================================================================
   // Scanner_InspectBar — single-bar diagnostic for the SignalScan inspector.
   // Computes the bias at `shift` (EvaluateB) and evaluates every TS factor
   // INDEPENDENTLY (no short-circuit) so the caller can show the full row.
   // Each out-param: 1 = pass, 0 = fail, -1 = N/A (only when bias=0 → B blocks).
   // out_CG: 1 = pass (no climax), 0 = blocked by climax. Returns final TS (1/0).
   // Must be called while the engine's layer/PSAR/DPI state is current for `shift`
   // (i.e. from inside the chronological scan), exactly like EvaluateTS_AtShift.
   //==========================================================================
   int Scanner_InspectBar(int shift, int &out_bias, int &out_P, int &out_L,
                          int &out_I, int &out_F, int &out_CG,
                          string &out_P_reason, string &out_L_reason,
                          string &out_I_reason, string &out_F_reason,
                          int &out_L_layer)
   {
      int bb = EvaluateB(shift);
      out_bias = bb;
      out_P_reason = ""; out_L_reason = ""; out_I_reason = ""; out_F_reason = ""; out_L_layer = 0;
      if(bb == 0) { out_P = out_L = out_I = out_F = out_CG = -1; return 0; }
      STSBreakdown b;
      int verdict = EvaluateTS_Breakdown(shift, bb, b, true);   // full breakdown; passive (no reset)
      out_P = b.P; out_F = b.F; out_L = b.L; out_I = b.I; out_CG = b.CG;
      out_P_reason = b.P_reason; out_L_reason = b.L_reason;
      out_I_reason = b.I_reason; out_F_reason = b.F_reason;
      out_L_layer  = b.L_layer;
      return verdict;
   }

   //+------------------------------------------------------------------+
   //| Scanner_InspectLayers / Inspect_OneLayer                         |
   //| Per-layer state + verdict for W/M/S INDEPENDENTLY (read-only).   |
   //| Mirrors the EvaluateL gate per layer without the priority short- |
   //| circuit, so the inspector can show all three layers at once.     |
   //+------------------------------------------------------------------+
   void Scanner_InspectLayers(int shift, int bias, string &out_w, string &out_m, string &out_s)
   {
      out_w = Inspect_OneLayer(shift, bias, 1);
      out_m = Inspect_OneLayer(shift, bias, 2);
      out_s = Inspect_OneLayer(shift, bias, 3);
   }
   string Inspect_OneLayer(int shift, int bias, int layer)
   {
      ELayerPullbackState st = (layer==1) ? m_layer_w_pb_state :
                               (layer==2) ? m_layer_m_pb_state : m_layer_s_pb_state;
      string st_s = (st==LAYER_PB_RECOVERED) ? "REC" : (st==LAYER_PB_DETECTED) ? "DET" : "NONE";

      bool allow = (layer==1) ? m_settings.AllowLayer1_Entries :
                   (layer==2) ? m_settings.AllowLayer2_Entries : m_settings.AllowLayer3_Entries;
      if(!allow)     return st_s + " off";
      if(bias == 0)  return st_s + " NO(bias)";

      m_eval_g1_blocked = false;
      int align = CheckLayerPairAlign(bias, layer, shift);   // position + RECOVERED + GUARD1 gates
      if(align == 0)
      {
         if(m_eval_g1_blocked) return st_s + " NO(G1)";   // GUARD 1: first post-flip P-R cycle
         return (st != LAYER_PB_RECOVERED) ? st_s + " NO(PB)" : st_s + " NO(ALIGN)";
      }

      int layer_id = (layer==1) ? LAYER_1_WEAK : (layer==2) ? LAYER_2_MEDIUM : LAYER_3_STRONG;
      int lookback = MathMax(1, MathMin(4, m_settings.BarClose_LookbackBars));
      int bc = Eval_BarClose(shift, bias, layer_id);
      if(bc == 0 && lookback > 1)
         bc = Check_BarClose_MultiBar(shift, bias, layer_id, lookback) ? 1 : 0;
      if(bc == 0) return st_s + " NO(BC)";

      if(!CheckCandleDirectionGate(bias, shift)) return st_s + " NO(BD)";

      bool mom = true;
      if(lookback > 1 && m_settings.Require_Progressive_Momentum)
      {
         mom = Check_Progressive_Momentum(shift, bias, lookback);
         if(!mom && m_settings.DPI_Histogram_Growth_Boost)
            mom = Check_DPI_Histogram_Growing(shift, bias, lookback);
      }
      if(!mom) return st_s + " NO(MOM)";

      return st_s + " ok";
   }
   // Reset only the fired layer to NONE — other layers keep their independent states.
   void   Scanner_ResetLayerAfterFire(int layer)
   {
      if(layer == 3) { m_layer_s_pb_state = LAYER_PB_NONE; m_layer_s_bars_det = 0; }   // A21 2026-07
      else if(layer == 2) { m_layer_m_pb_state = LAYER_PB_NONE; m_layer_m_bars_det = 0; }
      else if(layer == 1) { m_layer_w_pb_state = LAYER_PB_NONE; m_layer_w_bars_det = 0; }
   }
   // Expire RECOVERED states when bias is absent — prevents stale state firing on bias return.
   // Preserves DETECTED so an in-progress pullback keeps tracking through brief bias gaps.
   void   Scanner_ExpireRecovered()
   {
      if(m_layer_s_pb_state == LAYER_PB_RECOVERED) { m_layer_s_pb_state = LAYER_PB_NONE; m_layer_s_bars_det = 0; }   // A21 2026-07
      if(m_layer_m_pb_state == LAYER_PB_RECOVERED) { m_layer_m_pb_state = LAYER_PB_NONE; m_layer_m_bars_det = 0; }
      if(m_layer_w_pb_state == LAYER_PB_RECOVERED) { m_layer_w_pb_state = LAYER_PB_NONE; m_layer_w_bars_det = 0; }
   }
   bool   Scanner_Check_DPI(int bias, int shift) { return Check_DPI(bias, shift); }
   bool   Scanner_Check_PSAR(int bias, int shift){ return Check_PSAR(bias, shift); }
   bool   Scanner_Check_PSAR_Flip(int bias, int shift) { return Check_PSAR_WithFlip(bias, shift); }
   bool   Scanner_Check_MTF(int bias, int shift = 1) { return Check_MTF(bias, shift); }
   bool   Scanner_Check_ADX(int shift)           { return Check_ADX(shift); }
   bool   Scanner_Check_ATR(int bias, int shift) { return Check_ATR(bias, shift); }
   bool   Scanner_Check_BB(int bias, int shift)  { return Check_BB(bias, shift); }
   bool   Scanner_Check_CandleBody(int bias, int shift) { return Check_CandleBody(bias, shift); }
   bool   Scanner_DetectClimax(int bias, int shift)     { return DetectClimax(bias, shift); }
   void   Scanner_ResetAllLayerPullback()               { ResetAllLayerPullback(); }

   // Shift-aware PHASE_AGE: require the phase at `shift` to have persisted for
   // MinPhaseConfirmBars consecutive bars. Mirrors the EA's m_diag_phase_confirm_bars
   // gate, computed directly from DetectMarketPhase so it is valid at any shift.
   bool PhaseAgeConfirmed(int shift)
   {
      int need = m_settings.MinPhaseConfirmBars;
      if(need <= 0) return true;
      EMarketPhase ph = DetectMarketPhase(shift);
      for(int i = shift + 1; i <= shift + need - 1; i++)
         if(DetectMarketPhase(i) != ph) return false;
      return true;
   }

   //==========================================================================
   // EvaluateF — shared F factor (pre-filters). Faithful, decision-only mirror
   // of the inline TS_PREFILTER blocks in EvaluateTS. Returns true = pass.
   // Each filter is gated by its own (default-off) flag, so EvaluateF is a no-op
   // under RRM_ORG/CUSTOM defaults — behaviour-preserving until a filter is
   // explicitly enabled. The two state-machine filters (DPI reset-recovery and
   // DPI histogram-decel) read state that the caller must keep current for
   // `shift`: the EA via per-tick UpdateDPIHistogramState, SignalScan via the
   // per-bar Scanner_UpdateDPIHistogramState replay in its chronological scan.
   //==========================================================================
   bool EvaluateF(int shift, int bias)
   {
      m_last_f_reason = "";   // which sub-filter blocked (for caller telemetry); "" = passed

      // F-AUDIT 2026-06: Time / News / Spread checks REMOVED from this function.
      // Rationale: these are execution-moment (live-context) gates that the
      // architecture intentionally evaluates at TE-time (SEA_TradeExecutor::EvaluateF)
      // — TS at shift=1 (bar close) can't meaningfully replay live spread or
      // live news context. The previous block here was guarded by `if(shift == 0)`
      // and so was only ever reachable from Scanner_InspectBar (when called with
      // shift=0), which made its presence misleading. The TE-side EvaluateF is
      // the single source of truth for Time/News/Spread rejection counters
      // (bridged into m_stats via Signal.AddTeStats() at OnDeinit).

      // ── EMA fan over-extension (stateless) ──
      if(m_settings.EmaFanFilterEnabled && (m_settings.EmaFanMaxTotalPips > 0.0 || m_settings.EmaFanMaxPct > 0.0))
      {
         double pip  = GlobalPipSize(m_symbol);
         // Ribbon snapshot: slots 1 and 4, current and previous bar.
         // Per design: pass-through (don't block) when any required slot is
         // invalid. Phase/bias/layer gates already refuse on invalid data;
         // the fan filter blocking on top of those would be redundant.
         bool fan_data_ok = GetEmaValid(1) && GetEmaValid(4) &&
                            GetEmaValidPrev(1) && GetEmaValidPrev(4);
         double e1_1 = fan_data_ok ? GetEma1()     : 0.0;
         double e4_1 = fan_data_ok ? GetEma4()     : 0.0;
         double e1_2 = fan_data_ok ? GetEma1Prev() : 0.0;
         double e4_2 = fan_data_ok ? GetEma4Prev() : 0.0;
         if(fan_data_ok && e1_1 > 0.0 && e4_1 > 0.0 && e1_2 > 0.0 && e4_2 > 0.0)
         {
            if(m_settings.EmaFanMaxPct > 0.0)
            {
               double mid_now  = (e1_1 + e4_1) / 2.0;
               double mid_prev = (e1_2 + e4_2) / 2.0;
               if(mid_now > 0.0 && mid_prev > 0.0)
               {
                  double pct_now  = MathAbs(e1_1 - e4_1) / mid_now  * 100.0;
                  double pct_prev = MathAbs(e1_2 - e4_2) / mid_prev * 100.0;
                  if(pct_now > m_settings.EmaFanMaxPct && pct_now > pct_prev) { m_last_f_reason = "EMA_OVEREXT"; return false; }
               }
            }
            else if(pip > 0.0)
            {
               double gap_now  = MathAbs(e1_1 - e4_1) / pip;
               double gap_prev = MathAbs(e1_2 - e4_2) / pip;
               if(gap_now > m_settings.EmaFanMaxTotalPips && gap_now > gap_prev) { m_last_f_reason = "EMA_OVEREXT"; return false; }
            }
         }
      }

      // -- Price over-extension: distance of close from a reference EMA (ATR units) --
      //    Blocks late entries where price is stretched far from the trend mean in the
      //    bias direction -- the dimension EMA-fan width, CandleBody and Climax all miss.
      if(m_settings.PriceExtFilterEnabled && m_settings.PriceExtMaxATR > 0.0)
      {
         int rh = h_ema3;
         if(m_settings.PriceExtRefEma == 1)      rh = h_ema1;
         else if(m_settings.PriceExtRefEma == 2) rh = h_ema2;
         else if(m_settings.PriceExtRefEma == 4) rh = h_ema4;
         // Read ref EMA via snapshot. Filter is pass-through on invalid
         // (don't block when we lack confident evidence to block).
         bool ok_ref;
         double pe_ref = GetMAValSafe(rh, shift, ok_ref);
         double pe_atr = ManualATR(m_settings.PriceExtAtrPeriod, shift);
         double pe_cls = iClose(m_symbol, PERIOD_CURRENT, shift);
         if(ok_ref && pe_ref > 0.0 && pe_atr > 0.0 && pe_cls > 0.0)
         {
            double pe_dist = (bias == 1) ? (pe_cls - pe_ref) : (pe_ref - pe_cls);  // +ve = stretched in bias dir
            if(pe_dist > m_settings.PriceExtMaxATR * pe_atr) { m_last_f_reason = "PRICE_OVEREXT"; return false; }
         }
      }

      // ── DPI GREEN momentum deceleration (stateless) ──
      if(m_settings.DpiDecelFilterEnabled && m_settings.Ind_Dpi_Enabled)
      {
         double hist_cur = 0.0, hist_prev = 0.0;
         bool   dpi_green = false, dpi_macd_agree = false, dpi_wants_yellow = false;
         double green_mag_cur = 0.0, green_mag_prev = 0.0;
         if(ComputeDPIMainHist(shift, hist_cur, hist_prev, dpi_green, dpi_macd_agree, green_mag_cur, green_mag_prev, dpi_wants_yellow))
         {
            bool green_was = (green_mag_prev > 0.0);
            bool green_is  = (green_mag_cur  > 0.0);
            if(green_was && green_is && green_mag_cur < green_mag_prev) { m_last_f_reason = "DPI_DECEL"; return false; } // shrinking
            if(green_was && !green_is)                                  { m_last_f_reason = "DPI_DECEL"; return false; } // disappeared
         }
      }

      // ── DPI CCI reset-recovery gate ──
      // MOVED into Check_DPI (canonical §5): RESET_RECOVERY is now part of the DPI vote itself
      // (so the scanner verdict and inspector show it too), gated by RequireResetRecovery alone.
      // No separate TS-level gate here anymore.

      // ── DPI histogram deceleration (state) ──
      if(m_settings.DPI_BlockOnDeceleration && m_settings.DPI_HistTrackingEnabled)
         if(m_dpi_hist_decelerating) { m_last_f_reason = "DPI_DECEL"; return false; }

      // ── Phase-age confirmation (reconstructed shift-aware) ──
      // F-AUDIT 2026-06: now also requires RequireMinPhaseConfirm, matching the
      // GetBias_4EMA_Direction gate (SEA_SignalEngine.mqh:~7091). Previously F
      // gated on MinPhaseConfirmBars > 0 alone, so TI users with
      // RequireMinPhaseConfirm=false but MinPhaseConfirmBars > 0 saw F block
      // (PHASE_AGE) even though B explicitly skipped the confirm.
      if(m_settings.RequireMinPhaseConfirm && m_settings.MinPhaseConfirmBars > 0)
         if(!PhaseAgeConfirmed(shift)) { m_last_f_reason = "PHASE_AGE"; return false; }

      // ── Climax / exhaustion guard (F-AUDIT 2026-06: was separate factor CG) ──
      // Merged into F as the final sub-filter per the SimpleEA equation
      // simplification (TS = B × P × F × L × I). DetectClimax is itself
      // side-effect-free; the ResetAllLayerPullback side effect is applied
      // by the EA-side callers (EvaluateTS, EvaluateTS_AtShift) when they
      // see F_reason == "CLIMAX_GUARD". Scanner_InspectBar (passive) does
      // NOT trigger the reset.
      if(m_settings.ClimaxGuard_Enabled && DetectClimax(bias, shift))
      {
         m_last_f_reason = "CLIMAX_GUARD";
         return false;
      }

      return true;
   }

//==========================================================================
   // EvaluateTS_Breakdown — THE single TS decision core (one source of truth).
   //   Evaluates P*F*L*I (+climax) at `shift` for the supplied `bias` (B) and
   //   fills `b` with each factor's outcome. Returns 1 iff every factor passes
   //   and climax does not veto. PURE: no telemetry, no layer reset (the climax
   //   reset side effect is the caller's responsibility). EvaluateL runs before
   //   EvaluateI (m_last_layer dependency).
   //   full_eval=false → waterfall (stop at first failing factor; later factors
   //   stay -1), the fast verdict path. full_eval=true → evaluate every factor
   //   and climax (stats / inspector). The verdict is identical either way.
   //==========================================================================
   int EvaluateTS_Breakdown(int shift, int bias, STSBreakdown &b, bool full_eval)
   {
      b.P = -1; b.P_reason = ""; b.F = -1; b.F_reason = "";
      b.L = -1; b.L_reason = ""; b.L_layer = 0; b.I = -1; b.I_reason = ""; b.CG = -1;
      
      if(bias == 0) return 0;

      b.P = EvaluateP(shift, bias);
      if(b.P == 0) b.P_reason = m_diag_last_reason;   // read-only capture for the inspector
      if(b.P == 0 && !full_eval) return 0;

      b.F = EvaluateF(shift, bias) ? 1 : 0;
      b.F_reason = (b.F == 1 ? "" : m_last_f_reason);
      if(b.F == 0 && !full_eval) return 0;

      b.L = EvaluateL(shift, bias);
      if(b.L == 0) b.L_reason = m_diag_last_reason;
      b.L_layer = m_last_layer;   // winning layer (1=W/2=M/3=S) for the inspector
      if(b.L == 0 && !full_eval) return 0;

      // SURGICAL FIX: Structural Context Gate
      // Prevents EvaluateI from executing (and improperly inflating telemetry 
      // rejection counters) on bars that have already failed higher-priority 
      // structural context (P, F, or L), even during a forced full_eval sweep.
      if(b.P == 1 && b.F == 1 && b.L == 1)
      {
         b.I = EvaluateI(shift, bias);
         if(b.I == 0) b.I_reason = m_diag_i_fails;
         if(b.I == 0 && !full_eval) return 0;
      }
      else
      {
         // If structural factors failed, indicator evaluation is fundamentally invalid.
         // Suppress evaluation and tag the structural bypass.
         b.I = -1; 
         b.I_reason = "SUPPRESSED_BY_STRUCTURE";
      }

      // F-AUDIT 2026-06: Climax merged into F (TS = B × P × F × L × I).
      // EvaluateF now runs DetectClimax as its final sub-filter and emits
      // F_reason="CLIMAX_GUARD" on block. b.CG is kept for inspector backward
      // compatibility — it now mirrors "was F blocked specifically by climax?".
      b.CG = (b.F == 0 && b.F_reason == "CLIMAX_GUARD") ? 0 : 1;

      return (b.P == 1 && b.F == 1 && b.L == 1 && b.I == 1) ? 1 : 0;
   }

   //==========================================================================
   // EvaluateTS_AtShift — scanner/EA verdict accessor: thin waterfall wrapper
   // over the shared core. Applies the climax layer-reset side effect (the EA's
   // stateful behavior); the inspector path (Scanner_InspectBar) does not (it
   // stays passive by not going through this wrapper).
   // F-AUDIT 2026-06: Climax now reported via b.F=0 with F_reason="CLIMAX_GUARD"
   // (merged into F). b.CG mirrors this for inspector backward compat.
   //==========================================================================
   int EvaluateTS_AtShift(int shift, int bias)
   {
      STSBreakdown b;
      int verdict = EvaluateTS_Breakdown(shift, bias, b, false);   // waterfall
      // Climax veto detected via F → apply layer reset (EA stateful behavior).
      if(b.F == 0 && b.F_reason == "CLIMAX_GUARD" && m_settings.ClimaxGuard_ResetPullback)
         ResetAllLayerPullback();
      return verdict;
   }
   int GetLastLayer() const { return m_last_layer; }
   bool   Scanner_Check_CCI(int bias, int shift) { return Check_CCI(bias, shift); }
   bool   Scanner_Check_VPRR(int shift)          { return Check_VPRR(shift); }
   bool   Scanner_Check_CI(int bias, int shift)  { return Check_CI(bias, shift); }
   bool   Scanner_Check_MACD(int bias, int shift){ return Check_MACD(bias, shift); }
   bool   Scanner_Check_MFI(int bias, int shift) { return Check_MFI(bias, shift); }
   bool   Scanner_Check_RSI(int bias, int shift) { return Check_RSI(bias, shift); }
   bool   Scanner_Check_Sto(int bias, int shift) { return Check_Sto(bias, shift); }
   bool   Scanner_Check_P123(int bias, int shift){ return Check_P123(bias, shift); }
   bool   Scanner_Check_Ross(int bias, int shift){ return Check_Ross(bias, shift); }
   bool   Scanner_Check_VRC(int bias, int shift) { return Check_VRC(bias, shift); }
   bool   Scanner_Check_SmaConv(int shift)       { return Check_SmaConverge(shift); }
   bool   Scanner_Check_Fib(int bias, int shift) { return Check_Fib(bias, shift); }
   // ─────────────────────────────────────────────────────────────────
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
      int tf1_bias  = GetMTFBias(h_mtf_tf1_fast, h_mtf_tf1_slow, m_settings.MTF_TF1, 1);
      int tf2_bias  = 0;

      bool single_tf_mode = (h_mtf_tf2_fast == INVALID_HANDLE ||
                             m_settings.MTF_TF2 == PERIOD_CURRENT ||
                             m_settings.MTF_TF2 == m_settings.MTF_TF1);

      if(!single_tf_mode)
         tf2_bias = GetMTFBias(h_mtf_tf2_fast, h_mtf_tf2_slow, m_settings.MTF_TF2, 1);

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
      // VPRR telemetry for the cockpit panel
      m_telemetry.vprr_enabled    = m_settings.VPRR_Enabled;
      m_telemetry.vprr_ratio      = GetActiveLayerVPRR();
      m_telemetry.vprr_min_ratio  = m_settings.VPRR_MinRatio;
      m_telemetry.vprr_pass       = (m_telemetry.vprr_ratio >= m_settings.VPRR_MinRatio);
      m_telemetry.vprr_vol_source = m_vprr_last_real ? "REAL" : "TICK";
      // A14/A20 2026-07: i_suppressed = true when L failed structurally (no layer aligned),
      // meaning I was never evaluated. Detected by L_NONE_ALIGNED reason string.
      m_telemetry.i_suppressed = (m_diag_last_reason == "L_NONE_ALIGNED");
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
      // STEP7 2026-06: m_diag_last_atr_pips reset removed (field deleted, dead-code cleanup)

      // Initialize phase diagnostics
      m_diag_last_phase = PHASE_UNORDERED;
      m_diag_phase_confirm_bars = 0;
      m_phase_reset_pending   = PHASE_UNORDERED;
      m_phase_reset_confirmed = PHASE_UNORDERED;
      m_phase_reset_count     = 0;
      m_bars_since_uno_exit   = 999999;   // sentinel — counts non-UNO bars since last UNO
      m_uno_run               = 0;        // no UNO run in progress at (re)init
      m_cb_oeb_blocked  = false;
      m_cb_prev_any_rec = false;
      // Session-once flag for DPI cold-start first-entry grant. Set here in
      // the constructor only — never cleared by Init() or ResetDirectionalState.
      // A fresh EA load is the one and only event that resets it.
      m_dpi_first_entry_consumed = false;
      // Directional state symmetry tracker — sentinel = uninitialized.
      // First call to UpdateLayerPullbackStates() will trigger a clean
      // ResetDirectionalState() regardless of bias direction.
      m_last_dir_state_bias = 999;

      // GUARD 1: not armed until a genuine ±1→∓1 flip is observed (live or in the
      // warm-up replay). Cold start is not a flip.
      m_g1_armed           = false;
      m_eval_g1_blocked    = false;
      m_layer_w_g1_recov   = 0; m_layer_m_g1_recov   = 0; m_layer_s_g1_recov   = 0;
      m_layer_w_g1_counted = false; m_layer_m_g1_counted = false; m_layer_s_g1_counted = false;

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
      m_psar_health_last_log     = 0;   // BUGFIX A2: replaces static local

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
   int    GetDPIResetState()       const { return m_dpi_reset_state; }
   int    GetDPIResetRecoveryBars()const { return m_dpi_reset_recovery_bars; }

   // Called after a trade is taken to reset the cycle back to IDLE
   void   ResetDPIResetState()
   {
      // Called by SimpleEA right after a successful trade execution. Three jobs:
      //   1. Reset the reset→recovery state machine to IDLE so the next entry
      //      must observe a fresh colour-flip + recovery cycle (the gate's
      //      between-trades discipline).
      //   2. Clear the cold-start "initialized" flag so the next bar re-seeds
      //      colour_prev from the live ribbon (prevents stale seed bias).
      //   3. Mark the cold-start first-entry grant as consumed — so the
      //      cold-start guard's pre-arming branch is permanently dormant for
      //      the rest of the session. Subsequent cold-starts (after bias-flip
      //      resets, etc.) re-seed colour_prev but DO NOT pre-arm state=3.
      m_dpi_reset_state          = 0;
      m_dpi_reset_recovery_bars  = 0;
      m_dpi_reset_initialized    = false;
      m_dpi_first_entry_consumed = true;
   }

   //+------------------------------------------------------------------+
   //| Layer Pullback-Recovery Diagnostic Getters                       |
   //+------------------------------------------------------------------+
   ELayerPullbackState GetLayerWPullbackState() const { return m_layer_w_pb_state; }
   ELayerPullbackState GetLayerMPullbackState() const { return m_layer_m_pb_state; }
   ELayerPullbackState GetLayerSPullbackState() const { return m_layer_s_pb_state; }
   double              GetLayerWBaseline()      const { return m_layer_w_baseline; }
   double              GetLayerMBaseline()      const { return m_layer_m_baseline; }
   double              GetLayerSBaseline()      const { return m_layer_s_baseline; }

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
                   int pass_open_delay, int pass_bc_recheck, int pass_spread_median,
                   int rej_time = 0,    int pass_time = 0,
                   int rej_news = 0,    int pass_news = 0,
                   int rej_spread = 0,  int pass_spread = 0)
   {
      m_stats.rejected_te_open_delay     += rej_open_delay;
      m_stats.rejected_te_bc_recheck     += rej_bc_recheck;
      m_stats.rejected_te_spread_median  += rej_spread_median;
      m_stats.passed_te_open_delay       += pass_open_delay;
      m_stats.passed_te_bc_recheck       += pass_bc_recheck;
      m_stats.passed_te_spread_median    += pass_spread_median;
      // F-AUDIT 2026-06: T/N/S counters were previously dead (only EvaluateFilterX
      // bumped them, no callers). Now sourced from CTradeExecutor::EvaluateF
      // where the actual gates run.
      m_stats.rejected_time              += rej_time;
      m_stats.passed_time                += pass_time;
      m_stats.rejected_news              += rej_news;
      m_stats.passed_news                += pass_news;
      m_stats.rejected_spread            += rej_spread;
      m_stats.passed_spread              += pass_spread;
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

      // Read ribbon from snapshot (single source of truth). Diagnostic only —
      // displays "INVALID" markers per slot rather than refusing to format.
      double e1 = GetEmaValid(1) ? GetEma1() : 0.0;
      double e2 = GetEmaValid(2) ? GetEma2() : 0.0;
      double e3 = GetEmaValid(3) ? GetEma3() : 0.0;
      double e4 = GetEmaValid(4) ? GetEma4() : 0.0;

      string diag = "";

      // EMA values with price distance in pips (annotate INVALID when slot bad)
      string e1_disp = GetEmaValid(1) ? StringFormat("%.5f(%+.1fp)", e1, (price - e1) / pip) : "INVALID";
      string e2_disp = GetEmaValid(2) ? StringFormat("%.5f(%+.1fp)", e2, (price - e2) / pip) : "INVALID";
      string e3_disp = GetEmaValid(3) ? StringFormat("%.5f(%+.1fp)", e3, (price - e3) / pip) : "INVALID";
      string e4_disp = GetEmaValid(4) ? StringFormat("%.5f(%+.1fp)", e4, (price - e4) / pip) : "INVALID";
      diag += StringFormat("EMA1(%d)=%s EMA2(%d)=%s\n",
                           m_settings.P_Ema1, e1_disp,
                           m_settings.P_Ema2, e2_disp);
      diag += StringFormat("EMA3(%d)=%s EMA4(%d)=%s\n",
                           m_settings.P_Ema3, e3_disp,
                           m_settings.P_Ema4, e4_disp);

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
      PrintGateStat("Time Window", m_settings.TradingHoursEnabled, m_stats.passed_time, m_stats.rejected_time,
                    m_settings.TradingHoursEnabled ? StringFormat("London:%s NY:%s Asia:%s",
                       m_settings.Session_London ? "on" : "off",
                       m_settings.Session_NY     ? "on" : "off",
                       m_settings.Session_Asia   ? "on" : "off") : "(disabled)");
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
                       ? (m_settings.EmaFanMaxPct > 0.0
                          ? StringFormat("%.3f%% max", m_settings.EmaFanMaxPct)
                          : StringFormat("%.1f pips max", m_settings.EmaFanMaxTotalPips))
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
      // F-AUDIT 2026-06: PriceExt + Climax rows (previously counted only in m_reject_filter, no breakdown)
      PrintGateStat("Price OverExt",
                    m_settings.PriceExtFilterEnabled,
                    m_stats.passed_priceext,
                    m_stats.rejected_priceext,
                    m_settings.PriceExtFilterEnabled
                       ? StringFormat("%.2f x ATR(%d) on EMA%d", m_settings.PriceExtMaxATR, m_settings.PriceExtAtrPeriod, m_settings.PriceExtRefEma)
                       : "(disabled)");
      PrintGateStat("Climax Guard",
                    m_settings.ClimaxGuard_Enabled,
                    m_stats.passed_climax,
                    m_stats.rejected_climax,
                    m_settings.ClimaxGuard_Enabled
                       ? StringFormat("lookback=%d ATR=%d barx%.1f movex%.1f", m_settings.ClimaxGuard_Lookback, m_settings.ClimaxGuard_ATRPeriod, m_settings.ClimaxGuard_BarATRMult, m_settings.ClimaxGuard_MoveATRMult)
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
                  m_stats.rejected_phase_age + m_stats.rejected_priceext +
                  m_stats.rejected_climax,                                   // F-AUDIT 2026-06: PriceExt + Climax now counted
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
      PrintIndicatorStat("VPRR",         m_settings.VPRR_Enabled,    m_stats.passed_vprr,         m_stats.rejected_vprr);
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
      int shift = m_settings.Vote_EvalShift;   // single source: SAME bar the vote uses (was ma_v_shift)
      count = 0;
      // Sized for every voter EvaluateIndicatorX can cast: ADX, MACD, RSI, CCI,
      // MFI, Sto, BB, PSAR, P123, Ross, ATR, CBody, CI, VRC, SmaConv, DPI, Fib,
      // MTF, VPRR = 19 voters. +1 spare to prevent overflow if a future voter
      // is added before the array is grown. Previously sized for 17; would
      // overflow once Fib/MTF/VPRR rows were added (added 2026-06).
      ArrayResize(out, 20);
      
      // (v_shift kept == Vote_EvalShift for the few checks already written to it)
      int v_shift = m_settings.Vote_EvalShift;

      if(m_settings.Ind_Adx_Enabled && h_adx != INVALID_HANDLE)
      {
         // COCKPIT PARITY: call Check_ADX (same function the eval uses) so the
         // pass/fail reflects ADX_Mode (STATIC / DYNAMIC_PERCENTILE / PHASE_AWARE)
         // exactly as evaluated. Previously this compared raw ADX to
         // m_cachedADXThreshold inline — which was stale on the first display
         // pass and silently diverged whenever ADX_Mode logic was extended.
         bool pass = Check_ADX(shift);
         double adx = m_ind_cache.adx_value;        // populated by Check_ADX
         double thr = m_cachedADXThreshold;          // populated by Check_ADX
         out[count].name    = "ADX";
         out[count].enabled = true;
         if(pass && m_diag_last_bias ==  1) { out[count].state = "BUY";  out[count].reason = StringFormat("(ADX=%.0f>=%.0f)", adx, thr); }
         else if(pass && m_diag_last_bias == -1) { out[count].state = "SELL"; out[count].reason = StringFormat("(ADX=%.0f>=%.0f)", adx, thr); }
         else                               { out[count].state = "FLAT"; out[count].reason = StringFormat("(ADX=%.0f%s%.0f)", adx, pass?">=":"<", thr); }
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
         count++;
      }

      if(m_settings.Ind_Psar_Enabled && h_psar != INVALID_HANDLE)
      {
         // COCKPIT PARITY FIX: EvaluateIndicatorX selects between Check_PSAR_WithFlip
         // (when Vote_AllowPsarFlip=true) and plain Check_PSAR. Plain Check_PSAR
         // is just "dot-on-side"; the flip-mode version additionally enforces a
         // PsarFlipDelay window and can reject with sub-codes DOT / NoF / EXP
         // (dot-wrong-side / no-flip-yet / flip-expired). The cockpit previously
         // always called plain Check_PSAR, which on sustained trends showed
         // PSAR(-) "passing for SHORT" while the eval was rejecting with EXP.
         // Mirror the eval's selector here so the row matches reality.
         bool b, s;
         if(m_settings.Vote_AllowPsarFlip) {
            b = Check_PSAR_WithFlip( 1, shift);
            s = Check_PSAR_WithFlip(-1, shift);
         } else {
            b = Check_PSAR( 1, shift);
            s = Check_PSAR(-1, shift);
         }
         double p = GetVal(h_psar, shift);
         out[count].name    = "PSAR";
         out[count].enabled = true;
         if(b)      { out[count].state = "BUY";  out[count].reason = StringFormat("(dot=%.5f<price)", p); }
         else if(s) { out[count].state = "SELL"; out[count].reason = StringFormat("(dot=%.5f>price)", p); }
         else       {
            // When flip-mode rejects, expose the sub-code so the cockpit
            // tells you WHY (not just "no signal"). Matches the corrected
            // setter/journal scheme: 1=NoF (no flip yet), 4=EXP (flip aged
            // out), else (0)=DOT (wrong side). NOTE: 2 is unused — mirrors
            // dpi_diag_sub's value scheme. Was previously reading == 2 for
            // EXP (which never fires), fixed 2026-06 in lockstep with the
            // journal reject reporter.
            string why = "(no signal)";
            if(m_settings.Vote_AllowPsarFlip) {
               int sub = m_ind_cache.psar_diag_sub;
               why = (sub == 1 ? "(NoF: no flip yet)" :
                      sub == 4 ? "(EXP: flip aged out)" :
                                 "(DOT: wrong side)");
            }
            out[count].state = "FLAT"; out[count].reason = why;
         }
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
         count++;
      }

      // ATR (volatility regime – non-directional vote)
      // COCKPIT PARITY: call Check_ATR (same function eval uses, hits same cache).
      // Previously duplicated the Min/Max comparison inline — risked divergence
      // if Check_ATR ever gained additional gating (e.g. regime-aware bounds).
      if(m_settings.Ind_Atr_Enabled && h_atr != INVALID_HANDLE)
      {
         bool pass = Check_ATR(current_bias, shift);
         double atr_pips = AtrPips();  // STEP7 2026-06: was m_diag_last_atr_pips (dead 0.0); now live read
         out[count].name    = "ATR";
         out[count].enabled = true;
         if(pass) { out[count].state = (current_bias == 1 ? "BUY" : (current_bias == -1 ? "SELL" : "FLAT")); out[count].reason = StringFormat("(ATR=%.1fpips ok)", atr_pips); }
         else     { out[count].state = "FLAT"; out[count].reason = StringFormat("(ATR=%.1fpips out-of-range [%.1f..%.1f])", atr_pips, m_settings.ATR_VoteMinPips, m_settings.ATR_VoteMaxPips); }
         count++;
      }

      // CandleBody (overextension filter – non-directional vote)
      // COCKPIT PARITY FIX: previously called CheckCandleBodyIndicator() directly,
      // which evaluates only the current bar's shape and ignores the CBOEB
      // (Candle-Body Over-Extension Block) carry state. The real TS vote in
      // EvaluateIndicatorX uses Check_CandleBody(), which DOES apply the carry:
      // once a bar trips CB_BodyOverExtended, m_cb_oeb_blocked stays armed until
      // the next layer pullback-recovery clears it, holding CBody at FAIL for
      // every intervening bar. The cockpit must mirror that or it will show
      // "CBody(-)" (passing for SHORT) while VOTE reads 2/3 with no visible
      // reason. Calling Check_CandleBody here aligns display with eval.
      if(m_settings.Ind_CandleBody_Enabled)
      {
         bool pass = Check_CandleBody(current_bias, shift);
         out[count].name    = "CBody";
         out[count].enabled = true;
         if(pass) { out[count].state = (current_bias == 1 ? "BUY" : (current_bias == -1 ? "SELL" : "FLAT")); out[count].reason = "(body ok)"; }
         else     { out[count].state = "FLAT"; out[count].reason = (m_cb_oeb_blocked ? "(OEB carry armed)" : "(overextended)"); }
         count++;
      }

      // Choppiness Index (ranging market filter – non-directional vote)
      // COCKPIT PARITY: call Check_CI (same function eval uses, hits same cache).
      if(m_settings.Ind_CI_Enabled)
      {
         bool pass = Check_CI(current_bias, shift);
         double ci_val = CalculateCI(shift);   // diagnostic only; cheap with cache
         out[count].name    = "CI";
         out[count].enabled = true;
         if(pass) { out[count].state = (current_bias == 1 ? "BUY" : (current_bias == -1 ? "SELL" : "FLAT")); out[count].reason = StringFormat("(CI=%.1f trending, thr=%.1f)", ci_val, m_settings.CI_RangingThreshold); }
         else     { out[count].state = "FLAT"; out[count].reason = StringFormat("(CI=%.1f ranging, thr=%.1f)", ci_val, m_settings.CI_RangingThreshold); }
         count++;
      }

      // VRC (low volatility filter – non-directional vote)
      // COCKPIT PARITY: call Check_VRC (same function eval uses).
      if(m_settings.Ind_VRC_Enabled && h_atr != INVALID_HANDLE)
      {
         bool pass = Check_VRC(current_bias, shift);
         EVolatilityRegime regime = GetVolatilityRegime();
         double atr = GetVal(h_atr, shift, 0);

         out[count].name    = "VRC";
         out[count].enabled = true;
         if(pass) {
            out[count].state  = (current_bias == 1 ? "BUY" : (current_bias == -1 ? "SELL" : "FLAT"));
            out[count].reason = StringFormat("(%s volatility ATR=%.5f)", EnumToString(regime), atr);
         } else {
            out[count].state  = "FLAT";
            out[count].reason = StringFormat("(LOW volatility ATR=%.5f)", atr);
         }
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
         count++;
      }

      // Fib (swing-retracement zone voter – directional)
      // COCKPIT COMPLETENESS: was silently missing from the cockpit voter row
      // (and therefore from the voter total count display) even though
      // EvaluateIndicatorX casts it. Added 2026-06.
      if(m_settings.Ind_Fib_Enabled)
      {
         bool b = Check_Fib( 1, v_shift);
         bool s = Check_Fib(-1, v_shift);
         out[count].name    = "Fib";
         out[count].enabled = true;
         if(b && !s)      { out[count].state = "BUY";  out[count].reason = StringFormat("(swing %d bars)", m_settings.Fib_SwingLookback); }
         else if(s && !b) { out[count].state = "SELL"; out[count].reason = StringFormat("(swing %d bars)", m_settings.Fib_SwingLookback); }
         else             { out[count].state = "FLAT"; out[count].reason = "(no valid retracement setup)"; }
         count++;
      }

      // MTF (higher-timeframe confluence – directional)
      // COCKPIT COMPLETENESS: was silently missing from the voter row even
      // though EvaluateIndicatorX casts it (a dedicated MTF: line in the panel
      // header shows the filter state but did not contribute to the voter row
      // and was easy to confuse with the cockpit voter total). Added 2026-06.
      if(m_settings.Ind_MTF_Enabled)
      {
         bool b = Check_MTF( 1, v_shift);
         bool s = Check_MTF(-1, v_shift);
         out[count].name    = "MTF";
         out[count].enabled = true;
         if(b && !s)      { out[count].state = "BUY";  out[count].reason = StringFormat("(%s/%s align)", EnumToString(m_settings.MTF_TF1), EnumToString(m_settings.MTF_TF2)); }
         else if(s && !b) { out[count].state = "SELL"; out[count].reason = StringFormat("(%s/%s align)", EnumToString(m_settings.MTF_TF1), EnumToString(m_settings.MTF_TF2)); }
         else             { out[count].state = "FLAT"; out[count].reason = "(HTF mismatch or insufficient data)"; }
         count++;
      }

      // VPRR (volume pullback-recovery ratio – non-directional)
      // COCKPIT COMPLETENESS: a dedicated VPRR: detail row exists below the
      // voter line, but VPRR was missing from the voter row itself so the
      // voter total could read fewer than the EvaluateIndicatorX denominator.
      // Adding here too keeps the voter row's count equal to the eval's.
      // Added 2026-06.
      if(m_settings.VPRR_Enabled)
      {
         bool pass = Check_VPRR(v_shift);
         out[count].name    = "VPRR";
         out[count].enabled = true;
         if(pass) { out[count].state = (current_bias == 1 ? "BUY" : (current_bias == -1 ? "SELL" : "FLAT")); out[count].reason = StringFormat("(ratio %.2f >= %.2f)", GetActiveLayerVPRR(), m_settings.VPRR_MinRatio); }
         else     { out[count].state = "FLAT"; out[count].reason = StringFormat("(ratio %.2f < %.2f)", GetActiveLayerVPRR(), m_settings.VPRR_MinRatio); }
         count++;
      }
      ArrayResize(out, count);
   }


   //+------------------------------------------------------------------+
   //| WarmUpLayerPullbackStates                                        |
   //| Replay historical bars to reconstruct the correct pullback state |
   //| at startup. Without this, all layers start NONE and block the    |
   //| first valid signal even when a pullback-recovery cycle already   |
   //| completed in recent history.                                     |
   //|                                                                  |
   //| Scan depth: LayerBaselineLookback + 60 bars. The baseline needs  |
   //| N bars of history to establish direction; the extra 60 bars      |
   //| covers a full pullback + recovery cycle at any reasonable TF.   |
   //| Replay is oldest-first (high shift → low shift) so state machine |
   //| transitions accumulate correctly.                                |
   //|                                                                  |
   //| HAND-OFF TO LIVE EVALUATION (fix history):                       |
   //|   Previously the warmup left m_last_dir_state_bias = 999, which  |
   //|   made the very first live UpdateLayerPullbackStates() call hit  |
   //|   ResetDirectionalState() and wipe every layer state, baseline,  |
   //|   VPRR accumulator, DPI reset state, and CB carry — discarding   |
   //|   the entire warmup. The fix:                                    |
   //|   (1) pass the bar's actual bias_dir into UpdateSingleLayerPull- |
   //|       back so warmup uses the SAME spec-faithful recovery test   |
   //|       (close vs fast EMA) that live evaluation uses, AND         |
   //|   (2) seed m_last_dir_state_bias from the most-recent historical |
   //|       bar's bias so the first live bar's bias_dir matches and    |
   //|       no ResetDirectionalState wipe is triggered.                |
   //|   The B==0 SOFT-reset rule applied in EvaluateTS (only layer     |
   //|   states cleared, baselines/VPRR/DPI/CB preserved) is mirrored   |
   //|   here for UNO/NEUTRAL bars so warmup and live behave identically.|
   //+------------------------------------------------------------------+
   void WarmUpLayerPullbackStates()
   {
      int lb_w = GetLayerLookback(1), lb_m = GetLayerLookback(2), lb_s = GetLayerLookback(3);
      int maxlb      = (int)MathMax(lb_w, MathMax(lb_m, lb_s));
      int scan_depth = maxlb + 61;   // baseline needs shift+maxlb+1, +60 for full cycle
      int bars_total = iBars(m_symbol, PERIOD_CURRENT);
      if(bars_total < scan_depth + 2) scan_depth = bars_total - 2;
      if(scan_depth <= 0) return;

      // ── Reset states and volume accumulators before replay ───────────
      m_layer_w_pb_state = LAYER_PB_NONE;
      m_layer_m_pb_state = LAYER_PB_NONE;
      m_layer_s_pb_state = LAYER_PB_NONE;
      m_layer_w_baseline = 0.0;
      m_layer_m_baseline = 0.0;
      m_layer_s_baseline = 0.0;
      m_layer_w_bars_det = 0;   // A21 2026-07
      m_layer_m_bars_det = 0;   // A21 2026-07
      m_layer_s_bars_det = 0;   // A21 2026-07
      // GUARD 1: the replay re-derives arming and the per-layer cycle counts from the
      // replayed history, so clear them before it runs.
      m_g1_armed           = false;
      m_layer_w_g1_recov   = 0; m_layer_m_g1_recov   = 0; m_layer_s_g1_recov   = 0;
      m_layer_w_g1_counted = false; m_layer_m_g1_counted = false; m_layer_s_g1_counted = false;
      m_phase_reset_pending   = PHASE_UNORDERED;
      m_phase_reset_confirmed = PHASE_UNORDERED;
      m_phase_reset_count     = 0;
      m_bars_since_uno_exit   = 999999;   // sentinel — counts non-UNO bars since last UNO
      m_uno_run               = 0;        // no UNO run in progress at (re)init
      m_cb_oeb_blocked  = false;
      m_cb_prev_any_rec = false;
      m_layer_w_vol_pb_avg = 0.0; m_layer_w_vol_pb_bars = 0;
      m_layer_w_vol_rec_avg = 0.0; m_layer_w_vol_rec_bars = 0; m_layer_w_vprr = 0.0;
      m_layer_m_vol_pb_avg = 0.0; m_layer_m_vol_pb_bars = 0;
      m_layer_m_vol_rec_avg = 0.0; m_layer_m_vol_rec_bars = 0; m_layer_m_vprr = 0.0;
      m_layer_s_vol_pb_avg = 0.0; m_layer_s_vol_pb_bars = 0;
      m_layer_s_vol_rec_avg = 0.0; m_layer_s_vol_rec_bars = 0; m_layer_s_vprr = 0.0;

      // Track the bias direction that owned the previous bar's state. We
      // use the same 999 sentinel as UpdateLayerPullbackStates so the very
      // first non-zero bias encountered triggers a clean directional
      // initialisation (sets m_last_dir_state_bias without wiping state).
      m_last_dir_state_bias = 999;

      // ── Replay oldest-to-newest: shift=scan_depth down to shift=1 ────
      // UpdateSingleLayerPullback reads EMA[shift] vs EMA[shift+1] — needs
      // shift+lookback bars of history, so start at scan_depth (oldest usable).
      int    last_seen_bias = 0;     // bias of the most recent bar that actually advanced state
      int    last_processed_shift = -1;
      for(int shift = scan_depth; shift >= 1; shift--)
      {
         // Guard: skip bars where EMA data isn't ready yet.
         // Use ReadEmaSafe (iMA + manual fallback) since the warmup walks
         // historical shifts outside the cached snapshot range.
         bool   ok1, ok2, ok3;
         string src_ignored;
         double e1 = ReadEmaSafe(1, shift, ok1, src_ignored);
         double e2 = ReadEmaSafe(2, shift, ok2, src_ignored);
         double e3 = ReadEmaSafe(3, shift, ok3, src_ignored);
         if(!ok1 || !ok2 || !ok3) continue;
         if(e1 == EMPTY_VALUE || e2 == EMPTY_VALUE || e3 == EMPTY_VALUE) continue;
         if(e1 == 0.0 || e2 == 0.0 || e3 == 0.0) continue;

         // Force unique bar_time so the once-per-bar guard in
         // UpdateLayerPullbackStates doesn't skip these historical bars.
         datetime bar_time = iTime(m_symbol, PERIOD_CURRENT, shift);
         m_layer_pb_last_update = 0;   // reset guard so each bar processes

         // Compute this bar's bias the same way live evaluation does.
         int b_wu = EvaluateB(shift);

         // ── B==0 (UNO/NEUTRAL) path — Path 2 UNO tolerance ─────────────
         // Mirror the live EvaluateTS dispatch: a transient UNO flicker that
         // resolves back to the same direction within UNO_ToleranceBars is
         // tolerated (layer states preserved). Only sustained UNO beyond
         // tolerance clears the layer pullback states; baselines / VPRR / DPI /
         // CB carry and m_last_dir_state_bias are preserved throughout, so a
         // brief UNO bar between two same-direction bars is not a flip.
         if(b_wu == 0)
         {
            m_uno_run++;
            if(m_uno_run > m_settings.UNO_ToleranceBars)
            {
               m_layer_w_pb_state = LAYER_PB_NONE;
               m_layer_m_pb_state = LAYER_PB_NONE;
               m_layer_s_pb_state = LAYER_PB_NONE;
               m_layer_w_bars_det = 0;   // A21 2026-07
               m_layer_m_bars_det = 0;   // A21 2026-07
               m_layer_s_bars_det = 0;   // A21 2026-07
            }
            // else: within tolerance — preserve layer states.
            m_layer_pb_last_update = bar_time;
            last_processed_shift = shift;
            continue;
         }
         // Non-UNO bar — end any UNO run.
         m_uno_run = 0;

         // ── Directional symmetry: real LONG↔SHORT flips wipe state ────
         // Same logic as UpdateLayerPullbackStates. Without this, SHORT-
         // direction pullback state accumulated under the prior downtrend
         // would leak into the new uptrend (and vice versa).
         if(b_wu != m_last_dir_state_bias)
         {
            // Don't wipe on the initial sentinel→bias transition — that
            // would discard a baseline we may have just begun to build
            // under no-bias bars. The reset only matters for genuine
            // direction flips between bullish and bearish.
            if(m_last_dir_state_bias != 999)
            {
               // GUARD 1: a flip inside the replayed history arms the guard and zeroes the
               // cycle counters exactly as the live path does — so a flip (and any P-R
               // cycles that already completed after it) that happened BEFORE the EA was
               // loaded are seeded correctly, and live evaluation does not re-skip a cycle
               // history already spent. The sentinel is excluded here for the same reason.
               m_g1_armed = true;
               ResetDirectionalState();
            }
            m_last_dir_state_bias = b_wu;
         }

         MaybeResetLayersOnPhaseChange(shift);

         // Spec-faithful recovery test (close vs fast EMA in bias direction)
         // requires bias_dir to be supplied; previously omitted, which fell
         // through to the back-compat 1-bar-slope-sign fallback inside
         // UpdateSingleLayerPullback and produced state transitions that
         // disagreed with live evaluation.
         UpdateSingleLayerPullback(h_ema1, shift, lb_w, GetLayerRecovery(1),
                                   m_layer_w_pb_state, m_layer_w_baseline, "LayerW_WU",
                                   m_layer_w_vol_pb_avg, m_layer_w_vol_pb_bars,
                                   m_layer_w_vol_rec_avg, m_layer_w_vol_rec_bars,
                                   m_layer_w_vprr, m_layer_w_bars_det, m_layer_w_bars_rec,
                                   m_layer_w_g1_recov, m_layer_w_g1_counted, b_wu,
                                   h_ema2, m_settings.LayerPriceTouchEnabled, GetLayerMinPBBars(1), GetLayerWindow(1), m_settings.LayerRecoveryMaxAgeEnabled);
         UpdateSingleLayerPullback(h_ema2, shift, lb_m, GetLayerRecovery(2),
                                   m_layer_m_pb_state, m_layer_m_baseline, "LayerM_WU",
                                   m_layer_m_vol_pb_avg, m_layer_m_vol_pb_bars,
                                   m_layer_m_vol_rec_avg, m_layer_m_vol_rec_bars,
                                   m_layer_m_vprr, m_layer_m_bars_det, m_layer_m_bars_rec,
                                   m_layer_m_g1_recov, m_layer_m_g1_counted, b_wu,
                                   h_ema3, m_settings.LayerPriceTouchEnabled, GetLayerMinPBBars(2), GetLayerWindow(2), m_settings.LayerRecoveryMaxAgeEnabled);
         UpdateSingleLayerPullback(h_ema3, shift, lb_s, GetLayerRecovery(3),
                                   m_layer_s_pb_state, m_layer_s_baseline, "LayerS_WU",
                                   m_layer_s_vol_pb_avg, m_layer_s_vol_pb_bars,
                                   m_layer_s_vol_rec_avg, m_layer_s_vol_rec_bars,
                                   m_layer_s_vprr, m_layer_s_bars_det, m_layer_s_bars_rec,
                                   m_layer_s_g1_recov, m_layer_s_g1_counted, b_wu,
                                   h_ema4, m_settings.LayerPriceTouchEnabled, GetLayerMinPBBars(3), GetLayerWindow(3), m_settings.LayerRecoveryMaxAgeEnabled);

         UpdateCBOverExtCarry(shift);

         last_seen_bias       = b_wu;
         last_processed_shift = shift;
         m_layer_pb_last_update = bar_time;
      }

      // ── Hand off cleanly to live evaluation ─────────────────────────
      // After the loop, m_last_dir_state_bias already holds the bias of the
      // most-recent advanced bar (see the directional-flip branch above).
      // If the loop never advanced any bar (e.g. empty history), seed it
      // from shift=1 directly so the first live call doesn't see 999 and
      // wipe everything.
      if(m_last_dir_state_bias == 999)
         m_last_dir_state_bias = EvaluateB(1);

      PrintFormat("[WarmUp] Layer states after %d-bar replay: W=%s M=%s S=%s "
                  "(last_bias=%d, last_shift=%d)",
                  scan_depth,
                  EnumToString(m_layer_w_pb_state),
                  EnumToString(m_layer_m_pb_state),
                  EnumToString(m_layer_s_pb_state),
                  last_seen_bias, last_processed_shift);
   }

   bool Init(ST_Settings &sets, string symbol) {
      // STEP18 2026-06: defensive release of stale handles before creating new ones.
      // Sibling of Executor.Init's ReleaseHandles() at SEA_TradeExecutor.mqh:2008.
      // On the normal OnDeinit→OnInit lifecycle, Signal.Release() (called from
      // OrchestrateDeinit) has already reset all member handles to INVALID_HANDLE,
      // so this Release() is a no-op. It defends against:
      //   1. MT5 lifecycle events where OnInit fires WITHOUT a preceding OnDeinit
      //      (manual refresh, some template/optimization scenarios) — would otherwise
      //      orphan the ~19 indicator handles from the previous Init.
      //   2. Partial Init failures: this function can return false at five
      //      "CRITICAL ERROR" checkpoints below (lines ~5760-5785) after creating
      //      a subset of handles. The next Init call now cleans up that partial
      //      leak before retrying.
      // Matches the canonical pattern: constructor already initializes all handles
      // to INVALID_HANDLE (lines ~4406+) with comment "Defensive init of indicator
      // handles (prevents stale handles across re-inits)"; this Release() extends
      // that intent to re-Init calls.
      Release();

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

      // Step19-audit 2026-06: VRC cache reset for parity with ADX above.
      // Previously the VRC threshold cache (m_cachedVRCLowThreshold /
      // m_lastVRCCalculation) and the rolling ATR history (m_atrHistory /
      // m_atrHistorySize) were only reset in the constructor — not in Init().
      // That meant a mid-session parameter change to VRC_LowThreshold,
      // VRC_ATRPeriod, or VRC_LookbackBars wouldn't take effect until
      // `refresh_sec` had elapsed since the previous CalculateVRCLowThreshold
      // call. Forcing both to zero here drops the cache so the next Check_VRC
      // call recomputes from current settings (matches the ADX pattern
      // documented in the prior STEP18 audit).
      ArrayInitialize(m_atrHistory, 0.0);
      m_atrHistorySize         = 0;
      m_lastVRCCalculation     = 0;
      m_cachedVRCLowThreshold  = 0.0;

      // Initialize DPI histogram tracking
      ArrayInitialize(m_dpi_hist_values, 0.0);
      m_dpi_hist_buffer_size = 0;
      m_dpi_hist_current = 0.0;
      m_dpi_hist_trend = 0;
      m_dpi_hist_decelerating = false;
      m_dpi_hist_green_present = false;
      m_dpi_hist_last_update = 0;
      m_dpi_reset_state = 0;
      m_dpi_reset_recovery_bars = 0;
      m_dpi_reset_colour_prev = false;
      m_dpi_reset_colour_ref  = false;
      m_dpi_reset_initialized = false;       // Re-seed colour_prev on next bar (cold-start guard)
      m_layer_w_pb_state = LAYER_PB_NONE;
      m_layer_m_pb_state = LAYER_PB_NONE;
      m_layer_s_pb_state = LAYER_PB_NONE;
      m_layer_w_baseline = 0.0;
      m_layer_m_baseline = 0.0;
      m_layer_s_baseline = 0.0;
      m_layer_w_bars_det = 0;   // A21 2026-07
      m_layer_m_bars_det = 0;   // A21 2026-07
      m_layer_s_bars_det = 0;   // A21 2026-07
      m_layer_pb_last_update = 0;
      // VPRR volume tracking reset
      m_layer_w_vol_pb_avg = 0.0; m_layer_m_vol_pb_avg = 0.0; m_layer_s_vol_pb_avg = 0.0;
      m_layer_w_vol_pb_bars = 0;  m_layer_m_vol_pb_bars = 0;  m_layer_s_vol_pb_bars = 0;
      m_layer_w_vol_rec_avg = 0.0; m_layer_m_vol_rec_avg = 0.0; m_layer_s_vol_rec_avg = 0.0;
      m_layer_w_vol_rec_bars = 0;  m_layer_m_vol_rec_bars = 0;  m_layer_s_vol_rec_bars = 0;
      m_layer_w_vprr = 0.0; m_layer_m_vprr = 0.0; m_layer_s_vprr = 0.0;
      m_vprr_last_real = false;
      m_vprr_real_warned = false;        // Re-arm one-shot REAL-volume warning on (re)init
      m_diag_last_bias = 0;
      m_diag_last_votes = 0;
      m_diag_last_reason = "";
      // STEP7 2026-06: m_diag_last_atr_pips reset removed (field deleted, dead-code cleanup)
      m_ts_status_string = "B[0] | I[0/0] | F[OK]";
      m_ts_status_str = "";
      m_te_status_str = "";
      m_diag_last_phase = PHASE_UNORDERED;
      m_diag_phase_confirm_bars = 0;
      m_phase_reset_pending   = PHASE_UNORDERED;
      m_phase_reset_confirmed = PHASE_UNORDERED;
      m_phase_reset_count     = 0;
      m_bars_since_uno_exit   = 999999;   // sentinel — counts non-UNO bars since last UNO
      m_uno_run               = 0;        // no UNO run in progress at (re)init
      m_cb_oeb_blocked  = false;
      m_cb_prev_any_rec = false;
      m_last_dir_state_bias = 999;   // re-arm directional symmetry reset
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
      m_telemetry.vprr_enabled    = m_settings.VPRR_Enabled;
      m_telemetry.vprr_ratio      = 0.0;
      m_telemetry.vprr_min_ratio  = m_settings.VPRR_MinRatio;
      m_telemetry.vprr_pass       = false;
      m_telemetry.vprr_vol_source = "—";
      m_telemetry.i_suppressed    = false;   // A14/A20 2026-07
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
         // BUGFIX A9 2026-06: was `return false;` (CRITICAL ERROR killing Init).
         // Check_CI uses inline CalculateCI() from raw OHLC — h_ci is ONLY read
         // by GetCiHandle() for chart visualization. Fatal here blocks the entire
         // EA on clean installs without ChoppinessIndex.ex5, even though the
         // voter functions correctly without it. Downgraded to warning.
         Print("WARNING: CI chart indicator (ChoppinessIndex.ex5) unavailable — CI voter uses inline calculation; chart visualization disabled.");
      }
      if(m_settings.Ind_VRC_Enabled && h_vrc == INVALID_HANDLE) {
         // BUGFIX A9 2026-06: was `return false;` (CRITICAL ERROR killing Init).
         // Check_VRC uses h_atr + GetVolatilityRegime() — h_vrc is ONLY read by
         // GetVrcHandle() for chart visualization. Fatal here blocks the EA on
         // installs without VRC_Indicator.ex5. Downgraded to warning.
         Print("WARNING: VRC chart indicator (VRC_Indicator.ex5) unavailable — VRC voter uses inline ATR percentile; chart visualization disabled.");
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

      // ── Historical warmup: reconstruct layer pullback states ──────────
      // When the EA starts mid-trend, historical bars already contain a
      // pullback-recovery cycle. Without scanning them, all layers start in
      // NONE and block the first valid signal.
      // Scan back enough bars to capture one full baseline + pullback cycle,
      // then replay UpdateSingleLayerPullback bar-by-bar so the state machine
      // arrives at the correct state (NONE / DETECTED / RECOVERED) at shift=1.
      if(m_settings.LayerPullbackEnabled && m_settings.BiasMode == BIAS_4EMA)
         WarmUpLayerPullbackStates();

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

   //+------------------------------------------------------------------+
   //| ValidateVPRRExternalSymbol                                        |
   //|                                                                   |
   //| Called from OnInit() after Signal.Init() to probe which volume   |
   //| source this broker actually provides and lock Settings accordingly.|
   //|                                                                   |
   //| Problem this solves:                                              |
   //|   REAL mode with a broker that has no real volume returns 0 on   |
   //|   every bar → VPRR ratio stays 0 → every trade blocked silently. |
   //|   This must be caught at init, not discovered mid-session.        |
   //|                                                                   |
   //| Resolution logic:                                                 |
   //|   TICK     → always available, no probe needed.                  |
   //|   AUTO     → probes real vol on primary symbol; if available     |
   //|              locks to REAL; if absent locks to TICK.             |
   //|   REAL     → probes real vol; if absent downgrades to TICK.      |
   //|   EXTERNAL → probes proxy symbol (VPRR_ExternalSymbol) for real  |
   //|              volume; if absent falls back to TICK on primary.    |
   //|              EXTERNAL is never downgraded to REAL/AUTO — it      |
   //|              either works or falls back to tick.                 |
   //|                                                                   |
   //| Returns: always true (tick vol is universal fallback).            |
   //+------------------------------------------------------------------+
   //| ValidateVPRRExternalSymbol                                        |
   //|                                                                   |
   //| Called from OnInit() when VPRR is enabled.                       |
   //|                                                                   |
   //| For EXTERNAL mode: validates the proxy symbol is accessible and   |
   //| provides real volume. Falls back to TICK if not.                 |
   //|                                                                   |
   //| For AUTO/REAL/TICK: does nothing. The preset's AutoDetectVPRR()  |
   //| already probed volume availability and set the correct type.     |
   //| Re-probing here would corrupt the preset's decision if called    |
   //| during a weekend or before history loads (CopyRealVolume = 0).  |
   //+------------------------------------------------------------------+
   bool ValidateVPRRExternalSymbol(const bool print_details = true)
   {
      if(!m_settings.VPRR_Enabled)
      {
         if(print_details)
            Print("[VPRR_INIT] VPRR disabled — skipped.");
         return true;
      }

      // AUTO/REAL/TICK: already correctly set by AutoDetectVPRR() in preset. Do not re-probe.
      if(m_settings.VPRR_VolumeType != (int)VPRR_VOL_EXTERNAL)
      {
         if(print_details)
         {
            string src = (m_settings.VPRR_VolumeType == (int)VPRR_VOL_REAL) ? "REAL"
                       : (m_settings.VPRR_VolumeType == (int)VPRR_VOL_TICK) ? "TICK" : "AUTO";
            PrintFormat("[VPRR_INIT] Symbol='%s' | Source=%s (set by preset) ✅", m_symbol, src);
         }
         return true;
      }

      // ── EXTERNAL: validate proxy symbol ──────────────────────────────
      string proxy = m_settings.VPRR_ExternalSymbol;
      if(StringLen(proxy) == 0)
      {
         Print("[VPRR_INIT] WARNING: VolumeType=EXTERNAL but VPRR_ExternalSymbol is empty. "
               "Falling back to TICK. Set Inp_VPRR_ExternalSymbol (e.g. \"GC\" or \"MGC\").");
         m_settings.VPRR_VolumeType = (int)VPRR_VOL_TICK;
         return true;
      }

      long ext_vol[1];
      bool ext_available = false;
      for(int probe_shift = 1; probe_shift <= 3; probe_shift++)
      {
         if(CopyRealVolume(proxy, PERIOD_CURRENT, probe_shift, 1, ext_vol) == 1 && ext_vol[0] > 0)
         {
            ext_available = true;
            break;
         }
      }

      if(ext_available)
      {
         if(print_details)
            PrintFormat("[VPRR_INIT] Symbol='%s' | Proxy='%s' | Real volume confirmed → Source: EXTERNAL ✅",
                        m_symbol, proxy);
      }
      else
      {
         PrintFormat("[VPRR_INIT] WARNING: Proxy='%s' returned no real volume. "
                     "Is it in MarketWatch? Falling back to TICK on primary symbol.",
                     proxy);
         m_settings.VPRR_VolumeType = (int)VPRR_VOL_TICK;
      }

      return true;
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
   bool CheckCandleDirectionGate(int bias) { return CheckCandleDirectionGate(bias, 1); }
   bool CheckCandleDirectionGate(int bias, int shift) {
      if(!m_settings.CandleBody_RequireDirection) return true;   // gate disabled
      if(bias == 0)                               return true;   // no directional bias to check

      double o = iOpen(m_symbol, PERIOD_CURRENT, shift);
      double c = iClose(m_symbol, PERIOD_CURRENT, shift);

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
   bool CheckCandleBodyIndicator(int bias, int shift = 1) {
      if(!m_settings.Ind_CandleBody_Enabled) return true;

      // Cardinal rule: evaluate the SIGNAL BAR (shift), never bar 0. At shift=1
      // this reproduces the original bars 1..6 exactly (live EA unchanged); for
      // shift>1 it offsets every read off `base` so scanner/replay is correct.
      int base = (shift < 1) ? 1 : shift;

      // A22: refuse to confirm the candle if the signal bar's OHLC isn't readable.
      // Fail-closed keeps CandleBody consistent with the other I-voters — a bad
      // price read must not let an unverified candle pass the unanimous vote.
      if(!HasValidBarData(base))
         return false;

      // ── Over-extension (spike) guard — ATR-based, signal bar only. ─────────
      //    Rejects only genuine spikes (range > SpikeMult × ATR of the prior
      //    bars); normal breakout candles pass. See CB_IsSpike for the rationale
      //    and which knobs map to N / SpikeMult. CandleBody_CheckBars is no
      //    longer used by the spike test (a spike is a single bar).
      if(CB_IsSpike(base))
         return false;

      // Close-ratio quality filter (TopInvestor 75% rule)
      // Signal bar close must be in the "strong" portion of its range.
      // LONG:  (close - low)  / (high - low) >= MinCloseRatio
      // SHORT: (high - close) / (high - low) >= MinCloseRatio
      if(m_settings.CandleBody_MinCloseRatio > 0.0)
      {
         double h = iHigh(m_symbol, PERIOD_CURRENT, base);
         double l = iLow(m_symbol, PERIOD_CURRENT, base);
         double c = iClose(m_symbol, PERIOD_CURRENT, base);
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

      // Update cache after the user-configured refresh interval (default 14400s = 4h)
      // elapses, or on the very first call. 60-second floor matches Check_ADX
      // — prevents an accidental tiny value from forcing a full-percentile
      // recompute on every tick (CPU-expensive on long lookback buffers).
      datetime now = TimeCurrent();
      int refresh_sec = (m_settings.VRC_RefreshSec >= 60 ? m_settings.VRC_RefreshSec : 60);
      if(now - m_lastVRCCalculation > refresh_sec || m_cachedVRCLowThreshold == 0.0) {
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

   // F-AUDIT 2026-06: CheckFilters() removed — verified zero callers across all
   // .mqh/.mq5 files. Time/News/Spread are TE-side gates handled by
   // CTradeExecutor::EvaluateF; this function was an outdated duplicate.


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

   // F-AUDIT 2026-06: EvaluateFilterX() removed — verified zero callers across all
   // .mqh/.mq5 files (including SEA_IND_SignalScan.mq5). The TS-side filter chain
   // runs through EvaluateF (line ~3973); the TE-side Time/News/Spread gate runs
   // through CTradeExecutor::EvaluateF. Stat counters (m_stats.passed_time/news/
   // spread + rejected_*) are now bridged from CTradeExecutor via the existing
   // AddTeStats() bridge pattern.


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

      // Bias EMAs via GetMAValSafe (routes through ribbon snapshot when the
      // bias handles resolve to ribbon slots — which is the normal case).
      int hf = BiasFastHandle();
      int hs = BiasSlowHandle();
      bool ok_fcurr, ok_scurr;
      double f_curr = GetMAValSafe(hf, v_shift, ok_fcurr);
      double s_curr = GetMAValSafe(hs, v_shift, ok_scurr);

      // B1 2026-06: BIAS_4EMA is fully handled by EvaluateB() before reaching
      // here (EvaluateB short-circuits to GetBias_4EMA_Direction). The old
      // BIAS_4EMA branch (which called the now-removed GetBias_PhaseBased)
      // was unreachable dead code with different semantics (combined direction
      // + phase-gate, vs the live architecture which splits direction in
      // EvaluateB and phase-gate in EvaluateP). Removed to prevent accidental
      // resurrection of the old behavior.
      if(m_settings.BiasMode == BIAS_MANUAL) {
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

         // Historical reads (v_shift + lookback) — GetMAValSafe routes to
         // ReadEmaSafe for shifts outside the snapshot's two-bar window.
         bool ok_fprev, ok_sprev;
         double f_prev = GetMAValSafe(hf, v_shift + lookback, ok_fprev);
         double s_prev = GetMAValSafe(hs, v_shift + lookback, ok_sprev);

         // If any bias EMA read failed (current or historical), bail with
         // neutral bias — fails safe. Diagnostics will note BIAS_ZERO.
         if(!ok_fcurr || !ok_scurr || !ok_fprev || !ok_sprev) {
            if(m_settings.DebugFlow) {
               PrintFormat("[BIAS] EMA read invalid (fcurr=%d scurr=%d fprev=%d sprev=%d) → bias=0",
                           (int)ok_fcurr, (int)ok_scurr, (int)ok_fprev, (int)ok_sprev);
            }
            m_eval_str_B = "INV";
            int market_bias_inv = 0;
            if(market_bias_inv == 0) {
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
         }

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
               bool ok_ma;
               double ma    = GetMAValSafe(hf, v_shift, ok_ma);
               entry_signal = ok_ma ? ((price > ma) ? 1 : -1) : 0;
            }
            if(m_settings.DebugFlow) {
               datetime bar_time = iTime(m_symbol, PERIOD_CURRENT, v_shift);
               double price = iClose(m_symbol, PERIOD_CURRENT, v_shift);
               bool ok_ma_dbg;
               double ma    = GetMAValSafe(hf, v_shift, ok_ma_dbg);
               DebugLog(StringFormat("STEP 2 ENTRY[%s]: STRAT_2EMA_CROSS_PRICE %s price=%.5f ma=%.5f%s → signal=%d",
                                     TimeToString(bar_time), ema_fast_name, price, ma,
                                     ok_ma_dbg ? "" : "(INVALID)", entry_signal));
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
            entry_signal = market_bias;
            if(m_settings.DebugFlow) {
               datetime bar_time = iTime(m_symbol, PERIOD_CURRENT, v_shift);
               DebugLog(StringFormat("STEP 2 ENTRY[%s]: STRAT_4EMA_LAYER → bias=%d passed to KISS pipeline",
                                     TimeToString(bar_time), entry_signal));
            }
         }
         else {  // STRAT_2EMA_CROSS_EMA
            bool ok_fcc, ok_fpc, ok_scc, ok_spc;
            double f_curr_cross = GetMAValSafe(hf, v_shift,     ok_fcc);
            double f_prev_cross = GetMAValSafe(hf, v_shift + 1, ok_fpc);
            double s_curr_cross = GetMAValSafe(hs, v_shift,     ok_scc);
            double s_prev_cross = GetMAValSafe(hs, v_shift + 1, ok_spc);

            if(!ok_fcc || !ok_fpc || !ok_scc || !ok_spc)
            {
               // Any EMA read invalid → refuse direction (entry_signal=0).
               // Falls through to STEP 3 which will bail with bias=0.
               if(m_settings.DebugFlow)
                  DebugLog("STEP 2 ENTRY: STRAT_2EMA_CROSS_EMA — EMA read invalid → signal=0");
               entry_signal = 0;
            }
            else
            {
               bool bullish_cross = (f_prev_cross <= s_prev_cross && f_curr_cross > s_curr_cross);
               bool bearish_cross = (f_prev_cross >= s_prev_cross && f_curr_cross < s_curr_cross);
               bool has_crossover = (bullish_cross || bearish_cross);

               if(bullish_cross) entry_signal = 1;
               else if(bearish_cross) entry_signal = -1;
               else if(m_settings.ExitProfile == EXIT_PROFILE_RRM && market_bias != 0)
               {
                  bool ema_position_matches_bias = (market_bias == 1) ? (f_curr_cross > s_curr_cross) : (f_curr_cross < s_curr_cross);
                  if(ema_position_matches_bias)
                  {
                     entry_signal = market_bias;
                     if(m_settings.DebugFlow) {
                        datetime bar_time = iTime(m_symbol, PERIOD_CURRENT, v_shift);
                        DebugLog(StringFormat("STEP 2 ENTRY[%s]: RRM CONTINUATION bias=%d trend intact f=%.5f %s s=%.5f → signal=%d",
                                              TimeToString(bar_time), market_bias, f_curr_cross, (market_bias == 1 ? ">" : "<"), s_curr_cross, entry_signal));
                     }
                  }
                  else
                  {
                     entry_signal = 0;
                     if(m_settings.DebugFlow) {
                        datetime bar_time = iTime(m_symbol, PERIOD_CURRENT, v_shift);
                        DebugLog(StringFormat("STEP 2 ENTRY[%s]: RRM CONTINUATION rejected f=%.5f vs s=%.5f bias=%d → signal=0",
                                              TimeToString(bar_time), f_curr_cross, s_curr_cross, market_bias));
                     }
                  }
               }
               else
               {
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
      // BUGFIX A3 2026-06: the market_bias==0 handler (~line 6788) and SIGNAL_MISMATCH
      // handler (~line 6931) already incremented m_reject_bias and m_stats.rejected_bias.
      // Under Stats_FullEvaluation=true (the default), those handlers skip the early
      // return and set m_eval_any_failure=true instead. This terminal block then
      // re-incremented the same counters — double-counting every bias rejection in the
      // OnDeinit report. Guard: only increment when no earlier handler already counted.
      if(bias == 0 && !m_eval_any_failure) {
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
      else if(bias == 0) {
         // Earlier handler already counted and set m_eval_any_failure — propagate
         // reason only, no re-increment.
         if(m_diag_last_reason == "") m_diag_last_reason = "BIAS_ZERO";
      }
      else {
         m_stats.passed_bias++;
         if(bias > 0) m_stats.passed_bias_long++;
         else         m_stats.passed_bias_short++;
      }

      return bias;
   }

   // ─────────────────────────────────────────────────────────────────────────
   // EvaluateIndicatorX — KISS Component: Voting consensus
   // Casts all enabled indicator votes, logs diagnostics, applies vote mode.
   // Returns bias if voting passes, 0 if consensus fails.
   // ─────────────────────────────────────────────────────────────────────────
   int EvaluateIndicatorX(int v_shift, int bias)
   {
      // ═══════════════════════════════════════════════════════════════
      // 4. Voting Logic — All enabled indicators must agree (unanimous)
      // ═══════════════════════════════════════════════════════════════
      bool   all_pass    = true;

      int vote_pass = 0;
      int vote_enab = 0;

      #define CAST_VOTE_STAT(use_flag, check_expr, stat_rej_field, stat_pass_field) \
         { if(use_flag) { vote_enab++; bool _cv_pass = (check_expr); \
         if(_cv_pass) { vote_pass++; stat_pass_field++; } \
         else { all_pass = false; stat_rej_field++; } } }

      CAST_VOTE_STAT(m_settings.Ind_Adx_Enabled,    Check_ADX(v_shift),        m_stats.rejected_adx, m_stats.passed_adx)
      CAST_VOTE_STAT(m_settings.Ind_Macd_Enabled,   Check_MACD(bias, v_shift), m_stats.rejected_macd, m_stats.passed_macd)
      CAST_VOTE_STAT(m_settings.Ind_Rsi_Enabled,    Check_RSI(bias, v_shift),  m_stats.rejected_rsi, m_stats.passed_rsi)
      CAST_VOTE_STAT(m_settings.Ind_Cci_Enabled,    Check_CCI(bias, v_shift),  m_stats.rejected_cci, m_stats.passed_cci)
      CAST_VOTE_STAT(m_settings.Ind_Mfi_Enabled,    Check_MFI(bias, v_shift),  m_stats.rejected_mfi, m_stats.passed_mfi)
      CAST_VOTE_STAT(m_settings.Ind_Sto_Enabled,    Check_Sto(bias, v_shift),  m_stats.rejected_sto, m_stats.passed_sto)
      CAST_VOTE_STAT(m_settings.Ind_Bb_Enabled,     Check_BB(bias, v_shift),   m_stats.rejected_bb, m_stats.passed_bb)
      CAST_VOTE_STAT(m_settings.Ind_Psar_Enabled,   (m_settings.Vote_AllowPsarFlip ? Check_PSAR_WithFlip(bias, v_shift) : Check_PSAR(bias, v_shift)), m_stats.rejected_psar, m_stats.passed_psar)
      CAST_VOTE_STAT(m_settings.Ind_P123_Enabled,   Check_P123(bias, v_shift), m_stats.rejected_p123, m_stats.passed_p123)
      CAST_VOTE_STAT(m_settings.Ind_Ross_Enabled,   Check_Ross(bias, v_shift), m_stats.rejected_ross, m_stats.passed_ross)

      // --- NON-DIRECTIONAL SYSTEM FILTERS ---
      CAST_VOTE_STAT(m_settings.Ind_Atr_Enabled,        Check_ATR(bias, v_shift),        m_stats.rejected_atr, m_stats.passed_atr)
      CAST_VOTE_STAT(m_settings.Ind_CandleBody_Enabled, Check_CandleBody(bias, v_shift), m_stats.rejected_candle_body, m_stats.passed_candle_body)
      CAST_VOTE_STAT(m_settings.Ind_CI_Enabled,         Check_CI(bias, v_shift),         m_stats.rejected_ci, m_stats.passed_ci)
      CAST_VOTE_STAT(m_settings.Ind_VRC_Enabled,        Check_VRC(bias, v_shift),        m_stats.rejected_vrc, m_stats.passed_vrc)
      CAST_VOTE_STAT(m_settings.Ind_SmaConverge_Enabled, Check_SmaConverge(v_shift),      m_stats.rejected_sma_converge, m_stats.passed_sma_converge)
      CAST_VOTE_STAT(m_settings.Ind_Dpi_Enabled,         Check_DPI(bias, v_shift),         m_stats.rejected_dpi,          m_stats.passed_dpi)
      CAST_VOTE_STAT(m_settings.Ind_Fib_Enabled,         Check_Fib(bias, v_shift),         m_stats.rejected_fib,          m_stats.passed_fib)
      CAST_VOTE_STAT(m_settings.Ind_MTF_Enabled,         Check_MTF(bias, v_shift),                  m_stats.rejected_mtf,          m_stats.passed_mtf)
      CAST_VOTE_STAT(m_settings.VPRR_Enabled,            Check_VPRR(v_shift),              m_stats.rejected_vprr,         m_stats.passed_vprr)
      #undef CAST_VOTE_STAT

      // Telemetry derives DIRECTLY from the CAST_VOTE_STAT counters above (Step19-perf
      // 2026-06): the second `if(m_settings.Ind_X_Enabled) { s_enabled++; if(Check_X(...))
      // s_passed++; }` loop that used to live here was a faithful duplicate of the macro
      // pass — same gating, same Check_*, same result. For the 9 cache-hit indicators
      // (ADX/MACD/RSI/CCI/MFI/Sto/BB/PSAR/...) the second call short-circuited via
      // m_ind_cache, so the redundancy was effectively free; for the 5 uncached voters
      // (P123/Ross/Fib/MTF/VPRR) the second call re-ran the full computation, doubling
      // their per-bar cost. Reading from the macro's counters is exact (it iterates the
      // identical indicator list) and removes the duplicate Check_* round entirely.
      int s_enabled = vote_enab;
      int s_passed  = vote_pass;

      // Always use indicator pass count for display (vote_pass counts enabled indicators that passed)
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
                        DebugLog(StringFormat("[IND] --- Indicators (pass=%d/%d bias=%d) ---",
                                  vote_pass, vote_enab, bias));

            if(m_settings.Ind_Adx_Enabled) {
               double adx = GetVal(h_adx, v_shift);
               DebugLog(StringFormat("[IND] ADX: %.2f / threshold=%.2f → %s",
                                     adx, m_cachedADXThreshold, _res_adx ? "PASS" : "FAIL"));
            } else DebugLog("[IND] ADX: DISABLED → SKIP");

            if(m_settings.Ind_Macd_Enabled) {
               double macd_m = GetVal(h_macd, v_shift, 0);
               double macd_s = GetVal(h_macd, v_shift, 1);
               DebugLog(StringFormat("[IND] MACD: main=%.6f signal=%.6f hist=%.6f → %s",
                                     macd_m, macd_s, macd_m - macd_s, _res_macd ? "PASS" : "FAIL"));
            } else DebugLog("[IND] MACD: DISABLED → SKIP");

            if(m_settings.Ind_Rsi_Enabled) {
               double r = GetVal(h_rsi, v_shift);
               DebugLog(StringFormat("[IND] RSI: %.2f (OB=%.0f OS=%.0f) → %s",
                                     r, m_settings.T_RsiOB, m_settings.T_RsiOS, _res_rsi ? "PASS" : "FAIL"));
            } else DebugLog("[IND] RSI: DISABLED → SKIP");

            if(m_settings.Ind_Cci_Enabled) {
               double c = GetVal(h_cci, v_shift);
               DebugLog(StringFormat("[IND] CCI: %.2f → %s",
                                     c, _res_cci ? "PASS" : "FAIL"));
            } else DebugLog("[IND] CCI: DISABLED → SKIP");

            if(m_settings.Ind_Mfi_Enabled) {
               double mfi = GetVal(h_mfi, v_shift);
               DebugLog(StringFormat("[IND] MFI: %.2f (OB=%.0f OS=%.0f) → %s",
                                     mfi, m_settings.T_MfiOB, m_settings.T_MfiOS, _res_mfi ? "PASS" : "FAIL"));
            } else DebugLog("[IND] MFI: DISABLED → SKIP");

            if(m_settings.Ind_Sto_Enabled) {
               double sk = GetVal(h_sto, v_shift, 0);
               double sd = GetVal(h_sto, v_shift, 1);
               DebugLog(StringFormat("[IND] Stoch: K=%.2f D=%.2f (OB=%.0f OS=%.0f) → %s",
                                     sk, sd, m_settings.T_StoOB, m_settings.T_StoOS, _res_sto ? "PASS" : "FAIL"));
            } else DebugLog("[IND] Stoch: DISABLED → SKIP");

            if(m_settings.Ind_Bb_Enabled) {
               double bb_mid = GetVal(h_bb, v_shift, 0);
               double cl_bb  = iClose(m_symbol, PERIOD_CURRENT, v_shift);
               DebugLog(StringFormat("[IND] BB: mid=%.5f close=%.5f → %s",
                                     bb_mid, cl_bb, _res_bb ? "PASS" : "FAIL"));
            } else DebugLog("[IND] BB: DISABLED → SKIP");

            if(m_settings.Ind_Psar_Enabled) {
               double psar_v = GetVal(h_psar, v_shift);
               double cl_p   = iClose(m_symbol, PERIOD_CURRENT, v_shift);
               string flip_info = "";
               if(m_settings.Vote_AllowPsarFlip) {
                  int effective_n = GetEffectivePsarFlipDelay();  // layer-aware
                  if(effective_n == -1) {
                     flip_info = " [PERSISTENT]";
                  } else {
                     int bars_since_flip = GetBarsSinceLastFlip(bias, v_shift);
                     if(bars_since_flip == INT_MAX)
                        flip_info = StringFormat(" flip=none (N=%d)", effective_n);
                     else {
                        bool within = (bars_since_flip <= effective_n);
                        flip_info = StringFormat(" flip=%d/N=%d (%s)",
                                                 bars_since_flip, effective_n,
                                                 within ? "within" : "EXPIRED");
                     }
                  }
               } else {
                  flip_info = " [DOT-only]";
               }
               DebugLog(StringFormat("[IND] PSAR: dot=%.5f close=%.5f%s → %s",
                                     psar_v, cl_p, flip_info, _res_psar ? "PASS" : "FAIL"));
            } else DebugLog("[IND] PSAR: DISABLED → SKIP");

            if(m_settings.Ind_P123_Enabled) {
               DebugLog(StringFormat("[IND] P123: → %s", _res_p123 ? "PASS" : "FAIL"));
            } else DebugLog("[IND] P123: DISABLED → SKIP");

            if(m_settings.Ind_Ross_Enabled) {
               DebugLog(StringFormat("[IND] RossHook: → %s", _res_ross ? "PASS" : "FAIL"));
            } else DebugLog("[IND] RossHook: DISABLED → SKIP");

            if(m_settings.Ind_Dpi_Enabled) {
               DebugLog(StringFormat("[IND] DPI v31: F=%d S=%d RedType=%d CCI=%d Green=%d → %s",
                                     m_settings.DPI_MACD_Fast, m_settings.DPI_MACD_Slow, m_settings.DPI_RedSignalType,
                                     m_settings.DPI_UseCCIReset ? m_settings.DPI_CCI_Period : 0,
                                     m_settings.DPI_UseGreenHist ? 1 : 0,
                                     _res_dpi ? "PASS" : "FAIL"));
            } else DebugLog("[IND] DPI: DISABLED → SKIP");

            if(m_settings.Ind_Atr_Enabled) {
               double atr_v_pips = AtrPips();  // STEP7 2026-06: was m_diag_last_atr_pips (dead 0.0); now live read
               bool   atr_v_ok   = true;
               if(m_settings.ATR_VoteMinPips > 0.0 && atr_v_pips < m_settings.ATR_VoteMinPips) atr_v_ok = false;
               if(m_settings.ATR_VoteMaxPips > 0.0 && atr_v_pips > m_settings.ATR_VoteMaxPips) atr_v_ok = false;
               DebugLog(StringFormat("[IND] ATR Vote: %.1f pips (min=%.1f max=%.1f) → %s",
                                     atr_v_pips, m_settings.ATR_VoteMinPips, m_settings.ATR_VoteMaxPips,
                                     atr_v_ok ? "PASS" : "FAIL"));
            } else
               DebugLog("[IND] ATR Vote: DISABLED → SKIP");

            if(m_settings.Ind_CandleBody_Enabled) {
               bool cb_ok = CheckCandleBodyIndicator(bias);
               DebugLog(StringFormat("[IND] CandleBody: avg period=%d max=x%.1f check=%d → %s",
                                     m_settings.CandleBody_AvgPeriod, m_settings.CandleBody_MaxMult,
                                     m_settings.CandleBody_CheckBars, cb_ok ? "PASS" : "FAIL"));
            } else
               DebugLog("[IND] CandleBody: DISABLED → SKIP");

            if(m_settings.Ind_CI_Enabled) {
               double ci_val = CalculateCI(v_shift);
               bool ci_ok = Check_CI(bias, v_shift);
               string ci_status = (ci_val >= m_settings.CI_RangingThreshold ? "RANGING" : "TRENDING");
               DebugLog(StringFormat("[IND] ChoppinessIndex: CI=%.1f threshold=%.1f status=%s → %s",
                                     ci_val, m_settings.CI_RangingThreshold, ci_status,
                                     ci_ok ? "PASS" : "FAIL"));
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
         m_eval_all_pass       = all_pass;

      // Apply vote mode and return result
      if(all_pass) {
         m_diag_last_reason = "OK";
         m_diag_i_fails = "";
         // NOTE: signals_confirmed / signals_generated are TS-level counters and
         // are incremented at the top-level final_signal=1 site in EvaluateTS().
         // Incrementing them here counted "indicator-vote passes" — bars where
         // B/P/L/CG/F later vetoed still got counted, producing a false
         // "770 confirmed / 1 traded / 99.9% filtered" report.
         if(m_settings.DebugFlow) DebugLog(StringFormat("[RESULT] TS=%d (all %d voters passed)", bias, vote_pass));
         return bias;
      }
      else {
         m_diag_last_reason = StringFormat("NOT_ALL_PASS (%d/%d)", s_passed, s_enabled);
         m_reject_votes++;
         // Failing-voter names (BOTH directions): stored compactly for the inspector
         // (m_diag_i_fails), and printed for shorts (temporary diagnostic).
         {
            string fails = "";
            if(m_settings.Ind_Psar_Enabled && !(m_settings.Vote_AllowPsarFlip ? Check_PSAR_WithFlip(bias, v_shift) : Check_PSAR(bias, v_shift)))
            {
               // Sub-code distinguishes the three flip-mode failure paths so the user
               // can tell "dot on wrong side" from "no flip yet" from "flip too old".
               //   DOT = dot on wrong side of price (the visual check)
               //   NoF = no flip recorded for this direction yet
               //   EXP = flip is older than PsarFlipDelay window (sustained trend)
               // NOTE: setters write 0/1/3/4 (mirroring dpi_diag_sub's scheme, with 2
               // unused). Previously this read == 2 for EXP — but setters never write
               // 2 — so every expired-flip reject was silently labeled DOT, hiding the
               // most common rejection mode on sustained trends. Fixed 2026-06.
               if(m_settings.Vote_AllowPsarFlip)
               {
                  string psub = (m_ind_cache.psar_diag_sub == 1 ? "NoF" :
                                 m_ind_cache.psar_diag_sub == 4 ? "EXP" : "DOT");
                  fails += StringFormat("PSAR(%s) ", psub);
               }
               else fails += "PSAR ";
            }
            if(m_settings.Ind_Dpi_Enabled && !Check_DPI(bias, v_shift))
            {
               string dsub = (m_ind_cache.dpi_diag_sub==1 ? "DIR" : m_ind_cache.dpi_diag_sub==3 ? "GREEN" : m_ind_cache.dpi_diag_sub==4 ? "RESET" : "?");
               // For DIR rejections, show the ribbon colour (R=red, Y=yellow) — the
               // direction-vote uses ribbon colour, not the raw histogram value.
               // DIR(R) = ribbon RED blocked a LONG; DIR(Y) = ribbon YELLOW blocked a SHORT.
               if(m_ind_cache.dpi_diag_sub == 1)
                  fails += StringFormat("DPI:DIR(%s) ", m_ind_cache.dpi_diag_yellow ? "Y" : "R");
               else
                  fails += StringFormat("DPI:%s ", dsub);
            }
            if(m_settings.Ind_CandleBody_Enabled && !Check_CandleBody(bias, v_shift)) fails += "CBODY ";
            if(m_settings.Ind_MTF_Enabled && !Check_MTF(bias, v_shift)) fails += "MTF ";
            if(m_settings.Ind_Adx_Enabled && !Check_ADX(v_shift)) fails += "ADX ";
            if(m_settings.Ind_Macd_Enabled && !Check_MACD(bias, v_shift)) fails += "MACD ";
            if(m_settings.Ind_Cci_Enabled && !Check_CCI(bias, v_shift)) fails += "CCI ";
            // Diagnostic: print failing voters for BOTH directions. Previously this
            // only printed for bias<0 (shorts), which hid why LONG-bias bars never
            // confirm. With both directions visible, a per-bar grep of [LONG_REJECT]
            // immediately shows which voter (PSAR/DPI/CBODY/MTF/...) blocks longs.
            {
               datetime bar_time = iTime(m_symbol, PERIOD_CURRENT, v_shift);
               PrintFormat("[%s_REJECT] %s | %d/%d pass | FAILED: %s",
                           (bias < 0 ? "SHORT" : "LONG"),
                           TimeToString(bar_time, TIME_DATE|TIME_MINUTES), s_passed, s_enabled, fails);
            }
            string ifail = fails; StringTrimRight(ifail); StringReplace(ifail, " ", ",");
            m_diag_i_fails = ifail;
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
            // Snapshot slots 2 and 4. If either invalid, refuse direction (0).
            if(!GetEmaValid(2) || !GetEmaValid(4)) { result = 0; break; }
            double ema2 = GetEma2();
            double ema4 = GetEma4();
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
         // Read from snapshot for diagnostic display. INVALID slots print 0.
         double ema2 = GetEmaValid(2) ? GetEma2() : 0.0;
         double ema3 = GetEmaValid(3) ? GetEma3() : 0.0;
         double ema4 = GetEmaValid(4) ? GetEma4() : 0.0;
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

      // Phase at the evaluated bar. For the EA (v_shift=1) this equals the
      // phase EvaluateB just computed; recomputing here makes EvaluateP
      // shift-correct so SignalScan can evaluate phase at historical bars.
      EMarketPhase phase = DetectMarketPhase(v_shift);

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
   // LayerS_DirAligned - Layer S (EMA3/EMA4) positioned AND both EMAs sloping with bias.
   // Optional gate (LayerS_RequireDirAlign): blocks faster Layer M/W entries unless the
   // dominant S pair confirms direction (position + slope). NOT a pullback-recovery.
   bool LayerS_DirAligned(const int v_shift, const int bias)
   {
      if(bias == 0) return false;
      // Snapshot slots 3 and 4, current and previous bar. Refuse alignment
      // when any required slot is invalid — fails safe (no S confirmation).
      if(!GetEmaValid(3) || !GetEmaValid(4) ||
         !GetEmaValidPrev(3) || !GetEmaValidPrev(4))
         return false;
      double e3  = GetEma3();
      double e4  = GetEma4();
      double e3p = GetEma3Prev();
      double e4p = GetEma4Prev();
      double s3 = e3 - e3p;   // EMA3 slope
      double s4 = e4 - e4p;   // EMA4 slope
      if(bias == 1)  return (e3 > e4) && (s3 > 0.0) && (s4 > 0.0);   // LONG: stacked up + both rising
      return (e3 < e4) && (s3 < 0.0) && (s4 < 0.0);                  // SHORT: stacked down + both falling
   }

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
      m_eval_layer_w = CheckLayerPairAlign(bias, 1, v_shift);
      m_eval_layer_m = CheckLayerPairAlign(bias, 2, v_shift);
      m_eval_layer_s = CheckLayerPairAlign(bias, 3, v_shift);
      m_diag_layer_w = m_eval_layer_w;
      m_diag_layer_m = m_eval_layer_m;
      m_diag_layer_s = m_eval_layer_s;

      // Optional Layer-S direction gate: block faster M/W entries unless Layer S
      // (EMA3/EMA4) is position+slope aligned with bias. S's own entry is unaffected.
      bool layerS_dir_ok = (!m_settings.LayerS_RequireDirAlign) || LayerS_DirAligned(v_shift, bias);

      // Strong-S phase gate (book-faithful, SYMMETRIC across LONG/SHORT):
      // The RRM Trade Setups card affirms "during the Trending Phase" in BOTH
      // the Bullish and Bearish Strong rules. The Bullish rule additionally
      // restates this as "no trades during Emerging Phase"; the Bearish rule
      // omits this restatement (typo in original) but the Trending-Phase
      // affirmation is identical, so the symmetric reading is TM-only for
      // both directions. Setting Emerging_AllowStrongTrades=true overrides
      // and permits Strong-EM symmetrically.
      // m_diag_last_phase was set inside GetBias_4EMA_Direction (called via
      // EvaluateB earlier in this same TS pass), so it is current for v_shift.
      bool s_blocked_emerging = false;
      if(!m_settings.Emerging_AllowStrongTrades)
      {
         bool is_emerging = (m_diag_last_phase == PHASE_EMERGING_UP ||
                             m_diag_last_phase == PHASE_EMERGING_DN ||
                             m_diag_last_phase == PHASE_EMERGING);
         s_blocked_emerging = is_emerging;
      }

      if(m_settings.DebugLevel >= DEBUG_INDICATORS) {
         DebugLog(StringFormat("[EvaluateL] LayerW=%d LayerM=%d LayerS=%d (bias=%d) s_blocked_em=%d",
                               m_eval_layer_w, m_eval_layer_m, m_eval_layer_s, bias,
                               (int)s_blocked_emerging));
      }

      // Step 2: BD (Bar Direction) — same bar, applies equally to all layers
      bool bd_pass = CheckCandleDirectionGate(bias, v_shift);

      int lookback = MathMax(1, MathMin(4, m_settings.BarClose_LookbackBars));
      bool momentum_confirmed = true;
      if(lookback > 1 && m_settings.Require_Progressive_Momentum)
      {
         momentum_confirmed = Check_Progressive_Momentum(v_shift, bias, lookback);
         if(!momentum_confirmed && m_settings.DPI_Histogram_Growth_Boost)
            momentum_confirmed = Check_DPI_Histogram_Growing(v_shift, bias, lookback);
      }

      // Step 3: Priority walk L3 → L2 → L1; each layer also needs BC and BD.
      // S branch additionally honours the Strong-EM gate above.
      if(m_eval_layer_s == 1 && m_settings.AllowLayer3_Entries && !s_blocked_emerging) {
         int bc_s = Eval_BarClose(v_shift, bias, LAYER_3_STRONG);
         if(bc_s == 0 && lookback > 1)
            bc_s = Check_BarClose_MultiBar(v_shift, bias, LAYER_3_STRONG, lookback) ? 1 : 0;
         if(bc_s == 1 && bd_pass && momentum_confirmed) {
            m_last_layer = 3;
            if(m_settings.DebugFlow) DebugLog("EvaluateL: L3 (Strong/EMA3-EMA4) PASS → L=1");
            return 1;
         }
      }

      if(m_eval_layer_m == 1 && m_settings.AllowLayer2_Entries && layerS_dir_ok) {
         int bc_m = Eval_BarClose(v_shift, bias, LAYER_2_MEDIUM);
         if(bc_m == 0 && lookback > 1)
            bc_m = Check_BarClose_MultiBar(v_shift, bias, LAYER_2_MEDIUM, lookback) ? 1 : 0;
         if(bc_m == 1 && bd_pass && momentum_confirmed) {
            m_last_layer = 2;
            if(m_settings.DebugFlow) DebugLog("EvaluateL: L2 (Medium/EMA2-EMA3) PASS → L=1");
            return 1;
         }
      }

      if(m_eval_layer_w == 1 && m_settings.AllowLayer1_Entries && layerS_dir_ok) {
         int bc_w = Eval_BarClose(v_shift, bias, LAYER_1_WEAK);
         if(bc_w == 0 && lookback > 1)
            bc_w = Check_BarClose_MultiBar(v_shift, bias, LAYER_1_WEAK, lookback) ? 1 : 0;
         if(bc_w == 1 && bd_pass && momentum_confirmed) {
            m_last_layer = 1;
            if(m_settings.DebugFlow) DebugLog("EvaluateL: L1 (Weak/EMA1-EMA2) PASS → L=1");
            return 1;
         }
      }

      // No layer passed all checks — pick the most specific reason.
      // Reason naming convention: L_<what-failed>, prefix marks the TS-equation
      // factor (L) that rejected, suffix names the specific cause. Renamed in
      // 2026-06 to make journal/grep output consistent.
      m_last_layer = 0;
      if(s_blocked_emerging && m_eval_layer_s == 1 &&
         m_eval_layer_m == 0 && m_eval_layer_w == 0)
         m_diag_last_reason = "L_S_BLOCK_EM";
      else if(m_settings.LayerS_RequireDirAlign && !layerS_dir_ok && m_eval_layer_s == 0 &&
              (m_eval_layer_m == 1 || m_eval_layer_w == 1))
         m_diag_last_reason = "L_S_NOT_DIR_ALIGNED";
      else if(m_eval_g1_blocked)
         // GUARD 1 zeroes the layer, so this MUST precede L_NONE_ALIGNED or the block
         // would be misreported as "no layer aligned" and be invisible in the A/B.
         m_diag_last_reason = "L_G1_POSTFLIP";
      else if(m_eval_layer_w == 0 && m_eval_layer_m == 0 && m_eval_layer_s == 0)
         m_diag_last_reason = "L_NONE_ALIGNED";
      else if(!bd_pass)
         m_diag_last_reason = "L_BD_FAIL";
      else if(!momentum_confirmed)
         m_diag_last_reason = "L_MOMENTUM_FAIL";
      else
         m_diag_last_reason = "L_BC_FAIL";

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
      // The "I" term of the TS equation is a clean pass/fail flag (1/0), matching
      // B*P*L*I*F. The worker EvaluateIndicatorX returns the bias value (+1 long /
      // -1 short) on a pass for its own diagnostics/telemetry; collapse that to
      // 1/0 here so every TS-equation consumer reads an unambiguous flag and
      // direction stays the bias's responsibility (never re-derived from I).
      return (EvaluateIndicatorX(v_shift, bias) != 0) ? 1 : 0;
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
                           double &out_green_mag_cur, double &out_green_mag_prev,
                           bool &out_hist_wants_yellow)
   {
      if(!m_settings.Ind_Dpi_Enabled) return false;
      
      // SURGICAL FIX 1: Hard array bound protection
      if(v_shift < 0) return false;

      int MFast  = m_settings.DPI_MACD_Fast;
      int MSlow  = m_settings.DPI_MACD_Slow;
      int RST    = m_settings.DPI_RedSignalType;

      // Determine Red-EMA period(s) based on signal type
      int redPer1 = 1;  // primary EMA period for Red line
      int redPer2 = 1;  // secondary EMA period (only used when RST == 5 double-smooth)
      switch(RST)
      {
         case 1: redPer1 = m_settings.DPI_RedEMA_A;            redPer2 = redPer1; break;
         case 2: redPer1 = m_settings.DPI_RedEMA_B;            redPer2 = redPer1; break;
         case 3: redPer1 = m_settings.DPI_RedEMA_C;            redPer2 = redPer1; break;
         case 4: redPer1 = m_settings.DPI_RedEMA_D;            redPer2 = redPer1; break;
         case 5: redPer1 = m_settings.DPI_DoubleSmoothFirst;  redPer2 = m_settings.DPI_DoubleSmoothSecond; break;
         default: redPer1 = m_settings.DPI_RedEMA_C;          redPer2 = redPer1; break;
      }

      // bars_needed: Slow-EMA warmup + max(Red EMA) + 1 prev-bar capture + v_shift + warmup margin.
      // The +500 warmup makes the recursive-EMA seed residual underflow to ~0 so the engine's
      // Blue/Red/hist are bit-identical to SEA_IND_DPI_mc_main.mq5 (which warms over full chart
      // history). For the slowest Red (EMA21) the residual after 500 bars is ~1e-21 → exact A≡B,
      // incl. GREEN. CCI is already exact (windowed SMA). See README §9 (parity; no iCustom).
      int maxRed = MathMax(redPer1, redPer2);
      int bars_needed = MSlow + maxRed + v_shift + 500;
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
      out_hist_wants_yellow = false;

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

      // SURGICAL FIX 2: Epsilon Thresholding
      // Floating point calculations often leave infinitesimal residuals (e.g., -1e-15)
      // This forces them to absolute zero to prevent false directional flips in boolean logic
      if(MathAbs(hist) < 1e-9) hist = 0.0;
      if(MathAbs(blue) < 1e-9) blue = 0.0;
      if(MathAbs(hist_at_prev) < 1e-9) hist_at_prev = 0.0;
      if(MathAbs(blue_prev) < 1e-9) blue_prev = 0.0;

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

      // CCI value — computed once, shared by the colour lift and the legacy agreement flag.
      double cci_v = ComputeDPI_CCI(v_shift);
      if(MathAbs(cci_v) < 1e-9) cci_v = 0.0; // Epsilon threshold for CCI

      // out_macd_agree: legacy trend-filter flag. NO LONGER READ by the vote (the old same-bar
      // gate was removed, canonical §7); kept so existing callers' signatures are unaffected.
      //   DPI_UseCCIReset=true  → hist sign agrees with CCI sign
      //   DPI_UseCCIReset=false → hist >= 0 (pass-through)
      if(m_settings.DPI_UseCCIReset)
         out_macd_agree = ((hist >= 0.0 && cci_v >= 0.0) || (hist < 0.0 && cci_v < 0.0));
      else
         out_macd_agree = (hist >= 0.0);

      // ── Ribbon COLOUR — must reproduce SEA_IND_DPI_mc_main.mq5 (lines 480-487) EXACTLY.
      //   The indicator gates CCI-in-colour on InpEnableCCI (default TRUE), giving
      //   colour = sign(CCI). The engine-equivalent of InpEnableCCI is "CCI is not
      //   explicitly ignored" = !DPI_IgnoreCCIForVote.
      //   BUGFIX: this previously also required DPI_UseCCIReset (default FALSE), so the
      //   engine computed colour = sign(hist) while the painted ribbon used sign(CCI).
      //   The two disagreed whenever hist and CCI sat on opposite sides of zero
      //   (e.g. hist≈-0.000 but CCI bullish → ribbon YELLOW yet engine read SHORT,
      //   producing false "DPI:DIR" blocks). DPI_UseCCIReset governs the RESET state
      //   machine, not the colour, so it is no longer ANDed in here. With CCI in
      //   colour → colour = sign(CCI); else (IgnoreCCIForVote=true) → colour = sign(hist).
      bool cci_in_colour = !m_settings.DPI_IgnoreCCIForVote;   // ↔ indicator InpEnableCCI
      if(hist >= 0.0)
         out_hist_wants_yellow = !(cci_in_colour && cci_v <  0.0);
      else
         out_hist_wants_yellow =  (cci_in_colour && cci_v >= 0.0);

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

      // ── Refresh ribbon snapshot (single source of truth for all EMA reads) ──
      // MUST run before any consumer reads ribbon values. Subsequent code in this
      // function (DetectMarketPhase, layer detection, bias, fan filter, etc.) will
      // be migrated in Stage 2 to read from m_ribbon via GetEma1..4() instead of
      // direct GetMAVal(h_ema*) calls. For Stage 1 the snapshot populates only
      // the cockpit/telemetry view; trade decisions still use the legacy path.
      RefreshRibbonSnapshot(v_shift);

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

      // Update PSAR flip tracking on each bar close (uses shift=1 for closed bar).
      // Gated on Ind_Psar_Enabled, NOT Vote_AllowPsarFlip — because Check_PSAR's
      // PSAR_FlipGraceBars feature also reads m_psar_last_flip_time_* and would
      // silently degrade if tracking were skipped when AllowFlip=false. Also
      // removes the startup hole where toggling AllowFlip on mid-session would
      // find an empty tracker.
      if(m_settings.Ind_Psar_Enabled)
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
      m_telemetry.i_suppressed = false;   // A14/A20 2026-07: reset each bar; set in UpdateTelemetry
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
      m_eval_g1_blocked    = false;   // GUARD 1: set by CheckLayerPairAlign this bar
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
      // B is the core's input. EvaluateB sets bias telemetry/stats and, on
      // failure, m_eval_any_failure (BIAS_ZERO / SIGNAL_MISMATCH) internally.
      int B = EvaluateB(v_shift);

      // ── MTF telemetry (voter diagnostic, not a hard gate) ──────────
      // MTF is a voter inside EvaluateIndicatorX; here we only refresh its
      // UI status string. Decision-irrelevant, so it runs once up front.
      if(m_settings.Ind_MTF_Enabled)
      {
         string mtf_reason = "";
         string mtf_diag   = "";
         CheckMTFFilter(B, mtf_reason, mtf_diag);
         m_telemetry.mtf_status = mtf_diag;
      }

      // ── Layer-pullback state must be current before EvaluateL ───────
      // Advanced every bar — the Stats_FullEvaluation=true default already did
      // so; waterfall mode is now consistent with it.
      //
      // SYMMETRY WITH SignalScan (FIX): SignalScan owns two engines and calls
      // UpdateLayerPullback ONLY on bars where its engine's direction is active
      // (SEA_IND_SignalScan.mq5 lines 811–812). On idle bars it does a SOFT reset
      // — Scanner_ResetLayerAfterFire(1/2/3) — that wipes layer pullback states
      // only, preserving baselines / VPRR / DPI-reset / CB-carry / m_last_dir_state_bias.
      //
      // The EA uses ONE engine. Calling UpdateLayerPullbackStates(v_shift, 0) on a
      // UNO bar triggered ResetDirectionalState() (full wipe of baselines etc.),
      // and then a second wipe when bias returned to ±1 on the next bar — destroying
      // every in-progress pullback-recovery cycle. We now mirror SignalScan's idle
      // path on B==0: soft layer-state reset, no engine wipe.
      if(m_settings.BiasMode == BIAS_4EMA)
      {
         if(B != 0)
         {
            // Non-UNO bar — end any UNO run and accumulate cooldown bars (only
            // meaningful when MinBarsAfterUNOExit > 0). A same-direction return
            // does NOT reset layer state: m_last_dir_state_bias was preserved
            // through the tolerated flicker, so the guard inside
            // UpdateLayerPullbackStates does not fire ResetDirectionalState.
            // A genuine flip (B differs from the preserved direction) DOES fire
            // it there — correct.
            m_uno_run = 0;
            if(m_bars_since_uno_exit < 1000000) m_bars_since_uno_exit++;
            UpdateLayerPullbackStates(v_shift, B);
         }
         else
         {
            // UNO bar. Path 2 (2026-07): tolerate a transient UNO flicker.
            m_uno_run++;
            if(m_uno_run <= m_settings.UNO_ToleranceBars)
            {
               // Within tolerance — PRESERVE layer states so a brief UNO that
               // resolves back to the SAME direction does not erase an
               // in-progress DETECTED / RECOVERED. Do not advance the machine
               // (bias absent), do not touch m_last_dir_state_bias, and do not
               // arm the UNO-exit cooldown for a mere flicker.
            }
            else
            {
               // Sustained UNO beyond tolerance — the prior trend is gone. Soft
               // reset layer states (baselines, VPRR, DPI reset, CB carry, and
               // m_last_dir_state_bias are still preserved) and arm the
               // UNO-exit cooldown.
               m_bars_since_uno_exit = 0;
               m_layer_w_pb_state = LAYER_PB_NONE;
               m_layer_m_pb_state = LAYER_PB_NONE;
               m_layer_s_pb_state = LAYER_PB_NONE;
               m_layer_w_bars_det = 0;   // A21 2026-07
               m_layer_m_bars_det = 0;   // A21 2026-07
               m_layer_s_bars_det = 0;   // A21 2026-07
            }
         }
      }
      
      // ── P·F·L·I·CG via the shared core (ONE source of truth) ────────
      // EvaluateTS_Breakdown is the SAME evaluator SignalScan uses for its
      // dotted-lines (EvaluateTS_AtShift) and inspector (Scanner_InspectBar).
      // full_eval mirrors the former waterfall / full-evaluation split; the
      // verdict is identical either way. EvaluateB/P/L record m_eval_any_failure
      // internally — the F-factor stats are mapped from the breakdown below.
      STSBreakdown bd;
      EvaluateTS_Breakdown(v_shift, B, bd, full_eval);
      int L = bd.L;   // kept for the diagnostic summary below
      int I = bd.I;   // kept for the final-decision chain below

      // ── F: stats/telemetry (EvaluateF itself only sets m_last_f_reason) ──
      if(bd.F == 0)
      {
         m_diag_last_reason = bd.F_reason;     // EMA_OVEREXT | DPI_DECEL | DPI_RESET_WAIT | PHASE_AGE | CLIMAX_GUARD
         m_reject_filter++;
         if(bd.F_reason == "EMA_OVEREXT")        m_stats.rejected_emafan++;
         else if(bd.F_reason == "DPI_DECEL")     m_stats.rejected_dpi_decel++;
         else if(bd.F_reason == "PHASE_AGE")     m_stats.rejected_phase_age++;
         else if(bd.F_reason == "CLIMAX_GUARD")  m_stats.rejected_climax++;     // F-AUDIT 2026-06: new counter (Phase K)
         else if(bd.F_reason == "PRICE_OVEREXT") m_stats.rejected_priceext++;   // F-AUDIT 2026-06: new counter (Phase K)
         // F-AUDIT 2026-06: climax now arrives here as F_reason="CLIMAX_GUARD".
         // Apply the layer-reset side effect (was the dedicated bd.CG==0 handler).
         if(bd.F_reason == "CLIMAX_GUARD" && m_settings.ClimaxGuard_ResetPullback)
            ResetAllLayerPullback();
         if(m_settings.DebugFlow)
            DebugLog(StringFormat("[TS_PREFILTER] %s -> TS=0", bd.F_reason));
         if(m_eval_first_failure == "") m_eval_first_failure = bd.F_reason;
         m_eval_any_failure = true;
      }
      else if(bd.F == 1)
      {
         // F passed: Pass% counters for the gates that were active
         if(m_settings.EmaFanFilterEnabled && m_settings.EmaFanMaxTotalPips > 0.0)
            m_stats.passed_emafan++;
         if((m_settings.DpiDecelFilterEnabled && m_settings.Ind_Dpi_Enabled) ||
            (m_settings.DPI_BlockOnDeceleration && m_settings.DPI_HistTrackingEnabled))
            m_stats.passed_dpi_decel++;
         if(m_settings.MinPhaseConfirmBars > 0)
            m_stats.passed_phase_age++;
         if(m_settings.PriceExtFilterEnabled && m_settings.PriceExtMaxATR > 0.0)
            m_stats.passed_priceext++;                                         // F-AUDIT 2026-06 (Phase K)
         if(m_settings.ClimaxGuard_Enabled)
            m_stats.passed_climax++;                                            // F-AUDIT 2026-06 (Phase K)
      }
      // bd.F == -1 → F not reached (waterfall stopped at B/P); no F stats, as before.

      // ════════════════════════════════════════════════════════════
      // FINAL DECISION: TS = B × P × F × L × I  (F-AUDIT 2026-06)
      // F sub-filters live in CSignalEngine::EvaluateF (engine-side
      // pre-filters: EMA fan / price over-ext / DPI decel / phase-age /
      // climax). The separate TE-side EvaluateF (TradeExecutor) handles
      // spread / session / news at bar-open and is the "F'" of TE = F'.
      // Verdict short-circuits in the bd.F == 0 branch above by setting
      // m_eval_any_failure = true, which is the gate read at line 7802.
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
      // F-AUDIT 2026-06: dedicated `bd.CG == 0` handler removed — Climax now
      // arrives via bd.F == 0 with F_reason == "CLIMAX_GUARD" (handled in the
      // F=0 branch above, including the ResetAllLayerPullback side effect).
      else {
         // All factors passed → signal confirmed
         // TS = 1 (confirmed) or 0 (rejected). Direction is in m_diag_last_bias (+1/-1).
         final_signal = 1;
         // Note: m_diag_last_bias was already set by EvaluateB; update for consistency
         m_diag_last_bias = B;
         // TS-level counters (moved here from EvaluateIndicatorX so they reflect
         // actual TS=1 events, not just indicator-vote passes that B/P/L/CG/F
         // later veto).
         m_signals_generated++;
         m_stats.signals_confirmed++;
         if(B > 0) m_stats.signals_confirmed_long++;
         else      m_stats.signals_confirmed_short++;
         m_ts_status_string = StringFormat("B[%s] | P[%s] | L[L%d] | I[OK]",
                                            (B > 0 ? "L" : (B < 0 ? "S" : "0")),
                                            EnumToString(m_diag_last_phase),
                                            m_last_layer);
         if(m_settings.DebugFlow && final_signal != 0)
            DebugLog(StringFormat("[RESULT] TS=%d", final_signal));

         // ── Pullback cycle reset after TS=1 ───────────────────────────
         // A RECOVERED state is a one-shot gate: it is earned by a pullback
         // and consumed by the entry on THAT layer. Reset ONLY the winning
         // layer (m_last_layer) so the other two retain their independent
         // RECOVERED setups — they represent different timeframes (W=EMA1/2,
         // M=EMA2/3, S=EMA3/4) and each layer's cycle is independent of the
         // others. Previously all three were reset together, which created a
         // deadlock in trending markets: after one trade no layer could fire
         // until fresh pullback-recovery cycles completed on EACH layer.
         if(m_settings.LayerPullbackEnabled)
         {
            if(m_last_layer == 1 && m_layer_w_pb_state == LAYER_PB_RECOVERED)
            {
               m_layer_w_pb_state = LAYER_PB_NONE;
               m_layer_w_bars_det = 0;   // A21 2026-07
               if(m_settings.DebugFlow)
                  DebugLog("[PB_RESET] LayerW: RECOVERED → NONE (TS=1 consumed pullback cycle)");
            }
            else if(m_last_layer == 2 && m_layer_m_pb_state == LAYER_PB_RECOVERED)
            {
               m_layer_m_pb_state = LAYER_PB_NONE;
               m_layer_m_bars_det = 0;   // A21 2026-07
               if(m_settings.DebugFlow)
                  DebugLog("[PB_RESET] LayerM: RECOVERED → NONE (TS=1 consumed pullback cycle)");
            }
            else if(m_last_layer == 3 && m_layer_s_pb_state == LAYER_PB_RECOVERED)
            {
               m_layer_s_pb_state = LAYER_PB_NONE;
               m_layer_s_bars_det = 0;   // A21 2026-07
               if(m_settings.DebugFlow)
                  DebugLog("[PB_RESET] LayerS: RECOVERED → NONE (TS=1 consumed pullback cycle)");
            }
         }
      }

      // Ensure UI vote counter is up-to-date
         // m_diag_last_votes set from vote_pass above.
      
      // ===== TS PIPELINE SUMMARY =====
      if(m_settings.DebugLevel >= DEBUG_INDICATORS) {
         datetime sum_bar_time = iTime(m_symbol, PERIOD_CURRENT, m_settings.ma_v_shift);
         DebugLog("════════════════════════════════════════════════════════════");
         DebugLog(StringFormat("[TS_SUMMARY] Bar: %s (shift=%d)",
                               TimeToString(sum_bar_time, TIME_DATE|TIME_MINUTES),
                               m_settings.ma_v_shift));
         DebugLog("════════════════════════════════════════════════════════════");
         DebugLog("");

         // F (FILTERS) — post-F-AUDIT 2026-06: TS-side and TE-side are now distinct.
         //   TS-side F (engine: CSignalEngine::EvaluateF, bar-close shift=1):
         //     EMA fan over-extension × price over-extension × DPI decel
         //     × phase-age confirmation × climax guard
         //   TE-side F' (executor: CTradeExecutor::EvaluateF, bar-open shift=0):
         //     spread (live) × session time × news (live)
         //   MTF is a voter inside EvaluateI (not part of F).
         DebugLog("F (TS-side pre-filters — bar close, shift=1):");
         DebugLog(StringFormat("  %s EMA fan:    %s",
                               (m_settings.EmaFanFilterEnabled && (m_settings.EmaFanMaxTotalPips > 0.0 || m_settings.EmaFanMaxPct > 0.0)) ? "✅" : "⏭️",
                               m_settings.EmaFanFilterEnabled ? "enabled" : "disabled"));
         DebugLog(StringFormat("  %s Price ext:  %s",
                               (m_settings.PriceExtFilterEnabled && m_settings.PriceExtMaxATR > 0.0) ? "✅" : "⏭️",
                               m_settings.PriceExtFilterEnabled ? "enabled" : "disabled"));
         DebugLog(StringFormat("  %s DPI decel:  %s",
                               ((m_settings.DpiDecelFilterEnabled && m_settings.Ind_Dpi_Enabled) ||
                                (m_settings.DPI_BlockOnDeceleration && m_settings.DPI_HistTrackingEnabled)) ? "✅" : "⏭️",
                               (m_settings.DpiDecelFilterEnabled || m_settings.DPI_BlockOnDeceleration) ? "enabled" : "disabled"));
         DebugLog(StringFormat("  %s Phase age:  %s",
                               (m_settings.RequireMinPhaseConfirm && m_settings.MinPhaseConfirmBars > 0) ? "✅" : "⏭️",
                               m_settings.RequireMinPhaseConfirm ? "enabled" : "disabled"));
         DebugLog(StringFormat("  %s Climax:     %s",
                               m_settings.ClimaxGuard_Enabled ? "✅" : "⏭️",
                               m_settings.ClimaxGuard_Enabled ? "enabled" : "disabled"));
         DebugLog("F' (TE-side exec gates — bar open, shift=0):");
         DebugLog("  ⏭️  Spread: checked at TE (" + (m_settings.UseSpread ? "enabled" : "disabled") + ")");
         DebugLog("  ⏭️  Time window: checked at TE (" + (m_settings.TradingHoursEnabled ? "active" : "disabled") + ")");
         DebugLog("  ⏭️  News filter: checked at TE (" + (m_settings.UseNews ? "active" : "disabled") + ")");
         DebugLog("  ✅ MTF voter: checked at TS within EvaluateI (" + (m_settings.Ind_MTF_Enabled ? "enabled" : "disabled") + ")");
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
         // BUGFIX A8 2026-06: MTF and VPRR voters were missing from this tally.
         // CAST_VOTE_STAT (EvaluateIndicatorX) includes both — the diagnostic
         // banner must match the actual voter set (19 indicators total).
         if(m_settings.Ind_MTF_Enabled)          s_enabled++; else s_disabled++;
         if(m_settings.VPRR_Enabled)             s_enabled++; else s_disabled++;

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
                                  "ALL"));
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
         // Diagnostic-only reads. On invalid we degrade gracefully to "POS"
         // (generic position-failure label) — doesn't affect trade decisions.
         bool ok_f, ok_s;
         double f_val = GetMAValSafe(BiasFastHandle(), v_shift, ok_f);
         double s_val = GetMAValSafe(BiasSlowHandle(), v_shift, ok_s);
         int f_slope = GetSlope(BiasFastHandle(), v_shift);

         if(m_diag_last_reason == "PHASE_UNORDERED" || m_diag_last_reason == "PHASE") m_eval_str_B = "PHASE";
         else if(!ok_f || !ok_s) m_eval_str_B = "INV";
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
      // Mirror the ribbon snapshot — populated by RefreshRibbonSnapshot at top of EvaluateTS.
      // Cockpit reads from this; periods are sourced from m_settings.P_Ema1..4 at display time.
      m_telemetry.ribbon = m_ribbon;

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

   // B1 2026-06: GetBias_PhaseBased() removed (was unreachable dead code).
   // The function had two callers historically; the only HEAD reference was
   // EvaluateBias's BIAS_4EMA branch, which was itself unreachable because
   // EvaluateB short-circuits BIAS_4EMA before reaching EvaluateBias. The
   // function's semantics (combined direction extraction + phase-gate
   // blocking) were superseded by the split architecture:
   //   - GetBias_4EMA_Direction(v_shift)  — pure direction (no gating)
   //   - EvaluateP(v_shift, bias)          — phase-gate (UNORDERED/EMERGING blocks)
   // See SEA_SignalEngine.mqh:~7068 and ~7225 for the live equivalents.

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
      double ema2, ema3, ema4;
      bool   ok2, ok3, ok4;

      // Hot path: shift matches the cached snapshot — read directly from m_ribbon
      if(shift == m_ribbon.shift)
      {
         ok2  = m_ribbon.valid[1]; ema2 = m_ribbon.ema[1];
         ok3  = m_ribbon.valid[2]; ema3 = m_ribbon.ema[2];
         ok4  = m_ribbon.valid[3]; ema4 = m_ribbon.ema[3];
      }
      else if(shift == m_ribbon.shift + 1)
      {
         // Previous bar in the snapshot
         ok2  = m_ribbon.valid_prev[1]; ema2 = m_ribbon.ema_prev[1];
         ok3  = m_ribbon.valid_prev[2]; ema3 = m_ribbon.ema_prev[2];
         ok4  = m_ribbon.valid_prev[3]; ema4 = m_ribbon.ema_prev[3];
      }
      else
      {
         // Historical scan (e.g. phase-stability sweep) — full safe chain per slot
         string src_ignored;
         ema2 = ReadEmaSafe(2, shift, ok2, src_ignored);
         ema3 = ReadEmaSafe(3, shift, ok3, src_ignored);
         ema4 = ReadEmaSafe(4, shift, ok4, src_ignored);
      }

      // Refuse classification if any required slot is invalid — safe default
      // (caller treats PHASE_UNORDERED as no-signal, blocking trade).
      if(!ok2 || !ok3 || !ok4) return PHASE_UNORDERED;
      if(ema2 == EMPTY_VALUE || ema3 == EMPTY_VALUE || ema4 == EMPTY_VALUE)
         return PHASE_UNORDERED;

      // TM: perfect ascending/descending stack (pure positional — no slopes)
      // Slopes are validated downstream by the Entry Layer system.
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
