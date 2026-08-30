//+------------------------------------------------------------------+
//|                                          SSReplayStandalone.mq5  |
//|                        SS Replay - Standalone Host (Phases 1-5)  |
//|                                                                  |
//|  The first time every layer runs together: data source, engine,  |
//|  custom symbol sink, chart manager and panel, in one program.    |
//|                                                                  |
//|  WHY AN EA AND NOT AN INDICATOR                                  |
//|  The design calls for the engine in a Service and the panel in   |
//|  an indicator, so the EA slot stays free for the user's own      |
//|  strategy. That split needs an IPC transport which does not      |
//|  exist yet. Because the panel talks through CSSRReplayPort, the  |
//|  move is a wiring change - swap CSSRDirectPort for an IPC port   |
//|  and this file becomes two - not a rewrite of anything.          |
//|                                                                  |
//|  Attach to ANY chart. It opens a separate replay chart and drives |
//|  the engine from OnTimer. The panel stays on THIS chart, because  |
//|  MetaTrader delivers chart events only to the chart a program is   |
//|  attached to.                                                     |
//|                                                                  |
//|  KNOWN LIMITATION OF THIS HOST                                    |
//|  Changing the timeframe of the chart this EA sits on reinitialises |
//|  the EA, which rebuilds the session from scratch. The replay chart |
//|  is unaffected - only the host chart matters - so put this on a    |
//|  chart you will leave alone. Removing that limitation is exactly   |
//|  what moving the engine into a Service buys, and is why the split  |
//|  is the next structural step rather than a nicety.                 |
//+------------------------------------------------------------------+
#property description "SS Replay - standalone replay host"
#property version   "1.00"

#include <SSReplay/Common/SSR_Types.mqh>
#include <SSReplay/Common/SSR_Time.mqh>
#include <SSReplay/Common/SSR_Log.mqh>
#include <SSReplay/Core/SSR_ReplayController.mqh>
#include <SSReplay/Data/SSR_Mt5DataSource.mqh>
#include <SSReplay/Mt5/SSR_CustomSymbolSink.mqh>
#include <SSReplay/Chart/SSR_ChartManager.mqh>
#include <SSReplay/Chart/SSR_TradeLines.mqh>
#include <SSReplay/Ui/SSR_Panel.mqh>
#include <SSReplay/Ui/SSR_RangeDialog.mqh>
#include <SSReplay/Data/SSR_HistoryCatalog.mqh>
#include <SSReplay/Trading/SSR_TradingEngine.mqh>
#include <SSReplay/Trading/SSR_Statistics.mqh>
#include <SSReplay/Trading/SSR_Journal.mqh>
#include <SSReplay/Trading/SSR_AutoPause.mqh>
#include <SSReplay/Core/SSR_MasterClock.mqh>
#include <SSReplay/Ui/SSR_GroupPort.mqh>
#include <SSReplay/Data/SSR_SessionWatcher.mqh>
#include <SSReplay/Data/SSR_RandomPicker.mqh>
#include <SSReplay/Chart/SSR_BlindMode.mqh>
#include <SSReplay/Session/SSR_SessionManager.mqh>
#include <SSReplay/Strategy/SSR_MarketView.mqh>
#include <SSReplay/Strategy/SSR_StrategyHost.mqh>
#include <SSReplay/Strategy/SSR_RefStrategy.mqh>
#include <SSReplay/Integration/SSR_Publisher.mqh>
#include <SSReplay/Ui/SSR_SessionDialog.mqh>

input string          InpSymbol     = "";                   // Symbol (empty = this chart)
input datetime        InpStart      = 0;                    // Replay start (0 = auto)
input int             InpReplayBars = 2000;                 // Bars to replay when start is auto
input int             InpWarmupBars = 1000;                 // Warmup bars for HTF context
input ENUM_TIMEFRAMES InpChartTf    = PERIOD_M5;            // Replay chart timeframe
input int             InpSlot       = 1;                    // Replay slot
input int             InpTicksPerBar = 8;                   // Ticks per M1 bar (synthetic)
input double          InpSpreadPoints = 20;                 // Simulated spread, in points
input int             InpPumpMs     = 40;                   // Engine tick interval (ms)

//--- The execution model. Every one of these is an ASSUMPTION about a
//--- broker, so every one is an input rather than a constant buried in
//--- the code. Left at zero, a cost is not modelled - and the
//--- statistics say so out loud rather than pretending it was free.
input double          InpBalance    = 10000.0;              // Virtual starting balance
input double          InpCommission = 0.0;                  // Commission per lot, per side
input double          InpSlippage   = 0.0;                  // Slippage, in points (always adverse)
input double          InpSwapLong   = 0.0;                  // Swap per lot per day, long
input double          InpSwapShort  = 0.0;                  // Swap per lot per day, short
input double          InpMarginLot  = 0.0;                  // Margin per lot (fallback; 0 = not modelled)
input double          InpStopout    = 0.0;                  // Stop out level, percent (0 = off)

//--- Phase 11 -------------------------------------------------------
input string          InpAlsoSymbols = "";                   // Extra symbols, comma separated (max 3)
input string          InpExtraTfs    = "";                   // Extra chart timeframes, e.g. "M15,H1"
input bool            InpRandom      = false;                // Random start (and symbol, if a list is given)
input string          InpSeed        = "";                   // Seed to repeat a random session (blank = new)
input ENUM_SSR_BLIND  InpBlind       = SSR_BLIND_OFF;        // Blind mode
input bool            InpPauseEntry  = false;                // Pause when an order fills
input bool            InpPauseSL     = true;                 // Pause when a stop is hit
input bool            InpPauseTP     = true;                 // Pause when a target is hit
input ENUM_SSR_SESSION_MODE InpPauseSession = SSR_SESSION_OFF; // Pause on a new session

