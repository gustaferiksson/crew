import json
from pathlib import Path

import httpx
import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import ec

from crew_push import apns, store
from crew_push.hooks import Event, build
from conftest import TOKEN, FakeAPNs


def push(kind: str = "reply") -> tuple[dict[str, str], dict]:
    event = Event(kind, "Atlas", "atlas", "20261013_101512_ab12cd", "turn-1", "Done.")
    return build(event, {"prefs": store.DEFAULT_PREFS}, install_id="9f2c41d07ab35e11", now=1_000)


def test_request_shape(configured: Path, fake_apns: FakeAPNs, device, signing_key: ec.EllipticCurvePrivateKey) -> None:
    target = device()
    apns.send(target, *push())
    [request] = fake_apns.requests
    assert request.url == f"https://api.sandbox.push.apple.com/3/device/{TOKEN}"
    assert request.headers["apns-topic"] == "dev.gustaf.crew"
    assert request.headers["apns-push-type"] == "alert"
    scheme, token = request.headers["authorization"].split(" ")
    assert scheme == "bearer"
    assert jwt.get_unverified_header(token) == {"alg": "ES256", "kid": "ABC123DEFG", "typ": "JWT"}
    claims = jwt.decode(token, signing_key.public_key(), algorithms=["ES256"])
    assert claims["iss"] == "82K3YC8HVF"
    assert json.loads(request.content)["aps"]["alert"]["title"] == "Atlas"


def test_production_device_uses_production_host(configured: Path, fake_apns: FakeAPNs) -> None:
    apns.send({"token": TOKEN, "environment": "production"}, *push())
    assert fake_apns.requests[0].url.host == "api.push.apple.com"


def test_jwt_is_cached_then_refreshed(configured: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    config = store.apns_config()
    assert config
    clock = [10_000.0]
    monkeypatch.setattr(apns.time, "time", lambda: clock[0])
    first = apns.bearer(config)
    clock[0] += apns.TOKEN_LIFETIME_SECONDS - 1
    assert apns.bearer(config) == first
    clock[0] += 2
    refreshed = apns.bearer(config)
    assert refreshed != first
    assert jwt.decode(refreshed, options={"verify_signature": False})["iat"] == int(clock[0])
    assert apns.bearer({**config, "key_id": "OTHERKEY01"}) != refreshed


def test_expired_provider_token_forces_new_jwt(configured: Path, fake_apns: FakeAPNs) -> None:
    fake_apns.answers.append(httpx.Response(403, json={"reason": "ExpiredProviderToken"}))
    apns.send({"token": TOKEN, "environment": "sandbox"}, *push())
    assert apns._token == (0.0, "", "")


@pytest.mark.parametrize("answer", [
    httpx.Response(410, json={"reason": "Unregistered", "timestamp": 1}),
    httpx.Response(400, json={"reason": "BadDeviceToken"}),
    httpx.Response(400, json={"reason": "DeviceTokenNotForTopic"}),
])
def test_rejected_tokens_are_pruned(configured: Path, fake_apns: FakeAPNs, device, answer: httpx.Response) -> None:
    target = device()
    device("cd" * 32)
    fake_apns.answers.append(answer)
    apns.send(target, *push())
    assert [d["token"] for d in store.read_devices()] == ["cd" * 32]


def test_other_errors_keep_the_device(configured: Path, fake_apns: FakeAPNs, device) -> None:
    target = device()
    fake_apns.answers.append(httpx.Response(400, json={"reason": "PayloadTooLarge"}))
    apns.send(target, *push())
    assert len(store.read_devices()) == 1


def test_server_errors_retry_once_except_replies(configured: Path, fake_apns: FakeAPNs) -> None:
    target = {"token": TOKEN, "environment": "sandbox"}
    fake_apns.answers.extend([httpx.Response(503), httpx.Response(503)])
    apns.send(target, *push("reply"))
    assert len(fake_apns.requests) == 1
    fake_apns.answers[:] = [httpx.Response(500), httpx.Response(200)]
    apns.send(target, *push("approval"))
    assert len(fake_apns.requests) == 3


def test_network_errors_are_contained(configured: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    def refuse(request: httpx.Request) -> httpx.Response:
        raise httpx.ConnectError("refused", request=request)
    monkeypatch.setattr(apns, "_client", httpx.Client(transport=httpx.MockTransport(refuse)))
    apns.send({"token": TOKEN, "environment": "sandbox"}, *push("approval"))


def test_unconfigured_host_sends_nothing(fake_apns: FakeAPNs) -> None:
    apns.send({"token": TOKEN, "environment": "sandbox"}, *push())
    assert fake_apns.requests == []


def test_worker_thread_delivers_queued_pushes(configured: Path, fake_apns: FakeAPNs) -> None:
    for _ in range(3):
        apns.enqueue({"token": TOKEN, "environment": "sandbox"}, *push())
    apns._queue.join()
    assert len(fake_apns.requests) == 3

