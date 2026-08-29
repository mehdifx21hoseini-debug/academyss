//+------------------------------------------------------------------+
//|                                            SSR_PositionFile.mqh  |
//|                     SS Replay - Save and Resume Position (L2)    |
//|                                                                  |
//|  A snapshot on disk. Deliberately the SAME struct the rewind ring |
//|  holds, so "resume where I left off" and "step back" are the same |
//|  operation with a different source - not two mechanisms that will |
//|  drift apart.                                                     |
//|                                                                  |
//|  Plain key=value rather than JSON: less code to get wrong, and a  |
//|  user can read it when something goes strange.                    |
//+------------------------------------------------------------------+
#ifndef SSR_POSITION_FILE_MQH
#define SSR_POSITION_FILE_MQH

#include "../Common/SSR_Types.mqh"
#include "../Common/SSR_Time.mqh"
#include "SSR_Snapshot.mqh"

#define SSR_POSITION_DIR   "SSReplay\\positions"

//+------------------------------------------------------------------+
class CSSRPositionFile
  {
private:
   string            m_last_error;

   string            Path(const string key)
     {
      string safe = key;
      StringReplace(safe, "\\", "_");
      StringReplace(safe, "/",  "_");
      StringReplace(safe, ":",  "_");
      StringReplace(safe, ".",  "_");
      return SSR_POSITION_DIR + "\\" + safe + ".pos";
     }

   string            Field(const string line, const string k)
     {
      string want = k + "=";
      return (StringFind(line, want) == 0 ? StringSubstr(line, StringLen(want)) : "");
     }

public:
                     CSSRPositionFile(void) : m_last_error("") {}
   string            LastError(void) { return m_last_error; }

   bool              Save(const string key, SSRSnapshot &s)
     {
      m_last_error = "";
      if(!s.IsValid())
        {
         m_last_error = "snapshot is not valid";
         return false;
        }
      FolderCreate(SSR_POSITION_DIR);
      int h = FileOpen(Path(key), FILE_WRITE | FILE_TXT | FILE_ANSI);
      if(h == INVALID_HANDLE)
        {
         m_last_error = "cannot open " + Path(key);
         return false;
        }

      FileWriteString(h, "version="   + s.version + "\r\n");
      FileWriteString(h, "label="     + s.label + "\r\n");
      FileWriteString(h, "symbol="    + s.state.symbol + "\r\n");
      FileWriteString(h, "taken="     + IntegerToString(s.taken_at_msc) + "\r\n");
      FileWriteString(h, "start="     + IntegerToString(s.timeline.start_msc) + "\r\n");
      FileWriteString(h, "end="       + IntegerToString(s.timeline.end_msc) + "\r\n");
      FileWriteString(h, "warmup="    + IntegerToString(s.timeline.warmup_first_msc) + "\r\n");
      FileWriteString(h, "dfirst="    + IntegerToString(s.timeline.data_first_msc) + "\r\n");
      FileWriteString(h, "dlast="     + IntegerToString(s.timeline.data_last_msc) + "\r\n");
      FileWriteString(h, "now="       + IntegerToString(s.clock.now_msc) + "\r\n");
      FileWriteString(h, "speed="     + IntegerToString(s.clock.speed_x100) + "\r\n");
      FileWriteString(h, "emitted="   + IntegerToString(s.cursor.emitted_msc) + "\r\n");
      FileWriteString(h, "ticks="     + IntegerToString(s.cursor.tick_count) + "\r\n");
      FileWriteString(h, "bars="      + IntegerToString(s.cursor.bar_count) + "\r\n");
      FileWriteString(h, "fidelity="  + IntegerToString((int)s.state.fidelity) + "\r\n");
      FileWriteString(h, "datamode="  + IntegerToString((int)s.state.data_mode) + "\r\n");
      FileClose(h);
      return true;
     }

   bool              Load(const string key, SSRSnapshot &out)
     {
      m_last_error = "";
      out.Init();
      string p = Path(key);
      if(!FileIsExist(p))
        {
         m_last_error = "no saved position";
         return false;
        }
      int h = FileOpen(p, FILE_READ | FILE_TXT | FILE_ANSI);
      if(h == INVALID_HANDLE)
        {
         m_last_error = "cannot read " + p;
         return false;
        }

      while(!FileIsEnding(h))
        {
         string line = FileReadString(h), v;
         if((v = Field(line, "version"))  != "") out.version = v;
         else if((v = Field(line, "label"))    != "") out.label = v;
         else if((v = Field(line, "symbol"))   != "") out.state.symbol = v;
         else if((v = Field(line, "taken"))    != "") out.taken_at_msc = StringToInteger(v);
         else if((v = Field(line, "start"))    != "") out.timeline.start_msc = StringToInteger(v);
         else if((v = Field(line, "end"))      != "") out.timeline.end_msc = StringToInteger(v);
         else if((v = Field(line, "warmup"))   != "") out.timeline.warmup_first_msc = StringToInteger(v);
         else if((v = Field(line, "dfirst"))   != "") out.timeline.data_first_msc = StringToInteger(v);
         else if((v = Field(line, "dlast"))    != "") out.timeline.data_last_msc = StringToInteger(v);
         else if((v = Field(line, "now"))      != "") out.clock.now_msc = StringToInteger(v);
         else if((v = Field(line, "speed"))    != "") out.clock.speed_x100 = StringToInteger(v);
         else if((v = Field(line, "emitted"))  != "") out.cursor.emitted_msc = StringToInteger(v);
         else if((v = Field(line, "ticks"))    != "") out.cursor.tick_count = StringToInteger(v);
         else if((v = Field(line, "bars"))     != "") out.cursor.bar_count = StringToInteger(v);
         else if((v = Field(line, "fidelity")) != "") out.state.fidelity = (ENUM_SSR_FIDELITY)StringToInteger(v);
         else if((v = Field(line, "datamode")) != "") out.state.data_mode = (ENUM_SSR_DATA_MODE)StringToInteger(v);
        }
      FileClose(h);

      //--- rebuild the parts that are derived rather than stored
      out.clock.start_msc  = out.timeline.start_msc;
      out.clock.end_msc    = out.timeline.end_msc;
      out.state.start_msc  = out.timeline.start_msc;
      out.state.end_msc    = out.timeline.end_msc;
      out.state.current_msc = out.clock.now_msc;
      //--- a resumed session is never left running
      out.state.status     = SSR_STATE_PAUSED;

      if(!out.IsValid())
        {
         m_last_error = "saved position is incomplete";
         return false;
        }
      return true;
     }

   bool              Exists(const string key) { return FileIsExist(Path(key)); }
   void              Remove(const string key)
     { if(FileIsExist(Path(key))) FileDelete(Path(key)); }
  };

#endif // SSR_POSITION_FILE_MQH
//+------------------------------------------------------------------+
