//+------------------------------------------------------------------+
//|                                              SSR_TradeTypes.mqh  |
//|                   SS Replay - Virtual Trading Vocabulary (L2)    |
//|                                                                  |
//|  Nothing here reaches a broker. There is no OrderSend in this     |
//|  layer and there never will be - a replay tool that can place a   |
//|  real order is one misconfiguration away from a very bad day.     |
//+------------------------------------------------------------------+
#ifndef SSR_TRADE_TYPES_MQH
#define SSR_TRADE_TYPES_MQH

#include "../Common/SSR_Types.mqh"
#include "../Common/SSR_Time.mqh"

enum ENUM_SSR_ORDER
  {
   SSR_ORDER_BUY = 0,
   SSR_ORDER_SELL,
   SSR_ORDER_BUY_LIMIT,
   SSR_ORDER_SELL_LIMIT,
   SSR_ORDER_BUY_STOP,
   SSR_ORDER_SELL_STOP
  };

enum ENUM_SSR_POS_STATE
  {
   SSR_POS_PENDING = 0,
   SSR_POS_OPEN,
   SSR_POS_CLOSED,
   SSR_POS_CANCELLED
  };

enum ENUM_SSR_CLOSE_REASON
  {
   SSR_CLOSE_NONE = 0,
   SSR_CLOSE_MANUAL,
   SSR_CLOSE_SL,
   SSR_CLOSE_TP,
   SSR_CLOSE_PARTIAL,
   SSR_CLOSE_STOPOUT,
   SSR_CLOSE_SESSION_END
  };

string SSROrderName(const ENUM_SSR_ORDER t)
  {
   switch(t)
     {
      case SSR_ORDER_BUY:        return "BUY";
      case SSR_ORDER_SELL:       return "SELL";
      case SSR_ORDER_BUY_LIMIT:  return "BUY LIMIT";
      case SSR_ORDER_SELL_LIMIT: return "SELL LIMIT";
      case SSR_ORDER_BUY_STOP:   return "BUY STOP";
      case SSR_ORDER_SELL_STOP:  return "SELL STOP";
     }
   return "?";
  }

string SSRCloseReasonName(const ENUM_SSR_CLOSE_REASON r)
  {
   switch(r)
     {
      case SSR_CLOSE_MANUAL:      return "manual";
      case SSR_CLOSE_SL:          return "stop loss";
      case SSR_CLOSE_TP:          return "take profit";
      case SSR_CLOSE_PARTIAL:     return "partial";
      case SSR_CLOSE_STOPOUT:     return "stop out";
      case SSR_CLOSE_SESSION_END: return "session end";
     }
   return "open";
  }

bool SSRIsLong(const ENUM_SSR_ORDER t)
  {
   return (t == SSR_ORDER_BUY || t == SSR_ORDER_BUY_LIMIT || t == SSR_ORDER_BUY_STOP);
  }
bool SSRIsPending(const ENUM_SSR_ORDER t)
  { return (t != SSR_ORDER_BUY && t != SSR_ORDER_SELL); }

