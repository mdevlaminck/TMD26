//+------------------------------------------------------------------+
//|                                                        TMD19.mq5 |
//|                                                              MDV |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "MDV"
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Trade/Trade.mqh>
#include <TMD/GridManager.mqh>
#include <TMD/ChartStyle.mqh>
#include <TMD/Trend.mqh>

CTrade trade;

#define PANEL_PREFIX   "TMDP_"
#define PANEL_CUR_ROWS 8
#define PANEL_SYM_ROWS 28
#define HISTORY        5

enum ENUM_ONOFF
{
   OFF = 0,
   ON  = 1
};
// TYPES

enum GapBias
{
   GAP_NONE = 0,
   GAP_BULL = 1,
   GAP_BEAR = -1
};



struct GroupState
{
   int buyCount;
   int sellCount;
};


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
   bool   aligned;
   double currencyScore;
   double comp;

   int direction;

   GridManager *buyGrid;
   GridManager *sellGrid;

   int rsiM1Handle;
   int bbM1Handle;

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

   bool   eligibleNow;
   string stateText;
   color  stateColor;
   color  dotColor;

   bool   filtersValid;
   double rsiM1;
   double bbUpperM1;
   double bbLowerM1;
   bool   rsiBuyOk;
   bool   rsiSellOk;
   bool   bbBuyOk;
   bool   bbSellOk;

   bool needsFilterRefresh;
   bool structurallyValid;

   bool marketOpen;

   int    openCount;
   double openLots;
   
   // Volatility filter
   int    atrHandle;
   double atrValuePoints;
   double atrValuePrice;
   bool   highVolatility;
   
   string waitReason;
   
   GapBias mondayGapBias;
   int     mondayGapDay;
   
   int    trendH4;
   int    trendH1;
   bool   trendAligned;
   
};

class RiskOffEngine
{
private:
   datetime m_lastRiskOffTime;
   int      m_lastScore;
   bool     m_isRiskOff;
   bool     m_isExtremeRiskOff;

public:
   RiskOffEngine()
   {
      m_lastRiskOffTime   = 0;
      m_lastScore         = 0;
      m_isRiskOff         = false;
      m_isExtremeRiskOff  = false;
   }

   void Reset()
   {
      m_lastRiskOffTime   = 0;
      m_lastScore         = 0;
      m_isRiskOff         = false;
      m_isExtremeRiskOff  = false;
   }

   datetime LastRiskOffTime() const { return m_lastRiskOffTime; }
   int      LastScore()       const { return m_lastScore;      }
   bool     IsRiskOff()       const { return m_isRiskOff;      }
   bool     IsExtreme()       const { return m_isExtremeRiskOff; }

   bool InCooldown(const int cooldownSeconds) const
   {
      if(m_lastRiskOffTime <= 0 || cooldownSeconds <= 0)
         return false;

      return (TimeCurrent() - m_lastRiskOffTime < cooldownSeconds);
   }

   bool Update(
      const double &currStrength[],
      const PairData &pairs[],
      const int pairSize,
      const double slopeThr,
      const double accelThr,
      const double minComp,
      const int idxJPY,
      const int idxCHF,
      const int idxAUD,
      const int idxNZD,
      const int idxCAD,
      const bool useCHF,
      const bool useVolatility,
      const double volSpikeRatio,
      const ENUM_TIMEFRAMES volTf,
      const int volAtrPeriod,
      const int minAlignedPairs,
      const int minJpyBearishPairs,
      const bool useSymbolAtrReference,
      const string atrSymbol,
      const int scoreTrigger
   )
   {
      int score = 0;

      double jpy = currStrength[idxJPY];
      double chf = currStrength[idxCHF];
      double aud = currStrength[idxAUD];
      double nzd = currStrength[idxNZD];
      double cad = currStrength[idxCAD];

      bool riskOffStrength = false;

      if(useCHF)
      {
         riskOffStrength =
            (jpy >  0.6 && chf >  0.4) &&
            (aud < -0.4 && nzd < -0.4);
      }
      else
      {
         riskOffStrength =
            (jpy >  0.6) &&
            (aud < -0.4 && nzd < -0.4);
      }

      if(cad < -0.4)
         riskOffStrength = riskOffStrength || (jpy > 0.6 && aud < -0.4 && nzd < -0.4 && cad < -0.4);

      if(riskOffStrength)
         score += 2;

      double slopeCutoff = 5.0 - (slopeThr * 5.0);
      int jpyBearishCount = 0;

      for(int i = 0; i < pairSize; i++)
      {
         string sym = pairs[i].symbol;
         if(sym == "")
            continue;

         string quote = StringSubstr(sym, 3, 3);

         if(quote == "JPY" && pairs[i].slope <= slopeCutoff)
            jpyBearishCount++;
      }

      bool jpyFlow = (jpyBearishCount >= minJpyBearishPairs);
      if(jpyFlow)
         score += 2;

      int alignedPairs = 0;
      for(int i = 0; i < pairSize; i++)
      {
         if(!pairs[i].aligned)
            continue;

         if(MathAbs(pairs[i].comp) >= minComp)
            alignedPairs++;
      }

      bool marketAligned = (alignedPairs >= minAlignedPairs);
      if(marketAligned)
         score += 1;

      double accelDistanceCutoff = accelThr * 5.0;
      int accelShockCount = 0;
      for(int i = 0; i < pairSize; i++)
      {
         if(MathAbs(pairs[i].accel - 5.0) >= accelDistanceCutoff)
            accelShockCount++;
      }

      bool accelShock = (accelShockCount >= 4);
      if(accelShock)
         score += 1;

      bool volSpike = false;

      if(useVolatility)
      {
         string refSymbol = useSymbolAtrReference ? atrSymbol : _Symbol;
         if(refSymbol == "")
            refSymbol = _Symbol;

         int atrHandle = iATR(refSymbol, volTf, volAtrPeriod);
         if(atrHandle != INVALID_HANDLE)
         {
            double atrBuf[];
            ArrayResize(atrBuf, 25);

            int copied = CopyBuffer(atrHandle, 0, 0, 25, atrBuf);
            if(copied >= 21)
            {
               double atrNow  = atrBuf[0];
               double atrPast = atrBuf[20];

               if(atrPast > 0.0 && atrNow >= atrPast * volSpikeRatio)
                  volSpike = true;
            }

            IndicatorRelease(atrHandle);
         }
      }

      if(volSpike)
         score += 1;

      int trigger = scoreTrigger;
      if(trigger < 1)
         trigger = 1;

      m_lastScore        = score;
      m_isRiskOff        = (score >= trigger);
      m_isExtremeRiskOff = (score >= trigger + 2);

      if(m_isRiskOff)
         m_lastRiskOffTime = TimeCurrent();

      return m_isRiskOff;
   }
};

// CONFIG
input group "=== Symbol Settings ===";
input string InpSuffix = "";
input string InpPrefix = "";

input group "=== Lot Settings ===";
input ENUM_ONOFF InpUseAutoLot = ON;
input double InpBalancePerLot = 500;
input double InpInitialLot = 0.01;
input ENUM_ONOFF InpUseDynamicLot = ON;
input double InpMinLotFactor = 0.7;
input double InpMaxLotFactor = 2.5;

input group "=== Grid Settings ===";
input int InpMagicBuy = 2204;
input int InpMagicSell = 1981;
input int InpMaxOrders = 14;
input double InpMaxDD = 0;
input int InpGapPoints = 200;
input double InpProfitPercent = 0.06;
input double InpGridMultiplier = 1.03;

input group "=== Filter Settings ===";
input double InpMinScore = 6.8;
input double InpBuyRsi = 35;
input double InpSellRsi = 65;
input ENUM_ONOFF InpUseTopPairsFilter       = OFF;
input int        InpTopPairsCount           = 10;
input int        InpMaxCurrencyReuseInTop   = 3;   // each currency can appear at most X times in selected top basket
input double     InpOverlapPenaltyPerSide   = 0.2; // rank penalty per reused currency
input ENUM_ONOFF InpUseBB = ON;
input ENUM_ONOFF InpUseM15Filter = OFF;
input double InpM15FilterMin = 0.15;
input double InpMinAccel = 4.5;
input bool   InpUseMondayGapFilter   = true;
input double InpMondayGapMinPoints   = 100;   // points, adapt per symbol
input bool   InpBlockOverextendedImpulse = true;
input double InpMaxAccelDistanceFromMid  = 4.0; // 9.0 / 1.0 equivalent
input double InpMaxSlopeDistanceFromMid  = 4.2; // 9.2 / 0.8 equivalent
input group "=== Volatility Filter ===";
input bool            InpUseVolatilityFilter      = true;          // Enable volatility filter
input ENUM_TIMEFRAMES InpVolatilityTF             = PERIOD_M15;    // ATR timeframe
input int             InpATRPeriod                = 14;            // ATR period
input double          InpMaxATRPoints             = 250.0;         // Max ATR in points
input double          InpMaxATRPercentOfPrice     = 0.0;           // Optional: ATR as % of price (0 = off)
input ENUM_ONOFF      InpBlockNewEntriesOnHighVol = ON;            // Block new entries
input ENUM_ONOFF      InpBlockExpansionOnHighVol  = ON;            // Block grid expansion
input group "=== Risk-Off Engine ===";
enum ENUM_RISK_OFF_MODE
{
   RISK_OFF_DISABLED = 0,
   RISK_OFF_BLOCK_NEW = 1,
   RISK_OFF_BLOCK_AND_STOP_EXPANSION = 2,
   RISK_OFF_FULL_PROTECTION = 3
};

input ENUM_RISK_OFF_MODE InpRiskOffMode = RISK_OFF_BLOCK_AND_STOP_EXPANSION;

input int    InpRiskOffScoreTrigger      = 5;    // Score Trigger
input int    InpRiskOffCooldownSec       = 1800; // Cooldown Seconds
input double InpRiskOffSlopeThreshold    = 0.15;
input double InpRiskOffAccelThreshold    = 0.25;
input int    InpRiskOffMinAlignedPairs   = 10;
input int    InpRiskOffMinJpyPairs       = 3;
input bool   InpRiskOffUseCHF            = true;
input bool   InpRiskOffUseVolatility     = true;
input ENUM_TIMEFRAMES InpRiskOffVolTF    = PERIOD_M5;
input int    InpRiskOffATRPeriod         = 14;
input double InpRiskOffATRSpikeRatio     = 1.50;
input bool   InpRiskOffUseAtrSymbol      = false;
input string InpRiskOffAtrSymbol         = "EURUSD";

input bool   InpRiskOffCloseProfitableGrids = true;
input double InpRiskOffTrendExitMinProfit   = 0.0;
input group "=== Risk-Off Entry Filter ===";
input bool   InpUseRiskOffDirectionalEntryFilter = true;   // Entry only for CHF/JPY pairs
input double InpRiskOffMinAccel                  = 0.08;   // Extra momentum requirement during risk-off
input double InpRiskOffMinComp                   = 0.0;    // Min Comp - 0 = use normal comp filter only
input bool   InpBlockSafeHavenVsSafeHaven        = true;   // Block CHFJPY/JPYCHF during risk-off
input group "=== Risk Protection ===";
input ENUM_ONOFF InpUseRiskProtection      = ON;
input double     InpFreezeDDPercent        = 0.70;
input double     InpCriticalMarginLevel    = 120.0;
input double     InpFreezeMarginLevel      = 180.0;
input double     InpFreezeFreeMarginPct    = 80.0;
input int        InpMaxTotalPositions      = 50;
input double     InpBaseBalanceForMaxLots  = 1000.0;
input double     InpBaseMaxTotalLots       = 0.25;
input double     InpMinMaxTotalLots        = 0.10;
input double     InpHardMaxTotalLots       = 10.00;
input double     InpMaxFirstOrderMarginPct = 20.0;
input ENUM_ONOFF InpBlockGridExpansion     = ON;
input double     InpFreezeExpansionDD      = 15.0;
input double     InpFreezeExpansionMargin  = 240.0;
input double     InpMaxSpreadPoints        = 12.0;
input double     InpBaseBalanceForTrendExitProfit = 1000.0;
input double     InpBaseTrendExitMinProfit        = 1.50;
input double     InpMinTrendExitProfit            = 0.30;
input double     InpMaxTrendExitProfit            = 100.00;
input group "=== Time-Based Grid Exit ===";
input ENUM_ONOFF InpUseTimeExit               = ON;
input double     InpGridTimeExitStartDays     = 7.0;   // Start monitoring aged grids after X days
input double     InpGridTimeExitProfitDays    = 7.0;   // For this many extra days: exit only if >= 0 profit
input double     InpGridTimeExitStepDays      = 4.0;   // After profit-only phase, increase accepted loss every X days
input double     InpGridTimeExitLossStepPct   = 0.25;  // Accepted loss step as % of balance
input double     InpGridTimeExitMaxLossPct    = 1.50;  // Max accepted loss cap as % of balance
input group "=== Visual Settings ===";
input ENUM_ONOFF InpStyleChart = ON;
input ENUM_ONOFF InpShowPanel  = ON;

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

