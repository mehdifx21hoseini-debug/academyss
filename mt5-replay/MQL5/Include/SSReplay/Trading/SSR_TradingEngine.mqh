//+------------------------------------------------------------------+
//|                                          SSR_TradingEngine.mqh   |
//|                     SS Replay - Virtual Trading Engine (L2)      |
//|                                                                  |
//|  A complete simulated account that watches the replay stream.     |
//|  It reaches no broker: there is no OrderSend anywhere in this     |
//|  layer, and a grep proving that is part of the phase's tests.     |
//|                                                                  |
//|  THE STOP-AND-TARGET AMBIGUITY (design document risk R11)         |
//|                                                                  |
//|  When a single bar's range contains both a position's stop and    |
//|  its target, the outcome depends on which price came first -      |
//|  and on synthesised ticks that ORDER IS OUR ASSUMPTION, not the   |
//|  market's behaviour. A tool that resolves it in the trader's      |
//|  favour turns a coin flip into a winning strategy on paper.       |
//|                                                                  |
//|  So: the pessimistic outcome is taken, the trade is flagged       |
//|  ambiguous, and the statistics report what fraction of the        |
//|  results rest on that assumption. The user can then judge their   |
//|  own backtest instead of being quietly flattered by it.           |
//|                                                                  |
//|  REWIND CORRECTNESS                                               |
//|  Trades live in an append-only log. A rewind truncates the log    |
//|  and refolds the account, so a position opened in a future that   |
//|  was deleted ceases to have existed - rather than lingering as a  |
//|  balance nobody can explain.                                      |
//+------------------------------------------------------------------+
#ifndef SSR_TRADING_ENGINE_MQH
#define SSR_TRADING_ENGINE_MQH

#include "../Common/SSR_Types.mqh"
#include "../Common/SSR_Time.mqh"
#include "../Core/SSR_ITickObserver.mqh"
#include "SSR_TradeTypes.mqh"
#include "SSR_RiskEngine.mqh"
#include "../Common/SSR_SessionFile.mqh"

#define SSR_MAX_POSITIONS   512

