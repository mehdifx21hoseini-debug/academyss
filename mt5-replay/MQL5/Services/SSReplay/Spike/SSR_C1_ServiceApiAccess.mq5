//+------------------------------------------------------------------+
//|                                     SSR_C1_ServiceApiAccess.mq5  |
//|  SPIKE C1 - Service Access to Custom* APIs                       |
//|  TIER C - CRITICAL  (decides Core = Service vs Core = EA)        |
//|                                                                  |
//|  A Service has no chart. If it can still drive every operation   |
//|  the replay engine needs, then engine state can be decoupled     |
//|  from the chart lifecycle - which is the whole point of the      |
//|  "change timeframe without breaking replay" requirement.         |
//|                                                                  |
//|  Install: copy to MQL5\Services\SSReplay\Spike, compile, then in |
//|  Navigator -> Services right-click -> Add service -> Start.      |
//|  Runs once and exits. Read the Experts log and results.csv.      |
//+------------------------------------------------------------------+
#property service

#include <SSReplay/Spike/SSR_SpikeKit.mqh>

input string   InpOrigin = "US30Cash";           // Origin symbol
input string   InpTest   = "SSRC1";              // Test symbol
input datetime InpStart  = D'2024.01.08 00:00';  // Start time
input double   InpBase   = 38000.0;              // Base price

//+------------------------------------------------------------------+
bool Op(const string name, const bool ok, const int err, const double elapsed_us)
  {
   SSR_Metric("service_op", name, elapsed_us, "us", "err=" + IntegerToString(err));
   return SSR_Verdict("service_can_" + name, ok && err == 0, "ok/err=0",
                      StringFormat("%s/err=%d", (ok ? "ok" : "fail"), err),
                      "operation available inside a Service");
  }

