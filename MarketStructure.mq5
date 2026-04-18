//+------------------------------------------------------------------+
//|                                              MarketStructure.mq5 |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>

#property tester_file "market_structure.onnx"

struct OnnxProbability {
   long  labels[4]; 
   float values[4]; 
};

input group "AI Configuration"
input string    InpModelName      = "market_structure.onnx";
input double    InpThreshold      = 0.65; 
input int       InpWindowSize     = 5;

input group "Strategy Settings"
input double    InpLotSize        = 0.1;
input double    InpFibLevel       = 0.618;
input double    InpRR             = 2.0;
input int       InpMagic          = 888888;
input int       InpExpireHours    = 4;    

input group "Trailing Settings"
input double    InpTrailingStepRR = 0.8; 

//--- Global Variables
long      m_onnx_handle = INVALID_HANDLE;
int       h_atr, h_ma_trend;
CTrade    m_trade;
static    double s_currentLot = 0.0;

#define NUM_FEATURES 6

//+------------------------------------------------------------------+
int OnInit() {
   m_onnx_handle = OnnxCreate(InpModelName, ONNX_DEFAULT);
   if(m_onnx_handle == INVALID_HANDLE) return(INIT_FAILED);
Print("ONNX File loaded");
   h_atr = iATR(_Symbol, _Period, 14);
   h_ma_trend = iMA(_Symbol, _Period, 50, 0, MODE_SMA, PRICE_CLOSE);

   long input_shape[] = {1, NUM_FEATURES};
   OnnxSetInputShape(m_onnx_handle, 0, input_shape);
   
   long shape_label[] = {1}, shape_probs[] = {1}; 
   OnnxSetOutputShape(m_onnx_handle, 0, shape_label);
   OnnxSetOutputShape(m_onnx_handle, 1, shape_probs);
   s_currentLot = InpLotSize;
   m_trade.SetExpertMagicNumber(InpMagic);
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) {
   if(m_onnx_handle != INVALID_HANDLE) OnnxRelease(m_onnx_handle);
   IndicatorRelease(h_atr);
   ObjectDelete(0, "MarketStructure");
}

void OnTick() {
   ApplyTrailingRR();
   CheckAndCleanFibo();

   static datetime last_bar = 0;
   datetime current_bar = iTime(_Symbol, _Period, 0);
   if(last_bar == current_bar) return;
   last_bar = current_bar;

   if(PositionsTotal() > 0 || CountPendingOrders() > 0) return; 

   float inputs[NUM_FEATURES];
   if(!CalculateFeatures(inputs)) return;

   long predicted_label[1]; OnnxProbability prob_data[1];
   if(!OnnxRun(m_onnx_handle, ONNX_NO_CONVERSION, inputs, predicted_label, prob_data)) return;

   int signal = (int)predicted_label[0];
   float confidence = prob_data[0].values[signal];

   if(confidence < InpThreshold) return;

   double ma_val[1];
   CopyBuffer(h_ma_trend, 0, 1, 1, ma_val); 
   bool is_bullish = SymbolInfoDouble(_Symbol, SYMBOL_BID) > ma_val[0];

   if((signal == 3 || signal == 2) && is_bullish) {
       ExecutePendingFibo(ORDER_TYPE_BUY_LIMIT);
   }
   else if((signal == 1 || signal == 0) && !is_bullish) {
       ExecutePendingFibo(ORDER_TYPE_SELL_LIMIT);
   }
}

double GetLastPivot(int type, int count_back) {
    int found = 0;
    for(int i = 5; i < 100; i++) {
        bool is_pivot = true;
        for(int j = i-5; j <= i+5; j++) {
            if(type == 1) {
                if(iHigh(_Symbol, _Period, i) < iHigh(_Symbol, _Period, j)) { is_pivot = false; break; }
            } else {
                if(iLow(_Symbol, _Period, i) > iLow(_Symbol, _Period, j)) { is_pivot = false; break; }
            }
        }
        if(is_pivot) {
            found++;
            if(found == count_back) return (type == 1) ? iHigh(_Symbol, _Period, i) : iLow(_Symbol, _Period, i);
        }
    }
    return 0;
}
//+------------------------------------------------------------------+
//| FITUR: TRAILING RR                                               |
//+------------------------------------------------------------------+
void ApplyTrailingRR() {
   for(int i = PositionsTotal() - 1; i >= 0; i--) {

      ulong ticket = PositionGetTicket(i);
      
      if(PositionSelectByTicket(ticket)) {
         
         if(PositionGetInteger(POSITION_MAGIC) == InpMagic && PositionGetString(POSITION_SYMBOL) == _Symbol) {
            
            double open  = PositionGetDouble(POSITION_PRICE_OPEN);
            double sl    = PositionGetDouble(POSITION_SL);
            double tp    = PositionGetDouble(POSITION_TP);
            long type    = PositionGetInteger(POSITION_TYPE);
            double price = (type == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);

            double full_dist = MathAbs(tp - open);
            if(full_dist <= 0) continue;

            double trigger_price_dist = full_dist * InpTrailingStepRR;
            double current_profit_dist = MathAbs(price - open);

            if(current_profit_dist >= trigger_price_dist) {
               double new_sl = 0;
               double buffer = 30 * _Point;

               if(type == POSITION_TYPE_BUY) {
                  new_sl = NormalizeDouble(open + (current_profit_dist * 0.3), _Digits);
                  if(new_sl > sl + _Point || sl == 0) {
                     m_trade.PositionModify(ticket, new_sl, tp);
                  }
               } 
               else if(type == POSITION_TYPE_SELL) {
                  new_sl = NormalizeDouble(open - (current_profit_dist * 0.3), _Digits);
                  if(new_sl < sl - _Point || sl == 0) {
                     m_trade.PositionModify(ticket, new_sl, tp);
                  }
               }
            }
         }
      }
   }
}

