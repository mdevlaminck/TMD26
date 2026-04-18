//+------------------------------------------------------------------+
//|                                                     TMD_Lite.mq5 |
//|                                                              MDV |
//+------------------------------------------------------------------+
#property strict
#property version   "1.00"

#include <Trade/Trade.mqh>

#include <TMD_Lite/Config.mqh>
#include <TMD_Lite/Structs.mqh>
#include <TMD_Lite/Symbols.mqh>
#include <TMD_Lite/Utils.mqh>
#include <TMD_Lite/Trend.mqh>
#include <TMD_Lite/Strength.mqh>
#include <TMD_Lite/Exposure.mqh>
#include <TMD_Lite/Entry.mqh>
#include <TMD_Lite/Risk.mqh>
#include <TMD_Lite/GridManager.mqh>
#include <TMD_Lite/Exit.mqh>
#include <TMD_Lite/ChartStyle.mqh>
#include <TMD_Lite/Panel.mqh>

//+------------------------------------------------------------------+
//| Globals                                                          |
//+------------------------------------------------------------------+
CTrade         g_trade;
string         g_brokerSymbols[];
PairData       g_pairs[];
PortfolioStats g_stats;
DebugStats     g_debug;
int g_debugCycleCounter = 0;

datetime       g_lastStrengthBarTime = 0;
bool           g_strengthReady       = false;

//+------------------------------------------------------------------+
//| Logging helper                                                   |
//+------------------------------------------------------------------+
void LogMsg(const string msg)
{
   if(InpEnableLogging)
      Print("TMD_Lite: ", msg);
}
string BuildDebugSummary(const DebugStats &d, const PortfolioStats &s)
{
   string out = "DBG | ";

   out += "scan:" + IntegerToString(d.scannedPairs);

   out += " | blk T/S/P/T: "
       + IntegerToString(d.blockedTrend) + "/"
       + IntegerToString(d.blockedStrength) + "/"
       + IntegerToString(d.blockedPullback) + "/"
       + IntegerToString(d.blockedTrigger);

   out += " | blk X/R/M: "
       + IntegerToString(d.blockedExposure) + "/"
       + IntegerToString(d.blockedRisk) + "/"
       + IntegerToString(d.blockedSpread + d.blockedSession);

   out += " | ready B/S: "
       + IntegerToString(d.readyBuy) + "/"
       + IntegerToString(d.readySell);

   out += " | open/add: "
       + IntegerToString(d.openedBaskets) + "/"
       + IntegerToString(d.expandedBaskets);

   out += " | exit TP/HS/BE/CL: "
       + IntegerToString(d.exitTP) + "/"
       + IntegerToString(d.exitHardStop) + "/"
       + IntegerToString(d.exitStaleBE) + "/"
       + IntegerToString(d.exitControlledLoss);

   out += " | resc/em: "
       + IntegerToString(d.exitPortfolioRescue) + "/"
       + IntegerToString(d.exitEmergency);

   out += " | live pnl/dd/bsk/pos: "
       + DoubleToString(s.floatingPnl, 2) + "/"
       + DoubleToString(s.drawdownPct, 2) + "%/"
       + IntegerToString(s.totalBaskets) + "/"
       + IntegerToString(s.totalPositions);

   return out;
}
void MaybePrintDebugSummary()
{
   if(!InpEnableDebugSummary)
      return;

   g_debugCycleCounter++;

   if(g_debugCycleCounter < InpDebugPrintEveryN)
      return;

   g_debugCycleCounter = 0;

   UpdateRiskSnapshot(g_stats,
                      g_brokerSymbols,
                      InpFreezeDDPercent,
                      InpEmergencyDDPercent,
                      InpMinMarginLevelPct,
                      InpMagicBase,
                      InpFilterByMagicOnly);

   Print(BuildDebugSummary(g_debug, g_stats));
}

//+------------------------------------------------------------------+
//| Return true if broker symbol map is usable                       |
//+------------------------------------------------------------------+
bool ValidateBrokerSymbolMap(const string &brokerSymbols[])
{
   if(ArraySize(brokerSymbols) != TMD_LITE_SYMBOL_COUNT)
      return false;

   bool anyOk = false;

   for(int i = 0; i < ArraySize(brokerSymbols); i++)
   {
      if(brokerSymbols[i] == "")
      {
         Print("TMD_Lite: unresolved symbol for core ", TMD_SYMBOLS[i]);
         continue;
      }

      if(!EnsureSymbolReady(brokerSymbols[i]))
      {
         Print("TMD_Lite: symbol not ready ", brokerSymbols[i], " (core ", TMD_SYMBOLS[i], ")");
         continue;
      }

      anyOk = true;
   }

   return anyOk;
}

