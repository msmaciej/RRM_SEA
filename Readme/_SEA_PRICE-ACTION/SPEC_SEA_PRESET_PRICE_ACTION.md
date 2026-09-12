# SPEC — `PRESET_PRICE_ACTION` (mechanical specification for coding)

Companion to `README_SEA_PRESET_PRICE_ACTION.md` (design, §B/§C) and the `PA_A4_V2_*` cards (trader view).
This file turns every card rule into a number and a comparison, in the vocabulary of the SEA engine
(`EvaluateTS` → `EvaluateTE` → `EvaluateTM`, `TS = B × P × F × L × I → CG`). Bar index `[1]` = last
closed bar (signal bar), `[2]` = the one before. All examples are **shorts**; longs are the mirror
(swap H↔L, >↔<, Bid↔Ask). "pip" uses the engine's existing pip normalisation (JPY / metals aware).

Build order: **Phase 1** (fully specified here, codeable from existing engine + two voters) →
**Phase 2** (S/R-zone engine, specified to interface level). Everything in Phase 2 is marked `[P2]`.

---

## 0. What "stop beyond / below a level" means in SEA (read first)

The cards say *"ENTRY: stop below the body"*. That is a **pending stop order**: the trade is placed
at a price the market has *not yet reached*, and it becomes a position only when price gets there.
In MT5 terms:

| Card wording | MT5 order | Fills when |
|---|---|---|
| E1 "market at the close" | market order (`ORDER_TYPE_SELL`) | immediately at next tick after bar close |
| E2 "sell **stop** just below the body / IB low" | `ORDER_TYPE_SELL_STOP` at trigger < current Bid | Bid **falls** to the trigger (momentum confirms) |
| E3 "sell **limit** at 38–50 % retrace" | `ORDER_TYPE_SELL_LIMIT` at trigger > current Bid | price **rises** into the trigger (better price, no confirmation) |

SEA today fires a market order at bar open once TS=1 and the TE gates pass. Two ways to add E2/E3:

1. **Real MT5 pending orders** — `OrderSend` with `ORDER_TYPE_SELL_STOP/LIMIT`, `type_time=ORDER_TIME_SPECIFIED`.
   Simple, but the TE gate chain (spread, session, news, lots) runs at *placement*, not at *fill*, and
   the EA must track/cancel broker-side orders across restarts.
2. **Virtual pending ("armed level")** — the EA stores the trigger in memory and sends a **market
   order on the tick that touches it**. Gates run at fill time, expiry/cancel logic is engine-side,
   nothing lives on the broker. Slippage cost: one tick.

**This spec uses option 2 (virtual pending) as the default** (`Inp_PA_PendingMode = PA_PENDING_VIRTUAL`),
with `PA_PENDING_BROKER` as an optional later switch. It keeps Policy-A gate semantics identical to
every other preset. E1 is the existing market entry unchanged.

---

## 1. Inputs (all new inputs live in the `Inp_PA_*` namespace)

