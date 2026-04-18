//+------------------------------------------------------------------+
//|                                                         TMD8.mq5 |
//|                                                              MDV |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "MDV"
#property link      "https://www.mql5.com"
#property version   "1.00"



#import "restmql.dll"
   int CPing(string &str);
   string CPing2();
   string Get(string url);
   string Post(string url, string data);
#import

//==================================================================
// RSI HANDLES (MT5 native iRSI)
//==================================================================
int atr14Handle;
int rsi5Handle;
int rsi7Handle;
int rsi10Handle;
int rsi20Handle;
int rsi50Handle;

//==================================================================
// GLOBAL SETTINGS
//==================================================================
int lb7 = 7;
int lb5 = 5;
int lb10 = 10;
datetime lastBarTime = 0;

//==================================================================
// INITIALIZATION
//==================================================================
int OnInit()
{
   atr14Handle = iATR(_Symbol, PERIOD_M5, 14);
   rsi5Handle  = iRSI(_Symbol, PERIOD_M5, 5, PRICE_CLOSE);
   rsi7Handle  = iRSI(_Symbol, PERIOD_M5, 7, PRICE_CLOSE);
   rsi10Handle = iRSI(_Symbol, PERIOD_M5, 10, PRICE_CLOSE);
   rsi20Handle = iRSI(_Symbol, PERIOD_M5, 20, PRICE_CLOSE);
   rsi50Handle = iRSI(_Symbol, PERIOD_M5, 50, PRICE_CLOSE);
   
   if(atr14Handle == INVALID_HANDLE || rsi5Handle  == INVALID_HANDLE ||
   rsi7Handle  == INVALID_HANDLE ||
   rsi10Handle == INVALID_HANDLE ||
   rsi20Handle == INVALID_HANDLE ||
   rsi50Handle == INVALID_HANDLE)
{
   Print("RSI handle creation failed");
   return INIT_FAILED;
}

    Print("EA initialized successfully");
    return(INIT_SUCCEEDED);
}

//==================================================================
// DEINITIALIZATION
//==================================================================
void OnDeinit(const int reason)
{

IndicatorRelease(atr14Handle);
IndicatorRelease(rsi5Handle);
IndicatorRelease(rsi7Handle);
IndicatorRelease(rsi10Handle);
IndicatorRelease(rsi20Handle);
IndicatorRelease(rsi50Handle);
    Print("EA deinitialized cleanly");
}

