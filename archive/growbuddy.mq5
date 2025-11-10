//+------------------------------------------------------------------+
//| GrowBuddy - CAP-aligned EA (v1.22 final)                         |
//| - Uses built-in iIchimoku via entry_engine_refactored.mqh        |
//| - No fallback: if built-in indicator fails EA will stop          |
//| - Full helper functions included so file is self-contained       |
//+------------------------------------------------------------------+
#property copyright "Trade Buddy"
#property version   "1.22"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

// include logging BEFORE engine files so engine can call LOG_* directly
#include "logs\\logging.mqh"

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

// includes
#include "engines\\entry_engine_refactored.mqh"

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
string BuildConfigJson()
{
   double vol_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   // include key inputs - expand as needed
   string json = StringFormat(
     "{\"Ichim_TenkanSen\":%d,\"Ichim_KijuSen\":%d,\"Ichim_SenkouB\":%d,\"LotsType\":%d,\"InitialLots\":%.6f,\"SYMBOL_VOLUME_STEP\":%.6f,\"SYMBOL_DIGITS\":%d,\"MagicNumber\":%d}",
     Ichim_TenkanSen, Ichim_KijuSen, Ichim_SenkouB, LotsType, InitialLots, vol_step, digits, MagicNumber);
   return json;
}

int OnInit()
  {
   // initialize entry engine first (will stop if ichimoku handle fails)
   EntryEngine_Init();

   // initialize logging and create a run row
   bool log_ok = Logging_Init(true, DB_DEFAULT_SHORTNAME, 5000);
   if(!log_ok) Print("Logging_Init failed - continue without DB logging");
   g_run_key = Symbol() + "_" + TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS);
   string cfg = BuildConfigJson();
   LOG_CreateRun(g_run_key, "growbuddy_run", cfg);

   loopCountRemaining = NumberOfLoopTrade;
   PrintFormat("GrowBuddy v1.22 init - Magic=%d DebugMode=%s IchimTF=%d", MagicNumber, (DebugMode ? "true":"false"), (int)Ichim_TimeFrame);
   lastOpenCandleTime = 0;
   lastOpenDirection = 0;
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinit                                                    |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   Logging_Deinit();
   EntryEngine_Deinit();
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
         if(DebugMode) PrintFormat("Blocked by MaximumSpreads: cur=%d max=%d", sp, MaximumSpreads);
         return;
        }
     }

   // time window check (if enabled)
   if(EnableTime != 0)
     {
      if(!IsWithinTradeTime(Trade_SetTime1))
        {
         if(DebugMode) Print("Blocked by Trade_SetTime1 window");
         return;
        }
     }

   // takeover to remove external TP/SL (if requested)
   if(RemoveHardTPandSL && !takeover_done && (Initial_Trade==0 || Initial_Trade==1))
     {
      RemoveHardTPandSL_Takeover();
      takeover_done = true;
     }

   // Manage loss policy (per-tick permitted)
   ManageLossPolicy();

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
         PrintFormat("Entry check - time=%s sig=%d IchimTF=%d IchimTF_iTime=%s chartTF=%d chart_iTime=%s lastOpenCandleTF=%s",
                     TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS), sig, (int)Ichim_TimeFrame,
                     TimeToString(tfCandle, TIME_DATE|TIME_SECONDS), (int)_Period, TimeToString(curCandle, TIME_DATE|TIME_SECONDS),
                     (lastOpenCandleTime>0?TimeToString(lastOpenCandleTime,TIME_DATE|TIME_SECONDS):"0"));
        }

      if(sig != 0)
        {
         // allow open if there is NO existing EA position of the SAME DIRECTION
         bool hasSameDirPos = HasOpenPositionForMagicAndDirection((sig==1)?POSITION_TYPE_BUY:POSITION_TYPE_SELL);

         if(DebugMode) PrintFormat("Signal=%d hasSameDirPos=%s", sig, (hasSameDirPos ? "true":"false"));

         if(!hasSameDirPos)
           {
            bool blockedByCandleRule = false;
            if(DontOpenTradeInCandle)
              {
               datetime currentCandleTimeForTF = iTime(_Symbol, (ENUM_TIMEFRAMES)DontOpenCandlePeriod, 0);
               if(currentCandleTimeForTF == lastOpenCandleTime) blockedByCandleRule = true;
               if(DebugMode) PrintFormat("DontOpenTradeInCandle TF=%d curTFiTime=%s lastOpen=%s blocked=%s", (int)DontOpenCandlePeriod, TimeToString(currentCandleTimeForTF), (lastOpenCandleTime>0?TimeToString(lastOpenCandleTime):"0"), (blockedByCandleRule?"true":"false"));
              }

            if(!blockedByCandleRule)
              {
               bool okToOpen = TimeToOpenInitial();
               if(DebugMode) PrintFormat("TimeToOpenInitial returned %s", (okToOpen ? "true":"false"));
               if(okToOpen)
                 {
                  double lot = CalculateInitialLot();
                  double sl_price = ComputeInitialSLPrice(sig);
                  double tp_price = ComputeInitialTPPrice(sig, lot);
                  if(DebugMode) PrintFormat("Attempting OpenInitialBySignal sig=%d lot=%.4f sl=%.5f tp=%.5f", sig, lot, sl_price, tp_price);

                  OpenInitialBySignal(sig);

                  if(DontOpenTradeInCandle)
                     lastOpenCandleTime = iTime(_Symbol, (ENUM_TIMEFRAMES)DontOpenCandlePeriod, 0);
                  lastOpenDirection = sig;
                 }
               else
                 {
                  if(DebugMode) Print("Open blocked by TimeToOpenInitial()");
                 }
              }
            else
              {
               if(DebugMode) Print("Open blocked by DontOpenTradeInCandle (same TF candle)");
              }
           }
         else
           {
            if(DebugMode) Print("Open skipped: existing same-direction EA position found");
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Helpers                                                           |
//+------------------------------------------------------------------+
bool HasOpenPositionForMagicAndDirection(const long position_type)
  {
   int total = PositionsTotal();
   for(int i=0;i<total;i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket==0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      long magic = PositionGetInteger(POSITION_MAGIC);
      if(!UseNoMagicNumber && magic != MagicNumber) continue;
      long ptype = PositionGetInteger(POSITION_TYPE);
      string comm = PositionGetString(POSITION_COMMENT);
      if(ptype == position_type && StringFind(comm, InitialTradeComment) >= 0)
         return true;
     }
   return false;
  }

int CountEAOpenPositions()
  {
   int cnt=0;
   int total = PositionsTotal();
   for(int i=0;i<total;i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket==0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      long magic = PositionGetInteger(POSITION_MAGIC);
      if(!UseNoMagicNumber && magic != MagicNumber) continue;
      cnt++;
     }
   return cnt;
  }

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

// Opening helper functions and trade utilities
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

void OpenInitialBySignal(int sig)
  {
   double lot = CalculateInitialLot();
   if(lot <= 0.0) { Print("Invalid lot computed"); return; }

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(Slippage);

   if(GlobalMaxTrade>0)
     {
      int ourPositions = CountEAOpenPositions();
      if(ourPositions >= GlobalMaxTrade) { if(DebugMode) Print("GlobalMaxTrade reached"); return; }
     }

   // create plan id for this attempt
   if(StringLen(g_last_decision_id) == 0) g_last_decision_id = TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS) + "_auto";
   string plan_id = g_last_decision_id + "_p" + IntegerToString(g_plan_counter++);
   g_last_plan_id = plan_id;
   string ts = TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS);
   string eff_params = StringFormat("{\"LotsType\":%d,\"InitialLots\":%.6f}", LotsType, InitialLots);
   string formatted_comment = LOG_FormatOrderCommentWithPlan(InitialTradeComment, plan_id);

   // forced pending type handling if TradeDirection indicates
   if(TradeDirection >= 3 && TradeDirection <= 6)
     {
      ENUM_ORDER_TYPE orderType = ORDER_TYPE_BUY_STOP;
      switch(TradeDirection)
        {
         case 3: orderType = ORDER_TYPE_BUY_STOP; break;
         case 4: orderType = ORDER_TYPE_SELL_STOP; break;
         case 5: orderType = ORDER_TYPE_BUY_LIMIT; break;
         case 6: orderType = ORDER_TYPE_SELL_LIMIT; break;
        }
      double sl_price = ComputeInitialSLPrice((orderType==ORDER_TYPE_BUY_STOP || orderType==ORDER_TYPE_BUY_LIMIT) ? 1 : -1);
      double tp_price = ComputeInitialTPPrice((orderType==ORDER_TYPE_BUY_STOP || orderType==ORDER_TYPE_BUY_LIMIT) ? 1 : -1, lot);

      // log plan (pending)
      LOG_InsertPlan(g_run_key, g_last_decision_id, plan_id, ts, "pending", (sig==1?"buy":"sell"), lot, 0.0, sl_price, tp_price, formatted_comment, eff_params, "{}");

      ulong reqTicket = PlacePendingInitialOrder(orderType, lot, sig, sl_price, tp_price);
      if(reqTicket != 0 && DeletePendingOrder)
         DeleteOtherPendingOrders(reqTicket);
      lastInitialOpenTime = TimeCurrent();
      return;
     }

   double tp_price = ComputeInitialTPPrice(sig, lot);
   double sl_price = ComputeInitialSLPrice(sig);
   double tp_for_trade = (tp_price > 0.0) ? tp_price : 0.0;
   double sl_for_trade = (sl_price > 0.0) ? sl_price : 0.0;

   // log plan (market)
   LOG_InsertPlan(g_run_key, g_last_decision_id, plan_id, ts, "market", (sig==1?"buy":"sell"), lot, 0.0, sl_for_trade, tp_for_trade, formatted_comment, eff_params, "{}");

   bool ok=false;
   if(sig==1) ok = trade.Buy(lot, NULL, 0.0, sl_for_trade, tp_for_trade, formatted_comment);
   else if(sig==-1) ok = trade.Sell(lot, NULL, 0.0, sl_for_trade, tp_for_trade, formatted_comment);

   uint ret = (uint)trade.ResultRetcode();
   string retDesc = trade.ResultRetcodeDescription();
   ulong order_ticket = trade.ResultOrder();
   double filled_price = trade.ResultPrice();
   
   string req_json = StringFormat("{\"type\":\"market\",\"volume\":%.6f,\"sl\":%.6f,\"tp\":%.6f,\"comment\":\"%s\"}", lot, sl_for_trade, tp_for_trade, formatted_comment);
   // use IntegerToString to include unsigned ret safely in JSON string
   string res_json = StringFormat("{\"retcode\":%s,\"desc\":\"%s\",\"order\":%I64u}", IntegerToString((int)ret), retDesc, order_ticket);
   
   // log execution - explicit cast to int for LOG_InsertExecution param
   LOG_InsertExecution(g_run_key, plan_id, TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS), req_json, res_json, (int)ret, retDesc, (int)order_ticket, filled_price, sl_for_trade, tp_for_trade);

   if(!ok)
     {
      PrintFormat("OpenInitialBySignal: Order failed ret=%d desc=%s", ret, retDesc);
      if(SetSLForError) ProtectOnError();
      return;
     }

   lastInitialOpenTime = TimeCurrent();
   PrintFormat("OpenInitialBySignal: opened dir=%d lot=%.3f sl=%.5f tp=%.5f", sig, lot, sl_for_trade, tp_for_trade);
  }

