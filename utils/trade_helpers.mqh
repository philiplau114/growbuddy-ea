//+------------------------------------------------------------------+
//| trade_helpers.mqh - Logged order wrappers for GrowBuddy EA       |
//| - Adds LoggedMarketOrder / LoggedPendingOrder                    |
//| - Moves trade-related helpers from main EA into this header      |
//+------------------------------------------------------------------+
#property strict

#include "..\\logs\\logging.mqh"   // LOG_InsertPlan / LOG_InsertExecution
#include "common.mqh"              // utility helpers

// Reference the main EA's trade instance; main must define "CTrade trade;" before including this header
extern CTrade trade;

// ----------------- Existing helpers (updated) -----------------

// Check if EA allowed to trade
bool IsTradingAllowed()
{
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
     {
      Print("Trading not allowed by terminal settings");
      return(false);
     }
   return(true);
}

// Iterate positions safely and print a summary for EA positions (by Magic or comment)
void ForEachEAPosition(const int magic)
{
   int total = PositionsTotal();
   for(int i=0; i<total; i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket==0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      long pos_magic = (long)PositionGetInteger(POSITION_MAGIC);
      string pos_comm = PositionGetString(POSITION_COMMENT);
      if(pos_magic==magic || StringFind(pos_comm,"MAIN")>=0 || StringFind(pos_comm,"RICO")>=0)
        {
         PrintFormat("ForEachEAPosition: ticket=%I64u magic=%d comment=%s", ticket, pos_magic, pos_comm);
        }
     }
}

