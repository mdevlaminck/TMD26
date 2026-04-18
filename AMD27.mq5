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
input string InpSymbols                 = "AUDCAD,AUDCHF,AUDNZD,AUDUSD,CADCHF,CADJPY,CHFJPY,EURAUD,EURCAD,EURCHF,EURGBP,EURUSD,GBPCAD,GBPCHF,NZDCAD,NZDCHF,NZDUSD,USDCAD,USDCHF,USDJPY";

input group "=== Trading Window ==="
input int    InpServerStartHour         = 8;
input int    InpServerEndHour           = 22;
input int    InpCooldownMinutesAfterSL  = 5;
input bool   InpBlockJuly               = true;
input bool   InpBlockYearEndHoliday     = true;
input int    InpHolidayStartMonth       = 12;
input int    InpHolidayStartDay         = 20;
input int    InpHolidayEndMonth         = 1;
input int    InpHolidayEndDay           = 10;

input group "=== Order Placement ==="
input double InpLots                    = 0.10;
input int    InpMaxSpreadPips           = 3;
input bool   InpCancelOppositeOnFill    = true;
input bool   InpReplacePendingOnChange  = true;
input int    InpEntryBufferPoints       = 0;
input int    InpMinStopDistancePips     = 5;

input group "=== Lot Sizing ==="
input ENUM_RISK_MODE InpRiskMode        = RISK_HIGH;
input double InpRiskLowPct              = 0.12;
input double InpRiskMedPct              = 0.20;
input double InpRiskHighPct             = 0.35;
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

input group "=== News Filter ==="
input bool   InpUseNewsFilter              = true;
input int    InpNewsCacheMinutes           = 15;
input int    InpNewsLookaheadHours         = 48;
input int    InpCloseProfitBeforeNewsHours = 12;
input bool   InpCloseProfitBeforeNews      = true;
input int    InpBlockNewTier1BeforeHours   = 24;
input int    InpBlockNewTier1AfterHours    = 6;
input int    InpBlockAddTier1BeforeHours   = 12;
input int    InpBlockAddTier1AfterHours    = 12;
input int    InpBlockNewHighBeforeHours    = 3;
input int    InpBlockNewHighAfterHours     = 3;
input int    InpBlockAddHighBeforeHours    = 1;
input int    InpBlockAddHighAfterHours     = 3;

input group "=== Forex Factory CSV Fallback ==="
input bool   InpUseFFCsvFallback           = true;
input string InpFFCsvUrl                   = "https://nfs.faireconomy.media/ff_calendar_thisweek.csv";
input int    InpFFCsvTimeoutMs             = 8000;
input int    InpFFCsvRefreshMinutes        = 180;
input int    InpFFCsvTimeShiftMinutes      = 0;
input bool   InpFFCsvUseCommonFiles        = true;
input string InpFFCsvFilePrefix            = "HOLO_FF_";
input bool   InpUseTesterArchivedFFCsv      = true;
input int    InpTesterFFCsvWeeksAhead       = 1;

input group "=== ATR Spike Filter ==="
input bool            InpUseAtrSpikeFilter   = true;
input ENUM_TIMEFRAMES InpAtrSpikeTF          = PERIOD_H1;
input int             InpAtrSpikePeriod      = 14;
input int             InpAtrSpikeAvgPeriod   = 20;
input double          InpAtrSpikeBlockNew    = 1.50;
input double          InpAtrSpikeBlockAdd    = 1.30;
input double          InpImpulseBarRangeAtr  = 1.20;

input group "=== Grid Basket ==="
input bool   InpUseGridBasket           = true;
input int    InpGridGapPips             = 20;
input int    InpGridMaxLevels           = 10;
input double InpGridLotMultiplier       = 1.00;
input double InpGridTakeProfitPctPrice  = 0.10;   
input bool   InpGridUseAnchorHardStop   = false;
input bool   InpGridUseBasketTrail      = true;
input double InpGridTrailArmPctTarget   = 60.0;
input double InpGridTrailRetracePctPeak = 35.0;
input int    InpBasketProfitCloseMinOrders = 8;

input int    InpMaxConcurrentBaskets    = 5;
input double InpMaxOtherBasketDDPctBal  = 10.00;
input bool   InpBlockSharedCurrencies   = true;
input bool   InpUseCorrelationGate      = true;
input int    InpCorrelationBars         = 96;
input double InpMaxAbsCorrelation       = 0.65;
input int    InpExposureLogTriggerCount = 4;

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
datetime g_newsCacheValidUntil = 0;
bool     g_newsLiveCalendarOk  = false;
string g_lastSLReason = "-";
double g_maxGlobalDdMoney = 0.0;
double g_maxGlobalDdPct   = 0.0;
double g_closedBasketAgeHoursSum = 0.0;
int    g_closedBasketAgeCount    = 0;

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
   int    atrSpikeHandle;
   double atrFast;
   double atrSlow;
   double atrSpikeRatio;
   double curTfRangeAtr;
   bool   atrSpikeBlockNew;
   bool   atrSpikeBlockAdd;
   bool   newsBlockNew;
   bool   newsBlockAdd;
   bool   newsHasUpcoming;
   bool   newsUseFallback;
   string newsSource;
   datetime nextNewsTime;
   string nextNewsTitle;
   string nextNewsTag;
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
   bool   newsBlockNew;
   bool   atrSpikeBlockNew;
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
BasketState g_baskets[];

struct HOLO_FallbackNewsEvent
{
   datetime time;
   string   currency;
   string   title;
   bool     tier1;
};

int HoloGetFallbackNewsEvents(HOLO_FallbackNewsEvent &events[])
{
   ArrayResize(events, 0);
   return 0;
}

struct FFCsvNewsEvent
{
   datetime time;
   string   currency;
   string   title;
   bool     tier1;
   string   impact;
};

FFCsvNewsEvent g_ffCsvEvents[];
datetime g_ffCsvLastFetch = 0;
string   g_ffCsvLastFile  = "";

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
      g_states[idx].atrSpikeHandle = (InpUseAtrSpikeFilter ? iATR(sym, InpAtrSpikeTF, InpAtrSpikePeriod) : INVALID_HANDLE);
      g_states[idx].dailyHigh     = 0.0;
      g_states[idx].dailyLow      = 0.0;
      g_states[idx].yesterdayHigh = 0.0;
      g_states[idx].yesterdayLow  = 0.0;
      g_states[idx].hoH1          = 0.0;
      g_states[idx].loH1          = 0.0;
      g_states[idx].rangeAtrPct   = 0.0;
      g_states[idx].atrFast       = 0.0;
      g_states[idx].atrSlow       = 0.0;
      g_states[idx].atrSpikeRatio = 0.0;
      g_states[idx].curTfRangeAtr = 0.0;
      g_states[idx].atrSpikeBlockNew = false;
      g_states[idx].atrSpikeBlockAdd = false;
      g_states[idx].newsBlockNew  = false;
      g_states[idx].newsBlockAdd  = false;
      g_states[idx].newsHasUpcoming = false;
      g_states[idx].newsUseFallback = false;
      g_states[idx].nextNewsTime  = 0;
      g_states[idx].nextNewsTitle = "";
      g_states[idx].nextNewsTag   = "";
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
      if(g_states[i].atrSpikeHandle != INVALID_HANDLE)
         IndicatorRelease(g_states[i].atrSpikeHandle);
      g_states[i].atrHandle = INVALID_HANDLE;
      g_states[i].atrSpikeHandle = INVALID_HANDLE;
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
   MqlDateTime tm;
   TimeToStruct(TimeTradeServer(), tm);

   if(InpBlockJuly && tm.mon == 7)
      return false;

   if(InpBlockYearEndHoliday)
   {
      bool inStart = (tm.mon == InpHolidayStartMonth && tm.day >= InpHolidayStartDay);
      bool inEnd   = (tm.mon == InpHolidayEndMonth   && tm.day <= InpHolidayEndDay);
      if(inStart || inEnd)
         return false;
   }

   int h = tm.hour;
   return (h >= InpServerStartHour && h < InpServerEndHour);
}

bool IsCooldownActive()
{
   return (g_cooldownUntil > TimeTradeServer());
}

void ResetBasketState(int idx)
{
   g_baskets[idx].active       = false;
   g_baskets[idx].symbol       = "";
   g_baskets[idx].symbolIndex  = -1;
   g_baskets[idx].direction    = -1;
   g_baskets[idx].levels       = 0;
   g_baskets[idx].lastAddPrice = 0.0;
   g_baskets[idx].anchorSL     = 0.0;
   g_baskets[idx].baseLots     = 0.0;
   g_baskets[idx].trailActive  = false;
   g_baskets[idx].trailPeakPnl = 0.0;
   g_baskets[idx].startTime    = 0;
   g_baskets[idx].closeReason  = "-";
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

string FormatPercent(const double v)
{
   return DoubleToString(v, 2) + "%";
}

double GlobalDrawdownMoney()
{
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double eq  = AccountInfoDouble(ACCOUNT_EQUITY);
   return MathMax(0.0, bal - eq);
}

double GlobalDrawdownPct()
{
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   if(bal <= 0.0)
      return 0.0;
   return 100.0 * GlobalDrawdownMoney() / bal;
}

void UpdateMaxGlobalDrawdown()
{
   double ddMoney = GlobalDrawdownMoney();
   double ddPct   = GlobalDrawdownPct();

   if(ddMoney > g_maxGlobalDdMoney)
      g_maxGlobalDdMoney = ddMoney;
   if(ddPct > g_maxGlobalDdPct)
      g_maxGlobalDdPct = ddPct;
}

string FormatHours(const double hours, const int digits = 1)
{
   return DoubleToString(hours, digits) + "h";
}

double AverageHoldingHours()
{
   if(g_closedBasketAgeCount <= 0)
      return 0.0;

   return g_closedBasketAgeHoursSum / (double)g_closedBasketAgeCount;
}

void RegisterClosedBasketAge(const int basketIdx)
{
   if(basketIdx < 0 || basketIdx >= ArraySize(g_baskets))
      return;
   if(!g_baskets[basketIdx].active || g_baskets[basketIdx].startTime <= 0)
      return;

   datetime now = TimeTradeServer();
   if(now <= 0)
      now = TimeCurrent();
   if(now <= 0 || now < g_baskets[basketIdx].startTime)
      return;

   g_closedBasketAgeHoursSum += (double)(now - g_baskets[basketIdx].startTime) / 3600.0;
   g_closedBasketAgeCount++;
}

double BasketAgeHours(const int basketIdx)
{
   if(basketIdx < 0 || basketIdx >= ArraySize(g_baskets))
      return 0.0;
   if(!g_baskets[basketIdx].active || g_baskets[basketIdx].startTime <= 0)
      return 0.0;

   datetime now = TimeTradeServer();
   if(now <= 0)
      now = TimeCurrent();
   if(now < g_baskets[basketIdx].startTime)
      return 0.0;

   return (double)(now - g_baskets[basketIdx].startTime) / 3600.0;
}

string BasketAgeHoursText(const int basketIdx)
{
   if(basketIdx < 0 || basketIdx >= ArraySize(g_baskets))
      return "-";
   if(!g_baskets[basketIdx].active)
      return "-";

   return FormatHours(BasketAgeHours(basketIdx), 1);
}

double AccountMarginLevelPct()
{
   double ml = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
   if(ml > 0.0)
      return ml;

   double margin = AccountInfoDouble(ACCOUNT_MARGIN);
   if(margin <= 0.0)
      return 0.0;

   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   return 100.0 * eq / margin;
}

double SymbolOpenPnl(const string sym)
{
   double pnl = 0.0;

   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != sym)
         continue;

      pnl += PositionGetDouble(POSITION_PROFIT)
           + PositionGetDouble(POSITION_SWAP);
   }

   return pnl;
}
int BasketPositionCountBySymbol(const string sym)
{
   int count = 0;

   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != sym)
         continue;

      count++;
   }

   return count;
}

