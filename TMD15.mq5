//+------------------------------------------------------------------+
//|                                                        TMD15.mq5 |
//|                                                              MDV |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "MDV"
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <GridManager.mqh>



enum ENUM_ONOFF
{
   OFF = 0,
   ON  = 1
};
ENUM_TIMEFRAMES TFfromString(string tfStr)
{
   if(tfStr=="M1")  return PERIOD_M1;
   if(tfStr=="M5")  return PERIOD_M5;
   if(tfStr=="M15") return PERIOD_M15;
   if(tfStr=="M30") return PERIOD_M30;
   if(tfStr=="H1")  return PERIOD_H1;
   if(tfStr=="H4")  return PERIOD_H4;
   if(tfStr=="D1")  return PERIOD_D1;

   return PERIOD_CURRENT;
}

string StringFromTF(ENUM_TIMEFRAMES strTf)
{
   if(strTf==PERIOD_M1)  return "M1";
   if(strTf==PERIOD_M5)  return "M5";
   if(strTf==PERIOD_M15) return "M15";
   if(strTf==PERIOD_M30) return "M30";
   if(strTf==PERIOD_H1)  return "H1";
   if(strTf==PERIOD_H4)  return "H4";
   if(strTf==PERIOD_D1)  return "D1";

   return "M15";
}
struct SymbolTF
{
   string           symbol;
   ENUM_TIMEFRAMES  tf;
   datetime         lastBarTime;
   datetime         nextBarTime;
   int               magicNrBuy;
   int               magicNrSell;
   int               magicNrRangeBuy;
   int               magicNrRangeSell;
   GridManager       *buyGrid;
   GridManager       *sellGrid;
   GridManager       *rangeGridBuy;
   GridManager       *rangeGridSell;
   int               currentTrend;
   int               previousTrend;
      int handleM1;
   int handleM5;
   int handleM15;
   int handleH1;
   int handleH4;
   int handleD1;
   int handleW1;

   int handleRSI;
   int handleADX;
   
   double rsiPrev;
   double adxPrev;
   
   int trendLength;
   
   double point;
   int digits;
   
   double tpPrice;
   double slPrice;
   
   int lastCandle;
};

// Direction constants for trend classification
int DIR_UP    =  1 ;  // Uptrend: higher highs, higher lows
int DIR_DOWN  = -1 ;  // Downtrend: lower highs, lower lows
int DIR_RANGE =  0  ; // Range/Sideways: no clear direction


input int      MagicBuy = 2204;
input int      MagicSell = 1981;
input int      MagicRangeBuy = 9975;
input int      MagicRangeSell = 4979;
input int PeriodMA = 14;
input int      InpTimerSeconds = 1;
input ENUM_ONOFF        StyleChart = ON;              // TMD Chart Style
input double  GridGapPct = 0.25; 
input double  MaxDD = 30;
input int     MaxOrders = 8;
input double  ProfitPct = 0.04;
input ENUM_ONOFF AllowBuy = ON; // Allow BUY
input ENUM_ONOFF AllowSell = ON; // Allow SELL
input double  FixedLot = 0.03; // LotSize
input ENUM_ONOFF AutoLot = OFF;
input double  BalancePerLot = 3000;
input ENUM_ONOFF AllowTrend = ON; // Allow Trading in Trending Conditions
input int MinTrendLBuy = 1; // Min Trend Length BUY
input int MinTrendLSell = 6; // Min Trend Length SELL
input ENUM_ONOFF AllowRange = ON; // Allow Trading in Ranging Conditions
input int MinTrendLRangeBuy = 1; // Min Trend Length Ranging BUY
input int MinTrendLRangeSell = 1; // Min Trend Length Ranging SELL
input double AdxRange = 50; // Max ADX in Range Conditions
input double RsiRangeBuy = 25; // Max RSI for Buy in Range Conditions
input double RsiRangeSell = 75; // Min RSI for Sell in Range Conditions 
input int MaxSpread = 20; // Max Spread
input ENUM_ONOFF ShowPanel = ON; // Show Info Panel
input ENUM_ONOFF EarlyEnd = ON;
input ENUM_ONOFF RangeRsiExit = ON; // Exit in Range on RSI Level
input double RiskReward = 2;
input ENUM_ONOFF CandleClose = ON; // Wait Candle Close

// Colors
color tmdGreen = C'38,166,154';
color tmdRed =    C'239,83,80';
color tmdOrange = C'255,152,0';
color tmdSilver = C'219,219,219';
color tmdBg = C'16,26,37';
color tmdSubtleBg = C'42,58,79';
color tmdBid = C'41, 98, 255';
color tmdAsk = C'247, 82, 95';

// Newsfilter
string newsFilter;

// Runtime variables
double gGridGapPct; double gMaxDD; double gProfitPct; double gBalancePerLot;
int gMaxOrders; int gMinTrendLBuy; int gMinTrendLSell; int gMinTrendLRangeBuy; int gMinTrendLRangeSell;
ENUM_ONOFF gAllowBuy; ENUM_ONOFF gAllowSell;ENUM_ONOFF gAllowTrend;ENUM_ONOFF gAllowRange;

