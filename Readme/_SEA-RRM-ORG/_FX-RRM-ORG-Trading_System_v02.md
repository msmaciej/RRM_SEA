# PRESET_RRM_ORG v02 — Russ Horn RRM (Original, quality-gated)

**Status: IMPLEMENTED & DEFAULT.** Same engine as v01 (`SEA_Presets.mqh`, `if(preset == PRESET_RRM_ORG)`;
shared `EvaluateTS_Breakdown` core in `SEA_SignalEngine.mqh`). v02 is the input set and the three code
additions that came out of the 100-trade study (`_RRM_ORG_100_trades_tally.csv`, `_RRM_ORG_QUALITY_PRESET.md`)
cross-checked against the RRM manual, the 13 reports and the setup cards. Iconographic:
`_SEA-RRM-ORG/_FX-RRM-ORG-Trading_System_v02.png`.

What changed versus v01, in one line each:

- **Gates that existed but were off are on:** DPI reset→recovery, price-vs-EMA89 over-extension, EMA-fan, climax guard.
- **Fresh-cross gate (new):** a layer fires only on one of the first pullbacks after its reference EMA cross.
- **UNO Shark (new):** Layer S may fire in the Unordered phase when EMA34/EMA89 are still ordered.
- **Exits follow the manual:** BE at 70 % of risk, trail on EMA34 after BE, no fixed TP on H1+, optional stale scratch.
- **Session and voters trimmed:** London ±1 h plus a 07–12 window, no Asia; ADX/Stoch off — DPI is the only momentum voter.

---

## 0. Pipeline reminder — TS / TE / TM

- **TS — Trade Signal** (`EvaluateTS`, bar close, shift = 1): `B × P × L × I × F → CG`. Any factor 0 → no signal.
- **TE — Trade Entry** (`EvaluateTE`, next bar open): Policy-A gates — session, spread, news, caps, lot sizing.
- **TM — Trade Management** (`EvaluateTM`, while open): SL, BE, trail, TP, early exits.

The equation and the three stages are unchanged; v02 changes which factors are active and adds two gates inside **L**.

---

## 1. The idea — a young trend gives direction, its first pullbacks give the entry

The ribbon (`5 / 13 / 34 / 89`) classifies the market; a pullback that recovers marks the entry bar; four voters
must agree; four filters remove stretched or fading entries. The study added the piece the book implies but never
states as a rule: **the pullback has to be one of the first after the cross that started the trend**. Signals on the
third-plus shallow pullback of an old run were the losing half of the reference set (47 % quality) — the first
pullbacks after a cross and the deep pullbacks to EMA34/89 were the winning 80 % (84–86 %).

---

## 2. B — Bias (4-EMA ribbon order)

| EMA order | Market | B |
|-----------|--------|---|
| EMA2 > EMA3 > EMA4 | Trending up (TM↑) | +1 |
| EMA4 > EMA3 > EMA2 | Trending down (TM↓) | −1 |
| EMA2 > EMA4 > EMA3 | Emerging up (EM↑) | +1 |
| EMA3 > EMA4 > EMA2 | Emerging down (EM↓) | −1 |
| EMA3 > EMA2 > EMA4 | **UNO Shark**: long-term up, 13 fell back between 34 and 89 | +1, Layer S only |
| EMA4 > EMA2 > EMA3 | **UNO Shark**: long-term down, 13 bounced between 34 and 89 | −1, Layer S only |
| anything else | Unordered (UNO) | 0 → block |

`UnoSharkDirection()` supplies the two new rows when `Inp_RRM_ORG_UNO_AllowStrongShark = true` and sets
`m_uno_shark_ctx`; every other UNO geometry stays B = 0. Oracle: manual II.C/III — "the Shark trade most of the
time occurs in an Unordered Phase"; "a failed Emerging phase will often result in a nice Shark trade".

## 3. P — Phase gate

| Phase | W (5/13) | M (13/34) | S (34/89) |
|-------|----------|-----------|-----------|
| TM Trending | ✓ (M15 and up) | ✓ | ✓ |
| EM Emerging | ✓ (M15 and up) | ✓ | ✗ — Strong card: "during the Trending Phase" |
| UNO, Shark geometry | ✗ | ✗ | ✓ — price touched EMA89 within 8 bars |
| UNO, any other order | ✗ | ✗ | ✗ |

`BlockUnorderedPhase = true` (exempted only in the Shark context), `BlockEmergingPhase = false`,
`Emerging_AllowStrongTrades = false`, `LayerS_TMOnly = true` (exempted in the Shark context).
`AllowLayerW = false` on M1/M5 charts: every intraday late-trend loser in the study was a W entry.

