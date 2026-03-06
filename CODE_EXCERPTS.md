# Key Code Excerpts from RRM_SEA

## 1. EAutoStrategy Enum (SEA_Config.mqh)

```mql5
enum EAutoStrategy
{
   STRAT_SINGLE_SLOPE,     // Single EMA direction
   STRAT_PAIR_CROSS,       // EMA crossover (RRM uses this)
   STRAT_PRICE_CROSS       // Price vs EMA
};
```

---

## 2. EMarketPhase Enum (SEA_Config.mqh, Line 59)

```mql5
enum EMarketPhase {
   PHASE_UNORDERED,   // EMAs crossed/mixed - choppy market (NO TRADE)
   PHASE_EMERGING,    // EMAs forming trend - EMA4(89) between EMA2(13) and EMA3(34)
   PHASE_TRENDING     // EMAs fully stacked - strong established trend
};
```

---

## 3. EEntryLayer Enum (SEA_Config.mqh, Line 65)

```mql5
enum EEntryLayer {
   LAYER_NONE,        // No layer detected or detection disabled
   LAYER_1_WEAK,      // Layer 1: price touched EMA1/EMA2 zone (shallow pullback)
   LAYER_2_MEDIUM,    // Layer 2: price touched EMA2/EMA3 zone (medium pullback)
   LAYER_3_STRONG     // Layer 3: price touched EMA3/EMA4 zone (deep pullback)
};
```

---

## 4. EStrategyPreset Enum (SEA_Config.mqh, Line 12)

```mql5
enum EStrategyPreset
{
   PRESET_CUSTOM,             // User controlled (no preset overrides)
   PRESET_MA_BENCHMARK,       // MT5 MA compatibility
   PRESET_TREND_REVERSAL,     // Trend Reversal (Baseline)
   PRESET_TREND_SCALP,        // Trend Scalp (Intraday)
   PRESET_TREND_SWING,        // Trend Swing (Institutional)
   PRESET_RANGE_GRID,         // Range Grid (Conservative mean reversion)
   PRESET_RRM_ATR,            // RRM ATR Trend Pullback (OPTIMIZED)
   PRESET_RRM                 // RRM Strict No-ATR Trend Pullback
};
```

---

## 5. ST_Settings Struct (SEA_Config.mqh) - Key Fields

```mql5
struct ST_Settings
{
   // Logic
   bool CloseOnReverse;

   // Risk Management
   double RiskPercent;
   double MaxTotalRisk;          // Max % portfolio risk simultaneously (e.g., 4.0)
   int    MaxOpenTrades;         // Max concurrent trades (0 = no limit)
   bool   CountBEasZeroRisk;     // Breakeven trades don't count toward risk
   double MaxSpread;
   double MinATR;
   double MaxATR;
   bool   ATR_HardGate;
   bool   Use_ATRVote;

   // RRM (Trend Pullback)
   int    RRM_Lookback;
   double RRM_MinDivPips;

   // Bias
   bool          BiasEnabled;
   EBiasMode     BiasMode;       // AUTO, AUTO_PHASE, or MANUAL
   EManualSide   ManSide;
   EAutoStrategy AutoStrat;      // Which entry strategy to use
   int           BiasFastID;     // 0=EMA1(5), 1=EMA2(13), 2=EMA3(34), 3=EMA4(89)
   int           BiasSlowID;

   // EMAs (4-ribbon structure)
   int P_Ema1;                   // Default: 5
   int P_Ema2;                   // Default: 13
   int P_Ema3;                   // Default: 34 (RRM uses as fast bias)
   int P_Ema4;                   // Default: 89 (RRM uses as slow bias)

   // Indicator weights (voting)
   int Ind_EmaSig_Weight;
   int Ind_Adx_Weight;
   int Ind_Macd_Weight;
   int Ind_Rsi_Weight;
   int Ind_Cci_Weight;
   int Ind_Mfi_Weight;
   int Ind_Sto_Weight;
   int Ind_Bb_Weight;
   int Ind_Psar_Weight;
   int Ind_P123_Weight;
   int Ind_Ross_Weight;

   // Execution
   EMaMethod MaType;
   int       ma_h_shift;
   int       ma_v_shift;

   // Phase Detection (PR1)
   bool PhaseDetectionEnabled;
   bool BlockUnorderedPhase;
   bool RequireMinPhaseConfirm;
   int  MinPhaseConfirmBars;

   // Layer Detection (PR3)
   bool   EnableLayerDetection;
   double LayerTouchTolerancePips;
   bool   AllowLayer1_Entries;
   bool   AllowLayer2_Entries;
   bool   AllowLayer3_Entries;

   // Phase-specific permissions
   bool Emerging_AllowWeakTrades;
   bool Emerging_AllowMediumTrades;
   bool Emerging_AllowStrongTrades;
   bool Trending_AllowWeakTrades;
   bool Trending_AllowMediumTrades;
   bool Trending_AllowStrongTrades;

   // ... 100+ more fields (SL, TP, trailing, indicators, filters, etc.)
};
```

