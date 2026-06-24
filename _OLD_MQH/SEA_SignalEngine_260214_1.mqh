//+------------------------------------------------------------------+
//|                                           SEA_SignalEngine.mqh    |
//|                                  RRM SEA Trading System v1.02     |
//|                                                                    |
//| PURPOSE:                                                           |
//|   Core signal processing engine implementing 9-step pipeline      |
//|                                                                    |
//| ARCHITECTURE:                                                      |
//|   ┌─────────────────────────────────────────────────────────┐   |
//|   │  STEP 1: PRE-FILTERS (Spread, ATR, Time)               │   |
//|   │  STEP 2: MARKET BIAS (EMA position + slope)            │   |
//|   │  STEP 3: AUTOSTRAT SIGNAL (Entry timing)               │   |
//|   │  STEP 4: SIGNAL VALIDATION (Match bias)                │   |
//|   │  STEP 5: HTF FILTER (Higher timeframe)                 │   |
//|   │  STEP 6: RRM GATES (Pullback/Divergence)               │   |
//|   │  STEP 7: VOTING BYPASS (Threshold check)               │   |
//|   │  STEP 8: INDICATOR VOTING (Consensus)                  │   |
//|   │  STEP 9: FINAL DECISION (Accept/Reject)                │   |
//|   └────────────────────────────────────��────────────────────┘   |
//|                                                                    |
//| KEY CONCEPTS:                                                      |
//|   - Market Bias: Primary trend filter (LONG/SHORT/NEUTRAL)        |
//|   - Entry Signal: Timing within bias context                      |
//|   - Voting: Indicators confirm or reject bias                     |
//|                                                                    |
//| MAIN FUNCTIONS:                                                    |
//|   GetDirection() - Main signal pipeline (returns 1/-1/0)          |
//|   CheckFilters() - Pre-filters (spread, ATR, time)                |
//|   Check_*()      - Individual indicator voting functions          |
//|                                                                    |
//| See README.md for complete documentation                           |
//+------------------------------------------------------------------+

#property strict
#include "SEA_Config.mqh"

class SEA_SignalEngine
{
private:
   // ... existing member variables ...

public:
   // ... existing functions ...

   //=============================================================================
   // GetDirection() - Main Signal Processing Pipeline
   //=============================================================================
   // PROCESS FLOW:
   // 1. PRE-FILTERS: Check spread, ATR, time filters
   // 2. MARKET BIAS: Determine if trend is LONG (1), SHORT (-1), or NEUTRAL (0)
   //    - Uses BiasFast/BiasSlow EMAs
   //    - Checks position (Fast vs Slow) AND slope (both rising/falling)
   //    - If NEUTRAL → REJECT immediately (no valid trend)
   // 3. AUTOSTRAT: Generate entry signal (if bias valid)
   //    - STRAT_SINGLE_SLOPE: Single EMA slope direction
   //    - STRAT_PRICE_CROSS: Price vs EMA position/cross
   //    - STRAT_PAIR_CROSS: EMA crossover detection
   // 4. SIGNAL VALIDATION: Entry signal must match market bias
   // 5. HTF FILTER: Higher timeframe trend must align with bias
   // 6. RRM GATES: Optional pullback/divergence requirements
   // 7. VOTING: Indicators vote to confirm signal (MACD, CCI, PSAR, etc.)
   // 8. FINAL DECISION: Return bias if all checks pass, otherwise 0
   //=============================================================================
   
   int GetDirection() 
   {
      // (Full implementation with detailed inline comments as provided earlier)
      // ...
   }

   // ... rest of the class ...
};