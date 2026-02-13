# SimpleEA v1.02.016d — Preset-Driven Voting EA (MT5)

**RRM_Simple EA** is a modular, institutional-grade Expert Advisor for MetaTrader 5 that combines **market bias (directional analysis)**, **multi-layered filters (risk/sessions/news/spread/volatility)**, and a **vote-based confirmation system** to determine optimal entry and trade management conditions.

This project is specifically designed for **macOS + Wine + MT5** environments using **MQL5-only development** (no C++, no static locals, no lambdas).

---

## 📦 System Architecture

### **Main EA Files**
- **`SimpleEA_v1-02-016d_05-8b_RRM.mq5`** — Production-ready main EA (RRM build with optimized settings)
- **`SimpleEA_v1-02-016d.mq5`** — Baseline version

### **Core Modules (`.mqh` files)**
- **`SEA_SignalEngine.mqh`** — Signal generation, voting logic, bias calculation, indicator management, and RRM gates
- **`SEA_TradeExecutor.mqh`** — Trade execution, position sizing (risk-based + MA-compatible), SL/TP management, breakeven, trailing stops
- **`SEA_Reporting.mqh`** — Strategy Tester CSV export with comprehensive metrics
- **`SEA_UI.mqh`** — Real-time status panels and cockpit display (Settings + Position monitor)

### **Configuration**
- **`SimpleEA_Settings.json`** — Reference settings snapshot (documentation/backup)

### **Additional Resources**
- **`Calendar/`** — News event calendar data for fundamental filter
- **`Sets/`** — Pre-configured `.set` files for Strategy Tester
- **`Readme/`** — Detailed documentation and optimization results
- **`Revision/`** — Development history and previous versions

---

## 🎯 Core Trading Philosophy

### **Decision Pipeline (Conceptual Flow)**

```
1. SAFETY & MARKET FILTERS
   ├─ Spread check (max pips)
   ├─ ATR volatility gates (min/max)
   ├─ Time/Session filters
   ├─ News blackout window
   └─ Optional HTF (Higher Timeframe) veto

2. BIAS / MARKET DIRECTION
   ├─ EMA-based trend analysis (4 EMAs: fast, mid1, mid2, slow)
   ├─ Multiple strategies: Price Cross, EMA Golden Cross, Advanced Mapping
   ├─ Dual-shift support (horizontal + vertical bar shifts)
   └─ Output: +1 (buy) / -1 (sell) / 0 (neutral)

3. VOTING LAYER (Confirmation)
   ├─ EMA Signal vote
   ├─ ADX (trend strength)
   ├─ MACD (momentum alignment)
   ├─ RSI (overbought/oversold zones)
   ├─ CCI (cyclical indicator)
   ├─ MFI (money flow/volume)
   ├─ Stochastic (momentum oscillator)
   ├─ Bollinger Bands (volatility squeeze)
   ├─ PSAR (trend direction)
   └─ Ross Hook (fractal breakout)
   
   Signal accepted if: votes >= VoteThreshold
   (If VoteThreshold <= 1, voting is bypassed = bias-only mode)

4. EXECUTION
   ├─ Position sizing: Risk% or MA-compatible method
   ├��� Margin safety checks
   ├─ SL/TP placement (ATR-based)
   └─ One-trade-per-symbol enforcement

5. TRADE MANAGEMENT
   ├─ Breakeven (ATR-triggered)
   ├─ Trailing stops (ATR / PSAR / Fractal)
   ├─ Optional close-on-reverse signal
   └─ "Let profit run" capabilities
```

---

## 🛠️ Strategy Presets

Presets provide **pre-configured strategy contracts** with automatic parameter overrides:

| Preset | Description | Use Case |
|--------|-------------|----------|
| **PRESET_CUSTOM** | Manual control - no overrides | Full user customization |
| **PRESET_MA_BENCHMARK** | MT5 "Moving Average" EA compatibility | Validation baseline |
| **PRESET_TREND_REVERSAL** | Counter-trend/reversal logic | Reversal trading with confluence |
| **PRESET_TREND_SCALP** | Intraday trend continuation | Fast scalping with tight risk |
| **PRESET_TREND_SWING** | HTF-aligned trend following | Institutional swing trading |
| **PRESET_RANGE_GRID** | Mean-reversion flavor | Conservative range trading |
| **PRESET_RRM** | RRM trend pullback/reclaim | Trend bias + pullback + divergence |

