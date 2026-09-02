"""بستن حلقه‌ی ارجاع: چه کسی رسیدگی کرد و کدام ارجاع‌ها هنوز بازند.

Revision ID: 0004
Revises: 0003
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "0004"
down_revision = "0003"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("escalations", sa.Column("resolved_by", sa.String(120)))
    # پرس‌وجوی «ارجاع‌های باز این مکالمه» در هر پیام منتور اجرا می‌شود.
    op.create_index(
        "ix_escalations_open_by_conversation",
        "escalations",
        ["conversation_id"],
        postgresql_where=sa.text("resolved_at is null"),
    )


def downgrade() -> None:
    op.drop_index("ix_escalations_open_by_conversation", table_name="escalations")
    op.drop_column("escalations", "resolved_by")
