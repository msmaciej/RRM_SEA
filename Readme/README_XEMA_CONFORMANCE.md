# PRESET_XEMA engine — conformance report

**Deliverable:** `xema_engine_260903-01.py` — a standalone Python reimplementation of the
MT5 EA preset **PRESET_XEMA**, built to `SEA_ENGINE_SPEC.md` and checked against SEA source
(HEAD `b0244b7`), the real MT5 test log, and the 21-trade conformance CSV.

## Result vs the 21 real EA trades (EURUSD H1, Jan–Aug 2026)

| Check | Score |
|---|---|
| Entries reproduced (bar + direction) | **20 / 21** |
| Stop-loss exact to 5th decimal | **20 / 20** matched |
| Exit reason (SL vs 2.5R TP) | **20 / 20** matched |
| Exit **price** | exact on all 20 |
| Exit **time** inside the EA's exit candle | 17 / 20 |
| Oracle per-bar decisions | 100 / 113 |

The three exit-time exceptions (2026-04-16, 2026-04-21, 2026-05-19) are the spec's known
ceiling: the EA's stop/target was touched on an **intrabar tick** that an H1 candle can't
show, so the engine books the *same level and reason* one or more bars later. Price, level
and reason still match — only the minute differs.

## The one missing trade (2026-03-25) — honest cause

It is masked by a single **phantom** long at 2026-03-19: on that volatile bar the engine's
reproduced MT5 `iADX` reads ≈29 where the real terminal reads below the ~22 percentile
threshold, so a REJECT flips to ACCEPT and the phantom holds the one position slot through
2026-03-25. Every voter *except* ADX passes cleanly there, and MT5's `iADX` is not
bit-reproducible from the spec alone (verified: per-bar-DI exponential smoothing is the best
of the variants tried, 85/113 on raw ADX labels; SMMA and DM/TR-smoothed variants are worse).
The same ADX residual explains the other 9 phantoms and the 13 oracle disagreements — but
those 9 sit in gaps and do **not** displace any real trade.

## What's faithful (locked to source + log)

- Config = as-run XEMA: EMA 13/34, HTF H1 phase-required, ADX(14) DYNAMIC_PERCENTILE(50,
  lookback100, 4h refresh, static-fallback 20), BB(20,2.0) widening, CI(14)<61.8,
  PSAR(0.08/0.5) dot-only, SLMode SWING(lookback55, cushion0), TP fallback = entry±2.5·SL_dist,
  CloseOnReverse effectively off (AllowFlip=false), silent F-filters EmaFan(60p) + PriceExt(2.5·ATR14).
- Bar mapping (empirically pinned, 21/21 fills + 90/92 rejects): cross at bar *x* →
  signal/vote bar *x+1* → **fill bar *x+2***. SL = swing fractal(strength-2) computed **at the
  fill bar**; R and 2.5R TP off the fill price.
- 5 unanimous voters (MTF, ADX, PSAR, BB, CI) with the EA's exact percentile math and `adx>=thr`.
- Execution gates: session VETO on the fill-bar hour (allowed 1–21), RC 6% cap modelled as a
  sequential single position (reproduces all 3 RC vetoes and every non-overlap in the log).
- Indicators reproduce MT5 `iMA/iADX/iSAR/iBands` + SEA's inline `CalculateCI`.

## Bottom line

The engine is **faithful for ranking / sweeping knobs** — direction, entry bar, stop, target,
and exit reason match the live EA on 20 of 21 trades to the 5th decimal. It will **not**
match EA P/L to the cent, because (a) MT5's `iADX` can't be cloned bit-for-bit from the spec
and (b) intrabar tick fills can't be recovered from H1 candles. Both limits were called out in
the spec up front. **Do not** begin the knob sweep expecting cent-exact P/L; use it to compare
configs by trade structure and rank.

## Run it

```
python3 xema_engine_260903-01.py --data <MT5_H1.csv> \
    --verify --conf <conformance.csv> --oracle <oracle_rejects.csv>
```
Import `run(df, cfg)` for sweeps; `CFG` holds every knob (e.g. `adx_percentile`: the value that
best matches the EA's realized ADX decisions is ~55–60, which drops phantoms 10→5 while keeping
20/21 — a useful calibration knob, though 50 is the faithful as-run setting).
