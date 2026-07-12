//  SAVE AS UTF-16 LE WITH BOM
//+------------------------------------------------------------------+
//| SEA_ConfigSync.mqh                                                |
//|                                                                  |
//| Live-EA  ->  Scanner runtime config snapshot writer & reader.    |
//|                                                                  |
//| Purpose: the EA and SEA_IND_SignalScan share SEA_SignalEngine.mqh|
//| but build their ST_Settings independently. Any input divergence  |
//| produces different TS decisions on the same bar. This module     |
//| writes a text snapshot of the EA's final effective ST_Settings   |
//| (after InitializeConfig + ApplyPreset + safety auto-corrects),   |
//| which the scanner can optionally consume to mirror the live EA.  |
//|                                                                  |
//| File location: MQL5/Files/SEA_LiveConfig_<symbol>_<period>.txt   |
//| Per-symbol-TF naming so multiple chart instances do not clobber. |
//|                                                                  |
//| Field selection: only fields that SEA_SignalEngine reads are     |
//| serialized. TE-side fields (spread/time/news/risk/SL/TP/         |
//| trailing/safety) are excluded; they do not affect TS and the     |
//| scanner does not run a TradeExecutor.                            |
//|                                                                  |
//| Format: plain UTF-16 text. Lines starting with '#' are comments. |
//| Body lines are key=value. Enums serialize as int casts.          |
//+------------------------------------------------------------------+
#property strict

// --- Anti-stale build lock (MQL5-safe: no #if, no #error) ---
#ifndef SEA_BUILD_TOKEN_105001
enum { __SEA_BUILD_TOKEN_MISSING_CONFIGSYNC_105001 = SEA_BUILD_TOKEN_105001 };
#endif

#define SEA_MOD_CONFIGSYNC_105001 1

// EA version stamped into the snapshot header. Override at the include
// site if the EA is forked. Used by the reader for diagnostic display.
#ifndef SEA_CONFIGSYNC_EA_VERSION
#define SEA_CONFIGSYNC_EA_VERSION "SimpleEA_v1-05"
#endif

//+------------------------------------------------------------------+
//| Build snapshot filename for a given symbol + timeframe.           |
//+------------------------------------------------------------------+
string SEA_ConfigSync_Filename(const string symbol, const ENUM_TIMEFRAMES tf)
{
   string per = EnumToString(tf);
   StringReplace(per, "PERIOD_", "");
   return StringFormat("SEA_LiveConfig_%s_%s.txt", symbol, per);
}

//+------------------------------------------------------------------+
//| Internal helpers                                                  |
//+------------------------------------------------------------------+
string SEA_CS_Trim(const string s_in)
{
   string s = s_in;
   StringTrimLeft(s);
   StringTrimRight(s);
   return s;
}

bool SEA_CS_ParseBool(const string v)
{
   string s = SEA_CS_Trim(v);
   StringToLower(s);
   return (s == "true" || s == "1" || s == "yes");
}

