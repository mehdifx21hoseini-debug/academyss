//+------------------------------------------------------------------+
//|                                              SSR_Contract.mqh    |
//|              SS Replay - The Public Integration Contract         |
//|                                                                  |
//|  THIS FILE IS SELF-CONTAINED ON PURPOSE.                         |
//|                                                                  |
//|  It includes nothing. A third-party product - SSProX or anything |
//|  else - copies this file and SSR_Client.mqh, and is integrated.  |
//|  If it had to include the replay tool's headers, that product    |
//|  would not compile on a machine where the replay tool is not     |
//|  installed, and the coupling would run the wrong way.            |
//|                                                                  |
//|  THE WIRE NUMBERS ARE NOT THE INTERNAL ENUMS.                    |
//|                                                                  |
//|  They look the same today and that is a coincidence. Internal    |
//|  enums get a value inserted in the middle one day; if the wire   |
//|  read them directly, every installed copy of the other product   |
//|  would silently start reading "paused" as "resetting". So the    |
//|  numbers below are FROZEN, and the publisher maps onto them.     |
//|  The mapping is the boundary.                                    |
//|                                                                  |
//|  WHAT THIS CONTRACT DELIBERATELY CANNOT EXPRESS                  |
//|                                                                  |
//|   - any request for data at a time. There is no "give me the bar |
//|     at T" verb, because a client that could ask for one could    |
//|     ask for a future one. A client wanting prices reads the      |
//|     chart, which holds only what has been replayed.              |
//|   - any order that reaches a broker. The trade verbs land in the |
//|     virtual account and there is no path from there outward.     |
//|   - anything at all, unless the replay side granted it. Every    |
//|     verb is checked against a permission mask the REPLAY side    |
//|     sets, not the client.                                        |
//+------------------------------------------------------------------+
#ifndef SSR_CONTRACT_MQH
#define SSR_CONTRACT_MQH

//--- Contract version. Bumped only when the LAYOUT changes, never
//--- when the product does, so an integration does not break because
//--- somebody fixed a chart bug.
#define SSR_CONTRACT_VERSION   1

//--- Transport: terminal global variables, which are doubles and are
//--- shared across every program in the terminal. Chosen over files
//--- because a client may read them on every tick with no I/O, and
//--- over custom events because those only reach one chart.
//---
//--- Namespaced by SLOT, so two replay sessions cannot overwrite each
//--- other's state - which is exactly what would happen with one flat
//--- set of names, and would look like the replay jumping about.
#define SSR_GV_PREFIX          "SSR."

//--- how long a heartbeat may go unrefreshed before the session is
//--- considered gone. Terminal globals OUTLIVE the program that set
//--- them, so without this a client would believe a crashed replay
//--- was still running for as long as the terminal stayed open.
#define SSR_HEARTBEAT_STALE_MS 5000

//+------------------------------------------------------------------+
//| Wire states. FROZEN NUMBERS.                                     |
//+------------------------------------------------------------------+
#define SSR_W_STATE_IDLE       0
#define SSR_W_STATE_LOADING    1
#define SSR_W_STATE_READY      2
#define SSR_W_STATE_PLAYING    3
#define SSR_W_STATE_PAUSED     4
#define SSR_W_STATE_RESETTING  5
#define SSR_W_STATE_COMPLETED  6
#define SSR_W_STATE_ERROR      7

//--- Wire fidelity. FROZEN NUMBERS.
#define SSR_W_FID_REAL_TICK    0
#define SSR_W_FID_SYNTHETIC    1
#define SSR_W_FID_BAR          2

//+------------------------------------------------------------------+
//| Permissions, set by the REPLAY side. A client cannot widen them. |
//|                                                                  |
//| Read is always granted; the other two are off unless the person  |
//| running the replay turned them on. "Another program can place    |
//| trades in my account" is not a default.                          |
//+------------------------------------------------------------------+
#define SSR_PERM_READ          0x01
#define SSR_PERM_CONTROL       0x02   // play, pause, step, jump, speed
#define SSR_PERM_TRADE         0x04   // virtual trades only, always

