//+------------------------------------------------------------------+
//|                                                        TMD12.mq5 |
//|                                                              MDV |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "MDV"
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <GridManager.mqh>
#include <Trade/Trade.mqh>

CTrade trade;

enum ENUM_ONOFF
{
   OFF = 0,
   ON  = 1
};

struct CurrentBarAnalysis
{
   // Raw measurements
    double   barRange;            // high - low
    double   bodySize;            // abs(close - open)
    double   upperWick;           // high - max(open, close)
    double   lowerWick;           // min(open, close) - low
    // Ratios (0-100)
    double   bodyRatio;           // body / range * 100
    double   upperWickRatio;      // upperWick / range * 100
    double   lowerWickRatio;      // lowerWick / range * 100
    // Pattern classification
    string  pattern;             // "DOJI", "HAMMER", "MARUBOZU", etc.
    string  patternBias;         // "BULLISH", "BEARISH", "NEUTRAL"
    // Context
    bool    isBullishBar;        // close > open
    double   rangeVsATR;         // range / ATR ratio
    string  rangeStatus;         // "WIDE", "NORMAL", "NARROW"
    double   volumeVsAvg;         // volume ratio (if available)
    string  volumeStatus;        // "SPIKE", "NORMAL", "LOW"
    // Volume data
    double   buyVol;
    double   sellVol;
    double   delta;
    string  pressureStatus;      // "BUYING", "SELLING", "BALANCED"
};

struct BlockAnalytics
{
       bool  valid ;
       double totalBuy;
       double totalSell;
       double delta;
       double blockHeight;
       double blockArea;
       double avgUpperPin;
       double avgLowerPin;
       double avgBody;
       double newOpen;
       double newHigh;
       double newLow;
       double newClose;
       int   startIdx;
       int   endIdx;
       double   centerIdx;
       double boxBottom;
       int   trendType  ;     // 1 = UP, -1 = DOWN, 0 = RANGE/NEUTRAL
       bool  trendLocked  ;   // Once true, trendType never changes

};
struct TrendContext
{
       // Current trend info
    int     currentType;         // DIR_UP, DIR_DOWN, DIR_RANGE
    int     currentBlocks;       // Number of blocks in current trend
    string  currentLabel;        // "UPTREND", "DOWNTREND", "RANGE"
    // Previous trend info
    int     prevType;            // Previous trend type
    string  prevLabel;           // Previous trend label
    // Sequence analysis
    string  transition;          // "REVERSAL_TO_UP", "REVERSAL_TO_DOWN", "CONTINUATION", "NEW_TREND"
    int     trendChanges;        // Count of trend changes in window
    // Quality metrics
    double   qualityScore;
    string  confidenceLevel ;    // "HIGH", "MEDIUM", "LOW"
    string  strengthRating  ;    // "VERY_STRONG", "STRONG", "MODERATE", "WEAK"
};
struct TrendChannel
{
    int   channelType;      // 1 = UPTREND, -1 = DOWNTREND, 0 = RANGE
    int   startBlock;       // Newest block (e.g., 1)
    int   endBlock  ;       // Oldest block (e.g., 4)
    double angleDeg ;        // Channel angle in degrees
    double   upperX1 ;         // Upper line start X (left)
    double   upperX2  ;        // Upper line end X (right)
    double   lowerX1  ;        // Lower line start X (left)
    double   lowerX2 ;         // Lower line end X (right)
    double upperY1 ;         // Upper line start Y
    double upperY2 ;         // Upper line end Y
    double lowerY1  ;        // Lower line start Y
    double lowerY2 ;         // Lower line end Y
};

struct CompositeAnalysis
{
       // Block 1 composite candle metrics
    double   compRange;
    double   compBodySize;
    double   compUpperWick;
    double   compLowerWick;
    double   compBodyRatio;
    // Pattern
    string  compositePattern;    // Same patterns as current bar
    string  compositeBias ;      // BULLISH/BEARISH/NEUTRAL
    // Multi-block comparison (Block 1 vs Block 2)
    string  blockRelation  ;     // "ENGULFING", "INSIDE", "OUTSIDE", "NORMAL"
    string  blockRelationBias;   // Direction implication
};

//+------------------------------------------------------------------+
//| Market Structure Break Struct                                   |
//+------------------------------------------------------------------+
struct MarketStructureBreak
{
   bool     valid;          // true if BOS found
   bool     bullish;        // true = bullish BOS, false = bearish BOS
   int      barsAgo;        // how many bars ago break happened
   double   level;          // broken swing level
   datetime time;           // time of break candle
};

ENUM_TIMEFRAMES StringToTimeframe(string tf)
{
   if(tf == "1")   return PERIOD_M1;
   if(tf == "5")   return PERIOD_M5;
   if(tf == "60")  return PERIOD_H1;

   return WRONG_VALUE;
}

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
   TrendContext     trendContext;
   CompositeAnalysis compositeAnalysis;
   CurrentBarAnalysis currentBarAnalysis;
   BlockAnalytics    analyticsData[];
   TrendChannel      trendChannels[];
   MarketStructureBreak           msbInfo;
   int               magicNrBuy;
   int               magicNrSell;
   GridManager       buyGrid;
   GridManager       sellGrid;
};

SymbolTF streams[];

// Direction constants for trend classification
int DIR_UP    =  1 ;  // Uptrend: higher highs, higher lows
int DIR_DOWN  = -1 ;  // Downtrend: lower highs, lower lows
int DIR_RANGE =  0  ; // Range/Sideways: no clear direction

// INPUTS
input bool verboseLogging = false; // Verbose Logging
input string i_narrativeLang = "English";
input int i_window = 100; // Window Bars
input int i_groups = 20; // Group Count
input double i_rangeAngleThreshold = 10.0; // Range Angle Threshold (°)
input ENUM_ONOFF        StyleChart = ON;              // TMD Chart Style
input string   InpSymbols      = "EURUSD,GBPUSD,USDJPY";
input string   InpTimeframes   = "M5,M15,H1";
input int      InpTimerSeconds = 1;
input int      MagicBuy = 2204;
input int      MagicSell = 1981;

// Colors
color tmdGreen = C'38,166,154';
color tmdRed =    C'239,83,80';
color tmdOrange = C'255,152,0';
color tmdSilver = C'219,219,219';
color tmdBg = C'16,26,37';
color tmdSubtleBg = C'42,58,79';
color tmdBid = C'41, 98, 255';
color tmdAsk = C'247, 82, 95';





//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//---
   
   string symList[];
   string tfList[];
   
   int symCount = SplitString(InpSymbols,",",symList);
   int tfCount  = SplitString(InpTimeframes,",",tfList);
   
    ArrayResize(streams, symCount * tfCount);
    
    int index=0;
    
     for(int i=0;i<symCount;i++)
      {
         string symbol = symList[i];
         SymbolSelect(symbol,true);  // IMPORTANT
   
         for(int j=0;j<tfCount;j++)
         {
            streams[index].symbol = symbol;
            streams[index].tf     = TFfromString(tfList[j]);
            streams[index].lastBarTime = 0;
            streams[index].magicNrBuy = MagicBuy + index;
            streams[index].magicNrSell = MagicSell + index;
            
            streams[index].buyGrid = new GridManager(symbol, GRID_BUY, 0.01, 100, 0.06, 100);
            streams[index].buyGrid.SetGridMagicNumber(streams[index].magicNrBuy);
            streams[index].buyGrid.SetGridMultiplier(1.0);
            streams[index].buyGrid.SetGridMaxDD(0);

            streams[index].sellGrid = new GridManager(symbol, GRID_SELL, 0.01, 100, 0.06, 100);
            streams[index].sellGrid.SetGridMagicNumber(streams[index].magicNrSell);
            streams[index].sellGrid.SetGridMultiplier(1.0);
            streams[index].sellGrid.SetGridMaxDD(0);
            
            // Warm up data (VERY important for tester)
            MqlRates rates[];
            CopyRates(symbol, streams[index].tf, 0, 10, rates);
            
            datetime currentBar = iTime(symbol, streams[index].tf, 0);

            streams[index].lastBarTime = currentBar;
            streams[index].nextBarTime = currentBar + PeriodSeconds(streams[index].tf);
   
            index++;
         }
      }
      
      EventSetTimer(InpTimerSeconds);
   

   
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

      }
      
      CreatePanel();
      CreateAnalysis();
   
   Print("==== TMD12[1.0] Initialized ====");
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
   EventKillTimer();
  }
  
void OnTimer()
{
   datetime now = TimeCurrent();
   
       // Check market open
   if(!CheckTradeAllowed()) {
      return;
   }

   for(int i=0; i<ArraySize(streams); i++)
   {
      
      // Step 1: Cheap time check
      if(now >= streams[i].nextBarTime)
      {
         // Step 2: Confirm actual new bar
         datetime currentBar = iTime(streams[i].symbol, streams[i].tf, 0);
         
         if(currentBar != streams[i].lastBarTime && currentBar != 0)
         {
            
            streams[i].sellGrid.Update();
            streams[i].buyGrid.Update();
            streams[i].lastBarTime = currentBar;
            streams[i].nextBarTime = currentBar + PeriodSeconds(streams[i].tf);

            RunStrategy(streams[i].symbol, streams[i].tf, streams[i]);
         }
      }
   }
}
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
//---

   
  }
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Get ATR value (like ta.atr(20))                                  |
//+------------------------------------------------------------------+
double GetATR(int atrHandle)
{
   double atrBuffer[];
   
   // Copy latest closed candle ATR value
   if(CopyBuffer(atrHandle, 0, 1, 1, atrBuffer) <= 0)
   {
      Print("Failed to copy ATR buffer");
      return(0);
   }
   
   return atrBuffer[0];
}

//━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// VOLUME ENGINE FUNCTIONS
//━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

//+------------------------------------------------------------------+
//| Geo Volume Calculation                                           |
//| Returns: buyVol, sellVol, delta                                  |
//+------------------------------------------------------------------+
void f_geoVol(string symbol, ENUM_TIMEFRAMES tf, double &buyVol, double &sellVol, double &deltaVol, int shift=0)
{
   double high   = iHigh(symbol, tf, shift);
   double low    = iLow(symbol, tf, shift);
   double close  = iClose(symbol, tf, shift);
   long   volume = iVolume(symbol, tf, shift); // tick volume
   PrintVerbose("high: "+DoubleToString(high,5));
   PrintVerbose("low: "+DoubleToString(low,5));
   PrintVerbose("close: "+DoubleToString(close,5));
   PrintVerbose("volume: "+DoubleToString(volume,5));
   
   
   
   double r = high - low;

   // Equivalent of na(volume)
   if(volume <= 0)
   {
      buyVol  = EMPTY_VALUE;
      sellVol = EMPTY_VALUE;
      deltaVol = EMPTY_VALUE;
      return;
   }

   if(r == 0.0)
   {
      buyVol  = volume * 0.5;
      sellVol = volume * 0.5;
   }
   else
   {
      buyVol  = volume * ((close - low) / r);
      sellVol = volume * ((high - close) / r);
   }

   deltaVol = buyVol - sellVol;
}

CurrentBarAnalysis f_analyzeCurrentBar(
   string symbol,
   ENUM_TIMEFRAMES tf,
   int offset,
   double atr,
   double buyV,
   double sellV
)
{
   double h = iHigh(symbol,tf,offset);
   double l = iLow(symbol,tf,offset);
   double o = iOpen(symbol,tf,offset);
   double c = iClose(symbol,tf,offset);
   long v = iVolume(symbol,tf,offset);

   double barRange  = h - l;
   double bodySize  = MathAbs(c - o);
   double upperWick = h - MathMax(o, c);
   double lowerWick = MathMin(o, c) - l;

   double bodyR  = 0.0;
   double upperR = 0.0;
   double lowerR = 0.0;

   if(barRange > 0.0)
   {
      bodyR  = (bodySize  / barRange) * 100.0;
      upperR = (upperWick / barRange) * 100.0;
      lowerR = (lowerWick / barRange) * 100.0;
   }

   bool isBull = (c > o);

   // --- Pattern classification
   string pattern;
   string patternBias;
   ClassifyCandlePattern(bodyR, upperR, lowerR, isBull, pattern, patternBias);

   // --- Range status
   double rangeRatio;
   string rangeStatus;
   ClassifyRangeStatus(barRange, atr, rangeRatio, rangeStatus);

   // --- Volume status
   double volRatio;
   string volStatus;
   CalcVolumeStatus(symbol, tf,v, 20, offset, volRatio, volStatus);

   // --- Delta & pressure
   double delta = buyV - sellV;
   string pressure = f_calcPressureStatus(buyV, sellV);

   // --- Return struct
   CurrentBarAnalysis result;

   result.barRange   = barRange;
   result.bodySize   = bodySize;
   result.upperWick  = upperWick;
   result.lowerWick  = lowerWick;

   result.bodyRatio      = bodyR;
   result.upperWickRatio     = upperR;
   result.lowerWickRatio     = lowerR;

   result.pattern     = pattern;
   result.patternBias = patternBias;

   result.isBullishBar      = isBull;
   result.rangeVsATR  = rangeRatio;
   result.rangeStatus = rangeStatus;
   result.volumeVsAvg    = volRatio;
   result.volumeStatus   = volStatus;

   result.buyVol    = buyV;
   result.sellVol   = sellV;
   result.delta   = delta;
   result.pressureStatus = pressure;

   return result;
}

