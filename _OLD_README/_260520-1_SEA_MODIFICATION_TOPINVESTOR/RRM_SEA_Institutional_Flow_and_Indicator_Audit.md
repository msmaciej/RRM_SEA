# SimpleEA: Institutional Flow Analysis, Indicator Audit & Recommendations

## Part 1: Institutional Flow — What SimpleEA Captures and What It Doesn't

### What Institutional Flow Actually Is

Institutional traders (banks, hedge funds, sovereign wealth funds, pension funds) move markets through sustained directional positioning. They cannot enter or exit quickly due to position size, so their activity creates characteristic patterns: persistent directional pressure across multiple time horizons, pullbacks as weaker participants take profits against the flow, and resumption as institutions re-enter at better levels.

A trend-following system doesn't predict what institutions will do — it detects the footprints they've already left and rides the continuation.

### What SimpleEA Already Captures

**4-EMA Phase Detection = Institutional Presence Detector**

When EMA13, EMA34, and EMA89 align in clean order (TM phase), this reflects sustained buying or selling pressure across three different time horizons (roughly 1-hour, 3-hour, and 7-hour lookbacks on M5). Retail activity doesn't sustain this — it takes accumulated institutional positioning. The EM phase (EMA4 sandwiched between EMA2 and EMA3) detects the moment institutional flow is building but hasn't fully established itself. The EMA slopes during EM typically confirm this transition is underway.

**Pullback-Recovery State Machine (P2) = Institutional Accumulation/Distribution Pattern**

The classic institutional rhythm is: push price → weaker hands take profits (pullback) → institutions re-enter at better levels (recovery). P2's NONE → DETECTED → RECOVERED state machine tracks exactly this cycle. The per-layer recovery ratios acknowledge that deeper pullbacks (L3/Strong, touching EMA34/EMA89 zone) represent more significant institutional levels and need less recovery confirmation because the structural support is stronger.

**PSAR Flip Timing (P1) = Momentum Shift Detection**

The PSAR dot flip marks the moment momentum shifts from "pullback in progress" to "new wave starting." With layer-aware windows, the system synchronizes this momentum signal with each layer's natural speed, matching the institutional re-entry timing for shallow (L1) versus deep (L3) pullbacks.

**DPI Momentum Voter = Trend Strength Confirmation**

The DPI histogram (MACD-core architecture) confirms that momentum aligns with the bias direction. Combined with CCI reset detection, it filters entries where price structure looks right but underlying momentum is absent or diverging.

### What SimpleEA Doesn't Capture (Gaps)

**1. Volume Profile (Partially Addressable)**

Institutions can't hide their size. The ideal signal: pullback on declining volume + recovery on rising volume = institutional accumulation. SimpleEA has MFI available but it's a blunt oscillator, not a comparative volume tool. For forex: tick volume is a rough proxy, not actual institutional volume. For metals, indices, and shares: real volume data is available and much more meaningful.

Recommendation: On non-forex instruments where real volume is available, MFI becomes more meaningful. Consider a volume-comparison extension to the P2 state machine (compare average volume during DETECTED state vs. first bars of RECOVERED state).

**2. Session-Aware Signal Quality**

Institutional participation clusters around London open (07:00-09:00 GMT), New York open (13:00-15:00 GMT), and the overlap (13:00-16:00 GMT). SimpleEA has time filters but uses them as binary gates. A setup during London-New York overlap has fundamentally different follow-through probability than the same setup during Asian session — the institutional backing is different.

Recommendation: The existing time filter is adequate when configured to high-participation hours. No code change needed — just operational discipline.

**3. ADX Trajectory (Implementable — See Part 2)**

Rising ADX with aligned EMAs = institutional flow building. Falling ADX with aligned EMAs = institutional distribution (exiting into the trend). The current ADX check is threshold-only — it doesn't measure whether ADX is rising or falling at entry time.

Recommendation: Add an ADX slope mode (see Part 2 for implementation details).

**4. Spread as Institutional Proxy**

When institutional players are active, spreads tighten (better liquidity). Widening spreads during what should be a recovery is a warning that the move may be driven by thin liquidity rather than genuine institutional re-entry. SimpleEA's spread check is purely cost-control, not diagnostic.

Recommendation: Low priority. The spread filter already protects against thin-liquidity entries operationally.

---

## Part 2: Indicator Audit — Bugs Found

### BUG 1: ATR Voter Always Rejects (CRITICAL)

**Root cause:** `Check_ATR()` reads `m_diag_last_atr_pips` (line 812), which is set by `AtrPips()` inside `CheckFilters()` (line 4335). But `CheckFilters()` is **defined and never called** from the pipeline. Therefore `m_diag_last_atr_pips` stays at its initialized value of 0.0.

**Effect:** With default `ATR_VoteMinPips = 5.0`, the check `0.0 < 5.0` always fails. **ATR voter always rejects when enabled.** This means any preset or configuration that enables ATR voting gets a permanent signal kill.

**Fix:** `Check_ATR()` should compute ATR directly from the indicator handle instead of relying on a cached value from an uncalled function:

```mql5
bool Check_ATR(int bias, int shift)
{
    if(IsCacheValidForShift(shift) && m_ind_cache.atr_result != -1)
       return (m_ind_cache.atr_result == 1);

    // BUG FIX: Compute ATR pips directly from indicator handle
    // instead of relying on m_diag_last_atr_pips (set by uncalled CheckFilters)
    double atr_raw = GetVal(h_atr, shift);
    double atr_pips = GlobalAtrPips(atr_raw, m_symbol);
    
    // Also update the diagnostic cache so UI/logs show the correct value
    m_diag_last_atr_pips = atr_pips;
    
    bool pass = true;
    if(m_settings.ATR_VoteMinPips > 0.0 && atr_pips < m_settings.ATR_VoteMinPips) pass = false;
    if(m_settings.ATR_VoteMaxPips > 0.0 && atr_pips > m_settings.ATR_VoteMaxPips) pass = false;
    m_ind_cache.atr_result = pass ? 1 : 0;
    
    if(m_settings.DebugFlow) {
       if(m_settings.Ind_Atr_Enabled)
          DebugLog(StringFormat("[IND_ATR] ENABLED | ATR=%.1f pips (Min=%.1f, Max=%.1f) | Result: %s",
                                atr_pips, m_settings.ATR_VoteMinPips, m_settings.ATR_VoteMaxPips, 
                                pass ? "PASS" : "FAIL"));
       else
          DebugLog("[IND_ATR] DISABLED - skipped");
    }
    return pass;
}
```

**Dependency:** Requires `h_atr` to be created. See Bug 2.

### BUG 2: VRC Silently Bypassed When ATR Voter Is Disabled (MODERATE)

**Root cause:** `h_atr` creation at line 3803 uses `bool need_atr = m_settings.Ind_Atr_Enabled;`. If ATR voter is disabled but VRC is enabled, `h_atr = INVALID_HANDLE`. VRC's `GetVolatilityRegime()` then gets `atr = 0.0` from `GetVal()` and returns `VOLATILITY_NORMAL` (fail-safe bypass).

**Effect:** VRC always passes when ATR voter is disabled, regardless of actual volatility regime. VRC depends on ATR data but the handle creation doesn't account for this dependency.

**Fix:** Change the `need_atr` condition to include VRC:

```mql5
bool need_atr = (m_settings.Ind_Atr_Enabled || m_settings.Ind_VRC_Enabled);
```

### BUG 3: ADX — Not a Bug, But Missing Slope Mode

The ADX implementation is functionally correct for its three existing modes (STATIC, DYNAMIC_PERCENTILE, PHASE_AWARE). However, none of these modes measure ADX direction/slope. A rising ADX above threshold means trend strength is building (institutional flow increasing). A falling ADX above threshold means trend strength is waning (institutional distribution).

**Recommendation:** Add a fourth mode `ADX_MODE_RISING` that requires both `adx >= threshold` AND `adx > adx_prev` (ADX is rising). This aligns with institutional flow methodology where you want to enter when participation is increasing, not decreasing.

```mql5
case ADX_MODE_RISING:
{
    double adx_prev = GetVal(h_adx, shift + 1);
    threshold = (double)m_settings.T_Adx;
    bool above = (adx >= threshold);
    bool rising = (adx > adx_prev);
    result = above && rising;
    modeStr = "RISING";
    break;
}
```

This would need a new enum value `ADX_MODE_RISING` added to the ADX mode enum in `SEA_Config.mqh`.

---

## Part 3: Multi-Instrument Considerations

### Forex (EURUSD, GBPJPY, etc.)

The system is designed primarily for forex. The 4-EMA periods (5/13/34/89) are well-calibrated for FX volatility. Volume data is tick-based only, so volume-dependent indicators (MFI, volume comparison) are approximate. The system works correctly but volume signals are less reliable.

### Metals (XAUUSD, XAGUSD)

Gold and silver have real volume on futures exchanges, and tick volume on CFD platforms correlates better with actual volume than forex pairs because metals are exchange-traded instruments. The EMA periods may need adjustment — gold tends to trend more persistently with deeper pullbacks, so the default EMA periods might produce too many L1 signals and not enough L3. Consider wider EMA spacing (e.g., 8/21/55/144) for metals.

The system's existing `GlobalPipSize()` function should handle the different pip sizes correctly, but verify that ATR/spread calculations work with gold's 2-decimal pricing versus forex 5-decimal pricing.

### Shares/Equities (AAPL, MSFT, etc.)

Equities have real volume data. MFI and volume-comparison signals become genuinely meaningful. Session timing is simpler (market hours are fixed). The key difference: equities gap overnight, which can trigger false phase transitions. The `MinBarsAfterWeekendGap` setting helps but may need extension to cover daily gaps.

The 4-EMA system works well on equities when traded on higher timeframes (H1+). On lower timeframes, equity-specific noise (market makers, HFT) can create false EMA alignments that don't reflect institutional positioning.

### Indices (US500, NAS100, GER40)

Similar to equities but with less overnight gap risk (futures trade nearly 24h). The EMA system translates well to indices. Volume data from futures is high quality. Consider enabling VRC (once Bug 2 is fixed) since volatility regime classification is particularly useful for indices which alternate between low-volatility drift and high-volatility institutional rotation periods.

---

## Part 4: Implementation Priority

| # | Item | Risk | Impact | Effort |
|---|------|------|--------|--------|
| Bug 1 | ATR voter fix (reads zero) | None | High — ATR currently broken | 5 min |
| Bug 2 | VRC h_atr dependency fix | None | Medium — VRC silently bypassed | 1 line |
| Bug 3 | ADX_MODE_RISING | Low | Medium — institutional flow alignment | 15 min |
| Config | Metal/equity EMA period recommendations | None | Informational | 0 (documentation) |
| Volume | Pullback vs recovery volume comparison | Medium | Medium (non-forex only) | Future consideration |

Bugs 1 and 2 should be fixed immediately as they represent broken functionality. The ADX slope mode (Bug 3) can be added when convenient. Volume comparison is a future enhancement for when the system is deployed on volume-rich instruments.