//+------------------------------------------------------------------+
//| WHICH PENDING ORDER THREE LINES ON A CHART DESCRIBE.             |
//|                                                                  |
//| The side comes from where the STOP sits relative to the entry,   |
//| and limit-versus-stop from where the entry sits relative to the  |
//| market. Both are already drawn; asking the user to also pick     |
//| "buy limit" from a list would be asking them to repeat, in       |
//| words, a thing they have just said with a mouse - and to be      |
//| wrong about it half the time.                                    |
//|                                                                  |
//| It lives here, as a free function over four doubles, so it can   |
//| be tested without a chart, an account or a price feed. The rule  |
//| is the feature; everything around it is plumbing.                |
//+------------------------------------------------------------------+
bool SSRPendingFor(const double entry, const double stop, const double bid,
                   const double min_dist, ENUM_SSR_ORDER &out, string &why)
  {
   out = SSR_ORDER_BUY;
   why = "";

   if(entry <= 0.0 || stop <= 0.0 || bid <= 0.0)
     { why = "there is no entry line yet"; return false; }

   double gap = MathAbs(entry - stop);
   if(gap < min_dist)
     {
      why = "the entry and the stop are on top of each other - "
            "drag them apart";
      return false;
     }

   //--- ON the price is not a pending order, it is a market order that
   //--- has been drawn instead of pressed. Say which button they want
   //--- rather than placing something that fills on the next tick.
   if(MathAbs(entry - bid) < min_dist)
     {
      why = "the entry line is on the price - drag it away from here, "
            "or press Buy / Sell for a market order";
      return false;
     }

   bool is_long = (stop < entry);
   if(is_long)
      out = (entry < bid ? SSR_ORDER_BUY_LIMIT : SSR_ORDER_BUY_STOP);
   else
      out = (entry > bid ? SSR_ORDER_SELL_LIMIT : SSR_ORDER_SELL_STOP);
   return true;
  }

//+------------------------------------------------------------------+
//| One reduction of a position's size, and everything needed to     |
//| put it back.                                                     |
//|                                                                  |
//| WHY THIS EXISTS                                                  |
//| A rewind means the future did not happen. That has to include    |
//| the parts of a trade that were taken off in it. Without a record |
//| of each exit, an engine can only restore a position wholesale -  |
//| which is right for a trade that was closed in one go and wrong   |
//| for one that was scaled out of, leaving the trader holding a     |
//| size they never chose at a moment they never traded.             |
//|                                                                  |
//| So every exit, partial or final, is a leg, and a rewind unwinds  |
//| legs newest-first until none of them is in the future.           |
//+------------------------------------------------------------------+
struct SSRTradeLeg
  {
   double            volume;      // taken off by this leg
   double            price;
   long              msc;
   double            realised;    // profit this leg booked
   double            fee;         // commission this leg charged
   bool              closing;     // this leg ended the position

   //--- what the leg overwrote, so undoing it is exact rather than
   //--- recomputed from a state that no longer exists
   double            prev_swap_locked;
   long              prev_swap_from_msc;
   bool              prev_ambiguous;

   //--- Every field is written when a leg is booked, so nothing reads
   //--- an uninitialised one today. This exists so that stays true:
   //--- the guard is leg_count, and a guard is one edit away from
   //--- being forgotten.
   void              Init(void)
     {
      volume = 0.0; price = 0.0; msc = SSR_INVALID_TIME;
      realised = 0.0; fee = 0.0; closing = false;
      prev_swap_locked = 0.0; prev_swap_from_msc = SSR_INVALID_TIME;
      prev_ambiguous = false;
     }
  };

//--- legs per position. One is always reserved for the final close,
//--- so a trade can be scaled out of SSR_MAX_TRADE_LEGS-1 times.
#define SSR_MAX_TRADE_LEGS  8

