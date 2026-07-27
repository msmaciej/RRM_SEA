# VPRR — capability roadmap: what can be fixed, what cannot, and what data is required

Written 2026-07-27, closing the audit at HEAD `78dd01f`. Companion to the "VPRR —
Volume Pullback-Recovery Ratio (MEASUREMENT-ONLY)" section of `README.md`.

**Purpose.** The audit answered *what the code does* and *where it is wrong*. This
document answers the third question: **what would it take to make it correct**, split by
what is achievable with what we have today versus what is blocked and on what.

---

## CORRECTION to an earlier statement in this session

Earlier I stated that MQL5 exposes no open interest. **That was too strong and it changes
the roadmap.**

What is accurate:

| Claim | Verdict |
|---|---|
| There is no `CopyOpenInterest()` | **True** |
| `MqlRates` carries no OI field | **True** — `tick_volume` and `real_volume` only |
| Therefore OI is entirely unavailable | **FALSE** |

`SymbolInfoDouble(symbol, SYMBOL_SESSION_INTEREST)` returns **summary open interest** for
the current session. It is a **live scalar, not a historical series**.

The consequence is significant: OI **cannot be backfilled** for historical analysis, but
it **can be accumulated prospectively** — sample it once per bar from today and you build
your own OI series going forward. That moves OI from "impossible" to "start collecting
now, usable in N months."

Everything below marked `[probe]` needs confirmation against your actual broker before
being relied on. That is what the capability probe in Tier 0 is for.

---

## CORRECTION 2 (2026-07-27, after operator challenge)

Two things in the original version of this document were wrong, and both mattered.

**1. Tier A was cosmetic and was not labelled as such.** With no real-volume feed every
reading is `0.00`, so fixing DST bucketing or day-of-week baselines changes nothing
observable. The tiering looked productive while every item was gated on data not in hand.

**2. "Tick mode cannot answer the metals question" was wrong.** That carried a limit from
the VOTING design into the MEASUREMENT design without rechecking it. Your broker quotes
XAUUSD, so it produces tick counts for XAUUSD exactly as for FX — gold IS measurable
today, in tick mode. The accurate, narrower claim: tick counts cannot show *institutional
participation*, because a quote-update count cannot report contracts traded or aggressor
side. A real limit on interpretation; not a reason to skip the measurement.

**What actually unblocked this** was `Inp_VPRR_ResearchTickMode` (fix 7), which removed a
blocker the audit itself had introduced: defect V9's fail-closed rule was calibrated for a
voter and, once the voter was removed, only prevented measurement.

**Revised priority.** Tier 0 below is still worth doing, but it is no longer the first
step. The first step is: **turn on research tick mode for FX and XAUUSD and start
collecting.** See `README_SEA_VPRR_MEASUREMENT.md` for what the data can settle — in
particular L1.1, which can end this line of work with a single comparison.

---

## Tier 0 — broker capability probe (still worth doing, no longer first)

**Cost: one diagnostic script. Touches no trading path. Blocks nothing.**

Almost every question below resolves to *"what does our broker actually supply?"* — and we
are currently guessing. The repo already has `SEA_IND_ServerTime_Check.mq5` doing exactly
this kind of probing for VPRR proxies; this extends the same pattern.

What it should report, per symbol of interest:

| Probe | API | Tells us |
|---|---|---|
| Real bar volume | `CopyRealVolume` | Is VPRR measurable at all here? |
| Session open interest | `SymbolInfoDouble(SYMBOL_SESSION_INTEREST)` | Can we accumulate an OI series? |
| Trade ticks | `CopyTicksRange(..., COPY_TICKS_TRADE, ...)` | Do we get real trades, not just quotes? |
| Aggressor flags | `MqlTick.flags & (TICK_FLAG_BUY \| TICK_FLAG_SELL)` | **Can we get SIGNED volume?** |
| Tick history depth | `CopyTicksRange` over a past window | Can signed flow be BACKTESTED, or only run forward? |
| DOM | `MarketBookAdd` / `MarketBookGet` | Book imbalance available? (realtime only, no history) |
| Bar history depth | `Bars()` | Enough sessions for the RVOL baseline? |
| Proxy symbols | the above, on `GC`, `MGC`, `XAUUSD`, index CFDs | Which instrument is the best VPRR host? |

