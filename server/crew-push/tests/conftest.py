import importlib.util
import json
import sys
import types
import uuid
from dataclasses import dataclass, field
from datetime import UTC, datetime
from pathlib import Path
from typing import Any, Callable

import httpx
import pytest
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ec

from crew_push import apns, store

PLUGIN_ROOT = Path(__file__).resolve().parents[1]
FIXTURES = PLUGIN_ROOT.parents[1] / "Tests" / "fixtures" / "payments"
TOKEN = "ab" * 32
CARD = {"card_number": "4242 4242 4242 4242", "exp_month": "12", "exp_year": "2030", "cvc": "123",
        "cardholder_name": "Gustaf Eriksson"}
PAYMENT_FIELDS = ("card_number", "cardholder_name", "exp_month", "exp_year", "cvc", "billing_postal_code")
BOT_CHAT = "20261013_101512_ab12cd"


@pytest.fixture(autouse=True)
def hermes_root(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Path:
    monkeypatch.setitem(sys.modules, "hermes_constants",
                        types.SimpleNamespace(get_default_hermes_root=lambda: tmp_path))
    monkeypatch.setattr(apns, "_token", (0.0, "", ""))
    monkeypatch.setattr(apns, "_client", None)
    return tmp_path


@pytest.fixture(autouse=True)
def bot_chat(monkeypatch: pytest.MonkeyPatch, hermes_root: Path) -> dict[str, str]:
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
    monkeypatch.setitem(sys.modules, "hermes_cli.profiles", types.SimpleNamespace(
        get_profile_dir=lambda name: hermes_root if name == "default" else hermes_root / "profiles" / name,
        profile_exists=lambda name: name == "default" or (hermes_root / "profiles" / name).is_dir(),
        read_profile_meta=lambda directory: {"bot_title": directory.name.title()} if directory.name == "scout" else {}))
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


def fixture(name: str) -> Any:
    return json.loads((FIXTURES / name).read_text())


@dataclass(frozen=True)
class VaultItemMeta:
    id: str
    kind: str
    label: str
    origin: str | None
    created_at: str


@dataclass
class Vaults:
    records: dict[Path, list[dict[str, Any]]] = field(default_factory=dict)
    next_ids: list[str] = field(default_factory=list)
    now: float = 1760600000.0

    def add(self, base: Path, kind: str, label: str, secret: dict[str, Any], origin: str | None = None) -> VaultItemMeta:
        record = {"id": self.next_ids.pop(0) if self.next_ids else f"vault_{uuid.uuid4().hex[:12]}", "kind": kind,
                  "label": label, "origin": origin, "created_at": datetime.fromtimestamp(self.now, UTC).isoformat(),
                  "secret": {k: str(v) for k, v in secret.items() if kind != "payment" or k in PAYMENT_FIELDS}}
        self.records.setdefault(base, []).append(record)
        return VaultItemMeta(record["id"], kind, label, origin, record["created_at"])


@pytest.fixture
def vaults(monkeypatch: pytest.MonkeyPatch, hermes_root: Path) -> Vaults:
    state = Vaults()

    class VaultStore:
        def __init__(self, base_dir: Path) -> None:
            self.base = Path(base_dir)
            self.records = state.records.setdefault(self.base, [])

        def add_item(self, kind: str, label: str, secret: dict[str, Any], origin: str | None = None) -> VaultItemMeta:
            return state.add(self.base, kind, label, secret, origin)

        def list_items(self) -> list[VaultItemMeta]:
            return [VaultItemMeta(r["id"], r["kind"], r["label"], r["origin"], r["created_at"]) for r in self.records]

        def resolve_secret(self, item_id: str) -> dict[str, Any]:
            return dict(next(r["secret"] for r in self.records if r["id"] == item_id))

        def remove_item(self, item_id: str) -> bool:
            before = len(self.records)
            self.records[:] = [r for r in self.records if r["id"] != item_id]
            return len(self.records) != before

    monkeypatch.setitem(sys.modules, "agent", types.ModuleType("agent"))
    monkeypatch.setitem(sys.modules, "agent.vault_store", types.SimpleNamespace(VaultStore=VaultStore))
    (hermes_root / "profiles" / "scout").mkdir(parents=True)
    return state
