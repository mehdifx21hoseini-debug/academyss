//+------------------------------------------------------------------+
//|                                              SSR_ClassReport.mqh |
//|                 SS Replay - Twenty Students, One Session (L4)    |
//|                                                                  |
//|  The seed has been repeatable since Phase 11: hand twenty people  |
//|  the same one and they get the same candles, bar for bar. Until   |
//|  now that produced twenty separate reports and nothing that put   |
//|  them beside each other.                                         |
//|                                                                  |
//|  This reads the CSVs they send back and builds one page. It is    |
//|  the difference between a tool one person buys and a tool an      |
//|  academy buys.                                                    |
//|                                                                  |
//|  THE FILE NAME IS THE STUDENT'S NAME. No metadata, no form to     |
//|  fill in: the coach drops the files into a folder named after     |
//|  each person and runs the script. Anything more elaborate is a    |
//|  step somebody skips.                                            |
//|                                                                  |
//|  IT REFUSES TO RANK PEOPLE WHO RAN DIFFERENT SESSIONS.            |
//|  That is the whole reason the journal now writes a session key.   |
//|  A league table across two different windows is not a comparison, |
//|  it is a mistake with a heading on it - and the coach would draw  |
//|  a conclusion about a student from it.                            |
//+------------------------------------------------------------------+
#ifndef SSR_CLASS_REPORT_MQH
#define SSR_CLASS_REPORT_MQH

#include "../Common/SSR_Types.mqh"
#include "../Common/SSR_Time.mqh"
#include "SSR_ReportStyle.mqh"

//--- where the coach drops the files, and where the page lands
#define SSR_CLASS_DIR   "SSReplay\\class"
#define SSR_CLASS_OUT   "SSReplay\\class-report.html"
#define SSR_CLASS_MAX   64      // students in one report
#define SSR_CLASS_TRADES 400    // trades kept per student, for the strip

//+------------------------------------------------------------------+
//| One student's session, as read back out of their CSV.            |
//+------------------------------------------------------------------+
struct SSRStudent
  {
   string            name;          // the file name, minus .csv
   bool              parsed;
   string            problem;       // why not, when not

   string            session;
   string            symbol;
   string            key;           // what two identical runs share
   long              win_start;
   long              win_end;

   int               trades;
   double            win_rate;
   double            profit_factor;
   double            net_profit;
   double            expectancy;
   double            average_r;
   double            max_dd;
   double            max_dd_pct;
   int               loss_streak;
   double            ambiguous_pct;
   int               no_stop;       // trades whose R column was empty

   //--- when each trade was entered, and whether it made money. This is
   //--- the picture a coach actually wants: same candles, twenty rows,
   //--- and you can see at a glance who took the same setup.
   long              entry[];
   bool              won[];
   int               n_entries;

   void              Init(void)
     {
      name = ""; parsed = false; problem = "";
      session = ""; symbol = ""; key = ""; win_start = 0; win_end = 0;
      trades = 0; win_rate = 0.0; profit_factor = 0.0; net_profit = 0.0;
      expectancy = 0.0; average_r = 0.0; max_dd = 0.0; max_dd_pct = 0.0;
      loss_streak = 0; ambiguous_pct = 0.0; no_stop = 0;
      n_entries = 0;
      ArrayResize(entry, 0);
      ArrayResize(won, 0);
     }
  };

