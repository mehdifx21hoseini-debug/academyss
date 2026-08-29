//+------------------------------------------------------------------+
//|                                      SSR_CustomSymbolManager.mqh |
//|                  SS Replay - Custom Symbol Lifecycle (L0/MT5)    |
//|                                                                  |
//|  Owns the MetaTrader side of a replay symbol: creating it,       |
//|  copying the origin's trading specification, writing and         |
//|  deleting history, and tearing it down in an order the terminal  |
//|  will actually accept.                                           |
//|                                                                  |
//|  TEARDOWN ORDER IS NOT OPTIONAL                                  |
//|  CustomSymbolDelete refuses while a chart shows the symbol or    |
//|  while it sits in Market Watch. Getting the order wrong leaves   |
//|  an orphan symbol and its history on disk after every session,   |
//|  which is how these tools end up with forty dead symbols in the  |
//|  Market Watch tree.                                              |
//|                                                                  |
//|  SPECIFICATION FIDELITY                                          |
//|  The origin symbol is passed to CustomSymbolCreate so MetaTrader |
//|  copies digits, tick size, tick value, contract size, volume     |
//|  steps and margin itself. Setting those by hand is how lot and   |
//|  P/L maths silently diverges from the real instrument.           |
//+------------------------------------------------------------------+
#ifndef SSR_CUSTOM_SYMBOL_MANAGER_MQH
#define SSR_CUSTOM_SYMBOL_MANAGER_MQH

#include "../Common/SSR_Types.mqh"
#include "../Common/SSR_Time.mqh"
#include "../Common/SSR_Platform.mqh"
#include "../Common/SSR_SymbolNaming.mqh"

//--- CustomRatesUpdate in slices: one enormous call blocks the terminal
#define SSR_RATES_CHUNK       10000
//--- CustomTicksAdd in slices, for the same reason
#define SSR_TICKS_CHUNK       4096
//--- the far edge used when deleting "everything from here on"
#define SSR_FAR_FUTURE        D'2038.01.01 00:00'

//+------------------------------------------------------------------+
struct SSRSymbolStats
  {
   long              bars_written;
   long              ticks_added;
   long              ticks_rejected;
   long              rates_calls;
   long              ticks_calls;
   long              rates_deleted;
   long              ticks_deleted;
   long              write_time_ms;

   void              Init(void)
     {
      bars_written = 0; ticks_added = 0; ticks_rejected = 0;
      rates_calls = 0;  ticks_calls = 0;
      rates_deleted = 0; ticks_deleted = 0; write_time_ms = 0;
     }

   string            ToString(void)
     {
      return StringFormat("bars=%d ticks=%d rejected=%d calls=%d/%d "
                          "deleted=%d/%d time=%dms",
                          (int)bars_written, (int)ticks_added, (int)ticks_rejected,
                          (int)rates_calls, (int)ticks_calls,
                          (int)rates_deleted, (int)ticks_deleted, (int)write_time_ms);
     }
  };

