//+------------------------------------------------------------------+
//|                                                        TMD16.mq5 |
//|                                                              MDV |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "MDV"
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <GridManager.mqh>
#include <Trade/Trade.mqh>

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
   
   int direction; // ORDER_TYPE_BUY / ORDER_TYPE_SELL
   
   GridManager       *buyGrid;
   GridManager       *sellGrid;
   int            rsiM1Handle;
   int            bbM1Handle;
   
   
};

PairData Pairs[];

enum ENUM_ONOFF
{
   OFF = 0,
   ON  = 1
};

input group "=== Symbol Settings ===";
input string InpSuffix = ""; // Symbol Suffix
input group "=== Lot Settings ===";
input ENUM_ONOFF InpUseAutoLot = ON; // Auto-Lot
input double InpBalancePerLot = 500; // Grid Initial Balance per Lot - Auto-Lot
input double InpInitialLot = 0.01; // Grid Initial Lot (Fixed - Only when Auto-Lot is OFF)
input group "=== Grid Settings ===";
input int InpMagicBuy = 2204; // Grid Magic Buy Base Nr
input int InpMagicSell = 1981; // Grid Magic Sell Base Nr
input int InpMaxOrders = 14; // Grid Max Orders
input double InpMaxDD = 0; // Grid Max DD
input int InpGapPoints = 200; // Grid Gap Points
input double InpProfitPercent = 0.08; // Take Profit Percentage
input double InpGridMultiplier = 1.1; // Grid Multiplier
input group "=== Filter Settings ===";
input double InpMinScore = 0; // Minimum Strength Score
input double InpBuyRsi = 30; // Maximum RSI for BUY
input double InpSellRsi = 70; // Minimum RSI for SELL
input ENUM_ONOFF   InpUseBB = ON; // BB Filter
input group "=== Visual Settings ===";
input ENUM_ONOFF        StyleChart = ON;              // TMD Chart Style

string   InpSymbols      = "EURUSD,GBPUSD,AUDUSD,NZDUSD,USDJPY,USDCHF,USDCAD,EURGBP,EURJPY,EURCHF,EURAUD,EURNZD,EURCAD,GBPJPY,GBPCHF,GBPAUD,GBPNZD,GBPCAD,AUDJPY,AUDCHF,AUDNZD,AUDCAD,NZDJPY,NZDCHF,NZDCAD,CADJPY,CADCHF,CHFJPY";

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

int csdHandle;
int symCount;
string symList[];
struct SymbolTF
{
   string            symbol;
   GridManager       *buyGrid;
   GridManager       *sellGrid;
   int            rsiM1Handle;
   int            bbM1Handle;
   double         buySCR;
   double         sellSCR;
};




