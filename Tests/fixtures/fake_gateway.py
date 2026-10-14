import asyncio
import json
import os
import sys
import threading
import time
import uuid
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

from websockets.asyncio.server import serve

WS_PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8800
HTTP_PORT = int(sys.argv[2]) if len(sys.argv) > 2 else 8801
MODE = sys.argv[3] if len(sys.argv) > 3 else "normal"

tickets = set()
tickets_lock = threading.Lock()
connections = 0
busy_until = time.time() + 12


class Http(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path != "/api/auth/ws-ticket":
            self.send_response(404)
            self.end_headers()
            return
        if MODE == "signedout":
            self.send_response(401)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(b'{"error":"session_expired"}')
            return
        ticket = uuid.uuid4().hex
        with tickets_lock:
            tickets.add(ticket)
        body = json.dumps({"ticket": ticket, "ttl_seconds": 30}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


def consume(ticket):
    with tickets_lock:
        if ticket in tickets:
            tickets.remove(ticket)
            return True
    return False


def process_request(connection, request):
    query = parse_qs(urlparse(request.path).query)
    protocols = [p.strip() for p in request.headers.get("Sec-WebSocket-Protocol", "").split(",") if p.strip()]
    via_protocol = [p[len("hermes-gateway-ticket."):] for p in protocols if p.startswith("hermes-gateway-ticket.")]
    if via_protocol:
        ticket = via_protocol[0]
        print(f"upgrade with subprotocol ticket, protocols={protocols}", flush=True)
    else:
        ticket = query.get("ticket", [""])[0]
        print(f"upgrade with query ticket", flush=True)
        if MODE == "reject-query":
            consume(ticket)
            print("rejecting query ticket with 403", flush=True)
            return connection.respond(HTTPStatus.FORBIDDEN, "query tickets disabled\n")
    if not urlparse(request.path).path == "/api/ws" or not consume(ticket):
        print("bad ticket -> 403", flush=True)
        return connection.respond(HTTPStatus.FORBIDDEN, "bad ticket\n")
    return None


def select_subprotocol(connection, subprotocols):
    return "hermes-gateway-v1" if "hermes-gateway-v1" in subprotocols else None


ROSTER = {
    "profiles": [
        {"name": "default", "path": "/x", "is_default": True, "model": "claude-opus-4-5", "description": "", "display_name": "",
         "canonical_session": {"id": "s-default", "resolved_id": "s-default", "preview": "Done with the report.", "last_active": time.time() - 60, "message_count": 4},
         "ui_meta_revisions": {}, "ui_meta": None, "has_avatar": False},
        {"name": "ada", "path": "/x", "model": "gpt-5.2", "description": "Research", "display_name": "",
         "canonical_session": {"id": "s-ada", "resolved_id": "s-ada-tip", "preview": "Looking into it", "last_active": time.time() - 3600, "message_count": 9},
         "ui_meta_revisions": {"hermes-bots": 3},
         "ui_meta": {"hermes-bots": {"title": "Ada", "shape": "blob", "color": "#8b5cf6", "custom": True, "expression": "happy", "pinned": True, "created": 1791880000000, "groups": ["g1"], "future_key": {"nested": [1, True, None]}},
                     "other-plugin": "opaque"},
         "has_avatar": True},
        {"name": "scout", "path": "/x", "model": "gpt-5.2", "description": "Web", "display_name": "Scout",
         "canonical_session": {"id": "s-scout", "resolved_id": "s-scout", "preview": "Searching", "last_active": time.time() - 7200, "message_count": 2},
         "ui_meta_revisions": {"hermes-bots": 1},
         "ui_meta": {"hermes-bots": {"sectionId": "sec1", "sectionName": "Work"}}, "has_avatar": False},
        {"name": "ghost", "path": "/x", "description": "", "display_name": "",
         "ui_meta": {"hermes-bots": {"hidden": True}}},
    ],
    "bot_mode_protocol": True,
    "install_id": "fake",
}


PNG = "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAEElEQVR4nGP438AARAwQCgAt7gX9iz9uhAAAAABJRU5ErkJggg=="
CONFLICTS = {"scout": True}


async def chat(ws):
    answered = asyncio.Event()

    async def stream():
        lines = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "chat.tool-turn.v0.21.7.jsonl")).read().splitlines()
        for line in lines:
            event = json.loads(line)
            if "session_id" in event:
                event["session_id"] = "rt-1"
            if event["type"] == "tool.start" and not answered.is_set():
                await ws.send(json.dumps({"jsonrpc": "2.0", "id": "srq-approve1", "method": "approval", "params": {
                    "session_id": "rt-1", "request_id": "r1", "command": "ls", "description": "List files",
                    "choices": ["once", "session", "always", "deny"], "tool_name": "terminal"}}))
                await answered.wait()
            await ws.send(json.dumps({"jsonrpc": "2.0", "method": "event", "params": event}))
            await asyncio.sleep(0.02)

    await ws.send(json.dumps({"jsonrpc": "2.0", "method": "event", "params": {"type": "gateway.ready", "payload": {"change_events": True, "heartbeat": True, "replay_epoch": "epoch-1"}}}))
    async for raw in ws:
        msg = json.loads(raw)
        method, rid = msg.get("method"), msg.get("id")
        if method is None:
            print(f"client reply {json.dumps(msg)}", flush=True)
            answered.set()
            continue
        print(f"<- {method} {json.dumps(msg.get('params'))[:120]}", flush=True)
        results = {
            "gateway.ping": {"ok": True},
            "client.capabilities": {"server_requests": ["approval", "clarify"]},
            "session.list": {"sessions": [{"id": "stored-1", "title": "Bot Chat"}]},
            "session.resume": {"session_id": "rt-1", "stored_session_id": "stored-1", "message_count": 0, "messages": [], "info": {}, "running": False},
            "session.events.since": {"events": [], "latest_seq": 0, "truncated": False, "count": 0, "epoch": "epoch-1", "open_requests": []},
            "prompt.submit": {"status": "streaming"},
        }
        if method not in results:
            await ws.send(json.dumps({"jsonrpc": "2.0", "id": rid, "error": {"code": -32601, "message": f"unknown method {method}"}}))
            continue
        await ws.send(json.dumps({"jsonrpc": "2.0", "id": rid, "result": results[method]}))
        if method == "prompt.submit":
            asyncio.create_task(stream())


