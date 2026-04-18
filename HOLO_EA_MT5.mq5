//+------------------------------------------------------------------+
//|                                      HOLO_EA_MT5_multisymbol_grid|
//+------------------------------------------------------------------+
#property copyright "OpenAI"
#property version   "1.30"
#property strict

#include <Trade/Trade.mqh>

CTrade trade;

enum ENUM_HOLO_LOG_LEVEL
{
   LOG_NONE = 0,
   LOG_ERROR,
   LOG_INFO,
   LOG_DEBUG
};

enum ENUM_RISK_MODE
{
   RISK_LOW = 0,
   RISK_MEDIUM = 1,
   RISK_HIGH = 2
};

input group "=== Master ==="
input bool   InpEnableEA                = true;
input ulong  InpMagic                   = 26040301;
input ENUM_HOLO_LOG_LEVEL InpLogLevel   = LOG_INFO;

input group "=== Symbols ==="
input string InpSymbols                 = "AUDCAD,AUDNZD,CADCHF,EURAUD,EURCAD,EURGBP,GBPCAD,NZDCAD,NZDCHF,GBPCHF,USDJPY";

input group "=== Trading Window ==="
input int    InpServerStartHour         = 5;
input int    InpServerEndHour           = 21;
input int    InpCooldownMinutesAfterSL  = 5;

input group "=== Order Placement ==="
input double InpLots                    = 0.10;
input int    InpMaxSpreadPips           = 3;
input bool   InpCancelOppositeOnFill    = true;
input bool   InpReplacePendingOnChange  = true;
input int    InpEntryBufferPoints       = 0;
input int    InpMinStopDistancePips     = 5;

input group "=== Lot Sizing ==="
input ENUM_RISK_MODE InpRiskMode        = RISK_LOW;
input double InpRiskLowPct              = 0.25;
input double InpRiskMedPct              = 0.50;
input double InpRiskHighPct             = 1.00;
input bool   InpUseSLBasedLot           = true;
input double InpFallbackLot             = 0.10;

input group "=== Signal Filters ==="
input int    ATR_Period                 = 100;
input double InpMinRangeAtrPct          = 50.0;
input double InpSignalTolerancePips     = 1.0;
input bool   InpUseClosedM15Open        = false;
input bool   InpRequirePriceInZone      = true;
input bool   InpRejectIfYesterdayBroken = true;
input bool   InpRejectIfDailyExtremeBroken = true;

input group "=== Grid Basket ==="
input bool   InpUseGridBasket           = true;
input int    InpGridGapPips             = 12;
input int    InpGridMaxLevels           = 10;
input double InpGridLotMultiplier       = 1.03;
input double InpGridProfitPctBalance    = 0.12;
input bool   InpGridUseAnchorHardStop   = false;
input bool   InpGridUseBasketTrail      = true;
input double InpGridTrailArmPctTarget   = 60.0;
input double InpGridTrailRetracePctPeak = 35.0;

input group "=== Trade Management ==="
input bool   InpUseBreakEven            = true;
input double InpBE_Trigger_Pips         = 5.0;
input double InpBE_Lock_Pips            = 1.0;
input bool   InpUseTrailing             = true;
input double InpTrailStart_Pips         = 10.0;
input double InpTrailDistance_Pips      = 5.0;
input double InpTrailStep_Pips          = 1.0;

input group "=== Visuals ==="
input bool   Show_H1_Lines              = true;
input bool   Show_Daily_Lines           = true;
input bool   Show_Yesterday_Lines       = true;
input bool   Show_DaySeparator          = true;
input bool   Show_AreaOfInterest        = true;
input bool   Show_PendingMarkers        = true;
input bool   InpShowPanel               = true;
input bool   InpStyleChart              = true;

input color  Color_HO                   = clrMaroon;
input color  Color_LO                   = clrDodgerBlue;
input color  Color_DailyHigh            = clrCoral;
input color  Color_DailyLow             = clrCornflowerBlue;
input color  Color_YesterdayHigh        = clrOrangeRed;
input color  Color_YesterdayLow         = clrRoyalBlue;
input color  Color_DaySeparator         = clrDimGray;
input color  Color_AOI_Short            = clrNONE;
input color  Color_AOI_Long             = clrNONE;
input int    LineWidth_HO_LO            = 2;
input int    LineWidth_Daily            = 1;

input group "=== Performance ==="
input bool   InpThrottleVisualsInTester = true;
input int    InpVisualRefreshMs         = 250;

color tmdBg       = C'10,16,28';
color tmdSubtleBg = C'25,40,55';
color tmdSilver   = C'192,202,214';
color tmdGreen    = C'0,200,120';
color tmdRed      = C'230,70,70';
color tmdOrange   = C'255,165,0';
color tmdBid      = C'0,170,255';
color tmdAsk      = C'255,120,0';

string PREFIX = "HOLOEA_";
string g_panelObjs[];
ulong  g_lastVisualRefreshMs = 0;
datetime g_lastVisualBarTime = 0;
datetime g_cooldownUntil = 0;
string g_lastSLReason = "-";

struct SymbolState
{
   string symbol;
   int    digits;
   double point;
   double pip;
   int    atrHandle;
   double dailyHigh;
   double dailyLow;
   double yesterdayHigh;
   double yesterdayLow;
   double hoH1;
   double loH1;
   double rangeAtrPct;
   double bid;
   double ask;
   double spreadPips;
   double m15Open;
   bool   sellSignal;
   bool   buySignal;
   bool   sellM15Ok;
   bool   buyM15Ok;
   string buyReason;
   string sellReason;
};

struct SignalContext
{
   bool   levelsValid;
   bool   sellZoneValid;
   bool   buyZoneValid;
   bool   inSellZone;
   bool   inBuyZone;
   bool   atrOk;
   bool   sellM15Ok;
   bool   buyM15Ok;
   bool   yesterdayHighBroken;
   bool   yesterdayLowBroken;
   bool   dailyExtremeSellBroken;
   bool   dailyExtremeBuyBroken;
   bool   sellStopDistanceOk;
   bool   buyStopDistanceOk;
   bool   sellSignal;
   bool   buySignal;
   double bid;
   double ask;
   double spreadPips;
   double m15Open;
   string sellReason;
   string buyReason;
};

struct BasketState
{
   bool     active;
   string   symbol;
   int      symbolIndex;
   int      direction;
   int      levels;
   double   lastAddPrice;
   double   anchorSL;
   double   baseLots;
   bool     trailActive;
   double   trailPeakPnl;
   datetime startTime;
   string   closeReason;
};

SymbolState g_states[];
BasketState g_basket = {false, "", -1, -1, 0, 0.0, 0.0, 0.0, false, 0.0, 0, "-"};

void LogMsg(const ENUM_HOLO_LOG_LEVEL level, const string msg)
{
   if((int)InpLogLevel >= (int)level)
      Print("[HOLO_EA] ", msg);
}

string Trim(const string s)
{
   string t = s;
   StringTrimLeft(t);
   StringTrimRight(t);
   return t;
}

string FitPanelText(const string text, const int maxLen)
{
   int len = StringLen(text);
   if(len <= maxLen)
      return text;
   if(maxLen <= 3)
      return StringSubstr(text, 0, maxLen);
   return StringSubstr(text, 0, maxLen - 3) + "...";
}

string FormatServerDateTime(const datetime when)
{
   MqlDateTime tm;
   TimeToStruct(when, tm);
   return StringFormat("%02d/%02d/%04d %02d:%02d:%02d", tm.day, tm.mon, tm.year, tm.hour, tm.min, tm.sec);
}

double GetRiskPercent()
{
   switch(InpRiskMode)
   {
      case RISK_LOW:    return InpRiskLowPct;
      case RISK_MEDIUM: return InpRiskMedPct;
      case RISK_HIGH:   return InpRiskHighPct;
   }
   return InpRiskMedPct;
}

int GetStateIndexBySymbol(const string sym)
{
   for(int i = 0; i < ArraySize(g_states); i++)
      if(g_states[i].symbol == sym)
         return i;
   return -1;
}

