# SimpleEA v1.02.012n - Dual-Shift Elastic Voting EA (MT5)

**Code version:** 1.02.012n (`SimpleEA_v1-02-012n.mq5`, `#property version "102.012"`)  
**Platform:** MetaTrader 5 (MQL5)

SimpleEA is a modular Expert Advisor designed to benchmark (and then improve on) MT5's classic Moving Average stop-and-reverse behavior by adding optional filters, a confluence voting layer, and exit management.

## Core execution flow

The EA runs once per new bar (new-bar gating in `OnTick()`), in this order:

1. Compute ATR (previous closed bar) for volatility and exit calculations.
2. Manage an existing position (breakeven and trailing) using the current ATR snapshot.
3. Build a signal direction via the Signal Engine:
   - apply global filters (time window, spread, minimum ATR)
   - determine bias (manual or auto)
   - apply optional HTF EMA slope veto
   - if `VoteThreshold > 1`, run voting and require minimum votes
4. Pass the final direction to the Trade Executor:
   - hold if already in that direction
   - optionally stop-and-reverse if enabled
   - open a new position with ATR-based SL/TP if configured


## Project structure

This EA is split into an orchestrator and two services:

- `SimpleEA_v1-02-012n.mq5` - inputs, preset mapping, orchestration, Strategy Tester report export.
- `SEA_SignalEngine.mqh` - indicator handles, filters, bias determination, voting.
- `SEA_TradeExecutor.mqh` - position lookup, stop-and-reverse, order placement, breakeven, trailing.

The main EA includes the services via:

- `#include <RRMS\SEA_TradeExecutor.mqh>`
- `#include <RRMS\SEA_SignalEngine.mqh>`

### File encoding note

The shipped `.mq5/.mqh` sources are intended to be saved as **UTF-16 LE with BOM** (see the headers in the code). If you keep UTF-8 copies for review, ensure that the copies placed under `MQL5\Experts` and `MQL5\Include\RRMS` are UTF-16 LE with BOM so MetaEditor compiles them as expected.

## Execution model

- **New-bar execution only:** `OnTick()` runs signal generation once per new bar. Trade management (breakeven/trailing) is also updated once per bar.
- **Single-position model per symbol+magic:** the executor manages only one position for the current symbol and the configured magic number.
- **One ATR snapshot per bar:** ATR is read from the previous closed bar (`shift=1`) and reused for that bar's management and entry SL/TP calculations.


## Inputs overview

Inputs are grouped in the EA properties window.

### How to use presets (quick guide)

- **`InpPreset` is the master switch.** It determines which settings are *actually used* by the EA.
- **Use `PRESET_CUSTOM` when you want to tune parameters manually.** In this mode, the EA primarily uses the inputs in the `CUSTOM` groups (for example, `=== 5. CUSTOM: INDICATORS ===`).
- **Use any non-custom preset when you want a preconfigured behavior.** Presets set (and may force) key values internally in `ApplySettings()` to keep a coherent configuration. Inputs that contradict the preset may be **ignored**.
- **`PRESET_MA_BENCHMARK` (MT5 MovingAverage compatibility):** the EA uses only the `=== 0c. BENCHMARK: MT5 MOVING AVERAGE ===` inputs for MA period/shift and MA-style sizing, and **ignores** the `CUSTOM` MA controls (group 5). The on-chart status panel and the Experts log explicitly show what is used vs ignored.
- **Applying changes:** MT5 inputs are applied only on initialization. After changing inputs, click **OK** (chart) or **Stop → Start** (Strategy Tester) to reinitialize the EA with the new values.


### 0) Master preset

- `Inp_MagicNum` - unique magic number used to identify positions opened by this EA instance.
- `InpPreset` - one-click preset selection:
  - `PRESET_CUSTOM`
  - `PRESET_TREND_REVERSAL` (benchmark stop-and-reverse)
  - `PRESET_TREND_SCALP` (higher confluence trend continuation)
  - `PRESET_RANGE_GRID` (conservative mean-reversion-style configuration)

Presets override many settings in `ApplySettings()`. Bias configuration is still driven by the Bias settings below unless the preset explicitly forces a value (notably Trend Reversal).

### 1) Custom: logic and risk gates

- `Inp_CloseOnReverse` - if true, an opposing signal will close the current position before opening the new direction.
- `Inp_RiskPercent` - risk-based position sizing (percent of equity) when an SL is configured (i.e., `Inp_SL_Mult > 0`). Volume is calculated from SL distance using symbol tick size/value and normalized to broker min/max/step.
- `Inp_MaxSpreadPips` - spread veto.
- `Inp_MinATRPips` - minimum volatility veto (ATR in pips).