double BasketFloatingDDMoney(const string sym)
{
   double pnl = SymbolOpenPnl(sym);
   if(pnl < 0.0)
      return -pnl;
   return 0.0;
}

string BasketAvgEntryText(const string sym)
{
   double avg = BasketAverageEntryPrice(sym);
   if(avg <= 0.0)
      return "-";
   return FormatPrice(sym, avg);
}
string ShortSymbol(const string sym)
{
   if(StringLen(sym) < 6)
      return sym;

   return StringSubstr(sym, 0, 1) + StringSubstr(sym, 3, 1);
}
string BasketSummaryText(const int maxItems = 3)
{
   int activeCnt = ActiveBasketCount();
   if(activeCnt <= 0)
      return "FLAT";

   string s = IntegerToString(activeCnt) + " baskets";
   int shown = 0;

   for(int i = 0; i < ArraySize(g_baskets); i++)
   {
      if(!g_baskets[i].active)
         continue;

      s += "|" + ShortSymbol(g_baskets[i].symbol)
         + ":"
         + (g_baskets[i].direction == POSITION_TYPE_BUY ? "B" : "S")
         + IntegerToString(g_baskets[i].levels);

      shown++;
      if(shown >= maxItems)
         break;
   }

   return s;
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

string BaseCurrency(const string sym)
{
   if(StringLen(sym) < 6)
      return "";
   return StringSubstr(sym, 0, 3);
}

string QuoteCurrency(const string sym)
{
   if(StringLen(sym) < 6)
      return "";
   return StringSubstr(sym, 3, 3);
}

bool SymbolsShareCurrency(const string a, const string b)
{
   string a1 = BaseCurrency(a);
   string a2 = QuoteCurrency(a);
   string b1 = BaseCurrency(b);
   string b2 = QuoteCurrency(b);

   if(a1 == "" || a2 == "" || b1 == "" || b2 == "")
      return false;

   return (a1 == b1 || a1 == b2 || a2 == b1 || a2 == b2);
}
bool SymbolsConflictDirectional(const string symA, const int dirA,
                                const string symB, const int dirB)
{
   string aBase = BaseCurrency(symA);
   string aQuote = QuoteCurrency(symA);
   string bBase = BaseCurrency(symB);
   string bQuote = QuoteCurrency(symB);

   if(aBase == "" || aQuote == "" || bBase == "" || bQuote == "")
      return false;

   // Determine exposure for each currency
   // BUY:  base = +1, quote = -1
   // SELL: base = -1, quote = +1

   int aBaseExp  = (dirA == POSITION_TYPE_BUY ? +1 : -1);
   int aQuoteExp = -aBaseExp;

   int bBaseExp  = (dirB == POSITION_TYPE_BUY ? +1 : -1);
   int bQuoteExp = -bBaseExp;

   // Check all currency matches
   // Conflict only if SAME currency AND SAME exposure direction

   if(aBase == bBase && aBaseExp == bBaseExp)   return true;
   if(aBase == bQuote && aBaseExp == bQuoteExp) return true;
   if(aQuote == bBase && aQuoteExp == bBaseExp) return true;
   if(aQuote == bQuote && aQuoteExp == bQuoteExp) return true;

   return false;
}

int ActiveBasketCount()
{
   int count = 0;
   for(int i = 0; i < ArraySize(g_baskets); i++)
      if(g_baskets[i].active)
         count++;
   return count;
}



void ResetAllBasketStates()
{
   ArrayResize(g_baskets, ArraySize(g_states));
   for(int i = 0; i < ArraySize(g_baskets); i++)
      ResetBasketState(i);
}

double BasketNetProfit(const string sym = "")
{
   double pnl = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;
      if(sym != "" && PositionGetString(POSITION_SYMBOL) != sym)
         continue;

      pnl += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
   }
   return pnl;
}

int BasketPositionCount(const string sym = "", const int posType = -1)
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
      if(posType >= 0 && (int)PositionGetInteger(POSITION_TYPE) != posType)
         continue;

      count++;
   }
   return count;
}

double OtherBasketWorstDDPctBalance(const string excludeSym = "")
{
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   if(bal <= 0.0)
      return 0.0;

   double ddMoney = 0.0;
   for(int i = 0; i < ArraySize(g_baskets); i++)
   {
      if(!g_baskets[i].active)
         continue;
      if(excludeSym != "" && g_baskets[i].symbol == excludeSym)
         continue;

      double pnl = BasketNetProfit(g_baskets[i].symbol);
      if(pnl < 0.0)
         ddMoney += (-pnl);
   }

   return (ddMoney / bal) * 100.0;
}

double CalcReturnCorrelation(const string symA, const string symB, const int bars)
{
   if(symA == symB)
      return 1.0;

   int need = MathMax(20, bars + 1);

   double a[];
   double b[];
   ArraySetAsSeries(a, true);
   ArraySetAsSeries(b, true);

   int ca = CopyClose(symA, PERIOD_M15, 0, need, a);
   int cb = CopyClose(symB, PERIOD_M15, 0, need, b);

   if(ca < need || cb < need)
      return 0.0;

   double meanA = 0.0, meanB = 0.0;
   int n = need - 1;

   for(int i = 0; i < n; i++)
   {
      double ra = 0.0;
      double rb = 0.0;
      if(a[i + 1] != 0.0) ra = (a[i] - a[i + 1]) / a[i + 1];
      if(b[i + 1] != 0.0) rb = (b[i] - b[i + 1]) / b[i + 1];
      meanA += ra;
      meanB += rb;
   }

   meanA /= n;
   meanB /= n;

   double cov = 0.0, varA = 0.0, varB = 0.0;

   for(int i = 0; i < n; i++)
   {
      double ra = 0.0;
      double rb = 0.0;
      if(a[i + 1] != 0.0) ra = (a[i] - a[i + 1]) / a[i + 1];
      if(b[i + 1] != 0.0) rb = (b[i] - b[i + 1]) / b[i + 1];

      double da = ra - meanA;
      double db = rb - meanB;

      cov  += da * db;
      varA += da * da;
      varB += db * db;
   }

   if(varA <= 0.0 || varB <= 0.0)
      return 0.0;

   return (cov / MathSqrt(varA * varB));
}

double CalcReturnCorrelationAbs(const string symA, const string symB, const int bars)
{
   return MathAbs(CalcReturnCorrelation(symA, symB, bars));
}

int DirectionSign(const int dir)
{
   return (dir == POSITION_TYPE_BUY ? +1 : -1);
}

int CurrencyExposureSign(const string sym, const int dir, const string ccy)
{
   string base  = BaseCurrency(sym);
   string quote = QuoteCurrency(sym);
   if(base == "" || quote == "" || ccy == "")
      return 0;

   int baseExp  = (dir == POSITION_TYPE_BUY ? +1 : -1);
   int quoteExp = -baseExp;

   if(ccy == base)
      return baseExp;
   if(ccy == quote)
      return quoteExp;
   return 0;
}

bool HasOppositeSharedCurrencyExposure(const string symA, const int dirA,
                                       const string symB, const int dirB)
{
   string aBase  = BaseCurrency(symA);
   string aQuote = QuoteCurrency(symA);
   string bBase  = BaseCurrency(symB);
   string bQuote = QuoteCurrency(symB);

   if(aBase == "" || aQuote == "" || bBase == "" || bQuote == "")
      return false;

   string ccys[4] = {aBase, aQuote, bBase, bQuote};
   for(int i = 0; i < 4; i++)
   {
      string ccy = ccys[i];
      if(ccy == "")
         continue;

      int expA = CurrencyExposureSign(symA, dirA, ccy);
      int expB = CurrencyExposureSign(symB, dirB, ccy);
      if(expA == 0 || expB == 0)
         continue;

      if(expA == -expB)
         return true;
   }

   return false;
}

bool IsRecoveryCompatiblePair(const string candidateSym, const int candidateDir,
                              const string staleSym, const int staleDir)
{
   if(candidateSym == "" || staleSym == "" || candidateSym == staleSym)
      return false;

   // First allow clear currency-exposure hedges.
   // Example: stale EURGBP BUY (+EUR,-GBP) vs EURUSD SELL (-EUR,+USD).
   if(HasOppositeSharedCurrencyExposure(candidateSym, candidateDir, staleSym, staleDir))
      return true;

   // Fallback to the stricter price-correlation test.
   double corr = CalcReturnCorrelation(candidateSym, staleSym, InpCorrelationBars);
   if(MathAbs(corr) < InpMaxAbsCorrelation)
      return false;

   int candSign  = DirectionSign(candidateDir);
   int staleSign = DirectionSign(staleDir);
   double pnlCoMove = (double)(candSign * staleSign) * corr;
   return (pnlCoMove <= -InpMaxAbsCorrelation);
}

bool HasStaleBasket(const double minAgeHours = 24.0)
{
   for(int i = 0; i < ArraySize(g_baskets); i++)
   {
      if(!g_baskets[i].active)
         continue;
      if(BasketAgeHours(i) >= minAgeHours)
         return true;
   }
   return false;
}

bool IsRecoveryRunnerBasket(const int basketIdx, const double minAgeHours = 24.0)
{
   if(basketIdx < 0 || basketIdx >= ArraySize(g_baskets))
      return false;
   if(!g_baskets[basketIdx].active)
      return false;

   string sym = g_baskets[basketIdx].symbol;
   int    dir = g_baskets[basketIdx].direction;
   if(sym == "")
      return false;

   double pnl = BasketNetProfit(sym);
   if(pnl <= 0.0)
      return false;

   for(int i = 0; i < ArraySize(g_baskets); i++)
   {
      if(i == basketIdx)
         continue;
      if(!g_baskets[i].active)
         continue;
      if(BasketAgeHours(i) < minAgeHours)
         continue;
      if(IsRecoveryCompatiblePair(sym, dir, g_baskets[i].symbol, g_baskets[i].direction))
         return true;
   }

   return false;
}

bool IsRecoveryEligibleNewBasket(const string sym, const int dir, const double minAgeHours = 24.0)
{
   if(sym == "")
      return false;

   for(int i = 0; i < ArraySize(g_baskets); i++)
   {
      if(!g_baskets[i].active)
         continue;
      if(g_baskets[i].symbol == sym)
         continue;
      if(BasketAgeHours(i) < minAgeHours)
         continue;

      if(IsRecoveryCompatiblePair(sym, dir, g_baskets[i].symbol, g_baskets[i].direction))
         return true;
   }

   return false;
}

bool HasHighCorrelationConflict(const string sym, const int dir)
{
   if(!InpUseCorrelationGate)
      return false;

   bool recoveryEligible = IsRecoveryEligibleNewBasket(sym, dir, 24.0);

   for(int i = 0; i < ArraySize(g_baskets); i++)
   {
      if(!g_baskets[i].active)
         continue;
      if(g_baskets[i].symbol == sym)
         continue;

      double signedCorr = CalcReturnCorrelation(sym, g_baskets[i].symbol, InpCorrelationBars);
      double absCorr    = MathAbs(signedCorr);

      if(recoveryEligible &&
         BasketAgeHours(i) >= 24.0 &&
         IsRecoveryCompatiblePair(sym, dir, g_baskets[i].symbol, g_baskets[i].direction))
         continue;

      if(absCorr >= InpMaxAbsCorrelation)
         return true;
   }
   return false;
}

