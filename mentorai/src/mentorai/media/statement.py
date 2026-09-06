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
from dataclasses import dataclass, field
from html.parser import HTMLParser

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

_NORMALISE = re.compile(r"[\s  _.:/\\-]+")
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

    type_text = _key(row[roles["type"]]) if "type" in roles and len(row) > roles["type"] else ""
    if type_text in BALANCE_TYPES:
        return Row(kind="balance", net=profit, type_text=type_text)
    if type_text and type_text not in TRADE_TYPES:
        # نوع ناشناخته یعنی این سطر معامله نیست — مثلاً سطر جمع‌بندی.
        return None

    net = profit
    for extra in ("commission", "swap"):
        at = roles.get(extra)
        if at is not None and len(row) > at:
            net += parse_number(row[at]) or 0.0
    return Row(kind="trade", net=net, type_text=type_text)


def _summary_pairs(tables: list[list[list[str]]]) -> dict[str, str]:
    """جفت‌های «برچسب: مقدار» که خودِ گزارش نوشته.

    این‌ها فقط وقتی استفاده می‌شوند که سطر معامله‌ای پیدا نشود، ولی همیشه نگه داشته
    می‌شوند تا بشود عدد محاسبه‌شده را با عدد خود گزارش مقایسه کرد.
    """
    pairs: dict[str, str] = {}
    for table in tables:
        for row in table:
            for index, cell in enumerate(row[:-1]):
                label = _key(cell.rstrip(":"))
                value = row[index + 1].strip()
                if label and value and label not in pairs and parse_number(value) is not None:
                    pairs[label] = value
    return pairs


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
    reported = _summary_pairs(tables)

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

    # سطر معامله‌ای نبود. اگر خود گزارش پروفیت فکتور نوشته، همان را برمی‌داریم و
    # صریح علامت می‌زنیم که محاسبه‌ی ما نیست.
    factor = next(
        (parse_number(reported[k]) for k in ("profitfactor", "پروفیتفکتور") if k in reported),
        None,
    )
    if factor is None:
        return None
    return StatementMetrics(source="report_summary", profit_factor=factor, reported=reported)


def analyse(html: str) -> StatementMetrics | None:
    """همان `analyse_tables`، برای گزارشی که به شکل HTML آمده."""
    return analyse_tables(parse_tables(html))
