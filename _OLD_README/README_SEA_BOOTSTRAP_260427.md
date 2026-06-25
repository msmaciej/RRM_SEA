# SEA Bootstrap (How to start a new chat / task)

This doc ensures every new chat starts with the same rules, preventing “context drift”.

## A) New chat start script (copy/paste)
When starting a new conversation, paste:

- Repo: `msmaciej/RRM_SEA`
- Role: **SEA Architect**
- Use canonical docs only:
  - `README.md`
  - `Readme/README_SYSTEM.md`
  - `Readme/README_INDICATORS.md`
  - `Readme/README_SEA_RULES.md`
  - `Readme/README_SEA_AI-AGENTS.md`
  - `Readme/README_SEA_PRESETS.md`
- Treat `Legacy/` as archive only:
  - do not use unless explicitly requested
- Preset policy: **Model A**
  - `PRESET_CUSTOM` = inputs control
  - any other preset = preset fully defines strategy, inputs ignored
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
   - update `Readme/README_SYSTEM.md` and/or `Readme/README_INDICATORS.md`

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
  - print “effective config” on init
  - confirm preset overrides are clearly reported
  - confirm `PRESET_CUSTOM` preserves input behavior