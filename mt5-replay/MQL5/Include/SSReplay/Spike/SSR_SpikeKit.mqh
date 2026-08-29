//+------------------------------------------------------------------+
//|                                                 SSR_SpikeKit.mqh |
//|                                    SS Replay - Phase 0 Spike Kit |
//|                                                                  |
//|  Shared measurement harness for all Phase 0 spike tests.         |
//|  NOT product code. Nothing here survives into the engine.        |
//|                                                                  |
//|  Every number a spike produces goes through this file, so the    |
//|  results are comparable across spikes, runs and machines.        |
//+------------------------------------------------------------------+
#property copyright "SS Replay - Phase 0"
#property version   "1.00"

//--- output files (relative to <Terminal Data Folder>\MQL5\Files)
#define SSR_DIR        "SSR_Spike"
#define SSR_F_ENV      "SSR_Spike\\env.csv"
#define SSR_F_RESULTS  "SSR_Spike\\results.csv"
#define SSR_F_VERDICTS "SSR_Spike\\verdicts.csv"

//--- run-scoped state
string  g_ssr_spike   = "";
string  g_ssr_run     = "";
int     g_ssr_pass    = 0;
int     g_ssr_fail    = 0;
ulong   g_ssr_t_start = 0;

//+------------------------------------------------------------------+
//| Deterministic RNG (xorshift64) - reproducible across machines.   |
//| MathRand() is NOT used: it is 15-bit and shares global state.    |
//+------------------------------------------------------------------+
class SSR_Rng
  {
private:
   ulong             m_s;
public:
   void              Seed(const ulong s) { m_s = (s == 0 ? 88172645463325252 : s); }
   ulong             Next(void)
     {
      m_s ^= (m_s << 13);
      m_s ^= (m_s >> 7);
      m_s ^= (m_s << 17);
      return m_s;
     }
   //--- uniform in [0,1)
   double            Uniform(void) { return (double)(Next() % 1000000007) / 1000000007.0; }
   //--- uniform in [lo,hi)
   double            Range(const double lo, const double hi) { return lo + (hi - lo) * Uniform(); }
   //--- integer in [lo,hi]
   int               Int(const int lo, const int hi) { return lo + (int)(Next() % (ulong)(hi - lo + 1)); }
   //--- standard normal (Box-Muller)
   double            Normal(void)
     {
      double u1 = Uniform();
      double u2 = Uniform();
      if(u1 < 1e-12) u1 = 1e-12;
      return MathSqrt(-2.0 * MathLog(u1)) * MathCos(2.0 * M_PI * u2);
     }
  };

//+------------------------------------------------------------------+
//| Timing                                                           |
//+------------------------------------------------------------------+
ulong  SSR_Now(void)                    { return GetMicrosecondCount(); }
double SSR_ElapsedUs(const ulong t0)    { return (double)(GetMicrosecondCount() - t0); }
double SSR_ElapsedMs(const ulong t0)    { return (double)(GetMicrosecondCount() - t0) / 1000.0; }
double SSR_ElapsedSec(const ulong t0)   { return (double)(GetMicrosecondCount() - t0) / 1000000.0; }

//+------------------------------------------------------------------+
//| Memory (MB)                                                      |
//+------------------------------------------------------------------+
long SSR_MemMql(void)      { return MQLInfoInteger(MQL_MEMORY_USED); }
long SSR_MemTerminal(void) { return TerminalInfoInteger(TERMINAL_MEMORY_USED); }

//+------------------------------------------------------------------+
//| CSV helpers                                                      |
//+------------------------------------------------------------------+
string SSR_Csv(const string s)
  {
   string r = s;
   StringReplace(r, ",", ";");
   StringReplace(r, "\n", " ");
   StringReplace(r, "\r", " ");
   return r;
  }

string SSR_Utc(void) { return TimeToString(TimeGMT(), TIME_DATE | TIME_SECONDS); }

