bool SessionAllowed()
{
   int h = TimeHour(TimeCurrent());
   return (h>=7 && h<=18); // London + NY overlap
}
