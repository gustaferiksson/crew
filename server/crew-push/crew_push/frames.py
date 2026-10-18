import json
import secrets
import time
from contextlib import suppress
from typing import Any, Callable

SHOPIFY_PCI = "https://checkout.pci.shopifyinc.com"
CARD_FIELDS_BY = {SHOPIFY_PCI: "Card fields by Shopify"}
SLOT = "data-hermes-vault-slot"
ORDER = ("cc-number", "cc-exp", "cc-exp-month", "cc-exp-year", "cc-csc", "cc-name")
SETTLE_SECONDS = 1.5
VISIBLE_JS = (f"JSON.stringify([...document.querySelectorAll('[{SLOT}]')].filter(el => {{"
              "const r = el.getBoundingClientRect(); return el.tabIndex >= 0 && r.width >= 8 && r.height >= 8; })"
              f".map(el => Number(el.getAttribute('{SLOT}').split(':')[1])))")
SHOWN_FN = ("function () { const r = this.getBoundingClientRect(); return this.isConnected && r.width >= 8 && "
            "r.height >= 8 && (!this.checkVisibility || this.checkVisibility({opacityProperty: true, "
            "visibilityProperty: true})); }")
CLEAR_JS = f"document.querySelectorAll('[{SLOT}]').forEach(n => n.removeAttribute('{SLOT}')); 0"


class FrameFillError(RuntimeError):
    def __init__(self, code: str, filled: tuple[str, ...] = ()) -> None:
        super().__init__(code)
        self.code = code
        self.filled = filled


FOCUS = "el.focus(); if (document.activeElement !== el || !document.hasFocus()) return 'focus'; el.select(); return 'ok';"


def slot_js(nonce: str, index: int, body: str) -> str:
    target = json.dumps(f'[{SLOT}="{nonce}:{index}"]')
    return (f"(() => {{ if (location.origin !== {json.dumps(SHOPIFY_PCI)}) return 'origin'; "
            f"const el = document.querySelector({target}); if (!el) return 'gone'; {body} }})()")


def evaluate(cdp: Any, session_id: str, expression: str) -> Any:
    reply = cdp.call("Runtime.evaluate", {"expression": expression, "returnByValue": True, "userGesture": True},
                     session_id=session_id)
    result = reply.get("result") or {}
    if result.get("exceptionDetails"):
        raise FrameFillError("eval_failed")
    return (result.get("result") or {}).get("value")


def top_frame(cdp: Any, session_id: str) -> dict[str, Any]:
    return cdp.call("Page.getFrameTree", session_id=session_id)["result"]["frameTree"]["frame"]


def page_values(secret: dict[str, Any]) -> list[str]:
    number = str(secret.get("card_number") or "")
    month, year = str(secret.get("exp_month") or "").zfill(2), str(secret.get("exp_year") or "")[-2:]
    grouped = " ".join(number[i:i + 4] for i in range(0, len(number), 4))
    amex = f"{number[:4]} {number[4:10]} {number[10:]}"
    return [str(value) for value in secret.values() if value] + [grouped, amex, f"{month}{year}", f"{month}/{year}",
                                                                 f"{month} / {year}"]


def owner_shown(cdp: Any, frame_id: str) -> bool:
    page = cdp.page_session_id
    node = cdp.call("DOM.getFrameOwner", {"frameId": frame_id}, session_id=page)["result"]["backendNodeId"]
    owner = cdp.call("DOM.resolveNode", {"backendNodeId": node}, session_id=page)["result"]["object"]["objectId"]
    try:
        reply = cdp.call("Runtime.callFunctionOn", {"objectId": owner, "functionDeclaration": SHOWN_FN,
                                                    "returnByValue": True}, session_id=page)
        return ((reply.get("result") or {}).get("result") or {}).get("value") is True
    finally:
        with suppress(Exception):
            cdp.call("Runtime.releaseObject", {"objectId": owner}, session_id=page)


def attach_card_frames(cdp: Any, top_id: str, sessions: list[str], seen: dict[str, dict[str, Any]]) -> None:
    targets = cdp.call("Target.getTargets")["result"]["targetInfos"]
    for target in targets:
        url = str(target.get("url") or "")
        if target.get("type") != "iframe" or not url.startswith(f"{SHOPIFY_PCI}/"):
            continue
        attached = cdp.call("Target.attachToTarget", {"targetId": target["targetId"], "flatten": True})
        session_id = attached["result"]["sessionId"]
        sessions.append(session_id)
        frame = top_frame(cdp, session_id)
        own = frame.get("parentId") == top_id and frame.get("securityOrigin") == SHOPIFY_PCI
        shown = own and owner_shown(cdp, str(frame.get("id") or ""))
        seen[session_id] = {"page": url.split("?")[0].rsplit("/", 1)[-1], "own_frame": own, "shown": shown}
        if not shown:
            sessions.remove(session_id)
            cdp.call("Target.detachFromTarget", {"sessionId": session_id})