//+------------------------------------------------------------------+
//| Classify single candle pattern based on body/wick ratios        |
//| bodyR  = body percentage (0-100)                                |
//| upperR = upper wick percentage (0-100)                          |
//| lowerR = lower wick percentage (0-100)                          |
//| isBull = true if close > open                                   |
//+------------------------------------------------------------------+
void ClassifyCandlePattern(double bodyR,
                           double upperR,
                           double lowerR,
                           bool   isBull,
                           string &pattern,
                           string &bias)
{
   pattern = "STANDARD";
   bias    = "NEUTRAL";

   // --- DOJI variants (very small body)
   if(bodyR < 10.0)
   {
      if(lowerR > 65.0 && upperR < 15.0)
      {
         pattern = "DRAGONFLY";
         bias    = "BULLISH";
      }
      else if(upperR > 65.0 && lowerR < 15.0)
      {
         pattern = "GRAVESTONE";
         bias    = "BEARISH";
      }
      else
      {
         pattern = "DOJI";
         bias    = "NEUTRAL";
      }
   }
   // --- SPINNING TOP
   else if(bodyR < 35.0 && MathAbs(upperR - lowerR) < 20.0)
   {
      pattern = "SPINNING_TOP";
      bias    = "NEUTRAL";
   }
   // --- MARUBOZU
   else if(bodyR > 80.0)
   {
      pattern = "MARUBOZU";
      bias    = isBull ? "BULLISH" : "BEARISH";
   }
   // --- HAMMER / INVERTED HAMMER
   else if(bodyR < 40.0)
   {
      if(lowerR > 55.0 && upperR < 20.0)
      {
         pattern = "HAMMER";
         bias    = "BULLISH";
      }
      else if(upperR > 55.0 && lowerR < 20.0)
      {
         pattern = "INV_HAMMER";
         bias    = isBull ? "BULLISH" : "BEARISH";
      }
      else if(upperR > 45.0)
      {
         pattern = "LONG_UPPER";
         bias    = "BEARISH";
      }
      else if(lowerR > 45.0)
      {
         pattern = "LONG_LOWER";
         bias    = "BULLISH";
      }
   }
   // --- Standard directional candle
   else
   {
      pattern = "STANDARD";
      bias    = isBull ? "BULLISH" : "BEARISH";
   }
}

void ClassifyRangeStatus(double barRange, double atr, double &ratio, string &status) {
   ratio = atr > 0 ? barRange / atr : 1.0 ;
   status = ratio > 1.5 ? "WIDE" : ratio < 0.6 ? "NARROW" : "NORMAL";
}

//+------------------------------------------------------------------+
//| Calculate volume status relative to average                     |
//+------------------------------------------------------------------+
void CalcVolumeStatus(
string symbol,
ENUM_TIMEFRAMES tf,
double currentVol,
                      int period,
                      int offset,
                      double &ratio,
                      string &status)
{
   double sumVol = 0.0;
   int count = 0;

   for(int i = offset; i < offset + period; i++)
   {
      double v = (double)iVolume(symbol,tf,i);   // tick volume

      if(v > 0)
      {
         sumVol += v;
         count++;
      }
   }

   double avgVol = 0.0;

   if(count > 0)
      avgVol = sumVol / count;

   if(avgVol > 0)
      ratio = currentVol / avgVol;
   else
      ratio = 1.0;

   // Status logic
   if(ratio > 2.0)
      status = "SPIKE";
   else if(ratio < 0.5)
      status = "LOW";
   else
      status = "NORMAL";
}

string f_calcPressureStatus(double buyVol, double sellVol) {
    double total = buyVol + sellVol;
    string pressureStatus = "";
    if (total == 0) {
      pressureStatus = "BALANCED";
    } else {
      double buyPct = buyVol / total * 100 ;
      pressureStatus = buyPct > 55 ? "BUYING" : buyPct < 45 ? "SELLING" : "BALANCED";
    }
    return pressureStatus;
}

// Global variable example:
// string i_narrativeLang = "English";
// "Türkçe", "हिन्दी", "العربية", or default English

string f_L(string en, string tr, string hi, string ar)
{
   if(i_narrativeLang == "Türkçe")
      return tr;
   else if(i_narrativeLang == "हिन्दी")
      return hi;
   else if(i_narrativeLang == "العربية")
      return ar;
   else
      return en;
}

string f_patternDesc(string pattern)
{
   if(pattern == "DOJI")
      return f_L(
         "a doji indicating market indecision and uncertainty",
         "belirsizlik ve kararsızlığı gösteren bir doji",
         "एक डोजी जो बाजार में अनिश्चितता दर्शाता है",
         "دوجي يُشير إلى تردد السوق وعدم اليقين"
      );

   else if(pattern == "HAMMER")
      return f_L(
         "a hammer suggesting rejection at lower levels and potential bullish reversal",
         "alt seviyelerde reddedilme ve potansiyel yükseliş dönüşünü gösteren bir çekiç",
         "एक हैमर जो निचले स्तर पर अस्वीकृति और संभावित तेजी उलटफेर का सुझाव देता है",
         "مطرقة تُشير إلى رفض عند المستويات الدنيا واحتمال انعكاس صعودي"
      );

   else if(pattern == "INV_HAMMER")
      return f_L(
         "an inverted hammer",
         "ters çekiç",
         "एक उल्टा हैमर",
         "مطرقة مقلوبة"
      );

   else if(pattern == "DRAGONFLY")
      return f_L(
         "a dragonfly doji showing strong rejection at lows and buying pressure",
         "güçlü alış baskısı ve dipte reddedilme gösteren yusufçuk doji",
         "एक ड्रैगनफ्लाई डोजी जो निम्न स्तर पर मजबूत अस्वीकृति दिखाता है",
         "دوجي اليعسوب يُظهر رفضاً قوياً عند القيعان وضغطاً شرائياً"
      );

   else if(pattern == "GRAVESTONE")
      return f_L(
         "a gravestone doji showing strong rejection at highs and selling pressure",
         "güçlü satış baskısı ve tepede reddedilme gösteren mezar taşı doji",
         "एक ग्रेवस्टोन डोजी जो उच्च स्तर पर मजबूत अस्वीकृति दिखाता है",
         "دوجي شاهد القبر يُظهر رفضاً قوياً عند القمم وضغطاً بيعياً"
      );

   else if(pattern == "MARUBOZU")
      return f_L(
         "a marubozu with large body and small wicks indicating one-sided market power",
         "tek taraflı piyasa gücünü gösteren büyük gövdeli ve küçük fitilli marubozu",
         "एक मारूबोज़ू जो एकतरफा बाजार शक्ति दर्शाता है",
         "ماروبوزو بجسم كبير وفتائل صغيرة يدل على قوة سوقية أحادية الاتجاه"
      );

   else if(pattern == "LONG_UPPER")
      return f_L(
         "a candle with long upper wick indicating selling pressure and rejection at higher levels",
         "satış baskısı ve üst seviyelerde reddedilmeyi gösteren uzun üst fitilli mum",
         "एक कैंडल जो बिक्री दबाव दिखाती है",
         "شمعة بفتيل علوي طويل تدل على ضغط بيعي ورفض عند المستويات العليا"
      );

   else if(pattern == "LONG_LOWER")
      return f_L(
         "a candle with long lower wick indicating buying pressure and rejection at lower levels",
         "alım baskısı ve alt seviyelerde reddedilmeyi gösteren uzun alt fitilli mum",
         "एक कैंडल जो खरीद दबाव दिखाती है",
         "شمعة بفتيل سفلي طويل تدل على ضغط شرائي ورفض عند المستويات الدنيا"
      );

   else if(pattern == "SPINNING_TOP")
      return f_L(
         "a spinning top with small body and long wicks indicating imbalance between buyers and sellers",
         "alıcı ve satıcılar arasındaki dengesizliği gösteren küçük gövdeli topaç",
         "एक स्पिनिंग टॉप जो खरीदारों और विक्रेताओं के बीच असंतुलन दिखाता है",
         "قمة دوّارة بجسم صغير وفتائل طويلة تدل على اختلال التوازن بين المشترين والبائعين"
      );

   else
      return f_L(
         "a standard candle",
         "standart bir mum",
         "एक मानक कैंडल",
         "شمعة قياسية"
      );
}

// Range Status
string f_rangeStatusStr(string rangeStatus) {
   if (rangeStatus == "WIDE") {
      return f_L("WIDE RANGE","WIDE RANGE","WIDE RANGE","WIDE RANGE");
   } else if (rangeStatus == "NARROW") {
      return f_L("NARROW RANGE","NARROW RANGE","NARROW RANGE","NARROW RANGE");
   } else {
      return f_L("NORMAL RANGE","NORMAL RANGE","NORMAL RANGE","NORMAL RANGE");
   }
}

void PrintVerbose(string message) {
   if (verboseLogging) {
      Print(message);
   }
}

TrendChannel TrendChannelEmpty()
{
   TrendChannel tc;
   
   tc.channelType = 0;
   tc.startBlock  = -1;
   tc.endBlock    = -1;
   tc.angleDeg    = 0.0;
   
   tc.upperX1 = 0;
   tc.upperX2 = 0;
   tc.lowerX1 = 0;
   tc.lowerX2 = 0;
   
   tc.upperY1 = 0.0;
   tc.upperY2 = 0.0;
   tc.lowerY1 = 0.0;
   tc.lowerY2 = 0.0;
   
   return tc;
}

BlockAnalytics AnalyticsEmpty()
{
   BlockAnalytics blk;

   blk.valid        = false;
   blk.totalBuy     = 0.0;
   blk.totalSell    = 0.0;
   blk.delta        = 0.0;
   blk.blockHeight  = 0.0;
   blk.blockArea    = 0.0;
   blk.avgUpperPin  = 0.0;
   blk.avgLowerPin  = 0.0;
   blk.avgBody      = 0.0;
   blk.newOpen      = 0.0;
   blk.newHigh      = 0.0;
   blk.newLow       = 0.0;
   blk.newClose     = 0.0;
   blk.startIdx     = -1;
   blk.endIdx       = -1;
   blk.centerIdx    = -1;
   blk.boxBottom    = 0.0;
   blk.trendType    = 0;
   blk.trendLocked  = false;

   return blk;
}

void EnsureAnalyticsDataCount(int n, BlockAnalytics &analyticsData[])
{
   int current = ArraySize(analyticsData);

   if(current < n)
   {
      ArrayResize(analyticsData, n);
      for(int i = current; i < n; i++)
         analyticsData[i] = AnalyticsEmpty();
   }
   else if(current > n)
   {
      ArrayResize(analyticsData, n);
   }
}
void EnsureChannelCount(int n, TrendChannel &trendChannels[])
{
   int current = ArraySize(trendChannels);

   if(current < n)
   {
      ArrayResize(trendChannels, n);
      for(int i = current; i < n; i++)
         trendChannels[i] = TrendChannelEmpty();
   }
   else if(current > n)
   {
      ArrayResize(trendChannels, n);
   }
}

void LockBlockTrend(int blockIdx, int trendType, BlockAnalytics &analyticsData[])
{
   if(blockIdx < 0 || blockIdx >= ArraySize(analyticsData))
      return;

   if(!analyticsData[blockIdx].trendLocked)
   {
      analyticsData[blockIdx].trendType   = trendType;
      analyticsData[blockIdx].trendLocked = true;
   }
}

void CalculateGroups(string symbol, ENUM_TIMEFRAMES tf, BlockAnalytics &analyticsData[]) {
   EnsureAnalyticsDataCount(i_groups, analyticsData);
   int groupSize = MathMax(1, (int)MathRound((double)i_window / i_groups));
   int effWindow  = groupSize * i_groups; // groupsize = 5
   for (int gi = 0; gi < i_groups ; gi++) {
      int startOff = 1 + (gi * groupSize); // 1
      int endOff   = 1 + ((gi + 1) * groupSize) - 1; // 5
      double top = EMPTY_VALUE;
      double bot = EMPTY_VALUE;
      double sumBuyBlock = 0;
      double sumSellBlock = 0;
      double sumUpperPin = 0.0; double sumLowerPin = 0.0; double sumBody = 0.0;
      double compOpen = EMPTY_VALUE; double compHigh = EMPTY_VALUE; double compLow = EMPTY_VALUE; double compClose = EMPTY_VALUE;
      for (int k = startOff; k <= endOff;k++) {
         double h = iHigh(symbol,tf,k);
         double l = iLow(symbol,tf,k);
         double o = iOpen(symbol,tf,k);
         double c = iClose(symbol,tf,k); 
         if(top == EMPTY_VALUE || h > top)
         {
            top = h;
         }
         if(bot == EMPTY_VALUE || l < bot)
         {
            bot = l;
         }
         // Volume
         double bVol;double sVol;double vDelta;
         f_geoVol(symbol,tf,bVol,sVol,vDelta,k);
         sumBuyBlock += bVol;
         sumSellBlock += sVol;
         sumUpperPin += h - MathMax(o, c);
         sumLowerPin += MathMin(o, c) - l;
         sumBody     += MathAbs(c - o);
         
         // Comp candle
         if (k == endOff) {
            compOpen = o;
         }
         if (k == startOff) {
            compClose = c;
         }
         if (compHigh == EMPTY_VALUE || h > compHigh) {
            compHigh = h;
         }
         if (compLow == EMPTY_VALUE || l < compLow) {
            compLow = l;
         }
         

         
      }
      
      int xRight = startOff;
      int xLeft  = endOff;
      double xCenter = MathRound((xLeft + xRight) / 2.0);
      int n = groupSize;
      double blockDelta  = sumBuyBlock - sumSellBlock;
      double blockHeight = top - bot;
      double blockArea   = blockHeight * n;
      
      BlockAnalytics ba;
      ba.valid = true;
      ba.totalBuy = sumBuyBlock;
      ba.totalSell = sumSellBlock;
      ba.delta = blockDelta;
      ba.blockHeight = blockHeight;
      ba.blockArea = blockArea;
      ba.avgUpperPin = sumUpperPin / n;
      ba.avgLowerPin = sumLowerPin / n;
      ba.avgBody = sumBody / n;
      ba.newOpen = compOpen;
      ba.newHigh = compHigh;
      ba.newLow = compLow;
      ba.newClose = compClose;
      ba.startIdx = xLeft;
      ba.endIdx = xRight;
      ba.centerIdx = xCenter;
      ba.boxBottom = bot;
      
      analyticsData[gi] = ba;
      
   }

   
}

