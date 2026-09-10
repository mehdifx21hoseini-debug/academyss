//+------------------------------------------------------------------+
//|                                                  SSR_Strings.mqh |
//|                        SS Replay - every word the user reads      |
//|                                                                  |
//|  AN INDEX, NOT A STRING KEY.                                     |
//|                                                                  |
//|  The obvious design is T("panel.play"). It has two costs this    |
//|  product cannot pay.                                             |
//|                                                                  |
//|  The first is speed. The panel repaints at 10 Hz and draws about |
//|  sixty labels; a string key means sixty lookups a frame, each     |
//|  comparing against a table of hundreds. Phase 11's budget does    |
//|  not have room for that, and a localisation layer that makes the  |
//|  panel stutter is one somebody will rip out.                      |
//|                                                                  |
//|  The second is worse. A mistyped string key compiles, runs, and   |
//|  puts "panel.paly" on the chart in front of a user. A mistyped    |
//|  ENUM does not compile. That is the entire class of "the button   |
//|  says its own key name" bugs, removed rather than audited.        |
//|                                                                  |
//|  So T() takes an index and reads one array slot.                  |
//|                                                                  |
//|  ENGLISH IS COMPILED IN AND CAN NEVER BE MISSING.                |
//|                                                                  |
//|  A translation is an OVERRIDE loaded from a file: it replaces the |
//|  lines it has and leaves the rest in English. A translator who    |
//|  has done sixty of two hundred strings ships something usable,    |
//|  and a file that is missing, empty or corrupt costs nothing at    |
//|  all. There is no state in which this panel draws blank labels.   |
//|                                                                  |
//|  WHAT IS NOT HERE: every Print, every PrintFormat, every flight   |
//|  recorder line, every object name, every file name. A log in a    |
//|  language the person reading the bug report cannot read is not a  |
//|  localised log, it is a lost diagnostic.                          |
//+------------------------------------------------------------------+
#ifndef SSR_STRINGS_MQH
#define SSR_STRINGS_MQH