SymbolTF streams[];

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

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//---
   
   InitPairs();
   
   symCount = SplitString(InpSymbols,",",symList);
   csdHandle = iCustom(_Symbol,PERIOD_CURRENT,"Market\\Currency Strength Dashboard Pro");
   ArrayResize(streams, symCount);
   
   for(int i=0;i<symCount;i++)
      {
         string symbol = symList[i];
         streams[i].symbol = symbol+InpSuffix;
         
         streams[i].rsiM1Handle = iRSI(streams[i].symbol,PERIOD_M1,14,PRICE_CLOSE);
         streams[i].bbM1Handle = iBands(streams[i].symbol,PERIOD_M1,20,0,2,PRICE_CLOSE);
         
         double initialLot = InpInitialLot;
         if (InpUseAutoLot) {
            initialLot = CalculateLotSize(InpBalancePerLot);
         }
  
         streams[i].buyGrid = new GridManager(streams[i].symbol,GRID_BUY,initialLot,InpGapPoints,0.04,InpMaxOrders);
         streams[i].buyGrid.SetGridMagicNumber(InpMagicBuy + i);
         streams[i].buyGrid.SetGridMultiplier(InpGridMultiplier);
         streams[i].buyGrid.SetGridMaxDD(InpMaxDD);
         
         
         streams[i].sellGrid = new GridManager(streams[i].symbol,GRID_SELL,initialLot,InpGapPoints,0.04,InpMaxOrders);
         streams[i].sellGrid.SetGridMagicNumber(InpMagicSell + i);
         streams[i].sellGrid.SetGridMultiplier(InpGridMultiplier);
         streams[i].sellGrid.SetGridMaxDD(InpMaxDD);
      }
      
       if (StyleChart) {
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
   Print("==== TMD[1.0] Initialized with "+IntegerToString(symCount)+" symbols ====");
   
//---
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
//---
   IndicatorRelease(csdHandle);
      for(int i=0;i<symCount;i++)
      { 
         delete streams[i].buyGrid;
         delete streams[i].sellGrid;
         IndicatorRelease(streams[i].rsiM1Handle);
         IndicatorRelease(streams[i].bbM1Handle);
      }
      for(int i=0;i< (int) Symbols.Size();i++)
      { 
         delete Pairs[i].buyGrid;
         delete Pairs[i].sellGrid;
         IndicatorRelease(Pairs[i].rsiM1Handle);
         IndicatorRelease(Pairs[i].bbM1Handle);
      }
   Print("==== TMD[1.0] Stopped ====");
   
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
//---
      
       // Check market open
      if(!CheckMarketOpen()) {
         return;
      }
      
      
      currentPnL = 0;
      for(int i=0;i<symCount;i++)
      {
         streams[i].buyGrid.Update();
         currentPnL += streams[i].buyGrid.GridPnL();
         streams[i].sellGrid.Update(); 
         currentPnL += streams[i].sellGrid.GridPnL();
      }
      
      // Max DD
      if(InpMaxDD > 0 && currentPnL<-1*AccountInfoDouble(ACCOUNT_BALANCE)*0.01*InpMaxDD) {
         // Emergency Close All Grids
         Print("===!!! [TMD] CLOSING ALL GRIDS - MAX DD REACHED !!!===");
          for(int i=0;i<symCount;i++)
         {
            streams[i].buyGrid.CloseGrid();
            streams[i].sellGrid.CloseGrid(); 
         }
      }
      
      // Lotsize
      double lotSize = InpInitialLot;
      if (InpUseAutoLot) {
         lotSize = CalculateLotSize(InpBalancePerLot);
      }
      
      // If Strength Score > treshold, start looking for entries
      for(int i=0;i<symCount;i++)
      {
      
         // Strength Filter
         bool buyFilter = streams[i].buySCR > InpMinScore;
         bool sellFilter = streams[i].sellSCR > InpMinScore;
      
         // RSI - BB Filter
               
         double Ask = SymbolInfoDouble(streams[i].symbol, SYMBOL_ASK);
         double Bid = SymbolInfoDouble(streams[i].symbol, SYMBOL_BID);
         
         double PrevOpen = iOpen(streams[i].symbol,PERIOD_M1,1);
         double PrevClose = iClose(streams[i].symbol,PERIOD_M1,1);
         bool rsiBuyM1 = false;
         bool rsiSellM1 = false;
         bool bbBuyM1 = false;
         bool bbSellM1 = false;
         
         if (buyFilter || sellFilter ) {
               double rsiM1Buffer[];
               double bbM1UpperBuffer[];
               double bbM1LowerBuffer[];
               double rsiM1 = 0;
               double bbM1Upper = 0;
               double bbM1Lower = 0;
               if (CopyBuffer(streams[i].rsiM1Handle,0,0,1,rsiM1Buffer) > 0) {
                  rsiM1 = rsiM1Buffer[0];
               }
               if (CopyBuffer(streams[i].bbM1Handle,1,0,1,bbM1UpperBuffer) > 0) {
                  bbM1Upper = bbM1UpperBuffer[0];
               }
               if (CopyBuffer(streams[i].bbM1Handle,2,0,1,bbM1LowerBuffer) > 0) {
                  bbM1Lower = bbM1LowerBuffer[0];
               }
               
               
               rsiBuyM1 = rsiM1 > 0 && rsiM1 <  InpBuyRsi;
               rsiSellM1 = rsiM1 >  InpSellRsi;
               if (InpUseBB) {
                  bbBuyM1 = Ask < bbM1Lower;
                  bbSellM1 = Bid > bbM1Upper && bbM1Upper > 0;
               } else {
                  bbBuyM1 = true;
                  bbSellM1 = true;
               }

           }
           
                      
            if (streams[i].buyGrid.CountPositions() == 0 && buyFilter && rsiBuyM1 && bbBuyM1 && CanOpenGrid(streams[i].symbol,true) && IsTradeWindow()) {
                     streams[i].buyGrid.SetLotSize(lotSize);
                     //streams[i].buyGrid.Start();

            }
            if (streams[i].sellGrid.CountPositions() == 0 && sellFilter && rsiSellM1 && bbSellM1 && CanOpenGrid(streams[i].symbol,false) && IsTradeWindow() ) {
                        streams[i].sellGrid.SetLotSize(lotSize);
                        //streams[i].sellGrid.Start();
            }
         }
         

      static datetime lastBar = 0;
      datetime currentBar = iTime(_Symbol, PERIOD_CURRENT, 0);
      
      if(currentBar == lastBar)
         return; // wait until new candle
      
   
      lastBar = currentBar;
      
      Process();
      
      // BUY Signals - 0 - 27
      for(int i=0;i<symCount;i++)
      {
         double buffer[];
         
         if(CopyBuffer(csdHandle,i,0,1,buffer) > 0 ) {
            double sig = buffer[0];
            streams[i].buySCR = sig;
            if (sig > InpMinScore) {
               if (streams[i].sellGrid.CountPositions() > 0) {
                  Print("[ALERT] - ["+streams[i].symbol+"] STRONG but open SELL positions - Grid PL ",  DoubleToString(streams[i].sellGrid.GridPnL(),2)," GLOBAL PL ", DoubleToString(currentPnL,2) );
                  if (currentPnL > 0) {
                     for(int j=0;j<symCount;j++)
                     {
                        streams[j].buyGrid.CloseGrid();
                        streams[j].sellGrid.CloseGrid(); 
                     }
                  } 
               }
            }
         }
      }
      // SELL Signals - 28 - 55
      for(int i=28;i<symCount*2;i++)
      {
         double buffer[];
         if(CopyBuffer(csdHandle,i,0,1,buffer) > 0 ) {           
            double sig = buffer[0];
            streams[i-28].sellSCR = sig;
            if (sig > InpMinScore) {
               if (streams[i-28].buyGrid.CountPositions() > 0) {
                  Print("[ALERT] - ["+streams[i-28].symbol+"] WEAK but open BUY positions - PL ", DoubleToString(streams[i-28].buyGrid.GridPnL(),2), " GLOBAL PL ", DoubleToString(currentPnL,2) );
                  if (currentPnL > 0) {
                     for(int j=0;j<symCount;j++)
                     {
                        streams[j].buyGrid.CloseGrid();
                        streams[j].sellGrid.CloseGrid(); 
                     }
                  } 
               }             
            }
         }
      
      }
      
   
  }
