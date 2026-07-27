# SEA Signal Reference & Indicator Engine

## Overview
This document provides the complete technical documentation for the SimpleEA signal processing pipeline, the indicator voting logic, and the developer guide for extending the system with custom indicators via the Centralized Registry.

The Signal Engine evaluates **EVERY condition on the CLOSED candle** (shift=1, the **TS — Trade Setup** evaluation) before allowing any trade. 

The core system uses a strict multiplicative formula where unanimous agreement is required. The canonical form (post-F-AUDIT 2026-06) is:

$$TS = B \times P \times F \times L \times I$$

Expanded with the layer-and-bar-close detail and the F sub-filters:

$$TS = Bias \times Phase \times \prod_{j=1}^{m} F_{j} \times Layer_{X} \times bc_{X} \times \prod_{i=1}^{n} Ind_{i}$$

Where each factor returns 1 (pass/enabled), 0 (fail), or -1 (contradicts). Any 0 or -1 stops the pipeline.

The **Climax / Exhaustion Guard** (previously called `CX` or `CG` as a separate sixth factor) was merged into **F** as a sub-filter in the 2026-06 F-AUDIT. `F = 0` with `F_reason = CLIMAX_GUARD` now blocks an otherwise fully-aligned signal when price has over-extended into a blow-off impulse (single-bar range > `ClimaxGuard_BarATRMult` × ATR, or cumulative move > `ClimaxGuard_MoveATRMult` × ATR, in the trade direction). The conceptual veto (climax-as-veto) is unchanged — only the position in the equation moved, so reason-code reporting reads cleanly under the F factor. The check still re-scans the last `ClimaxGuard_Lookback` bars on every bar (a sliding window, not a stored countdown), so it stays blocking only while the triggering bar is inside that window.

---

## Part 1: The Core Signal Pipeline

```mermaid
flowchart TD
    Start([Bar Close: shift=1]) --> S1{Step 1: Pre-Filters}
    
    S1 -- Fails Spread/Time/News --> Reject([Return 0: NO TRADE])
    S1 -- Passes --> S2[Step 2: Evaluate Bias]
    
    S2 --> |1EMA, 2EMA, 4EMA, Manual| BiasCheck{Bias = ±1 ?}
    BiasCheck -- Bias = 0 --> Reject
    
    BiasCheck -- Bias = ±1 --> S3[Step 3: Evaluate LayerX]
    
    S3 --> |LayerW / LayerM / LayerS| LayerCheck{LayerX = 1 ?}
    LayerCheck -- Local Pair Slope/Pos Fail --> Reject
    
    LayerCheck -- Local Pair Aligned --> S4[Step 4: Evaluate bcX]
    
    S4 --> |Close beyond Fast EMA| BcCheck{bcX = 1 ?}
    BcCheck -- Price Trigger Fail --> Reject
    
    BcCheck -- Price Trigger Pass --> S5{Step 5: Hard Gates & HTF}
    S5 -- Fails --> Reject
    
    S5 -- Passes --> S8[Step 6: Indicator & Filter Voting]
    S8 --> |ADX × VRC × MACD × PSAR...| Math{"Π Ind_i = 1"}
    
    Math -- Fails --> Reject
    Math -- Passes --> End([Store Signal in g_ts_active])
    
    classDef reject fill:#ffcccc,stroke:#cc0000,stroke-width:2px,color:#990000;
    classDef accept fill:#ccffcc,stroke:#009900,stroke-width:2px,color:#006600;
    class Reject reject;
    class End accept;
```

### Step 1: Pre-Filters (Safety Checks)
**Purpose:** Ensure market conditions are safe for trading.
* **Spread Filter:** Current spread < `MaxSpreadPips`. (If fails: reason "SPREAD").
* **Time/Session Filter:** Current time within `StartHr` and `EndHr`. (If fails: reason "TIME").
* **News Filter:** No high-impact news within `NewsPre` and `NewsPost` window.
**Result:** If ANY fail → Return 0 (NO TRADE).

