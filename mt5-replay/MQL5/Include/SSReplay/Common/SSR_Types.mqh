//+------------------------------------------------------------------+
//|                                                    SSR_Types.mqh |
//|                            SS Replay - Common Types & Enums (L0) |
//|                                                                  |
//|  Vocabulary shared by every layer. Depends on nothing.           |
//|                                                                  |
//|  TIME CONVENTION - one rule for the whole product:               |
//|    All internal time is `long` MILLISECONDS since the Unix epoch |
//|    (the same basis as MqlTick.time_msc). datetime appears only   |
//|    at the boundaries, where a human or an MT5 API needs it.      |
//|    Mixing the two silently is the classic source of off-by-one-  |
//|    bar bugs, so the conversion helpers live in SSR_Time.mqh and  |
//|    nothing converts by hand.                                     |
//+------------------------------------------------------------------+
#ifndef SSR_TYPES_MQH
#define SSR_TYPES_MQH

//+------------------------------------------------------------------+
//| CAST TO long AT THE DEFINITION, not at every call site.          |
//|                                                                  |
//| 86400000 fits in an int, so MQL5 typed these as int - and then    |
//| computed `SSR_MSC_PER_DAY * 100` in int arithmetic, overflowed,   |
//| and handed the caller 50065408 with nothing but a warning. The    |
//| smoke test drove a whole prop-firm evaluation off that number.    |
//|                                                                   |
//| Every one of the 154 uses in this tree is long arithmetic or is    |
//| already cast at the point of printing, so the cast costs nothing   |
//| and removes the trap for the next multiplication anybody writes.   |
//+------------------------------------------------------------------+
#define SSR_MSC_PER_SEC     ((long)1000)
#define SSR_MSC_PER_MIN     ((long)60000)
#define SSR_MSC_PER_HOUR    ((long)3600000)
#define SSR_MSC_PER_DAY     ((long)86400000)
#define SSR_INVALID_TIME    (-1)
#define SSR_VERSION         "0.1.0"

//--- THE BUILD STAMP lives in its own header now, so the Phase 0
//--- spike kit can print it too without pulling in this type system.
#include "SSR_Build.mqh"

//+------------------------------------------------------------------+
//| Replay state machine                                             |
//+------------------------------------------------------------------+
enum ENUM_SSR_STATE
  {
   SSR_STATE_IDLE = 0,     // constructed, nothing configured
   SSR_STATE_LOADING,      // discovering / loading data
   SSR_STATE_READY,        // configured and positioned, not advancing
   SSR_STATE_PLAYING,      // advancing on every Pump()
   SSR_STATE_PAUSED,       // positioned, deliberately halted
   SSR_STATE_RESETTING,    // tearing state back to the start
   SSR_STATE_COMPLETED,    // reached the end of the timeline
   SSR_STATE_ERROR         // unrecoverable without an explicit Reset()
  };

//+------------------------------------------------------------------+
//| Fidelity - how a unit of replay time becomes emitted ticks.      |
//| Adaptive switching between these belongs to Phase 7; Phase 1     |
//| only defines and routes them.                                    |
//+------------------------------------------------------------------+
enum ENUM_SSR_FIDELITY
  {
   SSR_FIDELITY_FULL_TICK = 0,   // real broker ticks, one for one
   SSR_FIDELITY_SYNTHETIC_TICK,  // N synthesised ticks per M1 bar
   SSR_FIDELITY_BAR              // one tick at each bar close
  };

//+------------------------------------------------------------------+
//| Where the bytes come from. The engine never branches on this -   |
//| it exists for reporting and for provider selection at wiring     |
//| time, never inside the replay loop.                              |
//+------------------------------------------------------------------+
enum ENUM_SSR_DATA_MODE
  {
   SSR_DATA_MEMORY = 0,    // in-memory dataset (tests, generators)
   SSR_DATA_BROKER,        // MT5 broker history          - Phase 2
   SSR_DATA_CSV,           // imported CSV bars or ticks  - Phase 6
   SSR_DATA_EXTERNAL_TICK  // external tick dataset       - Phase 6
  };

//+------------------------------------------------------------------+
//| Replay speed. The enum VALUE is the speed multiplied by 100, so  |
//| the clock can advance with pure integer arithmetic and stay      |
//| bit-for-bit deterministic. See SSR_ReplayClock.mqh.              |
//+------------------------------------------------------------------+
enum ENUM_SSR_SPEED
  {
   SSR_SPEED_025 = 25,
   SSR_SPEED_050 = 50,
   SSR_SPEED_1   = 100,
   SSR_SPEED_2   = 200,
   SSR_SPEED_5   = 500,
   SSR_SPEED_10  = 1000,
   SSR_SPEED_25  = 2500,
   SSR_SPEED_50  = 5000,
   //--- not a multiplier: "emit as fast as the sink accepts".
   //--- The engine clamps to what it can really do, and the panel
   //--- shows what is running rather than what was asked for.
   SSR_SPEED_MAX = 100000
  };

