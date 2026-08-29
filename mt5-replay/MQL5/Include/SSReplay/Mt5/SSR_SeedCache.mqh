//+------------------------------------------------------------------+
//|                                               SSR_SeedCache.mqh  |
//|                        SS Replay - Seed Reuse Manifest (MT5)     |
//|                                                                  |
//|  CACHE, NOT WINDOW - and the difference is the whole point.      |
//|                                                                  |
//|    Bar Window (Phase 2)  in memory, one range, one symbol, dies  |
//|                          with the session. Stops CopyRates from  |
//|                          being called on every pump.             |
//|                                                                  |
//|    Seed Cache (here)     on disk, survives restarts. Stops the   |
//|                          WARMUP from being written again.        |
//|                                                                  |
//|  Re-downloading is not the expensive part - MetaTrader already   |
//|  keeps broker history on disk. The expensive part is pushing a   |
//|  hundred thousand bars into the custom symbol, and that is what  |
//|  this avoids repeating.                                          |
//|                                                                  |
//|  It never trusts itself blindly: a manifest is only honoured     |
//|  after the symbol is checked for the bars it claims to hold.     |
//+------------------------------------------------------------------+
#ifndef SSR_SEED_CACHE_MQH
#define SSR_SEED_CACHE_MQH

#include "../Common/SSR_Types.mqh"
#include "../Common/SSR_Time.mqh"

#define SSR_CACHE_DIR   "SSReplay\\cache"

//+------------------------------------------------------------------+
struct SSRSeedManifest
  {
   string            version;
   string            origin;
   string            replay_symbol;
   long              warmup_from_msc;
   long              warmup_to_msc;
   long              bar_count;
   long              written_at;      // local time, for the user's benefit

   void              Init(void)
     {
      version = SSR_VERSION; origin = ""; replay_symbol = "";
      warmup_from_msc = SSR_INVALID_TIME;
      warmup_to_msc   = SSR_INVALID_TIME;
      bar_count = 0; written_at = 0;
     }

   bool              IsValid(void)
     {
      return (replay_symbol != "" && warmup_from_msc > 0 &&
              warmup_to_msc > warmup_from_msc && bar_count > 0);
     }

   string            ToString(void)
     {
      return StringFormat("manifest[%s %s..%s bars=%d]",
                          replay_symbol, SSRFormatMsc(warmup_from_msc),
                          SSRFormatMsc(warmup_to_msc), (int)bar_count);
     }
  };

