# PRESET_FPM — The Five-Point Method (Forex Profit Model)

**Status: IMPLEMENTED.** Coded inline in `SEA_Presets.mqh` (`if(preset == PRESET_FPM)`),
evaluated through the shared `EvaluateTS_Breakdown` core. Source material:
`_SEA_FPM/FPM-cheat-sheets.pdf` (Forex Profit Model — Cheat Sheets 1 & 2).
Iconographic: `_SEA_FPM/FX-FPM-Trading_System_v02.png`.

FPM is a flat, **unanimous** five-point checklist — no EMA ribbon, no phase, no layer. It is the one
preset with a concise external design source (the two cheat sheets), so this document is written in
two layers: **(A)** the canonical checklist exactly as the cheat sheet states it, and **(B)** how the
coded preset implements it, including the places it deliberately deviates.

---

## A. Canonical FPM (from the cheat sheets)

### Entry checklist — all five must be true on the closed bar

| # | Buy | Sell |
|---|-----|------|
| 1 | PSAR crossed **below** price | PSAR crossed **above** price |
| 2 | MACD crossed **above** signal line | MACD crossed **below** signal line |
| 3 | Bollinger Bands are **widening** | Bollinger Bands are **widening** |
| 4 | 10 & 20 SMA are **converging** | 10 & 20 SMA are **converging** |
| 5 | Candle closed **above** both 10 & 20 SMA | Candle closed **below** both 10 & 20 SMA |

### Stop-loss checklist
1. Stop loss under recent swing low (buy) / above swing high (sell) — **25 pips max**.
2. Move to **break-even after +10 pips** profit.
3. Optional — trailing stop of **15 points** (or broker minimum).

### Take-profit checklist
1. Set take profit: **M5 = 7–15 pips · M15 = 10–20 pips · M30 = 30–50 pips**.
2. Exit if you see a valid **opposite** signal.

*Things to remember: check the news… relax… if you're late to the party, WAIT!*

---

## B. How PRESET_FPM implements it — with deviations

Evaluated at bar close (`shift = 1`), unanimous (`VOTE_MODE_ALL`); any factor 0 → TS = 0.
Bias is dual-SMA position (`BIAS_2EMA`, `STRAT_2EMA_POSITION`, `MaType = METHOD_SMA`, `P_Ema1=10`,
`P_Ema2=20`). Phase/layer are off.

| Cheat-sheet rule | Coded reality | Verdict |
|------------------|---------------|:-------:|
| 1. PSAR side | PSAR voter, dot position, flip every bar (`Vote_PsarFlipDelay=-1`) | ✓ faithful |
| 2. MACD cross | **fresh** cross, valid ≤ 5 bars (`MacdVoteMode=MACD_CROSSOVER_N`, `MacdFreshBars=5`) | ✓ (adds a freshness window) |
| 3. BB widening | `BbMode=BB_WIDENING` (bandwidth expanding) | ✓ faithful |
| 4. 10/20 SMA **converging** | **DROPPED** — `Ind_SmaConverge_Enabled=false` | ⚠ removed |
| 5. close above/below **both** SMAs | `BC_BIAS_FAST` = close vs **SMA10 only**; "both" carried by the position bias | ⚠ partial |
| SL swing, **25 pips max** | `SL_MODE_SWING` + TF-aware lookback + auto cushion/floor; **no 25-pip ceiling** | ⚠ cap not enforced |
| BE after **+10 pips** | `BEThresholdPips=0` → engages on any positive profit | ⚠ differs |
| Trail 15 points | `TRAIL_FIXED_PIPS`, default 15 (broker-min clamped) | ✓ faithful |
| TP M5/M15/M30 ranges | **default `TP_MODE_RR` = 1.5**; `FIXED_PIPS` uses midpoints 11/15/40 **+ H1 50** | ⚠ default is R:R; +H1 extra |
| Exit on opposite signal | `CloseOnReverse=false` — **not wired**; exit via SL/TP/trail | ⚠ not implemented |

### Why point 4 was dropped (deliberate)
"10 & 20 SMA converging" is mutually exclusive with a *trending* 2-SMA position bias: when
`STRAT_2EMA_POSITION` fires (price positioned beyond both SMAs, SMAs moving apart) the gap is
*diverging*, so a convergence test would fail on exactly the bars the system wants to trade. The
bar-close gate (`BC_BIAS_FAST`, close vs SMA10) covers the "price is positioned relative to the SMAs"
role instead. This is an engine decision, recorded so the preset can be judged against its source.

### Optional add-on voters (default OFF)
`Inp_FPM_Use_Adx`, `Inp_FPM_Use_CandleBody`, `Inp_FPM_Use_CI`, `Inp_FPM_Ind_Mfi_Enabled`
(MFI>50 long / <50 short), `Inp_FPM_Use_Dpi`, `Inp_FPM_Use_P123`, `Inp_FPM_Use_Ross`,
`Inp_FPM_Use_Mtf` — each adds another unanimous confirmation.

### TF cheat-sheet helpers (code)
`GetFPMFixedTpPips()`: ≤M5 11 · M15 15 · M30 40 · H1+ 50 pips (midpoints of the cheat-sheet ranges,
plus an H1+ value not in the source). `GetFPMSwingLookback()`: M1 10 · M5 12 · M15 15 · M30 18 ·
H1 20 · H4 30.

---

## C. Quick reference

```
Entry (cheat sheet): PSAR side · MACD cross · BB widening · SMA converging · close vs both SMAs
Entry (coded)      : PSAR · MACD fresh-cross(≤5) · BB widening · [SMA-converge DROPPED] · BC vs SMA10 · 2-SMA position bias
Vote : unanimous (all enabled), shift=1        Bias: 2-SMA position (10/20)
SL   : swing (TF-aware) [no 25-pip cap]        BE  : any positive profit [cheat sheet: +10 pips]
TP   : default R:R 1.5 (or TF fixed pips)       Trail: optional 15-pip lock
Exit-on-opposite: NOT wired (CloseOnReverse=false)   Enum: PRESET_FPM
```
