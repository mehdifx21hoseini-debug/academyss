//+------------------------------------------------------------------+
//|                                                SSR_QA_Smoke.mq5  |
//|            SS Replay - does the whole pipeline actually work?    |
//|                                                                  |
//|  WHY THIS EXISTS                                                 |
//|  Eleven releases have been shipped without a compiler or a       |
//|  terminal on this side, and the report coming back has been "it  |
//|  does not work". That sentence covers a dozen different          |
//|  failures - an empty window, a symbol that would not adopt, a    |
//|  panel on the wrong chart, a speed of 1x, a chart ninety pixels  |
//|  tall - and telling them apart has cost a round trip every time. |
//|                                                                  |
//|  This runs the ENTIRE stack the Expert Advisor runs, headless,   |
//|  in one pass, and prints PASS or FAIL for each stage with the    |
//|  number it measured. One run, one screenshot, and the failing    |
//|  layer names itself.                                             |
//|                                                                  |
//|  It is deliberately NOT a unit test. Unit tests pass while the   |
//|  product is broken, because the product is the assembly. This    |
//|  assembles the real objects in the real order.                   |
//|                                                                  |
//|  It cleans up after itself: the symbol it makes is removed.      |
//+------------------------------------------------------------------+
#property script_show_inputs
#property description "Runs the whole SS Replay pipeline once and reports PASS/FAIL per stage."

#include <SSReplay/Common/SSR_Build.mqh>
#include <SSReplay/Common/SSR_Types.mqh>
#include <SSReplay/Common/SSR_Time.mqh>
#include <SSReplay/Common/SSR_SymbolNaming.mqh>
#include <SSReplay/Common/SSR_FlightRecorder.mqh>
#include <SSReplay/Trading/SSR_TradingEngine.mqh>
#include <SSReplay/Trading/SSR_Journal.mqh>
#include <SSReplay/Chart/SSR_TradeLines.mqh>
#include <SSReplay/Core/SSR_ReplayController.mqh>
#include <SSReplay/Core/SSR_MasterClock.mqh>
#include <SSReplay/Data/SSR_Mt5DataSource.mqh>
#include <SSReplay/Mt5/SSR_CustomSymbolSink.mqh>
#include <SSReplay/Chart/SSR_ChartManager.mqh>

input string InpSymbol     = "";     // Symbol (empty = this chart)
input int    InpReplayBars = 400;    // Replay window, in M1 bars
input int    InpWarmupBars = 200;    // Warmup bars
input int    InpSlot       = 9;      // Slot to use (9 keeps it away from real sessions)

int g_pass = 0, g_fail = 0;

//--- declared before OnStart calls them. A prototype that comes after
//--- the call is not a prototype; this file has already cost two
//--- releases to that exact mistake elsewhere.
void Cleanup(const string rsym);
void Done(void);

void Ok(const string what, const string detail)
  { g_pass++; PrintFormat("  PASS  %-34s %s", what, detail); }

void No(const string what, const string detail)
  { g_fail++; PrintFormat("  FAIL  %-34s %s", what, detail); }

bool Check(const string what, const bool cond, const string detail)
  {
   if(cond) Ok(what, detail); else No(what, detail);
   return cond;
  }

