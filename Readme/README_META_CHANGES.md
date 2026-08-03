# Meta-Gate corrections — 2026-08-03

Summary of what changed and why, plus the two README edits you should paste in.

## 1. Root cause of "gated worse than ungated" (not a code rebuild)

The MetaGate features were **not** missing. `MetaBuildFeatures()` logs ~34 features
every event, and the context gauges (`adx`, `rsi`, `bb_width_atr`, `stoch`, `mfi`,
`di_spread`, `ret_vol_20`, `ema_fan_atr`) are live via their own handles regardless of
the `RRM_ORG` preset. The real DPI/telemetry values (`dpi_green`, `dpi_hist`, `phase`,
`layer_*`, `votes_frac`, `vprr_ratio`) are wired via `MetaSetTelemetry` /
`MetaSetIndicators`, which **are** called from `SimpleEA_v1-05.mq5` (lines ~1047-1050).
`macd_hist` is gone on purpose — replaced by the REAL `dpi_hist`.

What actually bit you: **stale collected data trained through a broken label.** Before
the 2026-07-31 → 2026-08 fixes, `macd_hist` was identically 0 (dead), DPI values were
proxies, and the label was the fixed-RR barrier that mislabeled ~half your winners.
The events writer de-dups by `event_time`, so re-running COLLECT did nothing. Fix =
**delete `TS_events_*` + `TS_outcomes_*` → re-COLLECT → re-TRAIN**, then let Ladder 1
gate the result. No rebuild of Ladder 2 was needed.

## 2. `rrm_meta.py` corrections (this package)

- **Dead-feature guard.** Before fitting, each feature is checked for zero variance;
  constant / all-zero / all-NaN columns are dropped from the model and reported. This
  catches the exact dead-column failure automatically and keeps it out of the exported
  `MetaModel_*.csv`.
- **Honest output.** Header and prints now say **"purged HOLDOUT + PSR"** (not
  "deflated Sharpe"), show the **number of thresholds tried** (a trial count), print a
  **SHIP-candidate / DO-NOT-SHIP** line, and point to `rrm_validate.py` for the real
  check. No change to the export format or the model the EA reads.

## 3. `rrm_validate.py` (Ladder 1 — new)

Purged K-fold + embargo, **CPCV**, **Deflated Sharpe** (with explicit trial count),
**PBO**, plus **feature health** and the **dual B/Q labels**. Run it before training;
train only the pairs it marks SHIP. `--smoke` runs a synthetic self-test with no MT5
data. No `mlfinlab` dependency.

## 4. README edits to paste (fix the two over-claim spots)

**`README_META_GATE.md` §6** — after the results block, replace any wording that implies
the trainer computes a deflated Sharpe with:

> The trainer reports a **purged-holdout PSR** (probabilistic Sharpe), not a deflated
> one. The threshold is tuned on the train slice and read once out-of-sample. The full
> **purged K-fold / CPCV + Deflated Sharpe + PBO** is Ladder 1 (`rrm_validate.py`); run
> it first and ship only its passers. Every threshold you sweep is a trial — that is
> what Ladder 1 deflates for.

**`README_META_GATE_RRM_MetaGate_Implementation_Spec.md` §6** — change the comment
"Purged + embargoed CV … with DEFLATED SHARPE + PBO" so it is clearly scoped to
`rrm_validate.py`, not `rrm_meta.py`:

> `rrm_meta.py` = fit + purged-holdout PSR + export (Ladder 2). Purged K-fold / CPCV,
> Deflated Sharpe and PBO are implemented in `rrm_validate.py` (Ladder 1), which runs
> first and decides which pairs are worth training at all.

## 5. Order of operations (the one rule)

COLLECT → **VALIDATE (Ladder 1)** → TRAIN only passers (Ladder 2) → GATE (Ladder 3).
Upgrade the CHECK before you trust the MODEL. See `README_META_SEQUENCE.md` (v5).

## 6. `rrm_validate.py` — 2026-08-03 updates (applied, not just knobs)

- **Profitability readout added.** Section [2] prints ungated total R / profit factor /
  expectancy (the "are we making money?" answer); section [4] compares gated vs ungated
  **on the same OOS trades**. `rrm_meta.py` prints a matching total-R / PF line too.
- **DSR trial count fixed.** N is now the number of thresholds swept (`len(THRESH_GRID)`),
  not folds × thresholds — folds are CV estimates of the same configs, not new trials.
- **DSR variance unit fixed.** The "variance across trials" now uses raw Sharpe ratios,
  not PSR probabilities (a unit mismatch that inflated the hurdle SR0).
- **Verdict rebalanced.** SHIP is decided by **profitability up OOS + PBO < 0.5 + wins on
  most CPCV paths**. DSR is reported as a STRICT advisory only — a fat-tailed R profile
  (many BE scratches + rare big winners, i.e. RRM) has low per-trade Sharpe even when
  clearly profitable, so requiring DSR > 0.95 would wrongly veto good gates.
- **`FEATURE_SUBSET` knob added.** Set it to a list (e.g. the regime tells) to test fewer
  features without re-collecting. `Q_TARGET_R` remains the signal-only barrier to set.

See `README_HOW_TO_READ_RESULTS.md` for a plain-language walk-through of every number.
