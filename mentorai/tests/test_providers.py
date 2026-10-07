"""انتخاب ارائه‌دهنده و فرمان `model-check` (ADR-035)."""

from __future__ import annotations

import json
from typing import Any

import httpx2
import pytest
from pydantic import ValidationError
from tests.test_openai_client import ANSWER, KEY, Server, _ok

from mentorai import cli
from mentorai.ai import providers
from mentorai.ai.client import AnthropicClient
from mentorai.ai.openai_client import OpenAIClient
from mentorai.ai.schema import JSON_SCHEMA
from mentorai.config import get_settings
from mentorai.model_check import render, run_checks


@pytest.fixture
def env(monkeypatch: pytest.MonkeyPatch) -> Any:
    for name in (
        "AI_PROVIDER",
        "AI_MODEL",
        "AI_EFFORT",
        "AI_PRICE_INPUT_USD",
        "AI_PRICE_OUTPUT_USD",
        "OPENAI_API_KEY",
    ):
        monkeypatch.delenv(name, raising=False)
    monkeypatch.setenv("ANTHROPIC_API_KEY", "sk-ant-test-only")

    def _set(**values: str) -> None:
        for key, value in values.items():
            monkeypatch.setenv(key, value)
        get_settings.cache_clear()

    _set()
    yield _set
    get_settings.cache_clear()


def test_anthropic_is_the_default_provider(env: Any) -> None:
    assert isinstance(providers.build_client(), AnthropicClient)


def test_openai_is_chosen_by_one_line(env: Any) -> None:
    env(
        AI_PROVIDER="openai",
        AI_MODEL="gpt-test",
        OPENAI_API_KEY=KEY,
        AI_PRICE_INPUT_USD="1",
        AI_PRICE_OUTPUT_USD="4",
    )

    assert isinstance(providers.build_client(), OpenAIClient)


def test_a_provider_that_is_not_built_is_refused_by_the_settings(env: Any) -> None:
    env(AI_PROVIDER="gemini")

    with pytest.raises(ValidationError):
        get_settings()


def test_an_incomplete_provider_is_refused_when_the_worker_starts(env: Any) -> None:
    env(AI_PROVIDER="openai")  # نه مدل، نه کلید

    with pytest.raises(ValueError, match="OPENAI_API_KEY"):
        providers.build_client()


# ---------------------------------------------------------------------------
# model-check
# ---------------------------------------------------------------------------


def _by_schema(request: httpx2.Request) -> httpx2.Response:
    """سرور ساختگی که برای هر شکل خروجی، پاسخ همان شکل را می‌دهد."""
    fmt = json.loads(request.content).get("text", {}).get("format")
    if fmt is None:
        text = "یک نمودار شمعی."
    else:
        keys = set(fmt["schema"]["properties"])
        if keys == set(JSON_SCHEMA["properties"]):  # type: ignore[arg-type]
            text = json.dumps(ANSWER)
        elif keys == {"candidates"}:
            text = json.dumps({"candidates": []})
        else:
            text = json.dumps({"answer": "از ویدیو ۱۰ شروع کنید."})
    return httpx2.Response(200, json=_ok(text))


def _client(handler: Any) -> OpenAIClient:
    return OpenAIClient(model="gpt-test", api_key=KEY, transport=httpx2.MockTransport(handler))


async def test_every_production_path_is_exercised() -> None:
    client = _client(_by_schema)

    steps = await run_checks(client)

    assert [s.name for s in steps] == [
        "پاسخ به دانشجو",
        "استخراج حافظه",
        "بسط دستور منتور",
        "خواندن تصویر",
    ]
    assert all(s.ok for s in steps), [s.detail for s in steps if not s.ok]
    text = render(client, steps)
    assert "❌" not in text and "ثبت نشد" in text, "هزینه‌ی این بررسی در سقف روزانه نمی‌آید"
    assert KEY not in text


async def test_a_provider_that_ignores_the_requested_shape_fails_the_memory_path() -> None:
    """همان باگی که پیش‌تر دیده نمی‌شد: هر مسیر شکل «پاسخ» را می‌گرفت."""

    def always_answer_shaped(request: httpx2.Request) -> httpx2.Response:
        return httpx2.Response(200, json=_ok(json.dumps(ANSWER)))

    steps = await run_checks(_client(always_answer_shaped))

    memory = next(s for s in steps if s.name == "استخراج حافظه")
    assert not memory.ok and "شکل خروجی اشتباه" in memory.detail


async def test_a_dead_key_fails_everything_and_says_why() -> None:
    server = Server(httpx2.Response(401, json={"error": {"code": "invalid_api_key"}}))

    steps = await run_checks(_client(server))

    assert not any(s.ok for s in steps)
    assert all("401" in s.detail for s in steps)


async def test_the_command_exits_non_zero_when_anything_fails(
    monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    import argparse

    server = Server(httpx2.Response(401, json={"error": {"code": "invalid_api_key"}}))
    monkeypatch.setattr(providers, "build_client", lambda: _client(server))

    code = await cli.cmd_model_check(argparse.Namespace(image=None))

    assert code == 1
    assert "❌" in capsys.readouterr().out


async def test_a_broken_configuration_is_reported_without_a_traceback(
    env: Any, capsys: pytest.CaptureFixture[str]
) -> None:
    import argparse

    env(AI_PROVIDER="openai")

    code = await cli.cmd_model_check(argparse.Namespace(image=None))

    assert code == 1
    assert "پیکربندی هوش مصنوعی ناقص است" in capsys.readouterr().err


def test_model_check_image_is_a_valid_png() -> None:
    """مدل تصویر معیوب را درست رد می‌کند؛ پس تصویر آزمایشی باید سالم باشد.

    یک بار PNG دست‌نویس با چک‌سام غلط، `model-check` را روی سرور ❌ کرد
    (`Could not process image`) و هیچ آزمونی با مدل ساختگی آن را نگرفت.
    """
    import struct
    import zlib

    from mentorai.model_check import _PIXEL

    assert _PIXEL[:8] == b"\x89PNG\r\n\x1a\n"
    chunks: list[tuple[bytes, bytes]] = []
    pos = 8
    while pos < len(_PIXEL):
        (length,) = struct.unpack(">I", _PIXEL[pos : pos + 4])
        kind = _PIXEL[pos + 4 : pos + 8]
        body = _PIXEL[pos + 8 : pos + 8 + length]
        (crc,) = struct.unpack(">I", _PIXEL[pos + 8 + length : pos + 12 + length])
        assert zlib.crc32(kind + body) & 0xFFFFFFFF == crc, kind
        chunks.append((kind, body))
        pos += 12 + length
    assert pos == len(_PIXEL)
    assert [kind for kind, _ in chunks] == [b"IHDR", b"IDAT", b"IEND"]

    width, height, depth, color = struct.unpack(">IIBB", chunks[0][1][:10])
    assert (depth, color) == (8, 2)  # RGB، ۸ بیت
    raw = zlib.decompress(chunks[1][1])
    assert len(raw) == height * (1 + width * 3)  # هر سطر: یک بایت فیلتر + پیکسل‌ها
