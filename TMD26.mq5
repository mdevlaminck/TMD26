//+------------------------------------------------------------------+
//|                                      TMD26_EA_MT5_multisymbol_grid|
//+------------------------------------------------------------------+
#property copyright "MDV"
#property version   "1.34"
#property strict

#include <Trade/Trade.mqh>

CTrade trade;

enum ENUM_TMD_LOG_LEVEL
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

enum ENUM_COMMISSION_MODE
{
   COMMISSION_OFF = 0,
   COMMISSION_HISTORY_PLUS_ESTIMATED_CLOSE = 1,
   COMMISSION_ESTIMATED_ROUND_TURN = 2
};

input group "=== Master ==="
input bool   InpEnableEA                = true;
input ulong  InpMagic                   = 26040301;
input ENUM_TMD_LOG_LEVEL InpLogLevel   = LOG_INFO;

input group "=== Symbols ==="
input string InpSymbols = "EURAUD,NZDCAD,AUDCAD";
input bool   InpAutoDetectBrokerSymbols = true;   // Finds broker symbols such as m.EURAUD, EURAUD.a, EURAUD.r automatically.
input string InpBrokerSymbolPrefix      = "";     // Optional forced prefix, e.g. "m.". Leave empty for auto-detect.
input string InpBrokerSymbolSuffix      = "";     // Optional forced suffix, e.g. ".a" or ".r". Leave empty for auto-detect.

input group "=== Trading Window ==="
input int    InpServerStartHour         = 1;
input int    InpServerEndHour           = 23;
input int    InpCooldownMinutesAfterSL  = 5;
input bool   InpBlockJuly               = false;
input bool   InpBlockYearEndHoliday     = false;
input int    InpHolidayStartMonth       = 12;
input int    InpHolidayStartDay         = 20;
input int    InpHolidayEndMonth         = 1;
input int    InpHolidayEndDay           = 10;
input bool InpUseFridayStopHour = true;
input int  InpFridayStopHour    = 16;   

input string InpBlockedEntryHours = "6";          // InpBlockedEntryHours Global block, applies to all symbols. Best result from test B.
input string InpPairBlockedEntryHours = "EURAUD=2;NZDCAD=20";       // InpPairBlockedEntryHours Optional. Format: "EURAUD=2;NZDCAD=20". Applies on all days.
input string InpPairDayBlockedEntryHours = "EURAUD:4=14;NZDCAD:1=4;AUDCAD:5=5";    // InpPairDayBlockedEntryHours Optional. Format: "EURAUD:4=14;NZDCAD:1,3=6". Day: 1=Mon ... 5=Fri.
input group "=== Order Placement ==="
input double InpLots                    = 0.10;
input int    InpMaxSpreadPips           = 3;
input int    InpDeviationPoints          = 10;
input bool   InpCancelOppositeOnFill    = true;
input bool   InpReplacePendingOnChange  = true;
input int    InpEntryBufferPoints       = 0;
input int    InpMinStopDistancePips     = 5;

input int    InpPendingMinLifeSeconds   = 0;
input double InpPendingRecalcMinPips    = 2.0;

input group "=== Evaluation Timing ==="
input bool            InpEntryOnlyOnNewBar       = true;
input ENUM_TIMEFRAMES InpEntryEvalTF             = PERIOD_M15;

input bool            InpGridOnlyOnNewBar        = true;
input ENUM_TIMEFRAMES InpGridEvalTF              = PERIOD_M5;

// Keep false for now. Basket exits should stay fast.
input bool            InpBasketExitOnlyOnNewBar  = false;
input ENUM_TIMEFRAMES InpBasketExitTF            = PERIOD_M1;

input group "=== Lot Sizing ==="
input ENUM_RISK_MODE InpRiskMode        = RISK_HIGH;
input double InpRiskLowPct              = 0.10;
input double InpRiskMedPct              = 0.20;
input double InpRiskHighPct             = 0.50;
input bool   InpUseSLBasedLot           = true;
input double InpFallbackLot             = 0.10;

input group "=== Broker Costs / Commission ==="
input ENUM_COMMISSION_MODE InpCommissionMode = COMMISSION_OFF;
input double InpCommissionPerLotRoundTurn = 0.0;  // Account currency per 1.00 lot, open+close. Example: 7.0 means 7 account-currency units per round turn lot.
input double InpCommissionPerLotPerSide   = 0.0;  // Optional. If > 0, overrides half of round-turn value.
input bool   InpUseCommissionInLotSizing  = true; // Adds estimated round-turn commission to SL risk per lot.


input group "=== Macro / News Filter ==="
input bool   InpUseMacroNewsFilter             = true;
input bool   InpUseBacktestMacroWindows        = true;   // InpUseBacktestMacroWindows - Tester mode.
input bool   InpUseBuiltInBacktestMacroWindows = true;   // InpUseBuiltInBacktestMacroWindows - Uses built-in validated windows. Safer than long input strings in tester/set files.
input bool   InpUseMql5CalendarLiveNews        = false;  // Live/forward mode: use the MT5 economic calendar.
input bool   InpMacroBlockNewEntries           = true;
input bool   InpMacroBlockGridAdds             = true;
input int    InpMacroGridBlockMinNextLevel     = 2;      // 2 blocks L2/L3/L4 grid adds during macro windows.
input int    InpCalendarEntryBlockBeforeHours  = 24;
input int    InpCalendarEntryBlockAfterHours   = 6;
input int    InpCalendarGridBlockBeforeHours   = 72;
input int    InpCalendarGridBlockAfterHours    = 12;
input bool   InpUseLongCentralBankBlackout        = true;
input string InpLongCentralBankCurrencies         = "CAD,NZD,AUD";
input int    InpCentralBankEntryBlockBeforeDays   = 5;    // Business days before event
input int    InpCentralBankGridBlockBeforeDays    = 5;    // Business days before event
input int    InpCentralBankBlockAfterHours        = 12;
input int    InpCentralBankGridBlockMinNextLevel  = 2;    // Block L2/L3/L4 grid adds
input int    InpCalendarMinImportance          = 2;      // 2=medium+, 3=high only depending on broker calendar feed.
input string InpCalendarCurrenciesBySymbol     = "EURAUD=EUR,AUD,USD,CNY;NZDCAD=NZD,CAD,USD;AUDCAD=AUD,CAD,USD";
// Optional extra tester windows. Use || as separator, not semicolon, because .set/report handling can truncate strings at semicolons.
// Format: yyyy.mm.dd hh:mi>yyyy.mm.dd hh:mi|SYMBOL1,SYMBOL2|TAG||yyyy.mm.dd hh:mi>yyyy.mm.dd hh:mi|SYMBOL|TAG
input string InpBacktestMacroWindows           = "";

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
input int    InpGridGapPips             = 40;
input double InpGridGapMultiplier = 1.50;
input int    InpGridGapMaxPips = 120;
input int    InpGridMaxLevels           = 4;
input double InpGridLotMultiplier       = 1.05;
input double InpGridTakeProfitPctPrice  = 0.10;   
input bool   InpGridUseAnchorHardStop   = false;
input bool   InpGridUseBasketTrail      = true;
input double InpGridTrailArmPctTarget   = 60.0;
input double InpGridTrailRetracePctPeak = 35.0;
input int    InpBasketProfitCloseMinOrders = 3;
input double InpStaleCloseAgeStartHours = 8;
input double InpStaleCloseAgeFullDecayHours = 36;
input double InpStaleClosePctAtStart = 0.55;
input double InpStaleClosePctAtMaxAge = 0.2;
input double InpLargeBasketClosePctAtMinOrders = 0.55;
input double InpLargeBasketClosePctAtMaxLevels = 0.2;
input double InpRecoveryCloseMinMoney = 0.5;

// --- Basket escape / breakeven logic ---
input bool   InpUseBasketBreakevenClose      = true;
input int    InpBasketBE_MinOrders           = 2;
input double InpBasketBE_MinAgeHours         = 3.0;
input double InpBasketBE_MinMoney            = 1;

input int    InpDeepBasketBE_MinOrders       = 3;
input double InpDeepBasketBE_MinAgeHours     = 6.0;
input double InpDeepBasketBE_MinMoney        = 0.00;


input bool   InpScaleAgeExitLossByRisk      = true;
input double InpExitLossRiskReferencePct    = 0.10;
input bool   InpUseAbsoluteMaxLevelTimeExit = true;
input double InpAbsoluteMaxLevelExitHours   = 336.0;

// --- Max-level controlled loss ladder ---
input bool   InpUseMaxLevelControlledExit    = true;

// Ladder step 1: early escape
input double InpMaxLevelExitAge1Hours        = 12.0;
input double InpMaxLevelExitLoss1PctBal      = 0.25;

// Ladder step 2: normal controlled escape
input double InpMaxLevelExitAge2Hours        = 24.0;
input double InpMaxLevelExitLoss2PctBal      = 0.50;

// Ladder step 3: old basket escape
input double InpMaxLevelExitAge3Hours        = 48.0;
input double InpMaxLevelExitLoss3PctBal      = 0.90;

// Ladder step 4: very old basket escape
input double InpMaxLevelExitAge4Hours        = 72.0;
input double InpMaxLevelExitLoss4PctBal      = 1.25;


// --- L2 aged basket loss exit ---
// Handles old 2-order baskets that never reach L3/L4.
input bool   InpUseL2AgeExit              = true;
input double InpL2AgeExitAge1Hours        = 48.0;
input double InpL2AgeExitLoss1PctBal      = 0.00;   

input double InpL2AgeExitAge2Hours        = 96.0;
input double InpL2AgeExitLoss2PctBal      = 0.50;   

input double InpL2AgeExitAge3Hours        = 144.0;
input double InpL2AgeExitLoss3PctBal      = 0.75;

input double InpL2AgeExitAge4Hours        = 216.0;
input double InpL2AgeExitLoss4PctBal      = 1.25;

input double InpL2AgeExitAge5Hours        = 288;
input double InpL2AgeExitLoss5PctBal      = 1.75;

input bool   InpL2AgeExitStartsCooldown   = true;


// --- L3 aged basket loss exit ---
// Handles dangerous 3-order baskets before they reach max level.
input bool   InpUseL3AgeExit              = true;
input double InpL3AgeExitAge1Hours        = 24.0;
input double InpL3AgeExitLoss1PctBal      = 0.2;

input double InpL3AgeExitAge2Hours        = 48.0;
input double InpL3AgeExitLoss2PctBal      = 0.40;

input double InpL3AgeExitAge3Hours        = 72.0;
input double InpL3AgeExitLoss3PctBal      = 0.6;

input double InpL3AgeExitAge4Hours        = 96;
input double InpL3AgeExitLoss4PctBal      = 1;

input bool   InpL3AgeExitStartsCooldown   = true;

// Optional final hard exit to avoid endless baskets
input bool   InpUseMaxLevelHardTimeExit      = true;
input double InpMaxLevelHardExitAgeHours     = 120.0;
input double InpMaxLevelHardExitMaxLossPctBal = 2.00;

input bool   InpMaxLevelExitStartsCooldown   = true;

input int    InpMaxConcurrentBaskets    = 8;
input double InpMaxOtherBasketDDPctBal  = 15.00;

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

string PREFIX = "TMD_";
string g_panelObjs[];
ulong  g_lastVisualRefreshMs = 0;
datetime g_lastVisualBarTime = 0;
datetime g_cooldownUntil = 0;
string g_lastSLReason = "-";
double g_maxGlobalDdMoney = 0.0;
double g_maxGlobalDdPct   = 0.0;
double g_closedBasketAgeHoursSum = 0.0;
int    g_closedBasketAgeCount    = 0;
datetime g_panelNewsLastCheck[];
string   g_panelNewsLastText[];
color    g_panelNewsLastColor[];

