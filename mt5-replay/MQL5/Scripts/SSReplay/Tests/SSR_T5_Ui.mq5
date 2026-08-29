//+------------------------------------------------------------------+
//|                                                     SSR_T5_Ui.mq5 |
//|                              SS Replay - Phase 5 UI Tests        |
//|                                                                  |
//|  Three things are worth asserting about a UI in code:            |
//|    - it contains no logic of its own                             |
//|    - a click and a key take the same path                        |
//|    - it leaves nothing behind when it goes                       |
//|  Looks are judged by eye; these are not.                         |
//+------------------------------------------------------------------+
#property script_show_inputs

#include <SSReplay/Common/SSR_Types.mqh>
#include <SSReplay/Common/SSR_Time.mqh>
#include <SSReplay/Ui/SSR_Panel.mqh>
#include <SSReplay/Ui/SSR_Keys.mqh>
#include <SSReplay/Ui/SSR_Theme.mqh>

int g_pass = 0, g_fail = 0;
void Check(const string n, const bool ok, const string d = "")
  { if(ok) { g_pass++; PrintFormat("  PASS  %s", n); }
    else   { g_fail++; PrintFormat("  FAIL  %s  %s", n, d); } }
void CheckEq(const string n, const long e, const long a)
  { Check(n, e == a, StringFormat("expected=%I64d actual=%I64d", e, a)); }
void Section(const string t) { PrintFormat("--- %s", t); }

//+------------------------------------------------------------------+
//| A port that records what it was asked to do and answers with a    |
//| state the test controls. No engine, no terminal, no broker.       |
//+------------------------------------------------------------------+
class CFakePort : public CSSRReplayPort
  {
public:
   SSRUiState state;
   int play, pause, reset, step, seek, speed, fidelity, follow, hide;
   //--- Phase 8 added three verbs to the port and this fake was never
   //--- brought up to them, which left it ABSTRACT: the class could
   //--- not be instantiated and this whole file could not compile.
   //--- Found by the Phase 16 audit, not by any brace count.
   int back, restart, jump;
   int last_step_bars, last_back_bars;
   long last_jump_msc;
   long last_speed;
   ENUM_SSR_FIDELITY last_fidelity;

        CFakePort(void) { Clear(); state.Init(); state.connected = true; }

   void Clear(void)
     {
      play = pause = reset = step = seek = speed = fidelity = follow = hide = 0;
      back = restart = jump = 0;
      last_step_bars = 0; last_back_bars = 0; last_jump_msc = 0;
      last_speed = 0; last_fidelity = SSR_FIDELITY_BAR;
     }

   virtual string Name(void) override        { return "fake"; }
   virtual bool   IsConnected(void) override { return true; }
   virtual bool   ReadState(SSRUiState &out) override { out = state; return true; }

   virtual bool   Play(void) override  { play++;  state.status = SSR_STATE_PLAYING; return true; }
   virtual bool   Pause(void) override { pause++; state.status = SSR_STATE_PAUSED;  return true; }
   virtual bool   Reset(void) override { reset++; state.status = SSR_STATE_READY;   return true; }
   virtual bool   StepBars(const int b) override { step++; last_step_bars = b; return true; }
   virtual bool   SeekTo(const long m) override  { seek++; return true; }
   virtual bool   StepBack(const int b) override
     { back++; last_back_bars = b; return true; }
   virtual bool   JumpTo(const long m) override
     { jump++; last_jump_msc = m; return true; }
   virtual bool   Restart(void) override { restart++; return true; }
   virtual bool   SetSpeedX100(const long s) override
     { speed++; last_speed = s; state.speed_x100 = s; return true; }
   virtual bool   SetFidelity(const ENUM_SSR_FIDELITY f) override
     { fidelity++; last_fidelity = f; state.fidelity = f; return true; }
   virtual bool   FollowCharts(void) override { follow++; return true; }
   virtual bool   HideOriginSymbol(void) override { hide++; return true; }
  };

