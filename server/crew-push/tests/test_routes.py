import stat
import types
from pathlib import Path

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from crew_push import apns, store
from conftest import TOKEN


@pytest.fixture
def client(plugin_api: types.ModuleType) -> TestClient:
    app = FastAPI()
    app.include_router(plugin_api.router, prefix="/api/plugins/crew-push")
    return TestClient(app)


def register(client: TestClient, **overrides: object) -> dict:
    body = {"token": TOKEN, "platform": "ios", "environment": "sandbox", "name": "iPhone", **overrides}
    return client.post("/api/plugins/crew-push/devices", json=body)


def test_status_reports_unconfigured_host(client: TestClient) -> None:
    body = client.get("/api/plugins/crew-push/status").json()
    assert body["plugin_version"] == "0.6.3"
    assert body["apns_configured"] is False
    assert body["http2"] is True
    assert body["devices"] == 0
    assert len(body["install_id"]) == 16


def test_register_stores_device_with_default_prefs(client: TestClient, configured: Path, hermes_root: Path) -> None:
    response = register(client, prefs={"routines": True, "unknown": True})
    assert response.status_code == 200
    assert response.json()["apns_configured"] is True
    [device] = store.read_devices()
    assert device["prefs"] == {**store.DEFAULT_PREFS, "routines": True}
    devices_file = hermes_root / "plugin-data" / "crew-push" / "devices.json"
    assert stat.S_IMODE(devices_file.stat().st_mode) == 0o600
    assert stat.S_IMODE(devices_file.parent.stat().st_mode) == 0o700


def test_register_is_an_upsert(client: TestClient) -> None:
    register(client)
    register(client, platform="macos", prefs={"previews": False})
    [device] = store.read_devices()
    assert device["platform"] == "macos"
    assert device["prefs"]["previews"] is False


@pytest.mark.parametrize("overrides", [
    {"token": "AB" * 32}, {"token": "ab" * 10}, {"token": "zz" * 32},
    {"platform": "watchos"}, {"environment": "development"},
])
def test_register_rejects_invalid_devices(client: TestClient, overrides: dict) -> None:
    assert register(client, **overrides).status_code == 400
    assert store.read_devices() == []


def test_register_caps_devices(client: TestClient) -> None:
    for index in range(store.MAX_DEVICES + 5):
        register(client, token=f"{index:064x}")
    tokens = [device["token"] for device in store.read_devices()]
    assert len(tokens) == store.MAX_DEVICES
    assert tokens[-1] == f"{store.MAX_DEVICES + 4:064x}"


def test_delete_removes_device_and_is_idempotent(client: TestClient) -> None:
    register(client)
    assert client.delete(f"/api/plugins/crew-push/devices/{TOKEN}").json() == {"ok": True}
    assert client.delete(f"/api/plugins/crew-push/devices/{TOKEN}").json() == {"ok": True}
    assert store.read_devices() == []


def test_test_push_needs_registered_device_and_key(client: TestClient, monkeypatch: pytest.MonkeyPatch,
                                                   enqueued: list) -> None:
    assert client.post("/api/plugins/crew-push/test", json={"token": TOKEN}).status_code == 404
    register(client, prefs={"previews": False, "replies": False})
    assert client.post("/api/plugins/crew-push/test", json={"token": TOKEN}).status_code == 409
    assert enqueued == []


def test_test_push_is_sent_to_that_device_only(client: TestClient, configured: Path, enqueued: list) -> None:
    register(client, token="cd" * 32)
    register(client, prefs={"previews": False, "replies": False})
    response = client.post("/api/plugins/crew-push/test", json={"token": TOKEN})
    assert response.status_code == 202
    [(device, headers, payload)] = enqueued
    assert device["token"] == TOKEN
    assert payload["aps"]["alert"] == {"title": "Hermes", "body": "Push notifications work."}
    assert payload["crew"]["kind"] == "reply"
    assert headers["apns-push-type"] == "alert"


def test_test_push_reaches_fake_apns(client: TestClient, configured: Path, fake_apns) -> None:
    register(client)
    client.post("/api/plugins/crew-push/test", json={"token": TOKEN})
    apns._queue.join()
    [request] = fake_apns.requests
    assert request.url == f"https://api.sandbox.push.apple.com/3/device/{TOKEN}"


def announce(client: TestClient, **overrides: object):
    body = {"token": TOKEN, "profile": "atlas", "session_id": "20261013_144627_bb3f2e", "read_at": 1791925650.5,
            **overrides}
    return client.post("/api/plugins/crew-push/read", json=body)


def test_read_is_pushed_silently_to_every_other_device(client: TestClient, configured: Path, enqueued: list) -> None:
    register(client)
    register(client, token="cd" * 32, platform="macos", prefs={"replies": False, "previews": False})
    register(client, token="ef" * 32)
    response = announce(client)
    assert response.status_code == 202
    assert response.json() == {"devices": 2}
    assert [device["token"] for device, _, _ in enqueued] == ["cd" * 32, "ef" * 32]
    _, headers, payload = enqueued[0]
    assert headers["apns-push-type"] == "background"
    assert headers["apns-priority"] == "5"
    assert headers["apns-collapse-id"].startswith("read.")
    assert payload["aps"] == {"content-available": 1}
    assert payload["crew"] == {"v": 1, "kind": "read", "install_id": store.install_id(), "profile": "atlas",
                               "session_id": "20261013_144627_bb3f2e", "thread-id": "profile.atlas",
                               "read_at": 1791925650.5}


def test_read_needs_valid_sender_and_key(client: TestClient, enqueued: list) -> None:
    register(client, token="cd" * 32)
    assert announce(client).status_code == 409
    assert announce(client, token="zz" * 32).status_code == 400
    assert announce(client, profile="").status_code == 422
    assert enqueued == []


def test_read_reaches_fake_apns_as_background_push(client: TestClient, configured: Path, fake_apns) -> None:
    register(client, token="cd" * 32)
    announce(client)
    apns._queue.join()
    [request] = fake_apns.requests
    assert request.url == f"https://api.sandbox.push.apple.com/3/device/{'cd' * 32}"
    assert request.headers["apns-push-type"] == "background"
    assert request.headers["apns-priority"] == "5"
    assert request.headers["apns-topic"] == "dev.gustaf.crew"
    assert fake_apns.payloads()[0]["crew"]["kind"] == "read"
