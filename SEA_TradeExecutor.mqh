//+------------------------------------------------------------------+
//|                                            SEA_TradeExecutor.mqh |
//|                              MJS Institutional Trading Solutions |
//| Purpose: Order Execution, Safety, Trailing & Position Management |
//| Status:  PRODUCTION READY (Cached Handles & Decoupling Fixed)    |
//+------------------------------------------------------------------+
#property strict

#ifndef SEA_BUILD_TOKEN_103001
enum { __SEA_BUILD_TOKEN_MISSING_TRADEEXEC_103001 = SEA_BUILD_TOKEN_103001 };
#endif

#define SEA_MOD_TRADEEXEC_103001 1

#include <RRMS\SEA_Config.mqh>
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
   
   // Indicator Handles (Fixes Asynchronous CopyBuffer failures)
   int         m_h_psar;
   int         m_h_fractals;
   
   // Telemetry Cache
   datetime    m_last_trade_bar;
   datetime    m_last_risk_warn;
   ulong       m_rrm_last_ticket;
   bool        m_rrm_trail_frozen;
   bool        m_rrm_be_reached;
   double      m_rrm_initial_sl;
   datetime    m_rrm_freeze_time;
   datetime    m_last_te_time;
   string      m_last_te_result;
   string      m_last_te_reason;
   
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

   void ReleaseHandles() {
      if(m_h_psar != INVALID_HANDLE) { IndicatorRelease(m_h_psar); m_h_psar = INVALID_HANDLE; }
      if(m_h_fractals != INVALID_HANDLE) { IndicatorRelease(m_h_fractals); m_h_fractals = INVALID_HANDLE; }
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
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && 
            PositionGetInteger(POSITION_MAGIC) == m_magic) {
            return ticket;
         }
      }
      return 0;
   }

   void CountMyPositions(int &buy_count, int &sell_count) {
      buy_count = 0; sell_count = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--) {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
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
         if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
         if((ulong)PositionGetInteger(POSITION_MAGIC) != m_magic) continue;
         m_trade.PositionClose(ticket);
      }
   }

   //+------------------------------------------------------------------+
   //| REFACTORED PRICE MATH & BULLETPROOF INDICATOR HELPERS            |
   //+------------------------------------------------------------------+
   
   double GetPipSize() const {
      int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
      if(digits == 3 || digits == 5) return _Point * 10.0;
      return _Point;
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
      ResetLastError();
      
      if(direction > 0) { 
         int idx = iLowest(_Symbol, PERIOD_CURRENT, MODE_LOW, lb, 1);
         if(idx < 0) {
            PrintFormat("⚠️ [DEBUG SL] iLowest failed! Error: %d", GetLastError());
            return 0.0;
         }
         return iLow(_Symbol, PERIOD_CURRENT, idx);
      } else { 
         int idx = iHighest(_Symbol, PERIOD_CURRENT, MODE_HIGH, lb, 1);
         if(idx < 0) {
            PrintFormat("⚠️ [DEBUG SL] iHighest failed! Error: %d", GetLastError());
            return 0.0;
         }
         return iHigh(_Symbol, PERIOD_CURRENT, idx);
      }
   }

   double GetFractalLevel(int direction) {
      int period = (m_settings.FractalPeriod > 0) ? m_settings.FractalPeriod : 5;
      int lookback = period * 3;
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

      double current_price = (direction > 0) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
      bool valid_side = (direction > 0 && fractal_level > current_price) || (direction < 0 && fractal_level < current_price);
      if(!valid_side) return 0.0;

      return MathAbs(fractal_level - current_price) / GetPipSize();
   }

   bool CheckPSARFlip(int direction, double current_price) {
      double psar = GetPSARAnchor(0);
      if(psar <= 0.0) return false;
      return (direction > 0 && psar > current_price) || (direction < 0 && psar < current_price);
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
            double profit_percent = (profit_pips * GetPipSize() / entry_price) * 100.0;
            return (profit_percent >= m_settings.TrailProfitPercent);
         }
         case TRIGGER_PSAR_ALIGN: {
            double psar = GetPSARAnchor(0);
            if(psar <= 0.0) return false;
            return (direction > 0 && psar < current_price) || (direction < 0 && psar > current_price);
         }
      }
      return true;
   }

   double NormalizeVolume(double vol) {
      double vmin=0.0, vmax=0.0, vstep=0.0;
      if(!SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN, vmin))  vmin = 0.01;
      if(!SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX, vmax))  vmax = 100.0;
      if(!SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP, vstep)) vstep = vmin;
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
      long stops_level_pts = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
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
      double tick_size=0.0, tick_value=0.0;
      if(!SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE, tick_size) || tick_size <= 0.0) return 0.0;
      if(!SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE_LOSS, tick_value) || tick_value <= 0.0) {
         SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE, tick_value);
      }
      if(tick_value <= 0.0) return 0.0;
      double loss_per_lot = (stop_dist / tick_size) * tick_value;
      if(loss_per_lot <= 0.0) return 0.0;
      double raw_lot = risk_money / loss_per_lot;
      if(raw_lot <= 0.0) return 0.0;
      return NormalizeVolume(raw_lot);
   }

   int CountConsecutiveLosses() {
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
         if(HistoryDealGetString(deal, DEAL_SYMBOL) != _Symbol) continue;
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

   double CalcLotMACompat() {
      double mr = m_settings.MA_MaximumRiskPct;
      if(mr <= 0.0) return 0.0;
      double price = 0.0;
      if(!SymbolInfoDouble(_Symbol, SYMBOL_ASK, price)) return 0.0;
      double margin = 0.0;
      if(!OrderCalcMargin(ORDER_TYPE_BUY, _Symbol, 1.0, price, margin)) return 0.0;
      if(margin <= 0.0) return 0.0;
      double free = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      if(free <= 0.0) return 0.0;
      double lot = NormalizeDouble(free * mr / margin, 2);
      int losses = CountConsecutiveLosses();
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
      double margin = 0.0;
      if(!OrderCalcMargin(type, _Symbol, vol, price, margin) || margin <= 0.0) return vol;
      if(margin <= free) return vol;
      double vmin=0.0, vstep=0.0;
      if(!SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN, vmin) || vmin <= 0.0) vmin = 0.01;
      if(!SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP, vstep) || vstep <= 0.0) vstep = vmin;
      int guard = 0;
      while(vol > vmin && margin > free && guard < 1000) {
         vol = NormalizeVolume(vol - vstep);
         if(vol < vmin) vol = vmin;
         if(!OrderCalcMargin(type, _Symbol, vol, price, margin) || margin <= 0.0) break;
         guard++;
      }
      if(margin > free) return 0.0;
      return vol;
   }

   //+------------------------------------------------------------------+
   //| REFACTORED: PURE PRICE ANCHOR SL CALCULATION                     |
   //+------------------------------------------------------------------+
   double RRM_GetStrictSL(bool isBuy, double entry) {
      double pipSize = GetPipSize();
      double fixed_dist = m_settings.SL_FixedPips * pipSize;
      
      switch(m_settings.SLMode) {
         case SL_MODE_SWING: {
            double swing_level = GetSwingLevel(isBuy ? 1 : -1);
            if(swing_level > 0.0) {
               bool valid = isBuy ? (swing_level < entry) : (swing_level > entry);
               if(!valid) {
                  PrintFormat("⚠️ [RRM SL] Swing anchor on wrong side. Using Fixed Pips.");
                  return isBuy ? (entry - fixed_dist) : (entry + fixed_dist);
               }
               double cushion_price = m_settings.SL_SwingPipsCushion * pipSize;
               return isBuy ? (swing_level - cushion_price) : (swing_level + cushion_price);
            }
            PrintFormat("⚠️ [RRM SL FALLBACK] Swing Anchor failed. Using Fixed Pips.");
            return isBuy ? (entry - fixed_dist) : (entry + fixed_dist);
         }
         case SL_MODE_PSAR_DOT: {
            double psar = GetPSARAnchor(1);
            if(psar > 0.0) {
               bool valid = isBuy ? (psar < entry) : (psar > entry);
               if(!valid) {
                  PrintFormat("⚠️ [RRM SL] PSAR anchor on wrong side. Using Fixed Pips.");
                  return isBuy ? (entry - fixed_dist) : (entry + fixed_dist);
               }
               double cushion_price = m_settings.SL_PsarPipsCushion * pipSize;
               return isBuy ? (psar - cushion_price) : (psar + cushion_price);
            }
            PrintFormat("⚠️ [RRM SL FALLBACK] PSAR Anchor failed or buffer empty. Using Fixed Pips.");
            return isBuy ? (entry - fixed_dist) : (entry + fixed_dist);
         }
         default:
            return isBuy ? (entry - fixed_dist) : (entry + fixed_dist);
      }
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
                  PrintFormat("⚠️ [SL] Swing anchor (%.5f) on wrong side of entry (%.5f) for %s — fallback to Fixed Pips", anchor, price, isBuy ? "BUY" : "SELL");
                  anchor = 0.0;
               }
            }
            break;
         case SL_MODE_PSAR_DOT:
            anchor = GetPSARAnchor(1);
            cushion_pips = m_settings.SL_PsarPipsCushion;
            if(anchor > 0.0) {
               bool valid = isBuy ? (anchor < price) : (anchor > price);
               if(!valid) {
                  PrintFormat("⚠️ [SL] PSAR anchor (%.5f) on wrong side of entry (%.5f) for %s — fallback to Fixed Pips", anchor, price, isBuy ? "BUY" : "SELL");
                  anchor = 0.0;
               }
            }
            break;
         case SL_MODE_FRACTAL:
            anchor = GetFractalLevel(isBuy ? 1 : -1);
            cushion_pips = 0.0; 
            break;
         case SL_MODE_PERCENT: {
            double sl_pips = (price * m_settings.SLPercent / 100.0) / pipSize;
            return isBuy ? (price - (sl_pips * pipSize)) : (price + (sl_pips * pipSize));
         }
         case SL_MODE_FIXED_PIPS:
         default: {
            double dist = m_settings.SL_FixedPips * pipSize;
            PrintFormat("ℹ️ [SL TRACE] Using FIXED PIPS: %.1f", m_settings.SL_FixedPips);
            return isBuy ? (price - dist) : (price + dist);
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
      return sl;
   }

   double RRM_GetStrictTP(bool isBuy, double entry, double sl) {
      if(!m_settings.TP_Enabled || m_settings.RRRatio <= 0.0 || sl <= 0.0) return 0.0;
      double sl_dist = MathAbs(entry - sl);
      if(sl_dist <= 0.0) return 0.0;
      double tp_dist = sl_dist * m_settings.RRRatio;
      return isBuy ? (entry + tp_dist) : (entry - tp_dist);
   }

   //+------------------------------------------------------------------+
   //| REFACTORED: STRICT TRAILING MANAGEMENT (No Double Scaling)       |
   //+------------------------------------------------------------------+
   void RRM_ManageStrictNoATR(ulong ticket) {
      if(!PositionSelectByTicket(ticket)) return;

      if(ticket != m_rrm_last_ticket) {
         m_rrm_last_ticket  = ticket;
         m_rrm_trail_frozen = false;
         m_rrm_freeze_time  = 0;
         m_rrm_be_reached   = false;
         if(m_rrm_initial_sl <= 0.0) m_rrm_initial_sl = PositionGetDouble(POSITION_SL);
      }

      ENUM_POSITION_TYPE pos_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      bool   isBuy     = (pos_type == POSITION_TYPE_BUY);
      double entry     = PositionGetDouble(POSITION_PRICE_OPEN);
      double cur_price = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double cur_sl    = PositionGetDouble(POSITION_SL);
      double cur_tp    = PositionGetDouble(POSITION_TP);
      int    digits    = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
      double pipSize   = GetPipSize();

      double R = (m_rrm_initial_sl > 0.0) ? MathAbs(entry - m_rrm_initial_sl) : 0.0;

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
            if(isBuy ? (be_sl > cur_sl) : (cur_sl == 0.0 || be_sl < cur_sl)) {
               if(m_trade.PositionModify(ticket, be_sl, cur_tp)) { 
                  m_rrm_be_reached = true; 
                  cur_sl = be_sl; 
                  if(m_settings.DebugFlow) PrintFormat("RRM Strict BE: SL -> %.5f (%s)", be_sl, _Symbol);
               }
            }
         }
      }

      // TRAILING
      if(m_settings.TrailMode != TRAIL_PSAR) return;
      if(m_settings.RRM_TrailStartsAfterBE && !m_rrm_be_reached) return;

      int shift = m_settings.RRM_TrailPsarShiftDelay;
      if(shift < 1) shift = 1;
      if(shift > 3) shift = 3;
      double psar = GetPSARAnchor(shift);
      if(psar <= 0.0) return;

      bool psar_flipped = isBuy ? (psar > cur_price) : (psar < cur_price);
      if(psar_flipped) {
         if(m_settings.RRM_FreezeTrailOnFlip && !m_rrm_trail_frozen) {
            m_rrm_trail_frozen = true; m_rrm_freeze_time = TimeCurrent();
            if(m_settings.DebugFlow) PrintFormat("RRM Strict trail frozen (PSAR flip): %s | PSAR=%.5f Price=%.5f", _Symbol, psar, cur_price);
         }
         return;
      } else if(m_rrm_trail_frozen) {
         int min_freeze_bars = 2;
         int bars_frozen = (m_rrm_freeze_time > 0) ? Bars(_Symbol, PERIOD_CURRENT, m_rrm_freeze_time, TimeCurrent()) : 0;
         if(bars_frozen >= min_freeze_bars) {
            m_rrm_trail_frozen = false;
            if(m_settings.DebugFlow) PrintFormat("RRM Strict trail UNFROZEN (PSAR corrected): %s | PSAR=%.5f Price=%.5f", _Symbol, psar, cur_price);
         }
         else return;
      }

      double cushion = m_settings.PSAR_TrailPipsCushion * pipSize;
      double new_sl  = isBuy ? NormalizeDouble(psar - cushion, digits) : NormalizeDouble(psar + cushion, digits);

      if(m_rrm_be_reached && cur_sl != 0.0) {
         if(isBuy  && new_sl < cur_sl) return;
         if(!isBuy && new_sl > cur_sl) return;
      }

      bool can_move = isBuy ? (new_sl > cur_sl && new_sl < cur_price) : ((cur_sl == 0.0 || new_sl < cur_sl) && new_sl > cur_price);
      if(can_move) m_trade.PositionModify(ticket, new_sl, cur_tp);
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
         m_excursion.be_reached = (sl_dist_from_entry <= 5.0 * _Point);
      }

      switch(m_settings.TrailMode) {
         case TRAIL_PSAR:
         case TRAIL_PSAR_FLIP_EXIT: m_excursion.trail_active = true; m_excursion.trail_type = "PSAR"; break;
         case TRAIL_FRACTAL: m_excursion.trail_active = true; m_excursion.trail_type = "FRACTAL"; break;
         case TRAIL_FIXED_PIPS: m_excursion.trail_active = true; m_excursion.trail_type = "FIXED"; break;
         case TRAIL_BREAKEVEN: m_excursion.trail_active = true; m_excursion.trail_type = "BE"; break;
         case TRAIL_PROFIT_PERCENT: m_excursion.trail_active = true; m_excursion.trail_type = "PROFIT%"; break;
         default: m_excursion.trail_active = false; m_excursion.trail_type = "OFF"; break;
      }
   }

