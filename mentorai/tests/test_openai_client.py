"""کلاینت OpenAI، با یک سرور ساختگی HTTP (`httpx2.MockTransport`).

هیچ‌کدام از این آزمون‌ها با OpenAI واقعی حرف نمی‌زنند، پس هیچ‌کدام ثابت نمی‌کنند که API
واقعی همین شکل را می‌پذیرد؛ آن را `mentorai model-check` روز اول روی سرور ثابت می‌کند.
چیزی که اینجا ثابت می‌شود: **آنچه ما می‌فرستیم و آنچه با پاسخ می‌کنیم** — به‌خصوص
قاعده‌هایی که اگر بشکنند هیچ خطایی دیده نمی‌شود (ذخیره‌شدن پیام دانشجو روی سرور
OpenAI، پاسخ بریده‌شده‌ی موفق‌نما، لو رفتن متن پیام در پیام خطا).
"""

from __future__ import annotations

import base64
import json
from collections.abc import Callable
from typing import Any

import httpx2
import pytest

from mentorai.ai import budget
from mentorai.ai.expand import SCHEMA as EXPANSION_SCHEMA
from mentorai.ai.openai_client import OPENAI_EFFORTS, OpenAIClient
from mentorai.ai.schema import JSON_SCHEMA
from mentorai.config import get_settings
from mentorai.memory.extract import EXTRACTION_SCHEMA

KEY = "sk-test-NEVER-PRINT-THIS-1234567890"
STUDENT_TEXT = "متن-خصوصی-دانشجو-نباید-در-خطا-بیاید"

ANSWER = {
    "answer": "دوره مقدماتی شانزده جلسه دارد.",
    "confidence": 0.9,
    "needs_human": False,
    "reason": "منبع رسمی",
    "used_chunk_ids": [1],
}


def _ok(
    text: str | None = None,
    *,
    status: str = "completed",
    output: list[dict[str, Any]] | None = None,
    usage: dict[str, Any] | None = None,
    incomplete: str | None = None,
) -> dict[str, Any]:
    """پاسخ موفق به شکل Responses API."""
    if output is None:
        output = [
            {
                "type": "message",
                "role": "assistant",
                "content": [
                    {
                        "type": "output_text",
                        "text": json.dumps(ANSWER) if text is None else text,
                        "annotations": [],
                    }
                ],
            }
        ]
    body: dict[str, Any] = {
        "id": "resp_1",
        "status": status,
        "output": output,
        "usage": usage or {"input_tokens": 3000, "output_tokens": 400},
    }
    if incomplete is not None:
        body["incomplete_details"] = {"reason": incomplete}
    return body


class Server:
    """سرور ساختگی: درخواست‌ها را ثبت می‌کند و پاسخ‌های از پیش تعیین‌شده را می‌دهد."""

    def __init__(self, *responses: httpx2.Response | Exception) -> None:
        self.responses = list(responses) or [httpx2.Response(200, json=_ok())]
        self.requests: list[httpx2.Request] = []

    def __call__(self, request: httpx2.Request) -> httpx2.Response:
        self.requests.append(request)
        reply = self.responses[min(len(self.requests), len(self.responses)) - 1]
        if isinstance(reply, Exception):
            raise reply
        return reply

    @property
    def sent(self) -> dict[str, Any]:
        return json.loads(self.requests[-1].content)


def _client(server: Callable[..., Any], **kwargs: Any) -> tuple[OpenAIClient, list[float]]:
    sleeps: list[float] = []

    async def fake_sleep(seconds: float) -> None:
        sleeps.append(seconds)

    client = OpenAIClient(
        model=kwargs.pop("model", "gpt-test"),
        api_key=KEY,
        transport=httpx2.MockTransport(server),
        sleep=fake_sleep,
        **kwargs,
    )
    return client, sleeps


