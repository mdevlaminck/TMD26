//+------------------------------------------------------------------+
//|                                           ImpulseMicroGridEA.mq5 |
//|                          Short-hold mean reversion micro-grid EA |
//+------------------------------------------------------------------+
#property strict

#include <Trade/Trade.mqh>

CTrade trade;

//------------------------------------------------------------
// Inputs
//------------------------------------------------------------
input group "=== Symbols / Timeframes ===";
input string           InpSymbols                  = "EURUSD,GBPUSD,USDJPY";
input ENUM_TIMEFRAMES  InpSignalTF                 = PERIOD_M5;
input ENUM_TIMEFRAMES  InpTrendTF                  = PERIOD_M15;

input group "=== Entry Logic ===";
input int              InpATRPeriod                = 14;
input double           InpImpulseATRMult           = 1.50;   // candle body > this * ATR
input double           InpDeviationATRMult         = 1.20;   // distance from EMA20 > this * ATR
input int              InpEMAPeriod                = 20;
input int              InpTrendFastEMA             = 50;
input int              InpTrendSlowEMA             = 200;
input double           InpTrendStrengthATRMult     = 0.80;   // if strong trend, skip countertrend

input group "=== Grid Logic ===";
input bool             InpUseGrid                  = true;
input int              InpMaxLevels                = 4;      // total positions in basket max
input double           InpGridStepATRMult          = 0.70;
input double           InpLot0                     = 0.01;
input double           InpLot1                     = 0.012;
input double           InpLot2                     = 0.015;
input double           InpLot3                     = 0.018;

input group "=== Exit Logic ===";
input double           InpBasketTargetMoney        = 7.50;   // close basket at this profit in account currency
input double           InpHardStopMoney            = 20.00;  // hard stop per symbol-direction basket
input int              InpMaxHoldMinutes           = 120;
input bool             InpExitAtEMA20Touch         = true;
input bool             InpExitOnOppImpulse         = true;
input bool             InpExitAtSmallProfitOnTime  = true;

input group "=== Filters ===";
input double           InpMaxSpreadPoints          = 25;
input bool             InpUseSessionFilter         = true;
input int              InpSessionStartHour         = 7;      // server time
input int              InpSessionEndHour           = 22;     // server time
input bool             InpOneBasketPerDirection    = true;
input bool             InpAllowBuy                 = true;
input bool             InpAllowSell                = true;

input group "=== Execution ===";
input ulong            InpMagic                    = 26040301;
input int              InpSlippagePoints           = 20;
input bool             InpDebug                    = true;

//------------------------------------------------------------
// Types
//------------------------------------------------------------
enum BasketDir
{
   BASKET_NONE = 0,
   BASKET_BUY  = 1,
   BASKET_SELL = -1
};

struct SymbolState
{
   string   symbol;
   datetime lastBarTime;
};

struct BasketStats
{
   bool      exists;
   int       dir;
   int       count;
   double    lots;
   double    avgPrice;
   double    profit;
   datetime  firstOpenTime;
   double    farthestPrice;     // worst excursion price in grid direction
   ulong     tickets[16];
   int       ticketCount;
};

//------------------------------------------------------------
// Globals
//------------------------------------------------------------
string      g_symbols[];
SymbolState g_states[];
int         g_symbolCount = 0;

//------------------------------------------------------------
// Utility
//------------------------------------------------------------
string Trim(const string s)
{
   string t = s;
   StringTrimLeft(t);
   StringTrimRight(t);
   return t;
}

bool SplitSymbols(const string csv, string &outArr[])
{
   string parts[];
   int n = StringSplit(csv, ',', parts);
   if(n <= 0)
      return false;

   ArrayResize(outArr, 0);

   for(int i = 0; i < n; i++)
   {
      string sym = Trim(parts[i]);
      if(sym == "")
         continue;
      int sz = ArraySize(outArr);
      ArrayResize(outArr, sz + 1);
      outArr[sz] = sym;
   }

   return (ArraySize(outArr) > 0);
}

double GetPointValue(const string symbol)
{
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   return point;
}

double GetSpreadPoints(const string symbol)
{
   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   double pt  = GetPointValue(symbol);
   if(pt <= 0.0)
      return 999999.0;
   return (ask - bid) / pt;
}

bool IsSessionAllowed()
{
   if(!InpUseSessionFilter)
      return true;

   MqlDateTime tm;
   TimeToStruct(TimeCurrent(), tm);

   if(InpSessionStartHour <= InpSessionEndHour)
      return (tm.hour >= InpSessionStartHour && tm.hour < InpSessionEndHour);

   return (tm.hour >= InpSessionStartHour || tm.hour < InpSessionEndHour);
}