//+------------------------------------------------------------------+


int SplitString(string inp, string separator, string &output[])
{
   return StringSplit(inp, StringGetCharacter(separator,0), output);
}

bool CheckMarketOpen()
  {
   MqlDateTime date_cur;
   TimeTradeServer(date_cur);
   datetime seconds_cur = date_cur.hour * 3600 + date_cur.min * 60 + date_cur.sec;
   int i = 0;
   while(true)
     {
      datetime seconds_from = {}, seconds_to = {};
      if(!SymbolInfoSessionTrade(Symbol(), (ENUM_DAY_OF_WEEK)date_cur.day_of_week, i, seconds_from, seconds_to))
         break;
      if(seconds_cur > seconds_from && seconds_cur < seconds_to)
         return true;
      ++i;
     }
   return false;
  }
  

//+------------------------------------------------------------------+
//| Calculate lot size based on account balance                      |
//| Default: 0.01 lots per 500 balance                               |
//+------------------------------------------------------------------+
double CalculateLotSize(double balancePerLot = 500.0, double lotPerBalance = 0.01)
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
    double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    
    
    // Round down to nearest lot step
    lots = MathFloor(lots / lotStep) * lotStep;
    
    // Ensure lots are within broker limits
    if(lots < minLot) lots = minLot;
    if(lots > maxLot) lots = maxLot;
    
    return lots;
}  