def _strict_ok(schema: Any, path: str = "") -> list[str]:
    """مشکلات سازگاری با `strict: true`: هر شیء بسته و همه‌ی کلیدهایش اجباری باشد."""
    problems: list[str] = []
    if not isinstance(schema, dict):
        return problems
    if schema.get("type") == "object":
        if schema.get("additionalProperties") is not False:
            problems.append(f"{path}: additionalProperties باید false باشد")
        props = set(schema.get("properties", {}))
        if set(schema.get("required", [])) != props:
            problems.append(f"{path}: همه‌ی کلیدها باید required باشند")
    for key, value in schema.get("properties", {}).items():
        problems += _strict_ok(value, f"{path}.{key}")
    if "items" in schema:
        problems += _strict_ok(schema["items"], f"{path}[]")
    return problems


# ---------------------------------------------------------------------------
# آنچه فرستاده می‌شود
# ---------------------------------------------------------------------------


async def test_the_request_has_the_shape_the_documentation_describes() -> None:
    server = Server()
    client, _ = _client(server, max_tokens=6000)

    await client.complete(system="دستور سیستم", user="پرسش دانشجو")

    request = server.requests[0]
    assert str(request.url) == "https://api.openai.com/v1/responses"
    assert request.headers["authorization"] == f"Bearer {KEY}"
    sent = server.sent
    assert sent["model"] == "gpt-test"
    assert sent["instructions"] == "دستور سیستم"
    assert sent["input"] == "پرسش دانشجو"
    assert sent["max_output_tokens"] == 6000
    assert sent["text"]["format"] == {
        "type": "json_schema",
        "name": "mentorai_output",
        "strict": True,
        "schema": JSON_SCHEMA,
    }


async def test_nothing_the_student_wrote_is_stored_on_the_provider_side() -> None:
    """پیش‌فرض سرور `store: true` است: ورودی و پاسخ دست‌کم ۳۰ روز آنجا می‌ماند.

    این شکستنی است که هیچ خطایی نمی‌دهد: همه‌چیز کار می‌کند و پیام دانشجو بی‌خبر
    روی سرور شخص ثالث می‌ماند. برای هر سه مسیر باید `false` صریح فرستاده شود.
    """
    server = Server()
    client, _ = _client(server)

    await client.complete(system="س", user="ک")
    assert server.sent["store"] is False
    await client.raw(system="س", user="ک", schema=EXPANSION_SCHEMA)
    assert server.sent["store"] is False
    await client.describe_image(system="س", prompt="ب", image=b"\x89PNG", media_type="image/png")
    assert server.sent["store"] is False


async def test_effort_is_sent_only_when_configured() -> None:
    server = Server()
    client, _ = _client(server)
    await client.complete(system="س", user="ک")
    assert "reasoning" not in server.sent, "مدلی که effort نمی‌شناسد آن را رد می‌کند"

    server = Server()
    client, _ = _client(server, effort="low")
    await client.complete(system="س", user="ک")
    assert server.sent["reasoning"] == {"effort": "low"}
    assert client.effort == "low"


async def test_each_caller_gets_the_output_shape_it_asked_for() -> None:
    server = Server()
    client, _ = _client(server)

    for wanted in (EXTRACTION_SCHEMA, EXPANSION_SCHEMA):
        await client.raw(system="س", user="ک", schema=wanted)
        assert server.sent["text"]["format"]["schema"] == wanted


def test_every_schema_the_system_sends_is_valid_for_strict_mode() -> None:
    """وگرنه OpenAI هر فراخوانی آن مسیر را با ۴۰۰ رد می‌کند و حافظه یا بسط بی‌صدا می‌میرد.

    اگر روزی کسی کلیدی به این شکل‌ها اضافه کند و آن را اجباری نکند، همین‌جا می‌افتد.
    """
    for name, schema in {
        "answer": JSON_SCHEMA,
        "memory": EXTRACTION_SCHEMA,
        "expansion": EXPANSION_SCHEMA,
    }.items():
        assert _strict_ok(schema, name) == []


