# PRESET_RRM Strategy Tester Configuration Guide

## Overview
This guide explains how to configure the EA in MetaTrader 5 Strategy Tester to match the manual trading strategy with 60% win rate.

## Key Changes Made
The PRESET_RRM preset has been modified to:
1. **Remove ATR-based exits**: No longer forces hardcoded ATR multipliers for SL/TP/BE
2. **Enable true R:R ratios**: TP is now calculated from actual SL distance (not ATR)
3. **Use input parameters**: All exit settings are now controlled via Strategy Tester inputs

## Recommended Strategy Tester Settings

### Entry & Confirmation Settings
These match your manual strategy and don't need changes from defaults:
- **Vote Threshold**: 4 (EMA + MACD + CCI + PSAR must all agree)
- **ADX Filter**: Enabled (avoid choppy markets)
- **EMA Strategy**: Follows slope direction

### Exit Settings (Critical for Performance)

#### 1. Initial SL Placement
```
Inp_SL_PlacementMode = SL_SWING_HIGHLOW
Inp_SL_SwingPipsCushion = 10.0 (for H1 timeframe)
```
**Why**: Uses last swing high/low (fractal) + fixed pips buffer, matching your manual strategy.

**Alternative Options**:
- `SL_PSAR_PIPS`: PSAR dot + pips cushion (also swing-based)
- `SL_FIXED_PIPS`: Simple fixed pips from entry

**Avoid**: `SL_ATR` and `SL_PSAR_ATR` (these use ATR, not swing-based)

#### 2. Take Profit (R:R Ratio)
```
Inp_TP_Mult = 2.0
```
**Why**: This is your R:R ratio. If SL is 10 pips from entry, TP will be 20 pips (1:2 ratio).

**How it works**:
- **Old behavior**: `TP = ATR × 2.0` (ignored actual SL distance)
- **New behavior**: `TP = SL_distance × 2.0` (true R:R ratio)

**Examples**:
- 1:1 ratio = Set to `1.0`
- 1:2 ratio = Set to `2.0` ✅ (your strategy)
- 1:3 ratio = Set to `3.0`

#### 3. Breakeven
```
Inp_Use_BE = true
Inp_BE_Trig = 1.0
Inp_BE_Buff = 0.1
```
**Why**: Moves SL to breakeven when profit reaches 1:1 R:R (configurable).

**How it works**:
- `BE_Trig = 1.0` means move to BE when profit = 1× SL distance
- `BE_Trig = 0.5` means move to BE when profit = 0.5× SL distance
- `BE_Buff = 0.1` adds a small buffer (0.1× SL distance) above entry to avoid premature exit

#### 4. Trailing Stop
```
Inp_TrailMode = TRAIL_PSAR
Inp_PSAR_TrailCushionMode = PSAR_CUSHION_PIPS
Inp_PSAR_TrailPipsCushion = 5.0
```
**Why**: Uses PSAR with fixed pips cushion (NOT ATR), matching your manual strategy.

**How it works**:
- Trail follows PSAR dot
- Fixed pips cushion (auto-scaled by timeframe and currency)
- No ATR involved in trailing

**Avoid**: Setting `PSAR_TrailCushionMode = PSAR_CUSHION_ATR` (uses ATR instead of fixed pips)

## Complete Example Configuration

### For H1 Timeframe (1:2 R:R, Swing SL, PSAR Trailing)
```
=== PRESET_RRM: TREND PULLBACK ===
InpPreset = PRESET_RRM
Inp_RRM_Mode = RRM_AUTO_BY_TF (or RRM_SWING for H1)

=== EXITS: INITIAL SL PLACEMENT ===
Inp_SL_PlacementMode = SL_SWING_HIGHLOW
Inp_SL_SwingPipsCushion = 10.0

=== EXITS: TP, BREAKEVEN, TRAILING ===
Inp_TP_Mult = 2.0  // 1:2 R:R ratio
Inp_Use_BE = true
Inp_BE_Trig = 1.0  // Move to BE at 1:1 R:R
Inp_BE_Buff = 0.1  // Small buffer above entry

=== EXITS: TRAILING STOP ===
Inp_TrailMode = TRAIL_PSAR
Inp_PSAR_TrailCushionMode = PSAR_CUSHION_PIPS
Inp_PSAR_TrailPipsCushion = 5.0
```

### For M15 Timeframe (1:2 R:R, PSAR SL, PSAR Trailing)
```
=== PRESET_RRM: TREND PULLBACK ===
InpPreset = PRESET_RRM
Inp_RRM_Mode = RRM_AUTO_BY_TF (will auto-select SCALP mode)

=== EXITS: INITIAL SL PLACEMENT ===
Inp_SL_PlacementMode = SL_PSAR_PIPS
Inp_SL_PsarPipsCushion = 5.0

=== EXITS: TP, BREAKEVEN, TRAILING ===
Inp_TP_Mult = 2.0  // 1:2 R:R ratio
Inp_Use_BE = true
Inp_BE_Trig = 1.0  // Move to BE at 1:1 R:R
Inp_BE_Buff = 0.1

=== EXITS: TRAILING STOP ===
Inp_TrailMode = TRAIL_PSAR
Inp_PSAR_TrailCushionMode = PSAR_CUSHION_PIPS
Inp_PSAR_TrailPipsCushion = 5.0
```

