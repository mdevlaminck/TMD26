//+------------------------------------------------------------------+
//|                                      LiquiditySweepReversal_v1   |
//+------------------------------------------------------------------+
#property strict
#property version   "1.00"

#include <Trade/Trade.mqh>

CTrade trade;

//====================================================================
// ENUMS
//====================================================================
enum ENUM_LS_DIR
{
   LS_DIR_NONE = 0,
   LS_DIR_BUY  = 1,
   LS_DIR_SELL = -1
};

enum ENUM_LS_LOG
{
   LS_LOG_ERROR = 0,
   LS_LOG_WARN  = 1,
   LS_LOG_INFO  = 2,
   LS_LOG_DEBUG = 3
};

//====================================================================
// INPUTS
//====================================================================
input group "=== General ===";
input string InpSymbols                 = "GBPUSD";
input ENUM_TIMEFRAMES InpTimeframe      = PERIOD_H1;
input long   InpMagicBase               = 2704001;

input group "=== Swing Detection ===";
input int    InpLookbackBars            = 80;
input int    InpSwingLeft               = 2;
input int    InpSwingRight              = 2;
input int    InpMinBarsFromCurrent      = 3;
input int    InpMaxSwingAgeBars         = 30;
input double InpMinProminenceATR        = 0.20;

input group "=== Sweep Logic ===";
input double InpMinSweepATR             = 0.05;
input double InpMaxSweepATR             = 0.40;
input bool   InpAllowSameBarReclaim     = true;

input group "=== Risk / Exit ===";
input double InpRiskPercent             = 0.50;
input double InpSLBufferATR             = 0.10;
input double InpTargetRR                = 2.0;

input group "=== Management ===";
input double InpBreakEvenAtR            = 1.00;
input int    InpBreakEvenOffsetPts      = 5;
input double InpTrailStartAtR           = 1.50;
input double InpTrailATRMult            = 1.20;

input group "=== Filters ===";
input int    InpMaxSpreadPoints         = 30;
input int    InpCooldownBars            = 8;

input group "=== Logging ===";
input ENUM_LS_LOG InpLogLevel           = LS_LOG_INFO;

//====================================================================
// STRUCTS
//====================================================================
struct SwingPoint
{
   bool     valid;
   bool     isHigh;
   int      barIndex;
   datetime barTime;
   double   price;
   double   prominenceAtr;
};

struct PositionState
{
   bool     active;
   ulong    ticket;
   int      direction;
   double   entry;
   double   initialSL;
   double   initialTP;
   bool     beApplied;
   bool     trailActive;
};

struct SymbolContext
{
   string        symbol;
   bool          enabled;
   bool          tradable;
   datetime      lastBarTime;
   double        atrPrice;
   double        spreadPoints;

   SwingPoint    swingHigh;
   SwingPoint    swingLow;

   int           cooldownBuyBars;
   int           cooldownSellBars;

   PositionState posBuy;
   PositionState posSell;
};

SymbolContext g_ctx[];
string g_symbols[];
int g_symbol_count = 0;

//====================================================================
// LOGGING
//====================================================================
void LogMsg(const ENUM_LS_LOG lvl,
            const string tag,
            const string symbol,
            const int dir,
            const string msg)
{
   if((int)lvl > (int)InpLogLevel)
      return;

   string sLvl = "INFO";
   if(lvl == LS_LOG_ERROR) sLvl = "ERROR";
   else if(lvl == LS_LOG_WARN) sLvl = "WARN";
   else if(lvl == LS_LOG_DEBUG) sLvl = "DEBUG";

   string sDir = "NONE";
   if(dir == LS_DIR_BUY) sDir = "BUY";
   else if(dir == LS_DIR_SELL) sDir = "SELL";

   Print(sLvl, " | ", tag, " | ", symbol, " | ", EnumToString(InpTimeframe), " | ", sDir, " | ", msg);
}

//====================================================================
// HELPERS
//====================================================================
double PointValue(const string symbol)
{
   return SymbolInfoDouble(symbol, SYMBOL_POINT);
}

