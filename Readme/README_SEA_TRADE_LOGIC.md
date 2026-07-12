# SEA Execution, Risk & Trade Logic

## Overview
This document covers the Phase 2 (TE - Trade Entry) execution mechanics, stop loss and take profit modes, timeframe-based auto-scaling cushions, and adaptive spread limits. 

SimpleEA handles execution dynamically. All cushion and buffer values auto-adjust by timeframe and symbol type—no manual optimization or input is required.

---

## 1. Signal Reception & The Handshake

The Signal Engine evaluates the core TS equation on the **CLOSED candle (shift=1)** to eliminate lag and false triggers. The entry logic is decoupled into structural alignment and price action triggers:

$$TS = Bias \times Phase \times \prod_{j=1}^{m} F_{j} \times Layer_{X} \times bc_{X} \times \prod_{i=1}^{n} Ind_{i}$$

or equivalently:

$$TS = B \times P \times F \times L \times I$$

* **B (Bias):** Master directional permission (1 = Long, −1 = Short, 0 = Neutral).
* **P (Phase):** Market structure gate (TM / EM / UNO). UNO always blocks; in `PRESET_RRM_ORG` EM is **allowed for LayerW and LayerM**, blocked for LayerS (`Emerging_AllowStrongTrades = false`). UNO is always blocked (B=0 so signal is 0 before P is even evaluated).
* **F (TS-side pre-filters):** EMA-fan over-extension × price over-extension × DPI deceleration × phase-age confirmation × Climax-Guard veto. All off by default in `PRESET_RRM_ORG`; the F factor is a no-op until a sub-filter is explicitly enabled.
* **L (LayerX — $Layer_W, Layer_M, Layer_S$):** Per-layer pullback-recovery state machine. Evaluates to 1 ONLY when the layer's pos × slope × BC × BD all pass; priority walk L3 → L2 → L1.
* **bcX:** Bar-close confirmation — the closed candle closes beyond the fast EMA of the active layer in the bias direction. Part of the L factor.
* **I (Indicators):** All enabled voters must pass (unanimous AND): DPI + PSAR + CandleBody + MTF in `PRESET_RRM_ORG`.

