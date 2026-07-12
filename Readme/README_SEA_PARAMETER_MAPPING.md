# PARAMETER_MAPPING

> ⚠️ **Breaking change:** existing MT5 `.set` files using legacy input names must be migrated to the new names below.

## Old → New parameter names

| Old name | New name | Scope | Renamed + reordered |
|---|---|---|---|
| `InpEma1Period` | `Inp_CUSTOM_Ema1Period` | CUSTOM | Yes |
| `InpEma2Period` | `Inp_CUSTOM_Ema2Period` | CUSTOM | Yes |
| `InpEma3Period` | `Inp_CUSTOM_Ema3Period` | CUSTOM | Yes |
| `InpEma4Period` | `Inp_CUSTOM_Ema4Period` | CUSTOM | Yes |
| `Inp_AutoStrat` | `Inp_CUSTOM_AutoStrat` | CUSTOM | Yes |
| `Inp_BEThresholdPips` | `Inp_CUSTOM_BEThresholdPips` | CUSTOM | Yes |
| `Inp_BE_Mode` | `Inp_CUSTOM_BE_Mode` | CUSTOM | Yes |
| `Inp_BarClose_DefaultEMA` | `Inp_CUSTOM_BarClose_DefaultEMA` | CUSTOM | Yes |
| `Inp_BarClose_Enabled` | `Inp_CUSTOM_BarClose_Enabled` | CUSTOM | Yes |
| `Inp_BarClose_Mode` | `Inp_CUSTOM_BarClose_Mode` | CUSTOM | Yes |
| `Inp_BiasEnabled` | `Inp_CUSTOM_BiasEnabled` | CUSTOM | Yes |
| `Inp_BiasFastID` | `Inp_CUSTOM_BiasFastID` | CUSTOM | Yes |
| `Inp_BiasMode` | `Inp_CUSTOM_BiasMode` | CUSTOM | Yes |
| `Inp_BiasSlowID` | `Inp_CUSTOM_BiasSlowID` | CUSTOM | Yes |
| `Inp_CI_Period` | `Inp_CUSTOM_Ind_CI_Period` | CUSTOM | Yes |
| `Inp_CI_RangingThreshold` | `Inp_CUSTOM_Ind_CI_RangingThreshold` | CUSTOM | Yes |
| `Inp_CloseOnReverse` | `Inp_CUSTOM_CloseOnReverse` | CUSTOM | Yes |
| `Inp_ExitProfile` | `Inp_CUSTOM_ExitProfile` | CUSTOM | Yes |
| `Inp_FixedTPPips` | `Inp_CUSTOM_FixedTPPips` | CUSTOM | Yes |
| `Inp_FractalHighColor` | `Inp_CUSTOM_FractalHighColor` | CUSTOM | Yes |
| `Inp_FractalLowColor` | `Inp_CUSTOM_FractalLowColor` | CUSTOM | Yes |
| `Inp_FractalMarkerSize` | `Inp_CUSTOM_FractalMarkerSize` | CUSTOM | Yes |
| `Inp_FractalPeriod` | `Inp_CUSTOM_FractalPeriod` | CUSTOM | Yes |
| `Inp_Ind_` | `Inp_CUSTOM_Ind_` | CUSTOM | Yes |
| `Inp_LayerTolerance` | `Inp_CUSTOM_LayerTolerance` | CUSTOM | Yes |
| `Inp_MaHorShift` | `Inp_CUSTOM_MaHorShift` | CUSTOM | Yes |
| `Inp_MaType` | `Inp_CUSTOM_MaType` | CUSTOM | Yes |
| `Inp_MaVerShift` | `Inp_CUSTOM_MaVerShift` | CUSTOM | Yes |
| `Inp_MacdFreshBars` | `Inp_CUSTOM_Ind_Macd_FreshBars` | CUSTOM | Yes |
| `Inp_MacdRequireDivergence` | `Inp_CUSTOM_Ind_Macd_RequireDivergence` | CUSTOM | Yes |
| `Inp_MacdRequireHook` | `Inp_CUSTOM_Ind_Macd_RequireHook` | CUSTOM | Yes |
| `Inp_MacdRequireSlope` | `Inp_CUSTOM_Ind_Macd_RequireSlope` | CUSTOM | Yes |
| `Inp_MacdSlopeMin` | `Inp_CUSTOM_Ind_Macd_SlopeMin` | CUSTOM | Yes |
| `Inp_MacdVoteMode` | `Inp_CUSTOM_Ind_Macd_Mode` | CUSTOM | Yes |
| `Inp_ManualSide` | `Inp_CUSTOM_ManualSide` | CUSTOM | Yes |
| `Inp_MarkerLookback` | `Inp_CUSTOM_MarkerLookback` | CUSTOM | Yes |
| `Inp_MinBarsAfterClose` | `Inp_CUSTOM_MinBarsAfterClose` | CUSTOM | Yes |
| `Inp_MinBarsAfterWeekendGap` | `Inp_CUSTOM_MinBarsAfterWeekendGap` | CUSTOM | Yes |
| `Inp_P_MacdFast` | `Inp_CUSTOM_Ind_Macd_Fast` | CUSTOM | Yes |
| `Inp_P_MacdSig` | `Inp_CUSTOM_Ind_Macd_Sig` | CUSTOM | Yes |
| `Inp_P_MacdSlow` | `Inp_CUSTOM_Ind_Macd_Slow` | CUSTOM | Yes |
| `Inp_RRM_EnableInCustom` | `Inp_CUSTOM_RRM_EnableInCustom` | CUSTOM | Yes |
| `Inp_SLMode` | `Inp_CUSTOM_SLMode` | CUSTOM | Yes |
| `Inp_SLPercent` | `Inp_CUSTOM_SLPercent` | CUSTOM | Yes |
| `Inp_SL_FixedPips` | `Inp_CUSTOM_SL_FixedPips` | CUSTOM | Yes |
| `Inp_SL_MinPips` | `Inp_CUSTOM_SL_MinPips` | CUSTOM | Yes |
| `Inp_SL_WidenToMinimum` | `Inp_CUSTOM_SL_WidenToMinimum` | CUSTOM | Yes |
| `Inp_ShowFractalMarkers` | `Inp_CUSTOM_ShowFractalMarkers` | CUSTOM | Yes |
| `Inp_ShowMarkerLabels` | `Inp_CUSTOM_ShowMarkerLabels` | CUSTOM | Yes |
| `Inp_ShowSwingMarkers` | `Inp_CUSTOM_ShowSwingMarkers` | CUSTOM | Yes |
| `Inp_SwingHighColor` | `Inp_CUSTOM_SwingHighColor` | CUSTOM | Yes |
| `Inp_SwingLookback` | `Inp_CUSTOM_SwingLookback` | CUSTOM | Yes |
| `Inp_SwingLowColor` | `Inp_CUSTOM_SwingLowColor` | CUSTOM | Yes |
| `Inp_SwingMarkerSize` | `Inp_CUSTOM_SwingMarkerSize` | CUSTOM | Yes |
| `Inp_TPFractalOffset` | `Inp_CUSTOM_TPFractalOffset` | CUSTOM | Yes |
| `Inp_TPMode` | `Inp_CUSTOM_TPMode` | CUSTOM | Yes |
| `Inp_TP_Enabled` | `Inp_CUSTOM_TP_Enabled` | CUSTOM | Yes |
| `Inp_TrailDistancePips` | `Inp_CUSTOM_TrailDistancePips` | CUSTOM | Yes |
| `Inp_TrailLockProfit` | `Inp_CUSTOM_TrailLockProfit` | CUSTOM | Yes |
| `Inp_TrailMode` | `Inp_CUSTOM_TrailMode` | CUSTOM | Yes |
| `Inp_TrailProfitPercent` | `Inp_CUSTOM_TrailProfitPercent` | CUSTOM | Yes |
| `Inp_TrailStepPips` | `Inp_CUSTOM_TrailStepPips` | CUSTOM | Yes |
| `Inp_TrailTrigger` | `Inp_CUSTOM_TrailTrigger` | CUSTOM | Yes |
| `Inp_VoteMode_All` | `Inp_CUSTOM_VoteMode_All` | CUSTOM | Yes |
| `Inp_Vote_PsarFlipDelay` | `Inp_CUSTOM_Ind_PsarFlipDelay` | CUSTOM | Yes |
| `Inp_DebugEvalAt` | `Inp_Debug_EvalAt` | Debug | Yes |
| `Inp_DebugEvalFrom` | `Inp_Debug_EvalFrom` | Debug | Yes |
| `Inp_DebugEvalMode` | `Inp_Debug_EvalMode` | Debug | Yes |
| `Inp_DebugEvalTo` | `Inp_Debug_EvalTo` | Debug | Yes |
| `Inp_DebugFlow` | `Inp_Debug_Flow` | Debug | Yes |
| `Inp_DebugLevel` | `Inp_Debug_Level` | Debug | Yes |
| `Inp_ExportCSV` | `Inp_Debug_ExportCSV` | Debug | Yes |
| `Inp_ExportUseCommonFiles` | `Inp_Debug_ExportUseCommonFiles` | Debug | Yes |
| `Inp_PrintEffectiveConfig` | `Inp_Debug_PrintEffectiveConfig` | Debug | Yes |
| `Inp_Stats_FullEvaluation` | `Inp_Debug_Stats_FullEvaluation` | Debug | Yes |
| `Inp_Stats_TrackPasses` | `Inp_Debug_Stats_TrackPasses` | Debug | Yes |
| `Inp_Stats_TrackRejections` | `Inp_Debug_Stats_TrackRejections` | Debug | Yes |
| `Inp_EndHour` | `Inp_VETO_EndHr` | Filters | Yes |
| `Inp_HtfEmaPeriod` | `Inp_Filter_HtfEmaPeriod` | Filters | Yes |
| `Inp_HtfPeriod` | `Inp_Filter_HtfPeriod` | Filters | Yes |
| `Inp_MaxSpreadPips` | `Inp_VETO_MaxSpread` | Filters | Yes |
| `Inp_MaxSpreadRetryBars` | `Inp_VETO_MaxSpreadRetryBars` | Filters | Yes |
| `Inp_NewsFile` | `Inp_VETO_NewsFile` | Filters | Yes |
| `Inp_NewsPost` | `Inp_VETO_NewsPostMinutes` | Filters | Yes |
| `Inp_NewsPre` | `Inp_VETO_NewsPreMinutes` | Filters | Yes |
| `Inp_StartHour` | `Inp_VETO_StartHr` | Filters | Yes |
| `Inp_UseHTF` | `Inp_Filter_UseHTF` | Filters | Yes |
| `Inp_UseNews` | `Inp_VETO_UseNews` | Filters | Yes |
| `Inp_UseSpread` | `Inp_VETO_UseSpread` | Filters | Yes |
| `Inp_UseTime` | `Inp_VETO_UseTime` | Filters | Yes |
| `InpPreset` | `Inp_Global_Preset` | Global | Yes |
| `Inp_MagicNum` | `Inp_Global_MagicNum` | Global | Yes |
| `Inp_DpiDecelFilterEnabled` | `Inp_RRM_DpiDecelFilterEnabled` | RRM Preset | Yes |
| `Inp_EmaFanFilterEnabled` | `Inp_RRM_EmaFanFilterEnabled` | RRM Preset | Yes |
| `Inp_EmaFanMaxTotalPips` | `Inp_RRM_EmaFanMaxTotalPips` | RRM Preset | Yes |
| `Inp_LayerAllowReversalPullback` | `Inp_RRM_LayerAllowReversalPullback` | RRM Preset | Yes |
| `Inp_LayerBaselineLookback` | `Inp_RRM_LayerBaselineLookback` | RRM Preset | Yes |
| `Inp_LayerFlatRatio` | `Inp_RRM_LayerFlatRatio` | RRM Preset | Yes |
| `Inp_LayerPullbackEnabled` | `Inp_RRM_LayerPullbackEnabled` | RRM Preset | Yes |
| `Inp_LayerRecoveryRatio` | `Inp_RRM_LayerRecoveryRatio` | RRM Preset | Yes |
| `Inp_PSAR_TrailCushionMode` | `Inp_RRM_PSAR_TrailCushionMode` | RRM Preset | Yes |
| `Inp_PSAR_TrailDelay` | `Inp_RRM_PSAR_TrailDelay` | RRM Preset | Yes |
| `Inp_DPI_BlockOnDeceleration` | `Inp_RRM_ORG_DPI_BlockOnDeceleration` | RRM_ORG Preset | Yes |
| `Inp_DPI_ExitOnHistDisappear` | `Inp_RRM_ORG_DPI_ExitOnHistDisappear` | RRM_ORG Preset | Yes |
| `Inp_DPI_ExitThreshold` | `Inp_RRM_ORG_DPI_ExitThreshold` | RRM_ORG Preset | Yes |
| `Inp_DPI_HistDecelLookback` | `Inp_RRM_ORG_DPI_HistDecelLookback` | RRM_ORG Preset | Yes |
| `Inp_DPI_HistMomentumThreshold` | `Inp_RRM_ORG_DPI_HistMomentumThreshold` | RRM_ORG Preset | Yes |
| `Inp_DPI_HistTrackingEnabled` | `Inp_RRM_ORG_DPI_HistTrackingEnabled` | RRM_ORG Preset | Yes |
| `Inp_Ind_Dpi_Enabled` | `Inp_RRM_ORG_Ind_Dpi_Enabled` | RRM_ORG Preset | Yes |
| `Inp_Ind_Dpi_Weight` | `Inp_RRM_ORG_Ind_Dpi_Weight` | RRM_ORG Preset | Yes |
| `Inp_EmergencyMarginLevel` | `Inp_RM_EmergencyMarginLevel` | Risk Management | Yes |
| `Inp_MarginAdj_Crypto` | `Inp_RM_MarginAdj_Crypto` | Risk Management | Yes |
| `Inp_MarginAdj_Exotic` | `Inp_RM_MarginAdj_Exotic` | Risk Management | Yes |
| `Inp_MarginAdj_Gold` | `Inp_RM_MarginAdj_Gold` | Risk Management | Yes |
| `Inp_MarginAdj_JPY` | `Inp_RM_MarginAdj_JPY` | Risk Management | Yes |
| `Inp_MarginUsageLimit` | `Inp_RM_MarginUsageLimit` | Risk Management | Yes |
| `Inp_MaxOpenTrades` | `Inp_RM_MaxOpenTrades` | Risk Management | Yes |
| `Inp_MaxTotalRisk` | `Inp_RM_MaxTotalRisk` | Risk Management | Yes |
| `Inp_MinMarginLevel` | `Inp_RM_MinMarginLevel` | Risk Management | Yes |
| `Inp_Override_BE_Cushion` | `Inp_RM_Override_BE_Cushion` | Risk Management | Yes |
| `Inp_Override_SL_Cushion` | `Inp_RM_Override_SL_Cushion` | Risk Management | Yes |
| `Inp_Override_Trail_Cushion` | `Inp_RM_Override_Trail_Cushion` | Risk Management | Yes |
| `Inp_UseMarginAdjustment` | `Inp_RM_UseMarginAdjustment` | Risk Management | Yes |
| `Inp_DrawEntryLines` | `Inp_UI_DrawEntryLines` | UI | Yes |
| `Inp_DrawTradeLines` | `Inp_UI_DrawTradeLines` | UI | Yes |

