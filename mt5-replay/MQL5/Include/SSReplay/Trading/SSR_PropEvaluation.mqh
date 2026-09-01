//+------------------------------------------------------------------+
//|                                           SSR_PropEvaluation.mqh |
//|            SS Replay - Prop Firm Evaluation Rules (L4/Trading)   |
//|                                                                  |
//|  WHAT THIS IS                                                    |
//|  A funded-account evaluation, run against the virtual account    |
//|  on replay time. Profit target, daily loss limit, overall        |
//|  drawdown, a minimum number of trading days, and a deadline.     |
//|  The four numbers every firm publishes and the two most people   |
//|  fail on.                                                        |
//|                                                                  |
//|  WHAT IT IS NOT                                                  |
//|  It is not any particular firm's rulebook. Firms differ on        |
//|  almost every detail - whether the daily loss is measured from    |
//|  balance or equity, whether the drawdown trails the peak or       |
//|  stays where it started, whether a day counts when a trade is     |
//|  opened or when one is closed. So the rules are INPUTS, and       |
//|  every choice this file makes on the user's behalf is written     |
//|  down in the panel and in the statement rather than buried here.  |
//|                                                                  |
//|  A REWIND VOIDS THE RUN, AND THAT IS THE POINT.                   |
//|  Every other observer in this project reconstructs its state on   |
//|  a rewind. This one refuses to. An evaluation you can rewind      |
//|  out of is not an evaluation - it is a score you edited - and     |
//|  reconstructing the drawdown across a rewind would produce a      |
//|  believable number that means nothing. Void, say so, and offer    |
//|  a reset.                                                        |
//+------------------------------------------------------------------+
#ifndef SSR_PROP_EVALUATION_MQH
#define SSR_PROP_EVALUATION_MQH

#include "../Common/SSR_Types.mqh"
#include "../Common/SSR_Time.mqh"
#include "../Core/SSR_ITickObserver.mqh"
#include "SSR_TradingEngine.mqh"

//--- one server day, in the milliseconds this engine counts in
//--- long, for the reason SSR_MSC_PER_DAY is: an int constant this
//--- size overflows on the first multiplication anybody writes
#define SSR_PROP_DAY_MSC   ((long)86400000)

//+------------------------------------------------------------------+
enum ENUM_SSR_PROP_STATE
  {
   SSR_PROP_OFF = 0,      // no evaluation configured
   SSR_PROP_RUNNING,      // in progress
   SSR_PROP_PASSED,       // every rule met
   SSR_PROP_FAILED,       // a rule was broken
   SSR_PROP_VOID          // the clock moved backwards; no verdict is honest
  };

string SSRPropStateName(const ENUM_SSR_PROP_STATE s)
  {
   switch(s)
     {
      case SSR_PROP_OFF:     return "off";
      case SSR_PROP_RUNNING: return "IN PROGRESS";
      case SSR_PROP_PASSED:  return "PASSED";
      case SSR_PROP_FAILED:  return "FAILED";
      case SSR_PROP_VOID:    return "VOID";
     }
   return "?";
  }

//+------------------------------------------------------------------+
//| The rules, as percentages of the starting balance.               |
//+------------------------------------------------------------------+
struct SSRPropRules
  {
   bool              enabled;
   double            start_balance;
   double            profit_target_pct;   // e.g. 8   -> +8%
   double            max_daily_loss_pct;  // e.g. 5   -> from the day's open equity
   double            max_total_loss_pct;  // e.g. 10
   bool              trailing;            // total loss trails the equity peak
   int               min_trading_days;    // days on which a trade happened
   int               max_days;            // 0 = no deadline

   void              Init(void)
     {
      enabled            = false;
      start_balance      = 10000.0;
      profit_target_pct  = 8.0;
      max_daily_loss_pct = 5.0;
      max_total_loss_pct = 10.0;
      trailing           = false;
      min_trading_days   = 3;
      max_days           = 30;
     }

   //--- the one line that says what the user actually signed up to
   string            ToString(void)
     {
      return StringFormat("target +%.1f%%  daily -%.1f%%  total -%.1f%% (%s)"
                          "  min %d day(s)%s",
                          profit_target_pct, max_daily_loss_pct,
                          max_total_loss_pct, (trailing ? "trailing" : "static"),
                          min_trading_days,
                          (max_days > 0
                           ? StringFormat("  within %d", max_days) : ""));
     }
  };

