# Indicator Logic & Modes Reference

This document details the specific logic implementation for every indicator available in **SimpleEA v1.02**.

---

## Indicator Families (Avoid Conflicts)
*To prevent "echo chamber" signals, try to pick one tool from each family rather than three from the same family.*

| Family | Indicators | Role | Risk of Overlap |
| :--- | :--- | :--- | :--- |
| **Momentum** | RSI, CCI, Stochastic, MACD | Detects overbought/oversold | **HIGH** (Pick 1) |
| **Trend** | ADX, PSAR, EMA Signal | Detects direction strength | Medium |
| **Structure** | Ross Hook, Pattern 1-2-3 | Detects breakouts | Low (Complimentary) |
| **Volume** | MFI | Detects money flow | Low (Unique) |


## 1. Master Filters

### Market Bias (The Narrative)
* **Role:** Determines the *only* allowed direction for trading.
* **Modes:**
    * `MANUAL`: You force the direction (Long/Short).
    * `AUTO (Single Slope)`: Bias is determined by the slope of the Slow EMA (EMA4).
    * `AUTO (Pair Cross)`: Bias is Long if Fast EMA > Slow EMA (and vice versa).

### HTF Filter (The Boss)
* **Role:** A "Hard Veto". It does not cast a vote; it blocks the trade entirely if it disagrees.
* **Logic:** Calculates the slope of an EMA on the Higher Time Frame (e.g., H4). Trade Chart Bias must match HTF Slope.

---

## 2. Voting Indicators
*These indicators contribute to the `InpVotingThreshold`. If `Votes >= Threshold`, a trade is opened.*

### 1. EMA Signal (Recovery)
* **Type:** Trend/Value.
* **Logic:**
    * **Buy:** Price must be *above* EMA1 (Fastest EMA).
    * **Concept:** Ensures we are not catching a falling knife. Price must have recovered above the short-term average.

### 2. ADX (Trend Strength)
* **Type:** Filter (Directionless).
* **Logic:** `ADX Value > Threshold` (Default 20).
* **Concept:** Prevents trading in dead/flat markets. It votes "Yes" if there is *any* strong trend, regardless of direction.

### 3. MACD (Momentum)
* **Type:** Oscillator.
* **Modes:**
    * `SIGNAL_ALIGN`: Buy if MACD Main Line > Signal Line.
    * `ZERO_CROSS`: Buy if MACD Main Line > 0.

### 4. RSI (Relative Strength Index)
* **Type:** Momentum / Mean Reversion.
* **Modes:**
    * `FILTER_EXTREME`: Votes YES if price is **NOT** Overbought (for Buy) or **NOT** Oversold (for Sell). "Safe to enter."
    * `TREND_ABOVE_50`: Votes YES if RSI > 50 (Bullish context).
    * `CROSS_LEVEL`: Votes YES if RSI is recovering from Oversold (Buy).

### 5. CCI (Commodity Channel Index)
* **Type:** Pure Momentum.
* **Modes:**
    * `TREND_ZERO`: Buy if CCI > 0.
    * `IMPULSE_100`: Buy if CCI > 100 (Strong impulse).

### 6. MFI (Money Flow Index)
* **Type:** Volume + Momentum.
* **Logic:** Checks if "Smart Money" is supporting the move.
    * **Buy:** MFI > 50 (Money flowing IN).
    * **Sell:** MFI < 50 (Money flowing OUT).

### 7. Stochastic
* **Type:** Momentum.
* **Modes:**
    * `CROSS_SIGNAL`: Buy if K line crosses above D line.
    * `ZONE_FILTER`: Buy if K line is not in Overbought zone.

### 8. Bollinger Bands
* **Type:** Volatility/Trend.
* **Modes:**
    * `TREND_FOLLOW`: Buy if Price > Middle Band.
    * `MEAN_REVERSION`: Buy if Price touches Lower Band (Buying the dip).

### 9. PSAR (Parabolic SAR)
* **Type:** Trend.
* **Logic:** Buy if Price is *above* the PSAR dots.

---

## 3. Price Action Patterns (Voting)
*These are high-quality triggers based on Fractal Geometry.*

### 10. Mark Crisp 1-2-3 Pattern
* **Type:** Structure Reversal / Continuation.
* **Logic (Buy):**
    1.  Find recent Low Fractal (Point 1).
    2.  Find recent High Fractal (Point 2).
    3.  Find recent Higher Low Fractal (Point 3).
    4.  **Signal:** Price breaks above Point 2.

### 11. Ross Hook
* **Type:** Trend Breakout.
* **Logic:** Identifies the first correction after a breakout.
    * **Buy:** Price breaks above the most recent Upper Fractal in an uptrend.
    * **Concept:** A simplified, robust implementation of the classic Ross Hook.

---

## 4. Trailing Logic
* `TRAIL_ATR`: Stop Loss moves based on volatility (Safe).
* `TRAIL_PSAR`: Stop Loss hops from dot to dot (Locks in trend).
* `TRAIL_FRACTAL`: Stop Loss moves to the most recent Swing Low (Professional choice for big trends).