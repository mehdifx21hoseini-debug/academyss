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

   //--- how many charts the user has scrolled away from the live edge.
   //--- FOLLOW is a one-shot that brings them back, not a toggle, so the
   //--- button has to show the number it would act on - otherwise
   //--- pressing it with nothing detached looks like a dead key.
   int                charts_detached;
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
   double             tp_points;       // 0 when no target is set
   string             trade_symbol;    // which instrument they act on
   bool               can_trade;

   //--- one line per strategy, already formatted. Empty when none.
   string             strategy_text;

   //--- what the next trade will be labelled, and the trailing distance
   //--- in points. Both live here so the panel shows what IS, rather
   //--- than what it last sent.
   string             trade_tag;
   double             trail_points;

   //+------------------------------------------------------------------+
   //| THE THIRD LINE, AND WHAT IT MAKES THE BUTTON DO.                 |
   //|                                                                  |
   //| With no entry line the button opens at market. With one, it       |
   //| places a pending - and `order_name` is what KIND, worked out from |
   //| the geometry down in the port rather than picked from a list up   |
   //| here. Empty when the three lines do not describe a legal order,   |
   //| with `order_why` saying which way to drag.                        |
   //+------------------------------------------------------------------+
   bool               entry_armed;
   double             entry_price;
   string             order_name;
   string             order_why;
   int                pending_count;

   //+------------------------------------------------------------------+
   //| THE EVALUATION, already decided elsewhere.                       |
   //|                                                                  |
   //| The panel gets a state, a headline and a progress fraction - not |
   //| the rules and the equity to compare for itself. A second place   |
   //| that knows what a daily loss limit means is a second place that  |
   //| can disagree with the first about whether you failed.            |
   //+------------------------------------------------------------------+
   bool               prop_on;
   int                prop_state;      // ENUM_SSR_PROP_STATE
   string             prop_state_name;
   string             prop_headline;
   string             prop_rules;
   double             prop_progress;   // 0..1 toward the profit target
   double             prop_floor;      // the equity level that ends the run
   int                prop_days;

   //--- THE OPEN POSITIONS, as rows the panel can show and act on.
   //--- Five is a display cap, not a trading cap: pos_rows says how
   //--- many are shown, open_positions how many exist, and when they
   //--- differ the panel says "+N more" instead of lying by omission.
   int                pos_rows;
   long               pos_ticket[5];
   string             pos_text[5];     // "BUY 1.00 @ 53513"
   double             pos_pl[5];
   //--- a row that has not filled yet. Half, break-even and a running
   //--- P/L all mean nothing on one, and offering them would be
   //--- offering three buttons that answer "refused".
   bool               pos_pending[5];

   //+------------------------------------------------------------------+
   //| THE STOP AND TARGET ARE LINES, NOT NUMBERS.                      |
   //|                                                                  |
   //| The panel used to carry two steppers in points. A stop typed in  |
   //| points is a stop chosen by arithmetic; a stop dragged on the     |
   //| chart is a stop chosen by structure, which is the whole reason   |
   //| a person practises on a replay. So the panel now shows what the  |
   //| LINES say and the mouse is what sets them.                       |
   //|                                                                  |
   //| line_long is read from geometry, not asked of the user: stop     |
   //| below price and target above means long. That is one fewer       |
   //| decision to make in a dialog, and it cannot disagree with what   |
   //| is drawn on the chart.                                           |
   //+------------------------------------------------------------------+
   bool               lines_armed;
   double             sl_price;
   double             tp_price;
   bool               line_long;      // meaningless while !lines_armed
   double             bid, ask;
   int                price_digits;
   double             spread_points;
   double             lot_from_risk;  // what Buy/Sell would send
   double             risk_money;     // ...and what it puts at stake
   double             reward_money;   // ...against what it plays for
   double             rr;             // reward : risk, 0 when unknown

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
      charts_detached = 0;
      clock_text = "--"; blind = false;
      trade_tag = ""; trail_points = 0.0;
      entry_armed = false; entry_price = 0.0;
      order_name = ""; order_why = ""; pending_count = 0;
      prop_on = false; prop_state = 0; prop_state_name = ""; prop_headline = "";
      prop_rules = ""; prop_progress = 0.0; prop_floor = 0.0; prop_days = 0;
      balance = 0.0; equity = 0.0; floating = 0.0;
      open_positions = 0; risk_percent = 0.0; stop_points = 0.0;
      trade_symbol = ""; can_trade = false; tp_points = 0.0;
      strategy_text = "";
      pos_rows = 0;
      for(int pi = 0; pi < 5; pi++)
        { pos_ticket[pi] = 0; pos_text[pi] = ""; pos_pl[pi] = 0.0;
          pos_pending[pi] = false; }
      for(int i = 0; i < 5; i++)
        { pos_ticket[i] = 0; pos_text[i] = ""; pos_pl[i] = 0.0; }
      lines_armed = false; sl_price = 0.0; tp_price = 0.0; line_long = true;
      bid = 0.0; ask = 0.0; price_digits = 2; spread_points = 0.0;
      lot_from_risk = 0.0; risk_money = 0.0; reward_money = 0.0; rr = 0.0;
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

   //--- the stop and target as LINES. ArmLines puts them on the chart
   //--- at a sane default; after that the mouse owns them and the port
   //--- only reports where they ended up.
   virtual bool      ArmLines(void)                      { return false; }
   virtual bool      ClearLines(void)                    { return false; }
   virtual bool      FlipLines(void)                     { return false; }

   //--- open the trade the LINES describe: side, stop and target all
   //--- come from where they were dragged to. The panel never decides
   //--- the direction, so the chart and the order cannot disagree.
   virtual bool      OpenFromLines(void)                  { return false; }

   //--- close ONE position, by the ticket the state row named
   virtual bool      ClosePosition(const long ticket)     { return false; }

   //+------------------------------------------------------------------+
   //| MANAGING A TRADE, not only opening and closing one.              |
   //|                                                                  |
   //| All three already worked in the engine and had no button. A tool |
   //| that can only open and close models the five seconds a trader    |
   //| spends entering and none of the hour they spend managing - which |
   //| is where the skill being practised actually lives.                |
   //+------------------------------------------------------------------+
   virtual bool      ClosePartial(const long ticket, const double fraction)
                                                          { return false; }
   virtual bool      BreakEven(const long ticket)         { return false; }
   virtual bool      SetTrailing(const double points)     { return false; }

   //--- the label the next trade will carry. The engine has stored a
   //--- tag per position since Phase 9; nothing has ever set it.
   virtual bool      SetTradeTag(const string tag)        { return false; }

   //--- add or remove the entry line, which is what turns the button
   //--- from "open at market" into "place an order"
   virtual bool      ToggleEntryLine(void)                { return false; }

   //--- write the session out as a statement a person can read. Returns
   //--- the path in `path_out` so the panel can show WHERE it went; a
   //--- file written somewhere unstated is a file the user cannot find.
   virtual bool      ExportStatement(string &path_out)     { path_out = ""; return false; }

   //--- restart the evaluation on the same rules. Separate from the
   //--- replay's own Reset, because a user who voids a run by rewinding
   //--- wants the evaluation back, not the whole session rebuilt.
   virtual bool      ResetEvaluation(void)                 { return false; }
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
