# Portfolio Risk Layer — account-wide governor

**Status: IMPLEMENTED. Universal (all presets). Default OFF.**

This is the one genuinely *institutional* technique a retail EA can copy: managing risk at the
**account/basket level**, not per-chart. It is the highest-impact enhancement in SimpleEA that
isn't a signal — because trend-following's real edge is diversification, and diversification
without portfolio-level risk control is just hidden concentration.

## What it does

It is a **governor on top of the existing per-chart sizer** — it only ever scales a lot *down*
or *blocks* a trade; it never increases size. When `Portfolio_Enabled = false` (default) it is a
complete no-op: every preset and every past backtest is byte-identical. Turn it on per chart to
opt that chart into account-wide coordination.

Three components, applied in order to each new entry:

1. **Volatility-parity target** (`Portfolio_VolParity`). Because SL is ATR-based, equal-%-risk
   already normalises per-trade volatility; this caps each new trade to its fair share of the
   account budget (`MaxAccountRisk / TargetSlots`) so one slot cannot hog the book.
2. **Account risk budget** (`Portfolio_MaxAccountRisk`, default 6%). Summed open risk across
   **all** positions with this magic (every chart/symbol) plus the new trade may not exceed the
   cap. Over budget → the new lot is scaled to fit, or blocked if it would fall below the min lot.
3. **Correlation cap** (`Portfolio_MaxCurrencyRisk`, default 3%). Each currency leg of the new
   symbol (e.g. EURUSD → EUR and USD) has its net open risk summed across the book; a new trade
   cannot push any single currency past the cap. This is what stops "long EURUSD + long GBPUSD +
   long AUDUSD" from silently becoming one 3×-short-USD position.

On a block, the TE result is `BLOCKED / PORTFOLIO_RISK`.

## Why it's account-wide (and the caveat)

MT5 runs one EA instance per chart, but `PositionsTotal()` is **account-wide**, so each instance
*does* see positions opened by other charts carrying the same magic. That is what makes the
budget and correlation cap real rather than per-chart illusions.

> **Caveat — test in multi-symbol mode.** Cross-instance coordination depends on every chart
> sharing one magic and on the broker exposing all positions to each instance (true in live and
> in MT5's multi-symbol Strategy Tester, but single-symbol backtests see only their own trades).
> Validate basket behaviour in the multi-symbol tester before relying on the caps live.

## Inputs (universal, `Inp_Global_Portfolio_*`)

| Input | Default | Meaning |
|-------|---------|---------|
| `Portfolio_Enabled` | false | master switch (off = per-chart sizing, unchanged) |
| `Portfolio_MaxAccountRisk` | 6.0 | cap on total open risk across all charts, % equity |
| `Portfolio_MaxCurrencyRisk` | 3.0 | cap on net risk per currency (correlation cap), % |
| `Portfolio_TargetSlots` | 6 | intended basket size (vol-parity target = MaxAccountRisk/slots) |
| `Portfolio_VolParity` | false | scale new lot toward equal-risk-per-slot |

## How to use it (the institutional playbook, retail-sized)

1. Pick a **low-correlation basket** — one instrument per currency block plus a metal/index
   (e.g. EURUSD, USDJPY, AUDUSD, XAUUSD), not three USD pairs.
2. Run a trend preset (TURTLE or TREND) on each chart, **same magic**.
3. Enable the portfolio layer on each; set `MaxAccountRisk` to your true account ceiling and
   `TargetSlots` to the basket size.
4. The layer then keeps total and per-currency risk bounded no matter how many charts fire at
   once — the coordination that per-chart caps cannot provide.

## Honest limits

This closes the *portfolio-construction* part of the institutional gap — the part that actually
matters for smooth returns. It does **not** close the structural gaps (capital, market breadth,
execution infrastructure, data). It makes running a basket **safe and coordinated**; it does not
make the underlying strategy profitable. Trend-following still needs real trends, a genuinely
diversified basket, and the discipline to hold through drawdowns. Not investment advice; validate
by walk-forward and multi-symbol testing before any live use.
