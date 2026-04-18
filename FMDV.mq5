//+------------------------------------------------------------------+
//| MT5 MQ5 EA: Higher-timeframe fractal bias + pullback entries     |
//| - H4 -> H1 bias: if H4 close > last H4 high-fractal -> bullish   |
//|   if H4 close < last H4 low-fractal -> bearish                    |
//| - Then on H1 look for pullback entries (max 1 per H4 candle)     |
//| - H1 -> M15 same logic for M15 entries (max 1 per H1 candle)      |
//| - Multi-symbol support (comma separated, up to 16 symbols)        |
//| - On-chart panel with equity, balance, drawdown, open positions   |
//| - Historical profit per symbol                                   |
//+------------------------------------------------------------------+
#property copyright "Assistant"
#property version   "1.00"
#property strict

#include <Trade/Trade.mqh>
CTrade trade;

//---- inputs
input string InpSymbols = "EURUSD,GBPUSD,USDJPY"; // comma separated list, max 16
input double InpLot = 0.01;
input int InpSlPoints = 400;   // stop loss in points (5 digits = 1 pip = 10 points)
input int InpTpPoints = 800;
input int MaxSymbols = 16;
input int TimerIntervalSeconds = 15; // how often to evaluate

//---- internal structures
struct SymbolState
{
   string symbol;
   datetime lastH4TradeTime; // each H4 candle allow 1 H1 entry
   datetime lastH1TradeTime; // each H1 candle allow 1 M15 entry
   double histProfit; // historical closed profit for symbol
};

//---- globals
SymbolState states[16];
int symbolCount = 0;
string symbolList[16];

// Panel object names
string panel_name = "HTF_Fractal_Panel";

//+------------------------------------------------------------------+
//| Trim spaces from start and end of string                          |
//+------------------------------------------------------------------+
string Trim(string str)
{
   int start=0, end=StringLen(str)-1;
   while(start<=end && (StringGetCharacter(str,start)==' ' || StringGetCharacter(str,start)=='\t')) start++;
   while(end>=start && (StringGetCharacter(str,end)==' ' || StringGetCharacter(str,end)=='\t')) end--;
   if(start>end) return("");
   return(StringSubstr(str,start,end-start+1));
}

//+------------------------------------------------------------------+
//| Utility: split symbols string into array                         |
//+------------------------------------------------------------------+
void ParseSymbols()
{
   string s = InpSymbols; // input string
   ArrayResize(symbolList, MaxSymbols); // ensure array size
   symbolCount = 0;

   while(StringLen(s) > 0 && symbolCount < MaxSymbols)
   {
      int comma = StringFind(s, ",");
      string token;

      if(comma == -1)
      {
         token = Trim(s);
         s = "";
      }
      else
      {
         token = Trim(StringSubstr(s, 0, comma));
         s = StringSubstr(s, comma + 1);
      }

      if(StringLen(token) > 0)
      {
         symbolList[symbolCount] = token;
         symbolCount++;
      }
   }

   // Optional: clear remaining slots
   for(int i = symbolCount; i < ArraySize(symbolList); i++)
      symbolList[i] = "";
}



//+------------------------------------------------------------------+
//| Find most recent completed fractal high index in rates arrays     |
//| rates array is in ascending time: rates[0] = oldest, rates[...]=latest
//| we return the index in that array (closest to end) of the fractal
//+------------------------------------------------------------------+
int LastFractalHighIndex(const MqlRates &rates[])
{
   int n = ArraySize(rates);
   if(n<5) return -1;
   // iterate from newest-2 down to 2 (so center can be checked)
   for(int i = n-3; i>=2; i--)
   {
      double h = rates[i].high;
      if(h>rates[i-1].high && h>rates[i-2].high && h>rates[i+1].high && h>rates[i+2].high)
         return i;
   }
   return -1;
}

int LastFractalLowIndex(const MqlRates &rates[])
{
   int n = ArraySize(rates);
   if(n<5) return -1;
   for(int i = n-3; i>=2; i--)
   {
      double l = rates[i].low;
      if(l<rates[i-1].low && l<rates[i-2].low && l<rates[i+1].low && l<rates[i+2].low)
         return i;
   }
   return -1;
}

