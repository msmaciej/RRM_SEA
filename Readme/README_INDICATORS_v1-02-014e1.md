# SimpleEA v1.02 (014e1) - Indicator, Filter, and Mode Reference

This document describes the implemented logic for each filter, bias mode, voting check, and exit helper in **SimpleEA v1.02 (014e1)**.

The EA is structured as:

1. Hard filters (trade veto)
2. Bias (direction selection)
3. Voting (optional confluence)
4. Execution and exit management

## Preset precedence (Benchmark vs Custom MA controls)

SimpleEA exposes both **Benchmark** and **Custom** MA controls in the Inputs dialog because MT5 does not support conditionally hiding inputs. Only one set is active at a time:

- If `InpPreset = PRESET_MA_BENCHMARK`:
  - Uses benchmark inputs: `Inp_MA_MaximumRiskPct`, `Inp_MA_DecreaseFactor`, `Inp_MA_Period`, `Inp_MA_Shift`.
  - Ignores custom MA inputs: `Inp_MaType`, `Inp_MaHorShift`, `Inp_MaVerShift`.
  - Bias uses **confirmed price/MA cross** on closed bars (shifts 1 and 2), and the executor uses benchmark-style sizing.
- Otherwise (`PRESET_CUSTOM`, `PRESET_TREND_REVERSAL`, etc.):
  - Uses custom MA inputs (`Inp_MaType`, `Inp_MaHorShift`, `Inp_MaVerShift`) and the standard risk inputs.
  - Benchmark inputs are ignored.

## 0) Timing and MA parameters

### Vertical/bar shift (`Inp_BarShift`)
The bar index used for most price/indicator reads inside the Signal Engine.

- `0` - aggressive: evaluate the current forming bar
- `1` - confirmed: evaluate the last closed bar

Note (benchmark preset): when `InpPreset = PRESET_MA_BENCHMARK`, SimpleEA intentionally uses a **closed-bar confirmed cross** for price/MA decisions (compares shifts 1 and 2). In that preset, `Inp_BarShift` is not used to “move” the cross logic onto the current bar.

This same setting is also used in the Trade Executor to optionally restrict entries to once per bar when `Inp_BarShift = 1` (redundant in this build because the EA already runs on new-bar gating, but it remains in the code).

### Horizontal MA shift (`Inp_MaHorShift`)
Passed into `iMA()` as the MA's built-in shift parameter for all EMA slots and the HTF filter.

Effect: shifts the MA line left/right in time, which is useful for matching the MT5 benchmark behavior.

Note (benchmark preset): when `InpPreset = PRESET_MA_BENCHMARK`, the EA uses `Inp_MA_Shift` (benchmark input) and maps it to the internal MA horizontal shift. The custom `Inp_MaHorShift` is ignored in that preset.

### MA method (`Inp_MaType`)
Applied to all `iMA()` handles (EMA slots and HTF filter):

- `METHOD_EMA` - exponential moving average (`MODE_EMA`)
- `METHOD_SMA` - simple moving average (`MODE_SMA`)

### ATR (volatility reference)
ATR is created as `iATR(Symbol, PERIOD_CURRENT, 14)` and read from the previous closed bar (`shift=1`).

- Used by the hard volatility filter (`Inp_MinATRPips`)
- Used for SL/TP distance, breakeven thresholds, and ATR trailing

## 1) Hard filters (trade veto)

Hard filters are evaluated first. If any filter fails, the Signal Engine returns `0` (no trade).

### 1.1 Time window filter (`Inp_UseTime`, `Inp_StartHour`, `Inp_EndHour`)

If enabled, the EA allows trading only when the broker server hour (`TimeCurrent()`) is inside the configured window.

- If `StartHour < EndHour`: pass when `hour >= StartHour AND hour < EndHour`
- If the window wraps midnight (`StartHour > EndHour`): pass when `hour >= StartHour OR hour < EndHour`

### 1.2 Spread ceiling (`Inp_MaxSpreadPips`)

Spread is computed in points:

`spread_points = (Ask - Bid) / _Point`

Trade is blocked when:

