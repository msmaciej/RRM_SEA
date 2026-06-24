//==============================================================================
// SEA_SignalEngine.mqh
// RRM SEA Trading System v1.02
//==============================================================================
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
//==============================================================================

#property strict
#include "SEA_Config.mqh"

class SEA_SignalEngine
{
private:
   // ... existing member variables ...

public:
   // ... existing functions ...

   //==========================================================================
   // GetDirection() - Main Signal Processing Pipeline
   //==========================================================================
   // This function implements the 9-step signal validation pipeline.
   // Each step must pass before moving to the next.
   // If any step fails, the function returns 0 (no trade).
   //
   // PROCESS FLOW:
   // 1. PRE-FILTERS: Spread, ATR, time checks
   // 2. MARKET BIAS: Check EMA position and slopes
   //    - LONG: Fast > Slow AND both rising
   //    - SHORT: Fast < Slow AND both falling
   //    - NEUTRAL: Neither condition met -> REJECT
   // 3. AUTOSTRAT: Generate entry signal based on strategy
   //    - STRAT_SINGLE_SLOPE: Single EMA direction
   //    - STRAT_PRICE_CROSS: Price vs EMA
   //    - STRAT_PAIR_CROSS: EMA crossover (relaxed bias logic)
   // 4. SIGNAL VALIDATION: Entry signal must match bias
   // 5. HTF FILTER: Higher timeframe must agree with bias
   // 6. RRM GATES: Check pullback/divergence if enabled
   // 7. VOTING BYPASS: Skip voting if threshold <= 1
   // 8. INDICATOR VOTING: Count indicator confirmations
   // 9. FINAL DECISION: Accept if votes >= threshold
   //
   // RETURNS: 1 (LONG), -1 (SHORT), 0 (NO TRADE)
   //==========================================================================
   
