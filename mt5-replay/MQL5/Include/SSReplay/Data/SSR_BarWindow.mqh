//+------------------------------------------------------------------+
//|                                                SSR_BarWindow.mqh |
//|                        SS Replay - Bounded M1 Read Window (L1)   |
//|                                                                  |
//|  A BOUNDED READ WINDOW, NOT A CACHE.                             |
//|                                                                  |
//|  The distinction matters. A cache (Phase 6) persists, spans      |
//|  symbols, and survives a session. This holds exactly one         |
//|  contiguous range of M1 bars for one symbol, in memory, and      |
//|  throws it away the moment the replay cursor walks out of it.    |
//|                                                                  |
//|  It exists because without it every Pump() would call CopyRates  |
//|  again - a terminal round trip per replay tick. That is not a    |
//|  performance nicety, it is the difference between an engine that |
//|  works and one that has to be redesigned in Phase 7.             |
//|                                                                  |
//|  Loading is asynchronous in MetaTrader: the first CopyRates for  |
//|  a range usually returns -1 while the terminal fetches it. The   |
//|  retry loop here is the single place that fact is handled.       |
//+------------------------------------------------------------------+
#ifndef SSR_BAR_WINDOW_MQH
#define SSR_BAR_WINDOW_MQH

#include "../Common/SSR_Types.mqh"
#include "../Common/SSR_Time.mqh"
#include "../Common/SSR_Platform.mqh"
#include "SSR_DataValidator.mqh"

//--- window sizing. 20,000 M1 bars is about two weeks of continuous
//--- market time and a few megabytes - large enough that the cursor
//--- rarely leaves it, small enough to reload without a visible stall.
#define SSR_WINDOW_BARS_DEFAULT    20000
#define SSR_WINDOW_LOAD_TIMEOUT_MS 15000
#define SSR_WINDOW_RETRY_SLEEP_MS  50

