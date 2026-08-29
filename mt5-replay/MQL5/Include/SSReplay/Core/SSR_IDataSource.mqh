//+------------------------------------------------------------------+
//|                                               SSR_IDataSource.mqh |
//|                          SS Replay - Data Source Contracts (L1)  |
//|                                                                  |
//|  The seam between the engine and wherever the bytes come from.   |
//|  Phase 2 implements these against MT5 broker history; Phase 6    |
//|  adds CSV and external tick datasets. The engine never changes.  |
//|                                                                  |
//|  WHY COMPOSITION AND NOT MULTIPLE INHERITANCE                    |
//|  MQL5 has single inheritance only, so one class cannot be both   |
//|  an IBarProvider and an ITickProvider. A data source therefore   |
//|  OWNS its providers and hands out pointers to them. This is also |
//|  the honest model: a CSV of daily bars genuinely has no tick     |
//|  provider, and the engine must be able to ask rather than guess. |
//|                                                                  |
//|  EVERY provider carries the future guard. The controller already |
//|  clamps ranges before calling, but a provider that trusts its    |
//|  caller is one refactor away from leaking the future.            |
//+------------------------------------------------------------------+
#ifndef SSR_IDATASOURCE_MQH
#define SSR_IDATASOURCE_MQH

#include "../Common/SSR_Types.mqh"
#include "../Common/SSR_Time.mqh"
#include "SSR_FutureGuard.mqh"

//+------------------------------------------------------------------+
//| What a source knows about the data it can offer, before any of   |
//| it is loaded. Phase 6's "Load More History" is driven by this.   |
//+------------------------------------------------------------------+
struct SSRDataRange
  {
   bool              available;
   long              first_msc;        // earliest instant held locally
   long              last_msc;         // latest instant held locally
   long              server_first_msc; // earliest the origin could supply
   long              bar_count;
   bool              has_ticks;

   void              Init(void)
     {
      available        = false;
      first_msc        = SSR_INVALID_TIME;
      last_msc         = SSR_INVALID_TIME;
      server_first_msc = SSR_INVALID_TIME;
      bar_count        = 0;
      has_ticks        = false;
     }

   //--- is there older data that a deeper load could still fetch?
   bool              CanExtendBackwards(void)
     {
      return (server_first_msc > 0 && first_msc > 0 && server_first_msc < first_msc);
     }
  };

//+------------------------------------------------------------------+
//| Base for every provider: guard ownership and error reporting.    |
//+------------------------------------------------------------------+
class CSSRProviderBase
  {
protected:
   CSSRFutureGuard  *m_guard;        // not owned
   ENUM_SSR_ERR      m_last_error;
   string            m_last_error_text;

   void              Fail(const ENUM_SSR_ERR e, const string text)
     {
      m_last_error      = e;
      m_last_error_text = text;
     }

   void              Succeed(void)
     {
      m_last_error      = SSR_OK;
      m_last_error_text = "";
     }

   //--- clamp a range through the guard; false means nothing readable
   bool              GuardRange(long &from_msc, long &to_msc)
     {
      if(m_guard == NULL)
         return (from_msc <= to_msc);
      return m_guard.ClampRange(from_msc, to_msc);
     }

public:
                     CSSRProviderBase(void)
     : m_guard(NULL), m_last_error(SSR_OK), m_last_error_text("") {}
   virtual          ~CSSRProviderBase(void) {}

   void              SetGuard(CSSRFutureGuard *g) { m_guard = g; }
   CSSRFutureGuard  *Guard(void)                  { return m_guard; }

   ENUM_SSR_ERR      LastError(void)     { return m_last_error; }
   string            LastErrorText(void) { return m_last_error_text; }
  };

//+------------------------------------------------------------------+
//| IHistoryProvider - discovery and preparation, no reading.        |
//+------------------------------------------------------------------+
class CSSRHistoryProvider : public CSSRProviderBase
  {
public:
   virtual          ~CSSRHistoryProvider(void) {}

   //--- what is available for this symbol right now
   virtual bool      Discover(const string symbol, SSRDataRange &out) = 0;

   //--- make sure [from,to] is locally present; may be slow
   virtual bool      Ensure(const string symbol, const long from_msc, const long to_msc) = 0;

   //--- try to extend the local history backwards; returns new first_msc
   virtual long      ExtendBackwards(const string symbol, const long bars) = 0;
  };

