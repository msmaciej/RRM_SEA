# RRM EA — Meta-Gate Implementation Spec (Option 1: logistic regression as parameters)

**Owner:** Maciek Szczech · **Date:** July 2026
**Goal:** Add an optional ML "second opinion" (meta-labeling) on top of the existing
`TS` gate, trained offline in Python, deployed into MQL5 as a handful of numbers.
**Constraints honoured:** macOS + Wine + MT5 + MQL5 only. No C++, no ONNX, no live
Python, no runtime libraries. The deployed model is pure MQL5 arithmetic.

---

## 0. Mental model (read once)

```
RRM_SEA (MQL5)                         RRM_EAv0.1_PY (Python)
─────────────                          ──────────────────────
 TS=1 fires ──► log feature row ─────►  TS_events_<PRESET>.csv
                                          │
                                          ├─ label each row (triple-barrier)
                                          ├─ train logistic regression
                                          ├─ validate (purged CV + deflated Sharpe)
                                          └─ export ──► MetaModel_<PRESET>.csv
                                                          │
 OnInit: load model  ◄──────────────────────────────────┘
 TS=1 fires ──► score = sigmoid(w·x+b) ──► score<thr? SKIP : TAKE (size by score)
```

Two CSVs cross between the repos. Nothing else. The model is `N` weights + means +
stds + an intercept + a threshold.

**Three run modes, in order:**
1. **COLLECT** — `Inp_META_Enabled=false`, `Inp_META_LogFeatures=true`. Run Tester → produces `TS_events_<PRESET>.csv`.
2. **TRAIN** — Python. Label, fit, validate, export `MetaModel_<PRESET>.csv`.
3. **GATE** — `Inp_META_Enabled=true`. Run Tester → meta-gated results. Compare, ship only if out-of-sample deflated Sharpe improves.

---

## 1. Where each piece lives

**RRM_SEA (MQL5) — new/edited files**
| File | Change |
| --- | --- |
| `SEA_Config.mqh` | New Zone 2 inputs: `Inp_META_*` (below). |
| `SEA_MetaGate.mqh` | **New module.** `MetaModel` struct, `LoadMetaModel()`, `BuildFeatureVector()`, `MetaScore()`, `EvaluateMetaGate()`, `LogTSEvent()`. |
| `SEA_SignalEngine.mqh` / `EvaluateTE()` | Two hooks: on `TS=1` call `LogTSEvent()` (collect) and/or `EvaluateMetaGate()` (gate). |
| `OnInit()` | Call `LoadMetaModel()` if `Inp_META_Enabled`. |

