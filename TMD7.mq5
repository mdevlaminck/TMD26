//+------------------------------------------------------------------+
//|  ML-Distilled Volatility Continuation EA (MT5)                   |
//|  Exact logic from model behavior                                  |
//+------------------------------------------------------------------+
#property strict
#property version   "1.00"
#property description "Rule-based distillation of ML volatility model"

#include <Trade\Trade.mqh>
CTrade  trade;

// ===================== INPUTS =====================
input double   RiskPercent     = 1.0;
input int      ATR_Period      = 14;
input int      RSI_Period      = 14;
input int      EMA_Fast        = 10;
input int      EMA_Mid         = 20;
input int      EMA_Slow        = 50;
input double   MinATRRatio     = 1.05;
input double   MinADX          = 18.0;

// ===================== GLOBALS =====================
int hATR, hRSI_M5, hRSI_H1, hADX;
int hEMA10, hEMA20, hEMA50;

double atr[], atrFast[], atrSlow[];
double rsiM5[], rsiH1[], adx[];
double ema10[], ema20[], ema50[];

datetime lastBarTime = 0;


//+------------------------------------------------------------------+
int OnInit()
{
   hATR     = iATR(_Symbol, PERIOD_M5, ATR_Period);
   hRSI_M5  = iRSI(_Symbol, PERIOD_M5, RSI_Period, PRICE_CLOSE);
   hRSI_H1  = iRSI(_Symbol, PERIOD_H1, RSI_Period, PRICE_CLOSE);
   hADX     = iADX(_Symbol, PERIOD_M5, 14);
   hEMA10   = iMA(_Symbol, PERIOD_M5, EMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
   hEMA20   = iMA(_Symbol, PERIOD_M5, EMA_Mid, 0, MODE_EMA, PRICE_CLOSE);
   hEMA50   = iMA(_Symbol, PERIOD_M5, EMA_Slow, 0, MODE_EMA, PRICE_CLOSE);

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnTick()
{

   datetime t = iTime(_Symbol, PERIOD_M5, 0);
   if(t == lastBarTime) return;
   lastBarTime = t;

   if(!TradingSessionOK()) return;
   if(PositionSelect(_Symbol)) { ManageTrade(); return; }

   LoadData();
   if(!RegimeOK()) return;

   if(BuySignal())  OpenTrade(ORDER_TYPE_BUY);
   if(SellSignal()) OpenTrade(ORDER_TYPE_SELL);
}

//+------------------------------------------------------------------+
void LoadData()
{
   CopyBuffer(hATR,    0, 0, 3, atr);
   CopyBuffer(hRSI_M5, 0, 0, 2, rsiM5);
   CopyBuffer(hRSI_H1, 0, 0, 2, rsiH1);
   CopyBuffer(hADX,    0, 0, 2, adx);
   CopyBuffer(hEMA10,  0, 0, 2, ema10);
   CopyBuffer(hEMA20,  0, 0, 2, ema20);
   CopyBuffer(hEMA50,  0, 0, 2, ema50);
}

//+------------------------------------------------------------------+
bool RegimeOK()
{
   double atrSlope = atr[0] - atr[1];
   double atrRatio = atr[0] / atr[1];

   if(atrRatio < MinATRRatio) return false;
   if(atrSlope <= 0) return false;
   if(adx[0] < MinADX) return false;

   return true;
}

//+------------------------------------------------------------------+
bool BuySignal()
{
   double distATH = (HighestHigh(200) - ClosePrice()) / atr[0];
   double emaFastSpread = (ema10[0] - ema20[0]) / atr[0];
   double emaSlowSpread = (ema20[0] - ema50[0]) / atr[0];

   if(distATH <= 2.0) return false;
   if(rsiH1[0] <= 55) return false;
   if(emaFastSpread <= 0 || emaSlowSpread <= 0) return false;
   if(rsiM5[0] <= 50) return false;
   if(ClosePrice() <= ema10[0]) return false;

   return true;
}

//+------------------------------------------------------------------+
bool SellSignal()
{
   double distATH = (HighestHigh(200) - ClosePrice()) / atr[0];
   double emaFastSpread = (ema10[0] - ema20[0]) / atr[0];
   double emaSlowSpread = (ema20[0] - ema50[0]) / atr[0];

   if(distATH <= 4.0) return false;
   if(rsiH1[0] >= 45) return false;
   if(emaFastSpread >= 0 || emaSlowSpread >= 0) return false;
   if(rsiM5[0] >= 50) return false;
   if(ClosePrice() >= ema10[0]) return false;

   return true;
}

//+------------------------------------------------------------------+
void OpenTrade(ENUM_ORDER_TYPE type)
{
   double sl, tp;
   double price = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol,SYMBOL_ASK)
                                           : SymbolInfoDouble(_Symbol,SYMBOL_BID);

   if(type == ORDER_TYPE_BUY)
      sl = MathMin(price - 1.8*atr[0], RecentSwingLow() - 0.2*atr[0]);
   else
      sl = MathMax(price + 1.8*atr[0], RecentSwingHigh() + 0.2*atr[0]);

   double lot = CalcLot(sl, price);

   trade.PositionOpen(_Symbol, type, lot, price, sl, 0);
}

//+------------------------------------------------------------------+
void ManageTrade()
{
   double atrSlope = atr[0] - atr[1];

   if(atrSlope < 0)
      trade.PositionClose(_Symbol);
}

//+------------------------------------------------------------------+
bool TradingSessionOK()
{
   MqlDateTime tm; TimeToStruct(TimeCurrent(), tm);
   if(tm.hour < 8 || tm.hour > 17) return false;
   return true;
}

//+------------------------------------------------------------------+
double CalcLot(double sl, double price)
{
   double risk = AccountInfoDouble(ACCOUNT_BALANCE) * RiskPercent / 100.0;
   double tick = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double dist = MathAbs(price - sl);
   return NormalizeDouble(risk / (dist / tick), 2);
}

//+------------------------------------------------------------------+
double HighestHigh(int bars)
{
   int idx = iHighest(_Symbol, PERIOD_M5, MODE_HIGH, bars, 1);
   return iHigh(_Symbol, PERIOD_M5, idx);
}

//+------------------------------------------------------------------+
double RecentSwingLow()
{
   int idx = iLowest(_Symbol, PERIOD_M5, MODE_LOW, 20, 1);
   return iLow(_Symbol, PERIOD_M5, idx);
}

//+------------------------------------------------------------------+
double RecentSwingHigh()
{
   int idx = iHighest(_Symbol, PERIOD_M5, MODE_HIGH, 20, 1);
   return iHigh(_Symbol, PERIOD_M5, idx);
}

//+------------------------------------------------------------------+
double ClosePrice()
{
   return iClose(_Symbol, PERIOD_M5, 0);
}
//+------------------------------------------------------------------+