```
// --- identity (LOCKED by the preset) ---
BiasMode            = BIAS_EMA_SLOPE        // Phase 1: single-EMA slope bias (new mode or XEMA Fast==Slow)
PhaseMode           = PHASE_NONE            // P inert
LayerMode           = LAYER_LEVEL_TOUCH     // L = signal bar touched a level (see §3.3)
VoteMode            = UNANIMOUS, shift = 1

// --- trend / MTF ---
Inp_PA_TrendEMA           = 144   // trade-TF slope + level
Inp_PA_TrendEMA2          = 377   // second dynamic level (no slope test)
Inp_PA_SlopeBars          = 10    // slope = EMA[1] - EMA[1+SlopeBars]
Inp_PA_SlopeMinATR        = 0.15  // |slope| >= SlopeMinATR * ATR(14)  else B = 0
Inp_PA_RequireEmaOrder    = false // if true also require EMA144 < EMA377 for shorts
Inp_PA_MTF_TF             = PERIOD_D1
Inp_PA_MTF_EMA            = 21
Inp_PA_MTF_SlopeBars      = 5
Inp_PA_MTF_SlopeMinATR    = 0.10  // on the D1 ATR
Inp_PA_MTF_UseStructure   = true  // [P2] D1 HH/HL vs LH/LL must agree as well

// --- level / location (L) ---
Inp_PA_TouchTolATR        = 0.25  // level "touched" if |extreme - level| <= tol * ATR(14)
Inp_PA_Use_EMA_Levels     = true  // EMA144 / EMA377 as levels
Inp_PA_Use_RoundLevels    = true  // 00 levels
Inp_PA_RoundStepPips      = 100   // 1.4100, 1.4200 ... (JPY: 100 pips = 1.00)
Inp_PA_Use_SwingFlip      = true  // last broken swing = role-flip level (Phase 1 approximation of zones)
Inp_PA_SwingLookback      = 60    // bars to search for the last broken swing
Inp_PA_ZoneMinPips        = 5     // [P2]
Inp_PA_ZoneMaxPips        = 30    // [P2]

// --- signal bars (I) ---
Inp_PA_PB_WickToBody      = 2.0   // wick >= 2.0 * body
Inp_PA_PB_WickToRange     = 0.55  // wick >= 55 % of range
Inp_PA_PB_BodyPos         = 0.35  // body entirely inside the opposite 35 % of the range
Inp_PA_PB_MinRangeATR     = 0.50  // range >= 0.5 * ATR(14) (kills dojis)
Inp_PA_IB_MaxBars         = 3     // up to 3 consecutive inside bars
Inp_PA_IB_AllowEqual      = true  // H <= mother H and L >= mother L (not strict)
Inp_PA_IB_StrongTrendBars = 10    // close on trend side of EMA144 for the last N bars
Inp_PA_Allow_A/B/C/D      = true/true/true/true

// --- entry (TE) ---
Inp_PA_EntryMode_A/B/C/D  = STOP / STOP / STOP / STOP     // E1 MARKET | E2 STOP | E3 LIMIT (B only)
Inp_PA_PendingMode        = PA_PENDING_VIRTUAL
Inp_PA_TriggerBufferPips  = 1.0   // beyond the body / IB extreme, + current spread
Inp_PA_E3_RetracePct      = 0.45  // 0.38 .. 0.50
Inp_PA_ExpiryBars         = 3     // armed level dies after N bars of the trade TF
Inp_PA_CancelIfRunsATR    = 1.5   // cancel if price moves 1.5 ATR beyond trigger without filling (E3 only)
Inp_PA_AntyStop           = true
Inp_PA_AntyStop_MaxRearm  = 1
Inp_PA_AntyStop_ExtPips   = 25    // if price runs 25 pips past the old SL, move trigger to the SL price
Inp_PA_NewsLockoutBars    = 3     // no arming for N bars after a high-impact release (uses TE news gate)

// --- management (TM) ---
Inp_PA_SL_A               = SL_ZONE_EDGE     // + SL_BufferPips
Inp_PA_SL_B               = SL_PB_WICK       // or SL_PB_60PCT
Inp_PA_SL_C               = SL_IB_MOTHER_50  // or SL_IB_MOTHER_EXT
Inp_PA_SL_D               = SL_PB_50PCT      // or SL_PB_WICK
Inp_PA_SL_BufferPips      = 2.0
Inp_PA_SL_MotherExtMaxPips= 10    // C: use "beyond mother" only if that is <= 10 pips farther than 50 %
Inp_PA_BE_Pips            = 20    // BE_MODE_PIPS (new) — move SL to entry (+ spread) at +20 pips
Inp_PA_Partial_Pct        = 50
Inp_PA_Partial_ShortPips  = 20    // setup on a short-term level (H1/M30/M15 role flip)
Inp_PA_Partial_LongPips   = 40    // setup on a long-term level (H4/D1) or EMA level
Inp_PA_TPMode             = TP_RR (Phase 1) | TP_NEXT_LEVEL [P2]
Inp_PA_RR                 = 2.0
Inp_PA_TrailMode          = TRAIL_EMA (144, shift 1, cushion 0.3 ATR) | TRAIL_LEVEL_LADDER [P2]
Inp_PA_TrailStartsAfterBE = true
Inp_PA_RiskPct            = 2.0 (Policy-A, max 3.0)
```

---

## 2. Data the preset needs on every closed bar

```
ATR14[1]                      iATR(trade TF, 14)
EMA144[k], EMA377[k]          iMA(trade TF, EMA, close)
D1_EMA21[k]                   iMA(PERIOD_D1, 21, EMA, close)
swings[]                      3-bar swings on the trade TF (§2.1), last Inp_PA_SwingLookback bars
armed                         struct { active, dir, setup, trigger, sl, tp_hint, born_bar, expiry_bar,
                                       rearm_count, level, level_kind, is_long_term }
```

