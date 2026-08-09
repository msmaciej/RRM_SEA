# PRESET_XEMA — Design & Documentation Draft

**EMA-cross trend-following preset for SimpleEA (RRM_SEA)**
**Status:** design draft — pre-implementation. Confirms scope before code is written.

`PRESET_XEMA` is a self-contained, flexible trend-following preset whose **entry and exit are an EMA crossover**. It is built almost entirely from logic that already exists in the SEA engine; only a small number of additions are genuinely new (marked NEW). The name leaves room for other entry/exit logic to be added later without redefining the preset.

It is deliberately **not** a variant of `PRESET_TOPINVESTOR` or the retired `PRESET_CUSTOM`. Its inputs live in a dedicated `Inp_XEMA_*` namespace with no shared seeds leaking into other presets — the pattern that avoids the ambiguity that got the old CUSTOM removed.

---

## 1. Signal architecture — how XEMA maps onto the TS/TE equation

SEA evaluates `TS = B × P × F × L × I → CG`, then executes through the TE gate chain. XEMA is a clean instantiation of that same pipeline with two factors switched off:

| Factor | In XEMA | Why |
|--------|---------|-----|
| **B** (direction) | **Supplied by the cross.** A bullish 20/50-style cross emits +1, a bearish cross −1. | The cross *is* the direction. B is not a separate knob and is **not** "always 1" — on a bar with no fresh cross the signal is simply 0. |
| **P** (phase) | Inert (pass-through). | Phase is a 4-EMA/ribbon concept; the cross replaces it. |
| **L** (layer) | Inert (pass-through). | Layer pullback-recovery is a 4-EMA concept; the cross is the entry timing. |
| **I** (indicators) | **HTF confirmation + optional anti-range voters.** | The higher-timeframe agreement is a *veto voter*, not the bias (see §2). Range filters live here too (see §4). |
| **F** (filters) | Optional. | Available if wanted; off by default. |
| **CG** (climax) | Optional. | Available if wanted; off by default. |

**Exit** is the opposite cross: `CloseOnReverse = true`, `TPMode = TP_MODE_NONE` (no fixed target — the trade runs until the trend turns). This is the "let profits run" exit, and it is the single most important design choice for staying in the trend-following family.

> **The HTF is confirmation, not bias.** It must live in **I**, never in **B**. Reason: the higher-timeframe trend should *permit or block* a cross, never *flip* its direction. If HTF disagrees → the MTF voter returns 0 → I = 0 → TS = 0 → the trade is blocked. That is exactly the "only trade with the higher-timeframe trend" gate.

---

## 2. Locked vs. flexible

