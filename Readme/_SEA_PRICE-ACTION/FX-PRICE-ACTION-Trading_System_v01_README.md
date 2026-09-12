# Price Action — Naked Trading (PRICE_ACTION) — candidate preset design

**Status: NOT YET IMPLEMENTED.** No Price-Action preset exists in the enum
(`FPM, MA, RRM_ORG, TOPINVESTOR, XEMA, TURTLE, TREND, RH_REBELLION`). This is a **design-stage**
artifact for a future `PRESET_PRICE_ACTION`, staged like `_RH_REBELLION` / `_RH_GS` before
implementation. Source in `_PRICE_ACTION/`: `Wozniak_Henryk_-_Price_Action.pdf` (Henryk Woźniak,
*Najlepsze systemy Forex – Price Action*, Dobry eBook, Kraków 2010, Polish, 85 pp.).
Iconographic: `_PRICE_ACTION/FX-PRICE-ACTION-Trading_System_v01.png`.

> **Read this first.** This is the first candidate that is not an indicator system. The book is
> explicitly *anti*-indicator and *anti*-EA: the author's edge is the discretionary reading of
> support/resistance importance and candle context. Everything below separates what is a **rule**
> (codeable) from what is **judgement** (stays confirmation-only or is dropped). The honest verdict
> is in §C: yes, it can become a preset, but the S/R-zone engine is real engineering work, so a
> two-phase build is proposed.

---

## 0. Pipeline reminder — same TS / TE / TM as every preset

Once coded, Price Action runs the identical three stages every SEA preset uses:
**TS** (`EvaluateTS`, bar close, `B × P × F × L × I → CG`) → **TE** (`EvaluateTE`, bar open,
Policy-A gate chain) → **TM** (`EvaluateTM`, while open: SL/TP/exit). For this system:
**B** = swing structure (HH/HL vs LH/LL) with EMA-slope helpers; **P** inert; **L** = the
correction into an S/R zone or EMA 144/377; **I** = pin bar / inside bar / PB+IB + higher-TF
agreement (unanimous); **F/CG** = closed-bar-only, no first-break entries, climax/news veto;
**TE** = three entry styles (market / stop / limit) + Anty-Stop re-arm; **TM** = bar-anchored SL,
BE at +20 pips, partials, TP at the next level or 2R.

---

## A. Canonical system (from the book)

### A.1 Doctrine — the naked chart
- **Price is the only indicator.** Stochastic / RSI / MACD / "Christmas-tree" charts are rejected;
  the book's argument: a market is never so oversold that it cannot get more oversold.
- Only lines allowed on the chart: **horizontal S/R levels**, a **trend line** sparingly,
  **Fibonacci 0.5 / 0.618 / 0.764** on H1 and above only, and three EMAs used as *levels and slope*,
  never as crossovers: **EMA 21 on D1** (master trend), **EMA 144 and EMA 377 on H1** (dynamic S/R;
  EMA 144 slope = short-term trend direction).
- Fibo and trend-line agreement *strengthen* a level; you **enter on the S/R level, not on the fibo**.
- Pick two or three of the setups below, drill them, do not switch.

### A.2 Market structure (Ch. 2, after Phil Newton)
| Element | Rule |
|---|---|
| **Swing High** | three-bar pattern: the middle bar's high is above the highs of both neighbours |
| **Swing Low** | mirror: middle bar's low below both neighbours |
| **Up-trend** | higher highs **and** higher lows (HH + HL) |
| **Down-trend** | lower highs **and** lower lows (LH + LL) |
| **Range** | price fails to make a new high or low; confirmed when an LH and HL form inside the last extremes |
| **Trend change (1-2-3)** | confirmed only when price breaks the last swing low (to down) / swing high (to up); the position is taken on the **correction back to the broken level** |

### A.3 Support / resistance — the core (Ch. 3–4)
- **Long-term S/R** are drawn on **H4, D1, W1** (review starts on H4); on a calm market they yield
  **100+ pip** moves. **Short-term S/R** appear on **H1, M30, M15** when a level breaks and flips role
  (support → resistance and vice-versa); these are low-risk setups with **SL ≈ 10–15 pips** and
  **40–50 pip** targets.
- **Zone, not line.** Mark how precisely the level was tested — typically **5–30 pips**. *That width
  is the SL size.*
