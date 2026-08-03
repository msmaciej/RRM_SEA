# META-GATE — Run Sequence (v5, Ladder 1 now in the loop)

**What this is:** the everyday loop to *use* the meta-gate. It is **not** "the Ladder 2
process." The loop spans three ladders plus the data step that feeds them. The only
change from v4.1 is that **Ladder 1 (validate) is now built and slots in before TRAIN.**

| Step | What it is | Ladder | File |
|---|---|---|---|
| 1 — COLLECT | gather the data (the EA writes the files) | — (data step) | EA |
| 2 — **VALIDATE** | **is a gate on this pair even worth training?** | **Ladder 1** | **`rrm_validate.py`** |
| 3 — TRAIN | build + export the model | Ladder 2 | `rrm_meta.py` |
| 4 — GATE | use the model | Ladder 3 | EA switch |

**The rule that reorders everything:** *upgrade the CHECK before you trust the MODEL.*
So you now COLLECT → **VALIDATE** → TRAIN **only the pairs that pass** → GATE.

---

## Two switches (Inputs tab) — the only things you flip
- `Inp_META_LogFeatures` — should the EA write its trades to a file? (on/off)
- `Inp_META_Enabled` — is the filter allowed to skip trades? (on/off)

Everything else — symbol, timeframe, dates, all other inputs — stays the same across
the steps for a given pair+TF. Across pairs/TFs you change only the chart.

---

## Step 1 — COLLECT  *(data step)*
- `Inp_META_LogFeatures = true`, `Inp_META_Enabled = false`
- Put up the chart for the pair+TF (e.g. EURUSD M1), run the backtest over your range.
- **Result — two files per pair+TF**, in `Common\Files`:
  - `TS_events_RRM_ORG_<SYM>_<TF>.csv` — one row per trade **entry** (the features)
  - `TS_outcomes_RRM_ORG_<SYM>_<TF>.csv` — one row per trade **close** (the real result)
- Journal prints `[META] COLLECT SUMMARY: N new events, M new outcomes … -> <path>`.

> **Do this after ANY engine change.** The events writer appends and de-dups by
> `event_time`, so re-running adds nothing. To refresh a pair+TF, **delete its
> `TS_events_*` and `TS_outcomes_*` from `Common\Files` first**, then COLLECT. If you
> skip this after fixing the engine you will train on stale/dead-feature rows — the
> single most common cause of "the gate made things worse."

## Step 2 — VALIDATE  *(Ladder 1 — `rrm_validate.py`)*  ← NEW
- No MT5 switches. Terminal: `python3 rrm_validate.py`  (self-test: `--smoke`)
- It reads the SAME events+outcomes files, then for each pair+TF prints:
  - **FEATURE HEALTH** — flags any DEAD (constant / all-zero) feature. If you see one,
    stop: delete + re-COLLECT (Step 1). A dead column means the data is stale/pre-fix.
  - **B vs Q labels** — B = realized BE-or-profit (the go/no-go label); Q = signal-only
    at a realistic R barrier (isolates TE-signal quality). The Q-vs-B gap tells you
    "bad signal" vs "good signal my exits give back."
  - **CPCV + Deflated Sharpe + PBO** — the honest verdict: **SHIP** only if the gate
    beats baseline across many purged OOS paths (Deflated Sharpe > 0.95, PBO < 0.5).
- **Train only the pairs marked SHIP.** A pair that fails here should not get a model.

## Step 3 — TRAIN  *(Ladder 2 — `rrm_meta.py`)*
- No MT5 switches. Terminal: `python3 rrm_meta.py`
- Joins events → outcomes on `event_time`, labels win = realized BE-or-profit (B),
  runs a purged **holdout + PSR** sanity read, and writes `MetaModel_RRM_ORG_<SYM>_<TF>.csv`
  into `MQL5\Files`. It now **drops any dead feature** and prints an honest
  SHIP-candidate / DO-NOT-SHIP line — but the authoritative pass/fail is Step 2.
- Idempotent: a pair whose model is newer than its data is skipped (`--force` to retrain).

## Step 4 — GATE  *(Ladder 3 — EA switch)*
- `Inp_META_Enabled = true`, `Inp_META_LogFeatures = false`
- Run each pair+TF. Each chart auto-loads its own model (`_Symbol`+`_Period`).
- Journal says `META: loaded …`. Compare gated vs. ungated numbers.
- To undo completely: delete the model file, or set `Inp_META_Enabled = false`.

---

## What changed vs v4.1
- **Ladder 1 is now in the loop** as Step 2 (`rrm_validate.py`): COLLECT → **VALIDATE**
  → TRAIN → GATE. Train only the passers.
- **The trainer is honest now.** `rrm_meta.py` does a purged *holdout* + *PSR* (not
  "deflated Sharpe"); the real CPCV / Deflated Sharpe / PBO live in Step 2. It also
  drops dead features and warns you to re-collect.
- Everything else is identical to v4.1: two switches, `Common\Files` locations, the
  delete-then-re-COLLECT rule, one model per pair+TF+preset.

## Where files live (no copying, no `--archive`)
- Events + outcomes → **`Common\Files`** (shared, durable). Both scripts search here first.
- Model → **`MQL5\Files`** (the EA reads it there).
- There is **no** archive step and **no** `Files_SEA/` folder. See
  `README_META_GATE.md §4a` for the authoritative detail.
