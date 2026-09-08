# The Super System (RH_STS) — candidate preset design

**Status: NOT YET IMPLEMENTED.** No Super-System preset exists in the enum today
(`FPM, MA, RRM_ORG, TOPINVESTOR, XEMA, TURTLE, TREND, RH_REBELLION`). This is a **design-stage**
artifact for a future `PRESET_RH_STS`, staged like `_RH_REBELLION` was before implementation.
Source material in `_RH_STS/`: `RussHorn_Forex_-_RRM_-_SS_-_Super_System_Strategy.pdf` (manual),
`The_Super_System.jpg` (annotated chart), `the_super_system.tpl` (MT4 template). Iconographic:
`_RH_STS/FX-SUPER-Trading_System_v01.png`.

> **Why this one fits SEA especially well.** The Super System is essentially an explicit, literal
> Russ Horn system built on the **same 34/89 trend backbone** the RRM ribbon uses, plus a fast
> EMA-cross trigger and a three-oscillator confirmation stack. Much of it maps onto knobs the engine
> already has; the gaps are small and enumerated in §C.

---

## A. Canonical system (from the manual)

A deliberately **conservative** method — "fewer signals but more secure ones" — usable on any
timeframe, majors. A trade needs **all five** conditions (one trend filter, one trigger, three
confirmations) true in **any order**.

### Components (exact — confirmed from `the_super_system.tpl`)
| # | Indicator | Settings | Colour |
|---|-----------|----------|--------|
| 1 | 3 EMA | period 3, EMA, apply **Close** | Lime |
| 2 | 5 EMA | period 5, EMA, apply **Open** | Red |
| 3 | 34 EMA | period 34, EMA, apply Close | Aqua |
| 4 | 89 EMA | period 89, EMA, apply Close | Magenta |
| 5 | RSI | period **3**, levels **20 / 80** | DodgerBlue |
| 6 | Stochastic | **(5,3,3)** default, levels 20 / 80 | — |
| 7 | ADX | period 14, **+DI / −DI only** (main ADX hidden) | +DI Lime / −DI Red |

Two details the manual text alone underplays, both verified in the template: the **5 EMA is applied
to the open price** (`apply=1`), and the ADX is used in **DI-directional** form (+DI vs −DI), not as a
trend-strength reading.

### Long entry rules
1. **34 EMA above 89 EMA** (long-term trend up — filter).
2. **3 RSI crosses above the 80 level.**
3. **Stochastic above its Signal line.**
4. **+D ADX above the −D line.**
5. **3 EMA crosses above 5 EMA** (trigger).
6. All met, in any order → open a **buy**.
7. **Stop Loss** below the 34 EMA or the last swing low.
8. **Take Profit** = **2× the Stop Loss** (2R), **or** close on an opposite signal — defined as:
   3 EMA falls below 5 EMA, 3 RSI falls below 20, and +D falls below −D.

### Short entry rules (mirror)
1. **34 EMA below 89 EMA** (trend down).
2. **3 RSI crosses under 20.**
3. **Stochastic below its Signal line.**
4. **−D ADX above +D.**
5. **3 EMA crosses under 5 EMA.**
6. All met, any order → **sell**.
7. **SL** above the 34 EMA or last swing high.
8. **TP** = 2× SL, or opposite-signal close (3 EMA above 5 EMA, 3 RSI above 20, −D below +D).

> **Note the RSI logic.** Long requires **RSI(3) crossing *above* 80** (and short below 20). With a
> 3-period RSI this is a **momentum-burst** trigger, not the usual "RSI > 50 = uptrend" reading — it
> fires on a sharp thrust into overbought. Faithful implementation needs an RSI **80/20 level-cross**
> test, not a midline-trend test.

### Worked examples (manual)
- **Long — EUR/JPY M5:** 34>89 and +D>−D established the up-trend; 3 EMA crossed 5 EMA up while
  Stochastic moved above its signal; RSI>80 was the last trigger. Entry @ **103.572**; SL @ **103.492**
  (−8 pips, below 34 EMA); TP @ **103.732** (+16 = 2R), hit in under an hour.
- **Short — AUD/USD H1:** 34<89; 3 EMA below 5 EMA; Stochastic below signal; −D above +D; RSI<20 the
  trigger. Entry @ **1.04959**; SL @ **1.05319** (+36, above swing high); TP @ **1.04239** (−72 = 2R),
  hit 11h later.

---

## B. How it would map onto the SEA TS/TE pipeline

`TS = B × P × F × L × I → CG`, then TE.

| Factor | Super System wiring |
|--------|---------------------|
| **B** (trend/direction) | 34 EMA vs 89 EMA position — the RRM slow backbone. `BIAS_2EMA` on EMA34/EMA89, or reuse the RRM 4-EMA phase's slow pair. |
| **Trigger** | 3 EMA(close) × 5 EMA(open) cross — the entry event. |
| **P / L** | Not the RRM layer machine; the 34/89 filter + 3×5 trigger stand in for phase/layer. |
| **I** (voters, unanimous) | RSI(3) 80/20 level-cross + Stochastic(5,3,3) main-vs-signal + ADX(14) +DI/−DI direction. |
| **Exit** | SL = nearest of {34 EMA, swing}; TP = **2R** (`RRRatio = 2`) **or** opposite-signal close (`CloseOnReverse`-style, on 3×5 + RSI + DI). |

Already present in the engine: Stochastic main-vs-signal vote (`STO_CROSS_SIGNAL`), swing SL, 2R TP,
close-on-reverse. No new indicator **file** is required.

---

## C. Open items before it can be coded (honest gaps)

1. **Per-slot applied price.** The 5 EMA is on the **open**; every other MA is on the close. The MA
   slots need an `apply`-price per slot (the same class of change flagged for the Sea Trading System's
   mixed EMA/SMA pair).
2. **RSI 80/20 level-cross vote.** `RsiMode` today is `RSI_TREND_ABOVE_50`. Super System needs an
   **`RSI_LEVEL_CROSS`** mode (long: cross **above 80**; short: cross **below 20**).
3. **ADX +DI/−DI directional vote.** SEA's ADX is a trend-**strength** gate (`ADX_MODE_*`). This needs
   a **DI-cross** vote (`+DI > −DI` long / `−DI > +DI` short).
4. **"34 EMA or swing" SL** and the compound **opposite-signal exit** (3×5 cross + RSI level + DI flip)
   need wiring into the exit chain (2R is standard `RRRatio=2`).

### Template vs manual — consistent
Unlike the Sea Trading System, the template matches the manual here: all four MAs are EMA
(`method=1`), periods 3/5/34/89, with the 5 EMA correctly on `apply=Open`. No discrepancy to resolve.

---

## D. Quick reference

```
Trend  : EMA34 > EMA89 (long) / < (short)         Trigger: EMA3(close) x EMA5(open) cross
Confirm: RSI(3) cross 80/20 + Stoch(5,3,3) vs signal + ADX(14) +DI/-DI   (unanimous)
SL     : nearest of {34 EMA, swing}               TP: 2R  OR  opposite-signal close
Character: conservative (fewer, surer)            Status: candidate PRESET_RH_STS (not built)
```
