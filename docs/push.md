# Push notifications

Design for layer 7: APNs on iOS and macOS for finished bot turns, approvals, questions and (opt-in) routine runs, delivered when Crew is not connected. Research date 2026-10-13, against Hermes **v0.21.7** (`git show v0.21.7:<path>` in `~/.hermes/hermes-agent`) and `uzairansaruzi/hermex-push` at `master` (plugin 0.4.0). Nothing here was sent to the test server.

## TL;DR

- **Build a small Hermes plugin, `crew-push`, that talks to APNs directly** with a token-based `.p8` key that lives on the Hermes host. No relay, no Cloudflare, no payload encryption, no Notification Service Extension.
- The plugin observes four stock hooks (`pre_llm_call`, `post_llm_call`, `on_session_end`, `pre_approval_request`) plus `pre_tool_call` for the `clarify` tool, and mounts three dashboard routes under `/api/plugins/crew-push/` (behind the normal dashboard login) for device registration.
- One APNs topic, `dev.gustaf.crew`, for both platforms. The client reports its APNs environment (`sandbox` or `production`) when it registers; one `.p8` serves both environments.
- Hermex's relay cannot be reused as is: it only accepts Hermex's two bundle ids and signs with Hermex's own APNs key, which cannot push to `dev.gustaf.crew`.
- Manual steps, done once: create the APNs key, copy it to the host, copy the plugin to the host and enable it. Details in [Manual steps](#manual-steps-once).

## 1. How Hermex does it

Sources: `hermex-push/plugin/**`, `hermex-push/relay/**`, `hermex/docs/agents/push.md`.

**Pieces.** A Hermes plugin (`hermex-push`, `kind: platform`, platform name `hermex`) on the host, a Cloudflare Worker relay (KV + one Durable Object per install) that holds device tokens and the APNs key, and the iPhone app with a Notification Service Extension (NSE).

**Hooks used** (`hooks.py`): `pre_llm_call` (remember the session's platform, start Live Activity progress), `post_llm_call` (capture `user_message` + `assistant_response`), `on_session_end` (the one turn boundary: send `reply`, or `turn_error` when `failed`, nothing when `interrupted`), `pre_tool_call` with `tool_name == "clarify"` (question banner), `post_tool_call` (progress), `pre_approval_request` / `post_approval_response` (approval banner; `surface == "smart"` skipped because nobody is waiting), `subagent_start` (mark child sessions so their replies can be muted). They chose the approval *observer* hooks over `register_approval_transport` because a registered transport replaces every built-in approval surface.

**Session filtering** (`sources.py`): fail closed. A session whose platform was never named by a turn hook gets nothing; chat platforms that already notify (`telegram`, `discord`, `slack`, `signal`, ... ~30 names) are skipped; `cron_*` and `kanban_*` sessions are skipped.

**Payload to the relay.** `POST {relay}/installs/{install_key}/notify` with `{v, kind, event_id, thread_id, collapse_id, session_id, source, is_subagent, sent_at, sealed}`. `sealed` is AES-256-GCM over `{title, subtitle, body, profile, request_id, bot_name}` with a host-generated preview key; ids are HMACs of the install key. The relay sends APNs a generic "Hermex / New activity" alert with `mutable-content: 1`, and the NSE decrypts `sealed` and rewrites the banner. Approvals, questions and errors are `time-sensitive`; approvals expire after 5 min, the rest after 1 h. A `progress` kind drives Live Activities.

**Device registration.** The phone never types a key:
1. `GET /api/plugins/hermex-push/pairing` (dashboard auth). 200 returns `{relay_url, install_key, preview_key, platform, payload_version, plugin_version}`; 409 means `HERMEX_PUSH_RELAY_URL` is unset; 404 means the plugin is not mounted.
2. If needed the app provisions the host itself: `PUT /api/env` (relay URL), `POST /api/dashboard/agent-plugins/install {identifier: "https://github.com/uzairansaruzi/hermex-push.git/plugin", force, enable}`, `POST .../hermex-push/enable`, `POST /api/gateway/restart`, and for updates the plugin's own `POST /api/plugins/hermex-push/restart` (re-execs the dashboard with `os.execv`).
3. The phone then registers its token directly with the relay: `POST {relay}/installs/{install_key}/devices {device_token, bundle_id, environment, prefs}`. The install key is a bearer capability, kept in the Keychain (shared access group with the NSE).

**Profiles.** Each Hermes profile has its own `plugins/` dir and `plugins.enabled`, so a single install would only cover the launch profile. Hermex's `scopes.py` wraps `PluginManager.invoke_hook` / `has_hook` once per process so the first loaded copy serves every profile that has no copy of its own, resolving the profile with `hermes_cli.profiles.get_active_profile_name()`. Keys live under the root home (`<root>/plugin-data/hermex-push/`) so all profiles pair as one host.

**Security posture.** Relay URL must be https (http only to loopback), redirects refused (the key is in the URL path), relay stores only `sha256(install_key)`, Worker logs must stay off, NSE falls back to a content-free banner on any failure.

**What Crew takes from it:** the hook selection, fail-closed filtering, skip-interrupted rule, approval observer choice, the profile fan-out shim, root-home `plugin-data`, the dashboard-route-behind-auth pattern. **What Crew drops:** the relay, the sealing, the NSE, Live Activities, and self-provisioning through `/api/env` and `agent-plugins/install`.

## 2. Hermes v0.21.7 plugin surface

**Structure.** A directory plugin is `plugin.yaml` + `__init__.py` exposing `register(ctx)` (`hermes_cli/plugins.py:1-9`). Sources: bundled, user `<HERMES_HOME>/plugins/<name>/`, opt-in project dir, and pip entry points (`hermes_agent.plugins`). User plugins load only when listed in `plugins.enabled` of that profile's `config.yaml` (`plugins_discovery.py:257-330`). Kinds: `standalone` (default), `backend`, `exclusive`, `platform`, `model-provider` (`plugins_manifest.py:27`). Crew needs `standalone`.

**Lifecycle hooks** (`VALID_HOOKS`, `plugins.py:109-204`), with the kwargs actually passed at v0.21.7:

| Hook | Fire site | Kwargs we use |
|---|---|---|
| `pre_llm_call` | turn start | `session_id`, `platform`, `user_message` |
| `post_llm_call` | `agent/turn_finalizer.py:470` | `session_id`, `turn_id`, `user_message`, `assistant_response`, `platform` |
| `on_session_end` | `agent/turn_finalizer.py:797`, once per `run_conversation()` (i.e. per turn) | `session_id`, `turn_id`, `completed`, `failed`, `interrupted`, `turn_exit_reason`, `platform` |
| `pre_approval_request` | `tools/approval_gateway_wait.py:203` (dashboard/gateway path), `approval_prompt.py`, `approval_smart.py`, `file_tools_write_guards.py` | `command`, `description`, `session_key`, `surface`, plus `session_id`, `turn_id`, `tool_call_id` from context vars (`approval_context.py:55-73`). **No `request_id` on the gateway path.** |
| `pre_tool_call` | every tool call | `tool_name`, `args`, `session_id`, `tool_call_id` |
| `on_human_input_request` / `_resolved` | `tools/human_input_hooks.py` (approval, clarify, sudo) | `kind`, redacted `prompt`, its own `request_id` (not the approval's), `session_id`, `platform` |

`session_id` in every hook is `agent.session_id`, and tui_gateway builds the agent with `session_id=session["session_key"]` (`tui_gateway/methods_session.py:82`, `agent_callbacks.py:612`), which is exactly the `stored_session_id` Crew uses for REST history. Compression rotates it (`session_compression.py:331`), so a tapped notification for an old id must still land on the bot.

There is **no dedicated cron hook**. Cron runs build an `AIAgent(platform="cron", session_id="cron_<job_id>_<YYYYmmdd_HHMMSS>")` (`cron/scheduler.py:2496, 2553`) in the gateway's ticker (or a detached cron worker), so `on_session_end` with `platform == "cron"` is the routine-finished signal, and `cron.jobs.get_job(job_id)` (`cron/jobs.py:1946`) gives the job name.

**Profiles are isolated.** `get_plugin_manager()` keeps one manager per resolved home (`plugins.py:1701`), the user plugin dir is `get_hermes_home()/plugins`, and enablement is per profile config. A profile created by cloning copies `plugins/` (`profiles.py:1322`), a fresh one does not. Every Crew bot is a profile, and Crew creates bots, so per-profile installs would silently miss new bots.

**Dashboard routes from a plugin.** The dashboard scans `<plugins>/*/dashboard/manifest.json` and mounts the manifest's `api` file's `router` (FastAPI `APIRouter`) at `/api/plugins/<name>/`, only for user plugins in the launch profile's `plugins.enabled` (`web_server_dashboard.py:869-890`). All `/api/` routes sit behind the dashboard auth middleware, so Crew's existing session cookie works. Since v0.21.x a plugin enabled after start is **hot-mounted on first request** (`_PluginApiHotMount`), no restart. The SPA expects a `dist/index.js` entry, so ship a no-op one with `"tab": {"hidden": true}`.

**Install API.** `POST /api/dashboard/agent-plugins/install {identifier, force, enable, catalog_name?, ref?}` clones a git URL (split at `.git/` for a subdirectory; `file://` works), then `enable` runs the Python dependency admission and `activate_plugin_now`, which loads the plugin in the dashboard process and nudges the running gateway to reload plugins over its control socket (`plugins_activation.py:96`). It always acts on the dashboard's launch profile (`_config_profile_scope(None)`). `PUT /api/env?profile=` writes a profile's `.env`.

**Dependencies.** `httpx` 0.28.1, `PyJWT[crypto]` and `cryptography` are core deps. `h2` (needed for `httpx.Client(http2=True)`; APNs is HTTP/2 only) appears in the lock only through `grpclib`, so it must be declared. At v0.21.7 a plugin's `pyproject.toml` `[project].dependencies` are installed by Hermes's package manager inside the enable transaction (`plugins_cmd_install.py:69-118`), and `plugin_dev.py:319` warns on unbounded requirements, so declare `h2>=4.1,<5`.

## 3. Options

| | (a) Crew plugin → APNs directly | (b) Reuse hermex-push + relay | (c1) Own relay (fork hermex relay) | (c2) Local notifications only |
|---|---|---|---|---|
| Works for `dev.gustaf.crew` | Yes | **No.** Relay allowlists `com.uzairansar.hermesmobile(.branch)`; APNs JWT is from Uzair's team, so Apple rejects our topic (`DeviceTokenNotForTopic`) | Yes, after deploying a Worker with our key and bundle id | Yes |
| Moving parts | Plugin on a host the user owns | Plugin + someone else's relay + NSE + AES sealing | Plugin + Worker + KV + Durable Object + NSE | None |
| Works with VPN off | Yes (server → Apple) | Yes | Yes | **No.** iOS kills the socket in the background |
| Who sees content | Apple (TLS to APNs, standard for any provider) | Relay sees metadata, content sealed | Same as (b), but it is our relay | Device only |
| Device registration | Authenticated dashboard route on the user's own server | Phone ↔ relay with install-key capability | Same as (b) | n/a |
| Ongoing ops | `.p8` on host | Depends on Uzair's Worker | Cloudflare account, wrangler deploys | None |

(a) wins: the relay exists in Hermex because it serves arbitrary users who should not hold an APNs key; here the user owns both the app's team and the server, and the server already reaches Apple. (c2) stays as the layer 6 fallback when push is not set up.

## 4. Recommendation: `crew-push` plugin

### 4.1 Layout

Lives in this repo so it versions with the app; installed by copying the directory to the host.

```
server/crew-push/
  plugin.yaml
  pyproject.toml              # [project].dependencies = ["h2>=4.1,<5"]
  __init__.py                 # register(): hooks + profile fan-out
  crew_push/
    __init__.py               # PLUGIN_NAME, PLUGIN_VERSION
    store.py                  # root plugin-data paths, apns.json, devices.json
    apns.py                   # ES256 JWT + HTTP/2 sender thread
    hooks.py                  # CrewPush: hook callbacks -> notifications
    fanout.py                 # one install serves every profile (from hermex scopes.py, MIT)
  dashboard/
    manifest.json             # {"name": "crew-push", "tab": {"hidden": true}, "entry": "dist/index.js", "api": "plugin_api.py"}
    dist/index.js             # empty module, the SPA requires an entry
    plugin_api.py             # /status, /devices (POST, DELETE), /test
```

State, all under the **root** home (`hermes_constants.get_default_hermes_root()`), never a profile home, so every profile and every process (dashboard, gateway, cron worker) shares it, and a reinstall cannot unregister devices:

```
~/.hermes/plugin-data/crew-push/
  AuthKey.p8      # 0600, copied by the user
  apns.json       # {"key_id": "ABC123DEFG", "team_id": "82K3YC8HVF", "topic": "dev.gustaf.crew"}
  devices.json    # 0600, written by the dashboard routes, read by every hook process
  install_id      # 16 random hex, created on first use; lets the client tell servers apart later
```

Why files, not `.env`: `.env` reads are profile-scoped and `get_secret` fails closed once a process serves several profiles (see the comment at `web_routers/dashboard_ui.py:_plugin_mutation`); Hermex only bypassed that for a non-secret. The key is a file Apple hands out anyway, and `scp` with mode 0600 is the simplest correct storage.

### 4.2 `plugin.yaml`

```yaml
name: crew-push
label: Crew Push
kind: standalone
version: 0.1.0
description: APNs notifications for the Crew app (finished turns, approvals, questions, routines).
author: Gustaf Eriksson
requires_hermes: ">=0.21.7"
provides_hooks: [pre_llm_call, post_llm_call, on_session_end, pre_tool_call, pre_approval_request, subagent_start]
```

### 4.3 Code sketch

`__init__.py`:

```python
import sys
from pathlib import Path

if (root := str(Path(__file__).resolve().parent)) not in sys.path:
    sys.path.append(root)

from crew_push.fanout import serve_every_profile_in_host
from crew_push.hooks import HOOK_NAMES, CrewPush


def register(ctx) -> None:
    push = CrewPush(profile=getattr(ctx, "profile_name", "") or "default")
    for name in HOOK_NAMES:
        ctx.register_hook(name, getattr(push, name))
    undo = serve_every_profile_in_host()
    if undo is not None:
        ctx.on_unload(undo)
```

`crew_push/store.py`:

```python
import fcntl, json, os, secrets
from pathlib import Path

PLATFORMS = {"ios", "macos"}
ENVIRONMENTS = {"sandbox", "production"}
DEFAULT_PREFS = {"replies": True, "approvals": True, "questions": True, "routines": False, "previews": True}


def data_dir() -> Path:
    from hermes_constants import get_default_hermes_root
    path = Path(get_default_hermes_root()) / "plugin-data" / "crew-push"
    path.mkdir(mode=0o700, parents=True, exist_ok=True)
    return path


def apns_config() -> dict | None:
    directory = data_dir()
    try:
        config = json.loads((directory / "apns.json").read_text())
        return {**config, "key": (directory / "AuthKey.p8").read_text()}
    except (OSError, ValueError):
        return None


def install_id() -> str:
    path = data_dir() / "install_id"
    if not path.exists():
        path.write_text(secrets.token_hex(8))
    return path.read_text().strip()


def read_devices() -> list[dict]:
    try:
        return json.loads((data_dir() / "devices.json").read_text())
    except (OSError, ValueError):
        return []


def mutate_devices(change) -> list[dict]:
    path = data_dir() / "devices.json"
    with open(data_dir() / ".lock", "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        devices = change(read_devices())
        tmp = path.with_suffix(".tmp")
        tmp.write_text(json.dumps(devices))
        os.chmod(tmp, 0o600)
        os.replace(tmp, path)
    return devices
```

`crew_push/apns.py`: one daemon thread per process drains a bounded queue, one HTTP/2 connection per APNs host, JWT cached 50 minutes (Apple: refresh between 20 and 60 minutes).

```python
import logging, queue, threading, time
import httpx, jwt
from . import store

log = logging.getLogger("crew_push")
HOSTS = {"production": "https://api.push.apple.com", "sandbox": "https://api.sandbox.push.apple.com"}
_queue: "queue.Queue[tuple[dict, dict, dict]]" = queue.Queue(maxsize=256)
_token: tuple[float, str] = (0.0, "")
_client: httpx.Client | None = None


def enqueue(device: dict, headers: dict, payload: dict) -> None:
    try:
        _queue.put_nowait((device, headers, payload))
    except queue.Full:
        log.warning("crew-push: queue full, dropping a push")
        return
    _ensure_worker()


def _bearer(config: dict) -> str:
    global _token
    issued, token = _token
    if time.time() - issued < 3000:
        return token
    token = jwt.encode({"iss": config["team_id"], "iat": int(time.time())}, config["key"],
                       algorithm="ES256", headers={"kid": config["key_id"]})
    _token = (time.time(), token)
    return token


def _send(device: dict, headers: dict, payload: dict) -> None:
    global _client
    config = store.apns_config()
    if config is None:
        return
    _client = _client or httpx.Client(http2=True, timeout=10, follow_redirects=False)
    response = _client.post(
        f"{HOSTS[device['environment']]}/3/device/{device['token']}", json=payload,
        headers={"authorization": f"bearer {_bearer(config)}", "apns-topic": config["topic"], **headers})
    if response.status_code == 410 or response.json().get("reason") in ("BadDeviceToken", "DeviceTokenNotForTopic", "Unregistered"):
        store.mutate_devices(lambda ds: [d for d in ds if d["token"] != device["token"]])
        return
    if response.status_code >= 300:
        log.warning("crew-push: APNs %s %s", response.status_code, response.json().get("reason"))


def _drain() -> None:
    while True:
        device, headers, payload = _queue.get()
        try:
            _send(device, headers, payload)
        except Exception:
            log.warning("crew-push: send failed", exc_info=False)


_worker: threading.Thread | None = None


def _ensure_worker() -> None:
    global _worker
    if _worker is None or not _worker.is_alive():
        _worker = threading.Thread(target=_drain, name="crew-push-apns", daemon=True)
        _worker.start()
```

(Real code: guard `response.json()` for empty 200 bodies, one retry on 5xx/network error for non-reply kinds, never log tokens or bodies.)

`crew_push/hooks.py`:

```python
import hashlib, time
from collections import OrderedDict
from . import apns, store

HOOK_NAMES = ("pre_llm_call", "post_llm_call", "on_session_end", "pre_tool_call", "pre_approval_request", "subagent_start")
NATIVE_NOTIFY_PLATFORMS = frozenset({"telegram", "discord", "whatsapp", "whatsapp_cloud", "slack", "signal",
    "mattermost", "matrix", "homeassistant", "email", "sms", "teams", "google_chat", "ntfy", "line", "irc"})
KINDS = {  # kind: (pref, category, interruption-level, seconds APNs may hold it)
    "reply": ("replies", "CREW_REPLY", "active", 3600),
    "turn_error": ("replies", "CREW_REPLY", "active", 3600),
    "approval": ("approvals", "CREW_APPROVAL", "time-sensitive", 300),
    "clarify": ("questions", "CREW_QUESTION", "time-sensitive", 3600),
    "routine": ("routines", "CREW_ROUTINE", "passive", 3600),
}


class Recent(OrderedDict):
    def remember(self, key, value):
        self[key] = value
        self.move_to_end(key)
        while len(self) > 4096:
            self.popitem(last=False)


class CrewPush:
    is_crew_push = True

    def __init__(self, profile: str):
        self.profile = profile
        self.platforms = Recent()
        self.replies = Recent()
        self.subagents = Recent()

    def pre_llm_call(self, *, session_id="", platform="", **_):
        if session_id and platform:
            self.platforms.remember(session_id, platform.lower())

    def post_llm_call(self, *, session_id="", assistant_response="", **_):
        self.replies.remember(session_id, str(assistant_response or ""))

    def subagent_start(self, *, child_session_id=None, **_):
        if child_session_id:
            self.subagents.remember(child_session_id, True)

    def on_session_end(self, *, session_id="", completed=False, failed=False, interrupted=False,
                       turn_id="", turn_exit_reason="", platform="", **_):
        reply = self.replies.pop(session_id, "")
        if interrupted or session_id in self.subagents:
            return
        if platform == "cron":
            self._notify("routine", session_id, turn_id, subtitle=_job_name(session_id), body=reply)
            return
        if failed:
            self._notify("turn_error", session_id, turn_id, body=turn_exit_reason or "The turn failed.")
            return
        if completed and reply:
            self._notify("reply", session_id, turn_id, body=reply)

    def pre_tool_call(self, *, tool_name="", args=None, session_id="", tool_call_id="", **_):
        if tool_name != "clarify":
            return
        questions = (args or {}).get("questions") or [{"question": (args or {}).get("question", "")}]
        first = questions[0].get("question", "") if isinstance(questions[0], dict) else str(questions[0])
        self._notify("clarify", session_id, tool_call_id, body=first or "Has a question for you.")

    def pre_approval_request(self, *, command="", description="", session_id="", session_key="",
                             surface="", tool_call_id="", **_):
        if surface == "smart":
            return
        from agent.redact import redact_sensitive_text
        self._notify("approval", session_id or session_key, tool_call_id or str(time.time()),
                     subtitle=description, body=redact_sensitive_text(command, force=True),
                     request_id=_pending_request_id(session_key))

    def _notify(self, kind, session_id, ref, *, body="", subtitle="", request_id=""):
        platform = self.platforms.get(session_id, "cron" if kind == "routine" else "")
        if not session_id or not platform or platform in NATIVE_NOTIFY_PLATFORMS:
            return
        pref, category, level, hold = KINDS[kind]
        bot = _bot_name(self.profile)
        for device in store.read_devices():
            if not device["prefs"].get(pref, False):
                continue
            previews = device["prefs"].get("previews", True)
            apns.enqueue(device, {
                "apns-push-type": "alert", "apns-priority": "10" if level != "passive" else "5",
                "apns-expiration": str(int(time.time()) + hold),
                "apns-collapse-id": f"{kind}.{_short(session_id)}",
            }, {
                "aps": {
                    "alert": {"title": bot, **({"subtitle": _clip(subtitle, 120)} if previews and subtitle else {}),
                              "body": _clip(body, 400) if previews else _generic(kind)},
                    "sound": "default", "thread-id": f"profile.{self.profile}", "category": category,
                    "interruption-level": level,
                },
                "crew": {"v": 1, "kind": kind, "install_id": store.install_id(), "profile": self.profile,
                         "session_id": session_id, "event_id": _short(f"{session_id}:{kind}:{ref}"),
                         **({"request_id": request_id} if request_id else {})},
            })
```

(Helpers `_short` = first 16 hex of sha256, `_clip` flattens markdown to plain text and truncates, `_generic(kind)` returns "Replied", "Needs approval", "Has a question", "Routine finished", `_bot_name(profile)` reads `ui_meta["hermes-bots"].title` then `display_name` via `hermes_cli.profiles.read_profile_meta(get_profile_dir(profile))` with the slug as fallback, exactly as Hermex's `bot_name_for`. `_job_name` parses `cron_<job>_<date>_<time>` with `rsplit("_", 2)[0][5:]` and calls `cron.jobs.get_job`. `_pending_request_id(session_key)` reads the newest entry of `tools.approval.list_gateway_approvals(session_key)`; on the gateway path the entry is queued before the hook fires, so this recovers the id the hook omits. All best effort; every callback is wrapped in `try/except` and logs, a push must never break a turn.)

Approval session identity, verified: tool calls run inside `model_tools._approval_observability`, which binds `session_id` (the agent's, i.e. the stored id) into the approval context vars that `_fire_approval_hook` copies into the hook kwargs, and tui_gateway binds `set_current_session_key(session["session_key"])` around every turn (`tui_gateway/prompt_turn.py:667`), so on Crew's path `session_id` and `session_key` are both the stored id and the `platforms` lookup from `pre_llm_call` matches. If a future version stops passing `session_id`, remember `session_key -> session_id` from `on_human_input_request` (it carries both) instead of guessing.

`crew_push/fanout.py`: Hermex's `scopes.py`, trimmed. It wraps `PluginManager.invoke_hook` and `has_hook` once per process (marker attribute on the class), and for a hook in `HOOK_NAMES` on a manager whose callbacks contain no `is_crew_push` instance it calls a lazily created `CrewPush(profile=get_active_profile_name())`. Verified at v0.21.7: `invoke_hook`, `has_hook`, `iter_hook_callbacks` live on `PluginDispatchMixin` (`plugins_dispatch.py:211, 481, 523`) and `get_active_profile_name` at `profiles.py:2100`. `plugin_api.py` also calls `serve_every_profile_in_host()` on import, because the dashboard imports the API file at startup even if the launch profile never runs a turn, and the dashboard process is where Crew's bot turns run.

`dashboard/plugin_api.py`:

```python
import re, sys, time
from pathlib import Path
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

if (root := str(Path(__file__).resolve().parents[1])) not in sys.path:
    sys.path.append(root)

from crew_push import PLUGIN_VERSION, store
from crew_push.fanout import serve_every_profile_in_host

serve_every_profile_in_host()
router = APIRouter()
TOKEN = re.compile(r"^[0-9a-f]{64,200}$")


class Device(BaseModel):
    token: str
    platform: str
    environment: str
    name: str = Field(default="", max_length=80)
    prefs: dict[str, bool] = {}


@router.get("/status")
def status():
    return {"plugin_version": PLUGIN_VERSION, "install_id": store.install_id(),
            "apns_configured": store.apns_config() is not None, "devices": len(store.read_devices())}


@router.post("/devices")
def register(device: Device):
    if not TOKEN.match(device.token) or device.platform not in store.PLATFORMS or device.environment not in store.ENVIRONMENTS:
        raise HTTPException(400, "invalid device")
    record = {**device.model_dump(), "prefs": {**store.DEFAULT_PREFS, **device.prefs}, "registered_at": int(time.time())}
    store.mutate_devices(lambda ds: [d for d in ds if d["token"] != device.token][-31:] + [record])
    return {"ok": True, "install_id": store.install_id(), "apns_configured": store.apns_config() is not None}


@router.delete("/devices/{token}")
def unregister(token: str):
    store.mutate_devices(lambda ds: [d for d in ds if d["token"] != token])
    return {"ok": True}


@router.post("/test")
def test(body: dict):
    ...  # enqueue one "reply"-shaped push to body["token"] only; 404 if not registered, 409 if APNs unconfigured
```

### 4.4 Registration API (Crew → dashboard, cookie auth, same as every other `/api` call)

| Method | Path | Body | Answer |
|---|---|---|---|
| GET | `/api/plugins/crew-push/status` | | `200 {plugin_version, install_id, apns_configured, http2, devices}`. **404** = plugin not installed or not enabled in the launch profile. `http2: false` = `h2` is missing in the dashboard's environment (added during implementation: Hermes runs from a managed environment, so checking `h2` by hand on the host is unreliable) |
| POST | `/api/plugins/crew-push/devices` | `{token, platform: "ios"\|"macos", environment: "sandbox"\|"production", name, prefs: {replies, approvals, questions, routines, previews}}` | `200 {ok, install_id, apns_configured}`. Upsert by token; also the way to change prefs |
| DELETE | `/api/plugins/crew-push/devices/{token}` | | `200 {ok}`, idempotent |
| POST | `/api/plugins/crew-push/test` | `{token}` | `202`; sends one push to that device only |
| GET | `/api/plugins/crew-push/payments?profile=` | | crew-push 0.4.0: the Shops card (master card row, shops, `terminal_backend`, `gate`); `/status` also reports `features: ["payments"]` and `gate`. Shapes: [flows/payments-contract.md](flows/payments-contract.md) |
| POST | `/api/plugins/crew-push/payments/shops` | `{profile, site}` | `201 {shop}`: copies the master card to that exact `https` origin |
| DELETE | `/api/plugins/crew-push/payments/shops/{id}?profile=` | | `200 {removed: true}`; only a payment item with an origin |
| GET | `/api/plugins/crew-push/payments/requests/{request_id}` | | the payment request crew-push recorded for an approval, for Hold to Pay |

Security: routes inherit the dashboard's auth gate, Host check and CORS (same as `/api/gateway/restart`), so only a signed-in Crew can register a token. A device token is not a secret capability (it only lets the key holder push to it), and the APNs key never leaves the host. Cap 32 devices. Validate the token as lowercase hex and the enums before writing.

### 4.5 APNs request

Headers: `apns-topic: dev.gustaf.crew`, `apns-push-type: alert`, `apns-priority: 10` (5 for routines), `apns-expiration: now + {approval 300, others 3600}`, `apns-collapse-id: <kind>.<sha256(session_id)[:16]>`. Host by the device's `environment`.

Body (well under the 4 KB limit with the 120/400 character clips):

```json
{
  "aps": {
    "alert": {"title": "Atlas", "subtitle": "Run the migration?", "body": "psql -f 0042_drop_legacy.sql"},
    "sound": "default",
    "thread-id": "profile.atlas",
    "category": "CREW_APPROVAL",
    "interruption-level": "time-sensitive"
  },
  "crew": {
    "v": 1,
    "kind": "approval",
    "install_id": "9f2c41d07ab35e11",
    "profile": "atlas",
    "session_id": "20261013_101512_ab12cd",
    "event_id": "5be0c2a91f7d3e44",
    "request_id": "c0ffee..."
  }
}
```

`kind`: `reply | turn_error | approval | clarify | routine | payment`, plus the silent `read` and `payment_resolved`. Title is always the bot's display name; the kind shows through subtitle/body and the category. `thread-id` groups notifications per bot in Notification Center, like Messages threads.

### 4.6 What is notified, and what is not

- Premise, verified: when iOS drops the socket, `tui_gateway/ws.py:459-466` detaches the session instead of closing it. After `dashboard.ws_orphan_reap_grace_s` (default 20 s) the orphan reaper interrupts a detached turn only if its activity clock is stale (`session_lifecycle.py:851`), so a healthy turn finishes and pushes. A turn parked on an approval or question while detached must keep that clock fresh (`activity_heartbeat` in the approval wait suggests it does); verify on device, and if such turns get interrupted, set `dashboard.ws_orphan_reap_grace_s: 0` on the host (park forever, the pre-reaper behaviour).
- Every completed, non-interrupted turn in a session whose platform is known and not a native chat platform (Telegram etc. already notify). That covers Crew, Hermex, Desktop and TUI turns alike, which is what the user wants from a phone. `on_session_end` with `interrupted=True` (Stop, or a socket drop on the Desktop backend) never pushes.
- Subagent turns: muted (their parent's approval and question banners still go out).
- Turns answering another bot (crew-push 0.3.1): muted when the turn's `user_message` is a `message_agent` delivery (`Message from 🤖 <name> (@<handle>):`, relayed `(@<handle>@<connection>)` or legacy `[Message from agent '<name>']`, Hermes Desktop's `AGENT_MESSAGE_RE`), flagged in `pre_llm_call` so a failed turn is muted too. Approvals and questions raised during such a turn still push: they block the bot until the user answers, and Crew shows them even though the turn is hidden. Since 0.3.2 the follow-up turn of such an exchange is muted too: `post_tool_call` remembers the `process_id` of every `message_agent` call made inside a muted turn, and a later `[IMPORTANT: Background process proc_… bot_mode_dm.py --run-delivery` notice for that process starts a muted turn. A delivery notice for a call the user's own turn made (the sender's chat) is unknown there, so its relay reply still pushes.
- Approvals: all surfaces except `smart` (an auxiliary model decided, nobody waits) and `vault-payment`.
- Payments (crew-push 0.4.0): a `vault-payment` approval that crew-push bound to its own checked fill sends kind `payment` (category `CREW_PAYMENT`, time-sensitive, expiring with the request, collapse id per `request_id`); when it ends, a silent `payment_resolved` goes to every device. Spec: [flows/payments-contract.md](flows/payments-contract.md).
- Questions: the `clarify` tool. `sudo`/`secret` prompts are out of v1; `on_human_input_request` (`kind == "sudo"`) is the hook if wanted later.
- Routines: `platform == "cron"`, off by default per device (`prefs.routines`), passive interruption level.

## 5. Client side

### 5.1 Entitlements and project

- Apple Developer: enable **Push Notifications** on App ID `dev.gustaf.crew` (one App ID serves iOS and macOS; the topic is the bundle id on both).
- `project.yml`: one target, two entitlement files because the key name differs per platform:
  - `Crew-iOS.entitlements`: `aps-environment = $(APS_ENVIRONMENT)`, `com.apple.developer.usernotifications.time-sensitive = true`.
  - `Crew-macOS.entitlements`: `com.apple.developer.aps-environment = $(APS_ENVIRONMENT)`, `com.apple.developer.usernotifications.time-sensitive = true` (plus the existing sandbox/network entitlements).
  - `CODE_SIGN_ENTITLEMENTS[sdk=iphone*]` / `[sdk=macosx*]` pick the file.
  - `APS_ENVIRONMENT = development` for Debug, `production` for Release; `INFOPLIST_KEY_CrewAPSEnvironment = $(APS_ENVIRONMENT)` so the app can report what it was signed with (`development` maps to `sandbox`). The server never guesses, a mismatched token is rejected by Apple with `BadDeviceToken`.
  - Push requires a provisioning profile on macOS too (Mac Development, or Developer ID with the push capability for distribution builds). `build.sh` must use automatic signing with `-allowProvisioningUpdates`.
- iOS `UIBackgroundModes`: `remote-notification` for the silent `read` push that clears a bot's notifications on other devices. No Notification Service Extension, no App Group.

### 5.2 Registration flow

1. `PushRegistrar` (`@Observable`, MainActor) owns: authorization status, device token, last registration fingerprint per server.
2. Ask for authorization (`[.alert, .sound, .badge]`) the first time a turn is started from Crew, or from Settings > Notifications. Never at first launch.
3. After authorization: iOS `UIApplication.shared.registerForRemoteNotifications()`, macOS `NSApplication.shared.registerForRemoteNotifications()`, via an app delegate adaptor (`@UIApplicationDelegateAdaptor` / `@NSApplicationDelegateAdaptor`). Token arrives in `didRegisterForRemoteNotificationsWithDeviceToken`, hex-encoded lowercase.
4. On every successful authenticated connect (layer 1's `connection` reaching connected), if `sha256(token + environment + prefs)` differs from the stored fingerprint or the last registration is older than 7 days: `POST /api/plugins/crew-push/devices`. On 404, show "Push is not set up on this server" with a link to the setup steps; do not retry until the next launch. On `apns_configured: false`, show "APNs key missing on the server".
5. Token change: register the new one, `DELETE` the old one.
6. Sign out: `DELETE /devices/{token}` first (best effort; the server drops it anyway on the first 410).
7. Settings > Notifications: toggles map 1:1 to `prefs` (Replies, Approvals, Questions, Routines, Show previews), a "Send test notification" button (`/test`), and the server status line from `/status`.
8. Layer 6 local notifications are only posted when `/status` said push is unavailable, so the two never double up.

### 5.3 Categories

Registered at launch with `UNUserNotificationCenter.setNotificationCategories`:

- `CREW_REPLY`: action `Reply` (`UNTextInputNotificationAction`) **in v1.1**; v1 has no actions.
- `CREW_APPROVAL`: v1: no actions, tapping opens the approval card. v1.1: `Approve once` and `Deny` (both `.authenticationRequired`, `Deny` also `.destructive`). Never offer `session`/`always` from a banner.
- `CREW_QUESTION`: v1 tap only. v1.1: text input for a single free-text question.
- `CREW_ROUTINE`: tap only.

Every category sets `.hiddenPreviewsShowTitle` so a locked device with "Show previews: when unlocked" still shows the bot name.

### 5.4 Foreground dedupe

`userNotificationCenter(_:willPresent:)` returns `[]` when the app is active, connected, and the notification's `crew.session_id` is the session currently on screen (the transcript already shows it), else `[.banner, .list, .sound]`. On macOS this means a backgrounded but connected Crew still shows banners, which is the desired behaviour. `apns-collapse-id` per kind and session means a second reply replaces the first instead of stacking. When a chat is opened, remove delivered notifications whose `crew.session_id` or `crew.profile` matches (`getDeliveredNotifications` + `removeDeliveredNotifications(withIdentifiers:)`). No server-side presence tracking.

### 5.5 Deep links

`didReceive response` → `PushRoute(profile, sessionID, kind, requestID?)` → the navigation store:

1. Select the bot `profile` in the split view (works offline from the cached bot list).
2. If `session_id` is the bot's chat session, open it; otherwise open that stored session (cron runs, other sessions). If REST says it no longer exists (compressed into a new id), fall back to the bot's chat.
3. For `approval`/`clarify`, the chat shows the card once the WebSocket is live and `session.resume` returns `open_requests`. If the server is unreachable (VPN off), show the transcript with the offline pill; the request is answerable once reconnected (approvals time out after 5 minutes server side, matching `apns-expiration`).

Ignore pushes whose `install_id` does not match the configured server's (`/status`), so a future second server cannot cross-route.

### 5.6 Actionable approvals (v1.1, feasible)

`approval.respond {session_id: <stored id>, choice: "once"|"deny", request_id?}` works without a live session: on session-not-found it falls back to matching `request_id` against every live session's pending approvals, then to `session_id` as a stored id (`tui_gateway/methods_prompt.py:1258-1272, 1423-1443`). So the action handler does: fresh `ws-ticket` → connect → `client.capabilities` → `approval.respond` → disconnect, inside the system's background window for notification actions. Limits: needs network reach (VPN on), so on failure post a local "Couldn't reach Hermes, open Crew to answer" notification; `request_id` is best effort (see 4.3), and without it the oldest pending approval in that session is resolved, so the handler should refuse to act when the payload has no `request_id`. Same transport works for a text reply (`prompt.submit`) and a single clarify answer.

## Manual steps (once)

1. **Apple Developer → Identifiers → `dev.gustaf.crew`**: enable Push Notifications. Regenerate the development (and later Developer ID / distribution) provisioning profiles, or let Xcode automatic signing do it.
2. **Apple Developer → Keys → +**: "Apple Push Notifications service (APNs)", environment **Sandbox & Production**, key restriction **Team Scoped (All Topics)**. Download `AuthKey_<KEYID>.p8` (one chance), note the Key ID. Team ID is `82K3YC8HVF`.
3. **Copy the key to the Hermes host** (as the user that runs Hermes):
   ```sh
   ssh host 'mkdir -p ~/.hermes/plugin-data/crew-push && chmod 700 ~/.hermes/plugin-data/crew-push'
   scp AuthKey_<KEYID>.p8 host:~/.hermes/plugin-data/crew-push/AuthKey.p8
   ssh host 'chmod 600 ~/.hermes/plugin-data/crew-push/AuthKey.p8 && printf %s "{\"key_id\":\"<KEYID>\",\"team_id\":\"82K3YC8HVF\",\"topic\":\"dev.gustaf.crew\"}" > ~/.hermes/plugin-data/crew-push/apns.json'
   ```
4. **Install the plugin** into the root (launch) profile only; the fan-out covers every other profile:
   ```sh
   rsync -a --delete server/crew-push/ host:~/.hermes/plugins/crew-push/
   ssh host 'hermes plugins enable crew-push'     # accept the h2 dependency
   ```
   If the enable does not install `h2` for a copied (not `hermes plugins install`ed) directory, install it into the Hermes venv: `uv pip install --python <hermes venv>/bin/python 'h2>=4.1,<5'`; `/status` should then report the plugin and a test push should succeed.
   Alternative once the repo is reachable from the host: `hermes plugins install https://github.com/<owner>/crew.git/server/crew-push --enable`.
5. **Restart the dashboard and gateway once** (their existing launcher/service) so the profile fan-out is installed in both processes. Enable without restart already loads the hooks for the launch profile and hot-mounts the routes, but the fan-out for other profiles and the gateway's cron path are only certain after a restart.
6. In Crew: Settings > Notifications > Send test notification.

Updates later: rsync again, restart. Device registrations and the key survive because they live in `plugin-data`, not in the plugin dir.

## Verification checklist

- `GET /api/plugins/crew-push/status` without a cookie → 401; with → `apns_configured: true`.
- Debug build (sandbox) on a physical iPhone and on the Mac: test push arrives on both.
- Turn finished in Crew while the iPhone app is backgrounded/killed and the VPN is off: exactly one banner, titled with the bot name, tap opens that bot.
- Same with Crew foreground on that chat: no banner. Foreground on another chat: banner.
- Approval in a non-default profile (proves the fan-out): time-sensitive banner, tap shows the card.
- Stop a running turn: no banner. Telegram-originated turn: no banner. Subagent: no reply banner.
- Routine with `prefs.routines` on: passive banner with the job name.
- Uninstall the app → next push gets 410 → device disappears from `devices.json`.

## Open points for implementation

- The `source` Crew passes to `session.create` (layer 3) decides the hook `platform`. Since crew-push 0.3.0 only the Bot Chat session (and cron routines) notify, whatever its platform; check that the chosen value is not filtered out of session listings (`_LISTING_DENY_SOURCES` in `tui_gateway/methods_session.py:141`).
- Confirm on device that a tapped remote notification's `request.identifier` equals the `apns-collapse-id`; if so, removing delivered notifications can use identifiers directly instead of scanning `userInfo`.
- Later polish, not v1: Communication Notifications (bot avatar on the banner, Messages style) need an NSE + `INSendMessageIntent` + the communication-notifications entitlement; Live Activities for running turns (Hermex's `progress` design is the reference).