`spread_points > (Inp_MaxSpreadPips * 10.0)`

Notes:

- The `* 10` conversion matches the 5-digit / 3-digit FX convention (1 pip = 10 points).
- On symbols where 1 pip is not 10 points, this threshold will be inaccurate.

### 1.3 Minimum volatility (`Inp_MinATRPips`)

ATR is converted to points and treated as "pips" for the threshold:

`atr_pips = ATR / _Point`

Trade is blocked when:

`atr_pips < Inp_MinATRPips`

### 1.4 News filter (CSV blackout) (`Inp_UseNews`, `Inp_NewsFile`, `Inp_NewsPre`, `Inp_NewsPost`)

When enabled, the EA blocks **new entries** in a time window around scheduled events loaded from a CSV file.

Implementation details (as coded in `CSignalEngine::LoadNews()` and `CSignalEngine::CheckFilters()`):

- The EA loads the CSV in `OnInit()` via `Signal.LoadNews(Inp_NewsFile)`.
- The loader attempts to read the file as **UTF-8** first and falls back to **ANSI**.
- Expected CSV layout (4 columns, with a header row):
  1. `Date`
  2. `Event` (ignored by the filter)
  3. `Impact`
  4. `Currency`
- The `Date` field is parsed in the specific `calendar_statement.csv` format:

  `"YYYY, Month DD, HH:MI"`  (example: `"2026, January 12, 09:00"`)

- A row is considered relevant if `Currency` matches **either** the base or quote currency of the current symbol (e.g., `EURUSD` matches `EUR` and `USD`).
- Rows whose impact begins with `Low` are ignored.
- Entry is blocked when the current server time is inside the configured window:

  `TimeCurrent() ∈ [event_time - Inp_NewsPre minutes, event_time + Inp_NewsPost minutes]`

Notes:

- This is an **entry blackout** only; it does not force-close existing positions.
- If the CSV file is missing/unreadable, the EA prints a message and continues with news filtering effectively disabled.

## 2) Bias engine (direction selection)

Bias returns one of:

- `+1` - long
- `-1` - short
- `0` - neutral (no trade)

Bias is computed after hard filters pass.

### 2.1 Manual bias (`Inp_BiasMode = BIAS_MANUAL`)

- `Inp_ManualSide = SIDE_LONG`  -> bias = `+1`
- `Inp_ManualSide = SIDE_SHORT` -> bias = `-1`
- `Inp_ManualSide = SIDE_BOTH`  -> fallback to slope of EMA4 (see note below)

Slope is computed as:

- compare EMA value at `shift=1` vs `shift=2`
- slope up -> `+1`, slope down -> `-1`, flat -> `0`

Note: this slope uses closed bars and does not use `Inp_BarShift`.

### 2.2 Auto bias (easy setup) (`Inp_BiasMode = BIAS_AUTO` and `Inp_EmaStrategy`)

`Inp_EmaStrategy` maps into an internal auto strategy and EMA slot selection:

- `EMA_STRAT_1_PRICE_CROSS`  -> `STRAT_PRICE_CROSS` using EMA1
- `EMA_STRAT_2_CROSS_1_2`    -> `STRAT_PAIR_CROSS` using EMA1 vs EMA2
- `EMA_STRAT_2_CROSS_3_4`    -> `STRAT_PAIR_CROSS` using EMA3 vs EMA4
- `EMA_STRAT_CUSTOM`         -> use the advanced bias inputs below

By default, price/MA comparisons for bias use the vertical shift:

- price = `Close[Inp_BarShift]`
- MA values = `MA[Inp_BarShift]`

Confirmed cross mode: when the active Settings enable **RequirePriceCross** (notably in `PRESET_MA_BENCHMARK` and in preset configurations that explicitly reduce churn), the signal is generated only on a **true cross** between two consecutive closed bars:

- Bullish cross: `Close[1] > MA[1]` and `Close[2] <= MA[2]`
- Bearish cross: `Close[1] < MA[1]` and `Close[2] >= MA[2]`

In this cross-confirm mode the decision uses shifts 1 and 2 and does not depend on `Inp_BarShift`.

