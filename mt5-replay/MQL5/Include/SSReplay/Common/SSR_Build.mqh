//+------------------------------------------------------------------+
//|                                                   SSR_Build.mqh  |
//|                                    SS Replay - the build stamp   |
//|                                                                  |
//|  ONE LINE, IN ONE PLACE, THAT EVERY PROGRAM CAN REACH.           |
//|                                                                  |
//|  It lives in its own header so the Phase 0 spike kit can print   |
//|  it without including the product's type system. The spikes are  |
//|  meant to measure MetaTrader, not the engine, and a stamp is the |
//|  one thing they legitimately share with it.                      |
//|                                                                  |
//|  Why this exists at all: four times now, a package of fixes has  |
//|  been run against, and judged by, an older compiled copy still   |
//|  sitting in the terminal. Each time it cost a full round trip to |
//|  work out that the code under test was not the code that was     |
//|  sent. A version printed on the first line of every run turns    |
//|  that from a forensic exercise into a glance.                    |
//+------------------------------------------------------------------+
#ifndef SSR_BUILD_MQH
#define SSR_BUILD_MQH

#define SSR_BUILD           "v50 2026-08-31  a11-right-class"

#endif // SSR_BUILD_MQH
//+------------------------------------------------------------------+