double NormalizeLots(const string symbol, double lots)
{
   double minLot  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double stepLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);

   if(stepLot <= 0.0)
      stepLot = 0.01;

   lots = MathMax(minLot, MathMin(maxLot, lots));
   lots = MathFloor(lots / stepLot) * stepLot;
   return NormalizeDouble(lots, 2);
}

double GetGridLotByLevel(int level)
{
   switch(level)
   {
      case 0: return InpLot0;
      case 1: return InpLot1;
      case 2: return InpLot2;
      default: return InpLot3;
   }
}

bool IsNewBar(const string symbol, ENUM_TIMEFRAMES tf, datetime &lastBarTime)
{
   datetime t = iTime(symbol, tf, 0);
   if(t == 0)
      return false;

   if(t != lastBarTime)
   {
      lastBarTime = t;
      return true;
   }
   return false;
}

//------------------------------------------------------------
// Indicators
//------------------------------------------------------------
double GetATR(const string symbol, ENUM_TIMEFRAMES tf, int period, int shift)
{
   int h = iATR(symbol, tf, period);
   if(h == INVALID_HANDLE)
      return 0.0;

   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(h, 0, shift, 1, buf) < 1)
   {
      IndicatorRelease(h);
      return 0.0;
   }
   IndicatorRelease(h);
   return buf[0];
}

double GetEMA(const string symbol, ENUM_TIMEFRAMES tf, int period, int shift)
{
   int h = iMA(symbol, tf, period, 0, MODE_EMA, PRICE_CLOSE);
   if(h == INVALID_HANDLE)
      return 0.0;

   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(h, 0, shift, 1, buf) < 1)
   {
      IndicatorRelease(h);
      return 0.0;
   }
   IndicatorRelease(h);
   return buf[0];
}

bool GetRates2(const string symbol, ENUM_TIMEFRAMES tf, MqlRates &r1, MqlRates &r2)
{
   MqlRates rr[];
   ArraySetAsSeries(rr, true);
   if(CopyRates(symbol, tf, 1, 2, rr) < 2)
      return false;

   r1 = rr[0]; // just closed bar
   r2 = rr[1]; // previous bar
   return true;
}

//------------------------------------------------------------
// Basket scanning
//------------------------------------------------------------
bool LoadBasketStats(const string symbol, int dir, BasketStats &bs)
{
   bs.exists         = false;
   bs.dir            = dir;
   bs.count          = 0;
   bs.lots           = 0.0;
   bs.avgPrice       = 0.0;
   bs.profit         = 0.0;
   bs.firstOpenTime  = 0;
   bs.farthestPrice  = 0.0;
   bs.ticketCount    = 0;
   ArrayInitialize(bs.tickets, 0);

   double weighted = 0.0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;

      if(!PositionSelectByTicket(ticket))
         continue;

      string psym = PositionGetString(POSITION_SYMBOL);
      if(psym != symbol)
         continue;

      long magic = PositionGetInteger(POSITION_MAGIC);
      if((ulong)magic != InpMagic)
         continue;

      long ptype = PositionGetInteger(POSITION_TYPE);
      if(dir == BASKET_BUY && ptype != POSITION_TYPE_BUY)
         continue;
      if(dir == BASKET_SELL && ptype != POSITION_TYPE_SELL)
         continue;

      double vol       = PositionGetDouble(POSITION_VOLUME);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double profit    = PositionGetDouble(POSITION_PROFIT);
      datetime opent   = (datetime)PositionGetInteger(POSITION_TIME);

      bs.exists = true;
      bs.count++;
      bs.lots   += vol;
      weighted  += vol * openPrice;
      bs.profit += profit;

      if(bs.firstOpenTime == 0 || opent < bs.firstOpenTime)
         bs.firstOpenTime = opent;

      if(bs.ticketCount < 16)
         bs.tickets[bs.ticketCount++] = ticket;

      if(dir == BASKET_BUY)
      {
         if(bs.count == 1 || openPrice > bs.farthestPrice)
            bs.farthestPrice = openPrice;
      }
      else if(dir == BASKET_SELL)
      {
         if(bs.count == 1 || openPrice < bs.farthestPrice)
            bs.farthestPrice = openPrice;
      }
   }

   if(bs.lots > 0.0)
      bs.avgPrice = weighted / bs.lots;

   return bs.exists;
}

bool CloseBasket(const BasketStats &bs)
{
   bool ok = true;

   for(int i = bs.ticketCount - 1; i >= 0; i--)
   {
      ulong ticket = bs.tickets[i];
      if(ticket == 0)
         continue;

      if(!PositionSelectByTicket(ticket))
         continue;

      if(!trade.PositionClose(ticket, InpSlippagePoints))
         ok = false;
   }

   return ok;
}

