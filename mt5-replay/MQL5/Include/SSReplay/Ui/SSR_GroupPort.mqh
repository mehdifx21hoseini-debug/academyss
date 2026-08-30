//+------------------------------------------------------------------+
//|                                                SSR_GroupPort.mqh |
//|                  SS Replay - Port Over A Master Clock (L4/Ui)    |
//|                                                                  |
//|  The panel drives several instruments without knowing there are  |
//|  several.                                                        |
//|                                                                  |
//|  This is the payoff of the port abstraction from Phase 5, and    |
//|  the reason multi-symbol did not need the panel rewritten. The   |
//|  panel calls Play(); whether that reaches one controller or four |
//|  is decided here and nowhere else.                               |
//|                                                                  |
//|  WHY NOT JUST POINT THE PANEL AT STREAM ZERO                     |
//|  Because every transport command would then move one chart and   |
//|  leave the rest behind - a board that LOOKS synchronised until   |
//|  the moment the user touches it. Transport goes to the group;    |
//|  only the readouts come from the primary stream.                 |
//+------------------------------------------------------------------+
#ifndef SSR_GROUP_PORT_MQH
#define SSR_GROUP_PORT_MQH

#include "SSR_ReplayPort.mqh"
#include "SSR_Theme.mqh"        // for the mark colour it hands down
#include "../Core/SSR_MasterClock.mqh"
#include "../Mt5/SSR_CustomSymbolSink.mqh"
#include "../Chart/SSR_ChartManager.mqh"
#include "../Chart/SSR_TradeLines.mqh"
#include "../Chart/SSR_BlindMode.mqh"
#include "../Trading/SSR_TradingEngine.mqh"
#include "../Strategy/SSR_StrategyHost.mqh"
#include "../Trading/SSR_Statistics.mqh"
#include "../Session/SSR_SessionManager.mqh"

