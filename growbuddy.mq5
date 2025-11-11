//+------------------------------------------------------------------+
//| GrowBuddy - CAP-aligned EA (v1.22 final)                         |
//| - Uses built-in iIchimoku via entry_engine_refactored.mqh        |
//| - Phase-B: Action-style Hedge integration (neutralizing ComputeLot, cycle TP, MaxReached signaling)
//| - Integrates with common.mqh, trade_helpers.mqh, logging.mqh     |
//+------------------------------------------------------------------+
#property copyright "Trade Buddy"
#property version   "1.22"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

// include common helpers, logging and trade wrapper helpers BEFORE engine files
#include "utils\\common.mqh"
#include "logs\\logging.mqh"
#include "utils\\trade_helpers.mqh"
#include "utils\\position_helpers.mqh"

// Hedge includes (action-style) - must exist in hedge\ subfolder
#include "hedge\\hedge_action.mqh"
#include "hedge\\hedge_engine.mqh"

// Debug flag (enable to collect detailed Experts logs)
input bool DebugMode = true;

// ---------------- INPUTS (aligned to CAP baseline) -------------------
// INITIAL TRADE SETTING
input int    Initial_Trade = 2;           // 2 = Auto (CAP)
input int    TradeDirection = 0;          // 0 = Any
input int    PendingPriceType = 1;        // 1 = Distance in points
input double PendingOrderPrice = 0.0;
input bool   ContinuousTrade = true;
input bool   StopEA = false;
input bool   ReverseSignals = false;
input int    MaximumSpreads = 0;
input bool   RemoveHardTPandSL = false;
input bool   DeletePendingOrder = true;
input int    NumberOfLoopTrade = 0;
input int    LotsType = 1;
input double InitialLots = 0.01;
input double XBalance = 1000.0;
input double LotsizePerXBalance = 0.01;
input int    TP_Type_Initial = 0;
input long   TakeProfit = 140000;

// GRID / HEDGE / OTHER (kept)
input int    Grid_Active = 0;
input int    NumberOfGrids = 3;
input int    GridGapType = 0;
input long   FixGridGAP = 3000;
input string CustomGridGAP = "3000;4000;5000;6500";
input int    GridLotsType = 0;
input double GridMultiplier = 1.0;
input string CustomLotsGAP = "0.01;0.0133;0.0177;0.0234";
input bool   DontOpenGridTrade = false;

input int    Hedge_Active = 0;
input int    Hedge_Order_Type = 0;
input int    HedgeGAPType = 3;
input long   HedgeGAP = 8000;
input string HedgeGAP_Custom = "8000;11000;14000;18000;22000";
input int    NumberOfCandle = 14;
input long   MaxDynamicGAP = 30000;
input long   MinDynamicGAP = 2000;
input int    MaxHedgeTrade = 5;
input int    LotTypeHedge = 0;
input double MultipleLotsHedge = 1.33;
input double AddLotsHedge = 0.0;
input string CustomLotsHedge = "0.0133;0.0177;0.0235;0.0313;0.0416";
input string CustomLotsMultipleHedge = "1.33;1.33;1.33;1.33;1.33";
input int    TP_Type_Hedge = 0;
input long   TakeProfit_Hedge = 1200;
input string TakeProfit_Hedge_Custom = "1800;1600;1400;1200;1000;900;800;700;600;500;400;300";

input int    NonHedgeMode = 0;
input bool   AddCurrentLots = false;

input int    LossTakingPolicy = 1;
input long   StopLoss = 45000;           // Stop loss in points
input bool   SetSLForError = true;

input bool   BreakOn = false;
input long   BreakStart = 7500;
input long   BreakStep = 1500;
input bool   StopBreakEventHedge = false;
input bool   TrailingSL = false;
input long   TrailingStop = 15000;
input long   TrailingStep = 1500;
input bool   StopTrailingEventHedge = false;

input int    MaxProfitandLossType = 0;
input double MaxProfit = 0.0;
input double MaxLoss = 0.0;
input bool   ActiveOnlyWhenHedge = false;
input int    MagicNumber = 333334;        // align to CAP baseline
input bool   EmailAlert = false;
input bool   UseNoMagicNumber = false;
input int    Slippage = 300;
input int    GlobalMaxTrade = 0;
input bool   DisableCheckErrorToOpenTrade = false;
input bool   CheckMarketClose = false;
input string InitialTradeComment = "MAIN";
input string HedgeTradeComment = "RICO";
input string GridTradeComment = "GRID";
input bool   AddComissionOnTP = true;
input double TradeCommissionPerLots = 0.0;

input bool   DisplayInfo = true;
input int    DisplayPosition = 0;
input int    TextFontSize = 0;
input int    TextColor = 16777215;
input bool   DrawLineUpcomingNews = true;
input int    MarginType = 0;
input bool   ShowTradePlan = false;
input int    HedgeLineColorTP = 32768;
input int    HedgeLineColorSL = 255;

input int    EnableTime = 0;
input bool   Trade_Filter1 = false;
input string Trade_SetTime1 = "00:00 - 23:40";
input bool   EnableNews = false;
input int    GMT_Mode = 1;
input int    ManualGMTOffset = 0;
input bool   OnlySymbolNews = true;
input bool   LowNews = false;
input int    LowIndentBefore = 280;
input int    LowIndentAfter = 280;
input bool   MediumNews = true;
input int    MidleIndentBefore = 5;
input int    MidleIndentAfter = 5;
input bool   HighNews = true;
input int    HighIndentBefore = 10;
input int    HighIndentAfter = 10;
input bool   CustomNews = false;
input string CustomNewsEvent = "Interest Rate; Press Conference; Nonfarm Payrolls";
input int    CustomIndentBefore = 180;
input int    CustomIndentAfter = 180;
input bool   ShowNewsLine = true;
input int    NewsUrl = 1;
input string CustomUrl = "";