## Notes on ordering changes

- Input groups were normalized to this hierarchy where applicable: **bool Enable/Use → enum Mode → int → double**.
- Ordering updates were applied across Global, RM, Filters, UI, Debug, MA, FPM, RRM, RRM_ORG, CUSTOM and indicator sub-groups.

## Migration guide

1. Open your existing `.set` file and rename legacy keys using the table above.
2. Re-save presets/templates from MT5 so future exports use the new canonical names.
3. Re-check CUSTOM and preset-specific blocks (RRM/FPM/RRM_ORG) because both naming and ordering were normalized.

---

## PRESET_RRM_ORG Exit Settings Migration (v1.04 → v1.05)

### Problem in v1.04

PRESET_RRM_ORG used `Inp_CUSTOM_*` inputs for exit settings, causing:
- Namespace confusion (mix of RRM_ORG and CUSTOM inputs)
- RR ratio effectively hardcoded via `Inp_CUSTOM_RRRatio` default (2.0), not via an `Inp_RRM_ORG_*` input
- Unclear where to configure RRM_ORG exits

### Solution in v1.05

Complete `Inp_RRM_ORG_*` namespace for all exit settings.

### Migration Table

| Old Input (v1.04) | New Input (v1.05) | Default Value |
|-------------------|-------------------|---------------|
| `Inp_CUSTOM_SLMode` | `Inp_RRM_ORG_SLMode` | `SL_MODE_PSAR_DOT` |
| `Inp_CUSTOM_SwingLookback` | `Inp_RRM_ORG_SwingLookback` | `20` |
| `Inp_CUSTOM_TPMode` | `Inp_RRM_ORG_TPMode` | `TP_MODE_RR` |
| `Inp_CUSTOM_RRRatio` | `Inp_RRM_ORG_RRRatio` | `2.0` (now user-configurable!) |
| `Inp_CUSTOM_TrailMode` | `Inp_RRM_ORG_TrailMode` | `TRAIL_PSAR` |
| `Inp_CUSTOM_BE_Mode` | `Inp_RRM_ORG_BE_Mode` | `BE_MODE_R_MULTIPLE` |

