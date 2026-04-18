//+------------------------------------------------------------------+
//|                                                   Breakout_v1.mq5|
//|                                      Non-grid multi-symbol ready |
//+------------------------------------------------------------------+
#property strict
#property version   "1.00"

#include <Trade/Trade.mqh>

CTrade trade;

//+------------------------------------------------------------------+
//| Inputs                                                        |
//+------------------------------------------------------------------+
input group "=== General ===";
input ulong             InpMagicNumber         = 26040201;
input string            InpSymbols             = "GBPUSD";
input ENUM_TIMEFRAMES   InpScanTF              = PERIOD_H1;
input bool              InpEnableDebug         = true;

input group "=== Filters ===";
input int               InpMaxSpreadPoints     = 25;
input bool              InpUseSpreadFilter     = true;

input group "=== Risk ===";
input bool              InpUseFixedLot         = false;
input double            InpFixedLot            = 0.10;
input double            InpRiskPerTradePct     = 0.50;

input group "=== Pending Orders ===";
input int               InpPendingExpiryBars   = 3;
input bool              InpOnePositionPerSymbol = false;
input bool              InpOnePendingPerSymbol  = false;
input bool              InpKeepOppositePendingAfterFill = true;

input group "=== Strategy: H1 Structure Break ===";
input bool              InpUseH4TrendFilter     = true;
input int               InpSwingLeftBars        = 2;
input int               InpSwingRightBars       = 2;
input int               InpStructureLookbackBars = 50;
input double            InpBreakoutBufferPoints = 15;
input double            InpStopBufferPoints     = 10;
input double            InpTakeProfitRR         = 2.0;

input double            InpMinStructureSizePoints   = 80;
input double            InpMinStructureATRMultiple  = 0.80;
input double            InpMinStopDistancePoints    = 60;
input bool              InpUsePendingInvalidation   = true;

input bool              InpUseATRBreakoutBuffer      = true;
input double            InpATRBreakoutBufferMult     = 0.10;
input int               InpMaxSignalAgeBars          = 12;
input bool              InpUseCloseBasedInvalidation = true;
input double            InpInvalidationBufferPoints  = 5;

input group "=== Trade Management ===";
input bool              InpUseBreakEven          = true;
input double            InpBreakEvenAtR          = 1.0;
input double            InpBreakEvenOffsetPoints = 5;

input bool              InpUsePartialClose       = true;
input double            InpPartialCloseAtR       = 1.5;
input double            InpPartialClosePct       = 50.0;

input bool              InpUseATRTrail           = true;
input double            InpATRTrailStartR        = 1.5;
input int               InpATRPeriod             = 14;
input double            InpATRTrailMult          = 1.5;

input bool   InpRemoveTPOnTrailStart = true;

//+------------------------------------------------------------------+
//| Constants                                                        |
//+------------------------------------------------------------------+
#define MAX_TRACKED_SYMBOLS 32

//+------------------------------------------------------------------+
//| Enums                                                            |
//+------------------------------------------------------------------+
enum BreakoutDirection
{
   BREAKOUT_NONE = 0,
   BREAKOUT_BUY  = 1,
   BREAKOUT_SELL = -1
};

//+------------------------------------------------------------------+
//| Structs                                                          |
//+------------------------------------------------------------------+
struct SymbolState
{
   string            symbol;
   bool              enabled;

   datetime          lastScanBarTime;
   datetime          lastManageBarTime;

   double            point;
   int               digits;

   double            bid;
   double            ask;
   double            spreadPoints;

   bool              symbolSelected;
   bool              marketWatchReady;
   bool              tradable;
   bool              spreadOk;
   
   bool              lastCanProcess;
   datetime          lastMgmtBarTime;
};

struct SwingPoint
{
   bool      valid;
   int       shift;
   double    price;
};

struct BreakoutSignal
{
   bool      valid;
   string    symbol;
   int       direction;
   double    entry;
   double    stopLoss;
   double    takeProfit;
   double    volume;
   double    triggerLevel;
   double    oppositeLevel;
   double    structureHigh;
   double    structureLow;
   double    structureSize;
   double    atrValue;
   int       triggerShift;
   int       oppositeShift;
   string    comment;
};

struct PositionMgmtState
{
   bool      active;
   ulong     ticket;
   string    symbol;

   int       posType;

   double    initialVolume;
   double    initialOpenPrice;
   double    initialSL;
   double    initialTP;
   double    initialRiskDistance;

   bool      breakEvenDone;
   bool      partialCloseDone;
   bool      trailActivated;
};

//+------------------------------------------------------------------+
//| Globals                                                          |
//+------------------------------------------------------------------+
string            g_symbols[MAX_TRACKED_SYMBOLS];
SymbolState       g_states[MAX_TRACKED_SYMBOLS];
PositionMgmtState g_mgmt[MAX_TRACKED_SYMBOLS];
int               g_symbolsTotal = 0;

//+------------------------------------------------------------------+
//| Utility: trim string                                             |
//+------------------------------------------------------------------+
string TrimString(string text)
{
   StringTrimLeft(text);
   StringTrimRight(text);
   return text;
}
//+------------------------------------------------------------------+
//| Reset one management state                                       |
//+------------------------------------------------------------------+
void ResetMgmtState(PositionMgmtState &ms)
{
   ms.active              = false;
   ms.ticket              = 0;
   ms.symbol              = "";
   ms.posType             = -1;
   ms.initialVolume       = 0.0;
   ms.initialOpenPrice    = 0.0;
   ms.initialSL           = 0.0;
   ms.initialTP           = 0.0;
   ms.initialRiskDistance = 0.0;
   ms.breakEvenDone       = false;
   ms.partialCloseDone    = false;
   ms.trailActivated      = false;
}
//+------------------------------------------------------------------+
//| Utility: parse symbol list                                       |
//+------------------------------------------------------------------+
int ParseSymbols(const string symbolList, string &outSymbols[])
{
   for(int i = 0; i < MAX_TRACKED_SYMBOLS; i++)
      outSymbols[i] = "";

   string parts[];
   int count = StringSplit(symbolList, ',', parts);
   if(count <= 0)
      return 0;

   int validCount = 0;

   for(int i = 0; i < count && validCount < MAX_TRACKED_SYMBOLS; i++)
   {
      string s = TrimString(parts[i]);
      if(s == "")
         continue;

      outSymbols[validCount] = s;
      validCount++;
   }

   return validCount;
}
//+------------------------------------------------------------------+
//| Find symbol index                                                |
//+------------------------------------------------------------------+
int FindSymbolIndex(const string symbol)
{
   for(int i = 0; i < g_symbolsTotal; i++)
   {
      if(g_states[i].symbol == symbol)
         return i;
   }

   return -1;
}
//+------------------------------------------------------------------+
//| Utility: safe symbol select                                      |
//+------------------------------------------------------------------+
bool EnsureSymbolReady(const string symbol)
{
   if(symbol == "")
      return false;

   if(!SymbolSelect(symbol, true))
      return false;

   return true;
}

