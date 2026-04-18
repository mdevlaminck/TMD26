//+------------------------------------------------------------------+
//|                                                        TMD22.mq5 |
//|                                                              MDV |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "MDV"
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Trade/Trade.mqh>

#include <TMD2/Utils.mqh>
#include <TMD2/GridManager.mqh>
#include <TMD2/ChartStyle.mqh>
#include <TMD2/Structs.mqh>
#include <TMD2/Config.mqh>
#include <TMD2/Trend.mqh>
#include <TMD2/PairData.mqh>
#include <TMD2/RiskOffEngine.mqh>
#include <TMD2/Globals.mqh>
#include <TMD2/PortfolioPressure.mqh>
#include <TMD2/EntryThrottle.mqh>
#include <TMD2/Panel.mqh>
#include <TMD2/MarketRegime.mqh>
#include <TMD2/SoftBasketSurvivability.mqh>
#include <TMD2/AdaptiveGridState.mqh>
#include <TMD2/PersistentInvalidation.mqh>
#include <TMD2/Groups.mqh>
#include <TMD2/Triggers.mqh>
#include <TMD2/EntryExit.mqh>
#include <TMD2/RiskProtection.mqh>


RiskOffEngine gRiskOff;
GroupState gGroupStates[5];
PairData Pairs[];

int OnInit()
{
   TesterHideIndicators(true);

   StyleChart();
   InitPairs();
   UpdateAllPairs();
   ResetEntryThrottleWindow();

   CreateTMDInfoPanel();
   UpdateTMDInfoPanel();

   gPeakEquity       = AccountInfoDouble(ACCOUNT_EQUITY);

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
         UpdateAllPairs();
         UpdateMarketRegimeState();
         UpdateSoftAdverseBasketState();
   }

   // New M5
   if(newM5)
   {
      RefreshPositionCaches();
      RefreshGroupStates();
      RefreshAllPairFilterCaches();
      // refresh current decision-layer fields before exits/entries
      UpdateMarketRegimeState();
      UpdateSoftAdverseBasketState();
 
      CheckExit();
      CheckEntry();
   }
   
   // New M1
   // New M1
   if (newM1) {
      currentPnL = 0.0;
      brokerWindowOpen = IsBrokerTradeWindow();
      UpdatePeakEquity();

      // Pass 1: refresh basket damage inputs from current live baskets
      for(int i = 0; i < PairSize; i++)
         UpdateWorstBasketPnLState(i);

      RefreshPositionCaches();
      RefreshGroupStates();
      EvaluatePortfolioPressureState();

      // Pass 2: apply live expansion policy and update grids
      for(int i = 0; i < PairSize; i++)
      {
         bool allowBuyExpansion  = AllowGridExpansion(i, true);
         bool allowSellExpansion = AllowGridExpansion(i, false);

         double buyBrake  = GetExpansionBrakeFactor(i, true);
         double sellBrake = GetExpansionBrakeFactor(i, false);

         Pairs[i].buyGrid.SetAllowExpansion(allowBuyExpansion);
         Pairs[i].sellGrid.SetAllowExpansion(allowSellExpansion);

         // Keep base grid multiplier unchanged
         Pairs[i].buyGrid.SetGridMultiplier(InpGridMultiplier);
         Pairs[i].sellGrid.SetGridMultiplier(InpGridMultiplier);

         // Live adaptive base gap from Patch 3
         Pairs[i].buyGrid.SetGridGap(GetLiveGapPoints(i, true));
         Pairs[i].sellGrid.SetGridGap(GetLiveGapPoints(i, false));

         // Separate expansion brake for live baskets
         Pairs[i].buyGrid.SetExpansionBrake(buyBrake);
         Pairs[i].sellGrid.SetExpansionBrake(sellBrake);

         Pairs[i].buyGrid.Update();
         currentPnL += Pairs[i].buyGrid.GridPnL();

         Pairs[i].sellGrid.Update();
         currentPnL += Pairs[i].sellGrid.GridPnL();
      }

      RefreshPositionCaches();
      RefreshGroupStates();
      EvaluatePortfolioPressureState();

      UpdateRiskPanelState();
      if(gEmergencyClose)
      {
         string reasonText = "UNKNOWN";

         double ddPct       = GetEquityDDPercent();
         double marginLevel = GetMarginLevelPercent();

         if(InpAccountEmergencyDDPct > 0.0 && ddPct >= InpAccountEmergencyDDPct)
            reasonText = "ACCOUNT DD HIT";
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




























