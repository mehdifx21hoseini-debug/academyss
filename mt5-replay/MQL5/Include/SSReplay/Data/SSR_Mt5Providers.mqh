//+------------------------------------------------------------------+
//|                                             SSR_Mt5Providers.mqh |
//|                     SS Replay - MT5 Broker Data Providers (L1)   |
//|                                                                  |
//|  The first code in the product that talks to MetaTrader.         |
//|  Everything above this file still believes it is talking to the  |
//|  abstract contracts from Phase 1.                                |
//|                                                                  |
//|  Two MetaTrader facts shape all three classes:                   |
//|                                                                  |
//|  1. History arrives ASYNCHRONOUSLY. The first CopyRates for a    |
//|     range typically returns -1 while the terminal downloads it.  |
//|     Treating that as "no data" is the single most common bug in  |
//|     MQL5 data code.                                              |
//|                                                                  |
//|  2. Tick history is OPTIONAL and usually shallow, especially for |
//|     CFDs. The tick provider reports honestly rather than         |
//|     returning an empty array that the engine would read as       |
//|     "a quiet market".                                            |
//+------------------------------------------------------------------+
#ifndef SSR_MT5_PROVIDERS_MQH
#define SSR_MT5_PROVIDERS_MQH

#include "../Common/SSR_Types.mqh"
#include "../Common/SSR_Time.mqh"
#include "../Common/SSR_Platform.mqh"
#include "../Core/SSR_IDataSource.mqh"
#include "SSR_BarWindow.mqh"
#include "SSR_DataValidator.mqh"

//--- how long to wait for MetaTrader to deliver history it is fetching
//--- from the server. Generous on purpose: giving up early reports "no
//--- data" for a symbol that simply had not arrived yet.
#define SSR_SYNC_TIMEOUT_MS     20000
#define SSR_TICK_TIMEOUT_MS     15000
//--- a hard stop on the paging loop. Not a tuning figure: it exists so
//--- a provider that stops making forward progress cannot spin forever.
#define SSR_TICK_PAGE_GUARD     64