SymbolTF stf;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//---

   // initialize input
   gGridGapPct = GridGapPct;
   gMaxDD = MaxDD;
   gProfitPct = ProfitPct;
   gBalancePerLot = BalancePerLot;
   gMaxOrders = MaxOrders;
   gMinTrendLBuy = MinTrendLBuy;
   gMinTrendLSell = MinTrendLSell;
   gMinTrendLRangeBuy = MinTrendLRangeBuy;
   gMinTrendLRangeSell = MinTrendLRangeSell;
   gAllowBuy = AllowBuy;
   gAllowSell = AllowSell;
   gAllowTrend = AllowTrend;
   gAllowRange = AllowRange;

   TesterHideIndicators(true);
   stf.symbol = _Symbol;
   stf.tf = _Period;
   stf.lastBarTime = 0;
   stf.magicNrBuy = MagicBuy;
   stf.magicNrSell = MagicSell;
   stf.magicNrRangeBuy = MagicRangeBuy;
   stf.magicNrRangeSell = MagicRangeSell;
   
            
   double Ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   stf.buyGrid = new GridManager(_Symbol, GRID_BUY, CalculateLotSize(gBalancePerLot), PriceToPoints((GridGapPct/100) * Ask,_Symbol), gProfitPct, gMaxOrders);
   stf.buyGrid.SetGridMagicNumber(stf.magicNrBuy);
   stf.buyGrid.SetGridMultiplier(1.0);
   stf.buyGrid.SetGridMaxDD(gMaxDD);
   if (AutoLot) {
         stf.buyGrid.SetLotSize(CalculateLotSize(gBalancePerLot));
      } else {
         stf.buyGrid.SetLotSize(FixedLot);
      }

   double Bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   stf.sellGrid = new GridManager(_Symbol, GRID_SELL, CalculateLotSize(gBalancePerLot), PriceToPoints((GridGapPct/100) * Bid,_Symbol), gProfitPct, gMaxOrders);
   stf.sellGrid.SetGridMagicNumber(stf.magicNrSell);
   stf.sellGrid.SetGridMultiplier(1.0);
   stf.sellGrid.SetGridMaxDD(gMaxDD);
   if (AutoLot) {
      stf.sellGrid.SetLotSize(CalculateLotSize(gBalancePerLot));
   } else {
      stf.sellGrid.SetLotSize(FixedLot);
   }
            
   stf.rangeGridBuy = new GridManager(_Symbol, GRID_BUY, CalculateLotSize(gBalancePerLot), PriceToPoints((GridGapPct/100) * Ask,_Symbol), gProfitPct, gMaxOrders);
   stf.rangeGridBuy.SetGridMagicNumber(stf.magicNrRangeBuy);
   stf.rangeGridBuy.SetGridMultiplier(1.0);
   stf.rangeGridBuy.SetGridMaxDD(gMaxDD);
   if (AutoLot) {
      stf.rangeGridBuy.SetLotSize(CalculateLotSize(gBalancePerLot));
   } else {
      stf.rangeGridBuy.SetLotSize(FixedLot);
   }   
            
   stf.rangeGridSell = new GridManager(_Symbol, GRID_SELL, CalculateLotSize(gBalancePerLot), PriceToPoints((GridGapPct/100) * Bid,_Symbol), gProfitPct, gMaxOrders);
   stf.rangeGridSell.SetGridMagicNumber(stf.magicNrRangeSell);
   stf.rangeGridSell.SetGridMultiplier(1.0);
   stf.rangeGridSell.SetGridMaxDD(gMaxDD);
   if (AutoLot) {
      stf.rangeGridSell.SetLotSize(CalculateLotSize(gBalancePerLot));
   } else {
      stf.rangeGridSell.SetLotSize(FixedLot);
   }      

   stf.handleM1  = iMA(_Symbol, PERIOD_M1, PeriodMA, 0, MODE_SMA, PRICE_CLOSE);
   stf.handleM5  = iMA(_Symbol, PERIOD_M5, PeriodMA, 0, MODE_SMA, PRICE_CLOSE);
   stf.handleM15 = iMA(_Symbol, PERIOD_M15, PeriodMA, 0, MODE_SMA, PRICE_CLOSE);
   stf.handleH1  = iMA(_Symbol, PERIOD_H1, PeriodMA, 0, MODE_SMA, PRICE_CLOSE);
   stf.handleH4  = iMA(_Symbol, PERIOD_H4, PeriodMA, 0, MODE_SMA, PRICE_CLOSE);
   stf.handleD1  = iMA(_Symbol, PERIOD_D1, PeriodMA, 0, MODE_SMA, PRICE_CLOSE);
   stf.handleW1  = iMA(_Symbol, PERIOD_W1, PeriodMA, 0, MODE_SMA, PRICE_CLOSE);
   
   stf.handleRSI = iRSI(_Symbol, _Period, PeriodMA, PRICE_CLOSE);
   stf.handleADX = iADX(_Symbol, _Period, PeriodMA);
   
   stf.point = SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   stf.digits = (int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
   
   if (ShowPanel) {
      CreatePanel();
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
      
      
      Print("==== TMD[1.0] Initialized ====");
      
    
//---
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
//---
   RemoveAllTMD();


   delete stf.buyGrid;
   delete stf.sellGrid;
   delete stf.rangeGridBuy;
   delete stf.rangeGridSell;
   IndicatorRelease(stf.handleM1);
   IndicatorRelease(stf.handleM5);
   IndicatorRelease(stf.handleM15);
   IndicatorRelease(stf.handleH1);
   IndicatorRelease(stf.handleH4);
   IndicatorRelease(stf.handleD1);
   IndicatorRelease(stf.handleW1);
   IndicatorRelease(stf.handleRSI);
   IndicatorRelease(stf.handleADX);

      
       Print("==== TMD[1.0] Stopped ====");
   
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
//---
      static datetime lastBar = 0;
      datetime currentBar = iTime(_Symbol, PERIOD_CURRENT, 0);
      
      double Ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double Bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      

      
      // Check market open
      if(!CheckTradeAllowed()) {
         return;
      }
      
      
 
      if (!CandleClose) {
         
          ExitConditions();
         
      }
   
      
      
      if (ShowPanel) {
         UpdatePanel(stf);
      }
      
      
   if(currentBar == lastBar)
      return; // wait until new candle
      
   
   lastBar = currentBar;
   
   ExitConditions();
   
   // Update: check PnL, open new grid order
   stf.sellGrid.Update();
   stf.buyGrid.Update();
   stf.rangeGridBuy.Update();
   stf.rangeGridSell.Update();
   
   // Run Strategy
   if (!IsTradeWindow()) {
      return;
   }

   double closePrice = iClose(_Symbol, _Period, 1);
   double openPrice = iOpen(_Symbol,_Period,1);
   
   if (closePrice > openPrice) {
      stf.lastCandle = DIR_UP;
   } else if (closePrice < openPrice) {
      stf.lastCandle = DIR_DOWN;
   }

    double buffer[];
    CopyBuffer(stf.handleM1, 0, 1, 1, buffer);
    double maM1 = buffer[0];
    CopyBuffer(stf.handleM5, 0, 1, 1, buffer);
    double maM5 = buffer[0];
    CopyBuffer(stf.handleM15, 0, 1, 1, buffer);
    double maM15 = buffer[0];
    CopyBuffer(stf.handleH1, 0, 1, 1, buffer);
    double maH1 = buffer[0];
    CopyBuffer(stf.handleH4, 0, 1, 1, buffer);
    double maH4 = buffer[0];
    CopyBuffer(stf.handleD1, 0, 1, 1, buffer);
    double maD1 = buffer[0];
     CopyBuffer(stf.handleW1, 0, 1, 1, buffer);
    double maW1 = buffer[0];
    CopyBuffer(stf.handleRSI, 0, 1, 1, buffer);
    double rsi = buffer[0];  
    CopyBuffer(stf.handleADX, 0, 1, 1, buffer);
    double adx = buffer[0];                                      


   // Trend
   if (closePrice > maM1 && closePrice > maM5 && closePrice > maM15 && closePrice > maH1 && closePrice > maH4) {
      stf.currentTrend = DIR_UP;
   } else
   if (closePrice < maM1 && closePrice < maM5 && closePrice < maM15 && closePrice < maH1 && closePrice < maH4 ) {
      stf.currentTrend = DIR_DOWN;
   } else {
      stf.currentTrend = DIR_RANGE;
      
   }
   
   // Trendlength
   if (stf.previousTrend != stf.currentTrend) {
      stf.trendLength = 0;
   } else {
      stf.trendLength++;
   }
   
   // Optimize Parameters
   OptimizeParameters();

   
   // Spread
   
   int spread = (int) SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   bool spreadFilter = spread <= MaxSpread ;
   
   // BUY - SELL
   
   if (gAllowTrend && spreadFilter && stf.trendLength >= gMinTrendLBuy && gAllowBuy && stf.currentTrend == DIR_UP && !hasOpenPositions(stf) && stf.lastCandle == DIR_UP ) {
      if (AutoLot) {
         stf.buyGrid.SetLotSize(CalculateLotSize(gBalancePerLot));
      } else {
         stf.buyGrid.SetLotSize(FixedLot);
      }
      
      
      stf.buyGrid.SetGridMaxDD(gMaxDD);  
      stf.buyGrid.SetGridMaxPositions(gMaxOrders);
      stf.buyGrid.SetGridGap(PriceToPoints((gGridGapPct/100) * Ask,_Symbol));
      stf.buyGrid.SetProfitPercent(gProfitPct);                
      stf.buyGrid.Start();
      stf.tpPrice = (1 + (gProfitPct/100))*Ask;
   }
   if (gAllowTrend && spreadFilter && stf.trendLength >= gMinTrendLSell && gAllowSell && stf.currentTrend == DIR_DOWN && !hasOpenPositions(stf) && stf.lastCandle == DIR_DOWN ) {
      if (AutoLot) {
         stf.sellGrid.SetLotSize(CalculateLotSize(gBalancePerLot));
      } else {
         stf.sellGrid.SetLotSize(FixedLot);
      }

      stf.sellGrid.SetGridMaxDD(gMaxDD);  
      stf.sellGrid.SetGridMaxPositions(gMaxOrders);
      stf.sellGrid.SetGridGap(PriceToPoints((gGridGapPct/100) * Bid,_Symbol));
      stf.sellGrid.SetProfitPercent(gProfitPct);
      stf.sellGrid.Start();
      stf.tpPrice = (1 - (gProfitPct/100))*Bid;
   }
   if (stf.currentTrend == DIR_RANGE ) {

      if (stf.buyGrid.GridPnL() + stf.sellGrid.GridPnL() > 0) {
         stf.buyGrid.CloseGrid();
         stf.sellGrid.CloseGrid();
         stf.tpPrice = 0;
         stf.slPrice = 0;
      }
      
      if (gAllowRange && stf.trendLength >= gMinTrendLRangeBuy && spreadFilter && adx < AdxRange && gAllowBuy && rsi < RsiRangeBuy && !hasOpenPositions(stf) && stf.lastCandle == DIR_DOWN   ) {
         
         double Ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         if (AutoLot) {
         stf.rangeGridBuy.SetLotSize(CalculateLotSize(gBalancePerLot));
         } else {
            stf.rangeGridBuy.SetLotSize(FixedLot);
         }
         stf.rangeGridBuy.SetGridMaxDD(gMaxDD);  
         stf.rangeGridBuy.SetGridMaxPositions(gMaxOrders);
         stf.rangeGridBuy.SetGridGap(PriceToPoints((gGridGapPct/100) * Ask,_Symbol));
         stf.rangeGridBuy.SetProfitPercent(gProfitPct);
         stf.rangeGridBuy.Start();
         stf.tpPrice = (1 + (gProfitPct/100))*Ask;
      }
      if (gAllowRange && stf.trendLength >= gMinTrendLRangeSell && spreadFilter && adx < AdxRange && gAllowSell && rsi > RsiRangeSell  && !hasOpenPositions(stf) && stf.lastCandle == DIR_UP ) {
          double Bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
          if (AutoLot) {
            stf.rangeGridSell.SetLotSize(CalculateLotSize(gBalancePerLot));
         } else {
            stf.rangeGridSell.SetLotSize(FixedLot);
         }
         stf.rangeGridSell.SetGridMaxDD(gMaxDD);  
         stf.rangeGridSell.SetGridMaxPositions(gMaxOrders);
         stf.rangeGridSell.SetGridGap(PriceToPoints((gGridGapPct/100) * Bid,_Symbol));
         stf.rangeGridSell.SetProfitPercent(gProfitPct);
         stf.rangeGridSell.Start();
         stf.tpPrice = (1 + (gProfitPct/100))*Bid;
      }
      
   }
   
   // Update previous values
   stf.adxPrev = adx;
   stf.rsiPrev = rsi;
   stf.previousTrend = stf.currentTrend;     
    
  }
  

//+------------------------------------------------------------------+
void RemoveAllTMD()
{
   int total = ObjectsTotal(0);

   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i);

      if(StringFind(name, "TMD_") == 0 ||
         StringFind(name, "TMD_") == 0)
      {
         ObjectDelete(0, name);
      }
   }
}
int SplitString(string inp, string separator, string &output[])
{
   return StringSplit(inp, StringGetCharacter(separator,0), output);
}