CompositeAnalysis runCompositeAnalysis(BlockAnalytics &blk1, BlockAnalytics &blk2) {
   CompositeAnalysis result;
   if (blk1.valid) {
      // Calculate composite candle metrics
        double cRange = blk1.newHigh - blk1.newLow;
        double cBody = MathAbs(blk1.newClose - blk1.newOpen);
        double cUpper = blk1.newHigh - MathMax(blk1.newOpen, blk1.newClose);
        double cLower = MathMin(blk1.newOpen, blk1.newClose) - blk1.newLow;
        double cBodyR = cRange > 0 ? (cBody / cRange) * 100 : 0.0;
        double cUpperR = cRange > 0 ? (cUpper / cRange) * 100 : 0.0;
        double cLowerR = cRange > 0 ? (cLower / cRange) * 100 : 0.0;
        
        bool isBull = blk1.newClose > blk1.newOpen ;
        
        string pattern, bias;
        ClassifyCandlePattern(cBodyR,cUpperR,cLowerR,isBull,pattern,bias);
        
        result.compRange = cRange;
        result.compBodySize = cBody;
        result.compUpperWick = cUpper;
        result.compLowerWick = cLower;
        result.compBodyRatio = cBodyR;
        result.compositePattern = pattern;
        result.compositeBias = bias;
        // Multi-block pattern detection (Block 1 vs Block 2)
        if (blk2.valid) {
            double b1High = blk1.newHigh; double b1Low = blk1.newLow;
            double b2High = blk2.newHigh; double b2Low = blk2.newLow;
            double b1Body = MathAbs(blk1.newClose - blk1.newOpen);
            double b2Body = MathAbs(blk2.newClose - blk2.newOpen);
            
            // Inside bar: Block 1 range completely inside Block 2
            if (b1High <= b2High && b1Low >= b2Low) {
               result.blockRelation = "INSIDE";
               result.blockRelationBias = "NEUTRAL";
            }
                
            // Outside bar: Block 1 range exceeds Block 2
            else if (b1High > b2High && b1Low < b2Low) {
               result.blockRelation = "OUTSIDE";
               result.blockRelationBias = isBull ? "BULLISH" : "BEARISH";
            }
                
            // Engulfing: Block 1 body engulfs Block 2 body
            else if (b1Body > b2Body * 1.3) {
               result.blockRelation = "ENGULFING";
                result.blockRelationBias = isBull ? "BULLISH" : "BEARISH";
            }
                
            else {
               result.blockRelation = "NORMAL";
               result.blockRelationBias = "NEUTRAL";
            }     
        } else {
               result.blockRelation = "NORMAL";
               result.blockRelationBias = "NEUTRAL";
        }
   }
   
   return result;
}

// Yang-Zhang (2000) volatility estimator
// Combines overnight (close-to-open), open-to-close, and Rogers-Satchell
// intraday components into the most efficient unbiased volatility measure.
// Returns per-bar volatility in PRICE UNITS (σ × close).

double f_yangZhangVolatility (string symbol, ENUM_TIMEFRAMES tf, int period) {
    double sumOvSq = 0.0;
    double sumOv   = 0.0;
    double sumClSq = 0.0;
    double sumCl   = 0.0;
    double sumRS   = 0.0;
    int   n       = MathMax(2, period);
    
    
    for (int i = 0;i<n;i++) {
      // Overnight return: log(open_i / close_{i-1})
      double ov = MathLog(iOpen(symbol,tf,i) / iClose(symbol,tf,i+1));
      sumOv += ov;
      sumOvSq += ov*ov;
      
       // Open-to-close return: log(close_i / open_i)
       double cl = MathLog(iClose(symbol,tf,i)/iOpen(symbol,tf,i));
       sumCl   += cl;
       sumClSq += cl * cl;
       
       // Rogers-Satchell intraday component
       double logHO = MathLog(iHigh(symbol,tf,i) / iOpen(symbol,tf,i));
        double logHC = MathLog(iHigh(symbol,tf,i)/ iClose(symbol,tf,i));
        double logLO = MathLog(iLow(symbol,tf,i) / iOpen(symbol,tf,i));
        double logLC = MathLog(iLow(symbol,tf,i) / iClose(symbol,tf,i));
        sumRS += (logHO * logHC) + (logLO * logLC);
      
    }
    double nm1 = n - 1;
    double varOv   = sumOvSq / nm1 - ((sumOv * sumOv) / (n * nm1));
    double varCl   = sumClSq / nm1 - ((sumCl * sumCl) / (n * nm1));
    double varRS   = sumRS / n;

    double k       = 0.34 / ((1.34 + n + 1) / (n - 1));
    double varYZ   = varOv + k * varCl + (1.0 - k) * varRS;
    double sigma   = MathSqrt(MathMax(0.0, varYZ));
    
    // Per-bar volatility in price units
    return sigma * iClose(symbol,tf,0);
    
}

void f_detectTrendChannels(double rangeThreshold, double yzVol, TrendChannel &trendChannels[], BlockAnalytics &analyticsData[]) {
   PrintVerbose("Start Detect TrendChannel");
   int numBlocks = ArraySize(analyticsData);
   EnsureChannelCount(numBlocks,trendChannels);
   if (numBlocks >= 2) {
      int i = 0;
      int channelCount = 0;
      while (i < numBlocks - 1) {
         BlockAnalytics newerBlk = analyticsData[i];     // i=0 is most recent
         BlockAnalytics olderBlk = analyticsData[i+1];  // i+1 is older
         // Check if newer block already has locked trend
          int dir = 0;
          if (newerBlk.trendLocked) {
            dir = newerBlk.trendType;
          } else {
            dir = f_isHigherPosition(newerBlk,olderBlk);
          }
          
          if (dir == DIR_RANGE) {
            LockBlockTrend(i,DIR_RANGE,analyticsData);
            i++;
            continue;
          }
          
          // Found a direction, extend as far as possible

          int segStart = i;
          int segEnd = i + 1;
          // Lock the starting block
          //LockBlockTrend(segStart, dir);
          // Scan forward while direction holds OR next block has same locked trend
          while (segEnd < numBlocks -1) {
            BlockAnalytics blkNewer = analyticsData[segEnd];
            BlockAnalytics blkOlder = analyticsData[segEnd+1];
            int nextDir = 0;
            if (blkNewer.trendLocked) {
               nextDir = blkNewer.trendType;
            } else {
               nextDir =  f_isHigherPosition(blkNewer, blkOlder);
            }
            // Continue if same direction OR if older block already locked with same trend
            if (nextDir == dir || (blkOlder.trendLocked && blkOlder.trendType == dir)) {
                  LockBlockTrend(segEnd, dir, analyticsData);
                  segEnd += 1;
            } else {
                  LockBlockTrend(segEnd, nextDir,analyticsData);
                  break;
            }
          }
          // Lock the last block in segment
          LockBlockTrend(segEnd, dir, analyticsData);
          
          
          double highestHigh, lowestHigh, highestLow, lowestLow;
          double hhIdx, lhIdx, hlIdx, llIdx;
          FindSegmentExtremes(segStart, segEnd,
                    highestHigh,
                    lowestHigh,
                    highestLow,
                    lowestLow,hhIdx, lhIdx, hlIdx, llIdx, analyticsData
                    );
                    
          BlockAnalytics blkOldest = analyticsData[segEnd];
          BlockAnalytics blkNewest = analyticsData[segStart];
          double segmentX1 = blkOldest.centerIdx ; // Oldest block (left)
          double segmentX2 = blkNewest.centerIdx ; // Newest block (right)
          
          // Calculate slopes from extreme points
          double upperSlope = EMPTY_VALUE;
          double lowerSlope = EMPTY_VALUE;
          double upperY1 = EMPTY_VALUE;
          double upperY2 = EMPTY_VALUE;
          double lowerY1 = EMPTY_VALUE;
          double lowerY2 = EMPTY_VALUE;
          
          if (dir == DIR_DOWN) {
            // DOWNTREND: Calculate slopes from extreme points
            double upperSpan = lhIdx - hhIdx;
            double lowerSpan = llIdx - hlIdx;
            upperSlope = upperSpan != 0 ? (lowestHigh - highestHigh) / upperSpan : 0.0;
            lowerSlope = lowerSpan != 0 ? (lowestLow - highestLow) / lowerSpan : 0.0;
           
           // Extend lines to segment boundaries
           upperY1 = highestHigh + (upperSlope * (segmentX1 - hhIdx));
           upperY2 = highestHigh + (upperSlope * (segmentX2 - hhIdx));
           lowerY1 = highestLow + (lowerSlope * (segmentX1 - hlIdx));
           lowerY2 = highestLow + (lowerSlope * (segmentX2 - hlIdx));
          } else if (dir == DIR_UP) {
            // UPTREND: Calculate slopes from extreme points
              double upperSpan = hhIdx - lhIdx;
              double lowerSpan = hlIdx - llIdx;
              upperSlope = upperSpan != 0 ? (highestHigh - lowestHigh) / upperSpan : 0.0;
              lowerSlope = lowerSpan != 0 ? (highestLow - lowestLow) / lowerSpan : 0.0;
              
              // Extend lines to segment boundaries
              upperY1 = lowestHigh + (upperSlope * (segmentX1 - lhIdx));
              upperY2 = lowestHigh + (upperSlope * (segmentX2 - lhIdx));
              lowerY1 = lowestLow + (lowerSlope * (segmentX1 - llIdx));
              lowerY2 = lowestLow + (lowerSlope * (segmentX2 - llIdx));
          } else {
            // RANGE: Connect segment boundaries
              upperSlope = 0.0;
              lowerSlope = 0.0;
              upperY1 =  blkOldest.newHigh;
              upperY2 = blkNewest.newHigh;
              lowerY1 = blkOldest.newLow;
              lowerY2 = blkNewest.newLow;
          }
          // Calculate angle using segment span
          double midY1 = (upperY1 + lowerY1) / 2;
          double midY2 = (upperY2 + lowerY2) / 2;
          double priceChange = midY2 - midY1;
          double segmentSpan = MathAbs(segmentX2 - segmentX1);
          double angleDeg = f_calcChannelAngle(priceChange, segmentSpan, yzVol);
          
          // Store segment X coordinates for drawing
          double upperX1 = segmentX1;
          double upperX2 = segmentX2;
          double lowerX1 = segmentX1;
          double lowerX2 = segmentX2;
          
          // Determine final type based on angle
          int finalType = dir;
          if (MathAbs(angleDeg) <= rangeThreshold) {
            finalType = 0;
          }
          
          // Create channel object
          TrendChannel channel;
          channel.channelType = finalType;
          channel.startBlock = segStart + 1 ;
          channel.endBlock = segEnd + 1 ;
          channel.angleDeg = angleDeg;
          channel.upperX1 = upperX1;
          channel.upperX2 = upperX2;
          channel.lowerX1 = lowerX1;
          channel.lowerX2 = lowerX2;
          channel.upperY1 = upperY1;
          channel.upperY2 = upperY2;
          channel.lowerY1 = lowerY1;
          channel.lowerY2 = lowerY2;
          
          ArrayResize(trendChannels,channelCount+1,0);    
          trendChannels[channelCount] = channel;
          channelCount++;
          
          i = segEnd + 1;
      }
   }
}

// Position comparison: Is block A positioned higher than block B?
int f_isHigherPosition(BlockAnalytics &a, BlockAnalytics &b) {
   if (!a.valid || !b.valid) {
      return DIR_RANGE;
   } else {
        double midA = (a.newHigh + a.newLow) / 2;
        double midB = (b.newHigh + b.newLow) / 2;
        if (midA > midB) {
         return DIR_UP;
        } else if (midA < midB ) {
            return DIR_DOWN;
        } else {
         return DIR_RANGE;
        }
   }
}

