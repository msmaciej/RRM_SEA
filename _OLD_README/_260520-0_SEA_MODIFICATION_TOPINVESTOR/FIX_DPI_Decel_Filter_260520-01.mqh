// ═══════════════════════════════════════════════════════════════════════
// FIX: DPI Deceleration Filter — check GREEN momentum, not raw |hist|
// 
// Problem:  Code checked |Blue−Red| shrinking bar-over-bar.
//           README specifies: block when GREEN histogram is shrinking.
//           These are different computations.
//
// GREEN = min(|Blue|, |hist|) when Blue and hist are same side of zero.
// GREEN = 0 (absent) when Blue and hist are on opposite sides.
//
// This fix requires changes in TWO locations:
//   1. ComputeDPIMainHist() — capture GREEN magnitude at shift and shift+1
//   2. Decel filter block in EvaluateTS() — use GREEN values instead of |hist|
//
// File: SEA_SignalEngine.mqh
// ═══════════════════════════════════════════════════════════════════════


// ─────────────────────────────────────────────────────────────────────
// CHANGE 1 of 2: ComputeDPIMainHist — extended signature + GREEN capture
// ─────────────────────────────────────────────────────────────────────
// 
// Replace the ENTIRE function (lines 5466–5567) with this version.
// New parameters: out_green_mag_cur, out_green_mag_prev
//
// All callers must be updated to pass the two new arguments.
// ─────────────────────────────────────────────────────────────────────

   bool ComputeDPIMainHist(int v_shift, double &out_hist_cur, double &out_hist_prev,
                           bool &out_green, bool &out_macd_agree,
                           double &out_green_mag_cur, double &out_green_mag_prev)
   {
      if(!m_settings.Ind_Dpi_Enabled) return false;

      int MFast  = m_settings.DPI_MACD_Fast;
      int MSlow  = m_settings.DPI_MACD_Slow;
      int RST    = m_settings.DPI_RedSignalType;

      // Determine Red-EMA period(s) based on signal type
      int redPer1 = 1;  // primary EMA period for Red line
      int redPer2 = 1;  // secondary EMA period (only used when RST == 5 double-smooth)
      switch(RST)
      {
         case 1: redPer1 = m_settings.DPI_RedEMA_A;           redPer2 = redPer1; break;
         case 2: redPer1 = m_settings.DPI_RedEMA_B;           redPer2 = redPer1; break;
         case 3: redPer1 = m_settings.DPI_RedEMA_C;           redPer2 = redPer1; break;
         case 4: redPer1 = m_settings.DPI_RedEMA_D;           redPer2 = redPer1; break;
         case 5: redPer1 = m_settings.DPI_DoubleSmoothFirst;  redPer2 = m_settings.DPI_DoubleSmoothSecond; break;
         default: redPer1 = m_settings.DPI_RedEMA_C;          redPer2 = redPer1; break;
      }

      // bars_needed: Slow-EMA warmup + max(Red EMA) + 1 prev-bar capture + v_shift + 5 safety
      int maxRed = MathMax(redPer1, redPer2);
      int bars_needed = MSlow + maxRed + v_shift + 7;
      if(iBars(m_symbol, PERIOD_CURRENT) <= bars_needed) return false;

      double alphaFast  = 2.0 / (double)(MFast  + 1);
      double alphaSlow  = 2.0 / (double)(MSlow  + 1);
      double alphaRed1  = 2.0 / (double)(redPer1 + 1);
      double alphaRed2  = 2.0 / (double)(redPer2 + 1);

      double ema_fast = 0.0, ema_slow = 0.0;
      double blue     = 0.0;
      double red1     = 0.0, red2 = 0.0;  // red2 only used for double-smooth
      double hist     = 0.0;

      out_hist_cur       = 0.0;
      out_hist_prev      = 0.0;
      out_green          = false;
      out_macd_agree     = false;
      out_green_mag_cur  = 0.0;
      out_green_mag_prev = 0.0;

      // Seed EMAs at the oldest bar so that initial Blue = 0 (fast = slow = seed price).
      double seed = iClose(m_symbol, PERIOD_CURRENT, bars_needed);
      ema_fast = seed;
      ema_slow = seed;
      // Blue starts at 0 → Red EMA(s) start at 0 for consistency.
      red1 = 0.0;
      red2 = 0.0;

      // ── Capture variables for GREEN at both bars ──
      double blue_prev = 0.0, hist_at_prev = 0.0;

      // Iterate from oldest bar toward v_shift (capturing hist at v_shift+1 en route).
      for(int i = bars_needed - 1; i >= v_shift; i--)
      {
         double cl = iClose(m_symbol, PERIOD_CURRENT, i);

         // Blue line = EMA(Fast, close) − EMA(Slow, close)
         ema_fast = alphaFast * cl   + (1.0 - alphaFast) * ema_fast;
         ema_slow = alphaSlow * cl   + (1.0 - alphaSlow) * ema_slow;
         blue     = ema_fast - ema_slow;

         // Red signal line
         if(RST == 5)
         {
            // Double-smooth: EMA(DoubleSmoothFirst, Blue) then EMA(DoubleSmoothSecond, that)
            red1 = alphaRed1 * blue + (1.0 - alphaRed1) * red1;
            red2 = alphaRed2 * red1 + (1.0 - alphaRed2) * red2;
            hist = blue - red2;
         }
         else
         {
            // Single EMA of Blue
            red1 = alphaRed1 * blue + (1.0 - alphaRed1) * red1;
            hist = blue - red1;
         }

         if(i == v_shift + 1)
         {
            out_hist_prev = hist;
            // ── NEW: capture blue and hist at prev bar for GREEN computation ──
            blue_prev    = blue;
            hist_at_prev = hist;
         }
      }
      out_hist_cur = hist;

      // out_green: Blue and hist on the same side of zero (momentum alignment)
      if(m_settings.DPI_UseGreenHist)
         out_green = ((blue > 0.0 && hist > 0.0) || (blue < 0.0 && hist < 0.0));
      else
         out_green = false;

      // ── NEW: GREEN magnitude at current bar (v_shift) ──
      // GREEN = min(|Blue|, |hist|) when both same side of zero, else 0.
      bool green_present_cur = ((blue > 0.0 && hist > 0.0) || (blue < 0.0 && hist < 0.0));
      if(green_present_cur)
         out_green_mag_cur = MathMin(MathAbs(blue), MathAbs(hist));
      else
         out_green_mag_cur = 0.0;

      // ── NEW: GREEN magnitude at previous bar (v_shift + 1) ──
      bool green_present_prev = ((blue_prev > 0.0 && hist_at_prev > 0.0) || (blue_prev < 0.0 && hist_at_prev < 0.0));
      if(green_present_prev)
         out_green_mag_prev = MathMin(MathAbs(blue_prev), MathAbs(hist_at_prev));
      else
         out_green_mag_prev = 0.0;

      // out_macd_agree: trend filter flag — dual-use:
      //   DPI_UseCCIReset=true  → true when hist sign agrees with CCI sign (no CCI reset warning)
      //   DPI_UseCCIReset=false → true when hist >= 0 (pass-through; caller uses for decel filter)
      if(m_settings.DPI_UseCCIReset)
      {
         // FIXED — inline CCI, bit-identical to DPI_mc_main.mq5:
         double cci_v = ComputeDPI_CCI(v_shift);
         out_macd_agree = ((hist >= 0.0 && cci_v >= 0.0) || (hist < 0.0 && cci_v < 0.0));
      }
      else
      {
         out_macd_agree = (hist >= 0.0);
      }

      return true;
   }


