# RRM SEA (Signal Engine Architecture) - Trading System

## Overview

**RRM SEA** is a professional-grade algorithmic trading system for MetaTrader 5, implementing **Real Risk Money (RRM) methodology** combined with a modular signal engine architecture.

## System Architecture

### Signal Processing Pipeline

The system uses a **9-step sequential pipeline** to generate and validate trading signals:

```
┌─────────────────────────────────────────────────────────────┐
│  STEP 1: PRE-FILTERS                                        │
│  ├─ Spread check (MaxSpreadPips)                            │
│  ├─ ATR volatility range (MinATR, MaxATR)                   │
│  └─ Time/session filters                                    │
│  → REJECT if any filter fails                               │
└─────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────┐
│  STEP 2: MARKET BIAS DETERMINATION                          │
│  ├─ Check EMA position: Fast vs Slow                        │
│  ├─ Check EMA slopes: Both rising/falling?                  │
│  ├─ Result: LONG (1), SHORT (-1), or NEUTRAL (0)           │
│  └─ Strategy-dependent relaxation:                          │
│      • STRAT_PAIR_CROSS: Only Fast slope required           │
│      • Other strategies: Both slopes required               │
│  → REJECT if NEUTRAL (no clear trend)                       │
└─────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────┐
│  STEP 3: AUTOSTRAT ENTRY SIGNAL                             │
│  ├─ STRAT_SINGLE_SLOPE: Single EMA direction                │
│  ├─ STRAT_PRICE_CROSS: Price vs EMA                         │
│  └─ STRAT_PAIR_CROSS: EMA crossover                         │
│  → Generate entry_signal (1/-1/0)                           │
└─────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────┐
│  STEP 4: SIGNAL VALIDATION                                  │
│  ├─ Entry signal must match market bias                     │
│  └─ If mismatch → REJECT                                    │
└─────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────┐
│  STEP 5: HTF (Higher Timeframe) FILTER                      │
│  ├─ Check HTF EMA slope                                     │
│  └─ Must align with bias → or REJECT                        │
└─────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────┐
│  STEP 6: RRM MANDATORY GATES (Optional)                     │
│  ├─ RRM_RequirePullbackReclaim:                             │
│  │   • Wait for price to pull back to Fast EMA             │
│  │   • Then reclaim (cross back above/below)               │
│  │   • Result: Better entry prices, fewer trades           │
│  └─ RRM_RequireEmaDiv:                                      │
│      • Require EMAs to be diverging (expanding)             │
│      • Avoid entries during EMA convergence                 │
│  → REJECT if enabled gates not satisfied                    │
└─────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────┐
│  STEP 7: VOTING BYPASS CHECK                                │
│  └─ If VoteThreshold <= 1 → ACCEPT (fast mode)              │
└─────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────┐
│  STEP 8: INDICATOR VOTING                                   │
│  ├─ Each enabled indicator votes if it agrees with bias:    │
│  │   • EMA1 (price position)                                │
│  │   • ADX (trend strength)                                 │
│  │   • MACD (momentum)                                      │
│  │   • CCI (momentum)                                       │
│  │   • RSI (momentum zones)                                 │
│  │   • Stochastic (momentum zones)                          │
│  │   • PSAR (trend direction)                               │
│  │   • Bollinger Bands (volatility)                         │
│  │   • MFI (money flow)                                     │
│  │   • P123 (pattern)                                       │
│  │   • Ross Hook (pattern)                                  │
│  └─ Count total votes                                       │
└─────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────┐
│  STEP 9: FINAL DECISION                                     │
│  ├─ If votes >= VoteThreshold → ACCEPT signal               │
│  └─ Otherwise → REJECT                                      │
└─────────────────────────────────────────────────────────────┘
```

---

## Key Concepts

### 1. Market Bias vs Entry Signal

**Market Bias** = Primary trend filter
- Determines if market is in LONG, SHORT, or NEUTRAL state
- Based on EMA position and slope alignment
- Acts as **master filter** - no trades against bias

**Entry Signal** = Timing within bias context
- Generated by AutoStrat strategy
- Only evaluated if valid bias exists
- Must match bias direction to be accepted

