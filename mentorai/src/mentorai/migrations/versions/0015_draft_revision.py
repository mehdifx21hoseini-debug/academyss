"""شماره‌ی نسخه‌ی پیش‌نویس، تا تأیید به متنی بخورد که منتور دیده.

مسیر «دستور کوتاه منتور» متن پیشنهادی را عوض می‌کند، ولی کارت قبلی با دکمه‌ی
تأییدش در گفتگو می‌ماند. اگر منتور آن دکمه‌ی قدیمی را بزند، متن **جدید** می‌رود —
یعنی چیزی را تأیید کرده که ندیده است. کل ادعای ایمنی این سیستم همین است که آدم هر
پیام را دیده و تأیید کرده، پس این شکاف قابل پذیرش نیست.

Revision ID: 0015
Revises: 0014
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "0015"
down_revision = "0014"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "drafts",
        sa.Column("revision", sa.SmallInteger, nullable=False, server_default="0"),
    )


def downgrade() -> None:
    op.drop_column("drafts", "revision")