//+------------------------------------------------------------------+
//| Find extreme points within a segment for channel drawing        |
//+------------------------------------------------------------------+
void FindSegmentExtremes(int segStart,
                         int segEnd,
                         double &highestHigh,
                         double &lowestHigh,
                         double &highestLow,
                         double &lowestLow,
                         double &highestHighIdx,
                         double &lowestHighIdx,
                         double &highestLowIdx,
                         double &lowestLowIdx,
                         BlockAnalytics &analyticsData[])
{
   highestHigh     = EMPTY_VALUE;
   lowestHigh      = EMPTY_VALUE;
   highestLow      = EMPTY_VALUE;
   lowestLow       = EMPTY_VALUE;

   highestHighIdx  = -1;
   lowestHighIdx   = -1;
   highestLowIdx   = -1;
   lowestLowIdx    = -1;

   int total = ArraySize(analyticsData);

   for(int i = segStart; i <= segEnd; i++)
   {
      if(i < total)
      {
         BlockAnalytics blk = analyticsData[i];

         if(blk.valid)
         {
            // --- Track highest high
            if(highestHigh == EMPTY_VALUE || blk.newHigh > highestHigh)
            {
               highestHigh    = blk.newHigh;
               highestHighIdx = blk.centerIdx;
            }

            // --- Track lowest high
            if(lowestHigh == EMPTY_VALUE || blk.newHigh < lowestHigh)
            {
               lowestHigh    = blk.newHigh;
               lowestHighIdx = blk.centerIdx;
            }

            // --- Track highest low
            if(highestLow == EMPTY_VALUE || blk.newLow > highestLow)
            {
               highestLow    = blk.newLow;
               highestLowIdx = blk.centerIdx;
            }

            // --- Track lowest low
            if(lowestLow == EMPTY_VALUE || blk.newLow < lowestLow)
            {
               lowestLow    = blk.newLow;
               lowestLowIdx = blk.centerIdx;
            }
         }
      }
   }
}

// Calculate channel angle from price movement (Yang-Zhang normalized)
// Result: volatility-normalized degrees — 45° = 1σ move per √T.
// Comparable across ANY instrument and ANY timeframe.
double f_calcChannelAngle(double priceChange, double barSpan, double yzVolPrice) {
       if (barSpan == 0 || yzVolPrice <= 0.0) {
         return 0.0;
       } else {
         double expectedMove = yzVolPrice * MathSqrt(barSpan);
         double normalizedChange = expectedMove > 0.0 ? priceChange / expectedMove : 0.0;
         return MathArctan(normalizedChange) * 180.0 / M_PI;
       }
        
}

void PrintTrendChannels(TrendChannel &channels[])
{
   int total = ArraySize(channels);
   
   Print("==============================================");
   Print("         TREND CHANNELS SUMMARY              ");
   Print("==============================================");
   Print("Total Channels: ", total);
   Print("----------------------------------------------");

   for(int i = 0; i < total; i++)
   {
      TrendChannel ch = channels[i];

      PrintFormat("Channel #%d", i);
      PrintFormat("  Type        : %s", ChannelTypeToString(ch.channelType));
      PrintFormat("  Blocks      : Start=%d  End=%d", ch.startBlock, ch.endBlock);
      PrintFormat("  Angle       : %.2f°", ch.angleDeg);

      Print("  --- Upper Line ---");
      PrintFormat("     X1=%d  Y1=%.5f", ch.upperX1, ch.upperY1);
      PrintFormat("     X2=%d  Y2=%.5f", ch.upperX2, ch.upperY2);

      Print("  --- Lower Line ---");
      PrintFormat("     X1=%d  Y1=%.5f", ch.lowerX1, ch.lowerY1);
      PrintFormat("     X2=%d  Y2=%.5f", ch.lowerX2, ch.lowerY2);

      Print("----------------------------------------------");
   }
}

string ChannelTypeToString(int type)
{
   switch(type)
   {
      case  1:  return "UPTREND";
      case -1:  return "DOWNTREND";
      case  0:  return "RANGE";
      default:  return "UNKNOWN";
   }
}

int MathSign(double value)
{
   if(value > 0.0)
      return 1;
   if(value < 0.0)
      return -1;
   return 0;
}

//+------------------------------------------------------------------+
//| Draw all detected channels                                       |
//| Projection only applied to latest channel (index 0)              |
//+------------------------------------------------------------------+
void DrawAllChannels(int    projLen,
                     color  upCol,
                     color  dnCol,
                     color  rangeCol,
                     int    lineWidth,
                     ENUM_LINE_STYLE lineStyle,
                     bool   showRange,
                     TrendChannel &trendChannels[])
{
   int n = ArraySize(trendChannels);
   if(n <= 0)
      return;

   for(int i = 0; i < n; i++)
   {
      TrendChannel ch = trendChannels[i];

      // Skip range channels if disabled
      if(ch.channelType == DIR_RANGE && !showRange)
         continue;

      // Select channel color
      color chCol;
      if(ch.channelType == DIR_UP)
         chCol = upCol;
      else if(ch.channelType == DIR_DOWN)
         chCol = dnCol;
      else
         chCol = rangeCol;

      // Projection only for latest channel
      int currentProjLen = (i == 0) ? projLen : 0;

      // Calculate slopes
      double upperBarSpan = MathAbs(ch.upperX2 - ch.upperX1);
      double lowerBarSpan = MathAbs(ch.lowerX2 - ch.lowerX1);

      double upperSlope = (upperBarSpan > 0)
                          ? (ch.upperY2 - ch.upperY1) / upperBarSpan
                          : 0.0;

      double lowerSlope = (lowerBarSpan > 0)
                          ? (ch.lowerY2 - ch.lowerY1) / lowerBarSpan
                          : 0.0;
      // Project endpoints
      double upperX2Proj = ch.upperX2 + currentProjLen;
      double lowerX2Proj = ch.lowerX2 + currentProjLen;

      double upperY2Proj = ch.upperY2 + (upperSlope * currentProjLen);
      double lowerY2Proj = ch.lowerY2 + (lowerSlope * currentProjLen);

      // Convert bar index → time
      datetime t1_upper = iTime(_Symbol, _Period, (int)ch.upperX1);
      datetime t1_lower = iTime(_Symbol, _Period, (int)ch.lowerX1);

      datetime t2_upper;
      datetime t2_lower;
      
      if (currentProjLen > 0 ) {
         datetime currentTime = iTime(_Symbol, _Period, 0);
         t2_upper = currentTime + (currentProjLen * PeriodSeconds());
         t2_lower = currentTime + (currentProjLen * PeriodSeconds());
      } else {
         t2_upper = iTime(_Symbol, _Period, (int)ch.upperX2);
         t2_lower = iTime(_Symbol, _Period, (int)ch.lowerX2);
      }

      // Unique names
      string upperName = "TMD_Channel_Upper_" + IntegerToString(i);
      string lowerName = "TMD_Channel_Lower_" + IntegerToString(i);

      // Delete old objects (prevents duplicates)
      ObjectDelete(0, upperName);
      ObjectDelete(0, lowerName);

      // Create upper trend line
      if(ObjectCreate(0, upperName, OBJ_TREND, 0,
                      t1_upper, ch.upperY1,
                      t2_upper, upperY2Proj))
      {
         ObjectSetInteger(0, upperName, OBJPROP_COLOR, chCol);
         ObjectSetInteger(0, upperName, OBJPROP_WIDTH, lineWidth);
         ObjectSetInteger(0, upperName, OBJPROP_STYLE, lineStyle);
         ObjectSetInteger(0, upperName, OBJPROP_RAY_RIGHT, false);
      }

      // Create lower trend line
      if(ObjectCreate(0, lowerName, OBJ_TREND, 0,
                      t1_lower, ch.lowerY1,
                      t2_lower, lowerY2Proj))
      {
         ObjectSetInteger(0, lowerName, OBJPROP_COLOR, chCol);
         ObjectSetInteger(0, lowerName, OBJPROP_WIDTH, lineWidth);
         ObjectSetInteger(0, lowerName, OBJPROP_STYLE, lineStyle);
         ObjectSetInteger(0, lowerName, OBJPROP_RAY_RIGHT, false);
      }
   }
}

//+------------------------------------------------------------------+
//| Remove all objects starting with "TMD_Channel_"                      |
//+------------------------------------------------------------------+
void RemoveAllChannels()
{
   int total = ObjectsTotal(0);

   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i);

      if(StringFind(name, "TMD_Channel") == 0 ||
         StringFind(name, "TMD_Channel") == 0)
      {
         ObjectDelete(0, name);
      }
   }
}


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

//+------------------------------------------------------------------+
// Analyze trend sequence and context
//+------------------------------------------------------------------+
TrendContext AnalyzeTrendContext(TrendChannel &channels[], double quality)
{
   TrendContext result;

   int numChannels = ArraySize(channels);

   //==============================
   // CURRENT CHANNEL
   //==============================
   if(numChannels > 0)
   {
      TrendChannel current = channels[0];

      result.currentType   = current.channelType;
      result.currentBlocks = current.endBlock - current.startBlock + 1;

      if(current.channelType == DIR_UP)
         result.currentLabel = "UPTREND";
      else if(current.channelType == DIR_DOWN)
         result.currentLabel = "DOWNTREND";
      else
         result.currentLabel = "RANGE";

      //==============================
      // PREVIOUS CHANNEL
      //==============================
      if(numChannels > 1)
      {
         TrendChannel prev = channels[1];

         result.prevType = prev.channelType;

         if(prev.channelType == DIR_UP)
            result.prevLabel = "UPTREND";
         else if(prev.channelType == DIR_DOWN)
            result.prevLabel = "DOWNTREND";
         else
            result.prevLabel = "RANGE";

         // Transition detection
         if(result.prevType != result.currentType)
         {
            if(result.currentType == DIR_UP)
               result.transition = "REVERSAL_TO_UP";
            else if(result.currentType == DIR_DOWN)
               result.transition = "REVERSAL_TO_DOWN";
            else
               result.transition = "NEW_TREND";
         }
         else
         {
            result.transition = "CONTINUATION";
         }
      }
      else
      {
         result.prevType   = 0;   // no NA in MQL5
         result.prevLabel  = "";
         result.transition = "NEW_TREND";
      }

      //==============================
      // COUNT TREND CHANGES
      //==============================
      result.trendChanges = 0;

      if(numChannels > 1)
      {
         for(int i = 0; i < numChannels - 1; i++)
         {
            TrendChannel ch1 = channels[i];
            TrendChannel ch2 = channels[i + 1];

            if(ch1.channelType != ch2.channelType)
               result.trendChanges++;
         }
      }
   }
   else
   {
      result.currentType   = DIR_RANGE;
      result.currentLabel  = "RANGE";
      result.transition    = "NEW_TREND";
      result.trendChanges  = 0;
   }

   //==============================
   // QUALITY METRICS
   //==============================
   result.qualityScore = quality;

   if(quality >= 80.0)
      result.confidenceLevel = "HIGH";
   else if(quality >= 60.0)
      result.confidenceLevel = "MEDIUM";
   else
      result.confidenceLevel = "LOW";

   //==============================
   // STRENGTH RATING (angle)
   //==============================
   if(numChannels > 0)
   {
      TrendChannel ch = channels[0];
      double absAngle = MathAbs(ch.angleDeg);

      if(absAngle > 45.0)
         result.strengthRating = "VERY_STRONG";
      else if(absAngle > 30.0)
         result.strengthRating = "STRONG";
      else if(absAngle > 15.0)
         result.strengthRating = "MODERATE";
      else
         result.strengthRating = "WEAK";
   }
   else
   {
      result.strengthRating = "WEAK";
   }

   return result;
}

//+------------------------------------------------------------------+
//| Pretty print TrendContext                                        |
//+------------------------------------------------------------------+
void PrintTrendContext(const TrendContext &ctx)
{
   string sep = "====================================================";
   
   Print(sep);
   Print("                    TREND CONTEXT                  ");
   Print(sep);
   
   // --- Current Trend ---
   Print(">> CURRENT TREND");
   PrintFormat("Type              : %d", ctx.currentType);
   PrintFormat("Label             : %s", ctx.currentLabel);
   PrintFormat("Blocks            : %d", ctx.currentBlocks);
   
   Print(" ");
   
   // --- Previous Trend ---
   Print(">> PREVIOUS TREND");
   PrintFormat("Type              : %d", ctx.prevType);
   PrintFormat("Label             : %s", ctx.prevLabel);
   
   Print(" ");
   
   // --- Transition ---
   Print(">> TRANSITION");
   PrintFormat("Transition Type   : %s", ctx.transition);
   PrintFormat("Trend Changes     : %d", ctx.trendChanges);
   
   Print(" ");
   
   // --- Quality Metrics ---
   Print(">> QUALITY METRICS");
   PrintFormat("Quality Score     : %.2f", ctx.qualityScore);
   PrintFormat("Confidence Level  : %s", ctx.confidenceLevel);
   PrintFormat("Strength Rating   : %s", ctx.strengthRating);
   
   Print(sep);
}

