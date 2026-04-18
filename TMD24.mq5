//+------------------------------------------------------------------+
//|                                      PA_Volume_SR_Institutional  |
//|                               Base skeleton for phased build     |
//+------------------------------------------------------------------+
#property strict

#include <Trade/Trade.mqh>

CTrade trade;

//==================================================================//
// ENUMS
//==================================================================//
enum ENUM_LOG_LEVEL
{
   LOG_NONE = 0,
   LOG_ERROR,
   LOG_WARN,
   LOG_INFO,
   LOG_DEBUG
};

enum ENUM_MARKET_REGIME
{
   REGIME_NONE = 0,
   REGIME_RANGE,
   REGIME_TREND_UP,
   REGIME_TREND_DOWN
};

enum ENUM_SIGNAL_TYPE
{
   SIG_NONE = 0,
   SIG_SWEEP_REVERSAL_BUY,
   SIG_SWEEP_REVERSAL_SELL,
   SIG_BREAKOUT_CONT_BUY,
   SIG_BREAKOUT_CONT_SELL
};

enum ENUM_BASKET_DIRECTION
{
   BASKET_DIR_NONE = 0,
   BASKET_DIR_BUY = 1,
   BASKET_DIR_SELL = -1
};

enum ENUM_ZONE_TYPE
{
   ZONE_NONE = 0,
   ZONE_SUPPORT,
   ZONE_RESISTANCE
};

//==================================================================//
// INPUTS
//==================================================================//
input group "=== General ===";
input ulong            InpMagicNumber                = 26040301;
input ENUM_LOG_LEVEL   InpLogLevel                   = LOG_INFO;
input bool             InpProcessOncePerBar          = true;
input int              InpMaxSpreadPoints            = 30;
input bool             InpAllowBuy                   = true;
input bool             InpAllowSell                  = true;

input group "=== Risk Management ===";
input bool             InpUseDynamicLot              = true;
input double           InpFixedLot                   = 0.10;
input double           InpRiskPerBasketPct           = 0.50;
input double           InpMaxDailyLossPct            = 2.00;
input double           InpMaxWeeklyLossPct           = 4.00;
input double           InpMaxEquityDrawdownPct       = 8.00;
input int              InpMaxOpenBaskets            = 2;
input int              InpMaxPositionsPerBasket      = 4;

input group "=== Grid / Basket ===";
input bool             InpEnableGrid                 = true;
input double           InpGridATRMultiplier          = 0.80;
input double           InpGridLotMultiplier          = 1.10;
input bool             InpUseTrailingBasketSL        = true;
input double           InpBasketTrailATRMultiplier   = 1.00;
input bool             InpGridAddsOnlyOnNewBar       = true;
input bool             InpGridRequireSameDirectionSignal = true;
input bool             InpGridRequireBetterPrice     = true;
input bool             InpGridAllowSweepAdds         = true;
input bool             InpGridAllowBreakoutAdds      = true;
input int              InpMaxAddsPerBasket           = 4;
input double           InpGridMinRemainingRiskPct    = 0.10;
input double           InpGridMaxLotPerAdd           = 0.50;

input group "=== Structure / Zones ===";
input int              InpSwingLeft                  = 3;
input int              InpSwingRight                 = 3;
input int              InpMaxZones                   = 20;
input int              InpZoneLookbackBars           = 300;
input int              InpZoneMinTouches             = 2;
input double           InpZoneATRWidthMultiplier     = 0.25;
input double           InpZoneMergeATRMultiplier     = 0.20;
input double           InpZoneBreakATRMultiplier     = 0.15;
input int              InpRegimeFastMAPeriod         = 20;
input int              InpRegimeSlowMAPeriod         = 50;
input double           InpRegimeMinSeparationATR     = 0.15;

input group "=== Volume / Price Action ===";
input int              InpVolumeLookback             = 20;
input double           InpVolumeSpikeFactor          = 1.50;
input double           InpMinBreakoutBodyATR         = 0.50;
input double           InpMinSweepPenetrationATR     = 0.20;
input double           InpMinSweepRejectWickATR      = 0.15;
input double           InpMaxSweepBodyATR            = 0.90;
input bool             InpRequireSweepVolumeSpike    = true;
input bool             InpRequireSweepStrongClose    = true;
input bool             InpUseRegimeFilterForSweep    = true;
input bool             InpAllowRangeSweeps           = true;
input double           InpSweepSL_BufferATR          = 0.1;
input double           InpSweepTP_ATR_Multiplier     = 1.80;

input bool             InpRequireBreakoutVolumeSpike = true;
input bool             InpUseRegimeFilterForBreakout = true;
input bool             InpAllowRangeBreakouts        = false;
input bool             InpRequireBreakoutStrongClose = true;
input bool             InpRequireBreakoutRetest      = false;
input int              InpBreakoutRetestLookbackBars = 3;
input double           InpBreakoutRetestToleranceATR = 0.10;
input double           InpBreakoutSL_BufferATR       = 0.12;
input double           InpBreakoutTP_ATR_Multiplier  = 2.20;
input double           InpMaxBreakoutOppWickATR      = 0.35;

input group "=== Trade Management ===";
input double           InpInitialSL_ATR_Multiplier   = 1.20;
input double           InpInitialTP_ATR_Multiplier   = 2.00;
input bool             InpUseBreakEven               = true;
input double           InpBreakEvenAtR               = 1.00;
input bool             InpUseTrailingStop            = true;
input double           InpTrailATRMultiplier         = 1.00;
input bool             InpUseStaleExit               = true;
input int              InpMaxBarsInTrade             = 24;
input bool             InpUseFailedPatternExit       = true;
input bool             InpUseOppositeSignalExit      = false;
input double           InpFailedBreakoutExitATR      = 0.10;
input double           InpFailedSweepExitATR         = 0.10;
input double           InpBreakEvenLockPoints        = 5.0;

input group "=== Session Filters ===";
input bool             InpBlockMondayEarly           = true;
input int              InpMondayBlockHour            = 5;
input bool             InpBlockFridayLate            = true;
input int              InpFridayBlockHour            = 19;
input bool             InpBlockJuly                  = false;
input bool             InpBlockYearEnd               = false; // 20 Dec -> 10 Jan

//==================================================================//
// STRUCTS
//==================================================================//
struct ZoneInfo
{
   bool              valid;
   ENUM_ZONE_TYPE    type;
   datetime          createdTime;
   datetime          lastTouchTime;
   double            upper;
   double            lower;
   int               touches;
   double            strength;
   bool              broken;
};

struct SignalInfo
{
   bool              valid;
   ENUM_SIGNAL_TYPE  type;
   string            symbol;
   ENUM_BASKET_DIRECTION direction;
   double            entryPrice;
   double            stopLoss;
   double            takeProfit;
   double            invalidationPrice;
   double            confidence;
   string            reason;
};

struct BasketState
{
   bool                   active;
   string                 symbol;
   ENUM_BASKET_DIRECTION  direction;
   int                    positionCount;
   double                 totalLots;
   double                 weightedEntry;
   double                 basketSL;
   double                 basketTP;
   double                 basketProfit;
   datetime               openedTime;
   ENUM_SIGNAL_TYPE       sourceSignal;
   double                 initialRiskPrice;
   double                 invalidationPrice;
   bool                   breakEvenDone;
   datetime               lastEntryTime;
   double                 lastEntryPrice;
   double                 lastEntryLots;
   int                    addCount;
};

struct SymbolContext
{
   string            symbol;
   double            point;
   int               digits;
   double            tickSize;
   double            tickValue;
   double            lotStep;
   double            minLot;
   double            maxLot;
   int               stopsLevel;
   int               freezeLevel;
   double            atr;
   double            spreadPoints;
   ENUM_MARKET_REGIME regime;
};

struct DailyRiskState
{
   datetime          dayStart;
   double            startBalance;
   double            startEquity;
   bool              dailyLock;
};

struct WeeklyRiskState
{
   datetime          weekStart;
   double            startBalance;
   double            startEquity;
   bool              weeklyLock;
};

//==================================================================//
// GLOBALS
//==================================================================//
datetime         g_lastBarTime       = 0;
DailyRiskState   g_dailyRisk;
WeeklyRiskState  g_weeklyRisk;

BasketState      g_basket;
SymbolContext    g_ctx;
ZoneInfo         g_zones[200];

ENUM_SIGNAL_TYPE g_lastEntrySignalType   = SIG_NONE;
double           g_lastEntryInvalidation = 0.0;
double           g_lastEntryInitialRisk  = 0.0;

//==================================================================//
// LOGGING
//==================================================================//
string LogLevelToString(ENUM_LOG_LEVEL lvl)
{
   switch(lvl)
   {
      case LOG_ERROR: return "ERROR";
      case LOG_WARN:  return "WARN";
      case LOG_INFO:  return "INFO";
      case LOG_DEBUG: return "DEBUG";
      default:        return "NONE";
   }
}

void LogPrint(ENUM_LOG_LEVEL lvl, const string msg)
{
   if((int)lvl > (int)InpLogLevel || lvl == LOG_NONE)
      return;

   Print("PAEA | ", LogLevelToString(lvl), " | ", _Symbol, " | ", msg);
}

//==================================================================//
// BASIC HELPERS
//==================================================================//
double NormalizePrice(const double price)
{
   return NormalizeDouble(price, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
}

double NormalizeVolumeToStep(const double lots)
{
   double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

   if(step <= 0.0)
      return lots;

   double v = MathFloor(lots / step) * step;
   if(v < minLot) v = minLot;
   if(v > maxLot) v = maxLot;

   return NormalizeDouble(v, 2);
}

bool IsNewBar()
{
   datetime t = iTime(_Symbol, _Period, 0);
   if(t <= 0)
      return false;

   if(t != g_lastBarTime)
   {
      g_lastBarTime = t;
      return true;
   }
   return false;
}

double GetSpreadPoints()
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double pt  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(pt <= 0.0)
      return 0.0;

   return (ask - bid) / pt;
}

bool IsSpreadOK()
{
   double spread = GetSpreadPoints();
   if(spread > InpMaxSpreadPoints)
   {
      LogPrint(LOG_DEBUG, "Spread blocked. Spread=" + DoubleToString(spread, 1));
      return false;
   }
   return true;
}