//+------------------------------------------------------------------+
//| THE INDEX. Grouped by where the user meets the words, because    |
//| that is the order a translator works in - a list sorted by key   |
//| makes them translate "Cancel" eleven times without ever knowing  |
//| which screen any of them is on.                                  |
//+------------------------------------------------------------------+
enum ENUM_SSR_STR
  {
   //--- transport and the panel's own furniture
   SSR_S_PLAY = 0,
   SSR_S_PAUSE,
   SSR_S_RESET,
   SSR_S_RESET_ASK,
   SSR_S_SPEED,
   SSR_S_FOLLOW,
   SSR_S_FOLLOW_N,
   SSR_S_LINES_ON,
   SSR_S_LINES_OFF,
   SSR_S_BOOKMARK,
   SSR_S_JUMP,
   SSR_S_SESSIONS,
   SSR_S_FIDELITY,

   //--- the tabs
   SSR_S_TAB_TRADE,
   SSR_S_TAB_POSITIONS,
   SSR_S_TAB_POSITIONS_N,
   SSR_S_TAB_STATS,
   SSR_S_TAB_SESSION,
   SSR_S_TAB_PROP,
   SSR_S_TAB_PROP_OK,
   SSR_S_TAB_PROP_FAIL,

   //--- the trade sheet
   SSR_S_GRP_RISK,
   SSR_S_RISK_PER_TRADE,
   SSR_S_SETUP,
   SSR_S_GRP_STOP_TARGET,
   SSR_S_PLACE_LINES,
   SSR_S_THEN_DRAG,
   SSR_S_WAITING_PRICE,
   SSR_S_LONG_SETUP,
   SSR_S_SHORT_SETUP,
   SSR_S_BUY,
   SSR_S_SELL,

   //--- the positions sheet
   SSR_S_GRP_OPEN_POSITIONS,
   SSR_S_NOTHING_OPEN,
   SSR_S_WAITING,
   SSR_S_NO_STOP,
   SSR_S_NOT_SHOWN,
   SSR_S_ROW_HINT,
   SSR_S_BREAK_EVEN_ALL,
   SSR_S_CLOSE_ALL,
   SSR_S_TRAILING_STOP,
   SSR_S_OFF,

   //--- the stats sheet
   SSR_S_GRP_ACCOUNT,
   SSR_S_BALANCE,
   SSR_S_EQUITY,
   SSR_S_FLOATING,
   SSR_S_GRP_THIS_RUN,
   SSR_S_BARS,
   SSR_S_TICKS,
   SSR_S_REJECTED,
   SSR_S_SAVE_STATEMENT,
   SSR_S_EVAL_SEE_PROP_TAB,

   //--- the prop sheet
   SSR_S_PROFIT_TARGET,
   SSR_S_DAILY_LOSS,
   SSR_S_NO_DAILY_LIMIT,
   SSR_S_DRAWDOWN,
   SSR_S_DRAWDOWN_TRAILING,
   SSR_S_DRAWDOWN_STATIC,
   SSR_S_NO_DRAWDOWN_LIMIT,
   SSR_S_TRADING_DAYS,
   SSR_S_DAYS_NEEDED,
   SSR_S_NO_MINIMUM,
   SSR_S_USED_FLOOR,
   SSR_S_DAY_OF_ELAPSED,
   SSR_S_RESET_EVALUATION,
   SSR_S_NO_TARGET,

   //--- the session sheet
   SSR_S_GRP_SESSION,
   SSR_S_BOOKMARKS,
   SSR_S_STREAMS,
   SSR_S_CHARTS,
   SSR_S_CHARTS_CLEAN,
   SSR_S_GRP_KEYBOARD,

   //--- the review card
   SSR_S_SESSION_REVIEW,
   SSR_S_TRADES_N,
   SSR_S_WON_PCT,
   SSR_S_MAX_DD,
   SSR_S_NET,
   SSR_S_MEASURED_RANGE,
   SSR_S_WHAT_WAS_COUNTED,
   SSR_S_EXPORT_FULL_STATEMENT,
   SSR_S_UP,
   SSR_S_DOWN,
   SSR_S_CLOSE,

   //--- the reveal card
   SSR_S_SESSION_COMPLETE,
   SSR_S_STILL_HIDDEN,
   SSR_S_REVEAL_EXPLAIN_1,
   SSR_S_REVEAL_EXPLAIN_2,
   SSR_S_REVEAL_BUTTON,
   SSR_S_BLIND,
   SSR_S_PROP,

   //--- the status strip
   SSR_S_BAL,
   SSR_S_FLOAT,
   SSR_S_OPEN,
   SSR_S_SPREAD,
   SSR_S_TOO_NARROW,
   SSR_S_TALL_NEEDS,

   //--- the command palette
   SSR_S_PAL_TITLE,
   SSR_S_PAL_HINT,
   SSR_S_PAL_NOTHING,
   SSR_S_PAL_OF,

   //--- the trade sheet's second half
   SSR_S_STOP_ROW,
   SSR_S_TARGET_ROW,
   SSR_S_LOT,
   SSR_S_NO_SIZE,
   SSR_S_PLACE_ORDER,
   SSR_S_OPEN_ORDER,
   SSR_S_LONG,
   SSR_S_SHORT,
   SSR_S_CANNOT_PLACE,
   SSR_S_OPEN_NO_SIZE,
   SSR_S_FLIP,
   SSR_S_AT_MARKET,
   SSR_S_ENTRY_LINE,
   SSR_S_REMOVE,
   SSR_S_BUY_BTN,
   SSR_S_SELL_BTN,
   SSR_S_PT,
   SSR_S_SPREAD_SHORT,
   SSR_S_N_OPEN,

   //--- the session sheet's keyboard hints
   SSR_S_KEYS_1,
   SSR_S_KEYS_2,
   SSR_S_KEYS_3,
   SSR_S_KEYS_4,

   //--- the key card
   SSR_S_KEYCARD_TITLE,
   SSR_S_KEYCARD_CLOSE,
   SSR_S_ALL_VIRTUAL,

   SSR_S_REJECTED_GUARD,
   SSR_S_STREAMS_SKEW,

   //--- the range dialog
   SSR_S_RD_TITLE,
   SSR_S_RD_START,
   SSR_S_RD_CONTEXT,
   SSR_S_RD_BARS,
   SSR_S_RD_COST,
   SSR_S_RD_NO_HISTORY,
   SSR_S_RD_LOAD_MORE,

   //--- the session dialog
   SSR_S_SD_TITLE,
   SSR_S_SD_OVERWRITE,
   SSR_S_SD_EXISTS,
   SSR_S_SD_NO_UNDO,
   SSR_S_SD_REPLACE,
   SSR_S_SD_KEEP,
   SSR_S_SD_NONE_YET,
   SSR_S_SD_HOW_1,
   SSR_S_SD_HOW_2,
   SSR_S_SD_LOAD,
   SSR_S_SD_DELETE,

   //--- the setup wizard
   SSR_S_SU_NEW_REPLAY,
   SSR_S_SU_SAME_AS_LAST,
   SSR_S_SU_SUMMARY,
   SSR_S_SU_CONTINUE,
   SSR_S_SU_CONTINUE_WHY,
   SSR_S_SU_RANDOM,
   SSR_S_SU_RANDOM_WHY,
   SSR_S_SU_CUSTOMISE,
   SSR_S_SU_SETTINGS,
   SSR_S_SU_MODE,
   SSR_S_SU_WHERE,
   SSR_S_SU_STEP,
   SSR_S_SU_ACCOUNT,
   SSR_S_SU_REPLAY,
   SSR_S_SU_EVALUATION,
   SSR_S_SU_SESSION,
   SSR_S_SU_NEXT_MODE,
   SSR_S_SU_NEXT_START,
   SSR_S_SU_BACK,
   SSR_S_SU_YOU_CHOSE,
   SSR_S_SU_SEED,
   SSR_S_SU_ORANGE_LINE,
   SSR_S_SU_BRING_LINE,
   SSR_S_SU_DRAG_LINE,
   SSR_S_SU_START_HERE,

   //--- the first-run card
   SSR_S_FIRSTRUN_TITLE,
   SSR_S_FIRSTRUN_1,
   SSR_S_FIRSTRUN_2,
   SSR_S_FIRSTRUN_3,
   SSR_S_FIRSTRUN_4,

   SSR_S_COUNT                     // must stay last
  };

