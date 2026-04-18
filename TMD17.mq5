//+------------------------------------------------------------------+
//|                                                        TMD17.mq5 |
//|                                                              MDV |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "MDV"
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Trade/Trade.mqh>

#include <TMD/GridManager.mqh>

//+------------------------------------------------------------------+
//| TMD INFO PANEL                                                   |
//+------------------------------------------------------------------+
#define PANEL_PREFIX "TMDP_"
#define PANEL_CUR_ROWS 8
#define PANEL_SYM_ROWS 28

string gPanelObjects[];

double currencyStrength[8];


#define HISTORY 5

CTrade trade;


struct PairData
{
   string symbol;

   double score;

   double history[HISTORY];
   int    index;
   bool   filled;

   double slope;
   double accel;
   double baseStrength;
   double quoteStrength;
   bool aligned;
   double currencyScore;
   double comp;
   
   int direction; // ORDER_TYPE_BUY / ORDER_TYPE_SELL
   
   GridManager       *buyGrid;
   GridManager       *sellGrid;
   
   int            rsiM1Handle;
   int            bbM1Handle;
   
    // --- cached multi-timeframe values ---
   int atrM5Handle;
   int atrM15Handle;
   int atrH1Handle;
   int atrH4Handle;

   double sM5;
   double sM15;
   double sH1;
   double sH4;
   double bullScore;
   double signedStrength;
   double atrNormM15;
   
   // ---- cached panel state ----
   bool  eligibleNow;
   string stateText;
   color stateColor;
   color dotColor;
   
   // ---- cached filter data ----
   bool   filtersValid;
   double rsiM1;
   double bbUpperM1;
   double bbLowerM1;
   bool   rsiBuyOk;
   bool   rsiSellOk;
   bool   bbBuyOk;
   bool   bbSellOk;
   
   // ---- cache flags ----
   bool   needsFilterRefresh;
   bool   structurallyValid;   // direction/alignment/comp/session/trade window eligible
   
   bool marketOpen;
   
   int    openCount;
   double openLots;
   
};

PairData Pairs[];

enum ENUM_ONOFF
{
   OFF = 0,
   ON  = 1
};

input group "=== Symbol Settings ===";
input string InpSuffix = ""; // Symbol Suffix
input string InpPrefix = ""; // Symbol Prefix
input group "=== Lot Settings ===";
input ENUM_ONOFF InpUseAutoLot = ON; // Auto-Lot
input double InpBalancePerLot = 500; // Grid Initial Balance per Lot - Auto-Lot
input double InpInitialLot = 0.01; // Grid Initial Lot (Fixed - Only when Auto-Lot is OFF)
input ENUM_ONOFF InpUseDynamicLot = ON;
input double InpMinLotFactor = 0.5;   // weakest trades
input double InpMaxLotFactor = 2.0;   // strongest trades
input group "=== Grid Settings ===";
input int InpMagicBuy = 2204; // Grid Magic Buy Base Nr
input int InpMagicSell = 1981; // Grid Magic Sell Base Nr
input int InpMaxOrders = 14; // Grid Max Orders
input double InpMaxDD = 0; // Grid Max DD
input int InpGapPoints = 200; // Grid Gap Points
input double InpProfitPercent = 0.06; // Take Profit Percentage
input double InpGridMultiplier = 1.05; // Grid Multiplier
input group "=== Filter Settings ===";
input double InpMinScore = 6.5; // Minimum Strength Score
input double InpBuyRsi = 35; // Maximum RSI for BUY
input double InpSellRsi = 65; // Minimum RSI for SELL
input ENUM_ONOFF InpUseTop2Filter = OFF;
input ENUM_ONOFF   InpUseBB = ON; // BB Filter
input ENUM_ONOFF InpUseM15Filter = OFF;      // Use M15 as optional direction filter
input double     InpM15FilterMin = 0.10;    // Minimum same-side M15 strength when filter is enabled
input double InpMinAccel = 4.5; // Minimum acceleration for new entries
input group "=== Risk Protection ===";
input ENUM_ONOFF InpUseRiskProtection      = ON;    // Master risk protection
input double     InpFreezeDDPercent        = 0.70;  // Freeze new risk at % of Grid Max DD
input double     InpCriticalMarginLevel    = 180.0; // Emergency close all below this margin level %
input double     InpFreezeMarginLevel      = 350.0; // No new grids below this margin level %
input double     InpFreezeFreeMarginPct    = 80.0;  // No new grids below this free margin % of equity
input int        InpMaxTotalPositions      = 20;    // Global max open positions
input double     InpBaseBalanceForMaxLots  = 1000.0; // Balance reference for max total lots
input double     InpBaseMaxTotalLots       = 0.25;   // Max total lots at reference balance
input double     InpMinMaxTotalLots        = 0.10;   // Floor for dynamic max total lots
input double     InpHardMaxTotalLots       = 10.00;   // Absolute cap for dynamic max total lots
input double     InpMaxFirstOrderMarginPct = 20.0;  // First order may use at most X% of free margin
input ENUM_ONOFF InpBlockGridExpansion     = ON;    // Block adding recovery legs under stress
input double     InpFreezeExpansionDD      = 8.0;   // Freeze adding grid levels above this DD %
input double     InpFreezeExpansionMargin  = 300.0; // Freeze adding grid levels below this margin %
input double     InpMaxSpreadPoints        = 25.0;  // Block new entries above this spread
input double InpBaseBalanceForTrendExitProfit = 1000.0; // Balance reference
input double InpBaseTrendExitMinProfit        = 1.50;   // Min profit at reference balance
input double InpMinTrendExitProfit            = 0.30;   // Floor
input double InpMaxTrendExitProfit            = 100.00;  // Cap
input group "=== Visual Settings ===";
input ENUM_ONOFF        InpStyleChart = ON;              // TMD Chart Style
input ENUM_ONOFF        InpShowPanel = ON;   // Show Panel
string Symbols[] = {
   "EURUSD","GBPUSD","AUDUSD","NZDUSD",
   "USDJPY","USDCHF","USDCAD",
   "EURGBP","EURJPY","EURCHF","EURAUD","EURNZD","EURCAD",
   "GBPJPY","GBPCHF","GBPAUD","GBPNZD","GBPCAD",
   "AUDJPY","AUDCHF","AUDNZD","AUDCAD",
   "NZDJPY","NZDCHF","NZDCAD",
   "CADJPY","CADCHF","CHFJPY"
};
string Currencies[] = {"USD","EUR","GBP","JPY","CHF","AUD","NZD","CAD"};

string GROUP_USD[] = {"EURUSD","GBPUSD","AUDUSD","NZDUSD","USDJPY","USDCHF","USDCAD"};

string GROUP_EUR[] = {"EURGBP","EURJPY","EURCHF","EURAUD","EURNZD","EURCAD"};

string GROUP_GBP[] = {"GBPJPY","GBPCHF","GBPAUD","GBPNZD","GBPCAD"};

string GROUP_AUDNZD[] = {"AUDJPY","AUDCHF","AUDNZD","AUDCAD","NZDJPY","NZDCHF","NZDCAD"};

string GROUP_SAFE[] = {"CADJPY","CADCHF","CHFJPY"};

struct GroupState
{
   int buyCount;
   int sellCount;
};


// Colors
color tmdGreen = C'38,166,154';
color tmdRed =    C'239,83,80';
color tmdOrange = C'255,152,0';
color tmdSilver = C'219,219,219';
color tmdBg = C'16,26,37';
color tmdSubtleBg = C'42,58,79';
color tmdBid = C'41, 98, 255';
color tmdAsk = C'247, 82, 95';


double currentPnL;
int PairSize;
bool brokerWindowOpen;
GroupState gGroupStates[5];
double gPeakEquity = 0.0;
bool   gFreezeNewEntries = false;
bool   gEmergencyClose   = false;
string gRiskStateText      = "NORMAL";
color  gRiskStateColor     = tmdGreen;

string gEntryStateText     = "ALLOWED";
color  gEntryStateColor    = tmdGreen;

string gExpandStateText    = "ALLOWED";
color  gExpandStateColor   = tmdGreen;

string gRiskReasonText     = "-";
color  gRiskReasonColor    = tmdSilver;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//---
   TesterHideIndicators(true);
   StyleChart();
   InitPairs();
   UpdateAllPairs();

   CreateTMDInfoPanel();
   UpdateTMDInfoPanel();   
   
   gPeakEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   gFreezeNewEntries = false;
   gEmergencyClose   = false;
   
   Print("==== TMD[1.0] Initialized with "+IntegerToString((int) Symbols.Size())+" symbols ====");
   
//---
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
//---
      DeleteTMDInfoPanel();
      for(int i=0;i< (int) Pairs.Size();i++)
      { 
         delete Pairs[i].buyGrid;
         delete Pairs[i].sellGrid;
         IndicatorRelease(Pairs[i].rsiM1Handle);
         IndicatorRelease(Pairs[i].bbM1Handle);
         IndicatorRelease(Pairs[i].atrM5Handle);
         IndicatorRelease(Pairs[i].atrM15Handle);
         IndicatorRelease(Pairs[i].atrH1Handle);
         IndicatorRelease(Pairs[i].atrH4Handle);
      }
  
   Print("==== TMD[1.0] Stopped ====");
   
  }
  
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   currentPnL = 0.0;

   brokerWindowOpen = IsBrokerTradeWindow();

   UpdatePeakEquity();
   
   // Maintain all grids first
   for(int i = 0; i < PairSize; i++)
   {
      bool allowBuyExpansion  = AllowGridExpansion(i, true);
      bool allowSellExpansion = AllowGridExpansion(i, false);
   
      Pairs[i].buyGrid.SetAllowExpansion(allowBuyExpansion);
      Pairs[i].sellGrid.SetAllowExpansion(allowSellExpansion);
   
      Pairs[i].buyGrid.Update();
      currentPnL += Pairs[i].buyGrid.GridPnL();
   
      Pairs[i].sellGrid.Update();
      currentPnL += Pairs[i].sellGrid.GridPnL();
   }
   
   RefreshPositionCaches();
   RefreshGroupStates();

   EvaluateRiskState();
   UpdateRiskPanelState();

   if(gEmergencyClose)
   {
      string reason = "UNKNOWN";

      double ddPct       = GetEquityDDPercent();
      double marginLevel = GetMarginLevelPercent();

      if(InpMaxDD > 0.0 && ddPct >= InpMaxDD)
         reason = "MAX DD HIT";
      else if(InpCriticalMarginLevel > 0.0 &&
              marginLevel > 0.0 &&
              marginLevel < InpCriticalMarginLevel)
         reason = "CRITICAL MARGIN LEVEL";

      EmergencyCloseAllGrids(reason);
      UpdateTMDInfoPanel();
      return;
   }

   static datetime lastBar = 0;
   datetime currentBar = iTime(_Symbol, PERIOD_M15, 0);

   if(currentBar != lastBar)
   {
      lastBar = currentBar;
      UpdateAllPairs();
   }

   static datetime lastEntryBar = 0;
   datetime currentEntryBar = iTime(_Symbol, PERIOD_M5, 0);
   
   bool newEntryBar = (currentEntryBar != lastEntryBar);
   if(newEntryBar)
   {
      lastEntryBar = currentEntryBar;
      RefreshAllPairFilterCaches();
      CheckExit();
      CheckEntry();
   }
   
      
   
      UpdateTMDInfoPanel();
   }

void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
   // Mouse click
   if(id == CHARTEVENT_CLICK)
   {
      int x = (int)lparam;
      int y = (int)dparam;

      HandleTMDPanelChartClick(x, y);
   }
}
//+------------------------------------------------------------------+