### Action Required

**If using existing `.set` files with PRESET_RRM_ORG**:
1. Open your `.set` file in a text editor
2. Replace `Inp_CUSTOM_SLMode`, `Inp_CUSTOM_SwingLookback`, `Inp_CUSTOM_TPMode`, `Inp_CUSTOM_RRRatio`, `Inp_CUSTOM_TrailMode`, `Inp_CUSTOM_BE_Mode` with the corresponding `Inp_RRM_ORG_*` keys listed in the table above
3. OR: Reconfigure via MT5 inputs panel (recommended)

**If configuring fresh**:
- All RRM_ORG settings are now grouped under dedicated "📐 RRM_ORG: (EXIT)" input groups
- No more searching through CUSTOM zone inputs

### Example: Changing RR Ratio

**Before (v1.04)** ❌:
```
User sets: Inp_CUSTOM_RRRatio = 1.0  (but still uses CUSTOM namespace — confusing!)
```

**After (v1.05)** ✅:
```
User sets: Inp_RRM_ORG_RRRatio = 1.0
Result: Uses RR = 1.0 (correct namespace, respects user input)
```

---

## 2026-06 Refactor: Inp_CUSTOM_* → Inp_Global_* (CUSTOM preset removed)

### Background

`PRESET_CUSTOM` was removed as part of the 2026-06 refactor (`SEA_Config.mqh` STEP4 changelog comment). It was architecturally a misnomer — its `Inp_CUSTOM_*` inputs only served as the seed defaults that other presets read from, not as a real user-control surface.

