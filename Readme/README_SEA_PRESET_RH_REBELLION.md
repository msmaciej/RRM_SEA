# PRESET_RH_REBELLION — Design & Documentation Draft

**Russ Horn "Forex Rebellion" 4-filter confluence preset for SimpleEA (RRM_SEA)**
**Status:** design draft — pre-implementation. Confirms scope before code is written.

`PRESET_RH_REBELLION` reproduces the **Forex Rebellion** system (Russ Horn, 2009) inside the SEA engine: an entry is taken only when **four independent filters agree**, with swing/EMA stops, a step-down-to-break-even manager, and a choice of RR or Donchian-channel exits. It reuses the existing SEA signal/risk pipeline almost entirely; the **one genuinely new component is a native QQE Adv voter** (marked NEW), because SEA has no QQE indicator today.

It is deliberately **not** a variant of `PRESET_XEMA` or `PRESET_RRM_ORG`. Its inputs live in a dedicated `Inp_RHR_*` namespace with no shared seeds leaking into other presets — the pattern that avoids the ambiguity that retired the old CUSTOM preset.

> **Naming.** The `RH_` prefix (Russ Horn) disambiguates this branded, discretionary-system reproduction from SEA's own trend-following presets. The system is a **confluence signal**, not a trend-following model in the CTA sense — all four filters are agreement gates, not a directional bias plus timing.

---

## 1. Signal architecture — how Rebellion maps onto the TS/TE equation

SEA evaluates `TS = B × P × F × L × I → CG`, then executes through the TE gate chain. Rebellion is a clean instantiation of that same pipeline: the **4/5 EMA cross supplies direction (B)**, phase and layer are inert, and the **other three Rebellion filters become unanimous I-voters**.

| Factor | In RH_REBELLION | Why |
|--------|-----------------|-----|
| **B** (direction) | **Supplied by the 4/5 EMA cross** (Rule 2). A bullish 4>5 cross emits +1, bearish −1. | The cross is the momentum trigger and the natural direction source, exactly as XEMA uses `STRAT_2EMA_CROSS_EMA`. |
| **P** (phase) | Inert (pass-through). | Phase is a 4-EMA ribbon concept; Rebellion has no phase model. |
| **L** (layer) | Inert (pass-through). | Layer pullback-recovery is a ribbon concept; Rebellion times entry off the cross. |
| **I** (indicators) | **Three unanimous voters:** shifted-5-EMA trend (Rule 1), QQE line-order (Rule 3), QQE zone (Rule 4). | These are the confluence filters. Under `VOTE_MODE_ALL`, all must pass — the system's defining "all four in line" rule. |
| **F** (filters) | Optional. | Available if wanted; off by default. |
| **CG** (climax) | Optional. | Available if wanted; off by default. |

**The confluence is the whole system.** With four agreement conditions (B + three I-voters, all unanimous), a signal fires only when the score is effectively ±4 — the exact "all four rules in line" behaviour the original EA panel prints.

> **Why the cross is B and the rest are I.** Rebellion's four rules are peers in the manual, but the engine needs one direction source. The 4/5 cross is the cleanest choice: it is the momentum trigger, it already exists as a locked-in strat, and making it B lets the other three ride the standard unanimous-I path. Rule 1 (price vs shifted 5 EMA) *could* have been B instead; it is kept as an I-voter so that all three "agreement" filters share one code path and one telemetry line (`I[3/3]`).

---

## 2. The four rules → engine mapping (verified against the original EA source)

The original `Forex Rebellion EA Lite.mq4` scores four ±1 rules and fires only at +4 / −4. Exact reproduction:

| # | Rebellion rule | Original EA test | SEA mapping | New? |
|---|----------------|------------------|-------------|------|
| **1** | Price vs shifted 5 EMA | `Close[1] ⋛ EMA(5, shift 5)` | **I-voter:** shifted-5-EMA read; `ma_h_shift = 5` on the trend EMA | Existing (`ma_h_shift`) |
| **2** | 4 / 5 EMA cross | `EMA(4) ⋛ EMA(5)` | **B:** `STRAT_2EMA_CROSS_EMA`, `Ema_Fast=4`, `Ema_Slow=5` | Existing |
| **3** | QQE line order | `QQE_RSI ⋛ QQE_signal` | **I-voter:** QQE RSI-line vs signal-line | **NEW (QQE voter)** |
| **4** | QQE zone | `QQE_RSI ⋛ 50` | **I-voter:** QQE RSI-line vs 50 level | **NEW (same QQE voter, 2nd test)** |

