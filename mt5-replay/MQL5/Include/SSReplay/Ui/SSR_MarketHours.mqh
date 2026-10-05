//+------------------------------------------------------------------+
//|                                              SSR_MarketHours.mqh |
//|                    SS Replay - where in the trading day am I?    |
//|                                                                  |
//|  WHY THIS EXISTS                                                 |
//|  A replay strips the one piece of context a live screen gives     |
//|  away for free: what time it is in the world. A trainee stepping  |
//|  through candles cannot feel that this stretch is the Tokyo       |
//|  lunch and that one is the London open, and those two facts       |
//|  explain most of what the candles are doing.                     |
//|                                                                  |
//|  So: four bands and a line for NOW. It is a clock with the        |
//|  markets drawn on it.                                            |
//|                                                                  |
//|  WHAT THE HOURS ARE, AND WHAT THEY ARE NOT                       |
//|  They are the conventional UTC windows each centre quotes for     |
//|  itself. They are NOT broker hours, they are not this symbol's    |
//|  quote sessions, and each centre's own daylight saving moves its  |
//|  band by an hour for part of the year. This is drawn as a sense   |
//|  of place, not as a boundary to trade off, and the panel says so  |
//|  rather than implying a precision it does not have.              |
//|                                                                  |
//|  THE OFFSET IS MEASURED, NOT ASSUMED.                            |
//|  The replay clock runs on broker time. Broker time against UTC is |
//|  a number only the terminal knows, it differs between brokers,    |
//|  and writing one in here would be exactly the hardcoded broker    |
//|  logic this product refuses. It is taken from the terminal and    |
//|  PRINTED on the row, so a wrong one is visible instead of silent. |
//|                                                                  |
//|  Its one honest limit: the terminal reports the offset in force   |
//|  NOW, and a replay of last November may have run under a          |
//|  different one. That is an hour, on a widget whose whole job is   |
//|  to say "this is the London morning". Stated, not hidden.         |
//+------------------------------------------------------------------+
#ifndef SSR_MARKET_HOURS_MQH
#define SSR_MARKET_HOURS_MQH

#include "SSR_Strings.mqh"
#include "SSR_Theme.mqh"
#include "SSR_Widgets.mqh"
#include "../Common/SSR_Time.mqh"

//--- The grid, in pixels. Twenty-four columns plus a name gutter have
//--- to fit the 245 px sheet left over beside a 44 px rail, which is
//--- what sets the 8 and why the centres are three letters. 26 + 192
//--- is 218, drawn 6 px inside the group: 21 px of slack, which is
//--- what a longer translated name gets to spend.
#define SSR_MH_CW      8               // one hour
#define SSR_MH_RH     12               // one centre
#define SSR_MH_GUTTER 26               // room for "LON"
#define SSR_MH_W      (SSR_MH_GUTTER + 24 * SSR_MH_CW)

//+------------------------------------------------------------------+
//| One financial centre's conventional session, in UTC hours.       |
//|                                                                  |
//| `from` may be greater than `to`: Sydney opens at 22:00 and closes |
//| at 07:00 the next day, and a band that cannot wrap would either   |
//| draw it backwards or not at all.                                  |
//+------------------------------------------------------------------+
struct SSRMarketCentre
  {
   string            name;
   int               from_utc;
   int               to_utc;
   color             tint;

   bool              OpenAt(const int utc_hour)
     {
      if(from_utc <= to_utc)
         return (utc_hour >= from_utc && utc_hour < to_utc);
      return (utc_hour >= from_utc || utc_hour < to_utc);   // wraps midnight
     }
  };

//+------------------------------------------------------------------+
//| HOW MANY HOURS AHEAD OF UTC THIS BROKER'S CLOCK RUNS.            |
//|                                                                  |
//| TimeTradeServer and TimeGMT are both "right now", so the          |
//| difference is this terminal's own answer rather than a guess.     |
//| Rounded to the hour because a broker offset is whole hours in     |
//| practice and a stray minute would shift every band by a column.   |
//+------------------------------------------------------------------+
int SSRServerUtcOffsetHours(void)
  {
   datetime srv = TimeTradeServer();
   datetime utc = TimeGMT();
   if(srv <= 0 || utc <= 0)
      return 0;
   double h = ((double)srv - (double)utc) / 3600.0;
   return (int)MathRound(h);
  }

//+------------------------------------------------------------------+
//| The four, in the order the trading day actually opens them.      |
//+------------------------------------------------------------------+
void SSRMarketCentres(SSRMarketCentre &out[])
  {
   ArrayResize(out, 4);
   out[0].name = "SYD";  out[0].from_utc = 22; out[0].to_utc =  7;
   out[0].tint = SSR_C_LINE_LONG;
   out[1].name = "TOK";   out[1].from_utc =  0; out[1].to_utc =  9;
   out[1].tint = SSR_C_HOLD;
   out[2].name = "LON";  out[2].from_utc =  8; out[2].to_utc = 17;
   out[2].tint = SSR_C_RUN;
   out[3].name = "NY"; out[3].from_utc = 13; out[3].to_utc = 22;
   out[3].tint = SSR_C_STOP;
  }

