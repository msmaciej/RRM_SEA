# Legacy DPI Indicators

The following files are kept here for **historical reference only** and are not used in active development:

- `DPI_Indicator.mq5` — Original TSI-based DPI standalone indicator; source of `DPI_tm_simple.mq5` (root)
- `DPI_Indicator_v7.mq5` — Obsolete MACD-only prototype, superseded by the mc_* family
- `DPI_v29_OK_CLEAN.mq5` — Renamed to `DPI_mc_simple.mq5` (root)
- `DPI_v31_CLEAN_22_OK_FINAL_WORKING.mq5` — Renamed to `DPI_mc_main.mq5` (root, with GREEN-off visual fix)

---

## DPI file mapping (after this PR)

**Active standalone indicators (repo root):**

| File | Source | Notes |
|------|--------|-------|
| `DPI_mc_simple.mq5` | ← renamed from `DPI_v29_OK_CLEAN.mq5` | MACD+CCI core, no GREEN |
| `DPI_mc_main.mq5`   | ← renamed from `DPI_v31_CLEAN_22_OK_FINAL_WORKING.mq5` | MACD+CCI core + GREEN toggle + GREEN-off visual fix |
| `DPI_tm_simple.mq5` | ← copied from `Legacy/DPI_Indicator.mq5` | TSI+MACD math family |

**Legacy (kept as historical reference, not used):**

| File | Notes |
|------|-------|
| `Legacy/DPI_Indicator.mq5` | TSI+MACD prototype; source of `DPI_tm_simple.mq5` |
| `Legacy/DPI_Indicator_v7.mq5` | Obsolete MACD-only prototype, superseded by mc_* family |
| `Legacy/DPI_v29_OK_CLEAN.mq5` | Original pre-rename; superseded by `DPI_mc_simple.mq5` |
| `Legacy/DPI_v31_CLEAN_22_OK_FINAL_WORKING.mq5` | Original pre-rename; superseded by `DPI_mc_main.mq5` |

---

## Vote rule

EA's internal DPI math (`SEA_SignalEngine.mqh::ComputeDPIMainHist`) implements the `DPI_mc_main` equation.

- **Yellow ribbon** → DPI=1 for Bias=Long
- **Red ribbon** → DPI=1 for Bias=Short
- **GREEN is visualization only** (momentum strength / overbought-oversold). It does **not** gate the DPI vote.

Setting `DPI_UseGreenHist=false` makes EA's DPI vote data equivalent to `DPI_mc_simple` (vote is driven solely by ribbon color with optional CCI-reset confirmation).
