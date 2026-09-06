"""خواندن فایل دانشجو: استیتمنت، پلن، و هر چیزی که باید رد شود.

مهم‌ترین چیزی که این تست‌ها می‌سنجند این است: هر فایلی که با اطمینان خوانده نشود
**رد** می‌شود. عدد حدسی از نبود عدد بدتر است، چون به چشم واقعی می‌آید.
"""

from __future__ import annotations

import io
import zipfile

import pytest

from mentorai.media import office, review, statement
from mentorai.media.extract import Refusal, extract
from mentorai.media.numbers import parse_number

MT4_COLUMNS = [
    "Ticket",
    "Open Time",
    "Type",
    "Size",
    "Item",
    "Price",
    "S/L",
    "T/P",
    "Close Time",
    "Price",
    "Commission",
    "Taxes",
    "Swap",
    "Profit",
]


def _cells(values: list[str]) -> str:
    return "".join(f"<td>{v}</td>" for v in values)


def mt4_report(trades: list[tuple[str, str]], *, deposit: str | None = "1000.00") -> str:
    """گزارش متاتریدر ۴ با ساختار واقعی: سطر واریز با colspan، بعد معامله‌ها."""
    rows = ["<tr>" + _cells(MT4_COLUMNS) + "</tr>"]
    if deposit is not None:
        rows.append(
            "<tr><td>1</td><td>2026.01.02 10:00</td><td>balance</td>"
            f'<td colspan="10">Deposit</td><td>{deposit}</td></tr>'
        )
    for index, (kind, profit) in enumerate(trades, start=2):
        rows.append(
            "<tr>"
            + _cells(
                [
                    str(index),
                    "2026.01.03 09:00",
                    kind,
                    "0.10",
                    "EURUSD",
                    "1.0800",
                    "1.0750",
                    "1.0900",
                    "2026.01.03 12:00",
                    "1.0850",
                    "0.00",
                    "0.00",
                    "0.00",
                    profit,
                ]
            )
            + "</tr>"
        )
    return (
        "<html><body><table><tr><td>Account:</td><td>12345</td></tr></table>"
        "<table>" + "".join(rows) + "</table></body></html>"
    )


def _zip(members: dict[str, str]) -> bytes:
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w") as archive:
        for name, body in members.items():
            archive.writestr(name, body)
    return buffer.getvalue()


def xlsx(rows: list[list[str]]) -> bytes:
    """یک xlsx کمینه ولی معتبر، برای آزمودن خواننده بدون کتابخانه‌ی بیرونی."""
    cells = []
    for r, row in enumerate(rows, start=1):
        body = "".join(
            f'<c r="{chr(64 + c)}{r}" t="inlineStr"><is><t>{v}</t></is></c>'
            for c, v in enumerate(row, start=1)
        )
        cells.append(f'<row r="{r}">{body}</row>')
    return _zip(
        {
            "[Content_Types].xml": "<Types/>",
            "xl/workbook.xml": (
                '<workbook xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/'
                'relationships"><sheets><sheet name="گزارش" sheetId="1" r:id="rId1"/>'
                "</sheets></workbook>"
            ),
            "xl/_rels/workbook.xml.rels": (
                '<Relationships><Relationship Id="rId1" Target="worksheets/sheet1.xml"/>'
                "</Relationships>"
            ),
            "xl/worksheets/sheet1.xml": (
                f"<worksheet><sheetData>{''.join(cells)}</sheetData></worksheet>"
            ),
        }
    )


def docx(paragraphs: list[str]) -> bytes:
    body = "".join(f"<w:p><w:r><w:t>{p}</w:t></w:r></w:p>" for p in paragraphs)
    return _zip(
        {
            "[Content_Types].xml": "<Types/>",
            "word/document.xml": (
                '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/'
                f'2006/main"><w:body>{body}</w:body></w:document>'
            ),
        }
    )


# ------------------------------------------------------------------ اعداد


