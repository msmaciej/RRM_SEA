# SimpleEA (RRM_SEA)

SimpleEA is a professional-grade Expert Advisor for MetaTrader 5 implementing a comprehensive 9-step signal validation pipeline combining market bias analysis, multi-indicator voting, and risk-aware position management. 

**Environment Constraints:** macOS + Wine + MT5 + **MQL5 ONLY** (no C++, no templates, no lambdas).

---

## 🗺️ Canonical Documentation Map
The system architecture has been refactored into focused, authoritative files. Start here:

* **[Step 1: Signal & Indicator Engine](README_SEA_SIGNAL_REFERENCE.md)**
    * The 9-step TS (Trade Setup) multiplicative pipeline (`TS = Bias × Phase × Layer × Indicators`).
    * Indicator logic (ADX Dynamic, VRC Percentiles, MACD, PSAR, etc.).
    * Developer Guide: Centralized Indicator Registry & Plugin pattern.
* **[Step 2: Execution & Trade Logic](README_SEA_TRADE_LOGIC.md)**
    * The TE (Trade Entry) execution architecture at shift=0.
    * Exit Management (SL, TP, Breakeven, and Trailing).
    * Auto-scaling TF-based cushions and Adaptive Spread Limits.
* **[SEA Agents Bootstrapping](README_SEA_BOOTSTRAP.md)**
    * AI Agent Manifest and instructions for starting new chat tasks.

---

## ⚙️ Configuration Zones (The Architect Manual)

Inputs in `SEA_Config.mqh` are visually grouped in the MT5 dialog to distinguish operator controls from preset-controlled strategy variables.

### ZONE 1: Preset Selection
Selects the core strategy.
* `PRESET_CUSTOM`: All inputs respected; full user control.
* `PRESET_MA`: Replicates the MT5 Moving Average EA benchmark.
* `PRESET_RRM`: Phase-based layer detection system (The Production Standard).

### ZONE 2: User Controls (Policy A Gates)
**Always editable by the user, regardless of preset.**
* Operator Gates: Spread Limits (`MaxSpreadPips`).
* Time/Session Filter (`StartHour`, `EndHour`).
* News Filter & HTF Trend Filter.
* UI, Diagnostics, and Reporting output levels.

### ZONE 3A: Preset Info
Contains the strategy-critical variables (EMA periods, Indicator toggles, Exit modes). 
* If `PRESET_CUSTOM` is active, these inputs drive the EA. 
* If any other preset is active, these inputs are **ignored and overridden** by the hardcoded preset to guarantee systemic integrity.

### ZONE 3B & 3C: Overrides & Adaptives
* **Zone 3B (Admin Override):** Setting `Inp_AdminOverridePreset = true` allows advanced users to test variations of strict presets without modifying source code.
* **Zone 3C (Pair Limits):** Auto-detects pair types to apply dynamic spread limits.

---

## ⚖️ The Preset Policy (Model A) & Architecture Rules

To avoid misleading behavior and user confusion, presets are defined as **fully authoritative**.

1.  **Anti-Confusion Mapping:** When `PRESET_RRM` is active, it fully defines all strategy-critical settings. Strategy-related inputs in MT5 are ignored. The EA prints a clear initialization note, and the UI/Logs display the *effective* settings.
2.  **Two-Phase Signal Timing:**
    * **TS (Trade Setup):** Evaluated strictly on the closed candle (`shift=1`) via `GetDirection()`.
    * **TE (Trade Entry):** Evaluated strictly on the open tick (`shift=0`) via `EvaluateTE()`, checking real-time spread, time, and news limits. 
    * No signal evaluation occurs on forming bars. No trade execution occurs without a prior TS validation.
3.  **Strict Multiplicative Voting:** In RRM setups, `VOTE_MODE_ALL` is enforced. Adding indicators makes the system MORE restrictive, not less. ANY indicator returning 0 kills the signal.

---

## 📊 System Analysis & Reporting

SimpleEA automatically outputs comprehensive performance metrics directly to the `OnDeinit` log, segmented into three critical diagnostic areas:

1.  **Signal Efficiency:** Tracks total bars evaluated, TS conversion rate, and individual component pass/fail rates (e.g., "Bias=0: 56.9% rejection").
2.  **Trade Performance:** Win rate (Long vs Short), Profit Factor, Average Win/Loss, and Consecutive streaks.
3.  **Risk Analysis:** Maximum Absolute/Relative Drawdown, Recovery Factor, and Risk-Reward ratio profiling.

*Use the `Inp_DebugLevel` (Zone 2) to control per-tick log verbosity (DEBUG_SILENT, SUMMARY, INDICATORS, FULL).*