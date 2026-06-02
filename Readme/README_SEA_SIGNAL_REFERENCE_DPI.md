# DPI Signal Reference — Canonical Logic Specification

> **Status:** CANONICAL. This file is the single source of truth for DPI vote logic.
> It supersedes the DPI descriptions in `README_SEA_DPI_mc_main.md`,
> `README_SEA_SIGNAL_REFERENCE_DPI_SECTION.md`, and any dated copies
> (`*_260521-14.md`). Those should be archived once this is adopted.
>
> **Important:** Section 7 ("Divergence from current implementation") records that the
> code and the older docs do **not** yet implement the logic below. This file states the
> *intended* logic (the design); the engine and the indicator are to be corrected to match
> it. §2/§3/§5 have been **verified line-by-line against source** and the §8 open items
> (O1–O5) **resolved with USER** (260601); coding (engine `Check_DPI`, then mc_main) follows.

---

## 1. Purpose

DPI (Dynamic Price Index) is the **I-factor momentum-direction voter**. Its output is a
single gate: `DPI = 1` (vote passes) or `DPI = 0` (vote blocks), evaluated for the
current bias (LONG or SHORT).

The vote is driven by the **ribbon (histogram) colour** the DPI indicator paints, with
optional, independently-toggled enhancement gates that make the vote progressively
stricter. For the end-to-end evaluation order and the equation in each configuration, see
**§4c**; for the multiplicative equation and component inventory, **§4 / §4b**.

---

## 2. Indicator architecture (how the ribbon is built)

These definitions are transcribed from `SEA_IND_DPI_mc_main.mq5` and **verified
line-by-line against source** (260601). Anchors below are the corrected, exact lines
(they reflect source, not the older docs — the previous "ribbon = Blue − Red"
description was wrong).

- **Blue line (LEAD):** fast MACD core = `EMA(Fast) − EMA(Slow)` of close (`g_BlueCore`).
- **Red signal line (FOLLOW):** smoothed signal = EMA of Blue (`g_RedSignal`;
  configurable EMA5/8/13/21 or Double).
- **`hist`:** `Blue − Red` (mc_main **463**: `double hist = g_BlueCore[i] - g_RedSignal[i]`) —
  this is the value plotted as the **Red_Contour line** (`g_RedContour`, **464**), i.e. one
  boundary. **It is *not* "the ribbon" by itself.**
- **Ribbon histogram (the coloured bars):** a **separate construction** (mc_main **494–527**),
  the **filled band between the Blue line and the contour**, *not* the bare `Blue − Red`
  difference:
  - Blue and hist on the **same side** of zero → bar extent = the value **further from
    zero** of `{Blue, hist}` (`MathMax` above zero / `MathMin` below zero; mc_main **517 / 523**).
  - Blue and hist on **opposite sides** → the band **spans from Blue across zero to hist**
    (positive portion and negative portion drawn separately).
  So the rendered ribbon's *height/geometry* depends on **both** Blue and hist, not simply
  where Blue sits relative to Red.
- **Ribbon colour (red/yellow):** decided separately by `hist_wants_yellow`
  (mc_main **480–488**) — see §3. The colour is independent of the band geometry above.
- **GREEN overlay (`g_HistGreen`):** (mc_main **529–534**) appears only when Blue and hist
  are on the **same side** of zero, and is **bounded by the 0-line on one edge and by
  whichever of {Blue-lead, Red-contour} is *closest to the 0-line* on the other edge** — so
  its capping line can be either Blue or the contour, whichever is nearer zero (not a fixed one):
  - Above zero → `MathMin(Blue, hist)` — fills from 0 up to the **lower** of the two.
  - Below zero → `MathMax(Blue, hist)` — fills from 0 down to the **higher** (least negative).
  - Otherwise absent (`EMPTY_VALUE`).
  Momentum-strength overlay, not a direction.
- **Zero line:** reference for "side" (above / below).

---

## 3. Ribbon colour (the BASE signal)

Colour is decided per bar **solely** by `hist_wants_yellow` (mc_main **480–488**); every
bar-rendering branch (mc_main **542, 562, 584, 600**) just tests that one boolean, so nothing
else colours the bars:

```
if (hist >= 0):  hist_wants_yellow = !(InpEnableCCI && CCI <  0)
else (hist < 0): hist_wants_yellow =  (InpEnableCCI && CCI >= 0)
```

Worked through, this splits cleanly by whether CCI is enabled:

- **CCI ENABLED (the live RRM_ORG config):** *both* branches reduce to the same thing —
  **colour = sign(CCI)**:
  - **CCI ≥ 0 → YELLOW**
  - **CCI < 0 → RED**
  - **The histogram sign (where Blue sits vs Red) does NOT affect the colour.** The
    `if(hist≥0)/else` split is structural only; both arms give "yellow ⟺ CCI ≥ 0."