string GROUP_USD[]    = {"EURUSD","GBPUSD","AUDUSD","NZDUSD","USDJPY","USDCHF","USDCAD"};
string GROUP_EUR[]    = {"EURGBP","EURJPY","EURCHF","EURAUD","EURNZD","EURCAD"};
string GROUP_GBP[]    = {"GBPJPY","GBPCHF","GBPAUD","GBPNZD","GBPCAD"};
string GROUP_AUDNZD[] = {"AUDJPY","AUDCHF","AUDNZD","AUDCAD","NZDJPY","NZDCHF","NZDCAD"};
string GROUP_SAFE[]   = {"CADJPY","CADCHF","CHFJPY"};

color tmdGreen    = C'38,166,154';
color tmdRed      = C'239,83,80';
color tmdOrange   = C'255,152,0';
color tmdSilver   = C'219,219,219';
color tmdBg       = C'16,26,37';
color tmdSubtleBg = C'42,58,79';
color tmdBid      = C'41,98,255';
color tmdAsk      = C'247,82,95';

string gPanelObjects[];
double currencyStrength[8];
PairData Pairs[];

double currentPnL = 0.0;
int    PairSize   = 0;
bool   brokerWindowOpen = false;

GroupState gGroupStates[5];

double gPeakEquity       = 0.0;
bool   gFreezeNewEntries = false;
bool   gEmergencyClose   = false;

string gRiskStateText    = "NORMAL";
color  gRiskStateColor   = clrNONE;
string gEntryStateText   = "ALLOWED";
color  gEntryStateColor  = clrNONE;
string gExpandStateText  = "ALLOWED";
color  gExpandStateColor = clrNONE;
string gRiskReasonText   = "-";
color  gRiskReasonColor  = clrNONE;

RiskOffEngine gRiskOff;
bool gRiskOffActive = false;
bool gRiskOffCooldown = false;

int OnInit()
{
   TesterHideIndicators(true);

   StyleChart();
   InitPairs();
   UpdateAllPairs();

   CreateTMDInfoPanel();
   UpdateTMDInfoPanel();

   gPeakEquity       = AccountInfoDouble(ACCOUNT_EQUITY);
   gFreezeNewEntries = false;
   gEmergencyClose   = false;

   Print("==== TMD[1.0] Initialized with " + IntegerToString(ArraySize(Symbols)) + " symbols ====");
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   DeleteTMDInfoPanel();

   for(int i = 0; i < ArraySize(Pairs); i++)
   {
      delete Pairs[i].buyGrid;
      delete Pairs[i].sellGrid;
      Pairs[i].buyGrid  = NULL;
      Pairs[i].sellGrid = NULL;
   }

   ReleasePairHandles();

   Print("==== TMD[1.0] Stopped ====");
}

void OnTick()
{
   static datetime lastM15 = 0;
   static datetime lastM5  = 0;
   static datetime lastM1  = 0;

   bool newM15 = IsNewBar(_Symbol, PERIOD_M15, lastM15);
   bool newM5  = IsNewBar(_Symbol, PERIOD_M5,  lastM5);
   bool newM1  = IsNewBar(_Symbol, PERIOD_M1,  lastM1);
      
   // New M15
   if(newM15)
   {
      for(int i = 0; i < PairSize; i++)
         UpdateMondayGapFilterForPair(Pairs[i]);
      UpdateAllPairs();
   }

   // New M5
   if(newM5)
   {
      RefreshPositionCaches();
      RefreshGroupStates();
      RefreshAllPairFilterCaches();
      CheckExit();
      CheckEntry();
   }
   
   // New M1
   if (newM1) {
      currentPnL = 0.0;
      brokerWindowOpen = IsBrokerTradeWindow();
      UpdatePeakEquity(); 
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
         string reasonText = "UNKNOWN";
   
         double ddPct       = GetEquityDDPercent();
         double marginLevel = GetMarginLevelPercent();
   
         if(InpMaxDD > 0.0 && ddPct >= InpMaxDD)
            reasonText = "MAX DD HIT";
         else if(InpCriticalMarginLevel > 0.0 && marginLevel > 0.0 && marginLevel < InpCriticalMarginLevel)
            reasonText = "CRITICAL MARGIN LEVEL";
   
         EmergencyCloseAllGrids(reasonText);
         UpdateTMDInfoPanel();
      }
   }

   UpdateTMDInfoPanel();
}

void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
   if(id == CHARTEVENT_CLICK)
   {
      int x = (int)lparam;
      int y = (int)dparam;
      HandleTMDPanelChartClick(x, y);
   }
}


void CheckEntry()
{
   if(gEmergencyClose)
      return;

   int topPairs[];
   if(InpUseTopPairsFilter)
      GetTopPairs(topPairs);

   for(int i = 0; i < PairSize; i++)
   {
      if(InpUseTopPairsFilter && !IsTopPairSelected(i, topPairs))
         continue;

      string riskReason = "";
      if(!AllowNewRiskEntry(i, riskReason))
      {
         if(Pairs[i].waitReason == "")
            Pairs[i].waitReason = riskReason;
         continue;
      }

      if(!IsPairEligibleNow(i))
         continue;
      if(IsBlockedByMondayGap(Pairs[i], Pairs[i].direction))
      {
         Pairs[i].waitReason = "MON GAP";
         continue;
      }
      if(!HasEntryTrigger(i))
      {
         if(Pairs[i].waitReason == "")
            Pairs[i].waitReason = PairFilterText(i);
         continue;
      }

      if(!SpreadAcceptable(Pairs[i].symbol, InpMaxSpreadPoints))
         continue;

      if(InpUseVolatilityFilter &&
         InpBlockNewEntriesOnHighVol == ON &&
         Pairs[i].highVolatility)
      {
         Print("ENTRY BLOCKED [HIGH VOL]: ", Pairs[i].symbol,
               " | ATR pts: ", DoubleToString(Pairs[i].atrValuePoints, 0));
         continue;
      }

      double baseLot = InpUseAutoLot ? CalculateLotSize(Pairs[i].symbol, InpBalancePerLot) : InpInitialLot;
      double lotSize = GetDynamicLotSize(baseLot, Pairs[i].comp);

      if(Pairs[i].direction == ORDER_TYPE_BUY)
      {
         if(!CanAffordOrder(Pairs[i].symbol, ORDER_TYPE_BUY, lotSize))
            continue;

         Print("TRADE BUY: ", Pairs[i].symbol,
               " | Rank: ", DoubleToString(GetEntryRankScore(i), 2),
               " | Comp: ", DoubleToString(Pairs[i].comp,2),
               " | Score: ", DoubleToString(Pairs[i].score,2),
               " | Cur: ", DoubleToString(Pairs[i].currencyScore,2),
               " | Sl: ", DoubleToString(Pairs[i].slope,2),
               " | Ac: ", DoubleToString(Pairs[i].accel,2),
               " | RSI: ", DoubleToString(Pairs[i].rsiM1,1),
               " | Lot: ", DoubleToString(lotSize,2));

         Pairs[i].waitReason = "LIVE";
         Pairs[i].buyGrid.SetLotSize(lotSize);
         Pairs[i].buyGrid.Start();
         continue;
      }

      if(Pairs[i].direction == ORDER_TYPE_SELL)
      {
         if(!CanAffordOrder(Pairs[i].symbol, ORDER_TYPE_SELL, lotSize))
            continue;

         Print("TRADE SELL: ", Pairs[i].symbol,
               " | Rank: ", DoubleToString(GetEntryRankScore(i), 2),
               " | Comp: ", DoubleToString(Pairs[i].comp,2),
               " | Score: ", DoubleToString(Pairs[i].score,2),
               " | Cur: ", DoubleToString(Pairs[i].currencyScore,2),
               " | Sl: ", DoubleToString(Pairs[i].slope,2),
               " | Ac: ", DoubleToString(Pairs[i].accel,2),
               " | RSI: ", DoubleToString(Pairs[i].rsiM1,1),
               " | Lot: ", DoubleToString(lotSize,2));

         Pairs[i].waitReason = "LIVE";
         Pairs[i].sellGrid.SetLotSize(lotSize);
         Pairs[i].sellGrid.Start();
      }
   }
}

void CheckExit()
{
   ApplyRiskOffProtection();

   double minExitProfit = GetDynamicTrendExitMinProfit();

   for(int i = 0; i < PairSize; i++)
   {
      if(Pairs[i].buyGrid.CountPositions() > 0)
      {
         bool   trendInvalid   = IsBuyTrendInvalidated(i);
         double pnl            = Pairs[i].buyGrid.GridPnL();
         double ageDays        = 0.0;
         double timeThreshold  = 0.0;
         string timeReason     = "";

         // 1) Existing trend-based exit
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

         // 2) New time-based stale-grid exit
         if(ShouldExitGridByTime(i, true, pnl, ageDays, timeThreshold, timeReason))
         {
            Print("EXIT BUY GRID [", timeReason, "]: ", Pairs[i].symbol,
                  " | AgeDays: ", DoubleToString(ageDays, 1),
                  " | GridPnL: ", DoubleToString(pnl, 2),
                  " | Threshold: ", DoubleToString(timeThreshold, 2),
                  " | Orders: ", IntegerToString(Pairs[i].buyGrid.CountPositions()));

            Pairs[i].buyGrid.CloseGrid();
            continue;
         }
      }

      if(Pairs[i].sellGrid.CountPositions() > 0)
      {
         bool   trendInvalid   = IsSellTrendInvalidated(i);
         double pnl            = Pairs[i].sellGrid.GridPnL();
         double ageDays        = 0.0;
         double timeThreshold  = 0.0;
         string timeReason     = "";

         // 1) Existing trend-based exit
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

         // 2) New time-based stale-grid exit
         if(ShouldExitGridByTime(i, false, pnl, ageDays, timeThreshold, timeReason))
         {
            Print("EXIT SELL GRID [", timeReason, "]: ", Pairs[i].symbol,
                  " | AgeDays: ", DoubleToString(ageDays, 1),
                  " | GridPnL: ", DoubleToString(pnl, 2),
                  " | Threshold: ", DoubleToString(timeThreshold, 2),
                  " | Orders: ", IntegerToString(Pairs[i].sellGrid.CountPositions()));

            Pairs[i].sellGrid.CloseGrid();
            continue;
         }
      }
   }
}

void ApplyRiskOffProtection()
{
   if(InpRiskOffMode != RISK_OFF_FULL_PROTECTION)
      return;

   if(!gRiskOffActive)
      return;

   if(!InpRiskOffCloseProfitableGrids)
      return;

   for(int i = 0; i < PairSize; i++)
   {
      if(Pairs[i].buyGrid.CountPositions() > 0)
      {
         double pnlBuy = Pairs[i].buyGrid.GridPnL();
         if(pnlBuy >= InpRiskOffTrendExitMinProfit)
            Pairs[i].buyGrid.CloseGrid();
      }

      if(Pairs[i].sellGrid.CountPositions() > 0)
      {
         double pnlSell = Pairs[i].sellGrid.GridPnL();
         if(pnlSell >= InpRiskOffTrendExitMinProfit)
            Pairs[i].sellGrid.CloseGrid();
      }
   }
}

bool IsInGroup(string symbol, string &group[])
{
   for(int i = 0; i < ArraySize(group); i++)
   {
      if(symbol == InpPrefix + group[i] + InpSuffix)
         return true;
   }
   return false;
}

int GetGroup(string symbol)
{
   if(IsInGroup(symbol, GROUP_USD))    return 0;
   if(IsInGroup(symbol, GROUP_EUR))    return 1;
   if(IsInGroup(symbol, GROUP_GBP))    return 2;
   if(IsInGroup(symbol, GROUP_AUDNZD)) return 3;
   if(IsInGroup(symbol, GROUP_SAFE))   return 4;
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

void RefreshGroupStates()
{
   for(int g = 0; g < 5; g++)
   {
      gGroupStates[g].buyCount = 0;
      gGroupStates[g].sellCount = 0;
   }

   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      string sym = PositionGetString(POSITION_SYMBOL);
      int group  = GetGroup(sym);
      if(group < 0)
         continue;

      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      if(type == POSITION_TYPE_BUY)  gGroupStates[group].buyCount = 1;
      if(type == POSITION_TYPE_SELL) gGroupStates[group].sellCount = 1;
   }
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

   for(int i = 0; i < PairSize; i++)
   {
      if(Pairs[i].direction == -1 || !Pairs[i].aligned)
         continue;

      if(idx1 == -1 || Pairs[i].comp > Pairs[idx1].comp)
         idx1 = i;
   }

   if(idx1 == -1)
      return;

   for(int i = 0; i < PairSize; i++)
   {
      if(i == idx1)
         continue;
      if(Pairs[i].direction == -1 || !Pairs[i].aligned)
         continue;
      if(HasCurrencyOverlap(Pairs[i].symbol, Pairs[idx1].symbol))
         continue;

      if(idx2 == -1 || Pairs[i].comp > Pairs[idx2].comp)
         idx2 = i;
   }
}

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

double CalculateLotSize(string symbol, double balancePerLot = 500.0, double lotPerBalance = 0.01)
{
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

   return NormalizeLot(symbol, lots);
}

