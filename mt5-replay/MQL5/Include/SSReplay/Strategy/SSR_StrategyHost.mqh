//+------------------------------------------------------------------+
//|                                           SSR_StrategyHost.mqh   |
//|                  SS Replay - Running Strategies (L3)             |
//|                                                                  |
//|  Turns the replay stream into the two hooks a strategy actually  |
//|  wants - "a bar closed" and "a tick arrived" - and keeps every    |
//|  strategy's trades separable from every other's.                 |
//|                                                                  |
//|  WHY OnBar IS NOT JUST "OnTick, SOMETIMES"                       |
//|                                                                  |
//|  The commonest backtesting bug after look-ahead is acting on a   |
//|  bar that is still forming: the signal fires, the bar goes on to |
//|  close somewhere else, and the backtest records a trade the      |
//|  strategy would never have taken live. So OnBar fires only when  |
//|  a bar of the strategy's timeframe has CLOSED, and by then       |
//|  shift 1 is finished and safe to read.                           |
//|                                                                  |
//|  Core knows none of this. This class is a CSSRTickObserver like  |
//|  any other, and the replay engine cannot tell a strategy from a  |
//|  chart.                                                          |
//+------------------------------------------------------------------+
#ifndef SSR_STRATEGY_HOST_MQH
#define SSR_STRATEGY_HOST_MQH

#include "../Common/SSR_Types.mqh"
#include "../Common/SSR_Time.mqh"
#include "../Core/SSR_ITickObserver.mqh"
#include "../Trading/SSR_TradingEngine.mqh"
#include "../Trading/SSR_Statistics.mqh"
#include "SSR_IStrategy.mqh"
#include "SSR_MarketView.mqh"

#define SSR_MAX_STRATEGIES   8

