//+------------------------------------------------------------------+
//|                                            SSR_SessionRange.mqh  |
//|                       SS Replay - The Session Request (L1/Data)  |
//|                                                                  |
//|  What the user asked for, separated from what the engine will do |
//|  about it. Holding this as its own object means the panel can    |
//|  build a request, quote it, adjust it and only then commit -     |
//|  rather than the engine discovering a bad range halfway through  |
//|  a seed.                                                         |
//+------------------------------------------------------------------+
#ifndef SSR_SESSION_RANGE_MQH
#define SSR_SESSION_RANGE_MQH

#include "../Common/SSR_Types.mqh"
#include "../Common/SSR_Time.mqh"
#include "SSR_HistoryCatalog.mqh"

//+------------------------------------------------------------------+
struct SSRSessionRange
  {
   string             origin;
   long               start_msc;
   long               end_msc;
   ENUM_TIMEFRAMES    max_tf;        // deepest timeframe the user wants context for
   long               visible_bars;  // candles of max_tf visible at the start
   ENUM_SSR_FIDELITY  fidelity;
   int                slot;

   void               Init(void)
     {
      origin       = "";
      start_msc    = SSR_INVALID_TIME;
      end_msc      = SSR_INVALID_TIME;
      max_tf       = PERIOD_H1;
      visible_bars = 300;
      fidelity     = SSR_FIDELITY_SYNTHETIC_TICK;
      slot         = 1;
     }

   long               WarmupBars(void)
     { return CSSRHistoryCatalog::WarmupFor(max_tf, visible_bars); }

   long               ReplayMinutes(void)
     {
      if(start_msc <= 0 || end_msc <= start_msc)
         return 0;
      return (end_msc - start_msc) / SSR_MSC_PER_MIN;
     }

   bool               IsComplete(void)
     {
      return (origin != "" && start_msc > 0 && end_msc > start_msc);
     }

   string             Describe(void)
     {
      if(!IsComplete())
         return "incomplete";
      return StringFormat("%s  %s -> %s  (%s)  %s context x%d",
                          origin,
                          SSRFormatMsc(start_msc), SSRFormatMsc(end_msc),
                          SSRFormatSpan(end_msc - start_msc),
                          EnumToString(max_tf), (int)visible_bars);
     }
  };

//+------------------------------------------------------------------+
//| Why a request cannot be served, in words a user can act on.      |
//+------------------------------------------------------------------+
string SSRValidateRange(SSRSessionRange &r, CSSRHistoryCatalog &cat)
  {
   if(r.origin == "")
      return "pick a symbol";
   if(!cat.Available())
      return "no M1 history for " + r.origin;
   if(r.start_msc <= 0)
      return "pick a start date";
   if(r.end_msc <= r.start_msc)
      return "the end must come after the start";

   long warm = r.WarmupBars();
   long earliest = cat.EarliestStart(warm);
   if(r.start_msc < earliest)
      return StringFormat("start too early - %s context needs history back to %s",
                          EnumToString(r.max_tf), SSRFormatMsc(earliest));
   if(r.start_msc >= cat.LastMsc())
      return "start is beyond the available history";

   SSRSeedQuote q;
   cat.Quote(r.max_tf, r.visible_bars, r.ReplayMinutes(), q);
   if(q.exceeds_history)
      return "not enough history: " + q.ToString();
   //--- not a refusal: the terminal will simply not draw them all, and
   //--- the user is better told than left wondering
   if(q.exceeds_maxbars)
      return "warning: exceeds the terminal's Max bars in chart setting";

   return "";
  }

#endif // SSR_SESSION_RANGE_MQH
//+------------------------------------------------------------------+
