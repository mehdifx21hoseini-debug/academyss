"""پایگاه دانش: سند، قطعه، جستجوی متنی و برداری.

Revision ID: 0002
Revises: 0001
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "0002"
down_revision = "0001"
branch_labels = None
depends_on = None

# بعد بردار. تغییرش نیاز به مهاجرت و ساخت دوباره‌ی همه‌ی بردارها دارد، پس عمداً یک
# عدد رایج انتخاب شده که با چند مدل چندزبانه‌ی کاندید می‌خواند.
EMBEDDING_DIM = 1024


REQUIRED_EXTENSIONS = ("vector", "pg_trgm")


def _require_extensions() -> None:
    """افزونه‌ها باید از قبل توسط ابرکاربر نصب شده باشند.

    ساختنشان اینجا یعنی نقش برنامه باید ابرکاربر باشد، که برای یک سرویس تولیدی
    قابل قبول نیست. نصبشان یک کار راه‌اندازی است، نه کار مهاجرت.
    """
    bind = op.get_bind()
    installed = {
        row[0]
        for row in bind.execute(
            sa.text("select extname from pg_extension where extname = any(:names)"),
            {"names": list(REQUIRED_EXTENSIONS)},
        )
    }
    missing = [e for e in REQUIRED_EXTENSIONS if e not in installed]
    if missing:
        raise RuntimeError(
            "این افزونه‌های پستگرس نصب نیستند: "
            + ", ".join(missing)
            + ". با کاربر ابرکاربر اجرا کنید: "
            + " ".join(f"CREATE EXTENSION IF NOT EXISTS {e};" for e in missing)
        )


def upgrade() -> None:
    _require_extensions()

    op.create_table(
        "knowledge_documents",
        sa.Column("id", sa.BigInteger, primary_key=True, autoincrement=True),
        # تفکیک ساختاری منبع رسمی از تجربه‌ی منتور. بازیابی می‌تواند روی آن فیلتر کند،
        # تا مثلاً پرسش قیمت هرگز از یک پاسخ قدیمی منتور جواب نگیرد.
        # کلید یکتای بیرونی: وارد کردن دوباره‌ی همان ردیف، به‌روزرسانی می‌کند نه تکرار.
        sa.Column("external_key", sa.String(64), nullable=False, unique=True),
        sa.Column("source_class", sa.String(16), nullable=False),
        sa.Column("authority", sa.String(16), nullable=False),
        sa.Column("category", sa.String(120)),
        sa.Column("title", sa.Text, nullable=False),
        sa.Column("body", sa.Text, nullable=False),
        sa.Column("valid_until", sa.Date),
        sa.Column("owner", sa.String(120)),
        sa.Column("notes", sa.Text),
        sa.Column("active", sa.Boolean, nullable=False, server_default=sa.true()),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()
        ),
        sa.Column(
            "updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()
        ),
        sa.CheckConstraint("source_class in ('official', 'mentor')", name="ck_doc_source_class"),
        sa.CheckConstraint("authority in ('fact', 'policy', 'guidance')", name="ck_doc_authority"),
    )
    op.create_index("ix_knowledge_documents_active", "knowledge_documents", ["active"])

    op.create_table(
        "knowledge_chunks",
        sa.Column("id", sa.BigInteger, primary_key=True, autoincrement=True),
        sa.Column(
            "document_id",
            sa.BigInteger,
            sa.ForeignKey("knowledge_documents.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("ordinal", sa.Integer, nullable=False),
        # متن نمایشی، خوانا، با نیم‌فاصله.
        sa.Column("content", sa.Text, nullable=False),
        # کلید تطبیق: نیم‌فاصله حذف‌شده، حروف و ارقام یکسان‌شده.
        sa.Column("search_text", sa.Text, nullable=False),
        sa.Column("embedding_model", sa.String(120)),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()
        ),
        sa.UniqueConstraint("document_id", "ordinal", name="uq_chunk_document_ordinal"),
    )

    # بردار و بردار متنی هر دو ستون محاسبه‌شده یا وابسته به search_text هستند.
    op.execute(f"alter table knowledge_chunks add column embedding vector({EMBEDDING_DIM})")
    # ستون تولیدشده: نمی‌تواند از search_text واگرا شود، چون جای جداگانه‌ای برای
    # به‌روزرسانی ندارد. پیکربندی simple است، نه arabic: ریشه‌یاب عربی روی فارسی
    # نتیجه‌ی غلط می‌دهد و پستگرس پیکربندی فارسی ندارد.
    op.execute(
        """
        alter table knowledge_chunks
        add column search_vector tsvector
        generated always as (to_tsvector('simple', search_text)) stored
        """
    )

    op.create_index("ix_knowledge_chunks_document_id", "knowledge_chunks", ["document_id"])
    op.execute("create index ix_knowledge_chunks_fts on knowledge_chunks using gin (search_vector)")
    op.execute(
        "create index ix_knowledge_chunks_trgm on knowledge_chunks "
        "using gin (search_text gin_trgm_ops)"
    )
    op.execute(
        "create index ix_knowledge_chunks_embedding on knowledge_chunks "
        "using hnsw (embedding vector_cosine_ops)"
    )


def downgrade() -> None:
    op.drop_table("knowledge_chunks")
    op.drop_table("knowledge_documents")
