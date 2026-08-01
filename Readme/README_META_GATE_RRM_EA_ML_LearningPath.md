# RRM EA — Financial ML Learning & Application Path

**Owner:** Maciek Szczech
**Date:** July 2026
**Scope:** Personal (own trading). Companion to the VortexDeep learning-path
roadmap, but a **separate track** — this is not a VortexDeep product.
**Repos:** `RRM_EAv0.1_PY` (research/validation brain) · `RRM_SEA` (live MQL5 execution)

> **Read this as:** validation first, then modeling. For a rule-based EA with a
> large parameter/preset surface, honest scoring is the prerequisite for trusting
> anything you build afterward. Coursera builds the modeling brain; the
> validation spine lives off-Coursera.

---

## The clean division

- **Coursera → the modeling brain.** Andrew Ng → EDHEC + ML for Trading → NYU.
  The bulk of the hours, but the *lower*-priority half for this EA.
- **Off-Coursera → the validation spine.** de Prado + Chan + the GARP paper +
  QuantInsti + `mlfinlab`. Smaller reading load, higher payoff, applied first and
  kept running throughout.
- **The repos → where it lands.** Model and validate offline in Python; the MQL5
  SEA executes *only validated logic*. Nothing is hard-coded into the EA until it
  survives Phase 0 scoring.

SEA stage vocabulary used below: `TS = B × P × L × I × F` (multiplicative signal
gate, `VOTE_MODE_ALL`) → `TE` (entry at shift=0) → `TM` (exits) → `RC/RM` (risk vetoes).

---

## Phase 0 — Validation *(off-Coursera, do this FIRST)*

> **2026-07-31 update (label = B):** the meta-gate label is now the trade's **realized
> BE-or-profit outcome** (logged to `TS_outcomes_*`), not the fixed `RR × SL` triple
> barrier. So Phase-0 validation (`rrm_validate.py`) grades the **realized recipe**: the
> label is the stored `be_or_better` column joined on `event_time` (no per-fold barrier
> re-simulation), and each fold re-fits the logistic model on `features → be_or_better`.
> The purged-CV / deflated-Sharpe rigour below is unchanged; only the label source moved.

- **Learn:** de Prado Ch. 7 (purged/embargoed CV) and Ch. 14 + the deflated Sharpe
  material; the GARP paper *"The 10 Reasons Most Machine Learning Funds Fail"* as
  the fast free intro; Ernest Chan's *Algorithmic Trading* as the accessible
  on-ramp. Optionally QuantInsti / Quantra for a structured course format.
- **Apply:** extend the Python metrics (`rrm_metrics.py`, RC reporting) to compute
  **deflated Sharpe** and **track trial count** across presets and pairs; add
  **purged + embargoed CV** via `mlfinlab` or an open reimplementation. Re-score
  the current SEA presets — expect some "good" backtests to deflate. No ML
  required; you already own the engine.
- **Why first:** with EMA periods, layer ratios, indicator toggles, 5 presets and
  per-pair variants, you are implicitly running many trials. Deflated Sharpe is the
  number that corrects for exactly that. Preset-locking is this instinct done by
  hand; this is the rigorous version.

## Phase 1 — ML foundation *(Coursera)*

- **Learn:** Andrew Ng — *Machine Learning Specialization* (DeepLearning.AI /
  Stanford, 3 courses).
- **Apply:** treat the `TS` components (B, P, L, and each indicator vote) as a
  **feature vector** and trade outcomes as **labels**; train a first
  logistic-regression / tree classifier in Python. Run **feature importance**
  (de Prado Ch. 8) to see which of the ~dozen indicators actually carry signal
  vs. just tightening `VOTE_MODE_ALL` for free.

## Phase 2 — Applied ML + risk *(Coursera, the core)*

- **Learn:** EDHEC — *Investment Management with Python & ML* (4 courses);
  Google Cloud + NYIF — *Machine Learning for Trading* (3 courses).