bool CheckMarketOpen(string symbol)
{
   MqlDateTime date_cur;
   TimeTradeServer(date_cur);
   datetime seconds_cur = date_cur.hour * 3600 + date_cur.min * 60 + date_cur.sec;

   for(int i = 0; ; i++)
   {
      datetime seconds_from = 0, seconds_to = 0;
      if(!SymbolInfoSessionTrade(symbol, (ENUM_DAY_OF_WEEK)date_cur.day_of_week, i, seconds_from, seconds_to))
         break;

      if(seconds_cur >= seconds_from && seconds_cur < seconds_to)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Calculate lot size based on account balance                      |
//| Default: 0.01 lots per 500 balance                               |
//+------------------------------------------------------------------+
double CalculateLotSize(string symbol, double balancePerLot = 500.0, double lotPerBalance = 0.01)
{
    // Get current account balance
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double exponent   = 0.65;
    double capBalance = 10000.0;
    double lots = (balance / balancePerLot) * lotPerBalance;
      
      if(balance > capBalance)
      {
          double baseLots = (capBalance / balancePerLot) * lotPerBalance;
          double excess   = balance - capBalance;
          lots = baseLots + MathPow(excess / balancePerLot, exponent) * lotPerBalance;
      }
    
  
    // Optional: round to broker lot step
    double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
    double minLot  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
    double maxLot  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
    
    if(lotStep <= 0) lotStep = 0.01;
   if(minLot <= 0)  minLot  = lotStep;
   if(maxLot <= 0)  maxLot  = 100.0;
    
    
    // Round down to nearest lot step
    lots = MathFloor(lots / lotStep) * lotStep;
    
    // Ensure lots are within broker limits
    if(lots < minLot) lots = minLot;
    if(lots > maxLot) lots = maxLot;
    
    return lots;
}  



int GetGroup(string symbol)
{
   if(IsInGroup(symbol, GROUP_USD)) return 0;
   if(IsInGroup(symbol, GROUP_EUR)) return 1;
   if(IsInGroup(symbol, GROUP_GBP)) return 2;
   if(IsInGroup(symbol, GROUP_AUDNZD)) return 3;
   if(IsInGroup(symbol, GROUP_SAFE)) return 4;

   return -1;
}



bool CanOpenGrid(string symbol, bool isBuy)
{
   int group = GetGroup(symbol);
   if(group == -1)
      return true;

   int total = gGroupStates[group].buyCount + gGroupStates[group].sellCount;
   if(total >= 2)
      return false;

   if(isBuy && gGroupStates[group].buyCount > 0)
      return false;

   if(!isBuy && gGroupStates[group].sellCount > 0)
      return false;

   return true;
}

void GetGroupState(int group, GroupState &state)
{
   state.buyCount = 0;
   state.sellCount = 0;

   for(int i = 0; i < PositionsTotal(); i++)
   {
      if(PositionGetTicket(i))
      {
         string sym = PositionGetString(POSITION_SYMBOL);
         int posGroup = GetGroup(sym);

         if(posGroup != group)
            continue;

         ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

         if(type == POSITION_TYPE_BUY)
            state.buyCount = 1;
         else if(type == POSITION_TYPE_SELL)
            state.sellCount = 1;
      }
   }
}

bool IsInGroup(string symbol, string &group[])
{
   int size = ArraySize(group);
   
   for(int i = 0; i < size; i++)
   {
      if(symbol == InpPrefix+group[i]+InpSuffix)
         return true;
   }
   return false;
}

// Returns true if broker-server trading window is allowed.
// Offset is derived from current server time vs UTC.
bool IsBrokerTradeWindow()
{
   MqlDateTime broker;
   TimeToStruct(TimeCurrent(), broker);

   if(broker.day_of_week == 1 && broker.hour < 10)
      return false;

   if(broker.day_of_week == 5 && broker.hour >= 19)
      return false;

   return true;
}

double GetStrengthFast(string symbol, ENUM_TIMEFRAMES tf, int atrHandle)
{
   if(atrHandle == INVALID_HANDLE)
      return 0.0;

   MqlRates rates[];
   ArraySetAsSeries(rates, true);

   if(CopyRates(symbol, tf, 1, 1, rates) < 1)
      return 0.0;

   double atrBuf[];
   ArraySetAsSeries(atrBuf, true);

   if(CopyBuffer(atrHandle, 0, 1, 1, atrBuf) < 1)
      return 0.0;

   if(atrBuf[0] <= 0.0)
      return 0.0;

   double raw = (rates[0].close - rates[0].open) / atrBuf[0];
   return MathTanh(raw); // -1 .. +1
}



void InitPairs()
{
   int total = ArraySize(Symbols);
   PairSize = ArraySize(Symbols);
   ArrayResize(Pairs, total);

   for(int i=0; i<total; i++)
   {
      Pairs[i].symbol = InpPrefix+Symbols[i]+InpSuffix;
      SymbolSelect(Pairs[i].symbol, true);
      Pairs[i].index  = 0;
      Pairs[i].filled = false;
      ArrayInitialize(Pairs[i].history, 0);
      
      Pairs[i].rsiM1Handle = iRSI(Pairs[i].symbol, PERIOD_M5, 14, PRICE_CLOSE);
      Pairs[i].bbM1Handle  = iBands(Pairs[i].symbol, PERIOD_M5, 20, 0, 2, PRICE_CLOSE);
      
      double initialLot = InpInitialLot;
      if (InpUseAutoLot) {
         initialLot = CalculateLotSize(Pairs[i].symbol,InpBalancePerLot);
      }

      Pairs[i].buyGrid = new GridManager(Pairs[i].symbol,GRID_BUY,initialLot,InpGapPoints,InpProfitPercent,InpMaxOrders);
      Pairs[i].buyGrid.SetGridMagicNumber(InpMagicBuy + i);
      Pairs[i].buyGrid.SetGridMultiplier(InpGridMultiplier);
      Pairs[i].buyGrid.SetGridMaxDD(InpMaxDD);
      
      
      Pairs[i].sellGrid = new GridManager(Pairs[i].symbol,GRID_SELL,initialLot,InpGapPoints,InpProfitPercent,InpMaxOrders);
      Pairs[i].sellGrid.SetGridMagicNumber(InpMagicSell + i);
      Pairs[i].sellGrid.SetGridMultiplier(InpGridMultiplier);
      Pairs[i].sellGrid.SetGridMaxDD(InpMaxDD);
      
      
      Pairs[i].filtersValid = false;
      Pairs[i].rsiM1        = 0.0;
      Pairs[i].bbUpperM1    = 0.0;
      Pairs[i].bbLowerM1    = 0.0;
      Pairs[i].rsiBuyOk     = false;
      Pairs[i].rsiSellOk    = false;
      Pairs[i].bbBuyOk      = false;
      Pairs[i].bbSellOk     = false;

      Pairs[i].eligibleNow  = false;
      Pairs[i].stateText    = "WAIT";
      Pairs[i].stateColor   = tmdSilver;
      Pairs[i].dotColor     = tmdSilver;
      
      Pairs[i].needsFilterRefresh  = false;
      Pairs[i].structurallyValid   = false;
      
      
      Pairs[i].atrM5Handle  = iATR(Pairs[i].symbol, PERIOD_M5, 14);
      Pairs[i].atrM15Handle = iATR(Pairs[i].symbol, PERIOD_M15, 14);
      Pairs[i].atrH1Handle  = iATR(Pairs[i].symbol, PERIOD_H1, 14);
      Pairs[i].atrH4Handle  = iATR(Pairs[i].symbol, PERIOD_H4, 14);
      
      Pairs[i].sM5 = 0.0;
      Pairs[i].sM15 = 0.0;
      Pairs[i].sH1 = 0.0;
      Pairs[i].sH4 = 0.0;
      Pairs[i].bullScore = 5.0;
      Pairs[i].signedStrength = 0.0;
      Pairs[i].atrNormM15 = 1.0;
      
      
   }
}

void UpdatePairHistory(PairData &p, double score)
{
   p.history[p.index] = score;

   p.index++;
   if(p.index >= HISTORY)
   {
      p.index = 0;
      p.filled = true;
   }
}

void UpdateMomentum(PairData &p)
{
   int count = p.filled ? HISTORY : p.index;

   if(count < 2)
   {
      p.slope = 5.0;
      p.accel = 5.0;
      return;
   }

   int newestIdx = (p.index - 1 + HISTORY) % HISTORY;
   int oldestIdx = p.filled ? p.index : 0;

   double rawSlope = p.history[newestIdx] - p.history[oldestIdx];
   double rawAccel = 0.0;

   if(count >= 3)
   {
      int idx2 = (newestIdx - 1 + HISTORY) % HISTORY;
      int idx3 = (newestIdx - 2 + HISTORY) % HISTORY;

      double slopeNow  = p.history[newestIdx] - p.history[idx2];
      double slopePrev = p.history[idx2] - p.history[idx3];

      rawAccel = slopeNow - slopePrev;
   }

   double vol = p.atrNormM15;
   if(vol <= 0.0)
      vol = 1.0;

   double slopeMult = 1.2 / vol;
   double accelMult = 2.0 / vol;

   p.slope = (MathTanh(rawSlope * slopeMult) + 1.0) * 5.0;
   p.accel = (MathTanh(rawAccel * accelMult) + 1.0) * 5.0;

   p.slope = MathMax(0.0, MathMin(10.0, p.slope));
   p.accel = MathMax(0.0, MathMin(10.0, p.accel));
}


void UpdateAllPairs()
{
   ArrayInitialize(currencyStrength, 0.0);

   int counts[8];
   ArrayInitialize(counts, 0);

   // -------------------------------------------------
   // Pass 1: compute MTF strength ONCE per pair
   // -------------------------------------------------
   for(int i = 0; i < PairSize; i++)
   {
  
      
      Pairs[i].marketOpen = CheckMarketOpen(Pairs[i].symbol);
      Pairs[i].sM5  = GetStrengthFast(Pairs[i].symbol, PERIOD_M5,  Pairs[i].atrM5Handle);
      Pairs[i].sM15 = GetStrengthFast(Pairs[i].symbol, PERIOD_M15, Pairs[i].atrM15Handle);
      Pairs[i].sH1  = GetStrengthFast(Pairs[i].symbol, PERIOD_H1,  Pairs[i].atrH1Handle);
      Pairs[i].sH4  = GetStrengthFast(Pairs[i].symbol, PERIOD_H4,  Pairs[i].atrH4Handle);

      Pairs[i].direction      = GetDirectionFromStrengths(Pairs[i].sH1, Pairs[i].sH4, Pairs[i].sM15);
      Pairs[i].bullScore      = GetBullScoreFromStrengths(Pairs[i].sM5, Pairs[i].sM15, Pairs[i].sH1, Pairs[i].sH4);
      Pairs[i].signedStrength = Pairs[i].bullScore - 5.0; // -5 .. +5
      Pairs[i].score          = ToDirectionalScore(Pairs[i].bullScore, Pairs[i].direction);
      Pairs[i].atrNormM15     = GetATRNormalizedFast(Pairs[i].symbol, Pairs[i].atrM15Handle, PERIOD_M15);

      UpdatePairHistory(Pairs[i], Pairs[i].score);
      UpdateMomentum(Pairs[i]);

      string base  = StringSubstr(Pairs[i].symbol, 0, 3);
      string quote = StringSubstr(Pairs[i].symbol, 3, 3);

      int baseIdx  = GetCurrencyIndexFast(base);
      int quoteIdx = GetCurrencyIndexFast(quote);

      if(baseIdx >= 0)
      {
         currencyStrength[baseIdx] += Pairs[i].signedStrength;
         counts[baseIdx]++;
      }

      if(quoteIdx >= 0)
      {
         currencyStrength[quoteIdx] -= Pairs[i].signedStrength;
         counts[quoteIdx]++;
      }
   }

   for(int i = 0; i < 8; i++)
   {
      if(counts[i] > 0)
         currencyStrength[i] /= counts[i];
   }

   // -------------------------------------------------
   // Pass 2: compute alignment / currency score / comp
   // -------------------------------------------------
   for(int i = 0; i < PairSize; i++)
   {

      int baseIdx, quoteIdx;
      GetPairCurrencies(Pairs[i].symbol, baseIdx, quoteIdx);

      if(baseIdx < 0 || quoteIdx < 0)
      {
         Pairs[i].aligned       = false;
         Pairs[i].baseStrength  = 0.0;
         Pairs[i].quoteStrength = 0.0;
         Pairs[i].currencyScore = 0.0;
         Pairs[i].comp          = 0.0;
         continue;
      }

      double baseStr  = currencyStrength[baseIdx];
      double quoteStr = currencyStrength[quoteIdx];

      Pairs[i].baseStrength  = baseStr;
      Pairs[i].quoteStrength = quoteStr;

      double dirSpread = 0.0;
      if(Pairs[i].direction == ORDER_TYPE_BUY)
         dirSpread = baseStr - quoteStr;
      else if(Pairs[i].direction == ORDER_TYPE_SELL)
         dirSpread = quoteStr - baseStr;

      double curScore = (MathTanh(dirSpread * 1.2) + 1.0) * 5.0;
      Pairs[i].currencyScore = MathMax(0.0, MathMin(10.0, curScore));

      Pairs[i].aligned =
         (Pairs[i].direction == ORDER_TYPE_BUY  && baseStr > quoteStr) ||
         (Pairs[i].direction == ORDER_TYPE_SELL && quoteStr > baseStr);

      double compRaw =
         Pairs[i].score         * 3.0 +
         Pairs[i].slope         * 2.5 +
         Pairs[i].accel         * 1.5 +
         Pairs[i].currencyScore * 3.0;

      Pairs[i].comp = MathMax(0.0, MathMin(10.0, compRaw / 10.0));
   }
}



void StyleChart() {
   
       if (InpStyleChart) {
         long chart = ChartID();
         ChartSetInteger(chart, CHART_COLOR_BACKGROUND, tmdBg);
         ChartSetInteger(chart, CHART_COLOR_FOREGROUND, tmdSilver);
         ChartSetInteger(chart, CHART_COLOR_GRID, tmdSubtleBg );
         ChartSetInteger(chart, CHART_COLOR_CANDLE_BULL, tmdGreen);
         ChartSetInteger(chart, CHART_COLOR_CANDLE_BEAR, tmdRed);
         ChartSetInteger(chart, CHART_COLOR_CHART_UP, tmdGreen);
         ChartSetInteger(chart, CHART_COLOR_CHART_DOWN, tmdRed);
         ChartSetInteger(chart, CHART_COLOR_STOP_LEVEL, tmdOrange);
         ChartSetInteger(chart, CHART_COLOR_BID,tmdBid);
         ChartSetInteger(chart, CHART_COLOR_ASK,tmdAsk);
        
         // ----- Chart options -----
         ChartSetInteger(chart, CHART_SHOW_GRID, false);
         ChartSetInteger(chart, CHART_SHOW_VOLUMES, false);
         ChartSetInteger(chart, CHART_SHOW_PERIOD_SEP, false);
         ChartSetInteger(chart, CHART_SHOW_OBJECT_DESCR, false);
         ChartSetInteger(chart, CHART_SHOW_OHLC, true);
         ChartSetInteger(chart, CHART_SHOW_ASK_LINE, true);
         ChartSetInteger(chart, CHART_SHOW_BID_LINE, true);
       
         
         // ----- Candles -----
         ChartSetInteger(chart, CHART_MODE, CHART_CANDLES);
         ChartSetInteger(chart, CHART_SCALE, 3);
         ChartSetInteger(chart, CHART_AUTOSCROLL, true);
         ChartSetInteger(chart, CHART_SHIFT, true);
         
         ChartRedraw();

      } 
}

void CheckEntry()
{
   if(!AllowNewRisk())
      return;


   int top1 = -1, top2 = -1;
   if(InpUseTop2Filter)
      GetTop2Pairs(top1, top2);

   for(int i = 0; i < PairSize; i++)
   {
      if(InpUseTop2Filter && i != top1 && i != top2)
         continue;

      if(!IsPairEligibleNow(i))
         continue;
       
      if(!HasEntryTrigger(i))
         continue; 

      if(!SpreadAcceptable(Pairs[i].symbol, InpMaxSpreadPoints))
         continue;

      double baseLot = InpUseAutoLot ? CalculateLotSize(Pairs[i].symbol, InpBalancePerLot) : InpInitialLot;
      double lotSize = GetDynamicLotSize(baseLot, Pairs[i].comp);

      if(Pairs[i].direction == ORDER_TYPE_BUY)
      {
         if(!CanAffordOrder(Pairs[i].symbol, ORDER_TYPE_BUY, lotSize))
            continue;

         Print("TRADE BUY: ", Pairs[i].symbol,
               " | Comp: ", DoubleToString(Pairs[i].comp,2),
               " | Score: ", DoubleToString(Pairs[i].score,2),
               " | Cur: ", DoubleToString(Pairs[i].currencyScore,2),
               " | Sl: ", DoubleToString(Pairs[i].slope,2),
               " | Ac: ", DoubleToString(Pairs[i].accel,2),
               " | RSI: ", DoubleToString(Pairs[i].rsiM1,1),
               " | Lot: ", DoubleToString(lotSize,2));

         Pairs[i].buyGrid.SetLotSize(lotSize);
         Pairs[i].buyGrid.Start();
         continue;
      }

      if(Pairs[i].direction == ORDER_TYPE_SELL)
      {
         if(!CanAffordOrder(Pairs[i].symbol, ORDER_TYPE_SELL, lotSize))
            continue;

         Print("TRADE SELL: ", Pairs[i].symbol,
               " | Comp: ", DoubleToString(Pairs[i].comp,2),
               " | Score: ", DoubleToString(Pairs[i].score,2),
               " | Cur: ", DoubleToString(Pairs[i].currencyScore,2),
               " | Sl: ", DoubleToString(Pairs[i].slope,2),
               " | Ac: ", DoubleToString(Pairs[i].accel,2),
               " | RSI: ", DoubleToString(Pairs[i].rsiM1,1),
               " | Lot: ", DoubleToString(lotSize,2));

         Pairs[i].sellGrid.SetLotSize(lotSize);
         Pairs[i].sellGrid.Start();
      }
   }
}

void CheckExit()
{
   double minExitProfit = GetDynamicTrendExitMinProfit();
   for(int i = 0; i < PairSize; i++)
   {
      // -------------------------
      // BUY grid exit
      // -------------------------
      if(Pairs[i].buyGrid.CountPositions() > 0)
      {
         bool trendInvalid = IsBuyTrendInvalidated(i);
         double pnl = Pairs[i].buyGrid.GridPnL();

         if(trendInvalid && pnl > minExitProfit)
         {
            Print("EXIT BUY GRID [TREND INVALID + PROFIT]: ", Pairs[i].symbol,
                  " | Dir: ", DirectionToText(Pairs[i].direction),
                  " | Aligned: ", (Pairs[i].aligned ? "YES" : "NO"),
                  " | GridPnL: ", DoubleToString(pnl, 2),
                  " | Score: ", DoubleToString(Pairs[i].score, 2),
                  " | Cur: ", DoubleToString(Pairs[i].currencyScore, 2));

            Pairs[i].buyGrid.CloseGrid();
            continue;
         }
      }

      // -------------------------
      // SELL grid exit
      // -------------------------
      if(Pairs[i].sellGrid.CountPositions() > 0)
      {
         bool trendInvalid = IsSellTrendInvalidated(i);
         double pnl = Pairs[i].sellGrid.GridPnL();

         if(trendInvalid && pnl > minExitProfit)
         {
            Print("EXIT SELL GRID [TREND INVALID + PROFIT]: ", Pairs[i].symbol,
                  " | Dir: ", DirectionToText(Pairs[i].direction),
                  " | Aligned: ", (Pairs[i].aligned ? "YES" : "NO"),
                  " | GridPnL: ", DoubleToString(pnl, 2),
                  " | Score: ", DoubleToString(Pairs[i].score, 2),
                  " | Cur: ", DoubleToString(Pairs[i].currencyScore, 2));

            Pairs[i].sellGrid.CloseGrid();
            continue;
         }
      }
   }
}

void GetPairCurrencies(string symbol, int &baseIdx, int &quoteIdx)
{
   string base  = StringSubstr(symbol, 0, 3);
   string quote = StringSubstr(symbol, 3, 3);

   baseIdx  = GetCurrencyIndexFast(base);
   quoteIdx = GetCurrencyIndexFast(quote);
}



int GetCurrencyIndexFast(string cur)
{
   StringToUpper(cur);

   if(cur == "USD") return 0;
   if(cur == "EUR") return 1;
   if(cur == "GBP") return 2;
   if(cur == "JPY") return 3;
   if(cur == "CHF") return 4;
   if(cur == "AUD") return 5;
   if(cur == "NZD") return 6;
   if(cur == "CAD") return 7;

   return -1;
}

double GetATRNormalized(string symbol)
{
    double atr[], price[];

    int atrHandle = iATR(symbol, PERIOD_M15, 14);
    if(atrHandle == INVALID_HANDLE) return 1.0;
    
    int copied = CopyBuffer(atrHandle, 0, 1, 1, atr);
    IndicatorRelease(atrHandle);
   
    if(copied < 1) return 1.0;

    if(CopyClose(symbol, PERIOD_M15, 1, 1, price) < 1) return 1.0;
    if(price[0] == 0) return 1.0;

    double atrPct = atr[0] / price[0];
    double norm = atrPct * 1000.0;

    return MathMax(0.5, MathMin(2.0, norm));
}


bool HasCurrencyOverlap(string sym1, string sym2)
{
    string b1 = StringSubstr(sym1,0,3);
    string q1 = StringSubstr(sym1,3,3);

    string b2 = StringSubstr(sym2,0,3);
    string q2 = StringSubstr(sym2,3,3);

    return (b1 == b2 || b1 == q2 || q1 == b2 || q1 == q2);
}

void GetTop2Pairs(int &idx1, int &idx2)
{
    idx1 = -1;
    idx2 = -1;

    // Find best
    for(int i = 0; i < PairSize; i++)
    {
        if(Pairs[i].direction == -1 || !Pairs[i].aligned) continue;

        if(idx1 == -1 || Pairs[i].comp > Pairs[idx1].comp)
            idx1 = i;
    }

    // Find second best with no overlap
    for(int i = 0; i < PairSize; i++)
    {
        if(i == idx1) continue;
        if(Pairs[i].direction == -1 || !Pairs[i].aligned) continue;

        if(idx2 == -1 && !HasCurrencyOverlap(Pairs[i].symbol, Pairs[idx1].symbol))
        {
            idx2 = i;
            continue;
        }

        if(idx2 != -1 &&
           !HasCurrencyOverlap(Pairs[i].symbol, Pairs[idx1].symbol) &&
           Pairs[i].comp > Pairs[idx2].comp)
        {
            idx2 = i;
        }
    }
}

bool HasActiveGrid(PairData &p)
{
    if(p.buyGrid.CountPositions() > 0) return true;
    if(p.sellGrid.CountPositions() > 0) return true;
    return false;
}




void SortCurrencies(double &strength[], int &indices[])
{
    for(int i = 0; i < 8; i++)
        indices[i] = i;

    for(int i = 0; i < 8 - 1; i++)
    {
        for(int j = i + 1; j < 8; j++)
        {
            if(strength[indices[j]] > strength[indices[i]])
            {
                int tmp = indices[i];
                indices[i] = indices[j];
                indices[j] = tmp;
            }
        }
    }
}

void SortPairs(int &indices[])
{
    int total = ArraySize(Pairs);

    for(int i = 0; i < total; i++)
        indices[i] = i;

    for(int i = 0; i < total - 1; i++)
    {
        for(int j = i + 1; j < total; j++)
        {
            if(Pairs[indices[j]].comp > Pairs[indices[i]].comp)
            {
                int tmp = indices[i];
                indices[i] = indices[j];
                indices[j] = tmp;
            }
        }
    }
}




double ToDirectionalScore(double bullScore, int direction)
{
   if(direction == ORDER_TYPE_BUY)
      return bullScore;

   if(direction == ORDER_TYPE_SELL)
      return 10.0 - bullScore;

   return 5.0;
}

double GetDynamicLotSize(double baseLot, double comp)
{
   if(!InpUseDynamicLot)
      return baseLot;

   double denom = MathMax(0.0001, 10.0 - InpMinScore);
   double t = (comp - InpMinScore) / denom;
   t = MathMax(0.0, MathMin(1.0, t));

   double factor = InpMinLotFactor + (InpMaxLotFactor - InpMinLotFactor) * t;
   return baseLot * factor;
}

//---------------------------------------------------------
//---------------------------------------------------------
//---------------------------------------------------------
double GetAccountDDPercent()
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);

   if(balance <= 0.0)
      return 0.0;

   return MathMax(0.0, (balance - equity) / balance * 100.0);
}

