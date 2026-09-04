# xema-analysis — offline parameter optimizer for the SEA "XEMA" preset

**Repo location:** `_SEA-Scripts/xema-analysis/`
**Last audited:** 2026-09-03 · engine `xema_engine_260903-01.py` · last verified vs EA @ source HEAD `b0244b7`
(the repo HEAD moves over time — this is the commit the 20/21 proof was run against; **always re-run `--verify` at the current HEAD** before trusting reports, per §4.)

---

## 1. What this folder IS (read this first — full context, no prior knowledge assumed)

The SEA EA (`SimpleEA_v1-05`, sources `SEA_*.mqh`) has several strategy **presets**.
**XEMA** is one of them — a trend-following preset: it enters on an EMA cross,
confirmed by a stack of filters (higher-timeframe agreement, ADX trend strength,
PSAR, Bollinger, Choppiness), places a swing-based stop, and exits at a stop or a
reward-multiple target. Its exact rules live in `SEA_Presets.mqh` (the `PRESET_XEMA`
block) + `SEA_SignalEngine.mqh` + `SEA_TradeExecutor.mqh`.

**The problem this folder solves:** to answer "does XEMA make money on this pair /
timeframe / period, and which settings are best?", you'd normally run the EA in the
MT5 Strategy Tester once per setting — slow, and one setting at a time. This folder
is a **Python reimplementation of XEMA** that runs the same logic offline on the
price CSVs in `Files/`, so you can sweep dozens of settings in seconds and get a
report.

**The catch, and the safeguard:** a Python reimplementation can DRIFT from the real
EA and give wrong numbers. So the engine here is **conformance-checked**: it is
proven to reproduce a real MT5 test log (EURUSD H1: 20 of 21 real trades, exact
stop-loss and exit reason). The `fixtures/` folder holds that proof, and the
`--verify` command re-checks it. **Trust the reports only when `--verify` passes at
the current code HEAD.**

**Honest limit:** the reports RANK settings (find the robust config); they are NOT
the EA's profit to the cent. Two unavoidable reasons: MT5's built-in ADX can't be
cloned bit-for-bit, and H1 candles hide intrabar tick fills. Use this to shortlist
settings, then confirm the winner in the real MT5 tester before trading it.

---

## 2. What this is NOT — how it differs from SEA META (`SEA_MetaGate.mqh` / `rrm_meta.py`)

These are easy to confuse because both involve "analysis" and Python. They are
completely different things:

| | **xema-analysis (this folder)** | **META (`SEA_MetaGate.mqh`, `rrm_meta.py`)** |
|---|---|---|
| What it is | An offline **parameter optimizer / backtester** | An **ML "second opinion" gate** built into the live EA |
| Question it answers | "Which XEMA *settings* are best for this pair/TF?" | "Should the EA *take THIS specific trade* right now?" |
| When it runs | Offline, on historical CSVs, when you research | Live, inside the EA, on every candidate signal |
| How it works | Replays XEMA rules over price data, sweeps knobs | Logs features -> trains a logistic-regression model -> the EA scores each signal and skips low-confidence ones |
| Output | A settings report (net-R per config, per year) | `MetaModel_*.csv` the EA loads to filter/size trades |
| Changes the EA? | No — pure research, never touches the EA | Yes — optional runtime filter (`Inp_META_Enabled`) |
| Its files | this folder | `SEA_MetaGate.mqh`, `_SEA-Scripts/rrm_meta*.py`, `rrm_validate.py`, `TS_events_*`, `MetaModel_*` |

In one line: **META decides *which trades to skip* while the EA runs; xema-analysis
decides *which settings to run* before you deploy.** They can even be combined — you
optimize settings here, then META filters individual trades live — but they are
separate tools with separate code.

---

## 3. Inventory — every file in this folder (10 files, audited 2026-09-03)

| file | what it is |
|---|---|
| `Readme/README_XEMA_ANALYSIS.md` | this file — what the folder is, context, META distinction, inventory |
| `Readme/README_XEMA_HOW_TO_RUN.md` | step-by-step ops: verify -> report -> read; what each knob tests; adding a pair |
| `README_XEMA_PROMPT_FRAMEWORK.md` | paste into a new chat to run a sweep conversationally (Pair/TF/Span/Spread) |
| `README_XEMA_CONFORMANCE.md` | the proof the engine is faithful (20/21) and its honest limits |
| `xema_engine_260903-01.py` | THE ENGINE — the verified XEMA reimplementation; `run(df,cfg)` + `CFG` |
| `xema_report.py` | main report: two-halves (2015-19 vs 2020-25) per-knob sweep table |
| `xema_sweep.py` | lighter helper: single config or one-knob, with `--from/--to` year filter |
| `fixtures/conformance_EURUSD_H1_260101-260831.csv` | 21 real EA trades (the answer key for `--verify`) |
| `fixtures/oracle_EURUSD_H1_260101-260831_rejects.csv` | per-bar EA accept/reject decisions (debug aid) |
| `fixtures/mt5_EURUSD_H1_20260902.log` | the raw MT5 test log these fixtures were extracted from |

