//+------------------------------------------------------------------+
//|                                                   SSR_Review.mqh |
//|              SS Replay - what the session actually measured       |
//|                                                                  |
//|  THE PROBLEM THIS SOLVES                                         |
//|                                                                  |
//|  The engine computes forty-three statistics. About ten are        |
//|  visible on the Stats tab; the rest exist only inside an exported |
//|  HTML file that a trader has to remember to produce, find and     |
//|  open. MAE, MFE, revenge trades, risk dispersion, the spread each |
//|  trade was entered at, and the count of trades placed with NO     |
//|  STOP are the deepest thing this product knows, and a trader      |
//|  closes the session without seeing any of them.                   |
//|                                                                  |
//|  THIS FILE COMPUTES NOTHING.                                     |
//|                                                                  |
//|  It turns an SSRStatistics into rows and sentences and stops      |
//|  there. Every number came from the statistics engine, which is    |
//|  the one place allowed to decide what a session means. A second   |
//|  place that derived even one figure would eventually disagree     |
//|  with the statement, and the statement is what gets sent to a     |
//|  prop firm.                                                       |
//|                                                                  |
//|  AND IT NEVER COACHES.                                           |
//|                                                                  |
//|  An observation states what was counted and stops: "1 of 2 trades |
//|  opened within two minutes of a loss". It does not say that was   |
//|  revenge trading, that it was bad, or what to do instead. The     |
//|  trader knows what happened in that session and this program does |
//|  not - inventing the interpretation is how a measurement tool     |
//|  turns into a horoscope.                                          |
//|                                                                  |
//|  A LINE WITH NO SAMPLES IS ABSENT, NOT ZERO.                     |
//|                                                                  |
//|  "0 revenge trades" out of one trade is not a clean sheet, it is  |
//|  a sample size of one, and printing it as a result is the quiet   |
//|  dishonesty this project exists to avoid.                         |
//+------------------------------------------------------------------+
#ifndef SSR_REVIEW_MQH
#define SSR_REVIEW_MQH

#include "../Trading/SSR_Statistics.mqh"

//+------------------------------------------------------------------+
//| MetaTrader stores OBJPROP_TEXT in full and DRAWS 63 characters.   |
//| Nothing errors; the end of the line simply is not there. On a     |
//| card whose last column is the value, the cut takes the only part  |
//| that mattered.                                                    |
//|                                                                   |
//| 60, not 63, because the card puts a two-character group marker in |
//| front of every row - and the limit applies to the string that     |
//| reaches the object, not to the part this file happened to build.  |
//| The first version of this was 62 and would have lost a digit off  |
//| the longest rows on the chart, where nobody would have read it as |
//| anything but a wrong number.                                      |
//+------------------------------------------------------------------+
#define SSR_REVIEW_ROW_MAX 60
#define SSR_REVIEW_PREFIX  2      // what the card prepends; see above

//+------------------------------------------------------------------+
//| One measure, formatted. `group` lets the card show them in the    |
//| order a person reads them rather than the order they are stored.  |
//+------------------------------------------------------------------+
struct SSRReviewRow
  {
   string            group;
   string            label;
   string            value;
  };

void SSRAddRow(SSRReviewRow &out[], int &i, const string group,
               const string label, const string value)
  {
   if(ArraySize(out) <= i)
      ArrayResize(out, i + 16);
   out[i].group = group;
   out[i].label = label;
   out[i].value = value;
   i++;
  }

//--- the row as one string, padded so the values line up. Tahoma draws
//--- all ten digits on the same advance width, which is the reason the
//--- panel uses it and the reason this can be done with spaces.
string SSRReviewLine(const SSRReviewRow &r)
  {
   string s = r.label;
   while(StringLen(s) < 34)
      s += " ";
   s += r.value;
   if(StringLen(s) > SSR_REVIEW_ROW_MAX)
      s = StringSubstr(s, 0, SSR_REVIEW_ROW_MAX - 1) + "~";
   return s;
  }

