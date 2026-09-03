# xema-analysis — the ONE folder for XEMA parameter sweeps

Put this whole folder in the repo at:  `_SEA-Scripts/xema-analysis/`
(and DELETE the old `_SEA-Scripts/xema-harness/` folder — it was the broken tool.)

The price CSVs live in the repo's `Files/` folder already — leave them there.

## What's in here (8 files — this is all you need)

| file | what it is |
|---|---|
| `PROMPT_FRAMEWORK_v03.md` | paste this into a new chat to run a sweep conversationally |
| `xema_engine_260903-01.py` | the VERIFIED engine (matches the real EA 20/21 trades) |
| `xema_report2.py` | two-halves per-knob report generator (the main report) |
| `xema_sweep.py` | quick single-config / one-knob helper |
| `XEMA_CONFORMANCE_REPORT.md` | proof the engine is faithful + its honest limits |
| `fixtures/conformance_EURUSD_H1_260101-260831.csv` | 21 real EA trades (the answer key) |
| `fixtures/oracle_EURUSD_H1_260101-260831_rejects.csv` | per-bar EA decisions (debug aid) |
| `fixtures/mt5_EURUSD_H1_20260902.log` | the raw MT5 test log (source of truth) |

## How to run a report (two ways)

**Conversational (easiest):** new chat → paste `PROMPT_FRAMEWORK_v03.md` → fill the
bottom line `Pair: EURUSD  Timeframe: H1  Span: 2015-2025  Spread: 0.8p` → get report.

**Direct command:** from this folder,
```
python3 xema_report2.py \
    --early  ../../Files/EURUSD_H1_201501020900_201912312200.csv \
    --recent ../../Files/EURUSD_H1_202001020600_202512312300.csv \
    --pip 0.0001 --spread 0.8 --label "EURUSD H1" --out report_EURUSD_H1.md
```
- pip: FX `0.0001` · JPY `0.01` · gold `0.1`
- point --early/--recent at the two CSVs in `Files/` for the pair/TF you want

## Prove the engine still matches the EA (do once per repo HEAD)
```
python3 xema_engine_260903-01.py --data <EURUSD_H1 file covering 2026-01..08> \
    --verify --conf fixtures/conformance_EURUSD_H1_260101-260831.csv \
    --oracle fixtures/oracle_EURUSD_H1_260101-260831_rejects.csv
```
Expect: matched entries 20/21, SL exact, exit reason 20/21. If it fails, the engine
drifted from the current code — fix before trusting any report.

## Honest limit
net-R RANKS settings (find the robust config); it is NOT EA profit to the cent
(MT5's ADX isn't bit-reproducible; H1 candles hide intrabar tick fills). Use it to
shortlist settings, then confirm the winners in the real MT5 tester.

---

## What to delete from the repo (old / broken / duplicates)
- the whole old `_SEA-Scripts/xema-harness/` folder (broken harness, patches, bundles,
  `(1)`/`(2)` duplicates) — replaced by this folder
- optional: the loose old sweep scripts in `_SEA-Scripts/` root
  (`gbp_map.py`, `jpy_map.py`, `gold_map.py`, `htf_sweep.py`, `ema_swing_sweep.py`,
  `sweep_psar.py`, `multiyear_xema.py`, `xema_test*.py`, `xema_decade_cost.py`,
  `xema_voter_test.py`, `xema_divergence_test.py`, `m5_*session.py`) — these were the
  drift-prone reconstructions this engine replaces. Harmless to keep, but they're the
  clutter you noticed.

Keep untouched: the EA files (`SEA_*.mqh`, `SimpleEA_*.mq5/.ex5`), `Files/` (CSVs),
and the `_SEA-Scripts/RRM/` MT5 scripts (unrelated to this).
