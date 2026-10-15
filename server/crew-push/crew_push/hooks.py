import functools
import hashlib
import logging
import re
import threading
import time
from collections import OrderedDict
from dataclasses import dataclass
from typing import Any, Callable, Literal

from . import apns, store

log = logging.getLogger("crew_push")

Kind = Literal["reply", "turn_error", "approval", "clarify", "routine"]

HOOK_NAMES = ("pre_llm_call", "post_llm_call", "on_session_end", "pre_tool_call", "pre_approval_request",
              "subagent_start")
BOT_CHAT_TITLE = "Bot Chat"


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
}

MARKDOWN = (
    (re.compile(r"```[^\n]*"), ""),
    (re.compile(r"!?\[([^\]]*)\]\([^)]*\)"), r"\1"),
    (re.compile(r"^[ \t]*(?:#{1,6}|>|[-*+]|\d+\.)[ \t]+", re.MULTILINE), ""),
    (re.compile(r"\*\*|__|~~|`|(?<!\w)\*|\*(?!\w)"), ""),
)


AGENT_MESSAGE = re.compile(r"Message from (?:🤖\s*)?[^:\n(]{1,64}?(?:\s*\(@[a-z0-9][a-z0-9_-]{0,63}"
                           r"(?:@[a-zA-Z0-9][a-zA-Z0-9_-]{0,63})?\))?:|\[Message from agent '[^']{1,64}'\]")


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


def build(event: Event, device: store.Device, *, install_id: str, now: float) -> tuple[dict[str, str], dict[str, Any]]:
    style = KINDS[event.kind]
    previews = bool(device.get("prefs", {}).get("previews", True))
    alert = {"title": event.title, "body": clip(event.body, 400) if previews else style.generic}
    if previews and event.subtitle:
        alert["subtitle"] = clip(event.subtitle, 120)
    headers = {
        "apns-push-type": "alert",
        "apns-priority": "5" if style.level == "passive" else "10",
        "apns-expiration": str(int(now) + style.hold_seconds),
        "apns-collapse-id": f"{event.kind}.{hashlib.sha256(event.session_id.encode()).hexdigest()[:16]}",
    }
    event_id = hashlib.sha256(f"{event.session_id}:{event.kind}:{event.ref}".encode()).hexdigest()[:16]
    crew = {"v": 1, "kind": event.kind, "install_id": install_id, "profile": event.profile,
            "session_id": event.session_id, "event_id": event_id}
    if event.request_id:
        crew["request_id"] = event.request_id
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


def quiet(hook: Callable[..., None]) -> Callable[..., None]:
    @functools.wraps(hook)
    def guarded(*args: Any, **kwargs: Any) -> None:
        try:
            hook(*args, **kwargs)
        except Exception:
            log.warning("crew-push: %s failed, a push was dropped", hook.__name__, exc_info=True)
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

    @quiet
    def pre_llm_call(self, *, session_id: str = "", platform: str = "", user_message: Any = "", **_: Any) -> None:
        if not session_id:
            return
        with self.lock:
            self.agent_turns.remember(session_id, bool(AGENT_MESSAGE.match(str(user_message or "").strip())))
            if platform:
                self.platforms.remember(session_id, platform.lower())

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

    @quiet
    def pre_tool_call(self, *, tool_name: str = "", args: Any = None, session_id: str = "",
                      tool_call_id: str = "", **_: Any) -> None:
        if tool_name != "clarify":
            return
        args = args if isinstance(args, dict) else {}
        questions = args.get("questions")
        first = questions[0] if isinstance(questions, list) and questions else {"question": args.get("question")}
        question = str((first.get("question") if isinstance(first, dict) else first) or "")
        self.notify("clarify", session_id, tool_call_id or str(int(time.time())),
                    body=plain(question) or "Has a question for you.")

    @quiet
    def pre_approval_request(self, *, command: str = "", description: str = "", session_id: str = "",
                             session_key: str = "", surface: str = "", tool_call_id: str = "",
                             **_: Any) -> None:
        if surface == "smart":
            return
        self.notify("approval", session_id or session_key, tool_call_id or str(int(time.time())),
                    body=redact(command) or "Needs your approval.", subtitle=description,
                    request_id=pending_request_id(session_key))

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
               request_id: str = "") -> None:
        if not session_id:
            return
        if self.platforms.get(session_id) != "cron" and not self.in_bot_chat(session_id):
            return
        event = Event(kind, bot_name(self.profile), self.profile, session_id, ref, body, subtitle, request_id)
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
