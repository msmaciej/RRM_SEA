# SEA Framework Reference Guide v2.0

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

**Strength:** Full behavioral profile. Handles sustained multi-turn sessions and complex agent personas. Present observable state is the evidence base.
**Weakness:** No built-in mechanism for historical state isolation or rule-vs-code delta analysis.

---

### OSCAR — Oracle · Scope · Classification · Audit · Remediation

**Use when:** A trade fired or did not fire at a specific past bar. The current system state is irrelevant. The RRM-ORG example set defines correct behaviour.

| Letter | Role |
|---|---|
| **O — Oracle** | Canonical reference. RRM-ORG examples define correct behaviour. Higher authority than code, docs, or developer memory. |
| **S — Scope** | Historical isolation boundary. Current cockpit is excluded from past-bar analysis. |
| **C — Classification** | Failure taxonomy: `TS_FN` · `TS_FP_PSAR` · `TS_FP_EXHAUST` · `TS_FP_PHASE` · `TS_FP_LAYER` |
| **A — Audit** | Forensic trace: bar extraction → rule reference → code path → delta statement |
| **R — Remediation** | Minimum-diff surgical fix anchored to a named Oracle rule. Never an opinion. |

**Strength:** Treats the rule specification as a first-class input with higher authority than code. Oracle must be consulted before any code is read — it is the first letter precisely to prevent skipping this step.
**Weakness:** Higher setup cost. Requires _RRM-ORG*.pdf and Oracle examples accessible at session start.

> OSCAR supersedes SCAR. The only structural change: Oracle is elevated from a step inside Audit to the first top-level component, enforcing rule-first discipline structurally rather than by instruction.

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

C4 decomposes: parse report → classify each weakness as C1/C2/C3 → each sub-problem uses its natural framework.

---

## Part D — ORIENT protocol (all sessions, in order)

```
1. git clone / pull  github.com/msmaciej/RRM_SEA  → confirm HEAD commit
2. Read README*.md                                  → EA logic is here; if wrong, fix README first then code
3. Read _RRM-ORG*.pdf                              → system + setups = ground truth for PRESET_RRM_ORG
4. Read relevant .mqh / .mq5                        → code must match docs; divergence = investigate
5. Oracle images (_RRM-ORG-100-trades/)             → on demand only: doubted entry, screenshot comparison, ambiguous setup
```

ORIENT ends when you can answer: *"What is the EA supposed to do, and does the code currently do it?"*

---

## Part E — Per-class workflow

**C1 · C3 → OSCAR**
```
ORIENT
→ O: confirm Oracle rule from _RRM-ORG*.pdf (which setup type, which checklist item)
→ S: isolate the exact historical bar — date / time / TF / pair. Cockpit excluded.
→ C: classify failure — TS_FN / TS_FP_PSAR / TS_FP_EXHAUST / TS_FP_PHASE / TS_FP_LAYER
→ A: trace TS equation factor by factor at shift=1 against rule spec → state the delta
→ R: minimum-diff fix anchored to the named Oracle rule → update README
```

**C2 · C4 → COSTAR**
```
ORIENT
→ C: current system state — screenshot / trade report / cockpit / log
→ O: what behaviour is wrong vs expected (per README_SEA_TRADE_LOGIC + README_SEA_PRESETS)
→ S: surgical — no rewrites, no scope creep
→ T: analytical — state the delta before touching code
→ A: you (developer with full codebase context)
→ R: traced fix in SEA_TradeExecutor.mqh or SEA_SignalEngine.mqh + README update
```

**C5 → RTFC**
```
R: Expert MQL5 developer, RRM methodology, MT5 FX markets
T: [single unambiguous task]
F: [exact output format — code block / diff / markdown section]
C: no hallucinations · no assumptions · no scope beyond the stated task ·
   verify feature not already implemented before building · update README in same session
```

---

## Part F — Conversational mode

**Default: directive.** AI reads ORIENT, selects framework, executes, delivers.

**Conversational gate fires only when:**
1. Problem class is ambiguous (C1 vs C3, or C2 vs C4)
2. Evidence is insufficient to isolate the bar or behaviour
3. A fix has two valid implementations with different tradeoffs — state both, ask which

No other reason to ask questions mid-session. If uncertain about code or logic → check repo. If uncertain about Oracle rule → check _RRM-ORG*.pdf. Ask only when neither resolves it.

---

## Part G — Hard rules (all frameworks)

- **TS evaluated at shift=1 (closed bar). TE executes at shift=0. Never mix them.**
- **README is authoritative.** Code contradicts README → investigate. README is wrong → fix README first, then code.
- **Oracle images called on demand.** Not pre-loaded every session.
- **No hallucinations or assumptions** about code, logic, or screenshots. Uncertain → check repo or ask.
- **One logical fix = one commit** with clear message.
- **No code change without README update** if observable behaviour changes.

---

## Part H — Quick reference: PRESET_RRM_ORG

| Fact | Detail |
|---|---|
| Signal evaluation | shift=1 (closed bar) — immutable |
| Trade execution | shift=0 (open bar) — execution conditions only, no signal re-evaluation |
| PSAR parameters | Step=0.05, Max=0.5 (intentional RRM-ORG) — chart PSAR must match exactly |
| PSAR vote | Dot position at shift=1 only (−1 persistent mode). Counter-flip clears bullish record immediately. |
| Cascade | EMA1<EMA2 → LayerW blocked → LayerM evaluates. EMA2<EMA3 → LayerM blocked → LayerS. |
| EM phase | W and M allowed. S always blocked (`Emerging_AllowStrongTrades=false`). |
| Session filter | Global `Inp_Session_*` — London/NY on by default. Not preset-owned. |
| S2 one-bar | Wick touches EMA zone + close recovers → NONE→RECOVERED in one candle. A21 bypassed. |
| A21 | MinPullbackBars W=1 M=1 S=1. Slope-path only — S2 path bypasses. |
| SL | SWING mode, lookback=34 (search window, not exact bar). |
| RR | 2.5 — PSAR trail starts only after BE. |
| LayerS_RequireDirAlign | false — prevents spurious block of LayerW/M during EM pullbacks. |

---

## Part I — New chat starter template

Copy and paste this block. Fill in the bracketed fields. The framework is selected automatically from the class.

```
Repo: github.com/msmaciej/RRM_SEA
Framework: Readme/README_SEA_FRAMEWORK.md (v2.0)

ORIENT: clone/pull repo → confirm HEAD → read README*.md → read _RRM-ORG*.pdf → read relevant .mqh/.mq5

Problem class: [C1 / C2 / C3 / C4 / C5]
Framework:     [OSCAR for C1/C3 · COSTAR for C2/C4 · RTFC for C5]
Problem:       [one clear sentence]
Evidence:      [screenshot / trade report / bar date+time+TF+pair / commit]
```

