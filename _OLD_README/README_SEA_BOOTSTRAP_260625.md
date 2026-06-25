# SEA Bootstrap (How to start a new chat / task)

This doc ensures every new chat starts with the same rules, preventing "context drift".

## A) New chat start script (copy/paste)
When starting a new conversation, paste:

- Repo: `msmaciej/RRM_SEA`
- Role: **SEA Architect**
- Use canonical docs only:
  - `README.md`
  - `Readme/README_SEA_SYSTEM.md`
  - `Readme/README_SEA_SIGNAL_REFERENCE.md`
  - `Readme/README_SEA_TRADE_LOGIC.md`
  - `Readme/README_SEA_AI-AGENTS.md`
  - `Readme/README_SEA_PRESETS.md`
  - `Readme/README_SEA_VETO_REFERENCE.md`
- Treat `_OLD_*/` directories (`_OLD_MQH/`, `_OLD_DPI_VPRR/`, `Readme/_OLD_README/`) as archive only:
  - do not use unless explicitly requested
- Preset policy: **Model A**
  - Available presets: `PRESET_MA`, `PRESET_FPM`, `PRESET_TOPINVESTOR`, `PRESET_RRM_ORG`
  - Any preset fully defines strategy-critical fields; user controls Policy-A gates (spread/time/news/risk) plus per-preset overrides (`Inp_RRM_ORG_*`, `Inp_FPM_*`, etc.) and globals (`Inp_Global_*`)
  - Removed in 2026-06 refactor: `PRESET_CUSTOM`, `PRESET_RRM`, `PRESET_TEST`
- Architecture constraints:
  - shift=1 evaluation only
  - shift=0 execution only
  - MQL5 only; no lambdas/static locals/etc.

Then state the task in 1–3 sentences.

## B) What the SEA Architect must do (process flow)
1. **Restate the task** and define acceptance criteria.
2. **Identify impacted files** (strict allowlist).
3. Produce a **Delegation Plan**:
   - One section per agent/file owner
   - Each section contains a copy/paste prompt for that agent
4. Execute in iterations:
   - Apply changes
   - Compile
   - Backtest/sanity test
   - Adjust
5. If architecture/behavior changed:
   - update `Readme/README_SEA_SYSTEM.md` and/or `Readme/README_SEA_SIGNAL_REFERENCE.md`

## C) Standard “Delegation Plan” template
SEA Architect output should follow this template:

1) Summary
- Goal:
- Non-goals:
- Acceptance criteria:
- File allowlist:

2) Delegation Plan
- SEA Config (SEA_Config.mqh)
  - Prompt: "..."
- SEA Presets (SEA_Presets.mqh)
  - Prompt: "..."
- SEA Core (SimpleEA_*.mq5)
  - Prompt: "..."
- SEA SignalEngine / TradeExecutor / UI / Reporting (if needed)
  - Prompt: "..."

3) Validation checklist
- Compile:
- Strategy Tester:
- Logs to verify:
- Expected behavior changes:

## D) Testing expectations (minimal)
- Always compile after changes.
- For config/preset refactors:
  - print "effective config" on init
  - confirm preset overrides are clearly reported
  - confirm `Inp_Global_*` defaults and per-preset (`Inp_RRM_ORG_*`, `Inp_FPM_*`, ...) overrides agree with the `ApplyPreset` block