> **Two `EvaluateF` functions.** This TS-side F (engine: `CSignalEngine::EvaluateF`) runs at bar close and covers the pre-filters listed above. A second, *different* `EvaluateF` lives in `CTradeExecutor` (this file) and runs at bar open — that one is the TE-side **F'** factor and covers spread × session × news. They share the letter "F" by design; each is the filter factor of its respective equation. See `TE = F'` block below.

If a setup passes the strict multiplicative consensus, it is stored in the global queue (`g_ts_dir = 1` or `-1`) precisely at `shift=1`. The Trade Executor then handles the *physical* execution with the broker strictly on `shift=0` (the open tick).

---

## 1.1 Encoding the Oracle — why Pullback-Recovery is EMA-only

**This section is the canonical statement of the P-R encoding decision.** `README_SEA_FRAMEWORK.md` (Part G) and `README_SEA_SIGNAL_REFERENCE.md` (§3b) state the resulting *rule*; this section states the *reason*. If the two ever disagree, this section is authoritative on intent and the rule tables are authoritative on values.

### The Oracle description

The RRM Trade Setups card describes each setup as a short list of conditions. For the Bullish Weak trade, verbatim:

- EMA1 over the EMA2
- **price pulls back to touch the EMA2**
- **price closes above the EMA1**
- EMA1 never crosses below EMA2 during this setup
- EMA3 and EMA4 should be under the EMA2

The two bolded lines are what a human reads as **one perceptual packet**: *the market dips into the ribbon and comes back out of it.* A trader does not evaluate them as two independent booleans — they see a shape on a chart, in one glance, and the shape either is or is not a pullback-recovery. The card's diagram draws exactly that shape: a stacked, sloped ribbon with price dipping toward it and turning back up.

### Why the packet cannot be encoded as written

Code cannot see a gestalt. It needs **separable, individually-decidable predicates**, evaluated bar by bar, each one true or false on its own. Translating the two lines literally — "wick touched EMA2" and "close is beyond EMA1" — and putting both **inside** the layer state machine fails in four specific ways, each of which was observed in this codebase and reverted:

1. **Recovery would become a duplicate of BC.** "Price closes above EMA1" *is already* the BC gate (`Eval_BarClose`). If RECOVERED is also a close-vs-EMA test, the same predicate is evaluated twice — once as a state transition, once as a factor — and the layer machine adds no information the BC gate did not already carry. (Historic: the close-based `recovery_cond`, removed 2026-07.)
2. **The cycle would complete in one bar.** Wick touches the zone (DETECTED) and the same candle closes beyond the fast EMA (RECOVERED) → `NONE → RECOVERED` inside a single candle. That is a spike, not a pullback. (Historic: the S2 one-bar shortcut, removed; the A21 minimum-duration gate now makes it structurally impossible.)
3. **"Touch" is not decidable without a magic number.** An exact touch of a floating-point EMA essentially never happens, so a literal encoding needs a tolerance band — a tunable with no value derivable from the Oracle or the code (see Framework Part F, *magic numbers are a smell*). The band is also broker-, spread- and tick-noise-dependent: the same setup would decide differently on two feeds.
4. **A wick is not evidence of a pullback.** A single spike into the zone on thin liquidity satisfies "touched" while the trend never paused at all.

### What the EA does instead — the split

The EA **splits the perceptual packet into its two halves and gives each half its own decidable predicate**, then requires both on the same bar:

| Oracle phrase (human packet) | EA predicate | Where it lives | Uses price? |
|---|---|---|---|
| *"price pulls back…"* | fast-EMA slope **leaves** the trend vs `bias_dir` — flat (`LayerFlatRatio`) or reversed (`LayerAllowReversalPullback`) → `LAYER_PB_DETECTED` | `UpdateSingleLayerPullback` (P-R state machine) | **No** — EMA slope only |
| *"…to touch the EMA2"* | (not tested — see *Accepted divergences* below) | — | — |
| *"…and comes back"* (recovery) | **both** layer EMA slopes (fast **and** slow) point in `bias_dir` again, after `LayerMinPullbackBars` → `LAYER_PB_RECOVERED` | `UpdateSingleLayerPullback` | **No** — EMA slope only |
| *"price closes above the EMA1"* | closed bar is beyond the layer's fast EMA in bias direction | **BC** gate, inside `EvaluateL` — *outside* the state machine | **Yes** |
| *(bar must be a real move, not a doji)* | close vs open in bias direction | **BD** gate, inside `EvaluateL` | **Yes** |
| *"EMA1 never crosses below EMA2 during this setup"* | fast/slow cross → layer invalidated, PB state reset to NONE, cascade W→M→S | `UpdateSingleLayerPullback` + `CheckLayerPairAlign` | **No** |

`L = 1` requires *(layer is RECOVERED and positionally aligned)* **AND** *BC* **AND** *BD* — all on the same closed bar. **The conjunction reconstructs the Oracle packet.** The packet is not weakened by the split; it is made decidable. What changed is only *where each half is decided*.

### The invariant

> **Price never enters the pullback-recovery state machine.** The machine reads EMA values and EMA slopes only. Price re-enters the pipeline exactly twice, both as independent factors *outside* the machine: **BC** (close beyond the fast EMA) and **BD** (bar closed in bias direction) — plus the TE-side BC re-check at `shift=0`. This is a deliberate engineering decision, not an omission.

Enforced in code at HEAD `3935f36`:
- `UpdateSingleLayerPullback` contains **no** price-series term (`Close/Open/High/Low/Bid/Ask/iClose/CopyClose`). Its only inputs are the ribbon EMA handles (volume appears only for VPRR bookkeeping and never drives a state transition).
- `LayerPriceTouchEnabled` is **`false` and inert**: the S2 price-zone gate code is removed; the `use_price_touch` parameter survives in the signature for ABI/back-compat and is never read. Setting it `true` has no effect.
- `LayerPullbackRatio` is a **slope** ratio (`|current_pace| / |baseline_pace|`, both EMA-slope paces) — it was never a price test. It is now **inert**: the DETECTED trigger consults `LayerFlatRatio` only. The input, struct field and config-sync entry still exist (dead knobs; see *Known dead inputs* below), so "inert" — not "deleted".
- The EA path, the warm-up replay, and the SignalScan/inspector path all call the *same* `UpdateSingleLayerPullback` with a non-zero `bias_dir`, so all three decide P-R identically.

### Why this is faithful, not a departure

The slow-EMA ribbon *is* a function of price. "The fast EMA stops advancing or rolls over" is the deterministic, feed-independent expression of "price pulled back **far enough to matter**". A dip too shallow to bend the fast EMA is trend breathing — the Oracle's own chart would not mark it as a setup either. And the setup-card diagrams draw sloped, stacked EMAs: slope *is* the machine-readable content of those pictures.

### Accepted divergences (state them, don't hide them)

| Oracle | EA | Consequence |
|---|---|---|
| Pullback must reach the **slow EMA of the pair** ("touch the EMA2") — a *depth* requirement | The EA tests **no depth at all**; any slope-leaving-trend qualifies | The EA is **more permissive** than the Oracle on shallow pullbacks. Accepted: depth was tested (S2) and cost more than it bought. |
| A pullback *through* the slow EMA is still readable to a human as an aggressive dip | Fast/slow cross → layer **invalidated**, cascade to the next-deeper layer | The EA is **stricter** on deep pullbacks — but it does not lose the setup: the deeper layer picks it up. This matches the Oracle's own "EMA1 never crosses below EMA2 during this setup". |

If pullback **depth** is ever wanted back, the correct home is a **new, separate factor** (an F sub-filter, or a fourth per-layer sub-check evaluated alongside BC), never a price term readmitted into the P-R machine — that would re-create failure modes 1–4 above.

### Known dead inputs (documented so they are not mistaken for live controls)

`LayerPullbackRatio` (`Inp_RRM_ORG_LayerPBPullbackRatio`), `LayerRecoveryRatio` / `_W/_M/_S`, `LayerRecoveryOnSlope`, `LayerPriceTouchEnabled` are all present in the input surface and the `ST_Settings` struct but **not read by the engine** under the Path-2 slope model. Changing them changes nothing. They are retained for back-compat and config-file compatibility. Removing them from the UI is a separate task.

---

## 2. Adaptive Spread Limits (Zone 3C)
Different instruments have inherently different liquidity and spread profiles. SimpleEA auto-detects the pair type and applies strict maximum spread limits at the exact moment of execution (shift=0).

| Pair Type | Example | Default Max Spread |
|-----------|---------|--------------------|
| **Major** | EURUSD  | 2.0 pips |
| **Minor** | EURJPY  | 4.0 pips |
| **Exotic** | USDZAR | 10.0 pips |
| **Gold** | XAUUSD  | 5.0 pips |
| **Crypto**| BTCUSD  | 50.0 pips |

*Note: ATR gates (Zone 2A) handle volatility filtering; these adaptive limits strictly handle execution cost management.*

---

## 3. TF-Based Cushions
Cushions automatically scale with the timeframe to provide appropriate noise protection for stops and trailing features. JPY pairs are automatically detected and scaled appropriately (×100 vs standard ×10).

### SL Cushion (`GetRecommendedInitialSlCushionPips`)
Applied to `SL_MODE_PSAR_DOT`, `SL_MODE_SWING`, and `SL_MODE_FRACTAL`.

| Timeframe | Standard Pair | JPY Pair |
|-----------|---------------|----------|
| M1        | 2 pips        | 3 pips   |
| M5        | 3 pips        | 5 pips   |
| M15       | 5 pips        | 8 pips   |
| M30       | 7 pips        | 12 pips  |
| H1        | 10 pips       | 15 pips  |
| H4        | 15 pips       | 25 pips  |
| D1        | 25 pips       | 40 pips  |

### Trail Cushion (`GetRecommendedTrailPsarCushionPips`)
Applied to `TRAIL_PSAR` logic.

| Timeframe | Standard Pair | JPY Pair |
|-----------|---------------|----------|
| M1        | 1 pip         | 2 pips   |
| M5        | 2 pips        | 3 pips   |
| M15       | 3 pips        | 5 pips   |
| H1        | 7 pips        | 10 pips  |
| H4        | 10 pips       | 15 pips  |

### Breakeven Buffer (`GetTFBasedCushion`)
Used as the padding space when moving stops to breakeven (e.g., locking in +5 pips instead of exactly 0.0).
* **M1/M5:** 3 pips
* **M15:** 5 pips
* **H1:** 10 pips
* **H4:** 15 pips

## 3.1 The Trade Lifecycle



```mermaid
flowchart TD
    Start([Tick Open: shift=0]) --> CheckTS{Check g_ts_active}
    
    CheckTS -- No Setup --> Wait([Wait for next tick])
    CheckTS -- Setup Ready --> LiveCheck{Live Execution Gates}
    
    LiveCheck -- Real-time Spread > Limit --> Abort([Abort / Wait])
    LiveCheck -- Passes --> Calc[Calculate TF-Based Cushions]
    
    Calc --> |GetRecommendedInitialSlCushionPips| Exec[Execute Trade via CTrade]
    Exec --> Mgt([Active Trade Management Loop])
    
    Mgt --> BE{Breakeven Triggered?}
    BE -- Yes --> MoveBE[Move SL to Entry + GetTFBasedCushion]
    BE -- No --> Trail{Trailing Triggered?}
    
    Trail -- Yes --> MoveTrail[Trail SL + GetRecommendedTrailPsarCushionPips]
    Trail -- No --> ExitCheck{Exit Condition Met?}
    
    MoveBE --> ExitCheck
    MoveTrail --> ExitCheck
    
    ExitCheck -- Hit SL / TP / PSAR Flip --> Close([Close Position & Reset g_ts_active])
    ExitCheck -- No --> Mgt

    classDef active fill:#e6f3ff,stroke:#0066cc,stroke-width:2px;
    classDef terminal fill:#eeeeee,stroke:#666666,stroke-width:2px;
    class Exec active;
    class Close terminal;
