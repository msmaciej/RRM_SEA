# SignalScan — Reference

`SEA_IND_SignalScan.mq5` (v4.0) is the RRM_SEA **signal scanner and bar inspector**. It is a chart indicator, not the EA. It has two jobs:

1. **Historical scan** — walk a window of past bars and mark, on each bar, where the TS equation would have fired a signal (per direction, per layer).
2. **Bar Inspector** — mark any single historical bar with a draggable line and read that bar's full TS factor-by-factor breakdown: a *historical* version of the EA cockpit.

Crucially, it does **not** re-implement the strategy. Both jobs route the actual decision through the **same core the EA uses** — `EvaluateTS_Breakdown` in `SEA_SignalEngine.mqh` — so what it shows is the EA's own logic, not a parallel copy. See [Architecture](#architecture) and [Parity with the EA](#parity-with-the-ea).

---

## Quick start

1. Open a chart for the **pair + timeframe you want to test** (the scanner uses whatever chart it is dropped on). For RRM_ORG parity, that means the same symbol + TF your EA runs on.
2. Drag `SEA_IND_SignalScan` from the Navigator onto the chart.
3. In the input dialog set, at minimum:
   - **EMA periods** — `5 / 13 / 34 / 89` for RRM_ORG.
   - **MarketBias** — `SBIAS_4EMA_TM` = same bias mode as the RRM_ORG EA.
   - **TS Components** — set each component `true`/`false`. Every component set `true` must pass for a signal line to appear.
   - Optionally **Scn_Sync_With_EA = true** to inherit the live EA's exact config (see [Config sync](#eascanner-config-sync)).
4. Click OK. **Blue** vertical lines = LONG signals, **red** = SHORT signals; the top-left panel shows pair/TF, active components, and per-layer counts.
5. To change settings: right-click chart → Indicators list → `SEA_IND_SignalScan` → Edit.

---

## Inputs

Inputs are organised into labelled groups. The signal-affecting ones:

| Group | Key inputs | Notes |
|-------|-----------|-------|
| **STEP2 · EMA Ribbon** | EMA1–EMA4 periods | RRM_ORG default `5 / 13 / 34 / 89` |
| **STEP3 · Market BIAS** | `MarketBias` (`EScanBias`) | see enum below |
| **STEP4 · TS Components** | `TS_Pullback_Recovery` (**L**), `TS_DPI` / `TS_PSAR_Flip` / `TS_MTF` (**I**), `TS_ADX` / `TS_RSI` / `TS_CCI` / `TS_MACD` … | *all* `true` items must pass |
| **STEP5 · Indicator params** | per-indicator settings (ADX, ATR, Bollinger, CandleBody, CCI, Choppiness, DPI, MACD, MFI, MTF, PSAR, Pullback-Recovery, RSI, Stochastic) | only edit the group for each `true` item |
| **Time window** | `DateFrom`, `DateTo`, `BarsBack` (=500) | `DateFrom=0` → scan back `BarsBack` bars |
| **Bar Inspector** | `Scn_Inspect_Enabled` (=true), `Scn_Inspect_Color` (=`clrGold`), `Scn_Inspect_Time` | the draggable gold line |
| **STEP7 · Sync** | `Scn_Sync_With_EA` (=false), `Scn_Sync_MaxStaleSeconds` (=60) | inherit the live EA config |
| **Display (STEP0)** | panel position/fonts, signal-line style, per-layer LONG/SHORT colours, EMA + HTF overlays | visuals only — no effect on signals |

**`MarketBias` (`EScanBias`) values:**

| Value | Meaning |
|-------|---------|
| `SBIAS_4EMA_TM` (0) | 4-EMA, TRENDING markets only — **same as RRM_ORG** (recommended) |
| `SBIAS_4EMA_TM_EM` (1) | 4-EMA, TRENDING + EMERGING |
| `SBIAS_2EMA` (2) | fast EMA vs slow EMA |
| `SBIAS_1EMA` (3) | slope of a single EMA |
| `SBIAS_LONG` / `SBIAS_SHORT` (4/5) | manual, one direction on every bar |
| `SBIAS_BOTH` (6) | test both directions on every bar |

---

## Historical scan & signal marking

`RunFullScan()` scans **chronologically, oldest → newest** (`for s = shift_to … 1: ScanBar(s)`). Oldest-first matters: it lets per-bar state — the layer machine, PSAR-flip history, and UNO-flicker tolerance — accumulate exactly as it would live, so each bar is judged with the state it actually had.

