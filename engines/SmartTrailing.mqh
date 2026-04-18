void SmartTrail(string sym)
{
   double atr = iATR(sym,PERIOD_H1,14,1);

   for(int i=0;i<PositionsTotal();i++)
   {
      PositionSelectByIndex(i);
      if(PositionGetSymbol(i)!=sym) continue;

      double newSL;

      if(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)
         newSL = SymbolInfoDouble(sym,SYMBOL_BID) - atr*1.2;
      else
         newSL = SymbolInfoDouble(sym,SYMBOL_ASK) + atr*1.2;

      trade.PositionModify(sym,newSL,0);
   }
}