async def test_an_image_goes_before_its_question_as_a_data_url() -> None:
    server = Server(httpx2.Response(200, json=_ok("نمودار قیمت")))
    client, _ = _client(server)

    call = await client.describe_image(
        system="س", prompt="توصیف کن", image=b"\x89PNG-bytes", media_type="image/png"
    )

    sent = server.sent
    parts = sent["input"][0]["content"]
    assert sent["input"][0]["role"] == "user"
    assert parts[0]["type"] == "input_image"
    assert parts[0]["image_url"] == "data:image/png;base64," + base64.b64encode(
        b"\x89PNG-bytes"
    ).decode("ascii")
    assert parts[1] == {"type": "input_text", "text": "توصیف کن"}
    assert "text" not in sent, "توصیف تصویر متن آزاد است، نه ساختار"
    assert call.text == "نمودار قیمت"


# ---------------------------------------------------------------------------
# آنچه برمی‌گردد
# ---------------------------------------------------------------------------


async def test_a_normal_answer_is_parsed_and_counted() -> None:
    client, _ = _client(Server())

    call = await client.complete(system="س", user="ک")

    assert call.error is None
    assert call.answer is not None and call.answer.confidence == 0.9
    assert call.model == "gpt-test"
    assert (call.input_tokens, call.output_tokens) == (3000, 400)


async def test_cached_tokens_are_not_billed_twice() -> None:
    """در OpenAI، `input_tokens` از قبل شامل توکن‌های نهان است؛ جدا جمع زدنشان دوبار حساب می‌کند."""
    usage = {
        "input_tokens": 3000,
        "output_tokens": 400,
        "input_tokens_details": {"cached_tokens": 2500},
        "output_tokens_details": {"reasoning_tokens": 300},
    }
    client, _ = _client(Server(httpx2.Response(200, json=_ok(usage=usage))))

    call = await client.complete(system="س", user="ک")

    assert call.input_tokens == 3000
    assert call.cache_read_tokens == 0
    assert call.output_tokens == 400, "توکن فکر کردن داخل خروجی است و جدا اضافه نمی‌شود"


async def test_the_text_is_found_even_when_reasoning_comes_first() -> None:
    """مستندات صریحاً می‌گویند `output[0].content[0].text` همیشه متن نیست."""
    output = [
        {"type": "reasoning", "summary": []},
        {"type": "message", "content": [{"type": "output_text", "text": json.dumps(ANSWER)}]},
    ]
    client, _ = _client(Server(httpx2.Response(200, json=_ok(output=output))))

    call = await client.complete(system="س", user="ک")

    assert call.answer is not None


async def test_an_answer_cut_off_by_the_token_cap_is_never_a_success() -> None:
    """حتی اگر متنِ بریده‌شده تصادفاً JSON معتبر باشد."""
    body = _ok(status="incomplete", incomplete="max_output_tokens")  # متن کاملاً معتبر
    client, _ = _client(Server(httpx2.Response(200, json=body)), max_tokens=2048)

    call = await client.complete(system="س", user="ک")

    assert call.answer is None
    assert call.error is not None and "بریده" in call.error and "2048" in call.error
    assert call.output_tokens == 400, "توکن مصرف‌شده حتی در شکست هم پول است"


async def test_a_refusal_is_an_error_not_an_empty_answer() -> None:
    output = [{"type": "message", "content": [{"type": "refusal", "refusal": "نمی‌توانم کمک کنم"}]}]
    client, _ = _client(Server(httpx2.Response(200, json=_ok(output=output))))

    call = await client.complete(system="س", user="ک")

    assert call.answer is None
    assert call.error is not None and "رد کرد" in call.error


@pytest.mark.parametrize(
    "body",
    [
        _ok(status="failed"),
        {**_ok(), "error": {"code": "server_error"}},
        _ok(output=[]),
        _ok(output=[{"type": "message", "content": []}]),
    ],
    ids=["failed", "error-in-body", "no-output", "no-text-part"],
)
async def test_any_other_shape_is_an_error(body: dict[str, Any]) -> None:
    client, _ = _client(Server(httpx2.Response(200, json=body)))

    call = await client.complete(system="س", user="ک")

    assert call.answer is None and call.error


