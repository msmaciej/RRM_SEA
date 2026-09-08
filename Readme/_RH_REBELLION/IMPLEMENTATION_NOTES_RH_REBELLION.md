# PRESET_RH_REBELLION — Implementation Notes

Implements the Russ Horn **Forex Rebellion** 4-filter confluence system as a
first-class SEA preset. Generated against repo HEAD `b2ec8f3`. **Not yet
compiled** — MQL5 cannot be built in the authoring environment (see caveats).

## Files changed (413 insertions, 1 deletion, 4 files)

| File | What changed |
|------|--------------|
| `SEA_Config.mqh` | `#define SEA_BUILD_RH_REBELLION`; `PRESET_RH_REBELLION` enum member (+ trailing comma on `PRESET_TREND`); struct fields for QQE + trend-EMA voters. |
| `SEA_Inputs.mqh` | `Inp_RHR_*` input block, wrapped in `#ifdef SEA_BUILD_RH_REBELLION`. |
| `SEA_SignalEngine.mqh` | New voters: `CalculateQQE`, `Check_QQE_Order`, `Check_QQE_Zone`, `Check_RHR_Trend`; handles `h_qqe`/`h_qqe_rsi`/`h_rhr_trend`; cache + stats fields; both cache-reset blocks; 3 `CAST_VOTE_STAT` registrations; scanner wrappers; end-of-run stat prints. |
| `SEA_Presets.mqh` | `GetPresetName`, `GetPresetContractWording`, `ValidateRHR_ExitConfig`, and the full `ApplyPreset` case. |

Everything RH-specific is inside `#ifdef SEA_BUILD_RH_REBELLION` (inputs, preset
case, validator) or gated at runtime by `if(preset == PRESET_RH_REBELLION)` /
`m_settings.Ind_QQE_Enabled` / `m_settings.Ind_RHR_Trend_Enabled`, so the preset
is inert until its build flag is on and it is selected — exactly like XEMA.

## How to apply

```bash
cd RRM_SEA
git apply PRESET_RH_REBELLION.patch      # verified: applies cleanly on b2ec8f3
# — or — drop in the four modified files from modified_files/
```
Then recompile `SimpleEA_v1-05.mq5` in MetaEditor and select `PRESET_RH_REBELLION`.

## The four rules → engine mapping (as built)

| Rule | Mechanism | Where |
|------|-----------|-------|
| **2 — 4/5 EMA cross (direction / B)** | `STRAT_2EMA_CROSS_EMA`, `P_Ema1=4`, `P_Ema2=5` | ApplyPreset |
| **1 — price vs shifted 5 EMA** | `Check_RHR_Trend` voter; `iMA(5, shift 5, EMA, close)` | SignalEngine |
| **3 — QQE line order** | `Check_QQE_Order` voter | SignalEngine |
| **4 — QQE zone (50)** | `Check_QQE_Zone` voter | SignalEngine |

All three I-voters are enabled together and sit in SEA's inherently-unanimous
`CAST_VOTE_STAT` AND, so a trade fires only when the cross direction plus all
three filters agree — the "all four rules in line" behaviour of the original EA.

Stop: `SL_MODE_SWING` (default) or ATR. Exit: `TP_MODE_RR` (`RRRatio` 1.0="the
100" / 1.5="1 Point 5") and/or `Donchian_UseChannelExit` at period 21. Management:
`BE_MODE_R_MULTIPLE` at +1R + the universal LPR ladder + `TRAIL_EMA`.

## The QQE voter (the only genuinely new logic)

`CalculateQQE()` reimplements QQE Adv (SF/RSI/WP = 1/8/3) inline from `iRSI`:
`RSI_line = EMA(SF)` of RSI; a two-pass Wilder smoothing of `|ΔRSI_line|` scaled
by the QQE constant `4.236` builds the trailing `signal_line`. It is
self-contained (no external `.ex4`, cannot crash the EA), modelled on the inline
CI voter.

**Compile-time fallback.** Define `SEA_QQE_USE_ICUSTOM` in `SEA_Config.mqh` to
read the real `QQE_ADV.ex4` via `iCustom("QQE ADV", SF, RSI, WP)` instead
(bit-identical to the original indicator, at the cost of an external dependency).
Default OFF (native).

`Inp_RHR_QQE_RequireCross` (default false) switches Rules 3 & 4 between the
shipped-EA **static-position** reading and the manual-strict **fresh-cross**
reading.

## Caveats — read before trading

1. **Not compiled.** Field/brace/`#ifdef` balance were checked programmatically,
   but only MetaEditor will confirm a clean build. Expect the possibility of
   small first-compile fixes.
2. **QQE math is a reconstruction.** The native `CalculateQQE` targets the
   standard QQE algorithm; it has **not** been validated bar-for-bar against
   `QQE_ADV.ex4`. Before trusting live signals, either (a) compare the native
   output to the real indicator on a chart, or (b) compile with
   `SEA_QQE_USE_ICUSTOM` to use the real `.ex4` directly.
3. **v1 enters at market**, not on a pending stop-order beyond the signal candle.
   SEA has no pending-order path in the executor; `Inp_RHR_PendingBufferPips` is
   reserved for that planned extension. Market entry on a closed-bar confluence
   is a faithful approximation.
4. **Secondary/stale QQE signals** and the manual's discretionary "is it clearly
   past the line?" judgement are not modelled — the preset is mechanical.
5. **ConfigSync / scanner UI:** newer presets (XEMA included) carry no
   `SEA_ConfigSync.mqh` entries, so none were added. If you later expose
   RH_REBELLION to the multi-symbol scanner, mirror whatever XEMA does there.

## Suggested validation sequence

1. Compile with the build flag on; select the preset; confirm inputs appear.
2. On EURUSD H1, enable `DebugLevel = DEBUG_INDICATORS`; confirm the
   `[IND_QQE_ORD]`, `[IND_QQE_ZONE]`, `[IND_RHR_TREND]` log lines and the
   end-of-run `QQE_Order` / `QQE_Zone` / `RHR_Trend` stat rows.
3. Overlay `QQE_ADV.ex4` on the chart and spot-check that `Check_QQE_*` fires on
   the same bars — or compile with `SEA_QQE_USE_ICUSTOM` and diff the two.
4. Confirm entries coincide with "all four in line" bars from the original EA.