int DigitsValue(const string symbol)
{
   return (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
}

double NormalizePrice(const string symbol, const double price)
{
   return NormalizeDouble(price, DigitsValue(symbol));
}

double PointsToPrice(const string symbol, const double points)
{
   return points * PointValue(symbol);
}

double PriceToPoints(const string symbol, const double priceDist)
{
   double pt = PointValue(symbol);
   if(pt <= 0.0)
      return 0.0;
   return priceDist / pt;
}

double CurrentSpreadPoints(const string symbol)
{
   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   if(ask <= 0.0 || bid <= 0.0 || ask < bid)
      return 999999.0;
   return PriceToPoints(symbol, ask - bid);
}

bool IsTradableSymbol(const string symbol)
{
   if(!SymbolSelect(symbol, true))
      return false;

   long mode = 0;
   if(!SymbolInfoInteger(symbol, SYMBOL_TRADE_MODE, mode))
      return false;

   return (mode == SYMBOL_TRADE_MODE_FULL ||
           mode == SYMBOL_TRADE_MODE_LONGONLY ||
           mode == SYMBOL_TRADE_MODE_SHORTONLY);
}

bool GetRates(const string symbol, MqlRates &rates[], const int count)
{
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(symbol, InpTimeframe, 0, count, rates);
   return (copied == count);
}

double GetATRPrice(const string symbol, const int period = 14)
{
   int handle = iATR(symbol, InpTimeframe, period);
   if(handle == INVALID_HANDLE)
      return 0.0;

   double buf[];
   ArraySetAsSeries(buf, true);
   double v = 0.0;

   if(CopyBuffer(handle, 0, 0, 2, buf) >= 1)
      v = buf[0];

   IndicatorRelease(handle);
   return v;
}

bool IsNewBar(const int idx)
{
   if(idx < 0 || idx >= ArraySize(g_ctx))
      return false;

   datetime t[1];
   if(CopyTime(g_ctx[idx].symbol, InpTimeframe, 0, 1, t) != 1)
      return false;

   if(g_ctx[idx].lastBarTime == 0)
   {
      g_ctx[idx].lastBarTime = t[0];
      return true;
   }

   if(t[0] != g_ctx[idx].lastBarTime)
   {
      g_ctx[idx].lastBarTime = t[0];
      return true;
   }

   return false;
}

int CountOpenEaPositions()
{
   int cnt = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(!PositionSelectByTicket(ticket))
         continue;
      long magic = PositionGetInteger(POSITION_MAGIC);
      if(magic == InpMagicBase)
         cnt++;
   }
   return cnt;
}

//====================================================================
// SWINGS
//====================================================================
bool IsSwingHigh(MqlRates &rates[], const int i, const int left, const int right)
{
   double p = rates[i].high;

   for(int k = 1; k <= left; k++)
      if(rates[i + k].high >= p)
         return false;

   for(int k = 1; k <= right; k++)
      if(rates[i - k].high > p)
         return false;

   return true;
}

bool IsSwingLow(MqlRates &rates[], const int i, const int left, const int right)
{
   double p = rates[i].low;

   for(int k = 1; k <= left; k++)
      if(rates[i + k].low <= p)
         return false;

   for(int k = 1; k <= right; k++)
      if(rates[i - k].low < p)
         return false;

   return true;
}

double CalcSwingProminenceATR(MqlRates &rates[], const SwingPoint &sp, const double atrPrice)
{
   if(!sp.valid || atrPrice <= 0.0)
      return 0.0;

   int leftSpan  = MathMin(4, ArraySize(rates) - sp.barIndex - 1);
   int rightSpan = MathMin(4, sp.barIndex - 1);

   if(leftSpan < 1 || rightSpan < 1)
      return 0.0;

   if(sp.isHigh)
   {
      double sideMax = -DBL_MAX;
      for(int k = 1; k <= leftSpan; k++)
         sideMax = MathMax(sideMax, rates[sp.barIndex + k].high);
      for(int k = 1; k <= rightSpan; k++)
         sideMax = MathMax(sideMax, rates[sp.barIndex - k].high);

      return (sp.price - sideMax) / atrPrice;
   }
   else
   {
      double sideMin = DBL_MAX;
      for(int k = 1; k <= leftSpan; k++)
         sideMin = MathMin(sideMin, rates[sp.barIndex + k].low);
      for(int k = 1; k <= rightSpan; k++)
         sideMin = MathMin(sideMin, rates[sp.barIndex - k].low);

      return (sideMin - sp.price) / atrPrice;
   }
}

