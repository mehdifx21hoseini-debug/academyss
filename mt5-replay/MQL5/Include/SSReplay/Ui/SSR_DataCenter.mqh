//+------------------------------------------------------------------+
//|                                               SSR_DataCenter.mqh |
//|                    SS Replay - what history do I actually have?  |
//|                                                                  |
//|  WHY THIS EXISTS                                                 |
//|  The commonest way a replay session fails is not a bug. It is a   |
//|  person choosing a symbol and a date for which their broker       |
//|  simply never sent them any minute bars. Until now the only way   |
//|  to find that out was to start a session and read the refusal.    |
//|                                                                  |
//|  So this window answers the question BEFORE it costs anything:    |
//|  for every symbol in Market Watch, the first and last minute bar  |
//|  the terminal holds, how many there are, and whether real ticks   |
//|  came with them.                                                  |
//|                                                                  |
//|  IT SCANS ONE SYMBOL PER TICK, ON PURPOSE.                       |
//|  CSSRHistoryProvider::Discover waits up to twenty seconds for a   |
//|  symbol's series to synchronise. Ninety symbols scanned in a      |
//|  loop is therefore a terminal that stops answering for half an    |
//|  hour, and a user who force-quits MetaTrader and files it as a    |
//|  freeze. One per Poll, with the count on screen, is the same work |
//|  done where the user can watch it and stop it.                    |
//|                                                                  |
//|  IT DOES NOT DOWNLOAD ANYTHING.                                   |
//|  Discover asks the terminal what it has and waits for a sync that |
//|  MetaTrader may or may not perform; it never requests history     |
//|  this product has not been told to use. A row that reads "none"   |
//|  means this terminal holds nothing for that symbol yet, and the   |
//|  cure is MetaTrader's own chart, not a button here that would     |
//|  pretend we control the broker's feed.                            |
//+------------------------------------------------------------------+
#ifndef SSR_DATA_CENTER_MQH
#define SSR_DATA_CENTER_MQH

#include "../Common/SSR_Types.mqh"
#include "../Common/SSR_Time.mqh"
#include "../Data/SSR_HistoryCatalog.mqh"
#include "../Data/SSR_Mt5Providers.mqh"
#include "SSR_Strings.mqh"
#include "SSR_Theme.mqh"
#include "SSR_Widgets.mqh"

#define SSR_DC_W        452
#define SSR_DC_ROWS     11
#define SSR_DC_ROW_H    17
//--- THE FOOTER BLOCK IS 76, AND THE NUMBER IS LOAD-BEARING.
//---
//--- It was 58, and at 58 the hint line sat six pixels inside the Stop
//--- button and was drawn through it. Nothing errors when two objects
//--- overlap - MetaTrader draws both - so this was invisible to every
//--- audit and showed up the moment the layout was rendered at its own
//--- coordinates. The three rows it has to clear, measured from the
//--- bottom of the window: buttons at -28 (22 high), hint at -48,
//--- progress at -62, and the paging row above them ends at +255.
#define SSR_DC_H        (SSR_HEADER_H + 46 + SSR_DC_ROWS * SSR_DC_ROW_H + 76)
#define SSR_DC_MAX      240            // Market Watch is not unbounded
#define SSR_DC_WAITS    6              // sync nudges before a row gives up

//--- column origins, measured from the window's left edge. Named so a
//--- change to one does not have to be chased through four functions.
#define SSR_DC_C_SYM    10
#define SSR_DC_C_FROM   104
#define SSR_DC_C_TO     196
#define SSR_DC_C_BARS   292
#define SSR_DC_C_TICKS  364

//+------------------------------------------------------------------+
//| One line of the inventory.                                        |
//+------------------------------------------------------------------+
struct SSRDcRow
  {
   string            symbol;
   bool              scanned;
   bool              available;
   long              first_msc;
   long              last_msc;
   long              bars;
   bool              has_ticks;
   bool              unsynced;         // asked for, not delivered in time
   int               waits;            // ticks spent waiting for a sync

   void              Init(const string s)
     {
      symbol    = s;
      scanned   = false;
      available = false;
      first_msc = 0;
      last_msc  = 0;
      bars      = 0;
      has_ticks = false;
      unsynced  = false;
      waits     = 0;
     }
  };

