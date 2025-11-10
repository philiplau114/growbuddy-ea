//+------------------------------------------------------------------+
//| entry_engine.mqh - combine Ichimoku + ADX into entry signal      |
//| Updated: Ichimoku Advance (type 2) includes Kumo, Future twist,  |
//|         and Chikou confirmations per spec                        |
//+------------------------------------------------------------------+
#include "..\\indicators\\ichimoku.mqh"
#include "..\\indicators\\adx.mqh"

// returns 1=buy, -1=sell, 0=none
int Entry_GetSignal(const string symbol, const ENUM_TIMEFRAMES tf)
  {
   int ichSignal = 0;

   if(Ichimoku_Active)
     {
      // read current signal bar values
      double tenkan=0, kijun=0, sa=0, sb=0, ch=0;
      bool ok = Ichimoku_GetValues(symbol, Ichim_TimeFrame, Ichim_TenkanSen, Ichim_KijuSen, Ichim_SenkouB, Ichim_SignalBars, tenkan, kijun, sa, sb, ch);
      if(!ok) return 0;

      // also read previous bar (for crosses / future twist checks)
      double tenkan_prev=0, kijun_prev=0, sa_prev=0, sb_prev=0, ch_prev=0;
      Ichimoku_GetValues(symbol, Ichim_TimeFrame, Ichim_TenkanSen, Ichim_KijuSen, Ichim_SenkouB, Ichim_SignalBars+1, tenkan_prev, kijun_prev, sa_prev, sb_prev, ch_prev);

      switch(Ichim_Signal_Type)
        {
         case 0: // Tenkan-Kijun Cross (basic)
           {
            if(tenkan_prev <= kijun_prev && tenkan > kijun) ichSignal = 1;
            else if(tenkan_prev >= kijun_prev && tenkan < kijun) ichSignal = -1;
           }
           break;

         case 2: // Tenkan-Kijun Up & Down (Advance) - stricter conditions
           {
            // Basic direction based on Tenkan vs Kijun
            if(tenkan > kijun)
              {
               // require Tenkan above Kumo (both Senkou spans) and current Kumo bullish (sa > sb)
               double topKumo = MathMax(sa, sb);
               bool tenkan_above_kumo = (tenkan > topKumo);
               bool kumo_bullish = (sa > sb);

               // future Kumo twist check: if previous plotted Kumo was not bullish but now bullish -> twist
               bool future_twist = (sa > sb) && (sa_prev <= sb_prev);

               // chikou confirmation (chikou plotted)
               bool chikou_conf = (ch > topKumo);

               if(tenkan_above_kumo && kumo_bullish && chikou_conf)
                 {
                  ichSignal = 1;
                 }
               else if(tenkan_above_kumo && kumo_bullish && future_twist)
                 {
                  // allow if future twist confirms
                  ichSignal = 1;
                 }
               else
                 {
                  // not strict enough -> no signal
                  ichSignal = 0;
                 }
              }
            else if(tenkan < kijun)
              {
               double bottomKumo = MathMin(sa, sb);
               bool tenkan_below_kumo = (tenkan < bottomKumo);
               bool kumo_bearish = (sa < sb);
               bool future_twist_bear = (sa < sb) && (sa_prev >= sb_prev);
               bool chikou_conf_sell = (ch < bottomKumo);

               if(tenkan_below_kumo && kumo_bearish && chikou_conf_sell)
                 {
                  ichSignal = -1;
                 }
               else if(tenkan_below_kumo && kumo_bearish && future_twist_bear)
                 {
                  ichSignal = -1;
                 }
               else
                 {
                  ichSignal = 0;
                 }
              }
           }
           break;

         case 3: // Kumo Breakout (simple)
           {
            double open = iOpen(symbol, Ichim_TimeFrame, Ichim_SignalBars);
            double close = iClose(symbol, Ichim_TimeFrame, Ichim_SignalBars);
            if(open < sa && close > sa) ichSignal = 1;
            else if(open > sa && close < sa) ichSignal = -1;
           }
           break;

         default:
           ichSignal = 0;
        }

      if(Ichim_ReverseSignal) ichSignal = -ichSignal;
     }

   // ADX filter / overrides (if enabled)
   if(ADX_Active)
     {
      double adx = ADX_GetMain(symbol, ADXTimeFrame, ADXPeriod, ADXSignalBars);
      if(ADX_Filter_Type==0 && adx < ADX_BUY_Level) return 0;
      if(ADX_Filter_Type==1 && adx > ADX_SELL_Level) return 0;

      if(ADX_Entry_Type==1)
        {
         double dp_now=0, dm_now=0, dp_prev=0, dm_prev=0;
         if(ADX_GetDI(symbol,ADXTimeFrame,ADXPeriod,ADXSignalBars,dp_now,dm_now) && ADX_GetDI(symbol,ADXTimeFrame,ADXPeriod,ADXSignalBars+1,dp_prev,dm_prev))
           {
            if(dp_prev <= dm_prev && dp_now > dm_now) return 1;
            if(dp_prev >= dm_prev && dp_now < dm_now) return -1;
           }
        }
      else if(ADX_Entry_Type==0)
        {
         int di = ADX_GetDI_Signal(symbol,ADXTimeFrame,ADXPeriod,ADXSignalBars);
         if(di==1) return 1;
         if(di==-1) return -1;
        }
     }

   return ichSignal;
  }
//+------------------------------------------------------------------+