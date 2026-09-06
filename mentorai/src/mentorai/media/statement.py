"""خواندن گزارش حساب متاتریدر و محاسبه‌ی اعداد آن.

قاعده‌ی حاکم بر این ماژول: **اندازه‌گیری با کد، نه با حدس مدل.** پروفیت فکتور و
دراوداون از خود سطرهای معامله حساب می‌شوند. اگر سطرها پیدا نشدند، عددی که خودِ
گزارش نوشته خوانده می‌شود و همین هم صریح علامت می‌خورد. اگر هیچ‌کدام نبود، این
ماژول چیزی برنمی‌گرداند و پرونده به منتور می‌رود — حدس زدن ممنوع است.

خروجی متاتریدر ۴ و ۵ هر دو HTML‌اند و بسته به زبان ترمینال، نام ستون‌ها فرق می‌کند.
برای همین تشخیص ستون بر پایه‌ی فهرست نام‌های شناخته‌شده است و نه بر پایه‌ی جای ستون.
"""

from __future__ import annotations

import re
from collections.abc import Mapping
from dataclasses import dataclass, field, fields
from html.parser import HTMLParser
from typing import Any

from mentorai.media.numbers import parse_number

MAX_ROWS = 20_000

# نام ستون‌ها به شکل نرمال‌شده. هر مجموعه یک «نقش» است، نه یک واژه.
COLUMN_ROLES: dict[str, frozenset[str]] = {
    "profit": frozenset({"profit", "p/l", "pl", "profit/loss", "سود", "سودوزیان", "سود/زیان"}),
    "type": frozenset({"type", "نوع"}),
    "volume": frozenset({"size", "volume", "lots", "حجم"}),
    "symbol": frozenset({"item", "symbol", "نماد", "جفتارز"}),
    "ticket": frozenset({"ticket", "position", "order", "deal", "شماره", "تیکت"}),
    "commission": frozenset({"commission", "کمیسیون"}),
    "swap": frozenset({"swap", "سواپ", "سوآپ"}),
    "time": frozenset({"time", "opentime", "closetime", "زمان"}),
}

# نوع سطرهایی که معامله‌اند، و آن‌هایی که جابه‌جایی پول‌اند.
TRADE_TYPES = frozenset(
    {"buy", "sell", "buylimit", "selllimit", "buystop", "sellstop", "خرید", "فروش"}
)
BALANCE_TYPES = frozenset({"balance", "credit", "واریز", "موجودی"})

# پرانتز و درصد هم حذف می‌شوند: برچسب «Profit Trades (% of total):» در گزارش
# انگلیسی و «معاملات سودآور - درصد از کل:» در فارسی، باید به یک کلید برسند.
_NORMALISE = re.compile(r"[\s  \u200c\u200e\u200f_.:/\\()%-]+")
# سلولی که بیش از این کشیده شده باشد، گزارش نیست؛ سقف جلوی سطر بسیار بلند را می‌گیرد.
MAX_COLSPAN = 64


def _span_of(attrs: list[tuple[str, str | None]]) -> int:
    for name, value in attrs:
        if name.lower() == "colspan":
            try:
                return max(1, min(int((value or "1").strip()), MAX_COLSPAN))
            except ValueError:
                return 1
    return 1


def _key(text: str) -> str:
    """کلید مقایسه‌ی نام ستون: بدون فاصله، بدون نشانه، حروف کوچک."""
    return _NORMALISE.sub("", (text or "").strip().lower())


