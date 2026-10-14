import fcntl
import json
import os
import secrets
from pathlib import Path
from typing import Any, Callable

Device = dict[str, Any]

PLATFORMS = frozenset({"ios", "macos"})
ENVIRONMENTS = frozenset({"sandbox", "production"})
DEFAULT_PREFS = {"replies": True, "approvals": True, "questions": True, "routines": False, "previews": True}
MAX_DEVICES = 32


def data_dir() -> Path:
    from hermes_constants import get_default_hermes_root

    path = Path(get_default_hermes_root()) / "plugin-data" / "crew-push"
    path.mkdir(mode=0o700, parents=True, exist_ok=True)
    return path


def apns_config() -> dict[str, str] | None:
    directory = data_dir()
    try:
        config = json.loads((directory / "apns.json").read_text())
        key = (directory / "AuthKey.p8").read_text()
    except (OSError, ValueError):
        return None
    fields = ("key_id", "team_id", "topic")
    if not isinstance(config, dict) or not all(isinstance(config.get(field), str) for field in fields):
        return None
    return {**{field: config[field] for field in fields}, "key": key}


def install_id() -> str:
    path = data_dir() / "install_id"
    if not path.exists():
        path.write_text(secrets.token_hex(8))
    return path.read_text().strip()


def read_devices() -> list[Device]:
    try:
        devices = json.loads((data_dir() / "devices.json").read_text())
    except (OSError, ValueError):
        return []
    return devices if isinstance(devices, list) else []


def mutate_devices(change: Callable[[list[Device]], list[Device]]) -> list[Device]:
    directory = data_dir()
    path = directory / "devices.json"
    tmp = directory / "devices.json.tmp"
    with open(directory / ".lock", "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        devices = change(read_devices())
        with os.fdopen(os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), "w") as file:
            json.dump(devices, file)
        os.chmod(tmp, 0o600)
        os.replace(tmp, path)
    return devices
