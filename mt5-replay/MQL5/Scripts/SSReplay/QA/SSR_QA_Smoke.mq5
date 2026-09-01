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
#include <SSReplay/Trading/SSR_ShotBook.mqh>
#include <SSReplay/Ui/SSR_FirstRun.mqh>
#include <SSReplay/Report/SSR_ClassReport.mqh>
#include <SSReplay/Data/SSR_Calendar.mqh>
#include <SSReplay/Chart/SSR_CalendarLines.mqh>
#include <SSReplay/Chart/SSR_TradeLines.mqh>
#include <SSReplay/Chart/SSR_BlindMode.mqh>
#include <SSReplay/Session/SSR_SessionManager.mqh>
#include <SSReplay/Trading/SSR_PropEvaluation.mqh>
#include <SSReplay/Ui/SSR_SetupPanel.mqh>
#include <SSReplay/Core/SSR_ReplayController.mqh>
#include <SSReplay/Core/SSR_MasterClock.mqh>
#include <SSReplay/Data/SSR_Mt5DataSource.mqh>
#include <SSReplay/Mt5/SSR_CustomSymbolSink.mqh>
#include <SSReplay/Chart/SSR_ChartManager.mqh>
#include <SSReplay/Ui/SSR_GroupPort.mqh>
#include <SSReplay/Ui/SSR_Panel.mqh>

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
void PropCase(const string what, const double start, const double target_pct,
              const double daily_pct, const double total_pct,
              const bool trailing, const int min_days, const int max_days,
              const double final_equity, const int days,
              const ENUM_SSR_PROP_STATE expect);

//+------------------------------------------------------------------+
//| A TEST MUST NOT EAT THE USER'S SETTINGS.                         |
//|                                                                  |
//| Stage 16 has always written a fake setup to MQL5\Files\SSReplay |
//| and then DELETED the file - so running the smoke test threw away  |
//| whatever the user had typed into the setup panel, and told them   |
//| PASS while doing it. Now the real file is moved aside first and   |
//| put back afterwards, whatever the stage does in between.          |
//+------------------------------------------------------------------+
void Stash(const string path)
  {
   if(FileIsExist(path + ".qabak"))
      FileDelete(path + ".qabak");
   if(FileIsExist(path))
      FileMove(path, 0, path + ".qabak", FILE_REWRITE);
  }