//+------------------------------------------------------------------+
//| Utility: refresh symbol market data                              |
//+------------------------------------------------------------------+
bool RefreshSymbolState(SymbolState &st)
{
   st.symbolSelected   = false;
   st.marketWatchReady = false;
   st.tradable         = false;
   st.spreadOk         = false;
   st.bid              = 0.0;
   st.ask              = 0.0;
   st.spreadPoints     = 0.0;
   st.point            = 0.0;
   st.digits           = 0;

   if(!EnsureSymbolReady(st.symbol))
      return false;

   st.symbolSelected = true;

   st.point  = SymbolInfoDouble(st.symbol, SYMBOL_POINT);
   st.digits = (int)SymbolInfoInteger(st.symbol, SYMBOL_DIGITS);

   if(st.point <= 0.0)
      return false;

   if(!SymbolInfoDouble(st.symbol, SYMBOL_BID, st.bid))
      return false;

   if(!SymbolInfoDouble(st.symbol, SYMBOL_ASK, st.ask))
      return false;

   st.spreadPoints = (st.ask - st.bid) / st.point;
   st.marketWatchReady = true;
   st.tradable = IsSymbolTradableNow(st.symbol);

   return true;
}

//+------------------------------------------------------------------+
//| Utility: new bar detection                                       |
//+------------------------------------------------------------------+
bool IsNewBar(const string symbol,
              const ENUM_TIMEFRAMES tf,
              datetime &lastBarTime)
{
   datetime barTime = iTime(symbol, tf, 0);
   if(barTime <= 0)
      return false;

   if(lastBarTime == 0)
   {
      lastBarTime = barTime;
      return false;
   }

   if(barTime != lastBarTime)
   {
      lastBarTime = barTime;
      return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| Logging                                                          |
//+------------------------------------------------------------------+
void DebugLog(const string msg)
{
   if(InpEnableDebug)
      Print("DBG | ", msg);
}

//+------------------------------------------------------------------+
//| Check whether symbol can be traded                               |
//+------------------------------------------------------------------+
bool IsSymbolTradableNow(const string symbol)
{
   if(symbol == "")
      return false;

   long tradeMode = SYMBOL_TRADE_MODE_DISABLED;
   if(!SymbolInfoInteger(symbol, SYMBOL_TRADE_MODE, tradeMode))
      return false;

   if(tradeMode == SYMBOL_TRADE_MODE_DISABLED)
      return false;

   bool visible = (bool)SymbolInfoInteger(symbol, SYMBOL_VISIBLE);
   if(!visible)
   {
      if(!SymbolSelect(symbol, true))
         return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| Spread filter                                                    |
//+------------------------------------------------------------------+
bool PassSpreadFilter(SymbolState &st)
{
   st.spreadOk = true;

   if(!InpUseSpreadFilter)
      return true;

   if(st.spreadPoints <= 0.0)
   {
      st.spreadOk = false;
      return false;
   }

   if(st.spreadPoints > (double)InpMaxSpreadPoints)
   {
      st.spreadOk = false;
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| Count open positions for symbol/magic                            |
//+------------------------------------------------------------------+
int CountOpenPositions(const string symbol)
{
   int count = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;

      if(!PositionSelectByTicket(ticket))
         continue;

      string posSymbol = PositionGetString(POSITION_SYMBOL);
      long   posMagic  = PositionGetInteger(POSITION_MAGIC);

      if(posSymbol != symbol)
         continue;

      if((ulong)posMagic != InpMagicNumber)
         continue;

      count++;
   }

   return count;
}

//+------------------------------------------------------------------+
//| Count pending orders for symbol/magic                            |
//+------------------------------------------------------------------+
int CountPendingOrders(const string symbol)
{
   int count = 0;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0)
         continue;

      if(!OrderSelect(ticket))
         continue;

      string ordSymbol = OrderGetString(ORDER_SYMBOL);
      long   ordMagic  = OrderGetInteger(ORDER_MAGIC);
      long   ordType   = OrderGetInteger(ORDER_TYPE);
      long   ordState  = OrderGetInteger(ORDER_STATE);

      if(ordSymbol != symbol)
         continue;

      if((ulong)ordMagic != InpMagicNumber)
         continue;

      if(ordState != ORDER_STATE_PLACED && ordState != ORDER_STATE_PARTIAL)
         continue;

      bool isPending =
         (ordType == ORDER_TYPE_BUY_LIMIT  ||
          ordType == ORDER_TYPE_SELL_LIMIT ||
          ordType == ORDER_TYPE_BUY_STOP   ||
          ordType == ORDER_TYPE_SELL_STOP  ||
          ordType == ORDER_TYPE_BUY_STOP_LIMIT ||
          ordType == ORDER_TYPE_SELL_STOP_LIMIT);

      if(!isPending)
         continue;

      count++;
   }

   return count;
}
//+------------------------------------------------------------------+
//| Check if matching pending already exists                         |
//+------------------------------------------------------------------+
bool HasMatchingPendingOrder(const string symbol,
                             const int direction,
                             const double triggerLevel,
                             const double oppositeLevel)
{
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0)
         continue;

      if(!OrderSelect(ticket))
         continue;

      string ordSymbol  = OrderGetString(ORDER_SYMBOL);
      long   ordMagic   = OrderGetInteger(ORDER_MAGIC);
      long   ordType    = OrderGetInteger(ORDER_TYPE);
      long   ordState   = OrderGetInteger(ORDER_STATE);
      string ordComment = OrderGetString(ORDER_COMMENT);

      if(ordSymbol != symbol)
         continue;

      if((ulong)ordMagic != InpMagicNumber)
         continue;

      if(ordState != ORDER_STATE_PLACED && ordState != ORDER_STATE_PARTIAL)
         continue;

      bool isPending =
         (ordType == ORDER_TYPE_BUY_STOP ||
          ordType == ORDER_TYPE_SELL_STOP ||
          ordType == ORDER_TYPE_BUY_STOP_LIMIT ||
          ordType == ORDER_TYPE_SELL_STOP_LIMIT);

      if(!isPending)
         continue;

      int    ordDir;
      double ordTrig;
      double ordOpp;

      if(!ParseSignalComment(ordComment, ordDir, ordTrig, ordOpp))
         continue;

      if(ordDir != direction)
         continue;

      if(NearlyEqualPrice(ordTrig, triggerLevel, point) &&
         NearlyEqualPrice(ordOpp, oppositeLevel, point))
      {
         return true;
      }
   }

   return false;
}
//+------------------------------------------------------------------+
//| Delete outdated pending orders of one direction                  |
//+------------------------------------------------------------------+
void DeleteOutdatedDirectionalPendings(const string symbol,
                                       const int direction,
                                       const double keepTriggerLevel,
                                       const double keepOppositeLevel)
{
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0)
         continue;

      if(!OrderSelect(ticket))
         continue;

      string ordSymbol  = OrderGetString(ORDER_SYMBOL);
      long   ordMagic   = OrderGetInteger(ORDER_MAGIC);
      long   ordType    = OrderGetInteger(ORDER_TYPE);
      long   ordState   = OrderGetInteger(ORDER_STATE);
      string ordComment = OrderGetString(ORDER_COMMENT);

      if(ordSymbol != symbol)
         continue;

      if((ulong)ordMagic != InpMagicNumber)
         continue;

      if(ordState != ORDER_STATE_PLACED && ordState != ORDER_STATE_PARTIAL)
         continue;

      bool isPending =
         (ordType == ORDER_TYPE_BUY_STOP ||
          ordType == ORDER_TYPE_SELL_STOP ||
          ordType == ORDER_TYPE_BUY_STOP_LIMIT ||
          ordType == ORDER_TYPE_SELL_STOP_LIMIT);

      if(!isPending)
         continue;

      int    ordDir;
      double ordTrig;
      double ordOpp;

      if(!ParseSignalComment(ordComment, ordDir, ordTrig, ordOpp))
         continue;

      if(ordDir != direction)
         continue;

      bool sameBox =
         NearlyEqualPrice(ordTrig, keepTriggerLevel, point) &&
         NearlyEqualPrice(ordOpp, keepOppositeLevel, point);

      if(sameBox)
         continue;

      if(trade.OrderDelete(ticket))
      {
         DebugLog(StringFormat("%s | outdated directional pending deleted | ticket=%I64u | dir=%d",
                  symbol,
                  ticket,
                  direction));
      }
   }
}
//+------------------------------------------------------------------+
//| Volume normalization                                             |
//+------------------------------------------------------------------+
double NormalizeVolume(const string symbol, const double lots)
{
   double minLot  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double stepLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);

   if(minLot <= 0.0 || maxLot <= 0.0 || stepLot <= 0.0)
      return 0.0;

   double vol = lots;

   if(vol < minLot)
      vol = minLot;
   if(vol > maxLot)
      vol = maxLot;

   vol = MathFloor(vol / stepLot) * stepLot;
   vol = MathMax(minLot, MathMin(maxLot, vol));

   return NormalizeDouble(vol, 2);
}

