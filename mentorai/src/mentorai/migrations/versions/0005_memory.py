"""حافظه‌ی بلندمدت دانشجو.

Revision ID: 0005
Revises: 0004
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "0005"
down_revision = "0004"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "student_memories",
        sa.Column("id", sa.BigInteger, primary_key=True, autoincrement=True),
        sa.Column(
            "student_id",
            sa.BigInteger,
            sa.ForeignKey("students.id", ondelete="CASCADE"),
            nullable=False,
        ),
        # حسابی که این واقعیت از گفتگوی آن یاد گرفته شد. الان برای بازیابی محدود
        # نمی‌شود، ولی ثبت می‌شود تا اگر بعداً جداسازی بین منتورها لازم شد، داده‌اش باشد.
        sa.Column(
            "account_id",
            sa.BigInteger,
            sa.ForeignKey("mentor_accounts.id", ondelete="SET NULL"),
        ),
        sa.Column("category", sa.String(32), nullable=False),
        sa.Column("content", sa.Text, nullable=False),
        # شکل نرمال‌شده، پایه‌ی یکتایی: همان واقعیت با نگارش دیگر دوباره ذخیره نمی‌شود.
        sa.Column("content_key", sa.String(200), nullable=False),
        sa.Column("confidence", sa.Float, nullable=False),
        sa.Column("source", sa.String(16), nullable=False),
        sa.Column(
            "source_message_id",
            sa.BigInteger,
            sa.ForeignKey("messages.id", ondelete="SET NULL"),
        ),
        sa.Column("active", sa.Boolean, nullable=False, server_default=sa.true()),
        sa.Column("superseded_at", sa.DateTime(timezone=True)),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()
        ),
        sa.CheckConstraint(
            "category in ('course', 'learning_stage', 'interest', 'goal', 'constraint', 'note')",
            name="ck_memory_category",
        ),
        sa.CheckConstraint("source in ('extracted', 'mentor')", name="ck_memory_source"),
    )
    # یک واقعیت به‌ازای هر دانشجو و دسته، فقط میان مواردی که هنوز فعال‌اند. مورد
    # جایگزین‌شده در ایندکس نمی‌ماند تا همان محتوا بعداً دوباره قابل ثبت باشد.
    op.create_index(
        "uq_memory_active_content",
        "student_memories",
        ["student_id", "category", "content_key"],
        unique=True,
        postgresql_where=sa.text("active"),
    )
    op.create_index(
        "ix_memory_student_active",
        "student_memories",
        ["student_id"],
        postgresql_where=sa.text("active"),
    )

    # یافته‌هایی که سیاست ردشان کرد. شمردنشان تنها راه فهمیدن این است که سیاست
    # درست کار می‌کند یا بیش‌ازحد سخت‌گیر است. محتوای ردشده ذخیره نمی‌شود.
    op.create_table(
        "memory_rejections",
        sa.Column("id", sa.BigInteger, primary_key=True, autoincrement=True),
        sa.Column(
            "student_id",
            sa.BigInteger,
            sa.ForeignKey("students.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("category", sa.String(32)),
        sa.Column("reason", sa.String(32), nullable=False),
        sa.Column("detail", sa.String(64)),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()
        ),
    )
    op.create_index("ix_memory_rejections_created_at", "memory_rejections", ["created_at"])


def downgrade() -> None:
    op.drop_table("memory_rejections")
    op.drop_table("student_memories")