async def test_text_that_is_not_the_expected_json_is_silence() -> None:
    client, _ = _client(Server(httpx2.Response(200, json=_ok("این JSON نیست"))))

    call = await client.complete(system="س", user="ک")

    assert call.answer is None
    assert call.error is not None and "شکل مورد انتظار" in call.error


# ---------------------------------------------------------------------------
# شکست‌ها
# ---------------------------------------------------------------------------


async def test_an_error_never_carries_what_the_provider_echoed_back() -> None:
    """پیام خطای ارائه‌دهنده ممکن است بخشی از پیام دانشجو را بازتاب دهد؛ فقط کد می‌ماند."""
    error = {
        "error": {
            "message": f"Invalid input: {STUDENT_TEXT}",
            "type": "invalid_request_error",
            "code": "unsupported_value",
            "param": "reasoning.effort",
        }
    }
    server = Server(httpx2.Response(400, json=error))
    client, _ = _client(server, effort="low")

    call = await client.complete(system="س", user="ک")

    assert call.answer is None and call.error is not None
    assert STUDENT_TEXT not in call.error
    assert "400" in call.error and "reasoning.effort" in call.error, "علتِ تنظیم دیده شود"
    assert len(server.requests) == 1, "۴۰۰ هرگز تکرار نمی‌شود: همان خطا را دوباره می‌گیرد"


async def test_a_connection_failure_does_not_leak_the_message_or_the_key() -> None:
    boom = httpx2.ConnectError(f"cannot connect {STUDENT_TEXT} {KEY}")
    client, _ = _client(Server(boom, boom, boom))

    call = await client.complete(system="س", user="ک")

    assert call.error is not None
    assert "ConnectError" in call.error
    assert STUDENT_TEXT not in call.error and KEY not in call.error


async def test_a_rate_limit_is_retried_and_the_server_wait_is_honoured() -> None:
    server = Server(
        httpx2.Response(429, headers={"retry-after": "3"}, json={"error": {"code": "rate"}}),
        httpx2.Response(200, json=_ok()),
    )
    client, sleeps = _client(server)

    call = await client.complete(system="س", user="ک")

    assert call.answer is not None
    assert len(server.requests) == 2
    assert sleeps == [3.0]


async def test_a_server_that_keeps_failing_is_given_up_on_after_a_bounded_number_of_tries() -> None:
    server = Server(httpx2.Response(503, json={"error": {"code": "overloaded"}}))
    client, sleeps = _client(server)

    call = await client.complete(system="س", user="ک")

    assert call.answer is None and call.error is not None and "503" in call.error
    # عدد ثابت، نه `MAX_RETRIES`: اگر سقف از خود ماژول وارد شود، با عوض شدنش هر دو طرف
    # مقایسه با هم عوض می‌شوند و تست هرگز نمی‌افتد. هر تلاش اضافه پول یا زمان است.
    assert len(server.requests) == 3
    assert sleeps == [1.0, 2.0]


async def test_a_bad_key_is_not_retried() -> None:
    server = Server(httpx2.Response(401, json={"error": {"code": "invalid_api_key"}}))
    client, sleeps = _client(server)

    call = await client.complete(system="س", user="ک")

    assert call.error is not None and "401" in call.error
    assert len(server.requests) == 1 and sleeps == []


def test_the_key_is_never_part_of_the_objects_text() -> None:
    client, _ = _client(Server())
    assert KEY not in repr(client)


# ---------------------------------------------------------------------------
# پیکربندی هنگام روشن شدن
# ---------------------------------------------------------------------------


@pytest.fixture
def env(monkeypatch: pytest.MonkeyPatch) -> Any:
    for name in (
        "AI_PROVIDER",
        "AI_MODEL",
        "AI_EFFORT",
        "AI_PRICE_INPUT_USD",
        "AI_PRICE_OUTPUT_USD",
        "OPENAI_API_KEY",
        "OPENAI_BASE_URL",
    ):
        monkeypatch.delenv(name, raising=False)

    def _set(**values: str) -> None:
        for key, value in values.items():
            monkeypatch.setenv(key, value)
        get_settings.cache_clear()

    yield _set
    get_settings.cache_clear()


