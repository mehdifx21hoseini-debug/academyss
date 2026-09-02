"""طرح اولیه: حساب‌ها، دانشجو و هویت، مکالمه و پیام، صف کار، ثبت تکراری و بازرسی.

Revision ID: 0001
Revises:
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "0001"
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "mentor_accounts",
        sa.Column("id", sa.BigInteger, primary_key=True, autoincrement=True),
        sa.Column("slug", sa.String(64), nullable=False, unique=True),
        sa.Column("mentor_name", sa.String(200), nullable=False),
        sa.Column("phone", sa.String(32), nullable=False),
        sa.Column("telegram_user_id", sa.BigInteger, unique=True),
        sa.Column("device_model", sa.String(120), nullable=False),
        sa.Column("system_version", sa.String(120), nullable=False),
        sa.Column("app_version", sa.String(60), nullable=False),
        sa.Column("session_encrypted", sa.LargeBinary),
        sa.Column("enabled", sa.Boolean, nullable=False, server_default=sa.true()),
        sa.Column("send_paused", sa.Boolean, nullable=False, server_default=sa.false()),
        sa.Column("paused_reason", sa.Text),
        sa.Column("flood_wait_until", sa.DateTime(timezone=True)),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()
        ),
    )

    op.create_table(
        "students",
        sa.Column("id", sa.BigInteger, primary_key=True, autoincrement=True),
        sa.Column("display_name", sa.String(300)),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()
        ),
    )

    op.create_table(
        "identities",
        sa.Column("id", sa.BigInteger, primary_key=True, autoincrement=True),
        sa.Column(
            "student_id",
            sa.BigInteger,
            sa.ForeignKey("students.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("telegram_user_id", sa.BigInteger, nullable=False, unique=True),
        sa.Column("username", sa.String(64)),
        sa.Column("first_name", sa.String(200)),
        sa.Column("last_name", sa.String(200)),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()
        ),
    )
    op.create_index("ix_identities_student_id", "identities", ["student_id"])

    op.create_table(
        "excluded_chats",
        sa.Column("id", sa.BigInteger, primary_key=True, autoincrement=True),
        sa.Column(
            "account_id",
            sa.BigInteger,
            sa.ForeignKey("mentor_accounts.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("telegram_peer_id", sa.BigInteger, nullable=False),
        sa.Column("reason", sa.Text),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()
        ),
        sa.UniqueConstraint("account_id", "telegram_peer_id", name="uq_excluded_account_peer"),
    )

    op.create_table(
        "conversations",
        sa.Column("id", sa.BigInteger, primary_key=True, autoincrement=True),
        sa.Column(
            "account_id",
            sa.BigInteger,
            sa.ForeignKey("mentor_accounts.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "student_id",
            sa.BigInteger,
            sa.ForeignKey("students.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("telegram_chat_id", sa.BigInteger, nullable=False),
        sa.Column("status", sa.String(32), nullable=False, server_default="active"),
        sa.Column("assistant_enabled", sa.Boolean, nullable=False, server_default=sa.true()),
        sa.Column("last_answered_message_id", sa.BigInteger),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()
        ),
        sa.Column(
            "updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()
        ),
        sa.UniqueConstraint("account_id", "telegram_chat_id", name="uq_conversation_account_chat"),
        sa.CheckConstraint(
            "status in ('active', 'awaiting_mentor', 'closed')", name="ck_conversation_status"
        ),
    )
    op.create_index("ix_conversations_student_id", "conversations", ["student_id"])

    op.create_table(
        "messages",
        sa.Column("id", sa.BigInteger, primary_key=True, autoincrement=True),
        sa.Column(
            "conversation_id",
            sa.BigInteger,
            sa.ForeignKey("conversations.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("telegram_message_id", sa.BigInteger, nullable=False),
        sa.Column("sender", sa.String(16), nullable=False),
        sa.Column("text", sa.Text),
        sa.Column("media_type", sa.String(32)),
        sa.Column("reply_to_message_id", sa.BigInteger),
        sa.Column("sent_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()
        ),
        # قید تشخیص پیام تکراری. بدون این، هر چیز دیگری فقط یک بررسی خوش‌بینانه است.
        sa.UniqueConstraint(
            "conversation_id", "telegram_message_id", name="uq_message_conversation_tg_id"
        ),
        sa.CheckConstraint(
            "sender in ('student', 'assistant', 'mentor')", name="ck_message_sender"
        ),
    )
    op.create_index("ix_messages_conversation_sent_at", "messages", ["conversation_id", "sent_at"])

    op.create_table(
        "jobs",
        sa.Column("id", sa.BigInteger, primary_key=True, autoincrement=True),
        sa.Column("kind", sa.String(64), nullable=False),
        sa.Column("payload", sa.Text, nullable=False),
        sa.Column("status", sa.String(16), nullable=False, server_default="pending"),
        sa.Column("attempts", sa.Integer, nullable=False, server_default="0"),
        sa.Column("max_attempts", sa.Integer, nullable=False, server_default="5"),
        sa.Column("last_error", sa.Text),
        sa.Column(
            "run_after", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()
        ),
        sa.Column("locked_by", sa.String(64)),
        sa.Column("locked_at", sa.DateTime(timezone=True)),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()
        ),
        sa.CheckConstraint(
            "status in ('pending', 'processing', 'done', 'failed', 'dead')", name="ck_job_status"
        ),
    )
    op.create_index(
        "ix_jobs_pending",
        "jobs",
        ["run_after", "id"],
        postgresql_where=sa.text("status = 'pending'"),
    )

    op.create_table(
        "duplicate_deliveries",
        sa.Column("id", sa.BigInteger, primary_key=True, autoincrement=True),
        sa.Column("account_id", sa.BigInteger, nullable=False),
        sa.Column("telegram_chat_id", sa.BigInteger, nullable=False),
        sa.Column("telegram_message_id", sa.BigInteger, nullable=False),
        sa.Column(
            "seen_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()
        ),
    )
    op.create_index("ix_duplicate_deliveries_seen_at", "duplicate_deliveries", ["seen_at"])

    op.create_table(
        "audit_log",
        sa.Column("id", sa.BigInteger, primary_key=True, autoincrement=True),
        sa.Column("actor", sa.String(120), nullable=False),
        sa.Column("action", sa.String(64), nullable=False),
        sa.Column("target", sa.String(200)),
        sa.Column("detail", sa.Text),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()
        ),
    )
    op.create_index("ix_audit_log_created_at", "audit_log", ["created_at"])


def downgrade() -> None:
    for table in (
        "audit_log",
        "duplicate_deliveries",
        "jobs",
        "messages",
        "conversations",
        "excluded_chats",
        "identities",
        "students",
        "mentor_accounts",
    ):
        op.drop_table(table)