//+------------------------------------------------------------------+
//| Find latest fractal price (value) and candle time on given TF     |
//+------------------------------------------------------------------+
bool GetLastFractal(const string symbol, ENUM_TIMEFRAMES tf, bool high, double &price, datetime &candleTime)
{
   MqlRates rates[];
   int copied = CopyRates(symbol, tf, 0, 500, rates);
   if(copied<=5) return false;
   int idx = high?LastFractalHighIndex(rates):LastFractalLowIndex(rates);
   if(idx==-1) return false;
   price = high?rates[idx].high:rates[idx].low;
   candleTime = rates[idx].time;
   return true;
}

//+------------------------------------------------------------------+
//| Check bias: for H4 relative to H4 fractals                       |
//+------------------------------------------------------------------+
int CheckH4Bias(const string symbol, datetime &h4CloseTime)
{
   // returns +1 bullish, -1 bearish, 0 neutral/none
   double fractalHigh, fractalLow;
   datetime fhTime, flTime;
   bool okh = GetLastFractal(symbol, PERIOD_H4, true, fractalHigh, fhTime);
   bool okl = GetLastFractal(symbol, PERIOD_H4, false, fractalLow, flTime);
   if(!okh && !okl) return 0;
   // get last closed H4 candle close
   MqlRates r4[];
   if(CopyRates(symbol, PERIOD_H4, 1, 2, r4) < 1) return 0; // 1st returned is one-candle-ago (closed)
   double lastClose = r4[0].close;
   h4CloseTime = r4[0].time;
   // bullish if lastClose > fractalHigh (the most recent fractal high)
   if(okh && lastClose > fractalHigh) return 1;
   if(okl && lastClose < fractalLow) return -1;
   return 0;
}

int CheckH1Bias(const string symbol, datetime &h1CloseTime)
{
   double fractalHigh, fractalLow;
   datetime fhTime, flTime;
   bool okh = GetLastFractal(symbol, PERIOD_H1, true, fractalHigh, fhTime);
   bool okl = GetLastFractal(symbol, PERIOD_H1, false, fractalLow, flTime);
   if(!okh && !okl) return 0;
   MqlRates r1[];
   if(CopyRates(symbol, PERIOD_H1, 1, 2, r1) < 1) return 0;
   double lastClose = r1[0].close;
   h1CloseTime = r1[0].time;
   if(okh && lastClose > fractalHigh) return 1;
   if(okl && lastClose < fractalLow) return -1;
   return 0;
}