//+------------------------------------------------------------------+
//| ALL FORTY-THREE, in nine groups.                                 |
//|                                                                  |
//| Nothing is filtered out for being zero. A measure that is zero    |
//| because nothing happened is a fact about the session; that is     |
//| different from an OBSERVATION, which is a sentence and needs      |
//| samples behind it before it earns the space.                      |
//+------------------------------------------------------------------+
int SSRReviewRows(const SSRStatistics &st, SSRReviewRow &out[])
  {
   int i = 0;

   SSRAddRow(out, i, "Result", "Trades",            IntegerToString(st.trades));
   SSRAddRow(out, i, "Result", "Wins",              IntegerToString(st.wins));
   SSRAddRow(out, i, "Result", "Losses",            IntegerToString(st.losses));
   SSRAddRow(out, i, "Result", "Break even",        IntegerToString(st.breakeven));
   SSRAddRow(out, i, "Result", "Still open",        IntegerToString(st.open_now));
   SSRAddRow(out, i, "Result", "Net profit",        StringFormat("%.2f", st.net_profit));
   SSRAddRow(out, i, "Result", "Gross profit",      StringFormat("%.2f", st.gross_profit));
   SSRAddRow(out, i, "Result", "Gross loss",        StringFormat("%.2f", st.gross_loss));
   SSRAddRow(out, i, "Result", "Commission",        StringFormat("%.2f", st.commission));
   SSRAddRow(out, i, "Result", "Swap",              StringFormat("%.2f", st.swap));

   SSRAddRow(out, i, "Rates",  "Win rate",          StringFormat("%.1f %%", st.win_rate));
   SSRAddRow(out, i, "Rates",  "Loss rate",         StringFormat("%.1f %%", st.loss_rate));
   SSRAddRow(out, i, "Rates",  "Profit factor",     StringFormat("%.2f", st.profit_factor));
   SSRAddRow(out, i, "Rates",  "Expectancy",        StringFormat("%.2f", st.expectancy));
   SSRAddRow(out, i, "Rates",  "Average win",       StringFormat("%.2f", st.average_win));
   SSRAddRow(out, i, "Rates",  "Average loss",      StringFormat("%.2f", st.average_loss));
   SSRAddRow(out, i, "Rates",  "Largest win",       StringFormat("%.2f", st.largest_win));
   SSRAddRow(out, i, "Rates",  "Largest loss",      StringFormat("%.2f", st.largest_loss));

   SSRAddRow(out, i, "R",      "Average R",         StringFormat("%.2f R", st.average_r));
   SSRAddRow(out, i, "R",      "Total R",           StringFormat("%.2f R", st.total_r));
   SSRAddRow(out, i, "R",      "Trades measured in R", IntegerToString(st.r_trades));
   SSRAddRow(out, i, "R",      "Expectancy in R",   StringFormat("%.2f R", st.expectancy_r));

   SSRAddRow(out, i, "Drawdown", "Max drawdown",    StringFormat("%.2f", st.max_drawdown));
   SSRAddRow(out, i, "Drawdown", "Max drawdown %",  StringFormat("%.2f %%", st.max_drawdown_pct));
   SSRAddRow(out, i, "Drawdown", "On closed trades", StringFormat("%.2f", st.max_drawdown_closed));
   SSRAddRow(out, i, "Drawdown", "Recovery factor", StringFormat("%.2f", st.recovery_factor));

   SSRAddRow(out, i, "Streaks", "Longest win streak",  IntegerToString(st.win_streak));
   SSRAddRow(out, i, "Streaks", "Longest loss streak", IntegerToString(st.loss_streak));
   SSRAddRow(out, i, "Streaks", "Stop outs",           IntegerToString(st.stopouts));

   SSRAddRow(out, i, "Excursion", "Average MAE",    StringFormat("%.2f", st.avg_mae));
   SSRAddRow(out, i, "Excursion", "Average MFE",    StringFormat("%.2f", st.avg_mfe));

   SSRAddRow(out, i, "Time",   "Average hold",      StringFormat("%.0f s", st.avg_hold_sec));
   SSRAddRow(out, i, "Time",   "Time in market",    StringFormat("%.1f %%", st.time_in_market_pct));

   SSRAddRow(out, i, "Discipline", "Risk spread",   StringFormat("%.0f %%", st.risk_spread_pct));
   SSRAddRow(out, i, "Discipline", "Risk samples",  IntegerToString(st.risk_samples));
   SSRAddRow(out, i, "Discipline", "Straight back in after a loss",
                                                    IntegerToString(st.revenge_trades));
   SSRAddRow(out, i, "Discipline", "Trades with no stop",
                                                    IntegerToString(st.trades_without_stop));

   SSRAddRow(out, i, "Execution", "Average spread", StringFormat("%.1f pt", st.avg_spread_points));
   SSRAddRow(out, i, "Execution", "Worst spread",   StringFormat("%.1f pt", st.worst_spread_points));
   SSRAddRow(out, i, "Execution", "Spread samples", IntegerToString(st.spread_samples));
   SSRAddRow(out, i, "Execution", "Entered at a wide spread",
                                                    IntegerToString(st.wide_spread_trades));
   SSRAddRow(out, i, "Execution", "Ambiguous bars", IntegerToString(st.ambiguous_trades));
   SSRAddRow(out, i, "Execution", "Ambiguous %",    StringFormat("%.1f %%", st.ambiguous_pct));

   ArrayResize(out, i);
   return i;
  }

