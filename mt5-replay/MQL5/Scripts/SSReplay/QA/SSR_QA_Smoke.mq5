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
#include <SSReplay/Core/SSR_ReplayController.mqh>
#include <SSReplay/Core/SSR_MasterClock.mqh>
#include <SSReplay/Data/SSR_Mt5DataSource.mqh>
#include <SSReplay/Mt5/SSR_CustomSymbolSink.mqh>

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

   //--- 7. stepping ------------------------------------------------
   ctrl.Pause();
   int step_before = Bars(rsym, PERIOD_M1);
   ctrl.StepBars(10);
   Check("step forward adds bars", Bars(rsym, PERIOD_M1) > step_before,
         StringFormat("%d -> %d", step_before, Bars(rsym, PERIOD_M1)));

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
