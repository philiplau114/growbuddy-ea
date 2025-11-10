//+------------------------------------------------------------------+
//| entry_engine_refactored.mqh                                      |
//| Ichimoku-based entry engine using built-in iIchimoku buffers     |
//| as single source of truth. No fallback.                          |
//+------------------------------------------------------------------+
#include "..\\indicators\\adx.mqh"   // ADX helper (must exist in project)

// Global handle for built-in Ichimoku indicator
int g_ichimoku_indicator_handle = INVALID_HANDLE;

// Initialize entry engine: create built-in iIchimoku handle and add to chart.
// If creation fails, the EA will print diagnostics and stop execution.
void EntryEngine_Init()
  {
   // create built-in Ichimoku handle with EA inputs (Ichim_* variables are declared in the EA)
   g_ichimoku_indicator_handle = iIchimoku(_Symbol, Ichim_TimeFrame, Ichim_TenkanSen, Ichim_KijuSen, Ichim_SenkouB);

   if(g_ichimoku_indicator_handle == INVALID_HANDLE)
     {
      int err = GetLastError();
      PrintFormat("EntryEngine_Init: ERROR creating built-in iIchimoku for %s TF=%d Tenkan=%d Kijun=%d SenkouB=%d. GetLastError=%d",
                  _Symbol, (int)Ichim_TimeFrame, Ichim_TenkanSen, Ichim_KijuSen, Ichim_SenkouB, err);
      long bars = iBars(_Symbol, Ichim_TimeFrame);
      PrintFormat("EntryEngine_Init: diagnostic: available bars on TF %d = %d", (int)Ichim_TimeFrame, (int)bars);
      Print("EntryEngine_Init: built-in iIchimoku handle creation failed -> stopping EA to ensure parity with chart indicator.");
      ExpertRemove(); // stop EA
      return;
     }

   // Best-effort: add built-in indicator to the chart for visual parity with CAP
   long chart_id = ChartID();
   if(chart_id != 0)
     {
      bool added = ChartIndicatorAdd(chart_id, 0, g_ichimoku_indicator_handle);
      if(!added)
        {
         if(DebugMode) PrintFormat("EntryEngine_Init: ChartIndicatorAdd returned false for handle=%d (chart may not accept programmatic indicators)", g_ichimoku_indicator_handle);
        }
      else
        {
         if(DebugMode) PrintFormat("EntryEngine_Init: ChartIndicatorAdd succeeded for handle=%d", g_ichimoku_indicator_handle);
        }
     }

   if(DebugMode)
      PrintFormat("EntryEngine_Init: built-in iIchimoku handle=%d created for TF=%d Tenkan=%d Kijun=%d SenkouB=%d",
                  g_ichimoku_indicator_handle, (int)Ichim_TimeFrame, Ichim_TenkanSen, Ichim_KijuSen, Ichim_SenkouB);
  }

// Deinitialize entry engine: release built-in handle
void EntryEngine_Deinit()
  {
   if(g_ichimoku_indicator_handle != INVALID_HANDLE)
     {
      IndicatorRelease(g_ichimoku_indicator_handle);
      if(DebugMode) PrintFormat("EntryEngine_Deinit: released built-in iIchimoku handle=%d", g_ichimoku_indicator_handle);
      g_ichimoku_indicator_handle = INVALID_HANDLE;
     }
  }

// Replace IchimokuAdvanceSignal with this state-based implementation
// Uses built-in iIchimoku buffers: 0=Tenkan,1=Kijun,2=SenkouA,3=SenkouB,4=Chikou
int IchimokuAdvanceSignal(const int signalShift)
  {
   if(g_ichimoku_indicator_handle == INVALID_HANDLE)
     {
      if(DebugMode) Print("IchimokuAdvanceSignal: built-in ichimoku handle invalid");
      return 0;
     }

   double bufTenkan[], bufKijun[], bufSA[], bufSB[];
   int c0 = CopyBuffer(g_ichimoku_indicator_handle, 0, signalShift, 1, bufTenkan);
   int c1 = CopyBuffer(g_ichimoku_indicator_handle, 1, signalShift, 1, bufKijun);
   int c2 = CopyBuffer(g_ichimoku_indicator_handle, 2, signalShift, 1, bufSA);
   int c3 = CopyBuffer(g_ichimoku_indicator_handle, 3, signalShift, 1, bufSB);

   if(c0<=0 || c1<=0 || c2<=0 || c3<=0)
     {
      if(DebugMode) PrintFormat("IchimokuAdvanceSignal: CopyBuffer failed shift=%d c0..c3=%d,%d,%d,%d", signalShift, c0, c1, c2, c3);
      return 0;
     }

   double tenkan = bufTenkan[0];
   double kijun  = bufKijun[0];
   double sa     = bufSA[0];
   double sb     = bufSB[0];

   bool tenkan_above_kumo = (tenkan > MathMax(sa, sb));
   bool tenkan_below_kumo = (tenkan < MathMin(sa, sb));
   bool kumo_bullish = (sa > sb);
   bool kumo_bearish = (sa < sb);

   if(DebugMode)
     PrintFormat("IchimokuAdvanceSignal(STATE): shift=%d Tenkan=%.6f Kijun=%.6f SA=%.6f SB=%.6f aboveKumo=%s belowKumo=%s kumoBull=%s",
                 signalShift, tenkan, kijun, sa, sb,
                 (tenkan_above_kumo?"true":"false"), (tenkan_below_kumo?"true":"false"), (kumo_bullish?"true":"false"));

   // Your spec (state-based): no cross required
   if(tenkan > kijun && tenkan_above_kumo && kumo_bullish) return 1;
   if(tenkan < kijun && tenkan_below_kumo && kumo_bearish) return -1;
   return 0;
  }