**Why this is the highest-value next step.** The aggressor-flag row alone decides whether
the deepest defect in VPRR — that volume is unsigned and therefore direction-blind — is
fixable on your current broker or not. Right now neither of us knows. One script settles
it, and it costs nothing to run.

---

## Tier A — fully fixable NOW, thresholds included, no new data

These are correctness defects, not tuning questions. Each has a right answer derivable
from the code or from an existing configured value, so none introduces a magic number.

### A1. The Climax Guard contradiction

**Problem.** The ratio is monotonic in volume, so a volume climax reads as *maximum
confirmation* — while Climax Guard vetoes that same bar for being an over-extended
blow-off. Two components of one pipeline reading one event in opposite directions.

**Fix without a magic number.** Reuse the threshold Climax Guard already uses
(`ClimaxGuard_BarATRMult`). When a bar exceeds it, VPRR's reading for that bar is
classified as *exhaustion*, not *confirmation*. No new tunable: the number is already
configured, already reasoned about, and the two components become consistent by
construction.

**Why it qualifies as Tier A.** The rule is event-indexed to an existing structural
threshold rather than time-indexed to an invented one.

### A2. RVOL bucketing by day-of-week, not just minute-of-day

**Problem.** The current baseline steps back in 24h blocks. Monday 14:30 is compared with
Sunday 14:30. Weekly volume structure is real — the Monday open, the Friday close, and the
weekend gap are not interchangeable with a mid-week bar.

**Fix.** Bucket by `(day-of-week, minute-of-day)`, or at minimum step back in 7-day blocks
so like is compared with like. Correctness, not tuning.

### A3. Session/DST robustness of the baseline

**Problem.** The baseline is keyed on broker server time. Server-time DST shifts move every
bucket by an hour, silently corrupting the baseline across the changeover.

**Fix.** Key buckets on a DST-stable reference, or detect the shift and invalidate the
affected window rather than averaging across it.

### A4. History-sufficiency reporting

**Problem.** RVOL silently returns "not computable" when history is thin. Correct, but the
operator cannot distinguish *"no real volume"* from *"not enough bars yet."*

**Fix.** Check `Bars()` against `VPRR_RVOL_Sessions` at init and print which condition is
in force. Pure diagnostics.

### A5. Roll-period flagging for futures proxies

**Problem.** Futures volume distorts around contract roll. A proxy like `GC` carries roll
artifacts that are not market participation.

**Fix.** Flag bars near a roll in the measurement CSV as a **column**, not a filter — let
the analysis decide. Detectable from contract expiry via `SYMBOL_EXPIRATION_TIME` `[probe]`.

**Tier A total: five items, all closeable in one focused session, none needing data.**

---

## Tier B — mechanism buildable now, THRESHOLD blocked on data

For each of these the code can be written today and validated for correctness with the
tick-volume harness. **The number cannot be chosen without outcome data.** Building the
mechanism and shipping it inert (behind the two-key gate) is legitimate; picking the
number now is not.

| # | Mechanism | Why the threshold is blocked |
|---|---|---|
| B1 | **Absolute participation floor** — require recovery RVOL ≥ floor, so a dead-quiet cycle stops passing on ratio ≈ 1 | "How much participation is enough" is empirical per instrument and timeframe |
| B2 | **Absorption detection** — high RVOL + compressed range ⇒ warning rather than confirmation | The compression threshold that separates absorption from initiation is empirical |
| B3 | **Slope-based cycle classification** — fading-into-pullback (healthy) vs building-into-pullback (distribution) | The slope magnitude that distinguishes them is empirical; only the SIGN is meaningful without data |
| B4 | **Confidence output instead of pass/fail** — VPRR emits a scalar for sizing rather than a boolean | The mapping from scalar to size multiplier is entirely empirical |
| B5 | **Prospective OI accumulation** — sample `SYMBOL_SESSION_INTEREST` per bar, persist, build the price/volume/OI table from `README.md` | Mechanism is buildable now; the table needs months of accumulated OI before it says anything |

**B5 is the one to start early**, because its blocker is *elapsed time*, not a decision. Every
day it is not collecting is a day of OI history that cannot be recovered later.

---

## Tier C — blocked on DATA ACCESS (obtainable, just not owned yet)

