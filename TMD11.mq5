#property strict
#property version   "6.0"
#property description "Quantum Institutional Trading AI"

#include <Trade/Trade.mqh>

#include "engines/MarketRegimeAI.mqh"
#include "engines/SignalEngine.mqh"
#include "engines/ExecutionEngine.mqh"
#include "engines/RiskEngine.mqh"
#include "engines/PortfolioEngine.mqh"
#include "engines/ScalingEngine.mqh"
#include "engines/SmartTrailing.mqh"
#include "engines/NewsFilter.mqh"
#include "engines/SessionFilter.mqh"
#include "engines/DashboardUI.mqh"

CTrade trade;

string Symbols[] = {"EURUSD","GBPUSD","USDJPY","XAUUSD","AUDUSD","USDCAD","USDCHF","NZDUSD"};

int OnInit()
{
   InitDashboard();
   return INIT_SUCCEEDED;
}

void OnTick()
{
   if(!SessionAllowed()) return;
   if(HighImpactNews()) return;

   for(int i=0;i<ArraySize(Symbols);i++)
      ProcessSymbol(Symbols[i]);

   UpdateDashboard();
}

void ProcessSymbol(string sym)
{
   if(!PortfolioAllow(sym)) return;

   MarketRegime regime = DetectMarketRegime(sym);
   EntrySignal sig = GenerateSignal(sym, regime);

   if(sig.valid)
   {
      double lot = CalculateLot(sym, sig.slPoints);
      ExecuteSmartOrder(sym, sig, lot);
   }

   ManageTrades(sym);
}
