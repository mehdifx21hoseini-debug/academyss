//+------------------------------------------------------------------+
//|                                              SSR_MarketView.mqh  |
//|                  SS Replay - What A Strategy May See (L3)        |
//|                                                                  |
//|  THE ONE BUG THIS LAYER EXISTS TO MAKE IMPOSSIBLE                |
//|                                                                  |
//|  Look-ahead. A strategy that reads one bar it should not have    |
//|  produces results that are not merely optimistic - they are      |
//|  unrelated to trading. And it is almost never deliberate: an     |
//|  index off by one, a CopyRates on the origin symbol instead of   |
//|  the replay one, an indicator handle created before the clock    |
//|  was set. Every one of those looks like working code.            |
//|                                                                  |
//|  So this view does not GUARD against reading the future. It is   |
//|  built from what the engine has already PUBLISHED, and the       |
//|  future is not in it. There is nothing to guard, no flag to      |
//|  forget to check, and no version of the code where a strategy    |
//|  reads ahead and nobody notices.                                 |
//|                                                                  |
//|  HIGHER TIMEFRAMES ARE AGGREGATED HERE, from the same M1 the     |
//|  engine published. The bar at shift 0 is the FORMING one - it    |
//|  will change - and IsForming() says so, because a strategy that  |
//|  treats a forming bar as closed has reinvented look-ahead by     |
//|  another route.                                                  |
//+------------------------------------------------------------------+
#ifndef SSR_MARKET_VIEW_MQH
#define SSR_MARKET_VIEW_MQH

#include "../Common/SSR_Types.mqh"
#include "../Common/SSR_Time.mqh"
#include "../Core/SSR_ITickObserver.mqh"

//--- M1 bars kept. Two days of them, which covers any intraday
//--- strategy and several days of an H4 one; a strategy needing more
//--- says so through Capacity() rather than being quietly starved.
#define SSR_VIEW_M1_BARS   4096