//--- Phase 12 -------------------------------------------------------
input string          InpSession     = "";                   // Session name (blank = do not save or resume)
input bool            InpResume      = true;                 // Resume it if the file exists

//--- Phase 13 -------------------------------------------------------
input bool            InpRefStrategy = false;                // Run the reference strategy (a template, not advice)
input ENUM_TIMEFRAMES InpStratTf     = PERIOD_M15;           // Its decision timeframe
input int             InpStratLookback = 20;                 // Its breakout lookback, in bars
input double          InpStratRisk   = 0.5;                  // Its risk per trade, percent

//--- Phase 14 -------------------------------------------------------
//--- Read access is always published. The other two are OFF unless
//--- asked for: "another program may trade in my account" is not
//--- something to arrive at by leaving a box unticked.
input bool            InpPublish     = true;                 // Publish session state to other products
input bool            InpAllowControl = false;               // Let them drive the replay
input bool            InpAllowTrade  = false;                // Let them place VIRTUAL trades

//--- Phase 15 -------------------------------------------------------
input double          InpRiskPercent = 0.5;                  // Risk per trade from the panel, percent
input bool            InpTradeLines  = true;                 // Draw draggable stop/target lines
input double          InpStopPoints  = 0;                    // Default stop, in points (0 = 10x the spread)
input double          InpRR          = 2.0;                  // Target distance, as a multiple of the stop

CSSRMt5DataSource    g_src;
CSSRCustomSymbolSink g_sink;
CSSRReplayController g_ctrl;
CSSRChartManager     g_charts;
CSSRPanel            g_panel;
CSSRHistoryCatalog   g_catalog;
CSSRRangeDialog      g_dialog;
CSSRTradeLines       g_lines;

//--- Phase 11. One clock over every stream; the panel talks to the
//--- GROUP, so a transport command can never move one chart alone.
CSSRReplayGroup      g_group;
CSSRGroupPort        g_gport;
CSSRBlindMode        g_blind;
CSSRRandomPicker     g_picker;
CSSRSessionWatcher   g_session;
CSSRTradeAutoPause   g_autopause;
CSSRSessionManager   g_session_mgr;
bool                 g_resumed = false;

//--- Phase 13. The view holds only what the engine published, so a
//--- strategy has no bar to read ahead by accident.
CSSRMarketView       g_view;
CSSRStrategyHost     g_strategies;
CSSRRefBreakout      g_ref_strategy;

//--- How many streams beyond the primary one. Declared HERE, above
//--- every array that uses it: a #define takes effect from the line
//--- it appears on, so one placed further down is not a smaller
//--- mistake than a missing one.
#define SSR_EXTRA_STREAMS  (SSR_MAX_STREAMS - 1)

//--- Phase 14. One-directional: this product publishes a contract
//--- and depends on nobody. There is no SSProX header here.
CSSRPublisher        g_publisher;
//--- one publisher per stream, so a client watching the second
//--- instrument is not told about the first (closes T60)
CSSRPublisher        g_publisher2[SSR_EXTRA_STREAMS];
CSSRSessionDialog    g_session_dlg;

//--- extra streams. Index 0 is g_src/g_sink/g_ctrl above; these are
//--- the rest, and they exist whether or not they are used because
//--- MQL5 has no place to put a heap of them.
CSSRMt5DataSource    g_src2[SSR_EXTRA_STREAMS];
CSSRCustomSymbolSink g_sink2[SSR_EXTRA_STREAMS];
CSSRReplayController g_ctrl2[SSR_EXTRA_STREAMS];
CSSRChartManager     g_charts2[SSR_EXTRA_STREAMS];
int                  g_extra = 0;

//--- The virtual account. It observes the replay stream and NOTHING
//--- ELSE: there is no OrderSend anywhere below it, so no path exists
//--- from a replay session to a live order.
CSSRTradingEngine    g_acct;
CSSRStatsEngine      g_stats;
CSSRJournal          g_journal;

string g_origin      = "";
long  g_replay_chart = 0;
ulong g_last_pump_us = 0;
int   g_slow_tick    = 0;
bool  g_ready        = false;

//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Parse "M15,H1" into timeframes, ignoring anything unusable.      |
//+------------------------------------------------------------------+
int ParseTimeframes(const string csv, ENUM_TIMEFRAMES &out[])
  {
   ArrayResize(out, 0);
   if(csv == "")
      return 0;
   string parts[];
   int n = StringSplit(csv, StringGetCharacter(",", 0), parts);
   for(int i = 0; i < n; i++)
     {
      string t = parts[i];
      StringTrimLeft(t); StringTrimRight(t); StringToUpper(t);
      ENUM_TIMEFRAMES tf = PERIOD_CURRENT;
      if(t == "M1")  tf = PERIOD_M1;   else if(t == "M5")  tf = PERIOD_M5;
      else if(t == "M15") tf = PERIOD_M15; else if(t == "M30") tf = PERIOD_M30;
      else if(t == "H1")  tf = PERIOD_H1;  else if(t == "H4")  tf = PERIOD_H4;
      else if(t == "D1")  tf = PERIOD_D1;
      else continue;
      int k = ArraySize(out);
      ArrayResize(out, k + 1);
      out[k] = tf;
     }
   return ArraySize(out);
  }

