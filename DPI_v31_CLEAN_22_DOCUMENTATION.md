# DPI v31 - Complete Documentation

## Overview
DPI (Divergence Price Indicator) v31 is a complete MT4→MT5 conversion with all features working:
- ✅ Continuous histogram ribbon (no gaps between red-contour and Blue line)
- ✅ CCI color resets (histogram changes color based on CCI trend filter)
- ✅ GREEN momentum overlay (visible when Blue and histogram aligned)
- ✅ Customizable colors via input parameters

## Components

### Lines
1. **Blue Line (LEAD)** - Fast MACD core = EMA(8) - EMA(13)
2. **Red Signal Line (FOLLOW)** - Smoothed signal line (configurable: EMA5/8/13/21 or Double)
3. **Red Contour Line** - Histogram value tracker = Blue - Red

### Histograms
4. **Base Layer (Red/Yellow)** - Fills from red-contour to Blue line (or both sides when opposite)
   - **Yellow** = Bullish (hist > 0, or CCI override)
   - **Red** = Bearish (hist < 0, or CCI override)
5. **GREEN Overlay** - Shows when Blue and histogram are aligned on same side of zero
   - Fills from 0 to the closer line (never extends beyond Blue)

## Input Parameters

### MACD Settings
- **Fast EMA period** (default: 8) - Fast moving average
- **Slow EMA period** (default: 13) - Slow moving average

### Red Signal Line Settings
- **Red line type** (default: 3 = EMA13)
  - 1 = EMA5
  - 2 = EMA8  
  - 3 = EMA13
  - 4 = EMA21
  - 5 = Double smoothed
- **Red EMA periods A/B/C/D** - Individual EMA periods for each type
- **Double smooth: First/Second EMA** - For double smoothing option

### CCI Reset Logic
- **Enable CCI reset logic** (default: true) - Enables trend filter
- **CCI period** (default: 13) - CCI calculation period
- **CCI price calculation** (default: Typical Price HLC/3)
  - Typical Price (HLC/3)
  - Close, Open, High, Low
  - Median (HL/2)
  - Weighted (HLCC/4)

### GREEN Histogram
- **Enable GREEN momentum histogram** (default: true)

### Color Customization
- **Bullish histogram color** (default: Yellow) - Color when histogram is bullish
- **Bearish histogram color** (default: Red) - Color when histogram is bearish
- **GREEN overlay color** (default: Lime) - Color for momentum alignment

## How It Works

### Histogram Color Logic
The histogram represents divergence/convergence between price momentum (Blue) and its signal (Red).

**Without CCI:**
- hist > 0 → Yellow (bullish)
- hist < 0 → Red (bearish)

**With CCI enabled:**
CCI acts as a trend filter that can "reset" colors:
- hist > 0 AND CCI > 0 → Yellow (strong bullish)
- hist > 0 AND CCI < 0 → **Red** (bullish weakening - CCI reset!)
- hist < 0 AND CCI > 0 → **Yellow** (bearish weakening - CCI reset!)
- hist < 0 AND CCI < 0 → Red (strong bearish)

### GREEN Overlay Logic
GREEN appears when Blue line and histogram are **aligned** (both positive OR both negative):

**When aligned:**
- Base layer fills to furthest extent: 0 → max(Blue, hist)
- GREEN fills to closer extent: 0 → min(Blue, hist)
- GREEN is always visible because it overlays on the base

**When opposite sides:**
- No GREEN (only base layer fills both sides)

### Technical Implementation (MT5 Specific)

**Four Histogram Buffers:**
The indicator uses FOUR separate histogram buffers instead of two:
- `g_HistYellowPos[]` - Yellow bars on positive side
- `g_HistYellowNeg[]` - Yellow bars on negative side
- `g_HistRedPos[]` - Red bars on positive side
- `g_HistRedNeg[]` - Red bars on negative side

This solves MT5's limitation where you need independent color control on each side when Blue and histogram are on opposite sides of zero.

**Example:**
```
Blue = 0.5 (positive)
hist = -0.3 (negative)
CCI = 100 (bullish)

Result:
- hist < 0 AND CCI > 0 → Yellow override
- YellowPos = 0.5 (fills positive side)
- YellowNeg = -0.3 (fills negative side)
- Both sides show YELLOW (CCI override working)
```

