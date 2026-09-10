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
| `VETO_NEWS` | A news event matching the chart pair's base/quote currency and the impact filter is inside `[t−Pre, t+Post]` (server time) | ✅ Fully configurable | `Inp_Global_VETO_UseNews`, `Inp_Global_VETO_NewsSource`, `Inp_Global_VETO_NewsImpactFilter`, `Inp_Global_VETO_NewsFile`, `Inp_Global_VETO_NewsPreMinutes`, `Inp_Global_VETO_NewsPostMinutes`, `Inp_Global_VETO_NewsCsvTzOffsetMin` | `false`, `NEWS_SRC_AUTO`, `NEWS_IMPACT_MED_PLUS`, `calendar_statement.csv`, `60`, `60`, `0` |

**Purpose**: Gate execution at shift=0 using real-time market conditions.

#### `VETO_NEWS` — event source and contract (NEWS-SRC, 2026-09-10 — *candidate, UNCONFIRMED until a live journal shows `source=CALENDAR events>0`*)

| Source (`Inp_Global_VETO_NewsSource`) | Where events come from | When it is used |
|---|---|---|
| `NEWS_SRC_AUTO` (default) | MT5 built-in economic calendar (`CalendarValueHistory` + `CalendarEventById`, filtered by the pair's `SYMBOL_CURRENCY_BASE` / `SYMBOL_CURRENCY_PROFIT`); falls back to the CSV only if the calendar API is unavailable on the terminal | live / demo |
| `NEWS_SRC_CALENDAR` | platform calendar only, no CSV fallback | live / demo |
| `NEWS_SRC_CSV` | hand-made CSV only (legacy path) | live / demo / tester |

**Resolved once at `OnInit`** (`CSignalEngine::ResolveNewsSource`) and printed as exactly one journal line:

```
[NEWS] source=CALENDAR|CSV|NONE events=N window=-Pre/+Post impact=<enum> tz=server [untimed=U refresh=hourly next=<time>] [calendar=unavailable|skipped(tester)]
```

**Fail-open is absolute.** `source=NONE` ⇒ `IsNewsBlocked()` returns `false` on every tick, even with `UseNews=true`, and OnInit prints `[NEWS] *** NEWS VETO INACTIVE … ***`. A news veto that is silently doing nothing is the failure this feature exists to remove; the loud line is the observable.

**Calendar path details**
- Window read: `[now − Post, now + Pre + 24 h]`, server time. The MQL5 calendar API and `TimeCurrent()` share the trade-server clock (MQL5 docs, *Economic Calendar*), so no timezone arithmetic is applied.
- Impact mapping: `CALENDAR_IMPORTANCE_HIGH/MODERATE/LOW` → the existing `"high"/"medium"/"low"` strings, so `NewsImpactPass()` and `SNewsEvent` are unchanged. `CALENDAR_IMPORTANCE_NONE` and `CALENDAR_TYPE_HOLIDAY` are ignored.
- Events without an exact release time (`time_mode` ≠ `CALENDAR_TIMEMODE_DATETIME` — all-day, "no time", tentative) are **not** loaded: their timestamp is a placeholder, so a ±Pre/Post window around it would block the wrong hour. They are counted as `untimed=U` on the journal line so they are visible, not silent.
- "Calendar works but the window is empty" is still `source=CALENDAR events=0` (no INACTIVE warning) — the hourly refresh fills it in. Only an API error (`GetLastError() ≠ 0`, e.g. 4014) counts as *unavailable*.
- **Hourly refresh (live/demo only):** `RefreshNewsIfDue()` runs at the top of `OrchestrateTick()` — before the TE consumer — and re-reads the calendar at most once per hour. A failed refresh keeps the previous list and warns once (`[NEWS] refresh failed — keeping previous N events`); it never degrades to NONE mid-session. At `DEBUG_FULL` each successful refresh logs `[NEWS] refresh events=N untimed=U next=<time>`.
- **Strategy Tester:** the calendar API is not available in the tester by platform design (error 4014). The tester therefore resolves to CSV if the file is readable, otherwise NONE + warning. No re-polling in the tester. *Known gap (T1, deferred):* without `#property tester_file` the CSV in `MQL5\Files` is not copied to the agent, so today the tester always reads `source=NONE` — never crashes, never blocks. The one-line directive is ready to add after one tester run with no CSV present proves it harmless.

**CSV contract** (`Inp_Global_VETO_NewsFile`, in `<terminal>\MQL5\Files` — *not* the Common folder; sample: `Readme/calendar_statement.csv`)

| Column | Format | Example |
|---|---|---|
| `Date` | quoted `"YYYY, Month DD, HH:MI"`, English month name, **server time** unless `NewsCsvTzOffsetMin` is set | `"2026, September 12, 14:30"` |
| `Event` | free text (ignored by the parser) | `Nonfarm Payrolls` |
| `Impact` | `high` / `medium` / `low` (case-insensitive; empty = treated as relevant under MED_PLUS) | `High` |
| `Currency` | ISO code, matched against base/quote | `USD` |

Header row required. `Inp_Global_VETO_NewsCsvTzOffsetMin` is **added** to every CSV time to reach server time (file in UTC, broker EET summer → `+180`); `0` = file already in server time (previous behaviour). A file whose events are all in the past loads but blocks nothing — OnInit now warns `[NEWS] WARNING CSV stale …` (G3).

**TE label (T2):** `[TE VETO] VETO_NEWS | <CCY> <impact> @ <time> (<source>)` names the actual blocking event instead of the former fixed "high-impact event active".

**Kill tests (J1 — status stays *candidate* until seen):** (a) clean compile; (b) live journal `[NEWS] source=CALENDAR events>0`; (c) `NewsSource=CSV` with no file ⇒ `source=NONE` + INACTIVE warning and no `VETO_NEWS` ever fires; (d) one-row CSV ⇒ `source=CSV events=1`; (e) `DEBUG_FULL` shows one `[NEWS] refresh` per hour, not per tick.

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
- `Inp_Filter_UseNews` → `Inp_VETO_UseNews`
- `Inp_Filter_NewsFile` → `Inp_VETO_NewsFile`
- `Inp_Filter_NewsPre` → `Inp_VETO_NewsPreMinutes`
- `Inp_Filter_NewsPost` → `Inp_VETO_NewsPostMinutes`

NEWS-SRC 2026-09-10: the two new inputs `Inp_Global_VETO_NewsSource` (default `NEWS_SRC_AUTO`) and `Inp_Global_VETO_NewsCsvTzOffsetMin` (default `0`) are absent from older `.set` files and simply take their defaults — no editing required; an old file loads and gets calendar-first behaviour automatically.

---

## See Also

- `SEA_Config.mqh` — Input definitions and mapping
- `SEA_TradeExecutor.mqh` — Veto implementation (`EvaluateTE`, `EvaluateCM`, `EvaluateRC`)
- `README.md` — Strategy and architecture overview
