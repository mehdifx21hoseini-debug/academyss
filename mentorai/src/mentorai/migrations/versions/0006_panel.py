"""کاربران و نشست‌های پنل مدیریت.

Revision ID: 0006
Revises: 0005
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "0006"
down_revision = "0005"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "panel_users",
        sa.Column("id", sa.BigInteger, primary_key=True, autoincrement=True),
        sa.Column("username", sa.String(64), nullable=False, unique=True),
        sa.Column("display_name", sa.String(200), nullable=False),
        # هش رمز با الگوریتم حافظه‌سنگین. ستون رمز متن ساده وجود ندارد و هرگز
        # نباید اضافه شود؛ در سیستم دیگر آکادمی همان ستون بود که مسیر ورود را باز نگه داشت.
        sa.Column("password_hash", sa.Text, nullable=False),
        sa.Column("role", sa.String(16), nullable=False),
        # نقش منتور بدون حساب معنی ندارد: دامنه‌ی دسترسی از همان حساب می‌آید.
        sa.Column(
            "account_id",
            sa.BigInteger,
            sa.ForeignKey("mentor_accounts.id", ondelete="RESTRICT"),
        ),
        sa.Column("active", sa.Boolean, nullable=False, server_default=sa.true()),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()
        ),
        sa.Column("last_login_at", sa.DateTime(timezone=True)),
        sa.CheckConstraint("role in ('mentor', 'admin')", name="ck_panel_user_role"),
        sa.CheckConstraint(
            "(role = 'admin' and account_id is null) or "
            "(role = 'mentor' and account_id is not null)",
            name="ck_panel_user_account_matches_role",
        ),
    )

    op.create_table(
        "panel_sessions",
        sa.Column("id", sa.BigInteger, primary_key=True, autoincrement=True),
        # خودِ توکن ذخیره نمی‌شود، فقط هشش. اگر نسخه‌ی پشتیبان پایگاه داده جایی برود،
        # هیچ نشست زنده‌ای از آن درنمی‌آید.
        sa.Column("token_hash", sa.String(64), nullable=False, unique=True),
        sa.Column(
            "user_id",
            sa.BigInteger,
            sa.ForeignKey("panel_users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()
        ),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("revoked_at", sa.DateTime(timezone=True)),
        sa.Column("source_ip", sa.String(64)),
    )
    op.create_index(
        "ix_panel_sessions_live",
        "panel_sessions",
        ["user_id"],
        postgresql_where=sa.text("revoked_at is null"),
    )


def downgrade() -> None:
    op.drop_table("panel_sessions")
    op.drop_table("panel_users")
