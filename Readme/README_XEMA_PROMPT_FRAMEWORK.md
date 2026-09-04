# SEA — PRESET_XEMA v03 — PAIRS × TF × YEARS analysis (verified-engine edition)

## PASTE THIS WHOLE FILE as your message. Fill in the MY REQUEST line at the bottom.

This is the conversational parameter-sweep framework. You give a Pair / TF / Span /
Spread; it returns a robust, both-halves, per-year settings report with the full
per-knob evidence tables. It is pure Python backtesting on the repo CSVs — it never
runs the EA.

**KEY CHANGE FROM v02:** do NOT reconstruct XEMA from memory or from source this
session. A **verified engine already exists** — `xema_engine.py`
(conformance-checked against the real MT5 log: 20/21 real trades reproduced,
stop-loss + exit-reason exact). USE IT. Rebuilding from scratch is what caused every
prior chat to drift. Attach these files (or pull from repo) and build ON them:
- `xema_engine.py`  — the verified engine (has `run(df, cfg)` and `CFG`)
- `xema_report.py`           — two-halves per-knob report generator (uses the engine)
- `README_XEMA_CONFORMANCE.md` — what "verified" means and its limits
- fixtures/ (conformance CSV + oracle + mt5 log) — to re-prove the engine if HEAD moved

## MINIMAL SETUP (do this first)
1. `git clone https://github.com/msmaciej/RRM_SEA` (or pull); note HEAD. This is for
   the CSV data in `Files/` and the engine files. No README/PDF reading needed.
2. Verify python3 + pandas + numpy.
3. **Re-prove the engine once** at this HEAD before trusting numbers:
   ```
   python3 xema_engine_260903-01.py --data <EURUSD_H1 file covering 2026-01..08> \
       --verify --conf fixtures/conformance_EURUSD_H1_260101-260831.csv \
       --oracle fixtures/oracle_EURUSD_H1_260101-260831_rejects.csv
   ```
   Expect **matched entries 20/21, SL exact, exit reason 20/21**. If it fails, STOP —
   the engine drifted from the current code; fix before sweeping. If it passes, the
   numbers below are trustworthy for RANKING.

## CONVERSATIONAL INTAKE — ask these one at a time, wait for answers
1. **Pair** — any symbol with CSVs in `Files/` (EURUSD / USDJPY / GBPUSD / XAUUSD …).
   Confirm the files exist; print their date spans.
2. **Timeframe** — M5, M15, or H1 (one per chat). NOTE: the engine was conformance-
   verified on **H1**. M15/M5 use the same indicator math but are an extrapolation —
   say so in the card; the ranking is still useful, exact-match is only proven on H1.
3. **Span** — full decade 2015-2025, a range (2020-2025), or a single year. Data is two
   CSVs per TF (2015-2019, 2020-2025); load whichever cover the span.
4. **Spread / cost** — the operator's real spread (else default FX 0.8p, JPY 0.8p
   [pip 0.01], gold ~$0.30 [pip 0.1]). Drives net-R and the verdict.
5. **Starting config** — confirm or edit the defaults below before sweeping.

**Default starting XEMA config** (these are the engine `CFG` defaults, = as-run XEMA):
entry EMA 13/34 · HTF ON single H1 EMAs 13/34 phase-required · ADX ON (period 14,
percentile 50, lookback 100) · BB-widening ON (period 20) · CI ON (period 14, thr
61.8) · PSAR ON (0.08/0.5) · swing SL lookback 55, cushion 0 · TP = 2.5R fallback ·
session hours 1-21. (Voter on/off via `use_adx/use_bb/use_ci/use_psar/use_htf`.)

Only after all five confirmed: begin the sweep.

