# HOW TO RUN — XEMA analysis operations guide

> **Run all commands below from the code folder** `_SEA-Scripts/xema-analysis/` (these docs live in `Readme/`, the code lives there). The `../../Files/` paths are relative to the code folder.

Plain, ordered steps: what to run, what each thing tests, and how to add a new pair.
Everything runs on the CSVs already in the repo's `Files/` folder.

---

## The order of operations (always the same)

1. **VERIFY** the engine matches the EA (once per repo HEAD, or after any EA change).
2. **REPORT** — run the sweep for a pair × TF × span → get the settings report.
3. **READ** the report: pick the robust setting, not the biggest number.

That's it. Verify once, then report as many pairs/TFs as you want.

---

## STEP 1 — VERIFY (prove the engine is still faithful)

Run this once after putting the folder in the repo, and again any time the EA
source changes:

```
python3 xema_engine.py \
    --data ../../Files/EURUSD_H1_202512290000_202608282300.csv \
    --verify --conf fixtures/conformance_EURUSD_H1_260101-260831.csv \
    --oracle fixtures/oracle_EURUSD_H1_260101-260831_rejects.csv
```

- **PASS looks like:** `matched entries 20/21 | SL exact 20/21 | exit reason 20/21`.
- **If it passes:** the engine is faithful; reports are trustworthy for ranking.
- **If it fails:** the EA code changed and the engine drifted — do NOT trust reports
  until the engine is fixed to match the new code.

This is the ONLY test that uses the `fixtures/` folder. It's the calibration check.

---

## STEP 2 — REPORT (the actual analysis: pair × TF × span → settings)

Two ways. Both produce the same kind of report.

### Way A — conversational (easiest)
New chat → paste `README_XEMA_PROMPT_FRAMEWORK.md` → fill the bottom line, e.g.
`Pair: USDJPY  Timeframe: H1  Span: 2015-2025  Spread: 0.8p` → get the report.

### Way B — one command
From this folder, point `--early` / `--recent` at the two CSVs for the pair/TF:

```
python3 xema_report.py \
    --early  ../../Files/USDJPY_H1_201501020900_201912312300.csv \
    --recent ../../Files/USDJPY_H1_202001020600_202512312300.csv \
    --pip 0.01 --spread 0.8 --label "USDJPY H1" \
    --out report_USDJPY_H1.md
```

**Pick the right pip and files:**

| pair | `--pip` | H1 early file / recent file (in `Files/`) |
|---|---|---|
| EURUSD | 0.0001 | `EURUSD_H1_201501..` / `EURUSD_H1_202001..` |
| GBPUSD | 0.0001 | `GBPUSD_H1_201501..` / `GBPUSD_H1_202001..` |
| USDJPY | 0.01   | `USDJPY_H1_201501..` / `USDJPY_H1_202001..` |
| XAUUSD | 0.1    | `XAUUSD_H1_201501..` / `XAUUSD_H1_202001..` |

For M15 or M5, swap `_H1_` → `_M15_` / `_M5_` in the filenames. (Data you have:
all 4 pairs in H1, M15, M5.)

`--spread` = your broker's real spread in pips (FX ~0.8, JPY ~0.8, gold ~$0.30 → 3).
Whole decade uses both files; for one half, pass the same file to both, or use the
`xema_sweep.py --from/--to` helper for a single year.

---

## What the report TESTS (every knob it sweeps)

Each row in the report is one setting changed, backtested over both halves. The knobs:

| knob | values swept | what it tests |
|---|---|---|
| entry EMA | 8/21, 13/34, 20/50, 21/55 | trend-cross speed |
| ADX gate | OFF, pct 40/50/60/70 | how strong a trend is required to enter |
| PSAR | OFF, 0.02/0.2, 0.08/0.5 | parabolic-SAR trend filter |
| Bollinger | OFF, period 20/30 | volatility-expansion filter |
| Choppiness (CI) | OFF, thr 55/61.8 | range-vs-trend filter |
| HTF | OFF / ON | higher-timeframe trend agreement |
| swing SL | lookback 34/55/89 | how far back the stop-loss anchor looks |
| take-profit | RR 1.5/2.0/2.5/3.0 | reward target vs the stop |
| session (M5) | all / London+NY / NY | which hours to trade |

The report shows EARLY half, RECENT half, decade total, trade count, and a verdict.

---

## STEP 3 — HOW TO READ IT (the one rule that matters)

- **"consistent ✓"** = positive in BOTH halves → robust, trust it.
- **"lopsided"** = wins one half, loses the other → a regime fit, DON'T trust it,
  even if its decade total is bigger.
