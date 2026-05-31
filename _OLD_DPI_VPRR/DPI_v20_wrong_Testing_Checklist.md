# DPI v14 - Visual Testing Checklist

## Setup
1. Open MT5
2. Compile `DPI_Indicator_v14_IndependentHistograms.mq5`
3. Apply to same chart as MT4 DPI
4. Use same settings:
   - For slow=13: InpSelectedRedForHistogram = 3
   - For slow=21: InpSelectedRedForHistogram = 4

## Visual Comparison Points

### 1. Blue Line Alignment ✓ (Already confirmed working)
- [ ] Blue line exactly matches MACD core
- [ ] No offset or lag
- [ ] Crosses zero at same points

### 2. Red Histogram Characteristics
Look for red bars in MT4 DPI, then check v14:
- [ ] Red appears at major peaks/troughs
- [ ] Red magnitude matches MT4 visual height
- [ ] Red appears when oscillator is "strong" (not weak/transitional)

### 3. Yellow Histogram Characteristics  
- [ ] Yellow appears during transitions
- [ ] Yellow appears when blue and histogram diverge
- [ ] Yellow is NOT the dominant color (should be less frequent than red)

### 4. Green Histogram - CRITICAL TEST
This is where v11-v13 failed. Check:
- [ ] Green bars are THIN (not thick bands)
- [ ] Green appears as "gap fillers" between red/yellow and blue line
- [ ] Green does NOT form a continuous base layer
- [ ] Green does NOT appear as wide residual caps on top of red
- [ ] Green bars are sparse, not in every position

### 5. Overall Visual Gestalt
Step back and compare the "feel":
- [ ] MT4 DPI has a specific color pattern/rhythm - does v14 match?
- [ ] Are the dominant colors in same proportion (red > yellow > green)?
- [ ] Does the histogram "contour" follow the blue line naturally?

## Common Visual Bugs to Watch For

❌ **Green too thick** → Color condition logic wrong
❌ **Green everywhere** → Should only appear in gaps, not continuous
❌ **Red missing** → Threshold or condition too strict  
❌ **Yellow dominant** → Condition inverted
❌ **Colors stacked weirdly** → Draw order issue
❌ **Gaps in histogram** → EMPTY_VALUE logic incorrect

## Specific Test Scenarios

### Scenario A: Strong Uptrend
MT4 DPI should show:
- Mostly RED bars above zero
- Blue line rising
- Minimal green (red fills most of blue)

v14 should match.

### Scenario B: Divergence Phase
MT4 DPI should show:
- YELLOW bars appearing
- Blue and histogram separating
- Some green filling gaps

v14 should match.

### Scenario C: Weak Oscillation Near Zero
MT4 DPI should show:
- Mix of colors
- Small bars
- Green may appear more

v14 should match.

## Measurement Method

1. Take screenshot of MT4 DPI
2. Take screenshot of v14 same timeframe
3. Overlay screenshots (50% opacity)
4. Check pixel-level alignment of:
   - Blue line (should be identical)
   - Red bar positions (should match)
   - Green bar thickness (critical - should be thin)

## Quick Visual Test

Pick 3 distinctive bars in MT4 DPI:
- One large red bar
- One yellow bar  
- One with visible green gap

Find same bars in v14 and compare color assignment.

## If v14 Still Wrong

Note which specific aspect is wrong:
- [ ] Red position wrong
- [ ] Yellow condition wrong
- [ ] Green still too thick
- [ ] Colors inverted
- [ ] Missing bars
- [ ] Extra bars

This will guide the next hypothesis adjustment.

---

**Success Criteria:**
When you overlay MT4 DPI and v14 screenshots at 50% opacity, the histogram colors should align so well that you can't tell which is which (except for blue line anti-aliasing differences).
