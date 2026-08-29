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
#property version   "0.1"

#include <SSReplay/Common/SSR_Types.mqh>
#include <SSReplay/Common/SSR_Time.mqh>
#include <SSReplay/Common/SSR_Log.mqh>
#include <SSReplay/Core/SSR_ReplayController.mqh>
#include <SSReplay/Data/SSR_Mt5DataSource.mqh>
#include <SSReplay/Mt5/SSR_CustomSymbolSink.mqh>
#include <SSReplay/Chart/SSR_ChartManager.mqh>
#include <SSReplay/Ui/SSR_DirectPort.mqh>
#include <SSReplay/Ui/SSR_Panel.mqh>

input string          InpSymbol     = "";                   // Symbol (empty = this chart)
input datetime        InpStart      = 0;                    // Replay start (0 = auto)
input int             InpReplayBars = 2000;                 // Bars to replay when start is auto
input int             InpWarmupBars = 1000;                 // Warmup bars for HTF context
input ENUM_TIMEFRAMES InpChartTf    = PERIOD_M5;            // Replay chart timeframe
input int             InpSlot       = 1;                    // Replay slot
input int             InpTicksPerBar = 8;                   // Ticks per M1 bar (synthetic)
input double          InpSpreadPoints = 20;                 // Simulated spread, in points
input int             InpPumpMs     = 40;                   // Engine tick interval (ms)

CSSRMt5DataSource    g_src;
CSSRCustomSymbolSink g_sink;
CSSRReplayController g_ctrl;
CSSRChartManager     g_charts;
CSSRDirectPort       g_port;
CSSRPanel            g_panel;

long  g_replay_chart = 0;
ulong g_last_pump_us = 0;
int   g_slow_tick    = 0;
bool  g_ready        = false;

//+------------------------------------------------------------------+
int OnInit()
  {
   string origin = (InpSymbol == "" ? _Symbol : InpSymbol);
   g_ssr_log.SetTag("host");
   g_ssr_log.SetLevel(SSR_LOG_INFO);

   if(!g_src.Open(origin))
     {
      Print("[host] no M1 history for ", origin);
      return INIT_FAILED;
     }

   SSRDataRange range;
   range.Init();
   g_src.RangeInto(range);

   //--- pick a window. Auto lands near the end of what the broker has,
   //--- leaving room for the warmup the higher timeframes need.
   long win_end   = range.last_msc;
   long win_start = (InpStart > 0 ? SSRToMsc(InpStart)
                                  : win_end - (long)InpReplayBars * SSR_MSC_PER_MIN);
   long floor_msc = range.first_msc + (long)InpWarmupBars * SSR_MSC_PER_MIN;
   if(win_start < floor_msc)
      win_start = floor_msc;
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

   if(!g_ctrl.Load(origin, win_start, win_end))
     {
      Print("[host] load failed: ", g_ctrl.LastErrorText());
      return INIT_FAILED;
     }

   string rsym = g_sink.ReplaySymbol();
   g_charts.Configure(rsym, origin);
   g_replay_chart = g_charts.OpenChart(InpChartTf);
   g_charts.ScanLeaks();

   g_port.Attach(GetPointer(g_ctrl), GetPointer(g_sink), GetPointer(g_charts));

   //--- The panel MUST live on this EA's own chart. MetaTrader delivers
   //--- OnChartEvent only for the chart a program is attached to, so a
   //--- panel drawn on the replay chart would render perfectly and
   //--- respond to nothing. The replay chart is opened separately.
   g_panel.Create(ChartID(), GetPointer(g_port));

   EventSetMillisecondTimer(InpPumpMs);
   g_last_pump_us = GetMicrosecondCount();
   g_ready = true;

   PrintFormat("[host] ready  %s -> %s  %s .. %s",
               origin, rsym, SSRFormatMsc(win_start), SSRFormatMsc(win_end));
   Print("[host] ", SSRKeyHint());
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   g_panel.Destroy();

   //--- REASON_CHARTCHANGE and friends destroy this EA and rebuild it.
   //--- Tearing the replay symbol down on every one of those would
   //--- discard the whole session, so the symbol only goes when the
   //--- user actually removed the tool.
   bool user_removed = (reason == REASON_REMOVE || reason == REASON_PROGRAM ||
                        reason == REASON_CLOSE);
   if(user_removed)
     {
      g_charts.CloseOwned();
      g_ctrl.Release();
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

   if(g_ctrl.Status() == SSR_STATE_PLAYING)
      g_ctrl.Pump(delta);

   //--- chart housekeeping is cheap but not free; keep it off the hot path
   g_slow_tick++;
   if(g_slow_tick % 5 == 0)
      g_charts.Sync();
   if(g_slow_tick % 50 == 0)
      g_charts.ScanLeaks();

   g_panel.Render();
  }

//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam,
                  const double &dparam, const string &sparam)
  {
   if(!g_ready)
      return;

   if(g_panel.OnEvent(id, lparam, dparam, sparam))
      return;

   //--- "Replay From Here" is deliberately absent from the standalone
   //--- host. It means clicking a candle on the REPLAY chart, and this
   //--- EA cannot receive that chart's events. It arrives with the
   //--- indicator panel, which lives on the replay chart itself.
  }

//+------------------------------------------------------------------+
//| The host is attached to a chart, so MetaTrader delivers ticks    |
//| here too. The engine is driven by the timer, not by them.        |
//+------------------------------------------------------------------+
void OnTick() {}
//+------------------------------------------------------------------+