//---------------------------------------------------------
double GetMarginPercent()
{
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double margin = AccountInfoDouble(ACCOUNT_MARGIN);

   if(equity <= 0.0)
      return 0.0;

   return (margin / equity) * 100.0;
}

//---------------------------------------------------------
string GetLeverageText()
{
   long lev = AccountInfoInteger(ACCOUNT_LEVERAGE);
   return "1:" + IntegerToString((int)lev);
}

//---------------------------------------------------------
string GetBrokerText()
{
   return AccountInfoString(ACCOUNT_COMPANY);
}

//---------------------------------------------------------
string GetAccountNameText()
{
   return AccountInfoString(ACCOUNT_NAME);
}

//---------------------------------------------------------
int GetHistoryDealCount()
{
   if(!HistorySelect(0, TimeCurrent()))
      return 0;

   return (int)HistoryDealsTotal();
}

//---------------------------------------------------------
void GetTradeStats(double &winRate, double &profitFactor, string &avgHoldText)
{
   winRate = 0.0;
   profitFactor = 0.0;
   avgHoldText = "-";

   if(!HistorySelect(0, TimeCurrent()))
      return;

   int deals = (int)HistoryDealsTotal();
   if(deals <= 0)
      return;

   double grossProfit = 0.0;
   double grossLoss   = 0.0;
   int wins = 0;
   int closedTrades = 0;

   long posIds[];
   datetime entryTimes[];
   ArrayResize(posIds, 0);
   ArrayResize(entryTimes, 0);

   long closePosIds[];
   datetime closeTimes[];
   ArrayResize(closePosIds, 0);
   ArrayResize(closeTimes, 0);

   for(int i = 0; i < deals; i++)
   {
      ulong dealTicket = HistoryDealGetTicket(i);
      if(dealTicket == 0)
         continue;

      long entryType = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
      long dealType  = HistoryDealGetInteger(dealTicket, DEAL_TYPE);
      long posId     = HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);
      datetime dt    = (datetime)HistoryDealGetInteger(dealTicket, DEAL_TIME);

      double profit     = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
      double commission = HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
      double swap       = HistoryDealGetDouble(dealTicket, DEAL_SWAP);
      double net        = profit + commission + swap;

      bool isTradeDeal =
         (dealType == DEAL_TYPE_BUY || dealType == DEAL_TYPE_SELL);

      if(!isTradeDeal)
         continue;

      if(entryType == DEAL_ENTRY_IN)
      {
         int n = ArraySize(posIds);
         ArrayResize(posIds, n + 1);
         ArrayResize(entryTimes, n + 1);
         posIds[n] = posId;
         entryTimes[n] = dt;
      }
      else if(entryType == DEAL_ENTRY_OUT || entryType == DEAL_ENTRY_OUT_BY)
      {
         closedTrades++;

         if(net > 0.0)
         {
            wins++;
            grossProfit += net;
         }
         else if(net < 0.0)
         {
            grossLoss += MathAbs(net);
         }

         int n = ArraySize(closePosIds);
         ArrayResize(closePosIds, n + 1);
         ArrayResize(closeTimes, n + 1);
         closePosIds[n] = posId;
         closeTimes[n] = dt;
      }
   }

   if(closedTrades > 0)
      winRate = 100.0 * (double)wins / (double)closedTrades;

   if(grossLoss > 0.0)
      profitFactor = grossProfit / grossLoss;
   else if(grossProfit > 0.0)
      profitFactor = 999.0;
   else
      profitFactor = 0.0;

   long totalHoldSec = 0;
   int  holdCount = 0;

   for(int i = 0; i < ArraySize(closePosIds); i++)
   {
      long pid = closePosIds[i];
      datetime closeT = closeTimes[i];

      for(int j = ArraySize(posIds) - 1; j >= 0; j--)
      {
         if(posIds[j] == pid)
         {
            if(closeT >= entryTimes[j])
            {
               totalHoldSec += (long)(closeT - entryTimes[j]);
               holdCount++;
            }
            break;
         }
      }
   }

   if(holdCount > 0)
   {
      long avgSec = totalHoldSec / holdCount;
      int hrs = (int)(avgSec / 3600);
      int mins = (int)((avgSec % 3600) / 60);

      if(hrs > 0)
         avgHoldText = IntegerToString(hrs) + "h " + IntegerToString(mins) + "m";
      else
         avgHoldText = IntegerToString(mins) + "m";
   }
}