bool IsBrokerTradeWindow()
{
   MqlDateTime broker;
   TimeToStruct(TimeCurrent(), broker);

   if(InpBlockMondayEarly && broker.day_of_week == 1 && broker.hour < InpMondayBlockHour)
      return false;

   if(InpBlockFridayLate && broker.day_of_week == 5 && broker.hour >= InpFridayBlockHour)
      return false;

   if(InpBlockJuly && broker.mon == 7)
      return false;

   if(InpBlockYearEnd)
   {
      if((broker.mon == 12 && broker.day >= 20) || (broker.mon == 1 && broker.day <= 10))
         return false;
   }

   return true;
}

bool RefreshSymbolContext(SymbolContext &ctx)
{
   ctx.symbol      = _Symbol;
   ctx.point       = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   ctx.digits      = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   ctx.tickSize    = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   ctx.tickValue   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   ctx.lotStep     = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   ctx.minLot      = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   ctx.maxLot      = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   ctx.stopsLevel  = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   ctx.freezeLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   ctx.spreadPoints= GetSpreadPoints();
   ctx.atr = GetATRValue(_Symbol, _Period, 14, 1);
   ctx.regime      = REGIME_NONE;

   if(ctx.point <= 0.0 || ctx.minLot <= 0.0)
   {
      LogPrint(LOG_ERROR, "Invalid symbol context");
      return false;
   }

   return true;
}

double GetATRValue(const string symbol, const ENUM_TIMEFRAMES tf, const int period, const int shift)
{
   int handle = iATR(symbol, tf, period);
   if(handle == INVALID_HANDLE)
      return 0.0;

   double buffer[];
   ArraySetAsSeries(buffer, true);

   if(CopyBuffer(handle, 0, shift, 1, buffer) <= 0)
   {
      IndicatorRelease(handle);
      return 0.0;
   }

   double value = buffer[0];
   IndicatorRelease(handle);
   return value;
}
double GetMAValue(const string symbol,
                  const ENUM_TIMEFRAMES tf,
                  const int period,
                  const int maShift,
                  const ENUM_MA_METHOD maMethod,
                  const ENUM_APPLIED_PRICE appliedPrice,
                  const int shift)
{
   int handle = iMA(symbol, tf, period, maShift, maMethod, appliedPrice);
   if(handle == INVALID_HANDLE)
      return 0.0;

   double buffer[];
   ArraySetAsSeries(buffer, true);

   if(CopyBuffer(handle, 0, shift, 1, buffer) <= 0)
   {
      IndicatorRelease(handle);
      return 0.0;
   }

   double value = buffer[0];
   IndicatorRelease(handle);
   return value;
}
//==================================================================//
// RISK HELPERS
//==================================================================//
datetime GetDayStart(datetime t)
{
   MqlDateTime x;
   TimeToStruct(t, x);
   x.hour = 0;
   x.min  = 0;
   x.sec  = 0;
   return StructToTime(x);
}

datetime GetWeekStart(datetime t)
{
   MqlDateTime x;
   TimeToStruct(t, x);

   int shift = x.day_of_week;
   if(shift < 0) shift = 0;

   datetime dayStart = GetDayStart(t);
   return dayStart - shift * 86400;
}

void RefreshRiskAnchors()
{
   datetime now = TimeCurrent();
   datetime ds  = GetDayStart(now);
   datetime ws  = GetWeekStart(now);

   if(g_dailyRisk.dayStart != ds)
   {
      g_dailyRisk.dayStart     = ds;
      g_dailyRisk.startBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      g_dailyRisk.startEquity  = AccountInfoDouble(ACCOUNT_EQUITY);
      g_dailyRisk.dailyLock    = false;
      LogPrint(LOG_INFO, "Daily risk anchor reset");
   }

   if(g_weeklyRisk.weekStart != ws)
   {
      g_weeklyRisk.weekStart     = ws;
      g_weeklyRisk.startBalance  = AccountInfoDouble(ACCOUNT_BALANCE);
      g_weeklyRisk.startEquity   = AccountInfoDouble(ACCOUNT_EQUITY);
      g_weeklyRisk.weeklyLock    = false;
      LogPrint(LOG_INFO, "Weekly risk anchor reset");
   }
}

double GetDailyDrawdownPct()
{
   if(g_dailyRisk.startEquity <= 0.0)
      return 0.0;

   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   return 100.0 * (g_dailyRisk.startEquity - eq) / g_dailyRisk.startEquity;
}

double GetWeeklyDrawdownPct()
{
   if(g_weeklyRisk.startEquity <= 0.0)
      return 0.0;

   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   return 100.0 * (g_weeklyRisk.startEquity - eq) / g_weeklyRisk.startEquity;
}

double GetEquityDrawdownPctVsBalance()
{
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double eq  = AccountInfoDouble(ACCOUNT_EQUITY);
   if(bal <= 0.0)
      return 0.0;

   return 100.0 * (bal - eq) / bal;
}

bool IsRiskLocked()
{
   RefreshRiskAnchors();

   double ddDaily  = GetDailyDrawdownPct();
   double ddWeekly = GetWeeklyDrawdownPct();
   double ddEq     = GetEquityDrawdownPctVsBalance();

   if(ddDaily >= InpMaxDailyLossPct)
   {
      g_dailyRisk.dailyLock = true;
      LogPrint(LOG_WARN, "Daily lock active");
   }

   if(ddWeekly >= InpMaxWeeklyLossPct)
   {
      g_weeklyRisk.weeklyLock = true;
      LogPrint(LOG_WARN, "Weekly lock active");
   }

   if(ddEq >= InpMaxEquityDrawdownPct)
   {
      LogPrint(LOG_WARN, "Equity DD lock active");
      return true;
   }

   return g_dailyRisk.dailyLock || g_weeklyRisk.weeklyLock;
}

double CalcLotByRisk(const double stopDistancePrice)
{
   if(!InpUseDynamicLot)
      return NormalizeVolumeToStep(InpFixedLot);

   if(stopDistancePrice <= 0.0)
      return NormalizeVolumeToStep(InpFixedLot);

   double balance    = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney  = balance * InpRiskPerBasketPct / 100.0;
   if(riskMoney <= 0.0)
      return NormalizeVolumeToStep(InpFixedLot);

   double tickSize   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);

   if(tickSize <= 0.0 || tickValue <= 0.0)
      return NormalizeVolumeToStep(InpFixedLot);

   double moneyPerLot = (stopDistancePrice / tickSize) * tickValue;
   if(moneyPerLot <= 0.0)
      return NormalizeVolumeToStep(InpFixedLot);

   double lots = riskMoney / moneyPerLot;
   return NormalizeVolumeToStep(lots);
}

//==================================================================//
// POSITION / BASKET
//==================================================================//
void ResetBasket(BasketState &b)
{
   b.active             = false;
   b.symbol             = "";
   b.direction          = BASKET_DIR_NONE;
   b.positionCount      = 0;
   b.totalLots          = 0.0;
   b.weightedEntry      = 0.0;
   b.basketSL           = 0.0;
   b.basketTP           = 0.0;
   b.basketProfit       = 0.0;
   b.openedTime         = 0;
   b.sourceSignal       = SIG_NONE;
   b.initialRiskPrice   = 0.0;
   b.invalidationPrice  = 0.0;
   b.breakEvenDone      = false;
   b.lastEntryTime      = 0;
   b.lastEntryPrice     = 0.0;
   b.lastEntryLots      = 0.0;
   b.addCount           = 0;
}

bool RefreshBasketState(BasketState &b)
{
   ResetBasket(b);

   double totalLotsWeightedPrice = 0.0;
   datetime latestTime = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;

      if(!PositionSelectByTicket(ticket))
         continue;

      string sym = PositionGetString(POSITION_SYMBOL);
      long magic = PositionGetInteger(POSITION_MAGIC);
      if(sym != _Symbol || (ulong)magic != InpMagicNumber)
         continue;

      long posType     = PositionGetInteger(POSITION_TYPE);
      double volume    = PositionGetDouble(POSITION_VOLUME);
      double open      = PositionGetDouble(POSITION_PRICE_OPEN);
      double profit    = PositionGetDouble(POSITION_PROFIT);
      double sl        = PositionGetDouble(POSITION_SL);
      double tp        = PositionGetDouble(POSITION_TP);
      datetime posTime = (datetime)PositionGetInteger(POSITION_TIME);

      if(!b.active)
      {
         b.active            = true;
         b.symbol            = sym;
         b.openedTime        = posTime;
         b.direction         = (posType == POSITION_TYPE_BUY ? BASKET_DIR_BUY : BASKET_DIR_SELL);
         b.sourceSignal      = g_lastEntrySignalType;
         b.invalidationPrice = g_lastEntryInvalidation;
         b.initialRiskPrice  = g_lastEntryInitialRisk;
         b.breakEvenDone     = false;
         b.basketSL          = sl;
         b.basketTP          = tp;
      }
      else
      {
         if(posTime < b.openedTime)
            b.openedTime = posTime;
      }

      if(posTime >= latestTime)
      {
         latestTime        = posTime;
         b.lastEntryTime   = posTime;
         b.lastEntryPrice  = open;
         b.lastEntryLots   = volume;
      }

      b.positionCount++;
      b.totalLots += volume;
      b.basketProfit += profit;
      totalLotsWeightedPrice += volume * open;

      if(b.direction == BASKET_DIR_BUY)
      {
         if(sl > 0.0 && (b.basketSL == 0.0 || sl < b.basketSL))
            b.basketSL = sl;
         if(tp > 0.0 && tp > b.basketTP)
            b.basketTP = tp;
      }
      else if(b.direction == BASKET_DIR_SELL)
      {
         if(sl > 0.0 && (b.basketSL == 0.0 || sl > b.basketSL))
            b.basketSL = sl;
         if(tp > 0.0 && (b.basketTP == 0.0 || tp < b.basketTP))
            b.basketTP = tp;
      }
   }

   if(b.active && b.totalLots > 0.0)
      b.weightedEntry = totalLotsWeightedPrice / b.totalLots;

   if(b.active)
   {
      b.addCount = MathMax(0, b.positionCount - 1);
   }

   if(b.active && b.initialRiskPrice <= 0.0 && b.basketSL > 0.0)
      b.initialRiskPrice = MathAbs(b.weightedEntry - b.basketSL);

   if(b.active && InpUseBreakEven && b.initialRiskPrice > 0.0)
   {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double currentPrice = (b.direction == BASKET_DIR_BUY ? bid : ask);

      double move = (b.direction == BASKET_DIR_BUY
                     ? currentPrice - b.weightedEntry
                     : b.weightedEntry - currentPrice);

      if(move >= b.initialRiskPrice * InpBreakEvenAtR)
         b.breakEvenDone = true;
   }

   return b.active;
}

