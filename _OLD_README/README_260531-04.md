# SimpleEA (RRM_SEA)

SimpleEA is a MetaTrader 5 Expert Advisor implementing a multiplicative signal validation pipeline built around four EMA ribbon market structure analysis, multi-indicator voting, and risk-aware position management.

**Environment:** macOS + Wine + MT5. MQL5 only — no C++, no templates, no lambdas.

---

## TS Equation — Signal Evaluation

```
TS = B × P × F × L × I      → then Climax (CG) veto
```

Every factor is multiplicative, so the verdict is order-independent; the engine evaluates them in the order **B → P → F → L → I**, then CG. Any factor = 0 → TS = 0 → no trade. After all five factors pass, a final **Climax veto** can still block the entry (see CG below).

| Factor | Name | What it answers |
|--------|------|-----------------|
| **B** | Bias | Which direction is the market moving? |
| **P** | Phase | Is the market structure suitable for trading? |
| **L** | Layer | Is this the right bar to enter? |
| **I** | Indicators | Do **all enabled** confirmations agree? (unanimous) |
| **F** | Filters | Are pre-entry conditions acceptable? (EMA-fan, DPI-decel, DPI reset-recovery, phase-age) |
| **CG** | Climax veto | After B·P·L·I·F pass, is price over-extended into an exhaustion impulse? If so, block. |

**I is unanimous.** When N indicators are enabled, **all N must pass** — there is no weighted or partial vote. The `I[x/y]` telemetry only reports how many passed for diagnostics; `x < y` never fires.

**Climax / Exhaustion Guard (CG)** is a *veto*, not a voter. It is checked **last**, only after B·P·L·I·F have all passed, and it overrides them: a fully-aligned signal is still blocked when the recent move is an over-extended blow-off — a single bar whose range > `ClimaxGuard_BarATRMult` × ATR, or a cumulative move > `ClimaxGuard_MoveATRMult` × ATR, in the trade direction. On a block it optionally resets all layer pullback state (`ClimaxGuard_ResetPullback`) so a fresh pullback-recovery cycle is required before the next signal. Because the I factor is an AND of *positive* confirmations, the *negative* veto is deliberately kept out of it — conceptually CG is a sibling of the F `EMA_FAN` over-extension filter, separated so a climax block reads cleanly in diagnostics.

TS is evaluated at bar close (shift=1) by the EA and at any historical shift by SignalScan, through one shared core, **`EvaluateTS_Breakdown(shift, bias, …)`** in `SEA_SignalEngine.mqh`. All three consumers route through it — the EA (`EvaluateTS`), the scanner verdict (`EvaluateTS_AtShift`), and the inspector (`Scanner_InspectBar`) — so they apply identical B·P·F·L·I·CG logic by construction (single source of truth). Trade execution (TE) then runs at the next bar open (shift=0); see the TE Equation below.

---

### B — Bias

Uses **EMA2(13), EMA3(34), EMA4(89)** position to classify market direction. EMA1(5) plays no role in B.

`DetectMarketPhase()` reads the three slow EMA positions and sets direction:

| EMA order | Market type | B |
|-----------|-------------|---|
| EMA2 > EMA3 > EMA4 | Trending Up (TM↑) | +1 |
| EMA4 > EMA3 > EMA2 | Trending Down (TM↓) | −1 |
| EMA2 > EMA4 > EMA3 | Emerging Up (EM↑) | +1 |
| EMA3 > EMA4 > EMA2 | Emerging Down (EM↓) | −1 |
| any other arrangement | Unordered (UNO) | 0 |

EM (Emerging) is identified by EMA4 (slowest) sandwiched between EMA2 and EMA3 — the slow backbone is being overtaken by momentum. UNO is any arrangement not matching TM or EM — no coherent structure.

---

### P — Phase gate

Uses the same phase detected by B. Answers: *is this market type acceptable for entry?*

| Phase | Default behaviour |
|-------|-------------------|
| TM (Trending) | Always passes |
| EM (Emerging) | Blocked by default (`BlockEmergingPhase=true` in RRM_ORG) |
| UNO (Unordered) | Always blocked |