string PanelName(string suffix)
{
   return PANEL_PREFIX + suffix;
}

//---------------------------------------------------------
void RegisterPanelObject(string name)
{
   int sz = ArraySize(gPanelObjects);
   ArrayResize(gPanelObjects, sz + 1);
   gPanelObjects[sz] = name;
}

//---------------------------------------------------------
bool CreatePanelRect(string name, int x, int y, int w, int h, color bg, color border)
{
   string obj = PanelName(name);
   if(!ObjectCreate(0, obj, OBJ_RECTANGLE_LABEL, 0, 0, 0))
      return false;

   ObjectSetInteger(0, obj, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, obj, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, obj, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, obj, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, obj, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, obj, OBJPROP_COLOR, bg);
   ObjectSetInteger(0, obj, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, obj, OBJPROP_BORDER_COLOR, border);
   ObjectSetInteger(0, obj, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, obj, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, obj, OBJPROP_BACK, false);
   ObjectSetInteger(0, obj, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, obj, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, obj, OBJPROP_HIDDEN, false);

   RegisterPanelObject(obj);
   return true;
}

//---------------------------------------------------------
bool CreatePanelLabel(string name, int x, int y, int fontSize, color clr,
                      string text, ENUM_ANCHOR_POINT anchor = ANCHOR_LEFT_UPPER)
{
   string obj = PanelName(name);
   if(!ObjectCreate(0, obj, OBJ_LABEL, 0, 0, 0))
      return false;

   ObjectSetInteger(0, obj, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, obj, OBJPROP_ANCHOR, anchor);
   ObjectSetInteger(0, obj, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, obj, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, obj, OBJPROP_FONTSIZE, fontSize);
   ObjectSetString(0, obj, OBJPROP_FONT, "Consolas");
   ObjectSetInteger(0, obj, OBJPROP_COLOR, clr);
   ObjectSetString(0, obj, OBJPROP_TEXT, text);
   ObjectSetInteger(0, obj, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, obj, OBJPROP_HIDDEN, false);

   RegisterPanelObject(obj);
   return true;
}

//---------------------------------------------------------
void SetPanelText(string name, string text, color clr = clrNONE)
{
   string obj = PanelName(name);
   if(ObjectFind(0, obj) < 0)
      return;

   string oldText = ObjectGetString(0, obj, OBJPROP_TEXT);
   if(oldText != text)
      ObjectSetString(0, obj, OBJPROP_TEXT, text);

   if(clr != clrNONE)
   {
      color oldClr = (color)ObjectGetInteger(0, obj, OBJPROP_COLOR);
      if(oldClr != clr)
         ObjectSetInteger(0, obj, OBJPROP_COLOR, clr);
   }
}

//---------------------------------------------------------
bool IsPairEligibleNow(int idx)
{
   if(idx < 0 || idx >= PairSize)
      return false;

   if(!Pairs[idx].structurallyValid)
      return false;

   if(!Pairs[idx].filtersValid)
      return false;

   if(Pairs[idx].direction == ORDER_TYPE_BUY)
   {
      if(Pairs[idx].buyGrid.CountPositions() > 0)
         return false;

      if(!CanOpenGrid(Pairs[idx].symbol, true))
         return false;

      return true;
   }

   if(Pairs[idx].direction == ORDER_TYPE_SELL)
   {
      if(Pairs[idx].sellGrid.CountPositions() > 0)
         return false;

      if(!CanOpenGrid(Pairs[idx].symbol, false))
         return false;

      return true;
   }

   return false;
}

//---------------------------------------------------------
string DirectionToText(int dir)
{
   if(dir == ORDER_TYPE_BUY)  return "BUY ";
   if(dir == ORDER_TYPE_SELL) return "SELL";
   return "----";
}

//---------------------------------------------------------
color DirectionToColor(int dir)
{
   if(dir == ORDER_TYPE_BUY)  return tmdGreen;
   if(dir == ORDER_TYPE_SELL) return tmdRed;
   return tmdSilver;
}

//---------------------------------------------------------
string PairStateText(int idx)
{
   if(HasActiveGrid(Pairs[idx]))
      return "LIVE";

   if(IsPairEligibleNow(idx))
      return "READY";

   return "WAIT";
}

//---------------------------------------------------------
color PairStateColor(int idx)
{
   if(HasActiveGrid(Pairs[idx]))
      return C'0,230,230';

   if(IsPairEligibleNow(idx))
      return tmdGreen;

   if(Pairs[idx].direction == -1 || !Pairs[idx].aligned)
      return tmdOrange;

   return tmdSilver;
}

//---------------------------------------------------------
color PairDotColor(int idx)
{
   if(HasActiveGrid(Pairs[idx]))
      return C'0,230,230';   // cyan

   if(IsPairEligibleNow(idx))
      return tmdGreen;

   if(Pairs[idx].direction == -1)
      return tmdSilver;

   if(!Pairs[idx].aligned)
      return tmdOrange;

   return tmdRed;
}

//---------------------------------------------------------
int GetPairOpenOrderCount(PairData &p)
{
   return p.buyGrid.CountPositions() + p.sellGrid.CountPositions();
}

//---------------------------------------------------------
double GetPairGridPnL(PairData &p)
{
   return p.buyGrid.GridPnL() + p.sellGrid.GridPnL();
}

