void InitDashboard()
{
   Comment("Quantum Institutional Trading AI v6\nStatus: ACTIVE");
}

void UpdateDashboard()
{
   Comment("Quantum AI v6\n",
           "Equity: ",AccountInfoDouble(ACCOUNT_EQUITY),"\n",
           "Open Trades: ",PositionsTotal(),"\n",
           "Free Margin: ",AccountInfoDouble(ACCOUNT_FREEMARGIN));
}