//+------------------------------------------------------------------+
//| First valid symbol for new-bar detection                         |
//+------------------------------------------------------------------+
string GetPrimaryMappedSymbol()
{
   for(int i = 0; i < ArraySize(g_brokerSymbols); i++)
   {
      if(g_brokerSymbols[i] != "")
         return g_brokerSymbols[i];
   }

   return "";
}

//+------------------------------------------------------------------+
//| Initialize pair array                                            |
//+------------------------------------------------------------------+
void InitializePairs()
{
   ArrayResize(g_pairs, TMD_LITE_SYMBOL_COUNT);

   for(int i = 0; i < TMD_LITE_SYMBOL_COUNT; i++)
   {
      g_pairs[i].symbol = g_brokerSymbols[i];
      g_pairs[i].base   = "";
      g_pairs[i].quote  = "";

      GetBaseQuoteCurrencies(g_pairs[i].symbol, g_pairs[i].base, g_pairs[i].quote);

      //--- trend
      g_pairs[i].trendDir        = TREND_NONE;
      g_pairs[i].trendValid      = false;
      g_pairs[i].trendFastEMA_H1 = 0.0;
      g_pairs[i].trendSlowEMA_H1 = 0.0;
      g_pairs[i].trendFastEMA_H4 = 0.0;
      g_pairs[i].trendSlowEMA_H4 = 0.0;

      //--- strength
      g_pairs[i].strengthBase     = 0.0;
      g_pairs[i].strengthQuote    = 0.0;
      g_pairs[i].strengthGap      = 0.0;
      g_pairs[i].strengthGapPrev  = 0.0;
      g_pairs[i].strengthGapDelta = 0.0;
      g_pairs[i].strengthBuyOk    = false;
      g_pairs[i].strengthSellOk   = false;

      //--- vol / spread
      g_pairs[i].atrM5         = 0.0;
      g_pairs[i].atrM15        = 0.0;
      g_pairs[i].spreadPoints  = 0.0;
      g_pairs[i].spreadToAtrM5 = 0.0;
      g_pairs[i].spreadOk      = false;

      //--- setup / trigger
      g_pairs[i].pullbackDepthAtr = 0.0;
      g_pairs[i].inPullbackZone   = false;
      g_pairs[i].setupState       = SETUP_NONE;
      g_pairs[i].triggerState     = TRIGGER_NONE;
      g_pairs[i].triggerBuy       = false;
      g_pairs[i].triggerSell      = false;

      //--- basket state
      g_pairs[i].hasBuyBasket  = false;
      g_pairs[i].hasSellBasket = false;
      g_pairs[i].buyOrders     = 0;
      g_pairs[i].sellOrders    = 0;
      g_pairs[i].buyLots       = 0.0;
      g_pairs[i].sellLots      = 0.0;
      g_pairs[i].buyProfit     = 0.0;
      g_pairs[i].sellProfit    = 0.0;
      g_pairs[i].buyAgeDays    = 0.0;
      g_pairs[i].sellAgeDays   = 0.0;

      //--- gates
      g_pairs[i].exposureBuyOk  = true;
      g_pairs[i].exposureSellOk = true;
      g_pairs[i].riskOk         = true;
      g_pairs[i].sessionOk      = true;

      //--- display
      g_pairs[i].basketState = BASKET_IDLE;
      g_pairs[i].stateText   = STATE_READY;
      g_pairs[i].blockReason = REASON_OK;
   }
}

//+------------------------------------------------------------------+
//| Refresh base/quote if needed                                     |
//+------------------------------------------------------------------+
void RefreshPairMetadata()
{
   for(int i = 0; i < ArraySize(g_pairs); i++)
   {
      if(g_pairs[i].symbol == "")
         continue;

      if(g_pairs[i].base == "" || g_pairs[i].quote == "")
         GetBaseQuoteCurrencies(g_pairs[i].symbol, g_pairs[i].base, g_pairs[i].quote);
   }
}

