import importlib.util
import re
import sys
import time
from pathlib import Path
from typing import Any

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

if (_root := str(Path(__file__).resolve().parents[1])) not in sys.path:
    sys.path.append(_root)

from crew_push import PLUGIN_VERSION, apns, store  # noqa: E402
from crew_push.fanout import serve_every_profile_in_host  # noqa: E402
from crew_push.hooks import Event, bot_name, build, build_read  # noqa: E402

serve_every_profile_in_host()
router = APIRouter()
TOKEN = re.compile(r"^[0-9a-f]{64,200}$")


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


@router.get("/status")
def status() -> dict[str, Any]:
    return {"plugin_version": PLUGIN_VERSION, "install_id": store.install_id(),
            "apns_configured": store.apns_config() is not None, "http2": importlib.util.find_spec("h2") is not None,
            "devices": len(store.read_devices())}


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