@pytest.mark.parametrize(
    ("raw", "expected"),
    [
        ("1234.56", 1234.56),
        ("1 234.56", 1234.56),
        ("1,234.56", 1234.56),
        ("1.234,56", 1234.56),
        ("1,50", 1.50),
        ("-42.10", -42.10),
        ("(42.10)", -42.10),
        ("۱۲۳٫۴۵".replace("٫", "."), 123.45),
        (" 1 000.00 ", 1000.0),
    ],
)
def test_numbers_are_read_the_way_terminals_write_them(raw: str, expected: float) -> None:
    assert parse_number(raw) == pytest.approx(expected)


@pytest.mark.parametrize("raw", ["", None, "buy", "1.2.3", "—", "Closed P/L:"])
def test_non_numbers_return_none_not_zero(raw: str | None) -> None:
    """صفر گرفتنِ چیزی که خوانده نشده، خطای بی‌صدا در جمع سود و زیان می‌سازد."""
    assert parse_number(raw) is None


# ------------------------------------------------------------------ استیتمنت


def test_profit_factor_is_computed_from_the_rows() -> None:
    html = mt4_report([("buy", "100.00"), ("sell", "-50.00"), ("buy", "35.00")])
    metrics = statement.analyse(html)

    assert metrics is not None
    assert metrics.source == "computed"
    assert metrics.trades == 3
    assert metrics.wins == 2 and metrics.losses == 1
    assert metrics.gross_profit == pytest.approx(135.0)
    assert metrics.gross_loss == pytest.approx(50.0)
    assert metrics.profit_factor == pytest.approx(2.7)
    assert metrics.net_profit == pytest.approx(85.0)


def test_deposit_row_is_not_counted_as_a_trade() -> None:
    """سطر واریز با colspan می‌آید. اگر معامله حساب شود، هم تعداد و هم پروفیت فکتور غلط می‌شود."""
    metrics = statement.analyse(mt4_report([("buy", "10.00")], deposit="5000.00"))

    assert metrics is not None
    assert metrics.trades == 1
    assert metrics.initial_deposit == pytest.approx(5000.0)


def test_drawdown_percent_needs_the_initial_deposit() -> None:
    """بدون سرمایه‌ی اولیه، درصد دراوداون بی‌معنی است و ساخته نمی‌شود."""
    trades = [("buy", "100.00"), ("sell", "-300.00"), ("buy", "50.00")]
    with_deposit = statement.analyse(mt4_report(trades, deposit="1000.00"))
    without = statement.analyse(mt4_report(trades, deposit=None))

    assert with_deposit is not None and without is not None
    # سقف روی ۱۱۰۰ است و پایین‌ترین نقطه ۸۰۰ → افت ۳۰۰ یعنی حدود ۲۷٪.
    assert with_deposit.max_drawdown_abs == pytest.approx(300.0)
    assert with_deposit.max_drawdown_pct == pytest.approx(27.27, abs=0.02)
    assert without.max_drawdown_abs == pytest.approx(300.0)
    assert without.max_drawdown_pct is None


def test_commission_and_swap_are_part_of_the_result() -> None:
    html = mt4_report([("buy", "10.00")]).replace(
        "<td>0.00</td><td>0.00</td><td>0.00</td><td>10.00</td>",
        "<td>-2.00</td><td>0.00</td><td>-1.00</td><td>10.00</td>",
    )
    metrics = statement.analyse(html)

    assert metrics is not None
    assert metrics.net_profit == pytest.approx(7.0)


def test_a_page_that_is_not_a_statement_is_refused() -> None:
    html = "<html><body><table><tr><td>نام</td><td>سبحان</td></tr></table></body></html>"
    assert statement.analyse(html) is None


def test_summary_is_used_only_when_no_rows_are_found_and_is_marked() -> None:
    html = (
        "<html><body><table>"
        "<tr><td>Total Net Profit:</td><td>250.00</td></tr>"
        "<tr><td>Profit Factor:</td><td>1.62</td></tr>"
        "</table></body></html>"
    )
    metrics = statement.analyse(html)

    assert metrics is not None
    assert metrics.source == "report_summary"
    assert metrics.profit_factor == pytest.approx(1.62)
    # از کجا آمدن عدد در خود رکورد ثبت می‌شود و در پنل دیده می‌شود؛ داخل پیام
    # دانشجو نمی‌آید، چون آنجا حرف اضافه است.
    assert "گزارش" not in review.render(metrics)


