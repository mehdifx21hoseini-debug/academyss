//+------------------------------------------------------------------+
//|                                                SSR_BlindMode.mqh |
//|                      SS Replay - Blind Mode (L3/Chart)           |
//|                                                                  |
//|  Practising on a period you recognise teaches you that you have  |
//|  a good memory. Blind Mode removes the labels that let you       |
//|  recognise it: the dates, the instrument, the price context.     |
//|                                                                  |
//|  WHAT IT CANNOT DO, SAID OUT LOUD                                |
//|                                                                  |
//|  MetaTrader has no property that hides the symbol name from a    |
//|  chart, and none that hides the time under the crosshair or in   |
//|  the Data Window. A tool that claims "blind" and leaves those    |
//|  in place is worse than one that does not offer the mode, so:    |
//|                                                                  |
//|   - the symbol is handled at the SOURCE, by naming the replay    |
//|     symbol "Chart.SSR1" instead of "XAUUSD.SSR1". Nothing to     |
//|     hide, because nothing was written.                           |
//|   - the leaks that remain are listed by Leaks(), and the panel   |
//|     shows that list rather than a checkmark.                     |
//|                                                                  |
//|  This class changes chart properties and REMEMBERS what they     |
//|  were, because a mode the user cannot leave without rebuilding   |
//|  their chart is a trap.                                          |
//+------------------------------------------------------------------+
#ifndef SSR_BLIND_MODE_MQH
#define SSR_BLIND_MODE_MQH

#include "../Common/SSR_Types.mqh"
#include "../Common/SSR_Time.mqh"
#include "SSR_ChartTypes.mqh"

//--- charts whose settings this can remember. Larger than
//--- SSR_MAX_CHARTS because a multi-symbol board has one chart
//--- registry PER STREAM, and blind mode spans all of them.
#define SSR_BLIND_MAX_CHARTS   48

//--- the three settings a user actually chooses between, so the host
//--- can offer one input instead of six checkboxes
enum ENUM_SSR_BLIND
  {
   SSR_BLIND_OFF = 0,
   SSR_BLIND_STANDARD,   // no dates, no instrument name; price stays
   SSR_BLIND_FULL        // and no price level either
  };

//+------------------------------------------------------------------+
//| What "blind" means, as separate choices rather than one switch.  |
//+------------------------------------------------------------------+
struct SSRBlindPolicy
  {
   bool              hide_dates;        // the time axis
   bool              hide_ohlc;         // the OHLC line in the corner
   bool              hide_price_scale;  // the price axis - hides the LEVEL
   bool              anonymous_symbol;  // applied by the sink, at creation
   bool              mask_ui_time;      // the panel shows elapsed, not the date
   bool              mask_ui_symbol;

   void              Init(void)
     {
      hide_dates = false; hide_ohlc = false; hide_price_scale = false;
      anonymous_symbol = false; mask_ui_time = false; mask_ui_symbol = false;
     }

   //--- the usual meaning of the word: the period is unrecognisable,
   //--- but the trader can still read price, because a chart with no
   //--- price axis is not practice, it is a guessing game
   void              Standard(void)
     {
      hide_dates = true; hide_ohlc = false; hide_price_scale = false;
      anonymous_symbol = true; mask_ui_time = true; mask_ui_symbol = true;
     }

   //--- for the trader who knows the price levels of their instrument
   //--- by heart and would recognise the period from those alone
   void              Full(void)
     {
      Standard();
      hide_ohlc = true; hide_price_scale = true;
     }

   void              Apply(const ENUM_SSR_BLIND level)
     {
      Init();
      if(level == SSR_BLIND_STANDARD) Standard();
      if(level == SSR_BLIND_FULL)     Full();
     }

   bool              AnyOn(void)
     {
      return (hide_dates || hide_ohlc || hide_price_scale ||
              anonymous_symbol || mask_ui_time || mask_ui_symbol);
     }

   string            ToString(void)
     {
      if(!AnyOn())
         return "blind off";
      string s = "blind:";
      if(anonymous_symbol) s += " symbol";
      if(hide_dates)       s += " dates";
      if(hide_ohlc)        s += " ohlc";
      if(hide_price_scale) s += " price";
      return s;
     }
  };

