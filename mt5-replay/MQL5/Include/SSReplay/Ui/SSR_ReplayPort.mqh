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
   int                bookmarks;
   bool               has_saved_position;
   int                checkpoints;
   bool               leak_clean;
   string             leak_advice;
   ENUM_SSR_ERR       last_error;
   string             last_error_text;

   //--- Phase 11. The panel shows WHY the replay stopped, because a
   //--- tool that pauses itself and says nothing is indistinguishable
   //--- from one that froze.
   string             pause_reason;
   int                streams;         // 1 for a single instrument
   long               skew_msc;        // between streams; must be 0

   //--- Phase 15. THE PANEL NEVER FORMATS THE CLOCK ITSELF any more.
   //--- Blind Mode has to reach the text, and a panel deciding what
   //--- may be shown would be a second place that has to know about
   //--- blind mode - and the one that gets forgotten.
   string             clock_text;      // masked already, if blind
   bool               blind;           // so the user can see they are

   //--- the virtual account, for the trade row
   double             balance;
   double             equity;
   double             floating;
   int                open_positions;
   double             risk_percent;    // what the trade buttons will risk
   double             stop_points;     // and the stop they size against
   string             trade_symbol;    // which instrument they act on
   bool               can_trade;

   //--- one line per strategy, already formatted. Empty when none.
   string             strategy_text;

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
      bookmarks = 0; has_saved_position = false; checkpoints = 0;
      leak_clean = true; leak_advice = "";
      last_error = SSR_OK; last_error_text = "";
      pause_reason = ""; streams = 1; skew_msc = 0;
      clock_text = "--"; blind = false;
      balance = 0.0; equity = 0.0; floating = 0.0;
      open_positions = 0; risk_percent = 0.0; stop_points = 0.0;
      trade_symbol = ""; can_trade = false;
      strategy_text = "";
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
   virtual bool      StepBack(const int bars) = 0;
   virtual bool      JumpTo(const long msc) = 0;
   virtual bool      Restart(void) = 0;
   virtual bool      Bookmark(const string label) { return false; }
   virtual bool      SavePosition(void)           { return false; }
   virtual bool      ResumePosition(void)         { return false; }
   virtual bool      SeekTo(const long msc) = 0;
   virtual bool      SetSpeedX100(const long speed) = 0;
   virtual bool      SetFidelity(const ENUM_SSR_FIDELITY f) = 0;

   //--- chart-side verbs the panel offers but does not implement
   virtual bool      FollowCharts(void)  { return false; }
   virtual bool      HideOriginSymbol(void) { return false; }

   //+------------------------------------------------------------------+
   //| TRADING, added in Phase 15.                                      |
   //|                                                                  |
   //| Every one defaults to refusing. A port that cannot trade says so |
   //| by inheriting these, and the panel greys the buttons out from    |
   //| can_trade rather than from knowing which port it is talking to.  |
   //|                                                                  |
   //| Nothing here reaches a broker. It cannot: the only implementation|
   //| routes into the virtual account, and there is no OrderSend below |
   //| any of it.                                                       |
   //+------------------------------------------------------------------+
   virtual bool      Buy(void)                          { return false; }
   virtual bool      Sell(void)                         { return false; }
   virtual bool      CloseAll(void)                     { return false; }
   virtual bool      BreakEvenAll(void)                 { return false; }
   virtual bool      SetRiskPercent(const double pct)   { return false; }
   virtual bool      SetStopPoints(const double pts)    { return false; }
   virtual string    TradeError(void)                   { return ""; }

   //+------------------------------------------------------------------+
   //| SESSIONS, added in Phase 15.                                     |
   //|                                                                  |
   //| Listing is separate from loading on purpose: the user picks from |
   //| what exists rather than typing a name and finding out.           |
   //+------------------------------------------------------------------+
   virtual int       SessionCount(void)                 { return 0; }
   virtual string    SessionName(const int i)           { return ""; }
   virtual string    SessionSummary(const int i)        { return ""; }
   virtual bool      SaveSession(const string name)     { return false; }
   virtual bool      LoadSession(const string name)     { return false; }
   virtual string    SessionError(void)                 { return ""; }
  };

#endif // SSR_REPLAY_PORT_MQH
//+------------------------------------------------------------------+