//+------------------------------------------------------------------+
class CSSRSeedCache
  {
private:
   bool              m_enabled;
   long              m_hits;
   long              m_misses;
   long              m_bars_saved;
   string            m_last_reason;

   string            Path(const string replay_symbol)
     {
      string safe = replay_symbol;
      StringReplace(safe, "\\", "_");
      StringReplace(safe, "/",  "_");
      StringReplace(safe, ":",  "_");
      return SSR_CACHE_DIR + "\\" + safe + ".manifest";
     }

   string            Field(const string line, const string key)
     {
      string want = key + "=";
      if(StringFind(line, want) != 0)
         return "";
      return StringSubstr(line, StringLen(want));
     }

public:
                     CSSRSeedCache(void)
     : m_enabled(true), m_hits(0), m_misses(0), m_bars_saved(0), m_last_reason("") {}

   void              SetEnabled(const bool on) { m_enabled = on; }
   bool              IsEnabled(void)   { return m_enabled; }
   long              Hits(void)        { return m_hits; }
   long              Misses(void)      { return m_misses; }
   long              BarsSaved(void)   { return m_bars_saved; }
   string            LastReason(void)  { return m_last_reason; }

   //+------------------------------------------------------------------+
   bool              Save(SSRSeedManifest &m)
     {
      if(!m_enabled || !m.IsValid())
         return false;
      FolderCreate(SSR_CACHE_DIR);
      int h = FileOpen(Path(m.replay_symbol), FILE_WRITE | FILE_TXT | FILE_ANSI);
      if(h == INVALID_HANDLE)
         return false;

      m.written_at = (long)TimeLocal();
      FileWriteString(h, "version="       + m.version + "\r\n");
      FileWriteString(h, "origin="        + m.origin + "\r\n");
      FileWriteString(h, "symbol="        + m.replay_symbol + "\r\n");
      FileWriteString(h, "from="          + IntegerToString(m.warmup_from_msc) + "\r\n");
      FileWriteString(h, "to="            + IntegerToString(m.warmup_to_msc) + "\r\n");
      FileWriteString(h, "bars="          + IntegerToString(m.bar_count) + "\r\n");
      FileWriteString(h, "written="       + IntegerToString(m.written_at) + "\r\n");
      FileClose(h);
      return true;
     }

   bool              Load(const string replay_symbol, SSRSeedManifest &out)
     {
      out.Init();
      if(!m_enabled)
         return false;
      string p = Path(replay_symbol);
      if(!FileIsExist(p))
         return false;
      int h = FileOpen(p, FILE_READ | FILE_TXT | FILE_ANSI);
      if(h == INVALID_HANDLE)
         return false;

      while(!FileIsEnding(h))
        {
         string line = FileReadString(h);
         string v;
         if((v = Field(line, "version")) != "") out.version = v;
         else if((v = Field(line, "origin")) != "") out.origin = v;
         else if((v = Field(line, "symbol")) != "") out.replay_symbol = v;
         else if((v = Field(line, "from"))   != "") out.warmup_from_msc = StringToInteger(v);
         else if((v = Field(line, "to"))     != "") out.warmup_to_msc   = StringToInteger(v);
         else if((v = Field(line, "bars"))   != "") out.bar_count       = StringToInteger(v);
         else if((v = Field(line, "written"))!= "") out.written_at      = StringToInteger(v);
        }
      FileClose(h);
      return out.IsValid();
     }

   void              Invalidate(const string replay_symbol)
     {
      string p = Path(replay_symbol);
      if(FileIsExist(p))
         FileDelete(p);
     }

   //+------------------------------------------------------------------+
   //| Can the warmup already sitting in `replay_symbol` be reused for  |
   //| a session warming up over [from_msc, to_msc]?                    |
   //|                                                                  |
   //| Four things must agree, and the symbol itself gets the last      |
   //| word. A manifest is a claim; the bars are the evidence.          |
   //+------------------------------------------------------------------+
   bool              CanReuse(const string origin, const string replay_symbol,
                              const long from_msc, const long to_msc)
     {
      m_last_reason = "";
      if(!m_enabled)
        { m_last_reason = "cache disabled"; m_misses++; return false; }

      SSRSeedManifest m;
      if(!Load(replay_symbol, m))
        { m_last_reason = "no manifest"; m_misses++; return false; }

      if(m.version != SSR_VERSION)
        { m_last_reason = "written by another version"; m_misses++; return false; }
      if(m.origin != origin)
        { m_last_reason = "different origin symbol"; m_misses++; return false; }

      //--- the cached warmup must COVER the requested one. A narrower
      //--- cache would leave the earliest candles missing, which shows
      //--- up as an empty higher timeframe rather than as an error.
      if(m.warmup_from_msc > from_msc || m.warmup_to_msc < to_msc)
        { m_last_reason = "cached range does not cover the request"; m_misses++; return false; }

      //--- evidence: does the symbol actually still hold those bars?
      long bars = 0;
      SeriesInfoInteger(replay_symbol, PERIOD_M1, SERIES_BARS_COUNT, bars);
      if(bars <= 0)
        { m_last_reason = "symbol holds no bars"; m_misses++; return false; }

      long first = 0, last = 0;
      SeriesInfoInteger(replay_symbol, PERIOD_M1, SERIES_FIRSTDATE,   first);
      SeriesInfoInteger(replay_symbol, PERIOD_M1, SERIES_LASTBAR_DATE, last);
      if(first <= 0 || SSRToMsc((datetime)first) > from_msc)
        { m_last_reason = "symbol history starts too late"; m_misses++; return false; }
      if(last <= 0 || SSRToMsc((datetime)last) + SSR_MSC_PER_MIN - 1 < to_msc)
        { m_last_reason = "symbol history ends too early"; m_misses++; return false; }

      m_hits++;
      m_bars_saved += m.bar_count;
      m_last_reason = StringFormat("reused %d bars", (int)m.bar_count);
      return true;
     }

   string            ToString(void)
     {
      return StringFormat("seedcache[%s hits=%d misses=%d saved=%d bars]",
                          (m_enabled ? "on" : "off"),
                          (int)m_hits, (int)m_misses, (int)m_bars_saved);
     }
  };

#endif // SSR_SEED_CACHE_MQH
//+------------------------------------------------------------------+