**RRM_EAv0.1_PY (Python) — new files under `meta/`**
| File | Purpose |
| --- | --- |
| `meta/label_triple_barrier.py` | Turn logged events + price data into 0/1 labels. |
| `meta/train_meta.py` | Fit logistic regression, purged CV, deflated Sharpe. |
| `meta/export_mql5.py` | Write `MetaModel_<PRESET>.csv` into `MQL5\Files\`. |

**Where the CSVs land (updated 2026-07-31 — superseding "both in `MQL5\Files\` by
default").** Under macOS+Wine the Strategy Tester gives each run a throwaway
`MQL5\Files\` sandbox, so the default (non-common) location does **not** persist across
sequential runs. Therefore: the **events log**
(`TS_events_<PRESET>_<SYMBOL>_<TF>.csv`) is written by the EA to the shared
**`Common\Files`** via `FILE_COMMON`, which survives; the **model**
(`MetaModel_<PRESET>_<SYMBOL>_<TF>.csv`) is written by Python into the terminal
`MQL5\Files\` and read by the EA **non-common** (the tester seeds each agent sandbox
from that folder at run start). `rrm_meta.py` searches both. See `README_META_GATE.md`
§4 and the `SEA_MetaGate.mqh` header note for the full rationale.

---

## 2. THE non-negotiable rule: feature parity

The model is trained on numbers the EA logged, and scored on numbers the EA computes
live. **They must be produced by the same code.** Enforce this structurally:

> `BuildFeatureVector()` is called in BOTH `LogTSEvent()` (collect) and `MetaScore()`
> (gate). There is exactly ONE place features are computed. Never recompute a feature
> in Python from raw price — Python only ever reads the logged values.

If you break this rule the model silently rots. This is the #1 failure mode.

---

## 3. Feature vector (what `BuildFeatureVector()` returns)

All features are read at the **closed bar (shift=1)** — the same bar `TS` is
evaluated on. No shift=0 / no look-ahead. Group A is preset-dependent (only the
enabled ones); Group B is always logged and is where most meta-edge lives.

**Group A — signal internals (log the raw value, not the pass/fail bool)**
- `bias_dir` (+1 / −1)
- `layer_id` (1/2/3), `layer_slope_ratio`
- For each **enabled** indicator in this preset: its raw value
  (`macd_hist`, `rsi`, `cci`, `adx`, `psar_dist_atr`, `dpi_hist`, …)

**Group B — context / regime (ALWAYS log — this is the meta-model's real edge)**
- `atr` (volatility level)
- `spread_pts`
- `hour` (0–23), `dow` (1–5)
- `dist_close_emaFast_atr` = (close − EMAfast) / ATR
- `ema_fast_slope_atr`, `ema_slow_slope_atr`
- `adx` (trend strength as context, even if not a voting indicator this preset)
- `bar_range_atr` = (high−low) / ATR
- `ret_vol_20` = stdev of last 20 bar returns

**Label-helper columns (logged alongside, NOT features):** `event_time`,
`symbol`, `preset`, `direction`, `sl_points`, `tp_points`, `time_barrier_bars`.
These let Python build the label; they are never fed to the model.

> **Per-preset models:** because enabled indicators differ per preset, train and
> export **one model per preset**. The gate is unchanged; you are only choosing,
> from data, which context makes each preset's strict signal trustworthy.

---

## 4. `TS_events_<PRESET>.csv` schema (written by the EA in COLLECT mode)

One row per `TS=1` event. Header written once in `OnInit`.

```
event_time,symbol,preset,direction,sl_points,tp_points,time_barrier_bars,
bias_dir,layer_id,layer_slope_ratio,<enabled_indicator_cols...>,
atr,spread_pts,hour,dow,dist_close_emaFast_atr,ema_fast_slope_atr,
ema_slow_slope_atr,adx,bar_range_atr,ret_vol_20
```

---

## 5. Label = triple-barrier (Python, `label_triple_barrier.py`)

For each logged event, define a **clean, fixed** outcome — NOT the EA's
trailing-managed result (managed exits make the label unstable). Use the price
series (your `MT5_DATA-*.csv`) to look forward from the entry bar:

- **Entry** = open of the bar *after* `event_time` (matches your TE at shift=0).
- **Upper barrier** = entry ± `tp_points` (direction-aware).
- **Lower barrier** = entry ∓ `sl_points`.
- **Vertical barrier** = `time_barrier_bars` bars after entry.
- **label = 1** if TP touched **before** SL and before the time barrier; else **0**.
- Compute on **net** terms: subtract spread/commission from the TP distance so the
  label reflects real profitability, not gross.

```python
# sketch
def label_event(px, entry_idx, direction, tp, sl, tmax, cost):
    entry = px.open[entry_idx]
    up  = entry + direction*(tp + cost)
    dn  = entry - direction*(sl)
    for k in range(entry_idx, min(entry_idx+tmax, len(px))):
        hi, lo = px.high[k], px.low[k]
        if direction*(hi-entry) >= (tp+cost) and lo... # check which touched first
        ...
    return 1 if tp_first else 0
```

(Handle the rare same-bar TP+SL touch conservatively as a loss.)

---

## 6. Train + validate + export (Python, `train_meta.py` / `export_mql5.py`)

Keep it a **logistic regression** for v1 — interpretable, and it exports to MQL5 as
plain weights.

```python
from sklearn.linear_model import LogisticRegression
from sklearn.preprocessing import StandardScaler
import numpy as np, pandas as pd

