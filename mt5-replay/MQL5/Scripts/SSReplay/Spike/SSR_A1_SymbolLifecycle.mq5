//+------------------------------------------------------------------+
//|                                       SSR_A1_SymbolLifecycle.mq5 |
//|  SPIKE A1 - Custom Symbol Lifecycle & Spec Fidelity              |
//|  TIER A - BLOCKER                                                |
//|                                                                  |
//|  Hypothesis: CustomSymbolCreate(name, path, origin) copies every |
//|  trading spec from the origin symbol, and CustomSymbolDelete     |
//|  removes the symbol without residue.                             |
//|                                                                  |
//|  PASS: all 12 critical properties identical to origin,           |
//|        symbol deletable, max name length recorded.               |
//+------------------------------------------------------------------+
#property script_show_inputs

#include <SSReplay/Spike/SSR_SpikeKit.mqh>

input string InpOrigin = "US30Cash";   // Origin symbol (must exist at the broker)
input string InpTest   = "SSRA1";      // Test symbol name

//+------------------------------------------------------------------+
int CompareLong(const string sym, const string origin, const ENUM_SYMBOL_INFO_INTEGER p, const string name)
  {
   long a = SymbolInfoInteger(origin, p);
   long b = SymbolInfoInteger(sym, p);
   SSR_Verdict("prop_" + name, a == b, IntegerToString(a), IntegerToString(b), "integer property");
   return (a == b) ? 0 : 1;
  }

int CompareDouble(const string sym, const string origin, const ENUM_SYMBOL_INFO_DOUBLE p, const string name)
  {
   double a = SymbolInfoDouble(origin, p);
   double b = SymbolInfoDouble(sym, p);
   bool ok = MathAbs(a - b) < 1e-12;
   SSR_Verdict("prop_" + name, ok, DoubleToString(a, 10), DoubleToString(b, 10), "double property");
   return ok ? 0 : 1;
  }

int CompareString(const string sym, const string origin, const ENUM_SYMBOL_INFO_STRING p, const string name)
  {
   string a = SymbolInfoString(origin, p);
   string b = SymbolInfoString(sym, p);
   SSR_Verdict("prop_" + name, a == b, a, b, "string property");
   return (a == b) ? 0 : 1;
  }

