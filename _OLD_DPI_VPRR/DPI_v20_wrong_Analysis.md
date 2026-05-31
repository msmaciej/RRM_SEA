# DPI v14 - Analysis & Approach

## What Went Wrong in v11-v13

### v11 Error
- Drew green as **full blue base layer** from zero
- Result: Thick green bars underlying everything
- Visual: Wrong - green was too dominant

### v12 Error  
- Drew green from zero as independent component
- Still didn't match MT4 DPI visual appearance
- Green appeared as separate bars, not integrated

### v13 Error
- Used DRAW_HISTOGRAM2 to draw green as "residual segment"
- Drew green from red_top to blue_top
- Result: Broad residual bands
- Visual: Still wrong - green appeared as thick caps

### Common Mistake
All three tried to make green a **computed residual** or **base layer**.
They assumed: Green = Blue - Red (arithmetically)

## v14 Approach - Independent Conditions

### Key Insight
MT4 DPI likely assigns histogram colors based on **independent conditions**:
- Not residual arithmetic
- Not layered base components
- Each color has its own **state-based trigger**

### Color Logic (v14 Hypothesis)

```
For each bar:

1. Calculate blue (MACD core) = Fast EMA - Slow EMA
2. Calculate smoothed red = DoubleSmooth(Selected Red EMA)

3. RED histogram:
   - Drawn when: smoothedRed and blue are SAME SIGN (both + or both -)
   - Value: smoothedRed
   - Meaning: Dominant aligned oscillator component

4. YELLOW histogram:
   - Drawn when: smoothedRed and blue are OPPOSITE SIGN
   - Value: smoothedRed  
   - Meaning: Divergence component

5. GREEN histogram:
   - Drawn when: Gap exists between blue and red/yellow
   - Two modes:
     a) If no red/yellow: green = blue - smoothedRed (residual)
     b) If red/yellow exists: green fills gap to complete blue total
   - Meaning: Completion/gap-fill component
```

### Visual Result Expected

```
MT4 DPI appearance:
- Red bars appear as primary histogram peaks (aligned state)
- Yellow bars appear during divergence
- Green bars appear as thin gap-fillers, not thick bands
- Blue line floats as reference overlay
```

## Preserved from TEST-02

✓ All input parameters (InpFastEMA, InpSlowEMA, RedA/B/C/D, etc.)
✓ Blue line = MACD core (Fast - Slow)
✓ Fibonacci selector logic (slow 13→selector 3, slow 21→selector 4)
✓ Double smoothing of selected red (5-pass then 3-pass)

## Key Differences from v11-v13

| Aspect | v11-v13 | v14 |
|--------|---------|-----|
| Green calculation | Residual arithmetic | Independent condition |
| Color assignment | Layered/stacked | State-based selection |
| Green draw type | HISTOGRAM2 / full base | HISTOGRAM (conditional) |
| Green appearance | Thick bands | Thin gap-fillers |
| Logic model | Arithmetic decomposition | State machine |

## Next Testing Steps

1. Compile v14 in MT5
2. Compare visual output with MT4 DPI screenshot
3. Check specific features:
   - Are red bars appearing at correct peaks?
   - Do yellow bars appear during divergence?
   - Is green appearing as thin gaps, not thick bands?
4. If still wrong, adjust the **condition logic**, not the arithmetic

## Alternative Hypotheses (if v14 still wrong)

### Hypothesis A: Threshold-based
```
if abs(smoothedRed) > threshold:
    draw RED histogram
elif abs(residual) > smaller_threshold:
    draw GREEN histogram  
else:
    draw YELLOW histogram
```

### Hypothesis B: Derivative-based
```
if derivative(smoothedRed) > 0 and smoothedRed > 0:
    draw RED
elif derivative(blue) > 0 and blue > 0:
    draw GREEN
else:
    draw YELLOW
```

### Hypothesis C: Zone-based
```
if blue in upper_zone:
    draw RED
elif blue in middle_zone:
    draw YELLOW
elif blue in lower_zone:
    draw GREEN
```

## Debugging Approach

If v14 visual still doesn't match:
1. **Don't patch arithmetic** - the math is likely correct
2. **Change the conditions** for color assignment
3. **Study MT4 screenshots** for exact bar color transitions
4. **Test edge cases** where colors switch

---

**Bottom line:** v14 abandons residual arithmetic model and uses independent state conditions for each color. This should produce thinner green bars that fill gaps rather than broad bands.
