//+------------------------------------------------------------------+
//|                                                     SSR_Keys.mqh |
//|                          SS Replay - Keyboard Shortcuts (UI)     |
//|                                                                  |
//|  Replay is a two-handed activity: one on the mouse reading the   |
//|  chart, one on the keyboard stepping. The shortcuts matter more  |
//|  than the buttons once someone has used the tool for an hour.    |
//|                                                                  |
//|  Mapped to a command enum rather than acted on directly, so the  |
//|  panel handles a key and a click through exactly one path.       |
//+------------------------------------------------------------------+
#ifndef SSR_KEYS_MQH
#define SSR_KEYS_MQH

enum ENUM_SSR_CMD
  {
   SSR_CMD_NONE = 0,
   SSR_CMD_TOGGLE,        // play <-> pause
   SSR_CMD_PLAY,
   SSR_CMD_PAUSE,
   SSR_CMD_RESET,
   SSR_CMD_STEP_FWD,
   SSR_CMD_STEP_FWD_10,
   SSR_CMD_STEP_BACK,
   SSR_CMD_STEP_BACK_10,
   SSR_CMD_JUMP,
   SSR_CMD_BOOKMARK,
   SSR_CMD_RESTART,
   SSR_CMD_SPEED_UP,
   SSR_CMD_SPEED_DOWN,
   SSR_CMD_FOLLOW,
   SSR_CMD_FIDELITY_CYCLE,
   SSR_CMD_REPLAY_FROM_HERE,
   SSR_CMD_COLLAPSE,
   SSR_CMD_SESSIONS,         // open the saved-session list
   //--- the stop and target are lines now, so they need verbs
   SSR_CMD_LINES_TOGGLE,     // put them on the chart / take them off
   SSR_CMD_LINES_FLIP,       // mirror them: long <-> short
   SSR_CMD_OPEN_LINES,       // take the trade the lines describe
   SSR_CMD_KEYS              // show the list of keys, on the chart
  };

//--- virtual key codes as MetaTrader reports them in CHARTEVENT_KEYDOWN
#define SSR_VK_SPACE   32
#define SSR_VK_LEFT    37
#define SSR_VK_RIGHT   39
#define SSR_VK_R       82
#define SSR_VK_F       70
#define SSR_VK_D       68
#define SSR_VK_PLUS    187
#define SSR_VK_MINUS   189
#define SSR_VK_NUMPLUS 107
#define SSR_VK_NUMMIN  109
#define SSR_VK_PGUP    33
#define SSR_VK_PGDN    34
#define SSR_VK_J       74
#define SSR_VK_B       66
#define SSR_VK_S       83
#define SSR_VK_L       76
#define SSR_VK_X       88
#define SSR_VK_TAB      9
#define SSR_VK_H       72
#define SSR_VK_0       48
//--- not commands: the two ways out of a text box, so the panel can
//--- hand the keyboard back without the user hunting for somewhere
//--- safe to click
#define SSR_VK_ESCAPE  27
#define SSR_VK_ENTER   13

//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| ONE TABLE. THE LOOKUP AND THE PRINTED GUIDE BOTH READ IT.        |
//|                                                                  |
//| This was a switch, and the guide the user is shown would have    |
//| been a second list written by hand beside it. Two lists drift -  |
//| always, and silently, and the one that drifts is the one the     |
//| user is reading. A guide that names a key which no longer does   |
//| anything is worse than no guide, because it is believed.         |
//|                                                                  |
//| So there is one table. A key that is not in it does nothing, and |
//| a key in it appears on the card automatically.                   |
//+------------------------------------------------------------------+
struct SSRKeyBinding
  {
   int               vk;
   string            label;    // as the user should read it
   ENUM_SSR_CMD      cmd;
   string            what;     // one short line, for the card
   bool              listed;   // false for duplicates like the numpad
  };

