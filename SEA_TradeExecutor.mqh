//+------------------------------------------------------------------+
//|                                            SEA_TradeExecutor.mqh |
//|                              MJS Institutional Trading Solutions |
//| Purpose: Order Execution, Safety, Trailing & Position Management |
//| Status:  PRODUCTION READY (Cached Handles & Decoupling Fixed)    |
//+------------------------------------------------------------------+
#property strict

#ifndef SEA_BUILD_TOKEN_105001
enum { __SEA_BUILD_TOKEN_MISSING_TRADEEXEC_105001 = SEA_BUILD_TOKEN_105001 };
#endif

#define SEA_MOD_TRADEEXEC_105001 1
#define SEA_LARGE_LOT_EQUITY_BLOCK_USD 10000.0
#define SEA_LARGE_LOT_PER_EQUITY_BLOCK 10.0
#define SEA_MARGIN_LEVEL_UNLIMITED 999999.0

#include <RRMS\SEA_Inputs.mqh>
#include <Trade\Trade.mqh>

class CTradeExecutor {
private:
   CTrade      m_trade;
   ulong       m_magic;
   ST_Settings m_settings;
   SNewsEvent  m_news_events[];
   int         m_news_count;
   string      m_symbol;
   string      m_te_veto_reason;
   string      m_rc_veto_reason; // specific veto label set by EvaluateRC(), read by EvaluateTE()
   
   // Indicator Handles (Fixes Asynchronous CopyBuffer failures)
   int         m_h_psar;
   int         m_h_fractals;
   int         m_h_cushion_atr;  // ATR handle for PSAR_CUSHION_ATR (cached)
   int         m_h_sl_atr;       // ATR handle for SL_MODE_ATR initial SL (cached)
   int         m_h_trail_ema_atr; // ATR handle for TRAIL_EMA cushion (cached)
   
   // Telemetry Cache
   datetime    m_last_trade_bar;
   datetime    m_last_close_bar;   // bar on which the last position was closed (same-bar re-entry guard)
   ulong       m_last_tracked_ticket; // previous-call ticket for close detection in EvaluateTM
   datetime    m_last_risk_warn;
   ulong       m_rrm_last_ticket;
   bool        m_rrm_trail_frozen;
   bool        m_rrm_be_reached;
   double      m_rrm_initial_sl;
   datetime    m_last_tm_bar;      // last bar on which EvaluateTM ran (gate)
   double      m_initial_sl_price; // SL price captured at trade entry (never changes)
   datetime    m_rrm_freeze_time;
   datetime    m_trail_ema_last_bar;   // TRAIL_EMA: last bar time checked (shift=1 evaluation only)
   datetime    m_last_marker_update;
   datetime    m_last_te_time;
   string      m_last_te_result;
   string      m_last_te_reason;
   double      m_cached_sl;    // SL pre-computed from historical anchor (EvaluateCM)
   double      m_cached_lots;  // Lots from m_cached_sl (EvaluateCM)
   double      m_cached_risk;  // Risk % (EvaluateCM)
   int         m_spread_block_bars;  // consecutive new-bar EvaluateTE calls blocked by VETO_SPREAD

   // ── PHASE A.1: TE-side rejection counters (read by SEA_SignalEngine via AddTeStats) ──
   int         m_te_rej_open_delay;
   int         m_te_rej_bc_recheck;
   int         m_te_rej_spread_median;
   int         m_te_pass_open_delay;
   int         m_te_pass_bc_recheck;
   int         m_te_pass_spread_median;

   // ── F-AUDIT 2026-06: TE-side Time/News/Spread counters ──
   // The original EvaluateFilterX (in CSignalEngine) bumped these into
   // m_stats.passed_*/rejected_* but had no callers. The actual T/N/S gates
   // live HERE (CTradeExecutor::EvaluateF). These counters get bridged into
   // CSignalEngine.m_stats at OnDeinit via the extended AddTeStats() call.
   int         m_te_rej_time,    m_te_pass_time;
   int         m_te_rej_news,    m_te_pass_news;
   int         m_te_rej_spread,  m_te_pass_spread;

   // ── DPI Histogram Exit: state cached from CSignalEngine each bar ──
   double      m_dpi_hist_current;       // Current CCI value from DPI tracking
   int         m_dpi_hist_trend;         // +1 = CCI positive, -1 = CCI negative, 0 = flat
   bool        m_dpi_hist_decelerating;  // True if momentum decelerating
   bool        m_dpi_hist_green_present; // True if GREEN area exists (Blue & hist aligned)
   int         m_exits_dpi_hist;         // Count of positions closed by DPI histogram exit

   // ── PHASE B: median-spread ring buffer for TE_SpreadMedianTicks gate ──
   double      m_spread_history[32];   // sized for max plausible TE_SpreadMedianTicks
   int         m_spread_history_count;
   int         m_spread_history_idx;
   
    // Position excursion tracking
    struct SPositionExcursion {
       ulong    ticket;
       datetime entry_time;
       double   entry_price;
      double   mae_pips;
      double   mfe_pips;
      double   current_pips;
      bool     be_reached;
      bool     trail_active;
      string   trail_type;
   };

    SPositionExcursion m_excursion;

    struct SPositionState {
       ulong    ticket;
       bool     be_triggered;
       double   peak_profit_pips;
       datetime last_update;
    };

    SPositionState m_position_states[];

    int FindPositionStateIndex(ulong ticket) {
       for(int i = 0; i < ArraySize(m_position_states); i++) {
          if(m_position_states[i].ticket == ticket) return i;
       }
       return -1;
    }

    void InitPositionState(ulong ticket) {
       int idx = FindPositionStateIndex(ticket);
       if(idx >= 0) {
          m_position_states[idx].last_update = TimeCurrent();
          return;
       }
       int size = ArraySize(m_position_states);
       ArrayResize(m_position_states, size + 1);
       m_position_states[size].ticket = ticket;
       m_position_states[size].be_triggered = false;
       m_position_states[size].peak_profit_pips = 0.0;
       m_position_states[size].last_update = TimeCurrent();
    }

    void RemovePositionState(ulong ticket) {
       int idx = FindPositionStateIndex(ticket);
       if(idx < 0) return;
       int size = ArraySize(m_position_states);
       for(int i = idx; i < size - 1; i++) m_position_states[i] = m_position_states[i + 1];
       ArrayResize(m_position_states, size - 1);
    }

    void CleanupClosedPositionStates() {
       for(int i = ArraySize(m_position_states) - 1; i >= 0; i--) {
          if(!PositionSelectByTicket(m_position_states[i].ticket)) RemovePositionState(m_position_states[i].ticket);
       }
    }

    bool GetPositionBETriggered(ulong ticket) {
       int idx = FindPositionStateIndex(ticket);
       return (idx >= 0) ? m_position_states[idx].be_triggered : false;
    }

    void SetPositionBETriggered(ulong ticket, bool value) {
       int idx = FindPositionStateIndex(ticket);
       if(idx >= 0) {
          m_position_states[idx].be_triggered = value;
          m_position_states[idx].last_update = TimeCurrent();
       }
    }

    double UpdatePositionPeakProfit(ulong ticket, double profit_pips) {
       InitPositionState(ticket);
       int idx = FindPositionStateIndex(ticket);
       if(idx < 0) return profit_pips;
       if(profit_pips > m_position_states[idx].peak_profit_pips) m_position_states[idx].peak_profit_pips = profit_pips;
       m_position_states[idx].last_update = TimeCurrent();
       return m_position_states[idx].peak_profit_pips;
    }

    double CalculateProfitPercentTrailSL(ulong ticket,
                                         ENUM_POSITION_TYPE pos_type,
                                         double entry_price,
                                         double current_price,
                                         double current_sl,
                                         double pipSize,
                                         int digits) {
       double profit_pips = (pos_type == POSITION_TYPE_BUY)
                          ? (current_price - entry_price) / pipSize
                          : (entry_price - current_price) / pipSize;
       if(profit_pips <= 0.0) return 0.0;

       double peak_profit_pips = UpdatePositionPeakProfit(ticket, profit_pips);
       double trail_percent = m_settings.TrailProfitPercentLPR / 100.0;
       if(trail_percent < 0.0) trail_percent = 0.0;
       if(trail_percent > 1.0) trail_percent = 1.0;

       double trail_profit_pips = peak_profit_pips * (1.0 - trail_percent);
       double new_sl = (pos_type == POSITION_TYPE_BUY)
                     ? entry_price + (trail_profit_pips * pipSize)
                     : entry_price - (trail_profit_pips * pipSize);

       // ── BE-FLOOR (Q8 2026-06) ───────────────────────────────────────
       // Previously this gate clamped new_sl to entry+RRM_BE_BufferPips when
       // the LPR-computed SL was below the buffer. On Silver/Gold where the
       // BE buffer scales with the instrument-fan multiplier (Silver≈75p × pipSize,
       // Gold≈150p × pipSize on M1), this clamp effectively turned the LPR trail
       // into a stale BE-lock through small peak retracements — the same bug
       // shape Patch B fixed in TRAIL_EMA.
       //
       // The buffer's actual purpose is the one-time BE-LOCK event in the BE
       // block of RRM_ManageStrictNoATR (lines 1463-1488). It should NOT also
       // be a continuous floor inside the LPR trail computation. Replaced with
       // a simple BE floor: if the LPR-computed SL would lock loss territory,
       // skip the move (return 0.0 = "no update"). The TrailLockProfit gate
       // below prevents backwards movement; the BE block elsewhere handles the
       // one-time lock.
       if(pos_type == POSITION_TYPE_BUY && new_sl < entry_price) {
          if(m_settings.DebugFlow)
             PrintFormat("[LPR] #%I64u BLOCKED (BE-floor): new_sl=%.5f < entry=%.5f "
                         "(Peak=%.1fp, Trail=%.1f%%, retracement still below entry).",
                         ticket, new_sl, entry_price,
                         peak_profit_pips, m_settings.TrailProfitPercentLPR);
          return 0.0;
       }
       if(pos_type == POSITION_TYPE_SELL && new_sl > entry_price) {
          if(m_settings.DebugFlow)
             PrintFormat("[LPR] #%I64u BLOCKED (BE-floor): new_sl=%.5f > entry=%.5f "
                         "(Peak=%.1fp, Trail=%.1f%%, retracement still above entry).",
                         ticket, new_sl, entry_price,
                         peak_profit_pips, m_settings.TrailProfitPercentLPR);
          return 0.0;
       }

       if(m_settings.TrailLockProfit && current_sl != 0.0) {
          if(pos_type == POSITION_TYPE_BUY && new_sl <= current_sl) return 0.0;
          if(pos_type == POSITION_TYPE_SELL && new_sl >= current_sl) return 0.0;
       }

       if(pos_type == POSITION_TYPE_BUY && new_sl >= current_price) return 0.0;
       if(pos_type == POSITION_TYPE_SELL && new_sl <= current_price) return 0.0;

       if(m_settings.DebugFlow) {
          PrintFormat("[LPR] #%I64u Peak=%.1f pips Trail=%.1f%% -> SL=%.5f",
                      ticket, peak_profit_pips, m_settings.TrailProfitPercentLPR, new_sl);
       }
       return NormalizeDouble(new_sl, digits);
    }

   //+------------------------------------------------------------------+
   //| ApplyTrailEMA — TRAIL_EMA logic, callable from any exit profile  |
   //+------------------------------------------------------------------+
   // Q3 (2026-06): extracted from RRM_ManageStrictNoATR so the same TRAIL_EMA
   // evaluation runs whether ExitProfile is RRM or SIMPLE. Before Q3, the
   // EXIT_PROFILE_SIMPLE path (EvaluateTM's fallthrough branch) had no TRAIL_EMA
   // case at all — users who set TrailMode=TRAIL_EMA on a non-RRM preset got
   // silent no-op. SimpleEA philosophy: the TRAIL_EMA equation evaluates to the
   // same result regardless of which exit-profile equation called it.
   //
   // Caller responsibilities (NOT handled here):
   //   - Trail-mode dispatch (caller has already decided TrailMode == TRAIL_EMA)
   //   - Path-specific upstream gates: BE-reached (RRM only via m_rrm_be_reached),
   //     Safety_DelayTrailUntilR (Q6 — applied on both paths by their callers),
   //     CheckTrailTrigger (EXIT_PROFILE_SIMPLE only)
   //
   // Helper responsibilities (handled here):
   //   - Per-bar gate (m_trail_ema_last_bar — single source of truth)
   //   - EMA period resolution (from TrailEMA_Period or ribbon-role fallback)
   //   - EMA value read at TrailEMA_Shift (clamped 1..5)
   //   - Cushion resolution: ATR-mode > fixed-pips > PSAR-fallback
   //   - SL proposal: EMA ± cushion
   //   - BE-floor gate (Patch B): never lock SL into loss territory
   //   - Lock-profit gate: never move SL backwards (TrailLockProfit)
   //   - TP-past-close: if proposed SL would cross TP, close at market instead
   //   - Valid-check: SL geometry vs cur_sl and cur_price
   //   - PositionModify (direct — does NOT fall through to the caller's tail)
   //
   // path_tag (e.g. "RRM" or "SIMPLE") appears only in diagnostic strings so
   // the journal shows which exit-profile path invoked the helper.
   void ApplyTrailEMA(ulong ticket, bool isBuy, double entry, double cur_price,
                      double cur_sl, double cur_tp, int digits, double pipSize,
                      const string path_tag)
   {
      datetime bar1_time = iTime(m_symbol, PERIOD_CURRENT, 1);
      if(bar1_time == m_trail_ema_last_bar) return;
      m_trail_ema_last_bar = bar1_time;

      // Period: preset resolver should have set this; fallback chain just in case
      int ema_period = m_settings.TrailEMA_Period;
      if(ema_period <= 0) {
         // Resolve from ribbon role at runtime (preset may not have had periods yet)
         switch(m_settings.TrailEMA_RibbonRole) {
            case 1:  ema_period = m_settings.P_Ema2; break;  // ROLE_EMA2 = 13
            case 2:  ema_period = m_settings.P_Ema3; break;  // ROLE_EMA3 = 34
            case 3:  ema_period = m_settings.P_Ema4; break;  // ROLE_EMA4 = 89
            default: ema_period = m_settings.P_Ema1; break;  // ROLE_EMA1 = 5
         }
      }
      if(ema_period <= 0) ema_period = 13; // absolute fallback: EMA13

      int h_ema = iMA(m_symbol, PERIOD_CURRENT, ema_period, 0, MODE_EMA, PRICE_CLOSE);
      if(h_ema == INVALID_HANDLE) return;

      // shift: how many bars back to read EMA. 1=last closed bar (default, tight).
      // Higher values (2-5) give progressively more room — EMA was lower N bars ago.
      int ema_shift = m_settings.TrailEMA_Shift;
      if(ema_shift < 1) ema_shift = 1;
      if(ema_shift > 5) ema_shift = 5;

      double ema_val[];
      ArraySetAsSeries(ema_val, true);
      if(CopyBuffer(h_ema, 0, ema_shift, 1, ema_val) != 1) { IndicatorRelease(h_ema); return; }
      IndicatorRelease(h_ema);

      // EMA cushion priority: ATR-based > fixed pips > PSAR fallback.
      // ATR mode auto-scales with instrument volatility — recommended for Gold/Silver.
      // Example H1 Gold: ATR≈17, mult=0.10 → cushion ≈ 1.7 pts ($1.70) — tight but noise-proof.
      double ema_cushion_pips = 0.0;
      if(m_settings.TrailEMA_CushionAtrMult > 0.0) {
         // ATR mode: cushion = ATR(period) × multiplier, converted to pips.
         // Uses cached m_h_trail_ema_atr handle (initialized in Init/UpdateSettings).
         if(m_h_trail_ema_atr != INVALID_HANDLE) {
            double atr_val[];
            ArraySetAsSeries(atr_val, true);
            if(CopyBuffer(m_h_trail_ema_atr, 0, 1, 1, atr_val) == 1 && atr_val[0] > 0.0)
               ema_cushion_pips = (atr_val[0] / pipSize) * m_settings.TrailEMA_CushionAtrMult;
         }
      }
      if(ema_cushion_pips <= 0.0 && m_settings.TrailEMA_CushionPips > 0.0)
         ema_cushion_pips = m_settings.TrailEMA_CushionPips;  // fixed pip fallback
      if(ema_cushion_pips <= 0.0)
         ema_cushion_pips = m_settings.PSAR_TrailPipsCushion; // last resort
      double cushion = ema_cushion_pips * pipSize;
      double new_sl  = isBuy
         ? NormalizeDouble(ema_val[0] - cushion, digits)
         : NormalizeDouble(ema_val[0] + cushion, digits);

      // ── BE-FLOOR (Patch B 2026-06) ──────────────────────────────
      // Refuse to lock SL into loss territory. The BE buffer is only for the
      // one-time BE-LOCK event in the BE block (RRM path); it must NOT also
      // be a continuous threshold against trail engagement (would make trail
      // dormant on Silver/Gold at multi-R of profit).
      if(isBuy  && new_sl < entry) {
         if(m_settings.DebugFlow)
            PrintFormat("[TRAIL_EMA/%s] #%I64u BLOCKED (BE-floor): new_sl=%.5f < entry=%.5f "
                        "(EMA still below entry — no profit to lock).",
                        path_tag, ticket, new_sl, entry);
         return;
      }
      if(!isBuy && new_sl > entry) {
         if(m_settings.DebugFlow)
            PrintFormat("[TRAIL_EMA/%s] #%I64u BLOCKED (BE-floor): new_sl=%.5f > entry=%.5f "
                        "(EMA still above entry — no profit to lock).",
                        path_tag, ticket, new_sl, entry);
         return;
      }

      if(m_settings.TrailLockProfit && cur_sl != 0.0) {
         if(isBuy  && new_sl <= cur_sl) {
            if(m_settings.DebugFlow)
               PrintFormat("[TRAIL_EMA/%s] #%I64u BLOCKED (lock-profit): new_sl=%.5f <= cur_sl=%.5f "
                           "(would move SL backwards). EMA=%.5f cushion=%.1fp.",
                           path_tag, ticket, new_sl, cur_sl, ema_val[0], ema_cushion_pips);
            return;
         }
         if(!isBuy && new_sl >= cur_sl) {
            if(m_settings.DebugFlow)
               PrintFormat("[TRAIL_EMA/%s] #%I64u BLOCKED (lock-profit): new_sl=%.5f >= cur_sl=%.5f "
                           "(would move SL backwards). EMA=%.5f cushion=%.1fp.",
                           path_tag, ticket, new_sl, cur_sl, ema_val[0], ema_cushion_pips);
            return;
         }
      }

      // TP guard: SL must not cross or touch TP — MT5 rejects with "invalid stops".
      // When EMA trail pushes SL past the TP level the trade has already run its
      // full target; close it immediately rather than silently doing nothing.
      if(cur_tp > 0.0) {
         bool sl_past_tp = isBuy ? (new_sl >= cur_tp) : (new_sl <= cur_tp);
         if(sl_past_tp) {
            if(m_settings.DebugFlow)
               PrintFormat("[TRAIL_EMA/%s] #%I64u: SL %.5f past TP %.5f — closing at market",
                           path_tag, ticket, new_sl, cur_tp);
            if(IsModifyAllowed()) m_trade.PositionClose(ticket);
            return;
         }
      }

      bool valid = isBuy
         ? (new_sl > cur_sl && new_sl < cur_price)
         : ((cur_sl == 0.0 || new_sl < cur_sl) && new_sl > cur_price);

      if(valid && IsModifyAllowed()) {
         if(m_settings.DebugFlow)
            PrintFormat("[TRAIL_EMA/%s] #%I64u: SL %.5f -> %.5f | EMA(%d,sh=%d)=%.5f cushion=%.1fp",
                        path_tag, ticket, cur_sl, new_sl, ema_period, ema_shift, ema_val[0],
                        ema_cushion_pips);
         m_trade.PositionModify(ticket, new_sl, cur_tp);
      }
      else if(!valid && m_settings.DebugFlow) {
         // Final block-condition: SL improvement fell on the wrong side of
         // cur_sl or cur_price (e.g. price reversed before this bar closed,
         // or rounding put new_sl == cur_sl). Surface it explicitly so the
         // user can see the geometry.
         PrintFormat("[TRAIL_EMA/%s] #%I64u BLOCKED (valid-check): new_sl=%.5f cur_sl=%.5f "
                     "cur_price=%.5f isBuy=%d. Required: %s.",
                     path_tag, ticket, new_sl, cur_sl, cur_price, (int)isBuy,
                     isBuy ? "new_sl > cur_sl AND new_sl < cur_price"
                           : "new_sl < cur_sl (or cur_sl==0) AND new_sl > cur_price");
      }
   }

   void ReleaseHandles() {
      if(m_h_psar != INVALID_HANDLE) { IndicatorRelease(m_h_psar); m_h_psar = INVALID_HANDLE; }
      if(m_h_fractals != INVALID_HANDLE) { IndicatorRelease(m_h_fractals); m_h_fractals = INVALID_HANDLE; }
      if(m_h_cushion_atr != INVALID_HANDLE) { IndicatorRelease(m_h_cushion_atr); m_h_cushion_atr = INVALID_HANDLE; }
      if(m_h_sl_atr != INVALID_HANDLE) { IndicatorRelease(m_h_sl_atr); m_h_sl_atr = INVALID_HANDLE; }
      if(m_h_trail_ema_atr != INVALID_HANDLE) { IndicatorRelease(m_h_trail_ema_atr); m_h_trail_ema_atr = INVALID_HANDLE; }
   }