int GetCurrencyIndexFast(string cur)
{
   cur = ToUpper(cur);

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

void GetPairCurrencies(string symbol, int &baseIdx, int &quoteIdx)
{
   string base  = StringSubstr(symbol, 0, 3);
   string quote = StringSubstr(symbol, 3, 3);

   baseIdx  = GetCurrencyIndexFast(base);
   quoteIdx = GetCurrencyIndexFast(quote);
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
   return MathTanh(raw);
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

   return Clamp(norm, 0.5, 2.0);
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
   double raw = (m5 * 1.0 + m15 * 1.5 + h1 * 3.5 + h4 * 4.0) / 10.0;
   return (MathTanh(raw) + 1.0) * 5.0;
}

double ToDirectionalScore(double bullScore, int direction)
{
   if(direction == ORDER_TYPE_BUY)  return bullScore;
   if(direction == ORDER_TYPE_SELL) return 10.0 - bullScore;
   return 5.0;
}

double GetDynamicLotSize(double baseLot, double comp)
{
   if(!InpUseDynamicLot)
      return baseLot;

   double t = Normalize01(comp, InpMinScore, 10.0);
   double factor = InpMinLotFactor + (InpMaxLotFactor - InpMinLotFactor) * t;
   return baseLot * factor;
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

   p.slope = Clamp(p.slope, 0.0, 10.0);
   p.accel = Clamp(p.accel, 0.0, 10.0);
}



double GetATRValue(int atrHandle)
{
   if(atrHandle == INVALID_HANDLE)
      return 0.0;

   double buf[];
   ArraySetAsSeries(buf, true);

   if(CopyBuffer(atrHandle, 0, 0, 1, buf) < 1)
      return 0.0;

   return buf[0];
}

double ATRToPoints(string symbol, double atrPrice)
{
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(point <= 0.0)
      return 0.0;

   return atrPrice / point;
}

double ATRPercentOfPrice(string symbol, double atrPrice)
{
   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   if(bid <= 0.0)
      return 0.0;

   return (atrPrice / bid) * 100.0;
}

bool IsHighVolatility(string symbol, double atrPrice)
{
   if(!InpUseVolatilityFilter)
      return false;

   double atrPoints = ATRToPoints(symbol, atrPrice);
   if(InpMaxATRPoints > 0.0 && atrPoints > InpMaxATRPoints)
      return true;

   if(InpMaxATRPercentOfPrice > 0.0)
   {
      double atrPct = ATRPercentOfPrice(symbol, atrPrice);
      if(atrPct > InpMaxATRPercentOfPrice)
         return true;
   }

   return false;
}

void UpdatePairVolatility(PairData &pair)
{
   pair.atrValuePrice  = GetATRValue(pair.atrHandle);
   pair.atrValuePoints = ATRToPoints(pair.symbol, pair.atrValuePrice);
   pair.highVolatility = IsHighVolatility(pair.symbol, pair.atrValuePrice);
}

void ReleasePairHandles()
{
   for(int i = 0; i < ArraySize(Pairs); i++)
   {
      if(Pairs[i].rsiM1Handle != INVALID_HANDLE)
      {
         IndicatorRelease(Pairs[i].rsiM1Handle);
         Pairs[i].rsiM1Handle = INVALID_HANDLE;
      }

      if(Pairs[i].bbM1Handle != INVALID_HANDLE)
      {
         IndicatorRelease(Pairs[i].bbM1Handle);
         Pairs[i].bbM1Handle = INVALID_HANDLE;
      }

      if(Pairs[i].atrM5Handle != INVALID_HANDLE)
      {
         IndicatorRelease(Pairs[i].atrM5Handle);
         Pairs[i].atrM5Handle = INVALID_HANDLE;
      }

      if(Pairs[i].atrM15Handle != INVALID_HANDLE)
      {
         IndicatorRelease(Pairs[i].atrM15Handle);
         Pairs[i].atrM15Handle = INVALID_HANDLE;
      }

      if(Pairs[i].atrH1Handle != INVALID_HANDLE)
      {
         IndicatorRelease(Pairs[i].atrH1Handle);
         Pairs[i].atrH1Handle = INVALID_HANDLE;
      }

      if(Pairs[i].atrH4Handle != INVALID_HANDLE)
      {
         IndicatorRelease(Pairs[i].atrH4Handle);
         Pairs[i].atrH4Handle = INVALID_HANDLE;
      }

      if(Pairs[i].atrHandle != INVALID_HANDLE)
      {
         IndicatorRelease(Pairs[i].atrHandle);
         Pairs[i].atrHandle = INVALID_HANDLE;
      }
   }
}

void InitPairs()
{
   int total = ArraySize(Symbols);
   PairSize = total;
   ArrayResize(Pairs, total);

   for(int i = 0; i < total; i++)
   {
      Pairs[i].symbol = InpPrefix + Symbols[i] + InpSuffix;
      SymbolSelect(Pairs[i].symbol, true);

      Pairs[i].index = 0;
      Pairs[i].filled = false;
      ArrayInitialize(Pairs[i].history, 0.0);

      Pairs[i].rsiM1Handle = iRSI(Pairs[i].symbol, PERIOD_M5, 14, PRICE_CLOSE);
      Pairs[i].bbM1Handle  = iBands(Pairs[i].symbol, PERIOD_M5, 20, 0, 2, PRICE_CLOSE);

      double initialLot = InpInitialLot;
      if(InpUseAutoLot)
         initialLot = CalculateLotSize(Pairs[i].symbol, InpBalancePerLot);

      Pairs[i].buyGrid = new GridManager(Pairs[i].symbol, GRID_BUY, initialLot, InpGapPoints, InpProfitPercent, InpMaxOrders);
      Pairs[i].buyGrid.SetGridMagicNumber(InpMagicBuy + i);
      Pairs[i].buyGrid.SetGridMultiplier(InpGridMultiplier);
      Pairs[i].buyGrid.SetGridMaxDD(InpMaxDD);

      Pairs[i].sellGrid = new GridManager(Pairs[i].symbol, GRID_SELL, initialLot, InpGapPoints, InpProfitPercent, InpMaxOrders);
      Pairs[i].sellGrid.SetGridMagicNumber(InpMagicSell + i);
      Pairs[i].sellGrid.SetGridMultiplier(InpGridMultiplier);
      Pairs[i].sellGrid.SetGridMaxDD(InpMaxDD);

      Pairs[i].atrM5Handle  = iATR(Pairs[i].symbol, PERIOD_M5, 14);
      Pairs[i].atrM15Handle = iATR(Pairs[i].symbol, PERIOD_M15, 14);
      Pairs[i].atrH1Handle  = iATR(Pairs[i].symbol, PERIOD_H1, 14);
      Pairs[i].atrH4Handle  = iATR(Pairs[i].symbol, PERIOD_H4, 14);

      Pairs[i].filtersValid = false;
      Pairs[i].rsiM1        = 0.0;
      Pairs[i].bbUpperM1    = 0.0;
      Pairs[i].bbLowerM1    = 0.0;
      Pairs[i].rsiBuyOk     = false;
      Pairs[i].rsiSellOk    = false;
      Pairs[i].bbBuyOk      = false;
      Pairs[i].bbSellOk     = false;

      Pairs[i].eligibleNow = false;
      Pairs[i].stateText   = "WAIT";
      Pairs[i].stateColor  = tmdSilver;
      Pairs[i].dotColor    = tmdSilver;

      Pairs[i].needsFilterRefresh = false;
      Pairs[i].structurallyValid  = false;

      Pairs[i].sM5 = 0.0;
      Pairs[i].sM15 = 0.0;
      Pairs[i].sH1 = 0.0;
      Pairs[i].sH4 = 0.0;
      Pairs[i].bullScore = 5.0;
      Pairs[i].signedStrength = 0.0;
      Pairs[i].atrNormM15 = 1.0;

      Pairs[i].marketOpen = false;
      Pairs[i].openCount  = 0;
      Pairs[i].openLots   = 0.0;
      
      Pairs[i].atrHandle = iATR(Pairs[i].symbol, InpVolatilityTF, InpATRPeriod);
      Pairs[i].atrValuePoints = 0.0;
      Pairs[i].atrValuePrice  = 0.0;
      Pairs[i].highVolatility = false;
      
      Pairs[i].mondayGapBias = GAP_NONE;
      Pairs[i].mondayGapDay  = -1;
      
      Pairs[i].trendH1 = FLATTREND;
      Pairs[i].trendH4 = FLATTREND;
      
      if(Pairs[i].atrHandle == INVALID_HANDLE)
      {
         Print("Failed to create ATR handle for ", Pairs[i].symbol);
      }
      
   }
}

void UpdateAllPairs()
{
   ArrayInitialize(currencyStrength, 0.0);

   int counts[8];
   ArrayInitialize(counts, 0);

   for(int i = 0; i < PairSize; i++)
   {
      Pairs[i].marketOpen = CheckMarketOpen(Pairs[i].symbol);

      Pairs[i].sM5  = GetStrengthFast(Pairs[i].symbol, PERIOD_M5,  Pairs[i].atrM5Handle);
      Pairs[i].sM15 = GetStrengthFast(Pairs[i].symbol, PERIOD_M15, Pairs[i].atrM15Handle);
      Pairs[i].sH1  = GetStrengthFast(Pairs[i].symbol, PERIOD_H1,  Pairs[i].atrH1Handle);
      Pairs[i].sH4  = GetStrengthFast(Pairs[i].symbol, PERIOD_H4,  Pairs[i].atrH4Handle);

      Pairs[i].direction      = GetDirectionFromStrengths(Pairs[i].sH1, Pairs[i].sH4, Pairs[i].sM15);
      Pairs[i].bullScore      = GetBullScoreFromStrengths(Pairs[i].sM5, Pairs[i].sM15, Pairs[i].sH1, Pairs[i].sH4);
      Pairs[i].signedStrength = Pairs[i].bullScore - 5.0;
      Pairs[i].score          = ToDirectionalScore(Pairs[i].bullScore, Pairs[i].direction);
      Pairs[i].atrNormM15     = GetATRNormalizedFast(Pairs[i].symbol, Pairs[i].atrM15Handle, PERIOD_M15);
      
      Pairs[i].trendH1 = (int) GetH1Trend(Pairs[i].symbol);
      Pairs[i].trendH4 = (int) GetH4Trend(Pairs[i].symbol);
            
      UpdatePairVolatility(Pairs[i]);

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
      Pairs[i].currencyScore = Clamp(curScore, 0.0, 10.0);

      Pairs[i].aligned =
         (Pairs[i].direction == ORDER_TYPE_BUY  && baseStr > quoteStr) ||
         (Pairs[i].direction == ORDER_TYPE_SELL && quoteStr > baseStr);
      
      Pairs[i].trendAligned = true;
      
      double compRaw =
         Pairs[i].score         * 3.0 +
         Pairs[i].slope         * 2.5 +
         Pairs[i].accel         * 1.5 +
         Pairs[i].currencyScore * 3.0;

      Pairs[i].comp = Clamp(compRaw / 10.0, 0.0, 10.0);
   }

   UpdateRiskOffState();
}

void RefreshPositionCaches()
{
   for(int i = 0; i < PairSize; i++)
   {
      Pairs[i].openCount = 0;
      Pairs[i].openLots  = 0.0;
   }

   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      string sym = PositionGetString(POSITION_SYMBOL);
      double vol = PositionGetDouble(POSITION_VOLUME);

      for(int j = 0; j < PairSize; j++)
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

bool HasActiveGrid(PairData &p)
{
   return (p.buyGrid.CountPositions() > 0 || p.sellGrid.CountPositions() > 0);
}

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

string DirectionToText(int dir)
{
   if(dir == ORDER_TYPE_BUY)  return "BUY ";
   if(dir == ORDER_TYPE_SELL) return "SELL";
   return "----";
}

color DirectionToColor(int dir)
{
   if(dir == ORDER_TYPE_BUY)  return tmdGreen;
   if(dir == ORDER_TYPE_SELL) return tmdRed;
   return tmdSilver;
}

// Strength Filters

bool GetLastClosedM5(string symbol, MqlRates &bar1, MqlRates &bar2)
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);

   if(CopyRates(symbol, PERIOD_M5, 1, 2, rates) < 2)
      return false;

   bar1 = rates[0];
   bar2 = rates[1];
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

   Pairs[idx].rsiM1 = rsiBuf[0];

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

      Pairs[idx].bbBuyOk  = (bar2.close < bbLower[1]);
      Pairs[idx].bbSellOk = (bar2.close > bbUpper[1]);
   }
   else
   {
      Pairs[idx].bbUpperM1 = 0.0;
      Pairs[idx].bbLowerM1 = 0.0;
      Pairs[idx].bbBuyOk   = true;
      Pairs[idx].bbSellOk  = true;
   }

   Pairs[idx].rsiBuyOk  = (rsiBuf[1] < InpBuyRsi  && rsiBuf[0] > rsiBuf[1]);
   Pairs[idx].rsiSellOk = (rsiBuf[1] > InpSellRsi && rsiBuf[0] < rsiBuf[1]);

   Pairs[idx].filtersValid = true;
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
   if(!Pairs[idx].trendAligned)
      return false;
   if(Pairs[idx].comp < InpMinScore)
      return false;
   if(Pairs[idx].accel < InpMinAccel)
      return false;
   if(Pairs[idx].accel >= 9.9)
      //return false;
   if(Pairs[idx].slope >= 9.9)
      //return false;
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

void RefreshAllPairFilterCaches()
{
   for(int i = 0; i < PairSize; i++)
   {
      bool hasLive    = HasActiveGrid(Pairs[i]);
      bool structural = IsPairStructurallyValid(i);

      Pairs[i].structurallyValid  = structural;
      Pairs[i].needsFilterRefresh = (structural || hasLive);

      if(Pairs[i].needsFilterRefresh)
         RefreshPairFilterCache(i);
      else
         InvalidatePairFilterCache(i);
   }
}