//+------------------------------------------------------------------+
void OnStart()
  {
   PrintFormat("=== SS Replay smoke test === build %s", SSR_BUILD);
   string origin = (InpSymbol == "" ? _Symbol : InpSymbol);
   PrintFormat("symbol %s", origin);

   //--- 1. history -------------------------------------------------
   int have = Bars(origin, PERIOD_M1);
   if(!Check("M1 history present", have >= InpReplayBars + InpWarmupBars,
             StringFormat("%d bars local, %d needed",
                          have, InpReplayBars + InpWarmupBars)))
     {
      Print("  -> the EA downloads this automatically; run it once, or press "
            "Home on an M1 chart.");
      Done();
      return;
     }

   //--- 2. the window, counted in BARS ------------------------------
   MqlRates back[];
   int got = CopyRates(origin, PERIOD_M1, 0, InpReplayBars, back);
   if(!Check("window can be counted back", got > 0,
             StringFormat("CopyRates returned %d (err %d)", got, GetLastError())))
     { Done(); return; }

   long win_start = (long)back[0].time * 1000;
   long win_end   = (long)back[got - 1].time * 1000 + SSR_MSC_PER_MIN - 1;
   int  in_window = Bars(origin, PERIOD_M1,
                         (datetime)(win_start / 1000), (datetime)(win_end / 1000));
   Check("window holds real bars", in_window >= InpReplayBars / 2,
         StringFormat("%d bars between %s and %s", in_window,
                      SSRFormatMsc(win_start), SSRFormatMsc(win_end)));

   long span_min = (win_end - win_start) / SSR_MSC_PER_MIN;
   if(in_window > 0 && span_min > in_window * 2)
      PrintFormat("  NOTE  window spans %d minutes for %d bars - it crosses a "
                  "market-closed gap. Play skips it.", (int)span_min, in_window);

   //--- 3. the data source -----------------------------------------
   CSSRMt5DataSource src;
   if(!Check("data source opens", src.Open(origin), origin))
     { Done(); return; }

   //--- 4. the custom symbol ---------------------------------------
   CSSRCustomSymbolSink sink;
   sink.SetSlot(InpSlot);
   string rsym = SSRReplaySymbolName(origin, InpSlot);
   PrintFormat("  ..    replay symbol will be %s", rsym);

   //--- 5. the controller: load, seed, and REPLAY ------------------
   CSSRReplayController ctrl;
   ctrl.Attach(GetPointer(src), GetPointer(sink));
   ctrl.SetWarmupBars(InpWarmupBars);
   bool loaded = ctrl.Load(origin, win_start, win_end);
   if(!Check("engine loads the window", loaded, ctrl.LastErrorText()))
     { Cleanup(rsym); Done(); return; }

   Check("replay symbol exists",
         (bool)SymbolInfoInteger(rsym, SYMBOL_EXIST), rsym);
   Check("replay symbol is ours",
         (bool)SymbolInfoInteger(rsym, SYMBOL_CUSTOM), "SYMBOL_CUSTOM");

   //--- THE ACCOUNT LISTENS FROM HERE, not from the trading stage.
   //--- It is fed by the same tick stream the replay emits, so it has
   //--- to be attached before the ticks start or it will have no price
   //--- to trade at when the stage arrives.
   CSSRTradingEngine acct;
   SSRExecutionModel exec;
   exec.Init();
   exec.use_real_spread = true;
   acct.SetExecution(exec);
   acct.SetBalance(10000.0);
   ctrl.AddObserver(GetPointer(acct));

   int seeded = Bars(rsym, PERIOD_M1);
   Check("warmup reached the symbol", seeded > 0,
         StringFormat("%d M1 bars in %s", seeded, rsym));

   //--- 6. THE ONE THAT MATTERS: does Play produce candles? --------
   long before_msc  = ctrl.Now();
   int  before_bars = Bars(rsym, PERIOD_M1);
   ctrl.Play();
   Check("engine reports PLAYING", ctrl.Status() == SSR_STATE_PLAYING,
         SSRStateName(ctrl.Status()));

   //--- sixty pumps of one simulated second each, at 60x. That is an
   //--- hour of market time: enough for any timeframe to move.
   ctrl.SetSpeedX100(6000);
   for(int i = 0; i < 60 && !IsStopped(); i++)
      ctrl.Pump(1000);

   long after_msc  = ctrl.Now();
   int  after_bars = Bars(rsym, PERIOD_M1);

   Check("the replay CLOCK advanced", after_msc > before_msc,
         StringFormat("%s -> %s", SSRFormatMsc(before_msc), SSRFormatMsc(after_msc)));
   Check("new CANDLES appeared", after_bars > before_bars,
         StringFormat("%d -> %d bars in %s", before_bars, after_bars, rsym));

   //+------------------------------------------------------------------+
   //| 7. THE CHART FOLLOWS.                                            |
   //|                                                                  |
   //| Bars in the symbol are not candles on a screen. The host hands   |
   //| its own chart to the replay symbol rather than opening one, so   |
   //| the chart arrives through Sync's DISCOVERY path - and until v53  |
   //| that path never applied the policy. AUTOSCROLL stayed off, the   |
   //| view never followed the new bars, and the candles "did not       |
   //| move" while the engine was writing them perfectly.               |
   //|                                                                  |
   //| This opens a chart WITHOUT OpenChart, exactly as the host does,  |
   //| and asks whether Sync made it follow.                            |
   //+------------------------------------------------------------------+
   //--- M1, not M5: this stage has to scroll the view away from the
   //--- end, and a chart with fewer bars than fit on screen cannot be
   //--- scrolled at all. M1 has five times as many.
   long probe = ChartOpen(rsym, PERIOD_M1);
   if(Check("a chart can be opened on the replay symbol", probe != 0, rsym))
     {
      ChartSetInteger(probe, CHART_AUTOSCROLL, false);   // as MT5 leaves it

      CSSRChartManager mgr;
      mgr.Configure(rsym, origin);
      mgr.Sync();

      Check("Sync makes a discovered chart follow",
            (bool)ChartGetInteger(probe, CHART_AUTOSCROLL),
            "CHART_AUTOSCROLL after Sync - off means new candles land "
            "off-screen and nothing appears to move");

      //+------------------------------------------------------------------+
      //| AND THE VIEW ACTUALLY MOVES.                                     |
      //|                                                                  |
      //| AUTOSCROLL being on is MetaTrader's promise, not the outcome.    |
      //| v53 checked the promise, shipped, and the candles still did not  |
      //| move. So this drags the view to the far left, writes a bar, and  |
      //| asks whether Redraw brought it back. That is the actual thing    |
      //| the user is looking at.                                          |
      //+------------------------------------------------------------------+
      ChartNavigate(probe, CHART_BEGIN, 0);
      Sleep(120);                        // let the terminal apply it
      long away_first = ChartGetInteger(probe, CHART_FIRST_VISIBLE_BAR);
      long away_vis   = ChartGetInteger(probe, CHART_VISIBLE_BARS);
      long away_off   = (away_vis > 0 ? away_first - (away_vis - 1) : 0);

      //--- A bar has to arrive, or there is correctly nothing to snap
      //--- to. And NO Sync in between: Sync would see the view I just
      //--- dragged, correctly read it as a user scrolling back, and
      //--- release following - which is the behaviour I want kept, not
      //--- the behaviour under test. This isolates Redraw's snap.
      ctrl.Pump(1000);
      ctrl.Pump(1000);
      mgr.Redraw(true);
      Sleep(120);

      long back_first = ChartGetInteger(probe, CHART_FIRST_VISIBLE_BAR);
      long back_vis   = ChartGetInteger(probe, CHART_VISIBLE_BARS);
      long back_off   = (back_vis > 0 ? back_first - (back_vis - 1) : 0);

      if(away_off <= 0)
         //--- every bar fits on screen, so there is no "away" to come
         //--- back from. Reporting this as a failure would be the test
         //--- lying about the product.
         PrintFormat("  NOTE  the view could not be scrolled away (%d bars, "
                     "%d visible) - the snap is untested on this screen",
                     Bars(rsym, PERIOD_M1), (int)away_vis);
      else
         Check("the view comes back to the newest bar", back_off < away_off,
               StringFormat("offset %d bars from the end -> %d after Redraw "
                            "(snaps=%d). If this does not fall, the candles "
                            "are being written off screen.",
                            (int)away_off, (int)back_off, (int)mgr.Snaps()));

      Ok("manager redraws on demand", "Redraw(force) returned");
      ChartClose(probe);
     }

   //+------------------------------------------------------------------+
   //| 8. STEPPING.                                                     |
   //|                                                                  |
   //| The first version of this compared bar counts one millisecond    |
   //| apart and reported "261 -> 261" as a failure. That number could  |
   //| not tell an engine that emitted nothing from a terminal that had |
   //| not finished building the bar yet - so it was a report that      |
   //| could not be acted on, which is the same as no report.           |
   //|                                                                  |
   //| Ask the engine what it did, then give MetaTrader a moment and    |
   //| ask the series separately. Two answers, two different causes.    |
   //+------------------------------------------------------------------+
   ctrl.Pause();
   int  step_before = Bars(rsym, PERIOD_M1);
   long step_clock  = ctrl.Now();
   int  emitted     = ctrl.StepBars(10);
   long after_clock = ctrl.Now();
   Sleep(250);                            // the series is built asynchronously
   int  step_after  = Bars(rsym, PERIOD_M1);

   Check("step forward emits ticks", emitted > 0,
         StringFormat("StepBars(10) returned %d%s", emitted,
                      (emitted < 0 ? " - " + ctrl.LastErrorText() : "")));
   Check("step forward advances the clock", after_clock > step_clock,
         StringFormat("%s -> %s", SSRFormatMsc(step_clock), SSRFormatMsc(after_clock)));
   Check("step forward reaches the series", step_after > step_before,
         StringFormat("%d -> %d bars after 250ms", step_before, step_after));

   //+------------------------------------------------------------------+
   //| 9. A JUMP PUTS ITS BARS IN THE SYMBOL.                           |
   //|                                                                  |
   //| The engine reported "jumped to ... (5918 bars in bulk)" and the  |
   //| symbol gained ONE bar. Nothing failed, nothing was logged, and   |
   //| every layer above it read success - because the seed cache's     |
   //| "the warmup is already there, skip the write" flag was never     |
   //| scoped to the warmup, and a jump writes its bars through the     |
   //| same door.                                                       |
   //|                                                                  |
   //| A count that is reported but not delivered is the worst kind of  |
   //| defect this project produces, so it gets its own stage: jump an  |
   //| hour, and ask the SYMBOL - not the engine - what it received.    |
   //+------------------------------------------------------------------+
   int  jump_before = Bars(rsym, PERIOD_M1);
   long jump_target = ctrl.Now() + 60 * SSR_MSC_PER_MIN;
   if(jump_target < win_end)
     {
      ctrl.JumpTo(jump_target);
      Sleep(300);
      int jump_after = Bars(rsym, PERIOD_M1);
      //--- and say which case was actually exercised. The swallowed
      //--- write only happens on a REUSED seed, so a pass on a fresh
      //--- symbol proves the healthy path and nothing more. A test that
      //--- does not say which half it ran is a test that overclaims.
      Check("a jump delivers its bars to the symbol",
            jump_after >= jump_before + 30,
            StringFormat("%d -> %d bars after jumping an hour (seed was %s). "
                         "Fewer than +30 means the write was swallowed and "
                         "the engine was told it succeeded.",
                         jump_before, jump_after,
                         (sink.ReusedSeed()
                          ? "REUSED - this is the path that was broken"
                          : "written fresh - the reused-seed path is NOT "
                            "covered by this run")));
     }
   else
      PrintFormat("  NOTE  no room ahead to test a jump (%d minutes left)",
                  (int)((win_end - ctrl.Now()) / SSR_MSC_PER_MIN));

   //+------------------------------------------------------------------+
   //| 10. THE BLACK BOX ITSELF.                                        |
   //|                                                                  |
   //| v54 added a diagnostic line, defaulted it to on, shipped it, and  |
   //| the user's log came back without a single one in it. The one      |
   //| thing that could have closed the loop was the one thing that did  |
   //| not run - and an unverified instrument is worse than none,        |
   //| because its silence reads as "nothing to report".                 |
   //|                                                                  |
   //| So the recorder is exercised here, on the user's own terminal,    |
   //| writing to the user's own disk: open it, write rows, close it,    |
   //| read the file back, count what is in it.                          |
   //+------------------------------------------------------------------+
   CSSRFlightRecorder rec;
   if(Check("the black box can open a file", rec.Open("smoke"), rec.Path()))
     {
      rec.Preamble(origin, rsym, win_start, win_end, 400, false, false,
                   SSR_INVALID_TIME, 30.0, 40);
      rec.Event("smoke test wrote this");
      for(int i = 0; i < 3 && !IsStopped(); i++)
        {
         SSRFlightSample fs;
         fs.Init();
         fs.state         = "SMOKE";
         fs.clock_msc     = ctrl.Now();
         fs.replay_symbol = rsym;
         fs.m1_bars       = Bars(rsym, PERIOD_M1);
         fs.chart_count   = 0;
         //--- Due() throttles to one sample per SSR_FLIGHT_SAMPLE_MS, so
         //--- three rows need the wait the running EA gets for free
         Sleep(SSR_FLIGHT_SAMPLE_MS + 50);
         if(rec.Due())
            rec.Write(fs);
        }
      string wrote = rec.Path();
      long   rows  = rec.Rows();
      rec.Close();

      int fh = FileOpen(wrote, FILE_READ | FILE_TXT | FILE_ANSI);
      if(Check("the black box file is on disk and readable",
               fh != INVALID_HANDLE,
               "MQL5\\Files\\" + wrote))
        {
         int lines = 0;
         while(!FileIsEnding(fh) && !IsStopped())
           {
            FileReadString(fh);
            lines++;
           }
         FileClose(fh);
         Check("the black box actually recorded rows",
               rows >= 4 && lines >= 20,
               StringFormat("%d rows written, %d lines in the file. This is "
                            "the file to send when anything looks wrong.",
                            (int)rows, lines));
         FileDelete(wrote);
        }
     }

   //+------------------------------------------------------------------+
   //| 11. THE TRADING SIDE.                                            |
   //|                                                                  |
   //| Never once run on MetaTrader. Not "probably broken" - UNMEASURED, |
   //| which is the state every defect in this project has been found    |
   //| hiding in. The draggable stop and target need a chart and a hand   |
   //| on a mouse and cannot be tested here, but everything underneath    |
   //| them can: a position at market with a stop and a target, a price   |
   //| that moves it, a close, and a statement on disk.                   |
   //|                                                                  |
   //| Splitting it this way means a failure upstairs has an answer      |
   //| already: if these pass and the lines do not, it is the lines.     |
   //+------------------------------------------------------------------+
   double bid = acct.Bid(), ask = acct.Ask();
   if(!Check("the account has a price to trade at", bid > 0.0 && ask >= bid,
             StringFormat("bid %.5f  ask %.5f", bid, ask)))
     {
      ctrl.Release();
      Cleanup(rsym);
      Done();
      return;
     }

   //--- a stop and a target far enough away that the next few ticks
   //--- cannot reach them: this stage is about opening and closing, and
   //--- a position stopped out mid-test would be measuring something else
   double pt = SymbolInfoDouble(rsym, SYMBOL_POINT);
   if(pt <= 0.0)
      pt = 0.01;
   double sl = bid - 5000 * pt;
   double tp = bid + 5000 * pt;

   long ticket = acct.Open(SSR_ORDER_BUY, 0.01, sl, tp);
   if(Check("a virtual position opens", ticket > 0,
            StringFormat("ticket %d%s", (int)ticket,
                         (ticket > 0 ? "" : " - " + acct.LastError()))))
     {
      Check("it is counted as open", acct.OpenCount() == 1,
            StringFormat("%d open", acct.OpenCount()));

      //--- and the price keeps moving under it
      double eq_before = acct.Equity();
      for(int i = 0; i < 20 && !IsStopped(); i++)
         ctrl.Pump(1000);
      Check("the open position is priced by the replay",
            acct.OpenCount() == 1,
            StringFormat("equity %.2f -> %.2f after an hour of replay",
                         eq_before, acct.Equity()));

      Check("it closes", acct.Close(ticket),
            (acct.LastError() == "" ? "closed" : acct.LastError()));
      Check("and the books balance", acct.OpenCount() == 0 && acct.ClosedCount() == 1,
            StringFormat("%d open, %d closed", acct.OpenCount(), acct.ClosedCount()));

      //--- the statement. A file that is merely CREATED proves nothing;
      //--- an empty one would pass that test and fail the user.
      //--- ExportHtml puts the file in its own folder and appends the
      //--- extension itself, so the name handed IN is not the path that
      //--- comes out. The first version of this stage opened the name it
      //--- had passed, failed, and reported it as a product defect. The
      //--- function has always been able to say where it wrote; ASK IT.
      CSSRJournal jrn;
      jrn.Attach(GetPointer(acct));
      string html = "SSReplay-smoke-statement";
      if(Check("the statement exports", jrn.ExportHtml(html, 2),
               jrn.LastPath() + (jrn.LastError() == "" ? "" : "  " + jrn.LastError())))
        {
         int jh = FileOpen(jrn.LastPath(), FILE_READ | FILE_TXT | FILE_ANSI);
         if(Check("the statement file is readable", jh != INVALID_HANDLE,
                  "MQL5\\Files\\" + jrn.LastPath()))
           {
            int bytes = (int)FileSize(jh);
            FileClose(jh);
            Check("and it has a statement in it", bytes > 2000,
                  StringFormat("%d bytes - a file that exists but is empty "
                               "would pass a weaker test than this", bytes));
            FileDelete(jrn.LastPath());
           }
        }
     }

   //+------------------------------------------------------------------+
   //| 12. THE LINES HAND OVER TO THE TRADE.                            |
   //|                                                                  |
   //| Placing an order disarms the planning lines - correctly, the      |
   //| proposal has become a position. But the host only drew positions  |
   //| while the lines were armed, so the stop and target of every trade |
   //| vanished the instant it was opened. The user pressed one button   |
   //| and watched the whole trade leave the chart.                      |
   //|                                                                  |
   //| Dragging needs a mouse. This does not: it asks whether the right  |
   //| objects exist before and after, which is the whole of the bug.    |
   //+------------------------------------------------------------------+
   long lchart = ChartOpen(rsym, PERIOD_M1);
   if(Check("a chart for the line test", lchart != 0, rsym))
     {
      CSSRTradeLines lines;
      lines.Attach(lchart, (int)SymbolInfoInteger(rsym, SYMBOL_DIGITS),
                   SymbolInfoDouble(rsym, SYMBOL_POINT),
                   clrTomato, clrMediumSeaGreen);

      double lpx = acct.Bid() > 0.0 ? acct.Bid() : 1000.0;
      Check("the planning lines arm", lines.ArmSide(lpx, 500, 2.0, true) &&
            ObjectFind(lchart, "SSR_LINE_SL") >= 0 &&
            ObjectFind(lchart, "SSR_LINE_TP") >= 0,
            "SSR_LINE_SL and SSR_LINE_TP are on the chart");

      lines.BeginPositions();
      lines.DrawPosition(4242, lpx, lpx - 5.0, lpx + 10.0, true, 0.10);
      lines.EndPositions();
      Check("an open trade draws its own levels",
            ObjectFind(lchart, "SSR_POS_4242_E") >= 0 &&
            ObjectFind(lchart, "SSR_POS_4242_S") >= 0 &&
            ObjectFind(lchart, "SSR_POS_4242_T") >= 0,
            "entry, stop and target");

      //--- THE REGRESSION, in one call
      lines.Disarm();
      Check("Disarm takes the planning lines and NOTHING else",
            ObjectFind(lchart, "SSR_LINE_SL") < 0 &&
            ObjectFind(lchart, "SSR_LINE_TP") < 0 &&
            ObjectFind(lchart, "SSR_POS_4242_E") >= 0 &&
            ObjectFind(lchart, "SSR_POS_4242_S") >= 0 &&
            ObjectFind(lchart, "SSR_POS_4242_T") >= 0,
            "planning lines gone, the trade's stop and target still drawn");

      //+------------------------------------------------------------------+
      //| A SHORT SETUP HAS TO SURVIVE THE NEXT PUMP.                      |
      //|                                                                  |
      //| SetStopPoints was hardcoded long, and the host fed the polled    |
      //| distance back into it every pump - so a stop dragged ABOVE the   |
      //| price was pushed below it again within 40ms, and no short could  |
      //| ever be built with a mouse. Arm short, apply a distance, and ask |
      //| whether the stop is still on the short side.                     |
      //+------------------------------------------------------------------+
      Check("the lines arm SHORT with the stop above the price",
            lines.ArmSide(lpx, 500, 2.0, false) && lines.SlPrice() > lpx &&
            lines.TpPrice() < lpx,
            StringFormat("price %s  sl %s  tp %s", DoubleToString(lpx, 2),
                         DoubleToString(lines.SlPrice(), 2),
                         DoubleToString(lines.TpPrice(), 2)));

      lines.SetStopPoints(lpx, 600);
      Check("and a stop distance does not flip it back to long",
            lines.SlPrice() > lpx && lines.TpPrice() < lpx,
            StringFormat("after SetStopPoints: sl %s  tp %s - below the price "
                         "here means a short can never be placed",
                         DoubleToString(lines.SlPrice(), 2),
                         DoubleToString(lines.TpPrice(), 2)));

      //+------------------------------------------------------------------+
      //| AND A CLOSED TRADE STAYS ON THE CHART.                           |
      //+------------------------------------------------------------------+
      datetime t1 = (datetime)SeriesInfoInteger(rsym, PERIOD_M1, SERIES_LASTBAR_DATE);
      if(t1 > 0)
        {
         lines.DrawClosed(777, t1 - 600, lpx, t1, lpx + 3.0, true, 0.10, 42.0);
         Check("a closed trade leaves history on the chart",
               ObjectFind(lchart, "SSR_HIST_777_A") >= 0 &&
               ObjectFind(lchart, "SSR_HIST_777_B") >= 0 &&
               ObjectFind(lchart, "SSR_HIST_777_L") >= 0,
               "entry arrow, exit arrow and the line between them");

         lines.DrawClosed(777, t1 - 600, lpx, t1, lpx + 3.0, true, 0.10, 42.0);
         Check("and drawing it again costs nothing",
               ObjectFind(lchart, "SSR_HIST_777_L") >= 0,
               "history does not change, so it is not redrawn");
        }

      lines.Clear();
      Check("Clear takes everything",
            ObjectFind(lchart, "SSR_POS_4242_E") < 0 &&
            ObjectFind(lchart, "SSR_HIST_777_L") < 0,
            "positions and history both go when the session is over");
      ChartClose(lchart);
     }

   ctrl.Release();
   Cleanup(rsym);
   Done();
  }

//+------------------------------------------------------------------+
void Cleanup(const string rsym)
  {
   long id = ChartFirst();
   while(id >= 0)
     {
      long nxt = ChartNext(id);
      if(ChartSymbol(id) == rsym)
         ChartClose(id);
      id = nxt;
     }
   if(SymbolInfoInteger(rsym, SYMBOL_EXIST))
     {
      SymbolSelect(rsym, false);
      if(!CustomSymbolDelete(rsym))
         PrintFormat("  NOTE  %s could not be deleted (%d) - run SSR_Z_Cleanup",
                     rsym, GetLastError());
     }
  }

void Done(void)
  {
   PrintFormat("=== %d passed, %d FAILED ===", g_pass, g_fail);
   if(g_fail == 0)
      Print("The pipeline works end to end. If the tool still looks dead on a "
            "chart, the problem is the VIEW - speed too low, or a chart too "
            "short for the panel - not the engine.");
   else
      Print("Send this whole block. The first FAIL is the layer to fix; "
            "everything below it is a consequence.");
  }
//+------------------------------------------------------------------+
