"""مدل داده.

منبع حقیقت طرح داده، فایل‌های مهاجرت هستند. این ماژول همان طرح را برای کد بازتاب می‌دهد.

قیدهایی که اینجا هستند تزئینی نیستند. به‌خصوص قید یکتایی روی پیام، مکانیزم تشخیص پیام
تکراری است: درج دوم شکست می‌خورد و همان شکست یعنی «قبلاً دیده شده». این اتمی است، برخلاف
خواندن و بعد نوشتن که بین دو کارگر هم‌زمان مسابقه دارد.
"""

from __future__ import annotations

import enum
from datetime import date, datetime

from pgvector.sqlalchemy import Vector
from sqlalchemy import (
    BigInteger,
    Boolean,
    CheckConstraint,
    Date,
    DateTime,
    Float,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    UniqueConstraint,
    func,
    text,
)
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, relationship


class Base(DeclarativeBase):
    pass


class Sender(enum.StrEnum):
    student = "student"
    assistant = "assistant"
    mentor = "mentor"


class ConversationStatus(enum.StrEnum):
    active = "active"
    awaiting_mentor = "awaiting_mentor"
    closed = "closed"


class JobStatus(enum.StrEnum):
    pending = "pending"
    processing = "processing"
    done = "done"
    failed = "failed"
    dead = "dead"


def _created_at() -> Mapped[datetime]:
    return mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)


class MentorAccount(Base):
    """یک حساب تلگرام آکادمی که یک منتور با آن کار می‌کند."""

    __tablename__ = "mentor_accounts"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    slug: Mapped[str] = mapped_column(String(64), unique=True, nullable=False)
    mentor_name: Mapped[str] = mapped_column(String(200), nullable=False)
    phone: Mapped[str] = mapped_column(String(32), nullable=False)

    telegram_user_id: Mapped[int | None] = mapped_column(BigInteger, unique=True)

    # اثر انگشت دستگاه یک‌بار تعیین و ثابت نگه داشته می‌شود. تغییر مکررش برای تلگرام
    # شبیه ربوده شدن نشست است. جزئیات در docs/TELEGRAM_SAFETY.md.
    device_model: Mapped[str] = mapped_column(String(120), nullable=False)
    system_version: Mapped[str] = mapped_column(String(120), nullable=False)
    app_version: Mapped[str] = mapped_column(String(60), nullable=False)

    # نشست MTProto، رمزنگاری‌شده. خطرناک‌ترین راز سیستم: اختیار کامل حساب را دارد.
    # هرگز لاگ نمی‌شود و هرگز از هیچ رابطی برنمی‌گردد.
    session_encrypted: Mapped[bytes | None] = mapped_column()

    enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default=text("true"))
    # پیش‌نویس یا ارسال مستقیم. سوییچ یک تنظیم است، نه بازنویسی کد (ADR-010).
    reply_mode: Mapped[str] = mapped_column(String(16), nullable=False, server_default="draft")
    # جایی که ربات کنترل با این منتور حرف می‌زند.
    control_chat_id: Mapped[int | None] = mapped_column(BigInteger)
    # کلید قطع دستی. یک حساب بدون توقف بقیه از مدار خارج می‌شود.
    send_paused: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default=text("false"))
    paused_reason: Mapped[str | None] = mapped_column(Text)
    flood_wait_until: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    created_at: Mapped[datetime] = _created_at()

    conversations: Mapped[list[Conversation]] = relationship(back_populates="account")


class Student(Base):
    __tablename__ = "students"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    display_name: Mapped[str | None] = mapped_column(String(300))
    created_at: Mapped[datetime] = _created_at()

    identities: Mapped[list[Identity]] = relationship(back_populates="student")


class Identity(Base):
    """یک هویت تلگرامی. یک دانشجو می‌تواند چند هویت داشته باشد."""

    __tablename__ = "identities"
    __table_args__ = (Index("ix_identities_student_id", "student_id"),)

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    student_id: Mapped[int] = mapped_column(
        ForeignKey("students.id", ondelete="CASCADE"), nullable=False
    )
    telegram_user_id: Mapped[int] = mapped_column(BigInteger, unique=True, nullable=False)
    username: Mapped[str | None] = mapped_column(String(64))
    first_name: Mapped[str | None] = mapped_column(String(200))
    last_name: Mapped[str | None] = mapped_column(String(200))
    created_at: Mapped[datetime] = _created_at()

    student: Mapped[Student] = relationship(back_populates="identities")


