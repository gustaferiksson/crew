import importlib.util
import json
import re
import sys
import time
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, Field
from starlette.concurrency import run_in_threadpool

if (_root := str(Path(__file__).resolve().parents[1])) not in sys.path:
    sys.path.append(_root)

from crew_push import PLUGIN_VERSION, apns, payments, store  # noqa: E402
from crew_push.fanout import serve_every_profile_in_host  # noqa: E402
from crew_push.hooks import Event, bot_name, build, build_read  # noqa: E402

serve_every_profile_in_host()
(store.data_dir() / "gate.json").unlink(missing_ok=True)
TOKEN = re.compile(r"^[0-9a-f]{64,200}$")
PROFILE = re.compile(r"^[a-z0-9][a-z0-9_-]{0,63}$")
ERRORS = {
    "invalid_profile": "profile must match ^[a-z0-9][a-z0-9_-]{0,63}$",
    "unknown_profile": "no such profile",
    "duplicate_shop": "this profile already has a card for that origin",
    "no_card": "no payment card without a website in the default vault",
    "several_cards": "more than one payment card without a website in the default vault",
    "unknown_shop": "no shop with that id",
    "unknown_request": "no payment request with that id",
    "login_off": "the dashboard login is off, so crew-push does not store cards",
    "invalid_card": "the card details are not valid",
    "payment_pending": "a payment for this profile is waiting for an answer",
    "vault_error": "the vault could not be updated",
}
SITE_ERRORS = {
    "not_https": "the site must use https",
    "ip_address": "the site must be a name, not an IP address",
    "localhost": "the site must be a public name",
    "no_host": "the site has no valid host",
    "port": "the site must use the standard https port",
}


def record_gate(request: Request) -> None:
    store.write_gate(getattr(request.app.state, "auth_required", False) is True)


router = APIRouter(dependencies=[Depends(record_gate)])


class DeviceIn(BaseModel):
    token: str
    platform: str
    environment: str
    name: str = Field(default="", max_length=80)
    prefs: dict[str, bool] = Field(default_factory=dict)


class PushTarget(BaseModel):
    token: str


class ReadIn(BaseModel):
    token: str
    profile: str = Field(min_length=1, max_length=64)
    session_id: str = Field(default="", max_length=200)
    read_at: float


class ShopIn(BaseModel):
    profile: str = Field(max_length=64)
    site: str = Field(max_length=2048)


class ProfileIn(BaseModel):
    profile: str = Field(max_length=64)


def failure(status: int, code: str, **extra: str) -> HTTPException:
    return HTTPException(status, {"code": code, **extra, "message": ERRORS[code]})


def checked_gate(request: Request) -> None:
    if getattr(request.app.state, "auth_required", False) is not True:
        raise failure(403, "login_off")


def checked_profile(profile: str) -> None:
    if not PROFILE.match(profile):
        raise HTTPException(400, {"code": "invalid_profile", "message": ERRORS["invalid_profile"]})
    from hermes_cli.profiles import profile_exists

    if not profile_exists(profile):
        raise HTTPException(404, {"code": "unknown_profile", "message": ERRORS["unknown_profile"]})


@router.get("/status")
def status() -> dict[str, Any]:
    return {"plugin_version": PLUGIN_VERSION, "install_id": store.install_id(),
            "apns_configured": store.apns_config() is not None, "http2": importlib.util.find_spec("h2") is not None,
            "devices": len(store.read_devices()), "features": ["payments", "card"], "gate": store.read_gate()}


@router.post("/devices")
def register_device(device: DeviceIn) -> dict[str, Any]:
    if not TOKEN.match(device.token) or device.platform not in store.PLATFORMS \
            or device.environment not in store.ENVIRONMENTS:
        raise HTTPException(400, "invalid device")
    prefs = {key: device.prefs.get(key, default) for key, default in store.DEFAULT_PREFS.items()}
    record = {**device.model_dump(), "prefs": prefs, "registered_at": int(time.time())}
    store.mutate_devices(
        lambda devices: [d for d in devices if d.get("token") != device.token][-(store.MAX_DEVICES - 1):] + [record])
    return {"ok": True, "install_id": store.install_id(), "apns_configured": store.apns_config() is not None}


@router.delete("/devices/{token}")
def unregister_device(token: str) -> dict[str, bool]:
    store.mutate_devices(lambda devices: [d for d in devices if d.get("token") != token])
    return {"ok": True}


@router.post("/test", status_code=202)
def send_test(body: PushTarget) -> dict[str, bool]:
    device = next((d for d in store.read_devices() if d.get("token") == body.token), None)
    if device is None:
        raise HTTPException(404, "device not registered")
    if store.apns_config() is None:
        raise HTTPException(409, "APNs key or apns.json missing on the server")
    try:
        from hermes_cli.profiles import get_active_profile_name

        profile = get_active_profile_name()
    except Exception:
        profile = "default"
    event = Event("reply", bot_name(profile), profile, "", f"test:{time.time()}", "Push notifications work.")
    with_preview = {**device, "prefs": {**device.get("prefs", {}), "previews": True}}
    apns.enqueue(device, *build(event, with_preview, install_id=store.install_id(), now=time.time()))
    return {"ok": True}


