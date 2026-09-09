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
#include <SSReplay/Ui/SSR_KeyCard.mqh>
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
#include <SSReplay/Ui/SSR_Layout.mqh>
#include <SSReplay/Ui/SSR_Palette.mqh>
#include <SSReplay/Ui/SSR_RevealCard.mqh>
#include <SSReplay/Ui/SSR_ReviewCard.mqh>
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

//+------------------------------------------------------------------+
//| EVERY LINE GOES TO A FILE AS WELL AS TO THE LOG.                 |
//|                                                                  |
//| The Experts tab is where these land, and getting them OUT of it  |
//| has cost a round trip nearly every time: select, scroll, copy,   |
//| hope nothing was missed. The tab is not a deliverable.            |
//|                                                                  |
//| So the run writes itself down. One file, plain text, the same    |
//| lines in the same order - and the last thing printed is where to |
//| find it. Nobody has to select anything again.                    |
//+------------------------------------------------------------------+
#define SSR_QA_RESULT_FILE  "SSReplay\\qa-result.txt"

int    g_fh    = INVALID_HANDLE;
int    g_out_n = 0;
string g_path  = "";
uint   g_t0    = 0;
uint   g_tlast = 0;

//+------------------------------------------------------------------+
//| WRITTEN AS IT HAPPENS, not collected and written at the end.      |
//|                                                                  |
//| A run that ends normally is the easy case. The runs that have     |
//| actually cost time this week are the ones that DID NOT end: an    |
//| array overrun that killed the program mid-stage, and a stage that |
//| hung and never returned. Both left an empty file and a log pane   |
//| somebody had to read by hand - which is the exact chore the file  |
//| was added to remove, failing in the one case that needed it.      |
//|                                                                  |
//| So the handle is opened first and every line is flushed. Whatever |
//| the run does next, the file already holds everything up to the    |
//| last thing that worked, and the last line in it names the place   |
//| it stopped.                                                       |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| AND OPENED IN A WAY THAT CANNOT SILENTLY GET NOTHING.            |
//|                                                                  |
//| Reported twice: "it hung and no file was made". Both times the    |
//| suite had in fact run. FileOpen without a share mode asks Windows |
//| for the file EXCLUSIVELY, and the obvious way to use this tool is |
//| to open qa-result.txt in an editor to copy it - which is exactly  |
//| what makes the next run unable to open it. It then wrote nowhere, |
//| the folder looked untouched, and a slow run and a dead one are    |
//| indistinguishable from outside.                                   |
//|                                                                  |
//| Two changes. FILE_SHARE_READ, so the run cannot lock out somebody |
//| reading the file it is writing. And when the usual name is taken  |
//| anyway, the run does NOT shrug and continue into the log pane: it |
//| writes a stamped file beside it and says so on the chart, where   |
//| the person waiting is actually looking.                           |
//+------------------------------------------------------------------+
void LogOpen(void)
  {
   g_t0    = GetTickCount();
   g_tlast = g_t0;
   FolderCreate("SSReplay");
   g_path = SSR_QA_RESULT_FILE;
   g_fh   = FileOpen(g_path, FILE_WRITE | FILE_TXT | FILE_ANSI |
                             FILE_SHARE_READ);
   if(g_fh == INVALID_HANDLE)
     {
      int err = GetLastError();
      string stamp = TimeToString(TimeLocal(), TIME_DATE | TIME_MINUTES);
      StringReplace(stamp, ".", "");
      StringReplace(stamp, ":", "");
      StringReplace(stamp, " ", "-");
      g_path = "SSReplay\\qa-result-" + stamp + ".txt";
      g_fh = FileOpen(g_path, FILE_WRITE | FILE_TXT | FILE_ANSI |
                              FILE_SHARE_READ);
      string note = StringFormat("%s could not be opened (err %d) - it is "
                                 "probably still open in an editor. Writing "
                                 "to %s instead.",
                                 SSR_QA_RESULT_FILE, err,
                                 (g_fh == INVALID_HANDLE ? "NOWHERE - the log "
                                  "pane is the only copy" : g_path));
      Print(note);
      Comment(note);
     }
  }

//+------------------------------------------------------------------+
//| AND PUT ON THE CHART, WHERE SOMEBODY IS ACTUALLY LOOKING.        |
//|                                                                  |
//| Three rounds have now been spent on "it got stuck", with no way   |
//| to say WHERE. The file flushes per line, so it holds the answer   |
//| - but only if it could be opened, and only if somebody thinks to  |
//| go and read a partial file that looks like a failure.             |
//|                                                                  |
//| The chart costs nothing and needs no thinking. The last check to  |
//| finish sits in the corner the whole run. If it stops changing,    |
//| that line is the last thing that worked, and the stage after it   |
//| is the one to look at. One glance replaces a round trip.          |
//|                                                                  |
//| The elapsed second count beside it separates the two things that  |
//| look identical from outside: a run that is SLOW keeps counting,   |
//| a run that is DEAD does not.                                      |
//+------------------------------------------------------------------+
void Log(const string line)
  {
   Print(line);
   g_out_n++;

   //--- a check that took real time says so, so the file is a profile
   //--- as well as a report and "which stage is slow" is answerable
   //--- from it without asking anyone to time anything by hand
   uint now = GetTickCount();
   uint dt  = now - g_tlast;
   g_tlast  = now;

   Comment(StringFormat("SS Replay smoke test   %s\n"
                        "line %d, %d seconds in\n%s\n\n"
                        "If this stops changing, THIS is where it stopped.",
                        SSR_BUILD, g_out_n, (int)((now - g_t0) / 1000), line));

   if(g_fh == INVALID_HANDLE)
      return;
   if(dt > 3000 && g_out_n > 1)
      FileWriteString(g_fh, StringFormat("  SLOW  the step before this one "
                                         "took %.1f seconds\r\n",
                                         dt / 1000.0));
   FileWriteString(g_fh, line + "\r\n");
   FileFlush(g_fh);                  // survive a stop, a crash, a hang
  }

void Ok(const string what, const string detail)
  { g_pass++; Log(StringFormat("  PASS  %-34s %s", what, detail)); }

void No(const string what, const string detail)
  { g_fail++; Log(StringFormat("  FAIL  %-34s %s", what, detail)); }

//+------------------------------------------------------------------+
//| DO NOT PUT A CALL THAT CHANGES SOMETHING IN THE COND ARGUMENT.   |
//|                                                                  |
//| MQL5 does not promise the order it evaluates a call's arguments   |
//| in, and in practice it builds `detail` BEFORE it runs `cond`. So  |
//|                                                                  |
//|   Check("it saves", mgr.Save(n), mgr.LastError());               |
//|                                                                  |
//| prints the error from the PREVIOUS call, and                     |
//|                                                                  |
//|   Check("...", lines.ArmSide(px,...), fmt(lines.SlPrice()));     |
//|                                                                  |
//| prints the stop from before it was armed. Six PASS lines in the   |
//| v90 run came back with an empty detail and one printed a LONG     |
//| setup under "the lines arm SHORT" - the checks were right and     |
//| every one of their evidence lines was a lie.                      |
//|                                                                  |
//| So: run it first, keep the answer in a bool, pass the bool.       |
//|                                                                  |
//|   bool saved = mgr.Save(n);                                       |
//|   Check("it saves", saved, mgr.LastError());                      |
//|                                                                  |
//| A read-only getter on both sides is fine - order cannot matter    |
//| when nothing moves.                                               |
//+------------------------------------------------------------------+
bool Check(const string what, const bool cond, const string detail)
  {
   if(cond) Ok(what, detail); else No(what, detail);
   return cond;
  }

void Note(const string what, const string detail)
  { Log(StringFormat("  NOTE  %-34s %s", what, detail)); }

//+------------------------------------------------------------------+
//| A BREADCRUMB BETWEEN TWO CHECKS.                                 |
//|                                                                  |
//| The chart shows the last line logged, so a freeze is located to   |
//| the gap AFTER it. Where that gap holds several terminal calls,    |
//| "somewhere in stage 26" is not an answer - and stage 26 is where  |
//| EURUSD@ stops, at line 152, seven seconds in, with the script     |
//| still attached to the chart. Still attached means blocked inside  |
//| a call, not killed by a runtime error: a script that dies is      |
//| removed from the chart.                                           |
//|                                                                  |
//| These name the individual call, so the next freeze names it too.  |
//+------------------------------------------------------------------+
void Step(const string where)
  { Log("  ..    " + where); }

//+------------------------------------------------------------------+
//| WHAT THE TERMINAL DID WITH THE TICKS WE GAVE IT.                 |
//|                                                                  |
//| "200 -> 200 bars" says the candles did not appear and stops       |
//| there, which leaves three very different faults looking the same: |
//| the engine never emitted, CustomTicksAdd refused, or the terminal |
//| took every tick and built nothing from them. Only the third is a  |
//| swallowed write, and only the numbers tell them apart.            |
//+------------------------------------------------------------------+
string TickVerdict(CSSRCustomSymbolSink &sink)
  {
   CSSRCustomSymbolManager *mgr = sink.Manager();
   if(mgr == NULL)
      return "";
   SSRSymbolStats st;
   mgr.StatsInto(st);
   if(st.ticks_calls <= 0)
      return "; the engine offered NO ticks to the terminal at all";
   return StringFormat("; %d call(s) offered ticks, the terminal took %d and "
                       "refused %d%s",
                       (int)st.ticks_calls, (int)st.ticks_added,
                       (int)st.ticks_rejected,
                       (st.ticks_rejected == 0 && st.ticks_added > 0
                        ? " - so it accepted every tick and built no bar from "
                          "them, which is a swallowed write, not a refusal"
                        : ""));
  }

//--- an object nobody can see is not on the panel, whether it was
//--- never created or drawn and then hidden. The panel hides by
//--- OBJPROP_TIMEFRAMES, so both cases answer the same question here.
bool QVisible(const long ch, const string nm)
  {
   if(ObjectFind(ch, nm) < 0)
      return false;
   return (ObjectGetInteger(ch, nm, OBJPROP_TIMEFRAMES) != OBJ_NO_PERIODS);
  }

