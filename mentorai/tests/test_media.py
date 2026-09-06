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
    assert "خودِ گزارش نوشته" in review.render(metrics)


# ------------------------------------------------------------------ سنجش


def test_profit_factor_below_the_academy_threshold_fails() -> None:
    metrics = statement.StatementMetrics(source="computed", profit_factor=1.2)
    findings = review.review(metrics)

    assert any(f.level == "fail" and "۱٫۳۵" in f.text for f in findings)


def test_ideal_drawdown_band_is_named() -> None:
    metrics = statement.StatementMetrics(source="computed", profit_factor=1.5, max_drawdown_pct=5.5)
    text = review.render(metrics)

    assert "مطلوب" in text
    assert review.DECISION_NOTE in text, "سنجش نباید به‌جای تیم آکادمی تصمیم بگیرد"


def test_drawdown_over_the_cap_fails() -> None:
    metrics = statement.StatementMetrics(
        source="computed", profit_factor=2.0, max_drawdown_pct=14.0
    )
    assert any(f.level == "fail" for f in review.review(metrics))


# ------------------------------------------------------------------ آفیس


def test_xlsx_statement_is_analysed_like_any_other() -> None:
    rows = [
        ["Ticket", "Type", "Size", "Profit"],
        ["1", "buy", "0.10", "80.00"],
        ["2", "sell", "0.10", "-40.00"],
    ]
    result = extract(xlsx(rows), filename="report.xlsx")

    assert result.kind == "statement"
    assert result.metrics is not None
    assert result.metrics.profit_factor == pytest.approx(2.0)


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
