# xema-analysis — code

This folder holds the XEMA offline analysis **engine + scripts + fixtures**.
The **documentation lives in the repo's central `Readme/` folder** (same convention
as META), namely:

- `Readme/README_XEMA_ANALYSIS.md` — what this is, context, META distinction, inventory
- `Readme/README_XEMA_HOW_TO_RUN.md` — verify → report → read; every knob; adding a pair
- `Readme/README_XEMA_PROMPT_FRAMEWORK.md` — paste-into-a-new-chat conversational runner
- `Readme/README_XEMA_CONFORMANCE.md` — the 20/21 proof and its honest limits

## Files here
- `xema_engine_260903-01.py` — the verified engine (`run(df,cfg)` + `CFG`)
- `xema_report.py` — two-halves per-knob sweep report
- `xema_sweep.py` — single-config / one-knob helper
- `fixtures/` — conformance CSV + oracle + MT5 log for `--verify`

## Quick start (detail in Readme/README_XEMA_HOW_TO_RUN.md)
```
# 1. prove the engine matches the EA at the current repo HEAD
python3 xema_engine_260903-01.py --data ../../Files/EURUSD_H1_<covers 2026-01..08>.csv \
    --verify --conf fixtures/conformance_EURUSD_H1_260101-260831.csv \
    --oracle fixtures/oracle_EURUSD_H1_260101-260831_rejects.csv     # expect 20/21

# 2. run a report for a pair/TF
python3 xema_report.py --early ../../Files/<PAIR>_H1_2015-19.csv \
    --recent ../../Files/<PAIR>_H1_2020-25.csv --pip <0.0001|0.01|0.1> \
    --spread <pips> --label "<PAIR> H1" --out report_<PAIR>_H1.md
```
