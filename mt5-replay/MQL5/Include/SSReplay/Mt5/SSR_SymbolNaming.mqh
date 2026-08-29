//+------------------------------------------------------------------+
//|                                             SSR_SymbolNaming.mqh |
//|                     SS Replay - Replay Symbol Naming (L0/MT5)    |
//|                                                                  |
//|  MetaTrader caps symbol names, and a truncated name that happens |
//|  to collide with another replay symbol would have two sessions   |
//|  writing into the same history. The suffix is therefore never    |
//|  the part that gets cut - the origin name is.                    |
//|                                                                  |
//|  Phase 0 spike A1 measures the real cap on the target build.     |
//|  Until that number exists, 31 is used and every name is verified |
//|  against the limit rather than assumed to fit.                   |
//+------------------------------------------------------------------+
#ifndef SSR_SYMBOL_NAMING_MQH
#define SSR_SYMBOL_NAMING_MQH

#include "../Common/SSR_Types.mqh"

//--- conservative until spike A1 reports the measured value
#define SSR_SYMBOL_NAME_MAX   31
#define SSR_SYMBOL_PATH       "SSReplay"
#define SSR_SYMBOL_SUFFIX     ".SSR"

//+------------------------------------------------------------------+
//| Build the replay symbol name for (origin, slot).                 |
//|                                                                  |
//| "US30Cash" slot 1  ->  "US30Cash.SSR1"                           |
//| A very long origin loses its TAIL, not the suffix, so the        |
//| result is always recognisable as a replay symbol.                |
//+------------------------------------------------------------------+
string SSRReplaySymbolName(const string origin, const int slot)
  {
   string suffix = SSR_SYMBOL_SUFFIX + IntegerToString(slot);
   int    room   = SSR_SYMBOL_NAME_MAX - StringLen(suffix);
   if(room < 1)
      return suffix;                       // pathological slot number

   string head = origin;
   if(StringLen(head) > room)
      head = StringSubstr(head, 0, room);
   return head + suffix;
  }

//--- is this name one of ours? used by cleanup and by the leak guard
bool SSRIsReplaySymbol(const string name)
  {
   return (StringFind(name, SSR_SYMBOL_SUFFIX) >= 0);
  }

//--- the Market Watch group replay symbols live in
string SSRReplaySymbolPath(void) { return SSR_SYMBOL_PATH; }

//--- would this name be accepted at all?
bool SSRIsNameUsable(const string name)
  {
   int n = StringLen(name);
   return (n > 0 && n <= SSR_SYMBOL_NAME_MAX);
  }

#endif // SSR_SYMBOL_NAMING_MQH
//+------------------------------------------------------------------+
