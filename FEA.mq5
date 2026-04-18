//+------------------------------------------------------------------+
//|                                                  MultiTFFractal.mq5
//|  Multi-Timeframe Fractal Trend EA                                |
//|  - Detects fractal breaks on a higher timeframe (HTF)            |
//|  - Enters on a lower timeframe (LTF) in direction of HTF trend   |
//|  - Configurable money management, SL/TP, EMA filter, trailing     |
//+------------------------------------------------------------------+
#property copyright "Assistant"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

//--- input parameters
input ENUM_TIMEFRAMES HTF = PERIOD_H1;        // Higher timeframe for fractal break (trend)
input ENUM_TIMEFRAMES LTF = PERIOD_M15;       // Lower timeframe for entries
input int HTF_lookback_bars = 50;             // How many HTF bars to scan for latest fractal
input int LTF_lookback_bars = 50;             // How many LTF bars to use for local checks

input double RiskPercent = 1.0;               // Risk percent of equity per trade (0 = disabled)
input double FixedLots = 0.0;                 // Fixed lot size if > 0 (overrides risk)
input double StopLossBufferPoints = 10;       // Extra buffer in points beyond fractal for SL
input double TakeProfitRR = 2.0;              // Take Profit as Risk Reward ratio (if >0)
input double TakeProfitPips = 0.0;            // Or fixed TP in pips (if >0 takes precedence)
input bool UseEMATrendFilter = true;          // Use EMA on LTF to filter entries
input int EMA_period = 50;                    // EMA period on LTF
input int MinConfirmationBars = 1;            // Number of closed LTF bars after signal to enter

input int MagicNumber = 20250501;
input double MaxSpreadPoints = 50;            // Max allowed spread in points
input double SlippagePoints = 30;             // Slippage in points allowed
input bool AllowBuy = true;
input bool AllowSell = true;

input bool UseTrailing = true;
input int TrailingStartPoints = 200;
input int TrailingStepPoints = 50;