### 2. AutoStrat Strategies

#### STRAT_PAIR_CROSS (EMA Crossover)
- **Signal**: Fast EMA crosses above/below Slow EMA
- **Bias Logic**: Relaxed - only requires Fast slope correct
- **Best For**: Catching trend starts early
- **Risk**: Can enter before trend fully established

#### STRAT_PRICE_CROSS (Price vs EMA)
- **Signal**: Price crosses above/below EMA
- **Bias Logic**: Strict - requires both EMAs sloping correctly
- **Best For**: Trending markets with pullbacks
- **Risk**: Late entries if trend already strong

#### STRAT_SINGLE_SLOPE (EMA Direction)
- **Signal**: Single EMA turning up/down
- **Bias Logic**: Strict - requires both EMAs sloping correctly
- **Best For**: Fast-moving markets
- **Risk**: Whipsaw in ranging conditions

### 3. RRM Gates

#### Pullback/Reclaim Gate
```
RRM_RequirePullbackReclaim = true
```
**What it does:**
- Waits for price to pull back to Fast EMA (dip below in uptrend)
- Requires price to reclaim EMA (cross back above)
- Confirms trend continuation after pullback

**Effect:**
- ✅ Better entry prices (buy the dip)
- ✅ Filters out weak momentum entries
- ❌ Misses strong breakouts
- ❌ Fewer total trades

**When to use:** Lower timeframes, trending markets with regular pullbacks

#### EMA Divergence Gate
```
RRM_RequireEmaDiv = true
RRM_MinDivPips = 2.0
```
**What it does:**
- Requires EMAs to be expanding (distance increasing)
- Avoids entries during EMA convergence (weakening trend)

**Effect:**
- ✅ Confirms momentum acceleration
- ❌ Misses early trend starts

---

## Configuration Guide

### Basic Setup (Conservative - Option 1)

```
BiasMode = BIAS_AUTO
BiasFastID = 2  // EMA3 (34)
BiasSlowID = 3  // EMA4 (89)
AutoStrat = STRAT_PAIR_CROSS
VoteThreshold = 4

Use_EmaSig = true
Use_Macd = true
Use_Cci = true
Use_Psar = true

RRM_RequirePullbackReclaim = false
RRM_RequireEmaDiv = false
```
**Result:** High-quality trades, late entries, fewer signals

### Early Entry Setup (Solution B)

```
BiasMode = BIAS_AUTO
BiasFastID = 0  // EMA1 (5)  ← FASTER
BiasSlowID = 1  // EMA2 (13) ← FASTER
AutoStrat = STRAT_PRICE_CROSS
VoteThreshold = 3

Use_EmaSig = true
Use_Macd = true
Use_Adx = true
```
**Result:** Earlier entries, more trades, requires good filtering

### Pullback Trading Setup (Option 4)

```
BiasMode = BIAS_AUTO
BiasFastID = 1  // EMA2 (13)
BiasSlowID = 2  // EMA3 (34)
AutoStrat = STRAT_PRICE_CROSS
VoteThreshold = 4

RRM_RequirePullbackReclaim = true  ← KEY
RRM_RequireEmaDiv = false

Use_EmaSig = true
Use_Macd = true
Use_Cci = true
Use_Psar = true
```
**Result:** Entries only after pullback confirmation, better prices

### Crossover Early Entry (Option 3 - Enhanced)

```
BiasMode = BIAS_AUTO
BiasFastID = 1  // EMA2 (13)
BiasSlowID = 2  // EMA3 (34)
AutoStrat = STRAT_PAIR_CROSS  ← Uses relaxed bias logic
VoteThreshold = 3

Use_EmaSig = true
Use_Macd = true
Use_Cci = true

RRM_RequirePullbackReclaim = false
```
**Result:** Catches crossovers early (only Fast slope required for bias)

---

## Understanding Your Results

### Current Setup Analysis
From your test log:
```
BiasFastID = 2 (EMA34)
BiasSlowID = 3 (EMA89)
AutoStrat = STRAT_PAIR_CROSS
VoteThreshold = 4
```