SwingPoint FindLatestValidSwingHigh(const string symbol, MqlRates &rates[], const double atrPrice)
{
   SwingPoint sp;
   ZeroMemory(sp);
   sp.valid = false;
   sp.isHigh = true;

   int start = InpSwingRight + 1;
   int end   = MathMin(InpLookbackBars, ArraySize(rates) - InpSwingLeft - 2);

   int bestBar = 999999;

   for(int i = start; i <= end; i++)
   {
      if(!IsSwingHigh(rates, i, InpSwingLeft, InpSwingRight))
         continue;

      if(i < InpMinBarsFromCurrent)
         continue;

      if(i > InpMaxSwingAgeBars)
         continue;

      SwingPoint tmp;
      ZeroMemory(tmp);
      tmp.valid = true;
      tmp.isHigh = true;
      tmp.barIndex = i;
      tmp.barTime = rates[i].time;
      tmp.price = rates[i].high;
      tmp.prominenceAtr = CalcSwingProminenceATR(rates, tmp, atrPrice);

      if(tmp.prominenceAtr < InpMinProminenceATR)
         continue;

      if(i < bestBar)
      {
         sp = tmp;
         bestBar = i;
      }
   }

   return sp;
}

SwingPoint FindLatestValidSwingLow(const string symbol, MqlRates &rates[], const double atrPrice)
{
   SwingPoint sp;
   ZeroMemory(sp);
   sp.valid = false;
   sp.isHigh = false;

   int start = InpSwingRight + 1;
   int end   = MathMin(InpLookbackBars, ArraySize(rates) - InpSwingLeft - 2);

   int bestBar = 999999;

   for(int i = start; i <= end; i++)
   {
      if(!IsSwingLow(rates, i, InpSwingLeft, InpSwingRight))
         continue;

      if(i < InpMinBarsFromCurrent)
         continue;

      if(i > InpMaxSwingAgeBars)
         continue;

      SwingPoint tmp;
      ZeroMemory(tmp);
      tmp.valid = true;
      tmp.isHigh = false;
      tmp.barIndex = i;
      tmp.barTime = rates[i].time;
      tmp.price = rates[i].low;
      tmp.prominenceAtr = CalcSwingProminenceATR(rates, tmp, atrPrice);

      if(tmp.prominenceAtr < InpMinProminenceATR)
         continue;

      if(i < bestBar)
      {
         sp = tmp;
         bestBar = i;
      }
   }

   return sp;
}

//====================================================================
// POSITION STATE
//====================================================================
void ClearPosState(PositionState &st)
{
   ZeroMemory(st);
}