//--- global helpers
string Symbol_ = "";
int ema_handle = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Symbol_ = _Symbol;
   ema_handle = iMA(Symbol_, LTF, EMA_period, 0, MODE_EMA, PRICE_CLOSE); // note: 6 params -> returns handle
   if(ema_handle == INVALID_HANDLE)
   {
      Print("Failed to create EMA handle. Error=", GetLastError());
      return INIT_FAILED;
   }
   PrintFormat("MultiTF Fractal EA initialized on %s. HTF=%s LTF=%s", Symbol_, EnumToString(HTF), EnumToString(LTF));
   return(INIT_SUCCEEDED);
}
double ReadEMA(int shift)
{
   if(ema_handle == INVALID_HANDLE) return 0.0;
   double buf[];
   // read 1 value starting at `shift`
   if(CopyBuffer(ema_handle, 0, shift, 1, buf) <= 0)
   {
      PrintFormat("CopyBuffer failed (err=%d)", GetLastError());
      return 0.0;
   }
   return buf[0];
}
//+------------------------------------------------------------------+
//| Find the last confirmed fractal on a given timeframe             |
//| fractal_type: 1 = bullish fractal (low), -1 = bearish fractal (high) |
//| returns: price of fractal (high for bearish, low for bullish) and bar index (shift) |
//+------------------------------------------------------------------+
bool GetLastFractal(ENUM_TIMEFRAMES tf, int lookback, int fractal_type, double &price, int &shift_out)
{
   // We'll copy enough bars
   MqlRates rates[];
   if(CopyRates(Symbol_, tf, 0, lookback+5, rates) <= 0)
      return false;
   // rates[0] most recent
   // We search for confirmed fractal: at bar i (i >=2): for bullish fractal low: low[i] < low[i-1..i+2]
   // For bearish fractal high: high[i] > high[i-1..i+2]
   for(int i = 2; i < ArraySize(rates)-2; i++)
   {
      bool is_fractal = true;
      if(fractal_type == 1) // bullish (down) fractal (local low)
      {
         double v = rates[i].low;
         if(!(v < rates[i-1].low && v < rates[i-2].low && v < rates[i+1].low && v < rates[i+2].low)) is_fractal = false;
         if(is_fractal)
         {
            price = v;
            shift_out = i;
            return true;
         }
      }
      else if(fractal_type == -1) // bearish (up) fractal (local high)
      {
         double v = rates[i].high;
         if(!(v > rates[i-1].high && v > rates[i-2].high && v > rates[i+1].high && v > rates[i+2].high)) is_fractal = false;
         if(is_fractal)
         {
            price = v;
            shift_out = i;
            return true;
         }
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Check whether HTF fractal has been broken (price beyond fractal) |
//| For bullish: price close > fractal high (break up).               |
//| For bearish: price close < fractal low  (break down).            |
//+------------------------------------------------------------------+
bool IsFractalBroken(ENUM_TIMEFRAMES tf, int fractal_type, double fractal_price)
{
   // get latest close price on that timeframe
   MqlRates rates[];
   if(CopyRates(Symbol_, tf, 0, 2, rates) <= 0) return false;
   double last_close = rates[0].close;
   if(fractal_type == -1) // bearish fractal (high) broken upward?
   {
      // break bullish if last_close > fractal_price
      return (last_close > fractal_price);
   }
   else // bullish fractal (low) broken downward?
   {
      // break bearish if last_close < fractal_price
      return (last_close < fractal_price);
   }
}

//+------------------------------------------------------------------+
//| Calculate lot size based on risk percent and stop loss distance  |
//+------------------------------------------------------------------+
double CalculateLotSize(double stoploss_price)
{
   if(FixedLots > 0.0) return(NormalizeDouble(FixedLots, 2));
   if(RiskPercent <= 0.0) return(0.01); // default minimal
   // For FX pairs - useful approx: risk in account currency calculation using SymbolInfoDouble
   double tick_value = SymbolInfoDouble(Symbol_, SYMBOL_TRADE_TICK_VALUE);
   double tick_size  = SymbolInfoDouble(Symbol_, SYMBOL_TRADE_TICK_SIZE);
   double point      = SymbolInfoDouble(Symbol_, SYMBOL_POINT);
   double price = SymbolInfoDouble(Symbol_, SYMBOL_BID);
   if(tick_value == 0 || tick_size == 0) // fallback
      tick_value = 0.0001;
   double distance_points = MathAbs(price - stoploss_price) / point;
   if(distance_points <= 0) distance_points = 1;
   double risk_amount = AccountInfoDouble(ACCOUNT_BALANCE) * (RiskPercent/100.0);
   // approximate lot calculation:
   double value_per_point_per_lot = tick_value / tick_size; // approximate
   double lots = risk_amount / (distance_points * value_per_point_per_lot);
   // Normalize to lot step and min/max
   double lot_step = SymbolInfoDouble(Symbol_, SYMBOL_VOLUME_STEP);
   double min_lot  = SymbolInfoDouble(Symbol_, SYMBOL_VOLUME_MIN);
   double max_lot  = SymbolInfoDouble(Symbol_, SYMBOL_VOLUME_MAX);
   if(lot_step <= 0) lot_step = 0.01;
   lots = MathMax(min_lot, MathMin(max_lot, lots));
   // adjust to step
   double steps = MathFloor(lots / lot_step);
   lots = steps * lot_step;
   if(lots < min_lot) lots = min_lot;
   return(NormalizeDouble(lots, (int) MathMax(0, MathRound(-MathLog10(lot_step)))));
}

//+------------------------------------------------------------------+
//| Simple EMA on LTF                                                |
//+------------------------------------------------------------------+
double GetEMA_LTF(int period, int shift)
{
   double ema[];
   if(CopyBuffer(iMA(Symbol_, LTF, period, 0, MODE_EMA, PRICE_CLOSE), 0, shift, 1, ema) <= 0)
      return 0.0;
   return ema[0];
}

//+------------------------------------------------------------------+
//| Count existing positions of symbol & magic by direction          |
//+------------------------------------------------------------------+
int CountPositions(int direction) // 1=BUY, -1=SELL, 0=all
{
   int cnt = 0;
   for(int i=0;i<PositionsTotal();i++)
   {
      if(PositionSelectByTicket(PositionGetTicket(i)))
      {
         if(PositionGetString(POSITION_SYMBOL) != Symbol_) continue;
         if((int)PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
         long pos_type = PositionGetInteger(POSITION_TYPE);
         if(direction == 0) cnt++;
         else if(direction==1 && pos_type==POSITION_TYPE_BUY) cnt++;
         else if(direction==-1 && pos_type==POSITION_TYPE_SELL) cnt++;
      }
   }
   return cnt;
}

//+------------------------------------------------------------------+
//| Close opposite positions (optional)                              |
//+------------------------------------------------------------------+
void CloseOppositeIfNeeded(int desiredDirection)
{
   for(int i = PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != Symbol_) continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      long pos_type = PositionGetInteger(POSITION_TYPE);
      if(desiredDirection==1 && pos_type==POSITION_TYPE_SELL) // close sells
      {
         trade.PositionClose(ticket, SlippagePoints * _Point);
      }
      else if(desiredDirection==-1 && pos_type==POSITION_TYPE_BUY) // close buys
      {
         trade.PositionClose(ticket, SlippagePoints * _Point);
      }
   }
}

//+------------------------------------------------------------------+
//| Entry logic executed on each tick                                |
//+------------------------------------------------------------------+
void CheckForEntries()
{
   // 1) find last HTF fractal (both directions)
   double htf_bull_price=0, htf_bear_price=0;
   int shift_bull = -1, shift_bear = -1;
   bool foundBull = GetLastFractal(HTF, HTF_lookback_bars, 1, htf_bull_price, shift_bull);   // bullish fractal (low)
   bool foundBear = GetLastFractal(HTF, HTF_lookback_bars, -1, htf_bear_price, shift_bear);   // bearish fractal (high)

   // 2) check whether either was broken (gives dominant bias)
   bool bullBroken = false, bearBroken = false;
   if(foundBear)
      bullBroken = IsFractalBroken(HTF, -1, htf_bear_price); // bear fractal (high) broken upwards -> bullish bias
   if(foundBull)
      bearBroken = IsFractalBroken(HTF, 1, htf_bull_price);  // bull fractal (low) broken downwards -> bearish bias

   int htfBias = 0; // 1 bullish, -1 bearish, 0 none
   double htfRefPrice = 0.0;
   if(bullBroken && !bearBroken) { htfBias = 1; htfRefPrice = htf_bear_price; }
   else if(bearBroken && !bullBroken) { htfBias = -1; htfRefPrice = htf_bull_price; }
   else
   {
      // nothing clear
      return;
   }

   // 3) Basic spread filter
   double spread_points = (SymbolInfoDouble(Symbol_, SYMBOL_ASK) - SymbolInfoDouble(Symbol_, SYMBOL_BID)) / SymbolInfoDouble(Symbol_, SYMBOL_POINT);
   if(spread_points > MaxSpreadPoints) return;

   // 4) On LTF: decide entry signal
   // We'll check last LTF closed bar and look for a confirming fractal-type or price action:
   MqlRates ltf_rates[];
   if(CopyRates(Symbol_, LTF, 0, LTF_lookback_bars, ltf_rates) <= 0) return;

   // Use EMA trend filter if configured
   double ema_now = 0;
   if(UseEMATrendFilter)
   {
      // compute simple EMA for current bar index 0
      ema_now = ReadEMA(1); // last closed LTF bar
      

   }

   // Define entry conditions:
   // For bullish HTF bias (htfBias==1): look for LTF pullback where recent LTF low is above HTF reference (or price above EMA)
   // For simplicity: require last closed LTF candle close > EMA (if EMA used) and the last LTF bullish fractal (local low) exists recently.
   // We'll search last few LTF bars for a bullish fractal (local low) and ensure price has moved above it again.

   // Search for LTF bullish fractal (local low)
   double ltf_bull_price=0, ltf_bear_price=0;
   int ltf_shift_bull = -1, ltf_shift_bear = -1;
   bool ltfFoundBull = GetLastFractal(LTF, LTF_lookback_bars, 1, ltf_bull_price, ltf_shift_bull);
   bool ltfFoundBear = GetLastFractal(LTF, LTF_lookback_bars, -1, ltf_bear_price, ltf_shift_bear);

   // We'll use last closed LTF bar as confirmation
   double last_close = ltf_rates[0].close;
   double last_open  = ltf_rates[0].open;

   // ensure we only enter on a closed candle (MinConfirmationBars closed)
   static datetime lastEntryBarTime = 0;
   if(ltf_rates[0].time == lastEntryBarTime) // already processed this bar
      return;

   // check signals
   bool enterLong = false;
   bool enterShort = false;
   double sl = 0, tp = 0;

   if(htfBias == 1 && AllowBuy) // bullish
   {
      // optional EMA filter
      if(!UseEMATrendFilter || last_close > ema_now)
      {
         // require LTF bullish fractal exists recently and price has moved back above that fractal low (pullback)
         if(ltfFoundBull)
         {
            // We want the fractal low to be below current price and not too old (shift small)
            if(ltf_shift_bull <= LTF_lookback_bars-2 && ltf_bull_price < last_close)
            {
               // Set SL below the HTF broken fractal low (htfRefPrice) or below LTF fractal low, whichever is lower
               sl = MathMin(htfRefPrice - StopLossBufferPoints * SymbolInfoDouble(Symbol_, SYMBOL_POINT),
                            ltf_bull_price - StopLossBufferPoints * SymbolInfoDouble(Symbol_, SYMBOL_POINT));
               enterLong = true;
            }
         }
      }
   }
   else if(htfBias == -1 && AllowSell) // bearish
   {
      if(!UseEMATrendFilter || last_close < ema_now)
      {
         if(ltfFoundBear)
         {
            if(ltf_shift_bear <= LTF_lookback_bars-2 && ltf_bear_price > last_close)
            {
               // SL above HTF fractal or above LTF fractal
               sl = MathMax(htfRefPrice + StopLossBufferPoints * SymbolInfoDouble(Symbol_, SYMBOL_POINT),
                            ltf_bear_price + StopLossBufferPoints * SymbolInfoDouble(Symbol_, SYMBOL_POINT));
               enterShort = true;
            }
         }
      }
   }

   // avoid multiple entries per same LTF bar
   if(enterLong || enterShort)
   {
      // compute lots
      double lots = CalculateLotSize(sl);
      if(lots <= 0) return;

      // compute TP
      if(TakeProfitPips > 0)
      {
         double pips = TakeProfitPips;
         if(enterLong) tp = SymbolInfoDouble(Symbol_, SYMBOL_BID) + pips * SymbolInfoDouble(Symbol_, SYMBOL_POINT);
         else tp = SymbolInfoDouble(Symbol_, SYMBOL_ASK) - pips * SymbolInfoDouble(Symbol_, SYMBOL_POINT);
      }
      else if(TakeProfitRR > 0 && sl != 0)
      {
         double rr = TakeProfitRR;
         double distance_points = MathAbs((enterLong ? (SymbolInfoDouble(Symbol_, SYMBOL_BID) - sl) : (sl - SymbolInfoDouble(Symbol_, SYMBOL_ASK)))) / SymbolInfoDouble(Symbol_, SYMBOL_POINT);
         double tp_points = distance_points * rr;
         if(enterLong) tp = SymbolInfoDouble(Symbol_, SYMBOL_BID) + tp_points * SymbolInfoDouble(Symbol_, SYMBOL_POINT);
         else tp = SymbolInfoDouble(Symbol_, SYMBOL_ASK) - tp_points * SymbolInfoDouble(Symbol_, SYMBOL_POINT);
      }

      // ensure no existing same direction position
      if((enterLong && CountPositions(1) == 0) || (enterShort && CountPositions(-1) == 0))
      {
         // close opposite if desired
         CloseOppositeIfNeeded(enterLong ? 1 : -1);

         // place market order
         bool ok=false;
         trade.SetExpertMagicNumber(MagicNumber);
         trade.SetDeviationInPoints((int)SlippagePoints);

         if(enterLong)
         {
            double price = SymbolInfoDouble(Symbol_, SYMBOL_ASK);
            double slr=sl, tpr=tp;
            // Normalize SL/TP to digits
            int digits = (int)SymbolInfoInteger(Symbol_, SYMBOL_DIGITS);
            slr = NormalizeDouble(slr, digits);
            if(tpr!=0) tpr = NormalizeDouble(tpr, digits);
            ok = trade.Buy(lots, Symbol_, price, slr, tpr, "MTF Fractal Buy");
            if(ok) lastEntryBarTime = ltf_rates[0].time;
         }
         else if(enterShort)
         {
            double price = SymbolInfoDouble(Symbol_, SYMBOL_BID);
            double slr=sl, tpr=tp;
            int digits = (int)SymbolInfoInteger(Symbol_, SYMBOL_DIGITS);
            slr = NormalizeDouble(slr, digits);
            if(tpr!=0) tpr = NormalizeDouble(tpr, digits);
            ok = trade.Sell(lots, Symbol_, price, slr, tpr, "MTF Fractal Sell");
            if(ok) lastEntryBarTime = ltf_rates[0].time;
         }

         if(ok)
            PrintFormat("Order placed: %s lots=%.2f dir=%s sl=%G tp=%G", Symbol_, lots, (enterLong? "BUY":"SELL"), sl, tp);
         else
            PrintFormat("Order failed: %s (result=%d)", Symbol_, GetLastError());
      }
   }
}

//+------------------------------------------------------------------+
//| Trailing stop handler                                             |
//+------------------------------------------------------------------+
void ManageTrailing()
{
   if(!UseTrailing) return;
   // iterate positions
   for(int i = PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != Symbol_) continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;

      long type = PositionGetInteger(POSITION_TYPE);
      double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
      double current_price = (type==POSITION_TYPE_BUY) ? SymbolInfoDouble(Symbol_, SYMBOL_BID) : SymbolInfoDouble(Symbol_, SYMBOL_ASK);
      double sl = PositionGetDouble(POSITION_SL);
      double profit = PositionGetDouble(POSITION_PROFIT);

      int digits = (int)SymbolInfoInteger(Symbol_, SYMBOL_DIGITS);
      double point = SymbolInfoDouble(Symbol_, SYMBOL_POINT);

      // compute distance in points
      double distance_points = (type==POSITION_TYPE_BUY) ? (current_price - open_price)/point : (open_price - current_price)/point;
      if(distance_points >= TrailingStartPoints)
      {
         // new SL should trail by TrailingStepPoints behind current price
         double new_sl = (type==POSITION_TYPE_BUY) ? (current_price - TrailingStepPoints * point) : (current_price + TrailingStepPoints * point);
         // only modify if it improves previous SL (for buys: new_sl > old_sl)
         if((type==POSITION_TYPE_BUY && new_sl > sl) || (type==POSITION_TYPE_SELL && new_sl < sl))
         {
            trade.PositionModify(ticket, NormalizeDouble(new_sl, digits), PositionGetDouble(POSITION_TP));
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Tick event                                                        |
//+------------------------------------------------------------------+
void OnTick()
{
   // Avoid heavy work too often: only run core logic on new LTF bar or every N ticks
   static datetime lastLtfTime = 0;
   MqlRates ltf_rates[];
   if(CopyRates(Symbol_, LTF, 0, 1, ltf_rates) <= 0) return;
   if(ltf_rates[0].time != lastLtfTime)
   {
      lastLtfTime = ltf_rates[0].time;
      CheckForEntries();
   }

   // manage trailing on every tick
   ManageTrailing();
}

//+------------------------------------------------------------------+
//| Deinit                                                            |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(ema_handle != INVALID_HANDLE) IndicatorRelease(ema_handle);
   Print("MultiTF Fractal EA stopped.");
}

//+------------------------------------------------------------------+
