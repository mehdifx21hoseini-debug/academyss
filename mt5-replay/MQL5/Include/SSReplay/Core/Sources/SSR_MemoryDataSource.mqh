//+------------------------------------------------------------------+
//|                                          SSR_MemoryDataSource.mqh |
//|                        SS Replay - In-Memory Data Source (L1)    |
//|                                                                  |
//|  A complete CSSRDataSource backed by an M1 array held in memory. |
//|                                                                  |
//|  It exists so the engine can be exercised with ZERO dependency   |
//|  on a broker, a terminal connection, or downloaded history. Every|
//|  core test runs against this, which is what makes those tests    |
//|  deterministic and runnable anywhere.                            |
//|                                                                  |
//|  It is also the reference implementation of the contracts: any   |
//|  future source (broker, CSV) should behave identically here.     |
//+------------------------------------------------------------------+
#ifndef SSR_MEMORY_DATASOURCE_MQH
#define SSR_MEMORY_DATASOURCE_MQH

#include "../SSR_IDataSource.mqh"
#include "../../Common/SSR_Time.mqh"

//+------------------------------------------------------------------+
//| Shared M1 store. The providers below read from one instance so   |
//| they cannot drift apart.                                         |
//+------------------------------------------------------------------+
class CSSRMemoryStore
  {
public:
   MqlRates          bars[];
   MqlTick           ticks[];
   string            symbol;

                     CSSRMemoryStore(void) : symbol("") {}

   int               BarCount(void)  { return ArraySize(bars); }
   int               TickCount(void) { return ArraySize(ticks); }

   long              FirstMsc(void)
     {
      return (ArraySize(bars) > 0 ? SSRToMsc(bars[0].time) : SSR_INVALID_TIME);
     }

   //--- the last instant COVERED by the data, i.e. the close of the
   //--- final bar, not its open. Getting this wrong shortens every
   //--- replay window by one bar.
   long              LastMsc(void)
     {
      int n = ArraySize(bars);
      if(n <= 0)
         return SSR_INVALID_TIME;
      return SSRToMsc(bars[n - 1].time) + SSR_MSC_PER_MIN - 1;
     }

   //--- index of the first bar whose open time is >= msc; n when none
   int               LowerBound(const long msc)
     {
      int lo = 0, hi = ArraySize(bars);
      while(lo < hi)
        {
         int mid = (lo + hi) / 2;
         if(SSRToMsc(bars[mid].time) < msc) lo = mid + 1;
         else                               hi = mid;
        }
      return lo;
     }
  };

//+------------------------------------------------------------------+
class CSSRMemoryHistoryProvider : public CSSRHistoryProvider
  {
private:
   CSSRMemoryStore  *m_store;
public:
                     CSSRMemoryHistoryProvider(CSSRMemoryStore *s) : m_store(s) {}

   virtual bool      Discover(const string symbol, SSRDataRange &out) override
     {
      out.Init();
      if(m_store == NULL || m_store.BarCount() <= 0)
        {
         Fail(SSR_ERR_NO_DATA, "memory store is empty");
         return false;
        }
      out.available        = true;
      out.first_msc        = m_store.FirstMsc();
      out.last_msc         = m_store.LastMsc();
      out.server_first_msc = out.first_msc;   // memory has no deeper origin
      out.bar_count        = m_store.BarCount();
      out.has_ticks        = (m_store.TickCount() > 0);
      Succeed();
      return true;
     }

   virtual bool      Ensure(const string symbol, const long from_msc, const long to_msc) override
     {
      Succeed();
      return (m_store != NULL && m_store.BarCount() > 0);
     }

   virtual long      ExtendBackwards(const string symbol, const long bars) override
     {
      //--- an in-memory dataset cannot grow; report the unchanged bound
      Succeed();
      return (m_store != NULL ? m_store.FirstMsc() : SSR_INVALID_TIME);
     }
  };

//+------------------------------------------------------------------+
class CSSRMemoryBarProvider : public CSSRBarProvider
  {
private:
   CSSRMemoryStore  *m_store;
public:
                     CSSRMemoryBarProvider(CSSRMemoryStore *s) : m_store(s) {}

   virtual int       ReadBars(const string symbol, const long from_msc,
                              const long to_msc, MqlRates &out[]) override
     {
      if(m_store == NULL) { Fail(SSR_ERR_NO_DATA, "no store"); return -1; }

      long lo = from_msc, hi = to_msc;
      //--- guard layer 2: the provider itself refuses the future
      if(!GuardRange(lo, hi))
        {
         Succeed();
         return 0;
        }

      int start = m_store.LowerBound(lo);
      int n = 0;
      int total = m_store.BarCount();
      for(int i = start; i < total; i++)
        {
         long t = SSRToMsc(m_store.bars[i].time);
         if(t > hi)
            break;
         n++;
        }
      if(n <= 0) { Succeed(); return 0; }
      if(ArraySize(out) < n && ArrayResize(out, n) < n)
        {
         Fail(SSR_ERR_INTERNAL, "resize failed");
         return -1;
        }
      for(int i = 0; i < n; i++)
         out[i] = m_store.bars[start + i];
      Succeed();
      return n;
     }

   virtual bool      ReadBarAt(const string symbol, const long msc, MqlRates &out) override
     {
      if(m_store == NULL) { Fail(SSR_ERR_NO_DATA, "no store"); return false; }
      long open = SSRBarOpenMsc(msc, PERIOD_M1);
      if(m_guard != NULL && !m_guard.Allows(open))
        {
         m_guard.Violation(open);
         Fail(SSR_ERR_FUTURE_ACCESS, "bar is beyond the horizon");
         return false;
        }
      int i = m_store.LowerBound(open);
      if(i >= m_store.BarCount() || SSRToMsc(m_store.bars[i].time) != open)
        {
         Fail(SSR_ERR_NO_DATA, "no bar at that time");
         return false;
        }
      out = m_store.bars[i];
      Succeed();
      return true;
     }

   virtual long      BarCount(const string symbol) override
     {
      return (m_store != NULL ? m_store.BarCount() : 0);
     }
  };

