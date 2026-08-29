//+------------------------------------------------------------------+
//|                                              SSR_IStrategy.mqh   |
//|                  SS Replay - The Strategy Contract (L3)          |
//|                                                                  |
//|  What the academy's own methods plug into.                       |
//|                                                                  |
//|  A strategy here is NOT an Expert Advisor. It never touches      |
//|  OrderSend, never reads a chart, never calls TimeCurrent. It is  |
//|  handed a view of the past and a way to place virtual trades,    |
//|  and that is the entire surface. Everything it cannot do is a    |
//|  thing it cannot get wrong.                                      |
//|                                                                  |
//|  THREE RULES, EACH ENFORCED RATHER THAN REQUESTED                |
//|                                                                  |
//|  1. It cannot see the future. The view holds what was published  |
//|     and nothing else, so there is no bar to read by accident.    |
//|  2. It cannot reach a broker. The only trading surface is a      |
//|     facade over the virtual account, and there is no OrderSend   |
//|     below it. A misconfigured strategy loses imaginary money.    |
//|  3. It cannot be non-deterministic. The clock is the replay's    |
//|     and the randomness is seeded from the session, so the same   |
//|     session replays to the same trades. A strategy that reaches  |
//|     for TimeCurrent() or MathRand() breaks that, which is why    |
//|     both are provided here instead.                              |
//|                                                                  |
//|  WHAT IS DELIBERATELY NOT HERE                                   |
//|  Any actual trading logic. This phase builds the frame the       |
//|  academy's methods sit in; inventing a strategy to fill it       |
//|  would be putting words in the user's mouth.                     |
//+------------------------------------------------------------------+
#ifndef SSR_ISTRATEGY_MQH
#define SSR_ISTRATEGY_MQH

#include "../Common/SSR_Types.mqh"
#include "../Common/SSR_Time.mqh"
#include "../Common/SSR_Random.mqh"
#include "../Trading/SSR_TradingEngine.mqh"
#include "SSR_MarketView.mqh"

//+------------------------------------------------------------------+
//| The only way a strategy may trade.                               |
//|                                                                  |
//| A facade, not a subclass, so a strategy cannot reach past it to  |
//| the engine's rewind or session internals. Every order is TAGGED  |
//| with the strategy's name, which is what makes per-strategy       |
//| statistics possible without a second bookkeeping path.           |
//+------------------------------------------------------------------+
class CSSRStrategyBroker
  {
private:
   CSSRTradingEngine *m_acct;      // not owned
   string             m_tag;
   long               m_placed;
   long               m_refused;
   string             m_last_error;

public:
                     CSSRStrategyBroker(void)
     : m_acct(NULL), m_tag(""), m_placed(0), m_refused(0), m_last_error("") {}

   void              Attach(CSSRTradingEngine *a, const string tag)
     { m_acct = a; m_tag = tag; }

   string            Tag(void)        { return m_tag; }
   long              Placed(void)     { return m_placed; }
   long              Refused(void)    { return m_refused; }
   string            LastError(void)  { return m_last_error; }

   long              Buy(const double volume, const double sl = 0.0,
                         const double tp = 0.0)
     { return Send(SSR_ORDER_BUY, volume, sl, tp, 0.0); }

   long              Sell(const double volume, const double sl = 0.0,
                          const double tp = 0.0)
     { return Send(SSR_ORDER_SELL, volume, sl, tp, 0.0); }

   long              Pending(const ENUM_SSR_ORDER type, const double volume,
                             const double price, const double sl = 0.0,
                             const double tp = 0.0)
     { return Send(type, volume, sl, tp, price); }

   //--- size from risk rather than from a guess, using the same engine
   //--- the manual trader uses. Two sizing formulas would drift apart.
   long              BuyRisk(const double risk_percent, const double sl,
                             const double tp = 0.0)
     {
      if(m_acct == NULL)
        { m_last_error = "no account"; m_refused++; return 0; }
      long t = m_acct.OpenWithRisk(SSR_ORDER_BUY, risk_percent, sl, tp, m_tag);
      if(t > 0) m_placed++; else { m_refused++; m_last_error = m_acct.LastError(); }
      return t;
     }

   long              SellRisk(const double risk_percent, const double sl,
                              const double tp = 0.0)
     {
      if(m_acct == NULL)
        { m_last_error = "no account"; m_refused++; return 0; }
      long t = m_acct.OpenWithRisk(SSR_ORDER_SELL, risk_percent, sl, tp, m_tag);
      if(t > 0) m_placed++; else { m_refused++; m_last_error = m_acct.LastError(); }
      return t;
     }

   bool              Close(const long ticket)
     { return (m_acct != NULL && m_acct.Close(ticket)); }

   bool              ClosePartial(const long ticket, const double volume)
     { return (m_acct != NULL && m_acct.ClosePartial(ticket, volume)); }

   bool              Modify(const long ticket, const double sl, const double tp)
     { return (m_acct != NULL && m_acct.Modify(ticket, sl, tp)); }

   bool              BreakEven(const long ticket)
     { return (m_acct != NULL && m_acct.BreakEven(ticket)); }

   bool              Trail(const long ticket, const double points)
     { return (m_acct != NULL && m_acct.SetTrailing(ticket, points)); }

   //--- read-only account state. A strategy may look at its own
   //--- position; it may not reach the engine that holds it.
   double            Balance(void)  { return (m_acct != NULL ? m_acct.Balance() : 0.0); }
   double            Equity(void)   { return (m_acct != NULL ? m_acct.Equity() : 0.0); }
   int               OpenCount(void){ return (m_acct != NULL ? m_acct.OpenCount() : 0); }

   //--- how many of MY positions are open. A strategy sharing an
   //--- account with the trader (or with another strategy) must be
   //--- able to count its own, or it will close somebody else's.
   int               MyOpenCount(void)
     {
      if(m_acct == NULL)
         return 0;
      int n = 0, total = m_acct.Total();
      for(int i = 0; i < total; i++)
        {
         SSRVirtualPosition p;
         if(m_acct.At(i, p) && p.IsOpen() && p.tag == m_tag)
            n++;
        }
      return n;
     }

   //--- my nth open position, so a strategy can manage what it opened
   bool              MyPosition(const int nth, SSRVirtualPosition &out)
     {
      if(m_acct == NULL)
         return false;
      int seen = 0, total = m_acct.Total();
      for(int i = 0; i < total; i++)
        {
         SSRVirtualPosition p;
         if(!m_acct.At(i, p) || !p.IsOpen() || p.tag != m_tag)
            continue;
         if(seen == nth)
           { out = p; return true; }
         seen++;
        }
      return false;
     }

   int               CloseAllMine(void)
     {
      int closed = 0;
      //--- backwards: closing does not reorder the log, but a strategy
      //--- reading forward while the states change under it is the
      //--- kind of thing that works until it does not
      if(m_acct == NULL)
         return 0;
      for(int i = m_acct.Total() - 1; i >= 0; i--)
        {
         SSRVirtualPosition p;
         if(m_acct.At(i, p) && p.IsOpen() && p.tag == m_tag &&
            m_acct.Close(p.ticket))
            closed++;
        }
      return closed;
     }

private:
   long              Send(const ENUM_SSR_ORDER type, const double volume,
                          const double sl, const double tp, const double price)
     {
      m_last_error = "";
      if(m_acct == NULL)
        { m_last_error = "no account"; m_refused++; return 0; }
      long t = m_acct.Open(type, volume, sl, tp, price, m_tag);
      if(t > 0)
         m_placed++;
      else
        { m_refused++; m_last_error = m_acct.LastError(); }
      return t;
     }
  };

