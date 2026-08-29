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

   void              ClosePosition(const int i, const double price,
                                   const ENUM_SSR_CLOSE_REASON reason,
                                   const bool ambiguous = false)
     {
      double realised = RealisedOf(m_pos[i], price, m_pos[i].volume);
      m_pos[i].profit      += realised;
      m_pos[i].commission  += m_exec.commission_per_lot * m_pos[i].volume;
      m_pos[i].close_price  = Norm(price);
      m_pos[i].close_msc    = m_now_msc;
      m_pos[i].reason       = reason;
      m_pos[i].state        = SSR_POS_CLOSED;
      if(ambiguous)
        {
         m_pos[i].ambiguous = true;
         m_ambiguous_count++;
        }
      m_balance += realised - m_exec.commission_per_lot * m_pos[i].volume + m_pos[i].swap;
      m_pos[i].volume = 0.0;
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
         m_pos[i].state      = SSR_POS_OPEN;
         m_pos[i].trail_peak = (is_long ? m_bid : m_ask);
         m_pos[i].commission += m_exec.commission_per_lot * m_pos[i].volume;
         m_balance           -= m_exec.commission_per_lot * m_pos[i].volume;
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

         CheckPendings();
         CheckStops();
        }
     }

   virtual void      OnClock(const long now_msc) override
     { if(now_msc > m_now_msc) m_now_msc = now_msc; }

   //+------------------------------------------------------------------+
   //| A rewind means those trades did not happen.                      |
   //|                                                                  |
   //| Positions opened after the cut are erased outright. Positions    |
   //| that were open at the cut but CLOSED after it are reopened, with |
   //| their realised profit taken back out of the balance - because at |
   //| the restored instant they were, in fact, still open.             |
   //+------------------------------------------------------------------+
   virtual void      OnRewind(const long msc) override
     {
      int keep = 0;
      for(int i = 0; i < m_count; i++)
        {
         //--- never existed at that instant
         if(m_pos[i].open_msc > msc ||
            (m_pos[i].state == SSR_POS_PENDING && m_pos[i].open_msc > msc))
            continue;

         //--- closed in the deleted future: undo the close
         if(m_pos[i].state == SSR_POS_CLOSED && m_pos[i].close_msc > msc)
           {
            m_balance -= m_pos[i].profit;
            m_balance += m_exec.commission_per_lot * m_pos[i].volume_initial;
            m_pos[i].state       = SSR_POS_OPEN;
            m_pos[i].volume      = m_pos[i].volume_initial;
            m_pos[i].profit      = 0.0;
            m_pos[i].close_price = 0.0;
            m_pos[i].close_msc   = SSR_INVALID_TIME;
            m_pos[i].reason      = SSR_CLOSE_NONE;
            if(m_pos[i].ambiguous)
              {
               m_pos[i].ambiguous = false;
               m_ambiguous_count--;
              }
           }

         if(keep != i)
            m_pos[keep] = m_pos[i];
         keep++;
        }
      m_count   = keep;
      m_now_msc = msc;
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
         m_pos[i].open_msc      = m_now_msc;
         return m_pos[i].ticket;
        }

      bool is_long = SSRIsLong(type);
      m_pos[i].state      = SSR_POS_OPEN;
      m_pos[i].open_price = FillPrice(is_long, true);
      m_pos[i].open_msc   = m_now_msc;
      m_pos[i].trail_peak = (is_long ? m_bid : m_ask);
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
        { m_pos[i].state = SSR_POS_CANCELLED; return true; }
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

      double price    = FillPrice(m_pos[i].IsLong(), false);
      double realised = RealisedOf(m_pos[i], price, volume);
      double comm     = m_exec.commission_per_lot * volume;

      m_pos[i].profit     += realised;
      m_pos[i].commission += comm;
      m_pos[i].volume     -= volume;
      m_balance           += realised - comm;
      return true;
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

   double            Bid(void) { return m_bid; }
   double            Ask(void) { return m_ask; }

   string            ToString(void)
     {
      return StringFormat("account[bal=%.2f eq=%.2f open=%d closed=%d ambiguous=%d (%.0f%%)]",
                          m_balance, Equity(), OpenCount(), ClosedCount(),
                          (int)m_ambiguous_count, AmbiguousPercent());
     }
  };

#endif // SSR_TRADING_ENGINE_MQH
//+------------------------------------------------------------------+
