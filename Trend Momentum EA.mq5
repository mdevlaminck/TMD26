//+------------------------------------------------------------------+
//|                                              TrendMomentumEA.mq5 |
//|                                  Copyright 2024, Trading Bot Dev |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, User"
#property link      "https://www.mql5.com"
#property version   "1.10"
#property strict

// Include the Trade class for easier execution
#include <Trade\Trade.mqh>

//--- INPUT PARAMETERS
input group "Indicator Settings"
input int      InpEMA50          = 50;          // Fast EMA Period
input int      InpEMA200         = 200;         // Slow EMA Period
input int      InpRSI            = 14;          // RSI Period
input int      InpStochK         = 5;           // Stochastic %K
input int      InpStochD         = 3;           // Stochastic %D
input int      InpStochSlowing   = 3;           // Stochastic Slowing

input group "Session Settings (Broker Server Time)"
input int      InpLondonStart    = 8;           // London Start Hour
input int      InpLondonEnd      = 16;          // London End Hour
input int      InpNYStart        = 13;          // New York Start Hour
input int      InpNYEnd          = 21;          // New York End Hour

input group "Risk Management"
input double   InpLotSize        = 0.1;         // Fixed Lot Size
input int      InpStopLoss       = 300;         // Stop Loss (Points)
input int      InpTakeProfit     = 600;         // Take Profit (Points)
input int      InpMagicNum       = 123456;      // Magic Number

//--- GLOBAL VARIABLES
int      handleEMA50, handleEMA200, handleRSI, handleStoch;
CTrade   trade;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Initialize Indicator Handles
   // FIX: Added validation for handles and initialization error handling
   handleEMA50  = iMA(_Symbol, _Period, InpEMA50, 0, MODE_EMA, PRICE_CLOSE);
   handleEMA200 = iMA(_Symbol, _Period, InpEMA200, 0, MODE_EMA, PRICE_CLOSE);
   handleRSI    = iRSI(_Symbol, _Period, InpRSI, PRICE_CLOSE);
   handleStoch  = iStochastic(_Symbol, _Period, InpStochK, InpStochD, InpStochSlowing, MODE_SMA, STO_LOWHIGH);

   if(handleEMA50 == INVALID_HANDLE || handleEMA200 == INVALID_HANDLE || 
      handleRSI == INVALID_HANDLE || handleStoch == INVALID_HANDLE)
   {
      Print("CRITICAL ERROR: Failed to create indicator handles.");
      return(INIT_FAILED);
   }

   // Set Trade Parameters
   trade.SetExpertMagicNumber(InpMagicNum);

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Properly release indicator handles to free memory
   IndicatorRelease(handleEMA50);
   IndicatorRelease(handleEMA200);
   IndicatorRelease(handleRSI);
   IndicatorRelease(handleStoch);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // 1. Position Check: Ensure no other trades are open with this Magic Number
   // FIX: We check positions specifically for this EA's magic number/symbol
   if(PositionSelectByMagic(_Symbol, InpMagicNum)) return;

   // 2. Session Logic
   if(!IsTradingSession()) return;

   // Indicator Data Arrays
   double ema50[], ema200[], rsi[], stochK[], stochD[];
   MqlRates rates[];
   
   // FIX: All arrays set as series so index [1] is the last completed candle
   ArraySetAsSeries(ema50, true);
   ArraySetAsSeries(ema200, true);
   ArraySetAsSeries(rsi, true);
   ArraySetAsSeries(stochK, true);
   ArraySetAsSeries(stochD, true);
   ArraySetAsSeries(rates, true);

   // FIX: Robust Error Handling for CopyBuffer. 
   // We fetch index 0 to 2 (3 values) to check crossovers on the closed bars.
   if(CopyBuffer(handleEMA50, 0, 0, 3, ema50) < 3) return;
   if(CopyBuffer(handleEMA200, 0, 0, 3, ema200) < 3) return;
   if(CopyBuffer(handleRSI, 0, 0, 3, rsi) < 3) return;
   if(CopyBuffer(handleStoch, 0, 0, 3, stochK) < 3) return; // Buffer 0 = %K
   if(CopyBuffer(handleStoch, 1, 0, 3, stochD) < 3) return; // Buffer 1 = %D
   if(CopyRates(_Symbol, _Period, 0, 3, rates) < 3) return;

   // Price data for execution
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT); // FIX: Explicit point size

   // Use Index [1] for signals - this is the last COMPLETED candle.
   // Using [0] results in "repainting" or flickering signals during a tick.
   double signalClosePrice = rates[1].close;
   double signalEMA50      = ema50[1];
   double signalEMA200     = ema200[1];

   // 3. Trend Logic
   bool isBuyTrend  = (signalClosePrice > signalEMA50 && signalClosePrice > signalEMA200);
   bool isSellTrend = (signalClosePrice < signalEMA50 && signalClosePrice < signalEMA200);

   //--- BUY CONDITIONS
   if(isBuyTrend)
   {
      bool rsiOk = (rsi[1] >= 50);
      
      // Stochastic crossover: K was below D on candle 2, and K is above D on candle 1
      bool stochCross = (stochK[2] <= stochD[2] && stochK[1] > stochD[1]);
      
      // Candle 1 (last closed candle) must be bullish
      bool candleBullish = (rates[1].close > rates[1].open);

      if(rsiOk && stochCross && candleBullish)
      {
         double sl = ask - InpStopLoss * point;
         double tp = ask + InpTakeProfit * point;
         
         if(trade.Buy(InpLotSize, _Symbol, ask, sl, tp, "TrendMomentum Buy"))
            Print("Buy executed at ", ask);
         else
            Print("Buy failed: ", trade.ResultRetcodeDescription());
      }
   }
   //--- SELL CONDITIONS
   else if(isSellTrend)
   {
      bool rsiOk = ( rsi[1] <= 50);
      
      // Stochastic crossover: K was above D on candle 2, and K is below D on candle 1
      bool stochCross = (stochK[2] >= stochD[2] && stochK[1] < stochD[1]);
      
      // Candle 1 (last closed candle) must be bearish
      bool candleBearish = (rates[1].close < rates[1].open);

      if(rsiOk && stochCross && candleBearish)
      {
         double sl = bid + InpStopLoss * point;
         double tp = bid - InpTakeProfit * point;
         
         if(trade.Sell(InpLotSize, _Symbol, bid, sl, tp, "TrendMomentum Sell"))
            Print("Sell executed at ", bid);
         else
            Print("Sell failed: ", trade.ResultRetcodeDescription());
      }
   }
}

//+------------------------------------------------------------------+
//| Custom function to check if a position exists for this EA        |
//+------------------------------------------------------------------+
bool PositionSelectByMagic(string symbol, long magic)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == symbol && 
            PositionGetInteger(POSITION_MAGIC) == magic)
            return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Check if current server time is within London or NY sessions     |
//+------------------------------------------------------------------+
bool IsTradingSession()
{
   MqlDateTime dt;
   TimeCurrent(dt);
   
   bool isLondon = (dt.hour >= InpLondonStart && dt.hour < InpLondonEnd);
   bool isNY = (dt.hour >= InpNYStart && dt.hour < InpNYEnd);
   
   return (isLondon || isNY);
}