//+------------------------------------------------------------------+
//| WRITER  -  serialize ST_Settings to text snapshot.                |
//|                                                                  |
//| Returns true on success.                                          |
//| Called from the EA OnInit AFTER InitializeConfig + ApplyPreset   |
//| (and any safety auto-corrects) so the snapshot reflects the      |
//| FINAL effective settings, not raw input values.                  |
//+------------------------------------------------------------------+
bool SEA_WriteConfigSnapshot(const ST_Settings &cfg)
{
   string fname = SEA_ConfigSync_Filename(_Symbol, (ENUM_TIMEFRAMES)_Period);
   uint   flags = FILE_TXT | FILE_WRITE | FILE_UNICODE;

   int h = FileOpen(fname, flags);
   if(h == INVALID_HANDLE) {
      PrintFormat("[CFG_SYNC] WRITER: FileOpen failed for %s err=%d", fname, GetLastError());
      return false;
   }

   datetime now = TimeCurrent();
   FileWriteString(h, "# SEA_LiveConfig snapshot\n");
   FileWriteString(h, StringFormat("# Snapshot=%s\n", TimeToString(now, TIME_DATE|TIME_SECONDS)));
   FileWriteString(h, StringFormat("# SnapshotEpoch=%d\n", (int)now));
   FileWriteString(h, StringFormat("# EA=%s\n", SEA_CONFIGSYNC_EA_VERSION));
   FileWriteString(h, StringFormat("# Symbol=%s\n", _Symbol));
   FileWriteString(h, StringFormat("# Period=%s\n", EnumToString((ENUM_TIMEFRAMES)_Period)));
   FileWriteString(h, "#\n");

   FileWriteString(h, "# -- 01 Bias --\n");
   FileWriteString(h, "AutoStrat=" + IntegerToString((int)cfg.AutoStrat) + "\n");
   FileWriteString(h, "BiasEnabled=" + (cfg.BiasEnabled ? "true" : "false") + "\n");
   FileWriteString(h, "BiasFastID=" + IntegerToString(cfg.BiasFastID) + "\n");
   FileWriteString(h, "BiasMode=" + IntegerToString((int)cfg.BiasMode) + "\n");
   FileWriteString(h, "BiasSlowID=" + IntegerToString(cfg.BiasSlowID) + "\n");
   FileWriteString(h, "MaType=" + IntegerToString((int)cfg.MaType) + "\n");
   FileWriteString(h, "ManSide=" + IntegerToString((int)cfg.ManSide) + "\n");
   FileWriteString(h, "ma_h_shift=" + IntegerToString(cfg.ma_h_shift) + "\n");
   FileWriteString(h, "ma_v_shift=" + IntegerToString(cfg.ma_v_shift) + "\n");
   FileWriteString(h, "# -- 02 EMA ribbon / slope --\n");
   FileWriteString(h, "P_Ema1=" + IntegerToString(cfg.P_Ema1) + "\n");
   FileWriteString(h, "P_Ema2=" + IntegerToString(cfg.P_Ema2) + "\n");
   FileWriteString(h, "P_Ema3=" + IntegerToString(cfg.P_Ema3) + "\n");
   FileWriteString(h, "P_Ema4=" + IntegerToString(cfg.P_Ema4) + "\n");
   FileWriteString(h, "SlopeLookbackBars=" + IntegerToString(cfg.SlopeLookbackBars) + "\n");
   FileWriteString(h, "# -- 03 Phase detection --\n");
   FileWriteString(h, "BlockEmergingPhase=" + (cfg.BlockEmergingPhase ? "true" : "false") + "\n");
   FileWriteString(h, "BlockUnorderedPhase=" + (cfg.BlockUnorderedPhase ? "true" : "false") + "\n");
   FileWriteString(h, "Emerging_AllowStrongTrades=" + (cfg.Emerging_AllowStrongTrades ? "true" : "false") + "\n");
   FileWriteString(h, "MinPhaseConfirmBars=" + IntegerToString(cfg.MinPhaseConfirmBars) + "\n");
   FileWriteString(h, "PhaseDetectionEnabled=" + (cfg.PhaseDetectionEnabled ? "true" : "false") + "\n");
   FileWriteString(h, "RequireMinPhaseConfirm=" + (cfg.RequireMinPhaseConfirm ? "true" : "false") + "\n");
   FileWriteString(h, "# -- 04 Layer detection --\n");
   FileWriteString(h, "AllowLayer1_Entries=" + (cfg.AllowLayer1_Entries ? "true" : "false") + "\n");
   FileWriteString(h, "AllowLayer2_Entries=" + (cfg.AllowLayer2_Entries ? "true" : "false") + "\n");
   FileWriteString(h, "AllowLayer3_Entries=" + (cfg.AllowLayer3_Entries ? "true" : "false") + "\n");
   FileWriteString(h, "EnableLayerDetection=" + (cfg.EnableLayerDetection ? "true" : "false") + "\n");
   FileWriteString(h, "LayerAllowReversalPullback=" + (cfg.LayerAllowReversalPullback ? "true" : "false") + "\n");
   FileWriteString(h, "LayerBaselineLookback=" + IntegerToString(cfg.LayerBaselineLookback) + "\n");
   FileWriteString(h, "LayerBaselineLookback_M=" + IntegerToString(cfg.LayerBaselineLookback_M) + "\n");
   FileWriteString(h, "LayerBaselineLookback_S=" + IntegerToString(cfg.LayerBaselineLookback_S) + "\n");
   FileWriteString(h, "LayerBaselineLookback_W=" + IntegerToString(cfg.LayerBaselineLookback_W) + "\n");
   FileWriteString(h, "LayerFlatRatio=" + DoubleToString(cfg.LayerFlatRatio, 8) + "\n");
   FileWriteString(h, "LayerPullbackEnabled=" + (cfg.LayerPullbackEnabled ? "true" : "false") + "\n");
   // F-AUDIT 2026-07: field renamed LayerPullbackRatio -> LayerPullbackRatio_Legacy (diagnostic
   // rename that resolved an unexplained MetaEditor "undeclared identifier" compile error tied to
   // the original name -- root cause not identified, likely a stale local build artifact). The
   // persisted key stays "LayerPullbackRatio" so old saved .set-sync files still round-trip.
   FileWriteString(h, "LayerPullbackRatio=" + DoubleToString(cfg.LayerPullbackRatio_Legacy, 8) + "\n");
   FileWriteString(h, "LayerRecoveryRatio=" + DoubleToString(cfg.LayerRecoveryRatio, 8) + "\n");
   FileWriteString(h, "LayerRecoveryRatio_M=" + DoubleToString(cfg.LayerRecoveryRatio_M, 8) + "\n");
   FileWriteString(h, "LayerRecoveryRatio_S=" + DoubleToString(cfg.LayerRecoveryRatio_S, 8) + "\n");
   FileWriteString(h, "LayerRecoveryRatio_W=" + DoubleToString(cfg.LayerRecoveryRatio_W, 8) + "\n");
   FileWriteString(h, "LayerResetOnRealign=" + (cfg.LayerResetOnRealign ? "true" : "false") + "\n");
   FileWriteString(h, "LayerResetPhaseConfirmBars=" + IntegerToString(cfg.LayerResetPhaseConfirmBars) + "\n");
   FileWriteString(h, "LayerS_RequireDirAlign=" + (cfg.LayerS_RequireDirAlign ? "true" : "false") + "\n");
   FileWriteString(h, "LayerS_TMOnly=" + (cfg.LayerS_TMOnly ? "true" : "false") + "\n");
   FileWriteString(h, "MinBarsAfterUNOExit=" + IntegerToString(cfg.MinBarsAfterUNOExit) + "\n");
   FileWriteString(h, "UNO_ToleranceBars=" + IntegerToString(cfg.UNO_ToleranceBars) + "\n");
   FileWriteString(h, "LayerPullbackWindow_W=" + IntegerToString(cfg.LayerPullbackWindow_W) + "\n");
   FileWriteString(h, "LayerPullbackWindow_M=" + IntegerToString(cfg.LayerPullbackWindow_M) + "\n");
   FileWriteString(h, "LayerPullbackWindow_S=" + IntegerToString(cfg.LayerPullbackWindow_S) + "\n");
   FileWriteString(h, "LayerPullbackWindow=" + IntegerToString(cfg.LayerPullbackWindow) + "\n");
   FileWriteString(h, "LayerRecoveryMaxAgeEnabled=" + (cfg.LayerRecoveryMaxAgeEnabled ? "true" : "false") + "\n");
   FileWriteString(h, "Guard1_SkipFirstPostFlipPR=" + (cfg.Guard1_SkipFirstPostFlipPR ? "true" : "false") + "\n");
   FileWriteString(h, "# -- 05 BarClose (bc factor) --\n");
   FileWriteString(h, "BarClose_DefaultEMA=" + IntegerToString((int)cfg.BarClose_DefaultEMA) + "\n");
   FileWriteString(h, "BarClose_Enabled=" + (cfg.BarClose_Enabled ? "true" : "false") + "\n");
   FileWriteString(h, "BarClose_LookbackBars=" + IntegerToString(cfg.BarClose_LookbackBars) + "\n");
   FileWriteString(h, "BarClose_Mode=" + IntegerToString((int)cfg.BarClose_Mode) + "\n");
   FileWriteString(h, "BarClose_PipTolerance=" + DoubleToString(cfg.BarClose_PipTolerance, 8) + "\n");
   FileWriteString(h, "Require_Progressive_Momentum=" + (cfg.Require_Progressive_Momentum ? "true" : "false") + "\n");
   FileWriteString(h, "# -- 06 Voting / PSAR-flip --\n");
   FileWriteString(h, "PSAR_FlipGraceBars=" + IntegerToString(cfg.PSAR_FlipGraceBars) + "\n");
   FileWriteString(h, "Vote_AllowPsarFlip=" + (cfg.Vote_AllowPsarFlip ? "true" : "false") + "\n");
   FileWriteString(h, "Vote_EvalShift=" + IntegerToString(cfg.Vote_EvalShift) + "\n");
   FileWriteString(h, "Vote_PsarFlipDelay=" + IntegerToString(cfg.Vote_PsarFlipDelay) + "\n");
   FileWriteString(h, "Vote_PsarFlipDelay_M=" + IntegerToString(cfg.Vote_PsarFlipDelay_M) + "\n");
   FileWriteString(h, "Vote_PsarFlipDelay_S=" + IntegerToString(cfg.Vote_PsarFlipDelay_S) + "\n");
   FileWriteString(h, "Vote_PsarFlipDelay_W=" + IntegerToString(cfg.Vote_PsarFlipDelay_W) + "\n");
   FileWriteString(h, "# -- 07 Indicator master enables --\n");
   FileWriteString(h, "Ind_Adx_Enabled=" + (cfg.Ind_Adx_Enabled ? "true" : "false") + "\n");
   FileWriteString(h, "Ind_Atr_Enabled=" + (cfg.Ind_Atr_Enabled ? "true" : "false") + "\n");
   FileWriteString(h, "Ind_Bb_Enabled=" + (cfg.Ind_Bb_Enabled ? "true" : "false") + "\n");
   FileWriteString(h, "Ind_CI_Enabled=" + (cfg.Ind_CI_Enabled ? "true" : "false") + "\n");
   FileWriteString(h, "Ind_CandleBody_Enabled=" + (cfg.Ind_CandleBody_Enabled ? "true" : "false") + "\n");
   FileWriteString(h, "Ind_Cci_Enabled=" + (cfg.Ind_Cci_Enabled ? "true" : "false") + "\n");
   FileWriteString(h, "Ind_Dpi_Enabled=" + (cfg.Ind_Dpi_Enabled ? "true" : "false") + "\n");
   FileWriteString(h, "Ind_Fib_Enabled=" + (cfg.Ind_Fib_Enabled ? "true" : "false") + "\n");
   FileWriteString(h, "Ind_MTF_Enabled=" + (cfg.Ind_MTF_Enabled ? "true" : "false") + "\n");
   FileWriteString(h, "Ind_Macd_Enabled=" + (cfg.Ind_Macd_Enabled ? "true" : "false") + "\n");
   FileWriteString(h, "Ind_Mfi_Enabled=" + (cfg.Ind_Mfi_Enabled ? "true" : "false") + "\n");
   FileWriteString(h, "Ind_P123_Enabled=" + (cfg.Ind_P123_Enabled ? "true" : "false") + "\n");
   FileWriteString(h, "Ind_Psar_Enabled=" + (cfg.Ind_Psar_Enabled ? "true" : "false") + "\n");
   FileWriteString(h, "Ind_Ross_Enabled=" + (cfg.Ind_Ross_Enabled ? "true" : "false") + "\n");
   FileWriteString(h, "Ind_Rsi_Enabled=" + (cfg.Ind_Rsi_Enabled ? "true" : "false") + "\n");
   FileWriteString(h, "Ind_SmaConverge_Enabled=" + (cfg.Ind_SmaConverge_Enabled ? "true" : "false") + "\n");
   FileWriteString(h, "Ind_Sto_Enabled=" + (cfg.Ind_Sto_Enabled ? "true" : "false") + "\n");
   FileWriteString(h, "Ind_VRC_Enabled=" + (cfg.Ind_VRC_Enabled ? "true" : "false") + "\n");
   FileWriteString(h, "# -- 08 ADX --\n");
   FileWriteString(h, "ADX_Lookback=" + IntegerToString(cfg.ADX_Lookback) + "\n");
   FileWriteString(h, "ADX_Mode=" + IntegerToString((int)cfg.ADX_Mode) + "\n");
   FileWriteString(h, "ADX_Percentile=" + DoubleToString(cfg.ADX_Percentile, 8) + "\n");
   FileWriteString(h, "ADX_PercentileRefreshSec=" + IntegerToString(cfg.ADX_PercentileRefreshSec) + "\n");
   FileWriteString(h, "ADX_Threshold_Accumulation=" + DoubleToString(cfg.ADX_Threshold_Accumulation, 8) + "\n");
   FileWriteString(h, "ADX_Threshold_Distribution=" + DoubleToString(cfg.ADX_Threshold_Distribution, 8) + "\n");
   FileWriteString(h, "ADX_Threshold_Trending=" + DoubleToString(cfg.ADX_Threshold_Trending, 8) + "\n");
   FileWriteString(h, "P_Adx=" + IntegerToString(cfg.P_Adx) + "\n");
   FileWriteString(h, "T_Adx=" + DoubleToString(cfg.T_Adx, 8) + "\n");
   FileWriteString(h, "# -- 09 MACD --\n");
   FileWriteString(h, "MacdBlockOnDivergence=" + (cfg.MacdBlockOnDivergence ? "true" : "false") + "\n");
   FileWriteString(h, "MacdDivLookback=" + IntegerToString(cfg.MacdDivLookback) + "\n");
   FileWriteString(h, "MacdFreshBars=" + IntegerToString(cfg.MacdFreshBars) + "\n");
   FileWriteString(h, "MacdHistDecelEnabled=" + (cfg.MacdHistDecelEnabled ? "true" : "false") + "\n");
   FileWriteString(h, "MacdRequireHook=" + (cfg.MacdRequireHook ? "true" : "false") + "\n");
   FileWriteString(h, "MacdRequireSlope=" + (cfg.MacdRequireSlope ? "true" : "false") + "\n");
   FileWriteString(h, "MacdSlopeMin=" + DoubleToString(cfg.MacdSlopeMin, 8) + "\n");
   FileWriteString(h, "MacdVoteMode=" + IntegerToString((int)cfg.MacdVoteMode) + "\n");
   FileWriteString(h, "P_MacdFast=" + IntegerToString(cfg.P_MacdFast) + "\n");
   FileWriteString(h, "P_MacdSig=" + IntegerToString(cfg.P_MacdSig) + "\n");
   FileWriteString(h, "P_MacdSlow=" + IntegerToString(cfg.P_MacdSlow) + "\n");
   FileWriteString(h, "# -- 10 RSI --\n");
   FileWriteString(h, "P_Rsi=" + IntegerToString(cfg.P_Rsi) + "\n");
   FileWriteString(h, "RsiMode=" + IntegerToString((int)cfg.RsiMode) + "\n");
   FileWriteString(h, "T_RsiOB=" + DoubleToString(cfg.T_RsiOB, 8) + "\n");
   FileWriteString(h, "T_RsiOS=" + DoubleToString(cfg.T_RsiOS, 8) + "\n");
   FileWriteString(h, "# -- 11 CCI --\n");
   FileWriteString(h, "CciMode=" + IntegerToString((int)cfg.CciMode) + "\n");
   FileWriteString(h, "P_Cci=" + IntegerToString(cfg.P_Cci) + "\n");
   FileWriteString(h, "# -- 12 MFI --\n");
   FileWriteString(h, "P_Mfi=" + IntegerToString(cfg.P_Mfi) + "\n");
   FileWriteString(h, "T_MfiOB=" + DoubleToString(cfg.T_MfiOB, 8) + "\n");
   FileWriteString(h, "T_MfiOS=" + DoubleToString(cfg.T_MfiOS, 8) + "\n");
   FileWriteString(h, "# -- 13 Stoch --\n");
   FileWriteString(h, "P_StoD=" + IntegerToString(cfg.P_StoD) + "\n");
   FileWriteString(h, "P_StoK=" + IntegerToString(cfg.P_StoK) + "\n");
   FileWriteString(h, "P_StoSlow=" + IntegerToString(cfg.P_StoSlow) + "\n");
   FileWriteString(h, "StoMode=" + IntegerToString((int)cfg.StoMode) + "\n");
   FileWriteString(h, "T_StoOB=" + DoubleToString(cfg.T_StoOB, 8) + "\n");
   FileWriteString(h, "T_StoOS=" + DoubleToString(cfg.T_StoOS, 8) + "\n");
   FileWriteString(h, "# -- 14 Bollinger Bands --\n");
   FileWriteString(h, "BbMode=" + IntegerToString((int)cfg.BbMode) + "\n");
   FileWriteString(h, "P_Bb=" + IntegerToString(cfg.P_Bb) + "\n");
   FileWriteString(h, "P_BbDev=" + DoubleToString(cfg.P_BbDev, 8) + "\n");
   FileWriteString(h, "# -- 15 PSAR params --\n");
   FileWriteString(h, "P_PsarMax=" + DoubleToString(cfg.P_PsarMax, 8) + "\n");
   FileWriteString(h, "P_PsarStep=" + DoubleToString(cfg.P_PsarStep, 8) + "\n");
   FileWriteString(h, "# -- 16 ATR --\n");
   FileWriteString(h, "ATR_VoteMaxPips=" + DoubleToString(cfg.ATR_VoteMaxPips, 8) + "\n");
   FileWriteString(h, "ATR_VoteMinPips=" + DoubleToString(cfg.ATR_VoteMinPips, 8) + "\n");
   FileWriteString(h, "P_Atr=" + IntegerToString(cfg.P_Atr) + "\n");
   FileWriteString(h, "# -- 17 CandleBody --\n");
   FileWriteString(h, "CandleBody_AvgPeriod=" + IntegerToString(cfg.CandleBody_AvgPeriod) + "\n");
   FileWriteString(h, "CandleBody_CarryOnOverext=" + (cfg.CandleBody_CarryOnOverext ? "true" : "false") + "\n");
   FileWriteString(h, "CandleBody_CheckBars=" + IntegerToString(cfg.CandleBody_CheckBars) + "\n");
   FileWriteString(h, "CandleBody_MaxMult=" + DoubleToString(cfg.CandleBody_MaxMult, 8) + "\n");
   FileWriteString(h, "CandleBody_MinCloseRatio=" + DoubleToString(cfg.CandleBody_MinCloseRatio, 8) + "\n");
   FileWriteString(h, "CandleBody_RequireDirection=" + (cfg.CandleBody_RequireDirection ? "true" : "false") + "\n");
   FileWriteString(h, "# -- 18 Choppiness Index --\n");
   FileWriteString(h, "CI_Period=" + IntegerToString(cfg.CI_Period) + "\n");
   FileWriteString(h, "CI_RangingThreshold=" + DoubleToString(cfg.CI_RangingThreshold, 8) + "\n");
   FileWriteString(h, "# -- 19 VRC --\n");
   FileWriteString(h, "VRC_Lookback=" + IntegerToString(cfg.VRC_Lookback) + "\n");
   FileWriteString(h, "VRC_LowThreshold=" + DoubleToString(cfg.VRC_LowThreshold, 8) + "\n");
   FileWriteString(h, "VRC_RefreshSec=" + IntegerToString(cfg.VRC_RefreshSec) + "\n");
   FileWriteString(h, "# -- 20 DPI --\n");
   FileWriteString(h, "DPI_BlockOnDeceleration=" + (cfg.DPI_BlockOnDeceleration ? "true" : "false") + "\n");
   FileWriteString(h, "DPI_CCI_AppliedPrice=" + IntegerToString(cfg.DPI_CCI_AppliedPrice) + "\n");
   FileWriteString(h, "DPI_CCI_Period=" + IntegerToString(cfg.DPI_CCI_Period) + "\n");
   FileWriteString(h, "DPI_DoubleSmoothFirst=" + IntegerToString(cfg.DPI_DoubleSmoothFirst) + "\n");
   FileWriteString(h, "DPI_DoubleSmoothSecond=" + IntegerToString(cfg.DPI_DoubleSmoothSecond) + "\n");
   FileWriteString(h, "DPI_GrantFirstEntry=" + (cfg.DPI_GrantFirstEntry ? "true" : "false") + "\n");
   FileWriteString(h, "DPI_HistDecelLookback=" + IntegerToString(cfg.DPI_HistDecelLookback) + "\n");
   FileWriteString(h, "DPI_HistMomentumThreshold=" + DoubleToString(cfg.DPI_HistMomentumThreshold, 8) + "\n");
   FileWriteString(h, "DPI_HistTrackingEnabled=" + (cfg.DPI_HistTrackingEnabled ? "true" : "false") + "\n");
   FileWriteString(h, "DPI_Histogram_Growth_Boost=" + (cfg.DPI_Histogram_Growth_Boost ? "true" : "false") + "\n");
   FileWriteString(h, "DPI_IgnoreCCIForVote=" + (cfg.DPI_IgnoreCCIForVote ? "true" : "false") + "\n");
   FileWriteString(h, "DPI_MACD_Fast=" + IntegerToString(cfg.DPI_MACD_Fast) + "\n");
   FileWriteString(h, "DPI_MACD_Slow=" + IntegerToString(cfg.DPI_MACD_Slow) + "\n");
   FileWriteString(h, "DPI_RedEMA_A=" + IntegerToString(cfg.DPI_RedEMA_A) + "\n");
   FileWriteString(h, "DPI_RedEMA_B=" + IntegerToString(cfg.DPI_RedEMA_B) + "\n");
   FileWriteString(h, "DPI_RedEMA_C=" + IntegerToString(cfg.DPI_RedEMA_C) + "\n");
   FileWriteString(h, "DPI_RedEMA_D=" + IntegerToString(cfg.DPI_RedEMA_D) + "\n");
   FileWriteString(h, "DPI_RedSignalType=" + IntegerToString(cfg.DPI_RedSignalType) + "\n");
   FileWriteString(h, "DPI_RequireResetRecovery=" + (cfg.DPI_RequireResetRecovery ? "true" : "false") + "\n");
   FileWriteString(h, "DPI_ResetRecoveryBars=" + IntegerToString(cfg.DPI_ResetRecoveryBars) + "\n");
   FileWriteString(h, "DPI_ResetRequireGreen=" + (cfg.DPI_ResetRequireGreen ? "true" : "false") + "\n");
   FileWriteString(h, "DPI_UseCCIReset=" + (cfg.DPI_UseCCIReset ? "true" : "false") + "\n");
   FileWriteString(h, "DPI_UseGreenHist=" + (cfg.DPI_UseGreenHist ? "true" : "false") + "\n");
   FileWriteString(h, "DpiBlockOnDivergence=" + (cfg.DpiBlockOnDivergence ? "true" : "false") + "\n");
   FileWriteString(h, "DpiDecelFilterEnabled=" + (cfg.DpiDecelFilterEnabled ? "true" : "false") + "\n");
   FileWriteString(h, "DpiDivLookback=" + IntegerToString(cfg.DpiDivLookback) + "\n");
   FileWriteString(h, "# -- 21 MTF --\n");
   FileWriteString(h, "MTF_EMA_Fast=" + IntegerToString(cfg.MTF_EMA_Fast) + "\n");
   FileWriteString(h, "MTF_EMA_Slow=" + IntegerToString(cfg.MTF_EMA_Slow) + "\n");
   FileWriteString(h, "MTF_RequirePhase=" + (cfg.MTF_RequirePhase ? "true" : "false") + "\n");
   FileWriteString(h, "MTF_TF1=" + IntegerToString((int)cfg.MTF_TF1) + "\n");
   FileWriteString(h, "MTF_TF2=" + IntegerToString((int)cfg.MTF_TF2) + "\n");
   FileWriteString(h, "# -- 22 Fibonacci --\n");
   FileWriteString(h, "Fib_MaxRetracement=" + DoubleToString(cfg.Fib_MaxRetracement, 8) + "\n");
   FileWriteString(h, "Fib_MinRetracement=" + DoubleToString(cfg.Fib_MinRetracement, 8) + "\n");
   FileWriteString(h, "Fib_SwingLookback=" + IntegerToString(cfg.Fib_SwingLookback) + "\n");
   FileWriteString(h, "# -- 23 Climax Guard --\n");
   FileWriteString(h, "ClimaxGuard_ATRPeriod=" + IntegerToString(cfg.ClimaxGuard_ATRPeriod) + "\n");
   FileWriteString(h, "ClimaxGuard_BarATRMult=" + DoubleToString(cfg.ClimaxGuard_BarATRMult, 8) + "\n");
   FileWriteString(h, "ClimaxGuard_Enabled=" + (cfg.ClimaxGuard_Enabled ? "true" : "false") + "\n");
   FileWriteString(h, "ClimaxGuard_Lookback=" + IntegerToString(cfg.ClimaxGuard_Lookback) + "\n");
   FileWriteString(h, "ClimaxGuard_MoveATRMult=" + DoubleToString(cfg.ClimaxGuard_MoveATRMult, 8) + "\n");
   FileWriteString(h, "ClimaxGuard_ResetPullback=" + (cfg.ClimaxGuard_ResetPullback ? "true" : "false") + "\n");
   FileWriteString(h, "# -- 24 VPRR --\n");
   FileWriteString(h, "VPRR_Enabled=" + (cfg.VPRR_Enabled ? "true" : "false") + "\n");
   FileWriteString(h, "VPRR_ExternalSymbol=" + cfg.VPRR_ExternalSymbol + "\n");
   FileWriteString(h, "VPRR_MinRatio=" + DoubleToString(cfg.VPRR_MinRatio, 8) + "\n");
   FileWriteString(h, "VPRR_MinRatio_M=" + DoubleToString(cfg.VPRR_MinRatio_M, 8) + "\n");
   FileWriteString(h, "VPRR_MinRatio_S=" + DoubleToString(cfg.VPRR_MinRatio_S, 8) + "\n");
   FileWriteString(h, "VPRR_MinRatio_W=" + DoubleToString(cfg.VPRR_MinRatio_W, 8) + "\n");
   FileWriteString(h, "VPRR_MinRecoveryBars=" + IntegerToString(cfg.VPRR_MinRecoveryBars) + "\n");
   FileWriteString(h, "VPRR_RecoveryBars=" + IntegerToString(cfg.VPRR_RecoveryBars) + "\n");
   FileWriteString(h, "VPRR_VolumeType=" + IntegerToString(cfg.VPRR_VolumeType) + "\n");
   FileWriteString(h, "# -- 25 Extension filters --\n");
   FileWriteString(h, "EmaFanFilterEnabled=" + (cfg.EmaFanFilterEnabled ? "true" : "false") + "\n");
   FileWriteString(h, "EmaFanMaxPct=" + DoubleToString(cfg.EmaFanMaxPct, 8) + "\n");
   FileWriteString(h, "EmaFanMaxTotalPips=" + DoubleToString(cfg.EmaFanMaxTotalPips, 8) + "\n");
   FileWriteString(h, "PriceExtAtrPeriod=" + IntegerToString(cfg.PriceExtAtrPeriod) + "\n");
   FileWriteString(h, "PriceExtFilterEnabled=" + (cfg.PriceExtFilterEnabled ? "true" : "false") + "\n");
   FileWriteString(h, "PriceExtMaxATR=" + DoubleToString(cfg.PriceExtMaxATR, 8) + "\n");
   FileWriteString(h, "PriceExtRefEma=" + IntegerToString(cfg.PriceExtRefEma) + "\n");
   FileWriteString(h, "# -- 26 MA Benchmark --\n");
   FileWriteString(h, "MABenchmarkStrict=" + (cfg.MABenchmarkStrict ? "true" : "false") + "\n");
   FileWriteString(h, "RequirePriceCross=" + (cfg.RequirePriceCross ? "true" : "false") + "\n");
   FileWriteString(h, "# -- 27 Trail / Exit (engine consults for indicator handles) --\n");
   FileWriteString(h, "ExitProfile=" + IntegerToString((int)cfg.ExitProfile) + "\n");
   FileWriteString(h, "TrailMode=" + IntegerToString((int)cfg.TrailMode) + "\n");
   FileWriteString(h, "# -- 28 Weekend-gap timing --\n");
   FileWriteString(h, "MinBarsAfterWeekendGap=" + IntegerToString(cfg.MinBarsAfterWeekendGap) + "\n");

   FileClose(h);
   PrintFormat("[CFG_SYNC] WRITER: snapshot written -> %s (%d fields)", fname, 187);
   return true;
}