struct SymbolState
{
   string symbol;      // Actual broker symbol used for trading, e.g. m.EURAUD.r
   string baseSymbol;  // Clean six-letter FX symbol used for rules/currency logic, e.g. EURAUD
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
datetime lastEntryEvalBarTime;
datetime lastGridEvalBarTime;
datetime lastBasketExitBarTime;
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
BasketState g_baskets[];
bool g_blockedEntryHours[24];

bool IsNewBarForSymbolTF(const string sym,
                         const ENUM_TIMEFRAMES tf,
                         datetime &lastBarTime)
{
   datetime currentBarTime = iTime(sym, tf, 0);

   if(currentBarTime <= 0)
      return false;

   // First call: allow evaluation immediately.
   if(lastBarTime == 0)
   {
      lastBarTime = currentBarTime;
      return true;
   }

   if(currentBarTime != lastBarTime)
   {
      lastBarTime = currentBarTime;
      return true;
   }

   return false;
}

void LogMsg(const ENUM_TMD_LOG_LEVEL level, const string msg)
{
   if((int)InpLogLevel >= (int)level)
      Print("[TMD] ", msg);
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
double ExitLossRiskScale()
{
   if(!InpScaleAgeExitLossByRisk)
      return 1.0;

   if(InpExitLossRiskReferencePct <= 0.0)
      return 1.0;

   double riskPct = GetRiskPercent();

   if(riskPct <= 0.0)
      return 1.0;

   return riskPct / InpExitLossRiskReferencePct;
}


double AcceptedExitLossMoney(const double lossPctBal)
{
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);

   if(bal <= 0.0)
      return 0.0;

   double scale = ExitLossRiskScale();

   return -bal * lossPctBal / 100.0 * scale;
}
bool IsKnownCurrencyCode(const string ccyRaw)
{
   string ccy = ccyRaw;
   StringToUpper(ccy);

   return (ccy == "USD" || ccy == "EUR" || ccy == "GBP" || ccy == "JPY" ||
           ccy == "CHF" || ccy == "CAD" || ccy == "AUD" || ccy == "NZD" ||
           ccy == "CNH" || ccy == "CNY" || ccy == "HKD" || ccy == "SGD" ||
           ccy == "NOK" || ccy == "SEK" || ccy == "DKK" || ccy == "ZAR" ||
           ccy == "MXN" || ccy == "TRY" || ccy == "PLN" || ccy == "CZK" ||
           ccy == "HUF");
}

bool IsKnownNonForexCoreSymbol(const string symbolRaw)
{
   string s = symbolRaw;
   StringToUpper(s);

   // Metals / CFDs that should behave as clean cores for broker prefix/suffix detection.
   return (s == "XAUUSD" || s == "XAGUSD" || s == "XAUEUR" || s == "XAGEUR" ||
           s == "USOIL" || s == "UKOIL" || s == "WTI" || s == "BRENT");
}

bool IsKnownForexCoreSymbol(const string symbolRaw)
{
   string s = symbolRaw;
   StringToUpper(s);

   if(StringLen(s) != 6)
      return false;

   string base  = StringSubstr(s, 0, 3);
   string quote = StringSubstr(s, 3, 3);

   return (IsKnownCurrencyCode(base) && IsKnownCurrencyCode(quote) && base != quote);
}

string StripConfiguredBrokerAffixes(const string symbolRaw)
{
   string s = Trim(symbolRaw);

   if(InpBrokerSymbolPrefix != "" && StringFind(s, InpBrokerSymbolPrefix) == 0)
      s = StringSubstr(s, StringLen(InpBrokerSymbolPrefix));

   if(InpBrokerSymbolSuffix != "")
   {
      int suffixLen = StringLen(InpBrokerSymbolSuffix);
      int sLen      = StringLen(s);
      if(sLen >= suffixLen && StringSubstr(s, sLen - suffixLen, suffixLen) == InpBrokerSymbolSuffix)
         s = StringSubstr(s, 0, sLen - suffixLen);
   }

   return s;
}

string ExtractCoreSymbol(const string symbolRaw)
{
   string s = StripConfiguredBrokerAffixes(symbolRaw);
   StringToUpper(s);

   if(IsKnownForexCoreSymbol(s) || IsKnownNonForexCoreSymbol(s))
      return s;

   int len = StringLen(s);

   // First scan 6-character cores such as EURAUD and XAUUSD inside broker variants.
   for(int i = 0; i <= len - 6; i++)
   {
      string candidate = StringSubstr(s, i, 6);
      if(IsKnownForexCoreSymbol(candidate) || IsKnownNonForexCoreSymbol(candidate))
         return candidate;
   }

   // Then scan 5-character oil cores such as USOIL / UKOIL, useful for future filters.
   for(int i = 0; i <= len - 5; i++)
   {
      string candidate = StringSubstr(s, i, 5);
      if(IsKnownNonForexCoreSymbol(candidate))
         return candidate;
   }

   return s;
}

string ResolveBrokerSymbol(const string requestedRaw)
{
   string requested = Trim(requestedRaw);
   if(requested == "")
      return "";

   if(SymbolSelect(requested, true))
      return requested;

   string forced = InpBrokerSymbolPrefix + requested + InpBrokerSymbolSuffix;
   if(forced != requested && SymbolSelect(forced, true))
      return forced;

   string requestedCore = ExtractCoreSymbol(requested);

   if(InpAutoDetectBrokerSymbols)
   {
      int total = SymbolsTotal(false);
      for(int i = 0; i < total; i++)
      {
         string candidate = SymbolName(i, false);
         if(candidate == "")
            continue;

         if(ExtractCoreSymbol(candidate) == requestedCore)
         {
            if(SymbolSelect(candidate, true))
               return candidate;
         }
      }
   }

   return requested;
}

string SymbolBaseName(const string sym)
{
   int idx = -1;
   for(int i = 0; i < ArraySize(g_states); i++)
   {
      if(g_states[i].symbol == sym || g_states[i].baseSymbol == sym)
      {
         idx = i;
         break;
      }
   }

   if(idx >= 0 && g_states[idx].baseSymbol != "")
      return g_states[idx].baseSymbol;

   return ExtractCoreSymbol(sym);
}

int GetStateIndexBySymbol(const string sym)
{
   string core = ExtractCoreSymbol(sym);

   for(int i = 0; i < ArraySize(g_states); i++)
   {
      if(g_states[i].symbol == sym)
         return i;

      if(core != "" && g_states[i].baseSymbol == core)
         return i;
   }

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
      string requestedSym = Trim(parts[i]);
      if(requestedSym == "")
         continue;

      string sym = ResolveBrokerSymbol(requestedSym);
      if(sym == "")
         continue;

      if(!SymbolSelect(sym, true))
      {
         LogMsg(LOG_ERROR, "failed SymbolSelect for requested=" + requestedSym + " resolved=" + sym);
         continue;
      }

      string baseSym = ExtractCoreSymbol(sym);
      if(baseSym == "")
         baseSym = ExtractCoreSymbol(requestedSym);

      int idx = ArraySize(g_states);
      ArrayResize(g_states, idx + 1);
      g_states[idx].symbol        = sym;
      g_states[idx].baseSymbol    = baseSym;
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
      g_states[idx].lastEntryEvalBarTime  = 0;
      g_states[idx].lastGridEvalBarTime   = 0;
      g_states[idx].lastBasketExitBarTime = 0;

      if(InpLogLevel >= LOG_INFO)
      {
         LogMsg(LOG_INFO,
                StringFormat("SYMBOL_MAP | requested=%s | resolved=%s | base=%s | digits=%d | point=%.10f | pip=%.10f",
                             requestedSym,
                             sym,
                             baseSym,
                             g_states[idx].digits,
                             g_states[idx].point,
                             g_states[idx].pip));
      }
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

void PrepareTradeForSymbol(const string sym)
{
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpDeviationPoints);

   if(sym != "")
      trade.SetTypeFillingBySymbol(sym);
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

   // Block full July
   if(InpBlockJuly && tm.mon == 7)
      return false;

   // Block year-end holiday period
   if(InpBlockYearEndHoliday)
   {
      bool inStart = (tm.mon == InpHolidayStartMonth && tm.day >= InpHolidayStartDay);
      bool inEnd   = (tm.mon == InpHolidayEndMonth   && tm.day <= InpHolidayEndDay);
      if(inStart || inEnd)
         return false;
   }

   int h = tm.hour;

   // Friday early stop
   // tm.day_of_week: 0=Sunday, 1=Monday, ..., 5=Friday, 6=Saturday
   if(InpUseFridayStopHour && tm.day_of_week == 5)
   {
      if(h >= InpFridayStopHour)
         return false;
   }

   // Normal trading hours
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

double CommissionPerLotPerSide()
{
   if(InpCommissionMode == COMMISSION_OFF)
      return 0.0;

   if(InpCommissionPerLotPerSide > 0.0)
      return InpCommissionPerLotPerSide;

   if(InpCommissionPerLotRoundTurn > 0.0)
      return InpCommissionPerLotRoundTurn / 2.0;

   return 0.0;
}

double EstimatedCommissionCost(const double lots, const bool roundTurn)
{
   if(lots <= 0.0 || InpCommissionMode == COMMISSION_OFF)
      return 0.0;

   double perSide = CommissionPerLotPerSide();
   if(perSide <= 0.0)
      return 0.0;

   return MathAbs(lots) * perSide * (roundTurn ? 2.0 : 1.0);
}

double HistoricalPositionCommission(const ulong positionId, const string sym, const datetime positionTime)
{
   if(positionId == 0)
      return 0.0;

   datetime fromTime = positionTime - 86400;
   if(fromTime < 0)
      fromTime = 0;

   datetime toTime = TimeTradeServer() + 3600;
   if(toTime <= 0)
      toTime = TimeCurrent() + 3600;

   if(!HistorySelect(fromTime, toTime))
      return 0.0;

   double commission = 0.0;
   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0)
         continue;

      if((ulong)HistoryDealGetInteger(deal, DEAL_POSITION_ID) != positionId)
         continue;

      if(HistoryDealGetString(deal, DEAL_SYMBOL) != sym)
         continue;

      if((ulong)HistoryDealGetInteger(deal, DEAL_MAGIC) != InpMagic)
         continue;

      commission += HistoryDealGetDouble(deal, DEAL_COMMISSION);
   }

   return commission;
}

double PositionCommissionAdjustment(const bool includeEstimatedCloseSide)
{
   if(InpCommissionMode == COMMISSION_OFF)
      return 0.0;

   string sym       = PositionGetString(POSITION_SYMBOL);
   double lots      = PositionGetDouble(POSITION_VOLUME);
   datetime posTime = (datetime)PositionGetInteger(POSITION_TIME);

   double adjustment = 0.0;

   if(InpCommissionMode == COMMISSION_HISTORY_PLUS_ESTIMATED_CLOSE)
   {
      ulong posId = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
      adjustment += HistoricalPositionCommission(posId, sym, posTime); // Usually negative on real brokers/testers.

      if(includeEstimatedCloseSide)
         adjustment -= EstimatedCommissionCost(lots, false);

      return adjustment;
   }

   if(InpCommissionMode == COMMISSION_ESTIMATED_ROUND_TURN)
      return -EstimatedCommissionCost(lots, true);

   return 0.0;
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
           + PositionGetDouble(POSITION_SWAP)
           + PositionCommissionAdjustment(true);
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
   string core = SymbolBaseName(sym);
   if(StringLen(core) < 6)
      return sym;

   return StringSubstr(core, 0, 1) + StringSubstr(core, 3, 1);
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

int VolumeDigitsForStep(const double stepRaw)
{
   double step = MathAbs(stepRaw);
   if(step <= 0.0)
      return 2;

   for(int d = 0; d <= 8; d++)
   {
      if(MathAbs(step - NormalizeDouble(step, d)) < 0.000000001)
         return d;
   }

   return 8;
}

double NormalizeLots(const string sym, double lots)
{
   double minLot  = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
   double stepLot = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);

   if(minLot <= 0.0)
      minLot = 0.01;
   if(stepLot <= 0.0)
      stepLot = minLot;
   if(maxLot <= 0.0)
      maxLot = lots;

   if(lots < minLot)
      lots = minLot;
   if(lots > maxLot)
      lots = maxLot;

   lots = MathFloor((lots / stepLot) + 0.0000001) * stepLot;

   if(lots < minLot)
      lots = minLot;
   if(lots > maxLot)
      lots = maxLot;

   return NormalizeDouble(lots, VolumeDigitsForStep(stepLot));
}