public:
   CTradeExecutor() : m_last_trade_bar(0), m_last_risk_warn(0),
                      m_rrm_last_ticket(0), m_rrm_trail_frozen(false),
                      m_rrm_be_reached(false), m_rrm_initial_sl(0.0),
                      m_rrm_freeze_time(0), m_last_te_time(0), m_last_te_result(""), m_last_te_reason(""),
                      m_h_psar(INVALID_HANDLE), m_h_fractals(INVALID_HANDLE) // CACHED HANDLES
   {
      m_excursion.ticket = 0; m_excursion.entry_time = 0; m_excursion.entry_price = 0.0;
      m_excursion.mae_pips = 0.0; m_excursion.mfe_pips = 0.0; m_excursion.current_pips = 0.0;
      m_excursion.be_reached = false; m_excursion.trail_active = false; m_excursion.trail_type = "OFF";
   }

   ~CTradeExecutor() {
      ReleaseHandles();
   }

   datetime LastTETime()   const { return m_last_te_time; }
   string   LastTEResult() const { return m_last_te_result; }
   string   LastTEReason() const { return m_last_te_reason; }

   void Init(ulong magic, ST_Settings &sets) {
      m_magic = magic;
      m_settings = sets;
      m_trade.SetExpertMagicNumber(m_magic);
      m_trade.SetDeviationInPoints(10);
      m_trade.SetTypeFilling(ORDER_FILLING_IOC);
      m_trade.LogLevel(LOG_LEVEL_ERRORS);
      
      ReleaseHandles();
      m_h_psar = iSAR(_Symbol, PERIOD_CURRENT, m_settings.P_PsarStep, m_settings.P_PsarMax);
      m_h_fractals = iFractals(_Symbol, PERIOD_CURRENT);
   }
   
   void UpdateSettings(ST_Settings &sets) { 
      bool recreate_psar = (m_settings.P_PsarStep != sets.P_PsarStep || m_settings.P_PsarMax != sets.P_PsarMax);
      m_settings = sets; 
      if (recreate_psar) {
         if (m_h_psar != INVALID_HANDLE) IndicatorRelease(m_h_psar);
         m_h_psar = iSAR(_Symbol, PERIOD_CURRENT, m_settings.P_PsarStep, m_settings.P_PsarMax);
      }
   }

   string GetPositionSnapshot() {
      for(int i = PositionsTotal() - 1; i >= 0; i--) {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(PositionGetInteger(POSITION_MAGIC) != (long)m_magic) continue;
         if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
         
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
            double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
            double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
            if(tick_value <= 0.0) tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
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
         if(PositionGetString(POSITION_SYMBOL) != _Symbol || PositionGetInteger(POSITION_MAGIC) != (long)m_magic) continue;
         if(m_settings.CountBEasZeroRisk && IsPositionAtBreakEven(ticket)) continue;
         total_risk += CalculatePositionRisk(ticket);
      }
      return total_risk;
   }

   bool IsPositionAtBreakEven(ulong ticket) {
      if(!PositionSelectByTicket(ticket)) return false;
      double sl = PositionGetDouble(POSITION_SL);
      double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
      return (sl != 0.0 && MathAbs(sl - open_price) <= 2.0 * SymbolInfoDouble(_Symbol, SYMBOL_POINT));
   }

   double CalculatePositionRisk(ulong ticket) {
      if(!PositionSelectByTicket(ticket)) return 0.0;
      double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl = PositionGetDouble(POSITION_SL);
      double volume = PositionGetDouble(POSITION_VOLUME);
      if(sl == 0.0) return 0.0;

      double stop_dist = MathAbs(open_price - sl);
      double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      if(tick_size == 0.0 || tick_value == 0.0) return 0.0;
      
      double account_equity = AccountInfoDouble(ACCOUNT_EQUITY);
      if(account_equity == 0.0) return 0.0;
      return (((stop_dist / tick_size) * tick_value * volume) / account_equity) * 100.0;
   }

   ulong FindPositionByMagic(ulong magic) const {
      for(int i = PositionsTotal() - 1; i >= 0; i--) {
         ulong ticket = PositionGetTicket(i);
         if(ticket > 0 && PositionGetString(POSITION_SYMBOL) == _Symbol && (ulong)PositionGetInteger(POSITION_MAGIC) == magic) {
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
         double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
         double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
         if(tick_value <= 0.0) tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
         if(tick_size > 0.0 && tick_value > 0.0) {
            return (MathAbs(open - sl) / tick_size) * tick_value * volume;
         }
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
         double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
         double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE_PROFIT);
         if(tick_value <= 0.0) tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
         if(tick_size > 0.0 && tick_value > 0.0) {
            return (MathAbs(tp - open) / tick_size) * tick_value * volume;
         }
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
      double price = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl = CalcEntrySL(isBuy, price);
      return (sl > 0.0) ? MathAbs(price - sl) / GetPipSize() : 0.0;
   }

   double GetTakeProfitPips(int direction) {
      double tp_pips = 0.0;
      switch(m_settings.TPMode) {
         case TP_MODE_FIXED_PIPS: 
            tp_pips = m_settings.FixedTPPips; 
            break;
         case TP_MODE_RR: {
            double sl_pips = GetStopLossPips(direction);
            tp_pips = (sl_pips > 0.0 && m_settings.RRRatio > 0.0) ? sl_pips * m_settings.RRRatio : m_settings.FixedTPPips;
            break;
         }
         case TP_MODE_FRACTAL: {
            tp_pips = GetFractalTP(direction);
            if(tp_pips <= 0.0) tp_pips = (GetStopLossPips(direction) > 0.0) ? GetStopLossPips(direction) * m_settings.RRRatio : m_settings.FixedTPPips;
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

   double EvaluateCM(int direction) {
      if(direction == 0) return 0.0;
      bool isBuy = (direction == 1);
      double price = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl = CalcEntrySL(isBuy, price);
      
      double lot = NormalizeVolume(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN));
      if(m_settings.UseMACompatSizer) {
         double ma_lot = CalcLotMACompat();
         if(ma_lot > 0.0) lot = ma_lot;
      } else {
         double risk_lot = CalcLotByRisk(price, sl);
         if(risk_lot > 0.0) lot = risk_lot;
      }

      ENUM_ORDER_TYPE order_type = isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      return AdjustLotForMargin(order_type, lot, price);
   }

   bool EvaluateRC() {
      if(m_settings.MaxOpenTrades > 0) {
         int open_count = 0;
         for(int i = PositionsTotal() - 1; i >= 0; i--) {
            ulong ticket = PositionGetTicket(i);
            if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
            if(PositionGetString(POSITION_SYMBOL) != _Symbol || PositionGetInteger(POSITION_MAGIC) != (long)m_magic) continue;
            open_count++;
         }
         if(open_count >= m_settings.MaxOpenTrades) return false;
      }
      if(m_settings.MaxTotalRisk > 0.0) {
         if(CalculateActiveRisk() + m_settings.RiskPercent > m_settings.MaxTotalRisk) return false;
      }
      return true;
   }

   void ExecuteTrade(int direction, double lots) {
      if(m_settings.ma_v_shift == 1 && m_last_trade_bar == iTime(_Symbol, PERIOD_CURRENT, 0)) {
         m_last_te_time = iTime(_Symbol, PERIOD_CURRENT, 0); m_last_te_result = "BLOCKED"; return;
      }
   
      int buy_count=0, sell_count=0;
      CountMyPositions(buy_count, sell_count);
   
      if((direction == 1 && buy_count > 0 && sell_count == 0) || (direction == -1 && sell_count > 0 && buy_count == 0)) {
         m_last_te_time = iTime(_Symbol, PERIOD_CURRENT, 0); m_last_te_result = "BLOCKED"; return;
      }
   
      if((buy_count + sell_count) > 0) {
         if(direction != 0 && m_settings.CloseOnReverse) {
            CloseAllMyPositions();
            m_last_trade_bar = iTime(_Symbol, PERIOD_CURRENT, 0);
            if(m_settings.MABenchmarkStrict) { m_last_te_time = iTime(_Symbol, PERIOD_CURRENT, 0); m_last_te_result = "BLOCKED"; return; }
         } else {
            m_last_te_time = iTime(_Symbol, PERIOD_CURRENT, 0); m_last_te_result = "BLOCKED"; return;
         }
      }
   
      if(direction == 0) return;
      double price = (direction == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl = 0, tp = 0;
      bool isBuy = (direction == 1);

      sl = CalcEntrySL(isBuy, price);

      if(m_settings.ExitProfile == EXIT_PROFILE_RRM) {
         tp = RRM_GetStrictTP(isBuy, price, sl);
      } else {
         if(m_settings.TPMode == TP_MODE_NONE || m_settings.TPMode == TP_MODE_PSAR_FLIP) {
            tp = 0.0;
         } else if(m_settings.TPMode == TP_MODE_FRACTAL) {
            double tp_pips = GetFractalTP(direction == 1 ? 1 : -1);
            if(tp_pips > 0.0) {
               double tp_dist = tp_pips * GetPipSize();
               tp = isBuy ? (price + tp_dist) : (price - tp_dist);
            } else if(sl > 0.0 && m_settings.RRRatio > 0.0) {
               double sl_dist = MathAbs(price - sl);
               tp = isBuy ? (price + sl_dist * m_settings.RRRatio) : (price - sl_dist * m_settings.RRRatio);
            }
         } else if(m_settings.RRRatio > 0) {
            double dist = (sl > 0) ? MathAbs(price - sl) * m_settings.RRRatio : m_settings.SL_FixedPips * GetPipSize() * m_settings.RRRatio;
            tp = isBuy ? price + dist : price - dist;
         }
      }
      
      int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
      if(sl > 0) sl = NormalizeDouble(sl, digits);
      if(tp > 0) tp = NormalizeDouble(tp, digits);
   
      ENUM_ORDER_TYPE type = isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      string comment = StringFormat("SEA_%s", EnumToString(m_settings.SLMode));

      if(!ValidateStopLevels(price, sl, tp)) {
         m_last_te_time = iTime(_Symbol, PERIOD_CURRENT, 0); m_last_te_result = "BLOCKED"; return;
      }

      if(m_trade.PositionOpen(_Symbol, type, lots, price, sl, tp, comment)) {
         m_last_te_time = iTime(_Symbol, PERIOD_CURRENT, 0); m_last_te_result = "ENTERED";
         m_last_trade_bar = iTime(_Symbol, PERIOD_CURRENT, 0);
         if(m_settings.ExitProfile == EXIT_PROFILE_RRM) {
            m_rrm_initial_sl = sl; m_rrm_be_reached = false; m_rrm_trail_frozen = false; m_rrm_last_ticket = 0;
         }
      } else {
         m_last_te_time = iTime(_Symbol, PERIOD_CURRENT, 0); m_last_te_result = "BLOCKED";
      }
   }

   int EvaluateTE(int ts_direction) {
      if(ts_direction == 0) return 0;
      m_te_veto_reason = "OK";
      string te_reject_reason = "";
      
      if(te_reject_reason == "") { if(!EvaluateRC()) te_reject_reason = "VETO_RISK_CONTROL"; }
      
      double te_lots = 0;
      if(te_reject_reason == "") {
         te_lots = EvaluateCM(ts_direction);
         if(te_lots <= 0) te_reject_reason = "VETO_INVALID_LOTS";
      }

      int result = 0;
      if(te_reject_reason == "") {
         ExecuteTrade(ts_direction, te_lots);
         result = (m_last_te_result == "ENTERED") ? 1 : 0;
         if(result == 0) te_reject_reason = m_last_te_reason;
      }
      
      m_te_veto_reason = (te_reject_reason == "") ? "OK" : te_reject_reason;
      return result;
   }

   //+------------------------------------------------------------------+
   //| REFACTORED: GENERAL EVALUATE TM (No Double Scaling)              |
   //+------------------------------------------------------------------+
   void EvaluateTM() {
      ulong ticket = GetMyPosition();
      if(ticket == 0 || !PositionSelectByTicket(ticket)) return;

      UpdatePositionExcursion(ticket);

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
      
      double pipSize  = GetPipSize();
      double profit_pips = (direction > 0) ? (current_price - entry_price) / pipSize : (entry_price - current_price) / pipSize;

      if(m_settings.TrailMode == TRAIL_PSAR_FLIP_EXIT || m_settings.TPMode == TP_MODE_PSAR_FLIP) {
         if(CheckPSARFlip(direction, current_price)) {
            m_trade.PositionClose(ticket);
            return;
         }
         if(m_settings.TrailMode == TRAIL_PSAR_FLIP_EXIT) return;
      }

      bool should_trail = CheckTrailTrigger(direction, profit_pips, entry_price, current_price);
      if(!should_trail) return;

      if(m_settings.TrailMode == TRAIL_PSAR) {
         int psar_shift = m_settings.PSAR_TrailDelay;
         if(psar_shift < 1) psar_shift = 1;
         if(psar_shift > 3) psar_shift = 3;
         double psar = GetPSARAnchor(psar_shift);
         if(psar > 0.0) {
            double cushion = m_settings.PSAR_TrailPipsCushion * pipSize;
            new_sl = (type == POSITION_TYPE_BUY) ? (psar - cushion) : (psar + cushion);
         }
      }
      else if(m_settings.TrailMode == TRAIL_FRACTAL) {
         double val = (type == POSITION_TYPE_BUY) ? GetFractalLevel(1) : GetFractalLevel(-1);
         if(val > 0) new_sl = val;
      }
      else if(m_settings.TrailMode == TRAIL_FIXED_PIPS) {
         double trail_dist = m_settings.TrailDistancePips * pipSize;
         new_sl = (type == POSITION_TYPE_BUY) ? (current_price - trail_dist) : (current_price + trail_dist);
      }
      else if(m_settings.TrailMode == TRAIL_BREAKEVEN) {
         double be_dist = m_settings.BEThresholdPips * pipSize;
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
         double trail_dist = m_settings.TrailDistancePips * pipSize;
         new_sl = (type == POSITION_TYPE_BUY) ? (current_price - trail_dist) : (current_price + trail_dist);
      }

      if(new_sl != 0.0) {
         int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
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
         
         if(modify) {
            m_trade.PositionModify(ticket, new_sl, current_tp);
         }
      }
   }
};
