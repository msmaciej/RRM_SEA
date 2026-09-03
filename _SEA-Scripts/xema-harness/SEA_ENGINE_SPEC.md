# PRESET_XEMA — exact engine spec (from SEA source @ HEAD b0244b7)

This is the ground truth for building a faithful Python engine. Everything below
was read from the EA source and confirmed against the real MT5 log
(`fixtures/mt5_EURUSD_H1_20260902.log`, EURUSD H1, Jan–Aug 2026). Build the Python
to THIS, then verify it reproduces the 21 trades in
`fixtures/conformance_EURUSD_H1_260101-260831.csv`.

The whole point: get the indicator MATH equal to SEA's, and the entry/management/
exit logic follows. Then any knob-sweep (SL/trail/PSAR/EMA/ADX/RR…) run through the
faithful engine is trustworthy for "is this preset profitable on this pair/TF/
period, and how do settings change it".

---

## CRITICAL: indicators are MT5 built-ins, not hand-rolled

SEA reads four indicators from MT5 built-in handles. To match SEA, the Python must
reproduce the **MT5 built-in** algorithm for each — bit-for-bit, including seeding/
warmup. A generic pandas/Wilder version is NOT enough (measured: harness ADX vs
MT5-style ADX differ by up to 17.8 in warmup and ~1.3 at the first trade bar —
enough to flip a trade across the threshold).

| Indicator | SEA source | MT5 call | Python must match |
|---|---|---|---|
| EMA (entry + HTF) | `iMA` handle | `iMA(sym, TF, period, 0, MODE_EMA, PRICE_CLOSE)` | MT5 iMA EMA (seed = SMA of first `period`, then EMA recursion) |
| PSAR | `iSAR` handle | `iSAR(sym, TF, step, max)` | MT5 iSAR (its exact init: first SAR from first two bars, EP/AF rules) |
| Bollinger | `iBands` handle | `iBands(sym, TF, period, 0, dev, PRICE_CLOSE)` | MT5 iBands (SMA ± dev·stdev, population stdev) |
| ADX | `iADX` handle | `iADX(sym, TF, period)` | MT5 iADX (see ADX section — seeding matters) |
| Choppiness (CI) | inline `CalculateCI()` | none (their own formula) | read `CalculateCI` in SignalEngine and copy exactly |

Config for the logged run: EMA 13/34, PSAR step 0.08 / max 0.5, BB 20/2.0,
CI period 14, ADX period 14.

---

## ADX gate — the main bug, now fully specified

Three things were wrong in the old harness; all three must be fixed:

1. **ADX value**: use MT5 `iADX` math (period 14), NOT pandas ewm. MT5 iADX:
   - +DM/-DM/TR per bar (standard directional movement)
   - Wilder smoothing seeded by simple SUM of first `period` (not ewm-from-bar-0)
   - +DI=100·smDM+/smTR, -DI=100·smDM-/smTR, DX=100·|+DI - -DI|/(+DI + -DI)
   - ADX seeded at bar `2·period-1` as the **average of the first `period` DX
     values**, then Wilder-recursed: `ADX = (ADX_prev·(period-1) + DX)/period`

2. **Percentile buffer is per-EVALUATED-bar, not per-bar** (SEA `UpdateADXHistory`,
   `Check_ADX`): the ADX buffer is appended ONLY on bars where `Check_ADX` runs —
   i.e. bars that reached the ADX vote (after cross+bias). The old harness built the
   percentile over EVERY bar → wrong sample population → wrong threshold. The Python
   must replay bar-by-bar and push to the buffer only on evaluated bars.
   - buffer max size = `ADX_Lookback` (100); when full, drop-oldest FIFO.
   - `CalculateADXPercentile(p)`: if size<10 → return static `T_Adx`; else sort,
     `index=(p/100)·(size-1)`, linear-interpolate between floor/ceil. (This
     interpolation formula the old harness already had right.)

3. **Threshold is cached/stale**: recomputed only when the buffer fills OR
   `ADX_PercentileRefreshSec` elapses — NOT every bar. Between refreshes the gate
   uses the last cached threshold. The old harness recomputed every bar.

Gate test: `pass if adx >= threshold` (inclusive).

---

## Entry (STRAT_2EMA_CROSS_EMA, EXIT_PROFILE_SIMPLE)

Fresh EMA cross on the closed signal bar `i` vs `i-1`:
`long = ef[i-1]<=es[i-1] and ef[i]>es[i]`; short symmetric. No continuation branch.
Fill on next bar `i+1` at open + spread. Signal bar = fill bar − 1.

