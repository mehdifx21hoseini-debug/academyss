//+------------------------------------------------------------------+
//|                                                SSR_LeakGuard.mqh |
//|                       SS Replay - Visual Leak Detection (Chart)  |
//|                                                                  |
//|  The engine guarantees the replay SYMBOL holds no future data.   |
//|  It cannot guarantee the user is not looking at the real symbol  |
//|  in the next window.                                             |
//|                                                                  |
//|  That gap is unclosable in code - MetaTrader will not let one    |
//|  program forbid another chart. So the honest response is to      |
//|  detect it and say so, loudly, every session. A backtest tool    |
//|  that stays quiet while the live price is on screen is lying by  |
//|  omission.                                                       |
//+------------------------------------------------------------------+
#ifndef SSR_LEAK_GUARD_MQH
#define SSR_LEAK_GUARD_MQH

#include "../Common/SSR_Types.mqh"
#include "../Common/SSR_SymbolNaming.mqh"
#include "SSR_ChartTypes.mqh"

//+------------------------------------------------------------------+
class CSSRLeakGuard
  {
private:
   string            m_origin;
   string            m_replay;
   SSRLeakReport     m_report;

public:
                     CSSRLeakGuard(void) : m_origin(""), m_replay("")
     { m_report.Init(); }

   void              Configure(const string origin, const string replay)
     {
      m_origin = origin;
      m_replay = replay;
      m_report.Init();
     }

   //+------------------------------------------------------------------+
   //| Walk every open chart and the Market Watch selection.            |
   //+------------------------------------------------------------------+
   void              Scan(void)
     {
      m_report.Init();

      if(m_origin != "")
         m_report.origin_in_watch = (SymbolInfoInteger(m_origin, SYMBOL_SELECT) != 0);

      long id = ChartFirst();
      while(id >= 0)
        {
         string s = ChartSymbol(id);
         if(s == m_replay)
            m_report.replay_charts++;
         else if(s == m_origin)
            m_report.origin_charts++;
         else if(!SSRIsReplaySymbol(s))
            m_report.other_live_charts++;
         id = ChartNext(id);
        }
     }

   void              ReportInto(SSRLeakReport &out) { out = m_report; }
   bool              IsClean(void)      { return m_report.IsClean(); }
   int               OriginCharts(void) { return m_report.origin_charts; }
   int               ReplayCharts(void) { return m_report.replay_charts; }
   bool              OriginInWatch(void){ return m_report.origin_in_watch; }

   //+------------------------------------------------------------------+
   //| Remove the origin symbol from Market Watch.                      |
   //|                                                                  |
   //| Offered, never automatic. Hiding a symbol the user put there is  |
   //| the kind of helpfulness that loses trust - the panel asks first. |
   //+------------------------------------------------------------------+
   bool              HideOrigin(void)
     {
      if(m_origin == "")
         return false;
      //--- a symbol with an open chart cannot be deselected, and closing
      //--- the user's chart without asking is worse than the leak
      if(m_report.origin_charts > 0)
         return false;
      return SymbolSelect(m_origin, false);
     }

   //--- one line for the panel. Empty when there is nothing to say.
   string            Advice(void)
     {
      if(m_report.IsClean())
         return "";
      if(m_report.origin_charts > 0)
         return StringFormat("%s is open on %d chart(s) - close it or your backtest is not blind",
                             m_origin, m_report.origin_charts);
      return StringFormat("%s is in Market Watch - its live price is visible", m_origin);
     }

   string            ToString(void)
     {
      return StringFormat("leak[origin_charts=%d in_watch=%s replay_charts=%d other=%d]",
                          m_report.origin_charts,
                          (m_report.origin_in_watch ? "yes" : "no"),
                          m_report.replay_charts, m_report.other_live_charts);
     }
  };

#endif // SSR_LEAK_GUARD_MQH
//+------------------------------------------------------------------+
