//+------------------------------------------------------------------+
//|                                              SSR_SessionFile.mqh |
//|                    SS Replay - Sectioned Key/Value Files (L0)    |
//|                                                                  |
//|  The format a whole session is written in. No domain knowledge   |
//|  lives here - this file knows about sections, keys and values,   |
//|  and nothing about replays, trades or charts. Each layer         |
//|  serialises ITSELF through this, which is what keeps the session |
//|  format from becoming a place where every layer meets.           |
//|                                                                  |
//|  WHY TEXT, NOT A BINARY STRUCT DUMP                              |
//|                                                                  |
//|  FileWriteStruct is faster and would be wrong twice over. A      |
//|  virtual position holds strings and a nested leg ledger, so it   |
//|  is not a POD and cannot be dumped at all. And a binary layout   |
//|  changes silently whenever a field is added - a file written by  |
//|  yesterday's build would load into today's struct, field by      |
//|  field, shifted, and produce a session that looks plausible and  |
//|  is nonsense. Text plus a version number cannot do that.         |
//|                                                                  |
//|  A VERSION IT DOES NOT KNOW IS REFUSED, not guessed at. Reading  |
//|  a future file as best we can is how a trader's account history  |
//|  quietly changes shape.                                          |
//+------------------------------------------------------------------+
#ifndef SSR_SESSION_FILE_MQH
#define SSR_SESSION_FILE_MQH

#include "SSR_Types.mqh"

//--- entries a session may hold. A full desk is roughly:
//---   4096 equity samples + 512 positions + four streams of settings
//--- so this is about three times the worst realistic case.
#define SSR_SF_MAX_ENTRIES   16384
#define SSR_SF_MAX_SECTIONS  1024

//--- the format's own version, separate from the product's. It changes
//--- only when the LAYOUT changes, so a build bump does not orphan
//--- everyone's saved sessions.
#define SSR_SF_FORMAT        1