//+------------------------------------------------------------------+
void OnStart()
  {
   LogOpen();
   Log(StringFormat("=== SS Replay smoke test === build %s", SSR_BUILD));
   Log(StringFormat("terminal %s   %s",
                    TerminalInfoString(TERMINAL_NAME),
                    TimeToString(TimeLocal(), TIME_DATE | TIME_MINUTES)));
   string origin = (InpSymbol == "" ? _Symbol : InpSymbol);
   Log(StringFormat("symbol %s", origin));

   //+------------------------------------------------------------------+
   //| SWEEP OUR OWN LEFTOVERS BEFORE ANYTHING ELSE.                    |
   //|                                                                  |
   //| The evidence says a symbol works ONCE. EURUSD@ passed on v90 and |
   //| has hung on every run since; USDJPY@ passed the first time it    |
   //| was tried. What a finished run leaves behind is a replay symbol  |
   //| that would not delete - Cleanup() prints a NOTE about it and     |
   //| carries on - and every later run then starts on top of it.       |
   //|                                                                  |
   //| Telling the user to go and run SSR_Z_Cleanup first is not a fix, |
   //| it is a chore with a note attached. The suite cleans up after    |
   //| itself, at the start, where it can still be sure of what it is   |
   //| looking at.                                                       |
   //|                                                                  |
   //| ONLY the slot this run uses - 9 by default, chosen to stay away  |
   //| from real sessions - so a sweep cannot reach a replay the user   |
   //| has running on slot 1 while this test runs.                       |
   //+------------------------------------------------------------------+
   {
      //--- the slot this run will actually use, not a 9 typed twice
      string tail  = SSR_SYMBOL_SUFFIX + IntegerToString(InpSlot);
      int    shut  = 0, gone = 0, kept = 0;
      string kept_names = "";

      long id = ChartFirst();
      while(id >= 0)
        {
         long nxt = ChartNext(id);
         string cs = ChartSymbol(id);
         if(StringLen(cs) > StringLen(tail) &&
            StringSubstr(cs, StringLen(cs) - StringLen(tail)) == tail)
           { ChartClose(id); shut++; }
         id = nxt;
        }
      if(shut > 0)
         Sleep(300);                 // the terminal needs a beat to let go

      for(int i = SymbolsTotal(false) - 1; i >= 0; i--)
        {
         string nm = SymbolName(i, false);
         if(StringLen(nm) <= StringLen(tail) ||
            StringSubstr(nm, StringLen(nm) - StringLen(tail)) != tail)
            continue;
         SymbolSelect(nm, false);
         ResetLastError();
         if(CustomSymbolDelete(nm))
            gone++;
         else
           {
            kept++;
            kept_names += StringFormat(" %s(err %d)", nm, GetLastError());
           }
        }

      if(shut + gone + kept > 0)
         Log(StringFormat("  ..    swept %d chart(s) and %d leftover symbol(s)"
                          "%s", shut, gone,
                          (kept > 0
                           ? StringFormat("; %d WOULD NOT GO:%s - this is the "
                                          "state a hung run leaves and the next "
                                          "one starts on top of",
                                          kept, kept_names)
                           : "")));
   }

   //--- 1. history -------------------------------------------------
   int have = Bars(origin, PERIOD_M1);
   if(!Check("M1 history present", have >= InpReplayBars + InpWarmupBars,
             StringFormat("%d bars local, %d needed",
                          have, InpReplayBars + InpWarmupBars)))
     {
      Log("  -> the EA downloads this automatically; run it once, or press "
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
      Log(StringFormat("  NOTE  window spans %d minutes for %d bars - it crosses a "
                  "market-closed gap. Play skips it.", (int)span_min, in_window));

   //--- 3. the data source -----------------------------------------
   CSSRMt5DataSource src;
   if(!Check("data source opens", src.Open(origin), origin))
     { Done(); return; }

   //--- 4. the custom symbol ---------------------------------------
   CSSRCustomSymbolSink sink;
   sink.SetSlot(InpSlot);
   string rsym = SSRReplaySymbolName(origin, InpSlot);
   Log(StringFormat("  ..    replay symbol will be %s", rsym));

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
         StringFormat("%d -> %d bars in %s%s%s", before_bars, after_bars, rsym,
                      (waited_ms > 0
                       ? StringFormat(" (the series took %d ms to rebuild)",
                                      waited_ms)
                       : ""),
                      (after_bars > before_bars ? "" : TickVerdict(sink))));

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
         Log(StringFormat("  NOTE  the view could not be scrolled away (%d bars, "
                     "%d visible) - the snap is untested on this screen",
                     Bars(rsym, PERIOD_M1), (int)away_vis));
      else
         Check("the view comes back to the newest bar", back_off < away_off,
               StringFormat("offset %d bars from the end -> %d after Redraw "
                            "(snaps=%d). If this does not fall, the candles "
                            "are being written off screen.",
                            (int)away_off, (int)back_off, (int)mgr.Snaps()));

      //+------------------------------------------------------------------+
      //| A CHART ALREADY AT THE END IS NOT DRAGGED THERE AGAIN.           |
      //|                                                                  |
      //| The snap exists for the case where CHART_AUTOSCROLL does not hold |
      //| on a custom symbol. Firing it on EVERY new bar made the two       |
      //| fight - and "new bar" is measured on M1 while the chart is M5 or  |
      //| higher, so a view that was exactly where it belonged got          |
      //| re-anchored five times for every candle the user could see. That  |
      //| is what "the chart jumps" was.                                    |
      //+------------------------------------------------------------------+
      long snaps_before = mgr.Snaps();
      mgr.Sync();  mgr.Redraw(true);
      mgr.Sync();  mgr.Redraw(true);
      Check("a view already at the end is left alone",
            mgr.Snaps() == snaps_before,
            StringFormat("%d snap(s) over two redraws with the view at the "
                         "newest bar - anything above zero is the terminal "
                         "and this manager pulling the same view in turn",
                         (int)(mgr.Snaps() - snaps_before)));

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
         StringFormat("%d -> %d bars after 250ms%s", step_before, step_after,
                      (step_after > step_before ? "" : TickVerdict(sink))));

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
   //+------------------------------------------------------------------+
   //| WHEN IT FAILS, SAY WHERE THE BARS WENT.                          |
   //|                                                                  |
   //| "272 -> 132" is a fact and not a diagnosis. Bars can only leave  |
   //| a custom symbol from one end or the other, so the first and last |
   //| times before and after separate the three possible stories: the  |
   //| write was refused, the series was rebuilt from the ticks and     |
   //| lost its head, or the terminal trimmed its own cache. Without    |
   //| them the next round trip is spent asking for them.                |
   //+------------------------------------------------------------------+
   int  jump_before = Bars(rsym, PERIOD_M1);
   datetime jb_first = (datetime)SeriesInfoInteger(rsym, PERIOD_M1, SERIES_FIRSTDATE);
   datetime jb_last  = (datetime)SeriesInfoInteger(rsym, PERIOD_M1, SERIES_LASTBAR_DATE);
   long jump_target = ctrl.Now() + 60 * SSR_MSC_PER_MIN;
   if(jump_target < win_end)
     {
      bool jump_ok = ctrl.JumpTo(jump_target);
      Sleep(300);
      int jump_after = Bars(rsym, PERIOD_M1);
      datetime ja_first = (datetime)SeriesInfoInteger(rsym, PERIOD_M1, SERIES_FIRSTDATE);
      datetime ja_last  = (datetime)SeriesInfoInteger(rsym, PERIOD_M1, SERIES_LASTBAR_DATE);
      //--- and say whether the HEAD survived, which is the part that was
      //--- being lost. The count alone cannot tell a jump that added
      //--- forty bars from one that added forty and dropped a hundred.
      Check("a jump keeps the history that was already there",
            ja_first <= jb_first,
            StringFormat("series starts at %s, started at %s - every "
                         "indicator on the replay chart reads this history",
                         TimeToString(ja_first), TimeToString(jb_first)));

      if(jump_after < jump_before)
         Log(StringFormat("  ->  the series LOST bars. before %d [%s .. %s], "
                     "after %d [%s .. %s], the engine said ok=%d. A later first "
                     "date means the head was dropped; an earlier last date "
                     "means the tail was.",
                     jump_before, TimeToString(jb_first), TimeToString(jb_last),
                     jump_after,  TimeToString(ja_first), TimeToString(ja_last),
                     (jump_ok ? 1 : 0)));
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
      Log(StringFormat("  NOTE  no room ahead to test a jump (%d minutes left)",
                  (int)((win_end - ctrl.Now()) / SSR_MSC_PER_MIN)));

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
   bool rec_open = rec.Open("smoke");
   if(Check("the black box can open a file", rec_open, rec.Path()))
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

      bool did_close = acct.Close(ticket);
      Check("it closes", did_close,
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
      bool jrn_ok = jrn.ExportHtml(html, 2);
      if(Check("the statement exports", jrn_ok,
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
                   SSR_C_LINE_SL, SSR_C_LINE_TP);

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
      bool armed_short = lines.ArmSide(lpx, 500, 2.0, false);
      Check("the lines arm SHORT with the stop above the price",
            armed_short && lines.SlPrice() > lpx && lines.TpPrice() < lpx,
            StringFormat("price %s  sl %s  tp %s", DoubleToString(lpx, 5),
                         DoubleToString(lines.SlPrice(), 5),
                         DoubleToString(lines.TpPrice(), 5)));

      lines.SetStopPoints(lpx, 600);
      Check("and a stop distance does not flip it back to long",
            lines.SlPrice() > lpx && lines.TpPrice() < lpx,
            StringFormat("after SetStopPoints: sl %s  tp %s - below the price "
                         "here means a short can never be placed",
                         DoubleToString(lines.SlPrice(), 5),
                         DoubleToString(lines.TpPrice(), 5)));

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
   bool saved = smgr.Save(sname, sset);
   if(Check("a session saves", saved,
            (smgr.LastError() == "" ? smgr.LastPath() : smgr.LastError())))
     {
      Check("and the file is there afterwards", smgr.Exists(sname),
            smgr.LastPath());

      long r_start = 0, r_end = 0;
      bool read_ok = smgr.ReadWindow(sname, 0, r_start, r_end);
      Check("and the window reads back", read_ok && r_end > r_start,
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
      a.random_start  = true;
      a.seed          = "class-2026-09";

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
               b.prop_daily == a.prop_daily && b.prop_total == a.prop_total &&
               b.random_start == a.random_start && b.seed == a.seed,
               StringFormat("balance %.2f  tf %s  extra [%s]  blind %s  "
                            "eval %s  session [%s]  random %s  seed [%s]",
                            b.balance, SSRSetupTfName(b.chart_tf), b.extra_tfs,
                            SSRSetupBlindName(b.blind),
                            (b.prop_on ? "on" : "off"), b.session_name,
                            (b.random_start ? "on" : "off"), b.seed));

         //+------------------------------------------------------------------+
         //| A SEED THAT DOES NOT SURVIVE IS NOT A SEED.                      |
         //|                                                                  |
         //| It is the one field whose entire purpose is to leave this        |
         //| machine and come back - to a student, into a lesson plan, into   |
         //| a bug report. Checked on its own so a failure names the seed     |
         //| rather than being one term in a twelve-way AND.                   |
         //+------------------------------------------------------------------+
         Check("34 the seed survives the round trip exactly",
               b.seed == "class-2026-09",
               StringFormat("[%s] - the same seed and symbol must give the "
                            "same session, or coaching, the class report and "
                            "every 'this is what broke it' are guesses",
                            b.seed));

         //+------------------------------------------------------------------+
         //| MODE IS A SHORTCUT OVER SETTINGS THAT ALREADY EXIST.             |
         //|                                                                  |
         //| There is no `mode` field, deliberately - a fifth source of truth |
         //| that has to agree with four others is the one that disagrees.    |
         //| So the test is that the settings a mode writes are the settings  |
         //| it reads back, and that the panel opens on what is TRUE rather   |
         //| than on what was last clicked.                                    |
         //+------------------------------------------------------------------+
         SSRSetupValues m;
         m.Init();
         Check("34 a fresh setup is Standard",
               !m.random_start && !m.prop_on && m.blind == SSR_BLIND_OFF,
               "nothing on until something is chosen");

         m.Init(); m.blind = SSR_BLIND_STANDARD;
         Check("34 blind alone reads as Blind",
               m.blind != SSR_BLIND_OFF && !m.prop_on && !m.random_start, "");
         m.Init(); m.prop_on = true;
         Check("34 prop alone reads as Prop",
               m.prop_on && !m.random_start && m.blind == SSR_BLIND_OFF, "");
         m.Init(); m.random_start = true;
         Check("34 random alone reads as Random", m.random_start, "");

         //--- and the combination the modes are deliberately not exclusive
         //--- about: a prop challenge run blind is a real thing to practise
         m.Init(); m.prop_on = true; m.blind = SSR_BLIND_FULL;
         Check("34 prop and blind can both be on",
               m.prop_on && m.blind == SSR_BLIND_FULL,
               "a challenge practised blind is a real exercise, and the "
               "caption shows both chips because both settings are on");
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
         bool halved = port.ClosePartial(t1, 0.5);
         Check("half of it closes", halved,
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

         bool be_ok = port.BreakEven(t1);
         Check("break-even puts the stop at the entry", be_ok,
               (port.TradeError() == "" ? "stop moved" : port.TradeError()));
         bool trail_ok = port.SetTrailing(250.0);
         Check("a trailing distance reaches the open trade", trail_ok,
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
      bool tj_ok = tj.ExportHtml(tname, 2);
      if(Check("the statement exports with tags in it", tj_ok,
               tj.LastPath() + (tj.LastError() == "" ? "" : "  " + tj.LastError())))
        {
         //--- READ IT. A file of the right size with no breakdown in it
         //--- passes a size check and fails the user, which is the whole
         //--- lesson of the volume column that printed 0.00 for a year.
         string body = "";
         int th = FileOpen(tj.LastPath(), FILE_READ | FILE_TXT | FILE_ANSI);
         if(th != INVALID_HANDLE)
           {
            while(!FileIsEnding(th) && !IsStopped())
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
   //| 18. EVERY CONTROL IS INSIDE THE PANEL - IN WHICHEVER MODE IT IS. |
   //|                                                                  |
   //| The frame height is a constant with the sheet heights added up in |
   //| a COMMENT beside it, and v69 put two new rows on two sheets. Both |
   //| looked fine in the code and neither was inside the frame: a row   |
   //| past the end is drawn over the status bar, which reads as a       |
   //| rendering fault rather than as a number nobody updated.            |
   //|                                                                  |
   //| So it is measured, not reasoned about. The panel is built on a    |
   //| real chart and every object it drew is asked where its bottom     |
   //| edge is. Nothing here knows a single layout number: the frame     |
   //| itself is read from the background rectangle the panel drew, so   |
   //| a future row is caught by the same test without editing it.       |
   //|                                                                  |
   //| WHICH MODE gets measured is not this test's choice. The panel     |
   //| reads the chart it is standing on, and on a terminal with the     |
   //| Toolbox open there is no room for the tabs. For two builds this   |
   //| stage FAILED there and told the user to rearrange their windows;  |
   //| that is a test declining to test what the product really does on  |
   //| that screen. Now it measures whichever mode it was given, holds   |
   //| both to the same invariant, and says plainly which one went       |
   //| unmeasured.                                                       |
   //+------------------------------------------------------------------+
   {
      long pchart = ChartOpen(rsym, PERIOD_M1);
      int  pch    = (int)ChartGetInteger(pchart, CHART_HEIGHT_IN_PIXELS);
      if(Check("a chart for the layout test", pchart != 0, rsym))
        {
         CSSRPanel pnl;
         pnl.Create(pchart, NULL, "SSRQ_");
         pnl.Render();

         bool compact = pnl.IsCompact();
         Check("the panel picked the mode this chart can hold",
               compact == (pch > 0 && pch < SSR_PANEL_H + 24),
               StringFormat("%s mode on a chart %d px tall - the full panel "
                            "needs %d",
                            (compact ? "compact" : "full"), pch,
                            SSR_PANEL_H + 24));

         int   worst_bottom = 0;
         string worst_name  = "";
         int   frame_top = 0, frame_bottom = 0;

         //--- the tab strip only exists in full mode, so only full mode
         //--- has four layouts to walk. Compact has exactly one, and it
         //--- is measured by the same code against the same invariant.
         int sheets = (compact ? 1 : 4);
         for(int t = 0; t < sheets; t++)
           {
            if(!compact)
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

         //+------------------------------------------------------------------+
         //| The caption is the one row the frame test cannot police: its    |
         //| controls are laid out from BOTH ends, so "inside the frame"     |
         //| stays true right up to the moment a chip lands on a button.     |
         //| Measured here from the objects themselves.                       |
         //+------------------------------------------------------------------+
         int chip_end = 0;
         string chips[] = {"SSRQ_chfid_bg", "SSRQ_chblind_bg", "SSRQ_chprop_bg"};
         for(int ci = 0; ci < ArraySize(chips); ci++)
            if(ObjectFind(pchart, chips[ci]) >= 0)
              {
               int ce = (int)ObjectGetInteger(pchart, chips[ci], OBJPROP_XDISTANCE) +
                        (int)ObjectGetInteger(pchart, chips[ci], OBJPROP_XSIZE);
               if(ce > chip_end) chip_end = ce;
              }
         int btn_start = 0;
         if(ObjectFind(pchart, "SSRQ_palette") >= 0)
            btn_start = (int)ObjectGetInteger(pchart, "SSRQ_palette",
                                              OBJPROP_XDISTANCE);
         Check("the caption's chips clear its buttons",
               chip_end > 0 && btn_start > 0 && chip_end <= btn_start,
               StringFormat("chips end at %d, buttons start at %d (%d px %s)",
                            chip_end, btn_start, btn_start - chip_end,
                            (chip_end <= btn_start ? "clear"
                             : "OVERLAP - a mode is printed under a button")));

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

         if(compact)
           {
            //+---------------------------------------------------------+
            //| COMPACT IS A MODE, NOT AN ERROR.                        |
            //|                                                         |
            //| For two builds this stage FAILED on any terminal with   |
            //| the Toolbox open, and told the user to rearrange their   |
            //| windows. That is a test refusing to test the thing the   |
            //| product actually does on that screen. The panel drops    |
            //| what is CONSULTED and keeps what is OPERATED - so that   |
            //| is what gets measured here, and the full-tab layout      |
            //| says out loud that it went unmeasured.                   |
            //+---------------------------------------------------------+
            Check("the compact panel fits the chart it shrank for",
                  pch > 0 && frame_bottom <= pch,
                  StringFormat("frame ends at %d on a %d px chart - a panel "
                               "that shrinks and still hangs off the bottom "
                               "has shrunk for nothing",
                               frame_bottom, pch));

            string driven[] = {"toggle","step","back","restart","spdbox","status"};
            string missing  = "";
            for(int i = 0; i < ArraySize(driven); i++)
               if(!QVisible(pchart, "SSRQ_" + driven[i]))
                  missing += (missing == "" ? "" : ",") + driven[i];
            Check("and kept everything the replay is driven with",
                  missing == "",
                  (missing == ""
                   ? "clock, transport, speed and status all on the chart"
                   : "MISSING " + missing + " - compact must cost the user "
                     "reading, never control"));

            Check("and dropped only what is consulted",
                  !QVisible(pchart, "SSRQ_tab0") &&
                  !QVisible(pchart, "SSRQ_tabline"),
                  "the tab strip and its sheet are gone; they come back the "
                  "moment there is room");

            Note("the four tab sheets were not measured",
                 StringFormat("this chart is %d px and compact mode has no "
                              "sheet - close the Toolbox (Ctrl+T) and re-run "
                              "to measure them", pch));
           }

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
            Log(StringFormat("  NOTE  %-34s %s", "no calendar on this terminal",
                        cal.Note()));
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
            Log(StringFormat("  NOTE  %-34s %s", "no isolated high-impact event",
                        "the pause path was not exercised this run - the "
                        "window holds no high-impact release with twelve "
                        "clear minutes in front of it"));
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
      int jh = FileOpen(junk, FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_SHARE_READ);
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
      bool page_written = rep.Write(out);
      if(Check("the page is written", page_written,
               out + (rep.LastError() == "" ? "" : "  " + rep.LastError())))
        {
         string body = "";
         int ph = FileOpen(out, FILE_READ | FILE_TXT | FILE_ANSI);
         if(ph != INVALID_HANDLE)
           {
            while(!FileIsEnding(ph) && !IsStopped())
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
         bool no_stop = (pa.OpenPendingWithRisk(SSR_ORDER_BUY_LIMIT,
                                               1.0, 99.0, 0.0) == 0);
         Check("a pending with no stop is refused, not guessed",
               no_stop, pa.LastError());
         bool not_pending = (pa.OpenPendingWithRisk(SSR_ORDER_BUY,
                                                   1.0, 99.0, 98.0) == 0);
         Check("and a market type is not accepted as a pending",
               not_pending, pa.LastError());

         //--- X on the row cancels it. The engine has always done this;
         //--- what is new is that the row exists to press.
         bool cancelled = pa.Close(pt1);
         Check("cancelling it takes it off the books",
               cancelled && pa.OpenCount() == 0,
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
                   SSR_C_LINE_SL, SSR_C_LINE_TP);

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

         Step("26 clearing the entry lines");
         el.Clear();
         //--- CSSRCustomSymbolManager::Destroy already carries this
         //--- lesson - "the terminal needs a beat to release a
         //--- just-closed chart" - and the QA has never given it one.
         //--- It is not a diagnosis, it is the one cheap thing the
         //--- evidence permits: the freeze is inside a call in this
         //--- gap, and this gap closes a chart that still holds
         //--- objects whose owner is destroyed a line later.
         Step("26 closing the entry-line chart");
         ChartClose(ec);
         Sleep(50);
         Step("26 entry-line chart closed");
        }
   }

   //+------------------------------------------------------------------+
   //| 26. EXECUTION HONESTY.                                           |
   //|                                                                  |
   //| Every one of these passed before the behaviour it checks existed,|
   //| because a stop that always filled at its own level and a bar     |
   //| context that belonged to a different minute both look like a     |
   //| working replay from outside. Driven straight through the engine  |
   //| with hand-made ticks: no chart, no data, nothing to be flaky.    |
   //|                                                                  |
   //| EVERY PRICE IS BUILT FROM THE INSTRUMENT, never typed in.        |
   //|                                                                  |
   //| The first version of this stage wrote 1.10000 and 1.09900 as if  |
   //| every chart were EURUSD. Run on an index with one digit, both    |
   //| normalise to the same number: the gap was not a gap, nothing was |
   //| closed, and four checks failed while reporting "filled 0, stop   |
   //| was 1". A test that only works on the instrument its author had  |
   //| open is not a test, it is a coincidence.                         |
   //+------------------------------------------------------------------+
   {
      int    dg = (int)SymbolInfoInteger(origin, SYMBOL_DIGITS);
      double pt = SymbolInfoDouble(origin, SYMBOL_POINT);
      if(pt <= 0.0) pt = 0.00001;

      //--- somewhere real to work from, and a fallback that is still
      //--- large compared with a point when the terminal has no price
      double base = SymbolInfoDouble(origin, SYMBOL_BID);
      if(base <= 0.0) base = 10000.0 * pt;
      base = NormalizeDouble(base, dg);

      double spread = 10.0 * pt;      // a plausible one, in points
      Step(StringFormat("26 read %s: digits %d, point %s, bid %s",
                        origin, dg, DoubleToString(pt, 8),
                        DoubleToString(base, dg)));

      //--- 26a. A STOP IS A MARKET ORDER ONCE IT IS TOUCHED.
      {
         Step("26a building the engine");
         CSSRTradingEngine ex;
         ex.SetBalance(10000.0);
         Step("26a reading the instrument into the risk model");
         ex.OnSessionStart(origin, dg, pt, 0);

         MqlTick t[1];
         t[0].bid = base; t[0].ask = base + spread; t[0].time_msc = 1000;
         Step("26a first tick");
         ex.OnTicks(t, 1);
         Step("26a opening the position");

         double sl = NormalizeDouble(base - 100.0 * pt, dg);
         long tk = ex.Open(SSR_ORDER_BUY, 0.10, sl, 0.0);
         Check("26a a position to gap through", tk > 0, ex.LastError());

         //--- the gap: the next tick is far below the stop, which is
         //--- exactly what a weekend open or a release looks like
         double gap = NormalizeDouble(base - 500.0 * pt, dg);
         t[0].bid = gap; t[0].ask = gap + spread; t[0].time_msc = 2000;
         ex.OnTicks(t, 1);

         SSRVirtualPosition gp;
         bool found = false;
         for(int i = 0; i < ex.Total(); i++)
            if(ex.At(i, gp) && gp.ticket == tk) { found = true; break; }

         Check("26a the gap closed it", found && gp.IsClosed(),
               StringFormat("stop %s, price gapped to %s",
                            DoubleToString(sl, dg), DoubleToString(gap, dg)));
         Check("26a and NOT at the stop price",
               found && gp.close_price < sl - pt * 0.5,
               StringFormat("filled %s, stop was %s - a stop that always fills "
                            "at its own level flatters every loss",
                            DoubleToString(found ? gp.close_price : 0.0, dg),
                            DoubleToString(sl, dg)));
         Check("26a it filled where the price actually was",
               found && MathAbs(gp.close_price - gap) < pt,
               StringFormat("filled %s, the gap was to %s",
                            DoubleToString(found ? gp.close_price : 0.0, dg),
                            DoubleToString(gap, dg)));
      }

      //--- 26b. SLIPPAGE REACHES AN EXIT, not just an entry.
      {
         CSSRTradingEngine ex;
         SSRExecutionModel em;
         em.Init();
         em.slippage_points = 20;
         ex.SetBalance(10000.0);
         ex.SetExecution(em);
         ex.OnSessionStart(origin, dg, pt, 0);

         MqlTick t[1];
         t[0].bid = base; t[0].ask = base + spread; t[0].time_msc = 1000;
         ex.OnTicks(t, 1);

         double sl = NormalizeDouble(base - 100.0 * pt, dg);
         long tk = ex.Open(SSR_ORDER_BUY, 0.10, sl, 0.0);

         //--- touched EXACTLY, no gap: the difference between the fill
         //--- and the stop can then only be slippage
         t[0].bid = sl; t[0].ask = sl + spread; t[0].time_msc = 2000;
         ex.OnTicks(t, 1);

         SSRVirtualPosition sp;
         bool found = false;
         for(int i = 0; i < ex.Total(); i++)
            if(ex.At(i, sp) && sp.ticket == tk) { found = true; break; }

         Check("26b slippage is applied to the exit",
               found && sp.IsClosed() && sp.close_price < sl - pt * 10.0,
               StringFormat("filled %s against a stop of %s with 20 points set",
                            DoubleToString(found ? sp.close_price : 0.0, dg),
                            DoubleToString(sl, dg)));
      }

      //--- 26c. A BAR CONTEXT FROM ANOTHER MINUTE IS NOT EVIDENCE.
      {
         CSSRTradingEngine ex;
         ex.SetBalance(10000.0);
         ex.OnSessionStart(origin, dg, pt, 0);

         //--- a bar from an hour ago whose range holds both levels
         MqlRates stale;
         stale.time  = (datetime)0;
         stale.open  = base;
         stale.high  = NormalizeDouble(base + 500.0 * pt, dg);
         stale.low   = NormalizeDouble(base - 1000.0 * pt, dg);
         stale.close = base;
         stale.tick_volume = 1; stale.spread = 1; stale.real_volume = 0;
         ex.OnBarContext(stale, true);

         MqlTick t[1];
         t[0].bid = base; t[0].ask = base + spread;
         t[0].time_msc = SSR_MSC_PER_HOUR;          // an hour past that bar
         ex.OnTicks(t, 1);

         double sl = NormalizeDouble(base - 200.0 * pt, dg);
         double tp = NormalizeDouble(base + 200.0 * pt, dg);
         long tk = ex.Open(SSR_ORDER_BUY, 0.10, sl, tp);

         //--- the target, and only the target, is reached
         t[0].bid = tp; t[0].ask = tp + spread;
         t[0].time_msc = SSR_MSC_PER_HOUR + 1000;
         ex.OnTicks(t, 1);

         SSRVirtualPosition cp;
         bool found = false;
         for(int i = 0; i < ex.Total(); i++)
            if(ex.At(i, cp) && cp.ticket == tk) { found = true; break; }

         Check("26c a target hit is booked as a target",
               found && cp.IsClosed() && cp.reason == SSR_CLOSE_TP,
               "a bar from an hour earlier must not turn a win into a loss");
         Check("26c and is not labelled assumed",
               found && !cp.ambiguous && ex.AmbiguousCount() == 0,
               StringFormat("%d marked assumed", (int)ex.AmbiguousCount()));
      }

      //--- 26d. EVERY OBSERVER THE HOST REGISTERS GETS A SLOT.
      {
         CSSRReplayController oc;
         CSSRTickObserver     obs[SSR_MAX_OBSERVERS];
         int taken = 0;
         for(int i = 0; i < SSR_MAX_OBSERVERS; i++)
            if(oc.AddObserver(GetPointer(obs[i])))
               taken++;
         Check("26d the controller holds every observer it advertises",
               taken == SSR_MAX_OBSERVERS && oc.ObserverCount() == SSR_MAX_OBSERVERS,
               StringFormat("%d of %d accepted", taken, SSR_MAX_OBSERVERS));
         Check("26d and the host's nine fit inside that",
               SSR_MAX_OBSERVERS >= 9,
               StringFormat("host registers 9 with an evaluation running, "
                            "%d slots exist", SSR_MAX_OBSERVERS));
         CSSRTickObserver  over;
         bool refused = !oc.AddObserver(GetPointer(over));
         Check("26d one too many is refused, with a reason",
               refused && oc.LastErrorText() != "",
               oc.LastErrorText());
      }

      //--- 26e. THE DISCIPLINE MEASURES ARE COMPUTED, not defaulted.
      {
         CSSRTradingEngine ex;
         ex.SetBalance(10000.0);
         ex.OnSessionStart(origin, dg, pt, 0);

         CSSRStatsEngine dst;
         dst.Attach(GetPointer(ex));

         MqlTick t[1];
         t[0].bid = base; t[0].ask = base + spread; t[0].time_msc = 1000;
         ex.OnTicks(t, 1);

         //--- one loser, then a second trade opened seconds later at a
         //--- deliberately different size and stop distance
         double sl_a = NormalizeDouble(base - 100.0 * pt, dg);
         long a = ex.Open(SSR_ORDER_BUY, 0.10, sl_a, 0.0);

         double px_b = NormalizeDouble(base - 110.0 * pt, dg);
         t[0].bid = px_b; t[0].ask = px_b + spread; t[0].time_msc = 61000;
         ex.OnTicks(t, 1);

         double sl_b = NormalizeDouble(px_b - 300.0 * pt, dg);
         long b = ex.Open(SSR_ORDER_BUY, 0.50, sl_b, 0.0);

         double px_c = NormalizeDouble(sl_b - 10.0 * pt, dg);
         t[0].bid = px_c; t[0].ask = px_c + spread; t[0].time_msc = 121000;
         ex.OnTicks(t, 1);

         if(a == 0 || b == 0)
            No("26e both trades opened", ex.LastError());

         SSRStatistics ds;
         ds.Init();                      // ComputeFor does this too; saying it
         dst.ComputeFor("", ds);         // here is what stops the warning

         Check("26e holding time is measured",
               ds.trades == 2 && ds.avg_hold_sec > 0.0,
               StringFormat("%d trades, average %.1fs", ds.trades, ds.avg_hold_sec));
         Check("26e going straight back in after a loss is counted",
               ds.revenge_trades >= 1,
               StringFormat("%d of %d trades", ds.revenge_trades, ds.trades));
         Check("26e uneven risk is visible",
               ds.risk_samples == 2 && ds.risk_spread_pct > 0.0,
               StringFormat("%.0f%% spread over %d trades",
                            ds.risk_spread_pct, ds.risk_samples));
      }
   }

   //+------------------------------------------------------------------+
   //| 27. THE SPREAD COMES FROM THE BAR.                               |
   //|                                                                  |
   //| One number for a whole session is the assumption that costs a    |
   //| trader most, because the spread is never wider than at the       |
   //| moments people most want to practise. Every M1 bar carries the   |
   //| spread the broker recorded for that minute, so the widening is   |
   //| already in the data and no model has to invent it.               |
   //|                                                                  |
   //| Driven through the synthesiser directly, with bars built here,   |
   //| so the check does not depend on whether THIS terminal's history  |
   //| happens to carry a spread - which is a real possibility and is   |
   //| exactly what the last check below is about.                      |
   //+------------------------------------------------------------------+
   {
      int    dg = (int)SymbolInfoInteger(origin, SYMBOL_DIGITS);
      double pt = SymbolInfoDouble(origin, SYMBOL_POINT);
      if(pt <= 0.0) pt = 0.00001;
      double base = SymbolInfoDouble(origin, SYMBOL_BID);
      if(base <= 0.0) base = 10000.0 * pt;
      base = NormalizeDouble(base, dg);

      CSSRTickSynthesizer sy;
      sy.Configure(dg, pt);
      sy.SetSpreadPoints(20);            // the fallback constant
      sy.SetTicksPerBar(8);

      //--- a quiet minute and a release minute, told apart by nothing
      //--- but the number the broker wrote on them
      MqlRates quiet, wide, none;
      quiet.time = (datetime)60;  quiet.open = base;
      quiet.high = NormalizeDouble(base + 50.0 * pt, dg);
      quiet.low  = NormalizeDouble(base - 50.0 * pt, dg);
      quiet.close = base; quiet.tick_volume = 10; quiet.real_volume = 0;
      quiet.spread = 8;

      wide = quiet; wide.time = (datetime)120; wide.spread = 240;
      none = quiet; none.time = (datetime)180; none.spread = 0;

      MqlTick tk[];
      ArrayResize(tk, 64);

      sy.SetSpreadMode(SSR_SPREAD_RECORDED);
      int nq = sy.Synthesize(quiet, tk, 0);
      double sq = (nq > 0 ? (tk[0].ask - tk[0].bid) / pt : -1.0);

      int nw = sy.Synthesize(wide, tk, 0);
      double sw = (nw > 0 ? (tk[0].ask - tk[0].bid) / pt : -1.0);

      int nn = sy.Synthesize(none, tk, 0);
      double sn = (nn > 0 ? (tk[0].ask - tk[0].bid) / pt : -1.0);

      Check("27 a quiet bar is replayed at the spread it recorded",
            MathAbs(sq - 8.0) < 0.5,
            StringFormat("%.1f pt on a bar that recorded 8", sq));
      Check("27 and a release minute is replayed WIDE",
            MathAbs(sw - 240.0) < 0.5 && sw > sq * 5.0,
            StringFormat("%.1f pt on a bar that recorded 240 - one number for "
                         "the whole session would have said %.1f here", sw, sq));
      Check("27 a bar with no recorded spread falls back, it does not go free",
            MathAbs(sn - 20.0) < 0.5,
            StringFormat("%.1f pt, the configured fallback is 20 - a bar with "
                         "spread 0 is a bar with no data, not a free entry", sn));

      Check("27 and the session can say which of the two it used",
            sy.BarsWithRecordedSpread() == 2 && sy.BarsWithFixedSpread() == 1,
            StringFormat("%d recorded, %d fixed - a feature that quietly did "
                         "nothing on this history must be able to say so",
                         (int)sy.BarsWithRecordedSpread(),
                         (int)sy.BarsWithFixedSpread()));
      Check("27 and how wide it got",
            MathAbs(sy.WidestRecordedSpread() - 240.0) < 0.5,
            StringFormat("widest %.1f, average %.1f",
                         sy.WidestRecordedSpread(), sy.AverageRecordedSpread()));

      //--- FIXED must still mean fixed, or the mode is decoration
      sy.ResetSpreadCounters();
      sy.SetSpreadMode(SSR_SPREAD_FIXED);
      int nf = sy.Synthesize(wide, tk, 0);
      double sf = (nf > 0 ? (tk[0].ask - tk[0].bid) / pt : -1.0);
      Check("27 asking for a fixed spread still gets one",
            MathAbs(sf - 20.0) < 0.5 && sy.BarsWithRecordedSpread() == 0,
            StringFormat("%.1f pt on the same 240-point bar", sf));

      //--- and the trade carries what it paid
      {
         CSSRTradingEngine ex;
         ex.SetBalance(10000.0);
         ex.OnSessionStart(origin, dg, pt, 0);

         MqlTick t[1];
         t[0].bid = base; t[0].ask = NormalizeDouble(base + 45.0 * pt, dg);
         t[0].time_msc = 1000;
         ex.OnTicks(t, 1);

         long tk2 = ex.Open(SSR_ORDER_BUY, 0.10,
                            NormalizeDouble(base - 500.0 * pt, dg), 0.0);
         SSRVirtualPosition sp;
         bool found = false;
         for(int i = 0; i < ex.Total(); i++)
            if(ex.At(i, sp) && sp.ticket == tk2) { found = true; break; }

         Check("27 a trade records the spread it was entered at",
               found && MathAbs(sp.spread_at_entry - 45.0) < 1.0,
               StringFormat("%.1f pt recorded on the position, market was 45",
                            found ? sp.spread_at_entry : -1.0));
      }
   }

   //+------------------------------------------------------------------+
   //| 28. RESET ASKS BEFORE IT DESTROYS A SESSION.                     |
   //|                                                                  |
   //| One press of a button beside Play, or one R typed by somebody     |
   //| who thought a text box had the keyboard, and every trade, every   |
   //| screenshot and the whole equity curve were gone with nothing      |
   //| asked and no way back.                                            |
   //|                                                                  |
   //| The checks that matter are not "the label changed". They are     |
   //| that the FIRST press does not reset, that something else in      |
   //| between cancels the arming, and that an empty session is not     |
   //| made to answer a question about nothing.                          |
   //+------------------------------------------------------------------+
   {
      long cchart = ChartOpen(rsym, PERIOD_M1);
      if(Check("28 a chart for the confirm test", cchart != 0, rsym))
        {
         CSSRTradingEngine cacct;
         cacct.SetBalance(10000.0);
         cacct.OnSessionStart(rsym, (int)SymbolInfoInteger(rsym, SYMBOL_DIGITS),
                              SymbolInfoDouble(rsym, SYMBOL_POINT), 0);

         //+------------------------------------------------------------------+
         //| THE GROUP IS NOT OPTIONAL HERE, and the first version of this    |
         //| stage left it out. ReadState returns false the moment there is  |
         //| no primary controller, so the panel saw a zeroed state, counted |
         //| no trades, and correctly decided there was nothing to confirm.  |
         //| Four checks failed against a feature that was working.          |
         //+------------------------------------------------------------------+
         CSSRReplayGroup cgroup;
         cgroup.Add(GetPointer(ctrl));

         CSSRGroupPort cport;
         cport.Attach(GetPointer(cgroup));
         cport.AttachAccount(GetPointer(cacct));

         CSSRPanel cp;
         cp.Create(cchart, GetPointer(cport), "SSRC_");

         //--- NOTHING TRADED YET: the question would be about nothing
         cp.Render();
         cp.Dispatch("reset");
         Check("28 an empty session is not asked to confirm",
               !cp.ResetIsArmed(),
               "a confirmation over nothing teaches people to press twice "
               "without reading, which is the same as having none");

         //--- now give it something to lose
         MqlTick t[1];
         double cpt = SymbolInfoDouble(rsym, SYMBOL_POINT);
         if(cpt <= 0.0) cpt = 0.00001;
         double cbase = SymbolInfoDouble(rsym, SYMBOL_BID);
         if(cbase <= 0.0) cbase = 10000.0 * cpt;
         t[0].bid = cbase; t[0].ask = cbase + 10.0 * cpt; t[0].time_msc = 1000;
         cacct.OnTicks(t, 1);
         long ct = cacct.Open(SSR_ORDER_BUY, 0.10, 0.0, 0.0);
         cacct.Close(ct);
         cacct.Open(SSR_ORDER_BUY, 0.10, 0.0, 0.0);   // and one left open

         //+------------------------------------------------------------------+
         //| THE TEST CHECKS ITS OWN EYES FIRST.                              |
         //|                                                                  |
         //| Everything below depends on the panel being able to SEE the two  |
         //| trades. When it could not - a group that was never attached -    |
         //| four checks failed and blamed a feature that was working. A      |
         //| precondition that is not asserted is a precondition that will    |
         //| one day be reported as a defect somewhere else.                  |
         //+------------------------------------------------------------------+
         cp.Render();
         SSRUiState cs;
         cp.StateInto(cs);
         if(!Check("28 the panel can see the trades it is about to protect",
                   cs.closed_trades == 1 && cs.open_positions == 1,
                   StringFormat("panel sees %d closed, %d open - the account "
                                "holds 1 and 1", cs.closed_trades,
                                cs.open_positions)))
            Log("  -> everything below this line is measuring the wiring, "
                  "not the confirmation");

         cp.Dispatch("reset");
         Check("28 the first press does NOT reset, it asks",
               cp.ResetIsArmed(),
               "this is the whole feature - a label that changes while the "
               "reset still happens is worse than no confirmation");
         Check("28 and it says what would be lost, not just 'are you sure'",
               StringFind(cp.ResetWarningText(), "1 closed") >= 0 &&
               StringFind(cp.ResetWarningText(), "1 open") >= 0,
               "[" + cp.ResetWarningText() + "] - asked to guess, people "
               "guess low");

         cp.Render();
         Check("28 and the button on the chart shows the question",
               ObjectGetString(cchart, "SSRC_reset", OBJPROP_TEXT) == "Reset?",
               "[" + ObjectGetString(cchart, "SSRC_reset", OBJPROP_TEXT) + "]");

         //--- SOMETHING ELSE CANCELS IT
         cp.Dispatch("step");
         Check("28 doing anything else disarms it",
               !cp.ResetIsArmed(),
               "an arming that survives the user changing their mind is a "
               "landmine: the NEXT press meant to arm it would destroy the "
               "session instead");

         cp.Render();
         Check("28 and the button goes back to saying Reset",
               ObjectGetString(cchart, "SSRC_reset", OBJPROP_TEXT) == "Reset",
               "[" + ObjectGetString(cchart, "SSRC_reset", OBJPROP_TEXT) + "]");

         //--- and the second press goes through
         cp.Dispatch("reset");
         bool armed_again = cp.ResetIsArmed();
         cp.Dispatch("reset");
         Check("28 a second press within the window carries it out",
               armed_again && !cp.ResetIsArmed(),
               "armed on the first press, consumed by the second");

         cp.Destroy();
         ChartClose(cchart);
        }
   }

   //+------------------------------------------------------------------+
   //| 29. THE KEYS, AND THE LIST THE USER IS SHOWN OF THEM.            |
   //|                                                                  |
   //| The guide is generated from the same table the keyboard reads,   |
   //| so the checks here are the ones a generated list can still fail: |
   //| that the table and the lookup agree, that no two keys shadow one |
   //| another, and that nothing on the card is cut off by MetaTrader.  |
   //|                                                                  |
   //| A guide that names a key which does nothing is worse than no     |
   //| guide, because it is believed.                                   |
   //+------------------------------------------------------------------+
   {
      SSRKeyBinding kb[];
      int kn = SSRKeyBindings(kb);
      Check("29 there are bindings at all", kn > 0,
            StringFormat("%d declared", kn));

      //--- the lookup and the table cannot disagree
      int wrong = 0;
      for(int i = 0; i < kn; i++)
         if(SSRKeyToCommand(kb[i].vk) != kb[i].cmd)
            wrong++;
      Check("29 every declared key resolves to the command beside it",
            wrong == 0,
            StringFormat("%d of %d disagree with the lookup", wrong, kn));

      //--- A KEY DECLARED TWICE IS A KEY THAT SILENTLY LOSES. The first
      //--- row wins the lookup and the second is dead, while the card
      //--- keeps advertising it.
      int dupes = 0;
      for(int i = 0; i < kn; i++)
         for(int j = i + 1; j < kn; j++)
            if(kb[i].vk == kb[j].vk)
               dupes++;
      Check("29 no key is declared twice", dupes == 0,
            StringFormat("%d collision(s) - the second one would never run",
                         dupes));

      //--- nothing on the card is cut off. MetaTrader stops an object's
      //--- text at 63 characters, and a line that ends mid-word reads as
      //--- a broken tool.
      int toolong = 0;
      string worst = "";
      for(int i = 0; i < kn; i++)
        {
         if(StringLen(kb[i].what) > 63 || StringLen(kb[i].label) > 63)
           { toolong++; worst = kb[i].what; }
        }
      Check("29 no line on the card is cut off by MetaTrader",
            toolong == 0,
            StringFormat("%d over 63 characters [%s]", toolong, worst));

      //--- THE KEYS THE USER ASKED FOR
      Check("29 R puts the stop and target lines on the chart",
            SSRKeyToCommand(SSR_VK_R) == SSR_CMD_LINES_TOGGLE,
            "the hand that is trading owns R");
      Check("29 Tab takes the trade the lines describe",
            SSRKeyToCommand(SSR_VK_TAB) == SSR_CMD_OPEN_LINES,
            "one key, from lines drawn to position open");
      Check("29 reset is still reachable, and off every letter",
            SSRKeyToCommand(SSR_VK_0) == SSR_CMD_RESET &&
            SSRKeyToCommand(SSR_VK_R) != SSR_CMD_RESET,
            "a finger reaching for the lines must not destroy the session");
      Check("29 and H opens the list",
            SSRKeyToCommand(SSR_VK_H) == SSR_CMD_KEYS, "");

      //--- the card itself
      long kchart = ChartOpen(rsym, PERIOD_M1);
      if(Check("29 a chart for the key card", kchart != 0, rsym))
        {
         CSSRKeyCard kc;
         Check("29 the card goes up", kc.Toggle(kchart) && kc.IsUp(),
               "generated from the bindings, not typed out beside them");

         int listed = 0;
         for(int i = 0; i < kn; i++)
            if(kb[i].listed)
               listed++;
         int drawn = 0;
         int total = ObjectsTotal(kchart, -1, -1);
         for(int i = 0; i < total; i++)
            if(StringFind(ObjectName(kchart, i, -1, -1), "SSRK_k") == 0)
               drawn++;
         Check("29 and carries a row for every listed binding",
               drawn == listed * 2,
               StringFormat("%d objects for %d rows - each row is a key and "
                            "a description", drawn, listed));

         Check("29 pressing it again takes it away",
               !kc.Toggle(kchart) && !kc.IsUp(),
               "a card you cannot close is a card in the way");

         kc.Destroy();
         ChartClose(kchart);
        }
   }

   //+------------------------------------------------------------------+
   //| 30. THE REPORT CAN BE READ WHILE IT IS BEING WRITTEN.            |
   //|                                                                  |
   //| Twice now: "it hung and no file was made". The suite had run.     |
   //| FileOpen with no share mode takes the file exclusively, so the    |
   //| ordinary way to use this tool - open qa-result.txt, copy it,      |
   //| leave the editor open - is what stops the next run from writing   |
   //| at all. Nothing appeared in the folder, and from outside a slow    |
   //| run and a dead one look the same.                                 |
   //|                                                                  |
   //| So it is asserted, not assumed: the file this run is holding      |
   //| open right now is opened a SECOND time, for reading, and read.    |
   //| That is the user's editor, in one check.                          |
   //+------------------------------------------------------------------+
   {
      int rh = FileOpen(g_path, FILE_READ | FILE_TXT | FILE_ANSI |
                                FILE_SHARE_READ | FILE_SHARE_WRITE);
      if(Check("30 the report can be opened while the run still holds it",
               rh != INVALID_HANDLE,
               (rh != INVALID_HANDLE
                ? "a second handle got in - an editor left open on this file "
                  "can no longer stop the next run from writing"
                : StringFormat("err %d on %s - this is the bug that made a "
                               "finished run look like a hang", GetLastError(),
                               g_path))))
        {
         string peek = FileReadString(rh);
         Check("30 and what it reads is this run",
               StringFind(peek, "SS Replay smoke test") >= 0,
               StringFormat("first line reads [%s]",
                            StringSubstr(peek, 0, 46)));
         FileClose(rh);
        }
   }

   //+------------------------------------------------------------------+
   //| 31. THE SAME SYMBOL REPLAYS TWICE IN A ROW.                      |
   //|                                                                  |
   //| The thing this suite has never done is run twice. The user has,   |
   //| every time, and the pattern in their reports is that a symbol     |
   //| works ONCE: the first run passes and the next one advances its    |
   //| clock, emits its ticks and gains no candle - while a jump, which  |
   //| writes rates rather than ticks, lands its bars in that same run.  |
   //|                                                                  |
   //| Create() destroys the old replay symbol and asks for the SAME     |
   //| NAME back microseconds later, on top of a bases\Custom teardown   |
   //| that has not finished. The manager now waits after the delete.    |
   //|                                                                  |
   //| This is the check that makes it fail HERE when it is wrong,       |
   //| rather than on a terminal I cannot reach: tear the session down   |
   //| and load the same slot again, then ask the same question the      |
   //| first pass asked - do candles appear.                             |
   //+------------------------------------------------------------------+
   {
      Step("31 tearing the session down to replay it again");
      ctrl.Release();

      bool again = ctrl.Load(origin, win_start, win_end);
      if(Check("31 the same symbol loads a second time", again,
               ctrl.LastErrorText()))
        {
         int  bars_before = Bars(rsym, PERIOD_M1);
         ctrl.Play();
         ctrl.SetSpeedX100(6000);
         for(int i = 0; i < 40 && !IsStopped(); i++)
            ctrl.Pump(1000);

         int  bars_after = bars_before;
         int  waited     = 0;
         for(int w = 0; w < 20 && bars_after <= bars_before; w++)
           {
            MqlRates poke[];
            CopyRates(rsym, PERIOD_M1, 0, 1, poke);
            bars_after = Bars(rsym, PERIOD_M1);
            if(bars_after > bars_before)
               break;
            Sleep(50);
            waited += 50;
           }

         Check("31 and its candles still build from its own ticks",
               bars_after > bars_before,
               StringFormat("%d -> %d bars on the second run%s%s",
                            bars_before, bars_after,
                            (waited > 0
                             ? StringFormat(" (took %d ms)", waited) : ""),
                            (bars_after > bars_before
                             ? " - a symbol that only works once is a symbol "
                               "nobody can use twice"
                             : TickVerdict(sink))));
        }
   }

   //+------------------------------------------------------------------+
   //| 32. THE DESIGN SYSTEM DRAWS WHAT IT SAYS IT DRAWS.               |
   //|                                                                  |
   //| Phase 2 added four primitives and a layout helper for phases that |
   //| have not been built yet. Library code that nothing calls and no   |
   //| test measures is the "polished placeholder" this redesign is      |
   //| under orders not to produce, so it is exercised here on a real    |
   //| chart the moment it exists.                                       |
   //+------------------------------------------------------------------+
   {
      //--- the layout helper first: it is pure arithmetic, so it can be
      //--- checked exactly rather than approximately
      SSRFrame ltr; ltr.Init(100, 50, 420, 8, false);
      SSRFrame rtl; rtl.Init(100, 50, 420, 8, true);

      Check("32 leading starts where reading starts",
            SSRLead(ltr, 0, 60) == 108 && SSRLead(rtl, 0, 60) == 452,
            StringFormat("ltr %d, rtl %d - one frame, two reading orders",
                         SSRLead(ltr, 0, 60), SSRLead(rtl, 0, 60)));

      Check("32 and trailing is the far edge in both",
            SSRTrail(ltr, 0, 60) == 452 && SSRTrail(rtl, 0, 60) == 108,
            "a value column stays on the side the eye ends on");

      Check("32 mirroring is symmetric, not approximate",
            SSRLead(ltr, 37, 84) == SSRTrail(rtl, 37, 84) &&
            SSRTrail(ltr, 37, 84) == SSRLead(rtl, 37, 84),
            "lead and trail swap exactly - if they did not, an RTL panel "
            "would drift by a pixel per control");

      SSRRows rows; rows.Init(200, 24);
      int r0 = rows.Next(); int r1 = rows.Next(); rows.Skip(6); int r2 = rows.Next();
      Check("32 rows advance once per row, and say how tall they got",
            r0 == 200 && r1 == 224 && r2 == 254 && rows.HeightFrom(200) == 78,
            StringFormat("%d, %d, %d, total %d - the height is ADDED UP, "
                         "which is the whole reason v69's two new rows went "
                         "past a frame that was a typed number",
                         r0, r1, r2, rows.HeightFrom(200)));

      Check("32 columns divide a frame without drifting",
            SSRColW(ltr, 3) == 131 &&
            SSRColX(ltr, 0, 3) == 108 && SSRColX(ltr, 2, 3) == 380,
            StringFormat("3 x %d starting at %d and %d",
                         SSRColW(ltr, 3), SSRColX(ltr, 0, 3),
                         SSRColX(ltr, 2, 3)));

      //--- now the primitives, on a real chart
      long dchart = ChartOpen(rsym, PERIOD_M1);
      if(Check("32 a chart for the primitives", dchart != 0, rsym))
        {
         CSSRWidgets w;
         w.Attach(dchart, "SSRW_");
         w.RemoveAll();

         int cw = w.Chip("c1", 20, 20, "BLIND", SSR_C_HOLD, SSR_C_WELL);
         Check("32 a chip reports the width it took",
               cw > 0 && ObjectFind(dchart, "SSRW_c1") >= 0,
               StringFormat("%d px for BLIND - a row of chips needs this to "
                            "lay the next one out", cw));

         //--- a meter is not a progress bar: it can pass its limit
         w.Meter("m1", 20, 40, 200, 10, 3.0, 10.0, SSR_C_RUN);
         bool under = (ObjectFind(dchart, "SSRW_m1_fill") >= 0);
         w.Meter("m1", 20, 40, 200, 10, 12.0, 10.0, SSR_C_RUN);
         color over_c = (color)ObjectGetInteger(dchart, "SSRW_m1_fill",
                                                OBJPROP_BGCOLOR);
         Check("32 a meter over its limit turns to the stop colour",
               under && over_c == SSR_C_STOP,
               "a prop rule that looked the same breached as it did at 30% "
               "would be a rule nobody could manage");
         Check("32 and the limit mark is drawn even when nothing reaches it",
               ObjectFind(dchart, "SSRW_m1_lim") >= 0,
               "the distance to the limit is the number being managed");

         string opts[] = {"Buy", "Sell", "Close all", "Bookmark", "Jump"};
         w.List("l1", 20, 60, 120, 18, opts, 0, 3, 1);
         bool three = (ObjectFind(dchart, "SSRW_l10") >= 0 &&
                       ObjectFind(dchart, "SSRW_l12") >= 0 &&
                       ObjectFind(dchart, "SSRW_l13") < 0);
         Check("32 a list draws a window onto its rows, not all of them",
               three,
               "5 rows, 3 shown - MQL5 has no clipping, so a list that drew "
               "everything would draw it over the chart");

         string sel = ObjectGetString(dchart, "SSRW_l11", OBJPROP_TEXT);
         Check("32 and the selected row is the selected row",
               sel == "Sell",
               StringFormat("row 1 reads [%s]", sel));

         w.ListClear("l1", 3);
         Check("32 clearing a list takes its tail with it",
               ObjectFind(dchart, "SSRW_l10") < 0 &&
               ObjectFind(dchart, "SSRW_l1_bg") < 0,
               "a shorter list would otherwise leave its old rows behind");

         w.Toast("t1", 20, 140, 220, "Position opened", SSR_C_RUN);
         Check("32 a toast does not touch the status strip",
               ObjectFind(dchart, "SSRW_t1") >= 0 &&
               ObjectFind(dchart, "SSRW_t1_ac") >= 0,
               "standing state and something that just happened are two "
               "different messages and must not evict each other");
         w.ToastClear("t1");

         w.RemoveAll();
         ChartClose(dchart);
        }
   }

   //+------------------------------------------------------------------+
   //| 33. THE COMMAND PALETTE.                                         |
   //|                                                                  |
   //| A search box that cannot be typed into by a test is still worth  |
   //| testing: the query is a plain string the palette re-filters on,  |
   //| so everything except the typing itself can be driven directly.   |
   //|                                                                  |
   //| The one thing measured here that no screenshot could show: that  |
   //| the palette invents no verbs. Every entry resolves to a command  |
   //| the key table already knows or an action the panel already       |
   //| dispatches, and this asserts that for all of them at once.       |
   //+------------------------------------------------------------------+
   {
      SSRCommand cmds[];
      int cn = SSRCommands(cmds);
      Check("33 there are commands at all", cn > 0,
            StringFormat("%d declared", cn));

      //--- EVERY entry must resolve to an existing path. A command with
      //--- neither is a verb invented in a search box.
      int orphan = 0;
      string orphan_name = "";
      for(int i = 0; i < cn; i++)
         if(cmds[i].cmd == SSR_CMD_NONE && cmds[i].action == "")
           { orphan++; if(orphan_name == "") orphan_name = cmds[i].label; }
      Check("33 every command resolves to a path that already existed",
            orphan == 0,
            (orphan == 0
             ? "no command invents a verb - each is a key the table knows or "
               "a button the panel dispatches"
             : StringFormat("%d with neither, first is [%s]",
                            orphan, orphan_name)));

      //--- and no label appears twice, or the second is unreachable
      int dupes = 0;
      for(int i = 0; i < cn; i++)
         for(int j = i + 1; j < cn; j++)
            if(cmds[i].label == cmds[j].label)
               dupes++;
      Check("33 no command is declared twice", dupes == 0,
            StringFormat("%d duplicate label(s)", dupes));

      //--- the key column comes from the key table, so it cannot lie
      string k = "";
      for(int i = 0; i < cn && k == ""; i++)
         if(cmds[i].cmd == SSR_CMD_TOGGLE)
            k = SSRCommandKey(cmds[i]);
      Check("33 a command with a shortcut shows the real one",
            k == "Space",
            StringFormat("play/pause reads [%s] - taken from the key table, "
                         "so a rebinding cannot leave the palette lying", k));

      //--- subsequence matching, which is what makes it usable at speed
      int hit[];
      Check("33 an empty query shows everything",
            SSRCommandFilter(cmds, "", hit) == cn,
            "opening it is how you find out what there IS");
      Check("33 letters in order are enough",
            SSRCommandFilter(cmds, "cep", hit) > 0 &&
            SSRCommandMatches("Close every position", "cep"),
            "[cep] finds [Close every position] - a trader mid-session "
            "types from memory, not from the exact wording");
      Check("33 and letters out of order are not",
            !SSRCommandMatches("Close every position", "pec"),
            "subsequence, not 'contains all these letters somewhere'");
      Check("33 a query that matches nothing says so",
            SSRCommandFilter(cmds, "zzqx", hit) == 0,
            "and the palette shows a line telling you to try fewer letters");

      //--- now on a real chart
      long pchart2 = ChartOpen(rsym, PERIOD_M1);
      if(Check("33 a chart for the palette", pchart2 != 0, rsym))
        {
         CSSRPalette pal;
         Check("33 it is not up until it is opened", !pal.IsUp(), "");
         pal.Show(pchart2);
         Check("33 it goes up", pal.IsUp() && pal.Matches() == cn,
               StringFormat("%d commands offered on open", pal.Matches()));
         Check("33 and something is selected from the start",
               pal.SelectedLabel() != "",
               StringFormat("[%s] - Enter always has a target",
                            pal.SelectedLabel()));

         string was = pal.SelectedLabel();
         pal.Move(+1);
         Check("33 the selection moves", pal.SelectedLabel() != was,
               StringFormat("[%s] -> [%s]", was, pal.SelectedLabel()));
         pal.Move(-99);
         Check("33 and cannot be moved off the top",
               pal.SelectedLabel() != "",
               "a selection off the end is an Enter that does nothing");

         bool run = false;
         pal.OnKey(SSR_VK_ESCAPE, run);
         Check("33 Escape closes it", !pal.IsUp() && !run,
               "a modal you cannot leave is a modal you open once");
         ChartClose(pchart2);
        }
   }

   //+------------------------------------------------------------------+
   //| 35. EXECUTION TRANSPARENCY REACHES THE ROW.                      |
   //|                                                                  |
   //| Two facts the engine has always recorded and never showed while  |
   //| they could still be acted on: whether a position has a stop, and |
   //| the spread it was entered at.                                     |
   //|                                                                  |
   //| Driven through the port, because a field the ENGINE fills and    |
   //| the PANEL reads is only proved by the thing in between.           |
   //+------------------------------------------------------------------+
   {
      CSSRTradingEngine ex2;
      ex2.SetBalance(10000.0);
      int    dg2 = (int)SymbolInfoInteger(origin, SYMBOL_DIGITS);
      double pt2 = SymbolInfoDouble(origin, SYMBOL_POINT);
      if(pt2 <= 0.0) pt2 = 0.00001;
      ex2.OnSessionStart(origin, dg2, pt2, 0);

      double b2 = SymbolInfoDouble(origin, SYMBOL_BID);
      if(b2 <= 0.0) b2 = 10000.0 * pt2;
      b2 = NormalizeDouble(b2, dg2);

      MqlTick t2[1];
      t2[0].bid = b2; t2[0].ask = b2 + 30.0 * pt2; t2[0].time_msc = 1000;
      ex2.OnTicks(t2, 1);

      //--- one WITH a stop, one without
      double sl2 = NormalizeDouble(b2 - 200.0 * pt2, dg2);
      long   with_stop = ex2.Open(SSR_ORDER_BUY, 0.10, sl2, 0.0);
      long   no_stop   = ex2.Open(SSR_ORDER_BUY, 0.10, 0.0, 0.0);
      Check("35 two positions to inspect", with_stop > 0 && no_stop > 0,
            ex2.LastError());

      //--- built the way the rest of this suite builds one: the port
      //--- takes what it needs, one Attach at a time. There is no Init
      //--- taking five pointers - I wrote one from memory and the
      //--- compiler said so, which is the third time this session a
      //--- signature guessed from a fragment has cost a build.
      CSSRGroupPort port2;
      port2.AttachAccount(GetPointer(ex2));

      SSRUiState st2;
      st2.Init();
      if(Check("35 the panel can read them", port2.ReadState(st2) &&
               st2.pos_rows >= 2,
               StringFormat("%d row(s)", st2.pos_rows)))
        {
         int i_with = -1, i_without = -1;
         for(int i = 0; i < st2.pos_rows; i++)
           {
            if(st2.pos_ticket[i] == with_stop) i_with    = i;
            if(st2.pos_ticket[i] == no_stop)   i_without = i;
           }
         Check("35 a trade WITHOUT a stop is flagged on its own row",
               i_without >= 0 && st2.pos_no_stop[i_without],
               "the statistics have counted these since Phase 9 and reported "
               "them after the session - the one moment nothing can be done");
         Check("35 and one WITH a stop is not",
               i_with >= 0 && !st2.pos_no_stop[i_with],
               "a warning that is always on is a warning nobody reads");
         Check("35 the spread it was entered at reaches the row",
               i_with >= 0 && st2.pos_spread[i_with] > 0.0,
               StringFormat("%.1f pt recorded on the row, market was 30 - the "
                            "number that says whether the fill was realistic, "
                            "and it has never been visible outside the "
                            "exported statement", st2.pos_spread[i_with]));
        }
      ex2.CloseAll();
   }

   //+------------------------------------------------------------------+
   //| 36. A BLIND SESSION ENDS WITH A REVEAL, NOT A DEINIT.            |
   //|                                                                  |
   //| Blind mode has restored the chart when the EXPERT WAS REMOVED     |
   //| since Phase 8, so a trader who wanted to know what they had been  |
   //| reading had to end the session to find out - losing the chart,    |
   //| the positions and their own reasoning on the way.                 |
   //|                                                                  |
   //| The card marks the moment. What is asserted here is that it       |
   //| decides WHEN, never WHETHER: the chart still comes back exactly   |
   //| as it was, which is the promise the whole mode rests on.          |
   //+------------------------------------------------------------------+
   {
      long bchart = ChartOpen(rsym, PERIOD_M1);
      if(Check("36 a chart for the reveal", bchart != 0, rsym))
        {
         bool had_ohlc = (bool)ChartGetInteger(bchart, CHART_SHOW_OHLC);

         //--- FULL, not Standard: Standard deliberately leaves the price
         //--- scale alone, because "a chart with no price axis is not
         //--- practice, it is a guessing game". Asserting that OHLC is
         //--- hidden therefore has to use the level that hides it - my
         //--- first version of this check asserted Standard would, which
         //--- would have failed the moment it ran.
         SSRBlindPolicy pol;
         pol.Apply(SSR_BLIND_FULL);
         CSSRBlindMode bl;
         bl.SetPolicy(pol);
         bl.Apply(bchart);
         Check("36 blind hides what the chart announces",
               bl.IsApplied() &&
               (bool)ChartGetInteger(bchart, CHART_SHOW_OHLC) == false,
               "the instrument and the dates are what a blind session is "
               "practising without");

         CSSRRevealCard card;
         Check("36 the card is not up until the session finishes",
               !card.IsUp(), "");

         card.Show(bchart, "4 trade(s), net +18.20");
         Check("36 it goes up when it does",
               card.IsUp() && ObjectFind(bchart, "SSRV_reveal") >= 0,
               "with the one button that lifts the blind");
         Check("36 and it carries a BLIND chip, not just a colour",
               ObjectFind(bchart, "SSRV_chip") >= 0,
               "a mode carried by colour alone is one a colour-blind trader "
               "cannot read");

         //--- THE POINT: while the card is up, the market is STILL hidden
         Check("36 the market stays hidden while the card is up",
               (bool)ChartGetInteger(bchart, CHART_SHOW_OHLC) == false,
               "a reveal that had already happened would make the button a "
               "decoration");

         //--- the card asks; the caller answers. It never reveals itself.
         card.Hide();
         Check("36 the card never reveals on its own",
               !card.IsUp() &&
               (bool)ChartGetInteger(bchart, CHART_SHOW_OHLC) == false,
               "dismissing the question is not answering it - the host owns "
               "the blind, and one place decides what revealing means");

         int back = bl.RestoreAll();
         Check("36 and the reveal puts the chart back exactly as it was",
               back > 0 && !bl.IsApplied() &&
               (bool)ChartGetInteger(bchart, CHART_SHOW_OHLC) == had_ohlc,
               StringFormat("%d chart(s) restored - a mode you cannot leave "
                            "is a trap, not a feature", back));
         ChartClose(bchart);
        }
   }

   //+------------------------------------------------------------------+
   //| 37. THE REVIEW SAYS ONLY WHAT WAS COUNTED.                       |
   //|                                                                  |
   //| The engine measures forty-three things and about ten of them     |
   //| were reachable without exporting a file. The review card puts    |
   //| all of them in front of the trader - which makes the danger the  |
   //| opposite one: a card that has forty-three numbers in it is a     |
   //| card that looks authoritative, and the temptation is to have it  |
   //| say what they MEAN.                                              |
   //|                                                                  |
   //| So the three things asserted here are the three that keep it     |
   //| honest: a sentence needs samples behind it, a session too small  |
   //| to support any sentence gets none, and every row fits inside     |
   //| the 63 characters MetaTrader will actually draw.                 |
   //|                                                                  |
   //| Pure functions on a struct - no engine, no chart, no timing. A   |
   //| test of an opinion should not be able to fail for a reason that  |
   //| has nothing to do with the opinion.                              |
   //+------------------------------------------------------------------+
   {
      Step("37 the review card");

      //--- a session with everything wrong with it that CAN be counted
      SSRStatistics rv;
      rv.Init();
      rv.trades              = 8;
      rv.wins                = 3;
      rv.losses              = 5;
      rv.net_profit          = -212.50;
      rv.win_rate            = 37.5;
      rv.total_r             = -1.85;
      rv.max_drawdown        = 318.40;
      rv.revenge_trades      = 2;
      rv.risk_spread_pct     = 61.0;
      rv.risk_samples        = 8;
      rv.trades_without_stop = 1;
      rv.spread_samples      = 8;
      rv.wide_spread_trades  = 3;
      rv.ambiguous_trades    = 1;
      rv.stopouts            = 1;

      SSRReviewRow rows[];
      int rn = SSRReviewRows(rv, rows);

      //--- FORTY-THREE, not "about forty". A row silently dropped by an
      //--- ArrayResize is exactly the kind of loss nobody notices, and
      //--- the count is the only thing that would show it.
      Check("37 every measure the engine computes reaches the card",
            rn == 43, StringFormat("%d rows", rn));

      //+------------------------------------------------------------------+
      //| THE 63-CHARACTER CUT IS REAL AND IT IS SILENT.                   |
      //|                                                                  |
      //| MetaTrader stores OBJPROP_TEXT and draws the first 63            |
      //| characters. Nothing errors; the number on the end of the line    |
      //| just is not there. A card whose LAST COLUMN is the value is a    |
      //| card where the cut takes the only part that matters.             |
      //+------------------------------------------------------------------+
      //--- measured on the string that REACHES THE OBJECT, marker and
      //--- all - not on the part this file happened to build. Checking
      //--- the unprefixed line is how a row two characters over the cut
      //--- passes its own test and still loses a digit on the chart.
      int over = 0, longest = 0;
      string worst = "";
      for(int i = 0; i < rn; i++)
        {
         string line = SSRReviewLine(rows[i]);
         int    len  = StringLen(line) + SSR_REVIEW_PREFIX;
         if(len > longest) { longest = len; worst = line; }
         if(len > 63) over++;
        }
      Check("37 no row is cut off by MetaTrader",
            over == 0,
            StringFormat("longest %d of 63 drawn: \"%s\"", longest, worst));

      //--- and the value is really the value it was handed. A card that
      //--- recomputed anything would be a second place deciding what a
      //--- session result means, and the statement is the first.
      bool carried = false;
      for(int i = 0; i < rn && !carried; i++)
         if(rows[i].label == "Net profit")
            carried = (rows[i].value == "-212.50");
      Check("37 it reports the engine's number, not one of its own",
            carried, "net profit -212.50 as the statistics gave it");

      //+------------------------------------------------------------------+
      //| A SENTENCE COSTS MORE ATTENTION THAN A ROW, SO IT EARNS ONE.     |
      //+------------------------------------------------------------------+
      string obs[];
      int on = SSRReviewObservations(rv, obs);
      Check("37 a session with something to report gets sentences",
            on >= 4, StringFormat("%d observation(s)", on));

      //--- EVERY line carries a count. This is the whole rule: an
      //--- observation is a measurement written out, and a sentence
      //--- with no number in it is an opinion wearing a measurement's
      //--- clothes.
      int bare = 0;
      string bare_line = "";
      for(int i = 0; i < on; i++)
        {
         bool has_digit = false;
         int  n = StringLen(obs[i]);
         for(int c = 0; c < n && !has_digit; c++)
           {
            ushort ch = StringGetCharacter(obs[i], c);
            has_digit = (ch >= '0' && ch <= '9');
           }
         if(!has_digit) { bare++; if(bare_line == "") bare_line = obs[i]; }
        }
      Check("37 every observation has a count behind it",
            bare == 0,
            (bare == 0 ? "no sentence without a number in it"
                       : "no count: \"" + bare_line + "\""));

      //--- ...and none of them tells the trader what it meant. These are
      //--- the words a coaching tool would reach for; this one does not
      //--- know what happened in that session and must not pretend to.
      string coaching[] = {"should", "avoid", "too many", "poor", "bad",
                           "revenge trading", "discipline problem", "try to"};
      int preached = 0;
      string preach_line = "";
      for(int i = 0; i < on; i++)
        {
         string low = obs[i];
         StringToLower(low);
         for(int w = 0; w < ArraySize(coaching); w++)
            if(StringFind(low, coaching[w]) >= 0)
              {
               preached++;
               if(preach_line == "")
                  preach_line = obs[i];
              }
        }
      Check("37 and none of them interprets it",
            preached == 0,
            (preached == 0 ? "counts, not verdicts"
                           : "coaching: \"" + preach_line + "\""));

      //+------------------------------------------------------------------+
      //| THE SAMPLE GATES, ONE AT A TIME.                                 |
      //|                                                                  |
      //| Same session, two trades. Nothing about the behaviour changed -  |
      //| only how much of it there is to look at - and that alone has to  |
      //| be enough to silence every sentence.                             |
      //+------------------------------------------------------------------+
      SSRStatistics tiny = rv;
      tiny.trades = 2;
      string tobs[];
      int tn = SSRReviewObservations(tiny, tobs);
      Check("37 two trades support no statement about behaviour",
            tn == 0,
            StringFormat("%d observation(s) - \"0 revenge trades\" out of "
                         "two is a sample size, not a clean sheet", tn));

      //--- risk dispersion specifically: wide spread, too few samples
      SSRStatistics few = rv;
      few.revenge_trades      = 0;
      few.trades_without_stop = 0;
      few.wide_spread_trades  = 0;
      few.ambiguous_trades    = 0;
      few.stopouts            = 0;
      few.risk_samples        = 2;        // below the gate
      few.risk_spread_pct     = 61.0;     // and screaming
      string fobs[];
      int fn = SSRReviewObservations(few, fobs);
      Check("37 risk dispersion stays quiet under three samples",
            fn == 0,
            StringFormat("%d observation(s) from 2 samples", fn));

      few.risk_samples = 3;               // the same session, one gate met
      fn = SSRReviewObservations(few, fobs);
      Check("37 and speaks the moment it has them",
            fn == 1 && StringFind(fobs[0], "61") >= 0,
            (fn > 0 ? fobs[0] : "nothing at three samples"));

      //+------------------------------------------------------------------+
      //| PAGING, because MQL5 has no scrollbar and no clipping: a list    |
      //| that ran off the end would paint its surplus over the chart.     |
      //+------------------------------------------------------------------+
      long vchart = ChartOpen(rsym, PERIOD_M1);
      if(Check("37 a chart for the card", vchart != 0, rsym))
        {
         CSSRReviewCard card;
         Check("37 the card is not up until it is asked for",
               !card.IsUp(), "");

         card.Show(vchart, rv);
         Check("37 it goes up with every measure in it",
               card.IsUp() && card.Rows() == 43 && card.First() == 0,
               StringFormat("%d rows, %d observations",
                            card.Rows(), card.Observations()));

         card.Page(-1);
         Check("37 paging up from the top stays at the top",
               card.First() == 0,
               StringFormat("first row %d", card.First()));

         for(int i = 0; i < 12; i++)
            card.Page(+1);
         Check("37 and paging past the end stops at the last full page",
               card.First() == 43 - SSR_RV_SHOWN,
               StringFormat("first row %d of %d, %d shown",
                            card.First(), card.Rows(), SSR_RV_SHOWN));

         //--- the keyboard belongs to a card that is up, including the
         //--- keys it does not use: Space here would start the replay
         //--- running behind the numbers being read.
         Check("37 an open card swallows the keys it does not use",
               card.OnKey(SSR_VK_SPACE) && card.IsUp(),
               "a modal that forwards Space is a modal in name only");
         Check("37 and Escape closes it",
               card.OnKey(SSR_VK_ESCAPE) && !card.IsUp(), "");

         card.Hide();
         Check("37 closing it leaves nothing on the chart",
               ObjectFind(vchart, "SSRR2_bg") < 0 &&
               ObjectFind(vchart, "SSRR2_m0") < 0,
               "a list drawn without clipping has to clean up its own rows");
         ChartClose(vchart);
        }
   }

   //+------------------------------------------------------------------+
   //| 38. THE METER AND THE RULE READ THE SAME NUMBER.                 |
   //|                                                                  |
   //| An evaluation has four rules and the panel drew ONE of them. The |
   //| daily loss limit - the rule that ends most real challenges - was |
   //| a number inside a sentence, "floor 9500.00", which a trader       |
   //| mid-trade has to subtract from their own equity to use.          |
   //|                                                                  |
   //| Four meters fix that, and introduce a worse failure than the one  |
   //| they fix: a bar that is worked out in the panel can read SAFE in  |
   //| the same frame the evaluation reads FAILED, and a trader will     |
   //| believe the bar. So the fractions come from the evaluation - the  |
   //| one place that knows what these rules mean and the same place     |
   //| that decides whether the run is over - and the check below is     |
   //| the one that matters: at the equity where the rule fires, the     |
   //| meter is FULL.                                                    |
   //+------------------------------------------------------------------+
   {
      Step("38 the evaluation meters");

      CSSRTradingEngine  eacct;
      SSRExecutionModel  eex;
      eex.Init();
      eex.use_real_spread = true;
      eacct.SetExecution(eex);
      eacct.SetBalance(10000.0);

      SSRPropRules er;
      er.Init();
      er.enabled            = true;
      er.start_balance      = 10000.0;
      er.profit_target_pct  = 8.0;      // +800
      er.max_daily_loss_pct = 5.0;      // -500 from the day's open
      er.max_total_loss_pct = 10.0;     // -1000 from the start, static
      er.trailing           = false;
      er.min_trading_days   = 3;
      er.max_days           = 30;

      CSSRPropEvaluation ev;
      ev.Attach(GetPointer(eacct));
      ev.SetRules(er);
      ev.Reset();

      long eday = 20000;
      ev.OnClock(eday * SSR_PROP_DAY_MSC + 3600000);   // establishes the day

      Check("38 nothing is used before anything happens",
            ev.DailyUsed() == 0.0 && ev.TotalUsed() == 0.0 &&
            ev.TargetProgress() == 0.0,
            StringFormat("daily %.3f  total %.3f  target %.3f",
                         ev.DailyUsed(), ev.TotalUsed(), ev.TargetProgress()));

      //--- halfway down the daily allowance, a quarter of the overall one
      eacct.SetBalance(9750.0);
      ev.OnClock(eday * SSR_PROP_DAY_MSC + 7200000);
      bool half = (MathAbs(ev.DailyUsed() - 0.50) < 0.001 &&
                   MathAbs(ev.TotalUsed() - 0.25) < 0.001);
      Check("38 the fractions are the rules, not an approximation of them",
            half,
            StringFormat("-250 of a 500 daily allowance is %.3f, of a 1000 "
                         "overall one %.3f", ev.DailyUsed(), ev.TotalUsed()));

      //--- and up, where a loss meter must read empty rather than negative
      eacct.SetBalance(10400.0);
      ev.OnClock(eday * SSR_PROP_DAY_MSC + 10800000);
      bool up = (ev.DailyUsed() == 0.0 && ev.TotalUsed() == 0.0 &&
                 MathAbs(ev.TargetProgress() - 0.50) < 0.001);
      Check("38 a session in profit uses none of either allowance",
            up,
            StringFormat("daily %.3f  total %.3f  target %.3f of +800",
                         ev.DailyUsed(), ev.TotalUsed(), ev.TargetProgress()));

      //+------------------------------------------------------------------+
      //| THE CHECK THIS WHOLE STAGE EXISTS FOR.                           |
      //|                                                                  |
      //| Not "the meter is roughly right". At the exact equity where       |
      //| OnClock ends the run, the bar the trader is looking at must be    |
      //| full. A meter that reads 0.99 in the frame the evaluation reads    |
      //| FAILED is a meter that says "you have room" as the run ends.       |
      //+------------------------------------------------------------------+
      eacct.SetBalance(9500.0);                      // exactly the daily floor
      ev.OnClock(eday * SSR_PROP_DAY_MSC + 14400000);
      bool fired = (ev.State() == SSR_PROP_FAILED);
      bool full  = (ev.DailyUsed() >= 1.0);
      Check("38 the meter is full in the frame the rule fires",
            fired && full,
            StringFormat("state %s, daily meter %.3f - %s",
                         SSRPropStateName(ev.State()), ev.DailyUsed(),
                         (fired && full
                          ? "the bar and the verdict agree"
                          : "a bar that says 'room left' as the run ends is "
                            "worse than no bar")));

      //--- clamped, because a bar that can exceed its own width is a
      //--- drawing bug and a fraction over 1 would draw one
      eacct.SetBalance(1000.0);
      Check("38 neither meter can exceed its own width",
            ev.DailyUsed() <= 1.0 && ev.TotalUsed() <= 1.0 &&
            ev.DailyUsed() >= 0.0 && ev.TotalUsed() >= 0.0,
            StringFormat("daily %.3f  total %.3f at -9000",
                         ev.DailyUsed(), ev.TotalUsed()));

      //+------------------------------------------------------------------+
      //| THE DAY COUNT THE PANEL SHOWS IS THE ONE THE RULE USES.          |
      //|                                                                  |
      //| m_trading_days is incremented on the DAY BOUNDARY, so a trader   |
      //| who traded today was not counted for today until tomorrow. The   |
      //| rule that decides the verdict adds the open day back in; the     |
      //| accessor the panel reads did not - so on the third day of a       |
      //| three-day minimum the panel said 2, and a trader reading it       |
      //| would believe they could not pass a run that would have passed.   |
      //+------------------------------------------------------------------+
      CSSRTradingEngine  dacct;
      dacct.SetExecution(eex);
      dacct.SetBalance(10000.0);
      dacct.OnSessionStart(rsym, (int)SymbolInfoInteger(rsym, SYMBOL_DIGITS),
                           SymbolInfoDouble(rsym, SYMBOL_POINT), 0);

      CSSRPropEvaluation dev;
      dev.Attach(GetPointer(dacct));
      dev.SetRules(er);
      dev.Reset();
      dev.OnClock(eday * SSR_PROP_DAY_MSC + 3600000);

      Check("38 an untraded day counts for nothing",
            dev.TradingDays() == 0,
            StringFormat("%d day(s)", dev.TradingDays()));

      MqlTick dt[1];
      double dpt = SymbolInfoDouble(rsym, SYMBOL_POINT);
      if(dpt <= 0.0) dpt = 0.00001;
      double dbase = SymbolInfoDouble(rsym, SYMBOL_BID);
      if(dbase <= 0.0) dbase = 10000.0 * dpt;
      dt[0].time     = (datetime)((eday * SSR_PROP_DAY_MSC) / 1000);
      dt[0].time_msc = eday * SSR_PROP_DAY_MSC + 7200000;
      dt[0].bid      = dbase;
      dt[0].ask      = dbase + 10.0 * dpt;
      dt[0].last     = dbase;
      dt[0].volume   = 1;
      dt[0].flags    = 0;
      dacct.OnTicks(dt, 1);
      dacct.Open(SSR_ORDER_BUY, 0.01);
      dev.OnClock(eday * SSR_PROP_DAY_MSC + 7200000);

      Check("38 a day that was traded counts TODAY, not tomorrow",
            dev.TradingDays() == 1,
            StringFormat("%d of %d needed, on the day the trade was taken",
                         dev.TradingDays(), er.min_trading_days));
      Check("38 and the days meter reads the same number",
            MathAbs(dev.DaysProgress() - (1.0 / 3.0)) < 0.001,
            StringFormat("%.3f toward three days", dev.DaysProgress()));

      //--- the deadline is a fraction too, and is zero when unset
      Check("38 the deadline is measured against the days elapsed",
            MathAbs(dev.DeadlineUsed() - (1.0 / 30.0)) < 0.001,
            StringFormat("day %d of %d is %.3f",
                         dev.TotalDays(), er.max_days, dev.DeadlineUsed()));

      SSRPropRules nod = er;
      nod.max_days = 0;
      dev.SetRules(nod);
      Check("38 a run with no deadline reports no deadline pressure",
            dev.DeadlineUsed() == 0.0,
            StringFormat("%.3f - an empty bar teaches nobody what it counts, "
                         "so the panel draws none", dev.DeadlineUsed()));

      //+------------------------------------------------------------------+
      //| A RULE THAT DOES NOT EXIST IS NOT A RULE WITH ROOM LEFT.         |
      //|                                                                  |
      //| DailyFloor() on a challenge with no daily limit returns the       |
      //| equity the day OPENED at - a perfectly good number and a          |
      //| catastrophic thing to print under the word "floor", because it    |
      //| tells a trader in profit that they are failing at this instant.   |
      //| The fraction has to read zero so the panel can tell the two       |
      //| apart and say "no daily limit" instead.                            |
      //+------------------------------------------------------------------+
      SSRPropRules norule = er;
      norule.max_daily_loss_pct = 0.0;
      norule.max_total_loss_pct = 0.0;
      norule.profit_target_pct  = 0.0;
      dev.SetRules(norule);
      Check("38 a rule that was never set uses none of an allowance it "
            "does not have",
            dev.DailyUsed() == 0.0 && dev.TotalUsed() == 0.0 &&
            dev.TargetProgress() == 0.0,
            StringFormat("daily %.3f  total %.3f  target %.3f",
                         dev.DailyUsed(), dev.TotalUsed(),
                         dev.TargetProgress()));
      dev.SetRules(er);

      //+------------------------------------------------------------------+
      //| AND THE SHEET, ON A REAL CHART.                                  |
      //+------------------------------------------------------------------+
      long pchart = ChartOpen(rsym, PERIOD_M1);
      if(Check("38 a chart for the prop sheet", pchart != 0, rsym))
        {
         CSSRReplayGroup pgroup;
         pgroup.Add(GetPointer(ctrl));

         CSSRGroupPort pport;
         pport.Attach(GetPointer(pgroup));
         pport.AttachAccount(GetPointer(dacct));

         CSSRPanel pp;
         pp.Create(pchart, GetPointer(pport), "SSRE_");

         pp.Render();

         //+------------------------------------------------------------------+
         //| COMPACT IS A MODE, NOT AN ERROR - the lesson from stage 18.      |
         //|                                                                  |
         //| On a terminal with the Toolbox open there is no room for the tab  |
         //| strip, so there is no fifth tab to find and no sheet to measure.   |
         //| Asserting one anyway would be this stage failing on a screen      |
         //| where the product is working. It says out loud what went          |
         //| unmeasured instead.                                                |
         //+------------------------------------------------------------------+
         if(pp.IsCompact())
           {
            Note("38 the prop sheet was not measured",
                 StringFormat("this chart is %d px and compact mode has no "
                              "tab strip - close the Toolbox (Ctrl+T) and "
                              "re-run to measure it",
                              (int)ChartGetInteger(pchart,
                                                   CHART_HEIGHT_IN_PIXELS)));
            pp.Destroy();
            ChartClose(pchart);
           }
         else
           {
         //--- WITHOUT an evaluation attached there is no fifth tab. A
         //--- panel that showed an empty scoreboard to everyone who is
         //--- not being scored would be asking a question nobody put.
         Check("38 no evaluation, no Prop tab",
               ObjectFind(pchart, "SSRE_tab3") >= 0 &&
               ObjectFind(pchart, "SSRE_tab4") < 0,
               "four tabs, as every session without one has");

         pport.AttachProp(GetPointer(dev));
         pp.Render();
         Check("38 an evaluation adds the tab",
               ObjectFind(pchart, "SSRE_tab4") >= 0,
               "the fifth tab exists only while there is something to score");

         //+------------------------------------------------------------------+
         //| MEASURED AT ITS WORST CASE, NOT AT ITS EMPTIEST.                 |
         //|                                                                  |
         //| A finished run with a deadline draws everything this sheet can:   |
         //| four rows, the deadline line, the reason it ended, and the Reset   |
         //| button. A layout measured while half of it is hidden is a layout   |
         //| measured on a screen no user is looking at.                        |
         //+------------------------------------------------------------------+
         dacct.SetBalance(9000.0);                     // through both floors
         dev.OnClock(eday * SSR_PROP_DAY_MSC + 18000000);
         Check("38 the sheet is measured with everything on it",
               dev.State() == SSR_PROP_FAILED && er.max_days > 0,
               StringFormat("%s, deadline %d day(s) - the deepest this sheet "
                            "ever draws", SSRPropStateName(dev.State()),
                            er.max_days));

         pp.Dispatch("tab4");
         pp.Render();

         //--- the test checks its own eyes first: four meters, or every
         //--- assertion below is about a sheet that was never drawn
         int drawn = 0;
         for(int m = 0; m < 4; m++)
            if(ObjectFind(pchart, "SSRE_m" + IntegerToString(m) + "_bg") >= 0)
               drawn++;
         if(Check("38 the sheet draws one meter per rule",
                  drawn == 4, StringFormat("%d of 4", drawn)))
           {
            //--- EVERY METER HAS ITS NUMBER BESIDE IT. A bar is
            //--- unreadable to a colour-blind trader, illegible in a
            //--- screenshot, and meaningless to anyone who has not
            //--- learned which way is bad.
            int labelled = 0;
            for(int m = 0; m < 4; m++)
              {
               string vid = "SSRE_m" + IntegerToString(m) + "_v";
               if(ObjectFind(pchart, vid) >= 0 &&
                  ObjectGetString(pchart, vid, OBJPROP_TEXT) != "")
                  labelled++;
              }
            Check("38 no rule is carried by a bar alone",
                  labelled == 4,
                  StringFormat("%d of 4 meters have their measurement written "
                               "beside them", labelled));

            //+------------------------------------------------------------------+
            //| THE 63-CHARACTER CUT, MEASURED ON THE CHART ITSELF.              |
            //|                                                                  |
            //| The rules line has been over that limit since the evaluation      |
            //| shipped - "within 30" was never on screen for anybody - and       |
            //| nothing errored. This reads back what the objects actually hold.  |
            //+------------------------------------------------------------------+
            int cut = 0, worst_len = 0;
            string worst_txt = "";
            int total = ObjectsTotal(pchart, -1, OBJ_LABEL);
            for(int i = 0; i < total; i++)
              {
               string nm = ObjectName(pchart, i, -1, OBJ_LABEL);
               if(StringFind(nm, "SSRE_") != 0)
                  continue;
               string tx = ObjectGetString(pchart, nm, OBJPROP_TEXT);
               int ln = StringLen(tx);
               if(ln > worst_len) { worst_len = ln; worst_txt = nm; }
               if(ln > 63) cut++;
              }
            Check("38 nothing the panel draws is cut off by MetaTrader",
                  cut == 0,
                  StringFormat("longest label %d of 63 drawn (%s)",
                               worst_len, worst_txt));

            //+------------------------------------------------------------------+
            //| THE FRAME, ON THE ONE SHEET STAGE 18 CANNOT REACH.               |
            //|                                                                  |
            //| Stage 18 walks the four sheets every session has. This one        |
            //| exists only while an evaluation does, and its panel there has no   |
            //| port - so a row past the end of THIS sheet would be drawn over     |
            //| the status bar and no test would have seen it. Same invariant,     |
            //| same method: read the frame off the background the panel drew,     |
            //| so a future row is caught without editing this.                    |
            //+------------------------------------------------------------------+
            int f_top = 0, f_bottom = 0, deepest = 0;
            string deep_name = "";
            int all = ObjectsTotal(pchart, -1, -1);
            for(int i = 0; i < all; i++)
              {
               string nm = ObjectName(pchart, i, -1, -1);
               if(StringFind(nm, "SSRE_") != 0)
                  continue;
               int oy = (int)ObjectGetInteger(pchart, nm, OBJPROP_YDISTANCE);
               int oh = (int)ObjectGetInteger(pchart, nm, OBJPROP_YSIZE);
               //--- a label answers zero for its height and is drawn below
               //--- its anchor anyway, so it is allowed a line of text
               if(ObjectGetInteger(pchart, nm, OBJPROP_TYPE) == OBJ_LABEL)
                  oh = 12;
               if(nm == "SSRE_bg")
                 { f_top = oy; f_bottom = oy + oh; continue; }
               if(oy + oh > deepest)
                 { deepest = oy + oh; deep_name = nm; }
              }
            if(Check("38 the prop panel drew a frame to measure against",
                     f_bottom > f_top && deep_name != "",
                     StringFormat("frame %d..%d px", f_top, f_bottom)))
               Check("38 and the prop sheet stays inside it",
                     deepest <= f_bottom,
                     StringFormat("deepest control %s ends at %d, frame ends "
                                  "at %d (%d px %s)",
                                  StringSubstr(deep_name, 5), deepest, f_bottom,
                                  (int)MathAbs(f_bottom - deepest),
                                  (deepest <= f_bottom
                                   ? "spare"
                                   : "OVER - a row past the end is drawn over "
                                     "the status bar and reads as a rendering "
                                     "fault")));
           }

         //+------------------------------------------------------------------+
         //| A TAB THAT STOPPED EXISTING CANNOT STAY SELECTED.                |
         //|                                                                  |
         //| Four meters reading zero is not "no evaluation" - it is "an       |
         //| evaluation going badly", which is the opposite of the truth.      |
         //+------------------------------------------------------------------+
         SSRPropRules off = er;
         off.enabled = false;
         dev.SetRules(off);
         pp.Render();
         Check("38 the tab goes when the evaluation does",
               ObjectFind(pchart, "SSRE_tab4") < 0,
               "an object nobody redraws is an object that stays forever, so "
               "a shrinking strip has to remove what it leaves behind");
         Check("38 and the user is not left standing on it",
               pp.Tab() == SSR_TAB_STATS,
               StringFormat("tab %d - four meters reading zero would say "
                            "'going badly', not 'not running'", pp.Tab()));

         pp.Destroy();
         ChartClose(pchart);
           }
        }
   }

   //+------------------------------------------------------------------+
   //| 39. THE TALL PANEL, AND A CLOSE BUTTON THAT WAS NEVER A BUTTON.  |
   //|                                                                  |
   //| The Positions sheet held five rows because the sheet was 186 px   |
   //| and the sheet was 186 px because SSR_SHEET_H was a constant. A    |
   //| trader scaling into a position runs out of rows long before they  |
   //| run out of screen, and the panel had no way to use the screen.    |
   //|                                                                  |
   //| Writing that turned up something worse. Every row drew its "no    |
   //| stop" note into an object called px<r> and then drew its CLOSE    |
   //| BUTTON into an object called px<r>. ObjectCreate refuses a name   |
   //| that already exists, so the button was never created: ButtonC     |
   //| found the label, wrote "X" over the note and moved it right.      |
   //| PollClicks scans OBJ_BUTTON, so no press on it was ever seen -    |
   //| per-row close has not worked since it shipped, and the spread and |
   //| "no stop" notes have never once been on screen.                   |
   //|                                                                  |
   //| Both are checked here from the CHART, by object type, because     |
   //| that is the only thing that would have caught it.                 |
   //+------------------------------------------------------------------+
   {
      Step("39 the tall panel");

      long tchart = ChartOpen(rsym, PERIOD_M1);
      int  tch    = (int)ChartGetInteger(tchart, CHART_HEIGHT_IN_PIXELS);
      if(Check("39 a chart for the tall panel", tchart != 0, rsym))
        {
         CSSRTradingEngine tacct;
         tacct.SetBalance(100000.0);
         tacct.OnSessionStart(rsym,
                              (int)SymbolInfoInteger(rsym, SYMBOL_DIGITS),
                              SymbolInfoDouble(rsym, SYMBOL_POINT), 0);

         MqlTick tt[1];
         double tpt = SymbolInfoDouble(rsym, SYMBOL_POINT);
         if(tpt <= 0.0) tpt = 0.00001;
         double tbase = SymbolInfoDouble(rsym, SYMBOL_BID);
         if(tbase <= 0.0) tbase = 10000.0 * tpt;
         tt[0].bid = tbase; tt[0].ask = tbase + 10.0 * tpt;
         tt[0].time_msc = 1000; tt[0].last = tbase;
         tt[0].volume = 1; tt[0].flags = 0;
         tacct.OnTicks(tt, 1);

         //--- twelve, so the wire is full and the standard sheet has to
         //--- admit it is hiding some
         int opened = 0;
         for(int i = 0; i < 12; i++)
            if(tacct.Open(SSR_ORDER_BUY, 0.01) > 0)
               opened++;

         CSSRReplayGroup tgroup;
         tgroup.Add(GetPointer(ctrl));
         CSSRGroupPort tport;
         tport.Attach(GetPointer(tgroup));
         tport.AttachAccount(GetPointer(tacct));

         CSSRPanel tp;
         tp.Create(tchart, GetPointer(tport), "SSRT_");
         tp.Render();

         //--- THE TEST CHECKS ITS OWN EYES FIRST. Everything below is
         //--- about a list of twelve; without twelve it would be about
         //--- nothing, and would pass.
         if(!Check("39 twelve positions to look at", opened == 12,
                   StringFormat("%d opened", opened)))
           {
            tacct.CloseAll();
            tp.Destroy();
            ChartClose(tchart);
           }
         else if(tp.IsCompact())
           {
            Note("39 the tall panel was not measured",
                 StringFormat("this chart is %d px and compact mode has no "
                              "sheet at all - close the Toolbox (Ctrl+T) and "
                              "re-run", tch));
            tacct.CloseAll();
            tp.Destroy();
            ChartClose(tchart);
           }
         else
           {
            tp.Dispatch("tab1");            // Positions
            tp.Render();

            //+------------------------------------------------------------------+
            //| THE BUG. A close button that is a label is a button that cannot   |
            //| be pressed, and it looks completely normal on the chart.          |
            //+------------------------------------------------------------------+
            Check("39 the per-row close is a BUTTON, not a label wearing an X",
                  ObjectFind(tchart, "SSRT_px0") >= 0 &&
                  ObjectGetInteger(tchart, "SSRT_px0", OBJPROP_TYPE) == OBJ_BUTTON,
                  "PollClicks scans OBJ_BUTTON; a label named px0 is a close "
                  "button no press can ever reach");

            Check("39 and the row note has an object of its own",
                  ObjectFind(tchart, "SSRT_pn0") >= 0 &&
                  ObjectGetInteger(tchart, "SSRT_pn0", OBJPROP_TYPE) == OBJ_LABEL,
                  "'no stop' and the entry spread were written into the same "
                  "object the X was, and overwritten every frame");

            //--- standard first: five drawn out of twelve, and it says so
            int cap_std = tp.RowCap();
            Check("39 the standard sheet shows five",
                  cap_std == 5, StringFormat("%d rows", cap_std));
            Check("39 and admits the other seven exist",
                  ObjectFind(tchart, "SSRT_posmore") >= 0,
                  "a display cap that hides trades silently is a panel "
                  "lying by omission");
            Check("39 the sixth row is not drawn",
                  ObjectFind(tchart, "SSRT_pr5") < 0,
                  "row 5 of a five-row sheet would be drawn over the hint");

            int h_std = tp.PanelH();

            //+------------------------------------------------------------------+
            //| P, THROUGH THE KEY PATH - not by calling the toggle. A binding    |
            //| that exists in the table and is not reachable from a keypress is  |
            //| a key the card promises and the panel ignores.                    |
            //+------------------------------------------------------------------+
            Check("39 P is bound to the panel size",
                  SSRKeyToCommand(SSR_VK_P) == SSR_CMD_PANEL_SIZE,
                  SSRCmdName(SSRKeyToCommand(SSR_VK_P)));

            //--- OnEvent takes lparam BY REFERENCE, so the key code has
            //--- to be a variable. A macro cannot bind to a const long&.
            double dz  = 0.0;
            long   vkp = SSR_VK_P;
            tp.OnEvent(CHARTEVENT_KEYDOWN, vkp, dz, "");
            tp.Render();

            Check("39 the wish is granted whatever the chart can hold",
                  tp.IsPro(),
                  "kept even where it cannot be honoured, so an afternoon on "
                  "a laptop does not cost the setting");

            if(tch > 0 && tch < SSR_PANEL_TALL_H + 24)
              {
               //+------------------------------------------------------------------+
               //| NO ROOM IS A RESULT, NOT A FAILURE.                              |
               //+------------------------------------------------------------------+
               Check("39 a chart with no room does not grow the panel anyway",
                     !tp.IsTall() && tp.PanelH() == h_std,
                     StringFormat("chart %d px, tall panel needs %d - a panel "
                                  "taller than its chart is an invisible panel",
                                  tch, SSR_PANEL_TALL_H + 24));
               Note("39 the tall layout was not measured",
                    StringFormat("this chart is %d px and the tall panel needs "
                                 "%d - make the chart taller and re-run",
                                 tch, SSR_PANEL_TALL_H + 24));
              }
            else
              {
               Check("39 the sheet grows by exactly what the constant says",
                     tp.IsTall() && tp.PanelH() == h_std + SSR_SHEET_GROW,
                     StringFormat("%d px -> %d px", h_std, tp.PanelH()));

               int cap_tall = tp.RowCap();
               Check("39 and the extra height becomes rows",
                     cap_tall == SSR_POS_MAX,
                     StringFormat("%d rows, up from %d", cap_tall, cap_std));

               Check("39 all twelve are drawn",
                     ObjectFind(tchart, "SSRT_pr11") >= 0 &&
                     ObjectFind(tchart, "SSRT_px11") >= 0,
                     "the last row is the one a five-row cap was hiding");

               Check("39 and nothing is hidden any more, so nothing says so",
                     ObjectFind(tchart, "SSRT_posmore") < 0,
                     "'+N not shown' with nothing not shown is a line that "
                     "teaches the user to ignore it");

               //+------------------------------------------------------------------+
               //| TWO DIGITS. The dispatch matched a name of length THREE, which   |
               //| is px0..px9 - correct on a five-row sheet and silently wrong on  |
               //| a twelve-row one, where the last two rows' buttons would have    |
               //| done nothing at all.                                              |
               //+------------------------------------------------------------------+
               long last = 0;
               int  before = tacct.OpenCount();
               //--- whichever ticket row 11 is showing; read from the state
               //--- the panel drew, not guessed from the order they opened
               SSRUiState ts;
               if(tport.ReadState(ts) && ts.pos_rows >= 12)
                  last = ts.pos_ticket[11];
               tp.Dispatch("px11");
               Check("39 the last row's close button reaches the last row",
                     last > 0 && tacct.OpenCount() == before - 1,
                     StringFormat("#%d closed: %d open, was %d",
                                  (int)last, tacct.OpenCount(), before));

               //--- and a name that merely starts "px" closes nothing.
               //--- StringToInteger answers 0 for anything it cannot read,
               //--- and 0 is a row number.
               int now_open = tacct.OpenCount();
               tp.Dispatch("pxq");
               Check("39 and a name that is not a row closes nothing",
                     tacct.OpenCount() == now_open,
                     StringFormat("%d open, unchanged - 'not a number' must "
                                  "not resolve to row zero", tacct.OpenCount()));

               //+------------------------------------------------------------------+
               //| THE FRAME, on the sheet that just grew.                          |
               //+------------------------------------------------------------------+
               tp.Render();
               int f_top = 0, f_bottom = 0, deepest = 0;
               string deep_name = "";
               int all = ObjectsTotal(tchart, -1, -1);
               for(int i = 0; i < all; i++)
                 {
                  string nm = ObjectName(tchart, i, -1, -1);
                  if(StringFind(nm, "SSRT_") != 0)
                     continue;
                  int oy = (int)ObjectGetInteger(tchart, nm, OBJPROP_YDISTANCE);
                  int oh = (int)ObjectGetInteger(tchart, nm, OBJPROP_YSIZE);
                  if(ObjectGetInteger(tchart, nm, OBJPROP_TYPE) == OBJ_LABEL)
                     oh = 12;
                  if(nm == "SSRT_bg")
                    { f_top = oy; f_bottom = oy + oh; continue; }
                  if(oy + oh > deepest)
                    { deepest = oy + oh; deep_name = nm; }
                 }
               if(Check("39 the tall panel drew a frame to measure against",
                        f_bottom > f_top && deep_name != "",
                        StringFormat("frame %d..%d px", f_top, f_bottom)))
                  Check("39 and twelve rows stay inside it",
                        deepest <= f_bottom,
                        StringFormat("deepest control %s ends at %d, frame "
                                     "ends at %d (%d px %s)",
                                     StringSubstr(deep_name, 5), deepest,
                                     f_bottom,
                                     (int)MathAbs(f_bottom - deepest),
                                     (deepest <= f_bottom
                                      ? "spare"
                                      : "OVER - raise SSR_SHEET_GROW")));

               //--- and back. The rows the tall sheet drew have to GO:
               //--- nothing repaints an object nobody draws any more.
               dz  = 0.0;
               vkp = SSR_VK_P;
               tp.OnEvent(CHARTEVENT_KEYDOWN, vkp, dz, "");
               tp.Render();
               Check("39 shrinking sweeps the rows it can no longer hold",
                     !tp.IsTall() && tp.PanelH() == h_std &&
                     ObjectFind(tchart, "SSRT_pr11") < 0 &&
                     ObjectFind(tchart, "SSRT_px11") < 0,
                     "a row left behind by a shrinking sheet is drawn over "
                     "the chart forever");
              }

            tacct.CloseAll();
            tp.Destroy();
            ChartClose(tchart);
           }
        }
   }

   //+------------------------------------------------------------------+
   //| 40. NOTHING IS DRAWN OVER ANYTHING ELSE, MEASURED.               |
   //|                                                                  |
   //| Every column in this panel was placed by arithmetic in somebody's |
   //| head. The Positions row is what that is worth: its note column    |
   //| sat nineteen pixels from the money column and would have printed  |
   //| straight through it - and nobody saw that for four builds only    |
   //| because a second bug stopped the note being drawn at all.         |
   //|                                                                  |
   //| So the labels are MEASURED, with the real face at the real point  |
   //| size on the machine the user is on, which is the only place the   |
   //| question has an answer: the same label is a different width at    |
   //| 100% and at 150% display scaling.                                 |
   //|                                                                  |
   //| Every sheet, because a collision only exists on the sheet that    |
   //| draws both halves of it.                                          |
   //+------------------------------------------------------------------+
   {
      Step("40 measuring every label");

      Stash(SSR_PANEL_FILE);

      long lchart = ChartOpen(rsym, PERIOD_M1);
      if(Check("40 a chart to measure on", lchart != 0, rsym))
        {
         //--- a probe first: if this terminal cannot measure text, every
         //--- check below would pass by measuring nothing
         uint pw = 0, ph = 0;
         bool can_measure = (TextSetFont(SSR_FONT, -80, 0, 0) &&
                             TextGetSize("Close all", pw, ph) && pw > 0);

         if(!can_measure)
           {
            Note("40 nothing was measured",
                 "TextGetSize failed on this terminal, so the overlap test "
                 "would have passed by having no boxes to compare");
            ChartClose(lchart);
           }
         else
           {
            CSSRTradingEngine lacct;
            lacct.SetBalance(10000.0);
            lacct.OnSessionStart(rsym,
                                 (int)SymbolInfoInteger(rsym, SYMBOL_DIGITS),
                                 SymbolInfoDouble(rsym, SYMBOL_POINT), 0);
            MqlTick lt[1];
            double lpt = SymbolInfoDouble(rsym, SYMBOL_POINT);
            if(lpt <= 0.0) lpt = 0.00001;
            double lbase = SymbolInfoDouble(rsym, SYMBOL_BID);
            if(lbase <= 0.0) lbase = 10000.0 * lpt;
            lt[0].bid = lbase; lt[0].ask = lbase + 10.0 * lpt;
            lt[0].time_msc = 1000; lt[0].last = lbase;
            lt[0].volume = 1; lt[0].flags = 0;
            lacct.OnTicks(lt, 1);
            //--- a position with NO STOP, so the note column is populated:
            //--- the empty case is the one that never collided
            lacct.Open(SSR_ORDER_BUY, 0.10, 0.0, 0.0);

            CSSRReplayGroup lgroup;
            lgroup.Add(GetPointer(ctrl));
            CSSRGroupPort lport;
            lport.Attach(GetPointer(lgroup));
            lport.AttachAccount(GetPointer(lacct));

            CSSRPanel lp;
            lp.Create(lchart, GetPointer(lport), "SSRL_");
            lp.Render();

            if(lp.IsCompact())
              {
               Note("40 only the compact panel was measured",
                    StringFormat("this chart is %d px and has no sheets - "
                                 "close the Toolbox (Ctrl+T) and re-run to "
                                 "measure all five",
                                 (int)ChartGetInteger(lchart,
                                                CHART_HEIGHT_IN_PIXELS)));
               string cw = "";
               int chits = LabelOverlaps(lchart, "SSRL_", cw);
               Check("40 the compact panel draws nothing over anything",
                     chits == 0,
                     (chits == 0 ? "no overlapping labels"
                                 : StringFormat("%d pair(s), worst: %s",
                                                chits, cw)));
              }
            else
              {
               //--- the sheet a collision is on is the sheet that draws
               //--- both halves of it, so every one gets its own pass
               string tabs[] = {"tab0", "tab1", "tab2", "tab3"};
               for(int t = 0; t < ArraySize(tabs); t++)
                 {
                  lp.Dispatch(tabs[t]);
                  lp.Render();
                  string sw = "";
                  int hits = LabelOverlaps(lchart, "SSRL_", sw);
                  Check(StringFormat("40 sheet %d draws nothing over anything",
                                     t),
                        hits == 0,
                        (hits == 0
                         ? "measured, no overlapping labels"
                         : StringFormat("%d pair(s), worst: %s", hits, sw)));
                 }

               //+------------------------------------------------------------------+
               //| AND THE ROW THAT STARTED IT, SPECIFICALLY.                       |
               //|                                                                  |
               //| A position with no stop draws all four columns of a Positions    |
               //| row at once: the position, the note, the money and the buttons.   |
               //| That combination is the one that collided, and it is the one a    |
               //| general sweep would miss if the sheet happened to be empty.        |
               //+------------------------------------------------------------------+
               lp.Dispatch("tab1");
               lp.Render();
               int nx, ny, nw, nh, mx, my, mw, mh;
               bool got = (LabelBox(lchart, "SSRL_pn0", nx, ny, nw, nh) &&
                           LabelBox(lchart, "SSRL_pl0", mx, my, mw, mh));
               if(Check("40 the no-stop note and the money are both drawn",
                        got, "a row with no stop draws every column it has"))
                  Check("40 and the note stops before the money starts",
                        nx + nw <= mx,
                        StringFormat("note ends at %d, money starts at %d "
                                     "(%d px %s)", nx + nw, mx,
                                     (int)MathAbs(mx - (nx + nw)),
                                     (nx + nw <= mx ? "clear" : "OVER")));
              }

            //+------------------------------------------------------------------+
            //| A PANEL ON A CHART WITH ROOM IS ENTIRELY ON THAT CHART.          |
            //|                                                                  |
            //| The clamp only kept the CAPTION reachable - a rule written for a  |
            //| panel dragged off the bottom and applied to the right edge too.   |
            //| So a panel nudged right on a wide chart stayed hanging off it,    |
            //| with close, collapse, corner, ? and K all past the edge.          |
            //+------------------------------------------------------------------+
            int lcw = (int)ChartGetInteger(lchart, CHART_WIDTH_IN_PIXELS);
            lp.Destroy();

            CSSRSessionFile far;
            if(far.Create(SSR_PANEL_FILE))
              {
               far.Section("panel");
               far.SetInt("x", 7000);   // inside the sanity bound, far right
               far.SetInt("y", 10);
               far.Close();
              }
            CSSRPanel lp2;
            lp2.Create(lchart, GetPointer(lport), "SSRL_");
            lp2.Render();
            if(lcw >= SSR_PANEL_W)
               Check("40 a panel from far off the right edge is pulled fully back",
                     lp2.X() + SSR_PANEL_W <= lcw,
                     StringFormat("x %d + %d panel = %d, on a %d px chart",
                                  lp2.X(), SSR_PANEL_W,
                                  lp2.X() + SSR_PANEL_W, lcw));
            else
               Note("40 the right-edge clamp was not measured",
                    StringFormat("this chart is %d px and the panel is %d - "
                                 "narrower than the panel is the one case "
                                 "the clamp cannot fix", lcw, SSR_PANEL_W));
            lp2.Destroy();

            lacct.CloseAll();
            ChartClose(lchart);
           }
        }

      Unstash(SSR_PANEL_FILE);

      //+------------------------------------------------------------------+
      //| 40b. THE PLANNING LINES SAY WHICH IS WHICH.                      |
      //|                                                                  |
      //| A red one, a green one and an amber one, and nothing written on   |
      //| any of them: which was the stop and which the target was carried  |
      //| by COLOUR ALONE. A trader who cannot separate this red from this  |
      //| green was being asked to drag one below the price and one above   |
      //| it, with no way to tell them apart but hovering each in turn -     |
      //| and a tooltip is not a second channel, it is the same channel      |
      //| behind a delay.                                                   |
      //+------------------------------------------------------------------+
      long gchart = ChartOpen(rsym, PERIOD_M1);
      if(Check("40 a chart for the planning lines", gchart != 0, rsym))
        {
         CSSRTradeLines gl;
         gl.Attach(gchart, (int)SymbolInfoInteger(rsym, SYMBOL_DIGITS),
                   SymbolInfoDouble(rsym, SYMBOL_POINT),
                   SSR_C_LINE_SL, SSR_C_LINE_TP);
         double gp = SymbolInfoDouble(rsym, SYMBOL_BID);
         if(gp <= 0.0) gp = 1.0;
         double gpt = SymbolInfoDouble(rsym, SYMBOL_POINT);
         if(gpt <= 0.0) gpt = 0.00001;

         //--- Arm takes a PRICE, a stop DISTANCE in points and an R:R -
         //--- not two prices. Read before writing, after four guesses
         //--- in this project that each cost a compile.
         bool armed = gl.Arm(gp, 100.0, 2.0);
         if(Check("40 the lines arm", armed,
                  StringFormat("entry %.5f, 100 pt stop, 2R target", gp)))
           {
            string sl_txt = "", tp_txt = "";
            int found = 0;
            int gtot = ObjectsTotal(gchart, -1, OBJ_HLINE);
            for(int i = 0; i < gtot; i++)
              {
               string nm = ObjectName(gchart, i, -1, OBJ_HLINE);
               string tx = ObjectGetString(gchart, nm, OBJPROP_TEXT);
               if(StringFind(tx, "STOP") >= 0)   { sl_txt = tx; found++; }
               if(StringFind(tx, "TARGET") >= 0) { tp_txt = tx; found++; }
              }
            Check("40 the stop and the target carry their names, not just "
                  "their colours",
                  found >= 2,
                  (found >= 2
                   ? "\"" + sl_txt + "\" and \"" + tp_txt + "\""
                   : StringFormat("%d of 2 named - the chart draws object "
                                  "descriptions, and these two had none",
                                  found)));
           }
         gl.Clear();
         ChartClose(gchart);
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
//| WHAT A LABEL ACTUALLY OCCUPIES, IN PIXELS, ON THIS TERMINAL.     |
//|                                                                  |
//| Every column in this panel was placed by arithmetic in somebody's |
//| head - "that's about four pixels a character, so 128 is clear of  |
//| the price". The Positions row is the proof that it does not work: |
//| its note column sat nineteen pixels from the money column and     |
//| would have printed straight through it, and nobody saw that for   |
//| four builds because the note had a second bug that stopped it      |
//| being drawn at all.                                               |
//|                                                                  |
//| TextGetSize answers with the real face at the real point size on  |
//| the machine the user is on, which is the only place the question  |
//| has an answer: the same label is a different width at 100% and at |
//| 150% display scaling.                                             |
//|                                                                  |
//| Negative size means tenths of a point and follows the OS scaling, |
//| which is exactly what OBJPROP_FONTSIZE does.                      |
//+------------------------------------------------------------------+
bool LabelBox(const long chart, const string name,
              int &lx, int &ly, int &lw, int &lh)
  {
   if(ObjectFind(chart, name) < 0)
      return false;
   if(ObjectGetInteger(chart, name, OBJPROP_TYPE) != OBJ_LABEL)
      return false;
   string txt = ObjectGetString(chart, name, OBJPROP_TEXT);
   if(txt == "")
      return false;                    // nothing drawn, nothing to collide

   string font = ObjectGetString(chart, name, OBJPROP_FONT);
   int    fs   = (int)ObjectGetInteger(chart, name, OBJPROP_FONTSIZE);
   if(font == "" || fs <= 0)
      return false;

   uint tw = 0, th = 0;
   if(!TextSetFont(font, -fs * 10, 0, 0))
      return false;
   if(!TextGetSize(txt, tw, th))
      return false;

   lx = (int)ObjectGetInteger(chart, name, OBJPROP_XDISTANCE);
   ly = (int)ObjectGetInteger(chart, name, OBJPROP_YDISTANCE);
   lw = (int)tw;
   lh = (int)th;
   return true;
  }

//+------------------------------------------------------------------+
//| Measure every label of one panel and report the worst overlap.   |
//|                                                                  |
//| Returns the number of overlapping PAIRS, and names the worst one. |
//| Two labels overlap when their boxes intersect by more than the    |
//| tolerance - one pixel, because a face's reported width and its    |
//| painted extent can differ by that much and a test that cries at   |
//| one pixel is a test people switch off.                            |
//+------------------------------------------------------------------+
int LabelOverlaps(const long chart, const string prefix, string &worst)
  {
   string names[];
   int    xs[], ys[], ws[], hs[];
   int    n = 0;
   int    total = ObjectsTotal(chart, -1, OBJ_LABEL);
   ArrayResize(names, total); ArrayResize(xs, total);
   ArrayResize(ys, total);    ArrayResize(ws, total);
   ArrayResize(hs, total);

   for(int i = 0; i < total; i++)
     {
      string nm = ObjectName(chart, i, -1, OBJ_LABEL);
      if(StringFind(nm, prefix) != 0)
         continue;
      int lx, ly, lw, lh;
      if(!LabelBox(chart, nm, lx, ly, lw, lh))
         continue;
      names[n] = nm; xs[n] = lx; ys[n] = ly; ws[n] = lw; hs[n] = lh;
      n++;
     }

   int hits = 0, deepest = 0;
   worst = "";
   for(int a = 0; a < n; a++)
      for(int b = a + 1; b < n; b++)
        {
         int ox = MathMin(xs[a] + ws[a], xs[b] + ws[b]) - MathMax(xs[a], xs[b]);
         int oy = MathMin(ys[a] + hs[a], ys[b] + hs[b]) - MathMax(ys[a], ys[b]);
         if(ox <= 1 || oy <= 1)
            continue;
         hits++;
         if(ox > deepest)
           {
            deepest = ox;
            worst = StringFormat("%s [%d..%d] over %s [%d..%d], %d px",
                                 StringSubstr(names[a], StringLen(prefix)),
                                 xs[a], xs[a] + ws[a],
                                 StringSubstr(names[b], StringLen(prefix)),
                                 xs[b], xs[b] + ws[b], ox);
           }
        }
   return hits;
  }

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
         Log(StringFormat("  NOTE  %s could not be deleted (%d) - run SSR_Z_Cleanup",
                     rsym, GetLastError()));
     }
  }

void Done(void)
  {
   Log(StringFormat("=== %d passed, %d FAILED ===", g_pass, g_fail));
   if(g_fail == 0)
      Log("The pipeline works end to end. If the tool still looks dead on a "
            "chart, the problem is the VIEW - speed too low, or a chart too "
            "short for the panel - not the engine.");
   else
      Log("The first FAIL is the layer to fix; everything below it is a "
            "consequence.");

   if(g_fh != INVALID_HANDLE)
     {
      FileClose(g_fh);
      g_fh = INVALID_HANDLE;
     }

   //--- the name it ACTUALLY wrote, which is not always the usual one
   string sent = StringFormat("--> SEND THIS ONE FILE:  MQL5\\Files\\%s   "
                              "(%d lines)", g_path, g_out_n);
   Print(sent);
   Print("--> Toolbox has a Files tab, or: File menu -> Open Data Folder -> MQL5 -> Files");
   //--- on the chart too. A run that finishes while the log pane is
   //--- scrolled away has told nobody anything.
   Comment(StringFormat("SS Replay smoke test: %d passed, %d FAILED\n%s",
                        g_pass, g_fail, sent));
  }
//+------------------------------------------------------------------+
