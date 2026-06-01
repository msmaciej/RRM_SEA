# DPI Signal Reference — Canonical Logic Specification

> **Status:** CANONICAL. This file is the single source of truth for DPI vote logic.
> It supersedes the DPI descriptions in `README_SEA_DPI_mc_main.md`,
> `README_SEA_SIGNAL_REFERENCE_DPI_SECTION.md`, and any dated copies
> (`*_260521-14.md`). Those should be archived once this is adopted.
>
> **Important:** Section 7 ("Divergence from current implementation") records that
> the code and the older docs do **not** yet implement the logic below. This file
> states the *intended* logic (the design); the engine and the indicator are to be
> corrected to match it.

---

## 1. Purpose

DPI (Dynamic Price Index) is the **I-factor momentum-direction voter**. Its output is a
single gate: `DPI = 1` (vote passes) or `DPI = 0` (vote blocks), evaluated for the
current bias (LONG or SHORT).

The vote is driven by the **ribbon (histogram) colour** the DPI indicator paints, with
optional, independently-toggled enhancement gates that make the vote progressively
stricter.

---

## 2. Indicator architecture (how the ribbon is built)

These definitions are transcribed from `SEA_IND_DPI_mc_main.mq5` (lines ~457–545).
**Verify line-by-line in the implementation chat** — they must reflect source, not the
older docs (the previous "ribbon = Blue − Red" description was wrong).

- **Blue line (LEAD):** fast MACD core = `EMA(Fast) − EMA(Slow)` of close (`g_BlueCore`).
- **Red signal line (FOLLOW):** smoothed signal = EMA of Blue (`g_RedSignal`;
  configurable EMA5/8/13/21 or Double).
- **`hist`:** `Blue − Red` — this is the value plotted as the **Red_Contour line**
  (`g_RedContour`), i.e. one boundary. **It is *not* "the ribbon" by itself.**
- **Ribbon histogram (the coloured bars):** a **separate construction** (lines ~490–525),
  the **filled band between the Blue line and the contour**, *not* the bare `Blue − Red`
  difference:
  - Blue and hist on the **same side** of zero → bar extent = the value **further from
    zero** of `{Blue, hist}` (`max` above zero / `min` below zero).
  - Blue and hist on **opposite sides** → the band **spans from Blue across zero to hist**
    (positive portion and negative portion drawn separately).
  So the rendered ribbon's *height/geometry* depends on **both** Blue and hist, not simply
  where Blue sits relative to Red.
- **Ribbon colour (red/yellow):** decided separately by `hist_wants_yellow`
  (lines ~480–488) — see §3. The colour is independent of the band geometry above.
- **GREEN overlay (`g_HistGreen`):** appears only when Blue and hist are on the **same side**
  of zero, and is **bounded by the 0-line on one edge and by whichever of {Blue-lead,
  Red-contour} is *closest to the 0-line* on the other edge** — so its capping line can be
  either Blue or the contour, whichever is nearer zero (not a fixed one):
  - Above zero → `MathMin(Blue, hist)` — fills from 0 up to the **lower** of the two.
  - Below zero → `MathMax(Blue, hist)` — fills from 0 down to the **higher** (least negative).
  - Otherwise absent (`EMPTY_VALUE`).
  Momentum-strength overlay, not a direction.
- **Zero line:** reference for "side" (above / below).

---

## 3. Ribbon colour (the BASE signal)

Colour is decided per bar **solely** by `hist_wants_yellow` (mc_main lines 480–488); every
bar-rendering branch (lines 536–600+) just tests that one boolean, so nothing else colours
the bars:

```
if (hist >= 0):  hist_wants_yellow = !(CCI_enabled && CCI <  0)
else (hist < 0): hist_wants_yellow =  (CCI_enabled && CCI >= 0)
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
      × RESET_RECOVERY     (RequireResetRecovery)— require reset→recovery cycle (Section 5) [needs tracking]
```

- **BASE** — always on. The ribbon colour vs bias (Section 3): RED→1 for SHORT,
  YELLOW→1 for LONG, else 0. CCI handling (`UseCCIReset` / `IgnoreCCIForVote`) shapes the
  colour and CCI treatment that feed BASE.
