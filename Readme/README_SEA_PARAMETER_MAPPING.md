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
| `Inp_RRM_ORG_MinPBBars_W` | `2` | **A21** — LayerW (EMA1/2) must stay in DETECTED for at least this many bars before IN-TREND. A pullback cannot complete in one bar. Set to 0 to disable. |
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
| `Inp_RRM_ORG_UNO_ToleranceBars` | `2` | Consecutive UNO bars tolerated before layer states wipe. A transient UNO flicker that resolves back to the SAME direction within this many bars PRESERVES DETECTED/IN-TREND. `0` = strict (reset on the first UNO bar). Plumbed to the scanner via ConfigSync. |
| `Inp_RRM_ORG_LayerPullbackWindow_W` | `21` | LayerW pullback **observation window** (bars) — distinct from the baseline slope lookback (13/21/34). Bounds how long an IN-TREND layer stays entry-eligible (the recovery max-age default). `0` = use the global. |
| `Inp_RRM_ORG_LayerPullbackWindow_M` | `34` | LayerM observation window. |
| `Inp_RRM_ORG_LayerPullbackWindow_S` | `55` | LayerS observation window. |
| `Inp_RRM_ORG_LayerPullbackWindow` | `0` | Global observation-window override (`0` = use per-layer values). |
| ~~`Inp_RRM_ORG_LayerRecoveryMaxAgeEnabled`~~ | ~~`true`~~ | **REMOVED 2026-07-24** — see "Inert max-age flag removal" below. The mechanism it described was deleted in the 2026-07 fire-on-edge refactor; only the decoy input survived. |

Corresponding `ST_Settings` fields: `UNO_ToleranceBars`, `LayerPullbackWindow_W/M/S`, `LayerPullbackWindow`. All synced EA→scanner via `SEA_ConfigSync`. (`LayerRecoveryMaxAgeEnabled` was removed 2026-07-24.)

### New telemetry field — ST_SignalTelemetry

| Field | Type | Set when | UI effect |
|-------|------|----------|-----------|
| `i_suppressed` | `bool` | `m_diag_last_reason == "L_NONE_ALIGNED"` — no layer structurally aligned, I factor never evaluated | Cockpit shows `I[?]` and `--/N [L-blocked]` in VOTE display instead of misleading `I[-]` |

---

## Input Surface Audit (2026-07, F-AUDIT)

Every `Inp_*` declaration in `SEA_Inputs.mqh` (457 at audit time, 437 after remediation — see Round 2
below) was traced
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
| `Inp_RRM_ORG_LayerPB_RecoveryOnSlope` | `LayerRecoveryOnSlope` | Never read. Consistent with the slope-only IN-TREND model (README.md, Layer section) being unconditional post-refactor — same shape as the already-documented `Inp_RRM_ORG_LayerPriceTouchEnabled` deprecation. |

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
- The `#ifdef SEA_BUILD_MA` blocks in `SEA_Reporting.mqh` / `SimpleEA_v1-05.mq5` are dead code in
  the current build (`SEA_BUILD_MA` is not the active preset — `SEA_Config.mqh` currently has only
  `SEA_BUILD_RRM_ORG` uncommented; this repo compiles one preset at a time). Fixed in place while
  touching them for this audit (see Round 1 note below on a real bug this caused), but the broader
  question of whether that preprocessor flag should exist at all is out of scope.

### Round 2 (2026-07) — methodology correction, 5 more dead inputs found

The first pass of this audit classified "is a field ever read" by searching `SEA_SignalEngine.mqh`,
`SEA_TradeExecutor.mqh`, `SEA_UI.mqh`, `SEA_Reporting.mqh`, and `SEA_ConfigSync.mqh` together. That
was too permissive: `SEA_ConfigSync.mqh` only serializes fields to/from `.set`-sync files for
save/load round-tripping — it is not a functional consumer. A field referenced only there is just
as dead as one referenced nowhere, but the first pass's script counted a ConfigSync read as
sufficient to call a field LIVE. This masked one field entirely and would have masked more had three
existing READMEs (`README_SEA_SIGNAL_REFERENCE.md`, `README_SEA_TRADE_LOGIC.md`,
`README_SEA_PRESETS.md`) not already documented them independently — a cross-reference the first
pass should have made and didn't.