> **Note:** When using presets, check `Inp_PrintEffectiveConfig=true` to see actual applied values after overrides.

---

## 🚀 Quick Start

### **1. Installation**

Copy files to your MT5 data folder:
```
MQL5/Experts/     → SimpleEA_v1-02-016d_05-8b_RRM.mq5
MQL5/Include/     → SEA_SignalEngine.mqh, SEA_TradeExecutor.mqh, 
                     SEA_Reporting.mqh, SEA_UI.mqh
```

### **2. Compilation**

**Critical:** All `.mq5/.mqh/.json` files **MUST** be saved as **UTF-16 LE with BOM (FF FE)**

Compile in MetaEditor:
- Open the `.mq5` file
- Press F7 or click "Compile"
- Verify no errors in the Toolbox

### **3. Attach to Chart or Strategy Tester**

**Live/Demo Chart:**
1. Drag EA onto chart
2. Select `InpPreset` (e.g., PRESET_RRM, PRESET_TREND_SCALP)
3. Enable visualization:
   - `Inp_UI_ShowStatusPanel = true`
   - `Inp_UI_ShowCockpitPanel = true`
4. Configure risk: `InpRiskPercent` (default: 2.0%)

**Strategy Tester:**
1. Select EA in tester
2. Choose symbol and timeframe
3. Configure preset and parameters
4. **Important:** Use **Stop → Start** after changing inputs (especially under macOS+Wine)
5. Enable `Inp_PrintEffectiveConfig=true` to see diagnostic output

---

## 📊 Key Configuration Parameters

### **1. Risk Management**
```cpp
InpRiskPercent        = 2.0    // Risk per trade (%)
InpMaxSpreadPips      = 3.0    // Maximum spread filter
InpMinATRPips         = 5.0    // Minimum ATR volatility
InpMaxATRPips         = 50.0   // Maximum ATR (prevents high-volatility entries)
```

### **2. Bias & Direction Source**
```cpp
InpPreset             = PRESET_RRM    // Strategy preset
Inp_BiasEnabled       = true          // Enable bias calculation
Inp_BiasMode          = BIAS_AUTO     // AUTO, PRICE_CROSS, or TREND
Inp_EmaStrategy       = EMA_STRAT_2_CROSS_1_2  // EMA cross method
```

### **3. Voting System**
```cpp
Inp_VoteThreshold     = 3        // Required votes for entry (1 = bypass voting)
Inp_Use_EmaSig        = true     // EMA signal vote
Inp_Use_Adx           = true     // ADX trend strength vote
Inp_Use_Macd          = true     // MACD momentum vote
Inp_Use_Rsi           = false    // RSI zone vote
Inp_Use_Cci           = false    // CCI vote
Inp_Use_Mfi           = false    // MFI volume vote
Inp_Use_Sto           = false    // Stochastic vote
```

### **4. Exit & Trade Management**
```cpp
Inp_SL_Mult           = 2.0      // Stop Loss (ATR multiplier, 0 = disabled)
Inp_TP_Mult           = 4.0      // Take Profit (ATR multiplier, 0 = disabled)
Inp_Use_BE            = true     // Enable breakeven
Inp_BE_Trig           = 1.0      // Breakeven trigger (ATR)
Inp_BE_Buff           = 0.1      // Breakeven buffer (ATR)
Inp_TrailMode         = TRAIL_PSAR   // TRAIL_NONE, TRAIL_ATR, TRAIL_PSAR, TRAIL_FRACTAL
Inp_Trail_Mult        = 3.0      // Trailing distance (ATR multiplier)
Inp_CloseOnReverse    = false    // Close position on opposite signal
```