void CreateAnalysis() {
   string bg = "TMD_PANEL_AL";
   if(!ObjectCreate(0,bg,OBJ_RECTANGLE_LABEL,0,0,0))
      return;
   ObjectSetInteger(0,bg,OBJPROP_CORNER,CORNER_LEFT_LOWER);
   ObjectSetInteger(0,bg,OBJPROP_XDISTANCE,20); 
   ObjectSetInteger(0,bg,OBJPROP_YDISTANCE,320);
   ObjectSetInteger(0,bg,OBJPROP_XSIZE,450);
   ObjectSetInteger(0,bg,OBJPROP_YSIZE,270);
   ObjectSetInteger(0,bg,OBJPROP_COLOR,C'10,16,28');
   ObjectSetInteger(0,bg,OBJPROP_BGCOLOR,C'10,16,28');
   ObjectSetInteger(0, bg, OBJPROP_BORDER_COLOR, C'10,16,28');
   ObjectSetInteger(0,bg,OBJPROP_BORDER_TYPE,BORDER_FLAT);
   ObjectSetInteger(0,bg,OBJPROP_STYLE,STYLE_SOLID);
   ObjectSetInteger(0,bg,OBJPROP_BACK,false);
   ObjectSetInteger(0,bg,OBJPROP_WIDTH,1);
   ObjectSetInteger(0, bg, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, bg, OBJPROP_HIDDEN, false);
   
      string online = "TMD_ALTITLE";
   if(!ObjectCreate(0,online,OBJ_LABEL,0,0,0))
      return;
   ObjectSetInteger(0,online,OBJPROP_CORNER,CORNER_LEFT_LOWER);
   ObjectSetInteger(0,online,OBJPROP_ANCHOR,ANCHOR_LEFT_LOWER);
   ObjectSetInteger(0,online,OBJPROP_XDISTANCE,42);
   ObjectSetInteger(0,online,OBJPROP_YDISTANCE,298);
   ObjectSetInteger(0,online,OBJPROP_FONTSIZE,10);
   ObjectSetString(0,online,OBJPROP_FONT,"Consolas");
   ObjectSetInteger(0,online,OBJPROP_COLOR,C'0,180,180');
   ObjectSetString(0,online,OBJPROP_TEXT,"MARKET ANALYSIS");
   
         
    string s3 = "TMD_S3_AL";
   if(!ObjectCreate(0,s3,OBJ_RECTANGLE_LABEL,0,0,0))
      return;
   ObjectSetInteger(0,s3,OBJPROP_CORNER,CORNER_LEFT_LOWER);
   ObjectSetInteger(0,s3,OBJPROP_XDISTANCE,20); 
   ObjectSetInteger(0,s3,OBJPROP_YDISTANCE,288);
   ObjectSetInteger(0,s3,OBJPROP_XSIZE,450);
   ObjectSetInteger(0,s3,OBJPROP_YSIZE,1);
   ObjectSetInteger(0,s3,OBJPROP_COLOR,clrBlack);
   ObjectSetInteger(0,s3,OBJPROP_BGCOLOR,C'25,40,55');
   ObjectSetInteger(0, s3, OBJPROP_BORDER_COLOR, tmdBg);
   ObjectSetInteger(0,s3,OBJPROP_BORDER_TYPE,BORDER_FLAT);
   ObjectSetInteger(0,s3,OBJPROP_STYLE,STYLE_SOLID);
   ObjectSetInteger(0,s3,OBJPROP_BACK,false);
   ObjectSetInteger(0,s3,OBJPROP_WIDTH,1);
   ObjectSetInteger(0, s3, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, s3, OBJPROP_HIDDEN, false);
   

   

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
   ObjectSetString(0,v1,OBJPROP_TEXT,DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE)));
   
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
   ObjectSetString(0,v2,OBJPROP_TEXT,DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY)));
   
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
   ObjectSetString(0,v3,OBJPROP_TEXT,"+"+DoubleToString(AccountInfoDouble(ACCOUNT_PROFIT)));
   
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
   ObjectSetString(0,l6,OBJPROP_TEXT,"QUALITY");
   
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
   ObjectSetString(0,l7,OBJPROP_TEXT,"STRENGTH");
   
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
   ObjectSetString(0,l8,OBJPROP_TEXT,"VOL MOMENTUM");
   
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
   ObjectSetString(0,l9,OBJPROP_TEXT,"BODY");
   
       string v9 = "TMD_V9";
   if(!ObjectCreate(0,v9,OBJ_LABEL,0,0,0))
      return;
   ObjectSetInteger(0,v9,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,v9,OBJPROP_ANCHOR,ANCHOR_RIGHT_UPPER);
   ObjectSetInteger(0,v9,OBJPROP_XDISTANCE,280);
   ObjectSetInteger(0,v9,OBJPROP_YDISTANCE,236);
   ObjectSetInteger(0,v9,OBJPROP_FONTSIZE,10);
   ObjectSetString(0,v9,OBJPROP_FONT,"Consolas");
   ObjectSetInteger(0,v9,OBJPROP_COLOR,C'0,230,120');
   ObjectSetString(0,v9,OBJPROP_TEXT,"Undefined");
   
      
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
   ObjectSetInteger(0, s3, OBJPROP_BORDER_COLOR, tmdBg);
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
   ObjectSetString(0,l10,OBJPROP_TEXT,"CANDLE");
   
   string v10 = "TMD_V10";
   if(!ObjectCreate(0,v10,OBJ_LABEL,0,0,0))
      return;
   ObjectSetInteger(0,v10,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,v10,OBJPROP_ANCHOR,ANCHOR_RIGHT_UPPER);
   ObjectSetInteger(0,v10,OBJPROP_XDISTANCE,280);
   ObjectSetInteger(0,v10,OBJPROP_YDISTANCE,267);
   ObjectSetInteger(0,v10,OBJPROP_FONTSIZE,10);
   ObjectSetString(0,v10,OBJPROP_FONT,"Consolas");
   ObjectSetInteger(0,v10,OBJPROP_COLOR,C'0,230,120');
   ObjectSetString(0,v10,OBJPROP_TEXT,"Undefined");
   
      string l11 = "TMD_L11";
   if(!ObjectCreate(0,l11,OBJ_LABEL,0,0,0))
      return;
   ObjectSetInteger(0,l11,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,l11,OBJPROP_ANCHOR,ANCHOR_LEFT_UPPER);
   ObjectSetInteger(0,l11,OBJPROP_XDISTANCE,30);
   ObjectSetInteger(0,l11,OBJPROP_YDISTANCE,285);
   ObjectSetInteger(0,l11,OBJPROP_FONTSIZE,10);
   ObjectSetString(0,l11,OBJPROP_FONT,"Consolas");
   ObjectSetInteger(0,l11,OBJPROP_COLOR,C'70,90,110');
   ObjectSetString(0,l11,OBJPROP_TEXT,"VOL DELTA");
   
   string v11 = "TMD_V11";
   if(!ObjectCreate(0,v11,OBJ_LABEL,0,0,0))
      return;
   ObjectSetInteger(0,v11,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,v11,OBJPROP_ANCHOR,ANCHOR_RIGHT_UPPER);
   ObjectSetInteger(0,v11,OBJPROP_XDISTANCE,280);
   ObjectSetInteger(0,v11,OBJPROP_YDISTANCE,285);
   ObjectSetInteger(0,v11,OBJPROP_FONTSIZE,10);
   ObjectSetString(0,v11,OBJPROP_FONT,"Consolas");
   ObjectSetInteger(0,v11,OBJPROP_COLOR,C'0,230,120');
   ObjectSetString(0,v11,OBJPROP_TEXT,"Undefined");
   
         string l12 = "TMD_L12";
   if(!ObjectCreate(0,l12,OBJ_LABEL,0,0,0))
      return;
   ObjectSetInteger(0,l12,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,l12,OBJPROP_ANCHOR,ANCHOR_LEFT_UPPER);
   ObjectSetInteger(0,l12,OBJPROP_XDISTANCE,30);
   ObjectSetInteger(0,l12,OBJPROP_YDISTANCE,304);
   ObjectSetInteger(0,l12,OBJPROP_FONTSIZE,10);
   ObjectSetString(0,l12,OBJPROP_FONT,"Consolas");
   ObjectSetInteger(0,l12,OBJPROP_COLOR,C'70,90,110');
   ObjectSetString(0,l12,OBJPROP_TEXT,"CHANNEL");
   
   string v12 = "TMD_V12";
   if(!ObjectCreate(0,v12,OBJ_LABEL,0,0,0))
      return;
   ObjectSetInteger(0,v12,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,v12,OBJPROP_ANCHOR,ANCHOR_RIGHT_UPPER);
   ObjectSetInteger(0,v12,OBJPROP_XDISTANCE,280);
   ObjectSetInteger(0,v12,OBJPROP_YDISTANCE,304);
   ObjectSetInteger(0,v12,OBJPROP_FONTSIZE,10);
   ObjectSetString(0,v12,OBJPROP_FONT,"Consolas");
   ObjectSetInteger(0,v12,OBJPROP_COLOR,C'0,230,120');
   ObjectSetString(0,v12,OBJPROP_TEXT,"Undefined");
   
   string l13 = "TMD_L13";
   if(!ObjectCreate(0,l13,OBJ_LABEL,0,0,0))
      return;
   ObjectSetInteger(0,l13,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,l13,OBJPROP_ANCHOR,ANCHOR_LEFT_UPPER);
   ObjectSetInteger(0,l13,OBJPROP_XDISTANCE,30);
   ObjectSetInteger(0,l13,OBJPROP_YDISTANCE,323);
   ObjectSetInteger(0,l13,OBJPROP_FONTSIZE,10);
   ObjectSetString(0,l13,OBJPROP_FONT,"Consolas");
   ObjectSetInteger(0,l13,OBJPROP_COLOR,C'70,90,110');
   ObjectSetString(0,l13,OBJPROP_TEXT,"PRESSURE");
   
   string v13 = "TMD_V13";
   if(!ObjectCreate(0,v13,OBJ_LABEL,0,0,0))
      return;
   ObjectSetInteger(0,v13,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,v13,OBJPROP_ANCHOR,ANCHOR_RIGHT_UPPER);
   ObjectSetInteger(0,v13,OBJPROP_XDISTANCE,280);
   ObjectSetInteger(0,v13,OBJPROP_YDISTANCE,323);
   ObjectSetInteger(0,v13,OBJPROP_FONTSIZE,10);
   ObjectSetString(0,v13,OBJPROP_FONT,"Consolas");
   ObjectSetInteger(0,v13,OBJPROP_COLOR,C'0,230,120');
   ObjectSetString(0,v13,OBJPROP_TEXT,"Undefined");
   
      string l14 = "TMD_L14";
   if(!ObjectCreate(0,l14,OBJ_LABEL,0,0,0))
      return;
   ObjectSetInteger(0,l14,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,l14,OBJPROP_ANCHOR,ANCHOR_LEFT_UPPER);
   ObjectSetInteger(0,l14,OBJPROP_XDISTANCE,30);
   ObjectSetInteger(0,l14,OBJPROP_YDISTANCE,342);
   ObjectSetInteger(0,l14,OBJPROP_FONTSIZE,10);
   ObjectSetString(0,l14,OBJPROP_FONT,"Consolas");
   ObjectSetInteger(0,l14,OBJPROP_COLOR,C'70,90,110');
   ObjectSetString(0,l14,OBJPROP_TEXT,"COMPOSITE RELATION");
   
   string v14 = "TMD_V14";
   if(!ObjectCreate(0,v14,OBJ_LABEL,0,0,0))
      return;
   ObjectSetInteger(0,v14,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,v14,OBJPROP_ANCHOR,ANCHOR_RIGHT_UPPER);
   ObjectSetInteger(0,v14,OBJPROP_XDISTANCE,280);
   ObjectSetInteger(0,v14,OBJPROP_YDISTANCE,342);
   ObjectSetInteger(0,v14,OBJPROP_FONTSIZE,10);
   ObjectSetString(0,v14,OBJPROP_FONT,"Consolas");
   ObjectSetInteger(0,v14,OBJPROP_COLOR,C'0,230,120');
   ObjectSetString(0,v14,OBJPROP_TEXT,"Undefined");
   
         string l15 = "TMD_L15";
   if(!ObjectCreate(0,l15,OBJ_LABEL,0,0,0))
      return;
   ObjectSetInteger(0,l15,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,l15,OBJPROP_ANCHOR,ANCHOR_LEFT_UPPER);
   ObjectSetInteger(0,l15,OBJPROP_XDISTANCE,30);
   ObjectSetInteger(0,l15,OBJPROP_YDISTANCE,361);
   ObjectSetInteger(0,l15,OBJPROP_FONTSIZE,10);
   ObjectSetString(0,l15,OBJPROP_FONT,"Consolas");
   ObjectSetInteger(0,l15,OBJPROP_COLOR,C'70,90,110');
   ObjectSetString(0,l15,OBJPROP_TEXT,"COMPOSITE PATTERN");
   
   string v15 = "TMD_V15";
   if(!ObjectCreate(0,v15,OBJ_LABEL,0,0,0))
      return;
   ObjectSetInteger(0,v15,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,v15,OBJPROP_ANCHOR,ANCHOR_RIGHT_UPPER);
   ObjectSetInteger(0,v15,OBJPROP_XDISTANCE,280);
   ObjectSetInteger(0,v15,OBJPROP_YDISTANCE,361);
   ObjectSetInteger(0,v15,OBJPROP_FONTSIZE,10);
   ObjectSetString(0,v15,OBJPROP_FONT,"Consolas");
   ObjectSetInteger(0,v15,OBJPROP_COLOR,C'0,230,120');
   ObjectSetString(0,v15,OBJPROP_TEXT,"Undefined");
   
            string l16 = "TMD_L16";
   if(!ObjectCreate(0,l16,OBJ_LABEL,0,0,0))
      return;
   ObjectSetInteger(0,l16,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,l16,OBJPROP_ANCHOR,ANCHOR_LEFT_UPPER);
   ObjectSetInteger(0,l16,OBJPROP_XDISTANCE,30);
   ObjectSetInteger(0,l16,OBJPROP_YDISTANCE,380);
   ObjectSetInteger(0,l16,OBJPROP_FONTSIZE,10);
   ObjectSetString(0,l16,OBJPROP_FONT,"Consolas");
   ObjectSetInteger(0,l16,OBJPROP_COLOR,C'70,90,110');
   ObjectSetString(0,l16,OBJPROP_TEXT,"MSB");
   
   string v16 = "TMD_V16";
   if(!ObjectCreate(0,v16,OBJ_LABEL,0,0,0))
      return;
   ObjectSetInteger(0,v16,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,v16,OBJPROP_ANCHOR,ANCHOR_RIGHT_UPPER);
   ObjectSetInteger(0,v16,OBJPROP_XDISTANCE,280);
   ObjectSetInteger(0,v16,OBJPROP_YDISTANCE,380);
   ObjectSetInteger(0,v16,OBJPROP_FONTSIZE,10);
   ObjectSetString(0,v16,OBJPROP_FONT,"Consolas");
   ObjectSetInteger(0,v16,OBJPROP_COLOR,C'0,230,120');
   ObjectSetString(0,v16,OBJPROP_TEXT,"Undefined");
}

