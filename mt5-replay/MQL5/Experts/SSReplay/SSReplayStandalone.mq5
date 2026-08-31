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
//--- 1x means ONE M5 CANDLE EVERY FIVE REAL MINUTES. Pressing Play and
//--- watching nothing happen for twenty seconds is not a slow replay,
//--- it is a broken-looking one - and it was the default. 30x puts a
//--- new M5 candle on screen every ten seconds, which reads as alive.
input double          InpStartSpeed = 30.0;                 // Speed when it starts (1 = real time)

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
input bool            InpAutoHistory = true;                 // Download M1 history for this symbol on start
input int             InpHistoryBars = 60000;                // How many M1 bars to have available (~6 weeks)
input bool            InpPickStart   = true;                 // Pick the start by dragging a line on the chart
input bool            InpOneChart    = true;                 // Turn THIS chart into the replay chart (one window)
input bool            InpTradeLines  = true;                 // Draw draggable stop/target lines
input double          InpStopPoints  = 0;                    // Default stop, in points (0 = 10x the spread)
input double          InpRR          = 2.0;                  // Target distance, as a multiple of the stop
input bool            InpVitals      = true;                 // Print one diagnostic line a second to the Experts log

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
long  g_panel_chart  = 0;      // where the panel and dialogs actually are
uint  g_panel_paint  = 0;      // last panel repaint, for the UI throttle
bool  g_on_replay_chart = false;   // is THIS chart the replay chart?
bool  g_switching       = false;   // the handover is under way
bool  g_picking         = false;   // waiting for the user to place the start line

//--- declared before they are called, so the compiler never has to guess.
//--- RunHostCommand was called from OnTimer NINETEEN LINES before its
//--- definition and its old prototype sat below both - a prototype that
//--- comes after the call is not a prototype, it is a comment.
void RunHostCommand(const ENUM_SSR_CMD cmd);
void RouteEvent(const int id, const long &lparam,
                const double &dparam, const string &sparam);
long  g_pick_msc        = SSR_INVALID_TIME;
string g_switch_to      = "";      // ...to this symbol, on the first tick
ulong g_last_pump_us = 0;
int   g_slow_tick    = 0;
bool  g_ready        = false;
bool  g_was_playing  = false;      // to notice the moment Play is pressed

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
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| THE ORIGIN SYMBOL, ACROSS A RESTART.                             |
//|                                                                  |
//| Changing a chart's symbol destroys this EA and builds it again,  |
//| and on the second pass _Symbol is the replay symbol - the origin |
//| is gone. Terminal globals hold only doubles, so the name is left |
//| in a hidden label on our own chart, which survives the symbol    |
//| change because objects belong to the chart, not to the symbol.   |
//+------------------------------------------------------------------+
#define SSR_HANDOFF  "SSR_ORIGIN_HANDOFF"

void StashOrigin(const string origin)
  {
   if(ObjectFind(0, SSR_HANDOFF) < 0)
      ObjectCreate(0, SSR_HANDOFF, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, SSR_HANDOFF, OBJPROP_XDISTANCE, -1000);
   ObjectSetInteger(0, SSR_HANDOFF, OBJPROP_YDISTANCE, -1000);
   ObjectSetInteger(0, SSR_HANDOFF, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, SSR_HANDOFF, OBJPROP_HIDDEN, true);
   ObjectSetString (0, SSR_HANDOFF, OBJPROP_TEXT, origin);
  }

string ReadStashedOrigin(void)
  {
   if(ObjectFind(0, SSR_HANDOFF) < 0)
      return "";
   return ObjectGetString(0, SSR_HANDOFF, OBJPROP_TEXT);
  }

#define SSR_PICK_STASH  "SSR_PICK_HANDOFF"
#define SSR_PICK_LINE   "SSR_PICK_LINE"
#define SSR_PICK_GO     "SSR_PICK_GO"
#define SSR_PICK_INFO   "SSR_PICK_INFO"
#define SSR_PICK_HERE   "SSR_PICK_HERE"

//--- SERIES_FIRSTDATE as a value, for a one-line log
long SeriesInfoIntegerOrZero(const string sym)
  {
   long v = 0;
   SeriesInfoInteger(sym, PERIOD_M1, SERIES_FIRSTDATE, v);
   return v;
  }

//+------------------------------------------------------------------+
//| DOWNLOAD THE M1 HISTORY, INSTEAD OF ASKING THE USER TO.          |
//|                                                                  |
//| Every session so far has been cramped by the four days of M1 the |
//| terminal happened to have cached, and the remedy was a paragraph |
//| of instructions about pressing Home on an M1 chart. A tool that  |
//| needs history should fetch history.                              |
//|                                                                  |
//| MetaTrader pulls history asynchronously: CopyRates on a range it |
//| does not hold starts a download and returns nothing. So this     |
//| asks, waits, and asks again, stopping the moment the broker      |
//| stops giving more - which is a fact about the broker, not a      |
//| failure, and is reported as such.                                |
//+------------------------------------------------------------------+
int EnsureHistory(const string sym, const int want_bars)
  {
   int have = Bars(sym, PERIOD_M1);
   if(have >= want_bars)
     {
      PrintFormat("[host] history: %d M1 bars already local, %d wanted - "
                  "nothing to download", have, want_bars);
      return have;
     }

   PrintFormat("[host] history: %d M1 bars local, downloading up to %d...",
               have, want_bars);

   long first = 0, server_first = 0;
   SeriesInfoInteger(sym, PERIOD_M1, SERIES_SERVER_FIRSTDATE, server_first);

   MqlRates tmp[];
   ulong t0 = GetTickCount();
   int   stalls = 0;
   while(have < want_bars && (GetTickCount() - t0) < 60000 && !IsStopped())
     {
      SeriesInfoInteger(sym, PERIOD_M1, SERIES_FIRSTDATE, first);
      if(first <= 0)
         first = (long)TimeCurrent();

      //--- the broker has nothing older; this is an answer, not an error
      if(server_first > 0 && first <= server_first)
        {
         PrintFormat("[host] history: the broker's earliest M1 bar is %s - "
                     "that is everything it has (%d bars).",
                     TimeToString((datetime)server_first), have);
         return have;
        }

      datetime want_from = (datetime)(first - (long)(want_bars - have) * 60);
      if(server_first > 0 && want_from < (datetime)server_first)
         want_from = (datetime)server_first;

      ResetLastError();
      CopyRates(sym, PERIOD_M1, want_from, (datetime)first, tmp);
      Sleep(300);

      int now_have = Bars(sym, PERIOD_M1);
      if(now_have <= have)
        {
         //--- no progress. Two dead passes means the download is not
         //--- coming, so say how far it got rather than spin for a minute.
         if(++stalls >= 6)
           {
            PrintFormat("[host] history: stopped at %d M1 bars - the download "
                        "stopped progressing. Usually that is all the broker "
                        "serves for this symbol.", now_have);
            return now_have;
           }
        }
      else
        {
         stalls = 0;
         if(now_have / 10000 != have / 10000)
            PrintFormat("[host] history: %d M1 bars...", now_have);
        }
      have = now_have;
     }

   PrintFormat("[host] history: %d M1 bars available, back to %s",
               have, TimeToString((datetime)SeriesInfoIntegerOrZero(sym)));
   return have;
  }

