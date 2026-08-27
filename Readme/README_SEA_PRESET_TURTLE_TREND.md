# PRESET_TURTLE & PRESET_TREND

**Status: IMPLEMENTED.** Both presets are coded inline in the existing SEA engine files.
No external indicator file is required — the Donchian breakout is computed inside
`SEA_SignalEngine.mqh`, exactly like ADX/CI/DPI. (`SEA_IND_Donchian.mq5` exists only as an
optional chart visualisation, mirroring the inline logic the way `SEA_IND_VPRR_Volume.mq5`
mirrors the VPRR voter — the presets do not depend on it.)

Both are breakout systems built on **one shared entry engine**:

- **`PRESET_TURTLE`** — Donchian breakout with **no trend filter**. The breakout is the trend.
- **`PRESET_TREND`** — the **same** breakout engine **gated by an EMA(20/50/200) stack + HTF
  confirmation**. This is the "Turtle + 3 EMAs" system.

`PRESET_XEMA` is unaffected — it remains the EMA-*crossover* trend follower. XEMA enters on a
cross; TURTLE/TREND enter on a channel breakout. Different trigger, different preset.

---

## 1. The shared idea — breakout of a price level = Donchian channel

"Price breaks recent resistance" and "price closes above the prior N-bar high" are the same
statement. The upper Donchian band (highest high of the last N bars) **is** recent resistance;
the lower band **is** recent support. So a support/resistance breakout, coded deterministically
for an EA, is a Donchian channel breakout — nothing subjective to draw.

The channel is measured **excluding the current bar** (anchored at `shift+1`), so a close
beyond it is a genuine break of the *prior* N-bar range, matching the classic Turtle definition
and the engine's `shift=1` evaluation.

---

## 2. How it maps onto the TS/TE pipeline

SEA evaluates `TS = B × P × F × L × I → CG`, then executes through the TE gate chain. Both
presets are a clean instantiation with the ribbon factors switched off:

| Factor | TURTLE | TREND |
|--------|--------|-------|
| **B** (direction) | Supplied by the breakout (`BIAS_MANUAL`). A break of the N-bar high = +1, the N-bar low = −1; no break = 0. | Same breakout, **then** gated by the EMA stack (see I). |
| **P** (phase) | Inert (breakout replaces phase). | Inert. |
| **L** (layer) | Inert (breakout is the entry timing). | Inert. |
| **I** (indicators) | **None** — all voters off. | **HTF confirmation** (MTF voter, 50/200) as a veto. |
| **F** / **CG** | Off. | Off (ADX available as optional anti-range). |

The EMA(20/50/200) direction gate in TREND is applied **inside the entry branch** (it reads the
ribbon snapshot), not as a separate voter — see §4.

**Exit** is the opposite Donchian channel (`Donchian_UseChannelExit = true`), plus the 2×ATR
initial stop. `TPMode = TP_MODE_NONE`, `CloseOnReverse = false` — the trade runs until the
channel exit or the stop. This is the "let profits run" design.

---

## 3. Entry — `STRAT_DONCHIAN_BREAKOUT` (`SEA_SignalEngine.mqh`)

A new `AutoStrat` branch in the STEP-2 dispatch of `EvaluateTS_Breakdown`:

```
n  = Donchian_EntryPeriod
up = iHigh( iHighest(MODE_HIGH, n, shift+1) )   // prior N-bar high  = resistance
dn = iLow ( iLowest (MODE_LOW,  n, shift+1) )   // prior N-bar low   = support
c  = Close[shift]
c > up  →  entry_signal = +1   (LONG breakout)
c < dn  →  entry_signal = −1   (SHORT breakout)
else    →  entry_signal =  0
```

