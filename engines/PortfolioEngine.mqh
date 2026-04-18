bool PortfolioAllow(string sym)
{
   double exposure = 0;

   for(int i=0;i<PositionsTotal();i++)
   {
      PositionSelectByIndex(i);
      exposure += PositionGetDouble(POSITION_VOLUME);
   }

   if(exposure > 5.0) return false;
   return true;
}
