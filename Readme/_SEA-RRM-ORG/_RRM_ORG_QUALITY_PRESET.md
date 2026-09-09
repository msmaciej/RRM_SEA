# RRM_ORG — Quality preset derived from the 100-trade set and the Oracle documents

Sources read: `_RRM-ORG-100-trades_0-050.pdf` + `_51-100.pdf` (all 100 signals), `_RRM-ORG-system.pdf`
(126-page manual, OCR), `_RRM-ORG-reports.pdf` (13 reports), `_RRM-ORG-setups.pdf` and the four
`RRM_A4_V2_*.PNG` cards. Companion data: `RRM_ORG_100_trades_tally.csv`.

---

## 1. What the Oracle documents confirm, correct, or add

| # | Finding from the 100 trades | Oracle text | Verdict |
|---|---|---|---|
| 1 | Best entries fire with the DPI at/just off the zero line (Clusters A and B; 78 % Big+Good vs 57 % otherwise). | *Letting Profits Run*: "Most of the time, we will be entering a trade when the DPI straddles the zero line." *Early Entry*: enter when the green nested histogram vanishes after the counter-trend swing — rare on Ribbon, occasional on Ghost, **frequent on Shark**. | **Confirmed.** Early Entry = Cluster B exactly. |
| 2 | Cluster C (shallow EMA5/13 pullback late in a run, DPI already extended) is where quality collapses. | *Opening the DPI* / *Silly Season*: when the DPI drops back to zero after a long climb the market is overbought — "buy signals in the area … most of the time they will not be successful"; a new long needs a full colour flip (red) and flip back (yellow) first. *Early Entry*: "once the histogram turns the right colour the market might have moved so far … too far away from the moving average." Manual VIII.D: large 13/34 gap ⇒ correction likely. | **Confirmed**, and the remedy is named: the reset→recovery cycle (`DPI_RequireResetRecovery`) + a price-vs-EMA distance gate. |
| 3 | Asian-session M1/M5 signals are scratches (37 % Big+Good vs 78 % London). | *When Not To Trade* #6: "Outside of the London session when trading 15 minute timeframe or less." Manual VIII.F: M1–H1 range outside London. | **Confirmed.** |
| 4 | Compression before the cross predicts the monster trades. | *When Not To Trade* #1–3: MAs pressed together + narrow DPI = do not trade **yet**; "the first move outside of this pattern can be a fake breakout … we want the market to resume a better flow." | **Refines** Cluster A: the winners were the *first pullback after* the cross, never the breakout candle itself. That is what the layer state machine already enforces (must earn DETECTED→IN-TREND). |
| 5 | Post-climax entries fail (GBPCHF 24 Jul H1, EURUSD 17 Oct M5). | Manual VIII.B/E: extra-large entry candle (1.5–2× average) and "after news or any large move … wait." *When Not To Trade* #4. | **Confirmed** ⇒ Climax Guard on. |
| 6 | Same setup on 2–3 TFs at once were the best trades. | *Multi-Timeframe*: HTF ≈ 4:1; M1 needs M5 **and** M15; M5 needs M15 **and** H1; M30 has no valid HTF; the HTF must itself be tradable and **not** OB/OS. | **Confirmed**; the EA's fixed `MTF_TF1=H1 / TF2=H2` defaults are wrong for most chart TFs. |
| 7 | Winners ran 3–10× the initial pullback; fixed 1:1 exits give the edge away. | Manual V: base target 1:1 but trailing makes realised R:R ≈ 2:1. *Letting Profits Run*: hold until green vanishes / PSAR flips on close / close through 13 EMA / ribbon crossover; trail SL on 34 EMA. Manual IV.E: **BE at ~70 % of initial SL**, not earlier. | **Confirmed**; EA default `BE_RMultiple=0.25` is far tighter than the Oracle. |
| 8 | — | Manual II.C / III: the **Shark trade "most of the time occurs in an Unordered Phase"**; the 5/13 crossover coincides with a Shark ~90 % of the time; the **13/34 crossover out of UNO into TM is "an acceptable entry"** (~85 % coincide with a Shark); a failed Emerging phase "often results in a nice Shark trade". *Jump Trade* report: tradable in UNO when EMA5 is outside EMA89 while EMA13 sits between EMA34/EMA89. | **New and important.** `BlockUnorderedPhase=true` structurally blocks the Oracle's highest-payoff setups. In the sample these are trades 3, 4, 22/36, 50, 52, 53 (all "Big"). |
| 9 | — | Trade Setups card: Weak — "EMA1 never crosses below EMA2 during this setup"; Medium — "EMA1 becomes unimportant"; Strong — "no trades during Emerging Phase". Checklist item 5: "Is there a reason this is not a good trade setup? (time of day, ranging market…)". | Layer cascade and `LayerS_TMOnly` match the card. Item 5 is the discretionary gate the EA lacks — the parameters below approximate it. |
| 10 | — | Manual V: ">75 % win ratio if we wait to trade the Trending Phases"; Emerging→Trending 75 % of the time but "trading opportunities are actually quite rare" in Emerging. | Consistent with the tally (TM-phase A/B entries ≈ 85 %). |