//+------------------------------------------------------------------+
//| Fill the market view with the history a jump skipped over.       |
//|                                                                  |
//| Bounded on purpose: the view holds a fixed number of M1 bars, so |
//| reading more would be work thrown away. And the upper bound is   |
//| the CLOCK, never the window - Prime trims to it as well, but     |
//| asking for the future and relying on the trim would be the host  |
//| leaning on somebody else's guard.                                |
//+------------------------------------------------------------------+
void PrimeView(void)
  {
   CSSRBarProvider *bp = g_src.Bars();
   if(bp == NULL)
      return;
   long now  = g_ctrl.Now();
   long from = now - (long)g_view.Capacity() * SSR_MSC_PER_MIN;
   if(from < g_ctrl.StartMsc())
      from = g_ctrl.StartMsc();

   MqlRates bars[];
   int n = bp.ReadBars(g_origin, from, now, bars);
   if(n <= 0)
      return;
   int taken = g_view.Prime(bars, n, now);
   PrintFormat("[host] view primed with %d bars to %s",
               taken, SSRFormatMsc(now));
  }

//+------------------------------------------------------------------+
//| The settings a session file carries, gathered in ONE place.      |
//|                                                                  |
//| Built by a function rather than inline at the save site, because |
//| a field added to the struct and forgotten here would be a        |
//| setting that silently resets every time a session is resumed.    |
//+------------------------------------------------------------------+
void CollectSettings(SSRSessionSettings &out)
  {
   out.Init();
   out.seed          = g_picker.Seed();
   out.blind         = (int)InpBlind;
   out.pause_flags   = g_autopause.Flags();
   out.session_mode  = (int)InpPauseSession;
   out.slot          = InpSlot;
   out.ticks_per_bar = InpTicksPerBar;
   out.spread_points = InpSpreadPoints;
   out.chart_tf      = InpChartTf;
  }

//+------------------------------------------------------------------+
//| Build a stream per extra symbol, over the SAME window.           |
//|                                                                  |
//| A stream that cannot be built is reported and skipped, not made  |
//| fatal: three instruments out of four is still a usable desk, and |
//| refusing to start at all because gold has a shorter history than |
//| the euro would be the tool overruling the user.                  |
//+------------------------------------------------------------------+
int OpenExtraStreams(const long win_start, const long win_end,
                     const ENUM_TIMEFRAMES &extra_tfs[], const int n_tfs,
                     const string &from_session[], const int n_session)
  {
   string want[];
   int    n = 0;

   //--- a session being resumed names its own instruments. Its first
   //--- entry is the primary stream, which is already open, so it is
   //--- skipped by the same test that skips a duplicate in the inputs.
   if(n_session > 0)
     {
      ArrayResize(want, n_session);
      for(int i = 0; i < n_session; i++)
         want[i] = from_session[i];
      n = n_session;
     }
   else
     {
      if(InpAlsoSymbols == "")
         return 0;
      n = StringSplit(InpAlsoSymbols, StringGetCharacter(",", 0), want);
     }

   int built = 0;

   for(int i = 0; i < n && built < SSR_EXTRA_STREAMS; i++)
     {
      string sym = want[i];
      StringTrimLeft(sym); StringTrimRight(sym);
      if(sym == "" || sym == g_origin)
         continue;

      //--- Two different failures used to print the same sentence. A
      //--- name that is not at this broker at all (a typo, or a symbol
      //--- whose real name carries a suffix) is not the same as one
      //--- that exists but has no M1 - and "no M1 history" sent the
      //--- reader looking in the wrong place.
      if(!SymbolSelect(sym, true))
        {
         PrintFormat("[host] %s skipped: this broker has no symbol by that name "
                     "- check Market Watch for its exact spelling", sym);
         continue;
        }

      if(!g_src2[built].Open(sym))
        { PrintFormat("[host] %s skipped: no M1 history", sym); continue; }

      int    digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
      double point  = SymbolInfoDouble(sym, SYMBOL_POINT);
      if(point <= 0.0) point = MathPow(10, -digits);

      //--- a slot of its own, or two streams would write into one
      //--- custom symbol and each would see the other's prices
      g_sink2[built].SetSlot(InpSlot + 1 + built);
      g_sink2[built].SetAnonymous(g_blind.Anonymous());

      g_ctrl2[built].SetLog(GetPointer(g_ssr_log));
      g_ctrl2[built].SetSymbolSpec(digits, point);
      g_ctrl2[built].SetSpreadPoints(InpSpreadPoints);
      g_ctrl2[built].SetTicksPerBar(InpTicksPerBar);
      g_ctrl2[built].SetWarmupBars(InpWarmupBars);
      g_ctrl2[built].SetDataMode(SSR_DATA_BROKER);
      g_ctrl2[built].Attach(GetPointer(g_src2[built]), GetPointer(g_sink2[built]));

      if(!g_ctrl2[built].Load(sym, win_start, win_end))
        {
         PrintFormat("[host] %s skipped: %s", sym,
                     g_ctrl2[built].LastErrorText());
         g_ctrl2[built].Release();
         continue;
        }

      g_charts2[built].Configure(g_sink2[built].ReplaySymbol(), sym);
      g_charts2[built].OpenChart(InpChartTf);
      if(n_tfs > 0)
         g_charts2[built].OpenLayout(extra_tfs, n_tfs);

      if(!g_group.Add(GetPointer(g_ctrl2[built])))
        { Print("[host] group refused a stream: ", g_group.LastError()); break; }

      PrintFormat("[host] stream %d: %s -> %s", built + 1, sym,
                  g_sink2[built].ReplaySymbol());
      built++;
     }
   return built;
  }

