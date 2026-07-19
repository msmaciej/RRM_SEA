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
* **P (Phase):** Market structure gate (TM / EM / UNO). UNO always blocks; in `PRESET_RRM_ORG` EM is **allowed for LayerW and LayerM**, blocked for LayerS unless strong-EM trading is enabled (`Emerging_AllowStrongTrades`, see inputs). UNO is always blocked (B=0 so signal is 0 before P is even evaluated).
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
- `LayerPriceTouchEnabled` is **gone** (F-AUDIT-STRUCT 2026-07): the S2 price-zone gate code was removed in Path 2, and the input, the `ST_Settings` field, and the `use_price_touch` parameter have now been removed too. There is no longer any switch — live, inert, or vestigial — by which price can re-enter the P-R machine.
- `LayerPullbackRatio` was a **slope** ratio (`|current_pace| / |baseline_pace|`, both EMA-slope paces) — never a price test. It became inert when the DETECTED trigger was narrowed to `LayerFlatRatio` only, and it is now **deleted** (F-AUDIT-STRUCT 2026-07), along with `LayerRecoveryRatio` / `_W/_M/_S` and `LayerRecoveryOnSlope`. The DETECTED trigger consults `LayerFlatRatio` alone.
- The EA path, the warm-up replay, and the SignalScan/inspector path all call the *same* `UpdateSingleLayerPullback` with a non-zero `bias_dir`, so all three decide P-R identically.

### Why this is faithful, not a departure

The slow-EMA ribbon *is* a function of price. "The fast EMA stops advancing or rolls over" is the deterministic, feed-independent expression of "price pulled back **far enough to matter**". A dip too shallow to bend the fast EMA is trend breathing — the Oracle's own chart would not mark it as a setup either. And the setup-card diagrams draw sloped, stacked EMAs: slope *is* the machine-readable content of those pictures.

### Accepted divergences (state them, don't hide them)

| Oracle | EA | Consequence |
|---|---|---|
| Pullback must reach the **slow EMA of the pair** ("touch the EMA2") — a *depth* requirement | The EA tests **no depth at all**; any slope-leaving-trend qualifies | The EA is **more permissive** than the Oracle on shallow pullbacks. Accepted: depth was tested (S2) and cost more than it bought. |
| A pullback *through* the slow EMA is still readable to a human as an aggressive dip | Fast/slow cross → layer **invalidated**, cascade to the next-deeper layer | The EA is **stricter** on deep pullbacks — but it does not lose the setup: the deeper layer picks it up. This matches the Oracle's own "EMA1 never crosses below EMA2 during this setup". |

If pullback **depth** is ever wanted back, the correct home is a **new, separate factor** (an F sub-filter, or a fourth per-layer sub-check evaluated alongside BC), never a price term readmitted into the P-R machine — that would re-create failure modes 1–4 above.

### Known dead inputs — ✅ RESOLVED (F-AUDIT-STRUCT, 2026-07)

**This section previously read:** *"`LayerPullbackRatio`, `LayerRecoveryRatio` / `_W/_M/_S`, `LayerRecoveryOnSlope`, `LayerPriceTouchEnabled` are all present in the input surface and the `ST_Settings` struct but not read by the engine … Removing them from the UI is a separate task."*

**That separate task is done.** All of them — inputs, `ST_Settings` fields, and `SEA_ConfigSync` entries — are **removed**. There are no longer any dead knobs in the P-R surface to mistake for live controls.

Two consequences worth carrying forward:

1. **`UpdateSingleLayerPullback` lost the `recovery_ratio` and `use_price_touch` parameters.** They were "retained in the signature for ABI/back-compat"; with their feeding fields gone they had no callers. Removing an argument that was never read cannot change a state transition, so **the invariant above is untouched** — and is now stronger: the "no price inside the P-R machine" rule is enforced by the *absence* of any price-touch parameter, rather than by a `false` default that a future edit could flip.