### Migration

`Inp_CUSTOM_*` inputs that represented **cross-preset globals** (shared by every preset) were renamed to `Inp_Global_*`. Inputs that were truly per-preset moved to per-preset blocks (`Inp_RRM_ORG_*`, `Inp_FPM_*`, `Inp_TI_*`, `Inp_MA_*`).

The complete current inputs file shows **64 `Inp_Global_*`** declarations (corrected 2026-07 audit —
previously misstated as 138 here; one further `Inp_Global_*` was removed as a proven-dead input in
the same audit, see "Input Surface Audit" below) and zero active `Inp_CUSTOM_*` input declarations.
Surviving `Inp_CUSTOM_*` strings in the source are now only changelog markers in comments.

### Categories of the rename

| Old `Inp_CUSTOM_*` purpose | Where it moved | Example |
|---|---|---|
| Cross-preset filter/safety toggles | `Inp_Global_*` | `Inp_CUSTOM_VETO_*` → `Inp_Global_VETO_*` |
| F sub-filter toggles | `Inp_Global_F_*` | `Inp_CUSTOM_EmaFanFilter` → `Inp_Global_F_EmaFanFilterEnabled` |
| Per-preset RRM_ORG exits | `Inp_RRM_ORG_*` | `Inp_CUSTOM_RRRatio` → `Inp_RRM_ORG_RRRatio` |
| Per-preset RRM_ORG indicator gates | `Inp_RRM_ORG_*` | `Inp_CUSTOM_ClimaxGuard_Enabled` → `Inp_Global_F_ClimaxGuard_Enabled` (climaxguard is global) |
| Indicator periods/thresholds | `Inp_Global_Ind_*` or `Inp_RRM_ORG_Ind_*` | depends on whether toggle is shared or per-preset |

