//+------------------------------------------------------------------+
//|                                            SSR_T8_Navigation.mq5 |
//|                       SS Replay - Phase 8 Replay Navigation      |
//|                                                                  |
//|  Runs on the in-memory source, so it needs no broker. The claim  |
//|  under test is that rewinding RESTORES state rather than         |
//|  reconstructing it - which is the difference between a snapshot  |
//|  architecture and a hack.                                        |
//+------------------------------------------------------------------+
#property script_show_inputs

#include <SSReplay/Common/SSR_Types.mqh>
#include <SSReplay/Common/SSR_Time.mqh>
#include <SSReplay/Core/SSR_ReplayController.mqh>
#include <SSReplay/Core/Sources/SSR_MemoryDataSource.mqh>
#include <SSReplay/Core/Sinks/SSR_RecordingSink.mqh>
#include <SSReplay/Ui/SSR_Keys.mqh>

input datetime InpStart  = D'2024.01.08 00:00';
input int      InpBars   = 4320;
input double   InpBase   = 38000.0;
input int      InpWarmup = 120;

int g_pass = 0, g_fail = 0;
void Check(const string n, const bool ok, const string d = "")
  { if(ok) { g_pass++; PrintFormat("  PASS  %s", n); }
    else   { g_fail++; PrintFormat("  FAIL  %s  %s", n, d); } }
void CheckEq(const string n, const long e, const long a)
  { Check(n, e == a, StringFormat("expected=%I64d actual=%I64d", e, a)); }
void Section(const string t) { PrintFormat("--- %s", t); }

void BuildBars(MqlRates &out[], const datetime start, const int count, const double base)
  {
   ArrayResize(out, count);
   double p = base;
   for(int i = 0; i < count; i++)
     {
      double o = p, c = o + ((i % 11) - 5) * 0.5;
      out[i].time = start + i * 60;
      out[i].open = o; out[i].close = c;
      out[i].high = MathMax(o, c) + 1.0;
      out[i].low  = MathMin(o, c) - 1.0;
      out[i].tick_volume = 10; out[i].spread = 2; out[i].real_volume = 0;
      p = c;
     }
  }

long g_start = 0, g_end = 0;

bool Wire(CSSRReplayController &c, CSSRMemoryDataSource &s, CSSRRecordingSink &k)
  {
   MqlRates bars[];
   BuildBars(bars, InpStart, InpBars, InpBase);
   if(!s.LoadBars(bars, ArraySize(bars)))
      return false;
   k.Clear();
   c.SetSymbolSpec(2, 0.01);
   c.SetTicksPerBar(8);
   c.SetWarmupBars(InpWarmup);
   c.SetFidelity(SSR_FIDELITY_SYNTHETIC_TICK);
   c.Attach(GetPointer(s), GetPointer(k));
   return c.Load("TEST", g_start, g_end);
  }