input bool            DontOpenTradeInCandle = false;
input ENUM_TIMEFRAMES DontOpenCandlePeriod = PERIOD_CURRENT;

input int    BBand_Active = 0;
input int    BBand_Strategy = 0;
input ENUM_TIMEFRAMES    BandsTimeFrame = PERIOD_CURRENT;
input int    BandsPeriod = 20;
input int    BandsShift = 0;
input int    BandsPrice = 0;
input double BandsDeviations = 2.0;
input bool   OpenTradeAfterReset = true;
input long   MinimumBandSize = 1000;
input int    SignalBars = 0;
input bool   ReverseBandSignal = false;

input int    ADX_Active = 0;
input ENUM_TIMEFRAMES    ADXTimeFrame = PERIOD_CURRENT;
input int    ADXPeriod = 14;
input int    ADX_Filter_Type = 0;
input double ADX_BUY_Level = 30.0;
input double ADX_SELL_Level = 19.0;
input int    ADX_Entry_Type = 2;
input bool   ADX_Reset_Trade = false;
input int    MinimumADXSize = 0;
input int    ADXSignalBars = 0;
input bool   ReverseAdxSignal = false;

input int    Ichimoku_Active = 1;
input int    Ichim_Signal_Type = 2;
input ENUM_TIMEFRAMES Ichim_TimeFrame = PERIOD_CURRENT;
input int    Ichim_TenkanSen = 17;
input int    Ichim_KijuSen = 20;
input int    Ichim_SenkouB = 60;
input bool   Ichim_OpenTradeReset = false;
input int    Ichim_SignalBars = 0;
input bool   Ichim_ReverseSignal = false;

// INTERNAL STATE
datetime lastInitialOpenTime = 0;
int loopsDone = 0;
int loopCountRemaining = 0;
bool takeover_done = false;

datetime lastOpenCandleTime = 0;    // 記錄最後一次成功開倉時，針對 DontOpenCandlePeriod 的 candle iTime
int    lastOpenDirection = 0;       // 最後一次開倉方向

// Logging globals
string g_run_key = "";
int    g_decision_counter = 0;
int    g_plan_counter = 0;
string g_last_decision_id = "";
string g_last_plan_id = "";

// Hedge integration globals (action-style)
// ---------- AFTER (新增 pending buffer 結構與 vars) ----------
HedgeEngine g_hedge;
HedgeConfig g_hedge_cfg;
bool g_hedge_started = false;
// NEW: gate to avoid repeated MaxReached handling per cycle
bool g_hedge_max_reached_handled = false;
// NEW: remember which decision_id was handled (extra safety; prevents repeated logs when flag logic fails)
string g_last_max_handled_decision_id = "";
// NEW: remember current hedge cycle decision id (cycle-scoped)
string g_hedge_cycle_decision_id = "";

// ================= pending hedgemax buffer (optional mitigation) =================
struct PendingHedgeMax {
   datetime ts;
   int step;
   double maybe_cycle_tp;
   double maybe_net_lots;
   string last_decision_id;
};
#define MAX_PENDING 64
PendingHedgeMax pendingHMs[MAX_PENDING];
int pendingCount = 0;
datetime last_pending_flush_ts = 0;

// push helper
void PushPendingHedgeMax(int step, double maybe_tp, double maybe_net, string last_decision)
{
   if(pendingCount >= MAX_PENDING) pendingCount = 0; // simple wrap/drop strategy
   pendingHMs[pendingCount].ts = TimeCurrent();
   pendingHMs[pendingCount].step = step;
   pendingHMs[pendingCount].maybe_cycle_tp = maybe_tp;
   pendingHMs[pendingCount].maybe_net_lots = maybe_net;
   pendingHMs[pendingCount].last_decision_id = last_decision;
   pendingCount++;
}

// flush helper (try to attribute pending hedgemax to current cycle)
void TryFlushPendingHMs()
{
   if(StringLen(g_hedge_cycle_decision_id) == 0) return;
   double curTP = g_hedge.GetCycleTPPrice();
   double curNet = g_hedge.GetNetLots();
   // tolerance in points (adjust as needed)
   double tol = SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 1000;
   for(int i=0;i<pendingCount;i++)
   {
      if((curNet>0 && pendingHMs[i].maybe_net_lots>0) || (curNet<0 && pendingHMs[i].maybe_net_lots<0))
      {
         if(fabs(pendingHMs[i].maybe_cycle_tp - curTP) <= tol)
         {
            // emit hedgemax under the stable cycle id
            string payload = "{";
            payload += "\"event\":\"HEDGE_MAX_REACHED_from_pending\",";
            payload += "\"step\":" + IntegerToString(pendingHMs[i].step) + ",";
            payload += "\"policy\":" + IntegerToString(LossTakingPolicy);
            payload += "}";
            LOG_CreateEventLine("hedge_max_reached", g_run_key, g_hedge_cycle_decision_id, payload);
            LOG_ConditionalFlush();

            // You may also apply LossTakingPolicy handling here if desired
         }
      }
   }
   // clear buffer after processing
   pendingCount = 0;
   last_pending_flush_ts = TimeCurrent();
}

// Forward declaration (OpenInitialBySignal defined below)
void OpenInitialBySignal(int sig);

// includes
#include "engines\\entry_engine_refactored.mqh"

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
string BuildConfigJson()
{
   // Use shared serializer from common.mqh for consistency
   return SerializeInputsToJson();
}

