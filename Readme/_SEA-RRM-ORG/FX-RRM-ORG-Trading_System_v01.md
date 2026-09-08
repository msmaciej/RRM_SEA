# PRESET_RRM_ORG — Russ Horn RRM (Original)

**Status: IMPLEMENTED & DEFAULT.** This is the SEA reference engine. Coded in `SEA_Presets.mqh`
(`if(preset == PRESET_RRM_ORG)`) and evaluated by the shared `EvaluateTS_Breakdown` core in
`SEA_SignalEngine.mqh`. The main repo `README.md` documents the pipeline in full; this file is the
preset-scoped summary that accompanies the iconographic `_SEA_RRM_ORG/FX-RRM-ORG-Trading_System_v01.png`.

RRM_ORG is the only preset that uses the **complete** ribbon machinery: 4-EMA phase, W/M/S layer
pullback→recovery, unanimous voting, and the climax veto.

---

## 1. The idea — trend gives direction, the pullback gives the entry

An EMA ribbon (`5 / 13 / 34 / 89`) classifies the market; the **trend** decides direction, a
**pullback that recovers** decides the entry bar, and a panel of **voters** must all agree before a
trade is taken. A final **climax veto** blocks entries into over-extended blow-offs.

---

## 2. The TS equation

```
TS = B × P × L × I × F   →   CG veto
```

Multiplicative and order-independent — any factor 0 → TS = 0. Evaluated at bar close (`shift = 1`);
TE then executes at the next bar open. All three consumers (EA, scanner verdict, inspector) route
through the one `EvaluateTS_Breakdown` core, so they agree by construction.

| Factor | Name | Question |
|--------|------|----------|
| **B** | Bias | Which way is the ribbon pointing? |
| **P** | Phase | Is the structure tradable (TM/EM; block UNO)? |
| **L** | Layer | Has a pullback recovered on the right bar? |
| **I** | Indicators | Do **all** enabled voters agree (unanimous)? |
| **F** | Filters | Pre-entry gates (EMA-fan, DPI decel/reset) — **off by default**. |
| **CG** | Climax veto | After B·P·L·I·F pass, is price an over-extended blow-off? |

---

## 3. B — Bias (4-EMA ribbon order)

Direction only, from the three slow EMAs (EMA1 plays no role here):

| EMA order | Market | B |
|-----------|--------|---|
| EMA2 > EMA3 > EMA4 | Trending Up (TM↑) | +1 |
| EMA4 > EMA3 > EMA2 | Trending Down (TM↓) | −1 |
| EMA2 > EMA4 > EMA3 | Emerging Up (EM↑) | +1 |
| EMA3 > EMA4 > EMA2 | Emerging Down (EM↓) | −1 |
| any other | Unordered (UNO) | 0 → block |

`BiasMode = BIAS_4EMA`, `AutoStrat = STRAT_4EMA_LAYER`, `MaType = METHOD_EMA`. Bias encodes
direction only — timing lives in the Layer system.

## 4. P — Phase gate

`BlockUnorderedPhase = true`, `BlockEmergingPhase = false`, `Emerging_AllowStrongTrades = false`:

- **TM (Trending):** passes — Weak/Medium/Strong all eligible.
- **EM (Emerging):** passes — Weak & Medium only; **Strong blocked**.
- **UNO:** always blocked (B = 0).

## 5. L — Layer pullback → recovery (fire-on-edge)

Three EMA-pair layers, walked **L3 → L2 → L1** (Strong→Medium→Weak); first to pass wins.

| Layer | EMA pair | Depth |
|-------|----------|-------|
| L3 Strong | 34 / 89 | deepest structural |
| L2 Medium | 13 / 34 | momentum |
| L1 Weak | 5 / 13 | entry timing |

Each layer is an independent state machine driven by EMA **position + slope** (a machine-deterministic
encoding of the Oracle "pull back to the EMA then close past it" setup):

- `LAYER_PB_NONE` → no structure yet → blocked.
- `LAYER_PB_DETECTED` → fast-EMA slope **flattens or reverses** vs `bias_dir` (min 2 bars, A21 gate) → blocked.
- `LAYER_PB_INTREND` → both EMA slopes resume with bias → the layer is trending again.

**The fire is the edge**, not the state: a layer is entry-eligible on the `DETECTED → IN-TREND`
transition and stays **armed** through the IN-TREND run until a TS=1 consumes it; it then WAITS for
the next genuine pullback→recovery. One entry per pullback. A fast/slow cross, BIAS flip, or
sustained-UNO invalidates the layer. Warm-up replays history so valid setups already present are not missed.

**Price confirmation (independent of the slope machine):**
- **BC** (layer-aware): close beyond the active layer's fast EMA (L1→EMA1, L2→EMA2, L3→EMA3).
- **BD**: signal bar closed in the bias direction (close > open for long). BC=1 with BD=0 → L=0.

## 6. I — Indicator voters (unanimous, `VOTE_MODE_ALL`)

Active voters in RRM_ORG: **DPI + PSAR + CandleBody + MTF** (`VOTE: 4/4`).

- **DPI** — inline MACD (`Blue = EMA8−EMA13`, `Red = EMA13 of Blue`, `hist = Blue−Red`); hist sign
  must match bias, optional CCI-reset agreement. Enabling DPI also arms the DPI deceleration pre-filter.
- **PSAR** — dot on the bias side; per-layer flip-delay windows (W/M/S).
- **CandleBody** — signal bar is not an over-sized spike and closes in direction.
- **MTF** — higher-timeframe EMA structure aligns with bias.

Disabled indicators contribute neutral (1). **VPRR does not vote** — measurement-only since 2026-07-27.

## 7. F — Filters & CG — Climax veto

**F** (TS-side): `EMA_OVEREXT`, `DPI_DECEL`, `DPI_RESET_WAIT` — all off by default.
**CG**: checked **last**; blocks a fully-aligned signal when one bar > `ClimaxGuard_BarATRMult × ATR`
or a cumulative move > `ClimaxGuard_MoveATRMult × ATR` in the trade direction. Optionally resets layer
pullback state so a fresh cycle is required.

---

## 8. Exits — user-controlled (RRM engine)

Strategy-critical inputs (bias/phase/layer/voters/BC mode) are **locked**; exits are operator-tunable:
swing SL with TF-aware cushion + min-floor (auto-widen), R:R or fixed-pip TP, break-even at N×R, and a
PSAR-based trailing lock once in profit. Policy-A gates (spread, session, news, risk caps) remain fully
operator-controlled under the preset.

---

## 9. Quick reference

```
Ribbon : EMA 5/13/34/89            Bias : 4-EMA ribbon order (dir only)
Phase  : TM + EM (UNO blocked)     Layer: L3→L2→L1, fire on recovery edge
Voters : DPI+PSAR+CandleBody+MTF   Vote : unanimous, shift=1
Confirm: BC (layer-aware) + BD     Veto : CG climax/exhaustion (last)
Exits  : user (swing SL/PSAR trail/BE)   Enum: PRESET_RRM_ORG (default)
```

Full detail: repo `README.md`, `Readme/README_SEA_SIGNAL_REFERENCE.md`,
`Readme/README_SEA_TRADE_LOGIC.md`, `Readme/README_SEA_VETO_REFERENCE.md`.
