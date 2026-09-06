"""پنل مدیریت.

سه تصمیم که شکل این ماژول را تعیین کرده‌اند:

**پنل مسیر خصوصی به داده ندارد.** هر خواندنی از `mentorai.access` یا از پرس‌وجوهایی
می‌گذرد که محدودسازی را داخل خود پرس‌وجو دارند. اگر پنل کوئری مستقیم می‌زد، دامنه‌ی
دسترسی منتور دو پیاده‌سازی داشت و دیر یا زود یکی از آن دو عقب می‌ماند.

**رندر سمت سرور.** برای سه منتور و یک مدیر، یک برنامه‌ی تک‌صفحه‌ای فقط یک مرحله‌ی
ساخت و یک سطح وابستگی اضافه می‌کند. اینجا HTML آماده می‌رود و همان اول کار می‌کند.

**پنل چیزی به تلگرام نمی‌فرستد.** هر ارسالی از کارگر و از دروازه‌ی ایمنی حساب
می‌گذرد. مسیر دومی برای ارسال یعنی مسیری که سقف نرخ و ساعت سکوت را نمی‌بیند.
"""

from __future__ import annotations

from collections.abc import AsyncIterator, Awaitable, Callable
from datetime import UTC, datetime
from pathlib import Path
from typing import Annotated

from fastapi import Depends, FastAPI, Form, HTTPException, Request, Response, status
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from sqlalchemy.ext.asyncio import AsyncSession

from mentorai import access, escalation
from mentorai.access import NotPermitted, Principal, Role
from mentorai.db.models import AuditLog, PanelUser
from mentorai.db.session import get_sessionmaker
from mentorai.web import csrf, fmt, labels, queries, security

_HERE = Path(__file__).resolve().parent


async def _session_dependency() -> AsyncIterator[AsyncSession]:
    """یک تراکنش به‌ازای هر درخواست.

    تثبیت در پایان درخواست انجام می‌شود، پس ثبت بازبینی که لایه‌ی دسترسی اضافه می‌کند
    هم با همان تراکنش می‌رود و مسیری نمی‌ماند که داده خوانده شود ولی ثبتش گم شود.
    """
    async with get_sessionmaker()() as session:
        try:
            yield session
            await session.commit()
        except Exception:
            await session.rollback()
            raise


def _template_globals() -> dict[str, object]:
    return {
        "silence_reason": labels.silence_reason,
        "media_refusal": labels.media_refusal,
        "conversation_status": labels.conversation_status,
        "sender_label": labels.sender,
        "source_class": labels.source_class,
        "authority": labels.authority,
        "csrf_field": csrf.FIELD,
        "digits": fmt.digits,
        "datetime_label": fmt.datetime_label,
        "date_label": fmt.date_label,
        "duration_label": fmt.duration_label,
        "bar_class": fmt.bar_class,
        "percent_label": fmt.percent_label,
    }


def create_app() -> FastAPI:
    app = FastAPI(title="MENTORAI", docs_url=None, redoc_url=None, openapi_url=None)
    templates = Jinja2Templates(directory=str(_HERE / "templates"))
    templates.env.globals.update(_template_globals())
    app.mount("/static", StaticFiles(directory=str(_HERE / "static")), name="static")
    app.state.templates = templates

    @app.middleware("http")
    async def security_headers(
        request: Request, call_next: Callable[[Request], Awaitable[Response]]
    ) -> Response:
        """سرآیندهای امنیتی روی هر پاسخ.

        سیاست محتوا هیچ منبع بیرونی را مجاز نمی‌کند: قلم و شیوه‌نامه هر دو از خود
        سرور می‌آیند. پنل چیزی از CDN نمی‌گیرد، چون هر دامنه‌ی مجاز یک راه اضافه برای
        تزریق است و اینجا لازم نیست.
        """
        response = await call_next(request)
        response.headers["Content-Security-Policy"] = (
            "default-src 'none'; style-src 'self'; font-src 'self'; img-src 'self'; "
            "form-action 'self'; frame-ancestors 'none'; base-uri 'none'"
        )
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["Referrer-Policy"] = "same-origin"
        response.headers["X-Frame-Options"] = "DENY"
        return response

    _register_routes(app)
    return app