//+------------------------------------------------------------------+
//| Risk-based lot sizing skeleton                                   |
//+------------------------------------------------------------------+
double CalculateRiskLot(const string symbol,
                        const double entryPrice,
                        const double stopLossPrice)
{
   if(InpUseFixedLot)
      return NormalizeVolume(symbol, InpFixedLot);

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(balance <= 0.0)
      return 0.0;

   double riskMoney = balance * InpRiskPerTradePct / 100.0;
   if(riskMoney <= 0.0)
      return 0.0;

   double tickSize  = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);

   if(tickSize <= 0.0 || tickValue <= 0.0)
      return 0.0;

   double priceDist = MathAbs(entryPrice - stopLossPrice);
   if(priceDist <= 0.0)
      return 0.0;

   double moneyPerLot = (priceDist / tickSize) * tickValue;
   if(moneyPerLot <= 0.0)
      return 0.0;

   double lots = riskMoney / moneyPerLot;
   return NormalizeVolume(symbol, lots);
}

//+------------------------------------------------------------------+
//| Basic symbol gate                                                |
//+------------------------------------------------------------------+
bool CanProcessSymbol(SymbolState &st)
{
   st.tradable = IsSymbolTradableNow(st.symbol);
   if(!st.tradable)
      return false;

   if(!PassSpreadFilter(st))
      return false;

   return true;
}

//+------------------------------------------------------------------+
//| Symbol status logger                                             |
//+------------------------------------------------------------------+
void LogSymbolStatus(const SymbolState &st)
{
   DebugLog(StringFormat("%s | status | tradable=%s | spreadOk=%s | spread=%.1f | bid=%.*f | ask=%.*f | pos=%d | pend=%d",
            st.symbol,
            st.tradable ? "true" : "false",
            st.spreadOk ? "true" : "false",
            st.spreadPoints,
            st.digits, st.bid,
            st.digits, st.ask,
            CountOpenPositions(st.symbol),
            CountPendingOrders(st.symbol)));
}

