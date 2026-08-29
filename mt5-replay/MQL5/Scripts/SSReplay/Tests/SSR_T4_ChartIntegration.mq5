//+------------------------------------------------------------------+
//|                                       SSR_T4_ChartIntegration.mq5 |
//|                    SS Replay - Phase 4 Native Chart Integration  |
//|                                                                  |
//|  The headline assertion of the whole project lives here:         |
//|                                                                  |
//|      M5 @ 10:37  ->  M15  ->  H1  ->  M5                         |
//|      replay time is STILL 10:37, and no future appeared          |
//|                                                                  |
//|  Opens and closes real charts, so run it with a bit of screen to |
//|  spare. Cleans up after itself.                                  |
//+------------------------------------------------------------------+
#property script_show_inputs

#include <SSReplay/Common/SSR_Types.mqh>
#include <SSReplay/Common/SSR_Time.mqh>
#include <SSReplay/Chart/SSR_ChartManager.mqh>
#include <SSReplay/Mt5/SSR_CustomSymbolSink.mqh>
#include <SSReplay/Data/SSR_Mt5DataSource.mqh>
#include <SSReplay/Core/SSR_ReplayController.mqh>

input string InpSymbol = "";    // Symbol (empty = current chart symbol)
input int    InpSlot   = 8;     // Slot
input int    InpBars   = 400;   // M1 bars to replay
input int    InpWarmup = 400;   // Warmup bars (deep enough for H1 context)

int g_pass = 0, g_fail = 0, g_skip = 0;

void Check(const string n, const bool ok, const string d = "")
  { if(ok) { g_pass++; PrintFormat("  PASS  %s", n); }
    else   { g_fail++; PrintFormat("  FAIL  %s  %s", n, d); } }
void CheckEq(const string n, const long e, const long a)
  { Check(n, e == a, StringFormat("expected=%I64d actual=%I64d", e, a)); }
void Skip(const string n, const string w) { g_skip++; PrintFormat("  SKIP  %s  (%s)", n, w); }
void Section(const string t) { PrintFormat("--- %s", t); }

//+------------------------------------------------------------------+
//| Counts the events the chart layer publishes.                     |
//+------------------------------------------------------------------+
class CTestObserver : public CSSRChartObserver
  {
public:
   int opened, closed, tf_changed, scrolled, followed;
   ENUM_TIMEFRAMES last_from, last_to;

        CTestObserver(void)
     : opened(0), closed(0), tf_changed(0), scrolled(0), followed(0),
       last_from(PERIOD_CURRENT), last_to(PERIOD_CURRENT) {}

   virtual void OnChartOpened(const long id) override { opened++; }
   virtual void OnChartClosed(const long id) override { closed++; }
   virtual void OnTimeframeChanged(const long id, const ENUM_TIMEFRAMES f,
                                   const ENUM_TIMEFRAMES t) override
     { tf_changed++; last_from = f; last_to = t; }
   virtual void OnUserScrolled(const long id) override { scrolled++; }
   virtual void OnUserFollowed(const long id) override { followed++; }
  };

//+------------------------------------------------------------------+
//| Is there any bar beyond `now` in any timeframe?                  |
//+------------------------------------------------------------------+
int FutureBars(const string sym, const long now_msc)
  {
   ENUM_TIMEFRAMES tfs[6] = {PERIOD_M1, PERIOD_M5, PERIOD_M15,
                             PERIOD_M30, PERIOD_H1, PERIOD_H4};
   int leaked = 0;
   for(int i = 0; i < 6; i++)
     {
      MqlRates r[];
      int n = CopyRates(sym, tfs[i], SSRToTime(now_msc) + 60,
                        SSRToTime(now_msc) + 86400 * 7, r);
      if(n > 0)
         leaked += n;
     }
   return leaked;
  }