//--- the time at the centre of what the chart is currently showing,
//--- or SSR_INVALID_TIME when the chart cannot answer
long MiddleOfView(void)
  {
   int first = (int)ChartGetInteger(0, CHART_FIRST_VISIBLE_BAR);
   int shown = (int)ChartGetInteger(0, CHART_VISIBLE_BARS);
   if(first <= 0 || shown <= 0)
      return SSR_INVALID_TIME;
   //--- CHART_FIRST_VISIBLE_BAR counts back from the newest bar, so the
   //--- middle of the view is half a screen further back than the edge
   int idx = first - shown / 2;
   if(idx < 0)
      idx = 0;
   datetime t[];
   if(CopyTime(_Symbol, _Period, idx, 1, t) != 1)
      return SSR_INVALID_TIME;
   return (long)t[0] * 1000;
  }

//+------------------------------------------------------------------+
//| PICK THE START BY DRAGGING A LINE, THE WAY SOFT4FX DOES.         |
//|                                                                  |
//| Typing a date into an inputs dialog is not how anyone chooses a  |
//| moment on a chart. This puts a draggable vertical line on the    |
//| REAL symbol's chart - which still has its whole history at this  |
//| point, because the handover has not happened yet - and a button  |
//| next to it. Drag the line to the candle you want to start from,  |
//| press the button, and everything after it ceases to exist.       |
//+------------------------------------------------------------------+
void ShowPicker(const string sym, const long default_msc)
  {
   datetime at = (datetime)(default_msc / 1000);

   ObjectDelete(0, SSR_PICK_LINE);
   ObjectCreate(0, SSR_PICK_LINE, OBJ_VLINE, 0, at, 0);
   ObjectSetInteger(0, SSR_PICK_LINE, OBJPROP_COLOR,      clrOrange);
   ObjectSetInteger(0, SSR_PICK_LINE, OBJPROP_WIDTH,      2);
   ObjectSetInteger(0, SSR_PICK_LINE, OBJPROP_STYLE,      STYLE_SOLID);
   ObjectSetInteger(0, SSR_PICK_LINE, OBJPROP_SELECTABLE, true);
   ObjectSetInteger(0, SSR_PICK_LINE, OBJPROP_SELECTED,   true);
   ObjectSetInteger(0, SSR_PICK_LINE, OBJPROP_BACK,       false);
   ObjectSetString (0, SSR_PICK_LINE, OBJPROP_TEXT,       "SS Replay starts here");

   ObjectDelete(0, SSR_PICK_GO);
   ObjectCreate(0, SSR_PICK_GO, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, SSR_PICK_GO, OBJPROP_CORNER,       CORNER_LEFT_UPPER);
   ObjectSetInteger(0, SSR_PICK_GO, OBJPROP_XDISTANCE,    14);
   ObjectSetInteger(0, SSR_PICK_GO, OBJPROP_YDISTANCE,    26);
   ObjectSetInteger(0, SSR_PICK_GO, OBJPROP_XSIZE,        240);
   ObjectSetInteger(0, SSR_PICK_GO, OBJPROP_YSIZE,        30);
   ObjectSetInteger(0, SSR_PICK_GO, OBJPROP_BGCOLOR,      C'46,139,87');
   ObjectSetInteger(0, SSR_PICK_GO, OBJPROP_BORDER_COLOR, C'34,105,65');
   ObjectSetInteger(0, SSR_PICK_GO, OBJPROP_COLOR,        clrWhite);
   ObjectSetInteger(0, SSR_PICK_GO, OBJPROP_FONTSIZE,     10);
   ObjectSetString (0, SSR_PICK_GO, OBJPROP_FONT,         SSR_FONT);
   ObjectSetString (0, SSR_PICK_GO, OBJPROP_TEXT,         "START REPLAY HERE");
   ObjectSetInteger(0, SSR_PICK_GO, OBJPROP_STATE,        false);
   ObjectSetInteger(0, SSR_PICK_GO, OBJPROP_SELECTABLE,   false);

   ObjectDelete(0, SSR_PICK_INFO);
   ObjectCreate(0, SSR_PICK_INFO, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, SSR_PICK_INFO, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
   ObjectSetInteger(0, SSR_PICK_INFO, OBJPROP_XDISTANCE,  14);
   ObjectSetInteger(0, SSR_PICK_INFO, OBJPROP_YDISTANCE,  62);
   ObjectSetInteger(0, SSR_PICK_INFO, OBJPROP_COLOR,      clrOrange);
   ObjectSetInteger(0, SSR_PICK_INFO, OBJPROP_FONTSIZE,   9);
   ObjectSetInteger(0, SSR_PICK_INFO, OBJPROP_SELECTABLE, false);
   ObjectSetString (0, SSR_PICK_INFO, OBJPROP_FONT,       SSR_FONT);
   ObjectSetString (0, SSR_PICK_INFO, OBJPROP_TEXT,
                    "Drag the orange line to where you want to start");

   //--- SCROLL, THEN SUMMON. The line landing two days back on its own
   //--- was the complaint: a start you have to hunt for is not a start
   //--- you chose. This button drops it in the middle of whatever you
   //--- are looking at, so scrolling IS the choosing.
   ObjectDelete(0, SSR_PICK_HERE);
   ObjectCreate(0, SSR_PICK_HERE, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, SSR_PICK_HERE, OBJPROP_CORNER,       CORNER_LEFT_UPPER);
   ObjectSetInteger(0, SSR_PICK_HERE, OBJPROP_XDISTANCE,    260);
   ObjectSetInteger(0, SSR_PICK_HERE, OBJPROP_YDISTANCE,    26);
   ObjectSetInteger(0, SSR_PICK_HERE, OBJPROP_XSIZE,        118);
   ObjectSetInteger(0, SSR_PICK_HERE, OBJPROP_YSIZE,        30);
   ObjectSetInteger(0, SSR_PICK_HERE, OBJPROP_BGCOLOR,      C'225,225,225');
   ObjectSetInteger(0, SSR_PICK_HERE, OBJPROP_BORDER_COLOR, C'120,120,120');
   ObjectSetInteger(0, SSR_PICK_HERE, OBJPROP_COLOR,        C'20,20,20');
   ObjectSetInteger(0, SSR_PICK_HERE, OBJPROP_FONTSIZE,     9);
   ObjectSetInteger(0, SSR_PICK_HERE, OBJPROP_STATE,        false);
   ObjectSetInteger(0, SSR_PICK_HERE, OBJPROP_SELECTABLE,   false);
   ObjectSetString (0, SSR_PICK_HERE, OBJPROP_FONT,         SSR_FONT);
   ObjectSetString (0, SSR_PICK_HERE, OBJPROP_TEXT, "LINE TO VIEW");

   ChartRedraw(0);
   PrintFormat("[host] PICK A START: drag the orange line on this %s chart to "
               "the candle you want to begin from, then press START REPLAY "
               "HERE. Everything after it will not exist.", sym);
  }

void RemovePicker(void)
  {
   ObjectDelete(0, SSR_PICK_LINE);
   ObjectDelete(0, SSR_PICK_GO);
   ObjectDelete(0, SSR_PICK_INFO);
   ObjectDelete(0, SSR_PICK_HERE);
   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
//| A SECOND PASS THAT FAILS MUST NOT LEAVE THE USER STRANDED.       |
//|                                                                  |
//| When OnInit returns INIT_FAILED MetaTrader unloads the EA. On the |
//| second pass that means a chart sitting on a replay symbol with no |
//| tool on it and no obvious way back - which is exactly what        |
//| happened, and it is the tool's fault, not the user's.             |
//|                                                                  |
//| So a failed second pass puts the chart back on the origin AND     |
//| poisons the handoff, so the next attempt runs in two-window mode  |
//| instead of walking into the same wall again. The poison clears     |
//| itself once read, so a later attempt is free to try once more.     |
//+------------------------------------------------------------------+
int FailInit(void)
  {
   if(g_on_replay_chart && g_origin != "")
     {
      StashOrigin("!" + g_origin);
      Print("[host] this pass failed on the replay chart. Putting the chart "
            "back on ", g_origin, " and switching one-window mode off for "
            "the next attempt - attach SS Replay again and it will use two "
            "windows.");
      ChartSetSymbolPeriod(ChartID(), g_origin, _Period);
     }
   return INIT_FAILED;
  }

//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| BUILD THE SESSION.                                               |
//|                                                                  |
//| Split out of OnInit for one reason: the start picker finishes in |
//| the TIMER, and the build has to happen from there.                |
//|                                                                  |
//| The first attempt tried to get back into OnInit by calling         |
//| ChartSetSymbolPeriod with the chart's OWN symbol and period,       |
//| assuming that forces a reinitialise. It does not - MetaTrader      |
//| sees nothing to change and does nothing at all. So the green       |
//| button removed the line, killed the timer, and left the user with  |
//| a chart doing nothing: "the orange line goes and nothing comes".   |
//|                                                                  |
//| A restart was never needed. This is the build; whoever has the     |
//| answer calls it.                                                   |
//+------------------------------------------------------------------+
//--- `origin` is NOT const: a random session may pick a different
//--- instrument than the one this chart shows, and the whole build has
//--- to follow it. The extraction that created this signature made it
//--- const without reading what the body does with it.
bool BuildSession(string origin, const bool on_replay,
                  const bool one_chart_ok)
  {
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
               return false;
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

   //+------------------------------------------------------------------+
   //| PICK A WINDOW - IN BARS, NOT MINUTES.                            |
   //|                                                                  |
   //| "end minus 2000 minutes" assumes the minutes exist. Run on a     |
   //| Sunday evening, the broker's last bar is Monday 01:09 and the    |
   //| 2000 minutes behind it are the WEEKEND: the window lands almost  |
   //| entirely inside the gap, the warmup finds 48 bars of Friday      |
   //| tail, and Play plays nothing while every button says ok. That is |
   //| the user's "nothing works" log, line by line.                    |
   //|                                                                  |
   //| Counting BARS back through the series skips gaps by construction:|
   //| 2000 bars ending Monday 01:09 starts mid-Thursday, dense data.   |
   //+------------------------------------------------------------------+
   long win_end   = range.last_msc;
   long auto_start = win_end - (long)InpReplayBars * SSR_MSC_PER_MIN;
   MqlRates back[];
   int got = CopyRates(origin, PERIOD_M1, 0, InpReplayBars, back);
   if(got > 0)
      auto_start = (long)back[0].time * 1000;
   else
      PrintFormat("[host] could not count %d bars back (%d) - falling back "
                  "to minutes, which a weekend gap will make too short",
                  InpReplayBars, GetLastError());

   long win_start = (random_start > 0 ? random_start
                     : (InpStart > 0 ? SSRToMsc(InpStart)
                        : (g_pick_msc != SSR_INVALID_TIME ? g_pick_msc
                                                          : auto_start)));
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
      return false;
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
      return false;
     }

   string rsym = g_sink.ReplaySymbol();
   g_charts.Configure(rsym, origin);
   //--- on the second pass THIS chart already is the replay chart, so
   //--- opening another would be the second window we just removed
   //+------------------------------------------------------------------+
   //| WHICH CHART SHOWS THE REPLAY.                                    |
   //|                                                                  |
   //| Pass 2: this chart IS it. Pass 1 that is about to hand itself    |
   //| over: none - a window opened now would be orphaned by its own    |
   //| restart. Two-window mode: open one.                              |
   //|                                                                  |
   //| The test is one_chart_ok, NOT InpOneChart. They differ exactly   |
   //| when a failed handover poisoned the stash: the input still says  |
   //| one window, the poison says two. Testing the input here left the |
   //| recovery run with NO replay chart at all - no candles, no lines  |
   //| to arm ("sl/tp lines -> refused" in the user's log), while every |
   //| transport button cheerfully worked on a chart showing nothing.   |
   //+------------------------------------------------------------------+
   g_replay_chart = (g_on_replay_chart ? ChartID()
                     : (one_chart_ok ? 0 : g_charts.OpenChart(InpChartTf)));

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
   //--- not on the pass that is about to hand this chart over: charts it
   //--- opened now would be owned by a CSSRChartManager that its own
   //--- restart destroys, and nothing would ever close them
   if(n_tfs > 0 && g_replay_chart != 0)
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
      return false;
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
   //--- the DEFAULT the SL/TP button starts from. Zero leaves it to the
   //--- port, which uses ten times the live spread - an instrument-
   //--- independent distance rather than a number that is sane on one
   //--- symbol and absurd on the next.
   if(InpStopPoints > 0.0)
     {
      g_gport.SetStopPoints(InpStopPoints);
      if(InpRR > 0.0)
         g_gport.SetTpPoints(InpStopPoints * InpRR);
     }
   if(InpTradeLines)
      g_gport.AttachLines(GetPointer(g_lines));
   g_gport.AttachJournal(GetPointer(g_journal));

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
   //+------------------------------------------------------------------+
   //| ONE WINDOW - AND THE PANEL ASKS ITS BUTTONS INSTEAD OF WAITING.  |
   //|                                                                  |
   //| Drawing on another chart was never the obstacle: ObjectCreate    |
   //| takes a chart id. Only EVENTS are chart-local, and the previous  |
   //| build tried to route them across with a forwarding indicator.    |
   //| That could not work and its own log line proved it: an indicator |
   //| created with iCustom and shown by ChartIndicatorAdd keeps the    |
   //| CREATOR's chart context, so it printed "chart X -> host X", the  |
   //| same id twice, and forwarded the host's events to the host.      |
   //|                                                                  |
   //| The panel polls OBJPROP_STATE instead. MetaTrader latches a      |
   //| button down when it is clicked and that latch is readable from   |
   //| any chart - the same reasoning already used for the stop and     |
   //| target lines, which have worked from day one precisely because   |
   //| they ask rather than listen.                                     |
   //|                                                                  |
   //| WHAT THIS COSTS: the KEYBOARD. Keys reach only the chart this    |
   //| program is attached to, and nothing latches them, so there is    |
   //| nothing to poll. Every command has a button, so nothing is out   |
   //| of reach - but the keys work on THIS chart, not the replay one.  |
   //| Said out loud below rather than left to be discovered.           |
   //+------------------------------------------------------------------+
   g_panel_chart = ChartID();

   g_dialog.Create(g_panel_chart, GetPointer(g_catalog));
   g_session_dlg.Create(g_panel_chart, GetPointer(g_gport));
   g_panel.Create(g_panel_chart, GetPointer(g_gport));

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
      //--- ONLY IF THERE IS SOMETHING LEFT TO PLAY THERE. The Sunday
      //--- session saved its position at the edge of the weekend gap;
      //--- resuming to it put the user in front of a chart with four
      //--- bars of future and a Play button that had nothing to say.
      //--- A saved place with no road ahead is not worth going back to.
      int ahead = Bars(origin, PERIOD_M1,
                       (datetime)(saved.taken_at_msc / 1000),
                       (datetime)(win_end / 1000));
      if(ahead >= 50)
        {
         //--- through the GROUP, so every chart resumes together
         if(g_group.JumpTo(saved.taken_at_msc))
            PrintFormat("[host] resumed at %s", SSRFormatMsc(saved.taken_at_msc));
        }
      else
         PrintFormat("[host] not resuming to %s - only %d bars ahead of it. "
                     "Starting at the window start instead.",
                     SSRFormatMsc(saved.taken_at_msc), ahead);
     }

   EventSetMillisecondTimer(InpPumpMs);
   g_last_pump_us = GetMicrosecondCount();
   //--- the speed the session opens at, through the port so the panel
   //--- and the engine agree from the first frame
   if(InpStartSpeed > 0.0)
     {
      g_gport.SetSpeedX100((long)MathRound(InpStartSpeed * 100.0));
      PrintFormat("[host] speed %s - %s", SSRSpeedName((long)MathRound(InpStartSpeed * 100.0)),
                  SSRSpeedMeaning((long)MathRound(InpStartSpeed * 100.0)));
     }

   g_ready = true;

   PrintFormat("[host] ready  %s -> %s  %s .. %s",
               origin, rsym, SSRFormatMsc(win_start), SSRFormatMsc(win_end));
   //--- NAME THE CHART THAT OWNS THE KEYBOARD.
   //--- The candles are on one chart and the controls on another, and a
   //--- user reasonably presses keys where the candles are. There they
   //--- do nothing: MetaTrader delivers key events only to the chart a
   //--- program is attached to. Saying which one costs a line.
   //--- TWO SESSIONS ON ONE SLOT share the publisher's terminal
   //--- globals and quietly fight over them. The user just did exactly
   //--- this - US30 and XAUUSD both on slot 1 - so it is detected,
   //--- not left in a manual.
   string suffix = SSR_SYMBOL_SUFFIX + IntegerToString(InpSlot);
   string mine   = g_sink.ReplaySymbol();
   for(int si = SymbolsTotal(false) - 1; si >= 0; si--)
     {
      string sn = SymbolName(si, false);
      if(sn == mine || !SSRIsReplaySymbol(sn))
         continue;
      if(StringLen(sn) > StringLen(suffix) &&
         StringSubstr(sn, StringLen(sn) - StringLen(suffix)) == suffix)
        {
         //--- LIVE OR LEFTOVER? The two need opposite advice, and the
         //--- first version of this line asserted "two instruments at
         //--- once" without checking - then printed it at a user who
         //--- was running one, beside a symbol left by a session that
         //--- had ended. A chart open on it is the difference.
         bool live = false;
         for(long cid = ChartFirst(); cid >= 0; cid = ChartNext(cid))
            if(ChartSymbol(cid) == sn)
              { live = true; break; }

         if(live)
            PrintFormat("[host] NOTE: %s is OPEN and also on replay slot %d. "
                        "Two sessions at once need different slots - set "
                        "'Replay slot' to %d on one of them.",
                        sn, InpSlot, InpSlot + 1);
         else
            PrintFormat("[host] NOTE: %s is left over from an earlier session "
                        "(no chart is open on it). Harmless; run "
                        "Scripts/SSReplay/Spike/SSR_Z_Cleanup to remove it.",
                        sn);
         break;
        }
     }

   //--- HOW MUCH IS ACTUALLY IN THE WINDOW. A window that opens fine
   //--- and contains a weekend is the one failure that looks exactly
   //--- like a healthy tool with a dead Play button.
   int win_bars = Bars(origin, PERIOD_M1,
                       (datetime)(win_start / 1000), (datetime)(win_end / 1000));
   if(win_bars >= 0 && win_bars < 30)
      PrintFormat("[host] WARNING: only %d bars inside the replay window - "
                  "this is mostly a market-closed gap (weekend?). Set "
                  "'Replay start' to a weekday, or raise 'Bars to replay'.",
                  win_bars);
   else
     {
      //--- A window can be perfectly healthy AND contain a weekend. The
      //--- user meets that gap minutes later as a chart that stops
      //--- moving, so it is named now rather than discovered then.
      long span_min = (win_end - win_start) / SSR_MSC_PER_MIN;
      if(win_bars > 0 && span_min > win_bars * 2)
         PrintFormat("[host] %d M1 bars inside the replay window, spanning "
                     "%d minutes - it crosses a market-closed gap. Play "
                     "skips it automatically and says so.",
                     win_bars, (int)span_min);
      else
         PrintFormat("[host] %d M1 bars inside the replay window", win_bars);
     }

   //--- THE STATE THAT MATTERS, ON ONE LINE. Three rounds have now been
   //--- spent asking "does it replay?" without the log saying what the
   //--- engine was actually holding when the user pressed Play.
   PrintFormat("[host] SESSION READY: window %s .. %s | %d bars | panel on %s "
               "| status %s",
               SSRFormatMsc(win_start), SSRFormatMsc(win_end), win_bars,
               (g_panel_chart == g_replay_chart ? "the replay chart" : "this chart"),
               SSRStateName(g_ctrl.Status()));

   //--- A PANEL TALLER THAN THE CHART IS AN INVISIBLE PANEL. The user's
   //--- Toolbox was open to three quarters of the screen, leaving a 90
   //--- pixel chart and a panel showing only its caption - which reads
   //--- exactly like a tool that did not start.
   int chart_h = (int)ChartGetInteger(g_panel_chart, CHART_HEIGHT_IN_PIXELS);
   if(chart_h > 0 && chart_h < SSR_PANEL_H + 20)
      PrintFormat("[host] THE CHART IS ONLY %d PIXELS TALL and the panel needs "
                  "%d. Press Ctrl+T to close the Toolbox, or drag its top edge "
                  "down - the panel is there, it just has nowhere to draw.",
                  chart_h, SSR_PANEL_H + 20);

   if(g_on_replay_chart)
      PrintFormat("[host] one window: the chart, the panel, the mouse and the "
                  "keyboard are all on %s. Nothing else to click.", _Symbol);
   else if(one_chart_ok)
      //--- a pass that is about to hand this chart over must not tell
      //--- the user to click it. Fifty milliseconds later it is gone.
      Print("[host] this pass is only preparing the session - the panel "
            "arrives after the handover below.");
   else
      PrintFormat("[host] the panel and the keyboard are on the %s chart - "
                  "click it first. The replay chart is for watching.", _Symbol);
   Print("[host] ", SSRKeyHint());

   //+------------------------------------------------------------------+
   //| PASS 1 ENDS BY HANDING ITS OWN CHART OVER.                       |
   //|                                                                  |
   //| Everything above already ran: the symbol exists, it is seeded,    |
   //| the engine is loaded and the session is restored. Only now does   |
   //| the chart change, which deinitialises this EA and starts it       |
   //| again on the replay symbol - where the second pass adopts the     |
   //| symbol rather than rebuilding it, because MetaTrader will not     |
   //| delete a symbol a chart is open on.                               |
   //|                                                                   |
   //| The origin is stashed FIRST. If the switch succeeds and the name  |
   //| is not there, the second pass has nothing to work from and the    |
   //| user is left on a chart with no tool - the one failure here that  |
   //| would need a manual rescue.                                       |
   //|                                                                   |
   //| Done from OnInit's tail rather than the timer because there is    |
   //| nothing left to do in this instance either way; the timer would   |
   //| only add a window in which the user could press something that    |
   //| is about to be destroyed.                                         |
   //+------------------------------------------------------------------+
   //+------------------------------------------------------------------+
   //| THE HANDOVER IS ARMED HERE AND DONE ON THE FIRST TIMER TICK.     |
   //|                                                                  |
   //| ChartSetSymbolPeriod is asynchronous and it deinitialises this    |
   //| very program. Calling it from inside OnInit asks MetaTrader to    |
   //| tear down a program that has not finished starting, and what      |
   //| happens then is not something the documentation promises. From    |
   //| the timer, OnInit has returned and the EA is fully alive, which   |
   //| is the ordinary way anything else changes a chart.                |
   //+------------------------------------------------------------------+
   if(one_chart_ok && !g_on_replay_chart)
     {
      StashOrigin(origin);
      g_switch_to = g_sink.ReplaySymbol();
      if(g_switch_to == "")
         Print("[host] no replay symbol name to hand this chart over to; "
               "staying on two windows.");
     }

   return true;
  }