### Step 2: Evaluate Bias
**Purpose:** Determine the PRIMARY trend direction (LONG/SHORT/NEUTRAL).

> **Bias is DIRECTION only.** Direction is defined by **structure**, per mode — *position* for the pair modes, *slope* for the single-EMA mode, *phase* for 4EMA. Momentum/pullback timing is **not** part of bias — that lives entirely in the Layer pullback-recovery system (Step 3). Consequently a directional bias returning `0` requires a genuine no-direction structure (an exact EMA tie, a mathematically flat single EMA, or a genuinely unordered ribbon), which is **rare by construction**. Frequent bias-`0` in a trending market is therefore a bug signal, not a market state. **`BiasMode` is preset-configurable** (`Inp_*`), so RRM_ORG may be run with 1-EMA or 2-EMA bias as well as its default 4-EMA phase — the semantics below apply to whichever mode is active, regardless of preset.

* **BIAS_MANUAL:** Fixed operator direction.
* **BIAS_1EMA:** Single EMA **slope** direction (rising=LONG, falling=SHORT, exactly-flat=NEUTRAL). Flat is near-impossible, so `0` is rare. (Slope *is* the direction here — there is no second EMA to give position.)
* **BIAS_2EMA:** Direction from the **position** of the two bias EMAs (fast above slow = LONG, fast below slow = SHORT). Bias = `0` only on an exact `fast == slow` tie (near-impossible).
  * `STRAT_2EMA_CROSS`: entry signal at the cross point only (one-bar signal)
  * `STRAT_PRICE_CROSS`: entry signal when price crosses the EMA (one-bar signal)
  * `STRAT_2EMA_POSITION`: continuous entry signal while price is on the correct side of both EMAs
  * *Fix 2026-07-22:* pair-mode bias is **position-only**. The former requirement that the fast EMA's **slope** also agree with its position was a momentum/pullback test wrongly folded into bias — it rejected **every pullback bar** (fast still on the trend side of slow but momentarily sloping against the trend) as `BIAS_ZERO`, blocking trades constantly. The slope/pullback check belongs to the Layer system, which already performs it, so it was removed from bias.
* **BIAS_4EMA:** Four-EMA **phase** detection (pure ribbon *position* of EMA2/EMA3/EMA4 — no slope term). EMA periods per `Inp_RRM_ORG_Ema1Period`…`Ema4Period` (EMA1=fastest … EMA4=slowest).
    * *TRENDING:* EMAs stacked descending/ascending (EMA2/3/4 ordered). (Bias = ±1)
    * *EMERGING:* EMA4 sandwiched between EMA2 and EMA3. (Bias = ±1)
    * *UNORDERED:* any other stacking. Bias forced to 0.

**Bias reason codes** (what the cockpit / `m_diag_last_reason` reports when bias = 0):

| Reason | Meaning |
|--------|---------|
| `BIAS_ZERO` | Genuine no-direction structure — an exact EMA tie, a flat single-EMA slope, or (4EMA) a genuinely unordered ribbon. A correct no-trade. |
| `BIAS_INVALID_READ` | A bias EMA **read failed** (both iMA and the manual fallback returned invalid). This is *bias unknown*, **not** a real no-direction market — a read defect to chase, no longer masked as `BIAS_ZERO`. Applies to both the 2EMA and 4EMA paths (2026-07-22). |
| `BIAS_DISABLED` | `BiasEnabled = false`. |
| `PHASE_UNORDERED` | (4EMA) the ribbon read cleanly and is genuinely unordered — the honest label matching the P factor (2026-07-22). |

