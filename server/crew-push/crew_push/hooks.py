import functools
import hashlib
import json
import logging
import re
import threading
import time
from collections import OrderedDict
from dataclasses import dataclass
from typing import Any, Callable, Literal

from . import apns, payments, store

log = logging.getLogger("crew_push")

Kind = Literal["reply", "turn_error", "approval", "clarify", "routine", "payment"]

HOOK_NAMES = ("pre_llm_call", "post_llm_call", "on_session_end", "pre_tool_call", "post_tool_call",
              "pre_approval_request", "post_approval_response", "transform_tool_result", "subagent_start")
BOT_CHAT_TITLE = "Bot Chat"
CLAIM_SECONDS = 60


@dataclass(frozen=True)
class KindStyle:
    pref: str
    category: str
    level: str
    hold_seconds: int
    generic: str


KINDS: dict[str, KindStyle] = {
    "reply": KindStyle("replies", "CREW_REPLY", "active", 3600, "Replied"),
    "turn_error": KindStyle("replies", "CREW_REPLY", "active", 3600, "Turn failed"),
    "approval": KindStyle("approvals", "CREW_APPROVAL", "time-sensitive", 300, "Needs approval"),
    "clarify": KindStyle("questions", "CREW_QUESTION", "time-sensitive", 3600, "Has a question"),
    "routine": KindStyle("routines", "CREW_ROUTINE", "passive", 3600, "Routine finished"),
    "payment": KindStyle("approvals", "CREW_PAYMENT", "time-sensitive", 300, "Wants to pay"),
}

MARKDOWN = (
    (re.compile(r"```[^\n]*"), ""),
    (re.compile(r"!?\[([^\]]*)\]\([^)]*\)"), r"\1"),
    (re.compile(r"^[ \t]*(?:#{1,6}|>|[-*+]|\d+\.)[ \t]+", re.MULTILINE), ""),
    (re.compile(r"\*\*|__|~~|`|(?<!\w)\*|\*(?!\w)"), ""),
)


AGENT_MESSAGE = re.compile(r"Message from (?:🤖\s*)?[^:\n(]{1,64}?(?:\s*\(@[a-z0-9][a-z0-9_-]{0,63}"
                           r"(?:@[a-zA-Z0-9][a-zA-Z0-9_-]{0,63})?\))?:|\[Message from agent '[^']{1,64}'\]")
DELIVERY = re.compile(r"\[IMPORTANT: Background process (proc_[0-9a-f]+)\b.*bot_mode_dm\.py --run-delivery", re.DOTALL)
PROCESS_ID = re.compile(r'"process_id":\s*"(proc_[0-9a-f]+)"')


def plain(markdown: str) -> str:
    text = markdown
    for pattern, replacement in MARKDOWN:
        text = pattern.sub(replacement, text)
    return text


def clip(text: str, limit: int) -> str:
    flat = " ".join(text.split())
    return flat if len(flat) <= limit else flat[: limit - 1].rstrip() + "…"


@dataclass(frozen=True)
class Event:
    kind: Kind
    title: str
    profile: str
    session_id: str
    ref: str
    body: str
    subtitle: str = ""
    request_id: str = ""
    expires_at: float = 0.0


def build(event: Event, device: store.Device, *, install_id: str, now: float) -> tuple[dict[str, str], dict[str, Any]]:
    style = KINDS[event.kind]
    previews = bool(device.get("prefs", {}).get("previews", True))
    collapse = event.request_id if event.kind == "payment" else event.session_id
    alert = {"title": event.title, "body": clip(event.body, 400) if previews else style.generic}
    if previews and event.subtitle:
        alert["subtitle"] = clip(event.subtitle, 120)
    headers = {
        "apns-push-type": "alert",
        "apns-priority": "5" if style.level == "passive" else "10",
        "apns-expiration": str(int(event.expires_at or now + style.hold_seconds)),
        "apns-collapse-id": f"{event.kind}.{hashlib.sha256(collapse.encode()).hexdigest()[:16]}",
    }
    event_id = hashlib.sha256(f"{event.session_id}:{event.kind}:{event.ref}".encode()).hexdigest()[:16]
    crew = {"v": 1, "kind": event.kind, "install_id": install_id, "profile": event.profile,
            "session_id": event.session_id, "event_id": event_id}
    if event.request_id:
        crew["request_id"] = event.request_id
    if event.expires_at:
        crew["expires_at"] = event.expires_at
    aps = {"alert": alert, "sound": "default", "thread-id": f"profile.{event.profile}",
           "category": style.category, "interruption-level": style.level}
    return headers, {"aps": aps, "crew": crew}


