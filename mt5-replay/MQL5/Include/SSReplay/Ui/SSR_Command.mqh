//+------------------------------------------------------------------+
//|                                                  SSR_Command.mqh |
//|                   SS Replay - one table of everything you can do  |
//|                                                                  |
//|  WHY A REGISTRY AND NOT A MENU                                   |
//|                                                                  |
//|  Twenty keyboard bindings exist and are discoverable only by      |
//|  pressing H. Thirty panel actions exist and are discoverable only |
//|  by finding the button. Nothing tells a new user that "export the |
//|  statement" is a thing this product does, and nothing tells an    |
//|  experienced one that it has a key.                              |
//|                                                                  |
//|  THIS INVENTS NO VERBS. Every entry resolves to something that    |
//|  already exists: either an ENUM_SSR_CMD - exactly what a key      |
//|  produces - or a panel action string, exactly what a button       |
//|  click produces. Two existing paths, no third one. A command      |
//|  that needed a new path would be a feature, and features do not   |
//|  arrive through a search box.                                    |
//|                                                                  |
//|  The key column is read from SSRKeyBindings(), so a command that  |
//|  has a shortcut always shows the right one and a rebinding is     |
//|  never followed by a palette that lies about it.                  |
//+------------------------------------------------------------------+
#ifndef SSR_COMMAND_MQH
#define SSR_COMMAND_MQH

#include "SSR_Keys.mqh"

//+------------------------------------------------------------------+
//| One entry. Exactly one of `cmd` and `action` is meaningful:       |
//| `cmd` goes to the host the way a keypress does, `action` goes to  |
//| the panel the way a click does.                                   |
//+------------------------------------------------------------------+
struct SSRCommand
  {
   string            label;    // what the user reads and types against
   string            group;    // Replay, Trade, Session, View
   ENUM_SSR_CMD      cmd;      // host command, or SSR_CMD_NONE
   string            action;   // panel action, or ""
  };

//--- grows the array itself: no count is kept anywhere, because a
//--- count kept by hand beside a list kept by hand will drift. This
//--- file learned that from SSR_Keys.mqh, which learned it from an
//--- ArrayResize(out,18) followed by twenty bindings.
void SSRAddCommand(SSRCommand &out[], int &i, const string label,
                   const string group, const ENUM_SSR_CMD cmd,
                   const string action = "")
  {
   if(ArraySize(out) <= i)
      ArrayResize(out, i + 8);
   out[i].label  = label;
   out[i].group  = group;
   out[i].cmd    = cmd;
   out[i].action = action;
   i++;
  }

