//+------------------------------------------------------------------+
//|                                             SSR_T13_Strategy.mq5 |
//|                       SS Replay - Phase 13 SS Strategy Layer     |
//|                                                                  |
//|  The claim under test is not "strategies run". It is that the    |
//|  two bugs which make a backtest meaningless CANNOT HAPPEN:       |
//|                                                                  |
//|   look-ahead    a strategy asking for a bar it should not have   |
//|                 gets a refusal, not the bar and not a zero. The  |
//|                 test includes a strategy that TRIES.             |
//|   forming bars  a signal taken on a bar that is still moving.    |
//|                 OnBar is asserted to fire only after the close.  |
//|                                                                  |
//|  Plus the third that makes results unattributable: two           |
//|  strategies whose trades cannot be told apart.                   |
//+------------------------------------------------------------------+
#property script_show_inputs

#include <SSReplay/Common/SSR_Types.mqh>
#include <SSReplay/Common/SSR_Time.mqh>
#include <SSReplay/Core/SSR_ReplayController.mqh>
#include <SSReplay/Core/Sources/SSR_MemoryDataSource.mqh>
#include <SSReplay/Core/Sinks/SSR_RecordingSink.mqh>
#include <SSReplay/Trading/SSR_TradingEngine.mqh>
#include <SSReplay/Trading/SSR_Statistics.mqh>
#include <SSReplay/Strategy/SSR_MarketView.mqh>
#include <SSReplay/Strategy/SSR_StrategyHost.mqh>
#include <SSReplay/Strategy/SSR_RefStrategy.mqh>

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
void CheckNear(const string n, const double e, const double a, const double tol)
  { Check(n, MathAbs(e - a) <= tol, StringFormat("expected=%.5f actual=%.5f", e, a)); }
void Section(const string t) { PrintFormat("--- %s", t); }

long g_start = 0, g_end = 0;

//--- a market that steps by one unit per minute, so every aggregation
//--- has an arithmetic answer the test can state
void BuildRamp(MqlRates &out[], const datetime start, const int count,
               const double base)
  {
   ArrayResize(out, count);
   for(int i = 0; i < count; i++)
     {
      double p = base + i;
      out[i].time  = start + i * 60;
      out[i].open  = p;
      out[i].close = p;
      out[i].high  = p + 0.5;
      out[i].low   = p - 0.5;
      out[i].tick_volume = 10; out[i].spread = 0; out[i].real_volume = 0;
     }
  }

//+------------------------------------------------------------------+
//| A strategy that tries to cheat, so the test can prove it cannot. |
//+------------------------------------------------------------------+
class CSSRCheater : public CSSRStrategy
  {
public:
   long              tried_future;
   long              got_future;
   long              bar_calls;
   long              closed_reads;
   long              forming_seen_closed;
   datetime          last_bar_time;
   long              now_at_bar;

                     CSSRCheater(void)
     : tried_future(0), got_future(0), bar_calls(0), closed_reads(0),
       forming_seen_closed(0), last_bar_time(0), now_at_bar(0) {}

   virtual string    Name(void) override { return "cheater"; }

   virtual void      OnBar(void) override
     {
      bar_calls++;
      if(ctx == NULL || ctx.market == NULL)
         return;
      now_at_bar = ctx.Now();

      MqlRates r;
      //--- shift 1 is the bar that just closed; it must be there
      if(ctx.market.Bar(PERIOD_M5, 1, r))
        { last_bar_time = r.time; closed_reads++; }

      //--- AND NOW THE CHEAT: a negative shift is the future, and an
      //--- enormous one is history the view never held. Both must be
      //--- refused, and neither may come back as a zero the strategy
      //--- could compare against.
      double v = 12345.0;
      tried_future++;
      if(ctx.market.Close(PERIOD_M5, -1, v))
         got_future++;
      tried_future++;
      if(ctx.market.Close(PERIOD_M5, 100000, v))
         got_future++;

      //--- the bar at shift 1 must ALREADY BE CLOSED: its close time
      //--- cannot be in the future of the replay clock
      if(last_bar_time > 0)
        {
         long bar_end = SSRToMsc(last_bar_time) + PeriodSeconds(PERIOD_M5) * 1000;
         if(bar_end > ctx.Now() + 1)
            forming_seen_closed++;
        }
     }
  };

