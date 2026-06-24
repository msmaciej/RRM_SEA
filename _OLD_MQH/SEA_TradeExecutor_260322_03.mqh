//+------------------------------------------------------------------+
//|                                            SEA_TradeExecutor.mqh |
//|                              MJS Institutional Trading Solutions |
//|                                                                  |
//| Purpose: Order Execution, Safety, Trailing & Position Management |
//| Status:  PRODUCTION READY (Revision M Compatible)                |
//+------------------------------------------------------------------+
#property strict

// --- Anti-stale build lock (MQL5-safe: no #if, no #error)
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
   datetime    m_last_trade_bar;
   datetime    m_last_risk_warn;
   ulong       m_rrm_last_ticket;
   bool        m_rrm_trail_frozen;
   bool        m_rrm_be_reached;
   double      m_rrm_initial_sl;
   datetime    m_last_te_time;
   string      m_last_te_result;
   string      m_last_te_reason;

   //+------------------------------------------------------------------+
   //| HELPER: Identify Position belonging to this specific EA Instance |
   //+------------------------------------------------------------------+
   ulong GetMyPosition() {
      // Iterate backwards through all positions
      for(int i = PositionsTotal() - 1; i >= 0; i--) {
         ulong ticket = PositionGetTicket(i);
         
         // Check Symbol AND Magic Number
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && 
            PositionGetInteger(POSITION_MAGIC) == m_magic) {
            return ticket;
         }
      }
      return 0; // No position found
   }

   //+------------------------------------------------------------------+
   //| HELPER: Count all positions for this EA instance (hedge-safe)   |
   //+------------------------------------------------------------------+
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

   //+------------------------------------------------------------------+
   //| HELPER: Close all positions for this EA instance (hedge-safe)   |
   //+------------------------------------------------------------------+
   void CloseAllMyPositions() {
      // Iterate backwards; PositionClose can change PositionsTotal()
      for(int i = PositionsTotal() - 1; i >= 0; i--) {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
         if((ulong)PositionGetInteger(POSITION_MAGIC) != m_magic) continue;
         m_trade.PositionClose(ticket);
      }
   }


   //+------------------------------------------------------------------+
   //| HELPER: Get Fractal for Trailing Stop                            |
   //+------------------------------------------------------------------+
   double GetFractalForTrail(int mode) { 
      double r[1];
      int h = iFractals(_Symbol, PERIOD_CURRENT);
      
      if(h == INVALID_HANDLE) return 0.0;
      
      // Look back 2-20 bars for nearest valid fractal
      for(int i=2; i<20; i++) {
         if(CopyBuffer(h, mode, i, 1, r) > 0 && r[0] != DBL_MAX && r[0] > 0) {
            IndicatorRelease(h);
            return r[0];
         }
      }
      IndicatorRelease(h);
      return 0.0;
   }

   //+------------------------------------------------------------------+
   //| HELPER: Get Parabolic SAR value for trailing stop                |
   //| Uses last confirmed value by default (shift=1).                  |
   //+------------------------------------------------------------------+
   double GetPsarForTrail(const int shift=1)
   {
      double r[1];
      int h = iSAR(_Symbol, PERIOD_CURRENT, m_settings.P_PsarStep, m_settings.P_PsarMax);
      if(h == INVALID_HANDLE) return 0.0;
      if(CopyBuffer(h, 0, shift, 1, r) <= 0) { IndicatorRelease(h); return 0.0; }
      IndicatorRelease(h);
      if(r[0] == DBL_MAX || r[0] <= 0.0) return 0.0;
      return r[0];
   }

   //+------------------------------------------------------------------+
   //| HELPER (Phase 2.2): Get PSAR value using strategy PSAR settings |
   //| Uses PSARStep/PSARMax fields (separate from trading PSAR params) |
   //+------------------------------------------------------------------+
   double GetPSARValue(const int shift=1)
   {
      double step = (m_settings.PSARStep > 0.0) ? m_settings.PSARStep : 0.02;
      double maxv = (m_settings.PSARMax  > 0.0) ? m_settings.PSARMax  : 0.2;
      double r[1];
      int h = iSAR(_Symbol, PERIOD_CURRENT, step, maxv);
      if(h == INVALID_HANDLE) return 0.0;
      if(CopyBuffer(h, 0, shift, 1, r) <= 0) { IndicatorRelease(h); return 0.0; }
      IndicatorRelease(h);
      if(r[0] == DBL_MAX || r[0] <= 0.0) return 0.0;
      return r[0];
   }

   //+------------------------------------------------------------------+
   //| HELPER (Phase 2.2): SL distance in pips using last fractal      |
   //| LONG: uses last down-fractal (support); SHORT: last up-fractal   |
   //+------------------------------------------------------------------+
   double GetFractalSL(int direction)
   {
      int period   = (m_settings.FractalPeriod > 0) ? m_settings.FractalPeriod : 5;
      int lookback = period * 3;
      double fractal_level = 0.0;

      // mode 1 = lower fractals (support), mode 0 = upper fractals (resistance)
      int mode = (direction > 0) ? 1 : 0;
      double r[1];
      int h = iFractals(_Symbol, PERIOD_CURRENT);
      if(h == INVALID_HANDLE) return 0.0;

      for(int i = period; i < lookback; i++)
      {
         if(CopyBuffer(h, mode, i, 1, r) > 0 && r[0] != DBL_MAX && r[0] > 0.0)
         {
            fractal_level = r[0];
            break;
         }
      }
      IndicatorRelease(h);

      if(fractal_level <= 0.0) return 0.0;

      double current_price = (direction > 0) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                              : SymbolInfoDouble(_Symbol, SYMBOL_BID);

      // Validate that fractal is on the correct side
      bool valid_side = (direction > 0 && fractal_level < current_price) ||
                        (direction < 0 && fractal_level > current_price);
      if(!valid_side) return 0.0;

      bool isJPY  = (StringFind(_Symbol, "JPY") >= 0);
      double pipSize = _Point * (isJPY ? 100.0 : 10.0);
      return MathAbs(current_price - fractal_level) / pipSize;
   }

   //+------------------------------------------------------------------+
   //| HELPER (Phase 2.2): SL distance in pips using PSAR dot          |
   //+------------------------------------------------------------------+
   double GetPSARSL(int direction)
   {
      double psar = GetPSARValue(1);
      if(psar <= 0.0) return 0.0;

      double current_price = (direction > 0) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                              : SymbolInfoDouble(_Symbol, SYMBOL_BID);

      // Validate PSAR is on the correct side
      bool valid_psar = (direction > 0 && psar < current_price) ||
                        (direction < 0 && psar > current_price);
      if(!valid_psar) return 0.0;

      bool isJPY  = (StringFind(_Symbol, "JPY") >= 0);
      double pipSize = _Point * (isJPY ? 100.0 : 10.0);
      return MathAbs(current_price - psar) / pipSize;
   }

   //+------------------------------------------------------------------+
   //| HELPER (Phase 2.2): TP distance in pips using next fractal      |
   //| LONG: uses next up-fractal above price; SHORT: next down-fractal |
   //+------------------------------------------------------------------+
   double GetFractalTP(int direction)
   {
      int period    = (m_settings.FractalPeriod > 0) ? m_settings.FractalPeriod : 5;
      int lookback  = period * 5;
      int offset    = (m_settings.TPFractalOffset > 0) ? m_settings.TPFractalOffset : 1;
      double fractal_level = 0.0;
      int found_count = 0;

      // mode 0 = upper fractals (resistance/TP for LONG)
      // mode 1 = lower fractals (support/TP for SHORT)
      int mode = (direction > 0) ? 0 : 1;
      double r[1];
      int h = iFractals(_Symbol, PERIOD_CURRENT);
      if(h == INVALID_HANDLE) return 0.0;

      for(int i = period; i < lookback; i++)
      {
         if(CopyBuffer(h, mode, i, 1, r) > 0 && r[0] != DBL_MAX && r[0] > 0.0)
         {
            found_count++;
            if(found_count >= offset)
            {
               fractal_level = r[0];
               break;
            }
         }
      }
      IndicatorRelease(h);

      if(fractal_level <= 0.0) return 0.0;

      double current_price = (direction > 0) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                              : SymbolInfoDouble(_Symbol, SYMBOL_BID);

      // Validate fractal is ahead (in profit direction)
      bool valid_side = (direction > 0 && fractal_level > current_price) ||
                        (direction < 0 && fractal_level < current_price);
      if(!valid_side) return 0.0;

      bool isJPY  = (StringFind(_Symbol, "JPY") >= 0);
      double pipSize = _Point * (isJPY ? 100.0 : 10.0);
      return MathAbs(fractal_level - current_price) / pipSize;
   }

   //+------------------------------------------------------------------+
   //| HELPER (Phase 2.2): Check if PSAR has flipped against position  |
   //+------------------------------------------------------------------+
   bool CheckPSARFlip(int direction, double current_price)
   {
      double psar = GetPSARValue(0);  // Current bar PSAR
      if(psar <= 0.0) return false;

      bool flipped = (direction > 0 && psar > current_price) ||
                     (direction < 0 && psar < current_price);
      return flipped;
   }

   //+------------------------------------------------------------------+
   //| HELPER (Phase 2.2): Check if trailing trigger condition is met  |
   //+------------------------------------------------------------------+
   bool CheckTrailTrigger(int direction, double profit_pips, double entry_price, double current_price)
   {
      switch(m_settings.TrailTrigger)
      {
         case TRIGGER_IMMEDIATE:
            return true;

         case TRIGGER_BREAKEVEN:
            return (profit_pips >= m_settings.BEThresholdPips);

         case TRIGGER_PROFIT_PIPS:
            return (profit_pips >= m_settings.TrailDistancePips);

         case TRIGGER_PROFIT_PERCENT:
            {
               bool isJPY  = (StringFind(_Symbol, "JPY") >= 0);
               double pipSize = _Point * (isJPY ? 100.0 : 10.0);
               double profit_percent = (profit_pips * pipSize / entry_price) * 100.0;
               return (profit_percent >= m_settings.TrailProfitPercent);
            }

         case TRIGGER_PSAR_ALIGN:
            {
               double psar = GetPSARValue(0);
               if(psar <= 0.0) return false;
               bool aligned = (direction > 0 && psar < current_price) ||
                              (direction < 0 && psar > current_price);
               return aligned;
            }
      }
      return true;
   }

   //+------------------------------------------------------------------+
   //| HELPER (Strict): Convert pips to price with TF and JPY scaling   |
   //+------------------------------------------------------------------+
   double RRM_ScalePips(double pips)
   {
      double scale = 1.0;
      if(_Period == PERIOD_M1)       scale = 0.5;
      else if(_Period == PERIOD_M5)  scale = 0.8;
      else if(_Period == PERIOD_M15) scale = 1.0;
      else if(_Period >= PERIOD_H1)  scale = 2.0;
      bool isJPY = (StringFind(_Symbol, "JPY") >= 0);
      return pips * _Point * scale * (isJPY ? 100.0 : 10.0);
   }

   //+------------------------------------------------------------------+
   //| HELPER (Strict): Compute initial SL; fallback is SL_FIXED_PIPS   |
   //+------------------------------------------------------------------+
   double RRM_GetStrictSL(bool isBuy, double entry)
   {
      bool   isJPY      = (StringFind(_Symbol, "JPY") >= 0);
      double fixed_dist = m_settings.SL_FixedPips * _Point * (isJPY ? 100.0 : 10.0);

      switch(m_settings.SLMode)
      {
         case SL_MODE_SWING:
         {
            double swing = isBuy ? GetFractalForTrail(1) : GetFractalForTrail(0);
            if(swing > 0.0)
            {
               double cushion = RRM_ScalePips(m_settings.SL_SwingPipsCushion);
               return isBuy ? (swing - cushion) : (swing + cushion);
            }
            return isBuy ? (entry - fixed_dist) : (entry + fixed_dist);
         }
         case SL_MODE_PSAR_DOT:
         {
            double psar = GetPsarForTrail(1);
            if(psar > 0.0)
            {
               double cushion = RRM_ScalePips(m_settings.SL_PsarPipsCushion);
               return isBuy ? (psar - cushion) : (psar + cushion);
            }
            return isBuy ? (entry - fixed_dist) : (entry + fixed_dist);
         }
         default:
            return isBuy ? (entry - RRM_ScalePips(m_settings.SL_FixedPips))
                         : (entry + RRM_ScalePips(m_settings.SL_FixedPips));
      }
   }

   //+------------------------------------------------------------------+
   //| HELPER (Strict): TP = |entry-SL|*RRRatio; 0 when TP disabled    |
   //+------------------------------------------------------------------+
   double RRM_GetStrictTP(bool isBuy, double entry, double sl)
   {
      if(!m_settings.TP_Enabled || m_settings.RRRatio <= 0.0 || sl <= 0.0)
         return 0.0;
      double sl_dist = MathAbs(entry - sl);
      if(sl_dist <= 0.0) return 0.0;
      double tp_dist = sl_dist * m_settings.RRRatio;
      return isBuy ? (entry + tp_dist) : (entry - tp_dist);
   }

   //+------------------------------------------------------------------+
   //| MANAGE (Strict): Non-ATR BE and PSAR trail for strict RRM path   |
   //+------------------------------------------------------------------+
   void RRM_ManageStrictNoATR(ulong ticket)
   {
      if(!PositionSelectByTicket(ticket)) return;

      // Reset state when a new ticket is detected
      if(ticket != m_rrm_last_ticket)
      {
         m_rrm_last_ticket  = ticket;
         m_rrm_trail_frozen = false;
         m_rrm_be_reached   = false;
         if(m_rrm_initial_sl <= 0.0)
            m_rrm_initial_sl = PositionGetDouble(POSITION_SL);
      }

      ENUM_POSITION_TYPE pos_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      bool   isBuy     = (pos_type == POSITION_TYPE_BUY);
      double entry     = PositionGetDouble(POSITION_PRICE_OPEN);
      double cur_price = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                                : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double cur_sl    = PositionGetDouble(POSITION_SL);
      double cur_tp    = PositionGetDouble(POSITION_TP);
      int    digits    = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
      double R         = (m_rrm_initial_sl > 0.0) ? MathAbs(entry - m_rrm_initial_sl) : 0.0;

      // ---- BREAKEVEN ----
      if(m_settings.BE_Mode != BE_MODE_OFF && !m_rrm_be_reached)
      {
         double move = isBuy ? (cur_price - entry) : (entry - cur_price);
         bool should_be = false;

         if(m_settings.BE_Mode == BE_MODE_TP_PROGRESS_PCT && cur_tp > 0.0)
         {
            double tp_dist = MathAbs(cur_tp - entry);
            if(tp_dist > 0.0 && m_settings.RRM_BE_ProgressPct > 0.0)
               should_be = (move >= tp_dist * (m_settings.RRM_BE_ProgressPct / 100.0));
         }
         else if(m_settings.BE_Mode == BE_MODE_R_MULTIPLE && R > 0.0)
            should_be = (move >= m_settings.RRM_BE_RMultiple * R);

         if(should_be)
         {
            double be_buffer = RRM_ScalePips(m_settings.RRM_BE_BufferPips);
            double be_sl = isBuy ? NormalizeDouble(entry + be_buffer, digits)
                                 : NormalizeDouble(entry - be_buffer, digits);
            bool improves = isBuy ? (be_sl > cur_sl) : (cur_sl == 0.0 || be_sl < cur_sl);
            if(improves)
            {
               if(m_trade.PositionModify(ticket, be_sl, cur_tp))
               {
                  m_rrm_be_reached = true;
                  cur_sl = be_sl;
                  PrintFormat("RRM Strict BE: SL -> %.5f (%s)", be_sl, _Symbol);
               }
            }
         }
      }

      // ---- TRAILING STOP (PSAR only) ----
      if(m_settings.TrailMode != TRAIL_PSAR) return;
      if(m_settings.RRM_TrailStartsAfterBE && !m_rrm_be_reached) return;
      if(m_rrm_trail_frozen) return;

      int shift = m_settings.RRM_TrailPsarShiftDelay;
      if(shift < 1) shift = 1;
      if(shift > 3) shift = 3;
      double psar = GetPsarForTrail(shift);
      if(psar <= 0.0) return;

      bool psar_flipped = isBuy ? (psar > cur_price) : (psar < cur_price);
      if(psar_flipped)
      {
         if(m_settings.RRM_FreezeTrailOnFlip)
         {
            m_rrm_trail_frozen = true;
            PrintFormat("RRM Strict trail frozen (PSAR flip): %s", _Symbol);
         }
         return;
      }

      double cushion = RRM_ScalePips(m_settings.PSAR_TrailPipsCushion);
      double new_sl  = isBuy ? NormalizeDouble(psar - cushion, digits)
                              : NormalizeDouble(psar + cushion, digits);

      // Never worsen SL once BE has been reached
      if(m_rrm_be_reached && cur_sl != 0.0)
      {
         if(isBuy  && new_sl < cur_sl) return;
         if(!isBuy && new_sl > cur_sl) return;
      }

      bool can_move = isBuy  ? (new_sl > cur_sl && new_sl < cur_price)
                              : ((cur_sl == 0.0 || new_sl < cur_sl) && new_sl > cur_price);
      if(can_move)
         m_trade.PositionModify(ticket, new_sl, cur_tp);
   }

   //+------------------------------------------------------------------+
   //| HELPER: Normalize trade volume to symbol constraints             |
   //+------------------------------------------------------------------+
   double NormalizeVolume(double vol) {
      double vmin=0.0, vmax=0.0, vstep=0.0;
      if(!SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN, vmin))  vmin = 0.01;
      if(!SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX, vmax))  vmax = 100.0;
      if(!SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP, vstep)) vstep = vmin;
      if(vstep <= 0.0) vstep = vmin;

      // Clamp first
      vol = MathMax(vmin, MathMin(vmax, vol));

      // Step-align (round down to avoid rejection)
      double steps = MathFloor(vol / vstep);
      double aligned = steps * vstep;

      // Derive precision from step size (e.g., 0.01 -> 2 digits)
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

   //+------------------------------------------------------------------+
   //| HELPER: Validate SL/TP distances against broker minimum levels   |
   //| Returns false and prints error if stop levels are violated.      |
   //+------------------------------------------------------------------+
   bool ValidateStopLevels(double entryPrice, double slPrice, double tpPrice)
   {
      long   stops_level_pts = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
      double minStopDist     = stops_level_pts * _Point;
      if(slPrice > 0.0)
      {
         double slDistance = MathAbs(entryPrice - slPrice);
         if(slDistance < minStopDist)
         {
            PrintFormat("ERROR: SL distance (%.5f) < broker min (%.5f, %d pts) — trade aborted",
                        slDistance, minStopDist, (int)stops_level_pts);
            return false;
         }
      }
      if(tpPrice > 0.0)
      {
         double tpDistance = MathAbs(tpPrice - entryPrice);
         if(tpDistance < minStopDist)
         {
            PrintFormat("ERROR: TP distance (%.5f) < broker min (%.5f, %d pts) — trade aborted",
                        tpDistance, minStopDist, (int)stops_level_pts);
            return false;
         }
      }
      return true;
   }

   //+------------------------------------------------------------------+
   //| HELPER: Risk-based position sizing using SL distance             |
   //| Returns 0.0 if sizing cannot be computed.                        |
   //+------------------------------------------------------------------+
   double CalcLotByRisk(double entry_price, double sl_price) {
      if(m_settings.RiskPercent <= 0.0) return 0.0;
      if(sl_price <= 0.0) return 0.0;

      double stop_dist = MathAbs(entry_price - sl_price);
      if(stop_dist <= 0.0) return 0.0;

      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      if(equity <= 0.0) equity = AccountInfoDouble(ACCOUNT_BALANCE);
      if(equity <= 0.0) return 0.0;

      double risk_money = equity * (m_settings.RiskPercent / 100.0);
      if(risk_money <= 0.0) return 0.0;

      // Use LOSS tick value when available for best accuracy
      double tick_size=0.0, tick_value=0.0;
      if(!SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE, tick_size) || tick_size <= 0.0)
         return 0.0;

      if(!SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE_LOSS, tick_value) || tick_value <= 0.0) {
         SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE, tick_value);
      }
      if(tick_value <= 0.0) return 0.0;

      // Money lost for 1.0 lot if SL is hit
      double loss_per_lot = (stop_dist / tick_size) * tick_value;
      if(loss_per_lot <= 0.0) return 0.0;

      double raw_lot = risk_money / loss_per_lot;
      if(raw_lot <= 0.0) return 0.0;
      return NormalizeVolume(raw_lot);
   }


   //+------------------------------------------------------------------+
   //| HELPER: MT5 MovingAverage-style sizing (MaximumRisk/Decrease)    |
   //| Implemented for PRESET_MA.                             |
   //+------------------------------------------------------------------+
   int CountConsecutiveLosses() {
      datetime to = TimeCurrent();
      HistorySelect(0, to);
      int losses = 0;
      int total = HistoryDealsTotal();
      for(int i = total - 1; i >= 0 && losses < 100; i--) {
         ulong deal = HistoryDealGetTicket(i);
         if(deal == 0) continue;
         if(HistoryDealGetString(deal, DEAL_SYMBOL) != _Symbol) continue;
         if((ulong)HistoryDealGetInteger(deal, DEAL_MAGIC) != m_magic) continue;
         long entry = HistoryDealGetInteger(deal, DEAL_ENTRY);
         if(entry != DEAL_ENTRY_OUT) continue;
         double profit = HistoryDealGetDouble(deal, DEAL_PROFIT);
         if(profit < 0.0) {
            losses++;
            continue;
         }
         // Stop at first non-loss close
         break;
      }
      return losses;
   }

   double CalcLotMACompat() {
      // Exact replication of MetaQuotes "Moving Average" EA TradeSizeOptimized():
      // lot = NormalizeDouble(FreeMargin * MaximumRisk / margin_for_1lot_buy, 2)
      // If consecutive losses > 1: lot = NormalizeDouble(lot - lot*losses/DecreaseFactor, 1)
      double mr = m_settings.MA_MaximumRiskPct;
      if(mr <= 0.0) return 0.0;

      double price = 0.0;
      if(!SymbolInfoDouble(_Symbol, SYMBOL_ASK, price))
         return 0.0;

      double margin = 0.0;
      if(!OrderCalcMargin(ORDER_TYPE_BUY, _Symbol, 1.0, price, margin))
         return 0.0;
      if(margin <= 0.0)
         return 0.0;

      double free = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      if(free <= 0.0) return 0.0;

      double lot = NormalizeDouble(free * mr / margin, 2);

      int losses = CountConsecutiveLosses();
      double df = m_settings.MA_DecreaseFactor;
      if(losses > 1 && df > 0.0) {
         lot = NormalizeDouble(lot - lot * losses / df, 1);
      }

      // Clamp to broker constraints, preserving MetaQuotes behavior
      double vmin=0.0, vmax=0.0, vstep=0.0;
      SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN, vmin);
      SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX, vmax);
      SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP, vstep);
      if(vmin <= 0.0) vmin = 0.01;
      if(vstep <= 0.0) vstep = vmin;
      if(vmax <= 0.0) vmax = 100.0;

      if(lot < vmin) lot = vmin;
      if(lot > vmax) lot = vmax;

      // Snap down to step
      lot = MathFloor(lot / vstep) * vstep;
      lot = NormalizeDouble(lot, (int)MathMax(0, (int)MathRound(-MathLog10(vstep))));

      if(lot < vmin) lot = vmin;
      return lot;
   }

   //+------------------------------------------------------------------+
   //| HELPER: Reduce volume to available free margin (safety)          |
   //| Returns 0.0 if even minimum volume is not affordable.            |
   //+------------------------------------------------------------------+
   double AdjustLotForMargin(ENUM_ORDER_TYPE type, double vol, double price) {
      if(vol <= 0.0) return 0.0;

      double free = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      if(free <= 0.0) return 0.0;

      double margin = 0.0;
      if(!OrderCalcMargin(type, _Symbol, vol, price, margin) || margin <= 0.0) {
         // If margin cannot be calculated (broker settings), do not block.
         return vol;
      }
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
   //| HELPER: Scale pips cushion to price distance (TF + JPY aware)    |
   //+------------------------------------------------------------------+
   double ScalePipsToPriceDistance(double base_pips) {
      // Apply timeframe multiplier
      double scaled_pips = base_pips;
      if(_Period == PERIOD_M1)           scaled_pips *= 0.5;
      else if(_Period == PERIOD_M5)      scaled_pips *= 0.8;
      else if(_Period == PERIOD_M15)     scaled_pips *= 1.0;
      else if(_Period >= PERIOD_H1)      scaled_pips *= 2.0;

      // Apply currency pair multiplier
      bool isJPY = (StringFind(_Symbol, "JPY") >= 0);
      double price_distance = scaled_pips * _Point * (isJPY ? 100.0 : 10.0);

      return price_distance;
   }

   //+------------------------------------------------------------------+
   //| HELPER: Calculate SL distance in pips using swing high/low      |
   //| Returns pips distance, or 0 if swing level could not be found.  |
   //+------------------------------------------------------------------+
   double CalculateSwingSL(int direction)
   {
      if(m_settings.SwingLookback <= 0) return 0.0;
      int lb = m_settings.SwingLookback;
      double current_price = (direction > 0) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                              : SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double swing_level = 0.0;
      if(direction > 0)
         swing_level = iLow(_Symbol, PERIOD_CURRENT, iLowest(_Symbol, PERIOD_CURRENT, MODE_LOW, lb, 1));
      else
         swing_level = iHigh(_Symbol, PERIOD_CURRENT, iHighest(_Symbol, PERIOD_CURRENT, MODE_HIGH, lb, 1));

      if(swing_level <= 0.0) return 0.0;

      bool isJPY = (StringFind(_Symbol, "JPY") >= 0);
      double pipSize = _Point * (isJPY ? 100.0 : 10.0);
      double sl_distance = MathAbs(current_price - swing_level);
      return sl_distance / pipSize;
   }

   //+------------------------------------------------------------------+
   //| HELPER: Calculate initial SL price for a given entry             |
   //| Used by both EvaluateCM (lot sizing) and ExecuteTrade (order).   |
   //+------------------------------------------------------------------+
   double CalcEntrySL(bool isBuy, double price)
   {
      double sl = 0.0;
      if(m_settings.ExitProfile == EXIT_PROFILE_RRM)
      {
         sl = RRM_GetStrictSL(isBuy, price);
      }
      else
      {
         bool isJPY = (StringFind(_Symbol, "JPY") >= 0);
         double sl_pips = GetStopLossPips(isBuy ? 1 : -1);
         double dist = sl_pips * _Point * (isJPY ? 100.0 : 10.0);
         sl = isBuy ? (price - dist) : (price + dist);
      }
      return sl;
   }

public:
   CTradeExecutor() : m_last_trade_bar(0), m_last_risk_warn(0),
                      m_rrm_last_ticket(0), m_rrm_trail_frozen(false),
                      m_rrm_be_reached(false), m_rrm_initial_sl(0.0),
                      m_last_te_time(0), m_last_te_result(""), m_last_te_reason("") {}

   //+------------------------------------------------------------------+
   //| INITIALIZATION                                                   |
   //+------------------------------------------------------------------+
   datetime LastTETime()   const { return m_last_te_time;   }
   string   LastTEResult() const { return m_last_te_result; }
   string   LastTEReason() const { return m_last_te_reason; }

   void Init(ulong magic, ST_Settings &sets) {
      m_magic = magic;
      m_settings = sets;
      
      m_trade.SetExpertMagicNumber(m_magic);
      m_trade.SetDeviationInPoints(10);
      m_trade.SetTypeFilling(ORDER_FILLING_IOC);
      m_trade.LogLevel(LOG_LEVEL_ERRORS);
   }
   
   void UpdateSettings(ST_Settings &sets) { 
      m_settings = sets; 
   }


   //==========================================================================
   // Risk Management: Portfolio-Level Gates
   //==========================================================================

   // Calculate current active risk from open positions
   // BE positions count as 0% risk if CountBEasZeroRisk=true
   double CalculateActiveRisk()
   {
      double total_risk = 0.0;

      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         // ✅ MQL5 FIX: Use PositionGetTicket() + PositionSelectByTicket()
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(!PositionSelectByTicket(ticket)) continue;
         
         if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
         if(PositionGetInteger(POSITION_MAGIC) != (long)m_magic) continue;

         // Check if position is at breakeven
         if(m_settings.CountBEasZeroRisk && IsPositionAtBreakEven(ticket))
         {
            if(m_settings.DebugFlow)
               PrintFormat("[RISK] Position #%I64d at BE, risk=0%%", ticket);
            continue;
         }

         // Calculate risk as % of account
         double position_risk = CalculatePositionRisk(ticket);
         total_risk += position_risk;
      }

      return total_risk;
   }

   // Check if position is at breakeven (SL = entry price)
   // ✅ MQL5 FIX: Changed parameter from 'int index' to 'ulong ticket'
   bool IsPositionAtBreakEven(ulong ticket)
   {
      if(!PositionSelectByTicket(ticket)) return false;

      double sl = PositionGetDouble(POSITION_SL);
      double open_price = PositionGetDouble(POSITION_PRICE_OPEN);

      if(sl == 0.0) return false;  // No SL = not at BE

      double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double tolerance = 2.0 * point;  // 2-pip tolerance

      return (MathAbs(sl - open_price) <= tolerance);
   }

   // Calculate risk % for a single position
   // ✅ MQL5 FIX: Changed parameter from 'int index' to 'ulong ticket'
   double CalculatePositionRisk(ulong ticket)
   {
      if(!PositionSelectByTicket(ticket)) return 0.0;

      double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl = PositionGetDouble(POSITION_SL);
      double volume = PositionGetDouble(POSITION_VOLUME);

      if(sl == 0.0) return 0.0;  // No SL = can't calculate risk

      double stop_dist = MathAbs(open_price - sl);
      double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);

      if(tick_size == 0.0 || tick_value == 0.0) return 0.0;

      double ticks = stop_dist / tick_size;
      double risk_money = ticks * tick_value * volume;
      double account_equity = AccountInfoDouble(ACCOUNT_EQUITY);

      if(account_equity == 0.0) return 0.0;

      return (risk_money / account_equity) * 100.0;
   }

   //+------------------------------------------------------------------+
   //| GetStopLossPips: strategy-based SL distance                     |
   //| Returns SL distance in pips based on configured SLMode.         |
   //| Falls back to m_settings.SL_FixedPips if calculation fails.     |
   //+------------------------------------------------------------------+
   double GetStopLossPips(int direction)
   {
      double sl_pips = 0.0;

      switch(m_settings.SLMode)
      {
         case SL_MODE_FIXED_PIPS:
            sl_pips = m_settings.SL_FixedPips;
            break;

         case SL_MODE_PERCENT:
            {
               double entry = (direction > 0) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                              : SymbolInfoDouble(_Symbol, SYMBOL_BID);
               if(entry > 0.0 && m_settings.SLPercent > 0.0)
               {
                  bool isJPY = (StringFind(_Symbol, "JPY") >= 0);
                  double pipSize = _Point * (isJPY ? 100.0 : 10.0);
                  sl_pips = (entry * m_settings.SLPercent / 100.0) / pipSize;
               }
               else
                  sl_pips = m_settings.SL_FixedPips;
            }
            break;

         case SL_MODE_SWING:
            sl_pips = CalculateSwingSL(direction);
            if(sl_pips <= 0.0)
            {
               sl_pips = m_settings.SL_FixedPips;
               if(m_settings.DebugFlow)
                  Print("[CM] Swing SL unavailable, using fixed SL");
            }
            break;

         case SL_MODE_FRACTAL:  // Phase 2.2: Last fractal level
            sl_pips = GetFractalSL(direction);
            if(sl_pips <= 0.0)
            {
               sl_pips = m_settings.SL_FixedPips;
               if(m_settings.DebugFlow)
                  Print("[CM] Fractal SL unavailable, using fixed SL");
            }
            break;

         case SL_MODE_PSAR_DOT:  // Phase 2.2: PSAR dot position
            sl_pips = GetPSARSL(direction);
            if(sl_pips <= 0.0)
            {
               sl_pips = m_settings.SL_FixedPips;
               if(m_settings.DebugFlow)
                  Print("[CM] PSAR SL unavailable, using fixed SL");
            }
            break;

         default:
            sl_pips = m_settings.SL_FixedPips;
            break;
      }

      if(sl_pips <= 0.0)
      {
         if(m_settings.DebugFlow)
            Print("[CM] Invalid SL calculation, using default");
         sl_pips = m_settings.SL_FixedPips;
      }

      return sl_pips;
   }

   //+------------------------------------------------------------------+
   //| GetTakeProfitPips: strategy-based TP distance (ATR optional)    |
   //| Returns TP distance in pips based on configured TPMode.         |
   //| Falls back to m_settings.FixedTPPips if calculation fails.      |
   //+------------------------------------------------------------------+
   double GetTakeProfitPips(int direction)
   {
      double tp_pips = 0.0;

      switch(m_settings.TPMode)
      {
         case TP_MODE_FIXED_PIPS:
            tp_pips = m_settings.FixedTPPips;
            break;

         case TP_MODE_RR:
            {
               double sl_pips = GetStopLossPips(direction);
               tp_pips = (sl_pips > 0.0 && m_settings.RRRatio > 0.0)
                         ? sl_pips * m_settings.RRRatio
                         : m_settings.FixedTPPips;
            }
            break;

         case TP_MODE_FRACTAL:  // Next fractal level as TP target
            tp_pips = GetFractalTP(direction);
            if(tp_pips <= 0.0)
            {
               // Fallback to R:R ratio
               double sl_f = GetStopLossPips(direction);
               tp_pips = (sl_f > 0.0 && m_settings.RRRatio > 0.0)
                         ? sl_f * m_settings.RRRatio
                         : m_settings.FixedTPPips;
               if(m_settings.DebugFlow)
                  Print("[CM] Fractal TP unavailable, using R:R fallback");
            }
            break;

         case TP_MODE_PSAR_FLIP:  // Phase 2.2: Exit managed by PSAR flip in EvaluateTM
            tp_pips = 0.0;   // No fixed TP; PSAR flip exit handled in TM
            break;

         case TP_MODE_NONE:  // Phase 2.2: No TP, rely on trailing stop only
            tp_pips = 0.0;
            break;

         default:
            tp_pips = m_settings.FixedTPPips;
            break;
      }

      // TP_PSAR_FLIP and TP_NONE intentionally return 0 (no fixed TP)
      if(tp_pips <= 0.0 && m_settings.TPMode != TP_MODE_PSAR_FLIP && m_settings.TPMode != TP_MODE_NONE)
         tp_pips = m_settings.FixedTPPips;

      return tp_pips;
   }

   //+------------------------------------------------------------------+
   //| CM: Capital Management — compute lot size for an entry signal   |
   //| Returns lot size (> 0) or 0 if sizing is not possible.          |
   //+------------------------------------------------------------------+
   double EvaluateCM(int direction)
   {
      if(direction == 0) return 0.0;

      bool isBuy = (direction == 1);
      double price = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                           : SymbolInfoDouble(_Symbol, SYMBOL_BID);

      // Determine SL price (same logic as ExecuteTrade for consistent sizing)
      double sl = CalcEntrySL(isBuy, price);

      // Position sizing precedence:
      // 1) MA-compat sizer (PRESET_MA)
      // 2) RiskPercent sizing via SL distance
      // 3) Fallback to minimum volume
      double lot = NormalizeVolume(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN));

      if(m_settings.UseMACompatSizer) {
         double ma_lot = CalcLotMACompat();
         if(ma_lot > 0.0) lot = ma_lot;
      } else {
         double risk_lot = CalcLotByRisk(price, sl);
         if(risk_lot > 0.0) {
            lot = risk_lot;
         } else if(m_settings.RiskPercent > 0.0) {
            datetime now = TimeCurrent();
            if(m_last_risk_warn == 0 || (now - m_last_risk_warn) >= 60) {
               PrintFormat("Risk Sizing: cannot compute volume for %s (RiskPercent=%.2f). Ensure SL is set and symbol tick data is available. Falling back to min volume.",
                           _Symbol, m_settings.RiskPercent);
               m_last_risk_warn = now;
            }
         }
      }

      // Margin safety: scale down if needed
      ENUM_ORDER_TYPE order_type = isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      double adj = AdjustLotForMargin(order_type, lot, price);
      if(adj <= 0.0) {
         if(m_settings.DebugFlow)
            Print("[CM] Lot sizing blocked: insufficient margin");
         return 0.0;
      }
      lot = adj;

      if(m_settings.DebugFlow) {
         double pipScale = (StringFind(_Symbol, "JPY") >= 0) ? 100.0 : 10.0;
         PrintFormat("[CM] SL=%.5f (%.1f pips), Lots=%.2f",
                     sl, sl > 0.0 ? MathAbs(price - sl) / (_Point * pipScale) : 0.0, lot);
      }

      return lot;
   }

   // Check if new trade is allowed based on risk limits
   bool EvaluateRC()
   {
      // Check max open trades limit
      if(m_settings.MaxOpenTrades > 0)
      {
         int open_count = 0;
         for(int i = PositionsTotal() - 1; i >= 0; i--)
         {
            // ✅ MQL5 FIX: Use PositionGetTicket() + PositionSelectByTicket()
            ulong ticket = PositionGetTicket(i);
            if(ticket == 0) continue;
            if(!PositionSelectByTicket(ticket)) continue;
            
            if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
            if(PositionGetInteger(POSITION_MAGIC) != (long)m_magic) continue;
            open_count++;
         }

         if(open_count >= m_settings.MaxOpenTrades)
         {
            if(m_settings.DebugFlow)
               PrintFormat("[RISK BLOCK] Max trades reached: %d/%d",
                          open_count, m_settings.MaxOpenTrades);
            return false;
         }
      }

      // Check max total risk limit
      if(m_settings.MaxTotalRisk > 0.0)
      {
         double current_risk = CalculateActiveRisk();
         double new_trade_risk = m_settings.RiskPercent;

         if(current_risk + new_trade_risk > m_settings.MaxTotalRisk)
         {
            if(m_settings.DebugFlow)
               PrintFormat("[RISK BLOCK] Risk limit: current=%.2f%% + new=%.2f%% > max=%.2f%%",
                          current_risk, new_trade_risk, m_settings.MaxTotalRisk);
            return false;
         }

         if(m_settings.DebugFlow)
            PrintFormat("[RISK OK] current=%.2f%% + new=%.2f%% = %.2f%% <= max=%.2f%%",
                       current_risk, new_trade_risk, current_risk + new_trade_risk,
                       m_settings.MaxTotalRisk);
      }

      return true;
   }

   //+------------------------------------------------------------------+
   //| EXECUTE SIGNAL                                                   |
   //+------------------------------------------------------------------+
   void ExecuteTrade(int direction, double lots) {
      // 1. Check Execution Timing (Avoid multiple entries per bar if not Aggressive)
      // If Vertical Shift is 1 (Closed Bar), we only trade once per bar.
      if(m_settings.ma_v_shift == 1 && m_last_trade_bar == iTime(_Symbol, PERIOD_CURRENT, 0)) {
         m_last_te_time = iTime(_Symbol, PERIOD_CURRENT, 0);
         m_last_te_result = "BLOCKED"; m_last_te_reason = "already traded this bar";
         if(m_settings.DebugFlow) PrintFormat("TE: BLOCKED already traded this bar [%s]", _Symbol);
         return;
      }
   
      // 2. Manage Existing Trades (Hedge-safe): ensure only one net direction
      int buy_count=0, sell_count=0;
      CountMyPositions(buy_count, sell_count);
   
      // If we already have a position in the same direction and no opposite positions -> HOLD
      if(direction == 1 && buy_count > 0 && sell_count == 0) {
         m_last_te_time = iTime(_Symbol, PERIOD_CURRENT, 0);
         m_last_te_result = "BLOCKED"; m_last_te_reason = "already in position";
         if(m_settings.DebugLevel >= DEBUG_SUMMARY)
            Print("[TE] ❌ BLOCKED: already have LONG position");
         return;
      }
      if(direction == -1 && sell_count > 0 && buy_count == 0) {
         m_last_te_time = iTime(_Symbol, PERIOD_CURRENT, 0);
         m_last_te_result = "BLOCKED"; m_last_te_reason = "already in position";
         if(m_settings.DebugLevel >= DEBUG_SUMMARY)
            Print("[TE] ❌ BLOCKED: already have SHORT position");
         return;
      }
   
      // If we have any positions and the signal is opposite -> REVERSE handling
      // MetaQuotes MA benchmark behavior: close on reverse signal, but DO NOT open the opposite trade
      // until a subsequent new-bar check (prevents same-bar stop-and-reverse churn).
      if((buy_count + sell_count) > 0) {
         if(direction != 0 && m_settings.CloseOnReverse) {
            CloseAllMyPositions();
            m_last_trade_bar = iTime(_Symbol, PERIOD_CURRENT, 0);
            if(m_settings.MABenchmarkStrict) {
               m_last_te_time = iTime(_Symbol, PERIOD_CURRENT, 0);
               m_last_te_result = "BLOCKED"; m_last_te_reason = "closed reverse, no new entry (MABench)";
               return;
            }
            // otherwise continue to open the new trade below...
         } else {
            m_last_te_time = iTime(_Symbol, PERIOD_CURRENT, 0);
            m_last_te_result = "BLOCKED"; m_last_te_reason = "already in position, no reverse";
            return;
         }
      }
   
      // 3. Open New Trade
      if(direction == 0) return;
   
      double price = (direction == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl = 0, tp = 0;
      bool isBuy = (direction == 1);

      // =====================================================================
      // ★★★ CALCULATE INITIAL SL AND TP ★★★
      // SL uses shared CalcEntrySL helper (same logic used by EvaluateCM).
      // =====================================================================
      sl = CalcEntrySL(isBuy, price);

      if(m_settings.ExitProfile == EXIT_PROFILE_RRM)
      {
         // Strict non-ATR path: TP computed from actual SL distance
         tp = RRM_GetStrictTP(isBuy, price, sl);
      }
      else
      {
         // Phase 2.2: Handle new TP modes first
         if(m_settings.TPMode == TP_MODE_NONE)
         {
            tp = 0.0;  // No fixed TP; rely on trailing stop
         }
         else if(m_settings.TPMode == TP_MODE_PSAR_FLIP)
         {
            tp = 0.0;  // No fixed TP; PSAR flip exit handled in EvaluateTM
         }
         else if(m_settings.TPMode == TP_MODE_FRACTAL)
         {
            double tp_pips = GetFractalTP(direction == 1 ? 1 : -1);
            if(tp_pips > 0.0)
            {
               bool isJPY = (StringFind(_Symbol, "JPY") >= 0);
               double pipSize = _Point * (isJPY ? 100.0 : 10.0);
               double tp_dist = tp_pips * pipSize;
               tp = isBuy ? (price + tp_dist) : (price - tp_dist);
            }
            else if(sl > 0.0 && m_settings.RRRatio > 0.0)
            {
               // Fallback to R:R ratio
               double sl_dist = MathAbs(price - sl);
               tp = isBuy ? (price + sl_dist * m_settings.RRRatio)
                          : (price - sl_dist * m_settings.RRRatio);
            }
         }
         else if(m_settings.RRRatio > 0) {
            double dist = 0.0;

            // True R:R mode: TP = actual SL distance × R:R ratio
            if(sl > 0) {
               double sl_distance = MathAbs(price - sl);
               if(sl_distance > 0) {
                  dist = sl_distance * m_settings.RRRatio;
               } else {
                  // Fallback to fixed pips if SL distance is zero
                  bool isJPY = (StringFind(_Symbol, "JPY") >= 0);
                  dist = m_settings.SL_FixedPips * _Point * (isJPY ? 100.0 : 10.0) * m_settings.RRRatio;
               }
            } else {
               // Fallback to fixed pips if SL calculation failed
               bool isJPY = (StringFind(_Symbol, "JPY") >= 0);
               dist = m_settings.SL_FixedPips * _Point * (isJPY ? 100.0 : 10.0) * m_settings.RRRatio;
            }

            tp = (direction == 1) ? price + dist : price - dist;
         }
      }
      
      // Normalize Prices
      int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
      if(sl > 0) sl = NormalizeDouble(sl, digits);
      if(tp > 0) tp = NormalizeDouble(tp, digits);
   
      // Execute Order
      ENUM_ORDER_TYPE type = (direction == 1) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      double lot = lots;  // Lot size computed by EvaluateCM
   
      // Build comment showing SL method used
      string comment = StringFormat("SEA_%s", EnumToString(m_settings.SLMode));

      if(m_settings.DebugFlow)
      {
         double pipScale = (StringFind(_Symbol, "JPY") >= 0) ? 100.0 : 10.0;
         PrintFormat("=== TRADE EXECUTION DEBUG ===");
         PrintFormat("  SL Mode: %s", EnumToString(m_settings.SLMode));
         PrintFormat("  Entry: %.5f", price);
         PrintFormat("  SL: %.5f (distance: %.1f pips)", sl, sl > 0.0 ? MathAbs(price - sl) / (_Point * pipScale) : 0.0);
         PrintFormat("  TP: %.5f (distance: %.1f pips)", tp, tp > 0.0 ? MathAbs(tp - price) / (_Point * pipScale) : 0.0);
         PrintFormat("  Broker Min Stop: %.5f (%d pts)", SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point, (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL));
      }

      if(!ValidateStopLevels(price, sl, tp))
      {
         m_last_te_time = iTime(_Symbol, PERIOD_CURRENT, 0);
         m_last_te_result = "BLOCKED"; m_last_te_reason = "stop level validation failed";
         if(m_settings.DebugLevel >= DEBUG_SUMMARY)
            PrintFormat("[TE] ❌ BLOCKED: stop levels invalid (SLMode=%s, Entry=%.5f, SL=%.5f, TP=%.5f)",
                        EnumToString(m_settings.SLMode), price, sl, tp);
         return;
      }

      if(m_trade.PositionOpen(_Symbol, type, lot, price, sl, tp, comment)) {
         m_last_te_time = iTime(_Symbol, PERIOD_CURRENT, 0);
         m_last_te_result = "ENTERED";
         m_last_te_reason = StringFormat("@%.5f tk=%I64u", price, m_trade.ResultDeal());
         Print("Signal Executed: ", EnumToString(type), " at ", price, 
               " | SL: ", sl, " (", EnumToString(m_settings.SLMode), ")",
               " | TP: ", tp,
               " | [Shift: ", m_settings.ma_v_shift, "]");
         m_last_trade_bar = iTime(_Symbol, PERIOD_CURRENT, 0);
         if(m_settings.ExitProfile == EXIT_PROFILE_RRM)
         {
            m_rrm_initial_sl   = sl;
            m_rrm_be_reached   = false;
            m_rrm_trail_frozen = false;
            m_rrm_last_ticket  = 0; // will sync on next EvaluateTM call
         }
         // Visualization: executed trade marker
         if(Inp_DrawTradeLines)
            SEA_DrawTradeExecLine(TimeCurrent(), direction, price, EnumToString(type));
      } else {
         m_last_te_time = iTime(_Symbol, PERIOD_CURRENT, 0);
         m_last_te_result = "BLOCKED";
         m_last_te_reason = StringFormat("order rejected (%d)", (int)m_trade.ResultRetcode());
         if(m_settings.DebugLevel >= DEBUG_SUMMARY)
            PrintFormat("[TE] ❌ OrderSend FAILED: retcode=%d (%s) | %s | Entry=%.5f SL=%.5f TP=%.5f",
                        (int)m_trade.ResultRetcode(), m_trade.ResultComment(),
                        type == ORDER_TYPE_BUY ? "BUY" : "SELL", price, sl, tp);
      }
   }

   //+------------------------------------------------------------------+
   //| EvaluateTE - Complete Trade Entry                                |
   //| Handles: Filters → Risk Check → Position Sizing → Order Execute  |
   //| Returns: 1 = trade entered, 0 = rejected or failed              |
   //+------------------------------------------------------------------+
   int EvaluateTE(int ts_direction)
   {
      if(ts_direction == 0) return 0;

      if(m_settings.DebugFlow)
         PrintFormat("[TE] Starting trade entry evaluation for direction=%d", ts_direction);

      // Track per-step results for pipeline summary
      string te_reject_reason  = "";
      bool   te_spread_pass    = true;
      double te_spread_pips    = 0.0;
      bool   te_time_pass      = true;
      bool   te_time_checked   = false;  // true only when time check was actually run
      bool   te_rc_pass        = false;
      bool   te_rc_checked     = false;  // true only when RC check was actually run
      bool   te_lots_pass      = false;
      bool   te_lots_checked   = false;  // true only when lot sizing was actually run
      double te_lots           = 0.0;
      int    result            = 0;

      // ═══════════════════════════════════════════════════════
      // STEP 1: Check Execution Filters
      // ═══════════════════════════════════════════════════════

      // Check spread
      if(m_settings.UseSpread && m_settings.MaxSpread > 0) {
         bool isJPY = (StringFind(_Symbol, "JPY") >= 0);
         double pipSize = _Point * (isJPY ? 100.0 : 10.0);
         te_spread_pips = (SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * _Point) / pipSize;
         te_spread_pass = (te_spread_pips <= m_settings.MaxSpread);
         if(!te_spread_pass) {
            if(m_settings.DebugFlow)
               PrintFormat("[TE] Rejected: Spread %.1f > max %.1f pips",
                           te_spread_pips, m_settings.MaxSpread);
            te_reject_reason = "SPREAD";
         }
      }

      // Check trading hours
      if(te_reject_reason == "" && m_settings.UseTime) {
         MqlDateTime dt;
         TimeToStruct(TimeCurrent(), dt);
         te_time_checked = true;
         te_time_pass = (m_settings.StartHr < m_settings.EndHr) ?
                        (dt.hour >= m_settings.StartHr && dt.hour < m_settings.EndHr) :
                        (dt.hour >= m_settings.StartHr || dt.hour < m_settings.EndHr);
         if(!te_time_pass) {
            if(m_settings.DebugFlow)
               PrintFormat("[TE] Rejected: Outside trading hours (hour=%d)", dt.hour);
            te_reject_reason = "TIME";
         }
      }

      // ═══════════════════════════════════════════════════════
      // STEP 2: Check Risk Control
      // ═══════════════════════════════════════════════════════
      if(te_reject_reason == "") {
         te_rc_checked = true;
         te_rc_pass = EvaluateRC();
         if(!te_rc_pass) {
            if(m_settings.DebugFlow)
               Print("[TE] Rejected: Risk control blocked entry");
            te_reject_reason = "RISK_CONTROL";
         }
      }

      // ═══════════════════════════════════════════════════════
      // STEP 3: Calculate Position Size
      // ═══════════════════════════════════════════════════════
      if(te_reject_reason == "") {
         te_lots_checked = true;
         te_lots = EvaluateCM(ts_direction);
         te_lots_pass = (te_lots > 0);
         if(!te_lots_pass) {
            if(m_settings.DebugFlow)
               Print("[TE] Rejected: Invalid lot size");
            te_reject_reason = "INVALID_LOT_SIZE";
         }
      }

      // ═══════════════════════════════════════════════════════
      // STEP 4: Execute Order
      // ═══════════════════════════════════════════════════════
      if(te_reject_reason == "") {
         if(m_settings.DebugFlow)
            PrintFormat("[TE] Position size: %.2f lots", te_lots);

         ExecuteTrade(ts_direction, te_lots);

         result = (m_last_te_result == "ENTERED") ? 1 : 0;
         if(result == 0 && te_reject_reason == "")
            te_reject_reason = m_last_te_reason;

         if(m_settings.DebugFlow) {
            if(result == 1)
               PrintFormat("[TE] ✅ SUCCESS - Trade entered: %s %.2f lots",
                           (ts_direction > 0 ? "BUY" : "SELL"), te_lots);
            else
               PrintFormat("[TE] ❌ FAILED/REJECTED - %s", m_last_te_reason);
         }
      }

      // ===== TE PIPELINE SUMMARY =====
      if(m_settings.DebugFlow) {
         Print("════════════════════════════════════════════════════════════");
         PrintFormat("[TE_SUMMARY] Direction: %s", ts_direction > 0 ? "LONG" : "SHORT");
         Print("════════════════════════════════════════════════════════════");
         Print("");

         Print("GATES:");
         if(m_settings.UseSpread && m_settings.MaxSpread > 0) {
            PrintFormat("  %s Spread: %.1f / %.1f pips max",
                        te_spread_pass ? "✅" : "❌", te_spread_pips, m_settings.MaxSpread);
         } else {
            Print("  ⏭️  Spread: disabled");
         }
         if(m_settings.UseTime) {
            if(te_time_checked)
               PrintFormat("  %s Time window: active", te_time_pass ? "✅" : "❌");
            else
               Print("  ⏭️  Time window: not evaluated");
         } else {
            Print("  ⏭️  Time window: disabled");
         }
         if(te_rc_checked)
            PrintFormat("  %s Risk control", te_rc_pass ? "✅" : "❌");
         else
            Print("  ⏭️  Risk control: not evaluated");
         if(te_lots_checked)
            PrintFormat("  %s Position size: %.2f lots", te_lots_pass ? "✅" : "❌", te_lots);
         else
            Print("  ⏭️  Position size: not evaluated");
         Print("");

         Print("════════════════════════════════════════════════════════════");
         if(result == 1) {
            PrintFormat("[TE_RESULT] ✅✅✅ TRADE ENTERED: %s %.2f lots ✅✅✅",
                        ts_direction > 0 ? "LONG" : "SHORT", te_lots);
         } else {
            PrintFormat("[TE_RESULT] ❌ REJECTED - Reason: %s", te_reject_reason);
         }
         Print("════════════════════════════════════════════════════════════");
         Print("");
      }
      // ===== TE PIPELINE SUMMARY: END =====

      // DEBUG_SUMMARY: compact 1-line result shown only when DebugFlow (DEBUG_FULL) is off,
      // since DEBUG_FULL already prints the full TE_PIPELINE_SUMMARY above.
      if(m_settings.DebugLevel >= DEBUG_SUMMARY && !m_settings.DebugFlow)
      {
         if(result == 1)
            PrintFormat("[TE] ✅ Trade entered: %s %.2f lots",
                        ts_direction > 0 ? "LONG" : "SHORT", te_lots);
         else
            PrintFormat("[TE] ❌ Trade rejected: %s (direction=%s)",
                        te_reject_reason, ts_direction > 0 ? "LONG" : "SHORT");
      }

      return result;
   }

   //+------------------------------------------------------------------+
   //| MANAGE OPEN TRADE (Trailing / Breakeven)                         |
   //+------------------------------------------------------------------+
   void EvaluateTM() {
      ulong ticket = GetMyPosition();
      if(ticket == 0 || !PositionSelectByTicket(ticket)) return;

      // Dispatch to strict non-ATR path if configured
      if(m_settings.ExitProfile == EXIT_PROFILE_RRM)
      {
         RRM_ManageStrictNoATR(ticket);
         return;
      }

      // 1. Trailing Stop Logic (Allows Profit to Run)
      if(m_settings.TrailMode == TRAIL_NONE) return;

      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double current_sl       = PositionGetDouble(POSITION_SL);
      double current_tp       = PositionGetDouble(POSITION_TP);
      double current_price    = PositionGetDouble(POSITION_PRICE_CURRENT);
      double entry_price      = PositionGetDouble(POSITION_PRICE_OPEN);
      int    direction        = (type == POSITION_TYPE_BUY) ? 1 : -1;
      double new_sl           = 0.0;

      bool   isJPY    = (StringFind(_Symbol, "JPY") >= 0);
      double pipSize  = _Point * (isJPY ? 100.0 : 10.0);
      double profit_pips = (direction > 0) ? (current_price - entry_price) / pipSize
                                           : (entry_price - current_price) / pipSize;

      // Phase 2.2: PSAR flip exit — close position immediately when PSAR flips
      if(m_settings.TrailMode == TRAIL_PSAR_FLIP_EXIT ||
         m_settings.TPMode    == TP_MODE_PSAR_FLIP)
      {
         if(CheckPSARFlip(direction, current_price))
         {
            if(m_settings.DebugFlow)
               PrintFormat("[TM] PSAR flip detected, closing position (ticket=%I64u)", ticket);
            m_trade.PositionClose(ticket);
            return;
         }
         // If only TP_PSAR_FLIP (not TRAIL_PSAR_FLIP_EXIT), skip further trailing for this mode
         if(m_settings.TrailMode == TRAIL_PSAR_FLIP_EXIT) return;
      }

      // Phase 2.2: Check trailing trigger condition before applying trail
      bool should_trail = CheckTrailTrigger(direction, profit_pips, entry_price, current_price);
      if(!should_trail) return;

      // Calculate new Stop based on Mode
      if(m_settings.TrailMode == TRAIL_PSAR) {
         // Trail stop to PSAR with fixed pips cushion.
         // Uses configurable bar-shift delay to avoid intra-bar repainting.
         int psar_shift = m_settings.PSAR_TrailDelay;
         if(psar_shift < 1) psar_shift = 1;
         if(psar_shift > 3) psar_shift = 3;
         double psar = GetPsarForTrail(psar_shift);
         if(psar > 0.0) {
            double cushion = 0.0;

            // Calculate cushion (TF-based, already set in Settings.PSAR_TrailPipsCushion)
            cushion = ScalePipsToPriceDistance(m_settings.PSAR_TrailPipsCushion);

            new_sl = (type == POSITION_TYPE_BUY) ? (psar - cushion) : (psar + cushion);
         }
      }
      else if(m_settings.TrailMode == TRAIL_FRACTAL) {
         double val = (type == POSITION_TYPE_BUY) ? GetFractalForTrail(1) : GetFractalForTrail(0);
         if(val > 0) new_sl = val;
      }
      else if(m_settings.TrailMode == TRAIL_FIXED_PIPS) {
         // Phase 2.2: Fixed pips trailing stop
         double trail_dist = m_settings.TrailDistancePips * pipSize;
         new_sl = (type == POSITION_TYPE_BUY) ? (current_price - trail_dist)
                                              : (current_price + trail_dist);
      }
      else if(m_settings.TrailMode == TRAIL_BREAKEVEN) {
         // Phase 2.2: Move SL to breakeven once threshold reached, then trail
         double be_dist = m_settings.BEThresholdPips * pipSize;
         bool at_or_past_be = (current_sl > 0.0) &&
            ((type == POSITION_TYPE_BUY  && current_sl >= entry_price) ||
             (type == POSITION_TYPE_SELL && current_sl <= entry_price));

         if(at_or_past_be)
         {
            // Already past BE: trail with fixed pips
            double trail_dist = m_settings.TrailDistancePips * pipSize;
            new_sl = (type == POSITION_TYPE_BUY) ? (current_price - trail_dist)
                                                 : (current_price + trail_dist);
         }
         else if(profit_pips * pipSize >= be_dist)
         {
            // Reached threshold: move to breakeven
            new_sl = entry_price;
         }
      }
      else if(m_settings.TrailMode == TRAIL_PROFIT_PERCENT) {
         // Phase 2.2: Trail after profit % threshold; uses TrailDistancePips once triggered
         double trail_dist = m_settings.TrailDistancePips * pipSize;
         new_sl = (type == POSITION_TYPE_BUY) ? (current_price - trail_dist)
                                              : (current_price + trail_dist);
      }

      // Execute Modification if valid and moving in profit direction
      if(new_sl != 0.0) {
         int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
         new_sl = NormalizeDouble(new_sl, digits);
         bool modify = false;
         
         if(type == POSITION_TYPE_BUY) {
            // Only move SL upward; respect minimum step
            bool improves = (current_sl == 0.0 || new_sl > current_sl);
            bool above_entry = !m_settings.TrailLockProfit || (new_sl >= 0.0);  // always allow initial SL
            double sl_change = MathAbs(new_sl - current_sl) / pipSize;
            bool step_ok = (current_sl == 0.0 || sl_change >= m_settings.TrailStepPips ||
                            m_settings.TrailStepPips <= 0.0);
            if(improves && new_sl < current_price && step_ok) modify = true;
         } 
         else {
            // Only move SL downward; respect minimum step
            bool improves = (current_sl == 0.0 || new_sl < current_sl);
            double sl_change = MathAbs(new_sl - current_sl) / pipSize;
            bool step_ok = (current_sl == 0.0 || sl_change >= m_settings.TrailStepPips ||
                            m_settings.TrailStepPips <= 0.0);
            if(improves && new_sl > current_price && step_ok) modify = true;
         }
         
         if(modify) {
            if(m_trade.PositionModify(ticket, new_sl, current_tp)) {
               // Log successful trailing SL modification
               if(m_settings.DebugFlow)
                  PrintFormat("[TM] Trailing SL updated: %s | New SL: %.5f (%s %s)",
                              EnumToString(m_settings.TrailMode),
                              new_sl, _Symbol, EnumToString(ENUM_TIMEFRAMES(_Period)));
            }
         }
      }
   }
};