bool IsPairEligibleNow(int idx)
{
   if(idx < 0 || idx >= PairSize)
      return false;

   Pairs[idx].waitReason = "";

   if(!Pairs[idx].structurallyValid)
      return false;

   if(IsBlockedByMondayGap(Pairs[idx], Pairs[idx].direction))
   {
      Pairs[idx].waitReason = "MON GAP";
      return false;
   }
   if(!Pairs[idx].filtersValid)
   {
      Pairs[idx].waitReason = "LOAD";
      return false;
   }

   string riskReason = "";
   if(!AllowNewRiskEntry(idx, riskReason))
   {
      Pairs[idx].waitReason = riskReason;
      return false;
   }

   if(Pairs[idx].direction == ORDER_TYPE_BUY)
   {
      if(Pairs[idx].buyGrid.CountPositions() > 0)
      {
         Pairs[idx].waitReason = "IN BUY";
         return false;
      }

      if(!CanOpenGrid(Pairs[idx].symbol, true))
      {
         Pairs[idx].waitReason = "NO BUY";
         return false;
      }

      return true;
   }

   if(Pairs[idx].direction == ORDER_TYPE_SELL)
   {
      if(Pairs[idx].sellGrid.CountPositions() > 0)
      {
         Pairs[idx].waitReason = "IN SELL";
         return false;
      }

      if(!CanOpenGrid(Pairs[idx].symbol, false))
      {
         Pairs[idx].waitReason = "NO SELL";
         return false;
      }

      return true;
   }

   return false;
}




// Strength Signals

bool GetRSITurn(int handle, double &rsi1, double &rsi2)
{
   double rsi[];
   ArraySetAsSeries(rsi, true);

   if(CopyBuffer(handle, 0, 1, 2, rsi) < 2)
      return false;

   rsi1 = rsi[0];
   rsi2 = rsi[1];
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
      bool bearConfirm = IsBearishConfirmCandle(Pairs[idx].symbol);
      return (rsiTurn && bbReentry && bearConfirm);
   }

   return false;
}

bool IsBuyTrendInvalidated(int idx)
{
   if(idx < 0 || idx >= PairSize)
      return false;

   if(Pairs[idx].buyGrid.CountPositions() <= 0)
      return false;

   if(Pairs[idx].direction == ORDER_TYPE_SELL)
      return true;

   return false;
}

bool IsSellTrendInvalidated(int idx)
{
   if(idx < 0 || idx >= PairSize)
      return false;

   if(Pairs[idx].sellGrid.CountPositions() <= 0)
      return false;

   if(Pairs[idx].direction == ORDER_TYPE_BUY)
      return true;

   return false;
}

bool IsPairTrendInvalidatedForExpansion(int idx, bool isBuyGrid)
{
   if(idx < 0 || idx >= PairSize)
      return true;

   if(isBuyGrid && Pairs[idx].direction == ORDER_TYPE_SELL)
      return true;
   if(!isBuyGrid && Pairs[idx].direction == ORDER_TYPE_BUY)
      return true;

   return false;
}
// Risk Metrics

double GetAccountDDPercent()
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);

   return MathMax(0.0, SafeDiv(balance - equity, balance, 0.0) * 100.0);
}

double GetEquityDDPercent()
{
   return GetAccountDDPercent();
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

   return MathMax(0.0, SafeDiv(gPeakEquity - eq, gPeakEquity, 0.0) * 100.0);
}

double GetFreeMarginPercent()
{
   double equity     = AccountInfoDouble(ACCOUNT_EQUITY);
   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);

   return SafeDiv(freeMargin, equity, 0.0) * 100.0;
}

double GetMarginLevelPercent()
{
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double margin = AccountInfoDouble(ACCOUNT_MARGIN);

   return SafeDiv(equity, margin, 0.0) * 100.0;
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

double GetDynamicMaxTotalLots()
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);

   if(InpBaseBalanceForMaxLots <= 0.0)
      return InpBaseMaxTotalLots;

   double maxLots = (balance / InpBaseBalanceForMaxLots) * InpBaseMaxTotalLots;

   if(InpHardMaxTotalLots > 0.0)
      maxLots = Clamp(maxLots, InpMinMaxTotalLots, InpHardMaxTotalLots);
   else
      maxLots = MathMax(maxLots, InpMinMaxTotalLots);

   return maxLots;
}

double GetDynamicTrendExitMinProfit()
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);

   if(InpBaseBalanceForTrendExitProfit <= 0.0)
      return InpBaseTrendExitMinProfit;

   double minProfit = (balance / InpBaseBalanceForTrendExitProfit) * InpBaseTrendExitMinProfit;

   if(InpMaxTrendExitProfit > 0.0)
      minProfit = Clamp(minProfit, InpMinTrendExitProfit, InpMaxTrendExitProfit);
   else
      minProfit = MathMax(minProfit, InpMinTrendExitProfit);

   return minProfit;
}
int GetGridMagicNumber(const int idx, const bool isBuyGrid)
{
   if(idx < 0 || idx >= PairSize)
      return -1;

   return isBuyGrid ? (InpMagicBuy + idx) : (InpMagicSell + idx);
}

datetime GetOldestGridOpenTime(const int idx, const bool isBuyGrid)
{
   if(idx < 0 || idx >= PairSize)
      return 0;

   string symbol = Pairs[idx].symbol;
   int    magic  = GetGridMagicNumber(idx, isBuyGrid);

   if(symbol == "" || magic < 0)
      return 0;

   datetime oldest = 0;

   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      string posSymbol = PositionGetString(POSITION_SYMBOL);
      long   posMagic  = PositionGetInteger(POSITION_MAGIC);
      long   posType   = PositionGetInteger(POSITION_TYPE);

      if(posSymbol != symbol)
         continue;

      if((int)posMagic != magic)
         continue;

      if(isBuyGrid && posType != POSITION_TYPE_BUY)
         continue;

      if(!isBuyGrid && posType != POSITION_TYPE_SELL)
         continue;

      datetime posTime = (datetime)PositionGetInteger(POSITION_TIME);

      if(oldest == 0 || posTime < oldest)
         oldest = posTime;
   }

   return oldest;
}

double GetGridAgeDays(const int idx, const bool isBuyGrid)
{
   datetime oldest = GetOldestGridOpenTime(idx, isBuyGrid);
   if(oldest <= 0)
      return 0.0;

   return (double)(TimeCurrent() - oldest) / 86400.0;
}

double GetAllowedTimeExitThresholdMoney(const double ageDays)
{
   if(!InpUseTimeExit)
      return -DBL_MAX;

   if(InpGridTimeExitStartDays <= 0.0)
      return -DBL_MAX;

   if(ageDays < InpGridTimeExitStartDays)
      return -DBL_MAX;

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(balance <= 0.0)
      balance = AccountInfoDouble(ACCOUNT_EQUITY);

   if(balance <= 0.0)
      return 0.0;

   // Phase 1:
   // Once grid age >= StartDays, begin looking for exit,
   // but for ProfitDays we only accept >= 0 money exit.
   double profitOnlyUntil = InpGridTimeExitStartDays + MathMax(0.0, InpGridTimeExitProfitDays);

   if(ageDays < profitOnlyUntil)
      return 0.0;

   // Phase 2:
   // After profit-only period, allow progressively larger loss.
   double stepDays = MathMax(0.1, InpGridTimeExitStepDays);
   double extraDays = ageDays - profitOnlyUntil;

   int steps = (int)MathFloor(extraDays / stepDays) + 1;
   if(steps < 1)
      steps = 1;

   double allowedLossPct = steps * MathMax(0.0, InpGridTimeExitLossStepPct);

   if(InpGridTimeExitMaxLossPct > 0.0)
      allowedLossPct = MathMin(allowedLossPct, InpGridTimeExitMaxLossPct);

   double allowedLossMoney = balance * allowedLossPct / 100.0;

   return -allowedLossMoney;
}

bool ShouldExitGridByTime(const int idx,
                          const bool isBuyGrid,
                          const double pnl,
                          double &ageDays,
                          double &thresholdMoney,
                          string &reason)
{
   ageDays        = 0.0;
   thresholdMoney = 0.0;
   reason         = "";

   if(!InpUseTimeExit)
      return false;

   if(idx < 0 || idx >= PairSize)
      return false;

   int count = isBuyGrid ? Pairs[idx].buyGrid.CountPositions()
                         : Pairs[idx].sellGrid.CountPositions();

   if(count <= 0)
      return false;

   ageDays = GetGridAgeDays(idx, isBuyGrid);
   if(ageDays < InpGridTimeExitStartDays)
      return false;

   thresholdMoney = GetAllowedTimeExitThresholdMoney(ageDays);

   if(pnl >= thresholdMoney)
   {
      if(thresholdMoney >= 0.0)
         reason = "TIME EXIT PROFIT";
      else
         reason = "TIME EXIT LOSS";

      return true;
   }

   return false;
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
double GetSpreadPoints(string symbol)
{
   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);

   if(ask <= 0.0 || bid <= 0.0)
      return -1.0;

   return PriceToPoints(symbol, ask - bid);
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

string GetLeverageText()
{
   long lev = AccountInfoInteger(ACCOUNT_LEVERAGE);
   return "1:" + IntegerToString((int)lev);
}

string GetBrokerText()
{
   return AccountInfoString(ACCOUNT_COMPANY);
}

string GetAccountNameText()
{
   return AccountInfoString(ACCOUNT_NAME);
}

void GetTradeStats(int &wins, int &losses,
                   double &winRate,
                   double &profitFactor,
                   string &avgHoldText)
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
   wins = 0;
   losses = 0;
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

      bool isTradeDeal = (dealType == DEAL_TYPE_BUY || dealType == DEAL_TYPE_SELL);
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
            losses++;
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
   int holdCount = 0;

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

color GetFreeMarginColor(double freeMarginPct)
{
   int stopoutMode = (int)AccountInfoInteger(ACCOUNT_MARGIN_SO_MODE);
   double stopoutCall = AccountInfoDouble(ACCOUNT_MARGIN_SO_CALL);
   double stopoutSo   = AccountInfoDouble(ACCOUNT_MARGIN_SO_SO);

   if (freeMarginPct == 0) return tmdSilver;
   if(stopoutCall <= 0.0 && stopoutSo <= 0.0)
   {
      if(freeMarginPct < 25.0) return tmdRed;
      if(freeMarginPct < 50.0) return tmdOrange;
      return tmdGreen;
   }

   if(stopoutMode == ACCOUNT_STOPOUT_MODE_PERCENT)
   {
      double danger = stopoutSo;
      double warn   = MathMax(stopoutCall, danger * 1.5);

      if(freeMarginPct <= warn) return tmdRed;
      if(freeMarginPct <= warn * 1.5) return tmdOrange;
      return tmdGreen;
   }

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity <= 0.0)
      return tmdRed;

   double dangerPct = SafeDiv(stopoutSo, equity, 0.0) * 100.0;
   double warnPct   = SafeDiv(stopoutCall, equity, 0.0) * 100.0;

   if(warnPct <= 0.0)
      warnPct = dangerPct * 1.5;

   if(freeMarginPct <= warnPct) return tmdRed;
   if(freeMarginPct <= warnPct * 1.5) return tmdOrange;
   return tmdGreen;
}

color GetLotUsageColor(double lots)
{
   double maxLots = GetDynamicMaxTotalLots();

   if(maxLots <= 0.0)
      return tmdSilver;

   double ratio = SafeDiv(lots, maxLots, 0.0);

   if(ratio >= 1.0) return tmdRed;
   if(ratio >= 0.75) return tmdOrange;
   return tmdGreen;
}

color GetPositionUsageColor(int positions)
{
   if(InpMaxOrders <= 0)
      return tmdSilver;

   double ratio = SafeDiv((double)positions, (double)InpMaxOrders, 0.0);

   if(ratio >= 1.0) return tmdRed;
   if(ratio >= 0.75) return tmdOrange;
   return tmdGreen;
}

// Risk Protection

//+------------------------------------------------------------------+
//| Safe-haven currency helpers                                      |
//+------------------------------------------------------------------+
bool RP_IsJPYCurrency(const string ccy)
{
   return (ccy == "JPY");
}

bool RP_IsCHFCurrency(const string ccy)
{
   return (ccy == "CHF");
}

bool RP_IsSafeHavenCurrency(const string ccy)
{
   return (ccy == "JPY" || ccy == "CHF");
}

string RP_GetBaseCurrency(const string symbol)
{
   if(StringLen(symbol) < 6)
      return "";

   return StringSubstr(symbol, 0, 3);
}

