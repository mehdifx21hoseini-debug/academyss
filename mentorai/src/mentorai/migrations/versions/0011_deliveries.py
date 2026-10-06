"""صندوق خروج: ارسال تلگرام از تراکنش پایگاه داده جدا می‌شود.

Revision ID: 0011
Revises: 0010
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "0011"
down_revision = "0010"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "deliveries",
        sa.Column("id", sa.BigInteger, primary_key=True, autoincrement=True),
        sa.Column(
            "conversation_id",
            sa.BigInteger,
            sa.ForeignKey("conversations.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "answered_message_id",
            sa.BigInteger,
            sa.ForeignKey("messages.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("body", sa.Text, nullable=False),
        sa.Column("status", sa.String(16), nullable=False, server_default="pending"),
        sa.Column("attempts", sa.Integer, nullable=False, server_default="0"),
        sa.Column("max_attempts", sa.Integer, nullable=False, server_default="5"),
        sa.Column("telegram_message_id", sa.BigInteger),
        sa.Column("last_error", sa.Text),
        sa.Column(
            "run_after", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.Column("claimed_at", sa.DateTime(timezone=True)),
        sa.Column("sent_at", sa.DateTime(timezone=True)),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.CheckConstraint(
            "status in ('pending', 'sending', 'sent', 'failed', 'abandoned')",
            name="ck_delivery_status",
        ),
        # کلید بی‌همتاسازی. برای یک پیام دانشجو بیش از یک تحویل ساخته نمی‌شود، و
        # این تضمین در خود پایگاه داده است نه در کد.
        sa.UniqueConstraint("answered_message_id", name="uq_delivery_answered_message"),
    )
    op.create_index(
        "ix_deliveries_pending",
        "deliveries",
        ["run_after"],
        postgresql_where=sa.text("status = 'pending'"),
    )
    op.create_index(
        "ix_deliveries_claimed_at",
        "deliveries",
        ["claimed_at"],
        postgresql_where=sa.text("status = 'sending'"),
    )


def downgrade() -> None:
    op.drop_index("ix_deliveries_claimed_at", table_name="deliveries")
    op.drop_index("ix_deliveries_pending", table_name="deliveries")
    op.drop_table("deliveries")