_READY = {
    "AI_PROVIDER": "openai",
    "AI_MODEL": "gpt-test",
    "OPENAI_API_KEY": KEY,
    "AI_PRICE_INPUT_USD": "0.25",
    "AI_PRICE_OUTPUT_USD": "2.0",
}


def test_a_fully_configured_client_starts(env: Any) -> None:
    env(**_READY, AI_EFFORT="low", AI_MAX_TOKENS="5000")

    client = OpenAIClient.from_settings()

    assert client.model == "gpt-test" and client.effort == "low"


@pytest.mark.parametrize(
    ("drop", "message"),
    [
        ("OPENAI_API_KEY", "OPENAI_API_KEY"),
        ("AI_MODEL", "AI_MODEL"),
    ],
)
def test_a_missing_required_setting_stops_the_start(env: Any, drop: str, message: str) -> None:
    values = {k: v for k, v in _READY.items() if k != drop}
    if drop == "AI_MODEL":  # قیمت بدون مدل را خود تنظیمات رد می‌کند
        values.pop("AI_PRICE_INPUT_USD")
        values.pop("AI_PRICE_OUTPUT_USD")
    env(**values)

    with pytest.raises(ValueError, match=message):
        OpenAIClient.from_settings()


def test_a_model_without_a_price_stops_the_start(env: Any) -> None:
    """بدون قیمت، سقف هزینه با نرخ جایگزین حساب می‌شود و عددش واقعی نیست."""
    values = {k: v for k, v in _READY.items() if not k.startswith("AI_PRICE")}
    env(**values)

    with pytest.raises(ValueError, match="قیمت شناخته‌شده ندارد"):
        OpenAIClient.from_settings()


def test_an_effort_the_provider_does_not_know_stops_the_start(env: Any) -> None:
    env(**_READY, AI_EFFORT="turbo")

    with pytest.raises(ValueError, match="AI_EFFORT"):
        OpenAIClient.from_settings()
    assert "turbo" not in OPENAI_EFFORTS


def test_the_owner_price_is_what_the_spending_cap_uses(env: Any) -> None:
    env(**_READY)

    price, known = budget.price_for("gpt-test")
    assert known and (price.input_usd, price.output_usd) == (0.25, 2.0)

    # هزینه‌ی همان ۳۰۰۰ ورودی و ۴۰۰ خروجی: ۳۰۰۰×۰٫۲۵ + ۴۰۰×۲ = ۱۵۵۰ واحد از یک میلیون دلار
    micros, priced = budget.cost_micros("gpt-test", input_tokens=3000, output_tokens=400)
    assert priced and micros == 1550

    # مدلی که مالک قیمتش را نگفته هنوز با گران‌ترین نرخ حساب می‌شود
    assert budget.price_for("gpt-other")[1] is False


@pytest.mark.parametrize(
    "values",
    [
        {"AI_MODEL": "m", "AI_PRICE_INPUT_USD": "1"},  # نیمه‌کاره
        {"AI_PRICE_INPUT_USD": "1", "AI_PRICE_OUTPUT_USD": "2"},  # بی‌نام مدل
    ],
    ids=["half-a-price", "price-without-model"],
)
def test_a_price_that_would_be_silently_ignored_is_refused(
    env: Any, values: dict[str, str]
) -> None:
    from pydantic import ValidationError

    env(**values)

    with pytest.raises(ValidationError):
        get_settings()


@pytest.mark.parametrize("url", ["http://api.example.com/v1", "ftp://x", "api.example.com"])
def test_an_unencrypted_base_url_is_refused(env: Any, url: str) -> None:
    from pydantic import ValidationError

    env(OPENAI_BASE_URL=url)

    with pytest.raises(ValidationError):
        get_settings()


def test_localhost_and_https_urls_are_allowed(env: Any) -> None:
    env(OPENAI_BASE_URL="http://localhost:8080/v1/")
    assert get_settings().openai_base_url == "http://localhost:8080/v1"
    env(OPENAI_BASE_URL="https://llm.example.com/v1")
    assert get_settings().openai_base_url == "https://llm.example.com/v1"