//+------------------------------------------------------------------+
//| Placeholder pending placement helper                             |
//+------------------------------------------------------------------+
bool PlacePendingSkeleton(const string symbol,
                          const ENUM_ORDER_TYPE orderType,
                          const double price,
                          const double sl,
                          const double tp,
                          const double volume,
                          const string comment)
{
   if(symbol == "")
      return false;

   MqlTradeRequest req;
   MqlTradeResult  res;
   ZeroMemory(req);
   ZeroMemory(res);

   datetime expiry = iTime(symbol, InpScanTF, 0) + PeriodSeconds(InpScanTF) * InpPendingExpiryBars;

   req.action       = TRADE_ACTION_PENDING;
   req.symbol       = symbol;
   req.magic        = InpMagicNumber;
   req.type         = orderType;
   req.price        = price;
   req.sl           = sl;
   req.tp           = tp;
   req.volume       = volume;
   req.type_time    = ORDER_TIME_SPECIFIED;
   req.expiration   = expiry;
   req.type_filling = ORDER_FILLING_RETURN;
   req.comment      = comment;

   if(!OrderSend(req, res))
   {
      DebugLog(StringFormat("%s | pending send failed | retcode=%d", symbol, res.retcode));
      return false;
   }

   bool ok = (res.retcode == TRADE_RETCODE_DONE || res.retcode == TRADE_RETCODE_PLACED);

   DebugLog(StringFormat("%s | pending send result | retcode=%d | ok=%s",
            symbol,
            res.retcode,
            ok ? "true" : "false"));

   return ok;
}
//+------------------------------------------------------------------+
//| Is swing high                                                    |
//+------------------------------------------------------------------+
bool IsSwingHigh(const string symbol,
                 const ENUM_TIMEFRAMES tf,
                 const int shift,
                 const int leftBars,
                 const int rightBars)
{
   if(shift < rightBars || shift < 1)
      return false;

   double center = iHigh(symbol, tf, shift);
   if(center <= 0.0)
      return false;

   for(int i = 1; i <= leftBars; i++)
   {
      if(iHigh(symbol, tf, shift + i) >= center)
         return false;
   }

   for(int i = 1; i <= rightBars; i++)
   {
      if(iHigh(symbol, tf, shift - i) > center)
         return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| Is swing low                                                     |
//+------------------------------------------------------------------+
bool IsSwingLow(const string symbol,
                const ENUM_TIMEFRAMES tf,
                const int shift,
                const int leftBars,
                const int rightBars)
{
   if(shift < rightBars || shift < 1)
      return false;

   double center = iLow(symbol, tf, shift);
   if(center <= 0.0)
      return false;

   for(int i = 1; i <= leftBars; i++)
   {
      if(iLow(symbol, tf, shift + i) <= center)
         return false;
   }

   for(int i = 1; i <= rightBars; i++)
   {
      if(iLow(symbol, tf, shift - i) < center)
         return false;
   }

   return true;
}
//+------------------------------------------------------------------+
//| Find highest confirmed swing high in lookback                    |
//+------------------------------------------------------------------+
SwingPoint FindHighestSwingHighInLookback(const string symbol,
                                          const ENUM_TIMEFRAMES tf,
                                          const int lookbackBars,
                                          const int leftBars,
                                          const int rightBars)
{
   SwingPoint sp;
   sp.valid = false;
   sp.shift = -1;
   sp.price = 0.0;

   int startShift = rightBars + 1;
   int endShift   = lookbackBars;

   for(int shift = startShift; shift <= endShift; shift++)
   {
      if(!IsSwingHigh(symbol, tf, shift, leftBars, rightBars))
         continue;

      double price = iHigh(symbol, tf, shift);

      if(!sp.valid || price > sp.price)
      {
         sp.valid = true;
         sp.shift = shift;
         sp.price = price;
      }
   }

   return sp;
}

//+------------------------------------------------------------------+
//| Find lowest confirmed swing low in lookback                      |
//+------------------------------------------------------------------+
SwingPoint FindLowestSwingLowInLookback(const string symbol,
                                        const ENUM_TIMEFRAMES tf,
                                        const int lookbackBars,
                                        const int leftBars,
                                        const int rightBars)
{
   SwingPoint sp;
   sp.valid = false;
   sp.shift = -1;
   sp.price = 0.0;

   int startShift = rightBars + 1;
   int endShift   = lookbackBars;

   for(int shift = startShift; shift <= endShift; shift++)
   {
      if(!IsSwingLow(symbol, tf, shift, leftBars, rightBars))
         continue;

      double price = iLow(symbol, tf, shift);

      if(!sp.valid || price < sp.price)
      {
         sp.valid = true;
         sp.shift = shift;
         sp.price = price;
      }
   }

   return sp;
}
//+------------------------------------------------------------------+
//| Get active breakout structure box                                |
//+------------------------------------------------------------------+
bool GetBreakoutStructureBox(const string symbol,
                             const ENUM_TIMEFRAMES tf,
                             SwingPoint &boxHigh,
                             SwingPoint &boxLow)
{
   boxHigh = FindHighestSwingHighInLookback(symbol,
                                            tf,
                                            InpStructureLookbackBars,
                                            InpSwingLeftBars,
                                            InpSwingRightBars);

   boxLow  = FindLowestSwingLowInLookback(symbol,
                                          tf,
                                          InpStructureLookbackBars,
                                          InpSwingLeftBars,
                                          InpSwingRightBars);

   if(!boxHigh.valid || !boxLow.valid)
      return false;

   if(boxHigh.price <= boxLow.price)
      return false;

   return true;
}
//+------------------------------------------------------------------+
//| Simple H4 trend bias                                             |
//| Returns BREAKOUT_BUY, BREAKOUT_SELL, BREAKOUT_NONE               |
//+------------------------------------------------------------------+
int GetH4TrendBias(const string symbol)
{
   double close1 = iClose(symbol, PERIOD_H4, 1);
   double close2 = iClose(symbol, PERIOD_H4, 2);
   double high1  = iHigh(symbol, PERIOD_H4, 1);
   double high2  = iHigh(symbol, PERIOD_H4, 2);
   double low1   = iLow(symbol, PERIOD_H4, 1);
   double low2   = iLow(symbol, PERIOD_H4, 2);

   if(close1 <= 0.0 || close2 <= 0.0)
      return BREAKOUT_NONE;

   if(high1 > high2 && low1 > low2 && close1 > close2)
      return BREAKOUT_BUY;

   if(high1 < high2 && low1 < low2 && close1 < close2)
      return BREAKOUT_SELL;

   return BREAKOUT_NONE;
}
//+------------------------------------------------------------------+
//| Build buy-side structure break signal                            |
//+------------------------------------------------------------------+
bool BuildBuyBreakoutSignal(SymbolState &st, BreakoutSignal &sig)
{
   sig.valid = false;

   SwingPoint boxHigh, boxLow;
   if(!GetBreakoutStructureBox(st.symbol, InpScanTF, boxHigh, boxLow))
   {
      DebugLog(StringFormat("%s | buy signal invalid | no valid breakout box", st.symbol));
      return false;
   }


   double atr = GetATRValue(st.symbol, InpScanTF, InpATRPeriod, 1);
   if(!ValidateStructureQuality(st.symbol, boxHigh.price, boxLow.price, atr, st.point))
      return false;

   double entryBuffer = GetBreakoutBufferPrice(st.symbol, st.point, atr);
   double entry       = boxHigh.price + entryBuffer;
   double sl          = boxLow.price  - InpStopBufferPoints * st.point;

   if(sl >= entry)
   {
      DebugLog(StringFormat("%s | buy signal invalid | sl >= entry", st.symbol));
      return false;
   }

   if(!ValidateStopDistance(st.symbol, entry, sl, st.point))
      return false;

   double riskDist = entry - sl;
   if(riskDist <= 0.0)
      return false;

   double tp  = entry + riskDist * InpTakeProfitRR;
   double vol = CalculateRiskLot(st.symbol, entry, sl);

   if(vol <= 0.0)
   {
      DebugLog(StringFormat("%s | buy signal invalid | volume <= 0", st.symbol));
      return false;
   }

   sig.valid         = true;
   sig.symbol        = st.symbol;
   sig.direction     = BREAKOUT_BUY;
   sig.entry         = NormalizeDouble(entry, st.digits);
   sig.stopLoss      = NormalizeDouble(sl, st.digits);
   sig.takeProfit    = NormalizeDouble(tp, st.digits);
   sig.volume        = vol;
   sig.triggerLevel  = boxHigh.price;
   sig.oppositeLevel = boxLow.price;
   sig.structureHigh = boxHigh.price;
   sig.structureLow  = boxLow.price;
   sig.structureSize = MathAbs(boxHigh.price - boxLow.price);
   sig.atrValue      = atr;
   sig.triggerShift  = boxHigh.shift;
   sig.oppositeShift = boxLow.shift;
   sig.comment       = BuildSignalComment(BREAKOUT_BUY, boxHigh.price, boxLow.price);

   return true;
}

//+------------------------------------------------------------------+
//| Build sell-side structure break signal                           |
//+------------------------------------------------------------------+
bool BuildSellBreakoutSignal(SymbolState &st, BreakoutSignal &sig)
{
   sig.valid = false;

   SwingPoint boxHigh, boxLow;
   if(!GetBreakoutStructureBox(st.symbol, InpScanTF, boxHigh, boxLow))
   {
      DebugLog(StringFormat("%s | sell signal invalid | no valid breakout box", st.symbol));
      return false;
   }


   double atr = GetATRValue(st.symbol, InpScanTF, InpATRPeriod, 1);
   if(!ValidateStructureQuality(st.symbol, boxLow.price, boxHigh.price, atr, st.point))
      return false;

   double entryBuffer = GetBreakoutBufferPrice(st.symbol, st.point, atr);
   double entry       = boxLow.price  - entryBuffer;
   double sl          = boxHigh.price + InpStopBufferPoints * st.point;

   if(sl <= entry)
   {
      DebugLog(StringFormat("%s | sell signal invalid | sl <= entry", st.symbol));
      return false;
   }

   if(!ValidateStopDistance(st.symbol, entry, sl, st.point))
      return false;

   double riskDist = sl - entry;
   if(riskDist <= 0.0)
      return false;

   double tp  = entry - riskDist * InpTakeProfitRR;
   double vol = CalculateRiskLot(st.symbol, entry, sl);

   if(vol <= 0.0)
   {
      DebugLog(StringFormat("%s | sell signal invalid | volume <= 0", st.symbol));
      return false;
   }

   sig.valid         = true;
   sig.symbol        = st.symbol;
   sig.direction     = BREAKOUT_SELL;
   sig.entry         = NormalizeDouble(entry, st.digits);
   sig.stopLoss      = NormalizeDouble(sl, st.digits);
   sig.takeProfit    = NormalizeDouble(tp, st.digits);
   sig.volume        = vol;
   sig.triggerLevel  = boxLow.price;
   sig.oppositeLevel = boxHigh.price;
   sig.structureHigh = boxHigh.price;
   sig.structureLow  = boxLow.price;
   sig.structureSize = MathAbs(boxHigh.price - boxLow.price);
   sig.atrValue      = atr;
   sig.triggerShift  = boxLow.shift;
   sig.oppositeShift = boxHigh.shift;
   sig.comment       = BuildSignalComment(BREAKOUT_SELL, boxLow.price, boxHigh.price);

   return true;
}
//+------------------------------------------------------------------+
//| Place breakout signal                                            |
//+------------------------------------------------------------------+
bool PlaceBreakoutSignal(const BreakoutSignal &sig)
{
   if(!sig.valid)
      return false;

   ENUM_ORDER_TYPE type = ORDER_TYPE_BUY_STOP;

   if(sig.direction == BREAKOUT_BUY)
      type = ORDER_TYPE_BUY_STOP;
   else if(sig.direction == BREAKOUT_SELL)
      type = ORDER_TYPE_SELL_STOP;
   else
      return false;

   return PlacePendingSkeleton(sig.symbol,
                               type,
                               sig.entry,
                               sig.stopLoss,
                               sig.takeProfit,
                               sig.volume,
                               sig.comment);
}
//+------------------------------------------------------------------+
//| Find first live position for symbol/magic                        |
//+------------------------------------------------------------------+
bool GetSymbolPosition(const string symbol,
                       ulong &ticket,
                       int &type,
                       double &volume,
                       double &openPrice,
                       double &sl,
                       double &tp)
{
   ticket    = 0;
   type      = -1;
   volume    = 0.0;
   openPrice = 0.0;
   sl        = 0.0;
   tp        = 0.0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong posTicket = PositionGetTicket(i);
      if(posTicket == 0)
         continue;

      if(!PositionSelectByTicket(posTicket))
         continue;

      string posSymbol = PositionGetString(POSITION_SYMBOL);
      long   posMagic  = PositionGetInteger(POSITION_MAGIC);

      if(posSymbol != symbol)
         continue;

      if((ulong)posMagic != InpMagicNumber)
         continue;

      ticket    = posTicket;
      type      = (int)PositionGetInteger(POSITION_TYPE);
      volume    = PositionGetDouble(POSITION_VOLUME);
      openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      sl        = PositionGetDouble(POSITION_SL);
      tp        = PositionGetDouble(POSITION_TP);
      return true;
   }

   return false;
}
//+------------------------------------------------------------------+
//| Start tracking live position                                     |
//+------------------------------------------------------------------+
void StartTrackingPosition(PositionMgmtState &ms,
                           const string symbol,
                           const ulong ticket,
                           const int posType,
                           const double volume,
                           const double openPrice,
                           const double sl,
                           const double tp)
{
   ms.active              = true;
   ms.ticket              = ticket;
   ms.symbol              = symbol;
   ms.posType             = posType;
   ms.initialVolume       = volume;
   ms.initialOpenPrice    = openPrice;
   ms.initialSL           = sl;
   ms.initialTP           = tp;
   ms.initialRiskDistance = GetPositionRiskDistance(symbol, posType, openPrice, sl);
   ms.breakEvenDone       = false;
   ms.partialCloseDone    = false;
   ms.trailActivated      = false;

   DebugLog(StringFormat("%s | tracking started | ticket=%I64u | type=%d | vol=%.2f | open=%.*f | sl=%.*f | tp=%.*f | risk=%.5f",
            symbol,
            ticket,
            posType,
            volume,
            (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS), openPrice,
            (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS), sl,
            (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS), tp,
            ms.initialRiskDistance));
}

//+------------------------------------------------------------------+
//| Stop tracking when position is gone                              |
//+------------------------------------------------------------------+
void StopTrackingPosition(PositionMgmtState &ms)
{
   if(ms.active)
   {
      DebugLog(StringFormat("%s | tracking reset | old ticket=%I64u", ms.symbol, ms.ticket));
   }

   string sym = ms.symbol;
   ResetMgmtState(ms);
   ms.symbol = sym;
}

//+------------------------------------------------------------------+
//| Sync management state with live position                         |
//+------------------------------------------------------------------+
bool SyncMgmtState(const string symbol, PositionMgmtState &ms)
{
   ulong  ticket;
   int    posType;
   double volume;
   double openPrice;
   double sl;
   double tp;

   bool hasLive = GetSymbolPosition(symbol, ticket, posType, volume, openPrice, sl, tp);

   if(!hasLive)
   {
      StopTrackingPosition(ms);
      return false;
   }

   if(!ms.active || ms.ticket != ticket)
   {
      StartTrackingPosition(ms, symbol, ticket, posType, volume, openPrice, sl, tp);
      return true;
   }

   return true;
}
//+------------------------------------------------------------------+
//| Position initial risk in price units                             |
//+------------------------------------------------------------------+
double GetPositionRiskDistance(const string symbol,
                               const int posType,
                               const double openPrice,
                               const double sl)
{
   if(openPrice <= 0.0 || sl <= 0.0)
      return 0.0;

   if(posType == POSITION_TYPE_BUY)
      return openPrice - sl;

   if(posType == POSITION_TYPE_SELL)
      return sl - openPrice;

   return 0.0;
}

//+------------------------------------------------------------------+
//| Current profit distance in price units                           |
//+------------------------------------------------------------------+
double GetPositionProfitDistance(const string symbol,
                                 const int posType,
                                 const double openPrice)
{
   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);

   if(openPrice <= 0.0)
      return 0.0;

   if(posType == POSITION_TYPE_BUY)
      return bid - openPrice;

   if(posType == POSITION_TYPE_SELL)
      return openPrice - ask;

   return 0.0;
}