### **5. UI & Reporting**
```cpp
Inp_UI_ShowStatusPanel     = true   // Display status panel
Inp_UI_ShowCockpitPanel    = true   // Display cockpit panel
Inp_ExportCSV              = false  // Export Strategy Tester report
Inp_PrintEffectiveConfig   = true   // Print effective settings (diagnostic)
```

---

## 💡 "Let Profit Run" Configuration

To maximize profit-taking while protecting gains:

1. **Disable Fixed TP:**
   ```cpp
   Inp_TP_Mult = 0.0   // Set to 0 to disable fixed take-profit
   ```

2. **Enable Trailing Stop:**
   ```cpp
   Inp_TrailMode = TRAIL_PSAR  // or TRAIL_ATR
   Inp_Trail_Mult = 3.0        // Adjust distance
   ```

3. **Enable Breakeven:**
   ```cpp
   Inp_Use_BE = true
   Inp_BE_Trig = 1.0   // Trigger when 1x ATR in profit
   Inp_BE_Buff = 0.1   // Small buffer above entry
   ```

4. **Disable Close-on-Reverse (for less noisy markets):**
   ```cpp
   Inp_CloseOnReverse = false
   ```

> **Note:** Some presets (including PRESET_RRM) may override these. Always verify with `Inp_PrintEffectiveConfig=true`.

---

## 🎨 UI & Visualization

### **Status Panel**
Displays:
- Preset mode and effective configuration
- MA method, periods, and shifts
- Bias mode and direction source
- Vote threshold and enabled filters
- Overrides and ignored flags

### **Cockpit Panel**
Real-time monitoring:
- Current bar timestamp
- Spread and ATR (in pips)
- Risk sizing method
- Last signal direction and bias
- Voting status (or BYPASS)
- Position info (side, volume, entry, P&L, SL/TP)

### **Signal Markers**
- Entry eligibility markers (per bar)
- Executed trade markers (visual confirmation)

### **Chart Indicator Management**
When `Inp_UI_ManageChartIndicators=true`, the EA will automatically manage indicators on the chart for consistent visualization (recommended for Strategy Tester visual mode).

---

## 📈 Strategy Tester CSV Reporting

### **Enable CSV Export:**
```cpp
Inp_ExportCSV = true
Inp_ExportUseCommonFiles = false  // Keep false for macOS+Wine compatibility
```

### **Report Contents:**
- Test configuration (preset, bias mode, votes, overrides)
- Core performance metrics (net profit, profit factor, Sharpe ratio)
- Risk & drawdown statistics
- Trade statistics (win rate, total trades)
- Deal-by-deal history (time, type, volume, price, profit, balance)

### **File Location:**
- **false (default):** `MT5/Tester/Agent-xxx/Files/`
- **true:** `Common/Files/` (may not work reliably on macOS+Wine)

---

## 🔧 Troubleshooting

### **"Settings changed but behavior didn't"**
✅ **Solution:** In Strategy Tester, use **Stop → Start** (not just restart)
✅ Enable `Inp_PrintEffectiveConfig=true` to see what's actually being applied

### **"Too many signal lines"**
⚠️ These represent **eligible signals** per bar (not only executed trades)
✅ Adjust marker display settings or use "execution only" visualization mode

### **"No trades opening"**
Check `LastReason` in the status panel or Expert log:
- Spread veto (spread too high)
- ATR veto (volatility too low or too high)
- News/time veto (blackout period)
- HTF veto (higher timeframe disagrees)
- Insufficient votes (not enough confirmation)
- Lot sizing = 0 (risk calculation failed or margin insufficient)
- Bias = 0 (no directional conviction)

### **"Indicators not showing on chart"**
✅ Enable `Inp_UI_ManageChartIndicators=true`
✅ Restart EA or use Stop → Start in tester

---

## ⚙️ Development Notes (IMPORTANT)

### **Platform Constraints:**
- **MQL5 ONLY** (no C++, no lambdas, no static locals)
- **UTF-16 LE with BOM encoding** required for all `.mq5/.mqh/.json` files
- Designed for **macOS + Wine + MT5** compatibility
- Conservative file I/O (avoid `FILE_COMMON` unless verified)

