# RRM_SEA Repository Analysis & PRESET_RRM_ORG Modification Proposals

## 1. Repository Architecture Summary

SimpleEA is a modular MQL5 Expert Advisor implementing a **9-step multiplicative signal pipeline**:

```
TS = B × P × L × I × F
```

Where any factor = 0 kills the signal. The code is split across six header files (`SEA_Config.mqh`, `SEA_Presets.mqh`, `SEA_SignalEngine.mqh`, `SEA_TradeExecutor.mqh`, `SEA_UI.mqh`, `SEA_Reporting.mqh`) plus the main `SimpleEA_v1-04.mq5`.

**Key architectural insight**: PRESET_RRM_ORG is the "original Russ Horn RRM" variant that adds the inline DPI momentum voter on top of the base PRESET_RRM structure. It uses `VOTE_MODE_ALL` — every enabled indicator must pass or the signal dies.

---

## 2. The 100-Trade Dataset: Observations

Having examined the trade screenshots from the `RRM-100-trades/` folder and the reference cheat sheets in `RRM-Setups/`:

**What the original RRM methodology prescribes** (from the Trade Setups PNG):

| Layer | Bullish Setup | Bearish Setup |
|---|---|---|
| **Weak** (L1) | Price pulls back to touch EMA2, closes above EMA1. EMA1 never crosses below EMA2. | Mirror |
| **Medium** (L2) | Price pulls back to touch EMA3, closes above EMA2. EMA1 becomes unimportant. | Mirror |
| **Strong** (L3) | Price pulls back to touch EMA4, closes above EMA3. Trending phase only. | Mirror |

**The RRM Trade Checklist confirms the canonical entry sequence:**
1. DPI/MACD evaluated as =1 (momentum direction)
2. Market in Emerging or Trending Phase
3. Trade setup identified (W/M/S layer)
4. PSAR dot on correct side (below price for long, above for short)
5. Enter at close of candle that confirms all requirements

**Common patterns observed across the 100 trades:**
- Trades on M1, M5, M30, H4, Daily across USDJPY, EURJPY, GBPUSD, GBPJPY, EURUSD
- The DPI subwindow (yellow = bullish histogram, red = bearish) is present on every chart
- PSAR dots (green dots) flip direction coinciding with the pullback-recovery moment
- The 4 EMAs form a visible ribbon: white (EMA1/5), yellow (EMA2/13), red (EMA3/34), blue (EMA4/89)
- Best trades show price pulling back INTO the EMA zone, then a strong momentum candle closing beyond the relevant fast EMA with PSAR flipping simultaneously

---

## 3. Current PRESET_RRM_ORG Implementation Analysis

### What PRESET_RRM_ORG Currently Does Well

The preset correctly locks the core architecture:
- `BIAS_4EMA` + `STRAT_4EMA_LAYER` + `VOTE_MODE_ALL`
- Phase detection ON, UNORDERED blocked
- Layer-aware bar close (`BC_LAYER_AWARE`): bcW→EMA1, bcM→EMA2, bcS→EMA3
- DPI voter as primary momentum gate
- PSAR with flip-delay tracking
- CandleBody spike rejection
- Phase-age confirmation (MinPhaseConfirmBars) to kill single-bar TM flickers
- EMA fan overextension filter (TF-scaled)
- DPI deceleration pre-filter
- JPY pair gate multiplier for recovery distance

### Where TS=1 Quality Can Be Improved

After studying the code and cross-referencing with the 100-trade dataset, here are the key bottlenecks and failure modes:

#### Problem A: Layer Slope Check Is Binary — Misses Early Recovery

`CheckLayerPairAlign()` (line 2405) requires **both** EMAs to have strictly positive slope (for LONG) on the evaluation bar. But the canonical RRM setup fires when price has *just* recovered — the fast EMA may still be flat or barely turning. The current code:

```mql5
slope_fast_aligned = (bias == 1) ? (ema_fast > ema_fast_prev) : ...
slope_slow_aligned = (bias == 1) ? (ema_slow > ema_slow_prev) : ...
```

This strict `>` means a fast EMA that's flat (equal to previous bar) fails. On M1/M5 this happens frequently during legitimate recoveries where price has closed strongly above the EMA but the EMA value hasn't yet "turned the corner."

**The `Layer_SlopeTolerance` setting exists** (line 2465) but is hardcoded to 0.0 in PRESET_RRM_ORG (line 1693: `cfg.Layer_SlopeTolerance = 0.0`). The tolerance code path is dead.

#### Problem B: PSAR Flip Timing vs. Layer Recovery Desynchronization

The RRM methodology says: pullback happens → price recovers → PSAR dot flips → enter at close. But in the code, the PSAR flip and layer recovery are evaluated independently. A common scenario:

1. Bar N-2: PSAR flips to bullish (dot goes below price)
2. Bar N-1: EMA slope hasn't turned yet (layer still fails)
3. Bar N: EMA slope turns, layer passes, but PSAR flip is now 2 bars old

If `Vote_PsarFlipDelay = 0` (flip-bar-only mode), this valid setup is rejected because the PSAR flip "expired." If `Vote_PsarFlipDelay = -1` (persistent), it's too loose and accepts stale flips from many bars ago.

#### Problem C: No Distinction Between "Pullback Quality" Across Layers

Currently all three layers use the same `CheckLayerPairAlign()` with identical slope strictness. But the original RRM treats them differently:
- **Weak (L1)**: shallow pullback — price barely dips to EMA2, fast recovery expected. Speed matters.
- **Medium (L2)**: deeper pullback — price reaches EMA3, EMA1 becomes "unimportant."
- **Strong (L3)**: deep pullback to EMA4 — slowest recovery, needs most confirmation, highest probability.

The code applies uniform gate widths regardless of layer depth.

#### Problem D: Bar Close Check Doesn't Distinguish Wick-Through from Body-Through

`Check_BarClose()` checks `close > ema_value` for LONG. But a candle that closed 0.1 pips above the EMA after a deep wick below it is very different from a strong bullish candle that opened and closed well above. The current code treats them identically.

#### Problem E: DPI Deceleration Filter Can Be Too Aggressive

The DPI decel pre-filter (line 5770) blocks when `|hist_cur| < |hist_prev|` — i.e., histogram magnitude shrunk by even 1 tick. During the natural oscillation of a recovering pullback, the histogram often ticks down for a bar before continuing. This rejects many valid setups that are simply in the "second push" of momentum.

---

## 4. Proposed Modifications for Better TS=1 and TE=1 Quality

### Proposal 1: Layer-Specific PSAR Flip Synchronization Window

**Concept**: Instead of a single `Vote_PsarFlipDelay` value, make the PSAR flip acceptance window **layer-aware**. Deeper layers (L3) get a wider window because recovery from EMA4 naturally takes longer.

**Implementation sketch** (in `SEA_Presets.mqh`, PRESET_RRM_ORG block):

```mql5
// NEW INPUTS
input int  Inp_RRM_ORG_PsarFlipDelay_W = 1;  // LayerW: 1 bar after flip
input int  Inp_RRM_ORG_PsarFlipDelay_M = 2;  // LayerM: 2 bars after flip
input int  Inp_RRM_ORG_PsarFlipDelay_S = 3;  // LayerS: 3 bars after flip
```

**In `SEA_SignalEngine.mqh`**, modify the PSAR check to accept the active layer context:

```mql5
// In EvaluateL(), after determining which layer is active,
// pass the layer-specific delay to Check_PSAR_WithFlip:
int effective_delay = (m_last_layer == 3) ? m_settings.PsarFlipDelay_S
                    : (m_last_layer == 2) ? m_settings.PsarFlipDelay_M
                    :                        m_settings.PsarFlipDelay_W;
```

**Why this helps**: L3 (Strong) setups by definition involve price pulling all the way back to EMA4. The PSAR typically flips 1-3 bars before the fast EMA slope turns. Giving L3 a 3-bar window captures the natural lag without loosening L1 (where flip and recovery should be nearly simultaneous).

---

### Proposal 2: Recovery-Momentum Gate with Layer-Scaled Thresholds

**Concept**: Replace the binary slope check with a **ratio-based recovery gate** that's calibrated per layer. The `LayerPullbackEnabled` infrastructure already exists but isn't connected to PRESET_RRM_ORG.

**Implementation** (in PRESET_RRM_ORG block):

```mql5
cfg.LayerPullbackEnabled        = true;   // Currently not set in ORG
cfg.LayerBaselineLookback       = (_Period <= PERIOD_M5) ? 8 : 10;
cfg.LayerPullbackRatio          = 0.5;    // 50% weaker = pullback detected
cfg.LayerRecoveryRatio          = 0.3;    // 30% strength = recovery confirmed
cfg.LayerFlatRatio              = 0.1;    // 10% = flat
cfg.LayerAllowReversalPullback  = true;   // slope reversal counts as pullback
```

**Additionally, add layer-specific recovery ratio overrides:**

```mql5
// NEW: Deeper layers need less slope recovery (they're structural)
input double Inp_RRM_ORG_RecoveryRatio_W = 0.4;  // LayerW: needs 40% recovery
input double Inp_RRM_ORG_RecoveryRatio_M = 0.3;  // LayerM: needs 30% recovery
input double Inp_RRM_ORG_RecoveryRatio_S = 0.2;  // LayerS: needs only 20% recovery
```

