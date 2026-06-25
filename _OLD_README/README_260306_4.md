# RRM_SEA (SimpleEA)

RRM_Simple EA — macOS + Wine + MT5 + **MQL5 ONLY**  
(**no C++**, **no templates**, **no lambdas**, **no static locals**)

## Canonical documentation (current)
All current docs live in `Readme/`:

- `Readme/README_SYSTEM.md` — system architecture & full documentation
- `Readme/README_INDICATORS.md` — indicator and voting pipeline reference
- `Readme/README_EXTENDING.md` — developer guide: how to add custom indicators
- `Readme/README_SEA_RULES.md` — agent ownership, constraints, preset policy
- `Readme/README_SEA_BOOTSTRAP.md` — how to start a new chat and run tasks with SEA agents
- `Readme/README_SEA_AI-AGENTS.md` — SEA Agents v.03 prompts (roles/guardrails/output)

## Legacy / archive
Historical/obsolete documentation is stored in `Legacy/`.  
Do not use it unless explicitly required:

- `Legacy/README_LEGACY.md`

## Quick start (for a new task)
1. Read `Readme/README_SEA_BOOTSTRAP.md`
2. Follow `Readme/README_SEA_RULES.md`
3. Define the task and proceed via the SEA Architect → Specialized Agent workflow

## Python EA vs SimpleEA MQL5 Comparison

### Layer Detection Equivalence
SimpleEA's STRAT_LAYER_DETECTION replicates Python EA's TrSet pattern logic:

| Feature | Python EA (`rrm_f1_34_its_engine.py`) | SimpleEA MQL5 |
|---------|----------------------------------------|---------------|
| Shallow Pullback | "Ribbon" (EMA1/2) | LAYER_1_WEAK |
| Medium Pullback | "Ghost" (EMA2/3) | LAYER_2_MEDIUM |
| Deep Pullback | "Shark" (EMA3/4) | LAYER_3_STRONG |
| Tolerance | `_is_near()` 1% | `LayerTouchTolerance` 1% |
| Lookback | Multi-bar scan (`TSV_DPB_LOOKBACK`) | Single-bar check (shift=1) |

### Performance Differences
- **Python EA**: 55–60% win rate, 5–8 trades/day (M1 timeframe)
- **SimpleEA**: 35–40% win rate, 2–3 trades/day (same conditions)

**Root Causes:**
1. **Lookback difference**: Python EA scans last N bars for patterns (`TSV_DPB_LOOKBACK`); SimpleEA checks only current bar (shift=1)
2. **Additional filters**: SimpleEA PRESET_RRM includes 7 extra protection gates:
   - Phase confirmation delay (4 bars)
   - Recovery momentum requirement
   - Divergence validation (1.5 pips minimum)
   - HTF alignment (optional)
   - Pullback lookback (20 bars)
3. **Trade-off**: SimpleEA prioritizes quality over quantity (fewer trades, stricter entry rules)

**Tuning for Python EA Parity:**
To increase trade frequency closer to Python EA levels:
- Set `MinPhaseConfirmBars = 2` (faster phase detection)
- Set `Emerging_AllowWeakTrades = true` (allow L1 in EMERGING phase)
- Set `RequireRecoveryMomentum = false` (accept more pullback patterns)
- Consider implementing multi-bar lookback (future enhancement)

See `Readme/README_SYSTEM.md` STRAT_LAYER_DETECTION section for full details.