class ExcludedChat(Base):
    """گفتگویی که دانشجو نیست: همکار، منتور دیگر، تأمین‌کننده. طبق ADR-008."""

    __tablename__ = "excluded_chats"
    __table_args__ = (
        UniqueConstraint("account_id", "telegram_peer_id", name="uq_excluded_account_peer"),
    )

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    account_id: Mapped[int] = mapped_column(
        ForeignKey("mentor_accounts.id", ondelete="CASCADE"), nullable=False
    )
    telegram_peer_id: Mapped[int] = mapped_column(BigInteger, nullable=False)
    reason: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[datetime] = _created_at()


class Conversation(Base):
    """مکالمه، موجودیت درجه‌یک.

    یکتا به‌ازای هر حساب و گفتگو. اگر یک دانشجو به دو حساب پیام بدهد، دو مکالمه دارد؛
    منتور مسئول از روی همان حسابی که پیام روی آن رسیده تعیین می‌شود (ADR-007).
    """

    __tablename__ = "conversations"
    __table_args__ = (
        UniqueConstraint("account_id", "telegram_chat_id", name="uq_conversation_account_chat"),
        CheckConstraint(
            "status in ('active', 'awaiting_mentor', 'closed')", name="ck_conversation_status"
        ),
        Index("ix_conversations_student_id", "student_id"),
    )

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    account_id: Mapped[int] = mapped_column(
        ForeignKey("mentor_accounts.id", ondelete="CASCADE"), nullable=False
    )
    student_id: Mapped[int] = mapped_column(
        ForeignKey("students.id", ondelete="CASCADE"), nullable=False
    )
    telegram_chat_id: Mapped[int] = mapped_column(BigInteger, nullable=False)

    status: Mapped[str] = mapped_column(
        String(32), nullable=False, server_default=ConversationStatus.active.value
    )
    # خاموش کردن دستیار روی یک گفتگوی مشخص، در هر زمان (ADR-008).
    assistant_enabled: Mapped[bool] = mapped_column(
        Boolean, nullable=False, server_default=text("true")
    )

    # آخرین پیامی که واقعاً پاسخ گرفت. علامت خوانده‌شدن هرگز از این جلوتر نمی‌رود،
    # تا پیام بی‌پاسخ خوانده‌نشده بماند و در تلگرام منتور دیده شود (ADR-009).
    last_answered_message_id: Mapped[int | None] = mapped_column(BigInteger)

    created_at: Mapped[datetime] = _created_at()
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )

    account: Mapped[MentorAccount] = relationship(back_populates="conversations")


class Message(Base):
    __tablename__ = "messages"
    __table_args__ = (
        # تشخیص پیام تکراری. شناسه پیام در تلگرام به‌ازای هر گفتگو یکتاست، و مکالمه
        # خودش به‌ازای حساب و گفتگو یکتاست، پس این جفت کافی است.
        UniqueConstraint(
            "conversation_id", "telegram_message_id", name="uq_message_conversation_tg_id"
        ),
        CheckConstraint("sender in ('student', 'assistant', 'mentor')", name="ck_message_sender"),
        Index("ix_messages_conversation_sent_at", "conversation_id", "sent_at"),
    )

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    conversation_id: Mapped[int] = mapped_column(
        ForeignKey("conversations.id", ondelete="CASCADE"), nullable=False
    )
    telegram_message_id: Mapped[int] = mapped_column(BigInteger, nullable=False)
    sender: Mapped[str] = mapped_column(String(16), nullable=False)

    text: Mapped[str | None] = mapped_column(Text)
    media_type: Mapped[str | None] = mapped_column(String(32))
    reply_to_message_id: Mapped[int | None] = mapped_column(BigInteger)

    sent_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    created_at: Mapped[datetime] = _created_at()


class Job(Base):
    """صف کار در خود پستگرس.

    برداشتن کار با FOR UPDATE SKIP LOCKED انجام می‌شود تا دو کارگر یک کار را برندارند
    و منتظر هم نمانند.
    """

    __tablename__ = "jobs"
    __table_args__ = (
        CheckConstraint(
            "status in ('pending', 'processing', 'done', 'failed', 'dead')", name="ck_job_status"
        ),
        # ایندکس جزئی: فقط کارهای در انتظار خوانده می‌شوند، پس کارهای تمام‌شده
        # اصلاً وارد ایندکس نمی‌شوند و با رشد جدول، برداشتن کار کند نمی‌شود.
        Index(
            "ix_jobs_pending",
            "run_after",
            "id",
            postgresql_where=text("status = 'pending'"),
        ),
    )

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    kind: Mapped[str] = mapped_column(String(64), nullable=False)
    payload: Mapped[str] = mapped_column(Text, nullable=False)

    status: Mapped[str] = mapped_column(
        String(16), nullable=False, server_default=JobStatus.pending.value
    )
    attempts: Mapped[int] = mapped_column(Integer, nullable=False, server_default="0")
    max_attempts: Mapped[int] = mapped_column(Integer, nullable=False, server_default="5")
    last_error: Mapped[str | None] = mapped_column(Text)

    run_after: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    locked_by: Mapped[str | None] = mapped_column(String(64))
    locked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    created_at: Mapped[datetime] = _created_at()


