//+------------------------------------------------------------------+
//|                                        SSR_A3_FutureIsolation.mq5 |
//|  SPIKE A3 - Future-Data Isolation                                |
//|  TIER A - BLOCKER  (this is the product's reason to exist)       |
//|                                                                  |
//|  Hypothesis: if history is written only up to T, then across     |
//|  EVERY timeframe and EVERY read path, no data beyond T exists.   |
//|  Not hidden - absent.                                            |
//|                                                                  |
//|  PASS: 100 random cut points x 7 timeframes x 4 conditions       |
//|        = 2800 assertions, all must pass.                         |
//|  FAIL: one single assertion. No tolerance.                       |
//+------------------------------------------------------------------+
#property script_show_inputs

#include <SSReplay/Spike/SSR_SpikeKit.mqh>

input string   InpOrigin = "";                 // Origin symbol (blank = this chart's symbol)

input string   InpTest   = "SSRA3";              // Test symbol
input datetime InpStart  = D'2024.01.08 00:00';  // Golden dataset start
input int      InpBars   = 4320;                 // M1 bars
input double   InpBase   = 38000.0;              // Base price
input int      InpCuts   = 100;                  // Random cut points to test

string g_origin = "";   //--- resolved from InpOrigin at the top of OnStart

ENUM_TIMEFRAMES g_tf[7]     = {PERIOD_M1, PERIOD_M5, PERIOD_M15, PERIOD_M30, PERIOD_H1, PERIOD_H4, PERIOD_D1};
string          g_tfname[7] = {"M1", "M5", "M15", "M30", "H1", "H4", "D1"};

//+------------------------------------------------------------------+
//| Four independent read paths must all agree that nothing exists   |
//| after T. Using four is deliberate: a leak may hide in only one.  |
//+------------------------------------------------------------------+
int AuditCut(const string sym, const datetime T, int &checks)
  {
   int leaks = 0;
   datetime far = T + 60 * 60 * 24 * 30;   // one month past the cut

   for(int i = 0; i < 7; i++)
     {
      ENUM_TIMEFRAMES tf = g_tf[i];
      string tag = g_tfname[i];

      //--- path 1: CopyRates over a future range must return nothing
      MqlRates r[];
      ArraySetAsSeries(r, false);
      int got = CopyRates(sym, tf, T + 1, far, r);
      checks++;
      if(got > 0)
        {
         leaks++;
         SSR_Verdict(StringFormat("leak_copyrates_%s", tag), false, "0 bars",
                     IntegerToString(got),
                     StringFormat("T=%s first_leaked=%s", TimeToString(T),
                                  TimeToString(r[0].time)));
        }

      //--- path 2: newest bar open time must not be beyond T
      datetime it = iTime(sym, tf, 0);
      checks++;
      if(it > T)
        {
         leaks++;
         SSR_Verdict(StringFormat("leak_itime_%s", tag), false, "<= T",
                     TimeToString(it), "T=" + TimeToString(T));
        }

      //--- path 3: Bars() counted over the future range must be zero
      int nb = Bars(sym, tf, T + 1, far);
      checks++;
      if(nb > 0)
        {
         leaks++;
         SSR_Verdict(StringFormat("leak_bars_%s", tag), false, "0",
                     IntegerToString(nb), "T=" + TimeToString(T));
        }

      //--- path 4: the series' own last-bar date must not be beyond T
      long lastbar = 0;
      if(SeriesInfoInteger(sym, tf, SERIES_LASTBAR_DATE, lastbar))
        {
         checks++;
         if((datetime)lastbar > T)
           {
            leaks++;
            SSR_Verdict(StringFormat("leak_lastbar_%s", tag), false, "<= T",
                        TimeToString((datetime)lastbar), "T=" + TimeToString(T));
           }
        }
     }
   return leaks;
  }

//+------------------------------------------------------------------+
void OnStart()
  {
   SSR_Begin("A3_FutureIsolation");

   g_origin = SSR_Origin(InpOrigin);
   if(!SSR_MakeSymbol(InpTest, g_origin))
     {
      SSR_Verdict("symbol_ready", false, "created", "failed", "");
      SSR_End();
      return;
     }

   int    digits = (int)SymbolInfoInteger(InpTest, SYMBOL_DIGITS);
   double point  = SymbolInfoDouble(InpTest, SYMBOL_POINT);
   if(point <= 0.0) point = MathPow(10, -digits);

   MqlRates m1[];
   int n = SSR_GenM1(m1, InpStart, InpBars, InpBase, point, digits);

   SSR_Rng rng;
   rng.Seed(777001);

   int total_checks = 0;
   int total_leaks  = 0;
   double t_reset_sum = 0;

   ulong t_all = SSR_Now();

   for(int c = 0; c < InpCuts; c++)
     {
      //--- pick a cut somewhere in the middle 80% of the dataset
      int cut = rng.Int((int)(n * 0.1), (int)(n * 0.9));
      datetime T = m1[cut].time;

      //--- rebuild history so it ends exactly at T
      ulong t0 = SSR_Now();
      CustomRatesDelete(InpTest, 0, D'2038.01.01 00:00');
      CustomTicksDelete(InpTest, 0, LONG_MAX);

      MqlRates slice[];
      ArrayResize(slice, cut + 1);
      for(int i = 0; i <= cut; i++)
         slice[i] = m1[i];
      CustomRatesUpdate(InpTest, slice);
      SymbolSelect(InpTest, true);
      SSR_WaitSeries(InpTest, PERIOD_M1, 10000);
      t_reset_sum += SSR_ElapsedMs(t0);

      int checks = 0;
      int leaks  = AuditCut(InpTest, T, checks);
      total_checks += checks;
      total_leaks  += leaks;

      if(c % 20 == 0)
         PrintFormat("[A3] cut %d/%d  T=%s  checks=%d leaks=%d",
                     c, InpCuts, TimeToString(T), total_checks, total_leaks);
     }

   double t_total = SSR_ElapsedSec(t_all);

   SSR_Metric("audit", "cuts_tested",       (double)InpCuts,      "count");
   SSR_Metric("audit", "assertions_run",    (double)total_checks, "count");
   SSR_Metric("audit", "leaks_found",       (double)total_leaks,  "count");
   SSR_Metric("audit", "total_runtime",     t_total,              "s");
   SSR_Metric("audit", "avg_rebuild_time",  t_reset_sum / MathMax(InpCuts, 1), "ms",
              "cost of a full history rebuild - feeds the Reset budget");

   SSR_Verdict("zero_future_leaks", total_leaks == 0, "0 leaks",
               IntegerToString(total_leaks),
               StringFormat("across %d assertions", total_checks));

   SSR_DropSymbol(InpTest);
   SSR_End();
  }
//+------------------------------------------------------------------+