//+------------------------------------------------------------------+
//| History discovery and preparation.                               |
//+------------------------------------------------------------------+
class CSSRMt5HistoryProvider : public CSSRHistoryProvider
  {
private:
   long              m_sync_wait_ms;
   long              m_ensure_calls;

   //--- nudge the terminal into fetching, then wait for the series
   bool              WaitForSeries(const string symbol, const int timeout_ms)
     {
      MqlRates warm[];
      ArraySetAsSeries(warm, false);
      CopyRates(symbol, PERIOD_M1, 0, 2, warm);

      ulong t0 = SSRMicros();
      while(SSRElapsedMs(t0) < timeout_ms)
        {
         long synced = 0;
         if(SeriesInfoInteger(symbol, PERIOD_M1, SERIES_SYNCHRONIZED, synced) && synced != 0)
           {
            m_sync_wait_ms += (long)SSRElapsedMs(t0);
            return true;
           }
         if(!SSRCanBlock())
            break;
         SSRPause(50);
         CopyRates(symbol, PERIOD_M1, 0, 2, warm);
        }
      m_sync_wait_ms += (long)SSRElapsedMs(t0);
      return false;
     }

public:
                     CSSRMt5HistoryProvider(void) : m_sync_wait_ms(0), m_ensure_calls(0) {}

   long              SyncWaitMs(void)  { return m_sync_wait_ms; }
   long              EnsureCalls(void) { return m_ensure_calls; }

   //+------------------------------------------------------------------+
   virtual bool      Discover(const string symbol, SSRDataRange &out) override
     {
      out.Init();

      if(!SymbolSelect(symbol, true))
        {
         Fail(SSR_ERR_NO_DATA,
              StringFormat("SymbolSelect(%s) failed err=%d", symbol, GetLastError()));
         return false;
        }

      //--- a failed sync is not fatal: the terminal may still hold enough
      //--- local history to replay. Report what exists either way.
      WaitForSeries(symbol, SSR_SYNC_TIMEOUT_MS);

      long first = 0, server_first = 0, bars = 0, lastbar = 0;
      SeriesInfoInteger(symbol, PERIOD_M1, SERIES_FIRSTDATE,        first);
      SeriesInfoInteger(symbol, PERIOD_M1, SERIES_SERVER_FIRSTDATE, server_first);
      SeriesInfoInteger(symbol, PERIOD_M1, SERIES_BARS_COUNT,       bars);
      SeriesInfoInteger(symbol, PERIOD_M1, SERIES_LASTBAR_DATE,     lastbar);

      if(bars <= 0 || first <= 0 || lastbar <= 0)
        {
         Fail(SSR_ERR_NO_DATA,
              StringFormat("no M1 history for %s (bars=%d first=%d)",
                           symbol, (int)bars, (int)first));
         return false;
        }

      out.available = true;
      out.first_msc = SSRToMsc((datetime)first);

      //--- The last instant COVERED, i.e. the close of the final bar -
      //--- using its open time instead silently shortens every window.
      //---
      //--- But SERIES_LASTBAR_DATE may be the bar STILL FORMING, whose
      //--- close has not happened yet. Reporting that as available data
      //--- puts the end of the timeline in the future. Compare against
      //--- the symbol's own last quote: if it falls inside that bar, the
      //--- bar is live, and the previous one is the last complete data.
      long lastbar_open  = SSRToMsc((datetime)lastbar);
      long lastbar_close = lastbar_open + SSR_MSC_PER_MIN - 1;
      long last_quote    = SymbolInfoInteger(symbol, SYMBOL_TIME_MSC);

      if(last_quote > 0 && last_quote <= lastbar_close)
         out.last_msc = lastbar_open - 1;      // the forming bar is not data yet
      else
         out.last_msc = lastbar_close;
      out.server_first_msc = (server_first > 0 ? SSRToMsc((datetime)server_first)
                                               : out.first_msc);
      out.bar_count        = bars;

      //--- probe for real ticks over the most recent day we hold
      MqlTick probe[];
      long to_msc   = out.last_msc;
      long from_msc = to_msc - 24 * 60 * 60 * 1000;
      int  got = CopyTicksRange(symbol, probe, COPY_TICKS_INFO,
                                (ulong)MathMax(from_msc, 0), (ulong)to_msc);
      out.has_ticks = (got > 0);

      Succeed();
      return true;
     }

   //+------------------------------------------------------------------+
   virtual bool      Ensure(const string symbol, const long from_msc, const long to_msc) override
     {
      m_ensure_calls++;
      if(from_msc > to_msc)
        {
         Fail(SSR_ERR_INVALID_ARG, "inverted range");
         return false;
        }

      datetime from_dt = SSRToTime(from_msc);
      datetime to_dt   = SSRToTime(to_msc);

      MqlRates tmp[];
      ArraySetAsSeries(tmp, false);

      ulong t0 = SSRMicros();
      while(SSRElapsedMs(t0) < SSR_SYNC_TIMEOUT_MS)
        {
         ResetLastError();
         int got = CopyRates(symbol, PERIOD_M1, from_dt, to_dt, tmp);
         if(got > 0)
           {
            Succeed();
            return true;
           }
         if(!SSRCanBlock())
            break;
         SSRPause(50);
        }

      Fail(SSR_ERR_LOAD_FAILED,
           StringFormat("could not prepare %s %s..%s err=%d",
                        symbol, SSRFormatMsc(from_msc), SSRFormatMsc(to_msc), GetLastError()));
      return false;
     }

   //+------------------------------------------------------------------+
   //| Ask the terminal to pull older history from the server.          |
   //| Returns the new earliest instant, or the old one when the server |
   //| has nothing deeper to give.                                      |
   //+------------------------------------------------------------------+
   virtual long      ExtendBackwards(const string symbol, const long bars) override
     {
      long first = 0, server_first = 0;
      SeriesInfoInteger(symbol, PERIOD_M1, SERIES_FIRSTDATE,        first);
      SeriesInfoInteger(symbol, PERIOD_M1, SERIES_SERVER_FIRSTDATE, server_first);

      if(first <= 0)
        {
         Fail(SSR_ERR_NO_DATA, "symbol has no history to extend");
         return SSR_INVALID_TIME;
        }
      if(server_first <= 0 || server_first >= first)
        {
         //--- not a failure: the broker simply has nothing older
         Succeed();
         return SSRToMsc((datetime)first);
        }

      datetime want_from = (datetime)(first - bars * 60);
      if(want_from < (datetime)server_first)
         want_from = (datetime)server_first;

      MqlRates tmp[];
      ArraySetAsSeries(tmp, false);

      ulong t0 = SSRMicros();
      while(SSRElapsedMs(t0) < SSR_SYNC_TIMEOUT_MS)
        {
         ResetLastError();
         CopyRates(symbol, PERIOD_M1, want_from, (datetime)first, tmp);

         long now_first = 0;
         SeriesInfoInteger(symbol, PERIOD_M1, SERIES_FIRSTDATE, now_first);
         if(now_first > 0 && now_first < first)
           {
            Succeed();
            return SSRToMsc((datetime)now_first);
           }
         if(!SSRCanBlock())
            break;
         SSRPause(100);
        }

      //--- the request timed out without growing the history. Report the
      //--- unchanged bound rather than an error: the caller can retry.
      Succeed();
      return SSRToMsc((datetime)first);
     }
  };