//+------------------------------------------------------------------+
//| Current R multiple                                               |
//+------------------------------------------------------------------+
double GetPositionRMultiple(const string symbol,
                            const int posType,
                            const double openPrice,
                            const double sl)
{
   double riskDist   = GetPositionRiskDistance(symbol, posType, openPrice, sl);
   double profitDist = GetPositionProfitDistance(symbol, posType, openPrice);

   if(riskDist <= 0.0)
      return 0.0;

   return profitDist / riskDist;
}
//+------------------------------------------------------------------+
//| Current R using stored initial risk                              |
//+------------------------------------------------------------------+
double GetStoredRiskRMultiple(const string symbol,
                              const int posType,
                              const double openPrice,
                              const double initialRiskDistance)
{
   if(initialRiskDistance <= 0.0)
      return 0.0;

   double profitDist = GetPositionProfitDistance(symbol, posType, openPrice);
   return profitDist / initialRiskDistance;
}

//+------------------------------------------------------------------+
//| Delete all pending orders for symbol/magic                       |
//+------------------------------------------------------------------+
void DeleteSymbolPendingOrders(const string symbol)
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0)
         continue;

      if(!OrderSelect(ticket))
         continue;

      string ordSymbol = OrderGetString(ORDER_SYMBOL);
      long   ordMagic  = OrderGetInteger(ORDER_MAGIC);
      long   ordType   = OrderGetInteger(ORDER_TYPE);
      long   ordState  = OrderGetInteger(ORDER_STATE);

      if(ordSymbol != symbol)
         continue;

      if((ulong)ordMagic != InpMagicNumber)
         continue;

      bool isPending =
         (ordType == ORDER_TYPE_BUY_LIMIT  ||
          ordType == ORDER_TYPE_SELL_LIMIT ||
          ordType == ORDER_TYPE_BUY_STOP   ||
          ordType == ORDER_TYPE_SELL_STOP  ||
          ordType == ORDER_TYPE_BUY_STOP_LIMIT ||
          ordType == ORDER_TYPE_SELL_STOP_LIMIT);

      if(!isPending)
         continue;

      if(ordState != ORDER_STATE_PLACED && ordState != ORDER_STATE_PARTIAL)
         continue;

      bool ok = trade.OrderDelete(ticket);
      if(ok)
         DebugLog(StringFormat("%s | pending deleted after fill | ticket=%I64u", symbol, ticket));
   }
}
//+------------------------------------------------------------------+
//| Modify position SL/TP                                            |
//+------------------------------------------------------------------+
bool ModifyPositionStops(const string symbol,
                         const double newSL,
                         const double newTP)
{
   if(!trade.PositionModify(symbol, newSL, newTP))
   {
      DebugLog(StringFormat("%s | PositionModify failed | sl=%.*f tp=%.*f",
               symbol,
               (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS), newSL,
               (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS), newTP));
      return false;
   }

   DebugLog(StringFormat("%s | PositionModify ok | sl=%.*f tp=%.*f",
            symbol,
            (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS), newSL,
            (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS), newTP));

   return true;
}
//+------------------------------------------------------------------+
//| Get ATR value                                                    |
//+------------------------------------------------------------------+
double GetATRValue(const string symbol,
                   const ENUM_TIMEFRAMES tf,
                   const int period,
                   const int shift = 1)
{
   int handle = iATR(symbol, tf, period);
   if(handle == INVALID_HANDLE)
      return 0.0;

   double buffer[];
   ArraySetAsSeries(buffer, true);

   double value = 0.0;

   if(CopyBuffer(handle, 0, shift, 1, buffer) == 1)
      value = buffer[0];

   IndicatorRelease(handle);
   return value;
}