int OnInit()
  {
   // initialize entry engine first (will stop if ichimoku handle fails)
   EntryEngine_Init();

   // initialize logging and create a run row
   bool log_ok = Logging_Init(DebugMode);
   if(!log_ok) Print("Logging_Init failed - continue without DB logging");
   g_run_key = Symbol() + "_" + TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS);
   string cfg = BuildConfigJson();
   LOG_CreateRun(g_run_key, "growbuddy_run", cfg);

   loopCountRemaining = NumberOfLoopTrade;
   
   // Log startup info into JSONL (if logging is available)
   string initPayload = "{";
   initPayload += "\"event\":\"init\",";
   initPayload += "\"version\":\"1.22\",";
   initPayload += "\"magic\":" + IntegerToString(MagicNumber) + ",";
   initPayload += "\"debug_mode\":\"" + (DebugMode ? "true" : "false") + "\",";
   initPayload += "\"ichim_tf\":" + IntegerToString((int)Ichim_TimeFrame);
   initPayload += "}";
   LOG_CreateEventLine("debug", g_run_key, "", initPayload);
   LOG_ConditionalFlush();
   
   lastOpenCandleTime = 0;
   lastOpenDirection = 0;

   // --- Initialize HedgeEngine config and instance (action-style) ---
   g_hedge_cfg.Hedge_Active = (Hedge_Active != 0);
   g_hedge_cfg.Hedge_Order_Type = Hedge_Order_Type;
   g_hedge_cfg.HedgeGAPType = HedgeGAPType;
   g_hedge_cfg.HedgeGAP = HedgeGAP;
   g_hedge_cfg.HedgeGAP_Custom = HedgeGAP_Custom;
   g_hedge_cfg.MaxHedgeTrade = MaxHedgeTrade;
   g_hedge_cfg.LotTypeHedge = LotTypeHedge;
   g_hedge_cfg.MultipleLotsHedge = MultipleLotsHedge;
   g_hedge_cfg.CustomLotsHedge = CustomLotsHedge;
   g_hedge_cfg.TP_Type_Hedge = TP_Type_Hedge;
   g_hedge_cfg.TakeProfit_Hedge = TakeProfit_Hedge;
   g_hedge_cfg.AddCurrentLots = AddCurrentLots;
   g_hedge_cfg.AddLotsHedge = AddLotsHedge;
   // broker constraints
   g_hedge_cfg.MinLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   g_hedge_cfg.MaxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   g_hedge_cfg.LotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   // init hedge engine (decision id will be assigned when starting cycle)
   g_hedge.Init(g_hedge_cfg, g_last_decision_id);
   g_hedge_started = false;
   
   // record stable cycle-scoped decision id to use for logging and gating
   g_hedge_cycle_decision_id = "";
   
   // NEW: clear the handled marker for safety
   g_hedge_max_reached_handled = false;
   g_last_max_handled_decision_id = "";

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinit                                                    |
//+------------------------------------------------------------------+
// Replace OnDeinit print with structured event (guarded)
void OnDeinit(const int reason)
{
   // Try to log deinit event; if logging already disabled, fallback to Print
   string p = "{";
   p += "\"event\":\"deinit\",";
   p += "\"reason\":" + IntegerToString(reason);
   p += "}";
   // If we can flush/write, use LOG_CreateEventLine; otherwise fallback to Print
   LOG_CreateEventLine("debug", g_run_key, "", p);
   LOG_ConditionalFlush();

   EntryEngine_Deinit();
   Logging_Deinit();
   // Keep a fallback print that always appears in Experts
   Print("GrowBuddy: deinit");
}