//+------------------------------------------------------------------+
void OnStart()
  {
   Print("=== SSR Phase 5 - Replay UI ===");

   //================================================================
   Section("T5.1  keyboard maps to commands, not to actions");
   {
      CheckEq("SPACE toggles",      SSR_CMD_TOGGLE,         SSRKeyToCommand(SSR_VK_SPACE));
      CheckEq("RIGHT steps",        SSR_CMD_STEP_FWD,       SSRKeyToCommand(SSR_VK_RIGHT));
      CheckEq("PgDn steps ten",     SSR_CMD_STEP_FWD_10,    SSRKeyToCommand(SSR_VK_PGDN));
      CheckEq("R resets",           SSR_CMD_RESET,          SSRKeyToCommand(SSR_VK_R));
      CheckEq("F follows",          SSR_CMD_FOLLOW,         SSRKeyToCommand(SSR_VK_F));
      CheckEq("D cycles fidelity",  SSR_CMD_FIDELITY_CYCLE, SSRKeyToCommand(SSR_VK_D));
      CheckEq("+ speeds up",        SSR_CMD_SPEED_UP,       SSRKeyToCommand(SSR_VK_PLUS));
      CheckEq("numpad + also",      SSR_CMD_SPEED_UP,       SSRKeyToCommand(SSR_VK_NUMPLUS));
      CheckEq("- slows down",       SSR_CMD_SPEED_DOWN,     SSRKeyToCommand(SSR_VK_MINUS));

      //--- LEFT WAS unbound on purpose, until Phase 8 gave it a real
      //--- rewind to be bound to. This assertion outlived that: it went
      //--- on demanding silence from a key that had done something for
      //--- seven phases, while T8.1 two files over asserted the
      //--- opposite. A test that contradicts another test is not a
      //--- second opinion; one of them is stale, and this was it.
      CheckEq("LEFT steps back", SSR_CMD_STEP_BACK, SSRKeyToCommand(SSR_VK_LEFT));
      CheckEq("unknown keys are ignored",     SSR_CMD_NONE, SSRKeyToCommand(999));
   }

   //================================================================
   Section("T5.2  the speed ladder");
   {
      CheckEq("ladder has eight steps", 8, SSR_SPEED_LADDER_SIZE);
      CheckEq("slowest is 0.25x", SSR_SPEED_025, SSRSpeedLadder(0));
      CheckEq("fastest is 50x",   SSR_SPEED_50,  SSRSpeedLadder(7));
      CheckEq("1x sits at index 2", 2, SSRSpeedLadderIndex(SSR_SPEED_1));

      bool ascending = true;
      for(int i = 1; i < SSR_SPEED_LADDER_SIZE; i++)
         if(SSRSpeedLadder(i) <= SSRSpeedLadder(i - 1))
            ascending = false;
      Check("ladder ascends", ascending);
      Check("names render", SSRSpeedName(SSR_SPEED_025) != "" &&
                            SSRSpeedName(SSR_SPEED_50) != "");
   }

   //================================================================
   Section("T5.3  the panel holds no logic of its own");

   CFakePort port;
   CSSRPanel panel;
   long cid = ChartID();
   panel.Create(cid, GetPointer(port), "SSRT5_");

   {
      port.state.status = SSR_STATE_READY;
      port.Clear();

      //--- every verb must reach the port; if the panel decided anything
      //--- itself, one of these counters would stay at zero
      panel.Render();
      Check("play reaches the port",  panel.Execute(SSR_CMD_PLAY)  && port.play == 1);
      panel.Render();
      Check("pause reaches the port", panel.Execute(SSR_CMD_PAUSE) && port.pause == 1);
      Check("reset reaches the port", panel.Execute(SSR_CMD_RESET) && port.reset == 1);

      Check("step reaches the port", panel.Execute(SSR_CMD_STEP_FWD));
      CheckEq("one bar requested", 1, port.last_step_bars);
      Check("ten-step reaches the port", panel.Execute(SSR_CMD_STEP_FWD_10));
      CheckEq("ten bars requested", 10, port.last_step_bars);

      Check("follow reaches the port", panel.Execute(SSR_CMD_FOLLOW) && port.follow == 1);
   }

   //================================================================
   Section("T5.4  toggle reads state rather than remembering it");
   {
      port.Clear();
      port.state.status = SSR_STATE_PAUSED;
      panel.Render();
      panel.Execute(SSR_CMD_TOGGLE);
      CheckEq("paused -> play", 1, port.play);

      port.Clear();
      port.state.status = SSR_STATE_PLAYING;
      panel.Render();
      panel.Execute(SSR_CMD_TOGGLE);
      CheckEq("playing -> pause", 1, port.pause);
   }

   //================================================================
   Section("T5.5  speed and fidelity walk their ranges");
   {
      port.Clear();
      port.state.speed_x100 = SSR_SPEED_1;
      panel.Render();
      panel.Execute(SSR_CMD_SPEED_UP);
      CheckEq("one step faster", SSR_SPEED_2, port.last_speed);

      port.state.speed_x100 = SSR_SPEED_50;
      panel.Render();
      panel.Execute(SSR_CMD_SPEED_UP);
      CheckEq("cannot exceed the top", SSR_SPEED_50, port.last_speed);

      port.state.speed_x100 = SSR_SPEED_025;
      panel.Render();
      panel.Execute(SSR_CMD_SPEED_DOWN);
      CheckEq("cannot go below the bottom", SSR_SPEED_025, port.last_speed);

      port.state.fidelity = SSR_FIDELITY_FULL_TICK;
      panel.Render();
      panel.Execute(SSR_CMD_FIDELITY_CYCLE);
      CheckEq("full -> synthetic", SSR_FIDELITY_SYNTHETIC_TICK, port.last_fidelity);
      panel.Render();
      panel.Execute(SSR_CMD_FIDELITY_CYCLE);
      CheckEq("synthetic -> bar", SSR_FIDELITY_BAR, port.last_fidelity);
      panel.Render();
      panel.Execute(SSR_CMD_FIDELITY_CYCLE);
      CheckEq("bar wraps to full", SSR_FIDELITY_FULL_TICK, port.last_fidelity);
   }

   //================================================================
   Section("T5.6  a click and a key take the same path");
   {
      port.Clear();
      port.state.status = SSR_STATE_READY;
      panel.Render();

      long   l = 0;
      double d = 0;
      string s = "SSRT5_play";
      panel.OnEvent(CHARTEVENT_OBJECT_CLICK, l, d, s);
      CheckEq("click reached the port", 1, port.play);

      port.Clear();
      panel.Render();
      long key = SSR_VK_SPACE;
      string empty = "";
      panel.OnEvent(CHARTEVENT_KEYDOWN, key, d, empty);
      Check("key reached the port too", port.play + port.pause == 1);

      //--- an object that is not ours must be left alone
      port.Clear();
      string foreign = "SomeUserObject";
      Check("foreign objects ignored",
            !panel.OnEvent(CHARTEVENT_OBJECT_CLICK, l, d, foreign));
      CheckEq("nothing was sent", 0, port.play + port.pause + port.reset);
   }

   //================================================================
   Section("T5.7  rendering is cheap when nothing changed");
   {
      port.state.status  = SSR_STATE_PAUSED;
      port.state.now_msc = SSRToMsc(D'2024.01.08 10:37');
      panel.Render();
      int w0 = panel.Writes();
      for(int i = 0; i < 20; i++)
         panel.Render();
      int spent = panel.Writes() - w0;
      Check("twenty identical renders wrote almost nothing", spent <= 2,
            StringFormat("%d label writes", spent));

      //+------------------------------------------------------------------+
      //| CHANGE WHAT THE PANEL ACTUALLY RENDERS.                        |
      //|                                                                |
      //| This bumped now_msc and expected the clock label to be         |
      //| rewritten. The panel does not format the clock from the        |
      //| instant - it prints clock_text, which the port hands over       |
      //| already masked when the session is blind. That is deliberate:  |
      //| a panel that formatted the instant itself would be a second    |
      //| place that has to know about Blind Mode, and the one that gets |
      //| forgotten, printing the date in the largest font on screen.    |
      //|                                                                |
      //| So the test was asserting against a design the product had     |
      //| deliberately moved away from, and the panel was right.         |
      //+------------------------------------------------------------------+
      port.state.now_msc   += 60000;
      port.state.clock_text = "2024.01.08 10:38:00";
      panel.Render();
      Check("a changed clock is written", panel.Writes() > w0 + spent,
            StringFormat("%d writes after %d", panel.Writes(), w0 + spent));
   }

   //================================================================
   Section("T5.8  collapse and teardown");
   {
      Check("starts expanded", !panel.IsCollapsed());
      panel.Execute(SSR_CMD_COLLAPSE);
      Check("collapses", panel.IsCollapsed());
      panel.Execute(SSR_CMD_COLLAPSE);
      Check("expands again", !panel.IsCollapsed());

      Check("panel owns objects", panel.ObjectCount() > 0,
            IntegerToString(panel.ObjectCount()));
      panel.Destroy();
      CheckEq("teardown leaves nothing on the chart", 0, panel.ObjectCount());
   }

   //================================================================
   Section("T5.9  state colours are distinct where meaning differs");
   {
      Check("running and paused differ",
            SSRStateColor(SSR_STATE_PLAYING) != SSRStateColor(SSR_STATE_PAUSED));
      Check("error stands apart",
            SSRStateColor(SSR_STATE_ERROR) != SSRStateColor(SSR_STATE_PLAYING));
      //--- the user must be able to see they are on approximated ticks
      Check("real ticks look different from synthetic",
            SSRFidelityColor(SSR_FIDELITY_FULL_TICK) !=
            SSRFidelityColor(SSR_FIDELITY_SYNTHETIC_TICK));
   }

   //================================================================
   Section("T5.9  the navigation verbs reach the port");
   {
      //--- ADDED IN PHASE 16. Phase 8 put StepBack, JumpTo and Restart
      //--- on the port and this fake was never brought up to them,
      //--- which left it abstract and this whole file uncompilable.
      //--- The assertions below exist so that cannot happen silently
      //--- again: they will not link unless the verbs are implemented.
      CFakePort p59;
      CSSRPanel panel59;
      panel59.Create(cid, GetPointer(p59), "SSRT59_");

      //--- OnEvent takes lparam BY REFERENCE, as MetaTrader hands it
      //--- over, so a literal cannot be passed. The sections above
      //--- already knew that; this one was written without looking.
      long   k59 = 0;
      double d59 = 0.0;
      string s59 = "";

      p59.state.status = SSR_STATE_PAUSED;
      k59 = SSR_VK_LEFT;
      panel59.OnEvent(CHARTEVENT_KEYDOWN, k59, d59, s59);
      CheckEq("LEFT stepped back", 1, p59.back);
      CheckEq("by one bar",        1, p59.last_back_bars);

      k59 = SSR_VK_PGUP;
      panel59.OnEvent(CHARTEVENT_KEYDOWN, k59, d59, s59);
      CheckEq("PgUp stepped back again", 2, p59.back);
      CheckEq("by ten bars",            10, p59.last_back_bars);

      Check("the port can be jumped", p59.JumpTo(123456789));
      CheckEq("which was recorded",   123456789, p59.last_jump_msc);
      Check("and restarted", p59.Restart());
      CheckEq("counted", 1, p59.restart);

      panel59.Destroy();
   }

   //================================================================
   ChartRedraw(cid);
   PrintFormat("=== Phase 5: PASS=%d  FAIL=%d  ===> %s",
               g_pass, g_fail, (g_fail == 0 ? "GREEN" : "RED"));
  }
//+------------------------------------------------------------------+
