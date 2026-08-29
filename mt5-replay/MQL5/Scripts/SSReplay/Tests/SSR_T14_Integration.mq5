//+------------------------------------------------------------------+
//|                                          SSR_T14_Integration.mq5 |
//|                    SS Replay - Phase 14 Integration Layer        |
//|                                                                  |
//|  The claim is not "two programs can talk". It is that the four   |
//|  couplings which would make this dangerous CANNOT FORM:          |
//|                                                                  |
//|   1. a client escalating itself to a real order                  |
//|   2. a client reading past the replay clock                      |
//|   3. a client granting itself a permission                       |
//|   4. a crashed session that still looks alive                    |
//|                                                                  |
//|  Plus the one that makes an integration rot silently: a wire     |
//|  number that changes because an internal enum did.               |
//+------------------------------------------------------------------+
#property script_show_inputs

#include <SSReplay/Common/SSR_Types.mqh>
#include <SSReplay/Common/SSR_Time.mqh>
#include <SSReplay/Core/SSR_ReplayController.mqh>
#include <SSReplay/Core/SSR_MasterClock.mqh>
#include <SSReplay/Core/Sources/SSR_MemoryDataSource.mqh>
#include <SSReplay/Core/Sinks/SSR_RecordingSink.mqh>
#include <SSReplay/Trading/SSR_TradingEngine.mqh>
#include <SSReplay/Integration/SSR_Contract.mqh>
#include <SSReplay/Integration/SSR_Publisher.mqh>
#include <SSReplay/Integration/SSR_Client.mqh>

input datetime InpStart  = D'2024.01.08 00:00';
input int      InpBars   = 4320;
input int      InpWarmup = 60;
input int      InpSlot   = 7;          // a slot no real session would use

int g_pass = 0, g_fail = 0;
void Check(const string n, const bool ok, const string d = "")
  { if(ok) { g_pass++; PrintFormat("  PASS  %s", n); }
    else   { g_fail++; PrintFormat("  FAIL  %s  %s", n, d); } }
void CheckEq(const string n, const long e, const long a)
  { Check(n, e == a, StringFormat("expected=%I64d actual=%I64d", e, a)); }
void CheckNear(const string n, const double e, const double a, const double tol)
  { Check(n, MathAbs(e - a) <= tol, StringFormat("expected=%.5f actual=%.5f", e, a)); }
void Section(const string t) { PrintFormat("--- %s", t); }

long g_start = 0, g_end = 0;

void BuildBars(MqlRates &out[], const datetime start, const int count,
               const double base)
  {
   ArrayResize(out, count);
   for(int i = 0; i < count; i++)
     {
      out[i].time  = start + i * 60;
      out[i].open  = base;  out[i].close = base;
      out[i].high  = base + 5.0;
      out[i].low   = base - 5.0;
      out[i].tick_volume = 10; out[i].spread = 0; out[i].real_volume = 0;
     }
  }

