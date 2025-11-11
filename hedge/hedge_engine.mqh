// hedge_engine.mqh
// Phase B: Action-style Hedge Engine (neutralizing ComputeLot, average TP, cycle safety)
// Place in: ...\growbuddy\hedge\hedge_engine.mqh
#property version "1.0"

#include "hedge_action.mqh"
#include "hedge_utils.mqh"

// local enums used by engine (ensure these symbols are defined)
enum HEDGE_ORDER_TYPE { HEDGE_PENDING = 0, HEDGE_INSTANT = 1 };
enum HEDGE_GAP_TYPE  { GAP_FIX = 0, GAP_CUSTOM = 1 /* dynamic types not in MVP */ };
enum LOT_TYPE       { LOT_MULTIPLE = 0, LOT_MULTIPLE_CUSTOM = 1, LOT_CUSTOM = 2, LOT_ADD = 3 };
enum TP_TYPE        { TP_POINTS_AVERAGE = 0, TP_POINTS_FIXDIST = 1, TP_CURRENCY = 2 };

// configuration struct (subset of inputs; filled by caller)
struct HedgeConfig
{
   bool   Hedge_Active;
   int    Hedge_Order_Type;    // 0 pending, 1 instant
   int    HedgeGAPType;        // GAP_FIX / GAP_CUSTOM
   long   HedgeGAP;            // points
   string HedgeGAP_Custom;
   int    MaxHedgeTrade;
   int    LotTypeHedge;
   double MultipleLotsHedge;
   string CustomLotsHedge;
   int    TP_Type_Hedge;
   long   TakeProfit_Hedge;    // points
   bool   AddCurrentLots;
   double AddLotsHedge;
   // broker constraints
   double MinLot;
   double MaxLot;
   double LotStep;
};

// internal record
struct HedgeRecord
{
   int      step;
   int      side;            // 1 buy, -1 sell (explicit, to avoid ambiguity)
   string   hedge_type;
   double   gap_points;
   double   requested_price;
   double   requested_lot;
   ulong    ticket;
   double   executed_price;
   double   filled_lot;
   string   state;
   datetime ts;
   string   raw;
};

class HedgeEngine
{
private:
   HedgeConfig cfg;
   HedgeRecord records[]; // history of hedge steps (ordered)
   string decision_id;
   double initial_price;
   int initial_side; // 1 buy, -1 sell
   double initial_lot;
   datetime started_ts;

   // helper: compute current net exposure and weighted average price
   void ComputeNetExposure(double &netLots, double &avgPrice)
   {
      // netLots = totalBuys - totalSells (positive => overall long)
      double totalBuys = 0.0, totalSells = 0.0;
      double weighted = 0.0; // for net average price (for net long we compute average buy price; for net short compute average sell price)
      // include initial trade
      if(initial_side == 1)
      {
         totalBuys += initial_lot;
         weighted += initial_price * initial_lot;
      }
      else if(initial_side == -1)
      {
         totalSells += initial_lot;
         weighted -= initial_price * initial_lot; // subtract for sells
      }

      // include filled hedges (only filled_lot contributes to net exposure)
      for(int i=0;i<ArraySize(records);i++)
      {
         HedgeRecord r = records[i];
         if(r.filled_lot <= 0.0) continue;
         if(r.side == 1)
         {
            totalBuys += r.filled_lot;
            weighted += r.executed_price * r.filled_lot;
         }
         else if(r.side == -1)
         {
            totalSells += r.filled_lot;
            weighted -= r.executed_price * r.filled_lot;
         }
      }

      // compute net
      netLots = totalBuys - totalSells;
      if(netLots > 0.0)
      {
         // net long: avgPrice = weighted_buys / totalBuys
         double totalWeightedBuys = 0.0;
         double tb = 0.0;
         // recompute buys weighted
         if(initial_side == 1) { totalWeightedBuys += initial_price * initial_lot; tb += initial_lot; }
         for(int i=0;i<ArraySize(records);i++)
         {
            HedgeRecord r = records[i];
            if(r.filled_lot <= 0.0) continue;
            if(r.side == 1) { totalWeightedBuys += r.executed_price * r.filled_lot; tb += r.filled_lot; }
         }
         if(tb > 0.0) avgPrice = totalWeightedBuys / tb;
         else avgPrice = initial_price;
      }
      else if(netLots < 0.0)
      {
         // net short: avgPrice = weighted_sells / totalSells
         double totalWeightedSells = 0.0;
         double ts = 0.0;
         if(initial_side == -1) { totalWeightedSells += initial_price * initial_lot; ts += initial_lot; }
         for(int i=0;i<ArraySize(records);i++)
         {
            HedgeRecord r = records[i];
            if(r.filled_lot <= 0.0) continue;
            if(r.side == -1) { totalWeightedSells += r.executed_price * r.filled_lot; ts += r.filled_lot; }
         }
         if(ts > 0.0) avgPrice = totalWeightedSells / ts;
         else avgPrice = initial_price;
      }
      else
      {
         // net zero: avgPrice is undefined for net, fallback to initial price
         avgPrice = initial_price;
      }
   }

