//+------------------------------------------------------------------+
//|                                                         TMD3.mq5 |
//|                                                              MDV |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "MDV"
#property link      "https://www.mql5.com"
#property version   "1.00"

// Panels
// TrendPanel
#define TrendPanel   "TMD_TrendPanel"
#define InfoLine1    "TMD_InfoLine1"
#define InfoLine2    "TMD_InfoLine2"
#define TrendLabel   "Trend:  M1  M5  M15  M30  H1  H2  H4  D1  W1"
//--- Trend constants
#define     UPTREND      1
#define     DOWNTREND   -1
#define     FLATTREND    0
#define TrendUp      233
#define TrendDown    234
#define TrendFlat    232

int               BarCount = 9;
ENUM_MA_METHOD    Method   = MODE_SMA;
int               TrendPeriods[9]  = { PERIOD_M1,PERIOD_M5,PERIOD_M15,PERIOD_M30, 
                         PERIOD_H1,PERIOD_H2,PERIOD_H4,PERIOD_D1,PERIOD_W1 };
int               TrendPosition[9] = {44,64,88,114,136,156,174,194,216};

// Infopanel
#define PANEL_X 30
#define PANEL_Y 50
#define PANEL_WIDTH 490
#define PANEL_HEIGHT 540
string fieldNames[] = { "Account Name","Broker","Leverage","Symbol","Profit","Profit Buy","Profit Sell","Pending","Lots","Winrate","Equity","Balance","Margin","Free Margin","Margin Level","Lot Size","Drawdown","Status","NewsFilter"};


// Colors
color tmdGreen = C'38,166,154';
color tmdRed =    C'239,83,80';
color tmdOrange = C'255,152,0';
color tmdSilver = C'219,219,219';
color tmdBg = C'16,26,37';
color tmdSubtleBg = C'42,58,79';
color tmdBid = C'41, 98, 255';
color tmdAsk = C'247, 82, 95';

// Adaptive Trigger Logic
int atrHandle;
//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//---
   TesterHideIndicators(false);
   
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
   ChartSetInteger(chart, CHART_SHOW_GRID, true);
   ChartSetInteger(chart, CHART_SHOW_VOLUMES, false);
   ChartSetInteger(chart, CHART_SHOW_PERIOD_SEP, false);
   ChartSetInteger(chart, CHART_SHOW_OBJECT_DESCR, true);
   ChartSetInteger(chart, CHART_SHOW_OHLC, true);
   ChartSetInteger(chart, CHART_SHOW_ASK_LINE, true);
   ChartSetInteger(chart, CHART_SHOW_BID_LINE, true);
 
   
   // ----- Candles -----
   ChartSetInteger(chart, CHART_MODE, CHART_CANDLES);
   ChartSetInteger(chart, CHART_SCALE, 3);
   ChartSetInteger(chart, CHART_AUTOSCROLL, true);
   ChartSetInteger(chart, CHART_SHIFT, true);
   
   ChartRedraw();
   
   CreatePanel();
   
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
   
   DisplayTrend();
   
   static datetime lastBar = 0;
   datetime currentBar = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(currentBar == lastBar)
      return; // wait until new candle

   lastBar = currentBar;
   
   // Handles
   atrHandle = iATR(_Symbol, _Period, 14);
   
   // Trends
   double H4Trend = GetTrend(PERIOD_H4,BarCount,MODE_EMA);
   double H1Trend = GetTrend(PERIOD_H1,BarCount,MODE_EMA);
   double M15Trend = GetTrend(PERIOD_H1,BarCount,MODE_EMA);
   double M5Trend = GetTrend(PERIOD_M5,BarCount,MODE_EMA);
   double M1Trend = GetTrend(PERIOD_M1,BarCount,MODE_EMA);
   
   if(AdaptiveTriggerImpulse()) {
     
      if (H4Trend == 1 && H1Trend == 1 && M15Trend == 1 && M5Trend == -1) {
         Print("UP Adaptive Trigger Impulse | Trends | H4: ",H4Trend," | H1: ",H1Trend," |M15: ",M15Trend," |M5: ",M5Trend);
      } else if(H4Trend == -1 && H1Trend == -1 && M15Trend == -1 && M5Trend == 1) {
         Print("DOWN Adaptive Trigger Impulse | Trends | H4: ",H4Trend," | H1: ",H1Trend," |M15: ",M15Trend," |M5: ",M5Trend);
      }
      
   }
   
   
  }
