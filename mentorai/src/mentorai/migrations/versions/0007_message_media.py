"""فایل‌های پیام: آنچه از استیتمنت و پلن خوانده شد.

Revision ID: 0007
Revises: 0006
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects.postgresql import JSONB

revision = "0007"
down_revision = "0006"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "message_media",
        sa.Column("id", sa.BigInteger, primary_key=True, autoincrement=True),
        # یک ردیف به‌ازای هر پیام. قید یکتایی یعنی اگر پردازش دوباره اجرا شود،
        # ردیف دوم ساخته نمی‌شود؛ همان چیزی که برای تحویل تکراری تلگرام لازم است.
        sa.Column(
            "message_id",
            sa.BigInteger,
            sa.ForeignKey("messages.id", ondelete="CASCADE"),
            nullable=False,
            unique=True,
        ),
        sa.Column("kind", sa.String(16), nullable=False),
        sa.Column("mime", sa.String(128)),
        sa.Column("size_bytes", sa.BigInteger),
        # اثر انگشت محتوا. برای تشخیص فایل تکراری، بدون نگه داشتن خود فایل.
        sa.Column("sha256", sa.String(64)),
        sa.Column("refusal", sa.String(32)),
        # خودِ فایل ذخیره نمی‌شود. استیتمنت شماره‌حساب و موجودی دارد و نگه داشتنش
        # یعنی ساختن انباری که باید محافظت، پشتیبان‌گیری و پاک شود — در حالی که
        # نسخه‌ی اصلی همیشه در چت تلگرام منتور هست.
        sa.Column("extracted_text", sa.Text),
        sa.Column("metrics", JSONB),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()
        ),
        sa.CheckConstraint(
            "kind in ('statement', 'plan', 'rejected')", name="ck_message_media_kind"
        ),
        # ردیف رد‌شده باید دلیل داشته باشد، وگرنه معلوم نیست چرا خوانده نشد.
        sa.CheckConstraint(
            "(kind = 'rejected') = (refusal is not null)", name="ck_message_media_refusal"
        ),
    )


def downgrade() -> None:
    op.drop_table("message_media")
