//+------------------------------------------------------------------+
//|                                                   SSR_T15_Ux.mq5 |
//|                       SS Replay - Phase 15 Professional UX       |
//|                                                                  |
//|  UI is usually where honesty is lost, because it is the layer    |
//|  that decides what a person is told. Four ways that happens      |
//|  here, one test each:                                            |
//|                                                                  |
//|   1. Blind Mode hides the date on the chart and the panel prints |
//|      it in the largest font on screen.                           |
//|   2. A BUY button that trades without a stop and calls it "1%".  |
//|   3. A session load that succeeded "with warnings" and showed    |
//|      only the success.                                           |
//|   4. A multi-symbol board whose trade buttons act on one         |
//|      instrument without saying which.                            |
//+------------------------------------------------------------------+
#property script_show_inputs

#include <SSReplay/Common/SSR_Types.mqh>
#include <SSReplay/Common/SSR_Time.mqh>
#include <SSReplay/Core/SSR_ReplayController.mqh>
#include <SSReplay/Core/SSR_MasterClock.mqh>
#include <SSReplay/Core/Sources/SSR_MemoryDataSource.mqh>
#include <SSReplay/Core/Sinks/SSR_RecordingSink.mqh>
#include <SSReplay/Trading/SSR_TradingEngine.mqh>
#include <SSReplay/Trading/SSR_Statistics.mqh>
#include <SSReplay/Chart/SSR_BlindMode.mqh>
#include <SSReplay/Session/SSR_SessionManager.mqh>
#include <SSReplay/Strategy/SSR_StrategyHost.mqh>
#include <SSReplay/Strategy/SSR_RefStrategy.mqh>
#include <SSReplay/Ui/SSR_GroupPort.mqh>
#include <SSReplay/Ui/SSR_Keys.mqh>
#include <SSReplay/Ui/SSR_Panel.mqh>

input datetime InpStart  = D'2024.01.08 00:00';
input int      InpBars   = 4320;
input int      InpWarmup = 60;

int g_pass = 0, g_fail = 0;
void Check(const string n, const bool ok, const string d = "")
  { if(ok) { g_pass++; PrintFormat("  PASS  %s", n); }
    else   { g_fail++; PrintFormat("  FAIL  %s  %s", n, d); } }
void CheckEq(const string n, const long e, const long a)
  { Check(n, e == a, StringFormat("expected=%I64d actual=%I64d", e, a)); }
void CheckStr(const string n, const string e, const string a)
  { Check(n, e == a, StringFormat("expected='%s' actual='%s'", e, a)); }
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

bool Wire(CSSRReplayController &c, CSSRMemoryDataSource &s,
          CSSRRecordingSink &k, const string name, const double base)
  {
   MqlRates bars[];
   BuildBars(bars, InpStart, InpBars, base);
   if(!s.LoadBars(bars, ArraySize(bars)))
      return false;
   k.Clear();
   c.SetSymbolSpec(2, 0.01);
   c.SetTicksPerBar(8);
   c.SetSpreadPoints(0);
   c.SetWarmupBars(InpWarmup);
   c.SetFidelity(SSR_FIDELITY_SYNTHETIC_TICK);
   c.Attach(GetPointer(s), GetPointer(k));
   return c.Load(name, g_start, g_end);
  }

