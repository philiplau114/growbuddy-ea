//+------------------------------------------------------------------+
//| adx.mqh - ADX and DI helper                                      |
//+------------------------------------------------------------------+
void ADX_Init()
  {
   // no-op
  }

double ADX_GetMain(const string symbol, const ENUM_TIMEFRAMES tf, const int period, const int shift=0)
  {
   int handle = iADX(symbol, tf, period);
   if(handle==INVALID_HANDLE) return(0.0);
   double buf[];
   if(CopyBuffer(handle,0,shift,1,buf) <= 0) { IndicatorRelease(handle); return(0.0); }
   double v = buf[0];
   IndicatorRelease(handle);
   return(v);
  }

bool ADX_GetDI(const string symbol, const ENUM_TIMEFRAMES tf, const int period, const int shift, double &diPlus, double &diMinus)
  {
   int handle = iADX(symbol, tf, period);
   if(handle==INVALID_HANDLE) return(false);
   double buf1[], buf2[];
   if(CopyBuffer(handle,1,shift,1,buf1) <= 0) { IndicatorRelease(handle); return(false); }
   if(CopyBuffer(handle,2,shift,1,buf2) <= 0) { IndicatorRelease(handle); return(false); }
   diPlus = buf1[0];
   diMinus = buf2[0];
   IndicatorRelease(handle);
   return(true);
  }

int ADX_GetDI_Signal(const string symbol, const ENUM_TIMEFRAMES tf, const int period, const int shift)
  {
   double dp, dm;
   if(!ADX_GetDI(symbol,tf,period,shift,dp,dm)) return(0);
   if(dp>dm) return(1);
   if(dm>dp) return(-1);
   return(0);
  }
//+------------------------------------------------------------------+