# ---------------------------------------------- شکل واقعی گزارش‌ها


MT4_TOTALS_ROWS = (
    # سطر جمع ستون‌ها: ستون «نوع» خالی است و عدد در ستون سود می‌نشیند.
    '<tr><td colspan="10">&nbsp;</td><td>0.00</td><td>0.00</td><td>0.00</td>'
    "<td>37.80</td></tr>"
    '<tr><td colspan="12">Closed P/L:</td><td colspan="2">37.80</td></tr>'
    # بخش «معاملات باز» جمع خودش را دارد، با همان شکل و عدد صفر.
    '<tr><td colspan="10">&nbsp;</td><td>0.00</td><td>0.00</td><td>0.00</td>'
    "<td>0.00</td></tr>"
)


def test_mt4_totals_rows_are_not_counted_as_trades() -> None:
    """اشکالی که روی گزارش واقعی پیدا شد.

    متاتریدر ۴ زیر جدول، سطر جمع ستون‌ها را با همان تعداد سلول می‌نویسد و ستون
    «نوع» را خالی می‌گذارد. اگر معامله شمرده شود، سود ناخالص دقیقاً به‌اندازه‌ی سود
    خالص اضافه می‌آید و پروفیت فکتور بی‌معنی بالا می‌رود.
    """
    html = mt4_report([("buy", "100.00"), ("sell", "-50.00")]).replace(
        "</table>", MT4_TOTALS_ROWS + "</table>"
    )
    metrics = statement.analyse(html)

    assert metrics is not None
    assert metrics.trades == 2, "سطرهای جمع نباید معامله شمرده شوند"
    assert metrics.gross_profit == pytest.approx(100.0)
    assert metrics.profit_factor == pytest.approx(2.0)


def mt5_report(*, persian: bool) -> bytes:
    """گزارش متاتریدر ۵ با ساختار واقعی: سه بخش، و خلاصه در پایان.

    خروجی واقعی ترمینال UTF-16 است، پس نمونه هم همان است.
    """
    labels = (
        (
            "کل سود خالص:",
            "سود ناخالص:",
            "زیان ناخالص:",
            "ضریب سود:",
            "کل معامله‌ها:",
            "معاملات سودآور - درصد از کل:",
            "معاملات با زیان - درصد از کل:",
            "ماکسیمم درادون بالانس:",
        )
        if persian
        else (
            "Total Net Profit:",
            "Gross Profit:",
            "Gross Loss:",
            "Profit Factor:",
            "Total Trades:",
            "Profit Trades (% of total):",
            "Loss Trades (% of total):",
            "Balance Drawdown Maximal:",
        )
    )
    values = (
        "1,021.95",
        "2,090.59",
        "-1,068.64",
        "1.96",
        "27",
        "16 (59.26%)",
        "11 (40.74%)",
        "475.56 (4.57%)",
    )
    summary = "".join(
        f"<tr><td>{label}</td><td>{value}</td></tr>"
        for label, value in zip(labels, values, strict=True)
    )
    # سه بخش، هر کدام با سطرهایی که ستون «نوع» دارند و buy/sell هستند: اگر همه با
    # هم شمرده شوند، هر عدد چند برابر می‌شود.
    section = (
        "<tr><td>زمان</td><td>پوزیشن</td><td>نماد</td><td>نوع</td><td>حجم</td>"
        "<td>قیمت</td><td>سود</td></tr>"
        "<tr><td>2026.07.22</td><td>1</td><td>US30</td><td>buy</td><td>1.00</td>"
        "<td>52306</td><td>101.52</td></tr>"
        "<tr><td>2026.07.23</td><td>2</td><td>US30</td><td>sell</td><td>1.00</td>"
        "<td>51612</td><td>-40.00</td></tr>"
    )
    html = (
        "<html><body><table>"
        "<tr><td>پوزیشن ها</td></tr>"
        + section
        + "<tr><td>سفارش‌ها</td></tr>"
        + section
        + "<tr><td>معاملات</td></tr>"
        + section
        + "<tr><td>نتایج</td></tr>"
        + summary
        + "</table></body></html>"
    )
    return html.encode("utf-16")