//+------------------------------------------------------------------+
class CSSRSessionFile
  {
private:
   //--- Parsed contents: one flat list, each entry tagged with the
   //--- section it belongs to. Sessions are small enough that a linear
   //--- scan is cheaper than any structure that would need maintaining.
   //---
   //--- DYNAMIC, not fixed. At the ceiling below, fixed arrays would
   //--- make this object about a megabyte - and it is declared as a
   //--- local inside Save and Restore, so that megabyte would be on
   //--- the stack. Dynamic arrays put it on the heap and cost only
   //--- what the file actually holds.
   string            m_sec_name[];
   int               m_sec_count;

   int               m_ent_sec[];
   string            m_ent_key[];
   string            m_ent_val[];
   int               m_ent_count;

   //--- grow in blocks rather than per entry: resizing four arrays
   //--- once per key would dominate the cost of reading the file
   bool              Reserve(const int need)
     {
      if(ArraySize(m_ent_key) >= need)
         return true;
      int want = (need < 256 ? 256 : need * 2);
      if(want > SSR_SF_MAX_ENTRIES)
         want = SSR_SF_MAX_ENTRIES;
      return (ArrayResize(m_ent_sec, want) == want &&
              ArrayResize(m_ent_key, want) == want &&
              ArrayResize(m_ent_val, want) == want);
     }

   bool              ReserveSections(const int need)
     {
      if(ArraySize(m_sec_name) >= need)
         return true;
      int want = (need < 32 ? 32 : need * 2);
      if(want > SSR_SF_MAX_SECTIONS)
         want = SSR_SF_MAX_SECTIONS;
      return (ArrayResize(m_sec_name, want) == want);
     }

   int               m_cursor;          // the selected section, or -1
   int               m_handle;          // open for writing, or INVALID
   int               m_write_sec;
   int               m_format;
   bool              m_truncated;       // we ran out of room
   string            m_last_error;
   string            m_path;

   void              Fail(const string why) { m_last_error = why; }

   string            Trim(const string s)
     {
      string t = s;
      StringTrimLeft(t);
      StringTrimRight(t);
      return t;
     }

public:
                     CSSRSessionFile(void)
     : m_sec_count(0), m_ent_count(0), m_cursor(-1),
       m_handle(INVALID_HANDLE), m_write_sec(0), m_format(SSR_SF_FORMAT),
       m_truncated(false), m_last_error(""), m_path("") {}

                    ~CSSRSessionFile(void) { Close(); }

   string            LastError(void)  { return m_last_error; }
   string            Path(void)       { return m_path; }
   int               Format(void)     { return m_format; }
   int               EntryCount(void) { return m_ent_count; }
   int               SectionTotal(void) { return m_sec_count; }
   bool              Truncated(void)  { return m_truncated; }

   void              Clear(void)
     {
      m_sec_count = 0;
      m_ent_count = 0;
      m_cursor    = -1;
      m_truncated = false;
      ArrayResize(m_sec_name, 0);
      ArrayResize(m_ent_sec,  0);
      ArrayResize(m_ent_key,  0);
      ArrayResize(m_ent_val,  0);
     }

   //================================================================
   //  WRITING
   //================================================================
   bool              Create(const string path)
     {
      m_last_error = "";
      m_path       = path;
      m_handle = FileOpen(path, FILE_WRITE | FILE_TXT | FILE_ANSI);
      if(m_handle == INVALID_HANDLE)
        {
         Fail("cannot write " + path + " (err " + IntegerToString(GetLastError()) + ")");
         return false;
        }
      m_write_sec = 0;
      FileWriteString(m_handle, "# SS Replay session file\r\n");
      FileWriteString(m_handle, StringFormat("# format %d\r\n", SSR_SF_FORMAT));
      return true;
     }

   //--- a comment. Used to name the columns of a packed row, so the
   //--- file stays readable by a person even where it is compact.
   void              Comment(const string text)
     {
      if(m_handle != INVALID_HANDLE)
         FileWriteString(m_handle, "# " + text + "\r\n");
     }

   void              Section(const string name)
     {
      if(m_handle == INVALID_HANDLE)
         return;
      if(m_write_sec > 0)
         FileWriteString(m_handle, "\r\n");
      FileWriteString(m_handle, "[" + name + "]\r\n");
      m_write_sec++;
     }

   void              Set(const string key, const string value)
     {
      if(m_handle == INVALID_HANDLE)
         return;
      //--- a newline in a value would forge a new entry on read, so it
      //--- is neutralised rather than trusted
      string v = value;
      StringReplace(v, "\r", " ");
      StringReplace(v, "\n", " ");
      FileWriteString(m_handle, key + "=" + v + "\r\n");
     }

   void              SetLong(const string key, const long v)
     { Set(key, IntegerToString(v)); }
   void              SetInt(const string key, const int v)
     { Set(key, IntegerToString(v)); }
   void              SetBool(const string key, const bool v)
     { Set(key, (v ? "1" : "0")); }

   //--- doubles are written with enough digits to survive the round
   //--- trip. A balance that comes back a cent short after a save is
   //--- the kind of bug nobody finds for months.
   void              SetDouble(const string key, const double v,
                               const int digits = 8)
     { Set(key, DoubleToString(v, digits)); }

   bool              Close(void)
     {
      if(m_handle == INVALID_HANDLE)
         return false;
      FileClose(m_handle);
      m_handle = INVALID_HANDLE;
      return true;
     }

   //================================================================
   //  READING
   //================================================================
   bool              Load(const string path)
     {
      m_last_error = "";
      m_path       = path;
      Clear();

      int h = FileOpen(path, FILE_READ | FILE_TXT | FILE_ANSI);
      if(h == INVALID_HANDLE)
        {
         Fail("cannot read " + path);
         return false;
        }

      int cur = -1;
      m_format = 0;
      while(!FileIsEnding(h))
        {
         string line = Trim(FileReadString(h));
         if(line == "")
            continue;

         if(StringGetCharacter(line, 0) == StringGetCharacter("#", 0))
           {
            //--- the format line is the one comment that means something
            if(StringFind(line, "# format ") == 0)
               m_format = (int)StringToInteger(StringSubstr(line, 9));
            continue;
           }

         if(StringGetCharacter(line, 0) == StringGetCharacter("[", 0))
           {
            int close = StringFind(line, "]");
            if(close < 1)
               continue;
            if(m_sec_count >= SSR_SF_MAX_SECTIONS ||
               !ReserveSections(m_sec_count + 1))
              { m_truncated = true; break; }
            m_sec_name[m_sec_count] = StringSubstr(line, 1, close - 1);
            cur = m_sec_count++;
            continue;
           }

         int eq = StringFind(line, "=");
         if(eq < 1 || cur < 0)
            continue;
         if(m_ent_count >= SSR_SF_MAX_ENTRIES || !Reserve(m_ent_count + 1))
           { m_truncated = true; break; }

         m_ent_sec[m_ent_count] = cur;
         m_ent_key[m_ent_count] = StringSubstr(line, 0, eq);
         m_ent_val[m_ent_count] = StringSubstr(line, eq + 1);
         m_ent_count++;
        }
      FileClose(h);

      if(m_truncated)
        {
         //--- LOUD, not a shrug. A session read halfway is a session
         //--- with trades missing from the middle of it.
         Fail(StringFormat("file is larger than this build can hold "
                           "(%d entries) - it was NOT fully read",
                           SSR_SF_MAX_ENTRIES));
         return false;
        }
      if(m_format <= 0)
        {
         Fail("not an SS Replay session file - no format line");
         return false;
        }
      if(m_format > SSR_SF_FORMAT)
        {
         Fail(StringFormat("session written by a newer build (format %d, "
                           "this build reads %d) - refusing rather than "
                           "guessing at it", m_format, SSR_SF_FORMAT));
         return false;
        }
      return true;
     }

   //--- how many sections carry this name
   int               SectionCount(const string name)
     {
      int n = 0;
      for(int i = 0; i < m_sec_count; i++)
         if(m_sec_name[i] == name)
            n++;
      return n;
     }

   //--- select the nth section with this name; everything read after
   //--- this comes from it
   bool              Select(const string name, const int nth = 0)
     {
      int seen = 0;
      for(int i = 0; i < m_sec_count; i++)
        {
         if(m_sec_name[i] != name)
            continue;
         if(seen == nth)
           { m_cursor = i; return true; }
         seen++;
        }
      m_cursor = -1;
      return false;
     }

   bool              Has(const string key)
     {
      for(int i = 0; i < m_ent_count; i++)
         if(m_ent_sec[i] == m_cursor && m_ent_key[i] == key)
            return true;
      return false;
     }

   //--- how many entries in the selected section carry this key. More
   //--- than one is normal: a packed row repeats its key per record.
   int               Count(const string key)
     {
      int n = 0;
      for(int i = 0; i < m_ent_count; i++)
         if(m_ent_sec[i] == m_cursor && m_ent_key[i] == key)
            n++;
      return n;
     }

   string            GetNth(const string key, const int nth,
                            const string def = "")
     {
      int seen = 0;
      for(int i = 0; i < m_ent_count; i++)
        {
         if(m_ent_sec[i] != m_cursor || m_ent_key[i] != key)
            continue;
         if(seen == nth)
            return m_ent_val[i];
         seen++;
        }
      return def;
     }

   string            Get(const string key, const string def = "")
     { return GetNth(key, 0, def); }

   long              GetLong(const string key, const long def = 0)
     {
      string v = Get(key, "");
      return (v == "" ? def : StringToInteger(v));
     }

   int               GetInt(const string key, const int def = 0)
     { return (int)GetLong(key, def); }

   double            GetDouble(const string key, const double def = 0.0)
     {
      string v = Get(key, "");
      return (v == "" ? def : StringToDouble(v));
     }

   bool              GetBool(const string key, const bool def = false)
     {
      string v = Get(key, "");
      if(v == "")
         return def;
      return (v == "1" || v == "true" || v == "yes");
     }
  };

