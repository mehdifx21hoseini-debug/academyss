//+------------------------------------------------------------------+
//|                                           SSR_T3_CustomSymbol.mq5 |
//|                     SS Replay - Phase 3 Custom Symbol Engine     |
//|                                                                  |
//|  Needs a real terminal: this is where the product first touches  |
//|  the Custom* API. Tests that cannot run without broker history   |
//|  SKIP rather than fail.                                          |
//|                                                                  |
//|  Cleans up after itself. If a run is interrupted, SSR_Z_Cleanup  |
//|  removes anything left behind.                                   |
//+------------------------------------------------------------------+
#property script_show_inputs

#include <SSReplay/Common/SSR_Types.mqh>
#include <SSReplay/Common/SSR_Time.mqh>
#include <SSReplay/Common/SSR_SymbolNaming.mqh>
#include <SSReplay/Mt5/SSR_CustomSymbolSink.mqh>
#include <SSReplay/Data/SSR_Mt5DataSource.mqh>
#include <SSReplay/Core/SSR_ReplayController.mqh>

input string InpSymbol = "";    // Symbol (empty = current chart symbol)
input int    InpSlot   = 9;     // Slot (9 keeps test symbols out of the way)
input int    InpBars   = 400;   // M1 bars to replay
input int    InpWarmup = 200;   // Warmup bars

int g_pass = 0, g_fail = 0, g_skip = 0;

void Check(const string n, const bool ok, const string d = "")
  { if(ok) { g_pass++; PrintFormat("  PASS  %s", n); }
    else   { g_fail++; PrintFormat("  FAIL  %s  %s", n, d); } }
void CheckEq(const string n, const long e, const long a)
  { Check(n, e == a, StringFormat("expected=%I64d actual=%I64d", e, a)); }
void Skip(const string n, const string w) { g_skip++; PrintFormat("  SKIP  %s  (%s)", n, w); }
void Section(const string t) { PrintFormat("--- %s", t); }

//+------------------------------------------------------------------+
//| SERIES_BARS_COUNT IS A REPORT, NOT A QUESTION.                   |
//|                                                                  |
//| MetaTrader builds a timeframe series lazily, when something      |
//| first asks for its bars. Until then it answers zero - not "no    |
//| bars" but "no series yet", and the two look identical.           |
//|                                                                  |
//| T3.6 read M5 and H1 cold, got zero for both, and reported that   |
//| the terminal had failed to derive higher timeframes from our M1  |
//| - the central claim of this entire architecture. Nothing had     |
//| failed. Nobody had asked.                                        |
//+------------------------------------------------------------------+
long SeriesBars(const string sym, const ENUM_TIMEFRAMES tf)
  {
   long n = 0;
   SeriesInfoInteger(sym, tf, SERIES_BARS_COUNT, n);
   if(n > 0)
      return n;
   MqlRates probe[];
   for(int i = 0; i < 10 && n <= 0; i++)
     {
      CopyRates(sym, tf, 0, 1, probe);        // touch it into existence
      SeriesInfoInteger(sym, tf, SERIES_BARS_COUNT, n);
      if(n <= 0)
         Sleep(100);
     }
   return n;
  }

