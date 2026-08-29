//+------------------------------------------------------------------+
//|                                            SSR_RecordingSink.mqh |
//|                          SS Replay - Recording Test Sink (L2)    |
//|                                                                  |
//|  Records everything the engine emits, in order, so a test can    |
//|  assert on the actual stream rather than on side effects.        |
//|                                                                  |
//|  It also enforces two invariants the real MT5 sink depends on,   |
//|  and reports a violation instead of silently tolerating it:      |
//|    - emitted ticks are strictly non-decreasing in time           |
//|    - no tick is ever emitted twice                               |
//|  If Phase 3's custom-symbol sink is fed a stream that breaks     |
//|  either rule, MetaTrader builds a corrupt bar - so the rules are |
//|  checked here, where the failure is cheap to diagnose.           |
//+------------------------------------------------------------------+
#ifndef SSR_RECORDING_SINK_MQH
#define SSR_RECORDING_SINK_MQH

#include "../SSR_IReplaySink.mqh"
#include "../../Common/SSR_Time.mqh"

//+------------------------------------------------------------------+
class CSSRRecordingSink : public CSSRReplaySink
  {
private:
   MqlTick           m_ticks[];
   int               m_tick_count;
   int               m_seed_bars;
   int               m_truncations;
   int               m_seeks;
   int               m_resets;
   int               m_state_changes;
   long              m_last_msc;
   int               m_order_violations;
   int               m_duplicate_stamps;
   long              m_last_truncate_msc;
   bool              m_prepared;
   string            m_symbol;

public:
                     CSSRRecordingSink(void) { Clear(); }

   virtual string    Name(void) override { return "recording"; }

   void              Clear(void)
     {
      ArrayResize(m_ticks, 0);
      m_tick_count        = 0;
      m_seed_bars         = 0;
      m_truncations       = 0;
      m_seeks             = 0;
      m_resets            = 0;
      m_state_changes     = 0;
      m_last_msc          = SSR_INVALID_TIME;
      m_order_violations  = 0;
      m_duplicate_stamps  = 0;
      m_last_truncate_msc = SSR_INVALID_TIME;
      m_prepared          = false;
      m_symbol            = "";
     }

   virtual bool      Prepare(const string symbol, const int digits, const double point) override
     {
      m_symbol   = symbol;
      m_prepared = true;
      return true;
     }

   virtual bool      SeedBars(const MqlRates &bars[], const int count) override
     {
      m_seed_bars += count;
      return true;
     }

   virtual bool      EmitTicks(const MqlTick &ticks[], const int count) override
     {
      if(count <= 0)
         return true;

      int need = m_tick_count + count;
      if(ArraySize(m_ticks) < need && ArrayResize(m_ticks, need) < need)
        {
         Fail(SSR_ERR_INTERNAL, "recording buffer resize failed");
         return false;
        }

      for(int i = 0; i < count; i++)
        {
         //--- going BACKWARDS is always wrong. An EQUAL stamp is not:
         //--- real broker ticks share a millisecond all the time, so it
         //--- is counted separately and judged per fidelity by the test.
         if(m_last_msc != SSR_INVALID_TIME)
           {
            if(ticks[i].time_msc < m_last_msc)       m_order_violations++;
            else if(ticks[i].time_msc == m_last_msc) m_duplicate_stamps++;
           }
         m_last_msc = ticks[i].time_msc;
         m_ticks[m_tick_count++] = ticks[i];
        }
      return true;
     }

   virtual long      TruncateFrom(const long from_msc) override
     {
      m_truncations++;
      m_last_truncate_msc = from_msc;

      int keep = 0;
      for(int i = 0; i < m_tick_count; i++)
         if(m_ticks[i].time_msc < from_msc)
           {
            if(keep != i)
               m_ticks[keep] = m_ticks[i];
            keep++;
           }
      m_tick_count = keep;
      m_last_msc   = (keep > 0 ? m_ticks[keep - 1].time_msc : SSR_INVALID_TIME);
      //--- an in-memory recorder can cut at the exact instant asked for
      return from_msc;
     }

   virtual void      OnStateChanged(const ENUM_SSR_STATE from, const ENUM_SSR_STATE to) override
     { m_state_changes++; }
   virtual void      OnSeek(const long msc) override { m_seeks++; }
   virtual void      OnReset(void) override          { m_resets++; }
   virtual void      Release(void) override          { m_prepared = false; }

   //--- assertions ---------------------------------------------------
   int               TickCount(void)        { return m_tick_count; }
   int               SeedBarCount(void)     { return m_seed_bars; }
   int               Truncations(void)      { return m_truncations; }
   int               Seeks(void)            { return m_seeks; }
   int               Resets(void)           { return m_resets; }
   int               StateChanges(void)     { return m_state_changes; }
   int               OrderViolations(void)  { return m_order_violations; }
   int               DuplicateStamps(void)  { return m_duplicate_stamps; }
   bool              IsPrepared(void)       { return m_prepared; }
   long              LastTruncateMsc(void)  { return m_last_truncate_msc; }

   long              FirstTickMsc(void)
     { return (m_tick_count > 0 ? m_ticks[0].time_msc : SSR_INVALID_TIME); }
   long              LastTickMsc(void)
     { return (m_tick_count > 0 ? m_ticks[m_tick_count - 1].time_msc : SSR_INVALID_TIME); }

   bool              TickAt(const int i, MqlTick &out)
     {
      if(i < 0 || i >= m_tick_count)
         return false;
      out = m_ticks[i];
      return true;
     }

   //--- how many ticks carry a stamp strictly after `msc`
   int               CountAfter(const long msc)
     {
      int n = 0;
      for(int i = 0; i < m_tick_count; i++)
         if(m_ticks[i].time_msc > msc)
            n++;
      return n;
     }

   //--- a stable fingerprint of the whole stream, for determinism tests
   ulong             Fingerprint(void)
     {
      ulong h = 1469598103934665603;
      for(int i = 0; i < m_tick_count; i++)
        {
         h ^= (ulong)m_ticks[i].time_msc;              h *= 1099511628211;
         h ^= (ulong)(long)(m_ticks[i].bid * 100000.0); h *= 1099511628211;
        }
      return h;
     }
  };

#endif // SSR_RECORDING_SINK_MQH
//+------------------------------------------------------------------+