//==================================================================//
// MARKET STRUCTURE / ZONES HELPERS
//==================================================================//
void ResetZones()
{
   for(int i = 0; i < ArraySize(g_zones); i++)
   {
      g_zones[i].valid         = false;
      g_zones[i].type          = ZONE_NONE;
      g_zones[i].createdTime   = 0;
      g_zones[i].lastTouchTime = 0;
      g_zones[i].upper         = 0.0;
      g_zones[i].lower         = 0.0;
      g_zones[i].touches       = 0;
      g_zones[i].strength      = 0.0;
      g_zones[i].broken        = false;
   }
}

int GetValidZoneCount()
{
   int count = 0;
   for(int i = 0; i < ArraySize(g_zones); i++)
   {
      if(g_zones[i].valid)
         count++;
   }
   return count;
}

bool IsSwingHigh(const int shift)
{
   if(shift < InpSwingRight || shift + InpSwingLeft >= Bars(_Symbol, _Period))
      return false;

   double h = iHigh(_Symbol, _Period, shift);
   if(h <= 0.0)
      return false;

   for(int i = 1; i <= InpSwingLeft; i++)
   {
      if(iHigh(_Symbol, _Period, shift + i) >= h)
         return false;
   }

   for(int i = 1; i <= InpSwingRight; i++)
   {
      if(iHigh(_Symbol, _Period, shift - i) > h)
         return false;
   }

   return true;
}

bool IsSwingLow(const int shift)
{
   if(shift < InpSwingRight || shift + InpSwingLeft >= Bars(_Symbol, _Period))
      return false;

   double l = iLow(_Symbol, _Period, shift);
   if(l <= 0.0)
      return false;

   for(int i = 1; i <= InpSwingLeft; i++)
   {
      if(iLow(_Symbol, _Period, shift + i) <= l)
         return false;
   }

   for(int i = 1; i <= InpSwingRight; i++)
   {
      if(iLow(_Symbol, _Period, shift - i) < l)
         return false;
   }

   return true;
}

double GetZoneMidPrice(const ZoneInfo &z)
{
   return 0.5 * (z.upper + z.lower);
}

double GetZoneWidthPrice()
{
   double atr = g_ctx.atr;
   if(atr <= 0.0)
      atr = GetATRValue(_Symbol, _Period, 14, 1);

   if(atr <= 0.0)
      atr = 10.0 * _Point;

   return MathMax(atr * InpZoneATRWidthMultiplier, 2.0 * _Point);
}

double GetZoneMergeDistance()
{
   double atr = g_ctx.atr;
   if(atr <= 0.0)
      atr = GetATRValue(_Symbol, _Period, 14, 1);

   if(atr <= 0.0)
      atr = 10.0 * _Point;

   return MathMax(atr * InpZoneMergeATRMultiplier, 2.0 * _Point);
}

double GetZoneBreakDistance()
{
   double atr = g_ctx.atr;
   if(atr <= 0.0)
      atr = GetATRValue(_Symbol, _Period, 14, 1);

   if(atr <= 0.0)
      atr = 10.0 * _Point;

   return MathMax(atr * InpZoneBreakATRMultiplier, 2.0 * _Point);
}

int FindNearestZoneIndex(const ENUM_ZONE_TYPE type, const double price, const double mergeDistance)
{
   int    bestIdx  = -1;
   double bestDist = DBL_MAX;

   for(int i = 0; i < ArraySize(g_zones); i++)
   {
      if(!g_zones[i].valid)
         continue;

      if(g_zones[i].type != type)
         continue;

      double mid  = GetZoneMidPrice(g_zones[i]);
      double dist = MathAbs(price - mid);
      if(dist <= mergeDistance && dist < bestDist)
      {
         bestDist = dist;
         bestIdx  = i;
      }
   }

   return bestIdx;
}

int FindFreeZoneSlot()
{
   for(int i = 0; i < ArraySize(g_zones); i++)
   {
      if(!g_zones[i].valid)
         return i;
   }

   int oldestIdx = -1;
   datetime oldestTime = LONG_MAX;

   for(int i = 0; i < ArraySize(g_zones); i++)
   {
      if(g_zones[i].createdTime < oldestTime)
      {
         oldestTime = g_zones[i].createdTime;
         oldestIdx  = i;
      }
   }

   return oldestIdx;
}

void AddOrMergeZone(const ENUM_ZONE_TYPE type, const int shift, const double pivotPrice)
{
   double zoneHalfWidth = 0.5 * GetZoneWidthPrice();
   double mergeDistance = GetZoneMergeDistance();
   datetime pivotTime   = iTime(_Symbol, _Period, shift);

   int idx = FindNearestZoneIndex(type, pivotPrice, mergeDistance);

   if(idx >= 0)
   {
      double oldMid = GetZoneMidPrice(g_zones[idx]);
      double newMid = (oldMid * g_zones[idx].touches + pivotPrice) / (g_zones[idx].touches + 1);

      g_zones[idx].upper         = NormalizePrice(newMid + zoneHalfWidth);
      g_zones[idx].lower         = NormalizePrice(newMid - zoneHalfWidth);
      g_zones[idx].touches++;
      g_zones[idx].lastTouchTime = pivotTime;
      g_zones[idx].strength     += 1.0;

      return;
   }

   idx = FindFreeZoneSlot();
   if(idx < 0)
      return;

   g_zones[idx].valid         = true;
   g_zones[idx].type          = type;
   g_zones[idx].createdTime   = pivotTime;
   g_zones[idx].lastTouchTime = pivotTime;
   g_zones[idx].upper         = NormalizePrice(pivotPrice + zoneHalfWidth);
   g_zones[idx].lower         = NormalizePrice(pivotPrice - zoneHalfWidth);
   g_zones[idx].touches       = 1;
   g_zones[idx].strength      = 1.0;
   g_zones[idx].broken        = false;
}

double GetAverageTickVolume(const int fromShift, const int count)
{
   if(count <= 0)
      return 0.0;

   double sum = 0.0;
   int used   = 0;

   for(int i = fromShift; i < fromShift + count; i++)
   {
      long v = iVolume(_Symbol, _Period, i);
      if(v <= 0)
         continue;

      sum += (double)v;
      used++;
   }

   if(used <= 0)
      return 0.0;

   return sum / used;
}

double GetZoneFreshnessScore(const ZoneInfo &z)
{
   int barsAgo = iBarShift(_Symbol, _Period, z.lastTouchTime, false);
   if(barsAgo < 0)
      return 0.0;

   if(barsAgo <= 25)  return 2.0;
   if(barsAgo <= 75)  return 1.5;
   if(barsAgo <= 150) return 1.0;
   return 0.5;
}

double GetZoneReactionScore(const ZoneInfo &z)
{
   double s = 0.0;

   // --- touches: logarithmic scaling (prevents saturation)
   double t = (double)z.touches;
   double touchScore = 2.0 * MathLog(1.0 + t);   // smooth growth
   s += touchScore;

   // --- freshness
   s += GetZoneFreshnessScore(z);

   // --- broken penalty
   if(z.broken)
      s -= 2.0;

   // --- recency bonus
   int barsAgo = iBarShift(_Symbol, _Period, z.lastTouchTime, false);
   if(barsAgo >= 0 && barsAgo <= 10)
      s += 0.5;

   return s;
}

void ScoreAndValidateZones()
{
   double breakDist = GetZoneBreakDistance();
   double close1    = iClose(_Symbol, _Period, 1);

   for(int i = 0; i < ArraySize(g_zones); i++)
   {
      if(!g_zones[i].valid)
         continue;

      g_zones[i].strength = GetZoneReactionScore(g_zones[i]);

      if(g_zones[i].type == ZONE_SUPPORT)
      {
         if(close1 < (g_zones[i].lower - breakDist))
            g_zones[i].broken = true;
      }
      else if(g_zones[i].type == ZONE_RESISTANCE)
      {
         if(close1 > (g_zones[i].upper + breakDist))
            g_zones[i].broken = true;
      }
   }
}

void SortZonesByStrengthDescending()
{
   for(int i = 0; i < ArraySize(g_zones) - 1; i++)
   {
      for(int j = i + 1; j < ArraySize(g_zones); j++)
      {
         double si = (g_zones[i].valid ? g_zones[i].strength : -1.0);
         double sj = (g_zones[j].valid ? g_zones[j].strength : -1.0);

         if(sj > si)
         {
            ZoneInfo tmp = g_zones[i];
            g_zones[i]   = g_zones[j];
            g_zones[j]   = tmp;
         }
      }
   }
}

void TrimZonesToMax()
{
   int kept = 0;

   for(int i = 0; i < ArraySize(g_zones); i++)
   {
      if(!g_zones[i].valid)
         continue;

      kept++;
      if(kept <= InpMaxZones)
         continue;

      g_zones[i].valid = false;
   }
}

void BuildZonesFromSwings()
{
   ResetZones();

   int totalBars = Bars(_Symbol, _Period);
   if(totalBars <= (InpSwingLeft + InpSwingRight + 10))
      return;

   int maxShift = MathMin(InpZoneLookbackBars, totalBars - InpSwingLeft - 2);
   if(maxShift <= InpSwingRight + 2)
      return;

   for(int shift = maxShift; shift >= InpSwingRight; shift--)
   {
      if(IsSwingHigh(shift))
      {
         double h = iHigh(_Symbol, _Period, shift);
         AddOrMergeZone(ZONE_RESISTANCE, shift, h);
      }

      if(IsSwingLow(shift))
      {
         double l = iLow(_Symbol, _Period, shift);
         AddOrMergeZone(ZONE_SUPPORT, shift, l);
      }
   }

   ScoreAndValidateZones();
   SortZonesByStrengthDescending();
   TrimZonesToMax();
}