@pytest.mark.parametrize("persian", [True, False])
def test_mt5_sections_are_not_merged_into_one_trade_list(persian: bool) -> None:
    """اشکال دوم روی گزارش واقعی.

    متاتریدر ۵ پوزیشن‌ها و سفارش‌ها و معامله‌ها را در یک جدول پشت هم می‌نویسد و هر
    سه ستون «نوع» با buy/sell دارند. شمردن هر سه با هم، روی گزارش واقعی ۲۷ معامله
    را ۸۲ تا و پروفیت فکتور ۱٫۹۶ را ۲۲٫۶ نشان داد. خلاصه‌ی خود گزارش این ابهام را
    ندارد.
    """
    result = extract(mt5_report(persian=persian), filename="ReportHistory.html")

    assert result.kind == "statement"
    metrics = result.metrics
    assert metrics is not None
    assert metrics.source == "report_summary"
    assert metrics.trades == 27
    assert metrics.wins == 16 and metrics.losses == 11
    assert metrics.profit_factor == pytest.approx(1.96)
    assert metrics.gross_profit == pytest.approx(2090.59)
    assert metrics.gross_loss == pytest.approx(1068.64)
    assert metrics.max_drawdown_pct == pytest.approx(4.57)


def test_a_utf16_report_is_read() -> None:
    """خروجی واقعی متاتریدر ۵ در UTF-16 است، نه UTF-8."""
    result = extract(mt5_report(persian=True), filename="ReportHistory.html")
    assert result.refused is None and result.metrics is not None


def test_the_report_summary_wins_over_recomputing_from_rows() -> None:
    """وقتی گزارش خودش عدد دارد، همان ملاک است.

    متاتریدر این اعداد را خودش حساب و چاپ می‌کند و دانشجو هم همان‌ها را در
    ترمینالش می‌بیند؛ دوباره‌حساب‌کردن فقط جای تازه‌ای برای اختلاف می‌سازد.
    """
    metrics = extract(mt5_report(persian=True), filename="r.html").metrics
    assert metrics is not None
    # از روی دو سطرِ هر بخش، محاسبه‌ی مستقیم عدد کاملاً دیگری می‌داد.
    assert metrics.profit_factor == pytest.approx(1.96)


def test_a_report_without_a_summary_is_still_computed_from_its_rows() -> None:
    """گزارشی که خلاصه ندارد نباید رد شود؛ مسیر محاسبه سر جایش می‌ماند."""
    metrics = statement.analyse(mt4_report([("buy", "60.00"), ("sell", "-30.00")]))
    assert metrics is not None
    assert metrics.source == "computed"
    assert metrics.profit_factor == pytest.approx(2.0)


# ------------------------------------------------------------------ سنجش


def test_the_reply_explains_what_the_profit_factor_means() -> None:
    """عدد بدون معنی‌اش، برای دانشجو چیزی نیست."""
    metrics = statement.StatementMetrics(source="computed", trades=10, profit_factor=0.62)
    text = review.render(metrics)

    assert "۰٫۶۲" in text
    assert "به‌ازای هر ۱ واحد ضرر" in text, "باید بگوید این عدد یعنی چه"
    assert "ضررها از سودها جلو زدن" in text, "زیر ۱ یعنی حساب رو به کاهش"
    assert "۱٫۵" in text, "معیار منتور باید گفته شود"


def test_the_reply_uses_the_mentor_review_target_not_the_investment_plan_one() -> None:
    """دو عدد تأییدشده برای دو کار متفاوت‌اند و نباید جابه‌جا شوند.

    «۱٫۳۵» شرط پذیرش در طرح جذب سرمایه است؛ بررسی عمومی استیتمنت معیار خودش را
    دارد و آن «بالای ۱٫۵» است.
    """
    text = review.render(statement.StatementMetrics(source="computed", profit_factor=1.4))

    assert "۱٫۵" in text
    assert "۱٫۳۵" not in text


