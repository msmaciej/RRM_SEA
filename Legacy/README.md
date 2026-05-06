# Legacy DPI Indicators

The following files are **obsolete DPI prototypes** and are kept here for historical reference only:

- `DPI_Indicator.mq5` — Original TSI-based DPI standalone indicator (superseded)
- `DPI_Indicator_v7.mq5` — MACD-based DPI standalone indicator v7 (superseded)

These have been superseded by:

- **`DPI_v31_CLEAN_22_OK_FINAL_WORKING.mq5`** (repo root) — authoritative v31 implementation for chart visualization
- **EA's internal DPI v31 logic** in `SEA_SignalEngine.mqh::ComputeDPIMainHist` and `Check_DPI` — v31-equivalent math integrated into the TS voting equation

Do **not** use the files in this directory for new development. Use `DPI_v31_CLEAN_22_OK_FINAL_WORKING.mq5` for standalone chart indicators, and configure the EA's internal DPI via `Ind_Dpi_Enabled`/`Ind_Dpi_Weight` inputs.
