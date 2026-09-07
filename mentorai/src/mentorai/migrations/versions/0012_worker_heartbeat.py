"""امضای زنده بودن کارگر، تا پنل بتواند سلامتش را بگوید.

Revision ID: 0012
Revises: 0011
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects.postgresql import JSONB

revision = "0012"
down_revision = "0011"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "worker_heartbeats",
        sa.Column("worker_id", sa.String(64), primary_key=True),
        sa.Column(
            "updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.Column("detail", JSONB, nullable=False, server_default="{}"),
    )


def downgrade() -> None:
    op.drop_table("worker_heartbeats")
