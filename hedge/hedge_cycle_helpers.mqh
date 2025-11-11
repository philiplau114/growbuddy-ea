// hedge_cycle_helpers.mqh
// Helper: start/confirm hedge cycle synchronously (Position-confirmed StartCycle)
// Place this file in: hedge\hedge_cycle_helpers.mqh

#property strict

// External globals expected from main EA:
//  - g_hedge_cfg (HedgeConfig), g_hedge (HedgeEngine instance)
//  - g_hedge_started (bool), g_hedge_cycle_decision_id (string), g_last_decision_id (string)
//  - g_hedge_max_reached_handled, g_last_max_handled_decision_id
//  - MagicNumber, InitialTradeComment, HedgeTradeComment, DebugMode, g_run_key
extern HedgeConfig g_hedge_cfg;
extern HedgeEngine g_hedge;
extern bool g_hedge_started;
extern string g_hedge_cycle_decision_id;
extern string g_last_decision_id;
extern bool g_hedge_max_reached_handled;
extern string g_last_max_handled_decision_id;
extern int MagicNumber;
extern string InitialTradeComment;
extern string HedgeTradeComment;
extern bool DebugMode;
extern string g_run_key;

// Try to start hedge cycle for a given position ticket.
// - ticket: position ticket (ulong)
// - decision_id: decision id to use (string), typically g_last_decision_id
// - sig: direction 1=buy, -1=sell
// - lot: volume of the initial position
// Returns true if cycle started (or assumed started) successfully.
bool StartHedgeCycleConfirmedByTicket(const ulong ticket, const string decision_id, const int sig, const double lot)
{
   // Defensive checks
   if(ticket == 0) return(false);

   // Retry loop: wait a short time for broker to make position visible
   const int MAX_TRIES = 8;
   const int SLEEP_MS = 250; // tune as needed
   bool pos_found = false;
   for(int t=0; t<MAX_TRIES; t++)
   {
      if(PositionSelectByTicket(ticket))
      {
         pos_found = true;
         break;
      }
      // short sleep and retry
      Sleep(SLEEP_MS);
   }

   double entry_price = 0.0;
   if(pos_found)
   {
      entry_price = PositionGetDouble(POSITION_PRICE_OPEN);
      // optional: verify magic/comment belongs to our EA
      long pmagic = (long)PositionGetInteger(POSITION_MAGIC);
      string pcomm = PositionGetString(POSITION_COMMENT);
      if(!(pmagic == MagicNumber || StringFind(pcomm, InitialTradeComment) >= 0 || StringFind(pcomm, HedgeTradeComment) >= 0))
      {
         // Not our position — still we can start cycle if caller insists, but log
         string dbg = StringFormat("{\"event\":\"StartHedgeCycle_WarningNotOurPos\",\"ticket\":%I64u,\"pmagic\":%d,\"comment\":\"%s\"}", ticket, (int)pmagic, pcomm);
         Print(dbg);
      }
   }
   else
   {
      // position not visible after retries -> fallback to market price snapshot
      entry_price = (sig == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
      string dbg = StringFormat("{\"event\":\"StartHedgeCycle_FallbackPrice\",\"ticket\":%I64u,\"fallback_price\":%.8f}", ticket, entry_price);
      Print(dbg);
   }

   // snapshot decision id
   if(StringLen(decision_id) > 0)
      g_hedge_cycle_decision_id = decision_id;
   else if(StringLen(g_last_decision_id) > 0)
      g_hedge_cycle_decision_id = g_last_decision_id;
   else
      g_hedge_cycle_decision_id = TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS) + "_auto";

   // initialize engine with stable decision id and start cycle
   g_hedge.Init(g_hedge_cfg, g_hedge_cycle_decision_id);
   g_hedge.StartCycle(entry_price, sig, lot);

   // mark started and reset hedgemax gating
   g_hedge_started = true;
   g_hedge_max_reached_handled = false;
   g_last_max_handled_decision_id = "";

   // Logging
   if(DebugMode)
   {
      string dbg = "{";
      dbg += "\"event\":\"StartHedgeCycleConfirmedByTicket\",";
      dbg += "\"decision_id\":\"" + g_hedge_cycle_decision_id + "\",";
      dbg += "\"ticket\":" + IntegerToString((int)ticket) + ",";
      dbg += "\"entry_price\":" + DoubleToString(entry_price, Digits()) + ",";
      dbg += "\"sig\":" + IntegerToString(sig) + ",";
      dbg += "\"lot\":" + DoubleToString(lot, 8);
      dbg += "}";
      // Use Print for immediate feedback; LOG_CreateEventLine can be used if available
      Print(dbg);
      // LOG_CreateEventLine("debug", g_run_key, g_hedge_cycle_decision_id, dbg);
      // LOG_ConditionalFlush();
   }

   return(true);
}

// Convenience: try start by ticket int (compat with LoggedMarketOrder out_ticket int)
bool StartHedgeCycleConfirmedByTicketInt(const int out_ticket_int, const string decision_id, const int sig, const double lot)
{
   if(out_ticket_int == 0) return(false);
   return StartHedgeCycleConfirmedByTicket((ulong)out_ticket_int, decision_id, sig, lot);
}