//---------------------------------------------------------
void GetSortedCurrencyIndices(double &strengths[], int &idx[])
{
   ArrayResize(idx, 8);
   for(int i = 0; i < 8; i++)
      idx[i] = i;

   for(int i = 0; i < 7; i++)
   {
      for(int j = i + 1; j < 8; j++)
      {
         if(strengths[idx[j]] > strengths[idx[i]])
         {
            int tmp = idx[i];
            idx[i] = idx[j];
            idx[j] = tmp;
         }
      }
   }
}
string GetServerTimeText()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);

   string hh = (dt.hour < 10 ? "0" : "") + IntegerToString(dt.hour);
   string mm = (dt.min  < 10 ? "0" : "") + IntegerToString(dt.min);
   string ss = (dt.sec  < 10 ? "0" : "") + IntegerToString(dt.sec);

   return hh + ":" + mm + ":" + ss;
}
//---------------------------------------------------------
void CreateTMDInfoPanel()
{
   if (!InpShowPanel) {
      return;
   }
   ArrayResize(gPanelObjects, 0);

   // Panel geometry
   int bgX = 20;
   int bgY = 30;
   int bgW = 900;
   int bgH = 720;

   CreatePanelRect("BG", bgX, bgY, bgW, bgH, C'10,16,28', C'10,16,28');
   CreatePanelRect("TB", 23, 33, bgW - 6, 28, C'10,16,28', C'10,16,28');

   // Separators
   CreatePanelRect("S1", 30, 65, 880, 1, C'25,40,55', tmdBg);
   CreatePanelRect("S2", 30, 130, 880, 1, C'25,40,55', tmdBg);
   CreatePanelRect("S3", 30, 286, 880, 1, C'25,40,55', tmdBg);

   // Currency section vertical separators
   CreatePanelRect("SV1", 280, 150, 1, 128, C'25,40,55', tmdBg); // after strengths
   CreatePanelRect("SV2", 470, 150, 1, 128, C'25,40,55', tmdBg); // after stats block
   CreatePanelRect("SV3", 640, 150, 1, 128, C'25,40,55', tmdBg); // before risk block

   // Header
   CreatePanelLabel("ONLINE_DOT", 30, 40, 9, C'0,230,120', "●");
   CreatePanelLabel("ONLINE_TXT", 42, 41, 9, C'0,180,180', "ONLINE");
   CreatePanelLabel("SERVER_TXT", 100, 41, 9, tmdSilver, "--:--:--");
   CreatePanelLabel("TITLE", 470, 38, 11, C'0,230,230', "◆ T M D ◆", ANCHOR_UPPER);

   // Left stats block
   CreatePanelLabel("L1", 30, 72, 9, C'70,90,110', "BALANCE");
   CreatePanelLabel("V1", 185, 72, 9, tmdSilver, "-", ANCHOR_RIGHT_UPPER);

   CreatePanelLabel("L2", 30, 90, 9, C'70,90,110', "EQUITY");
   CreatePanelLabel("V2", 185, 90, 9, tmdSilver, "-", ANCHOR_RIGHT_UPPER);

   CreatePanelLabel("L3", 30, 108, 9, C'70,90,110', "P / L");
   CreatePanelLabel("V3", 185, 108, 9, tmdSilver, "-", ANCHOR_RIGHT_UPPER);

   // Middle stats block
   CreatePanelLabel("L4", 230, 72, 9, C'70,90,110', "ACCOUNT");
   CreatePanelLabel("V4", 515, 72, 9, tmdSilver, "-", ANCHOR_RIGHT_UPPER);

   CreatePanelLabel("L5", 230, 90, 9, C'70,90,110', "BROKER");
   CreatePanelLabel("V5", 515, 90, 9, tmdSilver, "-", ANCHOR_RIGHT_UPPER);

   CreatePanelLabel("L6", 230, 108, 9, C'70,90,110', "LEVERAGE");
   CreatePanelLabel("V6", 515, 108, 9, tmdSilver, "-", ANCHOR_RIGHT_UPPER);

   // Right stats block
   CreatePanelLabel("L7", 560, 72, 9, C'70,90,110', "DD");
   CreatePanelLabel("V7", 760, 72, 9, tmdSilver, "-", ANCHOR_RIGHT_UPPER);

   CreatePanelLabel("L8", 560, 90, 9, C'70,90,110', "FREE MARGIN");
   CreatePanelLabel("V8", 760, 90, 9, tmdSilver, "-", ANCHOR_RIGHT_UPPER);

   CreatePanelLabel("L9", 560, 108, 9, C'70,90,110', "MARGIN %");
   CreatePanelLabel("V9", 760, 108, 9, tmdSilver, "-", ANCHOR_RIGHT_UPPER);

   // Currency header
   CreatePanelLabel("CUR_HDR", 30, 138, 9, C'180,40,220', "CURRENCIES");
   CreatePanelLabel("CUR_HDR2", 210, 138, 8, C'70,90,110', "STRENGTH", ANCHOR_RIGHT_UPPER);

   // Middle block in currency section: stats
   CreatePanelLabel("CURM_L1", 300, 138, 8, C'70,90,110', "WIN RATE");
   CreatePanelLabel("CURM_V1", 455, 138, 8, tmdSilver, "-", ANCHOR_RIGHT_UPPER);

   CreatePanelLabel("CURM_L2", 300, 153, 8, C'70,90,110', "PROFIT FACTOR");
   CreatePanelLabel("CURM_V2", 455, 153, 8, tmdSilver, "-", ANCHOR_RIGHT_UPPER);

   CreatePanelLabel("CURM_L3", 300, 168, 8, C'70,90,110', "AVG HOLD");
   CreatePanelLabel("CURM_V3", 455, 168, 8, tmdSilver, "-", ANCHOR_RIGHT_UPPER);

   CreatePanelLabel("CURM_L4", 300, 183, 8, C'70,90,110', "OPEN ORDERS");
   CreatePanelLabel("CURM_V4", 455, 183, 8, tmdSilver, "-", ANCHOR_RIGHT_UPPER);
   
   CreatePanelLabel("CURM_L6", 300, 198, 8, C'70,90,110', "MAX TOTAL ORDERS");
   CreatePanelLabel("CURM_V6", 455, 198, 8, tmdSilver, "-", ANCHOR_RIGHT_UPPER);

   CreatePanelLabel("CURM_L5", 300, 213, 8, C'70,90,110', "OPEN LOTS");
   CreatePanelLabel("CURM_V5", 455, 213, 8, tmdSilver, "-", ANCHOR_RIGHT_UPPER);
   
   CreatePanelLabel("CURM_L7", 300, 228, 8, C'70,90,110', "MAX LOTS DYN");
   CreatePanelLabel("CURM_V7", 455, 228, 8, tmdSilver, "-", ANCHOR_RIGHT_UPPER);

   // Right block in currency section: EA inputs
   CreatePanelLabel("CFG_L1", 490, 138, 8, C'70,90,110', "MIN COMP");
   CreatePanelLabel("CFG_V1", 620, 138, 8, tmdSilver, "-", ANCHOR_RIGHT_UPPER);

   CreatePanelLabel("CFG_L2", 490, 153, 8, C'70,90,110', "BUY RSI");
   CreatePanelLabel("CFG_V2", 620, 153, 8, tmdSilver, "-", ANCHOR_RIGHT_UPPER);

   CreatePanelLabel("CFG_L3", 490, 168, 8, C'70,90,110', "SELL RSI");
   CreatePanelLabel("CFG_V3", 620, 168, 8, tmdSilver, "-", ANCHOR_RIGHT_UPPER);

   CreatePanelLabel("CFG_L4", 490, 183, 8, C'70,90,110', "PROFIT %");
   CreatePanelLabel("CFG_V4", 620, 183, 8, tmdSilver, "-", ANCHOR_RIGHT_UPPER);

   CreatePanelLabel("CFG_L5", 490, 198, 8, C'70,90,110', "MAX DD");
   CreatePanelLabel("CFG_V5", 620, 198, 8, tmdSilver, "-", ANCHOR_RIGHT_UPPER);

   CreatePanelLabel("CFG_L6", 660, 138, 8, C'70,90,110', "MAX GRID ORDERS");
   CreatePanelLabel("CFG_V6", 840, 138, 8, tmdSilver, "-", ANCHOR_RIGHT_UPPER);

   CreatePanelLabel("CFG_L7", 660, 153, 8, C'70,90,110', "LOT MODE");
   CreatePanelLabel("CFG_V7", 840, 153, 8, tmdSilver, "-", ANCHOR_RIGHT_UPPER);
   
   CreatePanelLabel("CFG_L8", 660, 168, 8, C'70,90,110', "LOT BALANCE");
   CreatePanelLabel("CFG_V8", 840, 168, 8, tmdSilver, "-", ANCHOR_RIGHT_UPPER);
   
   CreatePanelLabel("RISK_L1", 660, 213, 8, C'70,90,110', "RISK STATE");
   CreatePanelLabel("RISK_V1", 840, 213, 8, tmdSilver, "-", ANCHOR_RIGHT_UPPER);

   CreatePanelLabel("RISK_L2", 660, 228, 8, C'70,90,110', "NEW ENTRIES");
   CreatePanelLabel("RISK_V2", 840, 228, 8, tmdSilver, "-", ANCHOR_RIGHT_UPPER);

   CreatePanelLabel("RISK_L3", 660, 243, 8, C'70,90,110', "GRID EXPAND");
   CreatePanelLabel("RISK_V3", 840, 243, 8, tmdSilver, "-", ANCHOR_RIGHT_UPPER);

   CreatePanelLabel("RISK_L4", 660, 258, 8, C'70,90,110', "RISK REASON");
   CreatePanelLabel("RISK_V4", 840, 258, 8, tmdSilver, "-", ANCHOR_RIGHT_UPPER);

   for(int i = 0; i < PANEL_CUR_ROWS; i++)
   {
      int y = 158 + i * 15;
      CreatePanelLabel("CUR_L_" + IntegerToString(i), 30,  y, 9, tmdSilver, "-");
      CreatePanelLabel("CUR_V_" + IntegerToString(i), 210, y, 9, tmdSilver, "-", ANCHOR_RIGHT_UPPER);
   }

   // Symbol header
   CreatePanelLabel("SYM_HDR", 30, 294, 9, C'0,230,230', "Symbols");
   //CreatePanelLabel("SYM_COL0", 42,  294, 8, C'70,90,110', "");
   CreatePanelLabel("SYM_COL1", 255, 294, 8, C'70,90,110', "COMP", ANCHOR_RIGHT_UPPER);
   CreatePanelLabel("SYM_COL2", 315, 294, 8, C'70,90,110', "SCORE", ANCHOR_RIGHT_UPPER);
   CreatePanelLabel("SYM_COL3", 375, 294, 8, C'70,90,110', "ACC", ANCHOR_RIGHT_UPPER);
   CreatePanelLabel("SYM_COL8", 445, 294, 8, C'70,90,110', "RSI", ANCHOR_RIGHT_UPPER);
   CreatePanelLabel("SYM_COL6", 500, 294, 8, C'70,90,110', "FLT");
   CreatePanelLabel("SYM_COL9", 575, 294, 8, C'70,90,110', "STATE");
   CreatePanelLabel("SYM_COL4", 665, 294, 8, C'70,90,110', "ORD", ANCHOR_RIGHT_UPPER);
   CreatePanelLabel("SYM_COL7", 735, 294, 8, C'70,90,110', "LOTS", ANCHOR_RIGHT_UPPER);
   CreatePanelLabel("SYM_COL5", 820, 294, 8, C'70,90,110', "P/L", ANCHOR_RIGHT_UPPER);

   for(int i = 0; i < PANEL_SYM_ROWS; i++)
   {
      int y = 314 + i * 14;

      CreatePanelLabel("SYM_DOT_" + IntegerToString(i), 30,  y, 8, tmdSilver, "●");
      CreatePanelLabel("SYM_A_"   + IntegerToString(i), 42,  y, 8, tmdSilver, "-");

      CreatePanelLabel("SYM_B_"   + IntegerToString(i), 255, y, 8, tmdSilver, "-", ANCHOR_RIGHT_UPPER);
      CreatePanelLabel("SYM_C_"   + IntegerToString(i), 315, y, 8, tmdSilver, "-", ANCHOR_RIGHT_UPPER);
      CreatePanelLabel("SYM_D_"   + IntegerToString(i), 375, y, 8, tmdSilver, "-", ANCHOR_RIGHT_UPPER);
      CreatePanelLabel("SYM_I_"   + IntegerToString(i), 445, y, 8, tmdSilver, "-", ANCHOR_RIGHT_UPPER);
      CreatePanelLabel("SYM_G_"   + IntegerToString(i), 500, y, 8, tmdSilver, "-");
      CreatePanelLabel("SYM_J_"   + IntegerToString(i), 575, y, 8, tmdSilver, "-");
      CreatePanelLabel("SYM_E_"   + IntegerToString(i), 665, y, 8, tmdSilver, "-", ANCHOR_RIGHT_UPPER);
      CreatePanelLabel("SYM_H_"   + IntegerToString(i), 735, y, 8, tmdSilver, "-", ANCHOR_RIGHT_UPPER);
      CreatePanelLabel("SYM_F_"   + IntegerToString(i), 820, y, 8, tmdSilver, "-", ANCHOR_RIGHT_UPPER);
      

      
   }

   ChartRedraw();
}


//---------------------------------------------------------
void UpdateTMDInfoPanel()
{
   if(!InpShowPanel)
      return;


   bool eaOnline = IsEAOnline();

   SetPanelText("ONLINE_DOT", "●", eaOnline ? C'0,230,120' : tmdRed);
   SetPanelText("ONLINE_TXT", eaOnline ? "ONLINE" : "OFFLINE",
                eaOnline ? C'0,180,180' : tmdRed);
   SetPanelText("SERVER_TXT", GetServerTimeText(), tmdSilver);
   
   
      // ---------------------------
   // Top stats
   // ---------------------------
   double balance    = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity     = AccountInfoDouble(ACCOUNT_EQUITY);
   double profit     = AccountInfoDouble(ACCOUNT_PROFIT);
   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double ddPct      = GetAccountDDPercent();
   double marginPct  = GetMarginLevelPercent();

   SetPanelText("V1", DoubleToString(balance, 2), tmdSilver);
   SetPanelText("V2", DoubleToString(equity, 2), tmdSilver);

   color pnlColor = tmdSilver;
   if(profit > 0.0) pnlColor = tmdGreen;
   else if(profit < 0.0) pnlColor = tmdRed;
   SetPanelText("V3", DoubleToString(profit, 2), pnlColor);

   SetPanelText("V4", GetAccountNameText(), tmdSilver);
   SetPanelText("V5", GetBrokerText(), tmdSilver);
   SetPanelText("V6", GetLeverageText(), C'0,190,190');

   color ddClr = tmdGreen;
   if(ddPct >= 10.0) ddClr = tmdOrange;
   if(ddPct >= 20.0) ddClr = tmdRed;
   SetPanelText("V7", DoubleToString(ddPct, 2) + "%", ddClr);

   SetPanelText("V8", DoubleToString(freeMargin, 2), tmdSilver);

   color margClr = GetFreeMarginColor(marginPct);
   SetPanelText("V9", DoubleToString(marginPct, 2) + "%", margClr);
   
   

   // ---------------------------
   // Trade stats
   // ---------------------------
   double winRate = 0.0;
   double profitFactor = 0.0;
   string avgHoldText = "-";
   GetTradeStats(winRate, profitFactor, avgHoldText);

   int totalOpenOrders = PositionsTotal();
   double totalOpenLots = 0.0;

   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;

      if(!PositionSelectByTicket(ticket))
         continue;

      totalOpenLots += PositionGetDouble(POSITION_VOLUME);
   }

   color wrClr = tmdSilver;
   if(winRate >= 55.0) wrClr = tmdGreen;
   else if(winRate < 45.0) wrClr = tmdOrange;

   color pfClr = tmdSilver;
   if(profitFactor >= 1.5) pfClr = tmdGreen;
   else if(profitFactor < 1.0) pfClr = tmdRed;
   else pfClr = tmdOrange;

   color ordClr = (totalOpenOrders > 0 ? C'0,230,230' : tmdSilver);
   color lotClr = (totalOpenLots > 0.0 ? C'0,230,230' : tmdSilver);
   color lotUsageClr = GetLotUsageColor(totalOpenLots);
   color ordUsageClr = GetPositionUsageColor(totalOpenOrders);

   SetPanelText("CURM_V1", DoubleToString(winRate, 1) + "%", wrClr);
   SetPanelText("CURM_V2", DoubleToString(profitFactor, 2), pfClr);
   SetPanelText("CURM_V3", avgHoldText, C'0,190,190');
   SetPanelText("CURM_V4", IntegerToString(totalOpenOrders), ordUsageClr);
   SetPanelText("CURM_V5", DoubleToString(totalOpenLots, 2), lotUsageClr);
   SetPanelText("CURM_V6", IntegerToString(InpMaxTotalPositions), ordUsageClr);
   double dynMaxLots = GetDynamicMaxTotalLots();
