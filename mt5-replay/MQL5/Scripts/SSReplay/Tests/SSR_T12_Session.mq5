//+------------------------------------------------------------------+
//|                                              SSR_T12_Session.mq5 |
//|                        SS Replay - Phase 12 Session System       |
//|                                                                  |
//|  A session file is only worth anything if what comes back is     |
//|  what went in. Four ways that is quietly false, one test each:   |
//|                                                                  |
//|  1. A number that round trips to nearly itself. A balance a cent |
//|     short after a save is a bug nobody finds for months, so the  |
//|     money is compared exactly.                                   |
//|  2. Trades that come back without their partial exits, so the    |
//|     restored session cannot step back over its own history.      |
//|  3. Statistics stored alongside the trades they came from, and   |
//|     believed over them when the two disagree.                    |
//|  4. A resume against broker history that has changed since the   |
//|     save - the trader reviewing a decision on a chart the        |
//|     decision was never made on.                                  |
//+------------------------------------------------------------------+
#property script_show_inputs

#include <SSReplay/Common/SSR_Types.mqh>
#include <SSReplay/Common/SSR_Time.mqh>
#include <SSReplay/Common/SSR_SessionFile.mqh>
#include <SSReplay/Common/SSR_Fingerprint.mqh>
#include <SSReplay/Core/SSR_ReplayController.mqh>
#include <SSReplay/Core/SSR_MasterClock.mqh>
#include <SSReplay/Core/Sources/SSR_MemoryDataSource.mqh>
#include <SSReplay/Core/Sinks/SSR_RecordingSink.mqh>
#include <SSReplay/Trading/SSR_TradingEngine.mqh>
#include <SSReplay/Trading/SSR_Statistics.mqh>
#include <SSReplay/Trading/SSR_AutoPause.mqh>
#include <SSReplay/Session/SSR_SessionManager.mqh>

input datetime InpStart  = D'2024.01.08 00:00';
input int      InpBars   = 4320;
input double   InpBase   = 1000.0;
input int      InpWarmup = 60;

int g_pass = 0, g_fail = 0;
void Check(const string n, const bool ok, const string d = "")
  { if(ok) { g_pass++; PrintFormat("  PASS  %s", n); }
    else   { g_fail++; PrintFormat("  FAIL  %s  %s", n, d); } }
void CheckEq(const string n, const long e, const long a)
  { Check(n, e == a, StringFormat("expected=%I64d actual=%I64d", e, a)); }
void CheckStr(const string n, const string e, const string a)
  { Check(n, e == a, StringFormat("expected='%s' actual='%s'", e, a)); }
void CheckExact(const string n, const double e, const double a)
  { Check(n, e == a, StringFormat("expected=%.10f actual=%.10f", e, a)); }
void CheckNear(const string n, const double e, const double a, const double tol)
  { Check(n, MathAbs(e - a) <= tol, StringFormat("expected=%.6f actual=%.6f", e, a)); }
void Section(const string t) { PrintFormat("--- %s", t); }

long g_start = 0, g_end = 0;

void BuildBars(MqlRates &out[], const datetime start, const int count,
               const double base, const double range)
  {
   ArrayResize(out, count);
   for(int i = 0; i < count; i++)
     {
      out[i].time  = start + i * 60;
      out[i].open  = base;  out[i].close = base;
      out[i].high  = base + range;
      out[i].low   = base - range;
      out[i].tick_volume = 10; out[i].spread = 2; out[i].real_volume = 0;
     }
  }