- **CCI DISABLED:** colour falls back to histogram sign — `hist ≥ 0 → YELLOW`,
  `hist < 0 → RED`.

| CCI enabled? | condition | ribbon colour |
|--------------|-----------|---------------|
| yes | CCI ≥ 0 | **YELLOW** (any hist) |
| yes | CCI < 0 | **RED** (any hist) |
| no  | hist ≥ 0 | **YELLOW** |
| no  | hist < 0 | **RED** |

So "DPI is not simply CCI sign" means the *full rule* spans both the CCI-on and CCI-off
cases (and the vote has further components, §4) — but in the **live config (CCI on), the
colour is exactly the CCI sign**, and is **independent of histogram sign**. A *yellow bar
inside a red move* (or vice-versa) is therefore a CCI flip — the "reset" of §5.

**Direction meaning of the colour:**
- **RED ribbon → vote = 1 for SHORT**
- **YELLOW ribbon → vote = 1 for LONG**
- colour not matching the bias → 0

---

## 4. The DPI equation

DPI is a **product of components**. Each component is gated by an `Inp_..._` setting:

- When a component's toggle is **OFF**, that component = **1** (neutral, no influence).
- When **ON**, it evaluates to **1 or 0**.
- All components multiply. **Any 0 → DPI = 0.**

```
DPI = BASE
      × GREEN              (UseGreenHist)        — require GREEN overlay present
      × GREEN_DECEL        (Decel_Filter)        — block when GREEN shrinking/gone
      × CCI_DECEL          (BlockOnDeceleration) — block when CCI momentum decelerating   [needs tracking]
      × RESET_RECOVERY     (RequireResetRecovery)— require reset→recovery cycle (Section 5)
```

- **BASE** — always on. The ribbon colour vs bias (Section 3): RED→1 for SHORT,
  YELLOW→1 for LONG, else 0. `UseCCIReset` selects whether CCI drives the colour
  (CCI on → colour = sign(CCI)) or it falls back to `sign(hist)` (CCI off); `IgnoreCCIForVote`
  forces the raw-hist path. The old same-bar hist-vs-CCI agreement gate is **removed** (§7).
- **GREEN** — Section 6 (`UseGreenHist`).
- **GREEN_DECEL** — block entry when the GREEN overlay is shrinking or has disappeared
  (`Decel_Filter`; engine field `DpiDecelFilterEnabled`).
- **CCI_DECEL** — block entry when CCI momentum is decelerating
  (`BlockOnDeceleration`; **requires `HistTrackingEnabled`**).
- **RESET_RECOVERY** — Section 5 (`RequireResetRecovery`). Reset is detected from the
  **ribbon colour** (a colour flip against trend); **decoupled from `HistTrackingEnabled`**
  (decision 260601, §8/O2,O4).

This is more than three components — DPI is **not** a simple voter like PSAR or MACD. See
Section 4b for the complete inventory and the live wiring/active status of each, because
**an input existing does not mean the component is wired, and being wired does not mean it
is active** (some require a master switch that is currently off).

With every optional toggle off, the equation collapses to `DPI = BASE` — the pure
ribbon-colour vote (yellow = buy, red = sell). That is the simplest form; each enabled
gate raises the bar.

This is the same thing the older docs wrote as
`DPI_PASS = dir_ok AND cci_ok AND green_ok` — a logical AND of toggled gates is identical
to a product where disabled gates are forced to 1. **The structure was right; the
definition of the first gate was wrong** (it used histogram sign instead of ribbon
colour — see Section 7).

---

## 4b. Complete component inventory & wiring status

Each item has **three independent properties** — *(exists as an input) ≠ (wired in the
engine) ≠ (active in RRM_ORG)*. You cannot infer one from another (proof: `AllowTransition`
existed as an input but was dead; `RequireResetRecovery` is wired and `true` yet was dormant
pre-fix — gated off by `HistTrackingEnabled`, now decoupled, §7).

**Entry-vote gates** (`Inp_RRM_ORG_DPI_…`):

| Input | Role | Wired? | Active in RRM_ORG | Notes |
|-------|------|--------|-------------------|-------|
| `Enabled` | master enable of the DPI vote | yes | **ON** (true) | |
| *(BASE — ribbon colour)* | direction | yes, **wrong basis** | ON | currently `sign(hist)`; must be ribbon colour (§3, §7) |
| `UseCCIReset` | **CCI drives ribbon colour** (≡ mc_main `InpEnableCCI`); false → colour = `sign(hist)` | yes | ON (true) | same-bar agreement gate **REMOVED** (§7); no longer gates reset |
| `IgnoreCCIForVote` | bypass CCI, raw hist direction only | yes (3×) | OFF (false) | |
| `UseGreenHist` | require GREEN overlay | yes (4×) | ON (true) | GREEN component (§6) |
| `Decel_Filter` | block when GREEN shrinking/gone | yes — field `DpiDecelFilterEnabled` | OFF (false) | input name ≠ engine field name |
| `BlockOnDeceleration` | block when CCI decelerating | yes (5×) | **DORMANT** + off | needs `HistTrackingEnabled` (off); default false |
| `RequireResetRecovery` | **sole owner of CCI_RESET** (reset→recovery cycle) | yes | ON (true) | reset = **colour flip**; **decoupled from `HistTrackingEnabled`** (260601) |
| `ResetRecoveryBars` | recovery bars after colour returns to trend | yes | (param) | 0 = immediate |
| `ResetRequireGreen` | also require GREEN during recovery | yes (1×) | (param) | sub-gate of reset-recovery |
| `AllowTransition` | (was: "pass when hist rising toward zero") | **REMOVED** | N/A | dead code; purpose subsumed by colour-based BASE (§7) |

