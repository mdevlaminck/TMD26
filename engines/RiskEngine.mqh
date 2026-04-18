double CalculateLot(string sym,double slPoints)
{
   double risk = 0.5;
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double tickValue = SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_VALUE);

   double lot = (equity * risk/100.0) / (slPoints * tickValue);
   return NormalizeDouble(lot,2);
}