//+------------------------------------------------------------------+
class CSSRGroupPort : public CSSRReplayPort
  {
private:
   CSSRReplayGroup      *m_group;    // not owned
   CSSRCustomSymbolSink *m_sink;     // the PRIMARY stream's sink; may be NULL
   CSSRChartManager     *m_charts;   // the primary stream's charts; may be NULL

   //--- Phase 15. All optional: a port with none of these is exactly
   //--- the read-only port it was before, and says so through the
   //--- state rather than by being a different class.
   CSSRBlindMode        *m_blind;
   CSSRTradingEngine    *m_acct;
   CSSRStatsEngine      *m_stats;
   CSSRStrategyHost     *m_strategies;
   CSSRSessionManager   *m_sessions;

   double                m_risk_percent;
   double                m_tp_points;    // 0 = no target on the order
   CSSRTradeLines       *m_lines;        // not owned; may be NULL
   double                m_stop_points;   // no default: there is no safe one
   string                m_trade_error;
   string                m_session_error;
   string                m_names[];     // the session list, as last read

   CSSRReplayController *Primary(void)
     { return (m_group != NULL ? m_group.At(0) : NULL); }

public:
                     CSSRGroupPort(void)
     : m_group(NULL), m_sink(NULL), m_charts(NULL), m_blind(NULL),
       m_acct(NULL), m_stats(NULL), m_strategies(NULL), m_sessions(NULL),
       m_risk_percent(0.5), m_stop_points(0.0), m_tp_points(0.0),
       m_lines(NULL),
       m_trade_error(""), m_session_error("") {}

   void              Attach(CSSRReplayGroup *g,
                            CSSRCustomSymbolSink *sink = NULL,
                            CSSRChartManager *charts = NULL)
     {
      m_group  = g;
      m_sink   = sink;
      m_charts = charts;
     }

   //--- everything the panel may show or drive, handed over one by
   //--- one so a host can wire only what it actually has
   void              AttachBlind(CSSRBlindMode *b)      { m_blind = b; }
   void              AttachAccount(CSSRTradingEngine *a){ m_acct = a; }
   void              AttachStats(CSSRStatsEngine *s)    { m_stats = s; }
   void              AttachStrategies(CSSRStrategyHost *h) { m_strategies = h; }
   void              AttachSessions(CSSRSessionManager *m) { m_sessions = m; }

   virtual string    Name(void) override { return "group"; }
   virtual bool      IsConnected(void) override
     { return (m_group != NULL && m_group.Count() > 0); }

   //+------------------------------------------------------------------+
   virtual bool      ReadState(SSRUiState &out) override
     {
      out.Init();
      CSSRReplayController *c = Primary();
      if(c == NULL)
         return false;

      out.connected        = true;
      out.status           = c.Status();
      out.speed_x100       = m_group.SpeedX100();
      out.fidelity           = c.Fidelity();
      out.fidelity_effective = c.EffectiveFidelity();
      out.fidelity_note      = c.FidelityReason();

      //--- THE CLOCK COMES FROM THE GROUP, not from a stream. Reading
      //--- the time off one chart is how a multi-symbol board reports
      //--- itself perfectly aligned while sitting a bar apart.
      out.now_msc   = m_group.Now();
      out.start_msc = m_group.StartMsc();
      out.end_msc   = m_group.EndMsc();
      out.progress  = m_group.Progress();
      out.streams   = m_group.Count();
      out.charts_detached = (m_charts != NULL ? m_charts.DetachedCount() : 0);
      out.tp_points       = m_tp_points;
      out.skew_msc  = m_group.MaxSkewMsc();

      //--- the group's reason if it has one, otherwise the stream's
      out.pause_reason = (m_group.PauseReason() != ""
                          ? m_group.PauseReason() : c.PauseReason());

      SSRPerfSnapshot perf;
      c.PerfInto(perf);
      out.perf_calibrated = perf.calibrated;
      out.us_per_tick     = perf.us_per_tick;
      out.pump_p95_ms     = perf.pump_p95_ms;

      //--- counters are SUMMED: the cost of the board is what the user
      //--- is paying, not the cost of whichever chart is on top
      for(int i = 0; i < m_group.Count(); i++)
        {
         CSSRReplayController *m = m_group.At(i);
         out.ticks_emitted    += m.TicksEmitted();
         out.bars_consumed    += m.BarsConsumed();
         out.guard_violations += m.Violations();
        }

      out.bookmarks          = c.BookmarkCount();
      out.has_saved_position = c.HasSavedPosition();
      out.checkpoints        = c.Snapshots().Count();
      out.last_error         = c.LastError();
      out.last_error_text    = c.LastErrorText();

      if(m_sink != NULL)
        {
         out.symbol = m_sink.ReplaySymbol();
         SSRSymbolStats st;
         m_sink.Manager().StatsInto(st);
         out.ticks_rejected = st.ticks_rejected;
        }
      else
         out.symbol = c.Symbol();

      //--- and a board says so, rather than pretending to be one chart
      if(out.streams > 1)
         out.symbol = StringFormat("%s +%d", out.symbol, out.streams - 1);

      if(m_charts != NULL)
        {
         out.leak_clean  = m_charts.LeaksClean();
         out.leak_advice = m_charts.LeakAdvice();
        }

      //+------------------------------------------------------------------+
      //| BLIND MODE REACHES THE TEXT HERE, not in the panel.              |
      //|                                                                  |
      //| A panel that formatted the clock itself would be a second place  |
      //| that has to know about blind mode - and the one that gets        |
      //| forgotten, leaving the date the mode exists to hide printed in   |
      //| the corner of the screen.                                        |
      //+------------------------------------------------------------------+
      if(m_blind != NULL && m_blind.IsOn())
        {
         out.blind      = true;
         out.clock_text = m_blind.MaskTime(out.now_msc, out.start_msc);
         out.symbol     = m_blind.MaskSymbol(out.symbol);
        }
      else
        {
         out.blind      = false;
         out.clock_text = (out.now_msc > 0 ? SSRFormatMsc(out.now_msc) : "--");
        }

      //--- the account, for the trade row
      if(m_acct != NULL)
        {
         out.balance        = m_acct.Balance();
         out.equity         = m_acct.Equity();
         out.floating       = m_acct.FloatingPL();
         out.open_positions = m_acct.OpenCount();
         out.risk_percent   = m_risk_percent;
         out.stop_points    = m_stop_points;
         out.can_trade      = (m_acct.Bid() > 0.0);
         //--- WHICH INSTRUMENT the buttons act on. On a multi-symbol
         //--- board the account follows the primary stream only, and
         //--- saying so is the difference between a limitation and a
         //--- trap.
         out.trade_symbol   = (c != NULL ? c.Symbol() : "");
        }

      if(m_strategies != NULL && m_strategies.Count() > 0)
         out.strategy_text = StrategyLine();
      return true;
     }

   //+------------------------------------------------------------------+
   //| One line the panel has room for: the busiest strategy's state,   |
   //| or a count when there are several.                               |
   //+------------------------------------------------------------------+
   string            StrategyLine(void)
     {
      if(m_strategies == NULL)
         return "";
      int n = m_strategies.Count();
      if(n == 0)
         return "";
      if(n == 1)
        {
         CSSRStrategy *s = m_strategies.At(0);
         return (s == NULL ? "" : s.Name() + ": " + s.Status());
        }
      return StringFormat("%d strategies running", n);
     }

   //--- verbs, every one of them fanned out ---------------------------
   virtual bool      Play(void) override
     { return (m_group != NULL && m_group.Play()); }

   virtual bool      Pause(void) override
     { return (m_group != NULL && m_group.Pause()); }

   virtual bool      Reset(void) override
     {
      if(m_group == NULL)
         return false;
      bool ok = true;
      for(int i = 0; i < m_group.Count(); i++)
         if(!m_group.At(i).Reset())
            ok = false;
      //--- and the master goes back with them, or it would keep
      //--- reporting a time no stream is at any more
      m_group.Align();
      return ok;
     }

   virtual bool      StepBars(const int bars) override
     { return (m_group != NULL && m_group.StepBars(bars)); }

   virtual bool      StepBack(const int bars) override
     { return (m_group != NULL && m_group.StepBackward(bars)); }

   virtual bool      JumpTo(const long msc) override
     { return (m_group != NULL && m_group.JumpTo(msc)); }

   virtual bool      SeekTo(const long msc) override
     { return (m_group != NULL && m_group.SeekAllTo(msc)); }

   virtual bool      Restart(void) override
     { return (m_group != NULL && m_group.Restart()); }

   virtual bool      SetSpeedX100(const long speed) override
     {
      if(m_group == NULL)
         return false;
      m_group.SetSpeedX100(speed);
      return true;
     }

   //+------------------------------------------------------------------+
   //| Fidelity is PER STREAM, because it describes the data each one   |
   //| actually has. Forcing full-tick on a board where one instrument  |
   //| has no tick history would claim a fidelity that does not exist   |
   //| there - so each stream is asked, and the answer may differ.      |
   //+------------------------------------------------------------------+
   virtual bool      SetFidelity(const ENUM_SSR_FIDELITY f) override
     {
      if(m_group == NULL)
         return false;
      bool any = false;
      for(int i = 0; i < m_group.Count(); i++)
         if(m_group.At(i).SetFidelity(f))
            any = true;
      return any;
     }

   //--- these belong to the primary stream's own chart set
   virtual bool      Bookmark(const string label) override
     {
      CSSRReplayController *c = Primary();
      if(c == NULL || !c.Bookmark(label))
         return false;

      //--- ...and put it where the user can see it. A stored bookmark
      //--- that leaves no mark is indistinguishable from one that was
      //--- never stored - which is exactly how it was reported.
      if(m_charts != NULL)
         m_charts.MarkTime(SSRToTime(c.Now()), "bookmark " + label,
                           SSR_C_ACCENT);
      return true;
     }

   virtual bool      SavePosition(void) override
     {
      if(m_group == NULL)
         return false;
      bool ok = true;
      for(int i = 0; i < m_group.Count(); i++)
         if(!m_group.At(i).SavePosition())
            ok = false;
      return ok;
     }

   virtual bool      ResumePosition(void) override
     {
      CSSRReplayController *c = Primary();
      if(c == NULL || !c.ResumePosition())
         return false;
      //--- and the rest of the board follows it, or resuming a session
      //--- would leave three charts where they were
      return m_group.SeekAllTo(c.Now());
     }

   virtual bool      FollowCharts(void) override
     { return (m_charts != NULL && m_charts.FollowAll() > 0); }

   virtual bool      HideOriginSymbol(void) override
     { return (m_charts != NULL && m_charts.Leak().HideOrigin()); }

   //================================================================
   //  TRADING
   //
   //  Sized from risk, never from a lot count typed into a panel. A
   //  trader practising position sizing is practising the thing that
   //  decides whether the rest of it matters, and a panel offering
   //  "1.00 lots" teaches the opposite lesson.
   //
   //  THE STOP IS THE USER'S. These buttons place a market order with
   //  no stop, because a panel that invented one would be inventing
   //  the risk figure too. Risk sizing needs a stop, so without one
   //  the order is refused and says why.
   //================================================================
   virtual bool      SetRiskPercent(const double pct) override
     {
      if(pct <= 0.0 || pct > 100.0)
        { m_trade_error = "risk must be between 0 and 100 percent"; return false; }
      m_risk_percent = pct;
      return true;
     }

   //--- the stop distance the size is computed from. Zero means the
   //--- buttons refuse, which is the correct behaviour and not a bug.
   virtual bool      SetStopPoints(const double pts) override
     {
      if(pts < 0.0)
        { m_trade_error = "a stop distance cannot be negative"; return false; }
      m_stop_points = pts;
      return true;
     }

   //--- the target is not on the base port: nothing else needs it, and
   //--- adding it there would oblige every other port to carry a field
   //--- it has no use for
   bool              SetTpPoints(const double pts)
     {
      if(pts < 0.0)
         return false;
      m_tp_points = pts;
      return true;
     }
   double            TpPoints(void) { return m_tp_points; }

   virtual bool      Buy(void) override  { return Market(SSR_ORDER_BUY); }
   virtual bool      Sell(void) override { return Market(SSR_ORDER_SELL); }

   virtual bool      CloseAll(void) override
     {
      m_trade_error = "";
      if(m_acct == NULL)
        { m_trade_error = "no account"; return false; }
      return (m_acct.CloseAll() > 0);
     }

   //--- move every open stop to its entry. One press, because the
   //--- moment a trader wants this they want it now.
   virtual bool      BreakEvenAll(void) override
     {
      m_trade_error = "";
      if(m_acct == NULL)
        { m_trade_error = "no account"; return false; }
      int moved = 0, total = m_acct.Total();
      for(int i = 0; i < total; i++)
        {
         SSRVirtualPosition p;
         if(m_acct.At(i, p) && p.IsOpen() && m_acct.BreakEven(p.ticket))
            moved++;
        }
      if(moved == 0)
         m_trade_error = "nothing open to move";
      return (moved > 0);
     }

   virtual string    TradeError(void) override { return m_trade_error; }

   //================================================================
   //  SESSIONS
   //================================================================
   virtual int       SessionCount(void) override
     {
      if(m_sessions == NULL)
         return 0;
      return m_sessions.List(m_names);
     }

   virtual string    SessionName(const int i) override
     { return (i >= 0 && i < ArraySize(m_names) ? m_names[i] : ""); }

   virtual string    SessionSummary(const int i) override
     {
      if(m_sessions == NULL || i < 0 || i >= ArraySize(m_names))
         return "";
      string summary = "";
      if(!m_sessions.Peek(m_names[i], summary))
         return m_names[i] + "  (unreadable: " + m_sessions.LastError() + ")";
      return summary;
     }

   virtual bool      SaveSession(const string name) override
     {
      m_session_error = "";
      if(m_sessions == NULL)
        { m_session_error = "sessions are not available"; return false; }
      if(name == "")
        { m_session_error = "a session needs a name"; return false; }
      SSRSessionSettings set;
      set.Init();
      //--- the panel knows none of the settings; the host owns them,
      //--- so what is written here is the transport-level state only.
      //--- A host that wants the full set calls the manager directly.
      set.slot = (m_sink != NULL ? m_sink.Slot() : 1);
      if(!m_sessions.Save(name, set))
        { m_session_error = m_sessions.LastError(); return false; }
      return true;
     }

   virtual bool      LoadSession(const string name) override
     {
      m_session_error = "";
      if(m_sessions == NULL)
        { m_session_error = "sessions are not available"; return false; }
      if(!m_sessions.Restore(name))
        { m_session_error = m_sessions.LastError(); return false; }
      //--- warnings are NOT swallowed by a successful load: the point
      //--- of Phase 12 was that a resume against changed history says so
      if(m_sessions.HadWarnings())
         m_session_error = m_sessions.Warnings();
      return true;
     }

   virtual string    SessionError(void) override { return m_session_error; }

private:
   //+------------------------------------------------------------------+
   //| A market order, SIZED FROM RISK - and refused without a stop.    |
   //|                                                                  |
   //| This is a product decision, not a limitation. Without a stop     |
   //| there is no risk figure, so there is no lot size either, and     |
   //| every alternative is worse:                                      |
   //|                                                                  |
   //|   - a default lot size teaches position sizing does not matter   |
   //|   - a default stop makes up the number the trade is judged on    |
   //|   - trading anyway and calling it "1% risk" is simply false      |
   //|                                                                  |
   //| A tool for learning to trade should not let its own panel be     |
   //| the one place where a trade is taken without knowing the risk.   |
   //+------------------------------------------------------------------+
   bool              Market(const ENUM_SSR_ORDER type)
     {
      m_trade_error = "";
      if(m_acct == NULL)
        { m_trade_error = "no account"; return false; }
      if(m_acct.Bid() <= 0.0)
        { m_trade_error = "no price yet - let the replay run first"; return false; }
      if(m_stop_points <= 0.0)
        {
         m_trade_error = "set a stop distance first - the size comes from "
                         "the risk, and the risk needs a stop";
         return false;
        }

      //--- the ENGINE's point, not a fresh symbol lookup. Asking
      //--- MetaTrader again could answer for a symbol the account is
      //--- not actually priced against, and the stop would be off by
      //--- a factor of ten with nothing to show for it.
      bool   is_long = (type == SSR_ORDER_BUY);
      double dist    = m_stop_points * m_acct.Point();
      double sl   = (is_long ? m_acct.Bid() - dist : m_acct.Ask() + dist);
      if(sl <= 0.0)
        { m_trade_error = "that stop falls below zero"; return false; }

      //--- and the target, when one has been set. Zero still means "no
      //--- target", so an order without one behaves exactly as before.
      double tp = 0.0;
      if(m_tp_points > 0.0)
        {
         double tdist = m_tp_points * m_acct.Point();
         tp = (is_long ? m_acct.Ask() + tdist : m_acct.Bid() - tdist);
         if(tp <= 0.0)
            tp = 0.0;
        }

      long t = m_acct.OpenWithRisk(type, m_risk_percent, sl, tp, "");
      if(t <= 0)
        { m_trade_error = m_acct.LastError(); return false; }
      return true;
     }
  };

#endif // SSR_GROUP_PORT_MQH
//+------------------------------------------------------------------+