### 2.1 Swing definition (book, ch. 2)
```
SwingHigh at bar i :  High[i] > High[i+1]  AND  High[i] > High[i-1]      // i >= 2 (needs a closed right neighbour)
SwingLow  at bar i :  Low[i]  < Low[i+1]   AND  Low[i]  < Low[i-1]
```
Structure state (used by `[P2]` bias and by the swing-flip level in Phase 1):
```
lastSH, prevSH, lastSL, prevSL   = the two most recent swing highs / lows
UP    : lastSH > prevSH AND lastSL > prevSL
DOWN  : lastSH < prevSH AND lastSL < prevSL
RANGE : otherwise
```

---

## 3. TS — `EvaluateTS_PriceAction()` (bar close, shift = 1)

### 3.1 B — direction (Phase 1: EMA slope; `[P2]`: swing structure)
```
slope  = EMA144[1] - EMA144[1 + Inp_PA_SlopeBars]
B = 0
if (slope <= -Inp_PA_SlopeMinATR * ATR14[1])                     B = -1   // short bias
if (slope >=  Inp_PA_SlopeMinATR * ATR14[1])                     B = +1
if (Inp_PA_RequireEmaOrder && B == -1 && !(EMA144[1] < EMA377[1])) B = 0   // mirror for +1
[P2] if (Inp_PA_MTF_UseStructure) B = (structure(trade TF) == DOWN ? -1 : structure == UP ? +1 : 0)
```

### 3.2 P — inert (returns 1)

### 3.3 L — location: the signal bar touched a level *against* the bias
For a short (B = -1) the candidate level list `levels[]` is built from:
```
EMA levels     : EMA144[1], EMA377[1]                                (kind = LVL_EMA,   long_term = true)
Round levels   : nearest k * Inp_PA_RoundStepPips above/below Close[1] (kind = LVL_ROUND, long_term = false)
Swing-flip     : the most recent SwingLow within SwingLookback that was later CLOSED BELOW
                 (i.e. exists j < i with Close[j] < Low[i]) and price has since come back up to it
                                                                    (kind = LVL_FLIP,  long_term = (trade TF >= H4))
[P2] Zones     : from the S/R-zone engine (§6), nearest above Close[1]  (kind = LVL_ZONE,  long_term = zone.tf >= H4)
```
Touch test (short): `High[1] >= level - tol AND High[1] <= level + tol` with `tol = Inp_PA_TouchTolATR * ATR14[1]`
(`[P2]`: for zones, `tol = zone.halfWidth`). The first level that passes (priority ZONE > FLIP > EMA > ROUND)
becomes `armed.level`. **L = 1 if any level passes; else L = 0.** Setup C (inside bar) may pass L
without a level if `strongTrend` (§3.4) is true.

### 3.4 I — signal-bar voters (all required; a voter not used by the identified setup returns 1)

**PinBar(short)** on bar `[1]`:
```
R   = High[1] - Low[1];   body = |Close[1] - Open[1]|;   UW = High[1] - max(Open[1], Close[1])
pass = R    >= Inp_PA_PB_MinRangeATR * ATR14[1]
    && UW   >= Inp_PA_PB_WickToBody  * max(body, 0.1 * R)          // guard for body == 0
    && UW   >= Inp_PA_PB_WickToRange * R
    && max(Open[1], Close[1]) <= Low[1] + Inp_PA_PB_BodyPos * R     // body in the lower 35 %
```
Long = mirror with the lower wick. (Direction rule: wick points **against** the trade.)

**InsideBar(short)**: find `n` (1..Inp_PA_IB_MaxBars) such that bars `[1..n]` are all inside bar `[n+1]`:
```
mother = n+1
for k in 1..n : High[k] <= High[mother] && Low[k] >= Low[mother]   (strict if !AllowEqual)
pass = (n >= 1)
IB_low  = min(Low[1..n]) ; IB_high = max(High[1..n])
strongTrend = for k in 1..Inp_PA_IB_StrongTrendBars : Close[k] < EMA144[k]   (short)
```

**PBIB(short)**: `InsideBar` passes **and** `PinBar` evaluated on the mother bar passes.

**MTF**: `d1slope = D1_EMA21[1] - D1_EMA21[1 + Inp_PA_MTF_SlopeBars]`; pass for short if
`d1slope <= -Inp_PA_MTF_SlopeMinATR * ATR(D1)`. `[P2]` additionally `structure(D1) == DOWN`.

**Setup identification** (first match wins; each needs `B == -1` and `MTF`):
```
D : Allow_D && PBIB                                  (L may be 0 if strongTrend)
B : Allow_B && PinBar && L == 1
A : Allow_A && L == 1 && level_kind in {LVL_FLIP, LVL_ZONE} && PinBar   // retest of a flipped level
C : Allow_C && InsideBar && (strongTrend || L == 1)
none → I = 0
```
(Setup A and B differ only by level kind; A's stop and partial rules follow the level, B's follow the bar.)

