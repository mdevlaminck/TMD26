struct EntrySignal
{
   bool valid;
   ENUM_ORDER_TYPE type;
   double entry, sl, tp;
   double slPoints;
};

EntrySignal GenerateSignal(string sym, MarketRegime regime)
{
   EntrySignal s; s.valid=false;

   double macdW = iMACD(sym,PERIOD_W1,12,26,9,PRICE_CLOSE,MODE_MAIN,1);
   double macdWs= iMACD(sym,PERIOD_W1,12,26,9,PRICE_CLOSE,MODE_SIGNAL,1);
   double rsi = iRSI(sym,PERIOD_D1,14,PRICE_CLOSE,1);
   double atr = iATR(sym,PERIOD_D1,14,1);
   double price = SymbolInfoDouble(sym,SYMBOL_BID);

   if(macdW > macdWs && rsi < 40)
   {
      s.valid=true;
      s.type = ORDER_TYPE_BUY_LIMIT;
      s.entry = price - atr*0.3;
      s.sl = s.entry - atr*1.6;
      s.tp = s.entry + atr*3.5;
   }

   if(macdW < macdWs && rsi > 60)
   {
      s.valid=true;
      s.type = ORDER_TYPE_SELL_LIMIT;
      s.entry = price + atr*0.3;
      s.sl = s.entry + atr*1.6;
      s.tp = s.entry - atr*3.5;
   }

   s.slPoints = MathAbs(s.entry - s.sl)/_Point;
   return s;
}