def plan(cdp: Any, sessions: list[str], nonce: str, secret: dict[str, Any]) -> list[tuple[str, dict[str, Any]]]:
    from agent.vault_login_classifier import (LoginControl, build_inspection_js, classify_checkout_control,
                                              select_checkout_fills)
    from agent.vault_store import PAYMENT_FIELDS

    fills: dict[str, tuple[str, dict[str, Any]]] = {}
    for session_id in sessions:
        controls = json.loads(evaluate(cdp, session_id, build_inspection_js(nonce)) or "[]")
        visible = set(json.loads(evaluate(cdp, session_id, VISIBLE_JS) or "[]"))
        shown = [raw for raw in controls if isinstance(raw, dict) and raw.get("index") in visible]
        classified = [control for control in map(classify_checkout_control, map(LoginControl.from_dict, shown))
                      if control is not None]
        for fill in select_checkout_fills(classified, secret, PAYMENT_FIELDS):
            fills.setdefault(fill["token"], (session_id, fill))
    if "cc-exp" in fills:
        fills = {token: fill for token, fill in fills.items() if token not in ("cc-exp-month", "cc-exp-year")}
    wanted = {token for name, token in (("card_number", "cc-number"), ("cvc", "cc-csc"), ("cardholder_name", "cc-name"))
              if secret.get(name)}
    expiry = "cc-exp" in fills or {"cc-exp-month", "cc-exp-year"} <= fills.keys()
    if not wanted <= fills.keys() or (secret.get("exp_month") and not expiry):
        raise FrameFillError("no_fields")
    return list(fills.values())


def typed_text(fill: dict[str, Any]) -> str:
    # Shopify's expiry field formats bare MMYY digits itself; a typed slash is rejected as invalid.
    return fill["value"].replace("/", "") if fill["token"] == "cc-exp" else fill["value"]


def landed_js(nonce: str, fill: dict[str, Any]) -> str:
    shown = "el.value.length" if fill["token"] == "cc-name" else "el.value.replace(/[^0-9]/g, '').length"
    return slot_js(nonce, fill["index"], f"return {shown} === {len(typed_text(fill))} ? 'ok' : 'short';")


def type_into(cdp: Any, session_id: str, nonce: str, fill: dict[str, Any]) -> bool:
    from tools.browser_vault_tool import _bot_desktop_browser_session

    if _bot_desktop_browser_session(cdp.task_id):
        from tools.bot_desktop import lease

        try:
            lease.assert_agent_may_act()
        except lease.HumanHasControl:
            raise FrameFillError("human_has_control", ("typing",)) from None
    focused = evaluate(cdp, session_id, slot_js(nonce, fill["index"], FOCUS))
    if focused != "ok":
        raise FrameFillError("origin_changed" if focused == "origin" else "error", ("typing",))
    cdp.call("Input.insertText", {"text": typed_text(fill)}, session_id=session_id)
    if evaluate(cdp, session_id, landed_js(nonce, fill)) != "ok":
        raise FrameFillError("error", ("typing",))
    return True


def is_missing(cdp: Any, session_id: str, nonce: str, fill: dict[str, Any]) -> bool:
    return evaluate(cdp, session_id, landed_js(nonce, fill)) != "ok"


def frame_pass(cdp: Any, top_id: str, secret: dict[str, Any], tokens: set[str],
               step: Callable[[Any, str, str, dict[str, Any]], bool], report: list[dict[str, Any]]) -> list[str]:
    nonce = secrets.token_hex(8)
    sessions: list[str] = []
    seen: dict[str, dict[str, Any]] = {}
    try:
        attach_card_frames(cdp, top_id, sessions, seen)
        fills = sorted(plan(cdp, sessions, nonce, secret), key=lambda planned: ORDER.index(planned[1]["token"]))
        for session_id, fill in fills:
            if fill["token"] in tokens:
                seen[session_id].update(token=fill["token"], result=step(cdp, session_id, nonce, fill))
        return [frame["token"] for frame in seen.values() if frame.get("result")]
    finally:
        report.append({"pass": step.__name__, "frames": list(seen.values())})
        for session_id in sessions:
            with suppress(Exception):
                evaluate(cdp, session_id, CLEAR_JS)
                cdp.call("Target.detachFromTarget", {"sessionId": session_id})


def fill(task_id: str, origin: str, secret: dict[str, Any], report: list[dict[str, Any]]) -> list[str]:
    from agent.redact import register_vault_redaction_value
    from agent.vault_store import normalize_origin
    from tools.browser_supervisor import SUPERVISOR_REGISTRY
    from tools.browser_vault_tool import _focus_bound_origin

    if not _focus_bound_origin(task_id, origin, "payment"):
        raise FrameFillError("origin_mismatch")
    cdp = SUPERVISOR_REGISTRY.capture(task_id)
    top = top_frame(cdp, cdp.page_session_id)
    if normalize_origin(str(top.get("url") or "")) != origin:
        raise FrameFillError("origin_changed")
    top_id = str(top.get("id") or "")
    for value in page_values(secret):
        register_vault_redaction_value(value)
    filled = frame_pass(cdp, top_id, secret, set(ORDER), type_into, report)
    try:
        time.sleep(SETTLE_SECONDS)
        missing = frame_pass(cdp, top_id, secret, set(filled), is_missing, report)
        if missing:
            frame_pass(cdp, top_id, secret, set(missing), type_into, report)
            time.sleep(SETTLE_SECONDS)
            missing = frame_pass(cdp, top_id, secret, set(filled), is_missing, report)
    except FrameFillError as error:
        raise FrameFillError(error.code, error.filled or ("typed",)) from None
    if missing:
        raise FrameFillError("not_kept", tuple(missing))
    return sorted(filled)
