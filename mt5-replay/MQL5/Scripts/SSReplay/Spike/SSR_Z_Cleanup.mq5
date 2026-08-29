//+------------------------------------------------------------------+
//|                                              SSR_Z_Cleanup.mq5   |
//|  Removes every artefact the Phase 0 spikes leave behind:         |
//|  test symbols, their charts, global variables and result files.  |
//|                                                                  |
//|  Run this between full test runs so numbers are never measured   |
//|  on top of a previous run's leftovers.                           |
//+------------------------------------------------------------------+
#property script_show_inputs

#include <SSReplay/Spike/SSR_SpikeKit.mqh>

input bool InpDeleteResults = false;   // Also delete results.csv / verdicts.csv / env.csv

string g_syms[] = {"SSRA1", "SSRA2", "SSRA2N", "SSRA3", "SSRB1", "SSRB1H",
                   "SSRB2", "SSRB3A", "SSRB3B", "SSRC1", "SSRC4",
                   "SSRD1", "SSRD2", "SSRD3", "SSRD4"};

//+------------------------------------------------------------------+
void OnStart()
  {
   int closed = 0;

   //--- close any chart on a spike symbol
   long id = ChartFirst();
   while(id >= 0)
     {
      long next = ChartNext(id);
      string s = ChartSymbol(id);
      if(StringFind(s, "SSR") == 0)
        {
         ChartClose(id);
         closed++;
        }
      id = next;
     }
   Sleep(500);

   int dropped = 0;
   for(int i = 0; i < ArraySize(g_syms); i++)
     {
      ResetLastError();
      SymbolSelect(g_syms[i], false);
      if(CustomSymbolDelete(g_syms[i]))
         dropped++;
     }

   //--- length-probe symbols from A1
   for(int len = 4; len <= 64; len++)
     {
      string probe = "";
      for(int i = 0; i < len; i++) probe += "A";
      CustomSymbolDelete(probe);
     }

   //--- global variables
   int gv = GlobalVariablesDeleteAll("SSR.");

   PrintFormat("[Cleanup] charts closed=%d  symbols deleted=%d  globals deleted=%d",
               closed, dropped, gv);

   if(InpDeleteResults)
     {
      FileDelete(SSR_F_RESULTS);
      FileDelete(SSR_F_VERDICTS);
      FileDelete(SSR_F_ENV);
      FileDelete("SSR_Spike\\c2_heartbeat.csv");
      FileDelete("SSR_Spike\\d3_timeseries.csv");
      FileDelete("SSR_Spike\\c1_service_probe.txt");
      Print("[Cleanup] result files deleted");
     }
   else
      Print("[Cleanup] result files kept - set InpDeleteResults to remove them");

   Print("[Cleanup] NOTE: remove leftover history manually from <DataFolder>\\bases\\Custom if needed");
  }
//+------------------------------------------------------------------+