// Set SL (in points) for a position by ticket. Uses trade.PositionModify.
bool SetPositionSL_ByPoints(const ulong ticket, const long sl_points)
{
   if(ticket==0) return(false);
   if(!PositionSelectByTicket(ticket))
   {
      PrintFormat("SetPositionSL: position select failed ticket=%I64u", ticket);
      return(false);
   }

   int type = (int)PositionGetInteger(POSITION_TYPE);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double price = (type==POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   double new_sl;
   if(type==POSITION_TYPE_BUY)
      new_sl = price - sl_points * point;
   else
      new_sl = price + sl_points * point;

   new_sl = NormalizeDouble(new_sl, digits);

   double current_tp = PositionGetDouble(POSITION_TP);

   bool ok = trade.PositionModify(ticket, new_sl, current_tp);
   if(!ok)
   {
      PrintFormat("PositionModify failed ticket=%I64u ret=%d desc=%s", ticket, trade.ResultRetcode(), trade.ResultRetcodeDescription());
      return(false);
   }
   PrintFormat("PositionModify OK ticket=%I64u newSL=%.*f", ticket, digits, new_sl);
   return(true);
}

// Set exact SL price (absolute) for a position
bool SetPositionSL_ByPrice(const ulong ticket, const double sl_price)
{
   if(ticket==0) return(false);
   if(!PositionSelectByTicket(ticket)) return(false);
   double current_tp = PositionGetDouble(POSITION_TP);
   bool ok = trade.PositionModify(ticket, sl_price, current_tp);
   if(!ok)
   {
      PrintFormat("PositionModify failed ticket=%I64u ret=%d desc=%s", ticket, trade.ResultRetcode(), trade.ResultRetcodeDescription());
      return(false);
   }
   return(true);
}

// Close position by ticket (wrapper)
bool ClosePositionByTicket(const ulong ticket)
{
   if(ticket==0) return(false);
   if(!PositionSelectByTicket(ticket)) return(false);
   bool ok = trade.PositionClose(ticket, Slippage);
   if(!ok)
   {
      PrintFormat("PositionClose failed ticket=%I64u ret=%d desc=%s", ticket, trade.ResultRetcode(), trade.ResultRetcodeDescription());
      return(false);
   }
   return(true);
}

// Close latest EA position (by magic).
bool CloseLatestEAPosition(const int magic)
{
   datetime latest = 0;
   ulong latestTicket = 0;
   int total = PositionsTotal();
   for(int i=0; i<total; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket==0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      long pm = (long)PositionGetInteger(POSITION_MAGIC);
      if(pm != magic) continue;
      datetime t = (datetime)PositionGetInteger(POSITION_TIME);
      if(t > latest) { latest = t; latestTicket = ticket; }
   }
   if(latestTicket>0) return ClosePositionByTicket(latestTicket);
   return(false);
}

// Existing SafeMarket wrappers (kept for compatibility)
bool SafeMarketBuy(const double lots, const string comment = "MAIN")
{
   if(!IsTradingAllowed()) return(false);
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(Slippage);
   bool ok = trade.Buy(lots, NULL, 0.0, 0.0, 0.0, comment);
   if(!ok)
      PrintFormat("SafeMarketBuy failed: ret=%d desc=%s", trade.ResultRetcode(), trade.ResultRetcodeDescription());
   return(ok);
}

bool SafeMarketSell(const double lots, const string comment = "MAIN")
{
   if(!IsTradingAllowed()) return(false);
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(Slippage);
   bool ok = trade.Sell(lots, NULL, 0.0, 0.0, 0.0, comment);
   if(!ok)
      PrintFormat("SafeMarketSell failed: ret=%d desc=%s", trade.ResultRetcode(), trade.ResultRetcodeDescription());
   return(ok);
}

// Place pending order example (MqlTradeRequest). Returns true on success.
bool PlacePendingOrder(const ENUM_ORDER_TYPE orderType, const double volume, double price, const long expiration_seconds = 0, const string comment = "MAIN")
{
   if(!IsTradingAllowed()) return(false);

   MqlTradeRequest req;
   MqlTradeResult  res;
   ZeroMemory(req);
   ZeroMemory(res);

   req.action = TRADE_ACTION_PENDING;
   req.type = orderType;
   req.symbol = _Symbol;
   req.volume = volume;
   req.price = price;
   req.deviation = Slippage;
   req.magic = MagicNumber;
   req.comment = comment;

   if(expiration_seconds>0)
     req.expiration = (datetime)(TimeCurrent() + expiration_seconds);

   if(!OrderSend(req,res))
   {
      PrintFormat("OrderSend failed result=%d comment=%s", res.retcode, res.comment);
      return(false);
   }
   PrintFormat("OrderSend OK ticket=%I64d ret=%d", res.order, res.retcode);
   return(true);
}

// Quick helper: compute sl price given sl_points and position type
double ComputeSLPriceFromPoints(const int position_type, const long sl_points)
{
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double price = (position_type==POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double sl = (position_type==POSITION_TYPE_BUY) ? price - sl_points*point : price + sl_points*point;
   return(NormalizeDouble(sl, (int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS)));
}

// ----------------- New: Logged order wrappers & plan helpers -----------------

// CreatePlanAndLog: write plan row to DB (thin wrapper around LOG_InsertPlan)
bool CreatePlanAndLog(const string run_key, const string decision_id, const string plan_id, const string planned_type, const string side, const double volume, const double price, const double sl, const double tp, const string comment, const string effective_params_json)
{
   if(StringLen(run_key) == 0 || StringLen(plan_id) == 0)
   {
      PrintFormat("CreatePlanAndLog: missing run_key or plan_id run_key=%s plan_id=%s", run_key, plan_id);
      return(false);
   }
   string ts = TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS);
   return LOG_InsertPlan(run_key, decision_id, plan_id, ts, planned_type, side, volume, price, sl, tp, comment, effective_params_json, "{}");
}

// EnsureCommentHasPlan: returns comment_base|plan:plan_id (truncated if necessary)
string EnsureCommentHasPlan(const string comment_base, const string plan_id)
{
   return LOG_FormatOrderCommentWithPlan(comment_base, plan_id);
}

// LoggedMarketOrder: use trade to place market order and log execution in DB
bool LoggedMarketOrder(const string run_key, const string plan_id, const int side, const double volume, const double sl, const double tp, const string comment_base, const int magic, const int deviation, int &out_order_ticket)
{
   out_order_ticket = 0;
   if(StringLen(run_key) == 0 || StringLen(plan_id) == 0)
   {
      PrintFormat("LoggedMarketOrder: missing run_key or plan_id run_key=%s plan_id=%s", run_key, plan_id);
      return(false);
   }

   if(!IsTradingAllowed())
   {
      Print("LoggedMarketOrder: trading not allowed by terminal settings");
      return(false);
   }

   string comment = EnsureCommentHasPlan(comment_base, plan_id);

   trade.SetExpertMagicNumber(magic);
   trade.SetDeviationInPoints(deviation);

   bool ok = false;
   if(side == 1)
      ok = trade.Buy(volume, NULL, 0.0, sl, tp, comment);
   else
      ok = trade.Sell(volume, NULL, 0.0, sl, tp, comment);

   uint ret_u = trade.ResultRetcode();
   int ret = (int)ret_u;
   string retDesc = trade.ResultRetcodeDescription();
   ulong ticket = trade.ResultOrder();
   double filled_price = trade.ResultPrice();

   string req_json = BuildMarketRequestJson(volume, sl, tp, comment);
   string res_json = StringFormat("{\"retcode\":%d,\"desc\":\"%s\",\"order\":%I64u}", ret, retDesc, ticket);

   LOG_InsertExecution(run_key, plan_id, TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS), req_json, res_json, ret, retDesc, (int)ticket, filled_price, sl, tp);

   out_order_ticket = (int)ticket;
   return ok;
}