SetPanelText("CURM_V7", DoubleToString(dynMaxLots, 2), lotUsageClr);

   // ---------------------------
   // Config block
   // ---------------------------
   SetPanelText("CFG_V1", DoubleToString(InpMinScore, 1), tmdSilver);
   SetPanelText("CFG_V2", DoubleToString(InpBuyRsi, 1), tmdSilver);
   SetPanelText("CFG_V3", DoubleToString(InpSellRsi, 1), tmdSilver);
   SetPanelText("CFG_V4", DoubleToString(InpProfitPercent, 2) + "%", tmdSilver);
   SetPanelText("CFG_V5", DoubleToString(InpMaxDD, 1) + "%", tmdSilver);
   SetPanelText("CFG_V6", IntegerToString(InpMaxOrders), tmdSilver);
string lotMode = "FIXED";
if(InpUseAutoLot && InpUseDynamicLot)      lotMode = "AUTO+DYN";
else if(InpUseAutoLot)                     lotMode = "AUTO";
else if(InpUseDynamicLot)                  lotMode = "FIXED+DYN";

SetPanelText("CFG_V7", lotMode, tmdSilver);
   SetPanelText("CFG_V8", DoubleToString(InpBalancePerLot,0), tmdSilver);
   
   SetPanelText("RISK_V1", gRiskStateText,   gRiskStateColor);
   SetPanelText("RISK_V2", gEntryStateText,  gEntryStateColor);
   SetPanelText("RISK_V3", gExpandStateText, gExpandStateColor);
   SetPanelText("RISK_V4", gRiskReasonText,  gRiskReasonColor);
   
      // ---------------------------
   // Cache visual states once
   // ---------------------------
   for(int i = 0; i < PairSize; i++)
      RefreshPairVisualState(i);
      
   // ---------------------------
   // Currency strengths
   // ---------------------------

   int curIdx[];
   GetSortedCurrencyIndices(currencyStrength, curIdx);

   for(int i = 0; i < PANEL_CUR_ROWS; i++)
   {
      if(i < ArraySize(curIdx))
      {
         int idx = curIdx[i];
         double val = currencyStrength[idx];

         color c = tmdSilver;
         if(val > 0.5) c = tmdGreen;
         else if(val < -0.5) c = tmdRed;
         else c = tmdOrange;

         string leftText  = IntegerToString(i + 1) + ". " + Currencies[idx];
         string rightText = DoubleToString(val, 2);

         SetPanelText("CUR_L_" + IntegerToString(i), leftText, c);
         SetPanelText("CUR_V_" + IntegerToString(i), rightText, c);
      }
      else
      {
         SetPanelText("CUR_L_" + IntegerToString(i), "-", tmdSilver);
         SetPanelText("CUR_V_" + IntegerToString(i), "-", tmdSilver);
      }
   }



   // ---------------------------
   // Symbols
   // ---------------------------
   for(int i = 0; i < PANEL_SYM_ROWS; i++)
   {
      if(i < PairSize)
      {
                  string dirTxt = DirectionToText(Pairs[i].direction);
         color dirClr  = DirectionToColor(Pairs[i].direction);

         string stateTxt = Pairs[i].stateText;
         color stateClr  = Pairs[i].stateColor;
         color dotClr    = Pairs[i].dotColor;

         int openOrders  = Pairs[i].openCount;
         double openLots = Pairs[i].openLots;
         double gridPnl  = GetPairGridPnL(Pairs[i]);

         color pnlClr = tmdSilver;
         if(gridPnl > 0.0) pnlClr = tmdGreen;
         else if(gridPnl < 0.0) pnlClr = tmdRed;

         string pairText = Pairs[i].symbol + " " + dirTxt;
         string filterTxt = PairFilterText(i);
         color filterClr = PairFilterColor(i);
         
         if(Pairs[i].buyGrid.CountPositions() > 0 && IsPairExpansionFrozen(i, true))
         {
            filterTxt = "EXP OFF";
            filterClr = tmdOrange;
         }
         else if(Pairs[i].sellGrid.CountPositions() > 0 && IsPairExpansionFrozen(i, false))
         {
            filterTxt = "EXP OFF";
            filterClr = tmdOrange;
         }

         color rsiClr = tmdSilver;
         if(Pairs[i].filtersValid)
         {
            if(Pairs[i].direction == ORDER_TYPE_BUY)
               rsiClr = Pairs[i].rsiBuyOk ? tmdGreen : tmdOrange;
            else if(Pairs[i].direction == ORDER_TYPE_SELL)
               rsiClr = Pairs[i].rsiSellOk ? tmdGreen : tmdOrange;
         }

         SetPanelText("SYM_DOT_" + IntegerToString(i), "●", dotClr);
         SetPanelText("SYM_A_"   + IntegerToString(i), pairText, dirClr);

         SetPanelText("SYM_B_" + IntegerToString(i),
                      DoubleToString(Pairs[i].comp, 1),
                      (Pairs[i].comp >= InpMinScore ? tmdGreen : tmdOrange));

         SetPanelText("SYM_C_" + IntegerToString(i),
                      DoubleToString(Pairs[i].score, 1),
                      (Pairs[i].score >= 6.0 ? C'0,190,190' : tmdSilver));

         SetPanelText("SYM_D_" + IntegerToString(i),
                      DoubleToString(Pairs[i].accel, 1),
                      (Pairs[i].accel >= 5.5 ? tmdGreen : (Pairs[i].accel <= 4.5 ? tmdOrange : tmdSilver)));

         SetPanelText("SYM_I_" + IntegerToString(i),
                      (Pairs[i].filtersValid ? DoubleToString(Pairs[i].rsiM1, 1) : "-"),
                      rsiClr);

         SetPanelText("SYM_G_" + IntegerToString(i), filterTxt, filterClr);
         SetPanelText("SYM_J_" + IntegerToString(i), stateTxt, stateClr);

         SetPanelText("SYM_E_" + IntegerToString(i),
                      IntegerToString(openOrders),
                      (openOrders > 0 ? C'0,230,230' : tmdSilver));

         SetPanelText("SYM_H_" + IntegerToString(i),
                      DoubleToString(openLots, 2),
                      (openLots > 0.0 ? C'0,230,230' : tmdSilver));

         SetPanelText("SYM_F_" + IntegerToString(i),
                      DoubleToString(gridPnl, 2),
                      pnlClr);
      }
      else
      {
         SetPanelText("SYM_DOT_" + IntegerToString(i), "●", tmdSilver);
         SetPanelText("SYM_A_"   + IntegerToString(i), "-", tmdSilver);
         SetPanelText("SYM_B_"   + IntegerToString(i), "-", tmdSilver);
         SetPanelText("SYM_C_"   + IntegerToString(i), "-", tmdSilver);
         SetPanelText("SYM_D_"   + IntegerToString(i), "-", tmdSilver);
         SetPanelText("SYM_I_"   + IntegerToString(i), "-", tmdSilver);
         SetPanelText("SYM_G_"   + IntegerToString(i), "-", tmdSilver);
         SetPanelText("SYM_J_"   + IntegerToString(i), "-", tmdSilver);
         SetPanelText("SYM_E_"   + IntegerToString(i), "-", tmdSilver);
         SetPanelText("SYM_H_"   + IntegerToString(i), "-", tmdSilver);
         SetPanelText("SYM_F_"   + IntegerToString(i), "-", tmdSilver);
      }
   }

   ChartRedraw();
}
//---------------------------------------------------------
void DeleteTMDInfoPanel()
{
   for(int i = 0; i < ArraySize(gPanelObjects); i++)
      ObjectDelete(0, gPanelObjects[i]);

   ArrayResize(gPanelObjects, 0);
   ChartRedraw();
}

bool IsEAOnline()
{
   bool terminalTrade = (bool)TerminalInfoInteger(TERMINAL_TRADE_ALLOWED);
   bool programTrade  = (bool)MQLInfoInteger(MQL_TRADE_ALLOWED);

   return (terminalTrade && programTrade);
}

double GetFreeMarginPercent()
{
   double equity     = AccountInfoDouble(ACCOUNT_EQUITY);
   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);

   if(equity <= 0.0)
      return 0.0;

   return (freeMargin / equity) * 100.0;
}
double GetMarginLevelPercent()
{
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double margin = AccountInfoDouble(ACCOUNT_MARGIN);

   if(margin <= 0.0)
      return 0.0; // or EMPTY_VALUE if you prefer

   return (equity / margin) * 100.0;
}

color GetFreeMarginColor(double freeMarginPct)
{
   int stopoutMode = (int)AccountInfoInteger(ACCOUNT_MARGIN_SO_MODE);
   double stopoutCall = AccountInfoDouble(ACCOUNT_MARGIN_SO_CALL);
   double stopoutSo   = AccountInfoDouble(ACCOUNT_MARGIN_SO_SO);

   // Fallback if broker does not provide usable values
   if(stopoutCall <= 0.0 && stopoutSo <= 0.0)
   {
      if(freeMarginPct < 25.0) return tmdRed;
      if(freeMarginPct < 50.0) return tmdOrange;
      return tmdGreen;
   }

   // Percent mode: values are already percentages
   if(stopoutMode == ACCOUNT_STOPOUT_MODE_PERCENT)
   {
      double danger = stopoutSo;
      double warn   = MathMax(stopoutCall, danger * 1.5);

      if(freeMarginPct <= warn)
         return tmdRed;

      if(freeMarginPct <= warn * 1.5)
         return tmdOrange;

      return tmdGreen;
   }

   // Money mode: broker levels are in account currency, not percent.
   // Convert them approximately to free-margin percent of equity.
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity <= 0.0)
      return tmdRed;

   double dangerPct = (stopoutSo   / equity) * 100.0;
   double warnPct   = (stopoutCall / equity) * 100.0;

   if(warnPct <= 0.0)
      warnPct = dangerPct * 1.5;

   if(freeMarginPct <= warnPct)
      return tmdRed;

   if(freeMarginPct <= warnPct * 1.5)
      return tmdOrange;

   return tmdGreen;
}
double GetPairOpenLots(const PairData &p)
{
   double lots = 0.0;

   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;

      if(!PositionSelectByTicket(ticket))
         continue;

      string sym = PositionGetString(POSITION_SYMBOL);
      if(sym != p.symbol)
         continue;

      lots += PositionGetDouble(POSITION_VOLUME);
   }

   return lots;
}


void RefreshPairVisualState(int idx)
{
   if(idx < 0 || idx >= PairSize)
      return;

   bool hasLive = HasActiveGrid(Pairs[idx]);
   bool eligible = false;

   if(!hasLive)
      eligible = IsPairEligibleNow(idx);

   Pairs[idx].eligibleNow = eligible;

   if(hasLive)
   {
      Pairs[idx].stateText  = "LIVE";
      Pairs[idx].stateColor = C'0,230,230';
      Pairs[idx].dotColor   = C'0,230,230';
      if (Pairs[idx].buyGrid.CountPositions() > 0 ) {
         Pairs[idx].stateText  = "BUY";
      }
      if (Pairs[idx].sellGrid.CountPositions() > 0 ) {
         Pairs[idx].stateText  = "SELL";
         Pairs[idx].stateColor = C'180,40,220';
         Pairs[idx].dotColor   = C'180,40,220';
      }
      
      return;
   }

   if(eligible)
   {
      Pairs[idx].stateText  = "READY";
      Pairs[idx].stateColor = tmdGreen;
      Pairs[idx].dotColor   = tmdGreen;
      return;
   }

   Pairs[idx].stateText = "WAIT";

   if(Pairs[idx].direction == -1 || !Pairs[idx].aligned)
   {
      Pairs[idx].stateColor = tmdOrange;
      Pairs[idx].dotColor   = (Pairs[idx].direction == -1 ? tmdSilver : tmdOrange);
   }
   else
   {
      Pairs[idx].stateColor = tmdSilver;
      Pairs[idx].dotColor   = tmdRed;
   }
}

void HandleTMDPanelChartClick(int x, int y)
{
   if(!InpShowPanel)
      return;

   int tableX1   = 28;
   int tableX2   = 830;
   int firstRowY = 313;
   int rowH      = 14;

   if(x < tableX1 || x > tableX2)
      return;

   if(y < firstRowY)
      return;

   int row = (y - firstRowY) / rowH;

   if(row < 0 || row >= PANEL_SYM_ROWS)
      return;

   if(row >= PairSize)
      return;

   string sym = Pairs[row].symbol;
   if(sym == "")
      return;

   if(Symbol() != sym)
      ChartSetSymbolPeriod(0, sym, (ENUM_TIMEFRAMES)Period());
}