In RRM_ORG only fully trending markets (TM) trade. The cockpit shows `PHASE: TRENDING UP [+]` when P passes.

---

### L — Layer (entry timing)

**This is where EMA1(5) enters the equation.** L evaluates three EMA pairs, each representing a depth of trend structure. It answers: *is this the right bar to enter — has there been a pullback and is the EMA pair now recovering?*

| Layer | EMA pair | Depth |
|-------|----------|-------|
| L3 Strong | EMA3(34) / EMA4(89) | Deepest — slowest structural layer |
| L2 Medium | EMA2(13) / EMA3(34) | Mid-depth — momentum layer |
| L1 Weak | EMA1(5) / EMA2(13) | Shallowest — fastest, entry timing |

Priority walk: **L3 → L2 → L1**. First layer passing all checks wins. The active layer is shown on the cockpit as `ACTIVE LAYER: L1+L2+L3`.

**Per-layer sub-checks (all four must pass):**

1. **Position** — fast EMA is on the correct side of slow EMA (EMA1 > EMA2 for LONG, EMA1 < EMA2 for SHORT). Structural alignment.

2. **Pullback state** — the layer must NOT be in active pullback. Each layer runs an independent state machine tracking the fast EMA's direction:
   - `LAYER_PB_NONE` → EMA trending normally, no pullback seen → **entry allowed**
   - `LAYER_PB_DETECTED` → EMA reversed direction vs baseline → **entry blocked**
   - `LAYER_PB_RECOVERED` → EMA resumed trend direction after pullback → **entry allowed**
   
   Transition logic (magnitude-based slope ratio):
   - **Baseline pace** = the EMA's *average* per-bar slope over its per-layer lookback window (`LayerBaselineLookback_W/M/S`, default 13/21/34 — fastest layer shortest, slowest layer longest).
   - **Current pace** = the EMA's recent slope over the last `k` bars (`k = max(2, lookback/4)`, so the slow S-layer is smoothed more than the fast W-layer).
   - **ratio** = |current pace| / |baseline pace|.
   - **Pullback** = `ratio < LayerPullbackRatio` (weakened), or `< LayerFlatRatio` (flat), or a slope reversal (when `LayerAllowReversalPullback`).
   - **Recovery** = trend direction resumed *and* `ratio >=` the layer's recovery threshold (`LayerRecoveryRatio_W/M/S`, default 0.4/0.3/0.2 — slower layers confirm on less momentum).

   Averaging both sides (rather than a single-bar slope) is what lets the slow S-layer EMAs register a genuine pause without false "weakened" readings. Each layer can be enabled/disabled independently via `AllowLayer{1,2,3}_Entries` (W/M/S), and the SignalScan inspector shows all three layers' states at the inspected bar.

3. **BC (Bar Close)** — signal bar close is beyond the fast EMA in bias direction (close > EMA1 for L1 LONG, close > EMA2 for L2 LONG, close > EMA3 for L3 LONG). Checks closing price level, not wicks or body.

4. **BD (Bar Direction)** — signal bar closed in bias direction (close > open for LONG, close < open for SHORT). A doji or opposing bar = fail even if close is beyond the EMA.

BC and BD are independent. A bar can close above EMA1 (BC=1) but be bearish (BD=0) → L=0.

---

### I — Indicators

All enabled technical voters evaluated at bar close (shift=1). All must pass (VOTE_MODE_ALL).

In RRM_ORG the active voters are: **DPI + PSAR + CandleBody + MTF** = 4 voters. The cockpit shows `VOTE: 4/4` when all pass.

Disabled indicators contribute 1 (neutral — they do not block). VPRR is enabled only when real exchange volume is available (metals on futures-linked brokers). VPRR is never enabled for FX pairs or any instrument where only tick volume is available — tick volume is broker-specific noise, not order flow.

---

### F — Filters (pre-entry, TS-side)

Optional pre-entry gates evaluated by the engine's `EvaluateF`. **All off by default in RRM_ORG**, so the F factor is a no-op there until a filter is explicitly enabled:

| Sub-filter | Blocks when | State |
|------------|-------------|-------|
| `EMA_OVEREXT` | EMA fan over-extended (spread too wide) | stateless / shift-correct |
| `DPI_DECEL` | DPI histogram momentum decelerating | **stateful** — needs `UpdateDPIHistogramState` current for the bar |
| `DPI_RESET_WAIT` | DPI CCI reset-recovery not yet complete | **stateful** |
| `PHASE_AGE` | current phase younger than `MinPhaseConfirmBars` | shift-relative |

> **Two different "F".** This TS-side F is **not** spread/session/news — those are TE-side gates (see TE Equation). They are separate functions in separate classes that happen to share the name. **MTF** (Multi-Timeframe alignment) is evaluated at TS time and counted as an **I** voter, not F. The DPI used here (decel / reset-recovery) is also distinct from the DPI **vote** in I, which is stateless.

---

## TE Equation — Trade Entry

Once TS produces a signal direction, the trade-executor gate chain decides whether an order is actually placed. TE runs every tick at the next bar open (shift=0), evaluated by `EvaluateTE(direction)` in `SEA_TradeExecutor.mqh`:

```
TE = direction × F × open-delay × BC-recheck × CM × RC   → execute
```

| Gate | Checks | Veto on fail |
|------|--------|--------------|
| **F** | spread ≤ MaxSpread · session window · no high-impact news · spread-median | `VETO_SPREAD` / `VETO_SPREAD_TIMEOUT` / `VETO_TIME` / `VETO_NEWS` / `VETO_SPREAD_MEDIAN` |
| **open-delay** | bar age ≥ `TE_OpenDelaySeconds` (lets the post-open spread spike resolve) | `VETO_OPEN_DELAY` |
| **BC re-check** | live price within `TE_BC_TolerancePips` of `Close[1]` | `VETO_BC_STALE` |
| **CM** | position sizing yields valid lots | `VETO_INVALID_LOTS` |
| **RC** | risk / margin / max-open-trades caps | `VETO_RC_*` |

TS shapes *whether a setup is valid*; TE shapes *whether it is executable right now*. Full veto catalog: `Readme/README_SEA_VETO_REFERENCE.md`.

---

## SignalScan Inspector

`SEA_IND_SignalScan.mq5` can mark any historical bar for inspection: drag the `SCN_INSPECT` vertical line onto a bar and the panel shows that bar's full TS breakdown, evaluating **every** factor independently (not the waterfall):

```
B:ok P:ok L:NO(BC) I:ok F:ok CG:ok
TS=0  blocked by L (Layer)
```

Each factor reads `ok` (passed), `NO(code)` (blocked, with the reason), or `--` (not applicable — only when there is no bias, B=0). When a factor is `NO`, the code is the engine's own reason for that bar:

| Factor | Code | Engine reason — meaning |
|--------|------|-------------------------|
| **P** | `UNORD` | `PHASE_UNORDERED` — EMAs not in a tradable order |
| | `EMERG` | `PHASE_EMERGING` — emerging phase, blocked by preset |
| **L** | `ALIGN` | `LAYER_NONE_ALIGNED` — no layer's EMAs stacked in bias direction yet (structural: a pullback entry can't fire here) |
| | `BC` | `BC_NOT_CONFIRMED` — bar close not yet beyond the fast EMA in bias direction |
| | `BD` | `CandleDir` — signal bar not closed in the bias direction |
| | `MOM` | `MOMENTUM_NOT_CONFIRMED` — progressive-momentum / DPI-growth check failed |
| **I** | *names* | failing voters, comma-joined (e.g. `DPI,PSAR`) — voters: DPI, PSAR, CBODY, MTF, ADX, MACD, CCI |
| **F** | `EMAFAN` | `EMA_OVEREXT` — EMA fan over-extended |
| | `DECEL` | `DPI_DECEL` — DPI histogram momentum decelerating |
| | `RESET` | `DPI_RESET_WAIT` — DPI CCI reset-recovery not complete |
| | `AGE` | `PHASE_AGE` — phase younger than `MinPhaseConfirmBars` |
| **CG** | `climax` | climax/exhaustion veto fired *(over-threshold ATR margin ratios are a planned addition)* |