//+------------------------------------------------------------------+
//| One entry. `name` is what a translation file writes on the left  |
//| of a line, and it is the ONLY stable public identifier: the      |
//| numeric value of the enum changes the moment somebody inserts a  |
//| string in the middle, and a translation file that referred to    |
//| numbers would silently shift every line it holds.                |
//+------------------------------------------------------------------+
struct SSRStringEntry
  {
   string            name;
   string            text;
  };

SSRStringEntry g_ssr_str[];
bool           g_ssr_str_ready = false;
string         g_ssr_lang      = "en";
int            g_ssr_overrides = 0;

void SSRAddString(SSRStringEntry &out[], int &i, const ENUM_SSR_STR id,
                  const string name, const string text)
  {
   //--- indexed by the ENUM, not by the order of these calls. A table
   //--- written in a different order from the enum would otherwise
   //--- compile, run, and put the wrong word on every button.
   int at = (int)id;
   if(at < 0 || at >= SSR_S_COUNT)
      return;
   if(ArraySize(out) < SSR_S_COUNT)
      ArrayResize(out, SSR_S_COUNT);
   out[at].name = name;
   out[at].text = text;
   i++;
  }

//+------------------------------------------------------------------+
//| THE ENGLISH CATALOGUE. Compiled in, so it cannot be missing.     |
//+------------------------------------------------------------------+
int SSRStringsEnglish(SSRStringEntry &out[])
  {
   ArrayResize(out, SSR_S_COUNT);
   for(int i = 0; i < SSR_S_COUNT; i++)
     { out[i].name = ""; out[i].text = ""; }
   int n = 0;

   SSRAddString(out, n, SSR_S_PLAY,        "play",          "Play");
   SSRAddString(out, n, SSR_S_PAUSE,       "pause",         "Pause");
   SSRAddString(out, n, SSR_S_RESET,       "reset",         "Reset");
   SSRAddString(out, n, SSR_S_RESET_ASK,   "reset.ask",     "Reset?");
   SSRAddString(out, n, SSR_S_SPEED,       "speed",         "Speed");
   SSRAddString(out, n, SSR_S_FOLLOW,      "follow",        "Follow  F");
   SSRAddString(out, n, SSR_S_FOLLOW_N,    "follow.n",      "Follow %d  F");
   SSRAddString(out, n, SSR_S_LINES_ON,    "lines.on",      "Lines on  L");
   SSRAddString(out, n, SSR_S_LINES_OFF,   "lines.off",     "SL / TP  L");
   SSRAddString(out, n, SSR_S_BOOKMARK,    "bookmark",      "Bookmark  B");
   SSRAddString(out, n, SSR_S_JUMP,        "jump",          "Jump...  J");
   SSRAddString(out, n, SSR_S_SESSIONS,    "sessions",      "Sessions...  S");
   SSRAddString(out, n, SSR_S_FIDELITY,    "fidelity",      "Fidelity  D");

   SSRAddString(out, n, SSR_S_TAB_TRADE,       "tab.trade",     "Trade");
   SSRAddString(out, n, SSR_S_TAB_POSITIONS,   "tab.positions", "Positions");
   SSRAddString(out, n, SSR_S_TAB_POSITIONS_N, "tab.positions.n", "Positions %d");
   SSRAddString(out, n, SSR_S_TAB_STATS,       "tab.stats",     "Stats");
   SSRAddString(out, n, SSR_S_TAB_SESSION,     "tab.session",   "Session");
   SSRAddString(out, n, SSR_S_TAB_PROP,        "tab.prop",      "Prop");
   SSRAddString(out, n, SSR_S_TAB_PROP_OK,     "tab.prop.ok",   "Prop OK");
   SSRAddString(out, n, SSR_S_TAB_PROP_FAIL,   "tab.prop.fail", "Prop !");

   SSRAddString(out, n, SSR_S_GRP_RISK,        "grp.risk",      "Risk");
   SSRAddString(out, n, SSR_S_RISK_PER_TRADE,  "risk.per.trade","Risk per trade");
   SSRAddString(out, n, SSR_S_SETUP,           "setup",         "Setup");
   SSRAddString(out, n, SSR_S_GRP_STOP_TARGET, "grp.stop.target","Stop & target");
   SSRAddString(out, n, SSR_S_PLACE_LINES,     "place.lines",
                "Place SL / TP lines on the chart");
   //--- 63, not 64. This shipped at 64 and MetaTrader has been cutting
   //--- the last character off it on every chart since - silently, and
   //--- mid-word, which reads as a rendering fault rather than a limit.
   SSRAddString(out, n, SSR_S_THEN_DRAG,       "then.drag",
                "Then drag them. Buy / Sell open with no stop until you do.");
   SSRAddString(out, n, SSR_S_WAITING_PRICE,   "waiting.price",
                "Waiting for the first price.");
   SSRAddString(out, n, SSR_S_LONG_SETUP,      "long.setup",
                "LONG setup - stop below, target above");
   SSRAddString(out, n, SSR_S_SHORT_SETUP,     "short.setup",
                "SHORT setup - stop above, target below");
   SSRAddString(out, n, SSR_S_BUY,             "buy",           "BUY");
   SSRAddString(out, n, SSR_S_SELL,            "sell",          "SELL");

   SSRAddString(out, n, SSR_S_GRP_OPEN_POSITIONS, "grp.open.positions",
                "Open positions");
   SSRAddString(out, n, SSR_S_NOTHING_OPEN,    "nothing.open",
                "Nothing open. Place the lines (L), drag the stop, press Open.");
   SSRAddString(out, n, SSR_S_WAITING,         "waiting",       "waiting");
   SSRAddString(out, n, SSR_S_NO_STOP,         "no.stop",       "  no stop");
   SSRAddString(out, n, SSR_S_NOT_SHOWN,       "not.shown",     "+%d not shown");
   SSRAddString(out, n, SSR_S_ROW_HINT,        "row.hint",
                "H halves   B stop to entry   X closes");
   SSRAddString(out, n, SSR_S_BREAK_EVEN_ALL,  "break.even.all","Break-even all");
   SSRAddString(out, n, SSR_S_CLOSE_ALL,       "close.all",     "Close all");
   SSRAddString(out, n, SSR_S_TRAILING_STOP,   "trailing.stop", "Trailing stop   %s");
   SSRAddString(out, n, SSR_S_OFF,             "off",           "off");

   SSRAddString(out, n, SSR_S_GRP_ACCOUNT,     "grp.account",   "Account");
   SSRAddString(out, n, SSR_S_BALANCE,         "balance",       "Balance");
   SSRAddString(out, n, SSR_S_EQUITY,          "equity",        "Equity");
   SSRAddString(out, n, SSR_S_FLOATING,        "floating",      "Floating");
   SSRAddString(out, n, SSR_S_GRP_THIS_RUN,    "grp.this.run",  "This run");
   SSRAddString(out, n, SSR_S_BARS,            "bars",          "Bars");
   SSRAddString(out, n, SSR_S_TICKS,           "ticks",         "Ticks");
   SSRAddString(out, n, SSR_S_REJECTED,        "rejected",      "Rejected");
   SSRAddString(out, n, SSR_S_SAVE_STATEMENT,  "save.statement","Save HTML statement");
   SSRAddString(out, n, SSR_S_EVAL_SEE_PROP_TAB, "eval.see.prop.tab",
                "Evaluation  ->  the Prop tab");

   SSRAddString(out, n, SSR_S_PROFIT_TARGET,   "profit.target", "Profit target");
   SSRAddString(out, n, SSR_S_DAILY_LOSS,      "daily.loss",    "Daily loss");
   SSRAddString(out, n, SSR_S_NO_DAILY_LIMIT,  "no.daily.limit","no daily limit");
   SSRAddString(out, n, SSR_S_DRAWDOWN,        "drawdown",      "Drawdown");
   SSRAddString(out, n, SSR_S_DRAWDOWN_TRAILING, "drawdown.trailing",
                "Drawdown (trailing)");
   SSRAddString(out, n, SSR_S_DRAWDOWN_STATIC, "drawdown.static",
                "Drawdown (static)");
   SSRAddString(out, n, SSR_S_NO_DRAWDOWN_LIMIT, "no.drawdown.limit",
                "no drawdown limit");
   SSRAddString(out, n, SSR_S_TRADING_DAYS,    "trading.days",  "Trading days");
   SSRAddString(out, n, SSR_S_DAYS_NEEDED,     "days.needed",   "%d of %d needed");
   SSRAddString(out, n, SSR_S_NO_MINIMUM,      "no.minimum",    "%d  (no minimum)");
   SSRAddString(out, n, SSR_S_USED_FLOOR,      "used.floor",    "%d%% used   floor %s");
   SSRAddString(out, n, SSR_S_DAY_OF_ELAPSED,  "day.of.elapsed","Day %d of %d elapsed");
   SSRAddString(out, n, SSR_S_RESET_EVALUATION,"reset.evaluation","Reset evaluation");
   SSRAddString(out, n, SSR_S_NO_TARGET,       "no.target",     "%+.2f%%   (no target)");

   SSRAddString(out, n, SSR_S_GRP_SESSION,     "grp.session",   "Session");
   SSRAddString(out, n, SSR_S_BOOKMARKS,       "bookmarks",     "Bookmarks");
   SSRAddString(out, n, SSR_S_STREAMS,         "streams",       "Streams");
   SSRAddString(out, n, SSR_S_CHARTS,          "charts",        "Charts");
   SSRAddString(out, n, SSR_S_CHARTS_CLEAN,    "charts.clean",  "clean");
   SSRAddString(out, n, SSR_S_GRP_KEYBOARD,    "grp.keyboard",  "Keyboard");

   SSRAddString(out, n, SSR_S_SESSION_REVIEW,  "session.review","SESSION REVIEW");
   SSRAddString(out, n, SSR_S_TRADES_N,        "trades.n",      "%d trades");
   SSRAddString(out, n, SSR_S_WON_PCT,         "won.pct",       "%.0f%% won");
   SSRAddString(out, n, SSR_S_MAX_DD,          "max.dd",        "max DD %.2f");
   SSRAddString(out, n, SSR_S_NET,             "net",           "net %.2f");
   SSRAddString(out, n, SSR_S_MEASURED_RANGE,  "measured.range","%d - %d of %d measured");
   SSRAddString(out, n, SSR_S_WHAT_WAS_COUNTED,"what.was.counted","WHAT WAS COUNTED");
   SSRAddString(out, n, SSR_S_EXPORT_FULL_STATEMENT, "export.full.statement",
                "Export the full statement");
   SSRAddString(out, n, SSR_S_UP,              "up",            "Up");
   SSRAddString(out, n, SSR_S_DOWN,            "down",          "Down");
   SSRAddString(out, n, SSR_S_CLOSE,           "close",         "Close");

   SSRAddString(out, n, SSR_S_SESSION_COMPLETE,"session.complete","SESSION COMPLETE");
   SSRAddString(out, n, SSR_S_STILL_HIDDEN,    "still.hidden",
                "The market is still hidden.");
   SSRAddString(out, n, SSR_S_REVEAL_EXPLAIN_1,"reveal.explain.1",
                "Revealing puts the instrument, the dates and the price");
   SSRAddString(out, n, SSR_S_REVEAL_EXPLAIN_2,"reveal.explain.2",
                "scale back exactly as they were before this session.");
   SSRAddString(out, n, SSR_S_REVEAL_BUTTON,   "reveal.button", "REVEAL THE MARKET");
   SSRAddString(out, n, SSR_S_BLIND,           "blind",         "BLIND");
   SSRAddString(out, n, SSR_S_PROP,            "prop",          "PROP");

   SSRAddString(out, n, SSR_S_BAL,             "bal",           "Bal %s");
   SSRAddString(out, n, SSR_S_FLOAT,           "float",         "Float %s");
   SSRAddString(out, n, SSR_S_OPEN,            "open",          "Open %d");
   SSRAddString(out, n, SSR_S_SPREAD,          "spread",        "Spread %.1f");
   SSRAddString(out, n, SSR_S_TOO_NARROW,      "too.narrow",
                "chart is %d px, panel needs %d - controls are off the edge");
   SSRAddString(out, n, SSR_S_TALL_NEEDS,      "tall.needs",
                "tall panel needs %d px, chart is %d");

   SSRAddString(out, n, SSR_S_PAL_TITLE,       "pal.title",     "RUN A COMMAND");
   SSRAddString(out, n, SSR_S_PAL_HINT,        "pal.hint",
                "Enter runs  ·  Up / Down chooses  ·  Esc closes");
   SSRAddString(out, n, SSR_S_PAL_NOTHING,     "pal.nothing",   "nothing matches");
   SSRAddString(out, n, SSR_S_PAL_OF,          "pal.of",        "  ·  %d of %d");

   SSRAddString(out, n, SSR_S_STOP_ROW,        "stop.row",      "Stop      %s      %s");
   SSRAddString(out, n, SSR_S_TARGET_ROW,      "target.row",    "Target    %s      %s");
   SSRAddString(out, n, SSR_S_LOT,             "lot",           "%.2f lot");
   SSRAddString(out, n, SSR_S_NO_SIZE,         "no.size",       "no size");
   SSRAddString(out, n, SSR_S_PLACE_ORDER,     "place.order",   "Place %s  %.2f lot");
   SSRAddString(out, n, SSR_S_OPEN_ORDER,      "open.order",    "Open %s  %.2f lot");
   SSRAddString(out, n, SSR_S_LONG,            "long",          "LONG");
   SSRAddString(out, n, SSR_S_SHORT,           "short",         "SHORT");
   SSRAddString(out, n, SSR_S_CANNOT_PLACE,    "cannot.place",
                "Cannot place this order yet");
   SSRAddString(out, n, SSR_S_OPEN_NO_SIZE,    "open.no.size",
                "Open - no size at this stop");
   SSRAddString(out, n, SSR_S_FLIP,            "flip",          "Flip  X");
   SSRAddString(out, n, SSR_S_AT_MARKET,       "at.market",     "At market");
   SSRAddString(out, n, SSR_S_ENTRY_LINE,      "entry.line",    "Entry line");
   SSRAddString(out, n, SSR_S_REMOVE,          "remove",        "Remove");
   SSRAddString(out, n, SSR_S_BUY_BTN,         "buy.btn",       "Buy  %s");
   SSRAddString(out, n, SSR_S_SELL_BTN,        "sell.btn",      "Sell  %s");
   SSRAddString(out, n, SSR_S_PT,              "pt",            "%.0f pt");
   SSRAddString(out, n, SSR_S_SPREAD_SHORT,    "spread.short",  "sp %.1f");
   SSRAddString(out, n, SSR_S_N_OPEN,          "n.open",        "%d open");

   SSRAddString(out, n, SSR_S_KEYS_1, "keys.1",
                "Space play/pause    < > step    PgUp/PgDn x10");
   SSRAddString(out, n, SSR_S_KEYS_2, "keys.2",
                "+ - speed    R reset    J jump    B bookmark");
   SSRAddString(out, n, SSR_S_KEYS_3, "keys.3",
                "S sessions   F follow   D fidelity   L lines   X flip");
   SSRAddString(out, n, SSR_S_KEYS_4, "keys.4",
                "caption:  [] corner    -  collapse    X  close");

   SSRAddString(out, n, SSR_S_KEYCARD_TITLE,   "keycard.title", "KEYS");
   SSRAddString(out, n, SSR_S_KEYCARD_CLOSE,   "keycard.close", "H closes this again");
   SSRAddString(out, n, SSR_S_ALL_VIRTUAL,     "all.virtual",
                "Every trade here is virtual. Nothing reaches a broker.");

   SSRAddString(out, n, SSR_S_REJECTED_GUARD,  "rejected.guard",
                "%-12s %d      guard %d");
   SSRAddString(out, n, SSR_S_STREAMS_SKEW,    "streams.skew",
                "%-12s %d      skew %d ms");

   SSRAddString(out, n, SSR_S_RD_TITLE,     "rd.title",     "NEW SESSION");
   SSRAddString(out, n, SSR_S_RD_START,     "rd.start",     "START");
   SSRAddString(out, n, SSR_S_RD_CONTEXT,   "rd.context",   "CONTEXT");
   SSRAddString(out, n, SSR_S_RD_BARS,      "rd.bars",
                "warmup %d bars  +  replay %d bars");
   SSRAddString(out, n, SSR_S_RD_COST,      "rd.cost",      "~%.0fs to load,  %.1f MB");
   SSRAddString(out, n, SSR_S_RD_NO_HISTORY,"rd.no.history","not enough history");
   SSRAddString(out, n, SSR_S_RD_LOAD_MORE, "rd.load.more", "LOAD MORE");

   SSRAddString(out, n, SSR_S_SD_TITLE,     "sd.title",     "SESSIONS");
   SSRAddString(out, n, SSR_S_SD_OVERWRITE, "sd.overwrite", "OVERWRITE SESSION?");
   SSRAddString(out, n, SSR_S_SD_EXISTS,    "sd.exists",    "\" already exists.");
   SSRAddString(out, n, SSR_S_SD_NO_UNDO,   "sd.no.undo",
                "Saving replaces it. There is no undo on disk.");
   SSRAddString(out, n, SSR_S_SD_REPLACE,   "sd.replace",   "REPLACE IT");
   SSRAddString(out, n, SSR_S_SD_KEEP,      "sd.keep",      "KEEP IT");
   SSRAddString(out, n, SSR_S_SD_NONE_YET,  "sd.none.yet",  "No saved sessions yet.");
   SSRAddString(out, n, SSR_S_SD_HOW_1,     "sd.how.1",
                "Set InpSession=\"a name\" on the EA and one is saved");
   SSRAddString(out, n, SSR_S_SD_HOW_2,     "sd.how.2",
                "when you remove it - trades, clock and all.");
   SSRAddString(out, n, SSR_S_SD_LOAD,      "sd.load",      "LOAD");
   SSRAddString(out, n, SSR_S_SD_DELETE,    "sd.delete",    "DELETE");

   SSRAddString(out, n, SSR_S_SU_NEW_REPLAY,   "su.new.replay",   "NEW REPLAY");
   SSRAddString(out, n, SSR_S_SU_SAME_AS_LAST, "su.same.as.last", "Same as last time");
   SSRAddString(out, n, SSR_S_SU_SUMMARY,      "su.summary",
                "%s  ·  %s  ·  %s  ·  %.2f%% risk");
   SSRAddString(out, n, SSR_S_SU_CONTINUE,     "su.continue",     "Continue \"");
   SSRAddString(out, n, SSR_S_SU_CONTINUE_WHY, "su.continue.why",
                "picks up where that session was left");
   SSRAddString(out, n, SSR_S_SU_RANDOM,       "su.random",       "Random session");
   SSRAddString(out, n, SSR_S_SU_RANDOM_WHY,   "su.random.why",
                "a start you have not seen, with a seed you can share");
   SSRAddString(out, n, SSR_S_SU_CUSTOMISE,    "su.customise",    "Customise...");
   SSRAddString(out, n, SSR_S_SU_SETTINGS,     "su.settings",  "SS REPLAY  -  SETTINGS");
   SSRAddString(out, n, SSR_S_SU_MODE,         "su.mode",      "SS REPLAY  -  MODE");
   SSRAddString(out, n, SSR_S_SU_WHERE,        "su.where",
                "SS REPLAY  -  WHERE TO START");
   SSRAddString(out, n, SSR_S_SU_STEP,         "su.step",         "step %d of 3");
   SSRAddString(out, n, SSR_S_SU_ACCOUNT,      "su.account",      "ACCOUNT");
   SSRAddString(out, n, SSR_S_SU_REPLAY,       "su.replay",       "REPLAY");
   SSRAddString(out, n, SSR_S_SU_EVALUATION,   "su.evaluation",   "EVALUATION");
   SSRAddString(out, n, SSR_S_SU_SESSION,      "su.session",      "SESSION");
   SSRAddString(out, n, SSR_S_SU_NEXT_MODE,    "su.next.mode",
                "Next  -  choose the kind of practice");
   SSRAddString(out, n, SSR_S_SU_NEXT_START,   "su.next.start",
                "Next  -  choose where to start");
   SSRAddString(out, n, SSR_S_SU_BACK,         "su.back",         "Back");
   SSRAddString(out, n, SSR_S_SU_YOU_CHOSE,    "su.you.chose",    "YOU CHOSE");
   SSRAddString(out, n, SSR_S_SU_SEED,         "su.seed",
                "SEED  -  the same seed replays the same session");
   SSRAddString(out, n, SSR_S_SU_ORANGE_LINE,  "su.orange.line",
                "THE REPLAY BEGINS AT THE ORANGE LINE");
   SSRAddString(out, n, SSR_S_SU_BRING_LINE,   "su.bring.line",
                "Bring the line to this view");
   SSRAddString(out, n, SSR_S_SU_DRAG_LINE,    "su.drag.line",    "Drag the orange line");
   SSRAddString(out, n, SSR_S_SU_START_HERE,   "su.start.here",   "START REPLAY HERE");

   SSRAddString(out, n, SSR_S_FIRSTRUN_TITLE,  "firstrun.title",
                "SS REPLAY  -  WHAT NOW?");
   SSRAddString(out, n, SSR_S_FIRSTRUN_1,      "firstrun.1",
                "Playing. SPACE pauses, arrows step one candle at a time.");
   SSRAddString(out, n, SSR_S_FIRSTRUN_2,      "firstrun.2",
                "R puts the stop and target on the chart. Drag them, Tab buys.");
   SSRAddString(out, n, SSR_S_FIRSTRUN_3,      "firstrun.3",
                "H lists every key. All virtual - nothing reaches a broker.");
   SSRAddString(out, n, SSR_S_FIRSTRUN_4,      "firstrun.4",
                "Shown once. Delete MQL5/Files/SSReplay/seen.txt for it again.");

   return n;
  }