bool HasSharedCurrencyConflict(const string sym, const int dir)
{
   if(!InpBlockSharedCurrencies)
      return false;

   bool recoveryEligible = IsRecoveryEligibleNewBasket(sym, dir, 24.0);

   for(int i = 0; i < ArraySize(g_baskets); i++)
   {
      if(!g_baskets[i].active)
         continue;

      string otherSym = g_baskets[i].symbol;
      int otherDir    = g_baskets[i].direction;

      if(otherSym == sym)
         continue;

      if(recoveryEligible &&
         BasketAgeHours(i) >= 24.0 &&
         IsRecoveryCompatiblePair(sym, dir, otherSym, otherDir))
         continue;

      if(SymbolsConflictDirectional(sym, dir, otherSym, otherDir))
         return true;
   }

   return false;
}

bool CanOpenNewBasket(const string sym,const int direction)
{
   bool recoveryEligible = IsRecoveryEligibleNewBasket(sym, direction, 24.0);

   if(HasOpenPosition(sym))
   {
      LogMsg(LOG_DEBUG, "NEW_BASKET_BLOCK | " + sym + " | already has open position");
      return false;
   }

   int active = ActiveBasketCount();
   if(active >= InpMaxConcurrentBaskets)
   {
      LogMsg(LOG_DEBUG,
             StringFormat("NEW_BASKET_BLOCK | %s | max baskets | active=%d max=%d",
                          sym, active, InpMaxConcurrentBaskets));
      return false;
   }

   double otherDd = OtherBasketWorstDDPctBalance(sym);
   if(otherDd > InpMaxOtherBasketDDPctBal)
   {
      LogMsg(LOG_DEBUG,
             StringFormat("NEW_BASKET_BLOCK | %s | other DD | dd=%.2f max=%.2f",
                          sym, otherDd, InpMaxOtherBasketDDPctBal));
      return false;
   }

   if(HasSharedCurrencyConflict(sym,direction))
   {
      LogMsg(LOG_DEBUG, "NEW_BASKET_BLOCK | " + sym + " | shared currency conflict");
      return false;
   }

   if(HasHighCorrelationConflict(sym, direction))
   {
      LogMsg(LOG_DEBUG, "NEW_BASKET_BLOCK | " + sym + " | correlation conflict");
      return false;
   }

   if(recoveryEligible)
   {
      LogMsg(LOG_DEBUG,
             StringFormat("RECOV_ENTRY_ALLOWED | %s | direction-aware stale recovery pass", sym));
   }

   return true;
}

void SyncBasketStates()
{
   BasketState oldBaskets[];
   ArrayResize(oldBaskets, ArraySize(g_baskets));

   for(int i = 0; i < ArraySize(g_baskets); i++)
   {
      oldBaskets[i].active       = g_baskets[i].active;
      oldBaskets[i].symbol       = g_baskets[i].symbol;
      oldBaskets[i].symbolIndex  = g_baskets[i].symbolIndex;
      oldBaskets[i].direction    = g_baskets[i].direction;
      oldBaskets[i].levels       = g_baskets[i].levels;
      oldBaskets[i].lastAddPrice = g_baskets[i].lastAddPrice;
      oldBaskets[i].anchorSL     = g_baskets[i].anchorSL;
      oldBaskets[i].baseLots     = g_baskets[i].baseLots;
      oldBaskets[i].trailActive  = g_baskets[i].trailActive;
      oldBaskets[i].trailPeakPnl = g_baskets[i].trailPeakPnl;
      oldBaskets[i].startTime    = g_baskets[i].startTime;
      oldBaskets[i].closeReason  = g_baskets[i].closeReason;
   }

   ResetAllBasketStates();

   datetime newestTime[];
   ArrayResize(newestTime, ArraySize(g_states));
   ArrayInitialize(newestTime, 0);

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

      if(!g_baskets[idx].active)
      {
         g_baskets[idx].active       = true;
         g_baskets[idx].symbol       = sym;
         g_baskets[idx].symbolIndex  = idx;
         g_baskets[idx].direction    = (int)PositionGetInteger(POSITION_TYPE);
         g_baskets[idx].levels       = 0;
         g_baskets[idx].lastAddPrice = 0.0;
         g_baskets[idx].anchorSL     = (g_baskets[idx].direction == POSITION_TYPE_BUY ? g_states[idx].dailyLow : g_states[idx].dailyHigh);
         g_baskets[idx].baseLots     = NormalizeLots(sym, PositionGetDouble(POSITION_VOLUME));
         g_baskets[idx].startTime    = (datetime)PositionGetInteger(POSITION_TIME);
         g_baskets[idx].closeReason  = "sync";

         if(idx < ArraySize(oldBaskets) && oldBaskets[idx].active)
         {
            g_baskets[idx].trailActive  = oldBaskets[idx].trailActive;
            g_baskets[idx].trailPeakPnl = oldBaskets[idx].trailPeakPnl;
            if(oldBaskets[idx].startTime > 0)
               g_baskets[idx].startTime = oldBaskets[idx].startTime;
         }
      }

      g_baskets[idx].levels++;

      datetime posTime = (datetime)PositionGetInteger(POSITION_TIME);
      if(posTime >= newestTime[idx])
      {
         newestTime[idx] = posTime;
         g_baskets[idx].lastAddPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      }

      if(PositionGetDouble(POSITION_VOLUME) < g_baskets[idx].baseLots || g_baskets[idx].baseLots <= 0.0)
         g_baskets[idx].baseLots = NormalizeLots(sym, PositionGetDouble(POSITION_VOLUME));
   }
}

void LogExposureSnapshot(const string tag)
{
   int totalPos = BasketPositionCount();
   if(totalPos < InpExposureLogTriggerCount)
      return;

   string msg = StringFormat("%s | exposure totalPos=%d activeBaskets=%d eq=%.2f bal=%.2f pnl=%.2f",
                             tag,
                             totalPos,
                             ActiveBasketCount(),
                             AccountInfoDouble(ACCOUNT_EQUITY),
                             AccountInfoDouble(ACCOUNT_BALANCE),
                             AccountInfoDouble(ACCOUNT_PROFIT));
   LogMsg(LOG_INFO, msg);

   for(int i = 0; i < ArraySize(g_baskets); i++)
   {
      if(!g_baskets[i].active)
         continue;

      double basketPnl = BasketNetProfit(g_baskets[i].symbol);
      int basketCnt = BasketPositionCount(g_baskets[i].symbol);
      LogMsg(LOG_INFO,
             StringFormat("EXPOSURE | %s | dir=%s | levels=%d | pos=%d | pnl=%.2f | lastAdd=%s | start=%s",
                          g_baskets[i].symbol,
                          (g_baskets[i].direction == POSITION_TYPE_BUY ? "BUY" : "SELL"),
                          g_baskets[i].levels,
                          basketCnt,
                          basketPnl,
                          FormatPrice(g_baskets[i].symbol, g_baskets[i].lastAddPrice),
                          FormatServerDateTime(g_baskets[i].startTime)));
   }
}

void LogBasketOpenContext(const string sym, const int direction, const double dealPrice, const double dealVolume, const string tag)
{
   int idx = GetStateIndexBySymbol(sym);
   if(idx < 0)
      return;

   SignalContext ctx;
   if(!EvaluateSignalContext(idx, ctx))
      return;

   double corrMax = 0.0;
   for(int i = 0; i < ArraySize(g_baskets); i++)
   {
      if(!g_baskets[i].active || g_baskets[i].symbol == sym)
         continue;
      double c = CalcReturnCorrelationAbs(sym, g_baskets[i].symbol, InpCorrelationBars);
      if(c > corrMax)
         corrMax = c;
   }

   LogMsg(LOG_INFO,
      StringFormat("%s | %s | %s | px=%s | lots=%.2f | spread=%s | atr%%=%.1f | HO=%s | LO=%s | DHi=%s | DLo=%s | YHi=%s | YLo=%s | M15=%s | sellSig=%s(%s) | buySig=%s(%s) | otherDD%%=%.2f | maxCorr=%.2f",
         tag,
         sym,
         (direction == POSITION_TYPE_BUY ? "BUY" : "SELL"),
         FormatPrice(sym, dealPrice),
         dealVolume,
         FormatPips(g_states[idx].spreadPips),
         g_states[idx].rangeAtrPct,
         FormatPrice(sym, g_states[idx].hoH1),
         FormatPrice(sym, g_states[idx].loH1),
         FormatPrice(sym, g_states[idx].dailyHigh),
         FormatPrice(sym, g_states[idx].dailyLow),
         FormatPrice(sym, g_states[idx].yesterdayHigh),
         FormatPrice(sym, g_states[idx].yesterdayLow),
         FormatPrice(sym, g_states[idx].m15Open),
         (ctx.sellSignal ? "Y" : "N"),
         ctx.sellReason,
         (ctx.buySignal ? "Y" : "N"),
         ctx.buyReason,
         OtherBasketWorstDDPctBalance(sym),
         corrMax));
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

   g_states[idx].atrFast = 0.0;
   g_states[idx].atrSlow = 0.0;
   g_states[idx].atrSpikeRatio = 0.0;
   g_states[idx].curTfRangeAtr = 0.0;
   g_states[idx].atrSpikeBlockNew = false;
   g_states[idx].atrSpikeBlockAdd = false;

   if(InpUseAtrSpikeFilter && g_states[idx].atrSpikeHandle != INVALID_HANDLE)
   {
      int need = MathMax(2, InpAtrSpikeAvgPeriod);
      double atrFastBuf[];
      ArraySetAsSeries(atrFastBuf, true);

      if(CopyBuffer(g_states[idx].atrSpikeHandle, 0, 1, need, atrFastBuf) > 0)
      {
         g_states[idx].atrFast = atrFastBuf[0];

         double sum = 0.0;
         int used = MathMin(ArraySize(atrFastBuf), need);
         for(int k = 0; k < used; k++)
            sum += atrFastBuf[k];

         if(used > 0)
            g_states[idx].atrSlow = sum / used;

         if(g_states[idx].atrFast > 0.0 && g_states[idx].atrSlow > 0.0)
            g_states[idx].atrSpikeRatio = g_states[idx].atrFast / g_states[idx].atrSlow;
      }

      double tfHigh = iHigh(sym, InpAtrSpikeTF, 0);
      double tfLow  = iLow(sym, InpAtrSpikeTF, 0);
      if(g_states[idx].atrFast > 0.0 && tfHigh > tfLow)
         g_states[idx].curTfRangeAtr = (tfHigh - tfLow) / g_states[idx].atrFast;

      g_states[idx].atrSpikeBlockNew = ((g_states[idx].atrSpikeRatio >= InpAtrSpikeBlockNew) ||
                                        (g_states[idx].curTfRangeAtr >= InpImpulseBarRangeAtr));
      g_states[idx].atrSpikeBlockAdd = ((g_states[idx].atrSpikeRatio >= InpAtrSpikeBlockAdd) ||
                                        (g_states[idx].curTfRangeAtr >= InpImpulseBarRangeAtr));
   }
}