string BaseCurrency(const string sym)
{
   string core = SymbolBaseName(sym);
   if(StringLen(core) < 6)
      return "";
   return StringSubstr(core, 0, 3);
}

string QuoteCurrency(const string sym)
{
   string core = SymbolBaseName(sym);
   if(StringLen(core) < 6)
      return "";
   return StringSubstr(core, 3, 3);
}

double RiskMultiplierForSymbol(const string sym)
{
   return 1.0;
}

int MaxSpreadPipsForSymbol(const string sym)
{
   return InpMaxSpreadPips;
}

double MinRangeAtrPctForSymbol(const string sym)
{
   return InpMinRangeAtrPct;
}

int MinStopDistancePipsForSymbol(const string sym)
{
   return InpMinStopDistancePips;
}

int GridMaxLevelsForSymbol(const string sym)
{
   return InpGridMaxLevels;
}

int GridGapPipsForSymbol(const string sym)
{
   return InpGridGapPips;
}

double GridGapMultiplierForSymbol(const string sym)
{
   return InpGridGapMultiplier;
}

int GridGapMaxPipsForSymbol(const string sym)
{
   return InpGridGapMaxPips;
}

double GridLotMultiplierForSymbol(const string sym)
{
   return InpGridLotMultiplier;
}

double GridTakeProfitPctForSymbol(const string sym)
{
   return InpGridTakeProfitPctPrice;
}

double LotSizingStopDistanceForSymbol(const string sym, const double rawStopDistance)
{
   return rawStopDistance;
}

double ApplyInitialLotBoundsForSymbol(const string sym, double lots)
{
   return NormalizeLots(sym, lots);
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

      pnl += PositionGetDouble(POSITION_PROFIT)
           + PositionGetDouble(POSITION_SWAP)
           + PositionCommissionAdjustment(true);
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

   bool recoveryEligible = IsRecoveryEligibleNewBasket(sym, dir, InpStaleCloseAgeStartHours);

   for(int i = 0; i < ArraySize(g_baskets); i++)
   {
      if(!g_baskets[i].active)
         continue;
      if(g_baskets[i].symbol == sym)
         continue;

      double signedCorr = CalcReturnCorrelation(sym, g_baskets[i].symbol, InpCorrelationBars);
      double absCorr    = MathAbs(signedCorr);

      if(recoveryEligible &&
         BasketAgeHours(i) >= InpStaleCloseAgeStartHours &&
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

   bool recoveryEligible = IsRecoveryEligibleNewBasket(sym, dir, InpStaleCloseAgeStartHours );

   for(int i = 0; i < ArraySize(g_baskets); i++)
   {
      if(!g_baskets[i].active)
         continue;

      string otherSym = g_baskets[i].symbol;
      int otherDir    = g_baskets[i].direction;

      if(otherSym == sym)
         continue;

      if(recoveryEligible &&
         BasketAgeHours(i) >= InpStaleCloseAgeStartHours  &&
         IsRecoveryCompatiblePair(sym, dir, otherSym, otherDir))
         continue;

      if(SymbolsConflictDirectional(sym, dir, otherSym, otherDir))
         return true;
   }

   return false;
}

bool CanOpenNewBasket(const string sym,const int direction)
{
   bool recoveryEligible = IsRecoveryEligibleNewBasket(sym, direction, InpStaleCloseAgeStartHours  );

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
                             BasketNetProfit());
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
      return ApplyInitialLotBoundsForSymbol(sym, InpFallbackLot);

   double riskPct = GetRiskPercent();
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney = balance * (riskPct / 100.0) * RiskMultiplierForSymbol(sym);
   double tickSize  = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);

   double rawStopDistance = MathAbs(entryPrice - stopPrice);
   double stopDistance    = LotSizingStopDistanceForSymbol(sym, rawStopDistance);

   if(stopDistance <= 0.0 || tickSize <= 0.0 || tickValue <= 0.0)
      return ApplyInitialLotBoundsForSymbol(sym, InpFallbackLot);

   double costPerLot = (stopDistance / tickSize) * tickValue;

   if(InpUseCommissionInLotSizing && InpCommissionMode != COMMISSION_OFF)
      costPerLot += EstimatedCommissionCost(1.0, true);

   if(costPerLot <= 0.0)
      return ApplyInitialLotBoundsForSymbol(sym, InpFallbackLot);

   double rawLots = riskMoney / costPerLot;

   return ApplyInitialLotBoundsForSymbol(sym, rawLots);
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

   return ApplyInitialLotBoundsForSymbol(g_states[idx].symbol, InpLots);
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
   ctx.atrOk      = (g_states[idx].rangeAtrPct >= MinRangeAtrPctForSymbol(sym));
   ctx.sellM15Ok  = (ctx.m15Open > 0.0 && g_states[idx].hoH1 > 0.0 && ctx.m15Open > g_states[idx].hoH1);
   ctx.buyM15Ok   = (ctx.m15Open > 0.0 && g_states[idx].loH1 > 0.0 && ctx.m15Open < g_states[idx].loH1);
   ctx.yesterdayHighBroken = (g_states[idx].yesterdayHigh > 0.0 && ctx.bid > g_states[idx].yesterdayHigh + InpSignalTolerancePips * g_states[idx].pip);
   ctx.yesterdayLowBroken  = (g_states[idx].yesterdayLow  > 0.0 && ctx.ask < g_states[idx].yesterdayLow  - InpSignalTolerancePips * g_states[idx].pip);
   ctx.dailyExtremeSellBroken = (g_states[idx].dailyHigh > 0.0 && iHigh(sym, PERIOD_H1, 0) >= g_states[idx].dailyHigh + InpSignalTolerancePips * g_states[idx].pip);
   ctx.dailyExtremeBuyBroken  = (g_states[idx].dailyLow  > 0.0 && iLow(sym, PERIOD_H1, 0) <= g_states[idx].dailyLow  - InpSignalTolerancePips * g_states[idx].pip);

   double sellStopDistPips = (g_states[idx].dailyHigh - (g_states[idx].hoH1 + InpEntryBufferPoints * g_states[idx].point)) / g_states[idx].pip;
   double buyStopDistPips  = ((g_states[idx].loH1 - InpEntryBufferPoints * g_states[idx].point) - g_states[idx].dailyLow) / g_states[idx].pip;
   ctx.sellStopDistanceOk = (sellStopDistPips >= MinStopDistancePipsForSymbol(sym));
   ctx.buyStopDistanceOk  = (buyStopDistPips  >= MinStopDistancePipsForSymbol(sym));

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
double PipSizeForSymbol(const string sym)
{
   int idx = GetStateIndexBySymbol(sym);
   if(idx >= 0)
      return g_states[idx].pip;

   double point = SymbolInfoDouble(sym, SYMBOL_POINT);
   int digits   = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);

   if(digits == 5 || digits == 3)
      return point * 10.0;

   return point;
}


int PendingOrderAgeSeconds(const ulong ticket)
{
   if(ticket == 0 || !OrderSelect(ticket))
      return 999999;

   datetime setupTime = (datetime)OrderGetInteger(ORDER_TIME_SETUP);
   if(setupTime <= 0)
      return 999999;

   datetime now = TimeCurrent();
   return (int)(now - setupTime);
}


bool PendingTooYoungToCancel(const ulong ticket)
{
   if(InpPendingMinLifeSeconds <= 0)
      return false;

   int ageSec = PendingOrderAgeSeconds(ticket);
   return (ageSec >= 0 && ageSec < InpPendingMinLifeSeconds);
}
void CancelPendingByType(const string sym, ENUM_ORDER_TYPE type, bool forceCancel = false)
{
   ulong ticket = FindPendingOrder(sym, type);
   if(ticket <= 0)
      return;

   if(!forceCancel && PendingTooYoungToCancel(ticket))
   {
      if(InpLogLevel >= LOG_DEBUG)
      {
         LogMsg(LOG_DEBUG,
                StringFormat("keep fresh pending %s type=%d ticket=%I64u age=%d sec",
                             sym,
                             (int)type,
                             ticket,
                             PendingOrderAgeSeconds(ticket)));
      }

      return;
   }

   if(!trade.OrderDelete(ticket))
   {
      LogMsg(LOG_ERROR,
             StringFormat("failed deleting pending %s ticket=%I64u ret=%d",
                          sym,
                          ticket,
                          trade.ResultRetcode()));
   }
}

void CancelPendingsForSymbol(const string sym, bool forceCancel = false)
{
   CancelPendingByType(sym, ORDER_TYPE_BUY_STOP, forceCancel);
   CancelPendingByType(sym, ORDER_TYPE_SELL_STOP, forceCancel);
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

      double pip = PipSizeForSymbol(sym);
      double minRecalcDist = InpPendingRecalcMinPips * pip;
      
      bool entryChanged = (MathAbs(oldEntry - entry) >= minRecalcDist);
      bool slChanged    = (MathAbs(oldSl - sl) >= minRecalcDist);
      bool lotsChanged  = (MathAbs(oldLots - lots) > (volStep * 0.5));
      
      // If the pending is still fresh, do not modify/recreate it immediately.
      // This prevents cancel/modify churn in the first 120 seconds.
      if(PendingTooYoungToCancel(existing))
         return true;
      
      // If price/SL changed by less than the recalculation threshold, keep the order.
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

         PrepareTradeForSymbol(sym);

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

   PrepareTradeForSymbol(sym);

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

   double tpPct = GridTakeProfitPctForSymbol(g_baskets[basketIdx].symbol);
   if(tpPct <= 0.0)
      return 0.0;

   double avgEntry = BasketAverageEntryPrice(g_baskets[basketIdx].symbol);
   if(avgEntry <= 0.0)
      return 0.0;

   double pct = tpPct / 100.0;

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

   double tpPct = GridTakeProfitPctForSymbol(g_baskets[basketIdx].symbol);
   if(tpPct <= 0.0)
      return 0.0;

   double avgEntry = BasketAverageEntryPrice(g_baskets[basketIdx].symbol);
   if(avgEntry <= 0.0)
      return 0.0;

   double targetDistance = avgEntry * (tpPct / 100.0);
   return targetDistance * InpGridTrailArmPctTarget / 100.0;
}

double Clamp01(const double v)
{
   if(v < 0.0) return 0.0;
   if(v > 1.0) return 1.0;
   return v;
}

double Lerp(const double a, const double b, const double t)
{
   return a + (b - a) * Clamp01(t);
}

double BasketProfitAtPrice(const string sym, const double closePrice)
{
   if(sym == "" || closePrice <= 0.0)
      return 0.0;

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

      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      ENUM_ORDER_TYPE orderType = (posType == POSITION_TYPE_BUY ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
      double lots = PositionGetDouble(POSITION_VOLUME);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double calcPnl = 0.0;

      if(OrderCalcProfit(orderType, sym, lots, openPrice, closePrice, calcPnl))
         pnl += calcPnl;

      pnl += PositionGetDouble(POSITION_SWAP)
           + PositionCommissionAdjustment(true);
   }

   return pnl;
}

double BasketTargetProfitMoney(const int basketIdx)
{
   if(basketIdx < 0 || basketIdx >= ArraySize(g_baskets))
      return 0.0;
   if(!g_baskets[basketIdx].active || g_baskets[basketIdx].symbol == "")
      return 0.0;

   double targetPrice = GridTargetPrice(basketIdx);
   if(targetPrice <= 0.0)
      return 0.0;

   return MathMax(0.0, BasketProfitAtPrice(g_baskets[basketIdx].symbol, targetPrice));
}

double StaleAgeRecoveryPct(const double ageHours)
{
   if(ageHours <= InpStaleCloseAgeStartHours)
      return InpStaleClosePctAtStart;

   double endH = MathMax(InpStaleCloseAgeStartHours + 1.0, InpStaleCloseAgeFullDecayHours);
   double t = (ageHours - InpStaleCloseAgeStartHours) / (endH - InpStaleCloseAgeStartHours);
   return Lerp(InpStaleClosePctAtStart, InpStaleClosePctAtMaxAge, t);
}

