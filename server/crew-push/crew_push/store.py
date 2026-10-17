import fcntl
import json
import os
import secrets
import time
from pathlib import Path
from typing import Any, Callable

Device = dict[str, Any]

PLATFORMS = frozenset({"ios", "macos"})
ENVIRONMENTS = frozenset({"sandbox", "production"})
DEFAULT_PREFS = {"replies": True, "approvals": True, "questions": True, "routines": False, "previews": True}
MAX_DEVICES = 32
MAX_PAYMENTS = 200


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


def read_list(name: str) -> list[Any]:
    try:
        items = json.loads((data_dir() / name).read_text())
    except (OSError, ValueError):
        return []
    return items if isinstance(items, list) else []


def write_locked(name: str, change: Callable[[list[Any]], Any]) -> Any:
    directory = data_dir()
    tmp = directory / f"{name}.tmp"
    with open(directory / ".lock", "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        value = change(read_list(name))
        with os.fdopen(os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), "w") as file:
            json.dump(value, file)
        os.chmod(tmp, 0o600)
        os.replace(tmp, directory / name)
    return value


def read_devices() -> list[Device]:
    return read_list("devices.json")


def mutate_devices(change: Callable[[list[Device]], list[Device]]) -> list[Device]:
    return write_locked("devices.json", change)


def mutate_payments(change: Callable[[list[dict[str, Any]]], list[dict[str, Any]]]) -> list[dict[str, Any]]:
    return write_locked("payments.json", lambda entries: change(entries)[-MAX_PAYMENTS:])


def write_gate(auth_required: bool) -> None:
    write_locked("gate.json", lambda _: {"auth_required": auth_required, "seen_at": time.time()})


def read_gate() -> bool | None:
    try:
        gate = json.loads((data_dir() / "gate.json").read_text())
    except (OSError, ValueError):
        return None
    value = gate.get("auth_required") if isinstance(gate, dict) else None
    return value if isinstance(value, bool) else None
