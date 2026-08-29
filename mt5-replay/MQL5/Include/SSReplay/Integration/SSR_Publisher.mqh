//+------------------------------------------------------------------+
//|                                             SSR_Publisher.mqh    |
//|              SS Replay - The Replay Side Of The Contract (L5)    |
//|                                                                  |
//|  Publishes what a session is doing, and executes the commands a  |
//|  client is ALLOWED to send.                                      |
//|                                                                  |
//|  THE COUPLING THIS FILE EXISTS TO PREVENT                        |
//|                                                                  |
//|  Not "SS Replay talks to SSProX" - it does not, and cannot. This |
//|  class knows about the replay group and the virtual account and   |
//|  nothing else. There is no SSProX header anywhere in this        |
//|  product, so the dependency runs one way: the other product      |
//|  depends on a contract, and the contract depends on nobody.      |
//|                                                                  |
//|  FOUR THINGS A CLIENT CANNOT DO, ENFORCED HERE                   |
//|                                                                  |
//|  1. Reach a broker. The trade verbs land in the virtual account. |
//|     There is no OrderSend below this file, on any path.          |
//|  2. Read the future. There is no data verb at all, so there is   |
//|     nothing to ask for.                                          |
//|  3. Grant itself a permission. The mask is written by the replay |
//|     side and checked here, not where the client set it.          |
//|  4. Keep a dead session alive. The heartbeat is refreshed only   |
//|     while this publisher is being pumped.                        |
//+------------------------------------------------------------------+
#ifndef SSR_PUBLISHER_MQH
#define SSR_PUBLISHER_MQH

#include "SSR_Contract.mqh"
#include "../Common/SSR_Types.mqh"
#include "../Common/SSR_Time.mqh"
#include "../Core/SSR_MasterClock.mqh"
#include "../Trading/SSR_TradingEngine.mqh"

