//+------------------------------------------------------------------+
//|                                       SSR_B4_BrokerDataAudit.mq5 |
//|  SPIKE B4 - Broker Tick & History Availability                   |
//|  TIER B - HIGH  (an audit, not a pass/fail test)                 |
//|                                                                  |
//|  Answers the practical question the whole fidelity strategy      |
//|  depends on: how much data does YOUR broker actually have?       |
//|  If tick history is near zero for US30Cash, F1 is fiction and    |
//|  CSV import moves forward in the roadmap.                        |
//+------------------------------------------------------------------+
#property script_show_inputs

#include <SSReplay/Spike/SSR_SpikeKit.mqh>

input string InpSymbols = "";   // Comma separated (blank = this chart + Market Watch)
input int    InpMaxAuto = 6;    // Cap when the list is blank

//+------------------------------------------------------------------+
void AuditSymbol(const string sym)
  {
   if(!SymbolSelect(sym, true))
     {
      SSR_Metric(sym, "available", 0, "bool", "SymbolSelect failed");
      return;
     }
   SSR_Metric(sym, "available", 1, "bool");

   //--- nudge the terminal into downloading, then wait for sync
   MqlRates warm[];
   CopyRates(sym, PERIOD_M1, 0, 10, warm);
   double wait = SSR_WaitSeries(sym, PERIOD_M1, 30000);
   SSR_Metric(sym, "m1_sync_wait", wait, "ms");

   long first_local = 0, first_server = 0, bars_m1 = 0;
   SeriesInfoInteger(sym, PERIOD_M1, SERIES_FIRSTDATE, first_local);
   SeriesInfoInteger(sym, PERIOD_M1, SERIES_SERVER_FIRSTDATE, first_server);
   SeriesInfoInteger(sym, PERIOD_M1, SERIES_BARS_COUNT, bars_m1);

   SSR_Metric(sym, "m1_bars_local", (double)bars_m1, "count");
   SSR_Metric(sym, "m1_first_local_days_ago",
              (double)(TimeCurrent() - (datetime)first_local) / 86400.0, "days",
              TimeToString((datetime)first_local, TIME_DATE));
   SSR_Metric(sym, "m1_first_server_days_ago",
              (double)(TimeCurrent() - (datetime)first_server) / 86400.0, "days",
              TimeToString((datetime)first_server, TIME_DATE));
   SSR_Metric(sym, "m1_downloadable_more",
              ((datetime)first_server < (datetime)first_local ? 1 : 0), "bool",
              "Load More History would gain data");

   //--- how deep does tick history go? walk back in doubling steps
   datetime now = TimeCurrent();
   int deepest_days = 0;
   for(int d = 1; d <= 2048; d *= 2)
     {
      MqlTick tk[];
      datetime from = now - d * 86400;
      int got = CopyTicksRange(sym, tk, COPY_TICKS_INFO,
                               (long)from * 1000, (long)(from + 3600) * 1000);
      if(got > 0)
         deepest_days = d;
      else
         break;
     }
   SSR_Metric(sym, "tick_history_depth", (double)deepest_days, "days",
              (deepest_days == 0 ? "NO tick history - F1 impossible" : ""));

   //--- practical ceiling of one CopyTicksRange call
   int cap = 0;
   {
      MqlTick tk[];
      datetime from = now - 7 * 86400;
      int got = CopyTicksRange(sym, tk, COPY_TICKS_ALL,
                               (long)from * 1000, (long)now * 1000);
      cap = got;
   }
   SSR_Metric(sym, "copyticksrange_week_return", (double)cap, "ticks",
              "sets the page size for TickSource");

   //--- how long does one day of M1 take to fetch once synced?
   ulong t0 = SSR_Now();
   MqlRates day[];
   int nday = CopyRates(sym, PERIOD_M1, now - 86400, now, day);
   SSR_Metric(sym, "copyrates_1day", SSR_ElapsedMs(t0), "ms",
              StringFormat("bars=%d", nday));
  }

//+------------------------------------------------------------------+
void OnStart()
  {
   SSR_Begin("B4_BrokerDataAudit");

   //--- A typed-in symbol list is a guess about someone else's Market
   //--- Watch, and a wrong guess makes the audit report "not available"
   //--- four times and measure nothing. Blank means "audit what this
   //--- terminal actually has", starting with the chart we were dropped
   //--- on. The cap is there because each symbol can wait up to 30s for
   //--- a history download, and a 40-symbol Market Watch would look
   //--- like a hang.
   string list = InpSymbols;
   if(StringLen(list) == 0)
     {
      list = Symbol();
      int have = 1;
      int total = SymbolsTotal(true);
      for(int i = 0; i < total && have < InpMaxAuto; i++)
        {
         string s = SymbolName(i, true);
         if(s == Symbol() || s == "")
            continue;
         list += "," + s;
         have++;
        }
      PrintFormat("[B4] no list given - auditing %d symbol(s) from this terminal: %s",
                  have, list);
     }

   string parts[];
   int n = StringSplit(list, StringGetCharacter(",", 0), parts);
   for(int i = 0; i < n; i++)
     {
      string s = parts[i];
      StringTrimLeft(s);
      StringTrimRight(s);
      if(s == "") continue;
      Print("[B4] auditing ", s);
      AuditSymbol(s);
     }

   SSR_Verdict("audit_completed", true, "report produced",
               IntegerToString(n) + " symbols", "no pass/fail - this is an audit");
   SSR_End();
  }
//+------------------------------------------------------------------+
