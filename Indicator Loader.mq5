//+------------------------------------------------------------------+
//|                                             Indicator Loader.mq5 |
//|                       Copyright 2025, phade, MetaQuotes Ltd.      |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, phade, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property description "A system to load up to 4 separate-window indicators for tests in the visual strategy tester"
#property description "Designed for Strategy Tester visualization"

// Input parameters for indicator paths
input string Indicator1_Path = "Examples\\MACD"; // Path to indicator 1
input string Indicator2_Path = "Examples\\ADX";  // Path to indicator 2
input string Indicator3_Path = "Examples\\ATR";  // Path to indicator 3
input string Indicator4_Path = "Examples\\CCI";  // Path to indicator 4


int indicator_handles[4];
int indicator_windows[];

string paths[] = {Indicator1_Path, Indicator2_Path, Indicator3_Path, Indicator4_Path};

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
  {
   long chart_id = ChartID();

// add indicators
   for(int i = 0; i < 4; i++)
     {
      if(paths[i] != "")
        {
         indicator_handles[i] = iCustom(_Symbol, _Period, paths[i]);
         if(indicator_handles[i] == INVALID_HANDLE)
           {
            Print("Failed to create handle for: ", paths[i], ", Error: ", GetLastError());
            continue;
           }

         

         if (paths[i] == "Market\\FX Dynamic MT5" || paths[i] == "Market\\Smart Stop Indicator MT5" ) {
            // Add to window
            if(!ChartIndicatorAdd(chart_id, 0, indicator_handles[i]))
              {
               Print("Failed to add indicator: ", paths[i], " to window ", 0, ", Error: ", GetLastError());
              }
          
         } else {
            // start with next available subwindow
            int window = (int)ChartGetInteger(chart_id, CHART_WINDOWS_TOTAL);
            // Add to subwindow
            if(!ChartIndicatorAdd(chart_id, window, indicator_handles[i]))
              {
               Print("Failed to add indicator: ", paths[i], " to window ", window, ", Error: ", GetLastError());
              }
           }
         }
         
     }

   return(INIT_SUCCEEDED);
  }



//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   static bool first_tick = true;
   if(first_tick)
     {
      long chart_id = ChartID();

      int total_windows = (int)ChartGetInteger(chart_id, CHART_WINDOWS_TOTAL);

      ArrayResize(indicator_windows, total_windows);

      Print("Subwindow count on first tick: ", total_windows);

      for(int w = 0; w < total_windows; w++)
        {
         int ind_total = ChartIndicatorsTotal(chart_id, w);
         string ind_names = "";

         for(int j = 0; j < ind_total; j++)
            ind_names += "  " + ChartIndicatorName(chart_id, w, j) + (j < ind_total - 1 ? "\n" : "");

         if(ind_names != "")
            Print("Subwindow ", w, " contents:\n", ind_names);

         indicator_windows[w] = w;
        }
      first_tick = false;
     }

   Comment("Indicator Loader EA Active");
  }


//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   long chart_id = ChartID();
   int total_windows = (int)ChartGetInteger(chart_id, CHART_WINDOWS_TOTAL);

   for(int w = total_windows - 1; w >= 1; w--)
   {
      if(ChartIndicatorsTotal(chart_id, w) > 0)
      {
         string ind_name = ChartIndicatorName(chart_id, w, 0);
         if(ind_name != "")
         {
            if(ChartIndicatorDelete(chart_id, w, ind_name))
               Print("Successfully removed indicator: ", ind_name, " from subwindow ", w);
            else
               Print("Failed to remove indicator: ", ind_name, " from subwindow ", w, ", Error: ", GetLastError());
         }
      }
   }
 
  // Release the corresponding handles
   for(int i = 0; i < 4; i++)
   {
      if(indicator_handles[i] != INVALID_HANDLE)
      {
         IndicatorRelease(indicator_handles[i]);
      }
   }

   Comment("");
}