void ExitConditions() {
           double Ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double Bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
     // Check for changed trends  
            if (stf.buyGrid.CountPositions() > 0 && stf.currentTrend != DIR_UP) {
               // Update; only PnL no new grid orders
               stf.buyGrid.UpdatePnL();
               if (stf.trendLength >= 1)  {
                  if (stf.buyGrid.GridPnL() > 0 ) {
                     stf.buyGrid.CloseGrid();
                  } 
               }
            }
            
            if (stf.rangeGridBuy.CountPositions() > 0 && stf.currentTrend != DIR_RANGE) {
               // Update; only PnL no new grid orders
               stf.rangeGridBuy.UpdatePnL();
               if (stf.trendLength >= 1)  {
                  if (stf.rangeGridBuy.GridPnL() > 0 ) {
                     stf.rangeGridBuy.CloseGrid();
                  } 
               }
            }
            
            if (stf.rangeGridSell.CountPositions() > 0 && stf.currentTrend != DIR_RANGE) {
               // Update; only PnL no new grid orders
               stf.rangeGridSell.UpdatePnL();
               if (stf.trendLength >= 1)  {
                  if (stf.rangeGridSell.GridPnL() > 0 ) {
                     stf.rangeGridSell.CloseGrid();
                  } 
               }
            }
            
            if (stf.sellGrid.CountPositions() > 0 && stf.currentTrend != DIR_DOWN) {
               stf.sellGrid.UpdatePnL();
               if (stf.trendLength >= 1)  {
                  if (stf.sellGrid.GridPnL() > 0) {
                     stf.sellGrid.CloseGrid();
                  } 
               }
            }
            
      
            
            if (RangeRsiExit) {
               if (stf.rangeGridBuy.CountPositions() > 0 && stf.rsiPrev > 65) { 
                  if (stf.rangeGridBuy.GridPnL() > 0 ) { 
                     stf.rangeGridBuy.CloseGrid();
                     stf.tpPrice = 0;
                     stf.slPrice = 0;
                  }
               }
              if (stf.rangeGridSell.CountPositions() > 0 && stf.rsiPrev < 35) { 
                  if (stf.rangeGridSell.GridPnL() > 0 ) { 
                     stf.rangeGridSell.CloseGrid();
                     stf.tpPrice = 0;
                     stf.slPrice = 0;
                  }
               } 
            }
            
            if(EarlyEnd) {
               if (stf.buyGrid.CountPositions() > 0 && stf.trendLength >= 75) { 
                  stf.buyGrid.SetProfitPercent(gProfitPct/2);
               }
               if (stf.buyGrid.CountPositions() > 0 && stf.trendLength >= 150) { 
                  if (stf.buyGrid.GridPnL() > 0 ) {
                        stf.buyGrid.CloseGrid();
                        stf.tpPrice = 0;
                        stf.slPrice = 0;
                  } 
               }
              if (stf.sellGrid.CountPositions() > 0 && stf.trendLength >= 75) { 
                  stf.sellGrid.SetProfitPercent(gProfitPct/2);
               }
               if (stf.sellGrid.CountPositions() > 0 && stf.trendLength >= 150) { 
                  if (stf.sellGrid.GridPnL() > 0 ) {
                        stf.sellGrid.CloseGrid();
                        stf.tpPrice = 0;
                        stf.slPrice = 0;
                  } 
               }
              if (stf.rangeGridBuy.CountPositions() > 0 && stf.trendLength >= 75) { 
                  stf.rangeGridBuy.SetProfitPercent(gProfitPct/2);
               }
               if (stf.rangeGridBuy.CountPositions() > 0 && stf.trendLength >= 150) { 
                  if (stf.rangeGridBuy.GridPnL() > 0 ) {
                        stf.rangeGridBuy.CloseGrid();
                        stf.tpPrice = 0;
                        stf.slPrice = 0;
                  } 
               }  
               if (stf.rangeGridSell.CountPositions() > 0 && stf.trendLength >= 75) { 
                  stf.rangeGridSell.SetProfitPercent(gProfitPct/2);
               }
               if (stf.rangeGridSell.CountPositions() > 0 && stf.trendLength >= 150) { 
                  if (stf.rangeGridSell.GridPnL() > 0 ) {
                        stf.rangeGridSell.CloseGrid();
                        stf.tpPrice = 0;
                        stf.slPrice = 0;
                  } 
               }                 
            }
       
             // Alternative Profit taking
            
            
            double avgBuy = GetAveragePrice(MagicBuy);
            double avgSell = GetAveragePrice(MagicSell);     
            double avgBuyRange = GetAveragePrice(MagicRangeBuy);    
            double avgSellRange = GetAveragePrice(MagicRangeSell);
            
            
            if (stf.buyGrid.CountPositions() > 0 ) {
               stf.tpPrice = avgBuy*(1 + (gProfitPct/100));
               stf.slPrice = avgBuy*(1 - ((gProfitPct/100)*RiskReward));
               if (Bid > stf.tpPrice ) {
                  stf.buyGrid.CloseGrid();
                  stf.tpPrice = 0; 
                  stf.slPrice = 0;
               }      
            } 
             if (stf.rangeGridBuy.CountPositions() > 0 ) {
               stf.tpPrice = avgBuyRange*(1 + (gProfitPct/100));
               stf.slPrice = avgBuyRange*(1 - ((gProfitPct/100)*RiskReward));
               if (Bid > stf.tpPrice ) {
                  stf.rangeGridBuy.CloseGrid();
                  stf.tpPrice = 0; 
                  stf.slPrice = 0;
               }      
            }  
             if (stf.sellGrid.CountPositions() > 0 ) {
               stf.tpPrice = avgSell*(1 - (gProfitPct/100));
               stf.slPrice = avgSell*(1 + ((gProfitPct/100)*RiskReward));
               if (Ask < stf.tpPrice ) {
                  stf.sellGrid.CloseGrid();
                  stf.tpPrice = 0; 
                  stf.slPrice = 0;
               }      
            }
             if (stf.rangeGridSell.CountPositions() > 0 ) {
               stf.tpPrice = avgSellRange*(1 - (gProfitPct/100));
               stf.slPrice = avgSellRange*(1 + ((gProfitPct/100)*RiskReward));
               if (Ask < stf.tpPrice ) {
                  stf.rangeGridSell.CloseGrid();
                  stf.tpPrice = 0; 
                  stf.slPrice = 0;
               }      
            }     
}