//+------------------------------------------------------------------+
class CSSRTradingEngine : public CSSRTickObserver
  {
private:
   //--- the log IS the account; everything else is derived from it
   SSRVirtualPosition m_pos[SSR_MAX_POSITIONS];
   int                m_count;
   long               m_next_ticket;

   CSSRRiskEngine     m_risk;
   SSRExecutionModel  m_exec;

   string             m_symbol;
   int                m_digits;
   double             m_point;

   double             m_balance_initial;
   double             m_balance;          // realised only
   double             m_margin_per_lot;   // initial margin, one lot
   double             m_stopout_level;    // margin level % that forces a close
   long               m_stopouts;
   double             m_bid, m_ask;
   long               m_now_msc;

   //--- bar context for the current bar, set before its ticks arrive
   MqlRates           m_bar;
   bool               m_bar_valid;
   bool               m_bar_synthetic;

   long               m_ambiguous_count;
   string             m_last_error;

   double             Norm(const double v) { return NormalizeDouble(v, m_digits); }

   int                Find(const long ticket)
     {
      for(int i = 0; i < m_count; i++)
         if(m_pos[i].ticket == ticket)
            return i;
      return -1;
     }

   //--- the price a market order actually gets: the wrong side of the
   //--- spread, then slippage against you. Never in your favour.
   double            FillPrice(const bool is_long, const bool opening)
     {
      double slip = m_exec.slippage_points * m_point;
      if(opening)
         return is_long ? m_ask + slip : m_bid - slip;
      return is_long ? m_bid - slip : m_ask + slip;
     }

   double            RealisedOf(SSRVirtualPosition &p, const double price,
                                const double volume)
     {
      double move = (p.IsLong() ? price - p.open_price : p.open_price - price);
      return m_risk.RiskOf(volume, move) * (move < 0.0 ? -1.0 : 1.0);
     }

   //+------------------------------------------------------------------+
   //| Would this bar touch both the stop and the target?               |
   //|                                                                  |
   //| Asked BEFORE the bar's ticks are processed, which is the whole   |
   //| reason the observer contract delivers bar context first.         |
   //+------------------------------------------------------------------+
   bool              BarIsAmbiguousFor(SSRVirtualPosition &p)
     {
      if(!m_bar_valid || !m_bar_synthetic)
         return false;                     // real ticks carry real order
      if(p.sl <= 0.0 || p.tp <= 0.0)
         return false;                     // needs both to be ambiguous

      bool sl_in, tp_in;
      if(p.IsLong())
        {
         sl_in = (m_bar.low  <= p.sl);
         tp_in = (m_bar.high >= p.tp);
        }
      else
        {
         sl_in = (m_bar.high >= p.sl);
         tp_in = (m_bar.low  <= p.tp);
        }
      return (sl_in && tp_in);
     }

   //+------------------------------------------------------------------+
   //| Book one exit - partial or final - as a LEG.                     |
   //|                                                                  |
   //| Every path that reduces a position goes through here, so there   |
   //| is exactly one description of what an exit does to the account   |
   //| and exactly one thing for a rewind to undo. Before the leg is    |
   //| written the swap owed at the CURRENT size is fixed, because      |
   //| after it the size is different and the days already held at the  |
   //| old size must not be restated.                                   |
   //+------------------------------------------------------------------+
   bool              BookExit(const int i, const double price, const double volume,
                              const ENUM_SSR_CLOSE_REASON reason,
                              const bool closing, const bool ambiguous)
     {
      if(m_pos[i].leg_count >= SSR_MAX_TRADE_LEGS)
        {
         //--- only reachable on a partial: a close always has the slot
         //--- reserved for it. Refusing beats taking an exit that a
         //--- rewind could never undo.
         m_last_error = "too many exits on one position";
         return false;
        }

      AccrueSwap();                       // settle the swap at the old size

      double realised = RealisedOf(m_pos[i], price, volume);
      double fee      = m_exec.commission_per_lot * volume;

      int e = m_pos[i].leg_count++;
      m_pos[i].legs[e].Init();
      m_pos[i].legs[e].volume             = volume;
      m_pos[i].legs[e].price              = Norm(price);
      m_pos[i].legs[e].msc                = m_now_msc;
      m_pos[i].legs[e].realised           = realised;
      m_pos[i].legs[e].fee                = fee;
      m_pos[i].legs[e].closing            = closing;
      m_pos[i].legs[e].prev_swap_locked   = m_pos[i].swap_locked;
      m_pos[i].legs[e].prev_swap_from_msc = m_pos[i].swap_from_msc;
      m_pos[i].legs[e].prev_ambiguous     = m_pos[i].ambiguous;

      m_pos[i].profit     += realised;
      m_pos[i].commission += fee;
      m_pos[i].volume     -= volume;
      //--- swap is NOT added here: AccrueSwap() already moved it into the
      //--- balance as it accrued. Adding it again would pay it twice.
      m_balance           += realised - fee;

      //--- what is left starts accruing swap from now, at the new size
      m_pos[i].swap_locked   = m_pos[i].swap;
      m_pos[i].swap_from_msc = m_now_msc;

      if(closing)
        {
         m_pos[i].volume      = 0.0;
         m_pos[i].close_price = Norm(price);
         m_pos[i].close_msc   = m_now_msc;
         m_pos[i].reason      = reason;
         m_pos[i].state       = SSR_POS_CLOSED;
         if(ambiguous && !m_pos[i].ambiguous)
           {
            m_pos[i].ambiguous = true;
            m_ambiguous_count++;
           }
        }
      return true;
     }

   void              ClosePosition(const int i, const double price,
                                   const ENUM_SSR_CLOSE_REASON reason,
                                   const bool ambiguous = false)
     {
      //--- a close must never be refused, so the last leg slot belongs
      //--- to it: ClosePartial stops one short on purpose
      if(m_pos[i].leg_count >= SSR_MAX_TRADE_LEGS)
         m_pos[i].leg_count = SSR_MAX_TRADE_LEGS - 1;
      BookExit(i, price, m_pos[i].volume, reason, true, ambiguous);
     }

   //+------------------------------------------------------------------+
   //| Undo every leg that happened after `msc`.                        |
   //|                                                                  |
   //| Newest first, each one restoring exactly what it overwrote. A    |
   //| position scaled out of three times and then closed comes back    |
   //| at whatever size it actually had at the restored instant.        |
   //+------------------------------------------------------------------+
   void              UnwindLegsAfter(const int i, const long msc)
     {
      while(m_pos[i].leg_count > 0 &&
            m_pos[i].legs[m_pos[i].leg_count - 1].msc > msc)
        {
         int e = --m_pos[i].leg_count;

         m_pos[i].volume     += m_pos[i].legs[e].volume;
         m_pos[i].profit     -= m_pos[i].legs[e].realised;
         m_pos[i].commission -= m_pos[i].legs[e].fee;
         m_balance           -= m_pos[i].legs[e].realised - m_pos[i].legs[e].fee;

         m_pos[i].swap_locked   = m_pos[i].legs[e].prev_swap_locked;
         m_pos[i].swap_from_msc = m_pos[i].legs[e].prev_swap_from_msc;

         if(m_pos[i].legs[e].closing)
           {
            m_pos[i].state       = SSR_POS_OPEN;
            m_pos[i].close_price = 0.0;
            m_pos[i].close_msc   = SSR_INVALID_TIME;
            m_pos[i].reason      = SSR_CLOSE_NONE;
            if(m_pos[i].ambiguous && !m_pos[i].legs[e].prev_ambiguous)
              {
               m_pos[i].ambiguous = false;
               m_ambiguous_count--;
              }
           }
        }
     }

   void              UpdateExcursions(const int i)
     {
      double price = (m_pos[i].IsLong() ? m_bid : m_ask);
      double move  = (m_pos[i].IsLong() ? price - m_pos[i].open_price
                                        : m_pos[i].open_price - price);
      if(move < m_pos[i].mae) m_pos[i].mae = move;
      if(move > m_pos[i].mfe) m_pos[i].mfe = move;
     }

   void              ApplyTrailing(const int i)
     {
      if(m_pos[i].trail_points <= 0.0)
         return;
      double dist = m_pos[i].trail_points * m_point;
      if(m_pos[i].IsLong())
        {
         if(m_bid > m_pos[i].trail_peak)
            m_pos[i].trail_peak = m_bid;
         double want = Norm(m_pos[i].trail_peak - dist);
         if(want > m_pos[i].sl)
            m_pos[i].sl = want;
        }
      else
        {
         if(m_pos[i].trail_peak <= 0.0 || m_ask < m_pos[i].trail_peak)
            m_pos[i].trail_peak = m_ask;
         double want = Norm(m_pos[i].trail_peak + dist);
         if(m_pos[i].sl <= 0.0 || want < m_pos[i].sl)
            m_pos[i].sl = want;
        }
     }

   //--- pendings become positions when price reaches them
   void              CheckPendings(void)
     {
      for(int i = 0; i < m_count; i++)
        {
         if(m_pos[i].state != SSR_POS_PENDING)
            continue;
         bool hit = false;
         switch(m_pos[i].type)
           {
            case SSR_ORDER_BUY_LIMIT:  hit = (m_ask <= m_pos[i].request_price); break;
            case SSR_ORDER_SELL_LIMIT: hit = (m_bid >= m_pos[i].request_price); break;
            case SSR_ORDER_BUY_STOP:   hit = (m_ask >= m_pos[i].request_price); break;
            case SSR_ORDER_SELL_STOP:  hit = (m_bid <= m_pos[i].request_price); break;
           }
         if(!hit)
            continue;

         bool is_long = m_pos[i].IsLong();
         m_pos[i].type       = (is_long ? SSR_ORDER_BUY : SSR_ORDER_SELL);
         m_pos[i].open_price = FillPrice(is_long, true);
         m_pos[i].open_msc   = m_now_msc;
         m_pos[i].state         = SSR_POS_OPEN;
         m_pos[i].swap_from_msc = m_now_msc;
         m_pos[i].trail_peak    = (is_long ? m_bid : m_ask);
         if(m_pos[i].sl > 0.0)
            m_pos[i].risk_at_entry =
               m_risk.RiskOf(m_pos[i].volume,
                             MathAbs(m_pos[i].open_price - m_pos[i].sl));
         m_pos[i].commission += m_exec.commission_per_lot * m_pos[i].volume;
         m_balance           -= m_exec.commission_per_lot * m_pos[i].volume;
        }
     }

   //+------------------------------------------------------------------+
   //| Swap, per REPLAY day held.                                       |
   //|                                                                  |
   //| On the replay calendar, not the real one: a session that replays |
   //| a week in an evening must pay a week of swap, not one night.     |
   //|                                                                  |
   //| RECOMPUTED, not accumulated. Each call restates what a position  |
   //| owes from its own open day and moves the balance by the          |
   //| difference. That makes the call idempotent, so it is safe to run |
   //| on every tick, and - the reason it is written this way - it      |
   //| survives a rewind: replaying the same days again cannot charge   |
   //| twice, and rewinding out of them refunds what was charged.       |
   //+------------------------------------------------------------------+
   void              AccrueSwap(void)
     {
      if(m_exec.swap_long_per_lot == 0.0 && m_exec.swap_short_per_lot == 0.0)
         return;
      if(m_now_msc == SSR_INVALID_TIME)
         return;
      long today = m_now_msc / SSR_MSC_PER_DAY;

      for(int i = 0; i < m_count; i++)
        {
         if(m_pos[i].state != SSR_POS_OPEN || m_pos[i].open_msc <= 0)
            continue;
         //--- from the last size change, not from the entry: a position
         //--- scaled out of already banked the days it held at the
         //--- larger size, in swap_locked
         long from = (m_pos[i].swap_from_msc > 0 ? m_pos[i].swap_from_msc
                                                 : m_pos[i].open_msc);
         long days = today - (from / SSR_MSC_PER_DAY);
         if(days < 0)
            days = 0;
         double per  = (m_pos[i].IsLong() ? m_exec.swap_long_per_lot
                                          : m_exec.swap_short_per_lot);
         double owed = m_pos[i].swap_locked
                     + per * m_pos[i].volume * (double)days;
         if(owed == m_pos[i].swap)
            continue;
         m_balance     += owed - m_pos[i].swap;   // the difference only
         m_pos[i].swap  = owed;
        }
     }

   //+------------------------------------------------------------------+
   //| A backtest that never runs out of margin flatters every           |
   //| oversized position it ever took.                                  |
   //+------------------------------------------------------------------+
   void              CheckStopout(void)
     {
      if(m_stopout_level <= 0.0 || m_margin_per_lot <= 0.0)
         return;
      double used = UsedMargin();
      if(used <= 0.0 || Equity() / used * 100.0 > m_stopout_level)
         return;

      //--- worst loser first, as a broker would, until the level
      //--- recovers or there is nothing left to close
      for(int guard = 0; guard < SSR_MAX_POSITIONS; guard++)
        {
         int    worst = -1;
         double worst_pl = 0.0;
         for(int i = 0; i < m_count; i++)
           {
            if(m_pos[i].state != SSR_POS_OPEN)
               continue;
            double px = (m_pos[i].IsLong() ? m_bid : m_ask);
            double pl = RealisedOf(m_pos[i], px, m_pos[i].volume);
            if(worst < 0 || pl < worst_pl)
              { worst = i; worst_pl = pl; }
           }
         if(worst < 0)
            return;

         ClosePosition(worst, FillPrice(m_pos[worst].IsLong(), false),
                       SSR_CLOSE_STOPOUT);
         m_stopouts++;

         used = UsedMargin();
         if(used <= 0.0 || Equity() / used * 100.0 > m_stopout_level)
            return;
        }
     }

   void              CheckStops(void)
     {
      for(int i = 0; i < m_count; i++)
        {
         if(m_pos[i].state != SSR_POS_OPEN)
            continue;

         UpdateExcursions(i);
         ApplyTrailing(i);

         bool is_long = m_pos[i].IsLong();
         double px    = (is_long ? m_bid : m_ask);

         bool sl_hit = (m_pos[i].sl > 0.0 &&
                        (is_long ? px <= m_pos[i].sl : px >= m_pos[i].sl));
         bool tp_hit = (m_pos[i].tp > 0.0 &&
                        (is_long ? px >= m_pos[i].tp : px <= m_pos[i].tp));

         if(!sl_hit && !tp_hit)
            continue;

         //--- THE HONEST CASE. If this bar's range holds both levels and
         //--- the tick order is our own invention, we cannot know which
         //--- came first - so we take the loss and label the result.
         if(BarIsAmbiguousFor(m_pos[i]))
           {
            ClosePosition(i, m_pos[i].sl, SSR_CLOSE_SL, true);
            continue;
           }

         if(sl_hit) ClosePosition(i, m_pos[i].sl, SSR_CLOSE_SL);
         else       ClosePosition(i, m_pos[i].tp, SSR_CLOSE_TP);
        }
     }

public:
                     CSSRTradingEngine(void)
     : m_count(0), m_next_ticket(1), m_symbol(""), m_digits(5), m_point(0.00001),
       m_balance_initial(10000.0), m_balance(10000.0),
       m_margin_per_lot(0.0), m_stopout_level(0.0), m_stopouts(0),
       m_bid(0.0), m_ask(0.0), m_now_msc(SSR_INVALID_TIME),
       m_bar_valid(false), m_bar_synthetic(true),
       m_ambiguous_count(0), m_last_error("")
     { m_exec.Init(); }

   virtual string    Name(void) override { return "virtual-trading"; }

   //--- configuration ------------------------------------------------
   void              SetBalance(const double b)
     { m_balance_initial = b; m_balance = b; }
   void              SetExecution(SSRExecutionModel &e) { m_exec = e; }
   void              ExecutionInto(SSRExecutionModel &out) { out = m_exec; }
   CSSRRiskEngine   *Risk(void) { return GetPointer(m_risk); }
   string            LastError(void) { return m_last_error; }

   //--- observer contract --------------------------------------------
   virtual void      OnSessionStart(const string symbol, const int digits,
                                    const double point, const long start_msc) override
     {
      m_symbol   = symbol;
      m_digits   = digits;
      m_point    = (point > 0.0 ? point : MathPow(10, -digits));
      m_now_msc  = start_msc;
      m_count    = 0;
      m_next_ticket = 1;
      m_balance  = m_balance_initial;
      m_ambiguous_count = 0;
      m_bar_valid = false;
      m_risk.ConfigureFromSymbol(symbol);
      m_stopouts      = 0;

      //--- margin per lot from the instrument when it declares one.
      //--- Left at zero it means margin is NOT modelled, which is said
      //--- out loud rather than faked with a plausible number.
      double m = SymbolInfoDouble(symbol, SYMBOL_MARGIN_INITIAL);
      if(m > 0.0)
         m_margin_per_lot = m;
     }

   virtual void      OnBarContext(const MqlRates &bar, const bool synthetic) override
     {
      m_bar           = bar;
      m_bar_valid     = true;
      m_bar_synthetic = synthetic;
     }

   virtual void      OnTicks(const MqlTick &ticks[], const int count) override
     {
      for(int i = 0; i < count; i++)
        {
         m_bid     = ticks[i].bid;
         m_ask     = (ticks[i].ask > 0.0 ? ticks[i].ask : ticks[i].bid);
         if(!m_exec.use_real_spread)
            m_ask = m_bid + m_exec.fixed_spread_points * m_point;
         m_now_msc = ticks[i].time_msc;

         AccrueSwap();
         CheckPendings();
         CheckStops();
         CheckStopout();
        }
     }

   virtual void      OnClock(const long now_msc) override
     { if(now_msc > m_now_msc) m_now_msc = now_msc; }

   //+------------------------------------------------------------------+
   //| A rewind means those trades did not happen.                      |
   //|                                                                  |
   //| Three things can be in the deleted future, and all three are     |
   //| undone here:                                                     |
   //|   - the order itself, if it was placed after the cut             |
   //|   - any exit taken after the cut, partial or final               |
   //|   - the FILL, if a pending order was triggered after the cut     |
   //|                                                                  |
   //| The last two are the ones an engine quietly gets wrong. Restoring|
   //| a scaled-out position to its full size, or leaving a pending      |
   //| order filled at a price the replay has just un-happened, both    |
   //| leave the trader holding something they never chose.             |
   //+------------------------------------------------------------------+
   virtual void      OnRewind(const long msc) override
     {
      int keep = 0;
      for(int i = 0; i < m_count; i++)
        {
         //--- the order was PLACED after the cut: it never existed
         long placed = (m_pos[i].request_msc > 0 ? m_pos[i].request_msc
                                                 : m_pos[i].open_msc);
         if(placed > msc)
            continue;

         //--- every exit taken in the deleted future, newest first
         UnwindLegsAfter(i, msc);

         //--- a pending cancelled in the deleted future is pending again
         if(m_pos[i].state == SSR_POS_CANCELLED &&
            m_pos[i].close_msc > msc)
           {
            m_pos[i].state     = SSR_POS_PENDING;
            m_pos[i].close_msc = SSR_INVALID_TIME;
            m_pos[i].reason    = SSR_CLOSE_NONE;
           }

         //--- a pending FILLED in the deleted future is pending again.
         //--- By now the legs are unwound, so the only money still on
         //--- the position is the entry commission and accrued swap.
         if(m_pos[i].state != SSR_POS_PENDING &&
            SSRIsPending(m_pos[i].request_type) &&
            m_pos[i].open_msc > msc)
           {
            m_balance             += m_pos[i].commission - m_pos[i].swap;
            m_pos[i].commission    = 0.0;
            m_pos[i].swap          = 0.0;
            m_pos[i].swap_locked   = 0.0;
            m_pos[i].swap_from_msc = SSR_INVALID_TIME;

            m_pos[i].state         = SSR_POS_PENDING;
            m_pos[i].type          = m_pos[i].request_type;
            m_pos[i].volume        = m_pos[i].volume_initial;
            m_pos[i].open_price    = 0.0;
            m_pos[i].open_msc      = m_pos[i].request_msc;
            m_pos[i].profit        = 0.0;
            m_pos[i].risk_at_entry = 0.0;
            m_pos[i].trail_peak    = 0.0;
            m_pos[i].mae           = 0.0;
            m_pos[i].mfe           = 0.0;
           }

         if(keep != i)
            m_pos[keep] = m_pos[i];
         keep++;
        }
      m_count   = keep;
      m_now_msc = msc;

      //--- days that no longer happened are not owed. AccrueSwap is a
      //--- restatement, so calling it here refunds them exactly.
      AccrueSwap();
     }

   //--- trading verbs -------------------------------------------------
   long              Open(const ENUM_SSR_ORDER type, const double volume,
                          const double sl = 0.0, const double tp = 0.0,
                          const double price = 0.0, const string tag = "")
     {
      m_last_error = "";
      if(m_count >= SSR_MAX_POSITIONS)
        { m_last_error = "too many positions"; return 0; }
      if(volume <= 0.0)
        { m_last_error = "volume must be positive"; return 0; }
      if(m_bid <= 0.0)
        { m_last_error = "no price yet - let the replay run first"; return 0; }

      int i = m_count++;
      m_pos[i].Init();
      m_pos[i].ticket         = m_next_ticket++;
      m_pos[i].type           = type;
      m_pos[i].volume         = volume;
      m_pos[i].volume_initial = volume;
      m_pos[i].sl             = Norm(sl);
      m_pos[i].tp             = Norm(tp);
      m_pos[i].tag            = tag;

      if(SSRIsPending(type))
        {
         if(price <= 0.0)
           { m_count--; m_last_error = "a pending order needs a price"; return 0; }
         m_pos[i].state         = SSR_POS_PENDING;
         m_pos[i].request_price = Norm(price);
         m_pos[i].request_msc   = m_now_msc;
         m_pos[i].request_type  = type;
         m_pos[i].open_msc      = m_now_msc;
         return m_pos[i].ticket;
        }

      bool is_long = SSRIsLong(type);
      m_pos[i].state        = SSR_POS_OPEN;
      m_pos[i].open_price   = FillPrice(is_long, true);
      m_pos[i].open_msc     = m_now_msc;
      m_pos[i].request_msc  = m_now_msc;
      m_pos[i].request_type = type;
      m_pos[i].swap_from_msc = m_now_msc;
      m_pos[i].trail_peak = (is_long ? m_bid : m_ask);
      if(m_pos[i].sl > 0.0)
         m_pos[i].risk_at_entry =
            m_risk.RiskOf(volume, MathAbs(m_pos[i].open_price - m_pos[i].sl));
      m_pos[i].commission = m_exec.commission_per_lot * volume;
      m_balance          -= m_pos[i].commission;
      return m_pos[i].ticket;
     }

   //--- size the trade from a risk percentage rather than a guess
   long              OpenWithRisk(const ENUM_SSR_ORDER type, const double risk_percent,
                                  const double sl, const double tp = 0.0,
                                  const string tag = "")
     {
      m_last_error = "";
      if(m_bid <= 0.0)
        { m_last_error = "no price yet"; return 0; }
      double entry = FillPrice(SSRIsLong(type), true);
      double lot   = m_risk.LotForRisk(Equity(), risk_percent, entry, sl);
      if(lot <= 0.0)
        { m_last_error = m_risk.LastReason(); return 0; }
      return Open(type, lot, sl, tp, 0.0, tag);
     }

   bool              Modify(const long ticket, const double sl, const double tp)
     {
      int i = Find(ticket);
      if(i < 0) { m_last_error = "no such ticket"; return false; }
      if(m_pos[i].state == SSR_POS_CLOSED)
        { m_last_error = "position is closed"; return false; }
      m_pos[i].sl = Norm(sl);
      m_pos[i].tp = Norm(tp);
      return true;
     }

   bool              SetTrailing(const long ticket, const double points)
     {
      int i = Find(ticket);
      if(i < 0) { m_last_error = "no such ticket"; return false; }
      m_pos[i].trail_points = points;
      if(m_pos[i].trail_peak <= 0.0)
         m_pos[i].trail_peak = (m_pos[i].IsLong() ? m_bid : m_ask);
      return true;
     }

   bool              Close(const long ticket)
     {
      int i = Find(ticket);
      if(i < 0) { m_last_error = "no such ticket"; return false; }
      if(m_pos[i].state == SSR_POS_PENDING)
        {
         //--- stamped, so a rewind past it can put the order back
         m_pos[i].state     = SSR_POS_CANCELLED;
         m_pos[i].close_msc = m_now_msc;
         m_pos[i].reason    = SSR_CLOSE_MANUAL;
         return true;
        }
      if(m_pos[i].state != SSR_POS_OPEN)
        { m_last_error = "position is not open"; return false; }
      ClosePosition(i, FillPrice(m_pos[i].IsLong(), false), SSR_CLOSE_MANUAL);
      return true;
     }

   //+------------------------------------------------------------------+
   //| Close part of a position. The remainder keeps the original entry |
   //| and ticket, so a partial exit does not fabricate a second trade  |
   //| in the statistics.                                               |
   //+------------------------------------------------------------------+
   bool              ClosePartial(const long ticket, const double volume)
     {
      int i = Find(ticket);
      if(i < 0) { m_last_error = "no such ticket"; return false; }
      if(m_pos[i].state != SSR_POS_OPEN)
        { m_last_error = "position is not open"; return false; }
      if(volume <= 0.0 || volume >= m_pos[i].volume)
         return Close(ticket);

      //--- one slot short of the ceiling: the last one belongs to the
      //--- close, which is never allowed to fail
      if(m_pos[i].leg_count >= SSR_MAX_TRADE_LEGS - 1)
        {
         m_last_error = "too many partial exits on one position";
         return false;
        }
      return BookExit(i, FillPrice(m_pos[i].IsLong(), false), volume,
                      SSR_CLOSE_PARTIAL, false, false);
     }

   int               CloseAll(void)
     {
      int n = 0;
      for(int i = 0; i < m_count; i++)
         if(m_pos[i].state == SSR_POS_OPEN)
           {
            ClosePosition(i, FillPrice(m_pos[i].IsLong(), false), SSR_CLOSE_MANUAL);
            n++;
           }
      return n;
     }

   bool              BreakEven(const long ticket)
     {
      int i = Find(ticket);
      if(i < 0 || m_pos[i].state != SSR_POS_OPEN)
        { m_last_error = "no open position"; return false; }
      m_pos[i].sl = m_pos[i].open_price;
      return true;
     }

   //--- margin -------------------------------------------------------
   void              SetMarginPerLot(const double m)   { m_margin_per_lot = m; }
   void              SetStopoutLevel(const double pct) { m_stopout_level = pct; }
   bool              MarginModelled(void) { return (m_margin_per_lot > 0.0); }
   long              Stopouts(void)       { return m_stopouts; }

   double            UsedMargin(void)
     {
      if(m_margin_per_lot <= 0.0)
         return 0.0;
      double v = 0.0;
      for(int i = 0; i < m_count; i++)
         if(m_pos[i].state == SSR_POS_OPEN)
            v += m_pos[i].volume;
      return v * m_margin_per_lot;
     }

   double            FreeMargin(void) { return Equity() - UsedMargin(); }

   //--- percent, or 0 when there is nothing open to measure against
   double            MarginLevel(void)
     {
      double used = UsedMargin();
      return (used > 0.0 ? Equity() / used * 100.0 : 0.0);
     }

   //--- account ------------------------------------------------------
   double            Balance(void)        { return m_balance; }
   double            InitialBalance(void) { return m_balance_initial; }

   double            FloatingPL(void)
     {
      double f = 0.0;
      for(int i = 0; i < m_count; i++)
         if(m_pos[i].state == SSR_POS_OPEN)
           {
            double px = (m_pos[i].IsLong() ? m_bid : m_ask);
            f += RealisedOf(m_pos[i], px, m_pos[i].volume);
           }
      return f;
     }

   double            Equity(void) { return m_balance + FloatingPL(); }

   int               Total(void)  { return m_count; }
   int               OpenCount(void)
     {
      int n = 0;
      for(int i = 0; i < m_count; i++)
         if(m_pos[i].state == SSR_POS_OPEN) n++;
      return n;
     }
   int               PendingCount(void)
     {
      int n = 0;
      for(int i = 0; i < m_count; i++)
         if(m_pos[i].state == SSR_POS_PENDING) n++;
      return n;
     }
   int               ClosedCount(void)
     {
      int n = 0;
      for(int i = 0; i < m_count; i++)
         if(m_pos[i].state == SSR_POS_CLOSED) n++;
      return n;
     }

   long              AmbiguousCount(void) { return m_ambiguous_count; }

   //--- what fraction of the results rest on an assumed tick order
   double            AmbiguousPercent(void)
     {
      int closed = ClosedCount();
      return (closed > 0 ? 100.0 * (double)m_ambiguous_count / (double)closed : 0.0);
     }

   bool              At(const int i, SSRVirtualPosition &out)
     {
      if(i < 0 || i >= m_count)
         return false;
      out = m_pos[i];
      return true;
     }

   bool              ByTicket(const long ticket, SSRVirtualPosition &out)
     {
      int i = Find(ticket);
      if(i < 0)
         return false;
      out = m_pos[i];
      return true;
     }

   //--- which instrument this account is priced against. The panel
   //--- shows it, because on a multi-symbol board the account follows
   //--- the primary stream only and that had better be visible.
   string            Symbol(void) { return m_symbol; }
   int               Digits(void) { return m_digits; }
   double            Point(void)  { return m_point; }

   double            Bid(void) { return m_bid; }
   double            Ask(void) { return m_ask; }

   //================================================================
   //  SESSION PERSISTENCE
   //
   //  The account IS the log of positions, so that is what is written:
   //  every position, every leg, and the assumptions they were priced
   //  under. Nothing derived is stored - balance, equity, statistics
   //  and R all fall out of the log, and a stored copy that disagreed
   //  with it would be believed over the log that is actually true.
   //
   //  The one exception is m_balance, written for a CHECK rather than
   //  to be restored: if replaying the log does not reproduce it, the
   //  file and this build disagree and the user is told so.
   //================================================================
   void              SaveInto(CSSRSessionFile &f)
     {
      f.Section("account");
      f.SetDouble("balance_initial", m_balance_initial, 2);
      f.SetDouble("balance_check",   m_balance, 2);
      f.SetInt("digits",             m_digits);
      f.SetDouble("point",           m_point, 10);
      f.SetLong("next_ticket",       m_next_ticket);
      f.SetDouble("margin_per_lot",  m_margin_per_lot, 4);
      f.SetDouble("stopout_level",   m_stopout_level, 2);
      f.SetLong("stopouts",          m_stopouts);
      f.SetLong("ambiguous",         m_ambiguous_count);

      f.Section("execution");
      f.SetDouble("commission_per_lot", m_exec.commission_per_lot, 6);
      f.SetDouble("slippage_points",    m_exec.slippage_points, 6);
      f.SetDouble("swap_long",          m_exec.swap_long_per_lot, 6);
      f.SetDouble("swap_short",         m_exec.swap_short_per_lot, 6);
      f.SetBool("use_real_spread",      m_exec.use_real_spread);
      f.SetDouble("fixed_spread",       m_exec.fixed_spread_points, 6);

      f.Section("positions");
      f.Comment("pos=ticket|type|state|volume|volume_initial|request_price|"
                "request_msc|request_type|open_price|open_msc|sl|tp|"
                "trail_points|trail_peak|close_price|close_msc|reason|"
                "commission|swap|profit|mae|mfe|ambiguous|risk_at_entry|"
                "swap_locked|swap_from_msc|tag|note");
      for(int i = 0; i < m_count; i++)
        {
         string r = "";
         r = SSRPackAdd(r, IntegerToString(m_pos[i].ticket));
         r = SSRPackAdd(r, IntegerToString((int)m_pos[i].type));
         r = SSRPackAdd(r, IntegerToString((int)m_pos[i].state));
         r = SSRPackAdd(r, DoubleToString(m_pos[i].volume, 4));
         r = SSRPackAdd(r, DoubleToString(m_pos[i].volume_initial, 4));
         r = SSRPackAdd(r, DoubleToString(m_pos[i].request_price, 8));
         r = SSRPackAdd(r, IntegerToString(m_pos[i].request_msc));
         r = SSRPackAdd(r, IntegerToString((int)m_pos[i].request_type));
         r = SSRPackAdd(r, DoubleToString(m_pos[i].open_price, 8));
         r = SSRPackAdd(r, IntegerToString(m_pos[i].open_msc));
         r = SSRPackAdd(r, DoubleToString(m_pos[i].sl, 8));
         r = SSRPackAdd(r, DoubleToString(m_pos[i].tp, 8));
         r = SSRPackAdd(r, DoubleToString(m_pos[i].trail_points, 4));
         r = SSRPackAdd(r, DoubleToString(m_pos[i].trail_peak, 8));
         r = SSRPackAdd(r, DoubleToString(m_pos[i].close_price, 8));
         r = SSRPackAdd(r, IntegerToString(m_pos[i].close_msc));
         r = SSRPackAdd(r, IntegerToString((int)m_pos[i].reason));
         r = SSRPackAdd(r, DoubleToString(m_pos[i].commission, 6));
         r = SSRPackAdd(r, DoubleToString(m_pos[i].swap, 6));
         r = SSRPackAdd(r, DoubleToString(m_pos[i].profit, 6));
         r = SSRPackAdd(r, DoubleToString(m_pos[i].mae, 8));
         r = SSRPackAdd(r, DoubleToString(m_pos[i].mfe, 8));
         r = SSRPackAdd(r, (m_pos[i].ambiguous ? "1" : "0"));
         r = SSRPackAdd(r, DoubleToString(m_pos[i].risk_at_entry, 6));
         r = SSRPackAdd(r, DoubleToString(m_pos[i].swap_locked, 6));
         r = SSRPackAdd(r, IntegerToString(m_pos[i].swap_from_msc));
         r = SSRPackAdd(r, m_pos[i].tag);
         r = SSRPackAdd(r, m_pos[i].note);
         f.Set("pos", r);

         //--- and its legs, which are what a rewind needs to undo the
         //--- exits. A restored session that cannot step back over its
         //--- own trades is not the session that was saved.
         for(int e = 0; e < m_pos[i].leg_count; e++)
           {
            string g = "";
            g = SSRPackAdd(g, IntegerToString(m_pos[i].ticket));
            g = SSRPackAdd(g, DoubleToString(m_pos[i].legs[e].volume, 4));
            g = SSRPackAdd(g, DoubleToString(m_pos[i].legs[e].price, 8));
            g = SSRPackAdd(g, IntegerToString(m_pos[i].legs[e].msc));
            g = SSRPackAdd(g, DoubleToString(m_pos[i].legs[e].realised, 6));
            g = SSRPackAdd(g, DoubleToString(m_pos[i].legs[e].fee, 6));
            g = SSRPackAdd(g, (m_pos[i].legs[e].closing ? "1" : "0"));
            g = SSRPackAdd(g, DoubleToString(m_pos[i].legs[e].prev_swap_locked, 6));
            g = SSRPackAdd(g, IntegerToString(m_pos[i].legs[e].prev_swap_from_msc));
            g = SSRPackAdd(g, (m_pos[i].legs[e].prev_ambiguous ? "1" : "0"));
            f.Set("leg", g);
           }
        }
     }

   //+------------------------------------------------------------------+
   //| Read the account back.                                           |
   //|                                                                  |
   //| Returns false only when the file is unusable. A balance that      |
   //| does not reproduce is reported through `warning` and does NOT     |
   //| fail the load: the trades are still the trades, and refusing to   |
   //| open the session would help nobody.                              |
   //+------------------------------------------------------------------+
   bool              RestoreFrom(CSSRSessionFile &f, string &warning)
     {
      warning = "";
      if(!f.Select("account"))
        { m_last_error = "session file has no account section"; return false; }

      m_balance_initial = f.GetDouble("balance_initial", 10000.0);
      m_digits          = f.GetInt("digits", 5);
      m_point           = f.GetDouble("point", MathPow(10, -m_digits));
      m_next_ticket     = f.GetLong("next_ticket", 1);
      m_margin_per_lot  = f.GetDouble("margin_per_lot", 0.0);
      m_stopout_level   = f.GetDouble("stopout_level", 0.0);
      m_stopouts        = f.GetLong("stopouts", 0);
      double want_balance = f.GetDouble("balance_check", 0.0);

      if(f.Select("execution"))
        {
         m_exec.commission_per_lot = f.GetDouble("commission_per_lot", 0.0);
         m_exec.slippage_points    = f.GetDouble("slippage_points", 0.0);
         m_exec.swap_long_per_lot  = f.GetDouble("swap_long", 0.0);
         m_exec.swap_short_per_lot = f.GetDouble("swap_short", 0.0);
         m_exec.use_real_spread    = f.GetBool("use_real_spread", true);
         m_exec.fixed_spread_points= f.GetDouble("fixed_spread", 0.0);
        }

      m_count           = 0;
      m_ambiguous_count = 0;
      m_balance         = m_balance_initial;

      if(!f.Select("positions"))
         return true;                    // a session with no trades yet

      int n = f.Count("pos");
      for(int i = 0; i < n && m_count < SSR_MAX_POSITIONS; i++)
        {
         string c[];
         if(SSRUnpack(f.GetNth("pos", i), c) < 26)
            continue;                    // a row this build cannot read

         int k = m_count++;
         m_pos[k].Init();
         m_pos[k].ticket         = SSRFieldLong(c, 0);
         m_pos[k].type           = (ENUM_SSR_ORDER)SSRFieldLong(c, 1);
         m_pos[k].state          = (ENUM_SSR_POS_STATE)SSRFieldLong(c, 2);
         m_pos[k].volume         = SSRFieldDouble(c, 3);
         m_pos[k].volume_initial = SSRFieldDouble(c, 4);
         m_pos[k].request_price  = SSRFieldDouble(c, 5);
         m_pos[k].request_msc    = SSRFieldLong(c, 6, SSR_INVALID_TIME);
         m_pos[k].request_type   = (ENUM_SSR_ORDER)SSRFieldLong(c, 7);
         m_pos[k].open_price     = SSRFieldDouble(c, 8);
         m_pos[k].open_msc       = SSRFieldLong(c, 9, SSR_INVALID_TIME);
         m_pos[k].sl             = SSRFieldDouble(c, 10);
         m_pos[k].tp             = SSRFieldDouble(c, 11);
         m_pos[k].trail_points   = SSRFieldDouble(c, 12);
         m_pos[k].trail_peak     = SSRFieldDouble(c, 13);
         m_pos[k].close_price    = SSRFieldDouble(c, 14);
         m_pos[k].close_msc      = SSRFieldLong(c, 15, SSR_INVALID_TIME);
         m_pos[k].reason         = (ENUM_SSR_CLOSE_REASON)SSRFieldLong(c, 16);
         m_pos[k].commission     = SSRFieldDouble(c, 17);
         m_pos[k].swap           = SSRFieldDouble(c, 18);
         m_pos[k].profit         = SSRFieldDouble(c, 19);
         m_pos[k].mae            = SSRFieldDouble(c, 20);
         m_pos[k].mfe            = SSRFieldDouble(c, 21);
         m_pos[k].ambiguous      = (SSRFieldLong(c, 22) != 0);
         m_pos[k].risk_at_entry  = SSRFieldDouble(c, 23);
         m_pos[k].swap_locked    = SSRFieldDouble(c, 24);
         m_pos[k].swap_from_msc  = SSRFieldLong(c, 25, SSR_INVALID_TIME);
         m_pos[k].tag            = SSRField(c, 26);
         m_pos[k].note           = SSRField(c, 27);

         if(m_pos[k].ambiguous)
            m_ambiguous_count++;

         //--- the balance is REPLAYED from the log rather than read,
         //--- so the log stays the single source of truth
         m_balance += m_pos[k].profit + m_pos[k].swap - m_pos[k].commission;
        }

      //--- legs, matched back to their positions by ticket
      int legs = f.Count("leg");
      int orphans = 0;
      for(int i = 0; i < legs; i++)
        {
         string c[];
         if(SSRUnpack(f.GetNth("leg", i), c) < 10)
            continue;
         int idx = Find(SSRFieldLong(c, 0));
         if(idx < 0 || m_pos[idx].leg_count >= SSR_MAX_TRADE_LEGS)
           { orphans++; continue; }

         int e = m_pos[idx].leg_count++;
         m_pos[idx].legs[e].Init();
         m_pos[idx].legs[e].volume             = SSRFieldDouble(c, 1);
         m_pos[idx].legs[e].price              = SSRFieldDouble(c, 2);
         m_pos[idx].legs[e].msc                = SSRFieldLong(c, 3);
         m_pos[idx].legs[e].realised           = SSRFieldDouble(c, 4);
         m_pos[idx].legs[e].fee                = SSRFieldDouble(c, 5);
         m_pos[idx].legs[e].closing            = (SSRFieldLong(c, 6) != 0);
         m_pos[idx].legs[e].prev_swap_locked   = SSRFieldDouble(c, 7);
         m_pos[idx].legs[e].prev_swap_from_msc = SSRFieldLong(c, 8, SSR_INVALID_TIME);
         m_pos[idx].legs[e].prev_ambiguous     = (SSRFieldLong(c, 9) != 0);
        }

      m_risk.ConfigureFromSymbol(m_symbol);

      //--- and now the check. Silence here would mean a session that
      //--- opens with a balance nobody can account for.
      if(want_balance != 0.0 && MathAbs(want_balance - m_balance) > 0.01)
         warning = StringFormat("balance replayed from the trades is %.2f, "
                                "but the file recorded %.2f - a difference "
                                "of %.2f", m_balance, want_balance,
                                m_balance - want_balance);
      if(orphans > 0)
         warning += StringFormat("%s%d partial-exit records could not be "
                                 "matched to a trade; stepping back over "
                                 "those exits will not undo them",
                                 (warning == "" ? "" : "  "), orphans);
      return true;
     }

   string            ToString(void)
     {
      return StringFormat("account[bal=%.2f eq=%.2f open=%d closed=%d "
                          "ambiguous=%d (%.0f%%) margin=%s stopouts=%d]",
                          m_balance, Equity(), OpenCount(), ClosedCount(),
                          (int)m_ambiguous_count, AmbiguousPercent(),
                          (MarginModelled() ? "modelled" : "off"),
                          (int)m_stopouts);
     }
  };

#endif // SSR_TRADING_ENGINE_MQH
//+------------------------------------------------------------------+