### 3.5 F — filters
```
- bar [1] closed                                   (shift = 1, engine default)
- "never the first break": setups A/D only arm on a level that was ALREADY broken earlier and is now
  being retested → guaranteed by the LVL_FLIP / LVL_ZONE construction. A live breakout bar (Close[1]
  beyond a level for the first time) never produces TS = 1.
- overextension: |Close[1] - EMA144[1]| <= 2.5 * ATR14[1]  (reuse F_PriceExt with ref EMA = 144)
- no arming while Inp_PA_NewsLockoutBars after a high-impact release (TE news calendar)
```

### 3.6 CG — climax veto (reuse): one bar > 2.0 ATR or move > 3.0 ATR in the trade direction → TS = 0.

### 3.7 Latch
`TS = B × 1 × F × L × I → CG`. On TS = 1 the preset **arms** (it does not enter):
```
armed.dir      = -1;   armed.setup = A|B|C|D;   armed.born_bar = time[1]
armed.expiry   = born + Inp_PA_ExpiryBars bars
armed.trigger  = per §4.1;   armed.sl = per §5.1;   armed.level = level;   armed.is_long_term = ...
```
A newer TS = 1 replaces an older armed level (one armed level per symbol/TF).

---

## 4. TE — `EvaluateTE_PriceAction()` (every tick while `armed.active`)

### 4.1 Trigger price by entry mode (short; `buf = Inp_PA_TriggerBufferPips + spread`)
```
E1 MARKET : trigger = Bid at the first tick after the signal bar closes  (existing path)
E2 STOP   : setup A/B : trigger = min(Open[1], Close[1]) - buf      // just below the PB body
            setup C/D : trigger = IB_low - buf                       // just below the inside bar(s)
E3 LIMIT  : setup B only : trigger = Low[1] + Inp_PA_E3_RetracePct * (High[1] - Low[1])
```
Long = mirror (`+buf`, `max(Open,Close)`, `IB_high`, `High - pct*R`).

### 4.2 Fill logic (virtual pending)
```
on tick:
  if (!armed.active) return
  if (time[0] >= armed.expiry)                          → cancel("expiry")
  if (E3 && Bid <= trigger - Inp_PA_CancelIfRunsATR*ATR) → cancel("ran away")
  if (structure flipped or B changed sign)              → cancel("bias lost")
  hit = (E2 && Bid <= trigger) || (E3 && Bid >= trigger) || (E1)
  if (hit):
      run Policy-A gate chain (spread, session, news, max trades/day, risk, lots)   // unchanged
      if gates pass → market SELL at Bid, SL = armed.sl (recomputed vs fill), TP per §5.4
                      armed.active = false; remember armed for Anty-Stop (§4.3)
      else          → keep armed until expiry (retry on next tick)   // NOT cancelled
```
Broker mode (`PA_PENDING_BROKER`) places `SELL_STOP/LIMIT` at `trigger` with `expiration = armed.expiry`
and mirrors cancel conditions with `OrderDelete`; gates then run at placement only.

### 4.3 Anty-Stop re-arm (book, ch. 4)
```
on SL hit of a PA position P:
  if (!Inp_PA_AntyStop || P.rearm_count >= Inp_PA_AntyStop_MaxRearm) return
  if (B still == P.dir && MTF still passes && level not invalidated*) :
      armed = copy of P.armed;  armed.rearm_count++;  armed.expiry = now + Inp_PA_ExpiryBars
      armed.trigger = P.entry_price            // same pending order, same place
      if (price is already > P.sl + Inp_PA_AntyStop_ExtPips against us)   // ran 25 pips past the stop
          armed.trigger = P.sl                 // re-enter at the old stop price, recover the loss
*level invalidated = a bar CLOSED beyond the level by more than tol (the retest has failed)
```

---

## 5. TM — `EvaluateTM_PriceAction()` (while a PA position is open)

### 5.1 Initial SL by setup (short; `b = Inp_PA_SL_BufferPips`)
```
SL_ZONE_EDGE     : level + tol + b                (A)    [P2: zone.upper + b]
SL_PB_WICK       : High[1] + b                    (B default, D alt)
SL_PB_60PCT      : Low[1] + 0.60 * (High[1]-Low[1])   (B aggressive)
SL_PB_50PCT      : Low[1] + 0.50 * (High[1]-Low[1])   (D default)
SL_IB_MOTHER_50  : Low[mother] + 0.50 * (High[mother]-Low[mother])   (C default)
SL_IB_MOTHER_EXT : High[mother] + b, only if (that - SL_IB_MOTHER_50) <= Inp_PA_SL_MotherExtMaxPips
E3 entries always use SL_PB_WICK (the retrace made the stop small).
Sanity: SL distance >= max(engine min-floor, 1.0 * spread + b); if SL < min → widen to min (never skip).
```