//+------------------------------------------------------------------+
//| M1 bars, served out of the bounded window.                       |
//+------------------------------------------------------------------+
class CSSRMt5BarProvider : public CSSRBarProvider
  {
private:
   CSSRBarWindow     m_window;

public:
                     CSSRMt5BarProvider(void) {}

   CSSRBarWindow    *Window(void) { return GetPointer(m_window); }
   void              SetWindowBars(const int n) { m_window.SetWindowBars(n); }
   void              Invalidate(void)           { m_window.Invalidate(); }

   virtual int       ReadBars(const string symbol, const long from_msc,
                              const long to_msc, MqlRates &out[]) override
     {
      long lo = from_msc, hi = to_msc;

      //--- guard layer 2. The controller already clamped, but a provider
      //--- that trusts its caller is one refactor from leaking the future.
      if(!GuardRange(lo, hi))
        {
         Succeed();
         return 0;
        }

      if(!m_window.Ensure(symbol, lo, hi))
        {
         //--- no data in range is not an error; a failed LOAD is
         if(m_window.LastError() == SSR_ERR_NO_DATA)
           {
            Succeed();
            return 0;
           }
         Fail(m_window.LastError(), m_window.LastErrorText());
         return -1;
        }

      int n = m_window.Read(lo, hi, out);
      if(n < 0)
        {
         Fail(SSR_ERR_INTERNAL, "window read failed");
         return -1;
        }
      Succeed();
      return n;
     }

   virtual bool      ReadBarAt(const string symbol, const long msc, MqlRates &out) override
     {
      long open = SSRBarOpenMsc(msc, PERIOD_M1);
      if(m_guard != NULL && !m_guard.Allows(open))
        {
         m_guard.Violation(open);
         Fail(SSR_ERR_FUTURE_ACCESS, "bar is beyond the horizon");
         return false;
        }
      if(!m_window.Ensure(symbol, open, open + SSR_MSC_PER_MIN - 1))
        {
         Fail(m_window.LastError(), m_window.LastErrorText());
         return false;
        }
      if(!m_window.ReadAt(open, out))
        {
         Fail(SSR_ERR_NO_DATA, "no bar at " + SSRFormatMsc(open));
         return false;
        }
      Succeed();
      return true;
     }

   virtual long      BarCount(const string symbol) override
     {
      long bars = 0;
      SeriesInfoInteger(symbol, PERIOD_M1, SERIES_BARS_COUNT, bars);
      return bars;
     }
  };

