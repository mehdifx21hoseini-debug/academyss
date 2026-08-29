//+------------------------------------------------------------------+
//|                                            SSR_DataValidator.mqh |
//|                            SS Replay - Data Validation (L1)      |
//|                                                                  |
//|  Broker history is not clean. It has duplicated minutes, bars    |
//|  out of order after a reconnect, and gaps - and a gap is NOT     |
//|  automatically a fault, because markets close.                   |
//|                                                                  |
//|  This class refuses to guess. It separates the two kinds of gap  |
//|  and reports both, so nothing downstream has to decide whether   |
//|  a missing Saturday is corruption.                               |
//+------------------------------------------------------------------+
#ifndef SSR_DATA_VALIDATOR_MQH
#define SSR_DATA_VALIDATOR_MQH

#include "../Common/SSR_Types.mqh"
#include "../Common/SSR_Time.mqh"

//--- a gap at least this long is treated as a market closure rather
//--- than as missing data. One hour is deliberately conservative:
//--- a real feed outage shorter than that still gets reported.
#define SSR_SESSION_GAP_MSC   (60 * 60 * 1000)

//+------------------------------------------------------------------+
struct SSRDataReport
  {
   int               total;
   int               duplicates;      // same open time seen twice
   int               out_of_order;    // a bar older than its predecessor
   int               micro_gaps;      // missing minutes, below the session threshold
   int               session_gaps;    // gaps long enough to be a market closure
   long              largest_gap_msc;
   int               invalid_ohlc;    // high<max(o,c), low>min(o,c), high<low
   int               nonpositive;     // a price at or below zero
   long              first_msc;
   long              last_msc;

   void              Init(void)
     {
      total = 0; duplicates = 0; out_of_order = 0;
      micro_gaps = 0; session_gaps = 0; largest_gap_msc = 0;
      invalid_ohlc = 0; nonpositive = 0;
      first_msc = SSR_INVALID_TIME;
      last_msc  = SSR_INVALID_TIME;
     }

   //--- session gaps are expected, so they do not make data dirty
   bool              IsClean(void)
     {
      return (duplicates == 0 && out_of_order == 0 &&
              invalid_ohlc == 0 && nonpositive == 0);
     }

   bool              IsUsable(void)
     {
      return (total > 0 && invalid_ohlc == 0 && nonpositive == 0);
     }

   string            ToString(void)
     {
      return StringFormat("bars=%d dup=%d ooo=%d micro_gap=%d session_gap=%d "
                          "max_gap=%s bad_ohlc=%d nonpos=%d range=%s..%s",
                          total, duplicates, out_of_order, micro_gaps, session_gaps,
                          SSRFormatSpan(largest_gap_msc), invalid_ohlc, nonpositive,
                          SSRFormatMsc(first_msc), SSRFormatMsc(last_msc));
     }
  };

//+------------------------------------------------------------------+
//| The longest stretch in a week during which this symbol quotes    |
//| nothing, read from the symbol itself.                            |
//|                                                                  |
//| A flat one-hour threshold calls a Friday-evening close "missing   |
//| data" on a symbol that trades 24/5, and calls a genuine two-hour  |
//| feed outage "a session break" on one that trades 24/7. The symbol |
//| already knows the answer; asking it is no more code than          |
//| guessing.                                                        |
//+------------------------------------------------------------------+
long SSRSymbolSessionGap(const string symbol)
  {
   long DAY  = 86400L * 1000;
   long WEEK = 7 * DAY;

   //--- collect every quote session of the week on one timeline, so a
   //--- gap can be measured from one session's CLOSE to the next one's
   //--- OPEN rather than from midnight
   long opens[64], closes[64];
   int  n = 0;

   for(int d = 0; d < 7 && n < 64; d++)
     {
      ENUM_DAY_OF_WEEK day = (ENUM_DAY_OF_WEEK)d;
      for(uint idx = 0; idx < 8 && n < 64; idx++)
        {
         datetime from = 0, to = 0;
         if(!SymbolInfoSessionQuote(symbol, day, idx, from, to))
            break;
         opens[n]  = (long)d * DAY + (long)from * 1000;
         closes[n] = (long)d * DAY + (long)to   * 1000;
         n++;
        }
     }

   //--- a symbol that declares no sessions tells us nothing; fall back
   //--- rather than declaring the whole week a closure
   if(n == 0)
      return SSR_SESSION_GAP_MSC;

   long widest = 0;
   for(int i = 1; i < n; i++)
     {
      long gap = opens[i] - closes[i - 1];
      if(gap > widest)
         widest = gap;
     }

   //--- and the wrap: the weekend usually lives here, between Friday's
   //--- close and Monday's open
   long wrap = (opens[0] + WEEK) - closes[n - 1];
   if(wrap > widest)
      widest = wrap;

   //--- never below an hour, or every lunch break reads as damage
   if(widest < SSR_SESSION_GAP_MSC)
      widest = SSR_SESSION_GAP_MSC;
   return widest;
  }

