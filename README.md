## Trade Signal Logic: How TS and TE Work

### Core Concept: Shift-Based Signal Evaluation

The SimpleEA system implements a **two-phase trading logic** that separates **Trade Signal (TS) evaluation** from **Trade Entry (TE) execution**:

### Phase 1: Trade Signal Evaluation (TS) on shift=1

**TS** is evaluated on the **completed candle** (shift=1) using a **multiplicative voting system**:

```
TS = Market_Bias × Indicator₁ × Indicator₂ × ... × Indicatorₙ
```

Where:
- **Market_Bias** ∈ {-1, 0, 1} = {SHORT, NEUTRAL, LONG}
- Each **Indicator** ∈ {0, 1} = {DISAGREE, AGREE with bias}

**Critical Rule:**
- **TS = 1** (valid LONG signal) ONLY if:
  - Market_Bias = 1 (LONG bias detected)
  - AND ALL enabled indicators vote 1 (agree with LONG bias)
  - AND votes ≥ VoteThreshold

- **TS = -1** (valid SHORT signal) ONLY if:
  - Market_Bias = -1 (SHORT bias detected)
  - AND ALL enabled indicators vote 1 (agree with SHORT bias)
  - AND votes ≥ VoteThreshold

- **TS = 0** (no signal) if:
  - Market_Bias = 0 (NEUTRAL/choppy market)
  - OR any enabled indicator votes 0 (disagrees)
  - OR votes < VoteThreshold

### Phase 2: Trade Entry Execution (TE) on shift=0

**When a new candle opens** (shift=0):
- IF **TS = 1** was evaluated on shift=1 → **TE = 1** → **ENTER LONG**
- IF **TS = -1** was evaluated on shift=1 → **TE = 1** → **ENTER SHORT**
- IF **TS = 0** was evaluated on shift=1 → **TE = 0** → **NO TRADE**

**Important:** 
- We do NOT re-evaluate TS at shift=0
- The trade entry happens immediately at the open of the new candle
- This ensures stable, confirmed signals based on closed candles

### Indicator Voting Example

**Scenario:** 4 indicators enabled with VoteThreshold = 4

**Evaluation at shift=1 (completed candle):**

1. **Market Bias Check:**
   - EMA Fast (13) > EMA Slow (34) ✅
   - Both EMAs sloping UP ✅
   - **Result: Market_Bias = 1 (LONG)**

2. **Indicator Voting:**
   - MACD: Main > Signal AND Main > 0 → Vote = 1 ✅
   - PSAR: Price > PSAR → Vote = 1 ✅
   - RSI: RSI < 70 (not overbought) → Vote = 1 ✅
   - CCI: CCI > 0 → Vote = 1 ✅
   - **Total Votes: 4**

3. **Trade Signal Calculation:**
   ```
   TS = Market_Bias × MACD × PSAR × RSI × CCI
   TS = 1 × 1 × 1 × 1 × 1 = 1 ✅
   
   Votes (4) >= VoteThreshold (4) ✅
   
   → TS = 1 (VALID LONG SIGNAL)
   ```

4. **Trade Entry at shift=0:**
   - New candle opens
   - TS = 1 was confirmed on shift=1
   - **TE = 1 → ENTER LONG IMMEDIATELY**

### Why This Logic Is Powerful

**1. Multiplicative System = Strict Filtering**
- ANY indicator disagreement → TS = 0
- Forces all components to align before entry
- Reduces false signals dramatically

**2. Shift=1 Evaluation = Confirmation**
- Uses CLOSED candles only
- No repainting or flickering signals
- Stable, backtestable results

**3. Shift=0 Entry = Speed**
- Enters at the OPEN of the new candle
- No delay after signal confirmation
- Optimal fill prices

### Signal Flow Visualization

```
Candle N (shift=1 - CLOSED)
├─ Step 1: Check Market Bias (L/S/N)
│  └─ If NEUTRAL → TS = 0 → STOP
├─ Step 2: Check AutoStrat Entry Signal
│  └─ Must match Bias → or STOP
├─ Step 3: Check HTF Filter (if enabled)
│  └─ Must align → or STOP
├─ Step 4: Check RRM Gates (if enabled)
│  └─ Must pass → or STOP
├─ Step 5: Evaluate ALL Enabled Indicators
│  ├─ MACD vote: 1 or 0
│  ├─ PSAR vote: 1 or 0
│  ├─ RSI vote: 1 or 0
│  ├─ CCI vote: 1 or 0
│  └─ ... (all enabled indicators)
├─ Step 6: Calculate TS
│  └─ TS = Bias × (all indicator votes multiplied)
└─ Step 7: Check Vote Threshold
   ├─ If votes >= threshold → TS confirmed
   └─ If votes < threshold → TS = 0

Candle N+1 (shift=0 - OPENING)
└─ IF TS ≠ 0 → TE = 1 → EXECUTE TRADE
   └─ No re-evaluation needed!
```

### Example: Failed Signal

**If ANY indicator disagrees:**

```
Market_Bias = 1 (LONG)
MACD = 1 ✅
PSAR = 1 ✅
RSI = 0 ❌ (RSI > 70, overbought)
CCI = 1 ✅

TS = 1 × 1 × 1 × 0 × 1 = 0

→ TS = 0 (NO SIGNAL)
→ TE = 0 (NO TRADE)
```

**Result:** Trade is rejected because RSI disagrees with the bias. This prevents buying into overbought conditions.
