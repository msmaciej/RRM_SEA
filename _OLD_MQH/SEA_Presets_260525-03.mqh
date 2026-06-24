//+-------------------------------------------------------------------+
//|                                                  SEA_Presets.mqh  |
//|                                   Copyright 2026, SimpleEA System |
//| DESCRIPTION: Preset definitions: overwrite strategy-critical fields|
//|              on top of already hydrated Settings.                 |
//|                                                                   |
//| IMPORTANT:                                                        |
//| - NO input->struct mapping in this file.                          |
//| - NO printing/diagnostic spam in this file.                       |
//| - NO ValidateEffectiveSettings() in this file.                    |
//| - Do NOT touch global-allowed-under-presets fields:               |
//|   PrintEffectiveConfig, DebugFlow, UI toggles, reporting toggles. |
//+-------------------------------------------------------------------+
#property strict

// Preset system version
#define PRESET_SYSTEM_VERSION "4.0.1"  // Major.Minor.Patch

#include <RRMS\SEA_Config.mqh>

// ═══════════════════════════════════════════════════════════════════════
// PRESET_RRM_ORG: EXIT MANAGEMENT CONFIGURATION EXAMPLES
// ═══════════════════════════════════════════════════════════════════════
//
// These examples show complete exit-management configurations.
// Copy and adjust values to match your instrument, timeframe, and risk.
//
// ──────────────────────────────────────────────────────────────────────
// CONFIGURATION A: Classic RRM (Swing SL + BE + PSAR Trail + Fixed TP)
// ──────────────────────────────────────────────────────────────────────
// Use case: conservative swing trading with BE lock and PSAR follow-through.
// Initial SL:   SLMode=SL_MODE_SWING, SwingLookback=34
// Breakeven:    BE_Mode=BE_MODE_TP_PROGRESS_PCT, BE_ProgressPct=33.0
// Trailing:     TrailMode=TRAIL_PSAR, TrailStartsAfterBE=true, TrailLockProfit=true
// Take Profit:  TPMode=TP_MODE_RR, RRRatio=3.0
// Flow:
//   1) Enter with swing-based SL.
//   2) At ~1/3 path to TP, lock BE (entry + buffer).
//   3) Trail using PSAR only in profit zone.
//   4) Exit on TP or trailing protection.
//
// ──────────────────────────────────────────────────────────────────────
// CONFIGURATION B: Let Profit Run (PSAR SL + 1R BE + % Trail + No TP)
// ──────────────────────────────────────────────────────────────────────
// Use case: trend capture with no fixed TP ceiling.
// Initial SL:   SLMode=SL_MODE_PSAR_DOT, PSAR cushion enabled
// Breakeven:    BE_Mode=BE_MODE_R_MULTIPLE, BE_RMultiple=1.0
// Trailing:     TrailMode=TRAIL_PROFIT_PERCENT, TrailProfitPercentLPR=25.0
// Take Profit:  TPMode=TP_MODE_NONE
// Flow:
//   1) Enter with PSAR-based SL.
//   2) At 1R profit, BE locks once.
//   3) Trail continuously at 25% behind peak profit.
//   4) Exit on retracement into trailed SL.
//
// ──────────────────────────────────────────────────────────────────────
// CONFIGURATION C: Aggressive Scalp (Fixed SL + Fast Trail + 1:1 TP)
// ──────────────────────────────────────────────────────────────────────
// Use case: quick momentum scalps with tight risk and fast exits.
// Initial SL:   SLMode=SL_MODE_FIXED_PIPS (tight stop)
// Breakeven:    BE_Mode=BE_MODE_OFF (or early BE if safer profile desired)
// Trailing:     TrailMode=TRAIL_FIXED_PIPS, quick trigger in custom profile
// Take Profit:  TPMode=TP_MODE_RR, RRRatio=1.0
// Flow:
//   1) Enter with small fixed SL.
//   2) Activate trailing quickly once short profit appears.
//   3) Trail toward breakeven/lock.
//   4) Capture 1:1 TP or trail-out.
//
// ──────────────────────────────────────────────────────────────────────
// CONFIGURATION D: Hybrid (Swing SL + Early BE + PSAR Trail + 1:2 TP)
// ──────────────────────────────────────────────────────────────────────
// Use case: balanced profile (early protection + trend participation).
// Initial SL:   SLMode=SL_MODE_SWING, SwingLookback=21
// Breakeven:    BE_Mode=BE_MODE_R_MULTIPLE, BE_RMultiple=0.5
// Trailing:     TrailMode=TRAIL_PSAR, TrailStartsAfterBE=true
// Take Profit:  TPMode=TP_MODE_RR, RRRatio=2.0
// Flow:
//   1) Enter with tighter swing anchor.
//   2) BE locks early at 0.5R.
//   3) PSAR trailing advances only after protection.
//   4) Exit at 1:2 TP or by trailing stop behavior.
//
// Notes:
// - In PRESET_RRM_ORG, TrailTrigger is configured in preset logic (not as input).
// - BE_MODE_TP_PROGRESS_PCT requires TP to be enabled (TPMode != TP_MODE_NONE).

// TF+JPY-aware initial SL cushion mapping (suited for SL_PSAR_DOT / SL_MODE_SWING)
double GetRecommendedInitialSlCushionPips()
{
   if(Settings.Override_SL_Cushion > 0.0)
      return Settings.Override_SL_Cushion;

   ENUM_TIMEFRAMES tf = _Period;
   bool isJPY = (StringFind(_Symbol, "JPY") >= 0);
   double base = 0.0;

   if      (tf <= PERIOD_M1)  base = isJPY ?  1.5 :  1.0;
   else if (tf <= PERIOD_M5)  base = isJPY ?  3.0 :  2.0;
   else if (tf <= PERIOD_M30) base = isJPY ?  5.0 :  3.0;
   else if (tf <= PERIOD_H1)  base = isJPY ?  8.0 :  5.0;
   else if (tf <= PERIOD_H4)  base = isJPY ? 15.0 : 10.0;
   else                       base = isJPY ? 25.0 : 15.0;

   // Scale for non-forex instruments (Gold, indices, crypto have wider pip ranges)
   double mult = GetInstrumentFanMultiplier();
   // Use full multiplier — cushion is measured in the same pip units as the fan threshold.
   // Gold: 2 pips × 20.0 = 40 pips ($0.40) cushion on M5 — meaningful protection.
   // Previous sqrt(20) ≈ 4.5x produced only 8.9 pips ($0.089) — essentially zero.
   return base * mult;
}

//+------------------------------------------------------------------+
//| GetEffectiveRiskPercent: TF-adaptive risk with smart override    |
//+------------------------------------------------------------------+
double GetEffectiveRiskPercent()
{
   if(!Settings.UseAdaptiveRisk)
      return Settings.RiskPercent;

   // Treat the legacy 2.0% default as "auto" while adaptive mode is enabled.
   if(Settings.RiskPercent > 0.0 && MathAbs(Settings.RiskPercent - 2.0) > 1e-8)
      return Settings.RiskPercent;

   ENUM_TIMEFRAMES tf = _Period;
   double adaptive = (tf <= PERIOD_M1) ? Settings.AdaptiveRisk_M1
                     : (tf <= PERIOD_M5) ? Settings.AdaptiveRisk_M5
                                         : Settings.AdaptiveRisk_M15Plus;
   return (adaptive > 0.0) ? adaptive : Settings.RiskPercent;
}

//+------------------------------------------------------------------+
//| GetMarginLevelAdjustment: instrument-aware margin multiplier     |
//+------------------------------------------------------------------+
double GetMarginLevelAdjustment()
{
   if(!Settings.UseMarginAdjustment)
      return 1.0;

   string sym = _Symbol;
   StringToUpper(sym);

   if(StringFind(sym, "JPY") >= 0)
      return (Settings.MarginAdj_JPY > 0.0) ? Settings.MarginAdj_JPY : 1.0;

   if(StringFind(sym, "XAU") >= 0 || StringFind(sym, "XAG") >= 0 || StringFind(sym, "GOLD") >= 0 || StringFind(sym, "SILVER") >= 0)
      return (Settings.MarginAdj_Gold > 0.0) ? Settings.MarginAdj_Gold : 1.0;

   if(StringFind(sym, "BTC") >= 0 || StringFind(sym, "ETH") >= 0)
      return (Settings.MarginAdj_Crypto > 0.0) ? Settings.MarginAdj_Crypto : 1.0;

   if(StringFind(sym, "TRY") >= 0 || StringFind(sym, "ZAR") >= 0 || StringFind(sym, "MXN") >= 0)
      return (Settings.MarginAdj_Exotic > 0.0) ? Settings.MarginAdj_Exotic : 1.0;

   return 1.0;
}

// TF+JPY-aware trailing cushion mapping (smaller, suited for TRAIL_PSAR + PSAR_CUSHION_PIPS)
// Also scales for non-forex instruments via GetInstrumentFanMultiplier()
double GetRecommendedTrailPsarCushionPips()
{
   if(Settings.Override_Trail_Cushion > 0.0)
      return Settings.Override_Trail_Cushion;

   ENUM_TIMEFRAMES tf = _Period;
   bool isJPY = (StringFind(_Symbol, "JPY") >= 0);
   double base = 0.0;

   if      (tf <= PERIOD_M1)  base = isJPY ?  1.0 :  0.5;
   else if (tf <= PERIOD_M5)  base = isJPY ?  2.0 :  1.0;
   else if (tf <= PERIOD_M30) base = isJPY ?  3.0 :  2.0;
   else if (tf <= PERIOD_H1)  base = isJPY ?  7.0 :  5.0;
   else if (tf <= PERIOD_H4)  base = isJPY ? 10.0 :  5.0;
   else                       base = isJPY ? 25.0 : 15.0;

   return base * GetInstrumentFanMultiplier();
}

// TF+JPY-aware breakeven/trail cushion values
double GetTFBasedCushion(ENUM_TIMEFRAMES tf)
{
   if(Settings.Override_BE_Cushion > 0.0)
      return Settings.Override_BE_Cushion;

   if(tf == PERIOD_CURRENT) tf = _Period;
   bool isJPY = (StringFind(_Symbol, "JPY") >= 0);
   double base = 0.0;

   if      (tf <= PERIOD_M1)  base = isJPY ?  2.0 :  1.5;
   else if (tf <= PERIOD_M5)  base = isJPY ?  5.0 :  3.0;
   else if (tf <= PERIOD_M30) base = isJPY ?  8.0 :  5.0;
   else if (tf <= PERIOD_H1)  base = isJPY ? 12.0 :  8.0;
   else if (tf <= PERIOD_H4)  base = isJPY ? 15.0 : 10.0;
   else                       base = isJPY ? 25.0 : 15.0;

   return base * GetInstrumentFanMultiplier();
}

//+------------------------------------------------------------------+
//| GetAutoHTF_TF1: one step higher timeframe                        |
//| GetAutoHTF_TF2: two steps higher timeframe                       |
//|                                                                    |
//| Traded TFs: M1, M5, M15, M30, H1, H2, H4                        |
//| TF1 = next standard TF above chart period                        |
//| TF2 = two standard TFs above chart period                        |
//|                                                                    |
//| User can override by passing a valid TF > chart period.           |
//| If override is <= chart period, auto-compute kicks in.            |
//+------------------------------------------------------------------+
ENUM_TIMEFRAMES GetAutoHTF_TF1(ENUM_TIMEFRAMES chart_tf = PERIOD_CURRENT)
{
   if(chart_tf == PERIOD_CURRENT) chart_tf = _Period;
   switch(chart_tf)
   {
      case PERIOD_M1:  return PERIOD_M5;
      case PERIOD_M5:  return PERIOD_M15;
      case PERIOD_M15: return PERIOD_H1;
      case PERIOD_M30: return PERIOD_H1;
      case PERIOD_H1:  return PERIOD_H4;
      case PERIOD_H2:  return PERIOD_H4;
      case PERIOD_H4:  return PERIOD_D1;
      case PERIOD_D1:  return PERIOD_W1;
      default:         return PERIOD_D1;
   }
}

ENUM_TIMEFRAMES GetAutoHTF_TF2(ENUM_TIMEFRAMES chart_tf = PERIOD_CURRENT)
{
   if(chart_tf == PERIOD_CURRENT) chart_tf = _Period;
   switch(chart_tf)
   {
      case PERIOD_M1:  return PERIOD_M15;
      case PERIOD_M5:  return PERIOD_H1;
      case PERIOD_M15: return PERIOD_H4;
      case PERIOD_M30: return PERIOD_H4;
      case PERIOD_H1:  return PERIOD_D1;
      case PERIOD_H2:  return PERIOD_D1;
      case PERIOD_H4:  return PERIOD_W1;
      case PERIOD_D1:  return PERIOD_MN1;
      default:         return PERIOD_W1;
   }
}

// Safe MTF_TF1 resolver: use user input if valid (> chart TF), otherwise auto-compute
ENUM_TIMEFRAMES GetSafeMTF_TF1(ENUM_TIMEFRAMES user_input)
{
   return (user_input > _Period) ? user_input : GetAutoHTF_TF1();
}

// Safe MTF_TF2 resolver: PERIOD_CURRENT = single-TF mode; otherwise validate
ENUM_TIMEFRAMES GetSafeMTF_TF2(ENUM_TIMEFRAMES user_input)
{
   if(user_input == PERIOD_CURRENT) return PERIOD_CURRENT;  // single-TF mode
   return (user_input > _Period) ? user_input : GetAutoHTF_TF2();
}

//+------------------------------------------------------------------+
//| GetInstrumentFanMultiplier: pip threshold scaling for non-forex    |
//|                                                                    |
//| Scales pip-based thresholds (SL cushion, trail cushion, BE buffer) |
//| for instruments with wider pip ranges than standard Forex.         |
//|                                                                    |
//| NOTE: This multiplier works for CUSHION thresholds (which scale    |
//| with typical bar ranges) but is INSUFFICIENT for EMA fan gap       |
//| thresholds because EMA gaps scale with price level, not just       |
//| volatility. See GetEmaFanMultiplier() for the fan-specific scaler. |
//|                                                                    |
//| Returns: multiplier to apply to FX base pip thresholds.            |
//|   Forex         : 1.0x (base)                                      |
//|   JPY pairs     : 1.5x (wider spreads in pip terms)                |
//|   Gold (XAU)    : 20.0x                                            |
//|   Silver (XAG)  : 10.0x                                            |
//|   Indices       : 15.0x                                            |
//|   Oil           : 8.0x                                             |
//|   Crypto        : 25.0x                                            |
//+------------------------------------------------------------------+
double GetInstrumentFanMultiplier()
{
   string sym = _Symbol;
   double mult = 1.0;
   string inst_class = "Forex";

   // Gold
   if(StringFind(sym, "XAU") >= 0 || StringFind(sym, "GOLD") >= 0)
      { mult = 20.0; inst_class = "Gold"; }
   // Silver
   else if(StringFind(sym, "XAG") >= 0 || StringFind(sym, "SILVER") >= 0)
      { mult = 10.0; inst_class = "Silver"; }
   // Crypto
   else if(StringFind(sym, "BTC") >= 0 || StringFind(sym, "ETH") >= 0 ||
           StringFind(sym, "CRYPTO") >= 0)
      { mult = 25.0; inst_class = "Crypto"; }
   // Indices
   else if(StringFind(sym, "NAS") >= 0 || StringFind(sym, "US30") >= 0 ||
           StringFind(sym, "US500") >= 0 || StringFind(sym, "SPX") >= 0 ||
           StringFind(sym, "SP500") >= 0 || StringFind(sym, "NDX") >= 0 ||
           StringFind(sym, "GER") >= 0 || StringFind(sym, "DAX") >= 0 ||
           StringFind(sym, "UK100") >= 0 || StringFind(sym, "FTSE") >= 0 ||
           StringFind(sym, "JP225") >= 0 || StringFind(sym, "NIKKEI") >= 0 ||
           StringFind(sym, "FRA40") >= 0 || StringFind(sym, "AUS200") >= 0 ||
           StringFind(sym, "STOXX") >= 0 || StringFind(sym, "HSI") >= 0)
      { mult = 15.0; inst_class = "Index"; }
   // Oil
   else if(StringFind(sym, "WTI") >= 0 || StringFind(sym, "BRENT") >= 0 ||
           StringFind(sym, "OIL") >= 0 || StringFind(sym, "CL") >= 0 ||
           StringFind(sym, "USOIL") >= 0 || StringFind(sym, "UKOIL") >= 0)
      { mult = 8.0; inst_class = "Oil"; }
   // JPY pairs
   else if(StringFind(sym, "JPY") >= 0)
      { mult = 1.5; inst_class = "Forex-JPY"; }

   PrintFormat("📐 [INSTRUMENT] %s detected as %s | cushion multiplier: %.1fx",
               sym, inst_class, mult);

   return mult;
}

//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| GetVPRRRecommendedMode — instrument + TF aware VPRR auto-config  |
//|                                                                    |
//| Instrument classes (separate tuning):                             |
//|   Gold (XAU)    — COMEX real vol, strong institutional footprint  |
//|   Silver (XAG)  — thinner, fewer institutions, needs looser ratio |
//|   Indices US    — CME futures, deep liquidity, strict ratio       |
//|   Indices EU    — Eurex/LSE, thinner than US, slightly looser     |
//|   Oil           — NYMEX/ICE futures                               |
//|   Crypto        — exchange vol but retail-dominated, loose        |
//|   Equities      — individual stocks (NVDA etc.), real exchange vol|
//|   FX            — tick vol only, approximation                    |
//|                                                                    |
//| TF multiplier applied to MinRatio automatically:                  |
//|   M5:  ×0.85 (noise), M15: ×1.00 (baseline),                     |
//|   H1:  ×0.95 (fewer bars), H4+: ×0.90 (very few cycles)          |
//| RecoveryBars reduced by 1 on M5 and H4+ when flag is set.        |
//+------------------------------------------------------------------+

// ── TF helpers ─────────────────────────────────────────────────────
double GetVPRR_TFMultiplier(double m_M5, double m_M15, double m_H1, double m_H4Plus)
{
   int tf = PERIOD_CURRENT;
   if(tf <= PERIOD_M5)  return m_M5;
   if(tf <= PERIOD_M15) return m_M15;
   if(tf <= PERIOD_H1)  return m_H1;
   return m_H4Plus;  // H4, H6, H8, H12, D1, W1, MN
}

int GetVPRR_TFRecBars(int base_bars, bool reduce_flag)
{
   if(!reduce_flag) return base_bars;
   int tf = PERIOD_CURRENT;
   if(tf <= PERIOD_M5 || tf >= PERIOD_H4)
      return MathMax(1, base_bars - 1);
   return base_bars;
}

struct ST_VPRRAutoMode
{
   bool   enabled;
   int    volume_type;    // EVPRRVolumeType cast to int
   double min_ratio;
   int    recovery_bars;  // Per-instrument + TF adjusted
};

ST_VPRRAutoMode GetVPRRRecommendedMode(
   // Per-instrument MinRatio (base, before TF adjustment)
   double mr_gold,      double mr_silver,
   double mr_idx_us,    double mr_idx_eu,
   double mr_oil,       double mr_crypto,
   double mr_equities,  double mr_fx,
   double mr_non_fx_tick,
   // Per-instrument RecoveryBars (base, before TF adjustment)
   int    rb_gold,      int    rb_silver,
   int    rb_idx_us,    int    rb_idx_eu,
   int    rb_oil,       int    rb_crypto,
   int    rb_equities,  int    rb_fx,
   // TF multipliers
   double tf_m5,        double tf_m15,
   double tf_h1,        double tf_h4plus,
   bool   tf_reduce_rb,
   // Default RecoveryBars fallback
   int    rb_default
)
{
   ST_VPRRAutoMode result;
   result.enabled       = false;
   result.volume_type   = (int)VPRR_VOL_AUTO;
   result.min_ratio     = 1.0;
   result.recovery_bars = rb_default;

   string sym = _Symbol;

   // ── Volume availability probe ──────────────────────────────────
   long real_vol[];
   bool has_real_vol = (CopyRealVolume(sym, PERIOD_CURRENT, 1, 1, real_vol) == 1 && real_vol[0] > 0);
   long tick_vol[];
   bool has_tick_vol = (CopyTickVolume(sym, PERIOD_CURRENT, 1, 1, tick_vol) == 1 && tick_vol[0] > 0);

   // ── Instrument classification (granular) ───────────────────────
   bool is_gold      = (StringFind(sym, "XAU")  >= 0 || StringFind(sym, "GOLD") >= 0);
   bool is_silver    = (StringFind(sym, "XAG")  >= 0 || StringFind(sym, "SILVER") >= 0);
   bool is_idx_us    = (StringFind(sym, "NAS")  >= 0 || StringFind(sym, "NDX")  >= 0 ||
                        StringFind(sym, "US30") >= 0 || StringFind(sym, "US500")>= 0 ||
                        StringFind(sym, "SPX")  >= 0 || StringFind(sym, "SP500")>= 0 ||
                        StringFind(sym, "DOW")  >= 0);
   bool is_idx_eu    = (StringFind(sym, "GER")  >= 0 || StringFind(sym, "DAX")  >= 0 ||
                        StringFind(sym, "UK100")>= 0 || StringFind(sym, "FTSE") >= 0 ||
                        StringFind(sym, "FRA40")>= 0 || StringFind(sym, "STOXX")>= 0 ||
                        StringFind(sym, "JP225")>= 0 || StringFind(sym, "AUS200")>=0);
   bool is_oil       = (StringFind(sym, "WTI")  >= 0 || StringFind(sym, "BRENT")>= 0 ||
                        StringFind(sym, "OIL")  >= 0 || StringFind(sym, "USOIL")>= 0 ||
                        StringFind(sym, "UKOIL")>= 0);
   bool is_crypto    = (StringFind(sym, "BTC")  >= 0 || StringFind(sym, "ETH")  >= 0 ||
                        StringFind(sym, "CRYPTO")>=0 || StringFind(sym, "LTC")  >= 0 ||
                        StringFind(sym, "XRP")  >= 0);
   // Equities: individual stocks — detected by real exchange vol when no other class matches.
   // Typical broker symbols: NVDA, AAPL, TSLA, MSFT, AMZN, GOOG (no commodity/index keyword)
   bool is_metals    = (is_gold || is_silver);
   bool is_indices   = (is_idx_us || is_idx_eu);
   bool is_non_fx    = (is_metals || is_indices || is_oil || is_crypto);
   // Equity: has real vol but no commodity/index keyword matched → individual stock
   bool is_equity    = (!is_non_fx && has_real_vol);

   // ── TF multiplier ──────────────────────────────────────────────
   double tf_mult = GetVPRR_TFMultiplier(tf_m5, tf_m15, tf_h1, tf_h4plus);

   // ── Assign base values by class, then apply TF adjustment ──────
   if(is_non_fx || is_equity)
   {
      if(has_real_vol)
      {
         result.enabled     = true;
         result.volume_type = (int)VPRR_VOL_REAL;
         double base_mr; int base_rb;

         if(is_gold)        { base_mr = mr_gold;      base_rb = rb_gold;      }
         else if(is_silver) { base_mr = mr_silver;    base_rb = rb_silver;    }
         else if(is_idx_us) { base_mr = mr_idx_us;    base_rb = rb_idx_us;    }
         else if(is_idx_eu) { base_mr = mr_idx_eu;    base_rb = rb_idx_eu;    }
         else if(is_oil)    { base_mr = mr_oil;       base_rb = rb_oil;       }
         else if(is_crypto) { base_mr = mr_crypto;    base_rb = rb_crypto;    }
         else               { base_mr = mr_equities;  base_rb = rb_equities;  }  // equity

         result.min_ratio     = MathMax(0.1, base_mr * tf_mult);
         result.recovery_bars = GetVPRR_TFRecBars(base_rb, tf_reduce_rb);
         PrintFormat("📊 [VPRR AUTO] %s TF:%s: %s real vol → MinRatio=%.2f (base=%.2f × %.2f) RecBars=%d",
                     sym, EnumToString(_Period == PERIOD_CURRENT ? (ENUM_TIMEFRAMES)Period() : _Period),
                     is_gold ? "Gold" : is_silver ? "Silver" :
                     is_idx_us ? "IdxUS" : is_idx_eu ? "IdxEU" :
                     is_oil ? "Oil" : is_crypto ? "Crypto" : "Equity",
                     result.min_ratio, base_mr, tf_mult, result.recovery_bars);
      }
      else if(has_tick_vol)
      {
         result.enabled       = true;
         result.volume_type   = (int)VPRR_VOL_TICK;
         result.min_ratio     = MathMax(0.1, mr_non_fx_tick * tf_mult);
         result.recovery_bars = GetVPRR_TFRecBars(rb_default, tf_reduce_rb);
         PrintFormat("📊 [VPRR AUTO] %s TF:%s: non-FX tick fallback → MinRatio=%.2f RecBars=%d",
                     sym, EnumToString(_Period == PERIOD_CURRENT ? (ENUM_TIMEFRAMES)Period() : _Period), result.min_ratio, result.recovery_bars);
      }
      else
         PrintFormat("📊 [VPRR AUTO] %s: no volume data → DISABLED", sym);
   }
   else
   {
      // FX: tick vol only
      if(has_tick_vol)
      {
         result.enabled       = true;
         result.volume_type   = (int)VPRR_VOL_TICK;
         result.min_ratio     = MathMax(0.1, mr_fx * tf_mult);
         result.recovery_bars = GetVPRR_TFRecBars(rb_fx, tf_reduce_rb);
         PrintFormat("📊 [VPRR AUTO] %s TF:%s: FX tick → MinRatio=%.2f RecBars=%d",
                     sym, EnumToString(_Period == PERIOD_CURRENT ? (ENUM_TIMEFRAMES)Period() : _Period), result.min_ratio, result.recovery_bars);
      }
      else
         PrintFormat("📊 [VPRR AUTO] %s: FX, no tick volume → DISABLED", sym);
   }

   return result;
}