//+------------------------------------------------------------------+
//| Error codes. MQL5 has no exceptions, so every fallible call      |
//| returns one of these and the caller is expected to check it.     |
//+------------------------------------------------------------------+
enum ENUM_SSR_ERR
  {
   SSR_OK = 0,
   SSR_ERR_INVALID_ARG,
   SSR_ERR_INVALID_STATE,
   SSR_ERR_NO_SOURCE,
   SSR_ERR_NO_SINK,
   SSR_ERR_NO_DATA,
   SSR_ERR_OUT_OF_RANGE,
   SSR_ERR_FUTURE_ACCESS,   // a read was attempted beyond the guard horizon
   SSR_ERR_LOAD_FAILED,
   SSR_ERR_SINK_FAILED,
   SSR_ERR_NOT_SUPPORTED,
   SSR_ERR_INTERNAL
  };

//+------------------------------------------------------------------+
//| Human-readable names. EnumToString would leak the SSR_ prefix    |
//| into user-facing text, so these stay explicit.                   |
//+------------------------------------------------------------------+
string SSRStateName(const ENUM_SSR_STATE s)
  {
   switch(s)
     {
      case SSR_STATE_IDLE:      return "IDLE";
      case SSR_STATE_LOADING:   return "LOADING";
      case SSR_STATE_READY:     return "READY";
      case SSR_STATE_PLAYING:   return "PLAYING";
      case SSR_STATE_PAUSED:    return "PAUSED";
      case SSR_STATE_RESETTING: return "RESETTING";
      case SSR_STATE_COMPLETED: return "COMPLETED";
      case SSR_STATE_ERROR:     return "ERROR";
     }
   return "UNKNOWN";
  }

string SSRFidelityName(const ENUM_SSR_FIDELITY f)
  {
   switch(f)
     {
      case SSR_FIDELITY_FULL_TICK:      return "FULL TICK";
      case SSR_FIDELITY_SYNTHETIC_TICK: return "SYNTHETIC TICK";
      case SSR_FIDELITY_BAR:            return "BAR";
     }
   return "UNKNOWN";
  }

string SSRDataModeName(const ENUM_SSR_DATA_MODE m)
  {
   switch(m)
     {
      case SSR_DATA_MEMORY:        return "MEMORY";
      case SSR_DATA_BROKER:        return "BROKER";
      case SSR_DATA_CSV:           return "CSV";
      case SSR_DATA_EXTERNAL_TICK: return "EXTERNAL TICK";
     }
   return "UNKNOWN";
  }

string SSRErrName(const ENUM_SSR_ERR e)
  {
   switch(e)
     {
      case SSR_OK:                 return "OK";
      case SSR_ERR_INVALID_ARG:    return "INVALID_ARG";
      case SSR_ERR_INVALID_STATE:  return "INVALID_STATE";
      case SSR_ERR_NO_SOURCE:      return "NO_SOURCE";
      case SSR_ERR_NO_SINK:        return "NO_SINK";
      case SSR_ERR_NO_DATA:        return "NO_DATA";
      case SSR_ERR_OUT_OF_RANGE:   return "OUT_OF_RANGE";
      case SSR_ERR_FUTURE_ACCESS:  return "FUTURE_ACCESS";
      case SSR_ERR_LOAD_FAILED:    return "LOAD_FAILED";
      case SSR_ERR_SINK_FAILED:    return "SINK_FAILED";
      case SSR_ERR_NOT_SUPPORTED:  return "NOT_SUPPORTED";
      case SSR_ERR_INTERNAL:       return "INTERNAL";
     }
   return "UNKNOWN";
  }

//--- speed helpers -------------------------------------------------
double SSRSpeedToDouble(const long speed_x100) { return (double)speed_x100 / 100.0; }

string SSRSpeedName(const long speed_x100)
  {
   if(speed_x100 >= SSR_SPEED_MAX)
      return "MAX";
   double v = SSRSpeedToDouble(speed_x100);
   if(v == MathFloor(v))
      return StringFormat("%dx", (int)v);
   //--- %.2g turned 0.25 into "0.25" but 0.1 into "0.1" and 0.75 into
   //--- "0.75" only by luck of the exponent. Two decimals, trimmed,
   //--- is the same answer without depending on that luck.
   string t = StringFormat("%.2f", v);
   while(StringLen(t) > 1 && StringSubstr(t, StringLen(t) - 1) == "0")
      t = StringSubstr(t, 0, StringLen(t) - 1);
   if(StringSubstr(t, StringLen(t) - 1) == ".")
      t = StringSubstr(t, 0, StringLen(t) - 1);
   return t + "x";
  }