// Entry_GetSignal_Refactored: ichimoku first (built-in), then ADX filter if enabled
int Entry_GetSignal_Refactored(const string symbol, const ENUM_TIMEFRAMES tf)
  {
   int ichSignal = 0;
   if(Ichimoku_Active)
     ichSignal = IchimokuAdvanceSignal(Ichim_SignalBars);

   // create decision_id and log signal
   // compute tf candle iTime deterministically
   datetime tf_candle = iTime(symbol, tf, Ichim_SignalBars);
   string decision_id = TimeToString(tf_candle, TIME_DATE|TIME_SECONDS) + "_" + IntegerToString(g_decision_counter++);
   g_last_decision_id = decision_id;

   // try to capture indicator values for logging
   double tenkan=0, kijun=0, sa=0, sb=0, chikou=0;
   double bufTenkan[], bufKijun[], bufSA[], bufSB[], bufChikou[];
   int ok0 = CopyBuffer(g_ichimoku_indicator_handle, 0, Ichim_SignalBars, 1, bufTenkan);
   int ok1 = CopyBuffer(g_ichimoku_indicator_handle, 1, Ichim_SignalBars, 1, bufKijun);
   int ok2 = CopyBuffer(g_ichimoku_indicator_handle, 2, Ichim_SignalBars, 1, bufSA);
   int ok3 = CopyBuffer(g_ichimoku_indicator_handle, 3, Ichim_SignalBars, 1, bufSB);
   int ok4 = CopyBuffer(g_ichimoku_indicator_handle, 4, Ichim_SignalBars, 1, bufChikou);
   if(ok0>0 && ok1>0 && ok2>0 && ok3>0 && ok4>0)
     {
      tenkan = bufTenkan[0];
      kijun  = bufKijun[0];
      sa     = bufSA[0];
      sb     = bufSB[0];
      chikou = bufChikou[0];
     }

   string ts = TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS);
   string tf_i = TimeToString(tf_candle, TIME_DATE|TIME_SECONDS);
   string reason_json = "[]";
   if(ichSignal == 1) reason_json = "[\"Tenkan>Kijun\",\"TenkanAboveKumo\",\"KumoBullish\"]";
   else if(ichSignal == -1) reason_json = "[\"Tenkan<Kijun\",\"TenkanBelowKumo\",\"KumoBearish\"]";

   // blocked reasons empty for now
   string blocked_json = "[]";
   string extra_json = "{}";

   // log the signal snapshot (best-effort)
   LOG_InsertSignal(g_run_key, decision_id, ts, tf_i, symbol, EnumToString(tf), tenkan, kijun, sa, sb, chikou, ichSignal, reason_json, blocked_json, extra_json);

   if(ichSignal != 0 && ADX_Active)
     {
      double adx = ADX_GetMain(symbol, ADXTimeFrame, ADXPeriod, ADXSignalBars);
      if(ADX_Filter_Type==0 && adx < ADX_BUY_Level)
        {
         if(DebugMode) PrintFormat("Entry_GetSignal_Refactored: ADX blocked buy (ADX=%.2f < %.2f)", adx, ADX_BUY_Level);
         return 0;
        }
      if(ADX_Filter_Type==1 && adx > ADX_SELL_Level)
        {
         if(DebugMode) PrintFormat("Entry_GetSignal_Refactored: ADX blocked sell (ADX=%.2f > %.2f)", adx, ADX_SELL_Level);
         return 0;
        }
     }

   if(Ichim_ReverseSignal) ichSignal = -ichSignal;

   if(DebugMode) PrintFormat("Entry_GetSignal_Refactored: ichSignal=%d (tf=%d shift=%d) decision_id=%s", ichSignal, (int)tf, Ichim_SignalBars, g_last_decision_id);

   return ichSignal;
  }
//+------------------------------------------------------------------+