//+------------------------------------------------------------------+
//| GetEmaFanMultiplier
//| GetEmaFanMultiplier: price-level-aware EMA fan gap scaling        |
//|                                                                    |
//| EMA gaps in pips scale with (price_level / pip_size). A 0.3%      |
//| move on Gold ($2400, pip=$0.01) = 7200 pips vs Forex (1.10,       |
//| pip=0.0001) = 33 pips. Static multipliers can't bridge this gap.  |
//|                                                                    |
//| Approach: (symbol_price / symbol_pip) / (forex_ref / forex_pip)   |
//| This auto-adapts to any instrument's price level.                  |
//| Falls back to static multiplier if live price unavailable.         |
//+------------------------------------------------------------------+
double GetEmaFanMultiplier()
{
   string sym = _Symbol;
   double pip = GlobalPipSize(sym);
   double bid = SymbolInfoDouble(sym, SYMBOL_BID);

   // Forex reference: EURUSD-like, price ~1.10, pip = 0.0001
   double fx_ref_ratio = 1.10 / 0.0001;  // = 11000

   if(bid > 0.0 && pip > 0.0)
   {
      double sym_ratio = bid / pip;
      double mult = sym_ratio / fx_ref_ratio;
      // Cap between 0.5x and 10000x
      mult = MathMax(0.5, MathMin(10000.0, mult));

      PrintFormat("📐 [EMA_FAN] %s | bid=%.2f pip=%.5f | dynamic fan multiplier: %.1fx",
                  sym, bid, pip, mult);
      return mult;
   }

   // Fallback: use cushion multiplier (underestimates for metals but better than 1.0)
   double fallback = GetInstrumentFanMultiplier();
   PrintFormat("📐 [EMA_FAN] %s | price unavailable — fallback fan multiplier: %.1fx", sym, fallback);
   return fallback;
}

// TF-based swing lookback for FPM preset — prevents anchor landing on wrong side
// FIX: replaces hardcoded Inp_FPM_SwingLookback=5 which was too short (5 bars on H1 = 5 hours)
int GetFPMSwingLookback()
{
   switch(_Period) {
      case PERIOD_M1:  return 10;
      case PERIOD_M5:  return 12;
      case PERIOD_M15: return 15;
      case PERIOD_M30: return 18;
      case PERIOD_H1:  return 20;
      case PERIOD_H4:  return 30;
      case PERIOD_D1:  return 10;
      default:         return 20;
   }
}

// TF-based TP pips for FPM preset (midpoints of cheat sheet ranges)
double GetFPMFixedTpPips()
{
   ENUM_TIMEFRAMES tf = _Period;
   if      (tf <= PERIOD_M5)  return 11.0;   // M5:  7-15 pips → midpoint 11
   else if (tf <= PERIOD_M15) return 15.0;   // M15: 10-20 pips → midpoint 15
   else if (tf <= PERIOD_M30) return 40.0;   // M30: 30-50 pips → midpoint 40
   else                       return 50.0;   // H1+: cheat sheet specifies 50 pips for higher timeframes
}

string PresetToString(EStrategyPreset p)
{
   switch(p)
   {
      case PRESET_CUSTOM:       return "CUSTOM";
      case PRESET_FPM:          return "FPM";
      case PRESET_MA:           return "MA";
      case PRESET_RRM:          return "RRM";
      case PRESET_RRM_ORG:      return "RRM_ORG";
      case PRESET_TEST:         return "TEST";
      case PRESET_TOPINVESTOR:  return "TOPINVESTOR";
      default:                  return "UNKNOWN";
   }
}

// GetPresetContractWording(): returns a one-line description of what the preset controls
// vs. what the user controls. Used in Cockpit Panel and Status Panel displays.
string GetPresetContractWording(EStrategyPreset preset)
{
   switch(preset)
   {
      case PRESET_CUSTOM:
         return "PRESET_CUSTOM"; //: All inputs respected; you control strategy, indicators, and operator gates.";
      case PRESET_FPM:
         return "PRESET_FPM"; //: Five-Point Method locked (PSAR+MACD+BB_WIDENING+SMA10/20+BarClose); SL mode/TP mode/Trail user-controlled via Zone 3C.";
      case PRESET_MA:
         return "PRESET_MA"; //: benchmark mode: replicates MT5 Moving Average EA; all voting disabled.";
      case PRESET_RRM:
         return "PRESET_RRM"; //: phase-based system fixed (AutoStrat, EMA/MACD config, vote threshold); only Policy A gates and exits user-controlled.";
      case PRESET_RRM_ORG:
         return "PRESET_RRM_ORG"; //: Original Russ Horn RRM with DPI momentum voter locked (TSI R/S/U inline); phase/layer/recovery/PSAR/CandleBody fixed; exits user-controlled.";
      case PRESET_TEST:
         return "PRESET_TEST"; //: Minimal testing mode: bypass voting (threshold=1), fixed SL/TP, no trailing.";
      case PRESET_TOPINVESTOR:
         return "PRESET_TOPINVESTOR"; //: TopInvestor/OXO methodology (EMA50/200 confluence); 3 profiles via Inp_TI_* toggles: Conservative(5), Moderate(8), Full(11 voters).";
      default:
         return "PRESET_ACTIVE"; //: Preset active; strategy-critical settings fixed by preset.";
   }
}

//+------------------------------------------------------------------+
//| GetActiveIndicatorCount(): Wrapper → use GetEnabledIndicatorCount|
//| Kept for backward compatibility; delegates to central function.  |
//+------------------------------------------------------------------+
int GetActiveIndicatorCount(const ST_Settings &cfg)
{
   return GetEnabledIndicatorCount(cfg);
}

//+------------------------------------------------------------------+
//| DetectSymbolType(): Detect symbol category for spread defaults   |
//+------------------------------------------------------------------+
string DetectSymbolType(const string symbol)
{
   string sym = symbol;
   StringToUpper(sym);
   
   // Majors
   if(StringFind(sym, "EURUSD") >= 0) return "MAJOR";
   if(StringFind(sym, "GBPUSD") >= 0) return "MAJOR";
   if(StringFind(sym, "USDJPY") >= 0) return "MAJOR";
   if(StringFind(sym, "USDCHF") >= 0) return "MAJOR";
   if(StringFind(sym, "AUDUSD") >= 0) return "MAJOR";
   if(StringFind(sym, "USDCAD") >= 0) return "MAJOR";
   if(StringFind(sym, "NZDUSD") >= 0) return "MAJOR";
   
   // Gold
   if(StringFind(sym, "XAUUSD") >= 0) return "GOLD";
   if(StringFind(sym, "GOLD")   >= 0) return "GOLD";
   
   // Crypto
   if(StringFind(sym, "BTC") >= 0) return "CRYPTO";
   if(StringFind(sym, "ETH") >= 0) return "CRYPTO";
   
   // Exotics
   if(StringFind(sym, "TRY") >= 0) return "EXOTIC";
   if(StringFind(sym, "ZAR") >= 0) return "EXOTIC";
   if(StringFind(sym, "MXN") >= 0) return "EXOTIC";

   // Default: minor
   return "MINOR";
}

//+------------------------------------------------------------------+
//| PrintPresetConfiguration(): Print active preset config           |
//+------------------------------------------------------------------+
void PrintPresetConfiguration(const ST_Settings &cfg, const string preset_name)
{
   Print("═══════════════════════════════════════════════════════════");
   Print("🎯 PRESET ACTIVE: ", preset_name);
   Print("═══════════════════════════════════════════════════════════");
   Print("");
   Print("📊 BIAS & STRATEGY:");
   Print("  BiasMode:       ", EnumToString(cfg.BiasMode));
   Print("  AutoStrat:      ", EnumToString(cfg.AutoStrat));
   Print("  EMA Periods:    ", cfg.P_Ema1, "/", cfg.P_Ema2, "/", cfg.P_Ema3, "/", cfg.P_Ema4);
   Print("");

   Print("🗳️  VOTING:");
   Print("  Mode:           ", EnumToString(cfg.VoteMode));
   Print("  Active Votes:   ", GetActiveIndicatorCount(cfg), " indicators enabled");
   Print("    ADX:     ", (cfg.Ind_Adx_Enabled ? "✓" : "✗"));
   Print("    ATR:     ", (cfg.Ind_Atr_Enabled ? "✓" : "✗"));
   Print("    BB:      ", (cfg.Ind_Bb_Enabled ? "✓" : "✗"));
   Print("    CandleBody: ", (cfg.Ind_CandleBody_Enabled ? "✓" : "✗"));
   Print("    CI:      ", (cfg.Ind_CI_Enabled ? "✓" : "✗"));
   Print("    VRC:     ", (cfg.Ind_VRC_Enabled ? "✓" : "✗"));
   Print("    CCI:     ", (cfg.Ind_Cci_Enabled ? "✓" : "✗"));
   Print("    MACD:    ", (cfg.Ind_Macd_Enabled ? "✓" : "✗"), (cfg.Ind_Macd_Enabled ? " (" + EnumToString(cfg.MacdVoteMode) + ")" : ""));
   Print("    MFI:     ", (cfg.Ind_Mfi_Enabled ? "✓" : "✗"));
   Print("    P123:    ", (cfg.Ind_P123_Enabled ? "✓" : "✗"));
   Print("    PSAR:    ", (cfg.Ind_Psar_Enabled ? "✓" : "✗"));
   Print("    Ross:    ", (cfg.Ind_Ross_Enabled ? "✓" : "✗"));
   Print("    RSI:     ", (cfg.Ind_Rsi_Enabled ? "✓" : "✗"));
   Print("    Stoch:   ", (cfg.Ind_Sto_Enabled ? "✓" : "✗"));
   Print("    SmaConv: ", (cfg.Ind_SmaConverge_Enabled ? "✓" : "✗"));
   Print("    DPI:     ", (cfg.Ind_Dpi_Enabled ? "✓" : "✗"),
         (cfg.Ind_Dpi_Enabled ? StringFormat(" (v31 MACD Fast=%d Slow=%d RedType=%d CCI=%d Green=%d)",
          cfg.DPI_MACD_Fast, cfg.DPI_MACD_Slow, cfg.DPI_RedSignalType,
          cfg.DPI_UseCCIReset ? cfg.DPI_CCI_Period : 0,
          cfg.DPI_UseGreenHist ? 1 : 0) : ""));
   Print("");

   Print("💰 RISK MANAGEMENT:");
   Print("  RiskPercent:    ", cfg.RiskPercent, "%");
   Print("  MaxOpenTrades:  ", (cfg.MaxOpenTrades > 0 ? IntegerToString(cfg.MaxOpenTrades) : "unlimited"));
   Print("  MaxTotalRisk:   ", (cfg.MaxTotalRisk > 0.0 ? DoubleToString(cfg.MaxTotalRisk, 1) + "%" : "unlimited"));
   Print("");
   Print("🛡️  GATES (Policy A - User Controlled):");
   Print("  MaxSpread:      ", cfg.MaxSpread, " pips");
   Print("  Time Filter:    ", (cfg.UseTime ? ("✓ " + IntegerToString(cfg.StartHr) + "h-" + IntegerToString(cfg.EndHr) + "h") : "✗"));
   Print("  News Filter:    ", (cfg.UseNews ? ("✓ ±" + IntegerToString(cfg.NewsPre) + "/" + IntegerToString(cfg.NewsPost) + "min") : "✗"));
   Print("");

   Print("🎯 EXIT PROFILE:");
   Print("  Profile:        ", EnumToString(cfg.ExitProfile));
   Print("  SL Mode:        ", EnumToString(cfg.SLMode), " (", cfg.SL_FixedPips, " pips)");
   Print("  TP Mode:        ", EnumToString(cfg.TPMode), (cfg.TP_Enabled ? " ✓ ENABLED" : " ✗ DISABLED"));
   Print("  Trail Mode:     ", EnumToString(cfg.TrailMode));
   Print("  BE Mode:        ", EnumToString(cfg.BE_Mode));
   Print("");

   Print("🔧 SYMBOL CONTEXT:");
   Print("  Symbol:         ", _Symbol);
   Print("  Type:           ", DetectSymbolType(_Symbol));
   Print("  Timeframe:      ", EnumToString(Period()));
   Print("");

   // ── VPRR: show effective values (post-TF-multiplied), not raw inputs ──
   Print("📊 VPRR (Volume Pullback-Recovery Ratio):");
   if(cfg.VPRR_Enabled)
   {
      string vol_src = (cfg.VPRR_VolumeType == (int)VPRR_VOL_REAL) ? "REAL (exchange)"
                     : (cfg.VPRR_VolumeType == (int)VPRR_VOL_TICK) ? "TICK (proxy)"
                     : "AUTO";
      Print("  Status:         ✓ ENABLED");
      Print("  Volume source:  ", vol_src);
      PrintFormat("  MinRatio:       %.2f  ← effective value (base × TF multiplier)", cfg.VPRR_MinRatio);
      Print("  RecoveryBars:   ", cfg.VPRR_RecoveryBars, "  ← effective value (TF-adjusted)");
      Print("  MinRecovBars:   ", cfg.VPRR_MinRecoveryBars);
      Print("  Weight:         ", cfg.VPRR_Weight);
      PrintFormat("  ℹ️  To change: adjust base inputs (MinRatio_Gold etc.) and TF multipliers");
      PrintFormat("  ℹ️  TF multipliers: M5=×0.85  M15=×1.00  H1=×0.95  H4+=×0.90 (see VPRR TF group)");
   }
   else
      Print("  Status:         ✗ DISABLED  (AutoEnable=ON: no matching real/tick volume detected)");
   Print("");

   Print("📐 SLOPE CALCULATION:");
   Print("  Lookback:      ", cfg.SlopeLookbackBars, " bar(s)");
   Print("");

   Print("📊 BAR CLOSE (bcX):");
   Print("  Enabled:       ", cfg.BarClose_Enabled ? "✓ YES" : "✗ NO");
   if(cfg.BarClose_Enabled && cfg.BarClose_Mode != BC_DISABLED) {
      Print("  Mode:          ", EnumToString(cfg.BarClose_Mode));
      if(cfg.BarClose_Mode == BC_FIXED_EMA || cfg.BarClose_Mode == BC_LAYER_AWARE)
         Print("  DefaultEMA:    ", EnumToString(cfg.BarClose_DefaultEMA));
   }
   Print("");

   Print("═══════════════════════════════════════════════════════════");
}

//+------------------------------------------------------------------+
//| PrintVPRRSummary(): called right after VPRR is configured in     |
//| each preset. Writes effective settings to Experts log AND sets   |
//| a chart comment so user sees effective values without the log.   |
//+------------------------------------------------------------------+
void PrintVPRRSummary(const ST_Settings &cfg, const string preset_name)
{
   string sym = _Symbol;
   string tf  = EnumToString(_Period == PERIOD_CURRENT ? (ENUM_TIMEFRAMES)Period() : _Period);

   if(!cfg.VPRR_Enabled)
   {
      PrintFormat("📊 VPRR [%s | %s | %s]  DISABLED — no volume data or AutoEnable=OFF",
                  preset_name, sym, tf);
      // Show/destroy VPRR panel (user-controlled via Inp_UI_ShowVPRRPanel)
      string off_lines[];  color off_clrs[];
      ArrayResize(off_lines, 2);  ArrayResize(off_clrs, 2);
      off_lines[0] = StringFormat("VPRR: OFF  [%s]", preset_name);  off_clrs[0] = clrOrangeRed;
      off_lines[1] = "Set AutoEnable=ON or check volume source";    off_clrs[1] = clrGray;
      SEA_UI_StoreVPRRContent(off_lines, off_clrs);
      ChartSetString(0, CHART_COMMENT, ""); // always clear the legacy chart comment
      return;
   }

   string vol_src = (cfg.VPRR_VolumeType == (int)VPRR_VOL_REAL) ? "REAL"
                  : (cfg.VPRR_VolumeType == (int)VPRR_VOL_TICK) ? "TICK" : "AUTO";

   // ── Experts log: full detail ──────────────────────────────────
   Print("═══════════════════════════════════════════════════════════");
   PrintFormat("📊 VPRR ACTIVE  [%s | %s | %s]", preset_name, sym, tf);
   Print("═══════════════════════════════════════════════════════════");
   PrintFormat("  Volume source : %s", vol_src);
   PrintFormat("  MinRatio      : %.2f  ← effective (base × TF multiplier)", cfg.VPRR_MinRatio);
   PrintFormat("  RecoveryBars  : %d    ← effective (TF-adjusted)", cfg.VPRR_RecoveryBars);
   PrintFormat("  MinRecovBars  : %d", cfg.VPRR_MinRecoveryBars);
   PrintFormat("  Weight        : %d", cfg.VPRR_Weight);
   Print("  ─────────────────────────────────────────────────────────");
   Print("  Tune base values in MT5 inputs → VPRR Per-Instrument group.");
   Print("  TF multiplier auto-applies: M5×0.85  M15×1.00  H1×0.95  H4+×0.90");
   Print("  Switch instrument or TF → restart EA → values auto-update.");
   Print("═══════════════════════════════════════════════════════════");

   // ── On-chart VPRR panel (user-controllable position via UI VP inputs) ──
   // Uses OBJ_LABEL objects through the shared panel renderer instead of
   // ChartSetString(CHART_COMMENT), which has no position control and always
   // overwrites the top-left corner, colliding with other panels.
   string vp_lines[];  color vp_clrs[];
   ArrayResize(vp_lines, 7);  ArrayResize(vp_clrs, 7);
   vp_lines[0] = "VPRR ACTIVE";                                              vp_clrs[0] = clrLimeGreen;
   vp_lines[1] = StringFormat("Preset: %s", preset_name);                    vp_clrs[1] = clrWhite;
   vp_lines[2] = StringFormat("Symbol: %s  TF: %s", sym, tf);               vp_clrs[2] = clrWhite;
   vp_lines[3] = StringFormat("Source: %s", vol_src);                        vp_clrs[3] = clrWhite;
   vp_lines[4] = StringFormat("MinRatio: %.2f (eff)", cfg.VPRR_MinRatio);   vp_clrs[4] = clrGold;
   vp_lines[5] = StringFormat("RecBars: %d (eff)", cfg.VPRR_RecoveryBars);  vp_clrs[5] = clrGold;
   vp_lines[6] = "Tune: MT5 inputs > VPRR group";                           vp_clrs[6] = clrGray;
   SEA_UI_StoreVPRRContent(vp_lines, vp_clrs);
   ChartSetString(0, CHART_COMMENT, ""); // always clear the legacy chart comment
}

//+------------------------------------------------------------------+
//| ValidatePresetConfiguration(): Validate preset sanity            |
//| Returns: true if valid, false if critical errors detected        |
//+------------------------------------------------------------------+
bool ValidatePresetConfiguration(const ST_Settings &cfg, const string preset_name)
{
   bool valid = true;
   string errors = "";

   // Check: At least one indicator enabled (EXCEPT for MA Benchmark Mode)
   if(GetActiveIndicatorCount(cfg) == 0 && !cfg.MABenchmarkStrict)
   {
      errors += "  ❌ ERROR: No voting indicators enabled!\n";
      valid = false;
   }

   // Check: EMA periods ascending
   if(cfg.P_Ema1 >= cfg.P_Ema2 || cfg.P_Ema2 >= cfg.P_Ema3 || cfg.P_Ema3 >= cfg.P_Ema4)
   {
      errors += "  ❌ ERROR: EMA periods must be ascending (EMA1 < EMA2 < EMA3 < EMA4)!\n";
      valid = false;
   }

   // Check: Risk percent valid
   // Note: MA Benchmark might use 0.0 to rely on fixed lots, so we allow 0.0 if strict mode is active
   if(cfg.RiskPercent < 0.0 || (cfg.RiskPercent == 0.0 && !cfg.MABenchmarkStrict && cfg.FixedLotSize <= 0.0) || cfg.RiskPercent > 100.0)
   {
      errors += "  ❌ ERROR: RiskPercent must be > 0 and <= 100 (unless using FixedLotSize)!\n";
      valid = false;
   }

   // Check: VOTE_MODE_ALL recommended (Skip warning for MA mode since voting is off)
   if(cfg.VoteMode != VOTE_MODE_ALL && !cfg.MABenchmarkStrict)
   {
      errors += "  ⚠️  WARNING: VoteMode is not VOTE_MODE_ALL (recommended default)\n";
   }

   // Print results
   if(!valid)
   {
      Print("═══════════════════════════════════════════════════════════");
      Print("❌ PRESET VALIDATION FAILED: ", preset_name);
      Print("═══════════════════════════════════════════════════════════");
      Print(errors);
      Print("---");
   }
   else if(errors != "")
   {
      Print("═══════════════════════════════════════════════════════════");
      Print("⚠️  PRESET VALIDATION WARNINGS: ", preset_name);
      Print("═══════════════════════════════════════════════════════════");
      Print(errors);
      Print("---");
   }

   return valid;
}

// ═══════════════════════════════════════════════════════════════════════
// EXIT CONFIGURATION VALIDATION (PRESET_RRM_ORG)
// ═══════════════════════════════════════════════════════════════════════
void ValidateRRM_ORG_ExitConfig(ST_Settings &cfg)
{
   string warnings = "";

   // ── Conflict 1: TP_MODE_NONE with BE_MODE_TP_PROGRESS_PCT ─────────
   if(cfg.TPMode == TP_MODE_NONE && cfg.BE_Mode == BE_MODE_TP_PROGRESS_PCT)
   {
      warnings += "[CONFLICT] BE_MODE_TP_PROGRESS_PCT requires TP target!\n";
      warnings += "  Fix: Change BE_Mode to BE_MODE_R_MULTIPLE or enable TP.\n\n";
   }

   // ── Conflict 2: TrailTrigger vs RRM_TrailStartsAfterBE ────────────
   if(cfg.TrailTrigger == TRIGGER_IMMEDIATE && cfg.RRM_TrailStartsAfterBE == true)
   {
      warnings += "[OVERRIDE] TrailTrigger=IMMEDIATE but RRM_TrailStartsAfterBE=true\n";
      warnings += "  Result: Trailing will WAIT for BE (safety override active).\n\n";
   }

   // ── Conflict 3: PSAR trail with BE disabled ───────────────────────
   if(cfg.TrailMode == TRAIL_PSAR && cfg.BE_Mode == BE_MODE_OFF && cfg.TrailTrigger == TRIGGER_BREAKEVEN)
   {
      warnings += "[DEADLOCK] PSAR trail waits for BE, but BE is disabled!\n";
      warnings += "  Fix: Enable BE or change TrailTrigger to TRIGGER_IMMEDIATE.\n\n";
   }

   // ── Warning 1: Let Profit Run with fixed TP ───────────────────────
   if(cfg.TrailMode == TRAIL_PROFIT_PERCENT && cfg.TPMode != TP_MODE_NONE)
   {
      warnings += "[NOTICE] TRAIL_PROFIT_PERCENT (LPR) works best with TP_MODE_NONE.\n";
      warnings += "  Current: Fixed TP will limit upside, trailing runs underneath.\n";
      warnings += "  Recommended: Set TPMode=TP_MODE_NONE for full LPR.\n\n";
   }

   // ── Warning 2: Aggressive immediate trail without BE ──────────────
   if(cfg.TrailTrigger == TRIGGER_IMMEDIATE && cfg.BE_Mode == BE_MODE_OFF && cfg.RRM_TrailStartsAfterBE == false)
   {
      warnings += "[RISK WARNING] Trailing from entry with NO breakeven protection!\n";
      warnings += "  SL can move into loss zone before profit is secured.\n";
      warnings += "  Recommended: Enable BE or set RRM_TrailStartsAfterBE=true.\n\n";
   }

   // ── Print warnings if any ──────────────────────────────────────────
   if(warnings != "")
   {
      Print("╔══════════════════════════════════════════════════════════╗");
      Print("║  ⚠️  PRESET_RRM_ORG EXIT CONFIGURATION WARNINGS         ║");
      Print("╚══════════════════════════════════════════════════════════╝");
      Print(warnings);
   }
}

