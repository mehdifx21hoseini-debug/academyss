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
//| One virtual position, from order to history.                     |
//+------------------------------------------------------------------+
struct SSRVirtualPosition
  {
   long               ticket;
   ENUM_SSR_ORDER     type;
   ENUM_SSR_POS_STATE state;

   double             volume;         // remaining
   double             volume_initial;
   double             request_price;  // for pendings
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

   string             tag;
   string             note;

   void               Init(void)
     {
      ticket = 0; type = SSR_ORDER_BUY; state = SSR_POS_PENDING;
      volume = 0.0; volume_initial = 0.0;
      request_price = 0.0; open_price = 0.0; open_msc = SSR_INVALID_TIME;
      sl = 0.0; tp = 0.0; trail_points = 0.0; trail_peak = 0.0;
      close_price = 0.0; close_msc = SSR_INVALID_TIME; reason = SSR_CLOSE_NONE;
      commission = 0.0; swap = 0.0; profit = 0.0;
      mae = 0.0; mfe = 0.0;
      ambiguous = false;
      tag = ""; note = "";
     }

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