- **GREEN** — Section 6 (`UseGreenHist`).
- **GREEN_DECEL** — block entry when the GREEN overlay is shrinking or has disappeared
  (`Decel_Filter`; engine field `DpiDecelFilterEnabled`).
- **CCI_DECEL** — block entry when CCI momentum is decelerating
  (`BlockOnDeceleration`; **requires `HistTrackingEnabled`**).
- **RESET_RECOVERY** — Section 5 (`RequireResetRecovery`; **requires `HistTrackingEnabled`**).

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
exists but is dead; `RequireResetRecovery` is wired and `true` but dormant).

**Entry-vote gates** (`Inp_RRM_ORG_DPI_…`):

| Input | Role | Wired? | Active in RRM_ORG | Notes |
|-------|------|--------|-------------------|-------|
| `Enabled` | master enable of the DPI vote | yes | **ON** (true) | |
| *(BASE — ribbon colour)* | direction | yes, **wrong basis** | ON | currently `sign(hist)`; must be ribbon colour (§3, §7) |
| `UseCCIReset` | CCI override in colour / reset gating | yes (8×) | ON (true) | also currently drives a same-bar agreement gate (to remove, §7) |
| `IgnoreCCIForVote` | bypass CCI, raw hist direction only | yes (3×) | OFF (false) | |
| `UseGreenHist` | require GREEN overlay | yes (4×) | ON (true) | GREEN component (§6) |
| `Decel_Filter` | block when GREEN shrinking/gone | yes — field `DpiDecelFilterEnabled` | OFF (false) | input name ≠ engine field name |
| `BlockOnDeceleration` | block when CCI decelerating | yes (5×) | **DORMANT** + off | needs `HistTrackingEnabled` (off); default false |
| `RequireResetRecovery` | reset→recovery cycle (**your CCI_RESET**) | yes (2×) | **DORMANT despite `true`** | gated by `HistTrackingEnabled` (off) |
| `ResetRecoveryBars` | recovery bars after CCI flip-back | yes | (param) | 0 = immediate |
| `ResetRequireGreen` | also require GREEN during recovery | yes (1×) | (param) | sub-gate of reset-recovery |
| `AllowTransition` | "pass when hist rising toward zero" | **NO — dead** | N/A | `m_settings.DPI_AllowTransition` read 0× |

**Computation params** (define the ribbon/CCI/green; not gates):
`MacdFast`(8), `MacdSlow`(13), `RedSignalType`(3=EMA13), `RedEMA_A/B/C/D`(5/8/13/21),
`DoubleSmoothFirst/Second`(5/8), `CCI_Period`(13), `CCI_Price`(Typical).

**Tracking subsystem** (master switch + features that are **not** the entry vote):

| Input | Role | Active in RRM_ORG | Notes |
|-------|------|-------------------|-------|
| `HistTrackingEnabled` | **MASTER SWITCH** for the tracking subsystem | **OFF** (false) | gates RESET_RECOVERY, CCI_DECEL, growth-boost, hist-exit |
| `Histogram_Growth_Boost` | feeds **LAYER** momentum, not the DPI vote | needs tracking | |
| `HistMomentumThreshold` | ignore CCI-delta below this | param; needs tracking | |
| `ExitOnHistDisappear` | **EXIT**: close when CCI trend flips | not an entry gate; needs tracking | |
| `ExitThreshold` | **EXIT**: close when \|CCI\| below threshold | EXIT param; needs tracking | |

**CRITICAL — the master switch.** `HistTrackingEnabled = false` in RRM_ORG. Because both
`RESET_RECOVERY` and `CCI_DECEL` are gated by it (`… && HistTrackingEnabled && …`), they
**do not run** — even though `RequireResetRecovery = true`. So the *live* DPI entry vote
today is effectively only `BASE × (CCI same-bar agreement) × GREEN`, with the reset/recovery
and deceleration logic **dormant**. Enabling the reset/recovery you intend requires
`HistTrackingEnabled = true` **and** the correctness fixes in Section 7.

---

## 5. CCI_RESET — "a reset must occur to validate the recovery"

`CCI_RESET` is **not** a per-bar "does CCI agree with the histogram this bar" test. It is a
requirement about what happened **during the pullback**, observed purely from the ribbon
colour.

**The two pullback scenarios (illustrated for a SELL / downtrend, trend colour = RED):**