def build_read(profile: str, session_id: str, read_at: float, *, install_id: str,
               now: float) -> tuple[dict[str, str], dict[str, Any]]:
    headers = {
        "apns-push-type": "background",
        "apns-priority": "5",
        "apns-expiration": str(int(now) + 3600),
        "apns-collapse-id": f"read.{hashlib.sha256(profile.encode()).hexdigest()[:16]}",
    }
    crew = {"v": 1, "kind": "read", "install_id": install_id, "profile": profile, "session_id": session_id,
            "thread-id": f"profile.{profile}", "read_at": read_at}
    return headers, {"aps": {"content-available": 1}, "crew": crew}


def build_resolved(profile: str, request_id: str, state: str, *, install_id: str,
                   now: float) -> tuple[dict[str, str], dict[str, Any]]:
    headers = {
        "apns-push-type": "background",
        "apns-priority": "5",
        "apns-expiration": str(int(now) + 3600),
        "apns-collapse-id": f"payment-resolved.{hashlib.sha256(request_id.encode()).hexdigest()[:16]}",
    }
    crew = {"v": 1, "kind": "payment_resolved", "install_id": install_id, "profile": profile,
            "request_id": request_id, "state": state}
    return headers, {"aps": {"content-available": 1}, "crew": crew}


def bot_name(profile: str) -> str:
    fallback = profile if profile and profile != "default" else "Hermes"
    try:
        from hermes_cli.profiles import get_profile_dir, read_profile_meta

        meta = read_profile_meta(get_profile_dir(profile or "default"))
    except Exception:
        return fallback
    return next((name for key in ("bot_title", "display_name") if (name := str(meta.get(key) or "").strip())),
                fallback)


def job_name(session_id: str) -> str:
    try:
        from cron.jobs import get_job

        job = get_job(session_id.rsplit("_", 2)[0].removeprefix("cron_"))
    except Exception:
        return ""
    return str((job or {}).get("name") or "")


def pending_request_id(session_key: str) -> str:
    try:
        from tools.approval import list_gateway_approvals

        pending = list_gateway_approvals(session_key)
    except Exception:
        return ""
    return str(pending[-1].get("request_id") or "") if pending else ""


def is_bot_chat(profile: str, session_id: str) -> bool:
    from hermes_cli.profiles import get_profile_dir
    from hermes_state import SessionDB

    db = SessionDB(db_path=get_profile_dir(profile) / "state.db", read_only=True)
    try:
        row = db.get_session_by_title(BOT_CHAT_TITLE)
        return bool(row) and db.get_compression_tip(row["id"]) == session_id
    finally:
        db.close()


def browser_open(task_id: str) -> bool:
    from tools.browser_supervisor import SUPERVISOR_REGISTRY
    from tools.browser_tool import _active_sessions, _last_session_key

    return SUPERVISOR_REGISTRY.get(task_id) is not None or bool(_active_sessions.get(_last_session_key(task_id)))


def card_page_origin(task_id: str) -> str | None:
    from tools.browser_vault_tool import _TAB_PROBES, _current_page_origin, _eval_js

    if not browser_open(task_id):
        return None
    probe = _eval_js(task_id, _TAB_PROBES["payment"])
    return _current_page_origin(task_id) if probe.get("success") and probe.get("result") in (True, "true") else None


def no_page_block(origin: str) -> dict[str, str]:
    try:
        from tools.browser_use_cli import is_browser_use_cli_mode

        browser_use = is_browser_use_cli_mode()
    except Exception:
        browser_use = False
    how = 'browser_exec first (new_tab("<checkout URL>"))' if browser_use else "browser_navigate first"
    return payments.block("crew_no_shop_page", f"No browser page is open on {origin}. Open the checkout with {how}, "
                                               "then call browser_vault fill again.")


def shop_tab_block(task_id: str, origins: list[str]) -> dict[str, str] | None:
    try:
        from tools.browser_vault_tool import _current_page_origin, _ensure_supervisor, _focus_bound_origin

        if not browser_open(task_id) or _ensure_supervisor(task_id) is None:
            return no_page_block(origins[0])
        if any(_focus_bound_origin(task_id, origin, "payment") for origin in origins):
            return None
        offer = card_page_origin(task_id)
        page = _current_page_origin(task_id)
    except Exception:
        log.warning("crew-push: could not read the browser for a payment fill, blocking it", exc_info=True)
        return no_page_block(origins[0])
    if offer and offer not in origins:
        return payments.block("crew_no_shop_card", payments.no_card_for(offer), missing_shop=offer)
    if page in origins:
        return payments.block("crew_no_shop_card", f"No open tab on {page} shows card fields. Open the shop's "
                                                   "checkout there; if its card fields sit in a payment frame, they "
                                                   "can't be filled, so tell the user.")
    return no_page_block(origins[0])