Net: nothing in the 100-trade analysis contradicts the Oracle. The Oracle adds one thing the tally could not show — the EA is currently *forbidden* from taking Horn's best trade (Shark / 13-34 crossover out of UNO) — and quantifies two exit rules (BE at 70 % SL, 34 EMA trail) the defaults get wrong.

---

## 2. Modified PRESET_RRM_ORG settings

Inputs are the ones that exist in `SEA_Inputs.mqh` today. Three tiers: **Q-Core** (all TFs), **Q-Intraday** (adds sub-H1 gates), **Q-Aggressive** (unlocks the Oracle's UNO trades — needs code, see §3).

### 2.1 Q-Core — apply on every chart

| Input | Default | **Set to** | Why (evidence) |
|---|---|---|---|
| `Inp_RRM_ORG_DPI_RequireResetRecovery` | false | **true** | The single strongest separator in the tally (finding 1/2). Requires a colour flip and flip-back before a new entry = Oracle "reset". |
| `Inp_RRM_ORG_DPI_GrantFirstEntry` | true | **false** | With reset-recovery on, the cold-start exemption re-admits exactly the late-trend (Cluster C) entry it was meant to protect. |
| `Inp_RRM_ORG_DPI_ResetRecoveryBars` | 0 | **1** | One bar of confirmed recovery — the Oracle enters on the close *after* green vanishes, not on the flip bar. |
| `Inp_RRM_ORG_DPI_UseCCIReset` | false | **true** | Reset detection is defined on the CCI-driven colour (`README_SEA_SIGNAL_REFERENCE_DPI.md` §5); leave off and the reset gate is watching raw hist sign only. |
| `Inp_RRM_ORG_DPI_UseGreenHist` | true | true | Keep. GREEN present = Blue and hist aligned = the fresh impulse after a reset. |
| `Inp_Global_F_PriceExtFilterEnabled` | false | **true** | Direct encoding of Cluster C / manual VIII.D. |
| `Inp_RRM_ORG_PriceExtRefEma` | 3 | **4** | Measure distance to EMA89, the anchor whose distance separated A/B from C. |
| `Inp_RRM_ORG_PriceExtMaxATR` | 2.5 | **2.0** (H1+), **2.5** (≤M15) | Cluster C entries sat 2–4 ATR from EMA89; A/B sat inside ~1.5 ATR or on it. |
| `Inp_Global_F_EmaFanFilterEnabled` | false | **true** | Manual VIII.D "gap as wide as the longest candles" — the fan pips defaults are already per-TF. |
| `Inp_Global_F_ClimaxGuard_Enabled` | false | **true** | Finding 5 / manual VIII.B/E. |
| `Inp_Global_ClimaxGuard_BarATRMult` | 2.0 | 2.0 | Oracle "1.5–2× average candle" — keep. |
| `Inp_Global_ClimaxGuard_MoveATRMult` | 3.0 | 3.0 | Keep. |
| `Inp_Global_F_DpiDecelFilterEnabled` | true | true | Keep (blocks when GREEN is shrinking — Oracle "Follow line turning first"). |
| `Inp_RRM_ORG_BE_RMultiple` | 0.25 | **0.7** | Manual IV.E: BE after ~70 % of initial SL. At 0.25R the normal retest of the entry (seen in most Big trades) stops you at zero. |
| `Inp_RRM_ORG_TrailStartsAfterBE` | false | **true** | Let the trade breathe until BE; PSAR trail from bar 1 + `TrailAllowLossSide=true` was cutting Cluster B winners on the retest. |
| `Inp_RRM_ORG_TrailAllowLossSide` | true | **false** | Same reason. |
| `Inp_RRM_ORG_TPMode` | TP_MODE_RR | **TP_MODE_NONE** (H1+) / **TP_MODE_RR** (≤M15) | H1+: the payoff is in the tail (finding 7) — exit by trail. ≤M15: B-cluster runs are capped (25–50 pips on M5), keep a target. |
| `Inp_RRM_ORG_RRRatio` | 2.5 | **2.0** (≤M15 only) | M5/M15 A/B trades typically reached 2–3× the pullback depth; 2.5 left many at 80 %. |
| `Inp_RRM_ORG_TrailMode` | TRAIL_PSAR | **TRAIL_EMA** (H1+) / TRAIL_PSAR (≤M15) | Oracle "conservative" trail = 34 EMA for runners; PSAR ("aggressive") on intraday. |
| `Inp_RRM_ORG_TrailEMA_RibbonRole` | ROLE_EMA3 | ROLE_EMA3 (34) | Oracle *Letting Profits Run*: "use the 34 EMA to trail your stop loss". |
| `Inp_RRM_ORG_TrailEMA_Shift` | 3 | **1** | Trail the last closed bar's EMA; shift 3 lags a fast reversal by 3 bars. |
| `Inp_RRM_ORG_TrailEMA_CushionAtrMult` | 1.0 | **0.3** | "Not ON the EMA but a little bit above it." 1.0 ATR is wider than the pullbacks it is meant to survive. |
| `Inp_RRM_ORG_SLMode` / `SwingLookback` | SWING / 55 | SWING / **21** | Oracle: "most recent swing"; 55 bars frequently picks a swing from a previous leg and doubles the R unit. |
| `Inp_RRM_ORG_LayerS_TMOnly` | true | true | Matches the Strong card. |
| `Inp_RRM_ORG_MinPBBars_W/M/S` | 3/3/3 | 3 / 3 / **2** | S-layer recoveries in the set were slow-EMA edges; 3 bars occasionally missed the Shark entry bar (trade 18, 34). |
| `Inp_RRM_ORG_CandleBody_MinCloseRatio` | 0.75 | 0.75 | Keep — rejects doji signal bars (BD rule). |
| `Inp_RRM_ORG_DDMaxTradesPerDay` | 15 | **4** (H1+) / **8** (≤M15) | The 100-trade set averages well under one signal per pair-day; 15 is a chop budget. Manual IX.E "avoid overtrading". |

### 2.2 Q-Intraday — add on M1 / M5 / M15

| Input | Default | **Set to** | Why |
|---|---|---|---|
| `Inp_Session_Enabled` | true | true | Keep master on. |
| `Inp_Session_London` / `Inp_Session_NY` / `Inp_Session_Asia` | true / true / false | true / true / **false** | Already Oracle-correct — verify it was not overridden. |
| `Inp_Session_London_Margin` | 0 | **-1 via Win1** — use `Inp_Session_Win1 = true`, 07:00–12:00 EET | Six of the intraday "Big" trades fired 06:30–08:40 EET (pre-London/London open). Default 09:00 start misses them. |
| `Inp_Session_NY_Margin` | 0 | 0, and consider `Inp_Session_NY_End` 20:00 | Late-NY (after 20:00 EET) produced 2 of the 4 intraday Smalls in Cluster A (trades 91, 95). |
| `Inp_RRM_ORG_Use_MTF` | true | true | Keep. |
| `Inp_RRM_ORG_MTF_TF1` / `_TF2` | H1 / H2 | **M1: M5 / M15 · M5: M15 / H1 · M15: H1 / H4 · H1: H4 / D1 · H4: D1 / W1** | Oracle 4:1 rule; two levels on M1/M5 per *Multi-Timeframe*. Set per chart — the defaults only make sense on M15. |
| `Inp_RRM_ORG_MTF_RequirePhase` | true | true | HTF must be TM/EM — Oracle "conditions you would allow a trade on that timeframe". |
| `Inp_RRM_ORG_AllowLayerW` | true | **false on M1/M5** | Every intraday Cluster C entry was W-layer; A/B on M1/M5 fired on M or 89 anyway (tally rows 38, 43, 65–79). Keep W on M15+. |
| `Inp_RRM_ORG_PsarFlipDelay_W/M/S` | 5/5/5 | **2 / 3 / 5** | Manual VIII.C: "PSAR validate on the specific candle or the next"; a 5-bar window admits stale flips on fast layers. |
| `Inp_RRM_ORG_MinBarsAfterUNOExit` | 0 | **2** | Oracle: first move out of a sideways pattern can be a fake breakout — require two ordered bars before the first recovery edge. |
| `Inp_RRM_ORG_UNO_ToleranceBars` | 0 | **1** | Prevents a one-bar EMA flicker from wiping the layer state mid-pullback (seen on M1 JPY charts). |
| `Inp_RRM_ORG_JpyGateMultiplier` | 1.3 | 1.3 | Keep. |
| `Inp_Global_VETO_UseSpread` / `MaxSpread` | false / 3.0 | **true / 2.0** (majors), 4.0 (crosses) | Six intraday trades in the set show 3.1–6.1 pip spreads on 10–30 pip outcomes. |

### 2.3 Q-Aggressive — unlock the Oracle's UNO setups (code change, not an input)

`BlockUnorderedPhase=true` is locked in the preset. The Oracle explicitly trades two UNO cases; both need a new gate rather than simply setting the flag false:

1. **Shark-in-UNO**: EMA34/EMA89 ordered with bias (long-term trend intact), EMA13 between them, price touched EMA89 and the signal bar closes past EMA34 with BD, DPI reset→recovery complete, PSAR on side. (Manual III: "Shark … most of the time occurs in an Unordered Phase".)
2. **13/34 crossover out of UNO**: EMA13 crosses EMA34 in the direction of the EMA34/EMA89 order, on the bar of the cross or the next, same voters. (Manual III "Crossover Entry Examples".)

Suggested implementation: a `UNO_AllowSharkAndCross` flag in `EvaluateTS_Breakdown` that, when phase = UNO **and** EMA3/EMA4 are ordered, evaluates only LayerS (with a "price touched EMA4 within `LayerPullbackWindow_S` bars" test) or the 13/34 cross edge, and skips W/M. Everything else in UNO stays blocked. The Jump Trade (EMA5 outside EMA89 while EMA13 is inside) can be a third case on LayerW with the same voters.

---

## 3. Gaps that inputs cannot close (recommended code work, in priority order)

1. **Trend-age cap for LayerW** — bars since the last EMA13/EMA89 cross (or since EM→TM). Disable W entries when age > ~40 bars unless the pullback touched EMA34. This is the cleanest single separator of Cluster A from Cluster C and has no input today (`PriceExt` approximates it).
2. **UNO Shark / 13-34 crossover** — §2.3.
3. **Pre-cross compression score** — percentile of EMA5–EMA89 fan width over the last 30 bars at the moment of the cross; low percentile ⇒ upgrade the next 1–2 pullbacks (larger size or wider trail). Oracle *When Not To Trade* #1/#3 describes the setup phase; the tally shows it precedes the largest moves.
4. **HTF OB/OS check in the MTF voter** — the Oracle requires the HTF DPI not be overbought/oversold, not just phase-aligned. MTF currently checks EMA order only.
5. **Early-exit rules from manual VII** — two opposite-colour DPI bars with both Lead and Follow sloping against the trade; close through EMA13 early in the trade; "sideways after entry" scratch (no 1R progress in ~12 bars). None of these exist; the trail is the only exit.

---

## 4. Expected effect on the 100-trade sample

Applying §2.1 + §2.2 mechanically to the tally: 18 of the 20 Cluster C/D signals are removed (the two survivors are the H4/D1 trend-continuation trades that ran anyway), 4 of the 80 A/B signals are lost (three Asian-session A trades on M1/M5 and one H1 entry >2 ATR from EMA89 — trade 31, which was the post-climax one). Net: 76 signals kept, all with 0 scratches; Big+Good rate moves from 73 % (100 trades) to ~88 %. §2.3 would add back the UNO Sharks the EA never sees.

This is a description of a hand-classified reference set, not a backtest; the numbers are the ceiling the filters could reach, not a forecast.