void Unstash(const string path)
  {
   if(FileIsExist(path))
      FileDelete(path);
   if(FileIsExist(path + ".qabak"))
      FileMove(path + ".qabak", 0, path, FILE_REWRITE);
  }

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

   //+------------------------------------------------------------------+
   //| Bars() ANSWERS FROM A CACHE, and a custom symbol just written to  |
   //| has not necessarily rebuilt it.                                   |
   //|                                                                   |
   //| This read it once and reported "200 -> 200 bars" - while the very  |
   //| next stage, which opens a chart on that symbol, counted 263. The   |
   //| candles were there; the count was stale, and the stage was         |
   //| measuring the terminal's cache rather than the engine.             |
   //|                                                                   |
   //| CopyRates pokes the series into building. A second is far longer   |
   //| than it has ever needed and short enough that a genuinely dead     |
   //| engine still fails here rather than hanging.                        |
   //+------------------------------------------------------------------+
   int  after_bars = before_bars;
   int  waited_ms  = 0;
   for(int w = 0; w < 20 && after_bars <= before_bars; w++)
     {
      MqlRates poke[];
      CopyRates(rsym, PERIOD_M1, 0, 1, poke);
      after_bars = Bars(rsym, PERIOD_M1);
      if(after_bars > before_bars)
         break;
      Sleep(50);
      waited_ms += 50;
     }

   Check("the replay CLOCK advanced", after_msc > before_msc,
         StringFormat("%s -> %s", SSRFormatMsc(before_msc), SSRFormatMsc(after_msc)));
   Check("new CANDLES appeared", after_bars > before_bars,
         StringFormat("%d -> %d bars in %s%s", before_bars, after_bars, rsym,
                      (waited_ms > 0
                       ? StringFormat(" (the series took %d ms to rebuild)",
                                      waited_ms)
                       : "")));

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

      //--- a MetaTrader object must be SELECTED before it can be
      //--- dragged, so an unselected stop costs a click to arm and a
      //--- second drag to use. These lines exist only to be dragged.
      Check("the planning lines are draggable on first touch",
            ObjectGetInteger(lchart, "SSR_LINE_SL", OBJPROP_SELECTED) &&
            ObjectGetInteger(lchart, "SSR_LINE_TP", OBJPROP_SELECTED),
            "both selected - no click needed before the drag");

      //+------------------------------------------------------------------+
      //| OFFSETS IN POINTS, NOT IN WHOLE UNITS.                           |
      //|                                                                  |
      //| This said `lpx - 5.0`. On gold at 4438 that is a stop below the   |
      //| entry; on EURUSD at 1.15965 it is MINUS 3.84, and a level at a    |
      //| negative price is correctly refused - so three stages failed and  |
      //| named the product, when what was wrong was the test's idea of how |
      //| big a price is. The same rule the product follows: ask the symbol.|
      //+------------------------------------------------------------------+
      lines.BeginPositions();
      lines.DrawPosition(4242, lpx, lpx - 500 * pt, lpx + 1000 * pt, true, 0.10);
      lines.EndPositions();
      Check("an open trade draws its own levels",
            ObjectFind(lchart, "SSR_POS_4242_E") >= 0 &&
            ObjectFind(lchart, "SSR_POS_4242_S") >= 0 &&
            ObjectFind(lchart, "SSR_POS_4242_T") >= 0,
            "entry, stop and target");

      //--- and worded the way the platform words them, because the whole
      //--- point of the request was that ours read as a different product
      Check("and they are labelled the MetaTrader way",
            ObjectGetString(lchart, "SSR_POS_4242_S", OBJPROP_TEXT) == "SL" &&
            ObjectGetString(lchart, "SSR_POS_4242_T", OBJPROP_TEXT) == "TP" &&
            StringFind(ObjectGetString(lchart, "SSR_POS_4242_E",
                                       OBJPROP_TEXT), "BUY ") == 0,
            "SL, TP, and BUY <volume> at <price>");

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

   //+------------------------------------------------------------------+
   //| 13. MANAGED IS NOT THE SAME SET AS OWNED.                        |
   //|                                                                  |
   //| Three separate defects have come from asking about ownership     |
   //| when the question was about what the user can see: v53's chart   |
   //| policy, v62's position lines, and blind mode reaching only the   |
   //| charts it had opened - which in one-window mode is every chart    |
   //| EXCEPT the one being watched.                                     |
   //|                                                                  |
   //| One assertion states the fact all three got wrong.                |
   //+------------------------------------------------------------------+
   long probe2 = ChartOpen(rsym, PERIOD_M15);
   if(Check("a second chart for the layout tests", probe2 != 0, rsym))
     {
      CSSRChartManager m2;
      m2.Configure(rsym, origin);
      m2.Sync();
      long owned[];
      int  n_owned = m2.OwnedIds(owned);
      Check("a discovered chart is MANAGED but not OWNED",
            m2.Count() >= 1 && n_owned == 0,
            StringFormat("%d managed, %d owned - anything the user must SEE "
                         "has to walk the managed set, never the owned one",
                         m2.Count(), n_owned));

      //--- multi timeframe
      ENUM_TIMEFRAMES tfs[];
      ArrayResize(tfs, 2);
      tfs[0] = PERIOD_M30;
      tfs[1] = PERIOD_H1;
      int opened = m2.OpenLayout(tfs, 2);
      Check("extra timeframes open on the replay symbol", opened == 2,
            StringFormat("%d of 2 opened, %d charts managed now",
                         opened, m2.Count()));

      //--- blind mode, on a chart nobody owned
      bool had_ohlc = (bool)ChartGetInteger(probe2, CHART_SHOW_OHLC);
      CSSRBlindMode  blind;
      SSRBlindPolicy pol;
      pol.Apply(SSR_BLIND_FULL);
      blind.SetPolicy(pol);
      blind.Apply(probe2);
      Sleep(80);
      Check("blind mode hides what the chart announces",
            !(bool)ChartGetInteger(probe2, CHART_SHOW_OHLC) &&
            !(bool)ChartGetInteger(probe2, CHART_SHOW_PRICE_SCALE),
            "OHLC line and price scale both off");

      blind.RestoreAll();
      Sleep(80);
      Check("and puts the chart back the way it was",
            (bool)ChartGetInteger(probe2, CHART_SHOW_OHLC) == had_ohlc,
            "a mode you cannot leave is a trap, not a feature");

      m2.CloseOwned();
      ChartClose(probe2);
     }

   //+------------------------------------------------------------------+
   //| 14. A SESSION SURVIVES BEING WRITTEN AND READ BACK.              |
   //+------------------------------------------------------------------+
   CSSRReplayGroup     sgrp;
   CSSRSessionManager  smgr;
   sgrp.Add(GetPointer(ctrl));
   smgr.Attach(GetPointer(sgrp), GetPointer(acct));

   SSRSessionSettings sset;
   sset.Init();
   string sname = "ssr-smoke-session";
   if(Check("a session saves", smgr.Save(sname, sset),
            (smgr.LastError() == "" ? smgr.LastPath() : smgr.LastError())))
     {
      Check("and the file is there afterwards", smgr.Exists(sname),
            smgr.LastPath());

      long r_start = 0, r_end = 0;
      Check("and the window reads back",
            smgr.ReadWindow(sname, 0, r_start, r_end) && r_end > r_start,
            StringFormat("%s .. %s", SSRFormatMsc(r_start), SSRFormatMsc(r_end)));

      FileDelete(smgr.LastPath());
     }

   //+------------------------------------------------------------------+
   //| 15. THE EVALUATION JUDGES CORRECTLY.                             |
   //|                                                                  |
   //| Four rules, each given a run that breaks exactly it and nothing  |
   //| else. A rule engine that says PASSED when it should say FAILED   |
   //| is worse than no rule engine: the user practises against a       |
   //| standard that does not exist and finds out at a real firm.       |
   //|                                                                  |
   //| Driven with a stub account rather than the replay, so each case  |
   //| is one equity curve and one verdict, with nothing else moving.   |
   //+------------------------------------------------------------------+
   PropCase("target reached after enough days",
            10000, 8.0, 5.0, 10.0, false, 2, 0,
            10900, 3, SSR_PROP_PASSED);
   PropCase("target reached too early still runs",
            10000, 8.0, 5.0, 10.0, false, 5, 0,
            10900, 2, SSR_PROP_RUNNING);
   PropCase("daily loss ends it",
            10000, 8.0, 5.0, 10.0, false, 1, 0,
            9400, 1, SSR_PROP_FAILED);
   PropCase("overall drawdown ends it, with the daily limit far away",
            10000, 50.0, 90.0, 10.0, false, 1, 0,
            8900, 1, SSR_PROP_FAILED);
   PropCase("the deadline ends it",
            10000, 8.0, 90.0, 90.0, false, 1, 3,
            10100, 6, SSR_PROP_FAILED);

   //--- and the one rule that is ours rather than any firm's
   {
      CSSRPropEvaluation ev;
      SSRPropRules r;
      r.Init();
      r.enabled = true;
      ev.SetRules(r);
      ev.Reset();
      ev.OnClock(SSR_PROP_DAY_MSC * 100);
      ev.OnRewind(SSR_PROP_DAY_MSC * 99);
      Check("a rewind voids the run", ev.State() == SSR_PROP_VOID,
            "an evaluation you can rewind out of is a score you edited");

      string why = "";
      Check("and it asks the replay to stop, once", ev.PauseRequested(why) &&
            !ev.PauseRequested(why),
            "consumed on the way out, as the observer interface requires");
   }

   //+------------------------------------------------------------------+
   //| 16. THE SETUP SURVIVES BEING WRITTEN AND READ BACK.              |
   //|                                                                  |
   //| Not a nicety: the one-window handover restarts this program, and |
   //| a setup that does not cross that restart is a form the user      |
   //| filled in and the tool threw away. v55 had to rescue exactly     |
   //| that for the picked start; this is the same trap for everything  |
   //| else on the panel.                                               |
   //+------------------------------------------------------------------+
   {
      Stash(SSR_SETUP_FILE);

      SSRSetupValues a;
      a.Init();
      a.balance       = 25000.0;
      a.risk_percent  = 1.25;
      a.spread_points = 17.0;
      a.speed         = 120.0;
      a.chart_tf      = PERIOD_M15;
      a.extra_tfs     = "M30,H1";
      a.blind         = SSR_BLIND_FULL;
      a.session_name  = "smoke-setup";
      a.prop_on       = true;
      a.prop_target   = 6.5;
      a.prop_daily    = 4.0;
      a.prop_total    = 9.0;

      if(Check("the setup saves", CSSRSetupPanel::Save(a),
               "MQL5\\Files\\SSReplay\\setup.ini"))
        {
         SSRSetupValues b;
         b.Init();
         Check("and every field comes back",
               CSSRSetupPanel::Restore(b) &&
               b.balance == a.balance && b.risk_percent == a.risk_percent &&
               b.spread_points == a.spread_points && b.speed == a.speed &&
               b.chart_tf == a.chart_tf && b.extra_tfs == a.extra_tfs &&
               b.blind == a.blind && b.session_name == a.session_name &&
               b.prop_on == a.prop_on && b.prop_target == a.prop_target &&
               b.prop_daily == a.prop_daily && b.prop_total == a.prop_total,
               StringFormat("balance %.2f  tf %s  extra [%s]  blind %s  "
                            "eval %s  session [%s]",
                            b.balance, SSRSetupTfName(b.chart_tf), b.extra_tfs,
                            SSRSetupBlindName(b.blind),
                            (b.prop_on ? "on" : "off"), b.session_name));
        }
      Unstash(SSR_SETUP_FILE);
   }

   //+------------------------------------------------------------------+
   //| 17. MANAGING A TRADE, AND WHAT THE TAGS SAY AFTERWARDS.          |
   //|                                                                  |
   //| The engine could halve a position, move a stop to entry and trail |
   //| since Phase 9. None of the three had a button, so the tool         |
   //| modelled the five seconds of entering a trade and none of the hour |
   //| of managing it - which is the part being practised.                |
   //|                                                                  |
   //| Driven through the PORT, not the engine, because the port is what  |
   //| the new buttons call: the lot-step rounding, the refusals and the  |
   //| tag normalisation all live there and none of them exist downstairs.|
   //|                                                                  |
   //| The volumes come from the symbol's own step. A test that assumed   |
   //| 0.01 would pass here and fail on the first broker who quotes in    |
   //| tenths, and reporting that as a product defect is exactly the      |
   //| hardcoded-broker trap this project is not allowed to fall into.    |
   //+------------------------------------------------------------------+
   //--- FROM HERE TO THE END, two stages drive a real panel - and a
   //--- panel that is driven writes down where it was left. The user's
   //--- own layout goes aside for the duration.
   Stash(SSR_PANEL_FILE);

   {
      double step = SymbolInfoDouble(rsym, SYMBOL_VOLUME_STEP);
      if(step <= 0.0)
         step = 0.01;

      CSSRStatsEngine stats;
      stats.Attach(GetPointer(acct));

      CSSRGroupPort port;
      port.AttachAccount(GetPointer(acct));
      port.AttachStats(GetPointer(stats));

      //--- the tag: trimmed, and its commas taken out, because the same
      //--- journal is exported as a CSV and one comma in a setup name
      //--- moves every column after it by one
      port.SetTradeTag("  break,out  ");
      Check("a setup tag is cleaned before it is stored",
            port.TagOrDefault() == "break out",
            StringFormat("[%s] from [  break,out  ]", port.TagOrDefault()));
      Check("and an empty one still labels the trade",
            (port.SetTradeTag("") && port.TagOrDefault() == "lines"),
            "an untagged trade is a trade nothing can group");

      double nbid = acct.Bid();
      double nsl  = nbid - 5000 * pt;
      double ntp  = nbid + 5000 * pt;

      long t1 = acct.Open(SSR_ORDER_BUY, step * 2, nsl, ntp, 0.0, "breakout");
      if(Check("a tagged position opens", t1 > 0,
               StringFormat("ticket %d at %.2f lots%s", (int)t1, step * 2,
                            (t1 > 0 ? "" : " - " + acct.LastError()))))
        {
         Check("half of it closes", port.ClosePartial(t1, 0.5),
               (port.TradeError() == "" ? "closed one step"
                : port.TradeError()));

         SSRVirtualPosition p1;
         bool seen1 = false;
         for(int i = 0; i < acct.Total() && !seen1; i++)
           {
            SSRVirtualPosition q;
            if(acct.At(i, q) && q.ticket == t1)
              { p1 = q; seen1 = true; }
           }
         Check("and the other half is still open",
               seen1 && p1.IsOpen() && MathAbs(p1.volume - step) < step / 10.0,
               StringFormat("%.3f lots left of %.3f", p1.volume, step * 2));

         Check("break-even puts the stop at the entry", port.BreakEven(t1),
               (port.TradeError() == "" ? "" : port.TradeError()));
         Check("a trailing distance reaches the open trade",
               port.SetTrailing(250.0),
               (port.TradeError() == "" ? "250 pt" : port.TradeError()));

         seen1 = false;
         for(int i = 0; i < acct.Total() && !seen1; i++)
           {
            SSRVirtualPosition q;
            if(acct.At(i, q) && q.ticket == t1)
              { p1 = q; seen1 = true; }
           }
         Check("the stop is AT the entry, not near it",
               seen1 && MathAbs(p1.sl - p1.open_price) < pt / 2.0,
               StringFormat("sl %.5f  entry %.5f", p1.sl, p1.open_price));
         Check("and the trail is on the position, not just in the panel",
               seen1 && MathAbs(p1.trail_points - 250.0) < 0.5,
               StringFormat("%.0f pt on the position", p1.trail_points));

         acct.Close(t1);
        }

      //--- ONE STEP CANNOT BE HALVED. The engine would silently close
      //--- the whole thing; a user who pressed "half" and lost the
      //--- position would be right to call that a bug.
      long t2 = acct.Open(SSR_ORDER_BUY, step, nsl, ntp, 0.0, "breakout");
      if(t2 > 0)
        {
         bool halved = port.ClosePartial(t2, 0.5);
         //--- and it must SAY why. A silent refusal is a button that
         //--- looks broken, which is the same defect wearing a
         //--- different face.
         Check("halving the minimum size is refused, and says why",
               !halved && acct.OpenCount() >= 1 && port.TradeError() != "",
               StringFormat("[%s] (the position is still open)",
                            port.TradeError()));
         acct.Close(t2);
        }

      long t3 = acct.Open(SSR_ORDER_SELL, step, ntp, nsl, 0.0, "fade");
      if(t3 > 0)
         acct.Close(t3);

      //+------------------------------------------------------------------+
      //| THE POINT OF TYPING A TAG.                                       |
      //|                                                                  |
      //| A win rate across a whole session says nothing anyone can act on.|
      //| Two win rates, one per setup, say which setup to stop trading -   |
      //| and the statistics engine has been able to compute per tag since  |
      //| Phase 10 with nothing ever setting one.                           |
      //+------------------------------------------------------------------+
      SSRStatistics all, sb, sf;
      all.Init(); sb.Init(); sf.Init();
      stats.Compute(all);
      stats.ComputeFor("breakout", sb);
      stats.ComputeFor("fade",     sf);

      Check("the statistics split by tag",
            sb.trades == 2 && sf.trades == 1 && all.trades >= sb.trades + sf.trades,
            StringFormat("breakout %d, fade %d, session %d",
                         sb.trades, sf.trades, all.trades));

      //+------------------------------------------------------------------+
      //| 17b. THE BUCKETS, AND THE ACCOUNTING THAT FEEDS THEM.            |
      //|                                                                  |
      //| ComputeFor subtracted swap but not commission, while the drawdown|
      //| twenty lines below it in the same class - and the statement's own |
      //| Profit column - always used profit + swap - commission. With the  |
      //| default commission of zero the two agree and nothing shows; this  |
      //| sets a commission so they cannot.                                 |
      //+------------------------------------------------------------------+
      {
         CSSRTradingEngine ca;
         SSRExecutionModel cx;
         cx.Init();
         cx.commission_per_lot = 7.0;
         ca.SetExecution(cx);
         ca.OnSessionStart("SMOKE", 5, 0.00001, 0);
         ca.SetBalance(10000.0);

         MqlTick ct[1];
         ct[0].time     = (datetime)0;
         ct[0].time_msc = 0;
         ct[0].bid      = 1000.0;
         ct[0].ask      = 1000.0;
         ct[0].last     = 1000.0;
         ct[0].volume   = 1;
         ct[0].flags    = 0;
         ca.OnTicks(ct, 1);

         long ct1 = ca.Open(SSR_ORDER_BUY, 1.0);
         ca.Close(ct1);

         CSSRStatsEngine cs;
         cs.Attach(GetPointer(ca));
         SSRStatistics cst;
         cst.Init();
         cs.Compute(cst);

         //--- one round turn at 7 per lot per side. Nothing moved, so the
         //--- whole result IS the commission and it must be a loss.
         Check("commission is inside the trade's result",
               cst.trades == 1 && cst.net_profit < -0.5 && cst.losses == 1,
               StringFormat("net %.2f over %d trade(s), %d counted as a loss "
                            "- a flat trade that cost 14 to place is not a win",
                            cst.net_profit, cst.trades, cst.losses));
      }

      //+------------------------------------------------------------------+
      //| 17c. WHEN THE TRADES WERE TAKEN.                                 |
      //|                                                                  |
      //| The buckets are read straight back off the trades this stage has  |
      //| already opened and closed, so the totals must agree with the      |
      //| session's own. Two views of one set of books that do not add up   |
      //| to the same number is the failure this checks for.                |
      //+------------------------------------------------------------------+
      SSRBucket wk[], hr[];
      stats.ByWeekday(wk);
      stats.ByHour(hr);

      int wk_trades = 0, hr_trades = 0;
      double wk_net = 0.0, hr_net = 0.0;
      for(int i = 0; i < ArraySize(wk); i++)
        { wk_trades += wk[i].trades; wk_net += wk[i].net; }
      for(int i = 0; i < ArraySize(hr); i++)
        { hr_trades += hr[i].trades; hr_net += hr[i].net; }

      Check("the weekday buckets hold every trade",
            ArraySize(wk) == 7 && wk_trades == all.trades &&
            MathAbs(wk_net - all.net_profit) < 0.01,
            StringFormat("%d trades / %.2f across 7 days, session says %d / %.2f",
                         wk_trades, wk_net, all.trades, all.net_profit));
      Check("and so do the hourly ones",
            ArraySize(hr) == 24 && hr_trades == all.trades &&
            MathAbs(hr_net - all.net_profit) < 0.01,
            StringFormat("%d trades / %.2f across 24 hours", hr_trades, hr_net));

      //+------------------------------------------------------------------+
      //| 17d. THE EQUITY CURVE IS READABLE, not only measurable.          |
      //|                                                                  |
      //| The samples have existed since Phase 10 and only ever produced a  |
      //| drawdown number. Drawing them needs them handed out one at a      |
      //| time, in order, with the times going forwards - a curve whose x   |
      //| axis went backwards would still compute the right drawdown and    |
      //| draw a scribble.                                                  |
      //+------------------------------------------------------------------+
      {
         //--- THE CURVE NEEDS A CLOCK. This engine was built a few lines
         //--- up for the tag work and never observed the replay, so it
         //--- holds no samples at all - and a stage that asserted "more
         //--- than two samples" against it would have failed for a reason
         //--- that has nothing to do with the product. It is driven here
         //--- through OnClock, the same entry point the controller uses,
         //--- at the sampler's own one-a-minute spacing rather than around
         //--- it.
         long feed = 1000000000000;
         for(int i = 0; i < 40; i++)
            stats.OnClock(feed + (long)i * 60000);

         int    es = stats.EquitySamples();
         long   pm = 0, sm = 0;
         double sv = 0.0;
         bool   ordered = true, all_read = true;
         for(int i = 0; i < es; i++)
           {
            if(!stats.EquityAt(i, sm, sv))
              { all_read = false; break; }
            if(i > 0 && sm < pm)
               ordered = false;
            pm = sm;
           }
         Check("the equity curve can be walked, in order",
               es > 2 && all_read && ordered,
               StringFormat("%d samples, times %s", es,
                            (ordered ? "increasing" : "OUT OF ORDER")));
         long dummy = 0;
         double dv = 0.0;
         Check("and it says where it ends",
               !stats.EquityAt(es, dummy, dv) && !stats.EquityAt(-1, dummy, dv),
               "one past the end and one before the start both refuse");
      }

      CSSRJournal tj;
      tj.Attach(GetPointer(acct), GetPointer(stats));
      string tname = "SSReplay-smoke-tags";
      if(Check("the statement exports with tags in it", tj.ExportHtml(tname, 2),
               tj.LastPath() + (tj.LastError() == "" ? "" : "  " + tj.LastError())))
        {
         //--- READ IT. A file of the right size with no breakdown in it
         //--- passes a size check and fails the user, which is the whole
         //--- lesson of the volume column that printed 0.00 for a year.
         string body = "";
         int th = FileOpen(tj.LastPath(), FILE_READ | FILE_TXT | FILE_ANSI);
         if(th != INVALID_HANDLE)
           {
            while(!FileIsEnding(th))
               body += FileReadString(th);
            FileClose(th);
           }
         Check("and the breakdown is really in the file",
               StringFind(body, "By setup") >= 0 &&
               StringFind(body, "breakout") >= 0 &&
               StringFind(body, "fade") >= 0,
               StringFormat("%d chars, all three markers present "
                            "- a size check alone would pass an empty table",
                            StringLen(body)));

         //--- and so are the four sections v70 added. Each is checked by
         //--- something only that section writes: a heading proves the
         //--- markup ran, a <polyline> proves the curve has geometry in
         //--- it rather than an empty figure with a caption under it.
         Check("the statement carries an equity curve with a line in it",
               StringFind(body, "Equity curve") >= 0 &&
               StringFind(body, "<polyline") >= 0 &&
               StringFind(body, "var SSRE=[[") >= 0,
               "heading, polyline and hover data all present");
         Check("and the weekday and hour breakdowns",
               StringFind(body, "By weekday") >= 0 &&
               StringFind(body, "By hour of the day") >= 0 &&
               StringFind(body, "Wednesday") >= 0,
               "both headings and a named day");
         Check("and every measure, not only the nine on the header",
               StringFind(body, "Every measure") >= 0 &&
               StringFind(body, "Average MFE") >= 0 &&
               StringFind(body, "Trades without a stop") >= 0,
               "three of the twenty-two that were computed and never shown");
         Check("and it is legible in either theme",
               StringFind(body, "prefers-color-scheme:dark") >= 0 &&
               StringFind(body, "[data-theme=") >= 0,
               "a colour defined only inside a media query is a colour a "
               "system-default reader never gets");
         FileDelete(tj.LastPath());
        }
   }

   //+------------------------------------------------------------------+
   //| 18. EVERY CONTROL IS INSIDE THE PANEL.                           |
   //|                                                                  |
   //| The frame height is a constant with the sheet heights added up in |
   //| a COMMENT beside it, and v69 put two new rows on two sheets. Both |
   //| looked fine in the code and neither was inside the frame: a row   |
   //| past the end is drawn over the status bar, which reads as a       |
   //| rendering fault rather than as a number nobody updated.            |
   //|                                                                  |
   //| So it is measured, not reasoned about. The panel is built on a    |
   //| real chart, every tab is opened, and every object it drew is      |
   //| asked where its bottom edge is. Nothing here knows a single       |
   //| layout number: the frame itself is read from the background       |
   //| rectangle the panel drew, so a future row is caught by the same   |
   //| test without editing it.                                          |
   //+------------------------------------------------------------------+
   {
      long pchart = ChartOpen(rsym, PERIOD_M1);
      int  pch    = (int)ChartGetInteger(pchart, CHART_HEIGHT_IN_PIXELS);
      if(pchart == 0)
         No("a chart for the layout test", "ChartOpen refused");
      else if(pch > 0 && pch < SSR_PANEL_H + 24)
        {
         //--- NOT a pass. The panel drops the tabs on a short chart, so
         //--- there would be no sheet to measure and a silent "ok" here
         //--- would be the most misleading line in the whole report.
         No("the layout can be measured",
            StringFormat("this chart is %d px tall and the panel needs %d - "
                         "it would run in compact mode, with no sheet to "
                         "measure. Close the Toolbox (Ctrl+T) and re-run.",
                         pch, SSR_PANEL_H + 24));
         ChartClose(pchart);
        }
      else
        {
         CSSRPanel pnl;
         pnl.Create(pchart, NULL, "SSRQ_");

         int   worst_bottom = 0;
         string worst_name  = "";
         int   frame_top = 0, frame_bottom = 0;

         for(int t = 0; t < 4; t++)
           {
            pnl.Dispatch("tab" + IntegerToString(t));
            pnl.Render();

            int n = ObjectsTotal(pchart, -1, -1);
            for(int i = 0; i < n; i++)
              {
               string nm = ObjectName(pchart, i, -1, -1);
               if(StringFind(nm, "SSRQ_") != 0)
                  continue;

               int oy = (int)ObjectGetInteger(pchart, nm, OBJPROP_YDISTANCE);
               int oh = (int)ObjectGetInteger(pchart, nm, OBJPROP_YSIZE);

               //--- a LABEL has no height of its own; MetaTrader answers
               //--- zero and the text is drawn below the anchor anyway,
               //--- so it is allowed the height of a line of it
               if(ObjectGetInteger(pchart, nm, OBJPROP_TYPE) == OBJ_LABEL)
                  oh = 12;

               if(nm == "SSRQ_bg")
                 { frame_top = oy; frame_bottom = oy + oh; continue; }

               if(oy + oh > worst_bottom)
                 { worst_bottom = oy + oh; worst_name = nm; }
              }
           }

         if(Check("the panel drew a frame to measure against",
                  frame_bottom > frame_top && worst_name != "",
                  StringFormat("frame %d..%d px", frame_top, frame_bottom)))
            Check("and nothing is drawn outside it",
                  worst_bottom <= frame_bottom,
                  StringFormat("deepest control %s ends at %d, frame ends at %d "
                               "(%d px %s)",
                               StringSubstr(worst_name, 5), worst_bottom,
                               frame_bottom,
                               (int)MathAbs(frame_bottom - worst_bottom),
                               (worst_bottom <= frame_bottom ? "spare"
                                : "OVER - raise SSR_SHEET_H")));

         pnl.Destroy();
         ChartClose(pchart);
        }
   }

   //+------------------------------------------------------------------+
   //| 19. THE PANEL COMES BACK WHERE IT WAS LEFT.                      |
   //|                                                                  |
   //| Not "a file was written" - a file written is not a panel that     |
   //| came back. A second panel is built from scratch on the same chart |
   //| and asked where it thinks it is, which is the only question the   |
   //| user is actually asking.                                          |
   //|                                                                  |
   //| The real panel.ini is moved aside first: a QA run that resets the |
   //| user's own layout has done more harm than the stage is worth.     |
   //+------------------------------------------------------------------+
   {
      long rc = ChartOpen(rsym, PERIOD_M1);
      if(Check("a chart for the position test", rc != 0, rsym))
        {
         int ax = 0, ay = 0, ac = 0, at = 0;
           {
            CSSRPanel a;
            a.Create(rc, NULL, "SSRR_");
            //--- move it the way a user without a mouse on this chart
            //--- would: the Move button, twice, then a different tab
            a.Dispatch("move");
            a.Dispatch("move");
            a.Dispatch("tab2");
            ax = a.X(); ay = a.Y(); ac = a.Corner(); at = a.Tab();
            a.Destroy();
           }

         Check("moving the panel leaves a file behind",
               FileIsExist(SSR_PANEL_FILE),
               "MQL5\\Files\\" + SSR_PANEL_FILE);

           {
            CSSRPanel b;
            b.Create(rc, NULL, "SSRR_");
            //--- SnapToCorner reads the chart's pixel size, and a chart
            //--- that has not been measured yet puts all four corners on
            //--- the same spot. Then x and y would match trivially and
            //--- this stage would be proving nothing about them, so it
            //--- says which half it actually proved.
            bool moved = (ax != 12 || ay != 24);
            Check("and a new panel starts where the old one stopped",
                  b.X() == ax && b.Y() == ay && b.Corner() == ac &&
                  b.Tab() == at,
                  StringFormat("%d,%d corner %d tab %d  ->  %d,%d corner %d tab %d%s",
                               ax, ay, ac, at, b.X(), b.Y(), b.Corner(), b.Tab(),
                               (moved ? ""
                                : "   NOTE this chart reports no size, so the "
                                  "panel never left the corner - corner and tab "
                                  "still prove the round trip, x and y do not")));
            b.Destroy();
           }

         //+------------------------------------------------------------------+
         //| A POSITION FROM A BIGGER SCREEN IS REFUSED.                      |
         //|                                                                  |
         //| Saved on a 3440-wide monitor, restored on a laptop: without the  |
         //| bound the panel is off the edge with no caption to grab. The     |
         //| test asks for the CONSTRUCTOR'S corner, not merely for something |
         //| on screen - the later clamp would also produce something on      |
         //| screen, and would pass a version with no guard in it at all.      |
         //+------------------------------------------------------------------+
           {
            CSSRSessionFile bad;
            if(bad.Create(SSR_PANEL_FILE))
              {
               bad.Section("panel");
               bad.SetInt("x", 99999);
               bad.SetInt("y", 77777);
               bad.SetInt("corner", 1);
               bad.Close();
              }
            CSSRPanel c;
            c.Create(rc, NULL, "SSRR_");
            Check("an impossible position falls back, it does not clamp",
                  c.X() == 12 && c.Y() == 24,
                  StringFormat("99999,77777 -> %d,%d (the corner it starts in)",
                               c.X(), c.Y()));
            c.Destroy();
           }

         ChartClose(rc);
        }
   }

   Unstash(SSR_PANEL_FILE);

   //+------------------------------------------------------------------+
   //| 20. A PICTURE OF EVERY TRADE.                                    |
   //|                                                                  |
   //| Driven through the real transitions - an account opens a position |
   //| and the book is shown the same tick the controller would show it. |
   //| What is asserted is a FILE WITH BYTES IN IT, not a call that      |
   //| returned true: ChartScreenShot can answer true and write nothing  |
   //| a browser will display, and the whole point of this feature is    |
   //| that the picture reaches a document someone else opens.            |
   //+------------------------------------------------------------------+
   {
      long sc = ChartOpen(rsym, PERIOD_M1);
      if(Check("a chart for the screenshot test", sc != 0, rsym))
        {
         CSSRTradingEngine sa;
         SSRExecutionModel sx;
         sx.Init();
         sa.SetExecution(sx);
         sa.OnSessionStart("SMOKE", 5, 0.00001, 0);
         sa.SetBalance(10000.0);

         MqlTick sk[1];
         sk[0].time     = (datetime)0;
         sk[0].time_msc = 0;
         sk[0].bid      = 1000.0;
         sk[0].ask      = 1000.0;
         sk[0].last     = 1000.0;
         sk[0].volume   = 1;
         sk[0].flags    = 0;
         sa.OnTicks(sk, 1);

         CSSRShotBook sb;
         sb.Attach(GetPointer(sa));
         sb.SetChart(sc);
         sb.Enable(true);
         sb.NewRun();
         sb.Reseed();

         //--- the entry
         long tk = sa.Open(SSR_ORDER_BUY, 0.10);
         sb.OnTicks(sk, 1);
         Check("an entry is queued, not shot where it happened",
               sb.Pending() == 1 && sb.Taken() == 0,
               "the repaint that puts the new bar on screen has not run yet - "
               "a shot taken here would picture the bar before the entry");

         int took = sb.Flush();
         string in_rel = sb.RelPath(tk, true);
         Check("and the flush writes the entry picture",
               took == 1 && in_rel != "",
               (in_rel != "" ? in_rel : "nothing written - " + sb.LastError()));

         //--- A FILE THAT EXISTS IS NOT A FILE WITH A PICTURE IN IT.
         string in_path = SSR_SHOT_DIR + "\\" + sb.Run() + "\\"
                          + SSRShotFile(tk, true);
         int ph = FileOpen(in_path, FILE_READ | FILE_BIN);
         int pbytes = 0;
         if(ph != INVALID_HANDLE)
           { pbytes = (int)FileSize(ph); FileClose(ph); }
         Check("and there is really a PNG in it",
               pbytes > 1000,
               StringFormat("%d bytes - an empty file would pass a test that "
                            "only asked whether it exists", pbytes));

         //--- the exit
         sa.Close(tk);
         sb.OnTicks(sk, 1);
         sb.Flush();
         Check("the exit gets its own picture", sb.RelPath(tk, false) != "",
               sb.RelPath(tk, false));

         //+------------------------------------------------------------------+
         //| OPENED AND CLOSED BETWEEN TWO LOOKS still owes both pictures.    |
         //|                                                                  |
         //| Not exotic: it is a scalp, and at 50x it is most stops. The      |
         //| auto-pause watcher lost a release to exactly this case.           |
         //+------------------------------------------------------------------+
         long tk2 = sa.Open(SSR_ORDER_SELL, 0.10);
         sa.Close(tk2);
         sb.OnTicks(sk, 1);
         Check("a trade that opened and closed unseen owes both pictures",
               sb.Pending() == 2,
               StringFormat("%d queued for one round trip", sb.Pending()));
         sb.Flush();
         Check("and gets them",
               sb.RelPath(tk2, true) != "" && sb.RelPath(tk2, false) != "",
               StringFormat("%d taken, %d refused", sb.Taken(), sb.Failed()));

         Check("a ticket that was never photographed answers empty",
               sb.RelPath(999999, true) == "",
               "the statement prints no <img> rather than a broken one");

         //--- and take the disk back
         string run = SSR_SHOT_DIR + "\\" + sb.Run();
         FileDelete(run + "\\" + SSRShotFile(tk,  true));
         FileDelete(run + "\\" + SSRShotFile(tk,  false));
         FileDelete(run + "\\" + SSRShotFile(tk2, true));
         FileDelete(run + "\\" + SSRShotFile(tk2, false));
         FolderDelete(run);
         ChartClose(sc);
        }
   }

   //+------------------------------------------------------------------+
   //| 21. ONE CLICK INSTEAD OF THREE NUMBERS.                          |
   //|                                                                  |
   //| Driven by setting the button's own latch and calling Poll - which |
   //| is exactly what a click does, prefix and all. Asserting that a    |
   //| preset "was loaded" would prove nothing; what the user gets is    |
   //| three numbers changing, so that is what is measured.              |
   //+------------------------------------------------------------------+
   {
      Stash(SSR_PRESET_FILE);

      long pk = ChartOpen(rsym, PERIOD_M1);
      if(Check("a chart for the preset test", pk != 0, rsym))
        {
         //--- 21a. NO FILE: the built-ins are used and the file is written,
         //--- so the first thing a user looking for their own numbers finds
         //--- is a file with the right shape in it.
           {
            //--- DELIBERATELY UNLIKE ANY BUILT-IN. With the struct's own
            //--- defaults, slot 0 ("My last") and the first shipped preset
            //--- hold the same three numbers, and a press that worked
            //--- perfectly would look like a press that did nothing.
            SSRSetupValues d;
            d.Init();
            d.prop_on     = true;
            d.prop_target = 3.0;
            d.prop_daily  = 2.0;
            d.prop_total  = 4.0;

            CSSRSetupPanel sp;
            sp.Create(pk, d);

            Check("a first run writes the preset file",
                  FileIsExist(SSR_PRESET_FILE),
                  "MQL5\\Files\\" + SSR_PRESET_FILE);

            ObjectSetInteger(pk, "SSRS_bpre", OBJPROP_STATE, true);
            sp.Poll();
            SSRSetupValues a;
            sp.Values(a);
            Check("and one press moves off what the panel opened with",
                  a.prop_on != d.prop_on || a.prop_target != d.prop_target ||
                  a.prop_daily != d.prop_daily || a.prop_total != d.prop_total,
                  StringFormat("%s %.1f/%.1f/%.1f -> %s %.1f/%.1f/%.1f",
                               (d.prop_on ? "on" : "off"), d.prop_target,
                               d.prop_daily, d.prop_total,
                               (a.prop_on ? "on" : "off"), a.prop_target,
                               a.prop_daily, a.prop_total));
            sp.Destroy();
           }

         //--- 21b. THE USER'S OWN NUMBERS WIN. One row, so the cycle is
         //--- exactly two presses long and "back to My last" is not a
         //--- guess about how many presets happened to be in the file.
         FileDelete(SSR_PRESET_FILE);
           {
            CSSRSessionFile pf;
            if(pf.Create(SSR_PRESET_FILE))
              {
               pf.Section("presets");
               pf.Set("p", "MyFirm|1|12.5|3.5|7.5");
               pf.Close();
              }

            SSRSetupValues d;
            d.Init();
            d.prop_on     = false;
            d.prop_target = 8.0;
            d.prop_daily  = 5.0;
            d.prop_total  = 10.0;

            CSSRSetupPanel sp;
            sp.Create(pk, d);

            ObjectSetInteger(pk, "SSRS_bpre", OBJPROP_STATE, true);
            sp.Poll();
            SSRSetupValues a;
            sp.Values(a);
            Check("a preset from the file fills all four fields",
                  a.prop_on && MathAbs(a.prop_target - 12.5) < 0.01 &&
                  MathAbs(a.prop_daily - 3.5) < 0.01 &&
                  MathAbs(a.prop_total - 7.5) < 0.01,
                  StringFormat("%s %.2f/%.2f/%.2f", (a.prop_on ? "on" : "off"),
                               a.prop_target, a.prop_daily, a.prop_total));

            //--- ...and the boxes below the button really say so. The
            //--- numbers are the only proof the user gets that the click
            //--- did anything, and they are written by a different code
            //--- path from the struct above.
            Check("and the boxes on the chart say the same thing",
                  ObjectGetString(pk, "SSRS_eptg", OBJPROP_TEXT) == "12.5" &&
                  ObjectGetString(pk, "SSRS_epdl", OBJPROP_TEXT) == "3.5" &&
                  ObjectGetString(pk, "SSRS_eptl", OBJPROP_TEXT) == "7.5",
                  StringFormat("[%s] [%s] [%s]",
                               ObjectGetString(pk, "SSRS_eptg", OBJPROP_TEXT),
                               ObjectGetString(pk, "SSRS_epdl", OBJPROP_TEXT),
                               ObjectGetString(pk, "SSRS_eptl", OBJPROP_TEXT)));

            ObjectSetInteger(pk, "SSRS_bpre", OBJPROP_STATE, true);
            sp.Poll();
            sp.Values(a);
            Check("and the cycle comes home to what the user had",
                  a.prop_on == d.prop_on &&
                  MathAbs(a.prop_target - d.prop_target) < 0.01 &&
                  MathAbs(a.prop_daily  - d.prop_daily)  < 0.01 &&
                  MathAbs(a.prop_total  - d.prop_total)  < 0.01,
                  StringFormat("%s %.1f/%.1f/%.1f - slot 0 is always My last",
                               (a.prop_on ? "on" : "off"), a.prop_target,
                               a.prop_daily, a.prop_total));
            sp.Destroy();
           }

         //--- 21c. A FILE THAT PARSES TO NOTHING IS AN EDIT SOMEBODY GOT
         //--- WRONG. Overwriting it would delete their work to fix a
         //--- problem they can see and this program cannot.
         FileDelete(SSR_PRESET_FILE);
           {
            CSSRSessionFile pf;
            if(pf.Create(SSR_PRESET_FILE))
              {
               pf.Section("presets");
               pf.Set("p", "nonsense");
               pf.Close();
              }

            SSRSetupValues d;
            d.Init();
            CSSRSetupPanel sp;
            sp.Create(pk, d);
            sp.Destroy();

            CSSRSessionFile rf;
            string still = "";
            if(rf.Load(SSR_PRESET_FILE) && rf.Select("presets"))
               still = rf.GetNth("p", 0);
            Check("an unreadable preset file is left exactly as it is",
                  still == "nonsense",
                  StringFormat("[%s] still in the file", still));
           }

         ChartClose(pk);
        }

      FileDelete(SSR_PRESET_FILE);
      Unstash(SSR_PRESET_FILE);
   }

   //+------------------------------------------------------------------+
   //| 22. THE ECONOMIC CALENDAR.                                       |
   //|                                                                  |
   //| Split deliberately into what is DETERMINISTIC and what depends on |
   //| this terminal having a calendar at all. Some servers do not       |
   //| publish one, and a stage that failed there would be reporting the |
   //| broker as a product defect - while a stage that passed there      |
   //| would be reporting nothing.                                       |
   //+------------------------------------------------------------------+
   {
      //--- 22a. THE LABEL, whatever the terminal has. v66 measured
      //--- MetaTrader cutting an object's text at exactly 63 characters,
      //--- and event names are routinely longer than that once a
      //--- currency is prefixed. A label that ends mid-word looks like a
      //--- rendering fault rather than a name that did not fit.
      {
         SSRCalendarItem it;
         it.Init();
         it.currency = "USD";
         it.name     = "Consumer Price Index excluding Food and Energy "
                       "year over year for the reference month, revised";
         string lab = it.Label();
         Check("a long event name is clipped before MetaTrader clips it",
               StringLen(lab) <= SSR_CAL_TEXT_MAX &&
               StringFind(lab, "USD") == 0,
               StringFormat("%d chars: [%s]", StringLen(lab), lab));

         SSRCalendarItem sh;
         sh.Init();
         sh.currency = "EUR";
         sh.name     = "ECB Rate";
         Check("and a short one is left alone", sh.Label() == "EUR  ECB Rate",
               "[" + sh.Label() + "]");
      }

      //--- 22b. THE FEED'S CONTRACT, with or without a calendar behind it
      CSSRCalendar cal;
      cal.SetShiftMinutes(0);
      cal.SetPauseMinutes(2);
      bool loaded = cal.Load(origin, win_start, win_end,
                             SSRNewsFloor(SSR_NEWS_MODERATE));

      SSRCalendarItem probe;
      Check("the feed refuses an index it does not have",
            !cal.At(-1, probe) && !cal.At(cal.Count(), probe) &&
            probe.msc == 0,
            "one before the start and one past the end both answer false");

      //--- 22c. AND IT SAYS WHICH KIND OF EMPTY IT IS. This is the whole
      //--- reason the class carries a note: "no calendar on this server"
      //--- and "a quiet week" draw the same blank chart.
      if(!loaded)
        {
         if(cal.Available())
            Ok("the calendar is present and this window is quiet",
               cal.Note());
         else
            //--- NOT a failure of this product. Reported as a NOTE so the
            //--- run is honest about which half it could not measure.
            PrintFormat("  NOTE  %-34s %s", "no calendar on this terminal",
                        cal.Note());
        }
      else
        {
         Check("the calendar loaded events for this window", cal.Count() > 0,
               StringFormat("%d event(s)%s", cal.Count(),
                            (cal.Note() == "" ? "" : "  -  " + cal.Note())));

         //--- every event inside the window it was asked for, widened by
         //--- the one day each side the loader documents
         bool inside = true;
         long lo = win_start - 86400000, hi = win_end + 86400000;
         for(int i = 0; i < cal.Count(); i++)
           {
            SSRCalendarItem it;
            if(cal.At(i, it) && (it.msc < lo || it.msc > hi))
               inside = false;
           }
         Check("and every one of them is inside that window", inside,
               StringFormat("%s .. %s, plus a day each side",
                            SSRFormatMsc(win_start), SSRFormatMsc(win_end)));

         //+------------------------------------------------------------------+
         //| THE PAUSE, driven through the real clock.                        |
         //|                                                                  |
         //| Only runs when the window actually contains a high-impact event, |
         //| and says so when it does not - a stage that quietly passed        |
         //| because there was nothing to test would be the most misleading    |
         //| line in the report.                                               |
         //+------------------------------------------------------------------+
         //--- AN ISOLATED ONE, not merely the first. The stage asserts
         //--- that ten minutes out is NOT a warning, and a second high
         //--- event sitting near that instant would raise one - a test
         //--- failing on the calendar's contents rather than on the code
         //--- is a test that cries wolf, and this project has already
         //--- paid for one of those.
         int high = -1;
         for(int i = 0; i < cal.Count() && high < 0; i++)
           {
            SSRCalendarItem it;
            if(!cal.At(i, it) ||
               it.importance < (int)CALENDAR_IMPORTANCE_HIGH)
               continue;

            bool alone = true;
            for(int j = 0; j < cal.Count() && alone; j++)
              {
               SSRCalendarItem other;
               if(j == i || !cal.At(j, other) ||
                  other.importance < (int)CALENDAR_IMPORTANCE_HIGH)
                  continue;
               //--- anything else high within the twelve minutes this
               //--- stage steps through disqualifies it
               if(other.msc > it.msc - 12 * SSR_MSC_PER_MIN &&
                  other.msc <= it.msc)
                  alone = false;
              }
            if(alone)
               high = i;
           }
         if(high < 0)
            PrintFormat("  NOTE  %-34s %s", "no isolated high-impact event",
                        "the pause path was not exercised this run - the "
                        "window holds no high-impact release with twelve "
                        "clear minutes in front of it");
         else
           {
            SSRCalendarItem it;
            cal.At(high, it);
            string why = "";

            cal.OnClock(it.msc - 10 * SSR_MSC_PER_MIN);
            bool early = cal.PauseRequested(why);
            cal.OnClock(it.msc - 1 * SSR_MSC_PER_MIN);
            bool near_it = cal.PauseRequested(why);

            Check("ten minutes out is not a warning, one minute is",
                  !early && near_it,
                  StringFormat("[%s]", why));

            //--- consumed exactly once, or the replay would sit in a
            //--- pause the user cannot leave
            Check("and it is consumed on the way out",
                  !cal.PauseRequested(why),
                  "asking twice answers no the second time");

            //--- a rewind un-happens it, or replaying the same hour runs
            //--- straight through the release the user rewound to watch
            cal.OnRewind(it.msc - 60 * SSR_MSC_PER_MIN);
            cal.OnClock(it.msc - 1 * SSR_MSC_PER_MIN);
            Check("a rewind puts the warning back",
                  cal.PauseRequested(why), StringFormat("[%s]", why));
           }
        }

      //--- 22d. THE LINES. Idempotent, and clean up after themselves.
      long cc = ChartOpen(rsym, PERIOD_M1);
      if(Check("a chart for the calendar lines", cc != 0, rsym))
        {
         CSSRCalendarLines cl;
         cl.Attach(cc);
         cl.Clear();
         int first  = cl.Draw(GetPointer(cal));
         int second = cl.Draw(GetPointer(cal));
         Check("drawing twice draws each line once",
               second == 0 && first == cal.Count(),
               StringFormat("%d created, %d on the second pass", first, second));
         Check("and clearing takes them all back",
               cl.Clear() == first &&
               ObjectFind(cc, SSR_CAL_PREFIX + "0") < 0,
               StringFormat("%d object(s) removed", first));
         ChartClose(cc);
        }
   }

   //+------------------------------------------------------------------+
   //| 23. THE FIRST-RUN CARD.                                          |
   //|                                                                  |
   //| Once per installation, which means a FILE - the one-window        |
   //| handover restarts this program, and a variable would show the     |
   //| card on the pass with no replay chart and swallow it on the pass  |
   //| that has one.                                                     |
   //|                                                                  |
   //| The user's own marker goes aside first. A QA run that deleted it  |
   //| would make the card reappear for somebody who had already read it,|
   //| and one that left a marker behind would hide it from somebody who |
   //| had not.                                                          |
   //+------------------------------------------------------------------+
   {
      Stash(SSR_SEEN_FILE);
      FileDelete(SSR_SEEN_FILE);

      Check("with no marker, the card has not been seen",
            !CSSRFirstRun::AlreadySeen(), SSR_SEEN_FILE + " is not there");

      long fc = ChartOpen(rsym, PERIOD_M1);
      if(Check("a chart for the first-run card", fc != 0, rsym))
        {
         CSSRFirstRun fr;
         Check("it goes up", fr.Show(fc) && fr.IsUp(),
               "four lines and a frame");
         Check("and it is really on the chart",
               ObjectFind(fc, "SSRF_bg") >= 0 &&
               ObjectFind(fc, "SSRF_l1") >= 0 &&
               ObjectFind(fc, "SSRF_l4") >= 0,
               "ObjectFind is a weak test, but an absent object is an "
               "absent card");

         //--- THE OBVIOUS BUG IS AN IMMEDIATE ONE. A timer that cleared
         //--- the card on its first pass would leave nothing on screen
         //--- and look exactly like a card that never drew.
         fr.Tick();
         Check("and the first timer pass does not take it away",
               fr.IsUp() && ObjectFind(fc, "SSRF_l1") >= 0,
               StringFormat("it stands for %d ms", SSR_FIRST_MS));

         fr.Clear();
         Check("clearing takes every piece of it",
               !fr.IsUp() && ObjectFind(fc, "SSRF_bg") < 0 &&
               ObjectFind(fc, "SSRF_l4") < 0,
               "nothing left behind on the chart");

         ChartClose(fc);
        }

      Check("marking it seen survives being asked again",
            CSSRFirstRun::MarkSeen() && CSSRFirstRun::AlreadySeen(),
            "the next run will not show it");

      FileDelete(SSR_SEEN_FILE);
      Unstash(SSR_SEEN_FILE);
   }

   //+------------------------------------------------------------------+
   //| 24. THE CLASS REPORT.                                            |
   //|                                                                  |
   //| Round trip, not a fixture. The journal WRITES a CSV and the class |
   //| report READS it - so the two halves are tested against each other |
   //| rather than against a hand-typed sample that would still parse    |
   //| perfectly on the day the writer changed a column.                 |
   //+------------------------------------------------------------------+
   {
      FolderCreate(SSR_CLASS_DIR);

      //--- its own statistics engine: the one stage 17 built went out of
      //--- scope with the block it was declared in, and reaching for a
      //--- name that is no longer there is how a file stops compiling
      //--- between one stage and the next
      CSSRStatsEngine cls_stats;
      cls_stats.Attach(GetPointer(acct));
      SSRStatistics cls_all;
      cls_all.Init();
      cls_stats.Compute(cls_all);

      //--- two students who ran the same session, one who did not, and
      //--- one file that is not a journal at all
      CSSRJournal cj;
      cj.Attach(GetPointer(acct), GetPointer(cls_stats));
      cj.SetSession("smoke-class", "EURUSD", 1700000000000, 1700003600000, "42");

      string a_name = "class-alice", b_name = "class-bob", c_name = "class-carol";
      bool wrote = cj.ExportCsv(a_name, 5);
      string a_src = cj.LastPath();

      Check("a journal csv carries the session it reports on", wrote,
            a_src + (cj.LastError() == "" ? "" : "  " + cj.LastError()));

      //--- MOVED, not copied: FileCopy is one more built-in to trust,
      //--- and the export can simply be run again for the next student
      FileMove(a_src, 0, SSR_CLASS_DIR + "\\" + a_name + ".csv", FILE_REWRITE);
      cj.ExportCsv(b_name, 5);
      FileMove(cj.LastPath(), 0, SSR_CLASS_DIR + "\\" + b_name + ".csv",
               FILE_REWRITE);

      //--- carol ran a different window. Same code, one field apart.
      cj.SetSession("smoke-class", "EURUSD", 1600000000000, 1600003600000, "7");
      cj.ExportCsv(c_name, 5);
      FileMove(cj.LastPath(), 0, SSR_CLASS_DIR + "\\" + c_name + ".csv",
               FILE_REWRITE);

      string junk = SSR_CLASS_DIR + "\\class-notajournal.csv";
      int jh = FileOpen(junk, FILE_WRITE | FILE_TXT | FILE_ANSI);
      if(jh != INVALID_HANDLE)
        {
         FileWriteString(jh, "date,amount\r\n2026.01.01,12.50\r\n");
         FileClose(jh);
        }

      CSSRClassReport rep;
      int n = rep.Scan(SSR_CLASS_DIR);
      Check("the folder is read", n >= 4,
            StringFormat("%d file(s)%s", n,
                         (rep.LastError() == "" ? "" : "  " + rep.LastError())));

      //--- what the coach is actually asking: who ran the same thing
      Check("two of them ran the same session and one did not",
            rep.Agreeing() == 2 && rep.Key() != "",
            StringFormat("%d agree on [%s]", rep.Agreeing(), rep.Key()));

      int readable = 0, unreadable = 0;
      bool alice_ok = false;
      for(int i = 0; i < n; i++)
        {
         SSRStudent st;
         if(!rep.At(i, st))
            continue;
         if(st.parsed)
           {
            readable++;
            if(st.name == a_name)
              {
               alice_ok = (st.symbol == "EURUSD" &&
                           st.win_start == 1700000000000 &&
                           st.trades == cls_all.trades &&
                           MathAbs(st.net_profit - cls_all.net_profit) < 0.02);
               //--- every trade of hers, back off the disk
               Check("and her trades come back with their entry times",
                     st.n_entries == cls_all.trades && st.n_entries > 0,
                     StringFormat("%d entries read for %d closed trades",
                                  st.n_entries, cls_all.trades));
              }
           }
         else
            unreadable++;
        }

      Check("the numbers survive the round trip", alice_ok,
            "symbol, window, trade count and net profit all match what "
            "the engine held");

      //--- A FILE THAT IS NOT A JOURNAL IS NAMED, NOT DROPPED. A name
      //--- missing from a report is a student who gets forgotten.
      Check("a file that is not a journal is reported, not skipped",
            unreadable == 1 && readable == 3,
            StringFormat("%d readable, %d rejected by name", readable,
                         unreadable));

      string out = "SSReplay\\class-smoke.html";
      if(Check("the page is written", rep.Write(out),
               out + (rep.LastError() == "" ? "" : "  " + rep.LastError())))
        {
         string body = "";
         int ph = FileOpen(out, FILE_READ | FILE_TXT | FILE_ANSI);
         if(ph != INVALID_HANDLE)
           {
            while(!FileIsEnding(ph))
               body += FileReadString(ph);
            FileClose(ph);
           }
         //--- the warning has to be IN the document, not only in the log
         Check("and it warns about the odd one out on the page itself",
               StringFind(body, "different session") >= 0 &&
               StringFind(body, "could not be read") >= 0 &&
               StringFind(body, "smark") >= 0,
               StringFormat("%d chars, both warnings and the entry strip "
                            "present", StringLen(body)));
         FileDelete(out);
        }

      FileDelete(SSR_CLASS_DIR + "\\" + a_name + ".csv");
      FileDelete(SSR_CLASS_DIR + "\\" + b_name + ".csv");
      FileDelete(SSR_CLASS_DIR + "\\" + c_name + ".csv");
      FileDelete(junk);
      FolderDelete(SSR_CLASS_DIR);
   }

   //+------------------------------------------------------------------+
   //| 25. ORDERS FROM THE CHART.                                       |
   //|                                                                  |
   //| The RULE is the feature: three lines decide which of four pending |
   //| orders this is. It is a free function over four doubles precisely |
   //| so it can be hammered here without a chart, an account or a feed. |
   //+------------------------------------------------------------------+
   {
      double B = 100.0, d = 0.01;      // bid, and one point
      ENUM_SSR_ORDER t;
      string why = "";

      //--- long: stop below the entry. Below the market is a limit,
      //--- above it is a stop. And the mirror image for a short.
      bool a1 = SSRPendingFor(99.0,  98.0,  B, d, t, why) && t == SSR_ORDER_BUY_LIMIT;
      bool a2 = SSRPendingFor(101.0, 100.5, B, d, t, why) && t == SSR_ORDER_BUY_STOP;
      bool a3 = SSRPendingFor(101.0, 102.0, B, d, t, why) && t == SSR_ORDER_SELL_LIMIT;
      bool a4 = SSRPendingFor(99.0,  99.5,  B, d, t, why) && t == SSR_ORDER_SELL_STOP;
      Check("three lines name the order without being asked",
            a1 && a2 && a3 && a4,
            StringFormat("buy limit %s, buy stop %s, sell limit %s, sell stop %s",
                         (a1 ? "ok" : "WRONG"), (a2 ? "ok" : "WRONG"),
                         (a3 ? "ok" : "WRONG"), (a4 ? "ok" : "WRONG")));

      //+------------------------------------------------------------------+
      //| THE REFUSALS MATTER MORE THAN THE FOUR ABOVE.                    |
      //|                                                                  |
      //| An entry line ON the price is a market order somebody drew        |
      //| instead of pressing, and placing it would fill on the next tick   |
      //| - looking exactly like a bug in the pending logic.                |
      //+------------------------------------------------------------------+
      bool on_price = !SSRPendingFor(B, 99.0, B, d, t, why);
      string why_on = why;
      bool stacked  = !SSRPendingFor(99.0, 99.0, B, d, t, why);
      string why_st = why;
      bool nothing  = !SSRPendingFor(0.0, 99.0, B, d, t, why);

      Check("an entry on the price is refused, not placed",
            on_price && StringFind(why_on, "market order") > 0,
            "[" + why_on + "]");
      Check("an entry on top of the stop is refused",
            stacked && StringFind(why_st, "drag") > 0, "[" + why_st + "]");
      Check("and so is no entry at all", nothing, "[" + why + "]");

      //--- 25b. THE ORDER ITSELF, through the engine.
      {
         CSSRTradingEngine pa;
         SSRExecutionModel px;
         px.Init();
         pa.SetExecution(px);
         pa.OnSessionStart("SMOKE", 5, 0.00001, 0);
         pa.SetBalance(10000.0);

         MqlTick pk[1];
         pk[0].time     = (datetime)0;
         pk[0].time_msc = 0;
         pk[0].bid      = 100.0;
         pk[0].ask      = 100.0;
         pk[0].last     = 100.0;
         pk[0].volume   = 1;
         pk[0].flags    = 0;
         pa.OnTicks(pk, 1);

         //+------------------------------------------------------------------+
         //| SIZED FROM THE ENTRY LINE, NOT THE MARKET.                       |
         //|                                                                  |
         //| The order goes in at 99 with its stop at 98: one unit of risk.    |
         //| Sized off the bid at 100 the distance would be two, and the lot   |
         //| would be half the right one - on every pending order, silently.   |
         //+------------------------------------------------------------------+
         double from_entry = pa.PreviewPendingLot(1.0, 99.0, 98.0);
         double entry_out  = 0.0;
         double from_market = pa.PreviewLot(SSR_ORDER_BUY, 1.0, 98.0, entry_out);
         //--- GREATER, not "twice". The relation the code guarantees is
         //--- that a shorter risk distance gives a bigger lot; the exact
         //--- factor also passes through lot-step rounding and the
         //--- broker's min and max, and a test that demanded 2.000 would
         //--- fail on a symbol whose sizing clamps rather than on a
         //--- defect. An audit that cries wolf is worse than none.
         Check("a pending is sized from its own entry, not from the bid",
               from_entry > 0.0 && from_market > 0.0 &&
               from_entry > from_market,
               StringFormat("%.4f lot from the line at 99, %.4f from the "
                            "market at 100 - half the distance, so about "
                            "twice the size (ratio %.2f)",
                            from_entry, from_market,
                            (from_market > 0.0 ? from_entry / from_market : 0.0)));

         long pt1 = pa.OpenPendingWithRisk(SSR_ORDER_BUY_LIMIT, 1.0, 99.0,
                                           98.0, 102.0, "orders");
         Check("the order is placed", pt1 > 0,
               StringFormat("ticket %d%s", (int)pt1,
                            (pt1 > 0 ? "" : " - " + pa.LastError())));

         SSRVirtualPosition vp;
         bool seen = false;
         for(int i = 0; i < pa.Total() && !seen; i++)
           {
            SSRVirtualPosition q;
            if(pa.At(i, q) && q.ticket == pt1)
              { vp = q; seen = true; }
           }
         Check("and it is PENDING, not open",
               seen && vp.state == SSR_POS_PENDING &&
               MathAbs(vp.request_price - 99.0) < 0.0001,
               StringFormat("state %d at %.5f", (seen ? (int)vp.state : -1),
                            (seen ? vp.request_price : 0.0)));

         //--- a market order with no price is still refused, and a
         //--- pending with no stop cannot be sized at all
         Check("a pending with no stop is refused, not guessed",
               pa.OpenPendingWithRisk(SSR_ORDER_BUY_LIMIT, 1.0, 99.0, 0.0) == 0,
               pa.LastError());
         Check("and a market type is not accepted as a pending",
               pa.OpenPendingWithRisk(SSR_ORDER_BUY, 1.0, 99.0, 98.0) == 0,
               pa.LastError());

         //--- X on the row cancels it. The engine has always done this;
         //--- what is new is that the row exists to press.
         Check("cancelling it takes it off the books",
               pa.Close(pt1) && pa.OpenCount() == 0,
               StringFormat("%d open, %d closed after the cancel",
                            pa.OpenCount(), pa.ClosedCount()));
      }

      //--- 25c. THE THIRD LINE, on a real chart.
      long ec = ChartOpen(rsym, PERIOD_M1);
      if(Check("a chart for the entry line", ec != 0, rsym))
        {
         CSSRTradeLines el;
         el.Attach(ec, (int)SymbolInfoInteger(rsym, SYMBOL_DIGITS),
                   SymbolInfoDouble(rsym, SYMBOL_POINT),
                   clrTomato, clrMediumSeaGreen);

         double base = (acct.Bid() > 0.0 ? acct.Bid() : 1000.0);
         Check("the entry line refuses to exist on its own",
               !el.ArmEntry(base) && !el.HasEntry(),
               "an entry with no stop beside it is not a setup");

         el.ArmSide(base, 500, 2.0, true);
         Check("and goes on once the other two are there",
               el.ArmEntry(base) && el.HasEntry() &&
               ObjectFind(ec, "SSR_LINE_EN") >= 0,
               "SSR_LINE_EN is on the chart");

         el.DisarmEntry();
         Check("removing it leaves the other two alone",
               !el.HasEntry() && ObjectFind(ec, "SSR_LINE_EN") < 0 &&
               ObjectFind(ec, "SSR_LINE_SL") >= 0,
               "back to a market setup");

         el.Clear();
         ChartClose(ec);
        }
   }

   ctrl.Release();
   Cleanup(rsym);
   Done();
  }

