import json
import os
import threading
from pathlib import Path

import httpx
from fastapi import FastAPI
from fastapi.testclient import TestClient

from hermes_cli import lifecycle
from hermes_cli.plugins import get_plugin_manager
from hermes_cli.web_server_dashboard import _discover_dashboard_plugins, _mount_one_plugin_api
from hermes_constants import set_hermes_home_override
from hermes_state import SessionDB

HOOKS = ("pre_llm_call", "post_llm_call", "on_session_end", "pre_tool_call", "post_tool_call", "pre_approval_request",
         "post_approval_response", "transform_tool_result", "subagent_start")
TOKEN = "ab" * 32
CARD = {"card_number": "4242424242424242", "exp_month": "12", "exp_year": "2030", "cvc": "123"}
DETAILS = {"amount": "499 kr", "merchant": "Zalando", "reason": "Winter boots, size 43"}


def bot_chat(home: Path, session_id: str) -> None:
    db = SessionDB(db_path=home / "state.db")
    db.create_session(session_id, "tui")
    db.set_session_title(session_id, "Bot Chat")
    db.close()


def turn(session_id: str, platform: str = "tui") -> None:
    lifecycle.invoke_hook("pre_llm_call", session_id=session_id, platform=platform, user_message="hi")
    lifecycle.invoke_hook("post_llm_call", session_id=session_id, assistant_response="**Done.**")
    lifecycle.invoke_hook("on_session_end", session_id=session_id, turn_id="t1", completed=True, failed=False,
                          interrupted=False, platform=platform)


class CheckoutTab:
    def focus_page(self, origin: str, *, accept: str | None = None, timeout: float = 10.0) -> dict[str, object]:
        return {"ok": True, "url": f"{origin}/checkout"} if origin == "https://www.zalando.se" else {"ok": False}


