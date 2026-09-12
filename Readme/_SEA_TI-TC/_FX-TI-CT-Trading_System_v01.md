# Top Investor — Counter-Trend System (CoG + CA) — candidate `PRESET_TI_CT`

**Status: NOT YET IMPLEMENTED — design stage.** Verified against the live repo (`SEA_Presets.mqh`
enum: `MA, TOPINVESTOR, FPM, RRM_ORG, XEMA, TURTLE, TREND, RH_REBELLION, RH_1MS, RH_STS, RH_SS, RH_GS,
RH_SM`): no CoG / Candle-Average preset exists, and the existing **`PRESET_TOPINVESTOR` is a different
system** (Dr Świerk's OXO / EMA 50-200 confluence, `README_SEA_PRESET_TOPINVESTOR_MANUAL.md`). This one
shares only the author. Staged like `_SEA_PRICE-ACTION/` before implementation.

Source in `_SEA_TI-CT/`: `Top-Investor-Opis-Systemu-Pzreciwtrendowego-Poziom-4.pdf` — *Szkolenie Top
Investor, Poziom 4, Bonus: Opis Systemu Przeciwtrendowego*, dr Dariusz Świerk, 2013, Polish, 102 pp.
(≈ 8 pp. of rules, 85 pp. of annotated screenshots, 5 pp. M1 trade log, 2 pp. cheat-sheet).

Iconographic: `_FX-TI-CT-Trading_System_v01.png` (system reference sheet, `_source.html` alongside).
Decision cards (RRM_A4 layout, one question per page): `TICT_A4_V1_Market Phases.PNG`,
`TICT_A4_V1_Trade Setups.PNG`, `TICT_A4_V1_Trade Checklist.PNG`, `TICT_A4_V1_Stop Loss And Management.PNG`,
stacked in `TICT_A4_V1_ALL-IN-ONE.PNG` — use the cards in front of the chart, the sheet when coding.

> **Read this first.** Unlike every preset so far this is a **mean-reversion** system, not a trend-
> continuation one, and its author is candid that the book version **cannot manage risk** (fixed
> 300-pip stop, or no stop at all). The edge — a fast return to the channel centre after an
> over-extended spike, on choppy pairs — is real and codeable. The risk model is not. §C spells out
> the one place the preset must deviate from the book and says so on the sheet.

---

## Naming

| Item | Proposal | Precedent |
|---|---|---|
| Enum | `PRESET_TI_CT` (string `"TI_CT"`) | `PRESET_RH_STS` etc. — author prefix + system token |
| Inputs | `Inp_TICT_*` | `PRESET_RH_STS` ↔ `Inp_RHSTS_*` |
| Folder | `Readme/_SEA_TI-CT/` | `_SEA_TI/`, `_SEA_PRICE-ACTION/` |
| Files | `_FX-TI-CT-Trading_System_vNN.*`, `TICT_A4_VN_*` | `_FX-TI-…`, `PA_A4_V2_*` |

`PRESET_TI_COG` would also be defensible (it names the indicator, not the author's label), but `TI_CT`
is what the source calls it and keeps the TopInvestor family visible in the enum. A *profile* inside
`PRESET_TOPINVESTOR` is **not** an option — different bias engine, different exit logic, opposite
trade direction relative to the last impulse.

---

## 0. Pipeline reminder — same TS / TE / TM as every preset

**TS** (`EvaluateTS`, bar close, `B × P × F × L × I → CG`) → **TE** (`EvaluateTE`, bar open,
Policy-A gate chain) → **TM** (`EvaluateTM`, while open). For this system: **B** = slope of the CoG
outer lines; **P** = slope age / channel width / structure; **L** = close beyond the 2σ line against
the trend; **I** = Candle Average ≥ 0.81 in the spike direction (+ MTF, + structure); **F/CG** =
current-bar-only, climax veto, "wait for the stop"; **TE** = market at next open; **TM** = TP at the
centre clamped before the nearest swing, three early exits, SL beyond 3σ (SEA) instead of 300 pips /
none (book).

---

## A. Canonical system (from the manual)

### A.1 Origin and character
- A modification of **Mostafa Belkhayate's** gold system, popular on Arab trading forums: his
  **Center of Gravity** channel with the original entry "timer" replaced by the **Candle Average**
  indicator. Original instrument gold; original TFs **D1 / H4**; the author and his students now run
  it on **M5 / M1**, on many instruments (the creator himself moved to M1).
- The name "counter-trend" means: fade the last **impulse**, in the direction of the **channel slope**.
  It is a mean-reversion trade that is *with* the CoG trend.
- The author's reservations (stated up front): runaway entries ("zlecenie uciekające") can sit at a loss
  for weeks or take the account to margin call; "you cannot manage risk properly in it". He trades it
  anyway, with his own filters, and knows a fund and several retail traders using it with good results.

### A.2 The two indicators
| Indicator | What it is | Signal reading |
|---|---|---|
| **CoG** (Center of Gravity) | Belkhayate polynomial-regression channel over the last **~180 bars** (D1/H4 setting): thick blue **centre**, bands at 1σ (dotted), **2σ (dashed red above / green below — the signal lines)**, 3σ (solid) | price touching / breaking the dashed line = market "excessively deflected" from its mean → high probability of return to the centre |
| **CA** (Candle Average) | histogram of the current candle's size vs the average of the last few candles | bar beyond **±0.81** = candle "longer than usual"; up-bar = bullish spike, down-bar = bearish spike |

Both together: price far from the mean **and** candles longer than normal → the return move is more
likely and quicker. **Both readings must be current.** CoG is a regression: it repaints, and the
author explicitly shows signals that "disappeared" in hindsight ("the CoG has since moved") — so
historical analysis under-counts real-time signals, and a past band touch is never a signal.

### A.3 Direction = slope of the outer lines
- Lines slope **down** → **shorts only**; slope **up** → **longs only**; **flat or near-flat → no
  signal**. Lines that turned only recently give the riskiest signals ("wait until it settles").
- The author's structural add-on: a down-trend makes lower highs and lower lows. If the **last swing
  high was broken**, the trend rule is violated → no short, even with a perfect CoG + CA reading.
- Trend-end tell (not in the original): the channel **squeezes** after a violent bar at the end of a
  long trend. Skip the signal; usable only after a proper trend, never mechanically.

### A.4 The signal (cheat-sheet, p. 101)
**Short:** outer lines point down · price touches or breaks the **red** dashed line · CA shows a bar
**above +0.81** (up). **Long:** lines up · price at the **green** dashed line · CA **below −0.81**.
All three on the **current** bar.

Timing refinements from the examples:
- **Wait for the stop** — if the market falls hard and there is a (long) signal, do not enter until
  the market stops; better price, not against momentum. If the impulse reaches or breaks the local
  swing on the left third of the screen, the market has shown strength → abandon the idea.
- **The ideal** — a strong breakout with momentum on the higher chart, lines turning, then a **pullback
  to the dashed line with a CA bar** ("what I would like to see").

### A.5 Filters — signals to skip (author's own list)
1. After a **very long move** (continuation hope = reversal risk).
2. Into a **strong S/R or trend line** (price can bounce and turn; TP behind a level is the classic
   mistake).
3. After a **long consolidation** (first move often false; enter on the confirmed continuation).
4. Lines **flat** or **just turned**.
5. **Structure broken** (new HH in a "down-trend").
6. **CoG squeeze** after a violent bar.
7. **Impulse still running** — wait for the first small bar / close back inside.
8. **No CA reading** — a band touch alone is nothing.
9. **Pair unsuitable** — strong trenders with shallow corrections (his example: USD/JPY never gave a
   long signal in weeks); prefer "ragged" pairs with many returns and corrections. Start with **6
   pairs** (the original set had 20 — too many).
10. Higher chart (D1/W1) arguing: reversal in progress, strong resistance right at the entry.

### A.6 Take profit
- **TP1 = the CoG centre line** (thick blue), as it stands now.
- **Author's modification:** if a prior swing high/low lies between entry and centre, set the TP **a
  few to a dozen pips before it** (pair-dependent) — "never behind it". Price reaching such a level
  must break it decisively to justify staying in.
- **TP2 — early exits:** (1) **opposite signal** — lines turn over and a valid signal prints the other
  way → close immediately (and don't even wait for the signal if the CoG starts curling and the market
  has clearly bottomed/topped); (2) **strong move in your favour with only a few / a dozen pips left
  to TP** → take it ("for the sake of your psyche"; a strong bar is almost always followed by a
  correction, TP could take hours); (3) **stall / double bottom at a swing on the way** → warning,
  then exit. Loss of momentum is the first warning.
- No break-even, no trailing, no partials. On small TFs / high volatility the author closes by hand
  after a strong bar in his favour.

### A.7 Stop loss and money management
- **SL = 300 pips fixed** (H4/D1 original). **Version 2: no SL.** The M1 trade log (EURUSD, 0.05–0.10
  lots, ≈10-pip targets, waits from 10 min to ~1.5 h, green = long waits) is from a trader who ran
  it with no stop: +150 % in 130 trades and no open runaway at the end; another statement shows an
  account ×6 in three months **with ≈ $2 000 of open losers on ≈ $3 000**.
- The author's own worst case: a runaway H4 long held two months; an AUD/USD short −120 pips for ten
  days, closed at TP to the pip. His stated goal after learning the system: **eliminate runaway trades
  and minimise time in the market.**

---

## B. How it maps onto the SEA TS / TE / TM pipeline

| Stage | TI-CT wiring | Status in SEA |
|-------|--------------|---------------|
| **CoG indicator** | polynomial-regression channel, N ≈ 180, bands at k·σ | **NEW** module. Must be built as a *moving* regression: value at bar[i] = endpoint of the fit over bars [i−N+1 … i], σ = rolling residual std-dev. This equals what the trader sees live and does **not** repaint. Degree 2 (Belkhayate's default) is enough; expose `Inp_TICT_CogBars`, `Inp_TICT_CogDegree`, `Inp_TICT_SigmaSignal` (2.0), `Inp_TICT_SigmaOuter` (3.0). |
| **B** (direction) | slope of the outer lines over K bars; flat band = no bias | **NEW** `BIAS_COG_SLOPE` — or, cheaper, reuse `BIAS_1EMA` + `STRAT_1EMA_SLOPE` on the CoG centre series with a minimum-slope threshold in ATR (flat = none) |
| **P** (phase quality) | slope age ≥ N bars (not "just turned"); channel not squeezing; structure intact | age gate = FreshX logic **inverted** (minimum age instead of maximum); width check = `BB_WIDENING` idea on CoG bands (veto on narrowing); structure = existing swing/`P123` machinery (last swing high not exceeded in a short bias) |
| **L** (location) | close (or touch) beyond the 2σ dashed line **against** the bias | `BB_MEAN_REVERSION` is the identical shape — reuse the check on CoG bands instead of BB; `Inp_TICT_TouchOrClose` |
| **I** voter | CA = body[1] / SMA(\|body\|, n) ≥ 0.81, in the spike direction | **NEW** CandleAverage voter (small; sibling of `CandleBody`). `Inp_TICT_CaPeriod`, `Inp_TICT_CaThreshold = 0.81`, body vs range selectable |
| **I** voter | higher-TF slope agrees / not reversing | reuse **MTF** voter on the CoG centre (or EMA proxy) |
| **F / CG** | signal on the current bar only; skip climax bars; skip after long move / consolidation | shift = 1 default; **CG** climax veto exists (set its ATR multiple *above* the CA threshold so the window is "big, not climactic"); `PriceExt`; ADX / CI anti-range from XEMA for the consolidation case |
| **TE** | market at next open; optional "wait for the stop" | market entry exists; **NEW** `Inp_TICT_ConfirmBar` — hold TS=1 latched until a bar closes back inside the 2σ line or with body < CA threshold, then enter |
| **TM — TP** | centre line clamped a few pips before the nearest swing | **NEW** `TP_COG_CENTER` (dynamic, re-evaluated each bar) + clamp via existing `TP_MODE_FRACTAL` logic (`min(centre, next fractal − cushion)`) |
| **TM — early exits** | opposite signal; strong move near TP; stall at a swing | `CloseOnReverse` exists (extend to "opposite TS"); **NEW** `TICT_ExitOnBigBarNearTP` (bar ≥ CA threshold in favour and TP progress ≥ X %); **NEW** stall exit (N bars within Y pips of the clamp level without a close beyond) |
| **TM — SL** | 300 pips fixed / none | `SL_MODE_FIXED_PIPS` exists; **NEW** `SL_COG_OUTER` (beyond 3σ + cushion) or `SL_MODE_ATR` — see §C |
| **Risk** | 0.05–0.10 lots, no stop | Policy-A risk %, unchanged — this is the deviation |

TS core and TE gate chain **unchanged**.

---

## C. Can it be integrated as a new PRESET? — verdict and open items

**Yes, as `PRESET_TI_CT`, in two phases — with one declared deviation.**

### The deviation (write it on the sheet, not in a footnote)
"No SL" is not codeable under Policy A: lot sizing needs a stop distance. The 300-pip stop is codeable
but on M5/M1 with 10-pip targets it is effectively "no stop". Proposal: **`SL_COG_OUTER`** — stop just
beyond the 3σ line (+ cushion), sized to 1–2 %; fallback `SL_MODE_ATR`. Expect more small losses than
the manual's statements show; that is the price of never carrying a −120-pip trade for ten days. Add a
`Inp_TICT_BookStop = false` switch that restores the 300-pip fixed stop for backtest comparison only.

### Phase 1 — "CT-lite" (backtestable on existing parts + one voter + one indicator)
1. **CoG module** (non-repainting, as in §B) — the only heavy piece. Validate it against the MT4
   Belkhayate indicator on the *last* bar (they must agree there; history will differ by design).
2. **Bias** from centre-line slope with a flat threshold; **age gate** (min. bars since slope sign
   change, default 20).
3. **L**: close beyond ±2σ against the bias (`BB_MEAN_REVERSION` port).
4. **CA voter**, threshold 0.81, period 5 (author says "the last few candles"; tune 3–8).
5. **MTF** agree; **CG** climax veto; existing swing-structure block for the broken-swing rule.
6. **Exits**: `TP_COG_CENTER` clamped by `TP_MODE_FRACTAL` cushion; `CloseOnReverse`; `SL_COG_OUTER`.
   Enough to measure hit-rate, average time-to-TP and the runaway tail before anything else.

### Phase 2 — the author's refinements
1. `Inp_TICT_ConfirmBar` "wait for the stop" entry.
2. Big-bar-near-TP exit and stall exit.
3. Squeeze veto (channel width falling for N bars after a climax bar).
4. S/R proximity veto — same interface as the PA S/R-zone engine (`_SEA_PRICE-ACTION/SPEC…` P2);
   don't build it twice.
5. Pair-suitability metric (mean-reversion score, e.g. share of 2σ touches that reached the centre
   within M bars) as a SignalScan report, not a gate.

### Not codeable — stays with the operator
- "Does this up-move look like an impulse or a correction?"; "is that resistance *strong*?";
  reading the squeeze as a trend end. The preset approximates, the sheet documents.
- The psychology the manual spends most of its pages on: sitting through a runaway. The SEA answer is
  the stop, not the psychology.

### Defaults proposed for the preset
```
CoG      : bars 180 (D1/H4 book) — 180 also on M5/M1 to start ; degree 2 ; signal 2σ ; outer 3σ
Bias     : centre-line slope over 10 bars ; flat if |slope| < 0.15 ATR/bar ; min age 20 bars
L        : close beyond 2σ against bias (touch-mode optional)       CA : period 5, threshold 0.81
Voters   : CA + MTF (D1 slope agrees) + structure — unanimous ; CG climax veto at 3.0 ATR
TE       : market at next open ; ConfirmBar off (P1) / on (P2) ; pairs: 6 choppy majors/crosses, no USDJPY
TM       : TP = CoG centre clamped 5–15 pips before next fractal ; CloseOnReverse on ; no BE, no trail
SL       : SL_COG_OUTER (3σ + 0.3 ATR) ; fallback ATR×2 ; BookStop=false (300 pips) for comparison
Risk     : 1 % (author: "cannot be managed") ; shift = 1
```

---

## D. Quick reference

```
Origin   : Belkhayate CoG channel + Candle Average (TopInvestor L4 bonus, Świerk 2013) ; gold D1/H4 → M5/M1
Side     : slope of the outer CoG lines — down = shorts, up = longs, flat/just turned = nothing
Signal   : price touches/closes beyond the 2σ dashed line AGAINST the trend + CA beyond 0.81 same bar — NOW (CoG repaints)
Skip     : after long move · into strong S/R · out of consolidation · broken swing · squeeze · impulse running · no CA · trending pair
Entry    : market at next open ; refinement: wait for the first small bar ; ideal = breakout → pullback to the band
TP       : CoG centre, clamped a few–a dozen pips BEFORE the nearest swing ; exits: opposite signal · big bar near TP · stall
SL       : book 300 pips or NONE (margin-call risk, author's words) ; SEA: beyond 3σ / ATR, 1–2 % — declared deviation
Status   : candidate PRESET_TI_CT (not built) — distinct from PRESET_TOPINVESTOR (OXO) ; P1 CoG + CA voter + centre TP ; P2 timing/exit refinements
```
