# The 1 Minute Scalper (RH_1MS) — candidate preset design

**Status: NOT YET IMPLEMENTED.** No scalper preset exists in the enum
(`FPM, MA, RRM_ORG, TOPINVESTOR, XEMA, TURTLE, TREND, RH_REBELLION`). Design-stage artifact for a
future `PRESET_RH_1MS`, staged like `_RH_REBELLION` before implementation. Source in `_RH_1MS/`:
`1-minute-scalper.pdf`, `1-minute-scalper.jpg`, `1_minute_scalper.tpl`. Iconographic:
`_RH_1MS/FX-1MIN-SCALPER-Trading_System_v01.png`.

---

## 0. Pipeline reminder — same TS / TE / TM as every preset

**TS** (`EvaluateTS`, bar close) → **TE** (`EvaluateTE`, bar open, Policy-A gates) → **TM**
(`EvaluateTM`, while open). For this system: **B** = 50 EMA vs 100 EMA stack + retrace-to-EMAs;
**I** = Stochastic 20/80 cross; **P** inert; **TM** = tight swing/EMA SL + fixed 7–12 pip TP. The
retrace step maps onto the Layer pullback gate rather than a separate factor.

---

## A. Canonical system (from the manual)

A simple **M1 pullback scalp**: trade with a fast/slow EMA stack, but only after price retraces to the
EMAs and the Stochastic turns back out of its extreme. Fast in, fast out, with a fixed small target.

### Components (exact — manual + `1_minute_scalper.tpl`, which agree)
| Indicator | Settings | Colour |
|-----------|----------|--------|
| 100 EMA | period 100, **EMA**, apply Close | Crimson |
| 50 EMA | period 50, **EMA**, apply Close | Green |
| Stochastic | %K **5** / slowing **3** / %D **3**, Low/High, Simple, levels 20/80 | — |

- **Timeframe: M1 only.** Pairs: low-spread majors (EUR/USD, GBP/USD, AUD/USD). The manual stresses
  that **low spread is essential** — on M1 a wide spread eats the whole edge.

### Long entry rules
1. **50 EMA above 100 EMA** (trade longs only).
2. Wait for price to **retrace back to the EMAs**.
3. **Stochastic crosses above 20** from below (the entry trigger).
4. All met → buy at the signal-candle close.
5. **Stop Loss** 2–3 pips below the last swing low **or** the 100 EMA — whichever is **closer**.
6. **Take Profit** 7–12 pips from entry.

### Short entry rules (mirror)
1. **50 EMA below 100 EMA** (shorts only).
2. Wait for price to **retrace back to the EMAs**.
3. **Stochastic crosses below 80** from above.
4. All met → sell at the signal-candle close.
5. **SL** 2–3 pips above the last swing high or the 100 EMA (nearer).
6. **TP** 7–12 pips.

### Worked examples (manual)
- **Long — EUR/USD M1:** 50>100 EMA; price retraced to the 100 EMA; Stochastic crossed above 20. Entry
  on close **1.29333**; SL **1.29273** (−6, = 2 pips below the swing low); TP **1.29453** (+12), hit
  4 min later.
- **Short — AUD/USD M1:** 50<100 EMA; price retraced between the 50 and 100 EMA; Stochastic crossed
  below 80. Entry **1.02397**; SL **1.02445** (+3 above the swing high); TP **1.02277** (−12), hit
  9 min later.

---

## B. How it would map onto the SEA TS / TE / TM pipeline

| Stage | 1-Min Scalper wiring | Status in SEA |
|-------|----------------------|---------------|
| **B** (direction) | 50 EMA vs 100 EMA position + retrace to the EMAs | reuse `BIAS_2EMA` (EMA50/100); retrace ≈ the Layer pullback gate |
| **P / L** | P inert; retrace uses the pullback logic | mostly existing |
| **I** voter | Stochastic(5,3,3) cross 20-up / 80-down | reuse Stochastic voter with a **level-cross (20/80)** mode |
| **TE** | fire on close; strict low-spread gate | shift=1 + `MaxSpread` (Policy-A) — already present |
| **TM** | SL = nearer of {swing ±2–3p, 100 EMA}; TP = 7–12 fixed pips | swing SL + fixed-pip TP exist; add the "or the 100 EMA" SL clause |

The TS core and TE gate chain are **unchanged** — shared with every preset.

---

## C. Open items before it can be coded (honest gaps — the smallest of the set)

This is the **lightest lift** of the Russ Horn candidates: everything is EMA-on-close (no per-slot
applied-price change needed, unlike the Golden/Super/Sea-Trading systems), the Stochastic voter already
exists, and the fixed-pip TP is standard. The only genuinely new pieces:

1. **Stochastic 20/80 level-cross mode.** The rule is "cross above 20 from below" / "cross below 80
   from above" — a *level* cross, distinct from the existing main-vs-signal cross (`STO_CROSS_SIGNAL`).
   Add an `STO_LEVEL_CROSS` mode (or reuse the RSI-style level-cross once that exists for RH_STS).
2. **"or the 100 EMA" SL clause.** SL is the *nearer* of the swing-based stop and the 100 EMA — a small
   `min()` addition to the swing SL chain (same shape as the Golden Strategy's swing/band SL).
3. **Retrace-to-EMA gate.** "Wait for price to retrace back to the EMAs" — the RRM Layer pullback
   machinery already models pullback→recovery; here it would gate on price returning into the 50/100
   EMA zone before the Stochastic trigger.

### Template vs manual — consistent
`1_minute_scalper.tpl` confirms 100 EMA and 50 EMA (both `method=1` = EMA, `apply=0` = close) and
Stochastic slowing=3 — matching the manual. No discrepancy.

---

## D. Quick reference

```
Trend  : 50 EMA vs 100 EMA (EMA, close)        Setup: price retraces to the EMAs
Long   : 50>100  AND  retrace  AND  Stoch cross 20-up      → BUY on close
Short  : 50<100  AND  retrace  AND  Stoch cross 80-down    → SELL on close
TM     : SL = nearer of {swing ±2-3p, 100 EMA} ; TP = fixed 7-12 pips
Notes  : M1 only ; low spread essential (Policy-A MaxSpread gate)
Status : candidate PRESET_RH_1MS (not built) — new: Stoch 20/80 level-cross, "or 100 EMA" SL clause
```
