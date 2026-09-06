"""ویس هم یک نوع فایل خوانده‌شده است.

Revision ID: 0009
Revises: 0008
"""

from __future__ import annotations

from alembic import op

revision = "0009"
down_revision = "0008"
branch_labels = None
depends_on = None

_OLD = "kind in ('statement', 'plan', 'image', 'rejected')"
_NEW = "kind in ('statement', 'plan', 'image', 'voice', 'rejected')"


def upgrade() -> None:
    op.drop_constraint("ck_message_media_kind", "message_media", type_="check")
    op.create_check_constraint("ck_message_media_kind", "message_media", _NEW)


def downgrade() -> None:
    op.drop_constraint("ck_message_media_kind", "message_media", type_="check")
    op.create_check_constraint("ck_message_media_kind", "message_media", _OLD)