class DuplicateDelivery(Base):
    """شمارش تحویل تکراری.

    پیام تکراری بی‌صدا دور انداخته نمی‌شود؛ ثبت می‌شود تا نرخ تکرار قابل اندازه‌گیری
    بماند. سیستم قبلی همین را نداشت و نرخش هرگز معلوم نشد.
    """

    __tablename__ = "duplicate_deliveries"
    __table_args__ = (Index("ix_duplicate_deliveries_seen_at", "seen_at"),)

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    account_id: Mapped[int] = mapped_column(BigInteger, nullable=False)
    telegram_chat_id: Mapped[int] = mapped_column(BigInteger, nullable=False)
    telegram_message_id: Mapped[int] = mapped_column(BigInteger, nullable=False)
    seen_at: Mapped[datetime] = _created_at()


class AuditLog(Base):
    """چه کسی چه چیزی را دید یا تغییر داد. بدون محتوای پیام."""

    __tablename__ = "audit_log"
    __table_args__ = (Index("ix_audit_log_created_at", "created_at"),)

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    actor: Mapped[str] = mapped_column(String(120), nullable=False)
    action: Mapped[str] = mapped_column(String(64), nullable=False)
    target: Mapped[str | None] = mapped_column(String(200))
    detail: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[datetime] = _created_at()


# بعد بردار. تغییرش نیاز به مهاجرت و ساخت دوباره‌ی همه‌ی بردارها دارد.
EMBEDDING_DIM = 1024


class SourceClass(enum.StrEnum):
    """تفکیک ساختاری منبع.

    محتوای رسمی آکادمی می‌تواند به‌عنوان واقعیت بیان شود. پاسخ تجربی منتور برای لحن و
    موضوعات آموزشی به کار می‌رود، ولی هرگز مرجع قیمت و قانون و شرط نیست.
    """

    official = "official"
    mentor = "mentor"


class Authority(enum.StrEnum):
    fact = "fact"
    policy = "policy"
    guidance = "guidance"


class KnowledgeDocument(Base):
    __tablename__ = "knowledge_documents"
    __table_args__ = (
        CheckConstraint("source_class in ('official', 'mentor')", name="ck_doc_source_class"),
        CheckConstraint("authority in ('fact', 'policy', 'guidance')", name="ck_doc_authority"),
        Index("ix_knowledge_documents_active", "active"),
    )

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    external_key: Mapped[str] = mapped_column(String(64), unique=True, nullable=False)
    source_class: Mapped[str] = mapped_column(String(16), nullable=False)
    authority: Mapped[str] = mapped_column(String(16), nullable=False)
    category: Mapped[str | None] = mapped_column(String(120))
    title: Mapped[str] = mapped_column(Text, nullable=False)
    body: Mapped[str] = mapped_column(Text, nullable=False)
    # تاریخ انقضا برای چیزهایی مثل قیمت. سند منقضی از بازیابی کنار می‌رود.
    valid_until: Mapped[date | None] = mapped_column(Date)
    owner: Mapped[str | None] = mapped_column(String(120))
    notes: Mapped[str | None] = mapped_column(Text)
    active: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default=text("true"))
    created_at: Mapped[datetime] = _created_at()
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )


class KnowledgeChunk(Base):
    __tablename__ = "knowledge_chunks"
    __table_args__ = (
        UniqueConstraint("document_id", "ordinal", name="uq_chunk_document_ordinal"),
        Index("ix_knowledge_chunks_document_id", "document_id"),
    )

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    document_id: Mapped[int] = mapped_column(
        ForeignKey("knowledge_documents.id", ondelete="CASCADE"), nullable=False
    )
    ordinal: Mapped[int] = mapped_column(Integer, nullable=False)
    content: Mapped[str] = mapped_column(Text, nullable=False)
    search_text: Mapped[str] = mapped_column(Text, nullable=False)
    embedding: Mapped[list[float] | None] = mapped_column(Vector(EMBEDDING_DIM))
    embedding_model: Mapped[str | None] = mapped_column(String(120))
    created_at: Mapped[datetime] = _created_at()


