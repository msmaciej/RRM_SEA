# SEA Framework Reference Guide v3.0

---

## Part A — Framework Taxonomy

Three frameworks. Three problem classes. Zero overlap in purpose.

### RTFC — Role · Task · Format · Constraints

**Use when:** You know exactly what needs to be done and want it executed without commentary.

| Letter | Role |
|---|---|
| **R — Role** | Who the AI acts as. Sets domain depth and eliminates beginner explanations. |
| **T — Task** | Exact technical objective. Single, unambiguous, fully specified. |
| **F — Format** | Output structure. Raw code block, JSON, bullet list — stated explicitly. |
| **C — Constraints** | Negative rules. What the AI must not do, assume, or include. |

**Strength:** Lowest token overhead for highest precision on contained tasks.
**Weakness:** Cannot resolve conflicts between two reference systems. Collapses when correct output depends on comparing code vs rule spec.

---

### COSTAR — Context · Objective · Style · Tone · Audience · Response

**Use when:** Something is wrong or unexpected right now in a running system. You have a cockpit screenshot, a log, a live state.

| Letter | Role |
|---|---|
| **C — Context** | Background state — what system, what constraints, what history |
| **O — Objective** | The task to complete — can be multi-part or diagnostic |
| **S — Style** | Code and writing aesthetics — minimalism, strict OOP, etc. |
| **T — Tone** | Analytical, forensic, zero hand-waving |
| **A — Audience** | Who reads the output — defines assumed expertise level |
| **R — Response** | Required output format and structure |

**Strength:** Full behavioral profile. Handles sustained multi-turn sessions. Present observable state is the evidence base.
**Weakness:** No built-in mechanism for historical state isolation or rule-vs-code delta analysis.

---

### OSCAR — Oracle · Scope · Classification · Audit · Remediation

**Use when:** A trade fired or did not fire at a specific past bar. Current system state is irrelevant. RRM-ORG example set defines correct behaviour.

| Letter | Role |
|---|---|
| **O — Oracle** | Canonical reference. RRM-ORG examples define correct behaviour. Higher authority than code, docs, or developer memory. |
| **S — Scope** | Historical isolation boundary. Current cockpit is excluded from past-bar analysis. |
| **C — Classification** | Failure taxonomy: `TS_FN` · `TS_FP_PSAR` · `TS_FP_EXHAUST` · `TS_FP_PHASE` · `TS_FP_LAYER` |
| **A — Audit** | Forensic trace: bar extraction → rule reference → code path → delta statement |
| **R — Remediation** | Minimum-diff surgical fix anchored to a named Oracle rule. Never an opinion. |

**Strength:** Oracle consulted before any code is read — structurally enforced by being the first letter.
**Weakness:** Higher setup cost. Requires _RRM-ORG*.pdf accessible at session start.

> OSCAR supersedes SCAR. Only structural change: Oracle elevated to first-class component, preventing code-first shortcuts.

---

## Part B — Framework Decision Matrix

| | RTFC | COSTAR | OSCAR |
|---|---|---|---|
| **Problem class** | Execute a known task precisely | Diagnose current system state | Audit historical signal correctness |
| **Core question** | Do exactly this | Why is the system behaving this way right now? | Was this past signal evaluation correct per the rules? |
| **Ground truth** | Your stated constraints | Current cockpit / observable state | RRM-ORG example set |
| **Time orientation** | Present task | Present state | Past events |
| **Code role** | Output target | Verification of current state | Record of what was computed |
| **Rule spec role** | Not present | Developer intent | First-class Oracle — highest authority |
| **Cockpit panel** | Not applicable | Central diagnostic input | Explicitly excluded |
| **Fix is correct when** | Satisfies stated constraint | Cockpit resolves to expected | Named Oracle example supports new behaviour |
| **Token cost** | Minimal | Medium | High |

---

## Part C — SEA Problem Classification → Framework Mapping

