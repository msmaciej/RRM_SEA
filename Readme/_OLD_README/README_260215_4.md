# SimpleEA - Professional Trading System for MT5

## Overview

**SimpleEA** is a professional-grade Expert Advisor for MetaTrader 5 that implements a comprehensive 9-step signal validation pipeline combining **market bias analysis**, **multi-indicator voting**, and **risk-aware position management**. Designed specifically for **macOS + Wine + MT5** environments using **MQL5-only development** (no C++, no static locals, no lambdas).

The system trades **quality over quantity**, using a strict multiplicative voting system where ALL enabled indicators must agree before entering a position. This results in fewer but higher-probability trades with improved win rates.

**Core Philosophy:** Simple systems that work > Complex systems that don't

---

## Table of Contents

- [System Architecture](#system-architecture)
- [How SimpleEA Works: Complete Process Flow](#how-simpleea-works-complete-process-flow)
- [The 9-Step Signal Pipeline: Visual Overview](#the-9-step-signal-pipeline-visual-overview)
- [Key Concepts (Quick Summary)](#key-concepts-quick-summary)
- [Key Design Principles](#key-design-principles)
- [Configuration Guide](#configuration-guide)
- [Installation](#installation)
- [Strategy Tester Usage](#strategy-tester-usage)
- [Additional Documentation](#additional-documentation)
- [System Requirements](#system-requirements)

**For detailed technical documentation:** See [README_INDICATORS.md](README_INDICATORS.md)

---

## System Architecture

### Core Components

**1. SimpleEA (Main Orchestrator)**  
- File: `SimpleEA_v1-02-016d_05-9_RRM.mq5`
- Coordinates all components
- Handles OnTick() event loop
- Manages new bar detection
- Triggers signal evaluation

**2. SEA_SignalEngine (Signal Pipeline)**  
- File: `SEA_SignalEngine.mqh`
- Implements 9-step validation pipeline
- Manages indicator handles
- Performs voting logic
- Returns trade direction: 1 (LONG), -1 (SHORT), 0 (NO TRADE)

**3. SEA_TradeExecutor (Trade Management)**  
- File: `SEA_TradeExecutor.mqh`
- Executes trade entries
- Calculates position sizing (risk-based + MA-compatible)
- Manages SL/TP placement (5 modes available)
- Implements breakeven logic
- Handles trailing stops (ATR, PSAR, Fractal)

**4. SEA_UI (Visualization)**  
- File: `SEA_UI.mqh`
- Real-time status panels
- Cockpit display with position monitoring
- Signal markers on chart

**5. SEA_Reporting (Analytics)**  
- File: `SEA_Reporting.mqh`
- Strategy Tester CSV export
- Comprehensive metrics and deal history

### Component Interaction Diagram

```
┌─────────────┐
│   OnTick()  │  ← Every price tick
└──────┬──────┘
       │
       ▼
┌─────────────────────────┐
│  New Bar Detection?     │
│  (Check iTime[0])       │
└──────┬──────────────────┘
       │
       ├─ NO → Manage existing positions (Breakeven, Trailing)
       │
       ├─ YES → Evaluate signal
       │
       ▼
┌─────────────────────────────────────────┐
│  SignalEngine.GetDirection()            │
│  [9-Step Pipeline on shift=1]           │
│  Returns: 1 (LONG) / -1 (SHORT) / 0    │
└──────┬──────────────────────────────────┘
       │
       ├─ Signal = 0 → Wait for next bar
       │
       ├─ Signal ≠ 0 → Calculate position size
       │
       ▼
┌─────────────────────────────────────────┐
│  TradeExecutor.ProcessSignal()          │
│  - Check: No existing position?         │
│  - Calculate lots (risk-based)          │
│  - Calculate SL/TP (ATR-based)          │
│  - Open trade at shift=0                │
└─────────────────────────────────────────┘
```

---

## How SimpleEA Works: Complete Process Flow

### Main Execution Loop (OnTick)

**Every time a new bar closes:**

```
1. Check if we have an open position
   ├─ YES → Manage it (breakeven, trailing stops)
   └─ NO → Look for new signal

2. Detect if new bar formed
   └─ Compare current iTime[0] with stored last bar time

3. If new bar → Call Signal Engine to evaluate conditions
   └─ SignalEngine.GetDirection() [9-step pipeline on shift=1]

4. If valid signal (≠ 0) AND no position open:
   ├─ Calculate position size
   ├─ Calculate SL/TP levels
   └─ Execute trade at shift=0 (current candle open)

5. Otherwise → Wait for next bar
```

**Critical Timing:**
- Signal evaluation happens on **shift=1** (CLOSED candle)
- Trade entry happens on **shift=0** (NEW candle open)
- This prevents repainting and ensures stable signals

---

## The 9-Step Signal Pipeline: Visual Overview

**All evaluation happens on CLOSED candle (shift=1)**

The system follows a strict sequential pipeline where **any failure stops immediately and returns 0 (NO TRADE)**:

```
Step 1: PRE-FILTERS
├─ Spread < MaxSpreadPips?
├─ MinATR < ATR < MaxATR?
├─ Time/Session allowed?
└─ No news blackout?
   → If ANY fail → TS = 0 → STOP
                ↓
Step 2: MARKET BIAS DETERMINATION
├─ Compare Fast EMA vs Slow EMA
├─ Check EMA slopes (rising/falling)
├─ Strategy-dependent relaxation:
│  ├─ STRAT_PAIR_CROSS: Only Fast slope required (relaxed)
│  └─ Others: Both slopes required (strict)
└─ Result: bias ∈ {-1, 0, 1} = {SHORT, NEUTRAL, LONG}
   → If bias = 0 → TS = 0 → STOP
                ↓
Step 3: AUTOSTRAT ENTRY SIGNAL
├─ STRAT_SINGLE_SLOPE: Single EMA direction
├─ STRAT_PRICE_CROSS: Price vs EMA
└─ STRAT_PAIR_CROSS: EMA crossover
   → Generate entry_signal (1/-1/0)
                ↓
Step 4: SIGNAL VALIDATION
└─ entry_signal must match bias direction
   → If mismatch → TS = 0 → STOP
                ↓
Step 5: HTF FILTER (Optional)
└─ Higher timeframe EMA must align with bias
   → If HTF disagrees → TS = 0 → STOP
                ↓
Step 6: RRM GATES (Optional)
├─ RRM_RequirePullbackReclaim?
│  └─ Check if price pulled back to EMA then reclaimed
└─ RRM_RequireEmaDiv?
   └─ Check if EMAs are expanding (not converging)
   → If enabled gates not met → TS = 0 → STOP
                ↓
Step 7: VOTING BYPASS CHECK
└─ If VoteThreshold <= 1 → Accept signal (bypass voting)
   → Otherwise → Continue to voting
                ↓
Step 8: INDICATOR VOTING
├─ Count votes from enabled indicators:
│  ├─ EMA1 (price position)
│  ├─ ADX (trend strength)
│  ├─ MACD (momentum alignment)
│  ├─ CCI (cyclical)
│  ├─ RSI (momentum zones)
│  ├─ Stochastic (momentum)
│  ├─ PSAR (trend direction)
│  ├─ Bollinger Bands (volatility)
│  ├─ MFI (money flow)
│  ├─ P123 (pattern)
│  └─ Ross Hook (fractal)
└─ Each indicator votes: 1 (AGREE) or 0 (DISAGREE)
                ↓
Step 9: FINAL DECISION
├─ Count total votes
├─ Compare: votes >= VoteThreshold?
│  ├─ YES → TS = bias direction (±1)
│  └─ NO → TS = 0
└─ Return TS to main EA
```

**Key Principle:** TS (Trade Signal) = Market_Bias × Indicator₁ × Indicator₂ × ... × Indicatorₙ

Where:
- **ANY component = 0** → Entire result = 0 (NO TRADE)
- **ALL components = 1** → Result = bias direction (±1)

This multiplicative system ensures **unanimous agreement** before entering a position.

---

## Key Concepts (Quick Summary)

### Market Bias vs Entry Signal

**Market Bias** = Primary trend filter that determines if the market is in LONG, SHORT, or NEUTRAL state based on EMA position and slope alignment. Acts as the master filter - no trades are taken against the bias.

**Entry Signal** = Timing signal generated by the AutoStrat strategy within the bias context. Must match the bias direction to be accepted.

### The Multiplicative Voting System

The system uses a multiplicative formula: **TS = Market_Bias × Indicator₁ × Indicator₂ × ... × Indicatorₙ**

This means **ANY component = 0 → entire result = 0** (NO TRADE). This strict filtering requires unanimous agreement from all enabled indicators, resulting in fewer but higher-quality trades.

### Signal Timing: shift=1 vs shift=0

- **Signal evaluation**: Happens on **shift=1** (CLOSED candle) - stable, confirmed data
- **Trade entry**: Happens on **shift=0** (NEW candle open) - immediate execution
- **Result**: No repainting, stable backtests, predictable live performance

**For detailed explanations of the signal pipeline, voting logic, and indicator calculations, see [README_INDICATORS.md](README_INDICATORS.md)**

---

## Key Design Principles

### 1. No Repainting

**How:** All decisions on shift=1 (closed candle)  
**Why:** Stable, backtestable results  
**Benefit:** What you see in backtest = what you get in live

**Timing:**
```
Candle N (shift=1):  Evaluate signal [CLOSED]
Candle N+1 (shift=0): Execute trade [OPEN]
```

### 2. Strict Filtering

**How:** Multiplicative voting (ANY disagreement = NO TRADE)  
**Why:** High-quality signals only  
**Benefit:** Higher win rate, fewer but better trades

### 3. Modular Architecture

**How:** Separate components (Signal, Execution, Risk, UI)  
**Why:** Easy to test, debug, and enhance  
**Benefit:** Professional-grade code structure

### 4. Shift-Based Timing

**How:** Evaluate on shift=1, execute on shift=0  
**Why:** Confirmation + Speed  
**Benefit:** Best of both worlds

---

## Configuration Guide

### Conservative Setup (High Quality, Fewer Trades)

```mql5
// BIAS & STRATEGY
InpPreset = PRESET_RRM                    // RRM Trend Pullback
Inp_BiasMode = BIAS_AUTO                  // Automatic bias
Inp_BiasFastID = 1                        // EMA 13 (fast)
Inp_BiasSlowID = 2                        // EMA 34 (slow)
Inp_AutoStrat = STRAT_PAIR_CROSS          // EMA crossover

// VOTING SYSTEM
Inp_VoteThreshold = 4                     // Need 4 votes
Inp_Use_EmaSig = true                     // Price vs EMA
Inp_Use_Macd = true                       // Momentum
Inp_Use_Cci = true                        // Cyclical
Inp_Use_Psar = true                       // Trend direction

// RRM QUALITY GATES
Inp_RRM_RequirePullbackReclaim = true     // Wait for pullback
Inp_RRM_RequireEmaDiv = true              // Require divergence

// RISK MANAGEMENT
InpRiskPercent = 1.5                      // 1.5% risk per trade
Inp_SL_Mult = 2.0                         // 2× ATR stop loss
Inp_TP_Mult = 4.0                         // 4× ATR take profit

// TRADE MANAGEMENT
Inp_Use_BE = true                         // Enable breakeven
Inp_BE_Trig = 1.0                         // Trigger at 1× ATR
Inp_BE_Buff = 0.1                         // Buffer 0.1× ATR
Inp_TrailMode = TRAIL_PSAR                // PSAR trailing

// FILTERS
InpMaxSpreadPips = 3.0                    // Max 3 pips spread
InpMinATRPips = 5.0                       // Min volatility
InpMaxATRPips = 50.0                      // Max volatility
```

**Expected Results:**
- Win rate: 55-60%
- Trades per month: 5-15 (H1/H4 timeframes)
- High-quality entries at pullbacks
- Lower drawdown

---

### Aggressive Setup (More Trades, Earlier Entries)

```mql5
// BIAS & STRATEGY
InpPreset = PRESET_CUSTOM                 // Custom control
Inp_BiasMode = BIAS_AUTO                  // Automatic bias
Inp_BiasFastID = 0                        // EMA 5 (very fast)
Inp_BiasSlowID = 1                        // EMA 13 (fast)
Inp_AutoStrat = STRAT_PRICE_CROSS         // Price cross

// VOTING SYSTEM
Inp_VoteThreshold = 3                     // Need 3 votes (lower)
Inp_Use_EmaSig = true                     // Price vs EMA
Inp_Use_Macd = true                       // Momentum
Inp_Use_Adx = true                        // Trend strength

// RRM QUALITY GATES
Inp_RRM_RequirePullbackReclaim = false    // No pullback wait
Inp_RRM_RequireEmaDiv = false             // No divergence check

// RISK MANAGEMENT
InpRiskPercent = 2.0                      // 2% risk per trade
Inp_SL_Mult = 1.5                         // 1.5× ATR (tighter)
Inp_TP_Mult = 3.0                         // 3× ATR

// TRADE MANAGEMENT
Inp_Use_BE = true                         // Enable breakeven
Inp_BE_Trig = 0.8                         // Trigger at 0.8× ATR
Inp_BE_Buff = 0.05                        // Small buffer
Inp_TrailMode = TRAIL_ATR                 // ATR trailing

// FILTERS
InpMaxSpreadPips = 5.0                    // Higher tolerance
InpMinATRPips = 3.0                       // Lower minimum
InpMaxATRPips = 100.0                     // Higher maximum
```

**Expected Results:**
- Win rate: 45-50%
- Trades per month: 30-80 (varies by timeframe)
- Earlier entries, more opportunities
- Higher drawdown potential

---

### "Let Profit Run" Setup

```mql5
// Standard bias and voting configuration...
// (use Conservative or Aggressive settings above)

// MODIFIED TRADE MANAGEMENT
Inp_TP_Mult = 0.0                         // DISABLE fixed TP
Inp_TrailMode = TRAIL_PSAR                // PSAR trailing
Inp_Trail_Mult = 3.0                      // 3× ATR distance
Inp_Use_BE = true                         // Breakeven protection
Inp_BE_Trig = 1.0                         // Trigger at 1× ATR
Inp_CloseOnReverse = false                // Don't close on reverse
```

**Strategy:** Let winners run until PSAR flips, protect with breakeven

---

### Important Configuration Notes

**Trade Count Varies by Timeframe:**
- Markets are fractal - same patterns on different scales
- **M5/M15:** 50-200 signals/month (more noise)
- **H1:** 20-50 signals/month (balanced)
- **H4/D1:** 5-20 signals/month (clean trends)

**Win Rate Depends on Filtering:**
- More filters + higher threshold = Higher win rate, fewer trades
- Fewer filters + lower threshold = Lower win rate, more trades

**Never assume fixed numbers** - adapt to market conditions and timeframe

---

## Installation

### Step 1: Copy Files

Copy files to your MT5 data folder:

```
MQL5/Experts/  → SimpleEA_v1-02-016d_05-9_RRM.mq5

MQL5/Include/  → SEA_SignalEngine.mqh
               → SEA_TradeExecutor.mqh
               → SEA_Reporting.mqh
               → SEA_UI.mqh
```

### Step 2: File Encoding (CRITICAL)

**All `.mq5`, `.mqh`, and `.json` files MUST be saved as UTF-16 LE with BOM**

Verify encoding (macOS/Linux):
```bash
file SimpleEA_v1-02-016d_05-9_RRM.mq5
# Should show: charset=utf-16le
# First bytes should be: FF FE (BOM)
```

If wrong encoding, the EA will fail to compile!

### Step 3: Compile

1. Open `SimpleEA_v1-02-016d_05-9_RRM.mq5` in MetaEditor
2. Press F7 or click "Compile"
3. Verify no errors in the Toolbox

### Step 4: Attach to Chart or Strategy Tester

**Live/Demo Chart:**
1. Drag EA onto chart
2. Configure inputs (see Configuration Guide)
3. Enable visualization:
   - `Inp_UI_ShowStatusPanel = true`
   - `Inp_UI_ShowCockpitPanel = true`
4. Click OK

**Strategy Tester:**
1. Select EA in tester
2. Choose symbol and timeframe
3. Configure parameters
4. Click Start

---

## Strategy Tester Usage

### Important Notes

**macOS + Wine Users:**
- Use **Stop → Start** after changing inputs (not just Restart)
- "Restart" may not reload new parameters properly

**Diagnostics:**
- Enable `Inp_PrintEffectiveConfig=true` to see actual settings
- Check Expert log for vote details and rejection reasons

---

### Understanding Test Results

#### Vote Logging Example

```
VOTE_DETAIL[2026.02.15 10:00]: bias=1 v_shift=1 votes=4/4
  | EMA1: p=1.08550 e=1.08420 PASS
  | MACD: main=0.00157 sig=0.00124 PASS
  | CCI: 152.3 PASS
  | PSAR: sar=1.08100 cl=1.08600 PASS
```

This shows:
- Bar time: 2026.02.15 10:00
- Bias: 1 (LONG)
- Evaluated at: shift=1
- Votes: 4 out of 4 required
- Each indicator's values and pass/fail

#### Rejection Reasons

| Reason | Meaning |
|--------|---------|
| `SPREAD` | Spread too high |
| `MIN_ATR` | Volatility too low |
| `MAX_ATR` | Volatility too high |
| `TIME` | Outside trading hours |
| `BIAS_ZERO` | No clear trend |
| `HTF_VETO` | Higher timeframe disagrees |
| `RRM_PULLBACK` | Pullback gate not satisfied |
| `RRM_EMA_DIV` | EMA divergence gate not satisfied |
| `VOTES 3/4` | Insufficient indicator votes (example: 3 out of 4) |

---

### CSV Export (Optional)

Enable comprehensive reporting:

```mql5
Inp_ExportCSV = true
Inp_ExportUseCommonFiles = false  // Keep false for macOS+Wine
```

**Report includes:**
- Configuration snapshot
- Performance metrics
- Risk & drawdown statistics
- Win rate & trade counts
- Deal-by-deal history

**File location:** `MT5/Tester/Agent-xxx/Files/`

---

## Additional Documentation

### Technical Deep Dive

**[README_INDICATORS.md](README_INDICATORS.md)** — Complete technical documentation including:
- Detailed 9-step pipeline walkthrough with examples
- Multiplicative voting system mathematics
- Complete execution trace (real-world example)
- Individual indicator voting logic and parameters
- RRM Gates implementation details
- HTF Filter calculations

### Historical/Development Files (Reference Only)

Files in `Readme/` subfolder are for development reference:
- `Readme/README_SimpleEA_v1-01.md`
- `Readme/README_v1-02-014e1.md`
- `Readme/_sea_optimization_results_*.md`

These are not needed for normal usage.

---

## System Requirements

- **Platform:** MetaTrader 5 (build 3650+)
- **Operating System:** 
  - Windows (native)
  - macOS (via Wine)
- **Encoding:** UTF-16 LE with BOM for all source files
- **Minimum Account:** $500+ recommended (for proper risk management)

---

## Version Information

**Current Version:** v1.02.016d-05-9_RRM  
**Build Number:** 1020168  
**Status:** Production Ready

**Key Features:**
- 9-step signal validation pipeline
- Dual-shift support (horizontal + vertical)
- RRM trend pullback/reclaim logic
- Multiple trailing stop modes (ATR, PSAR, Fractal)
- MaxATR upper volatility bound
- Comprehensive diagnostics and logging

---

## License

Copyright © 2026 - RRM SEA Trading System

---

## Support

**Repository:** [msmaciej/RRM_SEA](https://github.com/msmaciej/RRM_SEA)

For questions about the system logic, refer to the detailed walkthrough sections above.

---

## Risk Disclaimer

**Trading forex and CFDs involves substantial risk of loss.** This EA is provided for educational and research purposes. Past performance does not guarantee future results. Always test thoroughly in demo/backtest environments before live deployment.

**Remember: This system trades quality over quantity. Fewer signals, but higher probability of success.**

---

## Quick Reference Card

### Essential Pre-Flight Checks

✅ Files saved as UTF-16 LE with BOM  
✅ All `.mqh` files in `MQL5/Include/`  
✅ Selected appropriate configuration (Conservative/Aggressive)  
✅ Risk% set appropriately (1.5-2.0%)  
✅ `Inp_PrintEffectiveConfig=true` for diagnostics

### Minimum Viable Configuration

```mql5
InpPreset = PRESET_RRM              // Start with RRM preset
InpRiskPercent = 1.5                // Conservative risk
Inp_VoteThreshold = 4               // Strict filtering
Inp_SL_Mult = 2.0                   // 2× ATR stop
Inp_TP_Mult = 0.0                   // Let profit run
Inp_TrailMode = TRAIL_PSAR          // PSAR trailing
Inp_Use_BE = true                   // Breakeven protection
```

### Key Metrics to Monitor

- **Win Rate:** Varies by configuration (45-60%)
- **Profit Factor:** Target > 1.2
- **Max Drawdown:** Target < 20%
- **Sharpe Ratio:** Target > 0.5
- **Trade Frequency:** Varies significantly by timeframe

**Note:** Performance metrics vary by configuration, timeframe, and market conditions. There are no "fixed" expected results.

---

**End of README**