**Computation params** (define the ribbon/CCI/green; not gates):
`MacdFast`(8), `MacdSlow`(13), `RedSignalType`(3=EMA13), `RedEMA_A/B/C/D`(5/8/13/21),
`DoubleSmoothFirst/Second`(5/8), `CCI_Period`(13), `CCI_Price`(Typical).

**Tracking subsystem** (master switch + features that are **not** the entry vote):

| Input | Role | Active in RRM_ORG | Notes |
|-------|------|-------------------|-------|
| `HistTrackingEnabled` | **MASTER SWITCH** for the tracking subsystem | **OFF** (false) | gates CCI_DECEL, growth-boost, hist-exit (**not** RESET_RECOVERY — decoupled 260601) |
| `Histogram_Growth_Boost` | feeds **LAYER** momentum, not the DPI vote | needs tracking | |
| `HistMomentumThreshold` | ignore CCI-delta below this | param; needs tracking | |
| `ExitOnHistDisappear` | **EXIT**: close when CCI trend flips | not an entry gate; needs tracking | |
| `ExitThreshold` | **EXIT**: close when \|CCI\| below threshold | EXIT param; needs tracking | |

**The master switch (post-260601 decision).** `HistTrackingEnabled = false` in RRM_ORG. It
gates **`CCI_DECEL`, the growth-boost, and the hist-based exits** — but **no longer
`RESET_RECOVERY`**, which is being decoupled so the reset→recovery cycle runs on
`RequireResetRecovery` alone (decision O2/O4, §8). *Before* the fix, the live DPI entry vote
was effectively `BASE(sign hist) × (CCI same-bar agreement) × GREEN`, with reset/recovery and
deceleration **dormant**. *After* the fix the entry vote becomes
`BASE(ribbon colour) × GREEN × RESET_RECOVERY`, the same-bar agreement gate is gone, and
`CCI_DECEL`/exits remain dormant until `HistTrackingEnabled` is turned on deliberately (§7).

---

## 4c. How DPI evaluates — step-by-step (with equation expansions)

DPI is evaluated once per **closed** bar (shift=1) for the active bias
(`LONG = +1` / `SHORT = −1`). The engine entry point is `Check_DPI(bias, v_shift)`, which
returns `1` (vote passes) or `0` (vote blocks). Evaluation proceeds in this order:

**Step 0 — is DPI in the equation?** If the DPI voter is disabled
(`Inp_RRM_ORG_DPI_Enabled = false` → `Ind_Dpi_Enabled = false`), `Check_DPI` returns pass and
DPI contributes nothing (effectively `1`) to the TS product. Everything below applies only when
DPI is enabled.

**Step 1 — build the ribbon (§2).** From close prices on the closed bar:
```
Blue = EMA(MACD_Fast, close) − EMA(MACD_Slow, close)
Red  = EMA(RedSignalType, Blue)              (or double-smooth)
hist = Blue − Red                            (plotted as Red_Contour)
CCI  = CCI(CCI_Period, CCI_Price)
```

**Step 2 — ribbon COLOUR (§3)** — the single driver of direction:
```
if UseCCIReset (CCI in colour):  colour = YELLOW if CCI  ≥ 0  else RED   (independent of hist)
else (CCI off):                  colour = YELLOW if hist ≥ 0  else RED
```

**Step 3 — BASE (the direction vote):**
```
BASE = 1  if (colour = YELLOW and bias = LONG) or (colour = RED and bias = SHORT)
       0  otherwise
```
BASE is always defined (the ribbon is always yellow or red); it is `0` only when the colour
does not match the bias (§8/O5).

**Step 4 — the enabled gates.** Each component is `1` when its toggle is **off** (no
influence), and `1`/`0` when **on**:
```
GREEN          = 1  if UseGreenHist off         OR GREEN overlay present                       else 0
GREEN_DECEL    = 1  if Decel_Filter off          OR GREEN not shrinking / not gone              else 0
CCI_DECEL      = 1  if BlockOnDeceleration off    OR CCI not decelerating                        else 0   [needs HistTrackingEnabled]
RESET_RECOVERY = 1  if RequireResetRecovery off   OR reset→recovery completed (state ENTRY_ALLOWED) else 0
```

