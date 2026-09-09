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
//+------------------------------------------------------------------+
//| IT LIVES IN QA NOW, NOT AMONG THE SPIKES.                        |
//|                                                                  |
//| The engine prints "run SSR_Z_Cleanup" when a replay symbol will   |
//| not delete, and the script it named sat in Spike/ between         |
//| SSR_D4_RewindCost and SSR_C3_IpcChannel. An instruction pointing  |
//| into a folder of thirteen developer probes is an instruction      |
//| nobody follows.                                                   |
//+------------------------------------------------------------------+
void OnStart()
  {
   Print("=== SSR_Z_Cleanup  ssr=", SSR_BUILD, " ===");
   Comment("SSR_Z_Cleanup running...");

   int closed = 0;

   //--- close any chart on a spike symbol
   long id = ChartFirst();
   while(id >= 0)
     {
      long next = ChartNext(id);
      string s = ChartSymbol(id);
      //--- spike symbols start with SSR; product replay symbols carry
      //--- the .SSR suffix. Both are ours and both must go.
      if(StringFind(s, "SSR") == 0 || StringFind(s, ".SSR") >= 0)
        {
         ChartClose(id);
         closed++;
        }
      id = next;
     }
   Sleep(500);

   //+------------------------------------------------------------------+
   //| THE ORDER IS THE WHOLE TRICK.                                    |
   //|                                                                  |
   //| MetaTrader refuses to delete a symbol that is selected in Market |
   //| Watch (error 5306), and it needs a moment after being told to    |
   //| deselect one. Charts first, then deselect, then a beat, then     |
   //| delete - the same sequence CSSRCustomSymbolManager::Destroy uses. |
   //|                                                                  |
   //| And a refusal is REPORTED BY NAME with what to do about it.      |
   //| "symbols deleted=0" tells nobody anything.                       |
   //+------------------------------------------------------------------+
   int    dropped = 0, stuck = 0;
   string stuck_list = "";

   //--- product replay symbols: <origin>.SSR<slot>, any origin, any slot
   for(int i = SymbolsTotal(false) - 1; i >= 0; i--)
     {
      string name = SymbolName(i, false);
      if(StringFind(name, ".SSR") < 0)
         continue;
      SymbolSelect(name, false);
      Sleep(120);
      ResetLastError();
      if(CustomSymbolDelete(name))
         dropped++;
      else
        {
         stuck++;
         stuck_list += StringFormat("\n    %s  (error %d)", name, GetLastError());
        }
     }

   for(int i = 0; i < ArraySize(g_syms); i++)
     {
      SymbolSelect(g_syms[i], false);
      Sleep(60);
      ResetLastError();
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

   if(stuck > 0)
     {
      Print("[Cleanup] these would NOT delete:", stuck_list);
      Print("[Cleanup] error 5306 means the symbol is still selected in "
            "Market Watch. Right-click it there and choose Hide, then run "
            "this again. If that does not do it, a chart of it is still "
            "open somewhere - including in another profile.");
     }
   else
      Print("[Cleanup] nothing of ours is left behind.");

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

   //--- on the chart as well. The whole reason this script gets run is
   //--- that something looked stuck, and the Experts tab is the place
   //--- the person in that situation is least likely to be looking.
   Comment(StringFormat("SSR_Z_Cleanup  %s\n"
                        "%d chart(s) closed, %d replay symbol(s) deleted, "
                        "%d stuck%s\n\n"
                        "Stuck means a chart of it is still open, or it is "
                        "still shown in Market Watch (right-click it, Hide).",
                        SSR_BUILD, closed, dropped, stuck,
                        (stuck > 0 ? ":" + stuck_list : "")));
  }
//+------------------------------------------------------------------+