> **Spurious bias-zero on a valid trending bar — fixed 2026-07-22 (root cause).** A separate defect could make a fully valid bar (`BIAS+` / TM / layers in-trend) report `TS=0` blocked by `BIAS_ZERO`/`PHASE_UNORDERED` — the "blocks constantly" paradox. Cause: the **shadow** layer-state derivation (`DeriveLayerState`, run in parallel for the `[PB_DERIVE_DIFF]` diagnostic and *not* used for the verdict) **replayed `EvaluateB()` across historical bars**, and `EvaluateB` writes shared members (`m_eval_any_failure`, `m_eval_first_failure`, `m_diag_last_reason`). When the replay window contained an unordered historical bar it set `m_eval_any_failure=true` on the **live** evaluation, forcing `TS=0` and stamping a stale bias-zero reason regardless of the live bar's true state. Fix: the shadow now runs **only under `DebugFlow`** and its shared-state writes are snapshotted and restored, so it can never affect the live decision. This was the true cause of frequent `BIAS_ZERO` in trending markets — not the bias computation itself.

### Step 3: Evaluate LayerX ($Layer_{W}, Layer_{M}, Layer_{S}$)
**Purpose:** Confirm that the EMA pair is structurally aligned AND has completed a pullback-recovery cycle at this depth.

Each layer runs two independent checks. Both must pass.

**3a. Positional alignment:** the fast EMA is on the correct side of the slow EMA (above for LONG, below for SHORT). If misaligned, the layer fails immediately — the cascade rule (EMA1 crosses EMA2 → LayerW blocked, LayerM evaluates instead) is enforced here purely through position.

**3b. Pullback-recovery state machine:** each layer independently tracks whether a pullback has occurred and recovered. Three states:
- `LAYER_PB_NONE` — no pullback seen yet → **blocked** (must earn a pullback-recovery cycle first)
- `LAYER_PB_DETECTED` — pullback in progress → **blocked**
- `LAYER_PB_INTREND` — pullback completed, trend resumed → **allowed**

All slope tests are taken against **`bias_dir`** (the live B-factor direction), not a historical baseline — a baseline measured inside the dip points the wrong way and can strand a layer in DETECTED.

**DETECTED triggers — the fast EMA's slope *leaves* the trend (flat OR reversed):**
- Slope flat: `|slope| ≈ 0` within `LayerFlatRatio` (per `Inp_RRM_ORG_LayerPBFlatRatio`) — fast EMA has stopped advancing (tolerant edge).
- Slope reversed: fast-EMA slope sign now opposite `bias_dir` (when `LayerAllowReversalPullback` is enabled, per `Inp_RRM_ORG_LayerPBAllowReversal`) — fast EMA rolling over toward the slow EMA (conservative case).
- A fast EMA still sloping in `bias_dir` at a shallower angle is normal trend breathing — **not** a pullback. (The magnitude-ratio "weakened" trigger is removed.)
- Price-zone touch is a **price** test, not slope; it is excluded from this model and `LayerPriceTouchEnabled` is off by default (see inputs).

**Minimum duration gate (A21):** DETECTED must persist for at least `LayerMinPullbackBars_W/M/S` bars (per `Inp_RRM_ORG_MinPBBars_W/M/S`; contract ≥ 2) before IN-TREND is allowed. A pullback cannot complete in one bar.

**IN-TREND triggers:** both of the layer's EMA slopes (fast **and** slow) point in `bias_dir` again — after the minimum bar count is satisfied. Slope-only; **not** a close-vs-EMA test (that is the separate BC gate), so no longer a duplicate of BC. IN-TREND holds until a counter-`bias_dir` slope reversal relapses it to DETECTED or a TS=1 signal consumes it; optional `LayerRecoveryMaxAge` cap (default = observation window) expires a stale IN-TREND.

Each layer's state is reset to NONE after a TS=1 signal consumes it, requiring a fresh pullback-recovery before the next entry on that layer.

> **Why this machine is EMA-only and price sits in BC instead:** the Oracle states pullback and recovery as one human-perceptual packet; the EA splits it into two decidable predicates — structure (P-R: EMA position + slope) and price (BC: close beyond the fast EMA) — and requires both on the same bar. Canonical rationale + the "no price inside P-R" invariant: **`README_SEA_TRADE_LOGIC.md` §1.1**.