## Understanding Auto-Scaling

The EA automatically scales pips cushions based on:

### Timeframe Multipliers
- M1: 0.5× (e.g., 10 pips → 5 pips)
- M5: 0.8× (e.g., 10 pips → 8 pips)
- M15: 1.0× (e.g., 10 pips → 10 pips)
- H1+: 2.0× (e.g., 10 pips → 20 pips)

### Currency Pair Adjustment
- JPY pairs: Points are multiplied by 100.0 (e.g., USDJPY)
- Non-JPY pairs: Points are multiplied by 10.0 (e.g., EURUSD)

**Example**: Setting `Inp_SL_SwingPipsCushion = 10.0` on H1 EURUSD:
- Base cushion: 10 pips
- TF multiplier: 2.0 (H1)
- Currency multiplier: 10.0 (non-JPY)
- Final cushion: 10 × 2.0 = 20 pips from swing point

## Testing Your Configuration

### Step 1: Verify Entry Logic (Should Already Work)
- Check that EA only enters with 4/4 votes
- Verify ADX > 20 filter is active
- Confirm EMA slope direction is correct

### Step 2: Verify SL Placement
- Open a trade in visual mode
- Check that SL is at swing high/low + cushion pips
- **NOT** at a simple ATR distance from entry

### Step 3: Verify TP Calculation
- Measure actual SL distance in pips (e.g., 15 pips)
- With `Inp_TP_Mult = 2.0`, TP should be 30 pips from entry
- **NOT** based on current ATR value

### Step 4: Verify Breakeven
- Wait for price to move 1:1 R:R (profit = SL distance)
- SL should move to entry + small buffer
- Trade should be protected from loss

### Step 5: Verify Trailing
- As trade moves in profit, SL should follow PSAR
- Cushion should be fixed pips (scaled by TF/currency)
- **NOT** based on changing ATR values

## Optimization Tips

### If Win Rate is Still Low:
1. **Tighten SL cushion**: Try 5-8 pips instead of 10
2. **Adjust R:R ratio**: Try 1:1.5 or 1:3 instead of 1:2
3. **Change SL method**: Try `SL_PSAR_PIPS` instead of `SL_SWING_HIGHLOW`

### If Win Rate is Good but Profit is Low:
1. **Increase R:R ratio**: Try 3.0 or 4.0
2. **Disable breakeven**: Set `Inp_Use_BE = false` to let winners run
3. **Widen SL cushion**: Try 15-20 pips to avoid premature stops

### If Getting Stopped Out Too Early:
1. **Widen SL cushion**: Increase `Inp_SL_SwingPipsCushion`
2. **Change to PSAR SL**: `SL_PSAR_PIPS` may give more breathing room
3. **Adjust PSAR trailing cushion**: Increase `Inp_PSAR_TrailPipsCushion`

## What Changed from Old PRESET_RRM

### Before (Hardcoded ATR)
```mql5
Settings.SL_Mult = 1.25;  // ATR multiplier
Settings.TP_Mult = 4.0;   // ATR multiplier
Settings.BE_Trig = 1.5;   // ATR multiplier
Settings.SL_PlacementMode = SL_PSAR_PIPS;  // Forced
Settings.TrailMode = TRAIL_PSAR;  // Forced
```
**Problem**: Ignored Strategy Tester inputs, forced ATR-based calculations

### After (User-Controlled R:R)
```mql5
Settings.SL_Mult = 0.0;   // Disabled
Settings.TP_Mult = Inp_TP_Mult;  // R:R ratio from input
Settings.BE_Trig = Inp_BE_Trig;  // R:R ratio from input
Settings.SL_PlacementMode = Inp_SL_PlacementMode;  // User choice
Settings.TrailMode = Inp_TrailMode;  // User choice
```
**Benefit**: Full control via Strategy Tester, true R:R ratios, no ATR interference

## Summary

✅ **Key Points to Remember**:
1. **SL**: Use `SL_SWING_HIGHLOW` or `SL_PSAR_PIPS` (swing-based, NOT ATR)
2. **TP**: Set `Inp_TP_Mult` as R:R ratio (e.g., 2.0 for 1:2)
3. **BE**: Set `Inp_BE_Trig` as R:R trigger (e.g., 1.0 to move at 1:1)
4. **Trail**: Use `TRAIL_PSAR` with `PSAR_CUSHION_PIPS` (NOT ATR)
5. **Test**: Verify in visual mode that TP = SL_distance × R:R ratio

This configuration should now match your 60% manual trading strategy! 🎯
