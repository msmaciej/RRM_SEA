//+------------------------------------------------------------------+
//|                                               SEA_BarClose.mqh   |
//|                              MJS Institutional Trading Solutions |
//|                                                                  |
//| Purpose: Bar Close Confirmation (bcX) component                  |
//|   Checks candle close position vs target EMA.                   |
//|   Separate from LayerX (which checks position+slope only).      |
//|                                                                  |
//| Formula: TS = Bias × LayerX × bcX × IndicatorX × FilterX       |
//|                                                                  |
//| MODES:                                                           |
//|   BC_DISABLED:    Always returns 1 (bcX disabled)               |
//|   BC_FIXED_EMA:   Check close vs BarClose_DefaultEMA            |
//|   BC_LAYER_AWARE: Layer-aware check (bcW/bcM/bcS)               |
//|     • LayerW (LAYER_1_WEAK)   → bcW: Close beyond EMA1          |
//|     • LayerM (LAYER_2_MEDIUM) → bcM: Close beyond EMA2          |
//|     • LayerS (LAYER_3_STRONG) → bcS: Close beyond EMA3          |
//|   BC_BIAS_FAST:   Check close vs BiasFastID EMA                 |
//+------------------------------------------------------------------+
#property strict

#include <RRMS\SEA_Config.mqh>

//+------------------------------------------------------------------+
//| Check_BarClose: Bar close confirmation (bcX)                     |
//|                                                                  |
//| Parameters:                                                      |
//|   v_shift     : Bar shift (1 = last closed bar)                 |
//|   bias        : 1=LONG, -1=SHORT                                |
//|   active_layer: Active layer ID (LAYER_1_WEAK/MEDIUM/STRONG)    |
//|   ema1..ema4  : EMA values at v_shift                           |
//|   close_price : Close price at v_shift                          |
//|                                                                  |
//| Returns: 1 (pass/skip), 0 (fail)                                |
//+------------------------------------------------------------------+
int Check_BarClose(int v_shift, int bias, int active_layer,
                   double ema1, double ema2, double ema3, double ema4,
                   double close_price)
{
   // Check if bcX is enabled
   if(!Settings.BarClose_Enabled || Settings.BarClose_Mode == BC_DISABLED)
   {
      if(Settings.DebugFlow)
         Print("[bcX] DISABLED → PASS (returns 1)");
      return 1;
   }

   // Determine which EMA to check against
   double check_ema = 0.0;
   string bc_label  = "bc";
   string ema_name  = "";

   if(Settings.BarClose_Mode == BC_LAYER_AWARE)
   {
      // Layer-aware: use fast EMA of the active layer (bcW/bcM/bcS)
      switch(active_layer)
      {
         case LAYER_1_WEAK:
            check_ema = ema1; bc_label = "bcW"; ema_name = "EMA1";
            break;
         case LAYER_2_MEDIUM:
            check_ema = ema2; bc_label = "bcM"; ema_name = "EMA2";
            break;
         case LAYER_3_STRONG:
            check_ema = ema3; bc_label = "bcS"; ema_name = "EMA3";
            break;
         default:
            // LAYER_NONE or unknown: fall back to EMA1
            check_ema = ema1; bc_label = "bc"; ema_name = "EMA1";
            break;
      }
   }
   else if(Settings.BarClose_Mode == BC_BIAS_FAST)
   {
      // Use the BiasFastID EMA
      switch(Settings.BiasFastID)
      {
         case (int)ROLE_EMA1: check_ema = ema1; ema_name = "EMA1"; break;
         case (int)ROLE_EMA2: check_ema = ema2; ema_name = "EMA2"; break;
         case (int)ROLE_EMA3: check_ema = ema3; ema_name = "EMA3"; break;
         case (int)ROLE_EMA4: check_ema = ema4; ema_name = "EMA4"; break;
         default:             check_ema = ema1; ema_name = "EMA1"; break;
      }
      bc_label = "bc";
   }
   else  // BC_FIXED_EMA (default)
   {
      // Always check vs BarClose_DefaultEMA
      switch(Settings.BarClose_DefaultEMA)
      {
         case ROLE_EMA1: check_ema = ema1; ema_name = "EMA1"; break;
         case ROLE_EMA2: check_ema = ema2; ema_name = "EMA2"; break;
         case ROLE_EMA3: check_ema = ema3; ema_name = "EMA3"; break;
         case ROLE_EMA4: check_ema = ema4; ema_name = "EMA4"; break;
         default:        check_ema = ema1; ema_name = "EMA1"; break;
      }
      bc_label = "bc";
   }

   // Evaluate close position vs target EMA
   bool passed = false;
   if(bias == 1)        passed = (close_price > check_ema);   // LONG: close must be above EMA
   else if(bias == -1)  passed = (close_price < check_ema);   // SHORT: close must be below EMA

   if(Settings.DebugFlow)
   {
      if(bias == 1)
         PrintFormat("[%s] LONG: Close=%.5f vs %s=%.5f → %s",
                     bc_label, close_price, ema_name, check_ema,
                     passed ? "PASS (Close > EMA)" : "FAIL (Close <= EMA)");
      else if(bias == -1)
         PrintFormat("[%s] SHORT: Close=%.5f vs %s=%.5f → %s",
                     bc_label, close_price, ema_name, check_ema,
                     passed ? "PASS (Close < EMA)" : "FAIL (Close >= EMA)");
   }

   return passed ? 1 : 0;
}