//+------------------------------------------------------------------+
//| Packed rows.                                                     |
//|                                                                  |
//| A position is one LINE, not twenty keys. Twenty keys per trade    |
//| would put five hundred trades past any sane entry ceiling, and a  |
//| row a person can read across is easier to check than a block      |
//| they have to scroll.                                              |
//|                                                                  |
//| The separator is a pipe because it cannot occur in a symbol, a    |
//| number or a formatted time - unlike a comma, which is in every    |
//| locale's decimal point.                                           |
//+------------------------------------------------------------------+
#define SSR_SF_SEP   "|"

string SSRPackAdd(const string row, const string field)
  {
   string f = field;
   StringReplace(f, SSR_SF_SEP, "/");     // never forge a column
   return (row == "" ? f : row + SSR_SF_SEP + f);
  }

int SSRUnpack(const string row, string &out[])
  {
   return StringSplit(row, StringGetCharacter(SSR_SF_SEP, 0), out);
  }

//--- field accessors that cannot walk off the end of a short row
string SSRField(const string &f[], const int i, const string def = "")
  { return (i >= 0 && i < ArraySize(f) ? f[i] : def); }

long   SSRFieldLong(const string &f[], const int i, const long def = 0)
  {
   string v = SSRField(f, i, "");
   return (v == "" ? def : StringToInteger(v));
  }

double SSRFieldDouble(const string &f[], const int i, const double def = 0.0)
  {
   string v = SSRField(f, i, "");
   return (v == "" ? def : StringToDouble(v));
  }

#endif // SSR_SESSION_FILE_MQH
//+------------------------------------------------------------------+
