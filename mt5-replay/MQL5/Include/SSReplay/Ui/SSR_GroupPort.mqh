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
#include "../Trading/SSR_Journal.mqh"
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
   CSSRJournal          *m_journal;      // not owned; may be NULL
   bool                  m_line_long;    // which side Flip last chose
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
       m_lines(NULL), m_journal(NULL), m_line_long(true),
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

         //+------------------------------------------------------------------+
         //| WHAT THE LINES SAY, AND WHAT PRESSING BUY WOULD COST.            |
         //|                                                                  |
         //| The side is read from the geometry rather than asked of the      |
         //| user: stop below price and target above is a long. The panel     |
         //| then dims the other button, so the chart and the dialog cannot   |
         //| disagree about which trade is being set up.                      |
         //|                                                                  |
         //| The size comes from the trading engine's own preview, on the     |
         //| same fill price the order would use. Recomputing it here would   |
         //| be a second formula, and the second one is the one that drifts.  |
         //+------------------------------------------------------------------+
         out.bid            = m_acct.Bid();
         out.ask            = m_acct.Ask();
         out.price_digits   = m_acct.Digits();
         double pt          = PricePoint();
         if(pt > 0.0)
            out.spread_points = (out.ask - out.bid) / pt;

         if(m_lines != NULL && m_lines.IsArmed())
           {
            out.lines_armed = true;
            out.sl_price    = m_lines.SlPrice();
            out.tp_price    = m_lines.TpPrice();
            out.line_long   = (out.sl_price < out.bid);

            ENUM_SSR_ORDER side = (out.line_long ? SSR_ORDER_BUY : SSR_ORDER_SELL);
            double entry = 0.0;
            out.lot_from_risk = m_acct.PreviewLot(side, m_risk_percent,
                                                  out.sl_price, entry);
            if(out.lot_from_risk > 0.0 && entry > 0.0)
              {
               //--- money, not points: the number a person decides on.
               //--- Both sides come from the same lot and the same entry,
               //--- so the ratio below cannot be quietly inconsistent.
               double risk_dist = MathAbs(entry - out.sl_price);
               double rew_dist  = MathAbs(out.tp_price - entry);
               out.risk_money   = m_acct.MoneyFor(out.lot_from_risk, risk_dist);
               out.reward_money = m_acct.MoneyFor(out.lot_from_risk, rew_dist);
               if(risk_dist > 0.0)
                  out.rr = rew_dist / risk_dist;
              }
            //--- keep the legacy point fields in step, so anything still
            //--- reading them sees the lines rather than a stale stepper
            if(pt > 0.0)
              {
               out.stop_points = MathAbs(out.bid - out.sl_price) / pt;
               out.tp_points   = MathAbs(out.tp_price - out.bid) / pt;
              }
           }

         //--- THE OPEN POSITIONS, as rows. The panel shows them and puts
         //--- a close button on each, so a trade can be managed without
         //--- hunting the chart for its lines. Newest first, because the
         //--- trade being managed is almost always the trade just opened.
         int total = m_acct.Total();
         for(int pi = total - 1; pi >= 0 && out.pos_rows < 5; pi--)
           {
            SSRVirtualPosition vp;
            if(!m_acct.At(pi, vp) || vp.state != SSR_POS_OPEN)
               continue;
            int r = out.pos_rows++;
            out.pos_ticket[r] = vp.ticket;
            out.pos_text[r]   = StringFormat("%s %.2f @ %s",
                                (SSRIsLong(vp.type) ? "BUY" : "SELL"),
                                vp.volume,
                                DoubleToString(vp.open_price, out.price_digits));
            //--- MoneyFor returns a magnitude; the sign comes from which
            //--- way the price moved relative to the side
            double px    = (SSRIsLong(vp.type) ? out.bid : out.ask);
            double moved = (SSRIsLong(vp.type) ? px - vp.open_price
                                               : vp.open_price - px);
            out.pos_pl[r] = (moved >= 0 ? 1.0 : -1.0)
                            * m_acct.MoneyFor(vp.volume, MathAbs(moved));
           }
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

      //--- KEEP THE LINE AND THE NUMBER TELLING THE SAME STORY.
      //--- The stop is read back off the chart every tick, so a stepper
      //--- that only changed the number would be overwritten a moment
      //--- later and read as a dead button. Move the line instead; the
      //--- number then follows from it, which is the right direction.
      if(m_lines != NULL && m_lines.IsArmed() && m_acct != NULL &&
         m_acct.Bid() > 0.0 && pts > 0.0)
         m_lines.SetStopPoints(m_acct.Bid(), pts);

      return true;
     }

   void              AttachLines(CSSRTradeLines *lines) { m_lines = lines; }

   //+------------------------------------------------------------------+
   //| RECORD WHAT THE LINES SAY. DO NOT MOVE THEM.                     |
   //|                                                                  |
   //| The host reads the stop distance off the chart every pump and    |
   //| used to hand it to SetStopPoints - which moves the lines. Round  |
   //| trip: chart to number to chart, forty times a second, and the    |
   //| return leg was long-only, so a short setup was pushed back to    |
   //| the long side before the user could let go of the mouse.         |
   //|                                                                  |
   //| The poll needs the NUMBER, for sizing and for the panel. It has  |
   //| no business writing back to the thing it just read.              |
   //+------------------------------------------------------------------+
   void              NoteLineDistances(const double stop_pts, const double tp_pts,
                                       const bool is_long)
     {
      if(stop_pts > 0.0)
         m_stop_points = stop_pts;
      if(tp_pts > 0.0)
         m_tp_points = tp_pts;
      //--- and which way the lines currently point, so the panel's own
      //--- label agrees with the chart rather than with a stale button
      m_line_long = is_long;
     }

   //+------------------------------------------------------------------+
   //| THE LINE VERBS.                                                  |
   //|                                                                  |
   //| One button arms them, one clears them, one mirrors them across   |
   //| the price. Everything between those three presses is the mouse.  |
   //+------------------------------------------------------------------+
   virtual bool      ArmLines(void) override
     {
      m_trade_error = "";
      if(m_lines == NULL)
        { m_trade_error = "the chart lines are not available"; return false; }
      if(m_acct == NULL || m_acct.Bid() <= 0.0)
        { m_trade_error = "no price yet - let one tick through first"; return false; }

      //--- A DEFAULT THAT IS NOT INSIDE THE SPREAD.
      //--- Ten times the spread is a distance a person can see and then
      //--- drag; a fixed number of points is right on one instrument and
      //--- absurd on the next, which is exactly the hardcoded-symbol
      //--- logic this product is not allowed to contain.
      double pt = PricePoint();
      double spread_pts = (pt > 0.0 ? (m_acct.Ask() - m_acct.Bid()) / pt : 0.0);
      double stop_pts   = (m_stop_points > 0.0 ? m_stop_points
                                               : MathMax(10.0 * spread_pts, 10.0));
      bool ok = m_lines.ArmSide(m_acct.Bid(), stop_pts,
                                (m_tp_points > 0.0 && stop_pts > 0.0
                                 ? m_tp_points / stop_pts : 2.0),
                                m_line_long);
      if(!ok)
         m_trade_error = "could not place the lines on the chart";
      return ok;
     }

   virtual bool      ClearLines(void) override
     {
      m_trade_error = "";
      if(m_lines == NULL)
        { m_trade_error = "the chart lines are not available"; return false; }
      m_lines.Clear();
      return true;
     }

   virtual bool      FlipLines(void) override
     {
      m_line_long = !m_line_long;
      //--- unarmed, this is just a preference for the next Arm. Armed,
      //--- it has to re-place the lines, because their PRICES are what
      //--- the trade is sized and filled from - repainting them the
      //--- other colour would be a lie with a tidy appearance.
      if(m_lines != NULL && m_lines.IsArmed())
         return ArmLines();
      return true;
     }

   //--- one price step of the instrument the account trades. Asked of
   //--- the symbol, never assumed: a hardcoded 0.0001 is wrong on an
   //--- index, a metal, and every JPY pair.
   double            PricePoint(void)
     {
      if(m_acct == NULL)
         return 0.0;
      int d = m_acct.Digits();
      if(d < 0 || d > 10)
         return 0.0;
      return MathPow(10.0, -d);
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

   //+------------------------------------------------------------------+
   //| THE TRADE THE LINES DESCRIBE.                                    |
   //|                                                                  |
   //| One press instead of "read the lines, work out the side, find    |
   //| the matching button". The side is the geometry - stop below the  |
   //| price is a long - which is the same rule the panel paints, read  |
   //| here so there is exactly one place that knows it.                |
   //|                                                                  |
   //| The lines are cleared on success. Leaving them would mean the    |
   //| next press opens a second trade against a stop that belonged to  |
   //| the first, which is the kind of accident a practice tool must    |
   //| not be able to cause.                                            |
   //+------------------------------------------------------------------+
   virtual bool      OpenFromLines(void) override
     {
      m_trade_error = "";
      if(m_lines == NULL || !m_lines.IsArmed())
        { m_trade_error = "no lines on the chart yet"; return false; }
      if(m_acct == NULL || m_acct.Bid() <= 0.0)
        { m_trade_error = "no price yet"; return false; }

      double sl = m_lines.SlPrice();
      double tp = m_lines.TpPrice();
      bool   is_long = (sl < m_acct.Bid());

      //--- REFUSE A SETUP THAT MAKES NO SENSE, and say which one.
      //--- Both lines on the same side of the price is not a trade; it
      //--- is a stop that is already hit or a target already reached.
      if((is_long && tp <= m_acct.Bid()) || (!is_long && tp >= m_acct.Bid()))
        {
         m_trade_error = "the target is on the wrong side of the price - "
                         "drag it past the entry, or press Flip";
         return false;
        }

      //--- the exact prices the user dragged to - not a distance
      //--- recomputed from the bid, which would drift by the spread
      //--- and by every tick between the drag and the click
      bool ok = MarketAt(is_long ? SSR_ORDER_BUY : SSR_ORDER_SELL, sl, tp);
      //--- Disarm, not Clear. Clear also sweeps the position lines, and
      //--- one of those belongs to the order that was just placed.
      if(ok)
         m_lines.Disarm();
      return ok;
     }

   //+------------------------------------------------------------------+
   //| Close one position, from its row in the panel.                   |
   //+------------------------------------------------------------------+
   void              AttachJournal(CSSRJournal *j) { m_journal = j; }

   virtual bool      ExportStatement(string &path_out) override
     {
      path_out = "";
      m_trade_error = "";
      if(m_journal == NULL)
        { m_trade_error = "no journal attached"; return false; }
      if(m_journal.Count() <= 0)
        { m_trade_error = "no closed trades to report yet"; return false; }

      string stamp = TimeToString(TimeLocal(), TIME_DATE | TIME_MINUTES);
      StringReplace(stamp, ".", "");
      StringReplace(stamp, ":", "");
      StringReplace(stamp, " ", "-");
      string name = "SSReplay-" + stamp;
      if(!m_journal.ExportHtml(name))
        { m_trade_error = m_journal.LastError(); return false; }
      path_out = m_journal.LastPath();
      return true;
     }

   virtual bool      ClosePosition(const long ticket) override
     {
      m_trade_error = "";
      if(m_acct == NULL)
        { m_trade_error = "no account"; return false; }
      if(!m_acct.Close(ticket))
        { m_trade_error = m_acct.LastError(); return false; }
      return true;
     }

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
   //--- an order at EXPLICIT prices. Market() derives them from the
   //--- configured distances; the lines hand them over as dragged.
   bool              MarketAt(const ENUM_SSR_ORDER type,
                              const double sl, const double tp)
     {
      m_trade_error = "";
      if(m_acct == NULL)
        { m_trade_error = "no account"; return false; }
      if(m_acct.Bid() <= 0.0)
        { m_trade_error = "no price yet - let the replay run first"; return false; }
      if(sl <= 0.0)
        { m_trade_error = "no stop - the size comes from the risk, and "
                          "the risk needs a stop"; return false; }
      //--- tagged, because the statement has a Tag column and it came
      //--- back empty on the first real session. A column that is always
      //--- blank is either dead or a question the tool refused to answer;
      //--- this one can say how the trade was placed.
      long t = m_acct.OpenWithRisk(type, m_risk_percent, sl,
                                   (tp > 0.0 ? tp : 0.0), "lines");
      if(t <= 0)
        { m_trade_error = m_acct.LastError(); return false; }
      return true;
     }

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