//+------------------------------------------------------------------+
bool AdaptiveTriggerImpulse(double k = 0.7)
{
   double atrBuffer[];
   if(CopyBuffer(atrHandle, 0, 1, 1, atrBuffer) != 1)
      return false;

   double atr = atrBuffer[0];
   if(atr <= 0.0)
      return false;

   double impulse = MathAbs(iClose(_Symbol,PERIOD_CURRENT,1) - iOpen(_Symbol,PERIOD_CURRENT,1));
   
   if(impulse > 1.5 * atr) {
      //Print("Impulse too big");

         return false;

      
   }
      
    

   //--- compare
   if(!VolumeAboveMA()) {
        // Print("Volume too low");
        
            return false;
          
          
   }
       
   
   return impulse > k * atr;
}

//+------------------------------------------------------------------+
//| Returns true if previous bar volume is above SMA of volumes      |
//+------------------------------------------------------------------+
bool VolumeAboveMA(int period = 6)
{
    if(Bars(_Symbol,_Period) <= period + 1)
        return false;

    double sum = 0.0;

    //--- sum previous 'period' volumes
    for(int i = 1; i <= period; i++)  // i=1 -> previous bar
        sum += (double)iVolume(_Symbol,_Period,i);

    double maVolume = sum / period;

    //--- previous bar volume
    double prevVolume = (double)iVolume(_Symbol,_Period,1);
    

    return prevVolume > maVolume;
}

//+------------------------------------------------------------------+
//| Create the trend panel in the bottom left of the screen          |
//+------------------------------------------------------------------+
bool CreatePanel(void)
{
   // === TREND PANEL BACKGROUND ===
   if(!ObjectCreate(0, TrendPanel, OBJ_RECTANGLE_LABEL, 0, 0, 0))
   {
      PrintFormat("Failed to create %s. Error=%d", TrendPanel, GetLastError());
      return false;
   }

   ObjectSetInteger(0, TrendPanel, OBJPROP_CORNER, CORNER_LEFT_LOWER);
   ObjectSetInteger(0, TrendPanel, OBJPROP_XDISTANCE, 1);
   ObjectSetInteger(0, TrendPanel, OBJPROP_YDISTANCE, 60);   // moved higher
   ObjectSetInteger(0, TrendPanel, OBJPROP_XSIZE, 240);
   ObjectSetInteger(0, TrendPanel, OBJPROP_YSIZE, 26);
   ObjectSetInteger(0, TrendPanel, OBJPROP_BGCOLOR, clrWhite);
   ObjectSetInteger(0, TrendPanel, OBJPROP_COLOR, clrRed);
   ObjectSetInteger(0, TrendPanel, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, TrendPanel, OBJPROP_BACK, true);

   // THESE 3 are REQUIRED for STRATEGY TESTER:
   ObjectSetInteger(0, TrendPanel, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, TrendPanel, OBJPROP_HIDDEN, false);
   ObjectSetInteger(0, TrendPanel, OBJPROP_ZORDER, 10);

   // === INFO LINE 1 (TIMEFRAME NAMES) ===
   ObjectCreate(0, InfoLine1, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, InfoLine1, OBJPROP_CORNER, CORNER_LEFT_LOWER);
   ObjectSetInteger(0, InfoLine1, OBJPROP_XDISTANCE, 6);
   ObjectSetInteger(0, InfoLine1, OBJPROP_YDISTANCE, 51);

   string header = TrendLabel ;
   ObjectSetString(0, InfoLine1, OBJPROP_TEXT, header);
   ObjectSetString(0, InfoLine1, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, InfoLine1, OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, InfoLine1, OBJPROP_COLOR, clrBlack);

   ObjectSetInteger(0, InfoLine1, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, InfoLine1, OBJPROP_HIDDEN, false);
   ObjectSetInteger(0, InfoLine1, OBJPROP_BACK, false);

   // === INFO LINE 2 (BARCOUNT / METHOD) ===
   ObjectCreate(0, InfoLine2, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, InfoLine2, OBJPROP_CORNER, CORNER_LEFT_LOWER);
   ObjectSetInteger(0, InfoLine2, OBJPROP_XDISTANCE, 6);
   ObjectSetInteger(0, InfoLine2, OBJPROP_YDISTANCE, 34);
   ObjectSetInteger(0, InfoLine2, OBJPROP_BGCOLOR, clrBlack);

   string info = " " + IntegerToString(BarCount) + " / " + IntegerToString(Method);
   ObjectSetString(0, InfoLine2, OBJPROP_TEXT, info);
   ObjectSetString(0, InfoLine2, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, InfoLine2, OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, InfoLine2, OBJPROP_COLOR, clrWhite);

   ObjectSetInteger(0, InfoLine2, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, InfoLine2, OBJPROP_HIDDEN, false);
   ObjectSetInteger(0, InfoLine2, OBJPROP_BACK, false);

   // === TREND ARROWS (WINGDINGS) ===
   for(int i=1; i<=9; i++)
   {
      string name = "TMD_Trend" + IntegerToString(i);
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);

      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_LOWER);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, TrendPosition[i-1]);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, 34); // aligned with info line 2

      ObjectSetString(0, name, OBJPROP_FONT, "WingDings");
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clrBlack);

      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, false);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
   }

   DisplayTrend();
   return true;
}