//+------------------------------------------------------------------+
int OnInit()
  {
   string origin = (InpSymbol == "" ? _Symbol : InpSymbol);
   g_origin = origin;
   Print("[host] SS Replay build ", SSR_BUILD);
   g_ssr_log.SetTag("host");
   g_ssr_log.SetLevel(SSR_LOG_INFO);

   //--- BLIND MODE IS DECIDED FIRST. The replay symbol's name is fixed
   //--- when the symbol is created, so anonymising it later is not an
   //--- option - and the name is the one leak no chart property closes.
   SSRBlindPolicy blind;
   blind.Apply(InpBlind);
   g_blind.SetPolicy(blind);
   g_sink.SetAnonymous(blind.anonymous_symbol);

   if(!g_src.Open(origin))
     {
      Print("[host] no M1 history for ", origin);
      return INIT_FAILED;
     }

   SSRDataRange range;
   range.Init();
   g_src.RangeInto(range);

   //--- RANDOM REPLAY. Decided here because it decides the window, and
   //--- the seed is printed because a session you cannot return to is
   //--- one you cannot learn from.
   long random_start = SSR_INVALID_TIME;
   if(InpRandom)
     {
      g_catalog.Attach(g_src.History());
      g_picker.Attach(GetPointer(g_catalog));
      g_picker.SetSeed(SSRSeedFromText(InpSeed));
      g_picker.AddSymbolList(InpAlsoSymbols);
      g_picker.AddSymbol(origin);

      if(g_picker.Pick(InpWarmupBars, InpReplayBars, origin))
        {
         random_start = g_picker.PickedStart();
         //--- the picker may have chosen a DIFFERENT instrument, and
         //--- the whole session has to follow it
         if(g_picker.PickedSymbol() != origin)
           {
            origin   = g_picker.PickedSymbol();
            g_origin = origin;
            if(!g_src.Open(origin))
              {
               Print("[host] random pick has no history: ", origin);
               return INIT_FAILED;
              }
            range.Init();
            g_src.RangeInto(range);
           }
         PrintFormat("[host] random session - %s", g_picker.Ticket());
        }
      else
         Print("[host] random pick failed, using the normal window: ",
               g_picker.LastError());
     }

   //--- A RESUMED SESSION USES THE WINDOW IT WAS SAVED WITH. Loading
   //--- the account into a different window would put every trade
   //--- outside it, and the engine would refuse the restore for a
   //--- reason that looks like a bug in the file.
   bool resuming = (InpSession != "" && InpResume &&
                    g_session_mgr.Exists(InpSession));
   long saved_start = SSR_INVALID_TIME, saved_end = SSR_INVALID_TIME;
   if(resuming && !g_session_mgr.ReadWindow(InpSession, 0, saved_start, saved_end))
     {
      Print("[host] session file unreadable, starting fresh: ",
            g_session_mgr.LastError());
      resuming = false;
     }

   //--- pick a window. Auto lands near the end of what the broker has,
   //--- leaving room for the warmup the higher timeframes need.
   long win_end   = range.last_msc;
   long win_start = (random_start > 0 ? random_start
                     : (InpStart > 0 ? SSRToMsc(InpStart)
                                     : win_end - (long)InpReplayBars * SSR_MSC_PER_MIN));
   long floor_msc = range.first_msc + (long)InpWarmupBars * SSR_MSC_PER_MIN;
   if(win_start < floor_msc)
      win_start = floor_msc;

   //--- SAY IT WHEN THE WINDOW HAD TO SHRINK.
   //---
   //--- A user who asks for 2,000 replay bars behind 1,000 of warmup
   //--- and gets a day and a half is entitled to know. The engine
   //--- clamps to local history and carries on, which is the right
   //--- behaviour - but it used to carry on QUIETLY, and a line that
   //--- reads "warmup seeded: 939 bars" looks like success unless you
   //--- happen to remember you asked for 1,000.
   //---
   //--- And the terminal usually knows there is more: SERIES_SERVER_-
   //--- FIRSTDATE said 2020 on a symbol whose local history began two
   //--- days ago. Silently replaying 0.1% of what the broker holds is
   //--- the difference between a limitation and a trap.
   long want_bars  = (long)InpReplayBars + (long)InpWarmupBars;
   long have_bars  = (win_end - range.first_msc) / SSR_MSC_PER_MIN;
   if(!resuming && have_bars < want_bars)
     {
      PrintFormat("[host] SHORT ON HISTORY: asked for %d replay + %d warmup "
                  "= %d M1 bars, this terminal holds %d (from %s)",
                  InpReplayBars, InpWarmupBars, (int)want_bars,
                  (int)have_bars, SSRFormatMsc(range.first_msc));

      if(range.CanExtendBackwards())
         PrintFormat("[host] the broker HAS more - back to %s. "
                     "Open an M1 chart of %s and scroll left, or press Home, "
                     "to download it, then reload this EA.",
                     SSRFormatMsc(range.server_first_msc), origin);
      else
         Print("[host] and the broker has no more either - this is all there is.");
     }

   if(resuming)
     {
      win_start = saved_start;
      win_end   = saved_end;
      PrintFormat("[host] resuming \"%s\": %s .. %s", InpSession,
                  SSRFormatMsc(win_start), SSRFormatMsc(win_end));
     }
   if(win_start >= win_end)
     {
      PrintFormat("[host] not enough history: %s .. %s",
                  SSRFormatMsc(range.first_msc), SSRFormatMsc(range.last_msc));
      return INIT_FAILED;
     }

   int    digits = (int)SymbolInfoInteger(origin, SYMBOL_DIGITS);
   double point  = SymbolInfoDouble(origin, SYMBOL_POINT);
   if(point <= 0.0) point = MathPow(10, -digits);

   g_sink.SetSlot(InpSlot);
   g_ctrl.SetLog(GetPointer(g_ssr_log));
   g_ctrl.SetSymbolSpec(digits, point);
   g_ctrl.SetSpreadPoints(InpSpreadPoints);
   g_ctrl.SetTicksPerBar(InpTicksPerBar);
   g_ctrl.SetWarmupBars(InpWarmupBars);
   g_ctrl.SetDataMode(SSR_DATA_BROKER);
   //--- real ticks when the broker has them, synthetic otherwise. The
   //--- engine degrades on its own and the panel shows which is in use.
   g_ctrl.SetFidelity(range.has_ticks ? SSR_FIDELITY_FULL_TICK
                                      : SSR_FIDELITY_SYNTHETIC_TICK);
   g_ctrl.Attach(GetPointer(g_src), GetPointer(g_sink));

   //--- the execution model, declared before the session opens so the
   //--- first trade is priced under the same assumptions as the last
   SSRExecutionModel exec;
   exec.Init();
   exec.commission_per_lot = InpCommission;
   exec.slippage_points    = InpSlippage;
   exec.swap_long_per_lot  = InpSwapLong;
   exec.swap_short_per_lot = InpSwapShort;
   exec.use_real_spread    = true;
   g_acct.SetExecution(exec);
   g_acct.SetBalance(InpBalance);
   g_acct.SetMarginPerLot(InpMarginLot);
   g_acct.SetStopoutLevel(InpStopout);

   //--- ORDER MATTERS, twice over. The account must see a tick before
   //--- the statistics sample the equity it produces, and the auto
   //--- pause must look at the account only after the account has
   //--- acted on that same tick.
   g_ctrl.AddObserver(GetPointer(g_acct));
   g_ctrl.AddObserver(GetPointer(g_stats));

   g_autopause.Attach(GetPointer(g_acct));
   g_autopause.SetFlags(SSR_PAUSE_ON_NONE);
   g_autopause.Enable(SSR_PAUSE_ON_ENTRY,   InpPauseEntry);
   g_autopause.Enable(SSR_PAUSE_ON_SL,      InpPauseSL);
   g_autopause.Enable(SSR_PAUSE_ON_TP,      InpPauseTP);
   g_autopause.Enable(SSR_PAUSE_ON_STOPOUT, InpPauseSL);
   g_ctrl.AddObserver(GetPointer(g_autopause));

   //--- what counts as a new session is READ from the instrument, not
   //--- assumed from the clock
   g_session.SetMode(InpPauseSession);
   g_session.LearnFrom(origin);
   g_ctrl.AddObserver(GetPointer(g_session));

   //--- THE VIEW BEFORE THE STRATEGIES. By the time a strategy is
   //--- asked what it thinks about a bar, the view must already hold
   //--- it - and it must hold nothing beyond it.
   g_ctrl.AddObserver(GetPointer(g_view));
   g_strategies.Attach(GetPointer(g_view), GetPointer(g_acct));
   g_strategies.SetSeed(InpRandom ? g_picker.Seed() : 1);
   if(InpRefStrategy)
     {
      g_ref_strategy.Configure(InpStratTf, InpStratLookback, InpStratRisk);
      if(g_strategies.Add(GetPointer(g_ref_strategy), InpStratTf))
         Print("[host] strategy: ", g_ref_strategy.Name(),
               " on ", EnumToString(InpStratTf));
      else
         Print("[host] strategy refused: ", g_strategies.LastError());
     }
   g_ctrl.AddObserver(GetPointer(g_strategies));
   g_stats.Attach(GetPointer(g_acct));
   g_journal.Attach(GetPointer(g_acct), GetPointer(g_stats));

   if(!g_ctrl.Load(origin, win_start, win_end))
     {
      Print("[host] load failed: ", g_ctrl.LastErrorText());
      return INIT_FAILED;
     }

   string rsym = g_sink.ReplaySymbol();
   g_charts.Configure(rsym, origin);
   g_replay_chart = g_charts.OpenChart(InpChartTf);

   //--- the stop and target belong on the chart the user is watching,
   //--- not in a stepper. They are armed later, once a price exists.
   if(InpTradeLines && g_replay_chart != 0)
      g_lines.Attach(g_replay_chart, digits, point,
                     clrTomato, clrMediumSeaGreen);

   //--- MULTI TIMEFRAME COSTS NOTHING. The engine writes M1 into a
   //--- custom symbol and MetaTrader derives H1 from it; an extra
   //--- chart is an extra chart, not an extra code path.
   ENUM_TIMEFRAMES extra_tfs[];
   int n_tfs = ParseTimeframes(InpExtraTfs, extra_tfs);
   if(n_tfs > 0)
      PrintFormat("[host] opened %d extra chart(s)",
                  g_charts.OpenLayout(extra_tfs, n_tfs));
   g_charts.ScanLeaks();

   //--- MULTI SYMBOL. Every extra instrument is a full stream of its
   //--- own; the group is what keeps them on one clock.
   //---
   //--- WHEN A SESSION IS BEING RESUMED, THE FILE DECIDES which
   //--- symbols those are - not the inputs. A saved three-instrument
   //--- board that came back with whatever InpAlsoSymbols happened to
   //--- say would be a different board wearing the same name, and the
   //--- account restored into it would hold trades on charts that are
   //--- no longer there.
   g_group.Add(GetPointer(g_ctrl));
   string want_syms[];
   int    n_want = 0;
   if(resuming)
      n_want = g_session_mgr.ReadSymbols(InpSession, want_syms);
   g_extra = OpenExtraStreams(win_start, win_end, extra_tfs, n_tfs,
                              want_syms, n_want);

   if(!g_group.Align())
     {
      Print("[host] streams will not align: ", g_group.LastError());
      return INIT_FAILED;
     }

   //--- THE PANEL TALKS TO THE GROUP, never to one stream. A transport
   //--- command that reached only the primary chart would leave the
   //--- rest of the board behind - synchronised right up until the
   //--- moment the user touched it.
   g_gport.Attach(GetPointer(g_group), GetPointer(g_sink), GetPointer(g_charts));
   //--- and everything the panel may SHOW or DRIVE, handed over one by
   //--- one so the port offers only what this host actually has
   g_gport.AttachBlind(GetPointer(g_blind));
   g_gport.AttachAccount(GetPointer(g_acct));
   g_gport.AttachStats(GetPointer(g_stats));
   g_gport.AttachStrategies(GetPointer(g_strategies));
   g_gport.AttachSessions(GetPointer(g_session_mgr));
   g_gport.SetRiskPercent(InpRiskPercent);
   if(InpTradeLines)
      g_gport.AttachLines(GetPointer(g_lines));

   //--- other products may now see this session. The symbol they are
   //--- told about is the REPLAY symbol, because that is the one a
   //--- client is looking at on its chart.
   if(InpPublish)
     {
      g_publisher.Attach(GetPointer(g_group), GetPointer(g_acct));
      g_publisher.SetSlot(InpSlot);
      g_publisher.SetSymbol(rsym);
      g_publisher.SetPermissions(InpAllowControl, InpAllowTrade);
      if(g_publisher.Begin())
         Print("[host] ", g_publisher.ToString());

      //--- ONE PUBLISHER PER STREAM. A product watching the second
      //--- instrument would otherwise be told about the first, and
      //--- would show a clock that belongs to a chart it is not on.
      //--- The account travels with the primary only, because that is
      //--- where it actually is.
      for(int i = 0; i < g_extra; i++)
        {
         g_publisher2[i].Attach(GetPointer(g_group), NULL);
         g_publisher2[i].SetSlot(InpSlot + 1 + i);
         g_publisher2[i].SetSymbol(g_sink2[i].ReplaySymbol());
         g_publisher2[i].SetPermissions(InpAllowControl, false);
         g_publisher2[i].Begin();
        }
     }

   //--- and blind mode goes on every chart we own, remembering what
   //--- each looked like so the user can leave the mode again
   if(g_blind.IsOn())
     {
      long ids[];
      int  n = g_charts.OwnedIds(ids);
      for(int i = 0; i < n; i++)
         g_blind.Apply(ids[i]);
      for(int st = 0; st < g_extra; st++)
        {
         long ids2[];
         int  n2 = g_charts2[st].OwnedIds(ids2);
         for(int i = 0; i < n2; i++)
            g_blind.Apply(ids2[i]);
        }
      Print("[host] ", g_blind.ToString());
      Print("[host] ", g_blind.Leaks());
     }

   //--- the catalogue quotes the NEXT session from what this one just
   //--- measured, so the estimate stops being a constant after one run
   g_catalog.Attach(g_src.History());
   g_catalog.Scan(origin);
   g_dialog.Create(ChartID(), GetPointer(g_catalog));
   g_session_dlg.Create(ChartID(), GetPointer(g_gport));

   //--- The panel MUST live on this EA's own chart. MetaTrader delivers
   //--- OnChartEvent only for the chart a program is attached to, so a
   //--- panel drawn on the replay chart would render perfectly and
   //--- respond to nothing. The replay chart is opened separately.
   g_panel.Create(ChartID(), GetPointer(g_gport));

   //--- A SAVED SESSION, if one was named and exists. This restores
   //--- the account and every trade in it, not just the position -
   //--- and it reports anything it could not put back exactly.
   g_session_mgr.Attach(GetPointer(g_group), GetPointer(g_acct),
                        GetPointer(g_stats));
   if(resuming)
     {
      if(g_session_mgr.Restore(InpSession))
        {
         g_resumed = true;
         Print("[host] ", g_session_mgr.ResumeReport());
        }
      else
         Print("[host] could not resume: ", g_session_mgr.LastError());
     }

   //--- otherwise a position saved by a previous run lands the user
   //--- where they stopped rather than at the start of the window.
   //---
   //--- NOT after a random pick. A random session that resumes where
   //--- the last one stopped is not a random session, and the whole
   //--- point was to arrive somewhere the trader does not recognise.
   SSRSnapshot saved;
   if(!g_resumed && random_start <= 0 &&
      g_ctrl.PeekPosition(origin, saved) &&
      saved.taken_at_msc > win_start && saved.taken_at_msc < win_end)
     {
      //--- through the GROUP, so every chart resumes together
      if(g_group.JumpTo(saved.taken_at_msc))
         PrintFormat("[host] resumed at %s", SSRFormatMsc(saved.taken_at_msc));
     }

   EventSetMillisecondTimer(InpPumpMs);
   g_last_pump_us = GetMicrosecondCount();
   g_ready = true;

   PrintFormat("[host] ready  %s -> %s  %s .. %s",
               origin, rsym, SSRFormatMsc(win_start), SSRFormatMsc(win_end));
   //--- NAME THE CHART THAT OWNS THE KEYBOARD.
   //--- The candles are on one chart and the controls on another, and a
   //--- user reasonably presses keys where the candles are. There they
   //--- do nothing: MetaTrader delivers key events only to the chart a
   //--- program is attached to. Saying which one costs a line.
   PrintFormat("[host] the keyboard and the panel are on the %s chart - "
               "click it first. The replay chart is for watching.", _Symbol);
   Print("[host] ", SSRKeyHint());
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();

   //--- WITHDRAWN FIRST, and on every deinit reason. Terminal globals
   //--- outlive the program that set them, so leaving them behind
   //--- would tell every other product that a replay is still running.
   g_publisher.Withdraw();
   for(int i = 0; i < g_extra; i++)
      g_publisher2[i].Withdraw();

   g_session_dlg.Destroy();
   g_panel.Destroy();
   //--- the lines are ours, and a chart handed back with two stray
   //--- horizontal lines on it is a chart we did not clean up
   g_lines.Clear();

   //--- REASON_CHARTCHANGE and friends destroy this EA and rebuild it.
   //--- Tearing the replay symbol down on every one of those would
   //--- discard the whole session, so the symbol only goes when the
   //--- user actually removed the tool.
   //--- save where the user got to, whatever the reason. A chart change
   //--- that rebuilds this EA would otherwise drop them back at the
   //--- start of the window, which is the limitation this host carries.
   if(g_ready)
     {
      //--- THE WHOLE SESSION, on every deinit reason. A chart change
      //--- that rebuilds this EA must not cost the user their trades,
      //--- and by the time we know why we are closing it is too late
      //--- to go back for them.
      if(InpSession != "")
        {
         SSRSessionSettings set;
         CollectSettings(set);
         if(g_session_mgr.Save(InpSession, set))
            Print("[host] session saved -> ", g_session_mgr.LastPath());
         else
            Print("[host] session NOT saved: ", g_session_mgr.LastError());
        }

      g_ctrl.SavePosition();
      for(int i = 0; i < g_extra; i++)
         g_ctrl2[i].SavePosition();
     }

   g_dialog.Destroy();

   bool user_removed = (reason == REASON_REMOVE || reason == REASON_PROGRAM ||
                        reason == REASON_CLOSE);
   if(user_removed)
     {
      //--- a session's results are worth nothing if they die with the
      //--- chart. Summary to the log, detail to a file, both carrying
      //--- the caveat that says what the numbers rest on.
      if(g_journal.Count() > 0)
        {
         Print("[host] ", g_journal.Summary());
         if(g_strategies.Count() > 0)
           {
            g_strategies.StopAll();
            Print("[host] ", g_strategies.Report(GetPointer(g_stats)));
           }
         string stamp = TimeToString(TimeLocal(), TIME_DATE);
         StringReplace(stamp, ".", "");
         if(g_journal.ExportCsv(g_origin + "_" + stamp))
            Print("[host] journal -> ", g_journal.LastPath());
         else
            Print("[host] journal export failed: ", g_journal.LastError());
        }
      //--- a mode the user cannot leave is a trap: every chart goes
      //--- back to the settings it had before we touched it
      g_blind.RestoreAll();

      g_charts.CloseOwned();
      g_ctrl.Release();
      for(int i = 0; i < g_extra; i++)
        {
         g_charts2[i].CloseOwned();
         g_ctrl2[i].Release();
        }
      g_group.Clear();
      g_extra = 0;
     }
   g_ready = false;
  }