//+------------------------------------------------------------------+
void OnStart()
  {
   SSR_Begin("C1_ServiceApiAccess");
   Print("[C1] running inside a SERVICE - no chart context expected");
   SSR_Metric("context", "chart_id", (double)ChartID(), "id",
              "a Service is expected to report 0");

   int    digits = 5;
   double point  = 0.00001;
   ulong  t0;

   //--- 1. create
   SSR_DropSymbol(InpTest);
   t0 = SSR_Now();
   ResetLastError();
   bool r = CustomSymbolCreate(InpTest, "SSReplay\\Spike", InpOrigin);
   Op("CustomSymbolCreate", r, GetLastError(), SSR_ElapsedUs(t0));
   if(!r) { SSR_End(); return; }

   digits = (int)SymbolInfoInteger(InpTest, SYMBOL_DIGITS);
   point  = SymbolInfoDouble(InpTest, SYMBOL_POINT);
   if(point <= 0.0) point = MathPow(10, -digits);

   //--- 2. set integer property
   t0 = SSR_Now();
   ResetLastError();
   r = CustomSymbolSetInteger(InpTest, SYMBOL_SPREAD_FLOAT, true);
   Op("CustomSymbolSetInteger", r, GetLastError(), SSR_ElapsedUs(t0));

   //--- 3. set sessions
   t0 = SSR_Now();
   ResetLastError();
   r = CustomSymbolSetSessionQuote(InpTest, MONDAY, 0, (datetime)0, (datetime)86399);
   Op("CustomSymbolSetSessionQuote", r, GetLastError(), SSR_ElapsedUs(t0));
   SSR_Set247Sessions(InpTest);

   //--- 4. select into Market Watch (required for tick broadcast)
   t0 = SSR_Now();
   ResetLastError();
   r = SymbolSelect(InpTest, true);
   Op("SymbolSelect", r, GetLastError(), SSR_ElapsedUs(t0));

   //--- 5. write rates
   MqlRates m1[];
   int n = SSR_GenM1(m1, InpStart, 60, InpBase, point, digits);
   t0 = SSR_Now();
   ResetLastError();
   int w = CustomRatesUpdate(InpTest, m1);
   Op("CustomRatesUpdate", w == n, GetLastError(), SSR_ElapsedUs(t0));
   SSR_Metric("service_op", "rates_written", (double)w, "count");

   //--- 6. sleep - the reason a Service can host the engine loop at all
   t0 = SSR_Now();
   ResetLastError();
   Sleep(100);
   double slept = SSR_ElapsedMs(t0);
   Op("Sleep", slept >= 90.0, GetLastError(), slept * 1000.0);
   SSR_Metric("service_op", "sleep_actual", slept, "ms", "requested 100ms");

   //--- 7. read rates back
   MqlRates back[];
   ArraySetAsSeries(back, false);
   t0 = SSR_Now();
   ResetLastError();
   int nb = CopyRates(InpTest, PERIOD_M1, m1[0].time, m1[n - 1].time, back);
   Op("CopyRates", nb > 0, GetLastError(), SSR_ElapsedUs(t0));
   SSR_Metric("service_op", "rates_read", (double)nb, "count");

   //--- 8. inject ticks
   MqlTick tk[];
   SSR_BarToTicks(m1[n - 1], tk, 20, 20 * point, digits);
   t0 = SSR_Now();
   ResetLastError();
   int acc = CustomTicksAdd(InpTest, tk);
   Op("CustomTicksAdd", acc > 0, GetLastError(), SSR_ElapsedUs(t0));
   SSR_Metric("service_op", "ticks_accepted", (double)acc, "count");

   //--- 9. read ticks back
   MqlTick rb[];
   t0 = SSR_Now();
   ResetLastError();
   int nt = CopyTicksRange(InpTest, rb, COPY_TICKS_ALL,
                           (long)m1[n - 1].time * 1000,
                           (long)(m1[n - 1].time + 60) * 1000);
   Op("CopyTicksRange", nt > 0, GetLastError(), SSR_ElapsedUs(t0));
   SSR_Metric("service_op", "ticks_read", (double)nt, "count");

   //--- 10. delete a range (needed for Reset and Rewind)
   t0 = SSR_Now();
   ResetLastError();
   int dr = CustomRatesDelete(InpTest, m1[0].time, m1[10].time);
   Op("CustomRatesDelete", dr >= 0, GetLastError(), SSR_ElapsedUs(t0));

   t0 = SSR_Now();
   ResetLastError();
   int dt = CustomTicksDelete(InpTest, (long)m1[0].time * 1000, (long)m1[10].time * 1000);
   Op("CustomTicksDelete", dt >= 0, GetLastError(), SSR_ElapsedUs(t0));

   //--- 11. file IO (the fat IPC channel)
   t0 = SSR_Now();
   ResetLastError();
   FolderCreate(SSR_DIR);
   int fh = FileOpen("SSR_Spike\\c1_service_probe.txt",
                     FILE_WRITE | FILE_TXT | FILE_ANSI);
   bool file_ok = (fh != INVALID_HANDLE);
   if(file_ok)
     {
      FileWriteString(fh, "service file io ok " + SSR_Utc() + "\r\n");
      FileClose(fh);
     }
   Op("FileIO", file_ok, GetLastError(), SSR_ElapsedUs(t0));

   //--- 12. global variables (the fast IPC channel)
   t0 = SSR_Now();
   ResetLastError();
   GlobalVariableSet("SSR.c1.probe", 12345.678);
   double gv = GlobalVariableGet("SSR.c1.probe");
   bool gv_ok = MathAbs(gv - 12345.678) < 1e-9;
   Op("GlobalVariables", gv_ok, GetLastError(), SSR_ElapsedUs(t0));
   GlobalVariableDel("SSR.c1.probe");

   //--- teardown
   t0 = SSR_Now();
   ResetLastError();
   SymbolSelect(InpTest, false);
   r = CustomSymbolDelete(InpTest);
   Op("CustomSymbolDelete", r, GetLastError(), SSR_ElapsedUs(t0));

   SSR_End();
   Print("[C1] service finished - stop it from Navigator if it does not exit");
  }
//+------------------------------------------------------------------+