//+------------------------------------------------------------------+
class CSSRPublisher
  {
private:
   CSSRReplayGroup   *m_group;      // not owned
   CSSRTradingEngine *m_acct;       // not owned; may be NULL

   int                m_slot;
   int                m_permissions;
   bool               m_enabled;
   string             m_symbol;

   long               m_last_seq;   // the last command we executed
   long               m_published;
   long               m_executed;
   long               m_refused;
   string             m_last_command;

   void              Set(const string field, const double v)
     { GlobalVariableSet(SSRGvName(m_slot, field), v); }

   double            Get(const string field, const double def = 0.0)
     {
      string n = SSRGvName(m_slot, field);
      return (GlobalVariableCheck(n) ? GlobalVariableGet(n) : def);
     }

   //+------------------------------------------------------------------+
   //| Internal state to WIRE state.                                    |
   //|                                                                  |
   //| This switch is the boundary. Written as a mapping rather than a  |
   //| cast on purpose: the day somebody inserts a value into the       |
   //| internal enum, this stops compiling cleanly or keeps working -   |
   //| it does not silently start telling every installed client that   |
   //| a paused replay is resetting.                                    |
   //+------------------------------------------------------------------+
   int               WireState(const ENUM_SSR_STATE s)
     {
      switch(s)
        {
         case SSR_STATE_IDLE:       return SSR_W_STATE_IDLE;
         case SSR_STATE_LOADING:    return SSR_W_STATE_LOADING;
         case SSR_STATE_READY:      return SSR_W_STATE_READY;
         case SSR_STATE_PLAYING:    return SSR_W_STATE_PLAYING;
         case SSR_STATE_PAUSED:     return SSR_W_STATE_PAUSED;
         case SSR_STATE_RESETTING:  return SSR_W_STATE_RESETTING;
         case SSR_STATE_COMPLETED:  return SSR_W_STATE_COMPLETED;
         case SSR_STATE_ERROR:      return SSR_W_STATE_ERROR;
        }
      return SSR_W_STATE_IDLE;
     }

   int               WireFidelity(const ENUM_SSR_FIDELITY f)
     {
      switch(f)
        {
         case SSR_FIDELITY_FULL_TICK:      return SSR_W_FID_REAL_TICK;
         case SSR_FIDELITY_SYNTHETIC_TICK: return SSR_W_FID_SYNTHETIC;
         case SSR_FIDELITY_BAR:            return SSR_W_FID_BAR;
        }
      return SSR_W_FID_SYNTHETIC;
     }

public:
                     CSSRPublisher(void)
     : m_group(NULL), m_acct(NULL), m_slot(1),
       m_permissions(SSR_PERM_READ), m_enabled(false), m_symbol(""),
       m_last_seq(0), m_published(0), m_executed(0), m_refused(0),
       m_last_command("") {}

                    ~CSSRPublisher(void) { Withdraw(); }

   void              Attach(CSSRReplayGroup *g, CSSRTradingEngine *a = NULL)
     { m_group = g; m_acct = a; }

   //--- READ is always on; the rest is the user's decision, and the
   //--- default is no. "Another program may trade in my account" is
   //--- not something to arrive at by leaving a box unticked.
   void              SetPermissions(const bool control, const bool trade)
     {
      m_permissions = SSR_PERM_READ;
      if(control) m_permissions |= SSR_PERM_CONTROL;
      if(trade)   m_permissions |= SSR_PERM_TRADE;
     }

   void              SetSlot(const int slot)     { m_slot = slot; }
   void              SetSymbol(const string s)   { m_symbol = s; }
   int               Permissions(void)           { return m_permissions; }
   long              Published(void)             { return m_published; }
   long              Executed(void)              { return m_executed; }
   long              Refused(void)               { return m_refused; }
   string            LastCommand(void)           { return m_last_command; }
   bool              IsEnabled(void)             { return m_enabled; }

   //+------------------------------------------------------------------+
   //| Start publishing. Clears any command left by a previous run, so  |
   //| a stale sequence cannot be executed the moment we appear.        |
   //+------------------------------------------------------------------+
   bool              Begin(void)
     {
      if(m_group == NULL)
         return false;
      m_last_seq = 0;
      Set(SSR_GV_CMD_SEQ, 0.0);
      Set(SSR_GV_CMD_ACK, 0.0);
      Set(SSR_GV_CMD_ID,  (double)SSR_CMD_NONE);
      Set(SSR_GV_CMD_RC,  (double)SSR_RC_OK);
      Set(SSR_GV_VERSION, (double)SSR_CONTRACT_VERSION);
      m_enabled = true;
      Publish();
      return true;
     }

   //+------------------------------------------------------------------+
   //| Stop, and take the session's variables with us.                  |
   //|                                                                  |
   //| Terminal globals outlive the program that set them. Leaving      |
   //| them behind would tell every client that a replay is running     |
   //| until the terminal is restarted. The heartbeat would eventually  |
   //| save them - but only eventually, and only if they check it.      |
   //+------------------------------------------------------------------+
   void              Withdraw(void)
     {
      if(!m_enabled)
         return;
      string fields[] = {SSR_GV_VERSION, SSR_GV_HEARTBEAT, SSR_GV_STATE,
                         SSR_GV_NOW, SSR_GV_START, SSR_GV_END, SSR_GV_SPEED,
                         SSR_GV_FIDELITY, SSR_GV_SYNTHETIC, SSR_GV_PERM,
                         SSR_GV_STREAMS, SSR_GV_SYMHASH, SSR_GV_BALANCE,
                         SSR_GV_EQUITY, SSR_GV_OPEN, SSR_GV_AMBIGUOUS,
                         SSR_GV_CMD_SEQ, SSR_GV_CMD_ID, SSR_GV_CMD_A1,
                         SSR_GV_CMD_A2, SSR_GV_CMD_A3, SSR_GV_CMD_ACK,
                         SSR_GV_CMD_RC};
      for(int i = 0; i < ArraySize(fields); i++)
         GlobalVariableDel(SSRGvName(m_slot, fields[i]));
      m_enabled = false;
     }

   //+------------------------------------------------------------------+
   //| Publish the current state. Called from the host's timer.         |
   //+------------------------------------------------------------------+
   void              Publish(void)
     {
      if(!m_enabled || m_group == NULL || m_group.Count() == 0)
         return;
      CSSRReplayController *c = m_group.At(0);
      if(c == NULL)
         return;

      Set(SSR_GV_VERSION,   (double)SSR_CONTRACT_VERSION);
      Set(SSR_GV_STATE,     (double)WireState(c.Status()));
      Set(SSR_GV_NOW,       (double)m_group.Now());
      Set(SSR_GV_START,     (double)m_group.StartMsc());
      Set(SSR_GV_END,       (double)m_group.EndMsc());
      Set(SSR_GV_SPEED,     (double)m_group.SpeedX100());
      Set(SSR_GV_FIDELITY,  (double)WireFidelity(c.EffectiveFidelity()));
      Set(SSR_GV_SYNTHETIC, (c.EffectiveFidelity() == SSR_FIDELITY_FULL_TICK
                             ? 0.0 : 1.0));
      Set(SSR_GV_PERM,      (double)m_permissions);
      Set(SSR_GV_STREAMS,   (double)m_group.Count());
      Set(SSR_GV_SYMHASH,   SSRSymbolHash(m_symbol));

      if(m_acct != NULL)
        {
         Set(SSR_GV_BALANCE,   m_acct.Balance());
         Set(SSR_GV_EQUITY,    m_acct.Equity());
         Set(SSR_GV_OPEN,      (double)m_acct.OpenCount());
         //--- HOW MUCH OF THIS IS ASSUMED travels with the numbers, so
         //--- a client cannot display a balance from a replay without
         //--- also being able to say what it rests on
         Set(SSR_GV_AMBIGUOUS, m_acct.AmbiguousPercent());
        }

      //--- LAST. A client reads the heartbeat first and everything
      //--- else after, so writing it before the fields would let a
      //--- client read a fresh heartbeat beside stale values.
      Set(SSR_GV_HEARTBEAT, (double)GetTickCount64());
      m_published++;
     }

   //+------------------------------------------------------------------+
   //| Execute at most one pending command.                             |
   //|                                                                  |
   //| One per pump, deliberately. A client that could queue a hundred  |
   //| would be able to drive the replay faster than the person         |
   //| watching it can react - and the person is the point.             |
   //+------------------------------------------------------------------+
   bool              Poll(void)
     {
      if(!m_enabled || m_group == NULL)
         return false;

      long seq = (long)Get(SSR_GV_CMD_SEQ, 0.0);
      if(seq == 0 || seq == m_last_seq)
         return false;                  // nothing new

      int    cmd = (int)Get(SSR_GV_CMD_ID, SSR_CMD_NONE);
      double a1  = Get(SSR_GV_CMD_A1, 0.0);
      double a2  = Get(SSR_GV_CMD_A2, 0.0);
      double a3  = Get(SSR_GV_CMD_A3, 0.0);

      int rc = Execute(cmd, a1, a2, a3);

      //--- the result BEFORE the acknowledgement, because the client
      //--- watches the acknowledgement and reads the result after it
      Set(SSR_GV_CMD_RC,  (double)rc);
      Set(SSR_GV_CMD_ACK, (double)seq);
      m_last_seq = seq;

      if(rc == SSR_RC_OK) m_executed++;
      else                m_refused++;
      return true;
     }

private:
   //+------------------------------------------------------------------+
   //| THE ONLY PLACE A CLIENT'S REQUEST BECOMES AN ACTION.             |
   //+------------------------------------------------------------------+
   int               Execute(const int cmd, const double a1,
                             const double a2, const double a3)
     {
      m_last_command = StringFormat("cmd %d (%.4f, %.4f, %.4f)", cmd, a1, a2, a3);

      //--- the permission check lives HERE, not in the client. A
      //--- client that can be trusted to check its own permissions
      //--- does not need them.
      bool trading = (cmd == SSR_CMD_BUY || cmd == SSR_CMD_SELL ||
                      cmd == SSR_CMD_CLOSE_ALL);
      int  need    = (trading ? SSR_PERM_TRADE : SSR_PERM_CONTROL);
      if((m_permissions & need) == 0)
         return SSR_RC_NOT_PERMITTED;

      switch(cmd)
        {
         case SSR_CMD_PLAY:
            return (m_group.Play() ? SSR_RC_OK : SSR_RC_REFUSED);

         case SSR_CMD_PAUSE:
            return (m_group.Pause() ? SSR_RC_OK : SSR_RC_REFUSED);

         case SSR_CMD_STEP:
            return (m_group.StepBars((int)a1) ? SSR_RC_OK : SSR_RC_REFUSED);

         case SSR_CMD_STEP_BACK:
            return (m_group.StepBackward((int)a1) ? SSR_RC_OK : SSR_RC_REFUSED);

         case SSR_CMD_SPEED:
           {
            m_group.SetSpeedX100((long)a1);
            return SSR_RC_OK;
           }

         case SSR_CMD_JUMP:
            //--- clamped by the engine into its own timeline, so a
            //--- client asking for an instant outside the session
            //--- lands at the edge rather than anywhere strange
            return (m_group.JumpTo((long)a1) ? SSR_RC_OK : SSR_RC_REFUSED);

         case SSR_CMD_BUY:
           {
            if(m_acct == NULL)
               return SSR_RC_REFUSED;
            //--- tagged, so a trade another product placed can always
            //--- be told from one the trader placed
            return (m_acct.Open(SSR_ORDER_BUY, a1, a2, a3, 0.0, "external") > 0
                    ? SSR_RC_OK : SSR_RC_REFUSED);
           }

         case SSR_CMD_SELL:
           {
            if(m_acct == NULL)
               return SSR_RC_REFUSED;
            return (m_acct.Open(SSR_ORDER_SELL, a1, a2, a3, 0.0, "external") > 0
                    ? SSR_RC_OK : SSR_RC_REFUSED);
           }

         case SSR_CMD_CLOSE_ALL:
           {
            if(m_acct == NULL)
               return SSR_RC_REFUSED;
            m_acct.CloseAll();
            return SSR_RC_OK;
           }
        }
      return SSR_RC_UNKNOWN_CMD;
     }

public:
   string            ToString(void)
     {
      if(!m_enabled)
         return "publisher off";
      string p = "read";
      if((m_permissions & SSR_PERM_CONTROL) != 0) p += "+control";
      if((m_permissions & SSR_PERM_TRADE)   != 0) p += "+trade";
      return StringFormat("publisher[slot %d  %s  published=%I64d  "
                          "executed=%I64d  refused=%I64d]",
                          m_slot, p, m_published, m_executed, m_refused);
     }
  };

#endif // SSR_PUBLISHER_MQH
//+------------------------------------------------------------------+
