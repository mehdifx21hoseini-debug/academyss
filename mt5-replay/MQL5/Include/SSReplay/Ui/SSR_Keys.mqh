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
   SSR_CMD_LINES_FLIP        // mirror them: long <-> short
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

//+------------------------------------------------------------------+
ENUM_SSR_CMD SSRKeyToCommand(const long key)
  {
   switch((int)key)
     {
      case SSR_VK_SPACE:   return SSR_CMD_TOGGLE;
      case SSR_VK_RIGHT:   return SSR_CMD_STEP_FWD;
      case SSR_VK_PGDN:    return SSR_CMD_STEP_FWD_10;
      //--- bound at last: Phase 5 left these dead rather than have keys
      //--- that pretend to work, and Phase 8 is what earned them
      case SSR_VK_LEFT:    return SSR_CMD_STEP_BACK;
      case SSR_VK_PGUP:    return SSR_CMD_STEP_BACK_10;
      case SSR_VK_J:       return SSR_CMD_JUMP;
      case SSR_VK_B:       return SSR_CMD_BOOKMARK;
      case SSR_VK_S:       return SSR_CMD_SESSIONS;
      case SSR_VK_L:       return SSR_CMD_LINES_TOGGLE;
      case SSR_VK_X:       return SSR_CMD_LINES_FLIP;
      case SSR_VK_R:       return SSR_CMD_RESET;
      case SSR_VK_F:       return SSR_CMD_FOLLOW;
      case SSR_VK_D:       return SSR_CMD_FIDELITY_CYCLE;
      case SSR_VK_PLUS:
      case SSR_VK_NUMPLUS: return SSR_CMD_SPEED_UP;
      case SSR_VK_MINUS:
      case SSR_VK_NUMMIN:  return SSR_CMD_SPEED_DOWN;
     }
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
