# XEMA test-harness — consolidated, conformance-checked

One versioned Python reconstruction of **PRESET_XEMA** for offline sweeps.
It replaces the ad-hoc per-pair/per-question scripts from prior sessions
(`gbp_map.py`, `jpy_map.py`, `gold_map.py`, `htf_sweep.py`, `ema_swing_sweep.py`,
`sweep_psar.py`, `xema_test.py`, `multiyear_xema.py`, `m5_*session.py`) with a
single module any future sweep chat pulls, **verifies against the current EA**,
and reuses.

- **Module:** `xema_harness_260902-01.py`
- **Verified against repo HEAD:** `b0244b7956fe4c2851e71cb956462bd7f3591409` (2026-09-02)
- **Convention:** dated/versioned like `_SEA-Scripts/RRM/rrm_meta_<date>-<n>.py`;
  do not mutate in place — cut a new `xema_harness_<date>-<n>.py` when the
  reconstruction changes, and re-verify.

---

## Why this exists (the point)

Every sweep chat used to hand-rebuild the Python from memory. Saved
reconstructions **drift** from the EA silently, so a fixed bug can be frozen into
"findings". This harness closes that hole with a **conformance gate**: it is
authoritative *only where `--verify` passes against a fixture logged from the EA
at the current HEAD*. The saved reconstruction becomes safe to reuse because it
is provably checked before use.

The prior scripts had in fact drifted from the shipped EA in at least six ways —
all corrected here (see *Reconstruction* below). Two of them
(`multiyear_xema.py`, `sweep_psar.py`) even call a `signals(..., useP=1)`
signature that no longer exists in the committed `xema_test.py`, i.e. they are
already broken against the repo. That is exactly the failure mode the gate
prevents.

---

## The trust model (read before trusting any number)

| `--verify` result | meaning | exit code |
|---|---|---|
| **PASS** | reconstruction reproduces the EA's entries **and** exits (time, dir, SL, exit reason) within tolerance, from a full EA trade-log fixture → results at this commit are trustworthy | 0 |
| **PARTIAL** | fixture was a SignalScan/DebugFlow / entry-only dump → entries verified, exits provisional → treat results as provisional | 2 |
| **FAIL** | EA changed or harness drifted → **STOP**, read the printed per-bar diff, reconcile, re-verify | 1 |
| **REGRESSION-OK / -FAIL** | fixture is harness-derived; guards against harness **drift across edits** only — does **not** certify harness-vs-EA fidelity | 0 / 1 |

(A setup/config error — bad `--config` key, missing HTF file, HTF below chart TF
with no file supplied — prints `error: ...` and exits **3**, not a traceback.)

**Every sweep chat MUST run `--verify` at the current HEAD before trusting sweep
output.** PASS = faithful to this commit; FAIL = do not use.

### Honest limitation
A few EA quantities resolve at runtime and are **inherited** rather than set in
XEMA's preset block: `SL_SwingPipsCushion` and `RRM_BE_BufferPips`. The harness
ships the EA's own formulas for them (`GetRecommendedInitialSlCushionPips`,
`GetTFBasedCushion`, `GetInstrumentFanMultiplier`) as defaults, but the exact SL
*prices* for a given symbol×TF can only be **certified by `--verify` against a
real EA-log fixture**. Until an `EA_LOG` fixture PASSes, treat exact-price SLs as
best-effort. This is precisely the case the gate exists for.

---

## Reconstruction — how XEMA is modelled (and where the old scripts were wrong)

Everything below was read from the authoritative EA sources at HEAD `b0244b7`:
`SEA_Presets.mqh` (PRESET_XEMA block + `ValidateXEMA_ExitConfig`),
`SEA_Inputs.mqh` (`Inp_XEMA_*` defaults), `SEA_SignalEngine.mqh`
(`STRAT_2EMA_CROSS_EMA`, `CheckMTFFilter`, `Check_ADX`, `Check_BB`),
`SEA_TradeExecutor.mqh` (`GetSwingLevel`, `RRM_GetStrictSL`/`EnforceSLMinFloor`,
`EvaluateTM` SIMPLE path, `TryMoveToBreakEven`, `TryTrailRLadder`, `CloseOnReverse`).

**Entry** — `STRAT_2EMA_CROSS_EMA`, `ExitProfile=SIMPLE` (pure cross-only):
fast/slow EMA cross on the closed evaluation bar `i` vs `i-1`
(`prev fast<=slow & curr fast>slow` = long; strict on current, `<=`/`>=` on prev).

**HTF / MTF** — `CheckMTFFilter` with `MTF_RequirePhase=true`: for each configured
HTF, direction = sign(EMAfast−EMAslow), **but** if position says bull while both
HTF EMAs are falling (or bear while both rising) the HTF returns *unclear* (0) and
blocks. With a second HTF, **both** TF1 and TF2 must agree (strict AND, no
majority/pullback exception).

