# DPI v14 - Complete Rebuild from TEST-02 Foundation

## Package Contents

### Indicator Files (MT5)
1. **DPI_Indicator_v14_IndependentHistograms.mq5** (v14a)
   - Sign-based color assignment hypothesis
   - TEST FIRST - simpler logic
   
2. **DPI_Indicator_v14b_ThresholdBased.mq5** (v14b)
   - Threshold-based color assignment hypothesis  
   - Has tunable parameters for fine-tuning
   - Test if v14a doesn't match

### Documentation Files
3. **DPI_v14_Analysis.md**
   - Why v11-v13 failed
   - v14 approach explanation
   - Alternative hypotheses if needed

4. **DPI_v14_Testing_Checklist.md**
   - Detailed visual testing procedure
   - Specific points to verify
   - Debugging guide

5. **DPI_v14_Test_Guide.md**
   - Quick reference for testing both versions
   - Decision tree workflow
   - Threshold tuning guide for v14b

---

## What Changed from v11-v13

### The Fatal Flaw in v11-v13
All three versions tried to compute green as **arithmetic residual**:
- v11: Green = full blue base layer
- v12: Green = separate zero-based component  
- v13: Green = residual segment (DRAW_HISTOGRAM2)

**Result:** Thick green bands that dominated the visual appearance ❌

### The v14 Insight
MT4 DPI likely uses **independent state-based conditions** for each color:
- Not layered arithmetic
- Not residual decomposition
- Each color has its own **trigger condition**

**Result:** Thin green bars that appear as gap-fillers, not base layers ✓

---

## Quick Start

### 1. Compile & Test v14a
```
File: DPI_Indicator_v14_IndependentHistograms.mq5
Settings: 
  - InpFastEMA = 8
  - InpSlowEMA = 13 (or 21)
  - InpSelectedRedForHistogram = 3 (for 13) or 4 (for 21)
  - All other parameters from TEST-02
```

**Expected if correct:**
- Blue line matches MACD ✓ (already confirmed)
- Red bars at peaks ✓
- Yellow bars during divergence ✓
- **Green bars THIN, sparse, gap-fillers** ✓

### 2. If v14a Green Still Thick → Test v14b
```
File: DPI_Indicator_v14b_ThresholdBased.mq5
Settings:
  - Same as v14a PLUS
  - InpRedThreshold = 0.5 (start here)
  - InpGreenThreshold = 0.2 (start here)
```

**Tuning guide:**
- Green too thick → increase GreenThreshold (0.2 → 0.3)
- Red missing → decrease RedThreshold (0.5 → 0.4)
- Too much yellow → increase RedThreshold (0.5 → 0.6)

---

## Testing Procedure

### Step 1: Visual Overlay Test
1. Take screenshot of MT4 DPI
2. Take screenshot of v14a (same timeframe)
3. Overlay at 50% opacity
4. Check alignment:
   - Blue line: Should be pixel-perfect
   - Red histogram: Should match positions
   - **Green histogram: Should be THIN, not thick bands**

### Step 2: Color Transition Test
Pick 5 consecutive bars in MT4 DPI:
- Note their colors (e.g., Red→Red→Yellow→Green→Red)
- Find same bars in v14
- Verify color sequence matches

### Step 3: Green Thickness Test (CRITICAL)
- MT4 DPI green bars should be **thin accent bars**
- v14 green bars should match this thinness
- If v14 green forms **thick bands** → test v14b instead

---

## Success Criteria

✅ **Blue line:** Pixel-perfect match (already working from TEST-02)
✅ **Red histogram:** Appears at correct peaks with correct magnitude  
✅ **Yellow histogram:** Appears during transitions/divergence
✅ **Green histogram:** **THIN bars that fill gaps, not thick base layer**

---

## If Both v14a and v14b Fail

Report back with:
1. Screenshots (MT4 DPI, v14a, v14b)
2. Specific visual issue description
3. Color sequence for 5 consecutive bars

Next hypotheses to try:
- Derivative-based (color based on slope/acceleration)
- Zone-based (color based on absolute level)  
- Multi-condition state machine
- Hybrid approach

---

## Preserved from TEST-02 ✓

All critical elements maintained:
- [x] InpFastEMA, InpSlowEMA for MACD core
- [x] InpRedA/B/C/D_EMA for Fibonacci candidates
- [x] InpDoubleFirst, InpDoubleSecond for smoothing
- [x] InpSelectedRedForHistogram for selector logic
- [x] Blue line calculation (Fast - Slow EMA)
- [x] Double smoothing of selected red
- [x] Fibonacci selector mapping (slow 13→3, slow 21→4)

**Changed:** Only the histogram color assignment logic (from residual arithmetic to state conditions)

---

## Core Principle

> "The colors are not arithmetic layers — they are state indicators."

v14 stops trying to decompose blue into mathematical components and instead assigns colors based on **what state the oscillator is in** at each bar.

---

## Files Ready for Testing

All files are in `/home/claude/`:
- DPI_Indicator_v14_IndependentHistograms.mq5 ← Start here
- DPI_Indicator_v14b_ThresholdBased.mq5 ← If v14a fails
- DPI_v14_Analysis.md ← Why we rebuilt
- DPI_v14_Testing_Checklist.md ← Detailed test procedure  
- DPI_v14_Test_Guide.md ← Quick reference

**Next step:** Compile v14a and compare to MT4 DPI screenshot.
