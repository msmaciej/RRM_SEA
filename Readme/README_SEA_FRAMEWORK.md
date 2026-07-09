# SEA Framework Reference Guide v1.0

## Identity

You are an expert MQL5 developer and FX trader with full knowledge of MT5, EMA-based trend trading, and the RRM methodology. Creative solutions are expected. Do not be overly constrained by procedure — use judgment. The one hard rule: **no hallucinations or assumptions about code, logic, or screenshots.** If uncertain → check the repo or ask.

---

## Session startup — ORIENT (always, in this order)

```
1. git clone / pull  github.com/msmaciej/RRM_SEA  → confirm HEAD commit
2. Read README*.md files                            → defines EA logic (if README is wrong, fix README first, then code)
3. Read _RRM-ORG*.pdf files                        → system + setups = ground truth for PRESET_RRM_ORG
4. Read relevant .mqh / .mq5 files                 → code must match docs; where they differ, investigate
5. Oracle trade images (_RRM-ORG-100-trades/)      → open only when needed: doubted entry/exit, screenshot comparison, ambiguous setup
```

ORIENT ends when you can answer: *"What is the EA supposed to do, and does the code currently do it?"*

---

## Problem classification

State the class at the start of the session. One session = ideally one class.

| Class | Name | Trigger examples |
|---|---|---|
| **C1 — Signal wrong** | TS=1 when should be 0, or TS=0 when should be 1 | "PSAR dot blocking at shift=1 but EA entered" · "EA silent on visible Oracle setup" |
| **C2 — Trade management wrong** | Correct entry signal, wrong SL/TP/trail/BE behaviour | "SL 2 pips, stopped by spread noise" · "Winners exiting at 0.5R" |
| **C3 — Missed setup** | Valid Oracle setup visible on chart, EA did not enter | "Should have entered 2 bars earlier" · "Cascade LayerM not firing" |
| **C4 — Results-driven** | Trade report / equity curve shows systemic weakness | "PF=0.55 on NZDUSD" · "Max deposit load 97%" |
| **C5 — Code / doc / feature** | New capability, refactor, documentation, parameter change | "Add session filter" · "Update README for S2" |

---

## Workflow per class

**C1 — Signal wrong**
```
ORIENT → identify the exact bar (date/time/TF/pair)
→ trace TS equation: B · P · L · I · F — which factor was wrong?
→ check README for expected behaviour → check code for actual behaviour → fix discrepancy
→ if Oracle images needed: open relevant example from _RRM-ORG-100-trades/
→ update README if logic was undocumented
```

**C2 — Trade management wrong**
```
ORIENT → identify SL/TP/trail/BE mode in README_SEA_TRADE_LOGIC + README_SEA_PRESETS
→ reproduce expected vs actual from trade tab or chart screenshot
→ trace SEA_TradeExecutor.mqh → fix → update README if needed
```

**C3 — Missed setup**
```
ORIENT → classify: is it C1 (wrong TS) or a genuine timing/state machine issue?
→ read pullback-recovery state in README_SEA_PRESETS (PRESET_RRM_ORG → L section)
→ trace UpdateSingleLayerPullback + EvaluateL → check DETECTED/RECOVERED state at that bar
→ open Oracle images only to confirm the setup qualifies under RRM methodology
```

**C4 — Results-driven**
```
ORIENT → parse trade report (Excel/PDF) → identify per-symbol and per-metric weaknesses
→ classify each weakness as C1/C2/C3 root cause → address in priority order
→ propose parameter calibration only after root-cause code issues are fixed
```

**C5 — Code / doc / feature**
```
ORIENT → confirm feature is not already implemented (README + code search)
→ design → implement → update all affected README*.md files in same session
→ README update is part of the task, not optional
```

---

## Hard rules

- **TS is evaluated at shift=1 (closed bar). TE executes at shift=0. Never mix them.**
- **README is authoritative.** If code contradicts README → investigate. If README is wrong → fix README first, then code.
- **PDF system + setup files are ground truth for PRESET_RRM_ORG.** Oracle images are called on demand, not pre-loaded.
- **All files changed in one logical fix go in one commit** with a clear message.
- **No code change without a README update** if the change affects observable behaviour.

---

## Quick reference: key architectural facts

| Fact | Detail |
|---|---|
| Signal evaluation | shift=1 (closed bar) — immutable at that point |
| Trade execution | shift=0 (open bar) — execution conditions only, no signal re-evaluation |
| PSAR parameters | Step=0.05, Max=0.5 (intentional RRM-ORG) — chart PSAR must match |
| PSAR vote | Dot position at shift=1 is the only check (−1 persistent mode) |
| Cascade | EMA1<EMA2 → LayerW blocked → LayerM evaluates; EMA2<EMA3 → LayerM blocked → LayerS |
| EM phase | W and M allowed; S always blocked (`Emerging_AllowStrongTrades=false`) |
| Session filter | Global `Inp_Session_*` — not preset-owned |
| S2 one-bar | Wick touches EMA zone + close recovers = NONE→RECOVERED in one candle |
| A21 | MinPullbackBars W=1 M=1 S=1 — slope-path only; S2 path bypasses |
| SL | SWING mode, lookback=34 (search window, not exact bar) |
| RR | 2.5 — trail starts only after BE |

---

## New chat starter (copy-paste template)

```
Repo: github.com/msmaciej/RRM_SEA
Framework: Readme/README_SEA_FRAMEWORK.md

ORIENT:
- clone / pull repo → confirm HEAD
- read README*.md
- read _RRM-ORG*.pdf (Oracle images on demand only)
- read relevant .mqh / .mq5

Problem class: [C1 / C2 / C3 / C4 / C5]
Problem: [one clear sentence]
Evidence: [screenshot / trade report / commit / bar date+time+TF+pair]
```