def test_a_heavy_drawdown_gets_the_academy_recovery_path() -> None:
    """مسیر توقف و بازگشت، رکورد تأییدشده‌ی آکادمی برای دراوداون سنگین است."""
    text = review.render(
        statement.StatementMetrics(source="computed", profit_factor=0.6, max_drawdown_pct=44.39)
    )

    assert "متوقف کنید" in text
    assert "بک‌تست" in text
    assert "فوروارد تست" in text


def test_a_healthy_drawdown_does_not_get_the_recovery_path() -> None:
    """توصیه‌ی توقف معامله فقط جایی گفته می‌شود که رکورد آکادمی برایش نوشته شده."""
    text = review.render(
        statement.StatementMetrics(source="computed", profit_factor=2.0, max_drawdown_pct=5.5)
    )

    assert "متوقف کنید" not in text
    assert "مطلوب" in text


def test_the_reply_follows_the_mentor_answer_structure() -> None:
    """ساختار تأییدشده: سلام، تأیید آنچه درست بوده، اصلاح، و بستن با انرژی."""
    text = review.render(
        statement.StatementMetrics(source="computed", trades=40, profit_factor=1.6)
    )

    assert text.startswith(review.GREETING)
    assert "قدم درستیه" in text, "بخش تأیید نباید حذف شود"
    assert text.endswith(review.CLOSING_GOOD)


def test_even_a_bad_statement_opens_with_something_true_and_positive() -> None:
    """رکورد «اول تحسین، بعد اصلاح» می‌گوید این بخش در بدترین نتیجه هم می‌آید."""
    text = review.render(
        statement.StatementMetrics(
            source="computed",
            trades=106,
            wins=21,
            losses=85,
            profit_factor=0.62,
            max_drawdown_pct=44.39,
            net_profit=-616.51,
        )
    )

    assert "قدم درستیه" in text
    assert text.index("قدم درستیه") < text.index("۰٫۶۲"), "تحسین باید پیش از اصلاح بیاید"
    assert text.endswith(review.CLOSING_HARD)


def test_a_losing_result_is_worded_not_signed() -> None:
    """علامت منفی پیش از ارقام فارسی در متن راست‌به‌چپ جابه‌جا می‌شود."""
    metrics = statement.StatementMetrics(
        source="computed", trades=3, wins=1, losses=2, profit_factor=0.6, net_profit=-616.51
    )
    text = review.render(metrics)

    assert "ضرر داده" in text
    assert "زیان" not in text, "واژه‌ی محاوره‌ای منتورها «ضرر» است"
    assert "-۶۱۶" not in text and "-616" not in text


def test_an_xlsx_statement_is_read_from_its_summary() -> None:
    """متاتریدر ۵ خروجی اکسل هم می‌دهد، با همان بخش‌ها و همان خلاصه.

    آزموده‌شده روی خروجی واقعی: همان مسیر خلاصه، بدون کد جداگانه برای اکسل.
    """
    rows = [
        ["Positions"],
        ["Time", "Position", "Symbol", "Type", "Volume", "Price", "Profit"],
        ["2026.09.01", "1", "US30", "buy", "1.00", "53000", "10.00"],
        ["Deals"],
        ["Time", "Deal", "Symbol", "Type", "Volume", "Price", "Profit"],
        ["2026.09.01", "2", "US30", "sell", "1.00", "53010", "10.00"],
        ["Results"],
        ["Total Net Profit:", "-616.510000", "Gross Profit:", "1008.930000"],
        ["Gross Loss:", "-1625.440000"],
        ["Profit Factor:", "0.620712"],
        ["Balance Drawdown Maximal:", "892.80 (44.39%)"],
        ["Total Trades:", "106.000000"],
        ["Profit Trades (% of total):", "21 (19.81%)"],
        ["Loss Trades (% of total):", "85 (80.19%)"],
    ]
    result = extract(xlsx(rows), filename="ReportHistory.xlsx")

    assert result.kind == "statement"
    metrics = result.metrics
    assert metrics is not None
    assert metrics.source == "report_summary"
    assert metrics.trades == 106
    assert metrics.wins == 21 and metrics.losses == 85
    # عدد اکسل شش رقم اعشار دارد و باید مثل مسیر محاسبه گرد شود.
    assert metrics.profit_factor == pytest.approx(0.621)
    assert metrics.max_drawdown_pct == pytest.approx(44.39)
    assert metrics.net_profit == pytest.approx(-616.51)


