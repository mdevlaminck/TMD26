enum MarketRegime { REGIME_TREND, REGIME_RANGE, REGIME_BREAKOUT };

MarketRegime DetectMarketRegime(string sym)
{
   double atr = iATR(sym, PERIOD_D1,14,1);
   double atr_avg = iMA(sym,PERIOD_D1,20,0,MODE_SMA,PRICE_CLOSE,1);

   if(atr > atr_avg*1.3) return REGIME_BREAKOUT;
   if(atr < atr_avg*0.8) return REGIME_RANGE;

   return REGIME_TREND;
}