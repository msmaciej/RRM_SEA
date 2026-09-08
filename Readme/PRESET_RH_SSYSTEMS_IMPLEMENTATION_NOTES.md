# Implementation Notes — Russ Horn Presets (RH_1MS, RH_STS, RH_SS, RH_GS, RH_SM)

Adds five Russ Horn systems to SimpleEA as first-class presets, plus the shared engine
infrastructure they need. Mirrors the pattern established by `IMPLEMENTATION_NOTES_RH_REBELLION.md`.

**Files changed:** `SEA_Config.mqh`, `SEA_SignalEngine.mqh`, `SEA_Presets.mqh`
(354 insertions, 11 deletions). No new external indicator files — every voter is computed
inside `SEA_SignalEngine.mqh` from MT5 built-ins (`iWPR`, `iMomentum`, `iOsMA`, inline
Heiken-Ashi), exactly like the existing ADX / CI / DPI voters.

**Compile status:** all three files are brace-balanced and the parenthesis delta is unchanged
from the pristine tree (no new imbalance). The code follows the verified in-repo signatures
(`Check_X(int bias,int shift)`, `IndReadOK`, `CAST_VOTE_STAT`, the ribbon handle-creation
sites). It has NOT been run through MetaEditor here (no MQL5 compiler in this environment) —
do a compile pass in your Wine/MT5 MetaEditor; the spots most likely to need a nudge are listed
under "Compile checklist" below.

---

## 1. Preset short-codes (as per your `Readme/_RH_PRESETS` + `_RH_Indicators` folders)

| Enum | System | Source template |
|------|--------|-----------------|
| `PRESET_RH_1MS` | 1-Minute Scalper | `_RH_1MS_TPL_1minute scalper.tpl` |
| `PRESET_RH_STS` | Sea Trading System | `_RH_STS_sea trading a/b.tpl` |
| `PRESET_RH_SS`  | Super System | `_RH_SS_the super system.tpl` |
| `PRESET_RH_GS`  | Golden Strategy | `_RH_GS_golden strategy.tpl` |
| `PRESET_RH_SM`  | Secret Method | `_RH_SM_3 secret method.tpl` |

---

## 2. Shared engine additions (`SEA_Config.mqh` + `SEA_SignalEngine.mqh`)

### 2.1 MA method + per-slot applied price
- `EMaMethod` gained `METHOD_SMMA` and `METHOD_LWMA`.
- `ST_Settings` gained `int MaApplied1..4` (ENUM_APPLIED_PRICE as int; default `PRICE_CLOSE`).
- New helpers `MMethodMap()` and `MAppliedForSlot(slot)` map the config to `iMA()` arguments.
- Both ribbon handle-creation sites (primary init + the ReadEmaSafe re-create fallback) now use
  them, so a slot can be `SMMA`/`LWMA` and read `OPEN`/`HIGH`/`LOW`. Non-RH presets keep
  `PRICE_CLOSE` (baseline default set in `ApplyPreset`), so their behaviour is byte-for-byte
  unchanged.

### 2.2 New vote modes
- `ERsiMode::RSI_BREAKOUT_OBOS` — long `RSI > T_RsiOB`, short `RSI < T_RsiOS` (RH_SS 80/20).
- `EStochMode::STO_CROSS_LEVEL` — long `%K > T_StoOS`, short `%K < T_StoOB` (RH_1MS 20/80).
- Both added as new branches inside the existing `Check_RSI` / `Check_Sto` voters.

### 2.3 New voters (inline, MT5 built-ins)
| Voter | Handle | Config | Rule |
|-------|--------|--------|------|
| `Check_WPR` | `iWPR(P_Wpr)` | `Ind_Wpr_Enabled`, `T_WprUpper`, `T_WprLower` | long `%R>upper`, short `%R<lower` |
| `Check_Momentum` | `iMomentum(P_Momentum,CLOSE)` | `Ind_Momentum_Enabled`, `T_MomentumLevel` | long `>level`, short `<level` |
| `Check_OsMA` | `iOsMA(fast,slow,signal,CLOSE)` | `Ind_OsMA_Enabled` | long `OsMA>0`, short `<0` |
| `Check_HA` | inline Heiken-Ashi | `Bias_HeikenAshi` | long needs bull HA candle, short bear |

Heiken-Ashi is computed with a bounded recursive seed (`shift+200` bars) — no external
indicator. All four are cast in the `CAST_VOTE_STAT` block right after the Stochastic vote, with
matching `passed_/rejected_` stat fields added to the stats struct.

### 2.4 TM early-exit fields (config only, wiring pending — see §4)
`TM_ExitOnOsMAFlip`, `TM_ExitOnMARecross` + `TM_ExitMARole`, `SL_UseSlowMAClamp` + `SL_SlowMARole`.