---

## 6. DetectEntryLayer() Function (SEA_SignalEngine.mqh, Line 2457)

```mql5
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
```

---

## 7. AutoStrat Signal Generation (SEA_SignalEngine.mqh, Line 1797)

```mql5
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
else {  // STRAT_PAIR_CROSS (RRM DEFAULT)
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
                        (market_bias == 1) ? ">" : "<", s_curr_cross, entry_signal);
         }
      }
   }
}
```

---

## 8. PRESET_RRM Definition (SEA_Presets.mqh, Lines 674-850)

```mql5
if(preset == PRESET_RRM)
{
   // RRM: user-owned exits (SL/TP/BE/trailing preserved from InitializeConfig mapping).
   // Architecture: Filters → Bias → Votes → User-controlled Exits
   
   ERRMMode mode = Inp_RRM_Mode;
   if(mode == RRM_AUTO_BY_TF)
   {
      if(_Period == PERIOD_M1 || _Period == PERIOD_M5 || _Period == PERIOD_M15) 
         mode = RRM_SCALP;
      else 
         mode = RRM_SWING;
   }

   cfg.CloseOnReverse = true;
   cfg.BiasEnabled    = true;
   cfg.BiasMode       = Inp_BiasMode;  // AUTO or AUTO_PHASE
   cfg.MaType         = METHOD_EMA;
   
   // ATR FULLY DISABLED
   cfg.MinATR       = 0.0;
   cfg.MaxATR       = 0.0;
   cfg.ATR_HardGate = false;
   cfg.Use_ATRVote  = false;

   // BIAS CONFIGURATION
   if(cfg.BiasMode == BIAS_AUTO_PHASE)
   {
      cfg.AutoStrat  = STRAT_PAIR_CROSS;
      cfg.BiasFastID = 2;  // EMA3(34)
      cfg.BiasSlowID = 3;  // EMA4(89)
      cfg.P_Ema1 = 5; cfg.P_Ema2 = 13; cfg.P_Ema3 = 34; cfg.P_Ema4 = 89;
      cfg.MaxSpread = (mode == RRM_SCALP) ? 2.0 : 4.0;
   }
   else  // BIAS_AUTO
   {
      cfg.AutoStrat  = STRAT_PAIR_CROSS;
      cfg.BiasFastID = 2;  // EMA3(34)
      cfg.BiasSlowID = 3;  // EMA4(89)
      cfg.P_Ema1 = 5; cfg.P_Ema2 = 13; cfg.P_Ema3 = 34; cfg.P_Ema4 = 89;
      cfg.MaxSpread = (mode == RRM_SCALP) ? 2.0 : 4.0;
   }

   // VOTING (EMA + MACD/CCI/PSAR, NO ATR)
   cfg.VoteThreshold          = 4;
   cfg.VoteMode               = VOTE_MODE_ALL;  // All enabled indicators must agree
   cfg.Ind_EmaSig_Enabled     = true;
   cfg.Ind_Adx_Enabled        = false;
   cfg.Ind_Macd_Enabled       = true;
   cfg.Ind_Rsi_Enabled        = false;
   cfg.Ind_Cci_Enabled        = true;
   cfg.Ind_Mfi_Enabled        = false;
   cfg.Ind_Sto_Enabled        = false;
   cfg.Ind_Bb_Enabled         = false;
   cfg.Ind_Psar_Enabled       = true;
   cfg.Ind_P123_Enabled       = false;
   cfg.Ind_Ross_Enabled       = false;

   cfg.P_MacdFast             = 8;
   cfg.P_MacdSlow             = 13;
   cfg.P_MacdSig              = 8;
   cfg.MacdVoteMode           = MACD_HISTOGRAM;
   cfg.MacdRequireSlope       = false;
   cfg.MacdRequireDivergence  = false;
   cfg.MacdRequireHook        = false;
   cfg.MacdFreshBars          = 3;
   cfg.MacdSlopeMin           = 0.00001;

   // PROTECTION FEATURES
   cfg.RequirePullback           = true;
   cfg.PullbackLookback          = (tf <= PERIOD_M5 ? 20 : 15);
   cfg.RequireRecoveryMomentum   = true;
   cfg.Gate_UseMultiLayer        = true;
   cfg.RRM_Lookback           = 5;
   cfg.RRM_MinDivPips         = 1.5;

   // PHASE DETECTION (enabled in PRESET_RRM)
   cfg.PhaseDetectionEnabled      = true;
   cfg.EnableLayerDetection       = true;
   cfg.BlockUnorderedPhase        = true;
   cfg.RequireMinPhaseConfirm     = true;
   cfg.MinPhaseConfirmBars        = 4;

   // LAYER PERMISSIONS (phase-specific)
   cfg.Emerging_AllowWeakTrades   = true;
   cfg.Emerging_AllowMediumTrades = true;
   cfg.Emerging_AllowStrongTrades = false;  // Block deep pullbacks in emerging trend
   cfg.Trending_AllowWeakTrades   = true;
   cfg.Trending_AllowMediumTrades = true;
   cfg.Trending_AllowStrongTrades = true;

   // EXIT CONFIGURATION (Swing-based SL, PSAR trailing)
   cfg.ExitProfile           = EXIT_PROFILE_RRM_STRICT_NO_ATR;
   cfg.SL_PlacementMode      = SL_SWING_HIGHLOW;
   cfg.SL_Mult               = 0.0;  // ATR disabled
   cfg.SL_SwingPipsCushion   = GetRecommendedInitialSlCushionPips();
   cfg.SL_PsarPipsCushion    = GetRecommendedInitialSlCushionPips();
   cfg.TP_Mult               = 3.0;
   cfg.TP_Enabled            = true;
   cfg.TrailMode             = TRAIL_PSAR;
   cfg.PSAR_TrailCushionMode = PSAR_CUSHION_PIPS;
   cfg.PSAR_TrailPipsCushion = GetRecommendedTrailPsarCushionPips();
   cfg.Use_BE                = true;
   cfg.BE_Mode               = BE_MODE_R_MULTIPLE;

   // RISK LIMITS (portfolio-level)
   cfg.MaxTotalRisk      = 4.0;   // Max 4% total portfolio risk
   cfg.MaxOpenTrades     = 3;     // Max 3 concurrent trades
   cfg.CountBEasZeroRisk = true;

   // Restore operator-controlled gates (Policy A)
   cfg.MaxSpread = op_MaxSpread;
   cfg.UseTime   = op_UseTime;
   cfg.StartHr   = op_StartHr;
   cfg.EndHr     = op_EndHr;
   cfg.UseNews   = op_UseNews;
   cfg.NewsPre   = op_NewsPre;
   cfg.NewsPost  = op_NewsPost;
   cfg.UseHTF    = op_UseHTF;
   cfg.HtfPeriod = op_HtfPeriod;
   cfg.P_HtfEma  = op_P_HtfEma;

   ApplyAdminOverrides(cfg);
}
```

