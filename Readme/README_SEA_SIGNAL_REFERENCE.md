*** 

### File 1: SEA_SIGNAL_REFERENCE.md
*(Consolidates 'README_INDICATORS.md' and 'README_EXTENDING.md'. Save as 'README_SEA_SIGNAL_REFERENCE.md')*

```markdown
# SEA Signal Reference & Indicator Engine

## Overview
This document provides the complete technical documentation for the SimpleEA signal processing pipeline, the indicator voting logic, and the developer guide for extending the system with custom indicators via the Centralized Registry.

The Signal Engine evaluates **EVERY condition on the CLOSED candle** (shift=1, the **TS — Trade Setup** evaluation) before allowing any trade. 

The core system uses a strict multiplicative formula where unanimous agreement is required:
$TS = Bias \times MarketPhase \times EntryLayer \times \prod_{i=1}^{n} Ind_{i}$

Where each factor returns 1 (pass), 0 (fail), or -1 (contradicts). Any 0 or -1 stops the pipeline.

---

## Part 1: The 9-Step Signal Pipeline

flowchart TD
    Start([Bar Close: shift=1]) --> S1{Step 1: Pre-Filters}
    
    S1 -- Fails Spread/Time/News --> Reject([Return 0: NO TRADE])
    S1 -- Passes --> S2[Step 2: Market Bias Detection]
    
    S2 --> |BIAS_AUTO_PHASE| Phase[Evaluate 4-EMA Structure]
    Phase --> S3[Step 3: Entry Signal & Layer Detection]
    
    S3 --> |L1 Ribbon / L2 Ghost / L3 Shark| S4{Step 4: Validate Bias == Entry}
    S4 -- Mismatch --> Reject
    
    S4 -- Matches --> S5{Step 5: HTF Filter}
    S5 -- Veto --> Reject
    
    S5 -- Passes --> S6{Step 6: Hard Gates}
    S6 -- Fails Dynamic/Phase Gates --> Reject
    
    S6 -- Passes --> S7{Step 7: Voting Bypass?}
    S7 -- Threshold <= 1 --> S9[Step 9: Final Decision - Accept]
    
    S7 -- Threshold > 1 --> S8[Step 8: Indicator Voting]
    S8 --> |ADX × VRC × MACD × PSAR...| Math{"Π Ind_i >= VoteThreshold"}
    
    Math -- Fails --> Reject
    Math -- Passes --> S9
    
    S9 --> End([Store Signal in g_ts_active])
    
    classDef reject fill:#ffcccc,stroke:#cc0000,stroke-width:2px,color:#990000;
    classDef accept fill:#ccffcc,stroke:#009900,stroke-width:2px,color:#006600;
    class Reject reject;
    class End accept;

### Step 1: Pre-Filters (Safety Checks)
**Purpose:** Ensure market conditions are safe for trading.
* **Spread Filter:** Current spread < `MaxSpreadPips`. (If fails: reason "SPREAD").
* **Time/Session Filter:** Current time within `StartHr` and `EndHr`. (If fails: reason "TIME").
* **News Filter:** No high-impact news within `NewsPre` and `NewsPost` window.
**Result:** If ANY fail → Return 0 (NO TRADE).

### Step 2: Market Bias Determination
**Purpose:** Determine the PRIMARY trend direction (LONG/SHORT/NEUTRAL).
* **BIAS_MANUAL:** Fixed operator direction.
* **BIAS_AUTO:** Traditional 2-EMA check. Fast > Slow AND both slopes rising = LONG. Fast < Slow AND both slopes falling = SHORT.
* **BIAS_AUTO_PHASE (RRM Default):** Uses 4 EMAs (EMA1=5, EMA2=13, EMA3=34, EMA4=89) to detect market structure.
    * *TRENDING:* 3 of 3 layers agree on position + slope. (Bias = ±1)
    * *EMERGING:* 2 of 3 layers agree. (Bias = ±1)
    * *UNORDERED:* < 2 layers agree. Bias forced to 0. 

### Step 3: AutoStrat Entry Signal & Layer Detection
**Purpose:** Generate timing signal within the bias context.
* **STRAT_PAIR_CROSS:** Fast EMA crosses Slow EMA.
* **STRAT_LAYER_DETECTION:** Detects pullback-recovery patterns using 1% `LayerTouchTolerance`.
    * `LAYER_3_STRONG` ("Shark"): Price touches EMA3/EMA4 zone. Deep pullback.
    * `LAYER_2_MEDIUM` ("Ghost"): Price touches EMA2/EMA3 zone. Medium pullback.
    * `LAYER_1_WEAK` ("Ribbon"): Price touches EMA1/EMA2 zone. Shallow pullback.

### Step 4: Signal Validation
**Purpose:** Ensure the entry signal matches the primary bias.
* IF bias = 1 (LONG), entry_signal must = 1. Mismatches return 0.

### Step 5: HTF (Higher Timeframe) Filter
**Purpose:** Confirm trend on higher timeframe.
* Checks HTF EMA slope (e.g., H4 EMA slope when trading H1).
* If bias ≠ HTF direction → VETO (reason "HTF_VETO").

### Step 6: Hard Gates (Sequential)
**Gate 1: Dynamic Pullback Detection:** Validates the pullback sequence (pullback extreme reached $\rightarrow$ recovery started $\rightarrow$ layer intact). Lookback = 15 (M1/M5) or 10 (M15+).
**Gate 2: Phase-Based Layer Filtering (RRM):** * *UNORDERED:* Blocks all layers.
* *EMERGING:* Allows L1, L2. Blocks L3 (avoids deep reversals in unconfirmed trends).
* *TRENDING:* Allows L1, L2, L3.
**Gate 3: EMA Divergence:** Requires expanding EMAs to confirm momentum acceleration.

### Step 7: Voting Bypass Check
If `VoteThreshold <= 1`, skip Step 8 and accept signal immediately.

### Step 8: Indicator Voting
Each ENABLED indicator calls its `Check_XXX(bias, shift)` function. All presets enforce `VOTE_MODE_ALL` (multiplicative unanimous agreement).

### Step 9: Final Decision
If votes >= `VoteThreshold`, return bias (1 or -1). Signal is stored in `g_ts_active` for next bar's TE execution.


### 1.2 Bias & Phase Logic

flowchart TD
    Start([Evaluate 4-EMA Stack: 5, 13, 34, 89]) --> Alignment{Check Position & Slope Agreement}
    
    Alignment -- "3 of 3 Layers Agree" --> PhaseT[Phase: TRENDING\nBias = ±1]
    Alignment -- "2 of 3 Layers Agree" --> PhaseE[Phase: EMERGING\nBias = ±1]
    Alignment -- "< 2 Layers Agree" --> PhaseU[Phase: UNORDERED\nBias = 0]
    
    PhaseT --> AllowedT[Allow L1 Ribbon\nAllow L2 Ghost\nAllow L3 Shark]
    PhaseE --> AllowedE[Allow L1 Ribbon\nAllow L2 Ghost\n❌ BLOCK L3 Shark]
    PhaseU --> AllowedU[❌ BLOCK ALL TRADES]
    
    AllowedT --> Pullback{Detect Pullback Layer (1% Tolerance)}
    AllowedE --> Pullback
    
    Pullback -- "Touches EMA1/EMA2" --> L1[L1 Ribbon (Shallow)]
    Pullback -- "Touches EMA2/EMA3" --> L2[L2 Ghost (Medium)]
    Pullback -- "Touches EMA3/EMA4" --> L3[L3 Shark (Deep)]
    
    L1 --> Pass([Pass to Hard Gates])
    L2 --> Pass
    L3 --> Pass
    AllowedU --> Reject([Veto Signal: Return 0])
    
    classDef reject fill:#ffcccc,stroke:#cc0000,stroke-width:2px,color:#990000;
    classDef accept fill:#ccffcc,stroke:#009900,stroke-width:2px,color:#006600;
    class AllowedU,Reject reject;
    class Pass accept;

---

## Part 2: Indicator Voting Logic

### ADX (Trend Strength)
* **Static Mode:** ADX > fixed threshold (e.g., 25.0).
* **Dynamic Percentile Mode:** Adaptive threshold based on recent history.
    $Threshold = Percentile(Buffer_{ADX}, Lookback_{100}, Percentile_{50})$
* **Phase-Aware Mode:** Threshold scales by market phase (e.g., 12.0 for Unordered, 25.0 for Trending).

### VRC (Volatility Regime Classifier)
Filters out trades during low volatility regimes. Evaluates as a non-directional vote.
* **Check:** $ATR_{current} \geq Percentile(Buffer_{ATR}, 100, 33)$
* **Result:** VOLATILITY_LOW (reject) or VOLATILITY_NORMAL (pass). Cache updated every 4 hours.

### MACD (Momentum)
* **LONG:** Main > 0 AND Main > Signal.
* **SHORT:** Main < 0 AND Main < Signal.

### PSAR (Trend Direction)
* **LONG:** Close > PSAR dot.
* **SHORT:** Close < PSAR dot.
* **PSAR Flip Logic:** (If `Vote_AllowPsarFlip=true`), checks `bars_since_flip <= Vote_PsarFlipDelay` to ensure entry happens early in the flip cycle.

### Other Core Indicators
* **EMA1 (Price Position):** Price must be above (LONG) or below (SHORT) EMA1.
* **CCI:** LONG = CCI > 0; SHORT = CCI < 0.
* **RSI:** LONG = RSI < 70 (not overbought); SHORT = RSI > 30 (not oversold).
* **Stochastic:** LONG = K < 80; SHORT = K > 20.
* **ATR (Voting):** Non-directional vote ensuring volatility is between `ATR_VoteMinPips` and `ATR_VoteMaxPips`.

---

## Part 3: Extending the System (Plugin Architecture)

sequenceDiagram
    autonumber
    participant Cfg as SEA_Config.mqh
    participant Eng as SEA_SignalEngine.mqh
    participant Pipe as 9-Step Pipeline

    Note over Cfg: Add inputs (e.g., Inp_Use_Ichi)
    Note over Cfg: Map to EA_Settings struct
    Note over Cfg: Add to g_indicator_registry[]
    Cfg->>Eng: Passes GlobalSettings Struct via InitializeConfig()
    
    Note over Eng: Declare handle (h_ichi)
    Note over Eng: Init() -> Create iIchimoku handle
    Note over Eng: Write Check_Ichi(bias, shift) function
    
    Eng->>Pipe: Inject CAST_VOTE macro into Step 8
    Pipe-->>Eng: Returns Multiplicative Result (0 or 1)


SimpleEA uses a centralized indicator registry. To add a custom indicator (e.g., Ichimoku), you only modify `SEA_Config.mqh` and `SEA_SignalEngine.mqh`. No UI or preset files need changing.

### The 5-Component Plugin Pattern
1.  **Inputs (`SEA_Config.mqh`):** Add `Inp_Use_Ichi`, `Inp_W_Ichi`, and period variables.
2.  **Settings Struct (`SEA_Config.mqh`):** Add `Use_Ichi`, `W_Ichi`, and periods to `ST_Settings`. Map them in `InitializeConfig()`.
3.  **Handle (`SEA_SignalEngine.mqh`):** Declare `int h_ichi`. Create in `Init()` via `iIchimoku()`. Release in `Release()`.
4.  **Vote Function (`SEA_SignalEngine.mqh`):** ```c
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