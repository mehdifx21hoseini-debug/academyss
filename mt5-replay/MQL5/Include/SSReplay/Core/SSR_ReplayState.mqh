//+------------------------------------------------------------------+
//|                                               SSR_ReplayState.mqh |
//|                                    SS Replay - Replay State (L2) |
//|                                                                  |
//|  Plain data, deliberately. It is copied into snapshots, written  |
//|  to session files and published over IPC, so it must stay free   |
//|  of pointers and of any behaviour that could differ between a    |
//|  live instance and a restored one.                               |
//+------------------------------------------------------------------+
#ifndef SSR_REPLAY_STATE_MQH
#define SSR_REPLAY_STATE_MQH

#include "../Common/SSR_Types.mqh"
#include "../Common/SSR_Time.mqh"

//+------------------------------------------------------------------+
struct SSRReplayState
  {
   //--- identity
   string             symbol;          // source symbol being replayed
   ENUM_TIMEFRAMES    base_timeframe;  // storage base; always M1 in practice

   //--- timeline, epoch milliseconds
   long               start_msc;
   long               current_msc;
   long               end_msc;

   //--- available data bounds, which may be wider than start..end
   long               data_first_msc;
   long               data_last_msc;

   //--- behaviour
   ENUM_SSR_STATE     status;
   long               speed_x100;
   ENUM_SSR_DATA_MODE data_mode;
   ENUM_SSR_FIDELITY  fidelity;

   //--- diagnostics
   ENUM_SSR_ERR       last_error;
   string             last_error_text;
   long               ticks_emitted;
   long               bars_consumed;

   void               Init(void)
     {
      symbol          = "";
      base_timeframe  = PERIOD_M1;
      start_msc       = SSR_INVALID_TIME;
      current_msc     = SSR_INVALID_TIME;
      end_msc         = SSR_INVALID_TIME;
      data_first_msc  = SSR_INVALID_TIME;
      data_last_msc   = SSR_INVALID_TIME;
      status          = SSR_STATE_IDLE;
      speed_x100      = SSR_SPEED_1;
      data_mode       = SSR_DATA_MEMORY;
      fidelity        = SSR_FIDELITY_SYNTHETIC_TICK;
      last_error      = SSR_OK;
      last_error_text = "";
      ticks_emitted   = 0;
      bars_consumed   = 0;
     }

   bool               IsLive(void)
     {
      return (status == SSR_STATE_PLAYING || status == SSR_STATE_PAUSED ||
              status == SSR_STATE_READY   || status == SSR_STATE_COMPLETED);
     }

   double             Progress(void)
     {
      if(start_msc <= 0 || end_msc <= start_msc)
         return 0.0;
      long span = end_msc - start_msc;
      double p = (double)(current_msc - start_msc) / (double)span;
      if(p < 0.0) return 0.0;
      if(p > 1.0) return 1.0;
      return p;
     }

   string             ToString(void)
     {
      return StringFormat("%s | %s | %s | %s | %s | %.1f%%",
                          symbol,
                          SSRStateName(status),
                          SSRFormatMsc(current_msc),
                          SSRSpeedName(speed_x100),
                          SSRFidelityName(fidelity),
                          Progress() * 100.0);
     }
  };

//+------------------------------------------------------------------+
//| State machine - the only place transitions are decided.          |
//|                                                                  |
//| Written as an explicit table rather than scattered if-statements |
//| so an illegal transition is impossible to introduce by accident  |
//| in a later phase.                                                |
//+------------------------------------------------------------------+
bool SSRCanTransition(const ENUM_SSR_STATE from, const ENUM_SSR_STATE to)
  {
   if(from == to)
      return true;

   //--- an explicit Reset is always permitted, including out of ERROR
   if(to == SSR_STATE_RESETTING)
      return true;

   //--- any state may fail
   if(to == SSR_STATE_ERROR)
      return true;

   switch(from)
     {
      case SSR_STATE_IDLE:
         return (to == SSR_STATE_LOADING);

      case SSR_STATE_LOADING:
         return (to == SSR_STATE_READY || to == SSR_STATE_IDLE);

      case SSR_STATE_READY:
         return (to == SSR_STATE_PLAYING || to == SSR_STATE_PAUSED ||
                 to == SSR_STATE_LOADING || to == SSR_STATE_COMPLETED);

      case SSR_STATE_PLAYING:
         return (to == SSR_STATE_PAUSED || to == SSR_STATE_COMPLETED ||
                 to == SSR_STATE_READY);

      case SSR_STATE_PAUSED:
         return (to == SSR_STATE_PLAYING || to == SSR_STATE_READY ||
                 to == SSR_STATE_COMPLETED || to == SSR_STATE_LOADING);

      case SSR_STATE_RESETTING:
         return (to == SSR_STATE_IDLE || to == SSR_STATE_READY ||
                 to == SSR_STATE_LOADING);

      case SSR_STATE_COMPLETED:
         //--- stepping backwards or seeking revives a finished replay
         return (to == SSR_STATE_PAUSED || to == SSR_STATE_READY ||
                 to == SSR_STATE_LOADING);

      case SSR_STATE_ERROR:
         return false;   // only RESETTING, handled above
     }
   return false;
  }

#endif // SSR_REPLAY_STATE_MQH
//+------------------------------------------------------------------+