def test_xlsx_that_is_a_plan_comes_back_as_text() -> None:
    rows = [["مرحله", "قانون"], ["ورود", "فقط با تأیید تایم بالاتر"]]
    result = extract(xlsx(rows), filename="plan.xlsx")

    assert result.kind == "plan"
    assert "فقط با تأیید تایم بالاتر" in result.text


def test_empty_cells_do_not_shift_the_columns() -> None:
    """سلول خالی اصلاً در فایل نوشته نمی‌شود؛ ستون از مرجع سلول در می‌آید."""
    body = (
        '<row r="1"><c r="A1" t="inlineStr"><is><t>الف</t></is></c>'
        '<c r="C1" t="inlineStr"><is><t>ج</t></is></c></row>'
    )
    data = _zip(
        {
            "xl/workbook.xml": (
                '<workbook xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/'
                'relationships"><sheets><sheet name="s" r:id="rId1"/></sheets></workbook>'
            ),
            "xl/_rels/workbook.xml.rels": (
                '<Relationships><Relationship Id="rId1" Target="worksheets/sheet1.xml"/>'
                "</Relationships>"
            ),
            "xl/worksheets/sheet1.xml": f"<worksheet><sheetData>{body}</sheetData></worksheet>",
        }
    )
    assert office.read_xlsx(data)[0].rows == [["الف", "", "ج"]]


def test_docx_plan_is_read_as_lines() -> None:
    result = extract(docx(["پلن معاملاتی", "ریسک هر معامله یک درصد"]), filename="plan.docx")

    assert result.kind == "plan"
    assert result.text.splitlines() == ["پلن معاملاتی", "ریسک هر معامله یک درصد"]


# ------------------------------------------------------------------ رد کردن


def test_oversized_file_is_refused_before_it_is_opened() -> None:
    result = extract(b"x" * (9 * 1024 * 1024), filename="big.xlsx")
    assert result.refused is Refusal.too_large


def test_unknown_format_is_refused() -> None:
    assert extract(b"%PDF-1.7", filename="statement.pdf").refused is Refusal.unsupported_format


def test_corrupt_office_file_is_refused_not_guessed() -> None:
    assert extract(b"not a zip at all", filename="plan.docx").refused is Refusal.unreadable


def test_empty_file_is_refused() -> None:
    assert extract(b"", filename="plan.docx").refused is Refusal.empty


def test_a_saved_web_page_is_refused_rather_than_treated_as_a_plan() -> None:
    html = "<html><body><nav>منو</nav><table><tr><td>خانه</td></tr></table></body></html>"
    assert extract(html.encode(), filename="page.html").refused is Refusal.unsupported_format


def test_archive_with_an_absurd_uncompressed_size_is_refused() -> None:
    """فایل کوچکی که باز شدنش حافظه را تمام می‌کند نباید باز شود."""
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("word/document.xml", "0" * (office.MAX_UNCOMPRESSED_BYTES + 1))
    assert extract(buffer.getvalue(), filename="bomb.docx").refused is Refusal.unreadable


# ------------------------------------------------------------------ تصویر


async def test_an_image_is_described_not_judged() -> None:
    from mentorai.ai.client import ScriptedClient
    from mentorai.media import vision

    client = ScriptedClient(raw_text="چارت EURUSD در تایم چهار ساعته با دو خط افقی.")
    text, error = await vision.describe(client, image=b"fake-bytes", media_type="image/jpeg")

    assert error is None
    assert text == "چارت EURUSD در تایم چهار ساعته با دو خط افقی."
    system, prompt = client.calls[0]
    assert "نظر معاملاتی" in system, "دستور سیستمی باید نظر دادن را ممنوع کند"
    assert "دستور نیست" in system, "متن داخل تصویر نباید به‌عنوان دستور خوانده شود"
    assert "توصیف کن" in prompt