bool ParseSymbols()
{
   string parts[];
   int n = StringSplit(InpSymbols, ',', parts);
   if(n <= 0)
      return false;

   ArrayResize(g_states, 0);
   for(int i = 0; i < n; i++)
   {
      string sym = Trim(parts[i]);
      if(sym == "")
         continue;
      if(!SymbolSelect(sym, true))
      {
         LogMsg(LOG_ERROR, "failed SymbolSelect for " + sym);
         continue;
      }

      int idx = ArraySize(g_states);
      ArrayResize(g_states, idx + 1);
      g_states[idx].symbol        = sym;
      g_states[idx].digits        = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
      g_states[idx].point         = SymbolInfoDouble(sym, SYMBOL_POINT);
      g_states[idx].pip           = ((g_states[idx].digits == 5 || g_states[idx].digits == 3) ? g_states[idx].point * 10.0 : g_states[idx].point);
      g_states[idx].atrHandle     = iATR(sym, PERIOD_D1, ATR_Period);
      g_states[idx].dailyHigh     = 0.0;
      g_states[idx].dailyLow      = 0.0;
      g_states[idx].yesterdayHigh = 0.0;
      g_states[idx].yesterdayLow  = 0.0;
      g_states[idx].hoH1          = 0.0;
      g_states[idx].loH1          = 0.0;
      g_states[idx].rangeAtrPct   = 0.0;
      g_states[idx].bid           = 0.0;
      g_states[idx].ask           = 0.0;
      g_states[idx].spreadPips    = 0.0;
      g_states[idx].m15Open       = 0.0;
      g_states[idx].sellSignal    = false;
      g_states[idx].buySignal     = false;
      g_states[idx].sellM15Ok     = false;
      g_states[idx].buyM15Ok      = false;
      g_states[idx].buyReason     = "-";
      g_states[idx].sellReason    = "-";
   }
   return (ArraySize(g_states) > 0);
}

void ReleaseSymbols()
{
   for(int i = 0; i < ArraySize(g_states); i++)
   {
      if(g_states[i].atrHandle != INVALID_HANDLE)
         IndicatorRelease(g_states[i].atrHandle);
      g_states[i].atrHandle = INVALID_HANDLE;
   }
}

bool GetTickPrices(const string sym, double &bid, double &ask)
{
   MqlTick tick;
   if(SymbolInfoTick(sym, tick))
   {
      bid = tick.bid;
      ask = tick.ask;
      return (bid > 0.0 && ask > 0.0);
   }
   bid = SymbolInfoDouble(sym, SYMBOL_BID);
   ask = SymbolInfoDouble(sym, SYMBOL_ASK);
   return (bid > 0.0 && ask > 0.0);
}

int CurrentServerHour()
{
   MqlDateTime tm;
   TimeToStruct(TimeTradeServer(), tm);
   return tm.hour;
}

bool IsTradingWindow()
{
   int h = CurrentServerHour();
   return (h >= InpServerStartHour && h < InpServerEndHour);
}

bool IsCooldownActive()
{
   return (g_cooldownUntil > TimeTradeServer());
}

void ResetBasketState()
{
   g_basket.active       = false;
   g_basket.symbol       = "";
   g_basket.symbolIndex  = -1;
   g_basket.direction    = -1;
   g_basket.levels       = 0;
   g_basket.lastAddPrice = 0.0;
   g_basket.anchorSL     = 0.0;
   g_basket.baseLots     = 0.0;
   g_basket.trailActive  = false;
   g_basket.trailPeakPnl = 0.0;
   g_basket.startTime    = 0;
   g_basket.closeReason  = "-";
}

string FormatPrice(const string sym, const double v)
{
   int digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   return DoubleToString(v, digits);
}

string FormatPips(double v)
{
   return DoubleToString(v, 1);
}

string FormatMoney(double v)
{
   return DoubleToString(v, 2);
}

double NormalizePrice(const string sym, const double price)
{
   int digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   return NormalizeDouble(price, digits);
}

double NormalizeLots(const string sym, double lots)
{
   double minLot  = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
   double stepLot = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
   if(stepLot <= 0.0)
      stepLot = minLot;
   if(lots < minLot)
      lots = minLot;
   if(lots > maxLot)
      lots = maxLot;
   lots = MathFloor(lots / stepLot + 0.0000001) * stepLot;
   return NormalizeDouble(lots, 2);
}

double CalculateLot(const string sym, double entryPrice, double stopPrice)
{
   if(!InpUseSLBasedLot)
      return NormalizeLots(sym, InpFallbackLot);

   double riskPct = GetRiskPercent();
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney = balance * (riskPct / 100.0);
   double tickSize  = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
   double stopDistance = MathAbs(entryPrice - stopPrice);

   if(stopDistance <= 0.0 || tickSize <= 0.0 || tickValue <= 0.0)
      return NormalizeLots(sym, InpFallbackLot);

   double costPerLot = (stopDistance / tickSize) * tickValue;
   if(costPerLot <= 0.0)
      return NormalizeLots(sym, InpFallbackLot);

   return NormalizeLots(sym, riskMoney / costPerLot);
}

double GetInitialEntryLots(const int idx, const ENUM_ORDER_TYPE orderType, const double entryPrice)
{
   double stopRef = 0.0;
   if(orderType == ORDER_TYPE_BUY_STOP)
      stopRef = g_states[idx].dailyLow;
   else if(orderType == ORDER_TYPE_SELL_STOP)
      stopRef = g_states[idx].dailyHigh;

   if(InpUseSLBasedLot && stopRef > 0.0 && entryPrice > 0.0)
      return NormalizeLots(g_states[idx].symbol, CalculateLot(g_states[idx].symbol, entryPrice, stopRef));

   return NormalizeLots(g_states[idx].symbol, InpLots);
}

void CalcHighestLowestOpen(const string sym, ENUM_TIMEFRAMES period, double &ho, double &lo)
{
   ho = 0.0;
   lo = 0.0;

   datetime dayStart = iTime(sym, PERIOD_D1, 0);
   if(dayStart <= 0)
      return;

   int barsToday = iBarShift(sym, period, dayStart, true);
   if(barsToday < 0)
      barsToday = 0;

   int iHO = iHighest(sym, period, MODE_OPEN, barsToday + 1, 0);
   int iLO = iLowest(sym, period, MODE_OPEN, barsToday + 1, 0);
   if(iHO < 0 || iLO < 0)
      return;

   ho = iOpen(sym, period, iHO);
   lo = iOpen(sym, period, iLO);
}

void RefreshSymbolState(const int idx)
{
   string sym = g_states[idx].symbol;
   g_states[idx].dailyHigh     = iHigh(sym, PERIOD_D1, 0);
   g_states[idx].dailyLow      = iLow(sym, PERIOD_D1, 0);
   g_states[idx].yesterdayHigh = iHigh(sym, PERIOD_D1, 1);
   g_states[idx].yesterdayLow  = iLow(sym, PERIOD_D1, 1);
   CalcHighestLowestOpen(sym, PERIOD_H1, g_states[idx].hoH1, g_states[idx].loH1);

   g_states[idx].rangeAtrPct = 0.0;
   if(g_states[idx].atrHandle != INVALID_HANDLE)
   {
      double atrBuf[];
      ArraySetAsSeries(atrBuf, true);
      if(CopyBuffer(g_states[idx].atrHandle, 0, 1, 1, atrBuf) == 1)
      {
         double atr = atrBuf[0];
         double dailyRange = g_states[idx].dailyHigh - g_states[idx].dailyLow;
         if(atr > 0.0)
            g_states[idx].rangeAtrPct = (dailyRange / atr) * 100.0;
      }
   }
}

void RefreshAllSymbolStates()
{
   for(int i = 0; i < ArraySize(g_states); i++)
      RefreshSymbolState(i);
}

double CurrentM15Open(const string sym)
{
   int shift = (InpUseClosedM15Open ? 1 : 0);
   return iOpen(sym, PERIOD_M15, shift);
}

