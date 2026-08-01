# META-GATE — Run Sequence (the everyday loop)

**What this is:** the step-by-step loop to *use* the meta-gate. It is **not** "the Ladder 2
process." The loop spans two ladders, plus the data step that feeds them:

| Step | What it is | Ladder |
|---|---|---|
| 1 — COLLECT | gather the data (EA writes the files) | — (data step) |
| 2 — TRAIN | build the model (`rrm_meta.py`) | **Ladder 2** |
| 3 — GATE | use the model (EA switch) | **Ladder 3** |

**Ladder 1** (validate — `rrm_validate.py`) is **not built yet**. When it exists it slots in
*before* Step 2: Collect → **validate** → train only the passers → gate.

---

## Two switches (Inputs tab) — the only things you flip
- `Inp_META_LogFeatures` — should the EA write its trades to a file? (on/off)
- `Inp_META_Enabled` — is the filter allowed to skip trades? (on/off)

Everything else — symbol, timeframe, dates, all other inputs — stays the same across the
three steps for a given pair+TF. Across pairs/TFs you change only the chart; filenames keep
them separate automatically.

---

## Step 1 — COLLECT  *(data step)*
- `Inp_META_LogFeatures = true`, `Inp_META_Enabled = false`
- Put up the chart for the pair+TF (e.g. EURUSD M1), run the backtest over your training range.
- **Result — two files per pair+TF**, in `Common\Files`:
  - `TS_events_RRM_ORG_<SYM>_<TF>.csv` — one row per trade **entry** (the features)
  - `TS_outcomes_RRM_ORG_<SYM>_<TF>.csv` — one row per trade **close** (the real result)
- The Journal prints `[META] COLLECT SUMMARY: N new events, M new outcomes … -> <path>`.
- Repeat per pair+TF (change the chart, keep the switches).

## Step 2 — TRAIN  *(Ladder 2 — `rrm_meta.py`)*
- No MT5 switches. Terminal: `python3 rrm_meta.py`
- It auto-finds every events file, **joins it to its outcomes file on `event_time`**, labels
  each trade **win = closed break-even-or-profit** (this is "B"), trains one model per pair+TF,
  and writes `MetaModel_RRM_ORG_<SYM>_<TF>.csv` into `MQL5\Files` (where the EA reads it).
- Prints one summary line per pair+TF. Idempotent: a pair whose model is newer than its data
  is skipped (`--force` to retrain).

## Step 3 — GATE  *(Ladder 3 — EA switch)*
- `Inp_META_Enabled = true`, `Inp_META_LogFeatures = false`
- Run each pair+TF. Each chart auto-loads its own model (`_Symbol`+`_Period`).
- Journal says `META: loaded …`. Compare gated vs. ungated numbers.

---

## The one rule you must remember
The events writer **appends and de-dups by `event_time`** — re-running a range already in the
file adds nothing. **To re-collect a pair+TF (after any EA change, or changed management),
delete its `TS_events_*` and `TS_outcomes_*` from `Common\Files` first**, then run Step 1.

## Where files live (no copying, no `--archive`)
- Events + outcomes → **`Common\Files`** (shared, durable). The trainer searches here first.
- Model → **`MQL5\Files`** (the EA reads it there).
- There is **no** archive step and **no** `Files_SEA/` folder. If your notes mention them,
  the notes are stale. See `README_META_GATE.md §4a` for the authoritative detail.

## When to repeat
Re-collect + re-train a pair+TF only if you change the strategy, that pair's data/dates, or
trade management. Each pair+TF is independent. Honest check before trusting any model: train
past years, gate-test a year you didn't train on (and, once it exists, run Ladder 1 first).