//+------------------------------------------------------------------+
//| The pump. Real elapsed time in, replay time out.                 |
//+------------------------------------------------------------------+
void OnTimer()
  {
   if(!g_ready)
      return;

   ulong now   = GetMicrosecondCount();
   ulong delta = (now - g_last_pump_us) / 1000;
   g_last_pump_us = now;

   //--- a stalled terminal must not be replayed as a giant jump: the
   //--- engine would try to emit minutes of ticks in one call
   if(delta > 1000)
      delta = 1000;

   //--- ONE PUMP FOR THE BOARD. The group takes the wall delta and
   //--- hands every stream an instant, so there is nothing to drift.
   if(g_group.AnyPlaying())
      g_group.Pump(delta);

   //--- A JUMP WRITES ITS BARS IN BULK and publishes none of them, so
   //--- the view is empty on the far side of one. Priming is the
   //--- host's job because the host is what owns a data source.
   if(g_strategies.Count() > 0 && g_view.M1Count() == 0 &&
      g_ctrl.Now() > g_ctrl.StartMsc())
      PrimeView();

   //--- one command per pump at most, so a client cannot drive the
   //--- replay faster than the person watching it can react
   g_publisher.Poll();
   for(int i = 0; i < g_extra; i++)
      g_publisher2[i].Poll();

   //--- chart housekeeping is cheap but not free; keep it off the hot path
   g_slow_tick++;
   if(g_slow_tick % 5 == 0)
     {
      //--- the heartbeat rides with the chart housekeeping: often
      //--- enough that a client never sees a live session as stale,
      //--- rarely enough that it is not on the hot path
      g_publisher.Publish();
      for(int i = 0; i < g_extra; i++)
         g_publisher2[i].Publish();
      g_charts.Sync();
      for(int i = 0; i < g_extra; i++)
         g_charts2[i].Sync();
     }
   if(g_slow_tick % 50 == 0)
     {
      g_charts.ScanLeaks();
      //--- feed the measured seed rate back so the next session's cost
      //--- quote comes from this machine rather than from a constant
      if(g_ctrl.SeedBarsPerSec() > 0.0)
         g_catalog.SetMeasuredSeedRate(g_ctrl.SeedBarsPerSec());
     }

   //+------------------------------------------------------------------+
   //| THE STOP LINE, READ RATHER THAN LISTENED FOR.                    |
   //|                                                                  |
   //| The lines are on the replay chart and this EA is on the host, so |
   //| no drag event can ever arrive. Asking them where they are, once  |
   //| a tick, needs no events at all - and a dragged object updates    |
   //| its own price whether anyone was listening or not.               |
   //|                                                                  |
   //| The distance is recomputed against the live price every pass,    |
   //| so the lot size tracks both the line and the market.             |
   //+------------------------------------------------------------------+
   if(InpTradeLines && g_replay_chart != 0)
     {
      double px = g_acct.Bid();
      if(px > 0.0)
        {
         if(!g_lines.IsArmed())
           {
            double def_pts = (InpStopPoints > 0.0 ? InpStopPoints
                                                  : InpSpreadPoints * 10.0);
            if(g_lines.Arm(px, def_pts, InpRR))
               PrintFormat("[host] stop and target lines placed on %s - "
                           "drag them; the lot size follows the stop",
                           g_sink.ReplaySymbol());
           }
         else
           {
            g_lines.Poll();
            double pts = g_lines.StopPointsFrom(px);
            if(pts > 0.0)
              {
               g_gport.SetStopPoints(pts);
               g_gport.SetTpPoints(g_lines.RewardRatio(px) * pts);
              }

            //--- and every OPEN trade, on the chart, the way the
            //--- platform draws a real one. A virtual position that
            //--- lives only as a number in a panel asks the user to
            //--- carry it in their head; the point of practising on a
            //--- chart is to read it off the chart.
            g_lines.BeginPositions();
            for(int pi = 0; pi < g_acct.Total(); pi++)
              {
               SSRVirtualPosition vp;
               if(!g_acct.At(pi, vp) || vp.state != SSR_POS_OPEN)
                  continue;
               g_lines.DrawPosition(vp.ticket, vp.open_price, vp.sl, vp.tp,
                                    SSRIsLong(vp.type), vp.volume);
              }
            g_lines.EndPositions();
           }
        }
     }

   g_panel.Render();
  }