- **What makes a level tradeable:** it held price **at least 2–3 times**; it is **dual-function**
  (has acted as both S and R); it is **old and long-tested** rather than fresh; it has **not been
  pierced too often** (breakouts happen — a frequently pierced level is a mine); it **coincides with
  a fibo** (0.5 / 0.618 / 0.764, ≥ H1) and, with less weight, a trend line.
- **Round "00" levels** (1.4000, 1.4100, 1.4300…) act as levels. A **third attack** on a level with a
  weakening trend is faded with a small stop above the double/triple top.
- Weaker levels: right after big data releases, **Fridays** (stop-hunting), month-end option expiry.

### A.4 Trend gauge and timeframes (Ch. 6)
- Trade **H1 and higher**. Weight of signals: **W1 > D1 > H4 > H1 ≫ M15 / M5**. M15/M30 are used to
  see where a level broke and to manage the open trade.
- **D1 EMA 21 slope** gives the master trend. On H1, **EMA 144 / EMA 377** are dynamic levels that
  price respects; the **slope of EMA 144** gives the short-term trend — the longer price stays on one
  side, the bigger the potential. **Never enter because the EMAs crossed**; enter on the correction
  toward the EMAs, always with the trend. Lower-TF trend aligned with the higher-TF trend = higher
  continuation odds and better R:R.
- Trend line: two lows (up) or two highs (down) joined. Used as confirmation only.

### A.5 Candle setups (Ch. 7)
**Pin bar (PB)** — wick clearly larger than the body; a reversal bar. Occurs near S/R or the EMAs but
that is not mandatory. Strongest after multi-day corrections of the main trend; suited to H1/H4.
1. **E1 — aggressive:** enter as soon as the bar completes. SL just beyond the wick, or more
   aggressively at **60 % of the bar's height**.
2. **E2 — pending stop** just beyond the body (below for a short, above for a long).
3. **E3 — conservative (bigger TFs, big pin bars):** wait for a **38–50 % retrace** into the bar and
   enter there with the stop beyond the wick — smaller SL. If the wick is small, enter without
   waiting. The retrace may never come; this is for the patient.

**Inside bar (IB)** — one or more bars whose full range (wicks included) sits inside the previous
("mother") bar. Appears where the market is undecided: near S/R, inside flags/triangles. Best results
in **strong trends**, trading the **breakout in the trend direction**, SL above **50 % of the mother
bar** (or just beyond the mother bar if that is close). H4 IBs can mark reversal points.

**PB + IB combo** — the author's strongest PA signal: a pin bar followed by an inside bar, traded with
the trend; near a key S/R it may mark the reversal.

**False breakouts** — the trader's biggest plague, at S/R and around IBs. Defences: **wait for the
close** of the breakout bar; **never buy the first break** of a level — wait for the pullback and
place the buy-stop above that first break; after a false break *against* the trend, place the
correct order beyond the bar preceding the IB.

**Anty-Stop** — stopped out in a valid trend? Re-place the same pending order at the original
entry; if price runs **25 pips** past the stop, place it at the stop price instead to recover.

### A.6 Chart patterns (Ch. 5) — confirmation only
| Type | Pattern | Trigger | Measured target |
|---|---|---|---|
| Continuation | ascending / descending triangle | break of the flat side (often retested) | ≥ widest height |
| Continuation | symmetric triangle · flag | break in trend direction | triangle height · flagpole |
| Continuation | rectangle | break in trend direction, pullback to the edge common | ≥ box height; longer box = bigger break |
| Reversal | head & shoulders / inverse | neckline break (neckline becomes S/R) | ≥ head height |
| Reversal | double / triple top & bottom | break of the line between the peaks | ≥ peak-to-line height |

Reversal patterns raise the odds of a turn but are **not an entry on their own** — the book insists
on S/R plus a PB / IB at the level.

### A.7 Trade management, psychology and money management (Ch. 8–9)
- **SL** = width of the S/R zone (5–30 pips); PB: beyond wick / 60 %; IB: 50 % of mother bar.
- **Targets:** next S/R level; short-term 40–50 pips, long-term 100+; measured pattern moves.
- **Management:** at **+20 pips** move SL to **break-even**; take a partial at **+20** (short-term)
  or **+40** (long-term) and let the rest run to the next level; on small TFs / high volatility take
  profits fast. **Never let a profit turn into a loss.**
- **Seven rules:** no counter-trend trade right after a big news move · SL to BE at +20 · a move
  never lasts forever · always wait for the good setup · don't enter a setup that already played out
  · never let a profit become a loss · never trade out of boredom.