//+------------------------------------------------------------------+
//| A TABLE THAT IS SHORT BY ONE IS A BLANK BUTTON.                  |
//|                                                                  |
//| Adding an enum value and forgetting its line compiles perfectly  |
//| and draws nothing where the word should be - which reads as a    |
//| rendering fault, not as a missing string. So the gap is COUNTED  |
//| and named, once, at start-up, in the log the developer reads.    |
//|                                                                  |
//| Returns how many are missing, so a test can assert zero rather   |
//| than a human noticing a line in a busy log.                      |
//+------------------------------------------------------------------+
int SSRStringsMissing(void)
  {
   int gaps = 0;
   for(int i = 0; i < SSR_S_COUNT; i++)
      if(i >= ArraySize(g_ssr_str) || g_ssr_str[i].name == "")
         gaps++;
   return gaps;
  }

//+------------------------------------------------------------------+
//| Load the catalogue, then let a file override what it covers.     |
//|                                                                  |
//| The file is MQL5\Files\SSReplay\lang\<code>.txt, one line per     |
//| string: "name = text". Lines that are blank, commented, or name   |
//| something this build does not have are SKIPPED, not fatal - a    |
//| translation written against a newer build must still work on an  |
//| older one, or every update breaks every translation.             |
//+------------------------------------------------------------------+
bool SSRLoadLanguage(const string code)
  {
   SSRStringsEnglish(g_ssr_str);
   g_ssr_str_ready = true;
   g_ssr_lang      = "en";
   g_ssr_overrides = 0;

   int gaps = SSRStringsMissing();
   if(gaps > 0)
      PrintFormat("[i18n] %d string(s) have no English text - they will draw "
                  "blank. Add the missing SSRAddString line(s).", gaps);

   if(code == "" || code == "en")
      return true;

   string path = "SSReplay\\lang\\" + code + ".txt";
   if(!FileIsExist(path))
     {
      PrintFormat("[i18n] no %s - staying in English. Put a translation at "
                  "MQL5\\Files\\%s", path, path);
      return false;
     }

   //--- FILE_SHARE_READ because a translator will have the file open in an
   //--- editor while they test, and an exclusive open would fail with no
   //--- explanation anyone could act on
   int fh = FileOpen(path, FILE_READ | FILE_TXT | FILE_ANSI | FILE_SHARE_READ |
                     FILE_SHARE_WRITE);
   if(fh == INVALID_HANDLE)
     {
      PrintFormat("[i18n] %s could not be read (%d) - staying in English",
                  path, GetLastError());
      return false;
     }

   int applied = 0, unknown = 0;
   while(!FileIsEnding(fh))
     {
      string line = FileReadString(fh);
      StringTrimLeft(line);
      StringTrimRight(line);
      if(line == "" || StringGetCharacter(line, 0) == '#')
         continue;
      int eq = StringFind(line, "=");
      if(eq <= 0)
         continue;
      string key = StringSubstr(line, 0, eq);
      string val = StringSubstr(line, eq + 1);
      StringTrimLeft(key);  StringTrimRight(key);
      StringTrimLeft(val);  StringTrimRight(val);
      if(key == "" || val == "")
         continue;

      bool hit = false;
      for(int i = 0; i < SSR_S_COUNT && !hit; i++)
         if(g_ssr_str[i].name == key)
           { g_ssr_str[i].text = val; applied++; hit = true; }
      if(!hit)
         unknown++;
     }
   FileClose(fh);

   g_ssr_lang      = code;
   g_ssr_overrides = applied;
   PrintFormat("[i18n] %s: %d of %d strings translated%s", code, applied,
               SSR_S_COUNT,
               (unknown > 0
                ? StringFormat(", %d line(s) name nothing in this build "
                               "(skipped, not an error)", unknown) : ""));
   return true;
  }

//+------------------------------------------------------------------+
//| One array slot. Never a search, never a comparison.               |
//|                                                                  |
//| Callable before SSRLoadLanguage has run - a draw that happened    |
//| during construction would otherwise read an empty array - so it   |
//| loads English on first use rather than returning nothing.          |
//+------------------------------------------------------------------+
string T(const ENUM_SSR_STR id)
  {
   if(!g_ssr_str_ready)
     {
      SSRStringsEnglish(g_ssr_str);
      g_ssr_str_ready = true;
     }
   int at = (int)id;
   if(at < 0 || at >= ArraySize(g_ssr_str))
      return "";
   return g_ssr_str[at].text;
  }

//--- what a translator's file would be called, and how much of it landed
string SSRLanguage(void)      { return g_ssr_lang; }
int    SSRTranslated(void)    { return g_ssr_overrides; }
int    SSRStringCount(void)   { return SSR_S_COUNT; }
string SSRStringName(const ENUM_SSR_STR id)
  {
   int at = (int)id;
   if(at < 0 || at >= ArraySize(g_ssr_str))
      return "";
   return g_ssr_str[at].name;
  }

#endif // SSR_STRINGS_MQH
//+------------------------------------------------------------------+
