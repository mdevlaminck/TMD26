//+------------------------------------------------------------------+
//|                                                        TMD18.mq5 |
//|                                                              MDV |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "MDV"
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <TMD/TMD_All.mqh>

CTrade trade;

string gPanelObjects[];
double currencyStrength[8];
PairData Pairs[];

RiskOffEngine gRiskOff;
bool gRiskOffActive = false;
bool gRiskOffCooldown = false;

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
   if(id == CHARTEVENT_CLICK)
   {
      int x = (int)lparam;
      int y = (int)dparam;
      HandleTMDPanelChartClick(x, y);
   }
}