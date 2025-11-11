// hedge_utils.mqh
// Utility helpers for Hedge (Zone Recovery) MVP
// Path:
// C:\Users\Administrator.PHILIP-BACKTEST\AppData\Roaming\MetaQuotes\Terminal\AE2CC2E013FDE1E3CDF010AA51C60400\MQL5\Experts\Advisors\growbuddy\hedge\hedge_utils.mqh

#property copyright "GrowBuddy"
#property version   "1.0"

// Trim whitespace from both ends
string HB_Trim(const string s)
{
   int i = 0;
   int j = StringLen(s) - 1;
   while(i <= j && StringGetCharacter(s, i) <= 32) i++;
   while(j >= i && StringGetCharacter(s, j) <= 32) j--;
   if(i == 0 && j == StringLen(s) - 1) return s;
   return StringSubstr(s, i, j - i + 1);
}

// Parse semicolon separated list of numbers into dynamic array (out passed by reference)
void HB_ParseDoublesList(const string src, double &out[])
{
   ArrayResize(out, 0);
   string s = HB_Trim(src);
   if(StringLen(s) == 0) return;

   int pos = 0;
   string part = "";
   while(true)
   {
      int sep = StringFind(s, ";", pos);
      if(sep == -1)
      {
         // last token
         part = HB_Trim(StringSubstr(s, pos));
         if(StringLen(part) > 0)
         {
            double v = StringToDouble(part);
            int n = ArraySize(out);
            ArrayResize(out, n+1);
            out[n] = v;
         }
         break;
      }
      else
      {
         part = HB_Trim(StringSubstr(s, pos, sep - pos));
         if(StringLen(part) > 0)
         {
            double v = StringToDouble(part);
            int n = ArraySize(out);
            ArrayResize(out, n+1);
            out[n] = v;
         }
         pos = sep + 1;
      }
   }
}

// Safe array get with fallback to last element
double HB_GetArrayValueOrLast(double &arr[], int idx, double fallback)
{
   int n = ArraySize(arr);
   if(n == 0) return fallback;
   if(idx < 0) return arr[0];
   if(idx < n) return arr[idx];
   return arr[n-1];
}

// Round lot to step and clamp to min/max
double HB_NormalizeLot(double lot, double minLot, double maxLot, double lotStep)
{
   if(lotStep <= 0.0) lotStep = 0.01;
   // Avoid division by zero and invalid lot
   if(lot <= 0.0) lot = minLot;
   double steps = MathRound(lot / lotStep);
   double rlot = steps * lotStep;
   // enforce bounds
   if(rlot < minLot) rlot = minLot;
   if(rlot > maxLot) rlot = maxLot;
   // protect NaN or zero
   if(rlot <= 0.0) rlot = minLot;
   return rlot;
}

// Convert points to price (points measured where 1 point = SYMBOL_POINT)
double HB_PointsToPrice(const string symbol, double points)
{
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   return points * point;
}

// JSON escape for simple messages
string HB_JsonEscape(const string s)
{
   string out = "";
   int len = StringLen(s);
   for(int i=0; i<len; i++)
   {
      ushort ch = StringGetCharacter(s, i);
      if(ch == 34) out += "\\\"";
      else if(ch == 92) out += "\\\\";
      else if(ch == 10) out += "\\n";
      else if(ch == 13) out += "\\r";
      else out += CharToString((char)ch);
   }
   return out;
}