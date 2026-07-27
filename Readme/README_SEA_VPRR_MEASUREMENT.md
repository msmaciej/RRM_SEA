# VPRR measurement — CSV schema and how to analyse it

Companion to the VPRR section of `README.md`. Written 2026-07-27.

VPRR casts no vote. It measures and records. This document defines what it records and
what can be concluded from it.

---

## File

`SEA_VPRR_<symbol>_<timeframe>.csv`, in the terminal's **Common** files folder
(`FILE_COMMON`). One row per evaluated signal bar.

Written when `Inp_VPRR_LogPerSignal = true` and VPRR is enabled. Requires either a
real-volume source or `Inp_VPRR_ResearchTickMode = true`.

## Columns

| Column | Meaning |
|---|---|
| `bar_time` | Signal bar (shift=1) open time, broker server time |
| `symbol`, `tf` | Instrument and timeframe |
| `bias` | +1 long, −1 short |
| `layer` | Active layer: 1=W (EMA1/2), 2=M (EMA2/3), 3=S (EMA3/4) |
| `vprr_ratio` | The legacy ratio: mean recovery volume ÷ mean pullback volume |
| `threshold` | Effective threshold — per-layer override if set, else global. **Provisional** |
| `pb_rvol` | Mean RVOL across the pullback leg. 1.0 = typical for that minute-of-day |
| `rec_rvol` | Mean RVOL across the recovery leg |
| `pb_volPerRange` | Mean volume per point of range, pullback leg — effort vs result |
| `rec_volPerRange` | Same, recovery leg. High = volume moved price little (**absorption**) |
| `pb_volSlope` | Least-squares slope of volume vs bar index within the pullback. Negative = **fading**, positive = **building** |
| `rec_volSlope` | Same, recovery leg |
| `pb_bars`, `rec_bars` | Bars accumulated in each leg — the sample size behind that row |
| `vol_source` | `REAL` / `TICK` / `NONE` — **provenance. Never pool REAL and TICK rows** |
| `ts_fired` | 1 if TS produced a signal on this bar, 0 otherwise |

## Reading rules — non-negotiable

**`0.0` means NOT COMPUTABLE, not zero.** No real volume, insufficient history for the
RVOL baseline, or fewer than 2 bars for a slope. Exclude those rows **per column**, not
per row — a row can have a valid `pb_rvol` and an uncomputable `pb_volSlope`.

**Never mix `vol_source`.** `REAL` and `TICK` are different measurements. Pooling them
produces a number that describes neither.

**Tick rows do not measure institutional participation.** A quote-update count cannot
report contracts traded or which side was the aggressor. Tick rows measure *relative
activity*. That is a real quantity; it is not order flow.

**`ts_fired` is a column, not a filter.** Bars are logged whether or not TS fired.
Restricting the log to fired bars would condition the sample on the outcome.

---

## KNOWN GAP — there is no outcome column

**The CSV records what VPRR measured at signal time. It does not know what happened
next.** There is no win/loss, no P&L, no MFE/MAE.

Any "do winners differ from losers" question therefore requires **joining this file to
MT5 trade history on timestamp** — matching `bar_time` to the entry time of the resulting
trade. Only rows with `ts_fired = 1` that became actual trades have an outcome; the rest
have nothing to compare.

This is a deliberate scope boundary, not an oversight, but it is a real limitation and it
makes Analysis Level 2 below manual. Automating it — writing the outcome back after a
position closes — is a small self-contained change and is **not yet implemented**.

---

## Analysis Level 1 — needs nothing but this file

Available as soon as rows accumulate. This is where the fastest and most decisive
information is.

### L1.1 — Is the core premise even true? *(the decisive one)*

VPRR's entire premise is that recovery volume exceeds pullback volume on a valid setup.
**This has never been checked on this market.**

Compare `rec_rvol` against `pb_rvol` across all rows.

- Recovery consistently higher → premise survives, continue.
- Distributions essentially identical → **the premise is false here.** No threshold, no
  real-volume feed and no redesign rescues it. Stop and delete the subsystem.

One comparison can end this line of work. Run it first.

### L1.2 — Was the clock problem real?

Group rows by hour of day.

- `vprr_ratio` drifts with the clock while `pb_rvol`/`rec_rvol` do not → the session-clock
  diagnosis was correct and RVOL normalisation fixed it.
- Neither drifts → the clock problem was overstated in the audit, and that should be
  recorded here.

### L1.3 — Do pullbacks actually fade?

`pb_volSlope` should be predominantly **negative** if the classical reading holds — volume
drying up as the pullback exhausts. If it is indistinguishable from noise, that piece of
theory does not describe this instrument.

### L1.4 — Metals vs FX

Run research tick mode on **both** XAUUSD and an FX pair and compare the same columns.

If gold shows structure the FX pair does not, that is evidence — obtained for free — that
a real-volume feed is worth pursuing. If both look identical and featureless, that is
evidence it is not. Either way it is cheaper than a broker migration.

---

## Analysis Level 2 — requires the trade-history join

After joining on timestamp, split fired rows into winners and losers and compare each
column's distribution.

- **Separation** (e.g. winners show clearly higher `rec_rvol`, distributions barely
  overlapping) → thresholds can be set *from the data*, and re-arming via the two-key gate
  becomes a legitimate question.
- **No separation** (distributions sitting on top of each other) → VPRR has no edge on this
  setup. Delete it.

Sample size: aim for a few hundred fired signals. Fewer than ~100 will not distinguish a
weak effect from noise.

---

## Decision rule

| Finding | Action |
|---|---|
| L1.1 shows no recovery-vs-pullback difference | **Delete VPRR.** Nothing downstream can help |
| L1.1 survives, L2 shows no separation | **Delete VPRR.** The premise holds generally but carries no edge here |
| L1.1 survives, L2 shows separation on TICK rows | Set thresholds from data; consider a real-volume feed to test whether it strengthens |
| L1.4 shows gold ≫ FX | Pursue a real-volume feed; re-run on `REAL` rows before trusting anything |
| Everything uncomputable (`0.0`) | Check `Inp_VPRR_ResearchTickMode` and history depth before concluding anything |

**Deleting VPRR is a good outcome, not a failure.** It costs a few hundred lines and
returns a real fact about your own instrument.