**Why only 1 trade:**
- Using **slow EMAs** (34/89) for bias
- Even with relaxed crossover logic, both EMAs are slow to respond
- By the time they align, trend is well established
- Late but high-quality entry

**To get earlier entries:**
1. Change to faster EMAs (5/13 or 13/34)
2. Enable pullback logic for re-entries
3. Lower vote threshold (but keep quality)

---

## File Structure

```
RRM_SEA/
├── SimpleEA_v1-02-016d_05-8b_RRM.mq5    # Main EA
├── SEA_SignalEngine.mqh                  # Core signal processing
├── SEA_Config.mqh                        # Configuration structures
├── SEA_RiskManager.mqh                   # Position sizing
├── SEA_TradeManager.mqh                  # Trade execution
├── README.md                             # This file
└── README_INDICATORS.md                  # Indicator details
```

---

## Trading Rules Summary

### Entry Rules (ALL must pass)
1. ✅ Spread within limit
2. ✅ ATR within range (volatility OK)
3. ✅ Market bias valid (LONG or SHORT, not NEUTRAL)
4. ✅ Entry signal matches bias
5. ✅ HTF filter passes (if enabled)
6. ✅ RRM gates pass (if enabled)
7. ✅ Indicator votes >= threshold

### Exit Rules
- **Take Profit**: Fixed multiplier of ATR
- **Stop Loss**: Fixed multiplier of ATR
- **Break Even**: Move SL to BE after price moves X pips
- **Trailing Stop**: Optional trailing based on ATR

---

## Optimization Tips

### For More Trades
- Use faster EMAs (5/13 instead of 34/89)
- Lower vote threshold (3 instead of 4)
- Disable RRM gates
- Enable more indicators (but keep threshold reasonable)

### For Better Quality
- Use slower EMAs (34/89)
- Increase vote threshold
- Enable RRM gates (pullback/divergence)
- Add HTF filter
- Enable ADX (trend strength filter)

### For Better Entries
- Enable RRM_RequirePullbackReclaim
- Use STRAT_PRICE_CROSS with fast EMA
- Combine fast entry EMA with slow bias EMAs (requires code mod)

---

## Diagnostic Tools

### Vote Logging
In tester mode, the system logs detailed vote information:
```
VOTE_DETAIL[2026.02.09 09:00]: bias=1 v_shift=1 votes=4/4
  | EMA1: p=1.18557 e=1.18418 PASS
  | MACD: main=0.000628 sig=0.000396 PASS
  | CCI: 211.57 PASS
  | PSAR: sar=1.18255 cl=1.18557 PASS
```

**Use this to:**
- See which indicators voted
- Understand why trades were rejected
- Optimize indicator combinations
- Tune thresholds

### Rejection Reasons
The system provides clear rejection reasons:
- `BIAS_DISABLED`: Bias checking turned off
- `BIAS_ZERO`: No valid market bias (neutral/conflicting)
- `HTF_VETO`: Higher timeframe doesn't agree
- `RRM_PULLBACK`: Pullback gate not satisfied
- `RRM_EMA_DIV`: EMA divergence gate not satisfied
- `VOTES X/Y`: Insufficient indicator votes

---

## Version

**Current Version:** v1.02.016d-05-8b_RRM

**Key Features:**
- 9-step signal validation pipeline
- Strategy-dependent bias logic (STRAT_PAIR_CROSS relaxed)
- RRM mandatory gates (pullback/divergence)
- Comprehensive indicator voting
- Diagnostic logging for analysis
- Modular architecture for easy customization

**Recent Updates:**
- ✅ Fixed STRAT_PAIR_CROSS bias logic (relaxed slow slope requirement)
- ✅ Enhanced code documentation with process flow
- ✅ Improved README with configuration examples
- ✅ Added detailed RRM gate explanations

---

## Support

For detailed indicator behavior, see `README_INDICATORS.md`

For optimization strategies, see `Readme/_sea_optimization_scope_*.md`

For code architecture details, see inline comments in `SEA_SignalEngine.mqh`

---

## License

Copyright © 2026 - RRM SEA Trading System