**Step 5 — the product:**
```
DPI = BASE × GREEN × GREEN_DECEL × CCI_DECEL × RESET_RECOVERY
```
Any single `0` ⇒ `DPI = 0` (vote blocks).

### Equation by configuration
| Configuration | Equation |
|---|---|
| Simplest — all optional toggles off | `DPI = BASE` (pure colour vote) |
| Live RRM_ORG (GreenHist on, RequireResetRecovery on; decels off/dormant) | `DPI = BASE × GREEN × RESET_RECOVERY` |
| All gates on | `DPI = BASE × GREEN × GREEN_DECEL × CCI_DECEL × RESET_RECOVERY` |

Each enabled component **lengthens the product** and demands one more `= 1` confirmation, so
the vote becomes progressively stricter — fewer entries, each of higher probability. That is
exactly the `RequireResetRecovery = true` vs `false` trade-off (§5).

### Worked examples (SHORT bias; downtrend; trend colour = RED; GreenHist + RequireResetRecovery on)
| Bar situation | colour | BASE | GREEN | RESET_RECOVERY | DPI |
|---|--------|------|-------|----------------|-----|
| trend resuming: red, GREEN present, reset+recovery completed | RED | 1 | 1 | 1 | **1** |
| red + GREEN present, but **no reset** occurred during the pullback | RED | 1 | 1 | 0 | **0** |
| **yellow** bar mid-pullback (CCI ≥ 0) | YELLOW | 0 | — | — | **0** |
| red, reset+recovery completed, but **GREEN absent** | RED | 1 | 0 | 1 | **0** |

For a LONG bias in an uptrend, swap RED ↔ YELLOW throughout.

---

## 5. CCI_RESET — "a reset must occur to validate the recovery"

`CCI_RESET` is **not** a per-bar "does CCI agree with the histogram this bar" test. It is a
requirement about what happened **during the pullback**, observed purely from the **ribbon
colour**.

**Reset is a ribbon-COLOUR flip against the trend colour.** It is detected from the colour
(`hist_wants_yellow`), not from hist-vs-CCI agreement, and is **independent of where the
ribbon sits relative to the 0-line** — a reset typically occurs during a straddle of the
0-line, but on a strong pullback the colour can flip while the ribbon is still wholly above
or below 0. The detector only cares that the colour changed.

**The two pullback scenarios (illustrated for a SELL / downtrend, trend colour = RED):**

- **Scenario 1 — no reset:** the ribbon stays RED for the whole pullback. Valid on BASE, but
  the *weaker* case: lower probability that momentum resumes in the trend direction.
- **Scenario 2 — reset:** the ribbon flips to YELLOW for one or more bars mid-pullback
  (the **reset**), then returns to RED on resumption. The *stronger* case: higher
  probability of good momentum.

**Behaviour of the toggle (`Inp_RRM_ORG_DPI_RequireResetRecovery`):**

- **OFF →** `CCI_RESET = 1` always. Both scenarios pass on BASE alone. You take weak and
  strong setups alike.
- **ON →** `CCI_RESET = 1` **only if** a reset (a colour flip against trend) appeared during
  the pullback **and** the market is now in a confirmed recovery showing the proper trend
  colour again. If **no reset ever appeared** (Scenario 1), `CCI_RESET = 0` and DPI blocks
  — *even though the current bar is RED and BASE = 1*. The absence of a reset fails it.

So `RequireResetRecovery = true` filters for the higher-probability reset-then-recover setups
and rejects the no-reset ones. This is a **strict filter**: with it on, an entry that did not
follow a completed reset→recovery is blocked even when the colour matches bias, and the state
returns to IDLE after each trade (`ResetDPIResetState()`).

**Recovery validation — colour + bar count only (no EMAs).** Recovery is confirmed by the
ribbon colour returning to the trend colour, held for `ResetRecoveryBars` bars (0 = the first
trend-colour bar), and optionally also requiring GREEN present (`ResetRequireGreen`). **No
EMA-based recovery check is used** (decision O3, §8) — DPI stays self-contained on the ribbon.

This is conceptually the **reset → recovery state machine** already present (but dormant)
in the engine: `m_dpi_reset_state` cycling IDLE → RESET_DETECTED → RECOVERY_COUNTING →
ENTRY_ALLOWED. The fix re-bases its edge detection from `dpi_macd_agree` (hist-sign vs
CCI-sign) onto the **ribbon colour** (`hist_wants_yellow` vs trend colour), so the machine
detects exactly the colour flips described above.

---

## 6. GREEN — momentum confirmation

GREEN tracks momentum alignment (not direction); it appears on both sides of zero:
- **Above zero:** bullish momentum confirmed (Blue > 0 AND hist > 0).
- **Below zero:** bearish momentum confirmed (Blue < 0 AND hist < 0).

