//+------------------------------------------------------------------+
//| position_helpers.mqh - small helpers for GrowBuddy               |
//+------------------------------------------------------------------+
#property strict

// Returns true if there exists an open EA-managed position of the given direction.
// position_type: use POSITION_TYPE_BUY or POSITION_TYPE_SELL (from MQL5 enums)
bool HasOpenPositionForMagicAndDirection(const long position_type)
{
   int total = PositionsTotal();
   for(int i=0; i<total; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;

      long ptype = (long)PositionGetInteger(POSITION_TYPE);
      long pmagic = (long)PositionGetInteger(POSITION_MAGIC);
      string comm = PositionGetString(POSITION_COMMENT);

      // If UseNoMagicNumber is false, require magic to match OR comment include MAIN/RICO
      bool isEA;
      if(UseNoMagicNumber)
      {
         // treat any position with EA comments or any position as EA-managed when UseNoMagicNumber=true
         isEA = (StringFind(comm, InitialTradeComment) >= 0) || (StringFind(comm, HedgeTradeComment) >= 0) || (pmagic == MagicNumber);
      }
      else
      {
         isEA = (pmagic == MagicNumber) || (StringFind(comm, InitialTradeComment) >= 0) || (StringFind(comm, HedgeTradeComment) >= 0);
      }

      if(!isEA) continue;

      if(ptype == position_type)
         return true;
   }
   return false;
}

// Count EA-managed open positions (by magic/comment/UseNoMagicNumber)
// Returns number of positions considered managed by this EA.
int CountEAOpenPositions()
{
   int cnt = 0;
   int total = PositionsTotal();
   for(int i=0; i<total; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;

      long pmagic = (long)PositionGetInteger(POSITION_MAGIC);
      string comm = PositionGetString(POSITION_COMMENT);

      bool isEA;
      if(UseNoMagicNumber)
      {
         isEA = (StringFind(comm, InitialTradeComment) >= 0) || (StringFind(comm, HedgeTradeComment) >= 0) || (pmagic == MagicNumber);
      }
      else
      {
         isEA = (pmagic == MagicNumber) || (StringFind(comm, InitialTradeComment) >= 0) || (StringFind(comm, HedgeTradeComment) >= 0);
      }

      if(isEA) cnt++;
   }
   return cnt;
}