//==================================================================
// ON TICK
//==================================================================
void OnTick()
{
    datetime barTime = iTime(_Symbol, PERIOD_M5, 0);
    if(barTime == lastBarTime) return;
    lastBarTime = barTime;

   string lastLow = IsLastClosedBarLowest(lb7) ? "1" : "0";
   string lastHigh = IsLastClosedBarHighest(lb7) ? "1" : "0";
   string lastLow5 = IsLastClosedBarLowest(lb5) ? "1" : "0";
   string lastHigh5 = IsLastClosedBarHighest(lb5) ? "1" : "0";
   string lastLow10 = IsLastClosedBarLowest(lb10) ? "1" : "0";
   string lastHigh10 = IsLastClosedBarHighest(lb10) ? "1" : "0";
   double rsi5  = GetRSI(rsi5Handle);
   double rsi7  = GetRSI(rsi7Handle);
   double rsi10 = GetRSI(rsi10Handle);
   double rsi20 = GetRSI(rsi20Handle);
   double rsi50 = GetRSI(rsi50Handle);
   
   double atr14 = ReadBuf(atr14Handle, 1);
   double rsi7_now  = ReadBuf(rsi7Handle, 1);
   double rsi7_prev = ReadBuf(rsi7Handle, 2);
   double rsi7_prev2 = ReadBuf(rsi7Handle, 3);
   double rsiSlope7 = rsi7_now - rsi7_prev;
   double rsiSlope7Prev = rsi7_prev - rsi7_prev2;
   double RSI_ACCEL_7 = rsiSlope7 - rsiSlope7Prev;
   
   double rsi5_20 = rsi5 - rsi20;
   
   double bodyRatioAtr = bodyRatio() / atr14;

    // Build JSON
    string json = "{";
       json += "\"BODY_RATIO\":"+DoubleToString(bodyRatio(), 6)+",";
       json += "\"IS_LOW5\":"+lastLow5+",";
       json += "\"IS_LOW\":"+lastLow+",";
       json += "\"IS_LOW10\":"+lastLow10+",";
       json += "\"IS_HIGH5\":"+lastHigh5+","; 
       json += "\"IS_HIGH\":"+lastHigh+",";
       json += "\"IS_HIGH10\":"+lastHigh10+",";
      json += "\"RSI_5\":"  + DoubleToString(rsi5, 2)  + ",";
      json += "\"RSI_7\":"  + DoubleToString(rsi7, 2)  + ",";
      json += "\"RSI_10\":" + DoubleToString(rsi10, 2) + ",";
      json += "\"RSI_20\":" + DoubleToString(rsi20, 2) + ",";
      json += "\"RSI_50\":" + DoubleToString(rsi50, 2) ;
      json += ",\"ATR_14\":" + DoubleToString(atr14, 6);
      json += ",\"RSI_SLOPE_7\":" + DoubleToString(rsiSlope7, 4);
      json += ",\"RSI_5_20\":" + DoubleToString(rsi5_20, 4);  
      json += ",\"BODY_RATIO_ATR\":" + DoubleToString(bodyRatioAtr, 4);  
       json += ",\"RSI_ACCEL_7\":" + DoubleToString(RSI_ACCEL_7, 4);  
      json += "}";

    //Print("GridXGBoost JSON: ", json);
    //Print("POST RESULT:");
    string result = Post("http://127.0.0.1:8080/api/predict", json);
    if (GetJsonValue(result,"buyProb") > 0.9) {
      Print(result);
    }
    if (GetJsonValue(result,"sellProb") > 0.9) {
      Print(result);
    }
    //Print(Post("http://127.0.0.1:8080/api/predict", json));
}

//==================================================================
// HELPER FUNCTIONS
//==================================================================


bool IsLastClosedBarHighest(int lookback)
{
   if(Bars(_Symbol, _Period) < lookback + 2)
      return false;

   double lastHigh = iHigh(_Symbol, _Period, 1);

   for(int i = 2; i <= lookback; i++)
   {
      if(iHigh(_Symbol, _Period, i) >= lastHigh)
         return false;
   }

   return true;
}

bool IsLastClosedBarLowest(int lookback)
{
   if(Bars(_Symbol, _Period) < lookback + 2)
      return false;

   double lastLow = iLow(_Symbol, _Period, 1);

   for(int i = 2; i <= lookback; i++)
   {
      if(iLow(_Symbol, _Period, i) <= lastLow)
         return false;
   }

   return true;
}
double bodyRatio() {
   double ratio = (MathAbs(iClose(_Symbol,PERIOD_M5,1) - iOpen(_Symbol,PERIOD_M5,1)) / iOpen(_Symbol,PERIOD_M5,1)) * 100 ;
   
   return ratio;
}

double GetRSI(int handle)
{
   double buf[];
   if(CopyBuffer(handle, 0, 1, 1, buf) != 1)
      return EMPTY_VALUE;
   return buf[0];
}
double ReadBuf(int handle, int shift)
{
   double b[];
   if(CopyBuffer(handle, 0, shift, 1, b) != 1)
      return EMPTY_VALUE;
   return b[0];
}

// --- helper function ---
// Simple JSON parser for double values
double GetJsonValue(string json, string key)
{
    int pos = StringFind(json, "\"" + key + "\":");
    if (pos == -1) return 0.0;

    int start = pos + StringLen("\"" + key + "\":");
    int end = StringFind(json, ",", start);
    if (end == -1) end = StringLen(json); // last element

    string valStr = StringSubstr(json, start, end - start);
    return StringToDouble(valStr);
}