**GREEN magnitude** = `min(|Blue|, |hist|)` — the area from the 0-line to the closer of
{Blue, contour} (the "confirmed" portion of the move). The engine computes the same value
(`out_green_mag_*` in `ComputeDPIMainHist`), so A and B agree on GREEN presence and size.

**GREEN momentum lifecycle** (identical above and below zero):
1. **Appears** — momentum impulse begins; Blue and hist have aligned on the same side. The
   move is real, not a fake-out — direction confirmed.
2. **Grows** — momentum accelerating; both Blue and hist expanding. Strongest phase for
   entries (best follow-through).
3. **Declines** — momentum decelerating; the smaller of Blue/hist contracts even if the
   larger still expands. Early warning of exhaustion.
4. **Vanishes** — **OB/OS reached.** Blue and hist no longer aligned (hist crossed zero, or
   Blue crossed zero). A pullback/reversal is likely; open profit is at risk. GREEN gone in a
   bullish context = overbought; in a bearish context = oversold — either way, expect a
   retracement. (This is the *pullback context* around a reset — §5/§8 O1 — not the reset
   detector itself.)

**Behaviour of the toggle (`Inp_RRM_ORG_DPI_UseGreenHist`):**
- **OFF →** `GREEN = 1` always (no influence).
- **ON →** `GREEN = 1` when the GREEN overlay is present, else 0.

GREEN strengthens the vote when required; its disappearance lowers probability (and can
drive a separate exit — see §6b), but with the toggle off it does not gate entries.

---

## 6b. GREEN-driven tracking & exit features (`HistTrackingEnabled` subsystem)

These are **not** part of the entry vote (§4c); they are the exit-/filter-side features
around it. Two of them (`CCI_DECEL`, the GREEN-disappear exit) are gated by the
`HistTrackingEnabled` master switch (off in RRM_ORG today, §4b/§7); `GREEN_DECEL` is **not**
(it needs only `Ind_Dpi_Enabled`). Documented here so the single source covers them; faithful
to the engine, not the old vote model.

- **Block entry on GREEN shrinking — `DpiDecelFilterEnabled` (GREEN_DECEL).** Blocks a new
  entry when GREEN is declining bar-over-bar (`GREEN[shift] < GREEN[shift+1]`), preventing
  late entries after the momentum peak. Needs only `Ind_Dpi_Enabled` (**not**
  `HistTrackingEnabled`). This is the `GREEN_DECEL` factor of §4.
- **Block entry on CCI deceleration — `DPI_BlockOnDeceleration` (CCI_DECEL).** Blocks entries
  when CCI shows decreasing momentum across `DPI_HistDecelLookback` bars — a more granular
  check than GREEN shrinking. **Needs `HistTrackingEnabled`.** This is the `CCI_DECEL` factor.
- **Close on GREEN disappearance — `DPI_ExitOnHistDisappear` (EXIT, not a vote).** Force-closes
  an open position on the bar GREEN vanishes (OB/OS → expected pullback → lock in gains).
  **Direction-neutral**: works for BUY (GREEN was above zero) and SELL (GREEN was below zero).
  Needs `HistTrackingEnabled`. Optional `DPI_ExitThreshold` also closes when `|CCI|` drops
  below a floor (0 = disabled). Tracked via GREEN *presence* (`m_dpi_hist_green_present`),
  **not** CCI sign — the 260521 fix that ended the all-SHORTs-exit-immediately bug (§13).

### Signal-strength hierarchy (interpretation)

1. **Strongest** — trend colour + GREEN growing + no reset active: full alignment, impulse phase.
2. **Strong** — trend colour + GREEN present but flat: confirmed, not accelerating.
3. **Weakening** — GREEN shrinking: still directional, momentum fading — avoid new entries.
4. **Exhausted** — GREEN vanished: OB/OS — close positions, expect pullback.
5. **Reset active** — colour flipped against trend (the §5 reset): pullback in progress;
   under `RequireResetRecovery` this is what must occur, then recover, to validate entry.

---

## 7. Divergence from current implementation (to be corrected)

The engine (`Check_DPI` in `SEA_SignalEngine.mqh`) and the older docs currently implement:

| Component | Current (WRONG) | Canonical (this doc) |
|-----------|-----------------|----------------------|
| BASE / direction | `dir_ok = sign(histogram) == bias` | ribbon **colour** vs bias (Section 3) |
| CCI | `cci_ok = same-bar (hist sign == CCI sign)` agreement gate | gate **removed**; CCI instead drives the ribbon **colour** in BASE (`UseCCIReset` ≡ mc_main `InpEnableCCI`) |
| GREEN | `green_ok` hard gate when `UseGreenHist` | unchanged — correct |
| Reset→recovery state machine | present but **dormant** (needs `RequireResetRecovery && HistTrackingEnabled && UseCCIReset`); edges via `dpi_macd_agree` | this **is** `CCI_RESET`; active mechanism, gated by **`RequireResetRecovery` alone**, edges re-based on **ribbon colour** |