**Locked (defines the preset's identity):**

- `BiasMode = BIAS_2EMA`, `AutoStrat = STRAT_2EMA_CROSS_EMA` — the cross engine.
- `CloseOnReverse = true`, `TPMode = TP_MODE_NONE` — exit on the opposite cross.
- Phase / Layer detection off (inert by mode).

**Flexible (`Inp_XEMA_*` inputs):**

| Group | Inputs | Notes |
|-------|--------|-------|
| Entry cross | `Ema_Fast`, `Ema_Slow` | 20/50, 34/89, 50/200 … fully user-defined. Different charts can run different speeds (see §5). |
| HTF confirmation (I) | `MTF_Enabled`, `MTF_TF1`, `MTF_TF2`, `MTF_EMA_Fast`, `MTF_EMA_Slow`, `MTF_RequirePhase` | one or two HTFs; **single EMA** per HTF when Fast == Slow (slope mode), **pair** when Fast ≠ Slow; both HTFs must agree (strict AND). See §3. |
| Anti-range voters (I) | `Use_Adx`, `Use_Bb`, `Use_CI` (+ their periods/thresholds) | entry-TF trend-quality gates. See §4. |
| Stop loss | `SLMode` (`SWING` / `ATR`), `SwingLookback`, `SL_AtrPeriod`, `SL_AtrMult` | at-entry SL uses existing logic. |
| Exit management | `BE_TriggerR`, ladder steps, `TrailMode`, `TrailStartsAfterBE`, `TrailLockProfit` | see §6. |
| Trade management / risk (RC) | inherited globals — **per-TF risk** via `GetEffectiveRiskPercent()` (M1 1.0% / M5 1.5% / M15+ 2.0%), `MaxTotalRisk`, `MaxOpenTrades` | apply under any preset; no new risk logic. |
| Instruments | inherited | JPY / metals / indices / crypto auto-detected; adaptive spread + TF cushions apply. |
| Daily goal (universal) | `Inp_Global_DailyTarget_Enabled`, `Inp_Global_DailyTarget_Pct` | global feature, all presets except MA; see §5. |

---

## 3. HTF confirmation — flexible by design

- **Per HTF:** one EMA (slope mode, set Fast == Slow) **or** two EMAs (position/slope pair, Fast ≠ Slow).
- **Number of HTFs:** one (set `MTF_TF2 = PERIOD_CURRENT`) or two.
- **When two HTFs are set:** both must agree with the cross direction (strict AND). A trade is allowed only in the direction of the higher-TF trend(s).
- **Periods flexible:** e.g. trade M5 with 20/50, confirm on M15 and H1 both at 20/50 — or one HTF on D1 with a single EMA, etc.

> **Current-engine note (small extension needed for one case):** the MTF voter today uses **one** EMA-period pair (`MTF_EMA_Fast/Slow`) shared across *both* HTFs. So "same 20/50 on both HTFs" works out of the box. **Different periods per HTF** (e.g. HTF1 = 20/50, HTF2 = single EMA 100) would need two small per-HTF period fields — a minor addition. Decide before coding whether v1 needs independent per-HTF periods or shared is acceptable.

---

## 4. The three market-alignment conditions (REQUIRED — read before deploying)

An EMA-cross system flows *with* the market by construction — it buys strength and sells weakness. It becomes the naive retail trap only if one of the three conditions below is broken. **All three are mandatory for this preset.**

### Condition 1 — the HTF filter is mandatory, not optional

The single biggest weakness of any crossover is whipsaw in ranging markets. Only taking crosses aligned with the higher-timeframe trend is the primary defence. Keep `MTF_Enabled = true` and treat it as a hard gate. Turning it off converts XEMA into a raw crossover and is not a supported configuration.

### Condition 2 — exits must let profits run

Use the reverse-cross exit (and/or a trailing ratchet), **never a tight fixed take-profit.** A few large winners pay for many small losers; a small fixed TP quietly turns this into a losing system. `TPMode = TP_MODE_NONE` + `CloseOnReverse = true` is the design and should stay the default.

### Condition 3 — calibrated expectations

Expect a **low win rate (~30–40%)** and long flat / drawdown stretches while markets range. This is normal and unavoidable for the trend-following family. The failure is abandoning the system during the ranging phase that always precedes the trend that pays. Size positions so those stretches are survivable.

> **The failure mode to avoid** is a single-pair, over-optimized, tight-TP crossover — that fights the market. XEMA's defaults reject all three of those. The genuine remaining gap versus institutional trend-following is diversification (§5), not the signal itself.

---

## 5. Anti-range protection (the "HTFs agree but the entry TF is ranging" problem)

The HTF filter confirms higher-timeframe **direction**. It does **not** guarantee the *entry* timeframe is trending. Real scenario: HTF1 (M15) and HTF2 (H1) both point up, but M5 is chopping sideways — the 20/50 crosses back and forth and roughly half the crosses would be entered, all in a market with no move to catch. This is the classic crossover leak, and it needs a **separate entry-TF trend-quality gate**, distinct from the HTF direction gate.

Available as toggleable I-voters (all evaluated on the entry TF):

| Voter | Input | What it does | Dependency |
|-------|-------|--------------|------------|
| **ADX** (recommended primary) | `Ind_Adx_Enabled`, `ADX_MODE_DYNAMIC_PERCENTILE` | Blocks when trend strength is below the adaptive percentile — i.e. the entry TF is ranging. | None (native) |
| **BB widening** (recommended secondary) | `Ind_Bb_Enabled`, `BbMode = BB_WIDENING` | Requires bands to be actively expanding (volatility breakout). In a range, bands are flat/contracting → block. | None (native) |
| **Choppiness Index** (optional, most direct) | `Ind_CI_Enabled`, `CI_RangingThreshold` (≈ 61.8) | Purpose-built range detector; CI above threshold = choppy → block. | **None — native.** The CI vote is computed inline by the engine (correct Dreiss/TradingView formula since the A7 fix, 2026-06); no external file, cannot crash. Only the optional chart *visualisation* is external. |

**Recommended anti-range default for XEMA:** ADX (dynamic percentile) ON as the primary range filter, BB-widening available as a second confirmation, CI optional (native — no install needed). These are the mechanism that answers the M5-ranging scenario directly: low ADX on M5 → ADX voter returns 0 → the whipsaw crosses are filtered out even while both HTFs agree.

---

## 6. Realistic diversification, correlation, and daily goal

We cannot run a 50–100-market CTA book. The realistic universe is a **handful (≈2–8) of instruments**: FX majors/crosses, metals, and (already prepared in SEA) indices and crypto. The goals are therefore: get enough signals from a small basket, cap correlated exposure, and lock in the day once a goal is reached.

### 6.1 Correlation — the honest constraint and the practical fix

SEA's risk caps (`MaxTotalRisk`, `MaxOpenTrades`, `Safety_MaxPositionsPerDir`) filter by symbol + magic, so **they are per-chart, not account-wide.** Running 6 correlated pairs at full risk each = up to 6× the intended aggregate exposure, and the existing caps will not catch it.

Practical mitigations, in order of effort:

1. **Size per-chart risk low.** If all 6 charts can fire at once, set each to ~0.25–0.5% so worst-case aggregate stays ~1.5–3%. Simplest, effective, no code.
2. **Choose a low-correlation basket.** Do not run tightly linked instruments together (e.g. EUR/USD + GBP/USD + EUR/GBP share the same USD/EUR risk). Prefer one instrument per currency block plus a metal and an index. Manual, no code.
3. **Per-TF risk is the intended control.** Risk stays governed by the existing `GetEffectiveRiskPercent()` (M1/M5/M15+ tiers) — no separate account-wide risk logic is added, by design. Aggregate basket exposure is managed by keeping those per-TF tiers modest and by low-correlation basket selection (above).

### 6.2 Daily goal (universal feature)

No daily profit target existed. It is added as a **global** feature (`Inp_Global_DailyTarget_*`) available to every preset except MA: track daily realized P&L (balance delta since day-start); once it reaches the target %, block new entries for the rest of the day while open trades keep running. This delivers the close-the-day-after-reaching-goal behaviour and banks a good day.

### 6.3 EMA-speed diversification

Because `Ema_Fast`/`Ema_Slow` are free inputs, the same preset can run different speed sets on different charts (e.g. 20/50 on one, 34/89 on another). This diversifies the lookback and reduces the curve-fitting risk of betting on one "best" period pair — the retail analogue of a CTA running multiple trend horizons. Recommended over optimizing a single pair on backtest.

---

## 7. New code vs. existing — honest inventory

| Item | Status |
|------|--------|
| 2-EMA cross entry, flexible periods | Existing (`STRAT_2EMA_CROSS_EMA`) |
| HTF confirmation (1–2 HTFs, single EMA or pair) | Existing (MTF voter) — **shared periods across both HTFs**; per-HTF distinct periods = small extension |
| Anti-range voters (ADX / BB / CI) | Existing (toggleable I-voters) |
| SL at swing / ATR, adaptive cushions | Existing |
| Move SL to BE at chosen R | Existing (`BE_MODE_R_MULTIPLE`) |
| Exit on opposite cross ("let run") | Existing (`CloseOnReverse` + `TP_MODE_NONE`) |
| Stock trailing modes | Existing (PSAR / fractal / %-peak / fixed-pips / EMA) |
| TM / RC / lot sizing / instrument detection | Existing (inherited globals) |
| **Laddered R profit-lock (universal, all presets except MA)** ("let profit run" ladder) | **NEW** (~40–60 lines, modeled on R-multiple BE) |
| **Daily profit target / stop-for-day** (universal, all presets except MA) | **NEW** (~30–50 lines) |
| **Per-HTF distinct EMA periods** (only if wanted) | **NEW, small** |
| Account-wide aggregate-risk cap | **Dropped** — risk stays per-TF via existing machinery; no new risk logic. |

---

## 8. Deployment checklist

1. Add `PRESET_XEMA` to the `EStrategyPreset` enum + a `#define SEA_BUILD_XEMA`.
2. Add the `Inp_XEMA_*` input block (own namespace, no shared seeds).
3. Add the `ApplyPreset()` block: lock the cross engine + reverse-cross exit; wire every other field to `Inp_XEMA_*`.
4. Register in `GetPresetName()` / `GetPresetDescription()` and add an exit-config validator.
5. Wire the universal NEW pieces (R-ladder "let profit run" + daily goal — global inputs, all presets except MA). Risk stays per-TF; no account-wide cap is added.
6. Compile; backtest on one pair with HTF filter + ADX ON first.
7. Add pairs one at a time; rely on the per-TF risk tiers (M1 1.0% / M5 1.5% / M15+ 2.0%) and low-correlation basket selection to bound aggregate exposure — no account-wide cap by design.
8. Keep all three §4 conditions intact — they are the difference between flowing with the market and fighting it.
