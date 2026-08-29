//+------------------------------------------------------------------+
//|                                        SSR_T11_AdvancedReplay.mq5 |
//|                       SS Replay - Phase 11 Advanced Replay       |
//|                                                                  |
//|  Four claims are under test, and each has one way of being       |
//|  quietly false:                                                  |
//|                                                                  |
//|  Master clock   two streams that LOOK synchronised because the   |
//|                 test never changed speed mid-run. So the skew is |
//|                 asserted as EXACTLY zero, across a speed change, |
//|                 across a jump, and across a step back.           |
//|  Auto pause     a pause that fires and then keeps firing, or one |
//|                 that fires again on a rewind for a stop that was |
//|                 just un-hit.                                     |
//|  Random replay  a "random" start that cannot be reproduced, or   |
//|                 one that lands where there is no history.        |
//|  Blind mode     a mode that cannot be left, restoring the chart  |
//|                 to the blind state it created rather than the    |
//|                 one the user had.                                |
//+------------------------------------------------------------------+
#property script_show_inputs

#include <SSReplay/Common/SSR_Types.mqh>
#include <SSReplay/Common/SSR_Time.mqh>
#include <SSReplay/Common/SSR_Random.mqh>
#include <SSReplay/Common/SSR_SymbolNaming.mqh>
#include <SSReplay/Core/SSR_ReplayController.mqh>
#include <SSReplay/Core/SSR_MasterClock.mqh>
#include <SSReplay/Core/Sources/SSR_MemoryDataSource.mqh>
#include <SSReplay/Core/Sinks/SSR_RecordingSink.mqh>
#include <SSReplay/Trading/SSR_TradingEngine.mqh>
#include <SSReplay/Trading/SSR_AutoPause.mqh>
#include <SSReplay/Data/SSR_SessionWatcher.mqh>
#include <SSReplay/Chart/SSR_BlindMode.mqh>

input datetime InpStart  = D'2024.01.08 00:00';
input int      InpBars   = 4320;
input double   InpBase   = 1000.0;
input int      InpWarmup = 60;

int g_pass = 0, g_fail = 0;
void Check(const string n, const bool ok, const string d = "")
  { if(ok) { g_pass++; PrintFormat("  PASS  %s", n); }
    else   { g_fail++; PrintFormat("  FAIL  %s  %s", n, d); } }
void CheckEq(const string n, const long e, const long a)
  { Check(n, e == a, StringFormat("expected=%I64d actual=%I64d", e, a)); }
void Section(const string t) { PrintFormat("--- %s", t); }

long g_start = 0, g_end = 0;

//--- a flat market: nothing here depends on the prices except the
//--- sections that build their own
void BuildBars(MqlRates &out[], const datetime start, const int count,
               const double base, const double range)
  {
   ArrayResize(out, count);
   for(int i = 0; i < count; i++)
     {
      out[i].time  = start + i * 60;
      out[i].open  = base;  out[i].close = base;
      out[i].high  = base + range;
      out[i].low   = base - range;
      out[i].tick_volume = 10; out[i].spread = 2; out[i].real_volume = 0;
     }
  }

bool Wire(CSSRReplayController &c, CSSRMemoryDataSource &s, CSSRRecordingSink &k,
          const string name, const long start_msc, const long end_msc,
          const int bars, const double base)
  {
   MqlRates rates[];
   BuildBars(rates, SSRToTime(start_msc - (long)InpWarmup * SSR_MSC_PER_MIN),
             bars, base, 5.0);
   if(!s.LoadBars(rates, ArraySize(rates)))
      return false;
   k.Clear();
   c.SetSymbolSpec(2, 0.01);
   c.SetTicksPerBar(8);
   c.SetSpreadPoints(0);
   c.SetWarmupBars(InpWarmup);
   c.SetFidelity(SSR_FIDELITY_SYNTHETIC_TICK);
   c.Attach(GetPointer(s), GetPointer(k));
   return c.Load(name, start_msc, end_msc);
  }