void UpdateZoneTouchesFromRecentBars()
{
   int barsToCheck = MathMin(100, Bars(_Symbol, _Period) - 2);
   if(barsToCheck <= 1)
      return;

   for(int i = 0; i < ArraySize(g_zones); i++)
   {
      if(!g_zones[i].valid)
         continue;

      g_zones[i].touches = 0;

      for(int shift = barsToCheck; shift >= 1; shift--)
      {
         double high = iHigh(_Symbol, _Period, shift);
         double low  = iLow(_Symbol, _Period, shift);

         bool touched = !(high < g_zones[i].lower || low > g_zones[i].upper);
         if(touched)
         {
            g_zones[i].touches++;
            g_zones[i].lastTouchTime = iTime(_Symbol, _Period, shift);
         }
      }
   }

   ScoreAndValidateZones();
   SortZonesByStrengthDescending();
   TrimZonesToMax();
}

ENUM_MARKET_REGIME DetectMarketRegime()
{
   double fastMA = GetMAValue(_Symbol, _Period, InpRegimeFastMAPeriod, 0, MODE_EMA, PRICE_CLOSE, 1);
   double slowMA = GetMAValue(_Symbol, _Period, InpRegimeSlowMAPeriod, 0, MODE_EMA, PRICE_CLOSE, 1);
   double atr    = g_ctx.atr;

   if(atr <= 0.0)
      atr = GetATRValue(_Symbol, _Period, 14, 1);
   if(atr <= 0.0)
      atr = 10.0 * _Point;

   double sep = MathAbs(fastMA - slowMA);

   if(fastMA > slowMA && sep >= atr * InpRegimeMinSeparationATR)
      return REGIME_TREND_UP;

   if(fastMA < slowMA && sep >= atr * InpRegimeMinSeparationATR)
      return REGIME_TREND_DOWN;

   return REGIME_RANGE;
}

string RegimeToString(const ENUM_MARKET_REGIME regime)
{
   switch(regime)
   {
      case REGIME_RANGE:      return "RANGE";
      case REGIME_TREND_UP:   return "TREND_UP";
      case REGIME_TREND_DOWN: return "TREND_DOWN";
      default:                return "NONE";
   }
}

void LogTopZones()
{
   if(InpLogLevel < LOG_DEBUG)
      return;

   int printed = 0;
   for(int i = 0; i < ArraySize(g_zones); i++)
   {
      if(!g_zones[i].valid)
         continue;

      string t = (g_zones[i].type == ZONE_SUPPORT ? "SUP" : "RES");
      string msg =
         "Zone[" + IntegerToString(i) + "] " + t +
         " lower=" + DoubleToString(g_zones[i].lower, g_ctx.digits) +
         " upper=" + DoubleToString(g_zones[i].upper, g_ctx.digits) +
         " touches=" + IntegerToString(g_zones[i].touches) +
         " strength=" + DoubleToString(g_zones[i].strength, 2) +
         " broken=" + (g_zones[i].broken ? "true" : "false");

      LogPrint(LOG_DEBUG, msg);

      printed++;
      if(printed >= 5)
         break;
   }
}

double GetATRSafe()
{
   double atr = g_ctx.atr;
   if(atr <= 0.0)
      atr = GetATRValue(_Symbol, _Period, 14, 1);
   if(atr <= 0.0)
      atr = 10.0 * _Point;
   return atr;
}

double GetCandleRange(const int shift)
{
   return iHigh(_Symbol, _Period, shift) - iLow(_Symbol, _Period, shift);
}

double GetCandleBody(const int shift)
{
   return MathAbs(iClose(_Symbol, _Period, shift) - iOpen(_Symbol, _Period, shift));
}

double GetLowerWick(const int shift)
{
   double open  = iOpen(_Symbol, _Period, shift);
   double close = iClose(_Symbol, _Period, shift);
   double low   = iLow(_Symbol, _Period, shift);
   double lowerBody = MathMin(open, close);
   return lowerBody - low;
}

double GetUpperWick(const int shift)
{
   double open  = iOpen(_Symbol, _Period, shift);
   double close = iClose(_Symbol, _Period, shift);
   double high  = iHigh(_Symbol, _Period, shift);
   double upperBody = MathMax(open, close);
   return high - upperBody;
}

bool IsBullishCandle(const int shift)
{
   return iClose(_Symbol, _Period, shift) > iOpen(_Symbol, _Period, shift);
}

bool IsBearishCandle(const int shift)
{
   return iClose(_Symbol, _Period, shift) < iOpen(_Symbol, _Period, shift);
}

bool IsZoneTradableForSweep(const ZoneInfo &z)
{
   if(!z.valid)
      return false;

   if(z.broken)
      return false;

   if(z.touches < InpZoneMinTouches)
      return false;

   return true;
}

int FindBestSweepSupportZone()
{
   int bestIdx = -1;
   double bestScore = -DBL_MAX;

   for(int i = 0; i < ArraySize(g_zones); i++)
   {
      if(!g_zones[i].valid)
         continue;
      if(g_zones[i].type != ZONE_SUPPORT)
         continue;
      if(!IsZoneTradableForSweep(g_zones[i]))
         continue;

      double score = g_zones[i].strength;
      if(score > bestScore)
      {
         bestScore = score;
         bestIdx = i;
      }
   }

   return bestIdx;
}

int FindBestSweepResistanceZone()
{
   int bestIdx = -1;
   double bestScore = -DBL_MAX;

   for(int i = 0; i < ArraySize(g_zones); i++)
   {
      if(!g_zones[i].valid)
         continue;
      if(g_zones[i].type != ZONE_RESISTANCE)
         continue;
      if(!IsZoneTradableForSweep(g_zones[i]))
         continue;

      double score = g_zones[i].strength;
      if(score > bestScore)
      {
         bestScore = score;
         bestIdx = i;
      }
   }

   return bestIdx;
}

bool IsSweepVolumeConfirmed(const int shift)
{
   if(!InpRequireSweepVolumeSpike)
      return true;

   long volNow = iVolume(_Symbol, _Period, shift);
   double avg  = GetAverageTickVolume(shift + 1, InpVolumeLookback);

   if(avg <= 0.0)
      return true;

   return ((double)volNow >= avg * InpVolumeSpikeFactor);
}

bool IsSweepRegimeAllowed(const ENUM_BASKET_DIRECTION dir)
{
   if(!InpUseRegimeFilterForSweep)
      return true;

   if(g_ctx.regime == REGIME_RANGE)
      return InpAllowRangeSweeps;

   if(dir == BASKET_DIR_BUY && g_ctx.regime == REGIME_TREND_UP)
      return true;

   if(dir == BASKET_DIR_SELL && g_ctx.regime == REGIME_TREND_DOWN)
      return true;

   return false;
}

bool IsBullishSweepThroughSupport(const ZoneInfo &z, const int shift)
{
   double atr   = GetATRSafe();
   double high  = iHigh(_Symbol, _Period, shift);
   double low   = iLow(_Symbol, _Period, shift);
   double open  = iOpen(_Symbol, _Period, shift);
   double close = iClose(_Symbol, _Period, shift);

   double penetration = z.lower - low;
   if(penetration < atr * InpMinSweepPenetrationATR)
      return false;

   if(close <= z.lower)
      return false;

   if(InpRequireSweepStrongClose && close <= z.upper)
      return false;

   double lowerWick = GetLowerWick(shift);
   if(lowerWick < atr * InpMinSweepRejectWickATR)
      return false;

   double body = MathAbs(close - open);
   if(body > atr * InpMaxSweepBodyATR)
      return false;

   if(high <= z.lower)
      return false;


   // require wick dominance
   if(lowerWick < body * 1.2)
      return false;
      
   if(!IsBullishCandle(shift) && InpRequireSweepStrongClose)
      return false;

   return true;
}

bool IsBearishSweepThroughResistance(const ZoneInfo &z, const int shift)
{
   double atr   = GetATRSafe();
   double high  = iHigh(_Symbol, _Period, shift);
   double low   = iLow(_Symbol, _Period, shift);
   double open  = iOpen(_Symbol, _Period, shift);
   double close = iClose(_Symbol, _Period, shift);

   double penetration = high - z.upper;
   if(penetration < atr * InpMinSweepPenetrationATR)
      return false;

   if(close >= z.upper)
      return false;

   if(InpRequireSweepStrongClose && close >= z.lower)
      return false;

   double upperWick = GetUpperWick(shift);
   if(upperWick < atr * InpMinSweepRejectWickATR)
      return false;

   double body = MathAbs(close - open);
   if(body > atr * InpMaxSweepBodyATR)
      return false;

   if(low >= z.upper)
      return false;
      
    // require wick dominance
   if(upperWick < body * 1.2)
      return false;

   if(!IsBearishCandle(shift) && InpRequireSweepStrongClose)
      return false;

   return true;
}

double GetSweepBuyStopLoss(const ZoneInfo &z, const int shift)
{
   double atr = GetATRSafe();
   double low = iLow(_Symbol, _Period, shift);
   double sl  = low - atr * InpSweepSL_BufferATR;
   return NormalizePrice(sl);
}

double GetSweepSellStopLoss(const ZoneInfo &z, const int shift)
{
   double atr  = GetATRSafe();
   double high = iHigh(_Symbol, _Period, shift);
   double sl   = high + atr * InpSweepSL_BufferATR;
   return NormalizePrice(sl);
}

double GetSweepBuyTakeProfit(const double entry, const double sl)
{
   double atr = GetATRSafe();
   double tp1 = entry + atr * InpSweepTP_ATR_Multiplier;
   double rr  = entry + 2.0 * (entry - sl);
   return NormalizePrice(MathMax(tp1, rr));
}

