void ExecuteSmartOrder(string sym, EntrySignal s, double lot)
{
   trade.SetDeviationInPoints(5);

   if(s.type==ORDER_TYPE_BUY_LIMIT)
      trade.BuyLimit(lot,s.entry,sym,s.sl,s.tp);

   if(s.type==ORDER_TYPE_SELL_LIMIT)
      trade.SellLimit(lot,s.entry,sym,s.sl,s.tp);
}
