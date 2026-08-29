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
#include "../Core/SSR_MasterClock.mqh"
#include "../Mt5/SSR_CustomSymbolSink.mqh"
#include "../Chart/SSR_ChartManager.mqh"

//+------------------------------------------------------------------+
class CSSRGroupPort : public CSSRReplayPort
  {
private:
   CSSRReplayGroup      *m_group;    // not owned
   CSSRCustomSymbolSink *m_sink;     // the PRIMARY stream's sink; may be NULL
   CSSRChartManager     *m_charts;   // the primary stream's charts; may be NULL

   CSSRReplayController *Primary(void)
     { return (m_group != NULL ? m_group.At(0) : NULL); }

public:
                     CSSRGroupPort(void)
     : m_group(NULL), m_sink(NULL), m_charts(NULL) {}

   void              Attach(CSSRReplayGroup *g,
                            CSSRCustomSymbolSink *sink = NULL,
                            CSSRChartManager *charts = NULL)
     {
      m_group  = g;
      m_sink   = sink;
      m_charts = charts;
     }

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
      return true;
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
      return (c != NULL && c.Bookmark(label));
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
  };

#endif // SSR_GROUP_PORT_MQH
//+------------------------------------------------------------------+