### 2) Custom: market bias

- `Inp_BiasMode` - `BIAS_AUTO` or `BIAS_MANUAL`.
- `Inp_EmaStrategy` - easy strategy mapping:
  - `EMA_STRAT_1_PRICE_CROSS` - price vs EMA1 (benchmark mode)
  - `EMA_STRAT_2_CROSS_1_2` - EMA1 vs EMA2
  - `EMA_STRAT_2_CROSS_3_4` - EMA3 vs EMA4
  - `EMA_STRAT_CUSTOM` - use the Advanced Bias inputs
- `Inp_BarShift` - vertical/bar shift:
  - `0` = evaluate the current forming bar
  - `1` = evaluate the last closed bar

### 2a) Advanced bias (used when `Inp_EmaStrategy = EMA_STRAT_CUSTOM`)

- `Inp_ManualSide` - `SIDE_LONG`, `SIDE_SHORT`, or `SIDE_BOTH`.
- `Inp_AutoStrat_Adv` - `STRAT_SINGLE_SLOPE`, `STRAT_PAIR_CROSS`, or `STRAT_PRICE_CROSS`.
- `Inp_BiasFast_Adv` and `Inp_BiasSlow_Adv` - which EMA slot(s) act as fast/slow.

### 3) Filters

- `Inp_UseTime`, `Inp_StartHour`, `Inp_EndHour` - hour-of-day trading window (server time). Overnight windows are supported.
- `Inp_UseHTF`, `Inp_HtfPeriod`, `Inp_HtfEmaPeriod` - Higher Timeframe EMA slope veto.
- `Inp_UseNews`, `Inp_NewsFile`, `Inp_NewsPre`, `Inp_NewsPost` - CSV news blackout: blocks *new entries* from `NewsPre` minutes before to `NewsPost` minutes after matching events for the symbol’s base/quote currencies (CSV columns: `Date,Event,Impact,Currency`).

### 4) Voting

- `Inp_VoteThreshold` - minimum number of votes required. If `<= 1`, voting is bypassed and the EA trades purely on bias (after filters and HTF veto).

### 5) Indicators

- `Inp_MaType` - `METHOD_EMA` or `METHOD_SMA` (applied to all EMA slots and the HTF filter).
- `Inp_MaHorzShift` - horizontal shift passed into `iMA()` handles (benchmarking support).
- Periods/modes for ADX, MACD, RSI, CCI, MFI, Stochastic, Bollinger Bands, and PSAR.

### 6) Active votes

Enable/disable each vote source:

`Inp_Use_EmaSig`, `Inp_Use_Adx`, `Inp_Use_Macd`, `Inp_Use_Rsi`, `Inp_Use_Cci`, `Inp_Use_Mfi`, `Inp_Use_Sto`, `Inp_Use_Bb`, `Inp_Use_Psar`, `Inp_Use_P123`, `Inp_Use_Ross`.

### 7) Exit and reporting

- `Inp_SL_Mult`, `Inp_TP_Mult` - ATR-based SL/TP multipliers (0 disables placement).
- `Inp_Use_BE`, `Inp_BE_Trig`, `Inp_BE_Buff` - ATR-based breakeven.
- `Inp_TrailMode`, `Inp_Trail_Mult` - trailing logic (ATR and Fractal are implemented; PSAR trailing is not).
- `Inp_ExportCSV` - export Strategy Tester report on shutdown.


## Presets (what they actually change)

Presets are applied inside `ApplySettings()` after loading your custom inputs.

Important behavior:

- Presets override many settings (vote threshold, enabled votes, exit options, and some filters).
- Unless a preset explicitly forces a bias strategy, the bias mapping still comes from your `Inp_EmaStrategy` / manual bias selection.

### PRESET_TREND_REVERSAL (Benchmark)

Designed to mimic a traditional moving-average stop-and-reverse system.

- `CloseOnReverse = true`
- Forces `AutoStrat = STRAT_PRICE_CROSS` using EMA1 as the reference (`BiasFastID = 0`)
- `VoteThreshold = 1` (bias-only)
- Filters off (time, news, HTF)
- SL/TP multipliers set to 0 (no broker-side SL/TP)
- Breakeven and trailing disabled

### PRESET_TREND_SCALP (Sniper)

Higher-confluence trend continuation setup.

- `CloseOnReverse = false`
- `VoteThreshold = 3`
- Enabled votes: EMA recovery, ADX, MACD
- `SL_Mult = 1.5`, `TP_Mult = 3.0`
- Breakeven enabled
- `TrailMode = TRAIL_ATR`