//+------------------------------------------------------------------+
//| Commands. FROZEN NUMBERS.                                        |
//|                                                                  |
//| Note what is absent: nothing reads data, nothing names a symbol, |
//| nothing reaches a broker.                                        |
//+------------------------------------------------------------------+
#define SSR_CMD_NONE           0
#define SSR_CMD_PLAY           1
#define SSR_CMD_PAUSE          2
#define SSR_CMD_STEP           3    // a1 = bars forward
#define SSR_CMD_STEP_BACK      4    // a1 = bars back
#define SSR_CMD_SPEED          5    // a1 = speed x100
#define SSR_CMD_JUMP           6    // a1 = target, epoch milliseconds
#define SSR_CMD_BUY            7    // a1 = volume, a2 = sl, a3 = tp
#define SSR_CMD_SELL           8    // a1 = volume, a2 = sl, a3 = tp
#define SSR_CMD_CLOSE_ALL      9
//--- a1 = RISK PERCENT, not a volume. a2 = stop. a3 = target.
//--- Sized by the replay's own risk engine, so a product integrating
//--- here cannot arrive at a different lot size than the panel would
//--- for the same risk - which is the kind of disagreement nobody
//--- notices until the results are compared.
#define SSR_CMD_BUY_RISK      10
#define SSR_CMD_SELL_RISK     11

//--- Result codes. FROZEN NUMBERS.
#define SSR_RC_OK              0
#define SSR_RC_UNKNOWN_CMD    -1
#define SSR_RC_NOT_PERMITTED  -2
#define SSR_RC_REFUSED        -3    // the engine said no; a1 says nothing more
#define SSR_RC_NO_SESSION     -4

//+------------------------------------------------------------------+
//| Global variable names for one slot.                              |
//|                                                                  |
//| Built by a function rather than written out, so the client and    |
//| the publisher cannot disagree about a name - which is a bug that  |
//| shows up as "the integration silently does nothing".              |
//+------------------------------------------------------------------+
string SSRGvName(const int slot, const string field)
  {
   return SSR_GV_PREFIX + IntegerToString(slot) + "." + field;
  }

//--- the fields, named once
#define SSR_GV_VERSION    "v"
#define SSR_GV_HEARTBEAT  "hb"
#define SSR_GV_STATE      "state"
#define SSR_GV_NOW        "now"
#define SSR_GV_START      "start"
#define SSR_GV_END        "end"
#define SSR_GV_SPEED      "speed"
#define SSR_GV_FIDELITY   "fid"
#define SSR_GV_SYNTHETIC  "synth"
#define SSR_GV_PERM       "perm"
#define SSR_GV_STREAMS    "streams"
#define SSR_GV_SYMHASH    "sym"
#define SSR_GV_BALANCE    "bal"
#define SSR_GV_EQUITY     "eq"
#define SSR_GV_OPEN       "open"
#define SSR_GV_AMBIGUOUS  "amb"

#define SSR_GV_CMD_SEQ    "cmd.seq"
#define SSR_GV_CMD_ID     "cmd.id"
#define SSR_GV_CMD_A1     "cmd.a1"
#define SSR_GV_CMD_A2     "cmd.a2"
#define SSR_GV_CMD_A3     "cmd.a3"
#define SSR_GV_CMD_ACK    "cmd.ack"
#define SSR_GV_CMD_RC     "cmd.rc"

//--- slots a client may scan. Matches the replay tool's own ceiling.
#define SSR_MAX_SLOTS     8