The price data (CSVs) is NOT here — it's in the repo's `Files/` folder, shared by
everything. Reports read from there.

---

## 4. How to use it (summary — full detail in `Readme/README_XEMA_HOW_TO_RUN.md`)

1. **Verify** the engine still matches the EA (once per code HEAD):
   ```
   python3 xema_engine_260903-01.py --data ../../Files/EURUSD_H1_202512290000_202608282300.csv \
       --verify --conf fixtures/conformance_EURUSD_H1_260101-260831.csv \
       --oracle fixtures/oracle_EURUSD_H1_260101-260831_rejects.csv
   ```
   Expect `20/21`. If it fails, the EA changed and the engine must be re-checked
   before any report is trusted.

2. **Report** a pair/TF/span (conversationally via `README_XEMA_PROMPT_FRAMEWORK.md`, or):
   ```
   python3 xema_report.py --early ../../Files/<PAIR>_H1_2015-19.csv \
       --recent ../../Files/<PAIR>_H1_2020-25.csv --pip <0.0001|0.01|0.1> \
       --spread <pips> --label "<PAIR> H1" --out report_<PAIR>_H1.md
   ```

3. **Read** it: prefer **consistent** (positive in both halves) over a bigger
   **lopsided** total (a regime fit). net-R ranks; confirm winners in MT5.

---

## 5. Repo hygiene — what to keep / delete

- **DELETE** the old `_SEA-Scripts/xema-harness/` folder — an earlier, un-verified
  version (broken; full of duplicates/patches). This folder replaces it.
- **Optional delete:** loose old sweep scripts in `_SEA-Scripts/` root (`gbp_map.py`,
  `jpy_map.py`, `gold_map.py`, `htf_sweep.py`, `ema_swing_sweep.py`, `sweep_psar.py`,
  `multiyear_xema.py`, `xema_test*.py`, `xema_decade_cost.py`, `xema_voter_test.py`,
  `xema_divergence_test.py`, `m5_*session.py`) — drift-prone reconstructions this engine
  replaces.
- **KEEP untouched:** the EA (`SEA_*.mqh`, `SimpleEA_*`), `Files/` (CSVs), META files
  (`SEA_MetaGate.mqh`, `_SEA-Scripts/rrm_meta*.py`, `rrm_validate.py`) — META is a
  separate tool (see section 2), and `_SEA-Scripts/RRM/` (unrelated MT5 scripts).

---

## 6. Provenance
- Engine: `xema_engine_260903-01.py`, built to `SEA_ENGINE_SPEC.md`, verified against
  SEA source HEAD `b0244b7` and the MT5 log in `fixtures/`.
- Conformance: EURUSD H1 = 20/21 trades, SL + exit-reason exact. Other pairs/TFs use
  the same indicator math (trustworthy for ranking) but are not separately log-verified
  yet; see `Readme/README_XEMA_HOW_TO_RUN.md` section "add a new pair" to extend the proof.

---

## 7. Docs-vs-code audit (2026-09-03)

Every factual claim in these docs was checked against the engine code (the same way
the META docs are maintained). Results:

- **20/21 conformance** — verified: the engine prints `matched 20/21 | SL exact 20/21
  | exit reason 20/21` at the fixture. ✓
- **Voter on/off toggles** (`use_adx/bb/ci/psar/htf`) — real in code
  (`xema_engine_260903-01.py`, `cfg.get('use_*', True)`), default ON. ✓
- **Report sweeps EMA/ADX/PSAR/BB/CI/HTF/swing/RR/session** — confirmed in
  `xema_report.py`. ✓
- **Knob count** — corrected 2026-09-03: `CFG` has 25 keys = **19 tunable settings +
  6 internal constants**, plus **5 on/off toggles** passed as overrides. (An earlier
  draft said "22 knobs" — that was wrong; fixed in `Readme/README_XEMA_HOW_TO_RUN.md`.)
- **File inventory** — 10 files listed = 10 on disk. ✓
- **Verified-HEAD** — `b0244b7` is the commit the proof was run against; it remains in
  repo history, but the live HEAD moves, so the docs instruct re-verifying at the
  current HEAD (§4 / HOW_TO). ✓

Known honest limits (unchanged): net-R ranks configs, it is not cent-exact EA P/L
(MT5 iADX not bit-reproducible; H1 candles hide intrabar tick fills); conformance is
proven on EURUSD H1 only.
