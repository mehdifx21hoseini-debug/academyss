"""هر فراخوانی مدل با هزینه‌اش، تا سقف هزینه چیزی را از قلم نیندازد.

Revision ID: 0010
Revises: 0009
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "0010"
down_revision = "0009"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "model_usage",
        sa.Column("id", sa.BigInteger, primary_key=True, autoincrement=True),
        sa.Column("purpose", sa.String(24), nullable=False),
        sa.Column("model", sa.String(120), nullable=False),
        sa.Column("input_tokens", sa.Integer, nullable=False, server_default="0"),
        sa.Column("output_tokens", sa.Integer, nullable=False, server_default="0"),
        sa.Column("cache_read_tokens", sa.Integer, nullable=False, server_default="0"),
        sa.Column("cost_micros", sa.BigInteger, nullable=False),
        sa.Column("priced", sa.Boolean, nullable=False, server_default=sa.text("true")),
        sa.Column(
            "occurred_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.CheckConstraint(
            "purpose in ('answer', 'image_description', 'memory_extraction')",
            name="ck_model_usage_purpose",
        ),
        sa.CheckConstraint("cost_micros >= 0", name="ck_model_usage_cost_nonnegative"),
    )
    # سقف هزینه در هر فراخوانی مدل، خرج امروز و این ماه را می‌پرسد. بدون این اندیس،
    # آن پرس‌وجو با رشد جدول کل جدول را می‌خواند.
    op.create_index("ix_model_usage_occurred_at", "model_usage", ["occurred_at"])


def downgrade() -> None:
    op.drop_index("ix_model_usage_occurred_at", table_name="model_usage")
    op.drop_table("model_usage")