//+------------------------------------------------------------------+
class CSSRMarketView : public CSSRTickObserver
  {
private:
   MqlRates          m_m1[];          // dynamic: 4096 bars is ~250KB
   int               m_count;
   int               m_capacity;

   string            m_symbol;
   int               m_digits;
   double            m_point;

   long              m_now_msc;
   double            m_bid, m_ask;
   bool              m_synthetic;     // is the intrabar order invented?
   long              m_refusals;      // reads this view could not serve
   long              m_bars_seen;

   void              Grow(void)
     {
      if(m_capacity > 0)
         return;
      m_capacity = SSR_VIEW_M1_BARS;
      ArrayResize(m_m1, m_capacity);
     }

   //--- oldest half dropped rather than the whole buffer: losing every
   //--- early bar would take the swing high a strategy is measuring
   //--- against along with it
   void              MakeRoom(void)
     {
      int keep = m_capacity / 2;
      for(int i = 0; i < keep; i++)
         m_m1[i] = m_m1[i + (m_count - keep)];
      m_count = keep;
     }

   //+------------------------------------------------------------------+
   //| Walk back through the M1 buffer, grouping into `tf` bars, and    |
   //| return the group at `shift`. Shift 0 is the newest, which is     |
   //| the one still forming.                                           |
   //+------------------------------------------------------------------+
   bool              Group(const ENUM_TIMEFRAMES tf, const int shift,
                           MqlRates &out, bool &forming)
     {
      forming = false;
      //--- a NEGATIVE shift is a request for the future, and it is
      //--- counted as such: it is the single most useful number in
      //--- this class, because a strategy making it has a bug
      if(shift < 0)
        { m_refusals++; return false; }
      if(m_count <= 0)
        { m_refusals++; return false; }
      if(!SSRIsSupportedTimeframe(tf))
        { m_refusals++; return false; }  // W1/MN1 do not align with the epoch

      int  seen  = -1;
      long group = -1;
      bool open_set = false;

      for(int i = m_count - 1; i >= 0; i--)
        {
         long g = SSRBarOpenMsc(SSRToMsc(m_m1[i].time), tf);
         if(g != group)
           {
            //--- a new group begins here; the previous one is complete
            if(seen == shift && open_set)
               return true;             // the caller's group just ended
            group = g;
            seen++;
            if(seen == shift)
              {
               out          = m_m1[i];
               out.time     = SSRToTime(g);
               open_set     = true;
               forming      = (shift == 0);
              }
            else
               open_set = false;
            continue;
           }

         if(seen != shift || !open_set)
            continue;

         //--- still inside the requested group, moving BACKWARD in
         //--- time, so this bar is earlier: it owns the open
         out.open = m_m1[i].open;
         if(m_m1[i].high > out.high) out.high = m_m1[i].high;
         if(m_m1[i].low  < out.low)  out.low  = m_m1[i].low;
         out.tick_volume += m_m1[i].tick_volume;
         out.real_volume += m_m1[i].real_volume;
        }

      //--- ran off the start of the buffer. The group is only usable
      //--- if it was the one asked for AND we know it is complete,
      //--- which we do not - so it is refused rather than returned
      //--- half-built.
      if(seen == shift && open_set)
        {
         if(shift == 0)
            return true;                // forming, and known to be so
         m_refusals++;
         return false;
        }
      m_refusals++;
      return false;
     }

public:
                     CSSRMarketView(void)
     : m_count(0), m_capacity(0), m_symbol(""), m_digits(5),
       m_point(0.00001), m_now_msc(SSR_INVALID_TIME),
       m_bid(0.0), m_ask(0.0), m_synthetic(true),
       m_refusals(0), m_bars_seen(0) { Grow(); }

   virtual string    Name(void) override { return "market-view"; }

   //================================================================
   //  THE OBSERVER SIDE - how the past gets in
   //================================================================
   virtual void      OnSessionStart(const string symbol, const int digits,
                                    const double point, const long start_msc) override
     {
      m_symbol    = symbol;
      m_digits    = digits;
      m_point     = (point > 0.0 ? point : MathPow(10, -digits));
      m_count     = 0;
      m_now_msc   = start_msc;
      m_bid       = 0.0;
      m_ask       = 0.0;
      m_refusals  = 0;
      m_bars_seen = 0;
     }

   virtual void      OnBarContext(const MqlRates &bar, const bool synthetic) override
     {
      m_synthetic = synthetic;
      Grow();

      //--- the same bar arriving twice must UPDATE, not duplicate: a
      //--- forming bar is published as it grows
      if(m_count > 0 && m_m1[m_count - 1].time == bar.time)
        {
         m_m1[m_count - 1] = bar;
         return;
        }
      if(m_count >= m_capacity)
         MakeRoom();
      m_m1[m_count++] = bar;
      m_bars_seen++;
     }

   virtual void      OnTicks(const MqlTick &ticks[], const int count) override
     {
      if(count <= 0)
         return;
      m_bid     = ticks[count - 1].bid;
      m_ask     = (ticks[count - 1].ask > 0.0 ? ticks[count - 1].ask : m_bid);
      m_now_msc = ticks[count - 1].time_msc;
     }

   virtual void      OnClock(const long now_msc) override
     { if(now_msc > m_now_msc) m_now_msc = now_msc; }

   //--- a rewind deletes bars this view was told about
   virtual void      OnRewind(const long msc) override
     {
      int keep = 0;
      for(int i = 0; i < m_count; i++)
         if(SSRToMsc(m_m1[i].time) <= msc)
            keep++;
         else
            break;                      // the buffer is in time order
      m_count   = keep;
      m_now_msc = msc;
     }

   //================================================================
   //  THE STRATEGY SIDE - what may be read
   //
   //  Every accessor returns bool and fills an out-parameter. None of
   //  them returns 0.0 for "not available": a strategy comparing
   //  against a zero it did not know was a failure will take trades
   //  on it, and the whole point of this layer is that such a bug
   //  cannot exist.
   //================================================================
   bool              Bar(const ENUM_TIMEFRAMES tf, const int shift, MqlRates &out)
     {
      bool forming = false;
      return Group(tf, shift, out, forming);
     }

   //--- is this bar still being built? A strategy that treats a
   //--- forming bar as closed has reinvented look-ahead sideways.
   bool              IsForming(const ENUM_TIMEFRAMES tf, const int shift)
     { return (shift == 0); }

   bool              Open(const ENUM_TIMEFRAMES tf, const int shift, double &out)
     {
      MqlRates r;
      if(!Bar(tf, shift, r)) { out = 0.0; return false; }
      out = r.open;  return true;
     }
   bool              High(const ENUM_TIMEFRAMES tf, const int shift, double &out)
     {
      MqlRates r;
      if(!Bar(tf, shift, r)) { out = 0.0; return false; }
      out = r.high;  return true;
     }
   bool              Low(const ENUM_TIMEFRAMES tf, const int shift, double &out)
     {
      MqlRates r;
      if(!Bar(tf, shift, r)) { out = 0.0; return false; }
      out = r.low;   return true;
     }
   bool              Close(const ENUM_TIMEFRAMES tf, const int shift, double &out)
     {
      MqlRates r;
      if(!Bar(tf, shift, r)) { out = 0.0; return false; }
      out = r.close; return true;
     }
   bool              Time(const ENUM_TIMEFRAMES tf, const int shift, datetime &out)
     {
      MqlRates r;
      if(!Bar(tf, shift, r)) { out = 0; return false; }
      out = r.time;  return true;
     }

   //--- the highest high over `count` CLOSED bars, ending at `shift`.
   //--- Refuses outright if any bar in the span is missing, rather
   //--- than returning the extreme of the part that happened to be
   //--- there - a range computed from four bars when five were asked
   //--- for is a different number wearing the same name.
   bool              HighestHigh(const ENUM_TIMEFRAMES tf, const int shift,
                                 const int count, double &out)
     {
      out = 0.0;
      if(count <= 0)
         return false;
      double best = 0.0;
      for(int i = 0; i < count; i++)
        {
         MqlRates r;
         if(!Bar(tf, shift + i, r))
            return false;
         if(i == 0 || r.high > best)
            best = r.high;
        }
      out = best;
      return true;
     }

   bool              LowestLow(const ENUM_TIMEFRAMES tf, const int shift,
                               const int count, double &out)
     {
      out = 0.0;
      if(count <= 0)
         return false;
      double best = 0.0;
      for(int i = 0; i < count; i++)
        {
         MqlRates r;
         if(!Bar(tf, shift + i, r))
            return false;
         if(i == 0 || r.low < best)
            best = r.low;
        }
      out = best;
      return true;
     }

   //+------------------------------------------------------------------+
   //| How many bars of this timeframe are available, COMPLETE ones     |
   //| plus the forming one.                                            |
   //|                                                                  |
   //| One backward pass counting group boundaries. Asking Group() in   |
   //| a loop would be quadratic and would also count its own failure   |
   //| as a strategy misreading the view.                               |
   //+------------------------------------------------------------------+
   int               Available(const ENUM_TIMEFRAMES tf)
     {
      if(m_count <= 0 || !SSRIsSupportedTimeframe(tf))
         return 0;
      int  groups = 0;
      long last   = -1;
      for(int i = m_count - 1; i >= 0; i--)
        {
         long g = SSRBarOpenMsc(SSRToMsc(m_m1[i].time), tf);
         if(g == last)
            continue;
         last = g;
         groups++;
        }
      //--- the OLDEST group may have started before the buffer did, so
      //--- it cannot be served and is not counted as available
      return (groups > 1 ? groups - 1 : (groups == 1 ? 1 : 0));
     }

   //+------------------------------------------------------------------+
   //| Fill the view with history it did not watch arrive.              |
   //|                                                                  |
   //| A JUMP does not publish the bars it crosses - it writes them in  |
   //| bulk, which is the whole reason a jump is fast - so a strategy   |
   //| on the far side of one starts with an empty view and Available() |
   //| honestly says zero.                                              |
   //|                                                                  |
   //| Priming is the HOST's job, not this class's, because the host is |
   //| what owns a data source. And the caller must not hand over bars  |
   //| past `now`: this method does not police that, it TRIMS to it,    |
   //| because a view that silently accepted the future would undo      |
   //| everything the rest of this file is for.                         |
   //+------------------------------------------------------------------+
   int               Prime(const MqlRates &bars[], const int count,
                          const long now_msc)
     {
      Grow();
      m_count = 0;
      int taken = 0;
      for(int i = 0; i < count; i++)
        {
         //--- strictly at or before the clock. Never past it.
         if(SSRToMsc(bars[i].time) > now_msc)
            break;
         if(m_count >= m_capacity)
            MakeRoom();
         m_m1[m_count++] = bars[i];
         taken++;
        }
      if(now_msc > m_now_msc)
         m_now_msc = now_msc;
      return taken;
     }

   //--- prices, as they stand right now
   double            Bid(void)    { return m_bid; }
   double            Ask(void)    { return m_ask; }
   double            Spread(void) { return (m_ask > 0.0 ? m_ask - m_bid : 0.0); }
   long              Now(void)    { return m_now_msc; }
   string            Symbol(void) { return m_symbol; }
   int               Digits(void) { return m_digits; }
   double            Point(void)  { return m_point; }

   //+------------------------------------------------------------------+
   //| WHAT THIS DATA IS WORTH.                                         |
   //|                                                                  |
   //| True when the order of prices inside the current bar was         |
   //| invented rather than observed. A strategy that acts intrabar     |
   //| on synthetic ticks is trading an assumption, and it should be    |
   //| able to know that rather than find out from its results.         |
   //+------------------------------------------------------------------+
   bool              IsSynthetic(void) { return m_synthetic; }

   long              Refusals(void)  { return m_refusals; }
   long              BarsSeen(void)  { return m_bars_seen; }
   int               M1Count(void)   { return m_count; }
   int               Capacity(void)  { return m_capacity; }

   string            ToString(void)
     {
      return StringFormat("view[%s %d M1 bars  %s  %s  refused=%I64d]",
                          m_symbol, m_count, SSRFormatMsc(m_now_msc),
                          (m_synthetic ? "synthetic" : "real ticks"),
                          m_refusals);
     }
  };

#endif // SSR_MARKET_VIEW_MQH
//+------------------------------------------------------------------+
