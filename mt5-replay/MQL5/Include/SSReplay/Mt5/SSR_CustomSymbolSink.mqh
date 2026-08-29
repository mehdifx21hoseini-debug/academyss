//+------------------------------------------------------------------+
//|                                         SSR_CustomSymbolSink.mqh |
//|                    SS Replay - Custom Symbol Replay Sink (MT5)   |
//|                                                                  |
//|  THE ADAPTER. Everything above believes it is talking to the      |
//|  abstract CSSRReplaySink from Phase 1; everything below is        |
//|  MetaTrader's Custom* API.                                        |
//|                                                                  |
//|  Two rules the whole product rests on are enforced here:          |
//|                                                                  |
//|  1. WARMUP GOES IN AS BARS, REPLAY GOES IN AS TICKS.              |
//|     Seeding a hundred thousand warmup bars through tick injection |
//|     would take minutes and broadcast a hundred thousand chart     |
//|     updates nobody watches. Conversely, advancing replay by       |
//|     writing bars would skip the live candle formation that is the |
//|     entire point. Different jobs, different API.                  |
//|                                                                  |
//|  2. TRUNCATION IS DELETION, NEVER HIDING.                         |
//|     Rewind removes the bars and ticks from MetaTrader's own       |
//|     storage. A hidden-but-present future is the failure mode this |
//|     product exists to avoid.                                      |
//+------------------------------------------------------------------+
#ifndef SSR_CUSTOM_SYMBOL_SINK_MQH
#define SSR_CUSTOM_SYMBOL_SINK_MQH

#include "../Common/SSR_Types.mqh"
#include "../Common/SSR_Time.mqh"
#include "../Common/SSR_Platform.mqh"
#include "../Core/SSR_IReplaySink.mqh"
#include "SSR_CustomSymbolManager.mqh"

