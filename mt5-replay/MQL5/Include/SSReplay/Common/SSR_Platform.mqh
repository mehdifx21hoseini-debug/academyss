//+------------------------------------------------------------------+
//|                                                 SSR_Platform.mqh |
//|                        SS Replay - Platform Helpers (L0)         |
//|                                                                  |
//|  The few places the product must ask MetaTrader about itself,    |
//|  isolated so no higher layer calls a terminal API directly.      |
//+------------------------------------------------------------------+
#ifndef SSR_PLATFORM_MQH
#define SSR_PLATFORM_MQH

#include "SSR_Types.mqh"

//+------------------------------------------------------------------+
//| Waiting.                                                         |
//|                                                                  |
//| Sleep() is forbidden in indicators - they run on the interface   |
//| thread and blocking it freezes the terminal. The data layer is   |
//| shared between a Service (where waiting is correct) and a panel  |
//| indicator (where it is not), so every wait goes through here and |
//| becomes a no-op in the one context that must never block.        |
//+------------------------------------------------------------------+
bool SSRCanBlock(void)
  {
   return (MQLInfoInteger(MQL_PROGRAM_TYPE) != PROGRAM_INDICATOR);
  }

void SSRPause(const int ms)
  {
   if(!SSRCanBlock())
      return;
   Sleep(ms);
  }

//--- monotonic microseconds; wraps only after ~584,000 years
ulong SSRMicros(void) { return GetMicrosecondCount(); }
double SSRElapsedMs(const ulong t0) { return (double)(GetMicrosecondCount() - t0) / 1000.0; }

//--- memory, in megabytes
long SSRMemMql(void)      { return MQLInfoInteger(MQL_MEMORY_USED); }
long SSRMemTerminal(void) { return TerminalInfoInteger(TERMINAL_MEMORY_USED); }

//--- the terminal's own ceiling on how much history a chart may hold.
//--- Phase 6 quotes this to the user before a deep seed.
long SSRMaxBarsInChart(void) { return TerminalInfoInteger(TERMINAL_MAXBARS); }

#endif // SSR_PLATFORM_MQH
//+------------------------------------------------------------------+
