import ipaddress
import json
import re
import time
import unicodedata
from datetime import datetime
from pathlib import Path
from typing import Any
from urllib.parse import urlsplit

from . import store

LIMITS = {"amount": 32, "merchant": 64, "reason": 140}
HOST_LABEL = re.compile(r"^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$")
STATES = {"once": "approved", "session": "approved", "always": "approved", "deny": "denied", "timeout": "expired"}
FILL_ERRORS = frozenset({"origin_mismatch", "origin_changed", "human_has_control"})
NO_FIELDS_ERRORS = ("No payment form fields", "No fillable payment field")
PUBLIC_FIELDS = ("request_id", "profile", "session_id", "origin", "host", "card_label", "amount", "merchant", "reason",
                 "state", "fill", "fill_error", "created_at", "expires_at", "decided_at")

NEXT = "Click the shop's pay button. Never tick save card or remember card."
NO_FIELDS = ("The card fields weren't found; this checkout probably puts them in a payment frame, which can't be "
             "filled. Tell the user.")
DECLINED = {
    "denied": "The user denied this payment. Do not retry; ask what they want instead.",
    "expired": "Nobody answered within 5 minutes. Tell the user it expired and wait until they ask again.",
    "cancelled": "The request was cancelled. Stop.",
}
BLOCKS = {
    "crew_gate_off": ("Payments are off on this server: its dashboard login is off, or Crew has not connected since "
                      "crew-push started. Tell the user and do not retry."),
    "crew_not_bot_chat": "Payments only work in your Bot Chat in Crew. Tell the user you can only pay from your chat in Crew.",
    "crew_one_at_a_time": "A payment request is already waiting for the user. Wait for their answer; do not ask again.",
    "crew_after_decline": "The user declined the last payment. Do not try to pay again until they write to you.",
    "crew_missing_details": ("A payment fill needs amount (the total shown at checkout, with a digit, up to 32 "
                             "characters), merchant (up to 64) and reason (up to 140). Retry the same fill with them, "
                             "for example amount \"499 kr\", merchant \"Zalando\", reason \"Winter boots, size 43\"."),
    "crew_check_failed": ("crew-push could not check this payment, so it was blocked. If a password manager is locked, "
                          "unlock it with browser_vault action=unlock and retry; otherwise tell the user."),
}


class InvalidSite(ValueError):
    pass


class CardProblem(LookupError):
    pass


def no_card_for(origin: str) -> str:
    return f"There is no card for {origin}. Tell the user they can add this shop in Crew, then wait."


def block(code: str, message: str = "", **crew_payment: str) -> dict[str, str]:
    body = {"success": False, "error_type": code, **({"crew_payment": crew_payment} if crew_payment else {}),
            "error": message or BLOCKS[code]}
    return {"action": "block", "message": json.dumps(body)}


def clean(value: Any) -> str:
    text = str(value) if isinstance(value, (str, int, float)) else ""
    kept = "".join(c for c in text if c.isspace() or unicodedata.category(c) not in ("Cc", "Cf"))
    return " ".join(kept.split())


def claim(args: dict[str, Any]) -> dict[str, str] | None:
    details = {key: clean(args.get(key)) for key in LIMITS}
    if not all(0 < len(details[key]) <= limit for key, limit in LIMITS.items()):
        return None
    return details if any(c.isdigit() for c in details["amount"]) else None


def command_for(label: str, origin: str) -> str:
    return f"Fill payment card '{label}' on {origin}"


def host_of(origin: str) -> str:
    return urlsplit(origin).hostname or ""