class _TableCollector(HTMLParser):
    """جدول‌های یک صفحه‌ی HTML، به شکل سطر در سطر متن.

    عمداً از کتابخانه‌ی بیرونی استفاده نمی‌شود: تنها چیزی که لازم داریم متن سلول‌هاست
    و html.parser خودِ پایتون همین را می‌دهد، بدون افزودن وابستگی به سامانه‌ای که
    نشست حساب‌های تلگرام را نگه می‌دارد.
    """

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.tables: list[list[list[str]]] = []
        self._stack: list[list[list[str]]] = []
        self._row: list[str] | None = None
        self._cell: list[str] | None = None
        self._span = 1

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag == "table":
            self._stack.append([])
        elif tag == "tr" and self._stack:
            self._row = []
        elif tag in ("td", "th") and self._row is not None:
            self._cell = []
            self._span = _span_of(attrs)

    def handle_endtag(self, tag: str) -> None:
        if tag in ("td", "th") and self._cell is not None and self._row is not None:
            self._row.append(re.sub(r"\s+", " ", "".join(self._cell)).strip())
            # سلول کشیده‌شده باید جای واقعی‌اش را پر کند. گزارش متاتریدر سطر واریز را
            # با colspan می‌نویسد؛ بدون این، مبلغ واریز چند ستون جابه‌جا خوانده
            # می‌شود و سرمایه‌ی اولیه گم می‌شود.
            self._row.extend([""] * (self._span - 1))
            self._span = 1
            self._cell = None
        elif tag == "tr" and self._row is not None:
            if self._stack and len(self._stack[-1]) < MAX_ROWS:
                self._stack[-1].append(self._row)
            self._row = None
        elif tag == "table" and self._stack:
            self.tables.append(self._stack.pop())

    def handle_data(self, data: str) -> None:
        if self._cell is not None:
            self._cell.append(data)

    def close(self) -> None:  # noqa: D102
        super().close()
        # جدولِ بسته‌نشده هم باید برگردد؛ گزارش‌های واقعی همیشه HTML تمیزی نیستند.
        while self._stack:
            self.tables.append(self._stack.pop())


def parse_tables(html: str) -> list[list[list[str]]]:
    parser = _TableCollector()
    parser.feed(html)
    parser.close()
    return parser.tables


@dataclass(frozen=True)
class Row:
    kind: str  # "trade" یا "balance"
    net: float
    type_text: str


@dataclass
class StatementMetrics:
    """آنچه از یک استیتمنت می‌شود با اطمینان گفت."""

    source: str  # "computed" یا "report_summary"
    trades: int = 0
    wins: int = 0
    losses: int = 0
    gross_profit: float = 0.0
    gross_loss: float = 0.0
    net_profit: float = 0.0
    profit_factor: float | None = None
    initial_deposit: float | None = None
    max_drawdown_abs: float | None = None
    max_drawdown_pct: float | None = None
    reported: dict[str, str] = field(default_factory=dict)

    @property
    def win_rate(self) -> float | None:
        return (self.wins / self.trades) if self.trades else None

    @classmethod
    def from_dict(cls, data: Mapping[str, Any]) -> StatementMetrics | None:
        """بازسازی از ردیف ذخیره‌شده، یا None اگر ساختار با کد امروز نمی‌خواند.

        ردیف قدیمی بعد از تغییر این کلاس ممکن است کلید کم یا زیاد داشته باشد. عدد
        نیمه‌بازسازی‌شده از نبودِ عدد بدتر است، پس یا کامل درمی‌آید یا هیچ.
        """
        names = {f.name for f in fields(cls)}
        if "source" not in data or not names.issuperset(data.keys()):
            return None
        try:
            return cls(**dict(data))
        except TypeError:
            return None


def _header_index(table: list[list[str]]) -> tuple[int, dict[str, int]] | None:
    """شماره‌ی سطر عنوان و نقش هر ستون، یا None اگر این جدول معامله‌ها نیست.

    شرط: ستون سود باید باشد، به‌علاوه‌ی دست‌کم دو نقش دیگر. با شرط ضعیف‌تر، جدول
    خلاصه‌ی گزارش هم اشتباهاً جدول معامله‌ها خوانده می‌شود.
    """
    for index, row in enumerate(table[:20]):
        roles: dict[str, int] = {}
        for column, cell in enumerate(row):
            key = _key(cell)
            for role, names in COLUMN_ROLES.items():
                if key in names and role not in roles:
                    roles[role] = column
        if "profit" in roles and len(roles) >= 3:
            return index, roles
    return None


def _classify(row: list[str], roles: dict[str, int]) -> Row | None:
    profit_at = roles["profit"]
    if len(row) <= profit_at:
        return None
    profit = parse_number(row[profit_at])
    if profit is None:
        return None

    has_type = "type" in roles and len(row) > roles["type"]
    type_text = _key(row[roles["type"]]) if has_type else ""
    if type_text in BALANCE_TYPES:
        return Row(kind="balance", net=profit, type_text=type_text)
    if has_type and type_text not in TRADE_TYPES:
        # ستون نوع هست ولی مقدارش معامله نیست — سطر جمع‌بندی، سطر خالی، یا
        # سطر بخش دیگری از گزارش. خالی بودن هم «معامله نیست»: گزارش متاتریدر ۴
        # جمع ستون‌ها را در سطری با همین شکل می‌نویسد و اگر معامله شمرده شود،
        # سود ناخالص دقیقاً به‌اندازه‌ی سود خالص اضافه می‌آید.
        return None

    net = profit
    for extra in ("commission", "swap"):
        at = roles.get(extra)
        if at is not None and len(row) > at:
            net += parse_number(row[at]) or 0.0
    return Row(kind="trade", net=net, type_text=type_text)