//+------------------------------------------------------------------+
//| A stable number from a symbol name.                              |
//|                                                                  |
//| Names do not fit in a double, and publishing one would mean a     |
//| second transport with its own failure modes. A client does not    |
//| need the name - it is already on the chart - it needs to know     |
//| whether the session it found is the one it is looking at.         |
//+------------------------------------------------------------------+
double SSRSymbolHash(const string name)
  {
   //--- FNV-1a folded into 31 bits, which a double holds exactly
   ulong h = 0xCBF29CE484222325;
   int   n = StringLen(name);
   for(int i = 0; i < n; i++)
     {
      h ^= (ulong)StringGetCharacter(name, i);
      h *= 0x100000001B3;
     }
   return (double)(long)(h % 2147483647);
  }

//--- names for the log and the panel
string SSRWireStateName(const int s)
  {
   switch(s)
     {
      case SSR_W_STATE_IDLE:      return "idle";
      case SSR_W_STATE_LOADING:   return "loading";
      case SSR_W_STATE_READY:     return "ready";
      case SSR_W_STATE_PLAYING:   return "playing";
      case SSR_W_STATE_PAUSED:    return "paused";
      case SSR_W_STATE_RESETTING: return "resetting";
      case SSR_W_STATE_COMPLETED: return "completed";
      case SSR_W_STATE_ERROR:     return "error";
     }
   return "?";
  }

string SSRWireRcName(const int rc)
  {
   switch(rc)
     {
      case SSR_RC_OK:             return "ok";
      case SSR_RC_UNKNOWN_CMD:    return "unknown command";
      case SSR_RC_NOT_PERMITTED:  return "not permitted by the replay session";
      case SSR_RC_REFUSED:        return "the replay engine refused it";
      case SSR_RC_NO_SESSION:     return "no replay session is running";
     }
   return "?";
  }

//+------------------------------------------------------------------+
//| Everything a client can know about a session.                    |
//+------------------------------------------------------------------+
struct SSRPublicState
  {
   bool              active;        // false means: behave as if normal
   int               version;
   int               slot;
   int               state;         // SSR_W_STATE_*
   long              now_msc;
   long              start_msc;
   long              end_msc;
   long              speed_x100;
   int               fidelity;      // SSR_W_FID_*
   bool              synthetic;     // is the intrabar order invented?
   int               permissions;
   int               streams;
   double            symbol_hash;
   double            balance;
   double            equity;
   int               open_positions;
   double            ambiguous_pct; // how much of the result is assumed
   long              age_ms;        // since the last heartbeat

   void              Init(void)
     {
      active = false; version = 0; slot = 0;
      state = SSR_W_STATE_IDLE;
      now_msc = 0; start_msc = 0; end_msc = 0;
      speed_x100 = 100; fidelity = SSR_W_FID_SYNTHETIC; synthetic = true;
      permissions = 0; streams = 0; symbol_hash = 0.0;
      balance = 0.0; equity = 0.0; open_positions = 0;
      ambiguous_pct = 0.0; age_ms = 0;
     }

   bool              Can(const int perm) { return ((permissions & perm) != 0); }
   bool              IsPlaying(void)     { return (active && state == SSR_W_STATE_PLAYING); }

   double            Progress(void)
     {
      if(!active || end_msc <= start_msc)
         return 0.0;
      double p = (double)(now_msc - start_msc) / (double)(end_msc - start_msc);
      return (p < 0.0 ? 0.0 : (p > 1.0 ? 1.0 : p));
     }

   //+------------------------------------------------------------------+
   //| The sentence a client should show beside its own numbers.        |
   //|                                                                  |
   //| Not optional politeness. A product displaying a signal computed  |
   //| during a replay, with no indication that it IS a replay, has     |
   //| put a fabricated price on the screen next to real ones.          |
   //+------------------------------------------------------------------+
   string            Banner(void)
     {
      if(!active)
         return "";
      string s = "REPLAY " + SSRWireStateName(state);
      if(synthetic)
         s += " - synthetic ticks";
      if(ambiguous_pct > 0.0)
         s += StringFormat(" - %.0f%% of results assumed", ambiguous_pct);
      return s;
     }
  };

#endif // SSR_CONTRACT_MQH
//+------------------------------------------------------------------+
