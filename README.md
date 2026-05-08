# RRM_ORG Full Drop-In — Phase A + A.1 + B Combined

This directory contains **five fully-modified files** that replace the
corresponding files in your `RRM_SEA/` repo, plus a combined unified diff
for those who prefer patches over file replacement.

Build version: **103003** (was 103002).

## What's inside

| File | Original lines | Modified lines | Δ |
|---|---:|---:|---:|
| `SEA_Config.mqh` | 1855 | 1896 | +41 |
| `SEA_Presets.mqh` | 1799 | 1874 | +75 |
| `SEA_SignalEngine.mqh` | 5368 | 5576 | +208 |
| `SEA_TradeExecutor.mqh` | 1815 | 1926 | +111 |
| `SimpleEA_v1-03.mq5` | 1254 | 1263 | +9 |
| `RRM_ORG_full.patch` | — | 868 lines | combined diff |

## Two ways to apply

### Option A — file replacement (simplest)
```bash
cd RRM_SEA
cp /path/to/RRM_ORG_FullDropIn/SEA_Config.mqh        .
cp /path/to/RRM_ORG_FullDropIn/SEA_Presets.mqh        .
cp /path/to/RRM_ORG_FullDropIn/SEA_SignalEngine.mqh   .
cp /path/to/RRM_ORG_FullDropIn/SEA_TradeExecutor.mqh  .
cp /path/to/RRM_ORG_FullDropIn/SimpleEA_v1-03.mq5     .
```

### Option B — apply the combined patch
```bash
cd RRM_SEA
patch -p1 < /path/to/RRM_ORG_FullDropIn/RRM_ORG_full.patch
```
The patch was verified to apply cleanly to the unmodified repo and to
reverse cleanly back to the original (bidirectional, safe to roll back
with `patch -R`).

## What's been changed (summary)

### Phase A — TS-quality lift (in `SEA_Presets.mqh`)
All 11 changes scoped to `PRESET_RRM_ORG`:
- `Ind_Dpi_Enabled = true` (was false; activates the dead-code DPI decel filter)
- `EmaFanFilterEnabled = true` with TF-scaled threshold (25→180 pips by TF)
- `MinPhaseConfirmBars` TF-scaled (1/2/3 by TF; was 0)
- `RequireRecoveryMomentum` TF-conditional (fixes the duplicate-write bug at lines 1295/1309)
- `UseHTF = true` with auto HTF period selection
- `RRM_EnableDrawdownProtection = true` (was respecting input default)
- JPY pairs get 1.3× scaling on `Gate_Recovery` and `Gate_EmaDiv`

### Phase A.1 — Per-gate reporting (in `SEA_SignalEngine.mqh`, `SEA_TradeExecutor.mqh`, `SimpleEA_v1-03.mq5`)
- 14 new counter pairs in `SRejectionStats` (7 TS-side + 7 TE-side, but TE-side handled separately)
- 2 increment lines at existing `EMA_OVEREXT` and `DPI_DECEL` reject sites
- 2 new pre-filters: `PHASE_AGE` (rejects when phase too young) and `HTF_BLOCKED` (rejects when HTF disagrees with bias)
- New `GetHtfBias()` helper using existing `h_htf_ema` handle
- New `AddTeStats()` public method on CSignalEngine to bridge TE-side counters
- New "1b. PRE-FILTER QUALITY GATES" report section in `PrintEnhancedStatistics`
- 7 new entries in the sorted `PrintRejectionStatistics` reasons array (was [27], now [34])
- 6 TE counter fields + 6 getters on `CTradeExecutor`
- 1-line bridge call in `OrchestrateDeinit` so TE-side counters appear in the report

### Phase B — Operator-toggleable inputs (in `SEA_Config.mqh`, `SEA_Presets.mqh`, `SEA_TradeExecutor.mqh`)
- 25 new `Inp_RRM_ORG_*` inputs in `SEA_Config.mqh` (TF-scaled fan thresholds, phase-age bars, HTF toggle, TE-side gates)
- 3 new `ST_Settings` fields: `TE_RecheckBarClose`, `TE_OpenDelaySeconds`, `TE_SpreadMedianTicks`
- 3 new TE-side guards inside `EvaluateTE()`:
  - **Open-tick delay**: defers TE for N seconds at new bar (M5: 10s, M30: 5s, H1+: 0s)
  - **Bar-close re-check**: skips TE if bid drifted >2 pips against bias since shift=1 close
  - **Median spread**: replaces instant spread with median of last N ticks in `EvaluateF`
- All Phase A hardcoded values in `PRESET_RRM_ORG` block converted to input-driven assignments — defaults preserve Phase A behavior, but every gate is now tunable from the MT5 inputs panel

## Compile and verify

After applying:
```bash
# 1. Run MetaEditor compile
./compile_check.sh --syntax-only

# Expected: 0 errors, 0 (or very few) warnings

# 2. Confirm build version bumped
grep "SEA_BUILD_NUM" RRM_SEA/SimpleEA_v1-03.mq5
# Expected: #define SEA_BUILD_NUM 103003

# 3. Run a backtest with Inp_PresetMode = PRESET_RRM_ORG
#    Look for the new "1b. PRE-FILTER QUALITY GATES" section in OnDeinit log
```

## Rollback

If you need to roll back:
```bash
cd RRM_SEA
patch -R -p1 < /path/to/RRM_ORG_full.patch
```
This reverts all five files to their original state. Tested clean.

## What was NOT changed

- `SEA_UI.mqh` — unchanged. The new "1b" section uses the existing `PrintGateStat` helper, no UI module changes needed.
- `SEA_Reporting.mqh` — unchanged. The combined Phase A.1/B output still flows through the existing reporting module.
- All other presets (`PRESET_CUSTOM`, `PRESET_MA`, `PRESET_RRM`, `PRESET_TEST`, `PRESET_FPM`) — byte-identical. Only `PRESET_RRM_ORG` was modified.
- Stale-build tokens for UI and Reporting — kept at 103002 since those modules weren't touched. Only `SEA_MOD_SIGNALENGINE_*` and `SEA_MOD_TRADEEXEC_*` bumped to 103003.

## Sanity checks performed

- ✅ Combined patch applies cleanly to the unmodified repo
- ✅ Combined patch reverses cleanly back to original (bidirectional)
- ✅ All Phase A/A.1/B markers present in correct files
- ✅ `Inp_RRM_ORG_*` references inside `PRESET_RRM_ORG` resolve to declared inputs (35 distinct refs, all declared)
- ✅ Line endings preserved (CRLF for Config/Presets/SignalEngine, LF for TradeExecutor/SimpleEA)
- ✅ Build tokens consistently bumped 103002 → 103003 in the modules that changed

The patch was NOT compile-tested in MetaEditor in this environment (no
Wine/MT5 available). Run `./compile_check.sh --syntax-only` on your
macOS+Wine+MT5 setup to validate.