//+------------------------------------------------------------------+
class CSSRBarWindow
  {
private:
   MqlRates          m_bars[];
   int               m_count;
   bool              m_valid;      // a loaded range, even one holding no bars
   string            m_symbol;
   long              m_from_msc;        // covered range, inclusive of bar opens
   long              m_to_msc;
   int               m_window_bars;
   CSSRDataValidator m_validator;
   SSRDataReport     m_last_report;

   //--- instrumentation, so Phase 7 tunes with numbers not opinions
   long              m_hits;
   long              m_misses;
   long              m_loads;
   long              m_bars_loaded;
   long              m_load_time_ms;
   long              m_dropped;         // bars removed by sanitisation

   ENUM_SSR_ERR      m_last_error;
   string            m_last_error_text;

   void              Fail(const ENUM_SSR_ERR e, const string t)
     { m_last_error = e; m_last_error_text = t; }

   //+------------------------------------------------------------------+
   //| CopyRates with the async retry MetaTrader requires.              |
   //| Returns the bar count, or -1 when the range never arrives.       |
   //+------------------------------------------------------------------+
   int               LoadRange(const string symbol, const long from_msc, const long to_msc,
                               MqlRates &out[])
     {
      datetime from_dt = SSRToTime(from_msc);
      datetime to_dt   = SSRToTime(to_msc);

      ulong t0 = SSRMicros();
      int   got = -1;

      while(SSRElapsedMs(t0) < SSR_WINDOW_LOAD_TIMEOUT_MS)
        {
         ResetLastError();
         ArraySetAsSeries(out, false);
         got = CopyRates(symbol, PERIOD_M1, from_dt, to_dt, out);
         if(got > 0)
            break;

         //--- 0 is not -1. Zero bars means the range genuinely holds
         //--- none - a weekend, a holiday, a session break - and that
         //--- is normal data, not a failure. Only retry it while the
         //--- series is still syncing; once synced, believe the zero
         //--- instead of spinning out the whole timeout.
         if(got == 0)
           {
            long synced = 0;
            if(SeriesInfoInteger(symbol, PERIOD_M1, SERIES_SYNCHRONIZED, synced) && synced != 0)
               break;
           }

         //--- an indicator cannot wait, so it gets one attempt and an
         //--- honest failure rather than a frozen terminal
         if(!SSRCanBlock())
            break;
         SSRPause(SSR_WINDOW_RETRY_SLEEP_MS);
        }

      m_load_time_ms += (long)SSRElapsedMs(t0);
      return got;
     }

public:
                     CSSRBarWindow(void)
     : m_count(0), m_valid(false), m_symbol(""), m_from_msc(SSR_INVALID_TIME), m_to_msc(SSR_INVALID_TIME),
       m_window_bars(SSR_WINDOW_BARS_DEFAULT), m_hits(0), m_misses(0), m_loads(0),
       m_bars_loaded(0), m_load_time_ms(0), m_dropped(0),
       m_last_error(SSR_OK), m_last_error_text("")
     { m_last_report.Init(); }

   void              SetWindowBars(const int n) { m_window_bars = (n < 256 ? 256 : n); }
   int               WindowBars(void)           { return m_window_bars; }

   void              Invalidate(void)
     {
      m_count    = 0;
      m_valid    = false;
      m_from_msc = SSR_INVALID_TIME;
      m_to_msc   = SSR_INVALID_TIME;
      ArrayResize(m_bars, 0);
     }

   //+------------------------------------------------------------------+
   //| Does the window already cover this request?                      |
   //|                                                                  |
   //| A window holding ZERO bars can still be a valid answer: the      |
   //| range was loaded and the market was closed. Requiring bars here  |
   //| meant every pump across a weekend reloaded the same empty range. |
   //+------------------------------------------------------------------+
   bool              Covers(const string symbol, const long from_msc, const long to_msc)
     {
      return (m_valid && symbol == m_symbol &&
              from_msc >= m_from_msc && to_msc <= m_to_msc);
     }

   //+------------------------------------------------------------------+
   //| Guarantee the window covers [from_msc, to_msc], reloading if it  |
   //| does not. The reload extends forward from `from_msc` by the      |
   //| window size, because replay walks forward - loading symmetrically|
   //| around the request would throw away half the buffer on every     |
   //| step.                                                            |
   //+------------------------------------------------------------------+
   bool              Ensure(const string symbol, const long from_msc, const long to_msc)
     {
      if(from_msc > to_msc)
        {
         Fail(SSR_ERR_INVALID_ARG, "inverted range");
         return false;
        }

      if(Covers(symbol, from_msc, to_msc))
        {
         m_hits++;
         return true;
        }
      m_misses++;

      //--- span the request, then extend forward to the window size
      long span_bars = (to_msc - from_msc) / SSR_MSC_PER_MIN + 1;
      long want_bars = (span_bars > m_window_bars ? span_bars : m_window_bars);

      long lo = SSRBarOpenMsc(from_msc, PERIOD_M1);
      long hi = lo + want_bars * SSR_MSC_PER_MIN;
      if(hi < to_msc)
         hi = SSRBarOpenMsc(to_msc, PERIOD_M1) + SSR_MSC_PER_MIN;

      //--- a new symbol brings its own idea of what a gap means
      if(symbol != m_symbol)
         m_validator.LearnFrom(symbol);

      MqlRates tmp[];
      int got = LoadRange(symbol, lo, hi, tmp);
      m_loads++;

      if(got < 0)
        {
         Fail(SSR_ERR_LOAD_FAILED,
              StringFormat("CopyRates(%s, %s..%s) failed err=%d",
                           symbol, SSRFormatMsc(lo), SSRFormatMsc(hi), GetLastError()));
         Invalidate();
         return false;
        }

      if(got == 0)
        {
         //--- a real, empty answer. Record the range as covered so the
         //--- next pump is served from here instead of asking again.
         ArrayResize(m_bars, 0);
         m_count    = 0;
         m_valid    = true;
         m_symbol   = symbol;
         m_from_msc = lo;
         m_to_msc   = hi;
         m_last_error = SSR_OK;
         m_last_error_text = "";
         return true;
        }

      //--- broker history is not guaranteed clean; make it replay-safe
      m_validator.ValidateBars(tmp, got, m_last_report);
      int clean = m_validator.SanitizeBars(tmp, got);
      m_dropped += (got - clean);

      if(clean <= 0)
        {
         Fail(SSR_ERR_NO_DATA, "range contained no usable bars after validation");
         Invalidate();
         return false;
        }
      if(!m_last_report.IsUsable())
        {
         Fail(SSR_ERR_NO_DATA, "range failed validation: " + m_last_report.ToString());
         Invalidate();
         return false;
        }

      if(ArrayResize(m_bars, clean) < clean)
        {
         Fail(SSR_ERR_INTERNAL, "window resize failed");
         Invalidate();
         return false;
        }
      for(int i = 0; i < clean; i++)
         m_bars[i] = tmp[i];

      m_count       = clean;
      m_valid       = true;
      m_symbol      = symbol;
      m_from_msc    = SSRToMsc(m_bars[0].time);
      m_to_msc      = SSRToMsc(m_bars[clean - 1].time) + SSR_MSC_PER_MIN - 1;
      m_bars_loaded += clean;

      //--- the bars returned may sit inside a narrower span than asked
      //--- for. The COVERAGE is still the requested range: we asked, the
      //--- terminal answered, and re-asking would return the same thing.
      //--- Recording only the bar span would reload on every pump.
      if(lo < m_from_msc) m_from_msc = lo;
      if(hi > m_to_msc)   m_to_msc   = hi;

      m_last_error = SSR_OK;
      m_last_error_text = "";
      return true;
     }

   //+------------------------------------------------------------------+
   //| Copy bars whose OPEN time lies in [from_msc, to_msc] out of the  |
   //| window. Never touches the terminal.                              |
   //+------------------------------------------------------------------+
   int               Read(const long from_msc, const long to_msc, MqlRates &out[])
     {
      if(m_count <= 0)
         return 0;

      //--- binary search for the first bar at or after from_msc
      int lo = 0, hi = m_count;
      while(lo < hi)
        {
         int mid = (lo + hi) / 2;
         if(SSRToMsc(m_bars[mid].time) < from_msc) lo = mid + 1;
         else                                      hi = mid;
        }

      int n = 0;
      for(int i = lo; i < m_count; i++)
        {
         if(SSRToMsc(m_bars[i].time) > to_msc)
            break;
         n++;
        }
      if(n <= 0)
         return 0;
      if(ArraySize(out) < n && ArrayResize(out, n) < n)
        {
         Fail(SSR_ERR_INTERNAL, "output resize failed");
         return -1;
        }
      for(int i = 0; i < n; i++)
         out[i] = m_bars[lo + i];
      return n;
     }

   bool              ReadAt(const long msc, MqlRates &out)
     {
      long open = SSRBarOpenMsc(msc, PERIOD_M1);
      if(m_count <= 0 || open < m_from_msc || open > m_to_msc)
         return false;
      int lo = 0, hi = m_count;
      while(lo < hi)
        {
         int mid = (lo + hi) / 2;
         if(SSRToMsc(m_bars[mid].time) < open) lo = mid + 1;
         else                                  hi = mid;
        }
      if(lo >= m_count || SSRToMsc(m_bars[lo].time) != open)
         return false;
      out = m_bars[lo];
      return true;
     }

   //--- accessors ---------------------------------------------------
   int               Count(void)     { return m_count; }
   long              FromMsc(void)   { return m_from_msc; }
   long              ToMsc(void)     { return m_to_msc; }
   string            Symbol(void)    { return m_symbol; }
   ENUM_SSR_ERR      LastError(void) { return m_last_error; }
   string            LastErrorText(void) { return m_last_error_text; }

   long              Hits(void)       { return m_hits; }
   long              Misses(void)     { return m_misses; }
   long              Loads(void)      { return m_loads; }
   long              BarsLoaded(void) { return m_bars_loaded; }
   long              LoadTimeMs(void) { return m_load_time_ms; }
   long              Dropped(void)    { return m_dropped; }

   double            HitRate(void)
     {
      long total = m_hits + m_misses;
      return (total > 0 ? (double)m_hits / (double)total : 0.0);
     }

   void              ReportInto(SSRDataReport &out) { out = m_last_report; }

   string            ToString(void)
     {
      return StringFormat("window[%s %s..%s bars=%d hit=%.1f%% loads=%d dropped=%d]",
                          m_symbol, SSRFormatMsc(m_from_msc), SSRFormatMsc(m_to_msc),
                          m_count, HitRate() * 100.0, (int)m_loads, (int)m_dropped);
     }
  };

#endif // SSR_BAR_WINDOW_MQH
//+------------------------------------------------------------------+