void SyncPositionState(const int idx, const int dir)
{
   if(idx < 0 || idx >= ArraySize(g_ctx))
      return;

   if(dir == LS_DIR_BUY)
      ClearPosState(g_ctx[idx].posBuy);
   else if(dir == LS_DIR_SELL)
      ClearPosState(g_ctx[idx].posSell);
   else
      return;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;

      if(!PositionSelectByTicket(ticket))
         continue;

      string symbol = PositionGetString(POSITION_SYMBOL);
      if(symbol != g_ctx[idx].symbol)
         continue;

      long magic = PositionGetInteger(POSITION_MAGIC);
      if(magic != InpMagicBase)
         continue;

      ENUM_POSITION_TYPE pt = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

      if(dir == LS_DIR_BUY && pt != POSITION_TYPE_BUY)
         continue;
      if(dir == LS_DIR_SELL && pt != POSITION_TYPE_SELL)
         continue;

      string comment = PositionGetString(POSITION_COMMENT);

      string slStr, tpStr;
      if(dir == LS_DIR_BUY)
      {
         g_ctx[idx].posBuy.active = true;
         g_ctx[idx].posBuy.ticket = ticket;
         g_ctx[idx].posBuy.direction = dir;
         g_ctx[idx].posBuy.entry = PositionGetDouble(POSITION_PRICE_OPEN);

         if(ExtractField(comment, "SL=", slStr))
            g_ctx[idx].posBuy.initialSL = StringToDouble(slStr);
         if(ExtractField(comment, "TP=", tpStr))
            g_ctx[idx].posBuy.initialTP = StringToDouble(tpStr);

         double curSL = PositionGetDouble(POSITION_SL);
         if(g_ctx[idx].posBuy.initialSL > 0.0 && curSL >= g_ctx[idx].posBuy.entry)
            g_ctx[idx].posBuy.beApplied = true;
         if(g_ctx[idx].posBuy.beApplied)
            g_ctx[idx].posBuy.trailActive = true;
      }
      else
      {
         g_ctx[idx].posSell.active = true;
         g_ctx[idx].posSell.ticket = ticket;
         g_ctx[idx].posSell.direction = dir;
         g_ctx[idx].posSell.entry = PositionGetDouble(POSITION_PRICE_OPEN);

         if(ExtractField(comment, "SL=", slStr))
            g_ctx[idx].posSell.initialSL = StringToDouble(slStr);
         if(ExtractField(comment, "TP=", tpStr))
            g_ctx[idx].posSell.initialTP = StringToDouble(tpStr);

         double curSL = PositionGetDouble(POSITION_SL);
         if(g_ctx[idx].posSell.initialSL > 0.0 && curSL > 0.0 && curSL <= g_ctx[idx].posSell.entry)
            g_ctx[idx].posSell.beApplied = true;
         if(g_ctx[idx].posSell.beApplied)
            g_ctx[idx].posSell.trailActive = true;
      }

      return;
   }
}

bool ExtractField(const string src, const string key, string &value)
{
   int pos = StringFind(src, key);
   if(pos < 0)
      return false;

   int from = pos + StringLen(key);
   int next = StringFind(src, "|", from);
   if(next < 0)
      next = StringLen(src);

   value = StringSubstr(src, from, next - from);
   return true;
}

//====================================================================
// RISK / EXECUTION
//====================================================================
double NormalizeVolumeToStep(const string symbol, double lots)
{
   double volMin  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double volMax  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double volStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);

   if(volStep <= 0.0)
      volStep = 0.01;

   lots = MathMax(volMin, MathMin(volMax, lots));
   lots = MathFloor(lots / volStep) * volStep;
   lots = NormalizeDouble(lots, 2);

   return lots;
}

double CalcLotsByRisk(const string symbol, const double entry, const double sl)
{
   double riskMoney = AccountInfoDouble(ACCOUNT_BALANCE) * (InpRiskPercent / 100.0);
   if(riskMoney <= 0.0)
      return 0.0;

   double tickSize  = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tickSize <= 0.0 || tickValue <= 0.0)
      return 0.0;

   double stopDist = MathAbs(entry - sl);
   if(stopDist <= 0.0)
      return 0.0;

   double ticks = stopDist / tickSize;
   double moneyPerLot = ticks * tickValue;
   if(moneyPerLot <= 0.0)
      return 0.0;

   double lots = riskMoney / moneyPerLot;
   return NormalizeVolumeToStep(symbol, lots);
}

string MakeComment(const int dir, const double initSL, const double initTP)
{
   return "LSR|D=" + IntegerToString(dir) +
          "|SL=" + DoubleToString(initSL, 8) +
          "|TP=" + DoubleToString(initTP, 8);
}