//+------------------------------------------------------------------+
//| Update strength only on a new strength timeframe bar             |
//+------------------------------------------------------------------+
void UpdateStrengthIfNeeded()
{
   string primarySymbol = GetPrimaryMappedSymbol();
   if(primarySymbol == "")
      return;

   bool newStrengthBar = IsNewBar(primarySymbol, InpStrengthTF, g_lastStrengthBarTime);

   // First call: initialize strength once
   if(!g_strengthReady)
   {
      UpdateCurrencyStrengths(g_brokerSymbols,
                              InpStrengthTF,
                              InpStrengthFastEMA,
                              InpStrengthSlowEMA,
                              InpStrengthATRPeriod,
                              InpStrengthLookbackBars);

      g_strengthReady = true;
      LogMsg("Initial strength snapshot built");
      return;
   }

   if(newStrengthBar)
   {
      UpdateCurrencyStrengths(g_brokerSymbols,
                              InpStrengthTF,
                              InpStrengthFastEMA,
                              InpStrengthSlowEMA,
                              InpStrengthATRPeriod,
                              InpStrengthLookbackBars);

      LogMsg("Strength updated on new bar");
   }
}

//+------------------------------------------------------------------+
//| Update all pair states                                           |
//+------------------------------------------------------------------+
void UpdateAllPairStates(const bool countDebug)
{
   UpdateRiskSnapshot(g_stats,
                      g_brokerSymbols,
                      InpFreezeDDPercent,
                      InpEmergencyDDPercent,
                      InpMinMarginLevelPct,
                      InpMagicBase,
                      InpFilterByMagicOnly);

   UpdateAllPairBasketStates(g_pairs, InpMagicBase, InpFilterByMagicOnly);

   for(int i = 0; i < ArraySize(g_pairs); i++)
   {
      if(g_pairs[i].symbol == "" || !EnsureSymbolReady(g_pairs[i].symbol))
         continue;

      g_pairs[i].basketState = BASKET_IDLE;
      g_pairs[i].stateText   = STATE_READY;
      g_pairs[i].blockReason = REASON_OK;

      UpdatePairTrend(g_pairs[i],
                      InpTrendTF1,
                      InpTrendTF2,
                      InpTrendFastEMA,
                      InpTrendSlowEMA,
                      InpRequireTrendSlope);

      UpdatePairStrength(g_pairs[i], InpMinStrengthGap);

      UpdatePairSpreadState(g_pairs[i],
                            InpTriggerTF,
                            InpATRPeriod,
                            InpMaxSpreadPointsFX,
                            InpMaxSpreadPointsMetal,
                            InpMaxSpreadToATR);

      UpdatePairSessionState(g_pairs[i],
                             InpBlockLateFriday,
                             InpBlockEarlyMonday,
                             InpBlockJuly,
                             InpBlockYearEnd);

      UpdatePairRiskState(g_pairs[i], g_stats);

      UpdatePairExposureState(g_pairs[i],
                              InpUseDirectionalCurrencyLock,
                              InpMagicBase,
                              InpFilterByMagicOnly);

      UpdatePairEntryState(g_pairs[i],
                           InpSetupTF,
                           InpTriggerTF,
                           InpPullbackEMAPeriod,
                           InpTriggerEMAPeriod,
                           InpATRPeriod,
                           InpMinPullbackATR,
                           InpMaxPullbackATR);
if(countDebug)
{
   g_debug.scannedPairs++;

   if(g_pairs[i].basketState == BASKET_BLOCKED_TREND)
      g_debug.blockedTrend++;
   else if(g_pairs[i].basketState == BASKET_BLOCKED_STRENGTH)
      g_debug.blockedStrength++;
   else if(g_pairs[i].basketState == BASKET_BLOCKED_PULLBACK)
      g_debug.blockedPullback++;
   else if(g_pairs[i].basketState == BASKET_BLOCKED_TRIGGER)
      g_debug.blockedTrigger++;
   else if(g_pairs[i].basketState == BASKET_BLOCKED_SPREAD)
      g_debug.blockedSpread++;
   else if(g_pairs[i].basketState == BASKET_BLOCKED_EXPOSURE)
      g_debug.blockedExposure++;
   else if(g_pairs[i].basketState == BASKET_BLOCKED_SESSION)
      g_debug.blockedSession++;
   else if(g_pairs[i].basketState == BASKET_BLOCKED_RISK)
      g_debug.blockedRisk++;

   if(g_pairs[i].stateText == STATE_TRG_BUY)
      g_debug.readyBuy++;
   else if(g_pairs[i].stateText == STATE_TRG_SELL)
      g_debug.readySell++;
}                   
   }
}

