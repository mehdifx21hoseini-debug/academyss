//+------------------------------------------------------------------+
//|                                            SSR_Mt5DataSource.mqh |
//|                        SS Replay - MT5 Broker Data Source (L1)   |
//|                                                                  |
//|  Composes the three MT5 providers into the CSSRDataSource the    |
//|  engine expects. Phase 1's controller does not change by a line  |
//|  to use it - which is the point of having had the contract.      |
//+------------------------------------------------------------------+
#ifndef SSR_MT5_DATASOURCE_MQH
#define SSR_MT5_DATASOURCE_MQH

#include "../Core/SSR_IDataSource.mqh"
#include "SSR_Mt5Providers.mqh"

//+------------------------------------------------------------------+
class CSSRMt5DataSource : public CSSRDataSource
  {
private:
   CSSRMt5HistoryProvider *m_hist;
   CSSRMt5BarProvider     *m_bars;
   CSSRMt5TickProvider    *m_ticks;

   string                  m_symbol;
   bool                    m_has_ticks;
   bool                    m_allow_ticks;
   SSRDataRange            m_range;

public:
                     CSSRMt5DataSource(void)
     : m_symbol(""), m_has_ticks(false), m_allow_ticks(true)
     {
      m_mode  = SSR_DATA_BROKER;
      m_hist  = new CSSRMt5HistoryProvider();
      m_bars  = new CSSRMt5BarProvider();
      m_ticks = new CSSRMt5TickProvider();
      m_range.Init();
     }

                    ~CSSRMt5DataSource(void)
     {
      //--- detach before destroying: the guard belongs to the controller
      //--- and may already be gone. See TODO T1 from Phase 1.
      DetachGuard();
      if(CheckPointer(m_hist)  == POINTER_DYNAMIC) delete m_hist;
      if(CheckPointer(m_bars)  == POINTER_DYNAMIC) delete m_bars;
      if(CheckPointer(m_ticks) == POINTER_DYNAMIC) delete m_ticks;
     }

   virtual string    Name(void) override { return "mt5-broker"; }

   //+------------------------------------------------------------------+
   //| Opening does the discovery, so a caller that cannot even see the |
   //| symbol finds out here rather than three layers deeper.           |
   //+------------------------------------------------------------------+
   virtual bool      Open(const string symbol) override
     {
      m_symbol = symbol;
      m_open   = false;
      m_range.Init();

      if(!SymbolSelect(symbol, true))
         return false;

      if(!m_hist.Discover(symbol, m_range))
         return false;

      m_has_ticks = m_range.has_ticks;
      m_bars.Invalidate();
      m_open = true;
      return true;
     }

   virtual void      Close(void) override
     {
      m_bars.Invalidate();
      m_open = false;
     }

   virtual CSSRHistoryProvider *History(void) override { return m_hist; }
   virtual CSSRBarProvider     *Bars(void)    override { return m_bars; }

   //+------------------------------------------------------------------+
   //| Report the tick provider ONLY when real ticks exist.             |
   //|                                                                  |
   //| Returning it unconditionally would let the engine run at         |
   //| FULL_TICK fidelity against an empty tick history and emit        |
   //| nothing - a replay that silently shows a frozen market. Saying   |
   //| NULL makes the engine degrade to synthetic ticks and announce it.|
   //+------------------------------------------------------------------+
   virtual CSSRTickProvider    *Ticks(void) override
     {
      if(!m_allow_ticks || !m_has_ticks)
         return NULL;
      return m_ticks;
     }

   //+------------------------------------------------------------------+
   //| The base walks the providers via Ticks(), which returns NULL when |
   //| the broker has no tick history - so the tick provider would never |
   //| be armed. Reach all three directly instead.                       |
   //+------------------------------------------------------------------+
   virtual void      SetGuard(CSSRFutureGuard *g) override
     {
      m_guard = g;
      if(CheckPointer(m_hist)  == POINTER_DYNAMIC) m_hist.SetGuard(g);
      if(CheckPointer(m_bars)  == POINTER_DYNAMIC) m_bars.SetGuard(g);
      if(CheckPointer(m_ticks) == POINTER_DYNAMIC) m_ticks.SetGuard(g);
     }

   //--- guard lifetime (closes Phase 1 TODO T1) ----------------------
   virtual void      DetachGuard(void) override
     {
      m_guard = NULL;
      if(CheckPointer(m_hist)  == POINTER_DYNAMIC) m_hist.SetGuard(NULL);
      if(CheckPointer(m_bars)  == POINTER_DYNAMIC) m_bars.SetGuard(NULL);
      if(CheckPointer(m_ticks) == POINTER_DYNAMIC) m_ticks.SetGuard(NULL);
     }

   //--- configuration ------------------------------------------------
   void              SetAllowTicks(const bool on) { m_allow_ticks = on; }
   void              SetWindowBars(const int n)   { m_bars.SetWindowBars(n); }
   void              SetTickFlags(const uint f)   { m_ticks.SetFlags(f); }

   //--- diagnostics ---------------------------------------------------
   bool              HasTicks(void)   { return m_has_ticks; }
   string            SymbolName(void) { return m_symbol; }
   void              RangeInto(SSRDataRange &out) { out = m_range; }

   CSSRMt5HistoryProvider *Mt5History(void) { return m_hist; }
   CSSRMt5BarProvider     *Mt5Bars(void)    { return m_bars; }
   CSSRMt5TickProvider    *Mt5Ticks(void)   { return m_ticks; }

   string            ToString(void)
     {
      return StringFormat("mt5[%s open=%s ticks=%s %s]",
                          m_symbol, (m_open ? "yes" : "no"),
                          (m_has_ticks ? "yes" : "no"),
                          m_bars.Window().ToString());
     }
  };

#endif // SSR_MT5_DATASOURCE_MQH
//+------------------------------------------------------------------+