ulong PlacePendingInitialOrder(const ENUM_ORDER_TYPE orderType, const double lot, const int sig, const double sl_price, const double tp_price)
  {
   MqlTradeRequest req;
   MqlTradeResult  res;
   ZeroMemory(req); ZeroMemory(res);
   req.action = TRADE_ACTION_PENDING;
   req.symbol = _Symbol;
   req.volume = lot;
   req.type = orderType;
   req.magic = MagicNumber;
   req.deviation = Slippage;
   req.comment = InitialTradeComment;
   req.type_filling = ORDER_FILLING_RETURN;

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double price = 0.0;
   if(PendingPriceType == 0)
      price = NormalizeDouble(PendingOrderPrice, digits);
   else
     {
      double dist = PendingOrderPrice * point;
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if(orderType == ORDER_TYPE_BUY_STOP) price = NormalizeDouble(ask + dist, digits);
      else if(orderType == ORDER_TYPE_SELL_STOP) price = NormalizeDouble(bid - dist, digits);
      else if(orderType == ORDER_TYPE_BUY_LIMIT) price = NormalizeDouble(ask - dist, digits);
      else if(orderType == ORDER_TYPE_SELL_LIMIT) price = NormalizeDouble(bid + dist, digits);
      else price = NormalizeDouble((ask+bid)/2.0, digits);
     }

   req.price = price;
   req.tp = (tp_price > 0.0) ? tp_price : 0.0;
   req.sl = (sl_price > 0.0) ? sl_price : 0.0;
   // add plan id to comment if available
   if(StringLen(g_last_plan_id) > 0)
      req.comment = LOG_FormatOrderCommentWithPlan(InitialTradeComment, g_last_plan_id);

   if(!OrderSend(req, res))
     {
      PrintFormat("PlacePendingInitialOrder: OrderSend failed (OrderSend returned false)");
      return(0);
     }
   if(res.retcode != TRADE_RETCODE_DONE && res.retcode != TRADE_RETCODE_PLACED)
     {
      PrintFormat("PlacePendingInitialOrder: failed ret=%d comment=%s", res.retcode, res.comment);
      // log execution attempt with failure
      string req_json = StringFormat("{\"type\":\"pending\",\"volume\":%.6f,\"price\":%.*f,\"sl\":%.6f,\"tp\":%.6f,\"comment\":\"%s\"}", lot, digits, price, sl_price, tp_price, req.comment);
      string res_json = StringFormat("{\"retcode\":%d,\"comment\":\"%s\"}", res.retcode, res.comment);
      if(StringLen(g_last_plan_id)>0) LOG_InsertExecution(g_run_key, g_last_plan_id, TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS), req_json, res_json, res.retcode, res.comment, 0, 0.0, sl_price, tp_price);
      return(0);
     }

   PrintFormat("PlacePendingInitialOrder: placed ticket=%I64u type=%d price=%.*f sl=%.5f tp=%.5f", res.order, orderType, digits, price, req.sl, req.tp);

   // log successful placement
   string req_json = StringFormat("{\"type\":\"pending\",\"volume\":%.6f,\"price\":%.*f,\"sl\":%.6f,\"tp\":%.6f,\"comment\":\"%s\"}", lot, digits, price, sl_price, tp_price, req.comment);
   string res_json = StringFormat("{\"retcode\":%d,\"comment\":\"%s\",\"order\":%I64u}", res.retcode, res.comment, res.order);
   if(StringLen(g_last_plan_id)>0) LOG_InsertExecution(g_run_key, g_last_plan_id, TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS), req_json, res_json, res.retcode, res.comment, (int)res.order, price, sl_price, tp_price);

   return(res.order);
  }

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
               SetPositionStopLoss_Modify(ticket, StopLoss);
              }
           }
        }
      else if(LossTakingPolicy==2)
        {
         CloseLatestTradeByMagic();
        }
     }
  }

