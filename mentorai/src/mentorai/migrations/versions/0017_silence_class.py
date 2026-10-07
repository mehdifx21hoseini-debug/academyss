"""کلاس سکوت در `ai_runs` (RO-1، ADR-042).

شاخص‌ها تا امروز هر سکوتی را یکی می‌شمردند. از این به بعد هر اجرای ساکت یک کلاس دارد:
`intentional` (سکوت عمدی خارج از حوزه)، `needs_human` (یک آدم باید نگاه کند) و
`system_fault` (خطا یا نقص خود سیستم)، تا سکوت عمدی با خطا و با نیاز واقعی به منتور
قاطی نشود.

این مهاجرت فقط **می‌افزاید**:

- یک ستون nullable. **هیچ backfill ای نیست**؛ اجراهای قدیمی تهی می‌مانند و دست
  نمی‌خورند. شاخص‌ها تهی را مثل پیش از این (سکوتِ عادی) می‌شمارند.
- یک قید که کلاس را فقط به سکوت اجازه می‌دهد. پاسخ، حتی پاسخ جزئی، کلاس ندارد.

برگشت‌پذیر و غیرمخرب برای داده‌ی موجود: ستون و قید حذف می‌شوند، هیچ ردیفی تغییر نمی‌کند.

Revision ID: 0017
Revises: 0016
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "0017"
down_revision = "0016"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("ai_runs", sa.Column("silence_class", sa.String(16), nullable=True))
    op.create_check_constraint(
        "ck_ai_run_silence_class",
        "ai_runs",
        "silence_class is null or (outcome = 'silence' and silence_class in "
        "('intentional', 'needs_human', 'system_fault'))",
    )


def downgrade() -> None:
    op.drop_constraint("ck_ai_run_silence_class", "ai_runs", type_="check")
    op.drop_column("ai_runs", "silence_class")
