# The Secret Method (RH_SM) — candidate preset design

**Status: NOT YET IMPLEMENTED.** No Secret-Method preset exists in the enum
(`FPM, MA, RRM_ORG, TOPINVESTOR, XEMA, TURTLE, TREND, RH_REBELLION`). This is a **design-stage**
artifact for a future `PRESET_RH_SM`, staged like `_RH_REBELLION` before implementation. Source in
`_RH_SM/`: `RussHorn_Forex_-_RRM_-_SM_-_Secret_Method.pdf`, `the_Secret_method.jpg`,
`3_secret_method.tpl`. Iconographic: `_RH_SM/FX-SECRET-Trading_System_v01.png`.

---

## 0. Pipeline reminder — it uses the same TS / TE / TM as every preset

A preset never invents its own evaluation path. Once coded, the Secret Method runs the identical
three stages every SEA preset uses:

- **TS — Trade Signal** (`EvaluateTS`, bar close / shift=1): the multiplicative `B × P × F × L × I → CG`.
  Different presets activate different factors; the equation is the same.
- **TE — Trade Entry** (`EvaluateTE`, next bar open / shift=0): the shared Policy-A gate chain
  (spread · session · news · open-delay · BC-recheck · lots · risk caps).
- **TM — Trade Management** (`EvaluateTM`, while open): SL / TP / break-even / trailing / early-exit.

For the Secret Method: **B** = Heiken Ashi vs 14 SMA; **I** = OsMA + Momentum + RSI (unanimous);
**P/L** inert (flat system, like FPM); **TM** = swing SL + 2R TP + an OsMA-zero-flip early exit.

---

## A. Canonical system (from the manual)

Deliberately **conservative** — in both *entering* and *managing* trades — and usable on any timeframe,
majors. Heiken Ashi smooths the candles so the trend read is cleaner; three oscillators must then
agree.

### Components (exact — manual + `3_secret_method.tpl`, which agree)
| Indicator | Settings | Reference level |
|-----------|----------|-----------------|
| Heiken Ashi | smoothed candles (custom) | vs 14 SMA |
| 14 SMA | period 14, **SMA**, apply Close | trend line |
| OsMA | (12,26,9) default | 0 line |
| Momentum | period **10** | 100 line |
| RSI | period **5** | 50 line |

> **OsMA = MACD histogram.** In MT4 the "Moving Average of Oscillator" is `MACD_main − signal_line`,
> i.e. the MACD histogram. "OsMA crosses 0" therefore equals "MACD main crosses its signal" — which
> maps directly onto SEA's `MACD_HISTOGRAM` vote logic.

### Long entry rules
1. A **bullish (white) Heiken Ashi** candle crosses **above** the 14 SMA.
2. **OsMA** crosses **above** its Zero level.
3. **Momentum(10)** crosses **above 100**.
4. **RSI(5)** crosses **above 50**.
5. All met → wait for the current candle to **close**, then **buy**.
6. **Stop Loss** a few pips below the last swing low.
7. **Take Profit** = **double the Stop Loss** (2R).
8. **Early exit:** close the long *without* waiting for TP when **OsMA crosses back below Zero**.

### Short entry rules (mirror)
1. **Bearish (red) Heiken Ashi** crosses **below** the 14 SMA.
2. **OsMA** below Zero.
3. **Momentum(10)** below 100.
4. **RSI(5)** under 50.
5. All met → wait for close, then **sell**.
6. **SL** a few pips above the last swing high.
7. **TP** = 2× SL.
8. **Early exit:** close the short when **OsMA crosses back above Zero**.

### Worked examples (manual)
- **Long — EUR/USD M5:** price above 14 SMA as white HA candles; OsMA above 0 for two bars; Momentum
  just above 100; RSI above 50. Entry after close @ **1.29479**; SL @ **1.29399** (−8, below swing
  low); TP @ **1.29639** (+16 = 2R), hit 35 min later.
- **Short — AUD/USD M30:** red HA below 14 SMA; OsMA below 0 (two candles prior); Momentum below 100;
  RSI just under 50. Entry @ **1.04938**; SL @ **1.05216** (+27.8, above swing high); TP @ **1.04382**
  (−55.6 = 2R).

---

## B. How it would map onto the SEA TS / TE / TM pipeline

| Stage | Secret Method wiring | Status in SEA |
|-------|----------------------|---------------|
| **B** (direction) | Heiken Ashi close/colour vs 14 SMA | **NEW** — Heiken Ashi input |
| **P / L** | inert (flat system) | — |
| **I** voter | OsMA 0-cross | reuse **`MACD_HISTOGRAM`** |
| **I** voter | Momentum(10) vs 100 | **NEW** — Momentum voter |
| **I** voter | RSI(5) vs 50 | reuse **`RSI_TREND_ABOVE_50`** (period 5) |
| **TE** | spread/session/news/lots/risk | unchanged (shared) |
| **TM** | SL = swing; TP = 2R (`RRRatio=2`); early exit on OsMA zero-flip | swing SL + 2R exist; **OsMA-flip early exit = new TM rule** |

The TS core and TE gate chain are **unchanged** — shared with every preset. `CandleBody`/`BD`-style
direction logic already exists but reads *real* candles; the Secret Method needs the **Heiken Ashi**
derived series specifically.

---

## C. Open items before it can be coded (honest gaps)

1. **Heiken Ashi series.** New derived-candle input (HA open/high/low/close recursion). The bias read
   is "bullish HA candle whose close is above the 14 SMA" (short: bearish, below). No such input today.
2. **Momentum(10) voter.** New voter: MT4 Momentum = `close / close[n] × 100`, oscillating about 100.
   Long passes when it crosses **above 100**, short below. Trivial to compute, but not currently a voter.
3. **OsMA vote = MACD histogram.** Reuse `MACD_HISTOGRAM` with periods (12,26,9); "cross 0" is the
   histogram sign. No new indicator file.
4. **OsMA-zero-flip early exit (TM).** A management rule: close the position when the OsMA/MACD
   histogram crosses back through zero against the trade. New `EvaluateTM` exit condition (2R TP and
   swing SL already exist).

### Template vs manual — consistent
`3_secret_method.tpl` contains Heiken Ashi, Moving Average (period 14, **method=0 = SMA**, close),
OsMA, Momentum and RSI — matching the manual exactly. No discrepancy to resolve (unlike the Sea
Trading System's EMA-vs-SMA slip).

---

## D. Quick reference

```
Trend  : Heiken Ashi candle vs 14 SMA (SMA, close)
Confirm: OsMA(12,26,9) cross 0  +  Momentum(10) cross 100  +  RSI(5) cross 50   (unanimous)
Enter  : on candle close after all four align
TM     : SL = last swing (+few pips) ; TP = 2R ; EARLY EXIT on OsMA zero-flip
Pipeline: TS (B×I, P/L inert) → TE (Policy-A gates) → TM (this exit set)
Status : candidate PRESET_RH_SM (not built) — new: Heiken Ashi input, Momentum voter, OsMA-flip exit
```