void UpdatePanel(TrendContext &tc, string volMom, string bodyStatus, CurrentBarAnalysis &cb, 
double trendDelta, double trendDeltaPct, string posStatus, double channelPos, double upperPinChg, double lowerPinChg, CompositeAnalysis &ca, string analysis, MarketStructureBreak &msbInfo ) {
   ObjectSetString(0,"TMD_V4",OBJPROP_TEXT,ChannelTypeToString(tc.currentType));
   if (tc.currentType == DIR_UP) {
      ObjectSetInteger(0,"TMD_V4",OBJPROP_COLOR,C'0,230,230');
   } else if (tc.currentType == DIR_DOWN) {
      ObjectSetInteger(0,"TMD_V4",OBJPROP_COLOR,C'180,40,220');
   } else {
      ObjectSetInteger(0,"TMD_V4",OBJPROP_COLOR,tmdSilver);
   }
   
   double q = tc.qualityScore;
   ObjectSetString(0,"TMD_V6",OBJPROP_TEXT,DoubleToString(q,0));
   if (q > 80) {
      ObjectSetInteger(0,"TMD_V6",OBJPROP_COLOR,C'0,230,120');
   } else if (q > 60 ) {
      ObjectSetInteger(0,"TMD_V6",OBJPROP_COLOR, tmdOrange);
   } else {
      ObjectSetInteger(0,"TMD_V6",OBJPROP_COLOR,tmdRed);
   }
   
   string strength = tc.strengthRating;
   ObjectSetString(0,"TMD_V7",OBJPROP_TEXT,strength);
   if (strength == "STRONG" || strength == "VERY_STRONG") {
      ObjectSetInteger(0,"TMD_V7",OBJPROP_COLOR,C'0,230,120');
   } else if (strength == "MODERATE") {
      ObjectSetInteger(0,"TMD_V7",OBJPROP_COLOR, tmdOrange);
   } else {
      ObjectSetInteger(0,"TMD_V7",OBJPROP_COLOR,tmdRed);
   }
   
   ObjectSetString(0,"TMD_V8",OBJPROP_TEXT,volMom);
   if (StringFind(volMom, "INCREASING") != -1) { 
      ObjectSetInteger(0,"TMD_V8",OBJPROP_COLOR,C'0,230,120');
   } else {
      ObjectSetInteger(0,"TMD_V8",OBJPROP_COLOR,tmdRed);
   }
   
   ObjectSetString(0,"TMD_V9",OBJPROP_TEXT,bodyStatus);
   if (bodyStatus == "EXPANDING") {
      ObjectSetInteger(0,"TMD_V9",OBJPROP_COLOR,C'0,230,120');
   } else if (bodyStatus == "STABLE") {
      ObjectSetInteger(0,"TMD_V9",OBJPROP_COLOR, tmdSilver);
   } else {
      ObjectSetInteger(0,"TMD_V9",OBJPROP_COLOR,tmdRed);
   }
   
   ObjectSetString(0,"TMD_V10",OBJPROP_TEXT,cb.pattern);
   if (cb.patternBias == "BULLISH") {
      ObjectSetInteger(0,"TMD_V10",OBJPROP_COLOR,C'0,230,230');
   } else if (cb.patternBias == "BEARISH") {
      ObjectSetInteger(0,"TMD_V10",OBJPROP_COLOR,C'180,40,220');
   } else {
      ObjectSetInteger(0,"TMD_V10",OBJPROP_COLOR,tmdSilver);
   }
   
   ObjectSetString(0,"TMD_V11",OBJPROP_TEXT,DoubleToString(trendDeltaPct,0)+"%");
   if (trendDelta > 0) {
      ObjectSetInteger(0,"TMD_V11",OBJPROP_COLOR,C'0,230,230');
   } else {
      ObjectSetInteger(0,"TMD_V11",OBJPROP_COLOR,C'180,40,220');
   }
   
   ObjectSetString(0,"TMD_V12",OBJPROP_TEXT,posStatus+"("+DoubleToString(channelPos,0)+"%)");
   if (posStatus == "OVERBOUGHT") {
      ObjectSetInteger(0,"TMD_V12",OBJPROP_COLOR,C'180,40,220'); // BEARISH
   } else if (posStatus == "OVERSOLD") {
      ObjectSetInteger(0,"TMD_V12",OBJPROP_COLOR,C'0,230,230'); // BULLISH
   } else {
       ObjectSetInteger(0,"TMD_V12",OBJPROP_COLOR,tmdSilver);
   }
   
      ObjectSetString(0,"TMD_V13",OBJPROP_TEXT,DoubleToString(upperPinChg,0)+" / "+DoubleToString(lowerPinChg,0));
      if (upperPinChg > 15 && lowerPinChg < 15) {
         ObjectSetInteger(0,"TMD_V13",OBJPROP_COLOR,C'180,40,220');
      } else if (lowerPinChg > 15 && upperPinChg < 15) {
         ObjectSetInteger(0,"TMD_V13",OBJPROP_COLOR,C'0,230,230');
      } else  if (upperPinChg < -15 && lowerPinChg > -15){
          ObjectSetInteger(0,"TMD_V13",OBJPROP_COLOR,C'0,230,230');
      } else if (upperPinChg > -15 && lowerPinChg < -15) {
         ObjectSetInteger(0,"TMD_V13",OBJPROP_COLOR,C'180,40,220');
      } else {
          ObjectSetInteger(0,"TMD_V13",OBJPROP_COLOR,tmdSilver);
       }
       
       
       ObjectSetString(0,"TMD_V14",OBJPROP_TEXT,ca.blockRelation);
       if (ca.blockRelationBias == "BULLISH") {
         ObjectSetInteger(0,"TMD_V14",OBJPROP_COLOR,C'0,230,230');
       } else if (ca.blockRelationBias == "BEARISH") {
         ObjectSetInteger(0,"TMD_V14",OBJPROP_COLOR,C'180,40,220'); // BEARISH
       } else {
         ObjectSetInteger(0,"TMD_V14",OBJPROP_COLOR,tmdSilver);
       }
       
       ObjectSetString(0,"TMD_V15",OBJPROP_TEXT,ca.compositePattern);
       if (ca.compositeBias == "BULLISH") {
         ObjectSetInteger(0,"TMD_V15",OBJPROP_COLOR,C'0,230,230');
       } else if (ca.compositeBias == "BEARISH") {
         ObjectSetInteger(0,"TMD_V15",OBJPROP_COLOR,C'180,40,220'); // BEARISH
       } else {
         ObjectSetInteger(0,"TMD_V15",OBJPROP_COLOR,tmdSilver);
       }
       
     
       if (msbInfo.bullish) {
         ObjectSetString(0,"TMD_V16",OBJPROP_TEXT,"▲("+IntegerToString(msbInfo.barsAgo)+")");
         ObjectSetInteger(0,"TMD_V16",OBJPROP_COLOR,C'0,230,230');
       } else {
         ObjectSetString(0,"TMD_V16",OBJPROP_TEXT,"▼("+IntegerToString(msbInfo.barsAgo)+")");
         ObjectSetInteger(0,"TMD_V16",OBJPROP_COLOR,C'180,40,220'); // BEARISH
       } 
       CreateLabelsFromString("TMD_AL_ST", analysis, 30, 269, 12);
       
}