The practical symptom: a bar where the histogram is positive (`hist > 0`) but the ribbon
is RED (CCI override) is a valid SHORT under this spec (BASE = red = 1 for short), but the
current code blocks it because `sign(hist) = +1 ≠ short`. The fix is to read **ribbon
colour** for BASE.

Also note: `Inp_RRM_ORG_DPI_AllowTransition` is **dead code** — declared and assigned
everywhere but never read by any evaluation (read 0× in `SEA_SignalEngine.mqh`). **Decision
(260601): remove it.** Its original purpose was a workaround for the wrong hist-sign maths —
allowing a BUY when the ribbon was YELLOW but sitting *below* the 0-line (yellow = buy
momentum despite `hist < 0`), and symmetrically for SELL. Under colour-based BASE this is
already handled: a yellow bar votes long regardless of which side of the 0-line it sits on,
so `AllowTransition` is redundant.

**Master-switch decoupling (the live-gap fix).** Previously `HistTrackingEnabled = false`
gated both `RESET_RECOVERY` and `CCI_DECEL`, so even with `RequireResetRecovery = true` the
reset→recovery cycle never ran. **Decision (260601):** decouple `RESET_RECOVERY` from
`HistTrackingEnabled` so it runs on `RequireResetRecovery` alone — the reset needs only the
ribbon colour, which is always computed. `HistTrackingEnabled` is **retained for `CCI_DECEL`,
the GREEN-disappear exit, and growth-boost/green-tracking** (those genuinely need the CCI/GREEN
tracking buffers). It stays OFF in RRM_ORG until those exit/decel features are wanted, and
enabling it must not be required to make `CCI_RESET` work.

---

## 8. Open items — RESOLVED with USER (260601)

The four items below were verified against source and resolved with USER. Original questions
retained for history; resolutions in **bold**.

- **O1 — Reset detection source.** *(Q: detect reset from ribbon colour or `dpi_macd_agree`?)*
  **RESOLVED:** reset = **ribbon-colour flip** against the trend colour (one or more bars),
  detected from `hist_wants_yellow`, **not** `dpi_macd_agree`. It is independent of 0-line
  geometry (can occur while the ribbon is wholly above/below 0 on a strong pullback). The
  straddle / GREEN-disappearance is the surrounding *pullback context*, **not** the detector.

- **O2 — Toggle mapping.** *(Q: which input gates `CCI_RESET`?)* **RESOLVED:**
  **`RequireResetRecovery` is the sole owner** of the reset→recovery requirement.
  `UseCCIReset` is repurposed to mean "CCI drives the ribbon colour" (≡ mc_main
  `InpEnableCCI`). The two no longer overlap; the same-bar agreement gate is removed.

- **O3 — EMA recovery check.** *(Q: add EMA confirmation to recovery?)* **RESOLVED: NO.**
  Recovery is confirmed by colour-return + `ResetRecoveryBars` count (+ optional
  `ResetRequireGreen`). No EMA logic is wired into DPI — it stays self-contained on the ribbon.

- **O4 — CCI-in-colour vs CCI-as-gate.** *(Q: what does `UseCCIReset` control?)* **RESOLVED:**
  `UseCCIReset` controls **CCI inside the colour calculation only** (on → colour = sign(CCI);
  off → colour = sign(hist)). The reset *requirement* lives on `RequireResetRecovery`.
  `HistTrackingEnabled` is **decoupled from reset** and kept only for `CCI_DECEL` / GREEN-exit
  / growth-boost (those need the tracking buffers).

- **O5 — BASE has no neutral.** Colour is defined whether or not the ribbon touches the
  0-line, so BASE is always ±1 (it is 0 only when colour ≠ bias). A flat bar (`hist=0`)
  votes per the colour rule (CCI sign when CCI on) — faithful to mc_main; behaviourally
  different from the old `sign(hist)` which could be 0.

---

## 9. Implementation architecture (decided)

- **B — PRIMARY (live trading):** DPI is computed **inside the EA engine**
  (`Check_DPI` / `ComputeDPIMainHist`). This is the authoritative path for entries. Native
  speed, no runtime indicator dependency. `ComputeDPIMainHist(v_shift, …)` computes Blue/Red/
  hist with the same math as the standalone (§2) and returns the contract:
  - `out_hist_cur` / `out_hist_prev` — hist (`Blue − Red`) at the current and previous bar.
  - `out_green` — Blue and hist on the same side of zero (GREEN present).
  - `out_green_mag_cur` / `out_green_mag_prev` — `min(|Blue|, |hist|)` when aligned, else 0.
  - `out_macd_agree` — CCI/hist agreement flag (legacy; the same-bar gate it fed is being
    removed, §7 — CCI now drives the colour instead).

  GREEN presence is tracked per-bar in `UpdateDPIHistogramState()` and passed to the Trade
  Executor; the GREEN-disappear exit (§6b) uses `m_dpi_hist_green_present` (GREEN presence),
  **not** the CCI-sign `m_dpi_hist_trend`.