class ReplyMode(enum.StrEnum):
    draft = "draft"
    auto = "auto"


class Outcome(enum.StrEnum):
    answer = "answer"
    silence = "silence"


class DraftStatus(enum.StrEnum):
    pending = "pending"
    approved = "approved"
    edited = "edited"
    rejected = "rejected"
    sent = "sent"
    failed = "failed"


class AiRun(Base):
    """هر فراخوانی و هر تصمیم، با همه‌ی چیزی که برای بازخوانی لازم است.

    این جدول پاسخ پرسش «چرا سیستم این‌طور رفتار کرد» است. یک اجرا به‌ازای هر پیام، تا
    تلاش دوباره‌ی یک کار رکورد دوم نسازد.
    """

    __tablename__ = "ai_runs"
    __table_args__ = (
        CheckConstraint("outcome in ('answer', 'silence')", name="ck_ai_run_outcome"),
        UniqueConstraint("message_id", name="uq_ai_run_message"),
        Index("ix_ai_runs_conversation", "conversation_id", "created_at"),
        Index("ix_ai_runs_created_at", "created_at"),
    )

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    conversation_id: Mapped[int] = mapped_column(
        ForeignKey("conversations.id", ondelete="CASCADE"), nullable=False
    )
    message_id: Mapped[int] = mapped_column(
        ForeignKey("messages.id", ondelete="CASCADE"), nullable=False
    )
    outcome: Mapped[str] = mapped_column(String(16), nullable=False)
    reason: Mapped[str] = mapped_column(String(64), nullable=False)
    confidence: Mapped[float | None] = mapped_column(Float)
    model: Mapped[str | None] = mapped_column(String(120))
    prompt_version: Mapped[str] = mapped_column(String(32), nullable=False)
    effort: Mapped[str | None] = mapped_column(String(16))
    latency_ms: Mapped[int | None] = mapped_column(Integer)
    input_tokens: Mapped[int | None] = mapped_column(Integer)
    output_tokens: Mapped[int | None] = mapped_column(Integer)
    cache_read_tokens: Mapped[int | None] = mapped_column(Integer)
    retrieved: Mapped[list[dict[str, object]]] = mapped_column(
        JSONB, nullable=False, server_default="[]"
    )
    response_text: Mapped[str | None] = mapped_column(Text)
    error: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[datetime] = _created_at()


class Draft(Base):
    """پاسخ پیشنهادی که منتظر تأیید منتور است."""

    __tablename__ = "drafts"
    __table_args__ = (
        CheckConstraint(
            "status in ('pending', 'approved', 'edited', 'rejected', 'sent', 'failed')",
            name="ck_draft_status",
        ),
        UniqueConstraint("ai_run_id", name="uq_draft_ai_run"),
    )

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    ai_run_id: Mapped[int] = mapped_column(
        ForeignKey("ai_runs.id", ondelete="CASCADE"), nullable=False
    )
    conversation_id: Mapped[int] = mapped_column(
        ForeignKey("conversations.id", ondelete="CASCADE"), nullable=False
    )
    proposed_text: Mapped[str] = mapped_column(Text, nullable=False)
    final_text: Mapped[str | None] = mapped_column(Text)
    status: Mapped[str] = mapped_column(String(16), nullable=False, server_default="pending")
    decided_by: Mapped[str | None] = mapped_column(String(120))
    decided_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    control_message_id: Mapped[int | None] = mapped_column(BigInteger)
    created_at: Mapped[datetime] = _created_at()


class Escalation(Base):
    """پیامی که به منتور سپرده شده.

    برای دانشجو نامرئی است (ADR-009)، پس بدون این ثبت هیچ راهی برای فهمیدن اینکه چند
    پیام بی‌پاسخ مانده و چقدر منتظرند وجود ندارد.
    """

    __tablename__ = "escalations"
    __table_args__ = (UniqueConstraint("message_id", name="uq_escalation_message"),)

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    conversation_id: Mapped[int] = mapped_column(
        ForeignKey("conversations.id", ondelete="CASCADE"), nullable=False
    )
    message_id: Mapped[int] = mapped_column(
        ForeignKey("messages.id", ondelete="CASCADE"), nullable=False
    )
    ai_run_id: Mapped[int | None] = mapped_column(ForeignKey("ai_runs.id", ondelete="SET NULL"))
    reason: Mapped[str] = mapped_column(String(64), nullable=False)
    created_at: Mapped[datetime] = _created_at()
    resolved_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    resolved_by: Mapped[str | None] = mapped_column(String(120))