Note: this preset does not force a bias strategy; it uses whatever bias configuration you have selected (unless you change it).

### PRESET_RANGE_GRID (Conservative)

Conservative range/mean-reversion configuration (despite the legacy preset name).

- `CloseOnReverse = false`
- `VoteThreshold = 4`
- Enables time filter, news hook, and HTF filter
- Enables votes: RSI (forced to `RSI_FILTER_EXTREME`), Stochastic, Bollinger (forced to `BB_MEAN_REVERSION`)
- `SL_Mult = 2.0`, `TP_Mult = 2.0`
- Trailing disabled


## Benchmark sync guide (MT5 "Moving Average" EA)

The dual-shift implementation is specifically intended to let you replicate the timing style of MT5's built-in Moving Average EA, and then add filters/exits.

A typical "sync" configuration is:

- `Inp_MaType = METHOD_SMA`
- `Inp_EmaStrategy = EMA_STRAT_1_PRICE_CROSS`
- `Inp_BarShift = 0` (aggressive: current bar) or `1` (confirmed: previous closed bar)
- `Inp_MaHorzShift` = match the MA indicator shift you want to benchmark
- `Inp_CloseOnReverse = true`
- `Inp_VoteThreshold = 1`
- `Inp_SL_Mult = 0`, `Inp_TP_Mult = 0`

Then enable improvements one at a time, for example:

- Raise `Inp_VoteThreshold` and enable one vote (ADX or MACD) to reduce noise.
- Enable HTF veto to avoid trading against higher-timeframe slope.
- Use `TRAIL_ATR` to hold winners longer than stop-and-reverse.

## Installation

1. Copy `SimpleEA_v1-02-012n.mq5` into `MQL5\Experts\`.
2. Copy the include modules into `MQL5\Include\RRMS\`:
   - `SEA_SignalEngine.mqh`
   - `SEA_TradeExecutor.mqh`
3. If you enable `Inp_UseNews`, place `calendar_statement.csv` into `MQL5\Files\` (see limitations below).
4. Compile in MetaEditor and attach the EA to a chart.

## Strategy Tester CSV report

If `Inp_ExportCSV = true`, the EA writes a CSV report on shutdown when running in the Strategy Tester (`MQL_TESTER` must be true).

Report contents:

- Test configuration (preset, EMA strategy, vote threshold)
- Key statistics (net profit, profit factor, expected payoff, Sharpe, recovery factor)
- Drawdown metrics
- Deal history (time, type, volume, price, profit, running balance)

The report is created with a name like:

`Report_SimpleEA_<SYMBOL>_<PERIOD>_<STARTDATE>_<ENDDATE>.csv`

## Known limitations (as coded in v1.02.012n)

These items are present in inputs/settings but are not fully implemented in this code version:

- **BiasEnabled switch:** `Inp_BiasEnabled` is stored in settings, but the signal engine does not currently enforce it.
- **Trailing modes:** only `TRAIL_ATR` and `TRAIL_FRACTAL` are implemented. `TRAIL_PSAR` exists as an enum option but is not implemented.

Additional behavior notes (relevant for configuration and expectations):

- **Risk sizing requires an SL price:** risk-based volume requires a configured stop (`Inp_SL_Mult > 0`). If SL is disabled or symbol tick properties are unavailable, the executor falls back to the symbol’s minimum volume.
- **Instrument coverage (FX + metals):** lot sizing is based on `SYMBOL_TRADE_TICK_SIZE` and `SYMBOL_TRADE_TICK_VALUE_LOSS` (fallback: `SYMBOL_TRADE_TICK_VALUE`), so it is designed to work for 5-digit FX, JPY pairs, and XAU/XAG CFDs. Correctness depends on broker-provided symbol properties.
- **News filter scope:** the news blackout blocks *entries only*; it does not force-close existing positions. Impact handling is conservative: explicit “Low” events are ignored; anything else is treated as relevant.
- **ATR period is fixed at 14** in the signal engine (`iATR(..., 14)`), and ATR is read from the previous closed bar (`shift=1`).
- **Spread limit is pip-assumed:** spread is computed in points and compared to `MaxSpreadPips * 10`. This matches 5-digit / 3-digit FX conventions, but can be inaccurate on symbols where 1 pip is not 10 points.
- **Time filter uses broker server time** (`TimeCurrent()` hour), not local time.

## Detailed logic reference

See `README_INDICATORS_SimpleEA_v1-02.md` for the exact rules used for bias, filters, voting checks, and trailing.
