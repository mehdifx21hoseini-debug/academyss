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

#define SSR_MSC_PER_SEC     1000
#define SSR_MSC_PER_MIN     60000
#define SSR_MSC_PER_HOUR    3600000
#define SSR_MSC_PER_DAY     86400000
#define SSR_INVALID_TIME    (-1)
#define SSR_VERSION         "0.1.0"

//--- THE BUILD STAMP. Printed by the preflight and by the host on
//--- startup, for one reason: when a compile reports errors that were
//--- fixed two rounds ago, the only useful question is which copy of
//--- the source the terminal actually has. This answers it in one line
//--- instead of a conversation.
#define SSR_BUILD           "v8  2026-08-29  leftover-adopt"

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
   SSR_SPEED_50  = 5000
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
   double v = SSRSpeedToDouble(speed_x100);
   if(v == MathFloor(v))
      return StringFormat("%dx", (int)v);
   return StringFormat("%.2gx", v);
  }

//--- the speed ladder the UI steps through (Phase 5 consumes this)
long SSRSpeedLadder(const int index)
  {
   switch(index)
     {
      case 0: return SSR_SPEED_025;
      case 1: return SSR_SPEED_050;
      case 2: return SSR_SPEED_1;
      case 3: return SSR_SPEED_2;
      case 4: return SSR_SPEED_5;
      case 5: return SSR_SPEED_10;
      case 6: return SSR_SPEED_25;
      case 7: return SSR_SPEED_50;
     }
   return SSR_SPEED_1;
  }
#define SSR_SPEED_LADDER_SIZE 8

int SSRSpeedLadderIndex(const long speed_x100)
  {
   for(int i = 0; i < SSR_SPEED_LADDER_SIZE; i++)
      if(SSRSpeedLadder(i) == speed_x100)
         return i;
   return 2;   // 1x
  }

#endif // SSR_TYPES_MQH
//+------------------------------------------------------------------+