class MemorySource(enum.StrEnum):
    extracted = "extracted"
    mentor = "mentor"


class StudentMemory(Base):
    """حافظه‌ی بلندمدت دانشجو.

    فقط چیزهایی که از سیاست حافظه رد شده‌اند اینجا می‌آیند. حذف دانشجو این‌ها را هم
    می‌برد؛ همان قاعده‌ای که در راهنمای امنیت آمده.
    """

    __tablename__ = "student_memories"
    __table_args__ = (
        CheckConstraint(
            "category in ('course', 'learning_stage', 'interest', 'goal', 'constraint', 'note')",
            name="ck_memory_category",
        ),
        CheckConstraint("source in ('extracted', 'mentor')", name="ck_memory_source"),
    )

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    student_id: Mapped[int] = mapped_column(
        ForeignKey("students.id", ondelete="CASCADE"), nullable=False
    )
    account_id: Mapped[int | None] = mapped_column(
        ForeignKey("mentor_accounts.id", ondelete="SET NULL")
    )
    category: Mapped[str] = mapped_column(String(32), nullable=False)
    content: Mapped[str] = mapped_column(Text, nullable=False)
    content_key: Mapped[str] = mapped_column(String(200), nullable=False)
    confidence: Mapped[float] = mapped_column(Float, nullable=False)
    source: Mapped[str] = mapped_column(String(16), nullable=False)
    source_message_id: Mapped[int | None] = mapped_column(
        ForeignKey("messages.id", ondelete="SET NULL")
    )
    active: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default=text("true"))
    superseded_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = _created_at()


class MemoryRejection(Base):
    """یافته‌ای که سیاست ردش کرد. محتوای ردشده عمداً ذخیره نمی‌شود."""

    __tablename__ = "memory_rejections"
    __table_args__ = (Index("ix_memory_rejections_created_at", "created_at"),)

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    student_id: Mapped[int] = mapped_column(
        ForeignKey("students.id", ondelete="CASCADE"), nullable=False
    )
    category: Mapped[str | None] = mapped_column(String(32))
    reason: Mapped[str] = mapped_column(String(32), nullable=False)
    detail: Mapped[str | None] = mapped_column(String(64))
    created_at: Mapped[datetime] = _created_at()


class PanelRole(enum.StrEnum):
    mentor = "mentor"
    admin = "admin"


class PanelUser(Base):
    """کاربر پنل مدیریت.

    هیچ ستون رمز متن ساده‌ای اینجا نیست و هرگز نباید اضافه شود.
    """

    __tablename__ = "panel_users"
    __table_args__ = (
        CheckConstraint("role in ('mentor', 'admin')", name="ck_panel_user_role"),
        CheckConstraint(
            "(role = 'admin' and account_id is null) or "
            "(role = 'mentor' and account_id is not null)",
            name="ck_panel_user_account_matches_role",
        ),
    )

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    username: Mapped[str] = mapped_column(String(64), unique=True, nullable=False)
    display_name: Mapped[str] = mapped_column(String(200), nullable=False)
    password_hash: Mapped[str] = mapped_column(Text, nullable=False)
    role: Mapped[str] = mapped_column(String(16), nullable=False)
    account_id: Mapped[int | None] = mapped_column(
        ForeignKey("mentor_accounts.id", ondelete="RESTRICT")
    )
    active: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default=text("true"))
    created_at: Mapped[datetime] = _created_at()
    last_login_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class PanelSession(Base):
    """نشست پنل. فقط هش توکن ذخیره می‌شود، نه خود توکن."""

    __tablename__ = "panel_sessions"
    # فقط نشست‌های باطل‌نشده. نشست‌های باطل‌شده برای بازبینی می‌مانند ولی در
    # نمایه‌ی جست‌وجو جایی ندارند.
    __table_args__ = (
        Index(
            "ix_panel_sessions_live",
            "user_id",
            postgresql_where=text("revoked_at is null"),
        ),
    )

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    token_hash: Mapped[str] = mapped_column(String(64), unique=True, nullable=False)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("panel_users.id", ondelete="CASCADE"), nullable=False
    )
    created_at: Mapped[datetime] = _created_at()
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    source_ip: Mapped[str | None] = mapped_column(String(64))