bool EvaluateSignalContext(const int idx, SignalContext &ctx)
{
   ZeroMemory(ctx);
   string sym = g_states[idx].symbol;
   if(!GetTickPrices(sym, ctx.bid, ctx.ask))
      return false;

   g_states[idx].bid = ctx.bid;
   g_states[idx].ask = ctx.ask;
   ctx.spreadPips = (ctx.ask - ctx.bid) / g_states[idx].pip;
   ctx.m15Open    = CurrentM15Open(sym);
   ctx.levelsValid = (g_states[idx].dailyHigh > g_states[idx].dailyLow &&
                      g_states[idx].hoH1 > 0.0 && g_states[idx].loH1 > 0.0 &&
                      g_states[idx].dailyHigh > g_states[idx].hoH1 && g_states[idx].loH1 > g_states[idx].dailyLow);
   ctx.sellZoneValid = (g_states[idx].dailyHigh > g_states[idx].hoH1 && g_states[idx].hoH1 > 0.0);
   ctx.buyZoneValid  = (g_states[idx].loH1 > g_states[idx].dailyLow && g_states[idx].loH1 > 0.0);
   ctx.inSellZone = ctx.sellZoneValid &&
                    (ctx.bid >= (g_states[idx].hoH1 - InpSignalTolerancePips * g_states[idx].pip)) &&
                    (ctx.bid <= (g_states[idx].dailyHigh + InpSignalTolerancePips * g_states[idx].pip));
   ctx.inBuyZone  = ctx.buyZoneValid &&
                    (ctx.ask <= (g_states[idx].loH1 + InpSignalTolerancePips * g_states[idx].pip)) &&
                    (ctx.ask >= (g_states[idx].dailyLow - InpSignalTolerancePips * g_states[idx].pip));
   ctx.atrOk      = (g_states[idx].rangeAtrPct >= InpMinRangeAtrPct);
   ctx.sellM15Ok  = (ctx.m15Open > 0.0 && g_states[idx].hoH1 > 0.0 && ctx.m15Open > g_states[idx].hoH1);
   ctx.buyM15Ok   = (ctx.m15Open > 0.0 && g_states[idx].loH1 > 0.0 && ctx.m15Open < g_states[idx].loH1);
   ctx.yesterdayHighBroken = (g_states[idx].yesterdayHigh > 0.0 && ctx.bid > g_states[idx].yesterdayHigh + InpSignalTolerancePips * g_states[idx].pip);
   ctx.yesterdayLowBroken  = (g_states[idx].yesterdayLow  > 0.0 && ctx.ask < g_states[idx].yesterdayLow  - InpSignalTolerancePips * g_states[idx].pip);
   ctx.dailyExtremeSellBroken = (g_states[idx].dailyHigh > 0.0 && iHigh(sym, PERIOD_H1, 0) >= g_states[idx].dailyHigh + InpSignalTolerancePips * g_states[idx].pip);
   ctx.dailyExtremeBuyBroken  = (g_states[idx].dailyLow  > 0.0 && iLow(sym, PERIOD_H1, 0) <= g_states[idx].dailyLow  - InpSignalTolerancePips * g_states[idx].pip);

   double sellStopDistPips = (g_states[idx].dailyHigh - (g_states[idx].hoH1 + InpEntryBufferPoints * g_states[idx].point)) / g_states[idx].pip;
   double buyStopDistPips  = ((g_states[idx].loH1 - InpEntryBufferPoints * g_states[idx].point) - g_states[idx].dailyLow) / g_states[idx].pip;
   ctx.sellStopDistanceOk = (sellStopDistPips >= InpMinStopDistancePips);
   ctx.buyStopDistanceOk  = (buyStopDistPips  >= InpMinStopDistancePips);

   ctx.sellReason = "OK";
   ctx.buyReason  = "OK";

   if(!ctx.levelsValid)
   {
      ctx.sellReason = "invalid levels";
      ctx.buyReason  = "invalid levels";
   }
   else
   {
      if(InpRequirePriceInZone && !ctx.inSellZone)
         ctx.sellReason = "not in sell zone";
      else if(!ctx.atrOk)
         ctx.sellReason = "rangeATR low";
      else if(!ctx.sellM15Ok)
         ctx.sellReason = "M15<=HO";
      else if(InpRejectIfYesterdayBroken && ctx.yesterdayHighBroken)
         ctx.sellReason = "above yHigh";
      else if(InpRejectIfDailyExtremeBroken && ctx.dailyExtremeSellBroken)
         ctx.sellReason = "dHigh broken";
      else if(!ctx.sellStopDistanceOk)
         ctx.sellReason = "SL too small";

      if(InpRequirePriceInZone && !ctx.inBuyZone)
         ctx.buyReason = "not in buy zone";
      else if(!ctx.atrOk)
         ctx.buyReason = "rangeATR low";
      else if(!ctx.buyM15Ok)
         ctx.buyReason = "M15>=LO";
      else if(InpRejectIfYesterdayBroken && ctx.yesterdayLowBroken)
         ctx.buyReason = "below yLow";
      else if(InpRejectIfDailyExtremeBroken && ctx.dailyExtremeBuyBroken)
         ctx.buyReason = "dLow broken";
      else if(!ctx.buyStopDistanceOk)
         ctx.buyReason = "SL too small";
   }

   ctx.sellSignal = (ctx.sellReason == "OK");
   ctx.buySignal  = (ctx.buyReason == "OK");

   g_states[idx].spreadPips = ctx.spreadPips;
   g_states[idx].m15Open    = ctx.m15Open;
   g_states[idx].sellM15Ok  = ctx.sellM15Ok;
   g_states[idx].buyM15Ok   = ctx.buyM15Ok;
   g_states[idx].sellSignal = ctx.sellSignal;
   g_states[idx].buySignal  = ctx.buySignal;
   g_states[idx].sellReason = ctx.sellReason;
   g_states[idx].buyReason  = ctx.buyReason;
   return true;
}

ulong FindPendingOrder(const string sym, ENUM_ORDER_TYPE type)
{
   for(int i = OrdersTotal() - 1; i >= 0; --i)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket))
         continue;
      if(OrderGetString(ORDER_SYMBOL) != sym)
         continue;
      if((ulong)OrderGetInteger(ORDER_MAGIC) != InpMagic)
         continue;
      if((ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE) != type)
         continue;
      return ticket;
   }
   return 0;
}

int PendingCount(const string sym = "")
{
   int count = 0;
   for(int i = OrdersTotal() - 1; i >= 0; --i)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket))
         continue;
      if((ulong)OrderGetInteger(ORDER_MAGIC) != InpMagic)
         continue;
      if(sym != "" && OrderGetString(ORDER_SYMBOL) != sym)
         continue;
      count++;
   }
   return count;
}

bool HasOpenPosition(const string sym = "", int posType = -1)
{
   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;
      if(sym != "" && PositionGetString(POSITION_SYMBOL) != sym)
         continue;
      if(posType >= 0 && (int)PositionGetInteger(POSITION_TYPE) != posType)
         continue;
      return true;
   }
   return false;
}

void CancelPendingByType(const string sym, ENUM_ORDER_TYPE type)
{
   ulong ticket = FindPendingOrder(sym, type);
   if(ticket > 0)
   {
      if(!trade.OrderDelete(ticket))
         LogMsg(LOG_ERROR, StringFormat("failed deleting pending %s ticket=%I64u ret=%d", sym, ticket, trade.ResultRetcode()));
   }
}

void CancelPendingsForSymbol(const string sym)
{
   CancelPendingByType(sym, ORDER_TYPE_BUY_STOP);
   CancelPendingByType(sym, ORDER_TYPE_SELL_STOP);
}

void CancelAllPendings()
{
   for(int i = OrdersTotal() - 1; i >= 0; --i)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket))
         continue;
      if((ulong)OrderGetInteger(ORDER_MAGIC) != InpMagic)
         continue;
      trade.OrderDelete(ticket);
   }
}