bool OpenBuy(const string symbol, const double sl, const double tp)
{
   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
   double lots = CalcLotsByRisk(symbol, ask, sl);
   if(lots <= 0.0)
      return false;

   trade.SetExpertMagicNumber(InpMagicBase);
   string comment = MakeComment(LS_DIR_BUY, sl, tp);
   return trade.Buy(lots, symbol, 0.0, sl, tp, comment);
}

bool OpenSell(const string symbol, const double sl, const double tp)
{
   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   double lots = CalcLotsByRisk(symbol, bid, sl);
   if(lots <= 0.0)
      return false;

   trade.SetExpertMagicNumber(InpMagicBase);
   string comment = MakeComment(LS_DIR_SELL, sl, tp);
   return trade.Sell(lots, symbol, 0.0, sl, tp, comment);
}

//====================================================================
// SWEEP DETECTION
//====================================================================
bool DetectShortSweep(const int idx, MqlRates &rates[], double &sweepHigh)
{
   if(!g_ctx[idx].swingHigh.valid)
      return false;

   int sweepBar = 1;
   double level = g_ctx[idx].swingHigh.price;
   double atr   = g_ctx[idx].atrPrice;

   double extension = rates[sweepBar].high - level;
   if(extension < atr * InpMinSweepATR)
      return false;

   if(extension > atr * InpMaxSweepATR)
      return false;

   bool reclaimed = false;

   if(InpAllowSameBarReclaim && rates[sweepBar].close < level)
      reclaimed = true;
   else if(rates[2].high > level && rates[1].close < level)
      reclaimed = true;

   if(!reclaimed)
      return false;

   sweepHigh = rates[sweepBar].high;
   return true;
}

bool DetectLongSweep(const int idx, MqlRates &rates[], double &sweepLow)
{
   if(!g_ctx[idx].swingLow.valid)
      return false;

   int sweepBar = 1;
   double level = g_ctx[idx].swingLow.price;
   double atr   = g_ctx[idx].atrPrice;

   double extension = level - rates[sweepBar].low;
   if(extension < atr * InpMinSweepATR)
      return false;

   if(extension > atr * InpMaxSweepATR)
      return false;

   bool reclaimed = false;

   if(InpAllowSameBarReclaim && rates[sweepBar].close > level)
      reclaimed = true;
   else if(rates[2].low < level && rates[1].close > level)
      reclaimed = true;

   if(!reclaimed)
      return false;

   sweepLow = rates[sweepBar].low;
   return true;
}

//====================================================================
// SCAN
//====================================================================
void ScanSwings(const int idx)
{
   if(idx < 0 || idx >= ArraySize(g_ctx))
      return;

   MqlRates rates[];
   int need = InpLookbackBars + InpSwingLeft + InpSwingRight + 20;

   if(!GetRates(g_ctx[idx].symbol, rates, need))
   {
      LogMsg(LS_LOG_WARN, "SCAN", g_ctx[idx].symbol, LS_DIR_NONE, "failed to copy rates");
      return;
   }

   g_ctx[idx].atrPrice = GetATRPrice(g_ctx[idx].symbol, 14);
   if(g_ctx[idx].atrPrice <= 0.0)
      return;

   g_ctx[idx].swingHigh = FindLatestValidSwingHigh(g_ctx[idx].symbol, rates, g_ctx[idx].atrPrice);
   g_ctx[idx].swingLow  = FindLatestValidSwingLow(g_ctx[idx].symbol, rates, g_ctx[idx].atrPrice);

   if(g_ctx[idx].swingHigh.valid)
   {
      LogMsg(LS_LOG_INFO, "LEVEL", g_ctx[idx].symbol, LS_DIR_SELL,
             "swing high price=" + DoubleToString(g_ctx[idx].swingHigh.price, DigitsValue(g_ctx[idx].symbol)) +
             " age=" + IntegerToString(g_ctx[idx].swingHigh.barIndex) +
             " promATR=" + DoubleToString(g_ctx[idx].swingHigh.prominenceAtr, 2));
   }

   if(g_ctx[idx].swingLow.valid)
   {
      LogMsg(LS_LOG_INFO, "LEVEL", g_ctx[idx].symbol, LS_DIR_BUY,
             "swing low price=" + DoubleToString(g_ctx[idx].swingLow.price, DigitsValue(g_ctx[idx].symbol)) +
             " age=" + IntegerToString(g_ctx[idx].swingLow.barIndex) +
             " promATR=" + DoubleToString(g_ctx[idx].swingLow.prominenceAtr, 2));
   }
}