   void GetSymbolCurrencies(string sym, string &base, string &quote) {
      base = StringSubstr(sym, 0, 3);
      quote = StringSubstr(sym, 3, 3);
   }

   bool NewsImpactPass(string impact) {
      StringToLower(impact);
      return (StringFind(impact, "high") >= 0 || StringFind(impact, "med") >= 0);
   }

   ulong GetMyPosition() {
      for(int i = PositionsTotal() - 1; i >= 0; i--) {
         ulong ticket = PositionGetTicket(i);
         if(PositionGetString(POSITION_SYMBOL) == m_symbol && 
            PositionGetInteger(POSITION_MAGIC) == m_magic) {
            return ticket;
         }
      }
      return 0;
   }

   ulong FindWorstPosition() {
      ulong worst_ticket = 0;
      double worst_profit = DBL_MAX;
      for(int i = PositionsTotal() - 1; i >= 0; i--) {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
         if(PositionGetString(POSITION_SYMBOL) != m_symbol) continue;
         if((ulong)PositionGetInteger(POSITION_MAGIC) != m_magic) continue;
         double profit = PositionGetDouble(POSITION_PROFIT);
         if(worst_ticket == 0 || profit < worst_profit) {
            worst_ticket = ticket;
            worst_profit = profit;
         }
      }
      return worst_ticket;
   }