void CloseLatestTradeByMagic()
  {
   datetime latest = 0;
   ulong latestTicket = 0;
   int total = PositionsTotal();
   for(int i=0; i<total; i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket==0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      long magic = (long)PositionGetInteger(POSITION_MAGIC);
      string comm = PositionGetString(POSITION_COMMENT);
      if(!(magic==MagicNumber || StringFind(comm,InitialTradeComment)>=0 || UseNoMagicNumber)) continue;
      datetime t = (datetime)PositionGetInteger(POSITION_TIME);
      if(t>latest) { latest = t; latestTicket = ticket; }
     }

   if(latestTicket>0)
     {
      if(!trade.PositionClose(latestTicket,Slippage))
         PrintFormat("CloseLatestTradeByMagic: failed to close ticket=%I64u rc=%d", latestTicket, trade.ResultRetcode());
      else
         PrintFormat("CloseLatestTradeByMagic: closed ticket=%I64u", latestTicket);
     }
  }

bool SetPositionStopLoss_Modify(const ulong ticket, const long sl_points)
  {
   if(ticket==0) return(false);
   if(!PositionSelectByTicket(ticket)) return(false);
   int type = (int)PositionGetInteger(POSITION_TYPE);
   double point = SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
   double price = (type==POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol,SYMBOL_BID) : SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double new_sl = (type==POSITION_TYPE_BUY) ? price - sl_points * point : price + sl_points * point;
   new_sl = NormalizeDouble(new_sl, digits);
   double current_tp = PositionGetDouble(POSITION_TP);

   bool ok = trade.PositionModify(ticket, new_sl, current_tp);
   if(!ok)
     {
      Sleep(100);
      ok = trade.PositionModify(ticket, new_sl, current_tp);
      if(!ok) return(false);
     }
   return(true);
  }

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
      trade.PositionClose(ticket,Slippage);
     }
  }

// Simple TimeToOpenInitial implementation (basic checks)
bool TimeToOpenInitial()
  {
   if(StopEA) return(false);
   // check symbol trading properties exist
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(minLot <= 0 || step <= 0)
     {
      PrintFormat("TimeToOpenInitial: symbol volume info missing for %s (min=%.6f step=%.6f). Blocking open.", _Symbol, minLot, step);
      return(false);
     }
   // simple free margin check
   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   if(freeMargin > 0)
     {
      double conservativeNeeded = 50.0 * MathMax(InitialLots, minLot); // conservative per lot requirement
      if(freeMargin < conservativeNeeded)
        {
         PrintFormat("TimeToOpenInitial: freeMargin(%.2f) < conservativeNeeded(%.2f) - blocking open.", freeMargin, conservativeNeeded);
         return(false);
        }
     }
   return(true);
  }

//+------------------------------------------------------------------+