---

## 9. Main EA Global Variables (SimpleEA_v1-03.mq5)

```mql5
// MODULE OBJECTS
CSignalEngine  Signal;      // Signal processing
CTradeExecutor Executor;    // Trade execution

// EFFECTIVE CONFIGURATION (after preset application)
EEmaStrategy g_effectiveEmaStrategy;
EMaMethod    g_effectiveMaType;
EBiasMode    g_effectiveBiasMode;
string       g_effectiveSigNote;
string       g_effectiveDirSource;

// UI/TRACKING
datetime g_last_bar_time            = 0;
datetime g_start_time               = 0;
bool     g_chart_indicators_managed = false;

// TRADE SIGNAL STATE (TS = Trade Signal at bar close)
datetime g_ts_time   = 0;
int      g_ts_dir    = 0;      // 1=BUY, -1=SELL
int      g_ts_bias   = 0;
int      g_ts_votes  = 0;
int      g_ts_thr    = 0;
string   g_ts_reason = "";

// TWO-PHASE ENTRY STATE
// Phase 1: TS evaluated at bar-close (shift=1)
// Phase 2: TE evaluated on next bar first tick (shift=0)
bool     g_ts_active    = false;      // True while TS signal pending TE execution
datetime g_ts_bar_time  = 0;          // Bar N open-time when TS generated
int      g_ts_direction = 0;          // TS direction: 1=BUY, -1=SELL
datetime g_last_te_bar_time = 0;      // Bar time when TE executed

// RRM DRAWDOWN PROTECTION
int      g_consecutive_losses     = 0;
int      g_trades_today           = 0;
datetime g_last_trade_date        = 0;
double   g_daily_starting_balance = 0.0;
```