### Step 4: Evaluate bcX ($bc_{W}, bc_{M}, bc_{S}$)
**Purpose:** The final price action trigger verifying momentum resumption (Bar Close confirmation).
* **Logic:** Evaluates to 1 ONLY if the closed candle body strictly crosses or closes beyond the fast EMA of the active layer. 
* *Example (Short LayerW):* Bias is -1. LayerW is 1. `bcW` becomes 1 only when `Close < EMA1`.

### Step 5 & 6: Gates, Indicators, and Filters
Each ENABLED indicator calls its `Check_XXX(bias, shift)` function. The system enforcing a multiplicative unanimous agreement. Disabled indicators automatically return $1$. If all active equations pass, the final TS is approved and stored in `g_ts_active`.

### The Three Trade Setups (BIAS_4EMA Mode)

When using 4-EMA bias detection, the system evaluates **3 potential setups simultaneously**:

1. **LayerW × bcW (Weak/Ribbon Setup)**
   - Structural check: EMA1 vs EMA2 position + slope aligned
   - Trigger: Close beyond EMA1 (fast EMA)
   - Characteristics: Shallow pullback, fastest entry, lower risk
   - Example (LONG): EMA1 > EMA2, both rising, Close > EMA1

2. **LayerM × bcM (Medium/Ghost Setup)**
   - Structural check: EMA2 vs EMA3 position + slope aligned
   - Trigger: Close beyond EMA2
   - Characteristics: Medium pullback, balanced risk/reward
   - Example (LONG): EMA2 > EMA3, both rising, Close > EMA2

3. **LayerS × bcS (Strong/Shark Setup)**
   - Structural check: EMA3 vs EMA4 position + slope aligned
   - Trigger: Close beyond EMA3
   - Characteristics: Deep pullback, highest confirmation, higher risk
   - Example (LONG): EMA3 > EMA4, both rising, Close > EMA3

**Important**: Only **ONE** of these three setups needs to be active to generate a trade signal. The system takes the first active setup that passes all filters.

---

## Part 2: Indicator Voting Logic & UI Audit
To maintain institutional transparency, the Signal Engine generates a "Live Audit" string for the UI Cockpit. 

### The Audit Format
Each enabled indicator must report its status using the following nomenclature:
- **[+] PASS:** The indicator matches the primary bias (e.g., Bias is LONG and MACD > Signal).
- **[-] FAIL:** The indicator contradicts the primary bias (e.g., Bias is LONG but RSI is Overbought).
- **[.] NEUTRAL:** The indicator is enabled but currently returning a 0/Flat signal.

### Telemetry Mapping
The `ST_SignalTelemetry.active_indicators` field is a newline-delimited string:
`MACD [+]\nPSAR [+]\nCCI [.]\nADX [-]`

The UI Agent is responsible for parsing these symbols into the visual Cockpit grid using the primary Theme colors (`clr_Pass`, `clr_Fail`, `clr_Disabled`).

### ADX (Trend Strength)
* **Static Mode:** ADX > fixed threshold (e.g., 25.0).
* **Dynamic Percentile Mode:** Adaptive threshold based on recent history.
    $$Threshold = Percentile(Buffer_{ADX}, Lookback_{100}, Percentile_{50})$$
* **Phase-Aware Mode:** Threshold scales by market phase (e.g., 12.0 for Unordered, 25.0 for Trending).

### VRC (Volatility Regime Classifier)
Filters out trades during low volatility regimes. Evaluates as a non-directional vote.
* **Check:** $$ATR_{current} \geq Percentile(Buffer_{ATR}, 100, 33)$$
* **Result:** VOLATILITY_LOW (reject) or VOLATILITY_NORMAL (pass). Cache updated every 4 hours.

### MACD (Momentum)
* **LONG:** Main > 0 AND Main > Signal.
* **SHORT:** Main < 0 AND Main < Signal.