//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam,
                  const double &dparam, const string &sparam)
  {
   if(!g_ready)
      return;

   //+------------------------------------------------------------------+
   //| TRACE THE ROUTE, BECAUSE GUESSING IT COST TWO ROUNDS.            |
   //|                                                                  |
   //| J still does nothing. The panel passes it on - it prints no line |
   //| - and the host's branch calls Open() on a dialog that draws and  |
   //| now repaints. Two theories tested, one wrong. So instead of a    |
   //| third, every key says which layer took it. One run, one answer.  |
   //+------------------------------------------------------------------+
   if(id == CHARTEVENT_KEYDOWN)
     {
      ENUM_SSR_CMD kc = SSRKeyToCommand(lparam);
      PrintFormat("[route] key vk=%d -> %s | sessdlg=%s rangedlg=%s",
                  (int)lparam, SSRCmdName(kc),
                  (g_session_dlg.IsOpen() ? "OPEN" : "closed"),
                  (g_dialog.IsOpen() ? "OPEN" : "closed"));
     }

   //--- the session list is modal over everything, so it looks first
   if(g_session_dlg.IsOpen())
     {
      if(g_session_dlg.OnEvent(id, lparam, dparam, sparam))
        {
         g_panel.Render();
         return;
        }
     }

   //--- the range dialog is modal over the panel, so it looks next
   if(g_dialog.IsOpen())
     {
      if(g_dialog.OnEvent(id, lparam, dparam, sparam))
        {
         if(g_dialog.IsConfirmed())
           {
            SSRSessionRange r;
            g_dialog.RequestInto(r);
            //--- a confirmed range is a JUMP within the loaded session
            //--- when it fits, and otherwise needs a reload the host
            //--- cannot do without tearing the symbol down
            if(r.start_msc >= g_group.StartMsc() && r.start_msc < g_group.EndMsc())
               g_group.JumpTo(r.start_msc);
            else
               Print("[host] that range needs a fresh session - reattach with new inputs");
           }
         g_panel.Render();
         return;
        }
     }

   if(g_panel.OnEvent(id, lparam, dparam, sparam))
      return;

   //--- S opens the saved-session list. The host owns it because the
   //--- dialog needs the session manager, which knows every layer.
   if(id == CHARTEVENT_KEYDOWN && SSRKeyToCommand(lparam) == SSR_CMD_SESSIONS)
     {
      g_session_dlg.Open();
      return;
     }

   //--- J opens the range dialog; the panel maps the key, the host owns
   //--- the dialog because the dialog needs the catalogue
   if(id == CHARTEVENT_KEYDOWN && SSRKeyToCommand(lparam) == SSR_CMD_JUMP)
     {
      SSRSessionRange r;
      r.Init();
      r.origin    = (InpSymbol == "" ? _Symbol : InpSymbol);
      r.start_msc = g_group.Now();
      r.end_msc   = g_group.EndMsc();
      g_dialog.Open(r);
      PrintFormat("[route] range dialog opened: is_open=%s catalog=%s "
                  "seed=%s..%s problem=\"%s\"",
                  (g_dialog.IsOpen() ? "yes" : "NO"),
                  (g_catalog.Available() ? "available" : "NOT AVAILABLE"),
                  SSRFormatMsc(r.start_msc), SSRFormatMsc(r.end_msc),
                  g_dialog.Problem());
      return;
     }

   //--- "Replay From Here" still needs events from the REPLAY chart,
   //--- which this EA cannot receive. It arrives with the indicator
   //--- panel, which lives on that chart itself.
  }

//+------------------------------------------------------------------+
//| The host is attached to a chart, so MetaTrader delivers ticks    |
//| here too. The engine is driven by the timer, not by them.        |
//+------------------------------------------------------------------+
void OnTick() {}
//+------------------------------------------------------------------+