//+------------------------------------------------------------------+
//| THE TABLE.                                                       |
//|                                                                  |
//| Labels are written the way a person would say the thing, not the |
//| way the code names it: "Close every position", not "flat".        |
//+------------------------------------------------------------------+
int SSRCommands(SSRCommand &out[])
  {
   int i = 0;

   //--- Replay
   SSRAddCommand(out, i, "Play / pause",              "Replay", SSR_CMD_TOGGLE);
   SSRAddCommand(out, i, "Step one candle forward",   "Replay", SSR_CMD_STEP_FWD);
   SSRAddCommand(out, i, "Step one candle back",      "Replay", SSR_CMD_STEP_BACK);
   SSRAddCommand(out, i, "Step ten candles forward",  "Replay", SSR_CMD_STEP_FWD_10);
   SSRAddCommand(out, i, "Step ten candles back",     "Replay", SSR_CMD_STEP_BACK_10);
   SSRAddCommand(out, i, "Faster",                    "Replay", SSR_CMD_SPEED_UP);
   SSRAddCommand(out, i, "Slower",                    "Replay", SSR_CMD_SPEED_DOWN);
   SSRAddCommand(out, i, "Jump to a time",            "Replay", SSR_CMD_JUMP);
   SSRAddCommand(out, i, "Back to the start",         "Replay", SSR_CMD_RESTART);
   SSRAddCommand(out, i, "Bring the charts to now",   "Replay", SSR_CMD_FOLLOW);
   SSRAddCommand(out, i, "Tick detail",               "Replay", SSR_CMD_FIDELITY_CYCLE);

   //--- Trade. Every one of these is a button that already exists.
   SSRAddCommand(out, i, "Buy at market",             "Trade", SSR_CMD_NONE, "buy");
   SSRAddCommand(out, i, "Sell at market",            "Trade", SSR_CMD_NONE, "sell");
   SSRAddCommand(out, i, "Stop and target lines",     "Trade", SSR_CMD_LINES_TOGGLE);
   SSRAddCommand(out, i, "Take the trade the lines describe",
                                                      "Trade", SSR_CMD_OPEN_LINES);
   SSRAddCommand(out, i, "Flip the lines long / short",
                                                      "Trade", SSR_CMD_LINES_FLIP);
   SSRAddCommand(out, i, "Add an entry line (pending order)",
                                                      "Trade", SSR_CMD_NONE, "enbtn");
   SSRAddCommand(out, i, "Remove the planning lines", "Trade", SSR_CMD_NONE, "clrbtn");
   SSRAddCommand(out, i, "Break even on every position",
                                                      "Trade", SSR_CMD_NONE, "be");
   SSRAddCommand(out, i, "Close every position",      "Trade", SSR_CMD_NONE, "flat");
   SSRAddCommand(out, i, "Trailing stop off",         "Trade", SSR_CMD_NONE, "troff");

   //--- Session
   SSRAddCommand(out, i, "Bookmark this moment",      "Session", SSR_CMD_BOOKMARK);
   SSRAddCommand(out, i, "Saved sessions",            "Session", SSR_CMD_SESSIONS);
   SSRAddCommand(out, i, "Export the statement",      "Session", SSR_CMD_NONE, "stmt");
   SSRAddCommand(out, i, "Reset the session",         "Session", SSR_CMD_RESET);

   //--- View
   SSRAddCommand(out, i, "Keyboard shortcuts",        "View", SSR_CMD_KEYS);
   SSRAddCommand(out, i, "Collapse the panel",        "View", SSR_CMD_COLLAPSE);
   SSRAddCommand(out, i, "Move the panel to the next corner",
                                                      "View", SSR_CMD_NONE, "move");

   ArrayResize(out, i);
   return i;
  }

//+------------------------------------------------------------------+
//| The key that runs a command, or "" - read from the key table so   |
//| the two can never disagree.                                       |
//+------------------------------------------------------------------+
string SSRCommandKey(const SSRCommand &c)
  {
   if(c.cmd == SSR_CMD_NONE)
      return "";
   SSRKeyBinding keys[];
   int n = SSRKeyBindings(keys);
   for(int i = 0; i < n; i++)
      if(keys[i].cmd == c.cmd)
         return keys[i].label;
   return "";
  }

//+------------------------------------------------------------------+
//| SUBSEQUENCE MATCHING, not substring.                             |
//|                                                                  |
//| "cep" finds "Close every position" and "stmt" finds "Export the   |
//| statement". A trader typing into a box mid-session is typing      |
//| fast and from memory, and a search that demands the exact         |
//| substring makes them slow down and remember the wording - which   |
//| is the thing a palette exists to remove.                          |
//|                                                                  |
//| Case-insensitive on both sides. An empty query matches everything |
//| in table order, so opening the palette shows what there IS - the  |
//| discovery half of the feature, and the reason the table is        |
//| grouped rather than alphabetical.                                 |
//+------------------------------------------------------------------+
bool SSRCommandMatches(const string label, const string query)
  {
   if(query == "")
      return true;
   string l = label;  StringToLower(l);
   string q = query;  StringToLower(q);
   int li = 0, qi = 0;
   int ln = StringLen(l), qn = StringLen(q);
   while(li < ln && qi < qn)
     {
      if(StringGetCharacter(l, li) == StringGetCharacter(q, qi))
         qi++;
      li++;
     }
   return (qi >= qn);
  }

//--- indices of every command whose label matches, in table order
int SSRCommandFilter(const SSRCommand &all[], const string query, int &hit[])
  {
   int n = ArraySize(all), k = 0;
   ArrayResize(hit, n);
   for(int i = 0; i < n; i++)
      if(SSRCommandMatches(all[i].label, query))
         hit[k++] = i;
   ArrayResize(hit, k);
   return k;
  }

#endif // SSR_COMMAND_MQH
//+------------------------------------------------------------------+