bool EnsurePendingOrder(const string sym, ENUM_ORDER_TYPE type, double entry, double sl, double lots, const string comment)
{
   entry = NormalizePrice(sym, entry);
   sl    = (sl > 0.0 ? NormalizePrice(sym, sl) : 0.0);
   lots  = NormalizeLots(sym, lots);
   if(entry <= 0.0 || lots <= 0.0)
      return false;

   double point = SymbolInfoDouble(sym, SYMBOL_POINT);
   double stopLevelPts = (double)SymbolInfoInteger(sym, SYMBOL_TRADE_STOPS_LEVEL) * point;
   double bid = 0.0, ask = 0.0;
   if(!GetTickPrices(sym, bid, ask))
      return false;

   if(type == ORDER_TYPE_BUY_STOP && entry < ask + stopLevelPts)
      return false;
   if(type == ORDER_TYPE_SELL_STOP && entry > bid - stopLevelPts)
      return false;

   ulong existing = FindPendingOrder(sym, type);
   if(existing > 0 && OrderSelect(existing))
   {
      double oldEntry = OrderGetDouble(ORDER_PRICE_OPEN);
      double oldSl    = OrderGetDouble(ORDER_SL);
      double oldLots  = OrderGetDouble(ORDER_VOLUME_INITIAL);
      if(MathAbs(oldEntry - entry) <= (point * 2.0) && MathAbs(oldSl - sl) <= (point * 2.0) && MathAbs(oldLots - lots) < 0.000001)
         return true;

      if(InpReplacePendingOnChange)
         return trade.OrderModify(existing, entry, sl, 0.0, ORDER_TIME_GTC, 0, 0.0);
      return true;
   }

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(10);

   if(type == ORDER_TYPE_BUY_STOP)
      return trade.BuyStop(lots, entry, sym, sl, 0.0, ORDER_TIME_GTC, 0, comment);
   return trade.SellStop(lots, entry, sym, sl, 0.0, ORDER_TIME_GTC, 0, comment);
}

double BasketNetProfit()
{
   double pnl = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;
      pnl += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
   }
   return pnl;
}

int BasketPositionCount(const string sym = "")
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;
      if(sym != "" && PositionGetString(POSITION_SYMBOL) != sym)
         continue;
      count++;
   }
   return count;
}

double GridTargetMoney()
{
   if(InpGridProfitPctBalance <= 0.0)
      return 0.0;
   return AccountInfoDouble(ACCOUNT_BALANCE) * 0.01 * InpGridProfitPctBalance;
}

double GridTrailArmMoney()
{
   double target = GridTargetMoney();
   if(target <= 0.0)
      return 0.0;
   return target * InpGridTrailArmPctTarget / 100.0;
}

void StartCooldown(const string reasonTag)
{
   g_cooldownUntil = TimeTradeServer() + InpCooldownMinutesAfterSL * 60;
   g_lastSLReason  = reasonTag;
}

bool CloseBasket(const string reason, const bool startCooldownAfterClose = false)
{
   bool allOk = true;
   CancelAllPendings();

   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;
      if(!trade.PositionClose(ticket))
         allOk = false;
   }

   if(allOk)
   {
      g_basket.closeReason = reason;
      if(startCooldownAfterClose)
         StartCooldown(reason);
      ResetBasketState();
   }
   return allOk;
}

void SyncBasketState()
{
   if(!HasOpenPosition())
   {
      if(g_basket.active)
         ResetBasketState();
      return;
   }

   if(g_basket.active)
      return;

   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;

      string sym = PositionGetString(POSITION_SYMBOL);
      int idx = GetStateIndexBySymbol(sym);
      g_basket.active       = true;
      g_basket.symbol       = sym;
      g_basket.symbolIndex  = idx;
      g_basket.direction    = (int)PositionGetInteger(POSITION_TYPE);
      g_basket.levels       = MathMax(1, BasketPositionCount(sym));
      g_basket.lastAddPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      if(idx >= 0)
         g_basket.anchorSL = (g_basket.direction == POSITION_TYPE_BUY ? g_states[idx].dailyLow : g_states[idx].dailyHigh);
      g_basket.baseLots     = NormalizeLots(sym, PositionGetDouble(POSITION_VOLUME));
      g_basket.startTime    = (datetime)PositionGetInteger(POSITION_TIME);
      g_basket.closeReason  = "sync";
      break;
   }
}

double NextGridLots()
{
   if(!g_basket.active || g_basket.symbol == "")
      return 0.0;
   int exponent = MathMax(0, g_basket.levels);
   double baseLots = g_basket.baseLots;
   if(baseLots <= 0.0)
      baseLots = NormalizeLots(g_basket.symbol, InpLots);
   return NormalizeLots(g_basket.symbol, baseLots * MathPow(InpGridLotMultiplier, exponent));
}

bool OpenGridLevel()
{
   if(!g_basket.active || g_basket.symbol == "")
      return false;
   if(g_basket.levels >= InpGridMaxLevels)
      return false;

   double bid = 0.0, ask = 0.0;
   if(!GetTickPrices(g_basket.symbol, bid, ask))
      return false;

   double lots = NextGridLots();
   if(lots <= 0.0)
      return false;

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(10);

   bool ok = false;
   if(g_basket.direction == POSITION_TYPE_BUY)
      ok = trade.Buy(lots, g_basket.symbol, ask, 0.0, 0.0, StringFormat("HOLO Grid L%d", g_basket.levels + 1));
   else if(g_basket.direction == POSITION_TYPE_SELL)
      ok = trade.Sell(lots, g_basket.symbol, bid, 0.0, 0.0, StringFormat("HOLO Grid L%d", g_basket.levels + 1));

   if(ok)
   {
      g_basket.levels++;
      g_basket.lastAddPrice = (g_basket.direction == POSITION_TYPE_BUY ? bid : ask);
   }
   return ok;
}

void ManageGridBasket()
{
   if(!InpUseGridBasket)
      return;

   SyncBasketState();
   if(!g_basket.active || !HasOpenPosition(g_basket.symbol))
      return;

   int idx = g_basket.symbolIndex;
   if(idx < 0)
      idx = GetStateIndexBySymbol(g_basket.symbol);
   if(idx < 0)
      return;

   double bid = 0.0, ask = 0.0;
   if(!GetTickPrices(g_basket.symbol, bid, ask))
      return;

   double pnl = BasketNetProfit();
   double targetMoney = GridTargetMoney();
   double trailArm = GridTrailArmMoney();

   if(InpGridUseAnchorHardStop && g_basket.anchorSL > 0.0)
   {
      if(g_basket.direction == POSITION_TYPE_BUY && bid <= g_basket.anchorSL)
      {
         CloseBasket("grid stop @ daily low", true);
         return;
      }
      if(g_basket.direction == POSITION_TYPE_SELL && ask >= g_basket.anchorSL)
      {
         CloseBasket("grid stop @ daily high", true);
         return;
      }
   }

   if(InpGridUseBasketTrail && trailArm > 0.0)
   {
      if(!g_basket.trailActive && pnl >= trailArm)
      {
         g_basket.trailActive = true;
         g_basket.trailPeakPnl = pnl;
      }
      if(g_basket.trailActive)
      {
         if(pnl > g_basket.trailPeakPnl)
            g_basket.trailPeakPnl = pnl;

         double retraceMoney = g_basket.trailPeakPnl * InpGridTrailRetracePctPeak / 100.0;
         double floorPnl = MathMax(0.0, g_basket.trailPeakPnl - retraceMoney);
         if(g_basket.trailPeakPnl > 0.0 && pnl <= floorPnl)
         {
            CloseBasket("basket trail close", false);
            return;
         }
      }
   }
   else if(targetMoney > 0.0 && pnl >= targetMoney)
   {
      CloseBasket("basket TP", false);
      return;
   }

   if(!IsTradingWindow())
      return;
   if(g_basket.levels >= InpGridMaxLevels)
      return;

   double pip = g_states[idx].pip;
   double adversePips = 0.0;
   if(g_basket.direction == POSITION_TYPE_BUY)
      adversePips = (g_basket.lastAddPrice - bid) / pip;
   else if(g_basket.direction == POSITION_TYPE_SELL)
      adversePips = (ask - g_basket.lastAddPrice) / pip;

   if(adversePips >= InpGridGapPips)
      OpenGridLevel();
}

