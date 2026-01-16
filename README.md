# RRM Simple EA v1-0-000

## Revisions Description

vX-X-XXX
 │ │ │
 │ │ └─ Patch:  Documentation updates, fixes, clarifications
 │ └─── Minor: New sections, reorganization, non-breaking changes
 └───── Major: Core architecture changes (matches EA version)


**Simplified Trading System for MetaTrader 5**

## Philosophy

This EA follows the principle:  **Simple + Robust + Fast > Complex + Fragile + Slow**

- ✅ All logic in ONE file (~500 lines)
- ✅ JSON-driven configuration
- ✅ Clear, readable code
- ✅ Easy to test and modify
- ✅ Fast execution

## Platform Requirements

- **Operating System:** macOS + Wine + MT5
- **Language:** MQL5 ONLY
  - ❌ NO C++ features
  - ❌ NO static locals
  - ❌ NO lambdas
  - ❌ NO templates
- **File Encoding:**
  - `.mq5`, `.mqh`, `.json` files:  **UTF-16 LE with BOM (FF FE)**
  - `README.md`: UTF-8 (no BOM)

## Trading Logic

### Entry Signal Flow

```
1. New Bar Check → Only trade on closed bars
                    ↓
2. Basic Filters  → Spread < max_spread_pips
                  → ATR > min_atr_pips
                  → Candle body > min_body_pips
                    ↓
3. Market Bias    → EMA Stack Analysis
   (Trend)        → BULLISH:  ema_fast > ema_mid1 > ema_mid2 > ema_slow
                  → BEARISH: ema_fast < ema_mid1 < ema_mid2 < ema_slow
                  → CHOPPY: Mixed = NO TRADE
                    ↓
4. Pullback       → Look back N bars (pullback_lookback)
   Detection      → BULLISH: Low touched mid EMA from above
                  → BEARISH:  High touched mid EMA from below
                    ↓
5. Optional:       → MACD:  Main line aligned with trend
   MACD Filter    → BULLISH: main > signal
                  → BEARISH: main < signal
                    ↓
6. Optional:      → Avoid extremes
   RSI Filter     → BULLISH: RSI < overbought (70)
                  → BEARISH: RSI > oversold (30)
                    ↓
7. Recovery       → Price back in trend direction
   Confirmation   → BULLISH: Close > ema_fast
                  → BEARISH: Close < ema_fast
                    ↓
8. Execute Trade  → Calculate lot size from risk %
                  → SL = ATR × sl_atr_multiplier
                  → TP = ATR × tp_atr_multiplier
```

### Market Bias Determination

**Current Method:  EMA Stack**

The EA determines market bias by analyzing the relationship between 4 EMAs:

**BULLISH BIAS (Uptrend):**
- Fast EMA (13) > Mid1 EMA (21) > Mid2 EMA (34) > Slow EMA (55)
- All EMAs properly stacked from top to bottom
- Price should be above the fast EMA

**BEARISH BIAS (Downtrend):**
- Fast EMA (13) < Mid1 EMA (21) < Mid2 EMA (34) < Slow EMA (55)
- All EMAs properly stacked from bottom to top
- Price should be below the fast EMA

**NO BIAS (Choppy/Consolidation):**
- EMAs are crossed or not aligned
- No trade signals generated

**Function:** `GetTrendDirection()` in line ~250

### Pullback Detection

**Simple 5-Bar Lookback:**

For **LONG** setups:
1. Trend confirmed (bullish EMA stack)
2. Look back 5 bars (configurable)
3. Check if any bar's LOW touched the mid1 EMA (±0.05% tolerance)
4. Current bar:  Close > fast EMA (recovery confirmation)

For **SHORT** setups: 
1. Trend confirmed (bearish EMA stack)
2. Look back 5 bars
3. Check if any bar's HIGH touched the mid1 EMA (±0.05% tolerance)
4. Current bar: Close < fast EMA (recovery confirmation)

**Function:** `CheckPullback()` in line ~280

## Indicators Used