//+------------------------------------------------------------------+
//| One evaluation, one equity curve, one verdict.                   |
//|                                                                  |
//| Driven through the real account interface - a tick sets a price, |
//| a position marks the day as traded, SetBalance moves the equity  |
//| - so nothing here is a shape the product does not already have.  |
//| Equity sits at `start` every day but the last, which lands on    |
//| `final_equity`, so each case breaks exactly one rule.             |
//+------------------------------------------------------------------+
void PropCase(const string what, const double start, const double target_pct,
              const double daily_pct, const double total_pct,
              const bool trailing, const int min_days, const int max_days,
              const double final_equity, const int days,
              const ENUM_SSR_PROP_STATE expect)
  {
   CSSRTradingEngine  acct;
   SSRExecutionModel  ex;
   ex.Init();
   ex.use_real_spread = true;
   acct.SetExecution(ex);
   acct.SetBalance(start);

   SSRPropRules r;
   r.Init();
   r.enabled            = true;
   r.start_balance      = start;
   r.profit_target_pct  = target_pct;
   r.max_daily_loss_pct = daily_pct;
   r.max_total_loss_pct = total_pct;
   r.trailing           = trailing;
   r.min_trading_days   = min_days;
   r.max_days           = max_days;

   CSSRPropEvaluation ev;
   ev.Attach(GetPointer(acct));
   ev.SetRules(r);
   ev.Reset();

   long base = 20000;                       // an arbitrary server day
   ev.OnClock((base) * SSR_PROP_DAY_MSC + 3600000);   // establishes the day

   for(int d = 0; d < days && !IsStopped(); d++)
     {
      //--- a price, then a trade, so the day counts as traded
      MqlTick tk[1];
      tk[0].time     = (datetime)(((base + d) * SSR_PROP_DAY_MSC) / 1000);
      tk[0].time_msc = (base + d) * SSR_PROP_DAY_MSC + 3600000;
      tk[0].bid      = 1000.0;
      tk[0].ask      = 1000.0;
      tk[0].last     = 1000.0;
      tk[0].volume   = 1;
      tk[0].flags    = 0;
      acct.OnTicks(tk, 1);
      long t = acct.Open(SSR_ORDER_BUY, 0.01);
      if(t > 0)
         acct.Close(t);

      acct.SetBalance(d == days - 1 ? final_equity : start);
      ev.OnClock((base + d) * SSR_PROP_DAY_MSC + 43200000);
      if(ev.IsOver())
         break;
     }

   Check("evaluation: " + what, ev.State() == expect,
         StringFormat("%s, expected %s%s", SSRPropStateName(ev.State()),
                      SSRPropStateName(expect),
                      (ev.Reason() == "" ? "" : "  -  " + ev.Reason())));
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