- **Window:** `BarsBack` bars (default **500**) ending at the last closed bar, unless `DateFrom`/`DateTo` narrow it.
- **Marking:** each firing bar gets an `OBJ_VLINE`, coloured by direction and shaded by the layer that fired — LONG in blues (`Color_Long_S/M/W`), SHORT in reds (`Color_Short_S/M/W`), where S = strong/deep, M = medium, W = weak/shallow.
- **Panel counts:** total LONG/SHORT plus a per-layer split (`S: … M: … W: …`).
- **UNO tolerance:** a transient unordered-ribbon flicker that resolves back to the same direction within `UNO_ToleranceBars` (default 2) does **not** wipe layer state — mirroring the EA's `UNO_ToleranceBars` behaviour so scanner and live stay aligned.

The scan re-runs automatically on each new bar and whenever the inspector line is dragged, so marks stay current without waiting for a tick.

---

## Bar Inspector

Enable `Scn_Inspect_Enabled` (default on) and a gold `SCN_INSPECT` vertical line appears. **Drag it onto any bar** and the panel shows that bar's full TS breakdown.

- The marked time is resolved to a bar via `iBarShift` and clamped to **shift ≥ 1** — only *closed* bars, never the forming bar, matching the EA's shift=1 evaluation.
- Dragging fires `OnChartEvent(CHARTEVENT_OBJECT_DRAG)` → a full re-scan, so the bar is re-judged with correct accumulated state.
- The breakdown is captured **inside the chronological scan, at the marked shift, before** the fire path runs — so a fire's layer reset can't wipe the state being shown.
- Unlike the live TS evaluation (which short-circuits at the first failing factor), the inspector evaluates **every factor independently** (`Scanner_InspectBar`), so you see the whole row even past the first `NO`.

Panel output for a marked bar:

```
Inspector (drag SCN_INSPECT):
  Bar:  2026.05.21 14:37
  Bias: LONG
  B:ok P:ok L:NO(BC) I:ok F:ok CG:ok
    S: <layer S state>
    M: <layer M state>
    W: <layer W state>
  TS=0  blocked by L (Layer)
```