---

## 3. Per-preset config (`SEA_Presets.mqh` `ApplyPreset` blocks)

All five are flat systems (phase/layer/BarClose off, `Vote_EvalShift=1`, `EXIT_PROFILE_SIMPLE`,
`CloseOnReverse=false`), and restore Policy-A `MaxSpread`/`RiskPercent` like the TREND block.
Values are literals for a guaranteed-compilable first pass; `Inp_RH_*_*` runtime inputs can be
layered on later (see §4).

- **RH_1MS** — `BIAS_2EMA/STRAT_2EMA_POSITION`, EMA 50/100 (roles 0/1); Stoch(5,3,3)
  `STO_CROSS_LEVEL` 20/80; `SL_MODE_SWING` clamped to the 100 EMA (`SL_UseSlowMAClamp`,
  `SL_SlowMARole=1`); `TP_MODE_FIXED_PIPS = 10`. **Faithful.**
- **RH_STS** — EMA3/SMA20 position; MACD(6,17,1) zero; RSI(14)>50; BB(20,3) widening; swing SL;
  R:R 1.5. *Approximation:* a single `MaType` can't mix EMA3 + SMA20, so the first pass uses SMA
  for both slots — flagged inline. A per-slot MA-method field is the clean fix.
- **RH_SS** — EMA3 vs EMA5 (5 on OPEN) position; RSI(3) `RSI_BREAKOUT_OBOS` 80/20;
  Stoch(5,5,5) cross-signal; swing SL; 2R. EMA34/89 are created (roles 2/3) but the 34/89 trend
  filter and the ADX +DI/−DI directional voter are **not yet wired** (documented open items).
- **RH_GS** — 55 SMMA on HIGH (role 0) / 55 SMMA on LOW (role 1); Williams %R(55) −25/−75;
  Stoch(5,5,5); `TM_ExitOnMARecross`; swing SL; 2R. *Approximation:* bias uses SMMA-High vs
  SMMA-Low position; a true price-vs-channel-edge break bias is a refinement.
- **RH_SM** — Heiken-Ashi voter + price vs 14 SMA; OsMA(12,26,9) zero; Momentum(10) 100;
  RSI(5)>50; `TM_ExitOnOsMAFlip`; swing SL; 2R. **Faithful** (bias direction = HA candle + SMA14).

`PresetName()` and `GetPresetContractWording()` updated for all five.

---

## 4. Open items (honest list — carried over from the design docs)

1. **Per-slot MA method** — would let RH_STS use a true EMA3 + SMA20 pair (today: SMA/SMA).
2. **RH_SS 34/89 trend filter + ADX +DI/−DI voter** — needs a directional-DI voter and an
   "MA-A vs MA-B filter" gate; both are new engine pieces.
3. **RH_GS channel-break bias** — price vs the SMMA-High/Low edges (asymmetric), vs the current
   SMMA-vs-SMMA position bias.
4. **TM early-exit wiring** — `TM_ExitOnOsMAFlip`, `TM_ExitOnMARecross`, `SL_UseSlowMAClamp` are
   defined and set by the presets, but `SEA_TradeExecutor.mqh` (`EvaluateTM`/SL path) does not yet
   read them. The SL clamp and OsMA/MA-recross exits therefore need executor hooks to take effect.
5. **Runtime inputs** — presets use literals; add `Inp_RH_<code>_*` blocks to `SEA_Inputs.mqh`
   if you want tester-tunable parameters (the config layer already reads from `cfg`, so this is
   purely additive).
6. **Telemetry naming** — the new voters cast their votes correctly (they affect `all_pass`), but
   are not yet added to the *secondary* per-voter "which voter failed" diagnostic list.

---

## 5. Compile checklist (MetaEditor / Wine)

1. Compile `SimpleEA_v1-05.mq5`. Confirm the five new `EStrategyPreset` values appear in the
   input dropdown.
2. Watch for: `iOsMA` buffer index (buffer 0 = OsMA), `iWPR` sign convention (0..−100), and that
   `MODE_SMMA`/`MODE_LWMA`/`PRICE_OPEN/HIGH/LOW` resolve (they are standard MQL5 constants).
3. Smoke-test each preset on its intended TF (RH_1MS on M1; others per their docs) with
   `DebugFlow=true` and confirm the `[IND_WPR]/[IND_MOM]/[IND_OSMA]/[IND_HA]` log lines fire.
4. Apply the open-item executor hooks (§4.4) when you want the early-exits live.

Patch: `PRESET_RH_5SYSTEMS.patch` (apply with `git apply` from the repo root).