Voters are UNANIMOUS — all 5 must pass (confirmed: EA never rejects at 5/5, often
at 4/5): HTF, ADX, PSAR, BB(widening), CI(not-ranging). Single HTF here (TF1=H1,
EMA 13/34, phase-required). PSAR pass = SAR on correct side of price. BB pass =
bandwidth now > prev. CI pass = choppiness < ranging threshold.

Also silent gates seen in the log dying in `EvaluateF` (no reject line): possible
EmaFan / PriceExt / Climax sub-filters — check whether enabled in the as-run and
implement if so (2 phantom harness trades trace here).

---

## Stop loss — swing, off-by-one FIX

SEA `GetSwingLevel` = fractal strength-2, nearest-first, over `SwingLookback` (55),
fallback iLowest/iHighest. **Key fix**: SEA computes it at the FILL bar (shift 0 =
fill bar), so scan candidate bars relative to `i+1`, NOT the signal bar `i`. Old
harness passed `i` → off by one → wrong on trades where a fractal sits at i-2
(trades 8 & 12). With `eval_i = i+1`, all 21 SLs match the EA's `[TE]`-logged SL.
Cushion = 0.0 pips (logged). No min floor applied in this config.

Verified: 17/21 SLs were already exact; the off-by-one fixes the other 2; the
remaining were the phantom-trade entries, not SL math.

---

## Exit — the REAL preset stack (not a made-up FIX/TRAIL)

Implement the actual configured exit and let the pieces interact:
- Initial swing SL (above).
- **TP = 2.5R** fallback (`Inp_META_LabelRR=2.5`): when TP=0, TP = entry ± 2.5·SL_dist.
- Trail/BE per the preset inputs (as-run had TrailMode set — read the exact trail/BE
  params and implement; on these 21 trades price hit SL or TP before trail engaged,
  so exits were effectively SL-vs-2.5R-TP races, but the engine must still run the
  trail so that trades which WOULD trail do).
- Exit = first of {SL hit, TP hit, trail-stop hit, reverse-cross close} intrabar.

**Tick-vs-candle ceiling (unfixable on candles)**: the EA runs on ticks; some SL/TP
touches happen on intrabar tick spikes the H1 candle doesn't record (confirmed:
trade 8 SL at 1.17886 triggered 04.17 00:02 though the H1 bar high was only
1.17815). On candle data the exact exit TIMING of such trades cannot match. Accept
this as small noise: the engine matches WHICH trades/direction/SL, and net-R is a
close RANKING tool, not an identical-P&L reproducer. That is the honest ceiling.

---

## Execution gates (from the `[TE]` log lines — exact)

- **Session VETO_TIME**: only trade inside enabled sessions. As-run: London 09-17,
  NY 14-22, Asia 01-09 (server time, unioned) → allowed hours ≈ 01–22; blocked
  00 & 23. (Log: 02.23 00:00 BUY vetoed VETO_TIME.)
- **VETO_RC_MAX_TOTAL_RISK**: skip a new entry if it would push total open risk over
  the cap (~4% per trade, 6% total seen). Needs lot-sizing in account ccy (CHF here).
  This is sequential/portfolio-dependent — must be evaluated in the bar-by-bar walk
  using currently-open exposure. (Log: 01.02 11:00, 04.02 10:00, 04.06 13:00 vetoed.)
  Approximate first (per-trade risk %), refine if the phantom trades persist.

---

## Verification protocol

1. Build engine to this spec (new versioned file, e.g. `xema_engine_<date>-01.py`).
2. Run with the as-run config against EURUSD H1; `--verify` vs
   `fixtures/conformance_EURUSD_H1_260101-260831.csv`, `--tol-bars 1`.
3. Use `fixtures/oracle_EURUSD_H1_260101-260831_rejects.csv` (113 per-bar accept/
   reject decisions + which voter failed) to debug entry gating bar-by-bar.
4. Target: all 21 entries match on time/dir/SL; exits match except tick-sensitive
   ones (flag those explicitly, don't force them).
5. Only after that PASS: sweep knobs and report per-pair/TF/period results.

## Config actually run (the answer key's config)
```json
{ "ema_fast":13, "ema_slow":34,
  "htf_enabled":true, "htf_use_second":false, "htf_tf1":"H1",
  "htf_ema_fast":13, "htf_ema_slow":34, "htf_require_phase":true,
  "use_adx":true, "adx_period":14, "adx_percentile":50.0, "adx_lookback":100,
  "use_bb":true, "bb_period":20, "bb_dev":2.0,
  "use_ci":true, "ci_period":14,
  "use_psar":true, "psar_step":0.08, "psar_max":0.5,
  "sl_mode":"SWING", "swing_lookback":55, "sl_cushion_pips":0.0,
  "label_rr":2.5, "session_hours":"01-22", "max_risk_pct":4.0, "max_total_risk_pct":6.0 }
```
