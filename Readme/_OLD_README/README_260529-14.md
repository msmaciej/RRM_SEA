# SimpleEA (RRM_SEA)

SimpleEA is a MetaTrader 5 Expert Advisor implementing a multiplicative signal validation pipeline built around four EMA ribbon market structure analysis, multi-indicator voting, and risk-aware position management.

**Environment:** macOS + Wine + MT5. MQL5 only — no C++, no templates, no lambdas.

---

## TS Equation — Signal Evaluation

```
TS = B × P × L × I × F      → then Climax (exhaustion) veto
```

Every factor is multiplicative. Any factor = 0 → TS = 0 → no trade. After all five factors pass, a final **Climax veto** can still block the entry (see CG below).

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

TS is evaluated at bar close (shift=1) by the EA and at any historical shift by SignalScan, through the shared `EvaluateTS_AtShift(shift, bias)` core, so the EA and the scanner apply identical B·P·L·I·F·CG logic. Trade execution (TE) happens at the next bar open (shift=0) after F filters are rechecked.

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
   
   Transition logic (one bar, pure direction sign):
   - **Pullback** = fast EMA moves against its baseline direction on this bar
   - **Recovery** = fast EMA resumes baseline direction on this bar
   
   The baseline is the EMA's direction over the past `LayerBaselineLookback` bars — used only to know what "against" means. The slope evaluated is always `EMA[shift] − EMA[shift+1]` (one bar, mathematically correct at shift=1).

3. **BC (Bar Close)** — signal bar close is beyond the fast EMA in bias direction (close > EMA1 for L1 LONG, close > EMA2 for L2 LONG, close > EMA3 for L3 LONG). Checks closing price level, not wicks or body.

4. **BD (Bar Direction)** — signal bar closed in bias direction (close > open for LONG, close < open for SHORT). A doji or opposing bar = fail even if close is beyond the EMA.

BC and BD are independent. A bar can close above EMA1 (BC=1) but be bearish (BD=0) → L=0.

---

### I — Indicators

All enabled technical voters evaluated at bar close (shift=1). All must pass (VOTE_MODE_ALL).

In RRM_ORG the active voters are: **DPI + PSAR + CandleBody + MTF** = 4 voters. The cockpit shows `VOTE: 4/4` when all pass.

Disabled indicators contribute 1 (neutral — they do not block). VPRR is enabled only when real exchange volume is available (metals on futures-linked brokers). VPRR is never enabled for FX pairs or any instrument where only tick volume is available — tick volume is broker-specific noise, not order flow.

---

### F — Filters

Non-directional execution conditions checked at bar open (shift=0):
- Spread ≤ MaxSpread
- Session time within configured window
- No high-impact news

MTF (Multi-Timeframe alignment) is evaluated at TS time and counted as an I voter.

---

## Source Files

| File | Role |
|------|------|
| `SimpleEA_v1-04.mq5` | Main EA — OnInit, OnTick, OnDeinit |
| `SEA_Config.mqh` | All settings, inputs, ST_Settings struct |
| `SEA_Presets.mqh` | Preset definitions — RRM_ORG, RRM, TI, CUSTOM |
| `SEA_SignalEngine.mqh` | TS equation — shared `EvaluateTS_AtShift` core (B·P·L·I·F + climax veto) |
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