//+------------------------------------------------------------------+
//| Emergency close if needed                                        |
//+------------------------------------------------------------------+
void ProcessEmergencyIfNeeded()
{
   string reason = "Emergency close all";
   if(ProcessEmergencyClose(g_trade,
                            g_stats,
                            reason,
                            InpMagicBase,
                            InpFilterByMagicOnly))
   {
      g_debug.exitEmergency++;
      Print("CLOSE | ALL | reason=", ExitReasonToShortText(reason));
      LogMsg("Emergency close executed: " + reason);
   }
}

//+------------------------------------------------------------------+
//| Basket exits                                                     |
//+------------------------------------------------------------------+
void ProcessExitLayer()
{
   ProcessAllBasketExits(g_trade,
                         g_brokerSymbols,
                         InpBasketTargetPctBal,
                         InpBasketHardStopPctBal,
                         InpTimeExitStartDays,
                         InpMinOrdersForTimeExit,
                         InpLossAcceptDays,
                         InpAllowedLossClosePctBal,
                         g_debug,
                         InpMagicBase,
                         InpFilterByMagicOnly);

   string rescueReason = "";
   if(ProcessPortfolioNetRescue(g_trade,
                                g_brokerSymbols,
                                InpUsePortfolioNetExit,
                                InpPortfolioNetTargetPct,
                                InpTimeExitStartDays,
                                InpMinOrdersForTimeExit,
                                rescueReason,
                                InpMagicBase,
                                InpFilterByMagicOnly))
   {
      g_debug.exitPortfolioRescue++;
      LogMsg("Portfolio rescue executed: " + rescueReason);
   }
}

//+------------------------------------------------------------------+
//| Try opening new baskets                                          |
//+------------------------------------------------------------------+
void ProcessEntryLayer()
{
   for(int i = 0; i < ArraySize(g_pairs); i++)
   {
      if(g_pairs[i].symbol == "" || !EnsureSymbolReady(g_pairs[i].symbol))
         continue;

      EntryCandidate candidate;
      BuildEntryCandidate(g_pairs[i], candidate);

      if(!candidate.valid)
         continue;

      string reason = "";
      if(TryOpenInitialBasket(g_trade,
                              candidate,
                              InpUseAutoLot,
                              InpBalancePer001Lot,
                              InpFixedLot,
                              g_brokerSymbols,
                              g_stats,
                              InpMaxTotalPositions,
                              InpMaxTotalLots,
                              InpMaxBaskets,
                              InpBlockLateFriday,
                              InpBlockEarlyMonday,
                              InpBlockJuly,
                              InpBlockYearEnd,
                              InpMagicBase,
                              reason,
                              InpFilterByMagicOnly))
      {
         LogMsg("Initial basket opened: " + EntryCandidateToText(candidate));
         g_debug.openedBaskets++;
      }
      else
      {
         if(InpEnableLogging && reason != REASON_OK && reason != "") {
            //LogMsg("Entry blocked on " + g_pairs[i].symbol + ": " + reason);
         }
            
      }
   }
}

