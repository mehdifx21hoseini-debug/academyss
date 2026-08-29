//+------------------------------------------------------------------+
//|                                             SSR_RandomPicker.mqh |
//|                    SS Replay - Reproducible Random Start (L2)    |
//|                                                                  |
//|  Random Replay exists to stop the trader recognising the period. |
//|  Practising on a stretch you already know the ending of teaches  |
//|  you nothing except that you have a good memory.                 |
//|                                                                  |
//|  TWO THINGS THIS REFUSES TO DO                                   |
//|                                                                  |
//|  1. Pick a start it cannot justify. A start needs warmup behind  |
//|     it and a session's worth of bars ahead of it; a symbol that  |
//|     cannot supply both is skipped BY NAME, not silently dropped  |
//|     into a session that ends after four candles.                 |
//|                                                                  |
//|  2. Pick unrepeatably. Every pick comes from a seed, and the     |
//|     seed is reported. The session the trader wants to go back to |
//|     and study is the one they just did badly on, so it must be   |
//|     possible to ask for it again.                                |
//+------------------------------------------------------------------+
#ifndef SSR_RANDOM_PICKER_MQH
#define SSR_RANDOM_PICKER_MQH

#include "../Common/SSR_Types.mqh"
#include "../Common/SSR_Time.mqh"
#include "../Common/SSR_Random.mqh"
#include "SSR_HistoryCatalog.mqh"

#define SSR_MAX_RANDOM_SYMBOLS   32

//--- how many symbols to try before giving up. Bounded, because a
//--- list where nothing has enough history must produce an error the
//--- user can read, not a loop.
#define SSR_PICK_ATTEMPTS        8