### **File Encoding Verification:**
```bash
# Check file encoding (macOS/Linux)
file -I SimpleEA_v1-02-016d_05-8b_RRM.mq5

# Should show: charset=utf-16le
# First bytes should be: FF FE (BOM)
```

### **Build Versioning:**
```cpp
#define SEA_BUILD_NUM 1020168
#define SEA_BUILD_STR "1.02.016d-05-8_RRM"
```

---

## 📚 Additional Documentation

- **`README_INDICATORS.md`** — Detailed indicator documentation and voting logic
- **`Readme/README_SimpleEA_v1-01.md`** — Original system documentation
- **`Readme/README_v1-02-014e1.md`** — Dual-shift elastic voting EA documentation
- **`Readme/_sea_optimization_results_*.md`** — Optimization results and analysis

---

## 🏆 Key Features & Differentiators

✅ **Modular Architecture** — Cleanly separated concerns (Signal / Execution / Reporting / UI)  
✅ **Preset-Driven** — Pre-configured strategies with automatic parameter management  
✅ **Vote-Based Confirmation** — Reduces false signals through multi-indicator consensus  
✅ **Dual Shift Support** — Horizontal (forward-looking) and vertical (bar shift) flexibility  
✅ **RRM Strategy** — Specialized trend pullback/reclaim logic with divergence detection  
✅ **Advanced Trade Management** — Breakeven, multiple trailing modes, close-on-reverse  
✅ **macOS+Wine Optimized** — Designed specifically for constrained Wine/MT5 environments  
✅ **Comprehensive Reporting** — Strategy Tester CSV export with full trade-by-trade detail  
✅ **Real-Time Diagnostics** — Status and cockpit panels with live position monitoring  

---

## 📋 System Requirements

- **Platform:** MetaTrader 5 (build 3650+)
- **Operating System:** Windows / macOS (via Wine)
- **MQL5 Version:** Latest stable release
- **Encoding:** UTF-16 LE with BOM for all source files
- **Minimum Account:** $1000 recommended (for proper risk management)

---

## ⚖️ Risk Disclaimer

**Trading forex and CFDs involves substantial risk of loss.** This EA is provided for educational and research purposes. Past performance does not guarantee future results. Always test thoroughly in demo/backtest environments before live deployment.

---

## 📝 Version History

**v1.02.016d-05-8_RRM (Current)**
- Full dual-shift support (horizontal + vertical)
- RRM preset alignment with legacy controller
- MaxATR upper volatility bound (TASK1 OPT)
- PSAR trailing stop implementation
- Enhanced UI panels with cockpit display
- Build lock tokens for module version checking

---

## 📞 Support & Contact

**Repository:** [msmaciej/RRM_SEA](https://github.com/msmaciej/RRM_SEA)  
**Description:** RRM_Simple EA - macOS + Wine + MT5 + MQL5 ONLY (no C++, no static locals, no lambdas)

---

*Last updated: 2026-02-13 (aligned to SimpleEA v1-02-016d-05-8_RRM)*

---

## 🎓 Quick Reference Card

**Essential Checks Before Running:**
1. ✅ Files saved as UTF-16 LE with BOM
2. ✅ All `.mqh` files in `MQL5/Include/`
3. ✅ Selected appropriate preset
4. ✅ Risk% set appropriately (default: 2.0%)
5. ✅ `Inp_PrintEffectiveConfig=true` for diagnostics

**Recommended Starting Configuration (Conservative):**
```cpp
InpPreset          = PRESET_RRM
InpRiskPercent     = 1.5
Inp_VoteThreshold  = 3
Inp_SL_Mult        = 2.0
Inp_TP_Mult        = 0.0   // Let profit run
Inp_TrailMode      = TRAIL_PSAR
Inp_Use_BE         = true
```

**Performance Metrics to Monitor:**
- Win Rate > 40%
- Profit Factor > 1.2
- Max Drawdown < 20%
- Sharpe Ratio > 0.5
- Average trade count: 20-50 per month (depending on timeframe)

---

**Remember: Simple systems that work > Complex systems that don't**