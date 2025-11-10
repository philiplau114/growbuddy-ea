//+------------------------------------------------------------------+
//| common.mqh - helpers for GrowBuddy                               |
//| - Keeps original helpers (PrintArrayDouble, TimeToOpenInitial)   |
//| - Adds decision/plan id generators, config serialization and     |
//|   small JSON builders used by logging/trade helpers               |
//+------------------------------------------------------------------+
#property strict

// NOTE: This header expects the EA to define its input variables (InitialLots, StopLoss, ...)
/* -------------------- Original helpers -------------------- */
void PrintArrayDouble(const double &arr[])
  {
   string s="";
   for(int i=0;i<ArraySize(arr);i++) s += DoubleToString(arr[i],_Digits) + ",";
   Print(s);
  }

// TimeToOpenInitial - basic gate for allowing initial opens
// Returns true to allow opening initial trade, false to block.
bool TimeToOpenInitial()
{
   // global switch: stop EA
   if(StopEA) return(false);

   // basic checks: symbol trading properties
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if(minLot <= 0 || step <= 0)
   {
      PrintFormat("TimeToOpenInitial: symbol volume info missing for %s (min=%.6f step=%.6f). Blocking open.", _Symbol, minLot, step);
      return(false);
   }

   // conservative free margin check
   double lotsToCheck = MathMax(InitialLots, minLot);
   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);

   if(freeMargin <= 0.0)
   {
      Print("TimeToOpenInitial: Account free margin unknown - proceeding cautiously.");
   }
   else
   {
      double conservativeNeeded = 100.0 * lotsToCheck;
      if(freeMargin < conservativeNeeded)
      {
         PrintFormat("TimeToOpenInitial: freeMargin(%.2f) < conservativeNeeded(%.2f) - blocking open.", freeMargin, conservativeNeeded);
         return(false);
      }
   }

   return(true);
}

/* -------------------- Moved helpers -------------------- */

// TrimString: remove leading/trailing whitespace characters
string TrimString(const string s)
{
   string res = s;
   while(StringLen(res) > 0)
     {
      ushort ch = StringGetCharacter(res,0);
      if(ch==32 || ch==9 || ch==10 || ch==13) res = StringSubstr(res,1);
      else break;
     }
   while(StringLen(res) > 0)
     {
      int l = StringLen(res);
      ushort ch = StringGetCharacter(res,l-1);
      if(ch==32 || ch==9 || ch==10 || ch==13) res = StringSubstr(res,0,l-1);
      else break;
     }
   return(res);
}

// IsWithinTradeTime: parse "HH:MM - HH:MM" ranges and check current time
bool IsWithinTradeTime(const string range)
{
   if(StringLen(range) < 7) return(true);
   int pos = StringFind(range,"-");
   if(pos == -1) return(true);
   string left = TrimString(StringSubstr(range,0,pos));
   string right = TrimString(StringSubstr(range,pos+1));
   if(StringLen(left) < 5 || StringLen(right) < 5) return(true);
   int h1 = (int)StringToInteger(StringSubstr(left,0,2));
   int m1 = (int)StringToInteger(StringSubstr(left,3,2));
   int h2 = (int)StringToInteger(StringSubstr(right,0,2));
   int m2 = (int)StringToInteger(StringSubstr(right,3,2));
   datetime now = TimeCurrent();
   MqlDateTime dt; TimeToStruct(now, dt);
   int curMinutes = dt.hour*60 + dt.min;
   int fromMinutes = h1*60 + m1;
   int toMinutes = h2*60 + m2;
   if(fromMinutes <= toMinutes)
     return (curMinutes >= fromMinutes && curMinutes <= toMinutes);
   else
     return (curMinutes >= fromMinutes || curMinutes <= toMinutes);
}

// CalculateInitialLot: mirror original logic
double CalculateInitialLot()
{
   if(LotsType==0) return(InitialLots);
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double calc = (bal / XBalance) * LotsizePerXBalance;
   double step = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   if(step<=0) step = 0.01;
   double lots = MathMax(calc,InitialLots);
   lots = MathFloor(lots/step)*step;
   if(lots<=0) lots = InitialLots;
   return(lots);
}

// ComputeInitialSLPrice: compute SL price from StopLoss (points)
double ComputeInitialSLPrice(const int dir)
{
   if(StopLoss == 0) return(0.0);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double basePrice = (dir==1) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double delta = (double)StopLoss * point;
   double sl_price = (dir==1) ? basePrice - delta : basePrice + delta;
   sl_price = NormalizeDouble(sl_price, digits);
   return(sl_price);
}