//+------------------------------------------------------------------+
int OnInit()
  {
   //+------------------------------------------------------------------+
   //| ONE WINDOW, DONE PROPERLY THIS TIME.                             |
   //|                                                                  |
   //| Two earlier attempts put the panel on a SEPARATE replay chart    |
   //| and tried to reach its events from here. Drawing across charts    |
   //| works; events do not. A forwarding indicator could not work at    |
   //| all - iCustom keeps the creator's chart context, and its own log  |
   //| line printed the same id twice saying so. Polling the buttons     |
   //| worked, but nothing latches a KEY and nothing latches a DRAG, so  |
   //| the keyboard and the mouse stayed on the wrong window.            |
   //|                                                                  |
   //| The only way a program gets a chart's events is to BE on it. So   |
   //| this EA now turns its own chart into the replay chart and stays   |
   //| there. One window, and every input arrives the ordinary way.      |
   //|                                                                  |
   //| It costs one restart: changing the symbol deinitialises and       |
   //| reinitialises this EA. The code already survives that - the       |
   //| replay symbol and the session are deliberately kept through       |
   //| REASON_CHARTCHANGE - so the second pass adopts what the first     |
   //| one left and carries on.                                          |
   //+------------------------------------------------------------------+
   bool on_replay = SSRIsReplaySymbol(_Symbol);
   //--- set BEFORE any failure path: FailInit reads these to put the
   //--- chart back, and a failure that happens before they are assigned
   //--- is exactly the one that would strand the user
   g_on_replay_chart = on_replay;

   string stashed = ReadStashedOrigin();

   //+------------------------------------------------------------------+
   //| THE PICKED START HAS TO SURVIVE THE HANDOVER.                    |
   //|                                                                  |
   //| g_pick_msc is a global, and the handover restarts this program:  |
   //| globals are re-initialised, so on the second pass the choice was |
   //| simply gone and the window fell back to "the last 2000 bars".    |
   //| The user picked a moment and the tool quietly replayed a         |
   //| different one.                                                   |
   //|                                                                  |
   //| It rides across in a hidden label on the chart, the same way the |
   //| origin symbol does - objects belong to the chart and survive the |
   //| symbol change that restarts us.                                  |
   //+------------------------------------------------------------------+
   if(ObjectFind(0, SSR_PICK_STASH) >= 0)
     {
      string ps = ObjectGetString(0, SSR_PICK_STASH, OBJPROP_TEXT);
      if(ps != "")
         g_pick_msc = (long)StringToTime(ps) * 1000;
     }

   //--- a "!" prefix is last run's failed second pass telling this one
   //--- not to try the handover again. Read once, then cleared.
   bool one_chart_ok = InpOneChart;
   if(StringLen(stashed) > 0 && StringSubstr(stashed, 0, 1) == "!")
     {
      stashed = StringSubstr(stashed, 1);
      one_chart_ok = false;
      ObjectDelete(0, SSR_HANDOFF);
      Print("[host] one-window mode is OFF for this run: the last attempt "
            "failed after the chart was handed over. Two windows this time.");
     }

   string origin = (on_replay ? stashed
                              : (InpSymbol == "" ? _Symbol : InpSymbol));
   g_origin = origin;

   PrintFormat("[host] SS Replay build %s   pass=%s  chart=%s  origin=%s",
               SSR_BUILD, (on_replay ? "2 (on the replay chart)" : "1"),
               _Symbol, (origin == "" ? "<UNKNOWN>" : origin));

   if(on_replay && origin == "")
     {
      //--- attached straight to a replay chart with nothing to go on.
      //--- Refuse, and say what to do, rather than replaying a replay.
      Print("[host] this chart is already a replay symbol and I do not know "
            "which instrument it came from. Attach SS Replay to a normal "
            "chart, or set InpSymbol to the origin, and try again.");
      return FailInit();
     }

   g_sink.SetAdoptExisting(on_replay);
   for(int i = 0; i < SSR_EXTRA_STREAMS; i++)
      g_sink2[i].SetAdoptExisting(false);
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
      return FailInit();
     }

   //--- FETCH THE HISTORY BEFORE ANYTHING DEPENDS ON IT. Only on the
   //--- first pass: the second is on a custom symbol whose history we
   //--- wrote ourselves, and asking the broker for that is meaningless.
   if(InpAutoHistory && !on_replay)
     {
      EnsureHistory(origin, InpHistoryBars);
      g_src.Close();
      if(!g_src.Open(origin))
        {
         Print("[host] no M1 history for ", origin, " after the download");
         return FailInit();
        }
     }

   SSRDataRange range;
   range.Init();
   g_src.RangeInto(range);

   //+------------------------------------------------------------------+
   //| THE PICKER. Offered before anything is built, because what it    |
   //| picks decides what gets built.                                   |
   //|                                                                  |
   //| It runs on the REAL symbol's chart, which still holds the whole  |
   //| history - that is the only moment such a choice can be made by   |
   //| looking at price. An explicit 'Replay start' or a random session |
   //| has already answered the question, so the picker stays out of    |
   //| the way in both cases.                                           |
   //+------------------------------------------------------------------+
   if(InpPickStart && !on_replay && InpStart == 0 && !InpRandom)
     {
      //--- already chosen (this run, or before the handover)? then the
      //--- picker has nothing left to ask
      if(g_pick_msc == SSR_INVALID_TIME)
        {
         //--- default the line to where the auto window would have
         //--- started, so pressing the button without dragging gives
         //--- exactly the old behaviour
         //--- where the user is ALREADY looking, not an arbitrary
         //--- distance back. Falls back to the auto window's start only
         //--- when the chart cannot say what it is showing.
         long def = MiddleOfView();
         if(def == SSR_INVALID_TIME)
           {
            MqlRates back[];
            def = range.last_msc - (long)InpReplayBars * SSR_MSC_PER_MIN;
            if(CopyRates(origin, PERIOD_M1, 0, InpReplayBars, back) > 0)
               def = (long)back[0].time * 1000;
           }
         ShowPicker(origin, def);
         g_picking = true;
         EventSetMillisecondTimer(200);
         return INIT_SUCCEEDED;
        }

      PrintFormat("[host] starting from the line you placed: %s",
                  SSRFormatMsc(g_pick_msc));
     }

   if(!BuildSession(origin, on_replay, one_chart_ok))
      return FailInit();
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

   RemovePicker();
   if(reason == REASON_REMOVE || reason == REASON_PROGRAM || reason == REASON_CLOSE)
      ObjectDelete(ChartID(), SSR_PICK_STASH);

   g_session_dlg.Destroy();
   g_dialog.Destroy();
   g_panel.Destroy();

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

      //+------------------------------------------------------------------+
      //| GIVE THE CHART BACK BEFORE THE SYMBOL GOES.                      |
      //|                                                                  |
      //| MetaTrader will not delete a symbol a chart is open on, and this |
      //| chart is open on it. Switching back to the origin first is both  |
      //| the courtesy - the user gets the chart they had - and the only   |
      //| way the delete below can succeed.                                |
      //|                                                                  |
      //| The switch is asynchronous, so the delete may still lose the     |
      //| race. That is reported rather than hidden: the symbol is one per |
      //| slot and the next run adopts it, so a survivor costs nothing but |
      //| a line in the log.                                               |
      //+------------------------------------------------------------------+
      if(g_on_replay_chart && g_origin != "")
        {
         ObjectDelete(ChartID(), SSR_HANDOFF);
         if(ChartSetSymbolPeriod(ChartID(), g_origin, _Period))
            PrintFormat("[host] this chart is back on %s", g_origin);
         else
            PrintFormat("[host] could not put this chart back on %s (%d) - "
                        "switch it yourself; the replay symbol may survive "
                        "until then, which the next run will simply reuse.",
                        g_origin, GetLastError());
        }

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
//+------------------------------------------------------------------+
//| VITALS - one line, everything, once a second.                    |
//|                                                                  |
//| Three releases were spent guessing why "the candles do not move" |
//| from screenshots. Each guess was plausible, each was wrong, and  |
//| each cost a round trip because the report could not distinguish  |
//| an engine that is not running from an engine that is running     |
//| into a view that is not looking. This line separates them:       |
//|                                                                  |
//|   state / clock   is the ENGINE moving?                          |
//|   m1 / last       are BARS being written?                        |
//|   chart / auto    is the chart on the replay symbol at all?      |
//|   first/vis/off   is the VIEW at the newest bar?                 |
//|   snaps           is anything dragging it there?                 |
//|                                                                  |
//| off>0 and rising with m1 rising is the whole defect, visible in  |
//| one line instead of five messages.                               |
//+------------------------------------------------------------------+
void PrintVitals()
  {
   string rsym = g_sink.ReplaySymbol();
   int    m1   = (rsym == "" ? 0 : Bars(rsym, PERIOD_M1));
   datetime lastbar = (rsym == "" ? (datetime)0
                       : (datetime)SeriesInfoInteger(rsym, PERIOD_M1, SERIES_LASTBAR_DATE));

   string charts = "";
   for(int i = 0; i < g_charts.Count(); i++)
     {
      long id = g_charts.IdAt(i);
      long first = ChartGetInteger(id, CHART_FIRST_VISIBLE_BAR);
      long vis   = ChartGetInteger(id, CHART_VISIBLE_BARS);
      long off   = (vis > 0 ? first - (vis - 1) : 0);
      if(off < 0)
         off = 0;
      SSRChartInfo ci;
      ci.Init();
      bool have = g_charts.InfoAt(i, ci);
      charts += StringFormat(" | chart#%d %s %s auto=%d follow=%d first=%d vis=%d off=%d",
                             i, ChartSymbol(id),
                             EnumToString(ChartPeriod(id)),
                             (int)ChartGetInteger(id, CHART_AUTOSCROLL),
                             (have ? (ci.follow && !ci.user_detached ? 1 : 0) : -1),
                             (int)first, (int)vis, (int)off);
     }
   if(g_charts.Count() == 0)
      charts = " | NO CHART is showing " + rsym +
               " - the view cannot move because nothing is looking at it";

   PrintFormat("[vitals] %s clock=%s playing=%d spd=%.0fx | %s m1=%d last=%s snaps=%d%s",
               SSRStateName(g_ctrl.Status()),
               SSRFormatMsc(g_ctrl.Now()),
               (int)g_group.AnyPlaying(),
               g_ctrl.SpeedX100() / 100.0,
               rsym, m1,
               (lastbar > 0 ? TimeToString(lastbar, TIME_DATE | TIME_MINUTES) : "-"),
               (int)g_charts.Snaps(),
               charts);
  }