| Indicator | Purpose | Default Settings |
|-----------|---------|------------------|
| **EMA (4)** | Market bias and structure | 13, 21, 34, 55 |
| **MACD** | Momentum confirmation (optional) | 12, 26, 9 |
| **RSI** | Overbought/oversold filter (optional) | 14 period, 30/70 levels |
| **ATR** | Volatility + SL/TP sizing | 14 period |
| **Candle Body** | Entry bar quality | Min 0.5 pips |

## Risk Management

- **Position Sizing:** Based on account balance × risk_percent
- **Stop Loss:** ATR × sl_atr_multiplier (default:  2.0 ATR)
- **Take Profit:** ATR × tp_atr_multiplier (default: 4.0 ATR)
- **Trailing Stop:** Optional, ATR × trail_atr_multiplier (default: 1.5 ATR)

## Configuration

All settings in `SimpleEA_Settings.json`:

```json
{
  "risk":  {
    "percent": 2.0,           // Risk 2% per trade
    "max_spread_pips": 2.0,   // Reject if spread > 2 pips
    "min_atr_pips": 5.0       // Reject if ATR < 5 pips (low volatility)
  },
  
  "indicators": {
    "ema": {
      "fast": 13,
      "mid1": 21,             // Used for pullback detection
      "mid2":  34,
      "slow":  55
    }
  },
  
  "entry": {
    "min_body_pips": 0.5,          // Minimum candle body size
    "pullback_lookback": 5,        // Look back 5 bars for pullback
    "require_macd_align": true,    // Require MACD confirmation
    "require_rsi_filter": false    // Optional RSI filter
  },
  
  "exit": {
    "sl_atr_multiplier":  2.0,      // SL = 2 × ATR
    "tp_atr_multiplier": 4.0,      // TP = 4 × ATR (1: 2 risk/reward)
    "trail_stop": true,            // Enable trailing stop
    "trail_atr_multiplier": 1.5    // Trail at 1.5 × ATR
  }
}
```

## Installation

1. Copy `SimpleEA_vX-X-XXX.mq5` to `MQL5/Experts/`
2. Copy `SimpleEA_Settings.json` to `MQL5/Files/`
3. Ensure both files are UTF-16 LE with BOM
4. Compile in MetaEditor
5. Attach to chart

## Testing Before Modifications

### Strategy Tester Setup

1. **Open Strategy Tester** (Ctrl+R)
2. **Select EA:** SimpleEA_v1-0-000
3. **Symbol:** EURUSD (or your preferred pair)
4. **Timeframe:** H1 or H4 recommended
5. **Period:** 2024. 01.01 - 2024.12.31 (1 year)
6. **Mode:** "Every tick based on real ticks"
7. **Optimization:** OFF (initial test)

### What to Check

**Essential Metrics:**
- ✅ Does it open trades?  (should see 20-50 trades per year)
- ✅ Win rate > 40%? 
- ✅ Profit Factor > 1.2?
- ✅ Max drawdown < 20%?
- ✅ Risk/Reward ratio ~1:2?

**Log Analysis:**
- Check Expert tab for entry signals
- Verify EMA stack detection working
- Confirm pullback detection triggering
- Check SL/TP calculations

### If No Trades Open

**Debug checklist:**
1. Check spread filter (might be too strict)
2. Check ATR filter (might be too high)
3. Check EMA stack requirement (might be too strict)
4. Check pullback detection (lookback might be too short)

## Modular Expansion

### Adding Indicators WITHOUT Breaking Logic

The EA is designed for easy expansion.  Each indicator check is isolated:

**Example:  Adding PSAR for SL positioning**