//+------------------------------------------------------------------+
class CSSRCustomSymbolManager
  {
private:
   string            m_origin;
   string            m_symbol;
   int               m_slot;
   bool              m_created;
   bool              m_selected;
   int               m_digits;
   double            m_point;
   SSRSymbolStats    m_stats;

   ENUM_SSR_ERR      m_last_error;
   string            m_last_error_text;

   void              Fail(const ENUM_SSR_ERR e, const string t)
     { m_last_error = e; m_last_error_text = t; }
   void              Succeed(void)
     { m_last_error = SSR_OK; m_last_error_text = ""; }

   //+------------------------------------------------------------------+
   //| Quote and trade sessions across all seven days.                  |
   //|                                                                  |
   //| Without these the terminal may reject ticks stamped outside the  |
   //| symbol's session - silently, so the symptom is a missing candle  |
   //| rather than an error. Spike B3 measures whether that is actually |
   //| happening on the target build; setting 24/7 costs nothing either |
   //| way, so it is set unconditionally.                               |
   //+------------------------------------------------------------------+
   void              Apply247Sessions(void)
     {
      for(int d = 0; d <= 6; d++)
        {
         ENUM_DAY_OF_WEEK day = (ENUM_DAY_OF_WEEK)d;
         CustomSymbolSetSessionQuote(m_symbol, day, 0, (datetime)0, (datetime)86399);
         CustomSymbolSetSessionTrade(m_symbol, day, 0, (datetime)0, (datetime)86399);
        }
     }

public:
                     CSSRCustomSymbolManager(void)
     : m_origin(""), m_symbol(""), m_slot(1), m_created(false), m_selected(false),
       m_digits(5), m_point(0.00001), m_last_error(SSR_OK), m_last_error_text("")
     { m_stats.Init(); }

                    ~CSSRCustomSymbolManager(void) {}

   //--- identity ----------------------------------------------------
   string            Symbol(void)   { return m_symbol; }
   string            Origin(void)   { return m_origin; }
   int               Slot(void)     { return m_slot; }
   int               Digits(void)   { return m_digits; }
   double            Point(void)    { return m_point; }
   bool              IsCreated(void){ return m_created; }
   ENUM_SSR_ERR      LastError(void)     { return m_last_error; }
   string            LastErrorText(void) { return m_last_error_text; }
   void              StatsInto(SSRSymbolStats &out) { out = m_stats; }

   //+------------------------------------------------------------------+
   //| Create the replay symbol as a clone of `origin`.                 |
   //| An existing symbol of the same name is torn down first, so a     |
   //| crashed previous session cannot poison this one.                 |
   //+------------------------------------------------------------------+
   bool              Create(const string origin, const int slot = 1)
     {
      m_origin = origin;
      m_slot   = slot;
      m_symbol = SSRReplaySymbolName(origin, slot);
      m_stats.Init();

      if(!SSRIsNameUsable(m_symbol))
        {
         Fail(SSR_ERR_INVALID_ARG, "replay symbol name is not usable: " + m_symbol);
         return false;
        }

      //--- leftovers from a previous run must go before we recreate
      Destroy();

      if(!SymbolSelect(origin, true))
        {
         Fail(SSR_ERR_NO_DATA,
              StringFormat("origin symbol %s is not available (err=%d)", origin, GetLastError()));
         return false;
        }

      ResetLastError();
      if(!CustomSymbolCreate(m_symbol, SSRReplaySymbolPath(), origin))
        {
         int create_err = GetLastError();

         //--- Creation can fail because the symbol is STILL THERE: a
         //--- previous session crashed, or a chart refused to close in
         //--- time. Refusing to start would leave the user stuck until
         //--- they cleaned up by hand. If the leftover is demonstrably
         //--- ours, adopt it and wipe its history instead.
         ResetLastError();
         bool exists = (SymbolInfoInteger(m_symbol, SYMBOL_DIGITS) > 0 &&
                        GetLastError() == 0);

         if(!exists || !SSRIsReplaySymbol(m_symbol))
           {
            Fail(SSR_ERR_INTERNAL,
                 StringFormat("CustomSymbolCreate(%s, origin=%s) failed err=%d",
                              m_symbol, origin, create_err));
            return false;
           }
        }
      m_created = true;

      //--- the three overrides the engine depends on
      CustomSymbolSetInteger(m_symbol, SYMBOL_SPREAD_FLOAT, true);
      CustomSymbolSetInteger(m_symbol, SYMBOL_TRADE_MODE, SYMBOL_TRADE_MODE_DISABLED);
      Apply247Sessions();

      //--- CustomTicksAdd only broadcasts to charts for a symbol that is
      //--- in Market Watch, so selection is part of creation, not a
      //--- separate step a caller could forget
      if(!SymbolSelect(m_symbol, true))
        {
         Fail(SSR_ERR_INTERNAL,
              StringFormat("SymbolSelect(%s) failed err=%d", m_symbol, GetLastError()));
         return false;
        }
      m_selected = true;

      m_digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
      m_point  = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      if(m_point <= 0.0)
         m_point = MathPow(10, -m_digits);

      Succeed();
      return true;
     }

   //+------------------------------------------------------------------+
   //| Take over an EXISTING replay symbol without destroying it.       |
   //|                                                                  |
   //| Create() always tears down first, which is right when starting   |
   //| fresh and exactly wrong when the point is to keep the bars that  |
   //| are already there. The seed cache needs this second door.        |
   //+------------------------------------------------------------------+
   bool              Adopt(const string replay_symbol, const string origin)
     {
      ResetLastError();
      long digits = SymbolInfoInteger(replay_symbol, SYMBOL_DIGITS);
      if(digits <= 0 || GetLastError() != 0)
        {
         Fail(SSR_ERR_NO_DATA, "no symbol to adopt: " + replay_symbol);
         return false;
        }
      if(!SSRIsReplaySymbol(replay_symbol))
        {
         Fail(SSR_ERR_INVALID_ARG, "refusing to adopt a symbol that is not ours");
         return false;
        }

      m_origin  = origin;
      m_symbol  = replay_symbol;
      m_created = true;
      m_stats.Init();

      //--- re-apply the overrides: a symbol from an older run may have
      //--- been created before one of them existed
      CustomSymbolSetInteger(m_symbol, SYMBOL_SPREAD_FLOAT, true);
      CustomSymbolSetInteger(m_symbol, SYMBOL_TRADE_MODE, SYMBOL_TRADE_MODE_DISABLED);
      Apply247Sessions();

      if(!SymbolSelect(m_symbol, true))
        {
         Fail(SSR_ERR_INTERNAL, "SymbolSelect failed on the adopted symbol");
         return false;
        }
      m_selected = true;

      m_digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
      m_point  = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      if(m_point <= 0.0)
         m_point = MathPow(10, -m_digits);

      Succeed();
      return true;
     }

   //+------------------------------------------------------------------+
   //| Close every chart showing the replay symbol.                     |
   //|                                                                  |
   //| Chart INTEGRATION is Phase 4; this is not that. Deletion simply  |
   //| fails while a chart is open, so teardown has to do it.           |
   //+------------------------------------------------------------------+
   int               CloseCharts(void)
     {
      if(m_symbol == "")
         return 0;
      int closed = 0;
      long id = ChartFirst();
      while(id >= 0)
        {
         long next = ChartNext(id);
         if(ChartSymbol(id) == m_symbol)
           {
            ChartClose(id);
            closed++;
           }
         id = next;
        }
      return closed;
     }

   int               OpenChartCount(void)
     {
      if(m_symbol == "")
         return 0;
      int n = 0;
      long id = ChartFirst();
      while(id >= 0)
        {
         if(ChartSymbol(id) == m_symbol)
            n++;
         id = ChartNext(id);
        }
      return n;
     }

   //+------------------------------------------------------------------+
   //| Tear down in the only order MetaTrader accepts:                  |
   //|   charts -> Market Watch -> symbol                               |
   //| Safe to call when nothing exists.                                |
   //+------------------------------------------------------------------+
   bool              Destroy(void)
     {
      if(m_symbol == "")
         return true;

      CloseCharts();
      //--- the terminal needs a beat to release a just-closed chart
      SSRPause(50);

      SymbolSelect(m_symbol, false);
      m_selected = false;

      ResetLastError();
      bool ok = CustomSymbolDelete(m_symbol);
      m_created = false;

      //--- a symbol that was never there is not a failure
      Succeed();
      return ok;
     }

   //+------------------------------------------------------------------+
   //| Write M1 history in slices.                                      |
   //| Used for warmup seeding and for bulk fast-forward, never for     |
   //| the replay stream itself - that goes through ticks.              |
   //+------------------------------------------------------------------+
   bool              WriteBars(const MqlRates &bars[], const int count)
     {
      if(count <= 0)
         return true;
      if(!m_created)
        {
         Fail(SSR_ERR_INVALID_STATE, "symbol not created");
         return false;
        }

      ulong t0 = SSRMicros();
      int written = 0;

      for(int off = 0; off < count; off += SSR_RATES_CHUNK)
        {
         int n = MathMin(SSR_RATES_CHUNK, count - off);
         MqlRates slice[];
         if(ArrayResize(slice, n) < n)
           {
            Fail(SSR_ERR_INTERNAL, "slice allocation failed");
            return false;
           }
         for(int i = 0; i < n; i++)
            slice[i] = bars[off + i];

         ResetLastError();
         int w = CustomRatesUpdate(m_symbol, slice);
         m_stats.rates_calls++;
         if(w < 0)
           {
            Fail(SSR_ERR_SINK_FAILED,
                 StringFormat("CustomRatesUpdate failed at offset %d err=%d",
                              off, GetLastError()));
            m_stats.write_time_ms += (long)SSRElapsedMs(t0);
            return false;
           }
         written += w;
        }

      m_stats.bars_written  += written;
      m_stats.write_time_ms += (long)SSRElapsedMs(t0);
      Succeed();
      return true;
     }

   //+------------------------------------------------------------------+
   //| Inject ticks in slices.                                          |
   //|                                                                  |
   //| The return value matters: CustomTicksAdd can accept fewer ticks  |
   //| than it was given, and a shortfall means data quietly vanished.  |
   //| It is counted rather than ignored so Phase 7 has a real number   |
   //| instead of a suspicion.                                          |
   //+------------------------------------------------------------------+
   bool              AddTicks(const MqlTick &ticks[], const int count)
     {
      if(count <= 0)
         return true;
      if(!m_created)
        {
         Fail(SSR_ERR_INVALID_STATE, "symbol not created");
         return false;
        }
      if(!m_selected)
        {
         //--- without Market Watch selection the ticks land in history
         //--- but never reach a chart, so the candle never forms live
         Fail(SSR_ERR_INVALID_STATE, "symbol is not in Market Watch");
         return false;
        }

      ulong t0 = SSRMicros();

      for(int off = 0; off < count; off += SSR_TICKS_CHUNK)
        {
         int n = MathMin(SSR_TICKS_CHUNK, count - off);
         MqlTick slice[];
         if(ArrayResize(slice, n) < n)
           {
            Fail(SSR_ERR_INTERNAL, "slice allocation failed");
            return false;
           }
         for(int i = 0; i < n; i++)
            slice[i] = ticks[off + i];

         ResetLastError();
         int added = CustomTicksAdd(m_symbol, slice);
         m_stats.ticks_calls++;

         if(added < 0)
           {
            Fail(SSR_ERR_SINK_FAILED,
                 StringFormat("CustomTicksAdd failed at offset %d err=%d",
                              off, GetLastError()));
            m_stats.write_time_ms += (long)SSRElapsedMs(t0);
            return false;
           }
         m_stats.ticks_added += added;
         if(added < n)
            m_stats.ticks_rejected += (n - added);
        }

      m_stats.write_time_ms += (long)SSRElapsedMs(t0);
      Succeed();
      return true;
     }

   //+------------------------------------------------------------------+
   //| Remove everything at or after `from_msc`.                        |
   //|                                                                  |
   //| BOTH stores must be cut, and both at the SAME bar boundary.      |
   //| MetaTrader keeps ticks and M1 bars separately: deleting ticks    |
   //| does not un-build the bar they already contributed to. Cutting   |
   //| ticks at an arbitrary instant would leave a bar whose high and   |
   //| low still carry the future that was just deleted - a leak that   |
   //| looks like nothing is wrong.                                     |
   //|                                                                  |
   //| Returns the instant actually truncated from, which is the open   |
   //| of the bar containing `from_msc`, or -1 on failure.              |
   //+------------------------------------------------------------------+
   long              Truncate(const long from_msc)
     {
      if(!m_created)
        {
         Fail(SSR_ERR_INVALID_STATE, "symbol not created");
         return -1;
        }

      long bar_open = SSRBarOpenMsc(from_msc, PERIOD_M1);

      ResetLastError();
      int nr = CustomRatesDelete(m_symbol, SSRToTime(bar_open), SSR_FAR_FUTURE);
      if(nr < 0)
        {
         Fail(SSR_ERR_SINK_FAILED,
              StringFormat("CustomRatesDelete failed err=%d", GetLastError()));
         return -1;
        }
      m_stats.rates_deleted += nr;

      ResetLastError();
      int nt = CustomTicksDelete(m_symbol, bar_open, LONG_MAX);
      if(nt < 0)
        {
         Fail(SSR_ERR_SINK_FAILED,
              StringFormat("CustomTicksDelete failed err=%d", GetLastError()));
         return -1;
        }
      m_stats.ticks_deleted += nt;

      Succeed();
      return bar_open;
     }

   //--- clear every bar and tick, keeping the symbol itself
   bool              ClearAll(void)
     {
      if(!m_created)
         return true;
      ResetLastError();
      CustomRatesDelete(m_symbol, (datetime)0, SSR_FAR_FUTURE);
      CustomTicksDelete(m_symbol, 0, LONG_MAX);
      Succeed();
      return true;
     }

   //--- the replay clock as MetaTrader itself sees it. Phase 0 spike C4
   //--- checks that this equals the last injected tick's stamp.
   long              SymbolTimeMsc(void)
     {
      if(!m_created)
         return SSR_INVALID_TIME;
      return SymbolInfoInteger(m_symbol, SYMBOL_TIME_MSC);
     }

   long              BarCount(const ENUM_TIMEFRAMES tf)
     {
      if(!m_created)
         return 0;
      long n = 0;
      SeriesInfoInteger(m_symbol, tf, SERIES_BARS_COUNT, n);
      return n;
     }

   string            ToString(void)
     {
      return StringFormat("symbol[%s <- %s created=%s charts=%d %s]",
                          m_symbol, m_origin, (m_created ? "yes" : "no"),
                          OpenChartCount(), m_stats.ToString());
     }
  };

#endif // SSR_CUSTOM_SYMBOL_MANAGER_MQH
//+------------------------------------------------------------------+