   void CountMyPositions(int &buy_count, int &sell_count) {
      buy_count = 0; sell_count = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--) {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(PositionGetString(POSITION_SYMBOL) != m_symbol) continue;
         if((ulong)PositionGetInteger(POSITION_MAGIC) != m_magic) continue;
         long type = PositionGetInteger(POSITION_TYPE);
         if(type == POSITION_TYPE_BUY)  buy_count++;
         if(type == POSITION_TYPE_SELL) sell_count++;
      }
   }

   void CloseAllMyPositions() {
      for(int i = PositionsTotal() - 1; i >= 0; i--) {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(PositionGetString(POSITION_SYMBOL) != m_symbol) continue;
         if((ulong)PositionGetInteger(POSITION_MAGIC) != m_magic) continue;
         m_trade.PositionClose(ticket);
      }
   }

   int GetMarkerBarsToScan() const
   {
      int total_bars = Bars(m_symbol, PERIOD_CURRENT);
      if(total_bars <= 1) return 0;
      if(m_settings.MarkerLookback <= 0) return total_bars - 1;
      return MathMin(m_settings.MarkerLookback, total_bars - 1);
   }

   void DrawMarker(const string prefix,
                   datetime time,
                   double price,
                   bool isHigh,
                   int bar,
                   color high_color,
                   color low_color,
                   int width,
                   int high_arrow_code,
                   int low_arrow_code)
   {
       string side = isHigh ? "HIGH" : "LOW";
       string name = StringFormat("%s_%s_%d_%I64d", prefix, side, bar, (long)time);
       if(ObjectFind(0, name) >= 0) return;
   
       if(!ObjectCreate(0, name, OBJ_ARROW, 0, time, price)) return;
   
       color marker_color = isHigh ? high_color : low_color;
       ObjectSetInteger(0, name, OBJPROP_ARROWCODE, isHigh ? high_arrow_code : low_arrow_code);
       ObjectSetInteger(0, name, OBJPROP_COLOR, marker_color);
       ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
       ObjectSetInteger(0, name, OBJPROP_BACK, StringFind(prefix, "Swing") == 0);
       ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
       ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   
       string marker_type = (StringFind(prefix, "Swing") == 0) ? "Swing" : "Fractal";
       ObjectSetString(0, name, OBJPROP_TOOLTIP,
                       StringFormat("%s %s: %.5f", marker_type, isHigh ? "High" : "Low", price));
   
       if(!m_settings.ShowMarkerLabels) return;
   
       string label_prefix = (StringFind(prefix, "Swing") == 0) ? "SwingLabel" : "FractalLabel";
       string label_name = StringFormat("%s_%s_%d_%I64d", label_prefix, side, bar, (long)time);
       if(!ObjectCreate(0, label_name, OBJ_TEXT, 0, time, price)) return;
   
       ObjectSetString(0, label_name, OBJPROP_TEXT,
                       StringFormat("%s%.5f", (StringFind(prefix, "Swing") == 0) ? "S:" : "F:", price));
       ObjectSetInteger(0, label_name, OBJPROP_COLOR, marker_color);
       ObjectSetInteger(0, label_name, OBJPROP_FONTSIZE, (StringFind(prefix, "Swing") == 0) ? 7 : 8);
       ObjectSetInteger(0, label_name, OBJPROP_ANCHOR, isHigh ? ANCHOR_BOTTOM : ANCHOR_TOP);
       ObjectSetInteger(0, label_name, OBJPROP_SELECTABLE, false);
       ObjectSetInteger(0, label_name, OBJPROP_HIDDEN, true);
   }

   void DrawSwingMarkers()
   {
      int bars_to_scan = GetMarkerBarsToScan();
      int swing_lookback = (m_settings.SwingLookback > 0) ? m_settings.SwingLookback : 20;
      int total_bars = Bars(m_symbol, PERIOD_CURRENT);
      int last_bar = MathMin(bars_to_scan, total_bars - swing_lookback);
      if(last_bar < swing_lookback) return;

      for(int i = swing_lookback; i <= last_bar; i++)
      {
         int high_idx = iHighest(m_symbol, PERIOD_CURRENT, MODE_HIGH, swing_lookback, i);
         if(high_idx == i)
         {
            DrawMarker("SwingSL",
                       iTime(m_symbol, PERIOD_CURRENT, i),
                       iHigh(m_symbol, PERIOD_CURRENT, i),
                       true,
                       i,
                       m_settings.SwingHighColor,
                       m_settings.SwingLowColor,
                       m_settings.SwingMarkerSize,
                       217,
                       218);
         }

         int low_idx = iLowest(m_symbol, PERIOD_CURRENT, MODE_LOW, swing_lookback, i);
         if(low_idx == i)
         {
            DrawMarker("SwingSL",
                       iTime(m_symbol, PERIOD_CURRENT, i),
                       iLow(m_symbol, PERIOD_CURRENT, i),
                       false,
                       i,
                       m_settings.SwingHighColor,
                       m_settings.SwingLowColor,
                       m_settings.SwingMarkerSize,
                       217,
                       218);
         }
      }
   }

   void DrawFractalMarkers()
   {
      if(m_h_fractals == INVALID_HANDLE) return;

       // ── TEST: Count how many fractals exist in buffers ──
       //int high_count = 0, low_count = 0;
       //double test_upper[100], test_lower[100];
       
       //CopyBuffer(m_h_fractals, 0, 0, 100, test_upper);  // Last 100 bars, buffer 0 (highs)
       //CopyBuffer(m_h_fractals, 1, 0, 100, test_lower);  // Last 100 bars, buffer 1 (lows)
       
       //for(int x = 0; x < 100; x++) {
       //    if(test_upper[x] != EMPTY_VALUE && test_upper[x] > 0) high_count++;
       //    if(test_lower[x] != EMPTY_VALUE && test_lower[x] > 0) low_count++;
       //}
       
       //PrintFormat("📊 FRACTAL SCAN: Last 100 bars → Highs=%d | Lows=%d", high_count, low_count);
       // ── END TEST ──

      int bars_to_scan = GetMarkerBarsToScan();
      int start_bar = (m_settings.FractalPeriod > 0) ? m_settings.FractalPeriod : 5;
      if(bars_to_scan < start_bar) return;

      double upper[1], lower[1];

      for(int i = start_bar; i <= bars_to_scan; i++)
      {
         // ✅ Check if fractal indicator detected a HIGH at bar i
         if(CopyBuffer(m_h_fractals, 0, i, 1, upper) > 0 &&
           upper[0] != EMPTY_VALUE && upper[0] != DBL_MAX && upper[0] > 0.0)
         {
            // Fractal exists at bar i, draw marker at THIS BAR'S high
            DrawMarker("FractalSL",
                       iTime(m_symbol, PERIOD_CURRENT, i),
                       iHigh(m_symbol, PERIOD_CURRENT, i),  // ✅ Draw at candle high
                       true,
                       i,
                       m_settings.FractalHighColor,
                       m_settings.FractalLowColor,
                       m_settings.FractalMarkerSize,
                       217,
                       218);
         }
      
         // ✅ Check if fractal indicator detected a LOW at bar i
         if(CopyBuffer(m_h_fractals, 1, i, 1, lower) > 0 &&
           lower[0] != EMPTY_VALUE && lower[0] != DBL_MAX && lower[0] > 0.0)
         {
            // Fractal exists at bar i, draw marker at THIS BAR'S low
            DrawMarker("FractalSL",
                       iTime(m_symbol, PERIOD_CURRENT, i),
                       iLow(m_symbol, PERIOD_CURRENT, i),   // ✅ Draw at candle low
                       false,
                       i,
                       m_settings.FractalHighColor,
                       m_settings.FractalLowColor,
                       m_settings.FractalMarkerSize,
                       217,
                       218);
         }
      }
   }

    //+------------------------------------------------------------------+
    //| REFACTORED PRICE MATH & BULLETPROOF INDICATOR HELPERS            |
    //+------------------------------------------------------------------+
   
   double GetPipSize() const {
      return GlobalPipSize(m_symbol);
   }

   // ─────────────────────────────────────────────────────────────────────────
   // RiskMoneyPerLot — loss, in ACCOUNT (deposit) currency, of holding ONE lot
   // from entry to a stop `stop_dist` price units away. This is the single
   // source of truth for risk sizing and replaces all direct use of
   // SYMBOL_TRADE_TICK_VALUE, which the MT5 tester reports incorrectly under
   // "profit in pips for faster calculations" and on non-USD deposit accounts
   // (observed: XAUUSD tick_value 0.10 vs true ~1.00 → 10× oversize → intended
   // 2% stop-outs realised as ~18% losses → ~half the account erased over a few
   // consecutive stops).
   //
   // We use OrderCalcProfit(), the terminal's OWN profit engine. It returns P/L
   // in account currency with all FX conversion handled internally, correctly,
   // for majors, JPY pairs (different tick scale) and metals alike — and it is
   // immune to the pip-mode tick_value artifact. We compute the loss of a SELL
   // exit `stop_dist` above entry for a long (and symmetric for short); sign is
   // discarded — we only need the magnitude.
   //
   // Falls back to the contract-economics estimate only if OrderCalcProfit is
   // unavailable for some reason. Returns 0.0 if nothing usable can be derived
   // (callers already guard for that).
   // ─────────────────────────────────────────────────────────────────────────
   double RiskMoneyPerLot(double stop_dist) const {
      if(stop_dist <= 0.0) return 0.0;

      double ref_price = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      if(ref_price <= 0.0) ref_price = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
      if(ref_price <= 0.0) return 0.0;

      // Engine-authoritative: P/L of 1 lot, opened at ref_price, closed
      // stop_dist away in the losing direction. Use a BUY closed below entry.
      double pl = 0.0;
      if(OrderCalcProfit(ORDER_TYPE_BUY, m_symbol, 1.0, ref_price, ref_price - stop_dist, pl))
      {
         double loss = MathAbs(pl);
         if(loss > 0.0) return loss;
      }

      // Fallback (should be rare): contract economics in profit ccy, FX-converted
      // via the engine on a 1.0 price move so we still avoid the bad tick_value.
      double one_move_pl = 0.0;
      double contract = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_CONTRACT_SIZE);
      if(contract > 0.0 &&
         OrderCalcProfit(ORDER_TYPE_BUY, m_symbol, 1.0, ref_price, ref_price - 1.0, one_move_pl))
      {
         double per_price_unit = MathAbs(one_move_pl);   // account ccy per 1.0 price move per lot
         if(per_price_unit > 0.0) return per_price_unit * stop_dist;
      }
      return 0.0;
   }

   // ─────────────────────────────────────────────────────────────────────────
   // ResolveTickValue — per-tick loss in ACCOUNT currency, derived from
   // RiskMoneyPerLot (engine-authoritative) rather than the broker's
   // SYMBOL_TRADE_TICK_VALUE field, which is wrong in pip-mode / non-USD testing.
   // Retained for the risk-percent / MaxTotalRisk callers that still express
   // things per-tick: tick_value = RiskMoneyPerLot(tick_size).
   // Returns 0.0 if it cannot be established (callers guard for that).
   // ─────────────────────────────────────────────────────────────────────────
   double ResolveTickValue() const {
      double tick_size = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
      if(tick_size <= 0.0) return 0.0;
      double tv = RiskMoneyPerLot(tick_size);
      if(tv > 0.0) return tv;
      // last-resort: broker field (only reached if OrderCalcProfit failed entirely)
      double btv = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
      if(btv <= 0.0) btv = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE);
      return btv;
   }

   // ─────────────────────────────────────────────────────────────────────────
   // IsModifyAllowed — guard for SL/TP modifications (bugfix)
   //
   // The trailing-stop and break-even paths previously called PositionModify()
   // unconditionally on every management tick. When a tick was processed while
   // the symbol's trading session was closed (e.g. the 23:00 hour and weekend
   // gaps seen in the tester), the server rejected the modify with
   // "[Market closed]" / "failed modify". These rejections are harmless to the
   // account but flood the journal with errors and waste a modify attempt.
   //
   // This helper returns false when a modify would certainly be rejected:
   //   • the symbol is not in a full-trading mode, or
   //   • the current server time is outside the symbol's trade session.
   // Modify paths short-circuit on false, so management simply resumes on the
   // next tick once the session reopens. No strategy behavior changes — only
   // doomed modify attempts are skipped.
   // ─────────────────────────────────────────────────────────────────────────
   bool IsModifyAllowed() const {
      // 1) Symbol must permit full trading (not CLOSEONLY / DISABLED / LONGONLY-only, etc.)
      long trade_mode = SymbolInfoInteger(m_symbol, SYMBOL_TRADE_MODE);
      if(trade_mode == SYMBOL_TRADE_MODE_DISABLED || trade_mode == SYMBOL_TRADE_MODE_CLOSEONLY)
         return false;

      // 2) Current server time must fall inside an active trade session for today.
      datetime now = TimeCurrent();
      MqlDateTime mdt;
      TimeToStruct(now, mdt);
      ENUM_DAY_OF_WEEK dow = (ENUM_DAY_OF_WEEK)mdt.day_of_week;

      // Seconds-since-midnight for the current server time.
      int now_sec = mdt.hour * 3600 + mdt.min * 60 + mdt.sec;

      datetime from = 0, to = 0;
      bool any_session = false;
      for(int s = 0; SymbolInfoSessionTrade(m_symbol, dow, s, from, to); s++) {
         any_session = true;
         // Session boundaries are returned as seconds-since-midnight (date part is 1970-01-01).
         int from_sec = (int)from;
         int to_sec   = (int)to;
         if(now_sec >= from_sec && now_sec < to_sec)
            return true;   // inside an open trade session
      }

      // If the broker exposes no session table for this symbol we cannot prove
      // the market is closed — fall back to allowing the modify (preserves prior
      // behavior on brokers without session metadata).
      if(!any_session)
         return true;

      return false;   // sessions exist but 'now' is outside all of them → closed
   }

   // Returns ATR value for SL_MODE_ATR initial SL. Uses shift=1 (closed bar) for consistency with other anchors.
   double GetSLAtr() {
      if(m_h_sl_atr == INVALID_HANDLE) {
         PrintFormat("⚠️ [SL_ATR] Handle invalid — ATR SL cannot be computed");
         return 0.0;
      }
      double a[1];
      if(CopyBuffer(m_h_sl_atr, 0, 1, 1, a) == 1 && a[0] > 0.0)
         return a[0];
      PrintFormat("⚠️ [SL_ATR] CopyBuffer returned no data — ATR SL cannot be computed");
      return 0.0;
   }

   double GetPSARAnchor(int shift=1) {
      if(m_h_psar == INVALID_HANDLE) {
         Print("⚠️ [DEBUG SL] PSAR Handle is INVALID! Cannot fetch anchor.");
         return 0.0;
      }
      double r[1];
      ResetLastError();
      int copied = CopyBuffer(m_h_psar, 0, shift, 1, r);
      if(copied <= 0) {
         PrintFormat("⚠️ [DEBUG SL] PSAR CopyBuffer failed at shift %d! Error: %d", shift, GetLastError());
         return 0.0;
      }
      if(r[0] == DBL_MAX || r[0] <= 0.0) {
         PrintFormat("⚠️ [DEBUG SL] PSAR Value is empty (%.5f) at shift %d", r[0], shift);
         return 0.0;
      }
      return r[0];
   }

   double GetSwingLevel(int direction) {
      int lb = (m_settings.SwingLookback > 0) ? m_settings.SwingLookback : 20;
      int swing_strength = 2;  // A swing is a bar with N lower lows (or higher highs) on each side
      ResetLastError();
      
      // Scan from most recent to oldest, return the FIRST (nearest) valid swing
      for(int i = swing_strength + 1; i < lb; i++)
      {
         if(direction > 0)
         {
            // BUY: find swing LOW (bar with lower lows on both sides)
            double low_i = iLow(m_symbol, PERIOD_CURRENT, i);
            if(low_i <= 0.0) continue;
            
            bool is_swing = true;
            for(int j = 1; j <= swing_strength; j++)
            {
               if(iLow(m_symbol, PERIOD_CURRENT, i - j) <= low_i ||
                  iLow(m_symbol, PERIOD_CURRENT, i + j) <= low_i)
               {
                  is_swing = false;
                  break;
               }
            }
            if(is_swing) return low_i;
         }
         else
         {
            // SELL: find swing HIGH (bar with higher highs on both sides)
            double high_i = iHigh(m_symbol, PERIOD_CURRENT, i);
            if(high_i <= 0.0) continue;
            
            bool is_swing = true;
            for(int j = 1; j <= swing_strength; j++)
            {
               if(iHigh(m_symbol, PERIOD_CURRENT, i - j) >= high_i ||
                  iHigh(m_symbol, PERIOD_CURRENT, i + j) >= high_i)
               {
                  is_swing = false;
                  break;
               }
            }
            if(is_swing) return high_i;
         }
      }
      
      // Fallback: no swing found within lookback — use iLowest/iHighest as last resort
      if(direction > 0) {
         int idx = iLowest(m_symbol, PERIOD_CURRENT, MODE_LOW, lb, 1);
         if(idx >= 0) return iLow(m_symbol, PERIOD_CURRENT, idx);
      } else {
         int idx = iHighest(m_symbol, PERIOD_CURRENT, MODE_HIGH, lb, 1);
         if(idx >= 0) return iHigh(m_symbol, PERIOD_CURRENT, idx);
      }
      
      PrintFormat("⚠️ [DEBUG SL] No swing found within %d bars", lb);
      return 0.0;
   }

   double GetFractalLevel(int direction) {
      int period  = (m_settings.FractalPeriod > 0) ? m_settings.FractalPeriod : 5;
      // Use SwingLookback as the search window so fractal has same reach as swing SL.
      // Previous lookback = period*3 (15 bars) was too narrow on H1/H4 — fractals need
      // 2×period bars to form, and trending moves can push them beyond 15 bars back.
      int lookback = MathMax(period * 3, m_settings.SwingLookback);
      int mode = (direction > 0) ? 1 : 0;
      double r[1];

      if(m_h_fractals == INVALID_HANDLE) return 0.0;

      for(int i = period; i < lookback; i++) {
         if(CopyBuffer(m_h_fractals, mode, i, 1, r) > 0 && r[0] != DBL_MAX && r[0] > 0.0) {
            return r[0];
         }
      }
      Print("⚠️ [DEBUG SL] No valid fractal found within lookback window.");
      return 0.0;
   }

   double GetFractalTP(int direction) {
      int period = (m_settings.FractalPeriod > 0) ? m_settings.FractalPeriod : 5;
      int lookback = period * 5;
      int offset = (m_settings.TPFractalOffset > 0) ? m_settings.TPFractalOffset : 1;
      double fractal_level = 0.0;
      int found_count = 0;
      int mode = (direction > 0) ? 0 : 1; 
      double r[1];
      
      if(m_h_fractals == INVALID_HANDLE) return 0.0;
      
      for(int i = period; i < lookback; i++) {
         if(CopyBuffer(m_h_fractals, mode, i, 1, r) > 0 && r[0] != DBL_MAX && r[0] > 0.0) {
            found_count++;
            if(found_count >= offset) {
               fractal_level = r[0];
               break;
            }
         }
      }
      if(fractal_level <= 0.0) return 0.0;

      double current_price = (direction > 0) ? SymbolInfoDouble(m_symbol, SYMBOL_ASK) : SymbolInfoDouble(m_symbol, SYMBOL_BID);
      bool valid_side = (direction > 0 && fractal_level > current_price) || (direction < 0 && fractal_level < current_price);
      if(!valid_side) return 0.0;

      return MathAbs(fractal_level - current_price) / GetPipSize();
   }

   bool CheckPSARFlip(int direction, double current_price) {
      // FIX Bug2: use shift=1 (last confirmed closed bar) instead of shift=0 (still-forming bar)
      double psar = GetPSARAnchor(1);
      if(psar <= 0.0) return false;
      return (direction > 0 && psar > current_price) || (direction < 0 && psar < current_price);
   }

   //+------------------------------------------------------------------+
   //| CheckDPIHistogramExit — Exit when GREEN histogram vanishes       |
   //| Returns: true if position should be closed                       |
   //|                                                                   |
   //| DPI GREEN = Blue (lead) and hist (contour) on same side of zero. |
   //| GREEN appears BOTH above zero (bullish momentum) and below zero  |
   //| (bearish momentum). Its presence confirms momentum alignment in  |
   //| the given direction — it accompanies the red/yellow ribbon.      |
   //|                                                                   |
   //| When GREEN declines and disappears → OB/OS condition reached.    |
   //| This typically precedes pullbacks that erode open profits.       |
   //| Closing on GREEN disappearance locks in gains before retracement.|
   //|                                                                   |
   //| Direction-neutral: works for both BUY and SELL because GREEN     |
   //| exists on both sides of zero.                                    |
   //|                                                                   |
   //| BUG FIX (2026-05-21): Was checking CCI sign via m_dpi_hist_trend |
   //| (trend != 1 means "CCI not positive"), which killed all SHORTs   |
   //| on bar 1 because bearish CCI (-1 != 1) was always true.          |
   //| Now tracks actual GREEN presence from ComputeDPIMainHist().      |
   //+------------------------------------------------------------------+
   bool CheckDPIHistogramExit(ulong ticket)
   {
      if(!m_settings.DPI_ExitOnHistDisappear) return false;
      if(!m_settings.DPI_HistTrackingEnabled) return false;

      // GREEN vanished = OB/OS reached, pullback likely (direction-neutral)
      bool green_gone = !m_dpi_hist_green_present;
      bool below_threshold = false;

      if(m_settings.DPI_ExitThreshold > 0.0)
         below_threshold = (MathAbs(m_dpi_hist_current) < m_settings.DPI_ExitThreshold);

      if(green_gone || below_threshold)
      {
         if(m_settings.DebugFlow)
         {
            ENUM_POSITION_TYPE pos_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            string reason = green_gone
               ? "GREEN vanished (OB/OS — pullback likely)"
               : StringFormat("CCI below threshold (%.2f < %.2f)", MathAbs(m_dpi_hist_current), m_settings.DPI_ExitThreshold);
            PrintFormat("[DPI_EXIT] Ticket #%I64u | Dir=%s | Reason: %s | CCI=%.2f | CCI_Trend=%s | GREEN=%s",
                        ticket,
                        (pos_type == POSITION_TYPE_BUY) ? "BUY" : "SELL",
                        reason,
                        m_dpi_hist_current,
                        (m_dpi_hist_trend == 1 ? "POS" : m_dpi_hist_trend == -1 ? "NEG" : "FLAT"),
                        m_dpi_hist_green_present ? "YES" : "NO");
         }
         return true;
      }

      return false;
   }

   bool CheckTrailTrigger(int direction, double profit_pips, double entry_price, double current_price) {
      switch(m_settings.TrailTrigger) {
         case TRIGGER_IMMEDIATE: 
            return true;
         case TRIGGER_BREAKEVEN: 
            return (profit_pips >= m_settings.BEThresholdPips);
         case TRIGGER_PROFIT_PIPS: 
            return (profit_pips >= m_settings.TrailDistancePips);
         case TRIGGER_PROFIT_PERCENT: {
            double initial_sl = m_initial_sl_price;
            if(initial_sl <= 0.0) initial_sl = PositionGetDouble(POSITION_SL);
            double risk_pips = MathAbs(entry_price - initial_sl) / GetPipSize();
            if(risk_pips <= 0.0) return false;
            double trigger_pips = risk_pips * (m_settings.TrailProfitPercent / 100.0);
            return (profit_pips >= trigger_pips);
         }
         case TRIGGER_PSAR_ALIGN: {
            // FIX Bug2: use shift=1 (last confirmed closed bar) instead of shift=0 (still-forming bar)
            double psar = GetPSARAnchor(1);
            if(psar <= 0.0) return false;
            return (direction > 0 && psar < current_price) || (direction < 0 && psar > current_price);
         }
      }
      return true;
   }

   double NormalizeVolume(double vol) {
      double vmin=0.0, vmax=0.0, vstep=0.0;
      if(!SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN, vmin))  vmin = 0.01;
      if(!SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MAX, vmax))  vmax = 100.0;
      if(!SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP, vstep)) vstep = vmin;
      if(vstep <= 0.0) vstep = vmin;

      vol = MathMax(vmin, MathMin(vmax, vol));
      double steps = MathFloor(vol / vstep);
      double aligned = steps * vstep;

      int digits = 2;
      if(vstep > 0.0) {
         digits = (int)MathCeil(-MathLog10(vstep));
         if(digits < 0) digits = 0;
         if(digits > 8) digits = 8;
      }
      aligned = NormalizeDouble(aligned, digits);
      if(aligned < vmin) aligned = vmin;
      if(aligned > vmax) aligned = vmax;
      return aligned;
   }

   bool ValidateStopLevels(double entryPrice, double slPrice, double tpPrice) {
      long stops_level_pts = SymbolInfoInteger(m_symbol, SYMBOL_TRADE_STOPS_LEVEL);
      double minStopDist = stops_level_pts * _Point;
      if(slPrice > 0.0) {
         double slDistance = MathAbs(entryPrice - slPrice);
         if(slDistance < minStopDist) {
            PrintFormat("ERROR: SL distance (%.5f) < broker min (%.5f) — trade aborted", slDistance, minStopDist);
            return false;
         }
      }
      if(tpPrice > 0.0) {
         double tpDistance = MathAbs(tpPrice - entryPrice);
         if(tpDistance < minStopDist) {
            PrintFormat("ERROR: TP distance (%.5f) < broker min (%.5f) — trade aborted", tpDistance, minStopDist);
            return false;
         }
      }
      return true;
   }

   double CalcLotByRisk(double entry_price, double sl_price) {
      if(m_settings.RiskPercent <= 0.0 || sl_price <= 0.0) return 0.0;
      double stop_dist = MathAbs(entry_price - sl_price);
      if(stop_dist <= 0.0) return 0.0;
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      if(equity <= 0.0) equity = AccountInfoDouble(ACCOUNT_BALANCE);
      if(equity <= 0.0) return 0.0;
      double risk_money = equity * (m_settings.RiskPercent / 100.0);
      if(risk_money <= 0.0) return 0.0;

      double tick_size = 0.0, tick_value = 0.0;
      if(!SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE, tick_size) || tick_size <= 0.0) return 0.0;

      // Tick value in ACCOUNT currency, self-corrected against contract
      // economics (see ResolveTickValue) so the pip-mode / non-USD tester bug
      // that reported tv=0.10 instead of ~1.00 for XAUUSD can no longer 10×
      // the lot size.
      tick_value = ResolveTickValue();
      if(tick_value <= 0.0) return 0.0; // could not establish a usable value

      // Loss of one lot from entry to the actual stop, in ACCOUNT currency,
      // computed by the terminal's own profit engine (OrderCalcProfit). This is
      // the value that was previously corrupted by the bad tick_value field.
      double loss_per_lot = RiskMoneyPerLot(stop_dist);
      if(loss_per_lot <= 0.0) {
         // engine path failed → reconstruct from the (resolved) per-tick value
         loss_per_lot = (stop_dist / tick_size) * tick_value;
      }
      if(loss_per_lot <= 0.0) return 0.0;

      // ── Diagnostic: log full symbol economics on first call ──
      static bool s_first_calc = true;
      if(s_first_calc)
      {
         s_first_calc = false;
         double contract_size = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_CONTRACT_SIZE);
         string acc_ccy       = AccountInfoString(ACCOUNT_CURRENCY);
         string profit_ccy    = SymbolInfoString(m_symbol, SYMBOL_CURRENCY_PROFIT);
         string margin_ccy    = SymbolInfoString(m_symbol, SYMBOL_CURRENCY_MARGIN);
         double vol_min       = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
         double vol_step      = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);
         double raw_tv_loss   = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
         double raw_tv_gen    = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE);
         PrintFormat("📊 [LOT DIAG] %s | account_ccy=%s | profit_ccy=%s | margin_ccy=%s",
                     m_symbol, acc_ccy, profit_ccy, margin_ccy);
         PrintFormat("📊 [LOT DIAG] %s | contract=%.0f | tick_sz=%.5f | raw_tv_loss=%.5f | raw_tv_generic=%.5f | tv_resolved=%.5f",
                     m_symbol, contract_size, tick_size, raw_tv_loss, raw_tv_gen, tick_value);
         PrintFormat("📊 [LOT DIAG] %s | loss_per_lot(engine)=%.4f for stop=%.5f | vol_min=%.2f | vol_step=%.2f",
                     m_symbol, loss_per_lot, stop_dist, vol_min, vol_step);
      }

      double raw_lot = risk_money / loss_per_lot;
      if(raw_lot <= 0.0) return 0.0;

      // Warn if lot is being clamped to minimum (risk will exceed target)
      double vol_min = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
      if(raw_lot < vol_min && vol_min > 0.0)
      {
         double actual_risk_money = loss_per_lot * vol_min;
         double actual_risk_pct = (equity > 0.0) ? (actual_risk_money / equity * 100.0) : 0.0;
         PrintFormat("⚠️ [LOT CALC] %s raw_lot=%.4f < min_lot=%.2f — clamped to minimum. "
                     "Actual risk: %.2f %s (%.2f%%) vs target: %.2f %s (%.2f%%)",
                     m_symbol, raw_lot, vol_min,
                     actual_risk_money, AccountInfoString(ACCOUNT_CURRENCY), actual_risk_pct,
                     risk_money, AccountInfoString(ACCOUNT_CURRENCY), m_settings.RiskPercent);
      }

      double large_lot_threshold = (equity / SEA_LARGE_LOT_EQUITY_BLOCK_USD) * SEA_LARGE_LOT_PER_EQUITY_BLOCK;
      double pip_size = GetPipSize();
      if(pip_size > 0.0 && raw_lot > large_lot_threshold) {
         PrintFormat("⚠️ [CM] Very large lot computed: %.2f lots for %.1f pip SL on %.0f %s equity -- check SL_MinPips setting",
                     raw_lot, stop_dist / pip_size, equity, AccountInfoString(ACCOUNT_CURRENCY));
      }

      // ──────────────────────────────────────────────────────────────────────
      // HARD PER-TRADE RISK CAP (circuit breaker).
      //
      // With RiskMoneyPerLot() the 2% target is computed correctly, so this cap
      // should NEVER trigger in normal operation. It is a last-line defence
      // against a silent environmental fault — a broker/symbol reporting a
      // degenerate tick value or contract size, or a future code regression —
      // any of which could oversize the position. Without it such a fault
      // oversizes silently and is only discovered after a stop-out (exactly how
      // the original 10× bug erased half the account); with it the order is
      // clamped and the anomaly logged loudly.
      //
      // CRITICAL: the cap must validate against an INDEPENDENT measure of the
      // worst-case loss, not against `loss_per_lot` (which, if itself wrong,
      // would make the check circular and useless). We ask the terminal's own
      // engine, OrderCalcProfit, for the actual CHF loss of `raw_lot` at the
      // sizing stop. If that exceeds RiskCapMultiple × target risk, clamp.
      // ──────────────────────────────────────────────────────────────────────
      double risk_cap_mult    = (m_settings.RiskCapMultiple > 0.0) ? m_settings.RiskCapMultiple : 1.5;
      double max_loss_allowed = risk_money * risk_cap_mult;

      double ref_px = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      if(ref_px <= 0.0) ref_px = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
      double engine_loss = 0.0;   // independent worst-case loss of raw_lot at the sizing stop
      if(ref_px > 0.0)
      {
         if(!OrderCalcProfit(ORDER_TYPE_BUY, m_symbol, raw_lot, ref_px, ref_px - stop_dist, engine_loss))
            engine_loss = 0.0;   // engine call failed → fall back below
      }
      engine_loss = MathAbs(engine_loss);
      // Fallback to the loss_per_lot estimate only if the engine call failed.
      if(engine_loss <= 0.0) engine_loss = raw_lot * loss_per_lot;

      if(engine_loss > max_loss_allowed && engine_loss > 0.0)
      {
         double scale       = max_loss_allowed / engine_loss;   // <1
         double capped_lot  = raw_lot * scale;
         PrintFormat("🛑 [RISK CAP] %s raw_lot=%.4f would risk %.2f %s (%.2f%%) > cap %.2f%% (%.1f× target %.2f%%). "
                     "Clamping to %.4f lots. Investigate tick_value/contract/SL — sizing should not reach here.",
                     m_symbol, raw_lot, engine_loss, AccountInfoString(ACCOUNT_CURRENCY),
                     (equity > 0.0 ? engine_loss / equity * 100.0 : 0.0),
                     (equity > 0.0 ? max_loss_allowed / equity * 100.0 : 0.0),
                     risk_cap_mult, m_settings.RiskPercent,
                     capped_lot);
         raw_lot = capped_lot;
      }

      PrintFormat("📊 [LOT CALC] %s | stop=%.5f | tick_sz=%.5f | tick_val=%.5f | loss_per_lot=%.4f | risk=%.2f %s | raw_lot=%.4f | final_lot=%.4f",
                  m_symbol,
                  stop_dist,
                  tick_size,
                  tick_value,
                  loss_per_lot,
                  risk_money,
                  AccountInfoString(ACCOUNT_CURRENCY),
                  raw_lot,
                  NormalizeVolume(raw_lot));
      return NormalizeVolume(raw_lot);
   }

   // BUG FIX: Renamed from CountConsecutiveLosses() — daily scope for DrawdownProtection
   int CountConsecutiveLossesToday(){
      datetime to = TimeCurrent();
      
      // FIX: Calculate midnight (start of the current server day)
      // This ensures the consecutive loss counter resets to 0 every day
      datetime start_of_day = to - (to % 86400); 
      
      // Only select history for TODAY, not the entire account lifetime
      HistorySelect(start_of_day, to);
      
      int losses = 0;
      int total = HistoryDealsTotal();
      for(int i = total - 1; i >= 0 && losses < 100; i--) {
         ulong deal = HistoryDealGetTicket(i);
         if(deal == 0) continue;
         if(HistoryDealGetString(deal, DEAL_SYMBOL) != m_symbol) continue;
         if((ulong)HistoryDealGetInteger(deal, DEAL_MAGIC) != m_magic) continue;
         
         long entry = HistoryDealGetInteger(deal, DEAL_ENTRY);
         if(entry != DEAL_ENTRY_OUT) continue; // Only look at closed trades
         
         double profit = HistoryDealGetDouble(deal, DEAL_PROFIT);
         if(profit < 0.0) { 
            losses++; 
            continue; 
         }
         break; // If we find a win today, stop counting
      }
      return losses;
   }

   // BUG FIX: Full-history version for MA lot sizing (matches MetaQuotes MA EA behaviour)
   int CountConsecutiveLossesTotal(){
      datetime to = TimeCurrent();
      HistorySelect(0, to);
      int losses = 0;
      int total = HistoryDealsTotal();
      for(int i = total - 1; i >= 0 && losses < 100; i--) {
         ulong deal = HistoryDealGetTicket(i);
         if(deal == 0) continue;
         if(HistoryDealGetString(deal, DEAL_SYMBOL) != m_symbol) continue;
         if((ulong)HistoryDealGetInteger(deal, DEAL_MAGIC) != m_magic) continue;
         long entry = HistoryDealGetInteger(deal, DEAL_ENTRY);
         if(entry != DEAL_ENTRY_OUT) continue;
         double profit = HistoryDealGetDouble(deal, DEAL_PROFIT);
         if(profit < 0.0) { losses++; continue; }
         break;
      }
      return losses;
   }

   double CalcLotMACompat() {
      double mr = m_settings.MA_MaximumRiskPct;
      if(mr <= 0.0) return 0.0;
      double price = 0.0;
      if(!SymbolInfoDouble(m_symbol, SYMBOL_ASK, price)) return 0.0;
      double margin = 0.0;
      if(!OrderCalcMargin(ORDER_TYPE_BUY, m_symbol, 1.0, price, margin)) return 0.0;
      if(margin <= 0.0) return 0.0;
      double free = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      if(free <= 0.0) return 0.0;
      double lot = NormalizeDouble(free * mr / margin, 2);
      // BUG FIX: Use full-history loss count (matches MetaQuotes MA EA) instead of daily-only count
      int losses = CountConsecutiveLossesTotal();
      double df = m_settings.MA_DecreaseFactor;
      if(losses > 1 && df > 0.0) {
         lot = NormalizeDouble(lot - lot * losses / df, 1);
      }
      return NormalizeVolume(lot);
   }

   double AdjustLotForMargin(ENUM_ORDER_TYPE type, double vol, double price) {
      if(vol <= 0.0) return 0.0;
      double free = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      if(free <= 0.0) return 0.0;
      double margin_per_lot = 0.0;
      if(!OrderCalcMargin(type, m_symbol, 1.0, price, margin_per_lot) || margin_per_lot <= 0.0) {
         // Broker/symbol can occasionally fail 1-lot probing; fall back to direct requested-volume check.
         double margin = 0.0;
         if(!OrderCalcMargin(type, m_symbol, vol, price, margin) || margin <= 0.0) return vol;
         return (margin <= free) ? vol : 0.0;
      }

      double usage_limit_pct = m_settings.MarginUsageLimit;
      // Config semantics: 0 means "no cap override", i.e. allow up to 100% of free margin.
      // Settings are clamped to >=0 in InitializeConfig(); <=0 check is defensive.
      if(usage_limit_pct <= 0.0) usage_limit_pct = 100.0;
      double safe_free = free * usage_limit_pct / 100.0;
      double max_vol = safe_free / margin_per_lot;
      vol = NormalizeVolume(MathMin(vol, max_vol));

      // Secondary cap: ensure projected margin level stays above MinMarginLevel
      if(m_settings.MinMarginLevel > 0.0) {
         double equity = AccountInfoDouble(ACCOUNT_EQUITY);
         double current_margin = AccountInfoDouble(ACCOUNT_MARGIN);
         double adjusted_threshold = m_settings.MinMarginLevel * GetMarginLevelAdjustment();
         if(equity > 0.0 && margin_per_lot > 0.0 && adjusted_threshold > 0.0) {
            double max_additional_margin = (equity / (adjusted_threshold / 100.0)) - current_margin;
            if(max_additional_margin <= 0.0) return 0.0;
            double max_vol_by_margin_level = max_additional_margin / margin_per_lot;
            vol = NormalizeVolume(MathMin(vol, max_vol_by_margin_level));
         }
      }

      double vmin = 0.0;
      if(!SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN, vmin) || vmin <= 0.0) vmin = 0.01;
      if(vol < vmin) return 0.0;
      return vol;
   }

   //+------------------------------------------------------------------+
   //| REFACTORED: PURE PRICE ANCHOR SL CALCULATION                     |
   //+------------------------------------------------------------------+
   //+------------------------------------------------------------------+
   //| EnforceSLMinFloor — STEP19 2026-06 (extended STEP20 2026-06)      |
   //|                                                                  |
   //| Applies the SL_MinPips (user) AND broker-minimum (SYMBOL_TRADE_  |
   //| STOPS_LEVEL) floors to a candidate SL price. Single source of    |
   //| truth for BOTH Path 1 (RRM_GetStrictSL) AND Path 2 (CalcEntrySL  |
   //| — SIMPLE exit profile / FPM/MA/TI).                              |
   //|                                                                  |
   //| Returns:                                                          |
   //|   • the candidate SL unchanged if already at or beyond min dist   |
   //|   • the widened SL (price ± min_dist) if SL_WidenToMinimum=true   |
   //|     and the candidate was too close                               |
   //|   • 0.0 if SL_WidenToMinimum=false and the candidate was too      |
   //|     close — caller should treat this as a trade-block signal      |
   //|                                                                   |
   //| The Inp_Global_SL_MinPips comment promises "broker minimum still |
   //| applies" — STEP19 wired Path 2's five return points to this      |
   //| helper (was: no floor at all on SIMPLE exit profile, silently    |
   //| dropping the user's SL_MinPips setting). STEP20 then dedup'd     |
   //| Path 1's inline ~22-line floor block to one call here. Both      |
   //| paths now share this single floor implementation.                |
   //+------------------------------------------------------------------+
   double EnforceSLMinFloor(bool isBuy, double price, double sl) {
      if(sl <= 0.0) return sl;   // upstream already blocking; pass through
      double pipSize = GetPipSize();
      double user_min_dist = m_settings.SL_MinPips * pipSize;
      long stops_level_points = 0;
      if(!SymbolInfoInteger(m_symbol, SYMBOL_TRADE_STOPS_LEVEL, stops_level_points)) {
         Print("⚠️ [SL] Failed to read SYMBOL_TRADE_STOPS_LEVEL; using 0 points + 1 pip buffer fallback");
         stops_level_points = 0;
      }
      double broker_min_dist = (double)stops_level_points * _Point + pipSize;
      double min_sl_dist = MathMax(user_min_dist, broker_min_dist);

      double actual_dist = MathAbs(price - sl);
      if(actual_dist < min_sl_dist) {
         if(m_settings.SL_WidenToMinimum) {
            sl = isBuy ? (price - min_sl_dist) : (price + min_sl_dist);
            PrintFormat("⚠️ [SL] SL too close (%.1f pips), widened to minimum (%.1f pips)",
                        actual_dist / pipSize, min_sl_dist / pipSize);
         } else {
            PrintFormat("🚫 [SL] SL too close (%.1f pips < min %.1f pips), trade blocked",
                        actual_dist / pipSize, min_sl_dist / pipSize);
            return 0.0;
         }
      }
      return sl;
   }

   double RRM_GetStrictSL(bool isBuy, double price) {
      double pipSize = GetPipSize();
      double fixed_dist = m_settings.SL_FixedPips * pipSize;
      double sl = isBuy ? (price - fixed_dist) : (price + fixed_dist);
      
      switch(m_settings.SLMode) {
         case SL_MODE_SWING: {
            double swing_level = GetSwingLevel(isBuy ? 1 : -1);
            if(swing_level > 0.0) {
               bool valid = isBuy ? (swing_level < price) : (swing_level > price);
               if(!valid) {
                  PrintFormat("⚠️ [RRM SL] Swing anchor on wrong side. Using Fixed Pips.");
                  break;
               }
               double cushion_price = m_settings.SL_SwingPipsCushion * pipSize;
               sl = isBuy ? (swing_level - cushion_price) : (swing_level + cushion_price);
               break;
            }
            PrintFormat("⚠️ [RRM SL FALLBACK] Swing Anchor failed. Using Fixed Pips.");
            break;
         }
         case SL_MODE_PSAR_DOT: {
            double psar = GetPSARAnchor(1);
            if(psar > 0.0) {
               // Side validity — matches methodology: PSAR dot must be on
               // the trend side of the entry candle's CLOSED body.
               // Compare vs Close[1] (the closed entry candle), not the
               // live entry price — keeps the rule identical to the trail
               // path in CalcPsarTrailAnchorSL.
               double close_ref = iClose(m_symbol, PERIOD_CURRENT, 1);
               bool valid = (close_ref > 0.0)
                  ? (isBuy ? (psar < close_ref) : (psar > close_ref))
                  : (isBuy ? (psar < price)     : (psar > price));   // safe fallback
               if(!valid) {
                  PrintFormat("⚠️ [RRM SL] PSAR wrong side. psar=%.5f close[1]=%.5f entry=%.5f dir=%s — trying Swing fallback",
                              psar, close_ref, price, isBuy ? "BUY" : "SELL");
                  // Swing-first fallback — preserves the methodology
                  // (Swing High/Low is the OTHER documented placement on
                  // the Stop Loss card). Only falls to Fixed Pips if both
                  // structural anchors fail, so the SL never silently
                  // degrades from "methodology" to "arbitrary distance".
                  double swing_fb = GetSwingLevel(isBuy ? 1 : -1);
                  bool swing_ok = (swing_fb > 0.0) &&
                                  (isBuy ? (swing_fb < price) : (swing_fb > price));
                  if(swing_ok) {
                     double cushion_price = m_settings.SL_SwingPipsCushion * pipSize;
                     sl = isBuy ? (swing_fb - cushion_price) : (swing_fb + cushion_price);
                     PrintFormat("✅ [RRM SL] Swing fallback used: anchor=%.5f → SL=%.5f", swing_fb, sl);
                     break;
                  }
                  PrintFormat("⚠️ [RRM SL FALLBACK] Both PSAR and Swing invalid — Using Fixed Pips.");
                  break;
               }
               double cushion_price = m_settings.SL_PsarPipsCushion * pipSize;
               sl = isBuy ? (psar - cushion_price) : (psar + cushion_price);
               break;
            }
            PrintFormat("⚠️ [RRM SL FALLBACK] PSAR Anchor failed or buffer empty. Using Fixed Pips.");
            break;
         }
         case SL_MODE_FRACTAL: {
            double frac_level = GetFractalLevel(isBuy ? 1 : -1);
            if(frac_level > 0.0) {
               bool valid = isBuy ? (frac_level < price) : (frac_level > price);
               if(!valid) {
                  PrintFormat("⚠️ [RRM SL] Fractal anchor on wrong side. Using Fixed Pips.");
                  break;
               }
               double cushion_price = m_settings.SL_SwingPipsCushion * pipSize;
               sl = isBuy ? (frac_level - cushion_price) : (frac_level + cushion_price);
               break;
            }
            PrintFormat("⚠️ [RRM SL FALLBACK] Fractal Anchor failed. Using Fixed Pips.");
            break;
         }
         case SL_MODE_ATR: {
            // Full fallback hierarchy:
            // 1. Swing anchor + ATR cushion  (ideal — volatility-scaled below structure)
            // 2. Swing anchor fails/wrong side → ATR cushion from entry price (still volatility-correct)
            // 3. ATR read fails entirely → only then fall through to SL_MinPips floor
            double atr_val = GetSLAtr();
            double swing_level = GetSwingLevel(isBuy ? 1 : -1);
            bool swing_valid = (swing_level > 0.0 &&
                                (isBuy ? (swing_level < price) : (swing_level > price)));

            if(swing_valid && atr_val > 0.0) {
               // Best case: swing anchor − ATR×mult
               double cushion = atr_val * m_settings.SL_AtrMult;
               sl = isBuy ? (swing_level - cushion) : (swing_level + cushion);
               PrintFormat("✅ [RRM SL ATR] swing=%.5f ATR=%.5f mult=%.2f SL=%.5f",
                           swing_level, atr_val, m_settings.SL_AtrMult, sl);
            }
            else if(atr_val > 0.0) {
               // Swing failed or wrong side — use ATR cushion from entry price
               // Still volatility-correct; avoids fixed-pip fallback on Gold/indices
               double cushion = atr_val * m_settings.SL_AtrMult;
               sl = isBuy ? (price - cushion) : (price + cushion);
               PrintFormat("⚠️ [RRM SL ATR] Swing failed — using ATR from entry: cushion=%.5f SL=%.5f",
                           cushion, sl);
            }
            else {
               // ATR completely unavailable — fall through to SL_MinPips floor below
               PrintFormat("⚠️ [RRM SL ATR FALLBACK] ATR unavailable — SL_MinPips floor will apply");
            }
            break;
         }
         default:
            break;
      }

      // STEP20 2026-06: SL_MinPips floor (Path 1 dedup; pairs with STEP19 Path 2 callsites).
      // The inline floor block (~22 lines: user_min_dist / broker stops_level / widen-vs-block)
      // is replaced with a single EnforceSLMinFloor call. Behavior-preserving — the helper
      // is now the single source of truth for the SL floor across BOTH Path 1 (RRM) and
      // Path 2 (SIMPLE/FPM/MA/TI). `sl` is always nonzero here (initialized to fixed-pips
      // fallback at the top of RRM_GetStrictSL), so the helper's sl<=0 guard is a no-op.
      return EnforceSLMinFloor(isBuy, price, sl);
   }

   double CalcEntrySL(bool isBuy, double price) {
      double sl = 0.0;
      double pipSize = GetPipSize();

      if(m_settings.ExitProfile == EXIT_PROFILE_RRM) {
         return RRM_GetStrictSL(isBuy, price);
      }

      double anchor = 0.0;
      double cushion_pips = 0.0;

      PrintFormat("🔍 [SL TRACE] Calculating Entry SL... Mode: %s | isBuy: %s | EntryPrice: %.5f", EnumToString(m_settings.SLMode), isBuy ? "YES" : "NO", price);

      switch(m_settings.SLMode) {
         case SL_MODE_SWING:
            anchor = GetSwingLevel(isBuy ? 1 : -1);
            cushion_pips = m_settings.SL_SwingPipsCushion;
            if(anchor > 0.0) {
               bool valid = isBuy ? (anchor < price) : (anchor > price);
               if(!valid) {
                  // FIX: was silently falling through to fixed pips — now tries PSAR as secondary fallback
                  PrintFormat("⚠️ [SL] Swing anchor (%.5f) on wrong side of entry (%.5f) for %s — trying PSAR fallback", anchor, price, isBuy ? "BUY" : "SELL");
                  double psar_anchor = GetPSARAnchor(1);
                  bool psar_valid = (psar_anchor > 0.0) && (isBuy ? (psar_anchor < price) : (psar_anchor > price));
                  if(psar_valid) {
                     anchor       = psar_anchor;
                     cushion_pips = m_settings.SL_PsarPipsCushion;
                     PrintFormat("✅ [SL] PSAR fallback used: %.5f", anchor);
                  } else {
                     PrintFormat("⚠️ [SL] PSAR also invalid — using fixed pips (%.1f)", m_settings.SL_FixedPips);
                     anchor = 0.0;
                  }
               }
            }
            break;
         case SL_MODE_PSAR_DOT:
            anchor = GetPSARAnchor(1);
            cushion_pips = m_settings.SL_PsarPipsCushion;
            if(anchor > 0.0) {
               // Match RRM_GetStrictSL: validate PSAR vs the CLOSED candle's
               // body (close[1]) rather than the live entry price, so the
               // rule is identical to the trail path in CalcPsarTrailAnchorSL.
               double close_ref = iClose(m_symbol, PERIOD_CURRENT, 1);
               bool valid = (close_ref > 0.0)
                  ? (isBuy ? (anchor < close_ref) : (anchor > close_ref))
                  : (isBuy ? (anchor < price)     : (anchor > price));   // safe fallback
               if(!valid) {
                  PrintFormat("⚠️ [SL] PSAR wrong side (psar=%.5f close[1]=%.5f entry=%.5f, %s) — trying Swing fallback before Fixed Pips",
                              anchor, close_ref, price, isBuy ? "BUY" : "SELL");
                  // Try Swing as a methodology-aligned fallback BEFORE
                  // collapsing to fixed pips (Swing High/Low is the second
                  // documented SL placement on the methodology card).
                  double swing_fb = GetSwingLevel(isBuy ? 1 : -1);
                  bool swing_ok = (swing_fb > 0.0) &&
                                  (isBuy ? (swing_fb < price) : (swing_fb > price));
                  if(swing_ok) {
                     anchor       = swing_fb;
                     cushion_pips = m_settings.SL_SwingPipsCushion;
                     PrintFormat("✅ [SL] Swing fallback used: anchor=%.5f", anchor);
                  } else {
                     anchor = 0.0;  // both failed → fixed pips below
                  }
               }
            }
            break;
         case SL_MODE_FRACTAL:
            anchor = GetFractalLevel(isBuy ? 1 : -1);
            cushion_pips = m_settings.SL_SwingPipsCushion;  // FIX: was 0.0 — use same cushion as Swing
            // STEP17 2026-06: side-validity check (sibling of RRM_GetStrictSL FRACTAL guard
            // at line 1337+). Path 2 was the only anchor-based mode here without this gate
            // — SWING/PSAR/ATR all validated their anchors against `price`, but FRACTAL went
            // straight through. If GetFractalLevel returns a level on the WRONG side of entry
            // (price ran past the most recent fractal in a sharp move, or regime-transition),
            // the post-switch tail (lines ~1525+) would use it as the SL anchor — placing SL
            // ABOVE entry for LONG / BELOW entry for SHORT. The trade enters at immediate
            // loss territory and likely auto-stops on the first tick. Path 1 (RRM profile)
            // had this guard since file authoring; Path 2 (SIMPLE profile — FPM/MA/TI users)
            // was missed. STEP17 zeroed the anchor on invalid side (→ fixed pips).
            //
            // STEP21 2026-06: secondary structural fallback added. The STEP17-era stance
            // ("no secondary fallback — matches Path 1 simplicity") was the lone outlier
            // among Path 2's anchor modes: SWING falls back to PSAR (line 1465+), and
            // PSAR_DOT falls back to SWING (line 1494+). FRACTAL alone collapsed straight
            // to "arbitrary distance" (fixed pips) on a wrong-side anchor — silently
            // discarding the structural placement the user asked for. FRACTAL now mirrors
            // PSAR_DOT: on wrong-side fractal, try Swing High/Low as the methodology-
            // aligned secondary before degrading to fixed pips. Matches the author's
            // broader pattern "structural anchor before fixed pips".
            // NOTE: Path 1's FRACTAL case (RRM_GetStrictSL, ~line 1386) has the same gap
            // and is flagged as a separate sibling follow-up.
            if(anchor > 0.0) {
               bool valid = isBuy ? (anchor < price) : (anchor > price);
               if(!valid) {
                  PrintFormat("⚠️ [SL] Fractal anchor (%.5f) on wrong side of entry (%.5f) for %s — trying Swing fallback before Fixed Pips",
                              anchor, price, isBuy ? "BUY" : "SELL");
                  // STEP21 2026-06: Swing fallback (mirrors PSAR_DOT block at line 1494+).
                  double swing_fb = GetSwingLevel(isBuy ? 1 : -1);
                  bool swing_ok = (swing_fb > 0.0) &&
                                  (isBuy ? (swing_fb < price) : (swing_fb > price));
                  if(swing_ok) {
                     anchor       = swing_fb;
                     cushion_pips = m_settings.SL_SwingPipsCushion;   // already set above; explicit for parity with PSAR_DOT fallback
                     PrintFormat("✅ [SL] Swing fallback used: anchor=%.5f", anchor);
                  } else {
                     anchor = 0.0;   // both failed → fixed pips below
                  }
               }
            }
            break;
         case SL_MODE_ATR: {
            // Full fallback hierarchy — ATR never falls back to raw fixed pips:
            // 1. Swing anchor + ATR cushion (ideal)
            // 2. Swing fails/wrong side → ATR cushion from entry price (still volatility-correct)
            // 3. ATR entirely unavailable → fall through to SL_MinPips floor (last resort only)
            double atr_val = GetSLAtr();
            anchor = GetSwingLevel(isBuy ? 1 : -1);
            bool swing_valid = (anchor > 0.0 &&
                                (isBuy ? (anchor < price) : (anchor > price)));

            if(swing_valid && atr_val > 0.0) {
               double cushion = atr_val * m_settings.SL_AtrMult;
               double sl_atr = isBuy ? (anchor - cushion) : (anchor + cushion);
               PrintFormat("✅ [SL ATR] swing=%.5f ATR=%.5f mult=%.2f SL=%.5f",
                           anchor, atr_val, m_settings.SL_AtrMult, sl_atr);
               return EnforceSLMinFloor(isBuy, price, sl_atr);   // STEP19 2026-06: SL_MinPips floor
            }
            else if(atr_val > 0.0) {
               // Swing failed/wrong side — ATR cushion from entry price
               double cushion = atr_val * m_settings.SL_AtrMult;
               double sl_atr = isBuy ? (price - cushion) : (price + cushion);
               PrintFormat("⚠️ [SL ATR] Swing failed — ATR from entry: cushion=%.5f SL=%.5f",
                           cushion, sl_atr);
               return EnforceSLMinFloor(isBuy, price, sl_atr);   // STEP19 2026-06: SL_MinPips floor
            }
            else {
               // ATR unavailable — SL_MinPips floor will apply below
               PrintFormat("⚠️ [SL ATR] ATR unavailable — SL_MinPips floor will apply");
               anchor = 0.0;
            }
            break;
         }
         case SL_MODE_PERCENT: {
            double sl_pips = (price * m_settings.SLPercent / 100.0) / pipSize;
            double sl_pct = isBuy ? (price - (sl_pips * pipSize)) : (price + (sl_pips * pipSize));
            return EnforceSLMinFloor(isBuy, price, sl_pct);   // STEP19 2026-06: SL_MinPips floor
         }
         case SL_MODE_FIXED_PIPS:
         default: {
            double dist = m_settings.SL_FixedPips * pipSize;
            PrintFormat("ℹ️ [SL TRACE] Using FIXED PIPS: %.1f", m_settings.SL_FixedPips);
            double sl_fp = isBuy ? (price - dist) : (price + dist);
            return EnforceSLMinFloor(isBuy, price, sl_fp);    // STEP19 2026-06: SL_MinPips floor
         }
      }

      if(anchor > 0.0) {
         double cushion_price = cushion_pips * pipSize;
         sl = isBuy ? (anchor - cushion_price) : (anchor + cushion_price);
         PrintFormat("✅ [SL TRACE] Anchor Found! Anchor: %.5f | Cushion: %.1f pips | Final SL: %.5f", anchor, cushion_pips, sl);
      } else {
         PrintFormat("❌ [SL TRACE] Anchor FAILED! Falling back to %f pips.", m_settings.SL_FixedPips);
         double fallback_dist = m_settings.SL_FixedPips * pipSize;
         sl = isBuy ? (price - fallback_dist) : (price + fallback_dist);
      }
      return EnforceSLMinFloor(isBuy, price, sl);   // STEP19 2026-06: SL_MinPips floor (anchor + fallback paths)
   }

   double RRM_GetStrictTP(bool isBuy, double entry, double sl) {
      if(!m_settings.TP_Enabled || m_settings.RRRatio <= 0.0 || sl <= 0.0) return 0.0;
      double sl_dist = MathAbs(entry - sl);
      if(sl_dist <= 0.0) return 0.0;
      double tp_dist = sl_dist * m_settings.RRRatio;
      return isBuy ? (entry + tp_dist) : (entry - tp_dist);
   }

   //+------------------------------------------------------------------+
   //| RESOLVE TRAIL CUSHION as a PRICE distance.                        |
   //| Priority: manual override (pips) -> mode (ATR / PERCENT / PIPS)   |
   //| -> percent-of-price safety floor. Never returns <= 0 while a      |
   //| valid price exists, so a position is never left without cushion.  |
   //+------------------------------------------------------------------+
   double ResolveTrailCushionPrice(double pipSize) {
      // 1) Manual override always wins, interpreted as fixed pips.
      if(m_settings.Override_Trail_Cushion > 0.0)
         return m_settings.Override_Trail_Cushion * pipSize;

      double mid = 0.0;
      double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
      if(bid > 0.0 && ask > 0.0) mid = (bid + ask) / 2.0;
      else                       mid = bid > 0.0 ? bid : ask;

      double pct_floor = (mid > 0.0 && m_settings.PSAR_TrailCushionPct > 0.0)
                         ? mid * (m_settings.PSAR_TrailCushionPct / 100.0) : 0.0;

      double cushion = 0.0;
      switch(m_settings.PSAR_TrailCushionMode) {
         case PSAR_CUSHION_ATR: {
            if(m_h_cushion_atr != INVALID_HANDLE) {
               double a[1];
               if(CopyBuffer(m_h_cushion_atr, 0, 1, 1, a) == 1 && a[0] > 0.0)
                  cushion = a[0] * m_settings.PSAR_TrailCushionAtrMult;
            }
            if(cushion <= 0.0) cushion = pct_floor; // ATR not ready -> percent floor
            break;
         }
         case PSAR_CUSHION_PERCENT:
            cushion = pct_floor;
            break;
         case PSAR_CUSHION_PIPS:
         default:
            cushion = m_settings.PSAR_TrailPipsCushion * pipSize;
            break;
      }

      // Final safety: never zero cushion if we have a price to floor against.
      if(cushion <= 0.0 && pct_floor > 0.0) cushion = pct_floor;
      return cushion;
   }

   //+------------------------------------------------------------------+
   //| SHARED PSAR TRAIL SL: single source of truth for both trail paths|
   //| Resolves the trailing shift (RRM_TrailPsarDotShift, clamped     |
   //| 1..3), fetches the SAR dot at that shift, and applies the cushion. |
   //| NOTE: governs TRAILING only. Initial SL placement (SL_MODE_PSAR_DOT|
   //| in CalcEntrySL) intentionally keeps GetPSARAnchor(1) — the freshest|
   //| dot — because entry-risk sizing wants the closest valid stop, while|
   //| trailing wants flip-stability via the shift.                       |
   //| Returns the proposed SL price, or 0.0 if the anchor is unavailable.|
   //+------------------------------------------------------------------+
   double CalcPsarTrailAnchorSL(bool isBuy, double pipSize, int digits) {
      int shift = m_settings.RRM_TrailPsarDotShift;
      if(shift < 1) shift = 1;
      if(shift > 3) shift = 3;
      double psar = GetPSARAnchor(shift);
      if(psar <= 0.0) return 0.0;

      // ── PSAR side validity (RRM methodology) ──────────────────────────
      // The trail anchor MUST be a dot on the trend side of the closed
      // candle's body: dot below close for LONG, above close for SHORT.
      // A flipped (wrong-side) dot is NOT a valid trailing reference; we
      // refuse to propose a new anchor so the SL stays at the last good
      // value and resumes trailing only when PSAR returns to the correct
      // side on a subsequent closed bar.
      //
      // Reference: Stop Loss methodology card —
      //   "Move stop loss as each new dot progresses past the entry
      //    (break-even) level."  i.e. only progressing dots on the
      //    trend side qualify; dots on the wrong side do not.
      double close_ref = iClose(m_symbol, PERIOD_CURRENT, shift);
      if(close_ref <= 0.0) return 0.0;
      bool on_correct_side = isBuy ? (psar < close_ref) : (psar > close_ref);
      if(!on_correct_side) {
         if(m_settings.DebugFlow)
            PrintFormat("[PSAR TRAIL] Wrong-side dot ignored: psar=%.5f close[%d]=%.5f dir=%s — SL held at last good value",
                        psar, shift, close_ref, isBuy ? "BUY" : "SELL");
         return 0.0;  // caller treats 0.0 as "no proposal" → SL untouched
      }

      double cushion = ResolveTrailCushionPrice(pipSize);
      return isBuy ? NormalizeDouble(psar - cushion, digits)
                   : NormalizeDouble(psar + cushion, digits);
   }

   //+------------------------------------------------------------------+
   //| REFACTORED: STRICT TRAILING MANAGEMENT (No Double Scaling)       |
   //+------------------------------------------------------------------+
   void RRM_ManageStrictNoATR(ulong ticket) {
      if(!PositionSelectByTicket(ticket)) return;
      InitPositionState(ticket);

      if(ticket != m_rrm_last_ticket) {
         m_rrm_last_ticket  = ticket;
         m_rrm_trail_frozen = false;
         m_rrm_freeze_time  = 0;
         m_rrm_be_reached   = false;
         if(m_rrm_initial_sl <= 0.0) m_rrm_initial_sl = PositionGetDouble(POSITION_SL);
         if(m_initial_sl_price <= 0.0) m_initial_sl_price = PositionGetDouble(POSITION_SL);
      }

      ENUM_POSITION_TYPE pos_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      bool   isBuy     = (pos_type == POSITION_TYPE_BUY);
      double entry     = PositionGetDouble(POSITION_PRICE_OPEN);
      double cur_price = isBuy ? SymbolInfoDouble(m_symbol, SYMBOL_BID) : SymbolInfoDouble(m_symbol, SYMBOL_ASK);
      double cur_sl    = PositionGetDouble(POSITION_SL);
      double cur_tp    = PositionGetDouble(POSITION_TP);
      int    digits    = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
      double pipSize   = GetPipSize();

      double R = (m_rrm_initial_sl > 0.0) ? MathAbs(entry - m_rrm_initial_sl) : 0.0;
      m_rrm_be_reached = GetPositionBETriggered(ticket);

      // BREAKEVEN
      if(m_settings.BE_Mode != BE_MODE_OFF && !m_rrm_be_reached) {
         double move = isBuy ? (cur_price - entry) : (entry - cur_price);
         bool should_be = false;

         if(m_settings.BE_Mode == BE_MODE_TP_PROGRESS_PCT && cur_tp > 0.0) {
            double tp_dist = MathAbs(cur_tp - entry);
            if(tp_dist > 0.0 && m_settings.RRM_BE_ProgressPct > 0.0)
               should_be = (move >= tp_dist * (m_settings.RRM_BE_ProgressPct / 100.0));
         }
         else if(m_settings.BE_Mode == BE_MODE_R_MULTIPLE && R > 0.0) {
            should_be = (move >= m_settings.RRM_BE_RMultiple * R);
         }

         if(should_be) {
            double be_buffer = m_settings.RRM_BE_BufferPips * pipSize;
            double be_sl = isBuy ? NormalizeDouble(entry + be_buffer, digits) : NormalizeDouble(entry - be_buffer, digits);
            bool already_locked = isBuy ? (cur_sl >= be_sl) : (cur_sl != 0.0 && cur_sl <= be_sl);
            if(already_locked || (isBuy ? (be_sl > cur_sl) : (cur_sl == 0.0 || be_sl < cur_sl))) {
               if(already_locked || (IsModifyAllowed() && m_trade.PositionModify(ticket, be_sl, cur_tp))) {
                  SetPositionBETriggered(ticket, true);
                  m_rrm_be_reached = true;
                  if(!already_locked) cur_sl = be_sl;
                  if(m_settings.DebugFlow) PrintFormat("[BE] Position #%I64u locked at %.5f (one-time lock)", ticket, already_locked ? cur_sl : be_sl);
               }
            }
         }
      }

      // TRAILING
      // Allow TRAIL_EMA to pass through (handled below); all other non-PSAR modes exit here
      if(m_settings.TrailMode != TRAIL_PSAR &&
         m_settings.TrailMode != TRAIL_PROFIT_PERCENT &&
         m_settings.TrailMode != TRAIL_EMA) return;
      if(m_settings.RRM_TrailStartsAfterBE && !m_rrm_be_reached) return;

      // SAFETY: delay trailing until the position has earned a minimum R-multiple of
      // open profit. This lets winners run instead of being trailed out early — the
      // direct lever against a low reward:risk ratio. OFF by default (0 = disabled).
      if(m_settings.Safety_DelayTrailUntilR && m_settings.Safety_TrailActivateR > 0.0 && R > 0.0) {
         double open_profit_dist = isBuy ? (cur_price - entry) : (entry - cur_price);
         if(open_profit_dist < m_settings.Safety_TrailActivateR * R) {
            if(m_settings.DebugFlow)
               PrintFormat("[SAFETY] Trail delayed: open %.1f pips < %.2fR (%.1f pips) — letting winner run",
                           open_profit_dist / pipSize, m_settings.Safety_TrailActivateR,
                           (m_settings.Safety_TrailActivateR * R) / pipSize);
            return;
         }
      }

      if(m_settings.TrailMode == TRAIL_PROFIT_PERCENT) {
         double lpr_sl = CalculateProfitPercentTrailSL(ticket, pos_type, entry, cur_price, cur_sl, pipSize, digits);
         if(lpr_sl != 0.0 && IsModifyAllowed()) m_trade.PositionModify(ticket, lpr_sl, cur_tp);
         return;
      }

      // Q3 (2026-06): TRAIL_EMA body extracted into ApplyTrailEMA helper so the
      // same evaluation runs whether ExitProfile is RRM or EXIT_PROFILE_SIMPLE.
      // Pre-Q3 this block held the full ~150-line TRAIL_EMA implementation; it now
      // delegates to the helper. All upstream RRM-path gates above this point
      // (TrailMode allow-list, RRM_TrailStartsAfterBE, Safety_DelayTrailUntilR)
      // remain unchanged — they fire before the helper runs.
      if(m_settings.TrailMode == TRAIL_EMA) {
         ApplyTrailEMA(ticket, isBuy, entry, cur_price, cur_sl, cur_tp, digits, pipSize, "RRM");
         return;
      }


      int shift = m_settings.RRM_TrailPsarDotShift;
      if(shift < 1) shift = 1;
      if(shift > 3) shift = 3;
      double psar = GetPSARAnchor(shift);
      if(psar <= 0.0) return;

      // PSAR flip is defined against the CLOSED candle's body, not the live tick.
      // Using cur_price (Bid) here misses flips whenever price has run a bit
      // past the freshly-flipped dot — and that's the exact scenario in which
      // CalcPsarTrailAnchorSL would otherwise propose a wrong-side anchor.
      double close_for_flip = iClose(m_symbol, PERIOD_CURRENT, shift);
      bool psar_flipped = (close_for_flip > 0.0)
         ? (isBuy ? (psar > close_for_flip) : (psar < close_for_flip))
         : (isBuy ? (psar > cur_price)      : (psar < cur_price));   // safe fallback if close unavailable
      if(psar_flipped) {
         if(m_settings.RRM_FreezeTrailOnFlip && !m_rrm_trail_frozen) {
            m_rrm_trail_frozen = true; m_rrm_freeze_time = TimeCurrent();
            if(m_settings.DebugFlow) PrintFormat("RRM Strict trail frozen (PSAR flip): %s | PSAR=%.5f Price=%.5f", m_symbol, psar, cur_price);
         }
         return;
      } else if(m_rrm_trail_frozen) {
         int min_freeze_bars = 2;
         int bars_frozen = (m_rrm_freeze_time > 0) ? Bars(m_symbol, PERIOD_CURRENT, m_rrm_freeze_time, TimeCurrent()) : 0;
         if(bars_frozen >= min_freeze_bars) {
            m_rrm_trail_frozen = false;
            if(m_settings.DebugFlow) PrintFormat("RRM Strict trail UNFROZEN (PSAR corrected): %s | PSAR=%.5f Price=%.5f", m_symbol, psar, cur_price);
         }
         else return;
      }

      double new_sl = CalcPsarTrailAnchorSL(isBuy, pipSize, digits);
      if(new_sl == 0.0) return;

      // STEP16 2026-06: PSAR trail BE-floor fix (sibling pattern to Step 15's TRAIL_EMA bug).
      // Previously this gate clamped new_sl to entry+RRM_BE_BufferPips, requiring the
      // PSAR-derived SL to be 75+ pips above entry on XAGUSD M1 before trail could engage —
      // effectively dormant for typical M1 trading. The buffer's actual purpose is the
      // one-time BE-LOCK event (BE block earlier in RRM_ManageStrictNoATR); it must NOT
      // also be a continuous threshold against trail engagement. Replaced with the simple
      // BE-floor pattern used by ApplyTrailEMA (line 333) and CalculateProfitPercentTrailSL
      // (line 208): never lock SL into loss territory, but allow trail as soon as the
      // PSAR-derived SL is at or above entry. The SIMPLE-path PSAR clamp at
      // EvaluateTM (~line 3230) gets the same fix.
      if(isBuy) {
         if(new_sl < entry) {
            if(m_settings.DebugFlow) PrintFormat("[PSAR GUARD] #%I64u: Dot below entry (%.5f < %.5f), trail blocked (BE-floor)", ticket, new_sl, entry);
            return;
         }
         if(m_settings.TrailLockProfit && cur_sl != 0.0 && new_sl <= cur_sl) {
            if(m_settings.DebugFlow) PrintFormat("[PSAR GUARD] #%I64u: Would move SL backwards (%.5f <= %.5f), trail blocked", ticket, new_sl, cur_sl);
            return;
         }
      } else {
         if(new_sl > entry) {
            if(m_settings.DebugFlow) PrintFormat("[PSAR GUARD] #%I64u: Dot above entry (%.5f > %.5f), trail blocked (BE-floor)", ticket, new_sl, entry);
            return;
         }
         if(m_settings.TrailLockProfit && cur_sl != 0.0 && new_sl >= cur_sl) {
            if(m_settings.DebugFlow) PrintFormat("[PSAR GUARD] #%I64u: Would move SL backwards (%.5f >= %.5f), trail blocked", ticket, new_sl, cur_sl);
            return;
         }
      }

      bool can_move = isBuy ? (new_sl > cur_sl && new_sl < cur_price) : ((cur_sl == 0.0 || new_sl < cur_sl) && new_sl > cur_price);
      if(can_move && IsModifyAllowed()) m_trade.PositionModify(ticket, new_sl, cur_tp);
   }

   void UpdatePositionExcursion(ulong ticket) {
      if(!PositionSelectByTicket(ticket)) {
         m_excursion.ticket = 0; m_excursion.mae_pips = 0.0; m_excursion.mfe_pips = 0.0; m_excursion.current_pips = 0.0;
         return;
      }

      if(m_excursion.ticket != ticket) {
         m_excursion.ticket = ticket;
         m_excursion.entry_time = (datetime)PositionGetInteger(POSITION_TIME);
         m_excursion.entry_price = PositionGetDouble(POSITION_PRICE_OPEN);
         m_excursion.mae_pips = 0.0; m_excursion.mfe_pips = 0.0; m_excursion.current_pips = 0.0;
         m_excursion.be_reached = false; m_excursion.trail_active = false; m_excursion.trail_type = "OFF";
         m_trail_ema_last_bar = 0;
      }

      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double current_price = PositionGetDouble(POSITION_PRICE_CURRENT);
      double pipSize = GetPipSize();
      double pnl_pips = (type == POSITION_TYPE_BUY) ? (current_price - m_excursion.entry_price) / pipSize : (m_excursion.entry_price - current_price) / pipSize;
      m_excursion.current_pips = pnl_pips;

      if(pnl_pips < m_excursion.mae_pips) m_excursion.mae_pips = pnl_pips;
      if(pnl_pips > m_excursion.mfe_pips) m_excursion.mfe_pips = pnl_pips;

      double current_sl = PositionGetDouble(POSITION_SL);
      if(current_sl > 0.0) {
         double sl_dist_from_entry = MathAbs(current_sl - m_excursion.entry_price);
         // STEP13 2026-06: was hardcoded "<= 5.0 * GetPipSize()". With XAGUSD M1
         // (RRM_BE_BufferPips ≈ 75 pips via GetTFBasedCushion × instrument fan),
         // the actual BE setpoint sits 75+ pips from entry, never inside 5 pips,
         // so be_reached was permanently FALSE and the TrailStartsAfterBE gate at
         // line 1830 NEVER OPENED for any user who enabled it. Same fix pattern
         // already lives at line 2172 (IsPositionAtBreakEven) — author noted there:
         // "BUG FIX: Use RRM_BE_BufferPips + 2.0 tolerance instead of hardcoded".
         // This site was missed; aligning it now.
         double be_tolerance = (m_settings.RRM_BE_BufferPips + 2.0) * GetPipSize();
         m_excursion.be_reached = (sl_dist_from_entry <= be_tolerance);
      }

      switch(m_settings.TrailMode) {
         case TRAIL_PSAR:
         case TRAIL_PSAR_FLIP_EXIT: m_excursion.trail_active = true; m_excursion.trail_type = "PSAR"; break;

         case TRAIL_EMA:
            // STEP15 2026-06: actual trail logic moved to ApplyTrailEMA helper (restoring
            // Q3 design intent — see lines 240-269). Previously a duplicate inline TRAIL_EMA
            // body lived here AND in ApplyTrailEMA, with both sharing m_trail_ema_last_bar
            // as their per-bar gate. This inline copy ran FIRST per tick (via
            // UpdateExcursionOnly→UpdatePositionExcursion, which fires before EvaluateTM
            // dispatches RRM_ManageStrictNoATR→ApplyTrailEMA), so the gate variable was
            // set here and ApplyTrailEMA was BLOCKED every bar. The effective trail logic
            // was the OLD inline copy: buggy "entry+RRM_BE_BufferPips" clamp (delayed engage
            // by ~75 pips on XAGUSD M1) AND PSAR cushion only (ignoring user's configured
            // TrailEMA_CushionAtrMult / TrailEMA_CushionPips). ApplyTrailEMA's correct
            // BE-floor + ATR/Fixed/PSAR cushion priority chain never ran for any preset.
            // Removing the inline body leaves ApplyTrailEMA unshadowed; telemetry-only here
            // matches every other TrailMode case in this switch.
            m_excursion.trail_active = true;
            m_excursion.trail_type   = "EMA";
            break;
         case TRAIL_FRACTAL: m_excursion.trail_active = true; m_excursion.trail_type = "FRACTAL"; break;
         case TRAIL_FIXED_PIPS: m_excursion.trail_active = true; m_excursion.trail_type = "FIXED"; break;
         case TRAIL_BREAKEVEN: m_excursion.trail_active = true; m_excursion.trail_type = "BE"; break;
         case TRAIL_PROFIT_PERCENT: m_excursion.trail_active = true; m_excursion.trail_type = "PROFIT%"; break;
         default: m_excursion.trail_active = false; m_excursion.trail_type = "OFF"; break;
      }
   }

