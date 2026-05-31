# DPI v14a vs v14b - Quick Test Guide

## Two Versions, Two Hypotheses

### v14a: Sign-Based Color Assignment
**File:** `DPI_Indicator_v14_IndependentHistograms.mq5`

**Logic:**
- RED: When smoothedRed and blue have SAME SIGN (both positive or both negative)
- YELLOW: When smoothedRed and blue have OPPOSITE SIGN  
- GREEN: Fills gap between histogram and blue line

**Best for:** If MT4 DPI colors switch based on phase alignment

**Settings:** Standard TEST-02 parameters only

---

### v14b: Threshold-Based Color Assignment
**File:** `DPI_Indicator_v14b_ThresholdBased.mq5`

**Logic:**
- RED: When smoothedRed magnitude ≥ threshold% of blue (default 50%)
- YELLOW: When smoothedRed is weak compared to blue
- GREEN: Small residual gaps only

**Best for:** If MT4 DPI colors switch based on dominance/strength

**Settings:** 
- Standard TEST-02 parameters PLUS
- `InpRedThreshold = 0.5` (adjust 0.3-0.8 to tune red sensitivity)
- `InpGreenThreshold = 0.2` (adjust 0.1-0.4 to tune green visibility)

---

## Testing Workflow

### Step 1: Test v14a First
```
1. Compile DPI_Indicator_v14_IndependentHistograms.mq5
2. Apply with InpSelectedRedForHistogram = 3 (for slow 13)
3. Compare to MT4 DPI screenshot
```

**If v14a looks correct:**
✓ Done! Sign-based logic was correct.

**If v14a green still too thick:**
→ Proceed to Step 2

### Step 2: Test v14b
```
1. Compile DPI_Indicator_v14b_ThresholdBased.mq5
2. Start with default thresholds (0.5 / 0.2)
3. Compare to MT4 DPI screenshot
```

**If v14b green thinner but still not perfect:**
Adjust thresholds:
- Green too thick → Increase `InpGreenThreshold` (0.2 → 0.3)
- Red appearing as yellow → Decrease `InpRedThreshold` (0.5 → 0.4)
- Yellow appearing as red → Increase `InpRedThreshold` (0.5 → 0.6)

---

## Visual Comparison Checklist

For whichever version you test, check these specific points:

### ✓ Blue Line (Both Should Match)
- [ ] Exactly aligns with MACD core
- [ ] Already confirmed working from TEST-02

### ✓ Red Histogram  
- [ ] Appears at major peaks/troughs
- [ ] Magnitude looks correct
- [ ] Color appears when oscillator is strong

### ✓ Yellow Histogram
- [ ] Appears during transitions/divergence  
- [ ] Less frequent than red
- [ ] Makes sense as "weak phase" indicator

### ✓ Green Histogram (CRITICAL)
- [ ] **THIN bars, not thick bands** ← Most important
- [ ] Appears as gap-filler, not base layer
- [ ] Sparse, not everywhere
- [ ] Doesn't dominate visual appearance

---

## Decision Tree

```
Start
  ↓
Test v14a
  ↓
Green still too thick? ────NO──→ ✓ v14a is correct!
  ↓
 YES
  ↓
Test v14b with defaults
  ↓
Green better? ────NO──→ Need new hypothesis
  ↓                      (report back with screenshots)
 YES
  ↓
Tune thresholds until perfect
  ↓
✓ v14b is correct!
```

---

## Reporting Back

If both v14a and v14b fail, provide:

1. **Screenshot comparison:**
   - MT4 DPI (reference)
   - v14a output
   - v14b output (with threshold values used)

2. **Specific visual issue:**
   - "Green still appears as thick bands in v14a"
   - "Red/yellow assignment backwards in v14b"
   - "Colors correct but magnitudes wrong"

3. **Observation of color transitions:**
   - Pick 5 consecutive bars in MT4 DPI
   - Note their colors: e.g., "Red, Red, Yellow, Green, Red"
   - Note what v14a/v14b shows for same bars

This will guide the next hypothesis.

---

## Expected Outcome

One of these should match MT4 DPI:
- v14a if color is phase-alignment based
- v14b if color is magnitude-threshold based

If neither works, we need a hybrid or completely different color logic (e.g., derivative-based, multi-condition state machine).

---

**Key Success Metric:**  
Green histogram should look like **thin accent bars**, not **thick base layer**.
