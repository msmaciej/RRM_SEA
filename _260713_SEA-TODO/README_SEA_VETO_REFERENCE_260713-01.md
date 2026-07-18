# SimpleEA Veto Reference

This document lists all vetoes (trade rejection reasons), their configurability, and related inputs.

---

## Veto Categories

### 1. F Filter Vetoes (Execution-Moment Conditions)

| Veto Code | Description | User Control | Input Setting | Default |
|-----------|-------------|--------------|---------------|---------|
| `VETO_SPREAD` | Current spread exceeds limit | ✅ Fully configurable | `Inp_VETO_UseSpread`, `Inp_VETO_MaxSpread` | `false`, `3.0` |
| `VETO_SPREAD_TIMEOUT` | Spread blocked too many consecutive bars | ✅ Fully configurable | `Inp_VETO_MaxSpreadRetryBars` | `3` |
| `VETO_TIME` | Outside trading session window | ✅ Fully configurable | `Inp_Session_Enabled` (master on/off), `Inp_Session_London/NY/Asia` (named sessions), `Inp_Session_Win1/Win2` (custom windows) | London=true, NY=true, others=false |
| `VETO_NEWS` | Calendar event blackout active for this symbol | ✅ Fully configurable | `Inp_Global_VETO_UseNews`, `Inp_Global_VETO_NewsImpactFilter`, `Inp_Global_VETO_NewsPreMinutes`, `Inp_Global_VETO_NewsPostMinutes` | `true`, `NEWS_IMPACT_HIGH_ONLY`, `60`, `60` |

**Purpose**: Gate execution at shift=0 using real-time market conditions.

---

### 1a. News filter — source, scope, semantics (NEWS-AUDIT 2026-07)

**Source: MT5's native economic calendar** (`CalendarValueHistory` + `CalendarEventById`).
Event times are returned in **broker server time** — the same clock as `TimeCurrent()`. The filter
therefore contains **no timezone conversion and no DST handling anywhere**, by design.

> **The defect this replaced.** The filter previously parsed a CSV (`Inp_Global_VETO_NewsFile`,
> now removed). The exported myfxbook CSV is stamped in the **user's local clock** (UTC+2,
> Europe/Zurich) while `TimeCurrent()` runs on the **broker's** (UTC+3). Every blackout window sat
> exactly one hour early — **blocking the calm and trading the release**. Confirmed three ways:
> Market Watch 09:44 vs local 08:44; Fed Waller Speech 18:30 (CSV) → 19:30 (MT5 Calendar); US
> Federal Budget Balance 20:00 → 21:00. Zurich and the broker can also change DST on different
> dates, so the offset is not even constant. The native calendar removes the entire bug class.

> ⚠️ **The native calendar is UNAVAILABLE IN THE STRATEGY TESTER** (`FUNCTION_NOT_ALLOWED`, 4014).
> **In backtests this filter is INERT — the EA trades straight through news.** The EA prints a loud
> banner saying so at init. This is an accepted consequence of the native-only source architecture:
> live and backtest are, on this axis, *different systems*. Do not read a backtest as evidence about
> news-filter behaviour.

| Property | Behaviour |
|---|---|
| **Impact filtering** | `NEWS_IMPACT_HIGH_ONLY` blocks only `CALENDAR_IMPORTANCE_HIGH`, independently of MODERATE/LOW. `MED_PLUS` = MODERATE+HIGH. `ALL` = everything. Read from `MqlCalendarEvent.importance` — no string parsing. |
| **Symbol scoping** | By the symbol's **own currency legs**, via `SYMBOL_CURRENCY_BASE` / `SYMBOL_CURRENCY_PROFIT` (broker-canonical — immune to suffixes like `EURUSD.r` and to names like `GOLD`). A USD event blocks EURUSD, GBPUSD, USDJPY, NZDUSD, USDCAD. |
| **Metals** | `XAUUSD` / `XAGUSD` resolve to base `XAU`/`XAG`, profit `USD` → **driven by USD events**, exactly as required. XAU/XAG are not calendar currencies, so their own leg returns zero events; this is correct, not a failure. |
| **Pairs whose currency is quiet** | NZD and CAD had zero HIGH events in the reference week; NZDUSD/USDCAD are still blocked **via their USD leg**. |
| **Window** | `[t − NewsPre, t + NewsPost]`, minutes, **independently configurable**. |
| **Overlapping events** | **Merge automatically.** The check is an OR across events, so N simultaneous releases (e.g. the seven US prints on 16 July) produce **one continuous block**, not N competing ones. |
| **Scope of the block** | **New entries only.** `IsNewsBlocked()` is consulted from `EvaluateTE()` alone. `EvaluateTM()` — trailing stop, break-even, exits — never calls it, so **open positions stay fully managed throughout a blackout**. |
| **Refresh** | At init and once per bar, rate-limited to 1 request/min. A refresh that fails *on any currency leg* is **discarded whole** — a partial result would silently drop one currency's events while looking healthy. Stale-but-complete beats fresh-but-missing. |
| **On source failure** | **Fail-open + loud alert.** The EA keeps trading (an API outage must not silently kill a week) but logs `[NEWS] ⚠ … FILTER NOT PROTECTING THIS ACCOUNT` and raises a one-shot `Alert()`. |

**Verification at init:** `PrintNewsCalendarSummary()` dumps every event that *will* veto, with its
server time, so it can be checked against the terminal's Calendar tab before going live.


---

### 2. TE Quality Gates (Optional Signal Refinement)

