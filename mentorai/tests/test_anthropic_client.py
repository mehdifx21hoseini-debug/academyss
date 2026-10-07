"""کلاینت واقعی Anthropic، بدون شبکه.

تا اینجا فقط `ScriptedClient` آزموده می‌شد؛ هر آنچه به API واقعی می‌رود — نام مدل،
سقف توکن، مهلت، و تفسیر «چرا مدل ایستاد» — هیچ آزمونی نداشت. این فایل یک
`AsyncAnthropic` ساختگی می‌گذارد که دقیقاً همان پارامترهایی را که فرستاده می‌شوند ثبت
می‌کند.
"""

from __future__ import annotations

import json
from types import SimpleNamespace
from typing import Any

import pytest

from mentorai.ai import budget
from mentorai.ai.client import AnthropicClient
from mentorai.config import get_settings

ANSWER = {
    "answer": "دوره مقدماتی شانزده جلسه دارد.",
    "confidence": 0.9,
    "needs_human": False,
    "reason": "منبع رسمی",
    "used_chunk_ids": [1],
}


def _response(
    *, text: str | None = None, stop_reason: str = "end_turn", details: Any = None
) -> SimpleNamespace:
    content = [SimpleNamespace(type="text", text=text if text is not None else json.dumps(ANSWER))]
    return SimpleNamespace(
        content=content,
        usage=SimpleNamespace(input_tokens=3000, output_tokens=400, cache_read_input_tokens=0),
        stop_reason=stop_reason,
        stop_details=details,
    )


class _Messages:
    def __init__(self, response: SimpleNamespace) -> None:
        self._response = response
        self.sent: dict[str, Any] = {}

    async def create(self, **kwargs: Any) -> SimpleNamespace:
        self.sent = kwargs
        return self._response


@pytest.fixture
def fake_api(monkeypatch: pytest.MonkeyPatch) -> Any:
    """جایگزین `anthropic.AsyncAnthropic` که آخرین نمونه و پارامترهایش را نگه می‌دارد."""
    state = SimpleNamespace(response=_response(), client=None)

    class FakeAsyncAnthropic:
        def __init__(self, **kwargs: Any) -> None:
            self.init_kwargs = kwargs
            self.messages = _Messages(state.response)
            state.client = self

    import anthropic

    monkeypatch.setattr(anthropic, "AsyncAnthropic", FakeAsyncAnthropic)
    return state


@pytest.fixture
def env(monkeypatch: pytest.MonkeyPatch) -> Any:
    """تنظیم یک متغیر محیطی و پاک کردن حافظه‌ی نهان تنظیمات، قبل و بعد."""

    def _set(**values: str) -> None:
        for key, value in values.items():
            monkeypatch.setenv(key, value)
        get_settings.cache_clear()

    yield _set
    get_settings.cache_clear()


# ---------------------------------------------------------------------------
# آنچه به API می‌رسد
# ---------------------------------------------------------------------------


async def test_the_configured_model_and_limits_are_what_the_api_receives(
    fake_api: Any, env: Any
) -> None:
    env(
        AI_MODEL="claude-opus-5-5",
        AI_EFFORT="low",
        AI_MAX_TOKENS="6000",
        AI_TIMEOUT_SECONDS="75",
    )
    client = AnthropicClient.from_settings()

    call = await client.complete(system="س", user="پرسش")

    sent = fake_api.client.messages.sent
    assert sent["model"] == "claude-opus-5-5"
    assert sent["max_tokens"] == 6000
    assert sent["output_config"]["effort"] == "low"
    assert sent["output_config"]["format"]["type"] == "json_schema"
    assert fake_api.client.init_kwargs["timeout"] == 75
    assert call.answer is not None
    assert call.model == "claude-opus-5-5", "نام مدل واقعی در ثبت اجرا می‌آید"


def test_the_defaults_are_the_chosen_model_with_room_to_think(fake_api: Any, env: Any) -> None:
    env()
    settings = get_settings()
    client = AnthropicClient.from_settings()

    assert settings.ai_provider == "anthropic"
    assert client.model == "claude-sonnet-5-5"
    assert client.effort == "medium"
    # فکر کردن مدل از همین سقف کم می‌شود. ۲۰۴۸ پیشین پاسخ را نصفه می‌گذاشت.
    assert settings.ai_max_tokens >= 4096


def test_every_model_the_settings_can_pick_by_default_has_a_price(fake_api: Any, env: Any) -> None:
    """وگرنه سقف هزینه با نرخ جایگزین حساب می‌شود و عددش دیگر واقعی نیست."""
    env()
    assert AnthropicClient.from_settings().model in budget.PRICES
    for model in ("claude-opus-5-5", "claude-sonnet-5-5"):
        assert budget.price_for(model)[1], f"{model} در جدول قیمت نیست"


