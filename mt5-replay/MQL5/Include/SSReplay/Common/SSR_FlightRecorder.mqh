//+------------------------------------------------------------------+
//|                                          SSR_FlightRecorder.mqh |
//|                     SS Replay - Black Box Recorder (L0/Common)   |
//|                                                                  |
//|  WHY THIS EXISTS                                                 |
//|  Five releases were spent diagnosing "the candles do not move"    |
//|  from screenshots and hand-copied log fragments. Every diagnosis  |
//|  was plausible. Three were wrong, and one of them - a diagnostic  |
//|  line that a stale input set silenced - produced no evidence at   |
//|  all. The loop did not close because the report could never       |
//|  separate the layers: engine, symbol, chart, view.                |
//|                                                                  |
//|  So the tool records itself. One file, written continuously,      |
//|  machine readable, sent as an attachment rather than retyped.     |
//|  No filtering by the person reporting the fault, no "I think it   |
//|  said something like", no lines lost to a scrollback buffer.      |
//|                                                                  |
//|  WHAT IT IS NOT                                                  |
//|  Not telemetry. It writes to MQL5/Files on the user's own disk    |
//|  and sends nothing anywhere. Not a log: the Experts tab keeps its |
//|  job of talking to a person, and this talks to a program.         |
//+------------------------------------------------------------------+
#ifndef SSR_FLIGHT_RECORDER_MQH
#define SSR_FLIGHT_RECORDER_MQH

#include "SSR_Types.mqh"
#include "SSR_Time.mqh"
#include "SSR_Build.mqh"

//--- one sample every this many milliseconds of wall time
#define SSR_FLIGHT_SAMPLE_MS   500
//--- and a ceiling, so a session left running overnight cannot fill a
//--- disk. About forty minutes of samples, which is far more than any
//--- fault has ever needed.
#define SSR_FLIGHT_MAX_ROWS    5000

//+------------------------------------------------------------------+
//| One row of the recorder. Filled by the host, which is the only    |
//| layer that can see the engine, the symbol and the chart at once.  |
//+------------------------------------------------------------------+
struct SSRFlightSample
  {
   //--- engine
   string            state;
   long              clock_msc;
   bool              playing;
   long              speed_x100;
   //--- symbol
   string            replay_symbol;
   int               m1_bars;
   long              last_bar_time;
   long              emit_calls;
   long              emit_ticks;
   long              seed_bars;
   long              truncations;
   //--- chart
   int               chart_count;
   long              chart_id;
   string            chart_symbol;
   string            chart_period;
   bool              autoscroll;
   bool              following;
   long              first_visible;
   long              visible_bars;
   long              view_offset;
   long              snaps;
   //--- host
   long              pumps;
   long              pump_delta_ms;

   void              Init(void)
     {
      state = ""; clock_msc = 0; playing = false; speed_x100 = 0;
      replay_symbol = ""; m1_bars = 0; last_bar_time = 0;
      emit_calls = 0; emit_ticks = 0; seed_bars = 0; truncations = 0;
      chart_count = 0; chart_id = 0; chart_symbol = ""; chart_period = "";
      autoscroll = false; following = false;
      first_visible = 0; visible_bars = 0; view_offset = 0; snaps = 0;
      pumps = 0; pump_delta_ms = 0;
     }
  };