//+------------------------------------------------------------------+
//| Validate breakout structure quality                              |
//+------------------------------------------------------------------+
bool ValidateStructureQuality(const string symbol,
                              const double triggerLevel,
                              const double oppositeLevel,
                              const double atrValue,
                              const double point)
{
   double structureSize = MathAbs(triggerLevel - oppositeLevel);
   double structurePts  = structureSize / point;

   if(structurePts < InpMinStructureSizePoints)
   {
      DebugLog(StringFormat("%s | structure rejected | too small | pts=%.1f < %.1f",
               symbol,
               structurePts,
               InpMinStructureSizePoints));
      return false;
   }

   if(atrValue > 0.0)
   {
      double atrMultiple = structureSize / atrValue;

      if(atrMultiple < InpMinStructureATRMultiple)
      {
         DebugLog(StringFormat("%s | structure rejected | ATR multiple too small | mult=%.2f < %.2f",
                  symbol,
                  atrMultiple,
                  InpMinStructureATRMultiple));
         return false;
      }
   }

   return true;
}

//+------------------------------------------------------------------+
//| Validate stop distance                                            |
//+------------------------------------------------------------------+
bool ValidateStopDistance(const string symbol,
                          const double entry,
                          const double stopLoss,
                          const double point)
{
   double stopPts = MathAbs(entry - stopLoss) / point;

   if(stopPts < InpMinStopDistancePoints)
   {
      DebugLog(StringFormat("%s | stop distance rejected | pts=%.1f < %.1f",
               symbol,
               stopPts,
               InpMinStopDistancePoints));
      return false;
   }

   return true;
}
//+------------------------------------------------------------------+
//| Invalidate pending structure before fill                         |
//+------------------------------------------------------------------+
bool IsPendingInvalidated(const string symbol,
                          const int direction,
                          const double triggerLevel,
                          const double oppositeLevel)
{
   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);

   if(direction == BREAKOUT_BUY)
   {
      // buy breakout invalidates if market breaks below opposite structure
      if(bid < oppositeLevel)
         return true;
   }
   else if(direction == BREAKOUT_SELL)
   {
      // sell breakout invalidates if market breaks above opposite structure
      if(ask > oppositeLevel)
         return true;
   }

   return false;
}
//+------------------------------------------------------------------+
//| Build compact order comment                                      |
//+------------------------------------------------------------------+
string BuildSignalComment(const int direction,
                          const double triggerLevel,
                          const double oppositeLevel)
{
   string dir = (direction == BREAKOUT_BUY) ? "B" : "S";
   return StringFormat("H1BX|%s|%.5f|%.5f", dir, triggerLevel, oppositeLevel);
}

//+------------------------------------------------------------------+
//| Parse compact order comment                                      |
//+------------------------------------------------------------------+
bool ParseSignalComment(const string comment,
                        int &direction,
                        double &triggerLevel,
                        double &oppositeLevel)
{
   direction     = BREAKOUT_NONE;
   triggerLevel  = 0.0;
   oppositeLevel = 0.0;

   string parts[];
   int cnt = StringSplit(comment, '|', parts);
   if(cnt != 4)
      return false;

   if(parts[0] != "H1BX")
      return false;

   if(parts[1] == "B")
      direction = BREAKOUT_BUY;
   else if(parts[1] == "S")
      direction = BREAKOUT_SELL;
   else
      return false;

   triggerLevel  = StringToDouble(parts[2]);
   oppositeLevel = StringToDouble(parts[3]);

   if(triggerLevel <= 0.0 || oppositeLevel <= 0.0)
      return false;

   return true;
}
//+------------------------------------------------------------------+
//| Compare price levels with tolerance                              |
//+------------------------------------------------------------------+
bool NearlyEqualPrice(const double a, const double b, const double point)
{
   return (MathAbs(a - b) <= point * 0.5);
}
//+------------------------------------------------------------------+
//| Apply break-even                                                 |
//+------------------------------------------------------------------+
void TryApplyBreakEven(PositionMgmtState &ms,
                       const string symbol,
                       const int posType,
                       const double liveOpenPrice,
                       const double liveSL,
                       const double liveTP)
{
   if(!InpUseBreakEven)
      return;

   if(ms.breakEvenDone)
      return;

   double rNow = GetStoredRiskRMultiple(symbol, posType, ms.initialOpenPrice, ms.initialRiskDistance);
   if(rNow < InpBreakEvenAtR)
      return;

   double point  = SymbolInfoDouble(symbol, SYMBOL_POINT);
   int    digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);

   double beSL = liveSL;

   if(posType == POSITION_TYPE_BUY)
      beSL = ms.initialOpenPrice + InpBreakEvenOffsetPoints * point;
   else if(posType == POSITION_TYPE_SELL)
      beSL = ms.initialOpenPrice - InpBreakEvenOffsetPoints * point;
   else
      return;

   beSL = NormalizeDouble(beSL, digits);

   bool improve = false;

   if(posType == POSITION_TYPE_BUY && beSL > liveSL)
      improve = true;

   if(posType == POSITION_TYPE_SELL && (liveSL == 0.0 || beSL < liveSL))
      improve = true;

   if(!improve)
      return;

   if(ModifyPositionStops(symbol, beSL, liveTP))
   {
      ms.breakEvenDone = true;
      DebugLog(StringFormat("%s | BE applied | ticket=%I64u | R=%.2f",
               symbol,
               ms.ticket,
               rNow));
   }
}

//+------------------------------------------------------------------+
//| Partial close marker via position comment is not reliable here   |
//| So use simple live condition: only close if volume still large   |
//+------------------------------------------------------------------+
void TryApplyPartialClose(PositionMgmtState &ms,
                          const string symbol,
                          const double liveVolume,
                          const int posType)
{
   if(!InpUsePartialClose)
      return;

   if(ms.partialCloseDone)
      return;

   double rNow = GetStoredRiskRMultiple(symbol, posType, ms.initialOpenPrice, ms.initialRiskDistance);
   if(rNow < InpPartialCloseAtR)
      return;

   double volMin  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double volStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);

   if(volMin <= 0.0 || volStep <= 0.0)
      return;

   double closeVol = ms.initialVolume * (InpPartialClosePct / 100.0);
   closeVol = NormalizeVolume(symbol, closeVol);

   if(closeVol <= 0.0)
      return;

   if(liveVolume - closeVol < volMin)
   {
      DebugLog(StringFormat("%s | partial skipped | remaining volume would be below min", symbol));
      return;
   }

   if(!trade.PositionClosePartial(symbol, closeVol))
   {
      DebugLog(StringFormat("%s | partial close failed | vol=%.2f", symbol, closeVol));
      return;
   }

   ms.partialCloseDone = true;

   DebugLog(StringFormat("%s | partial close ok | ticket=%I64u | closeVol=%.2f | R=%.2f",
            symbol,
            ms.ticket,
            closeVol,
            rNow));
}