## 4. L — Layer pullback → recovery, then the fresh-cross count

**Step 1 — the layer machine (unchanged).** Walk S → M → W; first to pass wins. Each layer is a state machine on
its EMA pair: `NONE → DETECTED` (fast-EMA slope flattens or reverses against bias; min 3 bars W/M, 2 bars S)
`→ IN-TREND` (both slopes resume with bias). The `DETECTED → IN-TREND` edge is the fire; the layer stays armed
until a TS = 1 consumes it, then waits for the next pullback. One entry per pullback. A sustained UNO (beyond
`UNO_ToleranceBars = 1`) soft-resets W and M; `MinBarsAfterUNOExit = 2` before they can re-arm.

**Step 2 — the fresh-cross count (new, `CheckFreshCrossGate`).** For the layer whose edge fired:

| Layer | Touch EMA | Reference cross (the trend clock) | Cap |
|-------|-----------|-----------------------------------|-----|
| W | EMA13 | EMA13 × EMA34 — the ribbon's own 5/13 pair flips on every pullback, so the next-slower pair is the clock | first **2** pullbacks |
| M | EMA34 | EMA13 × EMA34 — its own pair (a 13/34 cross against bias = UNO = M invalid anyway) | first **3** pullbacks |
| S | EMA89 | EMA34 × EMA89 — its own pair | unlimited (measured, not gated) |

Walk back from the signal bar to the most recent bias-direction cross of the reference pair; from that bar to now,
count touch-episodes of the layer's EMA (long: any Low ≤ EMA; a run of touching bars = one episode; the current
pullback counts). Fire only while episodes ≤ cap. No cross inside `FreshX_Lookback = 300` bars = stale. Episodes,
not bars, so the rule is the same on M1 and D1; `FreshX_MaxBars_*` exists for a hard age cap and is off.
Reject reason: `L_FRESHX_STALE(W:pb3/age57 …)`. Oracle: manual III "Crossover entry examples", report
"Multi-Timeframe" ("trade 1 … trade 2 … trade 3 was overbought — no trade").

**Step 3 — price confirmation (unchanged).** **BC** layer-aware: close beyond the layer's fast EMA (W→EMA1,
M→EMA2, S→EMA3 — the book's "close past"). **BD**: bar closed in the bias direction. Progressive momentum over the
last 2 bars. In the Shark context S additionally needs the EMA89 touch (`L_UNO_SHARK_NOTOUCH` otherwise) and W/M are
hard-blocked (`L_UNO_S_ONLY`).

## 5. I — Indicator voters (unanimous, `VOTE_MODE_ALL`)

| Voter | Passes when… |
|-------|--------------|
| **DPI** | histogram colour = bias (CCI drives the colour), GREEN present, and a **reset → recovery** cycle completed since the last entry: colour flipped against the trend and back, plus 1 recovery bar. `GrantFirstEntry = false` — the first trade after start waits for one cycle. Oracle: "most of the time we enter when the DPI straddles the zero line"; *Opening the DPI* — after overbought, a full flip and flip-back before new longs. |
| **PSAR** | dot on the bias side; flip within W 2 · M 3 · S 5 bars (manual VIII.C: "validate on the specific candle or the next"). |
| **CandleBody** | closes in direction, in its top/bottom 25 %, not > 3× average. |
| **MTF** | higher TFs in a tradable phase, same direction. Set per chart to the 4:1 rule: M1→M5+M15 · M5→M15+H1 · M15→H1+H4 · H1→H4+D1 · H4→D1+W1 (report *Multi-Timeframe*: M1 and M5 need two confirming TFs). |

ADX, Stochastic, CI, MACD, RSI, BB, MFI, VRC, P123, Ross: off. Disabled voters contribute 1. VPRR does not vote.

## 6. F — Filters (now on) & CG — Climax veto

| Gate | Blocks when… | Oracle |
|------|--------------|--------|
| PriceExt | close > 2.5 × ATR(14) from EMA89 | *Early Entry*: "the market might have moved so far … too far from the moving average" |
| EMA-fan | EMA1–EMA4 spread beyond the per-TF pips table | manual VIII.D "large gap between the 13 and 34" |
| DPI-decel | GREEN shrinking or gone on the signal bar | *Silly Season* "DPI angle — Follow line turns first" |
| CG Climax | one bar > 2 × ATR, or 13-bar move > 3 × ATR, in the trade direction; checked last | manual VIII.B/E extra-large candle, wait after large moves |

## 7. TE — Trade entry (Policy-A)