// Ensure this file name matches your include and is compiled along with EA.
// SafePositionModifySetSL: adjust desiredSL to meet broker min stop distance and modify position.
// Returns true if modified successfully, false otherwise.
// Try to modify position SL to desiredSL (price). Adjusts to broker min stops and retries.
// Returns true if modification succeeded, false otherwise.
bool SafePositionModifySetSL(ulong ticket, double desiredSL)
{
   if(ticket == 0) return false;
   if(!PositionSelectByTicket(ticket))
   {
      string p = "{\"event\":\"SafePositionModify_SelectFail\",\"ticket\":" + IntegerToString((int)ticket) + "}";
      LOG_CreateEventLine("error", g_run_key, "", p);
      LOG_ConditionalFlush();
      return false;
   }

   int pos_type = (int)PositionGetInteger(POSITION_TYPE); // POSITION_TYPE_BUY or SELL
   double cur_bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double cur_ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double cur_price = (pos_type == POSITION_TYPE_BUY) ? cur_bid : cur_ask;
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   // broker min stop points
   int broker_min_points = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   int safety_points = 1;
   int effective_points = (broker_min_points > 0) ? broker_min_points : safety_points;
   double minStopDist = (double)effective_points * point;

   // Normalize desiredSL into a valid side and distance
   double newSL = desiredSL;
   if(pos_type == POSITION_TYPE_BUY)
   {
      if(!(newSL < cur_price)) newSL = NormalizeDouble(cur_price - minStopDist, digits);
      else if((cur_price - newSL) < minStopDist) newSL = NormalizeDouble(cur_price - minStopDist, digits);
   }
   else if(pos_type == POSITION_TYPE_SELL)
   {
      if(!(newSL > cur_price)) newSL = NormalizeDouble(cur_price + minStopDist, digits);
      else if((newSL - cur_price) < minStopDist) newSL = NormalizeDouble(cur_price + minStopDist, digits);
   }
   else
   {
      string p = "{\"event\":\"SafePositionModify_UnknownPosType\",\"ticket\":" + IntegerToString((int)ticket) + "}";
      LOG_CreateEventLine("error", g_run_key, "", p);
      LOG_ConditionalFlush();
      return false;
   }

   double oldSL = PositionGetDouble(POSITION_SL);
   if(MathAbs(newSL - oldSL) < (point / 2.0))
   {
      // already effectively same SL
      return true;
   }

   // try modify with retries; if invalid stops, expand pad and retry
   int max_attempts = 3;
   bool mod_ok = false;
   int pad_multiplier = 1;
   for(int attempt=1; attempt<=max_attempts; ++attempt)
   {
      MqlTradeRequest req;
      MqlTradeResult res;
      ZeroMemory(req); ZeroMemory(res);
      req.action = TRADE_ACTION_SLTP; // modify SL/TP
      req.position = ticket;
      req.symbol = _Symbol;
      req.sl = newSL;
      req.tp = PositionGetDouble(POSITION_TP);
      req.deviation = 10;
      if(!OrderSend(req, res))
      {
         string pl = "{\"event\":\"SafePositionModify_OrderSendFailed\",\"ticket\":" + IntegerToString((int)ticket) + ",\"err\":" + IntegerToString(GetLastError()) + "}";
         LOG_CreateEventLine("error", g_run_key, "", pl);
         LOG_ConditionalFlush();
         Sleep(10);
         continue;
      }
      // success codes: done or done partial
      if(res.retcode == TRADE_RETCODE_DONE || res.retcode == TRADE_RETCODE_DONE_PARTIAL)
      {
         mod_ok = true;
         break;
      }
      else
      {
         if(res.retcode == TRADE_RETCODE_INVALID_STOPS || res.retcode == 10016) // invalid stops
         {
            // expand minStopDist and recompute newSL relative to current price
            effective_points = MathMax(effective_points * 2, effective_points + 5);
            minStopDist = (double)effective_points * point;
            if(pos_type == POSITION_TYPE_BUY) newSL = NormalizeDouble(cur_price - minStopDist, digits);
            else newSL = NormalizeDouble(cur_price + minStopDist, digits);

            string pl = "{\"event\":\"SafePositionModify_RetryInvalidStops\",\"ticket\":" + IntegerToString((int)ticket) + ",\"attempt\":" + IntegerToString(attempt) + ",\"retcode\":" + IntegerToString(res.retcode) + "}";
            LOG_CreateEventLine("warning", g_run_key, "", pl);
            LOG_ConditionalFlush();
            Sleep(10);
            continue;
         }
         else
         {
            string pl = "{\"event\":\"SafePositionModify_Failed\",\"ticket\":" + IntegerToString((int)ticket) + ",\"retcode\":" + IntegerToString(res.retcode) + ",\"desc\":\"" + res.comment + "\"}";
            LOG_CreateEventLine("error", g_run_key, "", pl);
            LOG_ConditionalFlush();
            break;
         }
      }
   } // attempts

   if(mod_ok)
   {
      string pl = "{\"event\":\"SafePositionModify_OK\",\"ticket\":" + IntegerToString((int)ticket) + ",\"newSL\":" + DoubleToString(newSL, digits) + "}";
      LOG_CreateEventLine("debug", g_run_key, "", pl);
      LOG_ConditionalFlush();
      return true;
   }
   else
   {
      string pl = "{\"event\":\"SafePositionModify_FinalFail\",\"ticket\":" + IntegerToString((int)ticket) + "}";
      LOG_CreateEventLine("error", g_run_key, "", pl);
      LOG_ConditionalFlush();
      return false;
   }
}

// Convenience: set SL by StopLoss points (StopLoss is points from EA input)
// This computes a desiredSL from current market price and calls SafePositionModifySetSL
bool SafeSetSLByPoints(ulong ticket, long stopLossPoints)
{
   if(ticket == 0) return false;
   if(!PositionSelectByTicket(ticket)) return false;
   int pos_type = (int)PositionGetInteger(POSITION_TYPE);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double cur_price = (pos_type == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double desiredSL;
   if(pos_type == POSITION_TYPE_BUY)
      desiredSL = NormalizeDouble(cur_price - stopLossPoints * point, digits);
   else
      desiredSL = NormalizeDouble(cur_price + stopLossPoints * point, digits);
   return SafePositionModifySetSL(ticket, desiredSL);
}