//+------------------------------------------------------------------+
//| Apply ATR trailing                                               |
//+------------------------------------------------------------------+
void TryApplyATRTrail(PositionMgmtState &ms,
                      const string symbol,
                      const int posType,
                      const double liveSL,
                      const double liveTP)
{
   if(!InpUseATRTrail)
      return;

   double rNow = GetStoredRiskRMultiple(symbol, posType, ms.initialOpenPrice, ms.initialRiskDistance);
   if(rNow < InpATRTrailStartR)
      return;

   if(!ms.trailActivated)
   {
      ms.trailActivated = true;

      DebugLog(StringFormat("%s | ATR trail activated | ticket=%I64u | R=%.2f",
               symbol,
               ms.ticket,
               rNow));

      // --- OPTIONAL: remove TP on trail start ---
      if(InpRemoveTPOnTrailStart)
      {
         if(liveTP > 0.0)
         {
            if(ModifyPositionStops(symbol, liveSL, 0.0))
            {
               DebugLog(StringFormat("%s | TP removed on trail activation | ticket=%I64u",
                        symbol,
                        ms.ticket));
            }
         }
      }
   }

   double atr = GetATRValue(symbol, InpScanTF, InpATRPeriod, 1);
   if(atr <= 0.0)
      return;

   int    digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   double bid    = SymbolInfoDouble(symbol, SYMBOL_BID);
   double ask    = SymbolInfoDouble(symbol, SYMBOL_ASK);

   double newSL = liveSL;

   if(posType == POSITION_TYPE_BUY)
   {
      newSL = bid - atr * InpATRTrailMult;
      newSL = NormalizeDouble(newSL, digits);

      if(newSL > liveSL && newSL < bid)
      {
         if(ModifyPositionStops(symbol, newSL, liveTP))
         {
            DebugLog(StringFormat("%s | ATR trail moved | ticket=%I64u | newSL=%.*f | R=%.2f",
                     symbol,
                     ms.ticket,
                     digits, newSL,
                     rNow));
         }
      }
   }
   else if(posType == POSITION_TYPE_SELL)
   {
      newSL = ask + atr * InpATRTrailMult;
      newSL = NormalizeDouble(newSL, digits);

      if((liveSL == 0.0 || newSL < liveSL) && newSL > ask)
      {
         if(ModifyPositionStops(symbol, newSL, liveTP))
         {
            DebugLog(StringFormat("%s | ATR trail moved | ticket=%I64u | newSL=%.*f | R=%.2f",
                     symbol,
                     ms.ticket,
                     digits, newSL,
                     rNow));
         }
      }
   }
}
//+------------------------------------------------------------------+
//| Placeholder: signal scan                                         |
//+------------------------------------------------------------------+
void ScanForSignal(SymbolState &st)
{
   int openPos = CountOpenPositions(st.symbol);
   int pendOrd = CountPendingOrders(st.symbol);

   DebugLog(StringFormat("%s | scan hook called on %s | openPos=%d | pending=%d",
            st.symbol,
            EnumToString(InpScanTF),
            openPos,
            pendOrd));

   if(InpOnePositionPerSymbol && openPos > 0)
   {
      DebugLog(StringFormat("%s | scan note | live position exists, but dual pending model may still maintain opposite order", st.symbol));
   }

   BreakoutSignal buySig;
   BreakoutSignal sellSig;
   ZeroMemory(buySig);
   ZeroMemory(sellSig);

   bool hasBuy  = BuildBuyBreakoutSignal(st, buySig);
   bool hasSell = BuildSellBreakoutSignal(st, sellSig);

   if(hasBuy)
   {
      DeleteOutdatedDirectionalPendings(st.symbol,
                                        BREAKOUT_BUY,
                                        buySig.triggerLevel,
                                        buySig.oppositeLevel);

      if(!HasMatchingPendingOrder(st.symbol,
                                  BREAKOUT_BUY,
                                  buySig.triggerLevel,
                                  buySig.oppositeLevel))
      {
         DebugLog(StringFormat("%s | BUY breakout ready | entry=%.*f sl=%.*f tp=%.*f vol=%.2f boxH=%.*f boxL=%.*f structPts=%.1f atr=%.5f",
                  st.symbol,
                  st.digits, buySig.entry,
                  st.digits, buySig.stopLoss,
                  st.digits, buySig.takeProfit,
                  buySig.volume,
                  st.digits, buySig.structureHigh,
                  st.digits, buySig.structureLow,
                  buySig.structureSize / st.point,
                  buySig.atrValue));

         if(PlaceBreakoutSignal(buySig))
            DebugLog(StringFormat("%s | BUY STOP placed/refreshed", st.symbol));
         else
            DebugLog(StringFormat("%s | BUY STOP placement failed", st.symbol));
      }
      else
      {
         DebugLog(StringFormat("%s | BUY pending already matches current box", st.symbol));
      }
   }
   else
   {
      DeleteOutdatedDirectionalPendings(st.symbol, BREAKOUT_BUY, 0.0, 0.0);
   }

   if(hasSell)
   {
      DeleteOutdatedDirectionalPendings(st.symbol,
                                        BREAKOUT_SELL,
                                        sellSig.triggerLevel,
                                        sellSig.oppositeLevel);

      if(!HasMatchingPendingOrder(st.symbol,
                                  BREAKOUT_SELL,
                                  sellSig.triggerLevel,
                                  sellSig.oppositeLevel))
      {
         DebugLog(StringFormat("%s | SELL breakout ready | entry=%.*f sl=%.*f tp=%.*f vol=%.2f boxH=%.*f boxL=%.*f structPts=%.1f atr=%.5f",
                  st.symbol,
                  st.digits, sellSig.entry,
                  st.digits, sellSig.stopLoss,
                  st.digits, sellSig.takeProfit,
                  sellSig.volume,
                  st.digits, sellSig.structureHigh,
                  st.digits, sellSig.structureLow,
                  sellSig.structureSize / st.point,
                  sellSig.atrValue));

         if(PlaceBreakoutSignal(sellSig))
            DebugLog(StringFormat("%s | SELL STOP placed/refreshed", st.symbol));
         else
            DebugLog(StringFormat("%s | SELL STOP placement failed", st.symbol));
      }
      else
      {
         DebugLog(StringFormat("%s | SELL pending already matches current box", st.symbol));
      }
   }
   else
   {
      DeleteOutdatedDirectionalPendings(st.symbol, BREAKOUT_SELL, 0.0, 0.0);
   }

   if(!hasBuy && !hasSell)
      DebugLog(StringFormat("%s | no valid breakout box signal", st.symbol));
}
//+------------------------------------------------------------------+
//| Placeholder: pending order management                            |
//+------------------------------------------------------------------+
void ManagePendingOrders(SymbolState &st)
{
   int pendingCount = CountPendingOrders(st.symbol);

   if(pendingCount <= 0)
      return;

   DebugLog(StringFormat("%s | manage pending hook | count=%d", st.symbol, pendingCount));

   datetime nowTime = TimeCurrent();

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0)
         continue;

      if(!OrderSelect(ticket))
         continue;

      string ordSymbol = OrderGetString(ORDER_SYMBOL);
      long   ordMagic  = OrderGetInteger(ORDER_MAGIC);
      long   ordType   = OrderGetInteger(ORDER_TYPE);
      long   ordState  = OrderGetInteger(ORDER_STATE);
      datetime expiry  = (datetime)OrderGetInteger(ORDER_TIME_EXPIRATION);
      string ordComment = OrderGetString(ORDER_COMMENT);

      if(ordSymbol != st.symbol)
         continue;

      if((ulong)ordMagic != InpMagicNumber)
         continue;

      bool isPending =
         (ordType == ORDER_TYPE_BUY_LIMIT  ||
          ordType == ORDER_TYPE_SELL_LIMIT ||
          ordType == ORDER_TYPE_BUY_STOP   ||
          ordType == ORDER_TYPE_SELL_STOP  ||
          ordType == ORDER_TYPE_BUY_STOP_LIMIT ||
          ordType == ORDER_TYPE_SELL_STOP_LIMIT);

      if(!isPending)
         continue;

      if(ordState != ORDER_STATE_PLACED && ordState != ORDER_STATE_PARTIAL)
         continue;

      if(expiry > 0 && nowTime >= expiry)
      {
         if(trade.OrderDelete(ticket))
            DebugLog(StringFormat("%s | expired pending deleted | ticket=%I64u", st.symbol, ticket));
         continue;
      }

      if(InpUsePendingInvalidation)
      {
         int    direction;
         double triggerLevel;
         double oppositeLevel;

         if(ParseSignalComment(ordComment, direction, triggerLevel, oppositeLevel))
         {
            if(IsPendingInvalidated(st.symbol, direction, triggerLevel, oppositeLevel))
            {
               if(trade.OrderDelete(ticket))
               {
                  DebugLog(StringFormat("%s | invalidated pending deleted | ticket=%I64u | dir=%d | trig=%.*f | opp=%.*f",
                           st.symbol,
                           ticket,
                           direction,
                           st.digits, triggerLevel,
                           st.digits, oppositeLevel));
               }
            }
         }
      }
   }
}
//+------------------------------------------------------------------+
//| Placeholder: open position management                            |
//+------------------------------------------------------------------+
void ManageOpenPositions(SymbolState &st)
{
   int idx = FindSymbolIndex(st.symbol);
   if(idx < 0)
      return;

   if(!SyncMgmtState(st.symbol, g_mgmt[idx]))
      return;

   ulong  ticket;
   int    posType;
   double volume;
   double openPrice;
   double sl;
   double tp;

   if(!GetSymbolPosition(st.symbol, ticket, posType, volume, openPrice, sl, tp))
      return;

   double rStored = GetStoredRiskRMultiple(st.symbol,
                                           posType,
                                           g_mgmt[idx].initialOpenPrice,
                                           g_mgmt[idx].initialRiskDistance);

   DebugLog(StringFormat("%s | manage position | ticket=%I64u | type=%d | vol=%.2f | open=%.*f | sl=%.*f | tp=%.*f | Rstored=%.2f | BE=%s | PC=%s | TR=%s",
            st.symbol,
            ticket,
            posType,
            volume,
            st.digits, openPrice,
            st.digits, sl,
            st.digits, tp,
            rStored,
            g_mgmt[idx].breakEvenDone ? "1" : "0",
            g_mgmt[idx].partialCloseDone ? "1" : "0",
            g_mgmt[idx].trailActivated ? "1" : "0"));

   if(!InpKeepOppositePendingAfterFill)
      DeleteSymbolPendingOrders(st.symbol);

   TryApplyBreakEven(g_mgmt[idx], st.symbol, posType, openPrice, sl, tp);

   if(PositionSelect(st.symbol))
   {
      volume    = PositionGetDouble(POSITION_VOLUME);
      openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      sl        = PositionGetDouble(POSITION_SL);
      tp        = PositionGetDouble(POSITION_TP);
      posType   = (int)PositionGetInteger(POSITION_TYPE);
   }

   TryApplyPartialClose(g_mgmt[idx], st.symbol, volume, posType);

   if(PositionSelect(st.symbol))
   {
      volume    = PositionGetDouble(POSITION_VOLUME);
      openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      sl        = PositionGetDouble(POSITION_SL);
      tp        = PositionGetDouble(POSITION_TP);
      posType   = (int)PositionGetInteger(POSITION_TYPE);
   }

   TryApplyATRTrail(g_mgmt[idx], st.symbol, posType, sl, tp);
}

