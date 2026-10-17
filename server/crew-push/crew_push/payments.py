import fcntl
import ipaddress
import json
import re
import time
import unicodedata
from collections.abc import Iterator
from contextlib import contextmanager, suppress
from datetime import datetime
from pathlib import Path
from typing import Any
from urllib.parse import urlsplit

from . import store

LIMITS = {"amount": 32, "merchant": 64, "reason": 140}
HOST_LABEL = re.compile(r"^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$")
CARD_FIELDS = ("card_number", "exp_month", "exp_year", "cvc", "cardholder_name", "label")
CARD_NUMBER = re.compile(r"^[0-9]{12,19}$")
EXP_MONTH = re.compile(r"^(?:0?[1-9]|1[0-2])$")
EXP_YEAR = re.compile(r"^(?:[0-9]{2}|[0-9]{4})$")
LABEL_MARKS = frozenset("•·'")
STATES = {"once": "approved", "session": "approved", "always": "approved", "deny": "denied", "timeout": "expired"}
FILL_ERRORS = frozenset({"origin_mismatch", "origin_changed", "human_has_control"})
NO_FIELDS_ERRORS = ("No payment form fields", "No fillable payment field")
PUBLIC_FIELDS = ("request_id", "profile", "session_id", "origin", "host", "card_label", "amount", "merchant", "reason",
                 "state", "fill", "fill_error", "created_at", "expires_at", "decided_at")

NEXT = "Click the shop's pay button. Never tick save card or remember card."
NO_FIELDS = ("The card fields weren't found; this checkout probably puts them in a payment frame, which can't be "
             "filled. Tell the user.")
RETRY_LATER = ("This cancelled only this attempt. \"Never retry payment_declined\" means never retry on your own; "
               "if the user later asks you to pay again, call browser_vault fill again and Crew will ask them to "
               "approve it.")
RETRY_NOTE = ("Note from Crew: the earlier payment_declined only cancelled that attempt. The browser_vault "
              "description's \"never retry payment_declined\" means never retry on your own initiative. If the user "
              "is now asking to pay again, retrying is allowed and expected: call browser_vault fill once more and "
              "Crew will ask the user to approve it. Do not ask for permission again first.")
DECLINED = {
    "denied": "The user denied this payment. Do not retry in this turn; ask what they want instead. " + RETRY_LATER,
    "expired": "Nobody answered within 5 minutes. Tell the user it expired. Do not retry in this turn. " + RETRY_LATER,
    "cancelled": "The request was cancelled. Stop.",
}
BLOCKS = {
    "crew_gate_off": ("Payments are off on this server: its dashboard login is off, or Crew has not connected since "
                      "crew-push started. Tell the user and do not retry."),
    "crew_not_bot_chat": "Payments only work in your Bot Chat in Crew. Tell the user you can only pay from your chat in Crew.",
    "crew_one_at_a_time": "A payment request is already waiting for the user. Wait for their answer; do not ask again.",
    "crew_after_decline": ("The user declined a payment in this turn, so fills are blocked until the user sends a new "
                           "message. Do not retry now. If they ask you to try again in a new message, you may."),
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


class InvalidCard(ValueError):
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


@contextmanager
def vault_lock() -> Iterator[None]:
    with open(store.data_dir() / ".vault.lock", "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        yield


def luhn(digits: str) -> bool:
    doubled = (int(d) * (1 + index % 2) for index, d in enumerate(reversed(digits)))
    return sum(n - 9 if n > 9 else n for n in doubled) % 10 == 0


def card_entry(body: Any, now: datetime) -> tuple[str, dict[str, str]]:
    if not isinstance(body, dict) or not all(isinstance(body.get(key, ""), str) for key in CARD_FIELDS):
        raise InvalidCard("body")
    number = re.sub(r"[ -]", "", body.get("card_number", ""))
    if not CARD_NUMBER.match(number) or not luhn(number):
        raise InvalidCard("number")
    month, year = body.get("exp_month", "").strip(), body.get("exp_year", "").strip()
    if not EXP_MONTH.match(month) or not EXP_YEAR.match(year):
        raise InvalidCard("expiry")
    expiry = (int(year) if len(year) == 4 else 2000 + int(year), int(month))
    if expiry[0] > now.year + 20:
        raise InvalidCard("expiry")
    if expiry < ((now.year, now.month - 1) if now.month > 1 else (now.year - 1, 12)):
        raise InvalidCard("expired")
    cvc = body.get("cvc", "").strip()
    if not re.fullmatch(r"[0-9]{4}" if number[:2] in ("34", "37") else r"[0-9]{3}", cvc):
        raise InvalidCard("cvc")
    name = clean(body.get("cardholder_name", ""))
    if len(name) > 64:
        raise InvalidCard("name")
    label = body.get("label", "").strip()
    if not 0 < len(label) <= 40 or any(c in LABEL_MARKS or (c.isspace() and c != " ")
                                       or unicodedata.category(c) in ("Cc", "Cf") for c in label):
        raise InvalidCard("label")
    secret = {"card_number": number, "exp_month": f"{expiry[1]:02d}", "exp_year": str(expiry[0]), "cvc": cvc}
    return label, {**secret, **({"cardholder_name": name} if name else {})}


def set_master(label: str, secret: dict[str, str]) -> Any:
    with vault_lock():
        vault = master_vault()
        old = [item for item in vault.list_items() if item.kind == "payment" and not item.origin]
        if len(old) > 1:
            raise CardProblem("several")
        card = vault.add_item(kind="payment", label=label, secret=secret)
        try:
            for item in old:
                vault.remove_item(item.id)
        except Exception:
            with suppress(Exception):
                vault.remove_item(card.id)
            raise
        return card


def pending_payment(profile: str) -> bool:
    now = time.time()
    return any(entry.get("profile") == profile and entry.get("state") == "pending"
               and (entry.get("expires_at") or 0) > now for entry in store.read_list("payments.json"))


def update_shops(profile: str) -> None:
    with vault_lock():
        card, secret = master()
        vault = profile_vault(profile)
        current = shops(vault)
        for origin in dict.fromkeys(item.origin for item in current):
            items = [item for item in current if item.origin == origin]
            stale = [item for item in items if vault.resolve_secret(item.id) != secret]
            if not stale:
                continue
            if len(stale) == len(items):
                vault.add_item(kind="payment", label=f"{card.label} •••• {last4(secret)} · {host_of(origin)}",
                               secret=secret, origin=origin)
            for item in stale:
                vault.remove_item(item.id)


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