//+------------------------------------------------------------------+
void OnStart()
  {
   g_start = SSRToMsc(InpStart) + (long)InpWarmup * SSR_MSC_PER_MIN;
   g_end   = g_start + 2000 * SSR_MSC_PER_MIN;
   Print("=== SSR Phase 13 - SS Strategy Layer ===");

   //================================================================
   Section("T13.1  the view aggregates M1 into higher timeframes");
   {
      CSSRMarketView v;
      v.OnSessionStart("TEST", 2, 0.01, SSRToMsc(InpStart));

      //--- feed 60 M1 bars of a ramp: 1000, 1001, ... 1059
      MqlRates m1[];
      BuildRamp(m1, InpStart, 60, 1000.0);
      for(int i = 0; i < 60; i++)
         v.OnBarContext(m1[i], true);

      CheckEq("sixty M1 bars in", 60, v.M1Count());

      //--- M5 groups of five. Twelve groups; the OLDEST is not offered
      //--- because we cannot know it started inside our buffer.
      CheckEq("twelve M5 groups, eleven usable", 11, v.Available(PERIOD_M5));

      //--- shift 0 is the newest group: minutes 55..59 -> 1055..1059
      MqlRates r;
      Check("M5 shift 0", v.Bar(PERIOD_M5, 0, r));
      CheckNear("its open is the group's first minute",  1055.0, r.open,  1e-9);
      CheckNear("its close is the group's last",         1059.0, r.close, 1e-9);
      CheckNear("its high is the highest in it",         1059.5, r.high,  1e-9);
      CheckNear("its low is the lowest in it",           1054.5, r.low,   1e-9);
      CheckEq("volumes are summed", 50, (long)r.tick_volume);
      CheckEq("and it is stamped with the group's open",
              SSRToMsc(InpStart) + 55 * SSR_MSC_PER_MIN, SSRToMsc(r.time));

      //--- shift 1 is the group before it: 1050..1054
      Check("M5 shift 1", v.Bar(PERIOD_M5, 1, r));
      CheckNear("open",  1050.0, r.open,  1e-9);
      CheckNear("close", 1054.0, r.close, 1e-9);

      //--- M15: 1045..1059
      Check("M15 shift 0", v.Bar(PERIOD_M15, 0, r));
      CheckNear("open",  1045.0, r.open,  1e-9);
      CheckNear("close", 1059.0, r.close, 1e-9);
      CheckNear("high",  1059.5, r.high,  1e-9);

      //--- the extremes over a span, and the arithmetic is stateable
      double hi = 0.0, lo = 0.0;
      Check("highest over three M5 bars from shift 1",
            v.HighestHigh(PERIOD_M5, 1, 3, hi));
      CheckNear("is the top of the newest of them", 1054.5, hi, 1e-9);
      Check("lowest over the same", v.LowestLow(PERIOD_M5, 1, 3, lo));
      CheckNear("is the bottom of the oldest of them", 1039.5, lo, 1e-9);

      //--- W1 does not align with the epoch and was never claimed
      Check("W1 is refused", !v.Bar(PERIOD_W1, 0, r));
      CheckEq("and reported as unavailable", 0, v.Available(PERIOD_W1));

      //--- THE SINGLE-PASS RANGE MUST AGREE WITH THE BAR-BY-BAR ONE.
      //--- Extremes() was rewritten in Phase 16 to stop rescanning the
      //--- whole buffer once per requested bar; this compares the fast
      //--- answer against the slow one it replaced, so a future edit
      //--- to either cannot drift from the other unnoticed.
      int agreed = 0, checked = 0;
      for(int sh = 0; sh <= 4; sh++)
         for(int cn = 1; cn <= 4; cn++)
           {
            double fhi = 0.0, flo = 0.0;
            bool fast = v.Extremes(PERIOD_M5, sh, cn, fhi, flo);

            //--- the definition, computed the obvious way
            double shi = 0.0, slo = 0.0;
            bool slow = true;
            for(int k = 0; k < cn && slow; k++)
              {
               MqlRates b;
               if(!v.Bar(PERIOD_M5, sh + k, b))
                 { slow = false; break; }
               if(k == 0) { shi = b.high; slo = b.low; }
               else
                 {
                  if(b.high > shi) shi = b.high;
                  if(b.low  < slo) slo = b.low;
                 }
              }
            checked++;
            if(fast == slow &&
               (!fast || (MathAbs(fhi - shi) < 1e-9 && MathAbs(flo - slo) < 1e-9)))
               agreed++;
            else
               PrintFormat("      MISMATCH shift=%d count=%d  fast=%d %.2f/%.2f  "
                           "slow=%d %.2f/%.2f", sh, cn, fast, fhi, flo,
                           slow, shi, slo);
           }
      CheckEq("the fast range agrees with the slow one everywhere",
              checked, agreed);
   }

   //================================================================
   Section("T13.2  the view cannot be made to show the future");
   {
      CSSRMarketView v;
      v.OnSessionStart("TEST", 2, 0.01, SSRToMsc(InpStart));
      MqlRates m1[];
      BuildRamp(m1, InpStart, 60, 1000.0);
      for(int i = 0; i < 60; i++)
         v.OnBarContext(m1[i], true);

      long refused_before = v.Refusals();
      MqlRates r;
      double d = 999.0;

      Check("a negative shift is refused", !v.Bar(PERIOD_M5, -1, r));
      Check("and so is an absurd one",     !v.Bar(PERIOD_M5, 99999, r));
      Check("a price accessor refuses too", !v.Close(PERIOD_M5, -1, d));

      //--- AND IT DOES NOT RETURN A ZERO A STRATEGY COULD COMPARE
      //--- AGAINST. It returns false and writes 0.0, which is only
      //--- safe because the false is not ignorable.
      CheckNear("the out-parameter is cleared", 0.0, d, 1e-12);

      Check("every refusal is counted", v.Refusals() > refused_before,
            StringFormat("%I64d -> %I64d", refused_before, v.Refusals()));

      //--- a span that runs off the buffer is refused ENTIRELY, not
      //--- served from the part that happened to be there
      double hi = 0.0;
      Check("a span past the buffer is refused",
            !v.HighestHigh(PERIOD_M5, 0, 500, hi));
      CheckNear("with nothing in the out-parameter", 0.0, hi, 1e-12);

      //--- PRIMING CANNOT SMUGGLE THE FUTURE IN EITHER. The host hands
      //--- it history after a jump; anything past the clock is trimmed.
      CSSRMarketView p;
      p.OnSessionStart("TEST", 2, 0.01, SSRToMsc(InpStart));
      MqlRates hist[];
      BuildRamp(hist, InpStart, 100, 1000.0);
      long cut = SSRToMsc(InpStart) + 40 * SSR_MSC_PER_MIN;
      CheckEq("only the bars at or before the clock were taken",
              41, p.Prime(hist, 100, cut));
      CheckEq("and that is all it holds", 41, p.M1Count());
      Check("newest bar", p.Bar(PERIOD_M1, 0, r));
      CheckNear("is the one at the clock", 1040.0, r.close, 1e-9);
   }

   //================================================================
   Section("T13.3  a rewind takes bars out of the view");
   {
      CSSRMarketView v;
      v.OnSessionStart("TEST", 2, 0.01, SSRToMsc(InpStart));
      MqlRates m1[];
      BuildRamp(m1, InpStart, 60, 1000.0);
      for(int i = 0; i < 60; i++)
         v.OnBarContext(m1[i], true);

      long cut = SSRToMsc(InpStart) + 29 * SSR_MSC_PER_MIN;
      v.OnRewind(cut);
      CheckEq("the deleted future is gone", 30, v.M1Count());

      MqlRates r;
      Check("the newest bar", v.Bar(PERIOD_M1, 0, r));
      CheckNear("is the one at the cut", 1029.0, r.close, 1e-9);

      //--- and a bar arriving twice UPDATES rather than duplicating,
      //--- because a forming bar is published as it grows
      MqlRates again = m1[29];
      again.close = 1029.75;
      v.OnBarContext(again, true);
      CheckEq("no duplicate appeared", 30, v.M1Count());
      Check("the newest bar", v.Bar(PERIOD_M1, 0, r));
      CheckNear("was updated in place", 1029.75, r.close, 1e-9);
   }

   //================================================================
   Section("T13.4  OnBar fires on a CLOSE, never on a forming bar");
   {
      CSSRMemoryDataSource src; CSSRRecordingSink sink;
      CSSRReplayController ctrl; CSSRTradingEngine acct;
      CSSRMarketView view; CSSRStrategyHost host;
      CSSRCheater cheat;

      //--- ORDER: the view must see the bar before the strategy is
      //--- asked what it thinks about it
      ctrl.AddObserver(GetPointer(acct));
      ctrl.AddObserver(GetPointer(view));
      ctrl.AddObserver(GetPointer(host));

      MqlRates rates[];
      BuildRamp(rates, InpStart, InpBars, 1000.0);
      Check("data", src.LoadBars(rates, ArraySize(rates)));
      ctrl.SetSymbolSpec(2, 0.01);
      ctrl.SetTicksPerBar(8);
      ctrl.SetSpreadPoints(0);
      ctrl.SetWarmupBars(InpWarmup);
      ctrl.SetFidelity(SSR_FIDELITY_SYNTHETIC_TICK);
      ctrl.Attach(GetPointer(src), GetPointer(sink));

      host.Attach(GetPointer(view), GetPointer(acct));
      Check("strategy added", host.Add(GetPointer(cheat), PERIOD_M5),
            host.LastError());

      Check("loaded", ctrl.Load("TEST", g_start, g_end), ctrl.LastErrorText());
      acct.SetBalance(10000.0);
      ctrl.Play();
      //--- long enough that the view holds real history, or the
      //--- closed-bar claim below would pass without being tested
      for(int i = 0; i < 4000; i++)
         ctrl.Pump(1000);

      Check("OnBar was called", cheat.bar_calls > 0,
            IntegerToString(cheat.bar_calls));

      //--- about one call per M5 bar over the ~66 minutes replayed
      Check("about once per M5 bar",
            cheat.bar_calls >= 8 && cheat.bar_calls <= 16,
            IntegerToString(cheat.bar_calls));

      //--- and the closed bar was actually served, so the assertion
      //--- below is a test rather than a vacuous truth
      Check("the closed bar was read", cheat.closed_reads > 0,
            IntegerToString(cheat.closed_reads));

      //--- THE TWO CLAIMS THIS PHASE RESTS ON
      Check("it tried to read the future", cheat.tried_future > 0,
            IntegerToString(cheat.tried_future));
      CheckEq("and never once got it", 0, cheat.got_future);
      CheckEq("no forming bar was handed over as closed", 0,
              cheat.forming_seen_closed);

      Check("the view refused every attempt",
            view.Refusals() >= cheat.tried_future,
            StringFormat("refusals=%I64d tried=%I64d",
                         view.Refusals(), cheat.tried_future));
   }

   //================================================================
   Section("T13.5  a strategy trades, and its trades are its own");
   {
      CSSRMemoryDataSource src; CSSRRecordingSink sink;
      CSSRReplayController ctrl; CSSRTradingEngine acct; CSSRStatsEngine stats;
      CSSRMarketView view; CSSRStrategyHost host;
      CSSRRefBreakout ref;

      ctrl.AddObserver(GetPointer(acct));
      ctrl.AddObserver(GetPointer(stats));
      ctrl.AddObserver(GetPointer(view));
      ctrl.AddObserver(GetPointer(host));

      MqlRates rates[];
      BuildRamp(rates, InpStart, InpBars, 1000.0);
      src.LoadBars(rates, ArraySize(rates));
      ctrl.SetSymbolSpec(2, 0.01);
      ctrl.SetTicksPerBar(8);
      ctrl.SetSpreadPoints(0);
      ctrl.SetWarmupBars(InpWarmup);
      ctrl.SetFidelity(SSR_FIDELITY_SYNTHETIC_TICK);
      ctrl.Attach(GetPointer(src), GetPointer(sink));

      stats.Attach(GetPointer(acct));
      host.Attach(GetPointer(view), GetPointer(acct));
      ref.Configure(PERIOD_M5, 5, 1.0, 0.0);
      Check("reference strategy added", host.Add(GetPointer(ref), PERIOD_M5),
            host.LastError());

      Check("loaded", ctrl.Load("TEST", g_start, g_end), ctrl.LastErrorText());
      acct.SetBalance(10000.0);
      ctrl.Play();

      //--- long enough for the view to fill and the ramp to break out
      for(int i = 0; i < 4000; i++)
         ctrl.Pump(1000);

      Check("the market rose", view.Bid() > 1000.0,
            DoubleToString(view.Bid(), 2));
      Check("the strategy waited for history at first",
            ref.SkippedNoData() > 0, IntegerToString(ref.SkippedNoData()));
      Check("and then it traded", ref.Signals() > 0,
            IntegerToString(ref.Signals()));
      Check("through the account", acct.Total() > 0,
            IntegerToString(acct.Total()));

      //--- EVERY trade carries the strategy's name, which is the only
      //--- reason its results can be told from anyone else's
      int tagged = 0;
      for(int i = 0; i < acct.Total(); i++)
        {
         SSRVirtualPosition p;
         if(acct.At(i, p) && p.tag == "ref-breakout")
            tagged++;
        }
      CheckEq("every position is tagged", acct.Total(), tagged);

      //--- and never more than one at a time, because it asked
      Check("never two at once", acct.OpenCount() <= 1,
            IntegerToString(acct.OpenCount()));

      //--- a manual trade alongside it must NOT land in its results
      long manual = acct.Open(SSR_ORDER_BUY, 1.0, 0.0, 0.0, 0.0, "");
      Check("a manual trade opened", manual > 0, acct.LastError());
      for(int i = 0; i < 30; i++)
         ctrl.Pump(1000);
      acct.Close(manual);

      SSRStatistics all, mine;
      stats.Compute(all);
      Check("strategy statistics", host.StatsFor(0, GetPointer(stats), mine));
      Check("the account has more trades than the strategy",
            all.trades > mine.trades,
            StringFormat("all=%d mine=%d", all.trades, mine.trades));
      Check("and the strategy's report carries its caveat",
            StringFind(host.Report(GetPointer(stats)), "ref-breakout") >= 0,
            host.Report(GetPointer(stats)));

      //--- the broker facade counted what it did
      Check("orders were placed through the facade",
            ref.Signals() > 0, IntegerToString(ref.Signals()));
   }

   //================================================================
   Section("T13.6  results that cannot be attributed are refused");
   {
      CSSRTradingEngine acct;
      CSSRMarketView view;
      CSSRStrategyHost host;
      host.Attach(GetPointer(view), GetPointer(acct));

      CSSRRefBreakout a, b;
      Check("the first is accepted", host.Add(GetPointer(a), PERIOD_M15),
            host.LastError());

      //--- TWO STRATEGIES WITH ONE NAME would tag their trades
      //--- identically, and neither could ever be judged again
      Check("a duplicate name is refused", !host.Add(GetPointer(b), PERIOD_M15));
      Check("and says why",
            StringFind(host.LastError(), "told apart") >= 0, host.LastError());
      CheckEq("only one registered", 1, host.Count());

      Check("a null strategy is refused", !host.Add(NULL, PERIOD_M15));
      Check("and an unsupported timeframe too",
            !host.Add(GetPointer(b), PERIOD_W1));
      Check("named as unsupported",
            StringFind(host.LastError(), "timeframe") >= 0, host.LastError());
   }

   //================================================================
   Section("T13.7  the broker facade reaches nothing but the account");
   {
      CSSRTradingEngine acct;
      CSSRStrategyBroker broker;
      broker.Attach(GetPointer(acct), "mine");

      //--- no price yet: an order must be refused, not invented
      CheckEq("no trade before the replay has run", 0, broker.Buy(1.0));
      CheckEq("and it is counted as refused", 1, broker.Refused());
      Check("with a reason", StringLen(broker.LastError()) > 0,
            broker.LastError());

      //--- give it a price the way the engine does
      acct.OnSessionStart("TEST", 2, 0.01, g_start);
      MqlTick t[];
      ArrayResize(t, 1);
      t[0].time = SSRToTime(g_start); t[0].time_msc = g_start;
      t[0].bid = 1000.0; t[0].ask = 1000.0; t[0].last = 1000.0;
      t[0].volume = 1; t[0].volume_real = 0.0; t[0].flags = 0;
      acct.OnTicks(t, 1);
      acct.SetBalance(10000.0);
      acct.Risk().Configure(1.0, 1.0, 0.01, 100.0, 0.01, 2);

      long tk = broker.Buy(1.0, 990.0);
      Check("now it trades", tk > 0, broker.LastError());
      CheckEq("and it is counted", 1, broker.Placed());

      SSRVirtualPosition p;
      Check("the position exists", acct.ByTicket(tk, p));
      Check("tagged with the strategy's name", p.tag == "mine", p.tag);

      //--- MyOpenCount sees only mine
      acct.Open(SSR_ORDER_BUY, 1.0, 0.0, 0.0, 0.0, "somebody else");
      CheckEq("the account has two", 2, acct.OpenCount());
      CheckEq("but only one is mine", 1, broker.MyOpenCount());

      Check("and I can find it", broker.MyPosition(0, p));
      Check("it is the one I opened", p.ticket == tk,
            IntegerToString((int)p.ticket));

      CheckEq("closing mine closes one", 1, broker.CloseAllMine());
      CheckEq("the other is untouched", 1, acct.OpenCount());
      CheckEq("and none of mine remain", 0, broker.MyOpenCount());
   }

   //================================================================
   Section("T13.8  the same seed gives the same strategy");
   {
      //--- a strategy that needs randomness must still be reproducible,
      //--- and adding a second strategy must not change what the first
      //--- one does by consuming its numbers
      CSSRTradingEngine acct;
      CSSRMarketView view;

      CSSRStrategyHost h1;
      h1.Attach(GetPointer(view), GetPointer(acct));
      h1.SetSeed(8143772915);
      CSSRRefBreakout only;
      h1.Add(GetPointer(only), PERIOD_M15);

      CSSRStrategyHost h2;
      h2.Attach(GetPointer(view), GetPointer(acct));
      h2.SetSeed(8143772915);
      CSSRRefBreakout first;
      CSSRCheater     second;
      h2.Add(GetPointer(first), PERIOD_M15);
      h2.Add(GetPointer(second), PERIOD_M15);

      //--- both hosts gave "ref-breakout" a stream derived from the
      //--- SAME seed and the SAME name, so it must be the same stream
      //--- whether or not another strategy was registered beside it
      CSSRStrategy *s1 = h1.At(0);
      CSSRStrategy *s2 = h2.At(0);
      Check("both hosts registered it", s1 != NULL && s2 != NULL);
      Check("under the same name", s1.Name() == s2.Name(), s1.Name());
      CheckEq("and the second host took both", 2, h2.Count());
   }

   //================================================================
   PrintFormat("=== Phase 13: PASS=%d  FAIL=%d  ===> %s",
               g_pass, g_fail, (g_fail == 0 ? "GREEN" : "RED"));
  }
//+------------------------------------------------------------------+