When there is no bias the panel collapses to `TS=0 blocked by B (no bias)` and the per-factor line is not shown. The inspector is **passive** — it reproduces the shared `EvaluateTS_Breakdown` decision read-only and never mutates layer state.

---

## Source Files

| File | Role |
|------|------|
| `SimpleEA_v1-05.mq5` | Main EA — OnInit, OnTick, OnDeinit (active; `v1-04` retained for reference) |
| `SEA_Config.mqh` | All settings, inputs, ST_Settings struct |
| `SEA_Presets.mqh` | Preset definitions — RRM_ORG, RRM, TI, CUSTOM |
| `SEA_SignalEngine.mqh` | TS equation — single core `EvaluateTS_Breakdown` (B·P·F·L·I + CG veto), used by `EvaluateTS` / `EvaluateTS_AtShift` / `Scanner_InspectBar` |
| `SEA_TradeExecutor.mqh` | TE, order management, SL/TP/trailing |
| `SEA_UI.mqh` | Cockpit panel rendering |
| `SEA_Reporting.mqh` | OnDeinit stats and performance report |
| `SEA_IND_DPI_mc_main.mq5` | DPI indicator for chart (MACD+CCI, with GREEN overlay) |
| `SEA_IND_DPI_mc_simple.mq5` | DPI indicator for chart (MACD+CCI, no GREEN) |
| `SEA_IND_DPI_tm_simple.mq5` | DPI indicator for chart (TSI+MACD variant) |
| `SEA_IND_VPRR_Volume.mq5` | VPRR volume indicator for chart visualisation |
| `SEA_ServerTime_Check.mq5` | Diagnostic script — server time, CME session, VPRR proxy probe |

---

## Presets

| Preset | Description |
|--------|-------------|
| `PRESET_RRM_ORG` | Core RRM method — 4EMA, TM phase only, DPI+PSAR+CandleBody+MTF voting |
| `PRESET_RRM` | RRM variant — EM phase allowed |
| `PRESET_CUSTOM` | All inputs user-controlled, no overrides |
| `PRESET_MA` | Simple moving average benchmark |
| `PRESET_TEST` | Debug bypass — threshold=1, no voting |

When any non-CUSTOM preset is active it overrides all strategy-critical inputs. The EA prints the effective settings at init and displays them in the cockpit.

---

## DPI — Dynamic Price Indicator

The EA's internal DPI matches `SEA_IND_DPI_mc_main.mq5` bar-for-bar.

```
Blue(i) = EMA(MACD_Fast, close)(i) − EMA(MACD_Slow, close)(i)
Red(i)  = EMA(RedType, Blue)(i)
hist(i) = Blue(i) − Red(i)
```

Default periods: MACD fast=8, slow=13, Red signal=EMA(13) of Blue.

**DPI vote logic (I factor):**
- `hist > 0` → LONG pass; `hist < 0` → SHORT pass
- Optional CCI confirmation (`DPI_UseCCIReset=true`): requires `sign(hist) == sign(CCI)`

The GREEN momentum overlay is visualisation only — it does not gate the vote.

---

## VPRR — Volume Pullback-Recovery Ratio

VPRR measures whether recovery volume exceeds pullback volume for metals instruments. It is only meaningful with real exchange volume (CME/COMEX feed via a futures-linked broker or proxy symbol).

VPRR is **never enabled** for FX pairs regardless of settings — tick volume is broker-specific tick count, not traded volume, and produces meaningless ratios.

Use `SEA_ServerTime_Check.mq5` to verify whether your broker provides real volume for a proxy symbol before enabling VPRR.

---

## Detailed Reference

- `Readme/README_SEA_SIGNAL_REFERENCE.md` — full indicator logic and voting details
- `Readme/README_SEA_TRADE_LOGIC.md` — TE execution, SL/TP, trailing
- `Readme/README_SEA_PRESETS.md` — preset configuration reference
- `Readme/README_SEA_VETO_REFERENCE.md` — full veto and filter catalog
- `Readme/README_SEA_BOOTSTRAP.md` — AI agent instructions