void RefreshAllSymbolStates()
{
   EnsureNewsCalendarFresh();

   for(int i = 0; i < ArraySize(g_states); i++)
      RefreshSymbolState(i);
}


bool IsTier1NewsEventName(const string name)
{
   string s = name;
   StringToLower(s);
   if(StringFind(s, "interest rate") >= 0)      return true;
   if(StringFind(s, "rate decision") >= 0)      return true;
   if(StringFind(s, "monetary policy") >= 0)    return true;
   if(StringFind(s, "press conference") >= 0)   return true;
   if(StringFind(s, "cpi") >= 0)                return true;
   if(StringFind(s, "consumer price") >= 0)     return true;
   if(StringFind(s, "employment") >= 0)         return true;
   if(StringFind(s, "nonfarm") >= 0)            return true;
   if(StringFind(s, "nfp") >= 0)                return true;
   if(StringFind(s, "payroll") >= 0)            return true;
   if(StringFind(s, "jobless") >= 0)            return true;
   if(StringFind(s, "unemployment") >= 0)       return true;
   if(StringFind(s, "gdp") >= 0)                return true;
   if(StringFind(s, "gross domestic") >= 0)     return true;
   if(StringFind(s, "retail sales") >= 0)       return true;
   return false;
}

bool IsHighImpactNewsEvent(const MqlCalendarEvent &eventRec)
{
   return (eventRec.importance == CALENDAR_IMPORTANCE_HIGH);
}

void ResetNewsState(const int idx)
{
   g_states[idx].newsBlockNew   = false;
   g_states[idx].newsBlockAdd   = false;
   g_states[idx].newsHasUpcoming = false;
   g_states[idx].newsUseFallback = false;
   g_states[idx].newsSource     = "";
   g_states[idx].nextNewsTime   = 0;
   g_states[idx].nextNewsTitle  = "";
   g_states[idx].nextNewsTag    = "";
}

void ApplyNewsWindowToState(const int idx,
                            const datetime eventTime,
                            const string eventName,
                            const bool isTier1,
                            const string sourceTag)
{
   if(idx < 0 || idx >= ArraySize(g_states) || eventTime <= 0)
      return;

   datetime now = TimeTradeServer();
   int newBefore = (isTier1 ? InpBlockNewTier1BeforeHours : InpBlockNewHighBeforeHours);
   int newAfter  = (isTier1 ? InpBlockNewTier1AfterHours  : InpBlockNewHighAfterHours);
   int addBefore = (isTier1 ? InpBlockAddTier1BeforeHours : InpBlockAddHighBeforeHours);
   int addAfter  = (isTier1 ? InpBlockAddTier1AfterHours  : InpBlockAddHighAfterHours);

   if(now >= eventTime - newBefore * 3600 && now <= eventTime + newAfter * 3600)
      g_states[idx].newsBlockNew = true;

   if(now >= eventTime - addBefore * 3600 && now <= eventTime + addAfter * 3600)
      g_states[idx].newsBlockAdd = true;

   if(eventTime >= now)
   {
      if(!g_states[idx].newsHasUpcoming || eventTime < g_states[idx].nextNewsTime)
      {
         g_states[idx].newsHasUpcoming = true;
         g_states[idx].nextNewsTime    = eventTime;
         g_states[idx].nextNewsTitle   = eventName;
         g_states[idx].nextNewsTag     = (isTier1 ? "T1" : "HI");
         g_states[idx].newsSource      = sourceTag;
         g_states[idx].newsUseFallback = (sourceTag != "CAL");
      }
   }
}

bool SymbolContainsCurrency(const string sym, const string ccy)
{
   if(ccy == "")
      return false;
   return (BaseCurrency(sym) == ccy || QuoteCurrency(sym) == ccy);
}

bool ShouldPreCloseBeforeNews(const int idx)
{
   if(!InpUseNewsFilter || !InpCloseProfitBeforeNews)
      return false;
   if(idx < 0 || idx >= ArraySize(g_states))
      return false;
   if(!g_states[idx].newsHasUpcoming || g_states[idx].nextNewsTime <= 0)
      return false;

   datetime now = TimeTradeServer();
   return (now >= g_states[idx].nextNewsTime - InpCloseProfitBeforeNewsHours * 3600 &&
           now <  g_states[idx].nextNewsTime);
}


string SanitizeFilePart(const string s)
{
   string out = s;
   StringReplace(out, ":", "_");
   StringReplace(out, "/", "_");
   StringReplace(out, "\\", "_");
   StringReplace(out, "?", "_");
   StringReplace(out, "&", "_");
   StringReplace(out, "=", "_");
   StringReplace(out, " ", "_");
   StringReplace(out, ".", "_");
   return out;
}

datetime StartOfWeekMonday(const datetime when)
{
   MqlDateTime tm;
   TimeToStruct(when, tm);
   int dow = tm.day_of_week;
   if(dow == 0)
      dow = 7;
   datetime dayStart = when - (tm.hour * 3600 + tm.min * 60 + tm.sec);
   return (dayStart - (dow - 1) * 86400);
}

string FFWeekToken(const datetime when)
{
   MqlDateTime tm;
   TimeToStruct(StartOfWeekMonday(when), tm);
   return StringFormat("%04d%02d%02d", tm.year, tm.mon, tm.day);
}

string FFWeekTokenShifted(const datetime when, const int weekShift)
{
   return FFWeekToken(when + weekShift * 7 * 86400);
}

string GetFFCsvCacheFileNameByToken(const string weekToken)
{
   return InpFFCsvFilePrefix + weekToken + ".csv";
}

string GetFFCsvCacheFileName()
{
   return GetFFCsvCacheFileNameByToken(FFWeekToken(TimeTradeServer()));
}

bool ReadCachedTextFile(const string fileName, string &content)
{
   content = "";
   int flags = FILE_READ | FILE_TXT | FILE_ANSI;
   if(InpFFCsvUseCommonFiles)
      flags |= FILE_COMMON;

   int h = FileOpen(fileName, flags);
   if(h == INVALID_HANDLE)
      return false;

   while(!FileIsEnding(h))
   {
      content += FileReadString(h);
      if(!FileIsEnding(h))
         content += "\n";
   }
   FileClose(h);
   return (StringLen(content) > 0);
}

bool WriteCachedTextFile(const string fileName, const string content)
{
   int flags = FILE_WRITE | FILE_TXT | FILE_ANSI;
   if(InpFFCsvUseCommonFiles)
      flags |= FILE_COMMON;

   int h = FileOpen(fileName, flags);
   if(h == INVALID_HANDLE)
      return false;

   FileWriteString(h, content);
   FileClose(h);
   return true;
}

bool DownloadFFCsvContent(string &csvText)
{
   csvText = "";
   if(!InpUseFFCsvFallback || StringLen(Trim(InpFFCsvUrl)) == 0)
      return false;

   char post[];
   char result[];
   string headers = "User-Agent: MetaTrader5 HOLO EA\r\n";
   string responseHeaders = "";

   ResetLastError();
   int code = WebRequest("GET",
                         InpFFCsvUrl,
                         headers,
                         InpFFCsvTimeoutMs,
                         post,
                         result,
                         responseHeaders);

   if(code != 200)
   {
      LogMsg(LOG_DEBUG, StringFormat("FF CSV WebRequest failed code=%d err=%d", code, GetLastError()));
      return false;
   }

   csvText = CharArrayToString(result, 0, -1);
   string probe = csvText;
   StringToLower(probe);
   if(StringFind(probe, "<!doctype html") >= 0 || StringFind(probe, "<html") >= 0 || StringFind(probe, "error 1015") >= 0)
   {
      LogMsg(LOG_ERROR, "FF CSV request returned HTML/rate-limit page instead of CSV");
      return false;
   }

   return (StringLen(csvText) > 0);
}

int CsvSplitLine(const string line, string &fields[])
{
   ArrayResize(fields, 0);

   bool inQuotes = false;
   string cur = "";

   for(int i = 0; i < StringLen(line); i++)
   {
      ushort ch = (ushort)StringGetCharacter(line, i);

      if(ch == 34)
      {
         if(inQuotes && i + 1 < StringLen(line) && (ushort)StringGetCharacter(line, i + 1) == 34)
         {
            cur += "\"";
            i++;
         }
         else
         {
            inQuotes = !inQuotes;
         }
      }
      else if(ch == 44 && !inQuotes)
      {
         int n = ArraySize(fields);
         ArrayResize(fields, n + 1);
         fields[n] = cur;
         cur = "";
      }
      else
      {
         cur += ShortToString(ch);
      }
   }

   int n = ArraySize(fields);
   ArrayResize(fields, n + 1);
   fields[n] = cur;
   return ArraySize(fields);
}

bool ParseFFCsvDateTime(const string dateStr,
                        const string timeStr,
                        datetime &outTime)
{
   outTime = 0;
   string d = Trim(dateStr);
   string t = Trim(timeStr);

   if(d == "" || t == "")
      return false;

   string tl = t;
   StringToLower(tl);
   if(tl == "all day" || tl == "tentative")
      return false;

   string dparts[];
   if(StringSplit(d, '-', dparts) != 3)
      return false;

   int p0 = (int)StringToInteger(dparts[0]);
   int p1 = (int)StringToInteger(dparts[1]);
   int year = (int)StringToInteger(dparts[2]);
   int mon = p0;
   int day = p1;

   if(p0 > 12 && p1 <= 12)
   {
      day = p0;
      mon = p1;
   }

   string ampm = "";
   string timeCore = tl;
   if(StringLen(timeCore) >= 2)
   {
      ampm = StringSubstr(timeCore, StringLen(timeCore) - 2);
      timeCore = Trim(StringSubstr(timeCore, 0, StringLen(timeCore) - 2));
   }

   string tparts[];
   if(StringSplit(timeCore, ':', tparts) != 2)
      return false;

   int hour = (int)StringToInteger(tparts[0]);
   int minute = (int)StringToInteger(tparts[1]);

   if(ampm == "pm" && hour < 12)
      hour += 12;
   if(ampm == "am" && hour == 12)
      hour = 0;

   MqlDateTime tm;
   ZeroMemory(tm);
   tm.year = year;
   tm.mon = mon;
   tm.day = day;
   tm.hour = hour;
   tm.min = minute;
   tm.sec = 0;

   outTime = StructToTime(tm) + InpFFCsvTimeShiftMinutes * 60;
   return (outTime > 0);
}

bool CurrencyTrackedBySymbols(const string ccy)
{
   if(ccy == "")
      return false;

   for(int i = 0; i < ArraySize(g_states); i++)
      if(SymbolContainsCurrency(g_states[i].symbol, ccy))
         return true;

   return false;
}