//+------------------------------------------------------------------+
//| Display the current trend for all timeframes                     |
//+------------------------------------------------------------------+
void DisplayTrend(void)
{
   

   for(int i=1; i<=9; i++)
   {
      string name = "TMD_Trend"+IntegerToString(i);
      int Trend = (int)GetTrend(TrendPeriods[i-1], BarCount, Method);
      //Print("Trend ",Trend);
      if(Trend == FLATTREND)
      {
         // find the last trend direction
         int cntr = 1;
         int LastTrend;
         do
         {
            LastTrend = (int)GetTrend(TrendPeriods[i-1], BarCount, Method, false, cntr++);
         } while(LastTrend == FLATTREND && cntr < 2000); // safety guard

         ObjectSetString(0, name, OBJPROP_TEXT, CharToString(TrendFlat));
         ObjectSetString(0, name, OBJPROP_FONT, "Wingdings");
         ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
         ObjectSetInteger(0, name, OBJPROP_COLOR, (LastTrend == UPTREND ? tmdGreen : tmdRed));
         ObjectSetInteger(0, name, OBJPROP_YDISTANCE, 36);
         ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
         ObjectSetInteger(0,name,OBJPROP_HIDDEN,false);
         ObjectSetInteger(0,name,OBJPROP_BACK,false);
      }
      else
      {
         ObjectSetString(0, name, OBJPROP_TEXT, (Trend == UPTREND ? CharToString(TrendUp) : CharToString(TrendDown)));
         ObjectSetString(0, name, OBJPROP_FONT, "Wingdings");
         ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
         ObjectSetInteger(0, name, OBJPROP_COLOR, (Trend == UPTREND ? tmdGreen : tmdRed));
         ObjectSetInteger(0, name, OBJPROP_YDISTANCE, (Trend == UPTREND ? 36 : 34));
         ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
         ObjectSetInteger(0,name,OBJPROP_HIDDEN,false);
         ObjectSetInteger(0,name,OBJPROP_BACK,false);
      }
   }
   
   ChartRedraw(); // refresh chart
}
//+------------------------------------------------------------------+
//| Get the current trend for TimeFrame                              |
//+------------------------------------------------------------------+
double GetTrend(int TimeFrame,int TrendPeriod,ENUM_MA_METHOD Mode=MODE_SMA,bool Value=false,int Offset=0)
{
   int p = (int)MathSqrt(TrendPeriod);
   int e = TrendPeriod * 3;

   // Prepare arrays (series style)
   double vect[]; ArrayResize(vect, e); ArraySetAsSeries(vect, true);
   double buffer[]; ArrayResize(buffer, e); ArraySetAsSeries(buffer, true);
   double trend[]; ArrayResize(trend, e+2); ArraySetAsSeries(trend, true); // slightly bigger to avoid OOB

   // Build vect: vect[x] = 2*WMA(..., TrendPeriod/2) - WMA(..., TrendPeriod)
   for(int x=0; x<e; x++)
      vect[x] = 2.0 * WMA(TimeFrame, x, TrendPeriod/2) - WMA(TimeFrame, x, TrendPeriod);

   // For each x compute MA on vect using MAOnArray
   // We must ensure MAOnArray has enough elements: we supply 'e' and compute at positions 0..(e-TrendPeriod-1)
   for(int x=0; x<e-TrendPeriod; x++)
      buffer[x] = NormalizeDouble( MAOnArray(vect, e, p, Mode, x), (int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS) );

   // Determine trend directions by comparing consecutive buffer values
   for(int x = e - TrendPeriod; x >= 0; x--)
   {
      // initialize next value when x==e-TrendPeriod (trend[x+1] might be 0 initially)
      if(x == e - TrendPeriod)
         trend[x] = FLATTREND;
      else
         trend[x] = trend[x+1];

      if(buffer[x] > buffer[x+1]) trend[x] = UPTREND;
      else if(buffer[x] < buffer[x+1]) trend[x] = DOWNTREND;
      else trend[x] = FLATTREND;
   }

   // Return trend or value; the original code returned Buffer[x+1+Offset] when Value==true
   int ret_index = 1 + Offset; // matches original logic (x+1+Offset)
   if(Value)
   {
      if(ret_index >= 0 && ret_index < ArraySize(buffer)) return buffer[ret_index];
      else return 0.0;
   }
   else
   {
      if(ret_index >= 0 && ret_index < ArraySize(trend)) return trend[ret_index];
      else return FLATTREND;
   }
}