```

---

## 4. Exit Management Modes

```mermaid
flowchart TD
    Live([Trade Executed]) --> SLMode{Stop Loss Mode Selection}
    
    SLMode -- SL_MODE_SWING --> CalcSwing[Find Swing High/Low\n+ Initial SlCushionPips]
    SLMode -- SL_MODE_PSAR_DOT --> CalcPSAR[Find PSAR Dot\n+ Initial SlCushionPips]
    SLMode -- SL_MODE_FRACTAL --> CalcFractal[Find Fractal Base\n+ Initial SlCushionPips]
    
    CalcSwing --> Active[Position Live]
    CalcPSAR --> Active
    CalcFractal --> Active
    
    Active --> BECheck{Breakeven Trigger Met?}
    BECheck -- Yes --> MoveBE[Move SL to:\nEntry + BE Buffer Cushion]
    BECheck -- No --> TrailCheck
    MoveBE --> TrailCheck
    
    TrailCheck{Trailing Logic Mode}
    TrailCheck -- TRAIL_PSAR --> MoveTrailP[Trail SL behind PSAR\n+ TrailPsarCushionPips]
    TrailCheck -- TRAIL_FRACTAL --> MoveTrailF[Trail SL behind Fractal\n+ TrailPsarCushionPips]
    TrailCheck -- TRAIL_PSAR_FLIP_EXIT --> FlipCheck{PSAR Flipped?}
    
    FlipCheck -- Yes --> Close([Force Close Trade])
    FlipCheck -- No --> Wait([Wait Next Tick])
    MoveTrailP --> Wait
    MoveTrailF --> Wait
    
    classDef active fill:#e6f3ff,stroke:#0066cc,stroke-width:2px;
    classDef terminal fill:#eeeeee,stroke:#666666,stroke-width:2px;
    class Active active;
    class Close terminal;
