import json
import socket
import threading
from pathlib import Path
from typing import Iterator

import h2.config
import h2.connection
import h2.events
import httpx
import pytest

from crew_push import apns, store
from crew_push.hooks import Event, build
from conftest import TOKEN


class H2Server:
    def __init__(self, status: int, body: bytes) -> None:
        self.status, self.body = status, body
        self.requests: list[tuple[dict[str, str], bytes]] = []
        self.sock = socket.create_server(("127.0.0.1", 0))
        self.url = f"http://127.0.0.1:{self.sock.getsockname()[1]}"
        threading.Thread(target=self.serve, daemon=True).start()

    def serve(self) -> None:
        connection, _ = self.sock.accept()
        h2conn = h2.connection.H2Connection(h2.config.H2Configuration(client_side=False, header_encoding="utf-8"))
        h2conn.initiate_connection()
        connection.sendall(h2conn.data_to_send())
        streams: dict[int, tuple[dict[str, str], bytearray]] = {}
        while data := connection.recv(65535):
            for event in h2conn.receive_data(data):
                if isinstance(event, h2.events.RequestReceived):
                    streams[event.stream_id] = (dict(event.headers), bytearray())
                if isinstance(event, h2.events.DataReceived):
                    streams[event.stream_id][1].extend(event.data)
                    h2conn.acknowledge_received_data(event.flow_controlled_length, event.stream_id)
                if isinstance(event, h2.events.StreamEnded):
                    headers, body = streams.pop(event.stream_id)
                    self.requests.append((headers, bytes(body)))
                    h2conn.send_headers(event.stream_id, [(":status", str(self.status)),
                                                          ("content-length", str(len(self.body)))])
                    h2conn.send_data(event.stream_id, self.body, end_stream=True)
            connection.sendall(h2conn.data_to_send())
        connection.close()


@pytest.fixture
def server(request: pytest.FixtureRequest, monkeypatch: pytest.MonkeyPatch) -> Iterator[H2Server]:
    status, body = request.param
    fake = H2Server(status, body)
    monkeypatch.setitem(apns.HOSTS, "sandbox", fake.url)
    client = httpx.Client(http1=False, http2=True, timeout=5)
    monkeypatch.setattr(apns, "_client", client)
    yield fake
    client.close()


def send_one() -> None:
    event = Event("approval", "Atlas", "atlas", "s1", "call-1", "rm -rf build", "Clean the build dir?", "req-1")
    apns.send({"token": TOKEN, "environment": "sandbox"},
              *build(event, {"prefs": store.DEFAULT_PREFS}, install_id="0" * 16, now=0))


@pytest.mark.parametrize("server", [(200, b"")], indirect=True)
def test_push_over_http2(server: H2Server, configured: Path, device) -> None:
    device()
    send_one()
    [(headers, body)] = server.requests
    assert headers[":method"] == "POST"
    assert headers[":path"] == f"/3/device/{TOKEN}"
    assert headers["apns-topic"] == "dev.gustaf.crew"
    assert headers["apns-priority"] == "10"
    assert headers["authorization"].startswith("bearer ")
    assert json.loads(body)["crew"]["request_id"] == "req-1"
    assert len(store.read_devices()) == 1


@pytest.mark.parametrize("server", [(410, b'{"reason":"Unregistered","timestamp":1760000000000}')], indirect=True)
def test_unregistered_over_http2_prunes(server: H2Server, configured: Path, device) -> None:
    device()
    send_one()
    assert store.read_devices() == []