double GetSweepSellTakeProfit(const double entry, const double sl)
{
   double atr = GetATRSafe();
   double tp1 = entry - atr * InpSweepTP_ATR_Multiplier;
   double rr  = entry - 2.0 * (sl - entry);
   return NormalizePrice(MathMin(tp1, rr));
}

bool IsZoneTradableForBreakout(const ZoneInfo &z)
{
   if(!z.valid)
      return false;

   if(z.touches < InpZoneMinTouches)
      return false;

   return true;
}

int FindBestBreakoutResistanceZone()
{
   int bestIdx = -1;
   double bestScore = -DBL_MAX;
   double close1 = iClose(_Symbol, _Period, 1);

   for(int i = 0; i < ArraySize(g_zones); i++)
   {
      if(!g_zones[i].valid)
         continue;
      if(g_zones[i].type != ZONE_RESISTANCE)
         continue;
      if(!IsZoneTradableForBreakout(g_zones[i]))
         continue;

      double distPenalty = MathAbs(close1 - GetZoneMidPrice(g_zones[i])) / GetATRSafe();
      double score = g_zones[i].strength - 0.20 * distPenalty;

      if(score > bestScore)
      {
         bestScore = score;
         bestIdx   = i;
      }
   }

   return bestIdx;
}

int FindBestBreakoutSupportZone()
{
   int bestIdx = -1;
   double bestScore = -DBL_MAX;
   double close1 = iClose(_Symbol, _Period, 1);

   for(int i = 0; i < ArraySize(g_zones); i++)
   {
      if(!g_zones[i].valid)
         continue;
      if(g_zones[i].type != ZONE_SUPPORT)
         continue;
      if(!IsZoneTradableForBreakout(g_zones[i]))
         continue;

      double distPenalty = MathAbs(close1 - GetZoneMidPrice(g_zones[i])) / GetATRSafe();
      double score = g_zones[i].strength - 0.20 * distPenalty;

      if(score > bestScore)
      {
         bestScore = score;
         bestIdx   = i;
      }
   }

   return bestIdx;
}

bool IsBreakoutVolumeConfirmed(const int shift)
{
   if(!InpRequireBreakoutVolumeSpike)
      return true;

   long volNow = iVolume(_Symbol, _Period, shift);
   double avg  = GetAverageTickVolume(shift + 1, InpVolumeLookback);

   if(avg <= 0.0)
      return true;

   return ((double)volNow >= avg * InpVolumeSpikeFactor);
}

bool IsBreakoutRegimeAllowed(const ENUM_BASKET_DIRECTION dir)
{
   if(!InpUseRegimeFilterForBreakout)
      return true;

   if(g_ctx.regime == REGIME_RANGE)
      return InpAllowRangeBreakouts;

   if(dir == BASKET_DIR_BUY && g_ctx.regime == REGIME_TREND_UP)
      return true;

   if(dir == BASKET_DIR_SELL && g_ctx.regime == REGIME_TREND_DOWN)
      return true;

   return false;
}

bool DidBullishRetestHold(const ZoneInfo &z)
{
   if(!InpRequireBreakoutRetest)
      return true;

   double atr = GetATRSafe();
   double tol = atr * InpBreakoutRetestToleranceATR;

   int maxBars = MathMax(2, InpBreakoutRetestLookbackBars);

   // start at shift 2 so breakout candle itself is not counted as retest
   for(int shift = 2; shift <= maxBars; shift++)
   {
      double low   = iLow(_Symbol, _Period, shift);
      double close = iClose(_Symbol, _Period, shift);

      bool touchedRetest = (low <= z.upper + tol && low >= z.lower - tol);
      bool held          = (close > z.upper);

      if(touchedRetest && held)
         return true;
   }

   return false;
}

bool DidBearishRetestHold(const ZoneInfo &z)
{
   if(!InpRequireBreakoutRetest)
      return true;

   double atr = GetATRSafe();
   double tol = atr * InpBreakoutRetestToleranceATR;

   int maxBars = MathMax(2, InpBreakoutRetestLookbackBars);

   // start at shift 2 so breakout candle itself is not counted as retest
   for(int shift = 2; shift <= maxBars; shift++)
   {
      double high  = iHigh(_Symbol, _Period, shift);
      double close = iClose(_Symbol, _Period, shift);

      bool touchedRetest = (high >= z.lower - tol && high <= z.upper + tol);
      bool held          = (close < z.lower);

      if(touchedRetest && held)
         return true;
   }

   return false;
}

bool IsBullishBreakoutThroughResistance(const ZoneInfo &z, const int shift)
{
   double atr   = GetATRSafe();
   double open  = iOpen(_Symbol, _Period, shift);
   double close = iClose(_Symbol, _Period, shift);
   double high  = iHigh(_Symbol, _Period, shift);

   double body = MathAbs(close - open);
   if(body < atr * InpMinBreakoutBodyATR)
      return false;

   if(close <= z.upper)
      return false;

   if(InpRequireBreakoutStrongClose)
   {
      if(close <= z.upper + atr * 0.05)
         return false;
      if(!IsBullishCandle(shift))
         return false;
   }

   double upperWick = GetUpperWick(shift);
   if(upperWick > atr * InpMaxBreakoutOppWickATR)
      return false;

   if(high <= z.upper)
      return false;

   return true;
}

bool IsBearishBreakoutThroughSupport(const ZoneInfo &z, const int shift)
{
   double atr   = GetATRSafe();
   double open  = iOpen(_Symbol, _Period, shift);
   double close = iClose(_Symbol, _Period, shift);
   double low   = iLow(_Symbol, _Period, shift);

   double body = MathAbs(close - open);
   if(body < atr * InpMinBreakoutBodyATR)
      return false;

   if(close >= z.lower)
      return false;

   if(InpRequireBreakoutStrongClose)
   {
      if(close >= z.lower - atr * 0.05)
         return false;
      if(!IsBearishCandle(shift))
         return false;
   }

   double lowerWick = GetLowerWick(shift);
   if(lowerWick > atr * InpMaxBreakoutOppWickATR)
      return false;

   if(low >= z.lower)
      return false;

   return true;
}

double GetBreakoutBuyStopLoss(const ZoneInfo &z, const int shift)
{
   double atr = GetATRSafe();
   double barLow = iLow(_Symbol, _Period, shift);
   double refLow = MathMin(barLow, z.lower);
   return NormalizePrice(refLow - atr * InpBreakoutSL_BufferATR);
}

double GetBreakoutSellStopLoss(const ZoneInfo &z, const int shift)
{
   double atr = GetATRSafe();
   double barHigh = iHigh(_Symbol, _Period, shift);
   double refHigh = MathMax(barHigh, z.upper);
   return NormalizePrice(refHigh + atr * InpBreakoutSL_BufferATR);
}

double GetBreakoutBuyTakeProfit(const double entry, const double sl)
{
   double atr = GetATRSafe();
   double tp1 = entry + atr * InpBreakoutTP_ATR_Multiplier;
   double rr  = entry + 2.0 * (entry - sl);
   return NormalizePrice(MathMax(tp1, rr));
}

double GetBreakoutSellTakeProfit(const double entry, const double sl)
{
   double atr = GetATRSafe();
   double tp1 = entry - atr * InpBreakoutTP_ATR_Multiplier;
   double rr  = entry - 2.0 * (sl - entry);
   return NormalizePrice(MathMin(tp1, rr));
}

bool CloseAllBasketPositions(const string reason)
{
   bool hadAny = false;
   bool allOk  = true;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;

      if(!PositionSelectByTicket(ticket))
         continue;

      string sym = PositionGetString(POSITION_SYMBOL);
      long magic = PositionGetInteger(POSITION_MAGIC);

      if(sym != _Symbol || (ulong)magic != InpMagicNumber)
         continue;

      hadAny = true;

      if(!trade.PositionClose(ticket))
      {
         allOk = false;
         LogPrint(LOG_ERROR, "Close failed | reason=" + reason + " | ticket=" + IntegerToString((int)ticket));
      }
      else
      {
         LogPrint(LOG_INFO, "Position closed | reason=" + reason + " | ticket=" + IntegerToString((int)ticket));
      }
   }

   if(hadAny && allOk)
   {
      g_lastEntrySignalType   = SIG_NONE;
      g_lastEntryInvalidation = 0.0;
      g_lastEntryInitialRisk  = 0.0;
   }

   return hadAny && allOk;
}

bool ModifyAllBasketPositions(const double newSL, const double newTP, const string reason)
{
   bool hadAny = false;
   bool allOk  = true;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;

      if(!PositionSelectByTicket(ticket))
         continue;

      string sym = PositionGetString(POSITION_SYMBOL);
      long magic = PositionGetInteger(POSITION_MAGIC);

      if(sym != _Symbol || (ulong)magic != InpMagicNumber)
         continue;

      hadAny = true;

      double oldTP = PositionGetDouble(POSITION_TP);

      if(!trade.PositionModify(ticket, newSL, (newTP > 0.0 ? newTP : oldTP)))
      {
         allOk = false;
         LogPrint(LOG_ERROR, "Modify failed | reason=" + reason + " | ticket=" + IntegerToString((int)ticket));
      }
   }

   if(hadAny && allOk)
      LogPrint(LOG_INFO, "Basket modified | reason=" + reason + " | sl=" + DoubleToString(newSL, g_ctx.digits));

   return hadAny && allOk;
}

int GetBarsSinceTime(const datetime t)
{
   if(t <= 0)
      return 0;

   int shift = iBarShift(_Symbol, _Period, t, false);
   if(shift < 0)
      return 0;

   return shift;
}

bool ShouldExitStaleTrade(const BasketState &b)
{
   if(!InpUseStaleExit)
      return false;

   if(!b.active)
      return false;

   int barsOpen = GetBarsSinceTime(b.openedTime);
   return (barsOpen >= InpMaxBarsInTrade);
}