string RP_GetQuoteCurrency(const string symbol)
{
   if(StringLen(symbol) < 6)
      return "";

   return StringSubstr(symbol, 3, 3);
}
//+------------------------------------------------------------------+
//| During risk-off, only allow entries that BUY JPY or CHF          |
//| BUY base  => ORDER_TYPE_BUY                                      |
//| BUY quote => ORDER_TYPE_SELL                                     |
//+------------------------------------------------------------------+
bool RP_IsCorrectRiskOffSafeHavenDirection(const string symbol,
                                           const int direction,
                                           const bool blockSafeHavenVsSafeHaven = true)
{
   string base  = RP_GetBaseCurrency(symbol);
   string quote = RP_GetQuoteCurrency(symbol);

   if(base == "" || quote == "")
      return false;

   // Not a CHF/JPY related pair -> no restriction from this rule
   if(!RP_IsSafeHavenCurrency(base) && !RP_IsSafeHavenCurrency(quote))
      return true;

   // Block CHFJPY/JPYCHF if desired
   if(blockSafeHavenVsSafeHaven && RP_IsSafeHavenVsSafeHavenPair(symbol))
      return false;

   // Safe haven on base -> must BUY
   if(RP_IsSafeHavenCurrency(base))
      return (direction == ORDER_TYPE_BUY);

   // Safe haven on quote -> must SELL
   if(RP_IsSafeHavenCurrency(quote))
      return (direction == ORDER_TYPE_SELL);

   return true;
}
//+------------------------------------------------------------------+
//| Extra entry filter for CHF/JPY pairs during risk-off             |
//+------------------------------------------------------------------+
bool RP_PassRiskOffDirectionalEntryFilter(const PairData &pair,
                                          const bool riskOffActive,
                                          const bool useFilter,
                                          const double minAccel,
                                          const double minComp,
                                          const bool blockSafeHavenVsSafeHaven,
                                          string &reason)
{
   reason = "";

   if(!useFilter)
      return true;

   if(!riskOffActive)
      return true;

   // Only applies to CHF / JPY related pairs
   if(!RP_IsJPYOrCHFPair(pair.symbol))
      return true;

   // Direction must buy the safe haven
   if(!RP_IsCorrectRiskOffSafeHavenDirection(pair.symbol,
                                             pair.direction,
                                             blockSafeHavenVsSafeHaven))
   {
      reason = "RiskOff dir blocked";
      return false;
   }

   // Stronger momentum requirement during risk-off
   if(MathAbs(pair.accel) < minAccel)
   {
      reason = "RiskOff accel low";
      return false;
   }

   // Optional stronger comp requirement during risk-off
   if(minComp > 0.0 && MathAbs(pair.comp) < minComp)
   {
      reason = "RiskOff comp low";
      return false;
   }

   return true;
}
string RP_GetRiskOffEntryRuleText(const PairData &pair, const bool riskOffActive)
{
   if(!riskOffActive)
      return "";

   if(!RP_IsJPYOrCHFPair(pair.symbol))
      return "";

   if(RP_IsSafeHavenVsSafeHavenPair(pair.symbol))
      return "SAFEHAVENx2";

   if(!RP_IsCorrectRiskOffSafeHavenDirection(pair.symbol, pair.direction, false))
      return "wrong RiskOff dir";

   return "RiskOff dir ok";
}
bool RP_IsJPYOrCHFPair(const string symbol)
{
   string base  = RP_GetBaseCurrency(symbol);
   string quote = RP_GetQuoteCurrency(symbol);

   return (RP_IsSafeHavenCurrency(base) || RP_IsSafeHavenCurrency(quote));
}

bool RP_IsSafeHavenVsSafeHavenPair(const string symbol)
{
   string base  = RP_GetBaseCurrency(symbol);
   string quote = RP_GetQuoteCurrency(symbol);

   return (RP_IsSafeHavenCurrency(base) && RP_IsSafeHavenCurrency(quote));
}

bool AllowGridExpansion()
{
   if(IsRiskOffBlockingExpansion())
      return false;

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
   if(!AllowGridExpansion())
      return false;

   if(idx < 0 || idx >= PairSize)
      return false;

   if(InpUseVolatilityFilter &&
      InpBlockExpansionOnHighVol == ON &&
      Pairs[idx].highVolatility)
      return false;

   int gridDirection = isBuyGrid ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(IsBlockedByMondayGap(Pairs[idx], gridDirection))
      return false;

   // Only hard-block if the model is clearly opposite AND stress is high
   if(Pairs[idx].adaptiveState >= AGS_STRESS)
   {
      if(IsPairTrendInvalidatedForExpansion(idx, isBuyGrid))
         return false;
   }

   // Soft throttle: skip every other add when damaged
   if(InpUseSoftAdverseRegime)
   {
      if(isBuyGrid && Pairs[idx].buySoftThrottle)
      {
         int cnt = Pairs[idx].buyGrid.CountPositions();
         if(cnt >= 2 && (cnt % 2 == 0))
            return false;
      }

      if(!isBuyGrid && Pairs[idx].sellSoftThrottle)
      {
         int cnt = Pairs[idx].sellGrid.CountPositions();
         if(cnt >= 2 && (cnt % 2 == 0))
            return false;
      }
   }

   return true;
}
color AdaptiveStateColor(AdaptiveGridState st)
{
   if(st == AGS_NORMAL)  return tmdGreen;
   if(st == AGS_CAUTION) return tmdOrange;
   if(st == AGS_STRESS)  return C'255,120,0';
   if(st == AGS_BLOCK)   return tmdRed;
   return tmdSilver;
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

bool IsSelectiveRiskOffEntryModeActive()
{
   if(!InpUseRiskOffDirectionalEntryFilter)
      return false;

   if(InpRiskOffMode == RISK_OFF_DISABLED)
      return false;

   return (gRiskOffActive || gRiskOffCooldown);
}

bool AllowNewRisk()
{
   if(!InpUseRiskProtection)
   {
      if(IsRiskOffBlockingNewEntries() && !IsSelectiveRiskOffEntryModeActive())
         return false;

      return true;
   }

   if(gEmergencyClose)
      return false;
   if(gFreezeNewEntries)
      return false;
   if(IsExposureTooHigh())
      return false;

   if(IsRiskOffBlockingNewEntries() && !IsSelectiveRiskOffEntryModeActive())
      return false;

   return true;
}

bool AllowNewRiskEntry(const int idx, string &reason)
{
   reason = "";

   if(idx < 0 || idx >= PairSize)
   {
      reason = "IDX";
      return false;
   }

   if(!AllowNewRisk())
   {
      if(gEmergencyClose)
         reason = "EMERG";
      else if(gFreezeNewEntries)
         reason = "FROZEN";
      else if(IsExposureTooHigh())
         reason = "EXPOS";
      else if(gRiskOffActive)
         reason = "RISKOFF";
      else if(gRiskOffCooldown)
         reason = "RO CD";
      else
         reason = "RISK";

      return false;
   }

   if(!IsSelectiveRiskOffEntryModeActive())
      return true;

   string roReason = "";
   if(!RP_PassRiskOffDirectionalEntryFilter(Pairs[idx],
                                            true,
                                            InpUseRiskOffDirectionalEntryFilter,
                                            InpRiskOffMinAccel,
                                            InpRiskOffMinComp,
                                            InpBlockSafeHavenVsSafeHaven,
                                            roReason))
   {
      if(roReason == "RiskOff dir blocked") reason = "RO DIR";
      else if(roReason == "RiskOff accel low") reason = "RO ACC";
      else if(roReason == "RiskOff comp low") reason = "RO CMP";
      else reason = "RISKOFF";
      return false;
   }

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
         else if(InpUseVolatilityFilter && InpBlockExpansionOnHighVol == ON)
            gRiskReasonText = "NO EXPAND VOL";
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

   if(gRiskOffActive)
   {
      gRiskStateText  = "RISK OFF";
      gRiskStateColor = tmdRed;

      if(IsSelectiveRiskOffEntryModeActive())
      {
         gEntryStateText  = "SAFE ONLY";
         gEntryStateColor = tmdOrange;
         gRiskReasonText  = "JPY/CHF ONLY";
         gRiskReasonColor = tmdOrange;
      }
      else
      {
         gEntryStateText  = "BLOCKED";
         gEntryStateColor = tmdRed;
         gRiskReasonText  = "MARKET SHOCK";
         gRiskReasonColor = tmdRed;
      }

      if(IsRiskOffBlockingExpansion())
      {
         gExpandStateText  = "BLOCKED";
         gExpandStateColor = tmdRed;
      }
   }
   else if(gRiskOffCooldown)
   {
      gRiskStateText  = "RISK OFF";
      gRiskStateColor = tmdOrange;

      if(IsSelectiveRiskOffEntryModeActive())
      {
         gEntryStateText  = "SAFE ONLY";
         gEntryStateColor = tmdOrange;
         gRiskReasonText  = "COOLDOWN JPY/CHF";
         gRiskReasonColor = tmdOrange;
      }
      else
      {
         gEntryStateText  = "BLOCKED";
         gEntryStateColor = tmdOrange;
         gRiskReasonText  = "COOLDOWN";
         gRiskReasonColor = tmdOrange;
      }

      if(IsRiskOffBlockingExpansion())
      {
         gExpandStateText  = "BLOCKED";
         gExpandStateColor = tmdOrange;
      }
   }
}

// Panel

string PanelName(string suffix)
{
   return PANEL_PREFIX + suffix;
}

void RegisterPanelObject(string name)
{
   int sz = ArraySize(gPanelObjects);
   ArrayResize(gPanelObjects, sz + 1);
   gPanelObjects[sz] = name;
}

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

string GetServerTimeText()
{
   return FormatTime(TimeCurrent());
}


void CreateTMDInfoPanel()
{
   if(!InpShowPanel)
      return;

   ArrayResize(gPanelObjects, 0);

   int bgW = 900;

   CreatePanelRect("BG", 20, 30, 900, 720, C'10,16,28', C'10,16,28');
   CreatePanelRect("TB", 23, 33, bgW - 6, 28, C'10,16,28', C'10,16,28');

   CreatePanelRect("S1", 30, 65, 880, 1, C'25,40,55', tmdBg);
   CreatePanelRect("S2", 30, 130, 880, 1, C'25,40,55', tmdBg);
   CreatePanelRect("S3", 30, 286, 880, 1, C'25,40,55', tmdBg);

   CreatePanelRect("SV1", 280, 150, 1, 128, C'25,40,55', tmdBg);
   CreatePanelRect("SV2", 470, 150, 1, 128, C'25,40,55', tmdBg);
   CreatePanelRect("SV3", 640, 150, 1, 128, C'25,40,55', tmdBg);

   CreatePanelLabel("ONLINE_DOT", 30, 40, 9, C'0,230,120', "●");
   CreatePanelLabel("ONLINE_TXT", 42, 41, 9, C'0,180,180', "ONLINE");
   CreatePanelLabel("SERVER_TXT", 100, 41, 9, tmdSilver, "--:--:--");
   CreatePanelLabel("TITLE", 470, 38, 11, C'0,230,230', "◆ T M D ◆", ANCHOR_UPPER);

   CreatePanelLabel("L1", 30, 72, 9, C'70,90,110', "BALANCE");
   CreatePanelLabel("V1", 185, 72, 9, tmdSilver, "-", ANCHOR_RIGHT_UPPER);
   CreatePanelLabel("L2", 30, 90, 9, C'70,90,110', "EQUITY");
   CreatePanelLabel("V2", 185, 90, 9, tmdSilver, "-", ANCHOR_RIGHT_UPPER);
   CreatePanelLabel("L3", 30, 108, 9, C'70,90,110', "P / L");
   CreatePanelLabel("V3", 185, 108, 9, tmdSilver, "-", ANCHOR_RIGHT_UPPER);

   CreatePanelLabel("L4", 230, 72, 9, C'70,90,110', "ACCOUNT");
   CreatePanelLabel("V4", 515, 72, 9, tmdSilver, "-", ANCHOR_RIGHT_UPPER);
   CreatePanelLabel("L5", 230, 90, 9, C'70,90,110', "BROKER");
   CreatePanelLabel("V5", 515, 90, 9, tmdSilver, "-", ANCHOR_RIGHT_UPPER);
   CreatePanelLabel("L6", 230, 108, 9, C'70,90,110', "LEVERAGE");
   CreatePanelLabel("V6", 515, 108, 9, tmdSilver, "-", ANCHOR_RIGHT_UPPER);

   CreatePanelLabel("L7", 560, 72, 9, C'70,90,110', "DD");
   CreatePanelLabel("V7", 760, 72, 9, tmdSilver, "-", ANCHOR_RIGHT_UPPER);
   CreatePanelLabel("L8", 560, 90, 9, C'70,90,110', "FREE MARGIN");
   CreatePanelLabel("V8", 760, 90, 9, tmdSilver, "-", ANCHOR_RIGHT_UPPER);
   CreatePanelLabel("L9", 560, 108, 9, C'70,90,110', "MARGIN %");
   CreatePanelLabel("V9", 760, 108, 9, tmdSilver, "-", ANCHOR_RIGHT_UPPER);

   CreatePanelLabel("CUR_HDR", 30, 138, 9, C'180,40,220', "CURRENCIES");
   CreatePanelLabel("CUR_HDR2", 210, 138, 8, C'70,90,110', "STRENGTH", ANCHOR_RIGHT_UPPER);

   CreatePanelLabel("CURM_L1", 300, 138, 8, C'70,90,110', "WINS");
   CreatePanelLabel("CURM_V1", 455, 138, 8, tmdSilver, "-", ANCHOR_RIGHT_UPPER);
   
   CreatePanelLabel("CURM_L2", 300, 153, 8, C'70,90,110', "LOSSES");
   CreatePanelLabel("CURM_V2", 455, 153, 8, tmdSilver, "-", ANCHOR_RIGHT_UPPER);
   
   CreatePanelLabel("CURM_L3", 300, 168, 8, C'70,90,110', "WIN RATE");
   CreatePanelLabel("CURM_V3", 455, 168, 8, tmdSilver, "-", ANCHOR_RIGHT_UPPER);
   
   CreatePanelLabel("CURM_L4", 300, 183, 8, C'70,90,110', "PROFIT FACTOR");
   CreatePanelLabel("CURM_V4", 455, 183, 8, tmdSilver, "-", ANCHOR_RIGHT_UPPER);
   
   CreatePanelLabel("CURM_L5", 300, 198, 8, C'70,90,110', "AVG HOLD");
   CreatePanelLabel("CURM_V5", 455, 198, 8, tmdSilver, "-", ANCHOR_RIGHT_UPPER);
   CreatePanelLabel("CURM_L6", 300, 213, 8, C'70,90,110', "OPEN ORDERS");
   CreatePanelLabel("CURM_V6", 455, 213, 8, tmdSilver, "-", ANCHOR_RIGHT_UPPER);
   CreatePanelLabel("CURM_L7", 300, 228, 8, C'70,90,110', "MAX TOTAL ORDERS");
   CreatePanelLabel("CURM_V7", 455, 228, 8, tmdSilver, "-", ANCHOR_RIGHT_UPPER);
   CreatePanelLabel("CURM_L8", 300, 243, 8, C'70,90,110', "OPEN LOTS");
   CreatePanelLabel("CURM_V8", 455, 243, 8, tmdSilver, "-", ANCHOR_RIGHT_UPPER);
   CreatePanelLabel("CURM_L9", 300, 258, 8, C'70,90,110', "MAX LOTS DYN");
   CreatePanelLabel("CURM_V9", 455, 258, 8, tmdSilver, "-", ANCHOR_RIGHT_UPPER);

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
   CreatePanelLabel("CFG_L6", 490, 213, 8, C'70,90,110', "MAX GRID ORDERS");
   CreatePanelLabel("CFG_V6", 620, 213, 8, tmdSilver, "-", ANCHOR_RIGHT_UPPER);
   CreatePanelLabel("CFG_L7", 490, 228, 8, C'70,90,110', "LOT MODE");
   CreatePanelLabel("CFG_V7", 620, 228, 8, tmdSilver, "-", ANCHOR_RIGHT_UPPER);
   CreatePanelLabel("CFG_L8", 490, 243, 8, C'70,90,110', "LOT BALANCE");
   CreatePanelLabel("CFG_V8", 620, 243, 8, tmdSilver, "-", ANCHOR_RIGHT_UPPER);

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
      CreatePanelLabel("CUR_L_" + IntegerToString(i), 30, y, 9, tmdSilver, "-");
      CreatePanelLabel("CUR_V_" + IntegerToString(i), 210, y, 9, tmdSilver, "-", ANCHOR_RIGHT_UPPER);
   }

CreatePanelLabel("SYM_HDR",   30, 294, 9, C'0,230,230', "Symbols");
CreatePanelLabel("SYM_COL1", 255, 294, 8, C'70,90,110', "COMP",  ANCHOR_RIGHT_UPPER);
CreatePanelLabel("SYM_COL2", 315, 294, 8, C'70,90,110', "SCORE", ANCHOR_RIGHT_UPPER);
CreatePanelLabel("SYM_COL3", 375, 294, 8, C'70,90,110', "ACC",   ANCHOR_RIGHT_UPPER);
CreatePanelLabel("SYM_COL8", 435, 294, 8, C'70,90,110', "RSI",   ANCHOR_RIGHT_UPPER);
CreatePanelLabel("SYM_COL10",490, 294, 8, C'70,90,110', "SPR",   ANCHOR_RIGHT_UPPER);
CreatePanelLabel("SYM_COL6", 530, 294, 8, C'70,90,110', "FLT");
CreatePanelLabel("SYM_COL11",585, 294, 8, C'70,90,110', "H1/H4");
CreatePanelLabel("SYM_COL9", 650, 294, 8, C'70,90,110', "STATE");
CreatePanelLabel("SYM_COL4", 725, 294, 8, C'70,90,110', "ORD",   ANCHOR_RIGHT_UPPER);
CreatePanelLabel("SYM_COL7", 790, 294, 8, C'70,90,110', "LOTS",  ANCHOR_RIGHT_UPPER);
CreatePanelLabel("SYM_COL5", 865, 294, 8, C'70,90,110', "P/L",   ANCHOR_RIGHT_UPPER);

for(int i = 0; i < PANEL_SYM_ROWS; i++)
{
   int y = 314 + i * 14;

   CreatePanelLabel("SYM_DOT_" + IntegerToString(i), 30,  y, 8, tmdSilver, "●");
   CreatePanelLabel("SYM_A_"   + IntegerToString(i), 42,  y, 8, tmdSilver, "-");
   CreatePanelLabel("SYM_B_"   + IntegerToString(i), 255, y, 8, tmdSilver, "-", ANCHOR_RIGHT_UPPER);
   CreatePanelLabel("SYM_C_"   + IntegerToString(i), 315, y, 8, tmdSilver, "-", ANCHOR_RIGHT_UPPER);
   CreatePanelLabel("SYM_D_"   + IntegerToString(i), 375, y, 8, tmdSilver, "-", ANCHOR_RIGHT_UPPER);
   CreatePanelLabel("SYM_I_"   + IntegerToString(i), 435, y, 8, tmdSilver, "-", ANCHOR_RIGHT_UPPER);
   CreatePanelLabel("SYM_K_"   + IntegerToString(i), 490, y, 8, tmdSilver, "-", ANCHOR_RIGHT_UPPER); // spread
   CreatePanelLabel("SYM_G_"   + IntegerToString(i), 530, y, 8, tmdSilver, "-");
   CreatePanelLabel("SYM_L_"   + IntegerToString(i), 585, y, 8, tmdSilver, "-"); // H1/H4
   CreatePanelLabel("SYM_J_"   + IntegerToString(i), 650, y, 8, tmdSilver, "-");
   CreatePanelLabel("SYM_E_"   + IntegerToString(i), 725, y, 8, tmdSilver, "-", ANCHOR_RIGHT_UPPER);
   CreatePanelLabel("SYM_H_"   + IntegerToString(i), 790, y, 8, tmdSilver, "-", ANCHOR_RIGHT_UPPER);
   CreatePanelLabel("SYM_F_"   + IntegerToString(i), 865, y, 8, tmdSilver, "-", ANCHOR_RIGHT_UPPER);
}

   ChartRedraw();
}