//+------------------------------------------------------------------+
void OnStart()
  {
   g_start = SSRToMsc(InpStart) + (long)InpWarmup * SSR_MSC_PER_MIN;
   g_end   = g_start + 2000 * SSR_MSC_PER_MIN;
   Print("=== SSR Phase 15 - Professional UX ===");

   //================================================================
   Section("T15.1  the panel cannot leak what Blind Mode hides");
   {
      CSSRMemoryDataSource src; CSSRRecordingSink sink;
      CSSRReplayController ctrl; CSSRTradingEngine acct;
      CSSRReplayGroup grp; CSSRGroupPort port; CSSRBlindMode blind;

      ctrl.AddObserver(GetPointer(acct));
      Check("loaded", Wire(ctrl, src, sink, "TEST", 1000.0), ctrl.LastErrorText());
      acct.SetBalance(10000.0);
      grp.Add(GetPointer(ctrl));
      grp.Align();
      port.Attach(GetPointer(grp), NULL, NULL);
      port.AttachAccount(GetPointer(acct));

      grp.Play();
      for(int i = 0; i < 200; i++)
         grp.Pump(1000);

      //--- WITHOUT blind mode the clock is the date
      SSRUiState st;
      Check("state read", port.ReadState(st));
      Check("not blind",  !st.blind);
      Check("and the clock carries the date",
            StringFind(st.clock_text, "2024") >= 0, st.clock_text);

      //--- WITH it, the panel is handed elapsed time and nothing else.
      //--- The port masks; the panel never formats the instant itself,
      //--- so there is no second place to forget.
      SSRBlindPolicy p;
      p.Standard();
      blind.SetPolicy(p);
      port.AttachBlind(GetPointer(blind));

      Check("state read again", port.ReadState(st));
      Check("blind is flagged", st.blind);
      Check("the date is gone from the clock",
            StringFind(st.clock_text, "2024") < 0, st.clock_text);
      Check("and what is left is elapsed time",
            StringFind(st.clock_text, "in") >= 0, st.clock_text);
      CheckStr("the symbol is masked too", "(blind)", st.symbol);

      //--- and the raw instant is STILL in the state, because the
      //--- progress bar needs it. That is fine: what the panel PRINTS
      //--- is what matters, and it prints clock_text.
      Check("the engine's own clock is untouched", st.now_msc > g_start,
            SSRFormatMsc(st.now_msc));
   }

   //================================================================
   Section("T15.2  the trade buttons refuse rather than invent a size");
   {
      CSSRMemoryDataSource src; CSSRRecordingSink sink;
      CSSRReplayController ctrl; CSSRTradingEngine acct;
      CSSRReplayGroup grp; CSSRGroupPort port;

      ctrl.AddObserver(GetPointer(acct));
      Wire(ctrl, src, sink, "TEST", 1000.0);
      acct.SetBalance(10000.0);
      grp.Add(GetPointer(ctrl));
      grp.Align();
      port.Attach(GetPointer(grp), NULL, NULL);
      port.AttachAccount(GetPointer(acct));

      //--- before any price, a trade is refused with a reason
      Check("no trade before the replay has run", !port.Buy());
      Check("and it says why",
            StringFind(port.TradeError(), "no price") >= 0, port.TradeError());

      grp.Play();
      for(int i = 0; i < 100; i++)
         grp.Pump(1000);

      //--- THE POINT OF THIS SECTION. There is no stop, so there is no
      //--- risk figure, so there is no lot size. Every alternative is
      //--- worse than refusing, and the message says which.
      Check("still refused with no stop", !port.Buy());
      Check("and names the reason",
            StringFind(port.TradeError(), "stop") >= 0, port.TradeError());
      CheckEq("nothing was opened", 0, acct.Total());

      //--- give it a stop, and it sizes from the risk
      Check("risk set",  port.SetRiskPercent(1.0));
      Check("stop set",  port.SetStopPoints(200.0));
      Check("now it trades", port.Buy(), port.TradeError());
      CheckEq("one position", 1, acct.Total());

      SSRVirtualPosition pos;
      Check("it exists", acct.At(0, pos));
      Check("with a stop", pos.sl > 0.0, DoubleToString(pos.sl, 2));
      Check("below the entry for a buy", pos.sl < pos.open_price,
            StringFormat("sl=%.2f entry=%.2f", pos.sl, pos.open_price));

      //--- AND THE RISK IS THE RISK THAT WAS ASKED FOR. This is the
      //--- number the whole panel row exists to make true.
      Check("risk at entry was recorded", pos.HasR());
      double want = acct.InitialBalance() * 0.01;
      CheckNear("and it is one percent of the account",
                want, pos.risk_at_entry, want * 0.02);

      //--- refusals that are not silent
      Check("a negative risk is refused",   !port.SetRiskPercent(-1.0));
      Check("and one over 100 percent too", !port.SetRiskPercent(500.0));
      Check("a negative stop is refused",   !port.SetStopPoints(-5.0));

      //--- break even moves the stop to the entry, once there is one
      Check("break even", port.BreakEvenAll(), port.TradeError());
      acct.At(0, pos);
      CheckNear("the stop is now the entry", pos.open_price, pos.sl, 0.01);

      Check("flat closes it", port.CloseAll());
      CheckEq("nothing open", 0, acct.OpenCount());
      Check("and break even now has nothing to do", !port.BreakEvenAll());
   }

   //================================================================
   Section("T15.3  a board says which instrument it trades");
   {
      CSSRMemoryDataSource s1, s2; CSSRRecordingSink k1, k2;
      CSSRReplayController c1, c2; CSSRTradingEngine acct;
      CSSRReplayGroup grp; CSSRGroupPort port;

      c1.AddObserver(GetPointer(acct));
      Wire(c1, s1, k1, "PRIMARY", 1000.0);
      Wire(c2, s2, k2, "SECOND",  2000.0);
      acct.SetBalance(10000.0);
      grp.Add(GetPointer(c1));
      grp.Add(GetPointer(c2));
      Check("aligned", grp.Align(), grp.LastError());
      port.Attach(GetPointer(grp), NULL, NULL);
      port.AttachAccount(GetPointer(acct));

      grp.Play();
      for(int i = 0; i < 50; i++)
         grp.Pump(1000);

      SSRUiState st;
      port.ReadState(st);
      CheckEq("two streams", 2, st.streams);

      //--- THE LIMITATION IS NAMED. The account follows the primary
      //--- stream only; a panel that did not say so would leave a
      //--- trader pressing BUY while looking at the other chart.
      CheckStr("and the trade instrument is named", "PRIMARY", st.trade_symbol);
      Check("the symbol readout marks it as a board",
            StringFind(st.symbol, "+1") >= 0, st.symbol);
      CheckEq("with no skew", 0, st.skew_msc);
   }

   //================================================================
   Section("T15.4  a session that loaded WITH WARNINGS says both");
   {
      CSSRMemoryDataSource src; CSSRRecordingSink sink;
      CSSRReplayController ctrl; CSSRTradingEngine acct; CSSRStatsEngine stats;
      CSSRReplayGroup grp; CSSRGroupPort port; CSSRSessionManager mgr;

      ctrl.AddObserver(GetPointer(acct));
      ctrl.AddObserver(GetPointer(stats));
      Wire(ctrl, src, sink, "TEST", 1000.0);
      acct.SetBalance(10000.0);
      stats.Attach(GetPointer(acct));
      grp.Add(GetPointer(ctrl));
      grp.Align();
      mgr.Attach(GetPointer(grp), GetPointer(acct), GetPointer(stats));
      port.Attach(GetPointer(grp), NULL, NULL);
      port.AttachAccount(GetPointer(acct));
      port.AttachSessions(GetPointer(mgr));

      grp.Play();
      for(int i = 0; i < 100; i++)
         grp.Pump(1000);

      Check("saved through the port", port.SaveSession("t15"), port.SessionError());

      //--- the list shows what EXISTS, with what each file holds
      int n = port.SessionCount();
      Check("the list has it", n > 0, IntegerToString(n));
      int found = -1;
      for(int i = 0; i < n; i++)
         if(port.SessionName(i) == "t15")
            found = i;
      Check("by name", found >= 0);
      Check("and the row says what is in it",
            StringFind(port.SessionSummary(found), "TEST") >= 0,
            port.SessionSummary(found));

      //--- loading it back into the same board is clean
      Check("loaded", port.LoadSession("t15"), port.SessionError());
      CheckStr("with nothing to report", "", port.SessionError());

      //--- NOW THE CASE THAT MATTERS. Rebuild on revised bars: the
      //--- load succeeds and the change is reported. A dialog showing
      //--- only "loaded" would have undone the whole fingerprint.
      CSSRMemoryDataSource src2; CSSRRecordingSink sink2;
      CSSRReplayController ctrl2; CSSRTradingEngine acct2;
      CSSRReplayGroup grp2; CSSRGroupPort port2; CSSRSessionManager mgr2;

      ctrl2.AddObserver(GetPointer(acct2));
      MqlRates revised[];
      BuildBars(revised, InpStart, InpBars, 1000.0);
      for(int i = 0; i < ArraySize(revised); i++)
         revised[i].high += 0.01;         // one tick, everywhere
      src2.LoadBars(revised, ArraySize(revised));
      ctrl2.SetSymbolSpec(2, 0.01);
      ctrl2.SetTicksPerBar(8);
      ctrl2.SetSpreadPoints(0);
      ctrl2.SetWarmupBars(InpWarmup);
      ctrl2.SetFidelity(SSR_FIDELITY_SYNTHETIC_TICK);
      ctrl2.Attach(GetPointer(src2), GetPointer(sink2));
      Check("rebuilt", ctrl2.Load("TEST", g_start, g_end), ctrl2.LastErrorText());
      acct2.SetBalance(10000.0);
      grp2.Add(GetPointer(ctrl2));
      grp2.Align();
      mgr2.Attach(GetPointer(grp2), GetPointer(acct2), NULL);
      port2.Attach(GetPointer(grp2), NULL, NULL);
      port2.AttachSessions(GetPointer(mgr2));

      Check("it still loads", port2.LoadSession("t15"), "(refused!)");
      Check("BUT the change is carried out to the UI",
            StringLen(port2.SessionError()) > 0, "(silent!)");
      Check("and named as a revision",
            StringFind(port2.SessionError(), "revised") >= 0,
            port2.SessionError());

      //--- a name that is not there fails with a reason
      Check("an unknown session fails", !port2.LoadSession("no_such_thing"));
      Check("readably", StringLen(port2.SessionError()) > 5,
            port2.SessionError());
      Check("and an empty name is refused", !port2.SaveSession(""));

      mgr.Delete("t15");
   }

   //================================================================
   Section("T15.5  a port with nothing attached offers nothing");
   {
      //--- The panel greys its buttons from the STATE, not from
      //--- knowing which port it is talking to. So a bare port must
      //--- report itself as unable rather than throwing when pressed.
      CSSRReplayGroup grp;
      CSSRGroupPort port;
      port.Attach(GetPointer(grp), NULL, NULL);

      SSRUiState st;
      Check("nothing to read", !port.ReadState(st));
      Check("cannot trade",   !st.can_trade);
      Check("buy refused",    !port.Buy());
      Check("sell refused",   !port.Sell());
      Check("flat refused",   !port.CloseAll());
      Check("break even refused", !port.BreakEvenAll());
      Check("with a reason each time", StringLen(port.TradeError()) > 0,
            port.TradeError());

      CheckEq("no sessions to list", 0, port.SessionCount());
      Check("saving is refused",  !port.SaveSession("x"));
      Check("loading is refused", !port.LoadSession("x"));
      Check("and says sessions are unavailable",
            StringFind(port.SessionError(), "not available") >= 0,
            port.SessionError());
   }

   //================================================================
   Section("T15.6  strategy state reaches the panel");
   {
      CSSRTradingEngine acct;
      CSSRMarketView view;
      CSSRStrategyHost host;
      CSSRReplayGroup grp;
      CSSRGroupPort port;
      CSSRRefBreakout ref;

      host.Attach(GetPointer(view), GetPointer(acct));
      host.Add(GetPointer(ref), PERIOD_M15);
      port.Attach(GetPointer(grp), NULL, NULL);
      port.AttachStrategies(GetPointer(host));

      //--- one strategy: its own line, by name
      Check("the line names it",
            StringFind(port.StrategyLine(), "ref-breakout") >= 0,
            port.StrategyLine());

      //--- and it carries what the strategy is THINKING, not just that
      //--- it exists. A row saying "running" tells a user nothing.
      Check("and what it is doing",
            StringFind(port.StrategyLine(), ":") >= 0, port.StrategyLine());

      //--- a second strategy under the same name is refused, so its
      //--- results could never be confused with the first's
      CSSRRefBreakout other;
      other.Configure(PERIOD_H1, 10, 1.0);
      Check("a duplicate name is refused", !host.Add(GetPointer(other), PERIOD_H1));
      CheckEq("still one", 1, host.Count());

      //--- no strategies at all is an EMPTY line, not "0 strategies".
      //--- The panel is silent when there is nothing to say.
      CSSRStrategyHost none;
      CSSRGroupPort port3;
      port3.Attach(GetPointer(grp), NULL, NULL);
      port3.AttachStrategies(GetPointer(none));
      CheckStr("silence when there are none", "", port3.StrategyLine());
   }

   //================================================================
   Section("T15.7  the session key is mapped and does not collide");
   {
      CheckEq("S opens the session list", SSR_CMD_SESSIONS,
              SSRKeyToCommand(SSR_VK_S));
      Check("and the other keys still mean what they did",
            SSRKeyToCommand(SSR_VK_SPACE) == SSR_CMD_TOGGLE &&
            SSRKeyToCommand(SSR_VK_J)     == SSR_CMD_JUMP &&
            SSRKeyToCommand(SSR_VK_B)     == SSR_CMD_BOOKMARK &&
            SSRKeyToCommand(SSR_VK_R)     == SSR_CMD_RESET);
      Check("the hint mentions it",
            StringFind(SSRKeyHint(), "S sessions") >= 0, SSRKeyHint());
   }

   //================================================================
   Section("T15.8  the panel takes the keyboard away from MetaTrader");
   {
      //--- THE ASSERTION THAT WOULD HAVE CAUGHT IT.
      //---
      //--- MetaTrader opens a quick-navigation text box when SPACE is
      //--- pressed on a chart, and SPACE is this product's play key.
      //--- Every key after that went into the box instead of the EA, so
      //--- the replay stopped answering and read as frozen.
      //---
      //--- Fifteen phases and 1,159 assertions never saw it, because
      //--- every one of them tested logic and none of them touched a
      //--- chart's own behaviour. Thirty seconds of real use found it.
      //--- So the fix arrives with the test that was missing.
      long chart = ChartID();
      long was_nav = ChartGetInteger(chart, CHART_QUICK_NAVIGATION);
      long was_key = ChartGetInteger(chart, CHART_KEYBOARD_CONTROL);

      CSSRGroupPort port;
      CSSRPanel     panel;
      panel.Create(chart, GetPointer(port), "T15_kbd_");

      CheckEq("quick navigation is off while the panel lives",
              0, ChartGetInteger(chart, CHART_QUICK_NAVIGATION));
      CheckEq("the chart no longer steals the arrows",
              0, ChartGetInteger(chart, CHART_KEYBOARD_CONTROL));

      panel.Destroy();

      //--- and the chart the user gets back is the chart they had
      CheckEq("quick navigation is given back",
              was_nav, ChartGetInteger(chart, CHART_QUICK_NAVIGATION));
      CheckEq("keyboard control is given back",
              was_key, ChartGetInteger(chart, CHART_KEYBOARD_CONTROL));
   }

   //================================================================
   Section("T15.9  a dragged panel takes its labels with it");
   {
      //--- The text cache was keyed on the text alone, so moving the
      //--- panel left every unchanged label exactly where it was while
      //--- the buttons followed the mouse. The panel tore in half.
      //--- A cache is only safe when it remembers everything that
      //--- would have changed the write - including where it goes.
      CSSRGroupPort port2;
      CSSRPanel     panel2;
      panel2.Create(ChartID(), GetPointer(port2), "T15_move_");

      //--- the panel moves by CORNER now, not by coordinate: it lives on
      //--- a chart whose mouse events this program never receives, so
      //--- there is nothing to drag it with. The bug the cache caused is
      //--- the same either way - a label that stays behind when the
      //--- panel goes - so the test still asks the same question.
      panel2.SetCorner(0);                       // top-left
      long x_before = ObjectGetInteger(ChartID(), "T15_move_stbal",
                                       OBJPROP_XDISTANCE);

      panel2.SetCorner(1);                       // top-right
      long x_after = ObjectGetInteger(ChartID(), "T15_move_stbal",
                                      OBJPROP_XDISTANCE);

      Check("the label moved with the panel", x_after != x_before,
            StringFormat("before=%d after=%d (both would mean a stranded label)",
                         (int)x_before, (int)x_after));
      Check("and it moved to the right, with the panel",
            x_after > x_before,
            StringFormat("%d -> %d", (int)x_before, (int)x_after));

      panel2.Destroy();
   }

   //================================================================
   Section("T15.10  the panel lets the host's own keys through");
   {
      //--- The panel returned "handled" for every key it could map,
      //--- including the two it does not implement. The host checks the
      //--- panel first and stops when it claims an event, so S and J
      //--- were swallowed and their dialogs never opened. Nothing was
      //--- broken except who answered.
      CSSRGroupPort port3;
      CSSRPanel     panel3;
      panel3.Create(ChartID(), GetPointer(port3), "T15_own_");

      double dummy_f = 0;
      string dummy_s = "";

      long key_s = SSR_VK_S, key_j = SSR_VK_J, key_space = SSR_VK_SPACE;

      Check("S is passed to the host",
            !panel3.OnEvent(CHARTEVENT_KEYDOWN, key_s, dummy_f, dummy_s),
            "true here means the session list never opens");
      Check("J is passed to the host",
            !panel3.OnEvent(CHARTEVENT_KEYDOWN, key_j, dummy_f, dummy_s),
            "true here means the range dialog never opens");
      Check("but the panel still claims its own keys",
            panel3.OnEvent(CHARTEVENT_KEYDOWN, key_space, dummy_f, dummy_s),
            "play/pause is the panel's to run");

      panel3.Destroy();
   }

   //================================================================
   PrintFormat("=== Phase 15: PASS=%d  FAIL=%d  ===> %s",
               g_pass, g_fail, (g_fail == 0 ? "GREEN" : "RED"));
  }
//+------------------------------------------------------------------+