**ADX gate** — `ADX_MODE_DYNAMIC_PERCENTILE`: keep when
`adx[i] >= interpolated percentile(50)` of the rolling ADX buffer
(`lookback=100`, needs ≥10 valid values, else static passthrough).

**Voters** (BB widening, CI choppiness, PSAR, CandleBody, DPI) — all **OFF** by
default; each parameterised and faithful to its EA check when enabled.
BB widening = `bandwidth_now > bandwidth_prev` (reduces to `stdev_now > stdev_prev`).

**Initial SL** — `SL_MODE_SWING`: EA `GetSwingLevel` **fractal** detector
(strength-2, nearest-first over `SwingLookback`, fallback to iLowest/iHighest),
then ± `SL_SwingPipsCushion`, then floored to `max(SL_MinPips, broker stops-level)`
with widen-to-min. (Broker stops-level is unknown offline → user min only.)

**Exit** — the shipped `XEMA_NATIVE` = reverse-cross + BE + LPR, once-per-bar:
- **Reverse-cross close** when the next **fully-qualified opposite signal** fires
  (`CloseOnReverse`) — *not* a raw EMA-position flip.
- **BE at 2R**: move SL to entry ± `GetTFBasedCushion` once open profit ≥ 2R.
- **LPR ladder**: at 3R lock 2R, at 4R lock 3R (`Inp_Global_LPR_*`; XEMA forces the
  ladder on). SL only tightens.
- `TrailMode=NONE`, `TPMode=NONE` (forced by `ValidateXEMA_ExitConfig`).
- Hard SL hit (bar low/high touches SL) closes at SL; conservative SL-before-target.

### Corrections vs. the ad-hoc scripts

| # | old ad-hoc scripts | EA authoritative (this harness) |
|---|---|---|
| 1 | EMA 13/34, swing 55 baked in | **EMA 20/50, swing 20** (neutral EA default) |
| 2 | single H4-resampled HTF, EMA 13/34 | **dual M15+H1, EMA 20/50, phase-required, both agree** |
| 3 | swing SL = rolling `low.min()` | **fractal strength-2** detector (+ iLowest/iHighest fallback) |
| 4 | reverse-cross = raw EMA-position flip | close on next **qualified opposite signal** |
| 5 | per-tick `TRAIL k*R` | once-per-bar **BE@2R + LPR ladder (3R→2R, 4R→3R)** |
| 6 | fixed 2p cushion / 5p min | instrument/TF-scaled cushion + `SL_MinPips` floor |

**No per-pair findings are baked into defaults.** The harness ships the neutral
standard config; discovering per-pair settings (e.g. ADX-off for a given pair) is
the sweep chats' job — express them as `--config` overrides, never as new defaults.

---

## Configuration — every knob (`XemaConfig`)

Defaults below are the **neutral EA standard config** (`Inp_XEMA_*` @ HEAD b0244b7).
Pass overrides as a JSON dict via `--config` or the `config=` dict of `analyze()`.

**Entry EMA:** `ema_fast=20`, `ema_slow=50`

**HTF:** `htf_enabled=True`, `htf_use_second=True`, `htf_tf1="M15"`,
`htf_tf2="H1"`, `htf_ema_fast=20`, `htf_ema_slow=50`, `htf_require_phase=True`,
`htf_source_files={}` (map `{"M15":"path.csv"}` to supply a real HTF native file
when the HTF is not strictly above the chart TF).

**ADX:** `use_adx=True`, `adx_period=14`, `adx_percentile=50.0`, `adx_lookback=100`

**BB voter:** `use_bb=False`, `bb_period=20`, `bb_dev=2.0`
**CI voter:** `use_ci=False`, `ci_period=14`, `ci_ranging_thresh=61.8`
**PSAR voter:** `use_psar=False`, `psar_step=0.02`, `psar_max=0.2`
**CandleBody voter:** `use_candlebody=False`, `cb_require_dir=True`,
`cb_avg_period=14`, `cb_max_mult=3.0`, `cb_min_close_ratio=0.75`
**DPI voter:** `use_dpi=False`

**SL:** `sl_mode="SWING"`, `swing_lookback=20`, `swing_strength=2`,
`sl_atr_period=14`, `sl_atr_mult=1.0`, `sl_cushion_pips=None`
(→ `GetRecommendedInitialSlCushionPips`), `sl_min_pips=None` (→ 3.0),
`sl_widen_to_minimum=True`, `sl_fixed_pips=20.0`