### 5.2 Break-even — `BE_MODE_PIPS` (new mode alongside `BE_MODE_R_MULTIPLE`)
`if (profit_pips >= Inp_PA_BE_Pips) SL = entry ± spread` (once; never moved back).

### 5.3 Partial close
```
target = armed.is_long_term ? Inp_PA_Partial_LongPips : Inp_PA_Partial_ShortPips
if (profit_pips >= target && !partial_done) close Inp_PA_Partial_Pct % of volume; partial_done = true
(if BE has not fired yet, fire it in the same step — "never let a profit become a loss")
```

### 5.4 Take profit and trail
```
Phase 1 : TP = entry - Inp_PA_RR * (SL - entry)                       (TP_RR)
          Trail: after BE, TRAIL_EMA(144, shift 1, cushion 0.3 ATR)   (existing mode)
[P2]    : TP_NEXT_LEVEL : TP = nearest zone below entry (short) whose distance >= 1.0 * SL distance;
          TRAIL_LEVEL_LADDER : each time a bar CLOSES beyond a zone, SL = that zone's far edge + b
Either way: exit also on opposite structure break [P2] (a closed bar above lastSH for a short).
```

---

## 6. `[P2]` S/R-zone engine — interface + algorithm

```
struct Zone { double lo, hi; int touches; int breaks; datetime lastTouch; bool dualRole; ENUM_TIMEFRAMES tf; double score; }
Zone[] BuildZones(symbol, tf /*H4 or D1*/, lookbackBars=400)
Zone   NearestZone(price, dir)         // above for shorts, below for longs
```
Algorithm:
1. Collect swing highs and lows (§2.1) on `tf` over `lookbackBars`.
2. Cluster swing prices: two swings belong to the same cluster if `|p1 - p2| <= max(Inp_PA_ZoneMinPips, 0.5*ATR(tf))`.
   Zone `lo/hi` = min/max of the cluster; discard zones wider than `Inp_PA_ZoneMaxPips`.
3. `touches` = swings in the cluster + bars whose H or L entered the zone and closed back outside.
   `breaks` = bars that closed through the zone. `dualRole` = has acted as both S and R (a swing high
   and a swing low both in the cluster, or a break followed by a retest from the other side).
4. `score = 2*touches + 2*dualRole + age_bonus(bars since last touch: 0 if < 20, 1 if 20–200, 2 if > 200) - 2*breaks`;
   drop zones with `touches < 2` or `breaks > touches`.  Optional +1 if a fibo 0.5/0.618/0.764 of the
   last swing falls inside the zone (H1+ only), +1 if a round 00 price falls inside.
5. Rebuild once per `tf` bar; cache. `NearestZone` returns the highest-score zone within 3 ATR that
   is on the required side of price.
6. In L (§3.3) a zone touch is `High[1] within [zone.lo - tol, zone.hi + tol]`; SL = `zone.hi + b`;
   TP = `NearestZone(entry, below).hi` for TP_NEXT_LEVEL.

---

## 7. Validation plan (SignalScan / backtest)
```
- Unit: feed the book's figures 55–64 as synthetic OHLC → PinBar/InsideBar/PBIB must pass exactly there.
- SignalScan, EURUSD H1 2 years: count TS=1 per setup; expect A+B >> C+D; no TS=1 on breakout bars.
- E2 vs E1 vs E3 on the same signals: E2 fill rate ~60–75 %, E3 fill rate ~30–45 %, E3 avg SL smaller.
- Anty-Stop: re-arms must be <= 1 per losing trade and only while B/MTF unchanged.
- Sanity guards to log: SL widened to min-floor, armed expired, armed cancelled (bias lost / ran away).
```

## 8. Open decisions before coding
1. Slope bias (`BIAS_EMA_SLOPE`) as a new mode vs. reusing XEMA's `Fast == Slow` slope mode — pick one.
2. `LAYER_LEVEL_TOUCH` as a new LayerMode vs. implementing L inside the preset block — the former is cleaner.
3. `BE_MODE_PIPS` and partial close are generic TM features other presets will want (TopInvestor, RH_*):
   implement them in `SEA_TradeExecutor.mqh`, not preset-local.
4. Virtual pending (`armed`) is also reusable (Golden Strategy's aggressive/conservative toggle, RH_GS
   pending entries) — implement as a TE-level struct.