| Class | Name | Framework | Trigger examples |
|---|---|---|---|
| **C1** | Signal wrong | **OSCAR** | "PSAR dot blocking at shift=1 but EA entered" · "EA silent on visible Oracle setup" |
| **C2** | Trade management wrong | **COSTAR** | "SL 2 pips, stopped by noise" · "Winners exit at 0.5R" |
| **C3** | Missed setup | **OSCAR** | "Should have entered 2 bars earlier" · "Cascade LayerM not firing" |
| **C4** | Results-driven | **COSTAR** | "PF=0.55 on NZDUSD" · "Max deposit load 97%" |
| **C5** | Code / doc / feature | **RTFC** | "Add session filter" · "Update README for S2" |

C4 decomposes: parse report → classify each weakness as C1/C2/C3 → each uses its natural framework.

---

## Part D — ORIENT protocol (all sessions, executed silently after Step 2)

```
1. git clone / pull  github.com/msmaciej/RRM_SEA  → confirm HEAD commit
2. Read README*.md                                  → EA logic is here; if wrong, fix README first then code
3. Read _RRM-ORG*.pdf                              → system + setups = ground truth for PRESET_RRM_ORG
4. Read relevant .mqh / .mq5                        → code must match docs; divergence = investigate
5. Oracle images (_RRM-ORG-100-trades/)             → on demand only: doubted entry, screenshot comparison
```

---

## Part E — Per-class workflow

**C1 · C3 → OSCAR**
```
O: confirm Oracle rule from _RRM-ORG*.pdf (which setup, which checklist item)
S: isolate exact historical bar — date / time / TF / pair. Cockpit excluded.
C: classify failure — TS_FN / TS_FP_PSAR / TS_FP_EXHAUST / TS_FP_PHASE / TS_FP_LAYER
A: trace TS equation at shift=1 against rule spec → state the delta
R: minimum-diff fix anchored to named Oracle rule → update README
```

**C2 · C4 → COSTAR**
```
C: current system state — screenshot / trade report / cockpit / log
O: what behaviour is wrong vs expected (per README_SEA_TRADE_LOGIC + README_SEA_PRESETS)
S: surgical — no rewrites, no scope creep
T: analytical — state the delta before touching code
A: developer with full codebase context
R: traced fix in SEA_TradeExecutor.mqh or SEA_SignalEngine.mqh + README update
```

**C5 → RTFC**
```
R: Expert MQL5 developer, RRM methodology, MT5 FX markets
T: [single unambiguous task]
F: [exact output — code block / diff / markdown section]
C: no hallucinations · verify feature not already implemented · update README in same session
```

---

## Part F — Hard rules

- **TS evaluated at shift=1 (closed bar). TE executes at shift=0. Never mix them.**
- **README is authoritative.** Code contradicts README → investigate. README is wrong → fix README first, then code.
- **Oracle images called on demand.** Not pre-loaded every session.
- **No hallucinations or assumptions** about code, logic, or screenshots. Uncertain → check repo or ask.
- **One logical fix = one commit** with clear message.
- **No code change without README update** if observable behaviour changes.
- **One problem per session.** See Part I. A session closes when its problem is closed.
- **A hypothesis is never delivered as code.** Before writing any fix, state which of these it is:
  - **(a) Traced defect** — a specific line/path that provably contradicts the README, the Oracle, or its own stated contract. *Implement.*
  - **(b) Hypothesis** — a proposed change resting on an assumption about market behaviour, or on "this should help", with no traced defect behind it. **Do not implement.** Say plainly: *"This is a hypothesis, not a traced defect."* Then offer the audit or the A/B test that would confirm or kill it, and stop.

  If a fix cannot be tied to (a), it is (b). Delivering (b) as working code — especially with confident framing — is the most damaging failure mode in this project: it puts untested guesses into the trading path wearing the costume of a fix.
- **Magic numbers are a smell.** If a proposed fix introduces a tunable whose correct value cannot be derived from the Oracle or the code (e.g. "wait N bars"), stop and ask whether the rule should instead be **event-indexed** (tied to a structural event: a flip, a completed pullback-recovery, a cross) rather than **time-indexed**. Event-indexed rules need no magic number and scale across timeframes.

---

## Part G — Quick reference: PRESET_RRM_ORG