**Exit:** `exit_mode="XEMA_NATIVE"`, `close_on_reverse=True`,
`be_mode="R_MULTIPLE"`, `be_r_multiple=2.0`, `be_buffer_pips=None`
(→ `GetTFBasedCushion`), `trail_mode="NONE"`, `lpr_enabled=True`,
`lpr_ladder=((3.0,2.0),(4.0,3.0))`.
Sweep-only exit modes (NOT the shipped default): `REVCROSS_ONLY` (legacy raw
EMA-flip approximation), `FIX<r>` (fixed r:1 TP), `TRAIL<k>` (peak-anchored k·R).

**Cost / walk:** `spread_pips=None` (→ per-bar MT5 `<SPREAD>` column, else 0),
`independent=False` (sequential one-position, EA-like; `True` = independent walks),
`min_bars_between=0` (de-cluster gap for independent mode).

Pip size auto-detects from the symbol (FX 0.0001, JPY 0.01, gold 0.1) or a price
heuristic; override with `--symbol`.

---

## Usage

Single config (neutral default), any pair×TF×span:
```bash
python3 xema_harness_260902-01.py Files/EURUSD_M5_2020..._2025....csv
python3 xema_harness_260902-01.py Files/USDJPY_M5_....csv --sessions      # + session windows
python3 xema_harness_260902-01.py Files/XAUUSD_H1_....csv --json          # machine-readable
```

Per-knob sweep table + settings card (the single-cell sweep):
```bash
python3 xema_harness_260902-01.py Files/EURUSD_M15_....csv --sweep
```

Overrides (findings live here, never in defaults):
```bash
python3 xema_harness_260902-01.py Files/USDJPY_M5_....csv \
    --config '{"use_adx": false, "ema_fast": 8, "ema_slow": 21}'
```

Real HTF file (needed when an HTF is not above the chart TF, e.g. XEMA's M15 HTF
on an H1 chart — MT5 has real M15 data, a lone H1 CSV does not):
```bash
python3 xema_harness_260902-01.py Files/EURUSD_H1_....csv \
    --htf M15=Files/EURUSD_M15_....csv
```

**Conformance (mandatory before trusting a sweep):**
```bash
python3 xema_harness_260902-01.py Files/EURUSD_H1_....csv \
    --htf M15=Files/EURUSD_M15_....csv \
    --verify fixtures/conformance_EURUSD_H1_<dates>.csv
# exit 0 = PASS, 2 = PARTIAL, 1 = FAIL (prints a per-bar diff on failure)
```

Programmatic:
```python
import importlib.util, sys
spec = importlib.util.spec_from_file_location("xh", "xema_harness_260902-01.py")
xh = importlib.util.module_from_spec(spec); sys.modules["xh"] = xh
spec.loader.exec_module(xh)   # register in sys.modules BEFORE exec (dataclass resolution)
cfg = xh.XemaConfig(use_adx=False)
res = xh.analyze("Files/USDJPY_M5_....csv", cfg)
print(res["summary"], res["per_year"])
```

---

## The shrunk single-cell sweep starter

Once this exists, a sweep chat is just:

1. pull repo
2. `xema_harness_260902-01.py <H1> --htf M15=<M15> --verify fixtures/<EA_LOG>.csv`
   — **must PASS at current HEAD** (exit 0)
3. run the sweep for the requested pair×TF×span (`--sweep`, or `--config` overrides)
4. emit per-knob tables + settings card

No code reconstruction per chat.

---

## Fixtures

`fixtures/` holds conformance fixtures. Each starts with a `# kind:` header:

- `# kind: EA_LOG` — trade log exported from the MT5 tester (authoritative → can
  reach PASS). See `fixtures/TEMPLATE_conformance_EA_LOG.csv` for the exact export
  format and steps.
- `# kind: SIGNALSCAN` — SignalScan/DebugFlow dump of a few bars (entries mostly →
  PARTIAL). The brief's fallback when full EA logs can't be produced this session.
- `# kind: REGRESSION` — harness-derived self-consistency fixture. Guards against
  harness **drift across edits**; does **not** certify harness-vs-EA fidelity.

Shipped now: `fixtures/regression_EURUSD_H1_260101-260828.csv` (REGRESSION, 8
trades, covers SL + REVCROSS exits) and the EA_LOG template.
**Status: conformance is UNVERIFIED against the EA until an `EA_LOG` fixture is
produced and PASSes.** Produce one per the template and commit it.

Columns: `entry_time,direction,sl,exit_time,exit_reason` (SL price + exit checked
when present; `--tol-bars` / `--tol-sl` set tolerances, default ±1 bar / 1.0 pip).

---

## Provenance

- Harness version: `260902-01`
- Verified against HEAD: `b0244b7956fe4c2851e71cb956462bd7f3591409`
- Shipped fixture: `fixtures/regression_EURUSD_H1_260101-260828.csv` (REGRESSION)
- Conformance PASS against an EA_LOG fixture: **pending operator EA logs**
