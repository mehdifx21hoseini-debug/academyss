"""شمارش قطعه‌های رفته، تا تلاش دوباره پیام اول را دوباره نفرستد.

پاسخ از این پس می‌تواند چند پیام باشد، چون منتور واقعی هم چند پیام می‌فرستد. این
یک راه تازه برای ارسال دوباره باز می‌کند: اگر قطعه‌ی اول برود و قطعه‌ی دوم
`FloodWait` بخورد، تلاش دوباره از ابتدا شروع می‌شود و دانشجو قطعه‌ی اول را دو بار
می‌گیرد. `sent_parts` می‌گوید تا کجا رفته‌ایم تا ادامه از همان‌جا باشد.

Revision ID: 0013
Revises: 0012
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "0013"
down_revision = "0012"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "deliveries",
        sa.Column("sent_parts", sa.SmallInteger, nullable=False, server_default="0"),
    )
    op.create_check_constraint("ck_delivery_sent_parts", "deliveries", "sent_parts >= 0")


def downgrade() -> None:
    op.drop_constraint("ck_delivery_sent_parts", "deliveries", type_="check")
    op.drop_column("deliveries", "sent_parts")