int LoadSingleFFCsvFile(const string fileName,
                        FFCsvNewsEvent &events[],
                        const bool appendMode = true)
{
   string csvText = "";
   if(!ReadCachedTextFile(fileName, csvText) || StringLen(csvText) == 0)
      return 0;

   int base = (appendMode ? ArraySize(events) : 0);
   if(!appendMode)
      ArrayResize(events, 0);

   StringReplace(csvText, "\r", "");
   string lines[];
   int lineCount = StringSplit(csvText, '\n', lines);
   if(lineCount <= 0)
      return 0;

   int added = 0;
   for(int i = 1; i < lineCount; i++)
   {
      string line = Trim(lines[i]);
      if(line == "")
         continue;

      string f[];
      int cols = CsvSplitLine(line, f);
      if(cols < 5)
         continue;

      string d = Trim(f[0]);
      string t = Trim(f[1]);
      string ccy = Trim(f[2]);
      string impact = Trim(f[3]);
      string title = Trim(f[4]);

      string impactLc = impact;
      StringToLower(impactLc);
      if(StringFind(impactLc, "high") < 0)
         continue;
      if(!CurrencyTrackedBySymbols(ccy))
         continue;

      datetime evtTime = 0;
      if(!ParseFFCsvDateTime(d, t, evtTime))
         continue;

      int n = ArraySize(events);
      ArrayResize(events, n + 1);
      events[n].time     = evtTime;
      events[n].currency = ccy;
      events[n].title    = title;
      events[n].tier1    = IsTier1NewsEventName(title);
      events[n].impact   = impact;
      added++;
   }

   return added;
}

int LoadFFCsvEvents(FFCsvNewsEvent &events[])
{
   ArrayResize(events, 0);

   if(!InpUseFFCsvFallback)
      return 0;

   datetime now = TimeTradeServer();

   if(MQLInfoInteger(MQL_TESTER))
   {
      if(!InpUseTesterArchivedFFCsv)
         return 0;

      int total = 0;
      int weeksAhead = MathMax(0, InpTesterFFCsvWeeksAhead);
      for(int ws = 0; ws <= weeksAhead; ws++)
      {
         string testerFile = GetFFCsvCacheFileNameByToken(FFWeekTokenShifted(now, ws));
         total += LoadSingleFFCsvFile(testerFile, events, true);
      }
      return total;
   }

   string fileName = GetFFCsvCacheFileName();
   string csvText = "";

   bool haveCache = ReadCachedTextFile(fileName, csvText);
   bool needRefresh = (!haveCache ||
                       g_ffCsvLastFetch <= 0 ||
                       g_ffCsvLastFile != fileName ||
                       now >= g_ffCsvLastFetch + MathMax(5, InpFFCsvRefreshMinutes) * 60);

   if(needRefresh)
   {
      string fresh = "";
      if(DownloadFFCsvContent(fresh))
      {
         csvText = fresh;
         WriteCachedTextFile(fileName, csvText);
         g_ffCsvLastFetch = now;
         g_ffCsvLastFile = fileName;
      }
   }

   if(StringLen(csvText) == 0)
      return 0;

   return LoadSingleFFCsvFile(fileName, events, false);
}

bool RefreshNewsCalendarCache()
{
   for(int i = 0; i < ArraySize(g_states); i++)
      ResetNewsState(i);

   if(!InpUseNewsFilter)
   {
      g_newsLiveCalendarOk = false;
      g_newsCacheValidUntil = TimeTradeServer() + MathMax(1, InpNewsCacheMinutes) * 60;
      return false;
   }

   datetime now = TimeTradeServer();
   datetime from = now - MathMax(InpBlockNewTier1AfterHours, InpBlockAddTier1AfterHours) * 3600;
   datetime to   = now + MathMax(InpNewsLookaheadHours, MathMax(InpBlockNewTier1BeforeHours, InpBlockAddTier1BeforeHours)) * 3600;

   bool usedCsvFallback     = false;
   bool usedIncludeFallback = false;
   bool anyLiveData         = false;

   if(!MQLInfoInteger(MQL_TESTER))
   {
      string ccys[];
      ArrayResize(ccys, 0);

      for(int i = 0; i < ArraySize(g_states); i++)
      {
         string a = BaseCurrency(g_states[i].symbol);
         string b = QuoteCurrency(g_states[i].symbol);

         bool foundA = false, foundB = false;
         for(int k = 0; k < ArraySize(ccys); k++)
         {
            if(ccys[k] == a) foundA = true;
            if(ccys[k] == b) foundB = true;
         }
         if(a != "" && !foundA)
         {
            int n = ArraySize(ccys);
            ArrayResize(ccys, n + 1);
            ccys[n] = a;
         }
         if(b != "" && !foundB)
         {
            int n = ArraySize(ccys);
            ArrayResize(ccys, n + 1);
            ccys[n] = b;
         }
      }

      for(int c = 0; c < ArraySize(ccys); c++)
      {
         MqlCalendarValue values[];
         ResetLastError();
         int count = CalendarValueHistory(values, from, to, NULL, ccys[c]);
         if(count < 0)
            continue;

         anyLiveData = true;
         for(int v = 0; v < count; v++)
         {
            MqlCalendarEvent eventRec;
            if(!CalendarEventById(values[v].event_id, eventRec))
               continue;
            if(!IsHighImpactNewsEvent(eventRec))
               continue;

            bool isTier1 = IsTier1NewsEventName(eventRec.name);
            for(int i = 0; i < ArraySize(g_states); i++)
            {
               if(SymbolContainsCurrency(g_states[i].symbol, ccys[c]))
                  ApplyNewsWindowToState(i, values[v].time, eventRec.name, isTier1, "CAL");
            }
         }
      }
   }

   if(!anyLiveData)
   {
      ArrayResize(g_ffCsvEvents, 0);
      int ffCount = LoadFFCsvEvents(g_ffCsvEvents);
      for(int i = 0; i < ffCount; i++)
      {
         if(g_ffCsvEvents[i].time < from || g_ffCsvEvents[i].time > to)
            continue;

         for(int s = 0; s < ArraySize(g_states); s++)
         {
            if(SymbolContainsCurrency(g_states[s].symbol, g_ffCsvEvents[i].currency))
            {
               ApplyNewsWindowToState(s,
                                      g_ffCsvEvents[i].time,
                                      g_ffCsvEvents[i].title,
                                      g_ffCsvEvents[i].tier1,
                                      "CSV");
               usedCsvFallback = true;
            }
         }
      }
   }

   if(!anyLiveData && !usedCsvFallback)
   {
      HOLO_FallbackNewsEvent fallbackEvents[];
      int fbCount = HoloGetFallbackNewsEvents(fallbackEvents);
      for(int i = 0; i < fbCount; i++)
      {
         if(fallbackEvents[i].time < from || fallbackEvents[i].time > to)
            continue;

         for(int s = 0; s < ArraySize(g_states); s++)
         {
            if(SymbolContainsCurrency(g_states[s].symbol, fallbackEvents[i].currency))
            {
               ApplyNewsWindowToState(s,
                                      fallbackEvents[i].time,
                                      fallbackEvents[i].title,
                                      fallbackEvents[i].tier1,
                                      "INC");
               usedIncludeFallback = true;
            }
         }
      }
   }

   g_newsLiveCalendarOk  = anyLiveData;
   g_newsCacheValidUntil = now + MathMax(1, InpNewsCacheMinutes) * 60;
   return (anyLiveData || usedCsvFallback || usedIncludeFallback);
}

void EnsureNewsCalendarFresh()
{
   datetime now = TimeTradeServer();
   if(now >= g_newsCacheValidUntil)
      RefreshNewsCalendarCache();
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
   ctx.newsBlockNew = g_states[idx].newsBlockNew;
   ctx.atrSpikeBlockNew = g_states[idx].atrSpikeBlockNew;

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
      else if(ctx.newsBlockNew)
         ctx.sellReason = "NEWS";
      else if(ctx.atrSpikeBlockNew)
         ctx.sellReason = "ATR spike";
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
      else if(ctx.newsBlockNew)
         ctx.buyReason = "NEWS";
      else if(ctx.atrSpikeBlockNew)
         ctx.buyReason = "ATR spike";
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

   double point    = SymbolInfoDouble(sym, SYMBOL_POINT);
   double volStep  = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
   if(volStep <= 0.0)
      volStep = 0.01;

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
      double oldEntry = NormalizePrice(sym, OrderGetDouble(ORDER_PRICE_OPEN));
      double oldSl    = NormalizePrice(sym, OrderGetDouble(ORDER_SL));
      double oldLots  = NormalizeLots(sym, OrderGetDouble(ORDER_VOLUME_INITIAL));

      bool entryChanged = (MathAbs(oldEntry - entry) > point);
      bool slChanged    = (MathAbs(oldSl - sl) > point);
      bool lotsChanged  = (MathAbs(oldLots - lots) > (volStep * 0.5));

      if(!entryChanged && !slChanged && !lotsChanged)
         return true;

      // volume cannot be changed with OrderModify -> delete and recreate
      if(lotsChanged)
      {
         if(!InpReplacePendingOnChange)
            return true;

         if(!trade.OrderDelete(existing))
         {
            LogMsg(LOG_ERROR,
                   StringFormat("pending delete before recreate failed %s ticket=%I64u ret=%u",
                                sym, existing, trade.ResultRetcode()));
            return false;
         }

         trade.SetExpertMagicNumber(InpMagic);
         trade.SetDeviationInPoints(10);

         bool ok = false;
         if(type == ORDER_TYPE_BUY_STOP)
            ok = trade.BuyStop(lots, entry, sym, sl, 0.0, ORDER_TIME_GTC, 0, comment);
         else
            ok = trade.SellStop(lots, entry, sym, sl, 0.0, ORDER_TIME_GTC, 0, comment);

         if(!ok)
         {
            LogMsg(LOG_ERROR,
                   StringFormat("pending recreate failed %s type=%d ret=%u entry=%s sl=%s oldLots=%.2f newLots=%.2f",
                                sym, (int)type, trade.ResultRetcode(),
                                FormatPrice(sym, entry), FormatPrice(sym, sl),
                                oldLots, lots));
         }
         return ok;
      }

      // only price and/or SL changed -> modify in place
      if(InpReplacePendingOnChange)
      {
         bool ok = trade.OrderModify(existing, entry, sl, 0.0, ORDER_TIME_GTC, 0, 0.0);
         if(!ok)
         {
            uint rc = trade.ResultRetcode();
            if(rc == TRADE_RETCODE_NO_CHANGES)
               return true;

            LogMsg(LOG_ERROR,
                   StringFormat("pending modify failed %s ticket=%I64u ret=%u oldEntry=%s newEntry=%s oldSL=%s newSL=%s",
                                sym, existing, rc,
                                FormatPrice(sym, oldEntry), FormatPrice(sym, entry),
                                FormatPrice(sym, oldSl), FormatPrice(sym, sl)));
         }
         return ok;
      }

      return true;
   }

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(10);

   if(type == ORDER_TYPE_BUY_STOP)
      return trade.BuyStop(lots, entry, sym, sl, 0.0, ORDER_TIME_GTC, 0, comment);
   return trade.SellStop(lots, entry, sym, sl, 0.0, ORDER_TIME_GTC, 0, comment);
}


double BasketAverageEntryPrice(const string sym = "")
{
   double weightedSum = 0.0;
   double totalLots   = 0.0;

   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;
      if(sym != "" && PositionGetString(POSITION_SYMBOL) != sym)
         continue;

      double lots  = PositionGetDouble(POSITION_VOLUME);
      double price = PositionGetDouble(POSITION_PRICE_OPEN);

      weightedSum += lots * price;
      totalLots   += lots;
   }

   if(totalLots <= 0.0)
      return 0.0;

   return weightedSum / totalLots;
}