//+------------------------------------------------------------------+
//| IBarProvider - M1 bars. The engine only ever asks for M1,        |
//| because M1 is the storage base every higher timeframe derives    |
//| from. Asking for anything else would be asking the wrong layer.  |
//+------------------------------------------------------------------+
class CSSRBarProvider : public CSSRProviderBase
  {
public:
   virtual          ~CSSRBarProvider(void) {}

   //--- bars whose OPEN time lies in [from_msc, to_msc], ascending.
   //--- returns the count written into `out`, or -1 on error.
   virtual int       ReadBars(const string symbol, const long from_msc,
                              const long to_msc, MqlRates &out[]) = 0;

   //--- the single bar containing `msc`, if it exists
   virtual bool      ReadBarAt(const string symbol, const long msc, MqlRates &out) = 0;

   virtual long      BarCount(const string symbol) = 0;
  };

//+------------------------------------------------------------------+
//| ITickProvider - real ticks. A source without them says so, and   |
//| the engine drops to a synthetic fidelity instead of pretending.  |
//+------------------------------------------------------------------+
class CSSRTickProvider : public CSSRProviderBase
  {
public:
   virtual          ~CSSRTickProvider(void) {}

   virtual bool      HasTicks(const string symbol, const long from_msc, const long to_msc) = 0;

   //--- ticks in (from_msc, to_msc], ascending. -1 on error.
   //--- the half-open lower bound matters: the engine advances by
   //--- consuming everything strictly after the last emitted instant.
   virtual int       ReadTicks(const string symbol, const long from_msc,
                               const long to_msc, MqlTick &out[]) = 0;
  };

//+------------------------------------------------------------------+
//| IDataSource - owns the three providers above and its own         |
//| lifecycle. Anything that can be replayed implements this.        |
//+------------------------------------------------------------------+
class CSSRDataSource
  {
protected:
   ENUM_SSR_DATA_MODE m_mode;
   bool               m_open;
   CSSRFutureGuard   *m_guard;    // not owned

public:
                     CSSRDataSource(void)
     : m_mode(SSR_DATA_MEMORY), m_open(false), m_guard(NULL) {}
   virtual          ~CSSRDataSource(void) {}

   virtual string    Name(void) = 0;
   virtual bool      Open(const string symbol) = 0;
   virtual void      Close(void) = 0;

   //+------------------------------------------------------------------+
   //| The session about to run, announced before any reading starts.   |
   //|                                                                  |
   //| A source that buffers can size that buffer from the session      |
   //| instead of from a constant; one that does not simply ignores the |
   //| call. Core learns nothing about buffering either way.            |
   //+------------------------------------------------------------------+
   virtual void       OnSessionPlanned(const long replay_minutes) {}

   virtual CSSRHistoryProvider *History(void) = 0;
   virtual CSSRBarProvider     *Bars(void)    = 0;
   virtual CSSRTickProvider    *Ticks(void)   = 0;   // NULL when unsupported

   ENUM_SSR_DATA_MODE Mode(void)   { return m_mode; }
   bool               IsOpen(void) { return m_open; }

   //+------------------------------------------------------------------+
   //| Drop the guard everywhere this source holds it.                  |
   //|                                                                  |
   //| The guard is a MEMBER of the controller, so a data source that   |
   //| outlives its controller would keep a dangling pointer and the    |
   //| next read would touch freed memory. Every teardown path calls    |
   //| this first. Overridden by sources that own extra providers.      |
   //+------------------------------------------------------------------+
   virtual void       DetachGuard(void)
     {
      m_guard = NULL;
      CSSRHistoryProvider *h = History();
      if(h != NULL) h.SetGuard(NULL);
      CSSRBarProvider *b = Bars();
      if(b != NULL) b.SetGuard(NULL);
      CSSRTickProvider *t = Ticks();
      if(t != NULL) t.SetGuard(NULL);
     }

   //--- push the guard down into every provider this source owns
   virtual void       SetGuard(CSSRFutureGuard *g)
     {
      m_guard = g;
      CSSRHistoryProvider *h = History();
      if(h != NULL) h.SetGuard(g);
      CSSRBarProvider *b = Bars();
      if(b != NULL) b.SetGuard(g);
      CSSRTickProvider *t = Ticks();
      if(t != NULL) t.SetGuard(g);
     }
  };

#endif // SSR_IDATASOURCE_MQH
//+------------------------------------------------------------------+
