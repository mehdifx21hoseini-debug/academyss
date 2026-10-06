"""هدف تازه‌ی فراخوانی مدل: بسط دستور کوتاه منتور.

منتور یک جمله می‌نویسد و سیستم آن را با لحن آکادمی باز می‌کند. این یک فراخوانی
مدل است و مثل هر فراخوانی دیگری باید به سقف هزینه بخورد، پس `model_usage` باید
هدفش را بپذیرد.

Revision ID: 0014
Revises: 0013
"""

from __future__ import annotations

from alembic import op

revision = "0014"
down_revision = "0013"
branch_labels = None
depends_on = None

_OLD = "purpose in ('answer', 'image_description', 'memory_extraction')"
_NEW = (
    "purpose in ('answer', 'image_description', 'memory_extraction', "
    "'instruction_expansion')"
)


def upgrade() -> None:
    op.drop_constraint("ck_model_usage_purpose", "model_usage", type_="check")
    op.create_check_constraint("ck_model_usage_purpose", "model_usage", _NEW)


def downgrade() -> None:
    # سطرهای هدف تازه با قید قدیمی نمی‌خوانند. پاک کردنشان داده‌ی حسابداری هزینه را
    # از بین می‌برد، پس بازگشت فقط وقتی ممکن است که چنین سطری نباشد — و این بهتر از
    # حذف بی‌صدای رکورد مالی است.
    op.execute("delete from model_usage where purpose = 'instruction_expansion'")
    op.drop_constraint("ck_model_usage_purpose", "model_usage", type_="check")
    op.create_check_constraint("ck_model_usage_purpose", "model_usage", _OLD)
