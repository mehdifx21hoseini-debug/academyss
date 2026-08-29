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

#define SSR_JOURNAL_DIR   "SSReplay\\journal"

//+------------------------------------------------------------------+
class CSSRJournal
  {
private:
   CSSRTradingEngine *m_acct;      // not owned
   CSSRStatsEngine   *m_stats;     // not owned; may be NULL
   string             m_last_error;
   string             m_last_path;

   string             Csv(const string s)
     {
      string r = s;
      StringReplace(r, ",", ";");
      StringReplace(r, "\n", " ");
      StringReplace(r, "\r", " ");
      return r;
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
     : m_acct(NULL), m_stats(NULL), m_last_error(""), m_last_path("") {}

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
