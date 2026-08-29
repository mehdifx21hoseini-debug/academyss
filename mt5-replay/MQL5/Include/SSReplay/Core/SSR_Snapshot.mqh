//+------------------------------------------------------------------+
//|                                                  SSR_Snapshot.mqh |
//|                              SS Replay - Snapshot / State Model  |
//|                                                                  |
//|  A complete, restorable picture of the engine at one instant.    |
//|                                                                  |
//|  Rewind (Phase 8) and Save/Resume Session (Phase 12) both rest   |
//|  on this. Deliberately plain data with no pointers, so a         |
//|  snapshot can be copied, written to a file and restored into a   |
//|  freshly constructed engine with no hidden coupling.             |
//|                                                                  |
//|  The trading and statistics slots are reserved but NOT filled in |
//|  this phase - Phase 9 and 10 own them. They are named here so    |
//|  the file format does not have to change shape later.            |
//+------------------------------------------------------------------+
#ifndef SSR_SNAPSHOT_MQH
#define SSR_SNAPSHOT_MQH

#include "../Common/SSR_Types.mqh"
#include "../Common/SSR_Time.mqh"
#include "SSR_ReplayState.mqh"
#include "SSR_ReplayClock.mqh"
#include "SSR_ReplayCursor.mqh"
#include "SSR_ReplayTimeline.mqh"

//+------------------------------------------------------------------+
struct SSRSnapshot
  {
   //--- identity of the snapshot itself
   string             version;
   long               taken_at_msc;    // replay time when taken
   string             label;

   //--- the engine
   SSRReplayState     state;
   SSRReplayClock     clock;
   SSRReplayCursor    cursor;
   SSRReplayTimeline  timeline;

   //--- reserved, owned by later phases
   int                open_positions;   // Phase 9
   int                closed_trades;    // Phase 9
   double             virtual_balance;  // Phase 9
   double             virtual_equity;   // Phase 9

   void               Init(void)
     {
      version         = SSR_VERSION;
      taken_at_msc    = SSR_INVALID_TIME;
      label           = "";
      state.Init();
      clock.Init();
      cursor.Init();
      timeline.Init();
      open_positions  = 0;
      closed_trades   = 0;
      virtual_balance = 0.0;
      virtual_equity  = 0.0;
     }

   bool               IsValid(void)
     {
      return (taken_at_msc > 0 && state.symbol != "" && clock.IsConfigured());
     }

   string             ToString(void)
     {
      return StringFormat("snapshot[%s @ %s | %s | %s]",
                          (label == "" ? "unnamed" : label),
                          SSRFormatMsc(taken_at_msc),
                          state.symbol,
                          SSRStateName(state.status));
     }
  };

#endif // SSR_SNAPSHOT_MQH
//+------------------------------------------------------------------+
