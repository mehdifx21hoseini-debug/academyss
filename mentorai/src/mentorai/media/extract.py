"""تبدیل فایلی که دانشجو فرستاده به متنی که مسیر پاسخ‌گویی می‌فهمد.

این لایه سه کار می‌کند و بیشتر از این نه: اعتبارسنجی، تشخیص قالب، و استخراج. هیچ
تصمیمی درباره‌ی پاسخ دادن یا ندادن اینجا گرفته نمی‌شود.

**هر چیزی که خوانده نشود، رد می‌شود.** قالب ناشناخته، فایل خراب، یا سندی که شبیه
استیتمنت است ولی سطرهایش پیدا نشد — همه به `Refusal` ختم می‌شوند و در لایه‌ی بالاتر
به منتور می‌روند. حدس زدن محتوای یک فایل بدتر از نخواندن آن است.

متنی که از اینجا بیرون می‌آید همچنان **داده** است و نه دستور: از دانشجو آمده و هرگز
نباید به‌عنوان دستور سیستمی به مدل داده شود.
"""

from __future__ import annotations

import csv
import enum
import io
from dataclasses import dataclass

from mentorai.media import office, statement

# سقف حجم فایل. بزرگ‌تر از این اصلاً باز نمی‌شود.
MAX_BYTES = 8 * 1024 * 1024
# سقف متنی که به مدل می‌رسد. پلن معاملاتی گاهی ده‌ها صفحه است و همه‌اش لازم نیست.
MAX_TEXT_CHARS = 8_000

_STATEMENT_EXT = ("htm", "html", "csv", "xlsx", "xls")
_PLAN_EXT = ("docx", "txt", "md", "csv", "xlsx")


class Refusal(enum.StrEnum):
    too_large = "too_large"
    unsupported_format = "unsupported_format"
    unreadable = "unreadable"
    empty = "empty"


@dataclass(frozen=True)
class Extraction:
    """نتیجه‌ی خواندن یک فایل.

    `refused` که پر باشد یعنی هیچ متنی در کار نیست و پرونده به منتور می‌رود.
    """

    kind: str  # "statement" | "plan" | "rejected"
    text: str = ""
    metrics: statement.StatementMetrics | None = None
    refused: Refusal | None = None


def _reject(reason: Refusal) -> Extraction:
    return Extraction(kind="rejected", refused=reason)


def _extension(filename: str | None) -> str:
    """پسوند فایل، فقط برای تشخیص قالب.

    نام فایل از دانشجو می‌آید و هرگز به مسیر فایل‌سیستم تبدیل نمی‌شود؛ فقط همین
    چند حرف آخرش خوانده می‌شود.
    """
    if not filename or "." not in filename:
        return ""
    return filename.rsplit(".", 1)[-1].strip().lower()[:8]


def _decode(data: bytes) -> str | None:
    for encoding in ("utf-8-sig", "utf-16", "windows-1256", "latin-1"):
        try:
            return data.decode(encoding)
        except (UnicodeDecodeError, UnicodeError):
            continue
    return None


def _clip(text: str) -> str:
    if len(text) <= MAX_TEXT_CHARS:
        return text
    return text[:MAX_TEXT_CHARS].rstrip() + "\n…"


def _csv_rows(text: str) -> list[list[str]]:
    try:
        dialect = csv.Sniffer().sniff(text[:4096], delimiters=",;\t")
    except csv.Error:
        dialect = csv.excel
    rows = csv.reader(io.StringIO(text), dialect)
    return [row for row in rows if any(cell.strip() for cell in row)]


def _rows_as_text(rows: list[list[str]]) -> str:
    return "\n".join(" | ".join(cell for cell in row if cell) for row in rows if any(row))


def extract(data: bytes, *, filename: str | None = None, mime: str | None = None) -> Extraction:
    """فایل را بخوان، یا صریح رد کن.

    ترتیب مهم است: هر فایلی که می‌تواند استیتمنت باشد، اول به‌عنوان استیتمنت آزموده
    می‌شود. اگر سطرهای معامله پیدا شد، اعداد محاسبه می‌شوند؛ اگر نه، همان فایل
    به‌عنوان یک سند متنی خوانده می‌شود.
    """
    if not data:
        return _reject(Refusal.empty)
    if len(data) > MAX_BYTES:
        return _reject(Refusal.too_large)

    extension = _extension(filename)
    known = extension in set(_STATEMENT_EXT) | set(_PLAN_EXT)
    if not known and not (mime or "").startswith("text/"):
        return _reject(Refusal.unsupported_format)

    if extension in ("xlsx", "xls"):
        try:
            sheets = office.read_xlsx(data)
        except office.OfficeError:
            return _reject(Refusal.unreadable)
        metrics = statement.analyse_tables([sheet.rows for sheet in sheets])
        if metrics is not None:
            return Extraction(kind="statement", metrics=metrics)
        body = "\n\n".join(f"[{s.name}]\n{_rows_as_text(s.rows)}" for s in sheets)
        return Extraction(kind="plan", text=_clip(body)) if body.strip() else _reject(Refusal.empty)

    if extension == "docx":
        try:
            body = office.read_docx(data)
        except office.OfficeError:
            return _reject(Refusal.unreadable)
        return Extraction(kind="plan", text=_clip(body))

    text = _decode(data)
    if text is None or not text.strip():
        return _reject(Refusal.unreadable if text is None else Refusal.empty)

    if extension in ("htm", "html") or "<table" in text.lower():
        metrics = statement.analyse(text)
        # فایل HTML که استیتمنت نیست، سند متنی هم حساب نمی‌شود: صفحه‌ی وب ذخیره‌شده
        # پر از منو و اسکریپت است و متنش برای پاسخ‌گویی به درد نمی‌خورد.
        return (
            Extraction(kind="statement", metrics=metrics)
            if metrics
            else _reject(Refusal.unsupported_format)
        )

    if extension == "csv":
        rows = _csv_rows(text)
        metrics = statement.analyse_tables([rows])
        if metrics is not None:
            return Extraction(kind="statement", metrics=metrics)
        return Extraction(kind="plan", text=_clip(_rows_as_text(rows)))

    return Extraction(kind="plan", text=_clip(text))