- Prefer the consistent setting over the higher-total one. A tempting big number
  that only shows up in 2020–2025 is fitting the recent trend, not a real edge.
- net-R RANKS configs; it is not EA profit to the cent. Confirm the winner you pick
  in the real MT5 tester before trading it.

---

## HOW TO ADD A NEW PAIR/TF to the VERIFY check (optional, for full proof)

The engine is proven on **EURUSD H1** (that's the log we have). Reports on other
pairs/TFs use the same indicator math and are trustworthy for ranking, but if you
want a given pair/TF *proven* the same way:

1. In MT5 Strategy Tester, run SimpleEA with **PRESET_XEMA, default config**, on that
   pair/TF, over a short window (1–2 months), with logging on. Save the log.
2. Extract its trades into a CSV with columns
   `entry_time,direction,sl,exit_time,exit_reason` (same format as the EURUSD one in
   `fixtures/`). Name it `conformance_<PAIR>_<TF>_<dates>.csv`.
3. Run STEP 1 with `--data` = that pair/TF CSV and `--conf` = your new fixture.
4. If it matches, that pair/TF is now proven too. If not, note where it differs.

You don't have to do this to run reports — it's only to extend the formal proof
beyond EURUSD H1.

---

## Quick reference — run a report for each pair on H1, whole decade

```
# EURUSD
python3 xema_report.py --early ../../Files/EURUSD_H1_201501020900_201912312200.csv \
  --recent ../../Files/EURUSD_H1_202001020600_202512312300.csv --pip 0.0001 --spread 0.8 \
  --label "EURUSD H1" --out report_EURUSD_H1.md
# GBPUSD
python3 xema_report.py --early ../../Files/GBPUSD_H1_201501020900_201912312300.csv \
  --recent ../../Files/GBPUSD_H1_202001020600_202512312300.csv --pip 0.0001 --spread 0.8 \
  --label "GBPUSD H1" --out report_GBPUSD_H1.md
# USDJPY
python3 xema_report.py --early ../../Files/USDJPY_H1_201501020900_201912312300.csv \
  --recent ../../Files/USDJPY_H1_202001020600_202512312300.csv --pip 0.01 --spread 0.8 \
  --label "USDJPY H1" --out report_USDJPY_H1.md
# XAUUSD (gold)
python3 xema_report.py --early ../../Files/XAUUSD_H1_201501020900_201912302300.csv \
  --recent ../../Files/XAUUSD_H1_202001020600_202512312300.csv --pip 0.1 --spread 3 \
  --label "XAUUSD H1" --out report_XAUUSD_H1.md
```
(exact filenames: check `ls Files/` — the date suffixes may differ slightly.)

---

## Changing the BASE config for analysis (no code edit needed)

The engine's settings are NOT hardcoded into the logic. `CFG` at the top of
`xema_engine.py` is only the DEFAULT (the as-run XEMA). Every setting is
read as `cfg['...']`, so you change any of them by passing a different `cfg` — the
`.py` file never needs editing.

Three ways to change the base:
1. **Conversational:** the framework asks "confirm or edit the starting config" at
   intake — just state your edits (e.g. "base with ADX off, EMA 8/21").
2. **Command line** (`xema_sweep.py`): `--set adx_percentile=60 --set ema_fast=8`.
3. **In a script:** `cfg = copy.deepcopy(eng.CFG); cfg.update({...}); eng.run(df, cfg)`.

Every XEMA setting is already parameterised (verified against the code
2026-09-03): **19 tunable settings** live in `CFG` — `ema_fast/slow`,
`htf_ema_fast/slow`, `htf_require_phase`, `adx_period/percentile/lookback`,
`bb_period/dev`, `ci_period/ranging`, `psar_step/max`, `swing_lookback/strength`,
`sl_cushion_pips`, `label_rr`, `session_allowed` — **plus 5 on/off toggles** you
pass as overrides (`use_adx`, `use_bb`, `use_ci`, `use_psar`, `use_htf`; each
defaults to ON). `CFG` also holds 6 internal constants that are not tuning knobs
(`pip`, `t_adx`, `adx_refresh_sec`, `emafan_max_pips`, `priceext_atr`,
`priceext_max_atr`). You'd only edit the `.py` if you needed a BRAND-NEW knob that
doesn't exist yet.

**Important — verification caveat:** the 20/21 conformance proof is against the
DEFAULT config (the one the MT5 log used). If you set a different base, you are
still running the same verified ENGINE, but "matches the EA exactly" only strictly
holds for the default. Treat a custom base as trustworthy-for-ranking (same as any
non-default sweep row), and if you want it EA-exact, produce an MT5 log for that
config and re-verify against it.