- **Daily plan:** morning review, pending orders on the best S/R levels, alarms a dozen pips away.
  Enter when the *market* is ready, not when *you* are.
- **Money management:** be the casino, not the gambler. Risk **≤ 3 %** per trade (worked example 2 %
  vs 10 %: 19 consecutive losses = −30 % vs −85 %); **R:R 2:1** keeps a 50 % hit-rate profitable;
  scale risk down with trade frequency, weak discipline, a small deposit or a hostile market
  (guest section by Michał Zbróg).

---

## B. How it would map onto the SEA TS / TE / TM pipeline

| Stage | Price Action wiring | Status in SEA |
|-------|---------------------|---------------|
| **B** (direction) | swing structure HH/HL vs LH/LL; helpers: EMA 144 slope (H1), EMA 21 slope (D1) | EMA-slope bias reusable (single-EMA slope mode, as in the XEMA design); **NEW** swing-structure bias |
| **P** | inert (no ribbon phase) | — |
| **L** (pullback) | correction into an S/R zone or to EMA 144/377, then a reversal bar | layer/pullback engine reusable with EMA 144/377 as the layer EMAs; **NEW** S/R-zone engine |
| **I** voter | pin bar (wick ≥ k × body, close in the right half) | **NEW** PinBar voter (extend `CandleBody`) |
| **I** voter | inside bar (range incl. wicks inside the mother bar) + breakout direction | **NEW** InsideBar voter |
| **I** voter | PB + IB combo | composition of the two voters |
| **I** voter | higher-TF agreement (D1 EMA 21 slope / H4 structure) | reuse **MTF** voter |
| **F / CG** | closed breakout bar only; no first-break entries; no counter-trend after news | shift=1 default · L gate · **CG** climax veto + TE news gate |
| **TE** | E1 market · E2 stop beyond body / IB extreme · E3 limit at 38–50 % retrace; Anty-Stop re-arm | market entry exists; **NEW** pending-order entry modes + one-shot re-arm |
| **TM** | SL beyond wick / 60 % PB / 50 % IB mother / zone edge; BE at +20 pips; partial +20/+40; TP = next level or 2R | swing SL, `BE_MODE_R_MULTIPLE`, `RRRatio=2` exist; **NEW** bar-anchored SL modes, pip-based BE, partial close, level-based TP ladder |
| **Risk** | ≤ 3 % (2 % recommended), R:R ≥ 2 | Policy-A risk inputs, unchanged |

The TS core and TE gate chain are **unchanged** — shared with every preset.

---

## C. Can it be integrated as a new PRESET? — verdict and open items

**Yes, as `PRESET_PRICE_ACTION`, in two phases.** Phase 1 is codeable from existing engine parts
plus two small voters; Phase 2 is where the method's real identity (S/R zones) lives and needs a new
module.

### Phase 1 — "PA-lite" (existing engine + two voters)
1. **Bias:** single-EMA slope mode on EMA 144 (H1) — the same slope mode the XEMA design uses when
   `Fast == Slow`. Optional: `BIAS_SWING` later (see Phase 2 item 5).
2. **Layer:** reuse the pullback/recovery engine with **EMA 144 and EMA 377** as the layer EMAs
   (needs the layer EMA periods to be preset-configurable rather than tied to the 5/13/34/89 ribbon).
3. **PinBar voter (NEW, small):** `iOpen/iHigh/iLow/iClose` on the signal bar; passes when
   `wick ≥ Inp_PA_PinWickRatio × body` (default 2.0) and the wick points against the trade
   direction; optional `Inp_PA_PinMinRangeATR`.
4. **InsideBar voter (NEW, small):** bar[1] range ⊂ bar[2] range (wicks included), signal = break of
   the IB extreme in the trade direction. `Inp_PA_RequirePBIB` = require PB as the mother bar.
5. **MTF voter:** D1 EMA 21 slope must agree (reuse).
6. **Exits:** swing SL (lookback covering the PB/IB) + `BE_MODE_R_MULTIPLE` + `RRRatio = 2`. Good
   enough to backtest the *signal* quality before investing in Phase 2.

