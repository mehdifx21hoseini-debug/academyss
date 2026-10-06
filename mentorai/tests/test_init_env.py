"""اسکریپت ساخت `.env` روز اول (scripts/init-env.sh)."""

from __future__ import annotations

import base64
import shutil
import stat
import subprocess
from pathlib import Path

import pytest
from cryptography.fernet import Fernet

ROOT = Path(__file__).resolve().parent.parent


def _values(path: Path) -> dict[str, str]:
    out: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if line and not line.startswith("#") and "=" in line:
            key, _, value = line.partition("=")
            out[key] = value
    return out


@pytest.fixture
def deploy(tmp_path: Path) -> Path:
    """کپی همان چیدمان مخزن: اسکریپت در scripts/ و نمونه کنار آن."""
    (tmp_path / "scripts").mkdir()
    shutil.copy(ROOT / "scripts" / "init-env.sh", tmp_path / "scripts" / "init-env.sh")
    shutil.copy(ROOT / ".env.example", tmp_path / ".env.example")
    return tmp_path


def _run(deploy: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["bash", str(deploy / "scripts" / "init-env.sh")],
        capture_output=True,
        text=True,
        check=False,
    )


def test_the_database_password_is_the_same_in_both_places(deploy: Path) -> None:
    result = _run(deploy)
    assert result.returncode == 0, result.stderr

    values = _values(deploy / ".env")
    password = values["POSTGRES_PASSWORD"]
    assert len(password) == 48
    assert values["DATABASE_URL"] == f"postgresql+asyncpg://mentorai:{password}@db:5432/mentorai"
    assert "CHANGEME" not in (deploy / ".env").read_text(encoding="utf-8")


def test_the_session_key_is_a_working_fernet_key(deploy: Path) -> None:
    _run(deploy)
    key = _values(deploy / ".env")["SESSION_ENCRYPTION_KEY"]

    assert len(base64.urlsafe_b64decode(key)) == 32
    box = Fernet(key.encode())
    assert box.decrypt(box.encrypt(b"session")) == b"session"


def test_two_servers_never_get_the_same_secrets(
    deploy: Path, tmp_path_factory: pytest.TempPathFactory
) -> None:
    other = tmp_path_factory.mktemp("other")
    (other / "scripts").mkdir()
    shutil.copy(deploy / "scripts" / "init-env.sh", other / "scripts" / "init-env.sh")
    shutil.copy(deploy / ".env.example", other / ".env.example")
    _run(deploy)
    _run(other)

    a, b = _values(deploy / ".env"), _values(other / ".env")
    assert a["POSTGRES_PASSWORD"] != b["POSTGRES_PASSWORD"]
    assert a["SESSION_ENCRYPTION_KEY"] != b["SESSION_ENCRYPTION_KEY"]


def test_only_the_owner_can_read_the_file(deploy: Path) -> None:
    _run(deploy)
    mode = stat.S_IMODE((deploy / ".env").stat().st_mode)
    assert mode == 0o600


def test_an_existing_env_is_never_overwritten(deploy: Path) -> None:
    """کلید تازه یعنی نشست‌های ذخیره‌شده دیگر باز نمی‌شوند و هر حساب از نو وارد شود."""
    (deploy / ".env").write_text("SESSION_ENCRYPTION_KEY=old\n", encoding="utf-8")

    result = _run(deploy)

    assert result.returncode == 1
    assert (deploy / ".env").read_text(encoding="utf-8") == "SESSION_ENCRYPTION_KEY=old\n"


def test_every_other_line_is_left_as_in_the_example(deploy: Path) -> None:
    _run(deploy)
    filled = {"POSTGRES_PASSWORD", "DATABASE_URL", "SESSION_ENCRYPTION_KEY"}
    example = _values(deploy / ".env.example")
    written = _values(deploy / ".env")

    assert written.keys() == example.keys()
    assert {k: v for k, v in written.items() if k not in filled} == {
        k: v for k, v in example.items() if k not in filled
    }


def test_no_secret_is_printed(deploy: Path) -> None:
    result = _run(deploy)
    values = _values(deploy / ".env")
    for key in ("POSTGRES_PASSWORD", "SESSION_ENCRYPTION_KEY"):
        assert values[key] not in result.stdout + result.stderr