//+------------------------------------------------------------------+
void OnStart()
  {
   SSR_Begin("A1_SymbolLifecycle");

   //--- 0. origin must be available
   if(!SymbolSelect(InpOrigin, true))
     {
      SSR_Verdict("origin_available", false, "selectable", "SymbolSelect failed",
                  "err=" + IntegerToString(GetLastError()));
      SSR_End();
      return;
     }
   SSR_Verdict("origin_available", true, "selectable", "ok", InpOrigin);

   //--- 1. creation
   SSR_DropSymbol(InpTest);
   ulong t0 = SSR_Now();
   ResetLastError();
   bool created = CustomSymbolCreate(InpTest, "SSReplay\\Spike", InpOrigin);
   double t_create = SSR_ElapsedMs(t0);
   int err_create = GetLastError();

   SSR_Metric("create", "elapsed", t_create, "ms");
   if(!SSR_Verdict("symbol_created", created, "true", (created ? "true" : "false"),
                   "err=" + IntegerToString(err_create)))
     {
      SSR_End();
      return;
     }

   t0 = SSR_Now();
   bool selected = SymbolSelect(InpTest, true);
   SSR_Metric("select", "elapsed", SSR_ElapsedMs(t0), "ms");
   SSR_Verdict("symbol_selected", selected, "true", (selected ? "true" : "false"), "");

   //--- 2. the 12 critical properties for correct lot / PnL maths
   int bad = 0;
   bad += CompareLong  (InpTest, InpOrigin, SYMBOL_DIGITS,              "DIGITS");
   bad += CompareDouble(InpTest, InpOrigin, SYMBOL_POINT,               "POINT");
   bad += CompareDouble(InpTest, InpOrigin, SYMBOL_TRADE_TICK_SIZE,     "TRADE_TICK_SIZE");
   bad += CompareDouble(InpTest, InpOrigin, SYMBOL_TRADE_TICK_VALUE,    "TRADE_TICK_VALUE");
   bad += CompareDouble(InpTest, InpOrigin, SYMBOL_TRADE_CONTRACT_SIZE, "TRADE_CONTRACT_SIZE");
   bad += CompareDouble(InpTest, InpOrigin, SYMBOL_VOLUME_MIN,          "VOLUME_MIN");
   bad += CompareDouble(InpTest, InpOrigin, SYMBOL_VOLUME_MAX,          "VOLUME_MAX");
   bad += CompareDouble(InpTest, InpOrigin, SYMBOL_VOLUME_STEP,         "VOLUME_STEP");
   bad += CompareDouble(InpTest, InpOrigin, SYMBOL_MARGIN_INITIAL,      "MARGIN_INITIAL");
   bad += CompareString(InpTest, InpOrigin, SYMBOL_CURRENCY_BASE,       "CURRENCY_BASE");
   bad += CompareString(InpTest, InpOrigin, SYMBOL_CURRENCY_PROFIT,     "CURRENCY_PROFIT");
   bad += CompareString(InpTest, InpOrigin, SYMBOL_CURRENCY_MARGIN,     "CURRENCY_MARGIN");

   SSR_Metric("spec_fidelity", "properties_checked", 12, "count");
   SSR_Metric("spec_fidelity", "properties_mismatch", (double)bad, "count",
              (bad == 0 ? "clone is faithful" : "PLAN B: manual property map required"));

   //--- 3. can we override what the engine needs to override?
   ResetLastError();
   bool sf = CustomSymbolSetInteger(InpTest, SYMBOL_SPREAD_FLOAT, true);
   SSR_Verdict("set_spread_float", sf, "true", (sf ? "true" : "false"),
               "err=" + IntegerToString(GetLastError()));

   ResetLastError();
   bool tm = CustomSymbolSetInteger(InpTest, SYMBOL_TRADE_MODE, SYMBOL_TRADE_MODE_DISABLED);
   SSR_Verdict("set_trade_disabled", tm, "true", (tm ? "true" : "false"),
               "err=" + IntegerToString(GetLastError()));

   ResetLastError();
   SSR_Set247Sessions(InpTest);
   SSR_Verdict("set_sessions_247", GetLastError() == 0, "err=0",
               "err=" + IntegerToString(GetLastError()), "24/7 quote+trade");

   //--- 4. maximum symbol name length: grow until the terminal refuses
   int max_len = 0;
   for(int len = 4; len <= 64; len++)
     {
      string probe = "";
      for(int i = 0; i < len; i++)
         probe += "A";
      ResetLastError();
      if(CustomSymbolCreate(probe, "SSReplay\\Spike\\len"))
        {
         max_len = len;
         CustomSymbolDelete(probe);
        }
      else
         break;
     }
   SSR_Metric("naming", "max_symbol_name_length", (double)max_len, "chars",
              "drives the <SRC>.SSR<slot> naming convention");
   SSR_Verdict("name_len_usable", max_len >= 16, ">=16", IntegerToString(max_len),
               "need room for symbol + suffix");

   //--- 5. deletion must be clean
   t0 = SSR_Now();
   SymbolSelect(InpTest, false);
   ResetLastError();
   bool deleted = CustomSymbolDelete(InpTest);
   double t_delete = SSR_ElapsedMs(t0);
   int err_delete = GetLastError();

   SSR_Metric("delete", "elapsed", t_delete, "ms");
   SSR_Verdict("symbol_deleted", deleted, "true", (deleted ? "true" : "false"),
               "err=" + IntegerToString(err_delete));

   ResetLastError();
   long dig_after = SymbolInfoInteger(InpTest, SYMBOL_DIGITS);
   int  err_after = GetLastError();
   SSR_Verdict("no_residue_after_delete", err_after != 0, "error!=0",
               StringFormat("err=%d digits=%d", err_after, (int)dig_after),
               "reading a deleted symbol must fail");

   //--- 6. delete must be refused while a chart is open (orderly teardown matters)
   if(SSR_MakeSymbol(InpTest, InpOrigin))
     {
      long cid = ChartOpen(InpTest, PERIOD_M1);
      Sleep(500);
      ResetLastError();
      bool del_with_chart = CustomSymbolDelete(InpTest);
      int err_wc = GetLastError();
      SSR_Metric("teardown", "delete_with_open_chart", (del_with_chart ? 1 : 0), "bool",
                 "err=" + IntegerToString(err_wc));
      if(cid != 0)
         ChartClose(cid);
      Sleep(500);
      SSR_DropSymbol(InpTest);
     }

   SSR_End();
  }
//+------------------------------------------------------------------+