bool CheckTradeAllowed()
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
  
 bool GetMAValue(int handle, double &val)
{
   double buffer[1];
   if(CopyBuffer(handle, 0, 0, 1, buffer) < 1) return false;
   val = buffer[0];
   return true;
}

int PriceToPoints(double priceDiff, string symbol)
{
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(point <= 0.0)
      return 0;

   return (int)MathRound(priceDiff / point);
}

bool IsTradeWindow()
{
   datetime now      = TimeCurrent();          // server time
   datetime tomorrow  = now + 86400;
   MqlDateTime dt,tTomorrow;
   
   TimeToStruct(now, dt);
   TimeToStruct(tomorrow,tTomorrow);
   
   int weekday = dt.day_of_week;               // 0=Sunday, 1=Monday, ... 6=Saturday
   int minute = dt.min;
   int hour    = dt.hour;
   int year = dt.year;
   int month = dt.mon;
   int day = dt.day;
   
   if (hour >= 22 || hour < 2) {
      return true;
   }
   if (hour == 15 && minute >= 15 ) {
      return false;
   }
   
   // Block election week
   if (year == 2020) {
      if (month == 10 && day >= 30 ) {
         return false;
      }
      if (month == 11 && day <= 5) {
         return false;
      }
   }
   if (year == 2025) {
     if (month == 4 && day == 4) {
         return false;
      }
      if (month == 6 && day == 16) {
         return false;
      }
   }
   if (year == 2024) {


      if (month == 10 && day >= 30 ) {
         return false;
      }
      if (month == 11 && day <= 5) {
         return false;
      }
   }
   if (year == 2028) {
      if (month == 10 && day >= 30 ) {
         return false;
      }
      if (month == 11 && day <= 8) {
         return false;
      }
   }
   if (year == 2032) {
      if (month == 10 && day >= 30 ) {
         return false;
      }
      if (month == 11 && day <= 8) {
         return false;
      }
   }   
   return true;      // trading allowed
}

//+------------------------------------------------------------------+
//| Blocks NFP (1st or 2nd Friday) and ADP (Wednesdays before them)
//+------------------------------------------------------------------+
bool IsNfpOrAdpDay(datetime t = 0)
{
   if(t == 0)
      t = TimeCurrent();

   MqlDateTime today;
   TimeToStruct(t, today);

   // --- find weekday of 1st day of month
   MqlDateTime firstDay;
   firstDay.year = today.year;
   firstDay.mon  = today.mon;
   firstDay.day  = 1;
   firstDay.hour = 0;
   firstDay.min  = 0;
   firstDay.sec  = 0;

   datetime first_time = StructToTime(firstDay);

   MqlDateTime firstStruct;
   TimeToStruct(first_time, firstStruct);

   int first_wday = firstStruct.day_of_week; // 0=Sun ... 6=Sat

   // --- first Friday
   int firstFriday = 1 + (5 - first_wday + 7) % 7;
   int secondFriday = firstFriday + 7;

   // --- block NFP Fridays
   if(today.day_of_week == 5)
   {
      if(today.day == firstFriday || today.day == secondFriday)
         newsFilter = "New Trades Disabled: NFP/ADP";
         return true;
   }

   // --- block ADP Wednesdays
   if(today.day_of_week == 3)
   {
      if(today.day == firstFriday - 2 || today.day == secondFriday - 2)
         newsFilter = "New Trades Disabled: NFP/ADP";
         return true;
   }
   newsFilter = " - ";
   return false;
}

