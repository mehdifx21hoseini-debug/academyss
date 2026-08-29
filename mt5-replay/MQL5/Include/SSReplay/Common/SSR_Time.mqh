//+------------------------------------------------------------------+
//|                                                     SSR_Time.mqh |
//|                                 SS Replay - Time Utilities (L0)  |
//|                                                                  |
//|  The single place where millisecond time and datetime meet.      |
//|  Nothing else in the product converts between them by hand.      |
//+------------------------------------------------------------------+
#ifndef SSR_TIME_MQH
#define SSR_TIME_MQH

#include "SSR_Types.mqh"

//--- conversions ---------------------------------------------------
long     SSRToMsc(const datetime t)      { return (long)t * SSR_MSC_PER_SEC; }
datetime SSRToTime(const long msc)       { return (datetime)(msc / SSR_MSC_PER_SEC); }
long     SSRSecOf(const long msc)        { return msc / SSR_MSC_PER_SEC; }

//+------------------------------------------------------------------+
//| Floor a millisecond timestamp to the opening time of the bar     |
//| that contains it, for a given timeframe.                         |
//|                                                                  |
//| Valid for M1..H4 and D1, where MT5 bar boundaries align with     |
//| the epoch. W1 and MN1 do NOT align that way and are deliberately |
//| not handled here - the engine never needs them, because every    |
//| higher timeframe is derived by the terminal, not by us.          |
//+------------------------------------------------------------------+
long SSRBarOpenMsc(const long msc, const ENUM_TIMEFRAMES tf)
  {
   int secs = PeriodSeconds(tf);
   if(secs <= 0)
      return msc;
   long period = (long)secs * SSR_MSC_PER_SEC;
   return (msc / period) * period;
  }

//--- opening time of the bar AFTER the one containing msc
long SSRNextBarOpenMsc(const long msc, const ENUM_TIMEFRAMES tf)
  {
   int secs = PeriodSeconds(tf);
   if(secs <= 0)
      return msc;
   return SSRBarOpenMsc(msc, tf) + (long)secs * SSR_MSC_PER_SEC;
  }

//--- is this timeframe one the engine is allowed to reason about?
bool SSRIsSupportedTimeframe(const ENUM_TIMEFRAMES tf)
  {
   switch(tf)
     {
      case PERIOD_M1:  case PERIOD_M2:  case PERIOD_M3:  case PERIOD_M4:
      case PERIOD_M5:  case PERIOD_M6:  case PERIOD_M10: case PERIOD_M12:
      case PERIOD_M15: case PERIOD_M20: case PERIOD_M30:
      case PERIOD_H1:  case PERIOD_H2:  case PERIOD_H3:  case PERIOD_H4:
      case PERIOD_H6:  case PERIOD_H8:  case PERIOD_H12:
      case PERIOD_D1:
         return true;
     }
   return false;
  }

//--- formatting ----------------------------------------------------
string SSRFormatMsc(const long msc)
  {
   if(msc <= 0)
      return "--";
   return TimeToString(SSRToTime(msc), TIME_DATE | TIME_MINUTES | TIME_SECONDS);
  }

string SSRFormatMscMs(const long msc)
  {
   if(msc <= 0)
      return "--";
   return StringFormat("%s.%03d", SSRFormatMsc(msc), (int)(msc % SSR_MSC_PER_SEC));
  }

//--- a duration in milliseconds, rendered for humans
string SSRFormatSpan(const long span_msc)
  {
   if(span_msc < 0)
      return "--";
   long total = span_msc / SSR_MSC_PER_SEC;
   long d = total / 86400;
   long h = (total % 86400) / 3600;
   long m = (total % 3600) / 60;
   long s = total % 60;
   if(d > 0) return StringFormat("%dd %02d:%02d:%02d", (int)d, (int)h, (int)m, (int)s);
   return StringFormat("%02d:%02d:%02d", (int)h, (int)m, (int)s);
  }

//--- clamp helper used across the guard and the timeline
long SSRClampMsc(const long v, const long lo, const long hi)
  {
   if(v < lo) return lo;
   if(v > hi) return hi;
   return v;
  }

#endif // SSR_TIME_MQH
//+------------------------------------------------------------------+