//------------------------------------------------------------
// Trend / Entry logic
//------------------------------------------------------------
bool IsStrongTrendAgainst(const string symbol, int entryDir)
{
   double emaFast = GetEMA(symbol, InpTrendTF, InpTrendFastEMA, 1);
   double emaSlow = GetEMA(symbol, InpTrendTF, InpTrendSlowEMA, 1);
   double atr     = GetATR(symbol, InpTrendTF, InpATRPeriod, 1);
   double close1  = iClose(symbol, InpTrendTF, 1);

   if(emaFast == 0.0 || emaSlow == 0.0 || atr == 0.0)
      return false;

   double sep = MathAbs(emaFast - emaSlow);

   bool strongUp   = (emaFast > emaSlow && close1 > emaFast && sep > atr * InpTrendStrengthATRMult);
   bool strongDown = (emaFast < emaSlow && close1 < emaFast && sep > atr * InpTrendStrengthATRMult);

   if(entryDir == BASKET_SELL && strongUp)
      return true;
   if(entryDir == BASKET_BUY && strongDown)
      return true;

   return false;
}

bool DetectImpulseSignal(const string symbol, int &signalDir, string &reason)
{
   signalDir = BASKET_NONE;
   reason    = "";

   MqlRates r1, r2;
   if(!GetRates2(symbol, InpSignalTF, r1, r2))
      return false;

   double atr = GetATR(symbol, InpSignalTF, InpATRPeriod, 1);
   if(atr <= 0.0)
      return false;

   double ema20 = GetEMA(symbol, InpSignalTF, InpEMAPeriod, 1);
   if(ema20 <= 0.0)
      return false;

   double body      = MathAbs(r1.close - r1.open);
   double dev       = MathAbs(r1.close - ema20);
   bool   impulse   = (body > atr * InpImpulseATRMult);
   bool   extended  = (dev  > atr * InpDeviationATRMult);

   if(!impulse || !extended)
      return false;

   if(r1.close > r1.open)
   {
      signalDir = BASKET_SELL;
      reason    = "bull impulse overextension";
   }
   else if(r1.close < r1.open)
   {
      signalDir = BASKET_BUY;
      reason    = "bear impulse overextension";
   }
   else
   {
      return false;
   }

   if(IsStrongTrendAgainst(symbol, signalDir))
   {
      signalDir = BASKET_NONE;
      reason    = "blocked by strong higher-TF trend";
      return false;
   }

   return true;
}

//------------------------------------------------------------
// Grid logic
//------------------------------------------------------------
bool ShouldAddGridLevel(const string symbol, const BasketStats &bs)
{
   if(!InpUseGrid)
      return false;

   if(!bs.exists)
      return false;

   if(bs.count >= InpMaxLevels)
      return false;

   double atr = GetATR(symbol, InpSignalTF, InpATRPeriod, 1);
   if(atr <= 0.0)
      return false;

   double step = atr * InpGridStepATRMult;
   double bid  = SymbolInfoDouble(symbol, SYMBOL_BID);
   double ask  = SymbolInfoDouble(symbol, SYMBOL_ASK);

   MqlRates r1, r2;
   if(!GetRates2(symbol, InpSignalTF, r1, r2))
      return false;

   double body = MathAbs(r1.close - r1.open);
   bool strongStill = (body > atr * InpImpulseATRMult);

   if(strongStill)
      return false; // do not add while impulse still active

   if(bs.dir == BASKET_BUY)
   {
      // add only if price has moved lower by full step from avg
      if((bs.avgPrice - bid) >= step)
         return true;
   }
   else if(bs.dir == BASKET_SELL)
   {
      // add only if price has moved higher by full step from avg
      if((ask - bs.avgPrice) >= step)
         return true;
   }

   return false;
}

bool OpenPosition(const string symbol, int dir, double lots, const string comment)
{
   lots = NormalizeLots(symbol, lots);
   if(lots <= 0.0)
      return false;

   trade.SetExpertMagicNumber((long)InpMagic);
   trade.SetDeviationInPoints(InpSlippagePoints);

   bool ok = false;
   if(dir == BASKET_BUY)
      ok = trade.Buy(lots, symbol, 0.0, 0.0, 0.0, comment);
   else if(dir == BASKET_SELL)
      ok = trade.Sell(lots, symbol, 0.0, 0.0, 0.0, comment);

   return ok;
}

//------------------------------------------------------------
// Exit logic
//------------------------------------------------------------
bool HasOppositeImpulse(const string symbol, int basketDir)
{
   int sig;
   string reason;
   if(!DetectImpulseSignal(symbol, sig, reason))
      return false;

   return (sig == -basketDir);
}