//+------------------------------------------------------------------+
//| WMA helper: compute LWMA on timeframe at given shift and period  |
//+------------------------------------------------------------------+
double WMA(int timeframe, int shift, int period)
{
   if(period <= 0) return(0.0);
   double prices[];
   // we need 'period' samples starting at 'shift'
   if(!CopyClosesSafePad(timeframe, shift, period, prices))
      return(0.0);
      

   return( NormalizeDouble( ComputeLWMAFromArray(prices, period), (int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS) ) );
}

//+------------------------------------------------------------------+
//| Compute moving average on an array (series order)                |
//| arr is series: arr[0] = most recent                              |
//| index = starting position within series (0 = current), period >0 |
//| mode: MODE_SMA, MODE_EMA, MODE_SMMA, MODE_LWMA                   |
//+------------------------------------------------------------------+
double MAOnArray(const double &arr[], int arr_size, int period, ENUM_MA_METHOD mode, int index)
{
   if(period<=0 || index < 0 || (index + period) > arr_size) return(0.0);

   // For convenience create a local slice pointer: arr[index .. index+period-1]
   // arr[index] is most recent in this window
   // We'll handle each method:

   // --- SMA
   if(mode == MODE_SMA)
   {
      double s=0.0;
      for(int i=0;i<period;i++) s += arr[index + i];
      return s / period;
   }

   // --- LWMA (weighted)
   if(mode == MODE_LWMA)
   {
      double num=0.0, den=0.0;
      for(int i=0;i<period;i++)
      {
         int weight = period - i; // arr[index+0] most recent => highest weight
         num += arr[index + i] * weight;
         den += weight;
      }
      if(den==0.0) return 0.0;
      return num/den;
   }

   // --- EMA: compute by iterating from oldest -> newest in the window
   if(mode == MODE_EMA)
   {
      // alpha
      double alpha = 2.0 / (period + 1.0);
      // start with oldest value in window as initial EMA
      double ema = arr[index + period - 1];
      for(int i = period - 2; i >= 0; i--) // move towards most recent
         ema = alpha * arr[index + i] + (1.0 - alpha) * ema;
      return ema;
   }

   // --- SMMA (a.k.a. RMA) approximate: start from SMA then smooth forward
   if(mode == MODE_SMMA)
   {
      // initial smma = SMA of the window's oldest 'period' values (we only have exactly period values)
      double s=0.0;
      for(int i=0;i<period;i++) s += arr[index + i];
      double smma = s / period;
      // There's no earlier value to iterate, so return the SMA as SMMA for this window
      // (this matches typical initialization when only one window available)
      return smma;
   }

   // Default fallback to simple average
   double s2=0.0;
   for(int j=0;j<period;j++) s2+=arr[index+j];
   return s2/period;
}
//+------------------------------------------------------------------+
//| Helper: copy closes into array (series order) safe with padding |
//+------------------------------------------------------------------+
bool CopyClosesSafePad(int timeframe, int start_shift, int count, double &out[])
{
   // --- Basic checks
   if(count <= 0)
   {
      Print(__FUNCTION__, ": Invalid count = ", count);
      return(false);
   }

   if(timeframe < PERIOD_M1 || timeframe > PERIOD_MN1)
   {
      Print(__FUNCTION__, ": Invalid timeframe = ", timeframe);
      return(false);
   }

   ENUM_TIMEFRAMES tf = (ENUM_TIMEFRAMES)timeframe;

   // --- Resize array to requested count
   ArrayResize(out, count);

   // --- Initialize all elements to 0
   for(int i = 0; i < count; i++)
      out[i] = 0.0;

   // --- Check available bars
   int availableBars = Bars(_Symbol, tf);

   if(availableBars <= start_shift)
   {
      //Print(__FUNCTION__, ": Not enough bars. Available=", availableBars, 
      //      " start_shift=", start_shift, " -> returning array of zeros");
      ArraySetAsSeries(out, true);
      return(true);  // still returns true with zeros
   }

   // --- Determine how many bars we can actually copy
   int realCount = MathMin(count, availableBars - start_shift);

   // --- Copy closes
   int copied = CopyClose(_Symbol, tf, start_shift, realCount, out);

   if(copied <= 0)
   {
      Print(__FUNCTION__, ": CopyClose failed. Requested=", realCount,
            " copied=", copied, " err=", GetLastError());
      ArraySetAsSeries(out, true);
      return(true);  // still returns true with zeros
   }

   // --- If fewer bars were copied than realCount, fill remaining with 0
   if(copied < realCount)
   {
      for(int i = copied; i < realCount; i++)
         out[i] = 0.0;
   }

   // --- Ensure newest bar is index 0
   ArraySetAsSeries(out, true);

   return(true);
}
double ComputeLWMAFromArray(const double &arr[], int arr_size)
{
   int actual_size = ArraySize(arr);
   if(actual_size <= 0) return(0.0);

   // make sure arr_size does not exceed actual array size
   int size_to_use = MathMin(arr_size, actual_size);

   double num = 0.0, den = 0.0;
   for(int i = 0; i < size_to_use; i++)
   {
      int weight = size_to_use - i; // arr[0] = most recent => highest weight
      num += arr[i] * weight;
      den += weight;
   }

   if(den == 0.0) return(0.0);
   return(num / den);
}