//+------------------------------------------------------------------+
//| THE SPEED LADDER.                                                |
//|                                                                  |
//| Twenty stops, not eight, because the panel now has a trackbar    |
//| you drag with the mouse and eight stops on a 250-pixel bar makes |
//| dragging feel like flicking a switch.                            |
//|                                                                  |
//| The stops are spaced EVENLY on the bar, and the values grow      |
//| geometrically - so the bar is a logarithmic scale in speed. That |
//| is the only scale that works here: on a linear bar from 0.1x to  |
//| 200x, everything below 10x lives in the first 5% of the travel   |
//| and cannot be picked. 1x -> 2x has to cost the same travel as    |
//| 25x -> 50x, because that is what it costs in perception.         |
//|                                                                  |
//| Every stop is a number a person can say out loud. Dragging feels |
//| continuous because consecutive stops are close in perception,    |
//| not because the value became a float nobody chose.               |
//+------------------------------------------------------------------+
long SSRSpeedLadder(const int index)
  {
   switch(index)
     {
      case  0: return   10;   // 0.1x
      case  1: return   25;   // 0.25x
      case  2: return   50;   // 0.5x
      case  3: return   75;   // 0.75x
      case  4: return  100;   // 1x
      case  5: return  150;
      case  6: return  200;
      case  7: return  300;
      case  8: return  400;
      case  9: return  500;
      case 10: return  700;
      case 11: return 1000;   // 10x
      case 12: return 1500;
      case 13: return 2000;
      case 14: return 3000;
      case 15: return 5000;   // 50x
      case 16: return 7500;
      case 17: return 10000;  // 100x
      case 18: return 20000;  // 200x
      case 19: return SSR_SPEED_MAX;
     }
   return SSR_SPEED_1;
  }
#define SSR_SPEED_LADDER_SIZE 20
#define SSR_SPEED_DEFAULT_IX  4      /* 1x */

//+------------------------------------------------------------------+
//| Where on the ladder is this speed?                               |
//|                                                                  |
//| NEAREST, not exact. The old version returned 1x for anything it  |
//| did not recognise, so a session restored at 3x would jump to 1x  |
//| the first time the user pressed "+". A speed that is off-ladder  |
//| is still SOMEWHERE on it, and the honest answer is the closest   |
//| stop rather than a default that silently discards the value.     |
//+------------------------------------------------------------------+
int SSRSpeedLadderIndex(const long speed_x100)
  {
   int  best = SSR_SPEED_DEFAULT_IX;
   long gap  = -1;
   for(int i = 0; i < SSR_SPEED_LADDER_SIZE; i++)
     {
      long d = SSRSpeedLadder(i) - speed_x100;
      if(d < 0) d = -d;
      if(gap < 0 || d < gap)
        { gap = d; best = i; }
     }
   return best;
  }

//--- 0..1 along the bar, for the trackbar to place its thumb
double SSRSpeedFraction(const long speed_x100)
  {
   return (double)SSRSpeedLadderIndex(speed_x100) /
          (double)(SSR_SPEED_LADDER_SIZE - 1);
  }

//--- and back again, for a click or a drag at fraction f
long SSRSpeedAtFraction(const double f)
  {
   double c = f;
   if(c < 0.0) c = 0.0;
   if(c > 1.0) c = 1.0;
   return SSRSpeedLadder((int)MathRound(c * (SSR_SPEED_LADDER_SIZE - 1)));
  }

//+------------------------------------------------------------------+
//| What the speed MEANS, in the only unit that helps a decision.    |
//|                                                                  |
//| "5x" is a number. "1h in 12m" is something you can plan an       |
//| afternoon around.                                                |
//+------------------------------------------------------------------+
string SSRSpeedMeaning(const long speed_x100)
  {
   if(speed_x100 >= SSR_SPEED_MAX)
      return "as fast as ticks feed";
   double v = SSRSpeedToDouble(speed_x100);
   if(v <= 0.0)
      return "";
   double sec = 3600.0 / v;
   if(sec >= 5400.0)
      return StringFormat("1h in %.1fh", sec / 3600.0);
   if(sec >= 90.0)
      return StringFormat("1h in %dm", (int)MathRound(sec / 60.0));
   return StringFormat("1h in %ds", (int)MathRound(sec));
  }

#endif // SSR_TYPES_MQH
//+------------------------------------------------------------------+