int SSRKeyBindings(SSRKeyBinding &out[])
  {
   ArrayResize(out, 18);
   int i = 0;

   out[i].vk = SSR_VK_SPACE;  out[i].label = "Space";  out[i].cmd = SSR_CMD_TOGGLE;
   out[i].what = "play / pause";                       out[i].listed = true;  i++;
   out[i].vk = SSR_VK_RIGHT;  out[i].label = "Right";  out[i].cmd = SSR_CMD_STEP_FWD;
   out[i].what = "one candle forward";                 out[i].listed = true;  i++;
   out[i].vk = SSR_VK_LEFT;   out[i].label = "Left";   out[i].cmd = SSR_CMD_STEP_BACK;
   out[i].what = "one candle back";                    out[i].listed = true;  i++;
   out[i].vk = SSR_VK_PGDN;   out[i].label = "PgDn";   out[i].cmd = SSR_CMD_STEP_FWD_10;
   out[i].what = "ten candles forward";                out[i].listed = true;  i++;
   out[i].vk = SSR_VK_PGUP;   out[i].label = "PgUp";   out[i].cmd = SSR_CMD_STEP_BACK_10;
   out[i].what = "ten candles back";                   out[i].listed = true;  i++;
   out[i].vk = SSR_VK_PLUS;   out[i].label = "+ / -";  out[i].cmd = SSR_CMD_SPEED_UP;
   out[i].what = "faster / slower";                    out[i].listed = true;  i++;
   out[i].vk = SSR_VK_MINUS;  out[i].label = "-";      out[i].cmd = SSR_CMD_SPEED_DOWN;
   out[i].what = "slower";                             out[i].listed = false; i++;
   out[i].vk = SSR_VK_NUMPLUS; out[i].label = "Num +"; out[i].cmd = SSR_CMD_SPEED_UP;
   out[i].what = "faster";                             out[i].listed = false; i++;
   out[i].vk = SSR_VK_NUMMIN; out[i].label = "Num -";  out[i].cmd = SSR_CMD_SPEED_DOWN;
   out[i].what = "slower";                             out[i].listed = false; i++;

   //--- TRADING. R puts the stop and target on the chart, Tab takes
   //--- the trade they describe: the two keys a hand rests on while
   //--- the candles are moving.
   out[i].vk = SSR_VK_R;      out[i].label = "R";      out[i].cmd = SSR_CMD_LINES_TOGGLE;
   out[i].what = "stop and target lines on / off";     out[i].listed = true;  i++;
   out[i].vk = SSR_VK_TAB;    out[i].label = "Tab";    out[i].cmd = SSR_CMD_OPEN_LINES;
   out[i].what = "TAKE THE TRADE the lines describe";  out[i].listed = true;  i++;
   out[i].vk = SSR_VK_X;      out[i].label = "X";      out[i].cmd = SSR_CMD_LINES_FLIP;
   out[i].what = "flip them: long <-> short";          out[i].listed = true;  i++;
   out[i].vk = SSR_VK_L;      out[i].label = "L";      out[i].cmd = SSR_CMD_LINES_TOGGLE;
   out[i].what = "same as R";                          out[i].listed = false; i++;

   out[i].vk = SSR_VK_J;      out[i].label = "J";      out[i].cmd = SSR_CMD_JUMP;
   out[i].what = "jump to a time";                     out[i].listed = true;  i++;
   out[i].vk = SSR_VK_B;      out[i].label = "B";      out[i].cmd = SSR_CMD_BOOKMARK;
   out[i].what = "bookmark here";                      out[i].listed = true;  i++;
   out[i].vk = SSR_VK_S;      out[i].label = "S";      out[i].cmd = SSR_CMD_SESSIONS;
   out[i].what = "saved sessions";                     out[i].listed = true;  i++;
   out[i].vk = SSR_VK_F;      out[i].label = "F";      out[i].cmd = SSR_CMD_FOLLOW;
   out[i].what = "bring the charts back to now";       out[i].listed = true;  i++;
   out[i].vk = SSR_VK_D;      out[i].label = "D";      out[i].cmd = SSR_CMD_FIDELITY_CYCLE;
   out[i].what = "tick detail";                        out[i].listed = true;  i++;

   //+------------------------------------------------------------------+
   //| RESET MOVED OFF R, and off every letter.                         |
   //|                                                                  |
   //| R belongs to the hand that is trading. Reset destroys the whole  |
   //| session, so it now sits on a key nothing else is near - "back to |
   //| zero" - where it cannot be caught by a finger reaching for the   |
   //| lines. It still asks before it does anything.                    |
   //+------------------------------------------------------------------+
   out[i].vk = SSR_VK_0;      out[i].label = "0";      out[i].cmd = SSR_CMD_RESET;
   out[i].what = "start the session over (asks first)"; out[i].listed = true; i++;

   out[i].vk = SSR_VK_H;      out[i].label = "H";      out[i].cmd = SSR_CMD_KEYS;
   out[i].what = "this list";                          out[i].listed = true;  i++;

   ArrayResize(out, i);
   return i;
  }

ENUM_SSR_CMD SSRKeyToCommand(const long key)
  {
   SSRKeyBinding b[];
   int n = SSRKeyBindings(b);
   for(int i = 0; i < n; i++)
      if(b[i].vk == (int)key)
         return b[i].cmd;
   return SSR_CMD_NONE;
  }

//+------------------------------------------------------------------+
//| Name a command, so a key that did nothing can say which one it    |
//| was. "B does not work" and "B worked and showed nothing" look     |
//| identical from the outside, and they need opposite fixes.         |
//+------------------------------------------------------------------+
string SSRCmdName(const ENUM_SSR_CMD c)
  {
   switch(c)
     {
      case SSR_CMD_TOGGLE:           return "play/pause";
      case SSR_CMD_PLAY:             return "play";
      case SSR_CMD_PAUSE:            return "pause";
      case SSR_CMD_RESET:            return "reset";
      case SSR_CMD_STEP_FWD:         return "step forward";
      case SSR_CMD_STEP_FWD_10:      return "step forward x10";
      case SSR_CMD_STEP_BACK:        return "step back";
      case SSR_CMD_STEP_BACK_10:     return "step back x10";
      case SSR_CMD_JUMP:             return "jump";
      case SSR_CMD_BOOKMARK:         return "bookmark";
      case SSR_CMD_LINES_TOGGLE:     return "sl/tp lines";
      case SSR_CMD_LINES_FLIP:       return "flip lines";
      case SSR_CMD_RESTART:          return "restart";
      case SSR_CMD_SPEED_UP:         return "speed up";
      case SSR_CMD_SPEED_DOWN:       return "speed down";
      case SSR_CMD_FOLLOW:           return "follow charts";
      case SSR_CMD_FIDELITY_CYCLE:   return "fidelity";
      case SSR_CMD_REPLAY_FROM_HERE: return "replay from here";
      case SSR_CMD_COLLAPSE:         return "collapse";
      case SSR_CMD_SESSIONS:         return "sessions";
      case SSR_CMD_OPEN_LINES:       return "take the trade";
      case SSR_CMD_KEYS:             return "keys";
     }
   return "none";
  }

string SSRKeyHint(void)
  {
   return "SPACE play  <- -> step  PgUp/PgDn x10  J jump  B mark  "
          "S sessions  +/- speed  F follow  D fidelity  R reset";
  }

#endif // SSR_KEYS_MQH
//+------------------------------------------------------------------+
