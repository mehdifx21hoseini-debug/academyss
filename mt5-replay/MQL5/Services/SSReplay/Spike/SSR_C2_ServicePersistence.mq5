//+------------------------------------------------------------------+
//|                                   SSR_C2_ServicePersistence.mq5  |
//|  SPIKE C2 - Service Persistence Across Chart / TF / Profile      |
//|  TIER C - CRITICAL                                               |
//|                                                                  |
//|  The single most important reason to choose Service over EA:     |
//|  an EA is deinitialised and reinitialised on every timeframe     |
//|  change, taking the engine state with it. A Service should not   |
//|  care. This measures whether that is true.                       |
//|                                                                  |
//|  MANUAL PROCEDURE - perform in order while this runs:            |
//|    t+30s   change the chart timeframe M5 -> M15                  |
//|    t+60s   change it again M15 -> H1                             |
//|    t+90s   close the chart                                       |
//|    t+120s  open a new chart                                      |
//|    t+150s  change that chart's symbol                            |
//|    t+180s  switch MT5 profile                                    |
//|    t+240s  close every chart                                     |
//|    t+300s  stop the service                                      |
//|                                                                  |
//|  PASS: heartbeat counter never resets and no gap exceeds 3000ms. |
//+------------------------------------------------------------------+
#property service

#include <SSReplay/Spike/SSR_SpikeKit.mqh>

input int InpBeatMs   = 500;   // Heartbeat interval (ms)
input int InpRunSec   = 360;   // Total run time (seconds)

//+------------------------------------------------------------------+
int CountCharts()
  {
   int n = 0;
   long id = ChartFirst();
   while(id >= 0)
     {
      n++;
      id = ChartNext(id);
     }
   return n;
  }

//+------------------------------------------------------------------+
void OnStart()
  {
   SSR_Begin("C2_ServicePersistence");
   FolderCreate(SSR_DIR);

   //--- a counter that survives a service restart would hide a reset,
   //--- so we deliberately start from zero and detect restarts by it
   long   seq       = 0;
   ulong  t_start   = GetMicrosecondCount();
   ulong  t_prev    = t_start;
   double max_gap   = 0;
   int    over_3s   = 0;

   //--- publish a restart marker so an accidental relaunch is visible
   double prev_marker = GlobalVariableGet("SSR.c2.launches");
   GlobalVariableSet("SSR.c2.launches", prev_marker + 1);
   SSR_Metric("startup", "launch_count", prev_marker + 1, "count",
              "must stay 1 for the whole procedure");

   int fh = FileOpen("SSR_Spike\\c2_heartbeat.csv", FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(fh != INVALID_HANDLE)
      FileWriteString(fh, "seq,utc,uptime_ms,gap_ms,charts_open,mem_terminal_mb\r\n");

   Print("[C2] heartbeat started - now perform the manual procedure in the header");

   while(!IsStopped())
     {
      ulong now = GetMicrosecondCount();
      double uptime = (double)(now - t_start) / 1000.0;
      double gap    = (double)(now - t_prev) / 1000.0;
      t_prev = now;
      seq++;

      if(seq > 1)
        {
         if(gap > max_gap) max_gap = gap;
         if(gap > 3000.0)
           {
            over_3s++;
            PrintFormat("[C2] GAP %.0fms at seq=%d - thread was starved or suspended",
                        gap, (int)seq);
           }
        }

      if(fh != INVALID_HANDLE)
         FileWriteString(fh, StringFormat("%d,%s,%.0f,%.0f,%d,%d\r\n",
                                          (int)seq, SSR_Utc(), uptime, gap,
                                          CountCharts(), (int)SSR_MemTerminal()));

      //--- publish live state so a panel could read it (IPC smoke test)
      GlobalVariableSet("SSR.c2.seq", (double)seq);
      GlobalVariableSet("SSR.c2.uptime", uptime);

      if(uptime >= InpRunSec * 1000.0)
         break;

      Sleep(InpBeatMs);
     }

   if(fh != INVALID_HANDLE)
      FileClose(fh);

   double uptime_s = (double)(GetMicrosecondCount() - t_start) / 1000000.0;

   SSR_Metric("persistence", "heartbeats",     (double)seq,   "count");
   SSR_Metric("persistence", "uptime",         uptime_s,      "s");
   SSR_Metric("persistence", "max_gap",        max_gap,       "ms");
   SSR_Metric("persistence", "gaps_over_3s",   (double)over_3s, "count");
   SSR_Metric("persistence", "launch_count",
              GlobalVariableGet("SSR.c2.launches"), "count");

   SSR_Verdict("no_restart", GlobalVariableGet("SSR.c2.launches") <= 1.0, "1",
               DoubleToString(GlobalVariableGet("SSR.c2.launches"), 0),
               "more than 1 means the service was restarted");
   SSR_Verdict("no_long_gaps", over_3s == 0, "0 gaps > 3000ms",
               IntegerToString(over_3s),
               StringFormat("max gap %.0fms", max_gap));
   SSR_Verdict("survived_full_run", uptime_s >= InpRunSec * 0.95,
               IntegerToString(InpRunSec) + "s",
               StringFormat("%.0fs", uptime_s), "");

   SSR_End();
   Print("[C2] heartbeat log: <DataFolder>\\MQL5\\Files\\SSR_Spike\\c2_heartbeat.csv");
   Print("[C2] reset the launch counter before the next run: delete GV 'SSR.c2.launches'");
  }
//+------------------------------------------------------------------+
