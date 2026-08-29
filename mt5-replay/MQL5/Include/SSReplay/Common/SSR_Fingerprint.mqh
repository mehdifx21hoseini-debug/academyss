//+------------------------------------------------------------------+
//|                                              SSR_Fingerprint.mqh |
//|                    SS Replay - Data Fingerprint (L0)             |
//|                                                                  |
//|  THE PROBLEM THIS EXISTS FOR                                     |
//|                                                                  |
//|  A session file does not contain the price data. It cannot -     |
//|  that would be tens of megabytes - so on resume the bars are     |
//|  re-read from the broker and re-seeded into the custom symbol.   |
//|                                                                  |
//|  Which means the chart a trader comes back to is only the chart  |
//|  they left IF the broker's history has not changed. It does      |
//|  change: gaps get filled, bad prints get revised, a reconnect     |
//|  pulls a different depth, and switching broker changes it        |
//|  wholesale.                                                      |
//|                                                                  |
//|  Silently continuing would let a trader review yesterday's trade |
//|  against bars that no longer look the way they did when it was   |
//|  taken - and conclude something about their own decision from a  |
//|  chart the decision was never made on.                           |
//|                                                                  |
//|  So the replayed range is fingerprinted at save time and checked |
//|  at load. A mismatch does NOT block the resume - the trader may  |
//|  well want to continue anyway - it is REPORTED.                  |
//|                                                                  |
//|  WHAT THIS IS NOT                                                |
//|  Not a cryptographic hash and not trying to be. It has to catch  |
//|  history that changed by accident, not history altered by        |
//|  someone trying to fool it.                                      |
//+------------------------------------------------------------------+
#ifndef SSR_FINGERPRINT_MQH
#define SSR_FINGERPRINT_MQH

#include "SSR_Types.mqh"
#include "SSR_Time.mqh"

//+------------------------------------------------------------------+
struct SSRFingerprint
  {
   long              bars;         // how many bars were in the range
   long              first_msc;    // and where it actually began
   long              last_msc;     // and ended
   ulong             digest;       // over every OHLC in between

   void              Init(void)
     { bars = 0; first_msc = SSR_INVALID_TIME; last_msc = SSR_INVALID_TIME; digest = 0; }

   bool              IsValid(void) { return (bars > 0); }

   bool              Equals(SSRFingerprint &o)
     {
      return (bars == o.bars && first_msc == o.first_msc &&
              last_msc == o.last_msc && digest == o.digest);
     }

   //+------------------------------------------------------------------+
   //| What differs, in words. "The fingerprints differ" tells a user   |
   //| nothing they can act on; "eleven bars appeared" tells them the   |
   //| broker back-filled a gap.                                        |
   //+------------------------------------------------------------------+
   string            DiffText(SSRFingerprint &o)
     {
      if(Equals(o))
         return "";
      if(!o.IsValid())
         return "the broker has no history for this range any more";
      if(bars != o.bars)
         return StringFormat("%I64d bars then, %I64d now (%+I64d) - "
                             "the broker's history for this range changed",
                             bars, o.bars, o.bars - bars);
      if(first_msc != o.first_msc || last_msc != o.last_msc)
         return StringFormat("the range moved: %s..%s then, %s..%s now",
                             SSRFormatMsc(first_msc), SSRFormatMsc(last_msc),
                             SSRFormatMsc(o.first_msc), SSRFormatMsc(o.last_msc));
      return "same bar count and range, but the prices in them changed - "
             "the broker revised this history";
     }

   string            ToString(void)
     {
      if(!IsValid())
         return "fingerprint[none]";
      return StringFormat("fingerprint[%I64d bars %s..%s %I64u]",
                          bars, SSRFormatMsc(first_msc),
                          SSRFormatMsc(last_msc), digest);
     }
  };

//+------------------------------------------------------------------+
//| Fold one bar into a running digest.                              |
//|                                                                  |
//| Prices are folded as INTEGERS scaled by their own digits. A       |
//| double's bit pattern would make the digest depend on how the      |
//| value was arrived at rather than on what it is, so a bar that     |
//| round-tripped through the session file would differ from the      |
//| identical bar read fresh - and every resume would cry wolf.       |
//+------------------------------------------------------------------+
void SSRDigestBar(ulong &digest, const MqlRates &bar, const int digits)
  {
   double scale = MathPow(10, digits);
   ulong  parts[5];
   parts[0] = (ulong)bar.time;
   parts[1] = (ulong)MathRound(bar.open  * scale);
   parts[2] = (ulong)MathRound(bar.high  * scale);
   parts[3] = (ulong)MathRound(bar.low   * scale);
   parts[4] = (ulong)MathRound(bar.close * scale);

   for(int i = 0; i < 5; i++)
     {
      //--- FNV-1a's mixing, which is cheap and spreads a one-tick
      //--- change across the whole word
      digest ^= parts[i];
      digest *= 0x100000001B3;                   // FNV-1a prime
     }
  }

//--- fingerprint a series of bars
void SSRFingerprintBars(const MqlRates &bars[], const int count,
                        const int digits, SSRFingerprint &out)
  {
   out.Init();
   if(count <= 0)
      return;
   out.digest = 0xCBF29CE484222325;               // FNV-1a offset basis
   for(int i = 0; i < count; i++)
      SSRDigestBar(out.digest, bars[i], digits);
   out.bars      = count;
   out.first_msc = SSRToMsc(bars[0].time);
   out.last_msc  = SSRToMsc(bars[count - 1].time);
  }

//+------------------------------------------------------------------+
//| The round trip through a session file, as one packed field.      |
//|                                                                  |
//| The digest travels as a SIGNED long even though it is unsigned.  |
//| Written as %I64u it would exceed what StringToInteger can read   |
//| back for any digest above the signed maximum - about half of     |
//| them - and every such session would report a false mismatch.     |
//| The two's-complement bit pattern round trips exactly.            |
//+------------------------------------------------------------------+
string SSRFingerprintPack(SSRFingerprint &f)
  {
   return StringFormat("%I64d;%I64d;%I64d;%I64d",
                       f.bars, f.first_msc, f.last_msc, (long)f.digest);
  }

bool SSRFingerprintUnpack(const string s, SSRFingerprint &out)
  {
   out.Init();
   string p[];
   if(StringSplit(s, StringGetCharacter(";", 0), p) < 4)
      return false;
   out.bars      = StringToInteger(p[0]);
   out.first_msc = StringToInteger(p[1]);
   out.last_msc  = StringToInteger(p[2]);
   out.digest    = (ulong)(long)StringToInteger(p[3]);
   return true;
  }

#endif // SSR_FINGERPRINT_MQH
//+------------------------------------------------------------------+