def test_the_prices_match_the_official_table() -> None:
    assert budget.PRICES["claude-opus-5-5"] == budget.Price(4.00, 20.00)
    assert budget.PRICES["claude-sonnet-5-5"] == budget.Price(2.00, 10.00)


# ---------------------------------------------------------------------------
# پاسخی که کامل نیست
# ---------------------------------------------------------------------------


async def test_an_answer_cut_off_by_the_token_cap_is_never_a_success(
    fake_api: Any, env: Any
) -> None:
    """حتی اگر متنِ بریده‌شده تصادفاً JSON معتبر باشد.

    فکر کردن مدل از سقف توکن کم می‌شود؛ بریده شدن یعنی سقف کم است، و پاسخی که
    نصفه مانده نباید به دانشجو برسد.
    """
    fake_api.response = _response(stop_reason="max_tokens")  # متن کاملاً معتبر
    env()
    client = AnthropicClient.from_settings()
    fake_api.client.messages._response = fake_api.response

    call = await client.complete(system="س", user="پرسش")

    assert call.answer is None
    assert call.error is not None and "بریده" in call.error
    assert call.output_tokens == 400, "توکن مصرف‌شده حتی در شکست هم پول است"


async def test_a_refusal_is_an_error_not_an_empty_answer(fake_api: Any, env: Any) -> None:
    fake_api.response = _response(
        text="", stop_reason="refusal", details=SimpleNamespace(category="cyber")
    )
    env()
    client = AnthropicClient.from_settings()
    fake_api.client.messages._response = fake_api.response

    call = await client.complete(system="س", user="پرسش")

    assert call.answer is None
    assert call.error is not None and "cyber" in call.error


async def test_a_normal_finish_is_parsed(fake_api: Any, env: Any) -> None:
    env()
    client = AnthropicClient.from_settings()

    call = await client.complete(system="س", user="پرسش")

    assert call.error is None
    assert call.answer is not None and call.answer.confidence == 0.9


# ---------------------------------------------------------------------------
# مدل نامناسب هنگام روشن شدن رد می‌شود
# ---------------------------------------------------------------------------


def test_a_mistyped_model_name_stops_the_start_not_every_call(fake_api: Any, env: Any) -> None:
    """وگرنه از بیرون «همه‌چیز سالم است، فقط جواب نمی‌دهد» دیده می‌شود."""
    env(AI_MODEL="claude-sonet-5-5")

    with pytest.raises(ValueError, match="قیمت شناخته‌شده ندارد"):
        AnthropicClient.from_settings()


def test_a_model_that_rejects_the_effort_parameter_is_refused_at_start(
    fake_api: Any, env: Any
) -> None:
    """Haiku 4.5 پارامتر effort را نمی‌پذیرد؛ این کلاینت همیشه آن را می‌فرستد."""
    env(AI_MODEL="claude-haiku-4-5")

    with pytest.raises(ValueError, match="effort"):
        AnthropicClient.from_settings()


def test_an_unknown_effort_level_is_refused_at_start(fake_api: Any, env: Any) -> None:
    env(AI_EFFORT="turbo")

    with pytest.raises(ValueError, match="AI_EFFORT"):
        AnthropicClient.from_settings()


# ---------------------------------------------------------------------------
# شکل خروجی که هر مصرف‌کننده می‌خواهد
# ---------------------------------------------------------------------------


async def test_each_caller_gets_the_output_shape_it_asked_for(fake_api: Any, env: Any) -> None:
    """باگی که تا اینجا دیده نشده بود: `raw()` آرگومان `schema` را نادیده می‌گرفت.

    حافظه‌ی دانشجو و بسط دستور منتور هر دو شکل خود را می‌فرستند، ولی همیشه شکل
    «پاسخ» به API می‌رسید. حافظه هم بی‌خطا و بی‌اثر می‌ماند، چون `candidates` پیش‌فرض
    خالی دارد: هیچ‌چیز هیچ‌وقت ثبت نمی‌شد و هیچ‌کس نمی‌فهمید.
    """
    from mentorai.ai.expand import SCHEMA as EXPANSION_SCHEMA
    from mentorai.memory.extract import EXTRACTION_SCHEMA

    env()
    client = AnthropicClient.from_settings()

    for wanted in (EXTRACTION_SCHEMA, EXPANSION_SCHEMA):
        await client.raw(system="س", user="ک", schema=wanted)
        sent = fake_api.client.messages.sent["output_config"]["format"]["schema"]
        assert sent == wanted