class Viewer:
    """کاربر واردشده به‌همراه چیزهایی که هر مسیر به آن نیاز دارد."""

    def __init__(self, user: PanelUser, token: str) -> None:
        self.user = user
        self.token = token
        self.principal: Principal = security.principal_for(user)

    @property
    def csrf_token(self) -> str:
        return csrf.token_for(self.token)

    @property
    def is_admin(self) -> bool:
        return self.principal.role is Role.admin


class LoginRequired(Exception):
    """کاربر وارد نشده. به صفحه‌ی ورود هدایت می‌شود، نه خطای خام."""


async def current_viewer(
    request: Request, session: Annotated[AsyncSession, Depends(_session_dependency)]
) -> Viewer:
    token = request.cookies.get(security.SESSION_COOKIE)
    user = await security.resolve_session(session, token)
    if user is None or token is None:
        raise LoginRequired
    return Viewer(user, token)


ViewerDep = Annotated[Viewer, Depends(current_viewer)]
SessionDep = Annotated[AsyncSession, Depends(_session_dependency)]


def _require_csrf(request: Request, viewer: Viewer, submitted: str | None) -> None:
    if not csrf.valid(viewer.token, submitted):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "توکن فرم نامعتبر است")
    # سرآیند مبدأ لایه‌ی دوم است. توکن به‌تنهایی کافی است، ولی این یکی هیچ هزینه‌ای
    # ندارد و در برابر اشتباه در تنظیم کوکی هم می‌ایستد.
    origin = request.headers.get("origin")
    if origin is not None and origin != str(request.base_url).rstrip("/"):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "مبدأ درخواست نامعتبر است")


def _render(request: Request, name: str, viewer: Viewer | None, **context: object) -> HTMLResponse:
    templates: Jinja2Templates = request.app.state.templates
    return templates.TemplateResponse(
        request=request,
        name=name,
        context={"viewer": viewer, **context},
    )