async def handler(ws):
    if MODE == "chat":
        return await chat(ws)
    global connections
    connections += 1
    number = connections
    epoch = "epoch-1" if number < 3 else "epoch-2"
    print(f"connection {number} open, epoch {epoch}, subprotocol={ws.subprotocol}", flush=True)
    await ws.send(json.dumps({"jsonrpc": "2.0", "method": "event", "params": {"type": "gateway.ready", "payload": {"skin": {}, "change_events": True, "heartbeat": True, "replay_epoch": epoch}}}))

    async def script():
        await asyncio.sleep(0.5)
        for seq in range(1, 4):
            await ws.send(json.dumps({"jsonrpc": "2.0", "method": "event", "params": {"type": "message.delta", "session_id": "rt1", "seq": seq + 10 * number, "payload": {"text": f"hi{seq}"}}}))
        await ws.send(json.dumps({"jsonrpc": "2.0", "id": "srq-abc123", "method": "approval", "params": {"session_id": "rt-ada", "command": "rm -rf /tmp/x", "choices": ["once", "deny"]}}))
        await asyncio.sleep(2)
        await ws.send(json.dumps({"jsonrpc": "2.0", "method": "event", "params": {"type": "sessions.changed", "session_id": "", "payload": {}}}))
        if MODE == "silent" and number == 1:
            print("going silent", flush=True)
            await asyncio.sleep(3600)
        if number < 3:
            await asyncio.sleep(6)
            print(f"server closing connection {number}", flush=True)
            await ws.close(code=1011, reason="restart")

    task = asyncio.create_task(script())
    try:
        async for raw in ws:
            msg = json.loads(raw)
            method = msg.get("method")
            rid = msg.get("id")
            if method is None:
                print(f"client reply {msg}", flush=True)
                continue
            if MODE == "silent" and number == 1 and method == "gateway.ping":
                print("ignoring ping", flush=True)
                continue
            print(f"<- {method} {json.dumps(msg.get('params'))[:80]}", flush=True)
            if method == "gateway.ping":
                result = {"ok": True}
            elif method == "client.capabilities":
                result = {"server_requests": ["approval", "clarify"], "declines_not_shown": True}
            elif method == "profiles.list":
                result = ROSTER
            elif method == "session.active_list":
                busy = time.time() < busy_until
                result = {"sessions": [
                    {"current": False, "id": "rt-ada", "last_active": time.time(), "message_count": 3, "model": "m", "preview": "", "session_key": "s-ada-tip", "started_at": 0, "status": "waiting" if busy else "idle", "title": "Bot Chat"},
                    {"current": False, "id": "rt-scout", "last_active": time.time(), "message_count": 3, "model": "m", "preview": "", "session_key": "s-scout", "started_at": 0, "status": "working" if busy else "idle", "title": "Bot Chat"},
                ]}
            elif method == "profiles.configure":
                params = msg["params"]
                profile = next(p for p in ROSTER["profiles"] if p["name"] == params["name"])
                revisions = profile.setdefault("ui_meta_revisions", {})
                expected = params.get("ui_meta_expected_revisions", {}).get("hermes-bots")
                actual = revisions.get("hermes-bots", 0)
                if expected != actual or CONFLICTS.pop(params["name"], False):
                    result = {"ok": False, "applied": {"ui_meta": False, "ui_meta_conflicts": {"hermes-bots": {"expected": expected, "actual": actual}}, "ui_meta_revisions": {"hermes-bots": actual}}}
                else:
                    profile["ui_meta"] = {**(profile.get("ui_meta") or {}), **params["ui_meta"]}
                    revisions["hermes-bots"] = actual + 1
                    result = {"ok": True, "applied": {"ui_meta": True, "ui_meta_revisions": {"hermes-bots": actual + 1}}}
            elif method == "profiles.get_asset":
                found = msg["params"]["name"] == "ada"
                result = {"found": True, "mime": "image/png", "size": len(PNG), "data": "data:image/png;base64," + PNG} if found else {"found": False}
            elif method == "session.events.since":
                last = msg["params"].get("last_seen") or 0
                result = {"events": [{"type": "message.delta", "session_id": "rt1", "seq": last + 1, "payload": {"text": "replayed"}}], "latest_seq": last + 1, "truncated": False, "count": 1, "epoch": epoch,
                          "open_requests": [{"id": "srq-open", "method": "clarify", "params": {"session_id": "rt1", "questions": []}}]}
            else:
                await ws.send(json.dumps({"jsonrpc": "2.0", "id": rid, "error": {"code": -32601, "message": f"unknown method {method}"}}))
                continue
            await ws.send(json.dumps({"jsonrpc": "2.0", "id": rid, "result": result}))
    finally:
        task.cancel()
        print(f"connection {number} closed", flush=True)


async def main():
    threading.Thread(target=ThreadingHTTPServer(("127.0.0.1", HTTP_PORT), Http).serve_forever, daemon=True).start()
    async with serve(handler, "127.0.0.1", WS_PORT, process_request=process_request, select_subprotocol=select_subprotocol, ping_interval=None):
        print(f"fake gateway on ws {WS_PORT} http {HTTP_PORT} mode {MODE}", flush=True)
        await asyncio.Future()


asyncio.run(main())
