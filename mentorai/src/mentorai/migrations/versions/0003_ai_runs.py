"""اجرای هوش مصنوعی، پیش‌نویس و ارجاع.

Revision ID: 0003
Revises: 0002
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision = "0003"
down_revision = "0002"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # حالت پاسخ‌دهی هر حساب. سوییچ بین پیش‌نویس و ارسال مستقیم یک تنظیم است، نه
    # بازنویسی کد (ADR-010). هر حساب جداگانه مستقل می‌شود، نه همه با هم.
    op.add_column(
        "mentor_accounts",
        sa.Column("reply_mode", sa.String(16), nullable=False, server_default="draft"),
    )
    op.create_check_constraint(
        "ck_account_reply_mode", "mentor_accounts", "reply_mode in ('draft', 'auto')"
    )
    # جایی که ربات کنترل با این منتور حرف می‌زند.
    op.add_column("mentor_accounts", sa.Column("control_chat_id", sa.BigInteger))

    op.create_table(
        "ai_runs",
        sa.Column("id", sa.BigInteger, primary_key=True, autoincrement=True),
        sa.Column(
            "conversation_id",
            sa.BigInteger,
            sa.ForeignKey("conversations.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "message_id",
            sa.BigInteger,
            sa.ForeignKey("messages.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("outcome", sa.String(16), nullable=False),
        sa.Column("reason", sa.String(64), nullable=False),
        sa.Column("confidence", sa.Float),
        sa.Column("model", sa.String(120)),
        sa.Column("prompt_version", sa.String(32), nullable=False),
        sa.Column("effort", sa.String(16)),
        sa.Column("latency_ms", sa.Integer),
        sa.Column("input_tokens", sa.Integer),
        sa.Column("output_tokens", sa.Integer),
        sa.Column("cache_read_tokens", sa.Integer),
        # اسناد بازیابی‌شده به‌همراه امتیاز و رتبه‌شان. بدون این، پرسش «چرا این پاسخ
        # را داد» بی‌جواب می‌ماند.
        sa.Column("retrieved", postgresql.JSONB, nullable=False, server_default="[]"),
        sa.Column("response_text", sa.Text),
        sa.Column("error", sa.Text),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()
        ),
        sa.CheckConstraint("outcome in ('answer', 'silence')", name="ck_ai_run_outcome"),
    )
    op.create_index("ix_ai_runs_conversation", "ai_runs", ["conversation_id", "created_at"])
    op.create_index("ix_ai_runs_created_at", "ai_runs", ["created_at"])
    # یک اجرا به‌ازای هر پیام. تلاش دوباره‌ی یک کار نباید رکورد دوم بسازد.
    op.create_unique_constraint("uq_ai_run_message", "ai_runs", ["message_id"])

    op.create_table(
        "drafts",
        sa.Column("id", sa.BigInteger, primary_key=True, autoincrement=True),
        sa.Column(
            "ai_run_id",
            sa.BigInteger,
            sa.ForeignKey("ai_runs.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "conversation_id",
            sa.BigInteger,
            sa.ForeignKey("conversations.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("proposed_text", sa.Text, nullable=False),
        sa.Column("final_text", sa.Text),
        sa.Column("status", sa.String(16), nullable=False, server_default="pending"),
        sa.Column("decided_by", sa.String(120)),
        sa.Column("decided_at", sa.DateTime(timezone=True)),
        sa.Column("control_message_id", sa.BigInteger),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()
        ),
        sa.CheckConstraint(
            "status in ('pending', 'approved', 'edited', 'rejected', 'sent', 'failed')",
            name="ck_draft_status",
        ),
        sa.UniqueConstraint("ai_run_id", name="uq_draft_ai_run"),
    )
    op.create_index(
        "ix_drafts_pending",
        "drafts",
        ["created_at"],
        postgresql_where=sa.text("status = 'pending'"),
    )

    op.create_table(
        "escalations",
        sa.Column("id", sa.BigInteger, primary_key=True, autoincrement=True),
        sa.Column(
            "conversation_id",
            sa.BigInteger,
            sa.ForeignKey("conversations.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "message_id",
            sa.BigInteger,
            sa.ForeignKey("messages.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("ai_run_id", sa.BigInteger, sa.ForeignKey("ai_runs.id", ondelete="SET NULL")),
        sa.Column("reason", sa.String(64), nullable=False),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()
        ),
        sa.Column("resolved_at", sa.DateTime(timezone=True)),
        sa.UniqueConstraint("message_id", name="uq_escalation_message"),
    )
    # ارجاع برای دانشجو نامرئی است، پس بدون شمارش و زمان‌سنجی ممکن است پیامی روزها
    # بماند و کسی متوجه نشود. این ایندکس همان پرس‌وجوی پایش را سریع نگه می‌دارد.
    op.create_index(
        "ix_escalations_open",
        "escalations",
        ["created_at"],
        postgresql_where=sa.text("resolved_at is null"),
    )


def downgrade() -> None:
    op.drop_table("escalations")
    op.drop_table("drafts")
    op.drop_table("ai_runs")
    op.drop_column("mentor_accounts", "control_chat_id")
    op.drop_constraint("ck_account_reply_mode", "mentor_accounts")
    op.drop_column("mentor_accounts", "reply_mode")