2. **The `LayerPullbackRatio` compile-error workaround is dissolved.** The `_Legacy` rename (and the decoupled `ConfigSync` key it needed) existed only because of an unexplained *"undeclared identifier"* error. The field is deleted, so the identifier cannot be undeclared. The root cause is now traced — a partially-synced `MQL5\Include\RRMS\` directory, *not* the source — see `README_SEA_PARAMETER_MAPPING.md` → *Struct Surface Audit*. **Re-copy all modules to the Include directory before compiling; syncing a subset reproduces the error.**

---

## 1.2 GUARD 1 — skip the first post-flip pullback-recovery

**This section is the canonical statement of GUARD 1.** `Inp_Global_Guard1_SkipFirstPostFlipPR` — **default `false`.**

### Status: hypothesis under test, NOT a traced defect

> GUARD 1 rests on an assumption about **market behaviour** — *"after a bias flip, the first pullback→recovery is where a choppy move exhausts and bias reverses again; in a genuine trend, skipping it costs only one entry."* That premise is **not** derivable from the Oracle, and no code path contradicts the README without it. Per Framework Part F it is therefore a **(b) hypothesis**, and it ships **OFF by default** with an A/B protocol attached (below). It must not be switched on in a live account until the A/B has been run and reports a positive delta. The asymmetry argument is plausible; plausibility is not evidence.

### The rule

After a **genuine signed bias flip** (`+1 → −1` or `−1 → +1`), block the **first completed pullback-recovery cycle** on each layer. Allow entries from the **second completed cycle** onward. Hard block; no size-reduction variant.

| Property | Behaviour |
|---|---|
| **Event-indexed, never time-indexed** | The counter advances on *cycle completions*, never on bar counts. The post-flip trend may run 1..N bars before the first pullback and N is undefined, so a bar-count guard is the wrong abstraction. (`BiasConfirmBars` was rejected in a prior session and is **not** reintroduced.) |
| **Per-layer** | W / M / S each burn their own skip — P-R typically begins in W, then M, then S. |
| **Bias-definition-agnostic** | Hooks the `bias_dir` signal handed to `UpdateLayerPullbackStates`, never any preset's EMA arithmetic. |
| **UNO is transparent** | `0` neither arms nor re-arms the guard. See below — this is structural, not a special case. |
| **Cold start is not a flip** | The `999` sentinel does not arm the guard. |

### Why UNO cannot arm it (structural, not a special case)

`UpdateLayerPullbackStates` is **only ever called with `B != 0`** — the `B == 0` branch of `EvaluateTS_Breakdown` handles UNO separately and explicitly **preserves `m_last_dir_state_bias`**. That member therefore only ever holds `+1`, `−1`, or the `999` sentinel, which makes the existing test

```
if(bias_dir != m_last_dir_state_bias)     // SEA_SignalEngine.mqh
```

**exactly** a signed `±1 → ∓1` flip test. GUARD 1 hooks it directly and adds no new bias tracking. This matters: `DetectMarketPhase` is purely positional and returns UNO **both** in a deep pullback inside a healthy trend **and** on a genuine reversal path — it is directionally ambiguous and cannot mean "bias flipped". If UNO re-armed the guard, every deep pullback would re-arm it and good continuation entries would be lost permanently.

### The counting unit is the CYCLE, not the RECOVERED transition

The state graph already distinguishes them, and the distinction is load-bearing:

- Every **cycle-ending** event lands the layer back in `LAYER_PB_NONE` — TS=1 consumption, max-age expiry, fast/slow cross, phase-change clear, climax reset, sustained-UNO wipe.
- A **relapse** (`RECOVERED → DETECTED`) does **not** pass through `NONE`.

So a relapse that re-recovers is the **same cycle re-completing** and must **not** advance the count. Counting raw `→RECOVERED` transitions instead would let a wobbling first recovery present itself as "the second cycle" and be allowed — defeating the guard in precisely the choppy market it targets.

Implementation: `m_layer_*_g1_counted` latches the cycle as counted at the single `→ LAYER_PB_RECOVERED` write, and is cleared at the single `NONE → DETECTED` transition — the **only** exit from `NONE`. Every reset-to-NONE path therefore clears it for free, with no wiring in any of them (the same self-management pattern as `bars_rec`).

**A blocked first cycle that expires without firing still burns the skip** (`g1_recov` stays 1). Otherwise the guard would have no exit in a market that never offers a clean second cycle, and it would become an indefinite block.

### Where it lives

| Concern | Location (`SEA_SignalEngine.mqh`) |
|---|---|
| Arm on genuine flip (excl. `999`) | `UpdateLayerPullbackStates` + the warm-up replay — both, or live and warm-up desync |
| Zero the counters on flip | `ResetDirectionalState()` |
| Count a completed cycle | the single `state = LAYER_PB_RECOVERED` write in `UpdateSingleLayerPullback` |
| Clear the per-cycle latch | the single `NONE → DETECTED` transition |
| Block the entry | `CheckLayerPairAlign`, immediately after the RECOVERED gate |
| Report | `L_G1_POSTFLIP` (engine reason) · `NO(G1)` (SignalScan inspector) |

The counters are threaded through `UpdateSingleLayerPullback`, which the EA, the warm-up replay and SignalScan **all** call — so the three agree by construction, exactly as §1.1's invariant requires. The warm-up replay re-derives arming and the cycle counts from replayed history, so a flip that happened *before* the EA loaded is seeded correctly and live evaluation does not re-skip a cycle history already spent.

### The A/B that confirms or kills it

Same pair, same timeframe, same date range, same build (**≥ `e5aeadd`**, so the stale-PSAR path is already closed), `Inp_Global_Guard1_SkipFirstPostFlipPR` OFF vs ON. Report:

1. PF, net P&L, trade count — both runs.
2. **Trades removed by the guard, and their aggregate P&L in the OFF run.** This is the decisive number: **if the skipped trades were net-positive, GUARD 1 is dead**, whatever the equity curve does for other reasons.
3. Count of `L_G1_POSTFLIP` blocks (guard fired) vs entries taken — to confirm the guard is firing at the expected rate and not silently inert.

### Deferred — do NOT implement

"GUARD 2", an indicator-based trending-vs-choppy modifier (ADX / Choppiness Index / EMA-fan width). All three are already in the engine, all three are **lagging confirmers, not predictors**. Build and measure GUARD 1 first.

---

## 2. Adaptive Spread Limits (Zone 3C)
Different instruments have inherently different liquidity and spread profiles. SimpleEA auto-detects the pair type (`DetectPairType`) and applies the configured maximum spread limit at the exact moment of execution (shift=0) via `GetAdaptiveSpreadLimit`. Limits are **inputs** — read the current value there, not here:

| Pair Type | Example | Max-spread input |
|-----------|---------|------------------|
| **Major** | EURUSD  | `Inp_Adaptive_Spread_Major` |
| **Minor** | EURJPY  | `Inp_Adaptive_Spread_Minor` |
| **Exotic** | USDZAR | `Inp_Adaptive_Spread_Exotic` |
| **Gold** | XAUUSD  | `Inp_Adaptive_Spread_Gold` |
| **Crypto**| BTCUSD  | `Inp_Adaptive_Spread_Crypto` |
| **Indices** | US30 | `Inp_Adaptive_Spread_Indices` |

*Note: ATR gates (Zone 2A) handle volatility filtering; these adaptive limits strictly handle execution cost management.*

---

## 3. TF-Based Cushions
Cushions automatically scale with the timeframe to provide appropriate noise protection for stops and trailing features. JPY pairs are automatically detected and scaled appropriately (×100 vs standard ×10).

> **The per-TF values in this section are a non-authoritative snapshot** of the named code functions (`GetRecommendedInitialSlCushionPips`, `GetRecommendedTrailPsarCushionPips`, `GetTFBasedCushion`) and may lag them — those functions are the source of truth. `Inp_RM_Override_SL_Cushion` / `_Trail_Cushion` / `_BE_Cushion` (0 = auto) override them.

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