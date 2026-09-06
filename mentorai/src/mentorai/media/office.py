"""خواندن فایل‌های آفیس، فقط با کتابخانه‌ی استاندارد پایتون.

xlsx و docx هر دو یک بایگانی zip از چند فایل XML‌اند. برای *خواندن* — که تنها کاری
است که این سیستم لازم دارد — نیازی به کتابخانه‌ی بیرونی نیست. این تصمیم عمدی است:
سامانه‌ای که نشست کامل حساب‌های تلگرام را نگه می‌دارد، هر وابستگی تازه یک سطح تماس
اضافه است.

هر ورودی از دانشجو می‌آید و بی‌اعتماد است، پس هر دو خواننده سقف دارند: سقف حجم
بازشده، سقف تعداد عضو، و سقف سطر. بدون این‌ها یک فایل کوچکِ ساختگی می‌تواند با باز
شدن، حافظه‌ی سرور را تمام کند.
"""

from __future__ import annotations

import io
import re
import zipfile
from dataclasses import dataclass
from xml.etree import ElementTree

# سقف مجموع حجم بازشده‌ی همه‌ی اعضای بایگانی.
MAX_UNCOMPRESSED_BYTES = 40 * 1024 * 1024
MAX_MEMBERS = 512
MAX_ROWS = 5_000
MAX_COLUMNS = 64


class OfficeError(Exception):
    """فایل خوانده نشد. پیام برای لاگ است، نه برای نمایش به دانشجو."""


@dataclass(frozen=True)
class Sheet:
    name: str
    rows: list[list[str]]


def _local(tag: str) -> str:
    """نام تگ بدون فضای‌نام.

    فایل‌های آفیس چند فضای‌نام دارند و نسخه‌های مختلف آن‌ها را جابه‌جا می‌کنند.
    تکیه بر نام محلی، خواننده را در برابر این تفاوت‌ها مقاوم می‌کند.
    """
    return tag.rsplit("}", 1)[-1]


def _open_archive(data: bytes) -> zipfile.ZipFile:
    try:
        archive = zipfile.ZipFile(io.BytesIO(data))
    except zipfile.BadZipFile as exc:
        raise OfficeError("فایل یک بایگانی معتبر نیست") from exc

    infos = archive.infolist()
    if len(infos) > MAX_MEMBERS:
        raise OfficeError("بایگانی عضو بیش از حد دارد")
    if sum(i.file_size for i in infos) > MAX_UNCOMPRESSED_BYTES:
        raise OfficeError("حجم بازشده بیش از حد مجاز است")
    return archive


def _member(archive: zipfile.ZipFile, name: str) -> bytes | None:
    try:
        return archive.read(name)
    except KeyError:
        return None


def _parse(blob: bytes) -> ElementTree.Element:
    try:
        # XMLParser پیش‌فرض پایتون موجودیت خارجی را گسترش نمی‌دهد، پس فایل ساختگی
        # نمی‌تواند از این مسیر به فایل‌های سرور برسد.
        return ElementTree.fromstring(blob)
    except ElementTree.ParseError as exc:
        raise OfficeError("XML داخل بایگانی خراب است") from exc


# ---------------------------------------------------------------- xlsx


def _shared_strings(archive: zipfile.ZipFile) -> list[str]:
    blob = _member(archive, "xl/sharedStrings.xml")
    if blob is None:
        return []
    root = _parse(blob)
    values: list[str] = []
    for item in root:
        if _local(item.tag) != "si":
            continue
        values.append("".join(t.text or "" for t in item.iter() if _local(t.tag) == "t"))
    return values


def _column_index(reference: str) -> int:
    """«C7» → ۲. مرجع سلول ستون را می‌دهد، و سلول خالی اصلاً در فایل نوشته نمی‌شود.

    بدون این، سطری که سلول میانی‌اش خالی است یک ستون جابه‌جا خوانده می‌شود و کل
    جدول به هم می‌ریزد.
    """
    index = 0
    for char in reference:
        if not char.isalpha():
            break
        index = index * 26 + (ord(char.upper()) - 64)
    return max(index - 1, 0)