bool ShouldExitFailedSweep(const BasketState &b)
{
   if(!InpUseFailedPatternExit)
      return false;

   if(!b.active)
      return false;

   if(b.sourceSignal != SIG_SWEEP_REVERSAL_BUY && b.sourceSignal != SIG_SWEEP_REVERSAL_SELL)
      return false;

   double atr = GetATRSafe();
   double close1 = iClose(_Symbol, _Period, 1);

   if(b.direction == BASKET_DIR_BUY)
   {
      if(b.invalidationPrice > 0.0 && close1 < (b.invalidationPrice - atr * InpFailedSweepExitATR))
         return true;
   }
   else if(b.direction == BASKET_DIR_SELL)
   {
      if(b.invalidationPrice > 0.0 && close1 > (b.invalidationPrice + atr * InpFailedSweepExitATR))
         return true;
   }

   return false;
}

bool ShouldExitFailedBreakout(const BasketState &b)
{
   if(!InpUseFailedPatternExit)
      return false;

   if(!b.active)
      return false;

   if(b.sourceSignal != SIG_BREAKOUT_CONT_BUY && b.sourceSignal != SIG_BREAKOUT_CONT_SELL)
      return false;

   double atr = GetATRSafe();
   double close1 = iClose(_Symbol, _Period, 1);

   if(b.direction == BASKET_DIR_BUY)
   {
      if(b.invalidationPrice > 0.0 && close1 < (b.invalidationPrice - atr * InpFailedBreakoutExitATR))
         return true;
   }
   else if(b.direction == BASKET_DIR_SELL)
   {
      if(b.invalidationPrice > 0.0 && close1 > (b.invalidationPrice + atr * InpFailedBreakoutExitATR))
         return true;
   }

   return false;
}

bool ShouldExitOnOppositeSignal(const BasketState &b)
{
   if(!InpUseOppositeSignalExit)
      return false;

   if(!b.active)
      return false;

   SignalInfo sweepSig    = DetectLiquiditySweepSignal();
   SignalInfo breakoutSig = DetectBreakoutContinuationSignal();

   if(b.direction == BASKET_DIR_BUY)
   {
      if((sweepSig.valid && sweepSig.direction == BASKET_DIR_SELL) ||
         (breakoutSig.valid && breakoutSig.direction == BASKET_DIR_SELL))
         return true;
   }
   else if(b.direction == BASKET_DIR_SELL)
   {
      if((sweepSig.valid && sweepSig.direction == BASKET_DIR_BUY) ||
         (breakoutSig.valid && breakoutSig.direction == BASKET_DIR_BUY))
         return true;
   }

   return false;
}

bool ApplyBreakEvenIfNeeded(const BasketState &b)
{
   if(!InpUseBreakEven)
      return false;

   if(!b.active)
      return false;

   if(b.initialRiskPrice <= 0.0)
      return false;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double currentPrice = (b.direction == BASKET_DIR_BUY ? bid : ask);

   double move = (b.direction == BASKET_DIR_BUY
                  ? currentPrice - b.weightedEntry
                  : b.weightedEntry - currentPrice);

   if(move < b.initialRiskPrice * InpBreakEvenAtR)
      return false;

   double lockPrice = InpBreakEvenLockPoints * _Point;
   double newSL = 0.0;

   if(b.direction == BASKET_DIR_BUY)
   {
      newSL = NormalizePrice(b.weightedEntry + lockPrice);
      if(b.basketSL >= newSL && b.basketSL > 0.0)
         return false;
   }
    else if(b.direction == BASKET_DIR_SELL)
   {
      newSL = NormalizePrice(b.weightedEntry - lockPrice);
      if(b.basketSL > 0.0 && newSL >= b.basketSL)
         return false;
   }

   return ModifyAllBasketPositions(newSL, 0.0, "BreakEven");
}

bool ApplyTrailingStopIfNeeded(const BasketState &b)
{
   if(!InpUseTrailingStop)
      return false;

   if(!b.active)
      return false;

   double atr = GetATRSafe();
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   double newSL = 0.0;

   if(b.direction == BASKET_DIR_BUY)
   {
      newSL = NormalizePrice(bid - atr * InpTrailATRMultiplier);

      if(newSL <= b.weightedEntry)
         return false;

      if(b.basketSL > 0.0 && newSL <= b.basketSL)
         return false;
   }
   else if(b.direction == BASKET_DIR_SELL)
   {
      newSL = NormalizePrice(ask + atr * InpTrailATRMultiplier);

      if(newSL >= b.weightedEntry)
         return false;

      if(b.basketSL > 0.0 && newSL >= b.basketSL)
         return false;
   }
   else
      return false;

   return ModifyAllBasketPositions(newSL, 0.0, "Trail");
}
double GetBasketRiskBudgetMoney()
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(balance <= 0.0)
      return 0.0;

   return balance * InpRiskPerBasketPct / 100.0;
}

double GetMoneyRiskForPosition(const double volume, const double openPrice, const double slPrice)
{
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);

   if(tickSize <= 0.0 || tickValue <= 0.0)
      return 0.0;

   double stopDistance = MathAbs(openPrice - slPrice);
   if(stopDistance <= 0.0)
      return 0.0;

   double moneyPerLot = (stopDistance / tickSize) * tickValue;
   return moneyPerLot * volume;
}

double GetCurrentBasketOpenRiskMoney()
{
   double totalRisk = 0.0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;

      if(!PositionSelectByTicket(ticket))
         continue;

      string sym = PositionGetString(POSITION_SYMBOL);
      long magic = PositionGetInteger(POSITION_MAGIC);
      if(sym != _Symbol || (ulong)magic != InpMagicNumber)
         continue;

      double volume = PositionGetDouble(POSITION_VOLUME);
      double open   = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl     = PositionGetDouble(POSITION_SL);

      if(sl <= 0.0)
         continue;

      totalRisk += GetMoneyRiskForPosition(volume, open, sl);
   }

   return totalRisk;
}

double CalcAddLotByRemainingRisk(const double stopDistancePrice, const double referenceLot)
{
   if(stopDistancePrice <= 0.0)
      return 0.0;

   double budgetMoney   = GetBasketRiskBudgetMoney();
   double usedRiskMoney = GetCurrentBasketOpenRiskMoney();
   double remainingRisk = budgetMoney - usedRiskMoney;

   double minNeeded = budgetMoney * InpGridMinRemainingRiskPct;
   if(minNeeded < 0.0)
      minNeeded = 0.0;

   if(remainingRisk <= minNeeded)
      return 0.0;

   double tickSize   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);

   if(tickSize <= 0.0 || tickValue <= 0.0)
      return 0.0;

   double moneyPerLot = (stopDistancePrice / tickSize) * tickValue;
   if(moneyPerLot <= 0.0)
      return 0.0;

   double lotsByRisk = remainingRisk / moneyPerLot;

   double candidateLot = referenceLot;
   if(candidateLot <= 0.0)
      candidateLot = InpFixedLot;

   candidateLot *= InpGridLotMultiplier;
   candidateLot = MathMin(candidateLot, lotsByRisk);
   candidateLot = MathMin(candidateLot, InpGridMaxLotPerAdd);

   return NormalizeVolumeToStep(candidateLot);
}

double GetGridSpacingPrice()
{
   double atr = GetATRSafe();
   return MathMax(atr * InpGridATRMultiplier, 2.0 * _Point);
}

bool IsBasketAddCapReached(const BasketState &b)
{
   if(!b.active)
      return true;

   if(b.positionCount >= InpMaxPositionsPerBasket)
      return true;

   if(b.addCount >= InpMaxAddsPerBasket)
      return true;

   return false;
}

bool IsBasketStillValidForAdds(const BasketState &b)
{
   if(!b.active)
      return false;

   if(IsRiskLocked())
      return false;

   if(!IsBrokerTradeWindow())
      return false;

   if(!IsSpreadOK())
      return false;

   return true;
}

bool IsSignalAllowedForGrid(const SignalInfo &sig)
{
   if(!sig.valid)
      return false;

   if(sig.type == SIG_SWEEP_REVERSAL_BUY || sig.type == SIG_SWEEP_REVERSAL_SELL)
      return InpGridAllowSweepAdds;

   if(sig.type == SIG_BREAKOUT_CONT_BUY || sig.type == SIG_BREAKOUT_CONT_SELL)
      return InpGridAllowBreakoutAdds;

   return false;
}

bool IsBetterPriceForAdd(const BasketState &b, const double candidateEntry)
{
   if(!InpGridRequireBetterPrice)
      return true;

   double spacing = GetGridSpacingPrice();

   if(b.lastEntryPrice <= 0.0)
      return true;

   if(b.direction == BASKET_DIR_BUY)
      return (candidateEntry <= b.lastEntryPrice - spacing);

   if(b.direction == BASKET_DIR_SELL)
      return (candidateEntry >= b.lastEntryPrice + spacing);

   return false;
}

bool SelectGridAddSignal(const BasketState &b,
                         const SignalInfo &sweepSig,
                         const SignalInfo &breakoutSig,
                         SignalInfo &chosenSig)
{
   chosenSig.valid = false;

   if(!b.active)
      return false;

   SignalInfo bestSig;
   bestSig.valid = false;

   if(sweepSig.valid &&
      sweepSig.direction == b.direction &&
      IsSignalAllowedForGrid(sweepSig))
   {
      bestSig = sweepSig;
   }

   if(breakoutSig.valid &&
      breakoutSig.direction == b.direction &&
      IsSignalAllowedForGrid(breakoutSig))
   {
      if(!bestSig.valid || breakoutSig.confidence > bestSig.confidence)
         bestSig = breakoutSig;
   }

   if(!bestSig.valid)
      return false;

   if(InpGridRequireSameDirectionSignal && bestSig.direction != b.direction)
      return false;

   double candidateEntry = (b.direction == BASKET_DIR_BUY
                            ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                            : SymbolInfoDouble(_Symbol, SYMBOL_BID));

   if(!IsBetterPriceForAdd(b, candidateEntry))
      return false;

   chosenSig = bestSig;
   return true;
}