double GridTargetPrice(const int basketIdx)
{
   if(basketIdx < 0 || basketIdx >= ArraySize(g_baskets))
      return 0.0;

   if(!g_baskets[basketIdx].active || g_baskets[basketIdx].symbol == "")
      return 0.0;

   if(InpGridTakeProfitPctPrice <= 0.0)
      return 0.0;

   double avgEntry = BasketAverageEntryPrice(g_baskets[basketIdx].symbol);
   if(avgEntry <= 0.0)
      return 0.0;

   double pct = InpGridTakeProfitPctPrice / 100.0;

   if(g_baskets[basketIdx].direction == POSITION_TYPE_BUY)
      return NormalizePrice(g_baskets[basketIdx].symbol, avgEntry * (1.0 + pct));

   if(g_baskets[basketIdx].direction == POSITION_TYPE_SELL)
      return NormalizePrice(g_baskets[basketIdx].symbol, avgEntry * (1.0 - pct));

   return 0.0;
}

double GridTrailArmPriceDistance(const int basketIdx)
{
   if(basketIdx < 0 || basketIdx >= ArraySize(g_baskets))
      return 0.0;

   if(!g_baskets[basketIdx].active || g_baskets[basketIdx].symbol == "")
      return 0.0;

   if(InpGridTakeProfitPctPrice <= 0.0)
      return 0.0;

   double avgEntry = BasketAverageEntryPrice(g_baskets[basketIdx].symbol);
   if(avgEntry <= 0.0)
      return 0.0;

   double targetDistance = avgEntry * (InpGridTakeProfitPctPrice / 100.0);
   return targetDistance * InpGridTrailArmPctTarget / 100.0;
}

void StartCooldown(const string reasonTag)
{
   g_cooldownUntil = TimeTradeServer() + InpCooldownMinutesAfterSL * 60;
   g_lastSLReason  = reasonTag;
}



double NextGridLots(const int basketIdx)
{
   if(basketIdx < 0 || basketIdx >= ArraySize(g_baskets))
      return 0.0;
   if(!g_baskets[basketIdx].active || g_baskets[basketIdx].symbol == "")
      return 0.0;

   int exponent = MathMax(0, g_baskets[basketIdx].levels);
   double baseLots = g_baskets[basketIdx].baseLots;
   if(baseLots <= 0.0)
      baseLots = NormalizeLots(g_baskets[basketIdx].symbol, InpLots);

   return NormalizeLots(g_baskets[basketIdx].symbol, baseLots * MathPow(InpGridLotMultiplier, exponent));
}

bool CloseBasket(const string sym, const string reason, const bool startCooldownAfterClose = false)
{
   bool allOk = true;
   CancelPendingsForSymbol(sym);

   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != sym)
         continue;

      if(!trade.PositionClose(ticket))
         allOk = false;
   }

   int idx = GetStateIndexBySymbol(sym);
   if(allOk && idx >= 0)
   {
      RegisterClosedBasketAge(idx);
      g_baskets[idx].closeReason = reason;
      if(startCooldownAfterClose)
         StartCooldown(reason);
      ResetBasketState(idx);
   }
   return allOk;
}

bool CloseAllBaskets(const string reason, const bool startCooldownAfterClose = false)
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

      string sym = PositionGetString(POSITION_SYMBOL);
      if(!trade.PositionClose(ticket))
      {
         allOk = false;
         LogMsg(LOG_ERROR,
                StringFormat("CLOSE_ALL failed | %s | ticket=%I64u | ret=%u",
                             sym, ticket, trade.ResultRetcode()));
      }
   }

   if(allOk)
   {
      if(startCooldownAfterClose)
         StartCooldown(reason);

      for(int i = 0; i < ArraySize(g_baskets); i++)
      {
         if(g_baskets[i].active)
         {
            RegisterClosedBasketAge(i);
            g_baskets[i].closeReason = reason;
         }
         ResetBasketState(i);
      }
   }

   return allOk;
}

bool OpenGridLevel(const int basketIdx)
{
   if(basketIdx < 0 || basketIdx >= ArraySize(g_baskets))
      return false;
   if(!g_baskets[basketIdx].active || g_baskets[basketIdx].symbol == "")
      return false;
   if(g_baskets[basketIdx].levels >= InpGridMaxLevels)
      return false;

   double bid = 0.0, ask = 0.0;
   string sym = g_baskets[basketIdx].symbol;
   if(!GetTickPrices(sym, bid, ask))
      return false;

   double lots = NextGridLots(basketIdx);
   if(lots <= 0.0)
      return false;

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(10);

   bool ok = false;
   if(g_baskets[basketIdx].direction == POSITION_TYPE_BUY)
      ok = trade.Buy(lots, sym, ask, 0.0, 0.0, StringFormat("HOLO Grid L%d", g_baskets[basketIdx].levels + 1));
   else if(g_baskets[basketIdx].direction == POSITION_TYPE_SELL)
      ok = trade.Sell(lots, sym, bid, 0.0, 0.0, StringFormat("HOLO Grid L%d", g_baskets[basketIdx].levels + 1));

   if(ok)
   {
      g_baskets[basketIdx].levels++;
      g_baskets[basketIdx].lastAddPrice = (g_baskets[basketIdx].direction == POSITION_TYPE_BUY ? ask : bid);
      LogMsg(LOG_INFO,
             StringFormat("GRID_ADD | %s | dir=%s | level=%d | lots=%.2f | ref=%s",
                          sym,
                          (g_baskets[basketIdx].direction == POSITION_TYPE_BUY ? "BUY" : "SELL"),
                          g_baskets[basketIdx].levels,
                          lots,
                          FormatPrice(sym, g_baskets[basketIdx].lastAddPrice)));
      LogExposureSnapshot("AFTER_GRID_ADD");
   }
   return ok;
}