void UpdateTMDInfoPanel()
{
   if(!InpShowPanel)
      return;

   bool eaOnline = IsEAOnline();

   SetPanelText("ONLINE_DOT", "●", eaOnline ? C'0,230,120' : tmdRed);
   SetPanelText("ONLINE_TXT", eaOnline ? "ONLINE" : "OFFLINE",
                eaOnline ? C'0,180,180' : tmdRed);
   SetPanelText("SERVER_TXT", GetServerTimeText(), tmdSilver);

   double balance    = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity     = AccountInfoDouble(ACCOUNT_EQUITY);
   double profit     = AccountInfoDouble(ACCOUNT_PROFIT);
   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double ddPct      = GetAccountDDPercent();
   double marginPct  = GetMarginLevelPercent();

   SetPanelText("V1", FormatMoney(balance), tmdSilver);
   SetPanelText("V2", FormatMoney(equity), tmdSilver);

   color pnlColor = tmdSilver;
   if(profit > 0.0) pnlColor = tmdGreen;
   else if(profit < 0.0) pnlColor = tmdRed;
   SetPanelText("V3", FormatMoney(profit), pnlColor);

   SetPanelText("V4", GetAccountNameText(), tmdSilver);
   SetPanelText("V5", GetBrokerText(), tmdSilver);
   SetPanelText("V6", GetLeverageText(), C'0,190,190');

   color ddClr = tmdGreen;
   if(ddPct >= 10.0) ddClr = tmdOrange;
   if(ddPct >= 20.0) ddClr = tmdRed;
   SetPanelText("V7", FormatPercent(ddPct, 2), ddClr);

   SetPanelText("V8", FormatMoney(freeMargin), tmdSilver);
   SetPanelText("V9", FormatPercent(marginPct, 2), GetFreeMarginColor(marginPct));

   int wins = 0;
   int losses = 0;
   double winRate = 0.0;
   double profitFactor = 0.0;
   string avgHoldText = "-";
   
   GetTradeStats(wins, losses, winRate, profitFactor, avgHoldText);

   int totalOpenOrders = PositionsTotal();
   double totalOpenLots = GetTotalOpenLots();

   color wrClr = tmdSilver;
   if(winRate >= 55.0) wrClr = tmdGreen;
   else if(winRate < 45.0) wrClr = tmdOrange;

   color pfClr = tmdSilver;
   if(profitFactor >= 1.5) pfClr = tmdGreen;
   else if(profitFactor < 1.0) pfClr = tmdRed;
   else pfClr = tmdOrange;

   color ordUsageClr = GetPositionUsageColor(totalOpenOrders);
   color lotUsageClr = GetLotUsageColor(totalOpenLots);

   SetPanelText("CURM_V1", IntegerToString(wins), tmdGreen);
   SetPanelText("CURM_V2", IntegerToString(losses), tmdRed);
   SetPanelText("CURM_V3", DoubleToString(winRate, 1) + "%", wrClr);
   SetPanelText("CURM_V4", DoubleToString(profitFactor, 2), pfClr);
   SetPanelText("CURM_V5", avgHoldText, C'0,190,190');
   SetPanelText("CURM_V6", IntegerToString(totalOpenOrders), ordUsageClr);
   SetPanelText("CURM_V7", IntegerToString(InpMaxTotalPositions), ordUsageClr);
   SetPanelText("CURM_V8", FormatLots(totalOpenLots), lotUsageClr);
   SetPanelText("CURM_V9", FormatLots(GetDynamicMaxTotalLots()), lotUsageClr);

   SetPanelText("CFG_V1", FormatDouble(InpMinScore, 1), tmdSilver);
   SetPanelText("CFG_V2", FormatDouble(InpBuyRsi, 1), tmdSilver);
   SetPanelText("CFG_V3", FormatDouble(InpSellRsi, 1), tmdSilver);
   SetPanelText("CFG_V4", FormatPercent(InpProfitPercent, 2), tmdSilver);
   SetPanelText("CFG_V5", FormatPercent(InpMaxDD, 1), tmdSilver);
   SetPanelText("CFG_V6", IntegerToString(InpMaxOrders), tmdSilver);

   string lotMode = "FIXED";
   if(InpUseAutoLot && InpUseDynamicLot) lotMode = "AUTO+DYN";
   else if(InpUseAutoLot)                lotMode = "AUTO";
   else if(InpUseDynamicLot)             lotMode = "FIXED+DYN";

   SetPanelText("CFG_V7", lotMode, tmdSilver);
   SetPanelText("CFG_V8", FormatDouble(InpBalancePerLot, 0), tmdSilver);

   SetPanelText("RISK_V1", gRiskStateText,   gRiskStateColor);
   SetPanelText("RISK_V2", gEntryStateText,  gEntryStateColor);
   SetPanelText("RISK_V3", gExpandStateText, gExpandStateColor);
   SetPanelText("RISK_V4", gRiskReasonText,  gRiskReasonColor);

   for(int i = 0; i < PairSize; i++)
      RefreshPairVisualState(i);

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

         SetPanelText("CUR_L_" + IntegerToString(i), IntegerToString(i + 1) + ". " + Currencies[idx], c);
         SetPanelText("CUR_V_" + IntegerToString(i), FormatDouble(val, 2), c);
      }
      else
      {
         SetPanelText("CUR_L_" + IntegerToString(i), "-", tmdSilver);
         SetPanelText("CUR_V_" + IntegerToString(i), "-", tmdSilver);
      }
   }

   int sortedIdx[];
   GetSortedPairIndicesForPanel(sortedIdx);
   
   for(int i = 0; i < PANEL_SYM_ROWS; i++)
   {
      if(i < ArraySize(sortedIdx))
      {
         int p = sortedIdx[i];
   
         string dirTxt = DirectionToText(Pairs[p].direction);
         color  dirClr = DirectionToColor(Pairs[p].direction);
   
         string stateTxt = Pairs[p].stateText;
         color  stateClr = Pairs[p].stateColor;
         color  dotClr   = Pairs[p].dotColor;
   
         int    openOrders = Pairs[p].openCount;
         double openLots   = Pairs[p].openLots;
         double gridPnl    = GetPairGridPnL(Pairs[p]);
         
         double spreadPts = GetSpreadPoints(Pairs[p].symbol);
   
         color pnlClr = tmdSilver;
         if(gridPnl > 0.0) pnlClr = tmdGreen;
         else if(gridPnl < 0.0) pnlClr = tmdRed;
         
         color spreadClr = tmdSilver;

         if(spreadPts < 0.0)
         {
            spreadClr = tmdSilver;
         }
         else if(InpMaxSpreadPoints > 0.0)
         {
            if(spreadPts <= InpMaxSpreadPoints * 0.75)
               spreadClr = tmdGreen;
            else if(spreadPts <= InpMaxSpreadPoints)
               spreadClr = tmdOrange;
            else
               spreadClr = tmdRed;
         }
   
         string pairText  = Pairs[p].symbol + " " + dirTxt;
         string filterTxt = PairFilterText(p);
         color  filterClr = PairFilterColor(p);
         
         string trendTxt = TrendComboText(p);
         color  trendClr = TrendComboColor(p);
   
         if(Pairs[p].buyGrid.CountPositions() > 0 && IsPairExpansionFrozen(p, true))
         {
            filterTxt = "EXP OFF";
            filterClr = tmdOrange;
         }
         else if(Pairs[p].sellGrid.CountPositions() > 0 && IsPairExpansionFrozen(p, false))
         {
            filterTxt = "EXP OFF";
            filterClr = tmdOrange;
         }
   
         color rsiClr = tmdSilver;
         if(Pairs[p].filtersValid)
         {
            if(Pairs[p].direction == ORDER_TYPE_BUY)
               rsiClr = Pairs[p].rsiBuyOk ? tmdGreen : tmdOrange;
            else if(Pairs[p].direction == ORDER_TYPE_SELL)
               rsiClr = Pairs[p].rsiSellOk ? tmdGreen : tmdOrange;
         }
   
SetPanelText("SYM_DOT_" + IntegerToString(i), "●", dotClr);
SetPanelText("SYM_A_"   + IntegerToString(i), pairText, dirClr);
SetPanelText("SYM_B_"   + IntegerToString(i), FormatDouble(Pairs[p].comp, 1),
             (Pairs[p].comp >= InpMinScore ? tmdGreen : tmdOrange));
SetPanelText("SYM_C_"   + IntegerToString(i), FormatDouble(Pairs[p].score, 1),
             (Pairs[p].score >= 6.0 ? C'0,190,190' : tmdSilver));
SetPanelText("SYM_D_"   + IntegerToString(i), FormatDouble(Pairs[p].accel, 1),
             (Pairs[p].accel >= 5.5 ? tmdGreen : (Pairs[p].accel <= 4.5 ? tmdOrange : tmdSilver)));
SetPanelText("SYM_I_"   + IntegerToString(i),
             (Pairs[p].filtersValid ? FormatDouble(Pairs[p].rsiM1, 1) : "-"),
             rsiClr);

SetPanelText("SYM_K_"   + IntegerToString(i),
             (spreadPts >= 0.0 ? FormatDouble(spreadPts, 1) : "-"),
             spreadClr);

SetPanelText("SYM_G_"   + IntegerToString(i), filterTxt, filterClr);
SetPanelText("SYM_L_"   + IntegerToString(i), trendTxt, trendClr);
SetPanelText("SYM_J_"   + IntegerToString(i), stateTxt, stateClr);
SetPanelText("SYM_E_"   + IntegerToString(i), IntegerToString(openOrders),
             (openOrders > 0 ? C'0,230,230' : tmdSilver));
SetPanelText("SYM_H_"   + IntegerToString(i), FormatLots(openLots),
             (openLots > 0.0 ? C'0,230,230' : tmdSilver));
SetPanelText("SYM_F_"   + IntegerToString(i), FormatMoney(gridPnl), pnlClr);
      }
      else
      {
SetPanelText("SYM_DOT_" + IntegerToString(i), "●", tmdSilver);
SetPanelText("SYM_A_"   + IntegerToString(i), "-", tmdSilver);
SetPanelText("SYM_B_"   + IntegerToString(i), "-", tmdSilver);
SetPanelText("SYM_C_"   + IntegerToString(i), "-", tmdSilver);
SetPanelText("SYM_D_"   + IntegerToString(i), "-", tmdSilver);
SetPanelText("SYM_I_"   + IntegerToString(i), "-", tmdSilver);
SetPanelText("SYM_K_"   + IntegerToString(i), "-", tmdSilver);
SetPanelText("SYM_G_"   + IntegerToString(i), "-", tmdSilver);
SetPanelText("SYM_L_"   + IntegerToString(i), "-", tmdSilver);
SetPanelText("SYM_J_"   + IntegerToString(i), "-", tmdSilver);
SetPanelText("SYM_E_"   + IntegerToString(i), "-", tmdSilver);
SetPanelText("SYM_H_"   + IntegerToString(i), "-", tmdSilver);
SetPanelText("SYM_F_"   + IntegerToString(i), "-", tmdSilver);
      }
   }

   ChartRedraw();
}