| Fact | Detail |
|---|---|
| Signal evaluation | shift=1 (closed bar) — immutable |
| Trade execution | shift=0 (open bar) — execution conditions only, no signal re-evaluation |
| PSAR parameters | Step=0.05, Max=0.5 (intentional RRM-ORG) — chart PSAR must use same values |
| PSAR vote | Dot position at shift=1 only (−1 persistent). Counter-flip clears record immediately. |
| Cascade | EMA1<EMA2 → LayerW invalidated → LayerM. EMA2<EMA3 → LayerM invalidated → LayerS. A fast-vs-slow cross invalidates that layer (position lost) and resets its PB state. |
| EM phase | W and M allowed. S always blocked (`Emerging_AllowStrongTrades=false`). |
| Session filter | Global `Inp_Session_*` — London/NY on by default. Not preset-owned. |
| Pullback (DETECTED) | Slope-only, vs `bias_dir`: flat (`LayerFlatRatio`) OR reversed (`LayerAllowReversalPullback`). Weakened-but-still-in-trend is NOT a pullback. Price-touch is OFF (`LayerPriceTouchEnabled=false`). |
| Recovery (RECOVERED) | Slope-only: fast AND slow layer-EMA slopes back in `bias_dir`. Not a close-vs-EMA test (that is BC). No one-bar recovery. Valid until relapse (counter-`bias_dir` reversal) or TS=1 consumption; optional `LayerRecoveryMaxAge` cap (default = observation window). |
| A21 | `LayerMinPullbackBars` W=2 M=2 S=2. A pullback cannot complete in one bar. |
| Windows | Baseline slope lookback `LayerBaselineLookback_W/M/S` = 13/21/34. Pullback observation window `LayerPullbackWindow_W/M/S` = 21/34/55. Both user-editable (+ global fallback). |
| UNO reset | Transient same-direction UNO tolerated up to `UNO_ToleranceBars` (=2) — DETECTED/RECOVERED preserved. Reset on sustained UNO, bias flip, or confirmed phase change. |
| SL | SWING mode, lookback=34 (search window, not exact bar). |
| RR | 2.5 — PSAR trail starts only after BE. |
| LayerS_RequireDirAlign | false — prevents spurious block of LayerW/M during EM pullbacks. |

---

## Part H — Conversational intake (how every session starts)

### ⛔ Do not use a short starter

A 3-line starter pointing to this document is not reliable — the AI may skip reading it and jump directly to the problem, causing hallucination and code-first shortcuts. All mandatory instructions must be present in the pasted text.

### Use `Readme/SEA_CHAT_STARTER.md`

Copy the **entire contents** of `Readme/SEA_CHAT_STARTER.md` and paste it as your first message in a new chat. Fill in the last line with your problem. That file contains:

- `⛔ DO NOT` gate — AI cannot touch code until ORIENT is complete
- Explicit file reading order: README → PDFs → setup cards → this framework
- Mandatory confirmation before intake begins
- The 5-step conversational intake below

---

### STEP 1 — Preset

AI asks:

> Which preset is this problem about?
>
> 1. **PRESET_RRM_ORG** — Russ Horn RRM, 4 EMAs, DPI+PSAR+CandleBody (default)
> 2. **PRESET_FPM** — Five-Point Method
> 3. **PRESET_TOPINVESTOR** — TopInvestor / OXO, EMA50/200
> 4. **PRESET_MA** — benchmark
> 5. **Other / not sure**
>
> *Default: PRESET_RRM_ORG — confirm or select.*

You reply: a number, a name, or "confirm".

---

### STEP 2 — ORIENT (silent execution)

AI clones/pulls repo, confirms HEAD commit, reads README*.md, reads _RRM-ORG*.pdf (for RRM_ORG preset), reads the relevant .mqh files for the problem area. Oracle trade images loaded only if needed.

AI then reports:

> ORIENT complete — HEAD: [commit hash]
>
> My understanding of the relevant EA logic:
> [2–4 sentence summary of what the docs say about the problem area]
>
> *Correct anything that looks wrong before we proceed.*

You confirm or correct.

---

### STEP 3 — Problem class

AI suggests a class based on your problem statement:

> Based on "[your problem statement]", this looks like:
>
> - **C1 — Signal wrong** (TS=1 when should be 0, or TS=0 when should be 1) → OSCAR
> - **C2 — Trade management wrong** (correct entry, wrong SL/TP/trail/BE) → COSTAR
> - **C3 — Missed setup** (valid Oracle setup, EA did not enter) → OSCAR
> - **C4 — Results-driven** (trade report / equity curve shows systemic weakness) → COSTAR
> - **C5 — Code / doc / feature** (new capability, refactor, documentation) → RTFC
>
> I think this is **[C#]** — which means we use **[OSCAR/COSTAR/RTFC]**.
> *Confirm or correct.*

You confirm or select a different class.

---

### STEP 4 — Evidence

AI asks for what the selected class needs:

**C1 / C3 (OSCAR):**
> What is the exact bar?
> - Pair and timeframe (e.g. GBPUSD M1)
> - Date and time of the signal or entry (e.g. 2026-07-09 18:55)
> - Screenshot optional but useful — attach if you have it

**C2 (COSTAR):**
> Describe what you observed or attach a screenshot showing:
> - The trade tab (SL/TP values, entry price, current price)
> - The chart at the relevant moment

**C4 (COSTAR):**
> Please provide the trade report — upload the Excel or PDF export from MT5 History tab.

**C5 (RTFC):**
> What is the exact deliverable?
> - Code change: which file, what function, what behaviour
> - Doc update: which README section, what is wrong or missing
> - New feature: describe input/output in one sentence

---

### STEP 5 — Confirmation

AI summarises everything before starting:

> Ready to proceed:
>
> - **Repo:** github.com/msmaciej/RRM_SEA @ [HEAD commit]
> - **Preset:** [preset name]
> - **Class:** [C#] — [name]
> - **Framework:** [OSCAR / COSTAR / RTFC]
> - **Problem:** [restated precisely in one sentence]
> - **Evidence:** [what was provided]
>
> *Confirm to begin analysis, or correct anything above.*

You confirm → analysis begins. No further intake questions unless something genuinely blocks the analysis.

---

## Part I — Session scope (one problem per session)

### The rule

**One session = one problem = one class = one framework = one commit.**

When the problem is closed (fix delivered, README updated, compiled), the session is **done**. Start a new chat for the next problem.

### Why

Intake (Part H) runs *once*, at the start of a session, on the *first* problem. It has no natural re-entry point. So every problem raised *after* the first one in the same chat silently bypasses ORIENT, classification, and the evidence step — and inherits the previous problem's class and context, which do not apply to it.

Observed failure mode: a correctly-executed C1 audit closes; the session then continues on momentum ("while you're at it, also fix X"); each follow-up skips intake; discipline erodes progressively; and the AI eventually delivers a **hypothesis as code** (Part F) because nothing forced it to state a class or produce evidence. The work *feels* productive — it is a stream of confident, compiling code — which is exactly what makes it dangerous.

Momentum is not a reason to skip intake. **Momentum is the mechanism by which intake gets skipped.**

### Mid-session problem switch (Part H.1)

If a new problem surfaces mid-session — it will — the AI must **not** proceed on momentum. It must stop and say:

> **This is a new problem, not a continuation of the current one.**
>
> - **Recommended:** close this session and open a fresh chat with the full starter (ORIENT + intake). This is the default.
> - **If the new problem is genuinely small and self-contained** (typically C5 — a doc fix, an unwired parameter, a one-line defect), it may be handled in-session **only after** re-running intake STEP 3 → STEP 4 → STEP 5 (class → evidence → confirmation) for the *new* problem.
>
> Under no circumstances may a prior problem's class, framework, or evidence be carried into a new problem.

### What counts as "the same problem"

| Same problem (continue) | New problem (stop → new session) |
|---|---|
| Fixing a defect found *by* the current audit | A different symptom, even in the same file |
| Extending the current fix to sibling code paths **that share the identical traced defect** | A new feature, filter, or guard |
| README update mandated by the current fix (Part F) | A design change ("should we add X?") |
| Correcting an error in this session's own work | Anything requiring a *different* problem class |

The middle-left cell is the dangerous one — "same defect class, sibling code path" is legitimate, but only when the defect is **traced and identical**, not merely *similar*. When unsure: it is a new problem.

### Scope discipline within a session

- Findings outside the current problem's scope are **logged, not fixed.** State them plainly at the end ("noted, out of scope — worth a session of its own"), and let the operator decide.
- Never bundle an unrelated fix into the current commit, however small or tempting.