### 2.3 Advanced auto bias (used when `Inp_EmaStrategy = EMA_STRAT_CUSTOM`)

`Inp_AutoStrat_Adv` selects one of:

- `STRAT_SINGLE_SLOPE`: bias = slope of the selected fast EMA slot (slope uses `shift=1` vs `shift=2`)
- `STRAT_PRICE_CROSS`: by default this is a state decision (`Close[v_shift] > EMA_fast[v_shift] ? +1 : -1`). When RequirePriceCross is enabled, this becomes the confirmed cross logic described above (uses shifts 1 and 2).
- `STRAT_PAIR_CROSS`: bias = `EMA_fast[v_shift] > EMA_slow[v_shift] ? +1 : -1` (or 0 if equal)

`Inp_BiasFast_Adv` and `Inp_BiasSlow_Adv` choose which EMA slots are considered fast/slow.

### 2.4 HTF EMA veto (`Inp_UseHTF`, `Inp_HtfPeriod`, `Inp_HtfEmaPeriod`)

If enabled, the EA computes the slope of the HTF EMA using closed bars on the HTF:

- `htf_dir = (EMA[1] > EMA[2]) ? +1 : -1`

A trade is allowed only when:

- `bias == htf_dir`

Note: this veto uses HTF shifts 1 and 2 and does not use `Inp_BarShift`.

## 3) Voting framework

Voting is applied only when `Inp_VoteThreshold > 1`.

- If `Inp_VoteThreshold <= 1`, voting is bypassed and the EA trades purely on bias (after hard filters and HTF veto).
- If `Inp_VoteThreshold > 1`, each enabled vote that returns `true` increments a vote counter; a trade is allowed when `votes >= Inp_VoteThreshold`.

All voting checks use the vertical shift `v_shift = Inp_BarShift`.

## 4) Voting checks (as implemented)

### Vote 1 - EMA recovery (`Inp_Use_EmaSig`)

Price relative to EMA1:

- Buy: `Close[v_shift] > EMA1[v_shift]`
- Sell: `Close[v_shift] < EMA1[v_shift]`

### Vote 2 - ADX strength (`Inp_Use_Adx`)

Directionless strength gate:

- Pass when `ADX[v_shift] > T_Adx`

### Vote 3 - MACD (`Inp_Use_Macd`)

Two modes:

- `MACD_SIGNAL_ALIGN`: Buy if `MACD_main > MACD_signal`; Sell if `MACD_main < MACD_signal`
- `MACD_ZERO_CROSS`: Buy if `MACD_main > 0`; Sell if `MACD_main < 0`

### Vote 4 - RSI (`Inp_Use_Rsi`)

Three modes:

- `RSI_FILTER_EXTREME`:
  - Buy if `RSI < T_RsiOB` (not overbought)
  - Sell if `RSI > T_RsiOS` (not oversold)
- `RSI_TREND_ABOVE_50`:
  - Buy if `RSI > 50`
  - Sell if `RSI < 50`
- `RSI_CROSS_LEVEL`:
  - Buy if `RSI > T_RsiOS`
  - Sell if `RSI < T_RsiOB`

### Vote 5 - CCI (`Inp_Use_Cci`)

Two modes:

- `CCI_TREND_ZERO`: Buy if `CCI > 0`; Sell if `CCI < 0`
- `CCI_IMPULSE_100`: Buy if `CCI > 100`; Sell if `CCI < -100`

### Vote 6 - MFI (`Inp_Use_Mfi`)

- Buy if `MFI > T_Mfi`
- Sell if `MFI < (100 - T_Mfi)`

### Vote 7 - Stochastic (`Inp_Use_Sto`)

Two modes:

- `STO_CROSS_SIGNAL`: Buy if `%K > %D`; Sell if `%K < %D`
- `STO_ZONE_FILTER`: Buy if `%K < 80`; Sell if `%K > 20`

### Vote 8 - Bollinger Bands (`Inp_Use_Bb`)

Two modes:

- `BB_TREND_FOLLOW`:
  - Buy if `Close > MiddleBand`
  - Sell if `Close < MiddleBand`
