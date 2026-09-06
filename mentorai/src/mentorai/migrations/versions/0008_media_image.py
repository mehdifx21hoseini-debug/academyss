"""تصویر هم یک نوع فایل خوانده‌شده است.

Revision ID: 0008
Revises: 0007
"""

from __future__ import annotations

from alembic import op

revision = "0008"
down_revision = "0007"
branch_labels = None
depends_on = None

_OLD = "kind in ('statement', 'plan', 'rejected')"
_NEW = "kind in ('statement', 'plan', 'image', 'rejected')"


def upgrade() -> None:
    op.drop_constraint("ck_message_media_kind", "message_media", type_="check")
    op.create_check_constraint("ck_message_media_kind", "message_media", _NEW)


def downgrade() -> None:
    op.drop_constraint("ck_message_media_kind", "message_media", type_="check")
    op.create_check_constraint("ck_message_media_kind", "message_media", _OLD)