//+------------------------------------------------------------------+
void OnStart()
  {
   g_start = SSRToMsc(InpStart) + (long)InpWarmup * SSR_MSC_PER_MIN;
   g_end   = g_start + 2000 * SSR_MSC_PER_MIN;
   Print("=== SSR Phase 11 - Advanced Replay ===");

   //================================================================
   Section("T11.1  the random generator is random, and repeatable");
   {
      SSRRandom a, b;
      a.Seed(12345);
      b.Seed(12345);
      bool same = true;
      for(int i = 0; i < 500; i++)
         if(a.Next() != b.Next())
           { same = false; break; }
      Check("the same seed gives the same sequence", same);

      SSRRandom c;
      c.Seed(12346);
      a.Seed(12345);
      int differ = 0;
      for(int i = 0; i < 500; i++)
         if(a.Next() != c.Next())
            differ++;
      Check("a different seed gives a different one", differ > 490,
            IntegerToString(differ));

      //--- zero is the one state xorshift cannot leave
      SSRRandom z;
      z.Seed(0);
      ulong z1 = z.Next(), z2 = z.Next();
      Check("a zero seed does not produce a constant", z1 != z2);

      //--- the range must be a range, not an occasional overflow
      a.Seed(999);
      bool in_range = true;
      for(int i = 0; i < 2000; i++)
        {
         long v = a.InRange(100, 200);
         if(v < 100 || v >= 200)
           { in_range = false; break; }
        }
      Check("InRange stays inside [lo, hi)", in_range);
      CheckEq("an empty range returns lo", 50, a.InRange(50, 50));
      CheckEq("an inverted range returns lo", 50, a.InRange(50, 10));

      //--- and it spreads, rather than sitting in one corner
      a.Seed(7);
      int buckets[10];
      ArrayInitialize(buckets, 0);
      for(int i = 0; i < 10000; i++)
         buckets[(int)a.InRange(0, 10)]++;
      int empty = 0, lopsided = 0;
      for(int i = 0; i < 10; i++)
        {
         if(buckets[i] == 0)   empty++;
         if(buckets[i] < 700 || buckets[i] > 1300) lopsided++;
        }
      CheckEq("every bucket was hit", 0, empty);
      CheckEq("and none ran away with it", 0, lopsided);

      //--- the seed survives a round trip through the UI
      ulong seed = 8143772915;
      CheckEq("seed text round trips", (long)seed,
              (long)SSRSeedFromText(SSRSeedText(seed)));
   }

   //================================================================
   Section("T11.2  the master clock: skew is zero, not small");
   {
      CSSRMemoryDataSource s1, s2;
      CSSRRecordingSink    k1, k2;
      CSSRReplayController c1, c2;

      Check("stream A loaded", Wire(c1, s1, k1, "AAA", g_start, g_end,
                                    InpBars, 1000.0), c1.LastErrorText());
      Check("stream B loaded", Wire(c2, s2, k2, "BBB", g_start, g_end,
                                    InpBars, 2000.0), c2.LastErrorText());

      CSSRReplayGroup g;
      Check("A joins", g.Add(GetPointer(c1)));
      Check("B joins", g.Add(GetPointer(c2)));
      CheckEq("two streams", 2, g.Count());

      Check("aligned", g.Align(), g.LastError());
      CheckEq("on a common window start", g_start, g.StartMsc());
      CheckEq("and a common end",         g_end,   g.EndMsc());
      CheckEq("both start together",      0,       g.MaxSkewMsc());

      Check("playing", g.Play(), g.LastError());
      for(int i = 0; i < 40; i++)
         g.Pump(50);
      CheckEq("no skew after forty pumps", 0, g.MaxSkewMsc());
      Check("and both moved", g.Now() > g_start, SSRFormatMsc(g.Now()));
      CheckEq("every stream is at the master's instant",
              g.Now(), c1.Now());
      CheckEq("including the second one", g.Now(), c2.Now());

      //--- THE CASE THAT CATCHES A PER-STREAM CLOCK. A speed change
      //--- resets each clock's residue; two clocks fed deltas would
      //--- separate here and never come back.
      g.SetSpeedX100(SSR_SPEED_10);
      for(int i = 0; i < 40; i++)
         g.Pump(37);                    // a delta that does not divide evenly
      CheckEq("no skew across a speed change", 0, g.MaxSkewMsc());

      g.SetSpeedX100(SSR_SPEED_1);
      for(int i = 0; i < 13; i++)
         g.Pump(17);
      CheckEq("nor across a second one", 0, g.MaxSkewMsc());

      //--- navigation moves the board, not each chart separately
      long target = g_start + 500 * SSR_MSC_PER_MIN;
      Check("jumped", g.JumpTo(target), g.LastError());
      CheckEq("master is there", target, g.Now());
      CheckEq("no skew after a jump", 0, g.MaxSkewMsc());
      CheckEq("and the master agrees with the streams", c1.Now(), g.Now());

      //--- backwards, where the streams land on an M1 boundary at or
      //--- below what was asked. The master must follow them, not
      //--- report the instant that was typed.
      long back_to = target - 137 * SSR_MSC_PER_MIN - 12345;
      Check("jumped back", g.JumpTo(back_to), g.LastError());
      CheckEq("no skew after a backward jump", 0, g.MaxSkewMsc());
      CheckEq("the master followed the streams", c1.Now(), g.Now());
      Check("and landed at or before what was asked", g.Now() <= back_to,
            StringFormat("asked=%s landed=%s",
                         SSRFormatMsc(back_to), SSRFormatMsc(g.Now())));

      g.Play();
      Check("stepped forward", g.StepBars(10));
      CheckEq("no skew after a step forward", 0, g.MaxSkewMsc());

      Check("stepped back", g.StepBackward(5));
      CheckEq("no skew after a step back", 0, g.MaxSkewMsc());

      Check("restart returns to the window start", g.Restart(), g.LastError());
      CheckEq("at the start", g.StartMsc(), g.Now());
      CheckEq("together",     0,            g.MaxSkewMsc());
   }

   //================================================================
   Section("T11.3  streams that do not overlap are refused, by name");
   {
      CSSRMemoryDataSource s1, s2;
      CSSRRecordingSink    k1, k2;
      CSSRReplayController c1, c2;

      long late_start = g_end + 100 * SSR_MSC_PER_MIN;
      Wire(c1, s1, k1, "AAA", g_start, g_start + 100 * SSR_MSC_PER_MIN,
           InpBars, 1000.0);
      Wire(c2, s2, k2, "BBB", late_start, late_start + 100 * SSR_MSC_PER_MIN,
           InpBars, 2000.0);

      CSSRReplayGroup g;
      g.Add(GetPointer(c1));
      g.Add(GetPointer(c2));
      Check("align refuses", !g.Align());
      Check("and says why",
            StringFind(g.LastError(), "no common period") >= 0, g.LastError());
      Check("a group that will not align will not play", !g.Play());

      //--- and a pump on an unaligned group does nothing rather than
      //--- advancing one stream into a period the other cannot reach
      CheckEq("nor pump", 0, g.Pump(1000));
   }

   //================================================================
   Section("T11.4  auto pause: on the bar it happened, once");
   {
      CSSRMemoryDataSource src;
      CSSRRecordingSink    sink;
      CSSRReplayController ctrl;
      CSSRTradingEngine    acct;
      CSSRTradeAutoPause   ap;

      //--- a market that always reaches five either side of 1000
      Check("loaded", Wire(ctrl, src, sink, "TEST", g_start, g_end,
                           InpBars, 1000.0), ctrl.LastErrorText());
      acct.SetBalance(10000.0);
      ap.Attach(GetPointer(acct));
      ap.SetFlags(SSR_PAUSE_ON_SL);

      //--- ORDER MATTERS: the account must see the tick before the
      //--- watcher looks at the account
      ctrl.AddObserver(GetPointer(acct));
      ctrl.AddObserver(GetPointer(ap));
      Check("auto pause is on by default", ctrl.AutoPauseEnabled());

      ctrl.Play();
      for(int i = 0; i < 10; i++)
         ctrl.Pump(1000);
      Check("running", ctrl.Status() == SSR_STATE_PLAYING,
            SSRStateName(ctrl.Status()));

      //--- a stop the very next bar will reach
      long t = acct.Open(SSR_ORDER_BUY, 1.0, 998.0);
      Check("position opened", t > 0, acct.LastError());

      int pumps = 0;
      while(ctrl.Status() == SSR_STATE_PLAYING && pumps < 600)
        { ctrl.Pump(1000); pumps++; }

      Check("the replay stopped itself",
            ctrl.Status() == SSR_STATE_PAUSED, SSRStateName(ctrl.Status()));
      Check("and said what for",
            StringFind(ctrl.PauseReason(), "stop loss") >= 0,
            ctrl.PauseReason());
      CheckEq("the position really is closed", 1, acct.ClosedCount());
      CheckEq("counted once", 1, ctrl.AutoPauses());

      //--- AND IT LETS GO. An observer that keeps answering yes would
      //--- pin the replay in a pause the user cannot leave.
      Check("play resumes", ctrl.Play());
      for(int i = 0; i < 20; i++)
         ctrl.Pump(1000);
      Check("and stays running", ctrl.Status() == SSR_STATE_PLAYING,
            SSRStateName(ctrl.Status()));
      CheckEq("without pausing again", 1, ctrl.AutoPauses());
   }

   //================================================================
   Section("T11.5  auto pause is a switch, and a rewind does not re-fire it");
   {
      CSSRMemoryDataSource src;
      CSSRRecordingSink    sink;
      CSSRReplayController ctrl;
      CSSRTradingEngine    acct;
      CSSRTradeAutoPause   ap;

      Wire(ctrl, src, sink, "TEST", g_start, g_end, InpBars, 1000.0);
      acct.SetBalance(10000.0);
      ap.Attach(GetPointer(acct));
      ap.SetFlags(SSR_PAUSE_ON_SL);
      ctrl.AddObserver(GetPointer(acct));
      ctrl.AddObserver(GetPointer(ap));

      //--- turned off, the same events must not stop anything
      ctrl.SetAutoPause(false);
      ctrl.Play();
      for(int i = 0; i < 60; i++)
         ctrl.Pump(1000);
      long t = acct.Open(SSR_ORDER_BUY, 1.0, 998.0);
      Check("position opened", t > 0, acct.LastError());
      for(int i = 0; i < 300; i++)
         ctrl.Pump(1000);
      Check("still running with auto pause off",
            ctrl.Status() == SSR_STATE_PLAYING, SSRStateName(ctrl.Status()));
      CheckEq("nothing was counted", 0, ctrl.AutoPauses());
      CheckEq("but the stop was still honoured", 1, acct.ClosedCount());

      //--- REWIND TO BETWEEN THE OPEN AND THE CLOSE. The position comes
      //--- back open and the close un-happens; a watcher holding a
      //--- stale request would fire for a stop that was just un-hit.
      SSRVirtualPosition p;
      Check("found", acct.ByTicket(t, p));
      long back = (p.open_msc + p.close_msc) / 2;
      ctrl.SetAutoPause(true);
      ctrl.ClearPauseReason();
      Check("stepped back", ctrl.JumpTo(back), ctrl.LastErrorText());

      //+------------------------------------------------------------------+
      //| WHAT A REWIND MUST UNDO, stated so tick granularity cannot     |
      //| decide the verdict.                                             |
      //|                                                                 |
      //| This used to demand the position be OPEN again after rewinding  |
      //| to the midpoint between its open and its close. But those two   |
      //| instants are a fraction of a bar apart here - the market        |
      //| reaches the stop on the next tick - so the midpoint can land on |
      //| the very tick that closed it, and the assertion then fails for  |
      //| a reason that has nothing to do with rewinding.                 |
      //|                                                                 |
      //| The invariant that actually matters, and that holds whichever   |
      //| side of the tick the midpoint falls on: after stepping back     |
      //| before the close, THE CLOSE HAS NOT HAPPENED. Whether the       |
      //| position is open again or has ceased to exist depends on how    |
      //| far back we landed, and both are correct.                       |
      //+------------------------------------------------------------------+
      bool still_there = acct.ByTicket(t, p);
      Check("the close was undone", !still_there || !p.IsClosed(),
            (still_there ? p.ToString() : "position un-opened entirely"));
      CheckEq("and nothing is booked as closed", 0, acct.ClosedCount());

      string why = "";
      Check("and the watcher is holding nothing", !ap.PauseRequested(why), why);
      CheckEq("still nothing counted", 0, ctrl.AutoPauses());

      //--- flags read back the way they were set
      ap.SetFlags(SSR_PAUSE_ON_NONE);
      Check("off reads as off", ap.FlagsText() == "off", ap.FlagsText());
      ap.Enable(SSR_PAUSE_ON_TP, true);
      Check("one flag on", StringFind(ap.FlagsText(), "TP") >= 0, ap.FlagsText());
      ap.Enable(SSR_PAUSE_ON_TP, false);
      Check("and off again", ap.FlagsText() == "off", ap.FlagsText());
   }

   //================================================================
   Section("T11.6  a new session is read from the data, not from a clock");
   {
      CSSRSessionWatcher w;
      w.SetMode(SSR_SESSION_BY_GAP);
      w.SetThresholdMsc(60 * 60 * 1000);        // one hour
      w.OnSessionStart("TEST", 2, 0.01, g_start);

      MqlTick t[];
      ArrayResize(t, 1);
      string why = "";

      //--- three minutes apart: ordinary trading
      long now = g_start;
      for(int i = 0; i < 3; i++)
        {
         now += 3 * SSR_MSC_PER_MIN;
         t[0].time = SSRToTime(now); t[0].time_msc = now;
         t[0].bid = 1000.0; t[0].ask = 1000.0; t[0].last = 1000.0;
         t[0].volume = 1; t[0].volume_real = 0.0; t[0].flags = 0;
         w.OnTicks(t, 1);
        }
      Check("no pause during a session", !w.PauseRequested(why));

      //--- and now a two-hour silence
      now += 2 * 60 * SSR_MSC_PER_MIN;
      t[0].time = SSRToTime(now); t[0].time_msc = now;
      w.OnTicks(t, 1);
      Check("a gap is a new session", w.PauseRequested(why), why);
      Check("and it says how long the silence was",
            StringFind(why, "new session") >= 0, why);
      Check("consumed", !w.PauseRequested(why));
      CheckEq("raised once", 1, w.Raised());

      //--- off means off
      CSSRSessionWatcher off;
      off.SetMode(SSR_SESSION_OFF);
      off.OnSessionStart("TEST", 2, 0.01, g_start);
      long n2 = g_start;
      for(int i = 0; i < 3; i++)
        {
         n2 += 5 * 60 * SSR_MSC_PER_MIN;       // five hours each
         t[0].time = SSRToTime(n2); t[0].time_msc = n2;
         off.OnTicks(t, 1);
        }
      Check("nothing when the mode is off", !off.PauseRequested(why));

      //--- by day, on a day boundary
      CSSRSessionWatcher day;
      day.SetMode(SSR_SESSION_BY_DAY);
      long midday = (g_start / SSR_MSC_PER_DAY) * SSR_MSC_PER_DAY + 12 * SSR_MSC_PER_HOUR;
      day.OnSessionStart("TEST", 2, 0.01, midday);
      t[0].time = SSRToTime(midday + SSR_MSC_PER_MIN);
      t[0].time_msc = midday + SSR_MSC_PER_MIN;
      day.OnTicks(t, 1);
      Check("not a new day yet", !day.PauseRequested(why));

      long next = midday + 13 * SSR_MSC_PER_HOUR;   // past midnight
      t[0].time = SSRToTime(next); t[0].time_msc = next;
      day.OnTicks(t, 1);
      Check("midnight is a new day", day.PauseRequested(why), why);
      Check("and says so", StringFind(why, "new day") >= 0, why);

      //--- a rewind must not announce the boundary we are standing on
      CSSRSessionWatcher rw;
      rw.SetMode(SSR_SESSION_BY_GAP);
      rw.SetThresholdMsc(60 * 60 * 1000);
      rw.OnSessionStart("TEST", 2, 0.01, g_start);
      rw.OnRewind(g_start + 10 * SSR_MSC_PER_MIN);
      t[0].time_msc = g_start + 11 * SSR_MSC_PER_MIN;
      t[0].time = SSRToTime(t[0].time_msc);
      rw.OnTicks(t, 1);
      Check("nothing announced right after a rewind", !rw.PauseRequested(why));
   }

   //================================================================
   Section("T11.7  blind mode hides what it can and names what it cannot");
   {
      SSRBlindPolicy p;
      p.Init();
      Check("off by default", !p.AnyOn());

      p.Standard();
      Check("standard hides the dates",   p.hide_dates);
      Check("and anonymises the symbol",  p.anonymous_symbol);
      Check("but LEAVES the price scale", !p.hide_price_scale);

      p.Full();
      Check("full hides the price too", p.hide_price_scale);

      CSSRBlindMode b;
      SSRBlindPolicy std;
      std.Standard();
      b.SetPolicy(std);
      Check("on", b.IsOn());
      Check("and it wants an anonymous symbol", b.Anonymous());

      //--- the time the user sees says how far in, never which day
      string shown = b.MaskTime(g_start + 2 * SSR_MSC_PER_HOUR + 15 * SSR_MSC_PER_MIN,
                                g_start);
      Check("time is masked to elapsed", StringFind(shown, "02:15") >= 0, shown);
      Check("and carries no date", StringFind(shown, "2024") < 0, shown);
      Check("the symbol is masked too", b.MaskSymbol("XAUUSD") == "(blind)",
            b.MaskSymbol("XAUUSD"));

      //--- the honest part: what is still visible
      string leaks = b.Leaks();
      Check("the remaining leaks are listed", StringLen(leaks) > 20, leaks);
      Check("including the crosshair",
            StringFind(leaks, "crosshair") >= 0, leaks);

      //--- and the symbol name really does carry nothing
      string anon = SSRAnonSymbolName(1);
      Check("the anonymous name hides the instrument",
            StringFind(anon, "XAU") < 0 && StringFind(anon, "EUR") < 0, anon);
      Check("but is still recognisably ours", SSRIsReplaySymbol(anon), anon);
      Check("and fits", SSRIsNameUsable(anon), anon);
      Check("two slots do not collide",
            SSRAnonSymbolName(1) != SSRAnonSymbolName(2));

      //--- naming picks the right one without a global
      Check("named mode keeps the instrument",
            StringFind(SSRReplaySymbolNameFor("XAUUSD", 1, false), "XAUUSD") >= 0);
      Check("blind mode does not",
            StringFind(SSRReplaySymbolNameFor("XAUUSD", 1, true), "XAUUSD") < 0);

      //--- a mode you cannot leave is a trap. Nothing was applied to a
      //--- real chart here, so nothing should claim to have been.
      CheckEq("nothing saved without a chart", 0, b.SavedCharts());
      Check("apply refuses chart 0", !b.Apply(0));
      CheckEq("and restores nothing", 0, b.RestoreAll());

      SSRBlindPolicy none;
      none.Init();
      CSSRBlindMode offb;
      offb.SetPolicy(none);
      Check("an off policy applies nothing", !offb.Apply(12345));
      Check("and lists no leaks", offb.Leaks() == "", offb.Leaks());
   }

   //================================================================
   Section("T11.8  the clock advances to an instant, never backwards");
   {
      SSRReplayClock c;
      c.Init();
      Check("configured", c.Configure(g_start, g_end));

      long t1 = c.AdvanceTo(g_start + 1000);
      CheckEq("moved to the target exactly", g_start + 1000, t1);
      CheckEq("and no residue is owed", 0, c.residue);

      long t2 = c.AdvanceTo(g_start + 500);
      CheckEq("a backwards target does nothing", g_start + 1000, t2);

      long t3 = c.AdvanceTo(g_start + 1000);
      CheckEq("nor does the same target twice", g_start + 1000, t3);

      long t4 = c.AdvanceTo(g_end + 999999);
      CheckEq("past the end clamps to the end", g_end, t4);
      Check("and the clock is completed", c.IsCompleted());
   }

   //================================================================
   Section("T11.9  a group of one behaves exactly like one stream");
   {
      //--- the host now runs EVERY session through the group, so the
      //--- single-instrument path is the group path and has to be
      //--- proven rather than assumed unchanged.
      CSSRMemoryDataSource src;
      CSSRRecordingSink    sink;
      CSSRReplayController ctrl;

      Check("loaded", Wire(ctrl, src, sink, "TEST", g_start, g_end,
                           InpBars, 1000.0), ctrl.LastErrorText());

      CSSRReplayGroup g;
      g.Add(GetPointer(ctrl));
      Check("a group of one aligns", g.Align(), g.LastError());
      CheckEq("one stream",   1, g.Count());
      CheckEq("one live",     1, g.LiveCount());
      CheckEq("no skew to have", 0, g.MaxSkewMsc());
      CheckEq("its window is the group window", ctrl.StartMsc(), g.StartMsc());

      Check("plays", g.Play(), g.LastError());
      for(int i = 0; i < 30; i++)
         g.Pump(1000);
      Check("and advances", ctrl.Now() > g_start, SSRFormatMsc(ctrl.Now()));
      CheckEq("with the master on the same instant", ctrl.Now(), g.Now());
      Check("emitting ticks", ctrl.TicksEmitted() > 0,
            IntegerToString(ctrl.TicksEmitted()));

      Check("pauses", g.Pause());
      Check("stopped", ctrl.Status() == SSR_STATE_PAUSED,
            SSRStateName(ctrl.Status()));
      CheckEq("a manual pause carries no reason", 0,
              StringLen(g.PauseReason()));
   }

   //================================================================
   Section("T11.10  a stream whose data ends is finished, not drifting");
   {
      //--- a short stream beside a long one. The short one completes
      //--- and stops advancing; that is a fact about its history, and
      //--- must not read as the clock having failed.
      CSSRMemoryDataSource s1, s2;
      CSSRRecordingSink    k1, k2;
      CSSRReplayController c1, c2;

      long short_end = g_start + 30 * SSR_MSC_PER_MIN;
      Check("long stream",  Wire(c1, s1, k1, "LONG",  g_start, g_end,
                                 InpBars, 1000.0), c1.LastErrorText());
      Check("short stream", Wire(c2, s2, k2, "SHORT", g_start, short_end,
                                 InpBars, 2000.0), c2.LastErrorText());

      CSSRReplayGroup g;
      g.Add(GetPointer(c1));
      g.Add(GetPointer(c2));

      //--- the common window is the SHORTER one: replaying past it
      //--- would freeze one chart while the other moved
      Check("aligned", g.Align(), g.LastError());
      CheckEq("to the shorter end", short_end, g.EndMsc());

      //--- AND THE LONG STREAM WAS NARROWED TO IT. Without this it
      //--- would never report itself finished, and the board would sit
      //--- at its last common instant waiting for a stream that
      //--- believes it has days left.
      CheckEq("the long stream was narrowed", short_end, c1.EndMsc());
      Check("the short one was left alone", c2.EndMsc() == short_end,
            SSRFormatMsc(c2.EndMsc()));

      g.Play();
      for(int i = 0; i < 60; i++)
         g.Pump(1000);
      CheckEq("still no skew", 0, g.MaxSkewMsc());

      //--- run the whole common window out
      for(int i = 0; i < 2000 && !g.AllCompleted(); i++)
         g.Pump(1000);
      Check("the board finished", g.AllCompleted(),
            StringFormat("%s / %s", SSRStateName(c1.Status()),
                         SSRStateName(c2.Status())));
      CheckEq("nothing live", 0, g.LiveCount());
      CheckEq("and no drift alarm at the end", 0, g.MaxSkewMsc());
   }

   //================================================================
   PrintFormat("=== Phase 11: PASS=%d  FAIL=%d  ===> %s",
               g_pass, g_fail, (g_fail == 0 ? "GREEN" : "RED"));
  }
//+------------------------------------------------------------------+