Each factor reads `ok` (passed), `NO(code)` (blocked, with the engine's reason), or `--` (N/A — only when there is no bias, B=0). With no bias the panel collapses to `TS=0 blocked by B (no bias)`.

### Reason codes

| Factor | Code | Engine reason — meaning |
|--------|------|-------------------------|
| **P** | `UNORD` | `PHASE_UNORDERED` — EMAs not in a tradable order |
| | `EMERG` | `PHASE_EMERGING` — emerging phase, blocked by preset |
| **L** | `ALIGN` | `LAYER_NONE_ALIGNED` — no layer's EMAs stacked in bias direction yet |
| | `BC` | `BC_NOT_CONFIRMED` — bar close not yet beyond the fast EMA in bias direction |
| | `BD` | `CandleDir` — signal bar not closed in the bias direction |
| | `MOM` | `MOMENTUM_NOT_CONFIRMED` — progressive-momentum / DPI-growth check failed |
| **I** | *names* | failing voters, comma-joined (e.g. `DPI,PSAR`) — voters: DPI, PSAR, CBODY, MTF, ADX, MACD, CCI |
| **F** | `EMAFAN` | `EMA_OVEREXT` — EMA fan over-extended |
| | `DECEL` | `DPI_DECEL` — DPI histogram momentum decelerating |
| | `RESET` | `DPI_RESET_WAIT` — DPI CCI reset-recovery not complete |
| **CG** | `climax` | climax / exhaustion veto fired |

---

## Architecture

- **Single decision core.** The EA (`EvaluateTS`), the scanner's line-marking verdict (`EvaluateTS_AtShift`) and the inspector (`Scanner_InspectBar`) all call one function — `EvaluateTS_Breakdown(shift, bias, …)` in `SEA_SignalEngine.mqh`. That function evaluates **B · P · F · L · I** and the **CG** (climax) veto. `F` is the full `EvaluateF` (EMA-fan, price-ext, DPI-decel, DPI reset-recovery, climax). So the scanner applies the EA's logic *by construction*, not a re-implementation.
- **Two engine instances.** The scanner runs two `CSignalEngine` objects — `g_eng_long` and `g_eng_short` — because a historical bar could have been a long *or* a short setup, so both directions are tested. The live EA holds a single engine because it only has one current bias. Same code, two state containers.
- **Passive.** The inspector never mutates state; line-marking mirrors the EA's fire behaviour (fire → layer reset) as it scans so accumulated state stays faithful.

---

## EA↔scanner config sync

By default the scanner runs on **its own inputs**. To make it evaluate with the **live EA's exact configuration**, set `Scn_Sync_With_EA = true`.

- **EA side:** no setting needed. The EA writes its *effective* `ST_Settings` snapshot **unconditionally on init** (`SEA_WriteConfigSnapshot`, after preset apply + safety auto-corrects + validation), so what it publishes is exactly what its engine will run.
- **Scanner side:** with `Scn_Sync_With_EA = true`, `SEA_ReadConfigSnapshot` overlays that snapshot on top of the scanner's own settings. Keys absent from the snapshot keep the scanner defaults.
- **Requirements:** the scanner must be on the **same symbol + timeframe** as the EA, and the snapshot must be fresh — `Scn_Sync_MaxStaleSeconds` (default 60) rejects older snapshots and falls back to scanner inputs. Set it to 0 to ignore staleness (e.g. inspecting history while the EA isn't actively ticking).
- **Status line** in the panel:
  - `Sync: ON [N applied, age Xs]` — snapshot applied
  - `Sync: MISSING (using scanner inputs)` — no snapshot found
  - `Sync: STALE [age Xs] (using scanner inputs)` — snapshot too old
  - `Sync: OFF` — `Scn_Sync_With_EA=false`

---

## Parity with the EA

With `Scn_Sync_With_EA = true`, on the same symbol/TF, the scanner's **B · P · F · L · I · CG** verdict for a bar is produced by the same core, with the same settings, as the live EA — so the marked-bar breakdown is a faithful reproduction of what the EA decided (or would decide under the current preset) on that bar.

**What can still differ:**

1. **Config source.** With sync **off**, the scanner judges with its own inputs, not your preset — the single biggest divergence lever. Turn sync on (or set the scanner inputs to match the preset by hand).
2. **Layer-state history across a bias flip.** The two-engine model (idle side reset each bar for isolation) is a careful *reconstruction* of the EA's single persistent layer machine. It matches on essentially all bars but is not guaranteed byte-identical through some bias-flip sequences. This only affects **L**; B/P/F/I/CG are unaffected.
3. **Snapshot freshness / symbol-TF mismatch** — as above; if these aren't satisfied the scanner silently falls back to its own inputs (shown in the sync status line).

> Historical note: earlier comments claimed the F pre-filters and P were "not in the shared core." That is **stale** — `EvaluateTS_Breakdown` calls the full `EvaluateF` and `EvaluateP`, so both are in the core; parity is governed by config sync, not by missing logic.

**What the scanner does NOT cover** (by design — it is a *TS* tool):

- **TE (trade execution) equation** — spread / session / news / bar-open recheck / entry timing. These are bar-*open*, execution-time gates, separate from the TS breakdown. Not shown.
- **Active-trade & risk management** — no-2nd-entry-until-BE, 50%-risk add, PSAR-dot trailing. These depend on live *position* state that can't be reconstructed from a single historical bar without simulating the full position lifecycle. That is Strategy-Tester / position-simulation territory, not a per-bar scanner.

---

## Authority

Per `README_SEA_FRAMEWORK.md`, the **two authoritative sources** for "what the EA evaluated at bar X" are (a) the EA's DebugFlow journal, and (b) the SignalScan **inspector** (`Scanner_InspectBar`) — precisely because both run the real `EvaluateTS_Breakdown`. The scanner's value over the live cockpit is that it shows *any historical bar* (and 500 bars of marks at once); the live cockpit only shows the current bar. Where a reconstruction (e.g. hand-computed EMAs) disagrees with the inspector or journal, the inspector/journal win.

---

## Related docs

- `README.md` → *SignalScan Inspector* section (factor/reason summary) and the shared-core description.
- `README_SEA_FRAMEWORK.md` → authority rule (inspector + journal as ground truth).
- `README_SEA_PARAMETER_MAPPING.md` → EA→scanner field sync via `SEA_ConfigSync`, scanner input inventory.