@router.post("/read", status_code=202)
def announce_read(body: ReadIn) -> dict[str, int]:
    if not TOKEN.match(body.token):
        raise HTTPException(400, "invalid device")
    if store.apns_config() is None:
        raise HTTPException(409, "APNs key or apns.json missing on the server")
    others = [d for d in store.read_devices() if d.get("token") != body.token]
    install_id = store.install_id()
    for device in others:
        apns.enqueue(device, *build_read(body.profile, body.session_id, body.read_at, install_id=install_id,
                                         now=time.time()))
    return {"devices": len(others)}


@router.get("/payments")
def list_shops(profile: str) -> dict[str, Any]:
    checked_profile(profile)
    import hermes_yaml
    from hermes_cli.profiles import get_profile_dir

    try:
        card, master_secret = payments.master()
        card_row = {"label": card.label, "last4": payments.last4(master_secret), "problem": None}
    except payments.CardProblem as problem:
        card_row, master_secret = {"label": None, "last4": None, "problem": str(problem)}, None
    vault = payments.profile_vault(profile)
    config_path = get_profile_dir(profile) / "config.yaml"
    config = hermes_yaml.safe_load(config_path.read_text()) if config_path.is_file() else None
    terminal = config.get("terminal") if isinstance(config, dict) else None
    return {"card": card_row,
            "shops": [payments.shop(item, vault.resolve_secret(item.id), master_secret, profile)
                      for item in payments.shops(vault)],
            "terminal_backend": str(terminal.get("backend") or "local") if isinstance(terminal, dict) else "local",
            "gate": store.read_gate()}


@router.post("/payments/shops", status_code=201)
def add_shop(body: ShopIn) -> dict[str, Any]:
    checked_profile(body.profile)
    try:
        host = payments.shop_host(body.site)
    except payments.InvalidSite as invalid:
        reason = str(invalid)
        raise HTTPException(400, {"code": "invalid_site", "reason": reason, "message": SITE_ERRORS[reason]}) from None
    origin = f"https://{host}"
    vault = payments.profile_vault(body.profile)
    with payments.vault_lock():
        if any(item.origin == origin for item in payments.shops(vault)):
            raise HTTPException(409, {"code": "duplicate_shop", "message": ERRORS["duplicate_shop"]})
        try:
            card, secret = payments.master()
        except payments.CardProblem as problem:
            code = "no_card" if str(problem) == "missing" else "several_cards"
            raise HTTPException(409, {"code": code, "message": ERRORS[code]}) from None
        item = vault.add_item(kind="payment", label=f"{card.label} •••• {payments.last4(secret)} · {host}",
                              secret=secret, origin=origin)
    return {"shop": payments.shop(item, secret, secret, body.profile)}


@router.post("/payments/shops/update")
def update_shops(body: ProfileIn, request: Request) -> dict[str, Any]:
    checked_gate(request)
    checked_profile(body.profile)
    if payments.pending_payment(body.profile):
        raise failure(409, "payment_pending")
    try:
        payments.update_shops(body.profile)
        card, master_secret = payments.master()
    except payments.CardProblem as problem:
        raise failure(409, "no_card" if str(problem) == "missing" else "several_cards") from None
    except Exception:
        raise failure(500, "vault_error") from None
    vault = payments.profile_vault(body.profile)
    return {"shops": [payments.shop(item, vault.resolve_secret(item.id), master_secret, body.profile)
                      for item in payments.shops(vault)]}


def store_card(body: Any) -> dict[str, Any]:
    try:
        label, secret = payments.card_entry(body, datetime.now(UTC))
        card = payments.set_master(label, secret)
        return {"card": {"label": card.label, "last4": payments.last4(secret), "problem": None}}
    except payments.InvalidCard as invalid:
        reason = str(invalid)
        raise failure(400, "invalid_card", reason=reason) from None
    except payments.CardProblem:
        raise failure(409, "several_cards") from None
    except Exception:
        raise failure(500, "vault_error") from None


@router.put("/payments/card")
async def set_card(request: Request) -> dict[str, Any]:
    checked_gate(request)
    if request.headers.get("content-type", "").split(";")[0].strip().lower() != "application/json":
        raise failure(400, "invalid_card", reason="body")
    try:
        body = json.loads(await request.body())
    except Exception:
        raise failure(400, "invalid_card", reason="body") from None
    return await run_in_threadpool(store_card, body)


@router.delete("/payments/shops/{shop_id}")
def remove_shop(shop_id: str, profile: str) -> dict[str, bool]:
    checked_profile(profile)
    vault = payments.profile_vault(profile)
    with payments.vault_lock():
        if not any(item.id == shop_id for item in payments.shops(vault)) or not vault.remove_item(shop_id):
            raise HTTPException(404, {"code": "unknown_shop", "message": ERRORS["unknown_shop"]})
    return {"removed": True}


@router.get("/payments/requests/{request_id}")
def payment_request(request_id: str) -> dict[str, Any]:
    entry = payments.find(request_id)
    if entry is None:
        raise HTTPException(404, {"code": "unknown_request", "message": ERRORS["unknown_request"]})
    return payments.public(entry)
