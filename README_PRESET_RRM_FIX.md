# PRESET_RRM Fix - Quick Start Guide

## 🎯 What Was Fixed
The EA's PRESET_RRM now supports **true swing-based stop loss with risk-reward ratio take profit**, eliminating ATR interference that was causing poor backtest performance.

**Before**: 38% win rate in backtesting ❌  
**Goal**: 60% win rate matching manual strategy ✅

## 📁 Documentation Files

### For Users
📖 **[PRESET_RRM_STRATEGY_TESTER_GUIDE.md](./PRESET_RRM_STRATEGY_TESTER_GUIDE.md)**
- Complete Strategy Tester configuration guide
- Recommended settings for different timeframes
- Optimization tips and troubleshooting
- **Start here if you just want to use the EA**

### For Developers
🔧 **[PRESET_RRM_IMPLEMENTATION_SUMMARY.md](./PRESET_RRM_IMPLEMENTATION_SUMMARY.md)**
- Technical change summary with code comparisons
- Testing checklist and edge case analysis
- Backward compatibility notes
- **Start here if you want to understand the implementation**

## 🚀 Quick Start (3 Steps)

### Step 1: Load EA in Strategy Tester
1. Open MetaTrader 5 Strategy Tester
2. Select `SimpleEA_v1-02-016d_05-9_RRM.mq5`
3. Choose your symbol and timeframe (H1 recommended)

### Step 2: Configure PRESET_RRM Settings
```
InpPreset = PRESET_RRM

=== SL PLACEMENT ===
Inp_SL_PlacementMode = SL_SWING_HIGHLOW
Inp_SL_SwingPipsCushion = 10.0

=== TP (R:R RATIO) ===
Inp_TP_Mult = 2.0  // 1:2 R:R ratio

=== BREAKEVEN ===
Inp_Use_BE = true
Inp_BE_Trig = 1.0  // Move to BE at 1:1 R:R

=== TRAILING ===
Inp_TrailMode = TRAIL_PSAR
Inp_PSAR_TrailCushionMode = PSAR_CUSHION_PIPS
Inp_PSAR_TrailPipsCushion = 5.0
```

### Step 3: Run and Verify
1. Run in **visual mode** first
2. Verify:
   - ✅ SL is at swing high/low + cushion pips
   - ✅ If SL is 15 pips from entry, TP is 30 pips (1:2 R:R)
   - ✅ BE moves SL to entry at 1:1 profit
   - ✅ Trailing follows PSAR with pips cushion

## ❓ Common Questions

### Q: What's the main benefit?
**A**: TP is now calculated from actual SL distance, not ATR. This gives you true R:R ratios (e.g., 1:2 means TP is exactly 2× SL distance).

### Q: Does this break other presets?
**A**: No! Only PRESET_RRM is affected. Other presets (MANUAL, MA_BENCHMARK, etc.) work exactly as before.

### Q: Can I still use ATR-based exits?
**A**: Yes! Set `Inp_SL_PlacementMode = SL_ATR` to use legacy ATR-based behavior.

### Q: What if my win rate is still low?
**A**: See optimization tips in [PRESET_RRM_STRATEGY_TESTER_GUIDE.md](./PRESET_RRM_STRATEGY_TESTER_GUIDE.md), section "Optimization Tips".

## 🔍 What Changed in the Code

### SimpleEA_v1-02-016d_05-9_RRM.mq5
- Removed hardcoded ATR multipliers (`SL_Mult`, `TP_Mult`, `BE_Trig`)
- PRESET_RRM now uses input parameters for full user control
- All exit settings (SL, TP, BE, trailing) are now configurable

### SEA_TradeExecutor.mqh
- Added intelligent TP calculation based on SL placement mode
- For swing/fixed SL modes: `TP = SL_distance × R:R_ratio`
- For ATR SL modes: `TP = ATR × multiplier` (legacy behavior)
- Added edge case protection (zero SL distance, failed SL calculation)

## 📊 Expected Results

### Entry Logic (Unchanged)
- 4/4 votes required (EMA + MACD + CCI + PSAR)
- ADX > 20 filter (avoid choppy markets)
- EMA slope direction for bias

### Exit Logic (Fixed)
- **SL**: Swing high/low + pips cushion (swing-based, not ATR) ✅
- **TP**: Exact R:R ratio from SL distance (e.g., 1:2 = 2× SL) ✅
- **BE**: Moves at configured R:R trigger (e.g., 1:1) ✅
- **Trailing**: PSAR with pips cushion (no ATR interference) ✅

### Performance Target
- **Win rate**: ~60% (matching manual strategy)
- **R:R consistency**: Every trade has exact R:R ratio configured
- **No ATR variance**: TP distance doesn't change with market volatility

## 🛠️ Technical Details

### Files Modified
1. `SimpleEA_v1-02-016d_05-9_RRM.mq5` - PRESET_RRM configuration
2. `SEA_TradeExecutor.mqh` - TP calculation logic

### Files Created
1. `PRESET_RRM_STRATEGY_TESTER_GUIDE.md` - User documentation
2. `PRESET_RRM_IMPLEMENTATION_SUMMARY.md` - Developer documentation
3. `README_PRESET_RRM_FIX.md` - This file

### Safety Features
- ✅ Edge case protection (zero SL distance)
- ✅ Fallback to ATR if SL calculation fails
- ✅ Backward compatibility with legacy modes
- ✅ Input validation via existing EA checks

## 📞 Support

### Issues or Questions
1. Check the documentation files above
2. Test in visual mode to verify behavior
3. Compare backtest results to manual trading

### Next Steps
1. Read [PRESET_RRM_STRATEGY_TESTER_GUIDE.md](./PRESET_RRM_STRATEGY_TESTER_GUIDE.md) for detailed configuration
2. Run backtests with recommended settings
3. Optimize parameters for your specific symbol/timeframe
4. Compare results to manual trading performance

---

**Remember**: The goal is to match your 60% manual trading win rate by using true swing-based SL with R:R TP, eliminating ATR interference! 🎯
