//+------------------------------------------------------------------+
//|                                              SSR_Statistics.mqh  |
//|                    SS Replay - Statistics Engine (L2/Trading)    |
//|                                                                  |
//|  THE RULE THIS FILE EXISTS TO ENFORCE                            |
//|                                                                  |
//|  No metric travels without its data quality.                     |
//|                                                                  |
//|  A profit factor of 2.1 computed from a set of trades, 40% of    |
//|  which were resolved by assuming which of the stop and target     |
//|  came first, is not a profit factor of 2.1. It is a number with  |
//|  a caveat, and the caveat has to travel with it or the number     |
//|  will be quoted alone.                                           |
//|                                                                  |
//|  Likewise R: it is UNDEFINED for a trade taken without a stop.    |
//|  Averaging those in as zero, or measuring R against the loss that |
//|  actually happened, makes every loss exactly -1R and turns a      |
//|  trader with no risk discipline into one with perfect discipline. |
//|  So the average R reports how many trades it could be computed    |
//|  from, and the rest are excluded rather than invented.            |
//+------------------------------------------------------------------+
#ifndef SSR_STATISTICS_MQH
#define SSR_STATISTICS_MQH

#include "../Common/SSR_Types.mqh"
#include "../Common/SSR_Time.mqh"
#include "../Core/SSR_ITickObserver.mqh"
#include "SSR_TradingEngine.mqh"
#include "../Common/SSR_SessionFile.mqh"

//--- equity samples kept for the drawdown curve. One per replay minute
//--- for about three days, which outlasts any single sitting.
#define SSR_EQUITY_SAMPLES        4096
#define SSR_EQUITY_INTERVAL_MSC   60000

//+------------------------------------------------------------------+
struct SSRStatistics
  {
   //--- counts
   int               trades;          // closed
   int               wins;
   int               losses;
   int               breakeven;
   int               open_now;

   //--- money
   double            gross_profit;
   double            gross_loss;      // positive magnitude
   double            net_profit;
   double            commission;
   double            swap;

   //--- ratios
   double            win_rate;        // %
   double            loss_rate;       // %
   double            profit_factor;   // gross_profit / gross_loss
   double            expectancy;      // money per trade
   double            average_win;
   double            average_loss;    // positive magnitude
   double            largest_win;
   double            largest_loss;

   //--- R, over the trades where R is defined at all
   double            average_r;
   double            total_r;
   int               r_trades;        // how many that average came from
   double            expectancy_r;

   //--- risk
   double            max_drawdown;        // money, on the equity curve
   double            max_drawdown_pct;
   double            max_drawdown_closed; // money, on the balance curve only
   int               win_streak;
   int               loss_streak;
   int               stopouts;

   //--- excursions
   double            avg_mae;
   double            avg_mfe;

   //--- DATA QUALITY. Not decoration: these decide whether the numbers
   //--- above may be quoted on their own.
   int               ambiguous_trades;
   double            ambiguous_pct;
   bool              margin_modelled;
   int               trades_without_stop;

   void              Init(void)
     {
      trades = 0; wins = 0; losses = 0; breakeven = 0; open_now = 0;
      gross_profit = 0.0; gross_loss = 0.0; net_profit = 0.0;
      commission = 0.0; swap = 0.0;
      win_rate = 0.0; loss_rate = 0.0; profit_factor = 0.0;
      expectancy = 0.0; average_win = 0.0; average_loss = 0.0;
      largest_win = 0.0; largest_loss = 0.0;
      average_r = 0.0; total_r = 0.0; r_trades = 0; expectancy_r = 0.0;
      max_drawdown = 0.0; max_drawdown_pct = 0.0; max_drawdown_closed = 0.0;
      win_streak = 0; loss_streak = 0; stopouts = 0;
      avg_mae = 0.0; avg_mfe = 0.0;
      ambiguous_trades = 0; ambiguous_pct = 0.0;
      margin_modelled = false; trades_without_stop = 0;
     }

   //+------------------------------------------------------------------+
   //| Can these numbers be read at face value?                         |
   //|                                                                  |
   //| Deliberately strict. Anything above a tenth of the results        |
   //| resting on an assumed tick order is enough to change a           |
   //| conclusion, so it must be said before the conclusion is drawn.   |
   //+------------------------------------------------------------------+
   bool              IsTrustworthy(void)
     { return (trades > 0 && ambiguous_pct <= 10.0); }

   //--- the sentence that must accompany the numbers. Empty when there
   //--- is genuinely nothing to qualify.
   string            Caveat(void)
     {
      if(trades == 0)
         return "no closed trades yet";
      string s = "";
      if(ambiguous_pct > 0.0)
         s += StringFormat("%.0f%% of results assume which of stop and target came first. ",
                           ambiguous_pct);
      if(r_trades < trades)
         s += StringFormat("R covers %d of %d trades - the rest had no stop. ",
                           r_trades, trades);
      if(!margin_modelled)
         s += "Margin is not modelled. ";
      return s;
     }

   string            ToString(void)
     {
      return StringFormat("stats[%d trades  %.1f%% win  PF %.2f  net %.2f  "
                          "DD %.2f (%.1f%%)  avgR %.2f/%d]",
                          trades, win_rate, profit_factor, net_profit,
                          max_drawdown, max_drawdown_pct, average_r, r_trades);
     }
  };