bool ExecuteAddSignal(const BasketState &b, const SignalInfo &sig)
{
   if(!b.active || !sig.valid)
      return false;

   double entry = 0.0;
   double sl    = NormalizePrice(sig.stopLoss);
   double tp    = NormalizePrice(sig.takeProfit);

   if(sig.direction == BASKET_DIR_BUY)
      entry = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   else if(sig.direction == BASKET_DIR_SELL)
      entry = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   else
      return false;

   double stopDistance = MathAbs(entry - sl);
   if(stopDistance <= 0.0)
      return false;

   double refLot = b.lastEntryLots;
   if(refLot <= 0.0)
      refLot = (b.totalLots > 0.0 ? b.totalLots / MathMax(1, b.positionCount) : InpFixedLot);

   double lots = CalcAddLotByRemainingRisk(stopDistance, refLot);
   if(lots <= 0.0)
   {
      LogPrint(LOG_DEBUG, "Grid add blocked | no remaining risk budget");
      return false;
   }

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(10);

   bool ok = false;

   string comment = "Grid add | " + sig.reason;

   if(sig.direction == BASKET_DIR_BUY && InpAllowBuy)
      ok = trade.Buy(lots, _Symbol, 0.0, sl, tp, comment);
   else if(sig.direction == BASKET_DIR_SELL && InpAllowSell)
      ok = trade.Sell(lots, _Symbol, 0.0, sl, tp, comment);

   if(ok)
   {
      LogPrint(LOG_INFO,
         "Grid add executed | dir=" + IntegerToString((int)sig.direction) +
         " | lots=" + DoubleToString(lots, 2) +
         " | entry=" + DoubleToString(entry, g_ctx.digits) +
         " | sl=" + DoubleToString(sl, g_ctx.digits) +
         " | tp=" + DoubleToString(tp, g_ctx.digits));
   }
   else
   {
      LogPrint(LOG_ERROR, "Grid add failed. Retcode=" + IntegerToString((int)trade.ResultRetcode()));
   }

   return ok;
}

bool TryAddToBasket(const SignalInfo &sweepSig, const SignalInfo &breakoutSig)
{
   if(!InpEnableGrid)
      return false;

   if(!RefreshBasketState(g_basket))
      return false;

   if(!IsBasketStillValidForAdds(g_basket))
   {
      //g_tel.addBlockedValidity++;
      return false;
   }

   if(IsBasketAddCapReached(g_basket))
   {
      //g_tel.addBlockedCap++;
      LogPrint(LOG_DEBUG, "Grid add blocked | basket cap reached");
      return false;
   }

   double entry = (g_basket.direction == BASKET_DIR_BUY
                   ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                   : SymbolInfoDouble(_Symbol, SYMBOL_BID));

   if(!IsBetterPriceForAdd(g_basket, entry))
   {
      //g_tel.addBlockedPrice++;
      LogPrint(LOG_DEBUG, "Grid add blocked | no better price");
      return false;
   }

   SignalInfo addSig;
   addSig.valid             = true;
   addSig.symbol            = _Symbol;
   addSig.direction         = g_basket.direction;
   addSig.entryPrice        = entry;
   addSig.stopLoss          = g_basket.basketSL;
   addSig.takeProfit        = g_basket.basketTP;
   addSig.invalidationPrice = g_basket.invalidationPrice;
   addSig.confidence        = 0.0;
   addSig.reason            = "Structure-based grid add";

   return ExecuteAddSignal(g_basket, addSig);
}

//==================================================================//
// PLACEHOLDERS FOR NEXT PHASES
//==================================================================//
void UpdateMarketStructure()
{
   BuildZonesFromSwings();
   g_ctx.regime = DetectMarketRegime();

   LogPrint(LOG_DEBUG, "Market structure updated | regime=" + RegimeToString(g_ctx.regime) +
            " | validZones=" + IntegerToString(GetValidZoneCount()));
}
void UpdateZones()
{
   UpdateZoneTouchesFromRecentBars();
   LogTopZones();
}

SignalInfo DetectLiquiditySweepSignal()
{
   SignalInfo sig;
   sig.valid             = false;
   sig.type              = SIG_NONE;
   sig.symbol            = _Symbol;
   sig.direction         = BASKET_DIR_NONE;
   sig.entryPrice        = 0.0;
   sig.stopLoss          = 0.0;
   sig.takeProfit        = 0.0;
   sig.invalidationPrice = 0.0;
   sig.confidence        = 0.0;
   sig.reason            = "";

   const int shift = 1; // closed bar only

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // ---------------------------------------------------------------
   // Bullish sweep reversal from support
   // ---------------------------------------------------------------
   int supIdx = FindBestSweepSupportZone();
   if(supIdx >= 0)
   {
  

      bool pricePatternOk = IsBullishSweepThroughSupport(g_zones[supIdx], shift);
      bool volOk          = IsSweepVolumeConfirmed(shift);
      bool regimeOk = IsSweepRegimeAllowed(BASKET_DIR_BUY);
      
      if(g_ctx.regime == REGIME_TREND_DOWN)
         regimeOk = false;
      if(pricePatternOk && volOk && regimeOk)
      {
         double entry = ask;
         double sl    = GetSweepBuyStopLoss(g_zones[supIdx], shift);
         double tp    = GetSweepBuyTakeProfit(entry, sl);

         if(sl > 0.0 && tp > entry && sl < entry)
         {
            sig.valid             = true;
            sig.type              = SIG_SWEEP_REVERSAL_BUY;
            sig.symbol            = _Symbol;
            sig.direction         = BASKET_DIR_BUY;
            sig.entryPrice        = entry;
            sig.stopLoss          = sl;
            sig.takeProfit        = tp;
            sig.invalidationPrice = iLow(_Symbol, _Period, shift);
            sig.confidence        = g_zones[supIdx].strength + 1.0;
            sig.reason            = "Sweep reversal BUY @ support zone " + IntegerToString(supIdx);

            LogPrint(LOG_INFO,
               "Sweep BUY detected | zone=" + IntegerToString(supIdx) +
               " | entry=" + DoubleToString(entry, g_ctx.digits) +
               " | sl=" + DoubleToString(sl, g_ctx.digits) +
               " | tp=" + DoubleToString(tp, g_ctx.digits));

            return sig;
         }
      }
      else
      {
         if(InpLogLevel >= LOG_DEBUG)
         {
            string why =
               "Sweep BUY rejected | zone=" + IntegerToString(supIdx) +
               " | price=" + (pricePatternOk ? "ok" : "no") +
               " | vol=" + (volOk ? "ok" : "no") +
               " | regime=" + (regimeOk ? "ok" : "no");
            LogPrint(LOG_DEBUG, why);
         }
      }
   }

   // ---------------------------------------------------------------
   // Bearish sweep reversal from resistance
   // ---------------------------------------------------------------
   int resIdx = FindBestSweepResistanceZone();
   if(resIdx >= 0)
   {
    

      bool pricePatternOk = IsBearishSweepThroughResistance(g_zones[resIdx], shift);
      bool volOk          = IsSweepVolumeConfirmed(shift);
      bool regimeOk = IsSweepRegimeAllowed(BASKET_DIR_SELL);
      
      if(g_ctx.regime == REGIME_TREND_UP)
         regimeOk = false;
      if(pricePatternOk && volOk && regimeOk)
      {
         double entry = bid;
         double sl    = GetSweepSellStopLoss(g_zones[resIdx], shift);
         double tp    = GetSweepSellTakeProfit(entry, sl);

         if(sl > entry && tp > 0.0 && tp < entry)
         {
            sig.valid             = true;
            sig.type              = SIG_SWEEP_REVERSAL_SELL;
            sig.symbol            = _Symbol;
            sig.direction         = BASKET_DIR_SELL;
            sig.entryPrice        = entry;
            sig.stopLoss          = sl;
            sig.takeProfit        = tp;
            sig.invalidationPrice = iHigh(_Symbol, _Period, shift);
            sig.confidence        = g_zones[resIdx].strength + 1.0;
            sig.reason            = "Sweep reversal SELL @ resistance zone " + IntegerToString(resIdx);

            LogPrint(LOG_INFO,
               "Sweep SELL detected | zone=" + IntegerToString(resIdx) +
               " | entry=" + DoubleToString(entry, g_ctx.digits) +
               " | sl=" + DoubleToString(sl, g_ctx.digits) +
               " | tp=" + DoubleToString(tp, g_ctx.digits));

            return sig;
         }
      }
      else
      {
         if(InpLogLevel >= LOG_DEBUG)
         {
            string why =
               "Sweep SELL rejected | zone=" + IntegerToString(resIdx) +
               " | price=" + (pricePatternOk ? "ok" : "no") +
               " | vol=" + (volOk ? "ok" : "no") +
               " | regime=" + (regimeOk ? "ok" : "no");
            LogPrint(LOG_DEBUG, why);
         }
      }
   }

   return sig;
}