//+------------------------------------------------------------------+
class CSSRBlindMode
  {
private:
   SSRBlindPolicy    m_policy;
   bool              m_applied;

   //--- what each chart looked like before we touched it
   long              m_id[SSR_BLIND_MAX_CHARTS];
   bool              m_had_dates[SSR_BLIND_MAX_CHARTS];
   bool              m_had_ohlc[SSR_BLIND_MAX_CHARTS];
   bool              m_had_price[SSR_BLIND_MAX_CHARTS];
   int               m_saved;

   int               Find(const long id)
     {
      for(int i = 0; i < m_saved; i++)
         if(m_id[i] == id)
            return i;
      return -1;
     }

public:
                     CSSRBlindMode(void) : m_applied(false), m_saved(0)
     { m_policy.Init(); }

   void              SetPolicy(SSRBlindPolicy &p) { m_policy = p; }
   void              PolicyInto(SSRBlindPolicy &out) { out = m_policy; }
   bool              IsOn(void)      { return m_policy.AnyOn(); }
   bool              IsApplied(void) { return m_applied; }
   bool              Anonymous(void) { return m_policy.anonymous_symbol; }

   //+------------------------------------------------------------------+
   //| Apply to one chart, saving what was there first.                 |
   //|                                                                  |
   //| Saving happens ONCE per chart. Applying twice must not record    |
   //| our own hidden state as the thing to restore - that is how a     |
   //| "restore" leaves the chart exactly as blind as it found it.      |
   //+------------------------------------------------------------------+
   bool              Apply(const long chart_id)
     {
      if(chart_id == 0 || !m_policy.AnyOn())
         return false;

      if(Find(chart_id) < 0)
        {
         //--- REFUSE rather than change what cannot be changed back.
         //--- Applying past the registry would leave a chart blind
         //--- with no record of what it looked like - exactly the
         //--- trap this class exists to avoid.
         if(m_saved >= SSR_BLIND_MAX_CHARTS)
            return false;
         int i = m_saved++;
         m_id[i]         = chart_id;
         m_had_dates[i]  = (bool)ChartGetInteger(chart_id, CHART_SHOW_DATE_SCALE);
         m_had_ohlc[i]   = (bool)ChartGetInteger(chart_id, CHART_SHOW_OHLC);
         m_had_price[i]  = (bool)ChartGetInteger(chart_id, CHART_SHOW_PRICE_SCALE);
        }

      if(m_policy.hide_dates)
         ChartSetInteger(chart_id, CHART_SHOW_DATE_SCALE, false);
      if(m_policy.hide_ohlc)
         ChartSetInteger(chart_id, CHART_SHOW_OHLC, false);
      if(m_policy.hide_price_scale)
         ChartSetInteger(chart_id, CHART_SHOW_PRICE_SCALE, false);

      m_applied = true;
      return true;
     }

   //--- put the chart back the way the user had it
   bool              Restore(const long chart_id)
     {
      int i = Find(chart_id);
      if(i < 0)
         return false;
      ChartSetInteger(chart_id, CHART_SHOW_DATE_SCALE,  m_had_dates[i]);
      ChartSetInteger(chart_id, CHART_SHOW_OHLC,        m_had_ohlc[i]);
      ChartSetInteger(chart_id, CHART_SHOW_PRICE_SCALE, m_had_price[i]);

      //--- forget it, so a later Apply saves fresh state
      for(int k = i; k < m_saved - 1; k++)
        {
         m_id[k]        = m_id[k + 1];
         m_had_dates[k] = m_had_dates[k + 1];
         m_had_ohlc[k]  = m_had_ohlc[k + 1];
         m_had_price[k] = m_had_price[k + 1];
        }
      m_saved--;
      return true;
     }

   int               RestoreAll(void)
     {
      int n = 0;
      while(m_saved > 0)
         if(Restore(m_id[0]))
            n++;
         else
            break;
      m_applied = false;
      return n;
     }

   int               SavedCharts(void) { return m_saved; }

   //+------------------------------------------------------------------+
   //| What the UI shows instead of the truth.                          |
   //|                                                                  |
   //| Elapsed time, not the clock: the trader still needs to know how  |
   //| far into the session they are, and "02:15 in" reveals nothing    |
   //| about which day it is.                                           |
   //+------------------------------------------------------------------+
   string            MaskTime(const long msc, const long start_msc)
     {
      if(!m_policy.mask_ui_time)
         return SSRFormatMsc(msc);
      if(msc <= 0 || start_msc <= 0 || msc < start_msc)
         return "--";
      return SSRFormatSpan(msc - start_msc) + " in";
     }

   string            MaskSymbol(const string s)
     { return (m_policy.mask_ui_symbol ? "(blind)" : s); }

   //+------------------------------------------------------------------+
   //| The leaks this mode does NOT close. Shown to the user, because   |
   //| a trader who believes they are blind and is not will draw        |
   //| conclusions from a session that was never a fair test.           |
   //+------------------------------------------------------------------+
   string            Leaks(void)
     {
      if(!m_policy.AnyOn())
         return "";
      string s = "still visible: ";
      if(m_policy.hide_dates)
         s += "the date under the crosshair and in the Data Window; ";
      if(!m_policy.hide_price_scale)
         s += "the price level, which identifies the period on an "
              "instrument you know well; ";
      s += "the terminal's own Market Watch and Navigator";
      return s;
     }

   string            ToString(void)
     {
      return StringFormat("%s applied=%s charts=%d",
                          m_policy.ToString(),
                          (m_applied ? "yes" : "no"), m_saved);
     }
  };

#endif // SSR_BLIND_MODE_MQH
//+------------------------------------------------------------------+