//+------------------------------------------------------------------+
//| Expert tick                                                       |
//+------------------------------------------------------------------+
void OnTick()
  {
   if(StopEA) return;

   // spread guard
   if(MaximumSpreads>0)
     {
      int sp = (int)SymbolInfoInteger(_Symbol,SYMBOL_SPREAD);
      if(sp > MaximumSpreads)
        {
         // debug -> write to JSONL via logging.mqh instead of Print
         if(DebugMode)
         {
            string payload = "{";
            payload += "\"event\":\"BlockedByMaximumSpreads\",";
            payload += "\"current_spread\":" + IntegerToString(sp) + ",";
            payload += "\"max_spread\":" + IntegerToString(MaximumSpreads);
            payload += "}";
            LOG_CreateEventLine("debug", g_run_key, "", payload);
            LOG_ConditionalFlush();
         }
         return;
        }
     }

   // time window check (if enabled)
   if(EnableTime != 0)
     {
      if(!IsWithinTradeTime(Trade_SetTime1))
        {
         if(DebugMode)
           {
            string payload = "{";
            payload += "\"event\":\"BlockedByTradeTimeWindow\",";
            payload += "\"time_range\":\"" + Trade_SetTime1 + "\"";
            payload += "}";
            LOG_CreateEventLine("debug", g_run_key, "", payload);
            LOG_ConditionalFlush();
           }
         return;
        }
     }

   // takeover to remove external TP/SL (if requested)
   if(RemoveHardTPandSL && !takeover_done && (Initial_Trade==0 || Initial_Trade==1))
     {
      RemoveHardTPandSL_Takeover();
      takeover_done = true;
      if(DebugMode)
      {
         string payload = "{";
         payload += "\"event\":\"RemoveHardTPandSL_Takeover\",\"status\":\"done\"";
         payload += "}";
         LOG_CreateEventLine("debug", g_run_key, "", payload);
         LOG_ConditionalFlush();
      }
     }

   // Manage loss policy (per-tick permitted)
   ManageLossPolicy();

   // Hedge handling block
   if(g_hedge_cfg.Hedge_Active && g_hedge_started)
   {
      // --- NEW: instrumentation: snapshot EA/engine ids just before engine evaluates actions ---
      if(DebugMode)
      {
         string dbg = "{";
         dbg += "\"event\":\"PreEvaluateNextAction\",";
         dbg += "\"time\":\"" + TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS) + "\",";
         dbg += "\"g_last_decision_id\":\"" + g_last_decision_id + "\",";
         dbg += "\"g_hedge_cycle_decision_id\":\"" + g_hedge_cycle_decision_id + "\",";
         dbg += "\"g_hedge_started\":" + (g_hedge_started ? "true":"false") + ",";
         dbg += "\"cycle_tp\":" + DoubleToString(g_hedge.GetCycleTPPrice(),Digits()) + ",";
         dbg += "\"net_lots\":" + DoubleToString(g_hedge.GetNetLots(),8);
         dbg += "}";
         LOG_CreateEventLine("debug", g_run_key, (StringLen(g_hedge_cycle_decision_id)?g_hedge_cycle_decision_id:g_last_decision_id), dbg);
         LOG_ConditionalFlush();
      }
      // --- end instrumentation ---

      HedgeAction act = g_hedge.EvaluateNextAction();

      // First: check basket TP condition (basket-level close)
      double cycleTP = g_hedge.GetCycleTPPrice();
      double netLots = g_hedge.GetNetLots();
      if(cycleTP > 0.0 && netLots != 0.0)
      {
         double curPrice = (netLots > 0.0) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         bool cycleReached = (netLots > 0.0 && curPrice >= cycleTP) || (netLots < 0.0 && curPrice <= cycleTP);
         if(cycleReached)
         {
            // build payload listing closed tickets for traceability
            string closedList = "[";
            int total = PositionsTotal();
            bool firstItem = true;
            for(int i=total-1;i>=0;i--)
            {
               ulong ptk = PositionGetTicket(i);
               if(ptk==0) continue;
               if(!PositionSelectByTicket(ptk)) continue;
               long magic = (long)PositionGetInteger(POSITION_MAGIC);
               string comm = PositionGetString(POSITION_COMMENT);
               if(!UseNoMagicNumber && magic != MagicNumber && (StringFind(comm,InitialTradeComment) < 0 && StringFind(comm,HedgeTradeComment) < 0)) continue;
               int pos_type = (int)PositionGetInteger(POSITION_TYPE);
               bool closed = false;
               if(pos_type == POSITION_TYPE_BUY || pos_type == POSITION_TYPE_SELL)
               {
                  closed = trade.PositionClose(ptk);
               }
               // append to closed list payload (comma separate properly)
               if(!firstItem) closedList += ",";
               closedList += StringFormat("{\"ticket\":%I64u,\"closed\":%s}", ptk, closed ? "true":"false");
               firstItem = false;
            }
            closedList += "]";

            // inside the cycleReached branch, before LOG_CreateEventLine("hedge_close", ...)
            string close_decision_id = g_hedge_cycle_decision_id;
            if(StringLen(close_decision_id) == 0) close_decision_id = g_last_decision_id;
            
            string closePayload = "{";
            closePayload += "\"decision_id\":\"" + close_decision_id + "\",";
            closePayload += "\"cycle_tp\":" + DoubleToString(cycleTP,Digits()) + ",";
            closePayload += "\"net_lots\":" + DoubleToString(netLots,8) + ",";
            closePayload += "\"closed_positions\":" + closedList;
            closePayload += "}";
            LOG_CreateEventLine("hedge_close", g_run_key, close_decision_id, closePayload);
            LOG_ConditionalFlush();

            // mark hedge cycle ended
            g_hedge_started = false;
            
            // record stable cycle-scoped decision id to use for logging and gating
            g_hedge_cycle_decision_id = "";
            
            // NEW: clear the handled marker for safety
            g_hedge_max_reached_handled = false;
            g_last_max_handled_decision_id = "";

         }
      }

      // nothing to do
      if(act.type == HEDGE_ACT_NONE) { /* no action */ }
      // ---------- AFTER (replace HEDGE_ACT_MAX_REACHED branch with this) ----------
      else if(act.type == HEDGE_ACT_MAX_REACHED)
      {
         // compute stable cycle id for logging: prefer cycle-scoped id
         string cycle_id = g_hedge_cycle_decision_id;
         string fallback_id = g_last_decision_id; // for diagnostics only
      
         // If no cycle_id, we will push to pending buffer (optional) and log warning with context.
         if(StringLen(cycle_id) == 0)
         {
            // push to pending buffer for later reconciliation (if enabled)
            PushPendingHedgeMax(act.step, g_hedge.GetCycleTPPrice(), g_hedge.GetNetLots(), g_last_decision_id);
      
            // log detailed warning (include engine state for later analysis)
            string w = "{";
            w += "\"event\":\"HEDGE_MAX_REACHED_no_cycle_id\",";
            w += "\"ts\":\"" + TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS) + "\",";
            w += "\"note\":\"cycle id empty - pushed to pending buffer\",";
            w += "\"g_last_decision_id\":\"" + fallback_id + "\",";
            w += "\"maybe_cycle_tp\":" + DoubleToString(g_hedge.GetCycleTPPrice(), Digits()) + ",";
            w += "\"maybe_net_lots\":" + DoubleToString(g_hedge.GetNetLots(),8);
            w += "}";
            LOG_CreateEventLine("warning", g_run_key, fallback_id, w);
            LOG_ConditionalFlush();
      
            // DO NOT mark handled or apply LossTakingPolicy now.
         }
         else
         {
            // only mark and handle when we have a stable cycle id
            bool shouldHandle = false;
            if(!g_hedge_max_reached_handled) shouldHandle = true;
            else if(StringLen(g_last_max_handled_decision_id) == 0) shouldHandle = true;
            else if(g_last_max_handled_decision_id != cycle_id) shouldHandle = true;
      
            if(shouldHandle)
            {
               g_hedge_max_reached_handled = true;
               g_last_max_handled_decision_id = cycle_id;
      
               // Build hedgemax payload and include the decision_id (important for tracing)
               string payload = "{";
               payload += "\"event\":\"HEDGE_MAX_REACHED\",";
               payload += "\"decision_id\":\"" + cycle_id + "\",";
               payload += "\"step\":" + IntegerToString(act.step) + ",";
               payload += "\"policy\":" + IntegerToString(LossTakingPolicy);
               payload += "}";
               LOG_CreateEventLine("hedge_max_reached", g_run_key, cycle_id, payload);
               LOG_ConditionalFlush();
      
               // Apply LossTakingPolicy exactly as before, but log with cycle-scoped id for traceability
               if(LossTakingPolicy == 0)
               {
                  if(DebugMode)
                  {
                     string p = "{\"note\":\"LossTakingPolicy disabled\"}";
                     LOG_CreateEventLine("debug", g_run_key, cycle_id, p);
                     LOG_ConditionalFlush();
                  }
               }
               else if(LossTakingPolicy == 1)
               {
                  int total = PositionsTotal();
                  for(int i=0;i<total;i++)
                  {
                     ulong ptk = PositionGetTicket(i);
                     if(ptk==0) continue;
                     if(!PositionSelectByTicket(ptk)) continue;
                     long magic = (long)PositionGetInteger(POSITION_MAGIC);
                     string comm = PositionGetString(POSITION_COMMENT);
                     if(!UseNoMagicNumber && magic != MagicNumber && (StringFind(comm,InitialTradeComment) < 0 && StringFind(comm,HedgeTradeComment) < 0)) continue;
                     double prof = PositionGetDouble(POSITION_PROFIT);
                     if(prof < 0)
                     {
                        bool ok = SafeSetSLByPoints(ptk, StopLoss);
                        if(DebugMode)
                        {
                           string pp = "{";
                           pp += "\"event\":\"SetSLOnLossSide\",\"ticket\":" + IntegerToString((int)ptk) + ",";
                           pp += "\"ok\":" + (ok ? "true":"false");
                           pp += "}";
                           LOG_CreateEventLine("debug", g_run_key, cycle_id, pp);
                           LOG_ConditionalFlush();
                        }
                     }
                  }
               }
               else if(LossTakingPolicy == 2)
               {
                  CloseLatestEAPosition(MagicNumber);
                  if(DebugMode)
                  {
                     string p = "{\"event\":\"CloseLatestEAPosition\",\"magic\":" + IntegerToString(MagicNumber) + "}";
                     LOG_CreateEventLine("debug", g_run_key, cycle_id, p);
                     LOG_ConditionalFlush();
                  }
               }
            }
            else
            {
               // already handled for this cycle - instrument for debugging
               if(DebugMode)
               {
                  string p = "{";
                  p += "\"event\":\"HEDGE_MAX_ALREADY_HANDLED\",";
                  p += "\"decision_id\":\"" + cycle_id + "\"";
                  p += "}";
                  LOG_CreateEventLine("debug", g_run_key, cycle_id, p);
                  LOG_ConditionalFlush();
               }
            }
         }
      }
      else
      {
         // Normal place (pending or market)
         string plan_id = TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS) + "_h" + IntegerToString(act.step);
         string eff_params = "{}";
         string formatted_comment = LOG_FormatOrderCommentWithPlan(HedgeTradeComment, plan_id);

         // prepare SL/TP args: For hedges do NOT pass per-order SL/TP (zone-recovery semantics)
         double sl_arg = 0.0;
         double tp_arg = 0.0;

         // If engine returned non-zero per-order SL/TP, record as warning event and clear them
         if(act.sl > 0.0 || act.tp > 0.0)
         {
            string warnPayload = "{";
            warnPayload += "\"plan_id\":\"" + plan_id + "\",";
            warnPayload += "\"engine_sl\":" + DoubleToString(act.sl, Digits()) + ",";
            warnPayload += "\"engine_tp\":" + DoubleToString(act.tp, Digits()) + ",";
            warnPayload += "\"note\":\"per-order SL/TP cleared for zone-recovery\"";
            warnPayload += "}";
            LOG_CreateEventLine("warning", g_run_key, plan_id, warnPayload);
            LOG_ConditionalFlush();

            // clear them to enforce zone-recovery semantics (no per-order SL/TP)
            act.sl = 0.0;
            act.tp = 0.0;
         }

         if(act.type == HEDGE_ACT_PLACE_PENDING)
         {
            // place pending without per-order sl/tp
            ulong pending_ticket = LoggedPendingOrder(g_run_key, plan_id, (act.side==1?ORDER_TYPE_BUY_STOP:ORDER_TYPE_SELL_STOP), act.lot, act.price, sl_arg, tp_arg, HedgeTradeComment, MagicNumber, Slippage);
            if(pending_ticket == 0)
            {
               // pending failed -> report miss
               g_hedge.OnPendingMiss(act.step, "pending_failed");
               if(SetSLForError)
               {
                  // apply safety SL to losing side positions
                  int total = PositionsTotal();
                  for(int i=0;i<total;i++)
                  {
                     ulong ptk = PositionGetTicket(i);
                     if(ptk==0) continue;
                     if(!PositionSelectByTicket(ptk)) continue;
                     long magic = (long)PositionGetInteger(POSITION_MAGIC);
                     string comm = PositionGetString(POSITION_COMMENT);
                     if(!UseNoMagicNumber && magic != MagicNumber && (StringFind(comm,InitialTradeComment) < 0 && StringFind(comm,HedgeTradeComment) < 0)) continue;
                     double prof = PositionGetDouble(POSITION_PROFIT);
                     if(prof < 0)
                     {
                        //bool ok = SetPositionSL_ByPoints(ptk, StopLoss);
                        bool ok = SafeSetSLByPoints(ptk, StopLoss);
                        // compute log decision id for consistent logging (prefer cycle id)
                        string log_decision_id = g_hedge_cycle_decision_id;
                        if(StringLen(log_decision_id) == 0) log_decision_id = g_last_decision_id;

                        if(DebugMode)
                        {
                           string pp = "{";
                           pp += "\"event\":\"SetSLForErrorApplied\",";
                           pp += "\"ticket\":" + IntegerToString((int)ptk) + ",";
                           pp += "\"ok\":" + (ok ? "true":"false");
                           pp += "}";
                           LOG_CreateEventLine("debug", g_run_key, log_decision_id, pp);
                           LOG_ConditionalFlush();
                        }
                     }
                  }
               }
               // fallback to market (no per-order SL/TP)
               int out_ticket_int = 0;
               bool ok = LoggedMarketOrder(g_run_key, plan_id, act.side, act.lot, 0.0, 0.0, HedgeTradeComment, MagicNumber, Slippage, out_ticket_int);
               if(ok && out_ticket_int != 0)
               {
                  ulong out_ticket_ul = (ulong)out_ticket_int;
                  double execPrice = (act.side==1) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
                  g_hedge.OnOrderFilled(act.step, out_ticket_ul, execPrice, act.lot);
               }
            }
            else
            {
               // pending placed
               g_hedge.OnPendingPlaced(act.step, pending_ticket, act.price);
            }
         }
         else if(act.type == HEDGE_ACT_PLACE_MARKET)
         {
            int out_ticket_int = 0;
            // market order without per-order SL/TP (zone recovery uses basket-level TP)
            bool ok = LoggedMarketOrder(g_run_key, plan_id, act.side, act.lot, 0.0, 0.0, HedgeTradeComment, MagicNumber, Slippage, out_ticket_int);
            if(ok && out_ticket_int != 0)
            {
               ulong out_ticket_ul = (ulong)out_ticket_int;
               double execPrice = (act.side==1) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
               g_hedge.OnOrderFilled(act.step, out_ticket_ul, execPrice, act.lot);
            }
            else
            {
               // market rejected -> log event
               string missPayload = "{";
               missPayload += "\"plan_id\":\"" + plan_id + "\",";
               missPayload += "\"reason\":\"market_rejected\"";
               missPayload += "}";
               LOG_CreateEventLine("hedge_miss", g_run_key, plan_id, missPayload);
               LOG_ConditionalFlush();

               g_hedge.OnPendingMiss(act.step, "market_rejected");
            }
         }
      } // end normal actions
      // try flush any pending hedgemax now that we might have a cycle id
      TryFlushPendingHMs();
   } // end hedge active

   // Only run initial entry when in Auto or Instant mode
   if(Initial_Trade==2 || Initial_Trade==3)
     {
      // use Ichim_TimeFrame to evaluate entry signal (match the built-in indicator)
      int sig = Entry_GetSignal_Refactored(_Symbol, Ichim_TimeFrame);
      if(ReverseSignals) sig = -sig;

      if(DebugMode)
        {
         datetime tfCandle = iTime(_Symbol, Ichim_TimeFrame, 0);
         datetime curCandle = iTime(_Symbol, _Period, 0);
         string payload = "{";
         payload += "\"event\":\"EntryCheck\",";
         payload += "\"time\":\"" + TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS) + "\",";
         payload += "\"signal\":" + IntegerToString(sig) + ",";
         payload += "\"IchimTF\":" + IntegerToString((int)Ichim_TimeFrame) + ",";
         payload += "\"IchimTF_iTime\":\"" + TimeToString(tfCandle, TIME_DATE|TIME_SECONDS) + "\",";
         payload += "\"chartTF\":" + IntegerToString((int)_Period) + ",";
         payload += "\"chart_iTime\":\"" + TimeToString(curCandle, TIME_DATE|TIME_SECONDS) + "\",";
         payload += "\"lastOpenCandleTF\":\"" + (lastOpenCandleTime>0?TimeToString(lastOpenCandleTime,TIME_DATE|TIME_SECONDS):"0") + "\"";
         payload += "}";
         LOG_CreateEventLine("debug", g_run_key, "", payload);
         LOG_ConditionalFlush();
        }

      if(sig != 0)
        {
         // allow open if there is NO existing EA position of the SAME DIRECTION
         bool hasSameDirPos = HasOpenPositionForMagicAndDirection((sig==1)?POSITION_TYPE_BUY:POSITION_TYPE_SELL);

         if(DebugMode)
           {
            string p = "{";
            p += "\"event\":\"SignalHasSameDirPos\",";
            p += "\"signal\":" + IntegerToString(sig) + ",";
            p += "\"hasSameDirPos\":" + (hasSameDirPos ? "true":"false");
            p += "}";
            LOG_CreateEventLine("debug", g_run_key, "", p);
            LOG_ConditionalFlush();
           }

         if(!hasSameDirPos)
           {
            bool blockedByCandleRule = false;
            if(DontOpenTradeInCandle)
              {
               datetime currentCandleTimeForTF = iTime(_Symbol, (ENUM_TIMEFRAMES)DontOpenCandlePeriod, 0);
               if(currentCandleTimeForTF == lastOpenCandleTime) blockedByCandleRule = true;
               if(DebugMode)
               {
                  string p = "{";
                  p += "\"event\":\"DontOpenTradeInCandleCheck\",";
                  p += "\"TF\":" + IntegerToString((int)DontOpenCandlePeriod) + ",";
                  p += "\"curTF_iTime\":\"" + TimeToString(currentCandleTimeForTF) + "\",";
                  p += "\"lastOpen\":\"" + (lastOpenCandleTime>0?TimeToString(lastOpenCandleTime):"0") + "\",";
                  p += "\"blocked\":" + (blockedByCandleRule ? "true":"false");
                  p += "}";
                  LOG_CreateEventLine("debug", g_run_key, "", p);
                  LOG_ConditionalFlush();
               }
              }

            if(!blockedByCandleRule)
              {
               bool okToOpen = TimeToOpenInitial();
               if(DebugMode)
               {
                  string p = "{";
                  p += "\"event\":\"TimeToOpenInitial\",";
                  p += "\"ok\":" + (okToOpen ? "true":"false");
                  p += "}";
                  LOG_CreateEventLine("debug", g_run_key, "", p);
                  LOG_ConditionalFlush();
               }
               if(okToOpen)
                 {
                  double lot = CalculateInitialLot();
                  double sl_price = ComputeInitialSLPrice(sig);
                  double tp_price = ComputeInitialTPPrice(sig, lot);
                  if(DebugMode)
                  {
                     string p = "{";
                     p += "\"event\":\"AttemptingOpenInitialBySignal\",";
                     p += "\"sig\":" + IntegerToString(sig) + ",";
                     p += "\"lot\":" + DoubleToString(lot,4) + ",";
                     p += "\"sl\":" + DoubleToString(sl_price,Digits()) + ",";
                     p += "\"tp\":" + DoubleToString(tp_price,Digits());
                     p += "}";
                     LOG_CreateEventLine("debug", g_run_key, "", p);
                     LOG_ConditionalFlush();
                  }

                  OpenInitialBySignal(sig);

                  if(DontOpenTradeInCandle)
                     lastOpenCandleTime = iTime(_Symbol, (ENUM_TIMEFRAMES)DontOpenCandlePeriod, 0);
                  lastOpenDirection = sig;
                 }
               else
                 {
                  if(DebugMode)
                  {
                     string p = "{\"event\":\"OpenBlocked\",\"reason\":\"TimeToOpenInitial returned false\"}";
                     LOG_CreateEventLine("debug", g_run_key, "", p);
                     LOG_ConditionalFlush();
                  }
                 }
              }
            else
              {
               if(DebugMode)
               {
                  string p = "{\"event\":\"OpenBlocked\",\"reason\":\"DontOpenTradeInCandle (same TF candle)\"}";
                  LOG_CreateEventLine("debug", g_run_key, "", p);
                  LOG_ConditionalFlush();
               }
              }
           }
         else
           {
            if(DebugMode)
            {
               string p = "{\"event\":\"OpenSkipped\",\"reason\":\"existing same-direction EA position found\"}";
               LOG_CreateEventLine("debug", g_run_key, "", p);
               LOG_ConditionalFlush();
            }
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| OpenInitialBySignal (uses Logged wrappers in trade_helpers.mqh)  |
//+------------------------------------------------------------------+
void OpenInitialBySignal(int sig)
  {
   double lot = CalculateInitialLot();
   // Replace: if(lot <= 0.0) { Print("Invalid lot computed"); return; }
   if(lot <= 0.0)
   {
      string payload = "{\"event\":\"InvalidLotComputed\",\"lot\":" + DoubleToString(lot, 8) + "}";
      LOG_CreateEventLine("error", g_run_key, "", payload);
      LOG_ConditionalFlush();
      return;
   }

   // prepare trading context
   // Replace the Print fallback for GlobalMaxTrade
   if(GlobalMaxTrade>0)
   {
      int ourPositions = CountEAOpenPositions();
      if(ourPositions >= GlobalMaxTrade)
      {
         if(DebugMode)
         {
            string payload = "{";
            payload += "\"event\":\"GlobalMaxTradeReached\",";
            payload += "\"our_positions\":" + IntegerToString(ourPositions) + ",";
            payload += "\"limit\":" + IntegerToString(GlobalMaxTrade);
            payload += "}";
            LOG_CreateEventLine("debug", g_run_key, "", payload);
            LOG_ConditionalFlush();
         }
         return;
      }
   }

   // create decision / plan id if needed
   if(StringLen(g_last_decision_id) == 0) g_last_decision_id = TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS) + "_auto";
   string plan_id = GeneratePlanId(g_last_decision_id, g_plan_counter++);
   g_last_plan_id = plan_id;
   string ts = TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS);
   string eff_params = BuildEffectiveParamsJson(LotsType, InitialLots, lot, "{}");
   string formatted_comment = LOG_FormatOrderCommentWithPlan(InitialTradeComment, plan_id);

   double tp_price = ComputeInitialTPPrice(sig, lot);
   double sl_price = ComputeInitialSLPrice(sig);
   double tp_for_trade = (tp_price > 0.0) ? tp_price : 0.0;
   double sl_for_trade = (sl_price > 0.0) ? sl_price : 0.0;

   // create plan row
   bool loggedPlan = CreatePlanAndLog(g_run_key, g_last_decision_id, plan_id, "market", (sig==1?"buy":"sell"), lot, 0.0, sl_for_trade, tp_for_trade, formatted_comment, eff_params);
   if(!loggedPlan)
   {
      string payload = "{";
      payload += "\"event\":\"CreatePlanAndLogFailed\",";
      payload += "\"plan_id\":\"" + plan_id + "\"";
      payload += "}";
      LOG_CreateEventLine("error", g_run_key, plan_id, payload);
      LOG_ConditionalFlush();
   }

   // --- NEW: Snapshot a cycle-scoped decision id EARLY to reduce StartCycle race ---
   if(StringLen(g_last_decision_id) == 0)
      g_last_decision_id = TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS) + "_auto";

   if(!g_hedge_started)
   {
      g_hedge_cycle_decision_id = g_last_decision_id; // snapshot early
      if(DebugMode)
      {
         string dbg = "{";
         dbg += "\"event\":\"PreOrder_SetCycleId\",";
         dbg += "\"ts\":\"" + TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS) + "\",";
         dbg += "\"g_last_decision_id\":\"" + g_last_decision_id + "\"";
         dbg += "}";
         LOG_CreateEventLine("debug", g_run_key, g_hedge_cycle_decision_id, dbg);
         LOG_ConditionalFlush();
      }
   }
   // --- end new snapshot ---

   // Execute market order through logged wrapper
   int out_ticket = 0;
   bool ok = LoggedMarketOrder(g_run_key, plan_id, (sig==1?1:-1), lot, sl_for_trade, tp_for_trade, InitialTradeComment, MagicNumber, Slippage, out_ticket);

   // Replace: PrintFormat("OpenInitialBySignal: LoggedMarketOrder failed for plan=%s", plan_id);
   if(!ok)
   {
      string payload = "{";
      payload += "\"event\":\"LoggedMarketOrderFailed\",";
      payload += "\"plan_id\":\"" + plan_id + "\"";
      payload += "}";
      LOG_CreateEventLine("error", g_run_key, plan_id, payload);
      LOG_ConditionalFlush();
   
      if(SetSLForError) ProtectOnError(); // keep existing recovery behavior
      return;
   }

   // Replace Start-cycle block in OpenInitialBySignal with this safer sequence:
   // - snapshot g_hedge_cycle_decision_id before StartCycle (to avoid StartCycle-internal actions missing the id)
   // - call g_hedge.StartCycle
   // - set g_hedge_started only after StartCycle (defensive)

   // --- Start hedge cycle when initial order executed ---
   if(ok && out_ticket != 0)
   {
      double entry_price = 0.0;
      if(PositionSelectByTicket((ulong)out_ticket))
         entry_price = PositionGetDouble(POSITION_PRICE_OPEN);
      else
         entry_price = (sig==1) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);

      // Ensure a stable decision id exists for this open
      if(StringLen(g_last_decision_id) == 0)
         g_last_decision_id = TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS) + "_auto";

      // ONLY start a new hedge cycle if none already started.
      if(!g_hedge_started)
      {
         // Snapshot cycle id *before* calling StartCycle to avoid race where StartCycle triggers actions immediately.
         g_hedge_cycle_decision_id = g_last_decision_id;

         // Debug snapshot (include more context)
         if(DebugMode)
         {
            string dbg = "{";
            dbg += "\"event\":\"StartCycleSnapshot\",";
            dbg += "\"ts\":\"" + TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS) + "\",";
            dbg += "\"g_last_decision_id\":\"" + g_last_decision_id + "\",";
            dbg += "\"g_hedge_cycle_decision_id\":\"" + g_hedge_cycle_decision_id + "\",";
            dbg += "\"entry_price\":" + DoubleToString(entry_price,Digits());
            dbg += "}";
            LOG_CreateEventLine("debug", g_run_key, g_hedge_cycle_decision_id, dbg);
            LOG_ConditionalFlush();
         }

         // Initialize and start hedge cycle using the stable decision id already snapshot.
         g_hedge.Init(g_hedge_cfg, g_hedge_cycle_decision_id);
         g_hedge.StartCycle(entry_price, (sig==1?1:-1), lot);

         // mark hedge started (we assume StartCycle completed synchronously successfully).
         g_hedge_started = true;

         // reset hedgemax handled marker
         g_hedge_max_reached_handled = false;
         g_last_max_handled_decision_id = "";

         // LOG: emit hedge_cycle using the cycle-scoped id
         double cycleTP = g_hedge.GetCycleTPPrice();
         double netLots = g_hedge.GetNetLots();
         string cycle_id = g_hedge_cycle_decision_id;
         string payload = "{";
         payload += "\"decision_id\":\"" + cycle_id + "\",";
         payload += "\"initial_price\":" + DoubleToString(entry_price,Digits()) + ",";
         payload += "\"initial_lot\":" + DoubleToString(lot,2) + ",";
         payload += "\"cycle_tp\":" + DoubleToString(cycleTP, Digits()) + ",";
         payload += "\"net_lots\":" + DoubleToString(netLots, 8);
         payload += "}";
         LOG_CreateEventLine("hedge_cycle", g_run_key, cycle_id, payload);
         LOG_ConditionalFlush();
      }
      else
      {
         // already started: log debug so we can trace duplicate open attempts
         if(DebugMode)
         {
            string p = "{";
            p += "\"event\":\"StartCycleSkipped\",";
            p += "\"reason\":\"hedge_already_started\",";
            p += "\"existing_cycle_id\":\"" + (StringLen(g_hedge_cycle_decision_id) ? g_hedge_cycle_decision_id : g_last_decision_id) + "\"";
            p += "}";
            LOG_CreateEventLine("debug", g_run_key, (StringLen(g_hedge_cycle_decision_id)?g_hedge_cycle_decision_id:g_last_decision_id), p);
            LOG_ConditionalFlush();
         }
      }
   }
   // --- Hedge integration end ---

   lastInitialOpenTime = TimeCurrent();
   //PrintFormat("OpenInitialBySignal: opened dir=%d lot=%.3f sl=%.5f tp=%.5f ticket=%d", sig, lot, sl_for_trade, tp_for_trade, out_ticket);
   // Replace the PrintFormat that logs the opened trade
   string openedPayload = "{";
   openedPayload += "\"event\":\"OpenInitialBySignalOpened\",";
   openedPayload += "\"direction\":" + IntegerToString(sig) + ",";
   openedPayload += "\"lot\":" + DoubleToString(lot, 4) + ",";
   openedPayload += "\"sl\":" + DoubleToString(sl_for_trade, Digits()) + ",";
   openedPayload += "\"tp\":" + DoubleToString(tp_for_trade, Digits()) + ",";
   openedPayload += "\"ticket\":" + IntegerToString(out_ticket);
   openedPayload += "}";
   LOG_CreateEventLine("execution", g_run_key, plan_id, openedPayload);
   LOG_ConditionalFlush();
  }
//+------------------------------------------------------------------+