void RefreshPairFilterCache(int idx)
{
   if(idx < 0 || idx >= PairSize)
      return;

   InvalidatePairFilterCache(idx);

   MqlRates bar1, bar2;
   if(!GetLastClosedM5(Pairs[idx].symbol, bar1, bar2))
      return;

   double rsiBuf[];
   ArraySetAsSeries(rsiBuf, true);

   if(CopyBuffer(Pairs[idx].rsiM1Handle, 0, 1, 2, rsiBuf) < 2)
      return;

   Pairs[idx].rsiM1 = rsiBuf[0]; // last closed M5 RSI

   if(InpUseBB)
   {
      double bbUpper[], bbLower[];
      ArraySetAsSeries(bbUpper, true);
      ArraySetAsSeries(bbLower, true);

      if(CopyBuffer(Pairs[idx].bbM1Handle, 1, 1, 2, bbUpper) < 2)
         return;
      if(CopyBuffer(Pairs[idx].bbM1Handle, 2, 1, 2, bbLower) < 2)
         return;

      Pairs[idx].bbUpperM1 = bbUpper[0];
      Pairs[idx].bbLowerM1 = bbLower[0];

      // informational state only
      Pairs[idx].bbBuyOk  = (bar2.close < bbLower[1]); // previous candle was outside lower band
      Pairs[idx].bbSellOk = (bar2.close > bbUpper[1]); // previous candle was outside upper band
   }
   else
   {
      Pairs[idx].bbUpperM1 = 0.0;
      Pairs[idx].bbLowerM1 = 0.0;
      Pairs[idx].bbBuyOk   = true;
      Pairs[idx].bbSellOk  = true;
   }

   // informational state only
   Pairs[idx].rsiBuyOk  = (rsiBuf[1] < InpBuyRsi && rsiBuf[0] > rsiBuf[1]);
   Pairs[idx].rsiSellOk = (rsiBuf[1] > InpSellRsi && rsiBuf[0] < rsiBuf[1]);

   Pairs[idx].filtersValid = true;
}

void RefreshAllPairFilterCaches()
{
   for(int i = 0; i < PairSize; i++)
   {
      bool hasLive = HasActiveGrid(Pairs[i]);
      bool structural = IsPairStructurallyValid(i);

      Pairs[i].structurallyValid  = structural;
      Pairs[i].needsFilterRefresh = (structural || hasLive);

      if(Pairs[i].needsFilterRefresh)
         RefreshPairFilterCache(i);
      else
         InvalidatePairFilterCache(i);
   }
}

bool IsPairStructurallyValid(int idx)
{
   if(idx < 0 || idx >= PairSize)
      return false;

   if(!brokerWindowOpen)
      return false;

   if(!Pairs[idx].marketOpen)
      return false;
   
   if(Pairs[idx].direction == -1)
      return false;

   if(!Pairs[idx].aligned)
      return false;

   if(Pairs[idx].comp < InpMinScore)
      return false;
      
   if(Pairs[idx].accel < InpMinAccel)
      return false;
      
   if(InpUseRiskProtection)
   {
      if(gEmergencyClose || gFreezeNewEntries)
         return false;

      if(IsExposureTooHigh())
         return false;

      if(!SpreadAcceptable(Pairs[idx].symbol, InpMaxSpreadPoints))
         return false;
   }

   return true;
}

void InvalidatePairFilterCache(int idx)
{
   if(idx < 0 || idx >= PairSize)
      return;

   Pairs[idx].filtersValid = false;
   Pairs[idx].rsiM1        = 0.0;
   Pairs[idx].bbUpperM1    = 0.0;
   Pairs[idx].bbLowerM1    = 0.0;
   Pairs[idx].rsiBuyOk     = false;
   Pairs[idx].rsiSellOk    = false;
   Pairs[idx].bbBuyOk      = false;
   Pairs[idx].bbSellOk     = false;
}

string PairFilterText(int idx)
{
   if(idx < 0 || idx >= PairSize)
      return "-";

   if(!Pairs[idx].structurallyValid)
      return "N/A";

   if(!Pairs[idx].filtersValid)
      return "LOAD";

   bool trigger = HasEntryTrigger(idx);
   if(trigger)
      return "TRIG";

   if(Pairs[idx].direction == ORDER_TYPE_BUY)
   {
      if(Pairs[idx].rsiBuyOk && Pairs[idx].bbBuyOk) return "SET";
      if(Pairs[idx].rsiBuyOk) return "RSI";
      if(Pairs[idx].bbBuyOk)  return "BB";
      return "WAIT";
   }

   if(Pairs[idx].direction == ORDER_TYPE_SELL)
   {
      if(Pairs[idx].rsiSellOk && Pairs[idx].bbSellOk) return "SET";
      if(Pairs[idx].rsiSellOk) return "RSI";
      if(Pairs[idx].bbSellOk)  return "BB";
      return "WAIT";
   }

   return "-";
}

color PairFilterColor(int idx)
{
   if(idx < 0 || idx >= PairSize)
      return tmdSilver;

   if(!Pairs[idx].structurallyValid)
      return tmdSilver;

   if(!Pairs[idx].filtersValid)
      return tmdOrange;

   string txt = PairFilterText(idx);

   if(txt == "TRIG") return tmdGreen;
   if(txt == "SET")  return C'0,190,190';
   if(txt == "RSI")  return C'0,190,190';
   if(txt == "BB")   return C'0,190,190';
   if(txt == "WAIT") return tmdOrange;

   return tmdSilver;
}

int GetDirectionFromStrengths(double h1, double h4, double m15)
{
   int dir = -1;

   if(h1 > 0.0 && h4 > 0.0)
      dir = ORDER_TYPE_BUY;
   else if(h1 < 0.0 && h4 < 0.0)
      dir = ORDER_TYPE_SELL;
   else
      return -1;

   if(!PassesM15DirectionFilter(dir, m15))
      return -1;

   return dir;
}

bool PassesM15DirectionFilter(int direction, double m15)
{
   if(!InpUseM15Filter)
      return true;

   if(direction == ORDER_TYPE_BUY)
      return (m15 >= InpM15FilterMin);

   if(direction == ORDER_TYPE_SELL)
      return (m15 <= -InpM15FilterMin);

   return false;
}

double GetBullScoreFromStrengths(double m5, double m15, double h1, double h4)
{
   // H1/H4 dominate trend score, M15 is secondary, M5 is light
   double raw = (m5 * 1.0 + m15 * 1.5 + h1 * 3.5 + h4 * 4.0) / 10.0;
   return (MathTanh(raw) + 1.0) * 5.0; // 0..10
}

double GetATRNormalizedFast(string symbol, int atrHandle, ENUM_TIMEFRAMES tf)
{
   if(atrHandle == INVALID_HANDLE)
      return 1.0;

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(symbol, tf, 1, 1, rates) < 1)
      return 1.0;

   double atrBuf[];
   ArraySetAsSeries(atrBuf, true);
   if(CopyBuffer(atrHandle, 0, 1, 1, atrBuf) < 1)
      return 1.0;

   if(rates[0].close <= 0.0)
      return 1.0;

   double atrPct = atrBuf[0] / rates[0].close;
   double norm   = atrPct * 1000.0;

   return MathMax(0.5, MathMin(2.0, norm));
}

void RefreshPositionCaches()
{
   for(int i=0; i<PairSize; i++)
   {
      Pairs[i].openCount = 0;
      Pairs[i].openLots  = 0.0;
   }

   for(int i=0; i<PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      string sym = PositionGetString(POSITION_SYMBOL);
      double vol = PositionGetDouble(POSITION_VOLUME);

      for(int j=0; j<PairSize; j++)
      {
         if(Pairs[j].symbol == sym)
         {
            Pairs[j].openCount++;
            Pairs[j].openLots += vol;
            break;
         }
      }
   }
}

void RefreshGroupStates()
{
   for(int g = 0; g < 5; g++)
   {
      gGroupStates[g].buyCount = 0;
      gGroupStates[g].sellCount = 0;
   }

   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      string sym = PositionGetString(POSITION_SYMBOL);
      int group = GetGroup(sym);
      if(group < 0) continue;

      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      if(type == POSITION_TYPE_BUY)  gGroupStates[group].buyCount = 1;
      if(type == POSITION_TYPE_SELL) gGroupStates[group].sellCount = 1;
   }
}

double GetEquityDDPercent()
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);

   if(balance <= 0.0)
      return 0.0;

   return MathMax(0.0, (balance - equity) / balance * 100.0);
}

void UpdatePeakEquity()
{
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(eq > gPeakEquity)
      gPeakEquity = eq;
}

double GetPeakEquityDDPercent()
{
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);

   if(gPeakEquity <= 0.0)
      return 0.0;

   return MathMax(0.0, (gPeakEquity - eq) / gPeakEquity * 100.0);
}

double GetTotalOpenLots()
{
   double lots = 0.0;

   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      lots += PositionGetDouble(POSITION_VOLUME);
   }

   return lots;
}

bool SpreadAcceptable(string symbol, double maxPoints)
{
   double ask   = SymbolInfoDouble(symbol, SYMBOL_ASK);
   double bid   = SymbolInfoDouble(symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);

   if(ask <= 0.0 || bid <= 0.0 || point <= 0.0)
      return false;

   double spreadPts = (ask - bid) / point;
   return (spreadPts <= maxPoints);
}

bool CanAffordOrder(string symbol, ENUM_ORDER_TYPE type, double lots)
{
   if(lots <= 0.0)
      return false;

   double price = (type == ORDER_TYPE_BUY)
      ? SymbolInfoDouble(symbol, SYMBOL_ASK)
      : SymbolInfoDouble(symbol, SYMBOL_BID);

   if(price <= 0.0)
      return false;

   double marginRequired = 0.0;
   if(!OrderCalcMargin(type, symbol, lots, price, marginRequired))
      return false;

   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   if(freeMargin <= 0.0)
      return false;

   if(marginRequired > freeMargin * (InpMaxFirstOrderMarginPct / 100.0))
      return false;

   return true;
}

bool IsExposureTooHigh()
{
   if(InpMaxTotalPositions > 0 && PositionsTotal() >= InpMaxTotalPositions)
      return true;

   double maxTotalLots = GetDynamicMaxTotalLots();
   if(maxTotalLots > 0.0 && GetTotalOpenLots() >= maxTotalLots)
      return true;

   return false;
}

bool AllowGridExpansion()
{
   if(!InpUseRiskProtection)
      return true;

   if(!InpBlockGridExpansion)
      return true;

   double ddPct       = GetEquityDDPercent();
   double marginLevel = GetMarginLevelPercent();

   if(InpFreezeExpansionDD > 0.0 && ddPct >= InpFreezeExpansionDD)
      return false;

   if(marginLevel > 0.0 && marginLevel < InpFreezeExpansionMargin)
      return false;
   

   return true;
}

bool AllowGridExpansion(int idx, bool isBuyGrid)
{
   // first pass the existing global/account checks
   if(!AllowGridExpansion())
      return false;

   // then apply per-pair thesis validation
   if(IsPairTrendInvalidatedForExpansion(idx, isBuyGrid))
      return false;

   return true;
}

bool AllowNewRisk()
{
   if(!InpUseRiskProtection)
      return true;

   if(gEmergencyClose)
      return false;

   if(gFreezeNewEntries)
      return false;

   if(IsExposureTooHigh())
      return false;

   return true;
}

void EvaluateRiskState()
{
   gFreezeNewEntries = false;
   gEmergencyClose   = false;

   if(!InpUseRiskProtection)
      return;

   double ddPct         = GetEquityDDPercent();
   double marginLevel   = GetMarginLevelPercent();
   double freeMarginPct = GetFreeMarginPercent();

   if(InpMaxDD > 0.0 && ddPct >= InpMaxDD)
   {
      gEmergencyClose = true;
      return;
   }

   if(InpCriticalMarginLevel > 0.0 &&
      marginLevel > 0.0 &&
      marginLevel < InpCriticalMarginLevel)
   {
      gEmergencyClose = true;
      return;
   }

   if(InpMaxDD > 0.0 &&
      InpFreezeDDPercent > 0.0 &&
      ddPct >= (InpMaxDD * InpFreezeDDPercent))
   {
      gFreezeNewEntries = true;
   }

   if(InpFreezeMarginLevel > 0.0 &&
      marginLevel > 0.0 &&
      marginLevel < InpFreezeMarginLevel)
   {
      gFreezeNewEntries = true;
   }

   if(InpFreezeFreeMarginPct > 0.0 &&
      freeMarginPct < InpFreezeFreeMarginPct)
   {
      gFreezeNewEntries = true;
   }

   if(IsExposureTooHigh())
      gFreezeNewEntries = true;
}