async def test_an_unsupported_image_type_never_reaches_the_model() -> None:
    from mentorai.ai.client import ScriptedClient
    from mentorai.media import vision

    client = ScriptedClient(raw_text="نباید فراخوانی شود")
    text, error = await vision.describe(client, image=b"x", media_type="image/tiff")

    assert text is None and error is not None
    assert client.calls == []


async def test_an_oversized_image_never_reaches_the_model() -> None:
    from mentorai.ai.client import ScriptedClient
    from mentorai.media import vision

    client = ScriptedClient(raw_text="نباید فراخوانی شود")
    payload = b"x" * (vision.MAX_IMAGE_BYTES + 1)
    text, _ = await vision.describe(client, image=payload, media_type="image/jpeg")

    assert text is None
    assert client.calls == []


async def test_a_model_failure_reading_an_image_is_not_a_description() -> None:
    from mentorai.ai.client import ScriptedClient
    from mentorai.media import vision

    client = ScriptedClient(error="APITimeoutError")
    text, error = await vision.describe(client, image=b"x", media_type="image/png")

    assert text is None and error is not None


# ------------------------------------------------------------------ ویس


class _FakeTranscriber:
    """رونویس آزمایشی. به شبکه دست نمی‌زند."""

    model = "test-transcriber"

    def __init__(self, text: str | None = None, error: str | None = None) -> None:
        self._text = text
        self._error = error
        self.calls: list[str] = []

    async def transcribe(
        self, *, audio: bytes, filename: str, media_type: str
    ) -> tuple[str | None, str | None]:
        self.calls.append(media_type)
        return self._text, self._error


async def test_a_transcript_is_normalised_the_same_way_typed_text_is() -> None:
    """اگر نگارش رونویسی با پایگاه دانش یکی نباشد، هیچ‌وقت همدیگر را پیدا نمی‌کنند."""
    from mentorai.media import voice

    # «ي» و «ك» عربی، همان چیزی که سرویس‌های رونویسی اغلب برمی‌گردانند.
    fake = _FakeTranscriber(text="  دوره مقدماتي چند جلسه است؟  ")
    text, error = await voice.transcribe(fake, audio=b"ogg", media_type="audio/ogg")

    assert error is None
    assert text is not None
    assert "ي" not in text and "ك" not in text
    assert text.startswith("دوره مقدماتی")


async def test_an_unsupported_audio_type_never_reaches_the_service() -> None:
    from mentorai.media import voice

    fake = _FakeTranscriber(text="نباید فراخوانی شود")
    text, error = await voice.transcribe(fake, audio=b"x", media_type="audio/flac")

    assert text is None and error is not None
    assert fake.calls == []


async def test_oversized_audio_never_reaches_the_service() -> None:
    from mentorai.media import voice

    fake = _FakeTranscriber(text="نباید فراخوانی شود")
    payload = b"x" * (voice.MAX_AUDIO_BYTES + 1)
    text, _ = await voice.transcribe(fake, audio=payload, media_type="audio/ogg")

    assert text is None
    assert fake.calls == []


@pytest.mark.parametrize("returned", ["", "  ", "اه"])
async def test_an_empty_or_tiny_transcript_is_not_a_question(returned: str) -> None:
    """سکوت و نویز رونویسی می‌شوند به چیزی که سؤال نیست؛ نباید وارد مسیر پاسخ شود."""
    from mentorai.media import voice

    text, error = await voice.transcribe(
        _FakeTranscriber(text=returned), audio=b"ogg", media_type="audio/ogg"
    )
    assert text is None and error is not None


async def test_a_service_failure_is_not_a_transcript() -> None:
    from mentorai.media import voice

    text, error = await voice.transcribe(
        _FakeTranscriber(error="ConnectTimeout"), audio=b"ogg", media_type="audio/ogg"
    )
    assert text is None and error is not None


def test_no_transcriber_is_configured_by_default() -> None:
    """تا وقتی مالک سرویسی انتخاب نکرده، هیچ صدایی از این سیستم بیرون نمی‌رود."""
    from mentorai.config import get_settings
    from mentorai.media import voice

    get_settings.cache_clear()
    try:
        assert voice.build_transcriber() is None
    finally:
        get_settings.cache_clear()