//+------------------------------------------------------------------+
//| Real broker ticks.                                               |
//+------------------------------------------------------------------+
class CSSRMt5TickProvider : public CSSRTickProvider
  {
private:
   CSSRDataValidator m_validator;
   long              m_pages;
   long              m_ticks_read;
   long              m_read_time_ms;
   uint              m_flags;

public:
                     CSSRMt5TickProvider(void)
     : m_pages(0), m_ticks_read(0), m_read_time_ms(0), m_flags(COPY_TICKS_INFO) {}

   //--- COPY_TICKS_INFO is bid/ask only and much lighter than ALL.
   //--- Symbols with real traded volume can be switched to ALL.
   void              SetFlags(const uint f) { m_flags = f; }
   long              Pages(void)            { return m_pages; }
   long              TicksRead(void)        { return m_ticks_read; }
   long              ReadTimeMs(void)       { return m_read_time_ms; }

   virtual bool      HasTicks(const string symbol, const long from_msc, const long to_msc) override
     {
      if(from_msc > to_msc)
         return false;
      MqlTick probe[];
      int got = CopyTicksRange(symbol, probe, m_flags,
                               (ulong)MathMax(from_msc, 0), (ulong)to_msc);
      return (got > 0);
     }

   //+------------------------------------------------------------------+
   //| Ticks in (from_msc, to_msc].                                     |
   //|                                                                  |
   //| CopyTicksRange is INCLUSIVE at both ends, while the contract is  |
   //| half-open at the bottom, so the request starts one millisecond   |
   //| later. Getting this wrong re-emits the boundary tick on every    |
   //| pump.                                                            |
   //|                                                                  |
   //| The call is also paged: a single request can be truncated, and a |
   //| truncated read looks exactly like a quiet market. The loop walks |
   //| forward from the last stamp received until the range is covered. |
   //+------------------------------------------------------------------+
   virtual int       ReadTicks(const string symbol, const long from_msc,
                               const long to_msc, MqlTick &out[]) override
     {
      long lo = from_msc, hi = to_msc;
      if(!GuardRange(lo, hi))
        {
         Succeed();
         return 0;
        }

      //--- half-open lower bound. Clamped at zero first: casting a
      //--- negative long to ulong wraps to a colossal timestamp and the
      //--- request silently returns nothing.
      long cursor = (lo < 0 ? 0 : lo + 1);
      int  total   = 0;
      int  retries = 0;
      ulong t0     = SSRMicros();

      for(int page = 0; page < SSR_TICK_PAGE_GUARD && cursor <= hi; page++)
        {
         MqlTick buf[];
         ResetLastError();
         int got = CopyTicksRange(symbol, buf, m_flags, (ulong)cursor, (ulong)hi);

         if(got < 0)
           {
            //--- async: the terminal may still be fetching. Retries are
            //--- counted separately so they cannot consume the page
            //--- budget that bounds forward progress.
            if(SSRCanBlock() && SSRElapsedMs(t0) < SSR_TICK_TIMEOUT_MS && retries < 200)
              {
               retries++;
               SSRPause(50);
               page--;
               continue;
              }
            m_read_time_ms += (long)SSRElapsedMs(t0);
            Fail(SSR_ERR_LOAD_FAILED,
                 StringFormat("CopyTicksRange(%s) err=%d", symbol, GetLastError()));
            return -1;
           }
         if(got == 0)
            break;

         int clean = m_validator.SanitizeTicks(buf, got);
         if(clean <= 0)
            break;

         int need = total + clean;
         if(ArraySize(out) < need && ArrayResize(out, need) < need)
           {
            Fail(SSR_ERR_INTERNAL, "tick buffer resize failed");
            return -1;
           }
         for(int i = 0; i < clean; i++)
            out[total + i] = buf[i];
         total += clean;
         m_pages++;

         long last = buf[clean - 1].time_msc;
         if(last >= hi)
            break;
         //--- a page that did not reach `hi` means truncation; resume
         //--- from the millisecond after the last stamp received
         if(last < cursor)
            break;                        // no forward progress; stop rather than spin
         cursor = last + 1;
        }

      m_read_time_ms += (long)SSRElapsedMs(t0);
      m_ticks_read   += total;
      Succeed();
      return total;
     }
  };

#endif // SSR_MT5_PROVIDERS_MQH
//+------------------------------------------------------------------+