bool ClosePosition(ulong ticket)
{
   if(!PositionSelectByTicket(ticket))
      return false;

   return trade.PositionClose(ticket);
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

   GroupState state;
   GetGroupState(group, state);

   int total = state.buyCount + state.sellCount;

   // 🔒 Rule 1: max 2 grids per group
   if(total >= 2)
      return false;

   // 🔒 Rule 2: block same direction stacking
   if(isBuy && state.buyCount > 0)
      return false;

   if(!isBuy && state.sellCount > 0)
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
      if(symbol == group[i])
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Returns true if trading is allowed in local trading hours       |
//| Automatically handles timezone and DST                           |
//+------------------------------------------------------------------+
bool IsTradeWindow()
{
    // --- Get UTC time ---
    MqlDateTime utc;
    TimeToStruct(TimeGMT(), utc);

    // --- Get broker/server time ---
    MqlDateTime server;
    TimeToStruct(TimeCurrent(), server);

    // --- Compute timezone offset from UTC (can be positive or negative) ---
    int tzOffset = server.hour - utc.hour;

    // Adjust day if crossing midnight
    if(tzOffset > 12) tzOffset -= 24;
    if(tzOffset < -12) tzOffset += 24;

    // --- Compute local hour considering DST ---
    int localHour = (utc.hour + tzOffset + 24) % 24;

    // --- Compute local weekday ---
    int localWeekday = (utc.day_of_week + (utc.hour + tzOffset)/24) % 7;

    // --- Trading window rules ---
    // Monday before 10:00 → no trading
    if(localWeekday == 1 && localHour < 10) return false;

    // Friday after 19:00 → no trading
    if(localWeekday == 5 && localHour >= 19) return false;

    return true;
}

double GetStrength(string symbol, ENUM_TIMEFRAMES tf)
{
   double close[], open[], atr[];

   if(CopyClose(symbol, tf, 0, 2, close) < 2) return 0;
   if(CopyOpen(symbol, tf, 0, 2, open) < 2) return 0;

   int atrHandle = iATR(symbol, tf, 14);
   if(CopyBuffer(atrHandle, 0, 0, 1, atr) < 1) return 0;

   if(atr[0] == 0) return 0;

   double momentum = (close[0] - open[0]) / atr[0];

   return momentum;
}

double GetMTFStrength(string symbol)
{
   double m5  = GetStrength(symbol, PERIOD_M5)  * 1.5;
   double m15 = GetStrength(symbol, PERIOD_M15) * 2.5;
   double h1  = GetStrength(symbol, PERIOD_H1)  * 3.5;
   double h4  = GetStrength(symbol, PERIOD_H4)  * 2.5;

   return (m5 + m15 + h1 + h4) / 10.0;
}

void CalculateCurrencyStrength(double &currencyStrength[])
{
   ArrayInitialize(currencyStrength, 0);

   int counts[8];
   ArrayInitialize(counts, 0);

   for(int i=0; i<ArraySize(Symbols); i++)
   {
      string sym = Symbols[i];

      string base  = StringSubstr(sym, 0, 3);
      string quote = StringSubstr(sym, 3, 3);

      double strength = GetMTFStrength(sym);

      int baseIndex  = GetCurrencyIndex(base);
      int quoteIndex = GetCurrencyIndex(quote);

      if(baseIndex >= 0)
      {
         currencyStrength[baseIndex] += strength;
         counts[baseIndex]++;
      }

      if(quoteIndex >= 0)
      {
         currencyStrength[quoteIndex] -= strength;
         counts[quoteIndex]++;
      }
   }

   // Normalize
   for(int i=0; i<8; i++)
   {
      if(counts[i] > 0)
         currencyStrength[i] /= counts[i];
   }
}

int GetCurrencyIndex(string cur)
{
   StringToUpper(cur);
   
   for(int i = 0; i < ArraySize(Currencies); i++)
   {
      StringToUpper(Currencies[i]);  
      if(Currencies[i] == cur)
         return i;
   }
   return -1;
}

void GetStrongWeak(double &strengths[], int &strongest, int &weakest)
{
   strongest = 0;
   weakest   = 0;

   for(int i=1; i<8; i++)
   {
      if(strengths[i] > strengths[strongest])
         strongest = i;

      if(strengths[i] < strengths[weakest])
         weakest = i;
   }
}

string BuildPair(string strong, string weak)
{
   string pair1 = strong + weak;
   string pair2 = weak + strong;

   if(SymbolExists(pair1))
      return pair1;

   if(SymbolExists(pair2))
      return pair2;

   return "";
}

double GetBestTrade(string &outPair, string &direction)
{
   double strength[8];
   CalculateCurrencyStrength(strength);

   int strongest, weakest;
   GetStrongWeak(strength, strongest, weakest);

   string strongCur = Currencies[strongest];
   string weakCur   = Currencies[weakest];

   double spread = strength[strongest] - strength[weakest];

   Print("Strong: ", strongCur, " ", DoubleToString(strength[strongest],2));
   Print("Weak:   ", weakCur,   " ", DoubleToString(strength[weakest],2));
   Print("Spread: ", DoubleToString(spread,2));

   string pair = BuildPair(strongCur, weakCur);
   if(pair == "") return 0;

   // Direction
   if(StringSubstr(pair,0,3) == strongCur)
   {
      direction = "BUY";
   }
   else
   {
      direction = "SELL";
   }

   // === SCORE CALC ===

   // 1. Spread score (0–5)
   double spreadScore = MathMin(5.0, (spread / 2.0) * 5.0);

   // 2. Absolute strength (0–3)
   double absScore = 0;
   if(strength[strongest] > 0.5) absScore += 1.5;
   if(strength[weakest]  < -0.5) absScore += 1.5;

   // 3. Alignment (0–2)
   double alignmentScore = GetAlignmentScore(pair);

   double finalScore = spreadScore + absScore + alignmentScore;
   finalScore = MathMax(0, MathMin(10, finalScore));

   outPair = pair;

   Print("PAIR: ", pair, " | Score: ", DoubleToString(finalScore,2), " | Direction: ",direction);

   return finalScore;
}

bool SymbolExists(string symbol)
{
   long trade_mode;
   return SymbolInfoInteger(symbol, SYMBOL_TRADE_MODE, trade_mode);
}

double GetAlignmentScore(string symbol)
{
   double m15 = GetStrength(symbol, PERIOD_M15);
   double h1  = GetStrength(symbol, PERIOD_H1);
   double h4  = GetStrength(symbol, PERIOD_H4);

   int aligned = 0;

   if(m15 > 0 && h1 > 0 && h4 > 0) aligned = 2;
   if(m15 < 0 && h1 < 0 && h4 < 0) aligned = 2;

   if((m15 > 0 && h1 > 0) || (m15 < 0 && h1 < 0))
      aligned = MathMax(aligned,1);

   return aligned; // 0–2
}

void InitPairs()
{
   int total = ArraySize(Symbols);
   ArrayResize(Pairs, total);

   for(int i=0; i<total; i++)
   {
      Pairs[i].symbol = Symbols[i]+InpSuffix;
      Pairs[i].index  = 0;
      Pairs[i].filled = false;
      ArrayInitialize(Pairs[i].history, 0);
      
      Pairs[i].rsiM1Handle = iRSI(streams[i].symbol,PERIOD_M1,14,PRICE_CLOSE);
      Pairs[i].bbM1Handle = iBands(streams[i].symbol,PERIOD_M1,20,0,2,PRICE_CLOSE);
      
      double initialLot = InpInitialLot;
      if (InpUseAutoLot) {
         initialLot = CalculateLotSize(InpBalancePerLot);
      }

      Pairs[i].buyGrid = new GridManager(streams[i].symbol,GRID_BUY,initialLot,InpGapPoints,0.04,InpMaxOrders);
      Pairs[i].buyGrid.SetGridMagicNumber(InpMagicBuy + i);
      Pairs[i].buyGrid.SetGridMultiplier(InpGridMultiplier);
      Pairs[i].buyGrid.SetGridMaxDD(InpMaxDD);
      
      
      Pairs[i].sellGrid = new GridManager(streams[i].symbol,GRID_SELL,initialLot,InpGapPoints,0.04,InpMaxOrders);
      Pairs[i].sellGrid.SetGridMagicNumber(InpMagicSell + i);
      Pairs[i].sellGrid.SetGridMultiplier(InpGridMultiplier);
      Pairs[i].sellGrid.SetGridMaxDD(InpMaxDD);
      
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

// Computer slope and acceleration
void UpdateMomentum(PairData &p)
{
   if(!p.filled)
   {
      p.slope = 0;
      p.accel = 0;
      return;
   }

   int i0 = (p.index - 1 + HISTORY) % HISTORY;
   int i1 = (p.index - 2 + HISTORY) % HISTORY;
   int i2 = (p.index - 3 + HISTORY) % HISTORY;
   int iOld = p.index;

   // slope = newest - oldest
   p.slope = p.history[i0] - p.history[iOld];

   double slope_now  = p.history[i0] - p.history[i1];
   double slope_prev = p.history[i1] - p.history[i2];

   p.accel = slope_now - slope_prev;
}
double CalculatePairScore(string symbol)
{
   double mtf = GetMTFStrength(symbol);

   // normalize into 0–10 range
   double score = (mtf + 2.0) * 2.5;

   return MathMax(0, MathMin(10, score));
}

void UpdateAllPairs()
{
   for(int i=0; i<ArraySize(Pairs); i++)
   {
      string sym = Pairs[i].symbol;
      double score = CalculatePairScore(sym);
      int dir      = GetDirection(sym);

      Pairs[i].score = score;
      Pairs[i].direction = dir;

      UpdatePairHistory(Pairs[i], score);
      UpdateMomentum(Pairs[i]);
   }
}

int GetBestPairIndex()
{
   int best = -1;
   double bestValue = -999;

   for(int i=0; i<ArraySize(Pairs); i++)
   {
      if(Pairs[i].direction == -1)
         continue; // skip unclear setups
      // composite ranking
      double value = 
         Pairs[i].score * 0.6 +
         Pairs[i].slope * 2.0 +
         Pairs[i].accel * 3.0;

      if(value > bestValue)
      {
         bestValue = value;
         best = i;
      }
   }

   return best;
}

void Process()
{
   UpdateAllPairs();

   int best = GetBestPairIndex();
   if(best < 0) return;

   PairData p = Pairs[best];

   string dirText = (p.direction == ORDER_TYPE_BUY) ? "BUY" : "SELL";

   Print("BEST: ", p.symbol,
         " | ", dirText,
         " | Score: ", DoubleToString(p.score,2),
         " | Slope: ", DoubleToString(p.slope,2),
         " | Accel: ", DoubleToString(p.accel,2));

   // Entry filter
   if(p.score >= 6.5 && p.slope > 0.3 && p.accel > 0.1)
   {
      Print("TRADE: ", dirText, " ", p.symbol);

      // Execute trade here
   }
   
   // Exit 
   if(p.slope < 0 && p.accel < 0)
   {
      // momentum reversal → exit or hedge
      // Print("EXIT: ", dirText, " ", p.symbol);
   }
   if(p.score > 8.5 && p.accel < 0)
   {
      // move exhausted → skip
   }
}
int GetDirection(string symbol)
{
   double m15 = GetStrength(symbol, PERIOD_M15);
   double h1  = GetStrength(symbol, PERIOD_H1);
   double h4  = GetStrength(symbol, PERIOD_H4);

   // Strong alignment
   if(m15 > 0 && h1 > 0 && h4 > 0)
      return ORDER_TYPE_BUY;

   if(m15 < 0 && h1 < 0 && h4 < 0)
      return ORDER_TYPE_SELL;

   // Weak alignment fallback (M15 + H1)
   if(m15 > 0 && h1 > 0)
      return ORDER_TYPE_BUY;

   if(m15 < 0 && h1 < 0)
      return ORDER_TYPE_SELL;

   return -1; // no clear direction
}