//+------------------------------------------------------------------+
void OnStart()
  {
   string origin = (InpSymbol == "" ? _Symbol : InpSymbol);
   Print("=== SSR Phase 4 - Native Chart Integration ===");
   PrintFormat("    origin: %s   slot: %d", origin, InpSlot);

   CSSRMt5DataSource    src;
   CSSRCustomSymbolSink sink;
   CSSRReplayController ctrl;
   CSSRChartManager     charts;
   CTestObserver        obs;

   sink.SetSlot(InpSlot);
   charts.SetObserver(GetPointer(obs));

   SSRDataRange range;
   range.Init();
   if(!src.Open(origin))
     {
      Skip("everything", "no broker M1 history for " + origin);
      PrintFormat("=== Phase 4: PASS=%d FAIL=%d SKIP=%d ===", g_pass, g_fail, g_skip);
      return;
     }
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

   if(!ctrl.Load(origin, win_start, win_end))
     {
      Skip("everything", "load failed: " + ctrl.LastErrorText());
      PrintFormat("=== Phase 4: PASS=%d FAIL=%d SKIP=%d ===", g_pass, g_fail, g_skip);
      return;
     }

   string rsym = sink.ReplaySymbol();
   charts.Configure(rsym, origin);
   PrintFormat("    replay symbol: %s", rsym);

   //--- advance a little so there is something to look at
   ctrl.SetSpeedX100(SSR_SPEED_1);
   ctrl.Play();
   for(int i = 0; i < 300; i++)
      ctrl.Pump(1000);
   SSRPause(300);

   //================================================================
   Section("T4.1  chart registry tracks what is open");
   long cid = charts.OpenChart(PERIOD_M5);
   {
      Check("chart opened", cid != 0);
      SSRPause(800);
      charts.Sync();
      CheckEq("registry sees one chart", 1, charts.Count());
      Check("observer was told", obs.opened >= 1, IntegerToString(obs.opened));

      SSRChartInfo info;
      Check("info readable", charts.InfoAt(0, info));
      Check("chart is on the replay symbol", info.symbol == rsym, info.symbol);
      Check("following by default", info.follow);
   }

   //================================================================
   Section("T4.2  THE HEADLINE: timeframe changes do not disturb replay");
   if(cid == 0)
      Skip("timeframe cycle", "no chart");
   else
     {
      long   time_before  = ctrl.Now();
      long   ticks_before = ctrl.TicksEmitted();
      ENUM_SSR_STATE state_before = ctrl.Status();

      ENUM_TIMEFRAMES cycle[4] = {PERIOD_M15, PERIOD_H1, PERIOD_M5, PERIOD_M15};
      string          names[4] = {"M15", "H1", "M5", "M15"};

      for(int i = 0; i < 4; i++)
        {
         ChartSetSymbolPeriod(cid, rsym, cycle[i]);
         SSRPause(900);
         charts.Sync();

         //--- the replay clock must not have moved: the engine was never
         //--- asked anything, and it was never told anything either
         CheckEq(StringFormat("replay time survives -> %s", names[i]),
                 time_before, ctrl.Now());
         Check(StringFormat("state survives -> %s", names[i]),
               ctrl.Status() == state_before, SSRStateName(ctrl.Status()));
         CheckEq(StringFormat("no ticks re-emitted -> %s", names[i]),
                 ticks_before, ctrl.TicksEmitted());

         //--- and the new timeframe must be populated but not clairvoyant
         long bars = 0;
         SeriesInfoInteger(rsym, cycle[i], SERIES_BARS_COUNT, bars);
         Check(StringFormat("%s has bars", names[i]), bars > 0,
               IntegerToString((int)bars));
         CheckEq(StringFormat("%s shows no future", names[i]),
                 0, FutureBars(rsym, ctrl.Now()));
        }

      Check("observer saw every change", obs.tf_changed >= 4,
            IntegerToString(obs.tf_changed));

      //--- replay must still run afterwards, from where it left off
      long before_more = ctrl.Now();
      for(int i = 0; i < 60; i++)
         ctrl.Pump(1000);
      Check("replay continues after the cycle", ctrl.Now() > before_more);
      CheckEq("still no future after resuming", 0, FutureBars(rsym, ctrl.Now()));
     }

   //================================================================
   Section("T4.3  the partial higher-timeframe candle is genuinely partial");
   if(cid == 0)
      Skip("partial bar", "no chart");
   else
     {
      long now = ctrl.Now();

      //--- at replay time T, the current H1 bar must have opened at or
      //--- before T and must NOT have closed yet. A tool that shows a
      //--- finished H1 candle mid-hour is showing the future.
      datetime h1_open = iTime(rsym, PERIOD_H1, 0);
      Check("H1 bar exists", h1_open > 0, TimeToString(h1_open));
      if(h1_open > 0)
        {
         long open_msc = SSRToMsc(h1_open);
         Check("H1 bar opened at or before replay time",
               open_msc <= now,
               StringFormat("open=%s now=%s", SSRFormatMsc(open_msc), SSRFormatMsc(now)));
         Check("H1 bar has not closed yet",
               open_msc + 3600000 > now,
               StringFormat("open=%s now=%s", SSRFormatMsc(open_msc), SSRFormatMsc(now)));

         //--- its high and low may only reflect what has happened
         double h1_high = iHigh(rsym, PERIOD_H1, 0);
         double h1_low  = iLow(rsym, PERIOD_H1, 0);
         double m1_high = 0, m1_low = 0;
         bool   first   = true;
         for(int i = 0; i < 60; i++)
           {
            datetime bt = iTime(rsym, PERIOD_M1, i);
            if(bt <= 0 || SSRToMsc(bt) < open_msc)
               break;
            double hi = iHigh(rsym, PERIOD_M1, i);
            double lo = iLow(rsym, PERIOD_M1, i);
            if(first) { m1_high = hi; m1_low = lo; first = false; }
            else { if(hi > m1_high) m1_high = hi; if(lo < m1_low) m1_low = lo; }
           }
         if(!first)
           {
            Check("H1 high equals the M1 bars so far",
                  MathAbs(h1_high - m1_high) < point * 2,
                  StringFormat("h1=%.5f m1=%.5f", h1_high, m1_high));
            Check("H1 low equals the M1 bars so far",
                  MathAbs(h1_low - m1_low) < point * 2,
                  StringFormat("h1=%.5f m1=%.5f", h1_low, m1_low));
           }
        }
     }

   //================================================================
   Section("T4.4  auto-scroll stops fighting a user who scrolled back");
   if(cid == 0)
      Skip("auto scroll", "no chart");
   else
     {
      ChartSetSymbolPeriod(cid, rsym, PERIOD_M5);
      SSRPause(600);
      charts.Sync();
      charts.Follow(cid);
      SSRPause(300);

      SSRChartInfo before;
      charts.InfoAt(0, before);
      Check("following after an explicit Follow", before.follow);
      Check("MetaTrader autoscroll is on",
            ChartGetInteger(cid, CHART_AUTOSCROLL) != 0);

      //--- simulate the user dragging back into history
      ChartNavigate(cid, CHART_END, -50);
      SSRPause(600);
      //--- detaching deliberately requires the drift to persist across
      //--- two syncs, so a single bulk write cannot fake a user scroll
      charts.Sync();
      SSRPause(200);
      charts.Sync();

      SSRChartInfo after;
      charts.InfoAt(0, after);
      Check("manual scroll was detected", after.user_detached,
            StringFormat("offset=%d", (int)after.last_offset));
      Check("we stopped following", !after.follow);
      CheckEq("MetaTrader autoscroll released", 0,
              ChartGetInteger(cid, CHART_AUTOSCROLL));
      Check("observer was told", obs.scrolled >= 1, IntegerToString(obs.scrolled));

      //--- and the user can come back deliberately
      Check("Follow re-engages", charts.Follow(cid));
      SSRPause(400);
      charts.Sync();
      SSRChartInfo back;
      charts.InfoAt(0, back);
      Check("following again", back.follow);
      Check("no longer marked detached", !back.user_detached);
      Check("observer saw the follow", obs.followed >= 1, IntegerToString(obs.followed));
     }

   //================================================================
   Section("T4.5  repaint throttling");
   {
      long r0 = charts.Redraws();
      long s0 = charts.RedrawsSkipped();
      for(int i = 0; i < 50; i++)
         charts.Redraw();
      Check("most repaints were denied",
            (charts.RedrawsSkipped() - s0) > 40,
            StringFormat("painted=%d skipped=%d",
                         (int)(charts.Redraws() - r0),
                         (int)(charts.RedrawsSkipped() - s0)));
      Check("forced repaint always happens", charts.Redraw(true));
   }

   //================================================================
   Section("T4.6  leak guard");
   {
      charts.ScanLeaks();
      CSSRLeakGuard *lg = charts.Leak();
      Check("replay charts counted", lg.ReplayCharts() >= 1,
            IntegerToString(lg.ReplayCharts()));

      //--- the origin is in Market Watch because we selected it to read
      //--- history, so the guard must be saying something
      Check("guard notices the live symbol is reachable",
            lg.OriginInWatch() || lg.OriginCharts() > 0,
            lg.ToString());
      Check("advice is not silent when dirty",
            lg.IsClean() || StringLen(lg.Advice()) > 0, lg.Advice());
      PrintFormat("        %s", lg.ToString());
      if(!lg.IsClean())
         PrintFormat("        advice: %s", lg.Advice());
   }

   //================================================================
   Section("T4.7  we only close charts we opened");
   {
      long user_chart = ChartOpen(rsym, PERIOD_M15);
      SSRPause(600);
      charts.Sync();
      int total = charts.Count();
      Check("both charts tracked", total >= 2, IntegerToString(total));

      int closed = charts.CloseOwned();
      SSRPause(600);
      charts.Sync();
      Check("our chart was closed", closed >= 1, IntegerToString(closed));
      Check("the other chart survived", charts.Count() >= 1,
            IntegerToString(charts.Count()));

      //--- tidy up the one we opened by hand, outside the manager
      if(user_chart != 0)
         ChartClose(user_chart);
      SSRPause(400);
      charts.Sync();
      Check("observer saw closures", obs.closed >= 1, IntegerToString(obs.closed));
   }

   //================================================================
   ctrl.Release();
   SSRPause(300);
   PrintFormat("        %s", charts.ToString());
   PrintFormat("=== Phase 4: PASS=%d  FAIL=%d  SKIP=%d  ===> %s",
               g_pass, g_fail, g_skip, (g_fail == 0 ? "GREEN" : "RED"));
  }
//+------------------------------------------------------------------+