Session London 09–17 ±1 h **and** Win1 07–12 (six of the intraday Big trades fired 06:30–08:40 EET), NY 14–22, Asia
off (report *When Not To Trade* #6). Spread veto recommended at 2 pips majors / 4 crosses (currently off).
Optional news veto ±60 min. Caps: 8 trades/day, 3 consecutive losses, 8 % daily drawdown, 3-bar cooldown after a
close. Entry at the open of the bar after the signal close, 2 % risk sized from the swing stop.

## 8. TM — Trade management (Oracle exits)

| Stage | Rule | Oracle |
|-------|------|--------|
| SL | most recent swing high/low within 21 bars + TF cushion (min floor, auto-widen) | manual IV.A "a few pips beyond the most recent swing" |
| BE | at 0.7 × initial risk; SL never tightens while still at a loss | manual IV.E "about 70 % of my initial stop loss" |
| Trail | starts after BE: EMA34 of the last closed bar − 0.3 ATR, never moved backwards (H1+); PSAR trail on ≤ M15 | *Letting Profits Run* "use the 34 EMA to trail your stop loss" / "not on the EMA but a little above it" |
| TP | none on H1+ (trail is the exit); RR 2.0 on ≤ M15 | manual V 1:1 base, *Letting Profits Run* for runners |
| Early exit | optional `DPI_ExitOnHistDisappear` (GREEN vanished = OB/OS); optional **stale exit**: no 1 R of MFE within 12 bars → scratch | *Letting Profits Run* DPI OB/OS exit; manual VII.D "sideways market … get out at break even" |

## 9. Conflict check between the gates

- `LayerS_TMOnly` blocks S in EM; the Shark context is exempted explicitly — the two do not cancel.
- UNO cooldown/tolerance keep working for W and M; on Shark-context bars S keeps its cycle while W/M are treated as
  still in UNO, in both the live path and the SignalScan replay.
- DPI reset-recovery and the fresh-cross count both require a pullback to have happened — the same event, no double
  penalty.
- PriceExt on EMA89 cannot block a Shark (price is at EMA89 by definition) and does not touch first pullbacks.
- FreshX for M with the 13/34 reference works in EM: the 13/34 cross has already happened by then.
- `MTF_RequirePhase = true` will reject a Shark when the higher TF is itself UNO. Book-faithful, but it removes some
  of the deep-pullback Sharks of the reference set; the switch to reconsider if SignalScan shows those as `MTF`.

## 10. New inputs (all in the RRM_ORG group)

```
Inp_RRM_ORG_FreshX_Enabled            = true
Inp_RRM_ORG_FreshX_RefPair_W/M/S      = FRESHX_EMA2x3 / FRESHX_EMA2x3 / FRESHX_EMA3x4
Inp_RRM_ORG_FreshX_MaxPullbacks_W/M/S = 2 / 3 / 0        (0 = measured, not gated)
Inp_RRM_ORG_FreshX_MaxBars_W/M/S      = 0 / 0 / 0        (optional hard age cap)
Inp_RRM_ORG_FreshX_Lookback           = 300
Inp_RRM_ORG_UNO_AllowStrongShark      = true
Inp_RRM_ORG_UNO_Shark_TouchWindow     = 8
Inp_RRM_ORG_StaleExit_Enabled/Bars/MinR = false / 12 / 1.0
```

## 11. Quick reference

```
Ribbon : EMA 5/13/34/89               Bias : ribbon order; UNO-Shark geometry → S only
Phase  : TM + EM (S: TM only) + UNO-Shark   Layer: S→M→W, fire on recovery edge,
Fresh  : W first 2 / M first 3 / S any        first pullbacks after the reference cross
Voters : DPI(reset→recovery+GREEN) PSAR CandleBody MTF — unanimous
Filters: PriceExt(EMA89,2.5ATR) EMA-fan DPI-decel   Veto : CG climax (last)
TE     : London ±1h + 07–12, NY; no Asia; 2 %; 8/day
TM     : swing SL(21) · BE 0.7R · trail EMA34 after BE · TP none (H1+) / RR2 (≤M15)
Enum   : PRESET_RRM_ORG (default)     Study: _RRM_ORG_100_trades_tally.csv, _RRM_ORG_QUALITY_PRESET.md
```

Validation: run SignalScan over the 100-trade dates. Expected: the UNO-geometry Sharks (EURUSD H4 1 Nov 2012 16:00,
EURAUD H4 1 Nov 12:00, GBPUSD D1 4 May 2010, EURUSD D1 11 Jan 2010) become TS = 1; the late-trend bars (USDJPY H4
31 Oct 2012, EURUSD M15 30 Oct, USDJPY M5 13 Nov 00:15) read `L_FRESHX_STALE` or `PRICE_OVEREXT`. If early
fresh-cross bars also read `L_FRESHX_STALE`, raise `MaxPullbacks_W` to 3 before touching anything else.