- **Scenario 1 — no reset:** the ribbon stays RED for the whole pullback. Valid on BASE,
  but the *weaker* case: lower probability that momentum resumes in the trend direction.
- **Scenario 2 — reset:** the ribbon flips to YELLOW for one or more bars mid-pullback
  (the **reset**), then returns to RED on resumption. The *stronger* case: higher
  probability of good momentum.

**Behaviour of the toggle (`Inp_RRM_ORG_DPI_UseCCIReset`):**

- **OFF →** `CCI_RESET = 1` always. Both scenarios pass on BASE alone. You take weak and
  strong setups alike.
- **ON →** `CCI_RESET = 1` **only if** a reset (a yellow interruption) appeared during the
  pullback **and** the market is now in a confirmed recovery showing the proper trend
  colour again. If **no reset ever appeared** (Scenario 1), `CCI_RESET = 0` and DPI blocks
  — *even though the current bar is RED and BASE = 1*. The absence of a reset fails it.

So `UseCCIReset = true` filters for the higher-probability reset-then-recover setups and
rejects the no-reset ones.

**Recovery validation also checks the EMAs.** Recovery is confirmed by the ribbon colour
returning to the trend colour **and** the market (EMA) state confirming recovery — not by
ribbon colour alone. (See Open Item O3.)

This is conceptually the **reset → recovery state machine** already present (but dormant)
in the engine: `m_dpi_reset_state` cycling IDLE → RESET_DETECTED → RECOVERY → ENTRY_ALLOWED.

---

## 6. GREEN — momentum confirmation

GREEN tracks momentum alignment (not direction); it appears on both sides of zero:
- **Above zero:** bullish momentum confirmed (Blue > 0 AND hist > 0).
- **Below zero:** bearish momentum confirmed (Blue < 0 AND hist < 0).

Lifecycle within a move: **appears** (impulse starting) → **grows** (accelerating,
strongest for entries) → **declines** (decelerating) → **vanishes** (OB/OS, pullback
likely).

**Behaviour of the toggle (`Inp_RRM_ORG_DPI_UseGreenHist`):**
- **OFF →** `GREEN = 1` always (no influence).
- **ON →** `GREEN = 1` when the GREEN overlay is present, else 0.

GREEN strengthens the vote when required; its disappearance lowers probability (and can
drive a separate exit — see related `DPI_ExitOnHistDisappear`), but with the toggle off it
does not gate entries.

---

## 7. Divergence from current implementation (to be corrected)

The engine (`Check_DPI` in `SEA_SignalEngine.mqh`) and the older docs currently implement:

| Component | Current (WRONG) | Canonical (this doc) |
|-----------|-----------------|----------------------|
| BASE / direction | `dir_ok = sign(histogram) == bias` | ribbon **colour** vs bias (Section 3) |
| CCI | `cci_ok = same-bar (hist sign == CCI sign)` agreement gate | reset is the colour override (in BASE); `CCI_RESET` = reset-then-recovery requirement (Section 5) |
| GREEN | `green_ok` hard gate when `UseGreenHist` | unchanged — correct |
| Reset→recovery state machine | present but **dormant** (needs `RequireResetRecovery && HistTrackingEnabled && UseCCIReset`) | this **is** `CCI_RESET`; must be the active mechanism |

The practical symptom: a bar where the histogram is positive (`hist > 0`) but the ribbon
is RED (CCI override) is a valid SHORT under this spec (BASE = red = 1 for short), but the
current code blocks it because `sign(hist) = +1 ≠ short`. The fix is to read **ribbon
colour** for BASE.

Also note: `Inp_RRM_ORG_DPI_AllowTransition` is currently **dead code** — declared and
assigned everywhere but never read by any evaluation. It must either be implemented
deliberately or removed; it has no effect today.

**Master-switch dormancy (the biggest live gap).** `HistTrackingEnabled = false` in
RRM_ORG, and it gates both `RESET_RECOVERY` and `CCI_DECEL`. So even though
`RequireResetRecovery = true`, the reset→recovery cycle **never runs** in the live config —
the input is on, the feature is off. Any correction that makes `CCI_RESET` work must turn
`HistTrackingEnabled` on (and re-validate that the tracking subsystem behaves as intended
across all its sub-features, since enabling it also activates `CCI_DECEL`, the growth-boost,
and the hist-based exits).

