import json
import secrets
from contextlib import suppress
from typing import Any

SHOPIFY_PCI = "https://checkout.pci.shopifyinc.com"
CARD_FIELDS_BY = {SHOPIFY_PCI: "Card fields by Shopify"}
SLOT = "data-hermes-vault-slot"
VISIBLE_JS = (f"JSON.stringify([...document.querySelectorAll('[{SLOT}]')].filter(el => {{"
              "const r = el.getBoundingClientRect(); return el.tabIndex >= 0 && r.width >= 8 && r.height >= 8; })"
              f".map(el => Number(el.getAttribute('{SLOT}').split(':')[1])))")
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


def attach_card_frames(cdp: Any, top_id: str, sessions: list[str]) -> None:
    targets = cdp.call("Target.getTargets")["result"]["targetInfos"]
    for target in targets:
        if target.get("type") != "iframe" or not str(target.get("url") or "").startswith(f"{SHOPIFY_PCI}/"):
            continue
        attached = cdp.call("Target.attachToTarget", {"targetId": target["targetId"], "flatten": True})
        session_id = attached["result"]["sessionId"]
        sessions.append(session_id)
        frame = top_frame(cdp, session_id)
        if frame.get("parentId") != top_id or frame.get("securityOrigin") != SHOPIFY_PCI:
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


def type_into(cdp: Any, session_id: str, nonce: str, fill: dict[str, Any]) -> None:
    from tools.browser_vault_tool import _bot_desktop_browser_session

    if _bot_desktop_browser_session(cdp.task_id):
        from tools.bot_desktop import lease

        try:
            lease.assert_agent_may_act()
        except lease.HumanHasControl:
            raise FrameFillError("human_has_control") from None
    focused = evaluate(cdp, session_id, slot_js(nonce, fill["index"], FOCUS))
    if focused != "ok":
        raise FrameFillError("origin_changed" if focused == "origin" else "error")
    # Shopify's expiry field formats bare MMYY digits itself; a typed slash is rejected as invalid.
    text = fill["value"].replace("/", "") if fill["token"] == "cc-exp" else fill["value"]
    cdp.call("Input.insertText", {"text": text}, session_id=session_id)
    shown = "el.value.length" if fill["token"] == "cc-name" else "el.value.replace(/[^0-9]/g, '').length"
    landed = slot_js(nonce, fill["index"], f"return {shown} === {len(text)} ? 'ok' : 'short';")
    if evaluate(cdp, session_id, landed) != "ok":
        raise FrameFillError("error")


def fill(task_id: str, origin: str, secret: dict[str, Any]) -> list[str]:
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
    nonce = secrets.token_hex(8)
    sessions: list[str] = []
    filled: list[str] = []
    try:
        attach_card_frames(cdp, str(top.get("id") or ""), sessions)
        fills = plan(cdp, sessions, nonce, secret)
        for value in page_values(secret):
            register_vault_redaction_value(value)
        for session_id, planned in fills:
            try:
                type_into(cdp, session_id, nonce, planned)
            except FrameFillError as error:
                raise FrameFillError(error.code, tuple(filled)) from None
            filled.append(planned["token"])
        return sorted(filled)
    finally:
        for session_id in sessions:
            with suppress(Exception):
                evaluate(cdp, session_id, CLEAR_JS)
                cdp.call("Target.detachFromTarget", {"sessionId": session_id})
