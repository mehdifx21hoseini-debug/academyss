//+------------------------------------------------------------------+
//|                                                 SSR_Journal.mqh  |
//|                     SS Replay - Trade Journal & Export (L2)      |
//|                                                                  |
//|  The record a trader actually reviews afterwards.                 |
//|                                                                  |
//|  Every row carries its own honesty column. Exporting a set of     |
//|  results into a spreadsheet is exactly where the caveat gets      |
//|  lost - the numbers travel, the warning stays behind - so the     |
//|  flag is a column in the file, not a footnote in the UI.          |
//+------------------------------------------------------------------+
#ifndef SSR_JOURNAL_MQH
#define SSR_JOURNAL_MQH

#include "../Common/SSR_Types.mqh"
#include "../Common/SSR_Time.mqh"
#include "SSR_TradingEngine.mqh"
#include "SSR_Statistics.mqh"
#include "SSR_PropEvaluation.mqh"

#define SSR_JOURNAL_DIR   "SSReplay\\journal"

//+------------------------------------------------------------------+
class CSSRJournal
  {
private:
   CSSRTradingEngine *m_acct;      // not owned
   CSSRStatsEngine   *m_stats;     // not owned; may be NULL
   string             m_last_error;
   string             m_last_path;
   CSSRPropEvaluation *m_prop;      // not owned; may be NULL

   string             Csv(const string s)
     {
      string r = s;
      StringReplace(r, ",", ";");
      StringReplace(r, "\n", " ");
      StringReplace(r, "\r", " ");
      return r;
     }

   //--- Lots at two decimals hide a 0.001 lot as "0.00", which is the
   //--- same lie in a smaller font. Show what is there.
   string             VolumeText(const double v)
     {
      if(v > 0.0 && v < 0.005)
         return DoubleToString(v, 3);
      return DoubleToString(v, 2);
     }

   string             Row(SSRVirtualPosition &p, const int digits)
     {
      return StringFormat(
         "%d,%s,%s,%.2f,%s,%s,%s,%s,%s,%.2f,%.2f,%.2f,%s,%s,%.5f,%.5f,%s,%s",
         (int)p.ticket,
         SSROrderName(p.type),
         Csv(p.tag),
         p.volume_initial,
         SSRFormatMsc(p.open_msc),
         DoubleToString(p.open_price, digits),
         SSRFormatMsc(p.close_msc),
         DoubleToString(p.close_price, digits),
         SSRCloseReasonName(p.reason),
         p.profit, p.commission, p.swap,
         //--- R is left EMPTY, never zero, when it does not exist:
         //--- a zero would be averaged in by whatever reads this next
         (p.HasR() ? DoubleToString(p.RMultiple(), 3) : ""),
         SSRFormatSpan(p.DurationMsc()),
         p.mae, p.mfe,
         (p.ambiguous ? "ASSUMED" : "observed"),
         Csv(p.note));
     }

public:
                     CSSRJournal(void)
     : m_acct(NULL), m_stats(NULL), m_last_error(""), m_last_path(""),
       m_prop(NULL) {}

   //--- the evaluation's verdict belongs in the document, not only on a
   //--- panel that closes with the terminal
   void              AttachProp(CSSRPropEvaluation *p) { m_prop = p; }

   void              Attach(CSSRTradingEngine *a, CSSRStatsEngine *s = NULL)
     { m_acct = a; m_stats = s; }

   string            LastError(void) { return m_last_error; }
   string            LastPath(void)  { return m_last_path; }

   int               Count(void)
     { return (m_acct != NULL ? m_acct.ClosedCount() : 0); }

   //--- one line per trade, for the panel or the log
   string            Line(const int index, const int digits = 5)
     {
      if(m_acct == NULL)
         return "";
      int seen = 0;
      int total = m_acct.Total();
      for(int i = 0; i < total; i++)
        {
         SSRVirtualPosition p;
         if(!m_acct.At(i, p) || !p.IsClosed())
            continue;
         if(seen == index)
            return p.ToString();
         seen++;
        }
      return "";
     }

   //+------------------------------------------------------------------+
   //| Export to CSV.                                                   |
   //|                                                                  |
   //| The header block carries the summary AND its caveat, so a file   |
   //| opened three weeks later still says what its numbers rest on.    |
   //+------------------------------------------------------------------+
   bool              ExportCsv(const string name, const int digits = 5)
     {
      m_last_error = "";
      if(m_acct == NULL)
        { m_last_error = "no account attached"; return false; }

      FolderCreate(SSR_JOURNAL_DIR);
      string path = SSR_JOURNAL_DIR + "\\" + name + ".csv";
      int h = FileOpen(path, FILE_WRITE | FILE_TXT | FILE_ANSI);
      if(h == INVALID_HANDLE)
        { m_last_error = "cannot write " + path; return false; }
      m_last_path = path;

      SSRStatistics st;
      st.Init();
      if(m_stats != NULL)
         m_stats.Compute(st);

      //--- summary first, so the caveat cannot be scrolled past
      FileWriteString(h, "# SS Replay journal\r\n");
      FileWriteString(h, "# exported," + TimeToString(TimeLocal(), TIME_DATE | TIME_SECONDS) + "\r\n");
      if(m_stats != NULL)
        {
         FileWriteString(h, StringFormat("# trades,%d\r\n", st.trades));
         FileWriteString(h, StringFormat("# win_rate,%.2f\r\n", st.win_rate));
         FileWriteString(h, StringFormat("# profit_factor,%.4f\r\n", st.profit_factor));
         FileWriteString(h, StringFormat("# net_profit,%.2f\r\n", st.net_profit));
         FileWriteString(h, StringFormat("# expectancy,%.4f\r\n", st.expectancy));
         FileWriteString(h, StringFormat("# average_r,%.4f\r\n", st.average_r));
         FileWriteString(h, StringFormat("# r_trades,%d of %d\r\n", st.r_trades, st.trades));
         FileWriteString(h, StringFormat("# max_drawdown,%.2f\r\n", st.max_drawdown));
         FileWriteString(h, StringFormat("# max_drawdown_pct,%.2f\r\n", st.max_drawdown_pct));
         FileWriteString(h, StringFormat("# win_streak,%d\r\n", st.win_streak));
         FileWriteString(h, StringFormat("# loss_streak,%d\r\n", st.loss_streak));
         FileWriteString(h, StringFormat("# ambiguous_trades,%d (%.1f%%)\r\n",
                                         st.ambiguous_trades, st.ambiguous_pct));
         FileWriteString(h, StringFormat("# margin_modelled,%s\r\n",
                                         (st.margin_modelled ? "yes" : "no")));
         string caveat = st.Caveat();
         if(caveat != "")
            FileWriteString(h, "# CAVEAT," + Csv(caveat) + "\r\n");
        }

      FileWriteString(h,
         "ticket,type,tag,volume,open_time,open_price,close_time,close_price,"
         "reason,profit,commission,swap,r,duration,mae,mfe,resolution,note\r\n");

      int total = m_acct.Total();
      for(int i = 0; i < total; i++)
        {
         SSRVirtualPosition p;
         if(!m_acct.At(i, p) || !p.IsClosed())
            continue;
         FileWriteString(h, Row(p, digits) + "\r\n");
        }
      FileClose(h);
      return true;
     }

   //+------------------------------------------------------------------+
   //| Export an HTML STATEMENT.                                        |
   //|                                                                  |
   //| The CSV is for a spreadsheet. This is for a person: a trader     |
   //| reviewing their session, or a student handing it in. Same        |
   //| numbers, same caveat, opened by double-clicking.                 |
   //|                                                                  |
   //| It is written to be READ, so the caveat is at the top in amber   |
   //| rather than buried in a comment row. A statement whose header    |
   //| says "23% of these outcomes rest on an assumed tick order" is    |
   //| worth more than one that quietly does not mention it.            |
   //+------------------------------------------------------------------+
   bool              ExportHtml(const string name, const int digits = 5)
     {
      m_last_error = "";
      if(m_acct == NULL)
        { m_last_error = "no account attached"; return false; }

      FolderCreate(SSR_JOURNAL_DIR);
      string path = SSR_JOURNAL_DIR + "\\" + name + ".html";
      int h = FileOpen(path, FILE_WRITE | FILE_TXT | FILE_ANSI);
      if(h == INVALID_HANDLE)
        { m_last_error = "cannot write " + path; return false; }
      m_last_path = path;

      SSRStatistics st;
      st.Init();
      if(m_stats != NULL)
         m_stats.Compute(st);

      FileWriteString(h,
         "<!doctype html><html><head><meta charset=\"utf-8\">\r\n"
         "<title>SS Replay statement</title><style>\r\n"
         "body{font-family:Tahoma,Segoe UI,sans-serif;font-size:13px;color:#16181b;"
         "background:#f5f7f8;margin:0;padding:28px}\r\n"
         ".w{max-width:1000px;margin:0 auto}\r\n"
         "h1{font-size:21px;margin:0 0 4px}\r\n"
         "h2{font-size:13px;margin:26px 0 8px;color:#5c636b;text-transform:uppercase;"
         "letter-spacing:.06em}\r\n"
         ".sub{color:#5c636b;margin:0 0 20px;font-size:12px}\r\n"
         ".caveat{background:#fff6e5;border:1px solid #e3c88a;border-left:4px solid #a35a00;"
         "padding:11px 14px;margin:0 0 20px;color:#5a3d00}\r\n"
         ".kpi{display:flex;flex-wrap:wrap;gap:10px;margin:0 0 22px}\r\n"
         ".kpi div{background:#fff;border:1px solid #dde2e7;padding:10px 14px;min-width:132px}\r\n"
         ".kpi b{display:block;font-size:18px;margin-top:3px}\r\n"
         ".kpi span{font-size:11px;color:#5c636b;text-transform:uppercase;letter-spacing:.04em}\r\n"
         "table{width:100%;border-collapse:collapse;background:#fff;"
         "border:1px solid #dde2e7;font-size:12px}\r\n"
         "th{text-align:left;background:#eef1f4;padding:8px 9px;border-bottom:1px solid #dde2e7;"
         "font-size:11px;text-transform:uppercase;letter-spacing:.04em;color:#5c636b}\r\n"
         "td{padding:7px 9px;border-bottom:1px solid #eef1f4}\r\n"
         "td.n{text-align:right;font-variant-numeric:tabular-nums}\r\n"
         ".g{color:#1c7a45;font-weight:700} .r{color:#b03a2e;font-weight:700}\r\n"
         ".amb{color:#a35a00}\r\n"
         "</style></head><body><div class=\"w\">\r\n");

      FileWriteString(h, "<h1>SS Replay &mdash; session statement</h1>\r\n");
      FileWriteString(h, StringFormat("<p class=\"sub\">%s &nbsp;&middot;&nbsp; %s</p>\r\n",
                      Html(name), TimeToString(TimeLocal(), TIME_DATE | TIME_SECONDS)));

      string caveat = st.Caveat();
      if(caveat != "")
         FileWriteString(h, "<div class=\"caveat\"><b>Read this first.</b><br>" +
                            Html(caveat) + "</div>\r\n");

      //+------------------------------------------------------------------+
      //| THE VERDICT GOES ABOVE THE NUMBERS.                              |
      //|                                                                  |
      //| An evaluation that passed and one that failed can produce the    |
      //| same profit figure - the difference is a rule, and a rule buried |
      //| under a KPI grid is a rule the reader takes on trust. It also    |
      //| carries the RULES, so a statement can be read a year later by    |
      //| someone who does not know what was being attempted.               |
      //+------------------------------------------------------------------+
      if(m_prop != NULL && m_prop.IsOn())
        {
         string cls = "amb";
         if(m_prop.State() == SSR_PROP_PASSED) cls = "g";
         if(m_prop.State() == SSR_PROP_FAILED) cls = "r";
         FileWriteString(h, StringFormat(
            "<div class=\"caveat\"><b>Evaluation: "
            "<span class=\"%s\">%s</span></b><br>%s<br>%s</div>\r\n",
            cls, Html(m_prop.StateName()),
            Html(m_prop.Report()),
            Html(m_prop.Reason())));
        }

      FileWriteString(h, "<div class=\"kpi\">\r\n");
      FileWriteString(h, StringFormat("<div><span>Trades</span><b>%d</b></div>\r\n", st.trades));
      FileWriteString(h, StringFormat("<div><span>Net profit</span><b class=\"%s\">%.2f</b></div>\r\n",
                      (st.net_profit >= 0 ? "g" : "r"), st.net_profit));
      FileWriteString(h, StringFormat("<div><span>Win rate</span><b>%.1f%%</b></div>\r\n", st.win_rate));
      FileWriteString(h, StringFormat("<div><span>Profit factor</span><b>%.2f</b></div>\r\n", st.profit_factor));
      FileWriteString(h, StringFormat("<div><span>Expectancy</span><b>%.2f</b></div>\r\n", st.expectancy));
      FileWriteString(h, StringFormat("<div><span>Average R</span><b>%.2f</b></div>\r\n", st.average_r));
      FileWriteString(h, StringFormat("<div><span>Max drawdown</span><b class=\"r\">%.2f (%.1f%%)</b></div>\r\n",
                      st.max_drawdown, st.max_drawdown_pct));
      FileWriteString(h, StringFormat("<div><span>Win / loss streak</span><b>%d / %d</b></div>\r\n",
                      st.win_streak, st.loss_streak));
      FileWriteString(h, StringFormat("<div><span>Assumed tick order</span><b class=\"amb\">%d (%.1f%%)</b></div>\r\n",
                      st.ambiguous_trades, st.ambiguous_pct));
      FileWriteString(h, "</div>\r\n");

      //+------------------------------------------------------------------+
      //| THE SETUP BREAKDOWN.                                             |
      //|                                                                  |
      //| One line per tag, with the same measures as the header. This is  |
      //| the whole point of typing a setup name: a 44% win rate across a  |
      //| session says nothing a trader can act on, while "breakouts 61%,  |
      //| fades 22%" says stop trading fades.                              |
      //|                                                                  |
      //| Printed only when there are at least two setups. With one, every |
      //| row would repeat the header exactly, and a table that restates   |
      //| the numbers above it teaches the reader to skip tables.          |
      //+------------------------------------------------------------------+
      string tags[];
      double nets[];
      int    ntags = CollectTags(tags, nets);
      if(ntags > 1 && m_stats != NULL)
        {
         FileWriteString(h,
            "<h2>By setup</h2>\r\n"
            "<table><tr><th>Setup</th><th class=\"n\">Trades</th>"
            "<th class=\"n\">Win rate</th><th class=\"n\">Profit factor</th>"
            "<th class=\"n\">Expectancy</th><th class=\"n\">Average R</th>"
            "<th class=\"n\">Net</th></tr>\r\n");
         for(int t = 0; t < ntags; t++)
           {
            SSRStatistics ts;
            ts.Init();
            m_stats.ComputeFor(tags[t], ts);
            FileWriteString(h, StringFormat(
               "<tr><td>%s</td><td class=\"n\">%d</td><td class=\"n\">%.1f%%</td>"
               "<td class=\"n\">%.2f</td><td class=\"n\">%.2f</td>"
               "<td class=\"n\">%s</td>"
               "<td class=\"n\"><span class=\"%s\">%.2f</span></td></tr>\r\n",
               Html(tags[t] == "" ? "(untagged)" : tags[t]),
               ts.trades, ts.win_rate, ts.profit_factor, ts.expectancy,
               (ts.r_trades > 0 ? DoubleToString(ts.average_r, 2) : "-"),
               (ts.net_profit >= 0 ? "g" : "r"), ts.net_profit));
           }
         FileWriteString(h, "</table>\r\n");
        }

      FileWriteString(h, "<h2>Trades</h2>\r\n");
      FileWriteString(h,
         "<table><tr><th>#</th><th>Type</th><th>Tag</th><th class=\"n\">Volume</th>"
         "<th>Opened</th><th class=\"n\">Price</th><th>Closed</th><th class=\"n\">Price</th>"
         "<th>Reason</th><th class=\"n\">R</th><th class=\"n\">Profit</th></tr>\r\n");

      int total = m_acct.Total();
      for(int i = 0; i < total; i++)
        {
         SSRVirtualPosition p;
         if(!m_acct.At(i, p) || !p.IsClosed())
            continue;
         double net = p.profit + p.swap - p.commission;
         FileWriteString(h, StringFormat(
            "<tr><td>%d</td><td>%s</td><td>%s</td><td class=\"n\">%s</td>"
            "<td>%s</td><td class=\"n\">%s</td><td>%s</td><td class=\"n\">%s</td>"
            "<td>%s%s</td><td class=\"n\">%s</td>"
            "<td class=\"n\"><span class=\"%s\">%.2f</span></td></tr>\r\n",
            (int)p.ticket,
            (SSRIsLong(p.type) ? "BUY" : "SELL"),
            Html(p.tag),
            //+------------------------------------------------------------------+
            //| volume_initial, NOT volume.                                      |
            //|                                                                  |
            //| `volume` is what REMAINS - zero for every closed trade - so the  |
            //| statement reported "0.00 lots" for two real 0.21 lot trades that |
            //| had lost a hundred dollars between them. A statement that        |
            //| contradicts its own profit column is worse than no statement:    |
            //| it is a document the user might show someone.                    |
            //|                                                                  |
            //| The CSV export next door had it right all along, which is how a  |
            //| single field can be wrong in one place for a whole release.      |
            //+------------------------------------------------------------------+
            VolumeText(p.volume_initial),
            SSRFormatMsc(p.open_msc),  DoubleToString(p.open_price, digits),
            SSRFormatMsc(p.close_msc), DoubleToString(p.close_price, digits),
            SSRCloseReasonName(p.reason),
            (p.ambiguous ? " <span class=\"amb\">(assumed)</span>" : ""),
            (p.HasR() ? DoubleToString(p.RMultiple(), 2) : "-"),
            (net >= 0 ? "g" : "r"), net));
        }

      FileWriteString(h, "</table>\r\n</div></body></html>\r\n");
      FileClose(h);
      return true;
     }

   //+------------------------------------------------------------------+
   //| WHICH SETUPS THE SESSION ACTUALLY CONTAINED.                     |
   //|                                                                  |
   //| Read from the trades rather than from a list the user maintains: |
   //| a tag exists because it was traded, and a tag that was typed once|
   //| and never used should not occupy a row in the report.            |
   //|                                                                  |
   //| Ordered by net result, worst last, because the reason to break   |
   //| a session down by setup is to find the one to stop trading.      |
   //+------------------------------------------------------------------+
   int               CollectTags(string &tags[], double &nets[])
     {
      ArrayResize(tags, 0);
      ArrayResize(nets, 0);
      if(m_acct == NULL)
         return 0;

      int total = m_acct.Total();
      for(int i = 0; i < total; i++)
        {
         SSRVirtualPosition p;
         if(!m_acct.At(i, p) || !p.IsClosed())
            continue;

         int at = -1;
         for(int k = 0; k < ArraySize(tags) && at < 0; k++)
            if(tags[k] == p.tag)
               at = k;
         if(at < 0)
           {
            at = ArraySize(tags);
            ArrayResize(tags, at + 1);
            ArrayResize(nets, at + 1);
            tags[at] = p.tag;
            nets[at] = 0.0;
           }
         nets[at] += p.profit + p.swap - p.commission;
        }

      //--- a handful of tags at most; an insertion sort is the honest
      //--- size of the problem
      for(int i = 1; i < ArraySize(tags); i++)
        {
         string t = tags[i];
         double v = nets[i];
         int    j = i - 1;
         while(j >= 0 && nets[j] < v)
           { tags[j + 1] = tags[j]; nets[j + 1] = nets[j]; j--; }
         tags[j + 1] = t;
         nets[j + 1] = v;
        }
      return ArraySize(tags);
     }

   //--- HTML has five characters that must never arrive raw, or a tag
   //--- in a user's session name silently eats the rest of the page
   string            Html(const string in)
     {
      string o = in;
      StringReplace(o, "&", "&amp;");
      StringReplace(o, "<", "&lt;");
      StringReplace(o, ">", "&gt;");
      StringReplace(o, "\"", "&quot;");
      return o;
     }

   //--- a compact summary for the panel and the log
   string            Summary(void)
     {
      if(m_stats == NULL)
         return "no statistics attached";
      SSRStatistics st;
      m_stats.Compute(st);
      string s = st.ToString();
      string c = st.Caveat();
      return (c == "" ? s : s + "\n  " + c);
     }
  };

#endif // SSR_JOURNAL_MQH
//+------------------------------------------------------------------+