- **A — CHART VISUAL (independent inline twin; NO iCustom):** the standalone
  `SEA_IND_DPI_mc_main.mq5` stays for the on-chart ribbon. The EA does **not** read it via
  `iCustom` — that dependency was deliberately rejected for macOS/Wine robustness (§13). A and B
  are two **separate inline implementations** kept verdict-identical by construction:
  - **CCI** is a windowed SMA (`(price − SMA)/(0.015·mean_dev)`) over `period` bars — no EMA,
    no warmup — so it is **bit-identical** in both. In the live config colour = sign(CCI),
    hence **BASE and the reset detector are exactly equal** in A and B regardless of anything else.
  - **Blue / Red / hist** use identical EMA math and seeding (Fast/Slow = `close` at the oldest
    bar → Blue=0, Red=0; same alphas/recursion). The only difference is warmup depth: `mc_main`
    warms over full chart history; the engine warms over a bounded window. The engine therefore
    uses a **≥500-bar EMA warmup** so its recursive-EMA seed residual underflows (~1e-21 even for
    EMA21) and Blue/Red/hist **bit-match** `mc_main` — making GREEN (and hist-based colour, if CCI
    is ever disabled) exact too. `mc_main` is the reference and needs no change.
- **A ≡ B is by construction, not by runtime coupling.** The scanner inspector readout
  `I:NO(DPI:reason hist=…)` is the standing cross-check: it shows the engine's DPI verdict
  next to the mc_main ribbon on the same chart, so any A-vs-B divergence is visible
  immediately.

---

## 10. EA settings (PRESET_RRM_ORG)

- `Inp_RRM_ORG_DPI_Enabled` — enable the DPI voter in the TS equation (default: true).
- `Inp_RRM_ORG_DPI_UseCCIReset` — CCI drives the ribbon **colour** (on → colour = sign(CCI);
  off → colour = sign(hist)). ≡ mc_main `InpEnableCCI`. (Not the reset component — see below.)
- `Inp_RRM_ORG_DPI_RequireResetRecovery` — enable the **`CCI_RESET`** reset→recovery component
  (Section 5); sole owner, decoupled from `HistTrackingEnabled`.
- `Inp_RRM_ORG_DPI_IgnoreCCIForVote` — bypass CCI in the vote (raw direction only).
- `Inp_RRM_ORG_DPI_UseGreenHist` — enable the `GREEN` component (Section 6).
- `Inp_RRM_ORG_DPI_AllowTransition` — **REMOVED** (dead code; purpose subsumed by
  colour-based BASE — see Section 7).
- Core params: `DPI_MACD_Fast` (8), `DPI_MACD_Slow` (13), `DPI_RedSignalType` (3 = EMA13),
  `DPI_CCI_Period` (13), `DPI_CCI_AppliedPrice` (Typical). Single-sourced as
  `SEA_DEF_DPI_*` in `SEA_Config.mqh`.

---

## 11. Standalone indicator files

- `SEA_IND_DPI_mc_main.mq5` — MACD+CCI core, **with** GREEN overlay (the live/charted one).
- `SEA_IND_DPI_mc_simple.mq5` — MACD+CCI core, no GREEN.
- `SEA_IND_DPI_tm_simple.mq5` — TSI+MACD (William Blau Ergodic) core — different math.

The EA's internal DPI (B) mirrors **`mc_main`**.

**mc_main plot/buffer structure** (8 plots; 4 ribbon buffers give independent colour per side
when Blue and hist straddle zero — see §2 opposite-sides):

```
Plot 0: Blue_MACD_Core   (Blue lead line)        Plot 4: Hist_Red_Neg     (red ribbon, neg side)
Plot 1: Red_Signal       (smoothed Blue)         Plot 5: Hist_Yellow_Pos  (yellow ribbon, pos side)
Plot 2: Red_Contour      (hist = Blue − Red)      Plot 6: Hist_Yellow_Neg  (yellow ribbon, neg side)
Plot 3: Hist_Red_Pos     (red ribbon, pos side)   Plot 7: Hist_Green       (GREEN overlay)
```

**EA ↔ indicator parameter mapping** (the A≡B contract; defaults shown):

| EA setting | mc_main input | Default | Purpose |
|------------|---------------|---------|---------|
| `DPI_MACD_Fast` | `InpFastEMA` | 8 | Blue fast EMA |
| `DPI_MACD_Slow` | `InpSlowEMA` | 13 | Blue slow EMA |
| `DPI_RedSignalType` | `InpRedLineType` | 3 (EMA13) | Red signal calculation |
| `DPI_CCI_Period` | `InpCCIPeriod` | 13 | CCI period |
| `DPI_CCI_AppliedPrice` | `InpCCIPrice` | Typical | CCI price |
| `DPI_UseCCIReset` | `InpEnableCCI` | true | **CCI drives ribbon colour** (post-260601, §3/§8 O4) |
| `DPI_UseGreenHist` | `InpEnableGreen` | true | GREEN present required in vote (engine); visual toggle (indicator) |