# برچسب‌های خلاصه‌ی گزارش، به انگلیسی و فارسی. کلیدها به شکل نرمال‌شده‌اند.
#
# متاتریدر خودش این اعداد را حساب و چاپ می‌کند. خواندنشان از دوباره‌حساب‌کردن
# مطمئن‌تر است: نه به چیدمان ستون‌ها وابسته است، نه به اینکه کدام بخش گزارش
# معامله‌ی واقعی است — و متاتریدر ۵ سه بخش دارد (پوزیشن، سفارش، معامله) که
# شمردن هر سه با هم، هر عددی را چند برابر می‌کند.
SUMMARY_LABELS: dict[str, tuple[str, ...]] = {
    "gross_profit": ("grossprofit", "سودناخالص"),
    "gross_loss": ("grossloss", "زیانناخالص"),
    "net_profit": ("totalnetprofit", "کلسودخالص"),
    "profit_factor": ("profitfactor", "ضریبسود"),
    "total_trades": ("totaltrades", "کلمعاملهها"),
    "profit_trades": ("profittradesoftotal", "معاملاتسودآوردرصدازکل"),
    "loss_trades": ("losstradesoftotal", "معاملاتبازیاندرصدازکل"),
    "max_drawdown": ("maximaldrawdown", "ماکسیممدرادونبالانس", "balancedrawdownmaximal"),
    "deposit": ("depositwithdrawal",),
}
_LABEL_LOOKUP = {name: field for field, names in SUMMARY_LABELS.items() for name in names}

# «۴۷۵٫۵۶ (۴٫۵۷٪)» → درصد داخل پرانتز.
_PERCENT = re.compile(r"\(\s*(-?[\d,. ]+)\s*%\s*\)")


def _summary_pairs(tables: list[list[list[str]]]) -> dict[str, str]:
    """مقدارهای خلاصه‌ی گزارش، بر اساس برچسبشان.

    مقدار، **اولین سلول ناخالی بعد از برچسب** است و نه سلول بغلی: متاتریدر ۴
    برچسب و مقدار را با colspan می‌نویسد، پس بینشان سلول خالی می‌افتد.
    """
    found: dict[str, str] = {}
    for table in tables:
        for row in table:
            for index, cell in enumerate(row):
                field = _LABEL_LOOKUP.get(_key(cell))
                if field is None or field in found:
                    continue
                value = next((c.strip() for c in row[index + 1 :] if c.strip()), "")
                if value:
                    found[field] = value
    return found


def _leading_number(text: str | None) -> float | None:
    """عدد پیش از پرانتز. «۲۷٫۸۰ (۴٫۱۴٪)» → ۲۷٫۸۰"""
    if not text:
        return None
    return parse_number(text.split("(")[0])


def _from_summary(summary: dict[str, str]) -> StatementMetrics | None:
    """اعداد را از خلاصه‌ی خود گزارش بردار، یا None اگر خلاصه‌ای نبود."""
    factor = parse_number(summary.get("profit_factor"))
    gross_profit = parse_number(summary.get("gross_profit"))
    gross_loss = parse_number(summary.get("gross_loss"))
    if factor is None and (gross_profit is None or gross_loss is None):
        return None

    if factor is None and gross_profit is not None and gross_loss:
        factor = gross_profit / abs(gross_loss)
    # خروجی اکسل متاتریدر عدد را با شش رقم اعشار می‌نویسد؛ به همان دقتی گرد می‌شود
    # که مسیر محاسبه می‌دهد، وگرنه یک عدد در دو مسیر دو شکل دارد.
    factor = round(factor, 3) if factor is not None else None

    drawdown = summary.get("max_drawdown", "")
    percent = _PERCENT.search(drawdown)
    # شمارش‌ها به شکل «۲۳ (۴۷٫۹۲٪)» نوشته می‌شوند: عدد اول تعداد است و پرانتز درصد.
    trades = _leading_number(summary.get("total_trades"))
    wins = _leading_number(summary.get("profit_trades"))
    losses = _leading_number(summary.get("loss_trades"))

    return StatementMetrics(
        source="report_summary",
        trades=int(trades) if trades is not None else 0,
        wins=int(wins) if wins is not None else 0,
        losses=int(losses) if losses is not None else 0,
        gross_profit=abs(gross_profit) if gross_profit is not None else 0.0,
        gross_loss=abs(gross_loss) if gross_loss is not None else 0.0,
        net_profit=parse_number(summary.get("net_profit")) or 0.0,
        profit_factor=factor,
        initial_deposit=parse_number(summary.get("deposit")),
        max_drawdown_abs=_leading_number(drawdown),
        max_drawdown_pct=parse_number(percent.group(1)) if percent else None,
        reported=summary,
    )


