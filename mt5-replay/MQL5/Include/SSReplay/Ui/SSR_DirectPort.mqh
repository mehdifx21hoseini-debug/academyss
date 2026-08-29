//+------------------------------------------------------------------+
//|                                               SSR_DirectPort.mqh |
//|                  SS Replay - In-Process Port Implementation (UI) |
//|                                                                  |
//|  Wires the panel to a controller living in the same program.     |
//|                                                                  |
//|  This is the whole reason the port exists: today the engine and  |
//|  the panel share a process, tomorrow the engine moves into a     |
//|  Service and the panel becomes an indicator. Swapping this class |
//|  for an IPC one is the entire change - the panel never learns    |
//|  which side of the wire the engine is on.                        |
//+------------------------------------------------------------------+
#ifndef SSR_DIRECT_PORT_MQH
#define SSR_DIRECT_PORT_MQH

#include "SSR_ReplayPort.mqh"
#include "../Core/SSR_ReplayController.mqh"
#include "../Mt5/SSR_CustomSymbolSink.mqh"
#include "../Chart/SSR_ChartManager.mqh"

//+------------------------------------------------------------------+
class CSSRDirectPort : public CSSRReplayPort
  {
private:
   CSSRReplayController *m_ctrl;    // not owned
   CSSRCustomSymbolSink *m_sink;    // not owned; may be NULL
   CSSRChartManager     *m_charts;  // not owned; may be NULL

public:
                     CSSRDirectPort(void) : m_ctrl(NULL), m_sink(NULL), m_charts(NULL) {}

   void              Attach(CSSRReplayController *ctrl,
                            CSSRCustomSymbolSink *sink = NULL,
                            CSSRChartManager *charts = NULL)
     {
      m_ctrl   = ctrl;
      m_sink   = sink;
      m_charts = charts;
     }

   virtual string    Name(void) override        { return "direct"; }
   virtual bool      IsConnected(void) override { return (m_ctrl != NULL); }

   //+------------------------------------------------------------------+
   virtual bool      ReadState(SSRUiState &out) override
     {
      out.Init();
      if(m_ctrl == NULL)
         return false;

      out.connected        = true;
      out.status           = m_ctrl.Status();
      out.now_msc          = m_ctrl.Now();
      out.start_msc        = m_ctrl.StartMsc();
      out.end_msc          = m_ctrl.EndMsc();
      out.progress         = m_ctrl.Progress();
      out.speed_x100       = m_ctrl.SpeedX100();
      out.fidelity           = m_ctrl.Fidelity();
      out.fidelity_effective = m_ctrl.EffectiveFidelity();
      out.fidelity_note      = m_ctrl.FidelityReason();

      SSRPerfSnapshot perf;
      m_ctrl.PerfInto(perf);
      out.perf_calibrated = perf.calibrated;
      out.us_per_tick     = perf.us_per_tick;
      out.pump_p95_ms     = perf.pump_p95_ms;
      out.ticks_emitted    = m_ctrl.TicksEmitted();
      out.bars_consumed    = m_ctrl.BarsConsumed();
      out.guard_violations   = m_ctrl.Violations();
      out.bookmarks          = m_ctrl.BookmarkCount();
      out.has_saved_position = m_ctrl.HasSavedPosition();
      out.checkpoints        = m_ctrl.Snapshots().Count();
      out.last_error       = m_ctrl.LastError();
      out.last_error_text  = m_ctrl.LastErrorText();
      out.pause_reason     = m_ctrl.PauseReason();
      out.streams          = 1;
      out.skew_msc         = 0;
      //--- this port has no account and no blind mode, and says so
      //--- rather than leaving the panel to guess from zeros
      out.clock_text       = (m_ctrl.Now() > 0 ? SSRFormatMsc(m_ctrl.Now()) : "--");
      out.blind            = false;
      out.can_trade        = false;

      //--- show the REPLAY symbol, not the origin. The user is looking
      //--- at a chart of the replay symbol; naming the origin here
      //--- would invite them to open the wrong one.
      if(m_sink != NULL)
        {
         out.symbol = m_sink.ReplaySymbol();
         SSRSymbolStats st;
         m_sink.Manager().StatsInto(st);
         //--- ticks the terminal refused. Counted since Phase 3 but never
         //--- shown until now: a silent shortfall is missing price data.
         out.ticks_rejected = st.ticks_rejected;
        }
      else
         out.symbol = m_ctrl.Symbol();

      if(m_charts != NULL)
        {
         out.leak_clean  = m_charts.LeaksClean();
         out.leak_advice = m_charts.LeakAdvice();
        }
      return true;
     }

   //--- verbs -------------------------------------------------------
   virtual bool      Play(void) override
     { return (m_ctrl != NULL && m_ctrl.Play()); }

   virtual bool      Pause(void) override
     { return (m_ctrl != NULL && m_ctrl.Pause()); }

   virtual bool      Reset(void) override
     { return (m_ctrl != NULL && m_ctrl.Reset()); }

   virtual bool      StepBars(const int bars) override
     { return (m_ctrl != NULL && m_ctrl.StepBars(bars) >= 0); }

   virtual bool      StepBack(const int bars) override
     { return (m_ctrl != NULL && m_ctrl.StepBackward(bars)); }

   virtual bool      JumpTo(const long msc) override
     { return (m_ctrl != NULL && m_ctrl.JumpTo(msc)); }

   virtual bool      Restart(void) override
     { return (m_ctrl != NULL && m_ctrl.Restart()); }

   virtual bool      Bookmark(const string label) override
     { return (m_ctrl != NULL && m_ctrl.Bookmark(label)); }

   virtual bool      SavePosition(void) override
     { return (m_ctrl != NULL && m_ctrl.SavePosition()); }

   virtual bool      ResumePosition(void) override
     { return (m_ctrl != NULL && m_ctrl.ResumePosition()); }

   virtual bool      SeekTo(const long msc) override
     { return (m_ctrl != NULL && m_ctrl.SeekTo(msc)); }

   virtual bool      SetSpeedX100(const long speed) override
     { return (m_ctrl != NULL && m_ctrl.SetSpeedX100(speed)); }

   virtual bool      SetFidelity(const ENUM_SSR_FIDELITY f) override
     { return (m_ctrl != NULL && m_ctrl.SetFidelity(f)); }

   virtual bool      FollowCharts(void) override
     { return (m_charts != NULL && m_charts.FollowAll() > 0); }

   virtual bool      HideOriginSymbol(void) override
     { return (m_charts != NULL && m_charts.Leak().HideOrigin()); }
  };

#endif // SSR_DIRECT_PORT_MQH
//+------------------------------------------------------------------+