def pay(home: Path, handle: str, sent: list[dict[str, object]]) -> dict[str, object]:
    from hermes_cli.plugins import _dispatch_pre_tool_call_hooks
    from tools.approval import list_gateway_approvals, resolve_gateway_approval
    from tools.approval_context import set_current_observability_context, set_current_session_key
    from tools.approval_gateway_wait import _await_gateway_decision
    from tools.browser_supervisor import SUPERVISOR_REGISTRY

    from crew_push import store

    key, call = "agent:main:crew:dm", "call_pay_1"
    args = {"action": "fill", "handle": handle, **DETAILS}
    asked = threading.Event()
    outcome: dict[str, object] = {}

    def agent_thread() -> None:
        set_current_session_key(key)
        set_current_observability_context(tool_call_id=call, session_id="launch-session")
        ids = {"task_id": "default", "session_id": "launch-session", "tool_call_id": call}
        outcome["gate_off"] = _dispatch_pre_tool_call_hooks("browser_vault", args, **ids)[0]
        store.write_gate(True)
        outcome["blocked"] = _dispatch_pre_tool_call_hooks("browser_vault", {**args, "amount": ""}, **ids)[0]
        outcome["no_page"] = _dispatch_pre_tool_call_hooks("browser_vault", args, **ids)[0]
        with SUPERVISOR_REGISTRY._lock:
            SUPERVISOR_REGISTRY._by_task["default"] = CheckoutTab()
        outcome["allowed"] = _dispatch_pre_tool_call_hooks("browser_vault", args, **ids)[0]
        label = next(i.label for i in VaultStore(home / "vault").list_items() if i.id == handle)
        command = f"Fill payment card '{label}' on https://www.zalando.se"
        outcome["decision"] = _await_gateway_decision(key, lambda data: asked.set(), {
            "command": command, "description": "Confirm", "pattern_key": "mcp_elicitation",
            "pattern_keys": ["mcp_elicitation"]}, surface="vault-payment")
        raw = json.dumps({"success": True, "filled_fields": 5, "backend": "local", "kind": "payment",
                          "origin": "https://www.zalando.se", "fields": ["cc-csc", "cc-number"]})
        outcome["result"] = json.loads(next(r for r in lifecycle.invoke_hook(
            "transform_tool_result", tool_name="browser_vault", args=args, result=raw, **ids) if isinstance(r, str)))

    from agent.vault_store import VaultStore

    thread = threading.Thread(target=agent_thread)
    thread.start()
    asked.wait(30)
    [pending] = list_gateway_approvals(key)
    outcome["resolved"] = resolve_gateway_approval(key, "once", request_id=pending["request_id"])
    thread.join(30)
    from crew_push import apns

    apns._queue.join()
    [entry] = store.read_list("payments.json")
    return {"gate_off": json.loads(outcome["gate_off"])["error_type"],
            "blocked": json.loads(outcome["blocked"])["error_type"],
            "no_page": json.loads(outcome["no_page"])["error_type"], "allowed": outcome["allowed"],
            "request_id_matches": entry["request_id"] == pending["request_id"], "state": entry["state"],
            "fill": entry["fill"], "crew_payment": outcome["result"]["crew_payment"]["state"],
            "kinds": [p["crew"]["kind"] for p in sent]}


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
    home = Path(os.environ["HERMES_HOME"])
    bot_chat(home, "launch-session")
    turn("api-session", platform="api_server")
    turn("launch-session")
    beta = home / "profiles" / "beta"
    bot_chat(beta, "beta-session")
    set_hermes_home_override(beta)
    beta_manager = get_plugin_manager()
    result["beta_is_separate_manager"] = beta_manager is not manager
    result["beta_own_callbacks"] = len(beta_manager.iter_hook_callbacks("on_session_end"))
    turn("beta-session")
    apns._queue.join()
    result["pushes"] = [{"profile": p["crew"]["profile"], "session_id": p["crew"]["session_id"],
                         "body": p["aps"]["alert"]["body"]} for p in sent]

    set_hermes_home_override(home)
    sent.clear()
    from agent.vault_store import VaultStore

    VaultStore(home / "vault").add_item(kind="payment", label="Shopping card", secret=CARD)
    created = client.post("/api/plugins/crew-push/payments/shops",
                          json={"profile": "default", "site": "https://www.zalando.se/checkout"})
    listed = client.get("/api/plugins/crew-push/payments", params={"bot": "default"}).json()
    copy = next(i for i in VaultStore(home / "vault").list_items() if i.origin)
    result["shop"] = {"status": created.status_code, "card": listed["card"], "hosts": [s["host"] for s in listed["shops"]],
                      "label": copy.label, "same_secret": VaultStore(home / "vault").resolve_secret(copy.id) == CARD,
                      "gate": listed["gate"]}
    result["pay"] = pay(home, copy.id, sent)

    result["card_gate_off"] = client.put("/api/plugins/crew-push/payments/card", json={**CARD, "label": "x"}).status_code
    app.state.auth_required = True
    replaced = client.put("/api/plugins/crew-push/payments/card", json={
        "card_number": "4000 0566 5566 5556", "exp_month": "3", "exp_year": "31", "cvc": "321", "label": "Travel card"})
    vault, card_vault = VaultStore(home / "vault"), VaultStore(home / "vault" / "crew-push")
    masters = [item for item in card_vault.list_items() if item.kind == "payment" and not item.origin]
    updated = client.post("/api/plugins/crew-push/payments/shops/update", json={"profile": "default"})
    shops = [item for item in vault.list_items() if item.origin]
    result["card"] = {"status": replaced.status_code, "body": replaced.json(),
                      "masters": [(item.label, item.origin) for item in masters],
                      "secret": card_vault.resolve_secret(masters[0].id) if len(masters) == 1 else None,
                      "left_in_default": [item.label for item in vault.list_items() if not item.origin],
                      "update": updated.status_code, "shop_labels": [item.label for item in shops],
                      "files": {name: oct((home / "vault" / "crew-push" / name).stat().st_mode & 0o777) for name in ("vault.key", "vault.json.enc")}}
    app.state.auth_required = False

    from hermes_cli.web_server import app as dashboard

    _mount_one_plugin_api(dashboard, plugin, {"crew-push"}, set())
    anonymous = TestClient(dashboard, base_url="http://127.0.0.1")
    result["anonymous"] = {path: anonymous.request(method, f"/api/plugins/crew-push/{path}").status_code
                           for method, path in (("GET", "status"), ("GET", "payments?bot=default"),
                                                ("POST", "payments/shops"), ("GET", f"payments/requests/{'0' * 32}"),
                                                ("PUT", "payments/card"), ("POST", "payments/shops/update"))}
    print("RESULT " + json.dumps(result))


main()