//+------------------------------------------------------------------+
void OnTimer()
  {
   //+------------------------------------------------------------------+
   //| WAITING FOR THE USER TO PLACE THE LINE.                          |
   //|                                                                  |
   //| Nothing is built yet. When the button is pressed, the line's     |
   //| time is stashed and the EA is restarted by re-applying its own   |
   //| symbol and period - which costs nothing and brings us back into  |
   //| OnInit with the answer in hand, instead of duplicating the whole |
   //| build sequence out here where it would drift.                    |
   //+------------------------------------------------------------------+
   if(g_picking)
     {
      datetime at = (datetime)ObjectGetInteger(0, SSR_PICK_LINE, OBJPROP_TIME);
      if(at > 0)
         ObjectSetString(0, SSR_PICK_INFO, OBJPROP_TEXT,
                         "Start: " + TimeToString(at, TIME_DATE | TIME_MINUTES) +
                         "   -   drag the line, then press the green button");

      if(ObjectGetInteger(0, SSR_PICK_HERE, OBJPROP_STATE))
        {
         ObjectSetInteger(0, SSR_PICK_HERE, OBJPROP_STATE, false);
         long mid = MiddleOfView();
         if(mid != SSR_INVALID_TIME)
           {
            ObjectSetInteger(0, SSR_PICK_LINE, OBJPROP_TIME,
                             (datetime)(mid / 1000));
            ChartRedraw(0);
           }
         return;
        }

      if(ObjectGetInteger(0, SSR_PICK_GO, OBJPROP_STATE))
        {
         ObjectSetInteger(0, SSR_PICK_GO, OBJPROP_STATE, false);
         if(at <= 0)
           {
            Print("[host] the start line is gone - put it back, or turn "
                  "'Pick the start' off.");
            return;
           }
         RemovePicker();
         g_picking = false;
         EventKillTimer();
         g_pick_msc = (long)at * 1000;

         //--- and on the chart, so the handover's restart cannot lose it
         if(ObjectFind(0, SSR_PICK_STASH) < 0)
            ObjectCreate(0, SSR_PICK_STASH, OBJ_LABEL, 0, 0, 0);
         ObjectSetInteger(0, SSR_PICK_STASH, OBJPROP_XDISTANCE, -1000);
         ObjectSetInteger(0, SSR_PICK_STASH, OBJPROP_YDISTANCE, -1000);
         ObjectSetInteger(0, SSR_PICK_STASH, OBJPROP_HIDDEN,    true);
         ObjectSetString (0, SSR_PICK_STASH, OBJPROP_TEXT,
                          TimeToString(at, TIME_DATE | TIME_MINUTES));

         PrintFormat("[host] start set to %s - building the session",
                     TimeToString(at, TIME_DATE | TIME_MINUTES));

         //+------------------------------------------------------------------+
         //| BUILD IT HERE. The previous version called                       |
         //| ChartSetSymbolPeriod with this chart's OWN symbol and period,    |
         //| expecting a reinitialise. MetaTrader sees nothing to change and  |
         //| does nothing at all, so the button removed the line, killed the  |
         //| timer, and left a chart with no tool on it - exactly what the    |
         //| user reported. There was never a need to go back through OnInit; |
         //| the build is a function and this is where the answer is.          |
         //+------------------------------------------------------------------+
         if(!BuildSession(g_origin, false, InpOneChart))
           {
            Print("[host] the session could not be built from that start. "
                  "Remove SS Replay and try another point.");
            return;
           }
        }
      return;
     }

   //--- a pass that has asked for the symbol change is seconds from
   //--- being destroyed. Pumping ticks into a symbol whose chart is
   //--- mid-switch buys nothing and can only produce half-written bars.
   if(g_switching)
      return;

   if(g_switch_to != "")
     {
      string rs = g_switch_to;
      g_switch_to = "";
      if(!SymbolSelect(rs, true))
        {
         PrintFormat("[host] %s will not go into Market Watch, so this chart "
                     "cannot show it. Staying on two windows.", rs);
        }
      else
        {
         g_switching = true;
         PrintFormat("[host] handing this chart over to %s - SS Replay will "
                     "restart once on it. This is expected.", rs);
         if(!ChartSetSymbolPeriod(ChartID(), rs, InpChartTf))
           {
            g_switching = false;
            PrintFormat("[host] could not switch this chart to %s (%d). "
                        "Staying on two windows.", rs, GetLastError());
           }
         return;
        }
     }

   if(!g_ready)
      return;

   ulong now   = GetMicrosecondCount();
   ulong delta = (now - g_last_pump_us) / 1000;
   g_last_pump_us = now;

   //--- a stalled terminal must not be replayed as a giant jump: the
   //--- engine would try to emit minutes of ticks in one call
   if(delta > 1000)
      delta = 1000;

   //+------------------------------------------------------------------+
   //| PRESSING PLAY MEANS "I WANT TO WATCH THIS RUN".                  |
   //|                                                                  |
   //| A user who pauses and scrolls back to study a move is detached   |
   //| from the right edge on purpose, and the chart layer is right to  |
   //| leave them there. But when they press Play again they are asking |
   //| to see it move, and a chart still parked where they left it      |
   //| shows a replay running out of sight - the same silent failure    |
   //| this whole release exists to remove, arrived at by a route the   |
   //| user would blame on the tool rather than on their own scroll.    |
   //|                                                                  |
   //| Read as a transition, not a state, so it re-arms once per press  |
   //| and never fights a scroll made while it is already playing.      |
   //+------------------------------------------------------------------+
   bool playing = g_group.AnyPlaying();
   if(playing && !g_was_playing)
     {
      g_charts.FollowAll();
      for(int i = 0; i < g_extra; i++)
         g_charts2[i].FollowAll();
     }
   g_was_playing = playing;

   //--- ONE PUMP FOR THE BOARD. The group takes the wall delta and
   //--- hands every stream an instant, so there is nothing to drift.
   if(playing)
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
      //--- and repaint. Free at the tick fidelities, and the only thing
      //--- that moves the chart at bar fidelity, where no tick arrives
      //--- to do it. The manager throttles it.
      g_charts.Redraw();
      for(int i = 0; i < g_extra; i++)
         g_charts2[i].Sync();
     }
   //--- 25 pumps of InpPumpMs is about a second at the default 40ms.
   //--- A paused replay has nothing new to say, so it says it ten
   //--- times less often: enough to still answer "is it alive", not
   //--- enough to bury the log while the user reads a chart.
   if(InpVitals && g_slow_tick % (playing ? 25 : 250) == 0)
      PrintVitals();
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
         //+------------------------------------------------------------------+
         //| THE LINES ARE NOT ARMED HERE ANY MORE.                           |
         //|                                                                  |
         //| They used to appear on their own at the first tick. Two lines a  |
         //| user did not ask for, on every session, whether or not they were |
         //| about to trade - and no way to get rid of them. The panel has an |
         //| SL/TP button now (and the L key), so arming is a decision.        |
         //|                                                                  |
         //| What stays here is the POLL, and it stays for the reason it was  |
         //| written: the lines live on the replay chart, this program is not |
         //| attached to that chart, so no drag event can ever arrive. Asking |
         //| them where they are, once a tick, needs no events at all.         |
         //+------------------------------------------------------------------+
         if(g_lines.IsArmed())
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

   //+------------------------------------------------------------------+
   //| THE PANEL PAINTS AT UI RATE, NOT AT ENGINE RATE.                 |
   //|                                                                  |
   //| This ran on every pump - twenty-five times a second - and each    |
   //| pass rewrites every rectangle, button and label the panel owns,   |
   //| then calls ChartRedraw. That was affordable while the panel sat   |
   //| on an idle host chart. It is not affordable now that it sits on   |
   //| the replay chart, which MetaTrader is already repainting with     |
   //| incoming ticks: the two compete, the terminal goes sluggish, and  |
   //| a sluggish terminal is one that answers clicks late or not at all.|
   //|                                                                  |
   //| Ten frames a second is more than enough for a clock that counts   |
   //| in seconds. Anything the user DOES still repaints immediately -   |
   //| clicks and keys call Render themselves and do not come through    |
   //| here.                                                             |
   //+------------------------------------------------------------------+
   //+------------------------------------------------------------------+
   //| POLL FIRST, PAINT SECOND - AND THE ORDER MATTERS.                |
   //|                                                                  |
   //| A repaint rewrites every button. If it ran first it could rewrite|
   //| one that the user pressed a millisecond earlier and the press     |
   //| would be gone before anyone read it. Polling first means the      |
   //| longest a click can wait is one pump.                             |
   //+------------------------------------------------------------------+
   //--- not while a dialog is up: it is modal, and a panel that still
   //--- answers clicks underneath one is two UIs fighting for one mouse
   if(!g_session_dlg.IsOpen() && !g_dialog.IsOpen())
     {
      ENUM_SSR_CMD host_cmd = g_panel.PollClicks();
      if(host_cmd != SSR_CMD_NONE)
         RunHostCommand(host_cmd);
     }

   uint now_ms = GetTickCount();
   if(now_ms - g_panel_paint >= 100)
     {
      g_panel_paint = now_ms;
      g_panel.Render();
     }
  }