---

## 10. Key Input Parameters (SEA_Config.mqh)

### Zone 1: Preset Selection
```mql5
input group "══════════ 🎯 ZONE 1: PRESET SELECTION ══════════"
input ulong           Inp_MagicNum   = 12345;        // Magic number
input EStrategyPreset InpPreset      = PRESET_RRM;   // (DEFAULT: RRM)
```

### Zone 2: User Controls (Policy A - Always Editable)
```mql5
input group "──── ✅ Operator Gates: Spread & ATR Limits ────"
input double Inp_MaxSpreadPips = 3.0;    // Max spread (pips)
input double Inp_MinATRPips    = 0.0;    // Min ATR (0=off)
input double Inp_MaxATRPips    = 20.0;   // Max ATR (0=off)

input group "──── ✅ Operator Gates: Session Time Filter ────"
input bool Inp_UseTime   = false;  // Enable time filter
input int  Inp_StartHour = 8;      // Session start
input int  Inp_EndHour   = 20;     // Session end

input group "──── ✅ Diagnostics ────"
input bool Inp_PrintEffectiveConfig = true;  // Print config on init
input bool Inp_DebugFlow            = true;  // Enable diagnostic logging
```

### Zone 3A: Pipeline Config (Overridden by Presets)
```mql5
input group "═══ 🔧 STEP 1: Bias Calculation ═══"
input bool           Inp_BiasEnabled = true;
input EBiasMode      Inp_BiasMode    = BIAS_AUTO_PHASE;
input int            Inp_BiasFastID  = 2;   // EMA3(34)
input int            Inp_BiasSlowID  = 3;   // EMA4(89)
input EAutoStrategy  Inp_AutoStrat   = STRAT_PAIR_CROSS;

input group "═══ 🔧 STEP 2: Entry Signal ═══"
input ERRMMode  Inp_RRM_Mode         = RRM_AUTO_BY_TF;
input bool      Inp_RRM_EnableInCustom = false;
input bool      Inp_CloseOnReverse   = false;

input group "═══ 🔧 STEP 5: Pullback Gate ═══"
input bool   Inp_Gate_UseMultiLayer = false;
input bool   Inp_Gate_RequirePullback = false;
input int    Inp_Gate_PullbackLookback = 15;
input bool   Inp_Gate_RequireRecoveryMomentum = false;

input group "═══ 🔧 STEP 6: Voting ═══"
input bool Inp_VoteMode_All = true;    // ALL mode: all must agree
input int  Inp_VoteThreshold = 4;

input group "═══ 📊 Indicator: EmaSig ═══"
input bool   Inp_Ind_EmaSig_Enabled = true;
input int    Inp_Ind_EmaSig_Weight  = 1;

input group "═══ 📊 Indicator: MACD ═══"
input bool          Inp_Ind_Macd_Enabled = true;
input int           Inp_Ind_Macd_Weight  = 1;
input EMacdVoteMode Inp_MacdVoteMode     = MACD_ZERO_AND_CROSS;
input int           Inp_P_MacdFast       = 8;
input int           Inp_P_MacdSlow       = 13;
input int           Inp_P_MacdSig        = 8;

input group "═══ 📊 Indicator: CCI ═══"
input bool    Inp_Ind_Cci_Enabled = true;
input int     Inp_Ind_Cci_Weight  = 1;
input ECciMode Inp_Ind_Cci_Mode   = CCI_TREND_ZERO;

input group "═══ 📊 Indicator: PSAR ═══"
input bool   Inp_Ind_Psar_Enabled = true;
input int    Inp_Ind_Psar_Weight  = 1;

input group "── Step 9: Risk & Execution ──"
input double Inp_RiskPercent = 2.0;

input group "── SL Placement ──"
input ESlPlacementMode Inp_SL_PlacementMode = SL_SWING_HIGHLOW;
input double           Inp_SL_SwingPipsCushion = 10.0;

input group "── TP & Trailing ──"
input double        Inp_TP_Mult  = 3.0;
input ETrailingMode Inp_TrailMode = TRAIL_PSAR;
input double        Inp_PSAR_TrailPipsCushion = 5.0;
```