void ManageGridBasket()
{
   if(!InpUseGridBasket)
      return;

   SyncBasketStates();

   bool hasStaleBasket = HasStaleBasket(24.0);
   if(hasStaleBasket)
   {
      double globalRecoveryPnl = BasketNetProfit();
      if(globalRecoveryPnl > 0.0)
      {
         LogMsg(LOG_INFO,
                StringFormat("STALE_RECOVERY_CLOSE_ALL | globalPnl=%.2f", globalRecoveryPnl));
         CloseAllBaskets("global pnl > 0 with stale basket recovery", false);
         return;
      }
   }

   for(int bi = 0; bi < ArraySize(g_baskets); bi++)
   {
      if(!g_baskets[bi].active)
         continue;

      string sym = g_baskets[bi].symbol;
      if(!HasOpenPosition(sym))
      {
         ResetBasketState(bi);
         continue;
      }

      int idx = g_baskets[bi].symbolIndex;
      if(idx < 0)
         idx = GetStateIndexBySymbol(sym);
      if(idx < 0)
         continue;

      double bid = 0.0, ask = 0.0;
      if(!GetTickPrices(sym, bid, ask))
         continue;

      double pnl          = BasketNetProfit(sym);
      int basketOrders    = BasketPositionCount(sym);
      double globalPnl    = AccountInfoDouble(ACCOUNT_PROFIT);
      double avgEntry     = BasketAverageEntryPrice(sym);
      double targetPrice  = GridTargetPrice(bi);
      double trailArmDist = GridTrailArmPriceDistance(bi);
      double curPrice     = (g_baskets[bi].direction == POSITION_TYPE_BUY ? bid : ask);

      if(ShouldPreCloseBeforeNews(idx) && pnl > 0.0)
      {
         CloseBasket(sym, "profit close before news", false);
         continue;
      }

      if(InpGridUseAnchorHardStop && g_baskets[bi].anchorSL > 0.0)
      {
         if(g_baskets[bi].direction == POSITION_TYPE_BUY && bid <= g_baskets[bi].anchorSL)
         {
            CloseBasket(sym, "grid stop @ daily low", true);
            continue;
         }
         if(g_baskets[bi].direction == POSITION_TYPE_SELL && ask >= g_baskets[bi].anchorSL)
         {
            CloseBasket(sym, "grid stop @ daily high", true);
            continue;
         }
      }
      double basketAgeHours = BasketAgeHours(bi);
      bool staleBasketManaged   = (basketAgeHours >= 24.0);
      bool recoveryRunner       = IsRecoveryRunnerBasket(bi, 24.0);
      bool holdForStaleRecovery = (hasStaleBasket && recoveryRunner);

      if(staleBasketManaged && pnl > 0.0)
      {
         LogMsg(LOG_INFO,
                StringFormat("STALE_BASKET_PROFIT_CLOSE | basket=%s | pnl=%.2f | ageH=%.1f",
                             sym, pnl, basketAgeHours));
         CloseBasket(sym, "stale basket > 24h and in profit", false);
         continue;
      }

      if(InpBasketProfitCloseMinOrders > 0 && basketOrders >= InpBasketProfitCloseMinOrders)
      {
         if(globalPnl > 0.0)
         {
            LogMsg(LOG_INFO,
                   StringFormat("GLOBAL_PROFIT_FLUSH | basket=%s | basketOrders=%d | basketPnl=%.2f | globalPnl=%.2f",
                                sym, basketOrders, pnl, globalPnl));
            CloseAllBaskets("global pnl > 0 with large basket", false);
            return;
         }

         if(!holdForStaleRecovery && pnl > 0.0)
         {
            LogMsg(LOG_INFO,
                   StringFormat("BASKET_PROFIT_FLUSH | basket=%s | basketOrders=%d | basketPnl=%.2f",
                                sym, basketOrders, pnl));
            CloseBasket(sym, "basket pnl > 0 with large basket", false);
            continue;
         }
      }

      if(holdForStaleRecovery)
      {
         LogMsg(LOG_DEBUG,
                StringFormat("STALE_RECOVERY_HOLD | basket=%s | pnl=%.2f | ageH=%.1f | mode=runner",
                             sym, pnl, basketAgeHours));
      }

   if(!holdForStaleRecovery)
   {
      if(InpGridUseBasketTrail && trailArmDist > 0.0 && avgEntry > 0.0)
      {
         double armPrice = 0.0;

         if(g_baskets[bi].direction == POSITION_TYPE_BUY)
            armPrice = avgEntry + trailArmDist;
         else if(g_baskets[bi].direction == POSITION_TYPE_SELL)
            armPrice = avgEntry - trailArmDist;

         armPrice = NormalizePrice(g_baskets[bi].symbol, armPrice);

         bool armNow = false;
         if(g_baskets[bi].direction == POSITION_TYPE_BUY)
            armNow = (bid >= armPrice);
         else if(g_baskets[bi].direction == POSITION_TYPE_SELL)
            armNow = (ask <= armPrice);

         if(!g_baskets[bi].trailActive && armNow)
         {
            g_baskets[bi].trailActive = true;
            g_baskets[bi].trailPeakPnl = pnl;
         }

         if(g_baskets[bi].trailActive)
         {
            if(pnl > g_baskets[bi].trailPeakPnl)
               g_baskets[bi].trailPeakPnl = pnl;

            double retraceMoney = g_baskets[bi].trailPeakPnl * InpGridTrailRetracePctPeak / 100.0;
            double floorPnl = MathMax(0.0, g_baskets[bi].trailPeakPnl - retraceMoney);

            if(g_baskets[bi].trailPeakPnl > 0.0 && pnl <= floorPnl)
            {
               CloseBasket(g_baskets[bi].symbol,"basket trail close", false);
               return;
            }
         }
      }
      else if(targetPrice > 0.0)
      {
         bool hitTp = false;

         if(g_baskets[bi].direction == POSITION_TYPE_BUY)
            hitTp = (bid >= targetPrice);
         else if(g_baskets[bi].direction == POSITION_TYPE_SELL)
            hitTp = (ask <= targetPrice);

         if(hitTp)
         {
            CloseBasket(g_baskets[bi].symbol,"basket TP", false);
            return;
         }
      }
   }

      if(!IsTradingWindow())
         continue;
      if(g_baskets[bi].levels >= InpGridMaxLevels)
         continue;
      if(g_states[idx].newsBlockAdd)
         continue;
      if(g_states[idx].atrSpikeBlockAdd)
         continue;

      double pip = g_states[idx].pip;
      double adversePips = 0.0;

      if(g_baskets[bi].direction == POSITION_TYPE_BUY)
         adversePips = (g_baskets[bi].lastAddPrice - bid) / pip;
      else if(g_baskets[bi].direction == POSITION_TYPE_SELL)
         adversePips = (ask - g_baskets[bi].lastAddPrice) / pip;

      if(adversePips >= InpGridGapPips)
         OpenGridLevel(bi);
   }

   LogExposureSnapshot("GRID_MGMT");
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

   SyncBasketStates();

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

      if(ctx.newsBlockNew || ctx.atrSpikeBlockNew)
      {
         CancelPendingsForSymbol(sym);
         continue;
      }

      if(HasOpenPosition(sym))
      {
         if(InpCancelOppositeOnFill)
            CancelPendingsForSymbol(sym);
         continue;
      }

      bool basketAllowedSell = CanOpenNewBasket(sym, POSITION_TYPE_SELL);
      bool basketAllowedBuy  = CanOpenNewBasket(sym, POSITION_TYPE_BUY);

      bool sellOk = (ctx.sellSignal && basketAllowedSell);
      bool buyOk  = (ctx.buySignal  && basketAllowedBuy);

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
      string sym = HistoryDealGetString(trans.deal, DEAL_SYMBOL);
      ENUM_DEAL_REASON reason = (ENUM_DEAL_REASON)HistoryDealGetInteger(trans.deal, DEAL_REASON);

      if(reason == DEAL_REASON_SL)
      {
         datetime dealTime = (datetime)HistoryDealGetInteger(trans.deal, DEAL_TIME);
         StartCooldown("SL @ " + TimeToString(dealTime, TIME_DATE|TIME_MINUTES));
      }

      if(!HasOpenPosition(sym))
      {
         int idx = GetStateIndexBySymbol(sym);
         if(idx >= 0)
            ResetBasketState(idx);
      }
   }
   else if(entry == DEAL_ENTRY_IN)
   {
      string sym = HistoryDealGetString(trans.deal, DEAL_SYMBOL);
      int idx = GetStateIndexBySymbol(sym);
      int dealType = (int)HistoryDealGetInteger(trans.deal, DEAL_TYPE);
      double dealPrice = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
      double dealVolume = HistoryDealGetDouble(trans.deal, DEAL_VOLUME);

      if(idx >= 0)
      {
         bool wasActive = g_baskets[idx].active;
         SyncBasketStates();

         LogBasketOpenContext(sym,
                              (dealType == DEAL_TYPE_BUY ? POSITION_TYPE_BUY : POSITION_TYPE_SELL),
                              dealPrice,
                              dealVolume,
                              (wasActive ? "BASKET_ADD" : "BASKET_OPEN"));

         LogExposureSnapshot(wasActive ? "AFTER_BASKET_ADD" : "AFTER_BASKET_OPEN");
      }
   }

   if(InpCancelOppositeOnFill)
   {
      string sym = HistoryDealGetString(trans.deal, DEAL_SYMBOL);
      if(HasOpenPosition(sym))
         CancelPendingsForSymbol(sym);
   }
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

   int bgW = 1385;
   int rows = ArraySize(g_states);
   int bgH = 238 + rows * 18;

   CreatePanelRect("BG", 20, 30, bgW, bgH, tmdBg, tmdBg);
   CreatePanelRect("TB", 23, 33, bgW - 6, 28, tmdBg, tmdBg);
   CreatePanelRect("S1", 30, 67, bgW - 40, 1, tmdSubtleBg, tmdBg);
   CreatePanelRect("S2", 30, 153, bgW - 40, 1, tmdSubtleBg, tmdBg);

   CreatePanelLabel("ONLINE_DOT", 30, 40, 10, tmdGreen, "●");
   CreatePanelLabel("ONLINE_TXT", 44, 40, 9, C'0,180,180', "ONLINE");
   CreatePanelLabel("SERVER", 110, 40, 9, tmdSilver, "--:--:--");
   CreatePanelLabel("TITLE", 595, 38, 11, C'0,230,230', "◆ HOLO EA MS ◆", ANCHOR_UPPER);

   CreatePanelLabel("G1L", 30, 76, 8, C'70,90,110', "BALANCE");
   CreatePanelLabel("G1V", 180, 76, 8, tmdSilver, "-", ANCHOR_RIGHT_UPPER);
   CreatePanelLabel("G2L", 30, 92, 8, C'70,90,110', "EQUITY");
   CreatePanelLabel("G2V", 180, 92, 8, tmdSilver, "-", ANCHOR_RIGHT_UPPER);
   CreatePanelLabel("G3L", 30, 108, 8, C'70,90,110', "P/L");
   CreatePanelLabel("G3V", 180, 108, 8, tmdSilver, "-", ANCHOR_RIGHT_UPPER);
   CreatePanelLabel("G10L", 30, 124, 8, C'70,90,110', "DD / MAX");
   CreatePanelLabel("G10V", 180, 124, 8, tmdSilver, "-", ANCHOR_RIGHT_UPPER);

   CreatePanelLabel("G4L", 230, 76, 8, C'70,90,110', "GRID STATE");
   CreatePanelLabel("G4V", 575, 76, 8, tmdSilver, "-", ANCHOR_RIGHT_UPPER);
   CreatePanelLabel("G5L", 230, 92, 8, C'70,90,110', "WINDOW / COOLDOWN");
   CreatePanelLabel("G5V", 575, 92, 8, tmdSilver, "-", ANCHOR_RIGHT_UPPER);
   CreatePanelLabel("G6L", 230, 108, 8, C'70,90,110', "PENDINGS / SYMBOLS");
   CreatePanelLabel("G6V", 575, 108, 8, tmdSilver, "-", ANCHOR_RIGHT_UPPER);
   CreatePanelLabel("G11L", 230, 124, 8, C'70,90,110', "MARGIN LEVEL");
   CreatePanelLabel("G11V", 575, 124, 8, tmdSilver, "-", ANCHOR_RIGHT_UPPER);

   CreatePanelLabel("G7L", 625, 76, 8, C'70,90,110', "RISK / LOT");
   CreatePanelLabel("G7V", 1070, 76, 8, tmdSilver, "-", ANCHOR_RIGHT_UPPER);
   CreatePanelLabel("G8L", 625, 92, 8, C'70,90,110', "GRID CFG");
   CreatePanelLabel("G8V", 1070, 92, 8, tmdSilver, "-", ANCHOR_RIGHT_UPPER);
   CreatePanelLabel("G9L", 625, 108, 8, C'70,90,110', "LAST SL");
   CreatePanelLabel("G9V", 1070, 108, 8, tmdSilver, "-", ANCHOR_RIGHT_UPPER);
   CreatePanelLabel("G12L", 625, 124, 8, C'70,90,110', "AVG HOLD");
   CreatePanelLabel("G12V", 1070, 124, 8, tmdSilver, "-", ANCHOR_RIGHT_UPPER);

   CreatePanelLabel("SYMHDR", 30, 162, 9, C'180,40,220', "SYMBOLS");
   CreatePanelLabel("COL1", 120, 162, 8, C'70,90,110', "LEVELS");
   CreatePanelLabel("COL2", 235, 162, 8, C'70,90,110', "PEND");
   CreatePanelLabel("COL3", 305, 162, 8, C'70,90,110', "BUY");
   CreatePanelLabel("COL4", 385, 162, 8, C'70,90,110', "SELL");
   CreatePanelLabel("COL5", 470, 162, 8, C'70,90,110', "CD");
   CreatePanelLabel("COL6", 540, 162, 8, C'70,90,110', "M15");
   CreatePanelLabel("COL7", 615, 162, 8, C'70,90,110', "SPR");
   CreatePanelLabel("COL8", 685, 162, 8, C'70,90,110', "ATR%");
   CreatePanelLabel("COL9", 760, 162, 8, C'70,90,110', "NEWS");
   CreatePanelLabel("COL10", 825, 162, 8, C'70,90,110', "SPK");
   CreatePanelLabel("COL11", 895, 162, 8, C'70,90,110', "PNL");
   CreatePanelLabel("COL12", 965, 162, 8, C'70,90,110', "BPOS");
   CreatePanelLabel("COL13", 1025, 162, 8, C'70,90,110', "BAVG");
   CreatePanelLabel("COL14", 1105, 162, 8, C'70,90,110', "BDD%");
   CreatePanelLabel("COL15", 1175, 162, 8, C'70,90,110', "TP%");
   CreatePanelLabel("COL16", 1245, 162, 8, C'70,90,110', "AGEH");
   CreatePanelLabel("COL17", 1360, 162, 8, C'70,90,110', "ACTIVE", ANCHOR_RIGHT_UPPER);

   for(int i = 0; i < rows; i++)
   {
      int y = 182 + i * 18;
      CreatePanelLabel("R_SYM_" + IntegerToString(i), 30, y, 8, tmdSilver, "-");
      CreatePanelLabel("R_LVL_" + IntegerToString(i), 120, y, 8, tmdSilver, "-");
      CreatePanelLabel("R_PND_" + IntegerToString(i), 235, y, 8, tmdSilver, "-");
      CreatePanelLabel("R_BUY_" + IntegerToString(i), 305, y, 8, tmdSilver, "-");
      CreatePanelLabel("R_SEL_" + IntegerToString(i), 385, y, 8, tmdSilver, "-");
      CreatePanelLabel("R_CD_" + IntegerToString(i), 470, y, 8, tmdSilver, "-");
      CreatePanelLabel("R_M15_" + IntegerToString(i), 540, y, 8, tmdSilver, "-");
      CreatePanelLabel("R_SPR_" + IntegerToString(i), 615, y, 8, tmdSilver, "-");
      CreatePanelLabel("R_ATR_"  + IntegerToString(i), 685,  y, 8, tmdSilver, "-");
      CreatePanelLabel("R_NEWS_" + IntegerToString(i), 760,  y, 8, tmdSilver, "-");
      CreatePanelLabel("R_SPK_"  + IntegerToString(i), 825,  y, 8, tmdSilver, "-");
      CreatePanelLabel("R_PNL_"  + IntegerToString(i), 895,  y, 8, tmdSilver, "-");
      CreatePanelLabel("R_BPOS_" + IntegerToString(i), 965,  y, 8, tmdSilver, "-");
      CreatePanelLabel("R_BAVG_" + IntegerToString(i), 1025, y, 8, tmdSilver, "-");
      CreatePanelLabel("R_BDD_"  + IntegerToString(i), 1105, y, 8, tmdSilver, "-");
      CreatePanelLabel("R_BTP_"  + IntegerToString(i), 1175, y, 8, tmdSilver, "-");
      CreatePanelLabel("R_AGE_"  + IntegerToString(i), 1245, y, 8, tmdSilver, "-");
      CreatePanelLabel("R_ACT_"  + IntegerToString(i), 1360, y, 8, tmdSilver, "-", ANCHOR_RIGHT_UPPER);
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

double BasketFloatingDDPct(const string sym)
{
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   if(bal <= 0.0)
      return 0.0;

   double ddMoney = BasketFloatingDDMoney(sym);
   if(ddMoney <= 0.0)
      return 0.0;

   return 100.0 * ddMoney / bal;
}

string BasketFloatingDDPctText(const string sym)
{
   double ddPct = BasketFloatingDDPct(sym);
   if(ddPct <= 0.0)
      return "-";

   return FormatPercent(ddPct);
}

double BasketTpDistancePct(const int basketIdx)
{
   if(basketIdx < 0 || basketIdx >= ArraySize(g_baskets))
      return -1.0;
   if(!g_baskets[basketIdx].active || g_baskets[basketIdx].symbol == "")
      return -1.0;

   double tpPrice = GridTargetPrice(basketIdx);
   if(tpPrice <= 0.0)
      return -1.0;

   double bid = 0.0, ask = 0.0;
   string sym = g_baskets[basketIdx].symbol;
   if(!GetTickPrices(sym, bid, ask))
      return -1.0;

   double curPrice = 0.0;
   if(g_baskets[basketIdx].direction == POSITION_TYPE_BUY)
   {
      curPrice = bid;
      if(tpPrice <= curPrice || curPrice <= 0.0)
         return 0.0;
      return 100.0 * (tpPrice - curPrice) / curPrice;
   }

   if(g_baskets[basketIdx].direction == POSITION_TYPE_SELL)
   {
      curPrice = ask;
      if(tpPrice >= curPrice || curPrice <= 0.0)
         return 0.0;
      return 100.0 * (curPrice - tpPrice) / curPrice;
   }

   return -1.0;
}

string BasketTpDistancePctText(const int basketIdx)
{
   double pct = BasketTpDistancePct(basketIdx);
   if(pct < 0.0)
      return "-";
   return FormatPercent(pct);
}

void UpdatePanel()
{
   if(!InpShowPanel)
      return;

   double bal         = AccountInfoDouble(ACCOUNT_BALANCE);
   double eq          = AccountInfoDouble(ACCOUNT_EQUITY);
   double pnl         = AccountInfoDouble(ACCOUNT_PROFIT);
   UpdateMaxGlobalDrawdown();

   double ddMoney     = GlobalDrawdownMoney();
   double ddPct       = GlobalDrawdownPct();
   double marginLevel = AccountMarginLevelPct();
   double avgHoldHrs  = AverageHoldingHours();

   color pnlClr = (pnl > 0.0 ? tmdGreen : (pnl < 0.0 ? tmdRed : tmdSilver));
   color ddClr  = (ddMoney > 0.0 ? tmdRed : tmdGreen);

   color marginClr = tmdSilver;
   if(marginLevel > 0.0)
   {
      if(marginLevel < 150.0)      marginClr = tmdRed;
      else if(marginLevel < 300.0) marginClr = tmdOrange;
      else                         marginClr = tmdGreen;
   }

   SetPanelText("SERVER", FormatServerDateTime(TimeTradeServer()), tmdSilver);
   SetPanelText("ONLINE_DOT", "●", InpEnableEA ? tmdGreen : tmdRed);
   SetPanelText("ONLINE_TXT", InpEnableEA ? "ONLINE" : "OFFLINE", InpEnableEA ? C'0,180,180' : tmdRed);

   SetPanelText("G1V", FormatMoney(bal), tmdSilver);
   SetPanelText("G2V", FormatMoney(eq), tmdSilver);
   SetPanelText("G3V", FormatMoney(pnl), pnlClr);
   SetPanelText("G10V", FormatPercent(ddPct) + " / " + FormatPercent(g_maxGlobalDdPct), ddClr);

   string gridState = BasketSummaryText(InpMaxConcurrentBaskets);
   color gridClr = (ActiveBasketCount() > 0 ? tmdOrange : tmdSilver);
   SetPanelText("G4V", FitPanelText(gridState, 46), gridClr);

   string cdTxt = (IsTradingWindow() ? "OPEN" : "CLOSED");
   if(IsCooldownActive())
      cdTxt += " / COOLDOWN";
   SetPanelText("G5V", cdTxt, IsCooldownActive() ? tmdOrange : (IsTradingWindow() ? tmdGreen : tmdRed));

   SetPanelText("G6V", IntegerToString(PendingCount()) + " / " + IntegerToString(ArraySize(g_states)), tmdSilver);

   string marginTxt = (marginLevel > 0.0 ? FormatPercent(marginLevel) : "N/A");
   SetPanelText("G11V", marginTxt, marginClr);

   string riskModeTxt = "MED";
   if(InpRiskMode == RISK_LOW)  riskModeTxt = "LOW";
   if(InpRiskMode == RISK_HIGH) riskModeTxt = "HIGH";

   SetPanelText("G7V",
                StringFormat("%s / SL-%s / base %.2f",
                             riskModeTxt,
                             (InpUseSLBasedLot ? "ON" : "OFF"),
                             InpLots),
                tmdSilver);

   SetPanelText("G8V",
                StringFormat("gap %dp / max %d / x%.2f / baskets %d",
                             InpGridGapPips,
                             InpGridMaxLevels,
                             InpGridLotMultiplier,
                             InpMaxConcurrentBaskets),
                tmdSilver);

   SetPanelText("G9V", FitPanelText(g_lastSLReason, 56), tmdSilver);
   SetPanelText("G12V", (BasketPositionCount() > 0 ? FormatHours(avgHoldHrs, 1) : "-"), tmdSilver);

   int rows = ArraySize(g_states);
   for(int i = 0; i < rows; i++)
   {
      SignalContext ctx;
      EvaluateSignalContext(i, ctx);

      string sym       = g_states[i].symbol;
      double symPnl    = SymbolOpenPnl(sym);
      int basketPos    = BasketPositionCountBySymbol(sym);
      double basketDdPct = BasketFloatingDDPct(sym);
      double basketTpPct = BasketTpDistancePct(i);

      color symPnlClr  = (symPnl > 0.0 ? tmdGreen : (symPnl < 0.0 ? tmdRed : tmdSilver));
      color bddClr     = (basketDdPct > 0.0 ? tmdRed : tmdSilver);
      color btpClr     = (basketTpPct > 0.0 ? tmdOrange : tmdSilver);

      string levels    = FitPanelText(FormatPrice(sym, g_states[i].hoH1) + " / " + FormatPrice(sym, g_states[i].loH1), 14);
      string pnd       = IntegerToString(PendingCount(sym));
      string buy       = (g_states[i].buySignal  ? "READY" : FitPanelText(g_states[i].buyReason,  9));
      string sell      = (g_states[i].sellSignal ? "READY" : FitPanelText(g_states[i].sellReason, 9));
      string cd        = (IsCooldownActive() ? "YES" : "-");
      string m15       = StringFormat("S:%s B:%s",
                                      (g_states[i].sellM15Ok ? "Y" : "N"),
                                      (g_states[i].buyM15Ok  ? "Y" : "N"));
      string spr       = FormatPips(g_states[i].spreadPips);
      string atr       = DoubleToString(g_states[i].rangeAtrPct, 0);
      string newsTxt   = "-";
      if(g_states[i].newsBlockNew || g_states[i].newsBlockAdd)
      {
         newsTxt = (g_states[i].newsSource != "" ? g_states[i].newsSource : "ON");
         if(g_states[i].newsHasUpcoming && g_states[i].nextNewsTag != "")
            newsTxt += ":" + g_states[i].nextNewsTag;
      }
      else if(g_states[i].newsHasUpcoming)
      {
         newsTxt = (g_states[i].newsSource != "" ? g_states[i].newsSource : "NX");
         if(g_states[i].nextNewsTag != "")
            newsTxt += ":" + g_states[i].nextNewsTag;
      }

      string spikeTxt  = "-";
      if(InpUseAtrSpikeFilter)
         spikeTxt = StringFormat("%.2f/%.2f", g_states[i].atrSpikeRatio, g_states[i].curTfRangeAtr);

      string pnlTxt    = FormatMoney(symPnl);
      string bposTxt   = IntegerToString(basketPos);
      string bavgTxt   = BasketAvgEntryText(sym);
      string bddTxt    = BasketFloatingDDPctText(sym);
      string btpTxt    = BasketTpDistancePctText(i);
      string ageTxt    = BasketAgeHoursText(i);

      string state = "WAIT";
      color stateClr = tmdSilver;

      if(g_states[i].sellSignal)
      {
         state = "SELL";
         stateClr = Color_HO;
      }
      else if(g_states[i].buySignal)
      {
         state = "BUY";
         stateClr = Color_LO;
      }
      else if(g_states[i].spreadPips > InpMaxSpreadPips)
      {
         state = "SPREAD";
         stateClr = tmdRed;
      }

      string activeTxt = "-";
      color activeClr  = tmdSilver;

      int bidx = i;
      if(bidx >= 0 && bidx < ArraySize(g_baskets) && g_baskets[bidx].active)
      {
         bool staleMode   = (BasketAgeHours(bidx) >= 24.0);
         bool recoverMode = IsRecoveryRunnerBasket(bidx, 24.0);

         if(staleMode)
         {
            activeTxt = "STALE "
                      + (g_baskets[bidx].direction == POSITION_TYPE_BUY ? "B" : "S")
                      + IntegerToString(g_baskets[bidx].levels);
            activeClr = tmdRed;
         }
         else if(recoverMode)
         {
            activeTxt = "RECOV "
                      + (g_baskets[bidx].direction == POSITION_TYPE_BUY ? "B" : "S")
                      + IntegerToString(g_baskets[bidx].levels);
            activeClr = tmdGreen;
         }
         else
         {
            activeTxt = "GRID "
                      + (g_baskets[bidx].direction == POSITION_TYPE_BUY ? "B" : "S")
                      + IntegerToString(g_baskets[bidx].levels);
            activeClr = tmdOrange;
         }
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
      SetPanelText("R_ATR_"  + IntegerToString(i), atr, g_states[i].rangeAtrPct >= InpMinRangeAtrPct ? tmdGreen : tmdSilver);
      SetPanelText("R_NEWS_" + IntegerToString(i), newsTxt, (g_states[i].newsBlockNew || g_states[i].newsBlockAdd) ? tmdRed : (g_states[i].newsHasUpcoming ? tmdOrange : tmdSilver));
      SetPanelText("R_SPK_"  + IntegerToString(i), spikeTxt, (g_states[i].atrSpikeBlockNew || g_states[i].atrSpikeBlockAdd) ? tmdRed : tmdSilver);
      SetPanelText("R_PNL_"  + IntegerToString(i), pnlTxt,  symPnlClr);
      SetPanelText("R_BPOS_" + IntegerToString(i), bposTxt, basketPos > 0 ? tmdOrange : tmdSilver);
      SetPanelText("R_BAVG_" + IntegerToString(i), bavgTxt, basketPos > 0 ? tmdSilver : tmdSilver);
      SetPanelText("R_BDD_"  + IntegerToString(i), bddTxt,  bddClr);
      SetPanelText("R_BTP_"  + IntegerToString(i), btpTxt,  btpClr);
      SetPanelText("R_AGE_"  + IntegerToString(i), ageTxt,  basketPos > 0 ? tmdOrange : tmdSilver);
      SetPanelText("R_ACT_"  + IntegerToString(i), activeTxt, activeClr);
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

   if(!ParseSymbols())
      return INIT_FAILED;

   ResetAllBasketStates();

   StyleChart();
   CreatePanel();
   RefreshNewsCalendarCache();
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