//+------------------------------------------------------------------+
class CSSRDataCenter
  {
private:
   long              m_chart;
   CSSRWidgets       m_w;
   string            m_prefix;
   bool              m_open;

   SSRDcRow          m_rows[];
   int               m_count;
   int               m_top;
   int               m_selected;
   int               m_next_scan;      // the cursor the slow scan walks
   bool              m_scanning;

   CSSRMt5HistoryProvider m_hist;
   CSSRHistoryCatalog  m_cat;

   int               m_x, m_y;

   //+------------------------------------------------------------------+
   //| A date a trader can read at a glance, in the column width there  |
   //| is. Day-month-year because that is what the rest of this product |
   //| prints and a window that disagrees with its own panel is a bug   |
   //| report waiting to be written.                                     |
   //+------------------------------------------------------------------+
   string            Day(const long msc)
     {
      if(msc <= 0)
         return "-";
      MqlDateTime t;
      TimeToStruct(SSRToTime(msc), t);
      return StringFormat("%02d.%02d.%04d", t.day, t.mon, t.year);
     }

   //--- 288,000 is unreadable; 288k is not.
   string            Count(const long bars)
     {
      if(bars <= 0)
         return "-";
      if(bars < 10000)
         return IntegerToString((int)bars);
      if(bars < 10000000)
         return IntegerToString((int)(bars / 1000)) + "k";
      return IntegerToString((int)(bars / 1000000)) + "M";
     }

public:
                     CSSRDataCenter(void)
     : m_chart(0), m_prefix("SSRDC_"), m_open(false), m_count(0),
       m_top(0), m_selected(-1), m_next_scan(0), m_scanning(false),
       m_x(40), m_y(40) {}

                    ~CSSRDataCenter(void) { Destroy(); }

   bool              IsOpen(void)   { return m_open; }
   bool              IsScanning(void) { return m_scanning; }

   //--- what the caller came for: the symbol the user picked, or "".
   string            Picked(void)
     {
      if(m_selected < 0 || m_selected >= m_count)
         return "";
      return m_rows[m_selected].symbol;
     }

   void              Create(const long chart_id, const string prefix = "SSRDC_")
     {
      m_chart  = chart_id;
      m_prefix = prefix;
      m_w.Attach(chart_id, prefix);
      m_cat.Attach(GetPointer(m_hist));
     }

   void              Destroy(void)
     {
      if(m_chart == 0)
         return;
      m_w.RemoveAll();
      m_open     = false;
      m_scanning = false;
     }

   //+------------------------------------------------------------------+
   //| Open on MARKET WATCH, not on every symbol the broker lists.      |
   //|                                                                  |
   //| A broker with twelve hundred instruments turns "scan everything" |
   //| into a six-hour job for a list nobody reads. Market Watch is the |
   //| set the trader has already said they care about, and adding to   |
   //| it is one keystroke in MetaTrader's own window.                   |
   //+------------------------------------------------------------------+
   void              Open(void)
     {
      int total = SymbolsTotal(true);
      if(total > SSR_DC_MAX)
         total = SSR_DC_MAX;
      m_count = 0;
      ArrayResize(m_rows, total);
      for(int i = 0; i < total; i++)
        {
         string s = SymbolName(i, true);
         if(s == "")
            continue;
         m_rows[m_count].Init(s);
         m_count++;
        }
      ArrayResize(m_rows, m_count);

      m_top       = 0;
      m_selected  = (m_count > 0 ? 0 : -1);
      m_next_scan = 0;
      m_scanning  = (m_count > 0);
      m_open      = true;
      Repaint();
     }

   void              Close(void)
     {
      m_open     = false;
      m_scanning = false;
      m_w.RemoveAll();
      ChartRedraw(m_chart);
     }

   //+------------------------------------------------------------------+
   //| ONE SYMBOL PER CALL, AND NEVER A BLOCKING ONE.                   |
   //|                                                                  |
   //| Discover waits up to twenty seconds for a series to synchronise. |
   //| Called from the host timer that is also driving the picker, that |
   //| is twenty seconds in which MetaTrader paints nothing - for ONE   |
   //| symbol, on the symbols most likely to be in the list precisely   |
   //| because they have never been opened.                             |
   //|                                                                  |
   //| So this never hands Discover an unsynchronised series. It nudges |
   //| the terminal, moves to the next symbol, and comes back. The wait |
   //| still happens; it happens across ticks instead of inside one,    |
   //| and the window stays alive while it does.                        |
   //|                                                                  |
   //| SSR_DC_WAITS is a budget, not a timeout: a symbol the terminal   |
   //| will not sync is reported as having nothing rather than holding  |
   //| the whole scan behind it.                                        |
   //+------------------------------------------------------------------+
   bool              ScanStep(void)
     {
      if(!m_open || !m_scanning)
         return false;

      //--- find the next unresolved row, wrapping once
      int start = m_next_scan;
      int i     = -1;
      for(int k = 0; k < m_count; k++)
        {
         int c = (start + k) % m_count;
         if(!m_rows[c].scanned)
           { i = c; break; }
        }
      if(i < 0)
        {
         m_scanning = false;
         Render();
         return false;
        }
      m_next_scan = (i + 1) % m_count;

      string sym = m_rows[i].symbol;

      //--- a symbol that is not in Market Watch cannot be read at all
      if(!SymbolSelect(sym, true))
        {
         m_rows[i].scanned = true;
         Touched(i);
         return true;
        }

      long synced = 0;
      SeriesInfoInteger(sym, PERIOD_M1, SERIES_SYNCHRONIZED, synced);

      if(synced == 0)
        {
         //--- the nudge: asking for two bars is what makes MetaTrader
         //--- start fetching the series in the first place.
         MqlRates warm[];
         ArraySetAsSeries(warm, false);
         CopyRates(sym, PERIOD_M1, 0, 2, warm);

         m_rows[i].waits++;
         if(m_rows[i].waits < SSR_DC_WAITS)
            return true;                  // come back to it next time round

         //+------------------------------------------------------------------+
         //| OUT OF BUDGET, AND THE ANSWER IS "I DO NOT KNOW YET".            |
         //|                                                                  |
         //| The tempting move here is to call Scan anyway and take whatever  |
         //| comes back. It would block for the full twenty seconds - this    |
         //| branch is reached precisely when the series is NOT synchronised, |
         //| which is the one condition Discover's wait does not return       |
         //| early on - and it would do it inside the host timer.             |
         //|                                                                  |
         //| So the row says it does not know. That is a worse-looking table  |
         //| and a truer one: a number read off an unsynchronised series is   |
         //| a number that changes while the user is reading it, and "Read    |
         //| again" costs them one press once the terminal has caught up.     |
         //+------------------------------------------------------------------+
         m_rows[i].scanned  = true;
         m_rows[i].unsynced = true;
         Touched(i);
         return true;
        }

      //--- SYNCHRONISED, so Discover's own wait is satisfied on its first
      //--- check and Scan returns without blocking. That is the whole
      //--- reason the test above is here rather than inside Discover.
      m_rows[i].scanned = true;
      if(m_cat.Scan(sym))
        {
         m_rows[i].available = true;
         m_rows[i].first_msc = m_cat.FirstMsc();
         m_rows[i].last_msc  = m_cat.LastMsc();
         m_rows[i].bars      = m_cat.BarCount();
         m_rows[i].has_ticks = m_cat.HasTicks();
        }
      Touched(i);
      return true;
     }

   //--- repaint the table only when the row that changed is on screen;
   //--- otherwise just move the counter. A full repaint per symbol on a
   //--- ninety-symbol list is ninety teardowns of eleven rows for a
   //--- change nobody can see.
   void              Touched(const int i)
     {
      if(i >= m_top && i < m_top + SSR_DC_ROWS)
         Render();
      else
         Progress();
     }

   //+------------------------------------------------------------------+
   void              Repaint(void)
     {
      if(!m_open)
         return;
      Render();
     }

   //--- the counter alone, for the ticks where nothing else moved
   void              Progress(void)
     {
      if(!m_open)
         return;
      m_w.Label("prog", m_x + SSR_DC_C_SYM, m_y + SSR_DC_H - 62,
                StatusText(), SSR_C_TEXT_DIM, SSR_FS_SMALL);
      ChartRedraw(m_chart);
     }

   string            StatusText(void)
     {
      if(m_count == 0)
         return T(SSR_S_DC_EMPTY);
      if(m_scanning)
         {
         int done = 0;
         for(int i = 0; i < m_count; i++)
            if(m_rows[i].scanned)
               done++;
         return StringFormat(T(SSR_S_DC_SCANNING), done, m_count);
        }
      int have = 0;
      for(int i = 0; i < m_count; i++)
         if(m_rows[i].available)
            have++;
      return StringFormat(T(SSR_S_DC_DONE), have, m_count);
     }

   //+------------------------------------------------------------------+
   void              Render(void)
     {
      if(!m_open || m_chart == 0)
         return;

      //--- centred on every render, because the user resizes the window
      int cw = (int)ChartGetInteger(m_chart, CHART_WIDTH_IN_PIXELS);
      int ch = (int)ChartGetInteger(m_chart, CHART_HEIGHT_IN_PIXELS);
      if(cw > SSR_DC_W + 16) m_x = (cw - SSR_DC_W) / 2;
      if(ch > SSR_DC_H + 16) m_y = (ch - SSR_DC_H) / 2;
      if(m_x < 0) m_x = 0;
      if(m_y < 0) m_y = 0;

      int x = m_x, y = m_y;

      m_w.Rect("bg", x, y, SSR_DC_W, SSR_DC_H, SSR_C_PANEL, SSR_C_PANEL_EDGE);
      m_w.Rect("hdr", x + 1, y + 1, SSR_DC_W - 2, SSR_HEADER_H,
               SSR_C_HEADER, SSR_C_GROUP_EDGE);
      m_w.Label("title", x + SSR_PAD, y + 5, T(SSR_S_DC_TITLE),
                SSR_C_ACCENT, SSR_FS_TITLE);
      m_w.Button("close", x + SSR_DC_W - 24, y + 3, 18, SSR_HEADER_H - 5, "X");

      int hy = y + SSR_HEADER_H + 6;
      m_w.Label("hs", x + SSR_DC_C_SYM,   hy, T(SSR_S_DC_H_SYMBOL),
                SSR_C_TEXT_FAINT, SSR_FS_SMALL);
      m_w.Label("hf", x + SSR_DC_C_FROM,  hy, T(SSR_S_DC_H_FROM),
                SSR_C_TEXT_FAINT, SSR_FS_SMALL);
      m_w.Label("ht", x + SSR_DC_C_TO,    hy, T(SSR_S_DC_H_TO),
                SSR_C_TEXT_FAINT, SSR_FS_SMALL);
      m_w.Label("hb", x + SSR_DC_C_BARS,  hy, T(SSR_S_DC_H_BARS),
                SSR_C_TEXT_FAINT, SSR_FS_SMALL);
      m_w.Label("hk", x + SSR_DC_C_TICKS, hy, T(SSR_S_DC_H_TICKS),
                SSR_C_TEXT_FAINT, SSR_FS_SMALL);

      int ly = hy + 14;
      m_w.Rect("well", x + 6, ly, SSR_DC_W - 12,
               SSR_DC_ROWS * SSR_DC_ROW_H + 4, SSR_C_WELL, SSR_C_WELL_EDGE);

      for(int r = 0; r < SSR_DC_ROWS; r++)
        {
         string id  = "r" + IntegerToString(r);
         int    idx = m_top + r;
         int    ry  = ly + 2 + r * SSR_DC_ROW_H;

         if(idx >= m_count)
           {
            m_w.Hide(id,          true);
            m_w.Hide(id + "_sel", true);
            m_w.Hide(id + "_f",   true);
            m_w.Hide(id + "_t",   true);
            m_w.Hide(id + "_b",   true);
            m_w.Hide(id + "_k",   true);
            continue;
           }

         m_w.Hide(id,        false);
         m_w.Hide(id + "_f", false);
         m_w.Hide(id + "_t", false);
         m_w.Hide(id + "_b", false);
         m_w.Hide(id + "_k", false);

         bool sel = (idx == m_selected);
         m_w.Hide(id + "_sel", !sel);
         if(sel)
            m_w.Rect(id + "_sel", x + 7, ry, SSR_DC_W - 14, SSR_DC_ROW_H - 1,
                     SSR_C_TAB_ON, SSR_C_ACCENT);

         //--- the symbol is a button so the row can be chosen; the rest
         //--- are labels, because a cell nobody can press should not
         //--- light up under the cursor as though it could.
         m_w.ButtonC(id, x + 8, ry, 92, SSR_DC_ROW_H - 1,
                     m_rows[idx].symbol,
                     sel ? SSR_C_TAB_ON : SSR_C_WELL,
                     sel ? SSR_C_TAB_ON : SSR_C_WELL,
                     SSR_C_TEXT, SSR_FS_SMALL);

         color col = SSR_C_TEXT_DIM;
         string f = "", t = "", b = "", k = "";

         //--- FOUR STATES, AND THE TABLE SAYS WHICH. "Blank" is not one
         //--- of them: a row that shows nothing cannot tell the user
         //--- whether it has not looked yet, looked and found nothing,
         //--- or is still waiting for the terminal.
         if(!m_rows[idx].scanned)
           { f = T(SSR_S_DC_PENDING);  col = SSR_C_TEXT_FAINT; }
         else if(m_rows[idx].unsynced)
           { f = T(SSR_S_DC_UNSYNCED); col = SSR_C_HOLD; }
         else if(!m_rows[idx].available)
           { f = T(SSR_S_DC_NONE);     col = SSR_C_STOP; }
         else
           {
            f = Day(m_rows[idx].first_msc);
            t = Day(m_rows[idx].last_msc);
            b = Count(m_rows[idx].bars);
            k = (m_rows[idx].has_ticks ? T(SSR_S_DC_REAL)
                                       : T(SSR_S_DC_BARS_ONLY));
           }

         m_w.Label(id + "_f", x + SSR_DC_C_FROM,  ry + 3, f, col, SSR_FS_SMALL);
         m_w.Label(id + "_t", x + SSR_DC_C_TO,    ry + 3, t, col, SSR_FS_SMALL);
         m_w.Label(id + "_b", x + SSR_DC_C_BARS,  ry + 3, b, col, SSR_FS_SMALL);
         m_w.Label(id + "_k", x + SSR_DC_C_TICKS, ry + 3, k,
                   m_rows[idx].has_ticks ? SSR_C_RUN : SSR_C_TEXT_FAINT,
                   SSR_FS_SMALL);
        }

      //--- paging. Hidden rather than removed when the list fits, so
      //--- the buttons do not have to be rebuilt the moment it does not.
      bool pages = (m_count > SSR_DC_ROWS);
      m_w.Hide("up",   !pages);
      m_w.Hide("down", !pages);
      if(pages)
        {
         int by = ly + SSR_DC_ROWS * SSR_DC_ROW_H + 10;
         m_w.Button("up",   x + SSR_DC_W - 62, by, 24, 18, "^");
         m_w.Button("down", x + SSR_DC_W - 34, by, 24, 18, "v");
        }

      m_w.Label("prog", x + SSR_DC_C_SYM, y + SSR_DC_H - 62,
                StatusText(), SSR_C_TEXT_DIM, SSR_FS_SMALL);

      //--- WHAT THE WINDOW IS FOR, spelled out. A table of dates with no
      //--- next action is a report; with this line it is a chooser.
      m_w.Label("hint", x + SSR_DC_C_SYM, y + SSR_DC_H - 48,
                T(SSR_S_DC_HINT), SSR_C_TEXT_FAINT, SSR_FS_SMALL);

      int fy = y + SSR_DC_H - SSR_BTN_H - 6;
      m_w.Button("stop", x + SSR_PAD, fy, 86, SSR_BTN_H,
                 m_scanning ? T(SSR_S_DC_STOP) : T(SSR_S_DC_RESCAN));
      m_w.ButtonC("use", x + SSR_DC_W - 104, fy, 96, SSR_BTN_H,
                  T(SSR_S_DC_USE), SSR_C_PRIMARY, SSR_C_PRIMARY_EDGE,
                  SSR_C_PRIMARY_TEXT, SSR_FS_BODY);

      ChartRedraw(m_chart);
     }

   //+------------------------------------------------------------------+
   //| Returns the symbol when the user chose one, "" otherwise. The    |
   //| caller closes the window: this class does not know what the      |
   //| choice is for.                                                   |
   //+------------------------------------------------------------------+
   string            Poll(const int id, const string sparam)
     {
      if(!m_open || id != CHARTEVENT_OBJECT_CLICK)
         return "";
      if(StringFind(sparam, m_prefix) != 0)
         return "";

      string what = StringSubstr(sparam, StringLen(m_prefix));
      ObjectSetInteger(m_chart, sparam, OBJPROP_STATE, false);

      if(what == "close")
        { Close(); return ""; }

      if(what == "up")
        {
         m_top -= SSR_DC_ROWS;
         if(m_top < 0) m_top = 0;
         Render();
         return "";
        }
      if(what == "down")
        {
         if(m_top + SSR_DC_ROWS < m_count)
            m_top += SSR_DC_ROWS;
         Render();
         return "";
        }

      if(what == "stop")
        {
         if(m_scanning)
            m_scanning = false;
         else
           {
            //--- a rescan starts from the top with the old answers
            //--- cleared, because a half-refreshed table is a table
            //--- nobody can date.
            for(int i = 0; i < m_count; i++)
               m_rows[i].Init(m_rows[i].symbol);
            m_next_scan = 0;
            m_scanning  = true;
           }
         Render();
         return "";
        }

      if(what == "use")
        {
         //--- REFUSED, WITH THE REASON, rather than handing back a
         //--- symbol the session will fail on thirty seconds later.
         if(m_selected < 0 || m_selected >= m_count)
            return "";
         if(!m_rows[m_selected].scanned || !m_rows[m_selected].available)
           {
            m_w.Label("hint", m_x + SSR_DC_C_SYM, m_y + SSR_DC_H - 48,
                      T(SSR_S_DC_CANNOT), SSR_C_STOP, SSR_FS_SMALL);
            ChartRedraw(m_chart);
            return "";
           }
         return m_rows[m_selected].symbol;
        }

      if(StringFind(what, "r") == 0 && StringLen(what) <= 3)
        {
         string tail = StringSubstr(what, 1);
         //--- "r3" is a row; "rule" is not. Digits only, or a control
         //--- whose name happens to start with r selects row zero.
         for(int c = 0; c < StringLen(tail); c++)
           {
            ushort ch = StringGetCharacter(tail, c);
            if(ch < '0' || ch > '9')
               return "";
           }
         int r = (int)StringToInteger(tail);
         if(m_top + r < m_count)
            m_selected = m_top + r;
         Render();
         return "";
        }
      return "";
     }
  };

#endif // SSR_DATA_CENTER_MQH
//+------------------------------------------------------------------+
