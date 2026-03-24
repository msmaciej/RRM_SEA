# SimpleEA: Technical Documentation

**For the user guide and installation instructions, see [README.md](README.md)**

---

## Overview

This document provides detailed technical documentation for the SimpleEA signal processing pipeline, including:

- Step-by-step breakdown of the 9-step validation pipeline
- Mathematical formulas and voting system logic
- Complete execution trace with real indicator values
- Individual indicator voting rules and thresholds
- Advanced topics: RRM Gates, HTF Filter, shift logic

**Audience:** This documentation is for users who want to understand the internal mechanics, optimize parameters, or modify the EA.

---

## Table of Contents

- [The 9-Step Signal Pipeline: Detailed Walkthrough](#the-9-step-signal-pipeline-detailed-walkthrough)
- [Entry Layer: Pullback-Recovery Detection](#entry-layer-pullback-recovery-detection)
- [The Multiplicative Voting System Explained](#the-multiplicative-voting-system-explained)
- [TS Evaluation Trace: BIAS_AUTO_PHASE + Entry Layer Example](#ts-evaluation-trace-bias_auto_phase--entry-layer-example)
- [Complete Execution Trace: Real-World Example](#complete-execution-trace-real-world-example)
- [Indicator Voting Logic (Detailed)](#indicator-voting-logic-detailed)
- [Advanced Topics](#advanced-topics)

---

## The 9-Step Signal Pipeline: Detailed Walkthrough

### Overview

The Signal Engine evaluates **EVERY condition on the CLOSED candle** (shift=1, the **TS — Trade Setup** evaluation) before allowing any trade. If any step fails, the process stops immediately and returns 0 (NO TRADE).

The TS evaluation uses a multiplicative pipeline. At its core:

```
TS = Bias × MarketPhase × EntryLayer × [all enabled indicators]
```

Each factor returns 1 (pass), 0 (fail), or -1 (contradicts). Any 0 or -1 makes the whole product 0.

> **See also:** [README_SYSTEM.md — Bias, Market Phase, and Entry Layer Concepts](README_SYSTEM.md) for a conceptual overview of these three components and how they relate.

### Detailed TS Evaluation Walkthrough

For the complete pipeline diagram showing each step in order, see [README_SYSTEM.md — Complete TS Evaluation Pipeline](README_SYSTEM.md#complete-ts-evaluation-pipeline).

**Quick Summary**:
```
TS = [Pre-Filters] × [Bias × Phase] × [Layer] × [Indicators]
      ↓                ↓                 ↓         ↓
      Hard gates       Direction         Timing    Confirmation
```

1. **Pre-Filters** (Step 1): Block unsafe conditions (spread, time, news)
2. **Diagnostics** (Step 2): Passive — populate `m_diag_last_phase` and `m_diag_last_entry_layer`
3. **Bias** (Step 3): Determine LONG/SHORT/NONE using phase detection (3-layer voting when `BIAS_AUTO_PHASE`)
4. **Phase-Layer Filter** (Step 4): Validate pullback depth vs phase structure (blocks L3 in EMERGING, all in UNORDERED)
5. **Indicators** (Step 5): Final confirmation — multiplicative in VOTE_MODE_ALL

---

### Step 1: Pre-Filters (Safety Checks)

**Purpose:** Ensure market conditions are safe for trading

**Checks:**

#### 1.1 Spread Filter
- **Check:** Current spread < MaxSpreadPips
- **Why:** High spreads eat into profits
- **If fails:** Reject signal (reason: "SPREAD")
- **Example:** If spread = 5 pips and max = 3 → NO TRADE

#### 1.2 Time/Session Filter (if enabled)
- **Check:** Current time within allowed trading sessions
- **Why:** Some sessions have better price action
- **If fails:** Reject signal (reason: "TIME")
- **Configuration:** `UseTime`, `StartHr`, `EndHr`

#### 1.3 News Filter (if enabled)
- **Check:** No high-impact news within X minutes
- **Why:** News causes unpredictable volatility
- **If fails:** Reject signal (logs news event details)
- **Data Source:** `Calendar/calendar_statement.csv`
- **Configuration:** `UseNews`, `NewsPre`, `NewsPost`

**Result:** If ANY pre-filter fails → **STOP** → Return 0 (NO TRADE)

---

### Slope Threshold System

**Purpose:** Filter noise and false slope signals, especially on lower timeframes.

**How it works:**
1. **Calculate slope:** Compare EMA at current bar to N bars ago (configurable lookback)
2. **Apply threshold:** EMA must move at least X pips to count as rising/falling
3. **Adaptive scaling:** Threshold auto-adjusts based on:
   - **Timeframe:** M5 uses 0.5 pips, H4 uses 2.5 pips
   - **Pair volatility:** EURUSD uses 0.5 pips, EURJPY uses 0.8 pips, Gold uses 2.0 pips
   - **Preset:** RRM reduces threshold by 20% for stricter filtering

**Configuration:**
- `SlopeLookbackBars`: 1-5 bars (1=responsive, 3=smooth)
- `UseSlopeThreshold`: Enable/disable filtering
- `SlopeThresholdPips`: Fixed threshold (0=use adaptive)
- `SlopeThresholdAdaptive`: Auto-scale by TF/pair
- `SlopeMeasureMode`: PIPS (forex) or PERCENT (multi-asset)

**Example (EURUSD M15):**
```
Adaptive threshold = 0.5 (base) × 0.8 (M15 multiplier) = 0.4 pips

EMA34 current = 1.08500
EMA34 previous = 1.08497
Change = 0.00003 (0.3 pips)

Result: 0.3 < 0.4 → Slope = 0 (FLAT, within noise)
```

**Best Practices:**
- ✅ Use adaptive mode for most trading (auto-scales correctly)
- ✅ Use 1-bar lookback for M5-M30 (responsive)
- ✅ Use 2-bar lookback for H1-H4 (smoother, less noise)
- ✅ Use PIPS measurement for forex (intuitive)
- ⚠️ Use PERCENT only for multi-asset strategies (stocks, crypto, indices)

---

### Step 2: Market Bias Determination

**Purpose:** Determine the PRIMARY trend direction (the **Bias** component of the TS formula)

> **For a complete conceptual explanation of all three Bias modes, Market Phase types, and how Bias relates to MarketPhase and EntryLayer, see [README_SYSTEM.md — Bias, Market Phase, and Entry Layer Concepts](README_SYSTEM.md).**

This step produces `bias ∈ {-1, 0, 1}`. If the result is 0 (NEUTRAL), the pipeline stops here.

**How It Works:**

#### 2.1 Compare EMAs
- Get Fast EMA value (e.g., EMA 13)
- Get Slow EMA value (e.g., EMA 34)
- Get previous values for both (shift+N, where N = `SlopeLookbackBars`)
- Compare positions

#### 2.2 Calculate Slopes
- **Fast slope:** current vs N-bars-ago? (rising = 1, falling = -1, flat = 0)
- **Slow slope:** current vs N-bars-ago? (rising = 1, falling = -1, flat = 0)
- **Threshold applied:** Movement must exceed `GetMinSlopeThreshold()` to count as a slope

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

#### 2.4 BIAS_AUTO_PHASE Mode (Optional)

**Purpose:** Automatically block trades in choppy (UNORDERED) markets

**How It Works:**

1. Detect market phase using `DetectMarketPhase()`:
   - Check EMA3/EMA4 alignment and slope consistency
   - Return: `PHASE_UNORDERED`, `PHASE_EMERGING`, or `PHASE_TRENDING`

2. Apply bias override:
   ```
   IF phase == PHASE_UNORDERED:
     → Force bias = 0 (NEUTRAL)
     → STOP → Return 0 (NO TRADE)
   ELSE:
     → Proceed with normal bias calculation
   ```

**Configuration:** `InpBiasMode = BIAS_AUTO_PHASE` (Zone 3B §1)

**Why:** Prevents trading in choppy markets where direction is unclear

**Example:**
```
EMA3 (34) = 1.08550
EMA4 (89) = 1.08540
Difference = 0.00010 (0.1 pips - very flat)

Slope consistency (last 5 bars):
  Bar[5]: EMA3 > EMA4? YES
  Bar[4]: EMA3 > EMA4? NO
  Bar[3]: EMA3 > EMA4? YES
  Bar[2]: EMA3 > EMA4? NO
  Bar[1]: EMA3 > EMA4? YES
  
Consistent bars: 0 (flipping direction)

→ Phase = PHASE_UNORDERED
→ BIAS_AUTO_PHASE mode → bias = 0 (NEUTRAL)
→ STOP → Return 0 (NO TRADE)
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

#### 3.6 STRAT_LAYER_DETECTION Signal

**Purpose:** Detect pullback-recovery patterns based on EMA zone touches (TrSet methodology)

**Detection Algorithm:**
1. **Check L3 first** (deepest): Price within 1% of EMA3 OR EMA4 → LAYER_3_STRONG
2. **Check L2**: Price within 1% of EMA2 OR EMA3 → LAYER_2_MEDIUM
3. **Check L1** (shallowest): Price within 1% of EMA1 OR EMA2 → LAYER_1_WEAK
4. **Validate recovery** (if enabled):
   - Bullish: `close > touched_EMA`
   - Bearish: `close < touched_EMA`

**Example (Bullish LAYER_3_STRONG):**
```
Bar N (shift=1):
  EMA3 = 1.08500
  EMA4 = 1.08200
  Low  = 1.08450 (touched EMA3 within 1%)
  Close = 1.08600 (recovered above EMA3)
  
Result: LAYER_3_STRONG signal → TS armed
```

**Parameters:**
- `EnableLayerDetection`: Master toggle (default: true in PRESET_RRM)
- `LayerTouchTolerance`: Percentage tolerance for "touch" (default: 0.01 = 1%)
- `RequireRecoveryMomentum`: Require close beyond touched EMA (default: true)

**Integration with Phase Detection:**
- Phase determines which layers are tradeable
- Layer detection runs independently (passive observation)
- Both must align for valid TS signal

**Code Location:**
- Implementation: `SEA_SignalEngine.mqh::DetectEntryLayer()`
- Enum definitions: `SEA_Config.mqh::EEntryLayer`
- Preset configuration: `SEA_Presets.mqh` (PRESET_RRM, line ~744)

**Result:** entry_signal ∈ {-1, 0, 1}

---

### Step 3A: Layer Detection (RRM)

**Purpose:** Identify which EMA layer price is entering from

**Applies to:** RRM preset only (`Gate_UseMultiLayer = true`)

**How It Works:**

`DetectEntryLayer()` scans price position vs EMAs to determine entry layer:

| Layer | Price Condition | EMA Alignment Required |
|-------|----------------|------------------------|
| L1 | Price pulled back to EMA1, now at/beyond EMA1 | EMA1 and EMA2 aligned with bias |
| L2 | Price pulled back to EMA2, now at/beyond EMA2 | EMA2 and EMA3 aligned with bias |
| L3 | Price pulled back to EMA3, now at/beyond EMA3 | EMA3 and EMA4 aligned with bias (bias EMAs) |

**Example (LONG):**
```
EMA1 (5)  = 1.08450
EMA2 (13) = 1.08400
EMA3 (34) = 1.08300
EMA4 (89) = 1.08200
Price     = 1.08395

Check L1:
  Is price near EMA1? 1.08395 ≈ 1.08450? NO (5.5 pips away)
  
Check L2:
  Is price near EMA2? 1.08395 ≈ 1.08400? YES (0.5 pips) ✅
  Are EMA2 and EMA3 aligned? EMA2 > EMA3? YES ✅
  
→ Entry Layer = L2
```

**Result:** Returns `"L1"`, `"L2"`, `"L3"`, or `""` (empty = no layer detected)

**Used by:** Phase-based filtering (Step 6)

---

## Entry Layer: Pullback-Recovery Detection

> **For a conceptual overview of all three Entry Layer types and the pullback-recovery pattern, see [README_SYSTEM.md — Entry Layer](README_SYSTEM.md).**

The Entry Layer check is the **timing** component of the TS formula. It confirms that price has completed a pullback and resumed the trend direction before entering — filtering out entries made into the middle of a move.

### Layer Types

| Layer | EMA Pair | Nickname | Description |
|---|---|---|---|
| `LAYER_1_WEAK` | EMA1 – EMA2 | "Ribbon" | Shallow pullback; less aggressive entry |
| `LAYER_2_MEDIUM` | EMA2 – EMA3 | "Ghost" | Medium pullback; balanced risk/reward |
| `LAYER_3_STRONG` | EMA3 – EMA4 | "Shark" | Deep pullback; aggressive entry |

Each layer uses its EMA pair's relative position and slope to determine whether a pullback-recovery event has occurred.

### Pullback-Recovery Logic

For each layer (e.g., `LAYER_3_STRONG` = EMA3-EMA4):

```
1. Check EMA positions:
   - For LONG: EMA3 > EMA4  (EMA_fast above EMA_slow)
   - For SHORT: EMA3 < EMA4

2. Check slope alignment:
   - Both slopes in same direction (trending)

3. Detect pullback phase:
   - EMA3 slope flattens (moves toward EMA4 slope value)
   - EMA3 slope moves toward EMA4 (converging)

4. Detect flat phase:
   - EMA3 slope becomes flat (consolidation / brief pause)

5. Detect recovery phase:
   - EMA3 slope resumes trend direction (diverging from EMA4)
   - Price candle body closes beyond EMA3 (in bias direction)
     → LONG: Close > EMA3
     → SHORT: Close < EMA3

6. Return signal:
    1 = Recovery detected, matches bias  → PASS
    0 = No recovery detected             → FAIL
   -1 = Recovery contradicts bias        → FAIL
```

### Implementation Notes

- **Lookback window:** Configurable (e.g., 20 bars) — how far back to search for the pullback phase
- **Slope threshold:** Configurable — the minimum slope magnitude to distinguish "flat" from "trending"
- **Body close confirmation:** Price candle *body* (not wick) must close beyond EMA_fast in the bias direction; wicks are excluded to avoid false recoveries

### Which Layer Is Checked?

The system checks the configured layer (e.g., `LAYER_3_STRONG`). If `AllowLayer1`, `AllowLayer2`, and `AllowLayer3` are all enabled, all active layers are checked and the closest matching pullback is used.

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

### Step 6: Hard Gates (Sequential)

**Purpose:** Apply quality filters before voting

RRM gates run in sequence; ANY failure → immediate rejection.

#### Gate 1: Dynamic Pullback Detection (Multi-Layer)

**Check:** Has price pulled back to an active EMA layer and recovered?

**Logic:**
```
LONG:  Close[2] < FastEMA[2] AND Close[1] > FastEMA[1]
SHORT: Close[2] > FastEMA[2] AND Close[1] < FastEMA[1]
```

**Why:** Better entry price ("buy the dip in an uptrend")

**Configuration:**
- `Gate_UseMultiLayer = true` (enables multi-layer system)
- `Gate_Lookback` (bars to scan for pullback, default 20)
- `Gate_FullRecovery` (require full recovery beyond reference EMA)

**Result:** If fails → **STOP** → Return 0 (reason: `"NO_PULLBACK"` or `"NOT_RECOVERING"`)

---

#### Gate 2: Phase-Based Layer Filtering (RRM)

**Check:** Is detected entry layer allowed in current market phase?

**Applies when:**
- `RRM_FilterByPhase = true`
- `RRM_FilterLayersByPhase = true`
- Entry layer detected via `DetectEntryLayer()`

**Filtering Rules:**

| Market Phase | Allowed Layers | Blocked Layers | Reason |
|--------------|----------------|----------------|--------|
| UNORDERED | NONE | L1, L2, L3 | No clear trend |
| EMERGING | L1, L2 | L3 | Shallow entries, trend forming |
| TRENDING | L1, L2, L3 (ALL) | NONE | Strong trend, all depths allowed |

**Logic Flow:**
```
1. Detect current phase via DetectMarketPhase()
2. Detect entry layer via DetectEntryLayer()
3. Check if layer is allowed in this phase
4. If NOT allowed → REJECT
```

**Example:**
```
Phase = EMERGING
Entry Layer = L3
Bias = SHORT

Check:
  EMERGING phase allows: L1, L2 only
  Detected layer: L3
  Is L3 in allowed list? NO ❌
  
→ STOP → Return 0 (reason: "LAYER_NOT_ALLOWED_IN_PHASE")
```

**Why:** RRM methodology requires:
- Conservative entries during trend formation (EMERGING → L1/L2 only, avoid deep pullbacks)
- Aggressive entries during strong trends (TRENDING → L1/L2/L3 all allowed)
- No entries during chop (UNORDERED → block all)

**Configuration:**
- `InpBiasMode = BIAS_AUTO_PHASE` (optional: blocks UNORDERED at bias stage)
- `RRM_FilterByPhase = true` (enables phase detection)
- `RRM_FilterLayersByPhase = true` (applies layer restrictions)

**Result:** If layer not allowed → **STOP** → Return 0 (reason: `"LAYER_NOT_ALLOWED_IN_PHASE"`)

---

#### Gate 3: EMA Divergence (if enabled)

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

> **Note:** Indicator voting occurs **after** Bias, MarketPhase, and EntryLayer have all passed. Indicators are the final quality filter in the TS formula.

**How It Works:**

#### 8.1 Initialize
```
votes = 0
```

#### 8.2 For each ENABLED indicator

Call indicator's `Check_XXX(bias, shift)` function:
- Function returns: `true` (agrees) or `false` (disagrees)
- If `true` → `votes++`

#### 8.2a Indicator Types

Indicators fall into two categories based on whether they need to know the trade direction:

**Directional indicators** (receive bias parameter, check direction vs threshold):
- **MACD** — Checks histogram or crossover direction vs bias
- **RSI** — Checks overbought/oversold zones vs bias direction
- **Stochastic** — Checks %K/%D levels vs bias direction
- **CCI** — Checks commodity channel index level vs bias
- **Bollinger Bands** — Checks band touch or middle-line position vs bias
- **HTF** — Checks higher-timeframe EMA alignment with bias

**Non-directional indicators** (check market condition regardless of direction):
- **ATR** — Checks volatility is within acceptable range (min/max)
- **ADX** — Checks trend strength is above minimum threshold

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

**ATR (Volatility Range)** - `Inp_Ind_ATR_Enabled`
- **Check:** `ATR_VoteMinPips` < Current ATR < `ATR_VoteMaxPips`
- **Why:** Ensures volatility is within tradable range
- **Note:** Direction-independent (non-directional voting indicator only — not a hard gate)
- **Best for:** All strategies, prevents trading in dead zones or excessive volatility
- **Parameters:**
  - `P_Atr = 14` (ATR period)
  - `ATR_VoteMinPips = 5.0` (minimum volatility threshold)
  - `ATR_VoteMaxPips = 50.0` (maximum volatility threshold)

**Choppiness Index (CI)** - `Ind_CI_Enabled`
- **Check:** CI < threshold (e.g., < 61.8)
- **Why:** Detects ranging/choppy markets
- **Note:** Direction-independent (quality filter like CandleBody)
- **CI Values:**
  - 0-38.2: Strong directional trend (very low choppiness)
  - 38.2-61.8: Normal trending / transition zone
  - 61.8-100: Ranging / choppy market (high choppiness)
- **Best for:** All strategies, prevents trading in consolidation zones
- **Parameters:**
  - `CI_Period = 14` (calculation period)
  - `CI_RangingThreshold = 61.8` (reject if CI >= this value)

**VRC (Volatility Regime Classifier)** - `Ind_VRC_Enabled` — Phase 3 Enhancement
- **Check:** Current ATR >= 33rd percentile of recent ATR history
- **Why:** Filters out trades during low volatility (quiet/choppy markets with no momentum)
- **Note:** Direction-independent (non-directional vote like CI and CandleBody)
- **Volatility Regimes:**
  - VOLATILITY_LOW: ATR below 33rd percentile → **REJECT** (market too quiet)
  - VOLATILITY_NORMAL: ATR at/above 33rd percentile → **ALLOW** (acceptable conditions)
  - VOLATILITY_HIGH: Reserved for future enhancements (adaptive position sizing)
- **Best for:** Trend-following and breakout strategies (prevents trading in dead markets)
- **Parameters:**
  - `VRC_ATR_Period = 14` (ATR calculation period)
  - `VRC_Lookback = 100` (bars for percentile history)
  - `VRC_LowThreshold = 33.0` (percentile boundary for LOW/NORMAL regime)
- **Implementation:** Uses rolling ATR buffer + linear-interpolated percentile (same pattern as ADX dynamic mode)
- **Performance:** Threshold cached every 4 hours; requires minimum 10 bars of history for statistical validity

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


---

## TS Evaluation Trace: BIAS_AUTO_PHASE + Entry Layer Example

This trace shows a complete TS evaluation using `BIAS_AUTO_PHASE` mode with the Entry Layer check enabled — matching the full TS formula described in [README_SYSTEM.md](README_SYSTEM.md).

```
Bar Close: 2026-03-07 14:00:00
Symbol:    EURUSD
Timeframe: M1
Config:    BiasMode=BIAS_AUTO_PHASE, LayerDetect=true, AllowLayer3=true

─────────────────────────────────────────────────────────────────
STEP 1: Determine Bias
├─ BiasMode = BIAS_AUTO_PHASE
├─ EMA2 (1.08500) > EMA3 (1.08450) > EMA4 (1.08400)
├─ EMA2 slope: +0.0003 (rising) ✅
├─ EMA3 slope: +0.0002 (rising) ✅
├─ EMA4 slope: +0.0001 (rising) ✅
├─ EMAs properly ordered → Phase = PHASE_TRENDING
└─ Bias = 1 (LONG) ✅

STEP 2: Validate Market Phase
├─ Phase = PHASE_TRENDING (not UNORDERED)
└─ MarketPhase = 1 ✅

STEP 3: Check Entry Layer
├─ LayerDetect = true, checking LAYER_3_STRONG (EMA3-EMA4)
├─ EMA3 (1.08450) > EMA4 (1.08400) ✅ (LONG order)
├─ Pullback detected 3 bars ago: EMA3 slope flattened to ~0
├─ Recovery detected: EMA3 slope resumed +0.0002 (upward)
├─ Price body close (1.08462) > EMA3 (1.08450) ✅
└─ EntryLayer = 1 (matches bias LONG) ✅

STEP 4: Evaluate Indicators (post-structure checks)
├─ MACD: Histogram = +0.00015 (positive, matches LONG) → 1 ✅
├─ PSAR: Dots at 1.08390 (below price 1.08462) → 1 ✅
├─ ADX:  32.4 (> threshold 25) → 1 ✅
├─ RSI:  57.8 (not overbought < 70) → 1 ✅
└─ All enabled indicators passed ✅

─────────────────────────────────────────────────────────────────
RESULT: TS = Bias(1) × MarketPhase(1) × EntryLayer(1) × indicators(1) = 1
→ LONG signal confirmed ✅
→ Arm TE for next bar open
```

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


---

## Indicator Voting Logic (Detailed)

## Indicator Voting Logic

### General Principle

```
IF indicator_agrees_with_bias THEN votes++ END
```

Each indicator checks if current market conditions support the established bias (LONG or SHORT). The indicator does NOT determine direction - it only confirms or rejects the bias.

### Important Notes

1. **Bias is determined FIRST** (Step 2) by EMA position and slope
2. **Indicators vote SECOND** (Step 8) after bias is established
3. **Indicators don't create signals** - they validate bias
4. **Only ENABLED indicators** contribute to vote count
5. **Vote threshold** determines how many votes needed

---

## Available Indicators

### 1. EMA1 (Price Position)

**Setting:** `Use_EmaSig`

**What it checks:**
```
LONG bias: Price must be above EMA1
SHORT bias: Price must be below EMA1
```

**Vote logic:**
```mql5
bool Check_EMA1(const int bias, const int v_shift) {
   double price = iClose(m_symbol, PERIOD_CURRENT, v_shift);
   double ema   = GetMAVal(h_ema1, v_shift);
   
   if(bias > 0) return (price > ema);  // LONG: above
   else         return (price < ema);  // SHORT: below
}
```

**Purpose:** Confirms price is on correct side of fast EMA

**Best for:** All strategies, basic trend confirmation

**Default Period:** 5

---

### 2. ADX (Trend Strength)

**Setting:** `Use_Adx`

**What it checks:**
```
ADX value > threshold → Strong trend present
```

**Vote logic:**
```mql5
bool Check_ADX(const int v_shift) {
   double adx = GetVal(h_adx, v_shift);
   return (adx > m_settings.ADX_Threshold);  // Default: 25
}
```

**Purpose:** Filters out weak/ranging markets

**Note:** Direction-independent - only checks strength

**Best for:** Trending strategies, avoiding chop

**Parameters:**
- `ADX_Period = 14`
- `ADX_Threshold = 25.0`

**Recommendation:** Essential for trend-following systems

#### ADX Dynamic Modes (Phase 2 Enhancement)

ADX supports three validation modes for adaptive trend strength filtering:

##### 1. ADX_MODE_STATIC (Default)
- **Behavior:** Fixed threshold (e.g., 20.0)
- **Best for:** Stable market conditions, backtesting comparison
- **Configuration:**
  ```mql5
  Inp_Ind_Adx_Mode = ADX_MODE_STATIC;
  Inp_Ind_Adx_Threshold = 20.0;
  ```
- **Example:** ADX must be above 20.0 to pass (constant value)

##### 2. ADX_MODE_DYNAMIC_PERCENTILE
- **Behavior:** Adaptive threshold based on recent ADX history
- **Recalculation:** Every 4 hours to balance responsiveness and stability
- **Best for:** Volatile markets, automated trading, adaptive strategies
- **Configuration:**
  ```mql5
  Inp_Ind_Adx_Mode = ADX_MODE_DYNAMIC_PERCENTILE;
  Inp_Ind_Adx_Percentile = 50.0;  // 50th percentile = median
  Inp_Ind_Adx_Lookback = 100;     // bars to analyze
  ```
- **Example:** If the 50th percentile of last 100 ADX values = 18.5, then ADX must be > 18.5 to pass
- **Use Cases:**
  - 30th percentile: More aggressive (accepts weaker trends)
  - 50th percentile: Balanced (median strength required)
  - 70th percentile: Conservative (only strong trends pass)

##### 3. ADX_MODE_PHASE_AWARE
- **Behavior:** Different thresholds per market phase
- **Best for:** RRM strategy with phase detection (PRESET_RRM)
- **Configuration:**
  ```mql5
  Inp_Ind_Adx_Mode = ADX_MODE_PHASE_AWARE;
  Inp_Ind_Adx_Thr_Accum = 12.0;      // Accumulation/Unordered phase
  Inp_Ind_Adx_Thr_Trending = 25.0;   // Strong trending phase
  Inp_Ind_Adx_Thr_Distrib = 18.0;    // Distribution/transition phase
  ```
- **Threshold Selection:**
  - **PHASE_ACCUMULATION / PHASE_UNORDERED:** 12.0 (low threshold, accept weaker trends during accumulation)
  - **PHASE_TRENDING:** 25.0 (high threshold, require strong trend confirmation)
  - **PHASE_DISTRIBUTION:** 18.0 (medium threshold, transitional phase)
- **Rationale:** During accumulation, we want to catch emerging trends early (lower bar). During strong trends, we demand confirmation (higher bar).

##### Implementation Notes
- Rolling history buffer tracks ADX values for percentile calculation
- Cached threshold updated every 4 hours (14400 seconds) to avoid excessive recalculation
- History buffer size = `ADX_Lookback` parameter (default 100 bars)
- Percentile calculation uses linear interpolation between sorted values
- Static mode is used as fallback when history size < 10 bars

##### Testing Recommendations
1. **Compare Modes:** Run backtest with all three modes on same data (H1 EURUSD 2024)
2. **Percentile Sensitivity:** Test 30th, 50th, 70th percentiles in DYNAMIC mode
3. **Phase Thresholds:** Optimize phase-aware thresholds for your strategy
4. **Market Conditions:** Dynamic modes perform best in volatile/changing markets

---

### VRC (Volatility Regime Classifier) — Phase 3 Enhancement

**Purpose:** Filters out trades during low volatility regimes when markets are too quiet and likely choppy/ranging.

**Type:** Non-directional voting indicator (like Choppiness Index and CandleBody)

**Setting:** `Ind_VRC_Enabled`

#### How It Works

1. **ATR History Buffer:** Tracks last N bars of ATR values (default: 100 bars)
2. **Percentile Calculation:** Ranks current ATR against historical distribution using linear interpolation
3. **Regime Classification:**
   - **VOLATILITY_LOW:** ATR below 33rd percentile (too quiet → REJECT trade)
   - **VOLATILITY_NORMAL:** ATR at/above 33rd percentile (acceptable → ALLOW trade)
   - **VOLATILITY_HIGH:** Reserved for future enhancements (adaptive thresholds)
4. **Cache Update:** Threshold recalculated every 4 hours for performance

#### Vote Logic

```
IF current_ATR < ATR_33rd_percentile THEN
   VOTE = FAIL (volatility too low)
ELSE
   VOTE = PASS (volatility acceptable)
END
```

**Non-directional:** Vote result is independent of trade direction (LONG or SHORT).

#### Configuration

```mql5
Inp_Ind_VRC_Enabled = true;        // Enable VRC filter
Inp_Ind_VRC_Weight = 1;            // Vote weight (THRESHOLD mode)
Inp_Ind_VRC_ATR_Period = 14;       // ATR calculation period
Inp_Ind_VRC_Lookback = 100;        // Bars for percentile calculation
Inp_Ind_VRC_LowThreshold = 33.0;   // Low/Normal boundary (percentile)
```

#### Example Scenarios

| ATR Value | Historical Percentile | VRC Vote | Reason |
|-----------|----------------------|----------|--------|
| 0.0015 | 25th percentile | **FAIL** | Below 33% threshold (too quiet) |
| 0.0025 | 50th percentile | **PASS** | Above 33% threshold (normal) |
| 0.0045 | 80th percentile | **PASS** | Above 33% threshold (high volatility) |

#### Use Cases

- **Trend Following:** Avoid trades when ATR is too low (no momentum)
- **Breakout Strategies:** Ensure sufficient volatility for meaningful price moves
- **RRM Strategy:** Combine with Choppiness Index for double-filter (CI rejects ranging markets, VRC rejects quiet markets)

#### Implementation Notes

- Requires minimum 10 bars of history for statistical validity (returns NORMAL on startup)
- Uses linear interpolation for accurate percentile calculation (same as ADX dynamic mode)
- ATR handle (`h_atr`) reused from existing ATR voting indicator
- Cache updated every 4 hours (14400 seconds) to balance accuracy and performance

#### Testing Recommendations
1. **Backtest Comparison:** Run with/without VRC to measure impact on trade count and profitability
2. **Threshold Optimization:** Test 25%, 33%, 40% thresholds to find optimal filtering level
3. **Combine with CI:** Enable both CI and VRC for robust ranging/quiet market filtering
4. **Market Session Analysis:** Verify LOW regime appears during Asian session (quiet hours)

**Setting:** `Use_Macd`

**What it checks:**
```
LONG bias: MACD main > signal (bullish momentum)
SHORT bias: MACD main < signal (bearish momentum)
```

**Vote logic:**
```mql5
bool Check_MACD(const int bias, const int v_shift) {
   double main = GetVal(h_macd, v_shift, 0);
   double sig  = GetVal(h_macd, v_shift, 1);
   
   if(bias > 0) return (main > sig);   // LONG: above signal
   else         return (main < sig);   // SHORT: below signal
}
```

**Purpose:** Confirms momentum direction

**Best for:** Momentum strategies, swing trading

**Default Periods:** Fast=8, Slow=13, Signal=8 (RRM settings)

---

### 4. CCI (Commodity Channel Index)

**Setting:** `Use_Cci`

**What it checks:**
```
LONG bias: CCI > 0 (bullish momentum)
SHORT bias: CCI < 0 (bearish momentum)
```

**Vote logic:**
```mql5
bool Check_CCI(const int bias, const int v_shift) {
   double cci = GetVal(h_cci, v_shift);
   
   if(bias > 0) return (cci > 0);   // LONG: positive
   else         return (cci < 0);   // SHORT: negative
}
```

**Purpose:** Momentum oscillator confirmation

**Best for:** Trend and momentum strategies

**Default Period:** 14

**Note:** Very responsive, good for early momentum confirmation

---

### 5. RSI (Relative Strength Index)

**Setting:** `Use_Rsi`

**What it checks:**
```
LONG bias: RSI in bullish range (>50, <overbought)
SHORT bias: RSI in bearish range (<50, >oversold)
```

**Vote logic:**
```mql5
bool Check_RSI(const int bias, const int v_shift) {
   double rsi = GetVal(h_rsi, v_shift);
   
   if(bias > 0) {
      // LONG: Not overbought
      return (rsi < m_settings.RSI_OB);  // Default: 70
   } else {
      // SHORT: Not oversold
      return (rsi > m_settings.RSI_OS);  // Default: 30
   }
}
```

**Purpose:** Avoid extreme zones (potential reversals)

**Best for:** Trend-following, avoiding exhaustion

**Parameters:**
- `RSI_Period = 14`
- `RSI_OB = 70.0` (overbought)
- `RSI_OS = 30.0` (oversold)

---

### 6. Stochastic

**Setting:** `Use_Sto`

**What it checks:**
```
LONG bias: K line in bullish range (not overbought)
SHORT bias: K line in bearish range (not oversold)
```

**Vote logic:**
```mql5
bool Check_Sto(const int bias, const int v_shift) {
   double k = GetVal(h_sto, v_shift, 0);
   
   if(bias > 0) {
      return (k < m_settings.Sto_OB);  // LONG: not overbought (default: 80)
   } else {
      return (k > m_settings.Sto_OS);  // SHORT: not oversold (default: 20)
   }
}
```

**Purpose:** Zone filter, avoid extremes

**Best for:** Trend continuation, avoiding reversals

**Parameters:**
- `Sto_K = 5`
- `Sto_D = 3`
- `Sto_Slowing = 3`
- `Sto_OB = 80.0`
- `Sto_OS = 20.0`

---

### 7. PSAR (Parabolic SAR)

**Setting:** `Use_Psar`

**What it checks:**
```
LONG bias: Price above PSAR dots
SHORT bias: Price below PSAR dots
```

**Vote logic:**
```mql5
bool Check_PSAR(const int bias, const int v_shift) {
   double psar  = GetVal(h_psar, v_shift);
   double close = iClose(m_symbol, PERIOD_CURRENT, v_shift);
   
   if(bias > 0) return (close > psar);  // LONG: price above SAR
   else         return (close < psar);  // SHORT: price below SAR
}
```

**Purpose:** Trend direction confirmation

**Best for:** Trending markets, stop placement reference

**Parameters:**
- `PSAR_Step = 0.02`
- `PSAR_Maximum = 0.2`

**Note:** Excellent for trend confirmation, aligns well with EMA bias

**PSAR Trailing Stop:**

PSAR can also be used for trailing stop loss with `TrailMode = TRAIL_PSAR`. The system supports two cushion modes:

**1. PSAR_CUSHION_PIPS (Fixed Pips):**
```mql5
Inp_PSAR_TrailCushionMode = PSAR_CUSHION_PIPS
Inp_PSAR_TrailPipsCushion = 5.0  // Auto-scales by TF and pair type
```
- Applies a fixed pips cushion below/above PSAR dot
- Auto-scales based on timeframe (M1: 0.5×, M5: 0.8×, M15: 1.0×, H1+: 2.0×)
- Auto-adjusts for JPY pairs (×100 vs ×10 for standard pairs)
- Uses PSAR value at configurable bar-shift delay to avoid repainting

**PSAR Trailing Delay Parameter:**
```mql5
Inp_PSAR_TrailDelay = 1  // Bar shift delay (1-3)
```
- `1` = use PSAR at shift=1 (last confirmed bar) — fast response
- `2` = use PSAR at shift=2 (2 bars ago) — wait for confirmation
- `3` = use PSAR at shift=3 (3 bars ago) — very conservative

**When to Use:**
- Lower timeframes (M1-M15): `delay=1` (fast response)
- Medium timeframes (M30-H1): `delay=1` or `2` (balanced)
- Higher timeframes (H4-D1): `delay=2` or `3` (avoid whipsaws)

**2. PSAR_CUSHION_ATR (Dynamic ATR):**
```mql5
Inp_PSAR_TrailCushionMode = PSAR_CUSHION_ATR
Inp_PSAR_TrailCushionATR = 0.2  // Multiplier of current ATR
```
- Applies dynamic cushion: `cushion = ATR × multiplier`
- Adapts to current market volatility
- Larger cushion during volatile periods, tighter during calm

**Trailing Logic:**
```mql5
double psar = GetPsarValue(1);  // Last confirmed PSAR
double cushion = calculated_based_on_mode;

if(position_type == BUY)
   new_sl = psar - cushion;  // Trail below PSAR
else
   new_sl = psar + cushion;  // Trail above PSAR

// Only move SL in profit direction (never widen)
if(BUY && new_sl > current_sl && new_sl < current_price)
   ModifySL(new_sl);
```

**When to Use:**
- **PIPS mode:** Predictable cushion, works well for ranges and lower timeframes
- **ATR mode:** Adaptive cushion, works well for volatile/trending markets

---

### 8. Bollinger Bands

**Setting:** `Use_Bb`

**What it checks:**
```
LONG bias: Price relative to middle band
SHORT bias: Price relative to middle band
```

**Vote logic:**
```mql5
bool Check_BB(const int bias, const int v_shift) {
   double mid   = GetVal(h_bb, v_shift, 0);  // Middle band
   double close = iClose(m_symbol, PERIOD_CURRENT, v_shift);
   
   if(bias > 0) return (close > mid);  // LONG: above middle
   else         return (close < mid);  // SHORT: below middle
}
```

**Purpose:** Volatility-adjusted trend confirmation

**Best for:** Volatile markets, band-based strategies

**Parameters:**
- `BB_Period = 20`
- `BB_Deviation = 2.0`

---

### 9. MFI (Money Flow Index)

**Setting:** `Use_Mfi`

**What it checks:**
```
LONG bias: MFI not overbought
SHORT bias: MFI not oversold
```

**Vote logic:**
```mql5
bool Check_MFI(const int bias, const int v_shift) {
   double mfi = GetVal(h_mfi, v_shift);
   
   if(bias > 0) {
      return (mfi < m_settings.MFI_OB);  // LONG: not overbought (default: 80)
   } else {
      return (mfi > m_settings.MFI_OS);  // SHORT: not oversold (default: 20)
   }
}
```

**Purpose:** Volume-weighted momentum confirmation

**Best for:** Markets with volume data, avoiding extremes

**Parameters:**
- `MFI_Period = 14`
- `MFI_OB = 80.0`
- `MFI_OS = 20.0`

**Note:** Similar to RSI but includes volume - use one or the other

---

### 10. P123 Pattern

**Setting:** `Use_P123`

**What it checks:**
```
3-bar pattern recognition (specific formation)
Details in implementation
```

**Purpose:** Pattern-based entry confirmation

**Best for:** Pattern traders, swing entries

**Note:** Advanced pattern - see code for exact logic

---

### 11. Ross Hook

**Setting:** `Use_Ross`

**What it checks:**
```
Ross Hook pattern detection
Details in implementation
```

**Purpose:** Advanced pattern recognition

**Best for:** Joe Ross methodology followers

**Note:** Advanced pattern - see code for exact logic

---

### 12. ATR (Volatility Range)

**Setting:** `Inp_Ind_ATR_Enabled`

**What it checks:**
```
ATR_VoteMinPips < Current ATR < ATR_VoteMaxPips
```

**Purpose:** Validates volatility is within acceptable trading range (voting indicator only — not a hard gate)

**Note:** Direction-independent (non-directional voting indicator). ATR participates in voting like other indicators (MACD, RSI, etc.) and does NOT block trades directly.

**Best for:** All strategies; prevents trading in dead zones or excessive volatility

**Parameters:**
- `P_Atr = 14` (ATR period)
- `ATR_VoteMinPips = 5.0` (minimum volatility threshold)
- `ATR_VoteMaxPips = 50.0` (maximum volatility threshold)

---

## Voting Configuration

### Vote Threshold

```
VoteThreshold = X
```

Minimum number of indicators that must agree with bias before trade is accepted.

**Examples:**
- `VoteThreshold = 1`: Bypass mode (fast, minimal confirmation)
- `VoteThreshold = 2`: Light confirmation (2 indicators must agree)
- `VoteThreshold = 3`: Moderate confirmation (3 indicators must agree)
- `VoteThreshold = 4`: **Recommended** - Good balance
- `VoteThreshold = 5`: Strict confirmation (5 indicators must agree)
- `VoteThreshold = 6`: Very conservative (6 indicators must agree)

### Enabling Indicators

Each indicator can be enabled/disabled independently:

```
Use_EmaSig = true   // Enable EMA1 vote
Use_Adx = true      // Enable ADX vote
Use_Macd = true     // Enable MACD vote
Use_Cci = true      // Enable CCI vote
Use_Rsi = false     // Disable RSI vote
Use_Sto = false     // Disable Stochastic vote
Use_Bb = false      // Disable Bollinger vote
Use_Mfi = false     // Disable MFI vote
Use_Psar = true     // Enable PSAR vote
Use_P123 = false    // Disable P123 vote
Use_Ross = false    // Disable Ross vote
```

**Important:** Only ENABLED indicators contribute to vote count.

If you enable 5 indicators and set VoteThreshold = 4, then 4 out of those 5 must vote PASS.

---

## Recommended Combinations

### Conservative (High Win Rate)
```
Use_EmaSig = true
Use_Macd = true
Use_Cci = true
Use_Psar = true
VoteThreshold = 4
```
**Result:** 4/4 required, all must agree - very selective

**Best for:** Lower timeframes, volatile markets

---

### Balanced (Good Quality)
```
Use_EmaSig = true
Use_Adx = true
Use_Macd = true
Use_Cci = true
Use_Psar = true
VoteThreshold = 4
```
**Result:** 4/5 required, allows one dissenter

**Best for:** General trading, good balance of quality vs frequency

---

### Aggressive (More Trades)
```
Use_EmaSig = true
Use_Macd = true
Use_Cci = true
VoteThreshold = 2
```
**Result:** 2/3 required, light confirmation

**Best for:** Higher timeframes, strong trends, experienced traders

---

### Trend Confirmation Bundle
```
Use_EmaSig = true
Use_Adx = true      // ← Trend strength
Use_Macd = true
Use_Psar = true     // ← Trend direction
VoteThreshold = 3
```
**Focus:** Strong trending conditions

---

### Momentum Bundle
```
Use_Macd = true
Use_Cci = true
Use_Rsi = true
Use_Sto = true
VoteThreshold = 3
```
**Focus:** Momentum confirmation (but avoid redundancy - choose RSI OR Sto, not both)

---

## Understanding Indicator Redundancy

### Similar Indicators (Choose ONE from each group)

**Momentum Oscillators:**
- RSI
- Stochastic
- MFI

→ **Pick one** - they measure similar things

**Trend Indicators:**
- EMA1
- PSAR
- Bollinger Bands

→ **Use 1-2** - more than that is redundant

**Momentum Direction:**
- MACD
- CCI

→ **Both OK** - they measure momentum differently

---

## Diagnostic Logging

The system logs detailed vote information during backtesting:

```
VOTE_DETAIL[2026.02.09 09:00]: bias=1 v_shift=1 votes=4/4
  | EMA1: p=1.18557 e=1.18418 PASS
  | MACD: main=0.000628 sig=0.000396 PASS
  | CCI: 211.57 PASS
  | PSAR: sar=1.18255 cl=1.18557 PASS
```

This shows:
- Timestamp of the bar being evaluated
- Current bias (1=LONG, -1=SHORT)
- Bar shift (v_shift)
- Vote count (votes/threshold)
- Each enabled indicator with:
  - Its current values
  - Whether it voted PASS or FAIL

### How to Use Diagnostic Logs

**1. Identify weak indicators:**
```
If indicator frequently votes FAIL → Consider removing it
```

**2. Optimize thresholds:**
```
If RSI always shows 40-60 → Adjust RSI_OB/OS thresholds
If ADX always < 20 → Lower ADX_Threshold or disable
```

**3. Find missing trades:**
```
Check rejected signals → See which indicator blocked entry
Evaluate if that indicator is too strict
```

**4. Validate combinations:**
```
Track which indicators agree most often
Build bundles of complementary indicators
```

---

## Indicator Tuning Tips

### ADX Threshold
- **Default: 25** (medium-strong trends)
- **Lower to 20**: More trades, accepts weaker trends
- **Raise to 30**: Fewer trades, only strong trends

### RSI/Stochastic Zones
- **Default: 70/30 (RSI), 80/20 (Sto)**
- **Tighter (60/40 or 70/30)**: More selective, avoid extremes
- **Wider (80/20 or 90/10)**: Less restrictive, more trades

### MACD Periods
- **Default: 8,13,8** (RRM fast settings)
- **Standard: 12,26,9** (Traditional, slower)
- **Aggressive: 5,13,5** (Very fast)

---

## Best Practices

### 1. Start Simple
```
Use 3-4 complementary indicators
Set reasonable threshold (# of indicators minus 1)
Test and observe rejection reasons
```

### 2. Avoid Redundancy
```
Don't use RSI + Stochastic + MFI together
Don't use multiple EMA-based indicators
Mix different indicator types
```

### 3. Match to Market
```
Trending → Enable ADX, PSAR, MACD
Ranging → Disable or relax zone filters
Volatile → Enable BB, adjust ATR filters
```

### 4. Use Diagnostic Logs
```
Enable tester mode
Check which indicators frequently disagree
Remove indicators that rarely vote PASS
Adjust thresholds based on actual values
```

### 5. Optimize Systematically
```
Start with 1 indicator (e.g., EMA1 only)
Add indicators one at a time
Measure impact on win rate and trade frequency
Remove indicators that decrease performance
```

---

## Indicator Parameters Reference

### Complete Settings List

```
// ADX
ADX_Period = 14
ADX_Threshold = 25.0

// RSI
RSI_Period = 14
RSI_OB = 70.0  // Overbought
RSI_OS = 30.0  // Oversold

// Stochastic
Sto_K = 5
Sto_D = 3
Sto_Slowing = 3
Sto_OB = 80.0
Sto_OS = 20.0

// MFI
MFI_Period = 14
MFI_OB = 80.0
MFI_OS = 20.0

// Bollinger Bands
BB_Period = 20
BB_Deviation = 2.0

// PSAR
PSAR_Step = 0.02
PSAR_Maximum = 0.2

// CCI
CCI_Period = 14

// MACD (from EMA strategy settings)
MACD_Fast = 8
MACD_Slow = 13
MACD_Signal = 8
```

---

## Troubleshooting

### "Not enough votes" (frequent rejection)

**Possible causes:**
1. Threshold too high for number of enabled indicators
2. Indicators conflicting (e.g., using both RSI and Stochastic in opposite zones)
3. Market conditions don't match indicator settings

**Solutions:**
- Lower VoteThreshold
- Check diagnostic logs to see which indicators fail
- Disable conflicting indicators
- Adjust indicator thresholds (ADX, RSI zones, etc.)

### "Too many trades" (low quality)

**Possible causes:**
1. Threshold too low
2. Indicators too permissive
3. Not enough filtering

**Solutions:**
- Increase VoteThreshold
- Enable ADX (trend strength filter)
- Tighten RSI/Stochastic zones
- Enable RRM gates (pullback/divergence)

### "Indicators always PASS or always FAIL"

**Possible causes:**
1. Indicator threshold set wrong for this market
2. Indicator not suitable for this timeframe

**Solutions:**
- Check diagnostic logs for actual values
- Adjust thresholds to match observed ranges
- Disable indicator if it's not useful for this setup

---

## Version

**Current Version:** v1.02.016d-05-8b_RRM

**Key Features:**
- 11 available indicators
- Flexible voting system
- Comprehensive diagnostic logging
- Individual enable/disable per indicator
- Configurable thresholds and parameters

---

## See Also

- `README.md` - Main system documentation and signal pipeline
- `SEA_SignalEngine.mqh` - Implementation details
- `Readme/_sea_optimization_scope_*.md` - Optimization strategies
---

## Advanced Topics

### RRM Gates Deep Dive

#### Pullback/Reclaim Gate

**Purpose:** Wait for better entry prices by requiring price to pull back to the Fast EMA and then reclaim it.

**Implementation:**
```
For LONG:
  1. Check bar [2]: Close < FastEMA (pullback occurred)
  2. Check bar [1]: Close > FastEMA (reclaimed)
  3. Both conditions required → Gate passes

For SHORT:
  1. Check bar [2]: Close > FastEMA (pullback occurred)
  2. Check bar [1]: Close < FastEMA (reclaimed)
  3. Both conditions required → Gate passes
```

**Effect:**
- ✅ Better entry prices (buy dips in uptrends)
- ✅ Filters weak momentum
- ❌ Misses strong breakouts
- ❌ Reduces trade count (~30-50%)

**When to Use:**
- Lower timeframes (M5, M15, H1)
- Trending markets with regular pullbacks
- When you want higher win rate over trade frequency

---

#### EMA Divergence Gate

**Purpose:** Ensure EMAs are expanding (momentum accelerating), not converging (weakening).

**Implementation:**
```
Calculate distances:
  dist_current = |FastEMA[1] - SlowEMA[1]|
  dist_previous = |FastEMA[2] - SlowEMA[2]|

Check:
  IF dist_current > dist_previous:
    → EMAs diverging → Gate passes ✅
  ELSE:
    → EMAs converging → Gate fails ❌
```

**Optional Minimum Threshold:**
```
IF (dist_current - dist_previous) >= RRM_MinDivPips:
  → Gate passes ✅
```

**Effect:**
- ✅ Confirms momentum acceleration
- ✅ Avoids entries during trend exhaustion
- ❌ Misses very early trend starts
- ❌ Reduces trade count (~20-30%)

---

### HTF (Higher Timeframe) Filter

**Purpose:** Align with institutional direction by checking higher timeframe trend.

**Implementation:**
```
1. Create HTF EMA handle (e.g., H4 EMA if trading H1)
2. Get HTF EMA values:
   current = HTF_EMA[1]
   previous = HTF_EMA[2]
3. Calculate HTF slope:
   slope = (current > previous) ? 1 : -1
4. Compare with bias:
   IF bias == slope:
     → HTF agrees → Continue ✅
   ELSE:
     → HTF disagrees → VETO ❌
```

**Configuration:**
- `UseHTF`: Enable/disable
- `HTF_Period`: EMA period (typically same as bias EMA)
- `HTF_Timeframe`: PERIOD_H4, PERIOD_D1, etc.

**Recommended HTF Relationships:**
- Trading M5 → Check M15 or M30
- Trading M15 → Check H1
- Trading H1 → Check H4
- Trading H4 → Check D1

---

### Shift Logic: Horizontal vs Vertical

**Two Types of Shift:**

#### Horizontal Shift (ma_h_shift)
- Applied at indicator creation (4th parameter of iMA())
- Physically moves the MA line left/right on the chart
- Used for: Matching MetaQuotes Moving Average EA behavior
- Default: 0 (no horizontal shift)

#### Vertical Shift (ma_v_shift)
- Applied during calculation (which bar to read)
- Changes which candle we evaluate
- Used for: Repainting control

**Shift Values:**
- **shift=0**: Current (forming) candle - aggressive, may repaint
- **shift=1**: Last closed candle - safe, stable, no repainting

**SimpleEA Default:**
- Horizontal shift: 0 (ma_h_shift = 0)
- Vertical shift: 1 (ma_v_shift = 1)
- Result: Stable signals on closed candles

---

### Understanding the Multiplicative Formula

The multiplicative voting system is the core of SimpleEA's filtering logic.

**Formula:**
```
TS = Market_Bias × Indicator₁ × Indicator₂ × ... × Indicatorₙ
```

**Key Properties:**

1. **Any Zero Kills the Signal**
   - If ANY component = 0, the entire product = 0
   - This creates a veto system where unanimous agreement is required

2. **Comparison to Additive System**
   - Additive: `TS = Bias + Ind1 + Ind2 + ...` (weak filtering)
   - Multiplicative: `TS = Bias × Ind1 × Ind2 × ...` (strict filtering)

3. **Vote Threshold Implementation**
   - The system counts votes: if `votes >= threshold`, indicators vote as 1
   - If `votes < threshold`, indicators collectively vote as 0
   - This 0 then multiplies with bias to produce final 0 (NO TRADE)

**Example Comparison:**

**Additive System (NOT used):**
```
Bias = 1, MACD = 1, RSI = 0, PSAR = 1
Sum = 1 + 1 + 0 + 1 = 3 (TRADE accepted)
```

**Multiplicative System (USED):**
```
Bias = 1, MACD = 1, RSI = 0, PSAR = 1
Product = 1 × 1 × 0 × 1 = 0 (TRADE rejected)
```

The multiplicative system correctly rejects the signal because RSI disagreed.

---

### Signal Evaluation Timing Details

**Why shift=1 for Evaluation?**

1. **Data Stability**
   - shift=0 = Current forming candle (values change on every tick)
   - shift=1 = Last closed candle (values are final)

2. **No Repainting**
   - Indicators at shift=1 never change
   - Backtest results match live results

3. **Predictable Execution**
   - Signal decision made on closed candle
   - Trade executed at next candle open
   - No surprises

**Timing Sequence:**
```
Bar N closes → shift=1 for Bar N
  ↓
Evaluate all conditions on Bar N (shift=1)
  ↓
Decision: TS = 1 (LONG)
  ↓
Bar N+1 opens → shift=0 for Bar N+1
  ↓
Execute LONG trade at Bar N+1 open price
```

**Result:**
- 1 candle delay between signal and execution
- Completely stable and predictable
- No optimization curve-fitting risk

---

## Implementation Notes

### Code Organization

The signal engine is structured in `SEA_SignalEngine.mqh`:

1. **GetDirection()**: Main entry point
   - Orchestrates all 9 steps
   - Returns final trade signal

2. **Step Functions**:
   - `CheckPreFilters()`: Spread, ATR, time, news
   - `GetBias()`: Market bias determination
   - `GetAutoStratSignal()`: Entry signal generation
   - `CheckHTF()`: Higher timeframe filter
   - `CheckRRMGates()`: Pullback/divergence gates
   - `CountVotes()`: Indicator voting

3. **Indicator Checkers**:
   - `Check_EMA1()`, `Check_ADX()`, `Check_MACD()`, etc.
   - Each returns boolean (pass/fail)

### Performance Considerations

1. **Indicator Handles**
   - Created once in OnInit()
   - Reused on every tick
   - Proper cleanup in OnDeinit()

2. **Calculation Efficiency**
   - Only evaluate when new bar forms
   - Early exit on any failure (short-circuit)
   - Minimal indicator reads

3. **Memory Management**
   - No dynamic arrays in hot paths
   - Fixed buffer sizes
   - No heap allocations per tick

---

**Version:** v1.02.016d-05-9_RRM  
**Last Updated:** 2026-02-15