## Trading Interpretation

### Signal Strength
1. **Strong Bullish** - Yellow histogram, no CCI reset
2. **Weak Bullish** - Yellow histogram WITH red sections (CCI reset warnings)
3. **Strong Bearish** - Red histogram, no CCI reset
4. **Weak Bearish** - Red histogram WITH yellow sections (CCI reset warnings)

### GREEN Momentum
- **GREEN visible** = Blue and histogram aligned = Momentum confirmation
- **GREEN absent** = Lines on opposite sides = Momentum divergence

### EA Integration Example
```mql5
// Get indicator values
double blue = iCustom(..., 0, bar);      // Blue line
double hist = iCustom(..., 2, bar);      // Red contour (histogram)
double cci_val = iCustom(..., calc_buffer, bar);  // CCI if needed

// Determine color
bool is_yellow = (hist >= 0 && cci_val >= 0) || (hist < 0 && cci_val >= 0);
bool is_green = (blue > 0 && hist > 0) || (blue < 0 && hist < 0);

// Trading logic
if(is_yellow && !is_green) {
   // Bullish but no momentum confirmation - weak signal
}
if(is_yellow && is_green) {
   // Bullish with momentum confirmation - strong signal
}
```

## Color Settings - Two Methods

### Method 1: Input Parameters (Recommended)
1. Right-click indicator → Properties
2. Go to "Inputs" tab
3. Change:
   - Bullish histogram color
   - Bearish histogram color
   - GREEN overlay color
4. Click OK
5. Colors persist when you reload the indicator

### Method 2: Colors Tab (Quick Override)
1. Right-click indicator → Properties
2. Go to "Colors" tab
3. Change individual plot colors:
   - Hist_Red_Pos / Hist_Red_Neg
   - Hist_Yellow_Pos / Hist_Yellow_Neg
   - Hist_Green
4. Click OK
5. **Note:** These changes are temporary (instance-specific)

**Which to use?**
- **Inputs tab** = Permanent color scheme
- **Colors tab** = Quick test or one-time adjustment

## Troubleshooting

### GREEN Not Visible
**Symptoms:** GREEN is declared but doesn't show in Colors tab
**Cause:** `#property indicator_plots` count is wrong
**Fix:** Must be set to 8 (for plots 0-7)

### Gaps in Histogram
**Symptoms:** Ribbon doesn't fill continuously between lines
**Cause:** Using only 2 histogram buffers instead of 4
**Fix:** Already implemented - 4 buffers allow independent color per side

### CCI Resets Not Working
**Symptoms:** Histogram always matches its sign (no color overrides)
**Cause:** Color logic applies to wrong sides when opposite
**Fix:** Already implemented - same color (based on hist) applies to both sides

## Version History

- **v29** - CCI resets working, gaps present, no GREEN
- **v30_14** - Continuous ribbon, GREEN correct, no CCI resets
- **v30_16** - Attempted fix, still had issues
- **v31_18** - Four buffers, CCI logic bug
- **v31_20** - CCI logic fixed, GREEN not plotting (plots=7 bug)
- **v31_25** - **FINAL WORKING** - All features operational

## Files Structure

```
DPI_v31_CLEAN_22_FINAL_WORKING.mq5
├── Plot 0: Blue_MACD_Core (Blue line)
├── Plot 1: Red_Signal (Red signal line)
├── Plot 2: Red_Contour (Histogram value line)
├── Plot 3: Hist_Red_Pos (Red histogram positive)
├── Plot 4: Hist_Red_Neg (Red histogram negative)
├── Plot 5: Hist_Yellow_Pos (Yellow histogram positive)
├── Plot 6: Hist_Yellow_Neg (Yellow histogram negative)
└── Plot 7: Hist_Green (GREEN overlay)
```

## Credits

MT4 → MT5 conversion solving the fundamental rendering difference:
- MT4: Can apply multiple colors to single histogram natively
- MT5: Requires separate buffer per color per side
- Solution: Four histogram buffers + GREEN overlay = Perfect replication