//+------------------------------------------------------------------+
class CSSRPropEvaluation : public CSSRTickObserver
  {
private:
   CSSRTradingEngine  *m_acct;          // not owned
   SSRPropRules        m_rules;
   ENUM_SSR_PROP_STATE m_state;
   string              m_reason;

   long                m_first_day;     // server day index the run began on
   long                m_day;           // the day currently open
   double              m_day_open_eq;   // equity when that day began
   double              m_day_low_eq;    // and the worst it has been since
   bool                m_day_traded;

   double              m_peak_eq;       // highest equity of the whole run
   double              m_low_eq;
   int                 m_trading_days;
   int                 m_total_days;
   int                 m_last_positions;

   bool                m_pause_pending;
   bool                m_started;

   double              Equity(void)
     { return (m_acct != NULL ? m_acct.Equity() : m_rules.start_balance); }

   //--- the number of positions the account has ever had. A day counts
   //--- as traded when this rises, which is "a trade was OPENED that
   //--- day" - stated here rather than assumed, because firms differ.
   int                 Positions(void)
     { return (m_acct != NULL ? m_acct.Total() : 0); }

   void                Finish(const ENUM_SSR_PROP_STATE s, const string why)
     {
      if(m_state != SSR_PROP_RUNNING)
         return;
      m_state         = s;
      m_reason        = why;
      m_pause_pending = true;
     }

   //+------------------------------------------------------------------+
   //| A day closed. Count it, and open the next one.                   |
   //+------------------------------------------------------------------+
   void                RollDay(const long to_day)
     {
      if(m_day_traded)
         m_trading_days++;
      m_total_days = (int)(to_day - m_first_day) + 1;

      m_day         = to_day;
      m_day_open_eq = Equity();
      m_day_low_eq  = m_day_open_eq;
      m_day_traded  = false;
     }

public:
                     CSSRPropEvaluation(void)
     : m_acct(NULL), m_state(SSR_PROP_OFF), m_reason(""),
       m_first_day(0), m_day(0), m_day_open_eq(0.0), m_day_low_eq(0.0),
       m_day_traded(false), m_peak_eq(0.0), m_low_eq(0.0),
       m_trading_days(0), m_total_days(0), m_last_positions(0),
       m_pause_pending(false), m_started(false)
     { m_rules.Init(); }

   virtual string    Name(void) override { return "prop"; }

   void              Attach(CSSRTradingEngine *a) { m_acct = a; }
   void              SetRules(SSRPropRules &r)    { m_rules = r; }
   void              Rules(SSRPropRules &out)     { out = m_rules; }

   ENUM_SSR_PROP_STATE State(void)  { return m_state; }
   string            StateName(void){ return SSRPropStateName(m_state); }
   string            Reason(void)   { return m_reason; }
   bool              IsOn(void)     { return m_rules.enabled; }
   bool              IsOver(void)
     { return (m_state == SSR_PROP_PASSED || m_state == SSR_PROP_FAILED ||
               m_state == SSR_PROP_VOID); }

   int               TradingDays(void) { return m_trading_days; }
   int               TotalDays(void)   { return m_total_days; }
   double            PeakEquity(void)  { return m_peak_eq; }

   //--- how far along the profit target is, 0..1 and clamped, because a
   //--- progress bar that can exceed its own width is a drawing bug
   double            TargetProgress(void)
     {
      if(!m_started || m_rules.profit_target_pct <= 0.0)
         return 0.0;
      double want = m_rules.start_balance * m_rules.profit_target_pct / 100.0;
      if(want <= 0.0)
         return 0.0;
      double got = Equity() - m_rules.start_balance;
      if(got <= 0.0)
         return 0.0;
      return (got >= want ? 1.0 : got / want);
     }

   double            ProfitPct(void)
     {
      if(m_rules.start_balance <= 0.0)
         return 0.0;
      return (Equity() - m_rules.start_balance) / m_rules.start_balance * 100.0;
     }

   //--- the equity level at which the run ends, so the user can see the
   //--- floor rather than compute it. Two floors; the nearer one bites.
   double            DailyFloor(void)
     { return m_day_open_eq - m_rules.start_balance * m_rules.max_daily_loss_pct / 100.0; }

   double            TotalFloor(void)
     {
      double room = m_rules.start_balance * m_rules.max_total_loss_pct / 100.0;
      return (m_rules.trailing ? m_peak_eq - room : m_rules.start_balance - room);
     }

   double            Floor(void)
     {
      double d = DailyFloor(), t = TotalFloor();
      return (d > t ? d : t);
     }

   //--- one line, already decided, so the panel does not have to think
   string            Headline(void)
     {
      if(!m_rules.enabled)
         return "";
      if(m_state == SSR_PROP_VOID)
         return "VOID - " + m_reason;
      if(m_state == SSR_PROP_PASSED || m_state == SSR_PROP_FAILED)
         return StateName() + " - " + m_reason;
      return StringFormat("%+.2f%% of %+.1f%%   day %d   floor %.2f",
                          ProfitPct(), m_rules.profit_target_pct,
                          m_trading_days, Floor());
     }

   //+------------------------------------------------------------------+
   //| Start over on the same rules.                                    |
   //+------------------------------------------------------------------+
   void              Reset(void)
     {
      m_state         = (m_rules.enabled ? SSR_PROP_RUNNING : SSR_PROP_OFF);
      m_reason        = "";
      m_pause_pending = false;
      m_started       = false;
      m_trading_days  = 0;
      m_total_days    = 0;
      m_peak_eq       = m_rules.start_balance;
      m_low_eq        = m_rules.start_balance;
      m_day_open_eq   = m_rules.start_balance;
      m_day_low_eq    = m_rules.start_balance;
      m_day_traded    = false;
      m_last_positions = Positions();
     }

   virtual void      OnSessionStart(const string symbol, const int digits,
                                    const double point, const long start_msc) override
     {
      Reset();
      m_first_day = start_msc / SSR_PROP_DAY_MSC;
      m_day       = m_first_day;
     }

   //+------------------------------------------------------------------+
   //| The whole evaluation, once per clock move.                       |
   //|                                                                  |
   //| Order matters. A day that ends in a breach must be judged on the |
   //| breach, not on the roll - so the limits are checked BEFORE the   |
   //| day boundary, using the day that was still open when it happened.|
   //+------------------------------------------------------------------+
   virtual void      OnClock(const long now_msc) override
     {
      if(!m_rules.enabled || m_state != SSR_PROP_RUNNING || m_acct == NULL)
         return;

      double eq = Equity();

      //--- the first clock of the run establishes the day, not the rules
      if(!m_started)
        {
         m_started     = true;
         m_first_day   = now_msc / SSR_PROP_DAY_MSC;
         m_day         = m_first_day;
         m_day_open_eq = eq;
         m_day_low_eq  = eq;
         m_peak_eq     = eq;
         m_low_eq      = eq;
         m_total_days  = 1;
         return;
        }

      if(eq > m_peak_eq) m_peak_eq = eq;
      if(eq < m_low_eq)  m_low_eq  = eq;
      if(eq < m_day_low_eq) m_day_low_eq = eq;

      int pos = Positions();
      if(pos > m_last_positions)
        {
         m_last_positions = pos;
         m_day_traded     = true;
        }

      //--- 1. the daily limit, against the equity this day opened with
      if(m_rules.max_daily_loss_pct > 0.0 && eq <= DailyFloor())
        {
         Finish(SSR_PROP_FAILED,
                StringFormat("daily loss limit: equity %.2f is at or below "
                             "%.2f (day opened %.2f)",
                             eq, DailyFloor(), m_day_open_eq));
         return;
        }

      //--- 2. the overall drawdown, trailing or static as configured
      if(m_rules.max_total_loss_pct > 0.0 && eq <= TotalFloor())
        {
         Finish(SSR_PROP_FAILED,
                StringFormat("max drawdown: equity %.2f is at or below %.2f "
                             "(%s from %.2f)",
                             eq, TotalFloor(),
                             (m_rules.trailing ? "trailing" : "static"),
                             (m_rules.trailing ? m_peak_eq : m_rules.start_balance)));
         return;
        }

      //--- 3. the day boundary
      long day_now = now_msc / SSR_PROP_DAY_MSC;
      if(day_now > m_day)
         RollDay(day_now);

      //--- 4. the deadline
      if(m_rules.max_days > 0 && m_total_days > m_rules.max_days)
        {
         Finish(SSR_PROP_FAILED,
                StringFormat("out of time: day %d of %d",
                             m_total_days, m_rules.max_days));
         return;
        }

      //--- 5. the target. Counted only once the minimum days are in -
      //--- which is how every firm writes it, and the rule most people
      //--- are surprised by.
      if(m_rules.profit_target_pct > 0.0 &&
         eq >= m_rules.start_balance * (1.0 + m_rules.profit_target_pct / 100.0))
        {
         int days = m_trading_days + (m_day_traded ? 1 : 0);
         if(days >= m_rules.min_trading_days)
            Finish(SSR_PROP_PASSED,
                   StringFormat("target reached: %+.2f%% on %d trading day(s)",
                                ProfitPct(), days));
        }
     }

   //+------------------------------------------------------------------+
   //| THE REWIND. No verdict survives it.                              |
   //+------------------------------------------------------------------+
   virtual void      OnRewind(const long msc) override
     {
      if(!m_rules.enabled || m_state != SSR_PROP_RUNNING)
         return;
      m_state  = SSR_PROP_VOID;
      m_reason = "the clock was moved backwards at " + SSRFormatMsc(msc) +
                 " - an evaluation you can rewind is a score you edited. "
                 "Press Reset to start it again.";
      m_pause_pending = true;
     }

   //--- consumed on the way out, as the interface requires
   virtual bool      PauseRequested(string &reason) override
     {
      if(!m_pause_pending)
         return false;
      m_pause_pending = false;
      reason = "evaluation " + StateName() + " - " + m_reason;
      return true;
     }

   //+------------------------------------------------------------------+
   //| For the statement, where the rules matter as much as the result. |
   //+------------------------------------------------------------------+
   string            Report(void)
     {
      if(!m_rules.enabled)
         return "";
      return StringFormat("%s | %s | equity %.2f, peak %.2f, low %.2f | "
                          "%d trading day(s) of %d elapsed%s",
                          StateName(), m_rules.ToString(),
                          Equity(), m_peak_eq, m_low_eq,
                          m_trading_days, m_total_days,
                          (m_reason == "" ? "" : " | " + m_reason));
     }
  };

#endif // SSR_PROP_EVALUATION_MQH
//+------------------------------------------------------------------+