- **Apply:**
  - EDHEC → upgrade **CM/RM**: risk-based position sizing and drawdown-aware caps
    instead of fixed lots.
  - ML for Trading → model `TS` as a **graded probability**; port only the
    validated features/weights back into the MQL5 EA as new votes or a threshold.

## Phase 3 — Advanced *(Coursera, optional)*

- **Learn:** NYU — *Machine Learning and Reinforcement Learning in Finance*
  (4 courses, math-heavy).
- **Apply:** RL for **TE/TM** exits (SL/TP/BE/trail as a learned policy) and
  sizing; **unsupervised regime detection** to augment the hand-coded Phase logic
  (TM/EM/UNO) and Layer detection.

## Cross-cutting — sentiment *(optional)*

- **Learn:** DeepLearning.AI — *Natural Language Processing Specialization* (4 courses).
- **Apply:** turn the `F` news filter from a binary veto into a **graded sentiment
  feature** feeding `TS`.

## Always-on discipline

Every experiment tracked; deflated Sharpe reported with its trial count. Phase 0 is
a habit maintained through all later phases, not a one-time step.

---

## Reference implementation — EECS 545 "Team KIWY"

**Repo:** `github.com/israeldi/Final-Project-EECS545`
**What it is:** *"Statistical Arbitrage by Pair Trading using Clustering and
Machine Learning"* — a University of Michigan EECS 545 (Machine Learning, Fall
2019) capstone, bronze award in the application track. Jupyter notebooks + final
paper + poster, and it bundles **both canonical texts**: de Prado's *Advances in
Financial Machine Learning* and Ernest Chan's *Algorithmic Trading*.

**How it relates:**
- Sits at the intersection of this path — **clustering** (Phase 3 unsupervised) +
  **supervised ML signals** (Phases 1–2), built on the **de Prado** book (Phase 0).
- **Opposite strategy family** to the RRM EA: mean-reversion / market-neutral
  **pairs trading**, not trend/momentum. Not a template to copy — a clean example
  of the *other* branch, and of ML techniques the hand-coded EA doesn't use yet.
- **Clustering is the key transfer.** Where the EA hand-codes market states
  (Phase TM/EM/UNO, Layer), this project *learns* structure from data — the exact
  "unsupervised regime detection" upgrade flagged in Phase 3, shown in practice.

**How to use it:**
1. **Phase 0 critique exercise (highest value):** read the notebooks and check
   *whether* they actually used purged/embargoed CV and reported a deflated Sharpe,
   or shipped the book alongside plain train/test / k-fold. Best way to train the
   validation eye — on someone else's code first.
2. **Python research scaffold:** a reference for the offline workflow
   (data → features → clustering/ML → backtest) that mirrors what `RRM_EAv0.1_PY`
   should become.
3. **Strategy diversification idea:** pairs / stat-arb is market-neutral and
   largely uncorrelated with a trend EA — a natural *second* strategy once the ML
   tooling exists.

---

## Reading list (Phase 0 core)

- Marcos López de Prado — *Advances in Financial Machine Learning* (Wiley, 2018).
  Primary source. Ch. 7 (CV in finance), Ch. 8 (feature importance),
  Ch. 11–12 (backtesting, CPCV), Ch. 14 (backtest statistics, deflated Sharpe).
- Marcos López de Prado — *Machine Learning for Asset Managers* (Cambridge, 2020).
  Condensed alternative.
- Ernest Chan — *Algorithmic Trading: Winning Strategies and Their Rationale*.
  Practical on-ramp (mean reversion, cointegration, Kelly sizing, backtest pitfalls).
- GARP — *"The 10 Reasons Most Machine Learning Funds Fail"* (López de Prado).
  Free, fast intro to CPCV + deflated Sharpe.
- `mlfinlab` (Hudson & Thames) — reference Python implementation of the de Prado
  methods (now largely commercial; open reimplementations exist on GitHub).