bool Wire(CSSRReplayController &c, CSSRMemoryDataSource &s, CSSRRecordingSink &k,
          const string name, const double base, const double range = 5.0)
  {
   MqlRates rates[];
   BuildBars(rates, InpStart, InpBars, base, range);
   if(!s.LoadBars(rates, ArraySize(rates)))
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
   Print("=== SSR Phase 12 - Session System ===");

   //================================================================
   Section("T12.1  the file format: sections, repeats, and refusals");
   {
      CSSRSessionFile w;
      Check("created", w.Create("SSReplay\\test_fmt.ssr"), w.LastError());
      w.Section("alpha");
      w.Set("name", "hello");
      w.SetLong("big", 9007199254740993);
      w.SetDouble("money", 12345.67, 2);
      w.SetBool("yes", true);
      w.SetBool("no", false);
      w.Section("row");
      for(int i = 0; i < 5; i++)
         w.Set("r", StringFormat("%d|value %d", i, i));
      w.Section("alpha");                    // a second section, same name
      w.Set("name", "second");
      w.Close();

      CSSRSessionFile r;
      Check("loaded", r.Load("SSReplay\\test_fmt.ssr"), r.LastError());
      CheckEq("format recorded", SSR_SF_FORMAT, r.Format());
      CheckEq("two sections share a name", 2, r.SectionCount("alpha"));

      Check("first selected", r.Select("alpha", 0));
      CheckStr("string round trips", "hello", r.Get("name"));
      CheckEq("a long past 2^53 survives", 9007199254740993, r.GetLong("big"));
      CheckExact("and money is exact", 12345.67, r.GetDouble("money"));
      Check("true is true",  r.GetBool("yes"));
      Check("false is false", !r.GetBool("no"));
      CheckStr("a missing key gives the default", "fallback",
               r.Get("nothing", "fallback"));

      Check("second selected", r.Select("alpha", 1));
      CheckStr("and it is the other one", "second", r.Get("name"));

      Check("rows selected", r.Select("row"));
      CheckEq("five repeats of one key", 5, r.Count("r"));
      CheckStr("in order", "3|value 3", r.GetNth("r", 3));
      string cells[];
      CheckEq("a packed row unpacks", 2, SSRUnpack(r.GetNth("r", 2), cells));
      CheckEq("field 0", 2, SSRFieldLong(cells, 0));
      CheckStr("field 1", "value 2", SSRField(cells, 1));
      CheckStr("and past the end is the default", "-", SSRField(cells, 9, "-"));

      //--- a separator inside a value must not forge a column
      CheckStr("a pipe in a field is neutralised", "a/b",
               SSRPackAdd("", "a|b"));

      //--- A NEWER FORMAT IS REFUSED, not read as best we can
      int h = FileOpen("SSReplay\\test_future.ssr", FILE_WRITE|FILE_TXT|FILE_ANSI);
      if(h != INVALID_HANDLE)
        {
         FileWriteString(h, "# SS Replay session file\r\n");
         FileWriteString(h, StringFormat("# format %d\r\n", SSR_SF_FORMAT + 7));
         FileWriteString(h, "[alpha]\r\nname=x\r\n");
         FileClose(h);
        }
      CSSRSessionFile fut;
      Check("a newer file is refused", !fut.Load("SSReplay\\test_future.ssr"));
      Check("and says why",
            StringFind(fut.LastError(), "newer build") >= 0, fut.LastError());

      //--- and something that is not one of ours at all
      h = FileOpen("SSReplay\\test_junk.ssr", FILE_WRITE|FILE_TXT|FILE_ANSI);
      if(h != INVALID_HANDLE)
        { FileWriteString(h, "hello world\r\n"); FileClose(h); }
      CSSRSessionFile junk;
      Check("junk is refused", !junk.Load("SSReplay\\test_junk.ssr"));
      Check("named as not ours",
            StringFind(junk.LastError(), "no format line") >= 0, junk.LastError());

      FileDelete("SSReplay\\test_fmt.ssr");
      FileDelete("SSReplay\\test_future.ssr");
      FileDelete("SSReplay\\test_junk.ssr");
   }

   //================================================================
   Section("T12.2  the fingerprint notices history that changed");
   {
      MqlRates a[], b[];
      BuildBars(a, InpStart, 500, 1000.0, 5.0);

      SSRFingerprint f1, f2;
      SSRFingerprintBars(a, 500, 2, f1);
      Check("a fingerprint was taken", f1.IsValid(), f1.ToString());

      //--- the same bars, read again
      BuildBars(b, InpStart, 500, 1000.0, 5.0);
      SSRFingerprintBars(b, 500, 2, f2);
      Check("identical data matches", f1.Equals(f2));
      CheckStr("with nothing to report", "", f1.DiffText(f2));

      //--- ONE price revised, in the middle, by one tick
      b[250].high += 0.01;
      SSRFingerprintBars(b, 500, 2, f2);
      Check("one revised print is caught", !f1.Equals(f2));
      Check("and named as a revision",
            StringFind(f1.DiffText(f2), "revised") >= 0, f1.DiffText(f2));

      //--- bars appearing, as when a broker back-fills a gap
      BuildBars(b, InpStart, 511, 1000.0, 5.0);
      SSRFingerprintBars(b, 511, 2, f2);
      Check("extra bars are caught", !f1.Equals(f2));
      Check("and counted",
            StringFind(f1.DiffText(f2), "+11") >= 0, f1.DiffText(f2));

      //--- the range moving under us
      BuildBars(b, InpStart + 3600, 500, 1000.0, 5.0);
      SSRFingerprintBars(b, 500, 2, f2);
      Check("a moved range is caught", !f1.Equals(f2));
      Check("and described as moved",
            StringFind(f1.DiffText(f2), "moved") >= 0, f1.DiffText(f2));

      //--- and the digest survives the file round trip. Half of all
      //--- digests exceed the signed maximum; writing them unsigned
      //--- would make every one of those sessions cry wolf.
      SSRFingerprint packed;
      Check("unpacked", SSRFingerprintUnpack(SSRFingerprintPack(f1), packed));
      Check("and is bit-identical", f1.Equals(packed),
            f1.ToString() + " vs " + packed.ToString());

      SSRFingerprint big;
      big.Init();
      big.bars = 10; big.first_msc = 1; big.last_msc = 2;
      big.digest = 0xFFFFFFFFFFFFFFF0;          // past the signed maximum
      SSRFingerprint back;
      Check("a huge digest unpacks", SSRFingerprintUnpack(SSRFingerprintPack(big), back));
      Check("without wrapping", big.Equals(back),
            SSRFingerprintPack(big) + " vs " + SSRFingerprintPack(back));
   }

   //================================================================
   Section("T12.3  the account round trips - trades, legs and money");
   {
      CSSRMemoryDataSource src; CSSRRecordingSink sink;
      CSSRReplayController ctrl; CSSRTradingEngine acct;

      //--- BEFORE Load: an observer added afterwards never receives
      //--- OnSessionStart, so the account would price every trade
      //--- against default symbol specs instead of this instrument's
      ctrl.AddObserver(GetPointer(acct));
      Check("loaded", Wire(ctrl, src, sink, "TEST", 1000.0), ctrl.LastErrorText());
      SSRExecutionModel ex;
      ex.Init();
      ex.commission_per_lot = 3.5;
      ex.swap_long_per_lot  = -1.25;
      acct.SetExecution(ex);
      acct.SetBalance(10000.0);
      acct.SetMarginPerLot(1000.0);
      acct.SetStopoutLevel(50.0);

      ctrl.Play();
      for(int i = 0; i < 30; i++)
         ctrl.Pump(1000);

      //--- a scaled-out winner, a runner, and a pending order
      long t1 = acct.Open(SSR_ORDER_BUY, 2.0, 990.0, 0.0, 0.0, "scaled");
      Check("opened", t1 > 0, acct.LastError());
      for(int i = 0; i < 30; i++)
         ctrl.Pump(1000);
      Check("scaled out", acct.ClosePartial(t1, 1.0), acct.LastError());
      for(int i = 0; i < 30; i++)
         ctrl.Pump(1000);
      acct.Close(t1);

      long t2 = acct.Open(SSR_ORDER_BUY, 1.0, 900.0, 1200.0, 0.0, "runner");
      long t3 = acct.Open(SSR_ORDER_BUY_LIMIT, 1.0, 0.0, 0.0, 900.0, "waiting");
      for(int i = 0; i < 20; i++)
         ctrl.Pump(1000);

      double bal   = acct.Balance();
      int    total = acct.Total();
      int    open  = acct.OpenCount();
      int    pend  = acct.PendingCount();
      SSRVirtualPosition before1, before2;
      acct.ByTicket(t1, before1);
      acct.ByTicket(t2, before2);

      //--- write it
      CSSRSessionFile w;
      Check("file created", w.Create("SSReplay\\test_acct.ssr"), w.LastError());
      acct.SaveInto(w);
      w.Close();

      //--- and read it into a fresh account
      CSSRSessionFile r;
      Check("file loaded", r.Load("SSReplay\\test_acct.ssr"), r.LastError());
      CSSRTradingEngine back;
      string warn = "";
      Check("account restored", back.RestoreFrom(r, warn), back.LastError());
      CheckStr("with nothing to warn about", "", warn);

      CheckEq("every position came back", total, back.Total());
      CheckEq("open count",    open, back.OpenCount());
      CheckEq("pending count", pend, back.PendingCount());

      //--- THE MONEY IS COMPARED EXACTLY. A balance a cent short after
      //--- a save is a bug nobody finds for months.
      CheckNear("balance replayed from the log", bal, back.Balance(), 0.005);
      CheckNear("initial balance", 10000.0, back.InitialBalance(), 1e-9);

      SSRVirtualPosition after1, after2;
      Check("the scaled trade is there", back.ByTicket(t1, after1));
      CheckNear("its profit", before1.profit, after1.profit, 1e-6);
      CheckNear("its commission", before1.commission, after1.commission, 1e-6);
      CheckNear("its swap", before1.swap, after1.swap, 1e-6);
      CheckNear("its MAE", before1.mae, after1.mae, 1e-8);
      CheckNear("its risk at entry", before1.risk_at_entry, after1.risk_at_entry, 1e-6);
      CheckStr("its tag", "scaled", after1.tag);
      CheckEq("its close reason", (long)before1.reason, (long)after1.reason);

      //--- THE LEGS. Without them the restored session cannot step
      //--- back over its own partial exit.
      CheckEq("both legs came back", before1.leg_count, after1.leg_count);
      Check("more than one", after1.leg_count >= 2,
            IntegerToString(after1.leg_count));
      CheckNear("the partial leg's volume", before1.legs[0].volume,
                after1.legs[0].volume, 1e-9);
      CheckNear("and what it booked", before1.legs[0].realised,
                after1.legs[0].realised, 1e-6);
      Check("the closing leg is marked", after1.legs[after1.leg_count-1].closing);

      //--- the runner kept its stops
      Check("the runner is there", back.ByTicket(t2, after2));
      CheckNear("stop loss", before2.sl, after2.sl, 1e-9);
      CheckNear("take profit", before2.tp, after2.tp, 1e-9);
      Check("and is still open", after2.IsOpen());

      //--- the pending order is still an order, at its price
      SSRVirtualPosition pending;
      Check("the pending is there", back.ByTicket(t3, pending));
      CheckEq("still pending", (long)SSR_POS_PENDING, (long)pending.state);
      CheckNear("at its price", 900.0, pending.request_price, 1e-9);
      CheckEq("as the type it was placed with",
              (long)SSR_ORDER_BUY_LIMIT, (long)pending.request_type);

      //--- the execution assumptions travelled with the trades, or the
      //--- next trade in the resumed session would be priced differently
      SSRExecutionModel got;
      back.ExecutionInto(got);
      CheckNear("commission", 3.5,  got.commission_per_lot, 1e-9);
      CheckNear("swap",      -1.25, got.swap_long_per_lot, 1e-9);
      Check("margin is still modelled", back.MarginModelled());

      //--- LAST, because it destroys the state above: the restored
      //--- account can still be rewound over its own partial exit,
      //--- which is the whole reason the legs were written
      back.OnRewind(before1.legs[0].msc - 1);
      SSRVirtualPosition rewound;
      Check("rewound", back.ByTicket(t1, rewound));
      Check("back to full size", rewound.IsOpen() &&
            MathAbs(rewound.volume - 2.0) < 1e-9,
            StringFormat("state=%d vol=%.2f", (int)rewound.state, rewound.volume));

      FileDelete("SSReplay\\test_acct.ssr");
   }

   //================================================================
   Section("T12.4  a balance that does not reproduce is REPORTED");
   {
      //--- the file records the balance for a CHECK, not to be
      //--- restored. If replaying the log does not reproduce it, the
      //--- file and this build disagree and the user must hear so.
      CSSRSessionFile w;
      w.Create("SSReplay\\test_bad.ssr");
      w.Section("account");
      w.SetDouble("balance_initial", 10000.0, 2);
      w.SetDouble("balance_check",   99999.0, 2);   // a figure no trade supports
      w.SetInt("digits", 2);
      w.SetLong("next_ticket", 2);
      w.Section("positions");
      w.Set("pos", "1|0|2|0.0000|1.0000|0|0|0|1000|1000|0|0|0|0|1010|60000|1|"
                   "0|0|10|0|0|0|0|0|0|x|");
      w.Close();

      CSSRSessionFile r;
      Check("loaded", r.Load("SSReplay\\test_bad.ssr"), r.LastError());
      CSSRTradingEngine acct;
      string warn = "";
      Check("it still loads", acct.RestoreFrom(r, warn), acct.LastError());
      CheckEq("the trade is there", 1, acct.Total());
      CheckNear("the balance comes from the log", 10010.0, acct.Balance(), 0.005);
      Check("and the disagreement is reported",
            StringFind(warn, "balance replayed") >= 0, warn);
      Check("with both figures in it",
            StringFind(warn, "99999") >= 0, warn);

      FileDelete("SSReplay\\test_bad.ssr");
   }

   //================================================================
   Section("T12.5  the equity curve is stored; everything else is derived");
   {
      CSSRMemoryDataSource src; CSSRRecordingSink sink;
      CSSRReplayController ctrl; CSSRTradingEngine acct; CSSRStatsEngine stats;

      ctrl.AddObserver(GetPointer(acct));
      ctrl.AddObserver(GetPointer(stats));
      Wire(ctrl, src, sink, "TEST", 1000.0);
      acct.SetBalance(10000.0);
      stats.Attach(GetPointer(acct));

      ctrl.Play();
      for(int i = 0; i < 40; i++)
         ctrl.Pump(1000);
      long t = acct.Open(SSR_ORDER_BUY, 1.0, 990.0);
      for(int i = 0; i < 200; i++)
         ctrl.Pump(1000);
      acct.Close(t);
      for(int i = 0; i < 100; i++)
         ctrl.Pump(1000);

      int    samples = stats.EquitySamples();
      Check("the curve was sampled", samples > 3, IntegerToString(samples));
      double dd_money = 0.0, dd_pct = 0.0;
      stats.EquityDrawdown(dd_money, dd_pct);

      CSSRSessionFile w;
      w.Create("SSReplay\\test_eq.ssr");
      acct.SaveInto(w);
      stats.SaveInto(w);
      w.Close();

      CSSRSessionFile r;
      Check("loaded", r.Load("SSReplay\\test_eq.ssr"), r.LastError());
      CSSRTradingEngine acct2; CSSRStatsEngine stats2;
      string warn = "";
      acct2.RestoreFrom(r, warn);
      stats2.Attach(GetPointer(acct2));
      Check("curve restored", stats2.RestoreFrom(r));
      CheckEq("every sample came back", samples, stats2.EquitySamples());

      double dd_money2 = 0.0, dd_pct2 = 0.0;
      stats2.EquityDrawdown(dd_money2, dd_pct2);
      //--- the curve is stored to the cent, so two cents of tolerance
      //--- is the honest bound, not a fudge
      CheckNear("and the drawdown is the same figure",
                dd_money, dd_money2, 0.02);

      //--- the DERIVED statistics were never written, and come back
      //--- identical anyway - because they are recomputed from the
      //--- trades, which is the only copy there is
      SSRStatistics s1, s2;
      stats.Compute(s1);
      stats2.Compute(s2);
      CheckEq("trade count",   s1.trades, s2.trades);
      CheckNear("net profit",  s1.net_profit, s2.net_profit, 0.005);
      CheckNear("profit factor", s1.profit_factor, s2.profit_factor, 1e-6);
      CheckNear("average R",   s1.average_r, s2.average_r, 1e-6);
      CheckEq("ambiguous count", s1.ambiguous_trades, s2.ambiguous_trades);

      //--- and the file really does not contain them
      Check("no win rate was stored", !r.Select("statistics"));

      FileDelete("SSReplay\\test_eq.ssr");
   }

   //================================================================
   Section("T12.6  a whole session: save, rebuild, resume");
   {
      CSSRMemoryDataSource src; CSSRRecordingSink sink;
      CSSRReplayController ctrl; CSSRTradingEngine acct; CSSRStatsEngine stats;
      CSSRReplayGroup grp; CSSRSessionManager mgr;

      ctrl.AddObserver(GetPointer(acct));
      ctrl.AddObserver(GetPointer(stats));
      Wire(ctrl, src, sink, "TEST", 1000.0);
      acct.SetBalance(10000.0);
      stats.Attach(GetPointer(acct));
      grp.Add(GetPointer(ctrl));
      Check("aligned", grp.Align(), grp.LastError());
      mgr.Attach(GetPointer(grp), GetPointer(acct), GetPointer(stats));

      grp.Play();
      for(int i = 0; i < 120; i++)
         grp.Pump(1000);
      long t = acct.Open(SSR_ORDER_BUY, 1.0, 990.0, 0.0, 0.0, "kept");
      Check("traded", t > 0, acct.LastError());
      Check("bookmarked", ctrl.Bookmark("here"));
      for(int i = 0; i < 60; i++)
         grp.Pump(1000);

      long   saved_at   = grp.Now();
      double saved_bal  = acct.Balance();
      int    saved_open = acct.OpenCount();
      int    saved_eq   = stats.EquitySamples();

      SSRSessionSettings set;
      set.Init();
      set.seed        = 8143772915;
      set.blind       = 1;
      set.pause_flags = SSR_PAUSE_ON_SL;
      set.slot        = 3;
      Check("saved", mgr.Save("t12", set), mgr.LastError());

      //--- what a user would be shown before opening it
      string summary = "";
      Check("peeked", mgr.Peek("t12", summary), mgr.LastError());
      Check("the summary names the symbol",
            StringFind(summary, "TEST") >= 0, summary);
      Check("and how far in it got",
            StringFind(summary, "%") >= 0, summary);

      SSRSessionSettings got;
      Check("settings read back", mgr.ReadSettings("t12", got));
      CheckEq("the seed survived", (long)set.seed, (long)got.seed);
      CheckEq("blind level", set.blind, got.blind);
      CheckEq("pause flags", set.pause_flags, got.pause_flags);
      CheckEq("slot", set.slot, got.slot);

      string syms[];
      CheckEq("one symbol to rebuild", 1, mgr.ReadSymbols("t12", syms));
      CheckStr("named", "TEST", syms[0]);
      long ws = 0, we = 0;
      Check("and its window", mgr.ReadWindow("t12", 0, ws, we));
      CheckEq("window start", g_start, ws);
      CheckEq("window end",   g_end,   we);

      //================================================================
      //  A COMPLETELY FRESH SET OF OBJECTS - as after a restart
      //================================================================
      CSSRMemoryDataSource src2; CSSRRecordingSink sink2;
      CSSRReplayController ctrl2; CSSRTradingEngine acct2; CSSRStatsEngine stats2;
      CSSRTradeAutoPause   ap2;
      CSSRReplayGroup grp2; CSSRSessionManager mgr2;

      ctrl2.AddObserver(GetPointer(acct2));
      ctrl2.AddObserver(GetPointer(stats2));
      ctrl2.AddObserver(GetPointer(ap2));
      Check("rebuilt", Wire(ctrl2, src2, sink2, "TEST", 1000.0),
            ctrl2.LastErrorText());
      acct2.SetBalance(10000.0);
      stats2.Attach(GetPointer(acct2));
      ap2.Attach(GetPointer(acct2));
      ap2.SetFlags(SSR_PAUSE_ON_ENTRY);
      grp2.Add(GetPointer(ctrl2));
      grp2.Align();
      mgr2.Attach(GetPointer(grp2), GetPointer(acct2), GetPointer(stats2));

      Check("resumed", mgr2.Restore("t12"), mgr2.LastError());
      CheckEq("one stream restored", 1, mgr2.StreamsRestored());
      Check("with nothing to warn about", !mgr2.HadWarnings(), mgr2.Warnings());

      CheckEq("back at the same instant", saved_at, grp2.Now());
      CheckNear("with the same balance", saved_bal, acct2.Balance(), 0.005);
      CheckEq("the same open trades", saved_open, acct2.OpenCount());
      CheckEq("and the equity curve", saved_eq, stats2.EquitySamples());
      CheckEq("the bookmark came back", 1, ctrl2.BookmarkCount());

      SSRVirtualPosition p;
      Check("the trade is there", acct2.ByTicket(t, p));
      CheckStr("with its tag", "kept", p.tag);
      Check("and still open", p.IsOpen());

      //--- THE RESTORED POSITION IS NOT AN ENTRY THAT JUST HAPPENED.
      //--- Without the resync, the auto-pause watcher would announce
      //--- a fill from an hour ago the moment the replay resumed.
      string why = "";
      Check("no phantom entry announced", !ap2.PauseRequested(why), why);

      grp2.Play();
      grp2.Pump(1000);
      Check("and the replay carries on",
            ctrl2.Status() == SSR_STATE_PLAYING, SSRStateName(ctrl2.Status()));

      //--- the resumed session can still be rewound
      Check("stepped back", grp2.StepBackward(5));
      Check("earlier than the save", grp2.Now() < saved_at,
            SSRFormatMsc(grp2.Now()));

      Check("deleted", mgr2.Delete("t12"), mgr2.LastError());
      Check("and it is gone", !mgr2.Exists("t12"));
   }

   //================================================================
   Section("T12.7  a resume against changed history says so");
   {
      CSSRMemoryDataSource src; CSSRRecordingSink sink;
      CSSRReplayController ctrl; CSSRTradingEngine acct;
      CSSRReplayGroup grp; CSSRSessionManager mgr;

      ctrl.AddObserver(GetPointer(acct));
      Wire(ctrl, src, sink, "TEST", 1000.0);
      acct.SetBalance(10000.0);
      grp.Add(GetPointer(ctrl));
      grp.Align();
      mgr.Attach(GetPointer(grp), GetPointer(acct), NULL);

      grp.Play();
      for(int i = 0; i < 200; i++)
         grp.Pump(1000);

      SSRSessionSettings set;
      set.Init();
      Check("saved", mgr.Save("t12b", set), mgr.LastError());

      //--- REBUILT AGAINST DIFFERENT BARS. The range and the count are
      //--- identical; only the prices differ - which is exactly what a
      //--- broker revising its history looks like.
      CSSRMemoryDataSource src2; CSSRRecordingSink sink2;
      CSSRReplayController ctrl2; CSSRTradingEngine acct2;
      CSSRReplayGroup grp2; CSSRSessionManager mgr2;

      ctrl2.AddObserver(GetPointer(acct2));
      Check("rebuilt on revised data",
            Wire(ctrl2, src2, sink2, "TEST", 1000.0, 7.0),   // a wider range
            ctrl2.LastErrorText());
      acct2.SetBalance(10000.0);
      grp2.Add(GetPointer(ctrl2));
      grp2.Align();
      mgr2.Attach(GetPointer(grp2), GetPointer(acct2), NULL);

      Check("it still resumes", mgr2.Restore("t12b"), mgr2.LastError());
      Check("BUT the change is reported", mgr2.HadWarnings(), "(silent!)");
      Check("and named as a revision",
            StringFind(mgr2.Warnings(), "revised") >= 0, mgr2.Warnings());
      Check("the report reaches the user",
            StringFind(mgr2.ResumeReport(), "BUT") >= 0, mgr2.ResumeReport());

      mgr2.Delete("t12b");
   }

   //================================================================
   Section("T12.8  a session refuses what it cannot honestly restore");
   {
      CSSRSessionManager mgr;
      Check("no such session", !mgr.Exists("no_such_session_here"));
      string summary = "";
      Check("peek fails", !mgr.Peek("no_such_session_here", summary));
      Check("with a readable reason", StringLen(mgr.LastError()) > 5,
            mgr.LastError());
      Check("delete fails", !mgr.Delete("no_such_session_here"));

      //--- restoring into nothing
      CSSRReplayGroup empty;
      CSSRSessionManager m2;
      m2.Attach(GetPointer(empty), NULL, NULL);
      Check("cannot restore into an empty group", !m2.Restore("anything"));

      //--- a stream that is not the one the file describes
      CSSRMemoryDataSource src; CSSRRecordingSink sink;
      CSSRReplayController ctrl; CSSRReplayGroup grp; CSSRSessionManager m3;
      Wire(ctrl, src, sink, "TEST", 1000.0);
      grp.Add(GetPointer(ctrl));
      grp.Align();
      m3.Attach(GetPointer(grp), NULL, NULL);
      SSRSessionSettings set;
      set.Init();
      m3.Save("t12c", set);

      CSSRMemoryDataSource srcX; CSSRRecordingSink sinkX;
      CSSRReplayController ctrlX; CSSRReplayGroup grpX; CSSRSessionManager mX;
      Wire(ctrlX, srcX, sinkX, "OTHER", 1000.0);
      grpX.Add(GetPointer(ctrlX));
      grpX.Align();
      mX.Attach(GetPointer(grpX), NULL, NULL);
      Check("a session will not load into the wrong instrument",
            !mX.Restore("t12c"));
      Check("and says which is which",
            StringFind(mX.LastError(), "OTHER") >= 0 &&
            StringFind(mX.LastError(), "TEST") >= 0, mX.LastError());

      m3.Delete("t12c");
   }

   //================================================================
   PrintFormat("=== Phase 12: PASS=%d  FAIL=%d  ===> %s",
               g_pass, g_fail, (g_fail == 0 ? "GREEN" : "RED"));
  }
//+------------------------------------------------------------------+
