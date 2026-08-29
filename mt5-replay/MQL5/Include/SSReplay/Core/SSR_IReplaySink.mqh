//+------------------------------------------------------------------+
//|                                              SSR_IReplaySink.mqh |
//|                              SS Replay - Output Sink Contract(L2)|
//|                                                                  |
//|  The seam between the engine and MetaTrader.                     |
//|                                                                  |
//|  The core produces a stream of ticks and lifecycle events, and   |
//|  hands them to a sink. It has no idea whether the sink writes to |
//|  a custom symbol (Phase 3), to a test recorder (Phase 1), or to  |
//|  nothing at all. That is exactly what keeps the core testable    |
//|  without MetaTrader and free of any Custom*/Chart* dependency.   |
//+------------------------------------------------------------------+
#ifndef SSR_IREPLAYSINK_MQH
#define SSR_IREPLAYSINK_MQH

#include "../Common/SSR_Types.mqh"

//+------------------------------------------------------------------+
class CSSRReplaySink
  {
protected:
   ENUM_SSR_ERR      m_last_error;
   string            m_last_error_text;

   void              Fail(const ENUM_SSR_ERR e, const string t)
     {
      m_last_error = e;
      m_last_error_text = t;
     }

public:
                     CSSRReplaySink(void) : m_last_error(SSR_OK), m_last_error_text("") {}
   virtual          ~CSSRReplaySink(void) {}

   virtual string    Name(void) = 0;

   //--- called once before any data flows; the sink prepares itself
   virtual bool      Prepare(const string symbol, const int digits, const double point) = 0;

   //--- warmup history, delivered in bulk before replay begins
   virtual bool      SeedBars(const MqlRates &bars[], const int count) = 0;

   //--- the replay stream. `count` may be 0, which is not an error.
   virtual bool      EmitTicks(const MqlTick &ticks[], const int count) = 0;

   //+------------------------------------------------------------------+
   //| Everything at or after `from_msc` must cease to exist. This is   |
   //| what makes rewind and reset structural rather than cosmetic.     |
   //|                                                                  |
   //| Returns the instant actually truncated from, or -1 on failure.   |
   //|                                                                  |
   //| A sink may only be able to cut at a coarser boundary than asked. |
   //| The MT5 sink is exactly that case: bars and ticks live in        |
   //| separate stores and deleting a tick does not un-build the bar it |
   //| already contributed to, so the cut has to land on a bar open or  |
   //| the surviving bar keeps a high and low from the deleted future.  |
   //| The caller must trust the RETURNED instant, not the requested    |
   //| one, when repositioning.                                         |
   //+------------------------------------------------------------------+
   virtual long      TruncateFrom(const long from_msc) = 0;

   //+------------------------------------------------------------------+
   //| The warmup range this session is about to need, announced before |
   //| Prepare. A sink that stores history may already hold it and skip |
   //| the write; one that does not simply ignores the call. Core never |
   //| learns which kind it is talking to.                              |
   //+------------------------------------------------------------------+
   virtual void      OnWarmupPlanned(const long from_msc, const long to_msc) {}

   //+------------------------------------------------------------------+
   //| Does this sink actually need the warmup handed to it?            |
   //|                                                                  |
   //| Reading a hundred thousand bars out of the data layer is most of |
   //| the cost of starting a session. A sink that already holds them   |
   //| says so here and the read never happens. Core is not told why -  |
   //| only whether.                                                    |
   //+------------------------------------------------------------------+
   virtual bool      NeedsWarmup(const long from_msc, const long to_msc) { return true; }

   //--- lifecycle notifications; a sink may ignore any of them
   virtual void      OnStateChanged(const ENUM_SSR_STATE from, const ENUM_SSR_STATE to) {}
   virtual void      OnSeek(const long msc) {}
   virtual void      OnReset(void) {}

   //--- called when replay is torn down; release resources here
   virtual void      Release(void) {}

   ENUM_SSR_ERR      LastError(void)     { return m_last_error; }
   string            LastErrorText(void) { return m_last_error_text; }
  };

#endif // SSR_IREPLAYSINK_MQH
//+------------------------------------------------------------------+
