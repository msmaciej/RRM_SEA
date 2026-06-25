# SimpleEA: Extending with Custom Indicators

**For the system architecture overview, see [README_SYSTEM.md](README_SYSTEM.md)**  
**For existing indicator voting rules, see [README_INDICATORS.md](README_INDICATORS.md)**

---

## Table of Contents

- [Overview](#overview)
- [Architecture: The Indicator Plugin Pattern](#architecture-the-indicator-plugin-pattern)
- [Complete Example: Adding Ichimoku Cloud](#complete-example-adding-ichimoku-cloud)
  - [Step 1: Input Configuration (SEA_Config.mqh)](#step-1-input-configuration-sea_configmqh)
  - [Step 2: Settings Struct Fields (SEA_Config.mqh)](#step-2-settings-struct-fields-sea_configmqh)
  - [Step 3: Input Mapping in InitializeConfig() (SEA_Config.mqh)](#step-3-input-mapping-in-initializeconfig-sea_configmqh)
  - [Step 4: Indicator Handle Declaration (SEA_SignalEngine.mqh)](#step-4-indicator-handle-declaration-sea_signalenginemqh)
  - [Step 5: OnInit() — Handle Creation (SEA_SignalEngine.mqh)](#step-5-oninit--handle-creation-sea_signalenginemqh)
  - [Step 6: OnDeinit() — Handle Release (SEA_SignalEngine.mqh)](#step-6-ondeinit--handle-release-sea_signalenginemqh)
  - [Step 7: Vote Function (SEA_SignalEngine.mqh)](#step-7-vote-function-sea_signalenginemqh)
  - [Step 8: Indicator Registry (SEA_Config.mqh)](#step-8-indicator-registry-sea_configmqh)
  - [Step 9: Voting Loop Integration (SEA_SignalEngine.mqh)](#step-9-voting-loop-integration-sea_signalenginemqh)
  - [Step 10: Cockpit Display (SEA_SignalEngine.mqh — optional)](#step-10-cockpit-display-sea_signalenginemqh--optional)
- [Testing Guide](#testing-guide)
- [Common Indicator Patterns](#common-indicator-patterns)
- [Best Practices](#best-practices)
- [Troubleshooting](#troubleshooting)
- [Files Modified Summary](#files-modified-summary)

---

## Overview

SimpleEA uses a **plugin-style architecture** for indicator voting. Each indicator is a self-contained unit consisting of:

- A pair of **user-facing inputs** (enable toggle + parameters)
- A **settings struct field** that carries the configuration at runtime
- An **indicator handle** managed inside `CSignalEngine`
- A **vote function** (`Check_XYZ`) that returns `true` (pass) or `false` (fail)
- A **CAST_VOTE call** in the main voting loop

Adding a new indicator means adding these five components across two files: `SEA_Config.mqh` and `SEA_SignalEngine.mqh`. No changes to `SimpleEA_v1-03.mq5` or other modules are required.

### When to Add a Custom Indicator

- You need a signal type not covered by the built-in 11 indicators
- You want to combine multiple conditions into a single named vote
- You are backtesting a specific strategy that uses a non-standard confirmation

### Prerequisites

- Working knowledge of MQL5 (handles, `CopyBuffer`, `iClose`, etc.)
- Familiarity with MT5 indicator buffer layouts (check MQL5 documentation for buffer indices)
- Basic understanding of the 9-step pipeline described in [README_INDICATORS.md](README_INDICATORS.md)

---

## Architecture: The Indicator Plugin Pattern

Each indicator follows an identical five-component pattern:

```
┌─────────────────────────────────────────────────────────────────────┐
│  COMPONENT 1: User Input (SEA_Config.mqh)                           │
│  input bool Inp_Use_Ichi = false;  // Enable toggle                 │
│  input int  Inp_P_IchiTenkan = 9;  // Period parameter              │
├─────────────────────────────────────────────────────────────────────┤
│  COMPONENT 2: Settings Struct Fields (SEA_Config.mqh)               │
│  bool Use_Ichi;                    // Enable flag                   │
│  int  P_IchiTenkan;                // Period stored in struct        │
├─────────────────────────────────────────────────────────────────────┤
│  COMPONENT 3: Handle + Init/Release (SEA_SignalEngine.mqh)          │
│  int h_ichi;                       // Private member                │
│  h_ichi = iIchimoku(...);          // Created in Init()             │
│  IndicatorRelease(h_ichi);         // Freed in Release()            │
├─────────────────────────────────────────────────────────────────────┤
│  COMPONENT 4: Vote Function (SEA_SignalEngine.mqh)                  │
│  bool Check_Ichi(int bias, int shift) { ... }                       │
├─────────────────────────────────────────────────────────────────────┤
│  COMPONENT 5: CAST_VOTE Call (SEA_SignalEngine.mqh)                 │
│  CAST_VOTE(m_settings.Use_Ichi, m_settings.W_Ichi,                  │
│            Check_Ichi(bias, v_shift))                               │
└─────────────────────────────────────────────────────────────────────┘
```

### Visual Overview

```
SEA_Config.mqh                    SEA_SignalEngine.mqh
──────────────────────            ─────────────────────────────────────
 input bool Inp_Use_Ichi  ──────►  m_settings.Use_Ichi (Init gate)
 input int  Inp_P_IchiT   ──────►  m_settings.P_IchiTenkan
                                   │
 struct ST_Settings:               ▼
   bool Use_Ichi          ◄──  h_ichi = iIchimoku(...)    [Init()]
   int  P_IchiTenkan      ◄──  IndicatorRelease(h_ichi)   [Release()]
   double W_Ichi                   │
                                   ▼
 InitializeConfig():           Check_Ichi(bias, shift)
   cfg.Use_Ichi =                  │
     Inp_Use_Ichi                  ▼
                               CAST_VOTE(Use_Ichi, W_Ichi,
                                         Check_Ichi(...))
                                   │
                                   ▼
                               vote_weight += W_Ichi  (if pass)
```

---

## Centralized Indicator Registry (Architectural Improvement)

### Problem Solved

**Before (scattered implementation):**
When adding a new indicator, you had to update 6-8 different locations across multiple files:
- `SEA_Config.mqh` (inputs, struct fields, initialization)
- `SEA_SignalEngine.mqh` (handle, init, release, vote function, voting loop)
- `SEA_UI.mqh` (display formatting)
- `SEA_Presets.mqh` (each preset configuration)
- Manual counting and list management

**After (centralized registry):**
All indicator metadata is now stored in a **single centralized registry** (`g_indicator_registry[]`) that automatically handles:
- ✅ Indicator counting (`GetEnabledIndicatorCount()`)
- ✅ List generation (`GetEnabledIndicatorList()`)
- ✅ Cockpit display
- ✅ Status panel updates
- ✅ UI formatting

### How It Works

#### 1. Registry Declaration (SEA_Config.mqh)

```mql5
// Metadata for a single voting indicator
struct SIndicatorMeta {
   string name;         // Full display name (e.g. "ChoppinessIndex")
   string short_name;   // Compact code for UI (e.g. "CI")
   bool   is_enabled;   // Cached enabled state
   int    weight;       // Vote weight
};

// Global registry - currently 14 indicators
SIndicatorMeta g_indicator_registry[14];
```

#### 2. Registry Initialization (SEA_Config.mqh)

Called once in `OnInit()` after `InitializeConfig()` and `ApplyPreset()`:

```mql5
void InitializeIndicatorRegistry(const ST_Settings &cfg)
{
   int i = 0;

   // Alphabetical order for consistency
   g_indicator_registry[i].name       = "ADX";
   g_indicator_registry[i].short_name = "ADX";
   g_indicator_registry[i].is_enabled = cfg.Ind_Adx_Enabled;
   g_indicator_registry[i].weight     = cfg.Ind_Adx_Weight;
   i++;

   // ... repeat for all 14 indicators ...
}
```

#### 3. Automatic List Generation

```mql5
// Get comma-separated list of enabled indicators
string list = GetEnabledIndicatorList(Settings, false); // Full names
// → "ADX, MACD, PSAR, CCI"

string compact = GetEnabledIndicatorList(Settings, true); // Short names
// → "ADX, MACD, PSAR, CCI"
```

#### 4. Automatic Counting

```mql5
int count = GetEnabledIndicatorCount(Settings);
// Returns number of enabled indicators (used for validation warnings)
```

### Adding a New Indicator (Updated Process)

When adding a new indicator to the registry (Step 8 in the main example):

```mql5
// Step 8.1: Add to InitializeIndicatorRegistry() in SEA_Config.mqh
g_indicator_registry[i].name       = "Ichimoku";
g_indicator_registry[i].short_name = "Ichi";
g_indicator_registry[i].is_enabled = cfg.Use_Ichi;
g_indicator_registry[i].weight     = cfg.W_Ichi;
i++;

// Step 8.2: Update array size (was 14, now 15)
SIndicatorMeta g_indicator_registry[15];

// Step 8.3: Update GetEnabledIndicatorCount() to include the new flag
int GetEnabledIndicatorCount(const ST_Settings &cfg)
{
   int count = 0;
   if(cfg.Ind_EmaSig_Enabled)    count++;
   // ... existing indicators ...
   if(cfg.Use_Ichi)              count++; // ADD THIS LINE
   return count;
}
```

**That's it!** No changes needed to:
- ❌ `SEA_UI.mqh` — list generation is automatic
- ❌ `SimpleEA_v1-03.mq5` — main file unchanged
- ❌ `SEA_Presets.mqh` — only if you want preset-specific config

### Benefits

| Before | After |
|--------|-------|
| Update 6-8 files | Update 2-3 functions in 1 file |
| Manual list formatting | Automatic from registry |
| Manual counting logic | Automatic from registry |
| Easy to miss a location | Compile-time array bounds checking |
| Preset files scattered | Registry initialized once per preset |

### Example: Registry in Action

```mql5
// SimpleEA_v1-03.mq5 OnInit()
InitializeConfig();                    // Step 1: Load inputs
ApplyPreset(InpPreset, Settings);      // Step 2: Apply preset
InitializeIndicatorRegistry(Settings); // Step 3: Populate registry

// Now all UI functions automatically know which indicators are enabled:
int enabled = GetEnabledIndicatorCount(Settings);
// → Returns 5 (for example)

string list = GetEnabledIndicatorList(Settings, false);
// → "ADX, ChoppinessIndex, MACD, PSAR, CCI"

// Cockpit display automatically iterates g_indicator_registry[]
// Status panel automatically formats enabled indicator names
// No manual updates required!
```

### Migration Notes

**If you have old custom indicators:**
1. Add them to `InitializeIndicatorRegistry()`
2. Increment array size
3. Add flag to `GetEnabledIndicatorCount()`
4. Remove old manual list/count code (optional cleanup)

**Backward Compatibility:**
- Existing code continues to work
- Registry is additive (doesn't break existing logic)
- Old manual list functions still available but deprecated

---

## Complete Example: Adding Ichimoku Cloud

The following walkthrough adds **Ichimoku Cloud** as an optional voting indicator. The vote passes when:

- **LONG:** Price (close) is **above** the Kumo cloud (Senkou Span A and B)
- **SHORT:** Price (close) is **below** the Kumo cloud

The Ichimoku indicator in MT5 exposes these buffers:

| Buffer | Content |
|--------|---------|
| 0 | Tenkan-sen |
| 1 | Kijun-sen |
| 2 | Senkou Span A |
| 3 | Senkou Span B |
| 4 | Chikou Span |

---

### Step 1: Input Configuration (SEA_Config.mqh)

Add user-facing inputs in the **ZONE 3A** (Preset Info) section, alongside existing indicator inputs such as `Inp_Use_Macd`, `Inp_Use_Rsi`, etc.

```mql5
// --- Ichimoku Cloud Vote ---
input bool   Inp_Use_Ichi        = false; // [VOTE] Enable Ichimoku Cloud vote
input double Inp_W_Ichi          = 1.0;   // [VOTE] Ichimoku weight (THRESHOLD mode)
input int    Inp_P_IchiTenkan    = 9;     // Ichimoku Tenkan-sen period
input int    Inp_P_IchiKijun     = 26;    // Ichimoku Kijun-sen period
input int    Inp_P_IchiSenkou    = 52;    // Ichimoku Senkou Span B period
```

---

### Step 2: Settings Struct Fields (SEA_Config.mqh)

Add fields to the `ST_Settings` struct. Follow the grouping pattern: weight field next to the enable flag, period fields together with other indicator periods.

```mql5
// In the "Active Votes" section of ST_Settings:
bool Use_Ichi;

// In the "Per-indicator weights" section:
double W_Ichi;

// In the "Indicators (Periods)" section:
int P_IchiTenkan;
int P_IchiKijun;
int P_IchiSenkou;
```

---

### Step 3: Input Mapping in InitializeConfig() (SEA_Config.mqh)

Map the inputs to the struct in `InitializeConfig()`. Find the block that maps other indicator flags (e.g., `cfg.Use_Macd = Inp_Use_Macd;`) and add the Ichimoku lines alongside them.

```mql5
// Active votes
cfg.Use_Ichi     = Inp_Use_Ichi;
cfg.W_Ichi       = Inp_W_Ichi;

// Periods
cfg.P_IchiTenkan = Inp_P_IchiTenkan;
cfg.P_IchiKijun  = Inp_P_IchiKijun;
cfg.P_IchiSenkou = Inp_P_IchiSenkou;
```

---

### Step 4: Indicator Handle Declaration (SEA_SignalEngine.mqh)

Add a private handle member to the `CSignalEngine` class. Place it in the `// --- 1. INDICATOR HANDLES ---` section alongside existing handles.

```mql5
int h_ichi;  // Ichimoku Cloud
```

Also initialize it to `INVALID_HANDLE` in the constructor:

```mql5
// In CSignalEngine() constructor body, alongside other h_xxx = INVALID_HANDLE lines:
h_ichi = INVALID_HANDLE;
```

---

### Step 5: OnInit() — Handle Creation (SEA_SignalEngine.mqh)

Create the handle inside `Init()`, in the **optional indicators** block (after `h_ema1`–`h_ema4` are created). Mirror the guard pattern used for other indicators:

```mql5
h_ichi = (m_settings.Use_Ichi
          ? iIchimoku(m_symbol, PERIOD_CURRENT,
                      m_settings.P_IchiTenkan,
                      m_settings.P_IchiKijun,
                      m_settings.P_IchiSenkou)
          : INVALID_HANDLE);
```

---

### Step 6: OnDeinit() — Handle Release (SEA_SignalEngine.mqh)

Release the handle in `Release()`. Add one line beside the other `IndicatorRelease` calls:

```mql5
if(h_ichi != INVALID_HANDLE) { IndicatorRelease(h_ichi); h_ichi = INVALID_HANDLE; }
```

---

### Step 7: Vote Function (SEA_SignalEngine.mqh)

Add a private vote function in the **`// --- 5. SIGNAL CHECKS (VOTING LOGIC) ---`** section, after the existing `Check_Ross()` function. The function must:

- Accept `int bias` (+1 = LONG, -1 = SHORT) and `int shift` (bar offset; always use `1` for closed-bar evaluation)
- Return `bool` — `true` if the indicator confirms the bias, `false` otherwise
- Use `GetVal(handle, shift, buffer_index)` for buffer reads

```mql5
// Vote 12: Ichimoku Cloud (Price vs Kumo)
//
// Ichimoku iIchimoku() buffer layout:
//   Buffer 0 = Tenkan-sen
//   Buffer 1 = Kijun-sen
//   Buffer 2 = Senkou Span A  (cloud upper/lower depending on trend)
//   Buffer 3 = Senkou Span B  (cloud upper/lower depending on trend)
//   Buffer 4 = Chikou Span
//
// Vote logic:
//   LONG:  close > Max(SpanA, SpanB)  → price above cloud
//   SHORT: close < Min(SpanA, SpanB)  → price below cloud
//
bool Check_Ichi(int bias, int shift)
{
   if(h_ichi == INVALID_HANDLE) return false;
   double span_a = GetVal(h_ichi, shift, 2);
   double span_b = GetVal(h_ichi, shift, 3);
   double cl     = iClose(m_symbol, PERIOD_CURRENT, shift);

   if(span_a <= 0.0 || span_b <= 0.0) return false; // Guard against missing data

   double cloud_top    = MathMax(span_a, span_b);
   double cloud_bottom = MathMin(span_a, span_b);

   if(bias == 1)  return (cl > cloud_top);    // LONG: price above cloud
   if(bias == -1) return (cl < cloud_bottom); // SHORT: price below cloud
   return false;
}
```

---

### Step 8: Indicator Registry (SEA_Config.mqh)

The codebase maintains a **centralized indicator registry** (`g_indicator_registry[14]`) initialized in `OnInit()` via `InitializeIndicatorRegistry()`. This registry drives all indicator count displays and list outputs across the UI.

**Add your new indicator to `InitializeIndicatorRegistry()` in `SEA_Config.mqh`:**

```mql5
// Inside InitializeIndicatorRegistry() — add one entry for your new indicator:
g_indicator_registry[i].name       = "Ichimoku";      // Full name for status panel
g_indicator_registry[i].short_name = "Ichi";          // Short code for cockpit compact list
g_indicator_registry[i].is_enabled = cfg.Use_Ichi;
g_indicator_registry[i].weight     = cfg.W_Ichi;
i++;
// IMPORTANT: also update the array declaration size from 14 to 15 (or higher)
```

**Also update the array declaration size:**

```mql5
// In SEA_Config.mqh — change the registry array size:
SIndicatorMeta g_indicator_registry[15];  // was 14; +1 for Ichimoku
```

**Also update `GetEnabledIndicatorCount()` in `SEA_Config.mqh` to include the new flag:**

```mql5
// Add inside GetEnabledIndicatorCount():
if(cfg.Use_Ichi) count++;
```

These three additions ensure your indicator appears in all counts, lists, status panels, and the cockpit display automatically — with **no changes required** to `SEA_Presets.mqh`, `SEA_UI.mqh`, or `SimpleEA_v1-03.mq5`.

---

### Step 9: Voting Loop Integration (SEA_SignalEngine.mqh)

Add a single `CAST_VOTE` line in the voting block inside `GetDirection()`. Place it after the last existing `CAST_VOTE` line (currently `Check_Ross`):

```mql5
CAST_VOTE(m_settings.Use_Ichi, m_settings.W_Ichi, Check_Ichi(bias, v_shift))
```

The `CAST_VOTE` macro handles both `VOTE_MODE_THRESHOLD` (accumulates `vote_weight`) and `VOTE_MODE_ALL` (updates `all_pass`):

```mql5
// Macro reference (already defined in SEA_SignalEngine.mqh — do NOT redefine):
// #define CAST_VOTE(use_flag, weight_field, check_expr) \
//    if(use_flag) { \
//       bool _cv_pass = (check_expr); \
//       if(_cv_pass) vote_weight += weight_field; \
//       else         all_pass    = false; \
//    }
```

---

### Step 10: Cockpit Display (SEA_SignalEngine.mqh — optional)

To show the Ichimoku vote state in the Cockpit panel, add a snapshot entry inside `CaptureVoteSnapshots()`. Place it after the existing `Use_Ross` block:

```mql5
if(m_settings.Use_Ichi && h_ichi != INVALID_HANDLE)
{
   bool b = Check_Ichi(1,  shift);
   bool s = Check_Ichi(-1, shift);
   double span_a = GetVal(h_ichi, shift, 2);
   double span_b = GetVal(h_ichi, shift, 3);

   out[count].name    = "Ichi";
   out[count].enabled = true;

   if(b)      { out[count].state = "BUY";  out[count].reason = StringFormat("(above cloud %.5f)", MathMax(span_a, span_b)); }
   else if(s) { out[count].state = "SELL"; out[count].reason = StringFormat("(below cloud %.5f)", MathMin(span_a, span_b)); }
   else       { out[count].state = "FLAT"; out[count].reason = "(inside cloud)"; }

   out[count].vote_result = CalcVoteResult(current_bias, out[count].state);
   count++;
}
```

Also expand the `ArrayResize(out, 15)` call at the top of `CaptureVoteSnapshots()` to accommodate the new Ichimoku entry (e.g., change `15` to `16`).

---

## Testing Guide

### 1. Compile and Load

1. Save all modified files.
2. In MetaEditor, press **F7** to compile `SimpleEA_v1-03.mq5`.
3. Resolve any compilation errors before proceeding.

### 2. Enable in EA Inputs

1. Attach the EA to a chart or open Strategy Tester.
2. In the EA Inputs tab, locate **`Inp_Use_Ichi`** and set it to `true`.
3. Verify the period inputs (`Inp_P_IchiTenkan`, etc.) are set to expected values.

### 3. Verify in Cockpit

1. Enable `Inp_ShowCockpit = true` (or the equivalent UI input).
2. The Cockpit panel should display an **"Ichi"** row.
3. Check that it shows `BUY`, `SELL`, or `FLAT` consistent with the chart's price relative to the cloud.

### 4. Check Logs

Enable `Inp_DebugFlow = true` and run a brief Strategy Tester pass. In the **Journal** tab, look for:

- `VOTE_DETAIL[...]: ... | Ichi: PASS/FAIL(w=1.0)` confirming the vote is being evaluated.
- No `CRITICAL ERROR` messages related to the Ichimoku handle.

---

## Common Indicator Patterns

Use these templates as a starting point. Replace `XYZ` with your indicator name.

---

### Oscillator Template (RSI, CCI, Stochastic style)

Suitable for indicators that produce a single value oscillating around a central level or between bounds.

```mql5
// Vote: XYZ Oscillator
bool Check_XYZ(int bias, int shift)
{
   if(h_xyz == INVALID_HANDLE) return false;
   double val = GetVal(h_xyz, shift, 0); // Buffer 0 = main line

   // LONG: value in bullish zone; SHORT: value in bearish zone
   if(bias == 1)  return (val > m_settings.T_XyzBullish);
   if(bias == -1) return (val < m_settings.T_XyzBearish);
   return false;
}
```

**Inputs needed:** enable toggle, weight, period, upper threshold, lower threshold.

---

### Position Template (PSAR, Bollinger Bands style)

Suitable for indicators that produce a price-level output; the vote compares price to that level.

```mql5
// Vote: XYZ Price-Level
bool Check_XYZ(int bias, int shift)
{
   if(h_xyz == INVALID_HANDLE) return false;
   double level = GetVal(h_xyz, shift, 0);
   double cl    = iClose(m_symbol, PERIOD_CURRENT, shift);

   if(bias == 1)  return (cl > level); // LONG: price above indicator
   if(bias == -1) return (cl < level); // SHORT: price below indicator
   return false;
}
```

**Inputs needed:** enable toggle, weight, indicator-specific parameters.

---

### Histogram Template (MACD style)

Suitable for indicators with a main line and a signal line where the histogram direction matters.

```mql5
// Vote: XYZ Histogram
bool Check_XYZ(int bias, int shift)
{
   if(h_xyz == INVALID_HANDLE) return false;
   double main_line   = GetVal(h_xyz, shift, 0); // Buffer 0 = main
   double signal_line = GetVal(h_xyz, shift, 1); // Buffer 1 = signal

   // Require both zero-line position and histogram direction
   if(bias == 1)  return (main_line > 0 && main_line > signal_line);
   if(bias == -1) return (main_line < 0 && main_line < signal_line);
   return false;
}
```

**Inputs needed:** enable toggle, weight, fast period, slow period, signal period.

---

### Cross Template (MA Cross, Ichimoku Cross style)

Suitable for indicators where two lines crossing produces the signal.

```mql5
// Vote: XYZ Line Cross
bool Check_XYZ(int bias, int shift)
{
   if(h_xyz == INVALID_HANDLE) return false;
   double fast_curr = GetVal(h_xyz, shift,     0); // Buffer 0 = fast line, current bar
   double fast_prev = GetVal(h_xyz, shift + 1, 0); // fast line, one bar earlier
   double slow_curr = GetVal(h_xyz, shift,     1); // Buffer 1 = slow line, current bar
   double slow_prev = GetVal(h_xyz, shift + 1, 1); // slow line, one bar earlier

   bool bullish_cross = (fast_prev <= slow_prev) && (fast_curr > slow_curr);
   bool bearish_cross = (fast_prev >= slow_prev) && (fast_curr < slow_curr);

   if(bias == 1)  return bullish_cross;
   if(bias == -1) return bearish_cross;
   return false;
}
```

**Note:** Cross-based votes are strict. Consider using a position-based check (fast > slow) for less lag.

---

## Best Practices

### Naming Conventions

| Item | Convention | Example |
|------|-----------|---------|
| Input variable | `Inp_Use_XYZ`, `Inp_P_XYZ*`, `Inp_W_XYZ` | `Inp_Use_Ichi` |
| Struct field | `Use_XYZ`, `P_XYZ*`, `W_XYZ` | `Use_Ichi` |
| Handle | `h_xyz` (lowercase) | `h_ichi` |
| Vote function | `Check_XYZ(int bias, int shift)` | `Check_Ichi` |
| Snapshot name | Short display label (≤6 chars) | `"Ichi"` |

### Validation Patterns

- **Always guard** the vote function: `if(h_xyz == INVALID_HANDLE) return false;`
- **Guard invalid data:** Check for `0.0`, `DBL_MAX`, or other sentinel values before using buffer data.
- **Guard buffer reads:** `GetVal()` returns `0.0` on failure; ensure `0.0` is not a valid indicator value for your logic.

### Use Closed Bar (shift=1)

All vote functions receive `shift` from the calling site; do not hard-code `0`. In `GetDirection()`, `v_shift` is set to `m_settings.ma_v_shift` (default `1` = closed bar). This prevents signal repainting.

### Weight Support

Always add a weight field (`W_XYZ`) even if you initially set it to `1.0`. This allows users to fine-tune the indicator's contribution in `VOTE_MODE_THRESHOLD` mode without code changes.

### Documentation Requirements

Add a comment block above the vote function describing:

- The indicator's buffer layout
- The exact LONG and SHORT conditions
- Any edge cases or MT5-specific notes

---

## Troubleshooting

### Indicator Not Appearing in Cockpit

**Symptom:** Cockpit panel does not show a row for the new indicator.

**Causes and fixes:**

1. `Inp_Use_Ichi` is `false` — enable it in EA inputs.
2. The `CaptureVoteSnapshots()` block was not added — verify Step 10.
3. `ArrayResize(out, N)` is too small — increase `N` to accommodate the new entry.

---

### Vote Not Counting

**Symptom:** Vote count in Cockpit is lower than expected; Ichimoku row shows PASS but votes do not increase.

**Causes and fixes:**

1. The `CAST_VOTE` line was not added to `GetDirection()` — verify Step 9.
2. `m_settings.Use_Ichi` is `false` at runtime — check `InitializeConfig()` mapping (Step 3).
3. `VoteThreshold <= 1` — the pipeline bypasses voting entirely (Step 7 in the 9-step pipeline). Set a higher threshold to test voting.

---

### Handle Creation Fails

**Symptom:** `CRITICAL ERROR` in journal, or `h_ichi == INVALID_HANDLE` during a vote.

**Causes and fixes:**

1. Wrong symbol or timeframe string — ensure `m_symbol` and `PERIOD_CURRENT` are used.
2. Indicator not installed on the MT5 terminal — verify the indicator is available in your MT5 build.
3. Invalid parameters (e.g., period = 0) — add a parameter validation guard before calling `iIchimoku()`.

---

### Wrong Vote Direction

**Symptom:** Ichimoku shows SELL when price is clearly above the cloud.

**Causes and fixes:**

1. Buffer indices are swapped — verify the MT5 documentation for the specific indicator's buffer layout.
2. Span A vs Span B logic is inverted — review `MathMax` / `MathMin` logic in `Check_Ichi`.
3. Using `shift=0` instead of `shift=1` — always evaluate on the closed bar to avoid repainting.

---

## Files Modified Summary

| File | Section | Change Type |
|------|---------|------------|
| `SEA_Config.mqh` | ZONE 3A input declarations | Add `input` variables for enable flag, weight, and parameters |
| `SEA_Config.mqh` | `ST_Settings` struct | Add `bool Use_XYZ`, `double W_XYZ`, `int P_XYZ*` fields |
| `SEA_Config.mqh` | `InitializeConfig()` | Map new inputs to struct fields |
| `SEA_Config.mqh` | `InitializeIndicatorRegistry()` | Add entry to the centralized indicator registry |
| `SEA_Config.mqh` | `GetEnabledIndicatorCount()` | Add `cfg.Use_XYZ` flag to the count |
| `SEA_Config.mqh` | `g_indicator_registry[N]` | Increment array declaration size by 1 |
| `SEA_SignalEngine.mqh` | `// --- 1. INDICATOR HANDLES ---` | Declare `int h_xyz` private member |
| `SEA_SignalEngine.mqh` | `CSignalEngine()` constructor | Initialise `h_xyz = INVALID_HANDLE` |
| `SEA_SignalEngine.mqh` | `Init()` | Create handle with `iXXX(...)` guarded by `Use_XYZ` |
| `SEA_SignalEngine.mqh` | `Release()` | Release handle: `IndicatorRelease(h_xyz)` |
| `SEA_SignalEngine.mqh` | `// --- 5. SIGNAL CHECKS ---` | Add `Check_XYZ(int bias, int shift)` vote function |
| `SEA_SignalEngine.mqh` | `GetDirection()` voting block | Add `CAST_VOTE(Use_XYZ, W_XYZ, Check_XYZ(...))` |
| `SEA_SignalEngine.mqh` | `CaptureVoteSnapshots()` (optional) | Add snapshot block for Cockpit display; expand `ArrayResize` by 1 |

No changes required in `SimpleEA_v1-03.mq5`, `SEA_Presets.mqh`, `SEA_TradeExecutor.mqh`, `SEA_UI.mqh`, or `SEA_Reporting.mqh`.