> **Faithfulness note — EA Lite vs. the manual.** The EA Lite simplifies Rules 3 & 4 to a *static position* test at the last closed bar ("is the RSI line above/below the signal, and above/below 50, right now?"). The **manual** describes them more strictly as *fresh crosses* (the RSI line crossing the signal line and then crossing the 50 line at candle close). `PRESET_RH_REBELLION` implements the **static-position** reading by default (it matches the shipped EA and is what a per-bar unanimous voter naturally expresses), with an optional `Inp_RHR_QQE_RequireCross` flag to demand a fresh cross for the higher-quality manual reading. Both are documented so results reconcile against either reference.

---

## 3. The NEW component — native QQE Adv voter

SEA has **no QQE indicator** (confirmed: zero references across the codebase). There is a plain RSI voter with an `RSI_TREND_ABOVE_50` mode, but that is raw RSI with no signal line — it can approximate Rule 4 only, never Rule 3. Rebellion therefore requires a real QQE.

**Implementation model: the inline CI voter** (`CalculateCI` / `Check_CI`). Like CI, QQE will be a self-contained `CalculateQQE()` + `Check_QQE()` pair computed inline from `iRSI` — native, no external `.ex4` dependency, cannot crash the EA.

### 3.1 The QQE Adv algorithm (SF=1, RSI=8, WP=3)

Reproduces `QQE_ADV.ex4` as used by the template:

```
RSI_raw(i)   = iRSI(RSI_Period=8, PRICE_CLOSE)(i)
RSI_line(i)  = EMA(SF=1, RSI_raw)(i)              // SF=1 ⇒ effectively the RSI itself
ATR_RSI(i)   = |RSI_line(i) − RSI_line(i−1)|      // "true range" of the RSI line
MA_ATR(i)    = Wilder(WP=3, ATR_RSI)(i)           // first Wilder smoothing
DAR(i)       = Wilder(WP*2+ ... , MA_ATR)(i) × 4.236   // smoothed, scaled band (QQE "delta")
signal_line(i) = trailing-stop of RSI_line by ±DAR(i)  // the Wilder signal line
```

- **RSI_line** = the blue line (buffer 0 in the .ex4).
- **signal_line** = the red line (buffer 1). Standard QQE trailing-band construction using the Wilder-smoothed average of the RSI's bar-to-bar change, scaled by the QQE constant 4.236.
- **50 level** = fixed, non-parameterised.

The two votes read exactly what the EA read: `iCustom("QQE ADV", 0, 1)` = RSI_line, `iCustom("QQE ADV", 1, 1)` = signal_line.

### 3.2 The two votes

| Vote | Test (LONG / SHORT) | Rebellion rule |
|------|---------------------|----------------|
| **QQE line order** | RSI_line > signal_line / < signal_line | Rule 3 |
| **QQE zone** | RSI_line > 50 / < 50 | Rule 4 |

Both are cast on the entry TF at bar close (shift 1), both must pass under `VOTE_MODE_ALL`. With `Inp_RHR_QQE_RequireCross=true`, each additionally requires the relevant line to have *crossed* on the signal bar (prev-vs-curr), matching the manual.

> **Effort estimate.** Comparable to the CI/DPI inline voters: one `CalculateQQE()` (RSI read + two Wilder passes + trailing-stop state), one `Check_QQE()` casting two votes, plus a handful of `Inp_RHR_QQE_*` inputs and telemetry lines. No external file, no new dependency.

---

## 4. Locked vs. flexible