//+------------------------------------------------------------------+
void OnStart()
  {
   g_start = SSRToMsc(InpStart) + (long)InpWarmup * SSR_MSC_PER_MIN;
   g_end   = g_start + 2000 * SSR_MSC_PER_MIN;
   Print("=== SSR Phase 8 - Replay Navigation ===");

   //================================================================
   Section("T8.1  keys that were left dead now mean something");
   {
      CheckEq("LEFT steps back",      SSR_CMD_STEP_BACK,    SSRKeyToCommand(SSR_VK_LEFT));
      CheckEq("PgUp steps back ten",  SSR_CMD_STEP_BACK_10, SSRKeyToCommand(SSR_VK_PGUP));
      CheckEq("J jumps",              SSR_CMD_JUMP,         SSRKeyToCommand(SSR_VK_J));
      CheckEq("B bookmarks",          SSR_CMD_BOOKMARK,     SSRKeyToCommand(SSR_VK_B));
      CheckEq("RIGHT still steps forward", SSR_CMD_STEP_FWD, SSRKeyToCommand(SSR_VK_RIGHT));
   }

   //================================================================
   Section("T8.2  the checkpoint ring");
   {
      CSSRSnapshotStore st;
      st.SetInterval(60000);
      Check("first checkpoint is always due", st.IsDue(g_start));

      SSRSnapshot s;
      for(int i = 0; i < 10; i++)
        {
         s.Init();
         s.version      = SSR_VERSION;
         s.taken_at_msc = g_start + (long)i * 60000;
         s.state.symbol = "TEST";
         s.clock.Configure(g_start, g_end);
         s.clock.now_msc = s.taken_at_msc;
         st.Checkpoint(s);
        }
      CheckEq("ten checkpoints held", 10, st.Count());

      SSRSnapshot found;
      Check("finds the one at or before a time",
            st.NearestAtOrBefore(g_start + 5 * 60000 + 30000, found));
      CheckEq("and it is the nearest earlier one",
              g_start + 5 * 60000, found.taken_at_msc);

      Check("nothing before the first", !st.NearestAtOrBefore(g_start - 1, found));

      //--- checkpoints describing a discarded future must go with it
      int dropped = st.DropFrom(g_start + 7 * 60000);
      Check("later checkpoints dropped", dropped == 3, IntegerToString(dropped));
      Check("and the newest survivor is found",
            st.NearestAtOrBefore(g_end, found));
      CheckEq("which is the one before the cut", g_start + 6 * 60000, found.taken_at_msc);
   }

   //================================================================
   Section("T8.3  THE POINT: rewind restores counters, does not reset them");
   {
      CSSRMemoryDataSource src;
      CSSRRecordingSink    sink;
      CSSRReplayController ctrl;
      Check("loaded", Wire(ctrl, src, sink));
      ctrl.SetSpeedX100(SSR_SPEED_1);
      ctrl.Play();

      //--- run far enough that several checkpoints have been taken
      for(int i = 0; i < 900; i++)
         ctrl.Pump(1000);

      long mark_time  = ctrl.Now();
      long mark_ticks = ctrl.TicksEmitted();
      Check("checkpoints were taken", ctrl.Snapshots().Count() > 1,
            ctrl.SnapshotText());
      Check("ticks were counted", mark_ticks > 0, IntegerToString(mark_ticks));

      //--- go on, then come back to exactly here
      for(int i = 0; i < 300; i++)
         ctrl.Pump(1000);
      Check("moved on", ctrl.Now() > mark_time);

      long back_bars = (ctrl.Now() - mark_time) / SSR_MSC_PER_MIN;
      Check("stepped back", ctrl.StepBackward((int)back_bars), ctrl.LastErrorText());

      //--- this is the assertion the whole phase exists for. A plain
      //--- seek zeroes the cursor; a restore brings the number back.
      Check("the tick count came BACK, not to zero",
            ctrl.TicksEmitted() > 0,
            StringFormat("%I64d after rewinding from %I64d",
                         ctrl.TicksEmitted(), mark_ticks));
      Check("and it is near where it was",
            ctrl.TicksEmitted() <= mark_ticks,
            StringFormat("%I64d vs %I64d", ctrl.TicksEmitted(), mark_ticks));

      CheckEq("nothing survives past the rewind point",
              0, sink.CountAfter(ctrl.Now()));
      CheckEq("the stream stayed ordered", 0, sink.OrderViolations());
      PrintFormat("        %s", ctrl.SnapshotText());
   }

   //================================================================
   Section("T8.4  forward jump goes through the bulk path");
   {
      CSSRMemoryDataSource src;
      CSSRRecordingSink    sink;
      CSSRReplayController ctrl;
      Wire(ctrl, src, sink);
      ctrl.Play();
      for(int i = 0; i < 60; i++)
         ctrl.Pump(1000);

      long before_ticks = sink.TickCount();
      long before_seed  = sink.SeedBarCount();
      long target = ctrl.Now() + 600 * SSR_MSC_PER_MIN;   // ten hours

      int bulk = ctrl.JumpForward(target);
      Check("jump reported bars written in bulk", bulk > 0, IntegerToString(bulk));
      CheckEq("clock landed on the target", target, ctrl.Now());

      //--- the whole point: ten hours of market must NOT arrive as ticks
      long tick_delta = sink.TickCount() - before_ticks;
      long seed_delta = sink.SeedBarCount() - before_seed;
      Check("bars went in bulk", seed_delta > 500, IntegerToString(seed_delta));
      Check("and far fewer ticks were emitted than bars",
            tick_delta < seed_delta,
            StringFormat("%I64d ticks vs %I64d bars", tick_delta, seed_delta));

      //--- but the bar CONTAINING the target must still be partial
      CheckEq("no data beyond the target", 0, sink.CountAfter(target));
      CheckEq("stream still ordered", 0, sink.OrderViolations());

      //--- and replay continues normally afterwards
      long after = ctrl.Now();
      for(int i = 0; i < 60; i++)
         ctrl.Pump(1000);
      Check("replay resumes after a jump", ctrl.Now() > after);
      CheckEq("still nothing in the future", 0, sink.CountAfter(ctrl.Now()));
   }

   //================================================================
   Section("T8.5  JumpTo picks the right direction");
   {
      CSSRMemoryDataSource src;
      CSSRRecordingSink    sink;
      CSSRReplayController ctrl;
      Wire(ctrl, src, sink);
      ctrl.Play();
      for(int i = 0; i < 600; i++)
         ctrl.Pump(1000);

      long here = ctrl.Now();

      Check("jump forward", ctrl.JumpTo(here + 120 * SSR_MSC_PER_MIN));
      Check("moved forward", ctrl.Now() > here);

      long far = ctrl.Now();
      Check("jump backward", ctrl.JumpTo(here));
      Check("moved back", ctrl.Now() < far);
      CheckEq("landed where asked", SSRBarOpenMsc(here, PERIOD_M1),
              SSRBarOpenMsc(ctrl.Now(), PERIOD_M1));

      Check("jumping to now is a no-op", ctrl.JumpTo(ctrl.Now()));

      //--- out of range must be clamped, not refused into an error
      Check("clamped past the end", ctrl.JumpTo(g_end + 999999999));
      Check("state is not ERROR", ctrl.Status() != SSR_STATE_ERROR,
            SSRStateName(ctrl.Status()));
   }

   //================================================================
   Section("T8.6  bookmarks");
   {
      CSSRMemoryDataSource src;
      CSSRRecordingSink    sink;
      CSSRReplayController ctrl;
      Wire(ctrl, src, sink);
      ctrl.Play();
      for(int i = 0; i < 300; i++)
         ctrl.Pump(1000);

      long marked = ctrl.Now();
      Check("bookmarked", ctrl.Bookmark("setup"));
      CheckEq("one bookmark", 1, ctrl.BookmarkCount());
      Check("label carries the time",
            StringFind(ctrl.BookmarkLabel(0), "setup") >= 0, ctrl.BookmarkLabel(0));

      for(int i = 0; i < 300; i++)
         ctrl.Pump(1000);
      Check("moved on", ctrl.Now() > marked);

      Check("returned to the bookmark", ctrl.GotoBookmark(0), ctrl.LastErrorText());
      CheckEq("landed on the marked bar",
              SSRBarOpenMsc(marked, PERIOD_M1), SSRBarOpenMsc(ctrl.Now(), PERIOD_M1));
      Check("a missing bookmark is refused", !ctrl.GotoBookmark(5));

      //--- and a jump before anything is loaded must say so rather than
      //--- clamping against an empty timeline
      CSSRReplayController bare;
      Check("jump before load is refused", !bare.JumpTo(g_start));
      Check("with a state error", bare.LastError() == SSR_ERR_INVALID_STATE,
            SSRErrName(bare.LastError()));
   }

   //================================================================
   Section("T8.7  save and resume position");
   {
      CSSRMemoryDataSource src;
      CSSRRecordingSink    sink;
      CSSRReplayController ctrl;
      Wire(ctrl, src, sink);
      ctrl.Play();
      for(int i = 0; i < 420; i++)
         ctrl.Pump(1000);

      long saved_at = ctrl.Now();
      Check("saved", ctrl.SavePosition("T8TEST"), ctrl.LastErrorText());
      Check("it exists", ctrl.HasSavedPosition("T8TEST"));

      SSRSnapshot peek;
      Check("readable without loading", ctrl.PeekPosition("T8TEST", peek));
      CheckEq("time round-tripped", saved_at, peek.taken_at_msc);
      Check("symbol round-tripped", peek.state.symbol == "TEST", peek.state.symbol);
      Check("a resumed position is never left running",
            peek.state.status != SSR_STATE_PLAYING, SSRStateName(peek.state.status));

      //--- a fresh engine over the same session must land on it
      CSSRMemoryDataSource src2;
      CSSRRecordingSink    sink2;
      CSSRReplayController ctrl2;
      Wire(ctrl2, src2, sink2);
      CheckEq("fresh engine starts at the window start", g_start, ctrl2.Now());
      Check("resumed", ctrl2.ResumePosition("T8TEST"), ctrl2.LastErrorText());
      CheckEq("and landed where the other stopped",
              SSRBarOpenMsc(saved_at, PERIOD_M1),
              SSRBarOpenMsc(ctrl2.Now(), PERIOD_M1));

      CSSRPositionFile pf;
      pf.Remove("T8TEST");
      Check("cleaned up", !ctrl.HasSavedPosition("T8TEST"));
   }

   //================================================================
   Section("T8.8  restart");
   {
      CSSRMemoryDataSource src;
      CSSRRecordingSink    sink;
      CSSRReplayController ctrl;
      Wire(ctrl, src, sink);
      ctrl.Play();
      for(int i = 0; i < 400; i++)
         ctrl.Pump(1000);
      ctrl.Bookmark("x");

      int seeded = sink.SeedBarCount();
      Check("restarted", ctrl.Restart());
      CheckEq("back at the start", g_start, ctrl.Now());
      Check("state is READY", ctrl.Status() == SSR_STATE_READY, SSRStateName(ctrl.Status()));
      CheckEq("replay stream cleared", 0, sink.CountAfter(g_start));
      CheckEq("warmup survived", seeded, sink.SeedBarCount());
      CheckEq("checkpoints cleared", 0, ctrl.Snapshots().Count());
      //--- but the user's bookmark is theirs, and the session is the
      //--- same one: restarting must not throw their notes away
      CheckEq("the bookmark survived the restart", 1, ctrl.BookmarkCount());

      //--- a genuinely new session does clear them
      Wire(ctrl, src, sink);
      CheckEq("a new session starts with none", 0, ctrl.BookmarkCount());
   }

   //================================================================
   PrintFormat("=== Phase 8: PASS=%d  FAIL=%d  ===> %s",
               g_pass, g_fail, (g_fail == 0 ? "GREEN" : "RED"));
  }
//+------------------------------------------------------------------+