df = pd.read_csv("TS_events_RRM.csv")
y  = labels                      # from section 5
X  = df[FEATURE_COLS].values     # Group A (enabled) + Group B

scaler = StandardScaler().fit(X) # store mean_/scale_  -> exported for parity
Xs = scaler.transform(X)

# Purged + embargoed CV (mlfinlab PurgedKFold, or a small custom splitter).
# Evaluate the GATED strategy vs ungated with DEFLATED SHARPE + PBO,
# not just classification accuracy. Track how many configs you tried.

clf = LogisticRegression(class_weight="balanced").fit(Xs, y)

# Export: per feature -> (name, mean, std, weight); plus intercept, threshold.
export_rows = []
for name, m, s, w in zip(FEATURE_COLS, scaler.mean_, scaler.scale_, clf.coef_[0]):
    export_rows.append(("FEATURE", name, m, s, w))
```

### `MetaModel_<PRESET>.csv` schema (what the EA reads)
```
INTERCEPT,<b0>
THRESHOLD,<0..1, tune on validation>
FEATURE,atr,<mean>,<std>,<weight>
FEATURE,rsi,<mean>,<std>,<weight>
...
```
`FEATURE,name,mean,std,weight`. The `name` **must exactly match** the string
`BuildFeatureVector()` uses, so the EA can map each weight to the right live value.

---

## 7. MQL5 side — `SEA_MetaGate.mqh` (sketches, MQL5-only idioms)

### 7a. Inputs (add to `SEA_Config.mqh`, Zone 2 — always user-editable)
```mql5
input bool   Inp_META_Enabled     = false;   // OFF = today's behaviour, exactly
input bool   Inp_META_LogFeatures = false;   // ON only during COLLECT mode
input double Inp_META_Threshold   = 0.50;    // overridden by model file if present
input string Inp_META_ModelFile   = "MetaModel_RRM.csv";
input bool   Inp_META_SizeByScore = false;   // false = fixed size; true = scale lots
```

### 7b. Model storage (globals — no static locals)
```mql5
#define META_MAX 32
string g_meta_name[META_MAX];
double g_meta_mean[META_MAX], g_meta_std[META_MAX], g_meta_w[META_MAX];
int    g_meta_n       = 0;
double g_meta_b0      = 0.0;
double g_meta_thr     = 0.5;
bool   g_meta_ready   = false;
```

### 7c. Load at `OnInit`
```mql5
bool LoadMetaModel(const string fname)
{
   int h = FileOpen(fname, FILE_READ|FILE_CSV|FILE_ANSI, ',');
   if(h == INVALID_HANDLE) { Print("META: no model file, gate inert"); return false; }
   g_meta_n = 0;
   while(!FileIsEnding(h))
   {
      string tag = FileReadString(h);
      if(tag == "INTERCEPT")      g_meta_b0  = (double)FileReadString(h);
      else if(tag == "THRESHOLD") g_meta_thr = (double)FileReadString(h);
      else if(tag == "FEATURE" && g_meta_n < META_MAX)
      {
         g_meta_name[g_meta_n] = FileReadString(h);
         g_meta_mean[g_meta_n] = (double)FileReadString(h);
         g_meta_std [g_meta_n] = (double)FileReadString(h);
         g_meta_w   [g_meta_n] = (double)FileReadString(h);
         g_meta_n++;
      }
   }
   FileClose(h);
   g_meta_ready = (g_meta_n > 0);
   return g_meta_ready;
}
```

### 7d. The parity-critical mapping (ONE source of truth)
`BuildFeatureVector()` fills a name→value lookup used by BOTH logging and scoring.
`GetFeatureByName()` returns the current shift=1 value for a given feature name.
```mql5
double GetFeatureByName(const string n)
{
   if(n=="atr")                 return g_atr;
   if(n=="rsi")                 return g_rsi_val;
   if(n=="adx")                 return g_adx_val;
   if(n=="dist_close_emaFast_atr") return (Close1 - g_emaFast)/g_atr;
   // ... every feature name the exporter can emit
   Print("META: unknown feature ", n); return 0.0;
}
```

### 7e. Score
```mql5
double MetaScore()
{
   double z = g_meta_b0;
   for(int i=0; i<g_meta_n; i++)
   {
      double raw = GetFeatureByName(g_meta_name[i]);
      double zi  = (g_meta_std[i]==0.0) ? 0.0 : (raw - g_meta_mean[i]) / g_meta_std[i];
      z += g_meta_w[i] * zi;
   }
   return 1.0 / (1.0 + MathExp(-z));      // sigmoid
}
```

### 7f. The gate (called in `EvaluateTE()` AFTER TS validated, BEFORE execute)
```mql5
// returns true = allow trade; also sets size multiplier
bool EvaluateMetaGate(double &size_mult)
{
   size_mult = 1.0;
   if(!Inp_META_Enabled || !g_meta_ready) return true;   // inert => today's behaviour
   double s = MetaScore();
   double thr = (g_meta_thr>0 ? g_meta_thr : Inp_META_Threshold);
   if(s < thr) return false;                              // veto this TS
   if(Inp_META_SizeByScore) size_mult = 0.5 + s;          // e.g. scale lots by score
   return true;
}
```

### 7g. Wiring in `EvaluateTE()`
```mql5
// ... TS already == 1 and F filters passed ...
if(Inp_META_LogFeatures) LogTSEvent();     // COLLECT mode
double size_mult = 1.0;
if(!EvaluateMetaGate(size_mult)) return;   // GATE mode veto -> no trade
// existing execution, multiply computed lot by size_mult
```

`LogTSEvent()` appends one CSV row using the exact same `GetFeatureByName()` values,
plus the label-helper columns from section 4.

---

## 8. End-to-end procedure

1. **Compile** with the new module. Leave `Inp_META_Enabled=false`.
2. **COLLECT:** set `Inp_META_LogFeatures=true`; run the preset across your history/pairs in Strategy Tester → `TS_events_RRM.csv`.
3. **LABEL + TRAIN (Python):** run `label_triple_barrier.py` then `train_meta.py`; inspect deflated Sharpe of gated vs ungated under purged CV.
4. **EXPORT:** `export_mql5.py` writes `MetaModel_RRM.csv` into `MQL5\Files\`.
5. **GATE:** set `Inp_META_Enabled=true`, `Inp_META_LogFeatures=false`; re-run Tester.
6. **DECIDE:** ship only if out-of-sample **deflated Sharpe** (not win rate, not gross Sharpe) improves. Otherwise keep the model file out and the EA is unchanged.

---

## 9. Guardrails

- **Default off.** With `Inp_META_Enabled=false` or no model file, the EA behaves
  exactly as today. The feature is reversible with one input.
- **Meta can only subtract.** It vetoes or sizes trades `TS` already approved; it
  can never create a trade `TS` rejected. Your strict `VOTE_MODE_ALL` is preserved.
- **Net-of-cost labels.** Label on post-spread/commission outcome or the model
  learns to love trades that don't survive costs.
- **Purged CV + deflated Sharpe only.** Standard k-fold and gross Sharpe will lie
  here. Count your trials.
- **One model per preset.** Never mix presets in one model.
- **No look-ahead.** Every feature is a shift=1 (or older) value.

## 10. Why this avoids ONNX/Wine entirely

The deployed model is `N` multiplications, one add, one `MathExp`. There is no
onnxruntime, no external library, nothing Wine-specific to verify. If you later want
gradient-boosted trees, that is the moment to test whether `OnnxRun` works in your
Tester under Wine — but only then, and only if the logistic baseline has already
proven the pipeline pays for itself.