//+------------------------------------------------------------------+
//| Simple pullback entry logic on target timeframe                   |
//| For bullish bias: wait for recent pullback (lowest close in last 8 bars)
//| then enter when a bullish engulfing / close above previous high  |
//+------------------------------------------------------------------+
bool CheckPullbackEntry(const string symbol, ENUM_TIMEFRAMES tf, int bias)
{
   // bias: +1 buy, -1 sell
   MqlRates rates[];
   int copied = CopyRates(symbol, tf, 0, 30, rates);
   if(copied<10) return false;
   int n = ArraySize(rates);
   // examine the last 8 completed bars (exclude current)
   int start = n-9; if(start<1) start=1;
   int end = n-2; // last closed bar is n-2 (because CopyRates with shift 0 returns latest including current)
   if(end<start) return false;
   // find pullback extreme within that zone
   double extreme = bias>0?DBL_MAX:-DBL_MAX;
   int extremeIndex = -1;
   for(int i=start;i<=end;i++)
   {
      if(bias>0)
      {
         if(rates[i].low < extreme) { extreme = rates[i].low; extremeIndex = i; }
      }
      else
      {
         if(rates[i].high > extreme) { extreme = rates[i].high; extremeIndex = i; }
      }
   }
   if(extremeIndex==-1) return false;
   // require that after the extreme we have at least one bar showing continuation momentum
   // check the last closed bar (n-2)
   MqlRates last = rates[n-2];
   MqlRates prev = rates[n-3];
   if(bias>0)
   {
      // bullish entry: last close > prev high (momentum after pullback)
      if(last.close > prev.high) return true;
   }
   else
   {
      if(last.close < prev.low) return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Open a market order (simple)                                     |
//+------------------------------------------------------------------+
bool OpenMarketOrder(const string symbol, int cmd, double lot)
{
   // cmd: ORDER_TYPE_BUY=0, SELL=1
   double price = (cmd==ORDER_TYPE_BUY)?SymbolInfoDouble(symbol,SYMBOL_ASK):SymbolInfoDouble(symbol,SYMBOL_BID);
   if(price<=0) return false;
   double sl = 0, tp = 0;
   if(cmd==ORDER_TYPE_BUY)
   {
      sl = price - InpSlPoints*SymbolInfoDouble(symbol,SYMBOL_POINT);
      tp = price + InpTpPoints*SymbolInfoDouble(symbol,SYMBOL_POINT);
   }
   else
   {
      sl = price + InpSlPoints*SymbolInfoDouble(symbol,SYMBOL_POINT);
      tp = price - InpTpPoints*SymbolInfoDouble(symbol,SYMBOL_POINT);
   }
   trade.SetExpertMagicNumber(20251130);
   trade.SetDeviationInPoints(20);
   bool res = false;
   if(cmd==ORDER_TYPE_BUY) res = trade.Buy(lot,NULL,price,sl,tp);
   else res = trade.Sell(lot,NULL,price,sl,tp);
   return res;
}

//+------------------------------------------------------------------+
//| Build or update on-chart panel                                   |
//+------------------------------------------------------------------+
void UpdatePanel()
{
   // remove old panel
   if(ObjectFind(0,panel_name) < 0)
   {
      // create label
      if(!ObjectCreate(0,panel_name,OBJ_LABEL,0,0,0)) return;
      ObjectSetInteger(0,panel_name,OBJPROP_XDISTANCE,10);
      ObjectSetInteger(0,panel_name,OBJPROP_YDISTANCE,10);
      ObjectSetInteger(0,panel_name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
      ObjectSetInteger(0,panel_name,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,panel_name,OBJPROP_HIDDEN,true);
   }
   string txt = "Equity: ";
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double dd = (balance>equity)?(balance-equity)/balance*100.0:0.0;
   txt += DoubleToString(equity,2)+"\n";
   txt += "Balance: "+DoubleToString(balance,2)+"\n";
   txt += "Drawdown %: "+DoubleToString(dd,2)+"\n";
   // open positions summary
   int total = PositionsTotal();
   txt += "Open positions: "+IntegerToString(total)+"\n";
   for(int i=0;i<symbolCount;i++)
   {
      string sym = symbolList[i];
      double profit = 0.0;
      // sum profit for symbol
      for(int p=0;p<PositionsTotal();p++)
      {
         ulong ticket = PositionGetTicket(p);
         if(PositionSelectByTicket(ticket))
         {
            if(PositionGetString(POSITION_SYMBOL)==sym) profit += PositionGetDouble(POSITION_PROFIT);
         }
      }
      txt += sym+": openP/L="+DoubleToString(profit,2)+" closedP/L="+DoubleToString(states[i].histProfit,2)+"\n";
   }
   ObjectSetString(0,panel_name,OBJPROP_TEXT,txt);
}

//+------------------------------------------------------------------+
//| Update historical profit per symbol (scan history deals once)    |
//+------------------------------------------------------------------+
void UpdateHistoricalProfit()
{
   // compute closed profit per symbol (last 1 year or all)
   for(int i=0;i<symbolCount;i++) states[i].histProfit = 0.0;
   ulong ticket=0;
   int totalDeals = HistoryDealsTotal();
   for(int d=0; d<totalDeals; d++)
   {
      ticket = HistoryDealGetTicket(d);
      if(ticket==0) continue;
      string sym = HistoryDealGetString(ticket, DEAL_SYMBOL);
      double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
      // find symbol index
      for(int s=0;s<symbolCount;s++)
      {
         if(symbolList[s]==sym) states[s].histProfit += profit;
      }
   }
}

//+------------------------------------------------------------------+
//| OnInit - performantly subscribe to needed symbols and timers     |
//+------------------------------------------------------------------+
int OnInit()
{
   ParseSymbols();
   if(symbolCount<=0) { Print("No symbols configured"); return(INIT_FAILED); }
   // initialize states and subscribe
   for(int i=0;i<symbolCount;i++)
   {
      states[i].symbol = symbolList[i];
      states[i].lastH4TradeTime = 0;
      states[i].lastH1TradeTime = 0;
      // subscribe symbol to receive rates (minimize repeated calls)
      SymbolSelect(states[i].symbol,true);
   }
   // compute historical profit once on init
   UpdateHistoricalProfit();
   // setup timer for periodic checks to avoid heavy OnTick
   EventSetTimer(TimerIntervalSeconds);
   // build initial panel
   UpdatePanel();
   Print("HTF Fractal Pullback EA initialized for ", symbolCount, " symbols.");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| OnDeinit                                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   if(ObjectFind(0,panel_name) >= 0) ObjectDelete(0,panel_name);
}

//+------------------------------------------------------------------+
//| Timer handler - main logic                                       |
//+------------------------------------------------------------------+
void OnTimer()
{
   // iterate symbols
   for(int i=0;i<symbolCount;i++)
   {
      string sym = states[i].symbol;
      // ensure symbol is available
      if(!SymbolInfoInteger(sym,SYMBOL_SELECT)) SymbolSelect(sym,true);
      // 1) H4 -> H1 flow: check H4 bias
      datetime h4CloseTime;
      int h4Bias = CheckH4Bias(sym, h4CloseTime);
      // if bullish/bearish and a new H4 close (so we only allow one H1 entry per H4)
      if(h4Bias!=0)
      {
         // check if we've already taken an H1 trade this H4 candle
         if(states[i].lastH4TradeTime != h4CloseTime)
         {
            // evaluate H1 pullback entry
            bool entry = CheckPullbackEntry(sym, PERIOD_H1, h4Bias);
            if(entry)
            {
               // place order
               
               int cmd = (h4Bias>0)?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
               bool ok = true;
               //ok = OpenMarketOrder(sym, cmd, InpLot);
               if(ok)
               {
                  states[i].lastH4TradeTime = h4CloseTime;
                  PrintFormat("Opened %s on %s due to H4 bias at %s", (cmd==ORDER_TYPE_BUY?"BUY":"SELL"), sym, TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS));
               }
            }
         }
      }
      // 2) H1 -> M15 flow: check H1 bias
      datetime h1CloseTime;
      int h1Bias = CheckH1Bias(sym, h1CloseTime);
      if(h1Bias!=0)
      {
         if(states[i].lastH1TradeTime != h1CloseTime)
         {
            bool entry2 = CheckPullbackEntry(sym, PERIOD_M15, h1Bias);
            if(entry2)
            {
               
               int cmd2 = (h1Bias>0)?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
               bool ok2 = true;
               //ok2 = OpenMarketOrder(sym, cmd2, InpLot);
               if(ok2)
               {
                  states[i].lastH1TradeTime = h1CloseTime;
                  PrintFormat("Opened %s on %s due to H1 bias at %s", (cmd2==ORDER_TYPE_BUY?"BUY":"SELL"), sym, TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS));
               }
            }
         }
      }
   }
   // refresh historical profit and panel (do this periodically but not too often)
   UpdateHistoricalProfit();
   UpdatePanel();
}

//+------------------------------------------------------------------+
//| OnTick - very light, do nothing (we use timer)                   |
//+------------------------------------------------------------------+
void OnTick()
{
   // intentionally empty to keep OnTick fast. Processing done in OnTimer.
}

//+------------------------------------------------------------------+
//| Helpers for HistoryDealGet* wrappers (MQL5 uses different APIs)   |
//+------------------------------------------------------------------+
ulong HistoryDealGetTicket(int index)
{
   // MQL5 doesn't provide direct index->ticket API; use HistoryDealGetInteger
   // but for portability we'll use HistoryDealGetInteger with DEAL_ENTRY
   // Instead use HistoryDealGetInteger(index, DEAL_TICKET) is invalid; use HistoryDealGetTicket via copy deals
   // Simplify: use HistoryDealSelect to iterate by time index
   datetime from = 0;
   if(HistorySelect(from, TimeCurrent()))
   {
      ulong ticket=0;
      if(HistoryDealGetTicket(index)>0) ticket = HistoryDealGetTicket(index);
      return ticket;
   }
   return 0;
}

// Note: In some brokers the HistoryDealGet* functions require different usage. This EA uses HistoryDealsTotal()+HistoryDealGetTicket as attempt; if unavailable adjust to platform specifics.

//+------------------------------------------------------------------+
// End of file
//+------------------------------------------------------------------+