## THE SWEEP (for the confirmed pair × TF × span)
Sweep EACH knob on a grid, others held at current best; THEN confirm the COMBINED
winner (per-knob winners don't always stack). Report NET-R after cost, PER YEAR,
with trade count n, for every config. Use `xema_report.py` for the standard
two-halves per-knob tables, then extend the grids below as needed via `--set`/`run()`:

- EMA entry: 8/21, 13/34, 21/55, 13/55, 8/34   (`ema_fast`,`ema_slow`)
- ADX: on/off (`use_adx`); period 10/14/20 (`adx_period`); percentile 40/50/60/70
  (`adx_percentile`); lookback 100 (`adx_lookback`)
- BB: on/off (`use_bb`); period 14/20/30 (`bb_period`) — deviation is inert for the
  widening gate (std rising is unaffected by the 2.0 multiplier); verify, only period matters
- CI: on/off (`use_ci`); threshold 55/61.8/68 (`ci_ranging`)
- PSAR: on/off (`use_psar`); step 0.02/0.03/0.05/0.08/0.10/0.12 (`psar_step`) × max
  0.2/0.5 (`psar_max`)
- HTF: on/off (`use_htf`); EMA periods 8/21, 13/34, 20/50 (`htf_ema_fast/slow`)
- Swing SL lookback: 20/34/55/89 (`swing_lookback`)
- Exit / target: TP multiple 1.0/1.5/2.0/2.5/3.0 (`label_rr`)   [engine exit = swing
  SL vs label_rr TP race; reverse-cross is RC-blocked in the as-run per the log]
- M5 only: session windows ALL / London+NY (8-20) / NY (12-21) via `session_allowed`
  — STRUCTURAL choices, not fitted to in-sample green hours.
Widen any grid whose best value sits at a boundary.

**OUTPUT REQUIREMENT — show the evidence, not just the verdict.** For EVERY knob,
print its FULL grid: one row per value, columns = EARLY-half netR, RECENT-half netR,
decade total, n, ROBUST? (both halves +ve). The settings card at the end REFERENCES
these tables; it does not replace them. The operator must SEE each setting's influence.

## METHOD (mandatory — robustness study, not a max-finder)
1. **Split-half**: evaluate 2015-2019 and 2020-2025 SEPARATELY, side by side. A setting
   is robust only if positive/best in BOTH halves. A higher decade TOTAL that is
   lopsided across halves = regime fit → REJECT ruthlessly.
2. Per-year net-R + n for every config.
3. Cost always applied; state the spread; re-run at the operator's real number.
4. One knob at a time, THEN combined-confirm — run the assembled config to verify the
   pieces stack.
5. Overfitting guard: H1 ~40-80 trades/yr; prefer the CONSISTENT setting over the
   higher-total one. Never tune on 2025 alone.
6. **Trust the verified engine, don't rebuild it.** It is authoritative for RANKING
   where `--verify` passed at this HEAD. Do NOT hand-reconstruct indicators — that
   reintroduces drift. Honest limits (from the conformance report): net-R RANKS
   configs; it is NOT EA P/L to the cent, because MT5's iADX isn't bit-reproducible
   and H1 candles hide intrabar tick fills. State this in the card.

## DELIVERABLE
One "settings card" for the confirmed pair × TF × span: the robust optimum with
both-halves, after-cost, per-year evidence, a clear viable / not-viable verdict, and
the note "engine 260903-01, verified 20/21 vs EA @ HEAD <hash>; ranks configs, not
cent-exact P/L". Plus the full per-knob evidence tables. Do NOT present a lopsided
in-sample maximum as an "optimum".

## PRIOR-STUDY CONTEXT (baseline; start above it)
Coarse on/off map from earlier sessions (treat as hypotheses to re-confirm with the
verified engine, NOT as facts — they were made with the un-verified reconstruction):
EURUSD viable M15/H1, ADX ON helped, CI-on helped. USDJPY viable H1/M15 but ADX OFF.
GBPUSD H1 only, ADX OFF. XAUUSD marginal H1, negative M15/M5. Robust exit = the
swing-SL/TP structure; wide fixed targets were regime fits. Expect a FLAT surface —
most "improvements" are regime fits; big wins came from structural choices (which TF,
ADX on/off, TP level). Prioritise ADX period/percentile, HTF choice, TP level per pair.

## MY REQUEST (fill in — one cell only)
Pair: [e.g. EURUSD]  Timeframe: [e.g. H1]  Span: [e.g. 2015-2025]
Spread: [e.g. 0.8p / my broker's real number]  Starting config: [default, or edits]
