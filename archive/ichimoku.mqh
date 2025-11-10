//+------------------------------------------------------------------+
//| ichimoku.mqh - simple Ichimoku helper                            |
//+------------------------------------------------------------------+
/*
  Provides:
    void Ichimoku_Init();
    bool Ichimoku_GetValues(symbol, tf, tenkan,kijun,senkouB, shift, &tenkan,&kijun,&senkouA,&senkouB,&chikou)
*/
void Ichimoku_Init()
  {
   // no-op for now
  }

bool Ichimoku_GetValues(const string symbol, const ENUM_TIMEFRAMES tf, const int tenkan, const int kijun, const int senkouB_param, const int shift,
                        double &tenkan_v, double &kijun_v, double &senkouA_v, double &senkouB_v, double &chikou_v)
  {
   int handle = iIchimoku(symbol, tf, tenkan, kijun, senkouB_param);
   if(handle==INVALID_HANDLE) return(false);

   double buf[];
   // Tenkan (buffer 0)
   if(CopyBuffer(handle,0,shift,1,buf) <= 0) { IndicatorRelease(handle); return(false); }
   tenkan_v = buf[0];
   // Kijun (buffer 1)
   if(CopyBuffer(handle,1,shift,1,buf) <= 0) { IndicatorRelease(handle); return(false); }
   kijun_v = buf[0];
   // Senkou A (buffer 2)
   if(CopyBuffer(handle,2,shift,1,buf) <= 0) { IndicatorRelease(handle); return(false); }
   senkouA_v = buf[0];
   // Senkou B (buffer 3)
   if(CopyBuffer(handle,3,shift,1,buf) <= 0) { IndicatorRelease(handle); return(false); }
   senkouB_v = buf[0];
   // Chikou: approximate using close shifted by tenkan period
   int idx = shift + tenkan;
   chikou_v = iClose(symbol, tf, idx);

   IndicatorRelease(handle);
   return(true);
  }
//+------------------------------------------------------------------+