//+------------------------------------------------------------------+
class CSSRRandomPicker
  {
private:
   CSSRHistoryCatalog *m_cat;                  // not owned
   SSRRandom           m_rng;
   ulong               m_seed;

   string              m_pool[SSR_MAX_RANDOM_SYMBOLS];
   int                 m_pool_count;

   string              m_last_error;
   string              m_skipped;              // why each candidate failed

   //--- the result of the last Pick()
   string              m_symbol;
   long                m_start_msc;
   long                m_end_msc;

   void              Fail(const string why) { m_last_error = why; }

public:
                     CSSRRandomPicker(void)
     : m_cat(NULL), m_seed(0), m_pool_count(0), m_last_error(""),
       m_skipped(""), m_symbol(""), m_start_msc(SSR_INVALID_TIME),
       m_end_msc(SSR_INVALID_TIME)
     { m_rng.Seed(1); }

   void              Attach(CSSRHistoryCatalog *c) { m_cat = c; }

   //--- the seed. Set it to repeat a session; leave it and one is
   //--- picked and reported.
   void              SetSeed(const ulong s)
     { m_seed = (s == 0 ? SSRPickSeed() : s); m_rng.Seed(m_seed); }
   ulong             Seed(void)     { return m_seed; }
   string            SeedText(void) { return SSRSeedText(m_seed); }

   //--- the candidate symbols. Empty means "whatever the caller names".
   bool              AddSymbol(const string s)
     {
      if(s == "" || m_pool_count >= SSR_MAX_RANDOM_SYMBOLS)
         return false;
      for(int i = 0; i < m_pool_count; i++)
         if(m_pool[i] == s)
            return true;
      m_pool[m_pool_count++] = s;
      return true;
     }

   //--- accepts "EURUSD,XAUUSD, US30" - spaces and empties tolerated
   int               AddSymbolList(const string csv)
     {
      string parts[];
      int n = StringSplit(csv, StringGetCharacter(",", 0), parts);
      int added = 0;
      for(int i = 0; i < n; i++)
        {
         string s = parts[i];
         StringTrimLeft(s);
         StringTrimRight(s);
         if(s != "" && AddSymbol(s))
            added++;
        }
      return added;
     }

   void              ClearSymbols(void) { m_pool_count = 0; }
   int               SymbolCount(void)  { return m_pool_count; }
   string            SymbolAt(const int i)
     { return (i >= 0 && i < m_pool_count ? m_pool[i] : ""); }

   string            LastError(void)  { return m_last_error; }
   string            SkippedText(void){ return m_skipped; }

   //--- the last pick
   string            PickedSymbol(void) { return m_symbol; }
   long              PickedStart(void)  { return m_start_msc; }
   long              PickedEnd(void)    { return m_end_msc; }
   bool              HasPick(void)      { return (m_start_msc > 0); }

   //+------------------------------------------------------------------+
   //| Pick a symbol and a start that the broker can actually serve.    |
   //|                                                                  |
   //| `fallback` is used when no pool was given - the single symbol    |
   //| the caller is already working with, made random in TIME only.    |
   //+------------------------------------------------------------------+
   bool              Pick(const long warmup_bars, const long replay_minutes,
                         const string fallback = "")
     {
      m_last_error = "";
      m_skipped    = "";
      m_symbol     = "";
      m_start_msc  = SSR_INVALID_TIME;
      m_end_msc    = SSR_INVALID_TIME;

      if(m_cat == NULL)
        { Fail("no catalogue attached"); return false; }
      if(m_seed == 0)
         SetSeed(0);                    // report a seed rather than none

      if(m_pool_count == 0)
        {
         if(fallback == "")
           { Fail("no symbols to choose from"); return false; }
         AddSymbol(fallback);
        }

      //--- try candidates until one has the depth. Each rejection is
      //--- recorded by name: "nothing worked" is not a useful answer.
      int attempts = (m_pool_count < SSR_PICK_ATTEMPTS
                      ? m_pool_count : SSR_PICK_ATTEMPTS);
      for(int a = 0; a < attempts; a++)
        {
         string sym = m_pool[m_rng.Index(m_pool_count)];

         if(!m_cat.Scan(sym))
           {
            m_skipped += sym + " (no history) ";
            continue;
           }

         long lo = m_cat.EarliestStart(warmup_bars);
         long hi = m_cat.LatestStart(warmup_bars, replay_minutes);
         if(lo <= 0 || hi <= 0 || hi <= lo)
           {
            m_skipped += StringFormat("%s (needs %I64d warmup + %I64d replay bars, has %I64d) ",
                                      sym, warmup_bars, replay_minutes,
                                      m_cat.BarCount());
            continue;
           }

         //--- an M1 boundary, because that is where a replay can
         //--- honestly begin - the engine would snap to one anyway,
         //--- and a reported start that is not the real one is a lie
         //--- the user will eventually notice
         long pick = SSRBarOpenMsc(m_rng.InRange(lo, hi), PERIOD_M1);
         if(pick < lo)
            pick = SSRBarOpenMsc(lo, PERIOD_M1) + SSR_MSC_PER_MIN;

         m_symbol    = sym;
         m_start_msc = pick;
         m_end_msc   = pick + replay_minutes * SSR_MSC_PER_MIN;
         if(m_end_msc > m_cat.LastMsc())
            m_end_msc = m_cat.LastMsc();
         return true;
        }

      Fail("no candidate had enough history: " +
           (m_skipped == "" ? "(none tried)" : m_skipped));
      return false;
     }

   //--- the line the user writes down to come back to this session
   string            Ticket(void)
     {
      if(!HasPick())
         return "no pick";
      return StringFormat("seed %s", SeedText());
     }

   string            ToString(void)
     {
      if(!HasPick())
         return StringFormat("picker[seed=%s no pick: %s]",
                             SeedText(), m_last_error);
      return StringFormat("picker[seed=%s -> %s %s .. %s]",
                          SeedText(), m_symbol,
                          SSRFormatMsc(m_start_msc), SSRFormatMsc(m_end_msc));
     }
  };

#endif // SSR_RANDOM_PICKER_MQH
//+------------------------------------------------------------------+