**Corrected rule:** a field is LIVE only if something in `SEA_SignalEngine.mqh`, `SEA_TradeExecutor.mqh`,
`SEA_UI.mqh`, `SEA_Reporting.mqh` (excluding pure config-value echoes), or `SimpleEA_v1-05.mq5` uses
its *value* in a decision, calculation, or display — not merely persists it. `SEA_ConfigSync.mqh`
usage alone does not confer LIVE status.

Re-running the corrected check found one further field directly (`LayerPullbackRatio`, now renamed
`LayerPullbackRatio_Legacy` — see below). A second class needed manual data-flow tracing the script
can't do automatically: `LayerRecoveryRatio` and its `_W/_M/_S` siblings *are* read into a local
variable (`GetLayerRecovery()` → `UpdateSingleLayerPullback()`'s `recovery_ratio` parameter), so a
naive "is it referenced" check calls them LIVE — but that parameter is explicitly, deliberately never
consulted in the IN-TREND-transition decision (the function's own comment: *"recovery_ratio /
recovery_cond are no longer consulted here (retained in the signature for ABI/back-compat)"*); its
only remaining use is inside a `DebugLog()` string. Confirmed against the three READMEs above, which
already described exactly this.

| Input (removed) | Fed field | Why it was dead |
|---|---|---|
| `Inp_RRM_ORG_LayerPBPullbackRatio` | `LayerPullbackRatio` (renamed `LayerPullbackRatio_Legacy`, see below) | Never referenced outside `SEA_ConfigSync.mqh`'s serialization. Already documented as inert in three READMEs. Its removed input comment had an extensive tuning history ("changed 0.50→0.65 for sensitivity") written *after* the value had already stopped mattering — the exact optimizer-sweep trap this audit exists to catch. |
| `Inp_RRM_ORG_LayerPBRecoveryRatio` | `LayerRecoveryRatio` | Traced to `GetLayerRecovery()` → `UpdateSingleLayerPullback()`'s `recovery_ratio` param, confirmed unused in the IN-TREND decision (only reaches a debug-log string). |
| `Inp_RRM_ORG_RecoveryRatio_W` | `LayerRecoveryRatio_W` | Same trace as above. |
| `Inp_RRM_ORG_RecoveryRatio_M` | `LayerRecoveryRatio_M` | Same trace as above. |
| `Inp_RRM_ORG_RecoveryRatio_S` | `LayerRecoveryRatio_S` | Same trace as above. |

**Field rename:** during troubleshooting an unrelated MetaEditor compile error ("undeclared
identifier 'LayerPullbackRatio'" at two call sites, with root cause never conclusively identified —
most likely a stale local build artifact predating this field, since the field, its declaration, and
every reference were verified byte-identical and syntactically valid), the `ST_Settings` field was
renamed `LayerPullbackRatio` → `LayerPullbackRatio_Legacy` as a diagnostic experiment. It resolved
the compile error, so the rename was kept. The persisted `SEA_ConfigSync.mqh` key stays
`"LayerPullbackRatio"` (decoupled from the field name) so old saved `.set`-sync files still round-trip.

This round's inputs bring the running total to **20 dead inputs removed**, input count **457 → 437**.
`Inp_RRM_ORG_LayerPriceTouchEnabled` was cross-checked against the same three READMEs and remains
correctly classified from round 1: already documented, intentionally retained for back-compat, no
further action.

---

## Climax layer-wipe removal (2026-07)

`Inp_Global_ClimaxGuard_ResetPullback` is **removed**, together with its entire scaffolding. This is a
mechanism deletion, not a dead-input sweep: the flag was wired end-to-end and would have executed the
moment both it and the climax master toggle were set.

### What was removed

| Surface | File | Was |
|---|---|---|
| Input | `SEA_Inputs.mqh` | `input bool Inp_Global_ClimaxGuard_ResetPullback = false;` |
| Settings mapping | `SEA_Inputs.mqh` | `Settings.ClimaxGuard_ResetPullback = Inp_Global_...;` |
| Struct field | `SEA_Config.mqh` | `bool ClimaxGuard_ResetPullback;` |
| Behaviour | `SEA_SignalEngine.mqh` | `ResetAllLayerPullback()` + both call sites (`EvaluateTS`, `EvaluateTS_AtShift`) |
| Dead wrapper | `SEA_SignalEngine.mqh` | `Scanner_ResetAllLayerPullback()` — no caller anywhere in the tree |
| Config-sync key | `SEA_ConfigSync.mqh` | snapshot writer + `SEA_CS_ApplyKey` parser for `ClimaxGuard_ResetPullback` |
| Scanner input | `SEA_IND_SignalScan.mq5` | `input bool CG_ResetPullback = true;` + its `BuildSettings` mapping |

### Why

1. **Same destructive class as the removed consumption reset, but broader.** It forced all three layer
   P-R state machines to `NONE`, on a bar the engine had just *rejected* — where the consumption reset
   wiped one layer after a *fire*.
2. **It contradicted the engine's own stale-only invariant.** `MaybeResetLayersOnPhaseChange` documents
   why a full reset to `NONE` is wrong: it erases an in-progress `DETECTED` at the pullback→recovery
   boundary, and `NONE` is exitable only by a *fresh* pullback, so the layer is stranded through the
   whole recovery. `ResetAllLayerPullback` did exactly that, unconditionally, on every layer.
3. **Blast radius wider than the README implied.** CG is the final sub-filter *inside* F (F-AUDIT
   2026-06), so it is evaluated before L and I — the wipe could fire on bars that were never signal
   candidates. The README text claiming CG "is checked last, only after B·P·L·I·F have all passed" was
   corrected in the same change.
4. **Cross-engine parity break.** The scanner defaulted `CG_ResetPullback = true` while the EA defaulted
   `false`, and `Scn_Sync_With_EA` was off by default at that time (scanner inputs authoritative; the default was flipped ON 2026-07-24) — so enabling
   `TS_ClimaxGuard` alone armed the wipe on the scanner but not on the EA.
5. **No Oracle mandate and no validation evidence.** No RRM rule makes a blocked entry unmake the
   pullback structure, and the flag has no known run in which it was ever enabled.

### Action required for existing `.set` files

None. `Inp_Global_ClimaxGuard_ResetPullback` and the scanner's `CG_ResetPullback` simply disappear from
the inputs dialog; MT5 ignores keys for inputs that no longer exist. Old config-sync snapshots that still
carry the `ClimaxGuard_ResetPullback=` line load unchanged — `SEA_CS_ApplyKey()` ignores unknown keys, the
same backward-compatible path used for the F-AUDIT-STRUCT keys retired below.

**Unchanged:** the climax guard itself — `Inp_Global_F_ClimaxGuard_Enabled`, `ClimaxGuard_Lookback`,
`ClimaxGuard_ATRPeriod`, `ClimaxGuard_BarATRMult`, `ClimaxGuard_MoveATRMult` — and its blocking behaviour.

---

## Inert max-age flag removal + diagnostic colour (2026-07-24)

Two changes in the diagnostics-fidelity session. Neither alters a trade decision.

### Removed — `Inp_RRM_ORG_LayerRecoveryMaxAgeEnabled`

The bar-count max-age expiry was deleted in the 2026-07 fire-on-edge refactor. The flag that
had gated it was left wired end-to-end and **defaulted `true`** — an optimizer decoy of exactly
the class the F-AUDIT exists to remove, and worse than the usual case because its default
implied an active safety mechanism ("prevents stale chase-entries") that no longer existed.

| Surface | File | Was |
|---|---|---|
| Input | `SEA_Inputs.mqh` | `input bool Inp_RRM_ORG_LayerRecoveryMaxAgeEnabled = true;` |
| Seed assignment | `SEA_Inputs.mqh` | `Settings.LayerRecoveryMaxAgeEnabled = true;` |
| Struct field | `SEA_Config.mqh` | `bool LayerRecoveryMaxAgeEnabled;` |
| Preset mapping | `SEA_Presets.mqh` | `cfg.LayerRecoveryMaxAgeEnabled = Inp_...;` |
| Config-sync | `SEA_ConfigSync.mqh` | snapshot writer + `SEA_CS_ApplyKey` parser |
| Engine parameter | `SEA_SignalEngine.mqh` | `bool maxage_enabled = false` + the argument at all 6 call sites |

**Why removal is provably non-behavioural:** `maxage_enabled` appeared in the body of
`UpdateSingleLayerPullback` only inside a *commented-out* transition
(`// else if(state==LAYER_PB_INTREND && maxage_enabled && bars_rec>=window)`). No live
expression read it, so no state transition can move. Same pattern as the `recovery_ratio` /
`use_price_touch` removals in the Struct Surface Audit. Arity: **19 params, 19 args at all 6
call sites** (live ×3, warm-up replay ×3).

A stale reasoning comment in `DeriveLayerState` justified its replay depth partly on
*"max-age bounds a true IN-TREND to <= window bars"*, with CROSS-anchor extension as the
`OFF` branch. That branch has been unconditional since max-age was deleted; the comment now
says so.

### Removed — `Scanner_DetectClimax`

One-line wrapper in `SEA_SignalEngine.mqh`, zero callers anywhere in the tree — same class as
`Scanner_ResetAllLayerPullback`. `DetectClimax` itself is live via `EvaluateF` and untouched.

### Added — `Inp_UI_clr_Waiting` / `ST_Settings.clr_Waiting`

Not a removal. The cockpit layer rows gained a third state (`[~]`, structurally stacked but not
fire-eligible) and it needs a colour distinct from `clr_Pass`, `clr_Fail` (`clrOrangeRed`) and
`clr_Disabled`. Default `clrYellow`.

### Net surface change

| Surface | Before | After |
|---|---|---|
| `ST_Settings` fields | 327 | **327** (−`LayerRecoveryMaxAgeEnabled`, +`clr_Waiting`) |
| `SEA_Inputs.mqh` inputs | 433 | **433** (−max-age, +`Inp_UI_clr_Waiting`) |

### Action required for existing `.set` files

None. `Inp_RRM_ORG_LayerRecoveryMaxAgeEnabled` disappears from the dialog and MT5 ignores keys
for inputs that no longer exist. Old config-sync snapshots still carrying
`LayerRecoveryMaxAgeEnabled=` load unchanged — `SEA_CS_ApplyKey()` ignores unknown keys, the
same backward-compatible path used for every prior retirement.

---

## Struct Surface Audit (2026-07, F-AUDIT-STRUCT)

The sequel the F-AUDIT logged as out of scope ("*a parallel audit of internal `ST_Settings` struct
fields … was not undertaken here … Worth a session of its own*"). Every field of `ST_Settings`
(360 at audit time, **327 after remediation**) was traced to a consumer.

**Result: 33 dead fields removed. 4 EA inputs and 4 SignalScan inputs removed as orphans.
Zero behavioural change** — by construction, since every removed field was proven unread.

### Method — and the two ways a naive sweep lies

A field is **LIVE** only if its *value* reaches a decision, calculation, or non-echo display. The
audit is a data-flow trace, not a reference count, because reference counting fails in **both**
directions:

| Failure | Example | Consequence |
|---|---|---|
| **False LIVE** — referenced, never consulted | `LayerRecoveryRatio` is read by `GetLayerRecovery()` and passed to `UpdateSingleLayerPullback`'s `recovery_ratio` param — which the function's own comment says is *"no longer consulted here"*. Its only remaining use was a `DebugLog` string printing `RecThresh=` for a threshold that no longer thresholds anything. | Dead code survives an audit. |
| **False DEAD** — read from an unexpected file | `UseAdaptiveRisk`, `AdaptiveRisk_M1/M5/M15Plus`, `Override_SL_Cushion`, `Override_BE_Cushion`, `FixedLotSize` are read in **`SEA_Presets.mqh`** — which hosts the TF-resolver and validator helpers (`:91`, `:119`, `:127`, `:817`), not just `ApplyPreset()`. | **Live risk-management code gets deleted.** |

The second is the mirror image of the F-AUDIT's own round-2 bug (which wrongly *included*
`SEA_ConfigSync.mqh` as proof of life). Both have the same root cause: **classifying a *file* as
consumer-or-not, instead of classifying each *occurrence* as read-or-write.** The rule that
survives both:

> **A file is never a consumer. An occurrence is.** Classify every occurrence as READ (any use of the
> value) or WRITE (LHS of `=`). `SEA_ConfigSync.mqh` reads are excluded entirely (serialization is
> not use). Config-echo `Print`s and `DebugLog` strings are excluded (echoing a value is not use).
> Everything else — *including `SEA_Presets.mqh` and `SEA_Config.mqh` helper functions* — counts.

### Negative controls (the audit must distinguish these, or it is a false-positive sweep)

| Field | Verdict | Why it proves the sweep is sound |
|---|---|---|
| `Emerging_AllowStrongTrades` | **LIVE** (`SEA_SignalEngine.mqh`) | The one live member of the six-field `*_Allow*Trades` matrix. Its five neighbours are dead. |
| `DrawEntryLines` | **LIVE** (`SimpleEA_v1-05.mq5:994`) | Same struct section as the dead `DrawTradeLines`; distinguished correctly. |
| `Override_Trail_Cushion` | **LIVE** (`SEA_TradeExecutor.mqh:1725`) | Live sibling of `Override_SL_Cushion` / `Override_BE_Cushion`. |
| `T_MfiOB` / `T_MfiOS` | **LIVE** | Live siblings of the dead `T_Mfi` — all three fed by the *same* input. |
| `LayerFlatRatio` | **LIVE** | The ratio that *replaced* `LayerPullbackRatio`. |

### The dead-field classes

**1. Bypassed mirrors (6)** — the field is unread, but its `Inp_*` **is** read *directly* by the
consumer. The feature works; the struct copy is a decoy. **Invisible to an input audit** (the input
is live) — this class is the reason the struct audit had to exist.

| Field | The input, read directly at |
|---|---|
| `UI_ShowStatusPanel` | `SEA_UI.mqh:524` |
| `UI_ShowCockpitPanel` | `SEA_UI.mqh:640` |
| `UI_ManageChartIndicators` | `SimpleEA_v1-05.mq5:132`, `:642` |
| `UseCustomColors` | `SEA_UI.mqh:158` |
| `UI_FontColor` | `SEA_UI.mqh:159` |
| `ExportUseCommonFiles` | `SEA_Reporting.mqh:35`, `:136` |

The init config-echo in `SimpleEA_v1-05.mq5` was the *only* reader of these fields. It now reads the
inputs directly — so the echo remains truthful and is no longer the thing keeping a dead field alive.

**2. Dead field + orphaned input (4 EA, 4 scanner)** — the field's only writer was an input whose
only sink was that field. Both removed. These are **new dead inputs the F-AUDIT missed**, because a
config-echo or `DebugLog` made their fields look consumed:

| Input removed | Fed | Note |
|---|---|---|
| `Inp_RRM_ORG_RequireRecoveryIntraday` | `RequireRecoveryMomentum` | **The worst of the set.** A user-facing QA toggle ("Require recovery <M15") that never reached a decision. A live decoy — exactly the optimizer-sweep trap the F-AUDIT exists to remove. |
| `Inp_RRM_ORG_CandleBody_CheckBars` | `CandleBody_CheckBars` | Its own declaration comment already said *"(inert — engine no longer uses CheckBars in ATR spike test)"* — admitted inert, yet survived the input audit. |
| `Inp_UI_DrawTradeLines` | `DrawTradeLines` | The "draw trade management lines" feature does not exist. |
| `Inp_RRM_ORG_LayerPriceTouchEnabled` | `LayerPriceTouchEnabled` | See *Reversal* below. |
| `PB_RecoveryRatio` `_W` `_M` `_S` (SignalScan) | `LayerRecoveryRatio*` | Scanner-side twins of the same dead sink. |

**3. Dead sinks, no input (23)** — literal-seeded or preset-written fields that nothing reads:
`Trending_AllowWeakTrades`, `Trending_AllowMediumTrades`, `Trending_AllowStrongTrades`,
`Emerging_AllowWeakTrades`, `Emerging_AllowMediumTrades` (the permission matrix — 5 of 6 dead;
real layer control is `AllowLayer{1,2,3}_Entries`) · `Gate_Recovery`, `Gate_EmaDiv`,
`Gate_CandleDirection` (three `SGateConfig` structs, 10 writes each, **zero reads** — every preset
carefully configures gates that do not exist) · `RRM_Lookback` (TopInvestor even TF-scales it) ·
`LayerPullbackRatio_Legacy`, `LayerRecoveryRatio`, `LayerRecoveryRatio_W/M/S`, `LayerRecoveryOnSlope`,
`LayerPriceTouchEnabled`, `Layer_SlopeTolerance` · `MfiMode`, `T_Mfi`, `VRC_ATR_Period` ·
`MTF_StrictAlignment` · `PSAR_TrailDelay` · `RequireRecoveryMomentum` · `CandleBody_CheckBars` ·
`Stats_TrackRejections`, `Stats_TrackPasses` (already input-less since the F-AUDIT).

### Engine change (the only non-deletion edit)

`UpdateSingleLayerPullback` lost two parameters — `recovery_ratio` and `use_price_touch` — and the
`GetLayerRecovery()` resolver was deleted. Both params were retained "for ABI/back-compat"; MQL5 has
no ABI concern for a private method, and with their feeding fields gone they had no callers.
Arity: **20 params, 20 args at all 6 call sites** (live path ×3, warm-up replay ×3). The
`[%s_PB]` DebugLog no longer prints `RecThresh=`.

**This does not touch the P-R invariant** (`README_SEA_TRADE_LOGIC.md` §1.1): removing an argument
that was never read cannot change a state transition. `LayerPriceTouchEnabled` was the last formal
trace of the removed S2 price-touch gate — with it gone, the "no price inside the P-R machine"
invariant is now enforced by *absence*, not by a `false` default.

### Reversal of a prior decision — `Inp_RRM_ORG_LayerPriceTouchEnabled`

The F-AUDIT kept this input as "dead but intentionally retained for `.set` back-compat". That
decision is **reversed** here, because its premise is gone: it was retained to feed a field that no
longer exists. An input with no sink is not back-compat — it is a pure decoy, the exact defect the
F-AUDIT exists to remove. (MT5 ignores unknown keys in `.set` files, and 20 inputs were already
removed under the breaking-change banner at the top of this document.) To restore it, re-add the
input, the field, and the `use_price_touch` param — but note the gate code it fed was deleted in
Path 2 and does not exist to be revived.

### Running totals

| Surface | Before | After |
|---|---|---|
| `ST_Settings` fields | 360 | **327** |
| `SEA_Inputs.mqh` inputs | 437 | **433** |
| `SEA_IND_SignalScan.mq5` inputs | 159 | **155** |

### The `LayerPullbackRatio` compile error — root cause

The F-AUDIT renamed `LayerPullbackRatio` → `LayerPullbackRatio_Legacy` as a diagnostic experiment
after an *"undeclared identifier"* error at two call sites; the rename resolved it and was kept,
root cause "never conclusively identified". **The field is now deleted outright, so the identifier
no longer exists and the error is structurally impossible.** The workaround is dissolved, not
enshrined — and the decoupled `ConfigSync` key it required is gone with it.

The root cause is now identifiable, and it was never in the source:

- Every module is included as `#include <RRMS\...>` — **angle brackets**. That resolves to
  MetaTrader's `MQL5\Include\RRMS\` directory, **not the repo folder**. The repo is not what
  MetaEditor compiles; a *copy* of it is.
- The two failing sites were `SEA_ConfigSync.mqh`'s save and load. Both reference a field declared in
  `SEA_Config.mqh`. That is exactly the error you get from a **partially-synced Include directory** —
  `SEA_ConfigSync.mqh` freshly copied, `SEA_Config.mqh` stale (predating the field).
- This explains the otherwise-baffling observation that the repo file was *"byte-identical and
  syntactically valid"*: it was valid, and it was not the file being compiled.
- It also explains why the rename "fixed" it. The rename **forced a re-copy** of `SEA_Config.mqh`
  into the Include directory. The re-copy is what fixed it. The experiment confounded two changes
  and credited the wrong one.

> ⚠️ **Operational consequence.** This is stated as the hypothesis best consistent with the evidence,
> not a traced defect — it cannot be proven from the repo, because the fault is *in the build
> environment*, which the repo cannot see. It is falsifiable: check whether `MQL5\Include\RRMS\` is a
> stale copy. **After any change to these files, re-copy ALL of them to `MQL5\Include\RRMS\` before
> compiling.** Syncing a subset reproduces this class of phantom error. Making that directory a
> symlink to the repo would eliminate it permanently.