bool ShouldExitBasket(const string symbol, const BasketStats &bs, string &why)
{
   why = "";

   if(!bs.exists)
      return false;

   if(bs.profit >= InpBasketTargetMoney)
   {
      why = "basket target";
      return true;
   }

   if(bs.profit <= -InpHardStopMoney)
   {
      why = "hard stop";
      return true;
   }

   int heldMin = (int)((TimeCurrent() - bs.firstOpenTime) / 60);
   if(heldMin >= InpMaxHoldMinutes)
   {
      if(InpExitAtSmallProfitOnTime)
      {
         if(bs.profit >= 0.0)
         {
            why = "time exit at >= 0";
            return true;
         }
      }
      else
      {
         why = "time exit";
         return true;
      }
   }

   if(InpExitAtEMA20Touch)
   {
      double ema20 = GetEMA(symbol, InpSignalTF, InpEMAPeriod, 0);
      double bid   = SymbolInfoDouble(symbol, SYMBOL_BID);
      double ask   = SymbolInfoDouble(symbol, SYMBOL_ASK);

      if(bs.dir == BASKET_BUY && bid >= ema20 && bs.profit > 0.0)
      {
         why = "ema20 touch";
         return true;
      }

      if(bs.dir == BASKET_SELL && ask <= ema20 && bs.profit > 0.0)
      {
         why = "ema20 touch";
         return true;
      }
   }

   if(InpExitOnOppImpulse)
   {
      if(HasOppositeImpulse(symbol, bs.dir) && bs.profit > 0.0)
      {
         why = "opposite impulse";
         return true;
      }
   }

   return false;
}

//------------------------------------------------------------
// Per-symbol process
//------------------------------------------------------------
void ProcessExistingBasket(const string symbol, int dir)
{
   BasketStats bs;
   if(!LoadBasketStats(symbol, dir, bs))
      return;

   string why;
   if(ShouldExitBasket(symbol, bs, why))
   {
      if(InpDebug)
         Print("EXIT | ", symbol, " | dir=", dir, " | reason=", why,
               " | count=", bs.count, " | profit=", DoubleToString(bs.profit, 2));

      CloseBasket(bs);
      return;
   }

   if(ShouldAddGridLevel(symbol, bs))
   {
      double lots = GetGridLotByLevel(bs.count); // next level
      if(OpenPosition(symbol, dir, lots, "GridAdd"))
      {
         if(InpDebug)
            Print("GRID ADD | ", symbol, " | dir=", dir, " | level=", bs.count + 1,
                  " | lots=", DoubleToString(lots, 2));
      }
   }
}

void ProcessNewEntry(const string symbol)
{
   if(GetSpreadPoints(symbol) > InpMaxSpreadPoints)
      return;

   int signalDir = BASKET_NONE;
   string reason = "";

   if(!DetectImpulseSignal(symbol, signalDir, reason))
      return;

   if(signalDir == BASKET_BUY && !InpAllowBuy)
      return;
   if(signalDir == BASKET_SELL && !InpAllowSell)
      return;

   if(InpOneBasketPerDirection)
   {
      BasketStats sameDir;
      if(LoadBasketStats(symbol, signalDir, sameDir))
         return;
   }

   double lots = GetGridLotByLevel(0);
   if(OpenPosition(symbol, signalDir, lots, "ImpulseEntry"))
   {
      if(InpDebug)
         Print("ENTRY | ", symbol, " | dir=", signalDir, " | ", reason,
               " | lots=", DoubleToString(lots, 2));
   }
}

//------------------------------------------------------------
// Init / Tick
//------------------------------------------------------------
int OnInit()
{
   if(!SplitSymbols(InpSymbols, g_symbols))
   {
      Print("No symbols configured.");
      return INIT_FAILED;
   }

   g_symbolCount = ArraySize(g_symbols);
   ArrayResize(g_states, g_symbolCount);

   for(int i = 0; i < g_symbolCount; i++)
   {
      g_states[i].symbol      = g_symbols[i];
      g_states[i].lastBarTime = 0;

      if(!SymbolSelect(g_symbols[i], true))
      {
         Print("Failed to select symbol: ", g_symbols[i]);
      }
   }

   trade.SetExpertMagicNumber((long)InpMagic);
   trade.SetDeviationInPoints(InpSlippagePoints);

   Print("ImpulseMicroGridEA initialized. Symbols=", InpSymbols);
   return INIT_SUCCEEDED;
}

void OnTick()
{
   if(!IsSessionAllowed())
      return;

   for(int i = 0; i < g_symbolCount; i++)
   {
      string symbol = g_states[i].symbol;

      // Always manage open baskets every tick
      ProcessExistingBasket(symbol, BASKET_BUY);
      ProcessExistingBasket(symbol, BASKET_SELL);

      // New entries only once per fresh signal bar
      if(IsNewBar(symbol, InpSignalTF, g_states[i].lastBarTime))
      {
         ProcessNewEntry(symbol);
      }
   }
}