### Action Required for existing `.set` files

If your `.set` file was last saved before the 2026-06 refactor:

1. Open the `.set` in a text editor.
2. Replace all `Inp_CUSTOM_*` keys with their `Inp_Global_*` / `Inp_RRM_ORG_*` / `Inp_FPM_*` / `Inp_TI_*` / `Inp_MA_*` equivalents. The rules of thumb above cover the common cases; for the full mapping consult `SEA_Inputs.mqh` and grep for the old name in `SEA_Config.mqh` to see which preset-namespace adopted it.
3. Alternatively, reconfigure via the MT5 inputs panel — the input groups are reorganised so that `Inp_Global_*` settings are clearly separated from per-preset blocks.

### Removed-preset cleanup

If your `.set` references `Inp_RRM_*` (the now-removed RRM variant) or `Inp_TEST_*` (the dev scaffold), those settings have no effect and can be deleted. The post-refactor preset list is `PRESET_MA`, `PRESET_FPM`, `PRESET_TOPINVESTOR`, `PRESET_RRM_ORG`.


---

## S2 + A21 + i_suppressed Additions (2026-07)

### New inputs — PRESET_RRM_ORG Layer Pullback

All new; no migration required. Defaults are active out of the box.

| Input | Default | Description |
|-------|---------|-------------|
| `Inp_RRM_ORG_LayerPriceTouchEnabled` | `false` | **Deprecated (Path 2, 2026-07).** The S2 price-zone-touch DETECTED gate was a PRICE test; the layer model is now pure position+slope, so this is off by default and the gate code was removed from `UpdateSingleLayerPullback`. Retained for back-compat; leaving it `true` has no effect. |
| `Inp_RRM_ORG_MinPBBars_W` | `2` | **A21** — LayerW (EMA1/2) must stay in DETECTED for at least this many bars before RECOVERED. A pullback cannot complete in one bar. Set to 0 to disable. |
| `Inp_RRM_ORG_MinPBBars_M` | `2` | **A21** — same gate for LayerM (EMA2/3). |
| `Inp_RRM_ORG_MinPBBars_S` | `2` | **A21** — same gate for LayerS (EMA3/4). Path 2: 2/2/2 across all layers/timeframes. |