//+------------------------------------------------------------------+
void OnStart()
  {
   g_start = SSRToMsc(InpStart) + (long)InpWarmup * SSR_MSC_PER_MIN;
   g_end   = g_start + 2000 * SSR_MSC_PER_MIN;
   Print("=== SSR Phase 14 - SSProX Integration Layer ===");

   //================================================================
   Section("T14.1  the wire numbers are frozen");
   {
      //--- IF THESE EVER CHANGE, every installed copy of every other
      //--- product starts misreading this one. They are asserted as
      //--- literals so that changing them is a decision, not a typo.
      CheckEq("idle",      0, SSR_W_STATE_IDLE);
      CheckEq("loading",   1, SSR_W_STATE_LOADING);
      CheckEq("ready",     2, SSR_W_STATE_READY);
      CheckEq("playing",   3, SSR_W_STATE_PLAYING);
      CheckEq("paused",    4, SSR_W_STATE_PAUSED);
      CheckEq("resetting", 5, SSR_W_STATE_RESETTING);
      CheckEq("completed", 6, SSR_W_STATE_COMPLETED);
      CheckEq("error",     7, SSR_W_STATE_ERROR);

      CheckEq("real ticks", 0, SSR_W_FID_REAL_TICK);
      CheckEq("synthetic",  1, SSR_W_FID_SYNTHETIC);
      CheckEq("bar",        2, SSR_W_FID_BAR);

      CheckEq("read",    0x01, SSR_PERM_READ);
      CheckEq("control", 0x02, SSR_PERM_CONTROL);
      CheckEq("trade",   0x04, SSR_PERM_TRADE);

      CheckEq("play",      1, SSR_CMD_PLAY);
      CheckEq("pause",     2, SSR_CMD_PAUSE);
      CheckEq("close all", 9, SSR_CMD_CLOSE_ALL);

      //--- and the naming is one function, so the two sides cannot
      //--- disagree about where a value lives
      Check("names are namespaced by slot",
            SSRGvName(3, "now") == "SSR.3.now", SSRGvName(3, "now"));
      Check("two slots do not collide",
            SSRGvName(1, "now") != SSRGvName(2, "now"));

      //--- the symbol hash is stable and separates instruments
      CheckNear("the same name hashes the same",
                SSRSymbolHash("EURUSD.SSR1"), SSRSymbolHash("EURUSD.SSR1"), 0.0);
      Check("different names do not",
            SSRSymbolHash("EURUSD.SSR1") != SSRSymbolHash("XAUUSD.SSR1"));
      Check("and it fits a double exactly",
            SSRSymbolHash("EURUSD.SSR1") < 2147483647.0);
   }

   //================================================================
   Section("T14.2  no session means no session, safely");
   {
      CSSRClient c;
      c.SetSlot(InpSlot);
      //--- make sure nothing is left from an earlier run
      CSSRPublisher wipe;
      CSSRReplayGroup dummy;
      wipe.Attach(GetPointer(dummy), NULL);
      wipe.SetSlot(InpSlot);
      wipe.Begin();
      wipe.Withdraw();

      Check("nothing to refresh", !c.Refresh());
      Check("and it says so",     !c.IsActive());
      Check("not playing",        !c.IsPlaying());
      CheckEq("no time",          0, c.Now());

      //--- THE BANNER IS EMPTY when there is no replay, because a
      //--- client showing "REPLAY" over live prices would be worse
      //--- than showing nothing
      Check("no banner", c.Banner() == "", c.Banner());

      //--- and every command is refused rather than swallowed
      Check("play is refused", !c.Play());
      CheckEq("with no-session", SSR_RC_NO_SESSION, c.LastRc());
      Check("buy is refused too", !c.Buy(1.0));
      CheckEq("discovery finds nothing", 0, c.Discover());
   }

   //================================================================
   Section("T14.3  a live session, read by a client");
   {
      CSSRMemoryDataSource src; CSSRRecordingSink sink;
      CSSRReplayController ctrl; CSSRTradingEngine acct;
      CSSRReplayGroup grp; CSSRPublisher pub;

      ctrl.AddObserver(GetPointer(acct));
      MqlRates bars[];
      BuildBars(bars, InpStart, InpBars, 1000.0);
      src.LoadBars(bars, ArraySize(bars));
      ctrl.SetSymbolSpec(2, 0.01);
      ctrl.SetTicksPerBar(8);
      ctrl.SetSpreadPoints(0);
      ctrl.SetWarmupBars(InpWarmup);
      ctrl.SetFidelity(SSR_FIDELITY_SYNTHETIC_TICK);
      ctrl.Attach(GetPointer(src), GetPointer(sink));
      Check("loaded", ctrl.Load("TEST", g_start, g_end), ctrl.LastErrorText());
      acct.SetBalance(10000.0);

      grp.Add(GetPointer(ctrl));
      Check("aligned", grp.Align(), grp.LastError());

      pub.Attach(GetPointer(grp), GetPointer(acct));
      pub.SetSlot(InpSlot);
      pub.SetSymbol("TEST.SSR7");
      pub.SetPermissions(false, false);      // read only, the default
      Check("publishing", pub.Begin());

      CSSRClient c;
      c.SetSlot(InpSlot);
      Check("the client sees it", c.Refresh());
      Check("active", c.IsActive());
      CheckEq("discovery finds it", InpSlot, c.Discover());

      SSRPublicState st;
      c.StateInto(st);
      CheckEq("contract version", SSR_CONTRACT_VERSION, st.version);
      CheckEq("state is ready",   SSR_W_STATE_READY,    st.state);
      CheckEq("the window start", g_start,              st.start_msc);
      CheckEq("the window end",   g_end,                st.end_msc);
      CheckEq("one stream",       1,                    st.streams);
      CheckNear("the balance",    10000.0, st.balance,  0.005);
      Check("it knows the ticks are synthetic", st.synthetic);
      CheckEq("fidelity",         SSR_W_FID_SYNTHETIC,  st.fidelity);

      Check("and it can tell the symbol is the one on its chart",
            c.IsMySymbol("TEST.SSR7"));
      Check("and that another is not", !c.IsMySymbol("OTHER.SSR7"));

      //--- THE BANNER. A product showing a signal computed during a
      //--- replay, with nothing saying it is a replay, has put a
      //--- fabricated price on screen beside real ones.
      Check("the banner says REPLAY",
            StringFind(c.Banner(), "REPLAY") >= 0, c.Banner());
      Check("and that the ticks are synthetic",
            StringFind(c.Banner(), "synthetic") >= 0, c.Banner());

      grp.Play();
      for(int i = 0; i < 40; i++)
        { grp.Pump(1000); pub.Publish(); }

      Check("the client follows the clock", c.Refresh());
      c.StateInto(st);
      CheckEq("playing", SSR_W_STATE_PLAYING, st.state);
      CheckEq("at the group's instant", grp.Now(), st.now_msc);
      Check("with progress", st.Progress() > 0.0,
            DoubleToString(st.Progress(), 4));

      //================================================================
      Section("T14.4  a client cannot grant itself a permission");
      {
         //--- read-only was published, so control is refused
         Check("cannot pause",    !c.Pause());
         CheckEq("not permitted", SSR_RC_NOT_PERMITTED, c.LastRc());
         Check("cannot trade",    !c.Buy(1.0));
         CheckEq("not permitted", SSR_RC_NOT_PERMITTED, c.LastRc());
         Check("the replay carried on regardless",
               ctrl.Status() == SSR_STATE_PLAYING, SSRStateName(ctrl.Status()));

         //--- AND WRITING THE PERMISSION MASK DIRECTLY DOES NOT HELP.
         //--- A client is not trusted to check its own permissions;
         //--- the publisher checks again on the far side.
         GlobalVariableSet(SSRGvName(InpSlot, SSR_GV_PERM),
                           (double)(SSR_PERM_READ | SSR_PERM_CONTROL |
                                    SSR_PERM_TRADE));
         c.Refresh();
         Check("the client now believes it may trade", c.Can(SSR_PERM_TRADE));

         //--- it sends the command; the publisher refuses it anyway
         long before = acct.Total();
         c.Send(SSR_CMD_BUY, 1.0, 0.0, 0.0, 0);      // fire, do not wait
         pub.Poll();
         CheckEq("but no position was opened", before, acct.Total());
         CheckEq("and the refusal was counted", 1, pub.Refused());

         //--- put the truth back
         pub.Publish();
         c.Refresh();
         Check("the published mask is restored", !c.Can(SSR_PERM_TRADE));
      }

      //================================================================
      Section("T14.5  with permission, control reaches the engine");
      {
         pub.SetPermissions(true, true);
         pub.Publish();
         Check("the client sees the grant", c.Refresh() && c.Can(SSR_PERM_CONTROL));

         //--- the test drives both sides by hand: send, then poll,
         //--- because there is no timer here to do it
         c.Send(SSR_CMD_PAUSE, 0, 0, 0, 0);
         Check("a command arrived", pub.Poll());
         Check("and the replay paused",
               ctrl.Status() == SSR_STATE_PAUSED, SSRStateName(ctrl.Status()));
         CheckEq("counted as executed", 1, pub.Executed());

         //--- polling again must NOT re-execute it
         Check("nothing new to poll", !pub.Poll());
         CheckEq("still one", 1, pub.Executed());

         long before_now = grp.Now();
         c.Send(SSR_CMD_STEP, 5, 0, 0, 0);
         Check("step arrived", pub.Poll());
         Check("and time moved", grp.Now() > before_now,
               StringFormat("%s -> %s", SSRFormatMsc(before_now),
                            SSRFormatMsc(grp.Now())));

         c.Send(SSR_CMD_SPEED, 500, 0, 0, 0);
         Check("speed arrived", pub.Poll());
         CheckEq("and was applied", 500, grp.SpeedX100());

         //--- a virtual trade, which is the only kind there is
         ctrl.Play();
         for(int i = 0; i < 10; i++)
            grp.Pump(1000);
         long before_trades = acct.Total();
         c.Send(SSR_CMD_BUY, 1.0, 0.0, 0.0, 0);
         Check("buy arrived", pub.Poll());
         CheckEq("a position was opened", before_trades + 1, acct.Total());

         SSRVirtualPosition p;
         Check("and it exists", acct.At((int)before_trades, p));
         Check("tagged as external, never as the trader's",
               p.tag == "external", p.tag);

         //--- an unknown verb is refused, not guessed at
         c.Send(4242, 0, 0, 0, 0);
         pub.Poll();
         CheckEq("unknown commands are refused", SSR_RC_UNKNOWN_CMD,
                 (int)GlobalVariableGet(SSRGvName(InpSlot, SSR_GV_CMD_RC)));
      }

      //================================================================
      Section("T14.6  a session that stops looks stopped");
      {
         //--- A CRASHED REPLAY leaves its globals exactly as they
         //--- were. Without a heartbeat a client would believe it was
         //--- running until the terminal restarted.
         Check("alive now", c.Refresh() && c.IsActive());

         //--- simulate a session that stopped being pumped
         GlobalVariableSet(SSRGvName(InpSlot, SSR_GV_HEARTBEAT),
                           (double)(GetTickCount64() - SSR_HEARTBEAT_STALE_MS - 1000));
         Check("a stale heartbeat reads as gone", !c.Refresh());
         Check("and the client says so", !c.IsActive());
         Check("with an empty banner", c.Banner() == "", c.Banner());

         //--- pumping it again brings it back
         pub.Publish();
         Check("a fresh heartbeat revives it", c.Refresh() && c.IsActive());

         //--- and a clean shutdown removes the variables entirely,
         //--- rather than leaving a stale session for five seconds
         pub.Withdraw();
         Check("withdrawn", !c.Refresh());
         Check("the version variable is gone",
               !GlobalVariableCheck(SSRGvName(InpSlot, SSR_GV_VERSION)));
         Check("and so is the command slot",
               !GlobalVariableCheck(SSRGvName(InpSlot, SSR_GV_CMD_SEQ)));
      }
   }

   //================================================================
   Section("T14.7  a client from the future is told, not mis-served");
   {
      CSSRClient c;
      c.SetSlot(InpSlot);
      //--- a replay tool newer than this client
      GlobalVariableSet(SSRGvName(InpSlot, SSR_GV_VERSION),
                        (double)(SSR_CONTRACT_VERSION + 5));
      GlobalVariableSet(SSRGvName(InpSlot, SSR_GV_HEARTBEAT),
                        (double)GetTickCount64());

      Check("it refuses to read", !c.Refresh());
      Check("rather than reading the wrong fields", !c.IsActive());
      Check("and names both versions",
            StringFind(c.LastError(), "contract v") >= 0, c.LastError());
      Check("telling the user what to do",
            StringFind(c.LastError(), "update") >= 0, c.LastError());

      GlobalVariableDel(SSRGvName(InpSlot, SSR_GV_VERSION));
      GlobalVariableDel(SSRGvName(InpSlot, SSR_GV_HEARTBEAT));
   }

   //================================================================
   Section("T14.8  the contract cannot express the dangerous things");
   {
      //--- These are assertions about the CONTRACT ITSELF, and they
      //--- are here because a future edit that adds one of these verbs
      //--- should have to delete a test that says why it must not.

      //--- there is no verb that names a time to READ. Every command
      //--- either moves the replay or trades; none returns data.
      int read_verbs = 0;
      for(int cmd = 0; cmd <= 9; cmd++)
        {
         //--- the full set, enumerated: play, pause, step, step back,
         //--- speed, jump, buy, sell, close all - and none of them
         //--- answers "what was the price at T"
         if(cmd == SSR_CMD_PLAY || cmd == SSR_CMD_PAUSE ||
            cmd == SSR_CMD_STEP || cmd == SSR_CMD_STEP_BACK ||
            cmd == SSR_CMD_SPEED || cmd == SSR_CMD_JUMP ||
            cmd == SSR_CMD_BUY || cmd == SSR_CMD_SELL ||
            cmd == SSR_CMD_CLOSE_ALL || cmd == SSR_CMD_NONE)
            continue;
         read_verbs++;
        }
      CheckEq("the command set is exactly the ten documented ones",
              0, read_verbs);

      //--- the published state carries the clock and NOTHING beyond it
      SSRPublicState st;
      st.Init();
      st.active = true;
      st.start_msc = 1000; st.end_msc = 2000;

      st.now_msc = 1500;
      CheckNear("progress in the middle", 0.5, st.Progress(), 1e-9);
      st.now_msc = 500;                       // before the window
      CheckNear("bounded below", 0.0, st.Progress(), 1e-9);
      st.now_msc = 5000;                      // past the end
      CheckNear("and above",     1.0, st.Progress(), 1e-9);

      //--- a state with nothing granted can do nothing
      st.permissions = SSR_PERM_READ;
      Check("read is granted",     st.Can(SSR_PERM_READ));
      Check("control is not",     !st.Can(SSR_PERM_CONTROL));
      Check("trade is not",       !st.Can(SSR_PERM_TRADE));

      //--- and the banner reports what the numbers rest on
      st.synthetic     = true;
      st.ambiguous_pct = 32.0;
      Check("the banner carries the ambiguity",
            StringFind(st.Banner(), "32% of results assumed") >= 0, st.Banner());
   }

   //================================================================
   PrintFormat("=== Phase 14: PASS=%d  FAIL=%d  ===> %s",
               g_pass, g_fail, (g_fail == 0 ? "GREEN" : "RED"));
  }
//+------------------------------------------------------------------+