public:
   CTradeExecutor() : m_last_trade_bar(0), m_last_close_bar(0), m_last_tracked_ticket(0), m_last_risk_warn(0),
                       m_rrm_last_ticket(0), m_rrm_trail_frozen(false),
                       m_rrm_be_reached(false), m_rrm_initial_sl(0.0),
                       m_last_tm_bar(0), m_initial_sl_price(0.0), m_rrm_freeze_time(0), m_last_marker_update(0),
                       m_last_te_time(0), m_last_te_result(""), m_last_te_reason(""),
                       m_cached_sl(0.0), m_cached_lots(0.0), m_cached_risk(0.0),
                       m_spread_block_bars(0), m_rc_veto_reason(""),
                       m_te_rej_open_delay(0), m_te_rej_bc_recheck(0), m_te_rej_spread_median(0),
                       m_te_pass_open_delay(0), m_te_pass_bc_recheck(0), m_te_pass_spread_median(0),
                       m_te_rej_time(0),    m_te_pass_time(0),
                       m_te_rej_news(0),    m_te_pass_news(0),
                       m_te_rej_spread(0),  m_te_pass_spread(0),
                       m_spread_history_count(0), m_spread_history_idx(0),
                       m_h_psar(INVALID_HANDLE), m_h_fractals(INVALID_HANDLE), m_h_cushion_atr(INVALID_HANDLE), m_h_sl_atr(INVALID_HANDLE), m_h_trail_ema_atr(INVALID_HANDLE), // CACHED HANDLES
                       m_dpi_hist_current(0.0), m_dpi_hist_trend(0), m_dpi_hist_decelerating(false), m_dpi_hist_green_present(false),
                       m_exits_dpi_hist(0)
   {
      m_excursion.ticket = 0; m_excursion.entry_time = 0; m_excursion.entry_price = 0.0;
      m_excursion.mae_pips = 0.0; m_excursion.mfe_pips = 0.0; m_excursion.current_pips = 0.0;
      m_excursion.be_reached = false; m_excursion.trail_active = false; m_excursion.trail_type = "OFF";
      ArrayInitialize(m_spread_history, 0.0);
   }

   ~CTradeExecutor() {
      ReleaseHandles();
   }

   datetime LastTETime()   const { return m_last_te_time; }
   string   LastTEResult() const { return m_last_te_result; }
   string   LastTEReason() const { return m_last_te_reason; }
   double   LastCachedSL()   const { return m_cached_sl; }
   double   LastCachedLots() const { return m_cached_lots; }
   double   LastCachedRisk() const { return m_cached_risk; }
   string   LastVetoReason() const { return m_te_veto_reason; }
   int      SpreadBlockBars() const { return m_spread_block_bars; }

   //+------------------------------------------------------------------+
   //| Classify whether a TE veto is temporary (retriable) or permanent |
   //| Temporary vetoes may resolve within the same bar; permanent ones  |
   //| indicate conditions that will not improve on subsequent ticks.    |
   //+------------------------------------------------------------------+
   bool IsTemporaryVeto(string veto_reason)
   {
      // VETO_OPEN_DELAY: bar age will increase — retry next tick
      if(veto_reason == "VETO_OPEN_DELAY") return true;
      // All other vetoes are considered permanent for the current bar
      return false;
   }

   // ── PHASE A.1: TE-side rejection counter getters ──────────────────
   // Used by SimpleEA OnDeinit to bridge counters into Signal.AddTeStats()
   int      RejOpenDelay()     const { return m_te_rej_open_delay;     }
   int      RejBCRecheck()     const { return m_te_rej_bc_recheck;     }
   int      RejSpreadMedian()  const { return m_te_rej_spread_median;  }
   int      PassOpenDelay()    const { return m_te_pass_open_delay;    }
   int      PassBCRecheck()    const { return m_te_pass_bc_recheck;    }
   int      PassSpreadMedian() const { return m_te_pass_spread_median; }

   // ── F-AUDIT 2026-06: TE-side T/N/S counter getters ──────────────
   int      RejTime()          const { return m_te_rej_time;     }
   int      PassTime()         const { return m_te_pass_time;    }
   int      RejNews()          const { return m_te_rej_news;     }
   int      PassNews()         const { return m_te_pass_news;    }
   int      RejSpread()        const { return m_te_rej_spread;   }
   int      PassSpread()       const { return m_te_pass_spread;  }

   // ── DPI Histogram Exit: state setter & stats getter ──────────────
   // Called once per bar from main EA before EvaluateTM(), so CheckDPIHistogramExit()
   // uses the current DPI state computed by CSignalEngine.
   void SetDPIHistogramState(double current, int trend, bool decelerating, bool green_present)
   {
      m_dpi_hist_current      = current;
      m_dpi_hist_trend        = trend;
      m_dpi_hist_decelerating = decelerating;
      m_dpi_hist_green_present = green_present;
   }
   int ExitsDpiHist() const { return m_exits_dpi_hist; }

   // BUG FIX: Public wrapper so OrchestrateInit() can restore g_consecutive_losses from history
   int GetConsecutiveLossesToday() { return CountConsecutiveLossesToday(); }

   void UpdateChartMarkers()
   {
      datetime current_bar = iTime(m_symbol, PERIOD_CURRENT, 0);
      if(current_bar == m_last_marker_update) return;
      m_last_marker_update = current_bar;

      RemoveAllMarkers();

      if(m_settings.ShowSwingMarkers)
         DrawSwingMarkers();
      if(m_settings.ShowFractalMarkers)
         DrawFractalMarkers();
   }

   void RemoveAllMarkers()
   {
      ObjectsDeleteAll(0, "SwingSL_");
      ObjectsDeleteAll(0, "FractalSL_");
      ObjectsDeleteAll(0, "SwingLabel_");
      ObjectsDeleteAll(0, "FractalLabel_");
   }

   int CooldownBarsRemaining() const
   {
      if(m_settings.MinBarsAfterClose <= 0 || m_last_close_bar == 0) return 0;
      int bars_since = Bars(m_symbol, PERIOD_CURRENT, m_last_close_bar, iTime(m_symbol, PERIOD_CURRENT, 0));
      int remaining = m_settings.MinBarsAfterClose - bars_since;
      return (remaining > 0) ? remaining : 0;
   }

   void Init(ulong magic, ST_Settings &sets) {
      m_magic = magic;
      m_symbol = _Symbol;
      m_settings = sets;
      m_last_marker_update = 0;
      m_trade.SetExpertMagicNumber(m_magic);
      m_trade.SetDeviationInPoints(10);
      m_trade.SetTypeFilling(ORDER_FILLING_IOC);
      m_trade.LogLevel(LOG_LEVEL_ERRORS);
      
      ReleaseHandles();
      // FIX Bug4: use m_symbol instead of _Symbol for multi-symbol correctness
      m_h_psar = iSAR(m_symbol, PERIOD_CURRENT, m_settings.P_PsarStep, m_settings.P_PsarMax);
      m_h_fractals = iFractals(m_symbol, PERIOD_CURRENT);
      m_h_cushion_atr = iATR(m_symbol, PERIOD_CURRENT, MathMax(1, m_settings.PSAR_TrailCushionAtrPeriod));
      m_h_sl_atr = iATR(m_symbol, PERIOD_CURRENT, MathMax(1, m_settings.SL_AtrPeriod));
      m_h_trail_ema_atr = iATR(m_symbol, PERIOD_CURRENT, MathMax(1, m_settings.TrailEMA_CushionAtrPeriod > 0 ? m_settings.TrailEMA_CushionAtrPeriod : 14));
   }
   
   void UpdateSettings(ST_Settings &sets) { 
      bool recreate_psar = (m_settings.P_PsarStep != sets.P_PsarStep || m_settings.P_PsarMax != sets.P_PsarMax);
      bool recreate_atr  = (m_settings.PSAR_TrailCushionAtrPeriod != sets.PSAR_TrailCushionAtrPeriod) || (m_h_cushion_atr == INVALID_HANDLE);
      bool recreate_sl_atr     = (m_settings.SL_AtrPeriod != sets.SL_AtrPeriod) || (m_h_sl_atr == INVALID_HANDLE);
      bool recreate_trail_ema_atr = (m_settings.TrailEMA_CushionAtrPeriod != sets.TrailEMA_CushionAtrPeriod) || (m_h_trail_ema_atr == INVALID_HANDLE);
      m_settings = sets; 
      if (recreate_psar) {
         if (m_h_psar != INVALID_HANDLE) IndicatorRelease(m_h_psar);
         // FIX Bug4: use m_symbol instead of _Symbol for multi-symbol correctness
         m_h_psar = iSAR(m_symbol, PERIOD_CURRENT, m_settings.P_PsarStep, m_settings.P_PsarMax);
      }
      if (recreate_atr) {
         if (m_h_cushion_atr != INVALID_HANDLE) IndicatorRelease(m_h_cushion_atr);
         m_h_cushion_atr = iATR(m_symbol, PERIOD_CURRENT, MathMax(1, m_settings.PSAR_TrailCushionAtrPeriod));
      }
      if (recreate_sl_atr) {
         if (m_h_sl_atr != INVALID_HANDLE) IndicatorRelease(m_h_sl_atr);
         m_h_sl_atr = iATR(m_symbol, PERIOD_CURRENT, MathMax(1, m_settings.SL_AtrPeriod));
      }
      if (recreate_trail_ema_atr) {
         if (m_h_trail_ema_atr != INVALID_HANDLE) IndicatorRelease(m_h_trail_ema_atr);
         int ema_atr_p = MathMax(1, m_settings.TrailEMA_CushionAtrPeriod > 0 ? m_settings.TrailEMA_CushionAtrPeriod : 14);
         m_h_trail_ema_atr = iATR(m_symbol, PERIOD_CURRENT, ema_atr_p);
      }
   }

   string GetPositionSnapshot() {
      for(int i = PositionsTotal() - 1; i >= 0; i--) {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(PositionGetInteger(POSITION_MAGIC) != (long)m_magic) continue;
         if(PositionGetString(POSITION_SYMBOL) != m_symbol) continue;
         
         ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         double entry = PositionGetDouble(POSITION_PRICE_OPEN);
         double current = PositionGetDouble(POSITION_PRICE_CURRENT);
         double sl = PositionGetDouble(POSITION_SL);
         double tp = PositionGetDouble(POSITION_TP);
         double lots = PositionGetDouble(POSITION_VOLUME);
         double profit = PositionGetDouble(POSITION_PROFIT);
         double swap = PositionGetDouble(POSITION_SWAP);

         double pipSize = GetPipSize();
         double sl_pips = (sl > 0.0) ? MathAbs(entry - sl) / pipSize : 0.0;
         double tp_pips = (tp > 0.0) ? MathAbs(tp - entry) / pipSize : 0.0;
         double rr_ratio = (sl_pips > 0.0 && tp_pips > 0.0) ? (tp_pips / sl_pips) : 0.0;

         double risk_amount = 0.0;
         if(sl > 0.0) {
            double stop_dist = MathAbs(entry - sl);
            double tick_size = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
            double tick_value = ResolveTickValue();
            if(tick_size > 0.0 && tick_value > 0.0) risk_amount = (stop_dist / tick_size) * tick_value * lots;
         }

         double equity = AccountInfoDouble(ACCOUNT_EQUITY);
         double free_margin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
         double margin_used = AccountInfoDouble(ACCOUNT_MARGIN);
         double margin_pct = (equity > 0.0 && margin_used > 0.0) ? (margin_used / equity * 100.0) : 0.0;

         double risk_pct = (equity > 0.0 && risk_amount > 0.0) ? (risk_amount / equity * 100.0) : 0.0;
         double pnl_pct = (equity > 0.0) ? (profit / equity * 100.0) : 0.0;
         double pnl_pips = (type == POSITION_TYPE_BUY) ? (current - entry) / pipSize : (entry - current) / pipSize;
         double r_multiple = (risk_amount > 0.0) ? (profit / risk_amount) : 0.0;
         double net_pnl = profit + swap;

         datetime entry_time = (datetime)PositionGetInteger(POSITION_TIME);
         int seconds = (int)(TimeCurrent() - entry_time);
         int hours = seconds / 3600;
         int minutes = (seconds % 3600) / 60;
         string duration = StringFormat("%dh %dm", hours, minutes);

         string dir_str = (type == POSITION_TYPE_BUY) ? "BUY" : "SELL";
         string ccy = AccountInfoString(ACCOUNT_CURRENCY);
         
         string snap = StringFormat("%s  %.2f lots  Entry=%.5f  Now=%.5f\n", dir_str, lots, entry, current);
         snap += StringFormat("SL=%.5f (%.1f pips)  TP=%.5f (%.1f pips)  RR=%.2f\n", sl, sl_pips, tp, tp_pips, rr_ratio);
         snap += StringFormat("P&L: %s%.2f (%.2f%%)  %.1f pips  %.2fR\n", ccy, profit, pnl_pct, pnl_pips, r_multiple);
         snap += StringFormat("Risk: %s%.2f (%.2f%%)  BE=%s  Trail=%s\n", ccy, risk_amount, risk_pct, m_excursion.be_reached ? "YES" : "NO", m_excursion.trail_active ? m_excursion.trail_type : "OFF");
         snap += StringFormat("MAE=%.1f pips  MFE=%.1f pips  Duration=%s\n", m_excursion.mae_pips, m_excursion.mfe_pips, duration);
         snap += StringFormat("Equity=%s%.2f  Free=%s%.2f  Margin=%.1f%%\n", ccy, equity, ccy, free_margin, margin_pct);
         if(swap != 0.0) snap += StringFormat("Swap=%s%.2f  Net=%s%.2f", ccy, swap, ccy, net_pnl);
         return snap;
      }
      return "Position: FLAT";
   }

   double CalculateActiveRisk() {
      double total_risk = 0.0;
      for(int i = PositionsTotal() - 1; i >= 0; i--) {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
         if(PositionGetString(POSITION_SYMBOL) != m_symbol || PositionGetInteger(POSITION_MAGIC) != (long)m_magic) continue;
         if(m_settings.CountBEasZeroRisk && !m_settings.Safety_CountBEInAggregateRisk
            && IsPositionAtBreakEven(ticket)) continue;
         total_risk += CalculatePositionRisk(ticket);
      }
      return total_risk;
   }

   bool IsPositionAtBreakEven(ulong ticket) {
      if(!PositionSelectByTicket(ticket)) return false;
      double sl = PositionGetDouble(POSITION_SL);
      double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
      // BUG FIX: Use RRM_BE_BufferPips + 2.0 tolerance instead of hardcoded 2.0 pips
      double tolerance_pips = m_settings.RRM_BE_BufferPips + 2.0;
      return (sl != 0.0 && MathAbs(sl - open_price) <= tolerance_pips * GetPipSize());
   }

   // Stricter than IsPositionAtBreakEven: returns true only when the position's
   // stop-loss has been moved to break-even OR into profit — i.e. the position can
   // no longer produce a loss. Used by the staged-risk entry gate so that a new
   // position is only added once every existing position is genuinely risk-free.
   // A small tolerance allows for spread/rounding at the exact BE point.
   bool IsPositionSLatBEorBetter(ulong ticket) {
      if(!PositionSelectByTicket(ticket)) return false;
      double sl = PositionGetDouble(POSITION_SL);
      if(sl == 0.0) return false;   // no stop set → full risk → not protected
      double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
      ENUM_POSITION_TYPE ptype = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double tol = 2.0 * GetPipSize();   // allow SL a couple pips below/above exact BE
      if(ptype == POSITION_TYPE_BUY)
         return (sl >= open_price - tol);   // SL at/above entry (minus tiny tolerance)
      else
         return (sl <= open_price + tol);   // SL at/below entry (plus tiny tolerance)
   }

   double CalculatePositionRisk(ulong ticket) {
      if(!PositionSelectByTicket(ticket)) return 0.0;
      double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl = PositionGetDouble(POSITION_SL);
      double volume = PositionGetDouble(POSITION_VOLUME);
      if(sl == 0.0) return 0.0;

      double stop_dist = MathAbs(open_price - sl);
      double tick_size = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
      double tick_value = ResolveTickValue();
      if(tick_size == 0.0 || tick_value == 0.0) return 0.0;
      
      double account_equity = AccountInfoDouble(ACCOUNT_EQUITY);
      if(account_equity == 0.0) return 0.0;
      return (((stop_dist / tick_size) * tick_value * volume) / account_equity) * 100.0;
   }

   double ComputeRiskPercent(double volume, double stop_dist) {
      if(volume <= 0.0 || stop_dist <= 0.0) return 0.0;

      double tick_size = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
      double tick_value = ResolveTickValue();
      if(tick_size <= 0.0 || tick_value <= 0.0) return 0.0;

      double account_equity = AccountInfoDouble(ACCOUNT_EQUITY);
      if(account_equity <= 0.0) return 0.0;

      double risk_money = (stop_dist / tick_size) * tick_value * volume;
      if(risk_money <= 0.0) return 0.0;
      return (risk_money / account_equity) * 100.0;
   }

   ulong FindPositionByMagic(ulong magic) const {
      for(int i = PositionsTotal() - 1; i >= 0; i--) {
         ulong ticket = PositionGetTicket(i);
         if(ticket > 0 && PositionGetString(POSITION_SYMBOL) == m_symbol && (ulong)PositionGetInteger(POSITION_MAGIC) == magic) {
            return ticket;
         }
      }
      return 0;
   }

   double GetActiveLots(ulong magic) {
      ulong ticket = FindPositionByMagic(magic);
      if(ticket > 0 && PositionSelectByTicket(ticket)) return PositionGetDouble(POSITION_VOLUME);
      return 0.0;
   }

   double GetActiveSLPrice(ulong magic) {
      ulong ticket = FindPositionByMagic(magic);
      if(ticket > 0 && PositionSelectByTicket(ticket)) return PositionGetDouble(POSITION_SL);
      return 0.0;
   }

   double GetActiveTPPrice(ulong magic) {
      ulong ticket = FindPositionByMagic(magic);
      if(ticket > 0 && PositionSelectByTicket(ticket)) return PositionGetDouble(POSITION_TP);
      return 0.0;
   }

   double GetActiveSLPips(ulong magic) {
      ulong ticket = FindPositionByMagic(magic);
      if(ticket > 0 && PositionSelectByTicket(ticket)) {
         double sl = PositionGetDouble(POSITION_SL);
         if(sl == 0.0) return 0.0;
         double open = PositionGetDouble(POSITION_PRICE_OPEN);
         return MathAbs(open - sl) / GetPipSize();
      }
      return 0.0;
   }

   // Initial (entry) SL in pips — never changes after entry
   double GetInitialSLPips(ulong magic) {
      ulong ticket = FindPositionByMagic(magic);
      if(ticket > 0 && PositionSelectByTicket(ticket) && m_initial_sl_price > 0.0) {
         double open = PositionGetDouble(POSITION_PRICE_OPEN);
         return MathAbs(open - m_initial_sl_price) / GetPipSize();
      }
      return 0.0;
   }

   double GetActiveTPPips(ulong magic) {
      ulong ticket = FindPositionByMagic(magic);
      if(ticket > 0 && PositionSelectByTicket(ticket)) {
         double tp = PositionGetDouble(POSITION_TP);
         if(tp == 0.0) return 0.0;
         double open = PositionGetDouble(POSITION_PRICE_OPEN);
         return MathAbs(tp - open) / GetPipSize();
      }
      return 0.0;
   }

   double GetActiveRiskMoney(ulong magic) {
      ulong ticket = FindPositionByMagic(magic);
      if(ticket > 0 && PositionSelectByTicket(ticket)) {
         double sl = PositionGetDouble(POSITION_SL);
         if(sl == 0.0) return 0.0;
         double open = PositionGetDouble(POSITION_PRICE_OPEN);
         double volume = PositionGetDouble(POSITION_VOLUME);
         double tick_size = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
         double tick_value = ResolveTickValue();
         if(tick_size > 0.0 && tick_value > 0.0) {
            return (MathAbs(open - sl) / tick_size) * tick_value * volume;
         }
      }
      return 0.0;
   }

   // Initial (entry) risk in $ — based on original SL, not current trailed SL
   double GetInitialRiskMoney(ulong magic) {
      ulong ticket = FindPositionByMagic(magic);
      if(ticket > 0 && PositionSelectByTicket(ticket) && m_initial_sl_price > 0.0) {
         double open       = PositionGetDouble(POSITION_PRICE_OPEN);
         double volume     = PositionGetDouble(POSITION_VOLUME);
         double tick_size  = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
         double tick_value = ResolveTickValue();
         if(tick_size > 0.0 && tick_value > 0.0)
            return (MathAbs(open - m_initial_sl_price) / tick_size) * tick_value * volume;
      }
      return 0.0;
   }

   double GetActiveRewardMoney(ulong magic) {
      ulong ticket = FindPositionByMagic(magic);
      if(ticket > 0 && PositionSelectByTicket(ticket)) {
         double tp = PositionGetDouble(POSITION_TP);
         if(tp == 0.0) return 0.0;
         double open = PositionGetDouble(POSITION_PRICE_OPEN);
         double volume = PositionGetDouble(POSITION_VOLUME);
         double tick_size = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
         double tick_value = ResolveTickValue();
         if(tick_size > 0.0 && tick_value > 0.0) {
            return (MathAbs(tp - open) / tick_size) * tick_value * volume;
         }
      }
      return 0.0;
   }

   // Current risk % of equity based on current (possibly trailed) SL
   double GetCurrentRiskPct(ulong magic) {
      ulong ticket = FindPositionByMagic(magic);
      if(ticket > 0 && PositionSelectByTicket(ticket)) {
         double sl         = PositionGetDouble(POSITION_SL);
         double open       = PositionGetDouble(POSITION_PRICE_OPEN);
         double volume     = PositionGetDouble(POSITION_VOLUME);
         double equity     = AccountInfoDouble(ACCOUNT_EQUITY);
         double tick_size  = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
         double tick_value = ResolveTickValue();
         if(sl > 0.0 && tick_size > 0.0 && tick_value > 0.0 && equity > 0.0)
            return ((MathAbs(open - sl) / tick_size) * tick_value * volume / equity) * 100.0;
      }
      return 0.0;
   }

   // Current risk in $ based on current (possibly trailed) SL
   double GetCurrentRiskMoney(ulong magic) {
      ulong ticket = FindPositionByMagic(magic);
      if(ticket > 0 && PositionSelectByTicket(ticket)) {
         double sl         = PositionGetDouble(POSITION_SL);
         double open       = PositionGetDouble(POSITION_PRICE_OPEN);
         double volume     = PositionGetDouble(POSITION_VOLUME);
         double tick_size  = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
         double tick_value = ResolveTickValue();
         if(sl > 0.0 && tick_size > 0.0 && tick_value > 0.0)
            return (MathAbs(open - sl) / tick_size) * tick_value * volume;
      }
      return 0.0;
   }

   double GetCurrentRR(ulong magic) {
      ulong ticket = FindPositionByMagic(magic);
      if(ticket > 0 && PositionSelectByTicket(ticket)) {
         double profit = PositionGetDouble(POSITION_PROFIT);
         double risk_money = GetActiveRiskMoney(magic);
         if(risk_money > 0.0) return profit / risk_money;
      }
      return 0.0;
   }

   double GetStopLossPips(int direction) {
      bool isBuy = (direction > 0);
      double price = isBuy ? SymbolInfoDouble(m_symbol, SYMBOL_ASK) : SymbolInfoDouble(m_symbol, SYMBOL_BID);
      double sl = CalcEntrySL(isBuy, price);
      return (sl > 0.0) ? MathAbs(price - sl) / GetPipSize() : 0.0;
   }

   double GetTakeProfitPips(int direction, double actual_sl_price) {
      double tp_pips = 0.0;
      double ref_price = iClose(m_symbol, PERIOD_CURRENT, 1);
      switch(m_settings.TPMode) {
         case TP_MODE_FIXED_PIPS: 
            tp_pips = m_settings.FixedTPPips; 
            break;
         case TP_MODE_RR: {
            double sl_pips = (actual_sl_price > 0.0 && ref_price > 0.0)
                             ? MathAbs(ref_price - actual_sl_price) / GetPipSize()
                             : 0.0;
            if(sl_pips > 0.0 && m_settings.RRRatio > 0.0)
               tp_pips = sl_pips * m_settings.RRRatio;
            else {
               PrintFormat("⚠️ [TP_RR] Cannot compute TP: actual_sl=%.5f ref=%.5f RR=%.2f — TP=0.", actual_sl_price, ref_price, m_settings.RRRatio);
               tp_pips = 0.0;
            }
            break;
         }
         case TP_MODE_FRACTAL: {
            tp_pips = GetFractalTP(direction);
            if(tp_pips <= 0.0) {
               double sl_pips = (actual_sl_price > 0.0 && ref_price > 0.0)
                                ? MathAbs(ref_price - actual_sl_price) / GetPipSize()
                                : 0.0;
               tp_pips = (sl_pips > 0.0 && m_settings.RRRatio > 0.0) ? sl_pips * m_settings.RRRatio : 0.0;
            }
            break;
         }
         case TP_MODE_PSAR_FLIP:
         case TP_MODE_NONE: 
            tp_pips = 0.0; 
            break;
         default: 
            tp_pips = m_settings.FixedTPPips; 
            break;
      }
      return tp_pips;
   }

   //+------------------------------------------------------------------+
   //| EvaluateCM - CAPITAL MANAGEMENT (Position Sizing + SL Geometry)  |
   //| Returns: lots > 0 = pass, 0 = veto                               |
   //|                                                                  |
   //| RC VETO EVALUATION (see EvaluateRC):                             |
   //|   • RC_VETO_SL_ZERO (HARDCODED - SL calculation failed)          |
   //|   • RC_VETO_SL_TOO_WIDE (threshold: Inp_Risk_MaxSlPips)          |
   //|   • RC_VETO_MARGIN (HARDCODED - insufficient margin)             |
   //|   • RC_VETO_RISK_PCT (threshold: Inp_Risk_RiskPercent)           |
   //|   • RC_VETO_DRAWDOWN_PROTECTION (thresholds: Max losses/trades)  |
   //|   • RC_VETO_SAME_BAR (HARDCODED - duplicate-entry protection)    |
   //|                                                                  |
   //| NOTE: RC safeguards cannot be disabled; users adjust thresholds. |
   //+------------------------------------------------------------------+
   double EvaluateCM(int direction) {
      if(direction == 0) return 0.0;
      bool isBuy = (direction == 1);
      // SL geometry and lot sizing anchored to bar-N close price (same data TS=1 was confirmed on)
      double ref_price = iClose(m_symbol, PERIOD_CURRENT, 1);
      double sl = CalcEntrySL(isBuy, ref_price);
      if(sl <= 0.0) {
         PrintFormat("[CM VETO] SL=0 returned by CalcEntrySL for %s dir=%s — SL mode=%s — trade blocked",
                     m_symbol, isBuy ? "BUY" : "SELL", EnumToString(m_settings.SLMode));
         m_cached_sl   = 0.0;
         m_cached_lots = 0.0;
         m_cached_risk = 0.0;
         return 0.0;  // triggers VETO_INVALID_LOTS in EvaluateTE
      }
      
      double lot = NormalizeVolume(SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN));
      if(m_settings.UseMACompatSizer) {
         double ma_lot = CalcLotMACompat();
         if(ma_lot > 0.0) lot = ma_lot;
      } else {
         double risk_lot = CalcLotByRisk(ref_price, sl);
         if(risk_lot > 0.0) lot = risk_lot;
      }

      // Margin adjustment uses live price — margin is a live broker value (correct)
      ENUM_ORDER_TYPE order_type = isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      double live_price = isBuy ? SymbolInfoDouble(m_symbol, SYMBOL_ASK) : SymbolInfoDouble(m_symbol, SYMBOL_BID);
      m_cached_sl   = sl;   // store historical-anchor SL for pre-check diagnostics; NOT used as placed SL (see ExecuteTrade Fix 3)
      double adjusted_lots = AdjustLotForMargin(order_type, lot, live_price);
      m_cached_lots = adjusted_lots;
      m_cached_risk = ComputeRiskPercent(adjusted_lots, MathAbs(ref_price - sl));
      return adjusted_lots;
   }

   //+------------------------------------------------------------------+
   //| EvaluateRC - RISK CONTROL Veto Gates                             |
   //| Returns: true = pass, false = veto                               |
   //|                                                                  |
   //| RC vetoes here combine hardcoded safeguards with user thresholds |
   //| from Inp_Risk_* and Inp_RRM_* controls.                          |
   //| Hardcoded safeguards remain always active for capital protection.|
   //+------------------------------------------------------------------+
   bool EvaluateRC(int direction, double lots) {
      m_rc_veto_reason = "";
      bool isBuy = (direction > 0);
      double live_price = isBuy ? SymbolInfoDouble(m_symbol, SYMBOL_ASK) : SymbolInfoDouble(m_symbol, SYMBOL_BID);

      if(m_settings.MinMarginLevel > 0.0) {
         ENUM_ORDER_TYPE order_type = isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
         double new_trade_margin = 0.0;
         double current_margin = AccountInfoDouble(ACCOUNT_MARGIN);
         double equity = AccountInfoDouble(ACCOUNT_EQUITY);
         if(equity <= 0.0) equity = AccountInfoDouble(ACCOUNT_BALANCE);
         if(OrderCalcMargin(order_type, m_symbol, lots, live_price, new_trade_margin) && new_trade_margin > 0.0) {
            double projected_margin = current_margin + new_trade_margin;
            double projected_level = (projected_margin > 0.0) ? (equity / projected_margin * 100.0) : SEA_MARGIN_LEVEL_UNLIMITED;
            double margin_adj = GetMarginLevelAdjustment();
            double adjusted_threshold = m_settings.MinMarginLevel * margin_adj;
            if(projected_level < adjusted_threshold) {
               PrintFormat("🚫 [RC] VETO_RC_MARGIN_LEVEL: Projected %.1f%% < Adjusted threshold %.1f%% (base=%.1f%% × %.2f instrument adj) [%s]",
                           projected_level, adjusted_threshold, m_settings.MinMarginLevel, margin_adj, _Symbol);
               m_rc_veto_reason = "VETO_RC_MARGIN_LEVEL";
               return false;
            }
         }
      }

      if(m_settings.MaxOpenTrades > 0) {
         int open_count = 0;
         for(int i = PositionsTotal() - 1; i >= 0; i--) {
            ulong ticket = PositionGetTicket(i);
            if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
            if(PositionGetString(POSITION_SYMBOL) != m_symbol || PositionGetInteger(POSITION_MAGIC) != (long)m_magic) continue;
            open_count++;
         }
         if(open_count >= m_settings.MaxOpenTrades) {
            PrintFormat("🚫 [RC] Open trades %d >= MaxOpenTrades %d -- trade blocked", open_count, m_settings.MaxOpenTrades);
            m_rc_veto_reason = "VETO_RC_MAX_OPEN_TRADES";
            return false;
         }
      }

      // SAFETY: cap concurrent positions per direction (limits correlated stacked risk).
      if(m_settings.Safety_MaxPositionsPerDir > 0) {
         int buy_count = 0, sell_count = 0;
         CountMyPositions(buy_count, sell_count);
         int dir_count = isBuy ? buy_count : sell_count;
         if(dir_count >= m_settings.Safety_MaxPositionsPerDir) {
            PrintFormat("🚫 [SAFETY] %s positions %d >= MaxPositionsPerDir %d -- trade blocked",
                        isBuy ? "LONG" : "SHORT", dir_count, m_settings.Safety_MaxPositionsPerDir);
            m_rc_veto_reason = "VETO_SAFETY_MAX_PER_DIR";
            return false;
         }
      }

      // SAFETY: staged-risk gate. Enforces the intended model where a new position
      // may only be added once EVERY existing same-symbol position is already at
      // break-even or better (i.e. risk-free). This guarantees at most ONE position
      // carries live risk at any time, so concurrent open trades cannot compound a
      // loss beyond the single newest position's risk. Works regardless of BE_Mode
      // configuration because it inspects actual placed stops, not internal flags.
      if(m_settings.Safety_RequirePriorAtBEToAdd) {
         for(int i = PositionsTotal() - 1; i >= 0; i--) {
            ulong tk = PositionGetTicket(i);
            if(tk == 0 || !PositionSelectByTicket(tk)) continue;
            if(PositionGetString(POSITION_SYMBOL) != m_symbol || PositionGetInteger(POSITION_MAGIC) != (long)m_magic) continue;
            if(!IsPositionSLatBEorBetter(tk)) {
               PrintFormat("🚫 [SAFETY] Staged-risk gate: position #%I64u not yet at BE+ — new entry blocked", tk);
               m_rc_veto_reason = "VETO_SAFETY_PRIOR_NOT_BE";
               return false;
            }
         }
      }
      if(m_settings.MaxTotalRisk > 0.0) {
         // Reuse m_cached_sl and m_cached_risk computed by EvaluateCM — avoids independent
         // CalcEntrySL() re-computation that could differ due to indicator-state or floating-point
         // variance, causing false-positive MaxTotalRisk blocks (Issue C fix).
         if(m_cached_sl <= 0.0) {
            PrintFormat("⚠️ [RC] m_cached_sl=0 — skipping MaxTotalRisk pre-check, ExecuteTrade will validate SL");
         }
         else
         {
            double new_trade_risk = m_cached_risk;   // already computed in EvaluateCM
            // +1e-6 epsilon (0.0001% in percentage terms) prevents a false block when the
            // user sets RiskPercent == MaxTotalRisk (e.g. both at 2.0%) and floating-point
            // rounding causes the computed risk to exceed the limit by a sub-micropercentage.
            if(CalculateActiveRisk() + new_trade_risk > m_settings.MaxTotalRisk + 1e-6) {
               PrintFormat("🚫 [RC] Active risk %.4f%% + new trade risk %.4f%% > MaxTotalRisk %.4f%% -- trade blocked",
                           CalculateActiveRisk(), new_trade_risk, m_settings.MaxTotalRisk);
               m_rc_veto_reason = "VETO_RC_MAX_TOTAL_RISK";
               return false;
            }
         }
      }
      return true;
   }

   void ExecuteTrade(int direction, double lots) {
      bool is_reentry = false;  // Set true when entering alongside an existing BE position
      if(lots <= 0.0) {
         m_last_te_time = iTime(m_symbol, PERIOD_CURRENT, 0); m_last_te_result = "BLOCKED"; return;
      }
      if(m_last_trade_bar == iTime(m_symbol, PERIOD_CURRENT, 0)) {
         m_last_te_time = iTime(m_symbol, PERIOD_CURRENT, 0); m_last_te_result = "BLOCKED"; m_last_te_reason = "SAME_BAR_ENTRY"; return;
      }
      if(m_last_close_bar == iTime(m_symbol, PERIOD_CURRENT, 0)) {
         m_last_te_time = iTime(m_symbol, PERIOD_CURRENT, 0); m_last_te_result = "BLOCKED"; m_last_te_reason = "SAME_BAR_CLOSE"; return;
      }
      if(m_settings.MinBarsAfterClose > 0 && m_last_close_bar > 0)
      {
         int bars_since = Bars(m_symbol, PERIOD_CURRENT, m_last_close_bar, iTime(m_symbol, PERIOD_CURRENT, 0));
         if(bars_since < m_settings.MinBarsAfterClose)
         {
            m_last_te_time   = iTime(m_symbol, PERIOD_CURRENT, 0);
            m_last_te_result = "BLOCKED";
            m_last_te_reason = StringFormat("POST_TRADE_COOLDOWN_%d/%d", bars_since, m_settings.MinBarsAfterClose);
            return;
         }
      }
   
      int buy_count=0, sell_count=0;
      CountMyPositions(buy_count, sell_count);
   
      if((direction == 1 && buy_count > 0 && sell_count == 0) || (direction == -1 && sell_count > 0 && buy_count == 0)) {
         if(m_settings.AllowReEntryAfterBE) {
            ulong ticket = GetMyPosition();
            if(ticket > 0 && IsPositionAtBreakEven(ticket)) {
               is_reentry = true;  // Mark: pyramid entry alongside a BE position
               // Fall through: allow new entry alongside existing BE position
            } else {
               m_last_te_time = iTime(m_symbol, PERIOD_CURRENT, 0); m_last_te_result = "BLOCKED"; m_last_te_reason = "ALREADY_IN_POSITION"; return;
            }
         } else {
            m_last_te_time = iTime(m_symbol, PERIOD_CURRENT, 0); m_last_te_result = "BLOCKED"; m_last_te_reason = "ALREADY_IN_POSITION"; return;
         }
      }
   
      if((buy_count + sell_count) > 0) {
         if(direction != 0 && m_settings.CloseOnReverse) {
            CloseAllMyPositions();
            m_last_trade_bar = iTime(m_symbol, PERIOD_CURRENT, 0);
            if(m_settings.MABenchmarkStrict) { m_last_te_time = iTime(m_symbol, PERIOD_CURRENT, 0); m_last_te_result = "BLOCKED"; return; }
         } else {
            m_last_te_time = iTime(m_symbol, PERIOD_CURRENT, 0); m_last_te_result = "BLOCKED"; return;
         }
      }
   
      if(direction == 0) return;
      bool isBuy = (direction == 1);
      double entry_price = isBuy ? SymbolInfoDouble(m_symbol, SYMBOL_ASK) : SymbolInfoDouble(m_symbol, SYMBOL_BID);
      double sl = 0, tp = 0;

      // Compute SL fresh from actual entry price at TE time (Fix 3: not cached historical anchor).
      // This ensures PSAR/swing SL distance is correct relative to the actual entry price,
      // not the signal bar close price from the previous bar.
      // m_cached_sl (from EvaluateCM) is preserved for display/pre-check purposes only.
      sl = CalcEntrySL(isBuy, entry_price);
      if(sl == 0.0) {
         Print("🚫 [ExecuteTrade] SL is zero after anchor + widen — trade blocked");
         m_last_te_time = iTime(m_symbol, PERIOD_CURRENT, 0);
         m_last_te_result = "BLOCKED";
         m_last_te_reason = "SL_ZERO";
         return;
      }

      // Recalculate lots from the freshly computed SL and actual entry price.
      // Since SL is now computed at TE time from actual entry price (not from cached bar-close anchor),
      // we always recalculate here to ensure lot sizing matches the placed SL.
      if(!m_settings.UseMACompatSizer && sl > 0.0)
      {
         double recalc_lots = CalcLotByRisk(entry_price, sl);
         if(recalc_lots > 0.0)
         {
            PrintFormat("📊 [ExecuteTrade] Lots from fresh SL (%.5f): %.4f→%.4f",
                        sl, lots, recalc_lots);
            lots = recalc_lots;
            // Re-apply margin safety with the new lot size
            lots = AdjustLotForMargin(isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, lots, entry_price);
            // FIX Bug1: update cached lots/risk to reflect final value sent to broker
            m_cached_lots = lots;
            m_cached_risk = ComputeRiskPercent(lots, MathAbs(entry_price - sl));
         }
      }

      // ── RE-ENTRY LOT SCALING ────────────────────────────────────────────
      // When entering alongside an existing BE position (pyramid), scale lot size down.
      // Original position is at breakeven — its risk is zero. Scaling the new entry to
      // 50% (default) keeps total new risk controlled. 0 = full size (disabled).
      if(is_reentry && m_settings.ReEntryLotScalePct > 0 && m_settings.ReEntryLotScalePct < 100) {
         double scale = m_settings.ReEntryLotScalePct / 100.0;
         double scaled_lots = NormalizeDouble(lots * scale, 2);
         double min_lot = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
         if(scaled_lots >= min_lot) {
            PrintFormat("📊 [RE-ENTRY] Lot scaling: %.4f × %d%% = %.4f (original at BE, total risk controlled)",
                        lots, m_settings.ReEntryLotScalePct, scaled_lots);
            lots = scaled_lots;
            m_cached_lots = lots;
            m_cached_risk = ComputeRiskPercent(lots, MathAbs(entry_price - sl));
         } else {
            PrintFormat("⚠️ [RE-ENTRY] Scaled lots %.4f < min lot %.4f — using min lot", scaled_lots, min_lot);
            lots = min_lot;
            m_cached_lots = lots;
            m_cached_risk = ComputeRiskPercent(lots, MathAbs(entry_price - sl));
         }
      }

      if(m_settings.ExitProfile == EXIT_PROFILE_RRM) {
         tp = RRM_GetStrictTP(isBuy, entry_price, sl);
      } else {
         if(m_settings.TPMode == TP_MODE_NONE || m_settings.TPMode == TP_MODE_PSAR_FLIP) {
            tp = 0.0;
         } else if(m_settings.TPMode == TP_MODE_FRACTAL) {
            double tp_pips = GetFractalTP(direction == 1 ? 1 : -1);
            if(tp_pips > 0.0) {
               double tp_dist = tp_pips * GetPipSize();
               tp = isBuy ? (entry_price + tp_dist) : (entry_price - tp_dist);
            } else if(sl > 0.0 && m_settings.RRRatio > 0.0) {
               double sl_dist = MathAbs(entry_price - sl);
               tp = isBuy ? (entry_price + sl_dist * m_settings.RRRatio) : (entry_price - sl_dist * m_settings.RRRatio);
            }
         } else if(m_settings.RRRatio > 0) {
            double dist = (sl > 0) ? MathAbs(entry_price - sl) * m_settings.RRRatio : m_settings.SL_FixedPips * GetPipSize() * m_settings.RRRatio;
            tp = isBuy ? entry_price + dist : entry_price - dist;
         }
      }
      
      int digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
      if(sl > 0) sl = NormalizeDouble(sl, digits);
      if(tp > 0) tp = NormalizeDouble(tp, digits);
   
      ENUM_ORDER_TYPE type = isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      string comment = StringFormat("SEA_%s", EnumToString(m_settings.SLMode));

      if(m_settings.TP_Enabled && tp == 0.0)
      {
         // FIX D3: when TP_Enabled=true but TP could not be derived, either compute from
         // SL distance × RRRatio (if both are valid) or block the trade rather than silently
         // substituting a hardcoded 2.0 RR that the user did not configure.
         if(sl > 0.0 && m_settings.RRRatio > 0.0) {
            double sl_dist      = MathAbs(entry_price - sl);
            tp = isBuy ? (entry_price + sl_dist * m_settings.RRRatio) : (entry_price - sl_dist * m_settings.RRRatio);
            PrintFormat("⚠️ [TP FALLBACK] TP was 0 — computed from SL dist (%.1f pips) × RR=%.2f → TP=%.5f",
                        sl_dist / GetPipSize(), m_settings.RRRatio, tp);
         } else {
            PrintFormat("🚫 [TP FALLBACK] TP=0 and cannot derive: sl=%.5f RRRatio=%.2f — BLOCKING TRADE",
                        sl, m_settings.RRRatio);
            m_last_te_time   = iTime(m_symbol, PERIOD_CURRENT, 0);
            m_last_te_result = "BLOCKED";
            m_last_te_reason = "TP_ZERO_NO_FALLBACK";
            return;
         }
      }

      if(!ValidateStopLevels(entry_price, sl, tp)) {
         m_last_te_time = iTime(m_symbol, PERIOD_CURRENT, 0); m_last_te_result = "BLOCKED"; return;
      }

      // ── SAFETY: minimum reward:risk gate (optional, 0 = disabled) ──
      // Rejects entries whose TP:SL geometry is unfavorable. Only applies when a
      // TP exists (tp>0); strategies that exit via trailing/PSAR-flip (tp==0)
      // have no fixed reward to measure and are intentionally exempt.
      if(m_settings.Safety_MinRewardRiskRatio > 0.0 && sl > 0.0 && tp > 0.0)
      {
         double risk_dist   = MathAbs(entry_price - sl);
         double reward_dist = MathAbs(tp - entry_price);
         if(risk_dist > 0.0)
         {
            double rr = reward_dist / risk_dist;
            if(rr < m_settings.Safety_MinRewardRiskRatio)
            {
               PrintFormat("🚫 [SAFETY] Entry blocked: R:R %.2f < min %.2f (risk=%.1f pips reward=%.1f pips)",
                           rr, m_settings.Safety_MinRewardRiskRatio,
                           risk_dist / GetPipSize(), reward_dist / GetPipSize());
               m_last_te_time   = iTime(m_symbol, PERIOD_CURRENT, 0);
               m_last_te_result = "BLOCKED";
               m_last_te_reason = "RR_BELOW_MIN";
               return;
            }
         }
      }

      if(m_trade.PositionOpen(m_symbol, type, lots, entry_price, sl, tp, comment)) {
         m_last_te_time = iTime(m_symbol, PERIOD_CURRENT, 0); m_last_te_result = "ENTERED";
         m_last_trade_bar = iTime(m_symbol, PERIOD_CURRENT, 0);
         m_initial_sl_price = sl;
         if(m_settings.ExitProfile == EXIT_PROFILE_RRM) {
            m_rrm_initial_sl = sl; m_rrm_be_reached = false; m_rrm_trail_frozen = false; m_rrm_last_ticket = 0;
         }
      } else {
         m_last_te_time = iTime(m_symbol, PERIOD_CURRENT, 0); m_last_te_result = "BLOCKED";
      }
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

   // ─────────────────────────────────────────────────────────────────────────
   // EvaluateF — Filters (TE equation factor F)
   // Checks execution-moment conditions: spread, session time, and news.
   // Called at bar open (shift=0) before placing a trade.
   // Returns 1 if all filters pass, 0 if any filter blocks execution.
   // ─────────────────────────────────────────────────────────────────────────
   int EvaluateF(bool news_blocked_override = false)
   {
      // F Gate 1: Spread check
      if(m_settings.UseSpread && m_settings.MaxSpread > 0.0)
      {
         double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
         double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
         int digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
         double pip = (digits == 3 || digits == 5) ? _Point * 10.0 : _Point;
         double spread_inst = (ask - bid) / pip;
         double spread_pips = spread_inst;

         // ── PHASE B: optional median-spread smoothing ───────────────
         // When TE_SpreadMedianTicks > 0, replace the instant spread with
         // the median of the last N ticks. Filters single-tick spikes at
         // session boundaries while still rejecting sustained widening.
         int N = m_settings.TE_SpreadMedianTicks;
         if(N > 0 && N <= 32) {
            m_spread_history[m_spread_history_idx % N] = spread_inst;
            m_spread_history_idx++;
            if(m_spread_history_count < N) m_spread_history_count++;
            if(m_spread_history_count == N) {
               // Insertion sort copy and pick median (N is small, this is cheap)
               double tmp[32];
               for(int i = 0; i < N; i++) tmp[i] = m_spread_history[i];
               for(int i = 1; i < N; i++) {
                  double key = tmp[i]; int j = i - 1;
                  while(j >= 0 && tmp[j] > key) { tmp[j+1] = tmp[j]; j--; }
                  tmp[j+1] = key;
               }
               spread_pips = (N % 2 == 1) ? tmp[N/2] : 0.5 * (tmp[N/2 - 1] + tmp[N/2]);
            }
         }

         if(spread_pips > m_settings.MaxSpread)
         {
            if(N > 0) {
               PrintFormat("[TE VETO] VETO_SPREAD_MEDIAN | median=%.1f (inst=%.1f) > MaxSpread=%.1f pips",
                           spread_pips, spread_inst, m_settings.MaxSpread);
               m_te_veto_reason = "VETO_SPREAD_MEDIAN";
               m_te_rej_spread_median++;
            } else {
               PrintFormat("[TE VETO] VETO_SPREAD | spread=%.1f pips > MaxSpread=%.1f pips", spread_pips, m_settings.MaxSpread);
               m_te_veto_reason = "VETO_SPREAD";
            }
            m_te_rej_spread++;   // F-AUDIT 2026-06: unified spread-rejection counter (was only m_te_rej_spread_median for median path)
            return 0;
         }
         m_te_pass_spread++;   // F-AUDIT 2026-06: spread filter ran and passed
      }

      // F Gate 2: Session time check
      if(m_settings.UseTime)
      {
         MqlDateTime dt;
         TimeCurrent(dt);
         bool time_pass = (m_settings.StartHr < m_settings.EndHr) ?
                          (dt.hour >= m_settings.StartHr && dt.hour < m_settings.EndHr) :
                          (dt.hour >= m_settings.StartHr || dt.hour < m_settings.EndHr);
         if(!time_pass)
         {
            PrintFormat("[TE VETO] VETO_TIME | hour=%d outside window [%d-%d]", dt.hour, m_settings.StartHr, m_settings.EndHr);
            m_te_veto_reason = "VETO_TIME";
            m_te_rej_time++;   // F-AUDIT 2026-06
            return 0;
         }
         m_te_pass_time++;   // F-AUDIT 2026-06
      }

      // F Gate 3: News check
      if(m_settings.UseNews && news_blocked_override)
      {
         Print("[TE VETO] VETO_NEWS | high-impact event active");
         m_te_veto_reason = "VETO_NEWS";
         m_te_rej_news++;   // F-AUDIT 2026-06
         return 0;
      }
      // F-AUDIT 2026-06: bump news-pass counter when filter is active AND we
      // reach here (no news block). UseNews && !news_blocked_override means
      // the news gate ran without rejecting.
      if(m_settings.UseNews) m_te_pass_news++;

      return 1;  // All execution-moment filters pass
   }

   //+------------------------------------------------------------------+
   //| EvaluateTE - Trade Entry Evaluation                              |
   //| Returns: 1 = execute, 0 = veto                                   |
   //|                                                                  |
   //| VETO EVALUATION ORDER:                                           |
   //|   1. F Filters (user-configurable via Inp_Global_VETO_*)                |
   //|      • VETO_SPREAD (Inp_Global_VETO_MaxSpread / Inp_Global_VETO_UseSpread)     |
   //|      • VETO_TIME (Inp_Global_VETO_UseTime, Inp_Global_VETO_StartHr/EndHr)      |
   //|      • VETO_NEWS (Inp_Global_VETO_UseNews, NewsPre/Post minutes)        |
   //|                                                                  |
   //|   2. TE Quality Gates (user-configurable via Inp_Global_VETO_TE_*)      |
   //|      • VETO_BC_STALE (Inp_Global_VETO_TE_RecheckBarClose)               |
   //|      • VETO_OPEN_DELAY (Inp_Global_VETO_TE_OpenDelaySeconds)            |
   //|      • VETO_SPREAD_MEDIAN (Inp_Global_VETO_TE_SpreadMedianTicks)        |
   //|                                                                  |
   //|   3. RC Safeguards / threshold gates (EvaluateCM + EvaluateRC)   |
   //|      • Hardcoded safeguards stay always active                    |
   //|      • Risk thresholds remain user-tunable via Inp_Risk_*        |
   //|                                                                  |
   //| DESIGN PRINCIPLE:                                                |
   //|   • TS=1 at shift=1 is trusted at shift=0                        |
   //|   • TE checks execution-moment veto conditions                   |
   //|   • Optional TE quality gates are OFF by default                 |
   //+------------------------------------------------------------------+
   int EvaluateTE(int direction, bool news_blocked_override = false, bool psar_recheck_blocked = false) {

      if(direction == 0) return 0;
      m_cached_sl   = 0.0;
      m_cached_lots = 0.0;
      m_cached_risk = 0.0;
      m_te_veto_reason = "OK";
      string te_reject_reason = "";

      // Log the reference prices being used for diagnostics
      bool isBuy = (direction > 0);
      double ref_price  = iClose(m_symbol, PERIOD_CURRENT, 1);
      double live_price = isBuy ? SymbolInfoDouble(m_symbol, SYMBOL_ASK) : SymbolInfoDouble(m_symbol, SYMBOL_BID);
      PrintFormat("📋 [TE] %s | ref_price(barClose)=%.5f | live_price=%.5f | spread_offset=%.5f",
                  m_symbol, ref_price, live_price, MathAbs(live_price - ref_price));

      // ── PSAR staleness gate ──
      // Re-validate PSAR direction at shift=1 of the CURRENT bar (i.e. the
      // bar that most recently closed). The TS=1 signal may have been
      // emitted N bars ago against an older shift=1; if PSAR has flipped
      // on the bar that just closed, the signal is no longer valid.
      // Caller (OnTick) computes this against Signal.Scanner_Check_PSAR_Flip()
      // or Scanner_Check_PSAR(), depending on Vote_AllowPsarFlip.
      if(psar_recheck_blocked)
      {
         PrintFormat("[TE VETO] VETO_PSAR_STALE | PSAR no longer on correct side for %s at shift=1 of current bar",
                     isBuy ? "BUY" : "SELL");
         m_te_veto_reason = "VETO_PSAR_STALE";
         m_last_te_result = "BLOCKED";
         m_last_te_reason = "VETO_PSAR_STALE";
         m_last_te_time   = iTime(m_symbol, PERIOD_CURRENT, 0);
         return 0;
      }

      // ── F: Filters (spread × session × news) ──
      int F = EvaluateF(news_blocked_override);
      if(F == 0) {
         te_reject_reason = m_te_veto_reason;
         // STEP14 2026-06: include VETO_SPREAD_MEDIAN in the retry-counter trigger.
         // Previously checked only "VETO_SPREAD"; with TE_SpreadMedianTicks > 0 the
         // gate at EvaluateF (line ~2841) emits "VETO_SPREAD_MEDIAN", which failed
         // this match and fell through to the else-branch that resets the counter
         // to 0. Result: MaxSpreadRetryBars timeout never fires for users with
         // median filter enabled — the carry can persist indefinitely waiting for
         // spread to normalize. The instant-spread path (VETO_SPREAD) was unaffected.
         if(m_te_veto_reason == "VETO_SPREAD" || m_te_veto_reason == "VETO_SPREAD_MEDIAN")
         {
            m_spread_block_bars++;
            if(m_settings.MaxSpreadRetryBars > 0 &&
               m_spread_block_bars >= m_settings.MaxSpreadRetryBars)
            {
               double pip = GlobalPipSize(m_symbol);
               double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
               double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
               double spread_pips = (pip > 0.0) ? (ask - bid) / pip : 0.0;
               PrintFormat("⚠️ [TE] VETO_SPREAD_TIMEOUT after %d bars. Killing carry. spread=%.1f > max=%.1f",
                           m_spread_block_bars, spread_pips, m_settings.MaxSpread);
               m_te_veto_reason = "VETO_SPREAD_TIMEOUT";
               te_reject_reason = "VETO_SPREAD_TIMEOUT";
               m_spread_block_bars = 0;
            }
         }
         else
         {
            m_spread_block_bars = 0;  // reset counter on any non-spread veto
         }
      }
      else
      {
         m_spread_block_bars = 0;  // reset counter when filters pass
      }

      // ══════════════════════════════════════════════════════════════
      // PHASE 2 GATE 1: Open-tick delay (TE_OpenDelaySeconds)
      // Defer TE by N seconds after a new bar opens. Bid/ask spreads
      // spike hardest at the bar boundary (esp. M1/M5 around session
      // opens). Skipping TE in the first N seconds lets the spike
      // resolve. No-op when TE_OpenDelaySeconds <= 0.
      // ══════════════════════════════════════════════════════════════
      if(te_reject_reason == "" && m_settings.TE_OpenDelaySeconds > 0) {
         datetime bar0_open = (datetime)SeriesInfoInteger(m_symbol, PERIOD_CURRENT, SERIES_LASTBAR_DATE);
         long age_sec       = (long)(TimeCurrent() - bar0_open);
         if(age_sec >= 0 && age_sec < m_settings.TE_OpenDelaySeconds) {
            m_te_veto_reason = "VETO_OPEN_DELAY";
            m_te_rej_open_delay++;
            if(m_settings.DebugFlow)
               PrintFormat("[TE] VETO_OPEN_DELAY: bar age=%d sec < %d sec required",
                           (int)age_sec, m_settings.TE_OpenDelaySeconds);
            te_reject_reason = m_te_veto_reason;
         }
      }

      // ══════════════════════════════════════════════════════════════
      // PHASE 2 GATE 2: Bar-close BC re-check (TE_RecheckBarClose)
      // The TS=1 setup was confirmed at shift=1 close. By the time TE
      // fires at shift=0, price may have drifted. Re-check that the
      // drift is within Inp_Global_VETO_TE_BC_TolerancePips.
      // ══════════════════════════════════════════════════════════════
      if(te_reject_reason == "" && m_settings.TE_RecheckBarClose) {
         double close1   = iClose(m_symbol, PERIOD_CURRENT, 1);
         double bid_now  = SymbolInfoDouble(m_symbol, SYMBOL_BID);
         double pip      = GlobalPipSize(m_symbol);
         // Drift in pips against bias direction:
         //   for LONG:  drift > 0  ⇒  bid is BELOW close1 (bad)
         //   for SHORT: drift > 0  ⇒  bid is ABOVE close1 (bad)
         double drift_pips = isBuy ? (close1 - bid_now) / pip : (bid_now - close1) / pip;
         double max_drift_pips = m_settings.TE_BC_TolerancePips;
         if(pip > 0.0 && drift_pips > max_drift_pips) {
            m_te_veto_reason = "VETO_BC_STALE";
            m_te_rej_bc_recheck++;
            if(m_settings.DebugFlow)
               PrintFormat("[TE] VETO_BC_STALE: drift=%.1f pips > %.1f (close1=%.5f bid=%.5f)",
                           drift_pips, max_drift_pips, close1, bid_now);
            te_reject_reason = m_te_veto_reason;
         }
      }

      double te_lots = 0;
      if(te_reject_reason == "") {
         te_lots = EvaluateCM(direction);
         if(te_lots <= 0) {
            te_reject_reason = "VETO_INVALID_LOTS";
            PrintFormat("[TE VETO] VETO_INVALID_LOTS | sl=%.5f invalid_lots=%.2f", m_cached_sl, te_lots);
         }
      }

      if(te_reject_reason == "") {
         if(!EvaluateRC(direction, te_lots)) {
            te_reject_reason = m_rc_veto_reason;
            PrintFormat("[TE VETO] %s | lots=%.2f risk=%.2f%%", te_reject_reason, te_lots, m_cached_risk);
         }
      }

      int result = 0;
      if(te_reject_reason == "") {
         ExecuteTrade(direction, te_lots);
         result = (m_last_te_result == "ENTERED") ? 1 : 0;
         if(result == 0) te_reject_reason = m_last_te_reason;
      }

      m_te_veto_reason = (te_reject_reason == "") ? "OK" : te_reject_reason;
      if(te_reject_reason != "" && m_last_te_result != "ENTERED") {
         m_last_te_result = "BLOCKED";
         m_last_te_time   = iTime(m_symbol, PERIOD_CURRENT, 0);
      }

      // ── PHASE A.1: Increment passed_* counters for active TE gates that survived ──
      if(result == 1) {
         if(m_settings.TE_OpenDelaySeconds > 0)   m_te_pass_open_delay++;
         if(m_settings.TE_RecheckBarClose)         m_te_pass_bc_recheck++;
         if(m_settings.TE_SpreadMedianTicks > 0)   m_te_pass_spread_median++;
      }

      return result;
   }

   //+------------------------------------------------------------------+
   //| REFACTORED: GENERAL EVALUATE TM (No Double Scaling)              |
   //+------------------------------------------------------------------+
   // Public method: excursion tracking only, no SL modification (for tick-by-tick call)
   void UpdateExcursionOnly() {
      CleanupClosedPositionStates();
      ulong ticket = GetMyPosition();
      if(ticket == 0 || !PositionSelectByTicket(ticket)) {
          m_initial_sl_price = 0.0;
          return;
      }
      UpdatePositionExcursion(ticket);
   }

   void EvaluateTM() {
      CleanupClosedPositionStates();
      if(m_settings.EmergencyMarginLevel > 0.0) {
         double margin_level = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
         if(margin_level > 0.0 && margin_level < m_settings.EmergencyMarginLevel) {
            ulong worst_ticket = FindWorstPosition();
            if(worst_ticket > 0) {
               m_trade.PositionClose(worst_ticket);
               m_last_close_bar = iTime(m_symbol, PERIOD_CURRENT, 0);
               m_last_tracked_ticket = 0;
               return;
            }
         }
      }

      ulong ticket = GetMyPosition();
      if(ticket == 0 || !PositionSelectByTicket(ticket)) {
         // Reset initial SL when no position
         m_initial_sl_price = 0.0;
         // Detect close: if we had a position last call but now we don't, record the close bar
         if(m_last_tracked_ticket > 0) {
            m_last_close_bar = iTime(m_symbol, PERIOD_CURRENT, 0);
            m_last_tracked_ticket = 0;
         }
         return;
      }
      m_last_tracked_ticket = ticket;

      // Always run excursion tracking (tick-by-tick, no gate)
      UpdatePositionExcursion(ticket);

      // Gate SL/BE modifications to once per bar
      datetime current_bar = iTime(m_symbol, PERIOD_CURRENT, 0);
      if(current_bar == m_last_tm_bar) return;
      m_last_tm_bar = current_bar;

      // Capture initial SL once at first bar of new position
      if(m_initial_sl_price <= 0.0) {
         m_initial_sl_price = PositionGetDouble(POSITION_SL);
      }

      // ── DPI Histogram Exit: check once per bar before other exit logic ──
      if(CheckDPIHistogramExit(ticket))
      {
         m_trade.PositionClose(ticket);
         m_last_close_bar = iTime(m_symbol, PERIOD_CURRENT, 0);
         m_last_tracked_ticket = 0;
         m_exits_dpi_hist++;
         return;
      }

      if(m_settings.ExitProfile == EXIT_PROFILE_RRM) {
         RRM_ManageStrictNoATR(ticket);
         return;
      }

      if(m_settings.TrailMode == TRAIL_NONE) return;

      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double current_sl       = PositionGetDouble(POSITION_SL);
      double current_tp       = PositionGetDouble(POSITION_TP);
      double current_price    = PositionGetDouble(POSITION_PRICE_CURRENT);
      double entry_price      = PositionGetDouble(POSITION_PRICE_OPEN);
      int    direction        = (type == POSITION_TYPE_BUY) ? 1 : -1;
      double new_sl           = 0.0;
      int    digits           = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);

      double pipSize  = GetPipSize();
      double profit_pips = (direction > 0) ? (current_price - entry_price) / pipSize : (entry_price - current_price) / pipSize;

      if(m_settings.TrailMode == TRAIL_PSAR_FLIP_EXIT || m_settings.TPMode == TP_MODE_PSAR_FLIP) {
         if(CheckPSARFlip(direction, current_price)) {
            m_trade.PositionClose(ticket);
            m_last_close_bar = iTime(m_symbol, PERIOD_CURRENT, 0);
            m_last_tracked_ticket = 0;
            return;
         }
         if(m_settings.TrailMode == TRAIL_PSAR_FLIP_EXIT) return;
      }

      // ── SAFETY: delay trail until open profit reaches R-multiple (Q6 2026-06) ──
      // The Inp_Global_Safety_DelayTrailUntilR input has a "Safety_" prefix that promises a
      // global gate. Previously this gate was honored only on the RRM path
      // (RRM_ManageStrictNoATR line 1529); on SIMPLE path the input was silently
      // dead. This block mirrors the RRM-path implementation so the "Safety_" prefix
      // is honest regardless of ExitProfile. The "let winners run" semantic is
      // path-agnostic — any trail mode benefits from waiting until the position has
      // earned a minimum R-multiple of open profit before trailing engages.
      //
      // OFF by default (Inp_Global_Safety_DelayTrailUntilR=false). No behavior change for
      // any user who didn't explicitly enable this safety override.
      if(m_settings.Safety_DelayTrailUntilR && m_settings.Safety_TrailActivateR > 0.0) {
         double R = (m_initial_sl_price > 0.0) ? MathAbs(entry_price - m_initial_sl_price) : 0.0;
         if(R > 0.0) {
            double open_profit_dist = (direction > 0) ? (current_price - entry_price)
                                                      : (entry_price - current_price);
            double threshold = m_settings.Safety_TrailActivateR * R;
            if(open_profit_dist < threshold) {
               if(m_settings.DebugFlow)
                  PrintFormat("[SAFETY/SIMPLE] Trail delayed: open %.1f pips < %.2fR (%.1f pips) — letting winner run",
                              open_profit_dist / pipSize, m_settings.Safety_TrailActivateR,
                              threshold / pipSize);
               return;
            }
         }
      }

      bool should_trail = CheckTrailTrigger(direction, profit_pips, entry_price, current_price);
      if(!should_trail) return;

      if(m_settings.TrailMode == TRAIL_PSAR) {
         new_sl = CalcPsarTrailAnchorSL(type == POSITION_TYPE_BUY, pipSize, digits);
      }
      else if(m_settings.TrailMode == TRAIL_FRACTAL) {
         double val = (type == POSITION_TYPE_BUY) ? GetFractalLevel(1) : GetFractalLevel(-1);
         if(val > 0) {
            // FIX: apply cushion to fractal trail (same as Swing SL cushion — instrument-scaled)
            double cushion = m_settings.SL_SwingPipsCushion * pipSize;
            new_sl = (type == POSITION_TYPE_BUY) ? (val - cushion) : (val + cushion);
         }
      }
      else if(m_settings.TrailMode == TRAIL_FIXED_PIPS) {
         double trail_dist = m_settings.TrailDistancePips * pipSize;
         new_sl = (type == POSITION_TYPE_BUY) ? (current_price - trail_dist) : (current_price + trail_dist);
      }
      else if(m_settings.TrailMode == TRAIL_BREAKEVEN) {
         bool at_or_past_be = (current_sl > 0.0) && ((type == POSITION_TYPE_BUY && current_sl >= entry_price) || (type == POSITION_TYPE_SELL && current_sl <= entry_price));
         if(at_or_past_be) {
            double trail_dist = m_settings.TrailDistancePips * pipSize;
            new_sl = (type == POSITION_TYPE_BUY) ? (current_price - trail_dist) : (current_price + trail_dist);
         }
         else if(profit_pips >= m_settings.BEThresholdPips) {
            new_sl = entry_price;
         }
      }
      else if(m_settings.TrailMode == TRAIL_PROFIT_PERCENT) {
         new_sl = CalculateProfitPercentTrailSL(ticket, type, entry_price, current_price, current_sl, pipSize, digits);
      }
      // Q3 (2026-06): TRAIL_EMA now reachable from EXIT_PROFILE_SIMPLE path too.
      // The helper handles its own SL apply (BE-floor, lock-profit, TP-past-close,
      // valid-check, PositionModify); we return immediately so the common SL-apply
      // tail below does NOT run for TRAIL_EMA. This keeps TRAIL_EMA's evaluation
      // identical regardless of which exit profile invoked it (SimpleEA principle).
      else if(m_settings.TrailMode == TRAIL_EMA) {
         ApplyTrailEMA(ticket, type == POSITION_TYPE_BUY, entry_price, current_price,
                       current_sl, current_tp, digits, pipSize, "SIMPLE");
         return;
      }

      // STEP16 2026-06: SIMPLE-path PSAR trail BE-floor fix — sibling of the RRM-path
      // fix in RRM_ManageStrictNoATR. Same OLD entry+RRM_BE_BufferPips clamp shape lived
      // here too; same fix applies. Uses `new_sl = 0.0` to skip modification (matches
      // the existing SIMPLE-path convention) rather than `return` (RRM-path convention).
      if(new_sl != 0.0 && m_settings.TrailMode == TRAIL_PSAR) {
         if(type == POSITION_TYPE_BUY) {
            if(new_sl < entry_price) {
               if(m_settings.DebugFlow) PrintFormat("[PSAR GUARD] #%I64u: Dot below entry (%.5f < %.5f), trail blocked (BE-floor)", ticket, new_sl, entry_price);
               new_sl = 0.0;
            }
            else if(m_settings.TrailLockProfit && current_sl != 0.0 && new_sl <= current_sl) {
               if(m_settings.DebugFlow) PrintFormat("[PSAR GUARD] #%I64u: Would move SL backwards (%.5f <= %.5f), trail blocked", ticket, new_sl, current_sl);
               new_sl = 0.0;
            }
         }
         else {
            if(new_sl > entry_price) {
               if(m_settings.DebugFlow) PrintFormat("[PSAR GUARD] #%I64u: Dot above entry (%.5f > %.5f), trail blocked (BE-floor)", ticket, new_sl, entry_price);
               new_sl = 0.0;
            }
            else if(m_settings.TrailLockProfit && current_sl != 0.0 && new_sl >= current_sl) {
               if(m_settings.DebugFlow) PrintFormat("[PSAR GUARD] #%I64u: Would move SL backwards (%.5f >= %.5f), trail blocked", ticket, new_sl, current_sl);
               new_sl = 0.0;
            }
         }
      }

      if(new_sl != 0.0) {
         new_sl = NormalizeDouble(new_sl, digits);
         bool modify = false;
         
         if(type == POSITION_TYPE_BUY) {
            bool improves = (current_sl == 0.0 || new_sl > current_sl);
            double sl_change = MathAbs(new_sl - current_sl) / pipSize;
            bool step_ok = (current_sl == 0.0 || sl_change >= m_settings.TrailStepPips || m_settings.TrailStepPips <= 0.0);
            if(improves && new_sl < current_price && step_ok) modify = true;
         } 
         else {
            bool improves = (current_sl == 0.0 || new_sl < current_sl);
            double sl_change = MathAbs(new_sl - current_sl) / pipSize;
            bool step_ok = (current_sl == 0.0 || sl_change >= m_settings.TrailStepPips || m_settings.TrailStepPips <= 0.0);
            if(improves && new_sl > current_price && step_ok) modify = true;
         }
         
         if(modify && IsModifyAllowed()) {
            m_trade.PositionModify(ticket, new_sl, current_tp);
         }
      }
   }
};