double BasketSizeRecoveryPct(const int basketOrders, const string sym = "")
{
   if(InpBasketProfitCloseMinOrders <= 0)
      return InpLargeBasketClosePctAtMinOrders;

   int maxOrders = MathMax(InpBasketProfitCloseMinOrders + 1, (sym == "" ? InpGridMaxLevels : GridMaxLevelsForSymbol(sym)));
   if(basketOrders <= InpBasketProfitCloseMinOrders)
      return InpLargeBasketClosePctAtMinOrders;

   double t = (double)(basketOrders - InpBasketProfitCloseMinOrders)
            / (double)MathMax(1, maxOrders - InpBasketProfitCloseMinOrders);
   return Lerp(InpLargeBasketClosePctAtMinOrders, InpLargeBasketClosePctAtMaxLevels, t);
}

double BasketRecoveryClosePnl(const int basketIdx, const bool staleMode)
{
   if(basketIdx < 0 || basketIdx >= ArraySize(g_baskets))
      return InpRecoveryCloseMinMoney;
   if(!g_baskets[basketIdx].active || g_baskets[basketIdx].symbol == "")
      return InpRecoveryCloseMinMoney;

   double targetMoney = BasketTargetProfitMoney(basketIdx);
   if(targetMoney <= 0.0)
      return InpRecoveryCloseMinMoney;

   double sizePct = BasketSizeRecoveryPct(BasketPositionCount(g_baskets[basketIdx].symbol), g_baskets[basketIdx].symbol);
   double pct = sizePct;

   if(staleMode)
   {
      double agePct = StaleAgeRecoveryPct(BasketAgeHours(basketIdx));
      pct = 0.5 * (agePct + sizePct);
   }

   return MathMax(InpRecoveryCloseMinMoney, targetMoney * MathMax(0.0, pct));
}

