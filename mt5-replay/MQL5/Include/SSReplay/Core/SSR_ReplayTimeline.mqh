//+------------------------------------------------------------------+
//|                                            SSR_ReplayTimeline.mqh |
//|                                   SS Replay - Replay Timeline(L2)|
//|                                                                  |
//|  Three ranges live here and they are not the same thing:         |
//|                                                                  |
//|    data   [data_first .. data_last]   what the source actually   |
//|                                        holds                     |
//|    replay [start .. end]               the window being replayed |
//|    warmup [warmup_first .. start]      history seeded BEFORE the |
//|                                        start so higher timeframes|
//|                                        have context on bar one   |
//|                                                                  |
//|  Conflating warmup with replay is what produces the "my H4 chart |
//|  is empty when replay starts" bug, so they are separate fields.  |
//+------------------------------------------------------------------+
#ifndef SSR_REPLAY_TIMELINE_MQH
#define SSR_REPLAY_TIMELINE_MQH

#include "../Common/SSR_Types.mqh"
#include "../Common/SSR_Time.mqh"

//+------------------------------------------------------------------+
struct SSRReplayTimeline
  {
   long              data_first_msc;
   long              data_last_msc;
   long              warmup_first_msc;
   long              start_msc;
   long              end_msc;

   void              Init(void)
     {
      data_first_msc   = SSR_INVALID_TIME;
      data_last_msc    = SSR_INVALID_TIME;
      warmup_first_msc = SSR_INVALID_TIME;
      start_msc        = SSR_INVALID_TIME;
      end_msc          = SSR_INVALID_TIME;
     }

   void              SetDataBounds(const long first_msc, const long last_msc)
     {
      data_first_msc = first_msc;
      data_last_msc  = last_msc;
     }

   //+------------------------------------------------------------------+
   //| Define the replay window. `end_msc <= 0` means "to the end of    |
   //| the available data". Everything is clamped into the data bounds, |
   //| so an out-of-range request degrades instead of failing.          |
   //+------------------------------------------------------------------+
   bool              SetWindow(const long a_start_msc, const long a_end_msc)
     {
      if(data_first_msc <= 0 || data_last_msc <= data_first_msc)
         return false;
      if(a_start_msc <= 0)
         return false;

      //--- Snap the start DOWN to an M1 boundary.
      //--- Truncation can only land on a bar open, so a start chosen
      //--- mid-minute would make the first rewind cut into the warmup
      //--- and delete history the replay never owned.
      long snapped = SSRBarOpenMsc(a_start_msc, PERIOD_M1);
      start_msc = SSRClampMsc(snapped, data_first_msc, data_last_msc);

      long e  = (a_end_msc > 0 ? a_end_msc : data_last_msc);
      end_msc = SSRClampMsc(e, start_msc, data_last_msc);

      return (end_msc > start_msc);
     }

   //--- how much history to seed before the start, expressed in M1 bars
   void              SetWarmupBars(const long bars)
     {
      if(start_msc <= 0)
        {
         warmup_first_msc = SSR_INVALID_TIME;
         return;
        }
      long want = start_msc - bars * SSR_MSC_PER_MIN;
      if(data_first_msc > 0 && want < data_first_msc)
         want = data_first_msc;
      warmup_first_msc = want;
     }

   //+------------------------------------------------------------------+
   //| How many M1 bars of warmup a given timeframe needs to show       |
   //| `visible_bars` candles at replay start.                          |
   //|                                                                  |
   //| This is the 288,000-bars-for-200-daily-candles arithmetic from   |
   //| the design document, in one place so the UI can quote a cost     |
   //| to the user BEFORE a long seed rather than after it.             |
   //+------------------------------------------------------------------+
   static long       WarmupBarsFor(const ENUM_TIMEFRAMES tf, const long visible_bars)
     {
      int secs = PeriodSeconds(tf);
      if(secs <= 0)
         return visible_bars;
      return visible_bars * (long)(secs / 60);
     }

   bool              IsValid(void)
     {
      return (start_msc > 0 && end_msc > start_msc &&
              data_first_msc > 0 && data_last_msc >= end_msc);
     }

   bool              Contains(const long msc)
     {
      return (msc >= start_msc && msc <= end_msc);
     }

   long              Span(void)       { return (IsValid() ? end_msc - start_msc : 0); }
   long              WarmupSpan(void)
     {
      if(warmup_first_msc <= 0 || start_msc <= 0)
         return 0;
      return start_msc - warmup_first_msc;
     }

   string            ToString(void)
     {
      return StringFormat("timeline[data %s..%s | warmup %s | replay %s..%s | span %s]",
                          SSRFormatMsc(data_first_msc), SSRFormatMsc(data_last_msc),
                          SSRFormatMsc(warmup_first_msc),
                          SSRFormatMsc(start_msc), SSRFormatMsc(end_msc),
                          SSRFormatSpan(Span()));
     }
  };

#endif // SSR_REPLAY_TIMELINE_MQH
//+------------------------------------------------------------------+
