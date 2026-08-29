//+------------------------------------------------------------------+
//|                                                SSR_Client.mqh    |
//|              SS Replay - The Third-Party Side (portable)         |
//|                                                                  |
//|  Copy this file and SSR_Contract.mqh into your product. That is  |
//|  the whole integration. Nothing else is needed, and nothing here |
//|  includes the replay tool - so your product still compiles on a  |
//|  machine that has never heard of it.                             |
//|                                                                  |
//|  THE RULE THIS CLASS IS BUILT AROUND                             |
//|                                                                  |
//|  Absence is the normal case. Most of the time no replay is       |
//|  running, and a client must behave exactly as it always did.     |
//|  So every accessor answers safely when there is no session, and  |
//|  IsActive() is the only question that ever needs asking.         |
//|                                                                  |
//|  And a session that CRASHED must not look like one that is       |
//|  running. Terminal global variables outlive the program that set |
//|  them, so this class trusts a heartbeat, not a flag.             |
//+------------------------------------------------------------------+
#ifndef SSR_CLIENT_MQH
#define SSR_CLIENT_MQH

#include "SSR_Contract.mqh"

//+------------------------------------------------------------------+
class CSSRClient
  {
private:
   int               m_slot;
   SSRPublicState    m_state;
   long              m_seq;          // our own command sequence
   int               m_last_rc;
   string            m_last_error;

   double            Gv(const string field, const double def = 0.0)
     {
      string n = SSRGvName(m_slot, field);
      if(!GlobalVariableCheck(n))
         return def;
      return GlobalVariableGet(n);
     }

public:
                     CSSRClient(void)
     : m_slot(1), m_seq(0), m_last_rc(SSR_RC_OK), m_last_error("")
     { m_state.Init(); }

   void              SetSlot(const int slot) { m_slot = slot; }
   int               Slot(void)              { return m_slot; }
   int               LastRc(void)            { return m_last_rc; }
   string            LastError(void)         { return m_last_error; }

   //+------------------------------------------------------------------+
   //| Find a running session. Returns the slot, or 0.                  |
   //|                                                                  |
   //| Scanning rather than assuming slot 1, because a user running two |
   //| replays is not doing anything wrong and a client that only ever  |
   //| looked at one would attach to whichever happened to be first.    |
   //+------------------------------------------------------------------+
   int               Discover(void)
     {
      int keep = m_slot;
      for(int s = 1; s <= SSR_MAX_SLOTS; s++)
        {
         m_slot = s;
         if(Refresh() && m_state.active)
            return s;
        }
      m_slot = keep;
      Refresh();
      return 0;
     }

   //+------------------------------------------------------------------+
   //| Read the session's state.                                        |
   //|                                                                  |
   //| Returns false when there is nothing to read, which is not an     |
   //| error - it is the answer most of the time.                       |
   //+------------------------------------------------------------------+
   bool              Refresh(void)
     {
      m_state.Init();
      m_state.slot = m_slot;

      int ver = (int)Gv(SSR_GV_VERSION, 0);
      if(ver <= 0)
         return false;                  // nothing has ever published here

      m_state.version = ver;
      if(ver > SSR_CONTRACT_VERSION)
        {
         //--- the replay tool is newer than this client. Reading its
         //--- fields anyway is how a client shows a number from the
         //--- wrong slot and nobody finds out for a month.
         m_last_rc    = SSR_RC_NO_SESSION;
         m_last_error = StringFormat("replay contract v%d; this client "
                                     "understands v%d - update it",
                                     ver, SSR_CONTRACT_VERSION);
         return false;
        }

      //--- THE HEARTBEAT DECIDES, not a flag. A crashed replay leaves
      //--- its globals behind exactly as they were.
      double hb  = Gv(SSR_GV_HEARTBEAT, 0.0);
      double now = (double)GetTickCount64();
      long   age = (long)(now - hb);
      if(hb <= 0.0 || age < 0 || age > SSR_HEARTBEAT_STALE_MS)
        {
         m_state.age_ms = (hb > 0.0 ? age : 0);
         return false;
        }

      m_state.age_ms        = age;
      m_state.active        = true;
      m_state.state         = (int)Gv(SSR_GV_STATE, SSR_W_STATE_IDLE);
      m_state.now_msc       = (long)Gv(SSR_GV_NOW, 0.0);
      m_state.start_msc     = (long)Gv(SSR_GV_START, 0.0);
      m_state.end_msc       = (long)Gv(SSR_GV_END, 0.0);
      m_state.speed_x100    = (long)Gv(SSR_GV_SPEED, 100.0);
      m_state.fidelity      = (int)Gv(SSR_GV_FIDELITY, SSR_W_FID_SYNTHETIC);
      m_state.synthetic     = (Gv(SSR_GV_SYNTHETIC, 1.0) != 0.0);
      m_state.permissions   = (int)Gv(SSR_GV_PERM, SSR_PERM_READ);
      m_state.streams       = (int)Gv(SSR_GV_STREAMS, 1.0);
      m_state.symbol_hash   = Gv(SSR_GV_SYMHASH, 0.0);
      m_state.balance       = Gv(SSR_GV_BALANCE, 0.0);
      m_state.equity        = Gv(SSR_GV_EQUITY, 0.0);
      m_state.open_positions= (int)Gv(SSR_GV_OPEN, 0.0);
      m_state.ambiguous_pct = Gv(SSR_GV_AMBIGUOUS, 0.0);
      return true;
     }

   //--- the state, as last refreshed
   void              StateInto(SSRPublicState &out) { out = m_state; }
   bool              IsActive(void)   { return m_state.active; }
   bool              IsPlaying(void)  { return m_state.IsPlaying(); }
   long              Now(void)        { return m_state.now_msc; }
   datetime          NowTime(void)    { return (datetime)(m_state.now_msc / 1000); }
   bool              IsSynthetic(void){ return m_state.synthetic; }
   string            Banner(void)     { return m_state.Banner(); }
   bool              Can(const int p) { return m_state.Can(p); }

   //--- is the session on THIS chart's symbol?
   bool              IsMySymbol(const string symbol)
     {
      return (m_state.active &&
              MathAbs(m_state.symbol_hash - SSRSymbolHash(symbol)) < 0.5);
     }

   //+------------------------------------------------------------------+
   //| Send a command and wait for the acknowledgement.                 |
   //|                                                                  |
   //| Synchronous on purpose. A fire-and-forget command whose result   |
   //| is never read is how a client ends up believing it paused the    |
   //| replay when it did not - and then acts on that belief.           |
   //|                                                                  |
   //| `timeout_ms` bounds the wait. This is a client's own thread and  |
   //| blocking the terminal is not on offer, so the default is short   |
   //| and a timeout is reported rather than waited out.                |
   //+------------------------------------------------------------------+
   bool              Send(const int cmd, const double a1 = 0.0,
                          const double a2 = 0.0, const double a3 = 0.0,
                          const int timeout_ms = 500)
     {
      m_last_rc    = SSR_RC_OK;
      m_last_error = "";

      if(!Refresh() || !m_state.active)
        {
         m_last_rc    = SSR_RC_NO_SESSION;
         m_last_error = SSRWireRcName(SSR_RC_NO_SESSION);
         return false;
        }

      //--- CHECKED HERE TOO, though the publisher checks again. This
      //--- one is a courtesy that gives a clear message; that one is
      //--- the rule, because a client is not trusted to enforce it.
      int need = SSR_PERM_CONTROL;
      if(cmd == SSR_CMD_BUY || cmd == SSR_CMD_SELL ||
         cmd == SSR_CMD_CLOSE_ALL ||
         cmd == SSR_CMD_BUY_RISK || cmd == SSR_CMD_SELL_RISK)
         need = SSR_PERM_TRADE;
      if(!m_state.Can(need))
        {
         m_last_rc    = SSR_RC_NOT_PERMITTED;
         m_last_error = SSRWireRcName(SSR_RC_NOT_PERMITTED);
         return false;
        }

      //--- a sequence the publisher echoes, so an old acknowledgement
      //--- is never mistaken for this one's
      m_seq++;
      GlobalVariableSet(SSRGvName(m_slot, SSR_GV_CMD_A1), a1);
      GlobalVariableSet(SSRGvName(m_slot, SSR_GV_CMD_A2), a2);
      GlobalVariableSet(SSRGvName(m_slot, SSR_GV_CMD_A3), a3);
      GlobalVariableSet(SSRGvName(m_slot, SSR_GV_CMD_ID), (double)cmd);
      //--- the sequence LAST: the publisher watches it, so writing it
      //--- first would let a command be picked up with stale arguments
      GlobalVariableSet(SSRGvName(m_slot, SSR_GV_CMD_SEQ), (double)m_seq);

      ulong until = GetTickCount64() + (ulong)(timeout_ms < 0 ? 0 : timeout_ms);
      while(GetTickCount64() <= until)
        {
         if((long)Gv(SSR_GV_CMD_ACK, 0.0) == m_seq)
           {
            m_last_rc = (int)Gv(SSR_GV_CMD_RC, SSR_RC_OK);
            if(m_last_rc != SSR_RC_OK)
               m_last_error = SSRWireRcName(m_last_rc);
            return (m_last_rc == SSR_RC_OK);
           }
         //--- Sleep is not available to an indicator, and this loop
         //--- must work in one. Spinning briefly is the cost of that.
        }

      m_last_rc    = SSR_RC_REFUSED;
      m_last_error = "the replay session did not answer within " +
                     IntegerToString(timeout_ms) + "ms";
      return false;
     }

   //--- the verbs, spelled out so a caller need not remember numbers
   bool              Play(void)              { return Send(SSR_CMD_PLAY); }
   bool              Pause(void)             { return Send(SSR_CMD_PAUSE); }
   bool              Step(const int bars)    { return Send(SSR_CMD_STEP, bars); }
   bool              StepBack(const int bars){ return Send(SSR_CMD_STEP_BACK, bars); }
   bool              SetSpeed(const long x100) { return Send(SSR_CMD_SPEED, (double)x100); }
   bool              JumpTo(const long msc)  { return Send(SSR_CMD_JUMP, (double)msc); }

   //--- VIRTUAL trades. There is no verb here that reaches a broker,
   //--- and no version of this file in which one appears.
   bool              Buy(const double volume, const double sl = 0.0,
                         const double tp = 0.0)
     { return Send(SSR_CMD_BUY, volume, sl, tp); }
   bool              Sell(const double volume, const double sl = 0.0,
                          const double tp = 0.0)
     { return Send(SSR_CMD_SELL, volume, sl, tp); }
   bool              CloseAll(void)          { return Send(SSR_CMD_CLOSE_ALL); }

   //--- sized from RISK by the replay's own engine. The stop is
   //--- required, because without one there is no risk to size from.
   bool              BuyRisk(const double risk_percent, const double sl,
                             const double tp = 0.0)
     { return Send(SSR_CMD_BUY_RISK, risk_percent, sl, tp); }
   bool              SellRisk(const double risk_percent, const double sl,
                              const double tp = 0.0)
     { return Send(SSR_CMD_SELL_RISK, risk_percent, sl, tp); }

   string            ToString(void)
     {
      if(!m_state.active)
         return "no replay session";
      return StringFormat("replay[slot %d  %s  %s  x%.2f  %s]",
                          m_slot, SSRWireStateName(m_state.state),
                          TimeToString(NowTime(), TIME_DATE | TIME_MINUTES),
                          m_state.speed_x100 / 100.0,
                          (m_state.synthetic ? "synthetic" : "real ticks"));
     }
  };

#endif // SSR_CLIENT_MQH
//+------------------------------------------------------------------+