void ManageStops()
{
   if(InpUseGridBasket)
      return;
   if(!HasOpenPosition())
      return;

   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;

      string sym = PositionGetString(POSITION_SYMBOL);
      int idx = GetStateIndexBySymbol(sym);
      if(idx < 0)
         continue;

      double bid = 0.0, ask = 0.0;
      if(!GetTickPrices(sym, bid, ask))
         continue;

      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl        = PositionGetDouble(POSITION_SL);
      double tp        = PositionGetDouble(POSITION_TP);
      double curPrice  = (type == POSITION_TYPE_BUY ? bid : ask);
      double profitPips = (type == POSITION_TYPE_BUY ? (curPrice - openPrice) : (openPrice - curPrice)) / g_states[idx].pip;
      double newSl = sl;

      if(InpUseBreakEven && profitPips >= InpBE_Trigger_Pips)
      {
         double bePrice = (type == POSITION_TYPE_BUY ? openPrice + InpBE_Lock_Pips * g_states[idx].pip
                                                     : openPrice - InpBE_Lock_Pips * g_states[idx].pip);
         if(type == POSITION_TYPE_BUY)
         {
            if(sl == 0.0 || bePrice > sl + (g_states[idx].point * 2.0))
               newSl = bePrice;
         }
         else
         {
            if(sl == 0.0 || bePrice < sl - (g_states[idx].point * 2.0))
               newSl = bePrice;
         }
      }

      if(InpUseTrailing && profitPips >= InpTrailStart_Pips)
      {
         double trailSl = (type == POSITION_TYPE_BUY ? curPrice - InpTrailDistance_Pips * g_states[idx].pip
                                                     : curPrice + InpTrailDistance_Pips * g_states[idx].pip);
         if(type == POSITION_TYPE_BUY)
         {
            if(newSl == 0.0 || trailSl > newSl + InpTrailStep_Pips * g_states[idx].pip)
               newSl = trailSl;
         }
         else
         {
            if(newSl == 0.0 || trailSl < newSl - InpTrailStep_Pips * g_states[idx].pip)
               newSl = trailSl;
         }
      }

      newSl = NormalizePrice(sym, newSl);
      if(newSl > 0.0)
      {
         bool shouldModify = false;
         if(type == POSITION_TYPE_BUY && (sl == 0.0 || newSl > sl + (g_states[idx].point * 2.0)) && newSl < bid)
            shouldModify = true;
         if(type == POSITION_TYPE_SELL && (sl == 0.0 || newSl < sl - (g_states[idx].point * 2.0)) && newSl > ask)
            shouldModify = true;
         if(shouldModify)
            trade.PositionModify(sym, newSl, tp);
      }
   }
}

void ManageEntries()
{
   if(!InpEnableEA)
      return;

   if(!IsTradingWindow())
   {
      CancelAllPendings();
      return;
   }

   if(IsCooldownActive())
   {
      CancelAllPendings();
      return;
   }

   SyncBasketState();
   if(HasOpenPosition())
   {
      if(InpCancelOppositeOnFill)
         CancelAllPendings();
      return;
   }

   for(int i = 0; i < ArraySize(g_states); i++)
   {
      SignalContext ctx;
      if(!EvaluateSignalContext(i, ctx))
         continue;

      string sym = g_states[i].symbol;
      if(ctx.spreadPips > InpMaxSpreadPips)
      {
         CancelPendingsForSymbol(sym);
         continue;
      }

      bool sellOk = ctx.sellSignal;
      bool buyOk  = ctx.buySignal;
      if(!sellOk)
         CancelPendingByType(sym, ORDER_TYPE_SELL_STOP);
      if(!buyOk)
         CancelPendingByType(sym, ORDER_TYPE_BUY_STOP);

      double sellEntry = g_states[i].hoH1 + InpEntryBufferPoints * g_states[i].point;
      double buyEntry  = g_states[i].loH1 - InpEntryBufferPoints * g_states[i].point;
      double pendingSellSL = (InpUseGridBasket ? 0.0 : g_states[i].dailyHigh);
      double pendingBuySL  = (InpUseGridBasket ? 0.0 : g_states[i].dailyLow);
      double sellLots = GetInitialEntryLots(i, ORDER_TYPE_SELL_STOP, sellEntry);
      double buyLots  = GetInitialEntryLots(i, ORDER_TYPE_BUY_STOP, buyEntry);

      if(sellOk)
         EnsurePendingOrder(sym, ORDER_TYPE_SELL_STOP, sellEntry, pendingSellSL, sellLots, "HOLO SellStop");
      if(buyOk)
         EnsurePendingOrder(sym, ORDER_TYPE_BUY_STOP, buyEntry, pendingBuySL, buyLots, "HOLO BuyStop");
   }
}

void UpdateCooldownFromHistoryIfNeeded()
{
   static datetime lastScan = 0;
   datetime now = TimeTradeServer();
   if(now == lastScan)
      return;
   lastScan = now;

   datetime from = now - 7 * 24 * 3600;
   if(!HistorySelect(from, now))
      return;

   int total = HistoryDealsTotal();
   for(int i = total - 1; i >= 0; --i)
   {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0)
         continue;
      if((ulong)HistoryDealGetInteger(deal, DEAL_MAGIC) != InpMagic)
         continue;
      if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal, DEAL_ENTRY) != DEAL_ENTRY_OUT)
         continue;

      datetime dealTime = (datetime)HistoryDealGetInteger(deal, DEAL_TIME);
      ENUM_DEAL_REASON reason = (ENUM_DEAL_REASON)HistoryDealGetInteger(deal, DEAL_REASON);
      if(reason == DEAL_REASON_SL)
      {
         datetime candidate = dealTime + InpCooldownMinutesAfterSL * 60;
         if(candidate > g_cooldownUntil)
         {
            g_cooldownUntil = candidate;
            g_lastSLReason = "SL @ " + TimeToString(dealTime, TIME_DATE|TIME_MINUTES);
         }
      }
      break;
   }
}

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
      return;
   if(!HistoryDealSelect(trans.deal))
      return;
   if((ulong)HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != InpMagic)
      return;

   ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   if(entry == DEAL_ENTRY_OUT)
   {
      ENUM_DEAL_REASON reason = (ENUM_DEAL_REASON)HistoryDealGetInteger(trans.deal, DEAL_REASON);
      if(reason == DEAL_REASON_SL)
      {
         datetime dealTime = (datetime)HistoryDealGetInteger(trans.deal, DEAL_TIME);
         StartCooldown("SL @ " + TimeToString(dealTime, TIME_DATE|TIME_MINUTES));
      }
      if(!HasOpenPosition())
         ResetBasketState();
   }
   else if(entry == DEAL_ENTRY_IN)
   {
      string sym = HistoryDealGetString(trans.deal, DEAL_SYMBOL);
      int dealType = (int)HistoryDealGetInteger(trans.deal, DEAL_TYPE);
      double dealPrice = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
      double dealVolume = HistoryDealGetDouble(trans.deal, DEAL_VOLUME);

      if(!g_basket.active)
      {
         int idx = GetStateIndexBySymbol(sym);
         g_basket.active       = true;
         g_basket.symbol       = sym;
         g_basket.symbolIndex  = idx;
         g_basket.direction    = (dealType == DEAL_TYPE_BUY ? POSITION_TYPE_BUY : POSITION_TYPE_SELL);
         g_basket.levels       = 1;
         g_basket.lastAddPrice = dealPrice;
         if(idx >= 0)
            g_basket.anchorSL  = (g_basket.direction == POSITION_TYPE_BUY ? g_states[idx].dailyLow : g_states[idx].dailyHigh);
         g_basket.baseLots     = NormalizeLots(sym, dealVolume);
         g_basket.startTime    = (datetime)HistoryDealGetInteger(trans.deal, DEAL_TIME);
         g_basket.closeReason  = "entry";
      }
   }

   if(InpCancelOppositeOnFill && HasOpenPosition())
      CancelAllPendings();
}

