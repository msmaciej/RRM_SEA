# SimpleEA v1.02.005 - Institutional Elastic Trading Framework

**Current Version:** 1.02.005  
**Platform:** MetaTrader 5 (MQL5)  
**Architecture:** Elastic Voting System with Decoupled Bias & Master Filters

---

## 1. Overview
SimpleEA v1.02.005 represents a complete architectural redesign of the original concept. It moves away from rigid, hard-coded logic into a modular **"Voting System."** Unlike traditional EAs that require *all* conditions to be met (AND logic), this EA allows for **Elastic Confluence**:
1.  **Narrative (Bias):** Defines the trade direction (Long/Short/Neutral).
2.  **Master Filter (HTF):** A higher timeframe "Veto" check.
3.  **Voting (Confluence):** A suite of 11 indicators and patterns that "vote" on the entry. If the `Voting Threshold` is met, the trade is taken.

---

## 2. Key Features
* **Decoupled Bias:** The trend direction (Bias) is determined separately from the entry triggers.
* **Higher Time Frame (HTF) Filter:** Optional "Boss" filter (e.g., trade H1 only if H4 trend aligns).
* **Volume Integration:** Uses **MFI (Money Flow Index)** to confirm institutional money flow behind price moves.
* **Price Action Patterns:** Includes **Mark Crisp 1-2-3** and **Ross Hook** fractal breakout patterns.
* **Elastic Inputs:** All settings are native MQL5 Inputs (no external JSON required).
* **Advanced Trailing:** Includes ATR, PSAR, and Fractal (Swing) trailing stops.

---

## 3. The Logic Flow

### Phase 1: Bias Determination
The EA asks: *"Which direction are we trading?"*
* **Auto:** Determined by EMA Slopes or Crossovers.
* **Manual:** User can force `Long Only` or `Short Only` (useful for fundamental traders).

### Phase 2: The Veto (HTF Filter)
If enabled, the EA checks the Higher Time Frame.
* *Example:* If Trading on H1, but H4 Trend is Down -> **NO BUY TRADES**, regardless of other indicators.

### Phase 3: The Voting System
The EA tallies votes from enabled indicators.
* **Input:** `InpVotingThreshold` (Default: 4).
* **Logic:** If you enable 6 indicators, and 4 of them say "GO", the trade executes.
* **Benefit:** One noisy indicator cannot block a high-probability trade.

---

## 4. Expert Strategy Configurations
*To avoid "Indicator Conflict" (Multicollinearity), our trading experts recommend specific setups. Do not simply enable everything.*

### Setup A: "The Trend Follower" (Classic)
*Best for: Strong trending pairs (GBP, JPY).*
* **Bias:** Auto (Pair Cross).
* **HTF Filter:** ON.
* **Voting Threshold:** 3.
* **Active Votes:**
    1.  ADX (Trend Strength).
    2.  EMA Recovery (Price Value).
    3.  MACD (Momentum).
    4.  MFI (Volume Support).

### Setup B: "The Breakout Trader" (Price Action)
*Best for: Volatile sessions (London/NY Open).*
* **Bias:** Manual or Auto.
* **HTF Filter:** ON.
* **Voting Threshold:** 2.
* **Active Votes:**
    1.  **Ross Hook** (Breakout Trigger).
    2.  **Pattern 1-2-3** (Structure Trigger).
    3.  MFI (Volume Confirmation).
    *Note: Turn OFF Oscillators (RSI/Stoch) for this setup to avoid lag.*

### Setup C: "The Swing Sniper" (Reversal/Deep Pullback)
*Best for: Ranging or Slow trends.*
* **Bias:** Auto (Single Slope).
* **Voting Threshold:** 4.
* **Active Votes:**
    1.  RSI (Filter Extremes).
    2.  Stochastic (Cross).
    3.  CCI (Momentum).
    4.  Bollinger Bands (Trend Mode).

---

## 5. Expert Usage Guidelines & Best Practices
*Critique and advice from our Institutional Trading Advisors.*

### ⚠️ Avoid Multicollinearity
Do not enable RSI, Stochastic, and CCI simultaneously unless you have a specific reason. They all measure momentum. If you enable all three, you are effectively counting the "same vote" three times, which distorts the voting logic.
* **Rule of Thumb:** Choose **ONE** Momentum Oscillator per setup.

### ⚠️ Spread Management
This EA currently trades on **Bar Close**.
* **Warning:** Do not run this EA during the "Rollover" period (22:00 - 23:00 GMT) or during low-liquidity Asian sessions for high-spread pairs. The current version does not have a Time Filter to block these hours automatically.

### ⚠️ News Events
* **Advisor Note:** High-impact news can invalidate technical patterns (like Fractals) instantly. It is recommended to disable `AutoTrading` during NFP, FOMC, or CPI releases.

---

## 6. Installation
1.  Copy `SimpleEA_v1-02-005.mq5` to your MT5 Data Folder: `MQL5\Experts\`.
2.  (Optional) Read `README_INDICATORS.md` for detailed mathematical logic of each tool.
3.  Compile in MetaEditor.
4.  Attach to chart. Adjust `InpVotingThreshold` based on how many indicators you enable.

---

## 7. Development Roadmap
*Based on expert feedback, the following features are planned for v1.03:*
1.  **Time Scheduler:** Auto-sleep during high-spread hours.
2.  **Breakeven Function:** Move Stop Loss to Entry price after `X` pips profit.
3.  **Weighted Voting:** Assign higher "Vote Weight" to structural patterns (Ross Hook) vs. oscillators.