//+------------------------------------------------------------------+
class CSSRCustomSymbolSink : public CSSRReplaySink
  {
private:
   CSSRCustomSymbolManager m_mgr;
   int                     m_slot;
   bool                    m_prepared;
   bool                    m_own_symbol;   // did we create it, or adopt one?

   //--- instrumentation for Phase 7
   long                    m_emit_calls;
   long                    m_emit_ticks;
   long                    m_seed_bars;
   long                    m_truncates;
   long                    m_emit_time_ms;
   long                    m_last_emit_msc;

public:
                     CSSRCustomSymbolSink(void)
     : m_slot(1), m_prepared(false), m_own_symbol(true),
       m_emit_calls(0), m_emit_ticks(0), m_seed_bars(0), m_truncates(0),
       m_emit_time_ms(0), m_last_emit_msc(SSR_INVALID_TIME) {}

                    ~CSSRCustomSymbolSink(void)
     {
      //--- a session that ends without an explicit Release must not
      //--- leave an orphan symbol behind in the Market Watch tree
      if(m_own_symbol && m_mgr.IsCreated())
         m_mgr.Destroy();
     }

   virtual string    Name(void) override { return "mt5-custom-symbol"; }

   void              SetSlot(const int slot) { m_slot = slot; }
   int               Slot(void)              { return m_slot; }

   //--- the replay symbol, which is NOT the symbol the engine was given
   string            ReplaySymbol(void) { return m_mgr.Symbol(); }
   CSSRCustomSymbolManager *Manager(void) { return GetPointer(m_mgr); }

   //+------------------------------------------------------------------+
   //| The controller hands us the ORIGIN symbol. We create a distinct  |
   //| replay symbol cloned from it, so the real instrument is never    |
   //| written to and the user's live chart is never touched.           |
   //+------------------------------------------------------------------+
   virtual bool      Prepare(const string symbol, const int digits, const double point) override
     {
      m_prepared = false;

      if(!m_mgr.Create(symbol, m_slot))
        {
         Fail(m_mgr.LastError(), m_mgr.LastErrorText());
         return false;
        }

      //--- start from an empty history: a previous session's data would
      //--- otherwise appear as the future of this one
      m_mgr.ClearAll();

      m_emit_calls    = 0;
      m_emit_ticks    = 0;
      m_seed_bars     = 0;
      m_truncates     = 0;
      m_emit_time_ms  = 0;
      m_last_emit_msc = SSR_INVALID_TIME;
      m_prepared      = true;
      return true;
     }

   //+------------------------------------------------------------------+
   //| Warmup history, in bulk. Bars, not ticks - see the header note.  |
   //+------------------------------------------------------------------+
   virtual bool      SeedBars(const MqlRates &bars[], const int count) override
     {
      if(!m_prepared)
        {
         Fail(SSR_ERR_INVALID_STATE, "sink not prepared");
         return false;
        }
      if(count <= 0)
         return true;

      if(!m_mgr.WriteBars(bars, count))
        {
         Fail(m_mgr.LastError(), m_mgr.LastErrorText());
         return false;
        }
      m_seed_bars += count;
      return true;
     }

   //+------------------------------------------------------------------+
   //| The replay stream. This is what makes the candle form live.      |
   //+------------------------------------------------------------------+
   virtual bool      EmitTicks(const MqlTick &ticks[], const int count) override
     {
      if(!m_prepared)
        {
         Fail(SSR_ERR_INVALID_STATE, "sink not prepared");
         return false;
        }
      if(count <= 0)
         return true;

      //--- MetaTrader will accept a tick stamped before one it already
      //--- holds and quietly corrupt the bar being built. The engine is
      //--- supposed to guarantee monotonicity; refusing here rather than
      //--- trusting it keeps a future regression from becoming a wrong
      //--- candle that nobody notices until Phase 16.
      if(m_last_emit_msc != SSR_INVALID_TIME && ticks[0].time_msc < m_last_emit_msc)
        {
         Fail(SSR_ERR_INTERNAL,
              StringFormat("out-of-order emit: %s before %s",
                           SSRFormatMscMs(ticks[0].time_msc),
                           SSRFormatMscMs(m_last_emit_msc)));
         return false;
        }

      ulong t0 = SSRMicros();
      if(!m_mgr.AddTicks(ticks, count))
        {
         Fail(m_mgr.LastError(), m_mgr.LastErrorText());
         return false;
        }
      m_emit_time_ms  += (long)SSRElapsedMs(t0);
      m_emit_calls++;
      m_emit_ticks    += count;
      m_last_emit_msc  = ticks[count - 1].time_msc;
      return true;
     }

   //+------------------------------------------------------------------+
   //| Delete, do not hide. Returns where the cut actually landed.      |
   //+------------------------------------------------------------------+
   virtual long      TruncateFrom(const long from_msc) override
     {
      if(!m_prepared)
        {
         Fail(SSR_ERR_INVALID_STATE, "sink not prepared");
         return -1;
        }

      long actual = m_mgr.Truncate(from_msc);
      if(actual < 0)
        {
         Fail(m_mgr.LastError(), m_mgr.LastErrorText());
         return -1;
        }
      m_truncates++;

      //--- the emit watermark must fall back with the data, or the very
      //--- next emit would be rejected as out of order
      m_last_emit_msc = (actual > 0 ? actual - 1 : SSR_INVALID_TIME);
      return actual;
     }

   virtual void      OnReset(void) override
     {
      m_last_emit_msc = SSR_INVALID_TIME;
     }

   //+------------------------------------------------------------------+
   //| Release the symbol. Called on teardown; safe to call twice.      |
   //+------------------------------------------------------------------+
   virtual void      Release(void) override
     {
      if(m_own_symbol && m_mgr.IsCreated())
         m_mgr.Destroy();
      m_prepared      = false;
      m_last_emit_msc = SSR_INVALID_TIME;
     }

   //+------------------------------------------------------------------+
   //| Keep the replay symbol alive after Release.                      |
   //|                                                                  |
   //| Phase 12 (Save / Resume Session) needs the symbol and its        |
   //| history to survive an engine teardown so a session can be        |
   //| reopened without reseeding from scratch.                         |
   //+------------------------------------------------------------------+
   void              SetOwnsSymbol(const bool own) { m_own_symbol = own; }
   bool              OwnsSymbol(void)              { return m_own_symbol; }

   //--- diagnostics --------------------------------------------------
   long              EmitCalls(void)   { return m_emit_calls; }
   long              EmitTicks(void)   { return m_emit_ticks; }
   long              SeededBars(void)  { return m_seed_bars; }
   long              Truncations(void) { return m_truncates; }
   long              EmitTimeMs(void)  { return m_emit_time_ms; }
   long              LastEmitMsc(void) { return m_last_emit_msc; }
   bool              IsPrepared(void)  { return m_prepared; }

   double            TicksPerSecond(void)
     {
      return (m_emit_time_ms > 0 ? (double)m_emit_ticks / ((double)m_emit_time_ms / 1000.0) : 0.0);
     }

   //--- what MetaTrader itself believes the time is on the replay
   //--- symbol. Phase 0 spike C4 asserts this equals the last tick.
   long              SymbolClockMsc(void) { return m_mgr.SymbolTimeMsc(); }

   string            ToString(void)
     {
      return StringFormat("sink[%s emits=%d ticks=%d seeded=%d cuts=%d %.0f t/s]",
                          m_mgr.Symbol(), (int)m_emit_calls, (int)m_emit_ticks,
                          (int)m_seed_bars, (int)m_truncates, TicksPerSecond());
     }
  };

#endif // SSR_CUSTOM_SYMBOL_SINK_MQH
//+------------------------------------------------------------------+