void DeleteObjectsByPrefix(const string prefix)
{
   for(int i = ObjectsTotal(0, 0, -1) - 1; i >= 0; --i)
   {
      string name = ObjectName(0, i, 0, -1);
      if(StringFind(name, prefix) == 0)
         ObjectDelete(0, name);
   }
}

void StyleChart()
{
   if(!InpStyleChart)
      return;

   long chart = ChartID();
   ChartSetInteger(chart, CHART_COLOR_BACKGROUND, tmdBg);
   ChartSetInteger(chart, CHART_COLOR_FOREGROUND, tmdSilver);
   ChartSetInteger(chart, CHART_COLOR_GRID, tmdSubtleBg);
   ChartSetInteger(chart, CHART_COLOR_CANDLE_BULL, tmdGreen);
   ChartSetInteger(chart, CHART_COLOR_CANDLE_BEAR, tmdRed);
   ChartSetInteger(chart, CHART_COLOR_CHART_UP, tmdGreen);
   ChartSetInteger(chart, CHART_COLOR_CHART_DOWN, tmdRed);
   ChartSetInteger(chart, CHART_COLOR_STOP_LEVEL, tmdOrange);
   ChartSetInteger(chart, CHART_COLOR_BID, tmdBid);
   ChartSetInteger(chart, CHART_COLOR_ASK, tmdAsk);
   ChartSetInteger(chart, CHART_SHOW_GRID, false);
   ChartSetInteger(chart, CHART_SHOW_VOLUMES, false);
   ChartSetInteger(chart, CHART_SHOW_PERIOD_SEP, false);
   ChartSetInteger(chart, CHART_SHOW_OBJECT_DESCR, false);
   ChartSetInteger(chart, CHART_SHOW_OHLC, true);
   ChartSetInteger(chart, CHART_SHOW_ASK_LINE, true);
   ChartSetInteger(chart, CHART_SHOW_BID_LINE, true);
   ChartSetInteger(chart, CHART_MODE, CHART_CANDLES);
   ChartSetInteger(chart, CHART_SCALE, 3);
   ChartSetInteger(chart, CHART_AUTOSCROLL, true);
   ChartSetInteger(chart, CHART_SHIFT, true);
}

void PanelRemember(const string name)
{
   int n = ArraySize(g_panelObjs);
   ArrayResize(g_panelObjs, n + 1);
   g_panelObjs[n] = name;
}

void PanelDeleteAll()
{
   for(int i = 0; i < ArraySize(g_panelObjs); i++)
      ObjectDelete(0, g_panelObjs[i]);
   ArrayResize(g_panelObjs, 0);
}

void CreatePanelRect(const string key, int x, int y, int w, int h, color border, color fill)
{
   string name = PREFIX + "P_" + key;
   ObjectDelete(0, name);
   if(ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0))
   {
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
      ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
      ObjectSetInteger(0, name, OBJPROP_BGCOLOR, fill);
      ObjectSetInteger(0, name, OBJPROP_COLOR, border);
      ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      PanelRemember(name);
   }
}

void CreatePanelLabel(const string key, int x, int y, int fs, color clr, const string text, ENUM_ANCHOR_POINT anchor = ANCHOR_LEFT_UPPER)
{
   string name = PREFIX + "P_" + key;
   ObjectDelete(0, name);
   if(ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0))
   {
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fs);
      ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
      ObjectSetString(0, name, OBJPROP_TEXT, text);
      ObjectSetInteger(0, name, OBJPROP_ANCHOR, anchor);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      PanelRemember(name);
   }
}

void SetPanelText(const string key, const string text, color clr)
{
   string name = PREFIX + "P_" + key;
   if(ObjectFind(0, name) >= 0)
   {
      ObjectSetString(0, name, OBJPROP_TEXT, text);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   }
}

void CreatePanel()
{
   if(!InpShowPanel)
      return;

   PanelDeleteAll();

   int bgW = 940;
   int rows = MathMin(ArraySize(g_states), 18);
   int bgH = 220 + rows * 18;

   CreatePanelRect("BG", 20, 30, bgW, bgH, tmdBg, tmdBg);
   CreatePanelRect("TB", 23, 33, bgW - 6, 28, tmdBg, tmdBg);
   CreatePanelRect("S1", 30, 67, bgW - 40, 1, tmdSubtleBg, tmdBg);
   CreatePanelRect("S2", 30, 135, bgW - 40, 1, tmdSubtleBg, tmdBg);

   CreatePanelLabel("ONLINE_DOT", 30, 40, 10, tmdGreen, "●");
   CreatePanelLabel("ONLINE_TXT", 44, 40, 9, C'0,180,180', "ONLINE");
   CreatePanelLabel("SERVER", 110, 40, 9, tmdSilver, "--:--:--");
   CreatePanelLabel("TITLE", 480, 38, 11, C'0,230,230', "◆ HOLO EA MS ◆", ANCHOR_UPPER);

   CreatePanelLabel("G1L", 30, 76, 8, C'70,90,110', "BALANCE");
   CreatePanelLabel("G1V", 170, 76, 8, tmdSilver, "-", ANCHOR_RIGHT_UPPER);
   CreatePanelLabel("G2L", 30, 92, 8, C'70,90,110', "EQUITY");
   CreatePanelLabel("G2V", 170, 92, 8, tmdSilver, "-", ANCHOR_RIGHT_UPPER);
   CreatePanelLabel("G3L", 30, 108, 8, C'70,90,110', "P/L");
   CreatePanelLabel("G3V", 170, 108, 8, tmdSilver, "-", ANCHOR_RIGHT_UPPER);

   CreatePanelLabel("G4L", 220, 76, 8, C'70,90,110', "GRID STATE");
   CreatePanelLabel("G4V", 450, 76, 8, tmdSilver, "-", ANCHOR_RIGHT_UPPER);
   CreatePanelLabel("G5L", 220, 92, 8, C'70,90,110', "WINDOW / COOLDOWN");
   CreatePanelLabel("G5V", 450, 92, 8, tmdSilver, "-", ANCHOR_RIGHT_UPPER);
   CreatePanelLabel("G6L", 220, 108, 8, C'70,90,110', "PENDINGS / SYMBOLS");
   CreatePanelLabel("G6V", 450, 108, 8, tmdSilver, "-", ANCHOR_RIGHT_UPPER);

   CreatePanelLabel("G7L", 520, 76, 8, C'70,90,110', "RISK / LOT");
   CreatePanelLabel("G7V", 900, 76, 8, tmdSilver, "-", ANCHOR_RIGHT_UPPER);
   CreatePanelLabel("G8L", 520, 92, 8, C'70,90,110', "GRID CFG");
   CreatePanelLabel("G8V", 900, 92, 8, tmdSilver, "-", ANCHOR_RIGHT_UPPER);
   CreatePanelLabel("G9L", 520, 108, 8, C'70,90,110', "LAST SL");
   CreatePanelLabel("G9V", 900, 108, 8, tmdSilver, "-", ANCHOR_RIGHT_UPPER);

   CreatePanelLabel("SYMHDR", 30, 144, 9, C'180,40,220', "SYMBOLS");
   CreatePanelLabel("COL1", 120, 144, 8, C'70,90,110', "LEVELS");
   CreatePanelLabel("COL2", 235, 144, 8, C'70,90,110', "PEND");
   CreatePanelLabel("COL3", 305, 144, 8, C'70,90,110', "BUY");
   CreatePanelLabel("COL4", 385, 144, 8, C'70,90,110', "SELL");
   CreatePanelLabel("COL5", 470, 144, 8, C'70,90,110', "CD");
   CreatePanelLabel("COL6", 540, 144, 8, C'70,90,110', "M15");
   CreatePanelLabel("COL7", 615, 144, 8, C'70,90,110', "SPR");
   CreatePanelLabel("COL8", 685, 144, 8, C'70,90,110', "ATR%");
   CreatePanelLabel("COL9", 760, 144, 8, C'70,90,110', "STATE");
   CreatePanelLabel("COL10", 905, 144, 8, C'70,90,110', "ACTIVE", ANCHOR_RIGHT_UPPER);

   for(int i = 0; i < rows; i++)
   {
      int y = 164 + i * 18;
      CreatePanelLabel("R_SYM_" + IntegerToString(i), 30, y, 8, tmdSilver, "-");
      CreatePanelLabel("R_LVL_" + IntegerToString(i), 120, y, 8, tmdSilver, "-");
      CreatePanelLabel("R_PND_" + IntegerToString(i), 235, y, 8, tmdSilver, "-");
      CreatePanelLabel("R_BUY_" + IntegerToString(i), 305, y, 8, tmdSilver, "-");
      CreatePanelLabel("R_SEL_" + IntegerToString(i), 385, y, 8, tmdSilver, "-");
      CreatePanelLabel("R_CD_" + IntegerToString(i), 470, y, 8, tmdSilver, "-");
      CreatePanelLabel("R_M15_" + IntegerToString(i), 540, y, 8, tmdSilver, "-");
      CreatePanelLabel("R_SPR_" + IntegerToString(i), 615, y, 8, tmdSilver, "-");
      CreatePanelLabel("R_ATR_" + IntegerToString(i), 685, y, 8, tmdSilver, "-");
      CreatePanelLabel("R_STA_" + IntegerToString(i), 760, y, 8, tmdSilver, "-");
      CreatePanelLabel("R_ACT_" + IntegerToString(i), 905, y, 8, tmdSilver, "-", ANCHOR_RIGHT_UPPER);
   }
}

