# META-GATE — README (plain-language)

An optional machine-learning **filter** for the RRM EA. It does not change your
trading rules. It watches your signals, learns which market *contexts* your
system loses in (e.g. ranging markets for a trend system), and skips trades in
those contexts. That is all it does.

**There is no LLM / ChatGPT here.** "Learn" = a small statistics script (logistic
regression) finds a pattern in a spreadsheet. Think "Excel with a formula," not AI.

---

## 1. The idea in three sentences

1. Your EA plays history and, for every signal it fires, writes down the market
   conditions at that moment (a spreadsheet).
2. A Python script reads that spreadsheet, checks from price data whether each
   signal won or lost, and learns "signals in *these* conditions usually lose."
3. Back in the EA, when a new signal fires, it checks what Python learned and
   **skips the ones that usually lose** — nothing else changes.

The EA and Python **never run at the same time** and are **not connected live**.
They only pass CSV files back and forth.

---

## 2. What it does NOT do (important)

- It does **not** optimize or change your TS / TE / SL / TP rules or their values.
- It does **not** send settings back to the EA. The only thing Python writes is a
  short list of numbers (weights).
- It can **only remove or shrink** a trade your rules already approved. It can
  never create a trade your rules rejected, move an SL, or edit an input.
- The "optimize my parameters" job is a *different* tool — the MT5 Strategy Tester
  optimizer. This is a filter that sits on top of already-tuned rules.

---

## 3. The files