double GlobalRecoveryClosePnl()
{
   double sumReq = 0.0;
   int staleCount = 0;

   for(int i = 0; i < ArraySize(g_baskets); i++)
   {
      if(!g_baskets[i].active)
         continue;
      if(BasketAgeHours(i) < InpStaleCloseAgeStartHours)
         continue;

      sumReq += BasketRecoveryClosePnl(i, true);
      staleCount++;
   }

   if(staleCount <= 0)
      return 0.0;

   double avgReq = sumReq / (double)staleCount;
   return MathMax(InpRecoveryCloseMinMoney, 0.5 * (sumReq + avgReq));
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

   return NormalizeLots(g_baskets[basketIdx].symbol, baseLots * MathPow(GridLotMultiplierForSymbol(g_baskets[basketIdx].symbol), exponent));
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

      PrepareTradeForSymbol(sym);
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
      PrepareTradeForSymbol(sym);
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
   if(g_baskets[basketIdx].levels >= GridMaxLevelsForSymbol(g_baskets[basketIdx].symbol))
      return false;

   double bid = 0.0, ask = 0.0;
   string sym = g_baskets[basketIdx].symbol;
   if(!GetTickPrices(sym, bid, ask))
      return false;

   double lots = NextGridLots(basketIdx);
   if(lots <= 0.0)
      return false;

   PrepareTradeForSymbol(sym);

   bool ok = false;
   if(g_baskets[basketIdx].direction == POSITION_TYPE_BUY)
      ok = trade.Buy(lots, sym, ask, 0.0, 0.0, StringFormat("TMD Grid L%d", g_baskets[basketIdx].levels + 1));
   else if(g_baskets[basketIdx].direction == POSITION_TYPE_SELL)
      ok = trade.Sell(lots, sym, bid, 0.0, 0.0, StringFormat("TMD Grid L%d", g_baskets[basketIdx].levels + 1));

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
double MaxLevelAllowedLossPctByAge(const double basketAgeHours)
{
   double lossPct = -1.0;

   if(basketAgeHours >= InpMaxLevelExitAge1Hours)
      lossPct = InpMaxLevelExitLoss1PctBal;

   if(basketAgeHours >= InpMaxLevelExitAge2Hours)
      lossPct = InpMaxLevelExitLoss2PctBal;

   if(basketAgeHours >= InpMaxLevelExitAge3Hours)
      lossPct = InpMaxLevelExitLoss3PctBal;

   if(basketAgeHours >= InpMaxLevelExitAge4Hours)
      lossPct = InpMaxLevelExitLoss4PctBal;

   return lossPct;
}
double AllowedLossPct_L2_ByAge(const double basketAgeHours)
{
   double lossPct = -1.0;

   if(basketAgeHours >= InpL2AgeExitAge1Hours)
      lossPct = InpL2AgeExitLoss1PctBal;

   if(basketAgeHours >= InpL2AgeExitAge2Hours)
      lossPct = InpL2AgeExitLoss2PctBal;

   if(basketAgeHours >= InpL2AgeExitAge3Hours)
      lossPct = InpL2AgeExitLoss3PctBal;

   if(basketAgeHours >= InpL2AgeExitAge4Hours)
      lossPct = InpL2AgeExitLoss4PctBal;

   if(basketAgeHours >= InpL2AgeExitAge5Hours)
      lossPct = InpL2AgeExitLoss5PctBal;

   return lossPct;
}


double AllowedLossPct_L3_ByAge(const double basketAgeHours)
{
   double lossPct = -1.0;

   if(basketAgeHours >= InpL3AgeExitAge1Hours)
      lossPct = InpL3AgeExitLoss1PctBal;

   if(basketAgeHours >= InpL3AgeExitAge2Hours)
      lossPct = InpL3AgeExitLoss2PctBal;

   if(basketAgeHours >= InpL3AgeExitAge3Hours)
      lossPct = InpL3AgeExitLoss3PctBal;

   if(basketAgeHours >= InpL3AgeExitAge4Hours)
      lossPct = InpL3AgeExitLoss4PctBal;

   return lossPct;
}
bool ManageL2L3AgeExit(const int basketIdx)
{
   if(basketIdx < 0 || basketIdx >= ArraySize(g_baskets))
      return false;

   if(!g_baskets[basketIdx].active || g_baskets[basketIdx].symbol == "")
      return false;

   string sym = g_baskets[basketIdx].symbol;

   if(!HasOpenPosition(sym))
      return false;

   double pnl            = BasketNetProfit(sym);       // includes swap
   int    basketOrders   = BasketPositionCount(sym);
   int    basketLevels   = g_baskets[basketIdx].levels;
   double basketAgeHours = BasketAgeHours(basketIdx);
   double bal            = AccountInfoDouble(ACCOUNT_BALANCE);

   // ------------------------------------------------------------
   // L3 aged exit
   // Only for 3-order baskets that have NOT reached max level yet.
   // If max level is reached, let your max-level ladder handle it.
   // ------------------------------------------------------------
   if(InpUseL3AgeExit)
   {
      bool isL3Basket =
         (basketOrders >= 3 || basketLevels >= 3) &&
         (basketOrders < GridMaxLevelsForSymbol(sym) && basketLevels < GridMaxLevelsForSymbol(sym));

      if(isL3Basket)
      {
         double allowedLossPct = AllowedLossPct_L3_ByAge(basketAgeHours);

         if(allowedLossPct >= 0.0)
         {
            double acceptedLossMoney = AcceptedExitLossMoney(allowedLossPct);

            if(pnl >= acceptedLossMoney)
            {
               LogMsg(LOG_INFO,
                      StringFormat("L3_AGE_EXIT | %s | pnl=%.2f | acceptedLoss=%.2f | lossPct=%.2f%% | ageH=%.1f | orders=%d | levels=%d",
                                   sym,
                                   pnl,
                                   acceptedLossMoney,
                                   allowedLossPct,
                                   basketAgeHours,
                                   basketOrders,
                                   basketLevels));

               CloseBasket(sym,
                           "L3 aged basket exit",
                           InpL3AgeExitStartsCooldown);

               return true;
            }
         }
      }
   }

   // ------------------------------------------------------------
   // L2 aged exit
   // Only for 2-order baskets.
   // This fixes old L2 baskets like EURCHF/EURGBP in your last test.
   // ------------------------------------------------------------
   if(InpUseL2AgeExit)
   {
      bool isL2Basket =
         (basketOrders == 2 || basketLevels == 2) &&
         basketOrders < 3 &&
         basketLevels < 3;

      if(isL2Basket)
      {
         double allowedLossPct = AllowedLossPct_L2_ByAge(basketAgeHours);

         if(allowedLossPct >= 0.0)
         {
            double acceptedLossMoney = AcceptedExitLossMoney(allowedLossPct);

            if(pnl >= acceptedLossMoney)
            {
               LogMsg(LOG_INFO,
                      StringFormat("L2_AGE_EXIT | %s | pnl=%.2f | acceptedLoss=%.2f | lossPct=%.2f%% | ageH=%.1f | orders=%d | levels=%d",
                                   sym,
                                   pnl,
                                   acceptedLossMoney,
                                   allowedLossPct,
                                   basketAgeHours,
                                   basketOrders,
                                   basketLevels));

               CloseBasket(sym,
                           "L2 aged basket exit",
                           InpL2AgeExitStartsCooldown);

               return true;
            }
         }
      }
   }

   return false;
}
bool ManageBasketEscapeClose(const int basketIdx)
{
   if(basketIdx < 0 || basketIdx >= ArraySize(g_baskets))
      return false;

   if(!g_baskets[basketIdx].active || g_baskets[basketIdx].symbol == "")
      return false;

   string sym = g_baskets[basketIdx].symbol;

   if(!HasOpenPosition(sym))
      return false;

   if(InpBasketExitOnlyOnNewBar)
   {
      int sidx = GetStateIndexBySymbol(sym);
   
      if(sidx >= 0)
      {
         if(!IsNewBarForSymbolTF(sym,
                                 InpBasketExitTF,
                                 g_states[sidx].lastBasketExitBarTime))
         {
            return false;
         }
      }
   }
   double pnl             = BasketNetProfit(sym);       // includes swap
   int    basketOrders    = BasketPositionCount(sym);
   double basketAgeHours  = BasketAgeHours(basketIdx);
   int    basketLevels    = g_baskets[basketIdx].levels;
   
    // L2/L3 aged exits.
   // This handles old baskets that do not reach max level.
   if(ManageL2L3AgeExit(basketIdx))
      return true;

   // ------------------------------------------------------------
   // 1) Normal basket breakeven / small-profit close
   // Example: L2+ baskets should not wait for full grid TP forever.
   // ------------------------------------------------------------
   if(InpUseBasketBreakevenClose)
   {
      if(basketOrders >= InpBasketBE_MinOrders &&
         basketAgeHours >= InpBasketBE_MinAgeHours &&
         pnl >= InpBasketBE_MinMoney)
      {
         LogMsg(LOG_INFO,
                StringFormat("BASKET_BE_CLOSE | %s | pnl=%.2f | ageH=%.1f | orders=%d | levels=%d | req=%.2f",
                             sym, pnl, basketAgeHours, basketOrders, basketLevels, InpBasketBE_MinMoney));

         CloseBasket(sym, "basket breakeven/small profit close", false);
         return true;
      }

      // Deeper basket: escape at true BE or tiny profit.
      if(basketOrders >= InpDeepBasketBE_MinOrders &&
         basketAgeHours >= InpDeepBasketBE_MinAgeHours &&
         pnl >= InpDeepBasketBE_MinMoney)
      {
         LogMsg(LOG_INFO,
                StringFormat("DEEP_BASKET_BE_CLOSE | %s | pnl=%.2f | ageH=%.1f | orders=%d | levels=%d | req=%.2f",
                             sym, pnl, basketAgeHours, basketOrders, basketLevels, InpDeepBasketBE_MinMoney));

         CloseBasket(sym, "deep basket breakeven escape", false);
         return true;
      }
   }

   // ------------------------------------------------------------
   // 2) Max-level controlled loss LADDER
   // Once max grid level is reached, the EA should stop trying
   // to win big and start trying to escape efficiently.
   // The older the basket becomes, the more loss we are willing
   // to accept to prevent a catastrophic end-of-test close.
   // ------------------------------------------------------------
   if(InpUseMaxLevelControlledExit)
   {
      bool atMaxLevel = (basketLevels >= GridMaxLevelsForSymbol(sym) || basketOrders >= GridMaxLevelsForSymbol(sym));
   
      if(atMaxLevel)
      {
         double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   
         // Get allowed loss % based on basket age.
         double allowedLossPct = MaxLevelAllowedLossPctByAge(basketAgeHours);
   
         if(allowedLossPct > 0.0)
         {
            double acceptedLossMoney = AcceptedExitLossMoney(allowedLossPct);
   
            if(pnl >= acceptedLossMoney)
            {
               LogMsg(LOG_INFO,
                      StringFormat("MAX_LEVEL_LOSS_LADDER_EXIT | %s | pnl=%.2f | acceptedLoss=%.2f | allowedLossPct=%.2f%% | ageH=%.1f | orders=%d | levels=%d",
                                   sym,
                                   pnl,
                                   acceptedLossMoney,
                                   allowedLossPct,
                                   basketAgeHours,
                                   basketOrders,
                                   basketLevels));
   
               CloseBasket(sym,
                           "max-level loss ladder exit",
                           InpMaxLevelExitStartsCooldown);
   
               return true;
            }
         }
   
         // Optional final hard time exit.
         // This prevents a basket from surviving for weeks.
         // It only closes if the basket has recovered to within
         // the maximum hard-exit loss limit.
         if(InpUseMaxLevelHardTimeExit && basketAgeHours >= InpMaxLevelHardExitAgeHours)
         {
            double hardExitLossMoney = AcceptedExitLossMoney(InpMaxLevelHardExitMaxLossPctBal);
   
            if(pnl >= hardExitLossMoney)
            {
               LogMsg(LOG_INFO,
                      StringFormat("MAX_LEVEL_HARD_TIME_EXIT | %s | pnl=%.2f | maxAllowedLoss=%.2f | ageH=%.1f | orders=%d | levels=%d",
                                   sym,
                                   pnl,
                                   hardExitLossMoney,
                                   basketAgeHours,
                                   basketOrders,
                                   basketLevels));
   
               CloseBasket(sym,
                           "max-level hard time exit",
                           InpMaxLevelExitStartsCooldown);
   
               return true;
            }
         }
      }
   }
   if(InpUseAbsoluteMaxLevelTimeExit && basketAgeHours >= InpAbsoluteMaxLevelExitHours)
   {
      LogMsg(LOG_INFO,
             StringFormat("ABSOLUTE_MAX_LEVEL_TIME_EXIT | %s | pnl=%.2f | ageH=%.1f | orders=%d | levels=%d",
                          sym,
                          pnl,
                          basketAgeHours,
                          basketOrders,
                          basketLevels));
   
      CloseBasket(sym,
                  "absolute max-level time exit",
                  InpMaxLevelExitStartsCooldown);
   
      return true;
   }

   return false;
}

void ManageGridBasket()
{
   if(!InpUseGridBasket)
      return;

   SyncBasketStates();

   bool hasStaleBasket = HasStaleBasket(InpStaleCloseAgeStartHours);
   if(hasStaleBasket)
   {
      double globalRecoveryPnl = BasketNetProfit();
      double globalRecoveryReq = GlobalRecoveryClosePnl();
      if(globalRecoveryPnl >= globalRecoveryReq)
      {
         LogMsg(LOG_INFO,
                StringFormat("STALE_RECOVERY_CLOSE_ALL | globalPnl=%.2f | req=%.2f", globalRecoveryPnl, globalRecoveryReq));
         CloseAllBaskets("global pnl >= blended stale recovery target", false);
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
      double globalPnl    = BasketNetProfit();
      double avgEntry     = BasketAverageEntryPrice(sym);
      double targetPrice  = GridTargetPrice(bi);
      double trailArmDist = GridTrailArmPriceDistance(bi);
      double curPrice     = (g_baskets[bi].direction == POSITION_TYPE_BUY ? bid : ask);

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
      
      // First try to escape bad/deep baskets before normal TP/trailing logic.
      // This is especially important with limited grid levels.
      if(ManageBasketEscapeClose(bi))
         continue;
      
      bool staleBasketManaged   = (basketAgeHours >= InpStaleCloseAgeStartHours);
      bool recoveryRunner       = IsRecoveryRunnerBasket(bi, InpStaleCloseAgeStartHours);
      bool holdForStaleRecovery = (hasStaleBasket && recoveryRunner);
      
      double staleCloseReq = BasketRecoveryClosePnl(bi, true);
      double largeBasketReq = BasketRecoveryClosePnl(bi, false);

      if(staleBasketManaged && pnl >= staleCloseReq)
      {
         LogMsg(LOG_INFO,
                StringFormat("STALE_BASKET_PROFIT_CLOSE | basket=%s | pnl=%.2f | req=%.2f | ageH=%.1f | orders=%d",
                             sym, pnl, staleCloseReq, basketAgeHours, basketOrders));
         CloseBasket(sym, "stale basket >= blended recovery target", false);
         continue;
      }

      if(InpBasketProfitCloseMinOrders > 0 && basketOrders >= InpBasketProfitCloseMinOrders)
      {
         if(globalPnl >= largeBasketReq)
         {
            LogMsg(LOG_INFO,
                   StringFormat("GLOBAL_PROFIT_FLUSH | basket=%s | basketOrders=%d | basketPnl=%.2f | globalPnl=%.2f | req=%.2f",
                                sym, basketOrders, pnl, globalPnl, largeBasketReq));
            CloseAllBaskets("global pnl >= blended large-basket recovery target", false);
            return;
         }

         if(!holdForStaleRecovery && pnl >= largeBasketReq)
         {
            LogMsg(LOG_INFO,
                   StringFormat("BASKET_PROFIT_FLUSH | basket=%s | basketOrders=%d | basketPnl=%.2f | req=%.2f",
                                sym, basketOrders, pnl, largeBasketReq));
            CloseBasket(sym, "basket pnl >= blended recovery target with large basket", false);
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
      if(g_baskets[bi].levels >= GridMaxLevelsForSymbol(sym))
         continue;

      double pip = g_states[idx].pip;
      double adversePips = 0.0;

      if(g_baskets[bi].direction == POSITION_TYPE_BUY)
         adversePips = (g_baskets[bi].lastAddPrice - bid) / pip;
      else if(g_baskets[bi].direction == POSITION_TYPE_SELL)
         adversePips = (ask - g_baskets[bi].lastAddPrice) / pip;

      double requiredGap = NextGridGapPips(bi);
      bool allowGridAdd = true;
      
      if(InpGridOnlyOnNewBar)
      {
         int sidx = GetStateIndexBySymbol(sym);
      
         if(sidx >= 0)
         {
            allowGridAdd = IsNewBarForSymbolTF(sym,
                                               InpGridEvalTF,
                                               g_states[sidx].lastGridEvalBarTime);
         }
         else
         {
            allowGridAdd = false;
         }
      }
      
      if(allowGridAdd && adversePips >= requiredGap)
      {
         string macroGridReason = "";
         int nextGridLevel = g_baskets[bi].levels + 1;
         if(IsMacroNewsBlocked(sym, true, nextGridLevel, macroGridReason))
         {
            LogMsg(LOG_INFO,
                   StringFormat("GRID_ADD_BLOCKED_BY_MACRO | %s | nextLevel=%d | %s",
                                sym, nextGridLevel, macroGridReason));
            continue;
         }

         OpenGridLevel(bi);
      }
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
         {
            PrepareTradeForSymbol(sym);
            trade.PositionModify(sym, newSl, tp);
         }
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
      string sym = g_states[i].symbol;
      // Block only NEW entries/pending orders during blocked hours.
      // Existing baskets are still managed elsewhere.
      // Pair-specific blocking must be inside this symbol loop, otherwise
      // one blocked pair would cancel entries for all other symbols.
      string blockReason = "";
      if(IsBlockedEntryForSymbol(sym, blockReason))
      {
         CancelPendingsForSymbol(sym, true);
      
         if(InpLogLevel >= LOG_DEBUG)
         {
            LogMsg(LOG_DEBUG,
                   StringFormat("ENTRY BLOCKED | %s | %s | globalHours=%s | pairHours=%s | pairDayHours=%s",
                                sym,
                                blockReason,
                                InpBlockedEntryHours,
                                InpPairBlockedEntryHours,
                                InpPairDayBlockedEntryHours));
         }
      
         continue;
      }

      // ------------------------------------------------------------
      // Entry logic only once per selected bar, e.g. M15.
      // This prevents real-tick flicker from constantly creating /
      // cancelling pending orders inside the same candle.
      // ------------------------------------------------------------
      if(InpEntryOnlyOnNewBar)
      {
         if(!IsNewBarForSymbolTF(sym,
                                 InpEntryEvalTF,
                                 g_states[i].lastEntryEvalBarTime))
         {
            continue;
         }
      }

      SignalContext ctx;
      if(!EvaluateSignalContext(i, ctx))
      {
         // Because entries are now only evaluated on new bars,
         // you may choose to cancel old pendings here or not.
         // I prefer cancelling when context is invalid on the new bar.
         CancelPendingsForSymbol(sym, true);
         continue;
      }

      if(ctx.spreadPips > MaxSpreadPipsForSymbol(sym))
      {
         CancelPendingsForSymbol(sym, true);
         continue;
      }

      if(HasOpenPosition(sym))
      {
         if(InpCancelOppositeOnFill)
            CancelPendingsForSymbol(sym, true);
         continue;
      }

      bool basketAllowedSell = CanOpenNewBasket(sym, POSITION_TYPE_SELL);
      bool basketAllowedBuy  = CanOpenNewBasket(sym, POSITION_TYPE_BUY);

      bool sellOk = (ctx.sellSignal && basketAllowedSell);
      bool buyOk  = (ctx.buySignal  && basketAllowedBuy);

      if(!sellOk)
         CancelPendingByType(sym, ORDER_TYPE_SELL_STOP, false);

      if(!buyOk)
         CancelPendingByType(sym, ORDER_TYPE_BUY_STOP, false);

      double sellEntry = g_states[i].hoH1 + InpEntryBufferPoints * g_states[i].point;
      double buyEntry  = g_states[i].loH1 - InpEntryBufferPoints * g_states[i].point;

      double pendingSellSL = (InpUseGridBasket ? 0.0 : g_states[i].dailyHigh);
      double pendingBuySL  = (InpUseGridBasket ? 0.0 : g_states[i].dailyLow);

      double sellLots = GetInitialEntryLots(i, ORDER_TYPE_SELL_STOP, sellEntry);
      double buyLots  = GetInitialEntryLots(i, ORDER_TYPE_BUY_STOP, buyEntry);

      if(sellOk)
         EnsurePendingOrder(sym,
                            ORDER_TYPE_SELL_STOP,
                            sellEntry,
                            pendingSellSL,
                            sellLots,
                            "TMD SellStop");

      if(buyOk)
         EnsurePendingOrder(sym,
                            ORDER_TYPE_BUY_STOP,
                            buyEntry,
                            pendingBuySL,
                            buyLots,
                            "TMD BuyStop");
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

   int bgW = 980;
   int rows = ArraySize(g_states);
   int bgH = 205 + rows * 18;

   CreatePanelRect("BG", 20, 30, bgW, bgH, tmdBg, tmdBg);
   CreatePanelRect("TB", 23, 33, bgW - 6, 28, tmdBg, tmdBg);
   CreatePanelRect("S1", 30, 67, bgW - 40, 1, tmdSubtleBg, tmdBg);
   CreatePanelRect("S2", 30, 154, bgW - 40, 1, tmdSubtleBg, tmdBg);

   CreatePanelLabel("ONLINE_DOT", 30, 40, 10, tmdGreen, "●");
   CreatePanelLabel("ONLINE_TXT", 44, 40, 9, C'0,180,180', "ONLINE");
   CreatePanelLabel("SERVER", 115, 40, 9, tmdSilver, "--:--:--");
   CreatePanelLabel("TITLE", 505, 38, 11, C'0,230,230', "◆ TMD ◆", ANCHOR_UPPER);

   // Compact risk/account dashboard.
   CreatePanelLabel("G1L", 30, 76, 8, C'70,90,110', "BAL / EQ");
   CreatePanelLabel("G1V", 215, 76, 8, tmdSilver, "-", ANCHOR_RIGHT_UPPER);
   CreatePanelLabel("G2L", 30, 92, 8, C'70,90,110', "FLOAT P/L");
   CreatePanelLabel("G2V", 215, 92, 8, tmdSilver, "-", ANCHOR_RIGHT_UPPER);
   CreatePanelLabel("G3L", 30, 108, 8, C'70,90,110', "DD CUR / MAX");
   CreatePanelLabel("G3V", 215, 108, 8, tmdSilver, "-", ANCHOR_RIGHT_UPPER);
   CreatePanelLabel("G4L", 30, 124, 8, C'70,90,110', "MARGIN");
   CreatePanelLabel("G4V", 215, 124, 8, tmdSilver, "-", ANCHOR_RIGHT_UPPER);

   CreatePanelLabel("G5L", 250, 76, 8, C'70,90,110', "BASKETS");
   CreatePanelLabel("G5V", 455, 76, 8, tmdSilver, "-", ANCHOR_RIGHT_UPPER);
   CreatePanelLabel("G6L", 250, 92, 8, C'70,90,110', "PEND / SYMBOLS");
   CreatePanelLabel("G6V", 455, 92, 8, tmdSilver, "-", ANCHOR_RIGHT_UPPER);
   CreatePanelLabel("G7L", 250, 108, 8, C'70,90,110', "WINDOW");
   CreatePanelLabel("G7V", 455, 108, 8, tmdSilver, "-", ANCHOR_RIGHT_UPPER);
   CreatePanelLabel("G8L", 250, 124, 8, C'70,90,110', "AVG HOLD");
   CreatePanelLabel("G8V", 455, 124, 8, tmdSilver, "-", ANCHOR_RIGHT_UPPER);

   CreatePanelLabel("G9L", 500, 76, 8, C'70,90,110', "RISK / LOT");
   CreatePanelLabel("G9V", 730, 76, 8, tmdSilver, "-", ANCHOR_RIGHT_UPPER);
   CreatePanelLabel("G10L", 500, 92, 8, C'70,90,110', "GRID");
   CreatePanelLabel("G10V", 730, 92, 8, tmdSilver, "-", ANCHOR_RIGHT_UPPER);
   CreatePanelLabel("G11L", 500, 108, 8, C'70,90,110', "NEWS FILTER");
   CreatePanelLabel("G11V", 730, 108, 8, tmdSilver, "-", ANCHOR_RIGHT_UPPER);
   CreatePanelLabel("G12L", 500, 124, 8, C'70,90,110', "TIME FILTERS");
   CreatePanelLabel("G12V", 950, 124, 8, tmdSilver, "-", ANCHOR_RIGHT_UPPER);

   CreatePanelLabel("SYMHDR", 30, 162, 9, C'180,40,220', "SYMBOL STATUS");
   CreatePanelLabel("COL1", 30, 180, 8, C'70,90,110', "SYM");
   CreatePanelLabel("COL2", 115, 180, 8, C'70,90,110', "SIGNAL");
   CreatePanelLabel("COL3", 205, 180, 8, C'70,90,110', "GRID");
   CreatePanelLabel("COL4", 275, 180, 8, C'70,90,110', "PEND");
   CreatePanelLabel("COL5", 330, 180, 8, C'70,90,110', "P/L");
   CreatePanelLabel("COL6", 410, 180, 8, C'70,90,110', "DD%");
   CreatePanelLabel("COL7", 475, 180, 8, C'70,90,110', "TP%");
   CreatePanelLabel("COL8", 540, 180, 8, C'70,90,110', "AGE");
   CreatePanelLabel("COL9", 605, 180, 8, C'70,90,110', "SPR");
   CreatePanelLabel("COL10", 665, 180, 8, C'70,90,110', "ATR");
   CreatePanelLabel("COL11", 725, 180, 8, C'70,90,110', "NEWS");
   CreatePanelLabel("COL12", 955, 180, 8, C'70,90,110', "STATE / REASON", ANCHOR_RIGHT_UPPER);

   for(int i = 0; i < rows; i++)
   {
      int y = 198 + i * 18;
      CreatePanelLabel("R_SYM_"  + IntegerToString(i), 30,  y, 8, tmdSilver, "-");
      CreatePanelLabel("R_SIG_"  + IntegerToString(i), 115, y, 8, tmdSilver, "-");
      CreatePanelLabel("R_GRID_" + IntegerToString(i), 205, y, 8, tmdSilver, "-");
      CreatePanelLabel("R_PND_"  + IntegerToString(i), 275, y, 8, tmdSilver, "-");
      CreatePanelLabel("R_PNL_"  + IntegerToString(i), 330, y, 8, tmdSilver, "-");
      CreatePanelLabel("R_DD_"   + IntegerToString(i), 410, y, 8, tmdSilver, "-");
      CreatePanelLabel("R_TP_"   + IntegerToString(i), 475, y, 8, tmdSilver, "-");
      CreatePanelLabel("R_AGE_"  + IntegerToString(i), 540, y, 8, tmdSilver, "-");
      CreatePanelLabel("R_SPR_"  + IntegerToString(i), 605, y, 8, tmdSilver, "-");
      CreatePanelLabel("R_ATR_"  + IntegerToString(i), 665, y, 8, tmdSilver, "-");
      CreatePanelLabel("R_NEWS_" + IntegerToString(i), 725, y, 8, tmdSilver, "-");
      CreatePanelLabel("R_ACT_"  + IntegerToString(i), 955, y, 8, tmdSilver, "-", ANCHOR_RIGHT_UPPER);
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


int ActiveBasketIndexBySymbol(const string sym)
{
   for(int i = 0; i < ArraySize(g_baskets); i++)
   {
      if(g_baskets[i].active && g_baskets[i].symbol == sym)
         return i;
   }

   return -1;
}

string DirectionShort(const int direction)
{
   if(direction == POSITION_TYPE_BUY)
      return "B";
   if(direction == POSITION_TYPE_SELL)
      return "S";
   return "-";
}

string PanelRiskModeText()
{
   if(InpRiskMode == RISK_LOW)
      return "LOW";
   if(InpRiskMode == RISK_HIGH)
      return "HIGH";
   return "MED";
}

string PanelMacroModeText()
{
   if(!InpUseMacroNewsFilter)
      return "OFF";

   string mode = "";
   if(InpUseBacktestMacroWindows)
      mode = "BT";
   if(InpUseMql5CalendarLiveNews)
      mode = (mode == "" ? "CAL" : mode + "+CAL");
   if(mode == "")
      mode = "ON";

   string scope = "";
   if(InpMacroBlockNewEntries)
      scope += "E";
   if(InpMacroBlockGridAdds)
      scope += (scope == "" ? "" : "+") + "G>L" + IntegerToString(InpMacroGridBlockMinNextLevel - 1);

   if(scope != "")
      mode += " " + scope;

   return mode;
}

color PanelMacroModeColor()
{
   if(!InpUseMacroNewsFilter)
      return tmdRed;
   if(InpUseMql5CalendarLiveNews)
      return tmdGreen;
   if(InpUseBacktestMacroWindows)
      return tmdOrange;
   return tmdSilver;
}

string PanelFilterSummaryText()
{
   string txt = "H:" + InpBlockedEntryHours;

   if(InpPairBlockedEntryHours != "")
      txt += " | Pair:" + InpPairBlockedEntryHours;

   if(InpPairDayBlockedEntryHours != "")
      txt += " | Day:" + InpPairDayBlockedEntryHours;

   return FitPanelText(txt, 68);
}

string PanelGridText(const string sym)
{
   int bidx = ActiveBasketIndexBySymbol(sym);
   if(bidx < 0)
      return "-";

   return DirectionShort(g_baskets[bidx].direction) + IntegerToString(g_baskets[bidx].levels)
        + "/" + IntegerToString(GridMaxLevelsForSymbol(sym));
}

string PanelBasketStateText(const string sym)
{
   int bidx = ActiveBasketIndexBySymbol(sym);
   if(bidx < 0)
      return "-";

   double ageH = BasketAgeHours(bidx);
   string side = DirectionShort(g_baskets[bidx].direction);
   string base = side + IntegerToString(g_baskets[bidx].levels);

   if(ageH >= 24.0)
      return "STALE " + base;

   if(IsRecoveryRunnerBasket(bidx, 24.0))
      return "RECOV " + base;

   return "ACTIVE " + base;
}

string PanelSignalText(const int idx, color &clr)
{
   clr = tmdSilver;

   if(idx < 0 || idx >= ArraySize(g_states))
      return "-";

   string sym = g_states[idx].symbol;

   if(g_states[idx].spreadPips > MaxSpreadPipsForSymbol(sym))
   {
      clr = tmdRed;
      return "SPREAD";
   }

   if(g_states[idx].buySignal)
   {
      clr = Color_LO;
      return "BUY";
   }

   if(g_states[idx].sellSignal)
   {
      clr = Color_HO;
      return "SELL";
   }

   clr = tmdSilver;
   return "WAIT";
}

string PanelReasonText(const int idx)
{
   if(idx < 0 || idx >= ArraySize(g_states))
      return "-";

   int bidx = ActiveBasketIndexBySymbol(g_states[idx].symbol);
   if(bidx >= 0)
      return PanelBasketStateText(g_states[idx].symbol);

   if(g_states[idx].buySignal || g_states[idx].sellSignal)
      return "READY";

   string buyR  = FitPanelText(g_states[idx].buyReason, 12);
   string sellR = FitPanelText(g_states[idx].sellReason, 12);

   if(buyR == "" && sellR == "")
      return "-";

   return FitPanelText("B:" + buyR + " S:" + sellR, 26);
}

string PanelNewsStatusText(const string sym, color &clr)
{
   clr = tmdGreen;

   int idx = GetStateIndexBySymbol(sym);
   if(ArraySize(g_panelNewsLastCheck) != ArraySize(g_states))
   {
      ArrayResize(g_panelNewsLastCheck, ArraySize(g_states));
      ArrayResize(g_panelNewsLastText,  ArraySize(g_states));
      ArrayResize(g_panelNewsLastColor, ArraySize(g_states));

      for(int i = 0; i < ArraySize(g_panelNewsLastCheck); i++)
      {
         g_panelNewsLastCheck[i] = 0;
         g_panelNewsLastText[i]  = "";
         g_panelNewsLastColor[i] = tmdSilver;
      }
   }

   datetime now = TimeCurrent();
   if(idx >= 0 && idx < ArraySize(g_panelNewsLastCheck) &&
      g_panelNewsLastCheck[idx] > 0 &&
      (now - g_panelNewsLastCheck[idx]) < 60 &&
      g_panelNewsLastText[idx] != "")
   {
      clr = g_panelNewsLastColor[idx];
      return g_panelNewsLastText[idx];
   }

   string txt = "OK";

   if(!InpUseMacroNewsFilter)
   {
      clr = tmdSilver;
      txt = "OFF";
   }
   else
   {
      string reason = "";
      if(IsMacroNewsBlocked(sym, false, 0, reason))
      {
         clr = tmdRed;
         txt = "ENTRY";
      }
      else
      {
         int bidx = ActiveBasketIndexBySymbol(sym);
         if(bidx >= 0)
         {
            int nextLevel = g_baskets[bidx].levels + 1;
            if(nextLevel <= GridMaxLevelsForSymbol(sym) &&
               IsMacroNewsBlocked(sym, true, nextLevel, reason))
            {
               clr = tmdOrange;
               txt = "GRID";
            }
         }
      }
   }

   if(idx >= 0 && idx < ArraySize(g_panelNewsLastCheck))
   {
      g_panelNewsLastCheck[idx] = now;
      g_panelNewsLastText[idx]  = txt;
      g_panelNewsLastColor[idx] = clr;
   }

   return txt;
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
   color ddClr  = (ddMoney > 0.0 ? (ddPct >= 20.0 ? tmdRed : tmdOrange) : tmdGreen);

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

   SetPanelText("G1V", FormatMoney(bal) + " / " + FormatMoney(eq), tmdSilver);
   SetPanelText("G2V", FormatMoney(pnl), pnlClr);
   SetPanelText("G3V", FormatPercent(ddPct) + " / " + FormatPercent(g_maxGlobalDdPct), ddClr);
   SetPanelText("G4V", (marginLevel > 0.0 ? FormatPercent(marginLevel) : "N/A"), marginClr);

   string gridState = BasketSummaryText(InpMaxConcurrentBaskets);
   color gridClr = (ActiveBasketCount() > 0 ? tmdOrange : tmdGreen);
   SetPanelText("G5V", FitPanelText(gridState, 28), gridClr);
   SetPanelText("G6V", IntegerToString(PendingCount()) + " / " + IntegerToString(ArraySize(g_states)), tmdSilver);

   string windowTxt = (IsTradingWindow() ? "OPEN" : "CLOSED");
   if(IsCooldownActive())
      windowTxt += " / COOLDOWN";
   SetPanelText("G7V", windowTxt, IsCooldownActive() ? tmdOrange : (IsTradingWindow() ? tmdGreen : tmdRed));

   SetPanelText("G8V", (BasketPositionCount() > 0 ? FormatHours(avgHoldHrs, 1) : "-"), tmdSilver);

   SetPanelText("G9V",
                StringFormat("%s %.2f%% / base %.2f",
                             PanelRiskModeText(),
                             GetRiskPercent(),
                             InpLots),
                tmdSilver);

   SetPanelText("G10V",
                StringFormat("gap %dp x%.2f | max L%d | TP %.2f%%",
                             InpGridGapPips,
                             InpGridLotMultiplier,
                             InpGridMaxLevels,
                             InpGridTakeProfitPctPrice),
                tmdSilver);

   SetPanelText("G11V", PanelMacroModeText(), PanelMacroModeColor());
   SetPanelText("G12V", PanelFilterSummaryText(), tmdSilver);

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
      color bddClr     = (basketDdPct > 0.0 ? (basketDdPct >= 5.0 ? tmdRed : tmdOrange) : tmdSilver);
      color btpClr     = (basketTpPct >= 0.0 ? tmdOrange : tmdSilver);

      color sigClr;
      string sigTxt    = PanelSignalText(i, sigClr);
      string gridTxt   = PanelGridText(sym);
      string pndTxt    = IntegerToString(PendingCount(sym));
      string pnlTxt    = FormatMoney(symPnl);
      string ddTxt     = BasketFloatingDDPctText(sym);
      string tpTxt     = BasketTpDistancePctText(i);
      string ageTxt    = BasketAgeHoursText(i);
      string sprTxt    = FormatPips(g_states[i].spreadPips);
      string atrTxt    = DoubleToString(g_states[i].rangeAtrPct, 0);
      string reasonTxt = PanelReasonText(i);

      color newsClr;
      string newsTxt = PanelNewsStatusText(sym, newsClr);

      SetPanelText("R_SYM_"  + IntegerToString(i), sym, tmdSilver);
      SetPanelText("R_SIG_"  + IntegerToString(i), sigTxt, sigClr);
      SetPanelText("R_GRID_" + IntegerToString(i), gridTxt, basketPos > 0 ? tmdOrange : tmdSilver);
      SetPanelText("R_PND_"  + IntegerToString(i), pndTxt, PendingCount(sym) > 0 ? tmdOrange : tmdSilver);
      SetPanelText("R_PNL_"  + IntegerToString(i), pnlTxt, symPnlClr);
      SetPanelText("R_DD_"   + IntegerToString(i), ddTxt, bddClr);
      SetPanelText("R_TP_"   + IntegerToString(i), tpTxt, btpClr);
      SetPanelText("R_AGE_"  + IntegerToString(i), ageTxt, basketPos > 0 ? tmdOrange : tmdSilver);
      SetPanelText("R_SPR_"  + IntegerToString(i), sprTxt, g_states[i].spreadPips > MaxSpreadPipsForSymbol(sym) ? tmdRed : tmdSilver);
      SetPanelText("R_ATR_"  + IntegerToString(i), atrTxt, g_states[i].rangeAtrPct >= MinRangeAtrPctForSymbol(sym) ? tmdGreen : tmdSilver);
      SetPanelText("R_NEWS_" + IntegerToString(i), newsTxt, newsClr);
      SetPanelText("R_ACT_"  + IntegerToString(i), reasonTxt, basketPos > 0 ? tmdOrange : tmdSilver);
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

double NextGridGapPips(const int basketIdx)
{
   if(basketIdx < 0 || basketIdx >= ArraySize(g_baskets))
      return 0.0;

   string sym = g_baskets[basketIdx].symbol;
   int level = g_baskets[basketIdx].levels;
   // level 1 means next add is L2

   double gap = GridGapPipsForSymbol(sym) * MathPow(GridGapMultiplierForSymbol(sym), MathMax(0, level - 1));
   return MathMin(gap, GridGapMaxPipsForSymbol(sym));
}
bool CsvIntListContains(string csv, const int value)
{
   StringReplace(csv, " ", "");
   if(csv == "")
      return false;

   string parts[];
   int count = StringSplit(csv, ',', parts);

   for(int i = 0; i < count; i++)
   {
      if(parts[i] == "")
         continue;

      int v = (int)StringToInteger(parts[i]);
      if(v == value)
         return true;
   }

   return false;
}

bool SymbolMatchesBlockingRule(const string sym, const string ruleSymRaw)
{
   string cleanRule = Trim(ruleSymRaw);
   string cleanSym  = Trim(sym);

   if(cleanSym == cleanRule)
      return true;

   string symCore  = ExtractCoreSymbol(cleanSym);
   string ruleCore = ExtractCoreSymbol(cleanRule);

   if(symCore != "" && ruleCore != "" && symCore == ruleCore)
      return true;

   return false;
}

bool IsPairBlockedByHourRules(const string sym, const int hour)
{
   string rules = InpPairBlockedEntryHours;
   StringReplace(rules, " ", "");

   if(rules == "")
      return false;

   string entries[];
   int count = StringSplit(rules, ';', entries);

   for(int i = 0; i < count; i++)
   {
      string rule = entries[i];
      if(rule == "")
         continue;

      int eq = StringFind(rule, "=");
      if(eq <= 0)
      {
         PrintFormat("Invalid pair blocked entry rule ignored: %s", rule);
         continue;
      }

      string ruleSym = StringSubstr(rule, 0, eq);
      string hours   = StringSubstr(rule, eq + 1);

      if(SymbolMatchesBlockingRule(sym, ruleSym) && CsvIntListContains(hours, hour))
         return true;
   }

   return false;
}

bool IsPairBlockedByDayHourRules(const string sym, const int dayOfWeek, const int hour)
{
   string rules = InpPairDayBlockedEntryHours;
   StringReplace(rules, " ", "");

   if(rules == "")
      return false;

   string entries[];
   int count = StringSplit(rules, ';', entries);

   for(int i = 0; i < count; i++)
   {
      string rule = entries[i];
      if(rule == "")
         continue;

      int eq = StringFind(rule, "=");
      if(eq <= 0)
      {
         PrintFormat("Invalid pair-day blocked entry rule ignored: %s", rule);
         continue;
      }

      string left  = StringSubstr(rule, 0, eq);      // SYMBOL:days
      string hours = StringSubstr(rule, eq + 1);     // hours

      int colon = StringFind(left, ":");
      if(colon <= 0)
      {
         PrintFormat("Invalid pair-day blocked entry rule ignored: %s", rule);
         continue;
      }

      string ruleSym = StringSubstr(left, 0, colon);
      string days    = StringSubstr(left, colon + 1);

      if(!SymbolMatchesBlockingRule(sym, ruleSym))
         continue;

      if(CsvIntListContains(days, dayOfWeek) && CsvIntListContains(hours, hour))
         return true;
   }

   return false;
}


bool SymbolListContains(string list, const string sym)
{
   StringReplace(list, " ", "");
   if(list == "")
      return false;

   string parts[];
   int count = StringSplit(list, ',', parts);

   for(int i = 0; i < count; i++)
   {
      if(parts[i] == "")
         continue;
      if(SymbolMatchesBlockingRule(sym, parts[i]))
         return true;
   }

   return false;
}

bool CurrencyListContains(string list, const string ccyRaw)
{
   string ccy = ccyRaw;
   StringToUpper(ccy);
   StringReplace(list, " ", "");

   if(list == "" || ccy == "")
      return false;

   string parts[];
   int count = StringSplit(list, ',', parts);

   for(int i = 0; i < count; i++)
   {
      string p = parts[i];
      StringToUpper(p);
      if(p == ccy)
         return true;
   }

   return false;
}

bool GetCalendarCurrenciesForSymbol(const string sym, string &currenciesOut)
{
   currenciesOut = "";

   string rules = InpCalendarCurrenciesBySymbol;
   StringReplace(rules, " ", "");

   if(rules != "")
   {
      string entries[];
      int count = StringSplit(rules, ';', entries);

      for(int i = 0; i < count; i++)
      {
         string rule = entries[i];
         if(rule == "")
            continue;

         int eq = StringFind(rule, "=");
         if(eq <= 0)
            continue;

         string ruleSym = StringSubstr(rule, 0, eq);
         string ccys    = StringSubstr(rule, eq + 1);

         if(SymbolMatchesBlockingRule(sym, ruleSym))
         {
            currenciesOut = ccys;
            return true;
         }
      }
   }

   string base  = BaseCurrency(sym);
   string quote = QuoteCurrency(sym);

   if(base != "" && quote != "")
   {
      currenciesOut = base + "," + quote + ",USD";
      return true;
   }

   return false;
}

bool IsMacroWindowRuleActive(const string sym,
                             const string rule,
                             string &reason)
{
   reason = "";

   string cleanRule = Trim(rule);
   if(cleanRule == "")
      return false;

   int p1 = StringFind(cleanRule, "|");
   if(p1 <= 0)
   {
      PrintFormat("Invalid macro rule ignored: %s", cleanRule);
      return false;
   }

   int p2 = StringFind(cleanRule, "|", p1 + 1);
   if(p2 <= p1)
   {
      PrintFormat("Invalid macro rule ignored: %s", cleanRule);
      return false;
   }

   string timeRange = StringSubstr(cleanRule, 0, p1);
   string symbols   = StringSubstr(cleanRule, p1 + 1, p2 - p1 - 1);
   string tag       = StringSubstr(cleanRule, p2 + 1);

   if(!SymbolListContains(symbols, sym))
      return false;

   int arrow = StringFind(timeRange, ">");
   if(arrow <= 0)
   {
      PrintFormat("Invalid macro time range ignored: %s", cleanRule);
      return false;
   }

   datetime fromTime = StringToTime(StringSubstr(timeRange, 0, arrow));
   datetime toTime   = StringToTime(StringSubstr(timeRange, arrow + 1));

   if(fromTime <= 0 || toTime <= 0)
   {
      PrintFormat("Invalid macro date ignored: %s", cleanRule);
      return false;
   }

   datetime now = TimeCurrent();
   if(now >= fromTime && now <= toTime)
   {
      reason = StringFormat("macro window %s [%s]", sym, tag);
      return true;
   }

   return false;
}

bool IsBuiltInBacktestMacroWindowBlocked(const string sym, string &reason)
{
   reason = "";

   if(!InpUseBuiltInBacktestMacroWindows)
      return false;

   // Built-in windows are intentionally hardcoded for repeatable MT5 tester work.
   // This avoids losing rules when .set files / reports truncate semicolon-separated input strings.
   // The 2026.02 windows were added after real-tick testing: OHLC allowed a small L1 exit on 2026.02.06,
   // while real ticks kept the EURAUD buy basket open into L4 and a large loss.
   string rules[] =
   {
      "2025.04.18 00:00>2025.04.21 23:59|EURAUD|Easter_2025",
      "2025.07.28 00:00>2025.07.30 23:59|EURAUD|AU_CPI_FOMC_2025_07",
      "2025.09.08 00:00>2025.09.11 23:59|EURAUD|ECB_2025_09",
      "2025.10.28 00:00>2025.10.30 23:59|EURAUD|ECB_2025_10",
      "2025.12.20 00:00>2025.12.26 23:59|NZDCAD|YEAR_END_2025",
      "2026.02.02 00:00>2026.02.03 23:59|EURAUD,AUDCAD|RBA_RATE_DECISION_2026_02",
      "2026.02.05 00:00>2026.02.11 23:59|EURAUD,AUDCAD|ECB_US_JOBS_DELAY_REAL_TICK_2026_02",
      "2026.03.04 00:00>2026.03.04 23:59|NZDCAD|CAD_US_SERVICES_RISK_2026_03",
      "2026.04.02 00:00>2026.04.03 23:59|EURAUD|Easter_2026",
      "2026.01.20 00:00>2026.01.29 23:59|NZDCAD,AUDCAD|BOC_MPR_2026_01",
      "2026.01.01 00:00>2026.01.10 23:59|AUDCAD,NZDCAD|NEW_YEAR_CAD_2026"
   };

   for(int i = 0; i < ArraySize(rules); i++)
   {
      if(IsMacroWindowRuleActive(sym, rules[i], reason))
      {
         reason = "built-in " + reason;
         return true;
      }
   }

   return false;
}

bool IsExtraBacktestMacroWindowBlocked(const string sym, string &reason)
{
   reason = "";

   if(InpBacktestMacroWindows == "")
      return false;

   // Prefer || as separator. Backward-compatible semicolon support is kept.
   // Internally normalize both to semicolon and parse one complete rule per item.
   string rules = InpBacktestMacroWindows;
   StringReplace(rules, "||", ";");

   string entries[];
   int count = StringSplit(rules, ';', entries);

   for(int i = 0; i < count; i++)
   {
      if(IsMacroWindowRuleActive(sym, entries[i], reason))
      {
         reason = "extra " + reason;
         return true;
      }
   }

   return false;
}

bool IsHardcodedMacroWindowBlocked(const string sym, string &reason)
{
   reason = "";

   if(!InpUseBacktestMacroWindows)
      return false;

   if(IsBuiltInBacktestMacroWindowBlocked(sym, reason))
      return true;

   if(IsExtraBacktestMacroWindowBlocked(sym, reason))
      return true;

   return false;
}
bool IsLongCentralBankCurrency(const string ccy)
{
   string list = InpLongCentralBankCurrencies;
   StringReplace(list, " ", "");
   StringToUpper(list);

   string x = ccy;
   StringToUpper(x);

   return CurrencyListContains(list, x);
}

bool IsCentralBankEventName(string name)
{
   StringToUpper(name);

   if(StringFind(name, "INTEREST RATE") >= 0)          return true;
   if(StringFind(name, "RATE DECISION") >= 0)          return true;
   if(StringFind(name, "RATE STATEMENT") >= 0)         return true;
   if(StringFind(name, "MONETARY POLICY") >= 0)        return true;
   if(StringFind(name, "POLICY RATE") >= 0)            return true;
   if(StringFind(name, "OVERNIGHT RATE") >= 0)         return true;
   if(StringFind(name, "CASH RATE") >= 0)              return true;
   if(StringFind(name, "OCR") >= 0)                    return true; // RBNZ Official Cash Rate
   if(StringFind(name, "MPR") >= 0)                    return true; // Monetary Policy Report
   if(StringFind(name, "PRESS CONFERENCE") >= 0)       return true;

   return false;
}

datetime AddBusinessDays(datetime startTime, int businessDays)
{
   datetime t = startTime;
   int added = 0;

   while(added < businessDays)
   {
      t += 86400;

      MqlDateTime dt;
      TimeToStruct(t, dt);

      if(dt.day_of_week >= 1 && dt.day_of_week <= 5)
         added++;
   }

   return t;
}

datetime SubtractBusinessDays(datetime startTime, int businessDays)
{
   datetime t = startTime;
   int subtracted = 0;

   while(subtracted < businessDays)
   {
      t -= 86400;

      MqlDateTime dt;
      TimeToStruct(t, dt);

      if(dt.day_of_week >= 1 && dt.day_of_week <= 5)
         subtracted++;
   }

   return t;
}

bool IsLongCentralBankBlackoutEvent(const string sym,
                                    const bool forGridAdd,
                                    const int nextGridLevel,
                                    const string eventCurrency,
                                    const string eventName,
                                    const datetime eventTime,
                                    string &reason)
{
   reason = "";

   if(!InpUseLongCentralBankBlackout)
      return false;

   if(!IsLongCentralBankCurrency(eventCurrency))
      return false;

   if(!IsCentralBankEventName(eventName))
      return false;

   if(forGridAdd && nextGridLevel < InpCentralBankGridBlockMinNextLevel)
      return false;

   string ccys = "";
   if(!GetCalendarCurrenciesForSymbol(sym, ccys))
      return false;

   if(!CurrencyListContains(ccys, eventCurrency))
      return false;

   datetime now = TimeCurrent();

   int beforeDays = forGridAdd ? InpCentralBankGridBlockBeforeDays
                               : InpCentralBankEntryBlockBeforeDays;

   datetime blackoutStart = SubtractBusinessDays(eventTime, beforeDays);
   datetime blackoutEnd   = eventTime + InpCentralBankBlockAfterHours * 3600;

   if(now >= blackoutStart && now <= blackoutEnd)
   {
      reason = StringFormat("long CB blackout %s | %s | %s",
                            sym,
                            eventCurrency,
                            eventName);
      return true;
   }

   return false;
}
bool IsMql5CalendarNewsBlocked(const string sym,
                               const bool forGridAdd,
                               const int nextGridLevel,
                               string &reason)
{
   reason = "";

   if(!InpUseMql5CalendarLiveNews)
      return false;

   string ccys = "";
   if(!GetCalendarCurrenciesForSymbol(sym, ccys))
      return false;

   datetime now = TimeCurrent();

   int normalBeforeH = forGridAdd ? InpCalendarGridBlockBeforeHours
                                  : InpCalendarEntryBlockBeforeHours;

   int normalAfterH  = forGridAdd ? InpCalendarGridBlockAfterHours
                                  : InpCalendarEntryBlockAfterHours;

   int cbBeforeDays = forGridAdd ? InpCentralBankGridBlockBeforeDays
                                 : InpCentralBankEntryBlockBeforeDays;

   // Search far enough into the future to catch long central-bank blackout events.
   datetime normalFrom = now - normalAfterH * 3600;
   datetime normalTo   = now + normalBeforeH * 3600;

   datetime cbTo = AddBusinessDays(now, cbBeforeDays) + 86400;

   datetime fromTime = normalFrom;
   datetime toTime   = MathMax(normalTo, cbTo);

   MqlCalendarValue values[];
   int count = CalendarValueHistory(values, fromTime, toTime);

   if(count <= 0)
      return false;

   for(int i = 0; i < count; i++)
   {
      MqlCalendarEvent event;
      if(!CalendarEventById(values[i].event_id, event))
         continue;

      MqlCalendarCountry country;
      if(!CalendarCountryById(event.country_id, country))
         continue;

      string eventCurrency = country.currency;
      StringToUpper(eventCurrency);

      if(!CurrencyListContains(ccys, eventCurrency))
         continue;

      datetime eventTime = values[i].time;

      // 1) Special long central-bank blackout for CAD/NZD/AUD.
      string cbReason = "";
      if(IsLongCentralBankBlackoutEvent(sym,
                                        forGridAdd,
                                        nextGridLevel,
                                        eventCurrency,
                                        event.name,
                                        eventTime,
                                        cbReason))
      {
         reason = cbReason;
         return true;
      }

      // 2) Normal medium/high impact news block.
      if((int)event.importance < InpCalendarMinImportance)
         continue;

      datetime normalStart = eventTime - normalBeforeH * 3600;
      datetime normalEnd   = eventTime + normalAfterH * 3600;

      if(now >= normalStart && now <= normalEnd)
      {
         reason = StringFormat("calendar news %s | %s | %s",
                               sym,
                               eventCurrency,
                               event.name);
         return true;
      }
   }

   return false;
}

bool IsMacroNewsBlocked(const string sym,
                        const bool forGridAdd,
                        const int nextGridLevel,
                        string &reason)
{
   reason = "";

   if(!InpUseMacroNewsFilter)
      return false;

   if(forGridAdd)
   {
      if(!InpMacroBlockGridAdds)
         return false;
      if(nextGridLevel < InpMacroGridBlockMinNextLevel)
         return false;
   }
   else
   {
      if(!InpMacroBlockNewEntries)
         return false;
   }

   if(IsHardcodedMacroWindowBlocked(sym, reason))
      return true;

   if(IsMql5CalendarNewsBlocked(sym, forGridAdd,nextGridLevel, reason))
      return true;

   return false;
}

bool IsBlockedEntryForSymbol(const string sym, string &reason)
{
   reason = "";

   MqlDateTime dt;
   TimeToStruct(TimeTradeServer(), dt);

   int hour = dt.hour;
   int dow  = dt.day_of_week; // 0=Sunday, 1=Monday, ..., 5=Friday, 6=Saturday

   if(hour < 0 || hour > 23)
      return false;

   if(g_blockedEntryHours[hour])
   {
      reason = StringFormat("global blocked hour %d", hour);
      return true;
   }

   if(IsPairBlockedByHourRules(sym, hour))
   {
      reason = StringFormat("pair blocked hour %s hour %d", sym, hour);
      return true;
   }

   if(IsPairBlockedByDayHourRules(sym, dow, hour))
   {
      reason = StringFormat("pair/day blocked hour %s day %d hour %d", sym, dow, hour);
      return true;
   }

   string macroReason = "";
   if(IsMacroNewsBlocked(sym, false, 0, macroReason))
   {
      reason = macroReason;
      return true;
   }

   return false;
}
void ParseBlockedEntryHours()
{
   for(int h = 0; h < 24; h++)
      g_blockedEntryHours[h] = false;

   string s = InpBlockedEntryHours;
   StringReplace(s, " ", "");

   if(s == "")
      return;

   string parts[];
   int count = StringSplit(s, ',', parts);

   for(int i = 0; i < count; i++)
   {
      if(parts[i] == "")
         continue;

      int hour = (int)StringToInteger(parts[i]);

      if(hour >= 0 && hour <= 23)
         g_blockedEntryHours[hour] = true;
      else
         PrintFormat("Invalid blocked entry hour ignored: %s", parts[i]);
   }
}


bool IsBlockedEntryHour()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);

   int hour = dt.hour;

   if(hour < 0 || hour > 23)
      return false;

   return g_blockedEntryHours[hour];
}
int OnInit()
{
   
   ParseBlockedEntryHours();

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpDeviationPoints);

   if(!ParseSymbols())
      return INIT_FAILED;

   ResetAllBasketStates();

   StyleChart();
   CreatePanel();
   RefreshAllSymbolStates();
   UpdateCooldownFromHistoryIfNeeded();
   RefreshVisualLayer(true);
   EventSetTimer(1);
   LogMsg(LOG_INFO,
          StringFormat("EA initialized symbols=%d | commissionMode=%d | commissionRT=%.2f | commissionSide=%.2f | brokerPrefix='%s' | brokerSuffix='%s' | autoDetect=%s | macroFilter=%s | hardcodedMacro=%s | builtInMacro=%s | liveCalendar=%s",
                       ArraySize(g_states),
                       (int)InpCommissionMode,
                       InpCommissionPerLotRoundTurn,
                       InpCommissionPerLotPerSide,
                       InpBrokerSymbolPrefix,
                       InpBrokerSymbolSuffix,
                       (InpAutoDetectBrokerSymbols ? "true" : "false"),
                       (InpUseMacroNewsFilter ? "true" : "false"),
                       (InpUseBacktestMacroWindows ? "true" : "false"),
                       (InpUseMql5CalendarLiveNews ? "true" : "false")));
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
