import json
import os
from pathlib import Path

import httpx
from fastapi import FastAPI
from fastapi.testclient import TestClient

from hermes_cli import lifecycle
from hermes_cli.plugins import get_plugin_manager
from hermes_cli.web_server_dashboard import _discover_dashboard_plugins, _mount_one_plugin_api
from hermes_constants import set_hermes_home_override

HOOKS = ("pre_llm_call", "post_llm_call", "on_session_end", "pre_tool_call", "pre_approval_request",
         "subagent_start")
TOKEN = "ab" * 32


def turn(session_id: str) -> None:
    lifecycle.invoke_hook("pre_llm_call", session_id=session_id, platform="tui", user_message="hi")
    lifecycle.invoke_hook("post_llm_call", session_id=session_id, assistant_response="**Done.**")
    lifecycle.invoke_hook("on_session_end", session_id=session_id, turn_id="t1", completed=True, failed=False,
                          interrupted=False, platform="tui")


def main() -> None:
    manager = get_plugin_manager()
    manager.discover_and_load()
    result: dict[str, object] = {
        "has_hook": {name: manager.has_hook(name) for name in HOOKS},
        "own_callbacks": [getattr(cb, "__qualname__", "") for cb in manager.iter_hook_callbacks("on_session_end")],
    }

    plugin = next(p for p in _discover_dashboard_plugins() if p["name"] == "crew-push")
    app = FastAPI()
    result["mounted"] = _mount_one_plugin_api(app, plugin, {"crew-push"}, set())
    client = TestClient(app)
    result["status"] = client.get("/api/plugins/crew-push/status").json()
    result["register"] = client.post("/api/plugins/crew-push/devices", json={
        "token": TOKEN, "platform": "ios", "environment": "sandbox", "name": "test"}).status_code

    from crew_push import apns

    sent: list[dict[str, object]] = []

    def fake_apns(request: httpx.Request) -> httpx.Response:
        sent.append(json.loads(request.content))
        return httpx.Response(200)

    apns._client = httpx.Client(transport=httpx.MockTransport(fake_apns))
    turn("launch-session")
    beta = Path(os.environ["HERMES_HOME"]) / "profiles" / "beta"
    set_hermes_home_override(beta)
    beta_manager = get_plugin_manager()
    result["beta_is_separate_manager"] = beta_manager is not manager
    result["beta_own_callbacks"] = len(beta_manager.iter_hook_callbacks("on_session_end"))
    turn("beta-session")
    apns._queue.join()
    result["pushes"] = [{"profile": p["crew"]["profile"], "session_id": p["crew"]["session_id"],
                         "body": p["aps"]["alert"]["body"]} for p in sent]
    print("RESULT " + json.dumps(result))


main()