   // helper: compute current unrealized loss in points (positive numeric value; for long: avgPrice - currentPrice ; for short: currentPrice - avgPrice)
   double ComputeUnrealizedLossPoints()
   {
      double netLots = 0.0, avgPrice = 0.0;
      ComputeNetExposure(netLots, avgPrice);
      double curPrice = (netLots >= 0.0) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      if(netLots > 0.0)
      {
         // net long: lossPoints = avgPrice - curPrice (positive when loss)
         double pts = (avgPrice - curPrice) / point;
         if(pts < 0.0) pts = 0.0;
         return pts;
      }
      else if(netLots < 0.0)
      {
         double pts = (curPrice - avgPrice) / point;
         if(pts < 0.0) pts = 0.0;
         return pts;
      }
      else return 0.0;
   }

   // compute TP price for closing whole cycle to achieve TakeProfit_Hedge (simple avg-target method)
   double ComputeCycleTPPrice()
   {
      double netLots = 0.0, avgPrice = 0.0;
      ComputeNetExposure(netLots, avgPrice);
      double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      // if netLots == 0, just return 0 (no meaningful TP)
      if(netLots == 0.0) return 0.0;
      // Use TakeProfit_Hedge as points to move avgPrice toward profit
      double tpPoints = (double)cfg.TakeProfit_Hedge;
      if(tpPoints <= 0.0) return 0.0;
      if(netLots > 0.0)
      {
         // net long -> need price higher
         return NormalizeDouble(avgPrice + tpPoints * point, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
      }
      else
      {
         // net short -> need price lower
         return NormalizeDouble(avgPrice - tpPoints * point, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
      }
   }

public:
   // Expose cycle TP and net exposure so EA can perform basket-level close checks
   // Return computed cycle TP price (0.0 if not applicable)
   double GetCycleTPPrice()
   {
      return ComputeCycleTPPrice();
   }

   // Return net lots (signed): positive => net long, negative => net short, 0 => neutral
   double GetNetLots()
   {
      double netLots = 0.0, avg = 0.0;
      ComputeNetExposure(netLots, avg);
      return netLots;
   }

   // Initialize engine (no external dependencies)
   void Init(const HedgeConfig &c, const string dec)
   {
      cfg = c;
      decision_id = dec;
      ArrayResize(records,0);
      initial_price = 0.0;
      initial_side = 0;
      initial_lot = 0.0;
      started_ts = 0;
   }

   // Start hedge cycle when initial trade filled (provide entry price, side, lot)
   void StartCycle(const double entry_price, const int side, const double lot)
   {
      initial_price = entry_price;
      initial_side = side;
      initial_lot = lot;
      started_ts = TimeCurrent();
      ArrayResize(records,0);
   }

   // compute gap points for step (1-based)
   double ComputeGapPoints(int step)
   {
      if(cfg.HedgeGAPType == GAP_FIX) return (double)cfg.HedgeGAP;
      double arr[];
      HB_ParseDoublesList(cfg.HedgeGAP_Custom, arr);
      return HB_GetArrayValueOrLast(arr, step-1, (double)cfg.HedgeGAP);
   }

   // compute lot for step (1-based) - neutralizing strategy
   double ComputeLot(int step)
   {
      // Determine current net and compute the amount required to neutralize (opposite side)
      double totalBuys = 0.0, totalSells = 0.0;
      // initial
      if(initial_side == 1) totalBuys += initial_lot;
      else if(initial_side == -1) totalSells += initial_lot;
      // filled hedges
      for(int i=0;i<ArraySize(records);i++)
      {
         HedgeRecord rr = records[i];
         if(rr.filled_lot <= 0.0) continue;
         if(rr.side == 1) totalBuys += rr.filled_lot;
         else if(rr.side == -1) totalSells += rr.filled_lot;
      }

      double netBuys = MathMax(0.0, totalBuys - totalSells);   // existing net buy volume
      double netSells = MathMax(0.0, totalSells - totalBuys);  // existing net sell volume

      double desiredLot = 0.0;
      if(initial_side == 1)
      {
         // initial long -> we want sells to offset buys
         desiredLot = netBuys - netSells; // how many sells to reach parity
      }
      else if(initial_side == -1)
      {
         // initial short -> we want buys to offset sells
         desiredLot = netSells - netBuys;
      }

      // if already neutral or desiredLot zero, pick minimal increment: use initial_lot or custom/default
      if(desiredLot <= 0.0) desiredLot = initial_lot;

      // allow AddCurrentLots or AddLotsHedge (legacy behaviour)
      if(cfg.AddCurrentLots) desiredLot += initial_lot;
      if(cfg.AddLotsHedge > 0.0) desiredLot += cfg.AddLotsHedge;

      // Respect user-specified custom sequence if configured
      if(cfg.LotTypeHedge == LOT_CUSTOM)
      {
         double arr[];
         HB_ParseDoublesList(cfg.CustomLotsHedge, arr);
         desiredLot = HB_GetArrayValueOrLast(arr, step-1, desiredLot);
      }
      else if(cfg.LotTypeHedge == LOT_MULTIPLE)
      {
         // keep compatibility with CAP: allow multiplier as optional (but do not force exponential blow-up)
         double base = initial_lot;
         if(ArraySize(records) > 0)
         {
            HedgeRecord last = records[ArraySize(records)-1];
            if(last.filled_lot > 0.0) base = last.filled_lot;
         }
         double cand = base * cfg.MultipleLotsHedge;
         // choose the larger of neutral desiredLot and multiplier candidate (keeps CAP behavior but prevents tiny lots)
         desiredLot = MathMax(desiredLot, cand);
      }

      // normalize and clamp
      desiredLot = HB_NormalizeLot(desiredLot, cfg.MinLot, cfg.MaxLot, cfg.LotStep);
      if(desiredLot > cfg.MaxLot) desiredLot = cfg.MaxLot;
      if(desiredLot < cfg.MinLot) desiredLot = cfg.MinLot;
      return desiredLot;
   }

   // Compute pending price from reference
   double ComputePendingPrice(const double referencePrice, const int side, const double gapPoints)
   {
      double priceOffset = HB_PointsToPrice(_Symbol, gapPoints);
      int digits = (int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
      if(side == 1) // initial buy -> hedge is sellstop lower
         return NormalizeDouble(referencePrice - priceOffset, digits);
      else
         return NormalizeDouble(referencePrice + priceOffset, digits);
   }

   // Evaluate next action — returns HedgeAction (engine DOES NOT execute)
   HedgeAction EvaluateNextAction()
   {
      HedgeAction act;
      act.type = HEDGE_ACT_NONE;
      act.step = ArraySize(records) + 1;
      act.side = 0;
      act.price = 0.0;
      act.lot = 0.0;
      act.sl = 0.0;
      act.tp = 0.0;
      act.comment = "";
      act.reason = "";

      if(!cfg.Hedge_Active) return act;
      if(initial_side == 0 || initial_lot <= 0.0) return act;

      int nextStep = ArraySize(records) + 1;

      // Max hedge safety: if we've reached allowed count, instruct EA to apply LossTakingPolicy
      if(cfg.MaxHedgeTrade > 0 && nextStep > cfg.MaxHedgeTrade)
      {
         act.type = HEDGE_ACT_MAX_REACHED;
         act.reason = "max_reached";
         act.step = nextStep;
         return act;
      }

      double gapPts = ComputeGapPoints(nextStep);
      double lot = ComputeLot(nextStep);
      int hedgeSide = (initial_side==1) ? -1 : 1;

      // compute TP for cycle (average-based, simple implementation)
      double tp_price = 0.0;
      if(cfg.TakeProfit_Hedge > 0)
      {
         // If TP_Type_Hedge indicates average or fixedpoints, compute cycle TP price
         if(cfg.TP_Type_Hedge == TP_POINTS_AVERAGE || cfg.TP_Type_Hedge == TP_POINTS_FIXDIST)
         {
            tp_price = ComputeCycleTPPrice();
         }
         // TP_TYPE TP_CURRENCY not implemented in MVP (would require tick value calc)
      }

      if(cfg.Hedge_Order_Type == HEDGE_PENDING)
      {
         double targetPrice = ComputePendingPrice(initial_price, initial_side, gapPts);
         act.type = HEDGE_ACT_PLACE_PENDING;
         act.step = nextStep;
         act.side = hedgeSide;
         act.price = targetPrice;
         act.lot = lot;
         act.tp = tp_price; // may be 0.0 if not set
         act.comment = StringFormat("dec:%s|h:%d|t:P", decision_id, nextStep);
         return act;
      }
      else // Instant
      {
         double curPrice = (initial_side==1) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
         double lossPoints = 0.0;
         if(initial_side == 1) lossPoints = (initial_price - curPrice) / point;
         else lossPoints = (curPrice - initial_price) / point;
         if(lossPoints >= gapPts)
         {
            act.type = HEDGE_ACT_PLACE_MARKET;
            act.step = nextStep;
            act.side = hedgeSide;
            act.price = curPrice;
            act.lot = lot;
            act.tp = tp_price;
            act.comment = StringFormat("dec:%s|h:%d|t:I", decision_id, nextStep);
            return act;
         }
      }
      return act;
   }

   // Caller MUST call these to update engine state after main EA executes orders
   // OnPendingPlaced: record a placed pending order (we store side as opposite initial)
   void OnPendingPlaced(int step, const ulong ticket, double requested_price)
   {
      HedgeRecord rec;
      rec.step = step;
      rec.side = (initial_side==1)? -1 : 1; // hedges are opposite direction
      rec.hedge_type = "pending";
      rec.gap_points = ComputeGapPoints(step);
      rec.requested_price = requested_price;
      rec.requested_lot = 0.0; // filled later
      rec.ticket = ticket;
      rec.executed_price = 0.0;
      rec.filled_lot = 0.0;
      rec.state = "placed";
      rec.ts = TimeCurrent();
      rec.raw = "";
      int n = ArraySize(records);
      ArrayResize(records, n+1);
      records[n] = rec;
   }

   // OnPendingMiss: record a missed pending placement (failed)
   void OnPendingMiss(int step, const string reason)
   {
      HedgeRecord rec;
      rec.step = step;
      rec.side = (initial_side==1)? -1 : 1;
      rec.hedge_type = "pending";
      rec.gap_points = ComputeGapPoints(step);
      rec.requested_price = 0.0;
      rec.requested_lot = 0.0;
      rec.ticket = 0;
      rec.executed_price = 0.0;
      rec.filled_lot = 0.0;
      rec.state = "missed";
      rec.ts = TimeCurrent();
      rec.raw = reason;
      int n = ArraySize(records);
      ArrayResize(records, n+1);
      records[n] = rec;
   }

   // OnOrderFilled: record a filled market order (or a filled pending). We use side opposite initial as hedges are opposite.
   void OnOrderFilled(int step, const ulong ticket, double executed_price, double filled_lot)
   {
      HedgeRecord rec;
      rec.step = step;
      rec.side = (initial_side==1)? -1 : 1;
      rec.hedge_type = "filled";
      rec.gap_points = ComputeGapPoints(step);
      rec.requested_price = executed_price;
      rec.requested_lot = filled_lot;
      rec.ticket = ticket;
      rec.executed_price = executed_price;
      rec.filled_lot = filled_lot;
      rec.state = "filled";
      rec.ts = TimeCurrent();
      rec.raw = "";
      int n = ArraySize(records);
      ArrayResize(records, n+1);
      records[n] = rec;
   }

   // helpers
   int HedgeCount() { return ArraySize(records); }

   void GetRecords(HedgeRecord &out[])
   {
      int n = ArraySize(records);
      ArrayResize(out, n);
      for(int i=0;i<n;i++)
      {
         out[i].step = records[i].step;
         out[i].side = records[i].side;
         out[i].hedge_type = records[i].hedge_type;
         out[i].gap_points = records[i].gap_points;
         out[i].requested_price = records[i].requested_price;
         out[i].requested_lot = records[i].requested_lot;
         out[i].ticket = records[i].ticket;
         out[i].executed_price = records[i].executed_price;
         out[i].filled_lot = records[i].filled_lot;
         out[i].state = records[i].state;
         out[i].ts = records[i].ts;
         out[i].raw = records[i].raw;
      }
   }
};