//+------------------------------------------------------------------+
//| Internal: dispatch one key=value pair onto ST_Settings.           |
//| Returns true if the key was recognized & applied.                 |
//|                                                                  |
//| Unknown keys are silently ignored to provide forward              |
//| compatibility with newer EA versions that may serialize fields   |
//| this scanner build does not yet know about.                      |
//+------------------------------------------------------------------+
bool SEA_CS_ApplyKey(ST_Settings &s, const string key, const string val)
{
   if(key == "ADX_Lookback") { s.ADX_Lookback = (int)StringToInteger(val); return true; }
   if(key == "ADX_Mode") { s.ADX_Mode = (EADXMode)(int)StringToInteger(val); return true; }
   if(key == "ADX_Percentile") { s.ADX_Percentile = StringToDouble(val); return true; }
   if(key == "ADX_PercentileRefreshSec") { s.ADX_PercentileRefreshSec = (int)StringToInteger(val); return true; }
   if(key == "ADX_Threshold_Accumulation") { s.ADX_Threshold_Accumulation = StringToDouble(val); return true; }
   if(key == "ADX_Threshold_Distribution") { s.ADX_Threshold_Distribution = StringToDouble(val); return true; }
   if(key == "ADX_Threshold_Trending") { s.ADX_Threshold_Trending = StringToDouble(val); return true; }
   if(key == "ATR_VoteMaxPips") { s.ATR_VoteMaxPips = StringToDouble(val); return true; }
   if(key == "ATR_VoteMinPips") { s.ATR_VoteMinPips = StringToDouble(val); return true; }
   if(key == "AllowLayer1_Entries") { s.AllowLayer1_Entries = SEA_CS_ParseBool(val); return true; }
   if(key == "AllowLayer2_Entries") { s.AllowLayer2_Entries = SEA_CS_ParseBool(val); return true; }
   if(key == "AllowLayer3_Entries") { s.AllowLayer3_Entries = SEA_CS_ParseBool(val); return true; }
   if(key == "AutoStrat") { s.AutoStrat = (EAutoStrategy)(int)StringToInteger(val); return true; }
   if(key == "BarClose_DefaultEMA") { s.BarClose_DefaultEMA = (EEmaRole)(int)StringToInteger(val); return true; }
   if(key == "BarClose_Enabled") { s.BarClose_Enabled = SEA_CS_ParseBool(val); return true; }
   if(key == "BarClose_LookbackBars") { s.BarClose_LookbackBars = (int)StringToInteger(val); return true; }
   if(key == "BarClose_Mode") { s.BarClose_Mode = (EBarCloseMode)(int)StringToInteger(val); return true; }
   if(key == "BarClose_PipTolerance") { s.BarClose_PipTolerance = StringToDouble(val); return true; }
   if(key == "BbMode") { s.BbMode = (EBbMode)(int)StringToInteger(val); return true; }
   if(key == "BiasEnabled") { s.BiasEnabled = SEA_CS_ParseBool(val); return true; }
   if(key == "BiasFastID") { s.BiasFastID = (int)StringToInteger(val); return true; }
   if(key == "BiasMode") { s.BiasMode = (EBiasMode)(int)StringToInteger(val); return true; }
   if(key == "BiasSlowID") { s.BiasSlowID = (int)StringToInteger(val); return true; }
   if(key == "BlockEmergingPhase") { s.BlockEmergingPhase = SEA_CS_ParseBool(val); return true; }
   if(key == "BlockUnorderedPhase") { s.BlockUnorderedPhase = SEA_CS_ParseBool(val); return true; }
   if(key == "CI_Period") { s.CI_Period = (int)StringToInteger(val); return true; }
   if(key == "CI_RangingThreshold") { s.CI_RangingThreshold = StringToDouble(val); return true; }
   if(key == "CandleBody_AvgPeriod") { s.CandleBody_AvgPeriod = (int)StringToInteger(val); return true; }
   if(key == "CandleBody_CarryOnOverext") { s.CandleBody_CarryOnOverext = SEA_CS_ParseBool(val); return true; }
   if(key == "CandleBody_CheckBars") { s.CandleBody_CheckBars = (int)StringToInteger(val); return true; }
   if(key == "CandleBody_MaxMult") { s.CandleBody_MaxMult = StringToDouble(val); return true; }
   if(key == "CandleBody_MinCloseRatio") { s.CandleBody_MinCloseRatio = StringToDouble(val); return true; }
   if(key == "CandleBody_RequireDirection") { s.CandleBody_RequireDirection = SEA_CS_ParseBool(val); return true; }
   if(key == "CciMode") { s.CciMode = (ECciMode)(int)StringToInteger(val); return true; }
   if(key == "ClimaxGuard_ATRPeriod") { s.ClimaxGuard_ATRPeriod = (int)StringToInteger(val); return true; }
   if(key == "ClimaxGuard_BarATRMult") { s.ClimaxGuard_BarATRMult = StringToDouble(val); return true; }
   if(key == "ClimaxGuard_Enabled") { s.ClimaxGuard_Enabled = SEA_CS_ParseBool(val); return true; }
   if(key == "ClimaxGuard_Lookback") { s.ClimaxGuard_Lookback = (int)StringToInteger(val); return true; }
   if(key == "ClimaxGuard_MoveATRMult") { s.ClimaxGuard_MoveATRMult = StringToDouble(val); return true; }
   if(key == "ClimaxGuard_ResetPullback") { s.ClimaxGuard_ResetPullback = SEA_CS_ParseBool(val); return true; }
   if(key == "DPI_BlockOnDeceleration") { s.DPI_BlockOnDeceleration = SEA_CS_ParseBool(val); return true; }
   if(key == "DPI_CCI_AppliedPrice") { s.DPI_CCI_AppliedPrice = (int)StringToInteger(val); return true; }
   if(key == "DPI_CCI_Period") { s.DPI_CCI_Period = (int)StringToInteger(val); return true; }
   if(key == "DPI_DoubleSmoothFirst") { s.DPI_DoubleSmoothFirst = (int)StringToInteger(val); return true; }
   if(key == "DPI_DoubleSmoothSecond") { s.DPI_DoubleSmoothSecond = (int)StringToInteger(val); return true; }
   if(key == "DPI_GrantFirstEntry") { s.DPI_GrantFirstEntry = SEA_CS_ParseBool(val); return true; }
   if(key == "DPI_HistDecelLookback") { s.DPI_HistDecelLookback = (int)StringToInteger(val); return true; }
   if(key == "DPI_HistMomentumThreshold") { s.DPI_HistMomentumThreshold = StringToDouble(val); return true; }
   if(key == "DPI_HistTrackingEnabled") { s.DPI_HistTrackingEnabled = SEA_CS_ParseBool(val); return true; }
   if(key == "DPI_Histogram_Growth_Boost") { s.DPI_Histogram_Growth_Boost = SEA_CS_ParseBool(val); return true; }
   if(key == "DPI_IgnoreCCIForVote") { s.DPI_IgnoreCCIForVote = SEA_CS_ParseBool(val); return true; }
   if(key == "DPI_MACD_Fast") { s.DPI_MACD_Fast = (int)StringToInteger(val); return true; }
   if(key == "DPI_MACD_Slow") { s.DPI_MACD_Slow = (int)StringToInteger(val); return true; }
   if(key == "DPI_RedEMA_A") { s.DPI_RedEMA_A = (int)StringToInteger(val); return true; }
   if(key == "DPI_RedEMA_B") { s.DPI_RedEMA_B = (int)StringToInteger(val); return true; }
   if(key == "DPI_RedEMA_C") { s.DPI_RedEMA_C = (int)StringToInteger(val); return true; }
   if(key == "DPI_RedEMA_D") { s.DPI_RedEMA_D = (int)StringToInteger(val); return true; }
   if(key == "DPI_RedSignalType") { s.DPI_RedSignalType = (int)StringToInteger(val); return true; }
   if(key == "DPI_RequireResetRecovery") { s.DPI_RequireResetRecovery = SEA_CS_ParseBool(val); return true; }
   if(key == "DPI_ResetRecoveryBars") { s.DPI_ResetRecoveryBars = (int)StringToInteger(val); return true; }
   if(key == "DPI_ResetRequireGreen") { s.DPI_ResetRequireGreen = SEA_CS_ParseBool(val); return true; }
   if(key == "DPI_UseCCIReset") { s.DPI_UseCCIReset = SEA_CS_ParseBool(val); return true; }
   if(key == "DPI_UseGreenHist") { s.DPI_UseGreenHist = SEA_CS_ParseBool(val); return true; }
   if(key == "DpiBlockOnDivergence") { s.DpiBlockOnDivergence = SEA_CS_ParseBool(val); return true; }
   if(key == "DpiDecelFilterEnabled") { s.DpiDecelFilterEnabled = SEA_CS_ParseBool(val); return true; }
   if(key == "DpiDivLookback") { s.DpiDivLookback = (int)StringToInteger(val); return true; }
   if(key == "EmaFanFilterEnabled") { s.EmaFanFilterEnabled = SEA_CS_ParseBool(val); return true; }
   if(key == "EmaFanMaxPct") { s.EmaFanMaxPct = StringToDouble(val); return true; }
   if(key == "EmaFanMaxTotalPips") { s.EmaFanMaxTotalPips = StringToDouble(val); return true; }
   if(key == "Emerging_AllowStrongTrades") { s.Emerging_AllowStrongTrades = SEA_CS_ParseBool(val); return true; }
   if(key == "EnableLayerDetection") { s.EnableLayerDetection = SEA_CS_ParseBool(val); return true; }
   if(key == "ExitProfile") { s.ExitProfile = (EExitProfile)(int)StringToInteger(val); return true; }
   if(key == "Fib_MaxRetracement") { s.Fib_MaxRetracement = StringToDouble(val); return true; }
   if(key == "Fib_MinRetracement") { s.Fib_MinRetracement = StringToDouble(val); return true; }
   if(key == "Fib_SwingLookback") { s.Fib_SwingLookback = (int)StringToInteger(val); return true; }
   if(key == "Ind_Adx_Enabled") { s.Ind_Adx_Enabled = SEA_CS_ParseBool(val); return true; }
   if(key == "Ind_Atr_Enabled") { s.Ind_Atr_Enabled = SEA_CS_ParseBool(val); return true; }
   if(key == "Ind_Bb_Enabled") { s.Ind_Bb_Enabled = SEA_CS_ParseBool(val); return true; }
   if(key == "Ind_CI_Enabled") { s.Ind_CI_Enabled = SEA_CS_ParseBool(val); return true; }
   if(key == "Ind_CandleBody_Enabled") { s.Ind_CandleBody_Enabled = SEA_CS_ParseBool(val); return true; }
   if(key == "Ind_Cci_Enabled") { s.Ind_Cci_Enabled = SEA_CS_ParseBool(val); return true; }
   if(key == "Ind_Dpi_Enabled") { s.Ind_Dpi_Enabled = SEA_CS_ParseBool(val); return true; }
   if(key == "Ind_Fib_Enabled") { s.Ind_Fib_Enabled = SEA_CS_ParseBool(val); return true; }
   if(key == "Ind_MTF_Enabled") { s.Ind_MTF_Enabled = SEA_CS_ParseBool(val); return true; }
   if(key == "Ind_Macd_Enabled") { s.Ind_Macd_Enabled = SEA_CS_ParseBool(val); return true; }
   if(key == "Ind_Mfi_Enabled") { s.Ind_Mfi_Enabled = SEA_CS_ParseBool(val); return true; }
   if(key == "Ind_P123_Enabled") { s.Ind_P123_Enabled = SEA_CS_ParseBool(val); return true; }
   if(key == "Ind_Psar_Enabled") { s.Ind_Psar_Enabled = SEA_CS_ParseBool(val); return true; }
   if(key == "Ind_Ross_Enabled") { s.Ind_Ross_Enabled = SEA_CS_ParseBool(val); return true; }
   if(key == "Ind_Rsi_Enabled") { s.Ind_Rsi_Enabled = SEA_CS_ParseBool(val); return true; }
   if(key == "Ind_SmaConverge_Enabled") { s.Ind_SmaConverge_Enabled = SEA_CS_ParseBool(val); return true; }
   if(key == "Ind_Sto_Enabled") { s.Ind_Sto_Enabled = SEA_CS_ParseBool(val); return true; }
   if(key == "Ind_VRC_Enabled") { s.Ind_VRC_Enabled = SEA_CS_ParseBool(val); return true; }
   if(key == "LayerAllowReversalPullback") { s.LayerAllowReversalPullback = SEA_CS_ParseBool(val); return true; }
   if(key == "LayerBaselineLookback") { s.LayerBaselineLookback = (int)StringToInteger(val); return true; }
   if(key == "LayerBaselineLookback_M") { s.LayerBaselineLookback_M = (int)StringToInteger(val); return true; }
   if(key == "LayerBaselineLookback_S") { s.LayerBaselineLookback_S = (int)StringToInteger(val); return true; }
   if(key == "LayerBaselineLookback_W") { s.LayerBaselineLookback_W = (int)StringToInteger(val); return true; }
   if(key == "LayerFlatRatio") { s.LayerFlatRatio = StringToDouble(val); return true; }
   if(key == "LayerPullbackEnabled") { s.LayerPullbackEnabled = SEA_CS_ParseBool(val); return true; }
   if(key == "LayerPullbackRatio") { s.LayerPullbackRatio_Legacy = StringToDouble(val); return true; }
   if(key == "LayerRecoveryRatio") { s.LayerRecoveryRatio = StringToDouble(val); return true; }
   if(key == "LayerRecoveryRatio_M") { s.LayerRecoveryRatio_M = StringToDouble(val); return true; }
   if(key == "LayerRecoveryRatio_S") { s.LayerRecoveryRatio_S = StringToDouble(val); return true; }
   if(key == "LayerRecoveryRatio_W") { s.LayerRecoveryRatio_W = StringToDouble(val); return true; }
   if(key == "LayerResetOnRealign") { s.LayerResetOnRealign = SEA_CS_ParseBool(val); return true; }
   if(key == "LayerResetPhaseConfirmBars") { s.LayerResetPhaseConfirmBars = (int)StringToInteger(val); return true; }
   if(key == "LayerS_RequireDirAlign") { s.LayerS_RequireDirAlign = SEA_CS_ParseBool(val); return true; }
   if(key == "LayerS_TMOnly") { s.LayerS_TMOnly = SEA_CS_ParseBool(val); return true; }
   if(key == "MABenchmarkStrict") { s.MABenchmarkStrict = SEA_CS_ParseBool(val); return true; }
   if(key == "MTF_EMA_Fast") { s.MTF_EMA_Fast = (int)StringToInteger(val); return true; }
   if(key == "MTF_EMA_Slow") { s.MTF_EMA_Slow = (int)StringToInteger(val); return true; }
   if(key == "MTF_RequirePhase") { s.MTF_RequirePhase = SEA_CS_ParseBool(val); return true; }
   if(key == "MTF_TF1") { s.MTF_TF1 = (ENUM_TIMEFRAMES)(int)StringToInteger(val); return true; }
   if(key == "MTF_TF2") { s.MTF_TF2 = (ENUM_TIMEFRAMES)(int)StringToInteger(val); return true; }
   if(key == "MaType") { s.MaType = (EMaMethod)(int)StringToInteger(val); return true; }
   if(key == "MacdBlockOnDivergence") { s.MacdBlockOnDivergence = SEA_CS_ParseBool(val); return true; }
   if(key == "MacdDivLookback") { s.MacdDivLookback = (int)StringToInteger(val); return true; }
   if(key == "MacdFreshBars") { s.MacdFreshBars = (int)StringToInteger(val); return true; }
   if(key == "MacdHistDecelEnabled") { s.MacdHistDecelEnabled = SEA_CS_ParseBool(val); return true; }
   if(key == "MacdRequireHook") { s.MacdRequireHook = SEA_CS_ParseBool(val); return true; }
   if(key == "MacdRequireSlope") { s.MacdRequireSlope = SEA_CS_ParseBool(val); return true; }
   if(key == "MacdSlopeMin") { s.MacdSlopeMin = StringToDouble(val); return true; }
   if(key == "MacdVoteMode") { s.MacdVoteMode = (EMacdVoteMode)(int)StringToInteger(val); return true; }
   if(key == "ManSide") { s.ManSide = (EManualSide)(int)StringToInteger(val); return true; }
   if(key == "MinBarsAfterUNOExit") { s.MinBarsAfterUNOExit = (int)StringToInteger(val); return true; }
   if(key == "UNO_ToleranceBars") { s.UNO_ToleranceBars = (int)StringToInteger(val); return true; }
   if(key == "LayerPullbackWindow_W") { s.LayerPullbackWindow_W = (int)StringToInteger(val); return true; }
   if(key == "LayerPullbackWindow_M") { s.LayerPullbackWindow_M = (int)StringToInteger(val); return true; }
   if(key == "LayerPullbackWindow_S") { s.LayerPullbackWindow_S = (int)StringToInteger(val); return true; }
   if(key == "LayerPullbackWindow") { s.LayerPullbackWindow = (int)StringToInteger(val); return true; }
   if(key == "LayerRecoveryMaxAgeEnabled") { s.LayerRecoveryMaxAgeEnabled = SEA_CS_ParseBool(val); return true; }
   if(key == "Guard1_SkipFirstPostFlipPR") { s.Guard1_SkipFirstPostFlipPR = SEA_CS_ParseBool(val); return true; }
   if(key == "MinBarsAfterWeekendGap") { s.MinBarsAfterWeekendGap = (int)StringToInteger(val); return true; }
   if(key == "MinPhaseConfirmBars") { s.MinPhaseConfirmBars = (int)StringToInteger(val); return true; }
   if(key == "PSAR_FlipGraceBars") { s.PSAR_FlipGraceBars = (int)StringToInteger(val); return true; }
   if(key == "P_Adx") { s.P_Adx = (int)StringToInteger(val); return true; }
   if(key == "P_Atr") { s.P_Atr = (int)StringToInteger(val); return true; }
   if(key == "P_Bb") { s.P_Bb = (int)StringToInteger(val); return true; }
   if(key == "P_BbDev") { s.P_BbDev = StringToDouble(val); return true; }
   if(key == "P_Cci") { s.P_Cci = (int)StringToInteger(val); return true; }
   if(key == "P_Ema1") { s.P_Ema1 = (int)StringToInteger(val); return true; }
   if(key == "P_Ema2") { s.P_Ema2 = (int)StringToInteger(val); return true; }
   if(key == "P_Ema3") { s.P_Ema3 = (int)StringToInteger(val); return true; }
   if(key == "P_Ema4") { s.P_Ema4 = (int)StringToInteger(val); return true; }
   if(key == "P_MacdFast") { s.P_MacdFast = (int)StringToInteger(val); return true; }
   if(key == "P_MacdSig") { s.P_MacdSig = (int)StringToInteger(val); return true; }
   if(key == "P_MacdSlow") { s.P_MacdSlow = (int)StringToInteger(val); return true; }
   if(key == "P_Mfi") { s.P_Mfi = (int)StringToInteger(val); return true; }
   if(key == "P_PsarMax") { s.P_PsarMax = StringToDouble(val); return true; }
   if(key == "P_PsarStep") { s.P_PsarStep = StringToDouble(val); return true; }
   if(key == "P_Rsi") { s.P_Rsi = (int)StringToInteger(val); return true; }
   if(key == "P_StoD") { s.P_StoD = (int)StringToInteger(val); return true; }
   if(key == "P_StoK") { s.P_StoK = (int)StringToInteger(val); return true; }
   if(key == "P_StoSlow") { s.P_StoSlow = (int)StringToInteger(val); return true; }
   if(key == "PhaseDetectionEnabled") { s.PhaseDetectionEnabled = SEA_CS_ParseBool(val); return true; }
   if(key == "PriceExtAtrPeriod") { s.PriceExtAtrPeriod = (int)StringToInteger(val); return true; }
   if(key == "PriceExtFilterEnabled") { s.PriceExtFilterEnabled = SEA_CS_ParseBool(val); return true; }
   if(key == "PriceExtMaxATR") { s.PriceExtMaxATR = StringToDouble(val); return true; }
   if(key == "PriceExtRefEma") { s.PriceExtRefEma = (int)StringToInteger(val); return true; }
   if(key == "RequireMinPhaseConfirm") { s.RequireMinPhaseConfirm = SEA_CS_ParseBool(val); return true; }
   if(key == "RequirePriceCross") { s.RequirePriceCross = SEA_CS_ParseBool(val); return true; }
   if(key == "Require_Progressive_Momentum") { s.Require_Progressive_Momentum = SEA_CS_ParseBool(val); return true; }
   if(key == "RsiMode") { s.RsiMode = (ERsiMode)(int)StringToInteger(val); return true; }
   if(key == "SlopeLookbackBars") { s.SlopeLookbackBars = (int)StringToInteger(val); return true; }
   if(key == "StoMode") { s.StoMode = (EStochMode)(int)StringToInteger(val); return true; }
   if(key == "T_Adx") { s.T_Adx = StringToDouble(val); return true; }
   if(key == "T_MfiOB") { s.T_MfiOB = StringToDouble(val); return true; }
   if(key == "T_MfiOS") { s.T_MfiOS = StringToDouble(val); return true; }
   if(key == "T_RsiOB") { s.T_RsiOB = StringToDouble(val); return true; }
   if(key == "T_RsiOS") { s.T_RsiOS = StringToDouble(val); return true; }
   if(key == "T_StoOB") { s.T_StoOB = StringToDouble(val); return true; }
   if(key == "T_StoOS") { s.T_StoOS = StringToDouble(val); return true; }
   if(key == "TrailMode") { s.TrailMode = (ETrailingMode)(int)StringToInteger(val); return true; }
   if(key == "VPRR_Enabled") { s.VPRR_Enabled = SEA_CS_ParseBool(val); return true; }
   if(key == "VPRR_ExternalSymbol") { s.VPRR_ExternalSymbol = val; return true; }
   if(key == "VPRR_MinRatio") { s.VPRR_MinRatio = StringToDouble(val); return true; }
   if(key == "VPRR_MinRatio_M") { s.VPRR_MinRatio_M = StringToDouble(val); return true; }
   if(key == "VPRR_MinRatio_S") { s.VPRR_MinRatio_S = StringToDouble(val); return true; }
   if(key == "VPRR_MinRatio_W") { s.VPRR_MinRatio_W = StringToDouble(val); return true; }
   if(key == "VPRR_MinRecoveryBars") { s.VPRR_MinRecoveryBars = (int)StringToInteger(val); return true; }
   if(key == "VPRR_RecoveryBars") { s.VPRR_RecoveryBars = (int)StringToInteger(val); return true; }
   if(key == "VPRR_VolumeType") { s.VPRR_VolumeType = (int)StringToInteger(val); return true; }
   if(key == "VRC_Lookback") { s.VRC_Lookback = (int)StringToInteger(val); return true; }
   if(key == "VRC_LowThreshold") { s.VRC_LowThreshold = StringToDouble(val); return true; }
   if(key == "VRC_RefreshSec") { s.VRC_RefreshSec = (int)StringToInteger(val); return true; }
   if(key == "Vote_AllowPsarFlip") { s.Vote_AllowPsarFlip = SEA_CS_ParseBool(val); return true; }
   if(key == "Vote_EvalShift") { s.Vote_EvalShift = (int)StringToInteger(val); return true; }
   if(key == "Vote_PsarFlipDelay") { s.Vote_PsarFlipDelay = (int)StringToInteger(val); return true; }
   if(key == "Vote_PsarFlipDelay_M") { s.Vote_PsarFlipDelay_M = (int)StringToInteger(val); return true; }
   if(key == "Vote_PsarFlipDelay_S") { s.Vote_PsarFlipDelay_S = (int)StringToInteger(val); return true; }
   if(key == "Vote_PsarFlipDelay_W") { s.Vote_PsarFlipDelay_W = (int)StringToInteger(val); return true; }
   if(key == "ma_h_shift") { s.ma_h_shift = (int)StringToInteger(val); return true; }
   if(key == "ma_v_shift") { s.ma_v_shift = (int)StringToInteger(val); return true; }
   return false;
}