### Phase 2 — the method proper (new work)
1. **S/R-zone engine (the heavy piece).** Cluster swing highs/lows (ZigZag or the three-bar swing
   definition of §A.2) on the configured level TF (default H4, plus D1) into horizontal zones;
   score each zone by **touches (≥ 2–3)**, **zone width (5–30 pips)**, **dual-function (role
   flip)**, **age since last test**, **break count**, and **00-round-number** proximity; optional
   fibo 0.5/0.618/0.764 confluence of the last swing. Output: the nearest tradeable zone above/below
   price and its width. This feeds **L** (price must be *inside* a zone), **TM** (SL = zone edge;
   TP = next zone) and can later feed a `BIAS_SWING` structure bias.
2. **Pending-order TE modes:** `PA_ENTRY_MARKET` (E1), `PA_ENTRY_STOP_BODY` (E2, stop beyond the
   PB body / IB extreme, expiry N bars), `PA_ENTRY_LIMIT_RETRACE` (E3, limit at
   `Inp_PA_RetracePct` 38–50 % of the PB, expiry N bars). The engine today enters at bar open; this
   adds pending orders with cancellation.
3. **Anty-Stop re-arm:** after an SL hit while B/MTF still agree, re-place the same pending order
   once (`Inp_PA_AntyStop = true`, `MaxRearm = 1`); if price moves 25 pips past the stop, re-place at
   the stop price. New TE rule.
4. **TM additions:** bar-anchored SL modes (`SL_PB_WICK`, `SL_PB_60PCT`, `SL_IB_MOTHER_50PCT`,
   `SL_ZONE_EDGE`); **pip-based BE** (`BE_MODE_PIPS`, default 20) alongside the existing R-multiple;
   **partial close** at +20 / +40 pips (`Inp_PA_PartialPct`); **level-based TP ladder** — TP at the
   next S/R zone, then trail to each subsequent zone (same ratchet shape as the XEMA R-ladder, keyed
   to levels instead of R).
5. **`BIAS_SWING` (optional):** HH/HL vs LH/LL from the swing series; flips only on a confirmed
   1-2-3 break. Replaces the EMA-slope proxy once the swing series exists.

### Not codeable — stays out of the preset
- The author's **judgement of level importance** beyond the scorable criteria above.
- **Trend lines** and **chart patterns** (triangles, flags, H&S, doubles) — confirmation only in the
  book; pattern recognition is out of scope. They are documented for the operator, not the engine.
- The book's own position: the author explicitly distrusts EAs. A faithful preset therefore keeps
  the *rules* (structure, zones, PB/IB, exits, MM) and leaves the *discretion* to the operator via
  the locked/flexible split — like every other preset.

### Defaults proposed for the preset
```
Level TF        : H4 (long-term) + D1 ; trade TF H1 ; MTF = D1 EMA 21 slope
Layer EMAs      : 144 / 377 (H1)          Zone width    : 5–30 pips (SL = width)
PinWickRatio    : 2.0                     IB            : wicks included, mother = PB optional
Entry           : E2 stop beyond body (default) ; E1 / E3 selectable ; expiry 3 bars
SL              : zone edge (or PB wick)  BE            : +20 pips     Partial : 50 % at +20 / +40
TP              : next S/R zone (ladder) ; fallback RR 2
Risk            : 2 % (max 3 %)           Voting        : unanimous, shift = 1
```

---

## D. Quick reference

```
Doctrine : naked chart — S/R levels · swing structure · pin bar · inside bar ; EMAs as levels/slope only
Structure: UP = HH+HL ; DOWN = LH+LL ; RANGE = inside last extremes ; 1-2-3 = break of last swing confirms
Levels   : H4/D1/W1 long-term (100+ pips) ; H1/M30/M15 short-term (SL 10–15, target 40–50) ; zone 5–30 pips = SL
Tradeable: held ≥2–3× · dual-function · old & long-tested · not pierced often · fibo/TL confluence · 00 levels
Trend    : D1 EMA 21 slope ; H1 EMA 144 slope + EMA 377 as dynamic S/R ; never a crossover
Setups   : PB (E1 market / E2 stop beyond body / E3 limit 38–50 %) ; IB breakout with trend (SL 50 % mother) ; PB+IB
Guards   : closed bar only · never the 1st break · no counter-trend after news · Anty-Stop re-arm ×1
TM       : SL = zone width or wick/60 %/50 % ; BE +20 pips ; partial +20/+40 ; TP next level or 2R
MM       : ≤3 % (2 %) per trade ; R:R ≥ 2 ; be the casino
Status   : candidate PRESET_PRICE_ACTION (not built) — Phase 1 PA-lite (EMA layer + PB/IB voters + MTF) ; Phase 2 S/R-zone engine, pending entries, partials, level ladder
```
