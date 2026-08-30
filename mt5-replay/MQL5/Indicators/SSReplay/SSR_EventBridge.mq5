//+------------------------------------------------------------------+
//|                                            SSR_EventBridge.mq5   |
//|                 SS Replay - one window instead of two (UI)       |
//|                                                                  |
//|  THE PROBLEM THIS SOLVES                                         |
//|  MetaTrader delivers OnChartEvent ONLY to the chart a program is |
//|  attached to. The engine runs as an Expert Advisor on a host     |
//|  chart and opens a second chart for the replay symbol, so the    |
//|  panel had to live on the host chart - the candles on one window |
//|  and every control on another. Soft4FX puts both on one screen,  |
//|  and so should we.                                               |
//|                                                                  |
//|  Drawing was never the obstacle: ObjectCreate takes a chart id,  |
//|  so the EA can paint the panel onto the replay chart today. Only |
//|  EVENTS are chart-local. This indicator is the missing half: it  |
//|  sits on the replay chart, receives that chart's clicks, keys    |
//|  and mouse moves, and forwards each one verbatim to the EA's     |
//|  chart with EventChartCustom.                                    |
//|                                                                  |
//|  THE ENCODING                                                    |
//|  The original event id travels as the custom event number, so    |
//|  the host receives CHARTEVENT_CUSTOM + id and subtracts to get   |
//|  the event it would have had. lparam, dparam and sparam pass     |
//|  through untouched: a forwarded click must be indistinguishable  |
//|  from a local one, or the host needs two code paths and one of   |
//|  them will rot.                                                  |
//|                                                                  |
//|  It draws nothing. It has no buffers. Removing it costs the      |
//|  panel its input and nothing else - which is exactly why the     |
//|  host checks that this installed and refuses to move the panel   |
//|  when it did not.                                                |
//+------------------------------------------------------------------+
#property description "SS Replay - forwards this chart's events to the replay host. Draws nothing."
#property version   "1.00"
#property indicator_chart_window
#property indicator_plots   0
#property indicator_buffers 0

#include <SSReplay/Common/SSR_Build.mqh>

//--- the chart the Expert Advisor is attached to. Passed by the host
//--- when it installs this; there is nothing sensible to default to,
//--- and 0 means "not configured" rather than "this chart".
input long InpHostChart = 0;   // Host chart id (set by SS Replay)

long g_host = 0;

//+------------------------------------------------------------------+
int OnInit()
  {
   g_host = InpHostChart;
   IndicatorSetString(INDICATOR_SHORTNAME, "SSR EventBridge");

   if(g_host == 0)
     {
      //--- SAY SO. A bridge with no far end is not a quiet no-op: the
      //--- panel on this chart would look alive and answer nothing.
      Print("[bridge] NOT CONNECTED - no host chart id was given. ",
            "The panel on this chart will not respond. build ", SSR_BUILD);
      return INIT_SUCCEEDED;
     }

   //--- the panel needs mouse moves to drag itself and its trackbar,
   //--- and this chart is where they now happen
   ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, true);
   PrintFormat("[bridge] chart %d -> host %d   build %s",
               (int)ChartID(), (int)g_host, SSR_BUILD);
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
int OnCalculate(const int rates_total, const int prev_calculated,
                const int begin, const double &price[])
  {
   //--- nothing to compute. The bridge exists for its event handler.
   return rates_total;
  }

//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam,
                  const double &dparam, const string &sparam)
  {
   if(g_host == 0 || g_host == ChartID())
      return;

   //--- CHARTEVENT_CUSTOM events would come back to us if the host ever
   //--- echoed one; forwarding those would build a loop between two
   //--- charts that only stops when the terminal does.
   if(id >= CHARTEVENT_CUSTOM)
      return;

   EventChartCustom(g_host, (ushort)id, lparam, dparam, sparam);
  }
//+------------------------------------------------------------------+