| # | Blocked | What unblocks it | How to get it |
|---|---|---|---|
| C1 | Any VPRR measurement at all | Real exchange volume on a metals instrument | Broker with futures-linked feed, or a proxy symbol (`GC`/`MGC`) in Market Watch. **A demo account with such a broker is sufficient and free** — this does not require moving live capital |
| C2 | Every threshold in Tier B | ~300–500 outcome-labelled signal bars | Already automated — `SEA_VPRR_<symbol>_<tf>.csv`. Needs C1 first, then calendar time |
| C3 | Signed volume / volume delta | Trade ticks carrying aggressor flags | `[probe]` Tier 0 answers whether this exists on your broker |
| C4 | Backtestable signed flow | **Tick HISTORY**, not just live ticks | `[probe]` If only live ticks are available, signed flow can run forward but can never be backtested — a hard constraint on how it could ever be validated |
| C5 | Positioning context | CFTC COT (public, weekly, free CSV) | Loadable via the existing news-CSV pattern (`LoadNews` in `SEA_SignalEngine.mqh`). Weekly granularity — useless per-bar, usable as a regime filter |
| C6 | Book imbalance | Level 2 DOM | `[probe]` Realtime only in MQL5 — **no history, therefore not backtestable**. Same constraint as C4 |

**The cheapest unblock by a wide margin is C1 via a demo account.** It converts VPRR from
untestable to testable at zero cost and zero risk, and it is the precondition for C2, which
is the precondition for all of Tier B.

---

## Tier D — NOT possible, and why

Stated so nobody spends a session rediscovering it.

| # | Not possible | Reason |
|---|---|---|
| D1 | **Historical per-bar open interest** | No API. `SYMBOL_SESSION_INTEREST` is a live scalar; `MqlRates` has no OI field. Cannot be backfilled — only accumulated forward (B5) |
| D2 | **Backfilling any of this on FX** | FX is OTC and fragmented with no consolidated tape. There is no real volume to recover — not a broker limitation, a market-structure fact |
| D3 | **Recovering signed flow from bar volume** | `CopyRealVolume` is unsigned by construction. Aggressor side is not derivable from a bar aggregate at any level of cleverness — it requires tick-level data (C3) |
| D4 | **Backtesting DOM imbalance** | MQL5 exposes no historical order book. Even where DOM is live, there is nothing to test against |
| D5 | **Deriving any threshold from the Oracle** | The RRM manual mentions volume once in 126 pages, narratively. It is silent on the subject and cannot adjudicate |
| D6 | **Validating thresholds by reasoning** | Category error. This is what killed the original implementation: plausible numbers, never measured |

---

## The data shopping list, in dependency order

1. **Broker capability probe output** (Tier 0) — free, today, unblocks the map.
2. **A real-volume instrument** (C1) — demo account is enough. Gold via a futures-linked
   broker, or index CFDs on a venue supplying exchange volume.
3. **300–500 outcome-labelled signal bars** (C2) — automatic once (2) exists.
4. **OI accumulation started** (B5) — begin as early as possible; the blocker is calendar
   time and it cannot be backfilled.
5. **COT history** (C5) — optional, free, public, only if positioning context is wanted.

---

## Decision gates

**Gate 1 — after Tier 0.** If the probe shows no real volume anywhere and no accessible
proxy: VPRR cannot be measured on this setup at all. The honest response is to leave it
inert exactly as it now is, or delete it. **Do not build Tier A or B into a system that
can never feed them.**

**Gate 2 — after C2 (data in hand).** Check whether any measured column separates winners
from losers. Exclude `0.0` rows per column — those are absent readings, not observations.
If nothing separates, delete VPRR. That is a cheap, legitimate and *good* outcome: a few
hundred lines removed and a real fact learned about your own instrument.

**Gate 3 — only if Gate 2 shows separation.** Set thresholds from the data, then consider
re-arming via the two-key gate. Not before.

---

## What I would do next, in order

1. **Write the Tier 0 probe.** Small, self-contained, diagnostic-only, touches no trading
   path. It converts most of this document from "unknown" to "known."
2. **Open a demo account with a real-volume feed.** Free, and it unblocks the entire chain.
3. **Start B5 (OI accumulation).** Only if the probe confirms `SYMBOL_SESSION_INTEREST` is
   populated. Its blocker is elapsed time, so starting late is the one cost that cannot be
   recovered.
4. **Tier A as one session.** Five real correctness fixes, no data dependency, no magic
   numbers.
5. **Everything else waits for Gate 2.**

**What NOT to do:** build Tier B mechanisms with plausible-looking default thresholds. That
is precisely how VPRR reached the state this audit found — reasoned numbers, never
measured, wearing the costume of a working feature.
