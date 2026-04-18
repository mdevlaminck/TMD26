//+------------------------------------------------------------------+
//|                                                         TMD5.mq5 |
//|                                                              MDV |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "MDV"
#property link      "https://www.mql5.com"
#property version   "1.00"


//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//---

//---
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
//---
   
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
//---
   static datetime lastBar = 0;
   datetime currentBar = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(currentBar == lastBar)
      return; // wait until new candle

   lastBar = currentBar;
   
   double lastUp   = GetLastFractalUp(_Symbol, PERIOD_CURRENT);
   double lastDown = GetLastFractalDown(_Symbol, PERIOD_CURRENT);

   if(lastUp != EMPTY_VALUE && iClose(_Symbol,PERIOD_CURRENT,0) > lastUp)
      Print("Last confirmed Fractal UP Broken: ", lastUp);

   if(lastDown != EMPTY_VALUE && iClose(_Symbol,PERIOD_CURRENT,0) < lastDown)
      Print("Last confirmed Fractal DOWN Broken: ", lastDown);
   
  }
//+------------------------------------------------------------------+

double GetLastFractalUp(string symbol, ENUM_TIMEFRAMES tf, int lookback = 300)
{
   int handle = iFractals(symbol, tf);
   if(handle == INVALID_HANDLE)
      return EMPTY_VALUE;

   double buf[];
   ArraySetAsSeries(buf, true);

   if(CopyBuffer(handle, 0, 2, lookback, buf) <= 0)
      return EMPTY_VALUE;

   for(int i = 0; i < ArraySize(buf); i++)
   {
      if(buf[i] != EMPTY_VALUE)
         return buf[i];   // MOST RECENT confirmed fractal up
   }

   return EMPTY_VALUE;
}
double GetLastFractalDown(string symbol, ENUM_TIMEFRAMES tf, int lookback = 300)
{
   int handle = iFractals(symbol, tf);
   if(handle == INVALID_HANDLE)
      return EMPTY_VALUE;

   double buf[];
   ArraySetAsSeries(buf, true);

   if(CopyBuffer(handle, 1, 2, lookback, buf) <= 0)
      return EMPTY_VALUE;

   for(int i = 0; i < ArraySize(buf); i++)
   {
      if(buf[i] != EMPTY_VALUE)
         return buf[i];   // MOST RECENT confirmed fractal down
   }

   return EMPTY_VALUE;
}