// ComputeInitialTPPrice: compute TP price either points-based or currency value based
double ComputeInitialTPPrice(const int dir, const double lot)
{
   if(TakeProfit == 0) return(0.0);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double basePrice = (dir==1) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if(TP_Type_Initial == 0)
     {
      double delta = (double)TakeProfit * point;
      double tp_price = (dir==1) ? basePrice + delta : basePrice - delta;
      return(NormalizeDouble(tp_price, digits));
     }
   else
     {
      double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      double point_local = point;
      if(tick_value > 0 && tick_size > 0)
        {
         double value_per_point_per_lot = tick_value / (tick_size / point_local);
         double value_per_point_for_lot = value_per_point_per_lot * lot;
         if(value_per_point_for_lot > 0.0)
           {
            double points_needed = (double)TakeProfit / value_per_point_for_lot;
            double delta = points_needed * point_local;
            double tp_price = (dir==1) ? basePrice + delta : basePrice - delta;
            return(NormalizeDouble(tp_price, digits));
           }
        }
      PrintFormat("ComputeInitialTPPrice: cannot compute currency-based TP for %s (tick info missing).", _Symbol);
      return(0.0);
     }
}

/* -------------------- Logging / JSON helpers -------------------- */

// Generate a deterministic decision id using TF candle iTime + a counter
// Example: 2025-09-01T00:00:00_1
string GenerateDecisionId(datetime tf_iTime, int counter)
{
   string ts = TimeToString(tf_iTime, TIME_DATE|TIME_SECONDS);
   return ts + "_" + IntegerToString(counter);
}

// Generate plan id from decision id and plan counter
// Example: 2025-09-01T00:00:00_1_p0
string GeneratePlanId(const string decision_id, int planCounter)
{
   return decision_id + "_p" + IntegerToString(planCounter);
}

// Safe JSON escape for a string (very small helper)
string JsonEscape(const string s)
{
   string out = s;
   StringReplace(out, "\\", "\\\\");
   StringReplace(out, "\"", "\\\"");
   return out;
}

// Build a basic config JSON of important EA inputs + symbol props.
string SerializeInputsToJson()
{
   double vol_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double vol_min  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tick_size  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   string json = "{";
   json += "\"Ichim_TenkanSen\":" + IntegerToString(Ichim_TenkanSen) + ",";
   json += "\"Ichim_KijuSen\":" + IntegerToString(Ichim_KijuSen) + ",";
   json += "\"Ichim_SenkouB\":" + IntegerToString(Ichim_SenkouB) + ",";
   json += "\"InitialLots\":" + DoubleToString(InitialLots,6) + ",";
   json += "\"LotsType\":" + IntegerToString(LotsType) + ",";
   json += "\"TakeProfit\":" + IntegerToString((int)TakeProfit) + ",";
   json += "\"StopLoss\":" + IntegerToString((int)StopLoss) + ",";
   json += "\"MagicNumber\":" + IntegerToString(MagicNumber) + ",";
   json += "\"SYMBOL_VOLUME_STEP\":" + DoubleToString(vol_step,6) + ",";
   json += "\"SYMBOL_VOLUME_MIN\":" + DoubleToString(vol_min,6) + ",";
   json += "\"SYMBOL_DIGITS\":" + IntegerToString(digits) + ",";
   json += "\"SYMBOL_POINT\":" + DoubleToString(point,6) + ",";
   json += "\"SYMBOL_TRADE_TICK_VALUE\":" + DoubleToString(tick_value,6) + ",";
   json += "\"SYMBOL_TRADE_TICK_SIZE\":" + DoubleToString(tick_size,6) + ",";
   json += "\"DebugMode\":" + (DebugMode ? "true" : "false") + ",";
   json += "\"Grid_Active\":" + IntegerToString(Grid_Active) + ",";
   json += "\"Hedge_Active\":" + IntegerToString(Hedge_Active) + ",";
   json += "\"DontOpenTradeInCandle\":" + (DontOpenTradeInCandle ? "true" : "false");
   json += "}";

   return json;
}

// Helper: build a compact JSON for effective_params in plans
string BuildEffectiveParamsJson(int lotsType, double initialLots, double calcLot, const string extra = "{}")
{
   string s = "{";
   s += "\"LotsType\":" + IntegerToString(lotsType) + ",";
   s += "\"InitialLots\":" + DoubleToString(initialLots,6) + ",";
   s += "\"CalculatedLot\":" + DoubleToString(calcLot,6) + ",";
   s += "\"extra\":" + extra;
   s += "}";
   return s;
}

// Small helper to produce a request JSON for market order
string BuildMarketRequestJson(double volume, double sl, double tp, const string comment)
{
   string j = "{";
   j += "\"type\":\"market\",";
   j += "\"volume\":" + DoubleToString(volume,6) + ",";
   j += "\"sl\":" + DoubleToString(sl,6) + ",";
   j += "\"tp\":" + DoubleToString(tp,6) + ",";
   j += "\"comment\":\"" + JsonEscape(comment) + "\"";
   j += "}";
   return j;
}

// Small helper to produce a request JSON for pending order
string BuildPendingRequestJson(double volume, double price, double sl, double tp, const string comment)
{
   string j = "{";
   j += "\"type\":\"pending\",";
   j += "\"volume\":" + DoubleToString(volume,6) + ",";
   j += "\"price\":" + DoubleToString(price, (int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS)) + ",";
   j += "\"sl\":" + DoubleToString(sl,6) + ",";
   j += "\"tp\":" + DoubleToString(tp,6) + ",";
   j += "\"comment\":\"" + JsonEscape(comment) + "\"";
   j += "}";
   return j;
}