```

### Stop Loss Modes (`ESLMode`)
* `SL_MODE_FIXED_PIPS`: Uses strict user-defined `Inp_SL_FixedPips`.
* `SL_MODE_PSAR_DOT`: Places SL at the last confirmed PSAR dot + TF-based SL Cushion.
* `SL_MODE_SWING`: Finds the highest high / lowest low over `SwingLookback` bars + TF-based SL Cushion.
* `SL_MODE_FRACTAL`: Places SL at the last confirmed Bill Williams 5-bar fractal + TF-based SL Cushion.
* `SL_MODE_PERCENT`: Uses `Inp_SLPercent` of the entry price.

### Take Profit Modes (`ETPMode`)
* `TP_MODE_FIXED_PIPS`: Strict pip distance via `Inp_FixedTPPips`.
* `TP_MODE_RR`: Calculates TP based on actual SL distance multiplied by the active preset's RR-ratio input (e.g. `Inp_RRM_ORG_RRRatio = 2.0` → 1:2 R:R under `PRESET_RRM_ORG`).
* `TP_MODE_FRACTAL`: Targets the next opposing market fractal.
* `TP_MODE_PSAR_FLIP`: No fixed TP; exits solely when the PSAR indicator flips direction.
* `TP_MODE_NONE`: Relies entirely on the Trailing Stop to close the trade.

### Breakeven Modes (`EBeMode`)
* `BE_MODE_OFF`: Breakeven logic disabled.
* `BE_MODE_TP_PROGRESS_PCT`: Moves SL to Entry + BE Buffer when price travels a specific percentage of the way to the Take Profit target.
* `BE_MODE_R_MULTIPLE`: Moves SL to Entry + BE Buffer when price reaches a multiple of the initial risk (e.g., at +1R).

### Trailing Stop Modes (`ETrailingMode`)
* `TRAIL_PSAR`: Trails the SL strictly behind the PSAR dot, padded by the TF-Based Trail Cushion.
* `TRAIL_FRACTAL`: Trails behind established fractal structures.
* `TRAIL_BREAKEVEN`: Enforces breakeven first, then begins trailing at a fixed distance.
* `TRAIL_PSAR_FLIP_EXIT`: Forces position closure immediately upon PSAR reversal (identical utility to TP_MODE_PSAR_FLIP but handled by the trailing engine).

---

## 5. Legacy Settings Removed (v1.03)
To enforce automation and prevent over-optimization, the following manual parameters were permanently removed and replaced by the systemic TF-based functions:
* ❌ `Inp_SL_PsarPipsCushion`, `Inp_SL_SwingPipsCushion` (Replaced by `GetRecommendedInitialSlCushionPips()`)
* ❌ `Inp_PSAR_TrailPipsCushion` (Replaced by `GetRecommendedTrailPsarCushionPips()`)
* ❌ `Inp_RRM_BE_BufferPips` (Replaced by `GetTFBasedCushion()`)
* ❌ `Use_BE`, `BE_Trig`, `BE_Buff` (Replaced by clean `BE_Mode` enums)
* ❌ ATR multipliers (`SL_Mult`, `TP_Mult`, `Trail_Mult`) — no longer used in RRM execution.