For TREND, when `Donchian_RequireEmaStack = true`, the signal is then gated by the ribbon EMAs
(slots 1/2/3 = the preset's EMA periods): a LONG requires `EMA1 > EMA2 > EMA3`, a SHORT
requires `EMA1 < EMA2 < EMA3`; otherwise the signal is zeroed. The ribbon snapshot is refreshed
at the top of every `EvaluateTS` pass, so it is valid under `BIAS_MANUAL`.

---

## 4. Exit — opposite channel (`SEA_TradeExecutor.mqh`)

Checked once per bar in the position-management path (before the RRM/universal exit logic):

```
LONG  : close of last bar < lowest low  of prior M bars  → close
SHORT : close of last bar > highest high of prior M bars  → close
```

where `M = Donchian_ExitPeriod`. The 2×ATR initial stop needs no new code — it uses
`SLMode = SL_MODE_ATR`, `SL_AtrMult = 2.0`, and the existing ATR-based risk sizer, which makes
1 unit ≈ a fixed % of account risk per N (Turtle-equivalent sizing).

---

## 5. Inputs

**TURTLE** (`Inp_TURTLE_*`)

| Input | Default | Meaning |
|-------|---------|---------|
| `Inp_TURTLE_EntryChannel` | 40 | entry breakout period N (S1=20, S2=55, H4-FX=40) |
| `Inp_TURTLE_ExitChannel` | 20 | exit channel period M (S1=10, S2=20) |
| `Inp_TURTLE_SL_AtrPeriod` | 20 | ATR(N) period |
| `Inp_TURTLE_SL_AtrMult` | 2.0 | initial stop = 2 × N |

**TREND** (`Inp_TREND_*`)

| Input | Default | Meaning |
|-------|---------|---------|
| `Inp_TREND_EntryChannel` | 20 | entry breakout period |
| `Inp_TREND_ExitChannel` | 10 | exit channel period |
| `Inp_TREND_Ema_Fast / _Mid / _Slow` | 20 / 50 / 200 | entry-TF EMA stack (20>50>200 = long-only) |
| `Inp_TREND_MTF_Enabled` | true | HTF filter (keep ON) |
| `Inp_TREND_MTF_TF1 / _TF2` | H1 / CURRENT | HTF(s); CURRENT on TF2 = single HTF |
| `Inp_TREND_MTF_EMA_Fast / _Slow` | 50 / 200 | HTF EMA pair |
| `Inp_TREND_SL_AtrPeriod / _Mult` | 20 / 2.0 | ATR stop |

---

## 6. Config surface (`SEA_Config.mqh`)

New enum values: `PRESET_TURTLE`, `PRESET_TREND` (in `EStrategyPreset`);
`STRAT_DONCHIAN_BREAKOUT` (in `EAutoStrategy`). New `ST_Settings` fields:
`Donchian_EntryPeriod`, `Donchian_ExitPeriod`, `Donchian_UseChannelExit`,
`Donchian_RequireEmaStack`. `STRAT_DONCHIAN_BREAKOUT` runs under `BIAS_MANUAL`, which already
validates in `ValidateBiasStratCombo`.

---

## 7. Adding to a winner (pyramiding) — IMPLEMENTED, switchable

A single input, `AddMode`, selects how (or whether) the system adds to an open winner. Both
presets expose it (`Inp_TURTLE_AddMode`, `Inp_TREND_AddMode`), default **`ADD_OFF`**.

| Mode | Behaviour | Risk profile |
|------|-----------|--------------|
| `ADD_OFF` | Single unit, never adds. | Baseline. |
| `ADD_BE_REENTRY` | The existing safe re-entry: adds a second unit only once the first is at breakeven-or-better, on a fresh signal, size scaled by `ReEntryScale` (0=full, 50=half). | Conservative — aggregate risk stays capped by construction. |
| `ADD_TURTLE_UNITS` | Authentic Turtle: adds mechanically every `AddStepATR × N` in favour, up to `MaxUnits`, full size, before breakeven. With `SharedStop=true` the stop of every unit moves to `SL_AtrMult × N` from the newest fill. | Aggressive — aggregate risk rises as units stack. |

**Where it runs.** The Turtle add-unit engine lives in `EvaluateTM()` (once per bar): it seeds
state on the first fill (`m_turtle_units/last_fill/N/dir`), adds a unit when price has advanced
far enough, and resets to flat on a full exit. `ADD_BE_REENTRY` reuses the existing
`AllowReEntryAfterBE` path in `ExecuteTrade` — the preset just turns it on for that mode.

**Account-level risk gate (Turtle mode).** Before each add, `AggregateOpenRiskPct()` sums open
risk across *all* of the account's positions (every symbol, this magic) and blocks the add if
the projected total would exceed `Turtle_MaxAggregateRisk` (`Inp_*_MaxAggRisk`, default **6%**,
0 = off). This is the guard against 4 units × correlated pairs silently running many times the
intended exposure — the per-chart caps alone cannot see across symbols.

**Inputs (per preset):** `AddMode`, `MaxUnits` (4), `AddStepATR` (0.5), `MaxAggRisk` (6.0),
`SharedStop` (true), `ReEntryScale` (50).

> **Netting vs hedging caveat.** On a **hedging** account each add is a separate position and the
> shared-stop/aggregate-risk helpers iterate them directly. On a **netting** account an add
> increases the single position's volume and averages its entry; unit *count* is still tracked by
> `m_turtle_units`, and the shared stop applies to the netted position. Validate the add spacing
> and stop behaviour in Strategy Tester on your account type before live use.

## 8. Anti-range filters — optional, layered, default OFF

Donchian breakouts bleed in ranging markets (every false breakout is a small loss). These
filters — already computed inline in the engine, the same ones XEMA uses — let you block
breakouts when no real trend is present. **All default OFF**, so out of the box TURTLE is pure
Turtle and TREND is Turtle+EMAs. Toggle them per backtest from the EA panel; no recompile.

| Filter | Input (TURTLE / TREND) | Blocks when | Note |
|--------|------------------------|-------------|------|
| **ADX** | `Inp_*_Use_Adx` | trend strength below adaptive percentile | industry-standard; dynamic-percentile mode |
| **Choppiness Index** | `Inp_*_Use_CI` | CI above ranging threshold (~61.8) | most *direct* range detector; native inline |
| **BB widening** | `Inp_*_Use_Bb` | Bollinger bands not expanding | requires real volatility breakout |
| **P123 (Mark Crisp)** | `Inp_*_Use_P123` | no 1-2-3 fractal breakout in bias direction | second, independent breakout confirmation |
| **Ross Hook** | `Inp_*_Use_Ross` | no fractal breakout **and** EMA slope agreeing | P123 + momentum interlock (stricter than P123) |

The ADX/CI/BB voters are *range* filters (block when no trend); P123 and Ross are *breakout-quality*
confirmations (require a second, fractal-based breakout to agree). Each is a unanimous **I-voter**: enabling one means a breakout must *also* pass it. Stack them
to taste — the defence is layered:

```
pure breakout            (TURTLE, all off)
  + EMA(20/50/200) stack (TREND)
    + ADX                (trend strength)
      + CI               (direct range block)
        + BB widening    (volatility expansion)
```

> **The trade-off is real.** Every filter that removes range-losses also removes some genuine
> breakouts — and in this family the profit lives in a few big trends, so an over-tight filter
> can veto the trade that pays for the year. Judge filters on **total return over a diversified
> basket across multiple years**, not on win rate. A higher win rate with lower net return means
> the filter is trimming the tail. Start from all-off (the true baseline) and add one at a time.

## 8. Validation & caveats

The core breakout logic was checked on EURUSD H1→H4, Donchian 40/20 with a 2×ATR(20) stop,
single unit: ~21% win rate, average win ≈ 2× average loss — the correct trend-following
signature (few big winners, many small losers). This is a **signal-shape** validation, not a
profitability claim; net over one pair/year was slightly negative, which is exactly why the
source docs stress diversification across a basket.

**Compilation:** these edits follow the repo's exact patterns and pass symbol/structure checks,
but were not compiled in MetaEditor in the authoring environment. Compile `SimpleEA_v1-05.mq5`
in MetaEditor to confirm a clean build before backtesting.

---

## 9. 2026-08 routing fix + toggle audit (CANDIDATE — pending Strategy Tester)

**Defect (traced).** Both presets ship `BiasMode = BIAS_MANUAL` + `AutoStrat =
STRAT_DONCHIAN_BREAKOUT`. In `EvaluateBias`, the `BIAS_MANUAL` branch derived `bias`
from `ManSide` only; the `STRAT_DONCHIAN_BREAKOUT` dispatch lived in the *non-manual*
`else` branch and was therefore unreachable under manual bias (`ValidateBiasStratCombo`
even comments "Manual mode doesn't use AutoStrat"). With the default
`Inp_Global_ManualSide = SIDE_BOTH`, `bias = 0` on every bar -> `EvaluateTS_Breakdown`
returns 0 immediately -> **zero trades**. A Python reconstruction on EURUSD M15 2025
reproduced 0 trades pre-fix, and the documented signal-shape post-fix (TURTLE 40/20:
~25% win, avg win approx 2.4x avg loss).

**Fix.** `EvaluateBias` now, under `BIAS_MANUAL`, calls a shared `DonchianEntrySignal()`
helper when `AutoStrat == STRAT_DONCHIAN_BREAKOUT`, so the breakout supplies B as the
README always specified. Status: **candidate — UNCONFIRMED** until an MT5 Strategy
Tester run shows `STRAT_DONCHIAN_BREAKOUT ... signal=+/-1` and trades on channel breaks.

**New enable toggles (default preserves prior behaviour).**

| Input | Preset | Default | Effect |
|-------|--------|---------|--------|
| `Inp_TREND_Use_EmaStack` | TREND | true | require EMA(20/50/200) stack; false = pure Donchian channels |
| `Inp_TURTLE_UseChannelExit` / `Inp_TREND_UseChannelExit` | both | true | opposite-channel exit; false = SL-only |
| `Inp_TURTLE_Use_Mtf` (+ `_MTF_TF1/_TF2/_EMA_Fast/_EMA_Slow`) | TURTLE | false | add HTF/MTF confirmation voter |
| `Inp_TURTLE_Use_Psar` / `_Use_Dpi` / `_Use_CandleBody` | TURTLE | false | add the named voter |
| `Inp_TREND_Use_Psar` / `_Use_Dpi` / `_Use_CandleBody` | TREND | false | add the named voter |

All are unanimous I-voters and take effect only after the routing fix (before it, the
pipeline never reaches `EvaluateI`). The four `Donchian_*` fields are now serialized in
`SEA_ConfigSync.mqh` so the SignalScan inspector reconstructs TURTLE/TREND correctly.