//+------------------------------------------------------------------+
//| Everything a strategy is given, in one object.                   |
//+------------------------------------------------------------------+
class CSSRStrategyContext
  {
public:
   CSSRMarketView     *market;      // not owned - the past, and only it
   CSSRStrategyBroker *broker;      // not owned - virtual trades only
   SSRRandom           rng;         // seeded from the session

                     CSSRStrategyContext(void) : market(NULL), broker(NULL)
     { rng.Seed(1); }

   //--- REPLAY time. Never TimeCurrent(): a strategy that reads the
   //--- wall clock stops being a function of the replay, and the same
   //--- session stops producing the same trades.
   long              Now(void)
     { return (market != NULL ? market.Now() : SSR_INVALID_TIME); }

   datetime          NowTime(void) { return SSRToTime(Now()); }

   //--- is the intrabar order under our feet real or invented?
   bool              IsSynthetic(void)
     { return (market == NULL || market.IsSynthetic()); }
  };

//+------------------------------------------------------------------+
//| The base every SS strategy derives from.                         |
//|                                                                  |
//| Deliberately small. A strategy overrides what it needs and        |
//| ignores the rest; the default of every hook is to do nothing,     |
//| which is the correct behaviour for a strategy that has not been   |
//| written yet.                                                      |
//+------------------------------------------------------------------+
class CSSRStrategy
  {
protected:
   CSSRStrategyContext *ctx;        // not owned; set by the host
   bool                 m_enabled;
   string               m_note;     // what it is doing, for the panel

public:
                     CSSRStrategy(void) : ctx(NULL), m_enabled(true), m_note("") {}
   virtual          ~CSSRStrategy(void) {}

   //--- MUST be overridden. A strategy with no name cannot have its
   //--- own statistics, because there is nothing to filter them by -
   //--- so the host REFUSES to register one, which is the same
   //--- guarantee a pure virtual would give and does not depend on
   //--- how the compiler treats an abstract class.
   virtual string    Name(void) { return ""; }

   void              Bind(CSSRStrategyContext *c) { ctx = c; }
   void              Enable(const bool on)        { m_enabled = on; }
   bool              IsEnabled(void)              { return m_enabled; }
   string            Note(void)                   { return m_note; }

   //--- lifecycle -----------------------------------------------------
   virtual void      OnStart(void) {}

   //+------------------------------------------------------------------+
   //| A new CLOSED bar of the strategy's own timeframe.                |
   //|                                                                  |
   //| The hook most strategies want, and the one that keeps them out   |
   //| of trouble: by the time it fires, the bar it describes is        |
   //| finished. Acting on shift 1 here is always safe.                 |
   //+------------------------------------------------------------------+
   virtual void      OnBar(void) {}

   //--- every tick, for strategies that manage intrabar. Whatever this
   //--- does on synthetic ticks rests on an invented order of prices,
   //--- and ctx.IsSynthetic() is how it can know.
   virtual void      OnTick(void) {}

   //--- the future was deleted; drop any state that described it
   virtual void      OnRewind(const long msc) {}

   virtual void      OnStop(void) {}

   //--- what the strategy is thinking, in one line, for the panel
   virtual string    Status(void) { return ""; }
  };

#endif // SSR_ISTRATEGY_MQH
//+------------------------------------------------------------------+