void CheckAndCleanFibo() {
   if(PositionsTotal() == 0 && CountPendingOrders() == 0) {
      if(ObjectFind(0, "MarketStructure") >= 0) {
         ObjectDelete(0, "MarketStructure");
      }
   }
}

void ExecutePendingFibo(ENUM_ORDER_TYPE type) {

    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);    

    if (s_currentLot > maxLot)
    {
        s_currentLot = maxLot;        
        return;
    }

    if (s_currentLot < minLot)
    {        
        return;
    }
    
    int ratio=(int)MathRound(s_currentLot/lotStep);
    if(MathAbs(ratio*lotStep-s_currentLot)>0.0000001)
    {          
     return;
    }  

    double p_high = GetLastPivot(1, 1);
    double p_low  = GetLastPivot(2, 1);
    
    if(p_high == 0 || p_low == 0) return;
    double range = p_high - p_low;

    double entry = 0, sl = 0, tp = 0;
    datetime expire = TimeCurrent() + InpExpireHours * 3600;

    if(type == ORDER_TYPE_BUY_LIMIT) {
        entry = NormalizeDouble(p_high - (range * InpFibLevel), _Digits);
        sl = NormalizeDouble(p_low - (15 * _Point), _Digits); 
        tp = NormalizeDouble(entry + (entry - sl) * InpRR, _Digits);
        
        if(entry < SymbolInfoDouble(_Symbol, SYMBOL_ASK)) {
            if(m_trade.BuyLimit(s_currentLot, entry, _Symbol, sl, tp, ORDER_TIME_SPECIFIED, expire, "MarketStructure Buy")) {
                DrawFibo(p_low, p_high);
            }
        }
    } 
    else if(type == ORDER_TYPE_SELL_LIMIT) {
        entry = NormalizeDouble(p_low + (range * InpFibLevel), _Digits);
        sl = NormalizeDouble(p_high + (15 * _Point), _Digits);
        tp = NormalizeDouble(entry - (sl - entry) * InpRR, _Digits);
        
        if(entry > SymbolInfoDouble(_Symbol, SYMBOL_BID)) {
            if(m_trade.SellLimit(s_currentLot, entry, _Symbol, sl, tp, ORDER_TIME_SPECIFIED, expire, "MarketStructure Sell")) {               
                DrawFibo(p_high, p_low);
            }
        }
    }
}

void DeleteAllPendingOrders() {
   for(int i = OrdersTotal() - 1; i >= 0; i--) {
      ulong t = OrderGetTicket(i);
      if(OrderSelect(t) && OrderGetInteger(ORDER_MAGIC) == InpMagic) m_trade.OrderDelete(t);
   }
}

double GetATR(int period) {
   double atr_buffer[];
   ArraySetAsSeries(atr_buffer, true);
   if(CopyBuffer(h_atr, 0, 1, 1, atr_buffer) > 0) {
      return atr_buffer[0];
   }
   return _Point;
}

double GetAvgVolume(int period) {
   long vol_buffer[];
   ArraySetAsSeries(vol_buffer, true);
   if(CopyTickVolume(_Symbol, _Period, 1, period, vol_buffer) > 0) {
      double sum = 0;
      for(int i=0; i<period; i++) sum += (double)vol_buffer[i];
      return sum / period;
   }
   return 1.0;
}

bool CalculateFeatures(float &f[]) {
   if(ArrayResize(f, 6) != 6) return false;
   
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
  
   if(CopyRates(_Symbol, _Period, 1, 60, rates) < 60) return false; 
   
   double close_price = rates[0].close;
   double open_price  = rates[0].open;
   
   double atr_val     = GetATR(14);
   double avg_vol     = GetAvgVolume(20);

   double safe_atr = (atr_val > 0) ? atr_val : _Point;
   double safe_vol = (avg_vol > 0) ? avg_vol : 1.0;

   f[0] = (float)((close_price - rates[5].close) / safe_atr);
   
   int hi_idx = iHighest(_Symbol, _Period, MODE_HIGH, 50, 1);
   f[1] = (float)((iHigh(_Symbol, _Period, hi_idx) - close_price) / safe_atr);
   
   int lo_idx = iLowest(_Symbol, _Period, MODE_LOW, 50, 1);
   f[2] = (float)((close_price - iLow(_Symbol, _Period, lo_idx)) / safe_atr);
   
   f[3] = (float)((double)rates[0].tick_volume / safe_vol);
   
   f[4] = (float)((close_price - open_price) / safe_atr);
   
   MqlDateTime dt; 
   TimeToStruct(rates[0].time, dt); 
   f[5] = (float)dt.hour;

   return true;
}

void DrawFibo(double p_start, double p_end) {
   string name = "MarketStructure";
   ObjectDelete(0, name);
   if(ObjectCreate(0, name, OBJ_FIBO, 0, TimeCurrent(), p_start, TimeCurrent(), p_end)) {
      ObjectSetInteger(0, name, OBJPROP_COLOR, clrDodgerBlue);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
      ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, true);
   }
}

int CountPendingOrders() {
   int count = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--) {
      ulong t = OrderGetTicket(i);
      if(OrderSelect(t) && OrderGetInteger(ORDER_MAGIC) == InpMagic) {
         count++;
      }
   }
   return count;
}