//====================================================================
// ENTRY HANDLERS
//====================================================================
void TryEnterShort(const int idx)
{
   if(idx < 0 || idx >= ArraySize(g_ctx))
      return;

   if(g_ctx[idx].posSell.active)
      return;

   if(g_ctx[idx].cooldownSellBars > 0)
      return;

   if(CurrentSpreadPoints(g_ctx[idx].symbol) > InpMaxSpreadPoints)
      return;

   MqlRates rates[];
   int need = 10;
   if(!GetRates(g_ctx[idx].symbol, rates, need))
      return;

   double sweepHigh = 0.0;
   if(!DetectShortSweep(idx, rates, sweepHigh))
      return;

   double bid = SymbolInfoDouble(g_ctx[idx].symbol, SYMBOL_BID);
   double sl  = NormalizePrice(g_ctx[idx].symbol, sweepHigh + g_ctx[idx].atrPrice * InpSLBufferATR);

   if(sl <= bid)
      return;

   double risk = sl - bid;
   double tp   = NormalizePrice(g_ctx[idx].symbol, bid - risk * InpTargetRR);

   if(OpenSell(g_ctx[idx].symbol, sl, tp))
   {
      g_ctx[idx].cooldownSellBars = InpCooldownBars;
      LogMsg(LS_LOG_INFO, "ENTRY", g_ctx[idx].symbol, LS_DIR_SELL,
             "short entered after high sweep bid=" + DoubleToString(bid, DigitsValue(g_ctx[idx].symbol)) +
             " sl=" + DoubleToString(sl, DigitsValue(g_ctx[idx].symbol)) +
             " tp=" + DoubleToString(tp, DigitsValue(g_ctx[idx].symbol)));
   }
   else
   {
      LogMsg(LS_LOG_ERROR, "ENTRY", g_ctx[idx].symbol, LS_DIR_SELL,
             "sell failed retcode=" + IntegerToString((int)trade.ResultRetcode()) +
             " msg=" + trade.ResultRetcodeDescription());
   }
}

void TryEnterLong(const int idx)
{
   if(idx < 0 || idx >= ArraySize(g_ctx))
      return;

   if(g_ctx[idx].posBuy.active)
      return;

   if(g_ctx[idx].cooldownBuyBars > 0)
      return;

   if(CurrentSpreadPoints(g_ctx[idx].symbol) > InpMaxSpreadPoints)
      return;

   MqlRates rates[];
   int need = 10;
   if(!GetRates(g_ctx[idx].symbol, rates, need))
      return;

   double sweepLow = 0.0;
   if(!DetectLongSweep(idx, rates, sweepLow))
      return;

   double ask = SymbolInfoDouble(g_ctx[idx].symbol, SYMBOL_ASK);
   double sl  = NormalizePrice(g_ctx[idx].symbol, sweepLow - g_ctx[idx].atrPrice * InpSLBufferATR);

   if(sl >= ask)
      return;

   double risk = ask - sl;
   double tp   = NormalizePrice(g_ctx[idx].symbol, ask + risk * InpTargetRR);

   if(OpenBuy(g_ctx[idx].symbol, sl, tp))
   {
      g_ctx[idx].cooldownBuyBars = InpCooldownBars;
      LogMsg(LS_LOG_INFO, "ENTRY", g_ctx[idx].symbol, LS_DIR_BUY,
             "long entered after low sweep ask=" + DoubleToString(ask, DigitsValue(g_ctx[idx].symbol)) +
             " sl=" + DoubleToString(sl, DigitsValue(g_ctx[idx].symbol)) +
             " tp=" + DoubleToString(tp, DigitsValue(g_ctx[idx].symbol)));
   }
   else
   {
      LogMsg(LS_LOG_ERROR, "ENTRY", g_ctx[idx].symbol, LS_DIR_BUY,
             "buy failed retcode=" + IntegerToString((int)trade.ResultRetcode()) +
             " msg=" + trade.ResultRetcodeDescription());
   }
}

