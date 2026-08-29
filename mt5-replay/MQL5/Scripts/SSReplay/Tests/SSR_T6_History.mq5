//+------------------------------------------------------------------+
//|                                               SSR_T6_History.mq5  |
//|                    SS Replay - Phase 6 History Management Tests  |
//+------------------------------------------------------------------+
#property script_show_inputs

#include <SSReplay/Common/SSR_Types.mqh>
#include <SSReplay/Common/SSR_Time.mqh>
#include <SSReplay/Data/SSR_HistoryCatalog.mqh>
#include <SSReplay/Data/SSR_SessionRange.mqh>
#include <SSReplay/Mt5/SSR_SeedCache.mqh>
#include <SSReplay/Data/SSR_Mt5DataSource.mqh>
#include <SSReplay/Mt5/SSR_CustomSymbolSink.mqh>
#include <SSReplay/Core/SSR_ReplayController.mqh>

input string InpSymbol = "";   // Symbol (empty = current chart symbol)
input int    InpSlot   = 7;    // Slot

int g_pass = 0, g_fail = 0, g_skip = 0;
void Check(const string n, const bool ok, const string d = "")
  { if(ok) { g_pass++; PrintFormat("  PASS  %s", n); }
    else   { g_fail++; PrintFormat("  FAIL  %s  %s", n, d); } }
void CheckEq(const string n, const long e, const long a)
  { Check(n, e == a, StringFormat("expected=%I64d actual=%I64d", e, a)); }
void Skip(const string n, const string w) { g_skip++; PrintFormat("  SKIP  %s  (%s)", n, w); }
void Section(const string t) { PrintFormat("--- %s", t); }