void EmergencyCloseAllGrids(string reason)
{
   Print("===!!! [TMD] EMERGENCY CLOSE ALL: ", reason, " !!!===");

   for(int i = 0; i < PairSize; i++)
   {
      Pairs[i].buyGrid.CloseGrid();
      Pairs[i].sellGrid.CloseGrid();
   }
}

void UpdateRiskPanelState()
{
   gRiskStateText    = "NORMAL";
   gRiskStateColor   = tmdGreen;
   gEntryStateText   = "ALLOWED";
   gEntryStateColor  = tmdGreen;
   gExpandStateText  = "ALLOWED";
   gExpandStateColor = tmdGreen;
   gRiskReasonText   = "-";
   gRiskReasonColor  = tmdSilver;

   if(!InpUseRiskProtection)
   {
      gRiskStateText    = "OFF";
      gRiskStateColor   = tmdSilver;
      gEntryStateText   = "UNLIMITED";
      gEntryStateColor  = tmdSilver;
      gExpandStateText  = "UNLIMITED";
      gExpandStateColor = tmdSilver;
      gRiskReasonText   = "PROTECTION DISABLED";
      gRiskReasonColor  = tmdSilver;
      return;
   }

   double ddPct         = GetEquityDDPercent();
   double marginLevel   = GetMarginLevelPercent();
   double freeMarginPct = GetFreeMarginPercent();
   bool exposureHigh    = IsExposureTooHigh();
   bool allowExpand     = AllowGridExpansion();

   if(gEmergencyClose)
   {
      gRiskStateText    = "EMERGENCY";
      gRiskStateColor   = tmdRed;
      gEntryStateText   = "BLOCKED";
      gEntryStateColor  = tmdRed;
      gExpandStateText  = "BLOCKED";
      gExpandStateColor = tmdRed;

      if(InpMaxDD > 0.0 && ddPct >= InpMaxDD)
         gRiskReasonText = "MAX DD";
      else if(InpCriticalMarginLevel > 0.0 && marginLevel > 0.0 && marginLevel < InpCriticalMarginLevel)
         gRiskReasonText = "CRIT MARGIN";
      else
         gRiskReasonText = "FORCED CLOSE";

      gRiskReasonColor = tmdRed;
      return;
   }

   if(gFreezeNewEntries)
   {
      gRiskStateText   = "FROZEN";
      gRiskStateColor  = tmdOrange;
      gEntryStateText  = "BLOCKED";
      gEntryStateColor = tmdOrange;

      if(InpMaxDD > 0.0 && ddPct >= (InpMaxDD * InpFreezeDDPercent))
         gRiskReasonText = "DD FREEZE";
      else if(InpFreezeMarginLevel > 0.0 && marginLevel > 0.0 && marginLevel < InpFreezeMarginLevel)
         gRiskReasonText = "MARGIN LOW";
      else if(InpFreezeFreeMarginPct > 0.0 && freeMarginPct < InpFreezeFreeMarginPct)
         gRiskReasonText = "FREE MGN LOW";
      else if(exposureHigh)
         gRiskReasonText = "EXPOSURE CAP";
      else
         gRiskReasonText = "RISK FILTER";

      gRiskReasonColor = tmdOrange;
   }

   if(!allowExpand)
   {
      gExpandStateText  = "FROZEN";
      gExpandStateColor = tmdOrange;

      if(gRiskReasonText == "-")
      {
         if(InpFreezeExpansionDD > 0.0 && ddPct >= InpFreezeExpansionDD)
            gRiskReasonText = "NO EXPAND DD";
         else if(InpFreezeExpansionMargin > 0.0 && marginLevel > 0.0 && marginLevel < InpFreezeExpansionMargin)
            gRiskReasonText = "NO EXPAND MGN";
         else
            gRiskReasonText = "EXPANSION OFF";

         gRiskReasonColor = tmdOrange;
      }
   }

   if(gRiskStateText == "NORMAL" && !allowExpand)
   {
      gRiskStateText  = "CAUTION";
      gRiskStateColor = tmdOrange;
   }
}

color GetLotUsageColor(double lots)
{
   double maxLots = GetDynamicMaxTotalLots();

   if(maxLots <= 0.0)
      return tmdSilver;

   double ratio = lots / maxLots;

   if(ratio >= 1.0)
      return tmdRed;

   if(ratio >= 0.75)
      return tmdOrange;

   return tmdGreen;
}

color GetPositionUsageColor(int positions)
{
   if(InpMaxOrders <= 0)
      return tmdSilver; // no limit active

   double ratio = positions / InpMaxOrders;

   if(ratio >= 1.0)
      return tmdRed;        // exceeded / maxed

   if(ratio >= 0.75)
      return tmdOrange;     // near limit (warning zone)

   return tmdGreen;         // safe
}

bool GetLastClosedM5(string symbol, MqlRates &bar1, MqlRates &bar2)
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);

   if(CopyRates(symbol, PERIOD_M5, 1, 2, rates) < 2)
      return false;

   bar1 = rates[0]; // last closed M5 bar
   bar2 = rates[1]; // previous closed M5 bar
   return true;
}

bool IsBuyReentryTrigger(int idx)
{
   if(idx < 0 || idx >= PairSize)
      return false;

   if(!Pairs[idx].filtersValid)
      return false;

   MqlRates bar1, bar2;
   if(!GetLastClosedM5(Pairs[idx].symbol, bar1, bar2))
      return false;

   double bbUpper[], bbLower[];
   ArraySetAsSeries(bbUpper, true);
   ArraySetAsSeries(bbLower, true);

   if(CopyBuffer(Pairs[idx].bbM1Handle, 1, 1, 2, bbUpper) < 2)
      return false;
   if(CopyBuffer(Pairs[idx].bbM1Handle, 2, 1, 2, bbLower) < 2)
      return false;

   bool wasOutside = (bar2.close < bbLower[1]);
   bool reentered  = (bar1.close > bbLower[0]);
   bool bullClose  = (bar1.close > bar1.open);

   return (wasOutside && reentered && bullClose);
}

bool IsSellReentryTrigger(int idx)
{
   if(idx < 0 || idx >= PairSize)
      return false;

   if(!Pairs[idx].filtersValid)
      return false;

   MqlRates bar1, bar2;
   if(!GetLastClosedM5(Pairs[idx].symbol, bar1, bar2))
      return false;

   double bbUpper[], bbLower[];
   ArraySetAsSeries(bbUpper, true);
   ArraySetAsSeries(bbLower, true);

   if(CopyBuffer(Pairs[idx].bbM1Handle, 1, 1, 2, bbUpper) < 2)
      return false;
   if(CopyBuffer(Pairs[idx].bbM1Handle, 2, 1, 2, bbLower) < 2)
      return false;

   bool wasOutside = (bar2.close > bbUpper[1]);
   bool reentered  = (bar1.close < bbUpper[0]);
   bool bearClose  = (bar1.close < bar1.open);

   return (wasOutside && reentered && bearClose);
}

bool GetRSITurn(int handle, double &rsi1, double &rsi2)
{
   double rsi[];
   ArraySetAsSeries(rsi, true);

   if(CopyBuffer(handle, 0, 1, 2, rsi) < 2)
      return false;

   rsi1 = rsi[0]; // last closed
   rsi2 = rsi[1]; // previous closed
   return true;
}

bool IsBuyRSITurnTrigger(int idx)
{
   double rsi1, rsi2;
   if(!GetRSITurn(Pairs[idx].rsiM1Handle, rsi1, rsi2))
      return false;

   return (rsi2 < InpBuyRsi && rsi1 > rsi2);
}

bool IsSellRSITurnTrigger(int idx)
{
   double rsi1, rsi2;
   if(!GetRSITurn(Pairs[idx].rsiM1Handle, rsi1, rsi2))
      return false;

   return (rsi2 > InpSellRsi && rsi1 < rsi2);
}

bool HasEntryTrigger(int idx)
{
   if(idx < 0 || idx >= PairSize)
      return false;

   if(Pairs[idx].direction == ORDER_TYPE_BUY)
   {
      bool rsiTurn        = IsBuyRSITurnTrigger(idx);
      bool bbReentry      = InpUseBB ? IsBuyReentryTrigger(idx) : true;
      bool bullishConfirm = IsBullishConfirmCandle(Pairs[idx].symbol);
      return (rsiTurn && bbReentry && bullishConfirm);
   }

   if(Pairs[idx].direction == ORDER_TYPE_SELL)
   {
      bool rsiTurn     = IsSellRSITurnTrigger(idx);
      bool bbReentry   = InpUseBB ? IsSellReentryTrigger(idx) : true;
      bool sellConfirm = IsBearishConfirmCandle(Pairs[idx].symbol);
      return (rsiTurn && bbReentry && sellConfirm);
   }

   return false;
}

bool IsBullishConfirmCandle(string symbol)
{
   MqlRates bar1, bar2;
   if(!GetLastClosedM5(symbol, bar1, bar2))
      return false;

   double prevMid = (bar2.high + bar2.low) * 0.5;
   return (bar1.close > bar1.open && bar1.close > prevMid);
}

bool IsBearishConfirmCandle(string symbol)
{
   MqlRates bar1, bar2;
   if(!GetLastClosedM5(symbol, bar1, bar2))
      return false;

   double prevMid = (bar2.high + bar2.low) * 0.5;
   return (bar1.close < bar1.open && bar1.close < prevMid);
}

bool IsBuyTrendInvalidated(int idx)
{
   if(idx < 0 || idx >= PairSize)
      return false;

   if(Pairs[idx].buyGrid.CountPositions() <= 0)
      return false;

   // original buy thesis no longer valid
   if(Pairs[idx].direction != ORDER_TYPE_BUY)
      return true;

   if(!Pairs[idx].aligned)
      return true;

   return false;
}

bool IsSellTrendInvalidated(int idx)
{
   if(idx < 0 || idx >= PairSize)
      return false;

   if(Pairs[idx].sellGrid.CountPositions() <= 0)
      return false;

   // original sell thesis no longer valid
   if(Pairs[idx].direction != ORDER_TYPE_SELL)
      return true;

   if(!Pairs[idx].aligned)
      return true;

   return false;
}

bool IsGridInProfit(GridManager *grid)
{
   if(grid == NULL)
      return false;

   return (grid.GridPnL() > 0.0);
}

double GetDynamicMaxTotalLots()
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);

   if(InpBaseBalanceForMaxLots <= 0.0)
      return InpBaseMaxTotalLots;

   double maxLots = (balance / InpBaseBalanceForMaxLots) * InpBaseMaxTotalLots;

   if(maxLots < InpMinMaxTotalLots)
      maxLots = InpMinMaxTotalLots;

   if(InpHardMaxTotalLots > 0.0 && maxLots > InpHardMaxTotalLots)
      maxLots = InpHardMaxTotalLots;

   return maxLots;
}

bool IsPairTrendInvalidatedForExpansion(int idx, bool isBuyGrid)
{
   if(idx < 0 || idx >= PairSize)
      return true;

   // no clear direction anymore
   if(Pairs[idx].direction == -1)
      return true;

   // currency alignment broken
   if(!Pairs[idx].aligned)
      return true;

   // grid-side thesis broken
   if(isBuyGrid && Pairs[idx].direction != ORDER_TYPE_BUY)
      return true;

   if(!isBuyGrid && Pairs[idx].direction != ORDER_TYPE_SELL)
      return true;

   return false;
}

bool IsPairExpansionFrozen(int idx, bool isBuyGrid)
{
   if(idx < 0 || idx >= PairSize)
      return true;

   if(isBuyGrid)
   {
      if(Pairs[idx].buyGrid.CountPositions() <= 0)
         return false;

      return !AllowGridExpansion(idx, true);
   }

   if(Pairs[idx].sellGrid.CountPositions() <= 0)
      return false;

   return !AllowGridExpansion(idx, false);
}

double GetDynamicTrendExitMinProfit()
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);

   if(InpBaseBalanceForTrendExitProfit <= 0.0)
      return InpBaseTrendExitMinProfit;

   double minProfit = (balance / InpBaseBalanceForTrendExitProfit) * InpBaseTrendExitMinProfit;

   if(minProfit < InpMinTrendExitProfit)
      minProfit = InpMinTrendExitProfit;

   if(InpMaxTrendExitProfit > 0.0 && minProfit > InpMaxTrendExitProfit)
      minProfit = InpMaxTrendExitProfit;

   return minProfit;
}