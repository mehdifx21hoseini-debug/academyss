//+------------------------------------------------------------------+
//|                                             SSR_SymbolNaming.mqh |
//|                        SS Replay - Replay Symbol Naming (L0)     |
//|                                                                  |
//|  MetaTrader caps symbol names, and a truncated name that happens |
//|  to collide with another replay symbol would have two sessions   |
//|  writing into the same history. The suffix is therefore never    |
//|  the part that gets cut - the origin name is.                    |
//|                                                                  |
//|  Pure string logic - no MetaTrader API - so it lives in Common   |
//|  rather than the MT5 layer. That keeps the Chart layer from       |
//|  depending sideways on the adapter just to recognise a name.      |
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

//+------------------------------------------------------------------+
//| The same thing, with the instrument's identity removed.          |
//|                                                                  |
//| For Blind Mode. MetaTrader prints the symbol name in the chart   |
//| caption and there is no property that hides it, so the only way  |
//| the name stops giving the game away is for it not to be there in |
//| the first place.                                                 |
//|                                                                  |
//| It still ends in the replay suffix, so cleanup and the leak      |
//| guard recognise it exactly as before. Anonymous to the trader,   |
//| not to the tool.                                                 |
//+------------------------------------------------------------------+
string SSRAnonSymbolName(const int slot)
  {
   return "Chart" + SSR_SYMBOL_SUFFIX + IntegerToString(slot);
  }

//--- either naming, chosen by the caller rather than by a global
string SSRReplaySymbolNameFor(const string origin, const int slot,
                              const bool anonymous)
  {
   return (anonymous ? SSRAnonSymbolName(slot)
                     : SSRReplaySymbolName(origin, slot));
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