//+------------------------------------------------------------------+
//| READER  -  load snapshot and overlay onto ST_Settings.            |
//|                                                                  |
//| Reads the file ONCE, buffering keys/values into parallel arrays. |
//| Performs the staleness check BEFORE any field is touched on s,   |
//| so a stale file never partially mutates the scanner's settings.  |
//|                                                                  |
//| Returns:                                                          |
//|   0  = OK, snapshot applied (out_keys_applied = N)                |
//|   1  = missing (file does not exist or open failed)               |
//|   2  = stale  (older than max_stale_sec; NOTHING applied)         |
//|                                                                  |
//| out_age_sec      = age of snapshot in seconds (vs TimeCurrent),  |
//|                    or -1 if no SnapshotEpoch header present.    |
//| out_keys_applied = number of recognized keys parsed & applied.   |
//|                    0 on missing/stale returns.                    |
//| out_diag         = short human-readable status string.            |
//|                                                                  |
//| When max_stale_sec <= 0, staleness is not enforced.               |
//|                                                                  |
//| The reader OVERLAYS values on top of whatever is already in s.   |
//| Intended call order in the scanner:                              |
//|     BuildSettings(s);                  // scanner defaults        |
//|     SEA_ReadConfigSnapshot(s, ...);    // overlay EA snapshot     |
//| Keys absent from the snapshot retain the scanner's defaults.     |
//+------------------------------------------------------------------+
int SEA_ReadConfigSnapshot(ST_Settings &s,
                            const int     max_stale_sec,
                            int          &out_age_sec,
                            int          &out_keys_applied,
                            string       &out_diag)
{
   out_age_sec      = -1;
   out_keys_applied =  0;
   out_diag         = "";

   string fname = SEA_ConfigSync_Filename(_Symbol, (ENUM_TIMEFRAMES)_Period);

   if(!FileIsExist(fname)) {
      out_diag = "missing: " + fname;
      return 1;
   }

   uint flags = FILE_TXT | FILE_READ | FILE_UNICODE | FILE_SHARE_READ | FILE_SHARE_WRITE;
   int h = FileOpen(fname, flags);
   if(h == INVALID_HANDLE) {
      out_diag = StringFormat("FileOpen failed err=%d for %s", GetLastError(), fname);
      return 1;
   }

   // --- Pass 1: read every line into parallel string buffers ---
   string keys_buf[];
   string vals_buf[];
   ArrayResize(keys_buf, 0);
   ArrayResize(vals_buf, 0);
   int epoch = 0;

   while(!FileIsEnding(h)) {
      string line = FileReadString(h);
      line = SEA_CS_Trim(line);
      if(line == "") continue;

      // header lines: scan for "SnapshotEpoch=<int>" wherever it appears
      if(StringGetCharacter(line, 0) == '#') {
         int hpos = StringFind(line, "SnapshotEpoch=");
         if(hpos >= 0) {
            string sval = StringSubstr(line, hpos + StringLen("SnapshotEpoch="));
            epoch = (int)StringToInteger(SEA_CS_Trim(sval));
         }
         continue;
      }

      int eq = StringFind(line, "=");
      if(eq <= 0) continue;
      string key = SEA_CS_Trim(StringSubstr(line, 0, eq));
      string val = SEA_CS_Trim(StringSubstr(line, eq + 1));

      int sz = ArraySize(keys_buf);
      ArrayResize(keys_buf, sz + 1);
      ArrayResize(vals_buf, sz + 1);
      keys_buf[sz] = key;
      vals_buf[sz] = val;
   }
   FileClose(h);

   // --- Staleness check BEFORE mutating s ---
   if(epoch > 0) {
      int now_sec = (int)TimeCurrent();
      out_age_sec = now_sec - epoch;
      if(max_stale_sec > 0 && out_age_sec > max_stale_sec) {
         out_diag = StringFormat("stale: age=%ds > max=%ds", out_age_sec, max_stale_sec);
         return 2;
      }
   }

   // --- Pass 2: apply the buffered key/value pairs to s ---
   int applied = 0;
   int unknown = 0;
   int total   = ArraySize(keys_buf);
   for(int i = 0; i < total; i++) {
      if(SEA_CS_ApplyKey(s, keys_buf[i], vals_buf[i]))
         applied++;
      else
         unknown++;
   }

   out_keys_applied = applied;
   out_diag = StringFormat("ok: %d applied, %d unknown, age=%ds", applied, unknown, out_age_sec);
   return 0;
}

//+------------------------------------------------------------------+
//| End of SEA_ConfigSync.mqh                                         |
//+------------------------------------------------------------------+

