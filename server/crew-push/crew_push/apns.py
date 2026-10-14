import logging
import queue
import threading
import time
from typing import Any

import httpx
import jwt

from . import store

log = logging.getLogger("crew_push")

HOSTS = {"production": "https://api.push.apple.com", "sandbox": "https://api.sandbox.push.apple.com"}
# Apple rejects provider tokens older than 60 minutes and throttles refreshes under 20.
TOKEN_LIFETIME_SECONDS = 50 * 60
PRUNE_REASONS = frozenset({"BadDeviceToken", "DeviceTokenNotForTopic", "Unregistered"})
TOKEN_REASONS = frozenset({"ExpiredProviderToken", "InvalidProviderToken"})

Push = tuple[store.Device, dict[str, str], dict[str, Any]]

_queue: "queue.Queue[Push]" = queue.Queue(maxsize=256)
_token: tuple[float, str, str] = (0.0, "", "")
_client: httpx.Client | None = None
_worker: threading.Thread | None = None
_worker_lock = threading.Lock()


def enqueue(device: store.Device, headers: dict[str, str], payload: dict[str, Any]) -> None:
    try:
        _queue.put_nowait((device, headers, payload))
    except queue.Full:
        log.warning("crew-push: queue full, dropping a push")
        return
    _ensure_worker()


def bearer(config: dict[str, str]) -> str:
    global _token
    issued, key_id, token = _token
    now = time.time()
    if key_id == config["key_id"] and now - issued < TOKEN_LIFETIME_SECONDS:
        return token
    token = jwt.encode({"iss": config["team_id"], "iat": int(now)}, config["key"],
                       algorithm="ES256", headers={"kid": config["key_id"]})
    _token = (now, config["key_id"], token)
    return token


def _post(config: dict[str, str], device: store.Device, headers: dict[str, str],
          payload: dict[str, Any]) -> tuple[int, str]:
    global _client
    _client = _client or httpx.Client(http2=True, timeout=10, follow_redirects=False)
    response = _client.post(
        f"{HOSTS[device['environment']]}/3/device/{device['token']}", json=payload,
        headers={"authorization": f"bearer {bearer(config)}", "apns-topic": config["topic"], **headers})
    try:
        body = response.json() if response.content else {}
    except ValueError:
        body = {}
    return response.status_code, str(body.get("reason", "")) if isinstance(body, dict) else ""


def send(device: store.Device, headers: dict[str, str], payload: dict[str, Any]) -> None:
    global _token
    config = store.apns_config()
    if config is None:
        log.warning("crew-push: APNs key or apns.json missing, dropping a push")
        return
    attempts = 1 if payload["crew"]["kind"] == "reply" else 2
    status, reason = 0, ""
    for _ in range(attempts):
        try:
            status, reason = _post(config, device, headers, payload)
        except httpx.TransportError as error:
            status, reason = 0, type(error).__name__
            continue
        if status < 500:
            break
    if reason in TOKEN_REASONS:
        _token = (0.0, "", "")
    if status == 410 or reason in PRUNE_REASONS:
        store.mutate_devices(lambda devices: [d for d in devices if d.get("token") != device["token"]])
        log.info("crew-push: removed a %s device APNs no longer accepts (%s)", device.get("platform"), reason)
        return
    if status != 200:
        log.warning("crew-push: APNs answered %s %s", status, reason)


def _drain() -> None:
    while True:
        device, headers, payload = _queue.get()
        try:
            send(device, headers, payload)
        except Exception as error:
            log.warning("crew-push: send failed (%s)", type(error).__name__)
        finally:
            _queue.task_done()


def _ensure_worker() -> None:
    global _worker
    with _worker_lock:
        if _worker is None or not _worker.is_alive():
            _worker = threading.Thread(target=_drain, name="crew-push-apns", daemon=True)
            _worker.start()
