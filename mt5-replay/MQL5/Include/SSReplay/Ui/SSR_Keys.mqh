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
   SSR_CMD_SPEED_UP,
   SSR_CMD_SPEED_DOWN,
   SSR_CMD_FOLLOW,
   SSR_CMD_FIDELITY_CYCLE,
   SSR_CMD_REPLAY_FROM_HERE,
   SSR_CMD_COLLAPSE
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

//+------------------------------------------------------------------+
ENUM_SSR_CMD SSRKeyToCommand(const long key)
  {
   switch((int)key)
     {
      case SSR_VK_SPACE:   return SSR_CMD_TOGGLE;
      case SSR_VK_RIGHT:   return SSR_CMD_STEP_FWD;
      case SSR_VK_PGDN:    return SSR_CMD_STEP_FWD_10;
      case SSR_VK_R:       return SSR_CMD_RESET;
      case SSR_VK_F:       return SSR_CMD_FOLLOW;
      case SSR_VK_D:       return SSR_CMD_FIDELITY_CYCLE;
      case SSR_VK_PLUS:
      case SSR_VK_NUMPLUS: return SSR_CMD_SPEED_UP;
      case SSR_VK_MINUS:
      case SSR_VK_NUMMIN:  return SSR_CMD_SPEED_DOWN;
     }
   //--- LEFT is deliberately unmapped until Phase 8 delivers a real
   //--- rewind. Binding it to nothing is better than binding it to
   //--- something that silently does not work.
   return SSR_CMD_NONE;
  }

string SSRKeyHint(void)
  {
   return "SPACE play  → step  PgDn x10  +/- speed  F follow  D fidelity  R reset";
  }

#endif // SSR_KEYS_MQH
//+------------------------------------------------------------------+
