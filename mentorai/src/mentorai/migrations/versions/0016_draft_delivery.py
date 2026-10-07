"""پیش‌نویس داخل خود گفتگو: محل تحویل و وضعیت «کنار گذاشته‌شده».

تا الان هر پیش‌نویس به ربات کنترل می‌رفت. حالا می‌تواند در کادر نوشتن همان گفتگوی
دانشجو، در حساب منتور، گذاشته شود (ADR-036). دو چیز لازم است:

- `delivery`: پیش‌نویس کجا گذاشته شد. برای پیش‌نویس‌های موجود `control_bot` است،
  یعنی رفتار قبلی دست‌نخورده می‌ماند.
- وضعیت `withdrawn`: سیستم خودش پیش‌نویس را کنار گذاشت، بی‌آنکه منتور تصمیمی بگیرد
  (پیش‌نویس تازه‌تر جایش را گرفت، یا منتور در کادر چیز دیگری نوشته بود). `rejected`
  نیست، چون رد کردن تصمیم منتور است و در آمار شرط خروج از حالت پیش‌نویس (ADR-010)
  می‌شمارد؛ کنار گذاشتن سیستم نباید آن عدد را عوض کند.

این مهاجرت فقط می‌افزاید: ستون تازه با مقدار پیش‌فرض، و یک قید که مقدار مجاز بیشتری
دارد. هیچ داده‌ای پاک یا عوض نمی‌شود.

Revision ID: 0016
Revises: 0015
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "0016"
down_revision = "0015"
branch_labels = None
depends_on = None

_OLD_STATUSES = "'pending', 'approved', 'edited', 'rejected', 'sent', 'failed'"
_NEW_STATUSES = "'pending', 'approved', 'edited', 'rejected', 'sent', 'failed', 'withdrawn'"


def upgrade() -> None:
    op.add_column(
        "drafts",
        sa.Column("delivery", sa.String(16), nullable=False, server_default="control_bot"),
    )
    op.create_check_constraint("ck_draft_delivery", "drafts", "delivery in ('control_bot', 'chat')")
    op.drop_constraint("ck_draft_status", "drafts", type_="check")
    op.create_check_constraint("ck_draft_status", "drafts", f"status in ({_NEW_STATUSES})")


def downgrade() -> None:
    # پیش‌نویس کنار گذاشته‌شده در قید قدیمی جا ندارد؛ به `rejected` نزدیک‌ترین است،
    # ولی بدون تغییر دادنش بازگشت ممکن نیست. بازگرداندن آن را `failed` می‌کند تا
    # آمار تصمیم‌های منتور (تأیید و رد) دست‌نخورده بماند.
    op.execute("update drafts set status = 'failed' where status = 'withdrawn'")
    op.drop_constraint("ck_draft_status", "drafts", type_="check")
    op.create_check_constraint("ck_draft_status", "drafts", f"status in ({_OLD_STATUSES})")
    op.drop_constraint("ck_draft_delivery", "drafts", type_="check")
    op.drop_column("drafts", "delivery")