### PSAR (Trend Direction)
* **Dot side is measured against the candle BODY, not Close.** On the closed bar (shift=1):
  * **LONG:** PSAR dot **below the body** — `dot < min(Open, Close)`.
  * **SHORT:** PSAR dot **above the body** — `dot > max(Open, Close)`.
  * A dot **inside** the body (between Open and Close) is on **neither** side and fails the vote. Using the body (not Close alone) is shape-robust — it judges dojis and long-wick bars correctly and matches how the dot sits relative to the candle. (Implemented by `PsarOnBullSide` / `PsarOnBearSide` in `SEA_SignalEngine.mqh`; the same body rule is used everywhere the dot side is evaluated, including the executor's trailing/SL anchoring.)
* **Evaluated only at shift=1 (closed bar).** Intra-bar (shift=0) dot movement is irrelevant — the dot may flip many times within a forming bar; only the closed-bar position counts.
* **Dot side is absolute — no grace.** At shift=1 the dot is either on the correct side of the body or the vote fails. There is **no** exception for a dot that has "recently flipped" to the wrong side. (The former `PSAR_FlipGraceBars` window was **removed 2026-07-19** — it inverted the rule and produced wrong-side-dot TS=1 false positives, contradicting RRM Trade Checklist item 4.)
* **PSAR Flip window — stateless.** When enabled (`Vote_AllowPsarFlip`), the dot-side test above must pass **first**; only then must a flip into that side have occurred within the last N bars, where N = `Vote_PsarFlipDelay{,_W,_M,_S}`. This is evaluated by **re-scanning the last N closed bars** each call: a flip into the correct side happened iff the dot was clearly on the **opposite** side of the body on some bar in `[shift+1 … shift+N]`. `N = -1` → persistent (dot position only); `N = 0` → flip on this bar only. **No persisted flip tracker** is consulted — the window is re-derived from raw bars every evaluation, so it cannot be de-synced by warm-up seeding or a mistimed reset (mirrors the stateless `PSFCL` logic in the RRM_EAv0.1_PY reference). The flip window can only make an already-correct-side dot *stricter*, never admit a wrong-side one.

### DPI (Dynamic Price Index) — Momentum Direction Voter

**Purpose:** Primary momentum direction confirmation using MACD-based histogram with optional CCI trend filter.

**How it works:**
- **Blue Line (LEAD):** Fast MACD core = EMA(Fast) - EMA(Slow)
- **Red Line (FOLLOW):** Smoothed signal line (EMA of Blue, or Double EMA)
- **Histogram:** Blue - Red (divergence/convergence)
- **Ribbon Color:** Determines vote direction
  - **Yellow ribbon** → DPI votes bullish (confirms LONG bias)
  - **Red ribbon** → DPI votes bearish (confirms SHORT bias)

**Vote Logic (used by EA):**
```mql5
// Ribbon color drives the vote (histogram color after CCI filter)
if (ribbon_color == YELLOW && bias == LONG)  return +1;  // Pass
if (ribbon_color == RED && bias == SHORT)    return +1;  // Pass
return 0;  // Fail
```

**Histogram Color Logic:**

*Without CCI:*
- hist > 0 → Yellow (bullish momentum)
- hist < 0 → Red (bearish momentum)

*With CCI Reset Enabled (trend filter):*
- hist > 0 AND CCI > 0 → Yellow (strong bullish)
- hist > 0 AND CCI < 0 → **Red** (bullish weakening — CCI reset!)
- hist < 0 AND CCI > 0 → **Yellow** (bearish weakening — CCI reset!)
- hist < 0 AND CCI < 0 → Red (strong bearish)

**GREEN Histogram (visualization only, not a vote):**
- Appears when Blue line and histogram are aligned (both positive OR both negative)
- Indicates momentum confirmation strength
- Does NOT affect EA voting logic

**EA Settings (PRESET_RRM_ORG)** — *non-authoritative snapshot. Authoritative current values live in the `Inp_RRM_ORG_DPI_*` inputs (`SEA_Inputs.mqh`); the defaults below are illustrative and may lag the inputs:*
- `Ind_Dpi_Enabled` — Enable/disable DPI voter (default: true in RRM_ORG)
- `DPI_MACD_Fast` — Fast EMA period (default: 8)
- `DPI_MACD_Slow` — Slow EMA period (default: 13)
- `DPI_RedSignalType` — Red signal line calculation (1-5):
  1. EMA5 of Blue
  2. EMA8 of Blue
  3. EMA13 of Blue (default)
  4. EMA21 of Blue
  5. Double smoothed EMA
- `DPI_UseCCIReset` — Enable CCI trend filter (default: true)
- `DPI_CCI_Period` — CCI calculation period (default: 13)
- `DPI_UseGreenHist` — Enable GREEN visualization overlay (default: true)

**DPI Deceleration Filter** (advanced):
- When enabled via `DpiDecelFilterEnabled`, blocks entries when GREEN histogram is shrinking
- Prevents late entries when momentum is weakening
- Only active when `Ind_Dpi_Enabled = true`

**Standalone Indicator Files:**
- `DPI_mc_main.mq5` — Full version with GREEN momentum overlay (toggleable)
- `DPI_mc_simple.mq5` — Simplified version without GREEN overlay
- `DPI_tm_simple.mq5` — TSI+MACD math variant (William Blau Ergodic)

**Trading Interpretation:**
- **Strong signals:** Yellow/Red histogram with no CCI resets
- **Weak signals:** Histogram color contradicts position (CCI reset active)
- **Avoid:** Ribbon color contradicts the bias direction

**Example (LONG setup):**
```
Bias = LONG (+1)
DPI Blue = 0.0005 (positive)
DPI hist = 0.0003 (positive)
CCI = +50 (bullish)
→ Ribbon = YELLOW (hist > 0, CCI > 0)
→ DPI vote = +1 (PASS)
→ GREEN visible (Blue and hist aligned)
```

See also:
- [`PRESET_RRM_ORG` preset flow](README_SEA_PRESETS.md#preset_rrm_org)
- [DPI `mc_main` EA integration notes](../DPI_mc_main_README.md#ea-integration-preset_rrm_org)

### CandleBody (CB) — Over-Extension Voter

**Purpose:** blocks entries on a bar whose body is abnormally large vs the recent average — a single-bar over-extension filter inside the indicator product ∏Ind.

**Sub-equation:** `CB = CB_body × CBOEB`

- **CB_body** (stateless, per bar): `0` if any of the last `CandleBody_CheckBars` bars has body `|close-open| > CandleBody_MaxMult ×` the average body of the prior `CandleBody_AvgPeriod` bars, in the trade direction. Shift-relative (evaluates the signal bar, never bar 0). Optional close-in-range quality check (`CandleBody_MinCloseRatio`).
- **CBOEB** (over-extension carry, stateful) — **[PENDING compile]**: once `CB_body` flags an over-extended bar, `CBOEB = 0` and holds the whole CB vote at 0 — so `CB = 1 × 0 = 0` even on a later bar whose own body is fine — until the **first of W/M/S completes a fresh pullback-recovery**, then it returns to 1. Edge-detected so a layer already recovered at trip-time does not clear it instantly. Toggle `CandleBody_CarryOnOverext` (default ON). Advanced once per bar in `UpdateLayerPullbackStates` (and the warmup replay), so live and scanner agree.

CandleBody is independent of the Climax factor `CX`: **CB** measures *body size* inside ∏Ind; **CX** measures *range / cumulative move vs ATR* over a lookback window as its own top-level factor. Neither reads the other. (Neither measures *distance from the EMAs* — a bar far from EMA89 with a normal body and no fresh range spike passes both.)

**Inputs:** `Ind_CandleBody_Enabled`, `CandleBody_AvgPeriod`, `CandleBody_MaxMult`, `CandleBody_CheckBars`, `CandleBody_RequireDirection`, `CandleBody_MinCloseRatio`, `CandleBody_CarryOnOverext` [PENDING].

---

## Part 3: Extending the System (Plugin Architecture)

```mermaid
sequenceDiagram
    autonumber
    participant Cfg as SEA_Config.mqh
    participant Eng as SEA_SignalEngine.mqh
    participant Pipe as TS Pipeline

    Note over Cfg: Add inputs (e.g., Inp_Use_Ichi)
    Note over Cfg: Map to EA_Settings struct
    Note over Cfg: Add to g_indicator_registry[]
    Cfg->>Eng: Passes GlobalSettings Struct via InitializeConfig()
    
    Note over Eng: Declare handle (h_ichi)
    Note over Eng: Init() -> Create iIchimoku handle
    Note over Eng: Write Check_Ichi(bias, shift) function
    
    Eng->>Pipe: Inject CAST_VOTE macro into Equation
    Pipe-->>Eng: Returns Multiplicative Result (0 or 1)
```

SimpleEA uses a centralized indicator registry. To add a custom indicator (e.g., Ichimoku), you only modify `SEA_Config.mqh` and `SEA_SignalEngine.mqh`. No UI or preset files need changing.

### The 5-Component Plugin Pattern
1.  **Inputs (`SEA_Config.mqh`):** Add `Inp_Use_Ichi`, `Inp_W_Ichi`, and period variables.
2.  **Settings Struct (`SEA_Config.mqh`):** Add `Use_Ichi`, `W_Ichi`, and periods to `ST_Settings`. Map them in `InitializeConfig()`.
3.  **Handle (`SEA_SignalEngine.mqh`):** Declare `int h_ichi`. Create in `Init()` via `iIchimoku()`. Release in `Release()`.
4.  **Vote Function (`SEA_SignalEngine.mqh`):** 

```c
    bool Check_Ichi(int bias, int shift) {
        if(h_ichi == INVALID_HANDLE) return false;
        double cloud_top = MathMax(span_a, span_b);
        if(bias == 1) return (close > cloud_top);
        return false;
    }
```

5.  **CAST_VOTE macro (`SEA_SignalEngine.mqh`):** Add `CAST_VOTE(m_settings.Use_Ichi, m_settings.W_Ichi, Check_Ichi(bias, v_shift))` into `GetDirection()`.

### The Centralized Registry
To ensure the UI, Cockpit, and Status Panels automatically track your new indicator, add it to the registry in `SEA_Config.mqh`:

```c
// Inside InitializeIndicatorRegistry()
g_indicator_registry[i].name       = "Ichimoku";
g_indicator_registry[i].short_name = "Ichi";
g_indicator_registry[i].is_enabled = cfg.Use_Ichi;
g_indicator_registry[i].weight     = cfg.W_Ichi;
i++;
```

## Indicator Audit & Cockpit Grid (Restored v1.03)

The UI Cockpit uses a dynamic "Strategy Logic" zone to display the real-time status of the 9-step voting pipeline.

### The Telemetry Protocol
The Signal Engine generates the `active_indicators` string at the end of each bar evaluation. This string acts as the source of truth for the UI Agent.

| Symbol | UI Translation | Color Logic | Meaning |
| :--- | :--- | :--- | :--- |
| `[+]` | `(+)` | `clr_Pass` | Indicator confirms the Trade Setup (TS). |
| `[-]` | `(-)` | `clr_Fail` | Indicator contradicts the Trade Setup. |
| `[.]` | `(.)` | `clr_Disabled` | Indicator is neutral or below threshold. |

### Visual Layout
The UI renders these as a vertical audit list within the Cockpit panel, providing the operator with instant feedback on why a signal was accepted or rejected.

---

## KISS Refactor Notes (v1.04+)

The signal evaluation pipeline was significantly simplified in v1.04, then the pullback-recovery state machine was re-introduced and extended in subsequent sessions.

**What was removed in v1.04:**
- The original wick-touch pullback detection (1% tolerance, historical bar scanning, ~300 lines)
- Complex multi-pass recovery state machines from the pre-v1.04 architecture
- `RequirePullback`, `PullbackLookback`, `Gate_UseMultiLayer` legacy inputs

**What replaced it (v1.04):**
- **EvaluateLayerX()**: Pure structural alignment (position + slope) per EMA pair
- **EvaluateBcX()**: Simple price close confirmation beyond fast EMA
- ~500 lines of dead code removed, clearer logic, faster execution

**What was re-introduced and extended (post-v1.04, Sessions A1–S2):**
- Full pullback-recovery state machine (`LAYER_PB_NONE / DETECTED / IN-TREND`) — one independent machine per layer
- Slope-flat DETECTED trigger: `ratio < LayerFlatRatio` — the fast EMA has stopped advancing
- Slope-reversal DETECTED trigger: `LayerAllowReversalPullback` — catches shallow pullbacks
- **A21 minimum pullback duration gate:** `LayerMinPullbackBars_W/M/S` (2/2/2) — a pullback cannot complete in one bar
- VPRR (Volume Pullback-Recovery Ratio) — **NO LONGER A GATE OR A VOTER (2026-07-27).** It measures and logs only; it cannot block a trade under any preset or setting. See `README.md` "VPRR — measurement-only" and `README_SEA_VPRR_MEASUREMENT.md`
- CBOEB (CandleBody Over-Extension Carry) — CB vote held at 0 until a fresh pullback-recovery cycle

**What was removed again (Path 2, 2026-07) — do not reintroduce:**
- **Slope-ratio "weakened" DETECTED trigger** (`|current_pace| / |baseline_pace| < LayerPullbackRatio`). A fast EMA still sloping in `bias_dir` at a shallower angle is normal trend breathing, not a pullback; the trigger oscillated state and produced noise entries. The engine no longer reads `LayerPullbackRatio` — the input and struct field survive as **dead knobs** (back-compat only; changing them has no effect).
- **S2 price-zone DETECTED trigger** (wick entering the EMA band). It was a *price* test inside a state machine that is defined on EMA position + slope. `LayerPriceTouchEnabled` defaults `false` and the gate code is removed — the parameter is **inert**.
- **Close-vs-EMA recovery** (`recovery_cond`). It duplicated the BC gate exactly; IN-TREND is now slope-only and structurally distinct from BC.
- **The S2 one-bar `NONE → IN-TREND` shortcut.** A pullback-recovery cycle cannot complete inside a single candle; the A21 gate is never bypassed.

See `README_SEA_TRADE_LOGIC.md` §1.1 for why each of these was removed and where price legitimately re-enters the pipeline.

**Enum Clarity (v1.04):**
- `BIAS_AUTO` renamed to `BIAS_2EMA` (2-EMA crossover)
- `BIAS_AUTO_PHASE` renamed to `BIAS_4EMA` (4-EMA phase detection)

**Enum Clarity (v1.05):**
- `BIAS_1EMA` added (single EMA slope direction)
- `STRAT_SINGLE_SLOPE` renamed to `STRAT_1EMA_SLOPE`
- `STRAT_PAIR_CROSS` renamed to `STRAT_2EMA_CROSS`
- `STRAT_POSITION_SLOPE` renamed to `STRAT_2EMA_POSITION`
- `STRAT_LAYER_DETECTION` renamed to `STRAT_4EMA_LAYER`
- `ValidateBiasStratCombo()` added to enforce valid combinations

The current formula including the pullback gate:
```
TS = Bias × Phase × F × (LayerW_rec × bcW  OR  LayerM_rec × bcM  OR  LayerS_rec × bcS) × Indicators × CG
```
Where `LayerX_rec` = 1 only when that layer's state machine is in `LAYER_PB_INTREND`.