---

## Summary Table

| Item | Location | Key Details |
|------|----------|------------|
| **EAutoStrategy** | SEA_Config.mqh | 3 options: SINGLE_SLOPE, PAIR_CROSS (RRM), PRICE_CROSS |
| **EMarketPhase** | SEA_Config.mqh, line 59 | 3 phases: UNORDERED, EMERGING, TRENDING |
| **EEntryLayer** | SEA_Config.mqh, line 65 | 4 layers: NONE, WEAK (L1), MEDIUM (L2), STRONG (L3) |
| **ST_Settings** | SEA_Config.mqh | 100+ config fields for all aspects |
| **DetectEntryLayer()** | SEA_SignalEngine.mqh, line 2457 | Passive layer detection by price-EMA proximity |
| **GetDirection()** | SEA_SignalEngine.mqh, line 1528 | 9-step signal validation pipeline |
| **AutoStrat Signal** | SEA_SignalEngine.mqh, line 1797 | Generates entry direction per strategy |
| **PRESET_RRM** | SEA_Presets.mqh, line 674 | Strict no-ATR with phase/layer detection |
| **PRESET_RRM_ATR** | SEA_Presets.mqh, line 574 | RRM with ATR voting, more permissive |
| **Main EA** | SimpleEA_v1-03.mq5 | Two-phase entry (TS at bar close, TE next bar open) |
| **Inputs** | SEA_Config.mqh, line 554+ | 100+ inputs grouped by Zone 1-3C |