- `BB_MEAN_REVERSION`:
  - Buy if `Low <= LowerBand`
  - Sell if `High >= UpperBand`

### Vote 9 - PSAR (`Inp_Use_Psar`)

- Buy if `Close > PSAR`
- Sell if `Close < PSAR`

### Vote 10 - P123 fractal breakout (`Inp_Use_P123`)

Implementation note: this is a simplified fractal breakout vote (not a multi-swing state machine).

- The engine searches from bar 2 onward to find the most recent confirmed fractal high and low.
- Buy vote if `Close[v_shift]` breaks above the most recent upper fractal.
- Sell vote if `Close[v_shift]` breaks below the most recent lower fractal.

### Vote 11 - Ross Hook interlock (`Inp_Use_Ross`)

Ross Hook is implemented as a two-condition interlock:

1. The same fractal breakout as Vote 10 must be true.
2. The selected "lead" EMA slot (`BiasFastID`) must have its slope aligned with the trade direction.

Slope is computed on the lead EMA as:

- `EMA_lead[shift]` vs `EMA_lead[shift + 1]` (note: this uses `v_shift` and `v_shift + 1`)

The vote passes when breakout is true and the lead slope matches the bias.

## 5) Execution and exit management

### 5.1 Stop-and-reverse (`Inp_CloseOnReverse`)

If a position is open and the signal flips:

- if `Inp_CloseOnReverse = true`, the EA closes the existing position and opens the new one
- if `Inp_CloseOnReverse = false`, the EA holds the existing position and ignores the opposing signal

### 5.2 SL/TP placement (`Inp_SL_Mult`, `Inp_TP_Mult`)

At entry, SL/TP are placed using ATR multipliers:

- SL distance = `ATR * SL_Mult` (0 disables SL)
- TP distance = `ATR * TP_Mult` (0 disables TP)

### 5.3 Breakeven (`Inp_Use_BE`, `Inp_BE_Trig`, `Inp_BE_Buff`)

ATR-based breakeven logic:

- For buys: when `Price >= Open + ATR * BE_Trig`, set `SL = Open + ATR * BE_Buff` if that improves SL.
- For sells: when `Price <= Open - ATR * BE_Trig`, set `SL = Open - ATR * BE_Buff` if that improves SL.

### 5.4 Trailing (`Inp_TrailMode`, `Inp_Trail_Mult`)

Implemented modes:

- `TRAIL_NONE`: no trailing
- `TRAIL_ATR`: trail by `ATR * Trail_Mult` using current Bid/Ask
- `TRAIL_FRACTAL`: trail to the most recent confirmed swing fractal (buy: last lower fractal; sell: last upper fractal)

Not implemented in this build:

- `TRAIL_PSAR` (enum exists, but no PSAR trailing logic is coded)

### 5.5 Position sizing

When `Inp_RiskPercent > 0` and a stop loss is configured (`Inp_SL_Mult > 0`), volume is calculated so that the **estimated loss at SL** is approximately the requested percentage of **account equity**.

Implementation summary:

1. Compute stop distance:
   - Buy: `stop_dist = entry_price - sl_price`
   - Sell: `stop_dist = sl_price - entry_price`

2. Convert stop distance to ticks:

   `ticks_to_sl = stop_dist / SYMBOL_TRADE_TICK_SIZE`

3. Estimate loss per 1 lot at SL:

   `loss_per_1_lot = ticks_to_sl * SYMBOL_TRADE_TICK_VALUE_LOSS`

4. Target loss:

   `target_loss = AccountEquity() * Inp_RiskPercent / 100`

5. Raw lot:

   `lot_raw = target_loss / loss_per_1_lot`

6. Normalize to broker constraints (`SYMBOL_VOLUME_MIN/MAX/STEP`) and round down to step.

If sizing cannot be computed (missing tick value/size, SL disabled, etc.), the executor falls back to the **symbol minimum volume** and prints a throttled warning. The final volume is also reduced if required to satisfy **free-margin** constraints (via `OrderCalcMargin`).
