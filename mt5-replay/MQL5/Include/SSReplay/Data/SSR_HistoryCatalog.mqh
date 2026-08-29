//+------------------------------------------------------------------+
//|                                          SSR_HistoryCatalog.mqh  |
//|                     SS Replay - What History Exists, and What It |
//|                                  Costs to Use (L1/Data)          |
//|                                                                  |
//|  The design document's arithmetic, made executable:              |
//|                                                                  |
//|      200 daily candles need 288,000 M1 bars behind them.         |
//|                                                                  |
//|  A user who picks "D1 context" and then waits four minutes with  |
//|  no explanation concludes the tool is broken. The same wait,     |
//|  quoted first and accepted, is just a load. This class exists to |
//|  make the second thing possible.                                 |
//+------------------------------------------------------------------+
#ifndef SSR_HISTORY_CATALOG_MQH
#define SSR_HISTORY_CATALOG_MQH

#include "../Common/SSR_Types.mqh"
#include "../Common/SSR_Time.mqh"
#include "../Common/SSR_Platform.mqh"
#include "../Core/SSR_IDataSource.mqh"

//--- Seed throughput, bars per second. The STARTING guess only: the
//--- engine measures its own seed and feeds the real figure back through
//--- SetMeasuredSeedRate, so every quote after the first session is
//--- taken from this machine rather than from this line.
#define SSR_SEED_BARS_PER_SEC_DEFAULT   6000.0
//--- rough on-disk cost of one M1 bar in the custom symbol store
#define SSR_SEED_BYTES_PER_BAR          60

//+------------------------------------------------------------------+
//| What a proposed session will cost before anything is written.    |
//+------------------------------------------------------------------+
struct SSRSeedQuote
  {
   long              warmup_bars;
   long              replay_bars;
   long              total_bars;
   double            seconds;
   double            megabytes;
   bool              exceeds_history;   // the broker simply does not have it
   bool              exceeds_maxbars;   // the terminal will not display it
   long              available_bars;

   void              Init(void)
     {
      warmup_bars = 0; replay_bars = 0; total_bars = 0;
      seconds = 0.0; megabytes = 0.0;
      exceeds_history = false; exceeds_maxbars = false; available_bars = 0;
      measured = false;
     }

   bool              measured;        // is the time figure real or a guess?

   bool              IsFeasible(void) { return (!exceeds_history && total_bars > 0); }

   string            ToString(void)
     {
      if(exceeds_history)
         return StringFormat("needs %d M1 bars, broker has %d",
                             (int)total_bars, (int)available_bars);
      return StringFormat("%d bars, %s%.0fs, %.1f MB",
                          (int)total_bars,
                          (measured ? "" : "about "), seconds, megabytes);
     }
  };