double GetPairGridPnL(PairData &p)
{
   return p.buyGrid.GridPnL() + p.sellGrid.GridPnL();
}

int GetPanelSortRank(int idx)
{
   if(idx < 0 || idx >= PairSize)
      return 99;

   if(HasActiveGrid(Pairs[idx]))
      return 0;

   if(IsPairEligibleNow(idx))
      return 1;

   return 2;
}

void GetSortedPairIndicesForPanel(int &indices[])
{
   int total = ArraySize(Pairs);
   ArrayResize(indices, total);

   for(int i = 0; i < total; i++)
      indices[i] = i;

   for(int i = 0; i < total - 1; i++)
   {
      for(int j = i + 1; j < total; j++)
      {
         int ia = indices[i];
         int ib = indices[j];

         int rankA = GetPanelSortRank(ia);
         int rankB = GetPanelSortRank(ib);

         bool doSwap = false;

         // 1) Primary sort: LIVE -> READY -> WAIT
         if(rankB < rankA)
         {
            doSwap = true;
         }
         // 2) Inside same bucket
         else if(rankA == rankB)
         {
            // LIVE bucket: sort by PnL descending, then alphabetically
            if(rankA == 0)
            {
               double pnlA = GetPairGridPnL(Pairs[ia]);
               double pnlB = GetPairGridPnL(Pairs[ib]);

               if(pnlB > pnlA)
               {
                  doSwap = true;
               }
               else if(pnlA == pnlB)
               {
                  string symA = Pairs[ia].symbol;
                  string symB = Pairs[ib].symbol;

                  if(StringCompare(symA, symB) > 0)
                     doSwap = true;
               }
            }
            // READY / WAIT: alphabetical
            else
            {
               string symA = Pairs[ia].symbol;
               string symB = Pairs[ib].symbol;

               if(StringCompare(symA, symB) > 0)
                  doSwap = true;
            }
         }

         if(doSwap)
         {
            int tmp = indices[i];
            indices[i] = indices[j];
            indices[j] = tmp;
         }
      }
   }
}