//+------------------------------------------------------------------+
//| Create labels for a long string, splitting on spaces            |
//+------------------------------------------------------------------+
void CreateLabelsFromString(string baseName, string text, int startX=30, int startY=269, int lineHeight=12, int maxLineLen=60)
{
    int lineCount = 0;
    string currentLine = "";

    int pos = 0;
    int len = StringLen(text);

    while(pos < len)
    {
        // Find next space
        int nextSpace = StringFind(text, " ", pos);
        if(nextSpace == -1) nextSpace = len; // last word

        string word = StringSubstr(text, pos, nextSpace - pos);

        // check if adding word exceeds maxLineLen
        if(StringLen(currentLine) + StringLen(word) + (StringLen(currentLine) > 0 ? 1 : 0) > maxLineLen)
        {
            // create label for currentLine
            string labelName = baseName + IntegerToString(lineCount+1);
            if(ObjectCreate(0, labelName, OBJ_LABEL, 0, 0, 0))
            {
                ObjectSetInteger(0, labelName, OBJPROP_CORNER, CORNER_LEFT_LOWER);
                ObjectSetInteger(0, labelName, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
                ObjectSetInteger(0, labelName, OBJPROP_XDISTANCE, startX);
                ObjectSetInteger(0, labelName, OBJPROP_YDISTANCE, startY - lineCount * lineHeight);
                ObjectSetInteger(0, labelName, OBJPROP_FONTSIZE, 9);
                ObjectSetString(0, labelName, OBJPROP_FONT, "Consolas");
                ObjectSetInteger(0, labelName, OBJPROP_COLOR, ColorToARGB(70,90,110));
                ObjectSetString(0, labelName, OBJPROP_TEXT, currentLine);
            }
            lineCount++;
            currentLine = "";
        }

        // append word
        if(StringLen(currentLine) > 0) currentLine += " ";
        currentLine += word;

        pos = nextSpace + 1;
    }

    // create label for remaining text
    if(StringLen(currentLine) > 0)
    {
        string labelName = baseName + IntegerToString(lineCount+1);
        if(ObjectCreate(0, labelName, OBJ_LABEL, 0, 0, 0))
        {
            ObjectSetInteger(0, labelName, OBJPROP_CORNER, CORNER_LEFT_LOWER);
            ObjectSetInteger(0, labelName, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
            ObjectSetInteger(0, labelName, OBJPROP_XDISTANCE, startX);
            ObjectSetInteger(0, labelName, OBJPROP_YDISTANCE, startY - lineCount * lineHeight);
            ObjectSetInteger(0, labelName, OBJPROP_FONTSIZE, 9);
            ObjectSetString(0, labelName, OBJPROP_FONT, "Consolas");
            ObjectSetInteger(0, labelName, OBJPROP_COLOR, ColorToARGB(70,90,110));
            ObjectSetString(0, labelName, OBJPROP_TEXT, currentLine);
        }
    }
}

// Helper to convert RGB to ARGB for Object color
int ColorToARGB(int r, int g, int b)
{
    return (255 << 24) | (r << 16) | (g << 8) | b;
}

int SplitString(string inp, string separator, string &output[])
{
   return StringSplit(inp, StringGetCharacter(separator,0), output);
}

bool IsNewBar(SymbolTF &s)
{
   datetime currentBar = iTime(s.symbol, s.tf, 0);
   if(currentBar==0)
      return false;

   if(currentBar != s.lastBarTime)
   {
      s.lastBarTime = currentBar;
      return true;
   }

   return false;
}

void RunStrategy(string symbol, ENUM_TIMEFRAMES tf, SymbolTF &stf)
{
   //Print("New bar: ",symbol," ",EnumToString(tf));
   MqlRates rates[];
   int copied = CopyRates(symbol, tf, 0, 200, rates);
   // ---- YOUR STRATEGY HERE ----
   // CopyRates
   // Indicators
   // Trade execution
   
   // Create ATR handle (period 20, current timeframe)
   int atrHandle = iATR(symbol, tf, 20);
   
   
   int rsiHandle = iRSI(symbol,tf,14,PRICE_CLOSE);
   int adxHandle = iADX(symbol,tf,7);
   
   double rsiBuffer[];
   double adxBuffer[];
   
   CopyBuffer(rsiHandle, 0, 1, 1, rsiBuffer) ;
   CopyBuffer(adxHandle, 0, 1, 1, adxBuffer) ;
   
   double rsi = rsiBuffer[0];
   double adx = adxBuffer[0];
   
   PrintVerbose("=== ANALYSIS ===");
   double globalAvgRange = GetATR(atrHandle);
   double globalYZVol    = f_yangZhangVolatility(symbol,tf,20);
   double b, s, d;
   f_geoVol( symbol, tf, b, s, d, 1); 
   CurrentBarAnalysis cb = f_analyzeCurrentBar(symbol,tf, 1,globalAvgRange,b,s);
   
   // Part 1: Current candle status
   string analysis = "The current candle presents a "+f_patternDesc(cb.pattern)+" with "+f_rangeStatusStr(cb.rangeStatus)+" showing "+cb.pressureStatus+" pressure ("+DoubleToString(cb.delta,2)+").";
    // Part 2: Broader trend context
    BlockAnalytics analyticsData[];
    CalculateGroups(symbol,tf,analyticsData);
    BlockAnalytics blk1 = analyticsData[0];
    BlockAnalytics blk2 = analyticsData[1];
    CompositeAnalysis g_composite = runCompositeAnalysis(blk1,blk2);
    
    TrendChannel trendChannels[];
    f_detectTrendChannels(i_rangeAngleThreshold,globalYZVol,trendChannels,analyticsData);
    if (verboseLogging) {
      PrintTrendChannels(trendChannels);
    }
        // Analyze trend context
    // Get latest trend data
    TrendChannel latestTrend = trendChannels[0];
    // Aggregate trend data
    double trendBuy = 0.0; double trendSell = 0.0;
    double sumUpperPin = 0.0; double sumLowerPin = 0.0; double sumBody = 0.0;
    double firstBlockUpperPin = EMPTY_VALUE; double lastBlockUpperPin = EMPTY_VALUE;
    double firstBlockLowerPin = EMPTY_VALUE; double lastBlockLowerPin = EMPTY_VALUE;
    double firstBlockBody = EMPTY_VALUE; double lastBlockBody = EMPTY_VALUE;
    double firstBlockVol = EMPTY_VALUE; double lastBlockVol = EMPTY_VALUE;
    double firstBlockDelta = EMPTY_VALUE; double lastBlockDelta = EMPTY_VALUE;
    int trendBlocks = 0;
    
    int trendStart = latestTrend.startBlock - 1;
    int trendEnd = latestTrend.endBlock - 1;
    trendBlocks = trendEnd - trendStart + 1;
    for (int i = trendStart; i <= trendEnd; i++) {
      BlockAnalytics ba = analyticsData[i];
      if (ba.valid) {
         trendBuy += ba.totalBuy;
         trendSell += ba.totalSell;
         sumUpperPin += ba.avgUpperPin;
         sumLowerPin += ba.avgLowerPin;
         sumBody += ba.avgBody;
         if (i == trendEnd) {
            firstBlockUpperPin = ba.avgUpperPin;
            firstBlockLowerPin = ba.avgLowerPin;
            firstBlockBody = ba.avgBody;
            firstBlockVol = ba.totalBuy + ba.totalSell;
            firstBlockDelta = ba.delta;
         }
                        
           if (i == trendStart) {
               lastBlockUpperPin = ba.avgUpperPin;
               lastBlockLowerPin = ba.avgLowerPin;
               lastBlockBody = ba.avgBody;
               lastBlockVol = ba.totalBuy + ba.totalSell;
               lastBlockDelta = ba.delta;
           }
                        
      }
      
    }
    double trendDelta = trendBuy - trendSell;
    double trendDeltaPct = trendBuy + trendSell > 0 ? (trendDelta / (trendBuy + trendSell)) * 100 : 0.0;
    double avgUpperPin = trendBlocks > 0 ? sumUpperPin / trendBlocks : EMPTY_VALUE;
    double avgLowerPin = trendBlocks > 0 ? sumLowerPin / trendBlocks : EMPTY_VALUE;
    double avgBody = trendBlocks > 0 ? sumBody / trendBlocks : EMPTY_VALUE;
    
    // Pin change percentages
    double upperPinChg = firstBlockUpperPin != EMPTY_VALUE && lastBlockUpperPin != EMPTY_VALUE && firstBlockUpperPin != 0 ? ((lastBlockUpperPin - firstBlockUpperPin) / firstBlockUpperPin) * 100 : 0.0;
    double lowerPinChg = firstBlockLowerPin != EMPTY_VALUE && lastBlockLowerPin != EMPTY_VALUE && firstBlockLowerPin != 0 ? ((lastBlockLowerPin - firstBlockLowerPin) / firstBlockLowerPin) * 100 : 0.0;
    
    // Body expansion status
    string bodyStatus = firstBlockBody != EMPTY_VALUE && lastBlockBody != EMPTY_VALUE ? (lastBlockBody > firstBlockBody ? "EXPANDING" : lastBlockBody < firstBlockBody ? "CONTRACTING" : "STABLE") : "-";
    
    // Volume momentum
    string volMom = firstBlockVol != EMPTY_VALUE && lastBlockVol != EMPTY_VALUE ? (lastBlockVol > firstBlockVol ? "INCREASING ▲" : "DECREASING ▼") : "-";
    
    // Delta direction
    string deltaDir = firstBlockDelta != EMPTY_VALUE && lastBlockDelta != EMPTY_VALUE ? (lastBlockDelta > firstBlockDelta ? "POSITIVE ▲" : "NEGATIVE ▼") : "-";
    
     // Pin ratio and control
    double pinRatio = avgUpperPin != EMPTY_VALUE && avgLowerPin != EMPTY_VALUE && avgLowerPin != 0 ? avgUpperPin / avgLowerPin : 1.0;
    string control = trendDelta > 0 ? "BUYERS" : trendDelta < 0 ? "SELLERS" : "BALANCED";
    
      // Trend Channel Boundaries (display-aligned with projection)
    double currentPrice = iClose(symbol,tf,1);
    int groupSize = MathMax(1, (int)MathRound((double)i_window / i_groups));
    int projLenCh = groupSize + 2;
    double upperChPrice = EMPTY_VALUE;
    double lowerChPrice = EMPTY_VALUE;
    double upperSpanCh = MathAbs(latestTrend.upperX2 - latestTrend.upperX1);
    double lowerSpanCh = MathAbs(latestTrend.lowerX2 - latestTrend.lowerX1);
     double upperSlopeCh = upperSpanCh != 0 ? (latestTrend.upperY2 - latestTrend.upperY1) / upperSpanCh : 0.0;
     double lowerSlopeCh = lowerSpanCh != 0 ? (latestTrend.lowerY2 - latestTrend.lowerY1) / lowerSpanCh : 0.0;
     upperChPrice = latestTrend.upperY2 + (upperSlopeCh * projLenCh);
     lowerChPrice = latestTrend.lowerY2 + (lowerSlopeCh * projLenCh) ;
    // Keep existing downstream variable names (now representing channel bounds)
    double resistPrice = upperChPrice;
    double supportPrice = lowerChPrice;
    
    double resistDiff = resistPrice != EMPTY_VALUE ? resistPrice - currentPrice : EMPTY_VALUE;
    double supportDiff = supportPrice != EMPTY_VALUE ? currentPrice - supportPrice : EMPTY_VALUE;
    double resistPct = resistDiff != EMPTY_VALUE && currentPrice != 0 ? (resistDiff / currentPrice) * 100 : EMPTY_VALUE;
    double supportPct = supportDiff != EMPTY_VALUE && currentPrice != 0 ? (supportDiff / currentPrice) * 100 : EMPTY_VALUE;
    double channelWidth = resistPrice != EMPTY_VALUE && supportPrice != EMPTY_VALUE ? resistPrice - supportPrice : EMPTY_VALUE;
    double rrRatio = resistDiff != EMPTY_VALUE && supportDiff != EMPTY_VALUE && supportDiff != 0 ? resistDiff / supportDiff : EMPTY_VALUE;
    double channelPos = channelWidth != EMPTY_VALUE && channelWidth != 0 ? ((currentPrice - supportPrice) / channelWidth) * 100 : EMPTY_VALUE;
    string posStatus = channelPos != EMPTY_VALUE ? (channelPos > 70 ? "OVERBOUGHT" : channelPos < 30 ? "OVERSOLD" : "NEUTRAL") : "-";

    // Quality score calculation — Continuous graduation (no dead zones)
    // Each component scores on a smooth 0→max scale instead of binary on/off.
    // Total possible: 15 + 10 + 10 + 10 + 8 + 5 = 58 on top of base 50 = 108, capped at 100.
    double quality = 50.0;
    int contradictions = 0;
    
     // ── Angle strength (0→15, continuous) ──
     // Linear interpolation from rangeThreshold (0 pts) to 45° (full 15 pts).
     // Eliminates the dead zone between rangeThreshold and old 35° cutoff.
     double absAngle = MathAbs(latestTrend.angleDeg);
     double angleRange = 45.0 - i_rangeAngleThreshold;
     double angleScore = angleRange > 0.0 ? 15.0 * MathMax(0.0, MathMin(1.0, (absAngle - i_rangeAngleThreshold) / angleRange)) : 0.0;
     quality += angleScore;
     
     // ── Delta consistency (0→10, proportional) ──
     // Scores based on the fraction of adjacent block pairs with consistent delta sign.
      int totalPairs = 0;
      int consistentPairs = 0;
      
      int startIndex = latestTrend.startBlock - 1;
      int endIndex   = latestTrend.endBlock - 1;
      
      int dataSize = ArraySize(analyticsData);
      
      for(int i = startIndex; i <= endIndex; i++)
      {
         if(i < dataSize && (i + 1) < dataSize)
         {
            double d1 = analyticsData[i].delta;
            double d2 = analyticsData[i + 1].delta;
      
            if(d1 != EMPTY_VALUE && d2 != EMPTY_VALUE)
            {
               totalPairs++;
      
               if(MathSign(d1) == MathSign(d2))
                  consistentPairs++;
            }
         }
      }
      
      bool deltaConsistent = (totalPairs > 0 && consistentPairs == totalPairs);
      
      double deltaRatio = 0.0;
      if(totalPairs > 0)
         deltaRatio = (double)consistentPairs / (double)totalPairs;
      
      quality += 10.0 * deltaRatio;
      
      // ── Volume momentum (0→10, continuous) ──
      // Scales linearly: 0 pts at no growth, full 10 pts at ≥50% growth.
      if(firstBlockVol != EMPTY_VALUE &&
         lastBlockVol != EMPTY_VALUE  &&
         firstBlockVol > 0.0)
      {
         double volGrowth = (lastBlockVol - firstBlockVol) / firstBlockVol;
         double volScore  = 10.0 * MathMax(0.0, MathMin(1.0, volGrowth / 0.5));
         quality += volScore;
      }
      
      // ── Body expansion (0→10, continuous) ──
      // Scales linearly: 0 pts at no growth, full 10 pts at ≥50% growth.
      if(firstBlockBody != EMPTY_VALUE &&
         lastBlockBody != EMPTY_VALUE  &&
         firstBlockBody > 0.0)
      {
         double bodyGrowth = (lastBlockBody - firstBlockBody) / firstBlockBody;
         double bodyScore  = 10.0 * MathMax(0.0, MathMin(1.0, bodyGrowth / 0.5));
         quality += bodyScore;
      }
    
   // ── Pin alignment (0→8, continuous) ──
   // Scores based on dominance ratio of correct pin direction.
   // Uptrend: lower pins dominate.
   // Downtrend: upper pins dominate.
   
   double upperPin = (avgUpperPin != EMPTY_VALUE ? avgUpperPin : 0.0);
   double lowerPin = (avgLowerPin != EMPTY_VALUE ? avgLowerPin : 0.0);
   
   double pinTotal = upperPin + lowerPin;
   double pinScore = 0.0;
   
   if(pinTotal > 0.0)
   {
      if(latestTrend.channelType == DIR_UP)
      {
         double ratio = (lowerPin / pinTotal - 0.5) / 0.3;
         ratio = MathMax(0.0, MathMin(1.0, ratio));
         pinScore = 8.0 * ratio;
      }
      else if(latestTrend.channelType == DIR_DOWN)
      {
         double ratio = (upperPin / pinTotal - 0.5) / 0.3;
         ratio = MathMax(0.0, MathMin(1.0, ratio));
         pinScore = 8.0 * ratio;
      }
   }
   
   bool pinAligned = (pinScore > 4.0);
   
   quality += pinScore;
   
     // ── Contradictions penalty (−5 each) ──
     if ((latestTrend.channelType == DIR_UP && trendDelta < 0) || (latestTrend.channelType == DIR_DOWN && trendDelta > 0)) {
      contradictions += 1;
     }
         
     if (latestTrend.channelType == DIR_UP && firstBlockVol != EMPTY_VALUE && lastBlockVol != EMPTY_VALUE && lastBlockVol < firstBlockVol) {
      contradictions += 1;
     }
         
     quality -= (contradictions * 5.0);
      // ── Perfect alignment bonus (+5) ──
     if (deltaConsistent && pinAligned && contradictions == 0) {
         quality += 5.0  ;
     }
         
    quality = MathMax(0, MathMin(100, quality));
    string confidenceLevel = quality >= 80 ? "HIGH" : quality >= 60 ? "MEDIUM" : "LOW";
    string strengthRating = MathAbs(latestTrend.angleDeg) > 45 ? "VERY STRONG" : MathAbs(latestTrend.angleDeg) > 30 ? "STRONG" : MathAbs(latestTrend.angleDeg) > 15 ? "MODERATE" : "WEAK";

   
    if (_Symbol == symbol && _Period == tf) {
      RemoveAllChannels();
      DrawAllChannels(projLenCh, C'0,230,230', C'180,40,220', clrGray, 2, STYLE_SOLID, true, trendChannels);
    }


    TrendContext trendContext = AnalyzeTrendContext(trendChannels,quality);
    if (verboseLogging) {
        PrintTrendContext(trendContext);
    }
    
    // Check divergence
    bool hasDivergence = (latestTrend.channelType == DIR_UP && trendDelta < 0) || (latestTrend.channelType == DIR_DOWN && trendDelta > 0);
    
    analysis += "In the broader timeframe, the market is in "+ChannelTypeToString(trendContext.currentType)+" with "+trendContext.strengthRating+" strength and "+trendContext.confidenceLevel+" quality ("+DoubleToString(trendContext.qualityScore,0)+").";
    
    // Part 3: Block structure pattern
    analysis += " The price structure shows ";
    if (trendContext.currentType == DIR_UP) {
      analysis += "Higher Highs / Higher Lows.";
    } else if(trendContext.currentType == DIR_DOWN) {
      analysis += "Lower Highs / Lower Lows.";
    } else {
      analysis += "a mixed pattern with no clear direction.";
    }
    
    string analysisp2 = "";
    // Composite candle vs previous block
    if (g_composite.blockRelation != "NORMAL" && g_composite.blockRelation != "") {
      analysisp2 += "The current block ";
      if (g_composite.blockRelation == "ENGULFING") {
         analysisp2 += "completely encompasses the previous block, indicating increased power in current direction.";
      }
      if (g_composite.blockRelation == "INSIDE") {
         analysisp2 += "is completely within the previous block range, indicating reduced volatility and potential accumulation.";
      }
      if (g_composite.blockRelation == "OUTSIDE") {
         analysisp2 += "exceeds the previous block range, indicating increased volatility and market strength.";
      }
    }
    
    // Part 4: Volume analysis - CRITICAL
    if (hasDivergence) {
      analysisp2 += "However, an important contradiction exists: while price moves ";
      if (trendContext.currentType == DIR_UP) {
         analysisp2 += "upward";
      } else if (trendContext.currentType == DIR_DOWN) {
         analysisp2 += "downward";
      }
      analysisp2 += ", volume shows ";
      if (trendDelta < 0) {
         analysisp2 += "selling dominance with "+DoubleToString(MathAbs(trendDeltaPct),0)+"%. This divergence between price direction and volume flow indicates sellers are active despite price rise.";
      } else {
         analysisp2 += "buying dominance with "+DoubleToString(MathAbs(trendDeltaPct),0)+"%. This divergence between price direction and volume flow indicates buyers are accumulating despite price decline.";
      }
    } else {
      analysisp2 += "Volume also confirms this trend, with ";
      if (trendDelta > 0) {
         analysisp2 += "buyers dominance with "+DoubleToString(MathAbs(trendDeltaPct),0)+"%.";
      } else if (trendDelta < 0) {
         analysisp2 += "sellers dominance with "+DoubleToString(MathAbs(trendDeltaPct),0)+"%.";
      } else {
         analysisp2 += "a balanced market with no dominant side.";
      }
    }
    
    // Volume momentum
    analysisp2 += " Volume momentum is "+volMom+", indicating ";
    if (StringFind(volMom, "INCREASING") != -1) {
      analysisp2 += "increased market participation.";
    } else {
      analysisp2 += "decreased market participation.";
    }

    
    // Part 5: Momentum signals (pins & bodies)
    string analysisp3 = "";
    analysisp3 += "Candle bodies are "+bodyStatus;
    if (bodyStatus == "EXPANDING"){
      analysisp3 += ", indicating increasing power and momentum.";
    } else if (bodyStatus == "CONTRACTING") {
      analysisp3 += ", which may indicate weakening trend strength.";
    }
    
    // Pin analysis
    if(MathAbs(upperPinChg) > 15 || MathAbs(lowerPinChg) > 15) {
      if (upperPinChg > 15) {
         analysisp3 += " Upper wicks have increased by "+DoubleToString(upperPinChg,2)+"%, indicating selling pressure at higher levels.";
      }
      if (upperPinChg < -15) {
         analysisp3 += " Upper wicks have decreased by "+DoubleToString(MathAbs(upperPinChg),2)+"%, which may indicate weakening resistance.";
      }
      if (lowerPinChg > 15) {
         analysisp3 += " Lower wicks have increased by "+DoubleToString(lowerPinChg,2)+"%, indicating buying support strengthening.";
      }
      if (lowerPinChg < -15) {
         analysisp3 += " Lower wicks have decreased by "+DoubleToString(MathAbs(lowerPinChg),2)+"%, which may indicate weakening support.";
      }
    }
    
   
    
    // Part 6: Position within channel
    string analysisp4 = "";
    if (channelPos != EMPTY_VALUE) {
      analysisp4 += "Price is positioned in the ";
      if (channelPos > 66.67) {
         analysisp4 += "UPPER ZONE";
      } else if (channelPos < 33.33) {
         analysisp4 += "LOWER ZONE";
      } else {
         analysisp4 += "MIDDLE ZONE";
      }
      analysisp4 += " ("+DoubleToString(channelPos,2)+"% of the channel)";
    }
    
    if (posStatus == "OVERBOUGHT" || posStatus == "OVERSOLD") {
      analysisp4 += "in "+posStatus+" zone";
    }
    analysisp4 += ".";
    

    
    // Part 7: Final assessment
    string analysisp5 = "Overall, ";
    if (contradictions > 0 || hasDivergence) {
      analysisp5 += "despite "+IntegerToString(contradictions)+" technical contradictions, the overall pattern maintains ";
      if(trendContext.currentType == DIR_UP) {
         analysisp5 += "UPTREND ";
      } else if (trendContext.currentType == DIR_DOWN){
         analysisp5 += "DOWNTREND ";
      } else {
         analysisp5 += "CONSOLIDATION ";
      }
      analysisp5 += "characteristics, but these contradictions suggest potential change in market behavior.";
      
    } else {
      analysisp5 += "all technical and volume indicators are aligned confirming ";
      if(trendContext.currentType == DIR_UP) {
         analysisp5 += "UPTREND characteristics ";
      } else if (trendContext.currentType == DIR_DOWN){
         analysisp5 += "DOWNTREND characteristics ";
      } else {
         analysisp5 += "a consolidation phase and has not yet selected a clear direction";
      }
      analysisp5 += ".";
    }
  
      // Part 8: MSB
      
     MarketStructureBreak msb = DetectMarketStructureBreak(symbol,tf,10);
     string analysisp6 = "The last MSB is ";
     if (msb.bullish) {
      analysisp6 += "BULLISH";
     } else {
      analysisp6 += "BEARISH";
     }
     analysisp6 += IntegerToString(msb.barsAgo)+" bars ago.";


     PrintVerbose(analysis);
     PrintVerbose(analysisp2);
     PrintVerbose(analysisp3);
     PrintVerbose(analysisp4);
     PrintVerbose(analysisp5);
     
     string totalAnalysis = analysis+analysisp2+analysisp3+analysisp4+analysisp5+analysisp6;
     
     if (_Symbol == symbol && _Period == tf) {
         UpdatePanel(trendContext, volMom, bodyStatus, cb, trendDelta,trendDeltaPct, posStatus, channelPos, upperPinChg, lowerPinChg,g_composite, totalAnalysis, msb);
     }
     
    ArrayResize(stf.analyticsData, ArraySize(analyticsData));
    ArrayCopy(stf.analyticsData, analyticsData);
    stf.currentBarAnalysis = cb; 
    stf.compositeAnalysis = g_composite;
    ArrayResize(stf.trendChannels, ArraySize(trendChannels));
    ArrayCopy(stf.trendChannels, trendChannels);
    
    stf.msbInfo = msb;

     
     if(adx > 20 && rsi < 70 && rsi > 30 && !hasDivergence && contradictions == 0 && trendContext.qualityScore > 80 && (trendContext.strengthRating == "VERY_STRONG" || trendContext.strengthRating == "STRONG"  ) && StringFind(volMom, "INCREASING") != -1 && bodyStatus == "EXPANDING") {
         if (trendContext.currentType == DIR_UP) {
            if (trendDelta > 0 && posStatus == "OVERSOLD" && (cb.patternBias == "BULLISH" && g_composite.compositeBias == "BULLISH" && g_composite.blockRelationBias == "BULLISH" ) && msb.bullish ) {
               Print(symbol+" - "+StringFromTF(tf)+"===> BUY SETUP");
               if (_Symbol== symbol && _Period == tf) {
                  DrawSignal(true,0);
               }
               
               stf.buyGrid = new GridManager(symbol,GRID_BUY,0.1,50,0.08,20);
               stf.buyGrid.SetGridMagicNumber(MagicBuy);
               stf.buyGrid.SetGridMultiplier(1);
               stf.buyGrid.Start();
               
            }
         }
         if (trendContext.currentType == DIR_DOWN) {
            if (trendDelta < 0 && posStatus == "OVERBOUGHT" && (cb.patternBias == "BEARISH" && g_composite.compositeBias == "BEARISH" && g_composite.blockRelationBias == "BEARISH" ) && !msb.bullish) {
               Print(symbol+" - "+StringFromTF(tf)+"===> SELL SETUP");
               if (_Symbol== symbol && _Period == tf) {
                  DrawSignal(false,0);
               }

               stf.sellGrid = new GridManager(symbol,GRID_SELL,0.1,50,0.08,20);
               stf.sellGrid.SetGridMagicNumber(MagicSell);
               stf.sellGrid.SetGridMultiplier(1);
               stf.sellGrid.Start();
               

            }
         }
     }
   
}


//+------------------------------------------------------------------+
//| Check Pivot High                                                 |
//+------------------------------------------------------------------+
bool IsPivotHigh(string symbol, ENUM_TIMEFRAMES tf, int shift, int pivotLen)
{
   double h = iHigh(symbol, tf, shift);

   for(int i = 1; i <= pivotLen; i++)
   {
      if(iHigh(symbol,tf,shift+i) >= h) return false;
      if(iHigh(symbol,tf,shift-i) >  h) return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Check Pivot Low                                                  |
//+------------------------------------------------------------------+
bool IsPivotLow(string symbol, ENUM_TIMEFRAMES tf, int shift, int pivotLen)
{
   double l = iLow(symbol, tf, shift);

   for(int i = 1; i <= pivotLen; i++)
   {
      if(iLow(symbol,tf,shift+i) <= l) return false;
      if(iLow(symbol,tf,shift-i) <  l) return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Detect Latest Market Structure Break                             |
//+------------------------------------------------------------------+
MarketStructureBreak DetectMarketStructureBreak(string symbol, ENUM_TIMEFRAMES tf, int pivotLen = 5)
{
   MarketStructureBreak msb;
   msb.valid   = false;
   msb.bullish = false;
   msb.barsAgo = -1;
   msb.level   = 0.0;
   msb.time    = 0;

   int bars = Bars(symbol,tf);
   if(bars < pivotLen*2+10)
      return msb;

   double lastSwingHigh = -DBL_MAX;
   double lastSwingLow  = DBL_MAX;

   int lastHighShift = -1;
   int lastLowShift  = -1;

   // 1️⃣ Find most recent pivot high & low
   for(int i = pivotLen+1; i < bars-pivotLen; i++)
   {
      if(lastHighShift == -1 && IsPivotHigh(symbol, tf, i,pivotLen))
      {
         lastSwingHigh = iHigh(symbol,tf,i);
         lastHighShift = i;
      }

      if(lastLowShift == -1 && IsPivotLow(symbol,tf,i,pivotLen))
      {
         lastSwingLow = iLow(symbol,tf,i);
         lastLowShift = i;
      }

      if(lastHighShift != -1 && lastLowShift != -1)
         break;
   }

   if(lastHighShift == -1 || lastLowShift == -1)
      return msb;

   // 2️⃣ Scan forward to detect break
   for(int i = 0; i < MathMin(lastHighShift,lastLowShift); i++)
   {
      double closePrice = iClose(symbol,tf,i);

      // Bullish BOS
      if(closePrice > lastSwingHigh)
      {
         msb.valid   = true;
         msb.bullish = true;
         msb.barsAgo = i;
         msb.level   = lastSwingHigh;
         msb.time    = iTime(symbol,tf,i);
         return msb;
      }

      // Bearish BOS
      if(closePrice < lastSwingLow)
      {
         msb.valid   = true;
         msb.bullish = false;
         msb.barsAgo = i;
         msb.level   = lastSwingLow;
         msb.time    = iTime(symbol,tf,i);
         return msb;
      }
   }

   return msb;
}

//+------------------------------------------------------------------+
//| Draw Fancy Buy/Sell Signal                                      |
//| isBuy      = true -> BUY, false -> SELL                         |
//| barIndex   = shift (0=current, 1=closed bar, etc.)              |
//| text       = optional custom text                               |
//+------------------------------------------------------------------+
void DrawSignal(bool isBuy, int barIndex, string text = "")
{
   string prefix = isBuy ? "TMD_BUY_" : "TMD_SELL_";
   datetime t = iTime(_Symbol, _Period, barIndex);
   string name = prefix + IntegerToString((long)t);

   // Avoid duplicates
   if(ObjectFind(0, name) >= 0)
      return;


   double price;

   if(isBuy)
      price = iLow(_Symbol, _Period, barIndex) - (10 * _Point);
   else
      price = iHigh(_Symbol, _Period, barIndex) + (10 * _Point);

   // --- Arrow ---
   ObjectCreate(0, name, OBJ_ARROW, 0, t, price);
   ObjectSetInteger(0, name, OBJPROP_ARROWCODE, isBuy ? 233 : 234); // Wingdings arrows
   ObjectSetInteger(0, name, OBJPROP_COLOR, isBuy ? tmdGreen : tmdRed);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);

   // --- Glow Circle (background effect) ---
   string glow = name + "_glow";
   ObjectCreate(0, glow, OBJ_ARROW, 0, t, price);
   ObjectSetInteger(0, glow, OBJPROP_ARROWCODE, 159); // Circle
   ObjectSetInteger(0, glow, OBJPROP_COLOR, isBuy ? tmdGreen : tmdRed);
   ObjectSetInteger(0, glow, OBJPROP_WIDTH, 4);
   ObjectSetInteger(0, glow, OBJPROP_BACK, true);

   // --- Optional Text ---
   if(text != "")
   {
      string label = name + "_txt";
      ObjectCreate(0, label, OBJ_TEXT, 0, t, price);
      ObjectSetString(0, label, OBJPROP_TEXT, text);
      ObjectSetInteger(0, label, OBJPROP_COLOR, isBuy ? tmdGreen : tmdRed);
      ObjectSetInteger(0, label, OBJPROP_FONTSIZE, 10);
      ObjectSetString(0, label, OBJPROP_FONT, "Arial Bold");
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
  
  int PriceToPoints(double priceDiff, string symbol)
{
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(point <= 0.0)
      return 0;

   return (int)MathRound(priceDiff / point);
}