//+------------------------------------------------------------------+
//| OBSERVATIONS.                                                    |
//|                                                                  |
//| A sentence costs more attention than a row, so it has to earn     |
//| one: every line below is emitted only when the underlying         |
//| counter has samples behind it AND has something to report.        |
//|                                                                  |
//| No line interprets. "1 of 2 trades opened within two minutes of   |
//| a loss" is a count. Whether that was revenge trading, or a plan   |
//| followed correctly, is something the trader knows and this        |
//| program does not.                                                 |
//+------------------------------------------------------------------+
int SSRReviewObservations(const SSRStatistics &st, string &out[])
  {
   int n = 0;
   ArrayResize(out, 8);

   //--- a session of one or two trades cannot support a statement
   //--- about behaviour, and saying one anyway is the failure mode
   //--- this whole file is written against
   if(st.trades < 3)
     {
      ArrayResize(out, 0);
      return 0;
     }

   if(st.revenge_trades > 0)
      out[n++] = StringFormat("%d of %d trades opened within two minutes "
                              "of a loss.", st.revenge_trades, st.trades);

   if(st.risk_samples >= 3 && st.risk_spread_pct >= 25.0)
      out[n++] = StringFormat("Risk varied %.0f%% across %d trades.",
                              st.risk_spread_pct, st.risk_samples);

   if(st.trades_without_stop > 0)
      out[n++] = StringFormat("%d trade(s) were placed with no stop.",
                              st.trades_without_stop);

   if(st.spread_samples >= 3 && st.wide_spread_trades > 0)
      out[n++] = StringFormat("%d of %d trades were entered at a spread "
                              "wider than this session's average.",
                              st.wide_spread_trades, st.spread_samples);

   if(st.ambiguous_trades > 0)
      out[n++] = StringFormat("%d trade(s) closed on a bar that reached "
                              "both the stop and the target.",
                              st.ambiguous_trades);

   if(st.stopouts > 0)
      out[n++] = StringFormat("%d position(s) were closed by a stop out.",
                              st.stopouts);

   ArrayResize(out, n);
   return n;
  }

#endif // SSR_REVIEW_MQH
//+------------------------------------------------------------------+