void ApplyPreset(const EStrategyPreset preset, ST_Settings &cfg)
{
   if(preset == PRESET_CUSTOM)
      return;
      
   // Do NOT modify cfg.PrintEffectiveConfig / cfg.DebugFlow
   // Do NOT modify UI toggles or reporting toggles (ExportCSV, ExportUseCommonFiles)

   // PSAR cushion seed: set from CUSTOM-specific inputs (not orphan globals).
   // These apply when Inp_Global_Preset = PRESET_CUSTOM and TrailMode = TRAIL_PSAR.
   // All other presets overwrite these in their own block below.
   cfg.PSAR_TrailCushionMode      = Inp_CUSTOM_PSAR_TrailCushionMode;
   cfg.PSAR_TrailCushionAtrPeriod = MathMax(1, Inp_CUSTOM_TrailCushionAtrPeriod);
   cfg.PSAR_TrailCushionAtrMult   = MathMax(0.0, Inp_CUSTOM_TrailCushionAtrMult);
   cfg.PSAR_TrailCushionPct       = MathMax(0.0, Inp_CUSTOM_TrailCushionPct);

   // ================================================================
   // Policy A: Universal Operational Filters (User Always Controls)
   // 
   // These filters apply ON TOP of preset strategy logic:
   //   - MaxSpread:  Cost control / broker protection (slippage, spreads)
   //   - Time:       User availability / preferred trading sessions
   //   - News:       Risk aversion / avoid high-impact news volatility
   //   - Risk:       Personal risk tolerance (RiskPercent, MaxOpenTrades, MaxTotalRisk, margin thresholds)
   //
   // Strategic filters (ATR voting, HTF) are preset-controlled.
   // Users who want full control: Use PRESET_CUSTOM
   // ================================================================
   const double op_MaxSpread     = cfg.MaxSpread;
   const bool   op_UseSpread     = cfg.UseSpread;
   const bool   op_UseTime       = cfg.UseTime;
   const int    op_StartHr       = cfg.StartHr;
   const int    op_EndHr         = cfg.EndHr;
   const bool   op_UseNews       = cfg.UseNews;
   const int    op_NewsPre       = cfg.NewsPre;
   const int    op_NewsPost      = cfg.NewsPost;
   
   const double op_RiskPercent   = cfg.RiskPercent;      // Policy A: user risk tolerance
   const int    op_MaxOpenTrades = cfg.MaxOpenTrades;    // Policy A: user position limit   
   const double op_MaxTotalRisk  = cfg.MaxTotalRisk;     // Policy A: user portfolio risk cap   
   const double op_MinMarginLevel = cfg.MinMarginLevel;  // Policy A: user margin safety thresholds
   
   const double op_EmergencyMarginLevel = cfg.EmergencyMarginLevel;  // Saved for PRESET_TEST exit-profile logic
   const EExitProfile op_ExitProfile = cfg.ExitProfile;

   
#ifdef SEA_PRESET_FPM
   if(preset == PRESET_FPM)
   {
      // ================================================================
      // PRESET_FPM: Five-Point Method (FPM)
      // ================================================================
      //
      // ENTRY FORMULA (3 indicator votes + bar-close gate must all align):
      //   1. PSAR crossed below/above price (dot position + optional flip)
      //   2. MACD crossed above/below signal line (MACD_CROSSOVER_N: fresh cross, ≤5 bars)
      //   3. Bollinger Bands widening (BB_WIDENING mode: bandwidth expanding bar-to-bar)
      //   + Bar-close gate: candle closed above/below 10+20 SMA (BarClose_Mode=BC_BIAS_FAST)
      //      (SmaConverge removed: contradicts trending Bias; BC_BIAS_FAST covers this role)
      //
      // LOCKED (never user-changeable in FPM):
      //   MaType    = SMA               (10 + 20 period SMAs)
      //   P_Ema1    = 10, P_Ema2 = 20   (10 SMA, 20 SMA)
      //   BiasMode  = BIAS_2EMA          (two-SMA structure)
      //   AutoStrat = STRAT_2EMA_POSITION (price position vs both SMAs)
      //   Ind_Psar  ON, Ind_Macd ON, Ind_Bb ON  (3 voting indicators; unanimous via VOTE_MODE_ALL)
      //   BarClose  = BC_BIAS_FAST       (close vs fast SMA=10)
      //   VoteMode  = VOTE_MODE_ALL      (all 3 voting indicators must agree unanimously)
      //   Phase/Layer detection OFF      (simple 2-SMA system)
      //
      // NOTE - Condition 4 (SmaConverge removed):
      //   SmaConverge (gap narrowing) was mutually exclusive with the trending Bias:
      //   when STRAT_2EMA_POSITION Bias fires (both SMAs moving apart), SmaConverge
      //   fails, and vice versa.  The BC_BIAS_FAST bar-close gate already satisfies
      //   "price is positioned relative to the SMAs." Ind_SmaConverge_Enabled = false.
      //
      // NOTE - Condition 3 (BB widening):
      //   BB_WIDENING compares bandwidth (upper - lower) at shift vs shift+1.
      //   Pass when bandwidth_now > bandwidth_prev (bands actively expanding).
      //   Bias-direction is not relevant — widening is symmetric.
      //
      // NOTE - SL/TP user control (Zone 3C):
      //   SL mode: SWING (swing high/low) or FIXED_PIPS — via Inp_FPM_SLMode
      //   TP mode: FIXED_PIPS (TF-based cheat sheet pips) or RR (user ratio) — via Inp_FPM_TPMode
      //
      // FLEXIBLE (via Inp_FPM_* inputs):
      //   SL mode, swing lookback, fixed SL pips, TP mode, R:R ratio,
      //   PSAR step/max, MACD periods, trailing toggle, trail distance
      //
      // ================================================================

      // ── SIGNAL ARCHITECTURE: locked ──────────────────────────────────
      cfg.BiasMode               = BIAS_2EMA;
      cfg.AutoStrat              = STRAT_2EMA_POSITION;    // Price must be above/below both SMA10 and SMA20
      cfg.BiasFastID             = (int)ROLE_EMA1;         // SMA10: fast
      cfg.BiasSlowID             = (int)ROLE_EMA2;         // SMA20: slow
      cfg.MaType                 = METHOD_SMA;             // SMA (not EMA)
      cfg.CloseOnReverse         = false;
      cfg.BiasEnabled            = true;
      cfg.RequirePriceCross      = false;
      cfg.MABenchmarkStrict      = false;
      cfg.UseMACompatSizer       = false;
      cfg.VoteMode               = VOTE_MODE_ALL;

      // ── SMA PERIODS: locked (10 + 20 per cheat sheet) ────────────────
      cfg.P_Ema1                 = 10;    // SMA10
      cfg.P_Ema2                 = 20;    // SMA20
      cfg.P_Ema3                 = 34;    // Unused but must be ascending
      cfg.P_Ema4                 = 89;    // Unused but must be ascending

      // ── INDICATOR TOGGLES: locked ─────────────────────────────────────
      cfg.Ind_Psar_Enabled       = true;   // Condition 1: PSAR position
      cfg.Ind_Macd_Enabled       = true;   // Condition 2: MACD vs signal
      cfg.Ind_Bb_Enabled         = true;   // Condition 3: BB widening
      // All other indicators OFF (not part of FPM methodology):
      cfg.Ind_Adx_Enabled        = false;
      cfg.Ind_Atr_Enabled        = false;
      cfg.Ind_CandleBody_Enabled = false;
      cfg.Ind_CI_Enabled         = false;
      cfg.Ind_VRC_Enabled        = false;
      cfg.Ind_Cci_Enabled        = false;
      cfg.Ind_Mfi_Enabled        = Inp_FPM_Ind_Mfi_Enabled;  // Volume gate: MFI>50 longs, <50 shorts (industry breakout standard)
      cfg.P_Mfi                  = Inp_FPM_Mfi_Period;
      cfg.T_MfiOB                = 80.0;
      cfg.T_MfiOS                = 20.0;
      cfg.MfiMode                = MFI_ZONE_FILTER;          // MFI>50 = bullish volume zone; <50 = bearish
      cfg.Ind_P123_Enabled       = false;
      cfg.Ind_Ross_Enabled       = false;
      cfg.Ind_Rsi_Enabled        = false;
      cfg.Ind_Sto_Enabled        = false;
      cfg.Ind_SmaConverge_Enabled = false;  // Removed: contradicts trending Bias; BC_BIAS_FAST covers Condition 4
      cfg.Ind_SmaConverge_Weight  = 1;
      cfg.Ind_Dpi_Enabled        = false;   // DPI not used in FPM methodology
      cfg.Ind_Dpi_Weight         = 1;
      cfg.Ind_MTF_Enabled        = false;   // MTF not part of FPM methodology

      // ── PSAR SETTINGS ─────────────────────────────────────────────────
      // Condition 1: PSAR crossed below price (for buy) = PSAR dot below price
      cfg.P_PsarStep             = Inp_FPM_PsarStep;
      cfg.P_PsarMax              = Inp_FPM_PsarMax;
      cfg.Vote_AllowPsarFlip     = true;   // Allow flip detection
      cfg.Vote_PsarFlipDelay     = -1;     // -1 = no time expiry: PSAR dot position evaluated on every bar

      // ── MACD SETTINGS ─────────────────────────────────────────────────
      // Condition 2: MACD crossed above signal line = fresh crossover (within N bars)
      cfg.P_MacdFast             = Inp_FPM_MacdFast;
      cfg.P_MacdSlow             = Inp_FPM_MacdSlow;
      cfg.P_MacdSig              = Inp_FPM_MacdSig;
      cfg.MacdVoteMode           = MACD_CROSSOVER_N;  // Fresh cross only (within N bars)
      cfg.MacdRequireSlope       = false;
      cfg.MacdRequireDivergence  = false;
      cfg.MacdRequireHook        = false;
      cfg.MacdHistDecelEnabled   = false;  // Not applicable: FPM uses MACD_CROSSOVER_N (event-based), not directional histogram
      cfg.MacdFreshBars          = 5;                  // Valid for 5 bars after cross (25 min on M5; allows Bias to confirm)
      cfg.MacdSlopeMin           = 0.00001;

      // ── BOLLINGER BANDS SETTINGS ──────────────────────────────────────
      // Condition 3: Bollinger Bands widening (BB_WIDENING)
      //   Compares bandwidth (upper - lower) at shift vs shift+1.
      //   Passes when bandwidth_now > bandwidth_prev (bands actively expanding).
      cfg.P_Bb                   = 20;
      cfg.P_BbDev                = 2.0;
      cfg.BbMode                 = BB_WIDENING;  // Cheat sheet: "Bollinger Bands are widening"

      // ── BAR CLOSE (bcX): Condition 5 ──────────────────────────────────
      // Candle closed above 10 SMA (fast SMA) → above both SMAs in bullish bias
      cfg.BarClose_Enabled       = true;
      cfg.BarClose_Mode          = BC_BIAS_FAST;   // Close vs SMA10 (fast)
      cfg.BarClose_DefaultEMA    = ROLE_EMA1;

      // ── PHASE DETECTION & LAYER FILTERING: disabled ───────────────────
      cfg.PhaseDetectionEnabled     = false;
      cfg.EnableLayerDetection      = false;
      cfg.BlockUnorderedPhase       = false;
      cfg.BlockEmergingPhase        = false;
      cfg.RequireMinPhaseConfirm    = false;
      cfg.MinPhaseConfirmBars       = 0;

      // Layer permissions (all irrelevant when detection is off, set safe defaults)
      cfg.Trending_AllowWeakTrades   = true;
      cfg.Emerging_AllowWeakTrades   = true;
      cfg.Trending_AllowMediumTrades = true;
      cfg.Emerging_AllowMediumTrades = true;
      cfg.Trending_AllowStrongTrades = true;
      cfg.Emerging_AllowStrongTrades = true;

      // ── PULLBACK DETECTION GATES: disabled ────────────────────────────
      cfg.RequireRecoveryMomentum   = false;
      cfg.Gate_Recovery.mode        = GATE_SCALE_FIXED;
      cfg.Gate_Recovery.value       = 0.0;
      cfg.RRM_Lookback              = 0;
      cfg.Gate_EmaDiv.mode          = GATE_SCALE_FIXED;
      cfg.Gate_EmaDiv.value         = 0.0;
      cfg.Gate_CandleDirection.mode  = GATE_SCALE_FIXED;
      cfg.Gate_CandleDirection.value = 0.0;

      // ── VOTE EVALUATION ───────────────────────────────────────────────
      cfg.Vote_EvalShift            = 1;

      // ── OTHER INDICATOR PERIODS (unused but set safe defaults) ─────────
      cfg.P_Adx                     = 14;
      cfg.T_Adx                     = 20.0;
      cfg.ADX_Mode                  = ADX_MODE_STATIC;
      cfg.ADX_Percentile            = 50.0;
      cfg.ADX_Lookback              = 100;
      cfg.ADX_Threshold_Accumulation = 12.0;
      cfg.ADX_Threshold_Trending     = 25.0;
      cfg.ADX_Threshold_Distribution = 18.0;
      cfg.P_Atr                     = 14;    // ATR period default
      cfg.ATR_VoteMinPips           = 5.0;   // ATR voter range default
      cfg.ATR_VoteMaxPips           = 50.0;  // ATR voter range default
      cfg.CandleBody_AvgPeriod      = 10;
      cfg.CandleBody_MaxMult        = 3.0;
      cfg.CandleBody_CheckBars      = 1;
      cfg.CandleBody_RequireDirection = true;
      cfg.Ind_CandleBody_Weight     = 1;
      cfg.CI_Period                 = 14;
      cfg.CI_RangingThreshold       = 61.8;
      cfg.Ind_CI_Weight             = 1;
      cfg.VRC_ATR_Period            = 14;    // VRC default
      cfg.VRC_Lookback              = 100;   // VRC default
      cfg.VRC_LowThreshold          = 33.0;  // VRC default
      cfg.Ind_VRC_Weight            = 1;     // VRC default
      cfg.P_Cci                     = 14;
      cfg.CciMode                   = CCI_TREND_ZERO;
      // P_Mfi / T_MfiOB / T_MfiOS / MfiMode — set above from Inp_FPM_Ind_Mfi_Enabled / Inp_FPM_Mfi_Period
      cfg.P_Rsi                     = 14;
      cfg.T_RsiOB                   = 70.0;
      cfg.T_RsiOS                   = 30.0;
      cfg.RsiMode                   = RSI_TREND_ABOVE_50;
      cfg.P_StoK                    = 5;
      cfg.P_StoD                    = 3;
      cfg.P_StoSlow                 = 3;
      cfg.T_StoOB                   = 80.0;
      cfg.T_StoOS                   = 20.0;
      cfg.StoMode                   = STO_CROSS_SIGNAL;
      cfg.FractalPeriod             = 5;
      cfg.TPFractalOffset           = 1;

      // ── RISK MANAGEMENT ───────────────────────────────────────────────
      cfg.CountBEasZeroRisk         = true;
      cfg.FixedLotSize              = 0.0;

      // ── EXIT STRATEGY ─────────────────────────────────────────────────
      cfg.ExitProfile               = EXIT_PROFILE_SIMPLE;

      // SL: Hardcode SL_MODE_SWING — swing is the FPM methodology; Inp_FPM_SLMode is kept for PRESET_CUSTOM only
      // FIX: was cfg.SLMode = Inp_FPM_SLMode — user could accidentally switch to non-swing mode
      cfg.SLMode                    = SL_MODE_SWING;
      // FIX: was Inp_FPM_SwingLookback (default 5) — too short; use TF-aware helper instead
      cfg.SwingLookback             = GetFPMSwingLookback();
      cfg.SL_SwingPipsCushion       = GetRecommendedInitialSlCushionPips();
      cfg.SL_PsarPipsCushion        = GetRecommendedInitialSlCushionPips();
      cfg.SL_MinPips                = GetRecommendedInitialSlCushionPips();  // Instrument-aware minimum SL floor: prevents tiny-SL fallback from computing oversized lots
      cfg.SL_WidenToMinimum         = true;  // Widen rather than block when SL too close — ensures trade always gets a sane SL
      cfg.SL_FixedPips              = Inp_FPM_SLFixedPips;

      // TP: User-selected mode
      //   TP_MODE_FIXED_PIPS → TF-based cheat sheet midpoints via GetFPMFixedTpPips()
      //   TP_MODE_RR         → user R:R ratio (Inp_FPM_RRRatio, any double e.g. 1.5, 2.0, 3.0)
      cfg.TPMode                    = Inp_FPM_TPMode;
      cfg.TP_Enabled                = true;
      cfg.FixedTPPips               = (Inp_FPM_TPMode == TP_MODE_FIXED_PIPS) ? GetFPMFixedTpPips() : 0.0;
      // FIX: was 0.0 when TP_MODE_FIXED_PIPS — ExecuteTrade TP chain skipped all branches → tp=0
      // Always set a non-zero RRRatio so the RRRatio>0 branch in ExecuteTrade fires as fallback
      cfg.RRRatio                   = (Inp_FPM_TPMode == TP_MODE_RR)         ? Inp_FPM_RRRatio      : 2.0;
      cfg.SLPercent                 = 0.0;

      // BE: Move to breakeven after 10 pips profit
      cfg.BE_Mode                   = BE_MODE_R_MULTIPLE;
      cfg.RRM_BE_RMultiple          = 1.0;                         // BE at 1R profit (triggers when profit ≥ 1× initial SL distance)
      cfg.RRM_BE_BufferPips         = GetTFBasedCushion(_Period);  // TF-adaptive buffer (e.g., M5=3p, M15=5p, H1=8p)
      cfg.BEThresholdPips           = 0.0;                         // Not used in R_MULTIPLE mode
      cfg.TrailTrigger              = TRIGGER_BREAKEVEN;

      // Trail: Optional 15-pip trailing stop (cheat sheet: "15 points or minimum broker-allowed distance")
      // If 15 pips is below the broker's minimum trail distance, the platform will
      // clamp it to the minimum. Set Inp_FPM_UseTrailing=false to disable entirely.
      cfg.TrailMode                 = Inp_FPM_UseTrailing ? TRAIL_FIXED_PIPS : TRAIL_NONE;
      cfg.TrailDistancePips         = Inp_FPM_TrailDistancePips;
      cfg.TrailLockProfit           = true;
      cfg.TrailStepPips             = 5.0;
      cfg.TrailProfitPercent        = 0.0;

      cfg.PSAR_TrailCushionMode     = PSAR_CUSHION_PIPS;
      cfg.PSAR_TrailPipsCushion     = 0.0;

      // ── SLOPE CALCULATION ─────────────────────────────────────────────
      cfg.SlopeLookbackBars         = 3;  // Smoother slope on M5; SMA20 needs multiple bars to show direction

      // ── MA BENCHMARK SPECIFIC: off ────────────────────────────────────
      cfg.ma_h_shift                = 1;
      cfg.ma_v_shift                = 1;

      // ── DRAWDOWN PROTECTION: off (not part of FPM methodology) ────────
      cfg.RRM_EnableDrawdownProtection = false;
      cfg.RRM_MaxConsecutiveLosses  = 0;
      cfg.RRM_MaxTradesPerDay       = 0;
      cfg.RRM_MaxDailyDrawdownPct   = 0.0;

      // ── POLICY A: RESTORE OPERATOR-CONTROLLED GATES ───────────────────
      cfg.UseSpread                 = op_UseSpread;
      cfg.MaxSpread                 = op_MaxSpread;
      cfg.UseTime                   = op_UseTime;
      cfg.StartHr                   = op_StartHr;
      cfg.EndHr                     = op_EndHr;
      cfg.UseNews                   = op_UseNews;
      cfg.NewsPre                   = op_NewsPre;
      cfg.NewsPost                  = op_NewsPost;
      cfg.RiskPercent               = op_RiskPercent;
      cfg.MaxOpenTrades             = op_MaxOpenTrades;
      cfg.MaxTotalRisk              = op_MaxTotalRisk;
      cfg.MinMarginLevel            = op_MinMarginLevel;
      cfg.EmergencyMarginLevel      = op_EmergencyMarginLevel;

      return;
   }
   
   
#endif // SEA_PRESET_FPM

   if(preset == PRESET_MA)
#ifdef SEA_PRESET_MA
   {
      // ================================================================
      // PRESET_MA: MT5 Moving Average Benchmark
      // Replicates MT5 built-in "Moving Average" Expert Advisor behavior
      // - Simple price/MA crossover (no bias, no phase detection)
      // - All indicator voting disabled
      // - Stop-and-reverse on every cross
      // - MA-compatible lot sizing (MaximumRisk + DecreaseFactor)
      // - No broker-side SL/TP (EA manages exits internally)
      // ================================================================
   
      // ================================================================
      // CORE STRATEGY SETTINGS
      // ================================================================
      cfg.CloseOnReverse         = true;
      cfg.BiasEnabled            = true;
      cfg.BiasMode               = BIAS_2EMA;
      cfg.AutoStrat              = STRAT_2EMA_CROSS_PRICE;
      cfg.BiasFastID             = (int)ROLE_EMA1;
      cfg.BiasSlowID             = (int)ROLE_EMA1;
      cfg.MaType                 = METHOD_SMA;
      cfg.RequirePriceCross      = true;
      cfg.MABenchmarkStrict      = true;
      cfg.UseMACompatSizer       = true;
   
      // ================================================================
      // INDICATOR VOTING CONFIGURATION (Alphabetical)
      // ================================================================
      cfg.Ind_Adx_Enabled        = false;
      cfg.Ind_Atr_Enabled        = false;
      cfg.Ind_Bb_Enabled         = false;
      cfg.Ind_CandleBody_Enabled = false;
      cfg.Ind_CI_Enabled         = false;
      cfg.Ind_VRC_Enabled        = false;
      cfg.Ind_Cci_Enabled        = false;
      cfg.Ind_Macd_Enabled       = false;
      cfg.Ind_Mfi_Enabled        = false;
      cfg.Ind_P123_Enabled       = false;
      cfg.Ind_Psar_Enabled       = false;
      cfg.Ind_Ross_Enabled       = false;
      cfg.Ind_Rsi_Enabled        = false;
      cfg.Ind_Sto_Enabled        = false;
      cfg.Ind_SmaConverge_Enabled = false;
      cfg.Ind_SmaConverge_Weight  = 1;
      cfg.Ind_Dpi_Enabled        = false;
      cfg.Ind_Dpi_Weight         = 1;
      cfg.Ind_MTF_Enabled        = false;   // MTF disabled: benchmark mode has all voting off
      cfg.VoteMode               = VOTE_MODE_ALL;
      
      // ================================================================
      // INDICATOR PERIODS & THRESHOLDS (Alphabetical)
      // ================================================================
      
      // ADX (Average Directional Index)
      cfg.P_Adx                  = 14;
      cfg.T_Adx                  = 20.0;
      cfg.ADX_Mode               = ADX_MODE_STATIC;
      cfg.ADX_Percentile         = 50.0;
      cfg.ADX_Lookback           = 100;
      cfg.ADX_Threshold_Accumulation = 12.0;
      cfg.ADX_Threshold_Trending     = 25.0;
      cfg.ADX_Threshold_Distribution = 18.0;
      
      // ATR (Average True Range) - Voting Indicator Only
      cfg.P_Atr                  = 14;
      cfg.ATR_VoteMinPips        = 5.0;
      cfg.ATR_VoteMaxPips        = 50.0;
      
      // Bollinger Bands
      cfg.P_Bb                   = 20;
      cfg.P_BbDev                = 2.0;
      cfg.BbMode                 = BB_TREND_FOLLOW;
   
      // Candle Body
      cfg.CandleBody_AvgPeriod   = 10;
      cfg.CandleBody_MaxMult     = 3.0;
      cfg.CandleBody_CheckBars   = 1;
      cfg.CandleBody_RequireDirection = true;
      cfg.Ind_CandleBody_Weight  = 1;

      // Choppiness Index
      cfg.CI_Period              = 14;
      cfg.CI_RangingThreshold    = 61.8;
      cfg.Ind_CI_Weight          = 1;
      
      // VRC (Volatility Regime Classifier)
      cfg.VRC_ATR_Period         = 14;
      cfg.VRC_Lookback           = 100;
      cfg.VRC_LowThreshold       = 33.0;
      cfg.Ind_VRC_Weight         = 1;

      // CCI (Commodity Channel Index)
      cfg.P_Cci                  = 14;
      cfg.CciMode                = CCI_TREND_ZERO;

      // EMA (Periods)
      cfg.P_Ema1                 = Inp_MA_Period; // Primary MA (user-controlled via input)
      cfg.P_Ema2                 = 13;
      cfg.P_Ema3                 = 34;
      cfg.P_Ema4                 = 89;
      
      // MACD (Moving Average Convergence Divergence)
      cfg.P_MacdFast             = 12;
      cfg.P_MacdSlow             = 26;
      cfg.P_MacdSig              = 9;
      cfg.MacdVoteMode           = MACD_HISTOGRAM;
      cfg.MacdRequireSlope       = false;
      cfg.MacdRequireDivergence  = false;
      cfg.MacdRequireHook        = false;
      cfg.MacdHistDecelEnabled   = false;  // TEST preset: decel filter off — isolation mode for indicator debugging
      cfg.MacdFreshBars          = 3;
      cfg.MacdSlopeMin           = 0.00001;
      
      // MFI (Money Flow Index)
      cfg.P_Mfi                  = 14;
      cfg.T_MfiOB                = 80.0;
      cfg.T_MfiOS                = 20.0;
      cfg.MfiMode                = MFI_ZONE_FILTER;
   
      // PSAR (Parabolic SAR)
      cfg.P_PsarStep             = 0.02;
      cfg.P_PsarMax              = 0.2;
      cfg.Vote_AllowPsarFlip     = false;
      cfg.Vote_PsarFlipDelay     = 0;
      
      // RSI (Relative Strength Index)
      cfg.P_Rsi                  = 14;
      cfg.T_RsiOB                = 70.0;
      cfg.T_RsiOS                = 30.0;
      cfg.RsiMode                = RSI_TREND_ABOVE_50;
   
      // Stochastic Oscillator
      cfg.P_StoK                 = 5;
      cfg.P_StoD                 = 3;
      cfg.P_StoSlow              = 3;
      cfg.T_StoOB                = 80.0;
      cfg.T_StoOS                = 20.0;
      cfg.StoMode                = STO_CROSS_SIGNAL;
   
      // ================================================================
      // PHASE DETECTION & LAYER FILTERING
      // ================================================================
      cfg.PhaseDetectionEnabled     = false;
      cfg.EnableLayerDetection      = false;
      cfg.BlockUnorderedPhase       = false;
      cfg.BlockEmergingPhase        = false;
      cfg.RequireMinPhaseConfirm    = false;
      cfg.MinPhaseConfirmBars       = 0;
      
      // Layer permissions per phase
      cfg.Trending_AllowWeakTrades   = false;
      cfg.Emerging_AllowWeakTrades   = false;
      cfg.Trending_AllowMediumTrades = false;
      cfg.Emerging_AllowMediumTrades = false;
      cfg.Trending_AllowStrongTrades = false;
      cfg.Emerging_AllowStrongTrades = false;
      
      // ================================================================
      // PULLBACK DETECTION GATES
      // ================================================================
      cfg.RequireRecoveryMomentum   = false;
      
      // Gate 2: Recovery momentum
      cfg.Gate_Recovery.mode        = GATE_SCALE_FIXED;
      cfg.Gate_Recovery.value       = 0.0;
      cfg.RRM_Lookback              = 0;
      
      // Gate 3: EMA divergence
      cfg.Gate_EmaDiv.mode          = GATE_SCALE_FIXED;
      cfg.Gate_EmaDiv.value         = 0.0;
      
      // Gate 4: Candle direction
      cfg.Gate_CandleDirection.mode  = GATE_SCALE_FIXED;
      cfg.Gate_CandleDirection.value = 0.0;
      
      // ================================================================
      // VOTE EVALUATION SETTINGS
      // ================================================================
      cfg.Vote_EvalShift            = 1;
      
      // ================================================================
      // RISK MANAGEMENT (Portfolio-level)
      // ================================================================
      cfg.RiskPercent               = 0.0; // Uses MA-compatible sizer instead
      cfg.FixedLotSize              = 0.0;
      cfg.MaxTotalRisk              = 100.0;
      cfg.MaxOpenTrades             = 1;
      cfg.CountBEasZeroRisk         = false;
      
      // ================================================================
      // EXIT STRATEGY CONFIGURATION
      // ================================================================
      cfg.ExitProfile               = EXIT_PROFILE_NONE;
      cfg.TP_Enabled                = false;
      cfg.TrailMode                 = TRAIL_NONE;
      cfg.PSAR_TrailCushionMode     = PSAR_CUSHION_PIPS;
      cfg.PSAR_TrailPipsCushion     = 0.0;
      cfg.BE_Mode                   = BE_MODE_OFF;
      
      // ================================================================
      // SL/TP STRATEGY MODES
      // ================================================================
      cfg.SLMode                    = SL_MODE_FIXED_PIPS;
      cfg.TPMode                    = TP_MODE_NONE;
      cfg.FixedTPPips               = 0.0;
      cfg.SLPercent                 = 0.0;
      cfg.RRRatio                   = 0.0;
      cfg.SwingLookback             = 0;
      
      // ================================================================
      // FRACTAL/PSAR SL/TP DEFAULTS
      // ================================================================
      cfg.FractalPeriod             = 5;
      cfg.TPFractalOffset           = 1;

      // ================================================================
      // ADVANCED TRAILING TRIGGER DEFAULTS
      // ================================================================
      cfg.TrailTrigger              = TRIGGER_IMMEDIATE;
      cfg.TrailDistancePips         = 0.0;
      cfg.BEThresholdPips           = 0.0;
      cfg.TrailProfitPercent        = 0.0;
      cfg.TrailStepPips             = 0.0;
      cfg.TrailLockProfit           = false;
      
      // ================================================================
      // MA-SPECIFIC SETTINGS
      // ================================================================
      cfg.ma_h_shift                = Inp_MA_Shift;
      cfg.ma_v_shift                = 1;
   
      // ================================================================
      // MA DRAWDOWN PROTECTION (All off for benchmark mode)
      // ================================================================
      cfg.RRM_EnableDrawdownProtection = false;
      cfg.RRM_MaxConsecutiveLosses  = 0;
      cfg.RRM_MaxTradesPerDay       = 0;
      cfg.RRM_MaxDailyDrawdownPct   = 0.0;

      // ================================================================
      // SLOPE CALCULATION SETTINGS (Benchmark Mode - No Filtering)
      // ================================================================
      cfg.SlopeLookbackBars         = 1; // MT5 standard (single bar)

      // ════════════════════════════════════════════════════════════════
      // BAR CLOSE (bcX) CONFIGURATION - Disabled for MA benchmark mode
      // ════════════════════════════════════════════════════════════════
      cfg.BarClose_Enabled          = false;        // Disabled: bcX not used in MA benchmark
      cfg.BarClose_Mode             = BC_DISABLED;
      cfg.BarClose_DefaultEMA       = ROLE_EMA1;

      // ════════════════════════════════════════════════════════════════
      // BAR CLOSE (bcX) CONFIGURATION - Disabled for MA benchmark mode
      // ════════════════════════════════════════════════════════════════
      cfg.BarClose_Enabled    = false;        // Disabled: bcX not used in MA benchmark
      cfg.BarClose_Mode       = BC_DISABLED;
      cfg.BarClose_DefaultEMA = ROLE_EMA1;

      // ================================================================
      // POLICY A: RESTORE OPERATOR-CONTROLLED GATES
      // ================================================================
      cfg.MaxSpread     = op_MaxSpread;
      cfg.UseSpread     = op_UseSpread;
      cfg.UseTime       = op_UseTime;
      cfg.StartHr       = op_StartHr;
      cfg.EndHr         = op_EndHr;
      cfg.UseNews       = op_UseNews;
      cfg.NewsPre       = op_NewsPre;
      cfg.NewsPost      = op_NewsPost;
      cfg.RiskPercent   = op_RiskPercent; // Policy A: restore user risk tolerance
      cfg.MaxOpenTrades = op_MaxOpenTrades; // Policy A: restore user position limit
      cfg.MaxTotalRisk  = op_MaxTotalRisk; // Policy A: restore user portfolio risk cap
      cfg.MinMarginLevel = op_MinMarginLevel; // Policy A: restore entry margin guard
      cfg.EmergencyMarginLevel = op_EmergencyMarginLevel; // Policy A: restore emergency margin guard

      return;
   }

   if(preset == PRESET_RRM)
#endif // SEA_PRESET_MA

   {
#ifdef SEA_PRESET_RRM_FAMILY
      // ================================================================
      // PRESET_RRM: RRM Methodology — Phase-Based Trend Pullback
      // ================================================================
      //
      // SIGNAL FORMULA (locked, no branches):
      //   TS = Phase(4EMA) × Layer(EMA-pair) × BarClose × Indicators × Gates
      //
      // LOCKED (never user-changeable):
      //   BiasMode    = BIAS_4EMA          (4-EMA phase: TRENDING/EMERGING/UNORDERED)
      //   AutoStrat   = STRAT_4EMA_LAYER   (layer-based pullback entry)
      //   VoteMode    = VOTE_MODE_ALL       (all enabled indicators must agree)
      //   Phase/Layer detection ON, UNORDERED blocked
      //
      // FLEXIBLE (via dedicated Inp_RRM_* inputs):
      //   EMA periods, indicator toggles, indicator parameters, SL/TP/Trail modes
      //
      // ================================================================

      // ── SIGNAL ARCHITECTURE: locked ──────────────────────────────────
      cfg.BiasMode               = BIAS_4EMA;
      cfg.AutoStrat              = STRAT_4EMA_LAYER;
      cfg.BiasFastID             = (int)ROLE_EMA3;    // EMA34: phase direction fast
      cfg.BiasSlowID             = (int)ROLE_EMA4;    // EMA89: phase direction slow
      cfg.MaType                 = METHOD_EMA;
      cfg.CloseOnReverse         = false;
      cfg.BiasEnabled            = true;              // true
      cfg.RequirePriceCross      = false;
      cfg.MABenchmarkStrict      = false;
      cfg.UseMACompatSizer       = false;
      cfg.VoteMode               = VOTE_MODE_ALL;

      // ── EMA PERIODS: flexible via Inp_RRM_* ──────────────────────────
      cfg.P_Ema1                 = Inp_RRM_Ema1Period;   // default 5
      cfg.P_Ema2                 = Inp_RRM_Ema2Period;   // default 13
      cfg.P_Ema3                 = Inp_RRM_Ema3Period;   // default 34
      cfg.P_Ema4                 = Inp_RRM_Ema4Period;   // default 89

      // ── SPREAD: derived from pair type (Zone 3C), no mode branching ──
      cfg.MaxSpread = op_MaxSpread;  // Policy A: user spread gate

      // ── INDICATOR TOGGLES: flexible via Inp_RRM_* ────────────────────
      cfg.Ind_Macd_Enabled       = Inp_RRM_Use_Macd;
      cfg.Ind_Psar_Enabled       = Inp_RRM_Use_Psar;
      cfg.Ind_CandleBody_Enabled = Inp_RRM_Use_CandleBody;
      cfg.Ind_Cci_Enabled        = Inp_RRM_Use_Cci;
      cfg.Ind_Rsi_Enabled        = Inp_RRM_Use_Rsi;
      cfg.Ind_Adx_Enabled        = Inp_RRM_Use_Adx;
      cfg.Ind_Sto_Enabled        = Inp_RRM_Use_Stoch;
      cfg.Ind_Bb_Enabled         = Inp_RRM_Use_Bb;
      cfg.Ind_Mfi_Enabled        = Inp_RRM_Use_Mfi;
      // Always off in RRM (not part of RRM methodology):
      cfg.Ind_Atr_Enabled        = false;
      cfg.Ind_CI_Enabled         = Inp_RRM_Use_CI; // Intentional: PRESET_RRM now exposes the CI toggle in its own preset block.
      cfg.CI_Period              = Inp_RRM_CiPeriod;            // CI now configurable in RRM (was ignoring this input)
      cfg.CI_RangingThreshold    = Inp_RRM_CiRangingThreshold;  // CI now configurable in RRM (was ignoring this input)
      cfg.Ind_VRC_Enabled        = false;
      cfg.Ind_P123_Enabled       = false;
      cfg.Ind_Ross_Enabled       = false;
      cfg.Ind_SmaConverge_Enabled = false;
      cfg.Ind_SmaConverge_Weight  = 1;
      cfg.Ind_Dpi_Enabled        = false;
      cfg.Ind_Dpi_Weight         = 1;
      cfg.Ind_MTF_Enabled        = Inp_Ind_MTF_Enabled;
      cfg.Ind_MTF_Weight         = Inp_Ind_MTF_Weight;
      cfg.MTF_TF1                = GetSafeMTF_TF1(Inp_MTF_TF1);
      cfg.MTF_TF2                = GetSafeMTF_TF2(Inp_MTF_TF2);
      cfg.MTF_EMA_Fast           = Inp_MTF_EMA_Fast;
      cfg.MTF_EMA_Slow           = Inp_MTF_EMA_Slow;
      cfg.MTF_RequirePhase       = false;   // Position-only; slope kills signals due to HTF lag
      cfg.MTF_StrictAlignment    = Inp_MTF_StrictAlignment;   // HTF directional gate: both HTFs must agree (strict). User-controlled.

      // ── MACD SETTINGS: flexible via Inp_RRM_* ────────────────────────
      cfg.P_MacdFast             = Inp_RRM_MacdFast;
      cfg.P_MacdSlow             = Inp_RRM_MacdSlow;
      cfg.P_MacdSig              = Inp_RRM_MacdSig;
      cfg.MacdVoteMode           = Inp_RRM_MacdMode;
      cfg.MacdRequireSlope       = Inp_RRM_MacdSlope;
      cfg.MacdRequireDivergence  = Inp_RRM_MacdDiv;
      cfg.MacdRequireHook        = false;
      cfg.MacdHistDecelEnabled   = Inp_RRM_MacdHistDecel;  // Decel pre-filter: block when histogram shrinking (analogous to DPI_BlockOnDeceleration)
      cfg.MacdFreshBars          = Inp_RRM_MacdFreshBars;
      cfg.MacdSlopeMin           = Inp_RRM_MacdSlopeMin;

      // ── PSAR SETTINGS: flexible via Inp_RRM_* ────────────────────────
      cfg.P_PsarStep             = Inp_RRM_PsarStep;
      cfg.P_PsarMax              = Inp_RRM_PsarMax;
      cfg.Vote_AllowPsarFlip     = true;              // true
      cfg.Vote_PsarFlipDelay     = -1;

      // ── CCI SETTINGS: flexible via Inp_RRM_* ─────────────────────────
      cfg.P_Cci                  = Inp_RRM_CciPeriod;
      cfg.CciMode                = Inp_RRM_CciMode;

      // ── RSI SETTINGS: flexible via Inp_RRM_* ─────────────────────────
      cfg.P_Rsi                  = Inp_RRM_RsiPeriod;
      cfg.RsiMode                = Inp_RRM_RsiMode;
      cfg.T_RsiOB                = Inp_RRM_Rsi_OB;
      cfg.T_RsiOS                = Inp_RRM_Rsi_OS;

      // ── ADX SETTINGS: flexible via Inp_RRM_* ─────────────────────────
      cfg.ADX_Mode               = Inp_RRM_Adx_Mode;
      cfg.P_Adx                  = Inp_RRM_AdxPeriod;
      cfg.T_Adx                  = Inp_RRM_AdxThreshold;
      cfg.ADX_Percentile         = Inp_RRM_Adx_Percentile;
      cfg.ADX_Lookback           = Inp_RRM_Adx_Lookback;
      cfg.ADX_Threshold_Accumulation  = Inp_RRM_Adx_Thr_Accum;
      cfg.ADX_Threshold_Trending      = Inp_RRM_Adx_Thr_Trending;
      cfg.ADX_Threshold_Distribution  = Inp_RRM_Adx_Thr_Distrib;

      // ── STOCH SETTINGS: fixed reasonable defaults ─────────────────────
      cfg.StoMode                = Inp_RRM_Sto_Mode;
      cfg.P_StoK                 = Inp_RRM_Sto_K;
      cfg.P_StoD                 = Inp_RRM_Sto_D;
      cfg.P_StoSlow              = Inp_RRM_Sto_Slow;
      cfg.T_StoOB                = Inp_RRM_Sto_OB;
      cfg.T_StoOS                = Inp_RRM_Sto_OS;

      // ── BB SETTINGS: fixed reasonable defaults ────────────────────────
      cfg.BbMode                 = Inp_RRM_Bb_Mode;
      cfg.P_Bb                   = Inp_RRM_Bb_Period;
      cfg.P_BbDev                = Inp_RRM_Bb_Deviation;

      // ── MFI SETTINGS: fixed reasonable defaults ───────────────────────
      cfg.MfiMode                = Inp_RRM_Mfi_Mode;
      cfg.P_Mfi                  = Inp_RRM_Mfi_Period;
      cfg.T_MfiOB                = Inp_RRM_Mfi_OB;
      cfg.T_MfiOS                = Inp_RRM_Mfi_OS;

      // ── CANDLE BODY SETTINGS ──────────────────────────────────────────
      cfg.CandleBody_AvgPeriod   = Inp_RRM_CandleBody_AvgPeriod;
      cfg.CandleBody_MaxMult     = Inp_RRM_CandleBody_MaxMult;
      cfg.CandleBody_CheckBars   = Inp_RRM_CandleBody_CheckBars;
      cfg.CandleBody_RequireDirection = Inp_RRM_CandleBody_RequireDir;
      cfg.Ind_CandleBody_Weight  = 1;

      // ── BAR CLOSE (bcX) CONFIGURATION ────────────────────────────────
      cfg.BarClose_Mode          = BC_LAYER_AWARE;
      cfg.BarClose_DefaultEMA    = ROLE_EMA1;
      cfg.BarClose_Enabled       = true;              // true

      // ── PHASE DETECTION & LAYER FILTERING: locked ────────────────────
      cfg.PhaseDetectionEnabled     = true;           // true
      cfg.EnableLayerDetection      = true;           // true
      cfg.BlockUnorderedPhase       = true;           // true
      cfg.BlockEmergingPhase        = false;           // true: EM phase = no trades; TM phase = trades allowed
      cfg.MinPhaseConfirmBars    = (_Period <= PERIOD_M5) ? 0 : 1;       // M1-M5: instant; M15+: require 1 bar confirmation
      cfg.RequireMinPhaseConfirm = (cfg.MinPhaseConfirmBars > 0);        // CRITICAL: without this, m_diag_phase_confirm_bars stays 0 → pre-filter blocks ALL bars

      // Layer permissions per phase (per RRM methodology PNGs):
      //   TRENDING:  Weak + Medium + Strong trades allowed (user-controllable via Inp_RRM_Allow*)
      //   EMERGING:  Weak + Medium allowed; Strong always blocked per RRM methodology
      //   UNORDERED: all blocked (BlockUnorderedPhase = true)
      cfg.Trending_AllowWeakTrades   = Inp_RRM_AllowWeak;
      cfg.Emerging_AllowWeakTrades   = Inp_RRM_AllowWeak;
      cfg.Trending_AllowMediumTrades = Inp_RRM_AllowMedium;
      cfg.Emerging_AllowMediumTrades = Inp_RRM_AllowMedium;
      cfg.Trending_AllowStrongTrades = Inp_RRM_AllowStrong;
      cfg.Emerging_AllowStrongTrades = false;  // STRONG always blocked in EMERGING per RRM methodology

      // ── PULLBACK DETECTION GATES ──────────────────────────────────────
      cfg.RequireRecoveryMomentum      = false;   // Wick-touch recovery valid on M1/M5
      cfg.LayerPullbackEnabled         = Inp_RRM_LayerPullbackEnabled;
      cfg.LayerBaselineLookback        = Inp_RRM_LayerBaselineLookback;
      cfg.LayerPullbackRatio           = Inp_RRM_LayerPullbackRatio;
      cfg.LayerRecoveryRatio           = Inp_RRM_LayerRecoveryRatio;
      cfg.LayerFlatRatio               = Inp_RRM_LayerFlatRatio;
      cfg.LayerAllowReversalPullback   = Inp_RRM_LayerAllowReversalPullback;
      cfg.LayerRecoveryRatio_W         = -1.0;  // use global LayerRecoveryRatio
      cfg.LayerRecoveryRatio_M         = -1.0;
      cfg.LayerRecoveryRatio_S         = -1.0;

      cfg.Gate_Recovery.mode        = GATE_SCALE_AUTO_TF;
      cfg.Gate_Recovery.value       = 1.0;
      cfg.RRM_Lookback              = (_Period <= PERIOD_M1) ? 15 : (_Period <= PERIOD_M5) ? 10 : 12;

      cfg.Gate_EmaDiv.mode          = GATE_SCALE_AUTO_TF;
      cfg.Gate_EmaDiv.value         = 1.0;
      cfg.Gate_CandleDirection.mode  = GATE_SCALE_FIXED;
      cfg.Gate_CandleDirection.value = 1.0;

      // ── VOTE EVALUATION ───────────────────────────────────────────────
      cfg.Vote_EvalShift            = 1;

      // ── RISK MANAGEMENT ───────────────────────────────────────────────
      cfg.CountBEasZeroRisk         = true;              // true
      cfg.FixedLotSize              = 0.0;

      // ── EXIT STRATEGY: flexible via Inp_RRM_* ────────────────────────
      cfg.ExitProfile               = EXIT_PROFILE_RRM;
      cfg.SLMode                    = Inp_RRM_SLMode;
      cfg.TPMode                    = Inp_RRM_TPMode;
      cfg.TP_Enabled                = (Inp_RRM_TPMode != TP_MODE_NONE);
      cfg.RRRatio                   = Inp_RRM_RRRatio;
      cfg.SwingLookback             = Inp_RRM_SwingLookback;
      cfg.SL_SwingPipsCushion       = GetRecommendedInitialSlCushionPips();
      cfg.SL_PsarPipsCushion        = GetRecommendedInitialSlCushionPips();
      cfg.SL_MinPips                = GetRecommendedInitialSlCushionPips();  // Instrument-aware minimum SL floor: prevents tiny-SL fallback from computing oversized lots
      cfg.SL_WidenToMinimum         = true;  // Widen rather than block when SL too close — ensures trade always gets a sane SL
      cfg.SL_AtrPeriod              = Inp_RRM_SL_AtrPeriod;   // Used when SLMode = SL_MODE_ATR
      cfg.SL_AtrMult                = Inp_RRM_SL_AtrMult;     // Used when SLMode = SL_MODE_ATR
      cfg.FixedTPPips               = 40.0;
      cfg.SLPercent                 = 0.5;

      cfg.TrailMode                 = Inp_RRM_TrailMode;
      cfg.PSAR_TrailCushionMode     = PSAR_CUSHION_PIPS;
      cfg.PSAR_TrailPipsCushion     = GetRecommendedTrailPsarCushionPips();
      cfg.RRM_TrailPsarShiftDelay   = Inp_RRM_TrailPsarShiftDelay;
      cfg.RRM_FreezeTrailOnFlip     = Inp_RRM_FreezeTrailOnFlip;
      cfg.RRM_TrailStartsAfterBE    = Inp_RRM_TrailStartsAfterBE;

      // ── ADVANCED TRAILING TRIGGER ─────────────────────────────────────
      ENUM_TIMEFRAMES tf            = (ENUM_TIMEFRAMES)_Period;
      cfg.TrailTrigger              = Inp_RRM_TrailTrigger;
      cfg.TrailDistancePips         = GetTFBasedCushion(tf);
      cfg.TrailLockProfit           = Inp_RRM_TrailLockProfit;
      cfg.TrailProfitPercent        = 2.0;  // used when TRIGGER_PROFIT_PERCENT is active
      cfg.TrailStepPips             = Inp_RRM_TrailStepPips;

      // -- BE
      cfg.BE_Mode                   = BE_MODE_R_MULTIPLE;
      cfg.BEThresholdPips           = GetTFBasedCushion(tf);
      cfg.RRM_BE_RMultiple          = Inp_RRM_BE_RMultiple;
      cfg.RRM_BE_ProgressPct        = Inp_RRM_BE_ProgressPct;
      cfg.RRM_BE_BufferPips         = GetTFBasedCushion(tf);  // M15=5p M1=1.5p H1=8p — CRITICAL: was missing, caused 0 trades

      // ── FRACTAL SL/TP DEFAULTS ────────────────────────────────────────
      cfg.FractalPeriod             = 5;
      cfg.TPFractalOffset           = 1;

      // ── RRM DRAWDOWN PROTECTION ───────────────────────────────────────
      cfg.RRM_EnableDrawdownProtection = Inp_RRM_EnableDrawdownProtection;
      cfg.RRM_MaxConsecutiveLosses  = Inp_RRM_MaxConsecutiveLosses;
      cfg.RRM_MaxTradesPerDay       = Inp_RRM_MaxTradesPerDay;
      cfg.RRM_MaxDailyDrawdownPct   = Inp_RRM_MaxDailyDrawdownPct;

      // ── SLOPE CALCULATION ─────────────────────────────────────────────
      cfg.SlopeLookbackBars         = 1;

      // ── POLICY A: RESTORE OPERATOR-CONTROLLED GATES ───────────────────
      cfg.UseSpread                 = op_UseSpread;
      cfg.UseTime                   = op_UseTime;
      cfg.StartHr                   = op_StartHr;
      cfg.EndHr                     = op_EndHr;
      cfg.UseNews                   = op_UseNews;
      cfg.NewsPre                   = op_NewsPre;
      cfg.NewsPost                  = op_NewsPost;
      cfg.RiskPercent               = GetEffectiveRiskPercent();
      cfg.MaxOpenTrades             = op_MaxOpenTrades;
      cfg.MaxTotalRisk              = op_MaxTotalRisk;
      cfg.MinMarginLevel            = op_MinMarginLevel;
      cfg.EmergencyMarginLevel      = op_EmergencyMarginLevel;

      // ── RE-ENTRY AFTER BREAKEVEN ──────────────────────────────────────
      cfg.AllowReEntryAfterBE       = Inp_RRM_AllowReEntryAfterBE;
      cfg.ReEntryLotScalePct        = MathMax(0, MathMin(100, Inp_RRM_ReEntryLotScalePct));  // 0=full size; 50=half-size re-entry

      // ── POST-TRADE COOLDOWN ───────────────────────────────────────────
      cfg.MinBarsAfterClose         = MathMax(0, Inp_RRM_MinBarsAfterClose);     // RRM cooldown (was hardcoded 3)

      // ── VPRR: Volume Pullback-Recovery Ratio ──────────────────────────
      if(Inp_RRM_VPRR_AutoEnable)
      {
         ST_VPRRAutoMode vprr_auto = GetVPRRRecommendedMode(
            Inp_VPRR_MinRatio_Gold,      Inp_VPRR_MinRatio_Silver,
            Inp_VPRR_MinRatio_IndicesUS, Inp_VPRR_MinRatio_IndicesEU,
            Inp_VPRR_MinRatio_Oil,       Inp_VPRR_MinRatio_Crypto,
            Inp_VPRR_MinRatio_Equities,  Inp_VPRR_MinRatio_FX,
            Inp_VPRR_MinRatio_NonFXTick,
            Inp_VPRR_RecBars_Gold,       Inp_VPRR_RecBars_Silver,
            Inp_VPRR_RecBars_IndicesUS,  Inp_VPRR_RecBars_IndicesEU,
            Inp_VPRR_RecBars_Oil,        Inp_VPRR_RecBars_Crypto,
            Inp_VPRR_RecBars_Equities,   Inp_VPRR_RecBars_FX,
            Inp_VPRR_TF_Mult_M5,         Inp_VPRR_TF_Mult_M15,
            Inp_VPRR_TF_Mult_H1,         Inp_VPRR_TF_Mult_H4Plus,
            Inp_VPRR_TF_ReduceRecBars,   Inp_RRM_VPRR_RecoveryBars
         );
         cfg.VPRR_Enabled         = vprr_auto.enabled;
         cfg.VPRR_VolumeType      = vprr_auto.volume_type;
         cfg.VPRR_MinRatio        = vprr_auto.min_ratio;
         cfg.VPRR_RecoveryBars    = MathMax(1, MathMin(10, vprr_auto.recovery_bars));
      }
      else
      {
         cfg.VPRR_Enabled         = Inp_RRM_VPRR_Enabled;
         cfg.VPRR_VolumeType      = (int)Inp_RRM_VPRR_VolumeType;
         cfg.VPRR_MinRatio        = MathMax(0.1, Inp_VPRR_MinRatio_FX);
         cfg.VPRR_RecoveryBars    = MathMax(1, MathMin(10, Inp_RRM_VPRR_RecoveryBars));
      }
      cfg.VPRR_MinRecoveryBars = MathMax(1, cfg.VPRR_RecoveryBars - 1);
      cfg.VPRR_Weight          = MathMax(1, Inp_RRM_VPRR_Weight);
      PrintVPRRSummary(cfg, "RRM");

      // ── SPREAD RETRY CAP ─────────────────────────────────────────────
      cfg.MaxSpreadRetryBars        = MathMax(1, Inp_RRM_MaxSpreadRetryBars);

      // ── EMA FAN OVEREXTENSION FILTER ──────────────────────────────────
      // Inp_RRM_EmaFanFilterEnabled=false by default — user opt-in.
      // When enabled: Inp_RRM_EmaFanMaxTotalPips sets the pip threshold,
      // Inp_RRM_EmaFanMaxPct sets the % threshold (0=use pips).
      // Recommended starting values: M1/M5=25p, M15/H1=40-60p, H4+=80-120p.
      cfg.EmaFanFilterEnabled       = Inp_RRM_EmaFanFilterEnabled;
      cfg.EmaFanMaxTotalPips        = (Inp_RRM_EmaFanMaxTotalPips > 0.0)
                                         ? Inp_RRM_EmaFanMaxTotalPips * GetEmaFanMultiplier()
                                         : 25.0 * GetEmaFanMultiplier();
      cfg.EmaFanMaxPct              = Inp_RRM_EmaFanMaxPct;

      // ── DPI DECELERATION FILTER ────────────────────────────────────────
      // DPI voter not enabled in PRESET_RRM base; filter stays inactive.
      cfg.DpiDecelFilterEnabled     = false;

      return;
   }


   if(preset == PRESET_RRM_ORG)
   {
#endif // SEA_PRESET_RRM_FAMILY

      // ================================================================
#ifdef SEA_PRESET_RRM_ORG
      // PRESET_RRM_ORG: Original Russ Horn RRM with Inline DPI Voter
      // ================================================================
      //
      // SIGNAL FORMULA (all steps must pass):
      //   STEP 1: DPI (inline MACD) — momentum direction voter
      //   STEP 2: Phase (4-EMA) — UNORDERED blocked, EMERGING/TRENDING allowed
      //   STEP 3: Layer (EMA pair spacing) — WEAK/MEDIUM/STRONG
      //   STEP 4: Recovery gates — Gate_Recovery + Gate_EmaDiv
      //   STEP 5: Bar close (BC_LAYER_AWARE) — close vs role-based EMA
      //   STEP 6: PSAR + CandleBody confirmation
      //   → ENTRY SIGNAL
      //
      // LOCKED: DPI (inline MACD), PSAR, CandleBody, phase structure,
      //         recovery gates, bar close mode.
      // FLEXIBLE: MACD periods (via Zone 3D inputs), SL/TP/Trail modes.
      //
      // ── PHASE A QUALITY PATCH (TS=1 hardening, 2026-05) ──────────────
      // Targets four failure modes seen in 100-trades reference set:
      //   (B) EM→TM flicker entries → MinPhaseConfirmBars TF-scaled > 0
      //   (C) Late-trend / overextended fan entries → EmaFanFilterEnabled
      //       turned on with TF-scaled threshold (mirrors PRESET_RRM)
      //   (C) DPI deceleration leaks → DPI voter forced ON (was opt-in,
      //       which silently disabled the already-coded decel pre-filter)
      //   (D) Tangled-ribbon false TM → MinPhaseConfirmBars + recovery
      // Also fixes a duplicate-write bug on RequireRecoveryMomentum where
      // line 1309 (now removed) was unconditionally overwriting line 1295.
      // ================================================================

      // ── SIGNAL ARCHITECTURE: locked ──────────────────────────────────
      cfg.BiasMode               = BIAS_4EMA;
      cfg.AutoStrat              = STRAT_4EMA_LAYER;
      cfg.BiasFastID             = (int)ROLE_EMA3;    // EMA34: phase direction fast
      cfg.BiasSlowID             = (int)ROLE_EMA4;    // EMA89: phase direction slow
      cfg.MaType                 = METHOD_EMA;
      cfg.CloseOnReverse         = false;
      cfg.BiasEnabled            = true;
      cfg.RequirePriceCross      = false;
      cfg.MABenchmarkStrict      = false;
      cfg.UseMACompatSizer       = false;
      cfg.VoteMode               = VOTE_MODE_ALL;

      // ── EMA PERIODS: RRM_ORG-owned (defaults match RRM standard 5/13/34/89) ──
      cfg.P_Ema1                 = Inp_RRM_ORG_Ema1Period;
      cfg.P_Ema2                 = Inp_RRM_ORG_Ema2Period;
      cfg.P_Ema3                 = Inp_RRM_ORG_Ema3Period;
      cfg.P_Ema4                 = Inp_RRM_ORG_Ema4Period;

      // ── DPI v31: controlled via Inp_RRM_ORG_Ind_Dpi_Enabled (replaces removed Inp_RRM_ORG_ForceDpiOn) ──
      // PHASE A: was opt-in (false). The "ORG" suffix marks the original
      // Russ Horn methodology, which uses DPI as the primary momentum
      // voter — every entry shown in /100-trades/*.{jpg,png} has DPI in
      // the subwindow. Enabling it also activates the DPI deceleration
      // pre-filter (line 4793 of SEA_SignalEngine.mqh) which was dead-code
      // until now because that filter requires Ind_Dpi_Enabled=true.
      cfg.Ind_Dpi_Enabled           = Inp_RRM_ORG_DPI_Enabled;
      cfg.Ind_Dpi_Weight            = Inp_RRM_ORG_DPI_Weight;
      cfg.DPI_MACD_Fast             = Inp_RRM_ORG_DPI_MacdFast;           // default 8
      cfg.DPI_MACD_Slow             = Inp_RRM_ORG_DPI_MacdSlow;           // default 13
      cfg.DPI_RedSignalType         = Inp_RRM_ORG_DPI_RedSignalType;      // default 3 (EMA13)
      cfg.DPI_RedEMA_A              = Inp_RRM_ORG_DPI_RedEMA_A;           // default 5
      cfg.DPI_RedEMA_B              = Inp_RRM_ORG_DPI_RedEMA_B;           // default 8
      cfg.DPI_RedEMA_C              = Inp_RRM_ORG_DPI_RedEMA_C;           // default 13
      cfg.DPI_RedEMA_D              = Inp_RRM_ORG_DPI_RedEMA_D;           // default 21
      cfg.DPI_DoubleSmoothFirst     = Inp_RRM_ORG_DPI_DoubleSmoothFirst;  // default 5
      cfg.DPI_DoubleSmoothSecond    = Inp_RRM_ORG_DPI_DoubleSmoothSecond; // default 8
      cfg.DPI_UseCCIReset           = Inp_RRM_ORG_DPI_UseCCIReset;        // default true
      cfg.DPI_CCI_Period            = Inp_RRM_ORG_DPI_CCI_Period;         // default 13
      cfg.DPI_CCI_AppliedPrice      = (int)Inp_RRM_ORG_DPI_CCI_Price;     // default PRICE_TYPICAL
      cfg.DPI_UseGreenHist          = Inp_RRM_ORG_DPI_UseGreenHist;       // default true

      // ── PSAR: LOCKED ON (timing/direction confirmation) ───────────────
      cfg.Ind_Psar_Enabled          = Inp_RRM_ORG_Use_Psar;
      cfg.Vote_AllowPsarFlip        = Inp_RRM_ORG_Vote_AllowPsarFlip;
      cfg.P_PsarStep                = Inp_RRM_ORG_PsarStep;
      cfg.P_PsarMax                 = Inp_RRM_ORG_PsarMax;
      // Vote: -1=persistent (every bar), 0=flip bar only, 1-10=N candles after flip
      cfg.Vote_PsarFlipDelay        = MathMax(-1, MathMin(10, Inp_RRM_ORG_Vote_PsarFlipDelay));

      // P1: Layer-aware PSAR flip delay overrides
      // -99 = use global Vote_PsarFlipDelay; otherwise override per layer.
      // Rationale: deeper layers (L3/Strong) have slower EMA slopes that lag
      // the PSAR flip by 1-3 bars, so they need a wider acceptance window.
      // The dot-position check always runs first (stale flips in ranging markets
      // are rejected regardless of window size).
      cfg.Vote_PsarFlipDelay_W      = MathMax(-99, MathMin(10, Inp_RRM_ORG_PsarFlipDelay_W));
      cfg.Vote_PsarFlipDelay_M      = MathMax(-99, MathMin(10, Inp_RRM_ORG_PsarFlipDelay_M));
      cfg.Vote_PsarFlipDelay_S      = MathMax(-99, MathMin(10, Inp_RRM_ORG_PsarFlipDelay_S));

      // ── CANDLE BODY ───────────────────────────────────────────────────
      cfg.Ind_CandleBody_Enabled    = Inp_RRM_ORG_Use_CandleBody;
      cfg.Ind_CandleBody_Weight     = Inp_RRM_ORG_CandleBody_Weight;
      cfg.CandleBody_AvgPeriod      = Inp_RRM_ORG_CandleBody_AvgPeriod;
      cfg.CandleBody_MaxMult        = Inp_RRM_ORG_CandleBody_MaxMult;
      cfg.CandleBody_CheckBars      = Inp_RRM_ORG_CandleBody_CheckBars;
      // cfg.CandleBody_CheckBars      = (_Period <= PERIOD_M5) ? 3 : 5;
      cfg.CandleBody_RequireDirection  = Inp_RRM_ORG_CandleBody_RequireDir;
      
      // ── INDICATOR TOGGLES: flexible via Inp_RRM_ORG_* ────────────────
      cfg.Ind_Adx_Enabled        = Inp_RRM_ORG_Use_Adx;
      cfg.Ind_Atr_Enabled        = Inp_RRM_ORG_Use_Atr;
      cfg.Ind_Bb_Enabled         = Inp_RRM_ORG_Use_Bb;
      cfg.Ind_CandleBody_Enabled = Inp_RRM_ORG_Use_CandleBody;
      // CCI/MACD: normally OFF because DPI (the I-factor) replaces them in RRM_ORG.
      // Kept as inputs for A/B testing: set DPI off + these on to compare DPI vs MACD+CCI.
      // Do NOT run DPI and MACD+CCI together — that double-counts the momentum signal.
      cfg.Ind_Cci_Enabled        = Inp_RRM_ORG_Use_Cci;
      cfg.Ind_CI_Enabled         = Inp_RRM_ORG_Use_CI;
      cfg.Ind_Macd_Enabled       = Inp_RRM_ORG_Use_Macd;
      cfg.Ind_Mfi_Enabled        = Inp_RRM_ORG_Use_Mfi;
      cfg.Ind_Psar_Enabled       = Inp_RRM_ORG_Use_Psar;
      cfg.Ind_P123_Enabled       = Inp_RRM_ORG_Use_P123;
      cfg.Ind_Ross_Enabled       = Inp_RRM_ORG_Use_Ross;
      cfg.Ind_Rsi_Enabled        = Inp_RRM_ORG_Use_Rsi;
      cfg.Ind_Sto_Enabled        = Inp_RRM_ORG_Use_Stoch;
      cfg.Ind_SmaConverge_Enabled   = false;
      cfg.Ind_SmaConverge_Weight    = Inp_RRM_ORG_SmaConverge_Weight;
      cfg.Ind_VRC_Enabled        = Inp_RRM_ORG_Use_VRC;

      // ── ADX SETTINGS: safe defaults (disabled) ────────────────────────
      cfg.ADX_Mode                  = Inp_RRM_ORG_Adx_Mode;
      cfg.P_Adx                     = Inp_RRM_ORG_AdxPeriod;
      cfg.T_Adx                     = Inp_RRM_ORG_AdxThreshold;
      cfg.ADX_Percentile            = Inp_RRM_ORG_Adx_Percentile;
      cfg.ADX_Lookback              = Inp_RRM_ORG_Adx_Lookback;
      cfg.ADX_Threshold_Accumulation   = Inp_RRM_ORG_Adx_Thr_Accum;
      cfg.ADX_Threshold_Trending       = Inp_RRM_ORG_Adx_Thr_Trending;
      cfg.ADX_Threshold_Distribution   = Inp_RRM_ORG_Adx_Thr_Distrib;

      // ── ATR SETTINGS: safe defaults (disabled) ────────────────────────
      cfg.P_Atr                     = Inp_RRM_ORG_P_Atr;
      cfg.ATR_VoteMinPips           = Inp_RRM_ORG_ATR_VoteMinPips;
      cfg.ATR_VoteMaxPips           = Inp_RRM_ORG_ATR_VoteMaxPips;

      // ── MACD SETTINGS: safe defaults (disabled) ───────────────────────
      cfg.MacdVoteMode              = Inp_RRM_ORG_MacdMode;
      cfg.MacdRequireSlope          = Inp_RRM_ORG_MacdSlope;
      cfg.MacdRequireDivergence     = Inp_RRM_ORG_MacdDiv;
      cfg.MacdRequireHook           = false;
      cfg.MacdHistDecelEnabled      = false;  // RRM_ORG uses DPI voter (not MACD histogram) as its momentum gate — decel handled via DPI_BlockOnDeceleration
      cfg.P_MacdFast                = Inp_RRM_ORG_MacdFast;
      cfg.P_MacdSlow                = Inp_RRM_ORG_MacdSlow;
      cfg.P_MacdSig                 = Inp_RRM_ORG_MacdSig;
      cfg.MacdFreshBars             = Inp_RRM_ORG_MacdFreshBars;
      cfg.MacdSlopeMin              = Inp_RRM_ORG_MacdSlopeMin;

      // ── CCI/RSI/STOCH/BB/MFI: safe defaults (all disabled) ───────────
      cfg.CciMode                   = Inp_RRM_ORG_CciMode;
      cfg.P_Cci                     = Inp_RRM_ORG_CciPeriod;

      // ── CI SETTINGS: flexible via Inp_RRM_ORG_* ──────────────────────
      cfg.CI_Period                 = Inp_RRM_ORG_CiPeriod;
      cfg.CI_RangingThreshold       = Inp_RRM_ORG_CiRangingThreshold;

      cfg.RsiMode                   = Inp_RRM_ORG_RsiMode;
      cfg.P_Rsi                     = Inp_RRM_ORG_RsiPeriod;
      cfg.T_RsiOB                   = Inp_RRM_ORG_Rsi_OB;
      cfg.T_RsiOS                   = Inp_RRM_ORG_Rsi_OS;

      cfg.StoMode                   = Inp_RRM_ORG_Sto_Mode;
      cfg.P_StoK                    = Inp_RRM_ORG_Sto_K;
      cfg.P_StoD                    = Inp_RRM_ORG_Sto_D;
      cfg.P_StoSlow                 = Inp_RRM_ORG_Sto_Slow;
      cfg.T_StoOB                   = Inp_RRM_ORG_Sto_OB;
      cfg.T_StoOS                   = Inp_RRM_ORG_Sto_OS;

      cfg.BbMode                    = Inp_RRM_ORG_Bb_Mode;
      cfg.P_Bb                      = Inp_RRM_ORG_Bb_Period;
      cfg.P_BbDev                   = Inp_RRM_ORG_Bb_Deviation;

      cfg.MfiMode                   = Inp_RRM_ORG_Mfi_Mode;
      cfg.P_Mfi                     = Inp_RRM_ORG_Mfi_Period;
      cfg.T_MfiOB                   = Inp_RRM_ORG_Mfi_OB;
      cfg.T_MfiOS                   = Inp_RRM_ORG_Mfi_OS;

      cfg.Ind_VRC_Weight            = Inp_RRM_ORG_VPRR_Weight_VRC;
      cfg.VRC_ATR_Period            = Inp_RRM_ORG_VRC_ATR_Period;
      cfg.VRC_Lookback              = Inp_RRM_ORG_VRC_Lookback;
      cfg.VRC_LowThreshold          = Inp_RRM_ORG_VRC_LowThreshold;

      // ── BAR CLOSE (bcX): LOCKED to layer-aware ───────────────────────
      cfg.BarClose_Mode             = BC_LAYER_AWARE;   // bcW=EMA1, bcM=EMA2, bcS=EMA3
      cfg.BarClose_DefaultEMA       = ROLE_EMA1;
      cfg.BarClose_Enabled          = true;

      // ── PHASE DETECTION & LAYER FILTERING: LOCKED ON ─────────────────
      cfg.PhaseDetectionEnabled     = true;
      cfg.EnableLayerDetection      = true;
      cfg.BlockUnorderedPhase       = true;           // UNORDERED → block all trades
      cfg.BlockEmergingPhase        = false;           // true: EM phase = no trades; TM phase = trades allowed

      // PHASE A: TF-scaled phase-age confirmation. The previous setting
      // (0 on every TF) lets a single bar that flickers into TM after UNO
      // qualify as a setup — see trade #095 (EURJPY M5) and #075 (USDJPY
      // M5) where the entry bar is the first/second TM bar after a
      // tangled-ribbon zone and price reverses immediately. Requiring
      // 1–3 bars of phase persistence kills these flickers cheaply.
      // Operator-tunable via Inp_RRM_ORG_PhaseConfirm* (Phase B).
      cfg.RequireMinPhaseConfirm    = true;  // ✅ ENABLE COUNTER UPDATE
      cfg.MinPhaseConfirmBars       = (_Period <= PERIOD_M5)  ? Inp_RRM_ORG_PhaseConfirmM5
                                    : (_Period <= PERIOD_M30) ? Inp_RRM_ORG_PhaseConfirmM30
                                    :                           Inp_RRM_ORG_PhaseConfirmH1plus;

      // EMERGING phase: WEAK + MEDIUM only; STRONG always blocked per RRM methodology
      cfg.Emerging_AllowWeakTrades   = Inp_RRM_AllowWeak;
      cfg.Emerging_AllowMediumTrades = Inp_RRM_AllowMedium;
      cfg.Emerging_AllowStrongTrades = false;         // STRONG always blocked in EMERGING per RRM methodology

      // TRENDING phase: controlled by layer filter inputs (Inp_RRM_Allow*)
      cfg.Trending_AllowWeakTrades   = Inp_RRM_AllowWeak;
      cfg.Trending_AllowMediumTrades = Inp_RRM_AllowMedium;
      cfg.Trending_AllowStrongTrades = Inp_RRM_AllowStrong;

      // ── PULLBACK DETECTION GATES: LOCKED ON ──────────────────────────
      // PHASE A: require recovery momentum on M15-and-down. The original
      // code set it true on M5 then immediately overwrote with `false` on
      // a second line — duplicate-write bug. Wick-touch recoveries are
      // the dominant noise mode on intraday, see trade #095.
      // Operator-tunable via Inp_RRM_ORG_RequireRecoveryIntraday.
      cfg.RequireRecoveryMomentum   = Inp_RRM_ORG_RequireRecoveryIntraday && (_Period <= PERIOD_M15);

      cfg.Gate_Recovery.mode        = GATE_SCALE_AUTO_TF;
      // PHASE A: JPY pairs run ~1.3× the natural noise vs majors at the
      // same TF. Loosen recovery distance proportionally so we don't chop
      // out of legitimate setups (#001 USDJPY, #060 GBPJPY, #100 EURJPY).
      // Operator-tunable via Inp_RRM_ORG_JpyGateMultiplier (1.0=disabled).
      {
         bool isJpyOrg = (StringFind(_Symbol, "JPY") >= 0);
         double jpyMul = (Inp_RRM_ORG_JpyGateMultiplier > 0.0) ? Inp_RRM_ORG_JpyGateMultiplier : 1.0;
         cfg.Gate_Recovery.value = isJpyOrg ? jpyMul : 1.0;
         cfg.Gate_EmaDiv.value   = isJpyOrg ? jpyMul : 1.0;
      }
      cfg.RRM_Lookback              = (_Period <= PERIOD_M1) ? 15 : (_Period <= PERIOD_M5) ? 10 : 12;

      cfg.Gate_EmaDiv.mode          = GATE_SCALE_AUTO_TF;
      cfg.Gate_CandleDirection.mode  = GATE_SCALE_FIXED;
      cfg.Gate_CandleDirection.value = 1.0;

      // ── P2: PULLBACK STATE MACHINE ─────────────────────────────────
      // Activates the NONE→DETECTED→RECOVERED state machine that already
      // exists in SEA_SignalEngine.mqh (UpdateSingleLayerPullback).
      // When enabled, CheckLayerPairAlign blocks layers that haven't
      // completed a full pullback-recovery cycle. This prevents entries
      // on continuous trending (no pullback) or mid-pullback (not yet recovered).
      //
      // The state machine runs per layer:
      //   NONE → DETECTED:  slope ratio < PullbackRatio (weakened), or
      //                     slope flattened (< FlatRatio), or slope reversed
      //   DETECTED → RECOVERED: slope resumed bias direction AND
      //                     ratio >= RecoveryRatio (per-layer or global)
      //   RECOVERED → DETECTED: new pullback detected (re-entrant)
      //
      // Per-layer recovery ratios (P2 extension): deeper layers have slower
      // EMAs, so they need less recovery momentum to confirm. Default values:
      //   L1 (Weak/EMA5-EMA13):  0.4 — fast EMAs, expect clear turn
      //   L2 (Medium/EMA13-EMA34): 0.3 — moderate, matches global default
      //   L3 (Strong/EMA34-EMA89): 0.2 — slow EMAs, early recovery is enough
      cfg.LayerPullbackEnabled        = Inp_RRM_ORG_LayerPBEnabled;
      cfg.LayerBaselineLookback       = MathMax(3, MathMin(20, Inp_RRM_ORG_LayerPBLookback));
      cfg.LayerPullbackRatio          = MathMax(0.1, MathMin(1.0, Inp_RRM_ORG_LayerPBPullbackRatio));
      cfg.LayerRecoveryRatio          = MathMax(0.1, MathMin(1.0, Inp_RRM_ORG_LayerPBRecoveryRatio));
      cfg.LayerFlatRatio              = MathMax(0.05, MathMin(0.5, Inp_RRM_ORG_LayerPBFlatRatio));
      cfg.LayerAllowReversalPullback  = Inp_RRM_ORG_LayerPBAllowReversal;
      // Per-layer recovery ratio overrides (-1.0 = use global LayerRecoveryRatio)
      cfg.LayerRecoveryRatio_W        = Inp_RRM_ORG_RecoveryRatio_W;
      cfg.LayerRecoveryRatio_M        = Inp_RRM_ORG_RecoveryRatio_M;
      cfg.LayerRecoveryRatio_S        = Inp_RRM_ORG_RecoveryRatio_S;

      // VPRR: Volume Pullback-Recovery Ratio (institutional participation confirmation)
      // AutoEnable=true: probe instrument + volume at preset-apply time; per-instrument settings applied.
      // AutoEnable=false: respect Inp_RRM_ORG_VPRR_Enabled / VolumeType / MinRatio manually.
      if(Inp_RRM_ORG_VPRR_AutoEnable)
      {
         ST_VPRRAutoMode vprr_auto = GetVPRRRecommendedMode(
            Inp_VPRR_MinRatio_Gold,      Inp_VPRR_MinRatio_Silver,
            Inp_VPRR_MinRatio_IndicesUS, Inp_VPRR_MinRatio_IndicesEU,
            Inp_VPRR_MinRatio_Oil,       Inp_VPRR_MinRatio_Crypto,
            Inp_VPRR_MinRatio_Equities,  Inp_VPRR_MinRatio_FX,
            Inp_VPRR_MinRatio_NonFXTick,
            Inp_VPRR_RecBars_Gold,       Inp_VPRR_RecBars_Silver,
            Inp_VPRR_RecBars_IndicesUS,  Inp_VPRR_RecBars_IndicesEU,
            Inp_VPRR_RecBars_Oil,        Inp_VPRR_RecBars_Crypto,
            Inp_VPRR_RecBars_Equities,   Inp_VPRR_RecBars_FX,
            Inp_VPRR_TF_Mult_M5,         Inp_VPRR_TF_Mult_M15,
            Inp_VPRR_TF_Mult_H1,         Inp_VPRR_TF_Mult_H4Plus,
            Inp_VPRR_TF_ReduceRecBars,   Inp_RRM_ORG_VPRR_RecoveryBars
         );
         cfg.VPRR_Enabled     = vprr_auto.enabled;
         cfg.VPRR_VolumeType  = vprr_auto.volume_type;
         cfg.VPRR_MinRatio    = vprr_auto.min_ratio;
         cfg.VPRR_RecoveryBars    = MathMax(1, MathMin(10, vprr_auto.recovery_bars));
      }
      else
      {
         cfg.VPRR_Enabled         = Inp_RRM_ORG_VPRR_Enabled;
         cfg.VPRR_VolumeType      = (int)Inp_RRM_ORG_VPRR_VolumeType;
         cfg.VPRR_MinRatio        = MathMax(0.1, Inp_VPRR_MinRatio_FX);
         cfg.VPRR_RecoveryBars    = MathMax(1, MathMin(10, Inp_RRM_ORG_VPRR_RecoveryBars));
      }
      cfg.VPRR_MinRecoveryBars = MathMax(1, cfg.VPRR_RecoveryBars - 1);
      cfg.VPRR_Weight          = MathMax(1, Inp_RRM_ORG_VPRR_Weight);
      PrintVPRRSummary(cfg, "RRM_ORG");

      // ── VOTE EVALUATION ───────────────────────────────────────────────
      cfg.Vote_EvalShift            = 1;

      // ── RISK MANAGEMENT ───────────────────────────────────────────────
      cfg.CountBEasZeroRisk         = true;
      cfg.FixedLotSize              = 0.0;

      // ── EXIT STRATEGY: RRM_ORG-specific inputs (complete namespace) ──
      cfg.ExitProfile               = EXIT_PROFILE_RRM;
      cfg.SLMode                    = Inp_RRM_ORG_SLMode;
      cfg.TPMode                    = Inp_RRM_ORG_TPMode;
      cfg.TP_Enabled                = (Inp_RRM_ORG_TPMode != TP_MODE_NONE);
      cfg.RRRatio                   = Inp_RRM_ORG_RRRatio;
      cfg.SwingLookback             = Inp_RRM_ORG_SwingLookback;
      cfg.SL_SwingPipsCushion       = GetRecommendedInitialSlCushionPips();
      cfg.SL_PsarPipsCushion        = GetRecommendedInitialSlCushionPips();
      cfg.SL_MinPips                = GetRecommendedInitialSlCushionPips();  // Instrument-aware minimum SL floor: prevents tiny-SL fallback from computing oversized lots
      cfg.SL_WidenToMinimum         = true;  // Widen rather than block when SL too close — ensures trade always gets a sane SL
      cfg.SL_AtrPeriod              = Inp_RRM_ORG_SL_AtrPeriod;  // Used when SLMode = SL_MODE_ATR
      cfg.SL_AtrMult                = Inp_RRM_ORG_SL_AtrMult;    // Used when SLMode = SL_MODE_ATR; Gold M15: try 1.0–1.5
      cfg.FixedTPPips               = 40.0;
      cfg.SLPercent                 = 0.5;

      cfg.TrailMode                 = Inp_RRM_ORG_TrailMode;
      // TRAIL_EMA: set period/shift so RRM_ManageStrictNoATR uses the right EMA.
      // Period=0 means "use ribbon EMA1 (P_Ema1)" — handled as fallback in executor.
      // TRAIL_EMA period resolution:
      //   Period > 0  → use that explicit period directly
      //   Period = 0  → use the ribbon EMA selected by RibbonRole
      //     ROLE_EMA1 (0) = cfg.P_Ema1 (default 5)   — very tight, not recommended for trailing
      //     ROLE_EMA2 (1) = cfg.P_Ema2 (default 13)  — good balance: responsive but some distance
      //     ROLE_EMA3 (2) = cfg.P_Ema3 (default 34)  — slower, gives trend more room
      //     ROLE_EMA4 (3) = cfg.P_Ema4 (default 89)  — very slow, maximum trend-following room
      cfg.TrailEMA_RibbonRole       = (int)Inp_RRM_ORG_TrailEMA_RibbonRole;
      if(Inp_RRM_ORG_TrailEMA_Period > 0) {
         cfg.TrailEMA_Period        = Inp_RRM_ORG_TrailEMA_Period;
      } else {
         switch((EEmaRole)cfg.TrailEMA_RibbonRole) {
            case ROLE_EMA1: cfg.TrailEMA_Period = cfg.P_Ema1; break;
            case ROLE_EMA2: cfg.TrailEMA_Period = cfg.P_Ema2; break;
            case ROLE_EMA3: cfg.TrailEMA_Period = cfg.P_Ema3; break;
            case ROLE_EMA4: cfg.TrailEMA_Period = cfg.P_Ema4; break;
            default:        cfg.TrailEMA_Period = cfg.P_Ema2; break;  // safe fallback
         }
      }
      cfg.TrailEMA_Shift            = MathMax(1, MathMin(5, Inp_RRM_ORG_TrailEMA_Shift));
      // EMA trail cushion: ATR-based is the recommended mode (auto-scales with instrument volatility).
      // Priority: ATR mult > pip value > PSAR_TrailPipsCushion fallback (in executor).
      cfg.TrailEMA_CushionPips         = MathMax(0.0, Inp_RRM_ORG_TrailEMA_CushionPips);
      cfg.TrailEMA_CushionAtrMult      = MathMax(0.0, Inp_RRM_ORG_TrailEMA_CushionAtrMult);
      cfg.TrailEMA_CushionAtrPeriod    = MathMax(1,   Inp_RRM_ORG_TrailEMA_CushionAtrPeriod);
      cfg.RRM_TrailPsarShiftDelay   = (Inp_RRM_ORG_TrailPsarShiftDelay < 1) ? 1 : (Inp_RRM_ORG_TrailPsarShiftDelay > 3) ? 3 : Inp_RRM_ORG_TrailPsarShiftDelay; // PSAR DOT trail shift (TRAILING only); default 2 for flip stability
      cfg.RRM_TrailStartsAfterBE    = Inp_RRM_ORG_TrailStartsAfterBE;
      cfg.TrailProfitPercentLPR     = Inp_RRM_ORG_TrailProfitPercentLPR;
      cfg.PSAR_TrailCushionMode     = Inp_RRM_ORG_PSAR_TrailCushionMode;
      cfg.PSAR_TrailCushionAtrPeriod = MathMax(1, Inp_RRM_ORG_TrailCushionAtrPeriod);
      cfg.PSAR_TrailCushionAtrMult   = MathMax(0.0, Inp_RRM_ORG_TrailCushionAtrMult);
      cfg.PSAR_TrailCushionPct       = MathMax(0.0, Inp_RRM_ORG_TrailCushionPct);
      cfg.PSAR_TrailPipsCushion     = GetRecommendedTrailPsarCushionPips(); // legacy PIPS-mode value; used only when cushion mode = PIPS
      cfg.BE_Mode                   = Inp_RRM_ORG_BE_Mode;
      cfg.RRM_BE_RMultiple          = Inp_RRM_ORG_BE_RMultiple;
      cfg.RRM_BE_ProgressPct        = Inp_RRM_ORG_BE_ProgressPct;
      cfg.RRM_BE_BufferPips         = GetTFBasedCushion(_Period);

      ENUM_TIMEFRAMES tfOrg         = (ENUM_TIMEFRAMES)_Period;
      cfg.TrailTrigger              = Inp_RRM_ORG_TrailTrigger;
      cfg.TrailDistancePips         = GetTFBasedCushion(tfOrg);
      cfg.BEThresholdPips           = GetTFBasedCushion(tfOrg);
      cfg.TrailLockProfit           = Inp_RRM_ORG_TrailLockProfit;
      cfg.TrailProfitPercent        = Inp_RRM_ORG_TrailProfitPercentLPR; // used when TRIGGER_PROFIT_PERCENT is active
      cfg.TrailStepPips             = Inp_RRM_ORG_TrailStepPips;

      cfg.FractalPeriod             = 5;
      cfg.TPFractalOffset           = 1;

      // ── DRAWDOWN PROTECTION ───────────────────────────────────────────
      // PHASE A: force-on for ORG (a "quality-first" preset). User can
      // still tune the thresholds via Inp_RRM_ORG_DD* and Inp_RRM_Max* inputs.
      cfg.RRM_EnableDrawdownProtection = Inp_RRM_ORG_ForceDDProtection; // Inp_RRM_EnableDrawdownProtection removed (cross-preset ref)
      cfg.RRM_MaxConsecutiveLosses  = (Inp_RRM_ORG_DDMaxConsecLosses > 0)
                                          ? Inp_RRM_ORG_DDMaxConsecLosses : 4;
      cfg.RRM_MaxTradesPerDay       = (Inp_RRM_ORG_DDMaxTradesPerDay > 0)
                                          ? Inp_RRM_ORG_DDMaxTradesPerDay : 5;
      cfg.RRM_MaxDailyDrawdownPct   = (Inp_RRM_ORG_DDMaxDailyPct > 0.0)
                                          ? Inp_RRM_ORG_DDMaxDailyPct : 2.0;

      // ── SLOPE CALCULATION ─────────────────────────────────────────────
      cfg.SlopeLookbackBars         = 1;
      cfg.ma_h_shift                = 0;
      cfg.ma_v_shift                = 1;

      // ── POLICY A: RESTORE OPERATOR-CONTROLLED GATES ───────────────────
      cfg.MaxSpread                 = op_MaxSpread;
      cfg.UseSpread                 = op_UseSpread;
      cfg.UseTime                   = op_UseTime;
      cfg.StartHr                   = op_StartHr;
      cfg.EndHr                     = op_EndHr;
      cfg.UseNews                   = op_UseNews;
      cfg.NewsPre                   = op_NewsPre;
      cfg.NewsPost                  = op_NewsPost;
      cfg.RiskPercent               = GetEffectiveRiskPercent();
      cfg.MaxOpenTrades             = op_MaxOpenTrades;
      cfg.MaxTotalRisk              = op_MaxTotalRisk;
      cfg.MinMarginLevel            = op_MinMarginLevel;
      cfg.EmergencyMarginLevel      = op_EmergencyMarginLevel;

      // ── MTF CONFIRMATION (replaces deprecated HTF filter) ───────────────
      cfg.Ind_MTF_Enabled           = Inp_Ind_MTF_Enabled;
      cfg.Ind_MTF_Weight            = Inp_Ind_MTF_Weight;
      cfg.MTF_TF1                   = GetSafeMTF_TF1(Inp_MTF_TF1);
      cfg.MTF_TF2                   = GetSafeMTF_TF2(Inp_MTF_TF2);
      cfg.MTF_EMA_Fast              = Inp_MTF_EMA_Fast;
      cfg.MTF_EMA_Slow              = Inp_MTF_EMA_Slow;
      cfg.MTF_RequirePhase          = false;   // Position-only check; slope requirement kills too many signals due to HTF EMA lag
      cfg.MTF_StrictAlignment       = Inp_MTF_StrictAlignment;   // HTF directional gate: trade only with higher-TF trend(s). User-controlled.

      // Legacy HTF filter: Inp_RRM_ORG_HtfFilter overrides the MTF inputs with
      // single-TF slope-based behaviour (MTF_EMA_Fast == MTF_EMA_Slow triggers
      // the slope path in GetMTFBias()).  TF and EMA period are taken from the
      // modern Inp_MTF_TF1 / Inp_MTF_EMA_Fast inputs so users only need those.
      if(Inp_RRM_ORG_HtfFilter)
      {
         cfg.Ind_MTF_Enabled        = true;
         cfg.MTF_TF1                = GetSafeMTF_TF1(Inp_MTF_TF1);
         cfg.MTF_TF2                = PERIOD_CURRENT;  // single-TF behaviour
         cfg.MTF_EMA_Fast           = Inp_MTF_EMA_Fast;
         cfg.MTF_EMA_Slow           = Inp_MTF_EMA_Fast; // equal periods → slope mode in engine
         cfg.MTF_RequirePhase       = false;
      }

      // ── RE-ENTRY AFTER BREAKEVEN ──────────────────────────────────────
      cfg.AllowReEntryAfterBE       = Inp_RRM_ORG_AllowReEntryAfterBE;
      cfg.ReEntryLotScalePct        = MathMax(0, MathMin(100, Inp_RRM_ORG_ReEntryLotScalePct));  // 0=full size; 50=half-size re-entry

      // ── POST-TRADE COOLDOWN ───────────────────────────────────────────
      cfg.MinBarsAfterClose         = MathMax(0, Inp_RRM_ORG_MinBarsAfterClose); // RRM_ORG cooldown (was hardcoded 3)

      // ── SPREAD RETRY CAP ─────────────────────────────────────────────
      cfg.MaxSpreadRetryBars        = MathMax(1, Inp_RRM_ORG_MaxSpreadRetryBars);

      // ── EMA FAN OVEREXTENSION FILTER ──────────────────────────────────
      // PHASE A: turned ON with TF-scaled threshold. The previous setting
      // (false / 25 pips) silently disabled the filter entirely. The 25-pip
      // value is correct only for M1/M5; H4 and Daily fan widths in the
      // dataset routinely exceed 80–150 pips on legitimate trends, so a
      // single hardcoded threshold can't work across the TF range we see.
      // The engine logic at SEA_SignalEngine.mqh:4754 only rejects when
      // `gap_now > max && gap_now > gap_prev` (i.e. still expanding), so
      // late-trend chases like #075 are blocked while fresh impulses pass.
      // Operator-tunable via Inp_RRM_ORG_EmaFanFilter and Inp_RRM_ORG_EmaFan_*.
      cfg.EmaFanFilterEnabled       = Inp_RRM_ORG_EmaFanFilter;
      double rrm_org_fan_base       = (_Period <= PERIOD_M5)  ? Inp_RRM_ORG_EmaFan_M5Pips
                                    : (_Period <= PERIOD_M30) ? Inp_RRM_ORG_EmaFan_M30Pips
                                    : (_Period <= PERIOD_H1)  ? Inp_RRM_ORG_EmaFan_H1Pips
                                    : (_Period <= PERIOD_H4)  ? Inp_RRM_ORG_EmaFan_H4Pips
                                    :                           Inp_RRM_ORG_EmaFan_DailyPips;
      cfg.EmaFanMaxTotalPips        = rrm_org_fan_base * GetEmaFanMultiplier();

      // Percentage-based alternative: if user set EmaFan_MaxPct > 0, use it instead.
      // This works universally across all instruments without multipliers.
      cfg.EmaFanMaxPct              = MathMax(0.0, Inp_RRM_ORG_EmaFan_MaxPct);
      if(cfg.EmaFanMaxPct > 0.0)
      {
         PrintFormat("📐 [EMA_FAN] Using percentage mode: %.3f%% (overrides pip-based threshold %.1f)",
                     cfg.EmaFanMaxPct, cfg.EmaFanMaxTotalPips);
      }

      // ── DPI DECELERATION FILTER ────────────────────────────────────────
      // PHASE A: now actually active because Ind_Dpi_Enabled is true above.
      // Operator-tunable via Inp_RRM_ORG_DPI_Decel_Filter.
      cfg.DpiDecelFilterEnabled     = Inp_RRM_ORG_DPI_Decel_Filter;

      // ── PHASE B: RECOVERY SENSITIVITY TUNING (opt-in, all default disabled/0) ──────────
      // These settings widen specific bottlenecks in the TS→TE pipeline to allow valid
      // pullback-recovery setups through.  All default to the conservative value that
      // preserves the original PRESET_RRM_ORG contract.
      cfg.DPI_IgnoreCCIForVote      = Inp_RRM_ORG_DPI_IgnoreCCIForVote;
      cfg.Layer_SlopeTolerance      = 0.0;   // Hardcoded: obsolete pip-based slope tolerance removed
      cfg.BarClose_PipTolerance     = Inp_RRM_ORG_BarClose_PipTolerance;
      cfg.BarClose_LookbackBars        = MathMax(1, MathMin(4, Inp_RRM_ORG_BarClose_LookbackBars));
      cfg.Require_Progressive_Momentum = Inp_RRM_ORG_BarClose_Require_Progressive_Momentum;
      cfg.DPI_Histogram_Growth_Boost   = Inp_RRM_ORG_DPI_Histogram_Growth_Boost;
      cfg.PSAR_FlipGraceBars        = Inp_RRM_ORG_PSAR_FlipGraceBars;

      // ── PHASE B: TE-side hardening (standardized veto inputs) ──────────
      cfg.TE_RecheckBarClose        = Inp_VETO_TE_RecheckBarClose;
      cfg.TE_BC_TolerancePips       = Inp_VETO_TE_BC_TolerancePips;
      cfg.TE_OpenDelaySeconds       = Inp_VETO_TE_OpenDelaySeconds;
      cfg.TE_SpreadMedianTicks      = Inp_VETO_TE_SpreadMedianTicks;

      ValidateRRM_ORG_ExitConfig(cfg);
      return;
   }


   if(preset == PRESET_TOPINVESTOR)
   {
      // ================================================================
#endif // SEA_PRESET_RRM_ORG

      // PRESET_TOPINVESTOR — Dr Świerk's TopInvestor / OXO Methodology
#ifdef SEA_PRESET_TOPINVESTOR
      // ================================================================
      //
      // Unified preset covering all 3 TopInvestor systems:
      //   System 1: EMA bounce (Layer pullback to EMA 50/200)
      //   System 2: Key level (Fibonacci retracement depth check)
      //   System 3: Exhaustion (DPI momentum + MACD divergence)
      //
      // OXO replaced by multi-indicator voting pipeline.
      // Three profiles via Inp_TI_* toggles:
      //   Conservative (5 voters) = K-3 confluence
      //   Moderate     (8 voters) = K-4/K-5 confluence
      //   Full         (11 voters) = K-6 confluence
      //
      // HTF anchor: EMA 50/200 (institutional standard) via MTF voter
      // Entry TF:   EMA 9/50/89/200 (TopInvestor template)
      //
      // SIGNAL FORMULA:
      //   TS = Phase(4EMA) × Layer × BC × BD × Indicators × Filters
      //
      // LOCKED: Architecture, EMA periods, phase/layer structure.
      // FLEXIBLE: Profile (Conservative/Moderate/Full via Inp_TI_*),
      //           SL/TP/Trail, session hours, spread, news filter.
      // ================================================================

      // ── SIGNAL ARCHITECTURE: locked ──────────────────────────────────
      // These define the fundamental engine of the TI methodology.
      // Changing them would produce a different strategy, not a variant of TI.
      cfg.BiasMode               = BIAS_4EMA;          // LOCKED: 4EMA phase detection is the TI definition; other modes break phase/layer logic entirely
      cfg.AutoStrat              = STRAT_4EMA_LAYER;   // LOCKED: layer pullback detection requires BIAS_4EMA; any other strat ignores the layer structure
      cfg.VoteMode               = VOTE_MODE_ALL;      // LOCKED: all voters must agree; THRESHOLD mode would let partial agreement trigger trades, undermining K-3/K-6 confluence design
      cfg.BiasEnabled            = true;               // LOCKED: bias filter is always required
      cfg.BiasFastID             = (int)ROLE_EMA3;     // LOCKED: EMA3(89) is the fast bias reference — TI standard; wired to Ema3 input
      cfg.BiasSlowID             = (int)ROLE_EMA4;     // LOCKED: EMA4(200) is the slow bias reference — TI standard; wired to Ema4 input
      cfg.MaType                 = METHOD_EMA;         // LOCKED: TopInvestor uses EMA exclusively; SMA would be a different methodology
      cfg.CloseOnReverse         = Inp_TI_CloseOnReverse;
      cfg.RequirePriceCross      = false;              // LOCKED: TI uses phase/layer for entry timing, not a price-cross event signal
      cfg.MABenchmarkStrict      = false;              // LOCKED: benchmark mode is for PRESET_MA only; enabling it breaks vote logic
      cfg.UseMACompatSizer       = false;              // LOCKED: TI uses risk-% sizer; MA compat sizer is for the benchmark preset only

      // ── EMA PERIODS (user-controlled via Inp_TI_Ema*) ─────────────
      cfg.P_Ema1                 = Inp_TI_Ema1;   // default 9   — trailing exit reference
      cfg.P_Ema2                 = Inp_TI_Ema2;   // default 50  — primary bounce level
      cfg.P_Ema3                 = Inp_TI_Ema3;   // default 89  — intermediate structure
      cfg.P_Ema4                 = Inp_TI_Ema4;   // default 200 — major trend anchor

      // ── PHASE: TM-only or allow EM via user toggle ────────────────
      cfg.PhaseDetectionEnabled     = true;            // LOCKED: phase detection is mandatory for 4EMA/layer architecture; disabling it collapses to a simple cross system
      cfg.EnableLayerDetection      = true;            // LOCKED: layer detection is the core of System 1 (EMA bounce); disabling it removes pullback/recovery logic entirely
      cfg.BlockUnorderedPhase       = Inp_TI_BlockUnorderedPhase;
      cfg.BlockEmergingPhase        = !Inp_TI_PhaseAllowEM;
      cfg.RequireMinPhaseConfirm    = Inp_TI_RequireMinPhaseConfirm;
      cfg.MinPhaseConfirmBars       = (_Period <= PERIOD_M5) ? 1 : 2;  // LOCKED: auto-scaled by TF — shorter TFs need fewer confirm bars; hardcoding one value would over-filter on M1 or under-filter on H4

      // Layer permissions
      // Trending phase: all 3 layers allowed — TI trades any pullback depth in a confirmed trend
      cfg.Trending_AllowWeakTrades   = true;           // LOCKED: weak pullbacks (L1) are valid TI entries in trending phase
      cfg.Trending_AllowMediumTrades = true;           // LOCKED: medium pullbacks (L2) are valid TI entries in trending phase
      cfg.Trending_AllowStrongTrades = true;           // LOCKED: strong pullbacks (L3) are valid TI entries in trending phase
      // Emerging phase: weak and medium allowed, strong controlled by user toggle
      cfg.Emerging_AllowWeakTrades   = true;           // LOCKED: L1 allowed in EM — less aggressive pullback, safer in emerging trend
      cfg.Emerging_AllowMediumTrades = true;           // LOCKED: L2 allowed in EM — standard confluence depth
      cfg.Emerging_AllowStrongTrades = Inp_TI_Emerging_AllowStrong; // user-controlled: strong EM trades are riskier (deeper pullback in unconfirmed trend)

      // ── LAYER: pullback-recovery detection ─────────────────────────
      cfg.LayerPullbackEnabled        = true;          // LOCKED: pullback detection is System 1 of TI; disabling it makes the preset trade raw EMA crosses only
      cfg.LayerBaselineLookback       = Inp_TI_LayerBaselineLookback;
      cfg.LayerPullbackRatio          = Inp_TI_LayerPullbackRatio;
      cfg.LayerRecoveryRatio          = Inp_TI_LayerRecoveryRatio;
      cfg.LayerFlatRatio              = Inp_TI_LayerFlatRatio;
      cfg.LayerAllowReversalPullback  = true;          // LOCKED: reversal pullbacks are part of the TI methodology (counter-trend bounce to EMA)
      cfg.LayerRecoveryRatio_W        = -1.0;          // LOCKED: -1 = inherit global LayerRecoveryRatio for all sub-layers; per-layer overrides not needed in TI
      cfg.LayerRecoveryRatio_M        = -1.0;          // LOCKED: same — uniform recovery ratio across L1/L2/L3
      cfg.LayerRecoveryRatio_S        = -1.0;          // LOCKED: same

      // ── BAR CLOSE: layer-aware ─────────────────────────────────────
      cfg.BarClose_Enabled       = true;               // LOCKED: bar-close confirmation is required to avoid intra-bar noise entries
      cfg.BarClose_Mode          = BC_LAYER_AWARE;     // LOCKED: layer-aware mode ties the close check to the active layer EMA (L1→EMA1, L2→EMA2, L3→EMA3); other modes ignore layer context
      cfg.BarClose_DefaultEMA    = ROLE_EMA1;          // LOCKED: fallback EMA for BC_FIXED_EMA mode; EMA1 (fast) is the tightest valid reference

      // ── HIGHER TF CONFIRMATION: EMA 50/200 (institutional) ────────
      // TopInvestor: "the secret to success is 2 timeframes higher"
      // One HTF voter: auto-computed 2 steps above chart TF
      cfg.Ind_MTF_Enabled        = true;               // LOCKED: HTF confirmation is mandatory in TI methodology
      cfg.Ind_MTF_Weight         = 1;                  // LOCKED: one vote; weighting is informational only in VOTE_MODE_ALL
      cfg.MTF_TF1                = GetAutoHTF_TF2();   // LOCKED: auto "2 TFs higher" rule (M15→H4, H1→D1); hardcoding a fixed TF would break multi-symbol/multi-TF usage
      cfg.MTF_TF2                = PERIOD_CURRENT;     // LOCKED: single-TF HTF mode; second slot disabled (PERIOD_CURRENT = off)
      cfg.MTF_EMA_Fast           = Inp_TI_MTF_EMA_Fast;   // default 50 — institutional standard
      cfg.MTF_EMA_Slow           = Inp_TI_MTF_EMA_Slow;   // default 200 — institutional standard
      cfg.MTF_RequirePhase       = true;               // LOCKED: HTF phase must be trending; accepting unordered HTF is a different (lower-quality) system
      cfg.MTF_StrictAlignment    = Inp_MTF_StrictAlignment;

      // ── SPREAD: pair-adaptive from Zone 3C ─────────────────────────
      cfg.MaxSpread              = op_MaxSpread;

      // ══════════════════════════════════════════════════════════════
      // CONSERVATIVE PROFILE (always on — 5 voters)
      // ══════════════════════════════════════════════════════════════

      // PSAR — direction confirmation
      cfg.Ind_Psar_Enabled       = true;               // LOCKED: PSAR is a Conservative base voter; always on regardless of profile
      cfg.P_PsarStep             = Inp_TI_Psar_Step;
      cfg.P_PsarMax              = Inp_TI_Psar_Max;
      cfg.Vote_AllowPsarFlip     = true;               // LOCKED: flip votes are valid TI signals (PSAR switching side = momentum confirmation)
      cfg.Vote_PsarFlipDelay     = -1;                 // LOCKED: -1 = no delay; immediate flip acceptance is the TI standard

      // ADX — trend strength filter ("silny trend")
      cfg.Ind_Adx_Enabled        = true;               // LOCKED: ADX is a Conservative base voter; always on regardless of profile
      cfg.ADX_Mode               = ADX_MODE_DYNAMIC_PERCENTILE; // LOCKED: dynamic percentile mode adapts to current market regime; static threshold would miss regime shifts (e.g. low-vol crypto vs high-vol Gold)
      cfg.P_Adx                  = Inp_TI_ADX_Period;
      cfg.ADX_Percentile         = Inp_TI_ADX_Percentile;
      cfg.ADX_Lookback           = Inp_TI_ADX_Lookback;
      cfg.ADX_Threshold_Accumulation  = Inp_TI_ADX_Threshold_Accum;
      cfg.ADX_Threshold_Trending      = Inp_TI_ADX_Threshold_Trend;
      cfg.ADX_Threshold_Distribution  = Inp_TI_ADX_Threshold_Dist;

      // CandleBody — spike rejection + direction gate + close ratio
      cfg.Ind_CandleBody_Enabled = true;               // LOCKED: CandleBody is a Conservative base voter; always on
      cfg.Ind_CandleBody_Weight  = 1;                  // LOCKED: one vote in VOTE_MODE_ALL; weight is informational
      cfg.CandleBody_AvgPeriod   = Inp_TI_CandleBody_AvgPeriod;
      cfg.CandleBody_MaxMult     = Inp_TI_CandleBody_MaxMult;
      cfg.CandleBody_CheckBars   = 1;                  // LOCKED: check the last bar only; checking multiple bars would reject valid pullback entries that follow a spike
      cfg.CandleBody_RequireDirection = true;          // LOCKED: candle must close in trade direction; direction-agnostic body check would allow counter-trend entries
      cfg.CandleBody_MinCloseRatio   = (Inp_TI_Profile >= TI_FULL) ? Inp_TI_CandleBody_FullRatio : 0.0;

      // Choppiness Index — ranging market blocker
      // NOTE: Requires ChoppinessIndex.ex5 custom indicator installed in MQL5/Indicators/
      // Set to false by default; enable only if the indicator is available.
      cfg.Ind_CI_Enabled         = false;              // LOCKED off: external dependency (ChoppinessIndex.ex5 must be installed); enabling by default would crash on clean installs
      cfg.Ind_CI_Weight          = 1;                  // weight is informational only in VOTE_MODE_ALL
      cfg.CI_Period              = 14;                 // standard CI period — only relevant if Ind_CI_Enabled is manually set true
      cfg.CI_RangingThreshold    = 61.8;               // standard ranging threshold (Fibonacci level) — only relevant if CI enabled

      // ══════════════════════════════════════════════════════════════
      // Profile-derived indicator toggles:
      //   CONSERVATIVE: only the base voters above
      //   MODERATE:     + MACD, CCI, BB
      //   FULL:         + DPI, SmaConv, Fib, CandleBody 75% ratio
      // ══════════════════════════════════════════════════════════════
      bool is_moderate = (Inp_TI_Profile >= TI_MODERATE);
      bool is_full     = (Inp_TI_Profile >= TI_FULL);

      // MACD — momentum direction (Moderate+)
      cfg.Ind_Macd_Enabled       = is_moderate;
      cfg.P_MacdFast             = Inp_TI_MACD_Fast;
      cfg.P_MacdSlow             = Inp_TI_MACD_Slow;
      cfg.P_MacdSig              = Inp_TI_MACD_Signal;
      cfg.MacdVoteMode           = MACD_HISTOGRAM;     // LOCKED: histogram mode (acceleration) is the TI vote logic; zero-line or crossover modes measure different aspects and would require re-tuning the whole voter set
      cfg.MacdRequireSlope       = true;               // LOCKED: histogram must be sloping in trade direction; flat histogram = no momentum = no trade in TI
      cfg.MacdRequireDivergence  = false;              // LOCKED: divergence is not part of TI MACD voter; enabling it would filter out valid momentum entries
      cfg.MacdRequireHook        = false;              // LOCKED: hook (reversal of histogram) is not a TI entry signal
      cfg.MacdHistDecelEnabled   = false;              // LOCKED: TI uses MacdRequireSlope=true which already enforces acceleration; double-filter not needed
      cfg.MacdFreshBars          = Inp_TI_MACD_FreshBars;
      cfg.MacdSlopeMin           = Inp_TI_MACD_SlopeMin;

      // CCI — momentum zero-line confirmation (Moderate+)
      cfg.Ind_Cci_Enabled        = is_moderate;
      cfg.P_Cci                  = Inp_TI_CCI_Period;
      cfg.CciMode                = CCI_TREND_ZERO;     // LOCKED: zero-line method (>0 bull, <0 bear) is the TI standard; impulse mode (±100) would require different thresholds and re-validation

      // BB Widening — volatility expansion (Moderate+)
      cfg.Ind_Bb_Enabled         = is_moderate;
      cfg.BbMode                 = BB_WIDENING;        // LOCKED: band-widening confirms expanding volatility at entry; mean-reversion or trend-follow modes measure opposite conditions
      cfg.P_Bb                   = Inp_TI_BB_Period;
      cfg.P_BbDev                = Inp_TI_BB_Deviation;

      // ── FULL additions ────────────────────────────────────────────

      // DPI — momentum exhaustion detection (Full)
      cfg.Ind_Dpi_Enabled        = is_full;
      cfg.Ind_Dpi_Weight         = 1;                  // LOCKED: one vote in VOTE_MODE_ALL
      cfg.DpiDecelFilterEnabled  = (Inp_TI_Profile >= TI_FULL);  // decel filter only meaningful when DPI is active

      // SMA Convergence — pullback detection (Full)
      cfg.Ind_SmaConverge_Enabled = is_full;
      cfg.Ind_SmaConverge_Weight  = 1;                 // LOCKED: one vote in VOTE_MODE_ALL

      // Fibonacci retracement — pullback depth check (Full)
      cfg.Ind_Fib_Enabled        = is_full;
      cfg.Ind_Fib_Weight         = 1;                  // LOCKED: one vote in VOTE_MODE_ALL
      cfg.Fib_MinRetracement     = Inp_TI_Fib_MinRetracement;
      cfg.Fib_MaxRetracement     = Inp_TI_Fib_MaxRetracement;
      cfg.Fib_SwingLookback      = Inp_TI_Fib_SwingLookback;

      // ── DISABLED (not part of TopInvestor methodology) ─────────────
      // RSI, MFI, Stochastic, ATR, VRC, P123, Ross are all disabled.
      // TI uses PSAR+ADX+CandleBody (Conservative), MACD+CCI+BB (Moderate),
      // DPI+SmaConv+Fib (Full). These oscillators overlap in function and
      // would introduce redundant or conflicting votes. Enable via PRESET_CUSTOM
      // if you want to test them in isolation.
      cfg.Ind_Rsi_Enabled        = false;
      cfg.Ind_Mfi_Enabled        = false;
      cfg.Ind_Sto_Enabled        = false;
      cfg.Ind_Atr_Enabled        = false;
      cfg.Ind_VRC_Enabled        = false;
      cfg.Ind_P123_Enabled       = false;
      cfg.Ind_Ross_Enabled       = false;

      // ── OTHER INDICATOR DEFAULTS (safe) ────────────────────────────
      // These indicators are all DISABLED above (RSI, MFI, Sto, ATR, VRC).
      // The values below are safe structural defaults that prevent uninitialized
      // fields from causing unexpected behavior if an indicator is enabled via
      // PRESET_CUSTOM or a future profile. They are NOT active in TI.
      cfg.P_Atr                  = 14;
      cfg.ATR_VoteMinPips        = 5.0;
      cfg.ATR_VoteMaxPips        = 50.0;
      cfg.Ind_VRC_Weight         = 1;
      cfg.VRC_ATR_Period         = 14;
      cfg.VRC_Lookback           = 100;
      cfg.VRC_LowThreshold       = 33.0;
      cfg.T_Adx                  = 20.0;
      cfg.P_Mfi                  = 14;
      cfg.T_MfiOB                = 80.0;
      cfg.T_MfiOS                = 20.0;
      cfg.MfiMode                = MFI_ZONE_FILTER;
      cfg.P_Rsi                  = 14;
      cfg.T_RsiOB                = 70.0;
      cfg.T_RsiOS                = 30.0;
      cfg.RsiMode                = RSI_TREND_ABOVE_50;
      cfg.P_StoK                 = 5;
      cfg.P_StoD                 = 3;
      cfg.P_StoSlow              = 3;
      cfg.T_StoOB                = 80.0;
      cfg.T_StoOS                = 20.0;
      cfg.StoMode                = STO_CROSS_SIGNAL;

      // ── PULLBACK DETECTION GATES ──────────────────────────────────
      cfg.RequireRecoveryMomentum   = false;           // LOCKED: TI does not require a momentum candle at recovery; the layer ratio is sufficient confirmation
      cfg.Gate_Recovery.mode        = GATE_SCALE_AUTO_TF;  // LOCKED: auto TF scaling gives correct gate width across M1–D1 without manual adjustment
      cfg.Gate_Recovery.value       = 1.0;             // LOCKED: baseline multiplier of 1.0; auto-scaling handles the rest
      cfg.RRM_Lookback              = (_Period <= PERIOD_M5) ? 10 : 12;  // LOCKED: auto-scaled by TF — shorter TFs use fewer bars to stay responsive
      cfg.Gate_EmaDiv.mode          = GATE_SCALE_AUTO_TF;  // LOCKED: same auto-scaling rationale as Gate_Recovery
      cfg.Gate_EmaDiv.value         = 1.0;             // LOCKED: baseline multiplier
      cfg.Gate_CandleDirection.mode  = GATE_SCALE_FIXED;   // LOCKED: candle direction gate uses a fixed dimensionless ratio, not a pip/ATR value
      cfg.Gate_CandleDirection.value = 1.0;            // LOCKED: ratio of 1.0 = candle must close fully in trade direction

      // ── VOTE EVALUATION ───────────────────────────────────────────
      cfg.Vote_EvalShift            = 1;               // LOCKED: evaluate on the previous closed bar (shift=1); shift=0 would evaluate on the forming bar — unreliable and repaints

      // ── RISK MANAGEMENT ───────────────────────────────────────────
      cfg.CountBEasZeroRisk         = true;            // LOCKED: once at BE, position is considered risk-free — correct accounting for TI's BE-first trail logic
      cfg.FixedLotSize              = 0.0;             // LOCKED: 0 = use risk-% sizing; fixed lot would override adaptive risk management

      // ── EXIT STRATEGY ─────────────────────────────────────────────
      cfg.ExitProfile               = EXIT_PROFILE_RRM;   // LOCKED: RRM exit engine (swing SL + PSAR trail); not a user tunable — changing it selects a fundamentally different exit architecture
      cfg.SLMode                    = Inp_TI_SLMode;
      // SwingLookback scaled by instrument: Gold/indices have wider swings
      // Forex M5: 20 bars. Gold M5: 40 bars. Indices M5: 35 bars.
      double swing_mult = MathSqrt(GetInstrumentFanMultiplier());
      cfg.SwingLookback             = (int)MathRound(20.0 * MathMax(1.0, swing_mult / 2.0));  // LOCKED: instrument-adaptive auto-calc; hardcoding would over-tighten SL on Gold/indices
      cfg.SL_SwingPipsCushion       = GetRecommendedInitialSlCushionPips();   // LOCKED: auto cushion per instrument/TF; hardcoding would be wrong for multi-symbol use
      cfg.SL_PsarPipsCushion        = GetRecommendedInitialSlCushionPips();   // LOCKED: same
      cfg.SL_MinPips                = GetRecommendedInitialSlCushionPips();  // Instrument-aware minimum SL floor
      cfg.SL_WidenToMinimum         = true;
      cfg.SL_AtrPeriod              = Inp_TI_SL_AtrPeriod;    // Used when SLMode = SL_MODE_ATR
      cfg.SL_AtrMult                = Inp_TI_SL_AtrMult;      // Used when SLMode = SL_MODE_ATR
      cfg.FixedTPPips               = 40.0;            // fallback only — unused when TPMode=TP_MODE_RR
      cfg.SLPercent                 = 0.5;             // fallback only — unused when SLMode=SL_MODE_SWING

      // Trail: EMA(Ema1) is the TopInvestor exit, PSAR is fallback
      cfg.TrailMode                 = Inp_TI_TrailMode;
      cfg.TrailEMA_Period           = Inp_TI_Ema1;    // always follows fast EMA — cannot be different from the ribbon's EMA1
      cfg.TrailEMA_Shift            = Inp_TI_TrailEMA_Shift;
      cfg.PSAR_TrailCushionMode     = PSAR_CUSHION_PIPS;   // LOCKED: pip-based PSAR cushion is the TI standard; ATR mode requires separate ATR calibration per instrument
      cfg.PSAR_TrailPipsCushion     = GetRecommendedTrailPsarCushionPips();   // LOCKED: auto per instrument/TF

      // TP: R:R based
      cfg.TPMode                    = Inp_TI_TPMode;
      cfg.TP_Enabled                = true;            // LOCKED: TP must be enabled for RR-based sizing to work correctly
      cfg.RRRatio                   = Inp_TI_RRRatio;

      // BE: move to breakeven at N×R profit
      cfg.BE_Mode                   = Inp_TI_BE_Mode;
      cfg.RRM_BE_RMultiple          = Inp_TI_BE_RMultiple;
      cfg.RRM_BE_BufferPips         = GetTFBasedCushion(_Period);   // LOCKED: TF-adaptive buffer; hardcoding would be wrong across M1–D1
      cfg.BEThresholdPips           = 0.0;             // LOCKED: 0 = use R-multiple threshold (set by BE_Mode); a fixed pip threshold would conflict with RR-based logic

      // Trail trigger
      ENUM_TIMEFRAMES tfTI          = (ENUM_TIMEFRAMES)_Period;
      cfg.TrailTrigger              = Inp_TI_TrailTrigger;
      cfg.TrailDistancePips         = GetTFBasedCushion(tfTI);      // LOCKED: TF-adaptive; used as minimum trail distance before locking profit
      cfg.TrailLockProfit           = true;            // LOCKED: always lock profit once trail is active — core of TI capital preservation
      cfg.TrailProfitPercent        = Inp_TI_TrailProfitPercent;
      cfg.TrailStepPips             = Inp_TI_TrailStepPips;

      // Fractal defaults — used only when SLMode/TPMode=FRACTAL (not TI default)
      cfg.FractalPeriod             = 5;               // LOCKED: standard Bill Williams fractal period; not used in default TI exit (swing SL + RR TP)
      cfg.TPFractalOffset           = 1;               // LOCKED: offset of 1 bar from fractal; not used in default TI exit

      // ── SLOPE CALCULATION ─────────────────────────────────────────
      cfg.SlopeLookbackBars         = 1;               // LOCKED: single-bar slope (bar[0] vs bar[1]); multi-bar slope would smooth out the signal and lag entry timing
      cfg.ma_h_shift                = 0;               // LOCKED: horizontal shift = 0; non-zero shifts the EMA display only, not the signal logic
      cfg.ma_v_shift                = 1;               // LOCKED: vertical shift = 1 bar back for slope calculation reference

      // ── DRAWDOWN PROTECTION ───────────────────────────────────────
      cfg.RRM_EnableDrawdownProtection = Inp_TI_EnableDDProtection;
      cfg.RRM_MaxConsecutiveLosses  = Inp_TI_MaxConsecutiveLosses;
      cfg.RRM_MaxTradesPerDay       = Inp_TI_MaxTradesPerDay;
      cfg.RRM_MaxDailyDrawdownPct   = Inp_TI_MaxDailyDrawdownPct;

      // ── EMA FAN OVEREXTENSION FILTER ──────────────────────────────
      // With EMA 9/50/89/200 the fan is naturally wider than 5/13/34/89
      // Base values are for FX; GetInstrumentFanMultiplier() scales for Gold/indices/oil/crypto
      cfg.EmaFanFilterEnabled       = Inp_TI_EmaFanFilterEnabled;
      double ti_fan_base            = (_Period <= PERIOD_M5)  ? Inp_TI_EmaFanBase_M1M5
                                    : (_Period <= PERIOD_M30) ? Inp_TI_EmaFanBase_M6M30
                                    : (_Period <= PERIOD_H1)  ? Inp_TI_EmaFanBase_H1
                                    : (_Period <= PERIOD_H4)  ? Inp_TI_EmaFanBase_H2H4
                                    :                           Inp_TI_EmaFanBase_H4Plus;
      cfg.EmaFanMaxTotalPips        = ti_fan_base * GetEmaFanMultiplier();
      cfg.EmaFanMaxPct              = 0.0;  // Pip mode by default; user can override
      PrintFormat("📐 [TOPINVESTOR] EMA Fan threshold: %.1f pips (base=%.1f × multiplier)",
                  cfg.EmaFanMaxTotalPips, ti_fan_base);
      PrintFormat("📐 [TOPINVESTOR] SL: SWING lookback=%d | cushion=%.1f pips | BE buffer=%.1f pips",
                  cfg.SwingLookback, cfg.SL_SwingPipsCushion, cfg.RRM_BE_BufferPips);

      // ── DPI DECELERATION FILTER ────────────────────────────────────
      cfg.DpiDecelFilterEnabled     = (Inp_TI_Profile >= TI_FULL);

      // ── RE-ENTRY / COOLDOWN ───────────────────────────────────────
      cfg.AllowReEntryAfterBE       = true;            // LOCKED: TI allows re-entry after BE — if the trend continues, a new pullback is a valid signal
      cfg.ReEntryLotScalePct        = MathMax(0, MathMin(100, Inp_TI_ReEntryLotScalePct));   // 0=full size; 50=half-size re-entry
      cfg.MinBarsAfterClose         = MathMax(0, Inp_TI_MinBarsAfterClose);

      // ── VPRR: Volume Pullback-Recovery Ratio ──────────────────────────
      if(Inp_TI_VPRR_AutoEnable)
      {
         ST_VPRRAutoMode vprr_auto = GetVPRRRecommendedMode(
            Inp_VPRR_MinRatio_Gold,      Inp_VPRR_MinRatio_Silver,
            Inp_VPRR_MinRatio_IndicesUS, Inp_VPRR_MinRatio_IndicesEU,
            Inp_VPRR_MinRatio_Oil,       Inp_VPRR_MinRatio_Crypto,
            Inp_VPRR_MinRatio_Equities,  Inp_VPRR_MinRatio_FX,
            Inp_VPRR_MinRatio_NonFXTick,
            Inp_VPRR_RecBars_Gold,       Inp_VPRR_RecBars_Silver,
            Inp_VPRR_RecBars_IndicesUS,  Inp_VPRR_RecBars_IndicesEU,
            Inp_VPRR_RecBars_Oil,        Inp_VPRR_RecBars_Crypto,
            Inp_VPRR_RecBars_Equities,   Inp_VPRR_RecBars_FX,
            Inp_VPRR_TF_Mult_M5,         Inp_VPRR_TF_Mult_M15,
            Inp_VPRR_TF_Mult_H1,         Inp_VPRR_TF_Mult_H4Plus,
            Inp_VPRR_TF_ReduceRecBars,   Inp_TI_VPRR_RecoveryBars
         );
         cfg.VPRR_Enabled         = vprr_auto.enabled;
         cfg.VPRR_VolumeType      = vprr_auto.volume_type;
         cfg.VPRR_MinRatio        = vprr_auto.min_ratio;
         cfg.VPRR_RecoveryBars    = MathMax(1, MathMin(10, vprr_auto.recovery_bars));
      }
      else
      {
         cfg.VPRR_Enabled         = Inp_TI_VPRR_Enabled;
         cfg.VPRR_VolumeType      = (int)Inp_TI_VPRR_VolumeType;
         cfg.VPRR_MinRatio        = MathMax(0.1, Inp_VPRR_MinRatio_FX);
         cfg.VPRR_RecoveryBars    = MathMax(1, MathMin(10, Inp_TI_VPRR_RecoveryBars));
      }
      cfg.VPRR_MinRecoveryBars = MathMax(1, cfg.VPRR_RecoveryBars - 1);
      cfg.VPRR_Weight          = MathMax(1, Inp_TI_VPRR_Weight);
      PrintVPRRSummary(cfg, "TOPINVESTOR");

      cfg.MaxSpreadRetryBars        = 3;               // LOCKED: retry blocked entries for up to 3 bars; longer retry risks entering on a stale signal

      // ── POLICY A: RESTORE OPERATOR-CONTROLLED GATES ───────────────
      cfg.UseSpread                 = op_UseSpread;
      cfg.UseTime                   = op_UseTime;
      cfg.StartHr                   = op_StartHr;
      cfg.EndHr                     = op_EndHr;
      cfg.UseNews                   = op_UseNews;
      cfg.NewsPre                   = op_NewsPre;
      cfg.NewsPost                  = op_NewsPost;
      cfg.RiskPercent               = op_RiskPercent;
      cfg.MaxOpenTrades             = op_MaxOpenTrades;
      cfg.MaxTotalRisk              = op_MaxTotalRisk;
      cfg.MinMarginLevel            = op_MinMarginLevel;
      cfg.EmergencyMarginLevel      = op_EmergencyMarginLevel;

      return;
   }

   //+------------------------------------------------------------------+
   // PURPOSE:
   //   Sandbox environment for testing individual indicators, voting
   //   combinations, and strategy components in isolation.
   //
   // WHAT'S CONFIGURED:
   //   - Basic 2EMA bias structure (EMA34 vs EMA89)
   //   - Simple fixed-pip SL/TP
   //   - All indicators DISABLED by default
   //   - No phase detection, no layer detection
   //
   // WHAT YOU MUST CONFIGURE (via inputs):
   //   - Enable specific indicators to test (Inp_CUSTOM_Ind_Macd_Enabled, etc.)
   //   - AutoStrat mode (STRAT_2EMA_POSITION vs STRAT_2EMA_CROSS_PRICE)
   //   - BarClose_Mode and target EMA
   //   - SL/TP distances
   //   - Voting thresholds
   //
   // NOT FOR:
   //   - Production trading (use PRESET_RRM)
   //   - Benchmarking (use PRESET_MA)
   //   - Strategy optimization (incomplete configuration)
   //
   // EXPECTED WORKFLOW:
   //   1. Select PRESET_TEST
   //   2. Enable 1-2 indicators via inputs
   //   3. Run backtest to see their impact
   //   4. Iterate: add more indicators, adjust settings
   //+------------------------------------------------------------------+
   
   if(preset == PRESET_TEST)
   {
      // ================================================================
      // PRESET_TEST: EA System Testing Mode
#endif // SEA_PRESET_TOPINVESTOR

      // ================================================================
      //
      // FORMULA:
      //   TS = Bias × LayerX × bcX × IndicatorX × FilterX
      //
      // CONFIGURATION:
      //   Bias = BIAS_2EMA (simple position + slope)
      //   LayerX = DISABLED (returns 1)
      //   bcX = Fixed EMA1 check
      //   IndicatorX = MACD, CCI, PSAR, CandleBody
      //   FilterX = User-controlled
      //
      // ================================================================
   
      Print("═══════════════════════════════════════════════════════════");
      Print("  PRESET: TEST (EA System Testing Mode)");
      Print("═══════════════════════════════════════════════════════════");
   
      // ================================================================
      // CORE STRATEGY SETTINGS
      // ================================================================
      cfg.CloseOnReverse            = false;
      cfg.BiasEnabled               = true;           // true
      cfg.BiasMode                  = BIAS_2EMA;
      cfg.AutoStrat                 = STRAT_2EMA_POSITION;  // ✅ Compatible with BIAS_2EMA
      cfg.BiasFastID                = (int)ROLE_EMA2;
      cfg.BiasSlowID                = (int)ROLE_EMA4;
      cfg.MaType                    = METHOD_EMA;
      cfg.RequirePriceCross         = false;
      cfg.MABenchmarkStrict         = false;
      cfg.UseMACompatSizer          = false;
      
      // ================================================================
      // INDICATOR VOTING CONFIGURATION (Alphabetical)
      // Multiple indicators enabled for comprehensive EA testing
      // Admin can disable/enable as needed via individual inputs
      // ================================================================
      cfg.Ind_Adx_Enabled           = false;
      cfg.Ind_Atr_Enabled           = false;
      cfg.Ind_Bb_Enabled            = false;
      cfg.Ind_CandleBody_Enabled    = true;           // true
      cfg.Ind_CI_Enabled            = false;
      cfg.Ind_VRC_Enabled           = false;
      cfg.Ind_Cci_Enabled           = true;           // true
      cfg.Ind_Macd_Enabled          = true;           // true
      cfg.Ind_Mfi_Enabled           = false;
      cfg.Ind_P123_Enabled          = false;
      cfg.Ind_Psar_Enabled          = true;           // true
      cfg.Ind_Ross_Enabled          = false;
      cfg.Ind_Rsi_Enabled           = false;
      cfg.Ind_Sto_Enabled           = false;
      cfg.Ind_SmaConverge_Enabled   = false;
      cfg.Ind_SmaConverge_Weight    = 1;
      cfg.Ind_Dpi_Enabled           = false;
      cfg.Ind_Dpi_Weight            = 1;
      cfg.Ind_MTF_Enabled           = false;   // MTF disabled: test preset uses fixed indicator set
   
      // BAR CLOSE (bcX) CONFIGURATION
      cfg.BarClose_Enabled          = true;           // true
      cfg.BarClose_Mode             = BC_BIAS_FAST;   // Fast
      cfg.BarClose_DefaultEMA       = ROLE_EMA1;      // Close vs EMA1
   
      cfg.VoteMode = VOTE_MODE_ALL;
      
      // ================================================================
      // INDICATOR PERIODS & THRESHOLDS (Alphabetical)
      // ================================================================
      
      // ADX (Average Directional Index)
      cfg.ADX_Mode                  = ADX_MODE_STATIC;
      cfg.P_Adx                     = 14;
      cfg.T_Adx                     = 20.0;
      cfg.ADX_Percentile            = 50.0;
      cfg.ADX_Lookback              = 100;
      cfg.ADX_Threshold_Accumulation   = 12.0;
      cfg.ADX_Threshold_Trending       = 25.0;
      cfg.ADX_Threshold_Distribution   = 18.0;
      
      // ATR (Average True Range) - Voting Indicator Only
      cfg.P_Atr                     = 14;
      cfg.ATR_VoteMinPips           = 5.0;
      cfg.ATR_VoteMaxPips           = 50.0;
      
      // Bollinger Bands
      // - BbMode options:
      //  - BB_TREND_FOLLOW (trade with breakouts)
      //  - BB_MEAN_REVERT (trade bounces)
      //  - BB_SQUEEZE_BREAKOUT (detect low volatility consolidation)
      cfg.BbMode                    = BB_TREND_FOLLOW;
      cfg.P_Bb                      = 20;
      cfg.P_BbDev                   = 2.0;
      
      // Candle Body
      cfg.CandleBody_AvgPeriod      = 5;      // ORG: 10     5
      cfg.CandleBody_MaxMult        = 3.0;    // ORG:  3.0   3.0
      cfg.CandleBody_CheckBars      = 3;      // ORG:  1     3
      cfg.CandleBody_RequireDirection = true;
      cfg.Ind_CandleBody_Weight     = 1;      // ORG:  1

      // Choppiness Index
      cfg.CI_Period                 = 14;
      cfg.CI_RangingThreshold       = 61.8;
      cfg.Ind_CI_Weight             = 1;
      
      // VRC (Volatility Regime Classifier)
      cfg.VRC_ATR_Period            = 14;
      cfg.VRC_Lookback              = 100;
      cfg.VRC_LowThreshold          = 33.0;
      cfg.Ind_VRC_Weight            = 1;
      
      // CCI (Commodity Channel Index)
      cfg.CciMode                   = CCI_TREND_ZERO;
      cfg.P_Cci                     = 13;          // ORG: 14
      
      // EMA (Periods)
      cfg.P_Ema1                    = 5;           // ORG:  5
      cfg.P_Ema2                    = 13;          // ORG: 13
      cfg.P_Ema3                    = 34;          // ORG: 34
      cfg.P_Ema4                    = 89;          // ORG: 89
   
      // MACD (Moving Average Convergence Divergence)
      cfg.MacdVoteMode              = MACD_ZERO_AND_HIST;
      cfg.P_MacdFast                = 8;           // ORG: 12  8   5  5
      cfg.P_MacdSlow                = 13;          // ORG: 26  13  8  8
      cfg.P_MacdSig                 = 5;           // ORG: 9   8   5  3
      cfg.MacdRequireSlope          = true;        // ORG: false
      cfg.MacdRequireDivergence     = false;       // ORG: false
      cfg.MacdRequireHook           = false;       // ORG: false
      cfg.MacdFreshBars             = 10;          // ORG: 3
      cfg.MacdSlopeMin              = 0.000001;    // ORG: 0.00001
   
      // MFI (Money Flow Index)
      cfg.MfiMode                   = MFI_ZONE_FILTER;
      cfg.P_Mfi                     = 14;
      cfg.T_MfiOB                   = 80.0;
      cfg.T_MfiOS                   = 20.0;
      
      // PSAR (Parabolic SAR)
      cfg.Vote_AllowPsarFlip        = true;        // true
      cfg.P_PsarStep                = 0.05;
      cfg.P_PsarMax                 = 0.5;
      cfg.Vote_PsarFlipDelay        = -1;          // -1=Flip+Dot, 0=Flip only, 1,2,..=Flip+N only
   
      // RSI (Relative Strength Index)
      cfg.RsiMode                   = RSI_TREND_ABOVE_50;
      cfg.P_Rsi                     = 14;
      cfg.T_RsiOB                   = 70.0;
      cfg.T_RsiOS                   = 30.0;
      
      // Stochastic Oscillator
      cfg.StoMode                   = STO_CROSS_SIGNAL;
      cfg.P_StoK                    = 5;
      cfg.P_StoD                    = 3;
      cfg.P_StoSlow                 = 3;
      cfg.T_StoOB                   = 80.0;
      cfg.T_StoOS                   = 20.0;
      
      // ================================================================
      // PHASE DETECTION & LAYER FILTERING (All disabled for testing)
      // ================================================================
      cfg.PhaseDetectionEnabled        = false;
      cfg.EnableLayerDetection         = false;
      cfg.BlockUnorderedPhase          = false;
      cfg.BlockEmergingPhase           = false;
      cfg.RequireMinPhaseConfirm       = false;
      cfg.MinPhaseConfirmBars          = 0;
      
      // Layer permissions per phase
      cfg.Trending_AllowWeakTrades     = false;
      cfg.Emerging_AllowWeakTrades     = false;
      cfg.Trending_AllowMediumTrades   = false;
      cfg.Emerging_AllowMediumTrades   = false;
      cfg.Trending_AllowStrongTrades   = false;
      cfg.Emerging_AllowStrongTrades   = false;
      
      // ================================================================
      // PULLBACK DETECTION GATES (All disabled)
      // ================================================================
      cfg.RequireRecoveryMomentum      = false;   // ORG: false
   
      // Gate 2: Recovery momentum
      cfg.Gate_Recovery.mode           = GATE_SCALE_FIXED;
      cfg.Gate_Recovery.value          = 0.0;
      cfg.RRM_Lookback                 = 0;
      
      // Gate 3: EMA divergence
      cfg.Gate_EmaDiv.mode             = GATE_SCALE_FIXED;
      cfg.Gate_EmaDiv.value            = 0.0;
      
      // Gate 4: Candle direction
      cfg.Gate_CandleDirection.mode    = GATE_SCALE_FIXED;
      cfg.Gate_CandleDirection.value   = 0.0;
      
      // ================================================================
      // VOTE EVALUATION SETTINGS
      // ================================================================
      cfg.Vote_EvalShift               = 1;
      
      // ================================================================
      // RISK MANAGEMENT (Portfolio-level)
      // ================================================================
      cfg.CountBEasZeroRisk            = true;     // ORG: false
      cfg.RiskPercent                  = 2.0;      // ORG: 2.0
      cfg.FixedLotSize                 = 0.0;
      cfg.MaxTotalRisk                 = 6.0;
      cfg.MaxOpenTrades                = 3;
      
      // ================================================================
      // EXIT STRATEGY CONFIGURATION
      // ================================================================
      if(op_ExitProfile == EXIT_PROFILE_NONE)
      {
         cfg.ExitProfile = EXIT_PROFILE_SIMPLE;
         // ════════════════════════════════════════════════════════════
         // TF-ADAPTIVE VALUE CALCULATION
         // ════════════════════════════════════════════════════════════
         ENUM_TIMEFRAMES tf = (ENUM_TIMEFRAMES)_Period;
         
         // ────────────────────────────────────────────────────────────
         // CUSHIONS: Extra buffer around market-determined levels
         // Used by: SL_MODE_PSAR_DOT, SL_MODE_SWING, TRAIL_PSAR
         // ────────────────────────────────────────────────────────────
         double sl_cushion    = GetRecommendedInitialSlCushionPips();   // M1=2p, H4=10p, D1=25p (JPY-adjusted)
         double trail_cushion = GetRecommendedTrailPsarCushionPips();   // M1=1p, H4=5p, D1=15p (JPY-adjusted)
         double be_cushion    = GetTFBasedCushion(tf);                  // M1=3p, H4=15p, D1=25p


         // ────────────────────────────────────────────────────────────
         // SWING LOOKBACK: Continuous bounding for ALL MT5 Timeframes
         // ────────────────────────────────────────────────────────────
         int swing_lookback = 20; // Default
         
         if      (tf <= PERIOD_M1)  swing_lookback = 10;
         else if (tf <= PERIOD_M5)  swing_lookback = 15;
         else if (tf <= PERIOD_M30) swing_lookback = 15;
         else if (tf <= PERIOD_H1)  swing_lookback = 20;
         else if (tf <= PERIOD_H4)  swing_lookback = 20;
         else                       swing_lookback = 30; // D1, W1, MN1

         // ────────────────────────────────────────────────────────────
         // FIXED TP DISTANCE: JPY-Aware and MT5 TF-Aware
         // ────────────────────────────────────────────────────────────
         double fixed_tp_pips = 40.0; // Default
         bool isJPY = (StringFind(_Symbol, "JPY") >= 0);
         
         if      (tf <= PERIOD_M1)  fixed_tp_pips = isJPY ? 15.0 : 10.0;
         else if (tf <= PERIOD_M5)  fixed_tp_pips = isJPY ? 20.0 : 15.0;
         else if (tf <= PERIOD_M30) fixed_tp_pips = isJPY ? 30.0 : 20.0;
         else if (tf <= PERIOD_H1)  fixed_tp_pips = isJPY ? 45.0 : 30.0;
         else if (tf <= PERIOD_H4)  fixed_tp_pips = isJPY ? 60.0 : 40.0;
         else                       fixed_tp_pips = isJPY ? 120.0: 80.0; // D1+


         // ════════════════════════════════════════════════════════════
         // APPLY EXIT MANAGEMENT VALUES
         // ════════════════════════════════════════════════════════════

         // ────────────────────────────────────────────────────────────
         // CORE SETTINGS
         // ────────────────────────────────────────────────────────────
         cfg.SwingLookback          = swing_lookback;  // TF-adaptive (M1=10 bars, D1=30 bars)
         cfg.RRRatio                = 2.0;             // Risk:Reward = 2:1 (risk 50p to win 100p)

         // ────────────────────────────────────────────────────────────
         // TAKE PROFIT
         // ────────────────────────────────────────────────────────────
         cfg.TP_Enabled             = true;
         cfg.TPMode                 = TP_MODE_RR;      // Use R:R ratio (dynamic TP)
         cfg.FixedTPPips            = fixed_tp_pips;   // TF-adaptive (M1=10p, H4=40p, D1=80p)
         cfg.TPFractalOffset        = 1;               // Fractal offset (if using TP_MODE_FRACTAL)
         cfg.FractalPeriod          = 5;               // Fractal period (if using TP_MODE_FRACTAL)

         // ────────────────────────────────────────────────────────────
         // BREAKEVEN
         // ────────────────────────────────────────────────────────────
         cfg.BE_Mode                = BE_MODE_R_MULTIPLE;
         cfg.RRM_BE_BufferPips      = be_cushion * 1; // ORG: * 0.5: TF-adaptive, tighter (H4=7.5p vs old 15p)
         cfg.RRM_BE_ProgressPct     = 5.0;            // Trigger at 10% progress toward TP
         cfg.BEThresholdPips        = 0.0;            // Not used (ProgressPct mode)

         // ────────────────────────────────────────────────────────────
         // TRAILING STOP
         // ────────────────────────────────────────────────────────────
         cfg.TrailMode              = TRAIL_PSAR;
         cfg.TrailTrigger           = TRIGGER_IMMEDIATE; // Start checking immediately
         cfg.RRM_TrailStartsAfterBE = false;          // ✅ Only trail after BE hit (safer!)
         cfg.TrailLockProfit        = true;           // Never trail SL below entry
         cfg.TrailDistancePips      = 5.0;            // Not used (PSAR mode = dynamic)
         cfg.TrailProfitPercent     = 5.0;            // Not used (PSAR mode)
         cfg.TrailStepPips          = 0.0;            // Not used (PSAR mode)

         // ────────────────────────────────────────────────────────────
         // STOP LOSS
         // ────────────────────────────────────────────────────────────
         cfg.SLMode                 = SL_MODE_PSAR_DOT;
         cfg.SL_SwingPipsCushion    = sl_cushion;     // TF+JPY adaptive (M1=2p, H4=10p)
         cfg.SL_PsarPipsCushion     = sl_cushion;     // TF+JPY adaptive (M1=2p, H4=10p)
         cfg.SLPercent              = 0.5;            // Not used (not using SL_MODE_PERCENT)

         // ────────────────────────────────────────────────────────────
         // PSAR TRAILING CONFIGURATION
         // ────────────────────────────────────────────────────────────
         cfg.PSAR_TrailCushionMode  = PSAR_CUSHION_PIPS;
         cfg.PSAR_TrailPipsCushion  = trail_cushion;   // TF+JPY adaptive (M1=1p, H4=5p, D1=15p)
      }
      
      // ================================================================
      // MA-SPECIFIC SETTINGS
      // ================================================================
      cfg.ma_h_shift                = 0;
      cfg.ma_v_shift                = 0;
      
      // ================================================================
      // RRM DRAWDOWN PROTECTION (Enabled for testing safety)
      // ================================================================
      cfg.RRM_EnableDrawdownProtection = true;  // ✅ Enabled
      cfg.RRM_MaxConsecutiveLosses  = 5;        // ✅ 3: Stop after 3 losses
      cfg.RRM_MaxTradesPerDay       = 12;       // ✅ 12: Limit overtrading
      cfg.RRM_MaxDailyDrawdownPct   = 6.0;      // ✅ 6: Stop if -6% day

      // ================================================================
      // SLOPE CALCULATION SETTINGS (Minimal - Testing Mode)
      // ================================================================
      cfg.SlopeLookbackBars         = 1;        // Single bar (fast)

      // ════════════════════════════════════════════════════════════════
      // BAR CLOSE (bcX) CONFIGURATION
      // Formula: TS = Bias × LayerX × bcX × IndicatorX × FilterX
      // CONFIGURATION: Fixed EMA1 check (not layer-aware for simpler testing)
      // ════════════════════════════════════════════════════════════════
      cfg.BarClose_Mode             = BC_BIAS_FAST;   // Always check vs fixed EMA
      cfg.BarClose_DefaultEMA       = ROLE_EMA1;      // Close vs EMA1
      cfg.BarClose_Enabled          = true;           // ✅ Enable bcX
      
      // ================================================================
      // POLICY A: RESTORE OPERATOR-CONTROLLED GATES
      // ================================================================
      cfg.MaxSpread                 = op_MaxSpread;
      cfg.UseSpread                 = op_UseSpread;
      cfg.UseTime                   = op_UseTime;
      cfg.StartHr                   = op_StartHr;
      cfg.EndHr                     = op_EndHr;
      cfg.UseNews                   = op_UseNews;
      cfg.NewsPre                   = op_NewsPre;
      cfg.NewsPost                  = op_NewsPost;
      cfg.RiskPercent               = op_RiskPercent;    // Policy A: restore user risk tolerance
      cfg.MaxOpenTrades             = op_MaxOpenTrades;  // Policy A: restore user position limit
      cfg.MaxTotalRisk              = op_MaxTotalRisk;   // Policy A: restore user portfolio risk cap
      cfg.MinMarginLevel            = op_MinMarginLevel; // Policy A: restore entry margin guard
      cfg.EmergencyMarginLevel      = op_EmergencyMarginLevel; // Policy A: restore emergency margin guard

      return;
   }

}

//+------------------------------------------------------------------+
//| END OF FILE                                                      |
//+------------------------------------------------------------------+
