# DPI Signal Reference — Corrected Section

> **Replace the DPI section in `README_SEA_SIGNAL_REFERENCE.md` (lines ~149-228) with this corrected version.**

### DPI (Dynamic Price Index) — Momentum Direction Voter

**Purpose:** Primary momentum direction confirmation using MACD-based histogram with CCI trend filter and GREEN momentum alignment.

**Architecture:**
- **Blue Line (LEAD):** Fast MACD core = `EMA(Fast) - EMA(Slow)` of close price
- **Red Line (FOLLOW):** Smoothed signal = EMA of Blue (configurable: EMA5/8/13/21 or Double)
- **Histogram (Ribbon):** `Blue - Red` — divergence between lead and signal
- **GREEN Overlay:** `min(|Blue|, |hist|)` when Blue and hist are on same side of zero

**Vote Logic (three conditions, all must pass):**

```mql5
// Check_DPI() in SEA_SignalEngine.mqh
bool dir_ok  = (hist_sign == bias);              // Histogram direction matches trade direction
bool cci_ok  = (IgnoreCCI || !UseCCI || CCI_agrees);  // CCI trend filter (optional)
bool green_ok = (!UseGreen || green_present);     // GREEN alignment (optional)

return dir_ok && cci_ok && green_ok;
```

- **dir_ok:** Histogram sign must match bias. `hist > 0` for LONG, `hist < 0` for SHORT.
- **cci_ok:** When `DPI_UseCCIReset = true`, histogram and CCI must agree in sign. Disagreement = CCI "reset" warning → vote fails. Bypassed with `DPI_IgnoreCCIForVote = true`.
- **green_ok:** When `DPI_UseGreenHist = true`, GREEN must be present (Blue and hist aligned on same side of zero). GREEN exists both above zero (bullish) and below zero (bearish).

**GREEN Histogram — Momentum Lifecycle:**

GREEN tracks momentum alignment, not direction. It appears on both sides of zero:
- **Above zero:** Bullish momentum confirmed (Blue positive AND hist positive)
- **Below zero:** Bearish momentum confirmed (Blue negative AND hist negative)

GREEN lifecycle within a move:
1. **Appears** → Momentum impulse starting; direction confirmed
2. **Grows** → Momentum accelerating; strongest phase for entries
3. **Declines** → Momentum decelerating; weakening, avoid new entries
4. **Vanishes** → OB/OS condition; pullback likely, close to protect profits

**DPI Deceleration Filter (entry blocking):**
When `DpiDecelFilterEnabled = true`, blocks entries where `GREEN[shift] < GREEN[shift+1]` (momentum fading). Prevents late entries after the momentum peak.

**DPI Exit (GREEN disappearance):**
When `DPI_ExitOnHistDisappear = true` (with `DPI_HistTrackingEnabled = true`), open positions are closed when GREEN vanishes — direction-neutral, works for both BUY and SELL. Rationale: GREEN vanishing = OB/OS → pullback coming → lock in gains.

**EA Settings (PRESET_RRM_ORG):**
- `Ind_Dpi_Enabled` — Enable/disable DPI voter (default: true in RRM_ORG)
- `DPI_MACD_Fast` — Fast EMA period (default: 8)
- `DPI_MACD_Slow` — Slow EMA period (default: 13)
- `DPI_RedSignalType` — Red signal line calculation (1-5):
  1. EMA5 of Blue
  2. EMA8 of Blue
  3. EMA13 of Blue (default)
  4. EMA21 of Blue
  5. Double smoothed EMA
- `DPI_UseCCIReset` — Enable CCI trend filter (default: true)
- `DPI_CCI_Period` — CCI calculation period (default: 13)
- `DPI_UseGreenHist` — Require GREEN alignment in vote (default: true)
- `DPI_IgnoreCCIForVote` — Bypass CCI in vote, use raw hist direction only (default: false)
- `DpiDecelFilterEnabled` — Block entries when GREEN shrinking (default: depends on preset)
- `DPI_HistTrackingEnabled` — Master switch for CCI histogram tracking system (default: false)
- `DPI_ExitOnHistDisappear` — Close positions when GREEN vanishes (default: false)

**Example (LONG setup):**
```
Bias = LONG (+1)
Blue = 0.0005 (positive → bullish lead)
hist = 0.0003 (positive → Blue above Red, momentum expanding)
CCI  = +50    (positive → trend agrees)
GREEN = min(0.0005, 0.0003) = 0.0003 (present above zero)

dir_ok   = PASS (hist > 0 matches LONG)
cci_ok   = PASS (hist > 0 AND CCI > 0, no reset)
green_ok = PASS (Blue > 0 AND hist > 0, GREEN present)
→ DPI vote = PASS
```

**Example (SHORT setup):**
```
Bias = SHORT (−1)
Blue = −0.0004 (negative → bearish lead)
hist = −0.0002 (negative → Blue below Red, momentum expanding bearish)
CCI  = −80     (negative → trend agrees)
GREEN = min(0.0004, 0.0002) = 0.0002 (present below zero)

dir_ok   = PASS (hist < 0 matches SHORT)
cci_ok   = PASS (hist < 0 AND CCI < 0, no reset)
green_ok = PASS (Blue < 0 AND hist < 0, GREEN present)
→ DPI vote = PASS
```

**Standalone Indicator Files:**
- `DPI_mc_main.mq5` — Full version with GREEN momentum overlay (toggleable)
- `DPI_mc_simple.mq5` — Simplified version without GREEN overlay
- `DPI_tm_simple.mq5` — TSI+MACD math variant (William Blau Ergodic)

See also:
- [`README_SEA_DPI_mc_main.md`](README_SEA_DPI_mc_main.md) — Full DPI documentation with color model, GREEN lifecycle, and EA integration
- [`PRESET_RRM_ORG` preset flow](README_SEA_PRESETS.md#preset_rrm_org)