//====================================================================
// MANAGEMENT
//====================================================================
void ManageBuyPosition(const int idx)
{
   if(!g_ctx[idx].posBuy.active)
      return;
   if(!PositionSelectByTicket(g_ctx[idx].posBuy.ticket))
      return;

   double bid   = SymbolInfoDouble(g_ctx[idx].symbol, SYMBOL_BID);
   double curSL = PositionGetDouble(POSITION_SL);
   double curTP = PositionGetDouble(POSITION_TP);

   if(g_ctx[idx].posBuy.initialSL <= 0.0 || g_ctx[idx].posBuy.entry <= 0.0)
      return;

   double risk = g_ctx[idx].posBuy.entry - g_ctx[idx].posBuy.initialSL;
   if(risk <= 0.0)
      return;

   double currentR = (bid - g_ctx[idx].posBuy.entry) / risk;

   if(!g_ctx[idx].posBuy.beApplied && currentR >= InpBreakEvenAtR)
   {
      double newSL = NormalizePrice(g_ctx[idx].symbol,
                                    g_ctx[idx].posBuy.entry + PointsToPrice(g_ctx[idx].symbol, InpBreakEvenOffsetPts));

      if(newSL > curSL && trade.PositionModify(g_ctx[idx].symbol, newSL, curTP))
      {
         g_ctx[idx].posBuy.beApplied = true;
         LogMsg(LS_LOG_INFO, "MGMT", g_ctx[idx].symbol, LS_DIR_BUY,
                "BE applied newSL=" + DoubleToString(newSL, DigitsValue(g_ctx[idx].symbol)));
      }
   }

   if(currentR >= InpTrailStartAtR)
      g_ctx[idx].posBuy.trailActive = true;

   if(!g_ctx[idx].posBuy.trailActive)
      return;

   double newSL = NormalizePrice(g_ctx[idx].symbol, bid - g_ctx[idx].atrPrice * InpTrailATRMult);
   if(newSL > curSL && newSL < bid)
   {
      if(trade.PositionModify(g_ctx[idx].symbol, newSL, curTP))
      {
         LogMsg(LS_LOG_INFO, "MGMT", g_ctx[idx].symbol, LS_DIR_BUY,
                "trail updated newSL=" + DoubleToString(newSL, DigitsValue(g_ctx[idx].symbol)));
      }
   }
}