//+------------------------------------------------------------------+
//| Draw the grid. Returns the height it used, so the sheet that     |
//| called it can put the next thing underneath without a second     |
//| copy of these numbers.                                            |
//|                                                                  |
//| `now_msc` is on the REPLAY's clock, which is broker time. Zero   |
//| means there is no session yet - the grid still draws, with no    |
//| marker, because an empty frame says less than an empty clock.    |
//+------------------------------------------------------------------+
int SSRDrawMarketHours(CSSRWidgets &w, const string pfx,
                       const int x, const int y, const long now_msc)
  {
   SSRMarketCentre c[];
   SSRMarketCentres(c);
   int n   = ArraySize(c);
   int gx  = x + SSR_MH_GUTTER;
   int off = SSRServerUtcOffsetHours();

   //--- where NOW falls, as an hour column and a fraction across it
   int  now_col  = -1;
   int  now_min  = 0;
   bool have_now = (now_msc > 0);
   MqlDateTime nt;
   if(have_now)
     {
      TimeToStruct(SSRToTime(now_msc), nt);
      now_col = nt.hour;
      now_min = nt.min;
     }

   int cy = y;

   //--- the hour ruler. Every third hour, because 24 numbers in 192 px
   //--- is a grey smear - and the three that matter (00, 09, 18) are
   //--- all divisible by three.
   for(int h = 0; h < 24; h += 3)
      w.Label(pfx + "h" + IntegerToString(h), gx + h * SSR_MH_CW - 2, cy,
              StringFormat("%02d", h), SSR_C_TEXT_FAINT, SSR_FS_SMALL);
   cy += 13;

   int grid_top = cy;

   for(int i = 0; i < n; i++)
     {
      string id = pfx + "r" + IntegerToString(i);
      int    ry = cy + i * SSR_MH_RH;

      w.Label(id + "n", x, ry + 1, c[i].name, SSR_C_TEXT_DIM, SSR_FS_SMALL);

      //--- the band as ONE rectangle per run of open hours, not one per
      //--- hour: twenty-four objects a row times four rows is ninety-six
      //--- chart objects for a picture that needs at most eight.
      int run_from = -1;
      for(int h = 0; h <= 24; h++)
        {
         bool open = (h < 24 && c[i].OpenAt(h));
         if(open && run_from < 0)
            run_from = h;
         if(!open && run_from >= 0)
           {
            w.Rect(id + "b" + IntegerToString(run_from),
                   gx + run_from * SSR_MH_CW, ry,
                   (h - run_from) * SSR_MH_CW, SSR_MH_RH - 2,
                   c[i].tint, c[i].tint);
            run_from = -1;
           }
        }
      //--- every band this product draws is one or two runs; the ids of
      //--- any third from a previous layout would linger, so the row is
      //--- swept of the columns it did not use this time.
      for(int h = 0; h < 24; h++)
         if(!c[i].OpenAt(h))
            w.Remove(id + "b" + IntegerToString(h));
     }
   cy += n * SSR_MH_RH;

   //--- THE OVERLAP, which is the only part of this grid a trader acts
   //--- on: London and New York open together is where the day's range
   //--- usually gets made. Marked under the bands rather than tinted
   //--- into them, so it reads as a comment on the picture.
   int ov_from = -1, ov_to = -1;
   for(int h = 0; h < 24; h++)
      if(c[2].OpenAt(h) && c[3].OpenAt(h))
        {
         if(ov_from < 0) ov_from = h;
         ov_to = h + 1;
        }
   if(ov_from >= 0)
     {
      w.Rect(pfx + "ov", gx + ov_from * SSR_MH_CW, cy + 1,
             (ov_to - ov_from) * SSR_MH_CW, 2, SSR_C_ACCENT, SSR_C_ACCENT);
      //--- AFTER THE BAR, not in the name gutter. The gutter is 26 px
      //--- wide because it holds three letters, and "overlap" is seven -
      //--- it was drawn straight over the column it was labelling.
      w.Label(pfx + "ovl", gx + ov_to * SSR_MH_CW + 4, cy - 3,
              T(SSR_S_MH_OVERLAP), SSR_C_ACCENT, SSR_FS_SMALL);
     }
   cy += 14;

   //--- NOW. Drawn last so it sits on top of every band, which is the
   //--- only z-order MetaTrader has.
   if(have_now && now_col >= 0)
     {
      int nx = gx + now_col * SSR_MH_CW + (now_min * SSR_MH_CW) / 60;
      w.Rect(pfx + "now", nx, grid_top - 2, 1,
             n * SSR_MH_RH + 2, SSR_C_TEXT, SSR_C_TEXT);
      w.Hide(pfx + "now", false);
      w.Label(pfx + "nowl", x, cy,
              StringFormat(T(SSR_S_MH_NOW), SSRWeekdayShort(nt.day_of_week),
                           nt.hour, nt.min, off),
              SSR_C_TEXT, SSR_FS_SMALL);
     }
   else
     {
      w.Hide(pfx + "now", true);
      w.Label(pfx + "nowl", x, cy, T(SSR_S_MH_NO_CLOCK),
              SSR_C_TEXT_FAINT, SSR_FS_SMALL);
     }
   cy += 13;

   //--- the caveat, in the same breath as the picture it qualifies
   w.Label(pfx + "note", x, cy, T(SSR_S_MH_NOTE),
           SSR_C_TEXT_FAINT, SSR_FS_SMALL);
   cy += 13;

   return cy - y;
  }

#endif // SSR_MARKET_HOURS_MQH
//+------------------------------------------------------------------+