### New config fields — ST_Settings

| Field | Type | Description |
|-------|------|-------------|
| `LayerPriceTouchEnabled` | `bool` | (deprecated/no-op) S2 price-zone gate — off under the slope model |
| `LayerMinPullbackBars_W` | `int` | A21 minimum bars in DETECTED for W layer |
| `LayerMinPullbackBars_M` | `int` | A21 minimum bars in DETECTED for M layer |
| `LayerMinPullbackBars_S` | `int` | A21 minimum bars in DETECTED for S layer |

### Path 2 inputs (2026-07) — slope-based pullback-recovery

| Input | Default | Description |
|-------|---------|-------------|
| `Inp_RRM_ORG_UNO_ToleranceBars` | `2` | Consecutive UNO bars tolerated before layer states wipe. A transient UNO flicker that resolves back to the SAME direction within this many bars PRESERVES DETECTED/RECOVERED. `0` = strict (reset on the first UNO bar). Plumbed to the scanner via ConfigSync. |
| `Inp_RRM_ORG_LayerPullbackWindow_W` | `21` | LayerW pullback **observation window** (bars) — distinct from the baseline slope lookback (13/21/34). Bounds how long a RECOVERED layer stays entry-eligible (the recovery max-age default). `0` = use the global. |
| `Inp_RRM_ORG_LayerPullbackWindow_M` | `34` | LayerM observation window. |
| `Inp_RRM_ORG_LayerPullbackWindow_S` | `55` | LayerS observation window. |
| `Inp_RRM_ORG_LayerPullbackWindow` | `0` | Global observation-window override (`0` = use per-layer values). |
| `Inp_RRM_ORG_LayerRecoveryMaxAgeEnabled` | `true` | When on, a RECOVERED layer that has waited longer than its observation window to fire expires to NONE (prevents stale chase-entries). Relapse (counter-`bias_dir` reversal) and TS=1 consumption still take precedence. |

Corresponding `ST_Settings` fields: `UNO_ToleranceBars`, `LayerPullbackWindow_W/M/S`, `LayerPullbackWindow`, `LayerRecoveryMaxAgeEnabled`. All synced EA→scanner via `SEA_ConfigSync`.

### New telemetry field — ST_SignalTelemetry

| Field | Type | Set when | UI effect |
|-------|------|----------|-----------|
| `i_suppressed` | `bool` | `m_diag_last_reason == "L_NONE_ALIGNED"` — no layer structurally aligned, I factor never evaluated | Cockpit shows `I[?]` and `--/N [L-blocked]` in VOTE display instead of misleading `I[-]` |

---

## Input Surface Audit (2026-07, F-AUDIT)

Every `Inp_*` declaration in `SEA_Inputs.mqh` (457 at audit time, 442 after remediation) was traced
to its consumer across `SEA_Config.mqh`, `SEA_Presets.mqh`, `SEA_SignalEngine.mqh`,
`SEA_TradeExecutor.mqh`, `SEA_UI.mqh`, `SEA_Reporting.mqh`, `SEA_ConfigSync.mqh`, and
`SimpleEA_v1-05.mq5`. Every input falls into exactly one status:

| Status | Meaning |
|---|---|
| **LIVE** | Read, and the field it feeds is genuinely consumed by TS/TE/UI logic under at least one preset. |
| **SEED DEFAULT** | Read into a field in `InitializeConfig()`, but unconditionally overridden by `ApplyPreset()` for at least one preset. **Do not delete** — see architecture below. |
| **DEAD** | The value never reaches any consumer, under any preset. Traced and removed (or the field's inertness documented) below. |

### The seed-then-override architecture (why some inputs *look* dead but aren't)

`SEA_Inputs.mqh`'s `InitializeConfig()` populates every `ST_Settings` field once, up front, from
the input panel — including the "⚠️ ENGINE SEED DEFAULTS" groups (the former `PRESET_CUSTOM`
namespace, renamed `Inp_Global_*` in the 2026-06 refactor — see above). `ApplyPreset()`
(`SEA_Presets.mqh`) then runs and **overwrites** most of those fields with preset-specific values.

This means a seed-default input can look orphaned by a naive grep (its value is always replaced
before use) while still being architecturally load-bearing: it's what a field falls back to for
any preset that *doesn't* override it, and it's the value new presets inherit by default. **34
`Inp_Global_*` inputs are in this position today** — every preset currently active happens to
override them, but the wire from input → field → consumer is intact and the consumer (the field)
genuinely reads it. This is different in kind from a DEAD input, where the field itself is never
read at all. Do not delete a SEED DEFAULT input on the grounds that "no preset uses my override" —
check whether the *field* has a live reader instead.

**Full SEED DEFAULT list** (all `Inp_Global_*`, all overridden by ≥1 of the four presets):
`Inp_Global_Ind_Adx_PercentileRefreshSec`, `Inp_Global_Ind_CandleBody_CarryOnOverext`,
`Inp_Global_Ind_CandleBody_MinCloseRatio`, `Inp_Global_Ind_Fib_Enabled`,
`Inp_Global_Ind_Fib_MaxRetracement`, `Inp_Global_Ind_Fib_MinRetracement`,
`Inp_Global_Ind_Fib_SwingLookback`, `Inp_Global_Ind_Mfi_Level`, `Inp_Global_LayerPullbackEnabled`,
`Inp_Global_LayerS_Require_DirAlign`, `Inp_Global_MTF_EMA_Fast`, `Inp_Global_MTF_EMA_Slow`,
`Inp_Global_MTF_RequirePhase`, `Inp_Global_MTF_TF1`, `Inp_Global_MTF_TF2`,
`Inp_Global_MinBarsAfterClose`, `Inp_Global_SL_AtrMult`, `Inp_Global_SL_AtrPeriod`,
`Inp_Global_SL_FixedPips`, `Inp_Global_SL_MinPips`, `Inp_Global_SL_WidenToMinimum`,
`Inp_Global_TrailEMA_Period`, `Inp_Global_TrailEMA_Shift`, `Inp_Global_VETO_MaxSpread`,
`Inp_Global_VETO_MaxSpreadRetryBars`, `Inp_Global_VETO_NewsPostMinutes`,
`Inp_Global_VETO_NewsPreMinutes`, `Inp_Global_VETO_TE_BC_TolerancePips`,
`Inp_Global_VETO_TE_OpenDelaySeconds`, `Inp_Global_VETO_TE_RecheckBarClose`,
`Inp_Global_VETO_TE_SpreadMedianTicks`, `Inp_Global_VETO_UseNews`, `Inp_Global_VETO_UseSpread`,
`Inp_Global_VPRR_Enabled`.

The remaining 27 `Inp_Global_*` inputs (`ClimaxGuard_*`, `Safety_*`, the `F_*` filter toggles,
`VPRR_MinRatio_W/M/S`, `ManualSide`, `LayerReset_*`, `MinBarsAfterWeekendGap`,
`VETO_NewsImpactFilter`) are **never** touched by `ApplyPreset()` for any preset — they are
uniformly LIVE, not seed defaults, despite sitting in the same input groups. `Inp_Global_Preset`,
`Inp_Global_MagicNum`, and `Inp_Global_VETO_NewsFile` are also LIVE, read directly by name outside
the `ST_Settings` struct entirely (control flow / file path, not a tunable).

### DEAD inputs found and removed

The higher-priority defect: inputs that *look* tunable — normal per-preset inputs, indistinguishable
in the panel from any other — but whose value never reaches a consumer. Sweeping one of these in an
optimizer produces flat, meaningless noise and can be misread as "this parameter doesn't matter,"
when in fact it was never being tested. 15 were found and removed in this audit (search history for
`F-AUDIT 2026-07` in `SEA_Inputs.mqh` / `SEA_Presets.mqh` for the exact diffs):

| Input (removed) | Fed field | Why it was dead |
|---|---|---|
| `Inp_RRM_ORG_MacdMode` | — (never assigned) | Never referenced outside its own declaration. `Settings.MacdVoteMode` (the field the MACD voter switches on) is hardcoded per-preset; default happened to match `MACD_HISTOGRAM`. |
| `Inp_FPM_Ind_SmaConverge_Enabled` | — (never assigned) | Never referenced outside its own declaration. `Ind_SmaConverge_Enabled` is hardcoded `false` in every preset. |
| `Inp_FPM_SLMode` | — (never assigned) | Disconnected by a deliberate prior fix ("user could accidentally switch to non-swing mode"); left declared afterward. |
| `Inp_FPM_SwingLookback` | — (never assigned) | Disconnected by the same fix; `GetFPMSwingLookback()` (TF-aware helper) supplies the value instead. |
| `Inp_MA_MaximumRiskPct` | `MA_MaximumRiskPct` | Field hardcoded `0.02` in `InitializeConfig()`, never touched by `ApplyPreset()` for any preset; default coincidentally matched. |
| `Inp_MA_DecreaseFactor` | `MA_DecreaseFactor` | Same pattern, hardcoded `3.0`. |
| `Inp_RRM_ORG_AllowWeak` | `Emerging_/Trending_AllowWeakTrades` | Neither field is ever read by the Phase/Layer gate. Real layer on/off is `AllowLayer1_Entries` (fed by `Inp_RRM_ORG_AllowLayerW`, which **is** live). |
| `Inp_RRM_ORG_AllowMedium` | `Emerging_/Trending_AllowMediumTrades` | Same — real control is `AllowLayer2_Entries` / `Inp_RRM_ORG_AllowLayerM`. |
| `Inp_RRM_ORG_AllowStrong` | `Trending_AllowStrongTrades` | Same — real control is `AllowLayer3_Entries` / `Inp_RRM_ORG_AllowLayerS`. (`Emerging_AllowStrongTrades`, the one sibling field that *is* read, is fed by `Inp_TI_Emerging_AllowStrong` instead — not this input.) |
| `Inp_RRM_ORG_Mfi_Mode` | `MfiMode` | `Check_MFI()` only ever compares `T_MfiOB`/`T_MfiOS`; never branches on mode. |
| `Inp_RRM_ORG_VRC_ATR_Period` | `VRC_ATR_Period` | VRC's shared ATR handle is built from `Settings.P_Atr`, not this field. |
| `Inp_Debug_Stats_TrackRejections` | `Stats_TrackRejections` | Never read; only `Stats_FullEvaluation` gates the stats logic. |
| `Inp_Debug_Stats_TrackPasses` | `Stats_TrackPasses` | Same. |
| `Inp_Global_MTF_StrictAlignment` | `MTF_StrictAlignment` | Self-documented in code: *"retained for compatibility but the gate is strict-by-construction; the flag no longer relaxes it."* |
| `Inp_RRM_ORG_LayerPB_RecoveryOnSlope` | `LayerRecoveryOnSlope` | Never read. Consistent with the slope-only RECOVERED model (README.md, Layer section) being unconditional post-refactor — same shape as the already-documented `Inp_RRM_ORG_LayerPriceTouchEnabled` deprecation. |

For the fields above that are still touched by other, unrelated live code paths (`MA_MaximumRiskPct`
in `SEA_TradeExecutor.mqh`'s lot sizing, `MTF_StrictAlignment` in `ConfigSync`), the removed input's
old feed line was replaced with a literal matching its prior default — behaviour is unchanged,
because these values were already provably not reaching any consumer before the edit.

### Negative control

`Emerging_AllowStrongTrades` — the one sibling of the three dead `Trending_/Emerging_Allow*Trades`
fields that survived — **is** read, at `SEA_SignalEngine.mqh:7977`, matching README.md's documented
Phase-gate behaviour ("LayerS always blocked in EM"). This confirms the dead-field detection isn't a
false-positive sweep: the mechanism correctly distinguishes the one real flag in that family from its
five decorative neighbours.

### Known, pre-existing, intentionally-retained dead input

`Inp_RRM_ORG_LayerPriceTouchEnabled` was already documented (S2 + A21 section, above) as deprecated
and no-op, retained deliberately for `.set`-file back-compat. This audit re-confirms that
classification and makes no further change to it — it is the one case in the input surface where
"dead but intentionally kept" was already the correct, documented state before this audit.

### Logged, out of scope

- `Inp_FPM_SLFixedPips` is read into `Settings.SL_FixedPips`, a field genuinely consumed elsewhere —
  but under `PRESET_FPM` specifically it is currently unreachable, because FPM's `SLMode` is
  hardcoded `SL_MODE_SWING` (see the `Inp_FPM_SLMode` removal above) and `SL_FixedPips` only applies
  under `SL_MODE_FIXED_PIPS`. Not reclassified as DEAD (the field has live readers under other
  presets/modes), but worth a maintainer's attention if FPM's fixed-pips SL mode is ever meant to be
  reachable again.
- A parallel audit of internal `ST_Settings` struct fields (independent of whether an `Inp_*` feeds
  them — e.g. the now-input-less `Trending_/Emerging_Allow*Trades`, `MfiMode`, `VRC_ATR_Period`,
  `Stats_TrackRejections/Passes`, `MTF_StrictAlignment`, `LayerRecoveryOnSlope` fields, which remain
  declared in the struct but unread) was not undertaken here — this audit's scope was the `Inp_*`
  input surface only. Worth a session of its own.
- The `#ifdef SEA_PRESET_MA` blocks in `SEA_Reporting.mqh` / `SimpleEA_v1-05.mq5` are dead code
  today (`SEA_PRESET_MA` is never `#define`d — `SEA_Config.mqh:14`); fixed in place while touching
  them for this audit, but the broader question of whether that preprocessor flag should exist at
  all is out of scope.