//+------------------------------------------------------------------+
//| One virtual position, from order to history.                     |
//+------------------------------------------------------------------+
struct SSRVirtualPosition
  {
   long               ticket;
   ENUM_SSR_ORDER     type;
   ENUM_SSR_POS_STATE state;

   double             volume;         // remaining
   double             volume_initial;
   //--- what was ASKED for, kept alongside what happened. A rewind
   //--- past a fill has to put the order back the way it was placed,
   //--- and by then `type` and `open_msc` describe the fill instead.
   double             request_price;  // for pendings
   long               request_msc;    // when the order was placed
   ENUM_SSR_ORDER     request_type;   // as placed, before the fill

   double             open_price;
   long               open_msc;
   double             sl;
   double             tp;
   double             trail_points;   // 0 = no trailing
   double             trail_peak;     // best price seen, for the trail

   double             close_price;
   long               close_msc;
   ENUM_SSR_CLOSE_REASON reason;

   double             commission;
   double             swap;
   double             profit;         // realised, in account currency

   //--- excursions, tracked tick by tick
   double             mae;            // worst adverse move, in price
   double             mfe;            // best favourable move, in price

   //--- THE HONESTY FLAG. True when this outcome rests on an assumed
   //--- order of prices inside a bar rather than on observed ticks.
   bool               ambiguous;

   //--- Swap already fixed by an earlier partial exit, and the instant
   //--- the CURRENT size began accruing. Without these, scaling out of
   //--- a position would retroactively restate the swap on the days it
   //--- was held at full size.
   double             swap_locked;
   long               swap_from_msc;

   //--- every exit, so a rewind can undo the ones that never happened
   SSRTradeLeg        legs[SSR_MAX_TRADE_LEGS];
   int                leg_count;

   //--- Money at risk when the position OPENED.
   //---
   //--- Recorded at entry on purpose: an R measured against the loss
   //--- that actually happened makes every loss exactly -1R, and so
   //--- flatters the discipline of a trader who never used a stop.
   double             risk_at_entry;

   string             tag;
   string             note;

   void               Init(void)
     {
      ticket = 0; type = SSR_ORDER_BUY; state = SSR_POS_PENDING;
      volume = 0.0; volume_initial = 0.0;
      request_price = 0.0; request_msc = SSR_INVALID_TIME;
      request_type = SSR_ORDER_BUY;
      open_price = 0.0; open_msc = SSR_INVALID_TIME;
      sl = 0.0; tp = 0.0; trail_points = 0.0; trail_peak = 0.0;
      close_price = 0.0; close_msc = SSR_INVALID_TIME; reason = SSR_CLOSE_NONE;
      commission = 0.0; swap = 0.0; profit = 0.0;
      swap_locked = 0.0; swap_from_msc = SSR_INVALID_TIME; leg_count = 0;
      mae = 0.0; mfe = 0.0; risk_at_entry = 0.0;
      ambiguous = false;
      tag = ""; note = "";
     }

   //--- R is UNDEFINED without a stop, and callers must check rather
   //--- than average a zero into everyone else's results
   bool               HasR(void)     { return (risk_at_entry > 0.0); }
   double             RMultiple(void)
     { return (risk_at_entry > 0.0 ? (profit + swap) / risk_at_entry : 0.0); }

   bool               IsLong(void)   { return SSRIsLong(type); }
   bool               IsOpen(void)   { return (state == SSR_POS_OPEN); }
   bool               IsClosed(void) { return (state == SSR_POS_CLOSED); }

   long               DurationMsc(void)
     {
      if(open_msc <= 0 || close_msc <= 0)
         return 0;
      return close_msc - open_msc;
     }

   string             ToString(void)
     {
      return StringFormat("#%d %s %.2f @ %.5f -> %.5f  %s%s",
                          (int)ticket, SSROrderName(type), volume,
                          open_price, close_price,
                          SSRCloseReasonName(reason),
                          (ambiguous ? "  [ambiguous]" : ""));
     }
  };

//+------------------------------------------------------------------+
//| Execution assumptions, all declared rather than hidden.          |
//+------------------------------------------------------------------+
struct SSRExecutionModel
  {
   double            commission_per_lot;  // charged per side
   double            slippage_points;     // applied adversely, always
   double            swap_long_per_lot;   // per day
   double            swap_short_per_lot;
   bool              use_real_spread;     // from the tick, or fixed below
   double            fixed_spread_points;

   void              Init(void)
     {
      commission_per_lot  = 0.0;
      slippage_points     = 0.0;
      swap_long_per_lot   = 0.0;
      swap_short_per_lot  = 0.0;
      use_real_spread     = true;
      fixed_spread_points = 0.0;
     }
  };

#endif // SSR_TRADE_TYPES_MQH
//+------------------------------------------------------------------+
