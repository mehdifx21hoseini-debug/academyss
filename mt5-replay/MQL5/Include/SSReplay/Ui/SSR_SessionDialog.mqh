//+------------------------------------------------------------------+
//|                                          SSR_SessionDialog.mqh   |
//|                    SS Replay - Pick A Saved Session (UI)         |
//|                                                                  |
//|  A list, not a text box.                                         |
//|                                                                  |
//|  Typing a session name and finding out afterwards whether it was |
//|  the right one is how a trader loads last Tuesday's session over |
//|  the one they meant. So the dialog shows what EXISTS, with the   |
//|  symbol and the instant each file holds, and the user picks.     |
//|                                                                  |
//|  IT ASKS BEFORE IT OVERWRITES. Saving onto a name that already   |
//|  exists replaces somebody's work, and there is no undo on disk.  |
//+------------------------------------------------------------------+
#ifndef SSR_SESSION_DIALOG_MQH
#define SSR_SESSION_DIALOG_MQH

#include "../Common/SSR_Types.mqh"
#include "../Common/SSR_Time.mqh"
#include "SSR_Theme.mqh"
#include "SSR_Widgets.mqh"
#include "SSR_ReplayPort.mqh"

#define SSR_SD_W        420
#define SSR_SD_H        260
#define SSR_SD_ROWS     8

enum ENUM_SSR_SD_MODE
  {
   SSR_SD_CLOSED = 0,
   SSR_SD_PICK,          // choose one to load
   SSR_SD_CONFIRM_SAVE   // it exists; really overwrite?
  };

