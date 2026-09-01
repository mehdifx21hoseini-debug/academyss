//+------------------------------------------------------------------+
//|                                              SSR_ClassReport.mq5 |
//|                 SS Replay - Twenty Students, One Session         |
//|                                                                  |
//|  HOW TO USE IT                                                   |
//|                                                                  |
//|  1. Give everyone the same seed. Same seed, same candles, bar     |
//|     for bar - that has worked since Phase 11 and is the only      |
//|     reason this script can exist.                                |
//|  2. Each of them presses Statement on the panel, which also       |
//|     writes a .csv beside the page.                                |
//|  3. Put those files in  MQL5\Files\SSReplay\class  and RENAME     |
//|     each one to the student's name. The file name IS the name -   |
//|     there is no form to fill in, because a form is a step         |
//|     somebody skips.                                              |
//|  4. Run this. It writes MQL5\Files\SSReplay\class-report.html     |
//|                                                                  |
//|  It is a shell. Everything it does lives in a header, so the      |
//|  smoke test can run the same code without running a script.       |
//+------------------------------------------------------------------+
#property script_show_inputs
#property description "Reads every student's journal CSV and builds one comparison page."

#include <SSReplay/Common/SSR_Build.mqh>
#include <SSReplay/Report/SSR_ClassReport.mqh>

input string InpFolder = SSR_CLASS_DIR;   // Folder under MQL5\Files
input string InpOut    = SSR_CLASS_OUT;   // Page to write

//+------------------------------------------------------------------+
void OnStart()
  {
   PrintFormat("=== SS Replay class report === build %s", SSR_BUILD);

   CSSRClassReport rep;
   int n = rep.Scan(InpFolder);
   if(n == 0)
     {
      Print("[class] ", rep.LastError());
      return;
     }

   int readable = 0;
   for(int i = 0; i < n; i++)
     {
      SSRStudent s;
      if(rep.At(i, s) && s.parsed)
         readable++;
     }

   PrintFormat("[class] %d file(s), %d readable, %d ran the same session",
               n, readable, rep.Agreeing());

   //--- NAMED, not counted. A coach who is told "three files disagree"
   //--- has to open all twenty to find out which.
   for(int i = 0; i < n; i++)
     {
      SSRStudent s;
      if(!rep.At(i, s))
         continue;
      if(!s.parsed)
         PrintFormat("[class]   %-24s COULD NOT READ - %s", s.name, s.problem);
      else
         if(rep.Key() != "" && s.key != rep.Key())
            PrintFormat("[class]   %-24s ran a DIFFERENT session - not "
                        "comparable with the rest", s.name);
     }

   if(!rep.Write(InpOut))
     {
      Print("[class] could not write the page: ", rep.LastError());
      return;
     }
   PrintFormat("[class] wrote MQL5\\Files\\%s - open it in a browser",
               rep.LastPath());
  }
//+------------------------------------------------------------------+