//+------------------------------------------------------------------+
class CSSRStrategyHost : public CSSRTickObserver
  {
private:
   CSSRStrategy       *m_strat[SSR_MAX_STRATEGIES];      // not owned
   CSSRStrategyBroker  m_broker[SSR_MAX_STRATEGIES];
   CSSRStrategyContext m_ctx[SSR_MAX_STRATEGIES];
   ENUM_TIMEFRAMES     m_tf[SSR_MAX_STRATEGIES];
   long                m_last_bar[SSR_MAX_STRATEGIES];   // its last CLOSED bar
   int                 m_count;

   CSSRMarketView     *m_view;      // not owned; shared by all of them
   CSSRTradingEngine  *m_acct;      // not owned
   ulong               m_seed;
   bool                m_started;
   string              m_last_error;

   long                m_bar_calls;
   long                m_tick_calls;

public:
                     CSSRStrategyHost(void)
     : m_count(0), m_view(NULL), m_acct(NULL), m_seed(1),
       m_started(false), m_last_error(""), m_bar_calls(0), m_tick_calls(0)
     {
      for(int i = 0; i < SSR_MAX_STRATEGIES; i++)
        {
         m_strat[i]    = NULL;
         m_tf[i]       = PERIOD_M1;
         m_last_bar[i] = SSR_INVALID_TIME;
        }
     }

   virtual string    Name(void) override { return "strategy-host"; }

   void              Attach(CSSRMarketView *v, CSSRTradingEngine *a)
     { m_view = v; m_acct = a; }

   //--- the session's seed, so a strategy that needs randomness is
   //--- still reproducible. Each strategy gets its own stream derived
   //--- from it, or two strategies would consume each other's numbers
   //--- and adding one would change the results of the others.
   void              SetSeed(const ulong s) { m_seed = (s == 0 ? 1 : s); }

   string            LastError(void) { return m_last_error; }
   int               Count(void)     { return m_count; }
   long              BarCalls(void)  { return m_bar_calls; }
   long              TickCalls(void) { return m_tick_calls; }

   //--- a stable number from a name. Mixed with the session seed so
   //--- each strategy gets its own stream: sharing one would mean
   //--- that adding a strategy changed what the others did.
   static ulong      NameHash(const string name)
     {
      ulong h = 0xCBF29CE484222325;
      int   n = StringLen(name);
      for(int i = 0; i < n; i++)
        {
         h ^= (ulong)StringGetCharacter(name, i);
         h *= 0x100000001B3;
        }
      return (h == 0 ? 1 : h);
     }

   CSSRStrategy     *At(const int i)
     { return (i >= 0 && i < m_count ? m_strat[i] : NULL); }

   //+------------------------------------------------------------------+
   //| Register a strategy and the timeframe its OnBar follows.         |
   //+------------------------------------------------------------------+
   bool              Add(CSSRStrategy *s, const ENUM_TIMEFRAMES tf)
     {
      m_last_error = "";
      if(s == NULL)
        { m_last_error = "null strategy"; return false; }
      if(m_count >= SSR_MAX_STRATEGIES)
        { m_last_error = "too many strategies"; return false; }
      if(!SSRIsSupportedTimeframe(tf))
        { m_last_error = "unsupported timeframe"; return false; }
      if(s.Name() == "")
        {
         //--- refused, because trades tagged with nothing cannot be
         //--- told apart afterwards, and unattributable results are
         //--- worse than no results
         m_last_error = "a strategy must have a name to be tagged by";
         return false;
        }
      for(int i = 0; i < m_count; i++)
         if(m_strat[i].Name() == s.Name())
           {
            m_last_error = "two strategies named " + s.Name() +
                           " - their trades could not be told apart";
            return false;
           }

      int k = m_count++;
      m_strat[k]    = s;
      m_tf[k]       = tf;
      m_last_bar[k] = SSR_INVALID_TIME;

      m_broker[k].Attach(m_acct, s.Name());
      m_ctx[k].market = m_view;
      m_ctx[k].broker = GetPointer(m_broker[k]);
      //--- a per-strategy stream, mixed from the session seed and the
      //--- name, so the order strategies were added in cannot change
      //--- what any of them does
      m_ctx[k].rng.Seed(m_seed ^ NameHash(s.Name()));
      s.Bind(GetPointer(m_ctx[k]));
      return true;
     }

   void              Clear(void)
     {
      for(int i = 0; i < SSR_MAX_STRATEGIES; i++)
         m_strat[i] = NULL;
      m_count = 0;
     }

   //================================================================
   //  OBSERVER CONTRACT
   //
   //  Registration order matters here as much as anywhere: this host
   //  must come AFTER the market view, so that by the time a strategy
   //  is asked what it thinks, the view already holds the bar.
   //================================================================
   virtual void      OnSessionStart(const string symbol, const int digits,
                                    const double point, const long start_msc) override
     {
      for(int i = 0; i < m_count; i++)
        {
         m_last_bar[i] = SSR_INVALID_TIME;
         m_broker[i].Attach(m_acct, m_strat[i].Name());
        }
      m_started = false;
     }

   virtual void      OnTicks(const MqlTick &ticks[], const int count) override
     {
      if(count <= 0 || m_view == NULL)
         return;

      if(!m_started)
        {
         for(int i = 0; i < m_count; i++)
            if(m_strat[i].IsEnabled())
               m_strat[i].OnStart();
         m_started = true;
        }

      long now = ticks[count - 1].time_msc;

      for(int i = 0; i < m_count; i++)
        {
         if(!m_strat[i].IsEnabled())
            continue;

         //--- THE BAR HOOK FIRST. A strategy that decides on the close
         //--- of a bar and manages on ticks expects the decision to
         //--- have been made before the management runs.
         long bar_open = SSRBarOpenMsc(now, m_tf[i]);
         if(m_last_bar[i] == SSR_INVALID_TIME)
           {
            //--- the first bar we ever see is one we joined PART WAY
            //--- through. Its close is not ours to act on, so it is
            //--- adopted silently and the hook waits for the next.
            m_last_bar[i] = bar_open;
           }
         else if(bar_open > m_last_bar[i])
           {
            m_last_bar[i] = bar_open;
            m_bar_calls++;
            m_strat[i].OnBar();
           }

         m_tick_calls++;
         m_strat[i].OnTick();
        }
     }

   virtual void      OnRewind(const long msc) override
     {
      for(int i = 0; i < m_count; i++)
        {
         //--- the bar we were waiting to close may not have happened
         m_last_bar[i] = SSR_INVALID_TIME;
         m_strat[i].OnRewind(msc);
        }
     }

   void              StopAll(void)
     {
      for(int i = 0; i < m_count; i++)
         m_strat[i].OnStop();
      m_started = false;
     }

   //================================================================
   //  RESULTS, PER STRATEGY
   //================================================================
   bool              StatsFor(const int i, CSSRStatsEngine *stats,
                              SSRStatistics &out)
     {
      out.Init();
      if(stats == NULL || i < 0 || i >= m_count)
         return false;
      stats.ComputeFor(m_strat[i].Name(), out);
      return true;
     }

   //--- one line per strategy, carrying the same caveat the whole
   //--- account's numbers carry. A strategy's profit factor computed
   //--- from assumed intrabar order is no more quotable than anyone
   //--- else's.
   string            Report(CSSRStatsEngine *stats)
     {
      if(m_count == 0)
         return "no strategies";
      string s = "";
      for(int i = 0; i < m_count; i++)
        {
         SSRStatistics st;
         if(!StatsFor(i, stats, st))
            continue;
         s += StringFormat("%s%-16s %s", (s == "" ? "" : "\n"),
                           m_strat[i].Name(), st.ToString());
         string c = st.Caveat();
         if(c != "")
            s += "\n                 " + c;
        }
      return s;
     }

   string            ToString(void)
     {
      return StringFormat("strategies[%d  bars=%I64d ticks=%I64d]",
                          m_count, m_bar_calls, m_tick_calls);
     }
  };

#endif // SSR_STRATEGY_HOST_MQH
//+------------------------------------------------------------------+