// LoggedPendingOrder: build MqlTradeRequest, OrderSend, and log execution
ulong LoggedPendingOrder(const string run_key, const string plan_id, const ENUM_ORDER_TYPE orderType, const double volume, const double price, const double sl, const double tp, const string comment_base, const int magic, const int deviation)
{
   if(StringLen(run_key) == 0 || StringLen(plan_id) == 0)
   {
      PrintFormat("LoggedPendingOrder: missing run_key or plan_id run_key=%s plan_id=%s", run_key, plan_id);
      return(0);
   }

   if(!IsTradingAllowed())
   {
      Print("LoggedPendingOrder: trading not allowed by terminal settings");
      return(0);
   }

   MqlTradeRequest req;
   MqlTradeResult  res;
   ZeroMemory(req); ZeroMemory(res);

   req.action = TRADE_ACTION_PENDING;
   req.symbol = _Symbol;
   req.volume = volume;
   req.type = orderType;
   req.magic = magic;
   req.deviation = deviation;
   req.comment = EnsureCommentHasPlan(comment_base, plan_id);
   req.type_filling = ORDER_FILLING_RETURN;
   req.price = price;
   req.sl = (sl > 0.0 ? sl : 0.0);
   req.tp = (tp > 0.0 ? tp : 0.0);

   bool sent = OrderSend(req, res);

   int ret = (int)res.retcode;
   string retDesc = res.comment;
   ulong order_ticket = res.order;

   string req_json = BuildPendingRequestJson(volume, price, sl, tp, req.comment);
   string res_json = StringFormat("{\"retcode\":%d,\"comment\":\"%s\",\"order\":%I64u}", ret, retDesc, order_ticket);

   LOG_InsertExecution(run_key, plan_id, TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS), req_json, res_json, ret, retDesc, (int)order_ticket, price, sl, tp);

   if(!sent || (ret != TRADE_RETCODE_PLACED && ret != TRADE_RETCODE_DONE))
   {
      PrintFormat("LoggedPendingOrder: OrderSend failed ret=%d comment=%s", ret, retDesc);
      return(0);
   }

   return(order_ticket);
}

// ----------------- Position / bulk helpers -----------------