   int GetDirection() 
   {
      // Diagnostics reset
      m_diag_last_bias   = 0;
      m_diag_last_votes  = 0;
      m_diag_last_reason = "";

      //------------------------------------------------------------------------
      // STEP 1: PRE-FILTERS
      //------------------------------------------------------------------------
      // Check spread, ATR range, time filters, etc.
      // If any filter fails, reject immediately
      //------------------------------------------------------------------------
      
      if(!CheckFilters()) return 0;

      // Master bias gate
      if(!m_settings.BiasEnabled) { 
         m_diag_last_reason="BIAS_DISABLED"; 
         return 0; 
      }

      // Use bar shift from settings (0=current bar, 1=closed bar)
      int v_shift = m_settings.ma_v_shift;
      
      //------------------------------------------------------------------------
      // STEP 2: MARKET BIAS DETERMINATION
      //------------------------------------------------------------------------
      // Establish primary trend direction using EMA position and slope.
      // This is the master filter - no trades allowed without valid bias.
      //
      // LONG BIAS: Fast EMA > Slow EMA AND both rising
      // SHORT BIAS: Fast EMA < Slow EMA AND both falling
      // NEUTRAL: Neither condition met (conflicting signals)
      //
      // Note: STRAT_PAIR_CROSS uses relaxed logic (only Fast slope required)
      //       Other strategies require both slopes aligned
      //------------------------------------------------------------------------
      
      int bias = 0;
      
      if(m_settings.BiasMode == BIAS_MANUAL) {
         // Manual mode: User forces direction or uses SIDE_BOTH
         
         if(m_settings.ManSide == SIDE_LONG)
            bias = 1;
         else if(m_settings.ManSide == SIDE_SHORT)
            bias = -1;
         else
         {
            // SIDE_BOTH: Fall back to AUTO bias logic
            
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
             
            // Determine market bias
            int market_bias = 0;
            
            // STRAT_PAIR_CROSS: Relaxed requirements (crossover is the signal)
            if(m_settings.AutoStrat == STRAT_PAIR_CROSS) {
               // Only require: Fast position correct + Fast slope correct
               // Don't require Slow slope - crossover indicates momentum shift
               if(f_curr > s_curr && fast_slope == 1)
                  market_bias = 1;
               else if(f_curr < s_curr && fast_slope == -1)
                  market_bias = -1;
               else
                  market_bias = 0;
            }
            else {
               // OTHER STRATEGIES: Strict requirements (both EMAs must align)
               // LONG: Fast > Slow AND both rising
               // SHORT: Fast < Slow AND both falling
               if(f_curr > s_curr && fast_slope == 1 && slow_slope == 1)
                  market_bias = 1;
               else if(f_curr < s_curr && fast_slope == -1 && slow_slope == -1)
                  market_bias = -1;
               else
                  market_bias = 0;
            }
             
            // If no valid market bias, reject immediately
            if(market_bias == 0) {
               bias = 0;
            }
            else {
               //------------------------------------------------------------------
               // STEP 3: AUTOSTRAT ENTRY SIGNAL GENERATION
               //------------------------------------------------------------------
               // Generate entry timing signal within bias context.
               // Signal must match bias direction to be valid.
               //------------------------------------------------------------------
               
               int entry_signal = 0;
                
               if(m_settings.AutoStrat == STRAT_SINGLE_SLOPE) {
                  // Strategy: Single EMA slope direction
                  entry_signal = GetSlope(hf);
               }
               else if(m_settings.AutoStrat == STRAT_PRICE_CROSS) {
                  // Strategy: Price vs EMA
                  if(m_settings.RequirePriceCross) {
                     entry_signal = PriceCrossDirection(hf, v_shift);
                  } else {
                     double price = iClose(m_symbol, PERIOD_CURRENT, v_shift);
                     double ma    = GetMAVal(hf, v_shift, 0);
                     entry_signal = (price > ma) ? 1 : -1;
                  }
               }
               else {  
                  // STRAT_PAIR_CROSS: EMA crossover detection
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
                  else
                     entry_signal = 0;
               }
                
               //------------------------------------------------------------------
               // STEP 4: SIGNAL VALIDATION
               //------------------------------------------------------------------
               // Entry signal must match market bias direction
               //------------------------------------------------------------------
               
               if(entry_signal == market_bias)
                  bias = market_bias;
               else
                  bias = 0;
            }
         }
      }
      else {
         // AUTO MODE: Dynamic bias determination
         
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
         
         // Determine market bias
         int market_bias = 0;
         
         // STRAT_PAIR_CROSS: Relaxed requirements
         if(m_settings.AutoStrat == STRAT_PAIR_CROSS) {
            if(f_curr > s_curr && fast_slope == 1)
               market_bias = 1;
            else if(f_curr < s_curr && fast_slope == -1)
               market_bias = -1;
            else
               market_bias = 0;
         }
         else {
            // OTHER STRATEGIES: Strict requirements
            if(f_curr > s_curr && fast_slope == 1 && slow_slope == 1)
               market_bias = 1;
            else if(f_curr < s_curr && fast_slope == -1 && slow_slope == -1)
               market_bias = -1;
            else
               market_bias = 0;
         }
         
         // If no valid market bias, reject immediately
         if(market_bias == 0) {
            bias = 0;
         }
         else {
            // STEP 3: AUTOSTRAT ENTRY SIGNAL
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
            else {
               // STRAT_PAIR_CROSS
               double f_curr_cross = GetMAVal(hf, v_shift, 0);
               double f_prev_cross = GetMAVal(hf, v_shift + 1, 0);
               double s_curr_cross = GetMAVal(hs, v_shift, 0);
               double s_prev_cross = GetMAVal(hs, v_shift + 1, 0);
               
               if(f_prev_cross <= s_prev_cross && f_curr_cross > s_curr_cross)
                  entry_signal = 1;
               else if(f_prev_cross >= s_prev_cross && f_curr_cross < s_curr_cross)
                  entry_signal = -1;
               else
                  entry_signal = 0;
            }
            
            // STEP 4: SIGNAL VALIDATION
            if(entry_signal == market_bias)
               bias = market_bias;
            else
               bias = 0;
         }
      }
      
      m_diag_last_bias = bias;

      if(bias == 0) { 
         m_diag_last_reason="BIAS_ZERO"; 
         return 0; 
      }

      //------------------------------------------------------------------------
      // STEP 5: HTF (HIGHER TIMEFRAME) FILTER
      //------------------------------------------------------------------------
      // Check if higher timeframe EMA slope agrees with bias direction.
      // If HTF doesn't agree, reject the trade.
      //------------------------------------------------------------------------
      
      if(m_settings.UseHTF) {
         double curr = GetMAVal(h_htf_ema, 1);
         double prev = GetMAVal(h_htf_ema, 2);
         int htf_dir = (curr > prev) ? 1 : -1;
         
         if(bias != htf_dir) { 
            m_diag_last_reason="HTF_VETO"; 
            return 0; 
         }
      }

      //------------------------------------------------------------------------
      // STEP 6: RRM MANDATORY GATES (Optional)
      //------------------------------------------------------------------------
      // Additional quality filters when enabled:
      // - RRM_RequirePullbackReclaim: Price must pull back to Fast EMA then reclaim
      // - RRM_RequireEmaDiv: EMAs must be expanding (not converging)
      //------------------------------------------------------------------------
      
      if(m_settings.RRM_RequirePullbackReclaim) {
         if(!Check_RRM_PullbackReclaim(bias)) { 
            m_diag_last_reason="RRM_PULLBACK"; 
            return 0; 
         }
      }
      if(m_settings.RRM_RequireEmaDiv) {
         if(!Check_RRM_EmaDiv(bias)) { 
            m_diag_last_reason="RRM_EMA_DIV"; 
            return 0; 
         }
      }

      //------------------------------------------------------------------------
      // STEP 7: VOTING BYPASS CHECK
      //------------------------------------------------------------------------
      // If VoteThreshold <= 1, skip indicator voting (fast mode)
      //------------------------------------------------------------------------
      
      if(m_settings.VoteThreshold <= 1) { 
         m_diag_last_votes=0; 
         m_diag_last_reason="BYPASS"; 
         return bias; 
      }

      //------------------------------------------------------------------------
      // STEP 8: INDICATOR VOTING
      //------------------------------------------------------------------------
      // Each enabled indicator votes if it agrees with the bias.
      // Count total votes from all enabled indicators.
      //------------------------------------------------------------------------
      
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
         if(m_diag_last_atr_ok) votes++;
      }

