//+------------------------------------------------------------------+
//|                                             SSR_QA_Preflight.mq5 |
//|                    SS Replay - Run This FIRST (Phase 16)         |
//|                                                                  |
//|  Everything the tool needs from this terminal, checked in one    |
//|  pass, with REAL NUMBERS.                                        |
//|                                                                  |
//|  The point is to fail in ninety seconds instead of after two     |
//|  hours of debugging. If the terminal cannot create a custom      |
//|  symbol, or the broker has four hundred M1 bars, no amount of    |
//|  reading the replay engine's source will explain what is wrong.  |
//|                                                                  |
//|  It cleans up after itself. Every symbol and chart it makes is   |
//|  removed before it finishes, whatever the outcome.               |
//+------------------------------------------------------------------+
#property script_show_inputs
#property description "Checks this terminal can run SS Replay. Run before anything else."

#include <SSReplay/Common/SSR_Types.mqh>
#include <SSReplay/Common/SSR_Time.mqh>
#include <SSReplay/Common/SSR_SymbolNaming.mqh>

input string InpSymbol      = "";      // Symbol to check (empty = this chart)
input int    InpWantBars    = 20000;   // M1 bars a real session wants
input bool   InpTestCharts  = true;    // Open and close a chart (visible, brief)
input int    InpBenchBars   = 50000;   // Bars per write-rate pass (0 = skip)

int    g_blockers = 0, g_limits = 0, g_ok = 0;
string g_notes    = "";

void Ok(const string what, const string detail)
  { g_ok++;       PrintFormat("  OK       %-38s %s", what, detail); }
void Limit(const string what, const string detail)
  { g_limits++;   PrintFormat("  LIMIT    %-38s %s", what, detail);
    g_notes += "\n  LIMIT   " + what + ": " + detail; }
void Blocker(const string what, const string detail)
  { g_blockers++; PrintFormat("  BLOCKER  %-38s %s", what, detail);
    g_notes += "\n  BLOCKER " + what + ": " + detail; }
void Head(const string t) { PrintFormat("\n--- %s", t); }

