# How to read the Meta-Gate results (plain language)

You do not need statistics to use this. Read this once and the output makes sense.

## The one idea that removes most confusion

There are **two different questions**, and they have **different answers**:

1. **"Is RRM_ORG profitable?"** — about your strategy. Answered by **total R** and
   **profit factor** (section [2]).
2. **"Does adding the ML filter help?"** — about the gate. Answered by comparing gated
   vs ungated out-of-sample (section [4]) and by **PBO**.

"DO NOT SHIP" answers **only question 2**. It means *the filter isn't worth adding* —
it says **nothing** about whether your strategy makes money. A profitable strategy and
"don't ship the filter" are perfectly compatible: it just means you run RRM_ORG plain,
like the disciplined human does. No contradiction.

## The words

- **ML** = machine learning. Here it's just logistic regression: a weighted score of
  features. Not ChatGPT, not a black box.
- **TS / TE / TM** = your engine's stages: TS = the signal gate (all votes must pass),
  TE = the entry, TM = the exits/trade management.
- **The gate / veto** = the ML filter. It can only **skip or shrink** a trade your rules
  already approved. It can never create a trade or move a stop.
- **B label** = "did the real trade close break-even-or-better (net P&L ≥ 0)?" This is
  win/loss on the *managed* trade (includes your exits). The go/no-go label.
- **Q label** = "ignoring your exits, did price move 1× your risk in your favour before
  hitting the stop?" A signal-reach score. **Q vs B** tells you signal vs exits:
  - Q ≈ B  → exits are fine; the **signal** is the limiting factor.
  - Q ≫ B  → good signals, but your **exits** give the profit back.
  - Q ≪ B  → weak signals your exits rescue.
- **Sharpe** = average return ÷ how bumpy the returns are. Rewards smooth; **punishes
  fat-tailed** profiles (many small scratches + rare big winners — i.e. RRM).
- **PSR** = Probabilistic Sharpe = "probability the true Sharpe is above 0," adjusted for
  sample size and fat tails. A number in 0–1.
- **DSR** (Deflated Sharpe) = PSR **after** subtracting the luck you'd expect from trying
  many thresholds. `DSR = P(true Sharpe > a hurdle SR0)`, where SR0 rises with the number
  of thresholds you swept. **Want > 0.95.**
- **Why DSR can be 0.000 even when you're clearly making money:** DSR is a *per-trade
  Sharpe* test. A profile of many BE scratches + rare big winners has a **low per-trade
  Sharpe** even when total R and profit factor are great. So on RRM-shaped returns DSR is
  almost always harsh. **Treat DSR as a strict bonus, not the deciding number.** The tool
  now does exactly that (see the verdict).
- **PBO** = Probability of Backtest Overfitting = "how likely is the threshold I picked to
  be a fluke?" **Want < 0.5, ideally < 0.2.** This is the number that actually catches
  overfit filters.
- **trials** = how many thresholds were swept (51). More trials = higher luck-bar (that's
  what DSR corrects for).
- **DEAD feature** = a column with the same value every row. It can't teach the model
  anything, so it's dropped.

## Reading a Ladder-1 block, section by section

- **[1] FEATURE HEALTH** — a `DEAD` column list. If a feature you expected to vary is
  dead, your data is stale/mis-wired → delete + re-collect. If it's dead *by design*
  (below), ignore it — it's auto-dropped.
- **[2] PROFITABILITY** — the money question, ungated, all trades. **total R > 0 and
  PF > 1 = RRM_ORG makes money on this data.** This is the number you care about most.
- **[3] CPCV** — the gate tested on many out-of-sample slices instead of one. "gated
  better on X% of paths" near 50% = coin-flip (no real help); near 100% = real help.
- **[4] DOES THE GATE HELP?** — gated vs ungated **on the same OOS trades**. If gated
  total R and PF are clearly higher **and** PBO < 0.5, the filter helps. DSR is shown but
  is a strict advisory.
- **VERDICT** — SHIP needs three YES's: **money up OOS**, **PBO < 0.5**, **wins on most
  paths**. DSR is reported but is *not* required (too harsh on fat tails).

## Dead features — your exact question answered

You asked: "an indicator voted =1 during TS, but its real value is e.g. 0.0154, not 1 —
so why is it dead?" **You're right, and nothing is lost.** Two different things get logged:

- The **raw value** (e.g. `dpi_hist = 0.000231`, `cci = 158`, `body_ratio = 0.20`). These
  **vary** and are **alive** — they're in your health table as live features.
- The **vote result** (pass/fail = 1/0, e.g. `cbody_vote`, `votes_frac`). Because a signal
  only fires when **all** required votes pass (`VOTE_MODE_ALL`), the vote result is
  **always the passing value** at every logged event → constant → dead. That's structural,
  not a bug, and re-collecting won't change it.

So `dpi_hist` (raw) is alive and carries the momentum information; `dpi_green` / `cbody_vote`
/ `votes_frac` (flags) are dead redundant copies. The information is kept under the raw
name. Nothing is missing. `vprr_ratio` is dead simply because the VPRR voter is off in
RRM_ORG. **All four are auto-dropped; you do not need to do anything.**

### How to drop / choose features (you don't have to, but if you want to)
- **Automatic:** the validator already drops every DEAD feature before scoring. Nothing to do.
- **Manual (for the experiment below):** open `rrm_validate.py`, find `FEATURE_SUBSET` near
  the top, and set it to a list, e.g.
  `FEATURE_SUBSET = ["adx","di_spread","bb_width_atr","ret_vol_20","ema_fan_atr","atr","hour"]`
  Set it back to `None` to use all live features.

## "How do we avoid ranging markets if we filter them out of training?"

You don't pre-remove them — the **opposite**. To learn "ranging → skip," the training data
must **contain** the ranging-market losers. The gate learns the pattern *from* those bad
trades (using `adx`, `bb_width_atr`, `ema_fan_atr`, `ret_vol_20`, `phase` — all alive).
The risk is the reverse of your worry: RRM_ORG's strict gate may already block most ranging
entries, so there are **few** ranging losers left to learn from → little for the filter to
add. That, plus a fat-tailed profile, is the likely reason the gate shows no edge on
EURUSD H1. The fix isn't to remove ranging trades — it's **more data** so enough bad-market
examples exist, and a **tighter feature set** so the model isn't drowned in noise.

## What to do next (two separate experiments)

1. **Feature-subset re-run — cheap, NO re-collect.** Set `FEATURE_SUBSET` to the regime
   tells (line above) and run `python3 rrm_validate.py` again. Fewer features on limited
   data usually drops PBO. If gated OOS money now beats ungated with PBO < 0.5 → there's a
   real "skip ranging" edge. If not → there probably isn't one on this pair/TF, honestly.
2. **More data / other timeframes — needs re-collect per pair+TF.** 425 trades is thin.
   For each new pair or TF: delete its two CSVs → COLLECT → VALIDATE. A lower timeframe
   (M15/M5) gives many more events; more pairs give more bad-market examples. This is the
   surer path to a gate that can actually learn.

Do **1 first** (five minutes). Then **2** if you want more statistical power. Either way,
if `[2]` shows total R > 0, RRM_ORG is profitable and you can run it ungated today.

## The practical decision rule

- **Ship the gate** only if: gated OOS total R and PF beat ungated, **and** PBO < 0.5.
- **Ignore a DSR of 0** on its own — it's expected on fat-tailed R; use it only to break
  ties between two otherwise-good gates.
- **If no gate ships:** run RRM_ORG ungated, exactly like the disciplined human. Ladder 1
  has simply protected you from bolting on a filter that doesn't help.
