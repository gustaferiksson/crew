import importlib.util
import json
import sys
import types
from pathlib import Path
from typing import Any, Callable

import httpx
import pytest
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ec

from crew_push import apns, store

PLUGIN_ROOT = Path(__file__).resolve().parents[1]
TOKEN = "ab" * 32
BOT_CHAT = "20261013_101512_ab12cd"


@pytest.fixture(autouse=True)
def hermes_root(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Path:
    monkeypatch.setitem(sys.modules, "hermes_constants",
                        types.SimpleNamespace(get_default_hermes_root=lambda: tmp_path))
    monkeypatch.setattr(apns, "_token", (0.0, "", ""))
    monkeypatch.setattr(apns, "_client", None)
    return tmp_path


@pytest.fixture(autouse=True)
def bot_chat(monkeypatch: pytest.MonkeyPatch) -> dict[str, str]:
    chat = {"id": BOT_CHAT, "tip": BOT_CHAT}

    class SessionDB:
        def __init__(self, db_path: Path, read_only: bool) -> None:
            assert db_path.name == "state.db" and read_only

        def get_session_by_title(self, title: str) -> dict[str, str] | None:
            return {"id": chat["id"]} if title == "Bot Chat" else None

        def get_compression_tip(self, session_id: str) -> str:
            return chat["tip"] if session_id == chat["id"] else session_id

        def close(self) -> None:
            pass

    monkeypatch.setitem(sys.modules, "hermes_state", types.SimpleNamespace(SessionDB=SessionDB))
    monkeypatch.setitem(sys.modules, "hermes_cli", types.ModuleType("hermes_cli"))
    monkeypatch.setitem(sys.modules, "hermes_cli.profiles",
                        types.SimpleNamespace(get_profile_dir=Path, read_profile_meta=lambda directory: {}))
    return chat


@pytest.fixture
def signing_key() -> ec.EllipticCurvePrivateKey:
    return ec.generate_private_key(ec.SECP256R1())


@pytest.fixture
def configured(signing_key: ec.EllipticCurvePrivateKey) -> Path:
    directory = store.data_dir()
    pem = signing_key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8,
                                    serialization.NoEncryption())
    (directory / "AuthKey.p8").write_bytes(pem)
    (directory / "apns.json").write_text(
        json.dumps({"key_id": "ABC123DEFG", "team_id": "82K3YC8HVF", "topic": "dev.gustaf.crew"}))
    return directory


class FakeAPNs:
    def __init__(self) -> None:
        self.requests: list[httpx.Request] = []
        self.answers: list[httpx.Response] = []

    def handle(self, request: httpx.Request) -> httpx.Response:
        self.requests.append(request)
        return self.answers.pop(0) if self.answers else httpx.Response(200)

    def payloads(self) -> list[dict[str, Any]]:
        return [json.loads(request.content) for request in self.requests]


@pytest.fixture
def fake_apns(monkeypatch: pytest.MonkeyPatch) -> FakeAPNs:
    fake = FakeAPNs()
    monkeypatch.setattr(apns, "_client", httpx.Client(transport=httpx.MockTransport(fake.handle)))
    return fake


@pytest.fixture
def enqueued(monkeypatch: pytest.MonkeyPatch) -> list[tuple[dict[str, Any], dict[str, str], dict[str, Any]]]:
    pushes: list[tuple[dict[str, Any], dict[str, str], dict[str, Any]]] = []
    monkeypatch.setattr(apns, "enqueue", lambda device, headers, payload: pushes.append((device, headers, payload)))
    return pushes


@pytest.fixture
def device() -> Callable[..., dict[str, Any]]:
    def make(token: str = TOKEN, **prefs: bool) -> dict[str, Any]:
        record = {"token": token, "platform": "ios", "environment": "sandbox", "name": "iPhone",
                  "prefs": {**store.DEFAULT_PREFS, **prefs}, "registered_at": 0}
        store.mutate_devices(lambda devices: [*devices, record])
        return record
    return make


@pytest.fixture
def plugin_api() -> types.ModuleType:
    spec = importlib.util.spec_from_file_location("hermes_dashboard_plugin_crew-push",
                                                  PLUGIN_ROOT / "dashboard" / "plugin_api.py")
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module
