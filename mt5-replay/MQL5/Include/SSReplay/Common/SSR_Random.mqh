//+------------------------------------------------------------------+
//|                                                   SSR_Random.mqh |
//|                    SS Replay - Reproducible Randomness (L0)      |
//|                                                                  |
//|  WHY NOT MathRand()                                              |
//|                                                                  |
//|  A random replay you cannot repeat is a lesson you cannot go     |
//|  back to. The trader takes a bad session, wants to see the same  |
//|  bars again with a clear head - and the tool has no way to       |
//|  produce them, because MathRand() carries one global sequence    |
//|  shared with every other program in the terminal and seeded by   |
//|  whatever ran before.                                            |
//|                                                                  |
//|  So: a self-contained generator with an explicit seed, and the   |
//|  seed is REPORTED. "Session 8_143_772_915" is a thing the user   |
//|  can write down and come back to. That is the whole point; the   |
//|  statistical quality of the stream is a distant second, and      |
//|  xorshift64* is already far better than this needs.              |
//+------------------------------------------------------------------+
#ifndef SSR_RANDOM_MQH
#define SSR_RANDOM_MQH

#include "SSR_Types.mqh"

//+------------------------------------------------------------------+
//| xorshift64*, seeded explicitly. Pure integer state, so the same  |
//| seed gives the same sequence on every machine and every run.     |
//+------------------------------------------------------------------+
struct SSRRandom
  {
   ulong             state;

   void              Seed(const ulong s)
     {
      //--- zero is the one state xorshift cannot leave, so it is
      //--- replaced rather than allowed to produce an endless run of
      //--- the same "random" number
      state = (s == 0 ? 0x9E3779B97F4A7C15 : s);
     }

   ulong             Next(void)
     {
      state ^= state >> 12;
      state ^= state << 25;
      state ^= state >> 27;
      return state * (ulong)2685821657736338717;
     }

   //--- a value in [lo, hi). Returns lo when the range is empty, which
   //--- is the only sane answer and never a crash.
   long              InRange(const long lo, const long hi)
     {
      if(hi <= lo)
         return lo;
      ulong span = (ulong)(hi - lo);
      return lo + (long)(Next() % span);
     }

   //--- an index into [0, count)
   int               Index(const int count)
     {
      if(count <= 0)
         return 0;
      return (int)(Next() % (ulong)count);
     }

   //--- a coin, for the callers that want one
   bool              Chance(const int percent)
     {
      if(percent <= 0)   return false;
      if(percent >= 100) return true;
      return ((int)(Next() % 100) < percent);
     }
  };

//+------------------------------------------------------------------+
//| A seed to start from when the user did not supply one.           |
//|                                                                  |
//| This is the ONE place a wall clock may be read, and it is not    |
//| replay logic: it picks a number to print back at the user. Once  |
//| picked, everything downstream is a pure function of it.          |
//+------------------------------------------------------------------+
ulong SSRPickSeed(void)
  {
   ulong a = (ulong)TimeLocal();
   ulong b = GetMicrosecondCount();
   ulong s = (a * 1000003) ^ (b * 2654435761);
   return (s == 0 ? 1 : s);
  }

//--- how the seed is shown to the user and typed back in
string SSRSeedText(const ulong seed) { return IntegerToString((long)seed); }

ulong  SSRSeedFromText(const string text)
  {
   string t = text;
   StringTrimLeft(t);
   StringTrimRight(t);
   if(t == "")
      return 0;
   return (ulong)StringToInteger(t);
  }

#endif // SSR_RANDOM_MQH
//+------------------------------------------------------------------+