int GetVisualStateIndex()
{
   int idx = GetStateIndexBySymbol(_Symbol);
   if(idx >= 0)
      return idx;
   if(ArraySize(g_states) > 0)
      return 0;
   return -1;
}

void DrawRectangle(const string name, datetime t1, double p1, datetime t2, double p2, color clr)
{
   ObjectDelete(0, name);
   if(ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, p1, t2, p2))
   {
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
      ObjectSetInteger(0, name, OBJPROP_FILL, true);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   }
}

void DrawHLineSegment(const string name, double price, datetime t1, datetime t2, color clr, ENUM_LINE_STYLE style, int width, const string text)
{
   if(price <= 0.0)
      return;

   string lineName = PREFIX + name + "_line";
   ObjectDelete(0, lineName);
   if(ObjectCreate(0, lineName, OBJ_TREND, 0, t1, price, t2, price))
   {
      ObjectSetInteger(0, lineName, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, lineName, OBJPROP_STYLE, style);
      ObjectSetInteger(0, lineName, OBJPROP_WIDTH, width);
      ObjectSetInteger(0, lineName, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, lineName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, lineName, OBJPROP_HIDDEN, true);
   }

   string textName = PREFIX + name + "_text";
   ObjectDelete(0, textName);
   if(ObjectCreate(0, textName, OBJ_TEXT, 0, t2 + PeriodSeconds(_Period) * 3, price))
   {
      ObjectSetString(0, textName, OBJPROP_TEXT, text);
      ObjectSetInteger(0, textName, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, textName, OBJPROP_FONTSIZE, 9);
      ObjectSetString(0, textName, OBJPROP_FONT, "Arial Bold");
      ObjectSetInteger(0, textName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, textName, OBJPROP_HIDDEN, true);
   }
}

void DrawMarker(const string name, datetime t, double price, color clr, const string text)
{
   string vName = PREFIX + name + "_v";
   ObjectDelete(0, vName);
   if(ObjectCreate(0, vName, OBJ_VLINE, 0, t, 0))
   {
      ObjectSetInteger(0, vName, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, vName, OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, vName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, vName, OBJPROP_HIDDEN, true);
   }

   string txt = PREFIX + name + "_t";
   ObjectDelete(0, txt);
   if(ObjectCreate(0, txt, OBJ_TEXT, 0, t, price))
   {
      ObjectSetString(0, txt, OBJPROP_TEXT, text);
      ObjectSetInteger(0, txt, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, txt, OBJPROP_FONTSIZE, 8);
      ObjectSetString(0, txt, OBJPROP_FONT, "Arial Bold");
      ObjectSetInteger(0, txt, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, txt, OBJPROP_HIDDEN, true);
   }
}

void DrawVisuals()
{
   int idx = GetVisualStateIndex();
   if(idx < 0)
      return;

   DeleteObjectsByPrefix(PREFIX + "L_");
   string sym = g_states[idx].symbol;
   datetime t1 = iTime(sym, PERIOD_D1, 0);
   datetime t2 = TimeCurrent();

   if(Show_H1_Lines)
   {
      DrawHLineSegment("L_H1_HO", g_states[idx].hoH1, t1, t2, Color_HO, STYLE_SOLID, LineWidth_HO_LO,
                       sym + " SELL @ " + FormatPrice(sym, g_states[idx].hoH1));
      DrawHLineSegment("L_H1_LO", g_states[idx].loH1, t1, t2, Color_LO, STYLE_SOLID, LineWidth_HO_LO,
                       sym + " BUY @ " + FormatPrice(sym, g_states[idx].loH1));
   }

   if(Show_Daily_Lines)
   {
      DrawHLineSegment("L_D_HIGH", g_states[idx].dailyHigh, t1, t2, Color_DailyHigh, STYLE_DOT, LineWidth_Daily,
                       "SL Sell (Daily High)");
      DrawHLineSegment("L_D_LOW", g_states[idx].dailyLow, t1, t2, Color_DailyLow, STYLE_DOT, LineWidth_Daily,
                       "SL Buy (Daily Low)");
   }

   if(Show_Yesterday_Lines)
   {
      DrawHLineSegment("L_Y_HIGH", g_states[idx].yesterdayHigh, t1, t2, Color_YesterdayHigh, STYLE_DOT, LineWidth_Daily,
                       "Yesterday High");
      DrawHLineSegment("L_Y_LOW", g_states[idx].yesterdayLow, t1, t2, Color_YesterdayLow, STYLE_DOT, LineWidth_Daily,
                       "Yesterday Low");
   }

   if(Show_DaySeparator)
   {
      string name = PREFIX + "L_DAYSEP";
      ObjectDelete(0, name);
      if(ObjectCreate(0, name, OBJ_VLINE, 0, t1, 0))
      {
         ObjectSetInteger(0, name, OBJPROP_COLOR, Color_DaySeparator);
         ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DASHDOT);
         ObjectSetInteger(0, name, OBJPROP_BACK, true);
         ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      }
   }

   if(Show_AreaOfInterest)
   {
      datetime tZone2 = t2 + PeriodSeconds(_Period) * 5;
      if(g_states[idx].dailyHigh > g_states[idx].hoH1 && g_states[idx].hoH1 > 0.0)
         DrawRectangle(PREFIX + "L_AOI_SELL", t1, g_states[idx].hoH1, tZone2, g_states[idx].dailyHigh, Color_AOI_Short);
      if(g_states[idx].loH1 > g_states[idx].dailyLow && g_states[idx].loH1 > 0.0)
         DrawRectangle(PREFIX + "L_AOI_BUY", t1, g_states[idx].dailyLow, tZone2, g_states[idx].loH1, Color_AOI_Long);
   }

   if(Show_PendingMarkers)
   {
      ulong buyOrd = FindPendingOrder(sym, ORDER_TYPE_BUY_STOP);
      ulong sellOrd = FindPendingOrder(sym, ORDER_TYPE_SELL_STOP);
      if(buyOrd > 0 && OrderSelect(buyOrd))
         DrawMarker("BUY_PENDING", (datetime)OrderGetInteger(ORDER_TIME_SETUP), OrderGetDouble(ORDER_PRICE_OPEN), Color_LO, sym + " BUY STOP");
      if(sellOrd > 0 && OrderSelect(sellOrd))
         DrawMarker("SELL_PENDING", (datetime)OrderGetInteger(ORDER_TIME_SETUP), OrderGetDouble(ORDER_PRICE_OPEN), Color_HO, sym + " SELL STOP");
   }
}