def redact(command: str) -> str:
    try:
        from agent.redact import redact_sensitive_text
    except Exception:
        return ""
    return redact_sensitive_text(command, force=True)


class Recent(OrderedDict[str, Any]):
    def remember(self, key: str, value: Any) -> None:
        self[key] = value
        self.move_to_end(key)
        while len(self) > 4096:
            self.popitem(last=False)


def quiet(hook: Callable[..., Any]) -> Callable[..., Any]:
    @functools.wraps(hook)
    def guarded(*args: Any, **kwargs: Any) -> Any:
        try:
            return hook(*args, **kwargs)
        except Exception:
            log.warning("crew-push: %s failed, a push was dropped", hook.__name__, exc_info=True)
            return None
    return guarded


class CrewPush:
    is_crew_push = True

    def __init__(self, profile: str) -> None:
        self.profile = profile or "default"
        self.lock = threading.Lock()
        self.platforms = Recent()
        self.replies = Recent()
        self.subagents = Recent()
        self.sent = Recent()
        self.bot_chats = Recent()
        self.agent_turns = Recent()
        self.agent_processes = Recent()
        self.user_turns = Recent()
        self.claims = Recent()

    @quiet
    def pre_llm_call(self, *, session_id: str = "", platform: str = "", user_message: Any = "",
                     **_: Any) -> dict[str, str] | None:
        if not session_id:
            return None
        text = str(user_message or "").strip()
        delivery = DELIVERY.match(text)
        user_turn = bool(user_message) and not (isinstance(user_message, str) and text.startswith("[")) \
            and not AGENT_MESSAGE.match(text) and not delivery
        with self.lock:
            self.agent_turns.remember(session_id, bool(AGENT_MESSAGE.match(text))
                                      or bool(delivery and delivery[1] in self.agent_processes))
            previous_turn = self.user_turns.get(session_id, 0.0)
            if user_turn:
                self.user_turns.remember(session_id, time.time())
            if platform:
                self.platforms.remember(session_id, platform.lower())
        if not user_turn:
            return None
        entries = [entry for entry in store.read_list("payments.json") if entry.get("session_id") == session_id]
        if entries and entries[-1].get("state") in ("denied", "expired") \
                and previous_turn <= (entries[-1].get("decided_at") or 0.0):
            return {"context": payments.RETRY_NOTE}
        return None

    @quiet
    def post_llm_call(self, *, session_id: str = "", assistant_response: Any = "", **_: Any) -> None:
        with self.lock:
            self.replies.remember(session_id, str(assistant_response or ""))

    @quiet
    def subagent_start(self, *, child_session_id: str | None = None, **_: Any) -> None:
        if child_session_id:
            with self.lock:
                self.subagents.remember(child_session_id, True)

    @quiet
    def on_session_end(self, *, session_id: str = "", turn_id: str = "", completed: bool = False,
                       failed: bool = False, interrupted: bool = False, turn_exit_reason: str = "",
                       platform: str = "", **_: Any) -> None:
        with self.lock:
            reply = self.replies.pop(session_id, "")
            from_agent = self.agent_turns.pop(session_id, False)
            if session_id and platform:
                self.platforms.remember(session_id, platform.lower())
        ref = turn_id or str(int(time.time()))
        if interrupted or from_agent or session_id in self.subagents:
            return
        if self.platforms.get(session_id) == "cron":
            body = plain(reply) or ("The routine failed." if failed else "The routine finished.")
            self.notify("routine", session_id, ref, body=body, subtitle=job_name(session_id))
            return
        if failed:
            self.notify("turn_error", session_id, ref, body=turn_exit_reason or "The turn failed.")
            return
        if completed and reply:
            self.notify("reply", session_id, ref, body=plain(reply))

    def pre_tool_call(self, *, tool_name: str = "", args: Any = None, session_id: str = "",
                      tool_call_id: str = "", task_id: str = "", **_: Any) -> dict[str, str] | None:
        if tool_name == "tool_call":
            try:
                from tools.tool_search import resolve_underlying_call

                underlying, inner, _error = resolve_underlying_call(args)
            except Exception:
                return payments.block("crew_check_failed") if "browser_vault" in str(args) else None
            if underlying == "browser_vault":
                tool_name, args = underlying, inner
        if tool_name == "browser_vault" and isinstance(args, dict) and args.get("action") == "fill":
            try:
                return self.check_payment(args, session_id, tool_call_id, task_id or "default")
            except Exception:
                log.warning("crew-push: checking a payment fill failed, blocking it", exc_info=True)
                return payments.block("crew_check_failed")
        self.push_question(tool_name=tool_name, args=args, session_id=session_id, tool_call_id=tool_call_id)
        return None

    def check_payment(self, args: dict[str, Any], session_id: str, tool_call_id: str,
                      task_id: str) -> dict[str, str] | None:
        from agent.vault_backends import backend_for_handle
        from tools.approval import list_gateway_approvals
        from tools.approval_context import get_current_session_key

        handle = str(args.get("handle") or "")
        backend = backend_for_handle(handle)
        item = backend.get_meta(handle) if backend is not None else None
        if item is None or item.kind != "payment":
            return None
        if store.read_gate() is not True:
            return payments.block("crew_gate_off")
        if not session_id or not is_bot_chat(self.profile, session_id):
            return payments.block("crew_not_bot_chat")
        command = payments.command_for(item.label, str(item.origin))
        session_key = get_current_session_key()
        pending = list_gateway_approvals(session_key)
        entries = [entry for entry in store.read_list("payments.json") if entry.get("session_id") == session_id]
        now = time.time()
        if any(entry.get("state") == "pending" and (entry.get("expires_at") or 0) > now for entry in entries) \
                or any(approval.get("command") == command for approval in pending):
            return payments.block("crew_one_at_a_time")
        with self.lock:
            user_turn = self.user_turns.get(session_id, 0.0)
        if entries and entries[-1].get("state") in ("denied", "expired") \
                and user_turn <= (entries[-1].get("decided_at") or now):
            return payments.block("crew_after_decline")
        claim = payments.claim(args)
        if claim is None:
            return payments.block("crew_missing_details")
        if item.origin and (blocked := shop_tab_block(task_id, list(item.allowed_origins) or [item.origin])):
            return blocked
        with self.lock:
            if any(key != tool_call_id and other["session_id"] == session_id and "request_id" not in other
                   and other["at"] > now - CLAIM_SECONDS for key, other in self.claims.items()):
                return payments.block("crew_one_at_a_time")
            if tool_call_id:
                self.claims.remember(tool_call_id, {
                    **claim, "origin": item.origin, "label": item.label, "command": command, "at": now,
                    "session_id": session_id, "session_key": session_key,
                    "snapshot": {str(approval.get("request_id") or "") for approval in pending}})
        return None

    @quiet
    def push_question(self, *, tool_name: str, args: Any, session_id: str, tool_call_id: str) -> None:
        if tool_name != "clarify":
            return
        args = args if isinstance(args, dict) else {}
        questions = args.get("questions")
        first = questions[0] if isinstance(questions, list) and questions else {"question": args.get("question")}
        question = str((first.get("question") if isinstance(first, dict) else first) or "")
        self.notify("clarify", session_id, tool_call_id or str(int(time.time())),
                    body=plain(question) or "Has a question for you.")

    @quiet
    def post_tool_call(self, *, tool_name: str = "", result: Any = "", session_id: str = "", **_: Any) -> None:
        if tool_name != "message_agent":
            return
        with self.lock:
            if self.agent_turns.get(session_id):
                for process in PROCESS_ID.findall(str(result or "")):
                    self.agent_processes.remember(process, True)

    @quiet
    def pre_approval_request(self, *, command: str = "", description: str = "", session_id: str = "",
                             session_key: str = "", surface: str = "", tool_call_id: str = "",
                             coalesced: bool = False, **_: Any) -> None:
        if surface == "vault-payment":
            if not coalesced:
                self.bind_payment(command, session_key, tool_call_id)
            return
        if surface == "smart":
            return
        self.notify("approval", session_id or session_key, tool_call_id or str(int(time.time())),
                    body=redact(command) or "Needs your approval.", subtitle=description,
                    request_id=pending_request_id(session_key))

    def bind_payment(self, command: str, session_key: str, tool_call_id: str) -> None:
        from tools.approval import list_gateway_approvals
        from tools.approval_context import _get_approval_timeout

        with self.lock:
            claim = self.claims.get(tool_call_id) if tool_call_id else None
        if claim is None or "request_id" in claim or claim["command"] != command or claim["session_key"] != session_key:
            return
        fresh = [approval for approval in list_gateway_approvals(session_key)
                 if approval.get("command") == command and str(approval.get("request_id") or "") not in claim["snapshot"]]
        if len(fresh) != 1 or not fresh[0].get("request_id"):
            return
        request_id = str(fresh[0]["request_id"])
        host = payments.host_of(claim["origin"])
        now = time.time()
        entry = {"request_id": request_id, "profile": self.profile, "session_id": claim["session_id"],
                 "session_key": session_key, "tool_call_id": tool_call_id, "command": command,
                 "origin": claim["origin"], "host": host, "card_label": claim["label"].removesuffix(f" · {host}"),
                 "amount": claim["amount"], "merchant": claim["merchant"], "reason": claim["reason"],
                 "state": "pending", "fill": None, "fill_error": None, "created_at": now,
                 "expires_at": now + _get_approval_timeout(), "decided_at": None}
        store.mutate_payments(lambda entries: [*entries, entry])
        with self.lock:
            claim["request_id"] = request_id
        self.notify("payment", claim["session_id"], request_id,
                    body=f"{claim['amount']} · {claim['merchant']} · {claim['reason']}", subtitle=f"Pay at {host}?",
                    request_id=request_id, expires_at=entry["expires_at"])

    @quiet
    def post_approval_response(self, *, command: str = "", session_key: str = "", surface: str = "",
                               choice: str = "", coalesced: bool = False, tool_call_id: str = "", **_: Any) -> None:
        if surface != "vault-payment" or coalesced:
            return
        entry = next((entry for entry in reversed(store.read_list("payments.json"))
                      if entry.get("session_key") == session_key and entry.get("command") == command
                      and entry.get("state") == "pending" and entry.get("tool_call_id") == tool_call_id), None)
        if entry is None:
            return
        state = payments.STATES.get(choice, "cancelled")
        payments.update(entry["request_id"], state=state, decided_at=time.time())
        install_id = store.install_id()
        for device in store.read_devices():
            apns.enqueue(device, *build_resolved(entry["profile"], entry["request_id"], state, install_id=install_id,
                                                 now=time.time()))

    @quiet
    def transform_tool_result(self, *, tool_name: str = "", args: Any = None, result: Any = "",
                              tool_call_id: str = "", task_id: str = "", session_id: str = "", **_: Any) -> str | None:
        if tool_name != "browser_vault" or not isinstance(args, dict) or not isinstance(result, str):
            return None
        raw = json.loads(result)
        if not isinstance(raw, dict):
            return None
        if args.get("action") == "fill":
            with self.lock:
                claim = self.claims.pop(tool_call_id, None) if tool_call_id else None
            entry = payments.find(claim["request_id"]) if claim and "request_id" in claim else None
            if entry is None:
                return None
            decorated = payments.decorate(raw, entry)
            payments.update(entry["request_id"], fill=decorated["crew_payment"]["fill"],
                            fill_error=decorated["crew_payment"]["fill_error"])
            return json.dumps(decorated, ensure_ascii=False)
        if args.get("action") != "list" or not raw.get("success"):
            return None
        page = card_page_origin(task_id or "default")
        shops = {item.get("origin") for item in raw.get("items") or []
                 if isinstance(item, dict) and item.get("kind") == "payment"}
        if not page or page in shops:
            return None
        hint = payments.no_card_for(page) if self.in_bot_chat(session_id) else payments.add_in_crew(page)
        return json.dumps({**raw, "crew_payment": {"missing_shop": page}, "hint": hint}, ensure_ascii=False)

    def in_bot_chat(self, session_id: str) -> bool:
        with self.lock:
            if session_id in self.bot_chats:
                return self.bot_chats[session_id]
        try:
            found = is_bot_chat(self.profile, session_id)
        except Exception:
            log.debug("crew-push: could not resolve the Bot Chat session", exc_info=True)
            return False
        with self.lock:
            self.bot_chats.remember(session_id, found)
        return found

    def notify(self, kind: Kind, session_id: str, ref: str, *, body: str, subtitle: str = "",
               request_id: str = "", expires_at: float = 0.0) -> None:
        if not session_id:
            return
        if self.platforms.get(session_id) != "cron" and not self.in_bot_chat(session_id):
            return
        event = Event(kind, bot_name(self.profile), self.profile, session_id, ref, body, subtitle, request_id,
                      expires_at)
        event_key = f"{session_id}:{kind}:{ref}"
        with self.lock:
            if event_key in self.sent:
                return
            self.sent.remember(event_key, True)
        devices = [d for d in store.read_devices() if d.get("prefs", {}).get(KINDS[kind].pref, False)]
        if not devices:
            return
        install_id = store.install_id()
        for device in devices:
            apns.enqueue(device, *build(event, device, install_id=install_id, now=time.time()))
