//+------------------------------------------------------------------+
//|                                                      SSR_Log.mqh |
//|                                   SS Replay - Logging (L0)       |
//|                                                                  |
//|  Levelled logging with an optional file sink. Kept deliberately  |
//|  small: the engine must never pay for logging in the hot loop,   |
//|  so every call site guards itself with the level check first.    |
//+------------------------------------------------------------------+
#ifndef SSR_LOG_MQH
#define SSR_LOG_MQH

enum ENUM_SSR_LOG_LEVEL
  {
   SSR_LOG_OFF = 0,
   SSR_LOG_ERROR,
   SSR_LOG_WARN,
   SSR_LOG_INFO,
   SSR_LOG_DEBUG,
   SSR_LOG_TRACE
  };

//+------------------------------------------------------------------+
class CSSRLog
  {
private:
   ENUM_SSR_LOG_LEVEL m_level;
   string             m_tag;
   string             m_file;
   bool               m_to_file;
   bool               m_to_print;

   string            Prefix(const string lvl)
     {
      return StringFormat("[SSR][%s][%s] ", lvl, m_tag);
     }

   void              Emit(const string lvl, const string msg)
     {
      string line = Prefix(lvl) + msg;
      if(m_to_print)
         Print(line);
      if(m_to_file && m_file != "")
        {
         int h = FileOpen(m_file, FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI);
         if(h != INVALID_HANDLE)
           {
            FileSeek(h, 0, SEEK_END);
            FileWriteString(h, TimeToString(TimeLocal(), TIME_DATE | TIME_SECONDS) +
                            " " + line + "\r\n");
            FileClose(h);
           }
        }
     }

public:
                     CSSRLog(void)
     : m_level(SSR_LOG_INFO), m_tag("core"), m_file(""), m_to_file(false), m_to_print(true) {}

   void              SetLevel(const ENUM_SSR_LOG_LEVEL l) { m_level = l; }
   ENUM_SSR_LOG_LEVEL Level(void)                         { return m_level; }
   void              SetTag(const string t)               { m_tag = t; }
   void              SetPrint(const bool on)              { m_to_print = on; }

   void              SetFile(const string relative_path)
     {
      m_file    = relative_path;
      m_to_file = (relative_path != "");
     }

   //--- callers check these before building an expensive message
   bool              IsError(void) { return m_level >= SSR_LOG_ERROR; }
   bool              IsWarn(void)  { return m_level >= SSR_LOG_WARN;  }
   bool              IsInfo(void)  { return m_level >= SSR_LOG_INFO;  }
   bool              IsDebug(void) { return m_level >= SSR_LOG_DEBUG; }
   bool              IsTrace(void) { return m_level >= SSR_LOG_TRACE; }

   void              Error(const string m) { if(IsError()) Emit("ERR ", m); }
   void              Warn (const string m) { if(IsWarn())  Emit("WARN", m); }
   void              Info (const string m) { if(IsInfo())  Emit("INFO", m); }
   void              Debug(const string m) { if(IsDebug()) Emit("DBG ", m); }
   void              Trace(const string m) { if(IsTrace()) Emit("TRC ", m); }
  };

//--- one shared logger; components may still own their own
CSSRLog g_ssr_log;

#endif // SSR_LOG_MQH
//+------------------------------------------------------------------+