//+------------------------------------------------------------------+
//| Computes the statistics, and samples equity so drawdown reflects |
//| what the trader actually lived through rather than only what     |
//| showed up in the closed-trade record.                            |
//+------------------------------------------------------------------+
class CSSRStatsEngine : public CSSRTickObserver
  {
private:
   CSSRTradingEngine *m_acct;      // not owned

   long              m_eq_msc[SSR_EQUITY_SAMPLES];
   double            m_eq_val[SSR_EQUITY_SAMPLES];
   int               m_eq_count;
   long              m_eq_last_msc;

   void              Sample(const long msc)
     {
      if(m_acct == NULL)
         return;
      if(m_eq_last_msc != SSR_INVALID_TIME &&
         msc - m_eq_last_msc < SSR_EQUITY_INTERVAL_MSC)
         return;

      if(m_eq_count >= SSR_EQUITY_SAMPLES)
        {
         //--- drop the oldest half rather than the whole curve: losing
         //--- every early sample would hide the drawdown that produced
         //--- the peak we are still measuring against
         int keep = SSR_EQUITY_SAMPLES / 2;
         for(int i = 0; i < keep; i++)
           {
            m_eq_msc[i] = m_eq_msc[i + keep];
            m_eq_val[i] = m_eq_val[i + keep];
           }
         m_eq_count = keep;
        }

      m_eq_msc[m_eq_count] = msc;
      m_eq_val[m_eq_count] = m_acct.Equity();
      m_eq_count++;
      m_eq_last_msc = msc;
     }

public:
                     CSSRStatsEngine(void)
     : m_acct(NULL), m_eq_count(0), m_eq_last_msc(SSR_INVALID_TIME) {}

   virtual string    Name(void) override { return "statistics"; }
   void              Attach(CSSRTradingEngine *a) { m_acct = a; }
   int               EquitySamples(void) { return m_eq_count; }

   virtual void      OnSessionStart(const string symbol, const int digits,
                                    const double point, const long start_msc) override
     {
      m_eq_count    = 0;
      m_eq_last_msc = SSR_INVALID_TIME;
     }

   virtual void      OnTicks(const MqlTick &ticks[], const int count) override
     {
      if(count > 0)
         Sample(ticks[count - 1].time_msc);
     }

   virtual void      OnClock(const long now_msc) override { Sample(now_msc); }

   //--- the curve describes a future that was deleted; so must it
   virtual void      OnRewind(const long msc) override
     {
      int keep = 0;
      for(int i = 0; i < m_eq_count; i++)
         if(m_eq_msc[i] <= msc)
           {
            m_eq_msc[keep] = m_eq_msc[i];
            m_eq_val[keep] = m_eq_val[i];
            keep++;
           }
      m_eq_count    = keep;
      m_eq_last_msc = (keep > 0 ? m_eq_msc[keep - 1] : SSR_INVALID_TIME);
     }

   //+------------------------------------------------------------------+
   //| Peak-to-trough on the sampled equity curve. Includes floating    |
   //| loss, because a trade that went far against you before winning   |
   //| was a drawdown you actually sat through.                         |
   //+------------------------------------------------------------------+
   void              EquityDrawdown(double &money, double &pct)
     {
      money = 0.0; pct = 0.0;
      if(m_eq_count < 2)
         return;
      double peak = m_eq_val[0];
      for(int i = 1; i < m_eq_count; i++)
        {
         if(m_eq_val[i] > peak)
            peak = m_eq_val[i];
         double dd = peak - m_eq_val[i];
         if(dd > money)
           {
            money = dd;
            pct   = (peak > 0.0 ? dd / peak * 100.0 : 0.0);
           }
        }
     }

   //+------------------------------------------------------------------+
   void              Compute(SSRStatistics &out)
     {
      out.Init();
      if(m_acct == NULL)
         return;

      out.margin_modelled = m_acct.MarginModelled();
      out.stopouts        = (int)m_acct.Stopouts();
      out.open_now        = m_acct.OpenCount();

      int  streak_w = 0, streak_l = 0;
      double mae_sum = 0.0, mfe_sum = 0.0;
      int    exc_n = 0;

      int total = m_acct.Total();
      for(int i = 0; i < total; i++)
        {
         SSRVirtualPosition p;
         if(!m_acct.At(i, p) || !p.IsClosed())
            continue;

         out.trades++;
         double net = p.profit + p.swap;
         out.commission += p.commission;
         out.swap       += p.swap;

         if(net > 0.0)
           {
            out.wins++;
            out.gross_profit += net;
            if(net > out.largest_win) out.largest_win = net;
            streak_w++; streak_l = 0;
            if(streak_w > out.win_streak) out.win_streak = streak_w;
           }
         else if(net < 0.0)
           {
            out.losses++;
            out.gross_loss += -net;
            if(-net > out.largest_loss) out.largest_loss = -net;
            streak_l++; streak_w = 0;
            if(streak_l > out.loss_streak) out.loss_streak = streak_l;
           }
         else
            out.breakeven++;

         //--- R only where R exists
         if(p.HasR())
           {
            out.total_r += p.RMultiple();
            out.r_trades++;
           }
         else
            out.trades_without_stop++;

         if(p.ambiguous)
            out.ambiguous_trades++;

         mae_sum += p.mae;
         mfe_sum += p.mfe;
         exc_n++;
        }

      if(out.trades == 0)
         return;

      out.net_profit = out.gross_profit - out.gross_loss;
      out.win_rate   = 100.0 * (double)out.wins   / (double)out.trades;
      out.loss_rate  = 100.0 * (double)out.losses / (double)out.trades;
      out.expectancy = out.net_profit / (double)out.trades;

      if(out.wins > 0)   out.average_win  = out.gross_profit / (double)out.wins;
      if(out.losses > 0) out.average_loss = out.gross_loss   / (double)out.losses;

      //--- profit factor is undefined without a loss; reporting it as
      //--- infinity or as the gross profit both mislead, so it stays 0
      //--- and the caller reads trades/losses to know why
      if(out.gross_loss > 0.0)
         out.profit_factor = out.gross_profit / out.gross_loss;

      if(out.r_trades > 0)
        {
         out.average_r    = out.total_r / (double)out.r_trades;
         out.expectancy_r = out.average_r;
        }

      if(exc_n > 0)
        {
         out.avg_mae = mae_sum / (double)exc_n;
         out.avg_mfe = mfe_sum / (double)exc_n;
        }

      out.ambiguous_pct = 100.0 * (double)out.ambiguous_trades / (double)out.trades;

      EquityDrawdown(out.max_drawdown, out.max_drawdown_pct);
      out.max_drawdown_closed = ClosedDrawdown();
     }

   //================================================================
   //  SESSION PERSISTENCE
   //
   //  ONLY THE EQUITY CURVE IS WRITTEN, and that is a deliberate line.
   //
   //  Every other statistic - win rate, profit factor, R, MAE, the
   //  ambiguous percentage - is DERIVED from the trades, and the
   //  trades are already in the file. Storing them too would create a
   //  second source of truth, and the day the two disagree the stored
   //  one wins silently, because nothing recomputes it to check.
   //
   //  The equity curve is the exception because it cannot be derived.
   //  It records what the account was worth minute by minute, floating
   //  losses included - the 130 the trader sat through on a trade that
   //  closed for 100. Recompute it from closed trades and that 130
   //  vanishes, so the restored session would report a smaller
   //  drawdown than the one the trader actually lived.
   //================================================================
   void              SaveInto(CSSRSessionFile &f)
     {
      f.Section("equity");
      f.Comment("the one statistic that cannot be recomputed from the "
                "trades: what the account was worth minute by minute, "
                "floating losses included");
      f.SetInt("samples", m_eq_count);
      f.SetLong("last_msc", m_eq_last_msc);
      for(int i = 0; i < m_eq_count; i++)
         f.Set("e", StringFormat("%I64d%s%.2f", m_eq_msc[i],
                                 SSR_SF_SEP, m_eq_val[i]));
     }

   bool              RestoreFrom(CSSRSessionFile &f)
     {
      m_eq_count    = 0;
      m_eq_last_msc = SSR_INVALID_TIME;
      if(!f.Select("equity"))
         return true;                    // a session saved before any run

      int n = f.Count("e");
      for(int i = 0; i < n && m_eq_count < SSR_EQUITY_SAMPLES; i++)
        {
         string c[];
         if(SSRUnpack(f.GetNth("e", i), c) < 2)
            continue;
         m_eq_msc[m_eq_count] = SSRFieldLong(c, 0);
         m_eq_val[m_eq_count] = SSRFieldDouble(c, 1);
         m_eq_count++;
        }
      //--- from the curve itself, not from the file: if the samples
      //--- were truncated on the way in, the stored value would let
      //--- the next sample be rejected as too soon
      m_eq_last_msc = (m_eq_count > 0 ? m_eq_msc[m_eq_count - 1]
                                      : SSR_INVALID_TIME);
      return true;
     }

   //--- drawdown of the realised balance alone, for comparison with the
   //--- equity figure. A large gap between them means the trader was
   //--- riding losses rather than taking them.
   double            ClosedDrawdown(void)
     {
      if(m_acct == NULL)
         return 0.0;
      double bal = m_acct.InitialBalance();
      double peak = bal, worst = 0.0;
      int total = m_acct.Total();
      for(int i = 0; i < total; i++)
        {
         SSRVirtualPosition p;
         if(!m_acct.At(i, p) || !p.IsClosed())
            continue;
         bal += p.profit + p.swap - p.commission;
         if(bal > peak) peak = bal;
         double dd = peak - bal;
         if(dd > worst) worst = dd;
        }
      return worst;
     }
  };

#endif // SSR_STATISTICS_MQH
//+------------------------------------------------------------------+