void SSR_Append(const string file, const string header, const string line)
  {
   FolderCreate(SSR_DIR);
   bool fresh = !FileIsExist(file);
   int h = FileOpen(file, FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(h == INVALID_HANDLE)
     {
      PrintFormat("[SSR] cannot open %s err=%d", file, GetLastError());
      return;
     }
   FileSeek(h, 0, SEEK_END);
   if(fresh)
      FileWriteString(h, header + "\r\n");
   FileWriteString(h, line + "\r\n");
   FileClose(h);
  }

//+------------------------------------------------------------------+
//| Run lifecycle                                                    |
//+------------------------------------------------------------------+
void SSR_Begin(const string spike)
  {
   g_ssr_spike   = spike;
   g_ssr_pass    = 0;
   g_ssr_fail    = 0;
   g_ssr_t_start = GetMicrosecondCount();
   g_ssr_run     = StringFormat("%s-%s", TimeToString(TimeGMT(), TIME_DATE), IntegerToString((int)(GetTickCount() % 100000)));
   StringReplace(g_ssr_run, ".", "");

   FolderCreate(SSR_DIR);

   //--- environment row: everything needed to interpret the numbers later
   string env = StringFormat("%s,%s,%s,%s,%d,%s,%s,%d,%d,%d,%d,%d",
                             g_ssr_run,
                             SSR_Utc(),
                             SSR_Csv(spike),
                             SSR_Csv(TerminalInfoString(TERMINAL_NAME)),
                             TerminalInfoInteger(TERMINAL_BUILD),
                             SSR_Csv(AccountInfoString(ACCOUNT_COMPANY)),
                             SSR_Csv(AccountInfoString(ACCOUNT_SERVER)),
                             TerminalInfoInteger(TERMINAL_CPU_CORES),
                             TerminalInfoInteger(TERMINAL_MEMORY_PHYSICAL),
                             TerminalInfoInteger(TERMINAL_MEMORY_TOTAL),
                             TerminalInfoInteger(TERMINAL_MEMORY_USED),
                             TerminalInfoInteger(TERMINAL_MAXBARS));
   SSR_Append(SSR_F_ENV,
              "run_id,utc,spike,terminal,build,company,server,cpu_cores,mem_physical_mb,mem_total_mb,mem_used_mb,max_bars",
              env);

   PrintFormat("=== [%s] BEGIN  run=%s  build=%d  cores=%d  maxbars=%d ===",
               spike, g_ssr_run, TerminalInfoInteger(TERMINAL_BUILD),
               TerminalInfoInteger(TERMINAL_CPU_CORES), TerminalInfoInteger(TERMINAL_MAXBARS));
  }

//--- record a measured number. NEVER record an opinion.
void SSR_Metric(const string testcase, const string metric, const double value,
                const string unit, const string notes = "")
  {
   string line = StringFormat("%s,%s,%s,%s,%s,%.6f,%s,%s",
                              g_ssr_run, SSR_Utc(), SSR_Csv(g_ssr_spike),
                              SSR_Csv(testcase), SSR_Csv(metric), value,
                              SSR_Csv(unit), SSR_Csv(notes));
   SSR_Append(SSR_F_RESULTS, "run_id,utc,spike,case,metric,value,unit,notes", line);
   PrintFormat("[%s] %-22s %-24s = %.4f %s %s",
               g_ssr_spike, testcase, metric, value, unit, notes);
  }

//--- record a PASS/FAIL assertion
bool SSR_Verdict(const string assertion, const bool ok,
                 const string expected, const string actual, const string notes = "")
  {
   if(ok) g_ssr_pass++; else g_ssr_fail++;
   string line = StringFormat("%s,%s,%s,%s,%s,%s,%s,%s",
                              g_ssr_run, SSR_Utc(), SSR_Csv(g_ssr_spike),
                              SSR_Csv(assertion), (ok ? "PASS" : "FAIL"),
                              SSR_Csv(expected), SSR_Csv(actual), SSR_Csv(notes));
   SSR_Append(SSR_F_VERDICTS, "run_id,utc,spike,assertion,verdict,expected,actual,notes", line);
   if(!ok)
      PrintFormat("[%s] FAIL  %s | expected=%s actual=%s %s",
                  g_ssr_spike, assertion, expected, actual, notes);
   return ok;
  }

void SSR_End(void)
  {
   double secs = SSR_ElapsedSec(g_ssr_t_start);
   SSR_Metric("_run", "total_runtime", secs, "s");
   SSR_Metric("_run", "assertions_pass", (double)g_ssr_pass, "count");
   SSR_Metric("_run", "assertions_fail", (double)g_ssr_fail, "count");
   PrintFormat("=== [%s] END  PASS=%d  FAIL=%d  runtime=%.2fs  ===> %s",
               g_ssr_spike, g_ssr_pass, g_ssr_fail, secs,
               (g_ssr_fail == 0 ? "SPIKE PASS" : "SPIKE FAIL"));
   PrintFormat("=== results in <DataFolder>\\MQL5\\Files\\%s ===", SSR_DIR);
  }

//+------------------------------------------------------------------+
//| Custom symbol helpers                                            |
//+------------------------------------------------------------------+

//--- fully remove a symbol, tolerating "not there"
void SSR_DropSymbol(const string sym)
  {
   ResetLastError();
   //--- close any chart still showing it, otherwise delete fails
   long cid = ChartFirst();
   while(cid >= 0)
     {
      if(ChartSymbol(cid) == sym)
        {
         long next = ChartNext(cid);
         ChartClose(cid);
         cid = next;
         continue;
        }
      cid = ChartNext(cid);
     }
   SymbolSelect(sym, false);
   CustomSymbolDelete(sym);
   ResetLastError();
  }

//--- 24/7 quote+trade sessions, so the terminal never silently drops a tick
void SSR_Set247Sessions(const string sym)
  {
   for(int d = 0; d <= 6; d++)
     {
      ENUM_DAY_OF_WEEK day = (ENUM_DAY_OF_WEEK)d;
      CustomSymbolSetSessionQuote(sym, day, 0, (datetime)0, (datetime)86399);
      CustomSymbolSetSessionTrade(sym, day, 0, (datetime)0, (datetime)86399);
     }
  }

//--- create a clean custom symbol cloned from an origin symbol
bool SSR_MakeSymbol(const string sym, const string origin, const bool sessions_247 = true)
  {
   SSR_DropSymbol(sym);

   ResetLastError();
   if(!CustomSymbolCreate(sym, "SSReplay\\Spike", origin))
     {
      PrintFormat("[SSR] CustomSymbolCreate(%s, origin=%s) failed err=%d", sym, origin, GetLastError());
      return false;
     }

   CustomSymbolSetInteger(sym, SYMBOL_SPREAD_FLOAT, true);
   CustomSymbolSetInteger(sym, SYMBOL_TRADE_MODE, SYMBOL_TRADE_MODE_DISABLED);

   if(sessions_247)
      SSR_Set247Sessions(sym);

   if(!SymbolSelect(sym, true))
     {
      PrintFormat("[SSR] SymbolSelect(%s) failed err=%d", sym, GetLastError());
      return false;
     }
   return true;
  }

//+------------------------------------------------------------------+
//| Sleep is not permitted in indicators, and this header is shared  |
//| with two indicator probes - route every wait through here.       |
//+------------------------------------------------------------------+
void SSR_Pause(const int ms)
  {
   if(MQLInfoInteger(MQL_PROGRAM_TYPE) == PROGRAM_INDICATOR)
      return;
   Sleep(ms);
  }

//--- wait until the terminal reports the series is built; returns ms waited, -1 on timeout
double SSR_WaitSeries(const string sym, const ENUM_TIMEFRAMES tf, const int timeout_ms = 10000)
  {
   ulong t0 = SSR_Now();
   while(SSR_ElapsedMs(t0) < timeout_ms)
     {
      long synced = 0;
      if(SeriesInfoInteger(sym, tf, SERIES_SYNCHRONIZED, synced) && synced != 0)
         return SSR_ElapsedMs(t0);
      SSR_Pause(5);
     }
   return -1.0;
  }

//+------------------------------------------------------------------+
//| Golden dataset - deterministic synthetic M1 bars.                |
//| Broker-independent, so every machine measures the same thing.    |
//+------------------------------------------------------------------+
int SSR_GenM1(MqlRates &out[], const datetime start, const int count,
              const double base_price, const double point, const int digits,
              const double vol_points = 25.0, const ulong seed = 20260829)
  {
   if(count <= 0) return 0;
   ArrayResize(out, count);

   SSR_Rng rng;
   rng.Seed(seed);

   double price = base_price;
   for(int i = 0; i < count; i++)
     {
      double o = price;
      double step = rng.Normal() * vol_points * point;
      double c = o + step;

      //--- wick extents beyond the body, always non-negative
      double up = MathAbs(rng.Normal()) * vol_points * 0.6 * point;
      double dn = MathAbs(rng.Normal()) * vol_points * 0.6 * point;

      double h = MathMax(o, c) + up;
      double l = MathMin(o, c) - dn;

      out[i].time         = start + i * 60;
      out[i].open         = NormalizeDouble(o, digits);
      out[i].high         = NormalizeDouble(h, digits);
      out[i].low          = NormalizeDouble(l, digits);
      out[i].close        = NormalizeDouble(c, digits);
      out[i].tick_volume  = (long)rng.Int(8, 400);
      out[i].spread       = rng.Int(1, 6);
      out[i].real_volume  = 0;

      //--- normalization can violate the invariant by one point; repair it
      if(out[i].high < MathMax(out[i].open, out[i].close))
         out[i].high = MathMax(out[i].open, out[i].close);
      if(out[i].low > MathMin(out[i].open, out[i].close))
         out[i].low = MathMin(out[i].open, out[i].close);

      price = out[i].close;
     }
   return count;
  }

//+------------------------------------------------------------------+
//| Reference aggregation M1 -> higher timeframe.                    |
//| This is the INDEPENDENT implementation that the terminal's own   |
//| aggregation is checked against in spike A2.                      |
//+------------------------------------------------------------------+
int SSR_AggregateM1(const MqlRates &m1[], const ENUM_TIMEFRAMES tf, MqlRates &out[])
  {
   int n = ArraySize(m1);
   ArrayResize(out, 0);
   if(n == 0) return 0;

   int secs = PeriodSeconds(tf);
   if(secs <= 0) return 0;

   int cnt = 0;
   datetime cur = 0;
   for(int i = 0; i < n; i++)
     {
      datetime slot = (datetime)(((long)m1[i].time / secs) * secs);
      if(cnt == 0 || slot != cur)
        {
         cnt++;
         ArrayResize(out, cnt);
         out[cnt - 1].time        = slot;
         out[cnt - 1].open        = m1[i].open;
         out[cnt - 1].high        = m1[i].high;
         out[cnt - 1].low         = m1[i].low;
         out[cnt - 1].close       = m1[i].close;
         out[cnt - 1].tick_volume = m1[i].tick_volume;
         out[cnt - 1].real_volume = m1[i].real_volume;
         out[cnt - 1].spread      = m1[i].spread;
         cur = slot;
        }
      else
        {
         if(m1[i].high > out[cnt - 1].high) out[cnt - 1].high = m1[i].high;
         if(m1[i].low  < out[cnt - 1].low)  out[cnt - 1].low  = m1[i].low;
         out[cnt - 1].close        = m1[i].close;
         out[cnt - 1].tick_volume += m1[i].tick_volume;
         out[cnt - 1].real_volume += m1[i].real_volume;
        }
     }
   return cnt;
  }

//+------------------------------------------------------------------+
//| Bar -> tick synthesis, OHLC path model.                          |
//|   bullish (C>=O): O -> L -> H -> C                               |
//|   bearish (C< O): O -> H -> L -> C                               |
//| The same assumption the engine will make, tested here first.     |
//+------------------------------------------------------------------+
int SSR_BarToTicks(const MqlRates &bar, MqlTick &out[], const int n,
                   const double spread_abs, const int digits)
  {
   int cnt = MathMax(n, 4);
   ArrayResize(out, cnt);

   double k[4];
   k[0] = bar.open;
   if(bar.close >= bar.open) { k[1] = bar.low;  k[2] = bar.high; }
   else                      { k[1] = bar.high; k[2] = bar.low;  }
   k[3] = bar.close;

   long base_msc = (long)bar.time * 1000;

   for(int i = 0; i < cnt; i++)
     {
      //--- position along the 3-segment path
      double u   = (cnt == 1) ? 0.0 : (double)i * 3.0 / (double)(cnt - 1);
      int    seg = (int)MathFloor(u);
      if(seg > 2) seg = 2;
      double f   = u - (double)seg;
      double p   = k[seg] + (k[seg + 1] - k[seg]) * f;

      out[i].time       = (datetime)(bar.time + (long)((double)i * 59.0 / (double)MathMax(cnt - 1, 1)));
      out[i].time_msc   = base_msc + (long)((double)i * 59000.0 / (double)MathMax(cnt - 1, 1));
      out[i].bid        = NormalizeDouble(p, digits);
      out[i].ask        = NormalizeDouble(p + spread_abs, digits);
      out[i].last       = out[i].bid;
      out[i].volume     = 1;
      out[i].volume_real = 1.0;
      out[i].flags      = TICK_FLAG_BID | TICK_FLAG_ASK;
     }
   //--- guarantee the last tick lands exactly on the close
   out[cnt - 1].bid  = NormalizeDouble(bar.close, digits);
   out[cnt - 1].ask  = NormalizeDouble(bar.close + spread_abs, digits);
   out[cnt - 1].last = out[cnt - 1].bid;
   return cnt;
  }

//+------------------------------------------------------------------+
//| Compare two rate arrays field by field.                          |
//| Returns number of OHLC/time mismatches; volume counted apart so  |
//| a volume-only difference does not mask a price difference.       |
//+------------------------------------------------------------------+
int SSR_CompareRates(const MqlRates &a[], const MqlRates &b[], const int digits,
                     int &vol_mismatch, string &first_detail)
  {
   vol_mismatch = 0;
   first_detail = "";
   int n = MathMin(ArraySize(a), ArraySize(b));
   int bad = 0;
   double tol = MathPow(10, -digits) * 0.5;

   for(int i = 0; i < n; i++)
     {
      bool m = false;
      string what = "";
      if(a[i].time != b[i].time)                     { m = true; what = "time"; }
      else if(MathAbs(a[i].open  - b[i].open)  > tol) { m = true; what = "open"; }
      else if(MathAbs(a[i].high  - b[i].high)  > tol) { m = true; what = "high"; }
      else if(MathAbs(a[i].low   - b[i].low)   > tol) { m = true; what = "low"; }
      else if(MathAbs(a[i].close - b[i].close) > tol) { m = true; what = "close"; }

      if(m)
        {
         bad++;
         if(first_detail == "")
            first_detail = StringFormat("idx=%d field=%s exp_t=%s act_t=%s exp=%.5f/%.5f/%.5f/%.5f act=%.5f/%.5f/%.5f/%.5f",
                                        i, what,
                                        TimeToString(a[i].time, TIME_DATE | TIME_MINUTES),
                                        TimeToString(b[i].time, TIME_DATE | TIME_MINUTES),
                                        a[i].open, a[i].high, a[i].low, a[i].close,
                                        b[i].open, b[i].high, b[i].low, b[i].close);
        }
      if(a[i].tick_volume != b[i].tick_volume)
         vol_mismatch++;
     }
   return bad;
  }
//+------------------------------------------------------------------+
