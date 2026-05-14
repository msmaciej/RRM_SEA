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
| `Inp_LayerPullbackRatio` | `Inp_RRM_LayerPullbackRatio` | RRM Preset | Yes |
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