void RefreshPairVisualState(int idx)
{
   if(idx < 0 || idx >= PairSize)
      return;

   bool hasLive  = HasActiveGrid(Pairs[idx]);
   bool eligible = false;

   if(!hasLive)
      eligible = IsPairEligibleNow(idx);

   Pairs[idx].eligibleNow = eligible;

   if(hasLive)
   {
      Pairs[idx].stateText  = "LIVE";
      Pairs[idx].stateColor = C'0,230,230';
      Pairs[idx].dotColor   = C'0,230,230';

      if(Pairs[idx].buyGrid.CountPositions() > 0)
         Pairs[idx].stateText = "BUY";

      if(Pairs[idx].sellGrid.CountPositions() > 0)
      {
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

   if(Pairs[idx].waitReason == "RO DIR" ||
      Pairs[idx].waitReason == "RO ACC" ||
      Pairs[idx].waitReason == "RO CMP" ||
      Pairs[idx].waitReason == "RISKOFF" ||
      Pairs[idx].waitReason == "RO CD")
   {
      Pairs[idx].stateText  = "RO";
      Pairs[idx].stateColor = (Pairs[idx].waitReason == "RO DIR" || Pairs[idx].waitReason == "RISKOFF") ? tmdRed : tmdOrange;
      Pairs[idx].dotColor   = Pairs[idx].stateColor;
      return;
   }
if(Pairs[idx].waitReason == "MON GAP")
{
   if(Pairs[idx].mondayGapBias == GAP_BULL)
      Pairs[idx].stateText = "GAP↑";
   else if(Pairs[idx].mondayGapBias == GAP_BEAR)
      Pairs[idx].stateText = "GAP↓";
   else
      Pairs[idx].stateText = "GAP";

   Pairs[idx].stateColor = tmdOrange;
   Pairs[idx].dotColor   = tmdOrange;
   return;
}

if(Pairs[idx].direction != -1 && !Pairs[idx].trendAligned)
{
   Pairs[idx].stateText  = "TRND";
   Pairs[idx].stateColor = tmdRed;
   Pairs[idx].dotColor   = tmdRed;
   return;
}
   if(Pairs[idx].highVolatility)
   {
      Pairs[idx].stateText  = "VOL";
      Pairs[idx].stateColor = tmdOrange;
      Pairs[idx].dotColor   = tmdOrange;
      return;
   }

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

string PairFilterText(int idx)
{
   if(idx < 0 || idx >= PairSize)
      return "-";

   if(!brokerWindowOpen)
      return "BROKER";

   if(!Pairs[idx].marketOpen)
      return "CLOSED";

   if(Pairs[idx].direction == -1)
      return "NO DIR";

   if(!Pairs[idx].aligned)
      return "CUR MIS";

   if(!Pairs[idx].trendAligned)
      return "TREND";

   if(Pairs[idx].comp < InpMinScore)
      return "COMP";

   if(Pairs[idx].accel < InpMinAccel)
      return "ACC";

   if(InpUseRiskProtection)
   {
      if(gEmergencyClose)
         return "EMERG";
      if(gFreezeNewEntries)
         return "FROZEN";
      if(IsExposureTooHigh())
         return "EXPOS";
      if(!SpreadAcceptable(Pairs[idx].symbol, InpMaxSpreadPoints))
         return "SPREAD";
   }

   if(!Pairs[idx].filtersValid)
      return "LOAD";
      
   if(Pairs[idx].adaptiveState == AGS_BLOCK)
      return "AD BLOCK";

   if(Pairs[idx].adaptiveState == AGS_STRESS)
      return "AD STR";

   if(Pairs[idx].adaptiveState == AGS_CAUTION)
      return "AD CAUT";
      
   if(Pairs[idx].waitReason == "RO DIR" ||
      Pairs[idx].waitReason == "RO ACC" ||
      Pairs[idx].waitReason == "RO CMP" ||
      Pairs[idx].waitReason == "RISKOFF" ||
      Pairs[idx].waitReason == "RO CD")
      return Pairs[idx].waitReason;

   if(Pairs[idx].waitReason == "MON GAP")
   {
      if(Pairs[idx].mondayGapBias == GAP_BULL)
         return "GAP BULL";
      if(Pairs[idx].mondayGapBias == GAP_BEAR)
         return "GAP BEAR";
      return "MON GAP";
   }

   if(HasEntryTrigger(idx))
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

   string txt = PairFilterText(idx);

   if(txt == "TRIG")    return tmdGreen;
   if(txt == "SET")     return C'0,190,190';
   if(txt == "RSI")     return C'0,190,190';
   if(txt == "BB")      return C'0,190,190';

   if(txt == "TREND")   return tmdRed;
   if(txt == "CUR MIS") return tmdOrange;
   if(txt == "ACC")     return tmdOrange;
   if(txt == "COMP")    return tmdOrange;
   if(txt == "SPREAD")  return tmdOrange;
   if(txt == "WAIT")    return tmdOrange;

   if(txt == "RO DIR")  return tmdRed;
   if(txt == "RO ACC")  return tmdOrange;
   if(txt == "RO CMP")  return tmdOrange;
   if(txt == "RISKOFF") return tmdRed;
   if(txt == "RO CD")   return tmdOrange;

   if(txt == "EMERG")   return tmdRed;
   if(txt == "FROZEN")  return tmdOrange;
   if(txt == "EXPOS")   return tmdOrange;
   if(txt == "MON GAP") return tmdOrange;
   if(txt == "GAP BULL") return tmdOrange;
   if(txt == "GAP BEAR") return tmdOrange;

   if(txt == "BROKER")  return tmdSilver;
   if(txt == "CLOSED")  return tmdSilver;
   if(txt == "NO DIR")  return tmdSilver;
   if(txt == "LOAD")    return tmdOrange;
   if(txt == "N/A")     return tmdSilver;
   
   if(txt == "AD CAUT")  return tmdOrange;
   if(txt == "AD STR")   return C'255,120,0';
   if(txt == "AD BLOCK") return tmdRed;

   return tmdSilver;
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

   int sortedIdx[];
   GetSortedPairIndicesForPanel(sortedIdx);

   if(row >= ArraySize(sortedIdx))
      return;

   int p = sortedIdx[row];
   string sym = Pairs[p].symbol;

   if(sym == "")
      return;

   if(Symbol() != sym)
      ChartSetSymbolPeriod(0, sym, (ENUM_TIMEFRAMES)Period());
}

// Utils

//+------------------------------------------------------------------+
//| BASIC MATH HELPERS                                               |
//+------------------------------------------------------------------+

double Clamp(double value, double minVal, double maxVal)
{
   if(value < minVal) return minVal;
   if(value > maxVal) return maxVal;
   return value;
}

double SafeDiv(double num, double den, double fallback = 0.0)
{
   if(den == 0.0)
      return fallback;
   return num / den;
}

double Normalize01(double value, double minVal, double maxVal)
{
   if(maxVal - minVal == 0.0)
      return 0.0;

   return Clamp((value - minVal) / (maxVal - minVal), 0.0, 1.0);
}

double MapToRange(double value, double inMin, double inMax, double outMin, double outMax)
{
   double t = Normalize01(value, inMin, inMax);
   return outMin + (outMax - outMin) * t;
}

// Fast tanh wrapper (consistent usage everywhere)
double TanhScaled(double value, double scale = 1.0)
{
   return MathTanh(value * scale);
}

//+------------------------------------------------------------------+
//| PRICE / LOT HELPERS                                              |
//+------------------------------------------------------------------+

double PointsToPrice(string symbol, double points)
{
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   return points * point;
}

double PriceToPoints(string symbol, double priceDiff)
{
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(point <= 0.0)
      return 0.0;

   return priceDiff / point;
}

double NormalizeLot(string symbol, double lots)
{
   double step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   double min  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double max  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);

   if(step <= 0.0) step = 0.01;
   if(min <= 0.0)  min  = step;
   if(max <= 0.0)  max  = 100.0;

   lots = MathFloor(lots / step) * step;

   if(lots < min) lots = min;
   if(lots > max) lots = max;

   return lots;
}

//+------------------------------------------------------------------+
//| FORMATTING HELPERS                                               |
//+------------------------------------------------------------------+

string FormatDouble(double value, int digits = 2)
{
   return DoubleToString(value, digits);
}

string FormatMoney(double value)
{
   return DoubleToString(value, 2);
}

string FormatLots(double lots)
{
   return DoubleToString(lots, 2);
}

string FormatPercent(double value, int digits = 1)
{
   return DoubleToString(value, digits) + "%";
}

string FormatSigned(double value, int digits = 2)
{
   if(value > 0)
      return "+" + DoubleToString(value, digits);
   return DoubleToString(value, digits);
}

//+------------------------------------------------------------------+
//| COLOR HELPERS                                                    |
//+------------------------------------------------------------------+

color ColorBySign(double value, color positive, color negative, color neutral)
{
   if(value > 0.0) return positive;
   if(value < 0.0) return negative;
   return neutral;
}

color ColorByThreshold(double value, double low, double high, color lowClr, color midClr, color highClr)
{
   if(value >= high) return highClr;
   if(value <= low)  return lowClr;
   return midClr;
}

color BlendColor(color c1, color c2, double t)
{
   t = Clamp(t, 0.0, 1.0);

   int r1 = (int)(c1 & 0xFF);
   int g1 = (int)((c1 >> 8) & 0xFF);
   int b1 = (int)((c1 >> 16) & 0xFF);

   int r2 = (int)(c2 & 0xFF);
   int g2 = (int)((c2 >> 8) & 0xFF);
   int b2 = (int)((c2 >> 16) & 0xFF);

   int r = (int)(r1 + (r2 - r1) * t);
   int g = (int)(g1 + (g2 - g1) * t);
   int b = (int)(b1 + (b2 - b1) * t);

   return (color)(r | (g << 8) | (b << 16));
}

//+------------------------------------------------------------------+
//| STRING HELPERS                                                   |
//+------------------------------------------------------------------+

string ToUpper(string s)
{
   StringToUpper(s);
   return s;
}

bool StringStartsWith(string text, string prefix)
{
   if(StringLen(text) < StringLen(prefix))
      return false;

   return (StringSubstr(text, 0, StringLen(prefix)) == prefix);
}

bool StringEndsWith(string text, string suffix)
{
   int lenText = StringLen(text);
   int lenSuf  = StringLen(suffix);

   if(lenText < lenSuf)
      return false;

   return (StringSubstr(text, lenText - lenSuf, lenSuf) == suffix);
}

//+------------------------------------------------------------------+
//| TIME HELPERS                                                     |
//+------------------------------------------------------------------+

string FormatTime(datetime t)
{
   MqlDateTime dt;
   TimeToStruct(t, dt);

   string hh = (dt.hour < 10 ? "0" : "") + IntegerToString(dt.hour);
   string mm = (dt.min  < 10 ? "0" : "") + IntegerToString(dt.min);
   string ss = (dt.sec  < 10 ? "0" : "") + IntegerToString(dt.sec);

   return hh + ":" + mm + ":" + ss;
}

bool IsNewBar(string symbol, ENUM_TIMEFRAMES tf, datetime &lastTime)
{
   datetime t = iTime(symbol, tf, 0);
   if(t != lastTime)
   {
      lastTime = t;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| DEBUG HELPERS                                                    |
//+------------------------------------------------------------------+

void DebugPrint(string msg, bool enabled = true)
{
   if(enabled)
      Print("[TMD] ", msg);
}

void DebugValue(string label, double value, int digits = 2, bool enabled = true)
{
   if(enabled)
      Print("[TMD] ", label, ": ", DoubleToString(value, digits));
}


// RiskOff

void UpdateRiskOffState()
{
   if(InpRiskOffMode == RISK_OFF_DISABLED)
   {
      gRiskOffActive   = false;
      gRiskOffCooldown = false;
      return;
   }

   gRiskOffActive = gRiskOff.Update(
      currencyStrength,
      Pairs,
      PairSize,
      InpRiskOffSlopeThreshold,
      InpRiskOffAccelThreshold,
      InpMinScore,
      3, // JPY
      4, // CHF
      5, // AUD
      6, // NZD
      7, // CAD
      InpRiskOffUseCHF,
      InpRiskOffUseVolatility,
      InpRiskOffATRSpikeRatio,
      InpRiskOffVolTF,
      InpRiskOffATRPeriod,
      InpRiskOffMinAlignedPairs,
      InpRiskOffMinJpyPairs,
      InpRiskOffUseAtrSymbol,
      InpRiskOffAtrSymbol,
      InpRiskOffScoreTrigger
   );

   gRiskOffCooldown = gRiskOff.InCooldown(InpRiskOffCooldownSec);
}

bool IsRiskOffBlockingNewEntries()
{
   if(InpRiskOffMode == RISK_OFF_DISABLED)
      return false;

   return (gRiskOffActive || gRiskOffCooldown);
}

bool IsRiskOffBlockingExpansion()
{
   if(InpRiskOffMode < RISK_OFF_BLOCK_AND_STOP_EXPANSION)
      return false;

   return (gRiskOffActive || gRiskOffCooldown);
}

double GetPairProfitPercent(const int idx)
{
   double base = InpProfitPercent;

   if(idx < 0 || idx >= PairSize)
      return base;

   if(Pairs[idx].comp >= 8.5 && Pairs[idx].score >= 7.2)
      return base * 1.30;

   if(Pairs[idx].comp >= 7.8 && Pairs[idx].score >= 6.9)
      return base * 1.15;

   return base;
}


void GetTopPairs(int &selected[])
{
   ArrayResize(selected, 0);

   int targetCount = InpTopPairsCount;
   if(targetCount <= 0)
      return;

   for(int pick = 0; pick < targetCount; pick++)
   {
      int    bestIdx   = -1;
      double bestScore = -999999.0;

      for(int i = 0; i < PairSize; i++)
      {
         if(Pairs[i].direction == -1 || !Pairs[i].aligned)
            continue;

         if(IsIndexInArray(i, selected))
            continue;

         if(!PassesSoftOverlapLimit(i, selected))
            continue;

         double rawRank   = GetEntryRankScore(i);
         if(rawRank < 0.0)
            continue;

         double penalty   = GetOverlapPenaltyScore(i, selected);
         double finalRank = rawRank - penalty;

         if(bestIdx == -1 || finalRank > bestScore)
         {
            bestIdx   = i;
            bestScore = finalRank;
         }
      }

      if(bestIdx == -1)
         break;

      int n = ArraySize(selected);
      ArrayResize(selected, n + 1);
      selected[n] = bestIdx;
   }
}

bool IsTopPairSelected(const int idx, const int &selected[])
{
   return IsIndexInArray(idx, selected);
}




double GetEntryRankScore(const int idx)
{
   if(idx < 0 || idx >= PairSize)
      return -1.0;

   if(Pairs[idx].direction == -1)
      return -1.0;

   if(!Pairs[idx].aligned)
      return -1.0;

   return
      Pairs[idx].score         * 0.40 +
      Pairs[idx].slope         * 0.25 +
      Pairs[idx].accel         * 0.15 +
      Pairs[idx].currencyScore * 0.20;
}

bool IsIndexInArray(const int value, const int &arr[])
{
   for(int i = 0; i < ArraySize(arr); i++)
   {
      if(arr[i] == value)
         return true;
   }
   return false;
}

int CountCurrencyUsageInSelected(const string currency, const int &selected[])
{
   if(currency == "")
      return 0;

   int count = 0;

   for(int i = 0; i < ArraySize(selected); i++)
   {
      int idx = selected[i];
      if(idx < 0 || idx >= PairSize)
         continue;

      string base  = StringSubstr(Pairs[idx].symbol, 0, 3);
      string quote = StringSubstr(Pairs[idx].symbol, 3, 3);

      if(base == currency)
         count++;
      if(quote == currency)
         count++;
   }

   return count;
}

double GetOverlapPenaltyScore(const int idx, const int &selected[])
{
   if(idx < 0 || idx >= PairSize)
      return 999.0;

   string base  = StringSubstr(Pairs[idx].symbol, 0, 3);
   string quote = StringSubstr(Pairs[idx].symbol, 3, 3);

   int baseUse  = CountCurrencyUsageInSelected(base, selected);
   int quoteUse = CountCurrencyUsageInSelected(quote, selected);

   return (baseUse + quoteUse) * InpOverlapPenaltyPerSide;
}

bool PassesSoftOverlapLimit(const int idx, const int &selected[])
{
   if(idx < 0 || idx >= PairSize)
      return false;

   if(InpMaxCurrencyReuseInTop <= 0)
      return true;

   string base  = StringSubstr(Pairs[idx].symbol, 0, 3);
   string quote = StringSubstr(Pairs[idx].symbol, 3, 3);

   int baseUse  = CountCurrencyUsageInSelected(base, selected);
   int quoteUse = CountCurrencyUsageInSelected(quote, selected);

   if(baseUse >= InpMaxCurrencyReuseInTop)
      return false;

   if(quoteUse >= InpMaxCurrencyReuseInTop)
      return false;

   return true;
}

GapBias DetectMondayGapBias(const string symbol, const double minPoints)
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);

   // Fetch enough H1 bars to safely cover Friday -> Monday transition
   int copied = CopyRates(symbol, PERIOD_H1, 0, 400, rates);
   if(copied < 30)
      return GAP_NONE;

   int mondayIdx = -1;
   int fridayIdx = -1;

   // ------------------------------------------------------------
   // Find the FIRST Monday bar after a non-Monday bar
   // With series array:
   // rates[0] = newest, larger index = older
   // So iterate old -> new to catch the weekend transition cleanly
   // ------------------------------------------------------------
   for(int i = copied - 2; i >= 0; i--)
   {
      MqlDateTime curDt, prevDt;
      TimeToStruct(rates[i].time,     curDt);
      TimeToStruct(rates[i + 1].time, prevDt);

      // Transition into Monday
      if(curDt.day_of_week == 1 && prevDt.day_of_week != 1)
      {
         mondayIdx = i;
         break;
      }
   }

   if(mondayIdx == -1)
      return GAP_NONE;

   // ------------------------------------------------------------
   // Walk backward in older history from that Monday bar
   // until we find the LAST Friday bar before the weekend
   // ------------------------------------------------------------
   for(int j = mondayIdx + 1; j < copied; j++)
   {
      MqlDateTime dt;
      TimeToStruct(rates[j].time, dt);

      if(dt.day_of_week == 5) // Friday
      {
         fridayIdx = j;
         break;
      }
   }

   if(fridayIdx == -1)
      return GAP_NONE;

   double mondayOpen  = rates[mondayIdx].open;
   double fridayClose = rates[fridayIdx].close;

   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(point <= 0.0)
      return GAP_NONE;

   double gapPoints = (mondayOpen - fridayClose) / point;

   Print("MONDAY GAP DETECT: ", symbol,
         " | MondayOpen=", DoubleToString(mondayOpen, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS)),
         " | FridayClose=", DoubleToString(fridayClose, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS)),
         " | GapPoints=", DoubleToString(gapPoints, 1),
         " | Threshold=", DoubleToString(minPoints, 1));

   if(gapPoints >= minPoints)
      return GAP_BULL;

   if(gapPoints <= -minPoints)
      return GAP_BEAR;

   return GAP_NONE;
}
void UpdateMondayGapFilterForPair(PairData &p)
{
   if(!InpUseMondayGapFilter)
   {
      p.mondayGapBias = GAP_NONE;
      p.mondayGapDay  = -1;
      return;
   }

   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now);

   // Only active on Monday. Reset on other days.
   if(now.day_of_week != 1)
   {
      if(p.mondayGapBias != GAP_NONE || p.mondayGapDay != -1)
      {
         p.mondayGapBias = GAP_NONE;
         p.mondayGapDay  = -1;
      }
      return;
   }

   // Only calculate once per Monday
   if(p.mondayGapDay == now.day)
      return;

   p.mondayGapBias = DetectMondayGapBias(p.symbol, InpMondayGapMinPoints);
   p.mondayGapDay  = now.day;

   Print("MONDAY GAP UPDATE: ", p.symbol,
         " | Day=", IntegerToString(now.day),
         " | Bias=", IntegerToString((int)p.mondayGapBias));
}

bool IsBlockedByMondayGap(const PairData &p, const int direction)
{
   if(!InpUseMondayGapFilter)
      return false;

   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now);

   // Monday only, no carry-over to Tuesday
   if(now.day_of_week != 1)
      return false;

   if(p.mondayGapBias == GAP_BULL && direction == ORDER_TYPE_SELL)
   {
      //Print("MONDAY GAP BLOCK SELL: ", p.symbol);
      return true;
   }

   if(p.mondayGapBias == GAP_BEAR && direction == ORDER_TYPE_BUY)
   {
      //Print("MONDAY GAP BLOCK BUY: ", p.symbol);
      return true;
   }

   return false;
}