      m_diag_last_votes = votes;

      //------------------------------------------------------------------------
      // DIAGNOSTIC LOGGING (Tester Mode Only)
      //------------------------------------------------------------------------
      // Log detailed vote information for analysis
      //------------------------------------------------------------------------
      
      #ifdef __MQL5__
      if(MQLInfoInteger(MQL_TESTER)) {
         datetime bar_time = iTime(m_symbol, PERIOD_CURRENT, v_shift);
         string vote_details = StringFormat("VOTE_DETAIL[%s]: bias=%d v_shift=%d votes=%d/%d",
                                            TimeToString(bar_time),
                                            bias, v_shift, votes, m_settings.VoteThreshold);
         
         // Log each enabled indicator with values
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

      //------------------------------------------------------------------------
      // STEP 9: FINAL DECISION
      //------------------------------------------------------------------------
      // If votes meet threshold, accept signal. Otherwise reject.
      //------------------------------------------------------------------------

      if(votes >= m_settings.VoteThreshold) { 
         m_diag_last_reason="OK"; 
         return bias; 
      }
      
      m_diag_last_reason = StringFormat("VOTES %d/%d", votes, m_settings.VoteThreshold);
      return 0;
      
   } // End of GetDirection()

   // ... rest of the class ...

}; // End of SEA_SignalEngine class