//+------------------------------------------------------------------+
class CSSRMemoryTickProvider : public CSSRTickProvider
  {
private:
   CSSRMemoryStore  *m_store;
public:
                     CSSRMemoryTickProvider(CSSRMemoryStore *s) : m_store(s) {}

   virtual bool      HasTicks(const string symbol, const long from_msc, const long to_msc) override
     {
      return (m_store != NULL && m_store.TickCount() > 0);
     }

   virtual int       ReadTicks(const string symbol, const long from_msc,
                               const long to_msc, MqlTick &out[]) override
     {
      if(m_store == NULL) { Fail(SSR_ERR_NO_DATA, "no store"); return -1; }

      long lo = from_msc, hi = to_msc;
      if(!GuardRange(lo, hi))
        {
         Succeed();
         return 0;
        }

      int total = m_store.TickCount();
      int n = 0;
      for(int i = 0; i < total; i++)
        {
         long t = m_store.ticks[i].time_msc;
         if(t > lo && t <= hi)
            n++;
        }
      if(n <= 0) { Succeed(); return 0; }
      if(ArraySize(out) < n && ArrayResize(out, n) < n)
        {
         Fail(SSR_ERR_INTERNAL, "resize failed");
         return -1;
        }
      int k = 0;
      for(int i = 0; i < total && k < n; i++)
        {
         long t = m_store.ticks[i].time_msc;
         if(t > lo && t <= hi)
            out[k++] = m_store.ticks[i];
        }
      Succeed();
      return k;
     }
  };

//+------------------------------------------------------------------+
class CSSRMemoryDataSource : public CSSRDataSource
  {
private:
   CSSRMemoryStore            m_store;
   CSSRMemoryHistoryProvider *m_hist;
   CSSRMemoryBarProvider     *m_bars;
   CSSRMemoryTickProvider    *m_ticks;

public:
                     CSSRMemoryDataSource(void)
     {
      m_mode  = SSR_DATA_MEMORY;
      m_hist  = new CSSRMemoryHistoryProvider(GetPointer(m_store));
      m_bars  = new CSSRMemoryBarProvider(GetPointer(m_store));
      m_ticks = new CSSRMemoryTickProvider(GetPointer(m_store));
     }

                    ~CSSRMemoryDataSource(void)
     {
      if(CheckPointer(m_hist)  == POINTER_DYNAMIC) delete m_hist;
      if(CheckPointer(m_bars)  == POINTER_DYNAMIC) delete m_bars;
      if(CheckPointer(m_ticks) == POINTER_DYNAMIC) delete m_ticks;
     }

   virtual string    Name(void) override { return "memory"; }

   virtual bool      Open(const string symbol) override
     {
      m_store.symbol = symbol;
      m_open = (m_store.BarCount() > 0);
      return m_open;
     }

   virtual void      Close(void) override { m_open = false; }

   virtual CSSRHistoryProvider *History(void) override { return m_hist;  }
   virtual CSSRBarProvider     *Bars(void)    override { return m_bars;  }
   virtual CSSRTickProvider    *Ticks(void)   override
     {
      //--- report honestly: no ticks loaded means no tick provider,
      //--- so the engine degrades fidelity instead of emitting nothing
      return (m_store.TickCount() > 0 ? m_ticks : NULL);
     }

   //--- loading -----------------------------------------------------
   bool              LoadBars(const MqlRates &src[], const int count)
     {
      if(count <= 0)
         return false;
      if(ArrayResize(m_store.bars, count) < count)
         return false;
      for(int i = 0; i < count; i++)
         m_store.bars[i] = src[i];
      return true;
     }

   bool              LoadTicks(const MqlTick &src[], const int count)
     {
      if(count <= 0)
        {
         ArrayResize(m_store.ticks, 0);
         return true;
        }
      if(ArrayResize(m_store.ticks, count) < count)
         return false;
      for(int i = 0; i < count; i++)
         m_store.ticks[i] = src[i];
      return true;
     }

   CSSRMemoryStore  *Store(void) { return GetPointer(m_store); }
  };

#endif // SSR_MEMORY_DATASOURCE_MQH
//+------------------------------------------------------------------+