def _cell_text(cell: ElementTree.Element, shared: list[str]) -> str:
    kind = cell.get("t")
    if kind == "inlineStr":
        return "".join(t.text or "" for t in cell.iter() if _local(t.tag) == "t").strip()
    value = next((v.text or "" for v in cell if _local(v.tag) == "v"), "")
    if kind == "s":
        try:
            return shared[int(value)].strip()
        except (ValueError, IndexError):
            return ""
    return value.strip()


def _sheet_targets(archive: zipfile.ZipFile) -> list[tuple[str, str]]:
    """(نام برگه، مسیر فایل برگه) به ترتیب کتاب کار.

    ترتیب و نام از workbook.xml می‌آید و مسیر واقعی از فایل روابط؛ تکیه بر
    «sheet1.xml برای برگه‌ی اول» در فایل‌های ساخته‌شده با ابزارهای دیگر می‌شکند.
    """
    workbook = _member(archive, "xl/workbook.xml")
    rels = _member(archive, "xl/_rels/workbook.xml.rels")
    if workbook is None or rels is None:
        raise OfficeError("ساختار کتاب کار ناقص است")

    targets: dict[str, str] = {}
    for rel in _parse(rels):
        rid = rel.get("Id")
        target = rel.get("Target")
        if rid and target:
            targets[rid] = "xl/" + target.lstrip("/").removeprefix("xl/")

    sheets: list[tuple[str, str]] = []
    for element in _parse(workbook).iter():
        if _local(element.tag) != "sheet":
            continue
        rid = next((v for k, v in element.attrib.items() if _local(k) == "id"), None)
        path = targets.get(rid or "")
        if path is not None:
            sheets.append((element.get("name") or "", path))
    return sheets


def read_xlsx(data: bytes) -> list[Sheet]:
    """برگه‌های یک فایل xlsx به‌صورت سطرهای متنی.

    فرمول‌ها محاسبه نمی‌شوند؛ مقدار ذخیره‌شده‌ی آخرین محاسبه خوانده می‌شود. تاریخ‌ها
    هم به شکل عدد سریال اکسل می‌مانند و اینجا تفسیر نمی‌شوند — تفسیر تاریخ کار
    لایه‌ای است که می‌داند ستون چیست.
    """
    archive = _open_archive(data)
    shared = _shared_strings(archive)
    sheets: list[Sheet] = []

    for name, path in _sheet_targets(archive):
        blob = _member(archive, path)
        if blob is None:
            continue
        rows: list[list[str]] = []
        for row in _parse(blob).iter():
            if _local(row.tag) != "row" or len(rows) >= MAX_ROWS:
                continue
            cells: list[str] = []
            for cell in row:
                if _local(cell.tag) != "c":
                    continue
                index = _column_index(cell.get("r") or "")
                if index >= MAX_COLUMNS:
                    continue
                while len(cells) < index:
                    cells.append("")
                cells.append(_cell_text(cell, shared))
            if any(cells):
                rows.append(cells)
        sheets.append(Sheet(name=name, rows=rows))

    if not sheets:
        raise OfficeError("هیچ برگه‌ای پیدا نشد")
    return sheets


# ---------------------------------------------------------------- docx

_WHITESPACE = re.compile(r"[ \t ‌]+")


def read_docx(data: bytes) -> str:
    """متن یک فایل docx، یک پاراگراف در هر خط.

    متن جدول‌ها هم می‌آید، چون هر سلول خودش پاراگراف دارد. ساختار جدول از دست
    می‌رود و این عمدی است: پلن معاملاتی متن است، نه داده‌ی ستونی.
    """
    archive = _open_archive(data)
    blob = _member(archive, "word/document.xml")
    if blob is None:
        raise OfficeError("سند اصلی داخل فایل نیست")

    lines: list[str] = []
    for paragraph in _parse(blob).iter():
        if _local(paragraph.tag) != "p" or len(lines) >= MAX_ROWS:
            continue
        parts: list[str] = []
        for node in paragraph.iter():
            tag = _local(node.tag)
            if tag == "t":
                parts.append(node.text or "")
            elif tag in ("tab", "br"):
                parts.append(" ")
        line = _WHITESPACE.sub(" ", "".join(parts)).strip()
        if line:
            lines.append(line)

    if not lines:
        raise OfficeError("سند متنی ندارد")
    return "\n".join(lines)