//+------------------------------------------------------------------+
void OnStart()
  {
   string sym = (InpSymbol == "" ? _Symbol : InpSymbol);
   Print("==================================================");
   Print("  SS REPLAY - PREFLIGHT");
   Print("  build: ", SSR_BUILD);
   Print("  symbol under test: ", sym);
   Print("==================================================");

   //================================================================
   Head("1. the terminal itself");
   {
      int build = (int)TerminalInfoInteger(TERMINAL_BUILD);
      //--- CustomSymbolCreate and CustomRatesUpdate arrived in 1730.
      //--- Below that nothing in this product can work at all.
      if(build < 1730)
         Blocker("terminal build", StringFormat("%d - custom symbols need 1730+", build));
      else if(build < 2085)
         Limit("terminal build",
               StringFormat("%d - works, but CustomTicksAdd was still "
                            "settling before ~2085", build));
      else
         Ok("terminal build", IntegerToString(build));

      long maxbars = TerminalInfoInteger(TERMINAL_MAXBARS);
      if(maxbars < 100000)
         Limit("max bars in chart",
               StringFormat("%I64d - a long warmup will be cut. "
                            "Tools > Options > Charts", maxbars));
      else
         Ok("max bars in chart", IntegerToString(maxbars));

      long mem = TerminalInfoInteger(TERMINAL_MEMORY_AVAILABLE);
      if(mem < 256)
         Limit("free memory", StringFormat("%I64d MB", mem));
      else
         Ok("free memory", StringFormat("%I64d MB", mem));

      long disk = TerminalInfoInteger(TERMINAL_DISK_SPACE);
      if(disk < 200)
         Limit("free disk", StringFormat("%I64d MB - custom symbol history "
                                         "and session files need room", disk));
      else
         Ok("free disk", StringFormat("%I64d MB", disk));

      if(!TerminalInfoInteger(TERMINAL_DLLS_ALLOWED))
         Ok("DLLs", "disabled - and this product needs none");

      if(MQLInfoInteger(MQL_TESTER))
         Blocker("environment", "this is the Strategy Tester; "
                                "custom symbols behave differently there");
      else
         Ok("environment", "live terminal");
   }

   //================================================================
   Head("2. the instrument");
   {
      if(!SymbolSelect(sym, true))
        {
         Blocker("symbol", sym + " could not be selected in Market Watch");
        }
      else
        {
         int    digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
         double point  = SymbolInfoDouble(sym, SYMBOL_POINT);
         double tv     = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
         double ts     = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
         Ok("symbol specs", StringFormat("digits=%d point=%g tick_value=%g tick_size=%g",
                                         digits, point, tv, ts));
         if(tv <= 0.0 || ts <= 0.0)
            Limit("risk sizing",
                  "this symbol reports no tick value or tick size, so lot "
                  "sizes will fall back to a 1:1 assumption");

         //--- POINT IS NOT TICK SIZE, and code that assumes it is will be
         //--- wrong by exactly the ratio between them. Every money figure
         //--- in this product goes through CSSRRiskEngine, which divides
         //--- by tick_size and never by point; this line is here so the
         //--- difference is on the record when a symbol has one.
         if(ts > 0.0 && point > 0.0 && MathAbs(ts - point) > point * 0.001)
            Ok("point vs tick size",
               StringFormat("they differ (%g vs %g) - money is computed from "
                            "tick size, so this is handled", point, ts));

         //--- WHAT ONE LOT MOVING ONE POINT IS WORTH. The number a user
         //--- can sanity-check against their broker in one glance.
         if(tv > 0.0 && ts > 0.0 && point > 0.0)
            PrintFormat("      one lot, one point = %.5g %s",
                        tv * (point / ts), AccountInfoString(ACCOUNT_CURRENCY));

         //--- SESSION HOURS, which Phase 6 and Phase 11 both read
         datetime from = 0, to = 0;
         if(SymbolInfoSessionQuote(sym, MONDAY, 0, from, to))
            Ok("declared sessions", "present - gap detection will use them");
         else
            Limit("declared sessions",
                  "none declared, so session detection falls back to a "
                  "one-hour gap");
        }
   }

   //================================================================
   Head("3. history depth - the number that decides everything");
   {
      //+------------------------------------------------------------------+
      //| WHAT THE TERMINAL HOLDS, AND WHAT THE SERVER WILL GIVE.          |
      //|                                                                  |
      //| Asking CopyRates for N bars and getting N back says nothing:     |
      //| the ceiling was mine, not the broker's. The first version of     |
      //| this check made exactly that mistake and reported 20,000 as a    |
      //| finding when 20,000 was the number it had asked for.             |
      //|                                                                  |
      //| SeriesInfoInteger answers the real question, and SERVER_FIRSTDATE|
      //| answers the one that matters more: whether MORE can be had.      |
      //+------------------------------------------------------------------+
      long local_bars = 0, local_first = 0, server_first = 0;
      SeriesInfoInteger(sym, PERIOD_M1, SERIES_BARS_COUNT,       local_bars);
      SeriesInfoInteger(sym, PERIOD_M1, SERIES_FIRSTDATE,        local_first);
      SeriesInfoInteger(sym, PERIOD_M1, SERIES_SERVER_FIRSTDATE, server_first);

      if(local_bars > 0)
         PrintFormat("      terminal holds  %I64d M1 bars from %s",
                     local_bars, TimeToString((datetime)local_first));
      if(server_first > 0)
        {
         double server_days = (double)(TimeCurrent() - (datetime)server_first) / 86400.0;
         PrintFormat("      server offers   back to %s  (%.0f calendar days)",
                     TimeToString((datetime)server_first), server_days);
         //--- calendar days, not trading days: an UPPER bound on what a
         //--- 200-day D1 warmup could draw on, and said as such
         if(server_days >= 200.0)
            Ok("server history", StringFormat("%.0f calendar days available - "
                                              "a 200-day D1 warmup is reachable "
                                              "once downloaded", server_days));
         else
            Limit("server history",
                  StringFormat("only %.0f calendar days on the server - "
                               "a 200-day D1 warmup is not reachable from "
                               "this broker", server_days));
        }

      //--- ASK TWICE. The first CopyRates on a cold symbol starts a
      //--- download and returns -1; treating that as "no history" is
      //--- the mistake Phase 2 was built to stop making.
      MqlRates r[];
      int got = CopyRates(sym, PERIOD_M1, 0, InpWantBars, r);
      if(got < 0)
        {
         Print("      (history is downloading - waiting up to 15s)");
         for(int i = 0; i < 30 && got < 0; i++)
           {
            Sleep(500);
            got = CopyRates(sym, PERIOD_M1, 0, InpWantBars, r);
           }
        }

      if(got <= 0)
        {
         Blocker("M1 history", StringFormat("CopyRates returned %d after "
                                            "waiting - open an M1 chart of "
                                            "%s and let it fill", got, sym));
        }
      else
        {
         double days = got / 1440.0;
         PrintFormat("      %d M1 bars   %s .. %s   (%.1f days)",
                     got, TimeToString(r[0].time), TimeToString(r[got-1].time), days);
         if(got < 2000)
            Blocker("M1 history", StringFormat("%d bars is not a session", got));
         else if(got < InpWantBars)
            Limit("M1 history",
                  StringFormat("%d of the %d asked for - shorter sessions "
                               "only, or scroll an M1 chart back to load more",
                               got, InpWantBars));
         else
            Ok("M1 history", StringFormat("%d bars (%.0f days)", got, days));

         //--- WHAT A WARMUP COSTS, against what is LOADED right now.
         //--- Not a verdict on the broker: the tool asks for more when
         //--- it needs it, and the server line above says whether more
         //--- exists. This one only says what is here at this moment.
         long need_d1 = 200L * 1440;
         if(local_bars < need_d1)
            Limit("D1 context, right now",
                  StringFormat("200 daily candles need %I64d M1 bars; %I64d "
                               "are loaded. The tool will pull more when it "
                               "seeds - see the server line above",
                               need_d1, local_bars));
         else
            Ok("D1 context, right now", "200 daily candles are already loaded");
        }

      //--- tick history decides FIDELITY, and the tool degrades rather
      //--- than pretending, so its absence is a limit and not a blocker
      MqlTick tk[];
      datetime t_to   = TimeCurrent();
      datetime t_from = t_to - 3 * 86400;
      int nt = CopyTicksRange(sym, tk, COPY_TICKS_ALL,
                              (ulong)t_from * 1000, (ulong)t_to * 1000);
      if(nt > 0)
         Ok("tick history", StringFormat("%d ticks in the last 3 days - "
                                         "full-tick fidelity is available", nt));
      else
         Limit("tick history",
               "none - the replay will synthesise ticks, and every "
               "stop-and-target inside one bar will be marked assumed");
   }

   //================================================================
   Head("4. custom symbols - the architecture's one hard dependency");
   {
      string test = "SSRPreflight" + SSR_SYMBOL_SUFFIX + "9";

      //--- a leftover from a previous run must not fail the check
      CustomSymbolDelete(test);
      ResetLastError();

      if(!CustomSymbolCreate(test, SSRReplaySymbolPath(), sym))
        {
         Blocker("custom symbol create",
                 StringFormat("error %d - without this NOTHING in this "
                              "product works", GetLastError()));
        }
      else
        {
         Ok("custom symbol create", test);
         CustomSymbolSetInteger(test, SYMBOL_TRADE_MODE, SYMBOL_TRADE_MODE_DISABLED);

         if(!SymbolSelect(test, true))
            Blocker("custom symbol select", "created but cannot be selected");
         else
            Ok("custom symbol select", "in Market Watch");

         //--- write bars and read them back. This is the whole engine
         //--- in miniature: if it does not round-trip, nothing will.
         MqlRates w[];
         ArrayResize(w, 500);
         datetime base = D'2020.01.06 00:00';
         for(int i = 0; i < 500; i++)
           {
            w[i].time  = base + i * 60;
            w[i].open  = 100.0 + i * 0.01;
            w[i].close = w[i].open;
            w[i].high  = w[i].open + 0.02;
            w[i].low   = w[i].open - 0.02;
            w[i].tick_volume = 10; w[i].spread = 2; w[i].real_volume = 0;
           }

         ulong t0 = GetMicrosecondCount();
         int   wrote = CustomRatesUpdate(test, w);
         double ms = (GetMicrosecondCount() - t0) / 1000.0;

         if(wrote <= 0)
            Blocker("custom bars write",
                    StringFormat("CustomRatesUpdate returned %d, error %d",
                                 wrote, GetLastError()));
         else
           {
            //--- CORRECTNESS ONLY. This write is 500 bars, and 500 bars
            //--- cannot measure a 288,000-bar warmup. Section 5 does
            //--- the measuring, at the scale it is quoting.
            Ok("custom bars write",
               StringFormat("%d bars accepted in %.1f ms", wrote, ms));

            MqlRates back[];
            int read = CopyRates(test, PERIOD_M1, w[0].time, w[499].time, back);
            for(int i = 0; i < 20 && read < 0; i++)
              { Sleep(200); read = CopyRates(test, PERIOD_M1, w[0].time, w[499].time, back); }

            if(read <= 0)
               Blocker("custom bars read back",
                       StringFormat("wrote %d, read %d", wrote, read));
            else if(read < wrote)
               Limit("custom bars read back",
                     StringFormat("wrote %d, read %d - the terminal kept "
                                  "fewer than it was given", wrote, read));
            else
               Ok("custom bars read back", StringFormat("%d bars", read));

            //--- and that HIGHER TIMEFRAMES ARE DERIVED, which is the
            //--- claim the entire architecture rests on
            MqlRates m5[];
            int n5 = CopyRates(test, PERIOD_M5, w[0].time, w[499].time, m5);
            for(int i = 0; i < 20 && n5 < 0; i++)
              { Sleep(200); n5 = CopyRates(test, PERIOD_M5, w[0].time, w[499].time, m5); }
            if(n5 > 0)
               Ok("higher timeframes derived",
                  StringFormat("%d M5 bars from %d M1 - the terminal builds "
                               "them, we never do", n5, read));
            else
               Blocker("higher timeframes derived",
                       "the terminal did not derive M5 from the M1 we wrote");
           }

         //--- ticks, which full-tick fidelity depends on
         MqlTick add[];
         ArrayResize(add, 100);
         for(int i = 0; i < 100; i++)
           {
            add[i].time      = w[0].time + i;
            add[i].time_msc  = (long)w[0].time * 1000 + i * 1000;
            add[i].bid       = 100.0;
            add[i].ask       = 100.02;
            add[i].last      = 100.0;
            add[i].volume    = 1;
            add[i].volume_real = 0.0;
            add[i].flags     = TICK_FLAG_BID | TICK_FLAG_ASK;
           }
         int nadd = CustomTicksAdd(test, add);
         if(nadd == ArraySize(add))
            Ok("custom ticks", StringFormat("%d accepted", nadd));
         else
            Limit("custom ticks",
                  StringFormat("%d of %d accepted (error %d) - full-tick "
                               "fidelity may be refused; the engine degrades "
                               "and says so", nadd, ArraySize(add), GetLastError()));

         //--- a chart of it, because a replay symbol with no chart is
         //--- a file nobody can see
         if(InpTestCharts)
           {
            long cid = ChartOpen(test, PERIOD_M1);
            if(cid == 0)
               Blocker("chart open", "could not open a chart of the custom symbol");
            else
              {
               Sleep(700);
               Ok("chart open", "opened and about to close");
               ChartClose(cid);
               Sleep(300);
              }
           }

         //--- CLEAN UP.
         //---
         //--- A SELECTED SYMBOL CANNOT BE DELETED - error 5306 - and the
         //--- first version of this script hit exactly that, because it
         //--- selected the symbol and never let go. The product's own
         //--- teardown had this right all along; the QA script did not.
         //--- Same order as CSSRCustomSymbolManager::Destroy().
         SymbolSelect(test, false);
         Sleep(100);                    // the terminal needs a beat

         ResetLastError();
         if(!CustomSymbolDelete(test))
            Limit("cleanup",
                  StringFormat("could not delete %s (error %d) - remove it "
                               "by hand from Market Watch", test, GetLastError()));
         else
            Ok("cleanup", "test symbol removed");
        }
   }

   //================================================================
   Head("5. write rate, measured at the scale it is quoted at");
   {
      //+------------------------------------------------------------------+
      //| WHY THIS SECTION EXISTS.                                         |
      //|                                                                  |
      //| The first version of this script timed a 500-bar write and       |
      //| multiplied by 576 to quote a 288,000-bar warmup. Two real runs   |
      //| then reported 35,159 and 180,245 bars/sec from that same 500-bar |
      //| sample - a 5x spread, out of a sample small enough to be mostly  |
      //| call overhead and whatever the terminal happened to be doing.    |
      //| Either number would have been quoted to a user as fact.          |
      //|                                                                  |
      //| A rule I set at the start of this project: no performance claim  |
      //| without measurement. Extrapolating 576x is a claim.              |
      //|                                                                  |
      //| So this writes at warmup scale, three times, in the shape a      |
      //| warmup actually uses - forward, disjoint, into a growing series  |
      //| - and quotes the SLOWEST pass, because the slowest is the one    |
      //| a user will sooner or later sit through.                         |
      //+------------------------------------------------------------------+
      if(InpBenchBars < 1000)
        {
         Print("      (skipped - InpBenchBars is below 1000, too small to measure)");
        }
      else
        {
         string bs = "SSRPreflight" + SSR_SYMBOL_SUFFIX + "B";
         CustomSymbolDelete(bs);
         ResetLastError();

         if(!CustomSymbolCreate(bs, SSRReplaySymbolPath(), sym))
           {
            Limit("write rate", StringFormat("could not create the benchmark "
                                             "symbol (error %d) - rate unknown",
                                             GetLastError()));
           }
         else
           {
            CustomSymbolSetInteger(bs, SYMBOL_TRADE_MODE, SYMBOL_TRADE_MODE_DISABLED);

            MqlRates b[];
            ArrayResize(b, InpBenchBars);

            double   worst_rate = 0.0;
            double   best_rate  = 0.0;
            bool     failed     = false;
            datetime cursor     = D'2015.01.05 00:00';

            for(int pass = 0; pass < 3; pass++)
              {
               for(int i = 0; i < InpBenchBars; i++)
                 {
                  b[i].time        = cursor + i * 60;
                  b[i].open        = 100.0 + (i % 500) * 0.01;
                  b[i].close       = b[i].open;
                  b[i].high        = b[i].open + 0.02;
                  b[i].low         = b[i].open - 0.02;
                  b[i].tick_volume = 10;
                  b[i].spread      = 2;
                  b[i].real_volume = 0;
                 }

               ulong  t0 = GetMicrosecondCount();
               int    n  = CustomRatesUpdate(bs, b);
               double ms = (GetMicrosecondCount() - t0) / 1000.0;

               if(n != InpBenchBars)
                 {
                  Limit("write rate",
                        StringFormat("pass %d wrote %d of %d (error %d)",
                                     pass + 1, n, InpBenchBars, GetLastError()));
                  failed = true;
                  break;
                 }

               double rate = (ms > 0.0 ? n / (ms / 1000.0) : 0.0);
               PrintFormat("      pass %d: %d bars in %.0f ms = %.0f bars/sec",
                           pass + 1, n, ms, rate);
               if(worst_rate == 0.0 || rate < worst_rate) worst_rate = rate;
               if(rate > best_rate)                       best_rate  = rate;

               //--- next pass appends AFTER this one, so each write goes
               //--- into a series that is already longer than the last
               cursor += InpBenchBars * 60;
              }

            if(!failed && worst_rate > 0.0)
              {
               Ok("write rate", StringFormat("%.0f bars/sec at %d-bar scale "
                                             "(slowest of 3; fastest was %.0f)",
                                             worst_rate, InpBenchBars, best_rate));

               //--- Say plainly how far this is being stretched. A 200-day
               //--- D1 warmup is 288,000 M1 bars; anything short of that
               //--- measured here is extrapolation, and is labelled so.
               double secs = 288000.0 / worst_rate;
               double reach = 288000.0 / (double)InpBenchBars;
               if(reach <= 1.0)
                  PrintFormat("      a 200-day D1 warmup (288,000 bars) is "
                              "MEASURED at %.0f seconds", secs);
               else
                  PrintFormat("      a 200-day D1 warmup (288,000 bars) "
                              "extrapolates to %.0f seconds - %.1fx beyond "
                              "what was measured, so treat it as an estimate",
                              secs, reach);

               if(secs > 120.0)
                  Limit("warmup cost",
                        StringFormat("about %.0f seconds for a full D1 warmup "
                                     "- usable, but not something to do often",
                                     secs));

               //--- THE OTHER RATE, and the one that decides whether replay
               //--- keeps up at speed: a warmup writes in bulk, but a running
               //--- replay appends one bar at a time. They are not the same
               //--- number and quoting the bulk one for both would mislead.
               MqlRates one[1];
               ulong    t1 = GetMicrosecondCount();
               int      appended = 0;
               for(int i = 0; i < 500; i++)
                 {
                  one[0].time        = cursor + i * 60;
                  one[0].open        = 100.0;
                  one[0].close       = 100.0;
                  one[0].high        = 100.02;
                  one[0].low         = 99.98;
                  one[0].tick_volume = 10;
                  one[0].spread      = 2;
                  one[0].real_volume = 0;
                  if(CustomRatesUpdate(bs, one) == 1) appended++;
                 }
               double per_bar_us = (GetMicrosecondCount() - t1) / 500.0;

               if(appended < 500)
                  Limit("single-bar append",
                        StringFormat("%d of 500 single-bar writes accepted "
                                     "(error %d)", appended, GetLastError()));
               else
                 {
                  Ok("single-bar append",
                     StringFormat("%.0f us per bar = %.0f bars/sec streaming",
                                  per_bar_us, 1000000.0 / per_bar_us));
                  //--- 1x speed on M1 is one bar per 60 seconds. The number
                  //--- that matters is the ceiling, not the comfort.
                  PrintFormat("      at that cost the M1 stream saturates "
                              "around %.0fx real time", 60000000.0 / per_bar_us);
                 }
              }

            SymbolSelect(bs, false);
            Sleep(100);
            ResetLastError();
            if(!CustomSymbolDelete(bs))
               Limit("benchmark cleanup",
                     StringFormat("could not delete %s (error %d) - remove it "
                                  "by hand from Market Watch", bs, GetLastError()));
           }
        }
   }

   //================================================================
   Head("6. the places this product writes to");
   {
      string path = "SSReplay\\preflight.txt";
      int h = FileOpen(path, FILE_WRITE | FILE_TXT | FILE_ANSI);
      if(h == INVALID_HANDLE)
         Blocker("file write",
                 StringFormat("cannot write MQL5\\Files\\%s (error %d) - "
                              "sessions and journals need this", path, GetLastError()));
      else
        {
         FileWriteString(h, "ok\r\n");
         FileClose(h);
         FileDelete(path);
         Ok("file write", "MQL5\\Files is writable");
        }

      //--- the Phase 14 transport
      string gv = "SSR.preflight";
      if(!GlobalVariableSet(gv, 1234.5))
         Limit("global variables",
               "cannot be set - other products will not see replay state");
      else
        {
         double v = GlobalVariableGet(gv);
         GlobalVariableDel(gv);
         if(MathAbs(v - 1234.5) > 1e-9)
            Limit("global variables", "written but read back wrong");
         else
            Ok("global variables", "the integration transport works");
        }
   }

   //================================================================
   Print("");
   Print("==================================================");
   PrintFormat("  OK: %d    LIMITS: %d    BLOCKERS: %d", g_ok, g_limits, g_blockers);
   if(g_notes != "")
      Print("  ", g_notes);
   Print("");
   if(g_blockers > 0)
      Print("  VERDICT: NO GO - fix the blockers above first.");
   else if(g_limits > 0)
      Print("  VERDICT: GO, WITH THE LIMITS ABOVE. They are real and the "
            "tool will say so again while running.");
   else
      Print("  VERDICT: GO.");
   Print("==================================================");
  }
//+------------------------------------------------------------------+