//+------------------------------------------------------------------+
class CSSRClassReport
  {
private:
   SSRStudent        m_s[];
   int               m_count;
   string            m_last_error;
   string            m_last_path;

   //--- the key the majority ran. Not the first file's: the coach who
   //--- accidentally drops in one file from last week should see that
   //--- one flagged, not the other nineteen.
   string            m_key;
   int               m_key_agree;

   string            Trim(const string in)
     {
      string t = in;
      StringTrimLeft(t);
      StringTrimRight(t);
      return t;
     }

   //--- a CSV line into fields. The journal replaces commas inside a
   //--- value with semicolons before writing, so a plain split is
   //--- correct here rather than merely convenient.
   int               Split(const string line, string &out[])
     { return StringSplit(line, ',', out); }

   string            Field(const string &f[], const int i)
     { return (i >= 0 && i < ArraySize(f) ? Trim(f[i]) : ""); }

   //--- "12 (3.4%)" -> 3.4 ; "5 of 9" -> 5 ; "17.5" -> 17.5
   double            LeadingNumber(const string in)
     {
      string t = Trim(in);
      if(t == "")
         return 0.0;
      return StringToDouble(t);
     }

   double            InParens(const string in)
     {
      int a = StringFind(in, "(");
      if(a < 0)
         return 0.0;
      return StringToDouble(StringSubstr(in, a + 1));
     }

   //--- MetaTrader writes and reads "2026.08.24 09:10:00"
   long              ParseTime(const string in)
     {
      datetime d = StringToTime(Trim(in));
      return (d > 0 ? (long)d * 1000 : 0);
     }

public:
                     CSSRClassReport(void)
     : m_count(0), m_last_error(""), m_last_path(""), m_key(""),
       m_key_agree(0) {}

   int               Count(void)      { return m_count; }
   string            LastError(void)  { return m_last_error; }
   string            LastPath(void)   { return m_last_path; }
   string            Key(void)        { return m_key; }
   int               Agreeing(void)   { return m_key_agree; }

   bool              At(const int i, SSRStudent &out)
     {
      if(i < 0 || i >= m_count)
        { out.Init(); return false; }
      out = m_s[i];
      return true;
     }

   //+------------------------------------------------------------------+
   //| READ ONE STUDENT'S FILE.                                         |
   //|                                                                  |
   //| Every failure is recorded ON the student rather than thrown       |
   //| away: a name missing from the report is a person the coach        |
   //| forgets to chase, while a row saying "this file has no header"    |
   //| is a person who gets asked to export it again.                    |
   //+------------------------------------------------------------------+
   bool              ReadOne(const string path, const string student_name,
                             SSRStudent &out)
     {
      out.Init();
      out.name = student_name;

      int h = FileOpen(path, FILE_READ | FILE_TXT | FILE_ANSI);
      if(h == INVALID_HANDLE)
        {
         out.problem = "cannot be opened";
         return false;
        }

      bool  header_seen = false;
      bool  in_rows     = false;
      int   c_open = -1, c_profit = -1, c_r = -1;

      while(!FileIsEnding(h))
        {
         string line = FileReadString(h);
         if(line == "")
            continue;

         if(StringGetCharacter(line, 0) == '#')
           {
            //+------------------------------------------------------------------+
            //| THE MARKER LINE HAS NO COMMA, and that rejected every file.      |
            //|                                                                  |
            //| `# SS Replay journal` is one field. The comma test below dropped |
            //| it before anything could notice it, so header_seen was never set |
            //| and four perfectly good exports came back as "no SS Replay        |
            //| header - is this a journal CSV?". The smoke test found it on its  |
            //| first run, which is the entire reason it round-trips a real file  |
            //| instead of parsing one I typed by hand.                           |
            //+------------------------------------------------------------------+
            if(StringFind(line, "# SS Replay journal") == 0)
              { header_seen = true; continue; }

            string f[];
            if(Split(line, f) < 2)
               continue;
            string k = Trim(StringSubstr(Field(f, 0), 1));
            string v = Field(f, 1);
            //--- a value that had commas in it was joined back with
            //--- semicolons by the writer, so the remainder is safe to
            //--- glue together for the few free-text keys
            for(int e = 2; e < ArraySize(f); e++)
               v += "," + Trim(f[e]);

            if(k == "session")        out.session       = v;
            else if(k == "symbol")    out.symbol        = v;
            else if(k == "session_key") out.key         = v;
            else if(k == "window_start") out.win_start  = (long)StringToInteger(v);
            else if(k == "window_end")   out.win_end    = (long)StringToInteger(v);
            else if(k == "trades")    out.trades        = (int)StringToInteger(v);
            else if(k == "win_rate")  out.win_rate      = LeadingNumber(v);
            else if(k == "profit_factor") out.profit_factor = LeadingNumber(v);
            else if(k == "net_profit")    out.net_profit    = LeadingNumber(v);
            else if(k == "expectancy")    out.expectancy    = LeadingNumber(v);
            else if(k == "average_r")     out.average_r     = LeadingNumber(v);
            else if(k == "max_drawdown")  out.max_dd        = LeadingNumber(v);
            else if(k == "max_drawdown_pct") out.max_dd_pct = LeadingNumber(v);
            else if(k == "loss_streak")   out.loss_streak   = (int)StringToInteger(v);
            else if(k == "ambiguous_trades") out.ambiguous_pct = InParens(v);
            continue;
           }

         //--- the column header, then the rows
         if(!in_rows)
           {
            string f[];
            int n = Split(line, f);
            for(int i = 0; i < n; i++)
              {
               string c = Field(f, i);
               if(c == "open_time") c_open   = i;
               if(c == "profit")    c_profit = i;
               if(c == "r")         c_r      = i;
              }
            if(c_open >= 0 && c_profit >= 0)
              { in_rows = true; continue; }
            continue;
           }

         string f[];
         if(Split(line, f) <= c_profit)
            continue;
         if(out.n_entries >= SSR_CLASS_TRADES)
            continue;

         long   t   = ParseTime(Field(f, c_open));
         double pnl = StringToDouble(Field(f, c_profit));
         if(t <= 0)
            continue;

         ArrayResize(out.entry, out.n_entries + 1);
         ArrayResize(out.won,   out.n_entries + 1);
         out.entry[out.n_entries] = t;
         out.won[out.n_entries]   = (pnl > 0.0);
         out.n_entries++;

         if(c_r >= 0 && Field(f, c_r) == "")
            out.no_stop++;
        }
      FileClose(h);

      if(!header_seen)
        {
         out.problem = "no SS Replay header - is this a journal CSV?";
         return false;
        }
      if(out.key == "")
         out.problem = "exported before v76, so it cannot be checked "
                       "against the others";
      out.parsed = true;
      return true;
     }

   //+------------------------------------------------------------------+
   //| Read every CSV in the folder. Sorted by net result, best first.  |
   //+------------------------------------------------------------------+
   int               Scan(const string dir = SSR_CLASS_DIR)
     {
      m_count = 0;
      m_key   = "";
      m_key_agree = 0;
      m_last_error = "";
      ArrayResize(m_s, SSR_CLASS_MAX);

      string   file  = "";
      long     find  = FileFindFirst(dir + "\\*.csv", file);
      if(find == INVALID_HANDLE)
        {
         m_last_error = StringFormat("no .csv files in MQL5\\Files\\%s - put "
                                     "each student's exported journal there, "
                                     "named after them", dir);
         return 0;
        }

      do
        {
         if(m_count >= SSR_CLASS_MAX)
            break;
         string nm = file;
         int dot = StringFind(nm, ".csv");
         if(dot > 0)
            nm = StringSubstr(nm, 0, dot);
         ReadOne(dir + "\\" + file, nm, m_s[m_count]);
         m_count++;
        }
      while(FileFindNext(find, file));
      FileFindClose(find);

      //--- WHICH SESSION THE CLASS ACTUALLY RAN: the most common key,
      //--- not the first one read. A coach who drops in one file from
      //--- last week should see that one flagged, not the other twenty.
      for(int i = 0; i < m_count; i++)
        {
         if(!m_s[i].parsed || m_s[i].key == "")
            continue;
         int agree = 0;
         for(int j = 0; j < m_count; j++)
            if(m_s[j].parsed && m_s[j].key == m_s[i].key)
               agree++;
         if(agree > m_key_agree)
           { m_key = m_s[i].key; m_key_agree = agree; }
        }

      //--- best first. An insertion sort is the honest size of a class.
      for(int i = 1; i < m_count; i++)
        {
         SSRStudent t = m_s[i];
         int j = i - 1;
         while(j >= 0 && Rank(m_s[j]) < Rank(t))
           { m_s[j + 1] = m_s[j]; j--; }
         m_s[j + 1] = t;
        }
      return m_count;
     }

   //--- an unreadable file sorts to the bottom rather than to the top,
   //--- where a zero would put it beside somebody who broke even
   double            Rank(SSRStudent &s)
     { return (s.parsed ? s.net_profit : -1.0e18); }

private:

   //--- HTML has five characters that must never arrive raw
   string            Html(const string in)
     {
      string o = in;
      StringReplace(o, "&", "&amp;");
      StringReplace(o, "<", "&lt;");
      StringReplace(o, ">", "&gt;");
      StringReplace(o, "\"", "&quot;");
      return o;
     }

   string            Signed(const double v)
     { return StringFormat("%s%.2f", (v >= 0.0 ? "+" : ""), v); }

   string            Cls(const double v) { return (v >= 0.0 ? "g" : "r"); }

   //--- the middle of the class, which is the number a student should be
   //--- compared against. An average is moved by one person who blew up.
   double            MedianNet(void)
     {
      double v[];
      int n = 0;
      ArrayResize(v, m_count);
      for(int i = 0; i < m_count; i++)
         if(m_s[i].parsed)
           { v[n] = m_s[i].net_profit; n++; }
      if(n == 0)
         return 0.0;
      //--- already sorted best-first by Scan, but Write must not depend
      //--- on that: a caller that read one file has never sorted
      for(int i = 1; i < n; i++)
        {
         double t = v[i];
         int j = i - 1;
         while(j >= 0 && v[j] > t)
           { v[j + 1] = v[j]; j--; }
         v[j + 1] = t;
        }
      if((n & 1) == 1)
         return v[n / 2];
      return (v[n / 2 - 1] + v[n / 2]) / 2.0;
     }

   //+------------------------------------------------------------------+
   //| THE TIME AXIS EVERY STRIP SHARES.                                |
   //|                                                                  |
   //| From the session window when the files carry one, because that is |
   //| the axis the students actually traded on - two people who both    |
   //| traded only the first hour should show two short clusters at the  |
   //| left, not two strips that each fill the width.                    |
   //+------------------------------------------------------------------+
   void              Axis(long &from, long &to)
     {
      from = 0; to = 0;
      for(int i = 0; i < m_count; i++)
         if(m_s[i].parsed && m_s[i].key == m_key &&
            m_s[i].win_start > 0 && m_s[i].win_end > m_s[i].win_start)
           { from = m_s[i].win_start; to = m_s[i].win_end; return; }

      for(int i = 0; i < m_count; i++)
         for(int e = 0; e < m_s[i].n_entries; e++)
           {
            long t = m_s[i].entry[e];
            if(from == 0 || t < from) from = t;
            if(to   == 0 || t > to)   to   = t;
           }
      if(to <= from)
         to = from + SSR_MSC_PER_MIN;
     }

public:
   //+------------------------------------------------------------------+
   //| THE PAGE.                                                        |
   //+------------------------------------------------------------------+
   bool              Write(const string out_path = SSR_CLASS_OUT)
     {
      m_last_error = "";
      if(m_count == 0)
        {
         m_last_error = "nothing to report on";
         return false;
        }

      FolderCreate("SSReplay");
      int h = FileOpen(out_path, FILE_WRITE | FILE_TXT | FILE_ANSI);
      if(h == INVALID_HANDLE)
        {
         m_last_error = "cannot write " + out_path;
         return false;
        }
      m_last_path = out_path;

      SSRWriteReportHead(h, "SS Replay class report");

      int readable = 0;
      for(int i = 0; i < m_count; i++)
         if(m_s[i].parsed)
            readable++;

      string sym = "", sess = "";
      for(int i = 0; i < m_count; i++)
         if(m_s[i].parsed && m_s[i].key == m_key)
           { sym = m_s[i].symbol; sess = m_s[i].session; break; }

      FileWriteString(h, "<div class=\"top\"><div>\r\n"
                         "<h1>SS Replay &mdash; class report</h1>\r\n");
      FileWriteString(h, StringFormat(
         "<p class=\"sub\">%d file(s) read &nbsp;&middot;&nbsp; %s</p>\r\n",
         m_count, TimeToString(TimeLocal(), TIME_DATE | TIME_MINUTES)));
      FileWriteString(h, "</div><button class=\"thm\" id=\"thm\">Dark</button>"
                         "</div>\r\n");

      //+------------------------------------------------------------------+
      //| THE WARNING COMES BEFORE THE LEAGUE TABLE, not after it.         |
      //|                                                                  |
      //| A table ranking people who did not run the same session is not a |
      //| comparison, it is a mistake with a heading on it - and a coach   |
      //| would draw a conclusion about a student from it before reaching  |
      //| any footnote.                                                     |
      //+------------------------------------------------------------------+
      if(readable > 0 && m_key_agree < readable)
         FileWriteString(h, StringFormat(
            "<div class=\"caveat\"><b>Read this first.</b><br>"
            "%d of the %d readable files ran the same session. The rest are "
            "marked below and are NOT comparable with the others - a "
            "different window is a different set of candles, not a worse "
            "trader.</div>\r\n", m_key_agree, readable));
      if(readable < m_count)
         FileWriteString(h, StringFormat(
            "<div class=\"caveat\"><b>%d file(s) could not be read.</b><br>"
            "They are listed at the bottom with the reason. A name missing "
            "from a report is a person who gets forgotten.</div>\r\n",
            m_count - readable));

      double median = MedianNet();
      double best = 0.0, worst = 0.0;
      int    total_trades = 0;
      bool   have = false;
      for(int i = 0; i < m_count; i++)
        {
         if(!m_s[i].parsed)
            continue;
         total_trades += m_s[i].trades;
         if(!have || m_s[i].net_profit > best)  best  = m_s[i].net_profit;
         if(!have || m_s[i].net_profit < worst) worst = m_s[i].net_profit;
         have = true;
        }

      FileWriteString(h, "<div class=\"kpi\">\r\n");
      FileWriteString(h, StringFormat("<div><span>Students</span><b>%d</b></div>\r\n",
                                      readable));
      FileWriteString(h, StringFormat("<div><span>Ran this session</span><b>%d</b></div>\r\n",
                                      m_key_agree));
      FileWriteString(h, StringFormat("<div><span>Trades between them</span><b>%d</b></div>\r\n",
                                      total_trades));
      FileWriteString(h, StringFormat("<div><span>Median result</span>"
                                      "<b class=\"%s\">%s</b></div>\r\n",
                                      Cls(median), Signed(median)));
      FileWriteString(h, StringFormat("<div><span>Best</span><b class=\"g\">%s</b></div>\r\n",
                                      Signed(best)));
      FileWriteString(h, StringFormat("<div><span>Worst</span><b class=\"r\">%s</b></div>\r\n",
                                      Signed(worst)));
      FileWriteString(h, "</div>\r\n");

      if(sym != "")
         FileWriteString(h, StringFormat(
            "<p class=\"figcap\">Session: %s%s</p>\r\n", Html(sym),
            (sess == "" ? "" : "  &middot;  " + Html(sess))));

      //+------------------------------------------------------------------+
      //| WHEN EACH OF THEM ENTERED.                                       |
      //|                                                                  |
      //| The reason to hand a class the same seed. One time axis, one row |
      //| per person, a mark per trade: who took the same setup, who sat   |
      //| out, and who was trading something nobody else could see are all |
      //| one glance rather than twenty documents.                          |
      //|                                                                  |
      //| Green and red carry the outcome, and POSITION carries the fact   |
      //| that matters - the two are not the same question, so the colour  |
      //| is not doing the work on its own.                                |
      //+------------------------------------------------------------------+
      long from = 0, to = 0;
      Axis(from, to);
      double span = (double)(to - from);
      if(span <= 0.0)
         span = 1.0;

      FileWriteString(h, "<h2>When each of them entered</h2>\r\n"
                         "<div class=\"fig\">\r\n");
      for(int i = 0; i < m_count; i++)
        {
         if(!m_s[i].parsed)
            continue;

         //+------------------------------------------------------------------+
         //| THE ODD ONE OUT IS NAMED IN THE STRIP, not only in the table.    |
         //|                                                                  |
         //| Their entries fall outside the shared window and are dropped, so |
         //| their row comes out EMPTY - which reads as "took no trades", the |
         //| one conclusion that is certainly wrong about them. A rendered     |
         //| draft showed exactly that: a blank row beside eleven busy ones,   |
         //| with the only explanation eight hundred pixels further down.      |
         //+------------------------------------------------------------------+
         bool odd_row = (m_key != "" && m_s[i].key != m_key);
         FileWriteString(h, "<div class=\"srow\"><div class=\"sname" +
                            (odd_row ? " amb" : "") + "\">" +
                            Html(m_s[i].name) +
                            (odd_row ? " - other session" : "") +
                            "</div><div class=\"strip" +
                            (odd_row ? " off" : "") + "\">");
         for(int e = 0; e < m_s[i].n_entries; e++)
           {
            double at = (double)(m_s[i].entry[e] - from) / span * 100.0;
            if(at < 0.0 || at > 100.0)
               continue;              // a trade outside the shared window
            FileWriteString(h, StringFormat(
               "<span class=\"smark %s\" style=\"left:%s&#37;\" title=\"%s\">"
               "</span>",
               (m_s[i].won[e] ? "g" : "r"), DoubleToString(at, 3),
               SSRFormatMsc(m_s[i].entry[e])));
           }
         FileWriteString(h, "</div></div>\r\n");
        }
      FileWriteString(h, StringFormat(
         "<div class=\"saxis\"><span>%s</span><span>%s</span></div>\r\n",
         SSRFormatMsc(from), SSRFormatMsc(to)));
      FileWriteString(h, "<p class=\"figcap\">Every mark is one entry, placed "
                         "at the moment it was taken. Green made money, red "
                         "did not. Hover for the time.</p>\r\n</div>\r\n");

      //--- the league table
      FileWriteString(h, "<h2>Results</h2>\r\n<div class=\"scroll\"><table>"
                         "<tr><th>Student</th><th class=\"n\">Trades</th>"
                         "<th class=\"n\">Win rate</th>"
                         "<th class=\"n\">Profit factor</th>"
                         "<th class=\"n\">Average R</th>"
                         "<th class=\"n\">Max drawdown</th>"
                         "<th class=\"n\">Worst streak</th>"
                         "<th class=\"n\">No stop</th>"
                         "<th class=\"n\">Net</th>"
                         "<th>Against the class</th></tr>\r\n");

      double peak = 0.0;
      for(int i = 0; i < m_count; i++)
         if(m_s[i].parsed && MathAbs(m_s[i].net_profit) > peak)
            peak = MathAbs(m_s[i].net_profit);

      for(int i = 0; i < m_count; i++)
        {
         if(!m_s[i].parsed)
            continue;
         bool odd = (m_key != "" && m_s[i].key != m_key);
         double w = (peak > 0.0 ? MathAbs(m_s[i].net_profit) / peak * 46.0 : 0.0);

         FileWriteString(h, StringFormat(
            "<tr><td>%s%s</td><td class=\"n\">%d</td><td class=\"n\">%s</td>"
            "<td class=\"n\">%s</td><td class=\"n\">%s</td>"
            "<td class=\"n\">%s</td><td class=\"n\">%d</td>"
            "<td class=\"n\">%s</td>"
            "<td class=\"n\"><span class=\"%s\">%s</span></td>"
            "<td class=\"bar\"><div class=\"bz\"></div>"
            "<div class=\"bf %s\" style=\"%s:50&#37;;width:%s&#37;\"></div>"
            "</td></tr>\r\n",
            Html(m_s[i].name),
            (odd ? " <span class=\"amb\">(different session)</span>" : ""),
            m_s[i].trades,
            DoubleToString(m_s[i].win_rate, 1) + "&#37;",
            (m_s[i].profit_factor > 0.0
             ? DoubleToString(m_s[i].profit_factor, 2) : "-"),
            DoubleToString(m_s[i].average_r, 2),
            DoubleToString(m_s[i].max_dd, 2) + " (" +
            DoubleToString(m_s[i].max_dd_pct, 1) + "&#37;)",
            m_s[i].loss_streak,
            (m_s[i].no_stop > 0
             ? "<span class=\"amb\">" + IntegerToString(m_s[i].no_stop) +
               "</span>" : "0"),
            Cls(m_s[i].net_profit), Signed(m_s[i].net_profit),
            Cls(m_s[i].net_profit),
            (m_s[i].net_profit >= 0.0 ? "left" : "right"),
            DoubleToString(w, 2)));
        }
      FileWriteString(h, "</table></div>\r\n");
      FileWriteString(h, "<p class=\"figcap\">\"No stop\" counts trades whose R "
                         "column was empty - risk that was never defined. It "
                         "is the most useful column here for a student who is "
                         "winning.</p>\r\n");

      //--- and the ones that could not be read
      if(readable < m_count)
        {
         FileWriteString(h, "<h2>Files that could not be read</h2>\r\n"
                            "<div class=\"scroll\"><table>"
                            "<tr><th>File</th><th>Why</th></tr>\r\n");
         for(int i = 0; i < m_count; i++)
            if(!m_s[i].parsed)
               FileWriteString(h, "<tr><td>" + Html(m_s[i].name) +
                                  "</td><td class=\"dim\">" +
                                  Html(m_s[i].problem) + "</td></tr>\r\n");
         FileWriteString(h, "</table></div>\r\n");
        }

      FileWriteString(h, "</div>\r\n");
      SSRWriteThemeToggle(h);
      FileWriteString(h, "</body></html>\r\n");
      FileClose(h);
      return true;
     }
  };

#endif // SSR_CLASS_REPORT_MQH
//+------------------------------------------------------------------+