**Locked (defines the preset's identity):**

- `BiasMode = BIAS_2EMA`, `AutoStrat = STRAT_2EMA_CROSS_EMA` — the 4/5 cross as B.
- `Ema_Fast = 4`, `Ema_Slow = 5` (the template values; user-adjustable only via the RHR inputs, not shared).
- QQE voter ON, both votes active; RSI/other momentum voters OFF (QQE replaces them).
- Phase / Layer detection off (inert by mode).
- `VOTE_MODE_ALL` — unanimous confluence.

**Flexible (`Inp_RHR_*` inputs):**

| Group | Inputs | Notes |
|-------|--------|-------|
| Trend EMA (Rule 1) | `Trend_Ema_Period` (5), `Trend_Ema_Shift` (5) | the shifted 5 EMA; `ma_h_shift` carries the displacement. |
| Cross EMAs (Rule 2 / B) | `Ema_Fast` (4), `Ema_Slow` (5) | the 4/5 cross. |
| QQE (Rules 3 & 4) | `QQE_SF` (1), `QQE_RSI_Period` (8), `QQE_WP` (3), `QQE_RequireCross` (false) | native voter; cross-mode optional. |
| Stop loss | `SLMode` (`SWING`), `SwingLookback`, and `SL_Mode=EMA-edge` option via 5-EMA | swing or 5-EMA-edge stop (both from the manual). |
| Exit target | `ExitMode` (`RR` / `DONCHIAN`), `RR_Ratio` (1.0 or 1.5), `Donchian_ExitPeriod` (21) | the "100", the "1 Point 5", or the Donchian wall. |
| Break-even ladder | `BE_Mode` (`R_MULTIPLE`), `BE_RMultiple`, LPR steps | step-down-to-BE manager (see §6). |
| Entry order | `PendingBufferPips` | pending stop a few pips beyond the signal candle. |
| Trade management / risk (RC) | inherited globals — per-TF risk, `MaxTotalRisk`, `MaxOpenTrades` | apply under any preset; no new risk logic. |
| Instruments | inherited | JPY / metals / indices / crypto auto-detected. |

---

## 5. Entry, stop, and exit — the manual's rules, wired to SEA

### 5.1 Entry (all four in line)

`TS = 1` fires when: the 4/5 cross gives a direction (B ≠ 0) **and** all three I-voters agree (shifted-5-EMA trend, QQE line-order, QQE zone). Then TE places the order.

**Pending-order tactic.** The manual enters a few pips *beyond* the signal candle, not at market. Mapped to the TE side via `Inp_RHR_PendingBufferPips` — a stop order at `signalCandle.High + buffer` (long) / `signalCandle.Low − buffer` (short). This reuses the existing pending/stop-entry path; if not wired for stop orders yet, it is a small TE addition (marked NEW-small below).

### 5.2 Stop (two options, both native)

- **Swing** (default): `SL_MODE_SWING`, `SwingLookback` ≈ recent swing — the manual's "safest" stop.
- **5-EMA edge**: place beyond the shifted-5-EMA high/low — reuses the EMA read; a thin `SL_MODE_EMA_EDGE` wrapper or the existing EMA-based SL path.

### 5.3 Exit (three, all native)

- **The "100" (1:1):** `TP_MODE_RR`, `RR_Ratio = 1.0` (+ spread).
- **The "1 Point 5" (1:1.5):** `TP_MODE_RR`, `RR_Ratio = 1.5` — the manual's default.
- **Donchian wall:** `Donchian_UseChannelExit = true`, `Donchian_ExitPeriod = 21` — already wired for Turtle/Trend; exit on the opposite 21-bar channel, or trail under the 5 EMA via `TRAIL_EMA`.

---

## 6. Trade management — reduce risk to zero (native)

The manual steps the stop down: at +½R → −½R (risk halved), at +1R → break-even, then trail. This maps directly to the existing managers:

- **Step-to-BE:** `BE_MODE_R_MULTIPLE` with `RRM_BE_RMultiple = 1.0` moves the stop to break-even at +1R.
- **Half-risk step + laddered lock:** the universal **Let-Profit-Run ladder** (`LPR_*`) provides the intermediate ½R lock and any further steps (e.g. trig 0.5 → lock −0.5, trig 1.0 → lock 0.0).
- **Break-even + spread:** nudge the BE stop into profit by the spread (existing `RRM_BE_BufferPips` / TF cushion).
- **Trend trail:** `TRAIL_EMA` follows the 5 EMA for the "ride the trend" exit.

No new risk logic is required — the entire manager chain already exists.

---

## 7. New code vs. existing — honest inventory

| Item | Status |
|------|--------|
| 4/5 EMA cross as B (flexible periods) | Existing (`STRAT_2EMA_CROSS_EMA`) |
| Shifted-5-EMA trend read (Rule 1) | Existing (`ma_h_shift`) |
| Unanimous 3-voter confluence | Existing (`VOTE_MODE_ALL`) |
| Swing SL / 5-EMA-edge SL | Existing (`SL_MODE_SWING`, EMA read) |
| RR exits ("100" / "1 Point 5") | Existing (`TP_MODE_RR`) |
| Donchian(21) channel exit | Existing (`Donchian_UseChannelExit`, from Turtle/Trend) |
| 5-EMA trailing exit | Existing (`TRAIL_EMA`) |
| Step-to-BE + ½R lock ladder | Existing (`BE_MODE_R_MULTIPLE` + `LPR_*`) |
| Per-TF risk / RC / instrument detection | Existing (inherited globals) |
| **Native QQE Adv voter (Rules 3 & 4)** | **NEW** (~inline CI-sized: `CalculateQQE` + `Check_QQE`, two votes, `Inp_RHR_QQE_*`) |
| **Pending stop-order entry beyond the signal candle** | **NEW-small** (if the stop-order TE path isn't already exposed) |
| **Optional QQE fresh-cross mode** (manual-strict Rules 3&4) | **NEW-small** (`Inp_RHR_QQE_RequireCross`) |

**Bottom line:** the execution/risk/exit chassis and two of the four entry signals are native. The only substantive new work is the **QQE Adv voter**; everything else is wiring.

---

## 8. Deployment checklist

1. Add `PRESET_RH_REBELLION` to the `EStrategyPreset` enum + a `#define SEA_BUILD_RH_REBELLION` in `SEA_Config.mqh`.
2. Add the `Inp_RHR_*` input block (own namespace, no shared seeds) in `SEA_Inputs.mqh`, guarded by `#ifdef SEA_BUILD_RH_REBELLION`.
3. Implement `CalculateQQE()` + `Check_QQE()` in `SEA_SignalEngine.mqh`, modelled on `CalculateCI`/`Check_CI`; register two votes and telemetry (`QQEord`, `QQEzone`).
4. Add the `ApplyPreset()` block: lock the 4/5 cross as B; `ma_h_shift=5` trend EMA; enable QQE voter (both tests); `VOTE_MODE_ALL`; `SL_MODE_SWING`; `TP_MODE_RR` (RR configurable) or Donchian exit; BE ladder.
5. Register in `GetPresetName()` / `GetPresetDescription()`.
6. Wire the pending-order buffer on the TE side (if not already available).
7. Compile; validate the QQE voter against `QQE_ADV.ex4` on a chart (values should match `iCustom("QQE ADV",…)` bar-for-bar) before trusting signals.
8. Backtest one pair on H1 with all four rules ON; confirm entries line up with the EA-panel "all four in line" bars.
9. Keep the confluence unanimous — all four agreeing is the system; loosening it changes what "Rebellion" means.

---

## 9. Known differences from the original (documented, not hidden)

- **QQE fidelity:** the native voter must be validated bar-for-bar against `QQE_ADV.ex4`. QQE has several public variants; this spec targets the SF/RSI/WP=1/8/3 build the template ships. Until validated, treat QQE signals as provisional.
- **Static vs. cross reading (Rules 3&4):** default is static-position (matches the EA panel); `QQE_RequireCross` gives the manual-strict cross reading. They will disagree on a minority of bars.
- **Discretion removed:** the manual leaves signal-clarity, market-regime and target choice to the trader ("is the close *clearly* past the 5 EMA?"). The preset makes these mechanical (a close past the EMA is a pass, period). This is the usual price of automating a discretionary system and should be expected to change the trade set at the margins.
- **Secondary / stale QQE signals** (manual §QQE) are not modelled as separate entries in v1; only the primary all-four-in-line entry fires.