//+------------------------------------------------------------------+
//| The commands the HOST owns, because their dialogs need layers    |
//| the panel is not allowed to know about.                          |
//|                                                                  |
//| One function, reached from both the key path and the button poll,|
//| so pressing J and clicking Jump cannot end up doing different    |
//| things - which is exactly what happened while they were two.     |
//+------------------------------------------------------------------+
void RunHostCommand(const ENUM_SSR_CMD cmd)
  {
   if(cmd == SSR_CMD_SESSIONS)
     {
      g_session_dlg.Open();
      g_panel.Render();
      return;
     }
   if(cmd == SSR_CMD_JUMP)
     {
      SSRSessionRange r;
      r.Init();
      r.origin    = (InpSymbol == "" ? _Symbol : InpSymbol);
      r.start_msc = g_group.Now();
      r.end_msc   = g_group.EndMsc();
      g_dialog.Open(r);
      PrintFormat("[host] jump dialog: open=%s catalog=%s",
                  (g_dialog.IsOpen() ? "yes" : "NO"),
                  (g_catalog.Available() ? "available" : "NOT AVAILABLE"));
      g_panel.Render();
     }
  }

//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam,
                  const double &dparam, const string &sparam)
  {
   if(!g_ready)
      return;

   RouteEvent(id, lparam, dparam, sparam);
  }

//+------------------------------------------------------------------+
void RouteEvent(const int id, const long &lparam,
                const double &dparam, const string &sparam)
  {

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

   //--- S and J on THIS chart. The button poll reaches the same place.
   if(id == CHARTEVENT_KEYDOWN)
     {
      ENUM_SSR_CMD kc = SSRKeyToCommand(lparam);
      if(kc == SSR_CMD_SESSIONS || kc == SSR_CMD_JUMP)
        {
         RunHostCommand(kc);
         return;
        }
     }

   //--- "Replay From Here" needs a click on a CANDLE, not on a panel
   //--- object, and only the chart this program is attached to reports
   //--- those. It waits for the engine to move into a Service, which
   //--- is what lets the UI live on the replay chart as a program in
   //--- its own right rather than as objects drawn from over here.
  }

//+------------------------------------------------------------------+
//| The host is attached to a chart, so MetaTrader delivers ticks    |
//| here too. The engine is driven by the timer, not by them.        |
//+------------------------------------------------------------------+
void OnTick() {}
//+------------------------------------------------------------------+