//+------------------------------------------------------------------+
//| Core per-symbol process                                          |
//+------------------------------------------------------------------+
void ProcessSymbol(SymbolState &st)
{
   if(!st.enabled)
      return;

   if(!RefreshSymbolState(st))
   {
      DebugLog(StringFormat("%s | refresh failed", st.symbol));
      return;
   }

   bool isNewScanBar = IsNewBar(st.symbol, InpScanTF, st.lastScanBarTime);
   bool canProcess   = CanProcessSymbol(st);

   if(isNewScanBar)
   {
      ManagePendingOrders(st);
      ManageOpenPositions(st);

      LogSymbolStatus(st);

      if(!canProcess)
      {
         DebugLog(StringFormat("%s | scan skipped | tradable=%s | spreadOk=%s",
                  st.symbol,
                  st.tradable ? "true" : "false",
                  st.spreadOk ? "true" : "false"));
         st.lastCanProcess = false;
         return;
      }

      DebugLog(StringFormat("%s | new bar detected on %s",
               st.symbol,
               EnumToString(InpScanTF)));

      ScanForSignal(st);
      st.lastCanProcess = true;
   }
}

//+------------------------------------------------------------------+
//| Init symbol states                                               |
//+------------------------------------------------------------------+
bool InitializeSymbols()
{
   g_symbolsTotal = ParseSymbols(InpSymbols, g_symbols);

   if(g_symbolsTotal <= 0)
   {
      Print("ERROR | No valid symbols configured in InpSymbols");
      return false;
   }

   for(int i = 0; i < g_symbolsTotal; i++)
   {
      g_states[i].symbol            = g_symbols[i];
      g_states[i].enabled           = true;
      g_states[i].lastScanBarTime   = 0;
      g_states[i].lastManageBarTime = 0;
      g_states[i].point             = 0.0;
      g_states[i].digits            = 0;
      g_states[i].bid               = 0.0;
      g_states[i].ask               = 0.0;
      g_states[i].spreadPoints      = 0.0;
      g_states[i].symbolSelected    = false;
      g_states[i].marketWatchReady  = false;
      g_states[i].tradable          = false;
      g_states[i].spreadOk          = false;
      g_states[i].lastCanProcess    = false;
      g_states[i].lastMgmtBarTime   = 0;
      
      ResetMgmtState(g_mgmt[i]);
      g_mgmt[i].symbol = g_symbols[i];

      DebugLog(StringFormat("initialized symbol[%d] = %s", i, g_states[i].symbol));
   }

   return true;
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   TesterHideIndicators(true);
   
   trade.SetExpertMagicNumber(InpMagicNumber);

   if(!InitializeSymbols())
      return(INIT_FAILED);

   DebugLog(StringFormat("EA init complete | symbols=%d | scanTF=%s",
            g_symbolsTotal,
            EnumToString(InpScanTF)));

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   DebugLog(StringFormat("EA deinit | reason=%d", reason));
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   for(int i = 0; i < g_symbolsTotal; i++)
      ProcessSymbol(g_states[i]);
}
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Get breakout entry buffer in price units                         |
//+------------------------------------------------------------------+
double GetBreakoutBufferPrice(const string symbol,
                              const double point,
                              const double atrValue)
{
   double fixedBuffer = InpBreakoutBufferPoints * point;

   if(!InpUseATRBreakoutBuffer)
      return fixedBuffer;

   if(atrValue <= 0.0)
      return fixedBuffer;

   double atrBuffer = atrValue * InpATRBreakoutBufferMult;

   return MathMax(fixedBuffer, atrBuffer);
}