void CreatePanel() { 

   string bg = "TMD_PANEL_BG";
   if(!ObjectCreate(0,bg,OBJ_RECTANGLE_LABEL,0,0,0))
      return;
   ObjectSetInteger(0,bg,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,bg,OBJPROP_XDISTANCE,20); 
   ObjectSetInteger(0,bg,OBJPROP_YDISTANCE,30);
   ObjectSetInteger(0,bg,OBJPROP_XSIZE,270);
   ObjectSetInteger(0,bg,OBJPROP_YSIZE,390);
   ObjectSetInteger(0,bg,OBJPROP_COLOR,C'10,16,28');
   ObjectSetInteger(0,bg,OBJPROP_BGCOLOR,C'10,16,28');
   ObjectSetInteger(0, bg, OBJPROP_BORDER_COLOR, C'10,16,28');
   ObjectSetInteger(0,bg,OBJPROP_BORDER_TYPE,BORDER_FLAT);
   ObjectSetInteger(0,bg,OBJPROP_STYLE,STYLE_SOLID);
   ObjectSetInteger(0,bg,OBJPROP_BACK,false);
   ObjectSetInteger(0,bg,OBJPROP_WIDTH,1);
   ObjectSetInteger(0, bg, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, bg, OBJPROP_HIDDEN, false);
   
   string tb = "TMD_TB";
   if(!ObjectCreate(0,tb,OBJ_RECTANGLE_LABEL,0,0,0))
      return;
   ObjectSetInteger(0,tb,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,tb,OBJPROP_XDISTANCE,23); 
   ObjectSetInteger(0,tb,OBJPROP_YDISTANCE,33);
   ObjectSetInteger(0,tb,OBJPROP_XSIZE,264);
   ObjectSetInteger(0,tb,OBJPROP_YSIZE,28);
   ObjectSetInteger(0,tb,OBJPROP_COLOR,C'10,16,28');
   ObjectSetInteger(0,tb,OBJPROP_BGCOLOR,C'10,16,28');
   ObjectSetInteger(0, tb, OBJPROP_BORDER_COLOR, C'10,16,28');
   ObjectSetInteger(0,tb,OBJPROP_BORDER_TYPE,BORDER_FLAT);
   ObjectSetInteger(0,tb,OBJPROP_STYLE,STYLE_SOLID);
   ObjectSetInteger(0,tb,OBJPROP_BACK,false);
   ObjectSetInteger(0,tb,OBJPROP_WIDTH,1);
   ObjectSetInteger(0, tb, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, tb, OBJPROP_HIDDEN, false);
   
      string s1 = "TMD_S1";
   if(!ObjectCreate(0,s1,OBJ_RECTANGLE_LABEL,0,0,0))
      return;
   ObjectSetInteger(0,s1,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,s1,OBJPROP_XDISTANCE,30); 
   ObjectSetInteger(0,s1,OBJPROP_YDISTANCE,65);
   ObjectSetInteger(0,s1,OBJPROP_XSIZE,250);
   ObjectSetInteger(0,s1,OBJPROP_YSIZE,1);
   ObjectSetInteger(0,s1,OBJPROP_COLOR,clrBlack);
   ObjectSetInteger(0,s1,OBJPROP_BGCOLOR,C'25,40,55');
   ObjectSetInteger(0, s1, OBJPROP_BORDER_COLOR, tmdBg);
   ObjectSetInteger(0,s1,OBJPROP_BORDER_TYPE,BORDER_FLAT);
   ObjectSetInteger(0,s1,OBJPROP_STYLE,STYLE_SOLID);
   ObjectSetInteger(0,s1,OBJPROP_BACK,false);
   ObjectSetInteger(0,s1,OBJPROP_WIDTH,1);
   ObjectSetInteger(0, s1, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, s1, OBJPROP_HIDDEN, false);
   
      string s2 = "TMD_S2";
   if(!ObjectCreate(0,s2,OBJ_RECTANGLE_LABEL,0,0,0))
      return;
   ObjectSetInteger(0,s2,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,s2,OBJPROP_XDISTANCE,30); 
   ObjectSetInteger(0,s2,OBJPROP_YDISTANCE,134);
   ObjectSetInteger(0,s2,OBJPROP_XSIZE,250);
   ObjectSetInteger(0,s2,OBJPROP_YSIZE,1);
   ObjectSetInteger(0,s2,OBJPROP_COLOR,clrBlack);
   ObjectSetInteger(0,s2,OBJPROP_BGCOLOR,C'25,40,55');
   ObjectSetInteger(0, s2, OBJPROP_BORDER_COLOR, tmdBg);
   ObjectSetInteger(0,s2,OBJPROP_BORDER_TYPE,BORDER_FLAT);
   ObjectSetInteger(0,s2,OBJPROP_STYLE,STYLE_SOLID);
   ObjectSetInteger(0,s2,OBJPROP_BACK,false);
   ObjectSetInteger(0,s2,OBJPROP_WIDTH,1);
   ObjectSetInteger(0, s2, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, s2, OBJPROP_HIDDEN, false);
   
   
   
      // ---------- Panel Title ----------
   string ol = "TMD_PANEL_ONLINE_LOGO";
   if(!ObjectCreate(0,ol,OBJ_LABEL,0,0,0))
      return;
   ObjectSetInteger(0,ol,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,ol,OBJPROP_ANCHOR,ANCHOR_LEFT_UPPER);
   ObjectSetInteger(0,ol,OBJPROP_XDISTANCE,30);
   ObjectSetInteger(0,ol,OBJPROP_YDISTANCE,40);
   ObjectSetInteger(0,ol,OBJPROP_FONTSIZE,9);
   ObjectSetString(0,ol,OBJPROP_FONT,"Consolas");
   ObjectSetInteger(0,ol,OBJPROP_COLOR,C'0,230,120');
   ObjectSetString(0,ol,OBJPROP_TEXT,"●");
   
   string online = "TMD_PANEL_ONLINE_TXT";
   if(!ObjectCreate(0,online,OBJ_LABEL,0,0,0))
      return;
   ObjectSetInteger(0,online,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,online,OBJPROP_ANCHOR,ANCHOR_LEFT_UPPER);
   ObjectSetInteger(0,online,OBJPROP_XDISTANCE,42);
   ObjectSetInteger(0,online,OBJPROP_YDISTANCE,41);
   ObjectSetInteger(0,online,OBJPROP_FONTSIZE,9);
   ObjectSetString(0,online,OBJPROP_FONT,"Consolas");
   ObjectSetInteger(0,online,OBJPROP_COLOR,C'0,180,180');
   ObjectSetString(0,online,OBJPROP_TEXT,"ONLINE");
   
   string title = "TMD_PANEL_TITLE";
   if(!ObjectCreate(0,title,OBJ_LABEL,0,0,0))
      return;
   ObjectSetInteger(0,title,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,title,OBJPROP_ANCHOR,ANCHOR_UPPER);
   ObjectSetInteger(0,title,OBJPROP_XDISTANCE,155);
   ObjectSetInteger(0,title,OBJPROP_YDISTANCE,38);
   ObjectSetInteger(0,title,OBJPROP_FONTSIZE,11);
   ObjectSetString(0,title,OBJPROP_FONT,"Consolas");
   ObjectSetInteger(0,title,OBJPROP_COLOR,C'0,230,230');
   ObjectSetString(0,title,OBJPROP_TEXT,"◆ T M D ◆");
   
   string l1 = "TMD_L1";
   if(!ObjectCreate(0,l1,OBJ_LABEL,0,0,0))
      return;
   ObjectSetInteger(0,l1,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,l1,OBJPROP_ANCHOR,ANCHOR_LEFT_UPPER);
   ObjectSetInteger(0,l1,OBJPROP_XDISTANCE,30);
   ObjectSetInteger(0,l1,OBJPROP_YDISTANCE,72);
   ObjectSetInteger(0,l1,OBJPROP_FONTSIZE,10);
   ObjectSetString(0,l1,OBJPROP_FONT,"Consolas");
   ObjectSetInteger(0,l1,OBJPROP_COLOR,C'70,90,110');
   ObjectSetString(0,l1,OBJPROP_TEXT,"BALANCE");
   
      
   string v1 = "TMD_V1";
   if(!ObjectCreate(0,v1,OBJ_LABEL,0,0,0))
      return;
   ObjectSetInteger(0,v1,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,v1,OBJPROP_ANCHOR,ANCHOR_RIGHT_UPPER);
   ObjectSetInteger(0,v1,OBJPROP_XDISTANCE,280);
   ObjectSetInteger(0,v1,OBJPROP_YDISTANCE,72);
   ObjectSetInteger(0,v1,OBJPROP_FONTSIZE,10);
   ObjectSetString(0,v1,OBJPROP_FONT,"Consolas");
   ObjectSetInteger(0,v1,OBJPROP_COLOR,C'180,200,220');
   ObjectSetString(0,v1,OBJPROP_TEXT,DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE),2));
   
      string l2 = "TMD_L2";
   if(!ObjectCreate(0,l2,OBJ_LABEL,0,0,0))
      return;
   ObjectSetInteger(0,l2,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,l2,OBJPROP_ANCHOR,ANCHOR_LEFT_UPPER);
   ObjectSetInteger(0,l2,OBJPROP_XDISTANCE,30);
   ObjectSetInteger(0,l2,OBJPROP_YDISTANCE,91);
   ObjectSetInteger(0,l2,OBJPROP_FONTSIZE,10);
   ObjectSetString(0,l2,OBJPROP_FONT,"Consolas");
   ObjectSetInteger(0,l2,OBJPROP_COLOR,C'70,90,110');
   ObjectSetString(0,l2,OBJPROP_TEXT,"EQUITY");
   
      string v2 = "TMD_V2";
   if(!ObjectCreate(0,v2,OBJ_LABEL,0,0,0))
      return;
   ObjectSetInteger(0,v2,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,v2,OBJPROP_ANCHOR,ANCHOR_RIGHT_UPPER);
   ObjectSetInteger(0,v2,OBJPROP_XDISTANCE,280);
   ObjectSetInteger(0,v2,OBJPROP_YDISTANCE,91);
   ObjectSetInteger(0,v2,OBJPROP_FONTSIZE,10);
   ObjectSetString(0,v2,OBJPROP_FONT,"Consolas");
   ObjectSetInteger(0,v2,OBJPROP_COLOR,C'180,200,220');
   ObjectSetString(0,v2,OBJPROP_TEXT,DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY),2));
   
   string l3 = "TMD_L3";
   if(!ObjectCreate(0,l3,OBJ_LABEL,0,0,0))
      return;
   ObjectSetInteger(0,l3,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,l3,OBJPROP_ANCHOR,ANCHOR_LEFT_UPPER);
   ObjectSetInteger(0,l3,OBJPROP_XDISTANCE,30);
   ObjectSetInteger(0,l3,OBJPROP_YDISTANCE,110);
   ObjectSetInteger(0,l3,OBJPROP_FONTSIZE,10);
   ObjectSetString(0,l3,OBJPROP_FONT,"Consolas");
   ObjectSetInteger(0,l3,OBJPROP_COLOR,C'70,90,110');
   ObjectSetString(0,l3,OBJPROP_TEXT,"P / L");
   
   string v3 = "TMD_V3";
   if(!ObjectCreate(0,v3,OBJ_LABEL,0,0,0))
      return;
   ObjectSetInteger(0,v3,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,v3,OBJPROP_ANCHOR,ANCHOR_RIGHT_UPPER);
   ObjectSetInteger(0,v3,OBJPROP_XDISTANCE,280);
   ObjectSetInteger(0,v3,OBJPROP_YDISTANCE,110);
   ObjectSetInteger(0,v3,OBJPROP_FONTSIZE,10);
   ObjectSetString(0,v3,OBJPROP_FONT,"Consolas");
   ObjectSetInteger(0,v3,OBJPROP_COLOR,C'0,230,120');
   ObjectSetString(0,v3,OBJPROP_TEXT,"+"+DoubleToString(AccountInfoDouble(ACCOUNT_PROFIT),2));
   
      string l4 = "TMD_L4";
   if(!ObjectCreate(0,l4,OBJ_LABEL,0,0,0))
      return;
   ObjectSetInteger(0,l4,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,l4,OBJPROP_ANCHOR,ANCHOR_LEFT_UPPER);
   ObjectSetInteger(0,l4,OBJPROP_XDISTANCE,30);
   ObjectSetInteger(0,l4,OBJPROP_YDISTANCE,141);
   ObjectSetInteger(0,l4,OBJPROP_FONTSIZE,10);
   ObjectSetString(0,l4,OBJPROP_FONT,"Consolas");
   ObjectSetInteger(0,l4,OBJPROP_COLOR,C'70,90,110');
   ObjectSetString(0,l4,OBJPROP_TEXT,"TREND");
   
   string v4 = "TMD_V4";
   if(!ObjectCreate(0,v4,OBJ_LABEL,0,0,0))
      return;
   ObjectSetInteger(0,v4,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,v4,OBJPROP_ANCHOR,ANCHOR_RIGHT_UPPER);
   ObjectSetInteger(0,v4,OBJPROP_XDISTANCE,280);
   ObjectSetInteger(0,v4,OBJPROP_YDISTANCE,141);
   ObjectSetInteger(0,v4,OBJPROP_FONTSIZE,10);
   ObjectSetString(0,v4,OBJPROP_FONT,"Consolas");
   ObjectSetInteger(0,v4,OBJPROP_COLOR,C'0,190,190');
   ObjectSetString(0,v4,OBJPROP_TEXT,"Undefined");
   
         string l5 = "TMD_L5";
   if(!ObjectCreate(0,l5,OBJ_LABEL,0,0,0))
      return;
   ObjectSetInteger(0,l5,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,l5,OBJPROP_ANCHOR,ANCHOR_LEFT_UPPER);
   ObjectSetInteger(0,l5,OBJPROP_XDISTANCE,30);
   ObjectSetInteger(0,l5,OBJPROP_YDISTANCE,160);
   ObjectSetInteger(0,l5,OBJPROP_FONTSIZE,10);
   ObjectSetString(0,l5,OBJPROP_FONT,"Consolas");
   ObjectSetInteger(0,l5,OBJPROP_COLOR,C'70,90,110');
   ObjectSetString(0,l5,OBJPROP_TEXT,"SPREAD");
   
    string v5 = "TMD_V5";
   if(!ObjectCreate(0,v5,OBJ_LABEL,0,0,0))
      return;
   ObjectSetInteger(0,v5,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,v5,OBJPROP_ANCHOR,ANCHOR_RIGHT_UPPER);
   ObjectSetInteger(0,v5,OBJPROP_XDISTANCE,280);
   ObjectSetInteger(0,v5,OBJPROP_YDISTANCE,160);
   ObjectSetInteger(0,v5,OBJPROP_FONTSIZE,10);
   ObjectSetString(0,v5,OBJPROP_FONT,"Consolas");
   ObjectSetInteger(0,v5,OBJPROP_COLOR,C'0,230,120');
   ObjectSetString(0,v5,OBJPROP_TEXT,IntegerToString(SymbolInfoInteger(_Symbol, SYMBOL_SPREAD)));
   
      string l6 = "TMD_L6";
   if(!ObjectCreate(0,l6,OBJ_LABEL,0,0,0))
      return;
   ObjectSetInteger(0,l6,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,l6,OBJPROP_ANCHOR,ANCHOR_LEFT_UPPER);
   ObjectSetInteger(0,l6,OBJPROP_XDISTANCE,30);
   ObjectSetInteger(0,l6,OBJPROP_YDISTANCE,179);
   ObjectSetInteger(0,l6,OBJPROP_FONTSIZE,10);
   ObjectSetString(0,l6,OBJPROP_FONT,"Consolas");
   ObjectSetInteger(0,l6,OBJPROP_COLOR,C'70,90,110');
   ObjectSetString(0,l6,OBJPROP_TEXT,"RSI");
   
       string v6 = "TMD_V6";
   if(!ObjectCreate(0,v6,OBJ_LABEL,0,0,0))
      return;
   ObjectSetInteger(0,v6,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,v6,OBJPROP_ANCHOR,ANCHOR_RIGHT_UPPER);
   ObjectSetInteger(0,v6,OBJPROP_XDISTANCE,280);
   ObjectSetInteger(0,v6,OBJPROP_YDISTANCE,179);
   ObjectSetInteger(0,v6,OBJPROP_FONTSIZE,10);
   ObjectSetString(0,v6,OBJPROP_FONT,"Consolas");
   ObjectSetInteger(0,v6,OBJPROP_COLOR,C'0,230,120');
   ObjectSetString(0,v6,OBJPROP_TEXT,"50");
   
         string l7 = "TMD_L7";
   if(!ObjectCreate(0,l7,OBJ_LABEL,0,0,0))
      return;
   ObjectSetInteger(0,l7,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,l7,OBJPROP_ANCHOR,ANCHOR_LEFT_UPPER);
   ObjectSetInteger(0,l7,OBJPROP_XDISTANCE,30);
   ObjectSetInteger(0,l7,OBJPROP_YDISTANCE,198);
   ObjectSetInteger(0,l7,OBJPROP_FONTSIZE,10);
   ObjectSetString(0,l7,OBJPROP_FONT,"Consolas");
   ObjectSetInteger(0,l7,OBJPROP_COLOR,C'70,90,110');
   ObjectSetString(0,l7,OBJPROP_TEXT,"ADX");
   
       string v7 = "TMD_V7";
   if(!ObjectCreate(0,v7,OBJ_LABEL,0,0,0))
      return;
   ObjectSetInteger(0,v7,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,v7,OBJPROP_ANCHOR,ANCHOR_RIGHT_UPPER);
   ObjectSetInteger(0,v7,OBJPROP_XDISTANCE,280);
   ObjectSetInteger(0,v7,OBJPROP_YDISTANCE,198);
   ObjectSetInteger(0,v7,OBJPROP_FONTSIZE,10);
   ObjectSetString(0,v7,OBJPROP_FONT,"Consolas");
   ObjectSetInteger(0,v7,OBJPROP_COLOR,C'0,230,120');
   ObjectSetString(0,v7,OBJPROP_TEXT,"Undefined");
   
            string l8 = "TMD_L8";
   if(!ObjectCreate(0,l8,OBJ_LABEL,0,0,0))
      return;
   ObjectSetInteger(0,l8,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,l8,OBJPROP_ANCHOR,ANCHOR_LEFT_UPPER);
   ObjectSetInteger(0,l8,OBJPROP_XDISTANCE,30);
   ObjectSetInteger(0,l8,OBJPROP_YDISTANCE,217);
   ObjectSetInteger(0,l8,OBJPROP_FONTSIZE,10);
   ObjectSetString(0,l8,OBJPROP_FONT,"Consolas");
   ObjectSetInteger(0,l8,OBJPROP_COLOR,C'70,90,110');
   ObjectSetString(0,l8,OBJPROP_TEXT,"Trend Length");
   
       string v8 = "TMD_V8";
   if(!ObjectCreate(0,v8,OBJ_LABEL,0,0,0))
      return;
   ObjectSetInteger(0,v8,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,v8,OBJPROP_ANCHOR,ANCHOR_RIGHT_UPPER);
   ObjectSetInteger(0,v8,OBJPROP_XDISTANCE,280);
   ObjectSetInteger(0,v8,OBJPROP_YDISTANCE,217);
   ObjectSetInteger(0,v8,OBJPROP_FONTSIZE,10);
   ObjectSetString(0,v8,OBJPROP_FONT,"Consolas");
   ObjectSetInteger(0,v8,OBJPROP_COLOR,C'0,230,120');
   ObjectSetString(0,v8,OBJPROP_TEXT,"Undefined");
   
   
   
   string l9 = "TMD_L9";
   if(!ObjectCreate(0,l9,OBJ_LABEL,0,0,0))
      return;
   ObjectSetInteger(0,l9,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,l9,OBJPROP_ANCHOR,ANCHOR_LEFT_UPPER);
   ObjectSetInteger(0,l9,OBJPROP_XDISTANCE,30);
   ObjectSetInteger(0,l9,OBJPROP_YDISTANCE,236);
   ObjectSetInteger(0,l9,OBJPROP_FONTSIZE,10);
   ObjectSetString(0,l9,OBJPROP_FONT,"Consolas");
   ObjectSetInteger(0,l9,OBJPROP_COLOR,C'70,90,110');
   if (AutoLot) {
      ObjectSetString(0,l9,OBJPROP_TEXT,"Autolot");
   } else {
      ObjectSetString(0,l9,OBJPROP_TEXT,"Fixed Lot");
   }
   
   
       string v9 = "TMD_V9";
   if(!ObjectCreate(0,v9,OBJ_LABEL,0,0,0))
      return;
   ObjectSetInteger(0,v9,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,v9,OBJPROP_ANCHOR,ANCHOR_RIGHT_UPPER);
   ObjectSetInteger(0,v9,OBJPROP_XDISTANCE,280);
   ObjectSetInteger(0,v9,OBJPROP_YDISTANCE,236);
   ObjectSetInteger(0,v9,OBJPROP_FONTSIZE,10);
   ObjectSetString(0,v9,OBJPROP_FONT,"Consolas");
   ObjectSetInteger(0,v9,OBJPROP_COLOR,tmdSilver);
   if (AutoLot) {
      ObjectSetString(0,v9,OBJPROP_TEXT,DoubleToString(CalculateLotSize(gBalancePerLot),2));
   } else {
      ObjectSetString(0,v9,OBJPROP_TEXT,DoubleToString(FixedLot,2));
   }
   
      string s3 = "TMD_S3";
   if(!ObjectCreate(0,s3,OBJ_RECTANGLE_LABEL,0,0,0))
      return;
   ObjectSetInteger(0,s3,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,s3,OBJPROP_XDISTANCE,30); 
   ObjectSetInteger(0,s3,OBJPROP_YDISTANCE,260);
   ObjectSetInteger(0,s3,OBJPROP_XSIZE,250);
   ObjectSetInteger(0,s3,OBJPROP_YSIZE,1);
   ObjectSetInteger(0,s3,OBJPROP_COLOR,clrBlack);
   ObjectSetInteger(0,s3,OBJPROP_BGCOLOR,C'25,40,55');
   ObjectSetInteger(0, s3, OBJPROP_BORDER_COLOR, tmdSubtleBg);
   ObjectSetInteger(0,s3,OBJPROP_BORDER_TYPE,BORDER_FLAT);
   ObjectSetInteger(0,s3,OBJPROP_STYLE,STYLE_SOLID);
   ObjectSetInteger(0,s3,OBJPROP_BACK,false);
   ObjectSetInteger(0,s3,OBJPROP_WIDTH,1);
   ObjectSetInteger(0, s3, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, s3, OBJPROP_HIDDEN, false);   
   
      string l10 = "TMD_L10";
   if(!ObjectCreate(0,l10,OBJ_LABEL,0,0,0))
      return;
   ObjectSetInteger(0,l10,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,l10,OBJPROP_ANCHOR,ANCHOR_LEFT_UPPER);
   ObjectSetInteger(0,l10,OBJPROP_XDISTANCE,30);
   ObjectSetInteger(0,l10,OBJPROP_YDISTANCE,267);
   ObjectSetInteger(0,l10,OBJPROP_FONTSIZE,10);
   ObjectSetString(0,l10,OBJPROP_FONT,"Consolas");
   ObjectSetInteger(0,l10,OBJPROP_COLOR,C'70,90,110');
   ObjectSetString(0,l10,OBJPROP_TEXT,"TP");
   
   string v10 = "TMD_V10";
   if(!ObjectCreate(0,v10,OBJ_LABEL,0,0,0))
      return;
   ObjectSetInteger(0,v10,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,v10,OBJPROP_ANCHOR,ANCHOR_RIGHT_UPPER);
   ObjectSetInteger(0,v10,OBJPROP_XDISTANCE,280);
   ObjectSetInteger(0,v10,OBJPROP_YDISTANCE,267);
   ObjectSetInteger(0,v10,OBJPROP_FONTSIZE,10);
   ObjectSetString(0,v10,OBJPROP_FONT,"Consolas");
   ObjectSetInteger(0,v10,OBJPROP_COLOR,tmdSilver);
   ObjectSetString(0,v10,OBJPROP_TEXT,"-");
   

}

