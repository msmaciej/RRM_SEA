# The Golden Strategy (RH_GS) — candidate preset design

**Status: NOT YET IMPLEMENTED.** No Golden-Strategy preset exists in the enum
(`FPM, MA, RRM_ORG, TOPINVESTOR, XEMA, TURTLE, TREND, RH_REBELLION`). This is a **design-stage**
artifact for a future `PRESET_RH_GS`, staged like `_RH_REBELLION` before implementation. Source in
`_RH_GS/`: `RussHorn_Forex_-_RRM_-_GS_-_Golden_Strategy.pdf`, `Golden_System.JPG`,
`golden_strategy.tpl`. Iconographic: `_RH_GS/FX-GOLDEN-Trading_System_v01.png`.

---

## 0. Pipeline reminder — same TS / TE / TM as every preset

Once coded, the Golden Strategy runs the identical three stages every SEA preset uses:
**TS** (`EvaluateTS`, bar close, `B × P × F × L × I → CG`) → **TE** (`EvaluateTE`, bar open,
Policy-A gate chain) → **TM** (`EvaluateTM`, while open: SL/TP/exit). For this system: **B** = price
vs the 55-SMMA High/Low channel; **I** = Williams %R + Stochastic (unanimous); **P/L** inert (channel
system, like Turtle/Trend); **TM** = swing SL + 2R TP + an SMMA-re-cross early exit.

---

## A. Canonical system (from the manual)

A high-win-rate **channel breakout**, tradeable on any timeframe, majors. Two 55-period Smoothed MAs —
one on the **highs**, one on the **lows** — form a band; a break through the relevant edge, confirmed
by Williams %R and Stochastic, is the trade.

### Components (exact — manual + `golden_strategy.tpl`, which agree)
| Indicator | Settings | Colour |
|-----------|----------|--------|
| 55 SMMA (High) | period 55, **Smoothed (SMMA)**, apply **High** | Green |
| 55 SMMA (Low) | period 55, **Smoothed (SMMA)**, apply **Low** | Crimson |
| Williams %R | period **55**, levels **−25 / −75** | Aqua |
| Stochastic | %K **5** / slowing **5** / %D **5**, Low/High, Simple, levels 20/80 | — |

> **The "channel" is an SMMA High/Low envelope.** Because one SMMA is fed the bar highs and the other
> the bar lows, they bracket price like an envelope. This is a close cousin of the Turtle/Trend
> **Donchian** breakout — but the band is a smoothed-MA envelope rather than an N-bar high/low.

### Long entry rules
1. Price crosses **above** the 55 SMMA set to **High** (green).
2. Williams **%R(55) crosses above −25**.
3. Stochastic is **above** its Signal line.
4. Two entry styles: **Aggressive** — buy without waiting for the signal candle to close; or
   **Conservative** — wait for the candle to **close above** the 55-SMMA-High first (confirmation).
5. **Stop Loss** a few pips below the most recent swing low.
6. **Take Profit** = **2× the Stop Loss**, **or** close when price **closes below** the 55-SMMA-High.

### Short entry rules (mirror)
1. Price crosses **below** the 55 SMMA set to **Low** (crimson).
2. Williams **%R(55) crosses below −75**.
3. Stochastic is **below** its Signal line.
4. Aggressive (no close wait) or Conservative (wait for close **below** the 55-SMMA-Low).
5. **SL** a few pips above the most recent swing high.
6. **TP** = 2× SL, or close when price **closes above** the 55-SMMA-Low.

### Worked examples (manual)
- **Long — GBP/USD M5:** price crossed above the 55-SMMA-High, %R above −25, Stochastic above its
  signal. Entry on close **1.60715**; SL **1.60655** (−6, below swing low); TP **1.60835** (+12 = 2R),
  hit 35 min later.
- **Short — EUR/USD M5:** price below the 55-SMMA-Low, %R below −75, Stochastic below signal. Entry
  **1.29760**; SL **1.29920** (above swing high); TP **1.29440** (2R), hit 40 min later.

---

## B. How it would map onto the SEA TS / TE / TM pipeline

| Stage | Golden Strategy wiring | Status in SEA |
|-------|------------------------|---------------|
| **B** (direction) | price vs 55-SMMA-High (long) / 55-SMMA-Low (short) — channel break | **NEW** — SMMA method + per-slot High/Low applied price |
| **P / L** | inert (channel system) | — |
| **I** voter | Williams %R(55) cross −25 / −75 | **NEW** — Williams %R voter |
| **I** voter | Stochastic(5,5,5) main vs signal | reuse **`STO_CROSS_SIGNAL`** |
| **TE** | Aggressive (shift 0, intrabar) / Conservative (shift 1, on close) | shift toggle (Conservative = engine default) |
| **TM** | SL = swing; TP = 2R (`RRRatio=2`); exit on price re-crossing the entry SMMA | swing SL + 2R exist; **SMMA-re-cross exit = new TM rule** |

The TS core and TE gate chain are **unchanged** — shared with every preset.

---

## C. Open items before it can be coded (honest gaps)

1. **SMMA method + High/Low applied price per slot.** Both MAs are **Smoothed** (`iMA` `MODE_SMMA`),
   one on **High**, one on **Low**. SEA presets today expose SMA/EMA on close only; this needs an SMMA
   `MaType` and a per-slot applied-price (the same per-slot applied-price work the Super System and Sea
   Trading System also need). `iMA` supports both natively, so no new indicator file.
2. **Williams %R(55) voter.** New voter: `iWPR`, long passes on a cross **above −25**, short on a cross
   **below −75**. (Not currently among SEA's voters.)
3. **Aggressive vs Conservative toggle.** Conservative = evaluate on the closed bar (shift=1, engine
   default). Aggressive = intrabar (shift=0). A profile input selects between them.
4. **SMMA-re-cross TM exit.** A management exit: close when price closes back across the entry SMMA
   (below the High-SMMA for a long, above the Low-SMMA for a short) — conceptually the same shape as
   XEMA's reverse-cross exit. 2R TP and swing SL already exist.

### Template vs manual — consistent
`golden_strategy.tpl` confirms both MAs as **SMMA (`method=2`)** on **High (`apply=2`)** and
**Low (`apply=3`)**, Williams %R period 55, and Stochastic slowing=5 — matching the manual. No
discrepancy to resolve.

---

## D. Quick reference

```
Channel: 55 SMMA on High (green) + 55 SMMA on Low (crimson)
Long   : close > High-SMMA  AND  %R(55) > -25  AND  Stoch main > signal
Short  : close < Low-SMMA   AND  %R(55) < -75  AND  Stoch main < signal
Entry  : Aggressive (intrabar) OR Conservative (on close)   [shift toggle]
TM     : SL = last swing (+few pips) ; TP = 2R ; EXIT on price re-crossing the SMMA
Status : candidate PRESET_RH_GS (not built) — new: SMMA+High/Low slots, Williams %R voter, SMMA-recross exit
```