//+------------------------------------------------------------------+
//| Try expanding existing baskets                                   |
//+------------------------------------------------------------------+
void ProcessExpansionLayer()
{
   for(int i = 0; i < ArraySize(g_brokerSymbols); i++)
   {
      string symbol = g_brokerSymbols[i];
      if(symbol == "" || !EnsureSymbolReady(symbol))
         continue;

      BasketInfo buyBasket, sellBasket;
      bool hasBuy  = BuildBasketInfo(symbol, ORDER_TYPE_BUY,  buyBasket,  InpMagicBase, InpFilterByMagicOnly);
      bool hasSell = BuildBasketInfo(symbol, ORDER_TYPE_SELL, sellBasket, InpMagicBase, InpFilterByMagicOnly);

      string reason = "";

      if(hasBuy)
      {
         if(TryExpandBasket(g_trade,
                            buyBasket,
                            g_stats,
                            InpSetupTF,
                            InpATRPeriod,
                            InpGridStepATR,
                            InpMinSecondsBetweenAdds,
                            InpMaxOrdersPerBasket,
                            InpUseLotMultiplier,
                            InpLotMultiplier,
                            InpUseAutoLot,
                            InpBalancePer001Lot,
                            InpFixedLot,
                            InpMaxTotalLots,
                            InpBasketHardStopPctBal,
                            InpBlockLateFriday,
                            InpBlockEarlyMonday,
                            InpBlockJuly,
                            InpBlockYearEnd,
                            InpMagicBase,
                            reason))
         {
            g_debug.expandedBaskets++;

            BasketInfo buyBasketAfter;
            if(BuildBasketInfo(symbol, ORDER_TYPE_BUY, buyBasketAfter, InpMagicBase, InpFilterByMagicOnly))
               LogMsg("BUY basket expanded: " + BasketInfoToText(buyBasketAfter));
            else
               LogMsg("BUY basket expanded: " + BasketInfoToText(buyBasket));
         }
      }

      reason = "";

      if(hasSell)
      {
         if(TryExpandBasket(g_trade,
                            sellBasket,
                            g_stats,
                            InpSetupTF,
                            InpATRPeriod,
                            InpGridStepATR,
                            InpMinSecondsBetweenAdds,
                            InpMaxOrdersPerBasket,
                            InpUseLotMultiplier,
                            InpLotMultiplier,
                            InpUseAutoLot,
                            InpBalancePer001Lot,
                            InpFixedLot,
                            InpMaxTotalLots,
                            InpBasketHardStopPctBal,
                            InpBlockLateFriday,
                            InpBlockEarlyMonday,
                            InpBlockJuly,
                            InpBlockYearEnd,
                            InpMagicBase,
                            reason))
         {
            g_debug.expandedBaskets++;

            BasketInfo sellBasketAfter;
            if(BuildBasketInfo(symbol, ORDER_TYPE_SELL, sellBasketAfter, InpMagicBase, InpFilterByMagicOnly))
               LogMsg("SELL basket expanded: " + BasketInfoToText(sellBasketAfter));
            else
               LogMsg("SELL basket expanded: " + BasketInfoToText(sellBasket));
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Refresh panel                                                    |
//+------------------------------------------------------------------+
void RenderDashboard()
{
   UpdateRiskSnapshot(g_stats,
                      g_brokerSymbols,
                      InpFreezeDDPercent,
                      InpEmergencyDDPercent,
                      InpMinMarginLevelPct,
                      InpMagicBase,
                      InpFilterByMagicOnly);

   UpdateAllPairBasketStates(g_pairs, InpMagicBase, InpFilterByMagicOnly);

   RenderPanel(g_pairs, g_stats, g_debug, 0);
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Full engine cycle                                                |
//+------------------------------------------------------------------+
void RunEngineCycle()
{
   ResetDebugStats(g_debug);
   RefreshPairMetadata();
   UpdateStrengthIfNeeded();
   UpdateAllPairStates(true);

   // Emergency first
   ProcessEmergencyIfNeeded();

   // Rebuild stats after possible emergency
   UpdateRiskSnapshot(g_stats,
                      g_brokerSymbols,
                      InpFreezeDDPercent,
                      InpEmergencyDDPercent,
                      InpMinMarginLevelPct,
                      InpMagicBase,
                      InpFilterByMagicOnly);

   // Exit layer before new entries
   ProcessExitLayer();

   // Refresh state after exits
   UpdateStrengthIfNeeded();
   UpdateAllPairStates(false);

   // New basket starts
   ProcessEntryLayer();

   // Refresh after new starts
   UpdateRiskSnapshot(g_stats,
                      g_brokerSymbols,
                      InpFreezeDDPercent,
                      InpEmergencyDDPercent,
                      InpMinMarginLevelPct,
                      InpMagicBase,
                      InpFilterByMagicOnly);
   UpdateAllPairBasketStates(g_pairs, InpMagicBase, InpFilterByMagicOnly);

   // Basket add-ons
   ProcessExpansionLayer();

   // Final refresh
   UpdateAllPairStates(false);
   RenderDashboard();
   
   MaybePrintDebugSummary();
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   TesterHideIndicators(true);
   
   // symbol mapping
   BuildBrokerSymbolMap(g_brokerSymbols);

   if(!ValidateBrokerSymbolMap(g_brokerSymbols))
   {
      Print("TMD_Lite: no valid mapped symbols found");
      return(INIT_FAILED);
   }

   // log mapping
   for(int i = 0; i < ArraySize(g_brokerSymbols); i++)
      LogMsg(TMD_SYMBOLS[i] + " -> " + g_brokerSymbols[i]);

   InitializeStrengthState();
   InitializeExposureState();
   InitializePairs();

   ApplyChartStyle(0);
   ApplyChartLayout(0);

   EventSetTimer(MathMax(1, InpTimerSeconds));

   // first render cycle
   RunEngineCycle();

   Print("TMD_Lite initialized");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   DeleteAllPanelObjects(0);
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Timer-driven EA by design
}

//+------------------------------------------------------------------+
//| Timer event                                                      |
//+------------------------------------------------------------------+
void OnTimer()
{
   RunEngineCycle();
}