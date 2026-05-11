# Parameter Mapping (Breaking Change)

This release renames ambiguous/conflicting inputs to explicit scoped names.

> ⚠️ **Breaking change:** existing `.set`/preset input files using old names will not auto-map. Re-enter values using the new names below.

| Old parameter name | New parameter name | Scope | Notes |
|---|---|---|---|
| `Inp_RiskPercent` | `Inp_RM_RiskPercentDefault` | RM | Clarifies this is the default RM risk when adaptive risk does not override. |
| `Inp_UseAdaptiveRisk` | `Inp_RM_UseAdaptiveRisk` | RM | Moves adaptive risk toggle under RM namespace for consistent precedence. |
| `Inp_AdaptiveRisk_M1` | `Inp_RM_AdaptiveRisk_M1` | RM | TF-specific adaptive RM value (M1). |
| `Inp_AdaptiveRisk_M5` | `Inp_RM_AdaptiveRisk_M5` | RM | TF-specific adaptive RM value (M5). |
| `Inp_AdaptiveRisk_M15Plus` | `Inp_RM_AdaptiveRisk_M15Plus` | RM | TF-specific adaptive RM value (M15+). |
| `Inp_RRRatio` | `Inp_CUSTOM_RRRatio` | CUSTOM | Removes conflict with `Inp_FPM_RRRatio` and `Inp_RRM_RRRatio`; now clearly CUSTOM-only. |
| `Inp_Ind_SmaConverge_Enabled` | `Inp_FPM_Ind_SmaConverge_Enabled` | FPM | Aligns FPM-only input with FPM prefix convention. |
| `Inp_Gate_RequireRecoveryMomentum` | `Inp_CUSTOM_RequireRecoveryMomentum` | CUSTOM | Removes ambiguous gate naming and RRM leakage into CUSTOM area. |
| `Inp_RRM_Lookback` | `Inp_CUSTOM_Lookback` | CUSTOM | Renamed because this input is consumed by CUSTOM baseline config, not locked to RRM preset. |

## Compatibility note

Code comments in `SEA_Config.mqh` include the old names next to the renamed inputs to make migration easier while updating user presets/templates.