// Delete other pending orders for the same symbol (except keep_ticket)
void DeleteOtherPendingOrders(const ulong keep_ticket)
{
   int total = OrdersTotal();
   for(int idx=0; idx<total; idx++)
   {
      ulong ticket = OrderGetTicket(idx);
      if(ticket==0 || ticket==keep_ticket) continue;
      if(!OrderSelect(ticket)) continue;
      string sym = OrderGetString(ORDER_SYMBOL);
      if(sym != _Symbol) continue;
      long state_l = OrderGetInteger(ORDER_STATE);
      if((ENUM_ORDER_STATE)state_l != ORDER_STATE_PLACED) continue;
      if(!trade.OrderDelete(ticket))
         PrintFormat("DeleteOtherPendingOrders: failed delete ticket=%I64u rc=%d", ticket, trade.ResultRetcode());
      else
         PrintFormat("DeleteOtherPendingOrders: deleted ticket=%I64u", ticket);
   }
}

// RemoveHardTPandSL_Takeover: remove TP/SL from EA-managed positions not using this EA's magic
void RemoveHardTPandSL_Takeover()
{
   int total = PositionsTotal();
   for(int i=0; i<total; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket==0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      long magic = (long)PositionGetInteger(POSITION_MAGIC);
      string comm = PositionGetString(POSITION_COMMENT);
      if(!UseNoMagicNumber && magic==MagicNumber) continue;
      if(!UseNoMagicNumber && StringFind(comm, InitialTradeComment) < 0) continue;
      double cur_tp = PositionGetDouble(POSITION_TP);
      double cur_sl = PositionGetDouble(POSITION_SL);
      if(cur_tp != 0.0 || cur_sl != 0.0)
      {
         bool ok = trade.PositionModify(ticket, 0.0, 0.0);
         if(ok) PrintFormat("RemoveHardTPandSL_Takeover: removed TP/SL ticket=%I64u", ticket);
         else PrintFormat("RemoveHardTPandSL_Takeover: failed modify ticket=%I64u rc=%d", ticket, trade.ResultRetcode());
      }
   }
}

// ProtectOnError: close EA-managed positions on error
void ProtectOnError()
{
   int total = PositionsTotal();
   for(int i=0; i<total; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket==0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      long magic = (long)PositionGetInteger(POSITION_MAGIC);
      string comm = PositionGetString(POSITION_COMMENT);
      if(!(magic==MagicNumber || StringFind(comm,InitialTradeComment)>=0 || UseNoMagicNumber)) continue;
      trade.PositionClose(ticket, Slippage);
   }
}

// ManageLossPolicy: original logic moved here (uses SetPositionStopLoss_Modify and CloseLatestEAPosition)
void ManageLossPolicy()
{
   if(LossTakingPolicy==0) return;
   int total = PositionsTotal();
   int count=0;
   double cycleProfit = 0.0;
   for(int i=0;i<total;i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket==0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      long magic = (long)PositionGetInteger(POSITION_MAGIC);
      string comm = PositionGetString(POSITION_COMMENT);
      if(magic==MagicNumber || StringFind(comm,InitialTradeComment)>=0 || StringFind(comm,HedgeTradeComment)>=0 || UseNoMagicNumber)
      {
         count++;
         cycleProfit += PositionGetDouble(POSITION_PROFIT);
      }
   }

   if(count >= MaxHedgeTrade)
   {
      if(LossTakingPolicy==1)
      {
         for(int i=0;i<total;i++)
         {
            ulong ticket = PositionGetTicket(i);
            if(ticket==0) continue;
            if(!PositionSelectByTicket(ticket)) continue;
            long magic = (long)PositionGetInteger(POSITION_MAGIC);
            string comm = PositionGetString(POSITION_COMMENT);
            if(!(magic==MagicNumber || StringFind(comm,InitialTradeComment)>=0 || StringFind(comm,HedgeTradeComment)>=0 || UseNoMagicNumber)) continue;
            double profit = PositionGetDouble(POSITION_PROFIT);
            if(profit < 0)
            {
               SetPositionSL_ByPoints(ticket, StopLoss);
            }
         }
      }
      else if(LossTakingPolicy==2)
      {
         CloseLatestEAPosition(MagicNumber);
      }
   }
}