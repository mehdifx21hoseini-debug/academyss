//+------------------------------------------------------------------+
//|                                            SSR_ITickObserver.mqh |
//|                     SS Replay - Replay Stream Observers (L2)     |
//|                                                                  |
//|  How anything watches the replay without Core knowing what it is. |
//|                                                                  |
//|  The trading engine, the statistics engine and any future         |
//|  strategy all need the same thing: the stream of ticks, in order, |
//|  with the replay clock attached. Core publishes exactly that and  |
//|  learns nothing about who is listening.                           |
//|                                                                  |
//|  TWO CALLS, NOT ONE, AND THE ORDER MATTERS                        |
//|  OnBarContext arrives BEFORE the ticks synthesised from that bar. |
//|  That ordering is what makes honest stop-and-target handling      |
//|  possible: an observer can see the bar's full range and know that |
//|  both levels fall inside it BEFORE deciding which was hit first.  |
//|  Given ticks alone it would have to guess, and the guess would    |
//|  always favour whichever the synthesiser happened to reach first. |
//+------------------------------------------------------------------+
#ifndef SSR_ITICK_OBSERVER_MQH
#define SSR_ITICK_OBSERVER_MQH

#include "../Common/SSR_Types.mqh"

//+------------------------------------------------------------------+
class CSSRTickObserver
  {
public:
   virtual          ~CSSRTickObserver(void) {}
   virtual string    Name(void) { return "observer"; }

   //+------------------------------------------------------------------+
   //| The bar the following ticks were built from, and whether those   |
   //| ticks are real or synthesised.                                   |
   //|                                                                  |
   //| `synthetic` is not a detail: when it is true, the ORDER of       |
   //| prices inside the bar is an assumption rather than data, and an  |
   //| observer that acts on that order must say so in its output.      |
   //+------------------------------------------------------------------+
   virtual void      OnBarContext(const MqlRates &bar, const bool synthetic) {}

   //--- ticks, in order, never repeated
   virtual void      OnTicks(const MqlTick &ticks[], const int count) {}

   //--- the replay clock moved, with or without ticks
   virtual void      OnClock(const long now_msc) {}

   //+------------------------------------------------------------------+
   //| Everything at or after `msc` did not happen after all.           |
   //|                                                                  |
   //| An observer that keeps state MUST honour this. Ignoring it is    |
   //| how a rewind leaves trades stranded in a future that was         |
   //| deleted - the exact failure this product exists to prevent, one  |
   //| layer up from the chart.                                         |
   //+------------------------------------------------------------------+
   virtual void      OnRewind(const long msc) {}

   //--- a new session; drop everything
   virtual void      OnSessionStart(const string symbol, const int digits,
                                    const double point, const long start_msc) {}
  };

#endif // SSR_ITICK_OBSERVER_MQH
//+------------------------------------------------------------------+
