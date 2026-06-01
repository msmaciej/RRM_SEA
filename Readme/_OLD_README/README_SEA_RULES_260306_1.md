# SEA Rules (Authoritative)

This document defines the **operating rules** for maintaining and modifying SimpleEA using the SEA multi-agent workflow.

## 1) Global engineering constraints
- **MQL5 only** (no MQL4-style APIs/patterns).
- Platform constraints:
  - macOS + Wine + MT5 environment
- Language constraints:
  - ❌ no C++
  - ❌ no templates
  - ❌ no lambdas
  - ❌ no static locals
- File encoding:
  - `.mq5`, `.mqh`, `.json` must be saved as **UTF-16 LE with BOM (FF FE)** (per project conventions).
  - Markdown docs are UTF-8.

## 2) Core timing architecture (non-negotiable)

### TS (Trade Setup) Evaluation
- **shift=1 (closed candle):** Complete signal validation pipeline
- **Function**: `GetDirection()` in `SEA_SignalEngine.mqh`
- **Evaluates**: Pre-filters, bias, indicators, voting (VOTE_MODE_ALL in presets), RRM gates, HTF filters
- **When**: Every bar close
- **Output**: TS=1 (signal confirmed, arm TE) or TS=0 (no signal)

### TE (Trade Entry) Execution
- **shift=0 (new candle open):** Execution-moment validation only
- **Function**: `EvaluateTE()` in `SEA_SignalEngine.mqh`
- **Evaluates**: Spread, time window, news events (NO signal re-validation)
- **When**: First tick after TS=1 (if `g_ts_active == true`)
- **Output**: TE=1 (execute trade) or TE=0 (reject, clear TS)

### Flow
```
1. Bar N closes → TS evaluated at shift=1 → If TS=1, store signal
2. Bar N+1 opens → TE evaluated at shift=0 → If TE=1, execute trade
3. 1-bar delay ensures entry confirmation
4. If TE=0, system continues evaluating TS on subsequent bar closes
```

**No signal evaluation on forming bars. No trade entries without TS→TE validation.**

### Implementation Details (PR #53)
- Global state: `g_ts_active`, `g_ts_direction`, `g_ts_bar_time`
- TS uses `Vote_EvalShift` (default=1, forced in presets)
- All presets use `VOTE_MODE_ALL` (unanimous voting)
- PSAR flip-count validation when `Vote_AllowPsarFlip=true`

## 3) Preset policy (anti-confusion, Model A)
To avoid misleading behavior and user confusion, presets are defined as **fully authoritative**.

- If `InpPreset == PRESET_CUSTOM`:
  - Inputs define the strategy and all parameters.
- If `InpPreset != PRESET_CUSTOM`:
  - The preset **fully defines all strategy-critical settings** (Model A).
  - Strategy-related inputs are ignored.
  - EA must print a **clear note** at init that a preset is active and overrides strategy inputs.
  - The UI/Logs must show the **effective** (final) settings.

### Strategy-critical settings (must be preset-defined when a preset is active)
At minimum:
- EMA periods / bias roles
- BiasMode / AutoStrat selection
- VoteThreshold
- Enabled indicators / indicator modes
- Gates / filters (spread/ATR bounds, HTF filters, RRM gates)
- SL/TP multipliers and trailing mode/cushion parameters

### AdminOverride system (preset testing, for experienced users)
- `Inp_AdminOverridePreset = false` (default, Normal User Mode):
  - Preset is fully enforced. Only Policy A operator gates are user-controlled.
  - Protects users from accidentally breaking preset strategy-critical settings.
  - Status Panel shows "AdminOverride: OFF [Normal User Mode]".
- `Inp_AdminOverridePreset = true` (Admin User Mode):
  - Override inputs (prefixed `[Admin]` in MT5 Inputs) become active after preset defaults are applied.
  - Allows testing preset variations without editing `SEA_Presets.mqh` or recompiling.
  - Status Panel shows "AdminOverride: ACTIVE [Admin Mode - Testing]".
  - Tested configurations can be saved as `.set` files.
  - This does NOT change PRESET_CUSTOM behavior (all inputs already respected in CUSTOM mode).

## 4) Agent ownership model (file boundaries)
Each file has a single owner (agent). Changes must be routed accordingly.

- **SEA Architect**
  - Planning, routing, impact analysis
  - **Sole owner of documentation**:
    - `README.md`
    - `Readme/README_SYSTEM.md`
    - `Readme/README_INDICATORS.md`
    - and any SEA workflow docs under `Readme/`
  - Does NOT implement executable MQL5 logic

- **SEA Config**
  - Owns: `SEA_Config.mqh`
  - Owns: enums, `EA_Settings` struct, `input` declarations, `InitializeConfig()`

- **SEA Presets**
  - Owns: `SEA_Presets.mqh`
  - Owns: `ApplyPreset()` and preset definitions (Model A)

- **SEA SignalEngine**
  - Owns: `SEA_SignalEngine.mqh`
  - Owns: indicator handles + 9-step voting pipeline (shift=1)

- **SEA TradeExecutor**
  - Owns: `SEA_TradeExecutor.mqh`
  - Owns: sizing, entries, SL/TP, BE, trailing (shift=0)

- **SEA UI**
  - Owns: `SEA_UI.mqh`
  - Owns: chart panels/objects and cleanup

- **SEA Reporting**
  - Owns: `SEA_Reporting.mqh`
  - Owns: Strategy Tester CSV/logging and performance metrics

- **SEA Core**
  - Owns: main EA file (current production): `SimpleEA_v1-02-016d_05-9c_RRM.mq5`
  - Owns: includes, OnInit/OnTick/OnDeinit wiring, calling module functions
  - Must keep main file global scope clean

## 5) Workflow rules (how tasks are executed)
For any change:
1. SEA Architect produces a **Delegation Plan**:
   - file allowlist
   - acceptance criteria
   - prompts for specialized agents
2. Specialized agent modifies only its owned file(s).
3. Integrate and validate:
   - compile in MetaEditor
   - Strategy Tester sanity test
4. Update docs only when behavior/architecture changes.

## 6) Source of truth priority
- Code is source of truth.
- `Readme/` docs are authoritative documentation for humans + AI workflow.
- `Legacy/` is archive only.