//+------------------------------------------------------------------+
class CSSRHistoryCatalog
  {
private:
   CSSRHistoryProvider *m_hist;     // not owned
   SSRDataRange         m_range;
   string               m_symbol;
   double               m_bars_per_sec;
   bool                 m_measured;

public:
                     CSSRHistoryCatalog(void)
     : m_hist(NULL), m_symbol(""),
       m_bars_per_sec(SSR_SEED_BARS_PER_SEC_DEFAULT), m_measured(false)
     { m_range.Init(); }

   void              Attach(CSSRHistoryProvider *h) { m_hist = h; }

   //--- once spike D1 has run, feed it the measured figure and every
   //--- quote the panel shows becomes real instead of estimated
   void              SetMeasuredSeedRate(const double bars_per_sec)
     {
      if(bars_per_sec <= 0.0)
         return;
      m_bars_per_sec = bars_per_sec;
      m_measured     = true;
     }
   double            SeedRate(void)     { return m_bars_per_sec; }
   bool              RateMeasured(void) { return m_measured; }

   bool              Scan(const string symbol)
     {
      m_symbol = symbol;
      m_range.Init();
      if(m_hist == NULL)
         return false;
      return m_hist.Discover(symbol, m_range);
     }

   void              RangeInto(SSRDataRange &out) { out = m_range; }
   bool              Available(void)  { return m_range.available; }
   long              FirstMsc(void)   { return m_range.first_msc; }
   long              LastMsc(void)    { return m_range.last_msc; }
   long              BarCount(void)   { return m_range.bar_count; }
   bool              HasTicks(void)   { return m_range.has_ticks; }
   bool              CanExtend(void)  { return m_range.CanExtendBackwards(); }

   //+------------------------------------------------------------------+
   //| M1 bars required to show `visible` candles of `tf` at the moment |
   //| replay begins. This is the 288,000-bar arithmetic.               |
   //+------------------------------------------------------------------+
   static long       WarmupFor(const ENUM_TIMEFRAMES tf, const long visible)
     {
      int secs = PeriodSeconds(tf);
      if(secs <= 60)
         return visible;
      return visible * (long)(secs / 60);
     }

   //+------------------------------------------------------------------+
   //| Quote a session before committing to it.                         |
   //+------------------------------------------------------------------+
   void              Quote(const ENUM_TIMEFRAMES max_tf, const long visible_bars,
                           const long replay_minutes, SSRSeedQuote &q)
     {
      q.Init();
      q.warmup_bars = WarmupFor(max_tf, visible_bars);
      q.replay_bars = replay_minutes;
      q.total_bars  = q.warmup_bars + q.replay_bars;

      q.seconds  = (m_bars_per_sec > 0.0 ? (double)q.total_bars / m_bars_per_sec : 0.0);
      q.measured = m_measured;
      q.megabytes = (double)q.total_bars * SSR_SEED_BYTES_PER_BAR / 1048576.0;

      q.available_bars  = m_range.bar_count;
      q.exceeds_history = (m_range.available && q.total_bars > m_range.bar_count);

      long maxbars = SSRMaxBarsInChart();
      //--- 0 means unlimited in the terminal settings
      q.exceeds_maxbars = (maxbars > 0 && q.total_bars > maxbars);
     }

   //+------------------------------------------------------------------+
   //| Latest instant a session may start at, leaving room for warmup   |
   //| and for at least `replay_minutes` of replay after it.            |
   //+------------------------------------------------------------------+
   long              LatestStart(const long warmup_bars, const long replay_minutes)
     {
      if(!m_range.available)
         return SSR_INVALID_TIME;
      long latest = m_range.last_msc - replay_minutes * SSR_MSC_PER_MIN;
      long floor_ = m_range.first_msc + warmup_bars * SSR_MSC_PER_MIN;
      return (latest < floor_ ? SSR_INVALID_TIME : latest);
     }

   long              EarliestStart(const long warmup_bars)
     {
      if(!m_range.available)
         return SSR_INVALID_TIME;
      return m_range.first_msc + warmup_bars * SSR_MSC_PER_MIN;
     }

   //--- is this a start the broker can actually serve?
   bool              CanStartAt(const long start_msc, const long warmup_bars)
     {
      if(!m_range.available || start_msc <= 0)
         return false;
      long earliest = EarliestStart(warmup_bars);
      return (start_msc >= earliest && start_msc < m_range.last_msc);
     }

   //+------------------------------------------------------------------+
   //| Ask the broker for deeper history. Returns bars gained.          |
   //+------------------------------------------------------------------+
   long              LoadMore(const long bars)
     {
      if(m_hist == NULL || !m_range.available)
         return 0;
      long before = m_range.first_msc;
      long after  = m_hist.ExtendBackwards(m_symbol, bars);
      if(after <= 0 || after >= before)
         return 0;
      //--- refresh, so a caller that quotes again sees the new depth
      m_hist.Discover(m_symbol, m_range);
      return (before - after) / SSR_MSC_PER_MIN;
     }

   //+------------------------------------------------------------------+
   //| A sensible read-window size for this session.                    |
   //|                                                                  |
   //| Closes the guessed constant from Phase 2: the window is sized    |
   //| from the session rather than fixed, so a short replay does not   |
   //| hold two weeks of bars and a long one does not thrash.           |
   //+------------------------------------------------------------------+
   static int        SuggestWindowBars(const long replay_minutes)
     {
      long want = replay_minutes / 4;
      if(want < 5000)  want = 5000;
      if(want > 60000) want = 60000;
      return (int)want;
     }

   string            ToString(void)
     {
      if(!m_range.available)
         return StringFormat("catalog[%s unavailable]", m_symbol);
      return StringFormat("catalog[%s %s..%s bars=%d ticks=%s deeper=%s]",
                          m_symbol,
                          SSRFormatMsc(m_range.first_msc), SSRFormatMsc(m_range.last_msc),
                          (int)m_range.bar_count,
                          (m_range.has_ticks ? "yes" : "no"),
                          (m_range.CanExtendBackwards() ? "yes" : "no"));
     }
  };

#endif // SSR_HISTORY_CATALOG_MQH
//+------------------------------------------------------------------+