```mql5
// Add to settings struct (line ~40)
struct EASettings {
    // ... existing fields ...
    bool use_psar_sl;        // NEW: Use PSAR for SL instead of ATR
    int psar_step;           // NEW: PSAR step
    int psar_maximum;        // NEW: PSAR maximum
};

// Add to JSON loading (line ~90)
g_settings.use_psar_sl = root["exit"]["use_psar_sl"]. ToBool();
g_settings.psar_step = (int)root["indicators"]["psar"]["step"].ToInt();
g_settings.psar_maximum = (int)root["indicators"]["psar"]["maximum"].ToInt();

// Modify OpenTrade() function (line ~350)
void OpenTrade(ENUM_ORDER_TYPE order_type)
{
    // ... existing code ...
    
    double sl_price;
    
    if(g_settings.use_psar_sl) {
        // NEW: Use PSAR dot for SL
        int psar_handle = iSAR(_Symbol, PERIOD_CURRENT, 
                               g_settings.psar_step * 0.01, 
                               g_settings.psar_maximum * 0.1);
        double psar[1];
        if(CopyBuffer(psar_handle, 0, 1, 1, psar) > 0) {
            sl_price = psar[0];
        }
        IndicatorRelease(psar_handle);
    }
    else {
        // Original:  Use ATR-based SL
        if(order_type == ORDER_TYPE_BUY)
            sl_price = price - (atr_value * g_settings.sl_atr_multiplier);
        else
            sl_price = price + (atr_value * g_settings.sl_atr_multiplier);
    }
    
    // ... rest of code unchanged ...
}
```

**This approach:**
- ✅ Doesn't break existing ATR logic
- ✅ Adds optional PSAR mode
- ✅ JSON-controlled (no recompile to switch)
- ✅ Isolated change (easy to debug)

### Adding Manual Market Bias

```mql5
// Add to settings
struct EASettings {
    string bias_mode;        // "auto", "long_only", "short_only"
};

// Modify EvaluateEntry()
int EvaluateEntry()
{
    // ... existing code ...
    
    int trend = GetTrendDirection(... );
    
    // NEW: Apply manual bias override
    if(g_settings. bias_mode == "long_only" && trend == -1)
        return 0;  // Block SHORT signals
    if(g_settings. bias_mode == "short_only" && trend == 1)
        return 0;  // Block LONG signals
    
    // ... rest of logic unchanged ...
}
```

## Current Limitations

1. **Market Bias:** Only EMA-based (no MT classification like weak/medium/strong)
2. **Pullback:** Simple 5-bar lookback (no convergence/divergence tracking)
3. **SL Positioning:** ATR-only (no PSAR, no EMA-based)
4. **Entry Timing:** Immediate on signal (no multi-bar confirmation)
5. **Trade Management:** Basic trailing only (no partial closes, pyramiding)

These are **intentional simplifications**. Add complexity ONLY if backtesting proves it adds edge. 

## Development Roadmap

**Phase 1: Test Base System** (Current)
- Run 1-year backtest on EURUSD H1/H4
- Verify edge exists with current logic
- Document baseline metrics

**Phase 2: Optimize** (If Phase 1 profitable)
- Find optimal EMA periods
- Find optimal ATR multipliers
- Find optimal pullback lookback
- Test on multiple pairs/timeframes

**Phase 3: Enhance** (If Phase 2 shows consistent profit)
- Add PSAR SL option
- Add manual bias override
- Add market type classification (weak/medium/strong)
- Add multi-timeframe confirmation

**Phase 4: Production** (If Phase 3 maintains edge)
- Forward test on demo 3 months
- Add risk controls (max daily loss, drawdown limits)
- Deploy to live (small lot size)

## Support

- **Issues:** Create GitHub issue
- **Questions:** See code comments in SimpleEA_vX-X-XXX.mq5
- **Modifications:** Test thoroughly before live deployment

## License
MIT License - Free to use, modify, distribute

---

JSON SETTINGS EXAMPLES:

Conservative JSON Settings 
(Fewer trades, higher quality)

{
  "risk":  { "percent": 1.0 },
  "indicators": {
    "ema":  { "fast": 21, "slow": 89 }
  },
  "entry": {
    "min_body_pips": 1.0,
    "require_macd_align": true,
    "require_rsi_filter": true
  },
  "exit": {
    "sl_atr_multiplier": 3.0,
    "tp_atr_multiplier": 6.0
  }
}

Aggressive JSON Settings 
(More trades, faster entries)

{
  "risk": { "percent": 3.0 },
  "indicators": {
    "ema":  { "fast": 8, "slow": 34 }
  },
  "entry": {
    "min_body_pips": 0.3,
    "require_macd_align": false,
    "require_rsi_filter": false
  },
  "exit":  {
    "sl_atr_multiplier": 1.5,
    "tp_atr_multiplier": 3.0
  }
}

---

**Remember:  Simple systems that work > Complex systems that don't**