//+------------------------------------------------------------------+
//|                                               SSR_ReplayPort.mqh |
//|                     SS Replay - UI to Engine Boundary (UI)       |
//|                                                                  |
//|  "The UI must contain no core logic" is easy to say and easy to  |
//|  erode. This file makes it structural: the panel can only reach  |
//|  the engine through a port that offers verbs and one flat state  |
//|  struct. It cannot read the clock, walk the timeline, or decide  |
//|  what a state transition means, because none of that is exposed. |
//|                                                                  |
//|  Two implementations, one interface:                             |
//|    Direct  - the engine is in this program (today)               |
//|    Ipc     - the engine is in a Service (when IPC lands)         |
//|  The panel cannot tell the difference, which is the point.       |
//+------------------------------------------------------------------+
#ifndef SSR_REPLAY_PORT_MQH
#define SSR_REPLAY_PORT_MQH

#include "../Common/SSR_Types.mqh"
#include "../Common/SSR_Time.mqh"

//+------------------------------------------------------------------+
//| Everything the panel is allowed to know, flattened.              |
//|                                                                  |
//| Flat and pointer-free on purpose: an IPC port fills this from    |
//| numbers on a wire, so anything that cannot survive that trip has |
//| no business being here.                                          |
//+------------------------------------------------------------------+
struct SSRUiState
  {
   bool               connected;
   string             symbol;          // the replay symbol, as shown
   ENUM_SSR_STATE     status;
   long               now_msc;
   long               start_msc;
   long               end_msc;
   double             progress;        // 0..1
   long               speed_x100;
   ENUM_SSR_FIDELITY  fidelity;            // what the user asked for
   ENUM_SSR_FIDELITY  fidelity_effective;  // what is actually running
   string             fidelity_note;       // why they differ, if they do
   bool               perf_calibrated;
   double             us_per_tick;
   double             pump_p95_ms;
   ENUM_SSR_DATA_MODE data_mode;
   long               ticks_emitted;
   long               bars_consumed;
   long               ticks_rejected;  // closes Phase 3 TODO T14
   long               guard_violations;
   bool               leak_clean;
   string             leak_advice;
   ENUM_SSR_ERR       last_error;
   string             last_error_text;

   void               Init(void)
     {
      connected = false; symbol = ""; status = SSR_STATE_IDLE;
      now_msc = SSR_INVALID_TIME; start_msc = SSR_INVALID_TIME;
      end_msc = SSR_INVALID_TIME; progress = 0.0;
      speed_x100 = SSR_SPEED_1;
      fidelity           = SSR_FIDELITY_SYNTHETIC_TICK;
      fidelity_effective = SSR_FIDELITY_SYNTHETIC_TICK;
      fidelity_note      = "";
      perf_calibrated    = false;
      us_per_tick        = 0.0;
      pump_p95_ms        = 0.0;
      data_mode = SSR_DATA_MEMORY;
      ticks_emitted = 0; bars_consumed = 0; ticks_rejected = 0;
      guard_violations = 0;
      leak_clean = true; leak_advice = "";
      last_error = SSR_OK; last_error_text = "";
     }

   bool               IsRunning(void)  { return (status == SSR_STATE_PLAYING); }
   bool               CanPlay(void)
     {
      return (status == SSR_STATE_READY || status == SSR_STATE_PAUSED);
     }
   bool               CanStep(void)
     {
      return (status == SSR_STATE_READY || status == SSR_STATE_PAUSED ||
              status == SSR_STATE_PLAYING);
     }
  };

//+------------------------------------------------------------------+
//| The verbs. Nothing here returns engine internals.                |
//+------------------------------------------------------------------+
class CSSRReplayPort
  {
public:
   virtual          ~CSSRReplayPort(void) {}

   virtual string    Name(void) = 0;
   virtual bool      IsConnected(void) = 0;

   //--- one call per frame; the panel renders whatever comes back
   virtual bool      ReadState(SSRUiState &out) = 0;

   virtual bool      Play(void) = 0;
   virtual bool      Pause(void) = 0;
   virtual bool      Reset(void) = 0;
   virtual bool      StepBars(const int bars) = 0;
   virtual bool      SeekTo(const long msc) = 0;
   virtual bool      SetSpeedX100(const long speed) = 0;
   virtual bool      SetFidelity(const ENUM_SSR_FIDELITY f) = 0;

   //--- chart-side verbs the panel offers but does not implement
   virtual bool      FollowCharts(void)  { return false; }
   virtual bool      HideOriginSymbol(void) { return false; }
  };

#endif // SSR_REPLAY_PORT_MQH
//+------------------------------------------------------------------+