def _register_routes(app: FastAPI) -> None:
    @app.exception_handler(LoginRequired)
    async def _login_required(request: Request, _: Exception) -> Response:
        return RedirectResponse("/login", status_code=status.HTTP_303_SEE_OTHER)

    @app.exception_handler(NotPermitted)
    async def _not_permitted(request: Request, _: Exception) -> Response:
        # «اجازه نداری» و «وجود ندارد» یک پاسخ می‌گیرند. تفکیکشان به منتور می‌گوید کدام
        # شناسه‌ها واقعی‌اند، و از آنجا می‌شود فهمید منتور دیگر چند مکالمه دارد.
        response = _render(request, "not_found.html", None)
        response.status_code = status.HTTP_404_NOT_FOUND
        return response

    @app.get("/login", response_class=HTMLResponse)
    async def login_form(request: Request) -> HTMLResponse:
        return _render(request, "login.html", None, error=None)

    @app.post("/login")
    async def login(
        request: Request,
        session: SessionDep,
        username: Annotated[str, Form()],
        password: Annotated[str, Form()],
    ) -> Response:
        user = await security.authenticate(session, username=username, password=password)
        if user is None:
            session.add(AuditLog(actor=f"panel:{username[:60]}", action="login_failed"))
            # پیام خطا عمداً یکی است. «کاربر پیدا نشد» به مهاجم می‌گوید کدام نام
            # کاربری وجود دارد.
            return _render(request, "login.html", None, error="نام کاربری یا رمز درست نیست")

        token = await security.create_session(
            session, user, source_ip=request.client.host if request.client else None
        )
        session.add(AuditLog(actor=f"panel:{user.username}", action="login"))
        response = RedirectResponse("/", status_code=status.HTTP_303_SEE_OTHER)
        response.set_cookie(
            security.SESSION_COOKIE,
            token,
            httponly=True,
            samesite="lax",
            # در محیط تولید پنل پشت HTTPS است. اینجا سخت‌گیرانه علامت می‌خورد تا
            # مرورگر هرگز این کوکی را روی اتصال رمزنگاری‌نشده نفرستد.
            secure=True,
            max_age=int(security.SESSION_LIFETIME.total_seconds()),
            path="/",
        )
        return response

    @app.post("/logout")
    async def logout(
        request: Request,
        session: SessionDep,
        viewer: ViewerDep,
        csrf_token: Annotated[str | None, Form()] = None,
    ) -> Response:
        _require_csrf(request, viewer, csrf_token)
        await security.revoke_session(session, viewer.token)
        session.add(AuditLog(actor=viewer.principal.label, action="logout"))
        response = RedirectResponse("/login", status_code=status.HTTP_303_SEE_OTHER)
        response.delete_cookie(security.SESSION_COOKIE, path="/")
        return response

    @app.get("/", response_class=HTMLResponse)
    async def dashboard(request: Request, session: SessionDep, viewer: ViewerDep) -> HTMLResponse:
        kpis = await queries.kpis(session, viewer.principal)
        return _render(request, "dashboard.html", viewer, kpis=kpis)

    @app.get("/conversations", response_class=HTMLResponse)
    async def conversation_list(
        request: Request, session: SessionDep, viewer: ViewerDep
    ) -> HTMLResponse:
        rows = await queries.conversation_rows(session, viewer.principal)
        return _render(request, "conversations.html", viewer, rows=rows)

    @app.get("/conversations/{conversation_id}", response_class=HTMLResponse)
    async def conversation_detail(
        request: Request, session: SessionDep, viewer: ViewerDep, conversation_id: int
    ) -> HTMLResponse:
        conversation = await access.get_conversation(session, viewer.principal, conversation_id)
        student = await access.get_student(session, viewer.principal, conversation.student_id)
        timeline = await queries.messages_with_runs(session, conversation.id)
        return _render(
            request,
            "conversation.html",
            viewer,
            conversation=conversation,
            student=student,
            timeline=timeline,
        )

    @app.post("/conversations/{conversation_id}/assistant")
    async def toggle_assistant(
        request: Request,
        session: SessionDep,
        viewer: ViewerDep,
        conversation_id: int,
        enabled: Annotated[str, Form()],
        csrf_token: Annotated[str | None, Form()] = None,
    ) -> Response:
        """خاموش و روشن کردن دستیار روی یک گفتگو (ADR-008)."""
        _require_csrf(request, viewer, csrf_token)
        conversation = await access.get_conversation(session, viewer.principal, conversation_id)
        conversation.assistant_enabled = enabled == "on"
        session.add(
            AuditLog(
                actor=viewer.principal.label,
                action="assistant_enabled" if conversation.assistant_enabled else "assistant_off",
                target=str(conversation.id),
            )
        )
        return RedirectResponse(
            f"/conversations/{conversation_id}", status_code=status.HTTP_303_SEE_OTHER
        )

    @app.get("/escalations", response_class=HTMLResponse)
    async def escalation_list(
        request: Request, session: SessionDep, viewer: ViewerDep
    ) -> HTMLResponse:
        rows = await queries.open_escalation_rows(session, viewer.principal)
        return _render(request, "escalations.html", viewer, rows=rows, now=datetime.now(UTC))

    @app.post("/conversations/{conversation_id}/resolve")
    async def resolve(
        request: Request,
        session: SessionDep,
        viewer: ViewerDep,
        conversation_id: int,
        csrf_token: Annotated[str | None, Form()] = None,
    ) -> Response:
        """بستن ارجاع‌های باز یک مکالمه و برگرداندن دستیار.

        مسیر از خود مکالمه می‌گذرد و نه از شناسه‌ی ارجاع، تا بررسی دسترسی همان بررسی
        همیشگی باشد و مسیر میان‌بری برای رسیدن به مکالمه‌ی منتور دیگر نماند.
        """
        _require_csrf(request, viewer, csrf_token)
        conversation = await access.get_conversation(session, viewer.principal, conversation_id)
        await escalation.resolve_open(session, conversation.id, by=viewer.principal.label)
        await escalation.resume_now(session, conversation, by=viewer.principal.label)
        return RedirectResponse("/escalations", status_code=status.HTTP_303_SEE_OTHER)

    @app.get("/knowledge", response_class=HTMLResponse)
    async def knowledge(request: Request, session: SessionDep, viewer: ViewerDep) -> HTMLResponse:
        rows = await queries.knowledge_rows(session)
        return _render(request, "knowledge.html", viewer, rows=rows, today=datetime.now(UTC).date())


app = create_app()