---

## 8. Open items to reconcile against code (do NOT assume — verify with USER + source)

- **O1 — Reset detection source.** The reset must be detected from the **ribbon colour**
  (yellow appearing during the pullback). The existing state machine detects edges via
  `dpi_macd_agree` (hist-sign vs CCI-sign), which is *not identical* to a colour flip in
  all cases (e.g. when the histogram itself crosses zero during the pullback). Confirm
  whether the state machine's reset detection should be **re-based on ribbon colour**.

- **O2 — Toggle mapping.** Confirm exactly which `Inp_..._` settings gate `CCI_RESET`
  (today the state machine needs `RequireResetRecovery && HistTrackingEnabled &&
  UseCCIReset`; the intent above attaches the component to `UseCCIReset`). Reconcile to a
  single clear toggle for the component.

- **O3 — EMA recovery check.** Confirm whether the EMA-based recovery confirmation
  ("validate recovery state of the market (EMAs) with DPI") already exists in the state
  machine or must be added.

- **O4 — CCI-in-colour vs CCI-as-gate.** Confirm whether `UseCCIReset` controls the CCI
  override **inside the colour calculation**, the reset-requirement **gate**, or both, and
  wire consistently.

---

## 9. Implementation architecture (decided)

- **B — PRIMARY (live trading):** DPI is computed **inside the EA engine**
  (`Check_DPI` / `ComputeDPIMainHist`). This is the authoritative path for entries. Native
  speed, no runtime indicator dependency.
- **A — FALLBACK / visual:** the standalone `SEA_IND_DPI_mc_main.mq5` stays (USER needs the
  on-chart visual) and can be read by the EA via `iCustom` if the internal DPI fails. It is
  modified only as needed so that **A and B produce identical verdicts**.
- **Both DPIs must behave identically.** The scanner inspector readout
  `I:NO(DPI:reason hist=…)` is the standing cross-check: it shows the engine's DPI verdict
  next to the mc_main ribbon on the same chart, so any A-vs-B divergence is visible
  immediately.

---

## 10. EA settings (PRESET_RRM_ORG)

- `Inp_RRM_ORG_DPI_Enabled` — enable the DPI voter in the TS equation (default: true).
- `Inp_RRM_ORG_DPI_UseCCIReset` — enable the `CCI_RESET` component (Section 5).
- `Inp_RRM_ORG_DPI_IgnoreCCIForVote` — bypass CCI in the vote (raw direction only).
- `Inp_RRM_ORG_DPI_UseGreenHist` — enable the `GREEN` component (Section 6).
- `Inp_RRM_ORG_DPI_AllowTransition` — **currently dead code** (see Section 7).
- Core params: `DPI_MACD_Fast` (8), `DPI_MACD_Slow` (13), `DPI_RedSignalType` (3 = EMA13),
  `DPI_CCI_Period` (13), `DPI_CCI_AppliedPrice` (Typical). Single-sourced as
  `SEA_DEF_DPI_*` in `SEA_Config.mqh`.

---

## 11. Standalone indicator files

- `SEA_IND_DPI_mc_main.mq5` — MACD+CCI core, **with** GREEN overlay (the live/charted one).
- `SEA_IND_DPI_mc_simple.mq5` — MACD+CCI core, no GREEN.
- `SEA_IND_DPI_tm_simple.mq5` — TSI+MACD (William Blau Ergodic) core — different math.

The EA's internal DPI (B) mirrors **`mc_main`**.

---

## 12. Files this supersedes (archive after adoption)

- `README_SEA_DPI_mc_main.md` (fold colour-model / lifecycle detail in here if still wanted)
- `README_SEA_SIGNAL_REFERENCE_DPI_SECTION.md`
- `README_SEA_DPI_mc_main_260521-14.md`
- `README_SEA_SIGNAL_REFERENCE_DPI_SECTION_260521-14.md`
- `_OLD_DPI_VPRR/DPI_v20_wrong_*.md`, `_OLD_DPI_VPRR/DPI_V21_wrong_*.md` (already archived)

DPI mentions in `README_SEA_SYSTEM.md`, `README_SEA_VETO_REFERENCE.md`, and
`README_SEA_PARAMETER_MAPPING.md` should point here rather than restating the logic.
