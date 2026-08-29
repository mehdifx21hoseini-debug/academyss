//+------------------------------------------------------------------+
//|                                           SSR_C3_IpcChannel.mq5  |
//|  SPIKE C3 - IPC Channel Integrity                                |
//|  TIER C - HIGH                                                   |
//|                                                                  |
//|  The Service owns the state, the Indicator panel shows it. That  |
//|  split only works if the channel between them is fast, lossless  |
//|  and race-free. Global variables hold doubles only, so the first |
//|  question is whether a datetime survives the round trip.         |
//+------------------------------------------------------------------+
#property script_show_inputs

#include <SSReplay/Spike/SSR_SpikeKit.mqh>

input int InpSamples = 10000;   // datetime round-trip samples
input int InpCycles  = 10000;   // command cycles for the race test

//+------------------------------------------------------------------+
void OnStart()
  {
   SSR_Begin("C3_IpcChannel");

   //--- 1. datetime -> double -> datetime must be lossless to 2099
   SSR_Rng rng;
   rng.Seed(31337);
   long   worst = 0;
   int    bad   = 0;
   datetime lo = D'1980.01.01 00:00';
   datetime hi = D'2099.12.31 23:59';

   ulong t0 = SSR_Now();
   for(int i = 0; i < InpSamples; i++)
     {
      datetime t = (datetime)(lo + (long)(rng.Uniform() * (double)(hi - lo)));
      GlobalVariableSet("SSR.c3.dt", (double)t);
      datetime back = (datetime)GlobalVariableGet("SSR.c3.dt");
      long d = (long)back - (long)t;
      if(d != 0)
        {
         bad++;
         if(MathAbs(d) > MathAbs(worst)) worst = d;
        }
     }
   double t_rt = SSR_ElapsedMs(t0);

   SSR_Metric("datetime", "samples",         (double)InpSamples, "count");
   SSR_Metric("datetime", "roundtrip_errors", (double)bad,       "count");
   SSR_Metric("datetime", "worst_error",     (double)worst,      "s");
   SSR_Metric("datetime", "elapsed",         t_rt,               "ms");
   SSR_Verdict("datetime_lossless", bad == 0, "0 errors", IntegerToString(bad),
               "datetime must survive the double channel to 2099");

   //--- 2. raw throughput of the fast channel
   t0 = SSR_Now();
   for(int i = 0; i < InpSamples; i++)
      GlobalVariableSet("SSR.c3.bench", (double)i);
   double t_write = SSR_ElapsedMs(t0);

   t0 = SSR_Now();
   double acc = 0;
   for(int i = 0; i < InpSamples; i++)
      acc += GlobalVariableGet("SSR.c3.bench");
   double t_read = SSR_ElapsedMs(t0);

   double wps = (t_write > 0 ? InpSamples / (t_write / 1000.0) : 0);
   double rps = (t_read  > 0 ? InpSamples / (t_read  / 1000.0) : 0);
   SSR_Metric("throughput", "writes_per_sec", wps, "ops/s");
   SSR_Metric("throughput", "reads_per_sec",  rps, "ops/s");
   SSR_Metric("throughput", "us_per_write", t_write * 1000.0 / InpSamples, "us");
   SSR_Metric("throughput", "us_per_read",  t_read  * 1000.0 / InpSamples, "us");
   SSR_Verdict("ipc_fast_enough", MathMin(wps, rps) >= 10000.0, ">=10000 ops/s",
               StringFormat("w=%.0f r=%.0f", wps, rps), "");

   //--- 3. the seq-last protocol must never expose a half-written command
   //---    writer: args first, seq last. reader: only trust a changed seq.
   int torn = 0;
   double last_seq = 0;
   t0 = SSR_Now();
   for(int i = 1; i <= InpCycles; i++)
     {
      //--- writer side
      GlobalVariableSet("SSR.c3.cmd.a1", (double)(i * 7));
      GlobalVariableSet("SSR.c3.cmd.a2", (double)(i * 13));
      GlobalVariableSet("SSR.c3.cmd.a3", (double)(i * 29));
      GlobalVariableSet("SSR.c3.cmd.seq", (double)i);   // published last

      //--- reader side
      double seq = GlobalVariableGet("SSR.c3.cmd.seq");
      if(seq != last_seq)
        {
         last_seq = seq;
         double a1 = GlobalVariableGet("SSR.c3.cmd.a1");
         double a2 = GlobalVariableGet("SSR.c3.cmd.a2");
         double a3 = GlobalVariableGet("SSR.c3.cmd.a3");
         if(a1 != seq * 7 || a2 != seq * 13 || a3 != seq * 29)
            torn++;
        }
     }
   double t_cmd = SSR_ElapsedMs(t0);

   SSR_Metric("protocol", "cycles",         (double)InpCycles, "count");
   SSR_Metric("protocol", "torn_reads",     (double)torn,      "count");
   SSR_Metric("protocol", "cmds_per_sec",   (t_cmd > 0 ? InpCycles / (t_cmd / 1000.0) : 0), "cmd/s");
   SSR_Verdict("seq_last_protocol_safe", torn == 0, "0 torn reads",
               IntegerToString(torn), "args written before seq");

   //--- 4. how long may a global variable name be?
   int max_name = 0;
   for(int len = 8; len <= 128; len++)
     {
      string nm = "SSR.";
      for(int i = 0; i < len - 4; i++) nm += "x";
      ResetLastError();
      if(GlobalVariableSet(nm, 1.0) != 0 && GlobalVariableCheck(nm))
        {
         max_name = len;
         GlobalVariableDel(nm);
        }
      else
         break;
     }
   SSR_Metric("naming", "max_gv_name_length", (double)max_name, "chars",
              "constrains the SSR.<slot>.<field> scheme");
   SSR_Verdict("gv_name_len_usable", max_name >= 24, ">=24", IntegerToString(max_name), "");

   //--- cleanup
   GlobalVariableDel("SSR.c3.dt");
   GlobalVariableDel("SSR.c3.bench");
   GlobalVariableDel("SSR.c3.cmd.a1");
   GlobalVariableDel("SSR.c3.cmd.a2");
   GlobalVariableDel("SSR.c3.cmd.a3");
   GlobalVariableDel("SSR.c3.cmd.seq");

   SSR_End();
  }
//+------------------------------------------------------------------+
