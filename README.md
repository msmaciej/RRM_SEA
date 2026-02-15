# SimpleEA - Professional Trading System for MT5

## Overview

**SimpleEA** is a professional-grade Expert Advisor for MetaTrader 5 that implements a comprehensive 9-step signal validation pipeline combining **market bias analysis**, **multi-indicator voting**, and **risk-aware position management**. Designed specifically for **macOS + Wine + MT5** environments using **MQL5-only development** (no C++, no static locals, no lambdas).

The system trades **quality over quantity**, using a strict multiplicative voting system where ALL enabled indicators must agree before entering a position. This results in fewer but higher-probability trades with improved win rates.

**Core Philosophy:** Simple systems that work > Complex systems that don't

---

## Table of Contents

- [System Architecture](#system-architecture)
- [How SimpleEA Works: Complete Process Flow](#how-simpleea-works-complete-process-flow)
- [The 9-Step Signal Pipeline: Visual Overview](#the-9-step-signal-pipeline-visual-overview)
- [The 9-Step Signal Pipeline: Detailed Walkthrough](#the-9-step-signal-pipeline-detailed-walkthrough)
- [The Multiplicative Voting System Explained](#the-multiplicative-voting-system-explained)
- [Complete Execution Trace: Real-World Example](#complete-execution-trace-real-world-example)
- [Key Design Principles](#key-design-principles)
- [Configuration Guide](#configuration-guide)
- [Installation](#installation)
- [Strategy Tester Usage](#strategy-tester-usage)
- [Additional Documentation](#additional-documentation)
- [System Requirements](#system-requirements)

---

## System Architecture

### Core Components

**1. SimpleEA (Main Orchestrator)**  
- File: `SimpleEA_v1-02-016d_05-9_RRM.mq5`
- Coordinates all components
- Handles OnTick() event loop
- Manages new bar detection
- Triggers signal evaluation

**2. SEA_SignalEngine (Signal Pipeline)**  
- File: `SEA_SignalEngine.mqh`
- Implements 9-step validation pipeline
- Manages indicator handles
- Performs voting logic
- Returns trade direction: 1 (LONG), -1 (SHORT), 0 (NO TRADE)

**3. SEA_TradeExecutor (Trade Management)**  
- File: `SEA_TradeExecutor.mqh`
- Executes trade entries
- Calculates position sizing (risk-based + MA-compatible)
- Manages SL/TP placement (5 modes available)
- Implements breakeven logic
- Handles trailing stops (ATR, PSAR, Fractal)

**4. SEA_UI (Visualization)**  
- File: `SEA_UI.mqh`
- Real-time status panels
- Cockpit display with position monitoring
- Signal markers on chart

**5. SEA_Reporting (Analytics)**  
- File: `SEA_Reporting.mqh`
- Strategy Tester CSV export
- Comprehensive metrics and deal history

### Component Interaction Diagram

```
┌─────────────┐
│   OnTick()  │  ← Every price tick
└──────┬──────┘
       │
       ▼
┌─────────────────────────┐
│  New Bar Detection?     │
│  (Check iTime[0])       │
└──────┬──────────────────┘
       │
       ├─ NO → Manage existing positions (Breakeven, Trailing)
       │
       ├─ YES → Evaluate signal
       │
       ▼
┌─────────────────────────────────────────┐
│  SignalEngine.GetDirection()            │
│  [9-Step Pipeline on shift=1]           │
│  Returns: 1 (LONG) / -1 (SHORT) / 0    │
└──────┬──────────────────────────────────┘
       │
       ├─ Signal = 0 → Wait for next bar
       │
       ├─ Signal ≠ 0 → Calculate position size
       │
       ▼
┌─────────────────────────────────────────┐
│  TradeExecutor.ProcessSignal()          │
│  - Check: No existing position?         │
│  - Calculate lots (risk-based)          │
│  - Calculate SL/TP (ATR-based)          │
│  - Open trade at shift=0                │
└─────────────────────────────────────────┘
```

---

## How SimpleEA Works: Complete Process Flow

### Main Execution Loop (OnTick)

**Every time a new bar closes:**

```
1. Check if we have an open position
   ├─ YES → Manage it (breakeven, trailing stops)
   └─ NO → Look for new signal

2. Detect if new bar formed
   └─ Compare current iTime[0] with stored last bar time

3. If new bar → Call Signal Engine to evaluate conditions
   └─ SignalEngine.GetDirection() [9-step pipeline on shift=1]

4. If valid signal (≠ 0) AND no position open:
   ├─ Calculate position size
   ├─ Calculate SL/TP levels
   └─ Execute trade at shift=0 (current candle open)

5. Otherwise → Wait for next bar
```

**Critical Timing:**
- Signal evaluation happens on **shift=1** (CLOSED candle)
- Trade entry happens on **shift=0** (NEW candle open)
- This prevents repainting and ensures stable signals

---

## The 9-Step Signal Pipeline: Visual Overview

**All evaluation happens on CLOSED candle (shift=1)**

The system follows a strict sequential pipeline where **any failure stops immediately and returns 0 (NO TRADE)**:

```
Step 1: PRE-FILTERS
├─ Spread < MaxSpreadPips?
├─ MinATR < ATR < MaxATR?
├─ Time/Session allowed?
└─ No news blackout?
   → If ANY fail → TS = 0 → STOP
                ↓
Step 2: MARKET BIAS DETERMINATION
├─ Compare Fast EMA vs Slow EMA
├─ Check EMA slopes (rising/falling)
├─ Strategy-dependent relaxation:
│  ├─ STRAT_PAIR_CROSS: Only Fast slope required (relaxed)
│  └─ Others: Both slopes required (strict)
└─ Result: bias ∈ {-1, 0, 1} = {SHORT, NEUTRAL, LONG}
   → If bias = 0 → TS = 0 → STOP
                ↓
Step 3: AUTOSTRAT ENTRY SIGNAL
├─ STRAT_SINGLE_SLOPE: Single EMA direction
├─ STRAT_PRICE_CROSS: Price vs EMA
└─ STRAT_PAIR_CROSS: EMA crossover
   → Generate entry_signal (1/-1/0)
                ↓
Step 4: SIGNAL VALIDATION
└─ entry_signal must match bias direction
   → If mismatch → TS = 0 → STOP
                ↓
Step 5: HTF FILTER (Optional)
└─ Higher timeframe EMA must align with bias
   → If HTF disagrees → TS = 0 → STOP
                ↓
Step 6: RRM GATES (Optional)
├─ RRM_RequirePullbackReclaim?
│  └─ Check if price pulled back to EMA then reclaimed
└─ RRM_RequireEmaDiv?
   └─ Check if EMAs are expanding (not converging)
   → If enabled gates not met → TS = 0 → STOP
                ↓
Step 7: VOTING BYPASS CHECK
└─ If VoteThreshold <= 1 → Accept signal (bypass voting)
   → Otherwise → Continue to voting
                ↓
Step 8: INDICATOR VOTING
├─ Count votes from enabled indicators:
│  ├─ EMA1 (price position)
│  ├─ ADX (trend strength)
│  ├─ MACD (momentum alignment)
│  ├─ CCI (cyclical)
│  ├─ RSI (momentum zones)
│  ├─ Stochastic (momentum)
│  ├─ PSAR (trend direction)
│  ├─ Bollinger Bands (volatility)
│  ├─ MFI (money flow)
│  ├─ P123 (pattern)
│  └─ Ross Hook (fractal)
└─ Each indicator votes: 1 (AGREE) or 0 (DISAGREE)
                ↓
Step 9: FINAL DECISION
├─ Count total votes
├─ Compare: votes >= VoteThreshold?
│  ├─ YES → TS = bias direction (±1)
│  └─ NO → TS = 0
└─ Return TS to main EA
```

**Key Principle:** TS (Trade Signal) = Market_Bias × Indicator₁ × Indicator₂ × ... × Indicatorₙ

Where:
- **ANY component = 0** → Entire result = 0 (NO TRADE)
- **ALL components = 1** → Result = bias direction (±1)

This multiplicative system ensures **unanimous agreement** before entering a position.

---

## The 9-Step Signal Pipeline: Detailed Walkthrough

### Overview

The Signal Engine evaluates **EVERY condition on the CLOSED candle** (shift=1) before allowing any trade. If any step fails, the process stops immediately and returns 0 (NO TRADE).

---

### Step 1: Pre-Filters (Safety Checks)

**Purpose:** Ensure market conditions are safe for trading

**Checks:**

#### 1.1 Spread Filter
- **Check:** Current spread < MaxSpreadPips
- **Why:** High spreads eat into profits
- **If fails:** Reject signal (reason: "SPREAD")
- **Example:** If spread = 5 pips and max = 3 → NO TRADE

#### 1.2 ATR Volatility Filter
- **Check:** MinATR < Current ATR < MaxATR
- **Why:** Too low = ranging market, too high = unpredictable moves
- **If fails:** Reject signal (reason: "MIN_ATR" or "MAX_ATR")
- **Example:** If ATR = 2 pips and min = 5 → NO TRADE
- **Note:** Can be "hard gate" (blocks trade) or "soft vote" (just influences voting)

#### 1.3 Time/Session Filter (if enabled)
- **Check:** Current time within allowed trading sessions
- **Why:** Some sessions have better price action
- **If fails:** Reject signal (reason: "TIME")
- **Configuration:** `UseTime`, `StartHr`, `EndHr`

#### 1.4 News Filter (if enabled)
- **Check:** No high-impact news within X minutes
- **Why:** News causes unpredictable volatility
- **If fails:** Reject signal (logs news event details)
- **Data Source:** `Calendar/calendar_statement.csv`
- **Configuration:** `UseNews`, `NewsPre`, `NewsPost`

**Result:** If ANY pre-filter fails → **STOP** → Return 0 (NO TRADE)

---

### Step 2: Market Bias Determination

**Purpose:** Determine the PRIMARY trend direction

**How It Works:**

#### 2.1 Compare EMAs
- Get Fast EMA value (e.g., EMA 13)
- Get Slow EMA value (e.g., EMA 34)
- Get previous values for both (shift+1)
- Compare positions

#### 2.2 Calculate Slopes
- **Fast slope:** current > previous? (rising = 1, falling = -1, flat = 0)
- **Slow slope:** current > previous? (rising = 1, falling = -1, flat = 0)

#### 2.3 Apply Bias Logic

**Standard (Strict) Logic:**
```
LONG bias:  Fast > Slow AND Fast rising (1) AND Slow rising (1)
SHORT bias: Fast < Slow AND Fast falling (-1) AND Slow falling (-1)
NEUTRAL:    Neither condition met → bias = 0
```

**STRAT_PAIR_CROSS (Relaxed) Logic:**
```
LONG bias:  Fast > Slow AND Fast rising (Slow can be flat/falling)
SHORT bias: Fast < Slow AND Fast falling (Slow can be flat/rising)
```

**Result:** 
- bias = 1 (LONG)
- bias = -1 (SHORT)
- bias = 0 (NEUTRAL/CHOPPY) → **STOP** → Return 0 (NO TRADE)

**Example:**
```
Fast EMA (13) current  = 1.08550
Fast EMA (13) previous = 1.08400
Slow EMA (34) current  = 1.08200
Slow EMA (34) previous = 1.08150

Position Check:
  Fast > Slow? 1.08550 > 1.08200? YES ✅

Slope Check (Fast):
  1.08550 > 1.08400? YES → Fast is RISING ✅

Slope Check (Slow):
  1.08200 > 1.08150? YES → Slow is RISING ✅

Strategy: Standard (strict)
  Required: Fast > Slow AND both rising
  
→ bias = 1 (LONG) ✅
```

---

### Step 3: AutoStrat Entry Signal

**Purpose:** Generate timing signal within the bias context

**Three Strategies:**

#### 3.1 STRAT_SINGLE_SLOPE
- **Signal:** Single EMA turning up/down
- **Best for:** Fast-moving trending markets
- **Risk:** Whipsaws in ranging conditions
- **Logic:** Returns slope of Fast EMA (1, -1, or 0)

#### 3.2 STRAT_PRICE_CROSS
- **Signal:** Price crosses above/below EMA
- **Best for:** Trending markets with pullbacks
- **Risk:** Late entries if trend is strong
- **Logic:** 
  ```
  If RequirePriceCross:
    BUY:  Open < MA and Close > MA (up-cross)
    SELL: Open > MA and Close < MA (down-cross)
  Else:
    BUY:  Price > MA
    SELL: Price < MA
  ```

#### 3.3 STRAT_PAIR_CROSS (Recommended)
- **Signal:** Fast EMA crosses above/below Slow EMA
- **Best for:** Catching trend starts early
- **Risk:** Can enter before trend fully established
- **Logic:**
  ```
  Bullish cross: Fast was ≤ Slow, now > Slow
  Bearish cross: Fast was ≥ Slow, now < Slow
  ```

**Result:** entry_signal ∈ {-1, 0, 1}

---

### Step 4: Signal Validation

**Purpose:** Ensure entry signal matches the bias

**Check:**
```
IF bias = 1 (LONG):
  entry_signal must = 1
  
IF bias = -1 (SHORT):
  entry_signal must = -1

IF mismatch:
  → REJECT (bias = 0)
```

**Why:** Prevents contradictory signals (e.g., LONG bias but SHORT entry)

**Result:** If mismatch → **STOP** → Return 0 (NO TRADE)

---

### Step 5: HTF (Higher Timeframe) Filter

**Purpose:** Confirm trend on higher timeframe

**How It Works:**
1. Get HTF EMA slope (e.g., if on H1, check H4)
2. Calculate: HTF_current > HTF_previous? (rising or falling)
3. Check if HTF slope agrees with bias

**Logic:**
```
HTF rising (+1):  Only allow LONG trades (bias must = 1)
HTF falling (-1): Only allow SHORT trades (bias must = -1)

If bias ≠ HTF direction → VETO
```

**Why:** "Trade with the big boys" - align with institutional direction

**Configuration:** `UseHTF`, `HTF_Period`, `HTF_Timeframe`

**Result:** If HTF disagrees → **STOP** → Return 0 (reason: "HTF_VETO")

---

### Step 6: RRM Mandatory Gates (Optional Quality Filters)

**Purpose:** Ensure high-quality entry points

#### Gate 1: Pullback/Reclaim (if enabled)

**Check:** Has price pulled back to Fast EMA and then reclaimed?

**Logic:**
```
LONG:  Close[2] < FastEMA[2] AND Close[1] > FastEMA[1]
SHORT: Close[2] > FastEMA[2] AND Close[1] < FastEMA[1]
```

**Why:** Better entry price ("buy the dip in an uptrend")

**Configuration:** `RRM_RequirePullbackReclaim`

**Result:** If fails → **STOP** → Return 0 (reason: "RRM_PULLBACK")

#### Gate 2: EMA Divergence (if enabled)

**Check:** Are EMAs expanding (distance increasing)?

**Logic:**
```
Current distance = |FastEMA - SlowEMA|
Previous distance = |FastEMA_prev - SlowEMA_prev|

IF current > previous:
  → EMAs diverging (momentum accelerating) ✅
ELSE:
  → EMAs converging (momentum decelerating) ❌
```

**Why:** Confirms momentum acceleration

**Configuration:** `RRM_RequireEmaDiv`

**Result:** If fails → **STOP** → Return 0 (reason: "RRM_EMA_DIV")

---

### Step 7: Voting Bypass Check

**Purpose:** Determine if voting is needed

**Check:**
```
IF VoteThreshold <= 1:
  → Skip voting, accept signal immediately (return bias)
  → This is "bias-only" mode
ELSE:
  → Proceed to Step 8 (voting required)
```

**Why:** Allows fast "bias-only" mode when threshold = 1

**Result:** If threshold ≤ 1 → **SKIP TO STEP 9** (return bias)

---

### Step 8: Indicator Voting

**Purpose:** Get multi-indicator confirmation

**How It Works:**

#### 8.1 Initialize
```
votes = 0
```

#### 8.2 For each ENABLED indicator

Call indicator's `Check_XXX(bias, shift)` function:
- Function returns: `true` (agrees) or `false` (disagrees)
- If `true` → `votes++`

#### 8.3 Available Indicators

**EMA1 (Price Position)** - `Use_EmaSig`
- **LONG:** Price > FastEMA
- **SHORT:** Price < FastEMA
- **Why:** Basic trend confirmation

**ADX (Trend Strength)** - `Use_Adx`
- **Check:** ADX > threshold (e.g., 25)
- **Why:** Filters out weak/ranging markets
- **Note:** Direction-independent

**MACD (Momentum)** - `Use_Macd`
- **LONG:** Main > 0 AND Main > Signal
- **SHORT:** Main < 0 AND Main < Signal
- **Why:** Confirms momentum direction

**CCI (Cyclical)** - `Use_Cci`
- **LONG:** CCI > 0
- **SHORT:** CCI < 0
- **Why:** Cyclical momentum indicator

**RSI (Momentum Zones)** - `Use_Rsi`
- **LONG:** RSI < 70 (not overbought)
- **SHORT:** RSI > 30 (not oversold)
- **Why:** Prevents buying tops/selling bottoms

**Stochastic** - `Use_Sto`
- **LONG:** Stoch aligned with bias
- **SHORT:** Stoch aligned with bias
- **Why:** Momentum oscillator confirmation

**PSAR (Trend Direction)** - `Use_Psar`
- **LONG:** Price > PSAR
- **SHORT:** Price < PSAR
- **Why:** Trend direction indicator

**Bollinger Bands** - `Use_Bb`
- **Check:** Price position vs BB middle
- **Why:** Volatility-based confirmation

**MFI (Money Flow)** - `Use_Mfi`
- **LONG:** MFI confirms buying pressure
- **SHORT:** MFI confirms selling pressure
- **Why:** Volume confirmation

**P123 (Pattern)** - `Use_P123`
- **Check:** Ross hook 1-2-3 pattern detected
- **Why:** Price action pattern

**Ross Hook (Fractal)** - `Use_Ross`
- **Check:** Fractal breakout confirmed
- **Why:** Structure-based entry

#### 8.4 Count total votes

**Example:**
```
Bias = 1 (LONG)
Enabled indicators: MACD, PSAR, RSI, CCI
VoteThreshold = 4

MACD Check:
  Main = 0.00157, Signal = 0.00124
  Main > 0? YES ✅
  Main > Signal? YES ✅
  → votes = 1 ✅

PSAR Check:
  PSAR = 1.08100, Close = 1.08600
  Close > PSAR? YES ✅
  → votes = 2 ✅

RSI Check:
  RSI = 62.5
  RSI < 70? YES ✅ (not overbought)
  → votes = 3 ✅

CCI Check:
  CCI = 152.3
  CCI > 0? YES ✅
  → votes = 4 ✅

Total votes = 4
```

---

### Step 9: Final Decision

**Purpose:** Make final trade decision

**Logic:**
```
IF votes >= VoteThreshold:
  IF bias = 1:
    return 1 (LONG signal)
  ELSE IF bias = -1:
    return -1 (SHORT signal)
ELSE:
  return 0 (NO TRADE - insufficient votes)
```

**Diagnostic Output:**
- Signal reason logged
- Vote details logged (in tester mode)
- Last bias, votes, and reason stored for UI

**Result:** Returns 1 (LONG), -1 (SHORT), or 0 (NO TRADE)

---

## The Multiplicative Voting System Explained

### Formula

```
TS = Market_Bias × Indicator₁ × Indicator₂ × ... × Indicatorₙ
```

Where:
- **Market_Bias** ∈ {-1, 0, 1} = {SHORT, NEUTRAL, LONG}
- Each **Indicator** ∈ {0, 1} = {DISAGREE, AGREE}

### Why Multiplicative?

**Key Property:** ANY component = 0 → ENTIRE result = 0

This creates a strict filter requiring **unanimous agreement**.

### Example: Failed Signal

```
Market_Bias = 1 (LONG)
MACD = 1 ✅ (agrees)
PSAR = 1 ✅ (agrees)
RSI = 0 ❌ (RSI = 75, overbought - disagrees)
CCI = 1 ✅ (agrees)

TS = 1 × 1 × 1 × 0 × 1 = 0

→ NO TRADE (RSI disagreed)
```

**Result:** Trade is rejected because RSI disagreed with the bias, preventing buying into overbought conditions.

### Example: Successful Signal

```
Market_Bias = 1 (LONG)
MACD = 1 ✅
PSAR = 1 ✅
RSI = 1 ✅ (RSI = 62, healthy)
CCI = 1 ✅

TS = 1 × 1 × 1 × 1 × 1 = 1

Votes (4) >= VoteThreshold (4) ✅

→ TS = 1 (VALID LONG SIGNAL)
```

### Benefits

1. **Strict Filtering:** Requires unanimous agreement
2. **Reduces False Signals:** Won't trade on weak conditions
3. **Higher Win Rate:** Only trades when all conditions align
4. **Fewer Trades:** But higher quality

---

## Complete Execution Trace: Real-World Example

### Scenario

- **Symbol:** EURUSD
- **Timeframe:** H1
- **Date:** 2026-02-15 10:00 (bar closes at shift=1)
- **Strategy:** STRAT_PAIR_CROSS
- **VoteThreshold:** 4
- **Enabled Indicators:** MACD, PSAR, RSI, CCI

---

### Phase 1: Signal Evaluation (shift=1)

#### **Step 1: Pre-Filters**

```
Spread Check:
  Current spread = 2.0 pips
  MaxSpreadPips = 3.0
  2.0 < 3.0? YES ✅
  → Spread filter PASSED

ATR Check:
  Current ATR = 15.3 pips
  MinATRPips = 5.0
  MaxATRPips = 50.0
  5.0 < 15.3 < 50.0? YES ✅
  → ATR filter PASSED

Time Check:
  Current time = 10:00 GMT (London session)
  Allowed sessions = London, New York
  → Time filter PASSED ✅

News Check:
  No high-impact news in next 60 minutes
  → News filter PASSED ✅

Result: ALL PRE-FILTERS PASSED → Continue to Step 2
```

#### **Step 2: Market Bias**

```
EMA Values (shift=1):
  Fast EMA (13) = 1.08550
  Slow EMA (34) = 1.08200

EMA Values (shift=2):
  Fast EMA (13) = 1.08400
  Slow EMA (34) = 1.08150

Position Check:
  Fast > Slow? 1.08550 > 1.08200? YES ✅

Slope Check (Fast):
  Current (1.08550) > Previous (1.08400)? YES ✅
  → Fast EMA is RISING

Slope Check (Slow):
  Current (1.08200) > Previous (1.08150)? YES ✅
  → Slow EMA is RISING

Strategy: STRAT_PAIR_CROSS (relaxed logic)
  Required: Fast > Slow AND Fast rising
  Optional: Slow rising (bonus)

Result: bias = 1 (LONG) ✅
```

#### **Step 3: AutoStrat Entry Signal**

```
Strategy: STRAT_PAIR_CROSS

Check EMA Crossover:
  Did Fast EMA cross above Slow EMA?

  Looking back:
  Bar 0 (shift=1): Fast (1.08550) > Slow (1.08200) ✅
  Bar 1 (shift=2): Fast (1.08400) > Slow (1.08150) ✅
  Bar 2 (shift=3): Fast (1.08100) < Slow (1.08120) ❌

  Cross detected between bars 2 and 1!

Result: entry_signal = 1 (LONG) ✅
```

#### **Step 4: Signal Validation**

```
Bias = 1 (LONG)
Entry Signal = 1 (LONG)

Do they match? YES ✅

Result: Validation PASSED
```

#### **Step 5: HTF Filter**

```
HTF = H4 (higher timeframe)

Get H4 EMA slope:
  H4 EMA current = 1.08400
  H4 EMA previous = 1.08100

  Is H4 rising? 1.08400 > 1.08100? YES ✅

Bias = LONG
HTF slope = UP

Do they agree? YES ✅

Result: HTF Filter PASSED
```

#### **Step 6: RRM Gates**

```
Gate 1: Pullback/Reclaim
  In this example: DISABLED
  → SKIP

Gate 2: EMA Divergence
  In this example: DISABLED
  → SKIP

Result: No gates to check → Continue
```

#### **Step 7: Voting Bypass**

```
VoteThreshold = 4

Is threshold <= 1? NO (4 > 1)

Result: Voting is REQUIRED → Continue to Step 8
```

#### **Step 8: Indicator Voting**

```
Initialize: votes = 0

--- Vote 1: MACD ---
Enabled: YES

Get MACD values (shift=1):
  Main Line = 0.00157
  Signal Line = 0.00124

Check for LONG:
  Is Main > 0? 0.00157 > 0? YES ✅
  Is Main > Signal? 0.00157 > 0.00124? YES ✅

MACD agrees with LONG bias
→ votes++ (votes = 1)

--- Vote 2: PSAR ---
Enabled: YES

Get PSAR value (shift=1):
  PSAR = 1.08100
  Close = 1.08600

Check for LONG:
  Is Close > PSAR? 1.08600 > 1.08100? YES ✅

PSAR agrees with LONG bias
→ votes++ (votes = 2)

--- Vote 3: RSI ---
Enabled: YES

Get RSI value (shift=1):
  RSI = 62.5

Check for LONG:
  Is RSI < 70? 62.5 < 70? YES ✅ (not overbought)

RSI agrees with LONG bias
→ votes++ (votes = 3)

--- Vote 4: CCI ---
Enabled: YES

Get CCI value (shift=1):
  CCI = 152.3

Check for LONG:
  Is CCI > 0? 152.3 > 0? YES ✅

CCI agrees with LONG bias
→ votes++ (votes = 4)

FINAL VOTE COUNT: 4
```

#### **Step 9: Final Decision**

```
votes = 4
VoteThreshold = 4

Is votes >= VoteThreshold? 4 >= 4? YES ✅

bias = 1 (LONG)

Result: Return 1 (VALID LONG SIGNAL)

Diagnostic:
  LastBias = 1
  LastVotes = 4
  LastReason = "OK"
```

---

### Phase 2: Trade Entry (shift=0)

```
Bar closes at 10:00 (evaluation complete)
New bar opens at 11:00 (shift=0)

OnTick() triggered:

Check stored TS value from shift=1:
  TS = 1 (LONG signal was confirmed)

NO RE-EVALUATION at shift=0!
Use the confirmed signal from shift=1

Execute Trade:
  Direction: LONG
  Entry Price: 1.08620 (current ask price)

Calculate SL/TP:
  ATR = 15.3 pips
  SL = Entry - (ATR × 2.0) = 1.08620 - 30.6 pips = 1.08314
  TP = Entry + (ATR × 4.0) = 1.08620 + 61.2 pips = 1.09232

Open Trade:
  ✅ LONG position opened
  Entry: 1.08620
  SL: 1.08314
  TP: 1.09232
  Lots: 0.10 (based on 2% risk)
```

---

### Result

**Trade Opened Successfully!**

✅ All 9 steps passed  
✅ All 4 indicators voted YES  
✅ Entry at optimal price (candle open)  
✅ No repainting (decision made on closed candle)

---

## Key Design Principles

### 1. No Repainting

**How:** All decisions on shift=1 (closed candle)  
**Why:** Stable, backtestable results  
**Benefit:** What you see in backtest = what you get in live

**Timing:**
```
Candle N (shift=1):  Evaluate signal [CLOSED]
Candle N+1 (shift=0): Execute trade [OPEN]
```

### 2. Strict Filtering

**How:** Multiplicative voting (ANY disagreement = NO TRADE)  
**Why:** High-quality signals only  
**Benefit:** Higher win rate, fewer but better trades

### 3. Modular Architecture

**How:** Separate components (Signal, Execution, Risk, UI)  
**Why:** Easy to test, debug, and enhance  
**Benefit:** Professional-grade code structure

### 4. Shift-Based Timing

**How:** Evaluate on shift=1, execute on shift=0  
**Why:** Confirmation + Speed  
**Benefit:** Best of both worlds

---

## Configuration Guide

### Conservative Setup (High Quality, Fewer Trades)

```mql5
// BIAS & STRATEGY
InpPreset = PRESET_RRM                    // RRM Trend Pullback
Inp_BiasMode = BIAS_AUTO                  // Automatic bias
Inp_BiasFastID = 1                        // EMA 13 (fast)
Inp_BiasSlowID = 2                        // EMA 34 (slow)
Inp_AutoStrat = STRAT_PAIR_CROSS          // EMA crossover

// VOTING SYSTEM
Inp_VoteThreshold = 4                     // Need 4 votes
Inp_Use_EmaSig = true                     // Price vs EMA
Inp_Use_Macd = true                       // Momentum
Inp_Use_Cci = true                        // Cyclical
Inp_Use_Psar = true                       // Trend direction

// RRM QUALITY GATES
Inp_RRM_RequirePullbackReclaim = true     // Wait for pullback
Inp_RRM_RequireEmaDiv = true              // Require divergence

// RISK MANAGEMENT
InpRiskPercent = 1.5                      // 1.5% risk per trade
Inp_SL_Mult = 2.0                         // 2× ATR stop loss
Inp_TP_Mult = 4.0                         // 4× ATR take profit

// TRADE MANAGEMENT
Inp_Use_BE = true                         // Enable breakeven
Inp_BE_Trig = 1.0                         // Trigger at 1× ATR
Inp_BE_Buff = 0.1                         // Buffer 0.1× ATR
Inp_TrailMode = TRAIL_PSAR                // PSAR trailing

// FILTERS
InpMaxSpreadPips = 3.0                    // Max 3 pips spread
InpMinATRPips = 5.0                       // Min volatility
InpMaxATRPips = 50.0                      // Max volatility
```

**Expected Results:**
- Win rate: 55-60%
- Trades per month: 5-15 (H1/H4 timeframes)
- High-quality entries at pullbacks
- Lower drawdown

---

### Aggressive Setup (More Trades, Earlier Entries)

```mql5
// BIAS & STRATEGY
InpPreset = PRESET_CUSTOM                 // Custom control
Inp_BiasMode = BIAS_AUTO                  // Automatic bias
Inp_BiasFastID = 0                        // EMA 5 (very fast)
Inp_BiasSlowID = 1                        // EMA 13 (fast)
Inp_AutoStrat = STRAT_PRICE_CROSS         // Price cross

// VOTING SYSTEM
Inp_VoteThreshold = 3                     // Need 3 votes (lower)
Inp_Use_EmaSig = true                     // Price vs EMA
Inp_Use_Macd = true                       // Momentum
Inp_Use_Adx = true                        // Trend strength

// RRM QUALITY GATES
Inp_RRM_RequirePullbackReclaim = false    // No pullback wait
Inp_RRM_RequireEmaDiv = false             // No divergence check

// RISK MANAGEMENT
InpRiskPercent = 2.0                      // 2% risk per trade
Inp_SL_Mult = 1.5                         // 1.5× ATR (tighter)
Inp_TP_Mult = 3.0                         // 3× ATR

// TRADE MANAGEMENT
Inp_Use_BE = true                         // Enable breakeven
Inp_BE_Trig = 0.8                         // Trigger at 0.8× ATR
Inp_BE_Buff = 0.05                        // Small buffer
Inp_TrailMode = TRAIL_ATR                 // ATR trailing

// FILTERS
InpMaxSpreadPips = 5.0                    // Higher tolerance
InpMinATRPips = 3.0                       // Lower minimum
InpMaxATRPips = 100.0                     // Higher maximum
```

**Expected Results:**
- Win rate: 45-50%
- Trades per month: 30-80 (varies by timeframe)
- Earlier entries, more opportunities
- Higher drawdown potential

---

### "Let Profit Run" Setup

```mql5
// Standard bias and voting configuration...
// (use Conservative or Aggressive settings above)

// MODIFIED TRADE MANAGEMENT
Inp_TP_Mult = 0.0                         // DISABLE fixed TP
Inp_TrailMode = TRAIL_PSAR                // PSAR trailing
Inp_Trail_Mult = 3.0                      // 3× ATR distance
Inp_Use_BE = true                         // Breakeven protection
Inp_BE_Trig = 1.0                         // Trigger at 1× ATR
Inp_CloseOnReverse = false                // Don't close on reverse
```

**Strategy:** Let winners run until PSAR flips, protect with breakeven

---

### Important Configuration Notes

**Trade Count Varies by Timeframe:**
- Markets are fractal - same patterns on different scales
- **M5/M15:** 50-200 signals/month (more noise)
- **H1:** 20-50 signals/month (balanced)
- **H4/D1:** 5-20 signals/month (clean trends)

**Win Rate Depends on Filtering:**
- More filters + higher threshold = Higher win rate, fewer trades
- Fewer filters + lower threshold = Lower win rate, more trades

**Never assume fixed numbers** - adapt to market conditions and timeframe

---

## Installation

### Step 1: Copy Files

Copy files to your MT5 data folder:

```
MQL5/Experts/  → SimpleEA_v1-02-016d_05-9_RRM.mq5

MQL5/Include/  → SEA_SignalEngine.mqh
               → SEA_TradeExecutor.mqh
               → SEA_Reporting.mqh
               → SEA_UI.mqh
```

### Step 2: File Encoding (CRITICAL)

**All `.mq5`, `.mqh`, and `.json` files MUST be saved as UTF-16 LE with BOM**

Verify encoding (macOS/Linux):
```bash
file SimpleEA_v1-02-016d_05-9_RRM.mq5
# Should show: charset=utf-16le
# First bytes should be: FF FE (BOM)
```

If wrong encoding, the EA will fail to compile!

### Step 3: Compile

1. Open `SimpleEA_v1-02-016d_05-9_RRM.mq5` in MetaEditor
2. Press F7 or click "Compile"
3. Verify no errors in the Toolbox

### Step 4: Attach to Chart or Strategy Tester

**Live/Demo Chart:**
1. Drag EA onto chart
2. Configure inputs (see Configuration Guide)
3. Enable visualization:
   - `Inp_UI_ShowStatusPanel = true`
   - `Inp_UI_ShowCockpitPanel = true`
4. Click OK

**Strategy Tester:**
1. Select EA in tester
2. Choose symbol and timeframe
3. Configure parameters
4. Click Start

---

## Strategy Tester Usage

### Important Notes

**macOS + Wine Users:**
- Use **Stop → Start** after changing inputs (not just Restart)
- "Restart" may not reload new parameters properly

**Diagnostics:**
- Enable `Inp_PrintEffectiveConfig=true` to see actual settings
- Check Expert log for vote details and rejection reasons

---

### Understanding Test Results

#### Vote Logging Example

```
VOTE_DETAIL[2026.02.15 10:00]: bias=1 v_shift=1 votes=4/4
  | EMA1: p=1.08550 e=1.08420 PASS
  | MACD: main=0.00157 sig=0.00124 PASS
  | CCI: 152.3 PASS
  | PSAR: sar=1.08100 cl=1.08600 PASS
```

This shows:
- Bar time: 2026.02.15 10:00
- Bias: 1 (LONG)
- Evaluated at: shift=1
- Votes: 4 out of 4 required
- Each indicator's values and pass/fail

#### Rejection Reasons

| Reason | Meaning |
|--------|---------|
| `SPREAD` | Spread too high |
| `MIN_ATR` | Volatility too low |
| `MAX_ATR` | Volatility too high |
| `TIME` | Outside trading hours |
| `BIAS_ZERO` | No clear trend |
| `HTF_VETO` | Higher timeframe disagrees |
| `RRM_PULLBACK` | Pullback gate not satisfied |
| `RRM_EMA_DIV` | EMA divergence gate not satisfied |
| `VOTES 3/4` | Insufficient indicator votes (example: 3 out of 4) |

---

### CSV Export (Optional)

Enable comprehensive reporting:

```mql5
Inp_ExportCSV = true
Inp_ExportUseCommonFiles = false  // Keep false for macOS+Wine
```

**Report includes:**
- Configuration snapshot
- Performance metrics
- Risk & drawdown statistics
- Win rate & trade counts
- Deal-by-deal history

**File location:** `MT5/Tester/Agent-xxx/Files/`

---

## Additional Documentation

**Only relevant current documentation:**

- **`README_INDICATORS.md`** — Detailed indicator voting logic and parameters

**Historical/Development Files (NOT needed for users):**
- `Readme/README_SimpleEA_v1-01.md`
- `Readme/README_v1-02-014e1.md`
- `Readme/_sea_optimization_results_*.md`

These are in subfolders for reference only.

---

## System Requirements

- **Platform:** MetaTrader 5 (build 3650+)
- **Operating System:** 
  - Windows (native)
  - macOS (via Wine)
- **Encoding:** UTF-16 LE with BOM for all source files
- **Minimum Account:** $500+ recommended (for proper risk management)

---

## Version Information

**Current Version:** v1.02.016d-05-9_RRM  
**Build Number:** 1020168  
**Status:** Production Ready

**Key Features:**
- 9-step signal validation pipeline
- Dual-shift support (horizontal + vertical)
- RRM trend pullback/reclaim logic
- Multiple trailing stop modes (ATR, PSAR, Fractal)
- MaxATR upper volatility bound
- Comprehensive diagnostics and logging

---

## License

Copyright © 2026 - RRM SEA Trading System

---

## Support

**Repository:** [msmaciej/RRM_SEA](https://github.com/msmaciej/RRM_SEA)

For questions about the system logic, refer to the detailed walkthrough sections above.

---

## Risk Disclaimer

**Trading forex and CFDs involves substantial risk of loss.** This EA is provided for educational and research purposes. Past performance does not guarantee future results. Always test thoroughly in demo/backtest environments before live deployment.

**Remember: This system trades quality over quantity. Fewer signals, but higher probability of success.**

---

## Quick Reference Card

### Essential Pre-Flight Checks

✅ Files saved as UTF-16 LE with BOM  
✅ All `.mqh` files in `MQL5/Include/`  
✅ Selected appropriate configuration (Conservative/Aggressive)  
✅ Risk% set appropriately (1.5-2.0%)  
✅ `Inp_PrintEffectiveConfig=true` for diagnostics

### Minimum Viable Configuration

```mql5
InpPreset = PRESET_RRM              // Start with RRM preset
InpRiskPercent = 1.5                // Conservative risk
Inp_VoteThreshold = 4               // Strict filtering
Inp_SL_Mult = 2.0                   // 2× ATR stop
Inp_TP_Mult = 0.0                   // Let profit run
Inp_TrailMode = TRAIL_PSAR          // PSAR trailing
Inp_Use_BE = true                   // Breakeven protection
```

### Key Metrics to Monitor

- **Win Rate:** Varies by configuration (45-60%)
- **Profit Factor:** Target > 1.2
- **Max Drawdown:** Target < 20%
- **Sharpe Ratio:** Target > 0.5
- **Trade Frequency:** Varies significantly by timeframe

**Note:** Performance metrics vary by configuration, timeframe, and market conditions. There are no "fixed" expected results.

---

**End of README**