Note the colour parameters and the `InpEnableGreen` *visual* toggle are standalone-only;
disabling GREEN's plot in the indicator does **not** change the EA's GREEN vote (B computes
GREEN internally regardless). To drop GREEN from the vote, set `DPI_UseGreenHist = false`.

---

## 12. Files this supersedes (consolidated 260601)

All DPI logic now lives **only** in this file. The following are superseded; their unique,
still-correct content (GREEN lifecycle/magnitude, exit/decel features, EA↔indicator mapping,
buffer/plot structure) has been folded in (§6, §6b, §9, §11). Their **old vote model**
(`dir_ok = sign(hist) AND cci_ok(same-bar) AND green_ok`) is deliberately **not** carried
over — it is the implementation §3/§4c/§7 correct.

- `README_SEA_DPI_mc_main_260521-14.md` (= `_OLD.md` = `_OLD-.md`, byte-identical triplet) —
  folded; archived in `Readme/_OLD_README/`.
- `README_SEA_SIGNAL_REFERENCE_DPI_SECTION_260521-14.md` (= `_OLD` = `_OLD-`, triplet) —
  strict subset of the above, nothing additional; archived in `Readme/_OLD_README/`.
- `README_SEA_DPI_mc_main_260509-01.md`, `…_260510-01.md` — earlier subsets; archived.
- `_OLD_DPI_VPRR/DPI_v20_wrong_*.md`, `_OLD_DPI_VPRR/DPI_V21_wrong_*.md` — analysis of
  known-wrong versions; nothing to fold; already archived.

The DPI subsection in `README_SEA_SIGNAL_REFERENCE.md` is reduced to a pointer to this file.
DPI mentions in `README_SEA_SYSTEM.md`, `README_SEA_VETO_REFERENCE.md`, and
`README_SEA_PARAMETER_MAPPING.md` should point here rather than restating the logic
(parameter *listing* in PARAMETER_MAPPING is fine — that is "when needed").

---

## 13. History / Change Log

**260601 — canonical consolidation & logic correction (this file).**
- Verified §2/§3 line-by-line against `SEA_IND_DPI_mc_main.mq5`; resolved §8 open items
  O1–O5 with USER.
- Locked: BASE = ribbon **colour** (not `sign(hist)`); same-bar hist-vs-CCI agreement gate
  **removed**; `UseCCIReset` = CCI-in-colour; `RequireResetRecovery` = sole owner of
  CCI_RESET with reset detected as a **colour flip**, **decoupled from `HistTrackingEnabled`**;
  EMA recovery check **not** added; `AllowTransition` **removed** (dead).
- Consolidated `README_SEA_DPI_mc_main*` and `…_SIGNAL_REFERENCE_DPI_SECTION*` into this file
  (§12); reduced the `README_SEA_SIGNAL_REFERENCE.md` DPI section to a pointer.

**260601 — A↔B parity audit + iCustom rejection (clarified).** Confirmed line-by-line that
the engine's inline DPI and `SEA_IND_DPI_mc_main.mq5` use identical formulas: CCI bit-identical
(windowed SMA); Blue/Red/hist same EMA math + seeding. `iCustom` was **never** wired and is
deliberately avoided (handle-free design — "safe under MQL5 on macOS/Wine"; an earlier 260509/10
`iCustom`-read approach was abandoned). The one parity gap found — the engine's short EMA warmup
(was `+7` bars) vs `mc_main`'s full-history warmup, which could flip GREEN-presence at borderline
zero-crossings — was closed by raising the engine warmup to **+500 bars** (`bars_needed` in
`ComputeDPIMainHist`), so Blue/Red/hist now bit-match the indicator. §9 corrected accordingly
(was previously, in error, describing an `iCustom` fallback).


- mc_simple / v29 — CCI resets working, gaps, no GREEN.
- v30_14 — continuous ribbon, GREEN correct, no CCI resets.
- v31_18 — four ribbon buffers, CCI logic bug.
- v31_20 — CCI logic fixed; GREEN not plotting (plots=7 bug).
- v31_25 — all features operational (base for `DPI_mc_main.mq5`).
- mc_main — GREEN-off visual fix (clean `0→Blue` ribbon when `InpEnableGreen=false`).

**EA v1-04 (260521) — SHORT-exit bug fix.** `CheckDPIHistogramExit()` checked
`m_dpi_hist_trend != 1` (CCI sign); for SHORTs CCI is correctly negative, so `-1 != 1` was
always true → every SHORT closed on bar 1 (0% SHORT win-rate). Fixed to track actual GREEN
**presence** via `ComputeDPIMainHist()` (direction-neutral) and pass
`m_dpi_hist_green_present` through Signal Engine → Executor.