| File | Where it lives | Role |
| --- | --- | --- |
| `SEA_MetaGate.mqh` | `MQL5\Include\RRMS\` | The whole feature+gate module. Self-contained. |
| `SEA_TradeExecutor.mqh` | `MQL5\Include\RRMS\` | Your file, with 2 small edits (include + gate around `ExecuteTrade`). |
| `rrm_meta.py` | your repo `scripts/` | The trainer. Runs on your Mac, not inside MT5. |
| `rrm_meta.config` | next to `rrm_meta.py` | Stores the `Common\Files` path + defaults so you set them once. |

**One-time setup:** copy `SEA_MetaGate.mqh` into `MQL5\Include\RRMS\`, replace
`SEA_TradeExecutor.mqh` with the patched one, compile. Nothing changes yet —
everything is OFF by default.

---

## 4. The CSV files (read vs write)

They do **not** all live in one folder — and under macOS+Wine that matters, because
the Strategy Tester gives each run its own throwaway `MQL5\Files\` sandbox.

| File | Made by | Read by | Lives in | Naming |
| --- | --- | --- | --- | --- |
| `PAIR_TF_FROM_TO.csv` (price bars) | you already have it | Python | `MQL5\Files\` (or your `rrm_meta.config` path) | e.g. `USDJPY_M15_240101_241231.csv` |
| `TS_events_<PRESET>_<SYMBOL>_<TF>.csv` (signal log) | **EA** (collect run) | Python | shared **`Common\Files`** (durable, `FILE_COMMON`) | e.g. `TS_events_RRM_ORG_EURUSD_M1.csv` |
| `TS_outcomes_<PRESET>_<SYMBOL>_<TF>.csv` (realized exits) | **EA** (collect run, on each trade close) | Python | shared **`Common\Files`** (durable, `FILE_COMMON`) | joined to the events log on `event_time`; provides the **B** realized label |
| `MetaModel_<PRESET>_<SYMBOL>_<TF>.csv` (the model) | **Python** | **EA** (gated run) | terminal `MQL5\Files\` (EA reads non-common) | e.g. `MetaModel_RRM_ORG_EURUSD_M1.csv` |

The signal log goes to **`Common\Files`** on purpose: a non-common write lands in the
per-run `…\Tester\Agent-*\MQL5\Files\` sandbox, which the tester wipes each run — so a
sequence of pair+TF collects would keep only the last. `Common\Files` is shared and
survives, so they accumulate (restored to `FILE_COMMON` 2026-07-31; the 2026-07-30
non-common detour is what caused the "only the last file" symptom). The model is read
non-common because the tester seeds each agent from the terminal `MQL5\Files\` (where
Python writes it) at run start. `rrm_meta.py` auto-discovers all three — it searches
`Common\Files` **and** every `MQL5\Files`.

### 4a. Where files live & the re-collect rule — authoritative version (read this)

Current reality of the code (it has changed across versions; this is the source of
truth — trust it over any older notes):

- **Events + outcomes → `…\MetaQuotes\Terminal\Common\Files\`**, every run, via
  `FILE_COMMON`. One fixed folder. On macOS/Wine:
  `~/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/users/<user>/AppData/Roaming/MetaQuotes/Terminal/Common/Files/`.
- **Config / report files (`SEA_LiveConfig_*`) → the tester `MQL5\Files`** sandbox — a
  *different* folder. Looking there for the events CSV is the usual "it's missing"
  confusion; it isn't missing, it's in `Common\Files`.
- **No `--archive` step and no `Files_SEA\events\` anymore.** Those were a workaround for
  the old sandbox-wipe, removed once the write moved to `FILE_COMMON`. If your notes
  mention them, the notes are stale. You copy nothing by hand.
- **The trainer finds files itself** (`Common\Files` searched first, path hardcoded); you
  never pass a path or run `find` in normal use.
- **Re-collect rule (important):** the events writer **appends and de-dups by
  `event_time`**, so re-running a range already in the file **adds nothing** (by design).
  To re-collect *fresh/corrected* data (after an EA change like the `macd_hist` fix, or
  changed trade management), **delete that pair+TF's `TS_events_*` and `TS_outcomes_*`
  from `Common\Files` first**, then run COLLECT — otherwise you keep the old rows.
- **Every collect prints a summary** (`OnDeinit`):
  `[META] COLLECT SUMMARY: N new events, M new outcomes … (K skipped as already-logged)`
  plus the exact folder. `0 new / K skipped` means "already collected — delete to redo."

---

## 5. How to run — 3 steps

**STEP 1 — Collect (EA writes the signal log).**
EA inputs: `Inp_META_LogFeatures = true`, `Inp_META_Enabled = false`,
`Inp_META_PresetName = RRM_ORG`. Run your normal `PRESET_RRM_ORG` backtest.
→ behaves exactly as today, and drops `TS_events_RRM_ORG.csv`.

**STEP 2 — Train (Python learns).**
Edit `rrm_meta.config` once (put your real `Common\Files` path + pair/TF/dates).
Then: `python3 scripts/rrm_meta.py` and press Enter through the prompts.
→ reads the price CSV + the events CSV, prints results, writes
`MetaModel_RRM_ORG.csv`.

**STEP 3 — Gate (EA uses the model).**
EA inputs: `Inp_META_LogFeatures = false`, `Inp_META_Enabled = true`.
Re-run the backtest and compare to Step 1.
→ To undo completely: delete the model file, or set `Inp_META_Enabled = false`.

**Install Python deps once:** `pip install pandas numpy scikit-learn`

---

## 6. How to read the results

Python prints an out-of-sample block, e.g.:

```
threshold             : 0.560
trades  all -> gated  : 420 -> 250
R-Sharpe all -> gated : 0.31 -> 0.58
```

- **trades all -> gated**: how many trades survive the filter (fewer = pickier).
- **R-Sharpe all -> gated**: risk-adjusted return before vs after the filter, on
  data the model did NOT train on. If gated > all, the filter helped honestly.
- **Ship the model only if gated beat all here.** If not, delete the model file;
  the EA reverts to its exact current behaviour.

Reminder printed by the script: every threshold / feature set you try is a
"trial." The more you try, the more a good number can be luck (the deflated-Sharpe
idea). Do not keep re-rolling until you like the number.

---

## 7. What it looks at (the features)

Computed at the closed signal bar. Two groups:

- **Signal-side** (mirrors your preset, read from live inputs): EMA fan 5/13/34/89,
  MACD 8/13 + CCI 13 (a proxy for DPI momentum), PSAR side/distance, candle body.
- **Ranging / context gauges** (always measured, even though `RRM_ORG` disables
  ADX/BB for voting): ADX, +DI/−DI spread, Bollinger width, ATR, 20-bar volatility,
  RSI, Stochastic, MFI, bar range, spread, hour, day-of-week.

The ranging gauges are the point: they let the model learn "trend signal fired in
a flat/ranging market → skip," **without** enabling those indicators in your rules.

- **RRM-native grades** (2026-08, real engine values via `MetaSetTelemetry`, not
  proxies): `phase` (UNORDERED/EMERGING/TRENDING), `layer_w` / `layer_m` / `layer_s`
  (the Weak/Medium/Strong setup grade from the Oracle Trade-Setups card: +1 pass / 0
  none / −1 contra), `votes_frac` (votes_for ÷ votes_total = signal conviction), and
  `vprr_ratio` (volume recovery/pullback). These are fed straight from `CSignalEngine`'s
  telemetry, so the model learns from RRM's **own** signal grade — the single most
  informative context there is. (The DPI feature is still a MACD+CCI proxy; feeding the
  real DPI histogram is the next enrichment.)

---

## 8. When to re-train (rule of thumb)

A model is a snapshot of ONE configuration. Re-collect (Step 1) + re-train
(Step 2) whenever you change anything that alters which trades fire or how they
turn out:

- change a preset value (EMA period, PSAR, SL/TP logic) → re-train,
- enable/disable an indicator in the preset → re-train (and if you want the new
  indicator as a *feature*, add one line in `MetaBuildFeatures`),
- switch pair, timeframe, or date range → re-train,
- different preset → train a separate model (different `Inp_META_PresetName`).

---

## 9. Honest limits

- The DPI feature is a MACD+CCI **proxy**, not your exact DPI indicator. Fine for a
  context feature; if you ever want the exact DPI value, expose the engine buffer.
  (2026-07-31 fix: the `macd_hist` proxy previously used a hard-coded signal period
  of 1 in the `iMACD` handle, which made the signal line identical to the main line
  so the histogram was **identically 0 on every bar** — a dead feature. It now uses
  the live DPI Red period, so `macd_hist` = Blue − Red as intended. Re-collect.)
- The model can only learn from features in the list. If your true "bad market"
  tell isn't in there, add it and re-train.
- The label ("was this a good trade?") is the **realized outcome of the trade RRM
  actually took** (2026-07-31, "B"): the EA logs each closed trade's real entry,
  real placed SL, exit and net P&L to `TS_outcomes_<PRESET>_<SYMBOL>_<TF>.csv`, and
  the trainer labels **`1` = closed break-even-or-in-profit (net P&L ≥ 0)**, else `0`.
  This is the operator's definition of a good RRM trade and matches de Prado
  meta-labelling (label the primary model's real bet). The old fixed `RR × SL`
  barrier (`Inp_META_LabelRR` / `Inp_META_LabelBars`) mislabelled BE/small-profit
  trades — the strategy's actual edge — as losers, because RRM exits on BE / the
  loss-side ratchet / PSAR and reaches a fixed 2.5R target only ~5% of the time; it
  is retained **only as a legacy fallback** when no `TS_outcomes` file is present
  (e.g. data collected before this change). Re-collect to get realized labels.
- Handles are created lazily, so the first few bars of a backtest may log neutral
  zeros while indicators warm up — negligible over a full run.

---

## 10. One-line mental model

**Your rules decide the trades; the meta-gate watches extra market gauges your
rules ignore, learns from history which conditions kill those trades, and skips
them — the rules themselves never change.**
