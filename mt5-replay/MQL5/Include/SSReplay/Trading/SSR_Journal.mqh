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
#include "SSR_ShotBook.mqh"
#include "../Report/SSR_ReportStyle.mqh"

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
   CSSRShotBook       *m_shots;     // not owned; may be NULL

   //+------------------------------------------------------------------+
   //| WHICH SESSION THIS IS A REPORT ON.                               |
   //|                                                                  |
   //| Twenty students can be handed the same seed and get bar-for-bar   |
   //| the same session. Without these four fields in the file, a coach  |
   //| comparing their results has no way to tell the one who ran a      |
   //| different window from the one who traded badly - and would        |
   //| conclude the second about the first.                             |
   //+------------------------------------------------------------------+
   string             m_sess_name;
   string             m_sess_symbol;
   long               m_sess_start;
   long               m_sess_end;
   string             m_sess_seed;

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
       m_prop(NULL), m_shots(NULL), m_sess_name(""), m_sess_symbol(""),
       m_sess_start(0), m_sess_end(0), m_sess_seed("") {}

   //--- the evaluation's verdict belongs in the document, not only on a
   //--- panel that closes with the terminal
   void              AttachProp(CSSRPropEvaluation *p) { m_prop = p; }

   //--- the pictures, if anyone was taking them. Without this the Chart
   //--- column is simply absent rather than empty, which is the honest
   //--- shape for a feature that was switched off.
   void              AttachShots(CSSRShotBook *s)      { m_shots = s; }

   //--- the host knows all of this and the journal cannot ask for it:
   //--- the window belongs to the controller and the seed to the
   //--- randomiser, and neither is something a report should reach into
   void              SetSession(const string name, const string symbol,
                                const long start_msc, const long end_msc,
                                const string seed)
     {
      m_sess_name   = name;
      m_sess_symbol = symbol;
      m_sess_start  = start_msc;
      m_sess_end    = end_msc;
      m_sess_seed   = seed;
     }

   //--- ONE STRING THAT IS EQUAL FOR TWO PEOPLE WHO RAN THE SAME THING.
   //--- The class report groups on it, so it must not carry anything
   //--- that differs between two identical sessions - no export time,
   //--- no student name, no balance.
   string            SessionKey(void)
     {
      return StringFormat("%s|%I64d|%I64d|%s", m_sess_symbol,
                          m_sess_start, m_sess_end, m_sess_seed);
     }

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

      //--- WHAT SESSION THIS WAS, before any result. A file that says
      //--- what it is a report on can be checked against another one;
      //--- a file that only says how it went cannot.
      FileWriteString(h, "# session," + Csv(m_sess_name) + "\r\n");
      FileWriteString(h, "# symbol," + Csv(m_sess_symbol) + "\r\n");
      FileWriteString(h, StringFormat("# window_start,%I64d\r\n", m_sess_start));
      FileWriteString(h, StringFormat("# window_end,%I64d\r\n", m_sess_end));
      FileWriteString(h, "# seed," + Csv(m_sess_seed) + "\r\n");
      FileWriteString(h, "# session_key," + Csv(SessionKey()) + "\r\n");
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

      SSRWriteReportHead(h, "SS Replay statement");

      FileWriteString(h, "<div class=\"top\"><div>\r\n");
      FileWriteString(h, "<h1>SS Replay &mdash; session statement</h1>\r\n");
      FileWriteString(h, StringFormat("<p class=\"sub\">%s &nbsp;&middot;&nbsp; %s</p>\r\n",
                      Html(name), TimeToString(TimeLocal(), TIME_DATE | TIME_SECONDS)));
      FileWriteString(h, "</div><button class=\"thm\" id=\"thm\">Dark</button></div>\r\n");

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
      //--- no count here on purpose: "nine of thirty-one" was written
      //--- when the table below had thirty-three rows, and a number in
      //--- prose is a number nothing recomputes
      FileWriteString(h, "<p class=\"figcap\">The nine read at a glance. "
                         "Every measure this session was scored on is at the "
                         "bottom of this page.</p>\r\n");

      WriteEquity(h);

      if(m_stats != NULL && st.trades > 0)
        {
         WriteWeekday(h);
         WriteHours(h);
        }

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
            "<h2>By setup</h2>\r\n<div class=\"scroll\">"
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
         FileWriteString(h, "</table></div>\r\n");
        }

      //+------------------------------------------------------------------+
      //| THE CHART COLUMN APPEARS ONLY IF THERE ARE PICTURES.             |
      //|                                                                  |
      //| Asked once, before the header is written, rather than per row -   |
      //| a header promising a column that every row leaves blank is a      |
      //| worse document than one that never mentions it.                   |
      //+------------------------------------------------------------------+
      bool shots = HasAnyShot();

      FileWriteString(h, "<h2>Trades</h2>\r\n<div class=\"scroll\">\r\n");
      FileWriteString(h,
         "<table><tr><th>#</th><th>Type</th><th>Tag</th><th class=\"n\">Volume</th>"
         "<th>Opened</th><th class=\"n\">Price</th><th>Closed</th><th class=\"n\">Price</th>"
         "<th>Reason</th><th class=\"n\">R</th><th class=\"n\">Profit</th>");
      if(shots)
         FileWriteString(h, "<th>Chart</th>");
      FileWriteString(h, "</tr>\r\n");

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
            "<td class=\"n\"><span class=\"%s\">%.2f</span></td>",
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

         if(shots)
            WriteShotCell(h, p.ticket);
         FileWriteString(h, "</tr>\r\n");
        }

      FileWriteString(h, "</table></div>\r\n");

      WriteAllMeasures(h, st);

      FileWriteString(h, "</div>\r\n");
      SSRWriteThemeToggle(h);
      FileWriteString(h, "</body></html>\r\n");
      FileClose(h);
      return true;
     }

   //--- is there a single picture to show? Walked once, and it stops at
   //--- the first hit rather than counting them all
   bool              HasAnyShot(void)
     {
      if(m_shots == NULL || m_acct == NULL)
         return false;
      int total = m_acct.Total();
      for(int i = 0; i < total; i++)
        {
         SSRVirtualPosition p;
         if(!m_acct.At(i, p) || !p.IsClosed())
            continue;
         if(m_shots.RelPath(p.ticket, true) != "" ||
            m_shots.RelPath(p.ticket, false) != "")
            return true;
        }
      return false;
     }

   //+------------------------------------------------------------------+
   //| ONE CELL, TWO THUMBNAILS - entry and exit, each a link to the    |
   //| full-size PNG beside this file.                                  |
   //|                                                                  |
   //| A missing shot renders as nothing at all. It must never render   |
   //| as a broken-image icon: this is a document a student hands in.   |
   //+------------------------------------------------------------------+
   void              WriteShotCell(const int h, const long ticket)
     {
      string in  = (m_shots != NULL ? m_shots.RelPath(ticket, true)  : "");
      string out = (m_shots != NULL ? m_shots.RelPath(ticket, false) : "");
      if(in == "" && out == "")
        {
         FileWriteString(h, "<td class=\"dim\">-</td>");
         return;
        }
      FileWriteString(h, "<td class=\"shot\"><div>");
      if(in != "")
         FileWriteString(h, "<a href=\"" + in + "\" target=\"_blank\">"
                            "<img src=\"" + in + "\" alt=\"chart at entry\" "
                            "title=\"at entry - click for full size\"></a>");
      if(out != "")
         FileWriteString(h, "<a href=\"" + out + "\" target=\"_blank\">"
                            "<img src=\"" + out + "\" alt=\"chart at exit\" "
                            "title=\"at exit - click for full size\"></a>");
      FileWriteString(h, "</div></td>");
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

   //+------------------------------------------------------------------+
   //| THE DOCUMENT'S SKIN.                                             |
   //|                                                                  |
   //| Every colour is a variable, declared three times: once on bare   |
   //| :root for light, once behind prefers-color-scheme for a viewer   |
   //| whose system is dark and who has chosen nothing, and once behind |
   //| [data-theme] for the button in the corner. A colour whose only   |
   //| definition sits inside a media query is a colour that does not   |
   //| exist for the third of readers who are in neither state.         |
   //|                                                                  |
   //| The dark set is SELECTED, not inverted. The two that carry       |
   //| meaning were measured against their own surface rather than      |
   //| chosen by eye - see the note on the palette in WriteEquity.      |

   //--- the button. A statement gets screenshotted and pasted into a
   //--- chat as often as it gets printed, and half those chats are dark.

   //--- a signed money figure, with the sign always shown. A statement
   //--- read at a glance must never make the reader hunt for a minus.
   string            Signed(const double v)
     { return StringFormat("%s%.2f", (v >= 0.0 ? "+" : ""), v); }

   string            Cls(const double v) { return (v >= 0.0 ? "g" : "r"); }

   //+------------------------------------------------------------------+
   //| THE EQUITY CURVE.                                                |
   //|                                                                  |
   //| No library. An <svg> with a polyline is the whole of it, and the |
   //| statistics engine has been sampling equity once a replay minute  |
   //| since Phase 10 - floating losses included - purely to compute a  |
   //| drawdown number. The shape was always there and never shown.     |
   //|                                                                  |
   //| ONE SERIES, so no legend: the heading names it. The two labels   |
   //| on the plot are the two points a trader actually looks for - the |
   //| deepest trough and where it ended - rather than a number on      |
   //| every sample, which is noise nobody reads.                       |
   //|                                                                  |
   //| Colour: the line is #1f6fb2 on light and #4e9fe6 on dark, chosen |
   //| against those surfaces rather than by eye - both clear 3:1 and   |
   //| the chroma floor. It is deliberately NOT the green/red pair:     |
   //| those mean profit and loss in this document, and an account      |
   //| curve is neither.                                                |
   //|                                                                  |
   //| Up to 1400 points survive, decimated by taking each window's     |
   //| MINIMUM AND MAXIMUM in the order they occurred. Plain stride     |
   //| sampling would step over the trough - and the trough is the      |
   //| entire reason to draw the curve rather than print its number.    |
   //+------------------------------------------------------------------+
   void              WriteEquity(const int h)
     {
      if(m_stats == NULL)
         return;
      int n = m_stats.EquitySamples();
      if(n < 3)
        {
         FileWriteString(h,
            "<h2>Equity curve</h2>\r\n<div class=\"fig\"><p class=\"figcap\">"
            "Not enough of the session was replayed to draw a curve - "
            "equity is sampled once a replay minute, and this run has "
            + IntegerToString(n) + ".</p></div>\r\n");
         return;
        }

      //--- pass one: the range, and where the deepest drawdown sat
      long   t0 = 0, t1 = 0, ms = 0;
      double v = 0.0, lo = 0.0, hi = 0.0;
      double peak = 0.0, worst = 0.0, worst_peak = 0.0;
      int    worst_i = -1;

      for(int i = 0; i < n; i++)
        {
         if(!m_stats.EquityAt(i, ms, v))
            continue;
         if(i == 0) { t0 = ms; lo = v; hi = v; peak = v; }
         t1 = ms;
         if(v < lo) lo = v;
         if(v > hi) hi = v;
         if(v > peak) peak = v;
         double dd = peak - v;
         if(dd > worst) { worst = dd; worst_i = i; worst_peak = peak; }
        }

      //--- the line the account started on belongs in the picture, or a
      //--- curve that never came back to it looks like it did
      double start = (m_acct != NULL ? m_acct.InitialBalance() : lo);
      if(start < lo) lo = start;
      if(start > hi) hi = start;

      double span = hi - lo;
      if(span <= 0.0)
         span = (hi != 0.0 ? MathAbs(hi) * 0.02 : 1.0);
      lo -= span * 0.08;
      hi += span * 0.08;
      span = hi - lo;

      double tspan = (double)(t1 - t0);
      if(tspan <= 0.0)
         tspan = 1.0;

      //--- geometry, in SVG user units. The viewBox scales; the numbers
      //--- below never have to know the reader's screen.
      double W = 980.0, H = 272.0;
      //--- the right margin is 88 wide and holds nothing but the closing
      //--- figure. Two renders were needed to accept that no placement
      //--- INSIDE the plot is safe: above the endpoint is where a rising
      //--- session's line is, below is where a falling one's is, and the
      //--- label lands on its own curve either way. Outside, it cannot.
      double padL = 70.0, padR = 88.0, padT = 16.0, padB = 34.0;
      double pw = W - padL - padR, ph = H - padT - padB;

      FileWriteString(h, "<h2>Equity curve</h2>\r\n"
                         "<div class=\"fig\" id=\"eqfig\"><div class=\"tip\"></div>\r\n");
      FileWriteString(h, StringFormat(
         "<svg viewBox=\"0 0 %.0f %.0f\" role=\"img\" "
         "aria-label=\"Account equity over the replayed session\">\r\n", W, H));

      //--- grid and the value axis. Solid hairlines, one shade off the
      //--- surface; a dashed grid reads as a threshold that is not there.
      for(int g = 0; g <= 3; g++)
        {
         double gv = lo + span * (double)g / 3.0;
         double gy = padT + ph * (1.0 - (double)g / 3.0);
         FileWriteString(h, StringFormat(
            "<line x1=\"%.1f\" y1=\"%.1f\" x2=\"%.1f\" y2=\"%.1f\" "
            "stroke=\"var(--grid)\" stroke-width=\"1\"/>"
            "<text x=\"%.1f\" y=\"%.1f\" text-anchor=\"end\" font-size=\"11\" "
            "fill=\"var(--muted)\" font-family=\"Tahoma,sans-serif\">%s</text>\r\n",
            padL, gy, W - padR, gy, padL - 8.0, gy + 4.0,
            DoubleToString(gv, 2)));
        }

      //--- the starting balance, named, so "above water" is a place on
      //--- the picture and not an arithmetic the reader has to do
      double sy = padT + ph * (1.0 - (start - lo) / span);
      FileWriteString(h, StringFormat(
         "<line x1=\"%.1f\" y1=\"%.1f\" x2=\"%.1f\" y2=\"%.1f\" "
         "stroke=\"var(--muted)\" stroke-width=\"1\" opacity=\".55\"/>"
         "<text x=\"%.1f\" y=\"%.1f\" text-anchor=\"end\" font-size=\"10\" "
         "fill=\"var(--muted)\" stroke=\"var(--panel)\" stroke-width=\"3\" "
         "paint-order=\"stroke\" font-family=\"Tahoma,sans-serif\">start</text>\r\n",
         padL, sy, W - padR, sy, W - padR - 3.0, sy - 5.0));

      //--- pass two: decimate, keeping both extremes of every window
      int budget = 1400;
      int win = 1;
      if(n > budget)
         win = (n + budget / 2 - 1) / (budget / 2);

      double xs[], ys[];
      string labels[];
      int    kept = 0;
      ArrayResize(xs, budget + 8);
      ArrayResize(ys, budget + 8);
      ArrayResize(labels, budget + 8);

      for(int a = 0; a < n; a += win)
        {
         int b = a + win;
         if(b > n)
            b = n;
         int imin = -1, imax = -1;
         double vmin = 0.0, vmax = 0.0;
         for(int i = a; i < b; i++)
           {
            if(!m_stats.EquityAt(i, ms, v))
               continue;
            if(imin < 0 || v < vmin) { imin = i; vmin = v; }
            if(imax < 0 || v > vmax) { imax = i; vmax = v; }
           }
         if(imin < 0)
            continue;

         int first  = (imin < imax ? imin : imax);
         int second = (imin < imax ? imax : imin);
         for(int k = 0; k < 2; k++)
           {
            int at = (k == 0 ? first : second);
            if(k == 1 && second == first)
               break;
            if(kept >= ArraySize(xs))
               break;
            if(!m_stats.EquityAt(at, ms, v))
               continue;
            xs[kept] = padL + pw * (double)(ms - t0) / tspan;
            ys[kept] = padT + ph * (1.0 - (v - lo) / span);
            labels[kept] = SSRFormatMsc(ms) + " &middot; <b>"
                           + DoubleToString(v, 2) + "</b>";
            kept++;
           }
        }
      if(kept < 2)
        {
         FileWriteString(h, "</svg></div>\r\n");
         return;
        }

      //--- the area first, so the line sits on top of its own fill.
      //--- The opening tag is written BEFORE the loop: an earlier version
      //--- emitted it from inside, on the first iteration, and the first
      //--- iteration is not where the first flush happens - so on any
      //--- curve long enough to flush, the path had no opening tag and
      //--- the whole figure silently vanished.
      FileWriteString(h, StringFormat("<path d=\"M%.1f,%.1f", xs[0], padT + ph));
      string d = "";
      for(int i = 0; i < kept; i++)
        {
         d += StringFormat("L%.1f,%.1f", xs[i], ys[i]);
         if(StringLen(d) > 3000)
           { FileWriteString(h, d); d = ""; }
        }
      FileWriteString(h, d);
      FileWriteString(h, StringFormat("L%.1f,%.1fZ\" fill=\"var(--equityfill)\" "
                                      "stroke=\"none\"/>\r\n",
                                      xs[kept - 1], padT + ph));

      FileWriteString(h, "<polyline fill=\"none\" stroke=\"var(--equity)\" "
                         "stroke-width=\"2\" stroke-linejoin=\"round\" "
                         "stroke-linecap=\"round\" points=\"");
      string pts = "";
      for(int i = 0; i < kept; i++)
        {
         pts += StringFormat("%.1f,%.1f ", xs[i], ys[i]);
         if(StringLen(pts) > 3000)
           { FileWriteString(h, pts); pts = ""; }
        }
      FileWriteString(h, pts + "\"/>\r\n");

      //+------------------------------------------------------------------+
      //| THE TWO POINTS WORTH NAMING - each on its own halo.               |
      //|                                                                  |
      //| The drawdown label has to sit where the drawdown is, and that is |
      //| by definition somewhere the line goes. paint-order:stroke draws  |
      //| a 3px surface-coloured outline UNDER the glyphs, so the text     |
      //| carries its own clearance wherever it lands - which a rectangle  |
      //| behind it could not, since nothing here can measure the text.    |
      //+------------------------------------------------------------------+
      if(worst_i >= 0 && worst > 0.0)
        {
         m_stats.EquityAt(worst_i, ms, v);
         double wx = padL + pw * (double)(ms - t0) / tspan;
         double wy = padT + ph * (1.0 - (v - lo) / span);
         double wpct = (worst_peak > 0.0 ? worst / worst_peak * 100.0 : 0.0);
         bool   right = (wx < W - 260.0);
         FileWriteString(h, StringFormat(
            "<circle cx=\"%.1f\" cy=\"%.1f\" r=\"4\" fill=\"var(--loss)\" "
            "stroke=\"var(--panel)\" stroke-width=\"2\"/>"
            "<text x=\"%.1f\" y=\"%.1f\" text-anchor=\"%s\" font-size=\"11\" "
            "fill=\"var(--loss)\" stroke=\"var(--panel)\" stroke-width=\"3\" "
            "paint-order=\"stroke\" font-family=\"Tahoma,sans-serif\">"
            "deepest drawdown %s (%s)</text>\r\n",
            wx, wy, (right ? wx + 9.0 : wx - 9.0), wy + 16.0,
            (right ? "start" : "end"),
            DoubleToString(-worst, 2),
            DoubleToString(wpct, 1) + "&#37;"));
        }

      //+------------------------------------------------------------------+
      //| WHERE IT ENDED - placed AWAY from where the line is.             |
      //|                                                                  |
      //| This label was drawn 9px above and left of the last point, which |
      //| is exactly where the line that produced that point is. A render  |
      //| of a rising session showed the figure lying across its own curve.|
      //| Above when the curve ends low, below when it ends high: the side |
      //| with no data on it.                                              |
      //+------------------------------------------------------------------+
      double fx = xs[kept - 1], fy = ys[kept - 1];
      m_stats.EquityAt(n - 1, ms, v);
      FileWriteString(h, StringFormat(
         "<circle cx=\"%.1f\" cy=\"%.1f\" r=\"4\" fill=\"var(--equity)\" "
         "stroke=\"var(--panel)\" stroke-width=\"2\"/>"
         "<text x=\"%.1f\" y=\"%.1f\" font-size=\"12\" "
         "font-weight=\"700\" fill=\"var(--equity)\" "
         "font-family=\"Tahoma,sans-serif\">%s</text>\r\n",
         fx, fy, fx + 9.0, fy + 4.0, DoubleToString(v, 2)));

      //--- the crosshair, parked until a pointer arrives
      FileWriteString(h, StringFormat(
         "<line id=\"eqcl\" y1=\"%.1f\" y2=\"%.1f\" x1=\"0\" x2=\"0\" "
         "stroke=\"var(--muted)\" stroke-width=\"1\" opacity=\"0\"/>"
         "<circle id=\"eqcd\" r=\"4\" cx=\"0\" cy=\"0\" fill=\"var(--equity)\" "
         "stroke=\"var(--panel)\" stroke-width=\"2\" opacity=\"0\"/>\r\n",
         padT, padT + ph));

      //--- the time axis: two labels, at the ends. A tick under every
      //--- point would be unreadable and the crosshair carries the rest.
      FileWriteString(h, StringFormat(
         "<text x=\"%.1f\" y=\"%.1f\" font-size=\"11\" fill=\"var(--muted)\" "
         "font-family=\"Tahoma,sans-serif\">%s</text>"
         "<text x=\"%.1f\" y=\"%.1f\" text-anchor=\"end\" font-size=\"11\" "
         "fill=\"var(--muted)\" font-family=\"Tahoma,sans-serif\">%s</text>\r\n",
         padL, H - 10.0, SSRFormatMsc(t0),
         W - 4.0, H - 10.0, SSRFormatMsc(t1)));

      FileWriteString(h, "</svg>\r\n");

      FileWriteString(h, "<p class=\"figcap\">Sampled once a replay minute, "
                         "floating profit and loss included - this is what the "
                         "account was worth while the trades were open, not "
                         "only after they closed. Every value is in the trade "
                         "table below.</p>\r\n</div>\r\n");

      //--- the hover data, in the same user units the plot was drawn in,
      //--- so nothing on the page has to redo the arithmetic
      FileWriteString(h, "<script>var SSRE=[");
      string js = "";
      for(int i = 0; i < kept; i++)
        {
         js += StringFormat("[%.1f,%.1f,\"%s\"]%s", xs[i], ys[i],
                            labels[i], (i + 1 < kept ? "," : ""));
         if(StringLen(js) > 3000)
           { FileWriteString(h, js); js = ""; }
        }
      FileWriteString(h, js + "];\r\n");

      FileWriteString(h,
         "(function(){var f=document.getElementById('eqfig');\r\n"
         "if(!f||!SSRE.length)return;\r\n"
         "var s=f.querySelector('svg'),tp=f.querySelector('.tip'),\r\n"
         " cl=f.querySelector('#eqcl'),cd=f.querySelector('#eqcd');\r\n"
         "function mv(e){var r=s.getBoundingClientRect();\r\n"
         " if(!r.width)return;\r\n"
         " var x=(e.clientX-r.left)/r.width*980,bi=0,bd=1e9;\r\n"
         " for(var i=0;i<SSRE.length;i++){var dd=Math.abs(SSRE[i][0]-x);\r\n"
         "  if(dd<bd){bd=dd;bi=i;}}\r\n"
         " var p=SSRE[bi];\r\n"
         " cl.setAttribute('x1',p[0]);cl.setAttribute('x2',p[0]);\r\n"
         " cl.setAttribute('opacity','.5');\r\n"
         " cd.setAttribute('cx',p[0]);cd.setAttribute('cy',p[1]);\r\n"
         " cd.setAttribute('opacity','1');\r\n"
         " tp.innerHTML=p[2];tp.style.opacity=1;\r\n"
         " var px=p[0]/980*r.width,w=tp.offsetWidth;\r\n"
         " tp.style.left=Math.max(4,Math.min(r.width-w-4,px-w/2))+'px';}\r\n"
         "function out(){cl.setAttribute('opacity','0');\r\n"
         " cd.setAttribute('opacity','0');tp.style.opacity=0;}\r\n"
         "s.addEventListener('pointermove',mv);\r\n"
         "s.addEventListener('pointerleave',out);})();\r\n"
         "</script>\r\n");
     }

   //--- the largest absolute net across a set of buckets, which is what
   //--- every bar in that set is measured against. Zero when nothing
   //--- traded, and the caller must not divide by it.
   double            PeakAbs(SSRBucket &b[])
     {
      double m = 0.0;
      for(int i = 0; i < ArraySize(b); i++)
         if(MathAbs(b[i].net) > m)
            m = MathAbs(b[i].net);
      return m;
     }

   string            DayName(const int i)
     {
      string d[] = {"Sunday","Monday","Tuesday","Wednesday",
                    "Thursday","Friday","Saturday"};
      return (i >= 0 && i < 7 ? d[i] : "?");
     }

   //+------------------------------------------------------------------+
   //| WHEN THE TRADES WERE TAKEN.                                      |
   //|                                                                  |
   //| A win rate over a whole session is one number and nothing can be |
   //| done with it. The same trades split by weekday and by hour are   |
   //| a decision: stop trading the first hour, or stop trading Monday. |
   //|                                                                  |
   //| Both are DIVERGING bars centred on zero - profit to the right,   |
   //| loss to the left - and that is not decoration. Green and red     |
   //| sit close enough under deuteranopia that colour alone is not a   |
   //| safe encoding for them (measured: dE 11.4 light, 12.0 dark, both |
   //| against their own surface). Direction from the centre line and   |
   //| the signed number beside it carry the same fact twice more, so   |
   //| the chart reads without relying on the hue at all.                |
   //+------------------------------------------------------------------+
   void              WriteWeekday(const int h)
     {
      SSRBucket b[];
      m_stats.ByWeekday(b);
      double peak = PeakAbs(b);

      FileWriteString(h, "<h2>By weekday</h2>\r\n<div class=\"scroll\"><table>"
                         "<tr><th>Day</th><th class=\"n\">Trades</th>"
                         "<th class=\"n\">Win rate</th><th class=\"n\">Avg R</th>"
                         "<th class=\"n\">Net</th><th>Profit and loss</th></tr>\r\n");

      for(int i = 0; i < ArraySize(b); i++)
        {
         if(b[i].trades == 0)
           {
            FileWriteString(h, "<tr><td class=\"dim\">" + DayName(i) +
                               "</td><td class=\"n dim\">-</td>"
                               "<td class=\"n dim\">-</td><td class=\"n dim\">-</td>"
                               "<td class=\"n dim\">-</td>"
                               "<td class=\"bar\"><div class=\"bz\"></div></td></tr>\r\n");
            continue;
           }
         //--- 46, not 50: at 50 the largest bar touches the edge of its
         //--- cell and reads as a value that ran out of room rather than
         //--- as the biggest one
         double w = (peak > 0.0 ? MathAbs(b[i].net) / peak * 46.0 : 0.0);
         FileWriteString(h, StringFormat(
            "<tr><td>%s</td><td class=\"n\">%d</td><td class=\"n\">%s</td>"
            "<td class=\"n\">%s</td>"
            "<td class=\"n\"><span class=\"%s\">%s</span></td>"
            "<td class=\"bar\"><div class=\"bz\"></div>"
            "<div class=\"bf %s\" style=\"%s:50&#37;;width:%s&#37;\"></div></td></tr>\r\n",
            DayName(i), b[i].trades,
            DoubleToString(b[i].WinRate(), 1) + "&#37;",
            (b[i].r_trades > 0 ? DoubleToString(b[i].AverageR(), 2) : "-"),
            Cls(b[i].net), Signed(b[i].net),
            Cls(b[i].net), (b[i].net >= 0.0 ? "left" : "right"),
            DoubleToString(w, 2)));
        }
      FileWriteString(h, "</table></div>\r\n");
     }

   //+------------------------------------------------------------------+
   //| The same question asked of the clock.                            |
   //|                                                                  |
   //| Twenty-four columns rather than twenty-four rows: the shape of a |
   //| trading day - dead hours, the session open, the hour it all goes |
   //| wrong - is a shape, and a table of it is not. Every hour is      |
   //| drawn, including the empty ones, because a gap in the day is     |
   //| information; the table underneath carries the exact numbers, so  |
   //| nothing here is reachable only by hovering.                      |
   //+------------------------------------------------------------------+
   void              WriteHours(const int h)
     {
      SSRBucket b[];
      m_stats.ByHour(b);
      double peak = PeakAbs(b);

      FileWriteString(h, "<h2>By hour of the day</h2>\r\n"
                         "<div class=\"fig\"><div class=\"hrs\">"
                         "<div class=\"hmid\"></div>\r\n");

      for(int i = 0; i < ArraySize(b); i++)
        {
         string hh = (i < 10 ? "0" : "") + IntegerToString(i);
         if(b[i].trades == 0)
           {
            FileWriteString(h, "<div class=\"hr\" title=\"" + hh +
                               ":00 - no trades\"></div>");
            continue;
           }
         double ht = (peak > 0.0 ? MathAbs(b[i].net) / peak * 46.0 : 0.0);
         FileWriteString(h, StringFormat(
            "<div class=\"hr\" title=\"%s:00 - %d trade%s, %s win, net %s\">"
            "<div class=\"hb %s\" style=\"height:%s&#37;\"></div></div>",
            hh, b[i].trades, (b[i].trades == 1 ? "" : "s"),
            DoubleToString(b[i].WinRate(), 0) + "&#37;",
            Signed(b[i].net), Cls(b[i].net), DoubleToString(ht, 2)));
        }

      FileWriteString(h, "\r\n</div><div class=\"hax\">");
      for(int i = 0; i < 24; i++)
         FileWriteString(h, "<div>" +
                            (i % 3 == 0 ? (i < 10 ? "0" : "") + IntegerToString(i)
                                        : "") + "</div>");
      FileWriteString(h, "</div>\r\n<p class=\"figcap\">Server time, bucketed by "
                         "the moment of ENTRY - the exit is the market's decision "
                         "as often as the trader's.</p>\r\n");

      FileWriteString(h, "<details><summary>Table view</summary><div class=\"scroll\">"
                         "<table><tr><th>Hour</th><th class=\"n\">Trades</th>"
                         "<th class=\"n\">Win rate</th><th class=\"n\">Avg R</th>"
                         "<th class=\"n\">Net</th></tr>\r\n");
      int shown = 0;
      for(int i = 0; i < ArraySize(b); i++)
        {
         if(b[i].trades == 0)
            continue;
         shown++;
         string hh = (i < 10 ? "0" : "") + IntegerToString(i);
         FileWriteString(h, StringFormat(
            "<tr><td>%s:00</td><td class=\"n\">%d</td><td class=\"n\">%s</td>"
            "<td class=\"n\">%s</td>"
            "<td class=\"n\"><span class=\"%s\">%s</span></td></tr>\r\n",
            hh, b[i].trades, DoubleToString(b[i].WinRate(), 1) + "&#37;",
            (b[i].r_trades > 0 ? DoubleToString(b[i].AverageR(), 2) : "-"),
            Cls(b[i].net), Signed(b[i].net)));
        }
      if(shown == 0)
         FileWriteString(h, "<tr><td colspan=\"5\" class=\"dim\">"
                            "no closed trades</td></tr>\r\n");
      FileWriteString(h, "</table></div></details></div>\r\n");
     }

   //--- one row of the full-measures table
   void              Measure(const int h, const string name, const string value,
                             const string means, const string cls = "")
     {
      FileWriteString(h, "<tr><td>" + name + "</td><td class=\"n\">" +
                         (cls == "" ? value
                                    : "<span class=\"" + cls + "\">" + value + "</span>") +
                         "</td><td class=\"dim\">" + means + "</td></tr>\r\n");
     }

   void              MeasureHead(const int h, const string title)
     {
      FileWriteString(h, "<tr class=\"head\"><td colspan=\"3\">" + title +
                         "</td></tr>\r\n");
     }

   //+------------------------------------------------------------------+
   //| EVERY NUMBER THE ENGINE COMPUTES.                                |
   //|                                                                  |
   //| The header grid shows nine of them because nine is what a person |
   //| reads at a glance. The other twenty-two were computed on every   |
   //| export and thrown away - among them the commission, the average  |
   //| win against the average loss, and the count of trades taken with |
   //| no stop at all, which is the single most useful line here for a  |
   //| student.                                                         |
   //|                                                                  |
   //| Each row says what the number MEANS. A statement is read months  |
   //| later by someone who did not take the trades.                    |
   //+------------------------------------------------------------------+
   void              WriteAllMeasures(const int h, SSRStatistics &st)
     {
      FileWriteString(h, "<h2>Every measure</h2>\r\n<div class=\"scroll\"><table>"
                         "<tr><th>Measure</th><th class=\"n\">Value</th>"
                         "<th>What it means</th></tr>\r\n");

      MeasureHead(h, "Counts");
      Measure(h, "Closed trades", IntegerToString(st.trades),
              "positions that were opened and closed during the replay");
      Measure(h, "Wins",  IntegerToString(st.wins),
              "closed for more than zero after commission and swap");
      Measure(h, "Losses", IntegerToString(st.losses), "closed for less than zero");
      Measure(h, "Break-even", IntegerToString(st.breakeven),
              "closed at exactly zero - rarer than it looks, and worth checking");
      Measure(h, "Still open", IntegerToString(st.open_now),
              "not counted in anything above: an open trade has no result yet");

      MeasureHead(h, "Money");
      Measure(h, "Gross profit", DoubleToString(st.gross_profit, 2),
              "the winners added up", "g");
      Measure(h, "Gross loss", DoubleToString(st.gross_loss, 2),
              "the losers added up, as a positive number", "r");
      Measure(h, "Commission", DoubleToString(st.commission, 2),
              "already taken off every trade's result, not a separate deduction");
      Measure(h, "Swap", DoubleToString(st.swap, 2),
              "financing on positions held across a rollover");
      Measure(h, "Net profit", Signed(st.net_profit),
              "gross profit less gross loss - the sum of the trade table below",
              Cls(st.net_profit));
      Measure(h, "Average win", DoubleToString(st.average_win, 2),
              "what a winner is worth on average", "g");
      Measure(h, "Average loss", DoubleToString(st.average_loss, 2),
              "what a loser costs on average - compare it with the line above", "r");
      Measure(h, "Largest win", DoubleToString(st.largest_win, 2),
              "one trade. If it is most of the net profit, the rest did not work", "g");
      Measure(h, "Largest loss", DoubleToString(st.largest_loss, 2),
              "one trade. Compare it with the average loss: a gap means a stop was moved", "r");

      MeasureHead(h, "Ratios");
      Measure(h, "Win rate", DoubleToString(st.win_rate, 1) + "&#37;",
              "share of closed trades that made money");
      Measure(h, "Loss rate", DoubleToString(st.loss_rate, 1) + "&#37;",
              "share that lost money; the remainder closed flat");
      Measure(h, "Profit factor",
              (st.profit_factor > 0.0 ? DoubleToString(st.profit_factor, 2)
                                      : "undefined"),
              "gross profit divided by gross loss. Undefined with no losing trade "
              "- reported as such rather than as infinity");
      Measure(h, "Expectancy", Signed(st.expectancy),
              "what one more trade is worth on average, in money",
              Cls(st.expectancy));

      MeasureHead(h, "Risk, in R");
      Measure(h, "Trades with a stop",
              IntegerToString(st.r_trades) + " of " + IntegerToString(st.trades),
              "R exists only where a stop was set; the rest cannot be measured in R");
      Measure(h, "Trades without a stop", IntegerToString(st.trades_without_stop),
              "every one of these is a trade with no defined risk");
      Measure(h, "Total R", Signed(st.total_r),
              "the R multiples added up, over the trades that have one",
              Cls(st.total_r));
      Measure(h, "Average R", Signed(st.average_r),
              "the number that survives a change of account size", Cls(st.average_r));
      Measure(h, "Expectancy in R", Signed(st.expectancy_r),
              "what one more trade is worth in units of the risk taken",
              Cls(st.expectancy_r));

      MeasureHead(h, "Risk, in money");
      Measure(h, "Max drawdown", DoubleToString(st.max_drawdown, 2),
              "peak to trough on the equity curve, floating losses included - "
              "what was actually sat through", "r");
      Measure(h, "Max drawdown &#37;", DoubleToString(st.max_drawdown_pct, 1) + "&#37;",
              "the same fall, against the peak it fell from", "r");
      Measure(h, "Max drawdown, closed only",
              DoubleToString(st.max_drawdown_closed, 2),
              "the same measure on the balance curve. Much smaller than the line "
              "above means losses were held rather than taken");
      Measure(h, "Longest winning streak", IntegerToString(st.win_streak),
              "consecutive winners");
      Measure(h, "Longest losing streak", IntegerToString(st.loss_streak),
              "consecutive losers - the number that decides whether a system is "
              "survivable, not the win rate");
      Measure(h, "Stop-outs", IntegerToString(st.stopouts),
              "times the account ran out of margin", (st.stopouts > 0 ? "r" : ""));

      MeasureHead(h, "How far trades ran against you");
      Measure(h, "Average MAE", DoubleToString(st.avg_mae, 2),
              "maximum adverse excursion: how far the average trade went the wrong "
              "way before it ended");
      Measure(h, "Average MFE", DoubleToString(st.avg_mfe, 2),
              "maximum favourable excursion: how far it went the right way. Much "
              "larger than the average win means profit was given back");

      MeasureHead(h, "Can these numbers be trusted");
      Measure(h, "Assumed tick order",
              IntegerToString(st.ambiguous_trades) + " (" +
              DoubleToString(st.ambiguous_pct, 1) + "&#37;)",
              "trades where stop and target sat inside one bar and which came "
              "first had to be assumed", (st.ambiguous_trades > 0 ? "amb" : ""));
      Measure(h, "Margin modelled", (st.margin_modelled ? "yes" : "no"),
              "with margin off, a position size that a real account would have "
              "refused was allowed here");
      FileWriteString(h, "</table></div>\r\n");
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
