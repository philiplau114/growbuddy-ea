// hedge_action.mqh
// HedgeAction definition for Action-style Hedge Engine
// Place in: ...\growbuddy\hedge\hedge_action.mqh

#property version "1.0"

// action types returned by HedgeEngine.EvaluateNextAction()
enum HEDGE_ACTION_TYPE
{
   HEDGE_ACT_NONE = 0,
   HEDGE_ACT_PLACE_PENDING = 1,
   HEDGE_ACT_PLACE_MARKET = 2,
   HEDGE_ACT_MAX_REACHED = 3   // engine signals MaxHedgeTrade reached; EA should apply LossTakingPolicy
};

struct HedgeAction
{
   int      type;     // HEDGE_ACTION_TYPE
   int      step;     // 1-based step
   int      side;     // 1=buy, -1=sell
   double   price;    // requested price (for pending) or snapshot price
   double   lot;
   double   sl;       // stoploss price (0.0 == none)
   double   tp;       // takeprofit price (0.0 == none)
   string   comment;  // short comment
   string   reason;   // diagnostic / fallback reason
};

// simple JSON serializer (for logging/debug if needed)
string HedgeActionToJson(const HedgeAction &a)
{
   return StringFormat("{\"type\":%d,\"step\":%d,\"side\":%d,\"price\":%.8f,\"lot\":%.4f,\"sl\":%.8f,\"tp\":%.8f,\"comment\":\"%s\",\"reason\":\"%s\"}",
                       a.type, a.step, a.side, a.price, a.lot, a.sl, a.tp, a.comment, a.reason);
}