//+------------------------------------------------------------------+
void OnStart()
  {
   string origin = (InpSymbol == "" ? _Symbol : InpSymbol);
   Print("=== SSR Phase 6 - History Management ===");

   //================================================================
   Section("T6.1  the warmup arithmetic (no terminal needed)");
   {
      //--- the design document's headline number, executed
      CheckEq("200 D1 candles need 288,000 M1 bars",
              288000, CSSRHistoryCatalog::WarmupFor(PERIOD_D1, 200));
      CheckEq("500 H4 candles need 120,000",
              120000, CSSRHistoryCatalog::WarmupFor(PERIOD_H4, 500));
      CheckEq("500 H1 candles need 30,000",
              30000,  CSSRHistoryCatalog::WarmupFor(PERIOD_H1, 500));
      CheckEq("500 M15 candles need 7,500",
              7500,   CSSRHistoryCatalog::WarmupFor(PERIOD_M15, 500));
      CheckEq("M1 needs one for one",
              500,    CSSRHistoryCatalog::WarmupFor(PERIOD_M1, 500));

      //--- the window is sized from the session now, not fixed
      Check("window scales with the session",
            CSSRHistoryCatalog::SuggestWindowBars(200000) >
            CSSRHistoryCatalog::SuggestWindowBars(1000));
      Check("window has a floor",
            CSSRHistoryCatalog::SuggestWindowBars(10) >= 5000);
      Check("window has a ceiling",
            CSSRHistoryCatalog::SuggestWindowBars(10000000) <= 60000);
   }

   //================================================================
   Section("T6.2  the catalog against the broker");

   CSSRMt5DataSource src;
   CSSRHistoryCatalog cat;
   bool have = src.Open(origin);
   if(!have)
      Skip("catalog", "no M1 history for " + origin);
   else
     {
      cat.Attach(src.History());
      Check("scan succeeded", cat.Scan(origin));
      Check("range available", cat.Available());
      Check("bars counted", cat.BarCount() > 0, IntegerToString((int)cat.BarCount()));
      Check("first precedes last", cat.FirstMsc() < cat.LastMsc());

      //--- T8: the still-forming bar must not be offered as data
      long now_quote = SymbolInfoInteger(origin, SYMBOL_TIME_MSC);
      if(now_quote > 0)
         Check("last available instant is not in the future",
               cat.LastMsc() <= now_quote + SSR_MSC_PER_MIN,
               StringFormat("last=%s quote=%s",
                            SSRFormatMscMs(cat.LastMsc()),
                            SSRFormatMscMs(now_quote)));
      PrintFormat("        %s", cat.ToString());
     }

   //================================================================
   Section("T6.3  quoting a session before paying for it");
   if(!have)
      Skip("quote", "no broker data");
   else
     {
      SSRSeedQuote q;
      cat.Quote(PERIOD_H1, 300, 2000, q);
      CheckEq("warmup bars quoted", 18000, q.warmup_bars);
      CheckEq("replay bars quoted", 2000,  q.replay_bars);
      CheckEq("total is the sum",   20000, q.total_bars);
      Check("time is estimated",  q.seconds > 0.0);
      Check("size is estimated",  q.megabytes > 0.0);

      //--- an impossible ask must be reported, not attempted
      SSRSeedQuote big;
      cat.Quote(PERIOD_D1, 5000, 100000, big);
      Check("a request beyond the history is flagged",
            big.exceeds_history || big.total_bars <= cat.BarCount(),
            big.ToString());

      //--- once spike D1 reports a real rate, quotes stop being guesses
      double before = cat.SeedRate();
      cat.SetMeasuredSeedRate(12345.0);
      Check("a measured rate replaces the estimate", cat.SeedRate() == 12345.0);
      cat.SetMeasuredSeedRate(before);
   }

   //================================================================
   Section("T6.4  range validation speaks in actionable words");
   if(!have)
      Skip("validation", "no broker data");
   else
     {
      SSRSessionRange r;
      r.Init();
      Check("an empty request is rejected", SSRValidateRange(r, cat) != "");

      r.origin = origin;
      r.max_tf = PERIOD_H1;
      r.visible_bars = 300;

      //--- too early: the warmup would reach before the broker's history
      r.start_msc = cat.FirstMsc();
      r.end_msc   = cat.FirstMsc() + 100 * SSR_MSC_PER_MIN;
      string why = SSRValidateRange(r, cat);
      Check("a start with no room for warmup is refused", why != "", why);
      Check("and the message says why", StringFind(why, "too early") >= 0, why);

      //--- a workable range
      long warm = r.WarmupBars();
      r.start_msc = cat.EarliestStart(warm) + 100 * SSR_MSC_PER_MIN;
      r.end_msc   = r.start_msc + 500 * SSR_MSC_PER_MIN;
      if(r.end_msc < cat.LastMsc())
        {
         string ok = SSRValidateRange(r, cat);
         Check("a workable range passes", ok == "" || StringFind(ok, "warning") == 0, ok);
         Check("it describes itself", StringLen(r.Describe()) > 10, r.Describe());
         CheckEq("replay minutes computed", 500, r.ReplayMinutes());
        }
      else
         Skip("workable range", "history too short to build one");
     }

   //================================================================
   Section("T6.5  the seed cache: manifest round trip");
   {
      CSSRSeedCache cache;
      SSRSeedManifest m;
      m.Init();
      m.origin          = "TESTORIGIN";
      m.replay_symbol   = "TESTORIGIN.SSR7";
      m.warmup_from_msc = SSRToMsc(D'2024.01.08 00:00');
      m.warmup_to_msc   = SSRToMsc(D'2024.01.09 00:00');
      m.bar_count       = 1440;

      Check("manifest is valid", m.IsValid());
      Check("saved", cache.Save(m));

      SSRSeedManifest back;
      Check("loaded", cache.Load("TESTORIGIN.SSR7", back));
      Check("origin survived",  back.origin == m.origin, back.origin);
      CheckEq("from survived",  m.warmup_from_msc, back.warmup_from_msc);
      CheckEq("to survived",    m.warmup_to_msc,   back.warmup_to_msc);
      CheckEq("count survived", m.bar_count,       back.bar_count);

      //--- a manifest without the bars behind it must not be believed
      Check("a manifest alone is not enough",
            !cache.CanReuse("TESTORIGIN", "TESTORIGIN.SSR7",
                            m.warmup_from_msc, m.warmup_to_msc),
            "reused a symbol that does not exist: " + cache.LastReason());

      cache.Invalidate("TESTORIGIN.SSR7");
      SSRSeedManifest gone;
      Check("invalidated", !cache.Load("TESTORIGIN.SSR7", gone));
   }

   //================================================================
   Section("T6.6  cache rejects what it should");
   {
      CSSRSeedCache cache;
      SSRSeedManifest m;
      m.Init();
      m.origin          = "A";
      m.replay_symbol   = "A.SSR7";
      m.warmup_from_msc = 1000000;
      m.warmup_to_msc   = 2000000;
      m.bar_count       = 10;
      cache.Save(m);

      Check("a different origin is refused",
            !cache.CanReuse("B", "A.SSR7", 1000000, 2000000));
      Check("a wider request is refused",
            !cache.CanReuse("A", "A.SSR7", 500000, 2000000),
            cache.LastReason());
      Check("the reason is recorded", StringLen(cache.LastReason()) > 0,
            cache.LastReason());

      cache.SetEnabled(false);
      Check("a disabled cache never reuses",
            !cache.CanReuse("A", "A.SSR7", 1000000, 2000000));
      cache.Invalidate("A.SSR7");
   }

   //================================================================
   Section("T6.7  end to end: the second load skips the seed");
   if(!have)
      Skip("cache reuse", "no broker data");
   else
     {
      long warm_bars = 600;
      long win_end   = cat.LastMsc();
      long win_start = win_end - 300 * SSR_MSC_PER_MIN;
      long floor_msc = cat.FirstMsc() + warm_bars * SSR_MSC_PER_MIN;
      if(win_start < floor_msc)
         win_start = floor_msc;

      int    digits = (int)SymbolInfoInteger(origin, SYMBOL_DIGITS);
      double point  = SymbolInfoDouble(origin, SYMBOL_POINT);
      if(point <= 0.0) point = MathPow(10, -digits);

      if(win_start >= win_end)
         Skip("cache reuse", "history too short");
      else
        {
         //--- first run: seeds for real
         ulong t0 = SSRMicros();
         {
            CSSRMt5DataSource    s1;
            CSSRCustomSymbolSink k1;
            CSSRReplayController c1;
            k1.SetSlot(InpSlot);
            k1.SetOwnsSymbol(false);       // survive teardown, so run 2 can reuse
            c1.SetSymbolSpec(digits, point);
            c1.SetWarmupBars(warm_bars);
            c1.Attach(GetPointer(s1), GetPointer(k1));
            Check("first load", c1.Load(origin, win_start, win_end), c1.LastErrorText());
            Check("first run seeded for real", !k1.ReusedSeed(), k1.CacheReason());
            c1.Release();
         }
         double first_ms = SSRElapsedMs(t0);

         //--- second run: same range, should adopt what is already there
         SSRPause(300);
         t0 = SSRMicros();
         {
            CSSRMt5DataSource    s2;
            CSSRCustomSymbolSink k2;
            CSSRReplayController c2;
            k2.SetSlot(InpSlot);
            k2.SetOwnsSymbol(false);
            c2.SetSymbolSpec(digits, point);
            c2.SetWarmupBars(warm_bars);
            c2.Attach(GetPointer(s2), GetPointer(k2));
            bool ok = c2.Load(origin, win_start, win_end);
            Check("second load", ok, c2.LastErrorText());
            Check("second run reused the seed", k2.ReusedSeed(), k2.CacheReason());

            if(ok && k2.ReusedSeed())
              {
               //--- reuse must not resurrect the previous session's replay
               string rsym = k2.ReplaySymbol();
               MqlRates ahead[];
               int n = CopyRates(rsym, PERIOD_M1,
                                 SSRToTime(win_start), SSRToTime(win_end), ahead);
               CheckEq("reused symbol carries no replay data", 0, MathMax(n, 0));
              }
            k2.SetOwnsSymbol(true);
            c2.Release();
         }
         double second_ms = SSRElapsedMs(t0);
         PrintFormat("        first load %.0fms, second %.0fms", first_ms, second_ms);
         Check("reuse was not slower", second_ms <= first_ms * 1.5,
               StringFormat("%.0f vs %.0f", second_ms, first_ms));
        }
     }

   //================================================================
   Section("T6.8  session gap is learned from the symbol");
   if(!have)
      Skip("session gap", "no broker data");
   else
     {
      long gap = SSRSymbolSessionGap(origin);
      Check("a gap was derived", gap >= SSR_SESSION_GAP_MSC,
            SSRFormatSpan(gap));
      PrintFormat("        %s treats %s as a market closure",
                  origin, SSRFormatSpan(gap));

      CSSRDataValidator v;
      long before = v.SessionGap();
      v.LearnFrom(origin);
      Check("validator adopted it", v.SessionGap() == gap,
            StringFormat("%I64d vs %I64d", v.SessionGap(), gap));
      Check("and it differs from the flat default or matches deliberately",
            v.SessionGap() >= before);
     }

   //================================================================
   PrintFormat("=== Phase 6: PASS=%d  FAIL=%d  SKIP=%d  ===> %s",
               g_pass, g_fail, g_skip, (g_fail == 0 ? "GREEN" : "RED"));
   Print("    run SSR_Z_Cleanup to remove test symbols");
  }
//+------------------------------------------------------------------+