//+------------------------------------------------------------------+
class CSSRSessionDialog
  {
private:
   long              m_chart;
   CSSRWidgets       m_w;
   CSSRReplayPort   *m_port;        // not owned
   string            m_prefix;

   ENUM_SSR_SD_MODE  m_mode;
   int               m_count;
   int               m_top;         // first visible row
   int               m_selected;
   string            m_pending;     // the name a save is waiting on
   string            m_message;

   int               m_x, m_y;

public:
                     CSSRSessionDialog(void)
     : m_chart(0), m_port(NULL), m_prefix("SSRSD_"),
       m_mode(SSR_SD_CLOSED), m_count(0), m_top(0), m_selected(-1),
       m_pending(""), m_message(""), m_x(60), m_y(60) {}

                    ~CSSRSessionDialog(void) { Destroy(); }

   void              Create(const long chart_id, CSSRReplayPort *port,
                            const string prefix = "SSRSD_")
     {
      m_chart  = chart_id;
      m_port   = port;
      m_prefix = prefix;
      m_w.Attach(chart_id, prefix);
      m_w.RemoveAll();
     }

   void              Destroy(void)
     {
      if(m_chart == 0)
         return;
      m_w.RemoveAll();
      m_mode = SSR_SD_CLOSED;
     }

   bool              IsOpen(void)      { return (m_mode != SSR_SD_CLOSED); }
   string            Message(void)     { return m_message; }
   string            Selected(void)
     { return (m_port != NULL && m_selected >= 0
               ? m_port.SessionName(m_selected) : ""); }

   //+------------------------------------------------------------------+
   void              Open(void)
     {
      if(m_port == NULL)
         return;
      m_count    = m_port.SessionCount();
      m_top      = 0;
      m_selected = (m_count > 0 ? 0 : -1);
      m_message  = (m_count == 0 ? "no saved sessions yet" : "");
      m_mode     = SSR_SD_PICK;
      Render();
     }

   void              Close(void)
     {
      m_mode = SSR_SD_CLOSED;
      m_w.RemoveAll();
      ChartRedraw(m_chart);
     }

   //+------------------------------------------------------------------+
   void              Render(void)
     {
      if(m_mode == SSR_SD_CLOSED)
         return;

      int x = m_x, y = m_y;
      m_w.Rect("bg", x, y, SSR_SD_W, SSR_SD_H, SSR_C_PANEL, SSR_C_PANEL_EDGE);
      m_w.Rect("hdr", x + 1, y + 1, SSR_SD_W - 2, SSR_HEADER_H,
               SSR_C_HEADER, SSR_C_HEADER);
      m_w.Label("title", x + SSR_PAD, y + 5,
                (m_mode == SSR_SD_CONFIRM_SAVE ? "OVERWRITE SESSION?" : "SESSIONS"),
                SSR_C_ACCENT, SSR_FS_TITLE);
      m_w.Button("close", x + SSR_SD_W - 24, y + 3, 18, SSR_HEADER_H - 5, "x");

      int cy = y + SSR_HEADER_H + SSR_GAP;

      if(m_mode == SSR_SD_CONFIRM_SAVE)
        {
         //--- NAMED, so the user is not confirming an abstraction
         m_w.Label("q1", x + SSR_PAD, cy,
                   "\"" + m_pending + "\" already exists.",
                   SSR_C_TEXT, SSR_FS_BODY);
         cy += SSR_ROW_H;
         m_w.Label("q2", x + SSR_PAD, cy,
                   "Saving replaces it. There is no undo on disk.",
                   SSR_C_HOLD, SSR_FS_SMALL);
         cy += SSR_ROW_H + SSR_GAP;
         m_w.Button("yes", x + SSR_PAD, cy, 110, SSR_BTN_H, "REPLACE IT");
         m_w.Button("no",  x + SSR_PAD + 118, cy, 110, SSR_BTN_H, "KEEP IT");
         ChartRedraw(m_chart);
         return;
        }

      //--- the list. Each row carries what the file HOLDS, not just
      //--- its name: the symbol, the instant, how far in it got.
      for(int r = 0; r < SSR_SD_ROWS; r++)
        {
         string id  = "row" + IntegerToString(r);
         int    idx = m_top + r;
         int    ry  = cy + r * (SSR_ROW_H - 2);

         if(idx >= m_count)
           {
            m_w.Hide(id, true);
            m_w.Hide(id + "_sel", true);
            continue;
           }
         m_w.Hide(id, false);
         m_w.Hide(id + "_sel", idx != m_selected);
         if(idx == m_selected)
            m_w.Rect(id + "_sel", x + 4, ry - 2, SSR_SD_W - 8, SSR_ROW_H - 3,
                     SSR_C_WELL, SSR_C_PANEL_EDGE);

         m_w.Button(id, x + 6, ry - 2, SSR_SD_W - 12, SSR_ROW_H - 3,
                    m_port.SessionSummary(idx), idx == m_selected);
        }
      cy += SSR_SD_ROWS * (SSR_ROW_H - 2) + SSR_GAP;

      m_w.Button("up",   x + SSR_PAD, cy, 40, SSR_BTN_H, "^", false, m_top > 0);
      m_w.Button("down", x + SSR_PAD + 44, cy, 40, SSR_BTN_H, "v", false,
                 m_top + SSR_SD_ROWS < m_count);
      m_w.Button("load", x + SSR_SD_W - SSR_PAD - 200, cy, 95, SSR_BTN_H,
                 "LOAD", false, m_selected >= 0);
      m_w.Button("del",  x + SSR_SD_W - SSR_PAD - 100, cy, 95, SSR_BTN_H,
                 "DELETE", false, m_selected >= 0);
      cy += SSR_BTN_H + 4;

      m_w.Label("msg", x + SSR_PAD, cy, m_message,
                (StringFind(m_message, "BUT") >= 0 ||
                 StringFind(m_message, "could not") >= 0
                 ? SSR_C_HOLD : SSR_C_TEXT_FAINT), SSR_FS_SMALL);
      ChartRedraw(m_chart);
     }

   //+------------------------------------------------------------------+
   //| Returns true when the event was ours.                            |
   //+------------------------------------------------------------------+
   bool              OnEvent(const int id, const long &lparam,
                             const double &dparam, const string &sparam)
     {
      if(m_mode == SSR_SD_CLOSED || id != CHARTEVENT_OBJECT_CLICK)
         return false;
      if(StringFind(sparam, m_prefix) != 0)
         return false;

      string what = StringSubstr(sparam, StringLen(m_prefix));
      ObjectSetInteger(m_chart, sparam, OBJPROP_STATE, false);

      if(what == "close")
        { Close(); return true; }

      if(m_mode == SSR_SD_CONFIRM_SAVE)
        {
         if(what == "yes")
           {
            bool ok = m_port.SaveSession(m_pending);
            m_message = (ok ? "saved \"" + m_pending + "\""
                            : "could not save: " + m_port.SessionError());
            m_pending = "";
            Open();                     // back to the refreshed list
            return true;
           }
         if(what == "no")
           { m_pending = ""; m_message = "kept the existing one"; Open(); return true; }
         return true;
        }

      if(what == "up")
        { if(m_top > 0) m_top--; Render(); return true; }
      if(what == "down")
        { if(m_top + SSR_SD_ROWS < m_count) m_top++; Render(); return true; }

      if(StringFind(what, "row") == 0)
        {
         int r = (int)StringToInteger(StringSubstr(what, 3));
         if(m_top + r < m_count)
            m_selected = m_top + r;
         Render();
         return true;
        }

      if(what == "load")
        {
         if(m_selected < 0)
            return true;
         string name = m_port.SessionName(m_selected);
         bool   ok   = m_port.LoadSession(name);
         //--- A SUCCESSFUL LOAD MAY STILL HAVE SOMETHING TO SAY. The
         //--- whole point of the fingerprint is that history which
         //--- changed since the save is reported, and swallowing that
         //--- because the load "worked" would undo it.
         string warn = m_port.SessionError();
         if(ok)
            m_message = "resumed \"" + name + "\"" +
                        (warn == "" ? "" : "  BUT: " + warn);
         else
            m_message = "could not resume: " + warn;
         Render();
         return true;
        }

      if(what == "del")
        {
         //--- deleting is NOT confirmed here, because the file it
         //--- removes is the one whose contents are on screen. The
         //--- confirmation is that the user had to select it first.
         m_message = "deleting is done from the session folder - this "
                     "dialog does not remove files";
         Render();
         return true;
        }
      return true;
     }

   //+------------------------------------------------------------------+
   //| Ask to save. Confirms first when the name is already taken.      |
   //+------------------------------------------------------------------+
   void              RequestSave(const string name)
     {
      if(m_port == NULL || name == "")
         return;
      m_pending = name;
      m_count   = m_port.SessionCount();
      for(int i = 0; i < m_count; i++)
         if(m_port.SessionName(i) == name)
           {
            m_mode = SSR_SD_CONFIRM_SAVE;
            Render();
            return;
           }

      bool ok = m_port.SaveSession(name);
      m_message = (ok ? "saved \"" + name + "\""
                      : "could not save: " + m_port.SessionError());
      m_pending = "";
      Open();
     }
  };

#endif // SSR_SESSION_DIALOG_MQH
//+------------------------------------------------------------------+