**Why this helps**: Currently `CheckLayerPairAlign()` uses a strict `ema_fast > ema_fast_prev` test. For L3, where EMA3 is a slow-moving average, requiring positive slope on the *evaluation bar* is too late — by the time EMA3 visibly turns, the entry opportunity has often passed. The pullback state machine (already coded at line 1223) tracks NONE→DETECTED→RECOVERED transitions and would catch the *transition moment* rather than waiting for full slope confirmation.

---

### Proposal 3: PSAR-Flip-Anchored Entry (The "Momentum Ignition" Gate)

**Concept**: The core insight from the 100 trades is that the best setups happen when **three things coincide on the same bar or within 1-2 bars**:
1. Price closes beyond the layer's fast EMA (BC passes)
2. PSAR dot flips to the bias direction
3. DPI histogram starts growing (or at least isn't shrinking)

Currently these are checked independently. Proposal: add a **composite quality score** that passes only when at least 2 of 3 conditions fire on the same bar (or within a tight window).

**Implementation sketch** (new function in `SEA_SignalEngine.mqh`):

```mql5
bool CheckMomentumIgnition(int v_shift, int bias, int active_layer)
{
    // 1. PSAR flip recency (bars since last flip in bias direction)
    int psar_age = GetBarsSinceLastFlip(bias, v_shift);
    bool psar_fresh = (psar_age >= 0 && psar_age <= 2);

    // 2. Bar close confirmation (already have this)
    bool bc_pass = (Eval_BarClose(v_shift, bias, active_layer) == 1);

    // 3. DPI histogram growing (not decelerating)
    double hist_cur = 0, hist_prev = 0;
    bool dpi_green = false, dpi_agree = false;
    bool dpi_growing = false;
    if(ComputeDPIMainHist(v_shift, hist_cur, hist_prev, dpi_green, dpi_agree))
    {
        bool aligned = (bias > 0) ? (hist_cur > 0) : (hist_cur < 0);
        dpi_growing = aligned && (MathAbs(hist_cur) >= MathAbs(hist_prev));
    }

    // Require at least 2 of 3
    int score = (psar_fresh ? 1 : 0) + (bc_pass ? 1 : 0) + (dpi_growing ? 1 : 0);
    return (score >= 2);
}
```

**Integration**: Call this as a post-Layer, pre-Indicator quality gate. This avoids entries where only one momentum signal fires (e.g., bar close passes but PSAR hasn't flipped and DPI is decelerating).

**Why this helps**: It formalizes the "pullback recovery with momentum ignition" pattern visible in the best trades. The 2-of-3 threshold is forgiving enough to not over-filter but strict enough to reject setups where only the price level is right but momentum hasn't confirmed.

---

### Proposal 4: Soften DPI Deceleration Filter with Lookback Grace

**Concept**: The current DPI decel filter (line 5787) triggers on a single bar of histogram shrinkage. Replace with a **N-bar lookback** that requires deceleration over multiple bars.

**Implementation** (modify the pre-filter block):

```mql5
// Replace single-bar check with multi-bar trend
if(m_settings.DpiDecelFilterEnabled && m_settings.Ind_Dpi_Enabled)
{
    int decel_count = 0;
    int decel_lookback = 3;  // new setting: DPI_DecelConfirmBars
    
    for(int i = 0; i < decel_lookback; i++)
    {
        double h_cur = 0, h_prev = 0;
        bool g = false, a = false;
        if(ComputeDPIMainHist(v_shift + i, h_cur, h_prev, g, a))
        {
            bool aligned_cur  = (B > 0) ? (h_cur > 0)  : (h_cur < 0);
            bool aligned_prev = (B > 0) ? (h_prev > 0) : (h_prev < 0);
            if(aligned_cur && aligned_prev && MathAbs(h_cur) < MathAbs(h_prev))
                decel_count++;
        }
    }
    
    // Only block if deceleration is sustained (2+ out of 3 bars)
    if(decel_count >= 2)
    {
        // ... reject as DPI_DECEL
    }
}
```

**New setting in PRESET_RRM_ORG:**
```mql5
cfg.DPI_DecelConfirmBars = 2;  // Require 2 bars of shrinking before blocking
```

**Why this helps**: Momentum oscillates naturally during recovery. A single bar of histogram contraction is noise. Requiring 2+ bars of sustained deceleration catches genuine exhaustion while allowing the normal "two steps forward, one step back" rhythm of trend resumption.

---

### Proposal 5: Layer-Adaptive Slope Tolerance

**Concept**: Enable `Layer_SlopeTolerance` but make it layer-dependent. Deeper layers get more tolerance because their EMAs move slowly.

**Implementation** (modify `CheckLayerPairAlign`):

```mql5
// Replace the single Layer_SlopeTolerance with per-layer values
double GetLayerSlopeTolerance(int layer_type)
{
    double pip = GlobalPipSize(m_symbol);
    switch(layer_type)
    {
        case 1: return m_settings.SlopeTol_W * pip;  // e.g., 0.0 (strict for W)
        case 2: return m_settings.SlopeTol_M * pip;  // e.g., 0.3 pips tolerance
        case 3: return m_settings.SlopeTol_S * pip;  // e.g., 0.5 pips tolerance
    }
    return 0.0;
}
```

**New settings:**
```mql5
input double Inp_RRM_ORG_SlopeTol_W = 0.0;  // Weak: strict (fast EMA turns quickly)
input double Inp_RRM_ORG_SlopeTol_M = 0.3;  // Medium: 0.3 pip tolerance
input double Inp_RRM_ORG_SlopeTol_S = 0.5;  // Strong: 0.5 pip tolerance
```

**Why this helps**: EMA34 (fast EMA of LayerS) moves very slowly. Requiring `ema34_now > ema34_prev` by any amount means a barely-flat EMA34 rejects the entire L3 setup. A 0.5-pip tolerance allows "hasn't yet turned but hasn't moved against" — which is exactly the moment the RRM methodology says to enter L3 trades.

---

### Proposal 6: TE-Level PSAR Reconfirmation

**Concept**: Between TS=1 (bar close, shift=1) and TE=1 (bar open, shift=0), market conditions can change. Add an optional TE-level check that PSAR dot is still on the correct side at execution time.

**Implementation** (in `SEA_TradeExecutor.mqh`, `EvaluateTE()`):

```mql5
// NEW: Optional PSAR reconfirmation at TE
if(m_settings.TE_RecheckPsar)
{
    double psar_now = iCustom(..., 0);  // shift=0, current forming bar
    double price_now = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    bool psar_ok = (bias > 0) ? (price_now > psar_now) : (price_now < psar_now);
    if(!psar_ok)
    {
        // PSAR has flipped against us since TS was armed
        return 0;  // TE=0, abort entry
    }
}
```

**New setting:**
```mql5
cfg.TE_RecheckPsar = true;  // Default ON for RRM_ORG
```

**Why this helps**: Prevents entering trades where the PSAR flipped back between bar close and next bar open — common during volatile sessions or news events. This is a cheap safety gate that protects TE quality without adding latency.

---

## 5. Implementation Priority Matrix

| # | Proposal | Impact on TS=1 Quality | Complexity | Risk of Over-Fitting |
|---|---|---|---|---|
| 1 | Layer-specific PSAR flip window | **High** — captures L3 setups currently missed | Medium | Low (structural) |
| 2 | Pullback state machine activation | **High** — replaces binary slope with state transitions | Low (code exists) | Low |
| 4 | DPI decel multi-bar confirmation | **Medium** — reduces false DPI_DECEL rejections | Low | Very low |
| 5 | Layer-adaptive slope tolerance | **Medium** — unblocks flat-EMA L3 setups | Low | Low |
| 3 | Momentum Ignition composite gate | **High** — formalizes the "best setup" pattern | Medium | Medium |
| 6 | TE PSAR reconfirmation | **Medium** — improves TE=1 quality directly | Low | Very low |

**Recommended implementation order**: 2 → 4 → 5 → 1 → 6 → 3

Start with Proposal 2 (activating existing pullback state machine) because the code already exists and just needs to be wired into PRESET_RRM_ORG. Then soften the DPI filter (4) and slope tolerance (5) as low-risk improvements. Layer-specific PSAR windows (1) and TE reconfirmation (6) come next. The Momentum Ignition composite (3) is the most ambitious and should be validated last.

---

## 6. Summary of Key Insight

The fundamental tension in the current PRESET_RRM_ORG is: **it evaluates pullback recovery through instantaneous slope direction, but the RRM methodology is fundamentally about state transitions** (trending → pullback → recovery → entry). The `LayerPullbackEnabled` state machine infrastructure already exists in the codebase but is disconnected from PRESET_RRM_ORG. Activating it — along with layer-scaled parameters and synchronized PSAR flip windows — would align the code with the methodology's intent: enter when the market has demonstrably pulled back *and* recovered, rather than when EMAs happen to point the right way on a single bar.

The PSAR dot flip is the "ignition signal" — it confirms that the pullback is over and momentum is returning. Making the PSAR flip window layer-aware acknowledges that deeper pullbacks take longer to resolve, and the flip may precede the EMA slope turn by 1-3 bars on L3 setups.