void UpdatePanel(SymbolTF &s) {
   
   ObjectSetString(0,"TMD_V1",OBJPROP_TEXT,DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE),2));
   ObjectSetString(0,"TMD_V2",OBJPROP_TEXT,DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY),2));
   
   double profit = AccountInfoDouble(ACCOUNT_PROFIT);
   ObjectSetString(0,"TMD_V3",OBJPROP_TEXT,DoubleToString(profit,2));
   if (profit > 0) {
      ObjectSetInteger(0,"TMD_V3",OBJPROP_COLOR,tmdGreen);
   } else if (profit < 0 ) {
      ObjectSetInteger(0,"TMD_V3",OBJPROP_COLOR,tmdRed);
   } else {
      ObjectSetInteger(0,"TMD_V3",OBJPROP_COLOR,tmdSilver);
   }
   
   if (s.currentTrend == DIR_UP) {
      ObjectSetInteger(0,"TMD_V4",OBJPROP_COLOR,C'0,230,230');
      ObjectSetString(0,"TMD_V4",OBJPROP_TEXT,"UP");
   } else if (s.currentTrend == DIR_DOWN) {
      ObjectSetString(0,"TMD_V4",OBJPROP_TEXT,"DOWN");
      ObjectSetInteger(0,"TMD_V4",OBJPROP_COLOR,C'180,40,220');
   } else {
      ObjectSetString(0,"TMD_V4",OBJPROP_TEXT,"RANGE");
      ObjectSetInteger(0,"TMD_V4",OBJPROP_COLOR,tmdSilver);
   }
   
   int spread = (int) SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   ObjectSetString(0,"TMD_V5",OBJPROP_TEXT,IntegerToString(spread));
   if (spread > MaxSpread) {
      ObjectSetInteger(0,"TMD_V5",OBJPROP_COLOR,tmdOrange);
   } else {
      ObjectSetInteger(0,"TMD_V5",OBJPROP_COLOR,tmdGreen);
   }
   
   double rsi = s.rsiPrev;
   ObjectSetString(0,"TMD_V6",OBJPROP_TEXT,DoubleToString(rsi,2));
   if (s.currentTrend == DIR_UP) {
      if ( rsi > 50 && rsi < 80) {
         ObjectSetInteger(0,"TMD_V6",OBJPROP_COLOR,tmdGreen);
      } else if (rsi > 80) {
          ObjectSetInteger(0,"TMD_V6",OBJPROP_COLOR,tmdOrange);
      } else if (rsi < 50) {
         ObjectSetInteger(0,"TMD_V6",OBJPROP_COLOR,tmdRed);
      }
   } else
   if (s.currentTrend == DIR_DOWN) {
      if ( rsi < 50 && rsi > 20) {
         ObjectSetInteger(0,"TMD_V6",OBJPROP_COLOR,tmdGreen);
      } else if (rsi < 20) {
          ObjectSetInteger(0,"TMD_V6",OBJPROP_COLOR,tmdOrange);
      } else if (rsi > 50) {
         ObjectSetInteger(0,"TMD_V6",OBJPROP_COLOR,tmdRed);
      }
   } else {
      if (rsi < RsiRangeBuy && gAllowBuy) {
         ObjectSetInteger(0,"TMD_V6",OBJPROP_COLOR,tmdGreen);
      } else if (rsi > RsiRangeSell && gAllowSell) {
         ObjectSetInteger(0,"TMD_V6",OBJPROP_COLOR,tmdGreen);
      } else {
         ObjectSetInteger(0,"TMD_V6",OBJPROP_COLOR,tmdSilver);
      }
      
   }
   
   double adx = s.adxPrev;
   ObjectSetString(0,"TMD_V7",OBJPROP_TEXT,DoubleToString(adx,2));
   if (s.currentTrend == DIR_RANGE) {
      if (adx < AdxRange) {
         ObjectSetInteger(0,"TMD_V7",OBJPROP_COLOR,tmdGreen);
      } else {
         ObjectSetInteger(0,"TMD_V7",OBJPROP_COLOR,tmdOrange);
      }
   }
   else if (adx > 65) {
      ObjectSetInteger(0,"TMD_V7",OBJPROP_COLOR,tmdRed);
   } else {
      ObjectSetInteger(0,"TMD_V7",OBJPROP_COLOR,tmdGreen);
   }
   
   ObjectSetString(0,"TMD_V8",OBJPROP_TEXT,IntegerToString(s.trendLength));
   if (s.currentTrend == DIR_RANGE) {
      if (gAllowRange && ((s.trendLength >= gMinTrendLRangeBuy && gAllowBuy) ||  (s.trendLength >= gMinTrendLRangeSell && gAllowSell))  ) {
         ObjectSetInteger(0,"TMD_V8",OBJPROP_COLOR,tmdGreen);
      } else  {
         ObjectSetInteger(0,"TMD_V8",OBJPROP_COLOR,tmdSilver);
      }
   } else if (s.currentTrend == DIR_UP) {
      if (gAllowTrend && (s.trendLength >= gMinTrendLBuy && gAllowBuy)){
         ObjectSetInteger(0,"TMD_V8",OBJPROP_COLOR,tmdGreen);
      } else if (gAllowTrend && (s.trendLength < gMinTrendLBuy && gAllowBuy)) {
         ObjectSetInteger(0,"TMD_V8",OBJPROP_COLOR,tmdOrange);
      } else {
         ObjectSetInteger(0,"TMD_V8",OBJPROP_COLOR,tmdSilver);
      }
   }else if (s.currentTrend == DIR_DOWN) {
      if (gAllowTrend && (s.trendLength >= gMinTrendLSell && gAllowSell)){
         ObjectSetInteger(0,"TMD_V8",OBJPROP_COLOR,tmdGreen);
      } else if (gAllowTrend && (s.trendLength < gMinTrendLSell && gAllowSell)) {
         ObjectSetInteger(0,"TMD_V8",OBJPROP_COLOR,tmdOrange);
      } else {
         ObjectSetInteger(0,"TMD_V8",OBJPROP_COLOR,tmdSilver);
      }
   }
   
   if (AutoLot) {
      ObjectSetString(0,"TMD_L9",OBJPROP_TEXT,"Autolot");
      ObjectSetString(0,"TMD_V9",OBJPROP_TEXT, DoubleToString(CalculateLotSize(gBalancePerLot),2));
   } else {
      ObjectSetString(0,"TMD_L9",OBJPROP_TEXT,"Fixed Lot");
      ObjectSetString(0,"TMD_V9",OBJPROP_TEXT, DoubleToString(FixedLot,2));
   }
   
   if (hasOpenPositions(s)) {
      if (s.tpPrice != 0) {
         ObjectSetString(0,"TMD_V10",OBJPROP_TEXT, DoubleToString(s.tpPrice,s.digits));
      } else {
         ObjectSetString(0,"TMD_V10",OBJPROP_TEXT, "-");
      }
   } else {
      ObjectSetString(0,"TMD_V10",OBJPROP_TEXT, "-");
   }
   
   

}

//+------------------------------------------------------------------+
//| Calculate lot size based on account balance                      |
//| Default: 0.01 lots per 500 balance                               |
//+------------------------------------------------------------------+
double CalculateLotSize(double balancePerLot = 1600.0, double lotPerBalance = 0.01)
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

void OptimizeParameters() {
   datetime now      = TimeCurrent();          // server time
   MqlDateTime dt;
   TimeToStruct(now, dt);
   int year = dt.year;
   if (year == 2020) {
      gGridGapPct = 0.10;
      gMaxDD = 0;
      gMaxOrders = 16;
      gProfitPct = 0.04;
      gAllowBuy = ON;
      gAllowSell = ON;
      gBalancePerLot = 1000;
      gAllowTrend = ON;
      gMinTrendLBuy = 7;
      gMinTrendLSell = 11;
      gAllowRange = ON;
      gMinTrendLRangeBuy = 1;
      gMinTrendLRangeSell = 6;
   }
}

bool hasOpenPositions(SymbolTF &s) {
   if (s.buyGrid.CountPositions() > 0 || s.sellGrid.CountPositions() > 0 || s.rangeGridBuy.CountPositions() > 0 || s.rangeGridSell.CountPositions() > 0) {
      return true;
   }
   return false;
   
}