//+------------------------------------------------------------------+
class CSSRFlightRecorder
  {
private:
   int                m_handle;
   string             m_path;
   long               m_rows;
   uint               m_last_sample_ms;
   bool               m_capped;
   bool               m_failed;
   string             m_error;

   //--- a field that can never break the column count
   string             Cell(const string s)
     {
      string out = s;
      StringReplace(out, ",", " ");
      StringReplace(out, "\r", " ");
      StringReplace(out, "\n", " ");
      StringReplace(out, "\"", "'");
      return out;
     }

   void               Line(const string text)
     {
      if(m_handle == INVALID_HANDLE)
         return;
      FileWriteString(m_handle, text + "\r\n");
      //--- flushed every line ON PURPOSE. The fault being chased may
      //--- end in a terminal that is closed, killed, or hung, and a
      //--- recording that only survives a clean shutdown would be
      //--- missing exactly the case worth having.
      FileFlush(m_handle);
     }

public:
                     CSSRFlightRecorder(void)
     : m_handle(INVALID_HANDLE), m_path(""), m_rows(0),
       m_last_sample_ms(0), m_capped(false), m_failed(false), m_error("")
     {}

                    ~CSSRFlightRecorder(void) { Close(); }

   bool               IsOpen(void)  { return m_handle != INVALID_HANDLE; }
   string             Path(void)    { return m_path; }
   long               Rows(void)    { return m_rows; }
   string             LastError(void) { return m_error; }

   //+------------------------------------------------------------------+
   //| One file per attach, named so the newest sorts last and so two   |
   //| charts running the tool cannot write to the same handle.         |
   //+------------------------------------------------------------------+
   bool               Open(const string tag)
     {
      Close();
      m_rows   = 0;
      m_capped = false;
      m_failed = false;
      m_error  = "";

      string when = TimeToString(TimeLocal(), TIME_DATE | TIME_MINUTES | TIME_SECONDS);
      StringReplace(when, ".", "");
      StringReplace(when, ":", "");
      StringReplace(when, " ", "-");
      m_path = "SSReplay-flight-" + Cell(tag) + "-" + when + ".csv";

      m_handle = FileOpen(m_path, FILE_WRITE | FILE_TXT | FILE_ANSI);
      if(m_handle == INVALID_HANDLE)
        {
         m_failed = true;
         m_error  = StringFormat("FileOpen(%s) failed err=%d", m_path, GetLastError());
         return false;
        }
      return true;
     }

   //+------------------------------------------------------------------+
   //| The header carries everything a reader needs to interpret the    |
   //| rows without asking the person who sent the file a single        |
   //| question. Every one of these has cost a round trip at some       |
   //| point in this project's history.                                 |
   //+------------------------------------------------------------------+
   void               Preamble(const string origin, const string replay_symbol,
                               const long win_start, const long win_end,
                               const int window_bars, const bool one_chart,
                               const bool reused_seed, const long picked_msc,
                               const double start_speed, const int pump_ms)
     {
      Line("# ss-replay-flight-recorder v1");
      Line("# build," + Cell(SSR_BUILD));
      Line("# terminal," + Cell(TerminalInfoString(TERMINAL_NAME)) +
           "," + IntegerToString(TerminalInfoInteger(TERMINAL_BUILD)));
      Line("# company," + Cell(AccountInfoString(ACCOUNT_COMPANY)));
      Line("# opened," + TimeToString(TimeLocal(), TIME_DATE | TIME_SECONDS));
      Line("# server_time," + TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS));
      Line("# origin," + Cell(origin));
      Line("# replay_symbol," + Cell(replay_symbol));
      Line("# window," + SSRFormatMsc(win_start) + "," + SSRFormatMsc(win_end));
      Line("# window_bars," + IntegerToString(window_bars));
      Line("# one_chart," + (one_chart ? "1" : "0"));
      Line("# reused_seed," + (reused_seed ? "1" : "0"));
      Line("# picked_start," + (picked_msc > 0 ? SSRFormatMsc(picked_msc) : "-"));
      Line("# start_speed," + DoubleToString(start_speed, 2));
      Line("# pump_ms," + IntegerToString(pump_ms));
      Line("# origin_m1_bars," + IntegerToString(Bars(origin, PERIOD_M1)));
      //--- what this build is capable of recording. Without it a reader
      //--- cannot tell "the marker is absent because the thing did not
      //--- happen" from "the marker is absent because this build never
      //--- wrote one" - and the first is a diagnosis while the second
      //--- is a guess wearing its clothes.
      Line("# markers,timer-entry,timer-guard,init-inherited,watchdog");
      Line("#");
      Line("# rows: kind=S is a sample, kind=E is an event");
      Line("kind,t,state,clock,playing,speed,rsym,m1,lastbar,emit_calls,"
           "emit_ticks,seed_bars,truncs,charts,chart_id,chart_sym,chart_tf,"
           "auto,follow,first,vis,off,snaps,pumps,delta_ms,note");
     }

   //+------------------------------------------------------------------+
   //| An event: a command, a transition, an error. Written the moment  |
   //| it happens, in the same stream as the samples, so cause and      |
   //| effect keep their order.                                         |
   //+------------------------------------------------------------------+
   void               Event(const string note)
     {
      if(m_handle == INVALID_HANDLE || m_capped)
         return;
      //--- 24 commas: an event fills kind and t, leaves the 23 sample
      //--- columns empty, and lands its text in the last one. Counted,
      //--- not eyeballed - a column-shifted file is a file that lies.
      Line("E," + TimeToString(TimeLocal(), TIME_SECONDS) +
           ",,,,,,,,,,,,,,,,,,,,,,,," + Cell(note));
      m_rows++;
     }

   //--- true when enough wall time has passed for the next sample
   bool               Due(void)
     {
      if(m_handle == INVALID_HANDLE || m_capped)
         return false;
      uint now = GetTickCount();
      if(m_last_sample_ms != 0 && (now - m_last_sample_ms) < SSR_FLIGHT_SAMPLE_MS)
         return false;
      m_last_sample_ms = now;
      return true;
     }

   void               Write(const SSRFlightSample &s)
     {
      if(m_handle == INVALID_HANDLE || m_capped)
         return;
      if(m_rows >= SSR_FLIGHT_MAX_ROWS)
        {
         m_capped = true;
         Line("# capped at " + IntegerToString(SSR_FLIGHT_MAX_ROWS) +
              " rows - reattach the EA to start a new recording");
         return;
        }

      Line(StringFormat(
              "S,%s,%s,%s,%d,%.2f,%s,%d,%s,%d,%d,%d,%d,%d,%d,%s,%s,%d,%d,%d,%d,%d,%d,%d,%d,",
              TimeToString(TimeLocal(), TIME_SECONDS),
              Cell(s.state),
              SSRFormatMsc(s.clock_msc),
              (int)s.playing,
              s.speed_x100 / 100.0,
              Cell(s.replay_symbol),
              s.m1_bars,
              (s.last_bar_time > 0
               ? TimeToString((datetime)s.last_bar_time, TIME_DATE | TIME_MINUTES)
               : "-"),
              (int)s.emit_calls, (int)s.emit_ticks,
              (int)s.seed_bars, (int)s.truncations,
              s.chart_count, (int)s.chart_id,
              Cell(s.chart_symbol), Cell(s.chart_period),
              (int)s.autoscroll, (int)s.following,
              (int)s.first_visible, (int)s.visible_bars, (int)s.view_offset,
              (int)s.snaps, (int)s.pumps, (int)s.pump_delta_ms));
      m_rows++;
     }

   void               Close(void)
     {
      if(m_handle == INVALID_HANDLE)
         return;
      Line("# closed," + TimeToString(TimeLocal(), TIME_DATE | TIME_SECONDS) +
           ",rows," + IntegerToString(m_rows));
      FileClose(m_handle);
      m_handle = INVALID_HANDLE;
     }
  };

#endif // SSR_FLIGHT_RECORDER_MQH
//+------------------------------------------------------------------+