SignalInfo DetectBreakoutContinuationSignal()
{
   SignalInfo sig;
   sig.valid             = false;
   sig.type              = SIG_NONE;
   sig.symbol            = _Symbol;
   sig.direction         = BASKET_DIR_NONE;
   sig.entryPrice        = 0.0;
   sig.stopLoss          = 0.0;
   sig.takeProfit        = 0.0;
   sig.invalidationPrice = 0.0;
   sig.confidence        = 0.0;
   sig.reason            = "";

   const int shift = 1; // closed bar only

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // ---------------------------------------------------------------
   // Bullish breakout through resistance
   // ---------------------------------------------------------------
   int resIdx = FindBestBreakoutResistanceZone();
   if(resIdx >= 0)
   {
     
      // breakout must occur close to zone
      double atr = GetATRSafe();
      double close1 = iClose(_Symbol, _Period, 1);
      double dist = MathAbs(close1 - GetZoneMidPrice(g_zones[resIdx]));
      if(dist > atr * 0.5)
         return sig;
      bool pricePatternOk = IsBullishBreakoutThroughResistance(g_zones[resIdx], shift);
      bool volOk          = IsBreakoutVolumeConfirmed(shift);
      bool regimeOk       = IsBreakoutRegimeAllowed(BASKET_DIR_BUY);
      bool retestOk       = DidBullishRetestHold(g_zones[resIdx]);

      if(pricePatternOk && volOk && regimeOk && retestOk)
      {
         double entry = ask;
         double sl    = GetBreakoutBuyStopLoss(g_zones[resIdx], shift);
         double tp    = GetBreakoutBuyTakeProfit(entry, sl);
         
         // Require momentum continuation
         double close2 = iClose(_Symbol, _Period, 2);
         if(close2 > close1)
            return sig;
         // News Spikes   
         double range = iHigh(_Symbol, _Period, shift) - iLow(_Symbol, _Period, shift);
         if(range > atr * 1.8)
            return sig;
         // Only in trend
         if (g_ctx.regime != REGIME_TREND_UP) {
            return sig;
         }      
         if(sl > 0.0 && tp > entry && sl < entry)
         {
            sig.valid             = true;
            sig.type              = SIG_BREAKOUT_CONT_BUY;
            sig.symbol            = _Symbol;
            sig.direction         = BASKET_DIR_BUY;
            sig.entryPrice        = entry;
            sig.stopLoss          = sl;
            sig.takeProfit        = tp;
            sig.invalidationPrice = g_zones[resIdx].lower;
            sig.confidence        = g_zones[resIdx].strength + 1.5;
            sig.reason            = "Breakout continuation BUY @ resistance zone " + IntegerToString(resIdx);

            LogPrint(LOG_INFO,
               "Breakout BUY detected | zone=" + IntegerToString(resIdx) +
               " | entry=" + DoubleToString(entry, g_ctx.digits) +
               " | sl=" + DoubleToString(sl, g_ctx.digits) +
               " | tp=" + DoubleToString(tp, g_ctx.digits));

            return sig;
         }
      }
      else
      {
         if(InpLogLevel >= LOG_DEBUG)
         {
            string why =
               "Breakout BUY rejected | zone=" + IntegerToString(resIdx) +
               " | price=" + (pricePatternOk ? "ok" : "no") +
               " | vol=" + (volOk ? "ok" : "no") +
               " | regime=" + (regimeOk ? "ok" : "no") +
               " | retest=" + (retestOk ? "ok" : "no");
            LogPrint(LOG_DEBUG, why);
         }
      }
   }

   // ---------------------------------------------------------------
   // Bearish breakout through support
   // ---------------------------------------------------------------
   int supIdx = FindBestBreakoutSupportZone();
   if(supIdx >= 0)
   {
        // breakout must occur close to zone
      double atr = GetATRSafe();
      double close1 = iClose(_Symbol, _Period, 1);
      double dist = MathAbs(close1 - GetZoneMidPrice(g_zones[resIdx]));
      if(dist > atr * 0.5)
         return sig;

      bool pricePatternOk = IsBearishBreakoutThroughSupport(g_zones[supIdx], shift);
      bool volOk          = IsBreakoutVolumeConfirmed(shift);
      bool regimeOk       = IsBreakoutRegimeAllowed(BASKET_DIR_SELL);
      bool retestOk       = DidBearishRetestHold(g_zones[supIdx]);

      if(pricePatternOk && volOk && regimeOk && retestOk)
      {
         double entry = bid;
         double sl    = GetBreakoutSellStopLoss(g_zones[supIdx], shift);
         double tp    = GetBreakoutSellTakeProfit(entry, sl);
         
          // Require momentum continuation
         double close2 = iClose(_Symbol, _Period, 2);
         if(close2 < close1)
            return sig;
         
         // News Spikes   
         double range = iHigh(_Symbol, _Period, shift) - iLow(_Symbol, _Period, shift);
         if(range > atr * 1.8)
            return sig;
            
         // Only in trend
         if (g_ctx.regime != REGIME_TREND_DOWN) {
            return sig;
         }   
         if(sl > entry && tp > 0.0 && tp < entry)
         {
            sig.valid             = true;
            sig.type              = SIG_BREAKOUT_CONT_SELL;
            sig.symbol            = _Symbol;
            sig.direction         = BASKET_DIR_SELL;
            sig.entryPrice        = entry;
            sig.stopLoss          = sl;
            sig.takeProfit        = tp;
            sig.invalidationPrice = g_zones[supIdx].upper;
            sig.confidence        = g_zones[supIdx].strength + 1.5;
            sig.reason            = "Breakout continuation SELL @ support zone " + IntegerToString(supIdx);

            LogPrint(LOG_INFO,
               "Breakout SELL detected | zone=" + IntegerToString(supIdx) +
               " | entry=" + DoubleToString(entry, g_ctx.digits) +
               " | sl=" + DoubleToString(sl, g_ctx.digits) +
               " | tp=" + DoubleToString(tp, g_ctx.digits));

            return sig;
         }
      }
      else
      {
         if(InpLogLevel >= LOG_DEBUG)
         {
            string why =
               "Breakout SELL rejected | zone=" + IntegerToString(supIdx) +
               " | price=" + (pricePatternOk ? "ok" : "no") +
               " | vol=" + (volOk ? "ok" : "no") +
               " | regime=" + (regimeOk ? "ok" : "no") +
               " | retest=" + (retestOk ? "ok" : "no");
            LogPrint(LOG_DEBUG, why);
         }
      }
   }

   return sig;
}

//==================================================================//
// EXECUTION
//==================================================================//
bool CanOpenNewBasket()
{
   RefreshBasketState(g_basket);

   if(g_basket.active)
   {
      LogPrint(LOG_DEBUG, "Existing basket already active");
      return false;
   }

   return true;
}

bool ExecuteSignal(const SignalInfo &sig)
{
   if(!sig.valid)
      return false;

   if(IsRiskLocked())
      return false;

   if(!IsBrokerTradeWindow())
   {
      LogPrint(LOG_DEBUG, "Trade window blocked");
      return false;
   }

   if(!IsSpreadOK())
      return false;

   if(!CanOpenNewBasket())
      return false;

   double entry = 0.0;
   double sl    = NormalizePrice(sig.stopLoss);
   double tp    = NormalizePrice(sig.takeProfit);

   if(sig.direction == BASKET_DIR_BUY)
      entry = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   else if(sig.direction == BASKET_DIR_SELL)
      entry = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   else
      return false;

   double stopDistance = MathAbs(entry - sl);
   double lots = CalcLotByRisk(stopDistance);

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(10);

   bool ok = false;
   if(sig.direction == BASKET_DIR_BUY && InpAllowBuy)
      ok = trade.Buy(lots, _Symbol, 0.0, sl, tp, sig.reason);
   else if(sig.direction == BASKET_DIR_SELL && InpAllowSell)
      ok = trade.Sell(lots, _Symbol, 0.0, sl, tp, sig.reason);

   if(ok)
   {
      g_lastEntrySignalType   = sig.type;
      g_lastEntryInvalidation = sig.invalidationPrice;
      g_lastEntryInitialRisk  = stopDistance;

      LogPrint(LOG_INFO,
         "Entry executed: " + sig.reason +
         " | lots=" + DoubleToString(lots, 2) +
         " | risk=" + DoubleToString(stopDistance, g_ctx.digits));
   }
   else
   {
      LogPrint(LOG_ERROR, "Entry failed. Retcode=" + IntegerToString((int)trade.ResultRetcode()));
   }

   return ok;
}

//==================================================================//
// TRADE MANAGEMENT
//==================================================================//
void ManageOpenBasket()
{
   if(!RefreshBasketState(g_basket))
      return;

   if(ShouldExitFailedSweep(g_basket))
   {
      CloseAllBasketPositions("FailedSweep");
      return;
   }

   if(ShouldExitFailedBreakout(g_basket))
   {
      CloseAllBasketPositions("FailedBreakout");
      return;
   }

   if(ShouldExitStaleTrade(g_basket))
   {
      CloseAllBasketPositions("StaleExit");
      return;
   }

   if(ShouldExitOnOppositeSignal(g_basket))
   {
      CloseAllBasketPositions("OppositeSignal");
      return;
   }

   ApplyBreakEvenIfNeeded(g_basket);
   RefreshBasketState(g_basket);

   if(InpUseTrailingBasketSL)
      ApplyTrailingStopIfNeeded(g_basket);
}

void EmergencyFlattenIfNeeded()
{
   if(!RefreshBasketState(g_basket))
      return;

   if(!IsRiskLocked())
      return;

   bool allOk = true;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;

      if(!PositionSelectByTicket(ticket))
         continue;

      string sym = PositionGetString(POSITION_SYMBOL);
      long magic = PositionGetInteger(POSITION_MAGIC);
      if(sym != _Symbol || (ulong)magic != InpMagicNumber)
         continue;

      if(!trade.PositionClose(ticket))
      {
         allOk = false;
         LogPrint(LOG_ERROR, "Emergency close failed for ticket " + IntegerToString((int)ticket));
      }
   }

   if(allOk)
   {
      g_lastEntrySignalType   = SIG_NONE;
      g_lastEntryInvalidation = 0.0;
      g_lastEntryInitialRisk  = 0.0;
   }
}

//==================================================================//
// INIT / TICK
//==================================================================//
int OnInit()
{
   ResetBasket(g_basket);
   ResetZones();

   if(!RefreshSymbolContext(g_ctx))
      return INIT_FAILED;

   RefreshRiskAnchors();

   LogPrint(LOG_INFO, "EA initialized");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   LogPrint(LOG_INFO, "EA deinitialized. Reason=" + IntegerToString(reason));
}

void OnTick()
{
   bool isNewBar = true;

   if(InpProcessOncePerBar)
   {
      isNewBar = IsNewBar();
      if(!isNewBar)
      {
         ManageOpenBasket();
         EmergencyFlattenIfNeeded();
         return;
      }
   }

   if(!RefreshSymbolContext(g_ctx))
      return;

   RefreshRiskAnchors();
   ManageOpenBasket();
   EmergencyFlattenIfNeeded();

   UpdateMarketStructure();
   UpdateZones();

   SignalInfo sweepSig    = DetectLiquiditySweepSignal();
   SignalInfo breakoutSig = DetectBreakoutContinuationSignal();

   if(RefreshBasketState(g_basket))
   {
      if(!InpGridAddsOnlyOnNewBar || isNewBar)
         TryAddToBasket(sweepSig, breakoutSig);
      return;
   }

   if(sweepSig.valid)
   {
      ExecuteSignal(sweepSig);
      return;
   }

   if(breakoutSig.valid)
   {
      ExecuteSignal(breakoutSig);
      return;
   }
}