def _drawdown(rows: list[Row], initial: float | None) -> tuple[float | None, float | None]:
    """بیشترین افت از سقف، به مبلغ و به درصد.

    درصد فقط وقتی محاسبه می‌شود که سرمایه‌ی اولیه معلوم باشد. بدون آن، منحنی از صفر
    شروع می‌شود و هر درصدی که در بیاید بی‌معنی است — و درصدِ بی‌معنی از نبودِ عدد
    بدتر است، چون به چشم واقعی می‌آید.
    """
    if not rows:
        return None, None
    equity = initial if initial is not None else 0.0
    peak = equity
    worst_abs = 0.0
    worst_pct = 0.0
    for row in rows:
        equity += row.net
        peak = max(peak, equity)
        drop = peak - equity
        if drop > worst_abs:
            worst_abs = drop
        if peak > 0:
            worst_pct = max(worst_pct, drop / peak)
    if initial is None:
        return worst_abs, None
    return worst_abs, worst_pct * 100.0


def analyse_tables(tables: list[list[list[str]]]) -> StatementMetrics | None:
    """اعداد یک گزارش حساب از روی جدول‌های آن، یا None اگر گزارش حساب نیست.

    ورودی عمداً «جدول» است و نه HTML: همان گزارش گاهی HTML است، گاهی CSV و گاهی
    xlsx. هر سه به سطر و ستون تبدیل می‌شوند و از اینجا به بعد یک مسیر دارند.

    None یعنی «نمی‌دانم»، و در لایه‌ی بالاتر به ارجاع به منتور ختم می‌شود.
    """
    if not tables:
        return None

    # خلاصه‌ی خود گزارش اولویت دارد. متاتریدر همین اعداد را حساب و چاپ می‌کند و
    # دانشجو هم همان‌ها را در ترمینالش می‌بیند؛ دوباره‌حساب‌کردن فقط جای تازه‌ای
    # برای اختلاف می‌سازد. محاسبه از سطرها می‌ماند برای گزارشی که خلاصه ندارد.
    reported = _summary_pairs(tables)
    from_summary = _from_summary(reported)
    if from_summary is not None:
        return from_summary

    for table in tables:
        found = _header_index(table)
        if found is None:
            continue
        start, roles = found
        parsed = [_classify(row, roles) for row in table[start + 1 :]]
        trades = [r for r in parsed if r is not None and r.kind == "trade"]
        balances = [r for r in parsed if r is not None and r.kind == "balance"]
        if not trades:
            continue

        wins = [t for t in trades if t.net > 0]
        losses = [t for t in trades if t.net < 0]
        gross_profit = sum(t.net for t in wins)
        gross_loss = abs(sum(t.net for t in losses))
        deposit = next((b.net for b in balances if b.net > 0), None)
        drawdown_abs, drawdown_pct = _drawdown(trades, deposit)

        return StatementMetrics(
            source="computed",
            trades=len(trades),
            wins=len(wins),
            losses=len(losses),
            gross_profit=round(gross_profit, 2),
            gross_loss=round(gross_loss, 2),
            net_profit=round(gross_profit - gross_loss, 2),
            profit_factor=round(gross_profit / gross_loss, 3) if gross_loss > 0 else None,
            initial_deposit=deposit,
            max_drawdown_abs=round(drawdown_abs, 2) if drawdown_abs is not None else None,
            max_drawdown_pct=round(drawdown_pct, 2) if drawdown_pct is not None else None,
            reported=reported,
        )

    # نه خلاصه‌ای بود و نه سطر معامله‌ای. یعنی این فایل گزارش حساب نیست.
    return None


def analyse(html: str) -> StatementMetrics | None:
    """همان `analyse_tables`، برای گزارشی که به شکل HTML آمده."""
    return analyse_tables(parse_tables(html))
