# SEA Signal Reference & Indicator Engine

## Overview
This document provides the complete technical documentation for the SimpleEA signal processing pipeline, the indicator voting logic, and the developer guide for extending the system with custom indicators via the Centralized Registry.

The Signal Engine evaluates **EVERY condition on the CLOSED candle** (shift=1, the **TS — Trade Setup** evaluation) before allowing any trade. 

The core system uses a strict multiplicative formula where unanimous agreement is required. Based on the KISS architecture, the core equation is:

$$TS = Bias \times Layer_{X} \times bc_{X} \times \prod_{i=1}^{n} Ind_{i} \times \prod_{j=1}^{m} Filter_{j}$$

Where each factor returns 1 (pass/enabled), 0 (fail), or -1 (contradicts). Any 0 or -1 stops the pipeline.

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
* **BIAS_MANUAL:** Fixed operator direction.
* **BIAS_1EMA:** Single EMA slope direction (up=LONG, down=SHORT, flat=NEUTRAL).
* **BIAS_2EMA:** Two EMAs crossover or position+slope validation.
  * `STRAT_2EMA_CROSS`: Signal at cross point only (one-bar signal)
  * `STRAT_PRICE_CROSS`: Signal when price crosses EMA (one-bar signal)
  * `STRAT_2EMA_POSITION`: Continuous signal when Fast>Slow + slopes agree
* **BIAS_4EMA:** Four EMAs phase detection. Uses EMA1=5, EMA2=13, EMA3=34, EMA4=89.
    * *TRENDING:* 3 of 3 layers agree on position + slope. (Bias = ±1)
    * *EMERGING:* 2 of 3 layers agree. (Bias = ±1)
    * *UNORDERED:* < 2 layers agree. Bias forced to 0.

### Step 3: Evaluate LayerX ($Layer_{W}, Layer_{M}, Layer_{S}$)
**Purpose:** Validate the local structural alignment for a specific pair of moving averages.
Instead of tracking dynamic wicks, the engine simply checks if the target EMA pair is structurally aligned with the Bias.
* **LayerW (Weak / Ribbon):** Evaluates position and slope of EMA1 vs EMA2. Returns 1 if aligned.
* **LayerM (Medium / Ghost):** Evaluates position and slope of EMA2 vs EMA3. Returns 1 if aligned.
* **LayerS (Strong / Shark):** Evaluates position and slope of EMA3 vs EMA4. Returns 1 if aligned.

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
* **LONG:** Close > PSAR dot.
* **SHORT:** Close < PSAR dot.
* **PSAR Flip Logic:** (If `Vote_AllowPsarFlip=true`), checks `bars_since_flip <= Vote_PsarFlipDelay` to ensure entry happens early in the flip cycle.

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

**EA Settings (PRESET_RRM_ORG):**
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

The signal evaluation pipeline has been drastically simplified:

**What was removed (v1.04):**
- Dynamic pullback detection with 1% wick touch tolerance (~300 lines)
- Historical bar scanning for pullback extremes
- Complex recovery detection state machines
- Phase-layer filtering logic
- Pullback state tracking variables (`RequirePullback`, `PullbackLookback`, `Gate_UseMultiLayer`)

**What replaced it:**
- **EvaluateLayerX()**: Pure structural alignment (position + slope) per EMA pair
- **EvaluateBcX()**: Simple price close confirmation beyond fast EMA
- **Result**: ~500 lines of dead code removed, clearer logic, faster execution

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

The formula is now purely multiplicative with clear OR logic for layers:
```
TS = Bias × (LayerW × bcW OR LayerM × bcM OR LayerS × bcS) × Indicators × Filters
```
Any Bias=0 or all layers=0 immediately stops the pipeline.

### Step 3 Detail: EvaluateLayerX
Each layer checks two conditions for the selected EMA pair:
1. **Position**: Fast EMA must be on the correct side of Slow EMA (above for LONG, below for SHORT).
2. **Slope**: Both EMAs must be sloping in the direction of the Bias (rising for LONG, falling for SHORT).

Returns 1 if both conditions pass, 0 otherwise. At least ONE of the three layers (LayerW, LayerM, LayerS) must return 1 to proceed.

### Step 4 Detail: EvaluateBcX
For each **active** layer (LayerX == 1), checks if the closed candle has momentum confirmation:
- **LONG Setup**: `Close > Fast EMA` of the active layer
- **SHORT Setup**: `Close < Fast EMA` of the active layer

**Example (Short LayerW):**
- Bias = -1 (SHORT)
- LayerW = 1 (EMA1 < EMA2, both falling)
- bcW = 1 when Close < EMA1

At least ONE active layer must have its bcX confirmed to proceed.