| Veto Code | Description | User Control | Input Setting | Default |
|-----------|-------------|--------------|---------------|---------|
| `VETO_PSAR_STALE` | Latched TS=1 survived into a new bar and PSAR no longer supports the direction at shift=1 of the bar that just closed | ⚠️ Structural, not a dedicated toggle — active whenever `Ind_Psar_Enabled=true` (fires only for signals that outlive the bar they were emitted on; same-OnTick fresh signals always pass) | `Ind_Psar_Enabled` (gate), `Vote_AllowPsarFlip` (selects `Scanner_Check_PSAR_Flip` vs `Scanner_Check_PSAR` as the recheck voter) | `Ind_Psar_Enabled=true` in `PRESET_RRM_ORG` |
| `VETO_BC_STALE` | Live price drifted too far from `Close[1]` | ✅ Fully configurable | `Inp_VETO_TE_RecheckBarClose`, `Inp_VETO_TE_BC_TolerancePips` | `false`, `3.0` |
| `VETO_OPEN_DELAY` | Bar age is below configured delay | ✅ Fully configurable | `Inp_VETO_TE_OpenDelaySeconds` | `0` (off) |
| `VETO_SPREAD_MEDIAN` | Median spread filter rejected entry | ✅ Fully configurable | `Inp_VETO_TE_SpreadMedianTicks` | `0` (off) |

**Purpose**: Optional conservative gates layered on top of F filters. `VETO_PSAR_STALE` is evaluated first — before the F filters below — inside `EvaluateTE()`; the boolean is computed by the caller, `ConsumeLatchedSignalTE()` in `SimpleEA_v1-05.mq5`, and passed in as `psar_recheck_blocked`. It is a **permanent** veto for the bar (not in `IsTemporaryVeto()`), so a stale-PSAR rejection consumes the signal rather than retrying it.

---

### 3. RC Safeguards (Hardcoded Risk Protection)

| Veto Code | Description | User Control | Input Setting |
|-----------|-------------|--------------|---------------|
| `VETO_INVALID_LOTS` | Invalid lot sizing / SL preconditions | ❌ Cannot disable | N/A |
| `VETO_RC_MARGIN_LEVEL` | Projected margin level too low | ❌ Cannot disable | threshold uses margin settings |
| `VETO_RC_MAX_OPEN_TRADES` | Max concurrent trades reached | ⚠️ Threshold only | `Inp_RM_MaxOpenTrades` |
| `VETO_RC_MAX_TOTAL_RISK` | Portfolio risk cap exceeded | ⚠️ Threshold only | `Inp_RM_MaxTotalRisk` |
| `SAME_BAR_ENTRY` / `SAME_BAR_CLOSE` | Same-bar duplicate-entry safety guards | ❌ Cannot disable | N/A |

**Purpose**: Non-bypassable safety gates that protect account integrity.

---

## Veto Evaluation Flow

```text
TS=1 generated at shift=1 (bar close)
    ↓
shift=0 (bar open/ticks) → EvaluateTE()
    ↓
PHASE 0: PSAR staleness (only if signal is latched past its origin bar)
  • VETO_PSAR_STALE
    ↓ (if pass, or signal is fresh)
PHASE 1: F Filters
  • VETO_SPREAD / VETO_SPREAD_TIMEOUT
  • VETO_TIME
  • VETO_NEWS
    ↓ (if pass)
PHASE 2: TE Quality Gates (optional)
  • VETO_OPEN_DELAY
  • VETO_BC_STALE
  • VETO_SPREAD_MEDIAN
    ↓ (if pass)
PHASE 3: CM/RC Risk Gates
  • VETO_INVALID_LOTS
  • VETO_RC_* safeguards / thresholds
  • SAME_BAR_* execution guards
    ↓ (if pass)
TE=1 → trade executed
```

---

## Design Philosophy

- **OptionC baseline**: TS=1 at shift=1 is trusted at shift=0.
- **OptionB control**: user-configurable vetoes are exposed via `Inp_VETO_*` and `Inp_VETO_TE_*`.
- **Risk safeguards** remain always active and cannot be disabled.

---

## Backward Compatibility Note

Input names were standardized from `Inp_Filter_*` (spread/time/news) to `Inp_VETO_*` and TE gate controls were exposed under `Inp_VETO_TE_*`.
If you load older `.set` files, remap old keys as follows:

- `Inp_Filter_UseSpread` → `Inp_VETO_UseSpread`
- `Inp_Filter_MaxSpreadPips` → `Inp_VETO_MaxSpread`
- `Inp_Filter_MaxSpreadRetryBars` → `Inp_VETO_MaxSpreadRetryBars`
- `Inp_Filter_UseTime` → `Inp_VETO_UseTime`
- `Inp_Filter_StartHour` → `Inp_VETO_StartHr`
- `Inp_Filter_EndHour` → `Inp_VETO_EndHr`
- `Inp_Filter_UseNews` → `Inp_Global_VETO_UseNews`
- `Inp_Filter_NewsFile` → **REMOVED** (NEWS-AUDIT 2026-07 — the CSV source is gone; the native MT5 calendar has no file path). Old `.set` files carrying this key will simply have an unknown input; delete the line.
- `Inp_Filter_NewsPre` → `Inp_VETO_NewsPreMinutes`
- `Inp_Filter_NewsPost` → `Inp_VETO_NewsPostMinutes`

---

## See Also

- `SEA_Config.mqh` — Input definitions and mapping
- `SEA_TradeExecutor.mqh` — Veto implementation (`EvaluateTE`, `EvaluateCM`, `EvaluateRC`)
- `README.md` — Strategy and architecture overview