//+------------------------------------------------------------------+
class CSSRDataValidator
  {
private:
   long              m_session_gap_msc;

public:
                     CSSRDataValidator(void) : m_session_gap_msc(SSR_SESSION_GAP_MSC) {}

   void              SetSessionGap(const long msc) { m_session_gap_msc = msc; }

   //--- derive the threshold from the symbol rather than assuming it
   void              LearnFrom(const string symbol)
     { m_session_gap_msc = SSRSymbolSessionGap(symbol); }
   long              SessionGap(void)              { return m_session_gap_msc; }

   //+------------------------------------------------------------------+
   //| Inspect an M1 series without modifying it.                       |
   //| Assumes nothing about ordering - that is one of the things it     |
   //| is looking for.                                                   |
   //+------------------------------------------------------------------+
   void              ValidateBars(const MqlRates &bars[], const int count, SSRDataReport &rep)
     {
      rep.Init();
      if(count <= 0)
         return;

      rep.total     = count;
      rep.first_msc = SSRToMsc(bars[0].time);
      rep.last_msc  = SSRToMsc(bars[count - 1].time) + SSR_MSC_PER_MIN - 1;

      long prev = SSR_INVALID_TIME;
      for(int i = 0; i < count; i++)
        {
         long t = SSRToMsc(bars[i].time);

         if(prev != SSR_INVALID_TIME)
           {
            if(t == prev)
               rep.duplicates++;
            else if(t < prev)
               rep.out_of_order++;
            else
              {
               long gap = t - prev - SSR_MSC_PER_MIN;
               if(gap > 0)
                 {
                  if(gap >= m_session_gap_msc) rep.session_gaps++;
                  else                         rep.micro_gaps++;
                  if(gap > rep.largest_gap_msc)
                     rep.largest_gap_msc = gap;
                 }
              }
           }

         //--- OHLC invariants. A bar violating these would make every
         //--- higher timeframe derived from it wrong, so it is fatal
         //--- rather than cosmetic.
         double hi = bars[i].high, lo = bars[i].low;
         double op = bars[i].open, cl = bars[i].close;
         if(hi < lo || hi < MathMax(op, cl) || lo > MathMin(op, cl))
            rep.invalid_ohlc++;
         if(op <= 0.0 || hi <= 0.0 || lo <= 0.0 || cl <= 0.0)
            rep.nonpositive++;

         if(t > prev || prev == SSR_INVALID_TIME)
            prev = t;
        }
     }

   //+------------------------------------------------------------------+
   //| Make a series safe to replay: strictly increasing open times,    |
   //| no duplicates. Returns the surviving count.                      |
   //|                                                                  |
   //| Out-of-order bars are DROPPED, not re-sorted. Sorting would      |
   //| invent an ordering the feed never had; dropping is visible in    |
   //| the report and leaves the caller able to reload the range.       |
   //+------------------------------------------------------------------+
   int               SanitizeBars(MqlRates &bars[], const int count)
     {
      if(count <= 0)
         return 0;
      int keep = 1;
      long prev = SSRToMsc(bars[0].time);
      for(int i = 1; i < count; i++)
        {
         long t = SSRToMsc(bars[i].time);
         if(t <= prev)
            continue;                    // duplicate or backwards: drop
         if(keep != i)
            bars[keep] = bars[i];
         prev = t;
         keep++;
        }
      return keep;
     }

   //+------------------------------------------------------------------+
   //| Ticks differ from bars in one important way: two ticks MAY share |
   //| a millisecond legitimately, so only a strictly backwards stamp   |
   //| is dropped.                                                      |
   //+------------------------------------------------------------------+
   int               SanitizeTicks(MqlTick &ticks[], const int count)
     {
      if(count <= 0)
         return 0;
      int keep = 1;
      long prev = ticks[0].time_msc;
      for(int i = 1; i < count; i++)
        {
         if(ticks[i].time_msc < prev)
            continue;                    // backwards: drop
         if(keep != i)
            ticks[keep] = ticks[i];
         prev = ticks[i].time_msc;
         keep++;
        }
      return keep;
     }

   void              ValidateTicks(const MqlTick &ticks[], const int count, SSRDataReport &rep)
     {
      rep.Init();
      if(count <= 0)
         return;
      rep.total     = count;
      rep.first_msc = ticks[0].time_msc;
      rep.last_msc  = ticks[count - 1].time_msc;

      long prev = SSR_INVALID_TIME;
      for(int i = 0; i < count; i++)
        {
         long t = ticks[i].time_msc;
         if(prev != SSR_INVALID_TIME)
           {
            if(t < prev)
               rep.out_of_order++;
            else if(t == prev)
               rep.duplicates++;          // legal for ticks; counted, not condemned
            else
              {
               long gap = t - prev;
               if(gap >= m_session_gap_msc)
                  rep.session_gaps++;
               if(gap > rep.largest_gap_msc)
                  rep.largest_gap_msc = gap;
              }
           }
         if(ticks[i].bid <= 0.0 && ticks[i].last <= 0.0)
            rep.nonpositive++;
         if(t >= prev || prev == SSR_INVALID_TIME)
            prev = t;
        }
     }
  };

#endif // SSR_DATA_VALIDATOR_MQH
//+------------------------------------------------------------------+