def shop_host(site: str) -> str:
    text = site.strip()
    if not text:
        raise InvalidSite("no_host")
    try:
        parts = urlsplit(text if "://" in text else f"https://{text}")
    except ValueError:
        raise InvalidSite("no_host") from None
    if parts.scheme.lower() != "https":
        raise InvalidSite("not_https")
    try:
        port = parts.port
    except ValueError:
        raise InvalidSite("port") from None
    if port not in (None, 443):
        raise InvalidSite("port")
    host = (parts.hostname or "").rstrip(".")
    if not host:
        raise InvalidSite("no_host")
    try:
        ipaddress.ip_address(host)
    except ValueError:
        pass
    else:
        raise InvalidSite("ip_address")
    try:
        host = host.encode("idna").decode("ascii").lower()
    except UnicodeError:
        raise InvalidSite("no_host") from None
    labels = host.split(".")
    if labels[-1].isdigit():
        raise InvalidSite("ip_address")
    if len(labels) < 2 or labels[-1] == "localhost":
        raise InvalidSite("localhost")
    if len(host) > 253 or not all(HOST_LABEL.match(label) for label in labels):
        raise InvalidSite("no_host")
    return host


def master_vault() -> Any:
    from agent.vault_store import VaultStore
    from hermes_constants import get_default_hermes_root

    return VaultStore(Path(get_default_hermes_root()) / "vault")


def profile_vault(profile: str) -> Any:
    from agent.vault_store import VaultStore
    from hermes_cli.profiles import get_profile_dir

    return VaultStore(get_profile_dir(profile) / "vault")


def master() -> tuple[Any, dict[str, Any]]:
    vault = master_vault()
    cards = [item for item in vault.list_items() if item.kind == "payment" and not item.origin]
    if len(cards) != 1:
        raise CardProblem("several" if cards else "missing")
    return cards[0], vault.resolve_secret(cards[0].id)


def last4(secret: dict[str, Any]) -> str:
    return re.sub(r"\D", "", str(secret.get("card_number") or ""))[-4:]


def shops(vault: Any) -> list[Any]:
    return [item for item in vault.list_items() if item.kind == "payment" and item.origin]


def shop(item: Any, secret: dict[str, Any], master_secret: dict[str, Any] | None, profile: str) -> dict[str, Any]:
    host = host_of(item.origin)
    paid = [entry.get("decided_at") or 0.0 for entry in store.read_list("payments.json")
            if entry.get("profile") == profile and entry.get("origin") == item.origin and entry.get("state") == "approved"]
    return {"id": item.id, "origin": item.origin, "host": host,
            "created_at": datetime.fromisoformat(item.created_at).timestamp(), "last_paid_at": max(paid, default=None),
            "stale": master_secret is not None and secret != master_secret,
            "punycode": any(label.startswith("xn--") for label in host.split("."))}


def find(request_id: str) -> dict[str, Any] | None:
    return next((entry for entry in store.read_list("payments.json") if entry.get("request_id") == request_id), None)


def update(request_id: str, **fields: Any) -> None:
    store.mutate_payments(lambda entries: [{**entry, **fields} if entry.get("request_id") == request_id else entry
                                           for entry in entries])


def public(entry: dict[str, Any]) -> dict[str, Any]:
    return {**{key: entry.get(key) for key in PUBLIC_FIELDS}, "now": time.time()}


def fill_outcome(raw: dict[str, Any]) -> tuple[str, str | None]:
    if raw.get("success") is True and "cc-number" in (raw.get("fields") or []):
        return "filled", None
    if raw.get("error_type") == "payment_declined":
        return "not_filled", None
    if raw.get("success") is True or str(raw.get("error") or "").startswith(NO_FIELDS_ERRORS):
        return "not_filled", "no_fields"
    return "not_filled", raw.get("error_type") if raw.get("error_type") in FILL_ERRORS else "error"


def decorate(raw: dict[str, Any], entry: dict[str, Any]) -> dict[str, Any]:
    fill, fill_error = fill_outcome(raw)
    out = {**raw, "crew_payment": {"request_id": entry["request_id"], "origin": entry["origin"], "state": entry["state"],
                                   "fill": fill, "fill_error": fill_error}}
    if fill == "filled":
        out["next"] = NEXT
    if fill_error == "no_fields":
        out.update(success=False, error=NO_FIELDS)
    if raw.get("error_type") == "payment_declined" and entry["state"] in DECLINED:
        out["error"] = DECLINED[entry["state"]]
    return out