void ManageSellPosition(const int idx)
{
   if(!g_ctx[idx].posSell.active)
      return;
   if(!PositionSelectByTicket(g_ctx[idx].posSell.ticket))
      return;

   double ask   = SymbolInfoDouble(g_ctx[idx].symbol, SYMBOL_ASK);
   double curSL = PositionGetDouble(POSITION_SL);
   double curTP = PositionGetDouble(POSITION_TP);

   if(g_ctx[idx].posSell.initialSL <= 0.0 || g_ctx[idx].posSell.entry <= 0.0)
      return;

   double risk = g_ctx[idx].posSell.initialSL - g_ctx[idx].posSell.entry;
   if(risk <= 0.0)
      return;

   double currentR = (g_ctx[idx].posSell.entry - ask) / risk;

   if(!g_ctx[idx].posSell.beApplied && currentR >= InpBreakEvenAtR)
   {
      double newSL = NormalizePrice(g_ctx[idx].symbol,
                                    g_ctx[idx].posSell.entry - PointsToPrice(g_ctx[idx].symbol, InpBreakEvenOffsetPts));

      if((curSL == 0.0 || newSL < curSL) && newSL > 0.0)
      {
         if(trade.PositionModify(g_ctx[idx].symbol, newSL, curTP))
         {
            g_ctx[idx].posSell.beApplied = true;
            LogMsg(LS_LOG_INFO, "MGMT", g_ctx[idx].symbol, LS_DIR_SELL,
                   "BE applied newSL=" + DoubleToString(newSL, DigitsValue(g_ctx[idx].symbol)));
         }
      }
   }

   if(currentR >= InpTrailStartAtR)
      g_ctx[idx].posSell.trailActive = true;

   if(!g_ctx[idx].posSell.trailActive)
      return;

   double newSL = NormalizePrice(g_ctx[idx].symbol, ask + g_ctx[idx].atrPrice * InpTrailATRMult);
   if((curSL == 0.0 || newSL < curSL) && newSL > ask)
   {
      if(trade.PositionModify(g_ctx[idx].symbol, newSL, curTP))
      {
         LogMsg(LS_LOG_INFO, "MGMT", g_ctx[idx].symbol, LS_DIR_SELL,
                "trail updated newSL=" + DoubleToString(newSL, DigitsValue(g_ctx[idx].symbol)));
      }
   }
}

//====================================================================
// INIT
//====================================================================
string Trim(const string s)
{
   string x = s;
   StringTrimLeft(x);
   StringTrimRight(x);
   return x;
}

bool ParseSymbols()
{
   string parts[];
   int n = StringSplit(InpSymbols, ',', parts);
   if(n <= 0)
      return false;

   ArrayResize(g_symbols, 0);

   for(int i = 0; i < n; i++)
   {
      string sym = Trim(parts[i]);
      if(sym == "")
         continue;

      int sz = ArraySize(g_symbols);
      ArrayResize(g_symbols, sz + 1);
      g_symbols[sz] = sym;
   }

   g_symbol_count = ArraySize(g_symbols);
   return (g_symbol_count > 0);
}

int OnInit()
{
   if(!ParseSymbols())
      return INIT_FAILED;

   ArrayResize(g_ctx, g_symbol_count);

   for(int i = 0; i < g_symbol_count; i++)
   {
      ZeroMemory(g_ctx[i]);
      g_ctx[i].symbol   = g_symbols[i];
      g_ctx[i].enabled  = true;
      g_ctx[i].tradable = IsTradableSymbol(g_ctx[i].symbol);

      LogMsg(LS_LOG_INFO, "INIT", g_ctx[i].symbol, LS_DIR_NONE,
             (g_ctx[i].tradable ? "initialized" : "not tradable"));
   }

   trade.SetExpertMagicNumber(InpMagicBase);
   return INIT_SUCCEEDED;
}

//====================================================================
// TICK
//====================================================================
void OnTick()
{
   for(int i = 0; i < g_symbol_count; i++)
   {
      if(!g_ctx[i].enabled || !g_ctx[i].tradable)
         continue;

      g_ctx[i].spreadPoints = CurrentSpreadPoints(g_ctx[i].symbol);
      g_ctx[i].atrPrice     = GetATRPrice(g_ctx[i].symbol, 14);

      SyncPositionState(i, LS_DIR_BUY);
      SyncPositionState(i, LS_DIR_SELL);

      ManageBuyPosition(i);
      ManageSellPosition(i);

      bool newBar = IsNewBar(i);
      if(!newBar)
         continue;

      if(g_ctx[i].cooldownBuyBars > 0)
         g_ctx[i].cooldownBuyBars--;
      if(g_ctx[i].cooldownSellBars > 0)
         g_ctx[i].cooldownSellBars--;

      ScanSwings(i);

      SyncPositionState(i, LS_DIR_BUY);
      SyncPositionState(i, LS_DIR_SELL);

      if(CountOpenEaPositions() < 6)
      {
         TryEnterLong(i);
         SyncPositionState(i, LS_DIR_BUY);

         TryEnterShort(i);
         SyncPositionState(i, LS_DIR_SELL);
      }
   }
}