// ─────────────────────────────────────────────────────────────────────
// CHANGE 2 of 2: Decel filter block in EvaluateTS()
// ─────────────────────────────────────────────────────────────────────
//
// Replace lines 5805–5847 with this block.
// Now checks GREEN momentum shrinking per README spec:
//   - GREEN present on both bars AND GREEN[cur] < GREEN[prev] → block
//   - GREEN absent on current bar but was present on prev bar → block
//     (momentum just disappeared = exhaustion)
//   - GREEN absent on both bars → pass (no momentum to decelerate;
//     ribbon-only setups are valid — direction confirmed, momentum
//     may be building)
//   - GREEN appeared (was absent, now present) → pass (momentum arriving)
// ─────────────────────────────────────────────────────────────────────

      // ══════════════════════════════════════════════════════════════════
      // PRE-FILTER: DPI GREEN Momentum Deceleration
      // Block when GREEN histogram is shrinking or disappearing bar-over-bar.
      // GREEN = min(|Blue|, |hist|) when Blue & hist same side of zero.
      // Per README_SEA_DPI_mc_main.md: "Blocks entry when GREEN[shift] < GREEN[shift+1]"
      // Only active when DpiDecelFilterEnabled=true AND Ind_Dpi_Enabled=true.
      // ══════════════════════════════════════════════════════════════════
      if(m_settings.DpiDecelFilterEnabled && m_settings.Ind_Dpi_Enabled)
      {
         double hist_cur = 0.0, hist_prev = 0.0;
         bool   dpi_green = false, dpi_macd_agree = false;
         double green_mag_cur = 0.0, green_mag_prev = 0.0;

         if(ComputeDPIMainHist(v_shift, hist_cur, hist_prev, dpi_green, dpi_macd_agree,
                               green_mag_cur, green_mag_prev))
         {
            // GREEN deceleration: momentum confirmation weakening or vanishing.
            //
            // Case 1: GREEN present on both bars but shrinking → momentum fading
            // Case 2: GREEN was present, now gone → momentum just died (OB/OS)
            // Case 3: GREEN absent on both bars → no momentum context, PASS
            //         (ribbon-only setups are valid — direction without momentum
            //          is not deceleration, it's a different market state)
            // Case 4: GREEN was absent, now appeared → momentum arriving, PASS

            bool green_was_present  = (green_mag_prev > 0.0);
            bool green_is_present   = (green_mag_cur  > 0.0);
            bool blocked = false;

            if(green_was_present && green_is_present && green_mag_cur < green_mag_prev)
            {
               // Case 1: GREEN shrinking
               blocked = true;
               if(m_settings.DebugFlow)
                  PrintFormat("[TS_PREFILTER] DPI_DECEL: GREEN shrinking cur=%.6f < prev=%.6f → TS=0",
                              green_mag_cur, green_mag_prev);
            }
            else if(green_was_present && !green_is_present)
            {
               // Case 2: GREEN just disappeared — exhaustion / OB/OS
               blocked = true;
               if(m_settings.DebugFlow)
                  PrintFormat("[TS_PREFILTER] DPI_DECEL: GREEN disappeared (prev=%.6f, cur=0) → TS=0",
                              green_mag_prev);
            }

            if(blocked)
            {
               m_diag_last_reason = "DPI_DECEL";
               m_reject_filter++;
               m_stats.rejected_dpi_decel++;    // PHASE A.1
               if(!full_eval) {
                  m_ts_status_string = StringFormat("B[%s] | I[%s] | F[%s]", m_eval_str_B, m_eval_str_I, m_eval_str_F);
                  UpdateTelemetry(0);
                  FlushOrClearDebugBuffer(0);
                  RestoreForcedDebug();
                  return 0;
               }
               if(m_eval_first_failure == "") m_eval_first_failure = "DPI_DECEL";
               m_eval_any_failure = true;
            }
         }
      }


// ─────────────────────────────────────────────────────────────────────
// CALLER UPDATE 1: Check_DPI vote (line 2264)
// ─────────────────────────────────────────────────────────────────────
//
// Find this line:
//      if(!ComputeDPIMainHist(v_shift, hist_cur, hist_prev, dpi_green, dpi_macd_agree))
//
// Replace with:
//      double _unused_green_cur = 0.0, _unused_green_prev = 0.0;
//      if(!ComputeDPIMainHist(v_shift, hist_cur, hist_prev, dpi_green, dpi_macd_agree,
//                             _unused_green_cur, _unused_green_prev))
//
// The DPI vote logic itself is unchanged — it uses hist direction and CCI agreement,
// not GREEN magnitude. The new outputs are simply discarded here.
// ─────────────────────────────────────────────────────────────────────