void UpdatePanel()
{
   if(!InpShowPanel)
      return;

   double bal   = AccountInfoDouble(ACCOUNT_BALANCE);
   double eq    = AccountInfoDouble(ACCOUNT_EQUITY);
   double pnl   = AccountInfoDouble(ACCOUNT_PROFIT);
   color pnlClr = (pnl > 0.0 ? tmdGreen : (pnl < 0.0 ? tmdRed : tmdSilver));

   SetPanelText("SERVER", FormatServerDateTime(TimeTradeServer()), tmdSilver);
   SetPanelText("ONLINE_DOT", "●", InpEnableEA ? tmdGreen : tmdRed);
   SetPanelText("ONLINE_TXT", InpEnableEA ? "ONLINE" : "OFFLINE", InpEnableEA ? C'0,180,180' : tmdRed);
   SetPanelText("G1V", FormatMoney(bal), tmdSilver);
   SetPanelText("G2V", FormatMoney(eq), tmdSilver);
   SetPanelText("G3V", FormatMoney(pnl), pnlClr);

   string gridState = "FLAT";
   color gridClr = tmdSilver;
   if(g_basket.active)
   {
      gridState = g_basket.symbol + " / " + (g_basket.direction == POSITION_TYPE_BUY ? "BUY" : "SELL") + StringFormat(" / L%d", g_basket.levels);
      gridClr = tmdOrange;
   }
   SetPanelText("G4V", FitPanelText(gridState, 32), gridClr);

   string cdTxt = (IsTradingWindow() ? "OPEN" : "CLOSED");
   if(IsCooldownActive())
      cdTxt += " / COOLDOWN";
   SetPanelText("G5V", cdTxt, IsCooldownActive() ? tmdOrange : (IsTradingWindow() ? tmdGreen : tmdRed));
   SetPanelText("G6V", IntegerToString(PendingCount()) + " / " + IntegerToString(ArraySize(g_states)), tmdSilver);

   string riskModeTxt = "MED";
   if(InpRiskMode == RISK_LOW) riskModeTxt = "LOW";
   if(InpRiskMode == RISK_HIGH) riskModeTxt = "HIGH";
   SetPanelText("G7V", StringFormat("%s / SL-%s / base %.2f", riskModeTxt, (InpUseSLBasedLot ? "ON" : "OFF"), InpLots), tmdSilver);
   SetPanelText("G8V", StringFormat("gap %dp / max %d / x%.2f", InpGridGapPips, InpGridMaxLevels, InpGridLotMultiplier), tmdSilver);
   SetPanelText("G9V", FitPanelText(g_lastSLReason, 45), tmdSilver);

   int rows = MathMin(ArraySize(g_states), 18);
   for(int i = 0; i < rows; i++)
   {
      SignalContext ctx;
      EvaluateSignalContext(i, ctx);
      string sym = g_states[i].symbol;
      string levels = FitPanelText(FormatPrice(sym, g_states[i].hoH1) + " / " + FormatPrice(sym, g_states[i].loH1), 14);
      string pnd = IntegerToString(PendingCount(sym));
      string buy = (g_states[i].buySignal ? "READY" : FitPanelText(g_states[i].buyReason, 9));
      string sell = (g_states[i].sellSignal ? "READY" : FitPanelText(g_states[i].sellReason, 9));
      string cd = (IsCooldownActive() ? "YES" : "-");
      string m15 = StringFormat("S:%s B:%s", (g_states[i].sellM15Ok ? "Y" : "N"), (g_states[i].buyM15Ok ? "Y" : "N"));
      string spr = FormatPips(g_states[i].spreadPips);
      string atr = DoubleToString(g_states[i].rangeAtrPct, 0);
      string state = "WAIT";
      color stateClr = tmdSilver;
      if(g_states[i].sellSignal) { state = "SELL"; stateClr = Color_HO; }
      else if(g_states[i].buySignal) { state = "BUY"; stateClr = Color_LO; }
      else if(g_states[i].spreadPips > InpMaxSpreadPips) { state = "SPREAD"; stateClr = tmdRed; }

      color activeClr = tmdSilver;
      string activeTxt = "-";
      if(g_basket.active && g_basket.symbol == sym)
      {
         activeTxt = "GRID";
         activeClr = tmdOrange;
      }
      else if(HasOpenPosition(sym))
      {
         activeTxt = "LIVE";
         activeClr = tmdGreen;
      }

      SetPanelText("R_SYM_" + IntegerToString(i), sym, activeClr == tmdSilver ? tmdSilver : activeClr);
      SetPanelText("R_LVL_" + IntegerToString(i), levels, tmdSilver);
      SetPanelText("R_PND_" + IntegerToString(i), pnd, PendingCount(sym) > 0 ? tmdOrange : tmdSilver);
      SetPanelText("R_BUY_" + IntegerToString(i), buy, g_states[i].buySignal ? Color_LO : tmdSilver);
      SetPanelText("R_SEL_" + IntegerToString(i), sell, g_states[i].sellSignal ? Color_HO : tmdSilver);
      SetPanelText("R_CD_" + IntegerToString(i), cd, IsCooldownActive() ? tmdOrange : tmdSilver);
      SetPanelText("R_M15_" + IntegerToString(i), m15, tmdSilver);
      SetPanelText("R_SPR_" + IntegerToString(i), spr, g_states[i].spreadPips > InpMaxSpreadPips ? tmdRed : tmdSilver);
      SetPanelText("R_ATR_" + IntegerToString(i), atr, g_states[i].rangeAtrPct >= InpMinRangeAtrPct ? tmdGreen : tmdSilver);
      SetPanelText("R_STA_" + IntegerToString(i), state, stateClr);
      SetPanelText("R_ACT_" + IntegerToString(i), activeTxt, activeClr);
   }
}

bool ShouldRefreshVisuals(const bool force = false)
{
   if(force)
   {
      g_lastVisualRefreshMs = GetTickCount();
      g_lastVisualBarTime   = iTime(_Symbol, _Period, 0);
      return true;
   }

   if(!MQLInfoInteger(MQL_TESTER) || !InpThrottleVisualsInTester)
      return true;

   datetime curBarTime = iTime(_Symbol, _Period, 0);
   ulong nowMs = GetTickCount();

   if(curBarTime != g_lastVisualBarTime)
   {
      g_lastVisualBarTime = curBarTime;
      g_lastVisualRefreshMs = nowMs;
      return true;
   }

   uint interval = (uint)MathMax(50, InpVisualRefreshMs);
   if(nowMs - g_lastVisualRefreshMs >= interval)
   {
      g_lastVisualRefreshMs = nowMs;
      return true;
   }
   return false;
}

void RefreshVisualLayer(const bool force = false)
{
   if(!ShouldRefreshVisuals(force))
      return;
   DrawVisuals();
   UpdatePanel();
   ChartRedraw(0);
}

int OnInit()
{
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(10);
   ResetBasketState();

   if(!ParseSymbols())
      return INIT_FAILED;

   StyleChart();
   CreatePanel();
   RefreshAllSymbolStates();
   UpdateCooldownFromHistoryIfNeeded();
   RefreshVisualLayer(true);
   EventSetTimer(1);
   LogMsg(LOG_INFO, "EA initialized symbols=" + IntegerToString(ArraySize(g_states)));
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   ReleaseSymbols();
   DeleteObjectsByPrefix(PREFIX + "L_");
   PanelDeleteAll();
}

void OnTimer()
{
   RefreshAllSymbolStates();
   UpdateCooldownFromHistoryIfNeeded();
   RefreshVisualLayer();
}

void OnTick()
{
   RefreshAllSymbolStates();
   UpdateCooldownFromHistoryIfNeeded();
   ManageEntries();
   ManageGridBasket();
   ManageStops();
   RefreshVisualLayer();
}
//+------------------------------------------------------------------+