//+------------------------------------------------------------------+
void OnStart()
  {
   string origin = (InpSymbol == "" ? _Symbol : InpSymbol);
   Print("=== SSR Phase 3 - Custom Symbol Engine ===");
   PrintFormat("    origin symbol: %s   slot: %d", origin, InpSlot);

   //================================================================
   Section("T3.1  naming rules (no terminal needed)");
   {
      string n = SSRReplaySymbolName("US30Cash", 1);
      Check("name is built from origin plus suffix", n == "US30Cash.SSR1", n);
      Check("name is recognised as ours", SSRIsReplaySymbol(n));
      Check("origin is not mistaken for ours", !SSRIsReplaySymbol("US30Cash"));

      //--- a very long origin must lose its TAIL, never the suffix,
      //--- or two different symbols could collide on one history
      string longn = SSRReplaySymbolName("AVERYLONGSYMBOLNAMEFROMSOMEBROKER", 2);
      Check("long name fits the cap", StringLen(longn) <= SSR_SYMBOL_NAME_MAX,
            StringFormat("%s len=%d", longn, StringLen(longn)));
      Check("suffix survived truncation", StringFind(longn, ".SSR2") >= 0, longn);
      Check("name is usable", SSRIsNameUsable(longn));

      //--- different slots must never collide
      Check("slots produce distinct names",
            SSRReplaySymbolName("US30Cash", 1) != SSRReplaySymbolName("US30Cash", 2));
   }

   //================================================================
   Section("T3.2  symbol lifecycle");

   CSSRCustomSymbolManager mgr;
   bool created = false;
   {
      created = mgr.Create(origin, InpSlot);
      if(!created)
        {
         Skip("lifecycle", "cannot create from " + origin + ": " + mgr.LastErrorText());
        }
      else
        {
         string sym = mgr.Symbol();
         Check("symbol created", mgr.IsCreated());
         Check("name matches the convention", sym == SSRReplaySymbolName(origin, InpSlot), sym);
         Check("symbol is selectable", SymbolInfoInteger(sym, SYMBOL_SELECT) != 0);

         //--- specification fidelity: these decide lot and P/L maths
         CheckEq("digits cloned",
                 SymbolInfoInteger(origin, SYMBOL_DIGITS),
                 SymbolInfoInteger(sym, SYMBOL_DIGITS));
         Check("point cloned",
               MathAbs(SymbolInfoDouble(origin, SYMBOL_POINT) -
                       SymbolInfoDouble(sym, SYMBOL_POINT)) < 1e-12);
         Check("tick size cloned",
               MathAbs(SymbolInfoDouble(origin, SYMBOL_TRADE_TICK_SIZE) -
                       SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE)) < 1e-12);
         Check("contract size cloned",
               MathAbs(SymbolInfoDouble(origin, SYMBOL_TRADE_CONTRACT_SIZE) -
                       SymbolInfoDouble(sym, SYMBOL_TRADE_CONTRACT_SIZE)) < 1e-8);

         //--- and the overrides the engine depends on
         CheckEq("trading disabled on the replay symbol",
                 SYMBOL_TRADE_MODE_DISABLED,
                 SymbolInfoInteger(sym, SYMBOL_TRADE_MODE));
         Check("floating spread enabled",
               SymbolInfoInteger(sym, SYMBOL_SPREAD_FLOAT) != 0);

         //--- The origin may be an expiring contract. Ours never is:
         //--- the user picks the replay window, and a window outside
         //--- an inherited contract life would be written into a
         //--- symbol the terminal treats as dead.
         CheckEq("replay symbol has no start date",
                 0, SymbolInfoInteger(sym, SYMBOL_START_TIME));
         CheckEq("replay symbol has no expiry",
                 0, SymbolInfoInteger(sym, SYMBOL_EXPIRATION_TIME));
        }
   }

   //================================================================
   Section("T3.3  writing history and truncating it");
   if(!created)
      Skip("history writes", "no symbol");
   else
     {
      string sym = mgr.Symbol();
      mgr.ClearAll();

      //--- synthetic bars: this test is about the WRITE path, so it must
      //--- not depend on what the broker happens to hold
      datetime t0 = D'2024.01.08 00:00';
      int      n  = 300;
      MqlRates bars[];
      ArrayResize(bars, n);
      double base = 38000.0;
      for(int i = 0; i < n; i++)
        {
         double o = base + i * 0.5;
         bars[i].time = t0 + i * 60;
         bars[i].open = o;   bars[i].high  = o + 1.0;
         bars[i].low  = o - 1.0; bars[i].close = o + 0.25;
         bars[i].tick_volume = 10; bars[i].spread = 2; bars[i].real_volume = 0;
        }

      Check("bars written", mgr.WriteBars(bars, n), mgr.LastErrorText());
      SSRPause(500);

      long m1 = mgr.BarCount(PERIOD_M1);
      Check("M1 series exists", m1 > 0, IntegerToString((int)m1));

      //--- the whole architecture in one assertion: we wrote ONLY M1,
      //--- and MetaTrader built the higher timeframes by itself
      long m5 = mgr.BarCount(PERIOD_M5);
      long h1 = mgr.BarCount(PERIOD_H1);
      Check("terminal derived M5 from our M1", m5 > 0, IntegerToString((int)m5));
      Check("terminal derived H1 from our M1", h1 > 0, IntegerToString((int)h1));
      PrintFormat("        M1=%d  M5=%d  H1=%d", (int)m1, (int)m5, (int)h1);

      //--- truncation must DELETE, and must report where it landed
      long cut_at = SSRToMsc(t0 + 150 * 60) + 20000;   // deliberately mid-bar
      long actual = mgr.Truncate(cut_at);
      Check("truncate reported an instant", actual > 0, IntegerToString(actual));
      Check("cut landed on a bar boundary",
            actual == SSRBarOpenMsc(cut_at, PERIOD_M1),
            StringFormat("actual=%s expected=%s", SSRFormatMsc(actual),
                         SSRFormatMsc(SSRBarOpenMsc(cut_at, PERIOD_M1))));
      SSRPause(500);

      MqlRates after[];
      int na = CopyRates(sym, PERIOD_M1, SSRToTime(actual), t0 + n * 60, after);
      CheckEq("nothing survives the cut", 0, MathMax(na, 0));

      MqlRates before[];
      int nb = CopyRates(sym, PERIOD_M1, t0, SSRToTime(actual) - 60, before);
      Check("history before the cut is intact", nb > 0, IntegerToString(nb));
     }

   //================================================================
   Section("T3.4  tick injection and the symbol clock");
   if(!created)
      Skip("tick injection", "no symbol");
   else
     {
      string sym = mgr.Symbol();
      mgr.ClearAll();

      datetime t0 = D'2024.01.08 00:00';
      MqlRates seed[];
      ArrayResize(seed, 60);
      for(int i = 0; i < 60; i++)
        {
         double o = 38000.0 + i * 0.5;
         seed[i].time = t0 + i * 60;
         seed[i].open = o; seed[i].high = o + 1.0;
         seed[i].low = o - 1.0; seed[i].close = o + 0.25;
         seed[i].tick_volume = 10; seed[i].spread = 2; seed[i].real_volume = 0;
        }
      mgr.WriteBars(seed, 60);
      SSRPause(300);

      long   base_msc = SSRToMsc(t0 + 60 * 60);
      double px       = 38050.0;
      MqlTick tk[];
      ArrayResize(tk, 20);
      for(int i = 0; i < 20; i++)
        {
         tk[i].time_msc    = base_msc + i * 1000;
         tk[i].time        = SSRToTime(tk[i].time_msc);
         tk[i].bid         = px + i * 0.5;
         tk[i].ask         = tk[i].bid + 0.2;
         tk[i].last        = tk[i].bid;
         tk[i].volume      = 1;
         tk[i].volume_real = 1.0;
         tk[i].flags       = TICK_FLAG_BID | TICK_FLAG_ASK;
        }

      Check("ticks injected", mgr.AddTicks(tk, 20), mgr.LastErrorText());
      SSRPause(500);

      SSRSymbolStats st;
      mgr.StatsInto(st);
      Check("ticks were accepted", st.ticks_added > 0, st.ToString());
      if(st.ticks_rejected > 0)
         PrintFormat("        NOTE %d ticks rejected - spike B3 territory",
                     (int)st.ticks_rejected);

      //--- the free win claimed in the design document: MetaTrader's own
      //--- clock for the symbol should equal the last injected tick
      long sym_clock = mgr.SymbolTimeMsc();
      long expect    = tk[19].time_msc;
      Check("symbol clock follows the injected tick",
            MathAbs(sym_clock - expect) <= 1000,
            StringFormat("symbol=%s injected=%s",
                         SSRFormatMscMs(sym_clock), SSRFormatMscMs(expect)));
     }

   //================================================================
   Section("T3.5  the sink refuses an out-of-order emit");
   {
      CSSRCustomSymbolSink sink;
      sink.SetSlot(InpSlot);
      if(!sink.Prepare(origin, 2, 0.01))
         Skip("sink ordering", "prepare failed: " + sink.LastErrorText());
      else
        {
         long base = SSRToMsc(D'2024.01.08 00:00');
         MqlTick a[], b[];
         ArrayResize(a, 2); ArrayResize(b, 2);
         for(int i = 0; i < 2; i++)
           {
            a[i].time_msc = base + 10000 + i * 1000;
            a[i].time = SSRToTime(a[i].time_msc);
            a[i].bid = 100.0; a[i].ask = 100.1; a[i].last = 100.0;
            a[i].volume = 1; a[i].volume_real = 1.0;
            a[i].flags = TICK_FLAG_BID | TICK_FLAG_ASK;

            b[i].time_msc = base + 1000 + i * 1000;      // BEFORE a
            b[i].time = SSRToTime(b[i].time_msc);
            b[i].bid = 100.0; b[i].ask = 100.1; b[i].last = 100.0;
            b[i].volume = 1; b[i].volume_real = 1.0;
            b[i].flags = TICK_FLAG_BID | TICK_FLAG_ASK;
           }

         Check("forward emit accepted", sink.EmitTicks(a, 2), sink.LastErrorText());
         Check("backward emit refused, not silently corrupting the bar",
               !sink.EmitTicks(b, 2));

         //--- but after a truncate the watermark must fall back, or the
         //--- engine could never replay the same range again
         long cut = sink.TruncateFrom(base);
         Check("truncate reported a cut", cut >= 0, IntegerToString(cut));
         Check("emit allowed again after truncate", sink.EmitTicks(b, 2),
               sink.LastErrorText());

         sink.Release();
        }
   }

   //================================================================
   Section("T3.6  end to end: broker data through the engine into MT5");
   {
      CSSRMt5DataSource    src;
      CSSRCustomSymbolSink sink;
      CSSRReplayController ctrl;

      sink.SetSlot(InpSlot);

      SSRDataRange range;
      range.Init();
      if(!src.Open(origin))
        {
         Skip("integration", "no broker M1 history for " + origin);
        }
      else
        {
         src.RangeInto(range);

         long win_end   = range.last_msc;
         long win_start = win_end - (long)InpBars * SSR_MSC_PER_MIN;
         long floor_msc = range.first_msc + (long)InpWarmup * SSR_MSC_PER_MIN;
         if(win_start < floor_msc)
            win_start = floor_msc;

         int    digits = (int)SymbolInfoInteger(origin, SYMBOL_DIGITS);
         double point  = SymbolInfoDouble(origin, SYMBOL_POINT);
         if(point <= 0.0) point = MathPow(10, -digits);

         ctrl.SetSymbolSpec(digits, point);
         ctrl.SetSpreadPoints(20);
         ctrl.SetTicksPerBar(8);
         ctrl.SetWarmupBars(InpWarmup);
         ctrl.SetDataMode(SSR_DATA_BROKER);
         ctrl.SetFidelity(SSR_FIDELITY_SYNTHETIC_TICK);
         ctrl.Attach(GetPointer(src), GetPointer(sink));

         bool loaded = ctrl.Load(origin, win_start, win_end);
         Check("engine loaded through the custom symbol sink", loaded,
               ctrl.LastErrorText());

         if(loaded)
           {
            string rsym = sink.ReplaySymbol();
            PrintFormat("        replay symbol: %s", rsym);

            Check("replay symbol is not the origin", rsym != origin);
            Check("warmup reached MetaTrader", sink.SeededBars() > 0,
                  IntegerToString((int)sink.SeededBars()));
            SSRPause(500);

            //--- the future must not exist on the replay symbol
            MqlRates fut[];
            int nf = CopyRates(rsym, PERIOD_M1,
                               SSRToTime(win_start), SSRToTime(win_end), fut);
            CheckEq("no replay data before play begins", 0, MathMax(nf, 0));

            ctrl.SetSpeedX100(SSR_SPEED_1);
            ctrl.Play();
            for(int i = 0; i < 180; i++)
               ctrl.Pump(1000);
            SSRPause(500);

            Check("ticks reached MetaTrader", sink.EmitTicks() > 0,
                  IntegerToString((int)sink.EmitTicks()));
            CheckEq("no guard violations", 0, ctrl.Violations());

            //--- the architecture's central claim, measured on real data:
            //--- we wrote M1 and ticks only, and the terminal built the
            //--- rest by itself
            //--- ASK BEFORE READING THE COUNT. SERIES_BARS_COUNT is
            //--- zero for a timeframe nothing has requested yet, and
            //--- this read it cold - then blamed the terminal for not
            //--- deriving what it had never been asked to derive.
            long rm1 = SeriesBars(rsym, PERIOD_M1);
            long rm5 = SeriesBars(rsym, PERIOD_M5);
            long rh1 = SeriesBars(rsym, PERIOD_H1);
            Check("M1 present on the replay symbol", rm1 > 0, IntegerToString((int)rm1));
            Check("M5 derived by the terminal",     rm5 > 0, IntegerToString((int)rm5));
            Check("H1 derived by the terminal",     rh1 > 0, IntegerToString((int)rh1));
            PrintFormat("        replay symbol bars  M1=%d M5=%d H1=%d",
                        (int)rm1, (int)rm5, (int)rh1);

            //--- nothing beyond the replay clock may exist in ANY timeframe
            long now = ctrl.Now();
            int leaked = 0;
            ENUM_TIMEFRAMES tfs[5] = {PERIOD_M1, PERIOD_M5, PERIOD_M15, PERIOD_H1, PERIOD_H4};
            for(int i = 0; i < 5; i++)
              {
               MqlRates ahead[];
               int na = CopyRates(rsym, tfs[i], SSRToTime(now) + 60,
                                  SSRToTime(now) + 86400, ahead);
               if(na > 0) leaked += na;
              }
            CheckEq("no future data in any timeframe", 0, leaked);

            //--- rewind must remove data, not hide it
            long back = now - 30 * SSR_MSC_PER_MIN;
            Check("backward seek", ctrl.SeekTo(back), ctrl.LastErrorText());
            SSRPause(500);
            MqlRates gone[];
            int ng = CopyRates(rsym, PERIOD_M1,
                               SSRToTime(ctrl.Now()) + 120, SSRToTime(win_end), gone);
            CheckEq("rewound data was deleted from MetaTrader", 0, MathMax(ng, 0));

            PrintFormat("        %s", sink.ToString());
           }

         ctrl.Release();
        }
   }

   //================================================================
   Section("T3.7  a leftover symbol is adopted, not fatal");
   {
      CSSRCustomSymbolManager a, b;
      if(!a.Create(origin, InpSlot))
         Skip("adoption", "cannot create from " + origin);
      else
        {
         //--- `a` deliberately does NOT tear down: this is what a crashed
         //--- session looks like from the next session's point of view
         CSSRCustomSymbolManager second;
         bool ok = second.Create(origin, InpSlot);
         Check("second create succeeds over the leftover", ok, second.LastErrorText());
         Check("it is the same symbol", second.Symbol() == a.Symbol());
         if(ok)
           {
            second.ClearAll();
            SSRPause(200);
            CheckEq("adopted symbol starts empty", 0, second.BarCount(PERIOD_M1));
           }
         second.Destroy();
        }
   }

   //================================================================
   Section("T3.8  teardown leaves nothing behind");
   {
      mgr.Destroy();
      SSRPause(300);

      string sym = SSRReplaySymbolName(origin, InpSlot);
      ResetLastError();
      long d = SymbolInfoInteger(sym, SYMBOL_DIGITS);
      int  e = GetLastError();
      Check("replay symbol is gone", e != 0 || d == 0,
            StringFormat("err=%d digits=%d", e, (int)d));
      CheckEq("no charts left on it", 0, mgr.OpenChartCount());
   }

   //================================================================
   PrintFormat("=== Phase 3: PASS=%d  FAIL=%d  SKIP=%d  ===> %s",
               g_pass, g_fail, g_skip, (g_fail == 0 ? "GREEN" : "RED"));
   Print("    if a run was interrupted, use SSR_Z_Cleanup to remove leftovers");
  }
//+------------------------------------------------------------------+
